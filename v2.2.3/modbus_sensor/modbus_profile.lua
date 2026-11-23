-- SC-TH1001 协议配置，依据产品说明书 V1.2 第 16、24–26 页。
-- 更换 Modbus 传感器时集中修改站号、串口格式、读寄存器范围及换算规则。
return {
    name = "SC-TH1001",
    serial = {
        port = 1,        -- Air8603M1 J21 的 485_1A / 485_1B
        enable_pin = 64, -- 板载隔离 485 电源使能，高电平有效
        de_pin = 65,     -- 由 UART RS485 模式控制，高电平发送
        rx_level = 0,   -- 收发器在 DE 为低电平时接收
        turnaround_us = 0, -- 使用 Air1603 底层的默认收发切换时序
        baud = 9600,
        data_bits = 8,
        parity = "NONE", -- 可改为 "ODD" 或 "EVEN"
        stop_bits = 1,
    },
    interval_ms = 1000,  -- 上一轮结束后到下一轮的间隔，只有一个请求在途
    timeout_ms = 500,    -- 手册标称响应不超过 200 ms，预留驱动及 RTOS 调度时间
    stale_after = 3,     -- 连续读失败达到此次数后，清空上一次显示的读数
    request = {
        slave = 0x30,   -- 出厂地址十进制 48
        function_code = 0x04, -- 0x04 输入寄存器，0x03 保持寄存器
        address = 0x0000,     -- 使用报文地址，不使用 PLC 表示的 30001
        count = 2,
    },
    -- offset 从首个寄存器起算，从 0 开始。现有解码支持 16 位有符号或无符号整数。
    fields = {
        { id = "temperature", offset = 0, signed = true,  divisor = 10, min = -40, max = 120 },
        { id = "humidity",    offset = 1, signed = false, divisor = 10, min = 0,   max = 100 },
    },
}
