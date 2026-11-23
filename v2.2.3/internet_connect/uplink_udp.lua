-- 每份温湿度报文为一个 UDP 数据报。笔记本可向报文来源的 IP 和端口回复。
local socket_uplink = require("uplink_socket")
local M = {}

function M.open(config, adapter, received)
    return socket_uplink.open(config, adapter, true, received)
end

return M
