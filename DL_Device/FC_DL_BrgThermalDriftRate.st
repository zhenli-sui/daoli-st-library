(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_BrgThermalDriftRate
  分类: DL_Device
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 轴承温升速率计算、相对环境温升与温升过快判定
*)
FUNCTION FC_DL_BrgThermalDriftRate : BOOL
VAR_INPUT
    rTempNow : REAL; // 本次轴承温度 [°C] / current bearing temperature
    rTempPrev : REAL; // 上次轴承温度 [°C] / previous bearing temperature
    rDtMin : REAL; // 采样间隔 [min] / sampling interval in minutes
    rAmbC : REAL; // 环境温度 [°C] / ambient temperature
    rAlarmRisePerMin : REAL; // 温升速率报警门槛 [°C/min] / rise rate alarm threshold
END_VAR
VAR_OUTPUT
    rRisePerMin : REAL; // 温升速率 [°C/min] / temperature rise rate
    rOverAmbC : REAL; // 相对环境温升 [°C] / temperature rise above ambient
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    bFastRise : BOOL; // 温升过快标志 [-] / fast rise flag
    iErrCode : INT; // 事件码 0=正常 1=采样间隔非法 2=结果非有限 / event code
END_VAR
VAR CONSTANT
    rAbsZero : REAL := -273.15; // 绝对零度 [°C] / absolute zero in Celsius
END_VAR
VAR
    rRiseRaw : REAL; // 未校验温升速率 [°C/min] / unchecked rise rate
END_VAR

    // —— 段 0：全路径预清 —— //
    rRiseRaw := 0.0;
    rRisePerMin := 0.0;
    rOverAmbC := 0.0;
    bValid := FALSE;
    bFastRise := FALSE;
    iErrCode := 0;
    FC_DL_BrgThermalDriftRate := FALSE;
    // —— 段 1：分母闸（采样间隔必须为正） —— //
    IF rDtMin <= 0.0 THEN
        iErrCode := 1; // 采样间隔非法，速率无定义 / invalid interval, rate undefined
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (°C - °C)/(min) = °C/min —— //
    rRiseRaw := (rTempNow - rTempPrev) / rDtMin; // 温升速率 [°C/min] / rise rate
    IF ABS(rRiseRaw) > 1.0E15 THEN
        iErrCode := 2; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    rRisePerMin := rRiseRaw;
    // —— 段 3：相对环境温升（量纲 °C - °C = °C） —— //
    IF rTempNow <= rAbsZero THEN
        iErrCode := 2; // 温度低于绝对零度，物理不可能 / temperature below absolute zero
        RETURN;
    END_IF;
    rOverAmbC := rTempNow - rAmbC; // 相对环境温升 [°C] / rise above ambient
    // —— 段 4：温升过快判定（门槛为负时按绝对值口径比对） —— //
    IF rAlarmRisePerMin > 0.0 THEN
        bFastRise := rRisePerMin > rAlarmRisePerMin; // 常规比对 / normal comparison
    ELSE
        bFastRise := rRisePerMin > ABS(rAlarmRisePerMin); // 门槛配置异常时退化为绝对值口径 / fallback on bad threshold
    END_IF;
    bValid := TRUE;
    FC_DL_BrgThermalDriftRate := TRUE;
END_FUNCTION
