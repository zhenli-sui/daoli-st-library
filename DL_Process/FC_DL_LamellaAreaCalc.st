(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_LamellaAreaCalc
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 斜板（斜管）沉淀区投影面积计算，按颗粒沉降速度与板倾角余弦折算并加余量系数
*)
FUNCTION FC_DL_LamellaAreaCalc : BOOL
VAR_INPUT
    rFlowM3h : REAL; // 处理水量 [m3/h] / treated water flow
    rVsMmS : REAL; // 设计颗粒沉降速度 [mm/s] / design particle settling velocity
    rCosTheta : REAL; // 板面与水平面夹角的余弦 [-]，如 60° ≈ 0.5 / cosine of plate inclination
    rAreaSafety : REAL; // 面积余量系数 [-]，典型 1.2~1.5 / area safety factor, typically 1.2~1.5
END_VAR
VAR_OUTPUT
    rAreaM2 : REAL; // 所需斜板投影面积 [m2] / required projected plate area
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=沉降速度非法 2=倾角过大 3=余量系数非法 4=结果非有限 / event code
END_VAR
VAR CONSTANT
    rSecPerHour : REAL := 3600.0; // 每小时秒数 [s/h] / seconds per hour
    rMmToM : REAL := 0.001; // 毫米转米系数 [m/mm] / millimetre to metre factor
    rCosMin : REAL := 0.1; // 可用余弦下限（倾角过大判据）[-] / minimum usable cosine
    rCosMax : REAL := 1.0; // 余弦物理上限（水平板）[-] / physical ceiling of cosine
END_VAR
VAR
    rFlowM3s : REAL; // 处理水量 [m3/s] / flow in cubic metres per second
    rVsMs : REAL; // 沉降速度 [m/s] / settling velocity in m/s
    rCosUse : REAL; // 生效余弦（上限已钳）[-] / effective cosine, capped at one
    rAreaRaw : REAL; // 未限幅面积 [m2] / unlimited area
END_VAR

    // —— 段 0：全路径预清 —— //
    rFlowM3s := 0.0;
    rVsMs := 0.0;
    rCosUse := 0.0;
    rAreaRaw := 0.0;
    rAreaM2 := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_LamellaAreaCalc := FALSE;
    // —— 段 1：分母闸（沉降速度必须为正） —— //
    IF rVsMmS <= 0.0 THEN
        iErrCode := 1; // 沉降速度非正，面积无定义 / non-positive settling velocity, area undefined
        RETURN;
    END_IF;
    IF rCosTheta <= rCosMin THEN
        iErrCode := 2; // 倾角过大（余弦过小），斜板失效 / inclination too steep, plates ineffective
        RETURN;
    END_IF;
    IF rAreaSafety <= 0.0 THEN
        iErrCode := 3; // 余量系数非法 / invalid safety factor
        RETURN;
    END_IF;
    // —— 段 2：单位归一 [m3/h]->[m3/s]、[mm/s]->[m/s] —— //
    rFlowM3s := rFlowM3h / rSecPerHour; // 水量 [m3/s] / flow in m3/s
    rVsMs := rVsMmS * rMmToM; // 沉速 [m/s] / velocity in m/s
    // —— 段 3：余弦物理上限钳位（cos 不得大于 1） —— //
    IF rCosTheta > rCosMax THEN
        rCosUse := rCosMax; // 超 1 视为水平板 / clamp to horizontal plate
    ELSE
        rCosUse := rCosTheta;
    END_IF;
    // —— 段 4：量纲链 (m3/s)/((m/s)*(-)) = m2 —— //
    rAreaRaw := rFlowM3s / (rVsMs * rCosUse) * rAreaSafety; // 斜板面积 [m2] / lamella area
    IF ABS(rAreaRaw) > 1.0E15 THEN
        iErrCode := 4; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    IF rAreaRaw < 0.0 THEN
        rAreaM2 := 0.0; // 负流量防御 / negative flow guard
    ELSE
        rAreaM2 := rAreaRaw;
    END_IF;
    bValid := TRUE;
    FC_DL_LamellaAreaCalc := TRUE;
END_FUNCTION
