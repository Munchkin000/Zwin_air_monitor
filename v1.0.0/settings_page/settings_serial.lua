-- 串口面板编辑 Air8603M1 的 UART1 参数。保存前的调整仅保留在当前面板。
local ui = require("ui_components")
local theme = require("ui_theme")
local widgets = require("settings_widgets")
local store = require("settings_store")
local config = require("modbus_serial_cfg")
local M = {}

function M.mount(parent, layout, context)
    local p = layout.px
    local pc = context.network.snapshot().pc
    local saved = store.modbus_serial()
    widgets.heading(parent, layout, "串口设置", "UART1 · RS485 Modbus RTU · 参数需与传感器一致")
    local status = ui.label(parent, layout, "修改后点击保存", 36, 425, 628, 26, 15, theme.muted)
    if not airui.dropdown then
        status:set_text("当前 AirUI 固件缺少串口设置控件")
        return
    end

    local fields = {}
    local edited = false
    local function mark_edited()
        edited = true
        status:set_text("配置已编辑 · 保存后生效")
    end
    local control_style = {
        bg_color = theme.surface_reserved, text_color = theme.text, border_color = theme.border,
        border_width = p(1), list_bg_color = theme.surface, list_text_color = theme.text,
        list_selected_bg_color = theme.status_background, list_selected_text_color = theme.clock,
    }

    -- 0x 和 ms 都是固定标签，输入框仅显示可以通过键盘编辑的数字。
    ui.label(parent, layout, "通信地址", 40, 115, 160, 27, 18, theme.secondary)
    ui.label(parent, layout, "0x", 222, 114, 32, 28, 19, theme.text)
    ui.label(parent, layout, "读取周期", 380, 115, 93, 27, 18, theme.secondary)
    ui.label(parent, layout, "ms", 632, 114, 30, 28, 17, theme.text)
    local address = { text = string.format("%02X", saved.slave), limit = 2 }
    local interval = { text = tostring(saved.interval_ms), limit = #tostring(config.max_interval_ms) }
    local active_keypad
    local function hide_keypad()
        if active_keypad then
            active_keypad:set_hidden(true)
            active_keypad = nil
        end
    end

    local function input_field(input, x, width)
        input.control = airui.button({
            parent = parent, x = p(x), y = p(105), w = p(width), h = p(42), text = input.text,
            font = "hzfont", font_size = p(19),
            style = { pad = 0, radius = p(8), shadow_width = 0, border_width = p(1),
                border_color = theme.border, bg_color = theme.surface_reserved, text_color = theme.text },
            on_click = function()
                hide_keypad()
                active_keypad = input.keypad
                active_keypad:set_hidden(false)
            end,
        })
    end
    input_field(address, 256, 86)
    input_field(interval, 490, 130)

    for index, field in ipairs(config.fields) do
        local y = 156 + (index - 1) * 50
        ui.label(parent, layout, field.label, 40, y + 9, 172, 27, 18, theme.secondary)
        local options = {}
        for i, option in ipairs(field.options) do options[i] = field.labels and field.labels[i] or tostring(option) end
        -- AirUI 的选中索引从 0 开始，Lua 的配置表从 1 开始。
        fields[field.key] = airui.dropdown({ parent = parent, x = p(256), y = p(y), w = p(407), h = p(40),
            options = options, default_index = config.option_index(field, saved[field.key]) - 1,
            style = control_style, on_change = mark_edited })
    end

    widgets.button(parent, layout, "保存配置", 406, 375, 257, 37, function()
        local slave = tonumber(address.text, 16)
        if not config.valid_slave(slave) then
            status:set_text(string.format("通信地址请输入 0x%02X 至 0x%02X", config.min_slave, config.max_slave))
            return
        end
        local draft = { slave = slave, interval_ms = tonumber(interval.text, 10) }
        for _, field in ipairs(config.fields) do
            draft[field.key] = field.options[fields[field.key]:get_selected() + 1]
        end
        local changed = not config.same(draft, store.modbus_serial())
        local ok, err = store.set_modbus_serial(draft)
        if not ok then
            status:set_text(err)
            return
        end
        edited = false
        address.text = string.format("%02X", slave)
        address.control:set_text(address.text)
        interval.text = tostring(draft.interval_ms)
        interval.control:set_text(interval.text)
        hide_keypad()
        if pc then
            status:set_text("已保存 · PC 仿真")
        else
            status:set_text(changed and "已保存 · 等待采集应用" or "当前配置已保存")
        end
    end, true)
    ui.label(parent, layout, "Modbus RTU 数据位通常为 8 位", 40, 384, 360, 24, 14, theme.muted)

    -- 两个输入框共用键盘布局。地址可输入十六进制，周期只提供十进制数字键。
    local function create_keypad(input, x, digits)
        local actions_y = 12 + ((#digits + 3) // 4) * 46
        local keypad = ui.box(parent, layout, x, 155, 300, actions_y + 56, theme.surface, 12, theme.border)
        input.keypad = keypad
        keypad:set_hidden(true)

        local function update_text(value)
            input.text = value
            input.control:set_text(value)
            mark_edited()
        end
        for index = 1, #digits do
            local digit = digits:sub(index, index)
            local column, row = (index - 1) % 4, (index - 1) // 4
            widgets.button(keypad, layout, digit, 12 + column * 70, 12 + row * 46, 65, 40, function()
                if #input.text < input.limit then update_text(input.text .. digit) end
            end)
        end
        widgets.button(keypad, layout, "清空", 12, actions_y, 87, 42, function() update_text("") end)
        widgets.button(keypad, layout, "退格", 106, actions_y, 87, 42, function()
            update_text(input.text:sub(1, -2))
        end)
        -- 完成只收起键盘，点击「保存配置」才会写入设备设置。
        widgets.button(keypad, layout, "完成", 200, actions_y, 87, 42, hide_keypad, true)
    end
    create_keypad(address, 96, "0123456789ABCDEF")
    create_keypad(interval, 364, "0123456789")

    -- 采集任务确认使用最新配置后更新提示。离开面板时解除订阅。
    local function on_applied(applied, ok)
        if not edited and config.same(applied, store.modbus_serial()) then
            status:set_text(ok and "已应用 · 按新配置采集" or "已保存 · UART1 初始化失败")
        end
    end
    sys.subscribe("APP_MODBUS_SERIAL_APPLIED", on_applied)
    return function() sys.unsubscribe("APP_MODBUS_SERIAL_APPLIED", on_applied) end
end

return M
