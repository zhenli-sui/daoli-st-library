(*
  FB_DL_AxisFollowErrGuard  —  轴跟随误差窗口监视 / Axis following-error window guard
  分类 Category : DL_Motion
  版本 Version  : 1.0.0
  来源 Source   : t1-6-plcopen — 运动守卫族零检索深化（P0-1 解除式教训落地）
  溯源 Origin   : clean-room 实现，PLCopen 跟随误差监视语义公开借鉴，未复制任何源码行
  功能 Function : 1) 经 I_DL_MotionAxis 读 fPosition（当拍量），与注入的位置指令 fPosSet
                  做差得跟随误差；|fVelocity| > fVelGate（运动门控）且误差 > fErrBand
                  持续 tErrTo → 故障级 03A9 锁存；
                  2) 误差进入 80% 带置预警沿信息级 04A8；误差回带内置恢复信息级 04A9；
                  3) 故障解除式全当拍量（R240 落地）：rtReset.Q AND NOT iAxis.bError
                  AND 误差回带内，逐 BOOL 标注见段 4；
                  4) 非有限误差 → 故障级 03AA 防御兜底锁存。
  边界 Boundary : ① I_DL_MotionAxis 无 fPosSet 属性（接口实测），位置指令由调用方引脚注入，
                  本件不实例化轴实现块；
                  ② 组态闸：fErrBand <= 0 或超时 <= 0 或门速 < 0 → 03A8 锁存；
                  ③ 门速 fVelGate = 0 语义为「静止也判」，显式允许（下移 0.0 语义合法）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : I_DL_MotionAxis（注入，不实例化）；Standard.library（TON / R_TRIG）
  码表 Error codes（Motion 段 0004，窗口 03A8~03AA / 04A8~04AA）:
    16#0004_03A8 故障级：组态非法（误差带/超时/门速域非法），锁存至 bReset
    16#0004_03A9 故障级：跟随误差超窗（运动门控下持续 tErrTo），锁存至 bReset
    16#0004_03AA 故障级：跟随误差非有限（防御兜底），锁存至 bReset
    16#0004_04A8 信息级：超窗预警沿（误差进入 80% 带）
    16#0004_04A9 信息级：误差恢复正常沿（回带内）
    16#0004_04AA 信息级：守卫使能沿（bEnable 上升沿）
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 2 · 序号 4）
*)

FUNCTION_BLOCK FB_DL_AxisFollowErrGuard
VAR_INPUT
    fPosSet      : REAL := 0.0;       // 位置指令 [mm 或 deg]，调用方注入 / Position command injected by caller
    fErrBand     : REAL := 0.5;       // 跟随误差带半宽 [mm 或 deg]，域 >= 0 / Following-error band half width
    fVelGate     : REAL := 1.0;       // 运动门速 [mm/s]，域 >= 0，0 = 静止也判 / Motion gating speed
    tErrTo       : TIME := T#500MS;   // 超窗确认超时 [ms]，域 > 0 / Over-window confirm timeout
    bEnable      : BOOL := FALSE;     // 守卫使能 [-] / Guard enable
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_IN_OUT
    iAxis        : I_DL_MotionAxis;   // 运动轴引用（注入，不实例化）/ Motion axis reference
END_VAR
VAR_OUTPUT
    fFollowErr   : REAL;              // 跟随误差绝对值 [mm 或 deg] / Absolute following error
    bWarn        : BOOL;              // 预警标志（误差 > 80% 带）/ Warning flag
    bFault       : BOOL;              // 故障锁存标志 / Fault latch flag
    bError       : BOOL;              // 故障级标志（与锁存位同源）/ Fault flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonErrTo     : TON;               // 超窗确认定时器，无条件周期刷新 / Over-window confirm timer
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    rtEn         : R_TRIG;            // 使能沿实例，无条件刷新 / Enable edge instance
    _fErr        : REAL;              // 跟随误差中间量 [mm 或 deg] / Following error intermediate
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
    _bWarnPrev   : BOOL;              // 上拍预警镜像（预警沿判据）/ Previous warn mirror
    _bInBandPrev : BOOL;              // 上拍带内镜像（恢复沿判据）/ Previous in-band mirror
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_fErr := ABS(fPosSet - iAxis.fPosition);              // 跟随误差（全当拍量）
rtReset(CLK := bReset);                               // 复位沿（每拍必调）
rtEn(CLK := bEnable);                                 // 使能沿（每拍必调）
tonErrTo(IN := bEnable AND (ABS(iAxis.fVelocity) > fVelGate) AND (_fErr > fErrBand), PT := tErrTo);
                                                      // 超窗确认（运动门控，每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bWarn := FALSE;                     // 预警出口缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (fErrBand < 0.0) OR (fVelGate < 0.0) OR (TIME_TO_DINT(tErrTo) <= 0) THEN
    _uFault := 16#0004_03A8;        // 故障级：组态非法
    _bFault := TRUE;
END_IF

(* —— 段 3：非有限误差防御兜底（NaN 自反判，禁近似阈值） —— *)
IF (_fErr <> _fErr) OR ((_fErr - _fErr) <> (_fErr - _fErr)) THEN
    _uFault := 16#0004_03AA;        // 故障级：误差非有限
    _bFault := TRUE;
    _fErr := 0.0;                   // 出口安全侧归零
END_IF

(* —— 段 4：故障聚合与超窗锁存（判据全当拍量） —— *)
IF (NOT _bFault) AND tonErrTo.Q THEN
    _uFault := 16#0004_03A9;        // 故障级：跟随误差超窗锁存
    _bFault := TRUE;
END_IF

(* —— 段 5：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；iAxis.bError = 当拍量；(_fErr <= fErrBand) = 当拍量。
     三者均不含锁存量（_bFault/_uFault），解除边真实可达。 —— *)
IF rtReset.Q AND (NOT iAxis.bError) AND (_fErr <= fErrBand) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，同上唯一解除路径）
END_IF

(* —— 段 6：预警与信息码派生（当拍量判据） —— *)
IF (NOT _bFault) AND bEnable THEN
    bWarn := _fErr > (fErrBand * 0.8);      // 预警：误差进入 80% 带
    IF bWarn AND (NOT _bWarnPrev) THEN
        _uInfo := 16#0004_04A8;             // 信息级：预警沿
    END_IF
    IF (NOT bWarn) AND _bInBandPrev AND (NOT _bWarnPrev) THEN
        _uInfo := 16#0004_04A9;             // 信息级：误差恢复沿（带内持续）
    END_IF
END_IF
IF rtEn.Q THEN
    _uInfo := 16#0004_04AA;         // 信息级：使能沿（覆盖预警沿，使能优先报告）
END_IF

(* —— 段 7：出口单点映射（锁存码回放，禁同拍抹除） —— *)
fFollowErr := _fErr;                // 误差出口镜像
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bWarn := FALSE;                 // 故障期预警强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bFault := _bFault;                  // 锁存位出口
bError := _bFault;                  // 故障标志与锁存位同源
_bWarnPrev := bWarn;                // 预警沿判据快照
_bInBandPrev := (NOT bWarn);        // 带内镜像快照

END_FUNCTION_BLOCK
