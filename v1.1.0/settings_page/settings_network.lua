-- 网络设置面板展示实时状态，并保存用户是否允许使用 4G 的偏好。
local ui = require("ui_components")        -- UI基础组件库
local theme = require("ui_theme")           -- UI主题配色
local widgets = require("settings_widgets") -- 设置页面通用小组件（标题栏等）
local store = require("settings_store")     -- 设置持久化存储模块，读写Flash保存配置
local M = {}

-- 将网络设置组件挂载到父容器上
-- parent：父UI容器；layout：布局缩放对象；context：页面全局上下文对象
function M.mount(parent, layout, context)
    local p = layout.px
    -- 绘制设置分组标题：主标题与描述小字
    widgets.heading(parent, layout, "网络设置", "查看 SIM 卡、4G 数据连接及外网状态")

    -- 开关所在卡片容器
    local card = ui.box(parent, layout, 24, 105, 652, 72, theme.surface_reserved, 10)
    ui.label(card, layout, "启用 4G 连接", 16, 9, 350, 26, 20)

    -- 根据是否PC仿真，显示不同提示文字
    local is_pc = context.network.snapshot().pc
    local notice = is_pc and "PC 仿真中保存开关偏好" or "开关设置在下次启动时应用"
    local tip = ui.label(card, layout, notice, 16, 39, 480, 23, 14, theme.muted)

    -- 从持久化存储读取4G启用开关的初始状态
    local initial = store.snapshot().cellular_enabled
    local updating = false -- 防抖动标记，防止回调重入

    -- 创建开关控件：控制是否允许使用4G
    airui.switch({
        parent = card, x = p(553), y = p(16), w = p(78), h = p(38), checked = initial,
        on_change = function(control)
            if updating then return end -- 如果正在处理，直接返回，避免重入
            local enabled = control:get_state() -- 获取开关最新状态 true/false
            local ok, err = store.set_cellular_enabled(enabled) -- 将开关配置写入Flash持久化
            if ok then
                -- 保存成功，更新提示文本
                if is_pc then
                    tip:set_text(enabled and "已保存 · 允许设备使用 4G" or "已保存 · 不使用设备 4G")
                else
                    local pending = context.network.snapshot().restart_required
                    tip:set_text(pending and "已保存 · 重启设备后生效" or notice)
                end
            else
                -- 保存失败，回滚开关UI状态，展示错误信息
                updating = true
                control:set_state(store.snapshot().cellular_enabled)
                updating = false
                tip:set_text(err)
            end
        end,
    })

    -- 需要展示的蜂窝网络状态字段列表：key、界面显示名称
    local fields = {
        { "sim", "SIM 卡状态" }, { "link", "4G 数据连接" }, { "internet", "4G 外网访问" },
        { "ip", is_pc and "4G IP 地址" or "4G 板内桥接 IP" },
    }
    local labels = {} -- 保存各个状态对应的UI标签控件引用，后续用来刷新文本

    -- 循环生成每一行网络状态标签与分割线
    for index, field in ipairs(fields) do
        local y = 188 + (index - 1) * 37
        ui.label(parent, layout, field[2], 36, y + 4, 235, 26, 16, theme.secondary)
        labels[field[1]] = ui.label(parent, layout, "", 273, y + 4, 391, 26, 17,
            theme.text, airui.TEXT_ALIGN_RIGHT)
        ui.box(parent, layout, 36, y + 35, 628, 1, theme.border)
    end

    -- PC仿真环境的电脑网络状态提示标签
    local host = ui.label(parent, layout, "", 36, 422, 628, 27, 14, theme.muted)

    -- 刷新网络状态UI：读取网络服务快照更新所有显示文本
    local function refresh()
        local snapshot = context.network.snapshot()
        -- 遍历字段，更新蜂窝网络状态，无数据则显示“待接入”
        for _, field in ipairs(fields) do
            labels[field[1]]:set_text(snapshot.cellular[field[1]] or "待接入")
        end
        -- PC仿真模式展示电脑网络外网状态；硬件模式置空不显示
        host:set_text(snapshot.pc and ("电脑网络 · " .. snapshot.host_internet) or "")
        -- 重新进入页面时，仍可看到之前修改过的开关是否等待重启。
        if not is_pc then
            tip:set_text(snapshot.restart_required and "已保存 · 重启设备后生效" or notice)
        end
    end

    -- 数据服务一收到驱动状态就发布事件，页面只负责填写当前快照。
    -- 订阅网络状态变更事件，网络发生变化自动执行refresh刷新UI
    sys.subscribe("APP_NETWORK_CHANGED", refresh)
    refresh() -- 页面挂载完成立刻执行一次刷新，初始化界面

    -- 返回页面销毁清理回调：取消事件订阅，防止内存泄漏、野回调
    return function() sys.unsubscribe("APP_NETWORK_CHANGED", refresh) end
end
return M