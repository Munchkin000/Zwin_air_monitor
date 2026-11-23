-- Air1603 的合宙 IoT 升级流程，独立于设置页生命周期。
local M = {}
local project_key
local current = { phase = "idle", message = "打开页面后可以检查更新", device_id = "未读取" }
local started, pc

-- 设置页只取得展示状态。项目 Key 留在升级模块内部。
function M.snapshot()
    return { phase = current.phase, message = current.message, device_id = current.device_id }
end

local function update(phase, message)
    current.phase, current.message = phase, message
    sys.publish("APP_FOTA_CHANGED")
end

local function device_identifier()
    -- Air1603 使用主控唯一标识在 IoT 平台绑定设备，保持与出厂固件的标识一致。
    local id = hmeta and hmeta.devid and hmeta.devid()
    if type(id) == "string" and id:match("^%x+$") then return id end
    -- 旧 Air1603 底层可能缺少 hmeta.devid，此时从 MCU 唯一 ID 取得十六进制标识。
    local raw_id = mcu and mcu.unique_id and mcu.unique_id()
    if type(raw_id) == "string" and #raw_id > 0 then return raw_id:toHex() end
end

function M.start(is_pc)
    if started then return end
    started, pc = true, is_pc
    if pc then
        update("unavailable", "PC 仿真 · 请在真机检查更新")
        return
    end

    local device_id = device_identifier()
    current.device_id = device_id or "未读取"
    if device_id then log.info("upgrade", "FOTA_DEVICE_ID", device_id) end

    -- 私有配置只用于真机包。未配置时照常启动主界面，更新入口显示原因。
    local ok, config = pcall(function() return require("fota_project") end)
    if ok and type(config) == "table" and type(config.project_key) == "string"
        and config.project_key:match("^[%w._~%-]+$") then
        project_key = config.project_key
    end
    if not project_key then
        update("unavailable", "未配置合宙 IoT 项目 Key")
    elseif not device_id then
        update("unavailable", "读取主控设备标识失败")
    elseif not (http and http.request and fota and rtos and rtos.reboot) then
        update("unavailable", "当前核心固件缺少远程升级接口")
    else
        update("idle", "点击检查更新获取平台发布的升级包")
    end
end

local platform_messages = {
    [3] = "平台未识别设备 · 请核对升级设备标识",
    [17] = "平台权限不足 · 请核对项目和设备归属",
    [21] = "平台未允许升级 · 请检查设备配置",
    [25] = "平台项目无效 · 请核对项目 Key",
    [26] = "平台未找到对应固件 · 请核对项目名称",
    [27] = "当前没有分配给本机的新版本",
    [40] = "平台暂停本机升级 · 请检查设备升级记录",
    [43] = "平台正在生成升级包 · 请稍后重试",
}

local result_messages = {
    [1] = "无法连接升级服务器",
    [2] = "升级地址错误",
    [3] = "升级连接断开 · 可重新检查",
    [5] = "程序版本格式错误",
}

-- 首次验证由现场人员主动触发。请求和下载直接走主控已就绪的 AirLink 网卡。
function M.check(connection)
    if current.phase ~= "idle" or pc then return end
    if not connection.ready or not connection.adapter then
        update("idle", "4G 尚未就绪 · 请检查网络设置")
        return
    end
    local loaded, library = pcall(function() return require("fota_iot_lib") end)
    if not loaded or type(library) ~= "table" or type(library.request) ~= "function" then
        update("idle", "升级扩展库未加载 · 请检查烧录文件")
        return
    end

    update("checking", "正在检查并下载更新")
    log.info("upgrade", "FOTA_REQUEST", VERSION, connection.adapter)
    local function completed(result, platform_code)
        log.info("upgrade", "FOTA_RESULT", result, platform_code)
        if result == 0 then
            update("ready", "升级包已就绪 · 点击重启应用")
            return
        end
        update("idle", platform_messages[platform_code] or result_messages[result]
            or "未取得可用升级包 · 请查看串口日志")
    end

    -- 每次使用新选项表，避免 libfota2 修改过的请求参数被重复使用。
    local called = pcall(library.request, completed, {
        project_key = project_key, mac = current.device_id, adapter = connection.adapter, timeout = 300000,
    })
    if not called then
        log.error("upgrade", "FOTA_REQUEST_FAILED")
        update("idle", "启动更新失败 · 请核对固件与扩展库")
    end
end

-- 更新包接收并写入成功后，由现场人员确认重启。
function M.reboot()
    if current.phase ~= "ready" then return end
    local timer = sys.timerStart(rtos.reboot, 500)
    if not timer then
        update("ready", "启动重启失败 · 请再试一次")
        return
    end
    update("rebooting", "正在重启并应用更新")
end

return M
