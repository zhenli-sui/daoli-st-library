(*==============================================================================
 * 组件名称 (Component)  : FC_DL_RampStepReal
 * 所属子库 (Sublibrary) : DL_MathData ｜ 版本 (Version) : 1.0.0 ｜ 2026-11-23
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符与 ABS，零厂商私有库
 * 功能描述 (Function)   : 固定步长爬坡（FC 形态，纯组合逻辑）：把当前值 fX 沿目标 fXTarget
 *                         方向每拍最多推进 fStep，剩余量不足一步时直接到达目标（无过冲）。
 *                         fStep ≤ 0 → 不爬坡，直接输出 fXTarget（开关量式跳变，信息级 eDirectJump）。
 *                         本件不持有跨拍状态：当前值由调用方以 fX 传入，故可重入、可多处例化。
 * 接口     (Interface)  : 输入 fX 当前值 [工程单位]、fXTarget 目标值 [工程单位]、
 *                         fStep 每拍最大步长，有效域 > 0 [工程单位/拍]；
 *                         输出 fY 爬坡后输出 [工程单位]、bArrived 到达标志（本拍已在目标上）、
 *                         eErrCode（E_DL_RampStepErr）；返回值 = 数值可信标志。
 * 边界     (Boundary)   : ① fStep ≤ 0 → 直通目标（信息级 eDirectJump，返回值 TRUE）。
 *                         ② 任一浮点入参非有限 → 故障级 eNonFinite，fY = 0 哨兵，返回 FALSE。
 *                         ③ 到达判定用容差 DL_RSTP_EPS（1E-6），禁浮点判等（R4）。
 *                         ④ 输出复检非有限 → 回退 fX 并报故障（保持上一有效当前值）。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口为 BOOL + REAL +
 *                         本文件内 enum E_DL_RampStepErr（全库唯一属主）。
 * 分工声明 (Scope)      : 带到达判定与跨周期驻留的斜坡发生器归 FB_DL_RampGenerator 与
 *                         FB_DL_RampSoakProfile；本件只做单拍步进决策，不积分、不驻留。
 * 归属     (Ownership)  : E_DL_RampStepErr 归属本文件（全库唯一属主，R264）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ 非有限双判 +
 *                         容差比较 + 无除法 ｜ R5 ✓ 逐行同行双语注释 ｜ R6 N/A（纯函数）
 *                         R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R78-B2 首版
 * 验收向量 (Acceptance) :
 *   A1 fX=0.0, fXTarget=10.0, fStep=3.0 → fY=3.0, bArrived=FALSE, eStepping；
 *   A2 fX=8.5, fXTarget=10.0, fStep=3.0 → 剩余 1.5 < 3.0 → fY=10.0, bArrived=TRUE, eArrived；
 *   A3 fX=10.0, fXTarget=0.0, fStep=4.0 → fY=6.0（下行），eStepping；
 *   A4 fX=0.0, fXTarget=10.0, fStep=0.0 → fY=10.0, eDirectJump, 返回 TRUE；
 *   A5 fXTarget=NaN → fY=0.0, eNonFinite, 返回 FALSE。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_RampStepErr（步长爬坡出口码；信息级 = 0..9，故障级 = 10 起）
 *----------------------------------------------------------------------------*)
TYPE E_DL_RampStepErr :
(
    eArrived    := 0,   // 信息级：本拍已到达目标 / Info: target reached this scan
    eStepping   := 1,   // 信息级：本拍推进一个步长 / Info: one step advanced this scan
    eDirectJump := 2,   // 信息级：步长越域，直接跳变到目标 / Info: step out of domain, jumped to target
    eNonFinite  := 10   // 故障级：入参或结果非有限 / Fault: non-finite input or result
);
END_TYPE

FUNCTION FC_DL_RampStepReal : BOOL
VAR_INPUT
    fX       : REAL;   // 当前值（调用方持有的实际值）[工程单位] / Current value held by the caller in engineering unit
    fXTarget : REAL;   // 目标值 [工程单位] / Target value in engineering unit
    fStep    : REAL;   // 每拍最大步长，有效域 > 0 [工程单位/拍] / Max step per scan, valid domain > 0
END_VAR
VAR_OUTPUT
    fY       : REAL;              // 爬坡后输出 [工程单位] / Ramped output in engineering unit
    bArrived : BOOL;              // 到达标志：本拍输出已在目标容差内 [-] / Arrived flag within tolerance this scan
    eErrCode : E_DL_RampStepErr;   // 出口码 [-] / Outlet code
END_VAR
VAR
    _bBadX      : BOOL;   // fX 非有限标志 [-] / Non-finite flag of fX
    _bBadTarget : BOOL;   // fXTarget 非有限标志 [-] / Non-finite flag of fXTarget
    _bBadStep   : BOOL;   // fStep 非有限标志 [-] / Non-finite flag of fStep
    _fRemain    : REAL;   // 剩余量 = 目标 − 当前 [工程单位] / Remaining distance in engineering unit
    _fAbsRemain : REAL;   // 剩余量绝对值 [工程单位] / Absolute remaining distance
END_VAR
VAR CONSTANT
    DL_RSTP_ZERO : REAL := 0.0;     // 零基准与符号分界 [-] / Zero base and sign boundary
    DL_RSTP_EPS  : REAL := 1.0E-6;  // 到达判定容差 [-] / Arrival tolerance
END_VAR

(* —— 段 0：出口预置安全侧 —— *)
FC_DL_RampStepReal := FALSE;                         // 返回值预置不可信 / Return preset not trustworthy
fY       := DL_RSTP_ZERO;                            // 输出哨兵 0 / Output sentinel
bArrived := FALSE;                                   // 到达标志预清（单拍位统一预置）/ Single-shot flag preset
eErrCode := E_DL_RampStepErr.eNonFinite;             // 预置最严码 / Preset strictest code

(* —— 段 1：入参非有限闸（R272 全量枚举 fX / fXTarget / fStep） —— *)
_bBadX      := (fX <> fX) OR ((fX - fX) <> DL_RSTP_ZERO);                    // 当前值非有限 / Current value non-finite
_bBadTarget := (fXTarget <> fXTarget) OR ((fXTarget - fXTarget) <> DL_RSTP_ZERO);  // 目标非有限 / Target non-finite
_bBadStep   := (fStep <> fStep) OR ((fStep - fStep) <> DL_RSTP_ZERO);        // 步长非有限 / Step non-finite
IF _bBadX OR _bBadTarget OR _bBadStep THEN
    RETURN;                                          // 故障出口：fY 保持 0 哨兵 / Fault exit, sentinel kept
END_IF

(* —— 段 2：步长域闸（fStep ≤ 0 → 不做爬坡，直接跳变到目标） —— *)
IF fStep <= DL_RSTP_ZERO THEN
    fY       := fXTarget;                            // 直通目标 / Jump straight to the target
    bArrived := TRUE;                                // 目标即到位 / Target equals arrival
    eErrCode := E_DL_RampStepErr.eDirectJump;        // 信息级：直接跳变 / Info: direct jump
    FC_DL_RampStepReal := TRUE;                      // 输出可信 / Output trustworthy
    RETURN;
END_IF

(* —— 段 3：剩余量与步进决策（不足一步即到达，结构性无过冲） —— *)
_fRemain    := fXTarget - fX;                        // 剩余量 / Remaining distance
_fAbsRemain := ABS(_fRemain);                        // 剩余量绝对值 / Absolute remaining distance
IF _fAbsRemain <= DL_RSTP_EPS THEN
    fY       := fXTarget;                            // 已在目标上：锁定目标 / Already there: lock the target
    bArrived := TRUE;                                // 到达标志 / Arrived flag
    eErrCode := E_DL_RampStepErr.eArrived;           // 信息级：已到达 / Info: arrived
ELSIF _fAbsRemain <= (fStep + DL_RSTP_EPS) THEN
    fY       := fXTarget;                            // 剩余不足一步：到达且不过冲 / Sub-step remainder: arrive without overshoot
    bArrived := TRUE;                                // 到达标志 / Arrived flag
    eErrCode := E_DL_RampStepErr.eArrived;           // 信息级：已到达 / Info: arrived
ELSE
    IF _fRemain > DL_RSTP_ZERO THEN
        fY := fX + fStep;                            // 上行推进一个步长 / Step upward
    ELSE
        fY := fX - fStep;                            // 下行推进一个步长 / Step downward
    END_IF
    bArrived := FALSE;                               // 未到达 / Not arrived
    eErrCode := E_DL_RampStepErr.eStepping;          // 信息级：推进中 / Info: stepping
END_IF

(* —— 段 4：结果复检（推进后非有限 → 回退当前值并报故障） —— *)
IF (fY <> fY) OR ((fY - fY) <> DL_RSTP_ZERO) THEN
    fY       := fX;                                  // 回退当前值 / Fall back to the current value
    bArrived := FALSE;                               // 到达标志撤销 / Arrival flag withdrawn
    eErrCode := E_DL_RampStepErr.eNonFinite;         // 故障级码 / Fault-level code
    FC_DL_RampStepReal := FALSE;                     // 故障出口不可信 / Fault exit not trustworthy
    RETURN;
END_IF

FC_DL_RampStepReal := TRUE;                          // 输出可信 / Output trustworthy
END_FUNCTION
