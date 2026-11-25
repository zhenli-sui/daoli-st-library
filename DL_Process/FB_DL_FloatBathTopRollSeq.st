(*
  Name: FB_DL_FloatBathTopRollSeq
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 浮法玻璃锡槽退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 拉边机三轴同步作业序，六相推进：待机 → 就位 → 夹持 → 同步张角 → 跟踪带宽 → 退出 → 完成。
           就位相向三轴发出就位指令并等三路到位信号全为 TRUE；夹持相保持指令并等夹持时长；
           同步张角相把张角给定按设定角速度斜坡推到 fAngleTargetDeg；跟踪带宽相保持张角并监视
           带宽是否漂出容差；退出相撤令（三轴回退），等退到位时长后置完成位。
        2) 多轴失步监视贯穿三轴：就位相超时未全部到位 → 失步故障；同步相与跟踪相内任一路到位
           信号掉线 → 失步故障。三轴指令始终同源（同一个状态量导出），不存在单轴独走的可能。
        3) 张角斜坡按「角速度 × 扫描周期」逐拍累加，故扫描周期必须作为入参并做零闸（R21），
           不许假设固定扫描周期；斜坡单向逼近目标，不越过目标值。
  边界条件：1) 非有限值闸：张角目标、带宽实测、扫描周期三路实值入参统一过
           NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf；命中即判组态非法并进故障相，
           绝不把 NaN 累加进张角保持值（累加后保持值被永久污染，R19）。
        2) 组态零闸：ABS(fCycleS) > DL_EPS 才允许角度积分（周期为零则斜坡不推进且步进发散）；
           tSyncS 必须 > T#0S（跟踪相时长为 0 表示跳过跟踪监视，属组态错误）；
           fAngleTargetDeg 必须落在 0 ~ DL_ANGLE_MAX_DEG(90 °) 并大于 0。
        3) 带宽容差闸：跟踪相内带宽相对漂移超过 DL_WIDTH_TOL_PCT(2 %) 判带宽失控故障；
           带宽参考值在进入跟踪相的同一个周期末锁存（R23：快照必须在迁移判断之后更新）。
        4) 相超时说明：eFbtPosition 由 tonPos 监视（就位超时 = 失步）；
           eFbtClamp 由 tonClamp 定时（夹持时长，无额外超时）；
           eFbtSyncAngle 由 tonAngle 监视（张角同步超时 = 失步）；
           eFbtTrackWidth 由 tonTrack 定时（跟踪时长，另有带宽容差监视）；
           eFbtRetract 由 tonRetract 定时（退出时长）；
           eFbtDone / eFbtIdle / eFbtFault 为稳态持留相，不设相超时（设了会周期性误报）；
           整序另设 tonSeq 总超时兜底。
        5) 状态机兜底：CASE 全态覆盖 + ELSE 强制回故障相并撤全部指令；故障解除路径为
           (NOT xStart) AND (NOT xFault) AND 组态恢复，可达。
        6) FB 主体不使用 RETURN，统一单出口（跨平台可移植性）。
  量纲自证：张角步进 = (°/s) × s = °，与 fAngleDeg 同量纲；
           带宽相对漂移 = (mm − mm) / mm × 100 = 无因次 [%]，与容差同量纲；
           三路到位信号为 [bool]；tonXxx 的 PT 均为 [TIME]；本件无跨量纲相加。
  码表 Error codes（本件格 0090_07xx，故障级一律 3 行内置 _uFault/_bFault/_eState）:
    16#0090_0701 故障级：组态非法（角度目标/跟踪时长/扫描周期越界或非有限）
    16#0090_0702 故障级：就位超时（三轴未全部到位，多轴失步）
    16#0090_0703 故障级：张角同步超时（斜坡未在时限内到达目标）
    16#0090_0704 故障级：同步/跟踪相内到位信号掉线（多轴失步）
    16#0090_0705 故障级：跟踪相带宽漂移超容差（带宽失控）
    16#0090_0706 故障级：整序总超时
    16#0090_0707 故障级：外部故障输入 xFault
    16#0090_0708 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0090_0709 信息级：张角已到达目标，转入跟踪相

  修订历史 Revision :
    2026-11-25  v1.0.0  R90 首版
*)

TYPE E_DL_FbtState :
(
    eFbtIdle      := 0,    // 待机：等启动上升沿 / Idle, awaiting start edge
    eFbtPosition  := 10,   // 就位：三轴发出就位指令 / Positioning, all three axes commanded
    eFbtClamp     := 20,   // 夹持：保持指令等夹持时长 / Clamping, commands held
    eFbtSyncAngle := 30,   // 同步张角：斜坡推到目标角 / Angle synchronising
    eFbtTrackWidth:= 40,   // 跟踪带宽：保持张角并监视带宽 / Width tracking
    eFbtRetract   := 50,   // 退出：撤令等退到位 / Retracting
    eFbtDone      := 60,   // 完成：保持完成位等撤令 / Done, held until release
    eFbtFault     := 90    // 故障：锁存待解除 / Fault, latched awaiting release
);
END_TYPE

FUNCTION_BLOCK FB_DL_FloatBathTopRollSeq
VAR_INPUT
    xStart          : BOOL;    // 作业启动指令（上升沿有效）[bool] / Sequence start, edge triggered [bool]
    xFault          : BOOL;    // 外部故障汇总 [bool] / External fault aggregate [bool]
    xInPos1         : BOOL;    // 1 轴到位信号 [bool] / Axis 1 in-position signal [bool]
    xInPos2         : BOOL;    // 2 轴到位信号 [bool] / Axis 2 in-position signal [bool]
    xInPos3         : BOOL;    // 3 轴到位信号 [bool] / Axis 3 in-position signal [bool]
    fAngleTargetDeg : REAL;    // 目标张角 [°] / Target nip angle [°]
    fWidthMeasMm    : REAL;    // 玻璃带宽度实测 [mm] / Measured ribbon width [mm]
    tSyncS          : TIME;    // 带宽跟踪监视时长 [TIME] / Width tracking supervision duration [TIME]
    fCycleS         : REAL;    // 扫描周期 [s] / Scan cycle time [s]
END_VAR
VAR_OUTPUT
    xCmd1           : BOOL;    // 1 轴就位/夹持指令 [bool] / Axis 1 command [bool]
    xCmd2           : BOOL;    // 2 轴就位/夹持指令 [bool] / Axis 2 command [bool]
    xCmd3           : BOOL;    // 3 轴就位/夹持指令 [bool] / Axis 3 command [bool]
    fAngleDeg       : REAL;    // 当前张角给定 [°] / Current nip angle setpoint [°]
    fWidthDevPct    : REAL;    // 跟踪相带宽相对漂移 [%] / Width relative drift during tracking [%]
    xAllInPos       : BOOL;    // 三轴全部到位 [bool] / All three axes in position [bool]
    xDone           : BOOL;    // 作业完成保持位 [bool] / Sequence complete held flag [bool]
    eState          : E_DL_FbtState;   // 状态出口，段尾单点映射 / State outlet, single-point mapped
    nErrId          : UDINT;   // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    tonPos          : TON;     // 就位相超时监视 [TIME] / Positioning timeout timer
    tonClamp        : TON;     // 夹持时长定时 [TIME] / Clamping duration timer
    tonAngle        : TON;     // 张角同步超时监视 [TIME] / Angle synchronising timeout timer
    tonTrack        : TON;     // 带宽跟踪时长定时 [TIME] / Width tracking duration timer
    tonRetract      : TON;     // 退出相时长定时 [TIME] / Retracting duration timer
    tonSeq          : TON;     // 整序总超时定时 [TIME] / Whole-sequence timeout timer
    rtStart         : R_TRIG;  // 启动上升沿检测 [bool] / Start rising edge detector
    _eState         : E_DL_FbtState := E_DL_FbtState.eFbtIdle;   // 内部相位（CASE 唯一写入目标）
    _eStatePrev     : E_DL_FbtState := E_DL_FbtState.eFbtIdle;   // 上一拍相位快照（周期末更新）
    _fAngleDeg      : REAL;    // 张角保持值 [°] / Retained nip angle [°]
    _fWidthRefMm    : REAL;    // 跟踪相带宽参考值（进相锁存）[mm] / Width reference latched on entry [mm]
    _fWidthDevPct   : REAL;    // 带宽相对漂移 [%] / Width relative drift [%]
    _fStepDeg       : REAL;    // 单拍张角步进 [°] / Angle step per cycle [°]
    _bAllInPos      : BOOL;    // 三轴全到位 [bool] / All axes in position [bool]
    _bCmdOut        : BOOL;    // 三轴指令聚合（状态导出）[bool] / Axis command aggregate [bool]
    _bCfgBad        : BOOL;    // 组态非法聚合 [bool] / Configuration invalid aggregate [bool]
    _bActive        : BOOL;    // 序激活（中间五相）[bool] / Sequence active flag [bool]
    _bAngleAtTgt    : BOOL;    // 张角已到目标（带死区）[bool] / Angle reached target [bool]
    _bWidthBad      : BOOL;    // 带宽漂移超容差 [bool] / Width drift out of tolerance [bool]
    _bFault         : BOOL;    // 故障锁存位 [bool] / Latched fault flag [bool]
    _uInfo          : UDINT;   // 信息码，每拍重算 / Info code, recomputed every cycle
    _uFault         : UDINT;   // 故障码锁存 / Latched fault code
END_VAR
VAR CONSTANT
    DL_EPS          : REAL := 1.0E-9;    // 组态零闸阈值 [-] / Configuration zero gate threshold [-]
    DL_BIG          : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT          : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_ANGLE_MAX_DEG: REAL := 90.0;      // 张角量程上限 [°] / Nip angle range ceiling [°]
    DL_ANGLE_RATE   : REAL := 2.0;       // 张角斜坡角速度 [°/s] / Angle ramp rate [°/s]
    DL_ANGLE_TOL_DEG: REAL := 0.10;      // 张角到位死区 [°] / Angle arrival deadband [°]
    DL_WIDTH_TOL_PCT: REAL := 2.0;       // 带宽漂移容差 [%] / Width drift tolerance [%]
    DL_POS_MAX      : TIME := T#20S;     // 就位相超时上限 [TIME] / Positioning timeout ceiling [TIME]
    DL_CLAMP_S      : TIME := T#3S;      // 夹持时长 [TIME] / Clamping duration [TIME]
    DL_ANGLE_MAX_T  : TIME := T#60S;     // 张角同步超时上限 [TIME] / Angle timeout ceiling [TIME]
    DL_RETRACT_S    : TIME := T#8S;      // 退出相时长 [TIME] / Retracting duration [TIME]
    DL_SEQ_MAX      : TIME := T#15M;     // 整序总超时上限 [TIME] / Whole-sequence timeout [TIME]
END_VAR

(* —— 段 0：单拍量预清零（锁存量 _uFault/_bFault/_fAngleDeg/_fWidthRefMm/_eStatePrev 不入清单） —— *)
_uInfo := 16#0000_0000;                     // 信息码每拍重算 / Info code recomputed
nErrId := 16#0000_0000;                     // 事件码缺省无事件 / Event code defaults to none
_fWidthDevPct := 0.0;                       // 带宽漂移每拍重算 / Width drift recomputed

(* —— 段 1：非有限值闸（R19：NaN 一旦累加进保持值会永久污染，必须前置拦截） —— *)
_bCfgBad := NOT (fAngleTargetDeg > -DL_BIG AND fAngleTargetDeg < DL_BIG)
            OR NOT (fWidthMeasMm > -DL_BIG AND fWidthMeasMm < DL_BIG)
            OR NOT (fCycleS > -DL_BIG AND fCycleS < DL_BIG);

(* —— 段 2：组态零闸（R4 / R21：周期零闸是角度积分的前置条件） —— *)
_bCfgBad := _bCfgBad
            OR (ABS(fCycleS) <= DL_EPS)                      // 周期为零：角度积分不推进且发散
            OR (tSyncS <= T#0S)                              // 跟踪时长为零：跳过监视属错组态
            OR (fAngleTargetDeg <= DL_EPS)                   // 目标张角必须为正
            OR (fAngleTargetDeg > DL_ANGLE_MAX_DEG);         // 目标张角不得越量程

(* —— 段 3：状态派生与判据量 —— *)
_fStepDeg := LIMIT(0.0, DL_ANGLE_RATE * fCycleS, DL_ANGLE_MAX_DEG);   // °/s × s = °
_bAllInPos := xInPos1 AND xInPos2 AND xInPos3;                        // 三轴全到位
_bAngleAtTgt := (NOT _bCfgBad) AND (ABS(fAngleTargetDeg - _fAngleDeg) <= DL_ANGLE_TOL_DEG);
_bActive := (_eState = E_DL_FbtState.eFbtPosition) OR (_eState = E_DL_FbtState.eFbtClamp)
            OR (_eState = E_DL_FbtState.eFbtSyncAngle) OR (_eState = E_DL_FbtState.eFbtTrackWidth)
            OR (_eState = E_DL_FbtState.eFbtRetract);
_bCmdOut := (_eState = E_DL_FbtState.eFbtPosition) OR (_eState = E_DL_FbtState.eFbtClamp)
            OR (_eState = E_DL_FbtState.eFbtSyncAngle) OR (_eState = E_DL_FbtState.eFbtTrackWidth);

(* 带宽相对漂移：分母零闸后才允许相除（参考值在跟踪相入口锁存） *)
IF ABS(_fWidthRefMm) > DL_EPS THEN
    _fWidthDevPct := (fWidthMeasMm - _fWidthRefMm) / _fWidthRefMm * DL_PCT;   // [%]
ELSE
    _fWidthDevPct := 0.0;                                                 // 参考值不可用则不计漂移
END_IF
_bWidthBad := (_eState = E_DL_FbtState.eFbtTrackWidth) AND (ABS(_fWidthDevPct) > DL_WIDTH_TOL_PCT);

(* —— 段 4：定时器与边沿无条件周期刷新（R7：调用语句不得置于 IF/CASE 内） —— *)
rtStart(CLK := xStart);                                                             // 启动上升沿
tonPos(IN := (_eState = E_DL_FbtState.eFbtPosition), PT := DL_POS_MAX);             // 就位超时监视
tonClamp(IN := (_eState = E_DL_FbtState.eFbtClamp), PT := DL_CLAMP_S);              // 夹持时长
tonAngle(IN := (_eState = E_DL_FbtState.eFbtSyncAngle), PT := DL_ANGLE_MAX_T);      // 张角同步超时
tonTrack(IN := (_eState = E_DL_FbtState.eFbtTrackWidth), PT := tSyncS);             // 跟踪时长
tonRetract(IN := (_eState = E_DL_FbtState.eFbtRetract), PT := DL_RETRACT_S);        // 退出时长
tonSeq(IN := _bActive, PT := DL_SEQ_MAX);                                           // 整序总超时

(* —— 段 5：全局故障拦截（优先级最高；已锁存则不再改写码值，禁同拍抹除） —— *)
IF xFault AND (NOT _bFault) THEN
    _uFault := 16#0090_0707;                // 故障级：外部故障输入
    _bFault := TRUE;                        // 锁存（3 行内置，R45 配对）
    _eState := E_DL_FbtState.eFbtFault;
END_IF
IF _bCfgBad AND (NOT _bFault) THEN
    _uFault := 16#0090_0701;                // 故障级：组态非法
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_FbtState.eFbtFault;
END_IF
IF tonSeq.Q AND _bActive AND (NOT _bFault) THEN
    _uFault := 16#0090_0706;                // 故障级：整序总超时
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_FbtState.eFbtFault;
END_IF
IF _bWidthBad AND (NOT _bFault) THEN
    _uFault := 16#0090_0705;                // 故障级：跟踪相带宽漂移超容差
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_FbtState.eFbtFault;
END_IF

(* —— 段 6：相位机（只做迁移；出口在段 8 单点映射） —— *)
CASE _eState OF

E_DL_FbtState.eFbtIdle:
    IF NOT xStart THEN
        ;                                   // 等启动 / Waiting for start
    ELSIF rtStart.Q THEN
        _eState := E_DL_FbtState.eFbtPosition;   // 进就位相
    END_IF

E_DL_FbtState.eFbtPosition:
    IF NOT xStart THEN
        _eState := E_DL_FbtState.eFbtIdle;      // 撤令：回待机
    ELSIF _bAllInPos THEN
        _eState := E_DL_FbtState.eFbtClamp;     // 三轴全到位：进夹持相
    ELSIF tonPos.Q THEN
        _uFault := 16#0090_0702;                // 故障级：就位超时（多轴失步）
        _bFault := TRUE;
        _eState := E_DL_FbtState.eFbtFault;
    END_IF

E_DL_FbtState.eFbtClamp:
    IF NOT xStart THEN
        _eState := E_DL_FbtState.eFbtIdle;
    ELSIF NOT _bAllInPos THEN
        _uFault := 16#0090_0704;                // 故障级：夹持中到位信号掉线（多轴失步）
        _bFault := TRUE;
        _eState := E_DL_FbtState.eFbtFault;
    ELSIF tonClamp.Q THEN
        _eState := E_DL_FbtState.eFbtSyncAngle; // 夹持完成：进同步张角相
    END_IF

E_DL_FbtState.eFbtSyncAngle:
    IF NOT xStart THEN
        _eState := E_DL_FbtState.eFbtIdle;
    ELSIF NOT _bAllInPos THEN
        _uFault := 16#0090_0704;                // 故障级：同步中到位信号掉线（多轴失步）
        _bFault := TRUE;
        _eState := E_DL_FbtState.eFbtFault;
    ELSIF _bAngleAtTgt THEN
        _uInfo := 16#0090_0709;                 // 信息级：张角已到达目标
        _eState := E_DL_FbtState.eFbtTrackWidth; // 本拍合法事件优先于超时迁移（R275）
    ELSIF tonAngle.Q THEN
        _uFault := 16#0090_0703;                // 故障级：张角同步超时
        _bFault := TRUE;
        _eState := E_DL_FbtState.eFbtFault;
    ELSE
        _fAngleDeg := MIN(fAngleTargetDeg, _fAngleDeg + _fStepDeg);   // 单向逼近，不越目标
    END_IF

E_DL_FbtState.eFbtTrackWidth:
    IF NOT xStart THEN
        _eState := E_DL_FbtState.eFbtIdle;
    ELSIF NOT _bAllInPos THEN
        _uFault := 16#0090_0704;                // 故障级：跟踪中到位信号掉线（多轴失步）
        _bFault := TRUE;
        _eState := E_DL_FbtState.eFbtFault;
    ELSIF tonTrack.Q THEN
        _eState := E_DL_FbtState.eFbtRetract;   // 跟踪结束：进退出相
    END_IF

E_DL_FbtState.eFbtRetract:
    IF xFault THEN
        _uFault := 16#0090_0707;                // 故障级：退出中外部故障
        _bFault := TRUE;
        _eState := E_DL_FbtState.eFbtFault;
    ELSIF tonRetract.Q THEN
        _eState := E_DL_FbtState.eFbtDone;      // 退到位：进完成相
    END_IF

E_DL_FbtState.eFbtDone:
    IF NOT xStart THEN
        _eState := E_DL_FbtState.eFbtIdle;      // 撤令：回待机
    END_IF

E_DL_FbtState.eFbtFault:
    IF (NOT xStart) AND (NOT xFault) AND (NOT _bCfgBad) THEN
        _bFault := FALSE;                       // 解除路径：撤令 + 外部故障消失 + 组态恢复（可达）
        _uFault := 16#0000_0000;                // 清锁存码
        _eState := E_DL_FbtState.eFbtIdle;      // 回待机
    END_IF

ELSE
    _uFault := 16#0090_0708;                    // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                            // 锁存
    _eState := E_DL_FbtState.eFbtFault;         // 强制回故障相

END_CASE

(* —— 段 7：后置段（R23：带宽参考快照在迁移判断之后按「进入沿」锁存） —— *)
IF (_eState = E_DL_FbtState.eFbtTrackWidth) AND (_eStatePrev <> E_DL_FbtState.eFbtTrackWidth) THEN
    _fWidthRefMm := fWidthMeasMm;               // 进跟踪相当拍锁存带宽参考值 [mm]
END_IF
IF _eState <> E_DL_FbtState.eFbtTrackWidth THEN
    _fWidthRefMm := fWidthMeasMm;               // 非跟踪相：参考值持续跟随，避免陈旧值误判
END_IF
_eStatePrev := _eState;                         // 快照统一在周期末尾更新（R23）

(* —— 段 8：出口单点映射（名实同源；三轴指令同源导出，故障侧一律撤令） —— *)
xCmd1 := _bCmdOut AND (NOT _bFault);            // 1 轴指令出口
xCmd2 := _bCmdOut AND (NOT _bFault);            // 2 轴指令出口
xCmd3 := _bCmdOut AND (NOT _bFault);            // 3 轴指令出口
fAngleDeg := LIMIT(0.0, _fAngleDeg, DL_ANGLE_MAX_DEG);   // 张角给定出口 [°]
fWidthDevPct := LIMIT(-DL_BIG, _fWidthDevPct, DL_BIG);   // 带宽漂移出口 [%]
xAllInPos := _bAllInPos;                                 // 三轴到位出口
xDone := (_eState = E_DL_FbtState.eFbtDone) AND (NOT _bFault);   // 完成位出口
eState := _eState;                                       // 状态出口单点映射
IF _bFault THEN
    nErrId := _uFault;                          // 故障锁存码回放（不在故障相按当下输入重推断）
ELSE
    nErrId := _uInfo;                           // 信息码
END_IF

END_FUNCTION_BLOCK
