-- 监测项目选择弹窗。flags 是页面传入的草稿，点击确定后由回调提交。
local ui = require("ui_components")    -- UI基础组件库
local theme = require("ui_theme")       -- UI主题配色
local data = require("env_data")         -- 环境监测参数字典模块
local M = {}

-- 创建监测项目编辑弹窗
-- parent：父控件容器；layout：布局对象；flags：选中状态草稿表；callbacks：回调函数集合
function M.create(parent, layout, flags, callbacks)
    local p = layout.px    -- 逻辑像素转物理像素的转换函数
    local modal = { alive = true, flags = flags, controls = {} } -- 弹窗实例对象
    
    -- 遮罩覆盖整个画布并接收点击，让操作集中在当前弹窗内。
    -- 创建全屏半透明遮罩容器，拦截底层界面点击事件
    modal.root = airui.container({ parent = parent, x = 0, y = 0, w = p(1024), h = p(600),
        color = 0x122C46, color_opacity = 105, on_click = function() end })
    
    -- 创建弹窗主对话框盒子：位置、宽高、背景色、圆角、边框
    local dialog = ui.box(modal.root, layout, 268, 40, 488, 520, theme.surface, 16, theme.border)
    ui.label(dialog, layout, "编辑监测项目", 24, 20, 436, 34, 23, theme.text) -- 弹窗标题文本
    local summary = ui.label(dialog, layout, "", 24, 58, 436, 25, 14, theme.secondary) -- 统计提示文本：已选择X/X项

    -- 统计当前勾选的监测项总数量
    local function selected_count()
        local count = 0
        for index = 1, #data.metrics do
            if modal.flags[index] then
                count = count + 1
            end
        end
        return count
    end

    -- 使用两段线绘制勾选符号，避免依赖中文字库中是否有该字形。
    -- 手动绘制对勾的线条图形，不用字体字符画√，防止字库缺失显示异常
    local function tick_items()
        return {
            { type = "line", x1 = p(4), y1 = p(10), x2 = p(8), y2 = p(14),
                width = math.max(1, p(2)), color = 0xFFFFFF, round_start = true,
                round_end = true },
            { type = "line", x1 = p(8), y1 = p(14), x2 = p(16), y2 = p(5),
                width = math.max(1, p(2)), color = 0xFFFFFF, round_start = true,
                round_end = true },
        }
    end

    -- 刷新某一行选项UI状态：背景色、复选框颜色、是否显示对勾、更新统计文字
    local function refresh(index)
        local selected = modal.flags[index]          -- 当前项是否勾选
        local control = modal.controls[index]        -- 获取该行保存的UI控件引用
        control.row:set_color(selected and 0xEBF6FF or 0xF5F8FC) -- 行背景：选中/未选中两套底色
        control.box:set_color(selected and theme.accent or theme.surface) -- 复选框背景色
        control.box:set_border_color(selected and theme.accent or 0xADC3D8, math.max(1, p(1)))
        -- 复选框边框颜色
        control.tick:set_items(selected and tick_items() or {})
        -- 勾选状态：绘制对勾图形 / 清空图形
        summary:set_text(string.format("已选择 %d / %d 项 · 上下滑动选择",
            selected_count(), #data.metrics)) -- 更新选择统计提示
    end

    -- 选项列表单独滚动，确定和取消按钮固定在弹窗底部。
    -- 列表容器：承载所有监测因子勾选行
    local list = ui.box(dialog, layout, 24, 96, 436, 312, theme.surface)
 
    -- 遍历所有环境监测参数，循环生成每一行勾选条目
    for index, metric in ipairs(data.metrics) do
        -- 行点击回调：翻转勾选状态
        local function toggle()
            if not modal.alive then 
                return
            end -- 如果弹窗已经销毁，直接返回，不执行操作
            modal.flags[index] = not modal.flags[index] -- 布尔取反，切换勾选标记
            refresh(index) -- 刷新本行UI显示
            log.info("environment", "EDITOR_TOGGLE", index, modal.flags[index], selected_count())
        end
        -- 创建单行容器盒子，绑定点击toggle切换勾选
        local row = ui.box(list, layout, 0, (index - 1) * 40, 420, 36, 0xF5F8FC, 8, nil, toggle)
        ui.label(row, layout, metric.name, 14, 6, 252, 25, 17, theme.text, nil, toggle) -- 参数中文名称标签，点击同样触发勾选
        local box = ui.box(row, layout, 380, 6, 24, 24, theme.surface, 4, 0xADC3D8, toggle) -- 复选框方框控件
        local tick = airui.shape({ parent = box, x = 0, y = 0, w = p(20), h = p(20), items = {} }) -- 绘制对勾的shape图形控件
        modal.controls[index] = { row = row, box = box, tick = tick } -- 将本行控件存入controls记录表，后续refresh刷新使用
        refresh(index) -- 初始化本行UI状态
    end

    -- 仪表与表格共用勾选结果，确定后一起更新。
    ui.label(dialog, layout, "确定后，仪表和表格同步显示已选项目", 24, 420, 436, 22, 12, theme.muted)
    ui.box(dialog, layout, 24, 448, 436, 1, theme.border) -- 分割横线

    -- 确定时先应用选择，再销毁弹窗并通知页面清理引用。
    -- finish：弹窗结束处理函数，save=true代表点击确定保存；false代表取消不保存
    local function finish(save)
        if not modal.alive then
            return
        end
        local count = selected_count()
        if save then 
            callbacks.apply(modal.flags)
        end -- 确定：调用上层apply回调，把勾选结果回传给页面
        modal:destroy()  -- 销毁弹窗UI资源
        callbacks.close() -- 调用关闭回调，通知父页面弹窗已关闭
        log.info("environment", save and "EDITOR_CONFIRM" or "EDITOR_CANCEL", count)
    end

    -- 创建按钮封装函数
    -- text按钮文字；x横坐标；primary是否主色调按钮；save标记，传给finish函数
    local function button(text, x, primary, save)
        return airui.button({ parent = dialog, text = text, x = p(x), y = p(462), w = p(208), h = p(40),
            font = "hzfont", font_size = p(17),
            style = { pad = 0, radius = p(8), border_width = 0, shadow_width = 0,
                bg_color = primary and theme.accent or 0xE7F0F8,
                text_color = primary and 0xFFFFFF or theme.secondary },
            on_click = function()
                -- defer延迟回调，交由上层调度处理，防止UI事件内直接销毁控件引发异常
                callbacks.defer(function() if modal.alive then finish(save) end end)
            end })
    end
    modal.cancel = button("取消", 24, false, false)   -- 创建【取消】按钮
    modal.confirm = button("确定", 252, true, true)   -- 创建【确定】按钮

    -- 弹窗销毁方法：标记失效，销毁根UI控件，清空控件引用，防止内存泄漏
    function modal:destroy()
        if not self.alive then return end
        self.alive = false
        self.root:destroy()
        self.controls = {}
    end

    log.info("environment", "EDITOR_OPEN", selected_count())
    return modal -- 返回弹窗实例对象给调用方
end
return M