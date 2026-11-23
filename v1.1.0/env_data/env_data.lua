-- 环境监测参数字典。default 是 PC 演示值，min/max 是仪表显示量程。
-- 采集模块通过 id 提交数据，单位、精度、校准和报警阈值应按实际设备协议确认。
local M = {}
-- 字段说明
-- `id`参数唯一 ID，采集业务上报数据用这个 id 匹配，字符串标识
-- `name`中文全名，界面显示中文名称
-- `symbol`英文简称符号，界面表头 / 仪表盘简写（CO、O2 等）
-- `unit`物理单位：ppm、%、ug/m3、℃、hPa
-- `default`**PC 仿真演示默认模拟值，硬件上不会使用这个 default**
-- `decimals`显示保留小数位数，格式化函数会读取该值
-- `min`仪表盘 UI 量程最小值（仅界面渲染，不代表传感器硬件报警）
-- `max`仪表盘 UI 量程最大值
-- `color`该参数在仪表盘 / 图表上使用的 RGB 颜色数值（十进制 RGB，等价 0xRRGGBB）
M.metrics = {
    { id = "co", name = "一氧化碳", symbol = "CO", unit = "ppm", default = 0.6, decimals = 2, min = 0, max = 100, color = 3571402 },
    { id = "o2", name = "氧气", symbol = "O2", unit = "%", default = 20.9, decimals = 2, min = 0, max = 30, color = 2530961 },
    { id = "h2s", name = "硫化氢", symbol = "H2S", unit = "ppm", default = 0.12, decimals = 2, min = 0, max = 100, color = 957108 },
    { id = "co2", name = "二氧化碳", symbol = "CO2", unit = "ppm", default = 620, decimals = 0, min = 0, max = 5000, color = 6454980 },
    { id = "ch4", name = "甲烷", symbol = "CH4", unit = "%Vol", default = 0.02, decimals = 2, min = 0, max = 100, color = 2325690 },
    { id = "pm25", name = "PM2.5", symbol = "PM2.5", unit = "ug/m3", default = 18, decimals = 0, min = 0, max = 150, color = 824797 },
    { id = "pm10", name = "PM10", symbol = "PM10", unit = "ug/m3", default = 32, decimals = 0, min = 0, max = 250, color = 1484734 },
    { id = "voc", name = "挥发性有机物", symbol = "VOC", unit = "ppm", default = 0.1, decimals = 3, min = 0, max = 10, color = 6454980 },
    { id = "o3", name = "臭氧", symbol = "O3", unit = "ppm", default = 0.03, decimals = 3, min = 0, max = 1, color = 957108 },
    { id = "so2", name = "二氧化硫", symbol = "SO2", unit = "ppm", default = 0.01, decimals = 3, min = 0, max = 10, color = 6454980 },
    { id = "no2", name = "二氧化氮", symbol = "NO2", unit = "ppm", default = 0.02, decimals = 3, min = 0, max = 10, color = 2325690 },
    { id = "nh3", name = "氨气", symbol = "NH3", unit = "ppm", default = 0.1, decimals = 2, min = 0, max = 100, color = 1484734 },
    { id = "temperature", name = "温度", symbol = "TEMP", unit = "℃", default = 24.6, decimals = 1, min = -20, max = 60, color = 13996840 },
    { id = "humidity", name = "湿度", symbol = "RH", unit = "%RH", default = 56, decimals = 1, min = 0, max = 100, color = 2530961 },
    { id = "pressure", name = "气压", symbol = "P", unit = "hPa", default = 1013.2, decimals = 1, min = 800, max = 1200, color = 3571402 },
}
-- 排序表使用 metrics 的下标。启用状态由采集通道配置提供。
M.gauge_order = { 1, 2, 13, 14, 6, 3, 4, 5, 7, 8, 9, 10, 11, 12, 15 } -- 仪表盘渲染排序表
-- 数据表和仪表共享显示精度，缺少数值时显示占位符。
function M.format(metric, value)
    if type(value) ~= "number" then return "--" end
    return string.format("%." .. metric.decimals .. "f", value)
end
-- 量程文本处理函数
function M.range_text(value)
    if value == math.floor(value) then
        return string.format("%.0f", value)
    end
    return (string.format("%.6f", value):gsub("0+$", ""):gsub("%.$", ""))
end
return M
