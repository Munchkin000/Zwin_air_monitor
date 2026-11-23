-- 系统更新面板显示版本、平台绑定标识和当前升级状态。
local ui = require("ui_components")
local theme = require("ui_theme")
local widgets = require("settings_widgets")
local upgrade = require("fota_service")
local M = {}

function M.mount(parent, layout, context)
    widgets.heading(parent, layout, "系统更新", "合宙 IoT · Air1603")
    ui.label(parent, layout, "当前程序版本", 40, 122, 170, 32, 18, theme.secondary)
    ui.label(parent, layout, VERSION, 250, 122, 410, 32, 20)
    ui.label(parent, layout, "升级设备标识", 40, 178, 170, 32, 18, theme.secondary)
    ui.label(parent, layout, upgrade.snapshot().device_id, 250, 178, 410, 32, 20)
    ui.box(parent, layout, 40, 228, 620, 1, theme.border)
    local status = ui.label(parent, layout, "", 40, 259, 620, 34, 18, theme.text)

    -- 状态决定按钮的动作。切到其他设置页也能继续下载，返回后恢复最新状态。
    local action_row = ui.box(parent, layout, 40, 334, 620, 54, theme.surface)
    local button = widgets.button(action_row, layout, "检查更新", 0, 0, 246, 47, function()
        if upgrade.snapshot().phase == "ready" then
            upgrade.reboot()
        else
            upgrade.check(context.network.snapshot())
        end
    end, true)

    local function refresh()
        local state = upgrade.snapshot()
        status:set_text(state.message)
        button:set_text(state.phase == "ready" and "重启应用" or "检查更新")
        action_row:set_hidden(state.phase ~= "idle" and state.phase ~= "ready")
    end
    sys.subscribe("APP_FOTA_CHANGED", refresh)
    refresh()
    return function() sys.unsubscribe("APP_FOTA_CHANGED", refresh) end
end

return M
