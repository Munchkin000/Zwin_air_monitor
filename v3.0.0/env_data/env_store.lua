-- 运行数据和告警状态独立于显示页面，环境页只读取这一份缓存。
local data = require("env_data")
local settings = require("channel_store")
local state = require("env_state").new()
local started
state.alerts = {}
local streaks = {}

local function valid(value)
    return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

-- 超限延时以连续有效采样次数计，同一方向的连续超限才触发。
local function alarm(id, value, channel)
    local previous = state.alerts[id]
    local side = value < channel.alarm_low and "low" or (value > channel.alarm_high and "high" or nil)
    if not side then
        streaks[id], state.alerts[id] = nil, nil
    else
        local run = streaks[id]
        if not run or run.side ~= side then run = {side = side, count = 0} end
        run.count = math.min(channel.alarm_delay, run.count + 1)
        streaks[id] = run
        if run.count >= channel.alarm_delay then state.alerts[id] = side
        elseif previous ~= side then state.alerts[id] = nil end
    end
    if state.alerts[id] == previous then return false end
    -- 串口只保留告警状态变化，不打印传感器实测值。
    log.info("environment", "CHANNEL_ALARM", id, state.alerts[id] or "normal")
    return true
end

function state:start(is_pc)
    if started then return end
    started = true
    local function apply_config(changed_id, bus_changed, source_changed)
        local _, channels = settings.snapshot()
        local flags = {}
        for index, metric in ipairs(data.metrics) do
            local id = metric.id
            flags[index] = channels[id].enabled
            if bus_changed or (id == changed_id and source_changed) then
                self:invalidate({id})
            end
            if bus_changed or id == changed_id then streaks[id], self.alerts[id] = nil, nil end
            -- 仿真可用静态值预览；真机上的启用因子在首次采集前统一显示待采集。
            if is_pc and flags[index] and not self.received[id] then self.values[id] = metric.default end
        end
        self:apply_selection(flags)
    end

    if not is_pc then self.values = {} end
    apply_config()
    sys.subscribe("CHANNEL_CONFIG_CHANGED", function(...)
        apply_config(...)
        sys.publish("ENVIRONMENT_CONFIG_CHANGED")
    end)
    sys.subscribe("ENVIRONMENT_DATA", function(values)
        if type(values) ~= "table" then return end
        local _, channels = settings.snapshot()
        local changed = false
        for id, value in pairs(values) do
            local channel = channels[id]
            if channel and channel.enabled and valid(value) then
                if self.values[id] ~= value or not self.received[id] then changed = true end
                self.values[id], self.received[id] = value, true
                if alarm(id, value, channel) then changed = true end
            end
        end
        if changed then sys.publish("ENVIRONMENT_CHANGED") end
    end)
    local function invalidate(ids)
        local changed = self:invalidate(ids)
        for _, id in ipairs(ids) do
            if self.alerts[id] then changed = true end
            streaks[id], self.alerts[id] = nil, nil
        end
        if changed then sys.publish("ENVIRONMENT_CHANGED") end
    end
    sys.subscribe("ENVIRONMENT_UNAVAILABLE", invalidate)
    sys.subscribe("ENVIRONMENT_SAMPLE_MISSED", function(id, stale)
        streaks[id] = nil
        if stale then invalidate({id}) end
    end)
end

return state
