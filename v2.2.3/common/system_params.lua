-- 系统周期统一保存在 FSKV。界面草稿保存成功后才通知后台任务。
local M = {}
local key = "air_system_params"
local current = {sample_ms = 1000, store_ms = 60000, upload_ms = 5000}
M.storage = {labels = {"1 分钟", "5 分钟", "10 分钟", "20 分钟", "30 分钟", "1 小时"},
    values = {60000, 300000, 600000, 1200000, 1800000, 3600000}}
M.upload = {labels = {"1 秒", "5 秒", "10 秒", "30 秒", "1 分钟", "5 分钟", "10 分钟", "30 分钟", "1 小时"},
    values = {1000, 5000, 10000, 30000, 60000, 300000, 600000, 1800000, 3600000}}

function M.index(options, value)
    for index, option in ipairs(options.values) do
        if option == value then return index end
    end
end

local function sample_valid(value)
    return type(value) == "number" and value % 1 == 0 and value >= 10 and value <= 0x7FFFFFFF
end

function M.start(legacy_sample)
    -- 首次升级沿用已保存的温度采样周期。已有新配置则以新配置为准。
    if sample_valid(legacy_sample) then current.sample_ms = legacy_sample end
    local saved = fskv and fskv.get(key)
    if type(saved) ~= "table" then return end
    if sample_valid(saved.sample_ms) then current.sample_ms = saved.sample_ms end
    if M.index(M.storage, saved.store_ms) then current.store_ms = saved.store_ms end
    if M.index(M.upload, saved.upload_ms) then current.upload_ms = saved.upload_ms end
end

function M.snapshot()
    return {sample_ms = current.sample_ms, store_ms = current.store_ms, upload_ms = current.upload_ms}
end

function M.sample_ms() return current.sample_ms end
function M.store_ms() return current.store_ms end
function M.upload_ms() return current.upload_ms end

function M.save(draft)
    if not sample_valid(draft.sample_ms) then return false, "采样周期请输入 10 至 2147483647 ms" end
    if not M.index(M.storage, draft.store_ms) or not M.index(M.upload, draft.upload_ms) then
        return false, "请选择预设周期"
    end
    local next_values = {sample_ms = draft.sample_ms, store_ms = draft.store_ms, upload_ms = draft.upload_ms}
    local sample_changed = next_values.sample_ms ~= current.sample_ms
    local store_changed = next_values.store_ms ~= current.store_ms
    local upload_changed = next_values.upload_ms ~= current.upload_ms
    if not (sample_changed or store_changed or upload_changed) then return true end
    if not (fskv and fskv.set(key, next_values)) then return false, "保存失败，请检查配置存储" end
    current = next_values
    if sample_changed then sys.publish("CHANNEL_CONFIG_CHANGED") end
    if store_changed then sys.publish("APP_STORAGE_PERIOD_CHANGED") end
    if upload_changed then sys.publish("APP_UPLOAD_PERIOD_CHANGED") end
    log.info("system_params", "SYSTEM_PARAMS_SAVED", current.sample_ms, current.store_ms, current.upload_ms)
    return true
end

return M
