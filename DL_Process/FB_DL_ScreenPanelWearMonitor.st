(*
  Name: FB_DL_ScreenPanelWearMonitor
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 矿山破碎筛分，ST 开源生态实测 0 命中，无外部代码引入）
  功能：筛板磨损监测（累计过料量法）：按运行时间积分过料吨位，乘磨损系数得累计磨损厚度与剩余寿命。
  边界条件：① 五浮点入参全部过非有限闸，任一非有限进冻结分支：输出保持上一有效值 + xValid = FALSE；
            ② 累计量为跨拍保持量，首扫以 _bInit 初始化，xReset 只清累计吨位（作用域：清累计，不清配置）；
            ③ 周期换算口径：TIME_TO_REAL 取毫秒（库内统一口径），tCycleS ≤ 0 时以 10 ms 缺省兜底；
            ④ 磨损厚度饱和于有效厚度差（钳的是剩余寿命量值，xValid 不受影响）。
  量纲自证：fFeedTph[t/h] × dt[h] = t；t/1000 = kt；kt × fWearCoef[mm/kt] = mm。
*)
FUNCTION_BLOCK FB_DL_ScreenPanelWearMonitor
VAR_INPUT
    xRun : BOOL;                (* 筛机运行反馈 [-] Screen running *)
    fFeedTph : REAL;            (* 瞬时给料量 [t/h] Instantaneous feed rate [t/h] *)
    fWearCoef : REAL;           (* 磨损系数 [mm/kt] Wear coefficient [mm per kilotonne] *)
    fPanelThkInitMm : REAL;     (* 筛板初始厚度 [mm] Initial panel thickness [mm] *)
    fPanelThkMinMm : REAL;      (* 筛板报废厚度 [mm] Scrap thickness [mm] *)
    xReset : BOOL;              (* 累计清零（换板后置位一拍） [-] Reset accumulation *)
    tCycleS : TIME;             (* 扫描周期 [ms] Scan cycle [ms] *)
END_VAR
VAR_OUTPUT
    fWornMm : REAL;             (* 累计磨损厚度 [mm] Accumulated wear [mm] *)
    fRemainLifePct : REAL;      (* 剩余寿命百分比 [%] Remaining life [%] *)
    xReplaceAlarm : BOOL;       (* 换板报警（剩余 ≤ 10 %） [-] Replace alarm *)
    xValid : BOOL;              (* 配置与链路有效 [-] Configuration and chain valid *)
END_VAR
VAR
    _bInit : BOOL := FALSE;     (* 首扫初始化标志 [-] First-scan init flag *)
    _bCfgBad : BOOL := FALSE;   (* 配置非法当拍量 [-] Configuration bad *)
    _bCalcOk : BOOL := FALSE;   (* 本拍计算有效 [-] Calculation valid this scan *)
    _fTonsAcc : REAL := 0.0;    (* 累计过料量 [t] Accumulated tonnage [t] *)
    _fWorn : REAL := 0.0;       (* 累计磨损厚度保持量 [mm] Wear thickness hold [mm] *)
    _fRemain : REAL := 0.0;     (* 剩余寿命保持量 [%] Remaining life hold [%] *)
    _fSpanMm : REAL := 0.0;     (* 有效可磨损厚度差 [mm] Usable thickness span [mm] *)
    _fDtH : REAL := 0.0;        (* 本拍时间步长 [h] Time step [h] *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;        (* 除零判定容差 [-] Divide-by-zero tolerance *)
    DL_KT : REAL := 1000.0;         (* 吨 → 千吨换算 [t/kt] Tonne to kilotonne *)
    DL_SECH : REAL := 3600.0;       (* 秒 → 小时换算 [s/h] Second to hour *)
    DL_CYCDEF : REAL := 0.01;       (* 缺省扫描周期 [s] Default scan cycle [s] *)
    DL_ALARM_PCT : REAL := 10.0;    (* 换板报警门限（剩余寿命） [%] Replace alarm threshold [%] *)
    DL_PCT : REAL := 100.0;         (* 百分数基准 [%] Percent base *)
END_VAR
(* 首扫初始化：累计量与保持量一次性归零（R310） *)
IF NOT _bInit THEN
    _fTonsAcc := 0.0;
    _fWorn := 0.0;
    _fRemain := DL_PCT;
    _bInit := TRUE;
END_IF
(* 周期换算：毫秒 → 秒 → 小时；非正周期以缺省 10 ms 兜底 *)
IF tCycleS <= T#0S THEN
    _fDtH := DL_CYCDEF / DL_SECH;
ELSE
    _fDtH := (TIME_TO_REAL(tCycleS) / 1000.0) / DL_SECH;
END_IF
(* 复位作用域：只清累计吨位与磨损量，不动配置与报警门限 *)
IF xReset THEN
    _fTonsAcc := 0.0;
    _fWorn := 0.0;
    _fRemain := DL_PCT;
END_IF
(* 非有限闸（NaN 自反 + Inf 差值自减）+ 组态域闸：五浮点入参全枚举（R272） *)
_bCfgBad := (fFeedTph <> fFeedTph) OR ((fFeedTph - fFeedTph) <> 0.0)
         OR (fWearCoef <> fWearCoef) OR ((fWearCoef - fWearCoef) <> 0.0)
         OR (fPanelThkInitMm <> fPanelThkInitMm) OR ((fPanelThkInitMm - fPanelThkInitMm) <> 0.0)
         OR (fPanelThkMinMm <> fPanelThkMinMm) OR ((fPanelThkMinMm - fPanelThkMinMm) <> 0.0)
         OR (fFeedTph < 0.0) OR (fFeedTph > 5000.0)
         OR (fWearCoef < 0.0) OR (fWearCoef > 20.0)
         OR (fPanelThkMinMm <= 0.0) OR (fPanelThkInitMm <= (fPanelThkMinMm + DL_EPS))
         OR (fPanelThkInitMm > 200.0);
_bCalcOk := NOT _bCfgBad;
IF _bCalcOk THEN
    (* 运行中按周期积分过料吨位：t/h × h = t *)
    IF xRun THEN
        _fTonsAcc := _fTonsAcc + fFeedTph * _fDtH;
    END_IF
    (* 累计磨损厚度：t → kt，kt × [mm/kt] = mm *)
    _fWorn := (_fTonsAcc / DL_KT) * fWearCoef;
    (* 剩余寿命：有效厚度差已过正性闸，绝无零除 *)
    _fSpanMm := fPanelThkInitMm - fPanelThkMinMm;
    _fRemain := (1.0 - _fWorn / _fSpanMm) * DL_PCT;
    (* 极限钳位：磨穿即 0 %，新板不超 100 % *)
    IF _fWorn >= _fSpanMm THEN
        _fRemain := 0.0;
    END_IF
    IF _fRemain < 0.0 THEN
        _fRemain := 0.0;
    ELSIF _fRemain > DL_PCT THEN
        _fRemain := DL_PCT;
    END_IF
END_IF
(* 统一出口（单点赋值）：冻结分支保持上一有效值，保持量来源均为已过闸的有限值（R273） *)
fWornMm := _fWorn;
fRemainLifePct := _fRemain;
xReplaceAlarm := _bCalcOk AND (_fRemain <= DL_ALARM_PCT);
xValid := _bCalcOk;
END_FUNCTION_BLOCK
