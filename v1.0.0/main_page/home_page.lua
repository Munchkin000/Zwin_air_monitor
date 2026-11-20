-- 主页包含品牌页眉、时钟和两行应用入口。入口名称、顺序及路由在 app_config.lua 配置。
local ui = require("ui_components")
local theme = require("ui_theme")
local router = require("ui_router")
local M = {}

-- 所有坐标以 1024×600 为基准，ui.layout 会根据屏幕尺寸等比缩放并居中。
local CANVAS_WIDTH, CANVAS_HEIGHT = 1024, 600 -- UI基准逻辑画布分辨率
local COLUMNS = 4                              -- 应用卡片一行最多4列
local CARD_WIDTH, CARD_GAP = 220, 16           -- 卡片宽度、卡片之间间隙

-- 创建主页实例
function M.create(context)
    local config, clock, network = context.config, context.clock, context.network
    local layout = ui.layout(config.display) -- 根据显示屏配置生成布局对象，处理多屏幕缩放居中
    local p = layout.px                      -- 逻辑像素转物理像素函数
    
    -- 页面实例对象，alive标记页面是否存活，防止销毁后回调操作控件
    local page = { alive = true }

    -- 页面根容器，大小等于真实屏幕分辨率
    page.root = airui.container({ x = 0, y = 0, w = config.display.width,
        h = config.display.height, color = theme.background })
  
    -- canvas画布容器：以1024*600基准排版，自动缩放、偏移居中适配真实屏幕
    local canvas = airui.container({ parent = page.root, x = layout.x, y = layout.y,
        w = p(CANVAS_WIDTH), h = p(CANVAS_HEIGHT), color = theme.background })

    -- 页眉组合公司标识、系统标题和当前网络状态。
    local header = ui.box(canvas, layout, 0, 0, CANVAS_WIDTH, 88, theme.header)
    require("ui_brand").create(header, layout, config.brand) -- 创建品牌Logo（ui_brand模块）
    ui.box(header, layout, 282, 27, 1, 34, theme.border)     -- 竖分割线，分割Logo与文字
    ui.label(header, layout, config.title, 307, 20, 380, 33, 25) -- 主标题，取自config配置
    ui.label(header, layout, config.brand.subtitle, 308, 55, 380, 24, 13, theme.secondary) 
    --副标题
    ui.box(canvas, layout, 0, 88, CANVAS_WIDTH, 1, theme.border) --页眉下方水平分割线
    -- 右上角网络状态盒子
    local net = ui.box(header, layout, 758, 29, 218, 34, theme.status_background, 17)
    local net_text = ui.label(net, layout, "网络初始化中", 14, 6, 190, 24, 14,
        theme.secondary, airui.TEXT_ALIGN_CENTER)

    -- 时分、日期和同步说明共用屏幕中线。标签宽度改变时，左坐标仍由中线计算。
    -- 秒数和时区是右侧的辅助信息，单独定位，避免占用时分数字的居中空间。
    local center_x = CANVAS_WIDTH / 2
    local time_width, date_width = 372, 624
    local time = ui.label(canvas, layout, "--:--", center_x - time_width / 2, 100, time_width, 108, 88,
        theme.clock, airui.TEXT_ALIGN_CENTER)
    local seconds = ui.label(canvas, layout, "--", 672, 122, 62, 46, 32, theme.secondary)
    ui.label(canvas, layout, config.time.zone_label, 670, 168, 110, 24, 14, theme.muted)
    local date = ui.label(canvas, layout, "", center_x - date_width / 2, 202, date_width, 32, 20,
        theme.secondary, airui.TEXT_ALIGN_CENTER)
    local sync = ui.label(canvas, layout, "", center_x - date_width / 2, 239, date_width, 24, 13,
        theme.muted, airui.TEXT_ALIGN_CENTER)
    -- “应用中心” 标题分割线
    ui.box(canvas, layout, 170, 284, 806, 1, theme.border)
    ui.box(canvas, layout, 48, 276, 4, 18, theme.accent, 2)
    ui.label(canvas, layout, "应用中心", 62, 271, 112, 27, 17, theme.secondary)
    -- 入口按配置顺序排列，每行最多四个。按当行数量计算宽度，末行不足四个时也居中。
    -- 循环生成应用卡片入口
    for index, app in ipairs(config.apps) do
        local column = (index - 1) % COLUMNS
        local row = math.floor((index - 1) / COLUMNS)
        local row_count = math.min(COLUMNS, #config.apps - row * COLUMNS)
        local row_width = row_count * CARD_WIDTH + (row_count - 1) * CARD_GAP
        local x = (CANVAS_WIDTH - row_width) / 2 + column * (CARD_WIDTH + CARD_GAP)
        ui.app_card(canvas, layout, app, x, 307 + row * 132, function()
            if not page.alive then return end
            log.info("home", "APP_CLICK", app.id)
            sys.publish("APP_LAUNCH", app.id)
            -- 已注册的入口跳转到对应页面，开发中的入口只在页脚提示。
            if app.route and router.has(app.route) then
                -- 延迟切页，等 AirUI 点击回调结束后再销毁当前页面。
                sys.timerStart(function()
                    if page.alive then router.open(app.route) end
                end, 1)
            else
                page:show_notice(app.title .. (app.reserved and " · 位置已预留" or " · 功能即将开放"))
            end
        end)
    end
    -- 页脚文本
    local footer = ui.label(canvas, layout, "轻触图标，开启应用", 48, 571, 690, 24, 13, theme.muted)
    ui.label(canvas, layout, config.brand.footer, 714, 571, 262, 24, 12,
        theme.muted, airui.TEXT_ALIGN_RIGHT)

    -- 连续点击只保留最新提示的计时器，短暂展示后恢复默认页脚。
    function page:show_notice(text)
        footer:set_text(text)
        footer:set_color(theme.accent)
        if self.notice_timer then sys.timerStop(self.notice_timer) end
        self.notice_timer = sys.timerStart(function()
            if not self.alive then return end
            footer:set_text("轻触图标，开启应用")
            footer:set_color(theme.muted)
            self.notice_timer = nil
        end, 2500)
    end

    -- 时钟和网络服务通过事件通知页面，界面只读取快照并更新标签。
    local function update_clock()
        if not page.alive then return end
        local value = clock.snapshot() --调用service_clock的snapshot拿到完整时间状态
        time:set_text(value.time)
        seconds:set_text(value.seconds)
        date:set_text(value.date)
        sync:set_text(value.status)
        sync:set_color(value.synced and theme.success or theme.muted) --同步成功用成功色，否则置灰色
    end
    local function update_network()
        if not page.alive then return end
        --调用service_network的snapshot拿网络状态
        local value = network.snapshot()
        net_text:set_text(value.text)
        net_text:set_color(value.ready and theme.success or theme.secondary)
    end
    sys.subscribe("APP_CLOCK_CHANGED", update_clock)   --时钟变更事件，每秒触发
    sys.subscribe("APP_NETWORK_CHANGED", update_network) --网络状态变更事件
    update_clock()  --页面刚打开，立刻刷新一次时钟
    update_network()--页面刚打开，立刻刷新一次网络状态
    -- 页面销毁方法（ui_router 打开新页面会调用）
    function page:destroy()
        -- 先解除订阅并停止提示计时器，避免对已销毁的控件进行更新。
        self.alive = false
        sys.unsubscribe("APP_CLOCK_CHANGED", update_clock)
        sys.unsubscribe("APP_NETWORK_CHANGED", update_network)
        if self.notice_timer then sys.timerStop(self.notice_timer) end
        self.root:destroy()
    end
    return page
end

return M
