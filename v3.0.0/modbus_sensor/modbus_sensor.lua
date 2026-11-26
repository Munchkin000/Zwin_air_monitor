-- UART1 的唯一轮询任务。全部因子使用系统采样周期，一次只发送一条 RTU 请求。
local rtu = require("modbus_rtu")
local profile = require("modbus_profile")
local config = require("channel_store")
local data = require("env_data")
local params = require("system_params")
local uptime = require("app_uptime")
local M = {}
local started

-- 两寄存器类型按 ABCD 顺序解码。÷10 类型对应已验证的 SC-TH1001 出厂值。
function M.decode(registers, data_type, offset)
    local first, second = registers[offset + 1], registers[offset + 2]
    if first == nil then return nil, "MISSING_REGISTER" end
    local value = first
    if data_type == "i16" or data_type == "i16_10" then
        if value >= 0x8000 then value = value - 0x10000 end
    elseif data_type == "f32" or data_type == "i32" then
        if second == nil then return nil, "MISSING_REGISTER" end
        local format = data_type == "f32" and ">f" or ">i4"
        value = string.unpack(format, string.pack(">I2I2", first, second))
    end
    if data_type == "i16_10" or data_type == "u16_10" then value = value / 10 end
    if value ~= value or math.abs(value) == math.huge then return nil, "INVALID_NUMBER" end
    return value
end

local function open_port(serial)
    local parameters = {}
    for key, value in pairs(profile.serial) do parameters[key] = value end
    for key, value in pairs(serial) do parameters[key] = value end
    local bus, err = rtu.open(parameters)
    if bus then
        log.info("modbus_sensor", "SENSOR_STARTED", "UART" .. parameters.port,
            parameters.baud, parameters.data_bits, parameters.stop_bits, parameters.parity)
    else
        log.error("modbus_sensor", "SENSOR_INIT_FAILED", err)
        sys.publish("APP_RUNTIME_FAULT", "sensor:uart", "传感器读取失败（UART1：" .. tostring(err) .. "）")
    end
    return bus
end

-- 出厂温湿度共用一条连续读请求，保持已上板验证的 0x04 / 两寄存器报文。
-- 两因子使用不同的协议时，按各自配置单独轮询。
local function can_pair(temp, hum)
    return temp and hum and temp.slave == hum.slave
        and temp.function_code == 4 and hum.function_code == 4 and temp.address == 0 and hum.address == 1
        and temp.count == 1 and hum.count == 1 and temp.data_type == "i16_10" and hum.data_type == "u16_10"
end

function M.start()
    if started then return end
    started = true
    sys.taskInit(function()
        local bus, opened_serial
        local jobs = {}
        local retry_at = 0

        local now = uptime.ms
        local active_period = params.sample_ms()

        local function poll(serial, request, ids)
            local registers, err = bus:read_registers(request, profile.timeout_ms)
            local current_bus, entries = config.snapshot()
            local values = {}
            local completed = now()
            for _, id in ipairs(ids) do
                local job = jobs[id]
                local current = entries[id]
                -- 保存可能发生在等应答时。丢弃已禁用或改变来源后的旧帧。
                if current_bus == serial and config.same_source(job.channel, current) then
                    local value, decode_error
                    if registers then
                        value, decode_error = M.decode(registers, current.data_type, current.address - request.address)
                    end
                    if value ~= nil then
                        -- 实测值交给 UI、历史存储和上报服务，串口只记录采集异常。
                        job.failures, values[id] = 0, value
                    else
                        job.failures = job.failures + 1
                        local stale = job.failures == profile.stale_after
                        if job.failures == 1 or stale then
                            log.warn("modbus_sensor", "SENSOR_READ_FAILED", id, err or decode_error, job.failures)
                        end
                        if job.failures == 1 then
                            local message = string.format("目标地址传感器无法读取（%s · 从站 0x%02X · 地址 %d · %s）",
                                id, current.slave, current.address, tostring(err or decode_error))
                            sys.publish("APP_RUNTIME_FAULT", "sensor:" .. id, message)
                        end
                        sys.publish("ENVIRONMENT_SAMPLE_MISSED", id, stale)
                    end
                    job.channel, job.due = current, completed + params.sample_ms()
                end
            end
            -- 即使数值不变也交给环境状态计数，以实现连续超限告警。
            if next(values) then sys.publish("ENVIRONMENT_DATA", values) end
            -- 预留至少约四个字符时间，避免一条应答结束后立即发送下一条请求。
            sys.wait(math.max(2, math.ceil(44000 / serial.baud)))
        end

        while true do
            local serial, entries = config.snapshot()
            local time = now()
            local period = params.sample_ms()
            local due, next_wait, any_enabled = {}, 1000, false
            if serial ~= opened_serial then
                if bus then bus:close() end
                bus, opened_serial, jobs, retry_at = nil, serial, {}, 0
            end
            for _, metric in ipairs(data.metrics) do
                local id = metric.id
                local channel, job = entries[id], jobs[id]
                if channel.enabled then
                    any_enabled = true
                    if not job or not config.same_source(job.channel, channel) then
                        job = {channel = channel, due = time, failures = 0}
                        jobs[id] = job
                    elseif active_period ~= period then
                        job.due = time + period
                    end
                    job.channel = channel
                    if job.due <= time then due[id] = channel
                    else next_wait = math.min(next_wait, job.due - time) end
                else
                    jobs[id] = nil
                end
            end

            active_period = period

            if any_enabled and not bus and time >= retry_at then
                bus = open_port(serial)
                retry_at = time + 2000
            end
            if bus and next(due) then
                local paired = can_pair(due.temperature, due.humidity)
                for _, metric in ipairs(data.metrics) do
                    -- 跳过当前批次已经失效的计划，下一轮以最新配置重新排序。
                    local active_bus, active_channels = config.snapshot()
                    if active_bus ~= serial or active_channels ~= entries then break end
                    local id = metric.id
                    if id == "temperature" and paired then
                        local request = {slave = due.temperature.slave, function_code = 4, address = 0, count = 2}
                        poll(serial, request, {"temperature", "humidity"})
                    elseif due[id] and not (id == "humidity" and paired) then
                        poll(serial, due[id], {id})
                    end
                end
            else
                sys.waitUntil("CHANNEL_CONFIG_CHANGED", math.max(1, next_wait))
            end
        end
    end)
end

return M
