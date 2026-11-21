(*==============================================================================
 * 组件名称 (Component)  : FC_DL_QuickSortLReal
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS / 显式类型转换），无厂商方言
 * 功能描述 (Function)   : 定长 LREAL 数组原地快速排序（最大 64 元素，升/降序）。
 *                         **显式栈迭代实现，无任何递归**——ST 递归在部分平台
 *                         （嵌入式运行时与汇川 InoProShop）栈深受限或直接不支持，
 *                         64 元素的最坏分区递归深度可达 64，实验室跑得通、
 *                         现场栈溢出，属不可交付实现。用于分位数、去极值均值、
 *                         报表排序、中值参考计算。小区间（< 8 元素）自动改走
 *                         插入排序：小数组上更快且无分区退化风险。
 *                         枢轴用三数取中，防已排序/全等值最坏情况退化。
 *
 * 【禁用递归声明 / No-recursion statement（边界 B1）】
 *   全文无对本函数的任何自调用。分治范式由"显式栈 + WHILE 主循环"承载，
 *   本实现可作为库内其他分治算法（最近点对、凸包等）的栈模板。
 * 【栈深上界警示 / Stack-depth warning（边界 B2）】
 *   **先压大区间、后压小区间**是栈深 O(log n) 的唯一保证：小区间先被
 *   处理，大区间在栈中等待，任意时刻栈内区间大小逐层减半。
 *   顺序写反后，全等值数组会把 16 深栈打爆。
 * 【失败语义披露 / Failure semantics（边界 B5）】
 *   NaN 预扫描拒绝时数组保持原样；循环保护触发（16#0001_0004）时数组
 *   可能部分有序：**返回 FALSE 时数组内容未定义，调用方应丢弃本轮结果**，
 *   本函数不伪装成功。快速排序不稳定，相同值的相对次序不保证（边界 B7），
 *   需要稳定排序时改用插入排序变体（后续扩产）。
 * 【对 ROUND_PLAN §7.13 的一处勘误 / Erratum】
 *   规格原文称三数取中"只取值装入枢轴、不必交换到固定位置，Lomuto 分区
 *   用值即可"。经实算证伪：尾元素为三数中最小者时，枢轴值大于尾元素，
 *   Lomuto 终换会把尾元素钉在分区边界位并被递归排除，该元素永久错位。
 *   本实现改为：先把中值交换到区间末位，再做标准 Lomuto，终换落位的
 *   必然是枢轴本身，边界位语义成立。
 * 【验收向量 / Acceptance vectors】
 *   V1  {3,1,2}, n=3, 升序 → {1,2,3}、返回 TRUE
 *   V2  {5,4,3,2,1}, n=5, 降序 → {5,4,3,2,1}（不变）、返回 TRUE
 *   V3  64 个 7.0（全等值最坏情况）→ 有限步内终止、返回 TRUE、全为 7.0
 *       （bUsedFallback 允许为 TRUE，降级不是缺陷）
 *   V4  n=1 / n=0 → 返回 TRUE、数组不变、比较与交换计数均为 0
 *   V5  {1.0, NaN, 3.0} → 返回 FALSE、16#0001_0006、数组仍为原顺序
 *   V6  已升序 64 个随机值 → 返回 TRUE、有序、比较计数在 O(n log n) 量级
 *   V7  32 个随机值排序后与冒泡排序参考实现逐元素比对，完全一致
 * 开源溯源 (Origin)     : 原创实现（参考西门子 LGF 数据处理组"按类型分族
 *                         提供排序"的组织方式与 OSCAT Basic 原地排序的行为
 *                         定义（EPL-2.0）；LGF 用希尔排序、OSCAT 用地址指针
 *                         入参，本函数按原子化原则选函数形态、显式栈替代
 *                         递归、数组引脚传参，clean-room 编写，未复制任何源码）。
 * 依赖     (Depends)    : 无 DL_ 内部依赖
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3，无递归、无指针、无数组越界
 *                         R4 ✓ 数量钳位 + NaN 预扫描 + 下标双检 + 双层防死锁计数
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无跨周期状态机）
 *                         R7 N/A（无定时器/边沿实例）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 收口批次 · R3）
 *   2026-11-15  v1.0.1  R11 修复：补声明 nPivotIdx : INT（段 5.3 三数取中
 *                       的枢轴下标 4 处赋值 + 段 5.3a 2 处下标引用，原 VAR
 *                       区漏声明，三平台编译阻断）。逻辑本体零改动。
 *                       R11 fix: declare nPivotIdx : INT, no logic change
 *============================================================================*)
FUNCTION FC_DL_QuickSortLReal : BOOL
VAR_IN_OUT
    afData        : ARRAY[0..63] OF LREAL;  // 待排序数组，原地修改，失败时内容未定义 / Array sorted in place, undefined content on failure
END_VAR
VAR_INPUT
    nCount        : INT;                    // 有效元素数，0..64，越界钳位或拒绝 / Valid element count, 0..64
    bAscending    : BOOL := TRUE;           // TRUE = 升序，FALSE = 降序 / TRUE: ascending, FALSE: descending
END_VAR
VAR_OUTPUT
    uCompareCount : UDINT;                  // 比较次数（性能诊断，饱和不回绕） / Comparison count, saturating
    uSwapCount    : UDINT;                  // 交换次数（饱和不回绕） / Swap count, saturating
    bUsedFallback : BOOL;                   // TRUE = 显式栈溢出，子区间转插入排序兜底 / TRUE: stack overflow, insertion-sort fallback used
    uErrorId      : UDINT;                  // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    anLoStack     : ARRAY[0..15] OF INT;    // 显式栈：待排区间下界 / Explicit stack: interval low bounds
    anHiStack     : ARRAY[0..15] OF INT;    // 显式栈：待排区间上界 / Explicit stack: interval high bounds
    nSp           : INT;                    // 栈指针，0 = 空 / Stack pointer, 0 = empty
    nLo           : INT;                    // 当前区间下界 / Current interval low bound
    nHi           : INT;                    // 当前区间上界 / Current interval high bound
    nI            : INT;                    // 分区扫描索引 / Partition scan index
    nJ            : INT;                    // 分区边界（枢轴落位下标） / Partition boundary, pivot landing index
    nMid          : INT;                    // 三数取中的中点下标 / Median-of-three middle index
    nPivotIdx     : INT;                    // 三数取中后枢轴所在下标（先归位到区间末位） / Index of the median-of-three pivot, relocated to the interval tail
    fPivot        : LREAL;                  // 枢轴值 / Pivot value
    fKeyLo        : LREAL;                  // 三数取中：区间首元素 / Median-of-three: first element
    fKeyMid       : LREAL;                  // 三数取中：区间中元素 / Median-of-three: middle element
    fKeyHi        : LREAL;                  // 三数取中：区间尾元素 / Median-of-three: last element
    fTmp          : LREAL;                  // 交换临时量 [EU] / Swap temp [EU]
    nSizeL        : INT;                    // 左子区间长度 / Left subinterval size
    nSizeR        : INT;                    // 右子区间长度 / Right subinterval size
    nPLo          : INT;                    // 较大子区间下界（先压栈） / Larger subinterval low, pushed first
    nPHi          : INT;                    // 较大子区间上界（先压栈） / Larger subinterval high, pushed first
    nQLo          : INT;                    // 较小子区间下界（后压栈） / Smaller subinterval low, pushed second
    nQHi          : INT;                    // 较小子区间上界（后压栈） / Smaller subinterval high, pushed second
    bJob1         : BOOL;                   // 插入排序任务 1 挂起 / Insertion job 1 pending
    bJob2         : BOOL;                   // 插入排序任务 2 挂起（双溢出兜底） / Insertion job 2 pending, dual-overflow fallback
    nJob1Lo       : INT;                    // 任务 1 区间下界 / Job 1 interval low bound
    nJob1Hi       : INT;                    // 任务 1 区间上界 / Job 1 interval high bound
    nJob2Lo       : INT;                    // 任务 2 区间下界 / Job 2 interval low bound
    nJob2Hi       : INT;                    // 任务 2 区间上界 / Job 2 interval high bound
    nKIns         : INT;                    // 插入排序外层索引 / Insertion sort outer index
    nJIns         : INT;                    // 插入排序内层回退索引 / Insertion sort inner shift index
    bShiftEnd     : BOOL;                   // 内层回退结束标志 / Inner shift finished flag
    bTake         : BOOL;                   // 当前元素是否归入左侧 / Current element belongs to the left side
    nGuard        : INT;                    // 外层主循环防死锁计数器 / Outer loop guard counter
    nGuard2       : INT;                    // 内层循环防死锁计数器（每段循环前清零） / Inner loop guard, reset before each loop
    nIdx          : INT;                    // NaN 预扫描索引 / NaN pre-scan index
END_VAR
VAR CONSTANT
    DL_QS_CAP       : INT   := 64;          // 数组容量，必须与数组维度严格一致 / Array capacity, must match the array
    DL_QS_STACK_MAX : INT   := 16;          // 显式栈深度（2×log2(64)=12，留余量）/ Explicit stack depth, log2 bound with margin
    DL_QS_INSERT_TH : INT   := 8;           // 小于该长度改用插入排序 / Insertion-sort threshold
    DL_QS_GUARD     : INT   := 4096;        // 外层主循环防死锁上限 / Outer loop guard limit
    DL_QS_GUARD2    : INT   := 1024;        // 内层循环防死锁上限 / Inner loop guard limit
    DL_QS_INF_LIM   : LREAL := 1.0E300;     // 非有限值判据阈值（超此视为 Inf） / Infinity threshold for non-finite detection
    DL_QS_CNT_MAX   : UDINT := 16#FFFF_FFFE;// 计数饱和值，不回绕 / Counter saturation, no wrap-around
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置：返回值先落 TRUE，计数清零，故障码清零
 *      Safe preset: return falls back to TRUE, counters and error cleared
 *-----------------------------------------------------------------------------*)
FC_DL_QuickSortLReal := TRUE;
uCompareCount := 16#0000_0000;
uSwapCount    := 16#0000_0000;
bUsedFallback := FALSE;
uErrorId      := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 2｜数量防御（边界：负值拒绝、超限钳位、0/1 直接有序）
 *      Count defence: negative rejected, over-capacity clamped, 0/1 already sorted
 *-----------------------------------------------------------------------------*)
IF nCount < 0 THEN
    uErrorId            := 16#0001_0001;    // 数量非法 / Invalid count
    FC_DL_QuickSortLReal := FALSE;
    RETURN;
ELSIF nCount > DL_QS_CAP THEN
    nCount   := DL_QS_CAP;                  // 钳位后继续排序 / Clamped, keep sorting
    uErrorId := 16#0001_0001;
END_IF

IF nCount <= 1 THEN
    RETURN;                                 // 0 或 1 个元素天然有序 / Trivially sorted
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜NaN/Inf 预扫描（边界 B4）：必须先做，否则分区行为未定义。
 *      NaN/Inf pre-scan: mandatory, otherwise partitioning is undefined
 *      "值不等于自身"是 NaN 的唯一 IEC 可移植判据；发现即拒绝，
 *      数组保持原样，绝不把半个乱序数组留给调用方
 *-----------------------------------------------------------------------------*)
FOR nIdx := 0 TO (nCount - 1) DO
    IF (nIdx >= 0) AND (nIdx < DL_QS_CAP) THEN
        IF (afData[nIdx] <> afData[nIdx]) OR (ABS(afData[nIdx]) > DL_QS_INF_LIM) THEN
            uErrorId            := 16#0001_0006;    // 数组含 NaN/Inf / NaN or Inf detected
            FC_DL_QuickSortLReal := FALSE;
            RETURN;
        END_IF
    END_IF
END_FOR;

(*------------------------------------------------------------------------------
 * 段 4｜显式栈初始化：压入首区间
 *      Explicit stack init: push the first interval
 *-----------------------------------------------------------------------------*)
nSp          := 1;
anLoStack[0] := 0;
anHiStack[0] := nCount - 1;
nGuard       := 0;

(*------------------------------------------------------------------------------
 * 段 5｜主循环：弹栈 → 小区间走插入排序 / 大区间走分区入栈
 *      Main loop: pop, small intervals to insertion sort, large to partitioning
 *-----------------------------------------------------------------------------*)
WHILE (nSp > 0) AND (nGuard < DL_QS_GUARD) DO

    nGuard := nGuard + 1;

    (* 段 5.1｜弹栈 / Pop the current interval *)
    nSp := nSp - 1;
    nLo := anLoStack[nSp];
    nHi := anHiStack[nSp];
    bJob1 := FALSE;
    bJob2 := FALSE;

    IF (nHi - nLo + 1) < DL_QS_INSERT_TH THEN
        (* 段 5.2｜小区间：登记插入排序任务（小数组更快且无退化风险） *)
        (* Small interval: register an insertion job *)
        bJob1   := TRUE;
        nJob1Lo := nLo;
        nJob1Hi := nHi;
    ELSE
        (* 段 5.3｜三数取中选枢轴：防已排序/全等值最坏退化（边界 B3） *)
        (* Median-of-three pivot: guards sorted and all-equal worst cases *)
        nMid    := (nLo + nHi) / 2;         // 整除取中点 / Integer division for the middle
        fKeyLo  := afData[nLo];
        fKeyMid := afData[nMid];
        fKeyHi  := afData[nHi];
        nPivotIdx := nHi;                   // 默认取尾元素 / Default to the last element
        IF ((fKeyLo <= fKeyMid) AND (fKeyMid <= fKeyHi))
        OR ((fKeyHi <= fKeyMid) AND (fKeyMid <= fKeyLo)) THEN
            nPivotIdx := nMid;              // 中元素为中值 / Middle element is the median
        ELSIF ((fKeyMid <= fKeyLo) AND (fKeyLo <= fKeyHi))
        OR ((fKeyHi <= fKeyLo) AND (fKeyLo <= fKeyMid)) THEN
            nPivotIdx := nLo;               // 首元素为中值 / First element is the median
        END_IF

        (* 段 5.3a｜枢轴归位：把中值交换到区间末位（勘误，见头注释）。
         *      Pivot relocation: move the median to the interval tail.
         *      只取值不换位时，尾元素小于枢轴会让终换钉错边界位且被递归排除 *)
        fTmp              := afData[nPivotIdx];
        afData[nPivotIdx] := afData[nHi];
        afData[nHi]       := fTmp;
        fPivot            := afData[nHi];   // 枢轴已在末位，直接取值 / Pivot now sits at the tail

        (* 段 5.4｜Lomuto 分区：小于（升序）或大于（降序）枢轴的归左 *)
        (* Lomuto partitioning: elements below (asc) or above (desc) pivot go left *)
        nJ     := nLo;
        nGuard2 := 0;
        FOR nI := nLo TO (nHi - 1) DO
            nGuard2 := nGuard2 + 1;
            IF (nGuard2 > DL_QS_GUARD2) OR (nI < 0) OR (nI >= DL_QS_CAP) THEN
                uErrorId            := 16#0001_0004;    // 循环保护触发，排序未完成 / Guard tripped, sort incomplete
                FC_DL_QuickSortLReal := FALSE;
                RETURN;
            END_IF
            (* 单行布尔合成：升序取小于、降序取大于，禁止排完再反转（边界 B6） *)
            (* One-line boolean: below pivot when ascending, above when descending *)
            bTake := (bAscending AND (afData[nI] < fPivot))
                  OR ((NOT bAscending) AND (afData[nI] > fPivot));
            IF uCompareCount < DL_QS_CNT_MAX THEN
                uCompareCount := uCompareCount + 1;
            END_IF
            IF bTake THEN
                fTmp         := afData[nI];
                afData[nI]   := afData[nJ];
                afData[nJ]   := fTmp;
                nJ           := nJ + 1;
                IF uSwapCount < DL_QS_CNT_MAX THEN
                    uSwapCount := uSwapCount + 1;
                END_IF
            END_IF
        END_FOR;

        (* 段 5.5｜枢轴落位：交换到分区边界 / Pivot lands at the partition boundary *)
        fTmp       := afData[nJ];
        afData[nJ] := afData[nHi];
        afData[nHi] := fTmp;
        IF uSwapCount < DL_QS_CNT_MAX THEN
            uSwapCount := uSwapCount + 1;
        END_IF

        (* 段 5.6｜子区间装配：大者记为 P，小者记为 Q（边界 B2 顺序硬约束） *)
        (* Assemble subintervals: larger as P, smaller as Q, order is mandatory *)
        nSizeL := nJ - nLo;
        nSizeR := nHi - nJ;
        IF nSizeL >= nSizeR THEN
            nPLo := nLo;   nPHi := nJ - 1;
            nQLo := nJ + 1; nQHi := nHi;
        ELSE
            nPLo := nJ + 1; nPHi := nHi;
            nQLo := nLo;   nQHi := nJ - 1;
        END_IF

        (* 段 5.7｜先压大区间 P；栈满则该区间转插入排序兜底（边界 B3 降级） *)
        (* Push the larger interval P first; on stack overflow fall back to insertion *)
        IF nPHi > nPLo THEN
            IF nSp < DL_QS_STACK_MAX THEN
                anLoStack[nSp] := nPLo;
                anHiStack[nSp] := nPHi;
                nSp := nSp + 1;
            ELSE
                bUsedFallback := TRUE;
                uErrorId      := 16#0001_0007;  // 显式栈溢出已降级 / Stack overflow, fallback used
                bJob1   := TRUE;
                nJob1Lo := nPLo;
                nJob1Hi := nPHi;
            END_IF
        END_IF

        (* 段 5.8｜后压小区间 Q；栈满同样降级（双溢出用任务 2 承接，不丢数据） *)
        (* Push the smaller interval Q second; dual overflow is caught by job 2 *)
        IF nQHi > nQLo THEN
            IF nSp < DL_QS_STACK_MAX THEN
                anLoStack[nSp] := nQLo;
                anHiStack[nSp] := nQHi;
                nSp := nSp + 1;
            ELSE
                bUsedFallback := TRUE;
                uErrorId      := 16#0001_0007;  // 显式栈溢出已降级 / Stack overflow, fallback used
                bJob2   := TRUE;
                nJob2Lo := nQLo;
                nJob2Hi := nQHi;
            END_IF
        END_IF

    END_IF

    (* 段 5.9｜插入排序任务 1 执行（小区间或 P 降级区间） *)
    (* Insertion job 1: small interval or the degraded P range *)
    IF bJob1 THEN
        nGuard2 := 0;
        nKIns := nJob1Lo + 1;
        WHILE nKIns <= nJob1Hi DO
            nGuard2 := nGuard2 + 1;
            IF nGuard2 > DL_QS_GUARD2 THEN
                uErrorId            := 16#0001_0004;
                FC_DL_QuickSortLReal := FALSE;
                RETURN;
            END_IF
            fTmp      := afData[nKIns];
            nJIns     := nKIns - 1;
            bShiftEnd := FALSE;
            WHILE (nJIns >= nJob1Lo) AND (NOT bShiftEnd) DO
                nGuard2 := nGuard2 + 1;
                IF nGuard2 > DL_QS_GUARD2 THEN
                    uErrorId            := 16#0001_0004;
                    FC_DL_QuickSortLReal := FALSE;
                    RETURN;
                END_IF
                IF uCompareCount < DL_QS_CNT_MAX THEN
                    uCompareCount := uCompareCount + 1;
                END_IF
                (* 单行布尔合成：升序遇不大于者停、降序遇不小于者停 *)
                (* One-line boolean: stop when the slot is found for either direction *)
                bShiftEnd := (bAscending AND (afData[nJIns] <= fTmp))
                          OR ((NOT bAscending) AND (afData[nJIns] >= fTmp));
                IF NOT bShiftEnd THEN
                    afData[nJIns + 1] := afData[nJIns];
                    nJIns := nJIns - 1;
                END_IF
            END_WHILE
            afData[nJIns + 1] := fTmp;
            nKIns := nKIns + 1;
        END_WHILE
    END_IF

    (* 段 5.10｜插入排序任务 2 执行（仅双溢出时挂起，正常流程不进入） *)
    (* Insertion job 2: pending only after a dual overflow, normally idle *)
    IF bJob2 THEN
        nGuard2 := 0;
        nKIns := nJob2Lo + 1;
        WHILE nKIns <= nJob2Hi DO
            nGuard2 := nGuard2 + 1;
            IF nGuard2 > DL_QS_GUARD2 THEN
                uErrorId            := 16#0001_0004;
                FC_DL_QuickSortLReal := FALSE;
                RETURN;
            END_IF
            fTmp      := afData[nKIns];
            nJIns     := nKIns - 1;
            bShiftEnd := FALSE;
            WHILE (nJIns >= nJob2Lo) AND (NOT bShiftEnd) DO
                nGuard2 := nGuard2 + 1;
                IF nGuard2 > DL_QS_GUARD2 THEN
                    uErrorId            := 16#0001_0004;
                    FC_DL_QuickSortLReal := FALSE;
                    RETURN;
                END_IF
                IF uCompareCount < DL_QS_CNT_MAX THEN
                    uCompareCount := uCompareCount + 1;
                END_IF
                bShiftEnd := (bAscending AND (afData[nJIns] <= fTmp))
                          OR ((NOT bAscending) AND (afData[nJIns] >= fTmp));
                IF NOT bShiftEnd THEN
                    afData[nJIns + 1] := afData[nJIns];
                    nJIns := nJIns - 1;
                END_IF
            END_WHILE
            afData[nJIns + 1] := fTmp;
            nKIns := nKIns + 1;
        END_WHILE
    END_IF

END_WHILE

(*------------------------------------------------------------------------------
 * 段 6｜外层守卫检查：超限说明分区异常，排序未完成，不伪装成功（边界 B5）
 *      Outer guard check: a trip means partitioning went wrong, never fake success
 *-----------------------------------------------------------------------------*)
IF nGuard >= DL_QS_GUARD THEN
    uErrorId            := 16#0001_0004;
    FC_DL_QuickSortLReal := FALSE;
END_IF
END_FUNCTION
