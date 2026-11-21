(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StdDevOnline
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（SQRT），零厂商私有库
 * 功能描述 (Function)   : Welford 单遍在线标准差（数值稳定型，免"先求和再减均方"的灾难性抵消）。
 *                         每次调用吞入一个样本，就地更新调用方持有的累加器 ST_DL_WelfordAcc：
 *                           nCount ← nCount + 1
 *                           fDelta  ← x − fMean
 *                           fMean   ← fMean + fDelta / nCount
 *                           fDelta2 ← x − fMean（注意用的是**更新后**的均值）
 *                           fM2     ← fM2 + fDelta × fDelta2
 *                         样本标准差 s = SQRT(fM2 / (nCount − 1))，返回 LREAL。
 * 无状态边界 (Stateless): **本 FC 自身零内部状态**（IEC 61131-3 的 FC 不得持有静态变量，本件遵守）。
 *                         全部跨拍状态由调用方通过 VAR_IN_OUT 累加器 stAcc 持有——这意味着：
 *                         ① 一个累加器实例 = 一路数据流，多路统计必须各用各的累加器（严禁共用）；
 *                         ② 调用方可在任意时刻把 stAcc 清零来重开统计窗（本件不提供隐式清零）；
 *                         ③ 本 FC 可重入、可并发、可放在任何 POU 内调用，结果只取决于入参与 stAcc。
 *                         若调用方希望"封装成自持状态的块"，请在外层包一层 FB 持有该累加器，
 *                         而不要把状态藏进本 FC（那会破坏无状态契约）。
 * 接口     (Interface)  : 入 fSample 新样本、stAcc 累加器（VAR_IN_OUT，读改写）；出 bValid 有效
 *                         （nCount >= 2 且样本有限）、fMean 当前均值、fM2 平方和、fStdDev 返回。
 * 边界     (Boundary)   : ① nCount < 2 → 标准差无定义，返回 0.0 且 bValid=FALSE（**不作 0 语义**
 *                         ——调用方必须查 bValid 才可用该值）；② 非有限样本（NaN/Inf，用 x<>x 自反
 *                         判 NaN、（x−x）<>(x−x) 判 Inf）→ 不入累加器、返回上次可用值域外的 0.0、
 *                         bValid=FALSE、bNonFin=TRUE——污染源绝不进状态，否则均值被永久毒化；
 *                         ③ fM2 累加可能因浮点误差出极小负值 → 开方前钳到 0（防 SQRT 负参得 NaN）；
 *                         ④ nCount 达上限 DL_WELFORD_MAX_N（16#00FF_FFFF）后不再自增，bSaturated=TRUE，
 *                         返回当前标准差（防 UDINT 回绕把 nCount 归零导致除零）。
 * 依赖     (Depends)    : 无 DL_ 内部依赖（仅本文件内的 ST_DL_WelfordAcc）；标准库仅 SQRT
 * 来源标签 (Source Tag) : T2-1 ◐（公开经典算法 Welford 1962 单遍方差；ST 重写 + 防御包装，零代码行复制）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。异常出口为 BOOL（bValid / bNonFin /
 *                         bSaturated）；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ n<2 防除零 + 非有限闸 + 负方差钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 1 · 序号 5）
 *==============================================================================*)

TYPE ST_DL_WelfordAcc :
STRUCT
    nCount : UDINT := 0;    // 已吞入样本数（调用方所有，须初值 0） [个] / Samples consumed, caller-owned, init 0
    fMean  : LREAL := 0.0;  // 当前均值 μ [工程单位] / Running mean [engineering unit]
    fM2    : LREAL := 0.0;  // 均值偏差平方和 Σ(x−μ)² [工程单位²] / Sum of squared deviations [unit squared]
END_STRUCT
END_TYPE

FUNCTION FC_DL_StdDevOnline : LREAL
VAR_INPUT
    fSample : LREAL := 0.0;    // 本拍新样本（非有限样本被拒收） [工程单位] / New sample this scan, non-finite samples rejected
END_VAR
VAR_IN_OUT
    stAcc : ST_DL_WelfordAcc;  // 累加器（调用方持有，本 FC 零内部状态） [混合] / Accumulator owned by caller, this FC holds no state
END_VAR
VAR_OUTPUT
    bValid     : BOOL;         // 标准差有效（nCount >= 2 且本拍样本被接收或历史可用） [-] / StdDev valid
    bNonFin    : BOOL;         // 本拍样本非有限，已被拒收（未污染累加器） [-] / Sample non-finite and rejected
    bSaturated : BOOL;         // 样本数已达上限，停止自增（防 UDINT 回绕） [-] / Sample count capped
    fMean      : LREAL;        // 当前均值（出口镜像，便于 HMI 直读） [工程单位] / Mean mirror for HMI
    fM2        : LREAL;        // 当前平方和（出口镜像） [工程单位²] / M2 mirror
END_VAR
VAR
    fDelta  : LREAL;           // x − 旧均值 [工程单位] / Sample minus old mean
    fDelta2 : LREAL;           // x − 新均值 [工程单位] / Sample minus new mean
    fVar    : LREAL;           // 样本方差（分母 n−1） [工程单位²] / Sample variance with n-1 denominator
END_VAR
VAR CONSTANT
    DL_WELFORD_MAX_N : UDINT := 16#00FF_FFFF;   // 样本数上限，留足余量防回绕 [个] / Sample cap with wrap margin
    DL_WELFORD_ZERO  : LREAL := 0.0;            // 零基准（负方差钳位用） [无量纲] / Zero baseline for variance clamping
END_VAR

(* —— 段 1：出口初始化（任何路径下返回值确定） —— *)
FC_DL_StdDevOnline := 0.0;      // 缺省返回 0.0，须配 bValid 才可用 / Default 0.0, meaningful only with bValid
bValid     := FALSE;            // 先假定无效 / Assume invalid
bNonFin    := FALSE;            // 非有限标志清零 / Non-finite flag cleared
bSaturated := FALSE;            // 饱和标志清零 / Saturation flag cleared

(* —— 段 2：非有限闸（污染源不入状态，否则均值被永久毒化） —— *)
bNonFin := (fSample <> fSample)                             // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive test
        OR ((fSample - fSample) <> (fSample - fSample));    // Inf 判：Inf−Inf 得 NaN，NaN≠NaN 为真 / Inf test via Inf minus Inf
IF bNonFin THEN
    fMean := stAcc.fMean;           // 回放当前均值，不改状态 / Replay mean without touching state
    fM2   := stAcc.fM2;             // 回放当前平方和 / Replay M2
    bValid := stAcc.nCount >= 2;    // 历史可用的前提下仍报有效（本拍未参与） / Still valid from history, sample excluded
    IF bValid THEN
        IF stAcc.nCount >= 2 THEN
            fVar := stAcc.fM2 / UDINT_TO_LREAL(stAcc.nCount - 1);    // 分母 n−1，n>=2 已闸 / n-1 denominator, guarded by n>=2
            IF fVar < DL_WELFORD_ZERO THEN
                fVar := DL_WELFORD_ZERO;                             // 负方差钳位（浮点误差） / Clamp negative variance
            END_IF
            FC_DL_StdDevOnline := SQRT(fVar);                        // 返回历史标准差 / Return historical StdDev
        END_IF
    END_IF
    RETURN;                         // 提前返回，累加器未被触碰 / Early return, accumulator untouched
END_IF

(* —— 段 3：样本数上限闸（防 UDINT 回绕把 nCount 归零） —— *)
IF stAcc.nCount >= DL_WELFORD_MAX_N THEN
    bSaturated := TRUE;                     // 达上限 / Cap reached
    fMean := stAcc.fMean;                   // 回放 / Replay
    fM2   := stAcc.fM2;                     // 回放 / Replay
    fVar  := stAcc.fM2 / UDINT_TO_LREAL(stAcc.nCount - 1);   // 上限远大于 2，分母安全 / Cap far above 2, denominator safe
    IF fVar < DL_WELFORD_ZERO THEN
        fVar := DL_WELFORD_ZERO;            // 负方差钳位 / Clamp
    END_IF
    FC_DL_StdDevOnline := SQRT(fVar);       // 返回当前标准差（不再更新） / Return current StdDev, no further update
    bValid := TRUE;                         // 历史统计仍有效 / Historical statistics still valid
    RETURN;
END_IF

(* —— 段 4：Welford 单遍更新（就地写回调用方累加器） —— *)
stAcc.nCount := stAcc.nCount + 1;                                   // 计数自增（已过上限闸） / Increment count, cap already gated
fDelta       := fSample - stAcc.fMean;                              // x − 旧均值 / Sample minus old mean
stAcc.fMean  := stAcc.fMean + (fDelta / UDINT_TO_LREAL(stAcc.nCount));   // 均值增量更新，分母 >= 1 恒安全 / Mean update, denominator >= 1
fDelta2      := fSample - stAcc.fMean;                              // x − 新均值 / Sample minus updated mean
stAcc.fM2    := stAcc.fM2 + (fDelta * fDelta2);                     // M2 累加（Welford 核心式） / M2 accumulation

(* —— 段 5：出口映射（n<2 无定义，返回 0 且 bValid=FALSE） —— *)
fMean := stAcc.fMean;               // 均值出口 / Mean outlet
fM2   := stAcc.fM2;                 // 平方和出口 / M2 outlet
IF stAcc.nCount >= 2 THEN
    fVar := stAcc.fM2 / UDINT_TO_LREAL(stAcc.nCount - 1);   // 样本方差（分母 n−1） / Sample variance
    IF fVar < DL_WELFORD_ZERO THEN
        fVar := DL_WELFORD_ZERO;                            // 负方差钳位（浮点误差不可开方） / Clamp negative variance
    END_IF
    FC_DL_StdDevOnline := SQRT(fVar);                       // 标准差 / Standard deviation
    bValid := TRUE;                                         // 有效 / Valid
ELSE
    FC_DL_StdDevOnline := 0.0;                              // 单样本无离散度，返回 0 但标无效 / Single sample: 0 but invalid
    bValid := FALSE;
END_IF

END_FUNCTION
