-- PC 和真机共用网络状态快照，主页、设置页和时钟服务按相同接口读取。
local M = {}
local uptime = require("app_uptime")
local AIRLINK_TIMEOUT_MS = 60000 -- 给开机握手留出时间，并过滤短时通信波动。
local peer_unready_since, peer_timeout_reported
-- PC 仿真主状态。真机启动时由 AirLink 驱动接管。
local current = { ready = false, text = "PC 网络 · 待验证", pc = true, host_internet = "外网待验证",
    restart_required = false, link_generation = 0, external_ready = false }
local cellular = {} -- 蜂窝4G状态存储表，硬件模组SIM、运营商、信号等信息
local started = false -- 服务启动标记，防止重复start
local restarting = false -- 等待整机重启时，忽略 4G 复位过程中的网卡波动。

-- 获取网络状态快照
function M.snapshot()
    local status = {}
    for key, value in pairs(cellular) do status[key] = value end
    return { ready = current.ready, text = current.text, pc = current.pc,
        cellular = status, host_internet = current.host_internet, adapter = current.adapter,
        restart_required = current.restart_required, link_generation = current.link_generation,
        external_ready = current.external_ready }
end

local function notify()
    -- 发布 APP_NETWORK_CHANGED，UI 随后调用 snapshot() 刷新网络显示。
    sys.publish("APP_NETWORK_CHANGED")
end

local function start_pc()
    -- PC 仿真通过 ETH0 使用电脑网络，后续按此接口判断连接状态。
    if socket and socket.dft and socket.ETH0 then
        socket.dft(socket.ETH0)
    end
    local function update(ready)
        current.ready = ready
        current.text = ready and "PC 网络 · 已验证" or "PC 网络 · 待验证"
        notify()
    end
    -- IP 就绪与校时成功分别记录。只有实际收到 NTP 应答才显示外网校时成功。
    sys.subscribe("NTP_UPDATE", function(source)
        if source == 1 then return end
        current.host_internet = "已完成网络校时"
        update(true)
    end)
    -- 网卡获取 IP 事件
    sys.subscribe("IP_READY", function(_, adapter)
        if not adapter or adapter == socket.ETH0 then
            if current.host_internet == "网络已断开" then
                current.host_internet = "外网待验证"
            end
            update(true)
        end
    end)
    -- IP_LOSE 代表 IP 丢失或网络断开。
    sys.subscribe("IP_LOSE", function(adapter)
        if not adapter or adapter == socket.ETH0 then
            current.host_internet = "网络已断开"
            update(false)
        end
    end)
end

-- 只有连续轮询到 AirLink 未就绪满 60 秒才记一次故障，恢复后重新计时。
-- IP_LOSE 只说明网卡断开，未提供 AirLink 的对端状态。
local function check_airlink_peer(peer_ready)
    if peer_ready == nil then return end
    if peer_ready then
        if peer_timeout_reported then log.info("cellular", "AIRLINK_PEER_RECOVERED") end
        peer_unready_since, peer_timeout_reported = nil, false
        return
    end

    local now = uptime.ms()
    peer_unready_since = peer_unready_since or now
    if not peer_timeout_reported and now - peer_unready_since >= AIRLINK_TIMEOUT_MS then
        peer_timeout_reported = true
        log.warn("cellular", "AIRLINK_PEER_TIMEOUT", AIRLINK_TIMEOUT_MS)
        sys.publish("APP_RUNTIME_FAULT", "air780", "Air780EX2通信超时（AirLink 连续 60 秒未就绪）")
    end
end

-- 同步串口桥接状态。同一条连接上的定时查询保留已验证的外网结果。
local function update_cellular_link(adapter, ready, ip, link, peer_ready)
    if restarting then return end
    check_airlink_peer(peer_ready)
    if current.ready == ready and cellular.link == link and cellular.ip == ip then return end

    local changed = current.ready ~= ready or cellular.ip ~= ip
    if changed then
        -- 校时结果只适用于发出请求时所在的连接。
        current.link_generation = current.link_generation + 1
        current.external_ready = false
        cellular.internet = ready and "待验证 · 等待网络校时" or "未连接"
        current.text = ready and "4G 桥接 · 外网待验证" or "4G · 未连接"
        log.info("cellular", ready and "CELLULAR_IP_READY" or "CELLULAR_LINK_DOWN", adapter, ip, link)
    end
    if not ready then current.text = "4G · 未连接" end
    current.adapter, current.ready = adapter, ready
    cellular.link, cellular.ip = link, ip
    if changed then sys.publish("APP_CELLULAR_LINK_CHANGED") end
    notify()
end

-- 真机 SNTP 请求显式绑定 4G 网卡。有成功应答才把首页状态更新为外网可达。
function M.report_cellular_sntp(generation, success)
    if current.pc or not current.ready or current.link_generation ~= generation then return end
    current.external_ready = success
    if success then
        cellular.internet = "已验证 · 网络校时成功"
        current.text = "4G · 外网已验证"
        log.info("cellular", "CELLULAR_INTERNET_OK", current.adapter, "SNTP")
    else
        cellular.internet = "本次校时失败 · 等待重试"
        current.text = "4G 桥接 · 外网待验证"
    end
    notify()
end

-- HTTP 有应答也说明能访问外网。保留校时状态，时钟任务会继续重试。
function M.report_cellular_http(generation)
    if not current.ready or current.link_generation ~= generation or current.external_ready then return end
    current.external_ready = true
    cellular.internet = "外网已验证 · 等待网络校时"
    current.text = "4G · 外网已验证"
    log.info("cellular", "CELLULAR_INTERNET_OK", current.adapter, "HTTP")
    notify()
end

local function start_hardware()
    -- Air780EX2 的出厂固件负责蜂窝注册。主控可通过桥接联网，SIM、运营商和射频信息等待对端上报。
    cellular = { sim = "模组未上报", operator = "模组未上报", signal = "模组未上报" }
    local boot_enabled = require("settings_store").snapshot().cellular_enabled
    -- UART AirLink 配置由启动时一次完成。设置保存在 FSKV，下次启动应用，避免运行中反复初始化网卡。
    sys.subscribe("APP_CELLULAR_PREFERENCE_CHANGED", function(enabled)
        current.restart_required = enabled ~= boot_enabled
        notify()
    end)
    current.text = boot_enabled and "4G · 初始化中" or "4G · 已关闭"
    cellular.link = boot_enabled and "正在初始化 AirLink" or "本次启动未启用"
    cellular.internet = "未连接"
    notify()
    if not boot_enabled then
        log.info("cellular", "CELLULAR_DISABLED_AT_BOOT")
        return
    end

    -- 网络失败保留页面运行，具体失败原因由串口日志和设置页显示。
    sys.taskInit(function()
        local called, ok, err = pcall(function()
            return require("cellular_air8603m1").start(update_cellular_link)
        end)
        if called and ok then
            require("cellular_recovery").start(M, function()
                -- 触发硬复位前使旧网卡状态失效。整机启动后由新的网络服务重新计时。
                update_cellular_link(current.adapter, false, nil, "联网超时 · 正在重启设备")
                restarting = true
            end)
            return
        end
        current.text = "4G · 初始化失败"
        cellular.link = "AirLink 初始化失败 · 请查看串口"
        log.error("cellular", "CELLULAR_INIT_FAILED", called and err or ok)
        sys.publish("APP_RUNTIME_FAULT", "air780", "Air780EX2初始化失败（" .. tostring(called and err or ok) .. "）")
        notify()
    end)
end

-- 启动网络状态服务
function M.start(_, is_pc)
    if started then return end
    started, current.pc = true, is_pc
    -- 4G 驱动可发布完整状态快照。缺失项表示未知，避免沿用上一次连接的数据。
    sys.subscribe("APP_CELLULAR_STATUS_DATA", function(status)
        if type(status) ~= "table" then return end
        -- 对端转发实际的 SIM_IND 状态或明确的读取失败时才写故障。
        -- 部分 4G 固件只提供数据桥接，缺失 SIM 状态仅在界面显示为「模组未上报」。
        if not is_pc then
            local reason
            if status.sim_state == "NORDY" then
                reason = "模组上报无卡"
            elseif status.sim_state == "SIM_PIN" then
                reason = "模组上报需要输入 PIN"
            elseif status.sim_error == true then
                reason = "模组上报读取异常"
            end
            if reason then sys.publish("APP_RUNTIME_FAULT", "sim", "SIM卡读取失败（" .. reason .. "）") end
        end
        for _, field in ipairs({ "sim", "operator", "signal" }) do
            cellular[field] = type(status[field]) == "string" and status[field] or
                (not is_pc and "模组未上报" or nil)
        end
        -- PC 测试可注入整组显示状态。真机链路、外网及 IP 由板级驱动管理。
        if is_pc then
            for _, field in ipairs({ "link", "internet", "ip" }) do
                cellular[field] = type(status[field]) == "string" and status[field] or nil
            end
        end
        notify()
    end)
    if is_pc then start_pc() else start_hardware() end
end
return M
