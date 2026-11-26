-- 运行目标切换。直接用 LuaTools 添加源码时，在这里选择目标平台。
-- stage_project.ps1 根据 -Mode 修改打包副本中的开关。
return {
    USE_HARDWARE = true, -- false 用于 PC 仿真，true 用于 Air8603M1 真机
}
