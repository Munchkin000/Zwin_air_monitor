-- 后台存储传感器快照和设备故障。即使没有进入任何页面，也会按系统参数写卡。
local params = require("system_params")
local uptime = require("app_uptime")
local metrics = require("env_data").metrics
local channels = require("channel_store")
local env = require("env_store")
local card = require("sd_card")
local store = require("sd_log_store")
local M = {}
local wake = "SD_LOG_WAKE"
local pending, recent = {}, {}
local started
local error_header = {"时间", "问题名称"}
local data_header = {"时间"}
for _, metric in ipairs(metrics) do data_header[#data_header + 1] = metric.id end

local function date_text(clock)
    if not clock.snapshot().valid then return end
    local date = clock.local_date()
    -- 文件按北京时间的日期归档，表格内仍保留到秒的完整时间。
    return string.format("%04d_%02d_%02d", date.year, date.month, date.day),
        string.format("%04d-%02d-%02d %02d:%02d:%02d",
            date.year, date.month, date.day, date.hour, date.min, date.sec)
end

function M.history_row(time)
    local row = {time}
    local _, entries = channels.snapshot()
    for _, metric in ipairs(metrics) do
        local id = metric.id
        local value = "none"
        if entries[id].enabled then value = env.received[id] and env.values[id] or "--" end
        row[#row + 1] = value
    end
    return row
end

function M.start(clock)
    if started then return end
    started = true
    local function enqueue(key, message)
        local now = uptime.ms()
        if recent[key] and now - recent[key] < 60000 then return end
        for _, entry in ipairs(pending) do
            if entry.key == key then return end
        end
        recent[key] = now
        local day, time = date_text(clock)
        -- 卡不可用时先保留最近 64 条故障，在恢复并校时后补写。
        if #pending == 64 then table.remove(pending, 1) end
        pending[#pending + 1] = {key = key, day = day, time = time, message = message}
        sys.publish(wake)
    end
    sys.subscribe("APP_RUNTIME_FAULT", enqueue)
    local period_changed = false
    sys.subscribe("APP_STORAGE_PERIOD_CHANGED", function()
        period_changed = true
        sys.publish(wake)
    end)

    sys.taskInit(function()
        local history_at = uptime.ms() + params.store_ms()
        local retry_at, next_probe = 0, 0
        while true do
            local now = uptime.ms()
            if period_changed then
                history_at = now + params.store_ms()
                period_changed = false
            end
            if now >= next_probe then
                local stat, cause = card.capacity()
                if not stat then enqueue("sd", "SD卡读取失败（" .. tostring(cause) .. "）") end
                next_probe = now + (stat and 60000 or 10000)
            end

            local day, time = date_text(clock)
            if day and now >= retry_at then
                local ok, reason = true
                if #pending > 0 then
                    local first = pending[1]
                    local batch_day = first.day or day
                    local rows = {}
                    local batch = {}
                    for _, entry in ipairs(pending) do
                        if (entry.day or day) ~= batch_day then break end
                        batch[entry] = true
                        rows[#rows + 1] = {entry.time or time, entry.message .. (entry.time and "" or "（发生时未校时）")}
                    end
                    ok, reason = store.write("fault", batch_day, error_header, rows, day)
                    -- 空间轮换期间可能有新故障进入队列，只移除本次已经写入的记录。
                    if ok then
                        for index = #pending, 1, -1 do
                            if batch[pending[index]] then table.remove(pending, index) end
                        end
                    end
                end
                if now >= history_at then
                    local history_ok, history_reason = store.write("history", day, data_header, {M.history_row(time)}, day)
                    if history_ok then
                        history_at = uptime.ms() + params.store_ms()
                    else
                        ok, reason = false, history_reason
                    end
                end
                if not ok then
                    log.warn("sd_history", "SD_LOG_FAILED", reason)
                    enqueue("sd", "SD卡读取或写入失败（" .. tostring(reason) .. "）")
                    retry_at = uptime.ms() + 10000
                end
            end
            local delay = 1000
            if day and now >= retry_at then
                delay = #pending > 0 and 100 or math.max(1, math.min(delay, history_at - uptime.ms()))
            end
            sys.waitUntil(wake, delay)
        end
    end)
end

return M
