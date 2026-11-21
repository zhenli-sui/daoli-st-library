(*
  FB_DL_AxisInposGuard  —  到位窗口判定守卫（MC_InPosition 语义 + 驻留确认） / Axis in-position guard with dwell confirm
  分类 Category : DL_Motion
  版本 Version  : 1.0.1
  来源 Source   : t1-6-plcopen — 运动守卫族零检索深化
  溯源 Origin   : clean-room 实现，MC_InPosition 语义公开借鉴，未复制任何源码行
  功能 Function : 1) 到位带双判据：|fPosition - fTarget| <= fPosBand 且 |fVelocity| <= fVelQuiet，
                  驻留 TON 持续 tDwell 后 bInpos = TRUE（tonDwell.Q 直出）；
                  2) 驻留期目标变更即复位驻留：变更判据为当拍量比较
                  ABS(fTarget - fTgtPrev) > fPosBand，禁锁存量自指；
                  3) 使能后 tWatch 内从未到位 → 故障级 03AF 锁存；
                  4) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 5。
  返修记录 Rework  :
    2026-11-19  v1.0.1  R42 P0-2 中等返修：v1.0.0 监视 TON（tonWatchTo）IN 引用
                        bInpos 输出量——该量在故障相被强制 FALSE 且为本拍后段
                        计算值（跨扫描序依赖），计时基跨故障相不复位，复位后
                        残留 .Q 即刻再判 03AF（P0 派单缺陷②）。修复要点：新增
                        _bSteady 当拍量（段 0 由 _bInBand AND _bQuiet 直接承载），
                        tonWatchTo 的 IN 改为 bEnable AND (NOT _bFault) AND
                        (NOT _bSteady)——全当拍量承载，故障相与到位拍均显式
                        复位计时基；对外接口签名不变。
  边界 Boundary : ① 组态闸：fPosBand <= 0、fVelQuiet < 0、任一超时 <= 0 → 03AE 锁存；
                  ② 目标非有限或轴位置非有限 → 03B0 防御兜底锁存（NaN 自反判）；
                  ③ 驻留 TON 电平驱动：目标变更拍 IN 必断（当拍量 NOT bTgtChg 串入）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : I_DL_MotionAxis（注入，不实例化）；Standard.library（TON / R_TRIG）
  码表 Error codes（Motion 段 0004，窗口 03AE~03B0 / 04AE~04B0）:
    16#0004_03AE 故障级：组态非法（到位带/静默阈/驻留/监视超时域非法），锁存至 bReset
    16#0004_03AF 故障级：驻留判据长期不满足（使能后 tWatch 未到位），锁存至 bReset
    16#0004_03B0 故障级：目标/位置非有限（防御兜底），锁存至 bReset
    16#0004_04AE 信息级：到位沿（bInpos 首次 TRUE）
    16#0004_04AF 信息级：目标变更检出（驻留复位）
    16#0004_04B0 信息级：失去到位沿（离开到位带）
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 3 · 序号 1）
    2026-11-19  v1.0.1  R42 P0-2 中等返修（见返修记录节）
*)

FUNCTION_BLOCK FB_DL_AxisInposGuard
VAR_INPUT
    fTarget      : REAL := 0.0;       // 目标位置 [mm 或 deg]，调用方注入 / Target position injected by caller
    fPosBand     : REAL := 0.05;      // 到位带半宽 [mm 或 deg]，域 > 0 / In-position band half width
    fVelQuiet    : REAL := 1.0;       // 速度静默阈 [mm/s]，域 >= 0 / Velocity quiet threshold
    tDwell       : TIME := T#200MS;   // 驻留确认时间 [ms]，域 > 0 / Dwell confirm time
    tWatch       : TIME := T#10S;     // 未到位监视超时 [ms]，域 > 0 / Not-in-position watchdog
    bEnable      : BOOL := FALSE;     // 守卫使能 [-] / Guard enable
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_IN_OUT
    iAxis        : I_DL_MotionAxis;   // 运动轴引用（注入，不实例化）/ Motion axis reference
END_VAR
VAR_OUTPUT
    bInpos       : BOOL;              // 到位出口（驻留 TON 直出）[-] / In-position outlet
    bFault       : BOOL;              // 故障锁存标志 / Fault latch flag
    bError       : BOOL;              // 故障级标志（与锁存同源）/ Fault flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonDwell     : TON;               // 驻留确认定时器，无条件周期刷新 / Dwell confirm timer
    tonWatchTo   : TON;               // 未到位监视定时器（专用超时命名），无条件刷新 / Watchdog timer
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _fTgtPrev    : REAL;              // 上拍目标快照 [mm 或 deg] / Previous target snapshot
    _bTgtChg     : BOOL;              // 目标变更当拍量 [-] / Target change current-scan flag
    _bInBand     : BOOL;              // 位置带内当拍量 [-] / In-band current-scan flag
    _bQuiet      : BOOL;              // 速度静默当拍量 [-] / Velocity-quiet current-scan flag
    _bSteady     : BOOL;              // 双判据同时成立当拍量（v1.0.1 监视 TON 计时基）/ Steady verdict current-scan flag
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
    _bInposPrev  : BOOL;              // 上拍到位镜像（到位/失位沿判据）/ Previous inpos mirror
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bTgtChg := ABS(fTarget - _fTgtPrev) > fPosBand;        // 目标变更（当拍量）
_bInBand := ABS(iAxis.fPosition - fTarget) <= fPosBand; // 位置带内（当拍量）
_bQuiet := ABS(iAxis.fVelocity) <= fVelQuiet;           // 速度静默（当拍量）
_bSteady := _bInBand AND _bQuiet;                       // 双判据同立（当拍量，v1.0.1 承载监视计时基）
rtReset(CLK := bReset);                                 // 复位沿（每拍必调）
tonDwell(IN := bEnable AND _bInBand AND _bQuiet AND (NOT _bTgtChg), PT := tDwell);
                                                        // 驻留确认（目标变更拍 IN 必断，每拍必调）
tonWatchTo(IN := bEnable AND (NOT _bFault) AND (NOT _bSteady), PT := tWatch);
                                                        // 未到位监视（全当拍量承载，故障相/到位拍显式复位，v1.0.1）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (fPosBand <= 0.0) OR (fVelQuiet < 0.0)
   OR (TIME_TO_DINT(tDwell) <= 0) OR (TIME_TO_DINT(tWatch) <= 0) THEN
    _uFault := 16#0004_03AE;        // 故障级：组态非法
    _bFault := TRUE;
END_IF

(* —— 段 3：非有限防御兜底（目标/位置 NaN 自反判，禁近似阈值） —— *)
IF (fTarget <> fTarget) OR (iAxis.fPosition <> iAxis.fPosition)
   OR ((fTarget - fTarget) <> (fTarget - fTarget))
   OR ((iAxis.fPosition - iAxis.fPosition) <> (iAxis.fPosition - iAxis.fPosition)) THEN
    _uFault := 16#0004_03B0;        // 故障级：非有限防御兜底
    _bFault := TRUE;
END_IF

(* —— 段 4：驻留超时锁存（判据当拍量） —— *)
IF (NOT _bFault) AND tonWatchTo.Q THEN
    _uFault := 16#0004_03AF;        // 故障级：驻留判据长期不满足
    _bFault := TRUE;
END_IF

(* —— 段 5：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；iAxis.bError = 当拍量；_bInBand AND _bQuiet = 当拍量。
     均不含锁存量（_bFault/_uFault），解除边真实可达。 —— *)
IF rtReset.Q AND (NOT iAxis.bError) AND _bInBand AND _bQuiet THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
END_IF

(* —— 段 6：信息码派生（当拍量判据） —— *)
bInpos := tonDwell.Q AND (NOT _bFault);     // 到位出口（驻留 TON 直出，故障期强制 FALSE）
IF (NOT _bFault) AND bEnable THEN
    IF bInpos AND (NOT _bInposPrev) THEN
        _uInfo := 16#0004_04AE;         // 信息级：到位沿
    END_IF
    IF _bTgtChg AND bInpos THEN
        _uInfo := 16#0004_04AF;         // 信息级：目标变更检出（驻留已复位）
    END_IF
    IF (NOT bInpos) AND _bInposPrev THEN
        _uInfo := 16#0004_04B0;         // 信息级：失去到位沿
    END_IF
END_IF

(* —— 段 7：出口单点映射（锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bInpos := FALSE;                // 故障期到位强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bFault := _bFault;                  // 锁存位出口
bError := _bFault;                  // 故障标志与锁存位同源
_bInposPrev := bInpos;              // 到位沿判据快照
_fTgtPrev := fTarget;               // 上拍目标快照（段末统一写）

END_FUNCTION_BLOCK
