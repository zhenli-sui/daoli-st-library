(*
  Name: FB_DL_CoilTaperTensionSeq
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 板带剪切分条卷取，ST 开源生态实测 0 命中，无外部代码引入）
  功能：卷取锥度张力斜坡控制序列：起卷建立张力→按卷径锥度衰减→尾卷保持。
  边界条件：① 五浮点入参全部过非有限闸；配置越域进冻结分支：输出保持末值 + xValid = FALSE（R191）；
            ② xEnable = FALSE 语义：冻结保持末张力（不降至 0，避免带钢松卷），xValid 同拍置 FALSE；
            ③ 锥度式 T = T0·(1 − taper·D/Dmax)：满卷时降至 T0·(1−taper)，起卷为 T0；
            ④ 尾卷判据 D ≥ 0.95·Dmax 后冻结衰减值（保持最后有效张力），不再随卷径继续下探；
            ⑤ 斜坡速率固定 DL_CTS_RATE [kN/s]，步长 = 速率 × fCycleS（周期入参，非法周期取 10 ms 缺省）。
  量纲自证：kN/s × s = kN；D/Dmax 无量纲，锥度量纲为 kN。
*)
TYPE E_DL_CtiPhase :
(
    eIdle  := 0,        (* 待机：未使能 / Idle, not enabled *)
    eBuild := 10,       (* 建张相：0 → T0 斜坡 / Tension build ramp *)
    eTaper := 20,       (* 锥度相：按卷径衰减 / Taper by coil diameter *)
    eTail  := 30,       (* 尾卷相：冻结衰减值保持 / Tail hold, taper frozen *)
    eFault := 90        (* 故障相：配置越域 / Fault, configuration out of range *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_CoilTaperTensionSeq
VAR_INPUT
    xEnable : BOOL;         (* 使能 [-] Enable *)
    fDiaActMm : REAL;       (* 卷径实测 [mm] Coil diameter actual [mm] *)
    fDiaMaxMm : REAL;       (* 最大卷径 [mm] Maximum coil diameter [mm] *)
    fTensionInitKN : REAL;  (* 起卷初始张力 [kN] Initial tension at build-up [kN] *)
    fTaperPct : REAL;       (* 锥度率（满卷衰减比例） [%] Taper ratio at full coil [%] *)
    fCycleS : REAL;         (* 扫描周期 [s] Scan cycle [s] *)
END_VAR
VAR_OUTPUT
    fTensionRefKN : REAL;   (* 张力设定 [kN] Tension setpoint [kN] *)
    eState : E_DL_CtiPhase; (* 当前相 [-] Present phase *)
    xValid : BOOL;          (* 配置与链路有效 [-] Configuration and chain valid *)
END_VAR
VAR
    _ePhase : E_DL_CtiPhase := E_DL_CtiPhase.eIdle;  (* 内部相（CASE 唯一写入目标） [-] Internal phase *)
    _bInit : BOOL := FALSE;     (* 首扫初始化标志 [-] First-scan init flag *)
    _bCfgBad : BOOL := FALSE;   (* 配置非法当拍量 [-] Configuration bad *)
    _bCalcOk : BOOL := FALSE;   (* 本拍有效 [-] Valid this scan *)
    _fRef : REAL := 0.0;        (* 张力设定保持量 [kN] Tension hold [kN] *)
    _fRatio : REAL := 0.0;      (* 卷径比 D/Dmax [-] Diameter ratio *)
    _fTaperKN : REAL := 0.0;    (* 当拍锥度张力 [kN] Tapered tension [kN] *)
    _fStep : REAL := 0.0;       (* 单拍斜坡步长 [kN] Ramp step per scan [kN] *)
    _fCy : REAL := 0.01;        (* 当拍有效周期 [s] Effective cycle [s] *)
END_VAR
VAR CONSTANT
    DL_CTS_EPS : REAL := 1.0E-9;        (* 判据容差 [-] Criterion tolerance *)
    DL_CTS_RATE : REAL := 5.0;          (* 建张斜坡速率 [kN/s] Build-up ramp rate [kN/s] *)
    DL_CTS_TAIL : REAL := 0.95;         (* 尾卷卷径比门限 [-] Tail diameter ratio *)
    DL_CTS_CYDEF : REAL := 0.01;        (* 缺省扫描周期 [s] Default scan cycle [s] *)
    DL_PCT : REAL := 100.0;             (* 百分数基准 [%] Percent base *)
END_VAR
(* 首扫初始化：张力设定从 0 起（建张相负责抬升） *)
IF NOT _bInit THEN
    _fRef := 0.0;
    _ePhase := E_DL_CtiPhase.eIdle;
    _bInit := TRUE;
END_IF
(* 非有限闸（NaN 自反 + Inf 差值自减）+ 组态域闸：五浮点入参全枚举（R272） *)
_bCfgBad := (fDiaActMm <> fDiaActMm) OR ((fDiaActMm - fDiaActMm) <> 0.0)
         OR (fDiaMaxMm <> fDiaMaxMm) OR ((fDiaMaxMm - fDiaMaxMm) <> 0.0)
         OR (fTensionInitKN <> fTensionInitKN) OR ((fTensionInitKN - fTensionInitKN) <> 0.0)
         OR (fTaperPct <> fTaperPct) OR ((fTaperPct - fTaperPct) <> 0.0)
         OR (fCycleS <> fCycleS) OR ((fCycleS - fCycleS) <> 0.0)
         OR (fDiaMaxMm < 100.0) OR (fDiaMaxMm > 2500.0)
         OR (fDiaActMm < 50.0) OR (fDiaActMm > (fDiaMaxMm + DL_CTS_EPS))
         OR (fTensionInitKN < 0.1) OR (fTensionInitKN > 500.0)
         OR (fTaperPct < 0.0) OR (fTaperPct > 60.0);
(* 周期派生：非法周期取 10 ms 缺省 *)
IF (fCycleS > 0.0) AND (fCycleS <= 1.0) THEN
    _fCy := fCycleS;
ELSE
    _fCy := DL_CTS_CYDEF;
END_IF
(* 卷径比：无量纲，分母已过下限闸 *)
_fRatio := fDiaActMm / fDiaMaxMm;
_bCalcOk := xEnable AND (NOT _bCfgBad);
(* 状态机：使能沿进入建张相；失能回待机（冻结保持，见出口） *)
CASE _ePhase OF
E_DL_CtiPhase.eIdle:
    IF _bCalcOk THEN
        _ePhase := E_DL_CtiPhase.eBuild;        (* 使能 → 建张 / Enabled, build tension *)
    END_IF
E_DL_CtiPhase.eBuild:
    _fStep := DL_CTS_RATE * _fCy;               (* kN/s × s = kN / Ramp step *)
    _fRef := _fRef + _fStep;                    (* 斜坡抬升 / Ramp up *)
    IF _fRef >= fTensionInitKN THEN
        _fRef := fTensionInitKN;                (* 到 T0 即止，绝无过冲 / Clamp to T0 *)
        _ePhase := E_DL_CtiPhase.eTaper;        (* → 锥度相 / To taper *)
    END_IF
E_DL_CtiPhase.eTaper:
    (* 锥度式：T = T0·(1 − taper·D/Dmax)，量纲 kN *)
    _fTaperKN := fTensionInitKN * (1.0 - (fTaperPct / DL_PCT) * _fRatio);
    _fRef := _fTaperKN;
    IF _fRatio >= DL_CTS_TAIL THEN
        _ePhase := E_DL_CtiPhase.eTail;         (* 到尾卷 → 冻结保持 / Tail, freeze *)
    END_IF
E_DL_CtiPhase.eTail:
    _fRef := _fTaperKN;                         (* 保持末有效锥度值 / Hold last tapered value *)
E_DL_CtiPhase.eFault:
    _fRatio := fDiaActMm / fDiaMaxMm;           (* 故障相驻留：仅刷新卷径比供追溯 *)
    IF _bCalcOk THEN
        _ePhase := E_DL_CtiPhase.eIdle;         (* 解除路径：配置恢复且使能 → 回待机（R152） *)
    END_IF
ELSE
    _ePhase := E_DL_CtiPhase.eFault;            (* 非法相兜底：直接迁故障相 / Illegal phase fallback *)
END_CASE
(* 失能或配置越域：非故障相回待机（出口冻结保持末张力，R191 已声明） *)
IF (NOT _bCalcOk) AND (_ePhase <> E_DL_CtiPhase.eFault) THEN
    _ePhase := E_DL_CtiPhase.eIdle;
END_IF
(* 统一出口（单点赋值）：冻结分支右值为已过闸的有限保持量（R273） *)
fTensionRefKN := _fRef;
eState := _ePhase;
xValid := _bCalcOk;
END_FUNCTION_BLOCK
