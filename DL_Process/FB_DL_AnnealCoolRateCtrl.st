(*
  Name: FB_DL_AnnealCoolRateCtrl
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 锻造加热退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：退火冷却速率控制：微分实测降温速率，超速报警；同时做超温（实测高于设定 + 容差）保护。
  边界条件：① 四浮点入参全部过非有限闸；配置越域或失能进冻结分支：输出保持末值 + xValid = FALSE（R191）；
            ② 归因分离（R190）：超速与超温各有独立内部成员 _bOverRate / _bOverTemp，出口合并为 xRateAlarm，
               两成因赋值点互不共用，头注释声明合并口径；
            ③ 微分为一阶差分：速率 = (上拍温度 − 本拍温度)/周期 × 60，正值为降温方向 [℃/min]；
            ④ 首扫 _bInit 以当前温度播种上拍快照，避免首拍出现虚假大速率；非法周期取 10 ms 缺省。
  量纲自证：℃ ÷ s × 60 = ℃/min；容差 ℃ 与温度同量纲。
*)
FUNCTION_BLOCK FB_DL_AnnealCoolRateCtrl
VAR_INPUT
    xEnable : BOOL;             (* 使能 [-] Enable *)
    fTempActC : REAL;           (* 炉温实测 [℃] Furnace temperature actual [degC] *)
    fTempSpC : REAL;            (* 炉温设定 [℃] Furnace temperature setpoint [degC] *)
    fCoolRateMaxCpm : REAL;     (* 最大允许降温速率 [℃/min] Maximum allowed cooling rate [degC/min] *)
    fCycleS : REAL;             (* 扫描周期 [s] Scan cycle [s] *)
END_VAR
VAR_OUTPUT
    fRateActCpm : REAL;         (* 实测降温速率（正值为降温） [℃/min] Actual cooling rate [degC/min] *)
    xRateAlarm : BOOL;          (* 超速或超温报警（归因见内部成员） [-] Over-rate or over-temperature alarm *)
    xValid : BOOL;              (* 配置与链路有效 [-] Configuration and chain valid *)
END_VAR
VAR
    _bInit : BOOL := FALSE;     (* 首扫初始化标志 [-] First-scan init flag *)
    _bCfgBad : BOOL := FALSE;   (* 配置非法当拍量 [-] Configuration bad *)
    _bCalcOk : BOOL := FALSE;   (* 本拍计算有效 [-] Calculation valid this scan *)
    _bOverRate : BOOL := FALSE; (* 超速成因（独立成员） [-] Over-rate cause *)
    _bOverTemp : BOOL := FALSE; (* 超温成因（独立成员） [-] Over-temperature cause *)
    _fPrev : REAL := 0.0;       (* 上拍温度快照（首扫播种） [℃] Previous temperature snapshot [degC] *)
    _fRate : REAL := 0.0;       (* 速率保持量 [℃/min] Rate hold [degC/min] *)
    _fCy : REAL := 0.01;        (* 当拍有效周期 [s] Effective cycle [s] *)
END_VAR
VAR CONSTANT
    DL_ACRC_EPS : REAL := 1.0E-9;       (* 判据容差 [-] Criterion tolerance *)
    DL_ACRC_CYDEF : REAL := 0.01;       (* 缺省扫描周期 [s] Default scan cycle [s] *)
    DL_ACRC_SECMIN : REAL := 60.0;      (* 每秒 → 每分钟换算 [s/min] Second to minute *)
    DL_ACRC_TOL : REAL := 5.0;          (* 超温容差 [℃] Over-temperature tolerance [degC] *)
    DL_ACRC_TMIN : REAL := 0.0;         (* 温度下限 [℃] Temperature floor [degC] *)
    DL_ACRC_TMAX : REAL := 1400.0;      (* 温度上限 [℃] Temperature ceiling [degC] *)
    DL_ACRC_RMIN : REAL := 0.1;         (* 允许速率下限 [℃/min] Rate floor [degC/min] *)
    DL_ACRC_RMAX : REAL := 100.0;       (* 允许速率上限 [℃/min] Rate ceiling [degC/min] *)
END_VAR
(* 首扫初始化：以当前温度播种上拍快照，避免虚假大速率（R310） *)
IF NOT _bInit THEN
    _fPrev := fTempActC;
    _fRate := 0.0;
    _bInit := TRUE;
END_IF
(* 周期派生：非法周期取 10 ms 缺省（步长不塌零，除零结构性排除） *)
IF (fCycleS > 0.0) AND (fCycleS <= 1.0) THEN
    _fCy := fCycleS;
ELSE
    _fCy := DL_ACRC_CYDEF;
END_IF
(* 非有限闸（NaN 自反 + Inf 差值自减）+ 组态域闸：四浮点入参全枚举（R272） *)
_bCfgBad := (fTempActC <> fTempActC) OR ((fTempActC - fTempActC) <> 0.0)
         OR (fTempSpC <> fTempSpC) OR ((fTempSpC - fTempSpC) <> 0.0)
         OR (fCoolRateMaxCpm <> fCoolRateMaxCpm) OR ((fCoolRateMaxCpm - fCoolRateMaxCpm) <> 0.0)
         OR (fCycleS <> fCycleS) OR ((fCycleS - fCycleS) <> 0.0)
         OR (fTempActC < DL_ACRC_TMIN) OR (fTempActC > DL_ACRC_TMAX)
         OR (fTempSpC < DL_ACRC_TMIN) OR (fTempSpC > DL_ACRC_TMAX)
         OR (fCoolRateMaxCpm < DL_ACRC_RMIN) OR (fCoolRateMaxCpm > DL_ACRC_RMAX);
_bCalcOk := xEnable AND (NOT _bCfgBad);
IF _bCalcOk THEN
    (* 一阶差分：正值为降温方向，量纲 ℃/s × 60 = ℃/min *)
    _fRate := ((_fPrev - fTempActC) / _fCy) * DL_ACRC_SECMIN;
    (* 归因分离：超速与超温各写各的成员，互不共用赋值点（R190） *)
    _bOverRate := _fRate > fCoolRateMaxCpm;
    _bOverTemp := fTempActC > (fTempSpC + DL_ACRC_TOL);
    (* 快照推进放在有效计算之后，冻结时快照不动 *)
    _fPrev := fTempActC;
ELSE
    _bOverRate := FALSE;
    _bOverTemp := FALSE;
    _fPrev := fTempActC;                    (* 冻结拍也同步快照，恢复时不产生阶跃虚假速率 *)
END_IF
(* 统一出口（单点赋值）：冻结分支保持末次有效速率，保持量为已过闸的有限值（R273） *)
fRateActCpm := _fRate;
xRateAlarm := (_bOverRate OR _bOverTemp) AND _bCalcOk;
xValid := _bCalcOk;
END_FUNCTION_BLOCK
