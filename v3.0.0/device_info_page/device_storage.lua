-- 读取 Air8603M1 的 Flash 应用文件区和板载 SD 卡容量。
local M = {}
local card = require("sd_card")

-- 将字节数换算成适合设备信息列表的单位，保留两位小数。
local function format_bytes(bytes)
    if bytes >= 1024 ^ 3 then return string.format("%.2f GiB", bytes / 1024 ^ 3) end
    if bytes >= 1024 ^ 2 then return string.format("%.2f MiB", bytes / 1024 ^ 2) end
    if bytes >= 1024 then return string.format("%.2f KiB", bytes / 1024) end
    return string.format("%d B", bytes)
end

-- Flash 统计 LuatOS 根文件系统的块数，固件、字库和脚本区有各自的分区。
local function flash_capacity()
    if not io.fsstat then
        log.warn("device_storage", "FLASH_STAT_UNAVAILABLE")
        return "固件不支持读取"
    end
    local ok, total, used, block_size, filesystem = io.fsstat("/")
    if not ok or type(total) ~= "number" or type(used) ~= "number"
        or type(block_size) ~= "number" or total <= 0 or used < 0 or used > total or block_size <= 0 then
        log.warn("device_storage", "FLASH_STAT_FAILED", ok, total, used, block_size, filesystem)
        return "容量读取失败"
    end
    local total_bytes, free_bytes = total * block_size, (total - used) * block_size
    log.info("device_storage", "FLASH_CAPACITY_BYTES", total_bytes, free_bytes)
    return format_bytes(total_bytes), format_bytes(free_bytes)
end

-- 日志后台与此页共用 SD 挂载和容量检查。
local function sd_capacity()
    local sizes, reason, detail = card.capacity()
    if not sizes then
        log.warn("device_storage", "SD_STAT_FAILED", reason, detail)
        sys.publish("APP_RUNTIME_FAULT", "sd", "SD卡读取失败（" .. reason .. "）")
        return reason
    end
    log.info("device_storage", "SD_CAPACITY_BYTES", sizes.total, sizes.free)
    return format_bytes(sizes.total), format_bytes(sizes.free)
end

-- 其中一种介质不可用时，在该介质的两行显示原因，另一种介质照常显示。
function M.read()
    local flash_total, flash_free = flash_capacity()
    local sd_total, sd_free = sd_capacity()
    return {
        flash_total = flash_total, flash_free = flash_free or flash_total,
        sd_total = sd_total, sd_free = sd_free or sd_total,
    }
end

return M
