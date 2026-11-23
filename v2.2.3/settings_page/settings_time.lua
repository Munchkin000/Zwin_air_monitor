-- 时间面板以进入时的应用时间作为草稿，逐行加减，按保存后应用到主页。
local ui = require("ui_components")        -- UI基础组件库
local theme = require("ui_theme")           -- UI主题配色
local widgets = require("settings_widgets")-- 设置页通用小组件（标题、按钮封装）
local calendar = require("settings_calendar")-- 日期时间工具模块（闰年、步进、时间戳转换）
local M = {}

-- 挂载时间设置面板到父容器
-- parent：父UI容器；layout：布局缩放对象；context：页面全局上下文
function M.mount(parent, layout, context)
    local clock = context.clock                -- 获取时钟服务实例service_clock
    local offset = context.config.time.utc_offset -- 获取时区偏移（东八区28800秒）
    -- 绘制设置分组标题与描述文字
    widgets.heading(parent, layout, "设置当前时间和日期", "以北京时间输入。调整后点击保存。")

    -- 初始化草稿时间：读取当前应用显示的本地时间作为编辑草稿
    local draft = clock.local_date()
    -- 年份限制在2000‑2099范围内，和calendar工具约束保持一致
    draft.year = math.max(2000, math.min(2099, draft.year))
    -- 修正日期，防止跨月出现非法日期（例如3月31日切到2月）
    draft.day = math.min(draft.day, calendar.days_in_month(draft.year, draft.month))

    local values = {} -- 保存时间各个字段显示文本控件引用，用于刷新界面
    -- 状态提示标签，展示操作提示、成功、错误信息
    local status = ui.label(parent, layout, "手动时间会用于本应用的时钟", 36, 426, 628, 28, 14, theme.muted)

    -- 刷新时间编辑区UI，把draft草稿时间渲染到界面标签
    local function refresh()
        for _, field in ipairs(calendar.fields) do
            -- 年份使用4位格式，其余月/日/时/分/秒使用2位补零格式
            values[field.key]:set_text(string.format(field.key == "year" and "%04d" or "%02d", draft[field.key]))
        end
    end

    -- 循环生成【年、月、日、时、分、秒】每一行编辑项
    for index, field in ipairs(calendar.fields) do
        local y = 100 + (index - 1) * 46 -- 计算当前行的Y坐标，每行高度46逻辑像素
        ui.label(parent, layout, field.label, 40, y + 9, 100, 29, 18, theme.secondary) -- 左侧字段名称：年、月、日…
        -- 中间时间显示文本控件，居中展示数值
        values[field.key] = ui.label(parent, layout, "", 218, y + 6, 174, 33, 21, theme.text, airui.TEXT_ALIGN_CENTER)

        -- 增减按钮的回调函数，delta=+1增加 / delta=-1减少
        local function adjust(delta)
            calendar.step(draft, field, delta) -- 调用日历工具做字段步进滚动，自动处理越界、闰年月末修正
            refresh()                           -- 更新界面显示
            status:set_text("时间已编辑 · 保存后生效") -- 修改草稿后提示需要点击保存才真正生效
        end

        widgets.button(parent, layout, "-", 522, y + 3, 59, 37, function() adjust(-1) end) -- 减号按钮
        widgets.button(parent, layout, "+", 595, y + 3, 59, 37, function() adjust(1) end) -- 加号按钮
        ui.box(parent, layout, 36, y + 44, 628, 1, theme.border) -- 行底部分割横线
    end

    -- 【保存时间】主按钮：把草稿时间提交给时钟服务设置手动时间
    widgets.button(parent, layout, "保存时间", 347, 383, 306, 38, function()
        -- 将草稿本地时间+时区偏移换算成UTC时间戳epoch
        local epoch = calendar.to_utc(draft, offset)
        if not epoch then -- 时间格式非法，转换失败
            status:set_text("日期或时间无效")
            return
        end
        -- 调用时钟服务接口设置手动时间（硬件写RTC / PC修改时间偏移）
        local ok, err = clock.set_manual_time(epoch)
        status:set_text(ok and "已保存 · 主页时钟已更新" or err)
    end, true)

    -- 【恢复自动时间】按钮：切回NTP网络自动校时模式
    widgets.button(parent, layout, "恢复自动时间", 36, 383, 292, 38, function()
        local ok, err = clock.use_auto_time()
        if ok then
            draft = clock.local_date() -- 切换成功，重新拉取当前时间刷新编辑草稿界面
            refresh()
        end
        status:set_text(ok and "已恢复自动时间" or err)
    end)

    refresh() -- 页面挂载完成，初始化渲染时间草稿到界面
end
return M
