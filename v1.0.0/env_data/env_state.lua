-- 环境监测状态包含当前数值、已接入标记、已选仪表和仪表窗口起始位置。
local data = require("env_data")
local M = {}
-- 工厂函数，创建一份全新环境状态实例
function M.new()
    local state = { selected = { table.unpack(data.default_selected) }, first = 1,
                    values = {}, received = {} }
    for _, metric in ipairs(data.metrics) do
        state.values[metric.id] = metric.default
    end
    -- 一次显示四项。限制起始位置，确保末尾窗口尽量填满。
    function state:last_first()
        return math.max(1, #self.selected - 3)
    end
    -- 生成勾选标记数组，供给编辑弹窗 env_editor 使用
    function state:selection_flags()
        local flags = {}
        for index = 1, #data.metrics do flags[index] = false end
        for _, index in ipairs(self.selected) do flags[index] = true end
        return flags -- 弹窗使用独立草稿，取消时直接丢弃。
    end
    -- 按配置顺序保存勾选结果。只有内容变化时才重置到第一组仪表。
    function state:apply_selection(flags)
        if type(flags) ~= "table" then return false end
        local next_selection = {}
        -- 按照gauge_order仪表盘渲染顺序，收集用户勾选的项
        for _, index in ipairs(data.gauge_order) do
            if flags[index] == true then next_selection[#next_selection + 1] = index end
        end
        -- 判断前后选择集合是否发生变化
        local changed = #next_selection ~= #self.selected
        for index, metric in ipairs(next_selection) do
            if self.selected[index] ~= metric then changed = true end
        end
        if not changed then return false end -- 没有变化直接返回false，不修改状态
        self.selected, self.first = next_selection, 1 -- 更新选中列表，滚动位置重置到窗口开头first=1
        return true -- 返回true代表状态发生变更
    end
    function state:slide(direction)
        local previous = self.first
        self.first = math.max(1, math.min(self:last_first(), self.first + direction))
        return self.first ~= previous
    end
    -- 只写入本次提供的有限数值，省略或无效的参数保留上一次状态。
    function state:update(values)
        if type(values) ~= "table" then return false end
        local changed = false
        for _, metric in ipairs(data.metrics) do
            local value = values[metric.id]
            if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
                self.values[metric.id], self.received[metric.id], changed = value, true, true
            end
        end
        return changed
    end
    -- 采集端连续失败时清空指定项目，避免将旧读数标作实时数据。
    function state:invalidate(ids)
        local changed = false
        for _, id in ipairs(ids) do
            if self.values[id] ~= nil or self.received[id] then
                self.values[id], self.received[id], changed = nil, nil, true
            end
        end
        return changed
    end
    return state
end
return M
