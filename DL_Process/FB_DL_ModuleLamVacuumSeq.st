(*
  FB_DL_ModuleLamVacuumSeq  —  组件层压真空顺控（抽气-加热-加压-放气）/ Module laminator vacuum sequence
  分类 Category : DL_Process
  码位 Code     : 16#06_0_B5
  版本 Version  : 1.0.2
  来源 Source   : t2-7-packml — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : clean-room 实现，层压工艺 PackML 段序公开语义借鉴，未复制任何源码行（RESUME 承接 R36 §4 #20 规格）
                  （段序语义对齐 FB_DL_StepSequencer，不实例化；三接口契约按 I_DL_* 真实成员名调用）
  功能 Function : 1) 四段顺控 Evac→Heat→Press→Vent，每段带 tSegmentTimeout 超时升级；
                  2) 加压段须真空度与温度双到位才允许升压（联锁内置，规格强制）；
                  3) 放气段结束须真空度回到常压确认（fVacKpa <= fAtmVacKpa）才进 Done；
                  4) 真空深度出口 fVacKpa = −iVac.fPressure（接口契约为负压值，出口取正深度）。
  边界 Boundary : ① 任一注入接口未装配校验由上层装配点承载（库内既有体例，__ISVALIDREF 为禁用项）；
                  ② 注入件 bFault（真空/温区/气缸）判故障升级；
                  ③ fPressTargetBar 超组态上限 fPressMaxBar 钳制并置信息码；配方四段全 0 判组态错；
                  ④ CASE 全态覆盖 + ELSE 兜底置 Fault；
                  ⑤ 解除式自证：bSegmentTimeoutFault 解除 = bReset 上升沿 AND eState = Idle；Idle 可达路径 =
                     每段正常推进（Evac→Heat→Press→Vent→Done→Idle）+ 超时 Fault 经 bReset 回 Idle，两条均给出；
                  ⑥ 段推进单发命令：各相进入拍单发一次（_bCmdLatch 承载，防重复下发）。
  依赖 Depends  : I_DL_VacuumGenerator / I_DL_TemperatureZone / I_DL_Cylinder（注入，不实例化）；
                  段序语义对齐 FB_DL_StepSequencer（已注册，不实例化）
  码表 Error codes（本件格 06_0_B5，子码步进 +0x100）:
    16#0006_01B5 信息级：周期完成（Done 相）
    16#0006_02B5 故障级：组态非法（目标 <= 0 / 配方全 0 / 超时 <= 0 / 上限 <= 0），锁存至复位
    16#0006_03B5 故障级：段超时升级（锁存，解除 = bReset 上升沿经 eFault 相迁出回 eIdle）
    16#0006_04B5 信息级：加压段真空联锁未满足（等待，不置故障）
    16#0006_05B5 故障级：注入件故障（真空/温区/气缸 bFault），锁存至复位
    16#0006_06B5 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0006_07B5 信息级：压力目标越上限，已钳制

R39 返修（R38 终审挂账闭环，v1.0.2）: ① tonSeg PT 误接 tSegmentTimeout → 拆分为四相独立配方 TON
  （tonEvac/tonHeat/tonPress/tonVent，PT 各接本段配方时长，IN 单相等式，跨相迁移拍必断，R228-A 达标）；
  ② tonSegMax 跨相不复位 → 同步拆分为四相独立超时 TON（tonEvacTo/tonHeatTo/tonPressTo/tonVentTo）；
  ③ eFault 无迁出 → eFault 相新增 bReset 上升沿迁出边回 eIdle（迁出条件 = 输入引脚 rtReset.Q，恒可达）。
  修订历史 Revision :
    2026-11-19  v1.0.2  R39 返修：配方时长接入 + 相独立超时 + eFault 迁出边（R38 挂账三项闭环）
    2026-11-18  v1.0.0  R38 首版
*)

TYPE E_DL_LamPhase :
(
    eIdle  := 0,     // 空闲：等启动指令 / Idle, waiting for start
    eEvac  := 10,    // 抽气段 / Evacuation segment
    eHeat  := 20,    // 加热段 / Heating segment
    ePress := 30,    // 加压段（真空+温度双联锁）/ Pressing segment, dual interlock
    eVent  := 40,    // 放气段 / Venting segment
    eDone  := 50,    // 完成：常压确认落定 / Done, atmospheric confirmed
    eFault := 90     // 故障：组态/超时/注入件锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_ModuleLamVacuumSeq
VAR_INPUT
    bStart          : BOOL := FALSE;      // 启动指令（上升沿）/ Start command
    fVacTargetKpa   : REAL := 85.0;       // 真空目标深度 [kPa]，域 > 0 / Vacuum target depth
    fPressTargetBar : REAL := 1.5;        // 加压目标 [bar]，域 (0, fPressMaxBar] / Press target
    fPressMaxBar    : REAL := 2.0;        // 加压组态上限 [bar]，域 > 0 / Press ceiling
    fTempTargetC    : REAL := 145.0;      // 加热目标温度 [°C]，域 > 0 / Heating target temperature
    fAtmVacKpa      : REAL := 2.0;        // 常压确认阈值 [kPa]，域 >= 0 / Atmospheric confirmation threshold
    atEvacMs        : TIME := T#60S;      // 抽气段配方时长 [ms] / Evacuation recipe duration
    atHeatMs        : TIME := T#180S;     // 加热段配方时长 [ms] / Heating recipe duration
    atPressMs       : TIME := T#300S;     // 加压段配方时长 [ms] / Pressing recipe duration
    atVentMs        : TIME := T#30S;      // 放气段配方时长 [ms] / Venting recipe duration
    tSegmentTimeout : TIME := T#420S;     // 单段超时 [ms]，域 > 0 / Segment timeout
    bReset          : BOOL := FALSE;      // 复位（超时/故障解除路径之一）/ Reset
END_VAR
VAR_OUTPUT
    bCycleDone            : BOOL;         // 周期完成 / Cycle done
    bSegmentTimeoutFault  : BOOL;         // 段超时故障锁存（解除 = bReset AND Idle）/ Segment timeout latch
    nSegment              : INT;          // 当前段号 [0..3]（0=抽 1=热 2=压 3=放）/ Segment index
    fVacKpa               : REAL;         // 真空深度出口 [kPa]（取正深度）/ Vacuum depth outlet
    nErrId                : UDINT;        // 事件码，0 = 无事件 / Event code
    eState                : E_DL_LamPhase;// 状态出口，段尾单点映射 / State outlet
END_VAR
VAR_IN_OUT
    iVac      : I_DL_VacuumGenerator;     // 真空发生器引用（注入，不实例化）/ Vacuum reference
    iTempZone : I_DL_TemperatureZone;     // 温区引用（注入，不实例化）/ Temperature zone reference
    iPressCyl : I_DL_Cylinder;            // 压合气缸引用（注入，不实例化）/ Press cylinder reference
END_VAR
VAR
    tonEvac     : TON;                    // 抽气段配方计时（单相独占，PT=配方时长）/ Evacuation recipe timer
    tonHeat     : TON;                    // 加热段配方计时（单相独占，PT=配方时长）/ Heating recipe timer
    tonPress    : TON;                    // 加压段配方计时（单相独占，PT=配方时长）/ Pressing recipe timer
    tonVent     : TON;                    // 放气段配方计时（单相独占，PT=配方时长）/ Venting recipe timer
    tonEvacTo   : TON;                    // 抽气段超时（单相独占）/ Evacuation timeout
    tonHeatTo   : TON;                    // 加热段超时（单相独占）/ Heating timeout
    tonPressTo  : TON;                    // 加压段超时（单相独占）/ Pressing timeout
    tonVentTo   : TON;                    // 放气段超时（单相独占）/ Venting timeout
    tonFaultWch : TON;                    // 故障观察窗，自复位 / Fault watch window, self-resetting
    rtStart     : R_TRIG;                 // 启动上升沿 / Start rising edge
    rtReset     : R_TRIG;                 // 复位上升沿 / Reset rising edge
    _eState     : E_DL_LamPhase := E_DL_LamPhase.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bCmdLatch  : BOOL;                   // 本相命令已单发标志 / Phase command one-shot latch
    _rPressTgt  : REAL;                   // 钳制后压力目标 [bar] / Clamped press target
    _rTempAct   : REAL;                   // 温区实测温度 [°C] / Zone actual temperature
    _rVacDepth  : REAL;                   // 真空深度暂存 [kPa] / Vacuum depth scratch
    _bVacOk     : BOOL;                   // 真空到位标志 / Vacuum in-position flag
    _bTempOk    : BOOL;                   // 温度到位标志 / Temperature in-position flag
    _bToL       : BOOL;                   // 段超时锁存保持量 / Segment timeout latch
    _uFault     : UDINT;                  // 故障码锁存 / Latched fault code
    _uInfo      : UDINT;                  // 信息码，每拍重算 / Info code
    _bFault     : BOOL;                   // 故障锁存位 / Latched fault bit
    _bCfgBad    : BOOL;                   // 组态非法聚合 / Configuration invalid aggregate
END_VAR
VAR CONSTANT
    DL_SEG_EVAC  : INT := 0;    // 段号：抽气 / Segment index evacuation
    DL_SEG_HEAT  : INT := 1;    // 段号：加热 / Segment index heating
    DL_SEG_PRESS : INT := 2;    // 段号：加压 / Segment index pressing
    DL_SEG_VENT  : INT := 3;    // 段号：放气 / Segment index venting
    DL_WATCH_PT  : TIME := T#2S;   // 故障观察窗 [ms]，自复位 / Fault watch window
END_VAR

(* —— 段 0：定时器与边沿无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtStart(CLK := bStart);                                          // 启动上升沿，每拍必调
rtReset(CLK := bReset);                                          // 复位上升沿，每拍必调
tonFaultWch(IN := (NOT tonFaultWch.Q), PT := DL_WATCH_PT);       // 观察窗自复位（表达式入参）
tonEvac(IN := (_eState = E_DL_LamPhase.eEvac), PT := atEvacMs);      // 抽气配方计时（单相独占，PT=配方时长）
tonHeat(IN := (_eState = E_DL_LamPhase.eHeat), PT := atHeatMs);      // 加热配方计时（单相独占，PT=配方时长）
tonPress(IN := (_eState = E_DL_LamPhase.ePress), PT := atPressMs);   // 加压配方计时（单相独占，PT=配方时长）
tonVent(IN := (_eState = E_DL_LamPhase.eVent), PT := atVentMs);      // 放气配方计时（单相独占，PT=配方时长）
tonEvacTo(IN := (_eState = E_DL_LamPhase.eEvac), PT := tSegmentTimeout);    // 抽气段超时（单相独占）
tonHeatTo(IN := (_eState = E_DL_LamPhase.eHeat), PT := tSegmentTimeout);    // 加热段超时（单相独占）
tonPressTo(IN := (_eState = E_DL_LamPhase.ePress), PT := tSegmentTimeout);  // 加压段超时（单相独占）
tonVentTo(IN := (_eState = E_DL_LamPhase.eVent), PT := tSegmentTimeout);    // 放气段超时（单相独占）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_bToL/_bCmdLatch 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;         // 信息码每拍重算
bCycleDone := FALSE;            // 完成出口缺省 FALSE（Done 相单点置位）
_bCfgBad := FALSE;              // 组态非法预清零
nErrId := 16#0000_0000;         // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fVacTargetKpa <> fVacTargetKpa) OR (fVacTargetKpa <= 0.0)
   OR (fTempTargetC <> fTempTargetC) OR (fTempTargetC <= 0.0) THEN
    _bCfgBad := TRUE;           // 目标非法
END_IF
IF (fPressMaxBar <= 0.0) OR (fAtmVacKpa < 0.0) OR (TIME_TO_DINT(tSegmentTimeout) <= 0) THEN
    _bCfgBad := TRUE;           // 上限/常压阈/超时非法
END_IF
IF (TIME_TO_DINT(atEvacMs) <= 0) AND (TIME_TO_DINT(atHeatMs) <= 0)
   AND (TIME_TO_DINT(atPressMs) <= 0) AND (TIME_TO_DINT(atVentMs) <= 0) THEN
    _bCfgBad := TRUE;           // 配方四段全 0（规格强制）
END_IF

(* —— 段 3：复位沿（超时/故障解除式：bReset AND eState = Idle） —— *)
IF rtReset.Q THEN
    IF _eState = E_DL_LamPhase.eIdle THEN
        _bFault := FALSE;       // 清故障锁存位（Idle 可达，规格解除式）
        _uFault := 16#0000_0000;
        _bToL   := FALSE;       // 超时锁存清零
        bSegmentTimeoutFault := FALSE;
    END_IF
END_IF

(* —— 段 4：过程量只读采集与换算 —— *)
_rTempAct := iTempZone.fTempActual;          // 温区实测 [°C]
_rVacDepth := -iVac.fPressure;               // 真空深度 = 负压反馈取反 [kPa]（接口契约：负值=真空）
fVacKpa := _rVacDepth;                       // 深度出口（正深度）
_bVacOk := _rVacDepth >= fVacTargetKpa;      // 真空到位判据（每拍重算）
_bTempOk := ABS(_rTempAct - fTempTargetC) <= MAX(fTempTargetC * 0.02, 2.0);   // 温度到位（±2% 或 ±2°C 宽容）

(* —— 段 5：相位机（只做迁移与单发命令；出口在段 8） —— *)
CASE _eState OF

E_DL_LamPhase.eIdle:
    IF _bCfgBad THEN
        _uFault := 16#0006_02B5;            // 故障级：组态非法
        _bFault := TRUE;                    // 锁存（复位沿 + Idle 可清）
        _eState := E_DL_LamPhase.eFault;
    ELSIF rtStart.Q THEN
        IF fPressTargetBar > fPressMaxBar THEN
            _rPressTgt := fPressMaxBar;     // 压力目标越上限钳制
            _uInfo := 16#0006_07B5;         // 信息级：已钳制
        ELSE
            _rPressTgt := fPressTargetBar;  // 域内直通
        END_IF
        _bCmdLatch := FALSE;                // 命令单发标志复位
        iVac.CmdEvacuate();                 // 单发抽气指令
        iTempZone.CmdEnable(bOn := TRUE);   // 温区投运
        _bCmdLatch := TRUE;                 // 单发标志
        _eState := E_DL_LamPhase.eEvac;     // 进抽气段
    END_IF

E_DL_LamPhase.eEvac:
    IF (iVac.bFault OR iTempZone.bFault OR iPressCyl.bFault) THEN
        _uFault := 16#0006_05B5;            // 故障级：注入件故障
        _bFault := TRUE;
        iVac.CmdStop();                     // 安全侧全停
        iTempZone.CmdEnable(bOn := FALSE);
        _eState := E_DL_LamPhase.eFault;
    ELSIF tonEvacTo.Q THEN
        _bToL := TRUE;                      // 超时锁存
        _uFault := 16#0006_03B5;            // 故障级：段超时升级
        _bFault := TRUE;
        iVac.CmdStop();
        iTempZone.CmdEnable(bOn := FALSE);
        _eState := E_DL_LamPhase.eFault;
    ELSIF _bVacOk AND (TIME_TO_DINT(atEvacMs) <= 0 OR tonEvac.Q) THEN
        iTempZone.SetSetpoint(fTemp := fTempTargetC);   // 单发设定点
        _eState := E_DL_LamPhase.eHeat;     // 进加热段（正常推进，Idle 路径之一）
        _bCmdLatch := FALSE;
    END_IF

E_DL_LamPhase.eHeat:
    IF (iVac.bFault OR iTempZone.bFault OR iPressCyl.bFault) THEN
        _uFault := 16#0006_05B5;
        _bFault := TRUE;
        iVac.CmdStop();
        iTempZone.CmdEnable(bOn := FALSE);
        _eState := E_DL_LamPhase.eFault;
    ELSIF tonHeatTo.Q THEN
        _bToL := TRUE;
        _uFault := 16#0006_03B5;
        _bFault := TRUE;
        iVac.CmdStop();
        iTempZone.CmdEnable(bOn := FALSE);
        _eState := E_DL_LamPhase.eFault;
    ELSIF _bTempOk AND (TIME_TO_DINT(atHeatMs) <= 0 OR tonHeat.Q) THEN
        iPressCyl.CmdExtend();              // 单发升压
        _eState := E_DL_LamPhase.ePress;    // 进加压段
        _bCmdLatch := FALSE;
    END_IF

E_DL_LamPhase.ePress:
    IF (iVac.bFault OR iTempZone.bFault OR iPressCyl.bFault) THEN
        _uFault := 16#0006_05B5;
        _bFault := TRUE;
        iPressCyl.CmdStop();
        iVac.CmdStop();
        iTempZone.CmdEnable(bOn := FALSE);
        _eState := E_DL_LamPhase.eFault;
    ELSIF tonPressTo.Q THEN
        _bToL := TRUE;
        _uFault := 16#0006_03B5;
        _bFault := TRUE;
        iPressCyl.CmdStop();
        iVac.CmdStop();
        iTempZone.CmdEnable(bOn := FALSE);
        _eState := E_DL_LamPhase.eFault;
    ELSIF NOT (_bVacOk AND _bTempOk) THEN
        _uInfo := 16#0006_04B5;             // 信息级：真空/温度双联锁未满足（等待，不置故障）
    ELSIF iPressCyl.bExtended AND (TIME_TO_DINT(atPressMs) <= 0 OR tonPress.Q) THEN
        iVac.CmdBlowOff();                  // 单发放气
        _eState := E_DL_LamPhase.eVent;     // 进放气段
        _bCmdLatch := FALSE;
    END_IF

E_DL_LamPhase.eVent:
    IF (iVac.bFault OR iTempZone.bFault OR iPressCyl.bFault) THEN
        _uFault := 16#0006_05B5;
        _bFault := TRUE;
        iVac.CmdStop();
        iTempZone.CmdEnable(bOn := FALSE);
        _eState := E_DL_LamPhase.eFault;
    ELSIF tonVentTo.Q THEN
        _bToL := TRUE;
        _uFault := 16#0006_03B5;
        _bFault := TRUE;
        iVac.CmdStop();
        iTempZone.CmdEnable(bOn := FALSE);
        _eState := E_DL_LamPhase.eFault;
    ELSIF (_rVacDepth <= fAtmVacKpa) AND (TIME_TO_DINT(atVentMs) <= 0 OR tonVent.Q) THEN
        iTempZone.CmdEnable(bOn := FALSE);  // 温区退出
        iPressCyl.CmdRetract();             // 压头缩回
        _eState := E_DL_LamPhase.eDone;     // 常压确认：进完成相
    END_IF

E_DL_LamPhase.eDone:
    bCycleDone := TRUE;                     // 完成出口（Done 相每拍重申）
    _uInfo := 16#0006_01B5;                 // 信息级：周期完成
    IF NOT bStart THEN
        _eState := E_DL_LamPhase.eIdle;     // 指令撤销：回空闲（Idle 可达路径：正常推进链末端）
    END_IF

E_DL_LamPhase.eFault:
    IF rtReset.Q THEN                       // 迁出边：bReset 上升沿（R228-B：输入引脚，恒可达）
        _bFault := FALSE;                   // 清故障锁存位
        _uFault := 16#0000_0000;            // 清锁存码
        _bToL   := FALSE;                   // 超时锁存清零
        bSegmentTimeoutFault := FALSE;      // 超时出口同步清除
        _eState := E_DL_LamPhase.eIdle;     // 迁出：回空闲（Idle 可达路径：故障迁出边）
    END_IF

ELSE
    _uFault := 16#0006_06B5;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_LamPhase.eFault;        // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _eState = E_DL_LamPhase.eEvac THEN
    nSegment := DL_SEG_EVAC;                // 段号 0：抽气
ELSIF _eState = E_DL_LamPhase.eHeat THEN
    nSegment := DL_SEG_HEAT;                // 段号 1：加热
ELSIF _eState = E_DL_LamPhase.ePress THEN
    nSegment := DL_SEG_PRESS;               // 段号 2：加压
ELSIF _eState = E_DL_LamPhase.eVent THEN
    nSegment := DL_SEG_VENT;                // 段号 3：放气
ELSE
    nSegment := -1;                         // Idle/Done/Fault：无有效段号
END_IF
bSegmentTimeoutFault := _bToL;              // 超时出口 = 锁存量（置位同拍不被抹）
IF _bFault THEN
    nErrId := _uFault;          // 故障锁存码回放（不在故障相按当下输入重推）
    bCycleDone := FALSE;        // 故障相完成出口强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;           // 信息码
END_IF
eState := _eState;              // 状态出口单点映射

END_FUNCTION_BLOCK
