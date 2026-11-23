-- 环境监测页由可切换的仪表和纵向滚动数据表组成。
local ui = require("ui_components")
local theme = require("ui_theme")
local data = require("env_data")
local Gauge = require("env_gauge")
local router = require("ui_router")
local state = require("env_store") -- 数据状态跨页面保留。
local channels = require("channel_store")
local M = {}
local NORMAL_COLOR = 0x16753D
local EXCEEDED_COLOR = 0xBD2432

-- 状态反映当前读数与告警上下限的比较，延时告警由采集状态独立判定。
local function reading_status(metric, value)
    if type(value) ~= "number" then return "--", theme.muted end
    if value < metric.alarm_low or value > metric.alarm_high then return "超标", EXCEEDED_COLOR end
    return "正常", NORMAL_COLOR
end

function M.create(context)
    local layout = ui.layout(context.config.display)
    local p = layout.px
    local page = { alive = true, gauges = {}, pending = {}, cells = {} }
    local drag
    local is_pc = context.network.snapshot().pc
    local display_metrics = {}

    -- 因子名称和单位来自字典，量程和精度使用已保存的通道值。
    local function load_display_metrics()
        local _, settings = channels.snapshot()
        for index, base in ipairs(data.metrics) do
            local config, metric = settings[base.id], {}
            for key, value in pairs(base) do metric[key] = value end
            metric.min, metric.max, metric.decimals = config.min, config.max, config.decimals
            metric.alarm_low, metric.alarm_high = config.alarm_low, config.alarm_high
            display_metrics[index] = metric
        end
    end
    load_display_metrics()
    page.root = airui.container({ x = 0, y = 0, w = context.config.display.width,
        h = context.config.display.height, color = theme.background })
    local canvas = airui.container({ parent = page.root, x = layout.x, y = layout.y,
        w = p(1024), h = p(600), color = theme.background })
    local function label(parent, text, x, y, w, h, size, color, align)
        return ui.label(parent, layout, text, x, y, w, h, size, color, align)
    end
    -- 涉及销毁或重建控件的操作延迟执行，离开页面时停止待处理计时器。
    function page:defer(action)
        local timer
        timer = sys.timerStart(function()
            page.pending[timer] = nil
            if page.alive then action() end
        end, 1)
        if timer then page.pending[timer] = true end
    end
    local function button(text, x, y, w, h, action, primary, size)
        return airui.button({ parent = canvas, text = text, x = p(x), y = p(y), w = p(w), h = p(h),
            font = "hzfont", font_size = p(size or 17),
            style = { pad = 0, radius = p(8), border_width = 0, shadow_width = 0,
                bg_color = primary and theme.accent or 0xE5F1FB,
                text_color = primary and 0xFFFFFF or theme.clock },
            on_click = function()
                if not page.alive then return end
                page:defer(action)
            end })
    end

    local header = ui.box(canvas, layout, 0, 0, 1024, 88, theme.header)
    page.logo = require("ui_brand").create(header, layout, context.config.brand)
    ui.box(header, layout, 282, 27, 1, 34, theme.border)
    label(header, "环境监测", 307, 20, 360, 33, 25, theme.text)
    label(header, "智易时代 · 环境数据看板", 308, 55, 360, 24, 13, theme.secondary)
    local badge = ui.box(header, layout, 704, 29, 130, 32, 0xFFF3DB, 16)
    local mode = label(badge, "演示数据", 0, 5, 130, 24, 14, 0xA36B14, airui.TEXT_ALIGN_CENTER)
    button("返回主页", 864, 27, 120, 36, function() router.open("home") end, false, 16)
    ui.box(canvas, layout, 0, 88, 1024, 1, theme.border)

    ui.box(canvas, layout, 40, 107, 4, 19, theme.accent, 2)
    label(canvas, "监测仪表", 54, 101, 110, 30, 19, theme.text)
    local count = label(canvas, "", 166, 105, 160, 24, 14, theme.secondary)
    local hint = label(canvas, "左右滑动查看", 367, 106, 475, 24, 13, theme.muted)
    local left, right, pager
    local viewport = ui.box(canvas, layout, 40, 140, 944, 176, theme.background)
    local empty = label(viewport, "暂无启用因子，请在系统设置的采集通道配置", 0, 68, 944, 40, 21,
        theme.muted, airui.TEXT_ALIGN_CENTER)

    -- 选择或窗口范围变化时重建可见的四个仪表，并更新页码和按钮状态。
    function page:refresh_gauges()
        for _, gauge in ipairs(self.gauges) do gauge:destroy() end
        self.gauges = {}
        empty:set_text(#state.selected == 0 and "暂无启用因子，请在系统设置的采集通道配置" or "")
        for slot = 0, 3 do
            local index = state.selected[state.first + slot]
            if index then
                local metric = display_metrics[index]
                local gauge = Gauge.create(viewport, layout, metric, state.values[metric.id], slot * 240)
                gauge.metric_id = metric.id
                self.gauges[#self.gauges + 1] = gauge
            end
        end
        count:set_text(string.format("已显示 %d / %d", #state.selected, #data.metrics))
        pager:set_text(#state.selected == 0 and "尚未添加仪表" or
            string.format("第 %d - %d 项 / 共 %d 项", state.first, math.min(state.first + 3, #state.selected), #state.selected))
        left:set_disabled(state.first <= 1)
        right:set_disabled(state.first >= state:last_first())
        log.info("environment", "GAUGES", #state.selected, "FIRST", state.first, "IDS", table.concat(state.selected, ","))
    end
    function page:slide(direction)
        if state:slide(direction) then self:refresh_gauges() end
    end
    left = button("<", 40, 322, 32, 24, function() page:slide(-1) end, false, 18)
    right = button(">", 952, 322, 32, 24, function() page:slide(1) end, false, 18)
    pager = label(canvas, "", 332, 323, 360, 24, 13, theme.secondary, airui.TEXT_ALIGN_CENTER)
    label(canvas, "弧线仅表示配置量程比例", 84, 326, 250, 21, 12, theme.muted)

    ui.box(canvas, layout, 40, 356, 4, 18, theme.accent, 2)
    label(canvas, "监测数据明细 · 上下滑动查看", 54, 350, 480, 28, 18, theme.text)
    local source_hint = label(canvas, "静态默认值预览 · 尚未接入传感器", 624, 353, 360, 24, 13,
        theme.muted, airui.TEXT_ALIGN_RIGHT)
    local table_root = ui.box(canvas, layout, 40, 378, 944, 214, theme.surface, 12, theme.border)
    local table_header = ui.box(table_root, layout, 0, 0, 942, 28, 0xE8F3FC)
    local columns = {
        { "序号", 14, 40 }, { "监测项目", 78, 250 },
        { "数值", 360, 150 }, { "单位", 568, 140 }, { "数据状态", 770, 146 },
    }
    for _, column in ipairs(columns) do
        label(table_header, column[1], column[2], 3, column[3], 24, 14,
            theme.secondary, airui.TEXT_ALIGN_CENTER)
    end
    -- 按启用因子统计当前数据来源，区分真机待采集和 PC 演示值。
    local function refresh_provenance()
        local total, received = #state.selected, 0
        for _, index in ipairs(state.selected) do
            if state.received[display_metrics[index].id] then received = received + 1 end
        end
        if total == 0 then
            mode:set_text("未启用因子")
            source_hint:set_text("")
        elseif received == 0 then
            mode:set_text(is_pc and "演示数据" or "待采集")
            source_hint:set_text(is_pc and "PC 仿真默认读数" or "等待启用通道的有效读数")
        else
            mode:set_text(received == total and "数据已接入" or "部分数据")
            source_hint:set_text("仪表与数据表同步更新")
        end
    end

    -- 表头固定，数据行在内层容器中上下滚动。选择变化时重建表体并回到首行。
    function page:refresh_table()
        if self.table_body then self.table_body:destroy() end
        self.table_body = ui.box(table_root, layout, 0, 28, 942, 184, theme.surface)
        self.cells = {}
        if #state.selected == 0 then
            label(self.table_body, "暂无启用因子", 0, 70, 942, 32, 17,
                theme.muted, airui.TEXT_ALIGN_CENTER)
        end
        -- 表格列出全部已选项，顺序与仪表一致。横向翻看仪表时无需重建表格。
        for row_number, index in ipairs(state.selected) do
            local metric = display_metrics[index]
            local row = ui.box(self.table_body, layout, 0, (row_number - 1) * 30, 926, 30,
                row_number % 2 == 0 and 0xF5F9FD or theme.surface)
            label(row, string.format("%02d", row_number), 14, 4, 40, 24, 14, theme.muted, airui.TEXT_ALIGN_CENTER)
            local title = metric.name .. (metric.name ~= metric.symbol and " (" .. metric.symbol .. ")" or "")
            label(row, title, 78, 4, 250, 24, 16, theme.text)
            local reading = state.values[metric.id]
            local value = label(row, data.format(metric, reading), 360, 3, 150, 26, 18,
                theme.clock, airui.TEXT_ALIGN_CENTER)
            label(row, metric.unit, 568, 4, 140, 24, 14, theme.secondary, airui.TEXT_ALIGN_CENTER)
            local status_text, status_color = reading_status(metric, reading)
            local status = label(row, status_text, 770, 4, 146, 24, 14,
                status_color, airui.TEXT_ALIGN_CENTER)
            self.cells[metric.id] = { value = value, status = status }
        end
        refresh_provenance()
    end

    -- 数据事件到达时刷新已有标签和表盘，保留表格滚动位置。
    local function update_values()
        if not page.alive then return end
        refresh_provenance()
        for _, index in ipairs(state.selected) do
            local metric = display_metrics[index]
            local cell = page.cells[metric.id]
            local reading = state.values[metric.id]
            local status_text, status_color = reading_status(metric, reading)
            cell.value:set_text(data.format(metric, reading))
            cell.status:set_text(status_text)
            cell.status:set_color(status_color)
        end
        for _, gauge in ipairs(page.gauges) do gauge:update(state.values[gauge.metric_id]) end
    end
    local function update_channels()
        if not page.alive then return end
        load_display_metrics()
        page:refresh_table()
        page:refresh_gauges()
    end
    sys.subscribe("ENVIRONMENT_CHANGED", update_values)
    sys.subscribe("ENVIRONMENT_CONFIG_CHANGED", update_channels)

    -- 横向手势仅从仪表区域开始。坐标先换算到基准画布。
    if airui.touch_subscribe then
        airui.touch_subscribe(function(event, x, y, track)
            if not page.alive then return end
            local lx, ly = (x - layout.x) / layout.scale, (y - layout.y) / layout.scale
            if event == airui.TP_DOWN then
                if lx >= 40 and lx <= 984 and ly >= 140 and ly <= 316 then
                    drag = { x = lx, y = ly, track = track }
                end
            elseif drag and drag.track == track and event == airui.TP_HOLD then
                if math.abs(lx - drag.x) > 42 then
                    hint:set_text(lx < drag.x and "松开查看后一项" or "松开查看前一项")
                end
            elseif drag and drag.track == track and event == airui.TP_UP then
                local dx, dy = lx - drag.x, ly - drag.y
                drag = nil
                hint:set_text("左右滑动查看")
                -- 要求横向位移足够且明显大于纵向位移，避免手指轻微抖动造成切换。
                if math.abs(dx) > 42 and math.abs(dx) > math.abs(dy) * 1.3 then
                    local direction = dx < 0 and 1 or -1
                    log.info("environment", "SWIPE", direction)
                    local timer
                    timer = sys.timerStart(function()
                        page.pending[timer] = nil
                        if page.alive then page:slide(direction) end
                    end, 1)
                    if timer then page.pending[timer] = true end
                end
            end
        end)
    end
    -- 数据缓存独立运行。离开时只清理当前页面的订阅和待执行操作。
    function page:destroy()
        self.alive = false
        drag = nil
        sys.unsubscribe("ENVIRONMENT_CHANGED", update_values)
        sys.unsubscribe("ENVIRONMENT_CONFIG_CHANGED", update_channels)
        if airui.touch_unsubscribe then airui.touch_unsubscribe() end
        for timer in pairs(self.pending) do sys.timerStop(timer) end
        self.pending = {}
        self.root:destroy()
        self.table_body = nil
        self.gauges, self.cells = {}, {}
    end
    page:refresh_table()
    page:refresh_gauges()
    log.info("environment", "ENVIRONMENT_READY", #data.metrics)
    return page
end
return M
