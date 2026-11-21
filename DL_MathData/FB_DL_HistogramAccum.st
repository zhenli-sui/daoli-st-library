(*==============================================================================
 * 组件名称 (Component)  : FB_DL_HistogramAccum
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（LGF Measurement 统计族深化）
 * 所属子库 (Sublibrary) : DL_MathData / Statistics
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），零标准库依赖
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 数值直方图累积
 * 功能一句话 (Summary)  : 按单调递增边界表分箱加权计数，含下溢/上溢桶与非有限拦截。
 * 边界与安全 (Boundary) : ①NaN 拒收（x <> x 自反判）与无穷拒收（差值自反判）；
 *                         ②权重非正拒收（复用样本非法码，R90 口径）；
 *                         ③边界表未单调递增 → bEdgeErr 且本拍不累计；
 *                         ④右闭约定：值恰等于边界归上侧箱（右箱）；
 *                         ⑤数组下标全程钳位，禁越界写；
 *                         ⑥容量上限 64 箱，超容箱计入上溢。
 * 错误码    : 16#0001_03C5 样本拒收（NaN/无穷/权重非正）——故障级（持续态）
 *             16#0001_03C6 边界表非法（未单调递增或点数不足）——故障级（持续态）
 * 码位总账  : 16#0001_03C5 用 ｜ 16#0001_03C6 用
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_HistogramAccum
VAR_INPUT
    fValue  : LREAL;  // 待分箱样本值 / Sample value to bin
    fWeight : LREAL;  // 样本权重，默认 1.0 / Sample weight, default 1.0
    bReset  : BOOL;   // 复位：清全部计数 / Reset: clear all counts
END_VAR
VAR_IN_OUT
    aEdges  : ARRAY[*] OF LREAL; // 单调递增分箱边界表 / Monotonic increasing bin edges
END_VAR
VAR_OUTPUT
    aCounts    : ARRAY[*] OF ULINT; // 各箱计数（与边界表同界）/ Counts per bin (same bounds as edges)
    uUnderflow : ULINT; // 下溢桶：低于最小边界的计数 / Underflow bucket count
    uOverflow  : ULINT; // 上溢桶：高于最大边界的计数 / Overflow bucket count
    bEdgeErr   : BOOL;  // 边界表非法标志（未单调递增）/ Illegal edge table flag
    eErr       : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR CONSTANT
    cMaxBins : INT := 64; // 内部容量上限 64 箱 / Internal capacity limit 64 bins
END_VAR
VAR
    aCntBuf   : ARRAY[0..63] OF ULINT; // 内部计数缓冲（跨拍保持）/ Internal counts buffer (kept across scans)
    uUfBuf    : ULINT; // 内部下溢计数 / Internal underflow count
    uOfBuf    : ULINT; // 内部上溢计数 / Internal overflow count
    nEdges    : INT;   // 边界点数 / Edge point count
    i         : INT;   // 分箱搜索游标 / Bin search cursor
    iUb       : INT;   // 输出数组上界 / Output array upper bound
    bSorted   : BOOL;  // 边界单调性中间判据 / Edge monotonicity intermediate
    bAccumOk  : BOOL;  // 本拍允许累计判据 / Accumulation allowed this cycle
END_VAR

// ---------- 周期起点：错误码与标志先清（持续态随后重置） ----------
eErr     := 0;
bEdgeErr := FALSE;
bAccumOk := TRUE;

// ---------- 复位优先：清内部计数 ----------
IF bReset THEN
    FOR i := 0 TO cMaxBins - 1 DO
        aCntBuf[i] := 0;                     // 清内部箱 / Clear internal bins
    END_FOR
    uUfBuf := 0;                             // 清下溢 / Clear underflow
    uOfBuf := 0;                             // 清上溢 / Clear overflow
END_IF

// ---------- 边界表防御：点数与单调性（下标钳位访问） ----------
nEdges := UPPER_BOUND(aEdges, 1) + 1;        // 边界点数 / Edge point count
IF nEdges < 2 THEN
    bEdgeErr := TRUE;                        // 点数不足 / Insufficient points
    eErr     := 16#0001_03C6;                // 边界表非法 / Illegal edge table
ELSE
    bSorted := TRUE;
    FOR i := 0 TO nEdges - 2 DO
        IF NOT (aEdges[i] < aEdges[i + 1]) THEN
            bSorted := FALSE;                // 严格递增被破坏 / Strict increase violated
        END_IF
    END_FOR
    IF NOT bSorted THEN
        bEdgeErr := TRUE;                    // 置非法标志 / Set illegal flag
        eErr     := 16#0001_03C6;            // 边界表非法码 / Illegal table code
    END_IF
END_IF
IF bEdgeErr THEN
    bAccumOk := FALSE;                       // 表非法本拍不累计 / No accumulation on illegal table
END_IF

// ---------- 样本防御：非有限与权重（拒收不累计） ----------
IF bAccumOk THEN
    IF (fValue <> fValue) OR ((fValue - fValue) <> (fValue - fValue)) THEN
        bAccumOk := FALSE;                   // NaN 或无穷拒收 / NaN or Inf rejected
        eErr     := 16#0001_03C5;            // 样本非法码 / Illegal sample code
    ELSIF (fWeight <= 0.0) OR (fWeight <> fWeight) THEN
        bAccumOk := FALSE;                   // 权重非正拒收（复用 03C5）/ Non-positive weight rejected (03C5 reuse)
        eErr     := 16#0001_03C5;            // 样本非法码（R90 复用）/ Illegal sample code (R90 reuse)
    END_IF
END_IF

// ---------- 分箱累计：右闭约定，恰等边界归右箱 ----------
IF bAccumOk THEN
    IF fValue < aEdges[0] THEN
        uUfBuf := uUfBuf + ULINT#1; // 低于最小边界 → 下溢 / Below first edge: underflow
    ELSIF fValue > aEdges[nEdges - 1] THEN
        uOfBuf := uOfBuf + ULINT#1; // 高于最大边界 → 上溢 / Above last edge: overflow
    ELSE
        i := 0;
        WHILE (i < nEdges - 1) AND (fValue > aEdges[i]) DO
            i := i + 1;                      // 找首个上边界不小于值的箱 / Find first upper edge covering value
        END_WHILE
        IF i > cMaxBins - 1 THEN
            i := cMaxBins - 1;               // 下标钳位，超容归上溢侧 / Clamp index, over-capacity to overflow
            uOfBuf := uOfBuf + ULINT#1;
        ELSE
            aCntBuf[i] := aCntBuf[i] + LREAL_TO_ULINT(fWeight); // 加权计数 / Weighted count
        END_IF
    END_IF
END_IF

// ---------- 输出镜像：按输出数组实际界钳位拷贝 ----------
iUb := UPPER_BOUND(aCounts, 1);
IF iUb > cMaxBins - 1 THEN
    iUb := cMaxBins - 1;                     // 输出上界钳位 / Clamp output upper bound
END_IF
FOR i := 0 TO iUb DO
    aCounts[i] := aCntBuf[i];                // 内部缓冲镜像到输出 / Mirror buffer to outputs
END_FOR
uUnderflow := uUfBuf;                        // 下溢输出 / Underflow output
uOverflow  := uOfBuf;                        // 上溢输出 / Overflow output

END_FUNCTION_BLOCK
