-- 每种协议独立保留地址和参数，只有 selected 指向的协议允许上报。
local M = {}
local key = "air_uplink_settings"
M.protocols = {
    {id = "mqtt", title = "MQTT", port = 1883},
    {id = "tcp", title = "TCP", port = 9000},
    {id = "udp", title = "UDP", port = 9001},
}
local current = {selected = "mqtt", endpoints = {}}
local defaults = {}
for _, protocol in ipairs(M.protocols) do
    local id = protocol.id
    defaults[id] = {host = "", port = protocol.port}
    current.endpoints[id] = {host = "", port = protocol.port}
end
defaults.mqtt.topic, defaults.mqtt.client_id = "air-monitor/env", ""
defaults.mqtt.username, defaults.mqtt.password, defaults.mqtt.secure = "", "", false
defaults.udp.local_port = 0

-- 按字段模板复制，兼容旧版或部分保存记录。
local function normalize(id, input)
    local values = {}
    for name, default in pairs(defaults[id]) do
        local value = type(input) == "table" and input[name]
        if type(value) == type(default) then values[name] = value else values[name] = default end
    end
    return values
end

function M.start()
    -- 主入口已先初始化 FSKV。首次使用时保留默认 MQTT，等待填写服务器地址。
    local saved = fskv and fskv.get(key)
    if type(saved) ~= "table" then return end
    -- 旧版选择 HTTP 时，升级后暂停上报，等待用户显式选择新的协议。
    if saved.selected == "http" then
        current.selected = ""
    elseif defaults[saved.selected] or saved.selected == "" then
        current.selected = saved.selected
    end
    if type(saved.endpoints) == "table" then
        for id in pairs(defaults) do current.endpoints[id] = normalize(id, saved.endpoints[id]) end
    end
end

function M.selected() return current.selected end

function M.endpoint(id)
    return normalize(id, current.endpoints[id])
end

function M.equal(a, b)
    for field, value in pairs(a) do if b[field] ~= value then return false end end
    return true
end

-- 协议开关与地址作为一个 FSKV 记录保存，失败时保留原有活动协议。
local function commit(next_settings)
    if not (fskv and fskv.set(key, next_settings)) then return false, "保存失败，请检查配置存储" end
    current = next_settings
    sys.publish("UPLINK_CONFIG_CHANGED")
    return true
end

function M.select(id)
    if id ~= "" and not defaults[id] then return false, "上报协议无效" end
    if current.selected == id then return true end
    local ok, err = commit({selected = id, endpoints = current.endpoints})
    if ok then log.info("uplink", "UPLINK_PROTOCOL", id == "" and "off" or id) end
    return ok, err
end

function M.save(id, input)
    if not defaults[id] then return false, "上报协议无效" end
    local host, port = input.host:match("^%s*(.-)%s*$"), tonumber(input.port)
    -- 公网测试支持 IPv4 和 DNS 域名，端口取整并校验取值范围。
    if #host > 96 or (host ~= "" and not host:match("^[%w][%w%.%-]*$")) then
        return false, "请输入 IPv4 地址或域名"
    end
    if not port or port % 1 ~= 0 or port < 1 or port > 65535 then
        return false, "服务器端口应为 1 至 65535 的整数"
    end
    input.host, input.port = host, port
    if id == "udp" then
        local local_port = input.local_port == "" and 0 or tonumber(input.local_port)
        if not local_port or local_port % 1 ~= 0 or local_port < 0 or local_port > 65535 then
            return false, "本地端口应为 0 至 65535 的整数"
        end
        input.local_port = local_port

    elseif id == "mqtt" then
        if input.topic == "" or input.topic:find("[#+%c]") then return false, "请输入 MQTT 发布主题" end
    end
    local endpoint = normalize(id, input)
    if M.equal(endpoint, M.endpoint(id)) then return true end
    local endpoints = {}
    for _, protocol in ipairs(M.protocols) do endpoints[protocol.id] = current.endpoints[protocol.id] end
    endpoints[id] = endpoint
    return commit({selected = current.selected, endpoints = endpoints})
end
return M
