-- 每个工作簿只有一张工作表。ZIP 使用 STORE，能够按块复制旧数据行。
local M = {}
local initial_crc = 0xFFFFFFFF
local crc_table = {}
for byte = 0, 255 do
    local crc = byte
    for _ = 1, 8 do
        crc = (crc >> 1) ~ ((crc & 1) == 1 and 0xEDB88320 or 0)
    end
    crc_table[byte] = crc
end

local function update_crc(crc, bytes)
    for index = 1, #bytes do
        crc = (crc >> 8) ~ crc_table[(crc ~ bytes:byte(index)) & 0xFF]
    end
    return crc
end

local function escape(text)
    return (tostring(text):gsub("[%z\1-\8\11\12\14-\31]", ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function render_row(row, index)
    local parts = {'<row r="' .. index .. '">'}
    for column, value in ipairs(row) do
        -- 当前表最多 16 列，A 到 P。测量值以数值单元格保存。
        local cell = string.char(64 + column) .. index
        if type(value) == "number" then
            parts[#parts + 1] = '<c r="' .. cell .. '"><v>' .. tostring(value) .. '</v></c>'
        else
            parts[#parts + 1] = '<c r="' .. cell .. '" t="inlineStr"><is><t xml:space="preserve">'
                .. escape(value) .. '</t></is></c>'
        end
    end
    parts[#parts + 1] = '</row>'
    return table.concat(parts)
end

local local_format = "<I4I2I2I2I2I2I4I4I4I2I2"
local central_format = "<I4I2I2I2I2I2I2I4I4I4I2I2I2I2I2I4I4"
local end_format = "<I4I2I2I2I2I4I4I2"
local local_size = string.packsize(local_format)
local xml = '<?xml version="1.0" encoding="UTF-8"?>'
local sheet_name = "xl/worksheets/sheet1.xml"
local sheet_start = xml .. '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
local sheet_end = "</sheetData></worksheet>"
local comment_size = #"ZWIN:0000000"

local function local_header(name, size, checksum)
    return string.pack(local_format, 0x04034B50, 20, 0, 0, 0, 33, checksum, size, size, #name, 0) .. name
end

local function central_entry(name, size, checksum, offset)
    return string.pack(central_format, 0x02014B50, 20, 20, 0, 0, 0, 33, checksum, size, size,
        #name, 0, 0, 0, 0, 0, offset) .. name
end

-- 工作簿关系和内容类型不会随数据变化，提前生成固定的 ZIP 条目。
local rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
local rels = "http://schemas.openxmlformats.org/package/2006/relationships"
local metadata = {
    {"[Content_Types].xml", '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        .. '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        .. '<Default Extension="xml" ContentType="application/xml"/>'
        .. '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        .. '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        .. '</Types>'},
    {"_rels/.rels", '<Relationships xmlns="' .. rels .. '"><Relationship Id="rId1" Type="' .. rel
        .. '/officeDocument" Target="xl/workbook.xml"/></Relationships>'},
    {"xl/workbook.xml", '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="'
        .. rel .. '"><sheets><sheet name="日志" sheetId="1" r:id="rId1"/></sheets></workbook>'},
    {"xl/_rels/workbook.xml.rels", '<Relationships xmlns="' .. rels .. '"><Relationship Id="rId1" Type="' .. rel
        .. '/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'},
}
local prefix, central_prefix = "", ""
for _, file in ipairs(metadata) do
    local name, bytes = file[1], xml .. file[2]
    local checksum = update_crc(initial_crc, bytes) ~ initial_crc
    central_prefix = central_prefix .. central_entry(name, #bytes, checksum, #prefix)
    prefix = prefix .. local_header(name, #bytes, checksum) .. bytes
end
local sheet_offset = #prefix + local_size + #sheet_name
local central_size = #central_prefix + string.packsize(central_format) + #sheet_name
local footer_size = string.packsize(end_format) + comment_size
local file_count = #metadata + 1

local function zip_footer(size, checksum, row_count)
    local directory = central_prefix .. central_entry(sheet_name, size, checksum, #prefix)
    -- 在 ZIP 注释中保存最后一行的行号，重启后追加时无需扫描 XML 计算行号。
    local ending = string.pack(end_format, 0x06054B50, 0, 0, file_count, file_count,
        #directory, sheet_offset + size, comment_size)
    return directory .. ending .. string.format("ZWIN:%07d", row_count)
end

local function previous_sheet(file, length)
    if file:read(#prefix) ~= prefix then return end
    local header = file:read(local_size)
    if not header or #header ~= local_size then return end
    local _, _, _, _, _, _, checksum, _, size = string.unpack(local_format, header)
    if size < #sheet_start + #sheet_end or length ~= sheet_offset + size + central_size + footer_size then return end
    if file:seek("set", length - comment_size) ~= length - comment_size then return end
    local comment = file:read(comment_size)
    local count = comment and tonumber(comment:match("^ZWIN:(%d%d%d%d%d%d%d)$"))
    if not count or count < 1 or count > 1048576 then return end
    local footer_offset = sheet_offset + size
    if file:seek("set", footer_offset) ~= footer_offset
        or file:read(central_size + footer_size) ~= zip_footer(size, checksum, count) then return end
    if file:seek("set", #prefix) ~= #prefix
        or file:read(local_size + #sheet_name) ~= local_header(sheet_name, size, checksum)
        or file:read(#sheet_start) ~= sheet_start then return end
    return size - #sheet_start - #sheet_end, checksum, count
end

function M.prepare(source, length, header, rows)
    local old_size, old_crc, count = 0, nil, 0
    if source then
        old_size, old_crc, count = previous_sheet(source, length)
        if not count then return nil, "当天工作簿格式异常，无法继续追加" end
    end
    if count + #rows > 1048576 then return nil, "当天工作簿已达到 Excel 行数上限" end
    local added = {}
    if count == 0 then
        count = 1
        added[1] = render_row(header, count)
    end
    for _, row in ipairs(rows) do
        count = count + 1
        added[#added + 1] = render_row(row, count)
    end
    local bytes = table.concat(added)
    local size = #sheet_start + old_size + #bytes + #sheet_end
    return {old_size = old_size, old_crc = old_crc, bytes = bytes, size = size, count = count,
        file_size = sheet_offset + size + central_size + footer_size}
end

local function write(file, bytes)
    local result = file:write(bytes)
    return result and (type(result) ~= "number" or result == #bytes)
end

function M.write(file, source, plan)
    -- 原工作簿留在原位。先写临时工作簿，最后回填新工作表的 CRC 和长度。
    if not write(file, prefix .. local_header(sheet_name, plan.size, 0) .. sheet_start) then return false end
    local crc = update_crc(initial_crc, sheet_start)
    local previous_rows = sheet_offset + #sheet_start
    if source and source:seek("set", previous_rows) ~= previous_rows then return false end
    local remaining = plan.old_size
    while remaining > 0 do
        local size = math.min(8192, remaining)
        local chunk = source:read(size)
        if not chunk or #chunk ~= size or not write(file, chunk) then return false end
        crc = update_crc(crc, chunk)
        remaining = remaining - size
        -- 防止较大的工作簿占用调度器，留出时间给 UI 和串口任务。
        sys.wait(1)
    end
    if source and (source:read(#sheet_end) ~= sheet_end
        or (update_crc(crc, sheet_end) ~ initial_crc) ~= plan.old_crc) then return false end
    local tail = plan.bytes .. sheet_end
    local checksum = update_crc(crc, tail) ~ initial_crc
    if not write(file, tail) or not write(file, zip_footer(plan.size, checksum, plan.count)) then return false end
    return file:seek("set", #prefix) == #prefix and write(file, local_header(sheet_name, plan.size, checksum))
end

-- 读取设备生成的日志工作簿。内存只保留当前数据块和跨块的半行。
local xml_entities = {amp = "&", lt = "<", gt = ">"}
local function read_row(xml_row)
    local values = {}
    for column, cell in xml_row:gmatch('<c r="([A-P])%d+"[^>]*>(.-)</c>') do
        local text = cell:match('<t xml:space="preserve">(.-)</t>')
        local index = column:byte() - 64
        if text then
            values[index] = (text:gsub("&([a-z]+);", xml_entities))
        else
            values[index] = tonumber(cell:match("<v>(.-)</v>") or "")
        end
    end
    return values
end

function M.read_rows(file, length, visit, cancelled)
    local remaining, expected_crc, expected_rows = previous_sheet(file, length)
    if not expected_rows then return false, "日志工作簿格式异常" end
    local crc = update_crc(initial_crc, sheet_start)
    local partial, count = "", 0
    while remaining > 0 do
        if cancelled() then return false end
        local size = math.min(8192, remaining)
        local chunk = file:read(size)
        if not chunk or #chunk ~= size then return false, "日志工作簿读取不完整" end
        crc = update_crc(crc, chunk)
        local combined, start = partial .. chunk, 1
        while true do
            local _, ending = combined:find("</row>", start, true)
            if not ending then break end
            local row = combined:sub(start, ending)
            if not row:match('^<row r="%d+">') then return false, "日志行格式异常" end
            count = count + 1
            visit(read_row(row), count)
            start = ending + 1
        end
        partial = combined:sub(start)
        if #partial > 8192 then return false, "日志行格式异常" end
        remaining = remaining - size
        if remaining > 0 then sys.wait(1) end
    end
    if partial ~= "" or count ~= expected_rows or file:read(#sheet_end) ~= sheet_end
        or (update_crc(crc, sheet_end) ~ initial_crc) ~= expected_crc then
        return false, "日志工作簿校验失败"
    end
    return true
end

return M
