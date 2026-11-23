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
    elseif name == "params" then
        -- 三条带调节钮的滑轨表示系统参数。
        line(5, 8, 27, 8); line(5, 16, 27, 16); line(5, 24, 27, 24)
        circle(11, 8, 3, true); circle(21, 16, 3, true); circle(14, 24, 3, true)
    elseif name == "serial" then
        -- 串口连接器轮廓及两排针脚。
        line(4, 8, 28, 8); line(28, 8, 25, 24)
        line(25, 24, 7, 24); line(7, 24, 4, 8)
        for i = 0, 4 do circle(8 + i * 4, 13, 1, true) end
        for i = 0, 3 do circle(10 + i * 4, 19, 1, true) end
    elseif name == "upload" then
        -- 向上箭头表示设备主动上报，底部托盘表示数据出口。
        line(16, 5, 16, 21, 3); line(9, 12, 16, 5, 3); line(16, 5, 23, 12, 3)
        line(5, 21, 5, 27); line(5, 27, 27, 27); line(27, 27, 27, 21)
    elseif name == "update" then
        -- 首尾相向的箭头表示系统更新。
        line(5, 15, 7, 10); line(7, 10, 11, 6); line(11, 6, 17, 5)
        line(17, 5, 22, 7); line(22, 7, 26, 12)
        line(20, 12, 26, 12); line(26, 12, 26, 6)
        line(27, 17, 25, 22); line(25, 22, 21, 26); line(21, 26, 15, 27)
        line(15, 27, 10, 25); line(10, 25, 6, 20)
        line(12, 20, 6, 20); line(6, 20, 6, 26)
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
    elseif name == "calendar" then
        -- 日历外框、装订线与日期点。
        rect(4, 7, 24, 22, 3)
        line(10, 3, 10, 10); line(22, 3, 22, 10); line(4, 14, 28, 14)
        for i = 0, 2 do circle(9 + 7 * i, 21, 1, true) end
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
