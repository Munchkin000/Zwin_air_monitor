-- 字段顺序决定设备信息页的显示顺序。新增项需指定唯一 id 和中文标签。
-- id 同时用于 DEVICE_INFO_DATA 更新事件，事件值为已格式化的显示字符串。
return {
    { id = "name", label = "设备名称" }, { id = "device_id", label = "设备编号" },
    { id = "board", label = "开发板型号" }, { id = "chip", label = "主控模组" },
    { id = "version", label = "程序版本" }, { id = "runtime", label = "运行平台" },
    { id = "sim", label = "SIM 卡状态" }, { id = "iccid", label = "SIM 卡 ICCID" },
    { id = "operator", label = "运营商" }, { id = "signal", label = "信号强度" },
    { id = "location", label = "定位状态" }, { id = "longitude", label = "经度" },
    { id = "latitude", label = "纬度" },
    { id = "flash_total", label = "Flash 总容量" }, { id = "flash_free", label = "Flash 剩余容量" },
    { id = "sd_total", label = "SD 卡总容量" }, { id = "sd_free", label = "SD 卡剩余容量" },
}
