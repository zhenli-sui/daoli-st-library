(*
  组件名 Component   : FB_DL_ValvePartialStrokeTest
  子库 Sublibrary    : DL_Device
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 安全阀部分行程测试 PST 顺控：
                       1) 测试许可联锁：bProcessPermissive 为测试前置硬闸，许可撤销
                       即中止测试并锁存（过程条件优先于测试）；
                       2) 测试行程限幅：测试目标位钳制在 [fTestLoPct, fTestHiPct]
                       测试带内，钳位后照常执行（行程受限是 PST 的安全本意）；
                       3) 顺控：eIdle → eCheck（许可与组态闸）→ eMove（开阀到测试
                       目标位）→ eReturn（回正常位）→ eDone，各相超时独立 TON；
                       4) 测试结果判级：行程到位差 <= fTravelTolPct → 合格；短行程
                       超容差 → 降级（NE107 需要维护）；完全不动 → 失效。
                       NE107 健康出口引用唯一属主 E_DL_Ne107Status（零重声明）。
  边界 Boundary      : ① 本件只出阀位指令与健康等级，不写物理 IO；
                       ② NE107 枚举全库唯一属主在 DL_Device（DeviceHealthArbiter 文件），
                       本件只引用；eFailure 与故障锁存配对，bReset 上升沿解除；
                       ③ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ④ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : E_DL_Ne107Status（DL_Device 唯一属主）；Standard.library（R_TRIG / TON）
  溯源 Origin        : 道莅自研 clean-room（参考 t2-8-ne107/ISA PST 语义分类与参数域，
                       零代码行复制；健康出口仅引用唯一属主枚举）
  码位 Code          : 16#03_2_F（Device 05xx 副带 052F）
  码表 Error codes（Device 故障窗口 052F，本件无信息码，单故障总码 + 成因枚举归因）:
    16#0003_052F 故障级：PST 故障总码（许可撤销 / 目标位超时 / 回位超时 /
                 组态非法 / 输入非有限），锁存至 bReset 上升沿，归因见 eCause
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 3 · 序号 11）
*)

TYPE E_DL_PstState :
(
    eIdle   := 0,   // 空闲：等测试沿 / Idle, waiting test edge
    eCheck  := 10,  // 检查：许可与组态闸 / Checking permissive and configuration
    eMove   := 20,  // 行程：开阀至测试目标位 / Moving to test target position
    eReturn := 30,  // 回程：回正常位 / Returning to normal position
    eDone   := 40,  // 完成：判级驻留 / Done, grading held
    eFault  := 90   // 故障：PST 锁存 / Fault, latched
);
END_TYPE

TYPE E_DL_PstCause :
(
    eNone       := 0,  // 无故障成因 / No cause
    ePermissive := 1,  // 测试许可撤销 / Test permissive lost
    eMoveTo     := 2,  // 目标位超时未到位 / Move target timeout
    eReturnTo   := 3,  // 回位超时未到位 / Return timeout
    eCfgIllegal := 4,  // 组态非法 / Illegal configuration
    eNonFinite  := 5   // 输入非有限 / Non-finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_ValvePartialStrokeTest
VAR_INPUT
    bEnable        : BOOL;               // 使能（电平）[-] / Enable
    bReset         : BOOL;               // 上升沿清故障锁存 [-] / Reset edge
    bTestCmd       : BOOL;               // 测试指令（上升沿承载）[-] / Test command edge
    bProcessPermissive: BOOL;            // 过程测试许可（硬联锁）[-] / Process test permissive
    fActPosPct     : REAL;               // 阀实际位置 [%] / Valve actual position
    fTestTargetPct : REAL;               // 测试目标位（会被钳入测试带）[%] / Test target position
    fNormalPosPct  : REAL := 0.0;        // 正常工作位 [%] / Normal operating position
    fTestLoPct     : REAL := 10.0;       // 测试带下限 [%] / Test band floor
    fTestHiPct     : REAL := 30.0;       // 测试带上限 [%] / Test band ceiling
    fTravelTolPct  : REAL := 2.0;        // 行程到位容差 [%] / Travel tolerance
    tMoveTo        : TIME := T#30S;      // 行程超时 [毫秒] / Move timeout
    tReturnTo      : TIME := T#30S;      // 回程超时 [毫秒] / Return timeout
END_VAR
VAR_OUTPUT
    fValveCmdPct   : REAL;               // 阀位指令输出 [%] / Valve position command
    bTestActive    : BOOL;               // 测试进行中电平 [-] / Test active level
    bTestPass      : BOOL;               // 结论：合格 [-] / Verdict pass flag
    bTestDerated   : BOOL;               // 结论：降级（短行程）[-] / Verdict derated flag
    fTestTravelPct : REAL;               // 实测测试行程 [%] / Measured test travel
    eNe107         : E_DL_Ne107Status;   // NE107 健康出口（唯一属主枚举） / NE107 health outlet
    eState         : E_DL_PstState;      // 状态出口，段尾单点映射 / State outlet
    eCause         : E_DL_PstCause;      // 故障成因出口（R190） / Fault cause outlet
    bError         : BOOL;               // 故障锁存标志 [-] / Fault latch flag
    uErrId         : UDINT;              // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset: R_TRIG;                     // 复位沿实例，段 0 无条件刷新 / Reset edge
    rtTest : R_TRIG;                     // 测试沿实例，段 0 无条件刷新 / Test edge
    tonMoveTo : TON;                     // 行程超时（专用超时件命名） / Move timeout
    tonReturnTo: TON;                    // 回程超时（专用超时件命名） / Return timeout
    _eState: E_DL_PstState := E_DL_PstState.eIdle;     // 内部相位（CASE 唯一写入目标）/ Internal phase
    _eCause: E_DL_PstCause := E_DL_PstCause.eNone;     // 故障成因锁存（锁存量）/ Latched cause
    _fTargetUse: REAL;                   // 钳位后测试目标位 [%] / Clamped test target
    _fPosStart : REAL;                   // 测试起点位置 [%] / Test start position
    _bFault: BOOL;                       // 故障锁存位（锁存量） / Latched fault bit
    _uFault: UDINT;                      // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad: BOOL;                      // 组态非法当拍量 [-] / Config illegal flag
    _bNonFin: BOOL;                      // 输入非有限当拍量 [-] / Non-finite input flag
    _bInPos: BOOL;                       // 到位当拍量 [-] / In-position flag
END_VAR
VAR CONSTANT
    DL_ABS_MAX : REAL := 1.0E30;         // 有限值判定上界 [%] / Finite bound
    DL_ZERO    : REAL := 0.0;            // 零常量 [%] / Zero constant
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);
rtTest (CLK := bTestCmd);
tonMoveTo  (IN := (_eState = E_DL_PstState.eMove) AND (NOT _bFault), PT := tMoveTo);
tonReturnTo(IN := (_eState = E_DL_PstState.eReturn) AND (NOT _bFault), PT := tReturnTo);

(* —— 段 1｜瞬时量预清零（锁存量 _bFault/_uFault/bTestPass/bTestDerated 不入清单） —— *)
uErrId   := 16#0000_0000;
bTestActive := FALSE;
_bInPos  := FALSE;
_bCfgBad := FALSE;
_bNonFin := FALSE;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲，阀位指令撤销 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    _eCause := E_DL_PstCause.eNone;
    fValveCmdPct := fNormalPosPct;       // 复位后指令回正常位（安全侧）
    _eState := E_DL_PstState.eIdle;
END_IF

(* —— 段 3｜组态闸与非有限判据 —— *)
IF (fTestLoPct >= fTestHiPct) OR (fTravelTolPct <= DL_ZERO) OR (fNormalPosPct < DL_ZERO)
   OR (tMoveTo = T#0S) OR (tReturnTo = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
IF (fActPosPct <> fActPosPct) OR ((fActPosPct - fActPosPct) <> DL_ZERO)
   OR (fTestTargetPct <> fTestTargetPct) OR ((fTestTargetPct - fTestTargetPct) <> DL_ZERO) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜主状态机：六态全覆盖 + ELSE 兜底 —— *)
CASE _eState OF

E_DL_PstState.eIdle:
    fValveCmdPct := fNormalPosPct;
    eNe107 := E_DL_Ne107Status.eOk;      // 空闲相健康出口正常
    IF bTestDerated AND (NOT bTestPass) THEN
        eNe107 := E_DL_Ne107Status.eMaintenanceReq;   // 上轮降级结论驻留期维持维护等级
    END_IF
    IF rtTest.Q AND bEnable AND (NOT _bFault) AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
        bTestPass := FALSE;
        bTestDerated := FALSE;
        _eState := E_DL_PstState.eCheck;
    ELSIF rtTest.Q AND (_bFault OR _bCfgBad OR _bNonFin) THEN
        _bFault := TRUE;                 // 带病启动拒绝
        _uFault := 16#0003_052F;
        IF _bCfgBad THEN
            _eCause := E_DL_PstCause.eCfgIllegal;
        ELSE
            _eCause := E_DL_PstCause.eNonFinite;
        END_IF
        bError  := TRUE;
        _eState := E_DL_PstState.eFault;
    END_IF

E_DL_PstState.eCheck:
    bTestActive := TRUE;
    eNe107 := E_DL_Ne107Status.eCheckFunction;    // 检查相：功能检查等级
    IF NOT bProcessPermissive THEN
        _bFault := TRUE;                 // 许可撤销：测试前置硬闸不过
        _uFault := 16#0003_052F;
        _eCause := E_DL_PstCause.ePermissive;
        bError  := TRUE;
        _eState := E_DL_PstState.eFault;
    ELSE
        _fTargetUse := MIN(MAX(fTestTargetPct, fTestLoPct), fTestHiPct);  // 行程限幅钳位
        _fPosStart := fActPosPct;
        fValveCmdPct := _fTargetUse;
        _eState := E_DL_PstState.eMove;
    END_IF

E_DL_PstState.eMove:
    bTestActive := TRUE;
    fValveCmdPct := _fTargetUse;
    eNe107 := E_DL_Ne107Status.eCheckFunction;
    _bInPos := ABS(fActPosPct - _fTargetUse) <= fTravelTolPct;
    IF _bNonFin THEN
        _bFault := TRUE;
        _uFault := 16#0003_052F;
        _eCause := E_DL_PstCause.eNonFinite;
        bError  := TRUE;
        _eState := E_DL_PstState.eFault;
    ELS    IF _bInPos THEN
        fTestTravelPct := ABS(fActPosPct - _fPosStart);   // 行程实测：目标位达成拍快照
        _eState := E_DL_PstState.eReturn;    // 迁出条件 1：目标位达成
    ELSIF NOT bProcessPermissive THEN
        _bFault := TRUE;                 // 迁出条件 2（故障路）：行程中许可撤销
        _uFault := 16#0003_052F;
        _eCause := E_DL_PstCause.ePermissive;
        bError  := TRUE;
        _eState := E_DL_PstState.eFault;
    ELSIF tonMoveTo.Q THEN
        _bFault := TRUE;                 // 迁出条件 3（故障路）：行程超时
        _uFault := 16#0003_052F;
        _eCause := E_DL_PstCause.eMoveTo;
        bError  := TRUE;
        _eState := E_DL_PstState.eFault;
    END_IF

E_DL_PstState.eReturn:
    bTestActive := TRUE;
    fValveCmdPct := fNormalPosPct;
    eNe107 := E_DL_Ne107Status.eCheckFunction;
    _bInPos := ABS(fActPosPct - fNormalPosPct) <= fTravelTolPct;
    IF _bInPos THEN
        _eState := E_DL_PstState.eDone;  // 回位达成：进判级相（行程已在 eMove 快照）
    ELSIF tonReturnTo.Q THEN
        _bFault := TRUE;
        _uFault := 16#0003_052F;
        _eCause := E_DL_PstCause.eReturnTo;
        bError  := TRUE;
        _eState := E_DL_PstState.eFault;
    END_IF

E_DL_PstState.eDone:
    bTestActive := FALSE;
    fValveCmdPct := fNormalPosPct;
    (* 判级：行程完全未动（<= 容差）→ 失效锁存；短行程（< 指令行程 - 容差）→ 降级 *)
    IF fTestTravelPct <= fTravelTolPct THEN
        _bFault := TRUE;                 // 行程完全未动：失效级
        _uFault := 16#0003_052F;
        _eCause := E_DL_PstCause.eMoveTo;
        bError  := TRUE;
        eNe107  := E_DL_Ne107Status.eFailure;
        _eState := E_DL_PstState.eFault;
    ELSE
        bTestPass := fTestTravelPct >= (ABS(_fTargetUse - _fPosStart) - fTravelTolPct);
        bTestDerated := NOT bTestPass;
        IF bTestDerated THEN
            eNe107 := E_DL_Ne107Status.eMaintenanceReq;   // 降级：需要维护
        ELSE
            eNe107 := E_DL_Ne107Status.eOk;
        END_IF
        IF NOT bTestCmd THEN
            _eState := E_DL_PstState.eIdle;   // 测试指令撤销：回空闲（结论锁存保留）
        END_IF
    END_IF

E_DL_PstState.eFault:
    bTestActive := FALSE;
    fValveCmdPct := fNormalPosPct;       // 故障相：阀位指令安全侧回正常位
    bError := TRUE;
    eNe107 := E_DL_Ne107Status.eFailure; // 故障相健康出口失效级
    ;                                    // 故障相驻留：只认复位沿（段 2 迁出）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0003_052F;
    _eCause := E_DL_PstCause.eCfgIllegal;
    bError  := TRUE;
    eNe107  := E_DL_Ne107Status.eFailure;
    _eState := E_DL_PstState.eFault;
END_IF  // R64 结构补齐：缺失的 END_IF（门禁机械修复）
END_CASE

(* —— 段 5｜状态出口单点映射 —— *)
eState := _eState;
END_FUNCTION_BLOCK
