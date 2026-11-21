(*
  FB_DL_LaserWeldPowerSeq  —  激光焊三段功率斜坡配方序列 / Laser weld three-stage power ramp sequencer
  分类 Category : DL_Process
  码位 Code     : 16#06_0_80
  版本 Version  : 1.0.0
  溯源 Source   : LGF SignalGenerators + LBP 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 按「预焊-满焊-收弧」三段配方（功率/速度/离焦）推进时序，每段由独立 TON 计时，计时器在 FB 主体无条件刷新；
                  2) 段切换当拍冻结功率/速度/离焦输出一拍，沿用上一拍指令，防阶跃冲击焊头与熔池；
                  3) 配方越界（功率 <= 0 或 > 额定）走组态闸出厂即锁存报码，不做运行时钳位掩盖。
  边界 Boundary : ① 三段功率/速度域反算见下方「类型可表性」段；
                  ② 段切换当拍冻结输出功率一拍（由 nSegNow 与 nSegPrev 比较实现，无标志位清零覆盖风险）；
                  ③ 配方越界走组态闸锁存报码，禁运行时钳位掩盖；
                  ④ 中止/失能三行同向：功率指令 0 → 段号 0 → 出光标志 FALSE。
  依赖 Depends  : None

  类型可表性（极限值 → 类型可表性反算）:
    额定功率上限 6000.0 W，功率分辨率 0.1 W → 6000.0 / 0.1 = 60000 计数，远小于 REAL 尾数可精确表出的
    整数上限 16777216，故 0.1 W 步进在本件量程内可精确表出，无舍入溢出。
    速度上限 500.000 mm/s，分辨率 0.001 mm/s → 500000 计数，同样可表。
    离焦 ±10.000 mm，分辨率 0.001 mm → 20000 计数，可表。
    结论：本件不做饱和换算，只做域闸判据。

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0680 故障级：配方越界（功率/速度/时间/离焦域外）→ 组态闸锁存，需 bReset 上升沿清除
    16#0002_0690 故障级：段序号越界或段驻留时间为 0（枚举兜底路径）
    16#0002_06A0 信息级：段切换冻结拍已发生（诊断用，永不置 bError）
*)

TYPE E_DL_LwpsPhase :
(
    eIdle   := 0,    // 空闲待命 / Idle
    ePrep   := 10,   // 预焊段 / Pre-weld stage
    eFull   := 20,   // 满焊段 / Full-weld stage
    eCrater := 30,   // 收弧段 / Crater fill stage
    eDone   := 40,   // 序列完成 / Sequence done
    eFault  := 90    // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_LaserWeldPowerSeq
VAR_INPUT
    bEnable      : BOOL;                          // 总使能，FALSE 回空闲并清功率 / Master enable
    bStart       : BOOL;                          // 启动指令，上升沿有效 / Start command, rising edge
    bAbort       : BOOL;                          // 中止指令，上升沿回空闲 / Abort command, rising edge
    bReset       : BOOL;                          // 复位指令，上升沿清锁存故障 / Reset command, rising edge
    afSegPowerW  : ARRAY[1..3] OF REAL;           // 三段激光功率配方 [W]，域 0 < P <= fRatedPowerW / Per-stage power [W]
    afSegSpeed   : ARRAY[1..3] OF REAL;           // 三段焊接速度配方 [mm/s]，域 > 0 / Per-stage weld speed [mm/s]
    afSegDefocus : ARRAY[1..3] OF REAL;           // 三段离焦量配方 [mm]，正负双向 / Per-stage defocus [mm]
    atSegTime    : ARRAY[1..3] OF TIME;           // 三段驻留时间 [ms]，域 > 0 / Per-stage dwell time [ms]
    fRatedPowerW : REAL := 6000.0;                // 激光器额定功率 [W]，域 > 0 / Rated laser power [W]
    fDefocusMax  : REAL := 10.0;                  // 离焦允许幅值 [mm]，域 > 0 / Defocus magnitude limit [mm]
    fEps         : REAL := 1.0E-6;                // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fPowerCmdW   : REAL;                          // 功率指令 [W]，段切换当拍冻结 / Power command [W], frozen on switch
    fSpeedCmd    : REAL;                          // 焊接速度指令 [mm/s] / Weld speed command [mm/s]
    fDefocusCmd  : REAL;                          // 离焦指令 [mm] / Defocus command [mm]
    nSegNow      : INT;                           // 当前段号 1..3，0 = 未运行 / Current stage 1..3, 0 = inactive
    bWeldActive  : BOOL;                          // 出光中标志 / Emission active flag
    bSeqDone     : BOOL;                          // 全序列完成，保持型 / Sequence done, level held
    nFreezeCount : INT;                           // 段切换冻结拍累计 [拍]，钳 32000 / Accumulated freeze scans
    bError       : BOOL;                          // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId     : UDINT;                         // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut    : E_DL_LwpsPhase;                // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState      : E_DL_LwpsPhase := E_DL_LwpsPhase.eIdle; // 内部状态（唯一真值）/ Internal state, single source of truth
    rtrStart     : R_TRIG;                        // 启动沿检测实例 / Start edge instance
    rtrAbort     : R_TRIG;                        // 中止沿检测实例 / Abort edge instance
    rtrReset     : R_TRIG;                        // 复位沿检测实例 / Reset edge instance
    tonPrep      : TON;                           // 预焊段计时实例 / Pre-weld stage timer
    tonFull      : TON;                           // 满焊段计时实例 / Full-weld stage timer
    tonCrater    : TON;                           // 收弧段计时实例 / Crater stage timer
    bCfgOk       : BOOL;                          // 配方组态合法标志 / Recipe configuration valid
    bTimeOk      : BOOL;                          // 段驻留时间合法标志 / Stage dwell time valid
    nSegPrev     : INT;                           // 上一拍段号，用于冻结判据 / Previous stage for freeze criterion
    nI           : INT;                           // 配方校验循环下标 / Recipe check loop index
    uFault       : UDINT;                         // 锁存故障码，0 = 无 / Latched fault code
    uInfo        : UDINT;                         // 信息级码，永不置 bError / Info code, never raises bError
END_VAR
VAR CONSTANT
    DL_LWPS_SEGMAX : INT := 3;                    // 段总数 [段]，与数组上界一致 / Stage count matching array bound
    DL_LWPS_CNTMAX : INT := 32000;                // 冻结拍计数上限 [拍]，防 INT 溢出 / Freeze counter ceiling
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用，禁入 CASE 分支）=== *)
rtrStart(CLK := bStart);                          // 每拍刷新启动沿 / Refresh start edge every scan
rtrAbort(CLK := bAbort);                          // 每拍刷新中止沿 / Refresh abort edge every scan
rtrReset(CLK := bReset);                          // 每拍刷新复位沿 / Refresh reset edge every scan
tonPrep(IN := (_eState = E_DL_LwpsPhase.ePrep), PT := atSegTime[1]);   // 预焊段计时，无条件刷新
tonFull(IN := (_eState = E_DL_LwpsPhase.eFull), PT := atSegTime[2]);   // 满焊段计时，无条件刷新
tonCrater(IN := (_eState = E_DL_LwpsPhase.eCrater), PT := atSegTime[3]); // 收弧段计时，无条件刷新

(* === 段 1 · 组态闸（每拍重算，出厂即报码，禁运行时钳位掩盖）=== *)
bCfgOk := (fRatedPowerW > fEps) AND (fDefocusMax > fEps) AND (fRatedPowerW < 1.0E7)
          AND (fRatedPowerW = fRatedPowerW) AND (fDefocusMax = fDefocusMax);   // 额定值域闸 + NaN 自反判据
bTimeOk := TRUE;                                  // 时间域先置真，逐段否决 / Assume valid then veto per stage
FOR nI := 1 TO DL_LWPS_SEGMAX DO
    bTimeOk := bTimeOk AND (atSegTime[nI] > T#0MS);                                  // 段驻留时间必须 > 0
    bCfgOk := bCfgOk AND (afSegPowerW[nI] > fEps)                                     // 功率正域闸，防 0 功率空烧
              AND (afSegPowerW[nI] <= fRatedPowerW + fEps)                            // 不超额定，防过载
              AND (afSegSpeed[nI] > fEps)                                             // 速度正域闸
              AND (ABS(afSegDefocus[nI]) <= fDefocusMax + fEps)                       // 离焦幅值域闸
              AND (afSegPowerW[nI] = afSegPowerW[nI])                                 // 功率 NaN 自反判据
              AND (afSegSpeed[nI] = afSegSpeed[nI])                                   // 速度 NaN 自反判据
              AND (afSegDefocus[nI] = afSegDefocus[nI]);                              // 离焦 NaN 自反判据
END_FOR
IF NOT bCfgOk THEN
    uFault := 16#0002_0680;                       // 故障级：配方越界，组态闸锁存
END_IF
IF NOT bTimeOk THEN
    uFault := 16#0002_0690;                       // 故障级：段驻留时间为 0，计时器无效
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零，条件满足再置 / Clear info code each scan
IF nFreezeCount > 0 THEN
    uInfo := 16#0002_06A0;                        // 信息级：冻结拍已发生（不置 bError）
END_IF

(* === 段 2 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_LwpsPhase.eIdle :
    nSegNow := 0;                                 // 段号 0 = 未运行
    bSeqDone := FALSE;                            // 新一轮启动前清完成标志
    IF rtrReset.Q THEN
        uFault := 16#0000;                        // 故障产生态内提供清零点（复位路径可达）
    END_IF
    IF rtrStart.Q AND (uFault = 16#0000) THEN     // 无故障才允许启动
        _eState := E_DL_LwpsPhase.ePrep;
        nFreezeCount := 0;                        // 新序列清零冻结计数
    ELSIF uFault <> 16#0000 THEN
        _eState := E_DL_LwpsPhase.eFault;
    END_IF

E_DL_LwpsPhase.ePrep :
    nSegNow := 1;                                 // 预焊段
    bSeqDone := FALSE;
    IF tonPrep.Q THEN
        _eState := E_DL_LwpsPhase.eFull;          // 本拍行为：计时到，本拍末转满焊
    END_IF

E_DL_LwpsPhase.eFull :
    nSegNow := 2;                                 // 满焊段
    bSeqDone := FALSE;
    IF tonFull.Q THEN
        _eState := E_DL_LwpsPhase.eCrater;        // 转入收弧段
    END_IF

E_DL_LwpsPhase.eCrater :
    nSegNow := 3;                                 // 收弧段
    bSeqDone := FALSE;
    IF tonCrater.Q THEN
        _eState := E_DL_LwpsPhase.eDone;          // 收弧完成，转完成态
        bSeqDone := TRUE;                         // 置位型标志，同拍/段尾均不清零
    END_IF

E_DL_LwpsPhase.eDone :
    nSegNow := 0;                                 // 出光结束，段号归 0
    bSeqDone := TRUE;                             // 完成标志保持到下次启动
    IF rtrStart.Q OR rtrReset.Q THEN
        _eState := E_DL_LwpsPhase.eIdle;          // 再次启动或复位回空闲
    END_IF

E_DL_LwpsPhase.eFault :
    nSegNow := 0;                                 // 故障态强制段号 0（安全侧）
    IF rtrReset.Q AND bCfgOk AND bTimeOk THEN
        uFault := 16#0000;                        // 组态修正且复位沿才解锁
        _eState := E_DL_LwpsPhase.eIdle;
    END_IF

ELSE
    _eState := E_DL_LwpsPhase.eFault;             // 非法状态拦截，落故障态
    nSegNow := 0;                                 // 安全侧段号
    uFault := 16#0002_0690;                       // 故障级：段序号越界（枚举兜底路径）
END_CASE
IF rtrAbort.Q OR (NOT bEnable) THEN
    _eState := E_DL_LwpsPhase.eIdle;              // 中止/失能优先回空闲，安全侧最高优先
    nSegNow := 0;                                 // 段号随之为 0
    bSeqDone := FALSE;                            // 完成标志随之中止
END_IF

(* === 段 3 · 输出映射（安全三行同向：驱动方向 → 记账符号 → 到位判据）=== *)
IF nSegNow <> nSegPrev THEN
    nFreezeCount := nFreezeCount + 1;             // 段切换当拍：冻结输出，沿用上一拍指令
    IF nFreezeCount > DL_LWPS_CNTMAX THEN
        nFreezeCount := DL_LWPS_CNTMAX;           // 冻结计数饱和，防 INT 溢出
    END_IF
ELSE
    IF (nSegNow >= 1) AND (nSegNow <= DL_LWPS_SEGMAX) THEN
        fPowerCmdW  := afSegPowerW[nSegNow];      // 段号已钳域，数组访问安全
        fSpeedCmd   := afSegSpeed[nSegNow];       // 速度随段切换
        fDefocusCmd := afSegDefocus[nSegNow];     // 离焦随段切换
    ELSE
        fPowerCmdW  := 0.0;                       // 非运行态功率指令 0（驱动方向安全）
        fSpeedCmd   := 0.0;                       // 速度指令 0
        fDefocusCmd := 0.0;                       // 离焦指令 0
    END_IF
END_IF
bWeldActive := (nSegNow >= 1) AND (nSegNow <= DL_LWPS_SEGMAX) AND (fPowerCmdW > fEps);  // 出光判据与功率同向
nSegPrev := nSegNow;                              // 段号记账：本拍末更新，供下一拍冻结判据
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级码优先上报
ELSE
    uErrorId := uInfo;                            // 无故障时上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
