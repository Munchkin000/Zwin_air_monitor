-- Air8603M1 的 4G 数据通道。Air1603 通过 UART3 上的 AirLink 访问 Air780EX2。
-- 串口参数和 WHALE 桥接地址沿用出厂固件。桥接地址属于板内网段。
local uptime = require("app_uptime")
local M = {}
local uart_id, uart_baud = 3, 2000000
local bridge_ip, mask, gateway = "192.168.111.1", "255.255.255.0", "192.168.111.2"
local peer_grace_ms = 4000

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

    -- 沿用已上板验证的升级用 DNS 顺序。优先使用板内代理，公网 DNS 作为备用。
    local function configure_dns()
        socket.setDNS(adapter, 1, gateway)
        socket.setDNS(adapter, 2, "223.5.5.5")
        socket.setDNS(adapter, 3, "114.114.114.114")
    end
    configure_dns()
    socket.dft(adapter)
    log.info("cellular", "AIRLINK_UART_STARTED", uart_id, uart_baud, adapter, bridge_ip, gateway)

    local bridge_ready = false
    local peer_unready_since
    -- 网卡 IP 状态和 AirLink 最近的通讯状态分别读取。
    -- 仅已就绪的网卡可容忍短时对端超时，避免反复关闭 MQTT 等存活连接。
    local function refresh()
        local peer_ready = airlink.ready() == true
        local net_ready = netdrv.ready(adapter) == true
        if peer_ready then
            peer_unready_since = nil
            bridge_ready = net_ready
        else
            local now = uptime.ms()
            peer_unready_since = peer_unready_since or now
            bridge_ready = bridge_ready and net_ready and now - peer_unready_since < peer_grace_ms
        end
        local link = bridge_ready and "桥接网卡已就绪" or
            (peer_ready and "等待数据网络 · 检查 SIM 和天线" or "AirLink 对端通讯超时")
        on_status(adapter, bridge_ready, bridge_ready and bridge_ip or nil, link, peer_ready)
    end
    sys.subscribe("IP_READY", function(_, event_adapter)
        if event_adapter == adapter then
            -- 网卡重新上线时内核可能重置 DNS，需要再次配置板内代理。
            configure_dns()
            refresh()
        end
    end)
    sys.subscribe("IP_LOSE", function(event_adapter)
        if event_adapter == adapter then
            -- 底层明确报告断开时立即更新状态，不走对端探测的容错时间。
            bridge_ready = false
            on_status(adapter, false, nil, "网卡 IP_LOSE · 数据网络已断开")
        end
    end)
    refresh()
    sys.timerLoopStart(refresh, 2000)
    return true
end

return M
