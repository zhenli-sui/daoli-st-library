(*
  FB_DL_SelfDischargeScreen  —  自放电筛分（压降速率 K 值分级 + 温度补偿） / Self-discharge screening by voltage-drop rate grading with temperature compensation
  分类 Category : DL_Algo
  版本 Version  : 1.0.0
  来源 Source   : roadmap-li-p2 — 锂电自放电筛分工站真缺口
  溯源 Origin   : 道莅 clean-room 实现；K 值 = ΔOCV/Δt 与 25 °C 温度补偿为公开自放电筛分算法，未复制任何源码行
  功能 Function : 1) 纯计算子函数 FC_DL_SelfDischargeKCalc 求压降速率
                  K = (fOcvStartV - fOcvEndV) / 静置时长(h)，静置时长按秒换算（除 3600.0 常量）；
                  2) 温度补偿：K25 = K / (1.0 + fTempCoeffPerK × (fTempC - 25.0))，
                  分母绝对值 <= 1.0E-6 返回 -1.0 哨兵（不饱和、不置 0，交主块判故障）；
                  3) 分级：K25 与 fClassAMvPerH / fClassBMvPerH / fClassCMvPerH 比较，
                  越 C 档为 eReject（ELSE 兜底）；
                  4) 报告值向上取整到 0.001 mV/h（先实数上限兜底 → 截断 → 余量进位，
                  正好整除不 +1，禁 TRUNC(x)+1）；
                  5) 本件只有故障码、无信息码（派单硬约束）。
  接口 Interface: 输入首末 OCV/静置时长/温度/温度系数/三档阈值；输出 K/K25/取整值/分级/码
  边界 Boundary : ① 组态闸：tRest <= T#0S、fTempCoeffPerK < 0.0、fClassAMvPerH < 0.0、
                  fClassBMvPerH <= fClassAMvPerH、fClassCMvPerH <= fClassBMvPerH
                  → 0389 锁存；② 首末 OCV 非有限（NaN 自反 + Inf 差值自减）→ 0389 锁存；
                  ③ 温补分母哨兵 -1.0 由主块转 0389 锁存（子函数不置故障）；
                  ④ 取整前实数上限兜底防 LREAL→DINT 溢出；⑤ 仅一个 R_TRIG，段 0 无条件调用；
                  ⑥ 故障相迁出唯一路径 = bReset 上升沿；⑦ 零全局耦合（无 GVL / %I %Q %M）。
  依赖 Depends  : Standard.library（R_TRIG）
  码表 Error codes（Algo 段 0002，故障窗口 0389；本件无信息码）:
    16#0002_0389 故障级：自放电筛分故障总码（组态非法 / OCV 非有限 / 温补分母非法），
                 锁存至 bReset 上升沿；归因见 eCause，不新增码位（派单硬约束单码）
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 3 · 序号 13）
*)

TYPE E_DL_SdsState :
(
    eIdle   := 0,     // 未使能待筛分 / Idle, waiting screening
    eRun    := 10,    // 筛分计算中 / Screening active
    eFault  := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_SdsClass :
(
    eNone   := 0,     // 未分级 / Not graded
    eClassA := 1,     // A 级（自放电最小） / Class A, lowest self-discharge
    eClassB := 2,     // B 级 / Class B
    eClassC := 3,     // C 级 / Class C
    eReject := 4      // 不合格（越 C 档） / Rejected
);
END_TYPE

TYPE E_DL_SdsCause :
(
    eNone       := 0, // 无故障成因 / No cause
    eCfgIllegal := 1, // 组态非法 / Illegal configuration
    eNonFinite  := 2, // OCV 非有限 / Non-finite OCV
    eCompDiv    := 3  // 温补分母非法 / Invalid compensation denominator
);
END_TYPE

FUNCTION FC_DL_SelfDischargeKCalc : REAL
VAR_INPUT
    fOcvStartV     : REAL;   // 静置前 OCV [V] / OCV before rest
    fOcvEndV       : REAL;   // 静置后 OCV [V] / OCV after rest
    fRestS         : REAL;   // 静置时长 [s]，域 > 0 / Rest duration in seconds
    fTempC         : REAL;   // 电芯温度 [°C] / Cell temperature
    fTempCoeffPerK : REAL;   // 温度系数 [1/K]，域 >= 0 / Temperature coefficient
END_VAR
VAR
    _fKPerH  : REAL;         // 未补偿压降速率 [V/h] / Uncompensated drop rate
    _fDen    : REAL;         // 温补分母 [-] / Compensation denominator
END_VAR
(* 纯计算子函数：K25 = K / (1 + coeff × (T - 25))；分母非法返回 -1.0 哨兵 *)
IF fRestS <= 1.0E-6 THEN                              // 除零前置判（时长正域） / Duration positive check
    FC_DL_SelfDischargeKCalc := -1.0;                 // 哨兵：时长非法 / Sentinel
    RETURN;
END_IF
_fKPerH := (fOcvStartV - fOcvEndV) / (fRestS / 3600.0);   // 压降速率 [V/h]（除常量 3600.0） / Drop rate
_fDen := 1.0 + fTempCoeffPerK * (fTempC - 25.0);          // 温补分母 / Compensation denominator
IF ABS(_fDen) <= 1.0E-6 THEN                          // 分母近零判据 / Near-zero denominator
    FC_DL_SelfDischargeKCalc := -1.0;                 // 哨兵：分母非法 / Sentinel
    RETURN;
END_IF
FC_DL_SelfDischargeKCalc := _fKPerH / _fDen * 1000.0; // 补偿后速率 [mV/h] / Compensated rate
END_FUNCTION

FUNCTION_BLOCK FB_DL_SelfDischargeScreen
VAR_INPUT
    fOcvStartV      : REAL := 0.0;      // 静置前 OCV [V] / OCV before rest
    fOcvEndV        : REAL := 0.0;      // 静置后 OCV [V] / OCV after rest
    tRest           : TIME := T#24H;    // 静置时长 [ms]，域 > 0 / Rest duration
    fTempC          : REAL := 25.0;     // 电芯温度 [°C] / Cell temperature
    fTempCoeffPerK  : REAL := 0.002;    // 温度系数 [1/K]，域 >= 0 / Temperature coefficient
    fClassAMvPerH   : REAL := 0.50;     // A 级上限 [mV/h] / Class A limit
    fClassBMvPerH   : REAL := 1.00;     // B 级上限 [mV/h] / Class B limit
    fClassCMvPerH   : REAL := 2.00;     // C 级上限 [mV/h] / Class C limit
    bEnable         : BOOL := FALSE;    // 筛分使能（电平）[-] / Screening enable
    bReset          : BOOL := FALSE;    // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState          : E_DL_SdsState;    // 状态出口，段 6 单点映射 / State outlet
    eClass          : E_DL_SdsClass;    // 分级出口 / Grading outlet
    eCause          : E_DL_SdsCause;    // 故障成因出口（R190） / Fault cause outlet
    fKMvPerH        : REAL;             // 温补后压降速率 [mV/h] / Compensated drop rate
    fKCeilMvPerH    : REAL;             // 向上取整到 0.001 的速率 [mV/h] / Ceiled rate
    bError          : BOOL;             // 故障锁存标志 [-] / Fault latch flag
    nErrId          : UDINT;            // 故障码，0 = 无故障（本件无信息码） / Fault code only
END_VAR
VAR
    _eState         : E_DL_SdsState := E_DL_SdsState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eClass         : E_DL_SdsClass := E_DL_SdsClass.eNone;   // 分级槽（每拍重算） / Grading slot
    _eCause         : E_DL_SdsCause := E_DL_SdsCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    rtReset         : R_TRIG;           // 复位沿实例，每周期无条件调用 / Reset edge
    _fK             : REAL;             // 子函数返回速率 [mV/h]（当拍量） / Sub-function result
    _fScaled        : REAL;             // 取整中间量（×1000 后） / Scaling intermediate
    _iScaled        : DINT;             // 截断后整数（×1000） / Truncated integer
    _bNonFin        : BOOL;             // OCV 非有限当拍量 [-] / Non-finite OCV
    _bCfgBad        : BOOL;             // 组态非法当拍量 [-] / Config illegal
    _bFault         : BOOL;             // 故障锁存位（锁存量） / Latched fault bit
    _uFault         : UDINT;            // 故障码锁存（锁存量） / Latched fault code
END_VAR

(* —— 段 0：沿实例无条件周期刷新 + 当拍量判据 —— *)
_bNonFin := (fOcvStartV <> fOcvStartV) OR (fOcvEndV <> fOcvEndV) OR (fTempC <> fTempC)
         OR ((fOcvStartV - fOcvStartV) <> (fOcvStartV - fOcvStartV))
         OR ((fOcvEndV - fOcvEndV) <> (fOcvEndV - fOcvEndV))
         OR ((fTempC - fTempC) <> (fTempC - fTempC));                        // NaN 自反 + Inf 差值自减 / NaN and Inf
_bCfgBad := (tRest <= T#0S) OR (fTempCoeffPerK < 0.0) OR (fClassAMvPerH < 0.0)
            OR (fClassBMvPerH <= fClassAMvPerH) OR (fClassCMvPerH <= fClassBMvPerH);   // 组态非法当拍量 / Config illegal
rtReset(CLK := bReset);                                                      // 复位沿，每拍必调 / Reset edge

(* —— 段 1：单拍量预清零（锁存量不入清单；分级槽每拍重算） —— *)
eClass := E_DL_SdsClass.eNone;      // 分级出口缺省未分级 / Grading default
fKMvPerH := 0.0;                    // 速率出口缺省 0 / Rate default
fKCeilMvPerH := 0.0;                // 取整出口缺省 0 / Ceil default
nErrId := 16#0000_0000;             // 故障码缺省无故障 / Fault code default

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_SdsCause.eNone;            // 清成因（锁存量） / Clear cause
    IF _eState = E_DL_SdsState.eFault THEN
        _eState := E_DL_SdsState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bNonFin THEN                               // 非有限锁存 / Non-finite latch
    _uFault := 16#0002_0389;                   // 故障级：筛分故障总码 / Algo fault code
    _eCause := E_DL_SdsCause.eNonFinite;       // 归因：非有限 / Cause: non-finite
    _bFault := TRUE;                           // 标志与码位配对（R45） / Flag paired with code
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0002_0389;
    _eCause := E_DL_SdsCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
    _bFault := TRUE;
END_IF

(* —— 段 3：K 值计算 + 温补哨兵 + 取整 + 分级（仅运行相且无故障） —— *)
IF (NOT _bFault) AND (_eState = E_DL_SdsState.eRun) THEN
    _fK := FC_DL_SelfDischargeKCalc(fOcvStartV := fOcvStartV, fOcvEndV := fOcvEndV,
                                    fRestS := TIME_TO_REAL(tRest) / 1000.0,
                                    fTempC := fTempC, fTempCoeffPerK := fTempCoeffPerK);   // 子函数求解（除零由子函数守卫） / Sub-function call
    IF _fK < 0.0 THEN                                      // 哨兵：时分母或时长非法 / Sentinel from sub-function
        _uFault := 16#0002_0389;
        _eCause := E_DL_SdsCause.eCompDiv;                 // 归因：温补分母非法 / Cause: denominator
        _bFault := TRUE;
    ELSE
        fKMvPerH := _fK;                                   // 速率镜像 / Rate mirror
        _fScaled := _fK * 1000.0;                           // 放大 1000 倍进入整数域 / Scale by thousand
        IF _fScaled >= 2.147483E9 THEN                      // 实数上限兜底（DINT 可表上界） / Real upper guard
            _fScaled := 2.147483E9;
        ELSIF _fScaled <= -2.147483E9 THEN                  // 实数下限兜底 / Real lower guard
            _fScaled := -2.147483E9;
        END_IF
        _iScaled := LREAL_TO_DINT(LREAL(_fScaled));         // 截断取整 / Truncate
        IF LREAL(_iScaled) < LREAL(_fScaled) - 1.0E-9 THEN  // 余量进位（正好整除不进位） / Ceiling by remainder
            _iScaled := _iScaled + 1;
        END_IF
        fKCeilMvPerH := DINT_TO_REAL(_iScaled) * 0.001;     // 还原为 0.001 mV/h 步长 / Restore 0.001 step
        IF fKCeilMvPerH <= fClassAMvPerH THEN
            _eClass := E_DL_SdsClass.eClassA;               // A 级 / Class A
        ELSIF fKCeilMvPerH <= fClassBMvPerH THEN
            _eClass := E_DL_SdsClass.eClassB;               // B 级 / Class B
        ELSIF fKCeilMvPerH <= fClassCMvPerH THEN
            _eClass := E_DL_SdsClass.eClassC;               // C 级 / Class C
        ELSE
            _eClass := E_DL_SdsClass.eReject;               // 不合格（ELSE 兜底） / Rejected fallback
        END_IF
    END_IF
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT _bNonFin —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_SdsCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_SdsState.eFault) THEN
    _eState := E_DL_SdsState.eFault;           // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_SdsState.eIdle:
    IF bEnable AND (NOT _bFault) THEN          // 使能条件 / Enable gate
        _eState := E_DL_SdsState.eRun;         // 进筛分相 / Enter screening
    END_IF

E_DL_SdsState.eRun:
    IF NOT bEnable THEN                        // 撤使能：回未使能（前置消失） / Disable returns idle
        _eState := E_DL_SdsState.eIdle;
    END_IF

E_DL_SdsState.eFault:
    ;                                          // 故障相：仅段 4 复位沿可迁出 / Only reset exits

ELSE
    _uFault := 16#0002_0389;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _eCause := E_DL_SdsCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_SdsState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
IF _bFault THEN
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
    eClass := E_DL_SdsClass.eNone;             // 故障相分级强制未分级 / Grading forced none
    fKCeilMvPerH := 0.0;                       // 故障相取整值强制 0（安全侧） / Ceil forced zero
ELSE
    nErrId := 16#0000_0000;                    // 无故障：本件无信息码 / No fault, no info code
    eClass := _eClass;                         // 分级出口 / Grading outlet
END_IF
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
