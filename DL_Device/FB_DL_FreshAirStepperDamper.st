(*
  FB_DL_FreshAirStepperDamper  —  新风阀步进执行器开环驱动 / Fresh-air stepper damper open-loop driver
  分类 Category : DL_Device
  码位 Code     : 16#03_2_16
  段位说明      : 03_2 段低半字节 00~0F 已满（05 为历史空穴留存），进位 16 段续号（R192）
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat-building — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : OSCAT 楼控步进阀公开语义借鉴，clean-room 实现，未复制任何源码行
                  （与 FB_DL_PulseDirStepper 分工：本件带开度当量换算与端点自学习；裸脉冲/方向驱动由 PulseDirStepper 承载）
  功能 Function : 1) 开度↔步数当量换算：目标步数 = fOpenCmdPct/100 × nStepsFullStroke，经 iStepper.MoveRelative 单发下发；
                  2) 反向行进时额外补 nBacklashSteps 间隙步（同向不补，间隙单向补偿）；
                  3) 端点自学习：回零撞负限位（uAlarmWord bit1）或超步数判 bAtEndStop 后清计数定标；
                  4) 未回零拒绝开度指令（只允许回零，置信息码）。
  边界 Boundary : ① nStepsFullStroke <= 0 / fStepRateHz <= 0 防除零判组态错；
                  ② fOpenCmdPct 越 0~100 钳制并置信息码；nBacklashSteps < 0 取 ABS 并置信息码；
                  ③ 位置计数 DINT 且到 [0, nStepsFullStroke] 边界钳制禁回绕（R28-2 两点向量：0% 计数钳 0 不出负值；
                     100% 计数钳 nStepsFullStroke 不越上界）；
                  ④ 步进接口按「步当量」下发（1 当量 = 1 步），单位换算由上层适配层承载；
                  ⑤ 解除式自证：bAtEndStop 解除 = 离开端点的 MoveRelative 受理（定标后计数已清零）；
                  ⑥ CASE 全态覆盖 + ELSE 兜底置故障相。
  依赖 Depends  : I_DL_StepperOpenLoop（注入，不实例化）；语义对齐 FB_DL_ToleranceWindow（已注册，不实例化）
  码表 Error codes（本件格 03_2_16，子码步进 +0x100）:
    16#0003_0116 信息级：未回零拒开度指令（只允许回零）
    16#0003_0216 故障级：组态非法（全行程步数 <= 0 / 步频 <= 0），锁存至复位
    16#0003_0316 信息级：开度越 0..100 已钳制
    16#0003_0416 信息级：反向间隙步数为负，已取 ABS
    16#0003_0516 信息级：端点定标完成（计数清零）
    16#0003_0616 故障级：状态机落 ELSE 兜底（非法相位 ID）

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

TYPE E_DL_DamperState :
(
    eUnhomed := 0,    // 未回零：只允许回零指令 / Unhomed, only homing allowed
    eHoming  := 10,   // 回零中：向端点步进 / Homing, stepping toward end stop
    eReady   := 20,   // 就绪：已定标待机 / Ready, calibrated and idle
    eMoving  := 30,   // 行进中：开度指令执行中 / Moving, executing position command
    eFault   := 90    // 故障：组态/驱动故障锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_FreshAirStepperDamper
VAR_INPUT
    fOpenCmdPct     : REAL := 0.0;       // 开度指令 [%]，域 0..100 / Open command percentage
    bHomingCmd      : BOOL := FALSE;     // 回零指令 / Homing command
    nStepsFullStroke: INT  := 1000;      // 全行程步数 [步]，域 > 0 / Full-stroke step count
    nBacklashSteps  : INT  := 5;         // 反向间隙步数 [步]，< 0 取 ABS / Backlash steps
    fStepRateHz     : REAL := 200.0;     // 步进频率 [Hz]，域 > 0 / Step rate
    bReset          : BOOL := FALSE;     // 复位（Fault 解除路径）/ Reset
END_VAR
VAR_OUTPUT
    fActualPosPct   : REAL;              // 实际开度 [%]（开环推算）/ Actual open percentage
    nStepCount      : DINT;              // 位置步计数 [步]，域 [0, 全行程] / Position step count
    bHoming         : BOOL;              // 回零进行中 / Homing in progress
    bHomed          : BOOL;              // 已回零定标 / Homed flag
    bAtEndStop      : BOOL;              // 端点判据成立 / At end stop
    nErrId          : UDINT;             // 事件码，0 = 无事件 / Event code
    eState          : E_DL_DamperState;  // 状态出口，段尾单点映射 / State outlet
END_VAR
VAR_IN_OUT
    iStepper : I_DL_StepperOpenLoop;     // 步进执行器引用（注入，不实例化）/ Stepper reference, injected
END_VAR
VAR
    tonReadyWch : TON;                   // 受理回读观察窗（单发后等 bReady），自复位 / Acceptance watch window
    tonFaultWch : TON;                   // 故障观察窗，自复位 / Fault watch window, self-resetting
    rtHome      : R_TRIG;                // 回零指令上升沿 / Homing command rising edge
    rtReset     : R_TRIG;                // 复位上升沿 / Reset rising edge
    _eState     : E_DL_DamperState := E_DL_DamperState.eUnhomed;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _nTarget    : INT;                   // 目标步数 [步] / Target step count
    _nDelta     : INT;                   // 本拍步增量 [步] / Step delta this scan
    _nBlCmp     : INT;                   // 间隙补偿生效步数 [步] / Effective backlash compensation
    _rClampCmd  : REAL;                  // 钳制后开度指令 [%] / Clamped open command
    _uFault     : UDINT;                 // 故障码锁存 / Latched fault code
    _uInfo      : UDINT;                 // 信息码，每拍重算 / Info code
    _bFault     : BOOL;                  // 故障锁存位 / Latched fault bit
    _bCfgBad    : BOOL;                  // 组态非法聚合 / Configuration invalid aggregate
    _bCmdPend   : BOOL;                  // 单发待受理标志 / One-shot pending acceptance flag
    _bHomePend  : BOOL;                  // 回零单发待受理标志 / Homing one-shot pending flag
    _nHomeSteps : INT;                   // 回零行程步数（含裕度）[步] / Homing travel steps with margin
END_VAR
VAR CONSTANT
    DL_ALM_NEG_LIM : WORD := 16#0002;    // 报警字 bit1 负限位 / Alarm word bit1 negative limit
    DL_HOME_MARGIN : INT  := 50;         // 回零裕度步数 [步] / Homing margin steps
    DL_WATCH_PT    : TIME := T#2S;       // 故障观察窗 [ms]，自复位 / Fault watch window
    DL_READY_PT    : TIME := T#5S;       // 受理回读观察窗 [ms] / Acceptance watch window
END_VAR

(* —— 段 0：定时器与边沿无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtHome(CLK := bHomingCmd);                                       // 回零上升沿，每拍必调
rtReset(CLK := bReset);                                          // 复位上升沿，每拍必调
tonFaultWch(IN := (NOT tonFaultWch.Q), PT := DL_WATCH_PT);       // 观察窗自复位（表达式入参）
tonReadyWch(IN := _bCmdPend OR _bHomePend, PT := DL_READY_PT);   // 受理回读观察窗（表达式入参）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_nStepCount/_bHomed 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;         // 信息码每拍重算
bHoming := FALSE;               // 回零出口缺省 FALSE（段 8 单点置位）
bAtEndStop := FALSE;            // 端点出口缺省 FALSE（Homing 相单点置位）
_bCfgBad := FALSE;              // 组态非法预清零
nErrId := 16#0000_0000;         // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (nStepsFullStroke <= 0) OR (fStepRateHz <> fStepRateHz) OR (fStepRateHz <= 0.0) THEN
    _bCfgBad := TRUE;           // 全行程步数/步频非法（防除零）
END_IF

(* —— 段 3：复位沿（Fault 解除唯一路径：bReset） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;           // 清故障锁存位
    _uFault := 16#0000_0000;
    _bCmdPend := FALSE;         // 受理标志复位
    _bHomePend := FALSE;
    _eState := E_DL_DamperState.eUnhomed;   // 复位回未回零（定标状态重判）
END_IF

(* —— 段 4：输入归一（钳制 + 间隙 ABS，均置信息码） —— *)
IF fOpenCmdPct < 0.0 THEN
    _rClampCmd := 0.0;          // 越下限钳 0（R28-2 向量一：0% 不回绕负值）
    _uInfo := 16#0003_0316;     // 信息级：开度越域已钳制
ELSIF fOpenCmdPct > 100.0 THEN
    _rClampCmd := 100.0;        // 越上限钳 100（R28-2 向量二：100% 不越上界）
    _uInfo := 16#0003_0316;     // 信息级：开度越域已钳制
ELSE
    _rClampCmd := fOpenCmdPct;  // 域内直通
END_IF
IF nBacklashSteps < 0 THEN
    _nBlCmp := -nBacklashSteps; // 负间隙步取 ABS（规格强制）
    _uInfo := 16#0003_0416;     // 信息级：负间隙步已取 ABS
ELSE
    _nBlCmp := nBacklashSteps;  // 正常值直通
END_IF
_nTarget := TRUNC(_rClampCmd / 100.0 * INT_TO_REAL(nStepsFullStroke));   // 开度→步数当量换算

(* —— 段 5：相位机（只做迁移与单发命令；出口在段 8） —— *)
CASE _eState OF

E_DL_DamperState.eUnhomed:
    IF _bCfgBad THEN
        _uFault := 16#0003_0216;            // 故障级：组态非法
        _bFault := TRUE;                    // 锁存（复位沿可清）
        _eState := E_DL_DamperState.eFault;
    ELSIF rtHome.Q THEN
        _nHomeSteps := nStepsFullStroke + _nBlCmp + DL_HOME_MARGIN;   // 回零行程（含裕度）
        iStepper.MoveRelative(fDistance := INT_TO_LREAL(-_nHomeSteps), fSpeed := fStepRateHz);   // 单发向端点
        _bHomePend := TRUE;                 // 待受理标志
        _eState := E_DL_DamperState.eHoming;// 进回零相
    ELSIF _nTarget <> DINT_TO_INT(nStepCount) THEN
        _uInfo := 16#0003_0116;             // 信息级：未回零拒开度指令（只允许回零）
    END_IF

E_DL_DamperState.eHoming:
    bAtEndStop := (iStepper.uAlarmWord AND DL_ALM_NEG_LIM) <> 0;   // 端点判据：负限位报警字
    IF bAtEndStop OR tonReadyWch.Q THEN
        nStepCount := 0;                    // 端点定标：计数清零（禁回绕）
        bHomed := TRUE;                     // 定标完成
        _uInfo := 16#0003_0516;             // 信息级：端点定标完成
        _bHomePend := FALSE;                // 受理标志清
        _eState := E_DL_DamperState.eReady; // 进就绪相
    ELSIF iStepper.uAlarmWord <> 0 THEN
        IF (iStepper.uAlarmWord AND DL_ALM_NEG_LIM) = 0 THEN
            _uFault := 16#0003_0216;        // 回零中出现非限位报警（驱动器/堵转）：按组态域故障升级
            _bFault := TRUE;
            iStepper.Stop();
            _eState := E_DL_DamperState.eFault;
        END_IF
    END_IF

E_DL_DamperState.eReady:
    IF _nTarget <> DINT_TO_INT(nStepCount) THEN
        _nDelta := _nTarget - DINT_TO_INT(nStepCount);              // 步增量
        IF (_nDelta < 0) AND (_nBlCmp > 0) THEN
            _nDelta := _nDelta - _nBlCmp;                           // 反向行进：额外补间隙步（同向不补）
        END_IF
        iStepper.MoveRelative(fDistance := INT_TO_LREAL(_nDelta), fSpeed := fStepRateHz);   // 单发下发（步当量）
        nStepCount := DINT(_nTarget);                               // 开环指令位置记账（钳制见段 6）
        _bCmdPend := TRUE;                                          // 待受理标志
        _eState := E_DL_DamperState.eMoving;                        // 进行进相
    ELSIF iStepper.uAlarmWord <> 0 THEN
        _uFault := 16#0003_0216;            // 就绪态出现驱动报警
        _bFault := TRUE;
        _eState := E_DL_DamperState.eFault;
    END_IF

E_DL_DamperState.eMoving:
    IF iStepper.bReady THEN
        _bCmdPend := FALSE;                 // 受理确认
        _eState := E_DL_DamperState.eReady; // 回就绪相
    ELSIF tonReadyWch.Q THEN
        _uFault := 16#0003_0216;            // 受理回读超观察窗（驱动无响应）
        _bFault := TRUE;
        iStepper.Stop();
        _eState := E_DL_DamperState.eFault;
    ELSIF iStepper.uAlarmWord <> 0 THEN
        _uFault := 16#0003_0216;            // 行进中出现驱动报警
        _bFault := TRUE;
        iStepper.Stop();
        _eState := E_DL_DamperState.eFault;
    END_IF

E_DL_DamperState.eFault:
    ;                                       // 故障相：等复位沿（段 3 承载解除）

ELSE
    _uFault := 16#0003_0616;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_DamperState.eFault;     // 强制回故障相

END_CASE

(* —— 段 6：位置计数边界钳制（禁回绕，R28-2 两点向量收口） —— *)
IF nStepCount < 0 THEN
    nStepCount := 0;                        // 下界钳 0（0% 向量：不出负计数）
ELSIF nStepCount > DINT(nStepsFullStroke) THEN
    nStepCount := DINT(nStepsFullStroke);   // 上界钳全行程（100% 向量：不越上界）
END_IF

(* —— 段 7：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
fActualPosPct := DINT_TO_REAL(nStepCount) * 100.0 / INT_TO_REAL(nStepsFullStroke);   // 开度出口（分母已闸 > 0）
bHoming := (_eState = E_DL_DamperState.eHoming);          // 回零出口（相位单点）
bHomed := bHomed AND (NOT _bFault);       // 定标出口（故障相撤销）
bAtEndStop := bAtEndStop AND (_eState = E_DL_DamperState.eHoming);   // 端点出口仅回零相有效
IF _bFault THEN
    nErrId := _uFault;          // 故障锁存码回放
ELSIF _uInfo <> 16#0000_0000 THEN
    nErrId := _uInfo;           // 信息码
END_IF
eState := _eState;              // 状态出口单点映射

END_FUNCTION_BLOCK
