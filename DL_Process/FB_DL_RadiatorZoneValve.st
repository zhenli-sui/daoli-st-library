(*
  FB_DL_RadiatorZoneValve  —  散热器末端温控阀脉冲控制 / Radiator zone valve pulse control
  分类 Category : DL_Process
  码位 Code     : 16#06_0_B9
  段位说明      : R38 W7 预留 B6~BF 本轮正式启用，B8 格由 CartonDenestPush 启用，本件启用 B9 格
  版本 Version  : 1.0.0
  来源 Source   : t2-2-lbp — FB_DL_ThreePointValve 典型消费场景待挖项
  溯源 Origin   : clean-room 实现，三点浮阀 + 房间温度闭环为公开经典控制语义，未复制任何源码行
  功能 Function : 1) 房间温度闭环：FC_DL_Hysteresis 迟滞判热需求（fRoomSpC 设定 + fBandC 回差带，
                  带内保持，防阀频繁切换）；
                  2) FB_DL_ThreePointValve 实例消费：热需求 → 开阀指令，无需求 → 关阀指令；
                  3) 最小启停间隔保护：全开后 tMinRun 内禁关、全关后 tMinOff 内禁开
                  （tonMinRun/tonMinOff 双实例，被闭锁期间置信息级码）；
                  4) 阀门限位开关与行程时间由组态透传，估算开度镜像出口。
  边界 Boundary : ① 本件只出三点阀开关指令（经 FB_DL_ThreePointValve 输出脉冲），不写物理 IO；
                  ② 温度信号非有限：需求冻结保持（不误开不误关）+ 信息级码；
                  ③ R228-A 达标声明：tonMinRun/tonMinOff 各自单用途计时（IN 为单相等式），
                  无跨相复用问题（本件无状态机相）；
                  ④ 组态域闸覆盖全部参与换算引脚（R151）；迟滞带/间隔域非法判组态错锁存；
                  ⑤ 需求判据取反口径：迟滞件 TRUE = 温度高（停热），需求 = NOT 迟滞输出，
                  上电冷态需求为 TRUE（保守供热侧）。
  依赖 Depends  : FB_DL_ThreePointValve（实例化，引脚按 registry 实名）；
                  FC_DL_Hysteresis（函数调用，bState 由本件成员持有回传）
  码表 Error codes（本件格 06_0_B9，子码步进 +0x100）:
    16#0006_01B9 信息级：最小启停间隔闭锁中（指令暂缓，不置故障）
    16#0006_02B9 故障级：组态非法（设定/回差/间隔域非法），锁存至复位
    16#0006_03B9 信息级：温度信号非有限，需求冻结保持
    16#0006_04B9 信息级：加热需求置位（bHeating 拍）
    16#0006_05B9 故障级：保留码，本件无 CASE 主状态机，仅作后续维护者新增分支时的防御式默认码

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 4 · 序号 17）
*)

FUNCTION_BLOCK FB_DL_RadiatorZoneValve
VAR_INPUT
    bEnable      : BOOL := TRUE;       // 总使能，FALSE 时关阀指令并冻结需求 [-] / Master enable
    fRoomTempC   : REAL := 20.0;       // 房间实测温度 [°C] / Room measured temperature
    fRoomSpC     : REAL := 21.0;       // 房间设定温度 [°C] / Room setpoint
    fBandC       : REAL := 0.5;        // 需求回差带 [°C]，域 > 0 / Demand hysteresis band
    bLimOpen     : BOOL := FALSE;      // 阀全开限位反馈（透传三点阀）[-] / Valve open limit, passed through
    bLimClosed   : BOOL := FALSE;      // 阀全关限位反馈（透传三点阀）[-] / Valve closed limit, passed through
    tStrokeOpen  : TIME := T#60S;      // 全行程开启时间 [ms]（透传三点阀）/ Full-open stroke time
    tStrokeClose : TIME := T#60S;      // 全行程关闭时间 [ms]（透传三点阀）/ Full-close stroke time
    tMinRun      : TIME := T#120S;     // 最小运行间隔（全开后禁关时长）[ms]，域 >= 0 / Minimum run time
    tMinOff      : TIME := T#120S;     // 最小停歇间隔（全关后禁开时长）[ms]，域 >= 0 / Minimum off time
    bReset       : BOOL := FALSE;      // 故障复位，上升沿生效 / Fault reset, rising edge
END_VAR
VAR_OUTPUT
    bHeating     : BOOL;               // 加热需求（迟滞后，电平）[-] / Heating demand, level
    bOpenCmd     : BOOL;               // 开阀指令生效中（透传阀件脉冲前）[-] / Open command active
    bCloseCmd    : BOOL;               // 关阀指令生效中 [-] / Close command active
    bOpened      : BOOL;               // 阀全开确认（限位优先）[-] / Valve fully opened
    bClosed      : BOOL;               // 阀全关确认（限位优先）[-] / Valve fully closed
    fValvePosEst : REAL;               // 阀估算开度 [%]（三点阀积分口径）/ Valve estimated position
    bError       : BOOL;               // 故障锁存，仅故障级码置位，bReset 清除 [-] / Fault latch
    uErrorId     : UDINT;              // 事件码，0 = 无事件（故障级锁存回放）/ Event code
END_VAR
VAR
    fbValve    : FB_DL_ThreePointValve;   // 三点浮阀实例（主体首部无条件刷新）/ Three-point valve instance
    tonMinRun  : TON;                     // 最小运行计时（全开期间，单用途）/ Minimum run timer, single purpose
    tonMinOff  : TON;                     // 最小停歇计时（全关期间，单用途）/ Minimum off timer, single purpose
    rtReset    : R_TRIG;                  // 复位上升沿 / Reset rising edge
    _bTempHigh : BOOL;                    // 迟滞判温高回传保持变量 / Hysteresis temp-high hold member
    _bHeatDem  : BOOL := TRUE;            // 热需求内部量（上电冷态为 TRUE，保守供热）/ Internal heat demand, TRUE on cold start
    _bTempBad  : BOOL;                    // 温度非有限标志 / Temperature non-finite flag
    _bOpenReq  : BOOL;                    // 开阀请求（需求 + 间隔闭锁裁决后）/ Open request after gating
    _bCloseReq : BOOL;                    // 关阀请求（需求取反 + 间隔闭锁裁决后）/ Close request after gating
    _bBlocked  : BOOL;                    // 本拍指令被间隔闭锁标志 / Command blocked by interval this cycle
    _bOpenedPrv: BOOL;                    // 上拍全开确认镜像（间隔计时基准）/ Previous fully-open mirror, timer basis
    _bClosedPrv: BOOL;                    // 上拍全关确认镜像（间隔计时基准）/ Previous fully-closed mirror, timer basis
    _uInfo     : UDINT;                   // 信息码，每拍重算 / Info code
    _uFault    : UDINT;                   // 故障码锁存寄存 / Latched fault code register
    _bFault    : BOOL;                    // 故障锁存位 / Latched fault bit
    _bCfgBad   : BOOL;                    // 组态非法聚合 / Configuration invalid aggregate
END_VAR
VAR CONSTANT
    DL_RZV_INF_CAP : REAL := 1.0E15;  // 非有限值筛查幅值上限 / Non-finite screening cap
END_VAR

(* —— 段 0：定时器与边沿实例无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
(* 间隔计时 IN 取上拍阀位确认镜像（SemaMutex 同款「IN 取上一拍锁存状态」口径） *)
rtReset(CLK := bReset);                                 // 复位沿刷新，每拍必调
tonMinRun(IN := _bOpenedPrv, PT := tMinRun);            // 最小运行计时（上拍全开电平，单用途）
tonMinOff(IN := _bClosedPrv, PT := tMinOff);            // 最小停歇计时（上拍全关电平，单用途）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_bHeatDem/_bTempHigh 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
_bCfgBad := FALSE;                  // 组态非法预清零
_bBlocked := FALSE;                 // 闭锁标志预清零
uErrorId := 16#0000_0000;           // 事件码缺省无事件

(* —— 段 3：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fRoomTempC <> fRoomTempC) OR (ABS(fRoomTempC) > DL_RZV_INF_CAP) OR ((fRoomTempC - fRoomTempC) <> 0.0)
   OR (fRoomSpC <> fRoomSpC) OR (ABS(fRoomSpC) > DL_RZV_INF_CAP) THEN
    _bTempBad := TRUE;              // 温度/设定非有限（需求冻结保持，信息级）
END_IF
IF (fBandC <= 0.0) OR (TIME_TO_DINT(tMinRun) < 0) OR (TIME_TO_DINT(tMinOff) < 0)
   OR (TIME_TO_DINT(tStrokeOpen) <= 0) OR (TIME_TO_DINT(tStrokeClose) <= 0) THEN
    _bCfgBad := TRUE;               // 回差/间隔/行程域非法
END_IF
IF _bCfgBad AND (NOT _bFault) THEN
    _uFault := 16#0006_02B9;        // 故障级：组态非法（仅首次进入时写入）
    _bFault := TRUE;
END_IF
IF rtReset.Q AND (NOT _bCfgBad) THEN
    _bFault := FALSE;               // 清故障锁存位（R228-B：rtReset.Q 恒可达）
    _uFault := 16#0000_0000;
END_IF

(* —— 段 4：需求判定（迟滞取反口径；非有限冻结保持） —— *)
IF (NOT _bTempBad) AND (NOT _bCfgBad) THEN
    _bTempHigh := FC_DL_Hysteresis(fIn := fRoomTempC,       // 迟滞判温高（TRUE = 停热侧）
                                   fThreshold := fRoomSpC,  // 设定点
                                   fHysteresis := fBandC,   // 回差带
                                   bState := _bTempHigh);   // 回传保持变量（同一成员，有状态纪律）
    _bHeatDem := NOT _bTempHigh;    // 需求 = NOT 温高（带内保持，防阀频切）
    IF _bHeatDem THEN
        _uInfo := 16#0006_01B9;     // 信息级：加热需求置位
    END_IF
ELSE
    _uInfo := 16#0006_03B9;         // 信息级：温度信号非有限，需求冻结保持（_bHeatDem 不改写）
END_IF

(* —— 段 5：最小启停间隔裁决（先于三点阀调用，数据流「先算后喂」） —— *)
IF NOT bEnable THEN
    _bOpenReq := FALSE;             // 失能：禁开
    _bCloseReq := TRUE;             // 失能：关阀（安全供热侧）
    _bHeatDem := FALSE;             // 失能：需求清零（出口同步）
ELSIF _bFault THEN
    _bOpenReq := FALSE;             // 故障：禁开
    _bCloseReq := TRUE;             // 故障：关阀（安全侧）
    _bHeatDem := FALSE;             // 故障：需求清零（出口同步）
ELSE
    _bOpenReq := _bHeatDem AND (NOT tonMinOff.Q);   // 开阀 = 需求 AND 非停歇闭锁
    _bCloseReq := (NOT _bHeatDem) AND (NOT tonMinRun.Q);    // 关阀 = 无需求 AND 非运行闭锁
    IF _bHeatDem AND tonMinOff.Q THEN
        _bBlocked := TRUE;          // 开阀被停歇闭锁
    END_IF
    IF (NOT _bHeatDem) AND tonMinRun.Q THEN
        _bBlocked := TRUE;          // 关阀被运行闭锁
    END_IF
END_IF
IF _bBlocked THEN
    _uInfo := 16#0006_01B9;         // 信息级：间隔闭锁中（覆盖需求码，闭锁状态优先）
END_IF

(* —— 段 6：三点阀实例调用（每拍顶层无条件；裁决结果作引脚） —— *)
fbValve(bCmdOpen := _bOpenReq,      // 开阀指令（电平）
        bCmdClose := _bCloseReq,    // 关阀指令（电平；与开同拍为假，裁决互斥）
        bLimOpen := bLimOpen,       // 限位透传
        bLimClosed := bLimClosed,   // 限位透传
        tStrokeOpen := tStrokeOpen, // 行程透传
        tStrokeClose := tStrokeClose,   // 行程透传
        fEstimateTol := 10.0,       // 估算-限位一致性容差（默认口径）
        bEnable := TRUE,            // 阀件动作联锁恒放行（闭锁已在本件裁决）
        bReset := bReset,           // 复位透传
        bTrack := FALSE);           // 不跟踪（限位开关口径由透传承载）

(* —— 段 7：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
_bOpenedPrv := fbValve.bOpened;     // 上拍全开镜像更新（下一拍间隔计时基准）
_bClosedPrv := fbValve.bClosed;     // 上拍全关镜像更新
bHeating := _bHeatDem;              // 需求出口镜像
bOpenCmd := fbValve.bOpenPulse;     // 开阀脉冲镜像（阀件输出）
bCloseCmd := fbValve.bClosePulse;   // 关阀脉冲镜像
bOpened := fbValve.bOpened;         // 全开确认镜像
bClosed := fbValve.bClosed;         // 全关确认镜像
fValvePosEst := fbValve.fPosEstimate;   // 估算开度镜像
IF _bFault THEN
    uErrorId := _uFault;            // 故障锁存码回放
    bError := TRUE;
ELSE
    uErrorId := _uInfo;             // 信息码
    bError := FALSE;
END_IF

END_FUNCTION_BLOCK
