-- 采集通道设置。因子配置在三页间共享草稿，只有保存才应用到采集任务。
local ui = require("ui_components")
local theme = require("ui_theme")
local widgets = require("settings_widgets")
local data = require("env_data")
local channels = require("channel_store")
local serial_cfg = require("modbus_serial_cfg")
local M = {}
local number_editor = require("settings_number")
local function number_text(value)
    if value == math.floor(value) then return string.format("%.0f", value) end
    return tostring(value)
end

function M.mount(parent, layout)
    local p = layout.px
    ui.label(parent, layout, "采集通道", 24, 14, 290, 36, 26)
    ui.label(parent, layout, "监测因子", 24, 72, 84, 31, 16, theme.secondary)
    local status = ui.label(parent, layout, "", 24, 429, 448, 26, 15, theme.muted)
    if not (airui.tabview and airui.dropdown) then
        status:set_text("当前固件缺少采集通道控件")
        return
    end

    local current, refresh
    local _, serial = channels.edit(data.metrics[1].id)
    local drafts, controls, options = {}, {}, {}
    local syncing, keypad, close_timer = false, nil, nil
    local number_format = {slave = function(v) return string.format("0x%02X", v) end}
    local style = {
        bg_color = theme.surface_reserved, text_color = theme.text, border_color = theme.border,
        border_width = p(1), list_bg_color = theme.surface, list_text_color = theme.text,
        list_selected_bg_color = theme.status_background, list_selected_text_color = theme.clock,
    }
    local function dropdown(parent_box, x, y, w, h, labels, callback, selected)
        return airui.dropdown({parent = parent_box, x = p(x), y = p(y), w = p(w), h = p(h),
            options = labels, default_index = selected or 0, style = style, on_change = callback})
    end
    local names, initial = {}, 1
    for index, metric in ipairs(data.metrics) do
        names[index] = metric.name .. "  /  " .. metric.id
        if metric.id == "temperature" then initial = index end
    end

    -- 标题区保留因子选择；下方三个选项卡只显示选中因子的字段。
    local selector = dropdown(parent, 110, 67, 280, 39, names, function(control)
        if syncing or not current then return end
        local metric = data.metrics[control:get_selected() + 1]
        if metric then current = metric; refresh() end
    end, initial - 1)
    ui.label(parent, layout, "UART1  /  RS485", 465, 73, 186, 24, 15, theme.clock, airui.TEXT_ALIGN_RIGHT)
    ui.box(parent, layout, 24, 119, 652, 1, theme.border)
    local tabs = airui.tabview({parent = parent, x = p(24), y = p(130), w = p(652), h = p(290),
        tabs = {"基本参数", "Modbus 协议", "量程限值"}, switch_mode = "jump", bg_color = theme.surface})
    local basic, modbus, limit = tabs:get_content(0), tabs:get_content(1), tabs:get_content(2)
    local function dirty()
        status:set_text("配置已编辑，保存后生效")
    end
    local function value_of(key, shared)
        return (shared and serial or drafts[current.id])[key]
    end
    local function set_value(key, value, shared)
        local target = shared and serial or drafts[current.id]
        target[key] = value
        dirty()
    end
    local function field_label(panel, text, x, y, width)
        ui.label(panel, layout, text, x, y + 5, width, 25, 15, theme.secondary)
    end

    -- 数字控件只进入编辑器。草稿在切换选项卡或因子时保留，返回系统菜单时自动丢弃。
    local function number(panel, key, title, x, y, width, kind)
        field_label(panel, title, x, y, width - 3)
        local format = number_format[key] or number_text
        local entry = widgets.button(panel, layout, "", x + width, y, 154, 30, function()
            if keypad then return end
            keypad = number_editor.open(parent, layout, title, value_of(key), kind, function(value, layer)
                if close_timer then return end
                if value ~= nil then
                    set_value(key, value)
                    controls[key]:set_text(format(value))
                end
                close_timer = sys.timerStart(function()
                    close_timer, keypad = nil, nil
                    layer:destroy()
                end, 1)
            end)
        end)
        controls[key] = entry
    end

    local function select_field(panel, key, title, values, labels, x, y, width, shared)
        field_label(panel, title, x, y, width - 3)
        local items = {}
        for index, value in ipairs(values) do items[index] = labels and labels[index] or tostring(value) end
        controls[key] = dropdown(panel, x + width, y, 164, 30, items, function(control)
            if not syncing then
                local value = values[control:get_selected() + 1]
                if value ~= nil then set_value(key, value, shared) end
            end
        end)
        options[key] = {values = values, shared = shared}
    end

    field_label(basic, "启用采集与显示", 10, 4, 210)
    local enabled = airui.switch({parent = basic, x = p(252), y = p(4), w = p(74), h = p(32),
        on_change = function(control)
            if not syncing then set_value("enabled", control:get_state()) end
        end})
    field_label(basic, "监测因子", 10, 47, 113)
    local factor_id = ui.label(basic, layout, "", 125, 50, 162, 26, 17)
    field_label(basic, "因子名称", 320, 47, 118)
    local factor_name = ui.label(basic, layout, "", 440, 50, 181, 26, 17)
    select_field(basic, "decimals", "数据小数位", {0, 1, 2, 3, 4, 5, 6}, nil, 10, 88, 133)
    ui.label(basic, layout, "启用后采集并显示。采样周期在系统参数中统一设置。", 10, 141, 605, 26, 14, theme.muted)

    ui.label(modbus, layout, "RS485 公共串口参数", 10, 0, 295, 23, 15, theme.clock)
    ui.label(modbus, layout, "当前因子的读取参数", 321, 0, 298, 23, 15, theme.clock)
    for index, item in ipairs(serial_cfg.fields) do
        select_field(modbus, item.key, item.label, item.options, item.labels, 10, 24 + (index - 1) * 34, 107, true)
    end
    ui.label(modbus, layout, "所有启用因子共用串口格式", 10, 163, 298, 22, 13, theme.muted)
    ui.label(modbus, layout, "起始地址填报文偏移，首地址为 0", 10, 181, 298, 22, 13, theme.muted)
    number(modbus, "slave", "从站地址", 321, 24, 128, "hex")
    select_field(modbus, "function_code", "功能码", channels.functions, channels.function_labels, 321, 58, 128)
    number(modbus, "address", "起始寄存器地址", 321, 92, 128)
    number(modbus, "count", "寄存器／位数量", 321, 126, 128)
    select_field(modbus, "data_type", "数据类型", channels.types, channels.type_labels, 321, 160, 128)

    number(limit, "min", "量程最小值", 10, 16, 130, "decimal")
    number(limit, "max", "量程最大值", 321, 16, 130, "decimal")
    number(limit, "alarm_low", "告警下限", 10, 60, 130, "decimal")
    number(limit, "alarm_high", "告警上限", 321, 60, 130, "decimal")
    number(limit, "alarm_delay", "超限延时 (次)", 10, 104, 130)
    ui.label(limit, layout, "表格按本次读数显示状态。连续超限达到设定次数后记录告警。",
        10, 155, 610, 25, 14, theme.muted)

    refresh = function()
        syncing = true
        local id = current.id
        if not drafts[id] then drafts[id] = channels.edit(id) end
        local values = drafts[id]
        enabled:set_state(values.enabled)
        factor_id:set_text(id)
        factor_name:set_text(current.name)
        for key, control in pairs(controls) do
            local option = options[key]
            if option then
                for index, value in ipairs(option.values) do
                    if value == value_of(key, option.shared) then control:set_selected(index - 1); break end
                end
            else
                control:set_text((number_format[key] or number_text)(values[key]))
            end
        end
        status:set_text("选择因子后编辑，保存配置生效")
        syncing = false
        log.info("channels", "CHANNEL_SELECTED", id)
    end
    current = data.metrics[selector:get_selected() + 1] or data.metrics[initial]
    refresh()
    widgets.button(parent, layout, "保存通道", 500, 425, 174, 32, function()
        local ok, err = channels.save(current.id, drafts[current.id], serial)
        status:set_text(ok and "已保存 · " .. current.name or err)
    end, true)
    return function()
        if close_timer then sys.timerStop(close_timer) end
    end
end

return M
