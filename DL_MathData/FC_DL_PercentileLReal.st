(*==============================================================================
 * 组件名称 (Component)  : FC_DL_PercentileLReal
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类     (Category)   : 统计函数（Function · Statistics / Pure function）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（LREAL 比较 / 显式类型转换），零厂商方言
 * 功能描述 (Function)   : 对定长样本数组求任意分位值（P0 至 P100），采用业界主流的
 *                         「排序 + 线性插值」口径（R-7 定义，与主流统计库默认一致），
 *                         用于节拍抖动 P95、称重偏差 P99、温度分布 P50 等现场统计判据。
 *                         函数内部完成**拷贝排序**：调用方数组保持原样，与库内就地
 *                         排序件的语义相反，此处刻意如此，见下方不变性声明。
 *
 * 【引脚契约 / Pin contract】
 *   输入 nCount    : INT   — 样本数 [个]，有效域 0 至 64，超上限按 64 截取；
 *   输入 fP        : REAL  — 分位点 [0.0 至 1.0]，0.95 表示 P95，越界钳位；
 *   输入输出 afData: LREAL 数组 [1..64] — 样本数组 [任意工程单位]，
 *                             **只读语义**：函数不写回任何元素，调用方数据帧后不变；
 *   输出 fActualP  : REAL  — 实际生效的分位点（钳位后的值）；
 *   输出 nGuard    : DINT  — 本次排序与拷贝循环的累计次数（防死锁计数，兼作性能诊断）；
 *   输出 bEmpty    : BOOL  — 有效样本为空（或全部非有限 / 排序保护触发），返回 0.0；
 *   输出 uErrorId  : UDINT — 事件码，0 = 无。本件全部码为信息级；
 *   返回  值        : LREAL — 分位值 [与样本同单位]，空集时返回 0.0。
 *
 * 【算法分步 / Algorithm steps（R-7 线性插值口径，写死防漂移）】
 *   ① 样本数闸门：nCount 小于 1 → 空集，返回 0.0、bEmpty 置位、置 0002_000E；
 *      nCount 大于 64 → 只取前 64 个，置 0124（信息级提示，不中断）；
 *   ② 分位点钳位：小于 0 钳到 0，大于 1 钳到 1，非有限（NaN）按 0 处理，置 0124；
 *      fActualP 输出钳位后的实际生效值，供 HMI 显示「实际用的是哪个分位」；
 *   ③ 拷贝筛选取样：把有效样本逐个拷进块内私有数组，**非有限样本直接剔除**
 *      （NaN 参与比较会让整个排序失去传递性，必须前置剔除而不是排序后过滤）；
 *      剔除后为空 → 按空集处理，置 0002_000E；
 *   ④ 插入排序：样本上限 64，插入排序的常数项小于快排且无递归、无栈深风险，
 *      对本规模是最优选择；两层循环均受同一防死锁计数约束；
 *   ⑤ 位置计算：pos = fActualP × (n − 1)，nLo 为 pos 的整数部分（向下取整，
 *      pos 恒非负，截断即向下），fFrac 为小数部分；
 *   ⑥ 插值取值：若 nLo 已到末位则直接取末元素（不外插，P100 恒为最大值）；
 *      否则取第 nLo 与第 nLo+1 个（数组 1 起，故下标分别加 1 与加 2）做线性插值；
 *   ⑦ 结果守卫：插值结果非有限时返回 0.0 并置 0124，绝不把 NaN 交给调用方。
 *
 * 【数组不变性声明 / Array immutability（与就地排序件的语义差异）】
 *   库内排序件（就地快速排序）会改写调用方数组，本件**不会**：全部排序都在块内
 *   私有数组上完成。两种语义同时存在于库内是刻意的——统计取值不应破坏现场数据，
 *   而复用同一份样本做多种统计时更需要原数组保持不变。
 *   代价是每次调用多做一次 64 元素的拷贝，扫描周期量级可忽略。
 *
 * 【为什么本件不调用库内排序件 / Why the sort is inlined】
 *   DL_MathData 层虽然可以依赖本层其他件，但本批六件按要求零互相依赖：
 *   若调用就地快排，则必须先把调用方数组整体备份再回写，既多一次拷贝，
 *   又会在保护触发时留下「部分有序」的中间态，语义反而更差。故内联插入排序。
 *
 * 【边界防错清单 / Boundary guard list】
 *   B1 nCount 小于 1 → 空集返回 0.0、bEmpty 置位、置 0002_000E；
 *   B2 nCount 大于 64 → 截到 64 并置 0124（不越界读取调用方数组）；
 *   B3 fP 越界或非有限 → 钳到 0 或 1，置 0124，继续计算；
 *   B4 样本含 NaN / 无穷 → 剔除该样本；剔除后为空则按空集处理；
 *   B5 排序循环防死锁：拷贝与排序共用 nGuard，超上限即停止、置 bEmpty 并按空集返回，
 *      绝不返回「部分有序」的结果冒充成功；
 *   B6 插值下标双检：nLo 必在 0 至 nN−1 之间，取 nLo+1 与 nLo+2 前先判 nLo+1 是否
 *      越界，越界改取末元素，杜绝数组越界读；
 *   B7 单样本（nCount 为 1）→ pos 恒为 0，直接返回该样本，不外插；
 *   B8 浮点比较全为有序比较（大于 / 小于）；「零个样本」这类判据落在整数域，
 *      浮点判等红线在本件不适用。
 *
 * 【与既有件的职责边界 / Family separation】
 *   FB_DL_SignalStatistics  = 均值 / 方差 / 极值（不含分位）；
 *   FC_DL_QuickSortLReal    = 只排序不取值，且就地改写调用方数组；
 *   本件                    = 排序 + 分位插值，拷贝排序不改调用方数组。
 *   三者互不可替代：要「均值与方差」用统计件，要「有序副本」用排序件，
 *   要「某个分位点上的值」才用本件。
 *
 * 【调用示例 / Call example（仅行注释，不嵌套块注释）】
 *   // 节拍抖动判据：最近 32 个节拍的 P95 超过 12.5 秒即提示瓶颈工位
 *   // fP95 := FC_DL_PercentileLReal(nCount := 32, fP := 0.95,
 *   //          afData := afCycleTime, fActualP => fUsedP, nGuard => nSortCnt,
 *   //          bEmpty => bNoSample, uErrorId => uPctErr);
 *   // IF (NOT bNoSample) AND (fP95 > 12.5) THEN
 *   //     bBottleneckHint := TRUE;
 *   // END_IF
 *
 * 【平台移植注意 / Porting notes】
 *   LREAL 为 64 位浮点，三平台一致；类型转换全部显式写出（REAL 到 LREAL、
 *   LREAL 到 INT），不做隐式提升；插入排序无递归、无栈使用，嵌入式运行时安全；
 *   数组上下界由常量与循环上界双重约束，不依赖动态边界函数。
 *
 * 【工程背景与应用场景 / Background and use cases】
 *   ① 节拍分析：P50 反映典型节拍，P95 反映抖动尾部，两者之差即瓶颈裕度；
 *   ② 称重 / 灌装偏差：P99 用于判定「最差 1 个百分点是否超差」，比均值更贴近验收口径；
 *   ③ 温度分布：多测点 P50 作为炉温代表值，抗单点传感器漂移；
 *   ④ 来料尺寸抽检：P5 与 P95 构成 90 个百分点的居中区间，用于与公差带做对撞判定。
 *
 * 【验收向量 / Acceptance vectors】
 *   V1 中位：样本 1, 2, 3, 4，fP = 0.5 → pos 1.5 → 2 + 0.5 × (3 − 2) = 2.5；
 *   V2 P90：同样本，fP = 0.9 → pos 2.7 → 3 + 0.7 × (4 − 3) = 3.7；
 *   V3 单样本：样本 7.5，fP = 0.9 → 7.5（pos 为 0，不外插）；
 *   V4 越界钳位：fP = 1.5、样本 1, 2, 3, 4 → fActualP 1.0、返回 4.0、置 0124；
 *   V5 空集：nCount 为 0 → 返回 0.0、bEmpty 置位、置 0002_000E；
 *   V6 输入不变：样本 4, 1, 3, 2，fP = 0.5 → 返回 2.5，且调用方数组帧后仍为原序。
 *
 * 【事件码表 / Event code table（全部信息级，不置报警位）】
 *   16#0001_0124  分位点或样本数越界已钳位 / 非有限样本已剔除 / 结果非有限已回退；
 *   16#0002_000E  有效样本为空（含全部非有限与排序保护触发），返回 0.0。
 *
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 11 · 泳道 A · LGF Math 组）
 *============================================================================*)
FUNCTION FC_DL_PercentileLReal : LREAL
VAR_INPUT
    nCount : INT;                          // 样本数 [个]，有效域 0 至 64 / Sample count [pcs], valid range 0 to 64
    fP     : REAL;                         // 分位点 [0.0 至 1.0]，0.95 即 P95 / Percentile [0.0 to 1.0], 0.95 means P95
END_VAR
VAR_IN_OUT
    afData : ARRAY[1..64] OF LREAL;        // 样本数组 [工程单位]，只读语义，块内拷贝 / Sample array [EU], read-only, copied internally
END_VAR
VAR_OUTPUT
    fActualP : REAL;                       // 实际生效的分位点，越界已钳位 / Effective percentile after clamping
    nGuard   : DINT;                       // 循环累计次数，防死锁兼性能诊断 / Loop counter for guard and diagnostics
    bEmpty   : BOOL;                       // 有效样本为空，返回 0.0 / Empty valid sample set, returns 0.0
    uErrorId : UDINT;                      // 事件码，0 = 无 / Event code, 0 = none
END_VAR
VAR
    afSorted : ARRAY[1..64] OF LREAL;      // 块内私有排序数组，不触碰调用方 / Private sorted array, the caller array is untouched
    nUsable  : INT;                        // 本拍可读样本上界 [个] / Readable sample upper bound of this scan [pcs]
    nN       : INT;                        // 剔除非有限后的有效样本数 [个] / Effective sample count after filtering [pcs]
    nI       : INT;                        // 外层索引 / Outer index
    nJ       : INT;                        // 内层回退索引 / Inner shift index
    fKey     : LREAL;                      // 当前插入键值 [工程单位] / Current insertion key [EU]
    bShift   : BOOL;                       // 内层回退继续标志 / Inner shift continues flag
    bSortOk  : BOOL;                       // 排序完整完成标志 / Sort completed flag
    fPos     : LREAL;                      // 分位在样本序列上的位置 [-] / Percentile position in the sample sequence [-]
    nLo      : INT;                        // 位置整数部分（截断） / Integer part of the position, truncated
    fFrac    : LREAL;                      // 位置小数部分 [-] / Fractional part of the position [-]
    fLo      : LREAL;                      // 插值下样本值 [工程单位] / Lower interpolation sample [EU]
    fHi      : LREAL;                      // 插值上样本值 [工程单位] / Upper interpolation sample [EU]
    fResult  : LREAL;                      // 插值结果工作副本 [工程单位] / Working copy of the interpolation result [EU]
END_VAR
VAR CONSTANT
    DL_SAMPLE_MAX : INT   := 64;           // 样本上限 [个]，与数组维度一致 / Sample upper bound [pcs], matches the array
    DL_GUARD_MAX  : DINT  := 100000;       // 循环防死锁上限 [次] / Loop guard limit [count]
    DL_FLOAT_EPS  : REAL  := 1.0E-6;       // 浮点容差 [-] / Float epsilon [-]
    DL_LL_EPS     : LREAL := 1.0E-9;       // 长浮点容差 [-] / Long-real epsilon [-]
    DL_P_MIN      : REAL  := 0.0;          // 分位点下界 / Percentile lower bound
    DL_P_MAX      : REAL  := 1.0;          // 分位点上界 / Percentile upper bound
    DL_LL_ZERO    : LREAL := 0.0;          // 长浮点零值 / Long-real zero
    DL_LL_ONE     : LREAL := 1.0;          // 长浮点一值，位置计算的减数 / Long-real one, used in the position formula
    DL_INF_LIM    : LREAL := 1.0E300;      // 非有限值判据阈值 / Non-finite threshold
    DL_ERR_CLAMP  : UDINT := 16#0001_0124; // 钳位与剔除的信息级码 / Info code for clamping and filtering
    DL_ERR_EMPTY  : UDINT := 16#0002_000E; // 有效样本为空的信息级码 / Info code for an empty valid sample set
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与输出预置（函数必须先给出安全返回值）
 *      Preset the return value and the outputs
 *   返回值预置 0.0、bEmpty 预置假：只有明确判定为空集时才置真，避免误报。
 *-----------------------------------------------------------------------------*)
FC_DL_PercentileLReal := DL_LL_ZERO;       // 返回值预置 0（Return preset to zero）
fActualP  := DL_P_MIN;                     // 生效分位点预置下界（Effective percentile preset）
nGuard    := 0;                            // 循环计数清零（Loop guard cleared）
bEmpty    := FALSE;                        // 空集标志预置假（Empty flag preset false）
uErrorId  := 16#0000_0000;                 // 事件码预清零（Event code preset to zero）
bSortOk   := TRUE;                         // 排序完成标志预置真（Sort flag preset true）
nN        := 0;                            // 有效样本数预置 0（Effective count preset）
nUsable   := 0;                            // 可读样本数预置 0（Readable count preset）
fResult   := DL_LL_ZERO;                   // 结果副本预置 0（Result working copy preset）

(*------------------------------------------------------------------------------
 * 段 2｜样本数闸门与可读上界（边界 B1 / B2）
 *      Sample count gate and the readable upper bound
 *   上界同时受「调用方声明数」与「数组容量」双重约束：取小者，
 *   任何情况下都不会读出数组之外。
 *-----------------------------------------------------------------------------*)
IF nCount < 1 THEN                         // 无样本（No samples declared）
    bEmpty   := TRUE;                      // 置空集标志（Raise the empty flag）
    uErrorId := DL_ERR_EMPTY;              // 置空集信息码（Raise the empty info code）
    RETURN;                                // 早退，返回值保持 0.0（Early exit, return stays zero）
END_IF

nUsable := nCount;                         // 可读上界先取声明数（Readable bound takes the declared count）
IF nUsable > DL_SAMPLE_MAX THEN            // 超数组容量（Above the array capacity）
    nUsable  := DL_SAMPLE_MAX;             // 截到容量，杜绝越界读（Truncate to the capacity）
    uErrorId := DL_ERR_CLAMP;              // 置截断信息码（Raise the truncation info code）
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜分位点钳位（边界 B3）
 *      Percentile clamping
 *   次序写死：先判上越界、再判下越界、最后判非有限（NaN 与两个有序比较都为假）。
 *   非有限按 0 处理而不是按 1 处理：0 分位取最小值，属保守回退。
 *-----------------------------------------------------------------------------*)
fActualP := fP;                            // 生效分位点先接管输入（Take the input percentile）
IF fP > DL_P_MAX THEN                      // 上越界（Above the upper bound）
    fActualP := DL_P_MAX;                  // 钳到 1（Clamp to one）
    uErrorId := DL_ERR_CLAMP;              // 置钳位信息码（Raise the clamp info code）
ELSIF fP < DL_P_MIN THEN                   // 下越界（Below the lower bound）
    fActualP := DL_P_MIN;                  // 钳到 0（Clamp to zero）
    uErrorId := DL_ERR_CLAMP;              // 置钳位信息码（Raise the clamp info code）
ELSIF NOT ((fP <= DL_P_MAX) AND (fP >= DL_P_MIN)) THEN   // 非有限值，NaN 落入此支（Not finite, NaN path）
    fActualP := DL_P_MIN;                  // 保守按 0 分位（Fall back to the zero percentile）
    uErrorId := DL_ERR_CLAMP;              // 置钳位信息码（Raise the clamp info code）
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜拷贝取样并剔除非有限样本（边界 B4）
 *      Copy the samples and filter out the non-finite ones
 *   NaN 参与比较会让排序失去传递性，必须在排序**之前**剔除，而不是排完再过滤。
 *-----------------------------------------------------------------------------*)
FOR nI := 1 TO nUsable DO                  // 只遍历可读区间（Iterate the readable range only）
    nGuard := nGuard + 1;                  // 拷贝循环同样计入防死锁（Counted by the guard）
    IF (afData[nI] <= DL_INF_LIM) AND (afData[nI] >= -DL_INF_LIM) THEN   // 有限样本（Finite sample）
        nN := nN + 1;                      // 有效样本数加 1（Effective count increments）
        afSorted[nN] := afData[nI];        // 拷进私有数组，调用方数组只读（Copy into the private array）
    ELSE                                   // 非有限样本（Non-finite sample）
        uErrorId := DL_ERR_CLAMP;          // 置剔除信息码（Raise the filtering info code）
    END_IF
END_FOR

IF nN < 1 THEN                             // 剔除后无有效样本（No effective sample left）
    bEmpty   := TRUE;                      // 置空集标志（Raise the empty flag）
    uErrorId := DL_ERR_EMPTY;              // 空集码覆盖钳位码，语义优先（The empty code wins）
    RETURN;                                // 早退，返回值保持 0.0（Early exit, return stays zero）
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜插入排序（边界 B5：两层循环共用防死锁计数）
 *      Insertion sort with a shared guard counter
 *   样本不超过 64，插入排序常数项小、无递归、无栈深风险，对本规模最优；
 *   超出防护上限即判定排序未完成，绝不把「部分有序」冒充成功。
 *-----------------------------------------------------------------------------*)
FOR nI := 2 TO nN DO                       // 从第二个元素起逐个插入（Insert from the second element）
    IF nGuard > DL_GUARD_MAX THEN          // 早期熔断，避免无谓空转（Early trip to avoid spinning）
        bSortOk := FALSE;                  // 标记未完成（Mark as incomplete）
        EXIT;                              // 跳出外层循环（Leave the outer loop）
    END_IF

    fKey   := afSorted[nI];                // 当前待插入键值（Current insertion key）
    nJ     := nI - 1;                      // 从已排序区末位开始回退（Start from the sorted tail）
    bShift := TRUE;                        // 回退标志置真（Shift flag set）

    WHILE bShift AND (nJ >= 1) DO          // 回退直到找到插入位（Shift until the slot is found）
        nGuard := nGuard + 1;              // 内层循环计入防死锁（Counted by the guard）
        IF nGuard > DL_GUARD_MAX THEN      // 触顶熔断（Guard exhausted）
            bShift  := FALSE;              // 停止回退（Stop shifting）
            bSortOk := FALSE;              // 标记未完成（Mark as incomplete）
        ELSIF afSorted[nJ] > fKey THEN     // 前一个更大，后移一格（Shift one slot right）
            afSorted[nJ + 1] := afSorted[nJ];
            nJ := nJ - 1;                  // 索引回退（Index steps back）
        ELSE                               // 找到插入位（Insertion slot found）
            bShift := FALSE;               // 停止回退（Stop shifting）
        END_IF
    END_WHILE

    afSorted[nJ + 1] := fKey;              // 键值落位，nJ 恒非负故下标合法（Place the key, index stays valid）
END_FOR

IF NOT bSortOk THEN                        // 排序未完成，结果不可信（Sort incomplete, result untrusted）
    bEmpty   := TRUE;                      // 按空集处理，绝不返回半成品（Treat as empty, never return a partial result）
    uErrorId := DL_ERR_EMPTY;              // 置空集信息码（Raise the empty info code）
    RETURN;                                // 早退，返回值保持 0.0（Early exit, return stays zero）
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜位置计算（R-7 口径：pos = P × (n − 1)）
 *      Position computation
 *   pos 恒非负，故 LREAL 到 INT 的截断转换等价于向下取整，无需额外取整函数。
 *-----------------------------------------------------------------------------*)
fPos  := REAL_TO_LREAL(fActualP) * (INT_TO_LREAL(nN) - DL_LL_ONE);   // 位置 = P 乘（n 减 1）（Position formula）
nLo   := LREAL_TO_INT(fPos);               // 整数部分，pos 非负故截断即向下（Truncation equals floor here）
fFrac := fPos - INT_TO_LREAL(nLo);         // 小数部分（Fractional part）

IF nLo < 0 THEN                            // 理论上不可达的兜底（Unreachable fallback）
    nLo := 0;                              // 索引归零（Index reset）
    fFrac := DL_LL_ZERO;                   // 小数部分归零（Fraction reset）
END_IF
IF nLo > (nN - 1) THEN                     // 上限兜底（Upper fallback）
    nLo := nN - 1;                         // 钳到末位（Clamp to the last slot）
    fFrac := DL_LL_ZERO;                   // 小数部分归零（Fraction reset）
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜线性插值取值（边界 B6 / B7：下标双检，末位不外插）
 *      Linear interpolation with double index checks
 *   数组 1 起：第 k 个样本（0 起计）位于下标 k+1，故下样本取 nLo+1、上样本取 nLo+2。
 *-----------------------------------------------------------------------------*)
IF (nLo + 1) >= nN THEN                    // 已到末位，直接取最大样本（Last slot, take the maximum）
    fResult := afSorted[nN];               // 不外插，P100 恒为最大值（No extrapolation）
ELSE                                       // 需要插值（Interpolation required）
    fLo := afSorted[nLo + 1];              // 下样本（Lower sample）
    fHi := afSorted[nLo + 2];              // 上样本，下标已由上一支保证不越界（Upper sample, bounds proven）
    fResult := fLo + fFrac * (fHi - fLo);  // 线性插值（Linear interpolation）
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜结果守卫（边界 B8）
 *      Post guard on the interpolation result
 *   非有限结果一律回退 0.0：统计值的下游多为比较与报警，NaN 会在那里静默失效。
 *-----------------------------------------------------------------------------*)
IF NOT ((fResult <= DL_INF_LIM) AND (fResult >= -DL_INF_LIM)) THEN   // 结果非有限（Non-finite result）
    fResult   := DL_LL_ZERO;               // 回退 0（Fall back to zero）
    uErrorId  := DL_ERR_CLAMP;             // 置回退信息码（Raise the fallback info code）
END_IF

FC_DL_PercentileLReal := fResult;          // 结果落位（Place the result）
END_FUNCTION
