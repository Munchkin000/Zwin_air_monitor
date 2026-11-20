-- 集中定义页面基础配色，颜色值使用 0xRRGGBB。
return {
    background = 0xF2F7FC,        -- 页面全局背景色
    header = 0xFFFFFF,           -- 顶部标题栏背景色
    surface = 0xFFFFFF,           -- 卡片、面板普通表面底色
    surface_reserved = 0xF8FBFE,  -- 保留/次要面板表面底色
    border = 0xD9E6F2,            -- 分割线、边框颜色
    text = 0x183B5B,              -- 主要正文文字颜色
    secondary = 0x486C8C,         -- 次要文字颜色
    muted = 0x71879D,             -- 弱化、置灰提示文字颜色
    accent = 0x0C95DD,            -- 主题强调色，按钮、重点元素、兜底Logo文字
    clock = 0x087EC0,             -- 时钟组件数字文字颜色
    brand_warm = 0xFFB43F,        -- 品牌暖色调（警示/提醒类）
    status_background = 0xEAF5FD, -- 状态栏信息提示块背景色
    success = 0x147D78,           -- 成功状态颜色
    -- 应用卡片按 app_config.lua 的 tone 选择图标前景色和底色。
    tones = 
    {
        blue = { foreground = 0x087FC4, background = 0xE5F3FD },    --蓝色色调：图标前景色、卡片背景色
        green = { foreground = 0x129AC6, background = 0xE5F6FC },  --绿色色调：图标前景色、卡片背景色
        purple = { foreground = 0x347CC5, background = 0xEBF1FD },  --紫色色调：图标前景色、卡片背景色
        amber = { foreground = 0xC17B12, background = 0xFFF3DB },   --琥珀/橙黄色色调：图标前景色、卡片背景色
        reserved = { foreground = 0x7D9AB4, background = 0xEAF1F8 },--保留默认色调：图标前景色、卡片背景色
    },
}