(*
  FB_DL_AxisAbortSafeSeq  —  运动中止安全序列（Abort→Stop→Disable 三段） / Axis abort safe sequence: stop, standstill wait, disable
  分类 Category : DL_Motion
  版本 Version  : 1.0.1
  来源 Source   : t1-6-plcopen — 运动序列族零检索深化（R233 成对纪律落地）
  溯源 Origin   : clean-room 实现，PLCopen 中止语义公开借鉴，未复制任何源码行
  功能 Function : 1) 三段顺控：eAbortStop（单发 iAxis.Stop，等轴受理反馈进
                  eStopping/eStandstill/eDisabled 稳态后迁出）→ eWaitStandstill
                  （等轴回 eStandstill）→ eDisable（单发 iAxis.Enable(bOn:=FALSE)，
                  等 bEnabled 落 FALSE）→ eDone；每段超时 TON 独立实例
                  （R233：配方推进与超时分件分实例）；
                  2) iAxis.bError → 故障级 03B1 锁存；段超时 → 03B2 锁存；
                  3) eFault 迁出边全当拍量（R240 落地），逐 BOOL 标注见段 5。
  返修记录 Rework  :
    2026-11-19  v1.0.1  R42 P0-4 轻度返修：v1.0.0 eAbortStop 相在单发 Stop 的
                        同拍即迁出 eWaitStandstill——该相驻留仅一个扫描拍，
                        tonStopTo 的 IN 只见单拍 TRUE，超时判据结构性不可达，
                        Stop 受理失败（轴拒收）将静默跳相（P0 派单缺陷④）。
                        修复要点：eAbortStop 相改为驻留等轴受理稳态
                        （eStopping/eStandstill/eDisabled 任一），受理确认后
                        才迁出；tonStopTo 跨相驻留恢复可计时性；对外接口
                        签名不变。
  边界 Boundary : ① 段迁出条件可满足性逐字自证：
                  eAbortStop → eWaitStandstill：Stop 受理后轴必进 eStopping（接口语义），
                  再至 eStandstill（受控停完成），迁出条件 eState 落已知稳态，可达；
                  eWaitStandstill → eDisable：轴停稳回 eStandstill 为接口规定稳态，可达；
                  eDisable → eDone：Enable(bOn:=FALSE) 后 bEnabled 落 FALSE 为接口规定
                  迁移（eStandstill → eDisabled），可达；
                  eFault 迁出：rtReset.Q AND NOT iAxis.bError AND bSrvOk（轴报警复位后 +
                  复位沿），可达；
                  ② 超时 TON 均单相独占（IN 为单相等式），跨相迁移拍 IN 必断（R228-A）；
                  ③ 组态闸：任一超时 <= 0 → 03B2 同级锁存（组态与超时归并为段超时码）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : I_DL_MotionAxis（注入，不实例化）；Standard.library（TON / R_TRIG）
  码表 Error codes（Motion 段 0004，窗口 03B1~03B3 / 04B1~04B3）:
    16#0004_03B1 故障级：轴故障锁存（iAxis.bError），锁存至 bReset
    16#0004_03B2 故障级：段超时或组态非法（Abort/Wait/Disable 各相独立计时），锁存至 bReset
    16#0004_03B3 故障级：相位落 ELSE 兜底（非法相位 ID），锁存至 bReset
    16#0004_04B1 信息级：序列完成（eDone 相）
    16#0004_04B2 信息级：中止指令受理（Stop 单发拍）
    16#0004_04B3 信息级：使能切断确认（bEnabled 落 FALSE 拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 3 · 序号 2）
    2026-11-19  v1.0.1  R42 P0-4 轻度返修（见返修记录节）
*)

TYPE E_DL_AbsSeqState :
(
    eIdle            := 0,    // 空闲：等中止指令 / Idle, waiting abort command
    eAbortStop       := 10,   // 受停：单发 Stop，等轴受理 / Abort stop issued, waiting acceptance
    eWaitStandstill  := 20,   // 等停稳：等轴回 eStandstill / Waiting axis standstill
    eDisable         := 30,   // 切使能：单发 Enable(FALSE)，等 bEnabled 落 / Disable, waiting bEnabled off
    eDone            := 40,   // 完成：安全序列落定 / Done
    eFault           := 90    // 故障：轴故障/超时锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisAbortSafeSeq
VAR_INPUT
    bAbortCmd    : BOOL := FALSE;     // 中止指令（上升沿启动序列）[-] / Abort command, starts on edge
    tStopTo      : TIME := T#2S;      // 受停相超时 [ms]，域 > 0 / Stop-phase timeout
    tStillTo     : TIME := T#10S;     // 等停稳相超时 [ms]，域 > 0 / Standstill-phase timeout
    tDisTo       : TIME := T#2S;      // 切使能相超时 [ms]，域 > 0 / Disable-phase timeout
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存（eFault 唯一迁出沿之一）/ Reset edge
END_VAR
VAR_IN_OUT
    iAxis        : I_DL_MotionAxis;   // 运动轴引用（注入，不实例化）/ Motion axis reference
END_VAR
VAR_OUTPUT
    eState       : E_DL_AbsSeqState;  // 状态出口，段尾单点映射 / State outlet
    bDone        : BOOL;              // 序列完成标志（eDone 相电平）/ Sequence done flag
    bCmdAccepted : BOOL;              // 中止指令受理单拍镜像 [-] / Command accepted mirror
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonStopTo    : TON;               // 受停相超时（单相独占），无条件刷新 / Stop-phase timeout
    tonStillTo   : TON;               // 等停稳相超时（单相独占），无条件刷新 / Standstill timeout
    tonDisTo     : TON;               // 切使能相超时（单相独占），无条件刷新 / Disable-phase timeout
    rtAbort      : R_TRIG;            // 中止指令沿实例，无条件刷新 / Abort edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_AbsSeqState := E_DL_AbsSeqState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bCmdLatch   : BOOL;              // 本相命令已单发标志 / Phase command one-shot latch
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
rtAbort(CLK := bAbortCmd);                                // 中止沿（每拍必调）
rtReset(CLK := bReset);                                   // 复位沿（每拍必调）
tonStopTo(IN := (_eState = E_DL_AbsSeqState.eAbortStop), PT := tStopTo);       // 受停超时（单相独占）
tonStillTo(IN := (_eState = E_DL_AbsSeqState.eWaitStandstill), PT := tStillTo); // 等停稳超时（单相独占）
tonDisTo(IN := (_eState = E_DL_AbsSeqState.eDisable), PT := tDisTo);           // 切使能超时（单相独占）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bCmdAccepted := FALSE;              // 受理镜像缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：轴故障与复位沿（判据当拍量） —— *)
IF iAxis.bError THEN                // iAxis.bError = 当拍量
    _uFault := 16#0004_03B1;        // 故障级：轴故障锁存
    _bFault := TRUE;
    iAxis.Stop();                   // 故障安全侧受控停
END_IF
IF (TIME_TO_DINT(tStopTo) <= 0) OR (TIME_TO_DINT(tStillTo) <= 0) OR (TIME_TO_DINT(tDisTo) <= 0) THEN
    _uFault := 16#0004_03B2;        // 故障级：组态非法（归并段超时码，头注释③）
    _bFault := TRUE;
END_IF
IF rtReset.Q AND (NOT iAxis.bError) THEN
(* 解除式逐 BOOL 标注（R240）：rtReset.Q = 当拍量；iAxis.bError = 当拍量；无锁存量自指。 *)
    IF _eState = E_DL_AbsSeqState.eFault THEN
        _eState := E_DL_AbsSeqState.eIdle;  // 故障相迁出：回空闲
    END_IF
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
END_IF

(* —— 段 3：相位机（只做迁移与单发命令；出口在段 5） —— *)
CASE _eState OF

E_DL_AbsSeqState.eIdle:
    IF rtAbort.Q AND (NOT _bFault) THEN
        _bCmdLatch := FALSE;                // 单发标志复位
        _eState := E_DL_AbsSeqState.eAbortStop;  // 进受停相
    END_IF

E_DL_AbsSeqState.eAbortStop:
    IF _bFault THEN
        _eState := E_DL_AbsSeqState.eFault; // 聚合故障直接进故障相
    ELSIF tonStopTo.Q THEN
        _uFault := 16#0004_03B2;            // 故障级：受停相超时（v1.0.1 相驻留承载，判据可达）
        _bFault := TRUE;
        _eState := E_DL_AbsSeqState.eFault;
    ELSE
        IF NOT _bCmdLatch THEN
            iAxis.Stop();                   // 单发受停命令（仅首拍）
            _bCmdLatch := TRUE;             // 单发标志
            _uInfo := 16#0004_04B2;         // 信息级：中止指令受理
            bCmdAccepted := TRUE;           // 受理镜像（单拍）
        END_IF
        IF (iAxis.eState = E_DL_AxisState.eStopping)         // 轴受理稳态 1：受控停中
           OR (iAxis.eState = E_DL_AxisState.eStandstill)    // 轴受理稳态 2：已停稳
           OR (iAxis.eState = E_DL_AxisState.eDisabled) THEN // 轴受理稳态 3：已失能
            _bCmdLatch := FALSE;                // 单发标志复位（下一相复用前）
            _eState := E_DL_AbsSeqState.eWaitStandstill;  // 受理确认：迁出（v1.0.1 驻留承载）
        END_IF
    END_IF

E_DL_AbsSeqState.eWaitStandstill:
    IF _bFault THEN
        _eState := E_DL_AbsSeqState.eFault; // 故障相
    ELSIF tonStillTo.Q THEN
        _uFault := 16#0004_03B2;            // 故障级：等停稳相超时
        _bFault := TRUE;
        _eState := E_DL_AbsSeqState.eFault;
    ELSE
        IF (iAxis.eState = E_DL_AxisState.eStandstill)
           OR (iAxis.eState = E_DL_AxisState.eDisabled) THEN
            _bCmdLatch := FALSE;            // 单发标志复位
            _eState := E_DL_AbsSeqState.eDisable;     // 停稳确认：进切使能相
        END_IF
    END_IF

E_DL_AbsSeqState.eDisable:
    IF _bFault THEN
        _eState := E_DL_AbsSeqState.eFault; // 故障相（使能请求已停发）
    ELSIF tonDisTo.Q THEN
        _uFault := 16#0004_03B2;            // 故障级：切使能相超时
        _bFault := TRUE;
        _eState := E_DL_AbsSeqState.eFault;
    ELSE
        IF NOT _bCmdLatch THEN
            iAxis.Enable(bOn := FALSE);     // 单发下使能命令
            _bCmdLatch := TRUE;             // 单发标志
        END_IF
        IF NOT iAxis.bEnabled THEN
            _uInfo := 16#0004_04B3;         // 信息级：使能切断确认
            _eState := E_DL_AbsSeqState.eDone;        // 进完成相
        END_IF
    END_IF

E_DL_AbsSeqState.eDone:
    bDone := TRUE;                      // 完成标志（eDone 相电平）
    _uInfo := 16#0004_04B1;             // 信息级：序列完成
    IF NOT bAbortCmd THEN
        bDone := FALSE;                 // 指令撤销：完成标志随相清除
        _eState := E_DL_AbsSeqState.eIdle;        // 回空闲
    END_IF

E_DL_AbsSeqState.eFault:
    ;                                   // 故障相：等复位沿（段 2 承载迁出）

ELSE
    _uFault := 16#0004_03B3;            // 故障级：非法相位 ID 兜底
    _bFault := TRUE;
    _eState := E_DL_AbsSeqState.eFault; // 强制回故障相

END_CASE

(* —— 段 4：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bDone := FALSE;                 // 故障相完成出口强制 FALSE（安全侧）
    bCmdAccepted := FALSE;          // 故障相受理镜像强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
