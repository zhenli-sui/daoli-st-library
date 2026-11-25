(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StatsZeroCrossRate
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符，零厂商私有库
 * 功能描述 (Function)   : 过零率统计（振动 / 流量脉动的频域粗特征）。
 *                         以 fThreshold（通常为 0，也可取样本均值作「过均值率」）为基准，
 *                         逐点比较相对阈值的位置（+1 = 高于阈值，-1 = 低于阈值，0 = 恰等于），
 *                         统计**位置符号发生翻转**的次数（双向翻转合并为单一净额计数）。
 *                         恰等于阈值的样本**不改变当前符号**（跳过而非计为新符号），
 *                         避免直流偏置或量化平台把翻转数虚增。
 *                         过零率 = 翻转数 / (n - 1)，即相邻样本对的翻转比例 [0..1]；
 *                         频率近似 ≈ 过零率 × 采样率 / 2（本件不回传频率，仅回传比例，
 *                         时基由调用方掌握）。
 * 接口     (Interface)  : 输入 afSample 样本数组 [EU]、iCount 有效样本数 [个]（2..64）、
 *                         fThreshold 判定阈值 [EU]（通常 0）；
 *                         输出 iCrossings 翻转次数 [次]、fRate 翻转比例 [0..1]、
 *                         fRatePercent 翻转百分比 [%]、bValid 结果可信、
 *                         eErrCode（E_DL_StatsZcrErr）；
 *                         返回值 = bValid。
 * 边界     (Boundary)   : ① 属主边界：只统计翻转比例，不换算 Hz（缺时基）、不做频谱分析。
 *                         ② 样本数域闸 2..64：n=1 时「相邻对」不存在，翻转率无定义 → 故障级 eBadCount
 *                         （除零防护：分母 n-1 必须 >= 1）。
 *                         ③ 非有限双判：**fThreshold 与全部样本逐一枚举**（漏判阈值会让
 *                         整个符号判定静默退化）。
 *                         ④ 全样本恰等于阈值（符号始终未定）→ 翻转数 0、比例 0.0、
 *                         置信息级 eNoSignDefined（不是故障：数据确实无方向信息）。
 *                         ⑤ 双向翻转合并为单一累加器 iCrossings（不分别计数后相加，
 *                         避免两处写入不一致）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_StatsRmsCalc` 分工：幅值特征归那件、翻转特征归本件；
 *                         与 `FB_DL_StatsZeroCrossRate`（若后续入库的跨周期件）分工：
 *                         本件为单批窗口统计，无跨周期状态。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + INT + 2×LREAL +
 *                         本文件内定义 enum E_DL_StatsZcrErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 点数域闸（分母 n-1 除零排除）+ 阈值与样本非有限双判 + 单点写入 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 20）
 * 验收向量 (Acceptance) : ① afSample=[1,-1,1,-1], iCount=4, fThreshold=0 → 翻转 3 次,
 *                         fRate=3/3=1.0, fRatePercent=100.0, eOk, TRUE；
 *                         ② afSample=[1,2,3,4], iCount=4, fThreshold=0 → 翻转 0 次, fRate=0.0；
 *                         ③ afSample=[1,0,-1], iCount=3, fThreshold=0 → 符号 +1 → 跳过 → -1，
 *                         翻转 1 次（零值未计新符号）, fRate=0.5；
 *                         ④ afSample=[0,0,0], fThreshold=0 → 翻转 0 次, eNoSignDefined（信息级）；
 *                         ⑤ iCount=1 → 返回 FALSE, eBadCount（分母 n-1 会为 0）。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StatsZcrErr（过零率统计错误码，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StatsZcrErr :
(
    eOk            := 0,   // 信息级：统计完成 / Info: computed
    eNoSignDefined := 1,   // 信息级：样本全部等于阈值，无符号信息 / Info: all samples equal threshold
    eBadCount      := 2,   // 故障级：样本数越域（n-1 会为 0） / Fault: sample count out of domain
    eNonFinite     := 3    // 故障级：阈值或样本含非有限值 / Fault: non-finite threshold or sample
);
END_TYPE

FUNCTION FC_DL_StatsZeroCrossRate : BOOL
VAR_INPUT
    afSample   : ARRAY[1..64] OF LREAL;  // 样本数组 [EU] / Sample array
    iCount     : INT;                    // 有效样本数（2..64） [个] / Valid sample count, 2..64
    fThreshold : LREAL;                  // 判定阈值（通常 0） [EU] / Decision threshold, usually zero
END_VAR
VAR_OUTPUT
    iCrossings  : INT;    // 符号翻转次数 [次] / Number of sign flips
    fRate       : LREAL;  // 翻转比例（翻转数 / (n-1)） [0..1] / Flip ratio
    fRatePercent: LREAL;  // 翻转百分比 [%] / Flip percentage
    bValid      : BOOL;   // 结果可信标志 [-] / Result trustworthy flag
    eErrCode    : E_DL_StatsZcrErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _i        : INT;    // 样本遍历下标 [-] / Sample index
    _iPrev    : INT;    // 上一有效符号（+1 / -1 / 0 = 未定） [-] / Previous sign, zero means undetermined
    _iCur     : INT;    // 当前符号 [-] / Current sign
    _iCross   : INT;    // 翻转净额累加器（单点写入） [次] / Net flip accumulator, single point
    _bNonFin  : BOOL;   // 非有限标志 [-] / Non-finite flag
    _fRate    : LREAL;  // 比例（钳位前） [-] / Ratio before clamping
END_VAR
VAR CONSTANT
    DL_SZC_CNT_MIN : INT := 2;        // 样本数下限（相邻对至少一对） [个] / Count lower bound
    DL_SZC_CNT_MAX : INT := 64;       // 样本数上限（数组容量） [个] / Count upper bound
    DL_SZC_HUND    : LREAL := 100.0;  // 百分数换算因子 [-] / Percent scaling factor
    DL_SZC_ZERO    : LREAL := 0.0;    // 零基准（含非有限判零） [-] / Zero base including non-finite probe
    DL_SZC_ONE     : LREAL := 1.0;    // 比例上限 [-] / Ratio upper bound
    DL_SZC_SIGN_P  : INT := 1;        // 符号：高于阈值 / Sign above threshold
    DL_SZC_SIGN_N  : INT := -1;       // 符号：低于阈值 / Sign below threshold
    DL_SZC_SIGN_0  : INT := 0;        // 符号：未定（恰等于阈值） / Sign undetermined
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_StatsZeroCrossRate := FALSE;                 // 返回值预置无效 / Return preset invalid
iCrossings   := 0;                                 // 翻转计数哨兵 / Flip count sentinel
fRate        := DL_SZC_ZERO;                       // 比例哨兵 / Ratio sentinel
fRatePercent := DL_SZC_ZERO;                       // 百分比哨兵 / Percentage sentinel
bValid       := FALSE;                             // 可信标志预置否 / Trust flag preset false
eErrCode     := E_DL_StatsZcrErr.eBadCount;        // 预置最严码 / Preset strictest code

(* —— 段 1：样本数域闸（分母 n-1 必须 >= 1，除零结构性排除） —— *)
IF (iCount < DL_SZC_CNT_MIN) OR (iCount > DL_SZC_CNT_MAX) THEN
    RETURN;
END_IF

(* —— 段 2：非有限域闸（阈值 + 全部样本逐项枚举） —— *)
_bNonFin := (fThreshold <> fThreshold) OR ((fThreshold - fThreshold) <> DL_SZC_ZERO);
_i := 1;
WHILE _i <= iCount DO
    IF (afSample[_i] <> afSample[_i]) OR ((afSample[_i] - afSample[_i]) <> DL_SZC_ZERO) THEN
        _bNonFin := TRUE;                          // 样本非有限 / Sample non-finite
    END_IF
    _i := _i + 1;
END_WHILE
IF _bNonFin THEN
    eErrCode := E_DL_StatsZcrErr.eNonFinite;       // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 3：符号翻转扫描（恰等于阈值不改符号；双向翻转合并为单一累加器） —— *)
_iPrev  := DL_SZC_SIGN_0;                          // 符号未定 / Sign undetermined
_iCross := 0;
_i      := 1;
WHILE _i <= iCount DO
    IF afSample[_i] > fThreshold THEN
        _iCur := DL_SZC_SIGN_P;                    // 高于阈值 / Above threshold
    ELSIF afSample[_i] < fThreshold THEN
        _iCur := DL_SZC_SIGN_N;                    // 低于阈值 / Below threshold
    ELSE
        _iCur := DL_SZC_SIGN_0;                    // 恰等于阈值：本点不定义符号 / Undetermined at threshold
    END_IF

    IF _iCur <> DL_SZC_SIGN_0 THEN
        IF (_iPrev <> DL_SZC_SIGN_0) AND (_iCur <> _iPrev) THEN
            _iCross := _iCross + 1;                // 符号翻转一次（单点写入） / One flip
        END_IF
        _iPrev := _iCur;                           // 更新有效符号 / Update effective sign
    END_IF
    _i := _i + 1;
END_WHILE

(* —— 段 4：翻转比例（分母 n-1 >= 1，已由段 1 保证） —— *)
_fRate := INT_TO_LREAL(_iCross) / INT_TO_LREAL(iCount - 1);   // 翻转比例 / Flip ratio
_fRate := MIN(MAX(_fRate, DL_SZC_ZERO), DL_SZC_ONE);         // 显式约束 0..1 / Constrain 0..1
fRate        := _fRate;
fRatePercent := _fRate * DL_SZC_HUND;              // 百分比 / Percentage
iCrossings   := _iCross;

(* —— 段 5：无符号信息判定（全样本等于阈值） —— *)
IF _iPrev = DL_SZC_SIGN_0 THEN
    eErrCode := E_DL_StatsZcrErr.eNoSignDefined;   // 信息级：无方向信息 / Info: no directional information
ELSE
    eErrCode := E_DL_StatsZcrErr.eOk;              // 信息级成功 / Info success
END_IF

(* —— 段 6：结果复检（非有限 + 计数非负 + 不超相邻对数） —— *)
IF (fRate <> fRate) OR (fRatePercent <> fRatePercent) THEN
    iCrossings   := 0;
    fRate        := DL_SZC_ZERO;
    fRatePercent := DL_SZC_ZERO;
    eErrCode     := E_DL_StatsZcrErr.eNonFinite;
    RETURN;
END_IF
IF (iCrossings < 0) OR (iCrossings > (iCount - 1)) THEN
    iCrossings   := 0;                             // 计数越界：内部不一致 / Count out of range
    fRate        := DL_SZC_ZERO;
    fRatePercent := DL_SZC_ZERO;
    eErrCode     := E_DL_StatsZcrErr.eBadCount;
    RETURN;
END_IF

(* —— 段 7：成功出口 —— *)
bValid := TRUE;
FC_DL_StatsZeroCrossRate := TRUE;                  // 统计可信 / Statistics trustworthy

END_FUNCTION
