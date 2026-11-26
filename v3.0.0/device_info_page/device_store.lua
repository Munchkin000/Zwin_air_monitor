-- 设备信息缓存由程序入口启动，允许驱动在页面关闭时继续更新数据。
local M = {}
local current, started = {}, false
local storage, storage_refresh_timer
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
-- 进入设备信息页时读取容量。短暂延后，让页面先创建并订阅刷新事件。
function M.refresh_storage()
    if not storage or storage_refresh_timer then return end
    storage_refresh_timer = sys.timerStart(function()
        storage_refresh_timer = nil
        M.update(storage.read())
    end, 1)
end

function M.start(config, is_pc)
    if started then return end
    started = true
    -- PC 显示仿真状态。实际容量仅由真机上的存储驱动读取。
    current = { name = config.device.name, device_id = config.device.id,
        board = config.device.board .. "（目标硬件）", chip = config.device.chip .. "（目标模组）",
        version = VERSION, runtime = "LuatOS PC 仿真",
        sim = "未接入 · PC 仿真", iccid = "未接入", flash_total = "不适用 · PC 仿真",
        flash_free = "不适用 · PC 仿真", sd_total = "不适用 · PC 仿真", sd_free = "不适用 · PC 仿真" }
    -- 真机上显示实际运行平台；尚未接入的硬件信息使用独立的状态提示。
    if is_pc == false then
        current.board, current.chip = config.device.board, config.device.chip
        current.runtime = "LuatOS " .. rtos.bsp()
        current.sim, current.iccid = "模组未上报", "模组未上报"
        current.flash_total, current.flash_free = "待读取", "待读取"
        current.sd_total, current.sd_free = "待读取", "待读取"
        storage = require("device_storage")
    end
    sys.subscribe("DEVICE_INFO_DATA", M.update)
    -- 运营商和信号集中显示在设备信息中，使用网络服务的同一份状态。
    sys.subscribe("APP_NETWORK_CHANGED", function()
        local cellular = require("service_network").snapshot().cellular
        M.update({sim = cellular.sim, operator = cellular.operator or "未接入", signal = cellular.signal or "未接入"})
    end)
end
return M
