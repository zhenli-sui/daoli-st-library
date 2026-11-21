(*
    FC_DL_CpkIndex —— 过程能力指数 Cp / Cpk
    ------------------------------------------------------------------
    分类      : DL_MathData / Statistics
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : 自研（Cp / Cpk 为公开统计定义）；ISO 22400-2 质量口径仅作术语参考
                （T2-8 次源，不复制任何条款文本）；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 由样本数组算 Cp、Cpk、均值与样本标准差（n-1 分母），供质量工站实时判
                工序能力（Cpk 小于 1.33 报警）；与 SignalStatistics 的分界是本件以规格
                限为输入、以能力指数为出口，不做通用统计量集合；
                防御链：规格限合法性闸 → 样本数闸 → 非有限样本逐点剔除 → σ 近零饱和闸
                → 六倍σ除号闸，每一闸都在除法之前；
                累加与方差用 LREAL 中间量，64 点大值平方不会溢出（R10 同纪律）。
    错误码    : 16#0001_0243 σ 近零，Cp / Cpk 已按饱和上限输出（常数样本，合法工况）——信息级，不置故障
                16#0001_0244 预留禁用（信息级，不得挪用）
                16#0001_031B 有效样本数不足（小于 2），无法计算——故障级，返回 0
                16#0001_031C 规格限非法（上限不大于下限）——故障级，返回 0
                16#0001_031D 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0243 用 / 16#0001_0244 预留 ｜ 16#0001_031B 用 / 16#0001_031C 用 / 16#0001_031D 预留
    状态机    : N/A —— 纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 纯组合函数，无定时器、无内部驻留状态；样本窗由调用方滚动填充，
                本件按 uCount 指定的前缀区间读取，绝不读取未填充的尾部。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)
FUNCTION FC_DL_CpkIndex : REAL
VAR_INPUT
    afSample : ARRAY[0..63] OF REAL;           // 样本数组，有效项 0~uCount-1 [用户单位] / sample array, valid items 0~uCount-1 [user unit]
    uCount   : UINT := 0;                      // 样本数 [个]，范围 2~64 / sample count [item], range 2~64
    fLsl     : REAL := 0.0;                    // 规格下限 [用户单位] / lower specification limit [user unit]
    fUsl     : REAL := 1.0;                    // 规格上限，必须大于下限 [用户单位] / upper specification limit, must exceed the lower one [user unit]
    fCpkSat  : REAL := 10.0;                   // Cpk 饱和上限（σ 近零时输出此值）[无量纲]，范围 1.0~100.0 / Cpk saturation cap [dimensionless], range 1.0~100.0
END_VAR
VAR_OUTPUT
    fCp        : REAL;                         // 潜在能力指数（不含偏移）[无量纲] / potential capability index without offset [dimensionless]
    fCpk       : REAL;                         // 实际能力指数，返回值的镜像 [无量纲] / actual capability index, mirror of the return value [dimensionless]
    fMean      : REAL;                         // 样本均值 [用户单位] / sample mean [user unit]
    fSigma     : REAL;                         // 样本标准差（n-1 分母）[用户单位] / sample standard deviation with n-1 denominator [user unit]
    eErr       : UDINT;                        // 错误码，0=正常 / error id, 0=ok
    bError     : BOOL;                         // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid     : BOOL;                         // 结果是否可用 / result usable flag
    bSaturated : BOOL;                         // 因 σ 近零而饱和 / saturated because sigma is near zero
END_VAR
VAR
    uIdx     : UINT;                           // 样本游标 [个] / sample cursor [item]
    uValidN  : UINT;                           // 剔除后有效样本数 [个] / valid sample count after removal [item]
    uKicked  : UINT;                           // 被剔除的非有限样本数 [个] / non-finite samples removed [item]
    fSum     : LREAL;                          // 样本和，LREAL 中间量防溢出 [用户单位] / sample sum, LREAL intermediate against overflow [user unit]
    fSumSq   : LREAL;                          // 偏差平方和，LREAL 中间量防溢出 [用户单位平方] / sum of squared deviations, LREAL intermediate [user unit squared]
    fDev     : REAL;                           // 单个样本偏差 [用户单位] / single sample deviation [user unit]
    fMeanL   : LREAL;                          // 均值 LREAL 中间量 [用户单位] / mean as LREAL intermediate [user unit]
    fVar     : LREAL;                          // 样本方差（n-1 分母）[用户单位平方] / sample variance with n-1 denominator [user unit squared]
    fSpan    : REAL;                           // 六倍标准差，Cp 分母 [用户单位] / six sigma span, the Cp denominator [user unit]
    fUpper   : REAL;                           // 上侧能力 [无量纲] / upper side capability [dimensionless]
    fLower   : REAL;                           // 下侧能力 [无量纲] / lower side capability [dimensionless]
    bNonFin  : BOOL;                           // 单个样本非有限判定标志 / single sample non-finite flag
END_VAR
VAR CONSTANT
    DL_CPK_MAX_N     : UINT := 64;             // 样本数上限 [个] / sample count upper bound [item]
    DL_CPK_MIN_N     : UINT := 2;              // 样本数下限，n 小于 2 时 σ 无定义 [个] / sample count lower bound, sigma is undefined below two [item]
    DL_CPK_LAST_IDX  : UINT := 63;             // 样本数组末索引 [个] / last sample index [item]
    DL_FLOAT_EPS     : REAL := 1.0E-6;         // 浮点判等容差 [用户单位] / float equality tolerance [user unit]
    DL_CPK_INF_GUARD : REAL := 4.0E38;         // 非有限幅值判定阈值 [用户单位] / non-finite magnitude guard [user unit]
    DL_CPK_SIGMA_K    : REAL := 3.0;           // 单侧三倍标准差 [无量纲] / three sigma per side [dimensionless]
    DL_CPK_SIGMA_6    : REAL := 6.0;           // 双侧六倍标准差 [无量纲] / six sigma over both sides [dimensionless]
    DL_CPK_SAT_MIN    : REAL := 1.0;           // 饱和上限下限 [无量纲] / lower bound of the saturation cap [dimensionless]
    DL_CPK_SAT_MAX    : REAL := 100.0;         // 饱和上限上限 [无量纲] / upper bound of the saturation cap [dimensionless]
    DL_CPK_ZERO       : REAL := 0.0;           // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
    DL_CPK_N1         : UINT := 1;             // n-1 分母的减数 [个] / subtrahend of the n-1 denominator [item]
END_VAR

// 段 1｜返回值与输出预置 / segment 1, preset return value and outputs
FC_DL_CpkIndex := DL_CPK_ZERO;                 // 故障缺省返回 0 / fault default returns zero
fCp := DL_CPK_ZERO;                            // Cp 预置 0 / preset Cp to zero
fCpk := DL_CPK_ZERO;                           // Cpk 预置 0 / preset Cpk to zero
fMean := DL_CPK_ZERO;                          // 均值预置 0 / preset the mean to zero
fSigma := DL_CPK_ZERO;                         // 标准差预置 0 / preset sigma to zero
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault
bValid := FALSE;                               // 预置结果不可用 / preset unusable
bSaturated := FALSE;                           // 预置未饱和 / preset not saturated
uValidN := 0;                                  // 有效样本数清零 / clear the valid count
uKicked := 0;                                  // 剔除数清零 / clear the removed count
fSum := 0.0;                                   // 求和清零 / clear the sum
fSumSq := 0.0;                                 // 平方和清零 / clear the squared sum

// 段 2｜饱和上限闸：越域即钳位，符号方向写进注释 / segment 2, saturation cap gate
IF (fCpkSat < DL_CPK_SAT_MIN) OR (fCpkSat > DL_CPK_SAT_MAX) THEN
    fCpkSat := MIN(MAX(fCpkSat, DL_CPK_SAT_MIN), DL_CPK_SAT_MAX); // 双侧钳位到 1.0~100.0 / clamp both sides into 1.0~100.0
END_IF

// 段 3｜规格限闸：上限不大于下限即非法，容差内视为相等同样非法 / segment 3, specification limit gate
IF (fUsl - fLsl) <= DL_FLOAT_EPS THEN
    eErr := 16#0001_031C;                      // 规格限非法故障码 / illegal specification limit fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 4｜样本数闸：先判界再索引 / segment 4, sample count gate before any indexing
IF (uCount < DL_CPK_MIN_N) OR (uCount > DL_CPK_MAX_N) THEN
    eErr := 16#0001_031B;                      // 样本数不足或越界故障码 / insufficient or out of range sample count fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 5｜第一遍：剔除非有限样本并求和 / segment 5, first pass removes non-finite samples and sums the rest
FOR uIdx := 0 TO uCount - 1 DO
    bNonFin := (afSample[uIdx] <> afSample[uIdx])
            OR (afSample[uIdx] > DL_CPK_INF_GUARD)
            OR (afSample[uIdx] < -DL_CPK_INF_GUARD); // 非有限判定 / non-finite check
    IF bNonFin THEN
        uKicked := uKicked + 1;                // 剔除计数，NaN 参与求和会污染全部结果 / count the removal, a NaN would poison the whole sum
    ELSE
        fSum := fSum + afSample[uIdx];         // LREAL 累加 / accumulate in LREAL
        uValidN := uValidN + 1;                // 有效样本计数 / count the valid sample
    END_IF
END_FOR
IF uValidN < DL_CPK_MIN_N THEN
    eErr := 16#0001_031B;                      // 剔除后仍不足两个有效样本 / still fewer than two valid samples after removal
    bError := TRUE;                            // 置故障标志 / raise the error flag
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 6｜均值与第二遍方差（两遍法比一次式 sumsq 数值稳定）/ segment 6, mean and second pass variance
fMeanL := fSum / UINT_TO_LREAL(uValidN);       // 分母由段 4 与段 5 保证不小于 2，显式升位转换 / the denominator is at least two thanks to the gates above, widened explicitly
fMean := LREAL_TO_REAL(fMeanL);                // 均值对外输出 / publish the mean
FOR uIdx := 0 TO uCount - 1 DO
    bNonFin := (afSample[uIdx] <> afSample[uIdx])
            OR (afSample[uIdx] > DL_CPK_INF_GUARD)
            OR (afSample[uIdx] < -DL_CPK_INF_GUARD); // 剔除样本不参与方差 / removed samples never enter the variance
    IF NOT bNonFin THEN
        fDev := afSample[uIdx] - fMean;        // 偏差 / deviation from the mean
        fSumSq := fSumSq + REAL_TO_LREAL(fDev) * REAL_TO_LREAL(fDev); // LREAL 乘方防溢出 / square in LREAL against overflow
    END_IF
END_FOR
fVar := fSumSq / UINT_TO_LREAL(uValidN - DL_CPK_N1); // n-1 分母，无偏估计，显式升位 / unbiased estimate with the n-1 denominator, widened explicitly
IF fVar < 0.0 THEN
    fVar := 0.0;                               // 数值噪声可能产生极小负值，钳到 0 再开方 / numerical noise may go slightly negative, clamp before the root
END_IF
fSigma := LREAL_TO_REAL(SQRT(fVar));           // 样本标准差 / sample standard deviation

// 段 7｜σ 近零饱和闸：常数样本是合法工况，只置信息码不置故障 / segment 7, sigma near zero saturation gate
IF fSigma <= DL_FLOAT_EPS THEN
    fCp := fCpkSat;                            // 潜在能力按饱和上限输出 / potential capability saturates
    fCpk := fCpkSat;                           // 实际能力按饱和上限输出 / actual capability saturates
    FC_DL_CpkIndex := fCpkSat;                 // 返回值同为饱和上限 / the return value follows the cap
    bSaturated := TRUE;                        // 标记饱和 / flag the saturation
    bValid := TRUE;                            // 饱和值是可用结果 / the saturated value is usable
    eErr := 16#0001_0243;                      // 饱和提示（信息级不置故障）/ saturation hint, info level never raises a fault
    RETURN;                                    // 饱和即出口 / saturation is the exit
END_IF

// 段 8｜能力指数计算：六倍 σ 分母已由段 7 保证非零 / segment 8, capability indices
fSpan := DL_CPK_SIGMA_6 * fSigma;              // 双侧六倍标准差 / six sigma over both sides
fCp := (fUsl - fLsl) / fSpan;                  // 潜在能力 / potential capability
fUpper := (fUsl - fMean) / (DL_CPK_SIGMA_K * fSigma); // 上侧能力，分母同样过闸 / upper capability, the denominator passed the same gate
fLower := (fMean - fLsl) / (DL_CPK_SIGMA_K * fSigma); // 下侧能力 / lower capability
fCpk := MIN(fUpper, fLower);                   // 实际能力取两侧较小值 / actual capability takes the smaller side
fCp := MIN(fCp, fCpkSat);                      // 上侧饱和封顶 / cap the upside at the saturation limit
fCpk := MIN(fCpk, fCpkSat);                    // 上侧饱和封顶 / cap the upside at the saturation limit

// 段 9｜出口：返回 Cpk 并对位镜像 / segment 9, exit with the Cpk mirror
FC_DL_CpkIndex := fCpk;                        // 返回值即 Cpk / the return value is Cpk
bValid := TRUE;                                // 结果可用 / the result is usable
END_FUNCTION
