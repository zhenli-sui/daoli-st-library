(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_ScrubberLiquidGasRatio
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 湿式洗涤塔液气比（L/m3）计算、最低液量需求与低液气比告警
*)
FUNCTION FC_DL_ScrubberLiquidGasRatio : BOOL
VAR_INPUT
    rLiquidM3h : REAL; // 循环液流量 [m3/h] / scrubbing liquid flow
    rGasNm3h : REAL; // 标态烟气量 [Nm3/h] / flue gas flow at normal conditions
END_VAR
VAR_OUTPUT
    rLG : REAL; // 液气比 [L/m3] / liquid to gas ratio
    rLiquidNeedM3h : REAL; // 满足最低液气比所需液量 [m3/h] / liquid demand at the minimum ratio
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    bLow : BOOL; // 低液气比告警（<2.0 L/m3）[-] / low ratio alarm
    iErrCode : INT; // 事件码 0=正常 1=烟气量非法 2=结果非有限 / event code
END_VAR
VAR CONSTANT
    rM3ToL : REAL := 1000.0; // 立方米转升系数 [L/m3] / cubic metre to litre factor
    rLgMin : REAL := 2.0; // 最低液气比 [L/m3] / minimum liquid to gas ratio
END_VAR
VAR
    rLgRaw : REAL; // 未限幅液气比 [L/m3] / unlimited ratio
    rNeedLh : REAL; // 最低液量需求 [L/h] / liquid demand in L/h
END_VAR

    // —— 段 0：全路径预清 —— //
    rLgRaw := 0.0;
    rNeedLh := 0.0;
    rLG := 0.0;
    rLiquidNeedM3h := 0.0;
    bValid := FALSE;
    bLow := FALSE;
    iErrCode := 0;
    FC_DL_ScrubberLiquidGasRatio := FALSE;
    // —— 段 1：分母闸（烟气量必须为正） —— //
    IF rGasNm3h <= 0.0 THEN
        iErrCode := 1; // 烟气量非法，液气比无定义 / invalid gas flow, ratio undefined
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (m3/h)/(Nm3/h) = 无量纲，×(L/m3) 得 L/m3 —— //
    rLgRaw := rLiquidM3h / rGasNm3h * rM3ToL; // 液气比 [L/m3] / liquid to gas ratio
    IF ABS(rLgRaw) > 1.0E15 THEN
        iErrCode := 2; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    IF rLgRaw < 0.0 THEN
        rLG := 0.0; // 负液量防御 / negative liquid guard
    ELSE
        rLG := rLgRaw;
    END_IF;
    // —— 段 3：最低液量反算（量纲 (L/m3)×(Nm3/h)/(L/m3) = m3/h） —— //
    rNeedLh := rLgMin * rGasNm3h; // 最低液量 [L/h] / minimum liquid in L/h
    rLiquidNeedM3h := rNeedLh / rM3ToL; // 折算 m3/h / back to m3/h
    // —— 段 4：低液气比告警（信息级，数值照给） —— //
    bLow := rLG < rLgMin; // 低液气比标志 [-] / low ratio flag
    bValid := TRUE;
    FC_DL_ScrubberLiquidGasRatio := TRUE;
END_FUNCTION
