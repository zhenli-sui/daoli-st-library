(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_NtuCoagDoseAdj
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 沉后浊度偏差比例微调混凝投加基准，单次步长与总量双限幅
*)
FUNCTION FC_DL_NtuCoagDoseAdj : BOOL
VAR_INPUT
    rNtuOut : REAL; // 沉后实测浊度 [NTU] / measured settled water turbidity
    rNtuSp : REAL; // 沉后浊度设定值 [NTU] / turbidity setpoint
    rDoseBase : REAL; // 前馈投加基准 [L/h] / feed-forward base dose
    rKp : REAL; // 比例增益 [(L/h)/NTU] / proportional gain
    rStepMax : REAL; // 单次修正步长上限 [L/h] / maximum single-step correction
END_VAR
VAR_OUTPUT
    rDoseOut : REAL; // 修正后投加量 [L/h] / corrected dose
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=步长上限非法 2=基准投加为负 3=结果非有限 / event code
END_VAR
VAR
    rErr : REAL; // 浊度偏差 实测-设定 [NTU] / turbidity error
    rDelta : REAL; // 比例修正量 [L/h] / proportional correction
    rDoseRaw : REAL; // 未限幅投加量 [L/h] / unlimited dose
    rDoseHi : REAL; // 总量上限 = 2×基准 [L/h] / total upper limit, twice the base
END_VAR

    // —— 段 0：全路径预清 —— //
    rErr := 0.0;
    rDelta := 0.0;
    rDoseRaw := 0.0;
    rDoseHi := 0.0;
    rDoseOut := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_NtuCoagDoseAdj := FALSE;
    // —— 段 1：步长上限闸（限幅基准不可为零） —— //
    IF rStepMax <= 0.0 THEN
        iErrCode := 1; // 步长上限非法，无法限幅 / invalid step limit, clamping impossible
        RETURN;
    END_IF;
    // —— 段 2：基准投加合法性（负基准无物理意义） —— //
    IF rDoseBase < 0.0 THEN
        iErrCode := 2; // 基准投加为负，拒绝修正 / negative base dose rejected
        RETURN;
    END_IF;
    // —— 段 3：比例修正与步长限幅（量纲 (L/h)/NTU × NTU = L/h） —— //
    rErr := rNtuOut - rNtuSp; // 偏差 [NTU] / error
    rDelta := rKp * rErr; // 比例修正 [L/h] / proportional term
    IF rDelta > rStepMax THEN
        rDelta := rStepMax; // 正向步长饱和 / saturate positive step
    ELSIF rDelta < -rStepMax THEN
        rDelta := -rStepMax; // 负向步长饱和 / saturate negative step
    END_IF;
    rDoseRaw := rDoseBase + rDelta; // 修正后投加 [L/h] / corrected dose
    // —— 段 4：总量双限幅 [0, 2×基准] 与结果域闸 —— //
    rDoseHi := rDoseBase + rDoseBase; // 总量上限 [L/h] / total upper limit
    IF ABS(rDoseRaw) > 1.0E15 THEN
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    IF rDoseRaw < 0.0 THEN
        rDoseOut := 0.0; // 下限零 / floor at zero
    ELSIF rDoseRaw > rDoseHi THEN
        rDoseOut := rDoseHi; // 上限 2×基准 / ceiling at twice the base
    ELSE
        rDoseOut := rDoseRaw;
    END_IF;
    bValid := TRUE;
    FC_DL_NtuCoagDoseAdj := TRUE;
END_FUNCTION
