(*
  组件名 Component   : FB_DL_AxisBrakeTest
  子库 Sublibrary    : DL_Motion
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 抱闸制动测试顺控（与 FB_DL_AxisBrakeDistPredict 分工：预测制动
                       距离 vs 周期性制动测试）：
                       1) 测试以上升沿承载：eIdle → eCloseBrake（出抱闸闭合指令）；
                       2) eCloseBrake：等轴零速（|速度| < 近零阈 持续 tZeroWin 确认），
                       超时 tZeroTo 判故障；抱闸反馈缺失判故障；
                       3) eMeasure：位置快照后驻留 tHoldDur，滑移量 = |位置 - 快照|，
                       超过 fSlipLimitMm 判不合格，否则合格；
                       4) eDone：结果驻留至测试指令撤销；到期计数按使能期扫描累计，
                       超过 uTestIntervalScans 置 bTestDue。
  边界 Boundary      : ① 本件只出抱闸闭合指令与测试结论，不驱动运动指令；
                       ② 各相超时用独立 TON 实例（tonZeroTo / tonHoldDur），禁跨相复用；
                       ③ 滑移量除法无（纯差值比较），非有限输入判非法锁存；
                       ④ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ⑤ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : Standard.library（R_TRIG / TON）
  溯源 Origin        : 道莅自研 clean-room（参考 t1-6-plcopen 运动接口分类与参数域，
                       零代码行复制）
  码位 Code          : 16#04_0_AA
  码表 Error codes（Motion 格 04_0_AA，单轨：故障 0x02AA / 信息 0x01AA）:
    16#0004_02AA 故障级：测试非法（零速超时 / 抱闸反馈缺失 / 组态非法 / 输入非有限），
                 锁存至 bReset 上升沿
    16#0004_01AA 信息级：测试结论写定沿（合格或不合格判定拍，bTestPass 同拍定值）
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 2 · 序号 7）
*)

TYPE E_DL_AbtState :
(
    eIdle       := 0,   // 空闲：等测试沿 / Idle, waiting test edge
    eCloseBrake := 10,  // 闭闸：等零速确认 / Closing brake, waiting zero speed
    eMeasure    := 20,  // 测量：驻留计滑移 / Measuring, slip dwell
    eDone       := 30,  // 完成：结论驻留 / Done, verdict held
    eFault      := 90   // 故障：测试非法锁存 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisBrakeTest
VAR_INPUT
    bEnable        : BOOL;               // 使能（电平），使能期累计到期计数 [-] / Enable
    bReset         : BOOL;               // 上升沿清故障锁存 [-] / Reset edge
    bTestCmd       : BOOL;               // 测试指令（上升沿承载）[-] / Test command edge
    fVelMmS        : REAL;               // 轴实际速度 [mm/s] / Axis velocity
    fPosMm         : REAL;               // 轴实际位置 [mm] / Axis position
    bBrakeFb       : BOOL;               // 抱闸闭合反馈 [-] / Brake closed feedback
    fVelNearZeroMmS: REAL := 0.5;        // 零速判据阈 [mm/s] / Near-zero velocity threshold
    fSlipLimitMm   : REAL := 0.1;        // 滑移量合格限 [mm] / Slip pass limit
    tZeroWin       : TIME := T#500MS;    // 零速确认窗 [毫秒] / Zero-speed confirm window
    tZeroTo        : TIME := T#10S;      // 闭闸零速超时 [毫秒] / Zero-speed timeout
    tHoldDur       : TIME := T#5S;       // 滑移测量驻留 [毫秒] / Slip measurement dwell
    uTestIntervalScans: UDINT := 8640000;// 定期测试到期计数 [拍] / Test due interval in scans
END_VAR
VAR_OUTPUT
    bBrakeCmdOut   : BOOL;               // 抱闸闭合指令输出 [-] / Brake close command
    bTestBusy      : BOOL;               // 测试进行中电平 [-] / Test busy level
    bTestPass      : BOOL;               // 结论：TRUE = 合格 [-] / Verdict pass flag
    bTestDue       : BOOL;               // 定期测试到期标志 [-] / Test due flag
    fSlipMm        : REAL;               // 实测滑移量 [mm] / Measured slip
    uScansSinceTest: UDINT;              // 距上次测试扫描累计 [拍] / Scans since last test
    eState         : E_DL_AbtState;      // 状态出口，段尾单点映射 / State outlet
    bError         : BOOL;               // 故障锁存标志 [-] / Fault latch flag
    uErrId         : UDINT;              // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset  : R_TRIG;                   // 复位沿实例，段 0 无条件刷新 / Reset edge
    rtTest   : R_TRIG;                   // 测试沿实例，段 0 无条件刷新 / Test edge
    tonZeroWin: TON;                     // 零速确认窗 / Zero-speed confirm timer
    tonZeroTo : TON;                     // 闭闸超时（专用超时件命名） / Zero-speed timeout
    tonHoldDur: TON;                     // 测量驻留计时 / Measurement dwell timer
    _eState  : E_DL_AbtState := E_DL_AbtState.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _fPosSnap: REAL;                     // 测量起点位置快照 [mm] / Position snapshot
    _bFault  : BOOL;                     // 故障锁存位（锁存量） / Latched fault bit
    _uFault  : UDINT;                    // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad : BOOL;                     // 组态非法当拍量 [-] / Config illegal flag
    _bNonFin : BOOL;                     // 输入非有限当拍量 [-] / Non-finite input flag
END_VAR
VAR CONSTANT
    DL_ABS_MAX : REAL := 1.0E30;         // 有限值判定上界 [工程单位] / Finite bound
    DL_ZERO    : REAL := 0.0;            // 零常量 [mm] / Zero constant
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);
rtTest (CLK := bTestCmd);
tonZeroWin (IN := (_eState = E_DL_AbtState.eCloseBrake) AND (ABS(fVelMmS) < fVelNearZeroMmS)
             AND (NOT _bFault), PT := tZeroWin);
tonZeroTo  (IN := (_eState = E_DL_AbtState.eCloseBrake) AND (NOT _bFault), PT := tZeroTo);
tonHoldDur (IN := (_eState = E_DL_AbtState.eMeasure) AND (NOT _bFault), PT := tHoldDur);

(* —— 段 1｜瞬时量预清零（锁存量 _bFault/_uFault/bTestPass/_fPosSnap 不入清单） —— *)
uErrId   := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲，抱闸指令撤销 —— *)
IF rtReset.Q THEN
    _bFault  := FALSE;
    _uFault  := 16#0000_0000;
    bBrakeCmdOut := FALSE;
    _eState  := E_DL_AbtState.eIdle;
END_IF

(* —— 段 3｜组态闸与非有限判据 —— *)
IF (fVelNearZeroMmS <= DL_ZERO) OR (fSlipLimitMm <= DL_ZERO) OR (tZeroWin = T#0S)
   OR (tZeroTo = T#0S) OR (tHoldDur = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
IF (fVelMmS <> fVelMmS) OR ((fVelMmS - fVelMmS) <> DL_ZERO)
   OR (fPosMm <> fPosMm) OR ((fPosMm - fPosMm) <> DL_ZERO) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜到期计数：使能期每拍累计，超限置到期标志 —— *)
IF bEnable AND (NOT _bFault) THEN
    uScansSinceTest := uScansSinceTest + UDINT#1;
    IF uScansSinceTest >= uTestIntervalScans THEN
        bTestDue := TRUE;
    END_IF
END_IF

(* —— 段 5｜主状态机：五态全覆盖 + ELSE 兜底 —— *)
CASE _eState OF

E_DL_AbtState.eIdle:
    bBrakeCmdOut := FALSE;
    bTestBusy    := FALSE;
    IF _bFault THEN
        bError := TRUE;                  // 故障锁存回放（R189）
    END_IF
    IF rtTest.Q AND bEnable AND (NOT _bFault) AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
        uScansSinceTest := UDINT#0;      // 新测试起点：到期计数清零
        bTestDue := FALSE;
        bBrakeCmdOut := TRUE;            // 出抱闸闭合指令
        bTestBusy := TRUE;
        _eState := E_DL_AbtState.eCloseBrake;
    ELSIF rtTest.Q AND (_bCfgBad OR _bNonFin OR _bFault) THEN
        _bFault := TRUE;                 // 带病启动拒绝
        _uFault := 16#0004_02AA;
        bError  := TRUE;
        _eState := E_DL_AbtState.eFault;
    END_IF

E_DL_AbtState.eCloseBrake:
    bBrakeCmdOut := TRUE;
    bTestBusy := TRUE;
    IF _bNonFin THEN
        _bFault := TRUE;                 // 输入非有限：判据不可信
        _uFault := 16#0004_02AA;
        bError  := TRUE;
        _eState := E_DL_AbtState.eFault;
    ELSIF NOT bBrakeFb THEN
        _bFault := TRUE;                 // 抱闸反馈缺失：指令已出而反馈不到
        _uFault := 16#0004_02AA;
        bError  := TRUE;
        _eState := E_DL_AbtState.eFault;
    ELSIF tonZeroWin.Q THEN
        _fPosSnap := fPosMm;             // 零速确认：取滑移测量起点快照
        _eState := E_DL_AbtState.eMeasure;   // 迁出条件 1：零速达成
    ELSIF tonZeroTo.Q THEN
        _bFault := TRUE;                 // 迁出条件 2（故障路）：零速超时
        _uFault := 16#0004_02AA;
        bError  := TRUE;
        _eState := E_DL_AbtState.eFault;
    END_IF

E_DL_AbtState.eMeasure:
    bBrakeCmdOut := TRUE;
    bTestBusy := TRUE;
    IF tonHoldDur.Q THEN
        fSlipMm := ABS(fPosMm - _fPosSnap);  // 滑移量 = 驻留期位置漂移
        bTestPass := fSlipMm <= fSlipLimitMm;
        uErrId := 16#0004_01AA;          // 信息级：结论写定沿（锁存至复位）
        _eState := E_DL_AbtState.eDone;
    END_IF

E_DL_AbtState.eDone:
    bBrakeCmdOut := FALSE;               // 测试结束：抱闸指令撤销
    bTestBusy := FALSE;
    IF NOT bTestCmd THEN
        _eState := E_DL_AbtState.eIdle;  // 测试指令撤销：回空闲（结论锁存保留）
    END_IF

E_DL_AbtState.eFault:
    bBrakeCmdOut := FALSE;               // 故障相：抱闸指令安全侧撤销
    bTestBusy := FALSE;
    bError := TRUE;
    ;                                    // 故障相驻留：只认复位沿（段 2 迁出）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0004_02AA;
    bError  := TRUE;
    _eState := E_DL_AbtState.eFault;
END_CASE

(* —— 段 6｜状态出口单点映射 —— *)
eState := _eState;
END_FUNCTION_BLOCK
