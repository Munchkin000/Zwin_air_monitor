-- 根据构建配置初始化显示和中文字库，向启动入口返回成功标志及错误原因。
local M = {}
-- 根据构建配置判断是否为 PC 仿真模式
function M.is_pc() return not require("build_config").USE_HARDWARE end

-- 初始化图形显示和中文字库
function M.init_display(config, brightness)
    -- 同时检查构建开关和实际运行平台，防止仿真脚本误用到真机。
    local bsp, pc = rtos.bsp():upper(), M.is_pc()
    if pc and not bsp:find("PC", 1, true) then
        return false, "当前使用 PC 配置，请将 USE_HARDWARE 设为 true 后下载"
    end
    if not pc and bsp ~= "AIR1603" then
        return false, "真机配置面向 Air8603M1（Air1603），当前 BSP: " .. bsp
    end
    -- airui 模块不存在、没有被加载时报错。
    if not airui then
        return false, "AirUI is required"
    end
    if pc then
        -- 尝试创建 PC 显示画布。V2039 模拟器使用 ARGB8888。
        if not airui.init(config.display.width, config.display.height, airui.COLOR_FORMAT_ARGB8888) then
            return false, "AirUI initialization failed"
        end
    else
        local ok, err = require("board_air8603m1").init_display(config.display, brightness)
        if not ok then return false, err end
    end
    -- 页面标签通过 hzfont 显示中文，进入页面前需要加载该字库。
    if airui.font_load({ type = "hzfont", size = 20, cache_size = 512, antialias = 3 }) == false then
        return false, "Chinese font initialization failed"
    end
    return true
end

-- 滑块通过平台层访问 PWM，PC 仿真只更新界面和配置。
function M.apply_brightness(level)
    if M.is_pc() then return true end
    return require("board_air8603m1").apply_brightness(level)
end

return M
