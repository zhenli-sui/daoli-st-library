(*
  Name        : FB_DL_SchmittTriggerGap
  Category    : DL_Base
  Version     : 1.0.0
  Purpose     : 带回差的双阈值整形器（施密特）：上阈置位、下阈复位，滞带宽可组态，输出干净布尔电平与单拍沿脉冲；/ Dual-threshold Schmitt shaping: set at upper threshold, reset at lower threshold, configurable hysteresis band, clean boolean plus single-scan edge pulses
  溯源        : 借 t2-1-lgf·comparator 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：fThHigh - fThLow <= eps（带宽容差比较，禁 = ）→ 锁存故障，输出保持 FALSE；
                ② 非有限输入该拍不参与翻转判定（保留上拍电平，防误翻）；
                ③ 翻转计数 UDINT 饱和：到 4294967295 前停止累加（防回绕）；
                ④ 沿脉冲单拍化：内部 _b* 置位 → 出口统一映射，不在 CASE 内直接写输出（R187）。
*)
TYPE E_DL_SchState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eRun   := 10,                            (* 整形运行 / Shaping active *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_SchCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：滞带宽非正 / Illegal config: band non-positive *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_SchmittTriggerGap
VAR_INPUT
    fIn      : REAL := 0.0;                  (* 原始测量输入 [工程单位] / Raw measurement input *)
    fThHigh  : REAL := 70.0;                 (* 上阈（置位阈），须 > fThLow [工程单位] / Upper (set) threshold *)
    fThLow   : REAL := 30.0;                 (* 下阈（复位阈），须 < fThHigh [工程单位] / Lower (reset) threshold *)
    bEnable  : BOOL := TRUE;                 (* 整形使能 [-] / Enable *)
    bReset   : BOOL := FALSE;                (* 复位命令，上升沿清故障/计数/电平 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bOut       : BOOL;                       (* 整形后布尔电平 [-] / Shaped boolean level *)
    bRising    : BOOL;                       (* 本拍上升沿脉冲（低→高）[-] / This-scan rising pulse *)
    bFalling   : BOOL;                       (* 本拍下降沿脉冲（高→低）[-] / This-scan falling pulse *)
    nTransitions : UDINT;                    (* 累计翻转次数（饱和 4.29e9）[-] / Total transitions, saturated *)
    eState     : E_DL_SchState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_SchCause;              (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_SchState := E_DL_SchState.eIdle;   (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_SchCause := E_DL_SchCause.eNone;   (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _fBand   : REAL;                         (* 当拍滞带宽 = fThHigh - fThLow [工程单位] / Hysteresis band *)
    _bLevel  : BOOL;                         (* 电平保持量（施密特记忆） / Level memory *)
    _bRiseC  : BOOL;                         (* 上升沿当拍判据（内部，出口统一映射） / Rising verdict, internal *)
    _bFallC  : BOOL;                         (* 下降沿当拍判据（内部） / Falling verdict, internal *)
    _bFinite : BOOL;                         (* 输入有限性判定当拍量 / Input finiteness this scan *)
END_VAR
VAR CONSTANT
    DL_SCH_EPS  : REAL  := 1.0E-6;           (* 带宽判零容差（REAL 量级）[-] / Band epsilon *)
    DL_SCH_CNTMAX : UDINT := 4294967295;     (* 翻转计数饱和上限（UDINT 可表上限，R28）[-] / Counter saturation cap *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (fThHigh - fThLow) <= DL_SCH_EPS;                                  (* 组态闸：带宽须为正（容差比较，R151） / Config gate: band must be positive *)
_bFinite := (fIn = fIn) AND ((fIn - fIn) = (fIn - fIn));                       (* NaN 自反 + Inf 差判联合闸 / NaN reflex and Inf gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调（段 0 恒执行） / Reset edge every scan *)
_fBand := fThHigh - fThLow;                                                    (* 跟踪带宽容差（仅映像，不参与闸） / Band mirror *)

(* —— 段 1：单拍量预清零（R107：沿脉冲内部量每拍清零，仅命中分支置位） —— *)
_bRiseC := FALSE;                                                              (* 上升沿判据预清 / Rising preset *)
_bFallC := FALSE;                                                              (* 下降沿判据预清 / Falling preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清计数 + 清电平 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_SchCause.eNone;                                            (* 清成因 / Clear cause *)
    nTransitions := 0;                                                         (* 清翻转计数 / Clear counter *)
    _bLevel := FALSE;                                                          (* 清电平记忆（回低电平，避免隐性回夹） / Clear level, no implicit clamp *)
    _eState := E_DL_SchState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R45 配对 / R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_SchCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_SchState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_SchState.eIdle:                                                       (* 未使能：电平强制 FALSE，不判翻转 / Disabled *)
        _bLevel := FALSE;                                                      (* 电平原位清（声明语义：失能即输出 FALSE） / Level forced low *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_SchState.eRun;                                     (* 使能进入整形 / Enter shaping *)
        END_IF
    E_DL_SchState.eRun:                                                        (* 整形相：双阈值滞环判定 / Shaping *)
        IF NOT bEnable THEN
            _bLevel := FALSE;                                                  (* 失能清电平 / Disable clears level *)
            _eState := E_DL_SchState.eIdle;                                    (* 回未使能 / Back to idle *)
        ELSIF _bFinite THEN
            IF (NOT _bLevel) AND (fIn >= fThHigh) THEN
                _bLevel := TRUE;                                               (* 超上阈置位（上升沿） / Above upper: set *)
                _bRiseC := TRUE;                                               (* 上升沿当拍判据置位 / Rising verdict *)
            ELSIF _bLevel AND (fIn <= fThLow) THEN
                _bLevel := FALSE;                                              (* 破下阈复位（下降沿） / Below lower: reset *)
                _bFallC := TRUE;                                               (* 下降沿当拍判据置位 / Falling verdict *)
            END_IF
        END_IF                                                                 (* 非有限输入：保留上拍电平，不翻转（边界②） / Non-finite: hold *)
    E_DL_SchState.eFault:                                                      (* 故障相：保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_SchState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_SchCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：翻转计数（饱和写入单点，双向合并非双计） —— *)
IF (_bRiseC OR _bFallC) AND (nTransitions < DL_SCH_CNTMAX) THEN
    nTransitions := nTransitions + 1;                                          (* 单次翻转净额 +1，饱和前停加 / Net +1 per transition, saturating *)
END_IF

(* —— 段 6：出口映射（内部 _b* → 输出单拍映射，R187；名实双出口，R191） —— *)
bOut := _bLevel;                                                               (* 电平出口 = 记忆电平 / Level outlet *)
bRising := _bRiseC;                                                            (* 上升沿单拍出口 / Rising single-scan outlet *)
bFalling := _bFallC;                                                           (* 下降沿单拍出口 / Falling single-scan outlet *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
