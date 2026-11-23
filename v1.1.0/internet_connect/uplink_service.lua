-- 上报任务负责独占连接、定时发送和失败重连。具体协议接入由各自脚本处理。
local config = require("uplink_config")
local env = require("env_store")
local M = {}
-- 每行只写一个 require，避免 LuaTools 合并脚本时把同一行的依赖拼接成一个文件名。
local protocols = {
    tcp = require("uplink_tcp"),
    udp = require("uplink_udp"),
    mqtt = require("uplink_mqtt"),
}
local WAKE = "UPLINK_SERVICE_WAKE"
local SEND_MS, CONNECT_TRIES = 5000, 20
local status = "等待上报配置"
local started

function M.status() return status end

local function set_status(message)
    if status == message then return end
    status = message
    sys.publish("UPLINK_STATUS_CHANGED")
end

function M.start(network)
    if started then return end
    started = true
    local function wake() sys.publish(WAKE) end
    sys.subscribe("UPLINK_CONFIG_CHANGED", wake)
    sys.subscribe("APP_NETWORK_CHANGED", wake)

    sys.taskInit(function()
        local channel, active_id, active, adapter, link_generation
        local remaining = CONNECT_TRIES

        local function close()
            if channel then channel:close(); channel = nil end
            remaining = CONNECT_TRIES
        end

        while true do
            local delay = SEND_MS
            local id = config.selected()
            local link = network.snapshot()
            local next_adapter = link.adapter
            -- PC 仿真可使用系统默认网卡。真机始终使用当前 AirLink 网卡。
            local endpoint = protocols[id] and config.endpoint(id)
            if id ~= active_id or next_adapter ~= adapter or link.link_generation ~= link_generation
                or (endpoint and active and not config.equal(endpoint, active)) then
                close()
                active_id, active, adapter, link_generation = id, endpoint, next_adapter, link.link_generation
            end

            if not endpoint then
                close()
                set_status("上报已关闭")
            elseif endpoint.host == "" then
                close()
                set_status("请填写并保存服务器地址")
            elseif not link.ready then
                close()
                set_status("等待网络就绪")
            elseif not (env.received.temperature and env.received.humidity) then
                set_status("等待传感器温湿度实测值")
                delay = 1000
            else
                local err
                if not channel then
                    channel, err = protocols[id].open(endpoint, next_adapter, function(data)
                        log.info("uplink", "UPLINK_RX", id, (data:gsub("%c", " ")))
                        set_status("已收到服务器回复")
                    end)
                end

                if channel and channel.state == "connecting" and remaining > 0 then
                    remaining, delay = remaining - 1, 400
                    set_status("正在连接服务器")
                elseif channel and channel.state == "ready" then
                    -- 只读取最近的实测温湿度。测试负载为 UTF-8 文本，TCP 分隔符由协议层添加。
                    local payload = string.format("温度:%.1f，湿度：%.1f", env.values.temperature, env.values.humidity)
                    local sent, send_err = channel:send(payload)
                    if sent then
                        log.info("uplink", "UPLINK_TX", id, payload)
                        set_status(id == "udp" and "UDP 已发送 · 等待对端回复" or "已发送温湿度")
                    else
                        err = send_err
                    end
                else
                    err = err or "连接中断或超时"
                end

                if err then
                    log.warn("uplink", "UPLINK_FAILED", id, err)
                    set_status(err .. " · 稍后重试")
                    close()
                end
            end
            sys.waitUntil(WAKE, delay)
        end
    end)
end

return M
