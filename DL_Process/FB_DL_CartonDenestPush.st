(*
  FB_DL_CartonDenestPush  —  纸箱分离-推箱顺控 / Carton denesting and push sequence
  分类 Category : DL_Process
  码位 Code     : 16#06_0_B8
  段位说明      : R38 W7 预留 B6~BF 本轮正式启用，B7 格由 ElectrolyteFillCtrl 启用，本件启用 B8 格
  版本 Version  : 1.0.0
  来源 Source   : t2-7-packml — 成型上游分离供箱工艺待挖项
  溯源 Origin   : clean-room 实现，未复制任何源码行
                  （与 FB_DL_CartonErectSeq / CartonErectorStation 分工：那族管开箱成型，本件是成型上游的分离供箱）
  功能 Function : 1) 七相顺控 Idle→LevelChk→VacPick→SepLift→Push→PushRet→Drop→Done：
                  料位联锁 → 真空吸取顶箱 → 分离缸提升 → 推杆推箱 → 推杆缩回 → 落箱放行；
                  2) 双联锁内置：推箱须「真空保持 AND 箱在位」双确认，联锁不满足只等待不故障；
                  3) 双料位联锁：低料位且无高料位判料仓耗尽（信息级等待，不启动新周期）；
                  4) 段超时升级：五段各配独立超时 TON，超时锁故障（安全侧全停）。
  边界 Boundary : ① 真空接口契约：iEjector.fPressure 为负压值，吸取确认深度 = −fPressure；
                  ② 组态域闸覆盖全部参与换算引脚（R151）；
                  ③ R228-A 达标声明：五只超时 TON 均单相独占（IN 为单相等式），跨相迁移拍 IN 必断；
                  ④ R228-B 达标声明：eFault 迁出 = rtReset.Q（输入引脚，恒可达），逐字写于此；
                  ⑤ 气缸命令经 I_DL_Cylinder 方法单发下发（方法内受理去重，重复调用无害）；
                  ⑥ CASE 全态覆盖 + ELSE 兜底置 Fault。
  依赖 Depends  : I_DL_Cylinder（×2 注入：分离缸/推箱缸，不实例化）；
                  I_DL_VacuumGenerator（注入，不实例化；FB_DL_VacuumEjector 为典型实现）；
                  段序语义对齐 FB_DL_StepSequencer（已注册，不实例化）
  码表 Error codes（本件格 06_0_B8，子码步进 +0x100）:
    16#0006_01B8 信息级：供箱周期完成（Done 相）
    16#0006_02B8 故障级：组态非法（吸取深度/常压阈/超时域非法），锁存至复位
    16#0006_03B8 故障级：段超时升级（五段独立计时），锁存至复位
    16#0006_04B8 故障级：注入件故障（分离缸/推箱缸/真空 bFault），锁存至复位
    16#0006_05B8 信息级：料仓耗尽（低料位且无高料位，等待补料，不置故障）
    16#0006_06B8 信息级：推箱双联锁等待（真空/箱在位未齐，不置故障）
    16#0006_07B8 故障级：状态机落 ELSE 兜底（非法相位 ID）

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 4 · 序号 16）
*)

TYPE E_DL_DenestState :
(
    eIdle     := 0,    // 空闲：等启动指令 / Idle, waiting for start
    eLevelChk := 10,   // 料位检查：联锁判定 / Level check interlock
    eVacPick  := 20,   // 真空吸取：建立吸取真空 / Vacuum pick, establish holding vacuum
    eSepLift  := 30,   // 分离提升：分离缸伸出 / Separate lift, separator cylinder extend
    ePush     := 40,   // 推箱：推杆伸出（双联锁内） / Push, pusher extend under dual interlock
    ePushRet  := 50,   // 推杆缩回 / Pusher retract
    eDrop     := 60,   // 落箱：分离缸缩回 + 破真空 / Drop, separator retract and blow-off
    eDone     := 70,   // 完成：周期落定 / Done
    eFault    := 90    // 故障：组态/超时/注入件锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_CartonDenestPush
VAR_INPUT
    bStart       : BOOL := FALSE;      // 启动指令（上升沿）/ Start command
    bBoxAtPick   : BOOL := FALSE;      // 取箱位有箱反馈 [-] / Box present at pick position
    bBoxMagHigh  : BOOL := FALSE;      // 料仓高料位反馈 [-] / Magazine high-level feedback
    bBoxMagLow   : BOOL := FALSE;      // 料仓低料位反馈 [-] / Magazine low-level feedback
    fVacPickKpa  : REAL := 40.0;       // 吸取确认深度 [kPa]，域 > 0 / Pick confirmation vacuum depth
    fAtmVacKpa   : REAL := 5.0;        // 落箱常压确认阈 [kPa]，域 >= 0 / Drop atmospheric threshold
    tStepTimeout : TIME := T#5S;       // 单段超时 [ms]，域 > 0 / Per-step timeout
    bReset       : BOOL := FALSE;      // 复位（eFault 迁出唯一沿）/ Reset, sole fault exit edge
END_VAR
VAR_OUTPUT
    bCycleDone   : BOOL;               // 供箱周期完成 / Cycle done
    nStep        : INT;                // 当前步号 [0..4]（0=吸取 1=提升 2=推箱 3=缩回 4=落箱）/ Step index
    bPushPermit  : BOOL;               // 推箱双联锁满足 [-] / Push dual interlock satisfied
    bMagEmpty    : BOOL;               // 料仓耗尽指示 [-] / Magazine empty indicator
    nErrId       : UDINT;              // 事件码，0 = 无事件 / Event code
    eState       : E_DL_DenestState;   // 状态出口，段尾单点映射 / State outlet
END_VAR
VAR_IN_OUT
    iSepCyl   : I_DL_Cylinder;         // 分离缸引用（注入，不实例化）/ Separator cylinder reference
    iPushCyl  : I_DL_Cylinder;         // 推箱缸引用（注入，不实例化）/ Pusher cylinder reference
    iEjector  : I_DL_VacuumGenerator;  // 真空发生器引用（注入，不实例化）/ Vacuum generator reference
END_VAR
VAR
    tonVacTo  : TON;                   // 吸取段超时（单相独占）/ Pick timeout, single phase
    tonSepTo  : TON;                   // 提升段超时（单相独占）/ Lift timeout, single phase
    tonPushTo : TON;                   // 推箱段超时（单相独占）/ Push timeout, single phase
    tonRetTo  : TON;                   // 缩回段超时（单相独占）/ Retract timeout, single phase
    tonDropTo : TON;                   // 落箱段超时（单相独占）/ Drop timeout, single phase
    tonWch    : TON;                   // 故障观察窗，自复位 / Fault watch window, self-resetting
    rtStart   : R_TRIG;                // 启动上升沿 / Start rising edge
    rtReset   : R_TRIG;                // 复位上升沿 / Reset rising edge
    _eState   : E_DL_DenestState := E_DL_DenestState.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _rVacDep  : REAL;                  // 真空深度暂存 [kPa] / Vacuum depth scratch
    _bVacOk   : BOOL;                  // 吸取确认标志 / Pick confirmed flag
    _bVacRel  : BOOL;                  // 常压确认标志 / Atmospheric confirmed flag
    _uFault   : UDINT;                 // 故障码锁存 / Latched fault code
    _uInfo    : UDINT;                 // 信息码，每拍重算 / Info code
    _bFault   : BOOL;                  // 故障锁存位 / Latched fault bit
    _bCfgBad  : BOOL;                  // 组态非法聚合 / Configuration invalid aggregate
END_VAR
VAR CONSTANT
    DL_CDP_WATCH_PT : TIME := T#2S;   // 故障观察窗 [ms]，自复位 / Fault watch window
    DL_CDP_INF_CAP  : REAL := 1.0E15; // 非有限值筛查幅值上限 / Non-finite screening cap
END_VAR

(* —— 段 0：定时器与边沿无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtStart(CLK := bStart);                                                // 启动沿刷新，每拍必调
rtReset(CLK := bReset);                                                // 复位沿刷新，每拍必调
tonWch(IN := (NOT tonWch.Q), PT := DL_CDP_WATCH_PT);                   // 观察窗自复位（表达式入参）
tonVacTo(IN := (_eState = E_DL_DenestState.eVacPick), PT := tStepTimeout);   // 吸取超时（单相独占）
tonSepTo(IN := (_eState = E_DL_DenestState.eSepLift), PT := tStepTimeout);   // 提升超时（单相独占）
tonPushTo(IN := (_eState = E_DL_DenestState.ePush), PT := tStepTimeout);     // 推箱超时（单相独占）
tonRetTo(IN := (_eState = E_DL_DenestState.ePushRet), PT := tStepTimeout);   // 缩回超时（单相独占）
tonDropTo(IN := (_eState = E_DL_DenestState.eDrop), PT := tStepTimeout);     // 落箱超时（单相独占）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bCycleDone := FALSE;                // 完成出口缺省 FALSE（Done 相单点置位）
bPushPermit := FALSE;               // 双联锁出口缺省 FALSE（段 5 单点重写）
_bCfgBad := FALSE;                  // 组态非法预清零
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fVacPickKpa <> fVacPickKpa) OR (fVacPickKpa <= 0.0) OR (ABS(fVacPickKpa) > DL_CDP_INF_CAP)
   OR (fAtmVacKpa < 0.0) OR (TIME_TO_DINT(tStepTimeout) <= 0) THEN
    _bCfgBad := TRUE;               // 吸取深度/常压阈/超时非法
END_IF

(* —— 段 3：eFault 迁出沿（R228-B：rtReset.Q 为输入引脚，恒可达） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;
    IF _eState = E_DL_DenestState.eFault THEN
        _eState := E_DL_DenestState.eIdle;      // 故障相迁出：回空闲
    END_IF
END_IF

(* —— 段 4：过程量只读采集与判据 —— *)
_rVacDep := -iEjector.fPressure;                // 真空深度 = 负压反馈取反 [kPa]（接口契约：负值=真空）
_bVacOk := _rVacDep >= fVacPickKpa;             // 吸取确认（每拍重算）
_bVacRel := _rVacDep <= fAtmVacKpa;             // 常压确认（每拍重算）
bMagEmpty := bBoxMagLow AND (NOT bBoxMagHigh);  // 料仓耗尽派生（每拍重算）

(* —— 段 5：相位机（只做迁移与单发命令；出口在段 7） —— *)
CASE _eState OF

E_DL_DenestState.eIdle:
    IF rtStart.Q AND _bCfgBad THEN
        _uFault := 16#0006_02B8;            // 故障级：组态非法
        _bFault := TRUE;
        _eState := E_DL_DenestState.eFault;
    ELSIF rtStart.Q AND bMagEmpty THEN
        _uInfo := 16#0006_05B8;             // 信息级：料仓耗尽等待补料（不启动周期）
    ELSIF rtStart.Q AND (NOT _bCfgBad) THEN
        _eState := E_DL_DenestState.eLevelChk;  // 进料位检查相
    END_IF

E_DL_DenestState.eLevelChk:
    IF (iSepCyl.bFault OR iPushCyl.bFault OR iEjector.bFault) THEN
        _uFault := 16#0006_04B8;            // 故障级：注入件故障
        _bFault := TRUE;
        iEjector.CmdStop();                 // 安全侧全停
        _eState := E_DL_DenestState.eFault;
    ELSIF bMagEmpty THEN
        _uInfo := 16#0006_05B8;             // 信息级：料仓耗尽（退回空闲等补料）
        _eState := E_DL_DenestState.eIdle;
    ELSE
        iEjector.CmdEvacuate();             // 单发吸取指令
        _eState := E_DL_DenestState.eVacPick;   // 进吸取相
    END_IF

E_DL_DenestState.eVacPick:
    IF (iSepCyl.bFault OR iPushCyl.bFault OR iEjector.bFault) THEN
        _uFault := 16#0006_04B8;
        _bFault := TRUE;
        iEjector.CmdStop();
        _eState := E_DL_DenestState.eFault;
    ELSIF tonVacTo.Q THEN
        _uFault := 16#0006_03B8;            // 故障级：吸取段超时
        _bFault := TRUE;
        iEjector.CmdStop();
        _eState := E_DL_DenestState.eFault;
    ELSIF _bVacOk AND tonWch.Q THEN
        iSepCyl.CmdExtend();                // 单发提升指令
        _eState := E_DL_DenestState.eSepLift;   // 进提升相
    END_IF

E_DL_DenestState.eSepLift:
    IF (iSepCyl.bFault OR iPushCyl.bFault OR iEjector.bFault) THEN
        _uFault := 16#0006_04B8;
        _bFault := TRUE;
        iSepCyl.CmdStop();
        iEjector.CmdStop();
        _eState := E_DL_DenestState.eFault;
    ELSIF tonSepTo.Q THEN
        _uFault := 16#0006_03B8;            // 故障级：提升段超时
        _bFault := TRUE;
        iSepCyl.CmdStop();
        _eState := E_DL_DenestState.eFault;
    ELSIF iSepCyl.bExtended THEN
        _eState := E_DL_DenestState.ePush;  // 提升到位：进推箱相
    END_IF

E_DL_DenestState.ePush:
    bPushPermit := _bVacOk AND bBoxAtPick;  // 双联锁派生出口（每拍重算）
    IF (iSepCyl.bFault OR iPushCyl.bFault OR iEjector.bFault) THEN
        _uFault := 16#0006_04B8;
        _bFault := TRUE;
        iPushCyl.CmdStop();
        _eState := E_DL_DenestState.eFault;
    ELSIF tonPushTo.Q THEN
        _uFault := 16#0006_03B8;            // 故障级：推箱段超时
        _bFault := TRUE;
        iPushCyl.CmdStop();
        _eState := E_DL_DenestState.eFault;
    ELSIF NOT bPushPermit THEN
        _uInfo := 16#0006_06B8;             // 信息级：双联锁等待（不置故障）
    ELSE
        iPushCyl.CmdExtend();               // 联锁满足：单发推箱
        IF iPushCyl.bExtended THEN
            iPushCyl.CmdRetract();          // 推到位即单发缩回
            _eState := E_DL_DenestState.ePushRet;   // 进缩回相
        END_IF
    END_IF

E_DL_DenestState.ePushRet:
    IF (iSepCyl.bFault OR iPushCyl.bFault OR iEjector.bFault) THEN
        _uFault := 16#0006_04B8;
        _bFault := TRUE;
        iPushCyl.CmdStop();
        _eState := E_DL_DenestState.eFault;
    ELSIF tonRetTo.Q THEN
        _uFault := 16#0006_03B8;            // 故障级：缩回段超时
        _bFault := TRUE;
        iPushCyl.CmdStop();
        _eState := E_DL_DenestState.eFault;
    ELSIF iPushCyl.bRetracted THEN
        iSepCyl.CmdRetract();               // 单发分离缸缩回
        iEjector.CmdBlowOff();              // 单发破真空落箱
        _eState := E_DL_DenestState.eDrop;  // 进落箱相
    END_IF

E_DL_DenestState.eDrop:
    IF (iSepCyl.bFault OR iPushCyl.bFault OR iEjector.bFault) THEN
        _uFault := 16#0006_04B8;
        _bFault := TRUE;
        iSepCyl.CmdStop();
        _eState := E_DL_DenestState.eFault;
    ELSIF tonDropTo.Q THEN
        _uFault := 16#0006_03B8;            // 故障级：落箱段超时
        _bFault := TRUE;
        _eState := E_DL_DenestState.eFault;
    ELSIF iSepCyl.bRetracted AND _bVacRel THEN
        _eState := E_DL_DenestState.eDone;  // 缩回 + 常压双确认：进完成相
    END_IF

E_DL_DenestState.eDone:
    bCycleDone := TRUE;                     // 完成出口（Done 相每拍重申）
    _uInfo := 16#0006_01B8;                 // 信息级：周期完成
    IF NOT bStart THEN
        _eState := E_DL_DenestState.eIdle;  // 指令撤销：回空闲
    END_IF

E_DL_DenestState.eFault:
    ;                                       // 故障相：等复位沿（段 3 承载迁出）

ELSE
    _uFault := 16#0006_07B8;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;
    _eState := E_DL_DenestState.eFault;     // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _eState = E_DL_DenestState.eVacPick THEN
    nStep := 0;                             // 步号 0：吸取
ELSIF _eState = E_DL_DenestState.eSepLift THEN
    nStep := 1;                             // 步号 1：提升
ELSIF _eState = E_DL_DenestState.ePush THEN
    nStep := 2;                             // 步号 2：推箱
ELSIF _eState = E_DL_DenestState.ePushRet THEN
    nStep := 3;                             // 步号 3：缩回
ELSIF _eState = E_DL_DenestState.eDrop THEN
    nStep := 4;                             // 步号 4：落箱
ELSE
    nStep := -1;                            // Idle/LevelChk/Done/Fault：无有效步号
END_IF
IF _bFault THEN
    nErrId := _uFault;                      // 故障锁存码回放（不在故障相按当下输入重推）
    bCycleDone := FALSE;                    // 故障相完成出口强制 FALSE（安全侧）
    bPushPermit := FALSE;                   // 故障相联锁出口强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF
eState := _eState;                          // 状态出口单点映射

END_FUNCTION_BLOCK
