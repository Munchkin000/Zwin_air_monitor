-- UART1 串口设置的选项、出厂默认值和校验规则，由设置界面与采集服务共用。
local profile = require("modbus_profile")
local M = {}

M.fields = {
    { key = "baud", label = "波特率", options = {4800, 9600, 19200, 38400, 57600, 115200, 230400} },
    { key = "data_bits", label = "数据位", options = {7, 8} },
    { key = "stop_bits", label = "停止位", options = {1, 2} },
    { key = "parity", label = "奇偶校验", options = {"NONE", "ODD", "EVEN"},
        labels = {"无校验", "奇校验", "偶校验"} },
}
M.min_slave, M.max_slave = 1, 247 -- Modbus RTU 单播站号范围
-- 10 ms 覆盖最低支持波特率下的 RTU 帧间静默，最大值沿用 sys.waitUntil 的定时器上限。
M.min_interval_ms, M.max_interval_ms = 10, 0x7FFFFFFF

function M.defaults()
    local config = { slave = profile.request.slave, interval_ms = profile.interval_ms }
    for _, field in ipairs(M.fields) do config[field.key] = profile.serial[field.key] end
    return config
end

function M.copy(config)
    local copy = { slave = config.slave, interval_ms = config.interval_ms }
    for _, field in ipairs(M.fields) do copy[field.key] = config[field.key] end
    return copy
end

-- 几处界面和存储复用这一判断，AirUI 下拉索引由界面负责换算。
function M.option_index(field, value)
    for index, option in ipairs(field.options) do
        if option == value then return index end
    end
end

function M.valid_slave(value)
    return type(value) == "number" and value >= M.min_slave and value <= M.max_slave and value % 1 == 0
end

function M.valid_interval(value)
    return type(value) == "number" and value >= M.min_interval_ms
        and value <= M.max_interval_ms and value % 1 == 0
end

function M.validate(config)
    if type(config) ~= "table" then return false, "串口配置无效" end
    for _, field in ipairs(M.fields) do
        if not M.option_index(field, config[field.key]) then return false, field.label .. "无效" end
    end
    if not M.valid_slave(config.slave) then return false, "通信地址请输入 1–247 的整数" end
    if not M.valid_interval(config.interval_ms) then
        return false, string.format("读取周期请输入 %d 至 %d ms 的整数", M.min_interval_ms, M.max_interval_ms)
    end
    return true
end

-- 旧记录可能已经有串口参数。只为缺失或无效的周期字段补上默认值。
function M.restore(saved)
    if type(saved) ~= "table" then return end
    local config = M.copy(saved)
    if not M.valid_interval(config.interval_ms) then config.interval_ms = profile.interval_ms end
    if M.validate(config) then return config end
end

-- 读取周期由调度使用，不影响 UART 或 Modbus 请求帧。
function M.same_link(left, right)
    if not left or not right or left.slave ~= right.slave then return false end
    for _, field in ipairs(M.fields) do
        if left[field.key] ~= right[field.key] then return false end
    end
    return true
end

function M.same(left, right)
    return M.same_link(left, right) and left.interval_ms == right.interval_ms
end

return M
