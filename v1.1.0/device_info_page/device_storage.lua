-- 读取 Air8603M1 的 Flash 应用文件区和板载 SD 卡容量。
local M = {}
local SD_PATH = "/sd"
-- 与 Air8603M1 出厂配置一致。GPIO74 已在板级上电流程打开 SD_3V3。
local SD_SPI, SD_CS = 1, 8
local SD_INIT_HZ, SD_TRANSFER_HZ = 400000, 20000000
local SD_SECTOR_BYTES = 512 -- FatFs 返回的扇区数量以 512 字节为单位。
local sd_mounted = false

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

-- 第一次进入页面时尝试挂载，挂载成功后复用同一文件系统。
local function sd_capacity()
    if not (spi and spi.setup and gpio and gpio.setup and fatfs and fatfs.SPI
        and fatfs.mount and fatfs.getfree) then
        log.warn("device_storage", "SD_DRIVER_UNAVAILABLE")
        return "固件不支持读取"
    end
    if not sd_mounted then
        -- 初始化时使用低速 SPI，由 FatFs 用 GPIO8 管理片选以及后续传输时钟。
        gpio.setup(SD_CS, 1)
        local result = spi.setup(SD_SPI, nil, 0, 0, 8, SD_INIT_HZ)
        if result ~= 0 then
            log.warn("device_storage", "SD_SPI_SETUP_FAILED", result)
            return "SD 卡接口初始化失败"
        end
        -- SD 卡已上电，传 nil 跳过电源复位。最后一个 false 关闭挂载失败后的自动格式化。
        local ok, err = fatfs.mount(fatfs.SPI, SD_PATH, SD_SPI, SD_CS, SD_TRANSFER_HZ, nil, 1, false)
        if not ok then
            log.warn("device_storage", "SD_MOUNT_FAILED", err)
            return "SD 卡未就绪"
        end
        sd_mounted = true
        log.info("device_storage", "SD_MOUNTED", SD_PATH)
    end

    local stat, err = fatfs.getfree(SD_PATH)
    local total = stat and stat.total_sectors
    local free = stat and stat.free_sectors
    if type(total) ~= "number" or type(free) ~= "number" or total <= 0 or free < 0 or free > total then
        log.warn("device_storage", "SD_STAT_FAILED", err)
        return "容量读取失败"
    end
    local total_bytes, free_bytes = total * SD_SECTOR_BYTES, free * SD_SECTOR_BYTES
    log.info("device_storage", "SD_CAPACITY_BYTES", total_bytes, free_bytes)
    return format_bytes(total_bytes), format_bytes(free_bytes)
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
