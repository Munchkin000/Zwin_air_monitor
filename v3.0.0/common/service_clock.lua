-- 时钟服务常驻运行，提供主页需要的时间文字和校时状态。
local M = {}
local network = require("service_network") -- 向网络服务读取适配器、回传真机校时结果
local pending_generation -- 发起真机校时请求时的连接编号
local store = require("settings_store") -- 设置持久化存储模块，读写flash保存偏移量
local clock_offset = false     --【PC仿真用】手动时间偏移量，pc下手动改时间不靠RTC，靠时间偏移
local manual_rtc = false       --【硬件板用】标记：是否用户手动修改过硬件RTC实时时钟
local cfg, pc, started, syncing = nil, false, false, false
-- cfg：时间相关配置；pc：是否PC仿真；started：服务是否已经启动；syncing：正在执行NTP校时标记
local synced, last_sync, last_error = false, nil, false
-- synced：NTP是否成功同步过；last_sync：上次NTP成功的时间戳；last_error：NTP校时出错标记
local weekdays = { "星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六" }
-- wday返回1代表周日，刚好数组下标一一对应

-- 仿真手动时间采用应用内偏移，系统自动时钟仍可运行和校时。
function M.local_date()
    local now = os.time() + (clock_offset or 0)
    return os.date("!*t", now + (cfg and cfg.utc_offset or 28800))
    -- `!`代表按 UTC 解析时间戳返回时间 table（year/month/day/hour/min/sec/wday）
end
-- 设置手动时间（传入 UTC 时间戳 epoch）
function M.set_manual_time(epoch)
    if pc then
        local offset = epoch - os.time()
        local ok, err = store.set_clock_offset(offset)
        if not ok then return false, err end
        clock_offset = offset
    else
        -- RTC 接收 UTC 日历字段，用户输入的时区换算由设置页完成。
        local utc = os.date("!*t", epoch)
        if not rtc or not rtc.set or not rtc.set({ year = utc.year, mon = utc.month,
            day = utc.day, hour = utc.hour, min = utc.min, sec = utc.sec }) then
            return false, "设备时钟设置失败"
        end
        manual_rtc = true
        synced = false
    end
    sys.publish("APP_CLOCK_CHANGED")
    log.info("clock", "MANUAL_TIME_SAVED", os.date("!%Y-%m-%d %H:%M:%S", epoch))
    return true
end
-- 切换回自动网络时间，取消手动时间
function M.use_auto_time()
    if pc then -- 清除 flash 里存储的偏移量，`clock_offset=false`，不再叠加偏移，跟随电脑系统时间
        local ok, err = store.set_clock_offset(false)
        if not ok then return false, err end
        clock_offset = false
    else
        manual_rtc = false -- 清除 “手动 RTC” 标记，允许 NTP 校时接管时钟
    end
    sys.publish("APP_CLOCK_CHANGED")
    log.info("clock", "AUTO_TIME_ENABLED")
    return true
end
-- 获取时钟完整状态（UI 页面调用）
function M.snapshot()
    local manual = clock_offset ~= false or manual_rtc
    local valid = manual or os.time() >= 1704067200 -- 未初始化的 RTC 时间不用于自动显示。
    -- `1704067200` ->（2024‑01‑01 00:00:00）
    local date = M.local_date()
    return {
        time = valid and string.format("%02d:%02d", date.hour, date.min) or "--:--",
        seconds = valid and string.format("%02d", date.sec) or "--",
        date = valid and string.format("%04d年%02d月%02d日   %s", date.year, date.month, date.day,
                                      weekdays[date.wday]) or "等待网络校时",
        status = manual and "手动设置时间" or syncing and "正在同步网络时间" or
                 (synced and (last_error and "网络校时重试中 · 时钟运行中" or "网络时间已同步") or
                  (pc and "电脑本地时间 · 等待网络校时" or "等待网络校时")),
        synced = synced and not manual, syncing = syncing and not manual, last_sync = last_sync, valid = valid,
    }
end
-- 启动时钟服务（只能调用一次）
function M.start(config, is_pc)
    if started then return end -- 防止重复启动
    started, cfg, pc = true, config.time, is_pc
    if pc then -- PC上电读取flash保存的时间偏移
        clock_offset = store.snapshot().clock_offset
    end
    if rtc and rtc.timezone then -- RTC强制设置RTC时区为0（UTC）
        rtc.timezone(0)
    end
    -- 订阅 NTP 同步成功事件当`socket.sntp()`完成网络校时，底层抛出`NTP_UPDATE`事件触发回调。
    -- NTP 校时成功后，硬件会自动把时间写入 RTC 芯片。
    sys.subscribe("NTP_UPDATE", function(source)
        -- 真机仅在本服务发出 SNTP 请求期间接收结果，忽略基站授时。
        if not pc and (source == 1 or not syncing) then return end
        manual_rtc = false -- NTP成功后清除硬件手动RTC标记，网络接管时钟
        synced, syncing, last_error, last_sync = true, false, false, os.time()
        sys.publish("APP_CLOCK_CHANGED")
        log.info("clock", "NTP_SYNC_OK", os.date("!%Y-%m-%d %H:%M:%S", last_sync))
        if not pc then network.report_cellular_sntp(pending_generation, true) end
    end)
    -- 每秒通知界面重新读取时间，校时任务独立运行。
    sys.taskInit(function()
        while true do
            sys.publish("APP_CLOCK_CHANGED")
            sys.wait(1000)
        end
    end)
    -- NTP 自动校时协程（重点）
    sys.taskInit(function()
        -- 给 PC 网络栈留出启动时间。PC 校时可以主动尝试，不必等待 IP_READY。
        sys.wait(1500)
        while true do
            -- PC 仿真不需要等待网络就绪；硬件模组要等网络就绪标记。
            local connection = network.snapshot()
            local ready = pc or connection.ready
            if ready and socket and socket.sntp then
                syncing = true
                sys.publish("APP_CLOCK_CHANGED")
                -- 等待校时完成事件。超时后继续使用现有时钟，下一次按失败间隔重试。
                -- PC 保持默认适配器。真机绑定到 AirLink 网卡，避免用其他网卡的结果标记 4G。
                pending_generation = connection.link_generation
                if not pc then log.info("clock", "NTP_REQUEST", connection.adapter, cfg.servers[1]) end
                local requested, result = pcall(socket.sntp, pc and cfg.pc_servers or cfg.servers, connection.adapter)
                if requested and result ~= false and syncing then
                    -- 阻塞等待校时成功事件，最多等待`cfg.sync_timeout_ms`
                    sys.waitUntil("NTP_UPDATE", cfg.sync_timeout_ms)
                end
                if syncing then
                    syncing, last_error = false, true
                    if not pc then network.report_cellular_sntp(pending_generation, false) end
                    sys.publish("APP_CLOCK_CHANGED")
                    log.warn("clock", "NTP unavailable; keeping current clock, will retry")
                end
                -- 上电初期模组可能仍在注册，真机失败后缩短等待时间，便于现场复测。
                local retry = pc and cfg.retry_interval_ms or cfg.hardware_retry_interval_ms
                local delay = last_error and retry or cfg.sync_interval_ms
                if pc then
                    sys.wait(delay)
                elseif network.snapshot().link_generation == pending_generation then
                    -- 4G 复位或重新取得 IP 时提前校时，避免等待上一次连接的长周期。
                    sys.waitUntil("APP_CELLULAR_LINK_CHANGED", delay)
                end
            else
                sys.wait(1000)
            end
        end
    end)
end

return M
