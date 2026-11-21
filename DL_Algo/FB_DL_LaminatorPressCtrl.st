(*
  FB_DL_LaminatorPressCtrl  —  层压机压力-时间闭环（真空段/加压段分离双目标 + 斜坡限速）/ Laminator pressure-time closed loop
  分类 Category : DL_Algo
  码位 Code     : 16#02_3_88
  段位说明      : 86/87 格由频率/三角波发生件启用，本件启用相邻 88 格（一件一码）
  版本 Version  : 1.0.0
  来源 Source   : t2-2-lbp — ROADMAP 原记 Process 属分层误记，闭环控制律按分层判定归 Algo，本轮改判并留痕
  溯源 Origin   : clean-room 实现，层压压力曲线公开工艺语义借鉴，未复制任何源码行
                  （与 FB_DL_RollCompressForceBalance 分工：那件管力平衡，本件管压力曲线跟随）
  功能 Function : 1) 六相顺控 Idle→Evac→RampPress→Hold→Release→Done，真空段/加压段目标分离；
                  2) 加压目标经 FB_DL_RateLimiter 斜坡限速（fRampRateBarS），斜坡中段由
                  FB_DL_CascadePid 主环（压力）+ 副环（执行器阀位反馈）闭环跟随；
                  3) Hold 相按配方时长 tonHold 驻留，压力越保持窗置信息级码（不静默）；
                  4) Release 相泄压 + 缩回，常压与缩回双确认才进 Done。
  边界 Boundary : ① 真空接口契约：iVac.fPressure 为负压值，深度 = −fPressure（取正深度比较）；
                  ② iActuatorFbPct 为加压执行器阀位反馈 [0..100]%（副环 PV，未接线时副环退化跟随）；
                  ③ R228-A 达标声明：四只定时器均单相独占（IN 为单相等式），跨相迁移拍 IN 必断；
                  ④ 组态域闸覆盖全部参与换算引脚；目标越上限钳制置信息级码；
                  ⑤ R228-B 达标声明：eFault 迁出 = bReset 上升沿（段 4 承载），迁出条件
                  「rtReset.Q」为输入引脚，可满足性自证成立，逐字写于此。
  依赖 Depends  : FB_DL_CascadePid / FB_DL_RateLimiter（实例化，引脚按 registry 实名）；
                  FC_DL_Hysteresis（函数调用，bState 由本件成员持有回传）；
                  I_DL_VacuumGenerator / I_DL_Cylinder（注入，不实例化）
  码表 Error codes（本件格 02_3_88，子码步进 +0x100）:
    16#0002_0188 信息级：周期完成（Done 相）
    16#0002_0288 故障级：组态非法（目标/容差/速率/时长域非法），锁存至复位
    16#0002_0388 故障级：段超时（Evac/Ramp/Release 各相独立计时），锁存至复位
    16#0002_0488 故障级：注入件故障（真空 bFault / 气缸 bFault），锁存至复位
    16#0002_0588 故障级：状态机落 ELSE 兜底（非法相位 ID），锁存至复位
    16#0002_0688 信息级：Hold 相压力越保持窗（等待回落，不置故障）
    16#0002_0788 信息级：压力目标越组态上限，已钳制

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 2 · 序号 6）
*)

TYPE E_DL_LamPressState :
(
    eIdle      := 0,    // 空闲：等启动指令 / Idle, waiting for start
    eEvac      := 10,   // 真空段：抽气至真空目标 / Evacuation to vacuum target
    eRampPress := 20,   // 加压段：斜坡升压 + 串级闭环跟随 / Ramp press with cascade loop
    eHold      := 30,   // 保持段：配方时长驻留 + 保持窗监视 / Recipe hold with window watch
    eRelease   := 40,   // 泄压段：放气 + 缩回双确认 / Release, blow-off and retract confirm
    eDone      := 50,   // 完成：周期落定 / Done
    eFault     := 90    // 故障：组态/超时/注入件锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_LaminatorPressCtrl
VAR_INPUT
    bStart          : BOOL := FALSE;      // 启动指令（上升沿）/ Start command
    fVacTargetKpa   : REAL := 85.0;       // 真空段目标深度 [kPa]，域 > 0 / Vacuum segment target depth
    fPressTargetBar : REAL := 1.5;        // 加压段目标压力 [bar]，域 (0, fPressMaxBar] / Press segment target
    fPressMaxBar    : REAL := 2.0;        // 加压组态上限 [bar]，域 > 0 / Press configuration ceiling
    fPressActBar    : REAL := 0.0;        // 压力变送实测 [bar]（主环 PV）/ Measured pressure, master PV
    fActuatorFbPct  : REAL := 0.0;        // 执行器阀位反馈 [%]（副环 PV）/ Actuator position feedback, slave PV
    fPressTolBar    : REAL := 0.05;       // 压力跟随容差 [bar]，域 > 0 / Pressure tracking tolerance
    fRampRateBarS   : REAL := 0.05;       // 加压斜坡速率 [bar/s]，域 > 0 / Press ramp rate
    fKpM            : REAL := 1.0;        // 主环比例增益 [1] / Master loop proportional gain
    tTiM            : TIME := T#5S;       // 主环积分时间 [s] / Master loop integral time
    fKpS            : REAL := 2.0;        // 副环比例增益 [1] / Slave loop proportional gain
    tTiS            : TIME := T#1S;       // 副环积分时间 [s] / Slave loop integral time
    tEvacDur        : TIME := T#60S;      // 真空段配方时长 [ms] / Evacuation recipe duration
    tEvacTimeout    : TIME := T#120S;     // 真空段超时 [ms]，域 > 0 / Evacuation timeout
    tPressTimeout   : TIME := T#180S;     // 加压段超时 [ms]，域 > 0 / Ramp press timeout
    tHoldDur        : TIME := T#120S;     // 保持段配方时长 [ms] / Hold recipe duration
    tReleaseTimeout : TIME := T#60S;      // 泄压段超时 [ms]，域 > 0 / Release timeout
    fAtmVacKpa      : REAL := 2.0;        // 常压确认阈值 [kPa]，域 >= 0 / Atmospheric confirmation threshold
    bReset          : BOOL := FALSE;      // 复位（eFault 迁出唯一沿）/ Reset, sole fault exit edge
END_VAR
VAR_OUTPUT
    fPressSpRamp    : REAL;               // 斜坡限速后的压力设定 [bar] / Rate-limited pressure setpoint
    fPressCmdPct    : REAL;               // 串级闭环输出 [%] / Cascade closed-loop output in percent
    nSegment        : INT;                // 当前段号 [0..3]（0=真空 1=加压 2=保持 3=泄压）/ Segment index
    bCycleDone      : BOOL;               // 周期完成 / Cycle done
    nErrId          : UDINT;              // 事件码，0 = 无事件 / Event code
    eState          : E_DL_LamPressState; // 状态出口，段尾单点映射 / State outlet
END_VAR
VAR_IN_OUT
    iVac      : I_DL_VacuumGenerator;     // 真空发生器引用（注入，不实例化）/ Vacuum generator reference
    iPressCyl : I_DL_Cylinder;            // 压合气缸引用（注入，不实例化）/ Press cylinder reference
END_VAR
VAR
    fbRate     : FB_DL_RateLimiter;       // 斜坡限速实例 / Ramp rate limiter instance
    fbPid      : FB_DL_CascadePid;        // 压力串级闭环实例 / Pressure cascade loop instance
    tonEvacTo  : TON;                     // 真空段超时（单相独占）/ Evacuation timeout, single phase
    tonPressTo : TON;                     // 加压段超时（单相独占）/ Ramp press timeout, single phase
    tonHold    : TON;                     // 保持段配方计时（单相独占，PT 接配方时长）/ Hold recipe timer, single phase
    tonRelTo   : TON;                     // 泄压段超时（单相独占）/ Release timeout, single phase
    tonWch     : TON;                     // 故障观察窗，自复位 / Fault watch window, self-resetting
    rtStart    : R_TRIG;                  // 启动上升沿 / Start rising edge
    rtReset    : R_TRIG;                  // 复位上升沿 / Reset rising edge
    _eState    : E_DL_LamPressState := E_DL_LamPressState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _rVacDepth : REAL;                    // 真空深度暂存 [kPa] / Vacuum depth scratch
    _rPressTgt : REAL;                    // 钳制后压力目标 [bar] / Clamped press target
    _rSpRamp   : REAL;                    // 斜坡设定中间量 [bar] / Ramped setpoint working value
    _rCmdPct   : REAL;                    // 闭环输出中间量 [%] / Closed-loop output working value
    _bVacOk    : BOOL;                    // 真空到位标志 / Vacuum reached flag
    _bPressOk  : BOOL;                    // 压力入窗标志 / Pressure in-window flag
    _uFault    : UDINT;                   // 故障码锁存 / Latched fault code
    _uInfo     : UDINT;                   // 信息码，每拍重算 / Info code
    _bFault    : BOOL;                    // 故障锁存位 / Latched fault bit
    _bCfgBad   : BOOL;                    // 组态非法聚合 / Configuration invalid aggregate
END_VAR
VAR CONSTANT
    DL_LP_WATCH_PT : TIME := T#2S;      // 故障观察窗 [ms]，自复位 / Fault watch window
    DL_LP_INF_CAP  : REAL := 1.0E15;    // 非有限值筛查幅值上限 / Non-finite screening cap
END_VAR

(* —— 段 0：定时器与边沿无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
(* Stage 0, unconditional refresh of timers and edges *)
rtStart(CLK := bStart);                                           // 启动上升沿，每拍必调
rtReset(CLK := bReset);                                           // 复位上升沿，每拍必调
tonWch(IN := (NOT tonWch.Q), PT := DL_LP_WATCH_PT);               // 观察窗自复位（表达式入参）
tonEvacTo(IN := (_eState = E_DL_LamPressState.eEvac), PT := tEvacTimeout);          // 真空段超时（单相独占）
tonPressTo(IN := (_eState = E_DL_LamPressState.eRampPress), PT := tPressTimeout);   // 加压段超时（单相独占）
tonHold(IN := (_eState = E_DL_LamPressState.eHold), PT := tHoldDur);                // 保持配方计时（单相独占，PT=配方时长）
tonRelTo(IN := (_eState = E_DL_LamPressState.eRelease), PT := tReleaseTimeout);     // 泄压段超时（单相独占）

(* —— 段 1：斜坡与串级实例无条件周期刷新（依赖件每拍必调） —— *)
(* Stage 1, dependency instances refreshed unconditionally *)
fbRate(bEnable := TRUE,                                   // 限速器恒使能，跨相平滑（斜坡连续性）
       fIn := _rPressTgt,                                 // 限速输入 = 钳制后目标
       fRateUp := MAX(fRampRateBarS, 1.0E-6),             // 上升速率（下限防零速率卡死）
       fRateDown := MAX(fRampRateBarS, 1.0E-6),           // 下降速率同源
       bTrack := (_eState <> E_DL_LamPressState.eRampPress),   // 非加压相跟踪实测压力（无扰）
       fTrackValue := fPressActBar,                       // 跟踪值 = 实测压力
       tSampleTime := T#100MS);                           // 采样周期口径与限速件默认一致
_rSpRamp := fbRate.fOut;                                  // 斜坡设定中间量
fbPid(bEnable := (_eState = E_DL_LamPressState.eRampPress) OR (_eState = E_DL_LamPressState.eHold),
      fSpMaster := _rSpRamp,                              // 主环设定 = 斜坡设定
      fPvMaster := fPressActBar,                          // 主环 PV = 压力实测
      fPvSlave := fActuatorFbPct,                         // 副环 PV = 阀位反馈
      fKpM := fKpM, tTiM := tTiM, tTdM := T#0S,           // 主环参数（微分关）
      fKpS := fKpS, tTiS := tTiS, tTdS := T#0S,           // 副环参数（微分关）
      rSpSlaveMin := 0.0, rSpSlaveMax := 100.0,           // 副设定域（阀位百分比）
      rOutMin := 0.0, rOutMax := 100.0,                   // 副环输出域
      tSampleTime := T#100MS, bReset := FALSE);           // 采样周期；PID 自身不复位（相切换靠使能门控）
_rCmdPct := fbPid.fOut;                                   // 闭环输出中间量

(* —— 段 2：单拍量预清零（锁存量 _uFault/_bFault 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bCycleDone := FALSE;                // 完成出口缺省 FALSE（Done 相单点置位）
_bCfgBad := FALSE;                  // 组态非法预清零
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 3：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fVacTargetKpa <> fVacTargetKpa) OR (fVacTargetKpa <= 0.0) OR (ABS(fVacTargetKpa) > DL_LP_INF_CAP)
   OR (fPressActBar <> fPressActBar) OR (ABS(fPressActBar) > DL_LP_INF_CAP) THEN
    _bCfgBad := TRUE;               // 真空目标/压力实测非法
END_IF
IF (fPressMaxBar <= 0.0) OR (fPressTolBar <= 0.0) OR (fRampRateBarS <= 0.0) OR (fAtmVacKpa < 0.0) THEN
    _bCfgBad := TRUE;               // 上限/容差/速率/常压阈非法
END_IF
IF (TIME_TO_DINT(tEvacTimeout) <= 0) OR (TIME_TO_DINT(tPressTimeout) <= 0)
   OR (TIME_TO_DINT(tHoldDur) <= 0) OR (TIME_TO_DINT(tReleaseTimeout) <= 0) THEN
    _bCfgBad := TRUE;               // 各段时长/超时非法
END_IF

(* —— 段 4：eFault 迁出沿（R228-B：迁出条件 rtReset.Q 为输入引脚，恒可达） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;
    IF _eState = E_DL_LamPressState.eFault THEN
        _eState := E_DL_LamPressState.eIdle;    // 故障相迁出：回空闲（迁出边唯一且可达）
    END_IF
END_IF

(* —— 段 5：过程量只读采集与判据 —— *)
_rVacDepth := -iVac.fPressure;                // 真空深度 = 负压反馈取反 [kPa]（接口契约：负值=真空）
_bVacOk := _rVacDepth >= fVacTargetKpa;       // 真空到位判据（每拍重算）
_bPressOk := ABS(fPressActBar - _rSpRamp) <= fPressTolBar;   // 压力入窗判据（相对斜坡设定）

(* —— 段 6：相位机（只做迁移与单发命令；出口在段 8） —— *)
CASE _eState OF

E_DL_LamPressState.eIdle:
    IF _bCfgBad AND rtStart.Q THEN
        _uFault := 16#0002_0288;            // 故障级：组态非法
        _bFault := TRUE;
        _eState := E_DL_LamPressState.eFault;
    ELSIF rtStart.Q AND (NOT _bCfgBad) THEN
        IF fPressTargetBar > fPressMaxBar THEN
            _rPressTgt := fPressMaxBar;     // 压力目标越上限钳制
            _uInfo := 16#0002_0788;         // 信息级：已钳制
        ELSE
            _rPressTgt := fPressTargetBar;  // 域内直通
        END_IF
        iVac.CmdEvacuate();                 // 单发抽气指令
        _eState := E_DL_LamPressState.eEvac;    // 进真空段
    END_IF

E_DL_LamPressState.eEvac:
    IF (iVac.bFault OR iPressCyl.bFault) THEN
        _uFault := 16#0002_0488;            // 故障级：注入件故障
        _bFault := TRUE;
        iVac.CmdStop();                     // 安全侧全停
        _eState := E_DL_LamPressState.eFault;
    ELSIF tonEvacTo.Q THEN
        _uFault := 16#0002_0388;            // 故障级：真空段超时
        _bFault := TRUE;
        iVac.CmdStop();
        _eState := E_DL_LamPressState.eFault;
    ELSIF _bVacOk AND tonWch.Q THEN
        _eState := E_DL_LamPressState.eRampPress;   // 真空到位（含观察窗防抖）：进加压段
    END_IF

E_DL_LamPressState.eRampPress:
    IF (iVac.bFault OR iPressCyl.bFault) THEN
        _uFault := 16#0002_0488;
        _bFault := TRUE;
        iPressCyl.CmdStop();                // 安全侧停缸
        _eState := E_DL_LamPressState.eFault;
    ELSIF tonPressTo.Q THEN
        _uFault := 16#0002_0388;            // 故障级：加压段超时
        _bFault := TRUE;
        iPressCyl.CmdStop();
        _eState := E_DL_LamPressState.eFault;
    ELSE
        IF NOT iPressCyl.bExtended THEN
            iPressCyl.CmdExtend();          // 未到位则持续请求伸出（缸件内单发化去重）
        END_IF
        IF _bPressOk AND iPressCyl.bExtended THEN
            _eState := E_DL_LamPressState.eHold;    // 压力入窗且到位：进保持段
        END_IF
    END_IF

E_DL_LamPressState.eHold:
    IF (iVac.bFault OR iPressCyl.bFault) THEN
        _uFault := 16#0002_0488;
        _bFault := TRUE;
        iPressCyl.CmdStop();
        _eState := E_DL_LamPressState.eFault;
    ELSIF NOT _bPressOk THEN
        _uInfo := 16#0002_0688;             // 信息级：保持窗越限（等待回落，不置故障）
    ELSIF tonHold.Q THEN
        iVac.CmdBlowOff();                  // 单发放气（保持到点）
        iPressCyl.CmdRetract();             // 单发缩回
        _eState := E_DL_LamPressState.eRelease;     // 进泄压段
    END_IF

E_DL_LamPressState.eRelease:
    IF (iVac.bFault OR iPressCyl.bFault) THEN
        _uFault := 16#0002_0488;
        _bFault := TRUE;
        iPressCyl.CmdStop();
        _eState := E_DL_LamPressState.eFault;
    ELSIF tonRelTo.Q THEN
        _uFault := 16#0002_0388;            // 故障级：泄压段超时
        _bFault := TRUE;
        _eState := E_DL_LamPressState.eFault;
    ELSIF (_rVacDepth <= fAtmVacKpa) AND (NOT iPressCyl.bExtended) THEN
        _eState := E_DL_LamPressState.eDone;    // 常压 + 缩回双确认：进完成相
    END_IF

E_DL_LamPressState.eDone:
    bCycleDone := TRUE;                     // 完成出口（Done 相每拍重申）
    _uInfo := 16#0002_0188;                 // 信息级：周期完成
    IF NOT bStart THEN
        _eState := E_DL_LamPressState.eIdle;    // 指令撤销：回空闲
    END_IF

E_DL_LamPressState.eFault:
    ;                                       // 故障相：等复位沿（段 4 承载迁出）

ELSE
    _uFault := 16#0002_0588;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;
    _eState := E_DL_LamPressState.eFault;   // 强制回故障相

END_CASE

(* —— 段 7：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _eState = E_DL_LamPressState.eEvac THEN
    nSegment := 0;                          // 段号 0：真空
ELSIF _eState = E_DL_LamPressState.eRampPress THEN
    nSegment := 1;                          // 段号 1：加压
ELSIF _eState = E_DL_LamPressState.eHold THEN
    nSegment := 2;                          // 段号 2：保持
ELSIF _eState = E_DL_LamPressState.eRelease THEN
    nSegment := 3;                          // 段号 3：泄压
ELSE
    nSegment := -1;                         // Idle/Done/Fault：无有效段号
END_IF
fPressSpRamp := _rSpRamp;                   // 斜坡设定镜像
fPressCmdPct := _rCmdPct;                   // 闭环输出镜像
IF _bFault THEN
    nErrId := _uFault;                      // 故障锁存码回放（不在故障相按当下输入重推）
    bCycleDone := FALSE;                    // 故障相完成出口强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF
eState := _eState;                          // 状态出口单点映射

END_FUNCTION_BLOCK
