(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_OrganicLoadRate
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 厌氧反应器有机负荷率 OLR（kgVS/(m3·d)）与进料 VS 量计算，含过载判定
*)
FUNCTION FC_DL_OrganicLoadRate : BOOL
VAR_INPUT
    rFeedM3Day : REAL; // 进料体积流量 [m3/d] / feed flow per day
    rCodMgL : REAL; // 进料 COD 浓度 [mg/L] / feed COD concentration
    rVsTsRatio : REAL; // VS/TS 比 [-]，典型 0.7 / volatile to total solids ratio
    rTsKgM3 : REAL; // 进料总固体浓度 [kg/m3] / feed total solids concentration
    rReactorM3 : REAL; // 反应器有效容积 [m3] / reactor working volume
END_VAR
VAR_OUTPUT
    rOlrKgVsM3d : REAL; // 有机负荷率 [kgVS/(m3·d)] / organic loading rate
    rVsKgDay : REAL; // 进料挥发性固体量 [kgVS/d] / volatile solids fed per day
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    bOver : BOOL; // 过载标志（>5.0 kgVS/(m3·d)）[-] / overload flag
    iErrCode : INT; // 事件码 0=正常 1=反应器容积非法 2=VS/TS 比超域 3=结果非有限 / event code
END_VAR
VAR CONSTANT
    rMgLToKgM3 : REAL := 0.001; // mg/L(=g/m3)转 kg/m3 系数 [kg/g] / mg per litre to kg per cubic metre
    rOlrHi : REAL := 5.0; // 过载门槛 [kgVS/(m3·d)] / overload threshold
END_VAR
VAR
    rCodKgM3 : REAL; // 进料 COD 浓度 [kg/m3] / COD concentration in kg/m3
    rVsRaw : REAL; // 未校验 VS 量 [kgVS/d] / unchecked volatile solids
    rOlrRaw : REAL; // 未校验负荷率 [kgVS/(m3·d)] / unchecked loading rate
END_VAR

    // —— 段 0：全路径预清 —— //
    rCodKgM3 := 0.0;
    rVsRaw := 0.0;
    rOlrRaw := 0.0;
    rOlrKgVsM3d := 0.0;
    rVsKgDay := 0.0;
    bValid := FALSE;
    bOver := FALSE;
    iErrCode := 0;
    FC_DL_OrganicLoadRate := FALSE;
    // —— 段 1：分母闸（反应器容积）与 VS/TS 比域闸 —— //
    IF rReactorM3 <= 0.0 THEN
        iErrCode := 1; // 反应器容积非法，负荷率无定义 / invalid reactor volume
        RETURN;
    END_IF;
    IF (rVsTsRatio <= 0.0) OR (rVsTsRatio > 1.0) THEN
        iErrCode := 2; // VS/TS 比超域 (0,1] / VS to TS ratio out of domain
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (m3/d)×(kg/m3)×(-) = kg/d —— //
    rCodKgM3 := rCodMgL * rMgLToKgM3; // COD 浓度 [kg/m3]，仅作参考量 / COD reference only
    // 量纲: (m3/d)*(kg/m3)*(-) = kgVS/d；VS 必须由 TS 乘 VS/TS 得，不得用 COD 冒充
    rVsRaw := rFeedM3Day * rTsKgM3 * rVsTsRatio; // VS 量 [kgVS/d] / volatile solids per day
    IF ABS(rVsRaw) > 1.0E15 THEN
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    IF rVsRaw < 0.0 THEN
        rVsKgDay := 0.0; // 负进料防御 / negative feed guard
    ELSE
        rVsKgDay := rVsRaw;
    END_IF;
    // —— 段 3：负荷率（量纲 (kg/d)/(m3) = kg/(m3·d)） —— //
    rOlrRaw := rVsKgDay / rReactorM3; // 负荷率 [kgVS/(m3·d)] / organic loading rate
    IF ABS(rOlrRaw) > 1.0E15 THEN
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    rOlrKgVsM3d := rOlrRaw;
    // —— 段 4：过载判定 —— //
    bOver := rOlrKgVsM3d > rOlrHi; // 过载标志 [-] / overload flag
    bValid := TRUE;
    FC_DL_OrganicLoadRate := TRUE;
END_FUNCTION
