-- 设置页共用的按钮和面板标题，坐标沿用项目的 1024×600 基准。
local ui = require("ui_components")  -- UI基础组件库
local theme = require("ui_theme")    -- UI主题配色模块
local M = {}

-- 创建设置页面通用按钮封装函数
-- parent：父容器；layout：布局缩放对象
-- text：按钮显示文字；x,y,w,h：基准分辨率下坐标宽高
-- action：按钮点击回调函数；primary：是否为主色调按钮（true主按钮，false次要按钮）
function M.button(parent, layout, text, x, y, w, h, action, primary)
    local p = layout.px  -- 逻辑像素转物理像素转换函数
    return airui.button({
        parent = parent, text = text, x = p(x), y = p(y), w = p(w), h = p(h),
        font = "hzfont", font_size = math.max(12, p(17)),  -- 使用中文字库，字号不小于12物理像素
        style = { pad = 0, radius = p(8), border_width = 0, shadow_width = 0,
            bg_color = primary and theme.accent or theme.status_background,  -- 主按钮用强调色，次要按钮用状态背景色
            text_color = primary and 0xFFFFFF or theme.clock },  -- 主按钮文字白色，次要按钮使用时钟主题文字色
        on_click = action,  -- 绑定点击回调
    })
end

-- 生成设置分组标题组件：主标题、副标题、底部分割横线
-- parent：父容器；layout：布局缩放对象
-- title：分组大标题；subtitle：分组描述小字
function M.heading(parent, layout, title, subtitle)
    ui.label(parent, layout, title, 24, 18, 652, 36, 26)         -- 分组主标题
    ui.label(parent, layout, subtitle, 24, 57, 652, 24, 14, theme.secondary)  -- 分组辅助描述文字，次要文字颜色
    ui.box(parent, layout, 24, 90, 652, 1, theme.border)         -- 标题下方水平分割线
end

return M