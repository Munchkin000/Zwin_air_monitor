-- Air8603M1 的 4G 数据通道。Air1603 通过 UART3 上的 AirLink 访问 Air780EX2。
-- 串口参数和 WHALE 桥接地址沿用出厂固件。桥接地址属于板内网段。
local M = {}
local uart_id, uart_baud = 3, 2000000
local bridge_ip, mask, gateway = "192.168.111.1", "255.255.255.0", "192.168.111.2"

-- 由网络服务调用。回调收集板内桥接状态，外网结果由网络校时服务另行验证。
function M.start(on_status)
    -- 出厂 Air8603M1 的桥接网卡是 15。LWIP_USER0 在这两版固件里是 7。
    local adapter = socket and socket.LWIP_GP_GW
    if not (adapter and socket.setDNS and socket.dft and netdrv and netdrv.WHALE
        and uart and airlink and airlink.MODE_UART and airlink.CONF_UART_ID) then
        return false, "固件缺少 AirLink UART 或 WHALE 网卡支持"
    end

    -- 配置并启动顺序与合宙出厂的 exnetif 一致。airlink.init/start 没有返回值。
    if uart.setup(uart_id, uart_baud, 8, 1) ~= 0 then
        return false, "UART3 初始化失败"
    end
    if airlink.config(airlink.CONF_UART_ID, uart_id) == false then
        return false, "AirLink UART 配置失败"
    end
    airlink.init()
    if not netdrv.setup(adapter, netdrv.WHALE) then
        return false, "WHALE 网卡初始化失败"
    end
    airlink.start(airlink.MODE_UART)
    local ip = netdrv.ipv4(adapter, bridge_ip, mask, gateway)
    if ip ~= bridge_ip then return false, "WHALE 桥接地址设置失败" end

    -- 沿用此前出厂固件校时成功时的 DNS 顺序。板内 DNS 代理留作备用。
    socket.setDNS(adapter, 1, "114.114.114.114")
    socket.setDNS(adapter, 2, "223.5.5.5")
    socket.setDNS(adapter, 3, gateway)
    socket.dft(adapter)
    log.info("cellular", "AIRLINK_UART_STARTED", uart_id, uart_baud, adapter, bridge_ip, gateway)

    -- 同步快照处理开始订阅前已出现的 IP_READY。轮询同时检测 AirLink 对端是否失联。
    local function refresh()
        local peer_ready = airlink.ready() == true
        local ip_ready = peer_ready and netdrv.ready(adapter) == true
        local link = ip_ready and "桥接网卡已就绪" or
            (peer_ready and "等待数据网络 · 检查 SIM 和天线" or "等待 Air780EX2 模组")
        on_status(adapter, ip_ready, ip_ready and bridge_ip or nil, link)
    end
    sys.subscribe("IP_READY", function(_, event_adapter)
        if event_adapter == adapter then refresh() end
    end)
    sys.subscribe("IP_LOSE", function(event_adapter)
        if event_adapter == adapter then on_status(adapter, false, nil, "数据网络已断开") end
    end)
    refresh()
    sys.timerLoopStart(refresh, 2000)
    return true
end

return M
