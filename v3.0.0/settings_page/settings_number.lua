local ui = require("ui_components")
local theme = require("ui_theme")
local widgets = require("settings_widgets")
local M = {}

-- 数字键盘使用独立预览行，数值、负号或十六进制地址不会被键盘遮挡。
local function number_text(value)
    if value == math.floor(value) then return string.format("%.0f", value) end
    return tostring(value)
end

function M.open(parent, layout, title, value, kind, accept)
    local hexadecimal = kind == "hex"
    local digits = hexadecimal and "0123456789ABCDEF" or (kind == "decimal" and "1234567890.-" or "1234567890")
    local text = hexadecimal and string.format("%02X", value) or number_text(value)
    local overlay = ui.box(parent, layout, 0, 0, 700, 464, theme.text, 0, nil, function() end)
    overlay:set_color(theme.text, 95)
    local dialog = ui.box(overlay, layout, 160, 45, 380, 365, theme.surface, 12, theme.border)
    ui.label(dialog, layout, title, 20, 14, 340, 28, 20)
    local preview = ui.label(dialog, layout, "", 20, 48, 340, 36, 21, theme.clock, airui.TEXT_ALIGN_CENTER)
    local function show()
        preview:set_text((hexadecimal and "0x" or "") .. text)
    end
    show()
    local function close()
        -- 回调执行结束后由外层释放弹窗，避免销毁当前触摸控件。
        accept(nil, overlay)
    end
    for index = 1, #digits do
        local digit = digits:sub(index, index)
        local col, row = (index - 1) % 4, (index - 1) // 4
        widgets.button(dialog, layout, digit, 20 + col * 86, 91 + row * 48, 80, 41, function()
            if #text >= (hexadecimal and 2 or 18) then return end
            if digit == "-" and #text ~= 0 then return end
            if digit == "." and text:find(".", 1, true) then return end
            text = text .. digit
            show()
        end)
    end
    widgets.button(dialog, layout, "清空", 20, 289, 80, 44, function() text = ""; show() end)
    widgets.button(dialog, layout, "退格", 106, 289, 80, 44, function() text = text:sub(1, -2); show() end)
    widgets.button(dialog, layout, "取消", 192, 289, 80, 44, close)
    widgets.button(dialog, layout, "确定", 278, 289, 80, 44, function()
        local number = hexadecimal and tonumber(text, 16) or tonumber(text)
        if number == nil then
            preview:set_text("请输入有效数值")
            return
        end
        accept(number, overlay)
    end, true)
    return overlay
end

return M
