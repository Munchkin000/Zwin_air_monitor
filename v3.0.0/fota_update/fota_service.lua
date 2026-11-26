-- 通过合宙 libfota3 更新 Air1603。状态独立于页面，切页期间下载可以继续。
local M = {}
local current = { phase = "idle", message = "打开页面后可以检查更新", device_id = "未读取" }
local started, library
local pending_reboot, network_timer

-- 设置页只读取展示状态，项目 Key 由升级服务内部管理。
function M.snapshot()
    return { phase = current.phase, message = current.message, device_id = current.device_id }
end

local function update(phase, message)
    if current.phase == phase and current.message == message then return end
    current.phase, current.message = phase, message
    sys.publish("APP_FOTA_CHANGED")
end

local function on_status(status, message, percent)
    if status == "network_fail" then
        -- 库每秒报告一次网卡未就绪，满 60 秒后退出且不另发结束回调。
        if not network_timer and (current.phase == "checking" or current.phase == "downloading") then
            log.warn("upgrade", "FOTA3_STATUS", status)
            update(current.phase, "等待 4G 恢复连接")
            network_timer = sys.timerStart(function()
                network_timer = nil
                update("idle", "等待 4G 超时 · 请重新检查")
            end, 65000)
        end
        return
    end
    if network_timer then
        sys.timerStop(network_timer)
        network_timer = nil
    end

    if status == "downloading" then
        -- 官方库只在整数百分比变化时回调，直接显示库提供的进度和已下载容量。
        if type(percent) == "number" then
            log.info("upgrade", "FOTA3_PROGRESS", percent, message or "-")
            if percent >= 100 then
                update("downloading", "下载 100% · 正在校验并写入")
            else
                update("downloading", message or string.format("正在下载更新 %d%%", percent))
            end
        end
        return
    end

    log.info("upgrade", "FOTA3_STATUS", status, message or "-")
    if status == "new_version" then
        update("checking", message or "发现新版本")
    elseif status == "download_start" then
        update("downloading", "正在下载更新 · 等待接收数据")
    elseif status == "download_fail" then
        -- HTTP -8 是下载超时，显示可直接理解的原因。结束后可手动重新检查。
        if message == "下载失败(-8)" then message = "升级包下载超时 · 请检查 4G 后重试" end
        update("idle", message or "下载失败 · 请查看串口日志")
    elseif status == "check_fail" or status == "no_new_version" then
        update("idle", message or "未取得可用升级包 · 请查看串口日志")
    elseif status == "rebooting" then
        update("rebooting", "正在重启并应用更新")
    end
end

local function on_confirm(action, _, confirm)
    if action == "download" then
        -- 现场人员点击「检查更新」后，允许官方库下载、校验并写入升级包。
        -- 开始传输前发布状态，让上报任务关闭业务连接，避免在下载期间重连。
        update("downloading", "正在连接下载服务器")
        confirm(true)
    elseif action == "reboot" then
        -- 官方库完成写入后等待确认。页面离开时也保留回调，返回后可以继续操作。
        pending_reboot = confirm
        update("ready", "升级包已就绪 · 点击重启应用")
    else
        confirm(false)
    end
end

function M.start(is_pc)
    if started then return end
    started = true
    if is_pc then
        update("unavailable", "PC 仿真 · 请在真机检查更新")
        return
    end

    -- 与 libfota3 一样，使用 hmeta.devid() 返回的 Air1603 主控标识。
    local read_id, device_id = pcall(function() return hmeta.devid() end)
    if not read_id or type(device_id) ~= "string" or device_id == "" then
        update("unavailable", "读取主控设备标识失败")
        return
    end
    current.device_id = device_id
    log.info("upgrade", "FOTA_DEVICE_ID", device_id)

    local loaded, config = pcall(function() return require("fota_project") end)
    if not loaded or type(config) ~= "table" or type(config.project_key) ~= "string"
        or not config.project_key:match("^[%w._~%-]+$") then
        update("unavailable", "未配置合宙 IoT 项目 Key")
        return
    end
    if not (http and http.request and fota and fota.init and fota.wait and fota.file
        and fota.isDone and fota.finish and rtos and rtos.reboot) then
        update("unavailable", "当前核心固件缺少远程升级接口")
        return
    end

    local ok, lib = pcall(function() return require("libfota3") end)
    if not ok or type(lib) ~= "table" or type(lib.config) ~= "function"
        or type(lib.check_update) ~= "function" then
        log.error("upgrade", "FOTA3_LIB_UNAVAILABLE")
        update("unavailable", "未加载 libfota3 · 请检查烧录文件")
        return
    end

    -- 使用已上板验证的库版本 202610201700。config 装载手动检查参数，
    -- 避免 request() 的异步校时占用手动检查流程。开机结果仍由官方库上报。
    local configured = pcall(lib.config, {
        project_key = config.project_key,
        script_name = PROJECT,
        script_version = VERSION,
        auto = false,
        on_status = on_status,
        on_confirm = on_confirm,
    })
    if not configured then
        log.error("upgrade", "FOTA3_CONFIG_FAILED")
        update("unavailable", "初始化 libfota3 失败 · 请查看串口日志")
        return
    end
    library = lib
    log.info("upgrade", "FOTA3_READY", PROJECT, VERSION, type(lib.version) == "function" and lib.version() or "-")
    update("idle", "点击检查更新获取平台发布的升级包")
end

-- 官方库经默认网卡访问平台。AirLink 启动后会将 4G 桥接网卡设为默认。
function M.check(connection)
    if current.phase ~= "idle" or not library then return end
    local adapter = connection.adapter
    if not (connection.ready and adapter and socket and socket.dft and socket.adapter
        and socket.dft() == adapter and socket.adapter(adapter)) then
        update("idle", "4G 尚未就绪 · 请检查网络设置")
        return
    end

    update("checking", "正在检查更新")
    log.info("upgrade", "FOTA3_REQUEST", PROJECT, VERSION, current.device_id, adapter)
    if not pcall(library.check_update) then
        log.error("upgrade", "FOTA3_CHECK_TASK_FAILED")
        update("idle", "启动更新失败 · 请查看串口日志")
    end
end

-- 确认后由官方库重启，应用升级并在下次开机上报结果。
function M.reboot()
    if current.phase ~= "ready" or not pending_reboot then return end
    local confirm = pending_reboot
    pending_reboot = nil
    update("rebooting", "正在重启并应用更新")
    confirm(true)
end

return M
