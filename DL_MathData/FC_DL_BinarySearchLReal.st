(*==============================================================================
 * 组件名称 (Component)  : FC_DL_BinarySearchLReal
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.1
 * 分类/来源标签         : lgf-datahandling（T2-1 LGF Data Handling 组回补）
 * 作者/日期             : Daoli Library / 2026-11-15
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS），纯函数无状态
 * 功能简介 (Function)   : 对升序 LREAL 数组做经典二分查找，返回首个命中索引
 *                         （元素下标），未命中返回 -1；无状态、无副作用纯函数。
 *                         与 FB_DL_ArraySearchFirst 职责分离：
 *                         本块 = 升序数组 O(log n) 快速查找（要求调用方保证有序）；
 *                         线性块 = 无序数组 O(n) 通用查找。
 *                         典型现场用途：标定表按给定工程量反查断点槽位、
 *                         报警限值表按测量值定位档位区间、配方参数有序索引。
 * 开源溯源 (Origin)     : 原创实现（参考 LGF 公开手册 Data Handling 分类中
 *                         数组查找族的功能分类与参数域），只借分类/参数域/命名，
 *                         clean-room 实现，未复制任何源码。来源标签：lgf-datahandling。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: ABS
 *
 * 【接口契约 / Interface contract】
 *   返回值：命中索引 [元素下标]，未命中 = -1。
 *   输入  ：afSorted 升序数组（调用方保证有序，VAR_IN_OUT 注入避免复制）；
 *           nCount 有效元素数；fTarget 目标值。
 *   输出  ：bFound 命中标志（与返回值同真相：TRUE 恒伴随返回值 >= 0）。
 *   纪律  ：纯函数同输入同输出；无内部状态；可安全放进 IF 表达式与
 *           多任务环境（无共享可变状态）。
 *
 * 【使用示例 / Usage example】
 *   VAR
 *       afCalTab : ARRAY[0..1023] OF LREAL;     // 升序标定表
 *       nSlot    : DINT;                        // 命中槽位
 *       bHit     : BOOL;                        // 命中标志
 *   END_VAR
 *   nSlot := FC_DL_BinarySearchLReal(afSorted := afCalTab,
 *                                    nCount := nRows, fTarget := fMeas,
 *                                    bFound => bHit);
 *   IF NOT bHit THEN
 *       nSlot := -1;    // 未命中走线性插值等后备逻辑
 *   END_IF
 *
 * 【选型对照 / Selection guide】
 *   本块（BinarySearchLReal）：升序数组、O(log n)、1024 元素最多 11 次比较、
 *                             不校验有序（契约责任在调用方）、无全量计数。
 *   FB_DL_ArraySearchFirst  ：无序可用、O(n) 单遍、支持全量计数与前缀搜索。
 *   高频轮询查找（每周期都查）选本块；低频事件查找 / 无序数据选线性块。
 *
 * 【算法与实时性披露 / Algorithm and timing disclosure】
 *   经典闭区间二分：每轮比较中点元素，命中即返；未命中按目标在左 / 右
 *   半区间收缩。DL_BS_MAX = 1024 时理论最大迭代 11 次（log2(1024) 向上取整），
 *   LREAL 比较约百纳秒级，单次调用总耗时微秒级以下，可放心放进每周期轮询。
 *   WHILE 循环配 64 次守护计数器（理论值的约 6 倍裕度），杜绝死循环。
 *
 * 验收向量 (Acceptance) : （afSorted = {1.5, 2.5, 3.5, 4.5, 5.5}，nCount = 5）
 *   V1 fTarget = 3.5 → 返回 2，bFound TRUE（中部命中）
 *   V2 fTarget = 1.5 → 返回 0，bFound TRUE（下边界命中）
 *   V3 fTarget = 5.5 → 返回 4，bFound TRUE（上边界命中）
 *   V4 fTarget = 3.6 → 返回 -1，bFound FALSE（带内未命中，容差外）
 *   V5 fTarget = 0.5 → 返回 -1，bFound FALSE（低于全域）
 *
 * 【V1 逐轮迭代推演 / Iteration trace of V1】
 *   轮次 ｜ nLo ｜ nHi ｜ nMid ｜ 探测值 ｜ 判定
 *   1    ｜ 0   ｜ 4    ｜ 2     ｜ 3.5    ｜ 容差命中 → 返回 2（1 轮即中）
 * 【V4 逐轮迭代推演 / Iteration trace of V4】（fTarget = 3.6）
 *   轮次 ｜ nLo ｜ nHi ｜ nMid ｜ 探测值 ｜ 判定
 *   1    ｜ 0   ｜ 4    ｜ 2     ｜ 3.5    ｜ 3.5 < 3.6 → 收缩右半 nLo=3
 *   2    ｜ 3   ｜ 4    ｜ 3     ｜ 4.5    ｜ 4.5 > 3.6 → 收缩左半 nHi=2
 *   3    ｜ nLo=3 > nHi=2 → 区间塌缩，WHILE 退出，返回 -1（3 轮收敛）
 *
 * 【重复值语义声明 / Duplicate-value semantics】
 *   数组含重复目标值时返回其中任一命中下标（经典二分不保证首个），
 *   需要"首个命中"语义的场合请改用 FB_DL_ArraySearchFirst（线性块），
 *   该契约与线性块的"首个命中"形成互补，选型时按语义需求取舍。
 *
 * 【常见误用清单 / Common misuse checklist】
 *   M1 对无序数组调用 → 返回值无意义（B1 契约责任），先排序再查；
 *   M2 nCount 传数组全长而实际只装了前 n 行 → 残留旧数据可能误命中，
 *      按实际装载行数传参；
 *   M3 把返回值直接当下标写数组而不查 bFound → 未命中时 -1 会被当
 *      "最后一个元素"（部分平台负下标越界），必须先判 bFound；
 *   M4 用本块结果做浮点精确相等断言 → 命中本身已是容差口径，
 *      后续再判等请沿用同一容差常量，勿混用严格判等；
 *   M5 在扫描周期内对同一表反复排序+查找 → 排序成本远高于查找本身，
 *      排序一次后缓存"已有序"标志再高频查找。
 * 故障码表 (Error codes):
 *   16#0001_010F  nCount 越界，已钳位到 0..DL_BS_MAX（信息级，查找照常执行）
 *   16#0001_0206  二分守护计数超限或下标兜底触发，强制返回未命中
 *                 （故障级，理论不可达）
 *                 【码位终审】原拟 0002_0101 / 0002_0201 与 DL_Algo PID 族
 *                 （FB_DL_PidController 0002_0101 输出饱和、FB_DL_CascadePid
 *                 0002_0201 副设定钳位）冲突，且 0002_01xx 段已由 DL_Algo
 *                 PID 族登记；DL_MathData 依公约 0.7 归 0001_xxxx 段，
 *                 R9 终审顺延至 0001_010F / 0001_0206（与既有 0101~010F、
 *                 0201~0212 逐条比对无冲突）。
 * 红线自检 (Redline)    : R1 ✓ 零全局存储 / 零外部变量引用 ｜ R2 ✓ 零物理地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ nCount 钳位 + 中点防溢出 + 守护计数 + 容差判等 + 空表直退
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 纯函数无状态（R6 状态机 N/A）
 *                         R7 ✓ 无定时器 / 边沿实例（R7 N/A）
 * 边界契约 (Boundaries):
 *   B1 调用方保证数组升序有序，本函数不校验全序（校验需 O(n)，会摧毁 O(log n) 价值）；
 *      无序输入的返回值无意义，属调用方契约责任，头注释写死。
 *   B2 中点计算固定写法 nMid := nLo + (nHi - nLo) / 2，防 (nLo + nHi) 溢出，
 *      DINT 域内安全——二分实现中最常见的溢出缺陷，此处从写法上根除。
 *   B3 守护上限 64 次：DL_BS_MAX = 1024 理论最大迭代 11 次，64 为约 6 倍裕度，
 *      超限视为平台异常强制退出，bFound FALSE 返回 -1，绝不死循环。
 *   B4 命中判据 ABS(afSorted[nMid] - fTarget) < DL_FLOAT_EPS，禁浮点直接判等；
 *      区间收缩判据用严格大于 / 小于，与容差判等正交不冲突。
 *   B5 nCount = 0（空表）直接返回 -1，合法工况不置故障码。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 09 · 泳道 A · Level 0 原子族回补）
 *   2026-11-15  v1.0.1  终审修复：补声明缺失的 uErrorId 输出引脚（原 1.0.0 在
 *                       函数体内五处读写 uErrorId 却未声明，三平台均编译失败）；
 *                       故障码 0002_0101/0002_0201 与 DL_Algo PID 族冲突，
 *                       顺延至 0001_010F / 0001_0206（同段位归口 DL_MathData）
 *============================================================================*)
FUNCTION FC_DL_BinarySearchLReal : DINT    // 返回命中索引 [元素下标]，未命中 = -1 / Hit index, -1 when not found
VAR_IN_OUT
    afSorted   : ARRAY[0..DL_BS_MAX-1] OF LREAL;  // 升序数组（调用方保证有序，本函数不校验全序）/ Ascending array, sorted by the caller
END_VAR
VAR_INPUT
    nCount     : DINT;                 // 有效元素数 [个]，0..DL_BS_MAX，越界钳位 / Valid element count [items], clamped
    fTarget    : LREAL;                // 目标值 [工程单位随应用] / Target value [EU by application]
END_VAR
VAR_OUTPUT
    bFound     : BOOL;                 // 命中标志，与返回值同真相源 / Hit flag, same truth as the return value
    uErrorId   : UDINT;                // 故障码，0 = 无故障（0001_010F 钳位信息级 / 0001_0206 守护故障级）/ Error code, 0 = no error
END_VAR
VAR
    nLo        : DINT;                 // 区间下界索引（闭区间）/ Interval lower bound index, inclusive
    nHi        : DINT;                 // 区间上界索引（闭区间）/ Interval upper bound index, inclusive
    nMid       : DINT;                 // 中点索引 / Midpoint index
    nGuard     : DINT;                 // 循环防死锁守护计数器 [次] / Loop guard counter [iterations]
    nCountEff  : DINT;                 // 钳位后的有效元素数 [个] / Effective clamped element count [items]
    fProbe     : LREAL;                // 当前探测点元素值缓存 / Probed element value cache
END_VAR
VAR CONSTANT
    DL_BS_MAX   : DINT := 1024;        // 数组容量上限 [元素]，必须与数组维度一致 / Array capacity limit, must match the dimension
    DL_BS_GUARD : DINT := 64;          // 二分守护上限 [次]，理论 11 次 × 约 6 倍裕度 / Binary guard limit, ~6x margin of theory
    DL_FLOAT_EPS: LREAL := 1.0E-9;     // LREAL 判等容差，禁浮点直接判等 / LREAL equality tolerance
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜缺省返回：未命中语义（-1 / FALSE），故障码清零
 *      Default return: miss semantics, error code cleared
 *      缺省即失败语义：任何提前退出路径都自动携带"未命中"，不会误报成功
 *-----------------------------------------------------------------------------*)
FC_DL_BinarySearchLReal := -1;
bFound    := FALSE;
uErrorId  := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 2｜范围钳位与空表直退（边界 B5）：nCount = 0 合法直退不置故障
 *      Range clamp and empty-table early exit
 *-----------------------------------------------------------------------------*)
IF (nCount < 0) OR (nCount > DL_BS_MAX) THEN
    IF nCount < 0 THEN
        nCountEff := 0;         // 负数视作空表 / Negative treated as empty
    ELSE
        nCountEff := DL_BS_MAX; // 超上限截断 / Overflow truncated
    END_IF
    uErrorId := 16#0001_010F;   // 信息级：范围越界已钳位 / Info: range clamped
ELSE
    nCountEff := nCount;        // 合法范围直通 / Legal range passes through
END_IF

IF nCountEff <= 0 THEN
    RETURN;                     // 空表：合法工况，保持缺省未命中返回
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜经典二分主体（边界 B2/B3/B4）：闭区间 [nLo, nHi]，中点防溢出写法，
 *      守护计数超限强制退出，命中判据用容差
 *      Classic binary search on a closed interval with overflow-safe midpoint
 *-----------------------------------------------------------------------------*)
nLo    := 0;                    // 闭区间下界从 0 起 / Closed lower bound from 0
nHi    := nCountEff - 1;        // 闭区间上界到末元素 / Closed upper bound at the last element
nGuard := 0;                    // 守护计数清零 / Guard counter cleared

WHILE (nLo <= nHi) AND (nGuard < DL_BS_GUARD) DO
    nGuard := nGuard + 1;       // 每轮累加，超限即退出（B3）

    (* 中点防溢出固定写法：不写 (nLo + nHi) / 2，DINT 极值下不回绕（B2） *)
    nMid := nLo + (nHi - nLo) / 2;

    (* 下标先判界再访问（红线 R4）：区间不变式已保证，仍显式兜底 *)
    IF (nMid >= 0) AND (nMid < DL_BS_MAX) THEN
        fProbe := afSorted[nMid];   // 取中点元素 / Probe the midpoint element
    ELSE
        uErrorId := 16#0001_0206;   // 故障级：下标越界兜底 / Fault: index guard tripped
        RETURN;
    END_IF

    IF ABS(fProbe - fTarget) < DL_FLOAT_EPS THEN
        FC_DL_BinarySearchLReal := nMid;    // 命中：返回当前下标 / Hit: return the index
        bFound := TRUE;
        RETURN;
    ELSIF fProbe < fTarget THEN
        nLo := nMid + 1;            // 目标在右半区间 / Target in the right half
    ELSE
        nHi := nMid - 1;            // 目标在左半区间 / Target in the left half
    END_IF
END_WHILE

(*------------------------------------------------------------------------------
 * 段 4｜守护超限兜底（边界 B3）：理论不可达，置故障级码保持未命中返回
 *      Guard-exceeded fallback: theoretically unreachable, fault code kept
 *-----------------------------------------------------------------------------*)
IF nGuard >= DL_BS_GUARD THEN
    uErrorId := 16#0001_0206;   // 故障级：守护超限 / Fault: guard exceeded
END_IF
END_FUNCTION
