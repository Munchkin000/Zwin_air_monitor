-- MQTT 发布客户端。连接断开后由上报服务统一重连。
local M = {}

function M.open(config, adapter)
    if not (mqtt and mqtt.create) then return nil, "固件缺少 MQTT 接口" end
    -- 原生 MQTT 事件依赖 sysplus；只在启用并连接 MQTT 时初始化。
    _G.sysplus = require("sysplus")
    local client = mqtt.create(adapter, config.host, config.port, config.secure)
    if not client then return nil, "创建 MQTT 客户端失败" end
    local channel = {state = "connecting"}
    local client_id = config.client_id
    if client_id == "" then
        local id = hmeta and hmeta.devid and hmeta.devid()
        if not id or id == "" then
            local raw = mcu and mcu.unique_id and mcu.unique_id()
            id = raw and raw:toHex() or "pc"
        end
        client_id = "air-monitor-" .. id
    end
    -- 匿名连接省略认证字段，有账号时按配置发送。
    local username = config.username ~= "" and config.username or nil
    local password = username and config.password or nil
    client:auth(client_id, username, password)
    client:on(function(_, event)
        if not client then return end
        if event == "conack" then
            channel.state = "ready"
        elseif event == "disconnect" or event == "error" then
            channel.state = "failed"
        end
    end)
    if not client:connect() then
        client:close()
        client = nil
        return nil, "MQTT 连接启动失败"
    end

    function channel:send(payload)
        local packet_id = client:publish(config.topic, payload, 1)
        if type(packet_id) == "number" and packet_id > 0 then return true end
        return false, "MQTT 发布失败"
    end

    function channel:close()
        local old = client
        client = nil
        if old then old:close() end
    end

    return channel
end

return M
