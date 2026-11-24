(*
  FB_DL_AxisLimitRecovery  —  硬限位触发后的脱离恢复顺控 / Hard-limit trigger back-off recovery sequence
  分类 Category : DL_Motion
  码位 Code     : 16#04_0_A7
  段位说明      : A6 格由 FB_DL_CamOverrideTrim 启用，本件启用相邻 A7 格（一件一码）
  版本 Version  : 1.0.1
  来源 Source   : t1-6-plcopen — 硬限位恢复顺控待挖项落地
  溯源 Origin   : clean-room 实现，PLCopen 恢复语义公开借鉴，未复制任何源码行
  功能 Function : 1) 七相顺控 Idle→Judge→Backoff→Confirm→Reenable→Done，判限位方向 → 低速反向
                  脱离 → 脱离确认 → 重新使能放行；
                  2) 判向：bLimPos 触发反向退、bLimNeg 触发正向退、双限同拍判组态/硬件故障；
                  3) 脱离确认双判据：限位开关释放 AND FB_DL_AxisInPosMonitor 稳定到位（防半脱假通过）；
                  4) 放行再使能：CmdReset → Enable(TRUE)，等 bEnabled 落定才进 Done。
  边界 Boundary : ① 与 FB_DL_SoftLimitGuard（软限位制动预判）分工：那件管预防，本件管硬限位已触发后的恢复；
                  与 FB_DL_TorqueLimitControl（达限即限）分工：那件管力矩限制本身；
                  ② 脱离移动经 I_DL_MotionAxis.MoveRelative 单发下发（进入相拍一次，方法内受理去重）；
                  ③ R228-A 达标声明：四只超时 TON 均单相独占（IN 为单相等式），跨相迁移拍 IN 必断；
                  ④ R228-B 达标声明（R41 P0-1 返修后逐字自证，与段 4 实现逐字对照）：
                  eFault 迁出 = rtReset.Q（当拍量） AND NOT iAxis.bError（当拍量）
                  AND NOT (bLimPos AND bLimNeg)（当拍量）——三个子条件全部为当拍量，
                  零锁存量自指（R240 修复点）；可满足性：双限不同拍触发（正常工况）
                  AND 轴无报警 AND 复位沿到达，迁出边真实可达，无恒假子式；
                  ⑤ 起始时无限位触发：置信息级码并停留 Idle（不做无意义移动）。
  依赖 Depends  : I_DL_MotionAxis（注入，不实例化）；FB_DL_AxisInPosMonitor（实例化，引脚按 registry 实名）
  码表 Error codes（本件格 04_0_A7，子码步进 +0x100）:
    16#0004_01A7 信息级：恢复完成（Done 相）
    16#0004_02A7 故障级：双限位同拍触发（组态/硬件矛盾），锁存至复位
    16#0004_03A7 故障级：段超时（Judge/Backoff/Confirm/Reenable 各相独立计时），锁存至复位
    16#0004_04A7 故障级：轴故障锁存（iAxis.bError），锁存至复位
    16#0004_05A7 故障级：状态机落 ELSE 兜底（非法相位 ID），锁存至复位
    16#0004_06A7 信息级：起始时无限位触发（无需恢复，停留 Idle）
    16#0004_07A7 故障级：组态非法（距离/速度/加速度/容差/超时域非法），锁存至复位

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 2 · 序号 8）
    2026-11-19  v1.0.1  R40 5 抽终审挂账（不改逻辑）：⚠ 段 4 解除式「rtReset.Q AND NOT _bFault」
                  引用锁存位自身，锁存后恒假 → eFault 永久锁死（R28-1 典型反例）；修复方向 = 改按
                  当前条件判定（NOT iAxis.bError AND NOT (bLimPos AND bLimNeg)），返修轮处理。
    2026-11-19  v1.0.1  R41 P0-1 返修实施：段 4 解除式重构为「rtReset.Q AND NOT iAxis.bError
                  AND NOT (bLimPos AND bLimNeg)」，全部当拍量、零锁存量自指；每个解除式 BOOL
                  已在段 4 逐个标注锁存量/当拍量；头注释④自证句与实现逐字对照。
*)

TYPE E_DL_AxlRecState :
(
    eIdle     := 0,    // 空闲：等恢复指令 / Idle, waiting for recovery command
    eJudge    := 10,   // 判向：确定脱离方向 / Judge, determine back-off direction
    eBackoff  := 20,   // 脱离：低速反向移动 / Backoff, low-speed reverse move
    eConfirm  := 30,   // 确认：限位释放 + 稳定到位 / Confirm, limit released and settled
    eReenable := 40,   // 放行：复位报警 + 再使能 / Reenable, reset alarm and power on
    eDone     := 50,   // 完成：恢复落定 / Done
    eFault    := 90    // 故障：双限/超时/轴故障锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisLimitRecovery
VAR_INPUT
    bStartRec    : BOOL := FALSE;     // 恢复指令（上升沿）/ Recovery start command
    bLimPos      : BOOL := FALSE;     // 正向硬限位开关，TRUE = 已触发 [-] / Positive hard limit switch, TRUE = tripped
    bLimNeg      : BOOL := FALSE;     // 负向硬限位开关，TRUE = 已触发 [-] / Negative hard limit switch, TRUE = tripped
    fBackoffDist : REAL := 5.0;       // 脱离距离 [mm]，域 (0, 10000] / Back-off distance
    fBackoffVel  : REAL := 2.0;       // 脱离速度 [mm/s]，域 (0, 1000] / Back-off velocity
    fBackoffAcc  : REAL := 50.0;      // 脱离加/减速度 [mm/s²]，域 > 0 / Back-off acceleration
    fPosTol      : REAL := 0.05;      // 确认相位置窗半宽 [mm]，域 > 0 / Confirm-phase position tolerance
    fVelTol      : REAL := 1.0;       // 确认相速度阈 [mm/s]，域 > 0 / Confirm-phase velocity threshold
    tPhaseTo     : TIME := T#10S;     // 单相超时 [ms]，域 > 0 / Per-phase timeout
    bReset       : BOOL := FALSE;     // 复位（eFault 迁出沿之一）/ Reset, fault exit edge
END_VAR
VAR_OUTPUT
    eState       : E_DL_AxlRecState;  // 状态出口，段尾单点映射 / State outlet
    bRecovered   : BOOL;              // 恢复完成锁存（Done 相置位，Idle 相清除）/ Recovered latch
    bBackDirNeg  : BOOL;              // 本次脱离方向（TRUE = 负向）/ Back-off direction of this recovery
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR_IN_OUT
    iAxis : I_DL_MotionAxis;          // 运动轴引用（注入，不实例化）/ Motion axis reference
END_VAR
VAR
    fbInPos    : FB_DL_AxisInPosMonitor;  // 到位监视实例（确认相使能）/ In-position monitor instance
    tonJudgeTo : TON;                     // 判向相超时（单相独占）/ Judge-phase timeout, single phase
    tonBackTo  : TON;                     // 脱离相超时（单相独占）/ Backoff-phase timeout, single phase
    tonConfTo  : TON;                     // 确认相超时（单相独占）/ Confirm-phase timeout, single phase
    tonEnTo    : TON;                     // 放行相超时（单相独占）/ Reenable-phase timeout, single phase
    rtStart    : R_TRIG;                  // 恢复指令上升沿 / Recovery start edge
    rtReset    : R_TRIG;                  // 复位上升沿 / Reset rising edge
    _eState    : E_DL_AxlRecState := E_DL_AxlRecState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _rDist     : REAL;                    // 生效脱离距离 [mm] / Effective back-off distance
    _rVel      : REAL;                    // 生效脱离速度 [mm/s] / Effective back-off velocity
    _rAcc      : REAL;                    // 生效脱离加减速度 [mm/s²] / Effective back-off acceleration
    _rTgt      : REAL;                    // 脱离目标位置 [mm]（监视比对用）/ Back-off target position for the monitor
    _bDirNeg   : BOOL;                    // 脱离方向内部量（TRUE = 负向）/ Internal direction flag
    _bCmdLatch : BOOL;                    // 本相命令已单发标志 / Phase command one-shot latch
    _uFault    : UDINT;                   // 故障码锁存 / Latched fault code
    _uInfo     : UDINT;                   // 信息码，每拍重算 / Info code
    _bFault    : BOOL;                    // 故障锁存位 / Latched fault bit
    _bCfgBad   : BOOL;                    // 组态非法聚合 / Configuration invalid aggregate
    _bResetOk  : BOOL;                    // 轴报警复位命令受理标志 / Axis alarm reset accepted flag
END_VAR
VAR CONSTANT
    DL_ALR_DIST_MAX : REAL := 10000.0;  // 脱离距离组态上限 [mm] / Back-off distance configuration bound
    DL_ALR_VEL_MAX  : REAL := 1000.0;   // 脱离速度组态上限 [mm/s] / Back-off velocity configuration bound
END_VAR

(* —— 段 0：定时器与边沿无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtStart(CLK := bStartRec);                                            // 恢复指令沿刷新，每拍必调
rtReset(CLK := bReset);                                               // 复位沿刷新，每拍必调
tonJudgeTo(IN := (_eState = E_DL_AxlRecState.eJudge), PT := tPhaseTo);     // 判向超时（单相独占）
tonBackTo(IN := (_eState = E_DL_AxlRecState.eBackoff), PT := tPhaseTo);    // 脱离超时（单相独占）
tonConfTo(IN := (_eState = E_DL_AxlRecState.eConfirm), PT := tPhaseTo);    // 确认超时（单相独占）
tonEnTo(IN := (_eState = E_DL_AxlRecState.eReenable), PT := tPhaseTo);     // 放行超时（单相独占）

(* —— 段 1：到位监视实例无条件周期刷新（确认相使能，其余相旁路） —— *)
fbInPos(bEnable := (_eState = E_DL_AxlRecState.eConfirm),   // 仅确认相判定
        fActPos := iAxis.fPosition,                          // 轴实际位置
        fTargetPos := _rTgt,                                 // 脱离目标位置
        fActVel := iAxis.fVelocity,                          // 轴实际速度
        fPosTol := MAX(fPosTol, 1.0E-6),                     // 位置窗（下限防零窗死判）
        fVelTol := MAX(fVelTol, 1.0E-6),                     // 速度阈（下限防零阈死判）
        tSettle := T#100MS,                                  // 稳定时间（恢复确认标准口径）
        uChatterLimit := 5,                                  // 抖振上限（默认口径）
        tChatterWin := T#2S);                                // 抖振观察窗（默认口径）

(* —— 段 2：单拍量预清零（锁存量 _uFault/_bFault/_bRecovered 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
_bCfgBad := FALSE;                  // 组态非法预清零
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 3：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fBackoffDist <= 0.0) OR (fBackoffDist > DL_ALR_DIST_MAX)
   OR (fBackoffVel <= 0.0) OR (fBackoffVel > DL_ALR_VEL_MAX)
   OR (fBackoffAcc <= 0.0) OR (fPosTol <= 0.0) OR (fVelTol <= 0.0)
   OR (TIME_TO_DINT(tPhaseTo) <= 0) THEN
    _bCfgBad := TRUE;               // 距离/速度/加速度/容差/超时非法
END_IF

(* —— 段 4：故障聚合与 eFault 迁出沿（R228-B 迁出条件逐字自证见头注释④） —— *)
IF iAxis.bError THEN
    _uFault := 16#0004_04A7;        // 故障级：轴故障锁存
    _bFault := TRUE;
END_IF
IF bLimPos AND bLimNeg THEN
    _uFault := 16#0004_02A7;        // 故障级：双限同拍
    _bFault := TRUE;
END_IF
IF rtReset.Q AND (NOT iAxis.bError) AND (NOT (bLimPos AND bLimNeg)) THEN
(* 解除式逐 BOOL 标注（R240）：rtReset.Q = 当拍量；iAxis.bError = 当拍量；
   bLimPos / bLimNeg = 当拍量——三者均不含锁存量（_bFault / _uFault），解除边真实可达。 *)
    IF _eState = E_DL_AxlRecState.eFault THEN
        _eState := E_DL_AxlRecState.eIdle;  // 故障相迁出：回空闲（迁出边全当拍量，R240）
    END_IF
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，同上唯一解除路径）
END_IF

(* —— 段 5：相位机（只做迁移与单发命令；出口在段 8） —— *)
CASE _eState OF

E_DL_AxlRecState.eIdle:
    IF rtStart.Q AND (NOT _bFault) THEN
        IF _bCfgBad THEN
            _uFault := 16#0004_07A7;            // 故障级：组态非法
            _bFault := TRUE;
            _eState := E_DL_AxlRecState.eFault;
        ELSIF (NOT bLimPos) AND (NOT bLimNeg) THEN
            _uInfo := 16#0004_06A7;             // 信息级：无限位触发，无需恢复
        ELSE
            _bCmdLatch := FALSE;                // 命令单发标志复位
            _eState := E_DL_AxlRecState.eJudge; // 进判向相
        END_IF
    END_IF

E_DL_AxlRecState.eJudge:
    IF _bFault THEN
        _eState := E_DL_AxlRecState.eFault;     // 聚合故障直接进故障相
    ELSIF tonJudgeTo.Q THEN
        _uFault := 16#0004_03A7;                // 故障级：判向相超时
        _bFault := TRUE;
        _eState := E_DL_AxlRecState.eFault;
    ELSE
        IF bLimPos THEN
            _bDirNeg := TRUE;                   // 正限触发：负向脱离
            _rDist := -fBackoffDist;
        ELSE
            _bDirNeg := FALSE;                  // 负限触发：正向脱离
            _rDist := fBackoffDist;
        END_IF
        _rVel := fBackoffVel;                   // 生效速度（低速口径由组态保证）
        _rAcc := fBackoffAcc;                   // 生效加减速度
        _rTgt := iAxis.fPosition + _rDist;      // 脱离目标位置（判向拍锁定）
        _eState := E_DL_AxlRecState.eBackoff;   // 进脱离相
    END_IF

E_DL_AxlRecState.eBackoff:
    IF _bFault THEN
        iAxis.Stop();                           // 故障安全侧受控停
        _eState := E_DL_AxlRecState.eFault;
    ELSIF tonBackTo.Q THEN
        _uFault := 16#0004_03A7;                // 故障级：脱离相超时
        _bFault := TRUE;
        iAxis.Stop();
        _eState := E_DL_AxlRecState.eFault;
    ELSE
        IF NOT _bCmdLatch THEN
            iAxis.MoveRelative(fDist := _rDist, fVel := _rVel, fAcc := _rAcc);  // 单发脱离移动
            _bCmdLatch := TRUE;                 // 单发标志
        END_IF
        _eState := E_DL_AxlRecState.eConfirm;   // 下发即进确认相（监视件承载收敛判定）
        _bCmdLatch := FALSE;                    // 确认相复用单发标志前复位
    END_IF

E_DL_AxlRecState.eConfirm:
    IF _bFault THEN
        iAxis.Stop();                           // 故障安全侧受控停
        _eState := E_DL_AxlRecState.eFault;
    ELSIF tonConfTo.Q THEN
        _uFault := 16#0004_03A7;                // 故障级：确认相超时
        _bFault := TRUE;
        iAxis.Stop();
        _eState := E_DL_AxlRecState.eFault;
    ELSIF (NOT bLimPos) AND (NOT bLimNeg) AND fbInPos.bSettled AND fbInPos.bValid THEN
        _bCmdLatch := FALSE;                    // 放行相命令单发标志复位
        _eState := E_DL_AxlRecState.eReenable;  // 双判据通过：进放行相
    END_IF

E_DL_AxlRecState.eReenable:
    IF _bFault THEN
        _eState := E_DL_AxlRecState.eFault;     // 故障相（使能请求已停发）
    ELSIF tonEnTo.Q THEN
        _uFault := 16#0004_03A7;                // 故障级：放行相超时
        _bFault := TRUE;
        _eState := E_DL_AxlRecState.eFault;
    ELSE
        IF NOT _bCmdLatch THEN
            _bResetOk := iAxis.Reset();         // 单发报警复位
            _bCmdLatch := TRUE;                 // 单发标志（复位与使能同窗，顺序固定）
        END_IF
        iAxis.Enable(bOn := TRUE);              // 使能请求（电平语义，方法内受理）
        IF iAxis.bEnabled AND (NOT iAxis.bError) THEN
            _eState := E_DL_AxlRecState.eDone;  // 使能落定且无报警：进完成相
        END_IF
    END_IF

E_DL_AxlRecState.eDone:
    bRecovered := TRUE;                     // 恢复完成锁存（Done 相每拍重申）
    _uInfo := 16#0004_01A7;                 // 信息级：恢复完成
    IF NOT bStartRec THEN
        bRecovered := FALSE;                // 指令撤销：完成锁存随相清除
        _eState := E_DL_AxlRecState.eIdle;  // 回空闲
    END_IF

E_DL_AxlRecState.eFault:
    ;                                       // 故障相：等复位沿（段 4 承载迁出）

ELSE
    _uFault := 16#0004_05A7;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;
    _eState := E_DL_AxlRecState.eFault;     // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
bBackDirNeg := _bDirNeg;                    // 方向出口镜像
IF _bFault THEN
    nErrId := _uFault;                      // 故障锁存码回放
    bRecovered := FALSE;                    // 故障相完成出口强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF
eState := _eState;                          // 状态出口单点映射

END_FUNCTION_BLOCK
