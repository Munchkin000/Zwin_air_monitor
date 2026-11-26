-- 调度使用开机时间，手动改时间和校时只影响文件中的时间戳。
local M = {}
local last, elapsed = nil, 0
function M.ms()
    if mcu.ticks2 then
        local high, low = mcu.ticks2(1)
        if high and low then return high * 1000000 + low end
    end
    local tick = mcu.ticks()
    elapsed = elapsed + ((tick - (last or tick)) & 0xFFFFFFFF)
    last = tick
    return (elapsed * 1000) // mcu.hz()
end
return M
