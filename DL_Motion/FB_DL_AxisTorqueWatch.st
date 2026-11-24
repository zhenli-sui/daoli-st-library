(*
  组件名 Component   : FB_DL_AxisTorqueWatch
  子库 Sublibrary    : DL_Motion
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 轴转矩趋势监视（与 FB_DL_TorqueLimitControl 分工：控 vs 监）：
                       1) 带域判据：转矩超上带限持续 tConfirmWin → 预警（bWarn）；
                       2) 趋势斜率判据：周期窗（tSlopeWin 自复触）两端采样，斜率
                       fSlopeNmS = (本端 - 上端) / 窗长，斜率超限 → 预警；
                       3) 堵转分级：转矩超上带限 且 轴速近零 持续 tStallTo → bStall；
                       4) 三判据各带独立确认窗，互不共用计时实例（R190 归因唯一）。
  边界 Boundary      : ① 监视件只出分级诊断位，不接管转矩控制输出；
                       ② 周期窗计时用 IN := bEnable AND NOT tonSlopeWin.Q 自复触
                       （R188 错峰周期窗范式，禁外部沿清零）；
                       ③ 斜率除法前置域闸：tSlopeWin <= T#0S 判组态非法；
                       ④ 非有限值（NaN 自反 + 无穷差值自减）判输入非法锁存；
                       ⑤ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ⑥ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : Standard.library（R_TRIG / TON）
  溯源 Origin        : 道莅自研 clean-room（参考 t2-4-s7-motion 监视分类与参数域，
                       零代码行复制）
  码位 Code          : 16#04_0_A9
  码表 Error codes（Motion 格 04_0_A9，单轨：故障 0x02A9 / 信息 0x01A9 / 0x03A9）:
    16#0004_02A9 故障级：组态非法或输入非有限，锁存至 bReset 上升沿
    16#0004_01A9 信息级：预警进入沿（bWarn 由 FALSE 转 TRUE 拍）
    16#0004_05A9 信息级：堵转检出沿（bStall 由 FALSE 转 TRUE 拍；子道 05 为 03 道撞车顺延勘误）
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 2 · 序号 6）
*)

TYPE E_DL_AtwState :
(
    eIdle  := 0,    // 空闲：未使能 / Idle, not enabled
    eRun   := 10,   // 监视运行：三判据并行 / Running, three criteria active
    eFault := 90    // 故障：组态/输入锁存 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisTorqueWatch
VAR_INPUT
    bEnable    : BOOL;                     // 使能（电平）[-] / Enable
    bReset     : BOOL;                     // 上升沿清故障锁存 [-] / Reset edge
    fTorqueNm  : REAL;                     // 实测转矩 [牛·米] / Measured torque
    fVelMmS    : REAL;                     // 轴实际速度 [mm/s] / Axis velocity
    fBandHiNm  : REAL := 10.0;             // 转矩上带限 [牛·米] / Torque band ceiling
    fBandLoNm  : REAL := 1.0;              // 转矩下带限 [牛·米] / Torque band floor
    fSlopeLimNmS: REAL := 5.0;             // 趋势斜率限值 [牛·米/秒] / Trend slope limit
    fVelNearZeroMmS: REAL := 0.5;          // 堵转判近零速度阈 [mm/s] / Near-zero velocity threshold
    tConfirmWin: TIME := T#2S;             // 带域预警确认窗 [毫秒] / Band confirm window
    tSlopeWin  : TIME := T#1S;             // 趋势斜率测量窗 [毫秒] / Slope measurement window
    tStallTo   : TIME := T#3S;             // 堵转确认窗 [毫秒] / Stall confirm window
END_VAR
VAR_OUTPUT
    bInBand    : BOOL;                     // 转矩在带内电平 [-] / Torque in-band level
    bWarn      : BOOL;                     // 预警电平（带域或斜率越限确认后）[-] / Warning level
    bStall     : BOOL;                     // 堵转电平 [-] / Stall level
    fSlopeNmS  : REAL;                     // 实测趋势斜率 [牛·米/秒] / Measured slope
    eState     : E_DL_AtwState;            // 状态出口，段尾单点映射 / State outlet
    bError     : BOOL;                     // 故障锁存标志 [-] / Fault latch flag
    uErrId     : UDINT;                    // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset    : R_TRIG;                   // 复位沿实例，段 0 无条件刷新 / Reset edge
    rtWarn     : R_TRIG;                   // 预警进入沿实例，段 0 无条件刷新 / Warn entry edge
    rtStall    : R_TRIG;                   // 堵转进入沿实例，段 0 无条件刷新 / Stall entry edge
    tonBandWin : TON;                      // 带域确认窗（专用确认窗命名） / Band confirm timer
    tonStallTo : TON;                      // 堵转确认窗（专用超时件命名（R228A 豁免）） / Stall timer
    tonSlopeWin: TON;                      // 斜率周期窗（自复触，R188） / Slope window timer
    _eState    : E_DL_AtwState := E_DL_AtwState.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bBandHi   : BOOL;                     // 带域越限当拍量 [-] / Band breach flag
    _bStallCond: BOOL;                     // 堵转条件当拍量 [-] / Stall condition flag
    _fTorqueSnap: REAL;                    // 窗始转矩快照 [牛·米] / Window-start torque snapshot
    _bSnapPend : BOOL;                     // 快照待取标志 [-] / Snapshot pending flag
    _bFault    : BOOL;                     // 故障锁存位（锁存量） / Latched fault bit
    _uFault    : UDINT;                    // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad   : BOOL;                     // 组态非法当拍量 [-] / Config illegal flag
    _bNonFin   : BOOL;                     // 输入非有限当拍量 [-] / Non-finite input flag
END_VAR
VAR CONSTANT
    DL_SLOPE_EPS: REAL := 1.0E-9;          // 斜率判零容差 [牛·米/秒] / Slope tolerance
    DL_WIN_EPS  : REAL := 1.0E-3;          // 窗长秒值下限 [秒] / Window seconds floor
    DL_ABS_MAX  : REAL := 1.0E30;          // 有限值判定上界 [工程单位] / Finite bound
    DL_ZERO     : REAL := 0.0;             // 零常量 [工程单位] / Zero constant
    DL_MS_PER_S : REAL := 1000.0;          // 毫秒 → 秒换算系数 [毫秒/秒] / Milliseconds per second
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内） —— *)
_bBandHi    := (fTorqueNm > fBandHiNm) OR (fTorqueNm < fBandLoNm);   // 带域越限当拍判据
_bStallCond := (fTorqueNm > fBandHiNm) AND (ABS(fVelMmS) < fVelNearZeroMmS);
rtReset    (CLK := bReset);
rtWarn     (CLK := bWarn);
rtStall    (CLK := bStall);
tonBandWin (IN := (_eState = E_DL_AtwState.eRun) AND _bBandHi AND (NOT _bFault), PT := tConfirmWin);
tonStallTo (IN := (_eState = E_DL_AtwState.eRun) AND _bStallCond AND (NOT _bFault), PT := tStallTo);
tonSlopeWin(IN := (_eState = E_DL_AtwState.eRun) AND (NOT _bFault) AND (NOT tonSlopeWin.Q),
            PT := tSlopeWin);            // 自复触周期窗：Q 拍断开一拍，下拍重启（R188）

(* —— 段 1｜瞬时量预清零（锁存量 _bFault/_uFault/bWarn/bStall/_fTorqueSnap 不入清单） —— *)
uErrId   := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲，诊断位复归 —— *)
IF rtReset.Q THEN
    _bFault  := FALSE;
    _uFault  := 16#0000_0000;
    bWarn    := FALSE;
    bStall   := FALSE;
    fSlopeNmS:= DL_ZERO;
    _eState  := E_DL_AtwState.eIdle;
END_IF

(* —— 段 3｜组态闸与非有限判据 —— *)
IF (fBandHiNm <= fBandLoNm) OR (tConfirmWin = T#0S) OR (tSlopeWin = T#0S)
   OR (tStallTo = T#0S) OR (fVelNearZeroMmS <= DL_ZERO) THEN
    _bCfgBad := TRUE;
END_IF
IF (fTorqueNm <> fTorqueNm) OR ((fTorqueNm - fTorqueNm) <> DL_ZERO)
   OR (fVelMmS <> fVelMmS) OR ((fVelMmS - fVelMmS) <> DL_ZERO) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜主状态机：三态全覆盖 + ELSE 兜底 —— *)
CASE _eState OF

E_DL_AtwState.eIdle:
    bInBand := FALSE;
    IF bEnable AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
        _fTorqueSnap := fTorqueNm;       // 窗始快照初始化
        _bSnapPend   := FALSE;
        _eState := E_DL_AtwState.eRun;
    ELSIF bEnable AND (_bCfgBad OR _bNonFin) THEN
        _bFault := TRUE;
        _uFault := 16#0004_02A9;
        bError  := TRUE;
        _eState := E_DL_AtwState.eFault;
    END_IF

E_DL_AtwState.eRun:
    IF NOT bEnable THEN
        bInBand := FALSE;
        bWarn   := FALSE;
        bStall  := FALSE;
        _eState := E_DL_AtwState.eIdle;  // 使能撤销回空闲
    ELSE
        bInBand := NOT _bBandHi;
        (* 斜率测量：Q 拍收口，快照按窗复归（除数 = 窗长秒值，组态闸已保证 > 0） *)
        IF tonSlopeWin.Q THEN
            IF NOT _bSnapPend THEN
                fSlopeNmS := (fTorqueNm - _fTorqueSnap)
                             / MAX(TIME_TO_REAL(tSlopeWin) / DL_MS_PER_S, DL_WIN_EPS);
                IF ABS(fSlopeNmS) < DL_SLOPE_EPS THEN
                    fSlopeNmS := DL_ZERO;    // 斜率近零归零
                END_IF
                _bSnapPend := TRUE;
            END_IF
            _fTorqueSnap := fTorqueNm;
            _bSnapPend   := FALSE;
        END_IF
        (* 分级判据：带域或斜率任一确认 → 预警；带域 + 近零速度确认 → 堵转 *)
        IF _bNonFin THEN
            _bFault := TRUE;             // 输入非有限：运行中锁存
            _uFault := 16#0004_02A9;
            bError  := TRUE;
            bWarn   := FALSE;
            bStall  := FALSE;
            _eState := E_DL_AtwState.eFault;
        ELSE
            bWarn := (NOT _bFault) AND (tonBandWin.Q OR (ABS(fSlopeNmS) > fSlopeLimNmS));
            bStall := (NOT _bFault) AND tonStallTo.Q;
            IF rtWarn.Q THEN
                uErrId := 16#0004_01A9;  // 信息级：预警进入沿
            END_IF
            IF rtStall.Q THEN
                uErrId := 16#0004_05A9;  // 信息级：堵转检出沿（子道 05 勘误顺延）
            END_IF
        END_IF
    END_IF

E_DL_AtwState.eFault:
    bError := TRUE;                      // 故障相驻留：诊断位冻结，只认复位沿（段 2 迁出）
    ;                                    // （冻结语义：bWarn/bStall 保持复位沿前值由段 2 归零）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0004_02A9;
    bError  := TRUE;
    _eState := E_DL_AtwState.eFault;
END_CASE

(* —— 段 5｜状态出口单点映射 —— *)
eState := _eState;
END_FUNCTION_BLOCK
