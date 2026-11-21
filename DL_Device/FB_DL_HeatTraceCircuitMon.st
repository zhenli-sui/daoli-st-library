(*
  Name        : FB_DL_HeatTraceCircuitMon
  Category    : DL_Device
  Version     : 1.0.1
  Purpose     : 电伴热回路监视：以「加热命令 × 电流存在性 × 温升响应」三重交叉判据区分断缆（无电流）、空烧/过热（超温）、热耦合失效（有电流但无温升）；/ Monitor heat-trace circuits by cross-checking heat command, current presence and temperature-rise response to distinguish open circuit, over-temperature and lost thermal coupling
  溯源        : 借 t2-8-isa182·回路一致性 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：电流下限/观察窗/最小温升/温度上限任一越域 → 锁存故障；
                ② 观察窗用自复位 TON（IN := NOT tonObs.Q，R188），窗起点温度快照在窗开始那拍取；
                ③ 断缆判据需延时确认（tCurrentConf），避免接触器合闸瞬态误判；
                ④ 三种成因各有独立状态成员与独立判据位（R190 归因唯一），不共用枚举成员；
                ⑤ 本件为诊断层，不驱动加热输出；切除动作须由上层安全联锁执行（属主边界）。
                ⑥ 输出语义（R191 名实双出口）：三个判据位在命中后锁存（仅复位沿清），bError 与
                   之同源置位；相位保持在 eMon 继续监视（不迁 eFault 冻结），以便断缆修复后
                   仍能观察其余判据 —— 此为「降级继续监视」而非冻结，故不置 eFault。
  修订记录    : 2026-11-20 v1.0.1：段 0 双定时器 IN 串 eMon 相位闸（确认延时/观察窗不再跨相自由跑，R52-07）；eIdle→eMon 迁入拍补 _fTempT0/_bT0Ok 起点快照。
*)
TYPE E_DL_HtcState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eMon   := 10,                            (* 监视运行 / Monitoring *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_HtcCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：电流/时间/温升/温度越域 / Illegal config *)
    eOpenCirc   := 2,                        (* 成因：断缆（命令通而无电流） / Cause: open circuit *)
    eOverTemp   := 3,                        (* 成因：过热（超温上限） / Cause: over-temperature *)
    eNoRise     := 4,                        (* 成因：无温升（电流有而热耦合失效） / Cause: no temperature rise *)
    ePhaseBad   := 5                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_HeatTraceCircuitMon
VAR_INPUT
    bHeatCmd   : BOOL := FALSE;              (* 加热命令电平 [-] / Heat command level *)
    fCurrent   : REAL := 0.0;                (* 回路电流实测，域 >= 0 [A] / Measured loop current *)
    fCurrentMin: REAL := 0.5;                (* 电流存在性下限，域 > 0 [A] / Current presence threshold, > 0 *)
    fTemp      : REAL := 20.0;               (* 伴热测点温度 [°C] / Heat-trace temperature *)
    tObserve   : TIME := T#300S;             (* 温升观察窗长，域 > T#0S [ms] / Rise observation window, > 0 *)
    fRiseMin   : REAL := 3.0;                (* 窗内最小期望温升，域 > 0 [K] / Minimum expected rise, > 0 *)
    fTempMax   : REAL := 120.0;              (* 温度上限（过热阈值）[°C] / Over-temperature limit *)
    bEnable    : BOOL := TRUE;               (* 监视使能 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清锁存与故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fRiseObs   : REAL;                       (* 观察窗内实测温升（当前窗）[K] / Measured rise in current window *)
    bCurPresent: BOOL;                       (* 电流存在性（本拍判定）[-] / Current presence *)
    bOpenCirc  : BOOL;                       (* 断缆判据锁存（命令通且无电流）[-] / Open-circuit latch *)
    bOverTemp  : BOOL;                       (* 过热判据锁存（超温上限）[-] / Over-temperature latch *)
    bNoRise    : BOOL;                       (* 无温升判据锁存（有电流但窗内温升不足）[-] / No-rise latch *)
    eState     : E_DL_HtcState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_HtcCause;              (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_HtcState := E_DL_HtcState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_HtcCause := E_DL_HtcCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonObs   : TON;                          (* 观察窗自复位计时器（R188） / Self-resetting observation window *)
    tonNoCur : TON;                          (* 无电流确认延时计时器（IN 由命令与电流派生） / No-current confirm timer *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bFinite : BOOL;                         (* 输入有限性当拍量 / Input finiteness *)
    _bCur    : BOOL;                         (* 电流存在性当拍量 / Current presence this scan *)
    _fTempT0 : REAL;                         (* 观察窗起点温度快照 [°C] / Temperature at window start *)
    _bT0Ok   : BOOL;                         (* 起点快照有效标志 / Snapshot validity *)
    _fRise   : REAL;                         (* 本窗温升中间量 [K] / Rise intermediate *)
END_VAR
VAR CONSTANT
    DL_HTC_EPS    : REAL := 1.0E-6;          (* 判零容差 [-] / Epsilon *)
    DL_HTC_TMIN   : REAL := 0.0;             (* 温度上限可接受下限（防组态倒置）[°C] / Temperature limit floor *)
    DL_HTC_CONF   : TIME := T#5S;            (* 断缆确认延时（接触器合闸瞬态穿越）[ms] / Open-circuit confirm delay *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；定时器全在段 0，无 IF 包裹） —— *)
_bCfgBad := (fCurrentMin <= DL_HTC_EPS)                                        (* 电流下限正域闸 / Current threshold gate *)
            OR NOT (tObserve > T#0S)                                           (* 观察窗正域闸 / Window gate *)
            OR (fRiseMin <= DL_HTC_EPS)                                        (* 最小温升正域闸 / Rise gate *)
            OR (fTempMax < DL_HTC_TMIN);                                       (* 温度上限须为非负（防组态倒置） / Temperature limit gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
tonObs(IN := (_eState = E_DL_HtcState.eMon) AND NOT tonObs.Q, PT := tObserve);                 (* 观察窗自复位（R188）+ eMon 相位闸（v1.0.1，上拍相位 1 拍延迟可接受） / Self-resetting window with phase gate *)
tonNoCur(IN := (_eState = E_DL_HtcState.eMon) AND bHeatCmd AND NOT _bCur, PT := DL_HTC_CONF);   (* 无电流确认延时（命令通且无电流才计时）+ 相位闸（v1.0.1） / No-current confirm with phase gate *)
_bFinite := (fCurrent = fCurrent) AND (fTemp = fTemp)                          (* NaN 自反闸 / NaN reflex gates *)
            AND ((fCurrent - fCurrent) = (fCurrent - fCurrent))                (* 电流 Inf 闸 / Current Inf gate *)
            AND ((fTemp - fTemp) = (fTemp - fTemp));                           (* 温度 Inf 闸 / Temperature Inf gate *)
_bCur := _bFinite AND (fCurrent >= fCurrentMin);                               (* 电流存在性：有限且 >= 下限 / Presence: finite and above threshold *)

(* —— 段 1：单拍量预清零（R107） —— *)
bCurPresent := FALSE;                                                          (* 电流指示预清 / Presence preset *)
fRiseObs := 0.0;                                                               (* 温升出口预清 / Rise preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清三判据 + 清快照 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_HtcCause.eNone;                                            (* 清成因 / Clear cause *)
    bOpenCirc := FALSE;                                                        (* 清断缆判据 / Clear open-circuit *)
    bOverTemp := FALSE;                                                        (* 清过热判据 / Clear over-temperature *)
    bNoRise := FALSE;                                                          (* 清无温升判据 / Clear no-rise *)
    _bT0Ok := FALSE;                                                           (* 清起点快照有效位（重新取快照） / Clear snapshot flag *)
    _fTempT0 := 0.0;                                                           (* 清起点温度 / Clear snapshot value *)
    _eState := E_DL_HtcState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_HtcCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_HtcState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_HtcState.eIdle:                                                       (* 未使能：快照失效，不判 / Disabled *)
        _bT0Ok := FALSE;                                                       (* 失能清快照（重使能重新对齐） / Clear snapshot *)
        IF bEnable AND NOT _bFault THEN
            _fTempT0 := fTemp;                                                 (* 迁入拍即取窗起点温度快照（相位闸配套，v1.0.1） / Snapshot at entry scan *)
            _bT0Ok := TRUE;                                                    (* 快照有效位随迁入同步置位 / Set snapshot flag at entry *)
            _eState := E_DL_HtcState.eMon;                                     (* 使能进入监视 / Enter monitoring *)
        END_IF
    E_DL_HtcState.eMon:                                                        (* 监视相：三重判据 / Monitoring *)
        IF NOT bEnable THEN
            _eState := E_DL_HtcState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSE
            bCurPresent := _bCur;                                              (* 电流指示出口（名实同源，R191） / Presence outlet *)
            IF _bFinite THEN
                IF NOT _bT0Ok THEN
                    _fTempT0 := fTemp;                                         (* 窗起点快照：首拍或窗回零点 / Window start snapshot *)
                    _bT0Ok := TRUE;                                            (* 立快照有效位 / Set snapshot flag *)
                END_IF
                _fRise := fTemp - _fTempT0;                                    (* 本窗温升 = 当前 - 起点（可负）[K] / Rise this window *)
                fRiseObs := _fRise;                                            (* 温升出口 / Rise outlet *)
                IF fTemp > fTempMax THEN                                       (* 过热判据（独立位，R190） / Over-temperature verdict *)
                    bOverTemp := TRUE;                                         (* 过热锁存（复位沿清） / Latch over-temperature *)
                    IF NOT _bFault THEN
                        _bFault := TRUE;                                       (* 同步故障锁存 / Latch fault *)
                        _eCause := E_DL_HtcCause.eOverTemp;                    (* 成因：过热 / Cause: over-temperature *)
                    END_IF
                END_IF
                IF tonNoCur.Q THEN                                             (* 命令通但确认延时内无电流：断缆 / Open circuit *)
                    bOpenCirc := TRUE;                                         (* 断缆锁存（复位沿清） / Latch open-circuit *)
                    IF NOT _bFault THEN
                        _bFault := TRUE;                                       (* 同步故障锁存 / Latch fault *)
                        _eCause := E_DL_HtcCause.eOpenCirc;                    (* 成因：断缆 / Cause: open circuit *)
                    END_IF
                END_IF
                IF tonObs.Q THEN                                               (* 观察窗到点：结算温升响应 / Window elapsed: settle *)
                    IF _bCur AND (_fRise < fRiseMin) THEN                      (* 有电流却温升不足：热耦合失效 / Current present but no rise *)
                        bNoRise := TRUE;                                       (* 无温升锁存（复位沿清） / Latch no-rise *)
                        IF NOT _bFault THEN
                            _bFault := TRUE;                                   (* 同步故障锁存 / Latch fault *)
                            _eCause := E_DL_HtcCause.eNoRise;                  (* 成因：无温升 / Cause: no rise *)
                        END_IF
                    END_IF
                    _fTempT0 := fTemp;                                         (* 新窗起点重置（自复位计时器同拍已回 0） / Restart window baseline *)
                    _bT0Ok := TRUE;                                            (* 快照保持有效 / Keep snapshot valid *)
                END_IF
            END_IF                                                             (* 非有限输入：本拍不判，保持锁存 / Non-finite: skip *)
        END_IF
    E_DL_HtcState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_HtcState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_HtcCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
