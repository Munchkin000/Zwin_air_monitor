-- 系统设置采用左侧导航和右侧内容。新增项目时在 sections 增加一项及对应面板。
local ui = require("ui_components")
local theme = require("ui_theme")
local icons = require("ui_icons")
local widgets = require("settings_widgets")
local router = require("ui_router")
local M = {}

local sections = {
    { title = "网络设置", icon = "network", id = "settings_network", mount = require("settings_network").mount },
    { title = "亮度和声音", icon = "brightness", id = "settings_media", mount = require("settings_media").mount },
    { title = "当前时间和日期", icon = "time", id = "settings_time", mount = require("settings_time").mount },
    { title = "串口设置", icon = "device", id = "settings_serial", mount = require("settings_serial").mount },
}

function M.create(context)
    local display = context.config.display
    local layout = ui.layout(display)
    local p = layout.px
    local page = { alive = true }
    page.root = airui.container({ x = 0, y = 0, w = display.width, h = display.height,
        color = theme.background })
    local canvas = airui.container({ parent = page.root, x = layout.x, y = layout.y,
        w = p(1024), h = p(600), color = theme.background })
    local header = ui.box(canvas, layout, 0, 0, 1024, 88, theme.header)
    require("ui_brand").create(header, layout, context.config.brand)
    ui.box(header, layout, 282, 27, 1, 34, theme.border)
    ui.label(header, layout, "系统设置", 307, 20, 380, 35, 25)
    ui.label(header, layout, "智易时代 · 终端管理", 308, 55, 380, 24, 13, theme.secondary)
    ui.box(canvas, layout, 0, 88, 1024, 1, theme.border)

    local nav = ui.box(canvas, layout, 34, 109, 233, 466, theme.surface, 12, theme.border)
    -- 独立滚动容器。新增菜单超出可见高度后，可上下滑动查看。
    local menu = ui.box(nav, layout, 9, 12, 212, 440, theme.surface)
    local content = ui.box(canvas, layout, 288, 109, 702, 466, theme.surface, 12, theme.border)
    local buttons = {}
    local selected, pane, unmount, pending

    local function open(index)
        if selected == index then return end
        if unmount then unmount() end
        if pane then pane:destroy() end
        selected = index
        for i, row in ipairs(buttons) do
            row:set_color(i == index and theme.status_background or theme.surface)
        end
        -- 面板可返回清理函数，用于解除订阅或提交待保存值。
        pane = ui.box(content, layout, 0, 0, 700, 464, theme.surface)
        unmount = sections[index].mount(pane, layout, context)
        log.info("settings", "SETTINGS_PANEL", sections[index].id)
    end

    -- 和其他页面一样，在点击处理结束后再切换界面，避免销毁正在处理事件的控件。
    local function defer(action)
        if not page.alive or pending then return end
        pending = sys.timerStart(function()
            pending = nil
            if page.alive then action() end
        end, 1)
    end

    for index, section in ipairs(sections) do
        local function select() defer(function() open(index) end) end
        local row = ui.box(menu, layout, 0, (index - 1) * 66, 200, 56, theme.surface, 8, nil, select)
        buttons[index] = row
        local badge = ui.box(row, layout, 9, 10, 36, 36, theme.tones.blue.background, 8, nil, select)
        icons.draw(badge, layout, section.icon, 6, 6, 24, theme.clock)
        ui.label(row, layout, section.title, 54, 16, 142, 26, 17, theme.text, nil, select)
    end
    widgets.button(canvas, layout, "返回主页", 864, 27, 120, 36,
        function() defer(function() router.open("home") end) end)
    open(1)

    function page:destroy()
        self.alive = false
        if pending then sys.timerStop(pending) end
        if unmount then unmount() end
        self.root:destroy()
    end
    return page
end

return M
