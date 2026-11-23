-- Air8603M1 的公共 SD 卡挂载入口。设备信息和日志共用同一次挂载。
local M = {path = "/sd", generation = 0}
local SPI_ID, CS, SECTOR_BYTES = 1, 8, 512
local mounted = false

function M.mount()
    if mounted then return true end
    if not (spi and spi.setup and gpio and gpio.setup and fatfs and fatfs.SPI
        and fatfs.mount and fatfs.getfree) then
        return false, "固件缺少 SD 驱动"
    end
    -- GPIO74 由板级初始化供电。挂载失败保留 SD 原有数据。
    gpio.setup(CS, 1)
    if spi.setup(SPI_ID, nil, 0, 0, 8, 400000) ~= 0 then return false, "SD 卡接口初始化失败" end
    local ok, err = fatfs.mount(fatfs.SPI, M.path, SPI_ID, CS, 20000000, nil, 1, false)
    if not ok then return false, "SD 卡未就绪", err end
    mounted = true
    M.generation = M.generation + 1 -- 每次重新挂载后重新检查日志备份。
    log.info("device_storage", "SD_MOUNTED", M.path)
    return true
end

-- 句柄都关闭后再清理失效挂载。后续后台探测会尝试重新挂载。
function M.invalidate()
    if mounted and fatfs.unmount and fatfs.unmount(M.path) then mounted = false end
end

function M.capacity()
    local ok, err, detail = M.mount()
    if not ok then return nil, err, detail end
    local stat, cause = fatfs.getfree(M.path)
    local total, free = stat and stat.total_sectors, stat and stat.free_sectors
    if type(total) ~= "number" or type(free) ~= "number" or total <= 0 or free < 0 or free > total then
        M.invalidate()
        return nil, "容量读取失败", cause
    end
    return {total = total * SECTOR_BYTES, free = free * SECTOR_BYTES}
end

return M
