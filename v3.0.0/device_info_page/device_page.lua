-- 设备信息页按 device_fields.lua 生成各行，从 device_store 读取待显示的数据。
local ui = require("ui_components")
local theme = require("ui_theme")
local router = require("ui_router")
local store = require("device_store")
local fields = require("device_fields")
local M = {}
function M.create(context)
    local layout = ui.layout(context.config.display)
    local p = layout.px
    local page = { alive = true, cells = {} }
    page.root = airui.container({ x = 0, y = 0, w = context.config.display.width,
        h = context.config.display.height, color = theme.background })
    local canvas = airui.container({ parent = page.root, x = layout.x, y = layout.y,
        w = p(1024), h = p(600), color = theme.background })
    local header = ui.box(canvas, layout, 0, 0, 1024, 88, theme.header)
    page.logo = require("ui_brand").create(header, layout, context.config.brand)
    ui.box(header, layout, 282, 27, 1, 34, theme.border)
    ui.label(header, layout, "设备信息", 307, 20, 360, 33, 25)
    ui.label(header, layout, "智易时代 · 设备与存储信息", 308, 55, 390, 24, 13, theme.secondary)
    airui.button({ parent = canvas, text = "返回主页", x = p(864), y = p(27), w = p(120), h = p(36),
        font = "hzfont", font_size = p(16),
        style = { pad = 0, radius = p(8), border_width = 0, shadow_width = 0,
            bg_color = 0xE5F1FB, text_color = theme.clock },
        on_click = function()
            if not page.alive or page.back_timer then return end
            -- 在点击回调结束后切页，同时用计时器句柄拦住重复的返回操作。
            page.back_timer = sys.timerStart(function()
                page.back_timer = nil
                if page.alive then router.open("home") end
            end, 1)
        end })
    ui.box(canvas, layout, 0, 88, 1024, 1, theme.border)
    ui.label(canvas, layout, "设备信息列表", 40, 104, 300, 30, 20)
    ui.label(canvas, layout, "上下滑动查看", 480, 109, 504, 24, 14,
        theme.muted, airui.TEXT_ALIGN_RIGHT)
    local panel = ui.box(canvas, layout, 40, 148, 944, 404, theme.surface, 12, theme.border)
    -- 只在固定高度的列表容器内滚动，标题和返回按钮保持在顶部。
    page.viewport = ui.box(panel, layout, 0, 0, 942, 402, theme.surface)
    for index, field in ipairs(fields) do
        local row = ui.box(page.viewport, layout, 0, (index - 1) * 62, 926, 62,
            index % 2 == 0 and 0xF5F9FD or theme.surface)
        ui.label(row, layout, string.format("%02d", index), 16, 20, 44, 28, 15, theme.muted)
        ui.label(row, layout, field.label, 80, 17, 270, 32, 19, theme.text)
        page.cells[field.id] = ui.label(row, layout, "", 370, 17, 534, 32, 18,
            theme.clock, airui.TEXT_ALIGN_RIGHT)
    end
    ui.label(canvas, layout, "Flash 容量按应用文件区统计", 40, 565, 944, 25, 13, theme.muted)
    -- 依据字段 ID 刷新数值标签，保留现有控件和列表滚动位置。
    local function refresh()
        if not page.alive then return end
        local values = store.snapshot()
        for _, field in ipairs(fields) do page.cells[field.id]:set_text(values[field.id] or "待接入") end
        log.info("device", "DEVICE_REFRESH")
    end
    sys.subscribe("DEVICE_INFO_CHANGED", refresh)
    -- 切页前取消订阅和计时器，根容器销毁时一起清理列表控件。
    function page:destroy()
        self.alive = false
        if self.back_timer then sys.timerStop(self.back_timer) end
        sys.unsubscribe("DEVICE_INFO_CHANGED", refresh)
        self.root:destroy()
        self.cells = {}
    end
    refresh()
    store.refresh_storage() -- 真机查询存储容量，结果通过已有的设备信息事件刷新列表。
    log.info("device", "DEVICE_READY", #fields)
    return page
end
return M
