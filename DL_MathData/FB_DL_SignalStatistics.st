(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SignalStatistics
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS / MIN / SQRT），无厂商方言
 * 功能描述 (Function)   : 采样流实时统计分析器，滑动窗口（2..64）内输出均值、
 *                         最小值、最大值、峰峰值、样本方差、样本标准差、样本数
 *                         七元组。用于 PID 整定前的噪声评估、SPC 过程能力分析、
 *                         称重稳定性判定、振动烈度监视。
 *                         方差用两遍法：第一遍求均值，第二遍累加离差平方和。
 * 本文件内含       : E_DL_StatState（枚举，归属本组件）
 *                    FB_DL_SignalStatistics（功能块主体）
 * 开源溯源 (Origin)     : 原创实现（参考西门子 LGF 数学组的统计函数分类方式
 *                         与 OSCAT Basic 的标准差/方差/极差行为定义（EPL-2.0）；
 *                         OSCAT 为整数组一次计算，本块为流式窗口，语义不同，
 *                         clean-room 编写，未复制任何源码）。
 * 依赖     (Depends)    : 无 DL_ 内部依赖
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3，累加用 LREAL 并显式转回 REAL
 *                         R4 ✓ 窗口钳位 + 环形取数正数化取模 + 除零前判 n<2 + NaN 跳过
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ ENUM + CASE + ELSE 兜底
 *                         R7 N/A（无定时器/边沿实例）
 *
 * 【方差公式披露 / Variance-formula disclosure（边界 B1）】
 *   **必须两遍法**。"平方和减均值平方"（E[x²] − E[x]²）在均值远大于标准差时
 *   （如 1000.0 ± 0.01）因灾难性抵消会算出负方差或 0，是 SPC 场景的
 *   经典事故。本块两遍遍历，多一遍 O(n) 换数值安全。
 *
 * 【样本方差口径 / Sample-variance convention（边界 B4）】
 *   用 n−1 分母（样本方差），因为 PLC 拿到的是抽样：与 Excel 的 STDEV.S
 *   一致，不是 STDEV.P。n < 2 时不做除法，方差与标准差输出 0 并置
 *   16#0002_0009（样本不足，瞬时码）。
 *
 * 【极值重算披露 / Extrema-recalc disclosure（边界 B3）】
 *   窗口滑动时若滑出的样本恰为当前极值，增量维护会残留旧极值；
 *   本块每拍随均值遍历一并重算极值（64 点代价可接受），简单且可验证。
 *
 * 【数值类型披露 / Numeric-type disclosure（边界 B7）】
 *   累加与离差用 LREAL（仅为抗累加误差），输出显式转回 REAL，
 *   与现场模拟量量程口径一致。
 *
 * 【验收向量 / Acceptance vectors】
 *   V1  窗口 8，序列 2,4,4,4,5,5,7,9 → fMean = 5.0、fMin = 2、fMax = 9、
 *       fRange = 7、fVariance = 32/7 ≈ 4.5714、fStdDev ≈ 2.1381
 *   V2  单样本 42 → fMean = 42、fVariance = 0、bStatValid = FALSE、16#0002_0009
 *   V3  8 个 3.0 → fMean = 3.0、fVariance = 0.0（非负、非 NaN，边界 B5）
 *   V4  1000.0 与 1000.01 交替 8 个 → 方差 ≈ 2.857e-5（远大于 0，
 *       证明两遍法未发生灾难性抵消）
 *   V5  窗口设 65 → 生效 64、16#0001_0001
 *   V6  V1 后 bClear 一拍 → nCount = 0、bValid = FALSE
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 收口批次 · R3）
 *============================================================================*)
TYPE E_DL_StatState :
(
    eEmpty   := 0,    // 无样本 / No samples yet
    eFilling := 10,   // 样本不足窗口，均值与极值已可用 / Filling, mean and extrema already valid
    eReady   := 20,   // 窗口已满，全部统计量有效 / Window full, all statistics valid
    eFault   := 99    // 参数事件当拍（已钳位，下拍恢复）/ Parameter event scan, clamped, recovers next scan
);
END_TYPE

FUNCTION_BLOCK FB_DL_SignalStatistics
VAR_INPUT
    fIn       : REAL;                      // 采样输入 [EU] / Sample input [EU]
    bSample   : BOOL := TRUE;              // TRUE = 本拍采一个样本（给单周期脉冲即按需采样） / TRUE: take one sample this scan
    nWindow   : INT   := 32;               // 窗口长度，2..64，越界自动钳位 / Window length, range 2..64, clamped
    bClear    : BOOL;                      // TRUE：清空窗口重新统计 / TRUE: clear window and restart
END_VAR
VAR_OUTPUT
    fMean     : REAL;                      // 窗口均值 [EU] / Window mean [EU]
    fMin      : REAL;                      // 窗口最小值 [EU] / Window minimum [EU]
    fMax      : REAL;                      // 窗口最大值 [EU] / Window maximum [EU]
    fRange    : REAL;                      // 峰峰值 fMax − fMin [EU] / Peak-to-peak [EU]
    fVariance : REAL;                      // 样本方差（n−1）[EU²] / Sample variance [EU^2]
    fStdDev   : REAL;                      // 样本标准差 [EU] / Sample standard deviation [EU]
    nCount    : INT;                       // 当前有效样本数 [个] / Valid sample count
    bValid    : BOOL;                      // 至少有 1 个样本（均值/极值有效） / At least one sample, mean valid
    bStatValid: BOOL;                      // 方差/标准差有效（n ≥ 2） / Variance valid, needs n ≥ 2
    uErrorId  : UDINT;                     // 故障码，0 = 无故障（本块码均为瞬时，逐拍重算） / Error code, transient, recomputed every scan
    eState    : E_DL_StatState;            // 当前状态（供诊断） / Current state for diagnostics
END_VAR
VAR
    afWindow  : ARRAY[0..63] OF REAL;      // 环形样本窗 [EU] / Circular sample window [EU]
    nWrite    : INT;                       // 写指针，值域 0..63 / Write index, range 0..63
    nCountInt : INT;                       // 有效样本数（内部） / Internal valid sample count
    nWinEff   : INT;                       // 生效窗口（钳位后） / Effective window after clamping
    nLastWin  : INT;                       // 上拍生效窗口（变更检测，触发整窗重填） / Previous window, change forces refill
    nK        : INT;                       // 遍历索引 / Traversal index
    nIdx      : INT;                       // 环形取数换算下标 / Resolved ring index
    fSum      : LREAL;                     // 均值累加器（宽类型抗漂移） / Sum accumulator for the mean
    fMeanInt  : LREAL;                     // 均值中间量 / Mean intermediate
    fVarAcc   : LREAL;                     // 离差平方和 / Sum of squared deviations
    fTmp      : LREAL;                     // 单点离差 / Single deviation
    fMinInt   : REAL;                      // 本拍重算的窗口最小值 [EU] / Recomputed window minimum [EU]
    fMaxInt   : REAL;                      // 本拍重算的窗口最大值 [EU] / Recomputed window maximum [EU]
    nGuard    : INT;                       // 遍历防死锁计数器 / Traversal guard counter
    bParamEvt : BOOL;                      // 本拍发生参数钳位或窗口变更 / Parameter clamp or window change this scan
    eStateInt : E_DL_StatState;            // 内部状态机当前态 / Internal state machine state
END_VAR
VAR CONSTANT
    DL_STAT_WIN_MIN : INT   := 2;         // 最小窗口（方差需 n ≥ 2） / Minimum window, variance needs n ≥ 2
    DL_STAT_WIN_MAX : INT   := 64;        // 最大窗口（= 数组维度） / Maximum window, equals the array dimension
    DL_STAT_CAP     : INT   := 64;        // 环形容量，必须与数组维度严格一致 / Ring capacity, must match the array
    DL_STAT_GUARD   : INT   := 256;       // 单遍遍历防死锁上限（容量 × 4） / Traversal guard limit, capacity times 4
    DL_STAT_INF_LIM : REAL  := 1.0E30;    // 非有限值判据阈值（超此视为 Inf） / Infinity threshold for non-finite detection
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜故障码本周期清零：本块故障码全部为瞬时码，逐拍重算
 *      Error code cleared every scan: all codes are transient
 *-----------------------------------------------------------------------------*)
uErrorId  := 16#0000_0000;
bParamEvt := FALSE;

(*------------------------------------------------------------------------------
 * 段 2｜窗口规整：越界钳位，只在本拍置码不刷屏
 *      Window normalization: clamp, code set only on the event scan
 *-----------------------------------------------------------------------------*)
nWinEff := nWindow;
IF nWinEff < DL_STAT_WIN_MIN THEN
    nWinEff  := DL_STAT_WIN_MIN;
    bParamEvt := TRUE;
END_IF
IF nWinEff > DL_STAT_WIN_MAX THEN
    nWinEff  := DL_STAT_WIN_MAX;
    bParamEvt := TRUE;
END_IF
IF bParamEvt THEN
    uErrorId := 16#0001_0001;           // 窗口非法已钳位 / Window invalid, clamped
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜窗口变更检测（R14 语义参数变更）：生效窗口与上拍不同 → 整窗作废
 *      Window change detection: effective window differs, whole window voided
 *-----------------------------------------------------------------------------*)
IF nWinEff <> nLastWin THEN
    nCountInt := 0;
    nWrite    := 0;
    IF nLastWin <> 0 THEN               // 上电首扫不算参数事件 / Power-up first scan is not a parameter event
        uErrorId  := 16#0001_0001;      // 窗口变更触发重填 / Window change forces refill
        bParamEvt := TRUE;
    END_IF
END_IF
nLastWin := nWinEff;

(*------------------------------------------------------------------------------
 * 段 4｜清空：电平触发，先于采样处理
 *      Clear: level-triggered, handled before sampling
 *-----------------------------------------------------------------------------*)
IF bClear THEN
    nCountInt := 0;
    nWrite    := 0;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜采样（边界：NaN/Inf 跳过不入窗）
 *      Sampling: NaN or Inf samples are skipped, never stored
 *-----------------------------------------------------------------------------*)
IF bSample THEN
    IF (fIn <> fIn) OR (ABS(fIn) > DL_STAT_INF_LIM) THEN
        uErrorId := 16#0001_0006;       // 样本非有限值已跳过 / Non-finite sample skipped
    ELSIF (nWrite >= 0) AND (nWrite < DL_STAT_CAP) THEN
        (* 写指针双检（红线 R4）：MOD 已保证范围，仍显式兜底防越界写 *)
        (* Write index double check: explicit guard besides MOD *)
        afWindow[nWrite] := fIn;
        nWrite    := (nWrite + 1) MOD DL_STAT_CAP;
        nCountInt := MIN(nCountInt + 1, nWinEff);
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜第一遍：均值与极值（边界 B3 极值每拍重算，边界 B7 宽类型累加）
 *      Pass 1: mean and extrema, extrema recomputed every scan
 *-----------------------------------------------------------------------------*)
IF nCountInt > 0 THEN

    fSum   := 0.0;
    nGuard := 0;
    FOR nK := 0 TO (nCountInt - 1) DO
        nGuard := nGuard + 1;
        IF nGuard > DL_STAT_GUARD THEN
            uErrorId := 16#0001_0004;   // 遍历保护触发，保留已算部分 / Traversal guard tripped, partial result kept
            EXIT;
        END_IF
        (* 正数化取模：先加两倍容量再取模，规避负数取模的平台差异 *)
        (* Positive modulo: add twice the capacity before MOD, platform-safe *)
        nIdx := (nWrite - 1 - nK + DL_STAT_CAP * 2) MOD DL_STAT_CAP;
        IF (nIdx < 0) OR (nIdx >= DL_STAT_CAP) THEN
            uErrorId := 16#0001_0004;   // 下标越界兜底（红线 R4） / Index guard fallback
            EXIT;
        END_IF
        fSum := fSum + afWindow[nIdx];
        IF nK = 0 THEN
            fMinInt := afWindow[nIdx];  // 首样本作极值哨兵 / First sample seeds both extrema
            fMaxInt := afWindow[nIdx];
        ELSE
            IF afWindow[nIdx] < fMinInt THEN
                fMinInt := afWindow[nIdx];
            END_IF
            IF afWindow[nIdx] > fMaxInt THEN
                fMaxInt := afWindow[nIdx];
            END_IF
        END_IF
    END_FOR;

    fMeanInt := fSum / INT_TO_LREAL(nCountInt);  // nCountInt > 0 已由段 6 入口保证 / Guaranteed positive at this point

    (*------------------------------------------------------------------------------
     * 段 7｜第二遍：离差平方和（边界 B1 两遍法，边界 B2 除零前判 n < 2）
     *      Pass 2: squared deviations, division guarded by n < 2
     *-----------------------------------------------------------------------------*)
    IF nCountInt >= 2 THEN

        fVarAcc := 0.0;
        nGuard  := 0;
        FOR nK := 0 TO (nCountInt - 1) DO
            nGuard := nGuard + 1;
            IF nGuard > DL_STAT_GUARD THEN
                uErrorId := 16#0001_0004;   // 遍历保护触发 / Traversal guard tripped
                EXIT;
            END_IF
            nIdx := (nWrite - 1 - nK + DL_STAT_CAP * 2) MOD DL_STAT_CAP;
            IF (nIdx < 0) OR (nIdx >= DL_STAT_CAP) THEN
                uErrorId := 16#0001_0004;   // 下标越界兜底（红线 R4） / Index guard fallback
                EXIT;
            END_IF
            fTmp    := afWindow[nIdx] - fMeanInt;
            fVarAcc := fVarAcc + fTmp * fTmp;
        END_FOR;

        fVarAcc := fVarAcc / INT_TO_LREAL(nCountInt - 1);  // n ≥ 2 已判，分母 ≥ 1 / Guarded, denominator ≥ 1

        (* 负方差钳位：浮点舍入可能给出 -1e-20 量级的负零，必须归零 *)
        (* Negative variance clamp: rounding may yield tiny negative zeros *)
        IF fVarAcc < 0.0 THEN
            fVarAcc := 0.0;
        END_IF

    ELSE
        fVarAcc   := 0.0;
        uErrorId  := 16#0002_0009;      // 样本不足（N < 2，方差无定义）/ Too few samples for variance
    END_IF

ELSE
    fSum      := 0.0;
    fMeanInt  := 0.0;
    fVarAcc   := 0.0;
    fMinInt   := 0.0;
    fMaxInt   := 0.0;
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜派生统计量：标准差与峰峰值，显式 LREAL_TO_REAL 回写
 *      Derived statistics: standard deviation and peak-to-peak, explicit casts
 *-----------------------------------------------------------------------------*)
fMean     := LREAL_TO_REAL(fMeanInt);
fVariance := LREAL_TO_REAL(fVarAcc);
fStdDev   := LREAL_TO_REAL(SQRT(fVarAcc));
fMin      := fMinInt;
fMax      := fMaxInt;
fRange    := fMaxInt - fMinInt;

(*------------------------------------------------------------------------------
 * 段 9｜状态派生与主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      State derivation and main state machine with ELSE fallback
 *-----------------------------------------------------------------------------*)
IF bParamEvt THEN
    eStateInt := E_DL_StatState.eFault;
ELSIF nCountInt <= 0 THEN
    eStateInt := E_DL_StatState.eEmpty;
ELSIF nCountInt < nWinEff THEN
    eStateInt := E_DL_StatState.eFilling;
ELSE
    eStateInt := E_DL_StatState.eReady;
END_IF

CASE eStateInt OF

    E_DL_StatState.eEmpty:
        (* 无样本：统计量保持段 8 的零值，bValid 由段 10 置 FALSE / No samples *)

    E_DL_StatState.eFilling:
        (* 填充中：均值/极值已有效，方差是否有效由 bStatValid 表达（边界 B4） *)
        (* Filling: mean valid, variance validity carried by bStatValid *)

    E_DL_StatState.eReady:
        (* 就绪：全部统计量有效 / Ready: all statistics valid *)

    E_DL_StatState.eFault:
        (* 参数事件当拍：参数已修正、下拍恢复，不锁存 / Event scan, recovers next scan *)

    ELSE
        (* 非法状态一律回故障态并置码（红线 R6） *)
        (* Illegal state falls back to fault with a code *)
        eStateInt := E_DL_StatState.eFault;
        uErrorId  := 16#0001_0005;

END_CASE

(*------------------------------------------------------------------------------
 * 段 10｜输出单一出口：有效标志由计数派生
 *      Single output exit: validity flags derived from the count
 *-----------------------------------------------------------------------------*)
nCount     := nCountInt;
bValid     := (nCountInt > 0);
bStatValid := (nCountInt >= 2);
eState     := eStateInt;
END_FUNCTION_BLOCK
