-- 保存设置偏好。仿真和真机都可通过 FSKV 读取同一套字段。
local serial_config = require("modbus_serial_cfg")
local M = {}
-- FSKV存储里面使用的key名称，整套设置存为一条记录
local key = "air_monitor_settings"
-- 设置项内存默认值：4G开关、屏幕亮度、媒体音量、PC仿真用时钟偏移和 UART1 参数
local current = { cellular_enabled = true, brightness = 82, volume = 64, clock_offset = false,
    modbus_serial = serial_config.defaults() }
local storage_ready = false -- FSKV存储是否初始化就绪标记

-- 校验亮度/音量数值：必须0‑100之间的整数
local function is_level(value)
    return type(value) == "number" and value >= 0 and value <= 100 and value % 1 == 0
end

-- 初始化设置存储，上电调用，从FSKV读取持久化配置覆盖内存默认值
function M.start()
    -- 尝试初始化FSKV，标记存储就绪状态
    storage_ready = fskv and fskv.init() == true
    if not storage_ready then
        log.warn("settings", "设置存储不可用")
        return
    end
    -- 从FSKV读取保存的完整配置表
    local saved = fskv.get(key)
    if type(saved) ~= "table" then return end
    -- 校验并覆盖4G开关配置
    if type(saved.cellular_enabled) == "boolean" then current.cellular_enabled = saved.cellular_enabled end
    -- 校验并覆盖亮度
    if is_level(saved.brightness) then current.brightness = saved.brightness end
    -- 校验并覆盖音量
    if is_level(saved.volume) then current.volume = saved.volume end
    -- 校验时钟偏移：整数，绝对值不能超过约100年秒数，防止异常超大值
    if type(saved.clock_offset) == "number" and saved.clock_offset % 1 == 0
        and math.abs(saved.clock_offset) < 3155760000 then
        current.clock_offset = saved.clock_offset
    end
    -- 兼容旧版本的串口配置，旧记录缺少读取周期时由配置模块补上默认值。
    local serial = serial_config.restore(saved.modbus_serial)
    if serial then current.modbus_serial = serial end
end

-- 获取当前设置快照，返回拷贝副本，防止外部直接修改内部current表
function M.snapshot()
    return { cellular_enabled = current.cellular_enabled, brightness = current.brightness,
        volume = current.volume, clock_offset = current.clock_offset,
        modbus_serial = M.modbus_serial() }
end

-- 轮询任务只需要串口项，返回副本，避免外部修改保存状态。
function M.modbus_serial()
    return serial_config.copy(current.modbus_serial)
end

-- 提交写入：先写Flash，写入成功才更新内存current；写失败内存保持旧值
-- 先确认写入成功，再更新内存。调用方可在页面上提示失败并保留原设置。
local function commit(next_value)
    if not storage_ready or not fskv.set(key, next_value) then
        return false, "保存失败，请检查配置存储"
    end
    current = next_value
    return true
end

-- 设置4G启用偏好开关
function M.set_cellular_enabled(enabled)
    if type(enabled) ~= "boolean" then return false, "无效的 4G 开关状态" end
    local next_value = M.snapshot()
    -- 和当前值一样直接返回，不重复写入Flash
    if enabled == next_value.cellular_enabled then return true end
    next_value.cellular_enabled = enabled
    local ok, err = commit(next_value)
    if ok then
        -- 联网模块订阅偏好变化，AirLink 开关下次启动时应用。连接状态由驱动另行上报。
        -- 发布事件通知其他业务模块：4G用户偏好发生改变
        sys.publish("APP_CELLULAR_PREFERENCE_CHANGED", enabled)
        log.info("settings", "CELLULAR_PREFERENCE", enabled)
    end
    return ok, err
end

-- 同时设置亮度、音量
function M.set_levels(brightness, volume)
    if not is_level(brightness) or not is_level(volume) then return false, "亮度或音量超出范围" end
    local next_value = M.snapshot()
    -- 数值无变化直接返回，避免重复写Flash
    if brightness == next_value.brightness and volume == next_value.volume then return true end
    next_value.brightness, next_value.volume = brightness, volume
    local ok, err = commit(next_value)
    if ok then
        -- 发布事件通知显示/音频模块：亮度音量配置更新
        sys.publish("APP_DISPLAY_SETTINGS_CHANGED", brightness, volume)
        log.info("settings", "DISPLAY_LEVELS", brightness, volume)
    end
    return ok, err
end

-- 先写入 FSKV，保存成功后唤醒采集任务，修改将在两次 RTU 请求之间应用。
function M.set_modbus_serial(values)
    local valid, err = serial_config.validate(values)
    if not valid then return false, err end
    if serial_config.same(values, current.modbus_serial) then return true end
    local next_value = M.snapshot()
    next_value.modbus_serial = serial_config.copy(values)
    local ok, save_err = commit(next_value)
    if ok then
        sys.publish("APP_MODBUS_SERIAL_CHANGED")
        log.info("settings", "MODBUS_SERIAL_SAVED", values.baud, values.data_bits, values.stop_bits,
            values.parity, values.slave, values.interval_ms)
    end
    return ok, save_err
end

-- 设置PC仿真模式的时钟偏移量
function M.set_clock_offset(offset)
    local next_value = M.snapshot()
    -- 偏移没有发生变化，直接返回
    if offset == next_value.clock_offset then return true end
    next_value.clock_offset = offset
    return commit(next_value)
end

return M
