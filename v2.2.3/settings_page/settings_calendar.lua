-- 日期编辑使用公历。这里集中处理闰年、各月天数和时区转换。
local M = {}
-- 时间编辑字段定义表：key为字段名，label界面显示文字，min/max取值范围
M.fields = {
    { key = "year", label = "年", min = 2000, max = 2099 },
    { key = "month", label = "月", min = 1, max = 12 },
    { key = "day", label = "日", min = 1, max = 31 },
    { key = "hour", label = "时", min = 0, max = 23 },
    { key = "min", label = "分", min = 0, max = 59 },
    { key = "sec", label = "秒", min = 0, max = 59 },
}
-- 平年每个月份的总天数，下标1~12对应1‑12月
local month_days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

-- 判断是否为闰年：能被4整除，不能被100整除 或者 可以被400整除
local function leap(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

-- 获取某年某月实际总天数，2月闰年返回29，其余读取month_days表
function M.days_in_month(year, month)
    if month == 2 and leap(year) then return 29 end
    return month_days[month]
end

-- 时间字段步进增减函数，date时间table，field字段配置，delta增减步长（+1 / -1）
function M.step(date, field, delta)
    local upper = field.max
    -- 如果操作的是日期day，上限取当前年月真实月末天数，而不是固定31
    if field.key == "day" then upper = M.days_in_month(date.year, date.month) end
    local value = date[field.key] + delta
    -- 各字段在自身范围内循环。调整年月后，将日期收敛到该月最后一天。
    -- 取模运算实现数值循环滚动，例如12月+1变为1月，1月‑1变为12月
    date[field.key] = field.min + (value - field.min) % (upper - field.min + 1)
    -- 修正日期：切换年月后，如果旧日期大于当月最大天数，强制修改为本月最后一天
    date.day = math.min(date.day, M.days_in_month(date.year, date.month))
end

-- 将本地时间date加上时区偏移offset，转换得到UTC时间戳；校验时间合法性，非法返回nil
function M.to_utc(date, offset)
    -- 遍历所有时间字段，校验：必须是数字、在最大最小范围内、必须为整数
    for _, field in ipairs(M.fields) do
        local value = date[field.key]
        if type(value) ~= "number" or value < field.min or value > field.max or value % 1 ~= 0 then
            return nil
        end
    end
    -- 额外校验日期不能超过当月实际最大天数（例如2月30日判定非法）
    if date.day > M.days_in_month(date.year, date.month) then return nil end
    -- 以 2000-01-01 UTC 为基准累加天数，避免 os.time(table) 依赖电脑本地时区。
    local days = date.day - 1
    -- 累加从2000年到目标年份前一年的整年天数
    for year = 2000, date.year - 1 do days = days + (leap(year) and 366 or 365) end
    -- 累加目标年份中，目标月份之前各个月的天数
    for month = 1, date.month - 1 do days = days + M.days_in_month(date.year, month) end
    -- 946684800 是2000‑01‑01 00:00:00 UTC时间戳；减去时区offset得到UTC时间戳
    return 946684800 + days * 86400 + date.hour * 3600 + date.min * 60 + date.sec - offset
end

return M
