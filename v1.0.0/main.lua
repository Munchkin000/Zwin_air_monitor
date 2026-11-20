-- 程序入口：先初始化显示和数据服务，再注册页面并打开主页。
PROJECT = "Zwin_AirMonitor"
VERSION = "0.1.0"
-- 页面、计时器和数据事件共用 LuatOS 的调度器。（_G 是 Lua 的全局环境表）
_G.sys = require("sys")
-- require表示从其他模块导入函数
local config = require("app_config")
local platform = require("platform")
local network = require("service_network")
local clock = require("service_clock")
local router = require("ui_router")
-- 创建系统初始化任务
sys.taskInit(function()
    -- 打印项目运行日志
    log.info("main", PROJECT, VERSION, "MODE", platform.is_pc() and "PC" or "HARDWARE")
    -- 应用设置及配置状态。先读取保存的亮度，再调用平台模块点亮屏幕。
    local settings = require("settings_store")
    settings.start()
    local ok, err = platform.init_display(config, settings.snapshot().brightness)
    if not ok then log.error("main", err); return end -- 屏幕初始化失败
    -- 数据服务在创建页面前开始接收事件，切页时仍保留最近一次数据。
    require("device_store").start(config, platform.is_pc()) -- 设备信息、设备运行状态等
    require("env_store"):start() -- 环境监测数据，冒号调用会自动将对象本身作为第一个参数传入
    -- 真机用 UART1 轮询温湿度。PC 仿真继续通过演示值或缓存事件提供数据。
    if not platform.is_pc() then require("modbus_sensor").start() end
    -- 页面 ID 与 app_config.lua 中的 route 对应。首次打开时传入公共依赖。
    -- router.register() 用于注册页面
    router.register("home", require("home_page")) -- "home" 是页面 ID，home_page 是对应的页面模块
    router.register("environment", require("env_page"))
    router.register("device", require("device_page"))
    router.register("settings", require("settings_page"))
    router.open("home", { config = config, clock = clock, network = network })
    -- 页面订阅建立后启动时钟和网络服务，界面根据状态变化刷新。
    clock.start(config, platform.is_pc())
    network.start(config, platform.is_pc())
    log.info("main", "HOME_READY", config.display.width, config.display.height)
end)
-- 初始化任务注册完成后进入调度循环。
sys.run()
