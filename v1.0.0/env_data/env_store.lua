-- 全局环境数据入口。缓存和仪表选择随本次运行保留，页面切换时继续接收数据。
local state = require("env_state").new()
local started = false

function state:start()
    if started then return end
    started = true
    -- 采集方发布以参数 id 为键的数值表，成功写入后再通知环境页读取缓存。
    sys.subscribe("ENVIRONMENT_DATA", function(values)
        if self:update(values) then sys.publish("ENVIRONMENT_CHANGED") end
    end)
    -- 采集超时后只清理失效项目，其他参数的缓存与选择不变。
    sys.subscribe("ENVIRONMENT_UNAVAILABLE", function(ids)
        if self:invalidate(ids) then sys.publish("ENVIRONMENT_CHANGED") end
    end)
end
return state
