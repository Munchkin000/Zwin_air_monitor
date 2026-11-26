-- Air8603M1 V000 / 10 寸 AirLCD_1100 的板级初始化。
-- 引脚、RGB 时序和上电顺序来自合宙出厂固件的 eng_8603m1_10i_v0 配置。
local M = {}
local board = {
    screen = { id = 0, interface = "rgb", w = 1024, h = 600, pin_rst = 15,
        pclk_hz = 50000000, hspw = 20, hbp = 140, hfp = 160, vspw = 3, vbp = 20, vfp = 12 },
    -- V1032 的 GT911 核心驱动支持轮询。改为 false 可恢复 GPIO51 下降沿模式，便于实板对照。
    touch = { port = 1, scl = 39, sda = 38, pin_rst = 14, pin_int = 51, polling = true },
    backlight = { channel = 3, frequency = 1000, startup_duty = 82, minimum_duty = 5 },
    watchdog_pin = 57,
    cellular_reset_pin = 72,
}

-- Air8603 原理图第 2、11 页：GPIO72 输出高电平时，Q1 将 Air780EX2 的 RESET_N 拉低。
-- 直接触发板载复位，不依赖 UART3 或 AirLink。按模组时序保持至少 500ms，再恢复成输入。
function M.reset_cellular()
    local pin = board.cellular_reset_pin
    if not gpio.setup(pin, 1) then return false end
    sys.wait(600)
    gpio.set(pin, 0)
    gpio.setup(pin, nil)
    return true
end

-- Air153D 看门狗经 NPN 三极管反相。沿用出厂波形和 180 秒周期。
-- 单独的协程定期喂狗，界面切换、4G 等待和校时都会让出调度。
local function start_watchdog()
    local pin = board.watchdog_pin
    gpio.setup(pin, 0, gpio.PULLUP)
    sys.taskInit(function()
        while true do
            gpio.set(pin, 1)
            sys.wait(2000)
            gpio.set(pin, 0)
            sys.wait(250)
            gpio.set(pin, 1)
            sys.wait(200)
            gpio.set(pin, 0)
            log.info("board", "WATCHDOG_FED", pin)
            sys.wait(177550)
        end
    end)
end

local applied_duty -- 记录已生效的 PWM 占空比，避免重复更新。
local function set_backlight(duty)
    local bl = board.backlight
    -- PWM3 是出厂板配置的通道，直接使用核心库的默认复用。
    return pwm.setup(bl.channel, bl.frequency, duty, 0, 100) and pwm.start(bl.channel)
end

-- 滑块 0% 表示最低可操作亮度，保留 5% 背光以便继续触摸操作。
function M.apply_brightness(level)
    local bl = board.backlight
    local duty = math.max(bl.minimum_duty, level)
    if duty == applied_duty then return true end
    -- 已启动 PWM 后直接改占空比。旧固件不支持该接口时用初始化接口重新设置。
    local ok = pwm.setDuty and pwm.setDuty(bl.channel, duty)
    if not ok then ok = set_backlight(duty) end
    if not ok then
        log.error("board", "BACKLIGHT_UPDATE_FAILED", bl.channel, duty)
        return false, "屏幕背光调节失败"
    end
    applied_duty = duty
    return true
end

-- 保持软件 I²C 对象和触摸句柄存活，供 AirUI 运行期间使用。
local touch_bus, touch_device

local function reset_touch(touch)
    -- 主控热重启时 GT911 可能仍在运行。先按住 RST，再驱动 INT，避免与芯片争用中断线。
    gpio.setup(touch.pin_rst, 0)
    sys.wait(20)
    -- 释放 RST 时保持 INT 低电平，选定 7 位地址 0x5D。
    gpio.setup(touch.pin_int, 0)
    sys.wait(2)
    gpio.set(touch.pin_rst, 1)
    sys.wait(60)
    -- 选址完成后将 INT 恢复为输入。轮询模式下保留输入，芯片可自行驱动这条线。
    gpio.setup(touch.pin_int, nil)
end

local function init_touch(panel)
    local touch = board.touch

    -- 使用独立测试中已验证的同一组引脚，通过软件 I²C 避开硬件 I²C1 忙时超时。
    local bus, bus_type
    if type(i2c.createSoft) == "function" then
        local ok, handle = pcall(i2c.createSoft, touch.scl, touch.sda, 5)
        if ok and handle then bus, bus_type = handle, "software" end
    end
    if not bus then
        -- 兼容未提供软件 I²C 接口的底层，串口保留降级原因。
        log.warn("board", "TOUCH_I2C_SOFTWARE_UNAVAILABLE")
        local result = i2c.setup(touch.port, i2c.SLOW, true)
        if result ~= 1 and result ~= true then
            log.error("board", "TOUCH_I2C_SETUP_FAILED", touch.port, result)
            return
        end
        bus, bus_type = touch.port, "hardware"
    end
    log.info("board", "TOUCH_I2C", bus_type, touch.scl, touch.sda)

    -- GPIO14 复位由 Lua 负责。V1032 省略 pin_int 会使用默认值 0。
    -- 轮询时显式传入 255，核心才会跳过 GPIO 中断并启动 GT911 采样定时器。
    local options = { port = bus, pin_rst = 255, pin_int = touch.polling and 255 or touch.pin_int,
        int_type = gpio.FALLING, w = panel.w, h = panel.h }
    local input_mode = touch.polling and "polling" or "interrupt"
    log.info("board", "TOUCH_INPUT_MODE", input_mode)
    -- 有限次数的探测优先执行。成功即进入主页，失败时仍继续启动以保留本地和远程诊断。
    local retry_delays = { 0, 200, 500, 1000 }
    for attempt, delay_ms in ipairs(retry_delays) do
        if delay_ms > 0 then
            sys.wait(delay_ms)
            log.warn("board", "TOUCH_RETRY", bus_type, attempt)
        end
        reset_touch(touch)

        local opened, device = pcall(tp.init, "gt911", options)
        if not opened then
            log.error("board", "TOUCH_FAILED", "GT911", bus_type, "init_error", attempt, device)
            return
        end
        if device then
            -- 触摸核心库只允许成功初始化一次，拿到句柄后只绑定，不再复位探测。
            touch_bus, touch_device = bus, device
            if airui.device_bind_touch(touch_device) then
                log.info("board", "TOUCH_READY", "GT911", bus_type, attempt, input_mode)
            else
                log.error("board", "TOUCH_FAILED", "GT911", bus_type, "bind_failed", attempt)
            end
            return
        end
    end
    log.error("board", "TOUCH_FAILED", "GT911", bus_type, "probe_failed", #retry_delays)
end

function M.init_display(config, brightness)
    if not (gpio and pwm and display and airui and i2c and tp) then
        return false, "缺少显示或触摸核心库，请检查 Air1603 102 号固件"
    end
    local panel = board.screen
    if config.width ~= panel.w or config.height ~= panel.h then
        return false, "Air8603M1 板级配置要求 1024×600"
    end

    start_watchdog()
    -- 先压灭背光并按出厂顺序上电，避免 LCD 初始化时闪屏。
    if not set_backlight(0) then return false, "PWM3 背光初始化失败" end
    gpio.setup(12, 1)
    gpio.setup(56, 1)
    sys.wait(100)

    -- display 驱动分配板载帧缓冲，AirUI 通过 RGB565 后端使用该缓冲。
    local ok, err = display.init("custom", panel)
    if not ok then return false, "LCD 初始化失败: " .. tostring(err) end
    log.info("board", "LCD_READY", panel.w, panel.h)
    if not airui.init(panel.w, panel.h, airui.COLOR_FORMAT_RGB565) then
        return false, "AirUI RGB565 初始化失败"
    end

    -- 完成出厂板级上电序列。4G 复位控制脚平时保持输入，GPIO73 保持功放关闭。
    gpio.setup(44, 1)
    gpio.setup(52, 1)
    gpio.setup(board.cellular_reset_pin, nil)
    sys.wait(20)
    gpio.setup(74, 1)
    gpio.setup(73, 0)
    gpio.setup(58, 1)
    sys.wait(200)
    gpio.setup(64, 1)
    gpio.setup(65, 0)

    -- 本任务先完成触摸检测和 AirUI 绑定，再让启动入口创建页面、启动采集与联网。
    init_touch(panel)

    -- 使用保存的亮度点亮屏幕。触摸探测最终失败时也要保留 LCD 供现场观察。
    local bl = board.backlight
    local duty = math.max(bl.minimum_duty, brightness or bl.startup_duty)
    if not set_backlight(duty) then return false, "PWM3 背光点亮失败" end
    applied_duty = duty
    log.info("board", "BACKLIGHT_READY", bl.channel, duty)
    return true
end

return M
