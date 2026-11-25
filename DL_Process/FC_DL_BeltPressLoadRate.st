(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_BeltPressLoadRate
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 带式压滤机单位滤带面积固体比负荷计算与过载判定
*)
FUNCTION FC_DL_BeltPressLoadRate : BOOL
VAR_INPUT
    rDsKgH : REAL; // 干固体处理量 [kg/h] / dry solids throughput
    rBeltWidthM : REAL; // 滤带有效宽度 [m] / effective belt width
    rBeltSpeedMmin : REAL; // 滤带线速度 [m/min] / belt linear speed
END_VAR
VAR_OUTPUT
    rLoadKgM2h : REAL; // 比负荷 [kg/(m2·h)] / specific solids loading
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    bOver : BOOL; // 过载标志（>500 kg/(m2·h)）[-] / overload flag
    iErrCode : INT; // 事件码 0=正常 1=滤带面积非法 2=结果非有限 / event code
END_VAR
VAR CONSTANT
    rMinPerHour : REAL := 60.0; // 每小时分钟数 [min/h] / minutes per hour
    rLoadHi : REAL := 500.0; // 比负荷过载门槛 [kg/(m2·h)] / overload threshold
END_VAR
VAR
    rAreaM2h : REAL; // 滤带处理面积速率 [m2/h] / belt area rate
    rLoadRaw : REAL; // 未限幅比负荷 [kg/(m2·h)] / unlimited specific loading
END_VAR

    // —— 段 0：全路径预清 —— //
    rAreaM2h := 0.0;
    rLoadRaw := 0.0;
    rLoadKgM2h := 0.0;
    bValid := FALSE;
    bOver := FALSE;
    iErrCode := 0;
    FC_DL_BeltPressLoadRate := FALSE;
    // —— 段 1：分母闸（滤带面积速率 = 宽 × 速 × 60） —— //
    rAreaM2h := rBeltWidthM * rBeltSpeedMmin * rMinPerHour; // 面积速率 [m2/h] / belt area rate
    IF (rBeltWidthM <= 0.0) OR (rAreaM2h <= 0.0) THEN
        iErrCode := 1; // 滤带面积速率非法，比负荷无定义 / invalid belt area rate
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (kg/h)/(m2/h) = kg/(m2·h) —— //
    rLoadRaw := rDsKgH / rAreaM2h; // 比负荷 [kg/(m2·h)] / specific loading
    IF ABS(rLoadRaw) > 1.0E15 THEN
        iErrCode := 2; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    // —— 段 3：负值防御与过载判定 —— //
    IF rLoadRaw < 0.0 THEN
        rLoadKgM2h := 0.0; // 负干固体防御 / negative dry solids guard
    ELSE
        rLoadKgM2h := rLoadRaw;
    END_IF;
    bOver := rLoadKgM2h > rLoadHi; // 过载判定 [-] / overload test
    bValid := TRUE;
    FC_DL_BeltPressLoadRate := TRUE;
END_FUNCTION
