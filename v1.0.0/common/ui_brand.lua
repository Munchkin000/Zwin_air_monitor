-- 创建各页面共用的公司标识。图片资源按 Air1603 的解码要求预处理。
local ui = require("ui_components")
local theme = require("ui_theme")
local M = {}

local ram_logo = "/ram/brand_logo.png"
local embedded_logo
local resolved_path

local function check_png(path)
    local file = io.open(path, "rb")
    if not file then
        log.warn("brand", "LOGO_MISSING", path)
        return false
    end
    -- 读取 PNG 文件头和 IHDR 的基础字段。尺寸或格式不兼容时尝试内置图片。
    local header = file:read(29)
    local bytes = file:seek("end")
    file:close()
    if not header or #header < 29 or header:sub(1, 8) ~= "\137PNG\r\n\26\n" or header:sub(13, 16) ~= "IHDR" then
        log.warn("brand", "LOGO_BAD_PNG", path)
        return false
    end
    local width, height = string.unpack(">I4I4", header, 17)
    if width <= 0 or height <= 0 or width % 16 ~= 0 or height % 16 ~= 0 then
        log.warn("brand", "LOGO_UNALIGNED", path, width, height)
        return false
    end
    -- PNG 头第 25、26、29 字节分别为位深、颜色类型和隔行方式。
    if header:byte(25) ~= 8 or header:byte(26) ~= 2 or header:byte(29) ~= 0 then
        log.warn("brand", "LOGO_FORMAT_UNSUPPORTED", path)
        return false
    end
    log.info("brand", "LOGO_RESOURCE", path, bytes, width, height)
    return true
end

-- LuaTools 漏打包 PNG 时，从同一份 Logo 恢复。/ram 是易失文件系统，不写 Flash。
local function restore_logo()
    if not (crypto and crypto.base64_decode) then
        log.error("brand", "LOGO_EMBEDDED_DECODE_UNAVAILABLE")
        return nil
    end
    local data = crypto.base64_decode((embedded_logo:gsub("%s", "")))
    if type(data) ~= "string" or #data == 0 then
        log.error("brand", "LOGO_EMBEDDED_DECODE_FAILED")
        return nil
    end
    local file = io.open(ram_logo, "wb")
    if not file then
        log.error("brand", "LOGO_RAM_OPEN_FAILED", ram_logo)
        return nil
    end
    local ok = file:write(data)
    file:close()
    if not ok or not check_png(ram_logo) then
        log.error("brand", "LOGO_RAM_WRITE_FAILED", ram_logo)
        return nil
    end
    log.info("brand", "LOGO_EMBEDDED_READY", ram_logo, #data)
    return ram_logo
end

local function create_image(parent, layout, brand, path)
    local p = layout.px
    local y = (88 - brand.logo_height) / 2
    -- 在 1024×600 基准下以 208×64 原尺寸居中显示，其他屏幕尺寸随页面等比缩放。
    local image = airui.image({ parent = parent, src = path,
        x = p(48), y = p(y), w = p(brand.logo_width), h = p(brand.logo_height),
        fit = layout.scale == 1 and "center" or "contain", zoom = 256, opacity = 255 })
    log.info("brand", "LOGO_CREATE", image and "ok" or "failed", layout.scale == 1 and "1:1" or "scaled", path)
    return image
end

function M.create(parent, layout, brand)
    -- 首个页面确认来源，后续页面共用已检查的路径。
    local path = resolved_path
    if not path and check_png(brand.logo) then path = brand.logo end
    local image = path and create_image(parent, layout, brand, path)
    if not image and path ~= ram_logo then
        path = restore_logo()
        image = path and create_image(parent, layout, brand, path)
    end
    if image then
        resolved_path = path
        return image
    end
    resolved_path = nil
    return ui.label(parent, layout, "智易时代", 48, 27, brand.logo_width, 40, 28, theme.accent)
end

-- 内置副本由 assets/brand_logo.png 转成 Base64。换图时同步更新此段。
embedded_logo = [=[
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
]=]

return M
