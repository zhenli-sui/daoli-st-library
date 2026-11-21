//==============================================================================
// 功能块：FB_DL_StepperMicroFeedPulseEquiv ｜ 中文名称：步进细分脉冲当量换算与组态校验
// 所属子库：DL_Device ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：步进电机细分脉冲当量链换算——整步数 x 细分数 x 减速比 / 丝距
//           导程 → 脉冲当量（脉冲/mm 与 mm/脉冲），并按反向间隙换算补偿
//           脉冲数；组态域校验复用 FB_DL_PulseDirStepper 的组态纪律
//           （细分 1..256 整数、导程/整步数/减速比 > 0）。触发式：bExecute
//           上升沿启动计算，结果锁存至下次触发或复位。细分数非 2 的幂
//           按实际值照算并给信息级提示（驱动器只认 2 的幂档位时由
//           上层拦截，本件不阻断换算链可观测性）。
// 开源溯源 (Origin)：道莅原创实现（参考步进驱动细分与丝距传动工程惯例 分类与参数域）
// 单位表：整步数[步/转] / 细分数[倍] / 减速比[倍] / 导程[毫米每转] /
//         脉冲当量[脉冲每毫米] / 间隙[毫米] / 时间[ms]
// 错误码表：16#0003_0186 信息级（细分数非 2 的幂，按实际值照算，不置
//           bError）/ 16#0003_0187 信息级（反向间隙组态为 0，无间隙补偿
//           提请确认，不置 bError）/ 16#0003_035A 故障级（导程/整步数/
//           减速比 <= 0 或任一输入非有限，组态非法，置 bError）/
//           16#0003_035B 故障级（细分数 <= 0、> 256 或非整数，组态域
//           校验失败，置 bError——该场景不可由 035A 的比值类判据观测，
//           属细分数独立域） / 16#0003_035C 故障级兜底（状态机落 ELSE
//           或非法状态，置 bError）
// 状态机：E_DL_StepperEquivState（四态：eIdle=0 / eCalc=10 / eDone=20 /
//           eFault=99），CASE 含 ELSE 兜底，ELSE 置 035C 并冻结输出
// 边界行为：① 组态非法（035A/035B）→ 进故障态，输出冻结为零，bReset
//           复位；② 细分数非 2 的幂但域内整数 → 照算 + 信息 0186；
//           ③ 间隙为 0 → 照算 + 信息 0187（合法但提请确认）；
//           ④ eDone 态结果锁存保持，新触发沿才重算（防每拍抖动）；
//           ⑤ 失能（bExecute 撤销）不回零——当量是组态量非过程量，
//           锁存保持直至复位；⑥ 安全侧 = 故障态输出全零，禁止残当量
//           进入下游脉冲换算。
// 依赖纪律：Device 域组态件，复用 FB_DL_PulseDirStepper 组态纪律（域值
//           一致性由本件头注释承担验证责任，改动任一侧须复核另一侧）。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P2 §588）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_StepperEquivState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 当量计算触发式相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_StepperEquivState :
(
    eIdle  := 0,   // 空闲：等触发沿 / Idle, awaiting trigger edge
    eCalc  := 10,  // 计算中：本拍完成换算并转出 / Calculating, conversion completed within this scan
    eDone  := 20,  // 完成：结果锁存保持 / Done, results latched
    eFault := 99   // 故障：组态非法/非法状态 / Fault, illegal config or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_StepperMicroFeedPulseEquiv
VAR_INPUT
    bExecute     : BOOL;                    // 触发计算 [—]，上升沿生效 / Trigger calculation, rising edge
    bReset       : BOOL;                    // 故障复位 [—]，上升沿清故障态 / Fault reset, rising edge clears the fault state
    fStepsPerRev : LREAL := 200.0;          // 整步数 [步每转]，典型 200（1.8 度步距角） / Full steps per revolution [steps/rev], typical 200
    fMicroStep   : LREAL := 16.0;           // 细分数 [倍]，有效域 1..256 整数，非 2 的幂给信息级提示 / Microstepping divisor [count], valid range 1..256 integer
    fGearRatioIn : LREAL := 1.0;            // 减速比（电机转/丝杠转）[倍]，须 > 0 / Gear reduction ratio [ratio], must be > 0
    fLeadMm      : LREAL := 5.0;            // 丝杠导程 [毫米每转]，须 > 0 / Screw lead [mm/rev], must be > 0
    fBacklashMm  : LREAL := 0.0;            // 反向间隙 [毫米]，>= 0，为 0 给信息级提示 / Backlash [mm], >= 0, zero raises an info notice
END_VAR
VAR_OUTPUT
    fPulsePerMm    : LREAL;                 // 脉冲当量 [脉冲每毫米] / Pulse equivalent [pulses/mm]
    fMmPerPulse    : LREAL;                 // 反向当量 [毫米每脉冲] / Inverse equivalent [mm/pulse]
    fBacklashPulse : LREAL;                 // 间隙补偿脉冲数 [脉冲] / Backlash compensation pulses [pulses]
    eState         : E_DL_StepperEquivState; // 相位出口 [—] / Phase outlet
    eErr           : UDINT;                 // 错误码，0 = 无错，码位 16#0003_0186 起信息级、16#0003_035A 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError         : BOOL;                  // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                  // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbTrig       : R_TRIG;                  // 触发沿检测（待机/故障分支同样无条件刷新） / Trigger edge detector, refreshed unconditionally
    _eState      : E_DL_StepperEquivState := E_DL_StepperEquivState.eIdle; // 当前相位 / Current phase
    _bCfgBadA    : BOOL;                    // 035A 类组态非法锁存 / Config fault latch of class 035A
    _bCfgBadB    : BOOL;                    // 035B 类细分数域非法锁存 / Microstep domain fault latch
    _bInfoPow2   : BOOL;                    // 非 2 的幂信息当拍标志 / Non-power-of-two info flag of this scan
    _bInfoNoBl   : BOOL;                    // 间隙为零信息当拍标志 / Zero-backlash info flag of this scan
    _bIllegal    : BOOL;                    // 非法状态标志 / Illegal state flag
    _nMicroDi    : DINT;                    // 细分数整数副本 [倍] / Integer copy of the microstep divisor
    _bInit       : BOOL := FALSE;           // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
END_VAR
VAR CONSTANT
    DL_SPE_INF      : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_SPE_EPS      : LREAL := 1.0E-6;      // 浮点判零/整判容差 [倍] / Float zero and integrality tolerance [count]
    DL_SPE_MICRO_MAX: LREAL := 256.0;       // 细分数上限 [倍] / Microstep divisor ceiling [count]
    DL_SPE_ZERO     : LREAL := 0.0;         // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：输出安全侧清零，单拍标志预清零
 *      Outputs cleared fail-safe first, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
fPulsePerMm    := DL_SPE_ZERO;             // 脉冲当量先清（安全侧） / Pulse equivalent cleared first
fMmPerPulse    := DL_SPE_ZERO;             // 反向当量先清 / Inverse equivalent cleared first
fBacklashPulse := DL_SPE_ZERO;             // 间隙脉冲先清 / Backlash pulses cleared first
eErr   := 16#0000_0000;                     // 错误码每拍重算 / Error code recomputed
bError := FALSE;                            // 故障标志每拍重算 / Fault flag recomputed
bValid := FALSE;                            // 可用标志每拍重算 / Usable flag recomputed
_bInfoPow2 := FALSE;                        // 非 2 幂信息预清零 / Power-of-two info pre-cleared
_bInfoNoBl := FALSE;                        // 间隙零信息预清零 / Zero-backlash info pre-cleared
_bIllegal  := FALSE;                        // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState   := E_DL_StepperEquivState.eIdle; // 相位空闲起步 / Phase starts idle
    _bCfgBadA := FALSE;                     // 组态锁存清零 / Config latch cleared
    _bCfgBadB := FALSE;                     // 细分数锁存清零 / Microstep latch cleared
    _bInit    := TRUE;                      // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜触发沿无条件刷新（R40：CASE 之外每拍必调）
 *      Trigger edge refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbTrig(CLK := bExecute);                    // 触发沿检测 / Trigger edge detection

(*------------------------------------------------------------------------------
 * 段 4｜组态域校验闸：比值类（035A）与细分数域（035B）分域锁存
 *      Configuration gates in two domains, latched separately
 *-----------------------------------------------------------------------------*)
IF (fLeadMm <> fLeadMm) OR (ABS(fLeadMm) > DL_SPE_INF)
   OR (fStepsPerRev <> fStepsPerRev) OR (ABS(fStepsPerRev) > DL_SPE_INF)
   OR (fGearRatioIn <> fGearRatioIn) OR (ABS(fGearRatioIn) > DL_SPE_INF)
   OR (fBacklashMm <> fBacklashMm) OR (ABS(fBacklashMm) > DL_SPE_INF)
   OR (fMicroStep <> fMicroStep) OR (ABS(fMicroStep) > DL_SPE_INF) THEN
    _bCfgBadA := TRUE;                      // 非有限归入比值类非法（035A） / Non-finite folded into class 035A
END_IF
IF (NOT _bCfgBadA) AND ((fLeadMm <= DL_SPE_EPS) OR (fStepsPerRev <= DL_SPE_EPS)
   OR (fGearRatioIn < DL_SPE_EPS)) THEN
    _bCfgBadA := TRUE;                      // 比值类组态非法锁存（导程/整步数/减速比任一 <= 容差） / Ratio-class config latched
END_IF
IF (NOT _bCfgBadA) AND ((fMicroStep < (DL_SPE_ZERO + DL_SPE_EPS))
   OR (fMicroStep > DL_SPE_MICRO_MAX)) THEN
    _bCfgBadB := TRUE;                      // 细分数域外锁存（035B） / Microstep domain latched
END_IF
IF (NOT _bCfgBadA) AND (NOT _bCfgBadB) THEN
    IF ABS(fMicroStep - LREAL_TO_DINT(fMicroStep)) > DL_SPE_EPS THEN
        _bCfgBadB := TRUE;                  // 细分数非整数锁存（035B） / Non-integer microstep latched
    ELSE
        _nMicroDi := LREAL_TO_DINT(fMicroStep); // 整数副本（域内已闸，转换安全） / Integer copy, range-gated
        IF (_nMicroDi > 1) AND ((_nMicroDi AND (_nMicroDi - 1)) <> 0) THEN
            _bInfoPow2 := TRUE;             // 非 2 的幂：照算并提示（信息级） / Non-power-of-two, computed with an info notice
        END_IF
    END_IF
END_IF
IF (NOT _bCfgBadA) AND (ABS(fBacklashMm) <= DL_SPE_EPS) THEN
    _bInfoNoBl := TRUE;                     // 间隙为 0 提示（信息级） / Zero-backlash notice, info
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜相位机（CASE 含 ELSE 兜底；状态改写只出现在分支判据内，R39）
 *      Phase machine with ELSE fallback, state writes only inside branches
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_StepperEquivState.eIdle:          // 空闲：触发沿且组态合法进计算
        IF fbTrig.Q AND (NOT _bCfgBadA) AND (NOT _bCfgBadB) THEN
            _eState := E_DL_StepperEquivState.eCalc; // 进计算相 / To the calc phase
        ELSIF fbTrig.Q AND (_bCfgBadA OR _bCfgBadB) THEN
            _eState := E_DL_StepperEquivState.eFault; // 组态非法进故障 / Illegal config to fault
        END_IF

    E_DL_StepperEquivState.eCalc:          // 计算：本拍完成换算并转完成
        // 拍 N 进入（触发沿且组态合法）/ 本拍行为：换算并锁存 / 拍 N+1 转出：进 eDone 保持
        fPulsePerMm := fStepsPerRev * fMicroStep * fGearRatioIn / fLeadMm; // 脉冲当量 [脉冲每毫米]，分母已闸 / Pulse equivalent, denominator gated
        fMmPerPulse := 1.0 / fPulsePerMm;   // 反向当量 [毫米每脉冲]，分子恒 1 无除零路径 / Inverse equivalent, numerator is 1
        fBacklashPulse := fBacklashMm * fPulsePerMm; // 间隙补偿脉冲 [脉冲] / Backlash compensation pulses
        _eState := E_DL_StepperEquivState.eDone; // 进完成态锁存 / To done, results latched

    E_DL_StepperEquivState.eDone:          // 完成：结果锁存保持，新沿才重算
        IF fbTrig.Q AND (_bCfgBadA OR _bCfgBadB) THEN
            _eState := E_DL_StepperEquivState.eFault; // 组态漂移非法进故障 / Config drift to fault
        ELSIF fbTrig.Q THEN
            _eState := E_DL_StepperEquivState.eCalc; // 新触发沿重算 / New edge recomputes
        END_IF

    E_DL_StepperEquivState.eFault:         // 故障：复位沿且组态恢复合法回空闲
        IF bReset AND (NOT _bCfgBadA) AND (NOT _bCfgBadB) THEN
            _bCfgBadA := FALSE;             // 复位清锁存 / Reset clears the latch
            _bCfgBadB := FALSE;             // 复位清锁存 / Reset clears the latch
            _eState := E_DL_StepperEquivState.eIdle; // 回空闲 / Back to idle
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _eState   := E_DL_StepperEquivState.eFault; // 回故障态（输出全零） / Back to fault, outputs zeroed
END_CASE

(*------------------------------------------------------------------------------
 * 段 6｜码位出口与放行（故障级码 3 行内置 bError，R45/R101 配对）
 *      Code outlet and release, fault codes paired with bError
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0003_035C;                 // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF _bCfgBadA THEN
    eErr   := 16#0003_035A;                 // 故障级：比值类组态非法 / Fault: ratio-class config illegal
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF _bCfgBadB THEN
    eErr   := 16#0003_035B;                 // 故障级：细分数域校验失败 / Fault: microstep domain check failed
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF _bInfoPow2 THEN
    eErr := 16#0003_0186;                   // 信息级：细分数非 2 的幂照算 / Info: non-power-of-two divisor, computed as-is
ELSIF _bInfoNoBl THEN
    eErr := 16#0003_0187;                   // 信息级：间隙为 0 提请确认 / Info: zero backlash notice
END_IF

bValid := (NOT bError) AND (_eState = E_DL_StepperEquivState.eDone); // 仅完成态放行 / Usable only in the done phase
eState := _eState;                          // 相位出口 / Phase outlet
END_FUNCTION_BLOCK
