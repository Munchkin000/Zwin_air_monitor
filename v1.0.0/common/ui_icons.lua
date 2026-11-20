-- 使用 AirUI 图形绘制应用图标。图形坐标以 32×32 为基准。
local M = {}

function M.draw(parent, layout, name, x, y, size, color)
    local items = {}
    local function line(x1, y1, x2, y2, width)
        items[#items + 1] = { type = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2,
            width = width or 2, color = color, round_start = true, round_end = true }
    end
    local function circle(cx, cy, r, fill)
        items[#items + 1] = { type = "circle", cx = cx, cy = cy, r = r, width = 2,
            color = color, fill = fill or false, fill_color = color }
    end
    local function rect(rx, ry, w, h, radius)
        items[#items + 1] = { type = "rect", x = rx, y = ry, w = w, h = h,
            radius = radius or 2, width = 2, color = color }
    end
    if name == "settings" then
        circle(16, 16, 10)
        circle(16, 16, 4)
        for i = 0, 7 do
            local a = i * math.pi / 4
            line(16 + math.cos(a) * 10, 16 + math.sin(a) * 10,
                 16 + math.cos(a) * 14, 16 + math.sin(a) * 14, 3)
        end
    elseif name == "environment" then
        -- 温度计及表示气流的横线。
        line(10, 5, 10, 20); line(16, 5, 16, 20)
        line(10, 5, 16, 5); circle(13, 24, 6)
        line(13, 12, 13, 25, 2); line(22, 10, 29, 10); line(22, 16, 27, 16)
        line(22, 22, 29, 22)
    elseif name == "device" or name == "log" then
        rect(6, 5, 21, 25, 3); rect(11, 2, 11, 6, 2)
        line(10, 16, 12, 18); line(12, 18, 16, 14)
        line(20, 16, 23, 16); line(10, 24, 23, 24)
    elseif name == "folder" then
        line(3, 9, 3, 27); line(3, 27, 29, 27); line(29, 27, 29, 9)
        line(3, 9, 3, 5); line(3, 5, 13, 5); line(13, 5, 17, 9)
        line(17, 9, 29, 9); line(4, 13, 28, 13)
    elseif name == "brand" then
        line(5, 6, 27, 6, 3); line(27, 6, 5, 26, 3); line(5, 26, 27, 26, 3)
    elseif name == "brightness" then
        circle(16, 16, 7)
        for i = 0, 7 do
            local a = i * math.pi / 4
            line(16 + math.cos(a) * 10, 16 + math.sin(a) * 10,
                 16 + math.cos(a) * 14, 16 + math.sin(a) * 14)
        end
    elseif name == "time" then
        circle(16, 16, 12)
        line(16, 8, 16, 16)
        line(16, 16, 22, 19)
    elseif name == "network" then
        for i = 0, 3 do rect(4 + i * 7, 24 - i * 5, 3, 4 + i * 5, 1) end
    else
        line(16, 7, 16, 25); line(7, 16, 25, 16)
    end
    -- 按图标目标尺寸和页面比例转换坐标，线宽至少为一个像素。
    local factor = layout.scale * size / 32
    for _, item in ipairs(items) do
        for _, key in ipairs({ "x1", "y1", "x2", "y2", "cx", "cy", "r", "x", "y", "w", "h", "radius", "width" }) do
            if item[key] then item[key] = math.floor(item[key] * factor + 0.5) end
        end
        item.width = math.max(1, item.width)
    end
    return airui.shape({ parent = parent, x = layout.px(x), y = layout.px(y),
        w = layout.px(size), h = layout.px(size), items = items })
end

return M
