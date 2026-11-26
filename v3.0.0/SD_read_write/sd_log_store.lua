-- 每个目录按北京时间每天一个工作簿。空间不足时清理最早的历史工作簿。
local card = require("sd_card")
local xlsx = require("sd_xlsx")
local M = {}
local folders = {"ZWIN_HIS", "ZWIN_LOG"}
local folder_for = {history = "ZWIN_HIS", fault = "ZWIN_LOG"}
local day_pattern = "%d%d%d%d_%d%d_%d%d"
local time_pattern = day_pattern .. "_%d%d_%d%d_%d%d"
local patterns = {"^" .. day_pattern .. "%.xlsx$", "^" .. time_pattern .. "%.xlsx$",
    "^" .. time_pattern .. "_%d%d%.xlsx$"}
local temporary_name = "/zwin_pending.tmp"
local reserve = 64 * 1024 -- 给 FAT32 簇分配和目录项留出空间。
local ready_mount, busy

local function scan(path, visit)
    local offset = 0
    while true do
        local ok, entries = io.lsdir(path, 64, offset)
        if not ok or type(entries) ~= "table" then return false end
        for _, entry in ipairs(entries) do
            if entry.type == 0 and type(entry.name) == "string" then visit(entry.name) end
        end
        if #entries < 64 then return true end
        offset = offset + #entries
        sys.wait(1)
    end
end

local function prepare_folders()
    if ready_mount == card.generation then return true end
    for _, folder in ipairs(folders) do
        local path = card.path .. "/" .. folder
        io.mkdir(path)
        local backups = {}
        if not scan(path, function(name)
            if name:match("^" .. day_pattern .. "%.xlsx%.bak$") then
                backups[#backups + 1] = path .. "/" .. name
            end
        end) then return false end
        -- 重启后恢复替换过程中留下的旧工作簿。正式文件存在表示替换已成功。
        for _, backup in ipairs(backups) do
            local destination = backup:sub(1, -5)
            local recovered
            if io.exists(destination) then
                recovered = os.remove(backup)
            else
                recovered = os.rename(backup, destination)
            end
            if not recovered then return false end
        end
        local temporary = path .. temporary_name
        if io.exists(temporary) and not os.remove(temporary) then return false end
    end
    ready_mount = card.generation
    return true
end

local function oldest_file(day, today)
    local oldest, filename
    local updating, active = day .. ".xlsx", today .. ".xlsx"
    for _, folder in ipairs(folders) do
        local path = card.path .. "/" .. folder
        local ok = scan(path, function(name)
            if name == updating or name == active then return end
            for _, pattern in ipairs(patterns) do
                if name:match(pattern) and (not filename or name < filename) then
                    filename, oldest = name, path .. "/" .. name
                    return
                end
            end
        end)
        if not ok then return nil, "日志目录读取失败" end
    end
    return oldest
end

local function reserve_space(size, day, today)
    for _ = 1, 16 do
        local stat, err = card.capacity()
        if not stat then return false, err end
        if stat.free >= size + reserve then return true end
        local file, cause = oldest_file(day, today)
        if not file then return false, cause or "SD 卡无可清理的旧日志" end
        if not os.remove(file) then return false, "最早日志清理失败" end
        log.info("sd_history", "SD_LOG_REMOVED", file)
    end
    return false, "SD 卡空间不足，稍后继续轮换"
end

local function write_failed(temporary, message)
    if io.exists(temporary) then os.remove(temporary) end
    ready_mount = nil
    card.invalidate()
    return false, message
end

local function write_log(kind, day, header, rows, today)
    local ok, err = card.mount()
    if not ok then return false, err end
    if not prepare_folders() then
        card.invalidate()
        return false, "无法准备日志目录或恢复旧日志"
    end
    local path = card.path .. "/" .. folder_for[kind]
    local destination = path .. "/" .. day .. ".xlsx"
    local temporary = path .. temporary_name
    local backup = destination .. ".bak"
    local existing = io.exists(destination)
    local source
    if existing then
        source = io.open(destination, "rb")
        if not source then return write_failed(temporary, "当天工作簿无法读取") end
    end
    local length = existing and io.fileSize(destination)
    local plan, reason = xlsx.prepare(source, length, header, rows)
    if source then source:close() end
    if not plan then return false, reason end
    local enough, issue = reserve_space(plan.file_size, day, today)
    if not enough then return false, issue end

    -- 留足临时副本的空间，录入失败时保留当天已有记录。
    if existing then
        source = io.open(destination, "rb")
        if not source then return write_failed(temporary, "当天工作簿无法读取") end
    end
    local file = io.open(temporary, "wb")
    local written = file and xlsx.write(file, source, plan)
    local closed = file and file:close()
    if source then source:close() end
    if not written or closed == false or io.fileSize(temporary) ~= plan.file_size then
        return write_failed(temporary, "SD 日志文件写入失败")
    end
    if existing and not os.rename(destination, backup) then
        return write_failed(temporary, "当天工作簿无法备份")
    end
    if not os.rename(temporary, destination) then
        if existing then os.rename(backup, destination) end
        return write_failed(temporary, "当天工作簿无法替换")
    end
    -- 替换已成功。如清理备份失败，下次写入前恢复现场，避免重复追加本批记录。
    if existing and not os.remove(backup) then ready_mount = nil end
    log.info("sd_history", "SD_LOG_SAVED", destination)
    return true
end

-- 查询和写入共用文件访问顺序，防止替换或轮换正在读取的文件。
local function access(operation, cancelled, ...)
    while busy do
        if cancelled and cancelled() then return false end
        sys.wait(10)
    end
    if cancelled and cancelled() then return false end
    busy = true
    local called, ok, reason = pcall(operation, ...)
    busy = false
    if called then return ok, reason end
    log.error("sd_history", "SD_LOG_OPERATION_FAILED", ok)
    return false, "日志文件操作失败"
end

function M.write(...)
    return access(write_log, nil, ...)
end

local function read_history(day, pc, visit, cancelled)
    if not pc then
        local mounted, reason = card.mount()
        if not mounted then return false, reason end
    end
    -- PC 读取启动脚本准备的目录。真机读取已经挂载的 SD 卡。
    local directory = pc and "/pc_history" or (card.path .. "/" .. folder_for.history)
    local path = directory .. "/" .. day .. ".xlsx"
    if not io.exists(path) then
        if not pc and io.exists(path .. ".bak") then
            path = path .. ".bak"
        else
            return false, "该日期暂无监测数据文件"
        end
    end
    local file = io.open(path, "rb")
    if not file then return false, "监测数据文件无法打开" end
    local called, ok, reason = pcall(xlsx.read_rows, file, io.fileSize(path), visit, cancelled)
    file:close()
    if not called then error(ok) end
    return ok, reason
end

function M.read_history(day, pc, visit, cancelled)
    return access(read_history, cancelled, day, pc, visit, cancelled)
end

return M
