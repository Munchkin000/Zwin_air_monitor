-- 应用的集中配置。主页标题、设备默认信息、显示尺寸和入口都从这里读取。
return {
    title = "空气质量监测系统",
    device = { name = "空气质量监测终端", id = "未设置", board = "Air8603M1", 
               chip = "Air1603" },
    brand = { logo = "/luadb/brand_logo.png", logo_width = 208, logo_height = 64,
        subtitle = "智易时代 · 企业内部应用", footer = "智易时代 / 空气质量监测" },
    display = { width = 1024, height = 600 }, -- 实际屏幕显示尺寸
    -- 时间服务使用 UTC 时间戳显示北京时间。PC 仿真使用单独的校时服务器列表。
    time = { utc_offset = 28800, zone_label = "北京时间",
        -- 真机先试与 PC 相同的阿里云 IP，DNS 暂未就绪时也能尝试校时。
        servers = { "203.107.6.88", "ntp.aliyun.com", "time1.cloud.tencent.com" },
        pc_servers = { "203.107.6.88" }, sync_interval_ms = 3600000,
        retry_interval_ms = 60000, hardware_retry_interval_ms = 15000, sync_timeout_ms = 15000 },
    -- 前四项占第一行，后四项是第二行的预留应用。id 是点击事件标识，title 是界面文字。
    -- 启用新页面时，在 main.lua 注册对应页面，再为入口填写 route 并调整图标和配色。
    -- 联网配置位于系统设置页，设备联网驱动放在 internet_connect 目录。
    apps = {
        --  id	    应用的标识符
        -- route	点击后打开的页面 ID
        -- title	界面上显示的名称
        -- icon	    图标类型，交给 ui_icons.lua 绘制
        -- tone	    卡片图标的配色类型
        -- reserved	是否为预留应用
        { id = "settings", route = "settings", title = "系统设置", 
            icon = "settings", tone = "blue" },
        { id = "environment", route = "environment", title = "环境监测", 
            icon = "environment", tone = "green" },
        { id = "device", route = "device", title = "设备信息", 
            icon = "device", tone = "purple" },
        { id = "logs", title = "运行日志", icon = "log", tone = "blue" },
        { id = "reserved_7", title = "预留应用 01", icon = "plus", reserved = true },
        { id = "reserved_8", title = "预留应用 02", icon = "plus", reserved = true },
        { id = "reserved_9", title = "预留应用 03", icon = "plus", reserved = true },
        { id = "reserved_10", title = "预留应用 04", icon = "plus", reserved = true },
    },
}
