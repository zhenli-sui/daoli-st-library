(*==============================================================================
 * 组件名称 (Component)  : FC_DL_ArrayDiffSummary
 * 所属子库 (Sublibrary) : DL_MathData
 * 归属目录 (Directory)  : C:\Library\DL_MathData
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 函数（FUNCTION）· 纯函数 · 双数组逐项容差比对
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 ABS，无实例依赖
 * 功能一句话 (Summary)  : 两组实数数组按统一绝对容差逐项比对，输出超差项数、首个
 *                         超差下标、最大绝对偏差及其下标与一致性结论。
 * 功能描述 (Function)   : 配方回读、双通道冗余比对、视觉参数下发校验三类场景，
 *                         现场只判「有差异」却定位不到第几项、差多少；用等号判等
 *                         又会因浮点误差把合格品报成不合格。本件一次扫描给出
 *                         计数、首个位置、最大偏差位置三个定位量，维修工直接翻表。
 * 与既有件边界 (Boundary): FC_DL_SearchMinMax 在单数组内找极值；FC_DL_ArraySearchFirst
 *                         在单数组内按判据找首个命中；本件是双数组逐项配对比较，
 *                         输出统计族，三者职责互斥，不存在覆盖关系。
 * 设计要点 (Key notes)  : ① 容差先取绝对值再钳到最小容差，杜绝「容差为零把纯浮点
 *                           噪声全判超差」的静默失效；
 *                         ② 非数与非有限值前置拦截：该项直接计为超差且不参与最大
 *                           偏差竞争，防止无穷大污染统计结果；
 *                         ③ 最大偏差并列时取先出现者，保证结果可复现；
 *                         ④ 单趟循环完成全部判定，无嵌套循环、无排序、无中间数组；
 *                         ⑤ 纯函数：无内部状态，同入参同结果，可重入。
 * 开源溯源 (Origin)     : 来源标签 lgf-comparator。LGF 为免费闭源发布的公开函数库
 *                         手册，本件仅借鉴其比较器组把「数组批量比较」与「容差窗口」
 *                         分成两个子域的分类骨架；许可证按其发布方条款仅作分类参考，
 *                         本件零代码行、零注释引用，属 clean-room 独立实现。统计口径
 *                         （最大偏差及其下标）为本库自有，LGF 批量比较不输出该量。
 * 码位说明 (Codes)      : 本件独占信息级码段 16#0001_0134 到 16#0001_0135，纯函数
 *                         无锁存面故不占故障级码；与 MathData 既有 0101 到 0124
 *                         及同轮 0125 到 013C 求差为空。
 *                         0134 项数越界已钳位 ｜ 0135 容差非法已回退。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 ABS。
 * 契约前置条件 (Contract): 函数内无法探测数组实际长度，「nCount 不得大于调用方实际
 *                         数组长度」由调用方负责，组态时须与装载行数绑定。
 * 红线自检 (Redline)    : 零全局变量表依赖 ｜ 零外部变量声明 ｜ 零物理地址
 *                         纯 IEC 61131-3 ｜ 浮点无等号判等，全部走容差 ｜ 无除法
 *                         数组下标先钳位后使用 ｜ 循环带守卫 ｜ 全变量双语同行注释
 * 修订历史 (Revision)   : 2026-11-15  v1.0.0  首版入库（Round 12 · 双数组比对族）
 *                         2026-11-15  v1.0.1  终审定点修复 A-D04：两项有限值相减仍可能
 *                         溢出为无穷（同号异号近满量程），原实现会让该偏差直接参与最大
 *                         偏差竞争并把 fMaxDev 污染成无穷；补「偏差本身超有限上限即按非
 *                         有限处置、不参与竞争」判据，兑现设计要点②的承诺
 *============================================================================*)

(*==============================================================================
 * 比对示意 (Comparison picture)：
 *   期望 10.0 / 20.0 / 30.0，实际 10.0 / 20.005 / 30.2，容差 0.01
 *   第 2 项偏差 0.005 在容差内，合格，但仍是目前最大偏差
 *   第 3 项偏差 0.2 超出容差，超差计数加一，并顶替最大偏差
 *   最终：超差一项、首个超差下标 3、最大偏差 0.2 落在下标 3、不相等
 *   若把实际第 2 项置为非数，该项计为超差且不参与最大偏差竞争
 *============================================================================*)

FUNCTION FC_DL_ArrayDiffSummary : BOOL
VAR_IN_OUT
    afExpected : ARRAY[1..64] OF REAL;   // 期望值数组，基准侧，只读不写 [工程单位] / Expected reference array, read only
    afActual   : ARRAY[1..64] OF REAL;   // 实际值数组，回读侧，只读不写 [工程单位] / Actual readback array, read only
END_VAR
VAR_INPUT
    nCount  : INT := 1;                  // 参与比对项数 [项]，域 1 到 64，越界钳位 / Item count, 1 to 64, clamped
    fAbsTol : REAL := 0.01;              // 统一绝对容差 [工程单位]，负值取绝对值 / Absolute tolerance, negative values folded to positive
END_VAR
VAR_OUTPUT
    nDiffCount   : INT;                  // 超差项数 [项] / Number of out of tolerance items
    nFirstDiffIdx : INT;                 // 首个超差项下标，0 表示无超差 [索引] / First out of tolerance index, zero when none
    fMaxDev      : REAL;                 // 最大绝对偏差值，只统计有限项 [工程单位] / Maximum absolute deviation over finite items
    nMaxDevIdx   : INT;                  // 最大偏差所在下标，0 表示未计算 [索引] / Index of the maximum deviation
    bEqual       : BOOL;                 // 全部项在容差内且无非有限值为真 / All items within tolerance and finite
    bNonFinite   : BOOL;                 // 出现过非数或非有限项为真 / NaN or infinity encountered
    uErrorId     : UDINT;                // 事件码，0 表示无事件 / Event code, zero means none
    bValid       : BOOL;                 // 项数与容差落在可服务域内为真，容差回退不否定结果 / Count and tolerance serviceable, a tolerance fallback does not void the result
END_VAR
VAR
    nCountUse : INT;                     // 生效项数，钳位后的值 [项] / Effective item count after clamping
    fTolUse   : REAL;                    // 生效容差，已取绝对值并钳到最小容差 [工程单位] / Effective tolerance after normalisation
    fDev      : REAL;                    // 单项绝对偏差 [工程单位] / Per item absolute deviation
    fA        : REAL;                    // 当前期望值快照 [工程单位] / Expected value snapshot
    fB        : REAL;                    // 当前实际值快照 [工程单位] / Actual value snapshot
    bFinA     : BOOL;                    // 期望值有限性判定结果 / Expected value finiteness
    bFinB     : BOOL;                    // 实际值有限性判定结果 / Actual value finiteness
    nGuard    : DINT;                    // 循环守卫计数，防遍历失控 [次] / Loop guard counter
    i         : INT;                     // 遍历索引，1 起 [索引] / Loop index, one based
END_VAR
VAR CONSTANT
    DL_ITEM_MAX   : INT := 64;          // 项数上限 [项] / Item count limit
    DL_GUARD_MAX  : DINT := 128;        // 循环守卫上限，两倍于项数上限故正常不触发 [次] / Loop guard limit, twice the item limit
    DL_I_MIN      : INT := 1;           // 数组首下标 [索引] / First array index
    DL_TOL_MIN    : REAL := 1.0E-9;     // 最小容差，容差为零时回退到此值 [工程单位] / Minimum tolerance used as the fallback
    DL_FINITE_MAX : REAL := 3.4E38;     // 有限性判定上限，超过即视为无穷大 [工程单位] / Finiteness ceiling, beyond this counts as infinity
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出预置：任何路径下输出确定
 *      Pre-set outputs so that every path is deterministic
 *-----------------------------------------------------------------------------*)
FC_DL_ArrayDiffSummary := FALSE;
nDiffCount             := 0;
nFirstDiffIdx          := 0;
fMaxDev                := 0.0;
nMaxDevIdx             := 0;
bEqual                 := FALSE;
bNonFinite             := FALSE;
uErrorId               := 16#0000_0000;
bValid                 := TRUE;

(*------------------------------------------------------------------------------
 * 段 2｜项数钳位（边界 B1）：先夹到 1 到 64 再进循环
 *      Clamp the item count into one to sixty four before the loop
 *-----------------------------------------------------------------------------*)
nCountUse := nCount;
IF nCountUse < DL_I_MIN THEN
    nCountUse := DL_I_MIN;
    bValid    := FALSE;
    uErrorId  := 16#0001_0134;   // 项数过小，已钳到下限
ELSIF nCountUse > DL_ITEM_MAX THEN
    nCountUse := DL_ITEM_MAX;
    bValid    := FALSE;
    uErrorId  := 16#0001_0134;   // 项数过大，已钳到上限
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜容差归一（边界 B2）：先拦非数，再取绝对值，再钳最小容差
 *      Normalise the tolerance: reject NaN, fold sign, apply the lower bound
 *-----------------------------------------------------------------------------*)
IF fAbsTol <> fAbsTol THEN
    fTolUse := DL_TOL_MIN;
    IF uErrorId = 16#0000_0000 THEN
        uErrorId := 16#0001_0135;   // 容差为非数，回退到最小容差
    END_IF
ELSE
    fTolUse := ABS(fAbsTol);
    IF (fTolUse < DL_TOL_MIN) OR (fTolUse > DL_FINITE_MAX) THEN
        fTolUse := DL_TOL_MIN;
        IF uErrorId = 16#0000_0000 THEN
            uErrorId := 16#0001_0135;   // 容差过小或非有限，回退到最小容差
        END_IF
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜单趟比对（边界 B3/B4/B5）：有限项走容差，非有限项直接计超差
 *      Single pass: finite items use the tolerance, non finite ones count as bad
 *-----------------------------------------------------------------------------*)
i      := DL_I_MIN;
nGuard := 0;
WHILE (i <= nCountUse) AND (nGuard < DL_GUARD_MAX) DO
    nGuard := nGuard + 1;

    fA    := afExpected[i];
    fB    := afActual[i];
    bFinA := NOT ((fA <> fA) OR (ABS(fA) > DL_FINITE_MAX));
    bFinB := NOT ((fB <> fB) OR (ABS(fB) > DL_FINITE_MAX));

    IF bFinA AND bFinB THEN
        fDev := ABS(fA - fB);
        IF fDev > DL_FINITE_MAX THEN
            (* 两个有限值相减仍可能溢出为无穷：按非有限处置，绝不参与最大偏差竞争 *)
            (* Two finite values can still overflow: treat it as non finite, no contest *)
            bNonFinite := TRUE;
            nDiffCount := nDiffCount + 1;
            IF nFirstDiffIdx = 0 THEN
                nFirstDiffIdx := i;
            END_IF
            fDev := 0.0;
        ELSE
            IF fDev > fTolUse THEN
                nDiffCount := nDiffCount + 1;
                IF nFirstDiffIdx = 0 THEN
                    nFirstDiffIdx := i;
                END_IF
            END_IF
            (* 最大偏差对所有有限项竞争，并列时取先出现者 *)
            (* The maximum is contested by every finite item, ties keep the earlier one *)
            IF fDev > fMaxDev THEN
                fMaxDev    := fDev;
                nMaxDevIdx := i;
            END_IF
        END_IF
    ELSE
        bNonFinite := TRUE;
        fDev       := 0.0;
        nDiffCount := nDiffCount + 1;
        IF nFirstDiffIdx = 0 THEN
            nFirstDiffIdx := i;
        END_IF
    END_IF

    i := i + 1;
END_WHILE

(*------------------------------------------------------------------------------
 * 段 5｜结论合成：无超差且无非有限值才算一致
 *      Verdict: equal only when no difference and every item is finite
 *-----------------------------------------------------------------------------*)
bEqual := (nDiffCount = 0) AND (NOT bNonFinite);

(*------------------------------------------------------------------------------
 * 段 6｜收口：返回一致性结论，合法性由 bValid 单独表达
 *      Close out: return the verdict, legality is expressed by bValid
 *-----------------------------------------------------------------------------*)
FC_DL_ArrayDiffSummary := bEqual;
END_FUNCTION
