(*
  Name: FB_DL_ThickenerFlocDoseCtrl
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 矿山破碎筛分，ST 开源生态实测 0 命中，无外部代码引入）
  功能：浓密机絮凝剂投加控制：给矿量前馈（g/t 基准投加）乘底流浓度反馈修正因子，输出溶液投加流量。
  边界条件：① 六入参全部过非有限闸；配置越域进冻结分支：输出保持上一有效值 + xValid = FALSE（R191 已声明）；
            ② xEnable = FALSE 语义：冻结保持末值（不降级为 0，避免投加泵被清零误动作），xValid 同拍置 FALSE；
            ③ 抗积分饱和：本件为乘性修正（无积分器，故无 windup 通路），修正因子钳位 0.7~1.4；
               输出达上限时冻结因子更新（保持末值），防止饱和期内因子持续堆高；
            ④ 固体吨位为代理量：以底流浓度近似给矿固体含量（保守偏小），代理假设见功能段。
  量纲自证：Q[m3/h] × ρ[t/m3] × C[−] = t/h；t/h × g/t = g/h；g/h ÷ g/L = L/h。
*)
FUNCTION_BLOCK FB_DL_ThickenerFlocDoseCtrl
VAR_INPUT
    xEnable : BOOL;             (* 投加使能 [-] Dosing enable *)
    fFeedM3h : REAL;            (* 给矿浆体流量 [m3/h] Feed slurry flow [m3/h] *)
    fDoseGpt : REAL;            (* 基准投加量（每吨固体） [g/t] Base dosage per tonne solids [g/t] *)
    fUnderDensityPct : REAL;    (* 底流浓度实测 [%] Underflow density actual [%] *)
    fUnderDensitySpPct : REAL;  (* 底流浓度设定 [%] Underflow density setpoint [%] *)
    fDoseMaxLph : REAL;         (* 投加泵流量上限 [L/h] Dosage pump ceiling [L/h] *)
END_VAR
VAR_OUTPUT
    fDoseLph : REAL;            (* 投加溶液流量 [L/h] Dosing solution flow [L/h] *)
    xSaturated : BOOL;          (* 输出已达上限 [-] Output saturated *)
    xValid : BOOL;              (* 配置与链路有效 [-] Configuration and chain valid *)
END_VAR
VAR
    _bInit : BOOL := FALSE;     (* 首扫初始化标志 [-] First-scan init flag *)
    _bCfgBad : BOOL := FALSE;   (* 配置非法当拍量 [-] Configuration bad *)
    _bCalcOk : BOOL := FALSE;   (* 本拍计算有效 [-] Calculation valid this scan *)
    _fTrim : REAL := 1.0;       (* 反馈修正因子（钳 0.7~1.4） [-] Feedback trim factor *)
    _fTrimNew : REAL := 1.0;    (* 本拍候选修正因子 [-] Candidate trim factor *)
    _fErrPct : REAL := 0.0;     (* 浓度偏差（设定 − 实测） [%] Density deviation [%] *)
    _fSolidsTph : REAL := 0.0;  (* 固体吨位代理量 [t/h] Solids tonnage proxy [t/h] *)
    _fDose : REAL := 0.0;       (* 投加流量保持量 [L/h] Dosing flow hold [L/h] *)
    _bSat : BOOL := FALSE;      (* 饱和锁存 [-] Saturation latch *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;        (* 除零判定容差 [-] Divide-by-zero tolerance *)
    DL_RHO_SL : REAL := 1.05;       (* 浆体密度代理值 [t/m3] Slurry density proxy [t/m3] *)
    DL_GPL : REAL := 0.5;           (* 絮凝剂溶液浓度 [g/L] Flocculant solution strength [g/L] *)
    DL_KFB : REAL := 0.5;           (* 反馈修正增益 [-] Feedback trim gain *)
    DL_TRIM_LO : REAL := 0.7;       (* 修正因子下限 [-] Trim floor *)
    DL_TRIM_HI : REAL := 1.4;       (* 修正因子上限 [-] Trim ceiling *)
    DL_PCT : REAL := 100.0;         (* 百分数基准 [%] Percent base *)
END_VAR
(* 首扫初始化：修正因子起点 1.0（纯前馈） *)
IF NOT _bInit THEN
    _fTrim := 1.0;
    _fDose := 0.0;
    _bSat := FALSE;
    _bInit := TRUE;
END_IF
(* 非有限闸（NaN 自反 + Inf 差值自减）+ 静态组态域闸：五浮点入参全枚举（R272） *)
_bCfgBad := (fFeedM3h <> fFeedM3h) OR ((fFeedM3h - fFeedM3h) <> 0.0)
         OR (fDoseGpt <> fDoseGpt) OR ((fDoseGpt - fDoseGpt) <> 0.0)
         OR (fUnderDensityPct <> fUnderDensityPct) OR ((fUnderDensityPct - fUnderDensityPct) <> 0.0)
         OR (fUnderDensitySpPct <> fUnderDensitySpPct) OR ((fUnderDensitySpPct - fUnderDensitySpPct) <> 0.0)
         OR (fDoseMaxLph <> fDoseMaxLph) OR ((fDoseMaxLph - fDoseMaxLph) <> 0.0)
         OR (fFeedM3h < 0.0) OR (fFeedM3h > 5000.0)
         OR (fDoseGpt < 1.0) OR (fDoseGpt > 500.0)
         OR (fUnderDensityPct < 0.0) OR (fUnderDensityPct > 60.0)
         OR (fUnderDensitySpPct < 5.0) OR (fUnderDensitySpPct > 60.0)
         OR (fDoseMaxLph < 0.1) OR (fDoseMaxLph > 5000.0);
_bCalcOk := xEnable AND (NOT _bCfgBad);
IF _bCalcOk THEN
    (* 固体吨位代理：Q[m3/h] × ρ[t/m3] × C[−] = t/h *)
    _fSolidsTph := fFeedM3h * DL_RHO_SL * (fUnderDensityPct / DL_PCT);
    (* 偏差：设定 − 实测，正值表示底流偏稀需加大投加 *)
    _fErrPct := fUnderDensitySpPct - fUnderDensityPct;
    (* 候选修正因子 + 钳位（量值饱和；饱和期间冻结更新以抗饱和） *)
    IF NOT _bSat THEN
        _fTrimNew := 1.0 + DL_KFB * (_fErrPct / DL_PCT);
        IF _fTrimNew < DL_TRIM_LO THEN
            _fTrimNew := DL_TRIM_LO;
        ELSIF _fTrimNew > DL_TRIM_HI THEN
            _fTrimNew := DL_TRIM_HI;
        END_IF
        _fTrim := _fTrimNew;
    END_IF
    (* 前馈 × 反馈：t/h × g/t = g/h；÷ g/L = L/h *)
    _fDose := ((_fSolidsTph * fDoseGpt) * _fTrim) / DL_GPL;
    (* 上限钳位：达上限即置饱和并冻结因子，防饱和期堆高 *)
    IF _fDose >= fDoseMaxLph THEN
        _fDose := fDoseMaxLph;
        _bSat := TRUE;
    ELSE
        _bSat := FALSE;
    END_IF
END_IF
(* 统一出口（单点赋值）：冻结分支保持上一有效值，保持量来源均为已过闸的有限值（R273） *)
fDoseLph := _fDose;
xSaturated := _bSat AND _bCalcOk;
xValid := _bCalcOk;
END_FUNCTION_BLOCK
