-- TCP 和 UDP 共用套接字生命周期，协议文件负责各自的报文边界。
local M = {}

function M.open(config, adapter, udp, received)
    if not (socket and zbuff) then return nil, "固件缺少套接字接口" end
    local channel = {state = "connecting"}
    local ctrl
    local buffer = zbuff.create(512)

    -- 收到笔记本回复后读取原始字节。仅用于连通性测试，不作为控制指令。
    local function on_event(sc, event, param)
        if not ctrl then return end
        if event == socket.ON_LINE then
            channel.state = (param == nil or param == 0) and "ready" or "failed"
        elseif event == socket.CLOSED then
            channel.state = "failed"
        elseif event == socket.EVENT then
            repeat
                buffer:seek(0)
                local ok, length = socket.rx(sc, buffer)
                if not ok then channel.state = "failed"; return end
                if not length or length <= 0 then return end
                received(buffer:query(0, math.min(length, 256)))
            until false
        end
    end

    function channel:close()
        if not ctrl then return end
        local old = ctrl
        ctrl = nil
        socket.close(old)
        socket.release(old)
        buffer:del()
    end

    function channel:send(payload)
        local ok, full = socket.tx(ctrl, payload)
        if not ok then return false, "发送失败" end
        if full then return false, "发送缓冲区已满" end
        return true
    end

    ctrl = socket.create(adapter, on_event)
    if not ctrl then buffer:del(); return nil, "创建套接字失败" end
    if not socket.config(ctrl, config.local_port or 0, udp) then
        channel:close()
        return nil, "配置套接字失败"
    end
    local ok, connected = socket.connect(ctrl, config.host, config.port)
    if not ok then
        channel:close()
        return nil, "连接失败"
    end
    if connected then channel.state = "ready" end
    return channel
end

return M
