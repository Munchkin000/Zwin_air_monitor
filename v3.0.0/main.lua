-- 程序入口：先初始化显示和触摸，再启动数据服务并打开主页。
PROJECT = "Zwin_AirMonitor"
-- 合宙 IoT 按三段数字识别脚本版本。正式工程代码每次修改后将末段加 1，供 OTA 测试。
VERSION = "003.000.000"
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
    -- 真机在此完成触摸绑定，再加载采集与上报配置，并启动板上其他业务。
    local ok, err = platform.init_display(config, settings.snapshot().brightness)
    if not ok then log.error("main", err); return end -- 屏幕初始化失败
    local channels = require("channel_store")
    channels.start(settings.modbus_serial()) -- 兼容既有 UART1 和各监测因子配置。
    local temperature = channels.edit("temperature")
    require("system_params").start(temperature.interval_ms) -- 迁移旧温度通道的周期。
    require("uplink_config").start() -- 读取平台上报配置，与串口参数分别保存。
    -- 数据服务在创建页面前开始接收事件，切页时仍保留最近一次数据。
    require("device_store").start(config, platform.is_pc()) -- 设备信息、设备运行状态等
    require("env_store"):start(platform.is_pc()) -- 环境监测数据，冒号调用会自动将对象本身作为第一个参数传入
    require("fota_service").start(platform.is_pc()) -- 初始化升级状态，检查由系统更新页触发。
    -- 页面 ID 与 app_config.lua 中的 route 对应。首次打开时传入公共依赖。
    -- router.register() 用于注册页面
    router.register("home", require("home_page")) -- "home" 是页面 ID，home_page 是对应的页面模块
    router.register("environment", require("env_page"))
    router.register("device", require("device_page"))
    router.register("logs", require("run_log_page"))
    router.register("settings", require("settings_page"))
    router.open("home", { config = config, clock = clock, network = network })
    -- 页面订阅建立后启动时钟和网络服务，界面根据状态变化刷新。
    clock.start(config, platform.is_pc())
    if not platform.is_pc() then
        -- 先订阅故障事件，再启动 UART1 和 4G，可记录开机初始化失败。
        require("sd_log_service").start(clock)
        require("modbus_sensor").start()
    end
    network.start(config, platform.is_pc()) -- 真机启动 4G 桥接及联网超时整机重启任务。
    require("uplink_service").start(network) -- 平台上报在独立任务中运行。
    log.info("main", "HOME_READY", config.display.width, config.display.height)
end)
-- 初始化任务注册完成后进入调度循环。
sys.run()
