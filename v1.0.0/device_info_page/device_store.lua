-- 设备信息缓存由程序入口启动，允许驱动在页面关闭时继续更新数据。
local M = {}
local current, started = {}, false
local allowed = {}
for _, field in ipairs(require("device_fields")) do allowed[field.id] = true end
-- 返回副本，防止页面改动共享缓存。
function M.snapshot()
    local copy = {}
    for key, value in pairs(current) do copy[key] = value end
    return copy
end
-- 设备信息按字段合并。只接受已登记字段的字符串，发生变化时通知页面。
function M.update(values)
    if type(values) ~= "table" then return false end
    local changed = false
    for key, value in pairs(values) do
        if allowed[key] and type(value) == "string" and value ~= current[key] then
            current[key], changed = value, true
        end
    end
    if changed then sys.publish("DEVICE_INFO_CHANGED") end
    return changed
end
function M.start(config, is_pc)
    if started then return end
    started = true
    -- PC 阶段使用配置项和占位状态。SIM、定位与存储数值由后续设备驱动提供。
    current = { name = config.device.name, device_id = config.device.id,
        board = config.device.board .. "（目标硬件）", chip = config.device.chip .. "（目标模组）",
        version = VERSION, runtime = "LuatOS PC 仿真",
        sim = "未接入 · PC 仿真", iccid = "未接入", location = "未接入定位数据",
        longitude = "--", latitude = "--", flash_total = "不适用 · PC 仿真",
        flash_free = "不适用 · PC 仿真", sd_total = "未接入 SD 卡", sd_free = "未接入 SD 卡" }
    -- 真机上显示实际运行平台；尚未接入的硬件信息使用独立的状态提示。
    if is_pc == false then
        current.board, current.chip = config.device.board, config.device.chip
        current.runtime = "LuatOS " .. rtos.bsp()
        current.sim, current.iccid = "模组未上报", "模组未上报"
        current.flash_total, current.flash_free = "待接入", "待接入"
    end
    sys.subscribe("DEVICE_INFO_DATA", M.update)
end
return M
