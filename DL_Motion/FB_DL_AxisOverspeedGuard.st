(*
  FB_DL_AxisOverspeedGuard  —  轴超速守卫（速度窗 + 加速度窗双判据） / Axis overspeed guard with velocity and acceleration windows
  分类 Category : DL_Motion
  版本 Version  : 1.0.0
  来源 Source   : t2-4-s7motion — 运动守卫族零检索深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 速度判据：|fVelocity| > fVelMax 持续 tVelTo → 故障级 03AC 独立锁存；
                  2) 加速度判据：离散差分 fAccEst := |v - vPrev| / tSamp（采样周期单位
                  已在头注释声明 [mm/s 每秒]），fAccEst > fAccMax 持续 tAccTo →
                  故障级 03AD 独立锁存（R190 归因唯一：两成因各自独立码位与独立出口）；
                  3) 故障解除式全当拍量（R240 落地），逐 BOOL 标注见段 5；
                  4) 速度回窗置信息级 04AB，加速度回窗置 04AC，使能沿置 04AD。
  边界 Boundary : ① 组态闸：fVelMax <= 0、fAccMax <= 0、tSamp <= 0、两超时 <= 0 → 03AB 锁存；
                  ② 差分分母下限 1.0E-6 s 防除零（TIME_TO_LREAL 后钳位）；
                  ③ 速度窗下限语义：判据为绝对值上窗，无下窗（下限 0 显式化）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : I_DL_MotionAxis（注入，不实例化）；Standard.library（TON / R_TRIG）
  码表 Error codes（Motion 段 0004，窗口 03AB~03AD / 04AB~04AD）:
    16#0004_03AB 故障级：组态非法（速度窗/加速度窗/采样周期/超时域非法），锁存至 bReset
    16#0004_03AC 故障级：超速锁存（速度窗判据），锁存至 bReset
    16#0004_03AD 故障级：加速度超窗锁存（加速度窗判据），锁存至 bReset
    16#0004_04AB 信息级：速度恢复正常沿（回速度窗内）
    16#0004_04AC 信息级：加速度恢复正常沿（回加速度窗内）
    16#0004_04AD 信息级：守卫使能沿（bEnable 上升沿）
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 2 · 序号 5）
*)

FUNCTION_BLOCK FB_DL_AxisOverspeedGuard
VAR_INPUT
    fVelMax      : REAL := 1000.0;    // 速度窗上限绝对值 [mm/s]，域 > 0 / Velocity window upper bound
    fAccMax      : REAL := 5000.0;    // 加速度窗上限 [mm/s²]，域 > 0 / Acceleration window bound
    tSamp        : TIME := T#10MS;    // 差分采样周期 [ms]，域 > 0 / Differentiation sample period
    tVelTo       : TIME := T#100MS;   // 超速确认超时 [ms]，域 > 0 / Overspeed confirm timeout
    tAccTo       : TIME := T#100MS;   // 超加速度确认超时 [ms]，域 > 0 / Over-acceleration confirm timeout
    bEnable      : BOOL := FALSE;     // 守卫使能 [-] / Guard enable
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_IN_OUT
    iAxis        : I_DL_MotionAxis;   // 运动轴引用（注入，不实例化）/ Motion axis reference
END_VAR
VAR_OUTPUT
    fVelAct      : REAL;              // 速度出口镜像 [mm/s] / Velocity outlet mirror
    fAccEst      : REAL;              // 加速度离散估计 [mm/s²] / Discrete acceleration estimate
    bVelFault    : BOOL;              // 超速独立锁存出口 [-] / Overspeed latch outlet
    bAccFault    : BOOL;              // 超加速度独立锁存出口 [-] / Over-acceleration latch outlet
    bFault       : BOOL;              // 聚合故障标志 [-] / Aggregate fault flag
    bError       : BOOL;              // 故障级标志（与聚合锁存同源）/ Fault flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonVelTo     : TON;               // 超速确认定时器，无条件周期刷新 / Overspeed confirm timer
    tonAccTo     : TON;               // 超加速度确认定时器，无条件周期刷新 / Over-acceleration confirm timer
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    rtEn         : R_TRIG;            // 使能沿实例，无条件刷新 / Enable edge instance
    _fVel        : REAL;              // 速度当拍量 [mm/s] / Current-scan velocity
    _fVelPrev    : REAL;              // 上拍速度快照 [mm/s] / Previous-scan velocity snapshot
    _fSampSec    : REAL;              // 生效采样周期 [s] / Effective sample period in seconds
    _bVelLat     : BOOL;              // 超速锁存位（锁存量）/ Overspeed latch bit
    _bAccLat     : BOOL;              // 超加速度锁存位（锁存量）/ Over-acceleration latch bit
    _bCfgBad     : BOOL;              // 组态非法锁存位（锁存量）/ Config-fault latch bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
    _bVelOkPrev  : BOOL;              // 上拍速度窗内镜像（恢复沿判据）/ Previous velocity-in-window mirror
    _bAccOkPrev  : BOOL;              // 上拍加速度窗内镜像（恢复沿判据）/ Previous acceleration-in-window mirror
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_fVel := iAxis.fVelocity;                              // 速度当拍量
_fSampSec := TIME_TO_LREAL(tSamp) * 1.0E-3;            // 采样周期换算秒 [s]
IF _fSampSec < 1.0E-6 THEN
    _fSampSec := 1.0E-6;            // 差分分母下限防除零（下限钳位）
END_IF
fAccEst := ABS(_fVel - _fVelPrev) / _fSampSec;         // 加速度离散估计（差分口径）
rtReset(CLK := bReset);                                // 复位沿（每拍必调）
rtEn(CLK := bEnable);                                  // 使能沿（每拍必调）
tonVelTo(IN := bEnable AND (ABS(_fVel) > fVelMax), PT := tVelTo);   // 超速确认（每拍必调）
tonAccTo(IN := bEnable AND (fAccEst > fAccMax), PT := tAccTo);      // 超加速度确认（每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bVelLat/_bAccLat/_bCfgBad 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bVelLat := FALSE;              // 清超速锁存位
    _bAccLat := FALSE;              // 清超加速度锁存位
    _bCfgBad := FALSE;              // 清组态锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (fVelMax <= 0.0) OR (fAccMax <= 0.0) OR (TIME_TO_DINT(tSamp) <= 0)
   OR (TIME_TO_DINT(tVelTo) <= 0) OR (TIME_TO_DINT(tAccTo) <= 0) THEN
    _uFault := 16#0004_03AB;        // 故障级：组态非法
    _bCfgBad := TRUE;
END_IF

(* —— 段 3：双判据独立锁存（R190：速度/加速度归因唯一，各走独立码位与出口） —— *)
IF (NOT _bCfgBad) AND tonVelTo.Q THEN
    _uFault := 16#0004_03AC;        // 故障级：超速锁存
    _bVelLat := TRUE;
END_IF
IF (NOT _bCfgBad) AND tonAccTo.Q THEN
    _uFault := 16#0004_03AD;        // 故障级：加速度超窗锁存
    _bAccLat := TRUE;
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；ABS(_fVel) <= fVelMax = 当拍量；fAccEst <= fAccMax = 当拍量。
     均不含锁存量（_bVelLat/_bAccLat），解除边真实可达。 —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (ABS(_fVel) <= fVelMax) AND (fAccEst <= fAccMax) THEN
    _bVelLat := FALSE;              // 清超速锁存位（锁存量，仅此当拍量解除沿可清）
    _bAccLat := FALSE;              // 清超加速度锁存位（锁存量，同上）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，同上唯一解除路径）
END_IF

(* —— 段 5：信息码派生（当拍量判据） —— *)
IF (NOT _bCfgBad) AND bEnable THEN
    IF (ABS(_fVel) <= fVelMax) AND (NOT _bVelOkPrev) THEN
        _uInfo := 16#0004_04AB;     // 信息级：速度恢复沿
    END_IF
    IF (fAccEst <= fAccMax) AND (NOT _bAccOkPrev) THEN
        _uInfo := 16#0004_04AC;     // 信息级：加速度恢复沿（覆盖速度恢复沿，后到优先）
    END_IF
END_IF
IF rtEn.Q THEN
    _uInfo := 16#0004_04AD;         // 信息级：使能沿（使能优先报告）
END_IF

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
fVelAct := _fVel;                   // 速度出口镜像
bVelFault := _bVelLat OR _bCfgBad;  // 超速独立出口（组态非法并入聚合安全侧）
bAccFault := _bAccLat OR _bCfgBad;  // 超加速度独立出口（同上）
bFault := _bVelLat OR _bAccLat OR _bCfgBad;     // 聚合故障
IF bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := bFault;                   // 故障标志与聚合锁存同源
_bVelOkPrev := (ABS(_fVel) <= fVelMax);   // 速度恢复沿判据快照
_bAccOkPrev := (fAccEst <= fAccMax);      // 加速度恢复沿判据快照
_fVelPrev := _fVel;                 // 上拍速度快照（段末统一写）

END_FUNCTION_BLOCK
