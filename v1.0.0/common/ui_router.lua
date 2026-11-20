-- 页面模块提供 create(context)，返回包含 root 和 destroy() 的实例。
-- 路由一次只保留一个页面实例。时钟和数据服务由程序入口启动，独立于页面。
local M = {}
local pages, current, context = {}, nil, nil -- `nil`代表无页面

-- 注册页面
function M.register(id, page)
    -- 传入的 page 必须拥有`create`函数，否则直接报错
    assert(type(page.create) == "function", "Page needs create(context)")
    pages[id] = page
end
-- 判断页面是否已经注册
function M.has(id)
    return pages[id] ~= nil
end
-- 打开页面（页面跳转核心接口）
function M.open(id, next_context)
    assert(pages[id], "Unknown page: " .. tostring(id))
    -- 首次打开主页时传入依赖，后续页面跳转沿用同一份配置和服务。
    context = next_context or context
    -- 果存在`current`旧页面实例 → **调用 `current:destroy()` 销毁旧页面**
    if current then
        current:destroy()
    end
    current = pages[id].create(context)
    return current
end

return M
