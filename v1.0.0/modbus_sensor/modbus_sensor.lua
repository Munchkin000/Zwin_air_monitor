-- 传感器轮询服务。当前采用 SC-TH1001 配置，读数发布到环境数据缓存。
local rtu = require("modbus_rtu")
local profile = require("modbus_profile")
local serial_config = require("modbus_serial_cfg")
local settings = require("settings_store")
local M = {}
local started = false

-- 将 RTU 寄存器换算为环境页面使用的物理量。温度负数按 16 位补码解析。
function M.decode(registers, fields)
    local values = {}
    for _, field in ipairs(fields) do
        local raw = registers[field.offset + 1]
        if type(raw) ~= "number" then return nil, "MISSING_REGISTER_" .. field.id end
        if field.signed and raw >= 0x8000 then raw = raw - 0x10000 end
        -- SC-TH1001 把物理量放大十倍保存，除以配置值还原。
        local value = raw / field.divisor
        if value < field.min or value > field.max then return nil, "OUT_OF_RANGE_" .. field.id end
        values[field.id] = value
    end
    return values
end

-- 站号属于当前请求，UART 的物理引脚仍从板级传感器配置读取。
local function open_port(config)
    local serial, request = {}, {}
    for key, value in pairs(profile.serial) do serial[key] = value end
    for _, field in ipairs(serial_config.fields) do serial[field.key] = config[field.key] end
    for key, value in pairs(profile.request) do request[key] = value end
    request.slave = config.slave

    local bus, err = rtu.open(serial)
    if bus then
        log.info("modbus_sensor", "SENSOR_STARTED", profile.name, "UART" .. serial.port, serial.baud,
            request.slave, "RS485_AUTO_DE", serial.de_pin, serial.data_bits, serial.stop_bits, serial.parity)
    else
        log.error("modbus_sensor", "SENSOR_INIT_FAILED", profile.name, err)
    end
    return bus, request
end

function M.start()
    if started then return end
    started = true
    local metric_ids = {}
    for index, field in ipairs(profile.fields) do metric_ids[index] = field.id end
    -- 开机后先清掉真实采集项目的演示数据，收到首帧前显示待采集。
    require("env_store"):invalidate(metric_ids)

    sys.taskInit(function()
        local bus, request, active
        local failures, last_good = 0, nil

        local function poll()
            local registers, read_error, exchange = bus:read_registers(request, profile.timeout_ms)
            -- 站号或串口格式变化时丢弃旧请求结果。单独修改周期时仍使用当前回包。
            if not serial_config.same_link(active, settings.modbus_serial()) then return end
            local values
            if registers then values, read_error = M.decode(registers, profile.fields) end
            if values then
                -- 数据变化时更新界面。读数从失败状态恢复时也重新发布。
                local changed = failures > 0 or not last_good
                for id, value in pairs(values) do
                    if last_good and last_good[id] ~= value then changed = true end
                end
                failures, last_good = 0, values
                if changed then
                    sys.publish("ENVIRONMENT_DATA", values)
                    for id, value in pairs(values) do
                        log.info("modbus_sensor", "SENSOR_READ_OK", id, value)
                    end
                end
            else
                failures = failures + 1
                if failures == 1 or failures == profile.stale_after then
                    log.warn("modbus_sensor", "SENSOR_READ_FAILED", profile.name, read_error, failures, exchange or "")
                end
                if failures == profile.stale_after then
                    -- 超时或坏帧不能作为新值显示。故障持续时不重复刷新页面。
                    last_good = nil
                    sys.publish("ENVIRONMENT_UNAVAILABLE", metric_ids)
                end
            end
        end

        while true do
            local desired = settings.modbus_serial()
            if not serial_config.same_link(active, desired) then
                if bus then bus:close() end
                if active then sys.publish("ENVIRONMENT_UNAVAILABLE", metric_ids) end
                failures, last_good = 0, nil
                bus, request = open_port(desired)
                active = desired
                sys.publish("APP_MODBUS_SERIAL_APPLIED", active, bus ~= nil)
            end
            if bus then poll() end

            -- 本轮结束后按已保存周期等待。空闲时修改周期会唤醒任务，以新周期重新计时。
            -- 站号或串口格式发生变化时退出等待，让外层循环重新初始化 UART。
            while true do
                desired = settings.modbus_serial()
                if not serial_config.same_link(active, desired) then break end
                if active.interval_ms ~= desired.interval_ms then
                    active = desired
                    sys.publish("APP_MODBUS_SERIAL_APPLIED", active, bus ~= nil)
                end
                if not sys.waitUntil("APP_MODBUS_SERIAL_CHANGED", active.interval_ms) then break end
            end
        end
    end)
end

return M
