(*==============================================================================
 * 组件名称 (Component)  : FC_DL_SearchMinMax
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 函数（FUNCTION）· 纯函数 · 数组极值与索引同出
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅用 ABS / MIN / MAX 等标准算子
 * 功能描述 (Function)   : 在注入数组的前 nCount 个元素中一次单遍扫描，同时求
 *                         最小值、最大值及其索引（可选首个命中或末次命中），
 *                         并统计被跳过的非有限值（NaN 与超大值）个数。用于
 *                         批次数据极值分析、多路温度最高点定位、传感器阵列
 *                         故障点筛查、配方曲线包络提取。
 * 与既有件边界 (Boundary): FB_DL_SignalStatistics 是流式窗口统计（有状态、
 *                         含均值方差）；FB_DL_PeakDetector 是时域峰值跟踪
 *                         （带衰减与事件）；本件是静态数组一次性扫描（纯函数、
 *                         无状态），只出极值与索引，不做任何时间维度处理。
 * 设计要点 (Key notes)  : ① 单遍扫描：一趟循环同时出极值与索引，不做两次
 *                           遍历（大数组下 O(2N) 与 O(N) 的差别会被任务周期
 *                           放大）；
 *                         ② 首命中用严格比较、末命中用非严格比较，不以
 *                           MODE 参数区分（单一布尔策略开关，语义单一，
 *                           不构成多职责巨无霸块）；
 *                         ③ 非有限值过滤不依赖厂商 ISNAN 函数：用「NaN 不等于
 *                           自身」这一 IEEE 754 可移植判据，配合绝对值超
 *                           1E300 兜底无穷大，两条件任一成立即跳过；
 *                         ④ 全量非有限时返回 FALSE 并置故障级码，绝不用 0 冒充
 *                           有效极值（否则上层会把「无数据」当成「最小值 0」）；
 *                         ⑤ 数组上界必须用钳位后的局部变量，禁止直接用入参
 *                           nCount 当 FOR 上界（越界访问是 PLC 上最典型的
 *                           内存踩踏来源）。
 * 开源溯源 (Origin)     : lgf-math。参考 LGF（Libre Graphical Framework）公开
 *                         函数库「Math」分类下 SearchMinMax 系列的四个类型
 *                         变体（LReal / DInt / UDInt / 通用）所体现的功能
 *                         分类与参数域（数据体 + 个数 + 极值 + 索引 的参数
 *                         形态），只借分类、参数域与命名习惯；本件只做 LREAL
 *                         主线，其余类型变体按库内「数据类型重载」规则另立块，
 *                         不塞进 MODE 参数。算法与实现 100% 自有 clean-room，
 *                         不构成衍生作品。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；无标准库功能块依赖
 * 故障码表 (Error codes):
 *   16#0001_0119【信息级】计数越界（小于 1 早退；大于上限则钳位后继续）
 *   16#0001_011A【信息级】检测到非有限值并已跳过，个数见 nSkipCnt
 *   16#0001_0217【故障级】全量非有限，无有效极值，返回 FALSE
 * 验收向量 (Acceptance) :
 *   V1 数据 3.5 / -2.0 / 9.0 / -2.0，个数 4，首命中 → 最小 -2.0 于索引 1，
 *      最大 9.0 于索引 2
 *   V2 同上改末次命中 → 最小 -2.0 于索引 3
 *   V3 数据 1.0 / NaN / 1.0 → 跳过 1 个、有效 2 个、全等标志 TRUE、码含 011A
 *   V4 个数 0 → 返回 FALSE、码 0119、两个索引均为 -1
 *   V5 个数 300（超 256）→ 只扫前 256 个、码 0119、返回 TRUE
 * 红线自检 (Redline)    : R1 零全局变量表与外部变量引用 ｜ R2 零物理地址直写
 *                         R3 纯 IEC 61131-3 ｜ R4 索引先钳位后访问、浮点比较
 *                         用容差、NaN 判据有注释豁免说明 ｜ R5 全变量中英双语
 *                         同行注释 ｜ R6 N/A（纯函数无状态机）｜ R7 N/A（无实例）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 10 · Level 1 数学族回补）
 *============================================================================*)

FUNCTION FC_DL_SearchMinMax : BOOL
VAR_INPUT
    nCount   : DINT := 0;        // 参与扫描的元素个数，有效域 1 到 DL_SMM_MAX [个] / Number of elements to scan, valid 1 to DL_SMM_MAX
    bLastHit : BOOL := FALSE;    // TRUE = 索引取末次命中，FALSE = 取首个命中（默认）[-] / TRUE selects the last hit, FALSE the first hit
END_VAR
VAR_IN_OUT
    afData   : ARRAY[0..255] OF LREAL;  // 扫描数据体，调用方持有并注入，上界 255 与 DL_SMM_MAX 保持一致 [工程单位] / Scanned data array, bound 255 kept in sync with DL_SMM_MAX
END_VAR
VAR_OUTPUT
    fMin      : LREAL;       // 最小值，无有效数据时为 0.0 [工程单位随应用] / Minimum value, 0.0 when no valid element
    fMax      : LREAL;       // 最大值，无有效数据时为 0.0 [工程单位随应用] / Maximum value, 0.0 when no valid element
    nMinIdx   : DINT := -1;  // 最小值索引，未找到为 -1 [元素下标] / Index of the minimum, -1 when not found
    nMaxIdx   : DINT := -1;  // 最大值索引，未找到为 -1 [元素下标] / Index of the maximum, -1 when not found
    nValidCnt : DINT;        // 实际参与比较的有效元素数 [个] / Number of elements actually compared
    nSkipCnt  : DINT;        // 因非有限值被跳过的元素数 [个] / Number of skipped non-finite elements
    bFlat     : BOOL;        // 全等标志，fMin 与 fMax 在容差内相等 [-] / TRUE when the minimum equals the maximum within tolerance
    uErrorId  : UDINT;       // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    i            : DINT;     // 循环索引，域 0 到钳位后个数减 1 [元素下标] / Loop index, 0 to clamped count minus one
    nCountClamp  : DINT;     // 钳位后的扫描个数，FOR 上界只许用本变量 [个] / Clamped scan count, the only legal FOR upper bound
    fValue       : LREAL;    // 当前元素值副本，避免在比较中重复取数组 [工程单位] / Current element value copy
    bFinite      : BOOL;     // 当前元素是否有限（非 NaN 且非超大幅值）[-] / TRUE when the current element is finite
END_VAR
VAR CONSTANT
    DL_SMM_MAX   : DINT  := 256;      // 数组上限，与形参上界 255 保持一致 [元素] / Array upper bound, kept in sync with the formal bound
    DL_SMM_MIN   : DINT  := 1;        // 最小扫描个数，0 与负数一律视为非法 [个] / Minimum legal scan count
    DL_FLOAT_EPS : LREAL := 1.0E-9;   // 浮点比较容差，用于全等判定 [-] / Float comparison tolerance for the flat test
    DL_BIG       : LREAL := 1.0E300;  // 超大值兜底门限，用于识别无穷大与溢出 [-] / Magnitude guard used to catch infinities
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出与返回值预置：早退路径必须给出确定的 0 与 -1
 *      Pre-set outputs: deterministic zeros and minus one on every early exit
 *-----------------------------------------------------------------------------*)
FC_DL_SearchMinMax := FALSE;
fMin      := 0.0;
fMax      := 0.0;
nMinIdx   := -1;
nMaxIdx   := -1;
nValidCnt := 0;
nSkipCnt  := 0;
bFlat     := FALSE;
uErrorId  := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 2｜计数域校验（边界 B1）：小于 1 直接早退，大于上限钳位后继续
 *      Count domain check: below one exits early, above the bound is clamped
 *      钳位而不报错退出的理由：现场宁可算出前 256 个的极值，也不要拿不到数
 *-----------------------------------------------------------------------------*)
IF nCount < DL_SMM_MIN THEN
    uErrorId := 16#0001_0119;   // 计数非法（小于 1），无有效极值
    RETURN;
END_IF

nCountClamp := nCount;
IF nCount > DL_SMM_MAX THEN
    nCountClamp := DL_SMM_MAX;  // 只扫前 DL_SMM_MAX 个，绝不越界
    uErrorId    := 16#0001_0119;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜单遍扫描：过滤非有限值，同时维护极值与索引
 *      Single pass: filter non-finite values while tracking extremes and indices
 *      NaN 判据：fValue 不等于 fValue 在 IEEE 754 下恒为 TRUE（NaN 不等于自身），
 *      这是唯一可移植的 NaN 检测手段，不依赖任何厂商 ISNAN 函数；
 *      绝对值超过 1E300 视为无穷大或数值溢出，一并跳过。
 *-----------------------------------------------------------------------------*)
FOR i := 0 TO (nCountClamp - 1) DO
    fValue := afData[i];

    IF (fValue <> fValue) OR (ABS(fValue) > DL_BIG) THEN
        bFinite := FALSE;
    ELSE
        bFinite := TRUE;
    END_IF

    IF NOT bFinite THEN
        nSkipCnt := nSkipCnt + 1;               // 非有限值：跳过，不参与比较
    ELSE
        IF nValidCnt = 0 THEN
            fMin     := fValue;                 // 首个有效元素直接作为初值
            fMax     := fValue;
            nMinIdx  := i;
            nMaxIdx  := i;
        ELSE
            IF bLastHit THEN
                IF fValue <= fMin THEN          // 末命中：等值也替换索引
                    fMin    := fValue;
                    nMinIdx := i;
                END_IF
                IF fValue >= fMax THEN
                    fMax    := fValue;
                    nMaxIdx := i;
                END_IF
            ELSE
                IF fValue < fMin THEN           // 首命中：等值不替换索引
                    fMin    := fValue;
                    nMinIdx := i;
                END_IF
                IF fValue > fMax THEN
                    fMax    := fValue;
                    nMaxIdx := i;
                END_IF
            END_IF
        END_IF
        nValidCnt := nValidCnt + 1;
    END_IF
END_FOR

(*------------------------------------------------------------------------------
 * 段 4｜全量非有限兜底（边界 B2）：无有效元素时绝不返回 0 冒充极值
 *      All non-finite fallback: never report zero as a valid extreme
 *-----------------------------------------------------------------------------*)
IF nValidCnt < 1 THEN
    fMin     := 0.0;
    fMax     := 0.0;
    nMinIdx  := -1;
    nMaxIdx  := -1;
    uErrorId := 16#0001_0217;   // 故障级：无有效极值
    FC_DL_SearchMinMax := FALSE;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜全等判定（浮点禁用判等）：用容差比较代替相等比较
 *      Flat detection with a tolerance compare instead of an equality compare
 *-----------------------------------------------------------------------------*)
IF ABS(fMax - fMin) < DL_FLOAT_EPS THEN
    bFlat := TRUE;
ELSE
    bFlat := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜事件码收口：数据质量问题优先于计数钳位事件
 *      Error code close-out: data quality outranks the count clamp event
 *-----------------------------------------------------------------------------*)
IF nSkipCnt > 0 THEN
    uErrorId := 16#0001_011A;   // 信息级：存在被跳过的非有限值
END_IF

FC_DL_SearchMinMax := TRUE;
END_FUNCTION
