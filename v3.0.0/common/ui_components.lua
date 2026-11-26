-- 公共组件统一处理坐标缩放、字体、容器边框和应用卡片样式。
local theme = require("ui_theme")
local M = {}

-- 维持 1024×600 画布比例，并在屏幕内居中。px 将基准坐标和尺寸转换成实际像素。
function M.layout(display)
    local scale = math.min(display.width / 1024, display.height / 600)
    return {
        scale = scale,
        x = math.floor((display.width - 1024 * scale) / 2),
        y = math.floor((display.height - 600 * scale) / 2),
        px = function(value) return math.floor(value * scale + 0.5) end,
    }
end

function M.label(parent, layout, text, x, y, w, h, size, color, align, on_click)
    local p = layout.px
    return airui.label({
        parent = parent, text = text, x = p(x), y = p(y), w = p(w), h = p(h),
        font = "hzfont", font_size = math.max(12, p(size)), color = color or theme.text,
        align = align or airui.TEXT_ALIGN_LEFT, on_click = on_click,
    })
end

function M.box(parent, layout, x, y, w, h, color, radius, border, on_click)
    local p = layout.px
    return airui.container({
        parent = parent, x = p(x), y = p(y), w = p(w), h = p(h),
        color = color, radius = p(radius or 0), border_color = border,
        border_width = border and math.max(1, p(1)) or 0, on_click = on_click,
    })
end

-- 应用卡片的 220 像素宽度与主页 CARD_WIDTH 对应，调整宽度时应同步修改两处。
function M.app_card(parent, layout, app, x, y, on_click)
    local tone = theme.tones[app.reserved and "reserved" or app.tone] or theme.tones.blue
    local card = M.box(parent, layout, x, y, 220, 116,
        app.reserved and theme.surface_reserved or theme.surface, 16, theme.border, on_click)
    -- V2039 中子控件可以接收点击事件，因此卡片、图标底板和文字使用相同的点击处理。
    local badge = M.box(card, layout, 86, 14, 48, 48, tone.background, 14, nil, on_click)
    require("ui_icons").draw(badge, layout, app.icon, 8, 8, 32, tone.foreground)
    M.label(card, layout, app.title, 8, 77, 204, 30, 21,
        app.reserved and theme.muted or theme.text, airui.TEXT_ALIGN_CENTER, on_click)
    return card
end

return M
