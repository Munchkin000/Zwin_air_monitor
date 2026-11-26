-- 因子配置与 UART1 总线参数。每次保存原子提交，采集任务始终看到完整的一份配置。
local data = require("env_data")
local profile = require("modbus_profile")
local serial_cfg = require("modbus_serial_cfg")
local M = {}
local key = "air_channel_settings"
local bus, channels
local metrics = {}
for _, metric in ipairs(data.metrics) do metrics[metric.id] = metric end
local sensor_fields = {}
for _, field in ipairs(profile.fields) do sensor_fields[field.id] = field end

M.functions = {0x03, 0x04, 0x02}
M.function_labels = {"03 保持寄存器", "04 输入寄存器", "02 离散输入"}
M.types = {"u16", "i16", "f32", "i32", "u16_10", "i16_10", "bit"}
M.type_labels = {"16 位无符号", "16 位有符号", "Float32 ABCD", "Int32 ABCD",
    "UInt16 ÷10", "Int16 ÷10", "离散位 (0/1)"}
local words = {u16 = 1, i16 = 1, f32 = 2, i32 = 2, u16_10 = 1, i16_10 = 1, bit = 1}

-- 存入 Flash 时按固定字段顺序保存数组，避免 15 个因子重复字段名超过 FSKV 大小限制。
local fields = {"enabled", "interval_ms", "decimals", "slave", "function_code", "address", "count",
    "data_type", "min", "max", "alarm_low", "alarm_high", "alarm_delay"}

local function copy(record)
    local result = {}
    for name, value in pairs(record) do result[name] = value end
    return result
end

local function integer(value, lo, hi)
    return type(value) == "number" and value >= lo and value <= hi and value % 1 == 0
end

local function level(value)
    return type(value) == "number" and math.abs(value) <= 1e9
end

local function validate(draft)
    if type(draft.enabled) ~= "boolean" then return "采集开关无效" end
    if not serial_cfg.valid_interval(draft.interval_ms) then return "采集周期超出范围（ms）" end
    if not integer(draft.decimals, 0, 6) then return "小数位请输入 0 至 6 的整数" end
    if not serial_cfg.valid_slave(draft.slave) then return "从站地址请输入 0x01 至 0xF7" end
    local fn = draft.function_code
    if fn ~= 2 and fn ~= 3 and fn ~= 4 then return "请选择读取功能码" end
    if not integer(draft.address, 0, 65535) then return "起始地址请输入 0 至 65535" end
    local width = words[draft.data_type]
    if not width or ((fn == 2) ~= (draft.data_type == "bit")) then
        return "02 功能码使用离散位，03 / 04 使用寄存器数据类型"
    end
    if not integer(draft.count, width, fn == 2 and 2000 or 125)
        or draft.address + draft.count > 65536 then return "数量与数据类型或地址范围不匹配" end
    if not (level(draft.min) and level(draft.max)) or draft.min >= draft.max then
        return "量程最小值必须小于最大值"
    end
    if not (level(draft.alarm_low) and level(draft.alarm_high)) or draft.alarm_low > draft.alarm_high then
        return "告警下限必须小于或等于上限"
    end
    if not integer(draft.alarm_delay, 1, 999) then return "超限延时请输入 1 至 999 次" end
end

-- UART1 只有一种工作格式。配置界面各因子共用这些字段，站号和周期单独保存。
local function bus_copy(serial)
    local result = {}
    for _, field in ipairs(serial_cfg.fields) do result[field.key] = serial[field.key] end
    return result
end

local function validate_bus(serial)
    for _, field in ipairs(serial_cfg.fields) do
        if not serial_cfg.option_index(field, serial[field.key]) then return field.label .. "无效" end
    end
end

function M.start(legacy)
    legacy = legacy or serial_cfg.defaults()
    bus, channels = bus_copy(legacy), {}
    local saved = fskv and fskv.get(key)
    if type(saved) == "table" and type(saved.bus) == "table" and not validate_bus(saved.bus) then
        bus = bus_copy(saved.bus)
    end
    for _, metric in ipairs(data.metrics) do
        local source = sensor_fields[metric.id]
        -- 旧站号、周期以及已验证的 ÷10 换算分别迁入温度和湿度。其余因子默认关闭。
        local draft = {
            enabled = source ~= nil, interval_ms = source and legacy.interval_ms or profile.interval_ms,
            decimals = metric.decimals, slave = source and legacy.slave or 1,
            function_code = source and profile.request.function_code or 0x03,
            address = source and profile.request.address + source.offset or 0, count = 1,
            data_type = source and (source.signed and "i16_10" or "u16_10") or "u16",
            min = metric.min, max = metric.max,
            alarm_low = source and source.min or metric.min, alarm_high = source and source.max or metric.max,
            alarm_delay = 3,
        }
        local record = type(saved) == "table" and type(saved.channels) == "table" and saved.channels[metric.id]
        if type(record) == "table" then
            local restored = {}
            for index, name in ipairs(fields) do restored[name] = record[index] end
            if not validate(restored) then draft = restored end
        end
        channels[metric.id] = draft
    end
end

-- 内部消费者只读此快照。保存时换用新表，正在等待应答的任务可以识别旧配置。
function M.snapshot()
    return bus, channels
end

-- 设置界面编辑的是副本，直到保存成功前都不改变采集任务的数据。
function M.edit(id)
    return copy(channels[id]), copy(bus)
end

function M.same_source(left, right)
    return left.enabled == right.enabled and left.slave == right.slave
        and left.function_code == right.function_code and left.address == right.address
        and left.count == right.count and left.data_type == right.data_type
end

function M.save(id, draft, serial)
    if not metrics[id] then return false, "未知监测因子" end
    local problem = validate(draft) or validate_bus(serial)
    if problem then return false, problem end
    local bus_changed = false
    for name, value in pairs(bus) do
        if value ~= serial[name] then bus_changed = true end
    end
    local changed = bus_changed
    local previous = channels[id]
    for _, name in ipairs(fields) do
        if previous[name] ~= draft[name] then changed = true end
    end
    if not changed then return true end

    local next_channels = copy(channels)
    next_channels[id] = copy(draft)
    local next_bus = bus_changed and bus_copy(serial) or bus
    local records = {}
    for metric_id, channel in pairs(next_channels) do
        local record = {}
        for index, name in ipairs(fields) do record[index] = channel[name] end
        records[metric_id] = record
    end
    if not (fskv and fskv.set(key, {bus = next_bus, channels = records})) then
        return false, "保存失败，请检查配置存储"
    end
    bus, channels = next_bus, next_channels
    sys.publish("CHANNEL_CONFIG_CHANGED", id, bus_changed, not M.same_source(previous, draft))
    log.info("channels", "CHANNEL_SAVED", id, draft.enabled, draft.interval_ms, draft.decimals)
    return true
end

return M
