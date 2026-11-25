(* ===========================================================================
   组件名   : FB_DL_ResolverFaultDetect
   分类     : DL_Motion / 旋转变压器故障检测
   一句话   : 断线（幅值过低）、短路（幅值过高）、失衡、相位异常四类分级检测与锁存
   复杂度   : 3        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fSin/fCos 两路瞬时值 [V]；fAmpMin/fAmpMax 幅值上下限 [V]
              fImbLimitPct 失衡限值 [%]；fPhaseDiff 实测相位差 [rad]
              fPhaseExpected 期望相位差 [rad]；fPhaseTol 相位容差 [rad]
              tConfirmDelay 故障确认延时；xReset 复位上升沿
   输出契约 : eFaultClass 锁存故障类别；xFault 故障锁存；iFaultCode 分级码
              11/12=一级严重（断线/短路） 21/22=二级（失衡/相位） 99=未分类
              fAmplitude 合成幅值 [V]；fImbalancePct 即时失衡度 [%]；xValid 参数与输入有效
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

TYPE E_DL_ResolverFault :
(
    eNoFault := 0,        // 无故障 | no fault
    eOpenWire := 1,       // 断线（幅值过低） | open wire, low amplitude
    eShortCircuit := 2,   // 短路（幅值过高） | short circuit, high amplitude
    eImbalanceFault := 3, // 两路失衡 | channel imbalance
    ePhaseFault := 4      // 相位异常 | phase anomaly
);
END_TYPE

FUNCTION_BLOCK FB_DL_ResolverFaultDetect
VAR_INPUT
    fSin : REAL;                       // 正弦路瞬时值 [V] | sine channel value [V]
    fCos : REAL;                       // 余弦路瞬时值 [V] | cosine channel value [V]
    fAmpMin : REAL := 0.5;             // 幅值下限（断线判据） [V] | amplitude low limit [V]
    fAmpMax : REAL := 9.0;             // 幅值上限（短路判据） [V] | amplitude high limit [V]
    fImbLimitPct : REAL := 5.0;        // 失衡限值 [%] | imbalance limit [%]
    fPhaseDiff : REAL := 0.0;          // 实测相位差 [rad] | measured phase difference [rad]
    fPhaseExpected : REAL := 0.0;      // 期望相位差 [rad] | expected phase difference [rad]
    fPhaseTol : REAL := 0.2;           // 相位容差 [rad] | phase tolerance [rad]
    tConfirmDelay : TIME := T#100MS;   // 故障确认延时 | fault confirm delay
    xReset : BOOL;                     // 故障复位上升沿 | fault reset rising edge
END_VAR
VAR_OUTPUT
    eFaultClass : E_DL_ResolverFault;  // 锁存故障类别（默认首项=无故障） | latched fault class
    xFault : BOOL;                     // 故障锁存标志 | latched fault flag
    iFaultCode : INT;                  // 分级故障码 0=无故障 | graded fault code
    fAmplitude : REAL;                 // 合成幅值 [V] | resultant amplitude [V]
    fImbalancePct : REAL;              // 即时失衡度 [%] | instantaneous imbalance [%]
    xValid : BOOL;                     // 输入与参数有效 | inputs and parameters valid
END_VAR
VAR
    _eCand : E_DL_ResolverFault := eNoFault;  // 本拍候选故障类别 | candidate fault class
    _fAbsSin : REAL;                   // 正弦绝对值 [V] | absolute sine [V]
    _fAbsCos : REAL;                   // 余弦绝对值 [V] | absolute cosine [V]
    _fMean : REAL;                     // 两路均值 [V] | mean magnitude [V]
    _fPhaseErr : REAL;                 // 相位偏差 [rad] | phase error [rad]
    _xBad : BOOL;                      // 输入非有限标志 | not-finite flag
    _xBadPar : BOOL;                   // 参数非法标志 | invalid parameter flag
    _tonConfirm : TON;                 // 确认延时定时器 | confirm delay timer
    _rtReset : R_TRIG;                 // 复位上升沿 | reset rising edge
END_VAR

// ---- 非有限检测 ----
_xBad := (fSin <> fSin) OR ((fSin - fSin) <> (fSin - fSin))
      OR (fCos <> fCos) OR ((fCos - fCos) <> (fCos - fCos))
      OR (fPhaseDiff <> fPhaseDiff) OR ((fPhaseDiff - fPhaseDiff) <> (fPhaseDiff - fPhaseDiff));

// ---- 参数合法性：上下限必须正向有序，其余限值必须为正 ----
_xBadPar := (fAmpMax <= fAmpMin) OR (fAmpMin < 0.0) OR (fImbLimitPct <= 0.0) OR (fPhaseTol <= 0.0);

// ---- 幅值与失衡度计算 ----
fAmplitude := 0.0;
fImbalancePct := 0.0;
_fAbsSin := 0.0;
_fAbsCos := 0.0;
IF NOT _xBad THEN
    fAmplitude := SQRT(fSin * fSin + fCos * fCos);
    _fAbsSin := ABS(fSin);
    _fAbsCos := ABS(fCos);
    _fMean := (_fAbsSin + _fAbsCos) * 0.5;
    IF _fMean > 0.000000001 THEN
        fImbalancePct := ABS(_fAbsSin - _fAbsCos) / _fMean * 100.0;   // 分母已守卫
    END_IF
END_IF

// ---- 相位偏差卷绕到 (−π, π] ----
_fPhaseErr := fPhaseDiff - fPhaseExpected;
IF _fPhaseErr > 1000000.0 THEN
    _fPhaseErr := 1000000.0;
ELSIF _fPhaseErr < -1000000.0 THEN
    _fPhaseErr := -1000000.0;
END_IF
_fPhaseErr := _fPhaseErr - 6.283185307 * TRUNC(_fPhaseErr / 6.283185307);
IF _fPhaseErr > 3.141592654 THEN
    _fPhaseErr := _fPhaseErr - 6.283185307;
ELSIF _fPhaseErr <= -3.141592654 THEN
    _fPhaseErr := _fPhaseErr + 6.283185307;
END_IF

xValid := NOT (_xBad OR _xBadPar);

// ---- 候选分类：四类判据互斥，且各有独立赋值语句（禁止共用枚举成员） ----
_eCand := eNoFault;
IF xValid THEN
    IF fAmplitude < fAmpMin THEN
        _eCand := eOpenWire;                       // 断线：幅值低于下限
    ELSIF fAmplitude > fAmpMax THEN
        _eCand := eShortCircuit;                   // 短路：幅值高于上限
    ELSIF fImbalancePct > fImbLimitPct THEN
        _eCand := eImbalanceFault;                 // 失衡：两路幅值差超限
    ELSIF ABS(_fPhaseErr) > fPhaseTol THEN
        _eCand := ePhaseFault;                     // 相位：偏差超出容差
    END_IF
END_IF

// ---- 确认延时定时器：无条件每周期调用 ----
_tonConfirm(IN := (_eCand <> eNoFault), PT := tConfirmDelay);
_rtReset(CLK := xReset);

// ---- 故障相回放锁存类别，不按当下输入重新推断 ----
IF xFault THEN
    _eCand := eFaultClass;
END_IF

// ---- 分级映射：一级（断线/短路）与二级（失衡/相位）各有独立码值 ----
iFaultCode := 0;
CASE _eCand OF
    eNoFault:
        iFaultCode := 0;                           // 无故障
    eOpenWire:
        iFaultCode := 11;                          // 一级：断线
    eShortCircuit:
        iFaultCode := 12;                          // 一级：短路
    eImbalanceFault:
        iFaultCode := 21;                          // 二级：失衡
    ePhaseFault:
        iFaultCode := 22;                          // 二级：相位异常
ELSE
    iFaultCode := 99;                              // 非法类别兜底
END_CASE

// ---- 锁存与唯一解除路径 ----
IF _tonConfirm.Q AND NOT xFault THEN
    eFaultClass := _eCand;                         // 锁存首次确认的类别
    xFault := TRUE;
END_IF
IF _rtReset.Q AND NOT xFault THEN
    eFaultClass := eNoFault;                       // 无故障时复位仅做清码
    iFaultCode := 0;
ELSIF _rtReset.Q AND xFault THEN
    xFault := FALSE;                               // 解除路径：复位上升沿
    eFaultClass := eNoFault;
    iFaultCode := 0;
END_IF
END_FUNCTION_BLOCK
