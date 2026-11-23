-- Air8603M1 V000 / 10 寸 AirLCD_1100 的板级初始化。
-- 引脚、RGB 时序和上电顺序来自合宙出厂固件的 eng_8603m1_10i_v0 配置。
local M = {}
local board = {
    screen = { id = 0, interface = "rgb", w = 1024, h = 600, pin_rst = 15,
        pclk_hz = 50000000, hspw = 20, hbp = 140, hfp = 160, vspw = 3, vbp = 20, vfp = 12 },
    touch = { port = 1, scl = 39, sda = 38, pin_rst = 14, pin_int = 51 },
    backlight = { channel = 3, frequency = 1000, startup_duty = 82, minimum_duty = 5 },
    watchdog_pin = 57,
}

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

local function init_touch(panel)
    local touch = board.touch
    -- 主控复位时触摸芯片可能仍有电，先单独复位 GT911，再交给 tp.init 选址。
    gpio.setup(touch.pin_rst, 0)
    sys.wait(20)
    gpio.set(touch.pin_rst, 1)
    sys.wait(50)

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

    local opened, device = pcall(tp.init, "gt911", { port = bus, pin_rst = touch.pin_rst,
        pin_int = touch.pin_int, int_type = gpio.FALLING, w = panel.w, h = panel.h })
    if opened and device then
        touch_bus, touch_device = bus, device
        if airui.device_bind_touch(touch_device) then
            log.info("board", "TOUCH_READY", "GT911", bus_type)
            return
        end
    end
    log.error("board", "TOUCH_FAILED", "GT911", bus_type)
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

    -- 完成出厂板级上电序列。GPIO72 保持输入，GPIO73 保持功放关闭。
    gpio.setup(44, 1)
    gpio.setup(52, 1)
    gpio.setup(72, nil)
    sys.wait(20)
    gpio.setup(74, 1)
    gpio.setup(73, 0)
    gpio.setup(58, 1)
    sys.wait(200)
    gpio.setup(64, 1)
    gpio.setup(65, 0)

    -- 即使触摸故障也点亮屏幕，便于通过串口区分显示和触摸问题。
    init_touch(panel)

    -- LCD 和触摸就绪后，使用保存的亮度点亮屏幕。
    local bl = board.backlight
    local duty = math.max(bl.minimum_duty, brightness or bl.startup_duty)
    if not set_backlight(duty) then return false, "PWM3 背光点亮失败" end
    applied_duty = duty
    log.info("board", "BACKLIGHT_READY", bl.channel, duty)
    return true
end

return M
