-- UART 半双工 Modbus-RTU 主站，提供 0x03 / 0x04 的连续寄存器读取。
-- UART 底层自动切换 RS485 方向，组帧与具体传感器的数值换算分离。
local M = {}

local function valid_integer(value, minimum, maximum)
    return type(value) == "number" and value % 1 == 0
        and value >= minimum and value <= maximum
end

-- 请求中的地址和数量是大端。CRC16 放在帧末尾，低字节在前。
function M.build_request(request)
    if not valid_integer(request.slave, 1, 247)
        or (request.function_code ~= 0x03 and request.function_code ~= 0x04)
        or not valid_integer(request.address, 0, 0xFFFF)
        or not valid_integer(request.count, 1, 125)
        or request.address + request.count > 0x10000 then
        return nil, "INVALID_REQUEST"
    end
    local payload = string.pack(">BBI2I2", request.slave, request.function_code, request.address, request.count)
    return payload .. string.pack("<I2", crypto.crc16_modbus(payload))
end

-- 可能分多次收到一帧。返回 nil 且无错误时，继续等待后续字节。
local function parse_response(request, response)
    if #response < 2 then return end
    local slave, code, size = response:byte(1, 3)
    if slave ~= request.slave then return nil, "SLAVE_MISMATCH" end

    local exception = code == (request.function_code | 0x80)
    if not exception then
        if code ~= request.function_code then return nil, "FUNCTION_MISMATCH" end
        if size == nil then return end
        if size ~= request.count * 2 then return nil, "INVALID_BYTE_COUNT" end
    end
    local length = exception and 5 or (5 + size)
    if #response < length then return end
    if #response ~= length then return nil, "INVALID_FRAME_LENGTH" end

    local crc = string.unpack("<I2", response, length - 1)
    if crypto.crc16_modbus(response:sub(1, -3)) ~= crc then return nil, "CRC_ERROR" end
    if exception then return nil, string.format("MODBUS_EXCEPTION_0x%02X", size) end

    local registers = {}
    for index = 1, request.count do
        registers[index] = string.unpack(">I2", response, 4 + (index - 1) * 2)
    end
    return registers
end

function M.open(serial)
    if not (uart and gpio and crypto and crypto.crc16_modbus) then
        return nil, "CORE_API_UNAVAILABLE"
    end
    local parity = uart[serial.parity]
    if parity == nil then return nil, "INVALID_PARITY" end

    -- 板载隔离收发器先供电，再把 DE 的控制权交给 UART。
    -- V1032 的 uart.write 只把数据交给发送队列。通过 setup 启用 RS485，
    -- 底层会在最后一位发完后切回接收。
    gpio.setup(serial.enable_pin, 1)
    gpio.setup(serial.de_pin, serial.rx_level)
    local port = serial.port
    local result = uart.setup(port, serial.baud, serial.data_bits, serial.stop_bits, parity,
        uart.LSB, 1024, serial.de_pin, serial.rx_level, serial.turnaround_us)
    if result ~= 0 then return nil, "UART_SETUP_FAILED" end

    local response_event = "MODBUS_RTU_RESPONSE_" .. port
    local pending
    -- 发送事件仅用于诊断。收到合法响应时可以直接完成本次请求。
    uart.on(port, "sent", function()
        if pending then pending.sent = true end
    end)
    -- 不在串口回调里阻塞读数据。累积到完整帧后唤醒轮询任务。
    uart.on(port, "receive", function()
        while true do
            local chunk = uart.read(port, 256)
            if not chunk or chunk == "" then break end
            if pending and not pending.done then
                pending.buffer = pending.buffer .. chunk
                local registers, err = parse_response(pending.request, pending.buffer)
                if registers or err then
                    pending.registers, pending.err, pending.done = registers, err, true
                    sys.publish(response_event)
                end
            end
        end
    end)

    -- 失败时记录请求、发送事件和回包。最多打印 32 字节，防止总线干扰刷屏。
    local function describe_exchange(frame, exchange)
        local function hex(bytes)
            return (bytes:gsub(".", function(byte) return string.format("%02X", byte:byte()) end))
        end
        local received = exchange.buffer
        local preview = received:sub(1, 32)
        return string.format("TX=%s SENT=%s RX_BYTES=%d RX=%s",
            hex(frame), tostring(exchange.sent), #received, #preview > 0 and hex(preview) or "-")
    end

    local bus = {}
    local closed = false

    -- 轮询任务完成当前请求后关闭串口，再用新参数重开。
    function bus:close()
        if closed or pending then return false end
        closed = true
        uart.on(port, "sent", nil)
        uart.on(port, "receive", nil)
        uart.close(port)
        return true
    end

    function bus:read_registers(request, timeout_ms)
        if closed then return nil, "UART_CLOSED" end
        if pending then return nil, "UART_BUSY" end
        local frame, err = M.build_request(request)
        if not frame then return nil, err end
        if uart.rxClear then uart.rxClear(port) end
        local exchange = { request = request, buffer = "", sent = false }
        pending = exchange

        -- 发送队列接收完整帧后等待响应，收发切换由已配置的 UART 底层负责。
        local written = uart.write(port, frame)
        if written ~= #frame then
            pending = nil
            return nil, "UART_WRITE_FAILED", describe_exchange(frame, exchange)
        end

        if not exchange.done then sys.waitUntil(response_event, timeout_ms) end
        pending = nil
        if not exchange.registers then
            return nil, exchange.err or "TIMEOUT", describe_exchange(frame, exchange)
        end
        return exchange.registers
    end
    return bus
end

return M
