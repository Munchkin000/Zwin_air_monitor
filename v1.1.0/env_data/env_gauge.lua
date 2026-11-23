-- 环境仪表的 270 度圆弧由多段 AirUI 原生线段绘成，适配 V2039 仿真。
-- 页面一次只创建当前窗口内的四个仪表。
local ui = require("ui_components")
local theme = require("ui_theme")
local data = require("env_data")
local M = {}
-- 圆弧生成辅助函数
local function arc(items, p, from, to, color, width)
    -- 每一段最多跨 5 度，根据角度计算线段两端的像素坐标。
    local segments = math.max(1, math.ceil((to - from) / 5))
    for index = 0, segments - 1 do
        local a = math.rad(from + (to - from) * index / segments)
        local b = math.rad(from + (to - from) * (index + 1) / segments)
        items[#items + 1] = {
            type = "line", x1 = p(112 + 52 * math.cos(a)), y1 = p(76 + 52 * math.sin(a)),
            x2 = p(112 + 52 * math.cos(b)), y2 = p(76 + 52 * math.sin(b)),
            width = math.max(1, p(width)), color = color, round_start = true, round_end = true,
        }
    end
end
-- 生成完整表盘图形描述表
local function ring(layout, metric, value)
    local items, p = {}, layout.px
    arc(items, p, 135, 405, 0xE7EFF7, 9)
    -- 等待首帧或数据失效时，只画背景环，中心数值由 data.format 显示为 --。
    if type(value) ~= "number" then return items end
    -- 圆弧长度限制在仪表量程内，中央数字仍显示原始读数。
    local fraction = math.max(0, math.min(1, (value - metric.min) / (metric.max - metric.min)))
    if fraction > 0 then arc(items, p, 135, 135 + fraction * 270, metric.color, 9) end
    local a = math.rad(135 + fraction * 270)
    items[#items + 1] = { type = "circle", cx = p(112 + 52 * math.cos(a)),
        cy = p(76 + 52 * math.sin(a)), r = math.max(2, p(4)), width = 0,
        color = metric.color, fill = true, fill_color = metric.color, fill_opacity = 255 }
    return items
end
-- 创建一个仪表盘实例（对外接口）
function M.create(parent, layout, metric, value, x)
    local p = layout.px
    local gauge = {}
    gauge.root = ui.box(parent, layout, x, 0, 224, 176, theme.background, 0)
    gauge.shape = airui.shape({ parent = gauge.root, x = 0, y = 0, w = p(220), h = p(137),
        items = ring(layout, metric, value) })
    gauge.value = ui.label(gauge.root, layout, data.format(metric, value), 12, 55, 200, 40, 29,
        theme.text, airui.TEXT_ALIGN_CENTER)
    ui.label(gauge.root, layout, metric.unit, 12, 96, 200, 23, 13, theme.muted, airui.TEXT_ALIGN_CENTER)
    ui.label(gauge.root, layout, data.range_text(metric.min), 25, 123, 65, 19, 12, theme.muted, airui.TEXT_ALIGN_CENTER)
    ui.label(gauge.root, layout, data.range_text(metric.max), 134, 123, 65, 19, 12, theme.muted, airui.TEXT_ALIGN_CENTER)
    ui.label(gauge.root, layout, metric.name, 8, 143, 208, 27, 20, theme.text, airui.TEXT_ALIGN_CENTER)
    function gauge:update(next_value)
        self.shape:set_items(ring(layout, metric, next_value))
        self.value:set_text(data.format(metric, next_value))
    end
    function gauge:destroy() self.root:destroy() end
    return gauge
end
return M
