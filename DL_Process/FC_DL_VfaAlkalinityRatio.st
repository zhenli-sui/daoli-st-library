(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_VfaAlkalinityRatio
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: VFA/碱度比计算与酸化风险分级（0=正常 1=关注 2=酸化预警）
*)
FUNCTION FC_DL_VfaAlkalinityRatio : BOOL
VAR_INPUT
    rVfaMgL : REAL; // 挥发性脂肪酸浓度 [mg/L，以乙酸计] / volatile fatty acids as acetic acid
    rAlkMgLcaco3 : REAL; // 碱度 [mg/L，以 CaCO3 计] / alkalinity as CaCO3
END_VAR
VAR_OUTPUT
    rRatio : REAL; // VFA/碱度比 [-] / VFA to alkalinity ratio
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iRisk : INT; // 风险等级 0=正常 1=关注 2=酸化预警 [-] / risk level
    iErrCode : INT; // 事件码 0=正常 1=碱度非法 2=比值超可观测上限 3=结果非有限 / event code
END_VAR
VAR CONSTANT
    rRiskWatch : REAL := 0.25; // 关注门槛 [-] / watch threshold
    rRiskAlarm : REAL := 0.4; // 酸化预警门槛 [-] / acidification alarm threshold
    rRatioCap : REAL := 100.0; // 比值输出饱和上限 [-] / ratio saturation cap
END_VAR
VAR
    rRatioRaw : REAL; // 未限幅比值 [-] / unchecked ratio
END_VAR

    // —— 段 0：全路径预清 —— //
    rRatioRaw := 0.0;
    rRatio := 0.0;
    iRisk := 0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_VfaAlkalinityRatio := FALSE;
    // —— 段 1：分母闸（碱度必须为正） —— //
    IF rAlkMgLcaco3 <= 0.0 THEN
        iErrCode := 1; // 碱度非法，比值无定义 / invalid alkalinity, ratio undefined
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (mg/L)/(mg/L) = 无量纲 —— //
    rRatioRaw := rVfaMgL / rAlkMgLcaco3; // 比值 [-] / ratio
    IF ABS(rRatioRaw) > 1.0E15 THEN
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    // —— 段 3：负值防御与上限饱和 —— //
    IF rRatioRaw < 0.0 THEN
        rRatio := 0.0; // 负浓度防御 / negative concentration guard
    ELSIF rRatioRaw > rRatioCap THEN
        rRatio := rRatioCap; // 超上限饱和 / saturate at cap
        iErrCode := 2; // 信息级：比值超上限 / info level: ratio capped
    ELSE
        rRatio := rRatioRaw;
    END_IF;
    // —— 段 4：风险分级（用原始比值分级，避免饱和影响） —— //
    IF rRatioRaw > rRiskAlarm THEN
        iRisk := 2; // 酸化预警 / acidification alarm
    ELSIF rRatioRaw >= rRiskWatch THEN
        iRisk := 1; // 关注 / watch
    ELSE
        iRisk := 0; // 正常 / normal
    END_IF;
    bValid := TRUE;
    FC_DL_VfaAlkalinityRatio := TRUE;
END_FUNCTION
