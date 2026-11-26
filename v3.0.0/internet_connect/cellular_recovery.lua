-- 4G 超时恢复由独立任务处理。确认超时后依次重启 4G 和大屏主控。
local store = require("settings_store")
local uptime = require("app_uptime")
local upgrade = require("fota_service")
local board = require("board_air8603m1")
local M = {}
local WAKE = "CELLULAR_RECOVERY_WAKE"

local function upgrading()
    local phase = upgrade.snapshot().phase
    return phase ~= "idle" and phase ~= "unavailable"
end

function M.start(network, on_restart_requested)
    if not rtos or type(rtos.reboot) ~= "function" then
        log.warn("cellular", "CELLULAR_RECOVERY_UNAVAILABLE")
        return
    end

    local since, probed
    local function wake() sys.publish(WAKE) end
    sys.subscribe("APP_NETWORK_CHANGED", wake)
    sys.subscribe("APP_FOTA_CHANGED", function()
        if upgrading() then since = nil end
        wake()
    end)
    sys.subscribe("APP_CELLULAR_RECONNECT_CHANGED", function()
        since = nil
        wake()
    end)

    sys.taskInit(function()
        while true do
            local state = network.snapshot()
            if state.external_ready or upgrading() then
                -- 连通后停止计时，直到出现新的外网失败或网卡掉线。OTA 结束后重新计时。
                since = nil
                sys.waitUntil(WAKE)
            else
                if not since then since, probed = uptime.ms(), false end
                local seconds = store.reconnect_seconds()
                local remaining = seconds * 1000 - (uptime.ms() - since)
                local probe_ms = math.min(3000, seconds * 500)
                local can_probe = state.ready and not probed and http and http.request

                if remaining <= 0 then
                    log.warn("cellular", "NETWORK_TIMEOUT_FULL_REBOOT", seconds)
                    -- 先撤下网卡就绪状态，避免复位过程中发起新的 OTA 下载。
                    on_restart_requested()
                    local called, reset = pcall(board.reset_cellular)
                    if called and reset then
                        log.warn("cellular", "CELLULAR_HW_RESET_PULSED")
                    else
                        log.error("cellular", "CELLULAR_HW_RESET_FAILED", reset)
                    end
                    -- 留出时间释放 4G 复位脚并输出串口日志。主控重启后重新初始化显示、触摸和联网。
                    log.warn("cellular", "AIR1603_REBOOT_REQUESTED")
                    sys.wait(200)
                    rtos.reboot()
                    return
                elseif can_probe and remaining <= probe_ms then
                    -- 在本轮剩余时间内通过 4G 发一次无业务数据的 HEAD 探测。
                    -- 避免只有 NTP 超时时误复位仍可访问外网的模组。
                    probed = true
                    local window = since
                    local ok, status = pcall(function()
                        return http.request("HEAD", "http://iot.openluat.com/", nil, nil,
                            {adapter = state.adapter, timeout = remaining}).wait()
                    end)
                    if since == window and ok and type(status) == "number" and status >= 100 and status <= 599 then
                        network.report_cellular_http(state.link_generation)
                    end
                else
                    sys.waitUntil(WAKE, can_probe and remaining - probe_ms or remaining)
                end
            end
        end
    end)
end

return M
