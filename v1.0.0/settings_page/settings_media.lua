-- 两个原生 AirUI 滑块共用同一个保存流程。真机亮度拖动时预览，停止后再写入 Flash。
local ui = require("ui_components")        -- UI基础组件库
local theme = require("ui_theme")           -- UI主题配色
local widgets = require("settings_widgets") -- 设置页面通用小组件
local store = require("settings_store")     -- 设置持久化存储模块（读写Flash）
local platform = require("platform")       -- 统一访问板级背光，PC 仿真无需 PWM
local M = {}

-- 将亮度音量设置组件挂载到指定父容器
-- parent：父UI容器；layout：布局缩放对象；context：页面全局上下文
function M.mount(parent, layout, context)
    local p = layout.px
    -- 绘制设置分组标题栏：主标题、描述小字
    widgets.heading(parent, layout, "亮度和声音", "调整屏幕亮度与媒体音量")
    -- 判断当前是否PC仿真环境
    local pc = context.network.snapshot().pc
    -- 根据仿真/硬件环境显示不同提示文本
    local note = pc and "PC 仿真 · 调整值用于设备设置" or "拖动即时调光 · 0% 保留最低背光 · 停止后保存"
    -- 状态提示文本控件，用于展示调整中、已保存、错误信息
    local status = ui.label(parent, layout, note, 26, 419, 650, 30, 15, theme.muted)
    -- 检测AirUI底层是否支持slider滑块控件，不支持直接提示返回
    if not airui.slider then
        status:set_text("当前 AirUI 固件缺少滑块组件")
        return
    end
    -- 读取Flash中已经保存的亮度、音量配置快照
    local selected = store.snapshot()
    local save_timer  -- 延迟保存计时器变量，防抖使用
    local brightness_error -- 记录硬件调光失败，避免保存提示覆盖错误

    -- 执行持久化保存亮度音量到Flash
    local function save()
        save_timer = nil
        -- 调用存储接口写入亮度、音量
        local ok, err = store.set_levels(selected.brightness, selected.volume)
        -- 根据PC/硬件环境拼接保存成功提示文字
        local saved = pc and "已保存 · PC 仿真" or "已保存"
        -- 更新状态提示：成功显示保存提示，失败显示错误信息
        status:set_text(ok and (brightness_error or saved) or err)
        return ok
    end

    -- 滑块生成封装函数
    -- field：存储字段名(brightness/volume)；title：分组标题；y：容器Y坐标；color：滑块主题颜色
    local function slider(field, title, y, color)
        -- 创建滑块所在卡片容器
        local card = ui.box(parent, layout, 24, y, 652, 134, theme.surface_reserved, 10)
        -- 卡片标题文字
        ui.label(card, layout, title, 20, 13, 260, 30, 20)
        -- 百分比数值显示标签，右侧对齐
        local value = ui.label(card, layout, string.format("%d%%", selected[field]), 520, 12, 112, 34, 22,
            color, airui.TEXT_ALIGN_RIGHT)
        -- 创建AirUI原生滑块控件
        airui.slider({
            parent = card, x = p(27), y = p(62), w = p(598), h = p(22),
            min = 0, max = 100, value = selected[field], -- 取值范围0‑100，初始读取存储里的值
            style = { bg_color = theme.border, indicator_color = color,
                knob_color = theme.surface, knob_border_color = color, knob_border_width = p(2) },
            -- 滑块值发生变化回调，拖动会连续触发
            on_change = function(control)
                local level = control:get_value()         -- 获取滑块当前数值
                selected[field] = level                    -- 更新内存中的配置值
                value:set_text(string.format("%d%%", level)) -- 更新界面百分比显示
                if field == "brightness" then
                    -- 真机即时更新 PWM3，PC 由平台层直接返回。保存计时器只负责持久化。
                    local ok, err = platform.apply_brightness(level)
                    brightness_error = not ok and err or nil
                end
                status:set_text(brightness_error or "调整中 · 停止拖动后保存")
                -- 拖动会连续触发回调，静止后集中写入一次，减少 Flash 写入。
                if save_timer then sys.timerStop(save_timer) end -- 如果已有等待保存的定时器，先停止
                save_timer = sys.timerStart(save, 500)           -- 500ms无拖动变化才执行保存
            end,
        })
        -- 滑块底部最小值文本0
        ui.label(card, layout, "0", 18, 100, 48, 23, 13, theme.muted)
        -- 滑块底部最大值文本100，右对齐
        ui.label(card, layout, "100", 573, 100, 60, 23, 13, theme.muted, airui.TEXT_ALIGN_RIGHT)
    end
    -- 创建【屏幕亮度】滑块卡片
    slider("brightness", "屏幕亮度", 106, theme.accent)
    -- 创建【媒体音量】滑块卡片
    slider("volume", "媒体音量", 255, theme.success)

    -- 返回清理回调函数：页面销毁/快速切页时调用
    return function()
        -- 快速切页时也提交最后的值，计时器不得再访问即将销毁的控件。
        if save_timer then
            sys.timerStop(save_timer) -- 停止还未执行的延迟保存定时器
            save()                    -- 立刻把当前内存的值写入Flash
        end
    end
end
return M