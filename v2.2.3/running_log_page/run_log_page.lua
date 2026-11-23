-- 运行日志页。日期和起止时间先作为草稿，点击「查询」才读取并替换结果。
local ui = require("ui_components")
local theme = require("ui_theme")
local widgets = require("settings_widgets")
local icons = require("ui_icons")
local router = require("ui_router")
local picker_ui = require("run_log_picker")
local history = require("run_log_model")
local M = {}

local ROWS_PER_PAGE = 45
local ROW_HEIGHT = 35
local columns = {
    {"时间", 15, 264}, {"参数名称", 302, 210}, {"测量值", 532, 124},
    {"单位", 671, 109}, {"状态", 808, 113},
}

function M.create(context)
    local display = context.config.display
    local layout = ui.layout(display)
    local p, center = layout.px, airui.TEXT_ALIGN_CENTER
    local page = {alive = true, timers = {}}
    local date = context.clock.local_date()
    date.year = math.max(2000, math.min(2099, date.year))
    local draft = {date = date, first = 0, last = 1439}
    local result, current_page, applied
    local querying = false
    local query_button, previous_button, next_button

    page.root = airui.container({x = 0, y = 0, w = display.width, h = display.height, color = theme.background})
    local canvas = airui.container({parent = page.root, x = layout.x, y = layout.y, w = p(1024), h = p(600),
        color = theme.background})
    local picker = picker_ui.create(canvas, layout)

    -- LVGL 正在派发点击事件时不销毁对象，待回调结束后再切页或重建。
    local function defer(action)
        if not page.alive then return end
        local timer
        timer = sys.timerStart(function()
            page.timers[timer] = nil
            if page.alive then action() end
        end, 1)
        if timer then page.timers[timer] = true end
    end
    picker.defer = defer
    local function button(parent, text, x, y, w, h, action, primary)
        return widgets.button(parent, layout, text, x, y, w, h, function() defer(action) end, primary)
    end

    local header = ui.box(canvas, layout, 0, 0, 1024, 88, theme.header)
    require("ui_brand").create(header, layout, context.config.brand)
    ui.box(header, layout, 282, 27, 1, 34, theme.border)
    ui.label(header, layout, "运行日志", 307, 20, 352, 33, 25, theme.text)
    ui.label(header, layout, "环境监测历史", 308, 55, 352, 24, 13, theme.secondary)
    button(header, "返回主页", 747, 25, 112, 39, function() router.open("home") end)
    ui.box(canvas, layout, 0, 88, 1024, 1, theme.border)

    local filters = ui.box(canvas, layout, 40, 106, 944, 81, theme.surface, 12, theme.border)
    ui.label(filters, layout, "查询日期", 18, 10, 174, 23, 14, theme.secondary)
    ui.label(filters, layout, "起始时间", 252, 10, 178, 23, 14, theme.secondary)
    ui.label(filters, layout, "终止时间", 453, 10, 178, 23, 14, theme.secondary)
    local status = ui.label(canvas, layout, "请选择日期和时间范围，再点击查询", 42, 191, 939, 25, 14, theme.muted)

    local date_text, first_button, last_button
    local function update_draft()
        date_text:set_text(history.date_label(draft.date, "-"))
        first_button:set_text(history.time_label(draft.first))
        last_button:set_text(history.time_label(draft.last))
        status:set_text("点击查询应用当前日期和时间范围")
        status:set_color(theme.muted)
    end
    local function open_date()
        defer(function()
            picker:date(draft.date, function(value)
                draft.date = value
                update_draft()
            end)
        end)
    end
    local date_box = ui.box(filters, layout, 18, 35, 203, 36, theme.status_background, 8, nil, open_date)
    -- 图标、文字和底板都可点击。图标居于左侧，点按区域覆盖整个日期字段。
    icons.draw(date_box, layout, "calendar", 9, 5, 25, theme.clock)
    date_text = ui.label(date_box, layout, history.date_label(draft.date, "-"), 46, 5, 148, 28, 17,
        theme.clock, airui.TEXT_ALIGN_LEFT, open_date)
    local function edit_time(field, title)
        picker:time(title, draft[field], function(value)
            draft[field] = value
            update_draft()
        end)
    end
    first_button = button(filters, history.time_label(draft.first), 252, 35, 178, 36,
        function() edit_time("first", "选择起始时间") end)
    last_button = button(filters, history.time_label(draft.last), 453, 35, 178, 36,
        function() edit_time("last", "选择终止时间") end)

    local panel = ui.box(canvas, layout, 40, 223, 944, 323, theme.surface, 12, theme.border)
    local headings = ui.box(panel, layout, 0, 0, 942, 33, 0xE8F3FC)
    for _, column in ipairs(columns) do
        ui.label(headings, layout, column[1], column[2], 5, column[3], 26, 15, theme.secondary, center)
    end
    local viewport
    local applied_text = ui.label(canvas, layout, "", 42, 557, 515, 29, 14, theme.muted)
    local progress = ui.label(canvas, layout, "", 558, 558, 210, 29, 14, theme.secondary, airui.TEXT_ALIGN_RIGHT)

    -- 长查询用分页控制 LVGL 对象数量。每页的表体可以上下滚动，表头留在原位。
    local function render(page_number, empty_text)
        if viewport then viewport:destroy() end
        viewport = ui.box(panel, layout, 0, 33, 942, 288, theme.surface)
        local count = result and result.count or 0
        local pages = math.max(1, math.ceil(count / ROWS_PER_PAGE))
        current_page = math.max(1, math.min(page_number, pages))
        previous_button:set_disabled(current_page == 1)
        next_button:set_disabled(current_page == pages)
        progress:set_text(count > 0 and string.format("%d 条 · %d / %d 页", count, current_page, pages) or "")
        applied_text:set_text(applied and string.format("查询范围  %s  %s 至 %s", applied.date,
            history.time_label(applied.first), history.time_label(applied.last)) or "")
        if count == 0 then
            ui.label(viewport, layout, empty_text or "该时间范围内暂无有效监测数据", 0, 111, 942, 34, 18, theme.muted, center)
            return
        end
        local first = (current_page - 1) * ROWS_PER_PAGE + 1
        for index = first, math.min(first + ROWS_PER_PAGE - 1, count) do
            local values = history.row(result, index)
            local row = ui.box(viewport, layout, 0, (index - first) * ROW_HEIGHT, 928, ROW_HEIGHT,
                index % 2 == 0 and 0xF5F9FD or theme.surface)
            for column_index, column in ipairs(columns) do
                local value = values[column_index]
                local color = theme.text
                if column_index == 5 then color = value == "超标" and 0xBD2432 or 0x16753D end
                ui.label(row, layout, value, column[2], 5, column[3], 27, 16, color, center)
            end
        end
        log.info("history", "HISTORY_PAGE", current_page, pages, first)
    end

    previous_button = button(canvas, "上一页", 781, 552, 95, 38, function() render(current_page - 1) end)
    next_button = button(canvas, "下一页", 889, 552, 95, 38, function() render(current_page + 1) end)
    local function query()
        if querying then return end
        local range, reason = history.range(draft.date, draft.first, draft.last)
        if not range then
            status:set_text(reason)
            status:set_color(0xBD2432)
            log.info("history", "HISTORY_QUERY_INVALID", reason)
            return
        end
        querying = true
        query_button:set_disabled(true)
        status:set_text("正在读取历史数据…")
        status:set_color(theme.clock)
        local pc = context.network.snapshot().pc
        sys.taskInit(function()
            local queried, issue = history.query(range, pc, function() return not page.alive end)
            if not page.alive then return end
            querying, result, applied = false, queried, range
            query_button:set_disabled(false)
            if not result then
                status:set_text(issue or "读取日志失败")
                status:set_color(0xBD2432)
                log.warn("history", "HISTORY_QUERY_FAILED", range.day, issue)
            else
                status:set_text("查询完成")
                status:set_color(theme.success)
                log.info("history", "HISTORY_QUERY", range.day, history.time_label(range.first),
                    history.time_label(range.last), result.count)
            end
            render(1, issue)
        end)
    end
    query_button = button(header, "查询", 875, 25, 109, 39, query, true)
    render(1, "查询结果将在此显示")

    -- 滚轮只在弹窗内处理手势。表体仍使用 AirUI 容器自身的上下滑动。
    if airui.touch_subscribe then
        airui.touch_subscribe(function(event, x, y, track)
            if page.alive then
                picker:touch(event, (x - layout.x) / layout.scale, (y - layout.y) / layout.scale, track)
            end
        end)
    end
    function page:destroy()
        self.alive = false
        if airui.touch_unsubscribe then airui.touch_unsubscribe() end
        for timer in pairs(self.timers) do sys.timerStop(timer) end
        self.root:destroy()
    end
    log.info("history", "HISTORY_READY")
    return page
end

return M
