-- 系统参数页只读设备身份，集中修改采样、存储和上报周期。
local ui = require("ui_components")
local theme = require("ui_theme")
local widgets = require("settings_widgets")
local params = require("system_params")
local number = require("settings_number")
local device = require("device_store")
local M = {}

function M.mount(parent, layout)
    local p = layout.px
    local id = device.snapshot()
    local draft = params.snapshot()
    widgets.heading(parent, layout, "系统参数", "采样周期应用于全部监测因子")
    local function caption(text, y)
        ui.label(parent, layout, text, 36, y + 8, 200, 27, 18, theme.secondary)
    end
    caption("设备名称", 106)
    ui.label(parent, layout, id.name, 255, 114, 410, 27, 18)
    caption("设备编号", 156)
    ui.label(parent, layout, id.device_id, 255, 164, 410, 27, 18)

    local function dropdown(text, y, options, value)
        caption(text, y)
        return airui.dropdown({
            parent = parent, x = p(255), y = p(y), w = p(335), h = p(40),
            options = options.labels, default_index = params.index(options, value) - 1,
            style = {bg_color = theme.surface_reserved, text_color = theme.text,
                border_color = theme.border, border_width = p(1)},
        })
    end
    local store = dropdown("存储周期", 210, params.storage, draft.store_ms)
    caption("采样周期 (ms)", 263)
    local keypad, close_timer, sample
    sample = widgets.button(parent, layout, tostring(draft.sample_ms), 255, 263, 335, 40, function()
        if keypad then return end
        keypad = number.open(parent, layout, "采样周期 (ms)", draft.sample_ms, "integer", function(value, overlay)
            if close_timer then return end
            if value then draft.sample_ms = value; sample:set_text(tostring(value)) end
            close_timer = sys.timerStart(function()
                close_timer, keypad = nil, nil
                overlay:destroy()
            end, 1)
        end)
    end)
    local upload = dropdown("上报周期", 316, params.upload, draft.upload_ms)
    local status = ui.label(parent, layout, "", 36, 408, 420, 26, 15, theme.muted)
    widgets.button(parent, layout, "保存参数", 465, 403, 194, 38, function()
        draft.store_ms = params.storage.values[store:get_selected() + 1]
        draft.upload_ms = params.upload.values[upload:get_selected() + 1]
        local ok, err = params.save(draft)
        status:set_text(ok and "系统参数已保存" or err)
    end, true)
    return function() if close_timer then sys.timerStop(close_timer) end end
end
return M
