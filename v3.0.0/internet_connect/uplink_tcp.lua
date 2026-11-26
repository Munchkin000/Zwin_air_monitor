-- 设备作为 TCP 客户端，笔记本作为 TCP Server。每条文本附加换行用于分帧。
local socket_uplink = require("uplink_socket")
local M = {}

function M.open(config, adapter, received)
    local channel, err = socket_uplink.open(config, adapter, false, received)
    if not channel then return nil, err end
    local send = channel.send
    function channel:send(payload) return send(self, payload .. "\r\n") end
    return channel
end

return M
