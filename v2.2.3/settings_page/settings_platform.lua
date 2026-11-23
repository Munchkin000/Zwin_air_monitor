-- 上报中心选项卡。开关立即保存，输入框通过保存按钮提交。
local ui = require("ui_components")
local theme = require("ui_theme")
local widgets = require("settings_widgets")
local config = require("uplink_config")
local uplink = require("uplink_service")
local M = {}

function M.mount(parent, layout)
    local p = layout.px
    widgets.heading(parent, layout, "上报中心", "上下滑动查看配置 · 同时只启用一种协议")
    local activity = ui.label(parent, layout, "", 33, 421, 632, 22, 16, theme.clock)
    local tip = ui.label(parent, layout, "", 33, 445, 632, 18, 14, theme.muted)
    if not (airui.tabview and airui.textarea and airui.keyboard) then
        activity:set_text("当前固件缺少上报中心控件")
        return
    end

    -- 键盘固定在面板底部。由输入框的点击区域显式打开，滑动表单时不会收起。
    -- 确认键只收起键盘，仍由当前选项卡的保存按钮提交参数。
    local keyboard, editing_input
    local function hide_keyboard()
        keyboard:hide()
        if editing_input then
            editing_input:set_style({bg_color = theme.surface_reserved})
            editing_input = nil
        end
    end
    keyboard = airui.keyboard({
        parent = parent, x = 0, y = -p(4), w = p(640), h = p(178), mode = "text",
        auto_hide = false, preview = false, popovers = false,
        on_commit = hide_keyboard,
    })
    keyboard:hide()

    local titles = {}
    for index, protocol in ipairs(config.protocols) do titles[index] = protocol.title end
    local tabs = airui.tabview({
        parent = parent, x = p(24), y = p(95), w = p(652), h = p(321), tabs = titles,
        switch_mode = "jump", bg_color = theme.surface,
        style = {tabbar_size = p(42), pad = {method = airui.TABVIEW_PAD_ALL, value = 0}},
    })
    tabs:set_on_change(function()
        hide_keyboard()
        tip:set_text("")
    end)

    local switches = {}
    local syncing = true
    local function refresh()
        syncing = true
        local selected = config.selected()
        for id, control in pairs(switches) do
            local desired = selected == id
            if control:get_state() ~= desired then control:set_state(desired) end
        end
        syncing = false
        local title = selected:upper()
        for _, protocol in ipairs(config.protocols) do
            if selected == protocol.id then title = protocol.title end
        end
        activity:set_text(selected == "" and "上报已关闭" or title .. " · " .. uplink.status())
    end

    for index, protocol in ipairs(config.protocols) do
        local id = protocol.id
        local tab = tabs:get_content(index - 1)
        -- 每个选项卡使用独立的滚动容器，标签栏和键盘留在容器之外。
        local content = ui.box(tab, layout, 0, 0, 632, 232, theme.surface)
        -- 底部预留滚动距离，使最后一排输入框和保存按钮都能滑到键盘上方。
        ui.box(content, layout, 0, 398, 1, 1, theme.surface)
        local saved, inputs = config.endpoint(id), {}
        ui.label(content, layout, "启用 " .. protocol.title .. " 上报", 10, 49, 440, 24, 17)
        switches[id] = airui.switch({
            parent = content, x = p(558), y = p(45), w = p(72), h = p(32),
            checked = config.selected() == id,
            on_change = function(control)
                if syncing then return end
                local ok, err = config.select(control:get_state() and id or "")
                refresh()
                tip:set_text(ok and "上报开关已保存" or err)
            end,
        })

        -- 同一协议的输入框保留草稿，只有提交后才更新运行配置。
        local function field(key, title, x, y, label_width, width, max_len, numeric, password)
            ui.label(content, layout, title, x, y + 7, label_width, 27, 15, theme.secondary)
            local input = airui.textarea({
                parent = content, x = p(x + label_width), y = p(y), w = p(width), h = p(35),
                text = tostring(saved[key]), max_len = max_len, mode = password and "password" or "normal",
                style = {radius = p(7), font_size = p(16), bg_color = theme.surface_reserved, text_color = theme.text},
            })
            inputs[key] = input
            -- 透明点击层与输入框同宽，轻点绑定键盘，上下拖动交给外层表单。
            local touch = ui.box(content, layout, x + label_width, y, width, 35, theme.surface, 0, nil, function()
                hide_keyboard()
                editing_input = input
                -- 用底色标出当前编辑项，拖动之后仍能辨认键盘对应的输入框。
                input:set_style({bg_color = theme.tones.blue.background})
                keyboard:set_layout(numeric and "numeric" or "text")
                keyboard:set_target(input)
                input:set_cursor(#input:get_text())
                keyboard:show()
            end)
            touch:set_color(theme.surface, 0)
        end

        -- 将地址和端口放在同一排，便于对照。
        local endpoint_y = 8
        if id == "udp" then
            field("host", "服务器", 10, endpoint_y, 64, 244, 96)
            field("port", "目标端口", 328, endpoint_y, 69, 77, 5, true)
            field("local_port", "本地端口", 488, endpoint_y, 69, 72, 5, true)
        else
            field("host", "服务器", 10, endpoint_y, 79, 320, 96)
            field("port", "端口", 424, endpoint_y, 63, 142, 5, true)
        end
        local secure
        if id == "mqtt" then
            ui.label(content, layout, "TLS", 424, 91, 85, 24, 15, theme.secondary)
            secure = airui.switch({
                parent = content, x = p(558), y = p(84), w = p(72), h = p(30), checked = saved.secure,
            })
        end
        if id == "mqtt" then
            field("topic", "发布主题", 10, 80, 79, 320, 96)
            field("client_id", "客户端 ID", 10, 117, 79, 320, 64)
            field("username", "用户名", 10, 154, 79, 257, 64)
            field("password", "密码", 361, 154, 57, 211, 96, false, true)
        elseif id == "udp" then
            ui.label(content, layout, "本地端口填 0 时自动分配，对端可回复到来源端口", 10, 99, 600, 26, 15, theme.muted)
        else
            ui.label(content, layout, "设备为 TCP 客户端，连接笔记本的 TCP Server", 10, 99, 600, 26, 15, theme.muted)
        end

        widgets.button(content, layout, "保存配置", 445, 194, 184, 34, function()
            hide_keyboard()
            local draft = {}
            for name, input in pairs(inputs) do draft[name] = input:get_text() end
            if secure then draft.secure = secure:get_state() end
            local ok, err = config.save(id, draft)
            tip:set_text(ok and "服务器配置已保存" or err)
        end, true)
    end

    sys.subscribe("UPLINK_STATUS_CHANGED", refresh)
    refresh()
    return function()
        hide_keyboard()
        sys.unsubscribe("UPLINK_STATUS_CHANGED", refresh)
    end
end

return M
