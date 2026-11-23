-- 运行日志查询模型。以保存的通道设置过滤和判断超标，界面只负责显示查询结果。
local calendar = require("settings_calendar")
local channels = require("channel_store")
local data = require("env_data")
local store = require("sd_log_store")
local M = {}
local RECORD_FORMAT = "<I4I1d" -- 当天秒数、因子序号、原始测量值。
local RECORD_SIZE = string.packsize(RECORD_FORMAT)
local CHUNK_ROWS = 128

function M.date_label(date, separator)
    return string.format("%04d%s%02d%s%02d", date.year, separator, date.month, separator, date.day)
end

function M.time_label(minutes)
    return string.format("%02d:%02d", minutes // 60, minutes % 60)
end

-- 筛选精度为分钟。起止分钟相同仍可查询这一分钟的 00 至 59 秒。
function M.range(date, first, last)
    if not calendar.to_utc({year = date.year, month = date.month, day = date.day,
        hour = 0, min = 0, sec = 0}, 0) then return nil, "请选择有效的查询日期" end
    if first < 0 or last >= 1440 or first > last then return nil, "起始时间不能晚于终止时间" end
    return {day = M.date_label(date, "_"), date = M.date_label(date, "-"),
        from = first * 60, to = last * 60 + 59, first = first, last = last}
end

local function second_of_day(timestamp, date)
    if type(timestamp) ~= "string" or timestamp:sub(1, 10) ~= date then return end
    local h, m, s = timestamp:match("^.......... (%d%d):(%d%d):(%d%d)$")
    if not h then return end
    h, m, s = tonumber(h), tonumber(m), tonumber(s)
    if h < 24 and m < 60 and s < 60 then return h * 3600 + m * 60 + s end
end

function M.query(range, pc, cancelled)
    local _, settings = channels.snapshot()
    local active = {}
    for _, metric in ipairs(data.metrics) do
        local config = settings[metric.id]
        if config.enabled then active[#active + 1] = {metric = metric, config = config} end
    end
    if #active == 0 then return nil, "请先在采集通道中启用监测因子" end

    -- 记录以小块二进制保存。全天数据量大时，无需为每行持有 Lua 表和文字标签。
    local result = {date = range.date, active = active, chunks = {}, count = 0}
    local chunk, columns, valid_header = {}, {}, false
    local function visit(row, row_number)
        if row_number == 1 then
            valid_header = row[1] == "时间"
            for column = 2, 16 do
                local id = row[column]
                if type(id) == "string" then columns[id] = column end
            end
            for _, entry in ipairs(active) do entry.column = columns[entry.metric.id] end
            return
        end
        local second = valid_header and second_of_day(row[1], range.date)
        if not second or second < range.from or second > range.to then return end
        for index, entry in ipairs(active) do
            local value = row[entry.column]
            -- 历史文件中未采到的值可能是 none 或 --，仅展示实际测量值。
            if type(value) == "number" then
                chunk[#chunk + 1] = string.pack(RECORD_FORMAT, second, index, value)
                result.count = result.count + 1
                if #chunk == CHUNK_ROWS then
                    result.chunks[#result.chunks + 1] = table.concat(chunk)
                    chunk = {}
                end
            end
        end
    end
    local ok, reason = store.read_history(range.day, pc, visit, cancelled)
    if not ok then return nil, reason end
    if not valid_header then return nil, "监测数据文件表头无效" end
    if #chunk > 0 then result.chunks[#result.chunks + 1] = table.concat(chunk) end
    return result
end

function M.row(result, index)
    local offset = index - 1
    local chunk = result.chunks[offset // CHUNK_ROWS + 1]
    local second, factor, value = string.unpack(RECORD_FORMAT, chunk, (offset % CHUNK_ROWS) * RECORD_SIZE + 1)
    local entry = result.active[factor]
    local time = string.format("%s %02d:%02d:%02d", result.date, second // 3600, second // 60 % 60, second % 60)
    local status = data.exceeds_alarm(entry.config, value) and "超标" or "正常"
    return {time, entry.metric.name, data.format(entry.config, value), entry.metric.unit, status}
end

return M
