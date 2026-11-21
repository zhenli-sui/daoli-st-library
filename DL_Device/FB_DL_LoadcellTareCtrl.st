(*
  组件名 Component   : FB_DL_LoadcellTareCtrl
  子库 Sublibrary    : DL_Device
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 称重传感器去皮/标定管理：
                       1) 去皮锁存：bTareCmd 上升沿把当下毛重读数锁存为皮重，
                       净重 = 毛重 - 皮重（锁存量，不随后续漂移）；
                       2) 两点标定：bCalCmd 上升沿按两点已知质量与其原始读数解算
                       斜率/截距（读数跨度近零前置拦截，不进入除法）；
                       3) 标定超期计数：使能期扫描累计，超过 uCalIntervalScans 置
                       bCalDue（维护提示，信息级语义，不置 bError）；
                       4) 非有限读数判输入非法，净重出口冻结保持（安全侧）。
  边界 Boundary      : ① 本件只做称重管理，不写物理 IO（原始读数由上层适配层传入）；
                       ② 皮重/标定系数均为锁存回放，禁按当下输入重推断（R152）；
                       ③ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ④ Device 件无 NE107 出口（去皮/标定为维护工序件，非诊断件）；
                       ⑤ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : Standard.library（R_TRIG）
  溯源 Origin        : 道莅自研 clean-room（参考 t2-6-rockwell-aoi 设备级粒度分类与
                       参数域，零代码行复制）
  码位 Code          : 16#03_2_E（Device 05xx 副带 052E）
  码表 Error codes（Device 故障窗口 052E，本件无信息码，单故障总码 + 成因枚举归因）:
    16#0003_052E 故障级：称重管理故障总码（标定读数跨度近零 / 皮重超量程 /
                 组态非法 / 输入非有限），锁存至 bReset 上升沿，归因见 eCause
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 2 · 序号 10）
*)

TYPE E_DL_LtcState :
(
    eIdle  := 0,    // 空闲：未使能 / Idle, not enabled
    eRun   := 10,   // 运行：去皮/标定/净重合成 / Running, tare, calibrate and net
    eFault := 90    // 故障：总码锁存 / Fault, latched
);
END_TYPE

TYPE E_DL_LtcCause :
(
    eNone      := 0,  // 无故障成因 / No cause
    eCalSpan   := 1,  // 标定读数跨度近零 / Calibration span near zero
    eTareRange := 2,  // 皮重超量程（皮重 >= 满量程） / Tare beyond capacity
    eCfgIllegal:= 3,  // 组态非法 / Illegal configuration
    eNonFinite := 4   // 输入非有限 / Non-finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_LoadcellTareCtrl
VAR_INPUT
    bEnable    : BOOL;                     // 使能（电平）[-] / Enable
    bReset     : BOOL;                     // 上升沿清故障锁存 [-] / Reset edge
    bTareCmd   : BOOL;                     // 去皮指令（上升沿承载）[-] / Tare command edge
    bCalCmd    : BOOL;                     // 标定指令（上升沿承载）[-] / Calibrate command edge
    fGrossG    : REAL;                     // 毛重读数 [克] / Gross reading
    fCalMassLoG: REAL;                     // 标定点 1 已知质量 [克] / Calibration mass 1
    fCalMassHiG: REAL;                     // 标定点 2 已知质量 [克] / Calibration mass 2
    fRawLo     : REAL;                     // 标定点 1 原始读数 [克] / Calibration raw 1
    fRawHi     : REAL;                     // 标定点 2 原始读数 [克] / Calibration raw 2
    fCapacityG : REAL := 10000.0;          // 传感器满量程 [克] / Sensor capacity
    uCalIntervalScans: UDINT := 8640000;  // 标定超期计数限 [拍] / Calibration due interval
END_VAR
VAR_OUTPUT
    fNetG      : REAL;                     // 净重输出 [克] / Net weight output
    fTareG     : REAL;                     // 锁存皮重 [克] / Latched tare weight
    fSlope     : REAL;                     // 标定斜率 [克/克读数] / Calibration slope
    fOffset    : REAL;                     // 标定截距 [克] / Calibration offset
    bTared     : BOOL;                     // 已去皮标志 [-] / Tared flag
    bCalOk     : BOOL;                     // 标定有效标志 [-] / Calibration valid flag
    bCalDue    : BOOL;                     // 标定超期标志 [-] / Calibration due flag
    uScansSinceCal: UDINT;                 // 距上次标定扫描累计 [拍] / Scans since calibration
    eState     : E_DL_LtcState;            // 状态出口，段尾单点映射 / State outlet
    eCause     : E_DL_LtcCause;            // 故障成因出口（R190） / Fault cause outlet
    bError     : BOOL;                     // 故障锁存标志 [-] / Fault latch flag
    uErrId     : UDINT;                    // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset: R_TRIG;                       // 复位沿实例，段 0 无条件刷新 / Reset edge
    rtTare : R_TRIG;                       // 去皮沿实例，段 0 无条件刷新 / Tare edge
    rtCal  : R_TRIG;                       // 标定沿实例，段 0 无条件刷新 / Calibrate edge
    _eState: E_DL_LtcState := E_DL_LtcState.eIdle;     // 内部相位（CASE 唯一写入目标）/ Internal phase
    _eCause: E_DL_LtcCause := E_DL_LtcCause.eNone;     // 故障成因锁存（锁存量）/ Latched cause
    _bFault: BOOL;                         // 故障锁存位（锁存量） / Latched fault bit
    _uFault: UDINT;                        // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad: BOOL;                        // 组态非法当拍量 [-] / Config illegal flag
    _bNonFin: BOOL;                        // 输入非有限当拍量 [-] / Non-finite input flag
    _bNetFin: BOOL;                        // 净重合成非有限当拍量 [-] / Net synthesis non-finite flag
    _fNetNew: REAL;                        // 净重合成暂存 [克]（过闸后才提交出口）/ Net synthesis temp
END_VAR
VAR CONSTANT
    DL_SPAN_EPS : REAL := 1.0E-6;          // 标定跨度近零判据 [克] / Span near-zero tolerance
    DL_ABS_MAX  : REAL := 1.0E30;          // 有限值判定上界 [克] / Finite bound
    DL_ZERO     : REAL := 0.0;             // 零常量 [克] / Zero constant
END_VAR

(* —— 段 0｜沿实例每拍无条件刷新（禁置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);
rtTare (CLK := bTareCmd);
rtCal  (CLK := bCalCmd);

(* —— 段 1｜瞬时量预清零（锁存量 _bFault/_uFault/fTareG/fSlope/fOffset 不入清单） —— *)
uErrId   := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;
_bNetFin := FALSE;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    _eCause := E_DL_LtcCause.eNone;
    _eState := E_DL_LtcState.eIdle;
END_IF

(* —— 段 3｜组态闸与非有限判据 —— *)
IF (fCapacityG <= DL_ZERO) OR (uCalIntervalScans = UDINT#0) THEN
    _bCfgBad := TRUE;
END_IF
IF (fGrossG <> fGrossG) OR ((fGrossG - fGrossG) <> DL_ZERO) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜标定超期计数：使能期累计，超限置到期（信息级语义，不置 bError） —— *)
IF bEnable AND (NOT _bFault) THEN
    uScansSinceCal := uScansSinceCal + UDINT#1;
    IF uScansSinceCal >= uCalIntervalScans THEN
        bCalDue := TRUE;
    END_IF
END_IF

(* —— 段 5｜主状态机：三态全覆盖 + ELSE 兜底 —— *)
CASE _eState OF

E_DL_LtcState.eIdle:
    IF bEnable AND (NOT _bCfgBad) THEN
        _eState := E_DL_LtcState.eRun;
    ELSIF bEnable AND _bCfgBad THEN
        _bFault := TRUE;                 // 故障级配对置位（R45）
        _uFault := 16#0003_052E;
        _eCause := E_DL_LtcCause.eCfgIllegal;
        bError  := TRUE;
        _eState := E_DL_LtcState.eFault;
    END_IF

E_DL_LtcState.eRun:
    IF NOT bEnable THEN
        _eState := E_DL_LtcState.eIdle;  // 使能撤销回空闲，皮重与标定系数保持
    ELSE
        IF _bNonFin THEN
            _bFault := TRUE;             // 读数非有限：锁存，净重出口冻结保持
            _uFault := 16#0003_052E;
            _eCause := E_DL_LtcCause.eNonFinite;
            bError  := TRUE;
            _eState := E_DL_LtcState.eFault;
        ELSE
            (* 净重合成：已标定走斜率/截距链，未标定直通毛皮差；暂存过闸后才提交 *)
            IF bCalOk THEN
                _fNetNew := fSlope * fGrossG + fOffset - fTareG;
            ELSE
                _fNetNew := fGrossG - fTareG;
            END_IF
            _bNetFin := (_fNetNew <> _fNetNew) OR ((_fNetNew - _fNetNew) <> DL_ZERO)
                        OR (ABS(_fNetNew) > DL_ABS_MAX);
            IF _bNetFin THEN
                _bFault := TRUE;         // 合成结果越域/非有限：锁存，出口保持上拍值
                _uFault := 16#0003_052E;
                _eCause := E_DL_LtcCause.eNonFinite;
                bError  := TRUE;
                _eState := E_DL_LtcState.eFault;
            ELSE
                fNetG := _fNetNew;       // 过闸提交（出口单点写）
            END_IF
            (* 去皮沿：锁存当下净重前毛重为皮重，皮重超量程判非法 *)
            IF rtTare.Q AND (NOT _bFault) THEN
                IF fGrossG >= fCapacityG THEN
                    _bFault := TRUE;
                    _uFault := 16#0003_052E;
                    _eCause := E_DL_LtcCause.eTareRange;
                    bError  := TRUE;
                    _eState := E_DL_LtcState.eFault;
                ELSE
                    fTareG := fGrossG;
                    bTared := TRUE;
                END_IF
            END_IF
            (* 标定沿：两点跨度近零拦截后解算斜率/截距，标定计数清零 *)
            IF rtCal.Q AND (NOT _bFault) THEN
                IF ABS(fRawHi - fRawLo) <= DL_SPAN_EPS THEN
                    _bFault := TRUE;     // 跨度近零：斜率无意义
                    _uFault := 16#0003_052E;
                    _eCause := E_DL_LtcCause.eCalSpan;
                    bError  := TRUE;
                    _eState := E_DL_LtcState.eFault;
                ELSE
                    fSlope := (fCalMassHiG - fCalMassLoG) / (fRawHi - fRawLo);
                    fOffset := fCalMassLoG - fSlope * fRawLo;
                    bCalOk := TRUE;
                    uScansSinceCal := UDINT#0;
                    bCalDue := FALSE;
                END_IF
            END_IF
        END_IF
    END_IF

E_DL_LtcState.eFault:
    bError := TRUE;                      // 故障相驻留：净重冻结保持，只认复位沿（段 2 迁出）
    ;                                    // （冻结语义：fNetG 保持故障前值，不静默归零）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0003_052E;
    _eCause := E_DL_LtcCause.eCfgIllegal;
    bError  := TRUE;
    _eState := E_DL_LtcState.eFault;
END_CASE

(* —— 段 6｜状态出口单点映射（名实同源） —— *)
eState := _eState;
END_FUNCTION_BLOCK
