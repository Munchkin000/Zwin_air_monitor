-- 日期弹窗和时分滚轮属于查询条件，只将选中的值交给页面草稿。
local ui = require("ui_components")
local theme = require("ui_theme")
local widgets = require("settings_widgets")
local calendar = require("settings_calendar")
local M = {}
local center = function() return airui.TEXT_ALIGN_CENTER end

function M.create(canvas, layout)
    local picker = {}
    local overlay, wheels, drag

    function picker:close()
        drag, wheels = nil, nil
        if overlay then overlay:destroy(); overlay = nil end
    end

    local function panel(width, height)
        picker:close()
        overlay = ui.box(canvas, layout, 0, 0, 1024, 600, 0xDCEBF7)
        local x, y = (1024 - width) / 2, (600 - height) / 2
        return ui.box(overlay, layout, x, y, width, height, theme.surface, 16, theme.border), x, y
    end

    -- 页面统一在点击回调返回后打开、关闭或重建弹窗控件。
    local function button(parent, text, x, y, w, h, action, primary)
        return widgets.button(parent, layout, text, x, y, w, h, function()
            picker.defer(action)
        end, primary)
    end

    function picker:date(selected, commit)
        local dialog = panel(510, 448)
        ui.label(dialog, layout, "选择查询日期", 24, 14, 458, 34, 23, theme.text)
        local title = ui.label(dialog, layout, "", 161, 62, 186, 34, 20, theme.clock, center())
        local year, month = selected.year, selected.month
        local grid
        local function render()
            if grid then grid:destroy() end
            grid = ui.box(dialog, layout, 23, 139, 462, 251, theme.surface)
            title:set_text(string.format("%04d 年 %02d 月", year, month))
            local epoch = calendar.to_utc({year = year, month = month, day = 1, hour = 0, min = 0, sec = 0}, 0)
            local offset = (os.date("!*t", epoch).wday + 5) % 7 -- 一周从星期一开始。
            for day = 1, calendar.days_in_month(year, month) do
                local slot = offset + day - 1
                local is_selected = year == selected.year and month == selected.month and day == selected.day
                button(grid, tostring(day), slot % 7 * 66 + 4, slot // 7 * 41 + 2, 58, 37, function()
                    picker:close()
                    commit({year = year, month = month, day = day})
                end, is_selected)
            end
        end
        local function move(delta)
            local month_index = math.max(2000 * 12, math.min(2099 * 12 + 11, year * 12 + month - 1 + delta))
            year, month = month_index // 12, month_index % 12 + 1
            render()
        end
        button(dialog, "年-", 26, 61, 55, 35, function() move(-12) end)
        button(dialog, "月-", 91, 61, 55, 35, function() move(-1) end)
        button(dialog, "月+", 361, 61, 55, 35, function() move(1) end)
        button(dialog, "年+", 426, 61, 55, 35, function() move(12) end)
        for index, name in ipairs({"一", "二", "三", "四", "五", "六", "日"}) do
            ui.label(dialog, layout, name, 27 + (index - 1) * 66, 110, 58, 25, 15, theme.secondary, center())
        end
        button(dialog, "取消", 364, 396, 116, 36, function() picker:close() end)
        render()
    end

    function picker:time(title, minutes, commit)
        local dialog, left, top = panel(438, 328)
        ui.label(dialog, layout, title, 26, 15, 382, 32, 23, theme.text)
        wheels = {}
        local function wheel(x, name, value, limit)
            local y, width, height = 92, 148, 137
            local box = ui.box(dialog, layout, x, y, width, height, theme.background, 8)
            ui.label(dialog, layout, name, x, 57, width, 29, 16, theme.secondary, center())
            ui.box(box, layout, 3, 46, 142, 44, theme.status_background, 7)
            local wheel_state = {value = value, x = left + x, y = top + y, width = width, height = height}
            local labels = {}
            for index = 1, 3 do
                local action
                if not airui.touch_subscribe and index ~= 2 then
                    action = function() wheel_state.adjust(index - 2) end
                end
                labels[index] = ui.label(box, layout, "", 0, (index - 1) * 45 + 4,
                    width, 37, index == 2 and 27 or 18, index == 2 and theme.clock or theme.muted, center(), action)
            end
            function wheel_state.adjust(delta)
                wheel_state.value = (wheel_state.value + delta) % limit
                for index, label in ipairs(labels) do
                    label:set_text(string.format("%02d", (wheel_state.value + index - 2) % limit))
                end
            end
            wheel_state.adjust(0)
            wheels[#wheels + 1] = wheel_state
        end
        wheel(50, "小时", minutes // 60, 24)
        wheel(239, "分钟", minutes % 60, 60)
        button(dialog, "取消", 52, 259, 152, 40, function() picker:close() end)
        button(dialog, "确定", 232, 259, 152, 40, function()
            local value = wheels[1].value * 60 + wheels[2].value
            picker:close()
            commit(value)
        end, true)
    end

    -- 只接管在滚轮内开始的手势，上划递增、下划递减，点击相邻数字也可步进。
    function picker:touch(event, x, y, track)
        if not wheels then return end
        if event == airui.TP_DOWN then
            drag = nil
            for _, wheel in ipairs(wheels) do
                if x >= wheel.x and x < wheel.x + wheel.width and y >= wheel.y and y < wheel.y + wheel.height then
                    drag = {wheel = wheel, track = track, y = y}
                    break
                end
            end
        elseif event == airui.TP_UP and drag and drag.track == track then
            local wheel, start = drag.wheel, drag.y
            drag = nil
            local distance = start - y
            if math.abs(distance) >= 18 then
                local steps = math.max(1, math.floor(math.abs(distance) / 34 + 0.5))
                wheel.adjust(distance > 0 and steps or -steps)
            elseif start < wheel.y + 45 then
                wheel.adjust(-1)
            elseif start >= wheel.y + 90 then
                wheel.adjust(1)
            end
        end
    end
    return picker
end

return M
