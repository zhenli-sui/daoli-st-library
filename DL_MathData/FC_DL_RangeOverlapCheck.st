(*==============================================================================
 * 组件名称 (Component)  : FC_DL_RangeOverlapCheck
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类     (Category)   : 区间关系判定函数（Function · Comparator / Pure function）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS / MIN / MAX），零厂商方言
 * 功能描述 (Function)   : 判定两个实数区间 A、B 的几何关系（相离 / 仅端点相接 /
 *                         部分重叠 / 一方包含另一方 / 完全相等），并输出重叠长度。
 *                         输入是 4 个端点而非 1 个测量值，返回值为关系枚举，全程
 *                         无内部状态，可任意频次调用。用于配方参数域校验、时间窗
 *                         互斥检查、公差带叠加分析、安全包络与工艺窗口对撞检查。
 *
 * 【引脚契约 / Pin contract】
 *   输入 fA1        : REAL — 区间 A 端点 1 [任意工程单位]，无序自动对调；
 *   输入 fA2        : REAL — 区间 A 端点 2，同上；
 *   输入 fB1        : REAL — 区间 B 端点 1，无序自动对调；
 *   输入 fB2        : REAL — 区间 B 端点 2，同上；
 *   输入 bIncA      : BOOL — A 是否闭区间（含端点），默认 TRUE；
 *   输入 bIncB      : BOOL — B 是否闭区间，默认 TRUE；
 *   输出 fOverlapSpan : REAL — 重叠长度 [与输入同单位]，无重叠 = 0.0，恒非负；
 *   输出 bTouching    : BOOL — 仅端点相接（重叠长度 0 但边界重合）；
 *   输出 bValid       : BOOL — 四个输入全部有限（非 NaN、非无穷）= TRUE；
 *   输出 uErrorId     : UDINT — 事件码，0 = 无。本件全部码为信息级。
 *   返回  值          : E_DL_RangeRelation — 区间关系枚举，见下方成员语义表。
 *
 * 【关系枚举语义 / Relation enum semantics（同文件发布）】
 *   eInvalid  = 0  — 输入含非有限值（NaN / 无穷），关系不可判，重叠长度 0.0；
 *   eDisjoint = 10 — 完全相离（两区间之间有正间隙）；
 *   eTouching = 20 — 仅端点相接，重叠长度 0.0，bTouching 置位；
 *   ePartial  = 30 — 部分重叠（互相不包含，重叠长度大于 0）；
 *   eContains = 40 — 一方包含另一方（含端点恰好重合的包含）；
 *   eEqual    = 50 — 两端点均在容差内相等，重叠长度 = 区间长度。
 *
 * 【判定次序 / Decision order（写死，避免多解）】
 *   ① 有限性闸门 → 全部有限才继续，否则返回 eInvalid 并置 0121；
 *   ② 端点归一 → 每个区间内部排序，保证「下限 <= 上限」；
 *   ③ 相等判定 → 两端点同时落在容差内即 eEqual（先判，避免被包含分支吞掉）；
 *   ④ 相离判定 → 任一侧上限严格小于对侧下限减去容差，即 eDisjoint；
 *   ⑤ 相接判定 → 任一侧上限与对侧下限重合（容差内），即 eTouching；
 *   ⑥ 包含判定 → 一侧下限不大于对侧下限且上限不小于对侧上限，即 eContains；
 *   ⑦ 其余 → ePartial（此时重叠长度必然大于 0，无需再判）。
 *   次序不可调换：相等必须先于包含，相离必须先于相接，相接必须先于部分重叠。
 *
 * 【开闭区间口径 / Open and closed intervals（防误解声明）】
 *   ① 几何关系与开闭无关：「相接」只描述两组端点几何重合，开区间同样判相接；
 *   ② 开闭只影响「相接处那一个点是否属于公共交集」，其判据为
 *      bTouching AND bIncA AND bIncB —— 调用方按此合成，本件不额外输出第三态；
 *   ③ 部分重叠与包含的重叠长度按端点差值计算，不做「开区间减去两个端点」的
 *      离散化折算：连续量工程口径下端点测度为零，减去端点会引入 1 个单位误差；
 *   ④ 相等判定用容差而非判等（浮点判等红线）：两端点差值绝对值均小于容差即认为
 *      相等，容差取 1.0E-6，对应工程上「不可分辨」的量级。
 *
 * 【数值安全 / Numeric safety】
 *   N1 非有限值用「区间比较取反」识别：NaN 参与任何有序比较均为假，
 *      故 NOT(下限比较 AND 上限比较) 同时覆盖 NaN 与正负无穷，无需判等；
 *   N2 重叠长度在返回前置零下限保护：极少数退化输入可能算出负零附近的微小负值，
 *      一律钳到 0.0，保证输出恒非负（下游可直接做累加不打补丁）；
 *   N3 全件无除法、无开方、无累加迭代，不存在除零与溢出风险；
 *   N4 全件无循环、无数组访问，不存在越界风险。
 *
 * 【边界防错清单 / Boundary guard list】
 *   B1 输入非有限 → bValid FALSE、返回 eInvalid、重叠长度 0.0、置 0121（信息级）；
 *   B2 端点无序（如 A = [10, 0]）→ 自动对调后按归一区间判定，不置任何码；
 *   B3 零长度区间（两端点相等）→ 合法输入，参与全部关系判定，不特殊对待；
 *   B4 相接与部分重叠的边界由容差分割：端点差值绝对值小于容差判相接，
 *      否则按下限比较判重叠，容差量级远小于工程分辨率，不会误判真实重叠；
 *   B5 包含判定允许端点恰好重合（A 包含 B 且共端点），此时关系为 eContains
 *      而非 eEqual（eEqual 要求两端点都相等，先判，语义不重叠）。
 *
 * 【与既有件的职责边界 / Family separation（本族唯一二元件）】
 *   FC_DL_LimitClassify    = 判单个测量值落在哪一档（单点 → 档位）；
 *   FC_DL_Hysteresis       = 判单个测量值的迟滞切换（单点 + 历史 → 开关）；
 *   FB_DL_ToleranceWindow  = 判单个测量值是否落在公差带（单点 → 布尔）；
 *   本件                   = 判两个区间之间的关系（四点 → 关系枚举），
 *   输入元数不同、返回类型不同，四者不可互相替代。
 *
 * 【调用示例 / Call example（仅行注释，不嵌套块注释）】
 *   // 配方切换前校验：新工艺窗口与安全包络是否相撞
 *   // eRel := FC_DL_RangeOverlapCheck(fA1 := fSafeLo, fA2 := fSafeHi,
 *   //        fB1 := fNewLo, fB2 := fNewHi, bIncA := TRUE, bIncB := TRUE,
 *   //        fOverlapSpan => fOverlap, bTouching => bTouch,
 *   //        bValid => bCfgValid, uErrorId => uRelErr);
 *   // IF eRel = E_DL_RangeRelation.ePartial OR eRel = E_DL_RangeRelation.eContains THEN
 *   //     bRejectRecipe := TRUE;
 *   // END_IF
 *
 * 【平台移植注意 / Porting notes】
 *   仅用 ABS / MIN / MAX 三个标准函数与有序比较，无舍入模式依赖；
 *   容差与有限性阈值全部来自 VAR CONSTANT，换平台无需改逻辑；
 *   返回枚举类型随本文件发布，导入顺序上本文件不依赖任何其他 DL_ 组件。
 *
 * 【工程背景与应用场景 / Background and use cases】
 *   ① 配方参数域校验：新配方允许的温度带与设备安全包络相撞时拒绝下发；
 *   ② 时间窗互斥检查：两班次的作业窗若部分重叠，提示排程冲突；
 *   ③ 公差带叠加：来料公差带与装配公差带仅端点相接时，判定为「临界合格」；
 *   ④ 安全包络对撞：机器人可达包络与围栏安全距离带的重叠长度用于风险评估。
 *
 * 【验收向量 / Acceptance vectors】
 *   V1 部分重叠：A = [0, 10]、B = [5, 15] → ePartial、重叠长度 5.0；
 *   V2 端点相接：A = [0, 10]、B = [10, 20] → eTouching、重叠长度 0.0、bTouching；
 *   V3 包含：A = [0, 10]、B = [2, 8] → eContains、重叠长度 6.0；
 *   V4 相离：A = [0, 10]、B = [20, 30] → eDisjoint、重叠长度 0.0；
 *   V5 相等：A = [0, 10]、B = [0, 10] → eEqual、重叠长度 10.0；
 *   V6 无序端点：A = [10, 0]、B = [5, 15] → 归一后同 V1，ePartial、5.0；
 *   V7 非有限：fA1 为 NaN → eInvalid、bValid FALSE、uErrorId 0121。
 *
 * 【事件码表 / Event code table（全部信息级，不置报警位）】
 *   16#0001_0121  输入含非有限值，关系不可判，返回 eInvalid 与重叠长度 0.0。
 *
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 11 · 泳道 A · LGF Comparator 组）
 *
 * 同文件发布类型 (Co-published type) : E_DL_RangeRelation（本函数返回枚举，
 *   按库内惯例随宿主 POU 同文件发布，禁止在其他文件重复声明同名枚举）。
 *============================================================================*)
TYPE E_DL_RangeRelation :
(
    eInvalid  := 0,    // 输入非有限值，关系不可判 / Inputs not finite, relation undecidable
    eDisjoint := 10,   // 完全相离，存在正间隙 / Fully disjoint with a positive gap
    eTouching := 20,   // 仅端点相接，重叠长度为零 / Endpoint touch only, zero overlap
    ePartial  := 30,   // 部分重叠，互不包含 / Partial overlap, neither contains the other
    eContains := 40,   // 一方包含另一方 / One range contains the other
    eEqual    := 50    // 两端点均在容差内相等 / Both endpoints equal within tolerance
);
END_TYPE

FUNCTION FC_DL_RangeOverlapCheck : E_DL_RangeRelation
VAR_INPUT
    fA1     : REAL;                        // 区间 A 端点 1 [工程单位]，无序自动对调 / Range A endpoint 1 [EU], auto-swapped
    fA2     : REAL;                        // 区间 A 端点 2 [工程单位] / Range A endpoint 2 [EU]
    fB1     : REAL;                        // 区间 B 端点 1 [工程单位]，无序自动对调 / Range B endpoint 1 [EU], auto-swapped
    fB2     : REAL;                        // 区间 B 端点 2 [工程单位] / Range B endpoint 2 [EU]
    bIncA   : BOOL := TRUE;                // A 是否闭区间，含端点 / A closed interval flag, endpoints included
    bIncB   : BOOL := TRUE;                // B 是否闭区间，含端点 / B closed interval flag, endpoints included
END_VAR
VAR_OUTPUT
    fOverlapSpan : REAL;                   // 重叠长度 [工程单位]，无重叠 0.0，恒非负 / Overlap length [EU], zero when none, never negative
    bTouching    : BOOL;                   // 仅端点相接（几何重合，与开闭无关）/ Endpoint touch only, independent of openness
    bValid       : BOOL;                   // 四个输入全为有限值 / All four inputs are finite
    uErrorId     : UDINT;                  // 事件码，0 = 无 / Event code, 0 = none
END_VAR
VAR
    _fLoA   : REAL;                        // 区间 A 归一下限 [工程单位] / Normalised lower bound of range A [EU]
    _fHiA   : REAL;                        // 区间 A 归一上限 [工程单位] / Normalised upper bound of range A [EU]
    _fLoB   : REAL;                        // 区间 B 归一下限 [工程单位] / Normalised lower bound of range B [EU]
    _fHiB   : REAL;                        // 区间 B 归一上限 [工程单位] / Normalised upper bound of range B [EU]
    _fTmp   : REAL;                        // 对调临时量 [工程单位] / Swap temporary [EU]
    _fLo    : REAL;                        // 重叠区间下限 = 两个下限的较大者 [工程单位] / Overlap lower bound, the larger of both [EU]
    _fHi    : REAL;                        // 重叠区间上限 = 两个上限的较小者 [工程单位] / Overlap upper bound, the smaller of both [EU]
    _bFinite : BOOL;                       // 有限性闸门标志 / Finiteness gate flag
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS  : REAL  := 1.0E-6;       // 端点比较容差 [工程单位] / Endpoint comparison epsilon [EU]
    DL_INF_LIM    : REAL  := 1.0E37;       // 非有限值判据阈值，超此视为无穷 / Non-finite threshold, beyond is infinity
    DL_SPAN_ZERO  : REAL  := 0.0;          // 重叠长度下界，恒非负 / Overlap length lower bound, never negative
    DL_ERR_NONFIN : UDINT := 16#0001_0121; // 输入非有限值的信息级码 / Info code for non-finite inputs
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与输出预置（函数必须先给出安全返回值）
 *      Preset the return value and the outputs
 *   默认返回 eInvalid：任何早退路径都天然带着「不可判」语义，不会误报相离。
 *-----------------------------------------------------------------------------*)
FC_DL_RangeOverlapCheck := E_DL_RangeRelation.eInvalid;   // 返回值预置不可判（Return preset to undecidable）
fOverlapSpan := DL_SPAN_ZERO;              // 重叠长度预置 0（Overlap span preset to zero）
bTouching    := FALSE;                     // 相接标志预置（Touch flag preset）
bValid       := TRUE;                      // 有效性预置通过（Validity preset to pass）
uErrorId     := 16#0000_0000;              // 事件码预清零（Event code preset to zero）
_bFinite     := TRUE;                      // 有限性闸门预置通过（Finiteness gate preset to pass）

(*------------------------------------------------------------------------------
 * 段 2｜有限性闸门（边界 B1 / 数值安全 N1）
 *      Finiteness gate
 *   NaN 与任何有序比较的结果均为假，故「比较区间取反」同时覆盖 NaN 与无穷，
 *   不必使用浮点判等，也不依赖任何厂商的非有限值判定函数。
 *-----------------------------------------------------------------------------*)
IF NOT ((fA1 <= DL_INF_LIM) AND (fA1 >= -DL_INF_LIM)) THEN   // 端点 A1 非有限（A1 not finite）
    _bFinite := FALSE;                     // 闸门关闭（Close the gate）
END_IF
IF NOT ((fA2 <= DL_INF_LIM) AND (fA2 >= -DL_INF_LIM)) THEN   // 端点 A2 非有限（A2 not finite）
    _bFinite := FALSE;                     // 闸门关闭（Close the gate）
END_IF
IF NOT ((fB1 <= DL_INF_LIM) AND (fB1 >= -DL_INF_LIM)) THEN   // 端点 B1 非有限（B1 not finite）
    _bFinite := FALSE;                     // 闸门关闭（Close the gate）
END_IF
IF NOT ((fB2 <= DL_INF_LIM) AND (fB2 >= -DL_INF_LIM)) THEN   // 端点 B2 非有限（B2 not finite）
    _bFinite := FALSE;                     // 闸门关闭（Close the gate）
END_IF

IF NOT _bFinite THEN                       // 任一输入不可判（Any input undecidable）
    bValid   := FALSE;                     // 有效性置假（Validity cleared）
    uErrorId := DL_ERR_NONFIN;             // 置非有限值信息码（Raise the non-finite info code）
    RETURN;                                // 早退，返回值保持 eInvalid（Early exit, return stays eInvalid）
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜端点归一（边界 B2：无序端点自动对调）
 *      Endpoint normalisation, unordered endpoints are swapped
 *   归一后不可能出现「下限大于上限」，后续全部比较都是同向比较。
 *-----------------------------------------------------------------------------*)
_fLoA := fA1;                              // A 下限暂存端点 1（A lower bound takes endpoint 1）
_fHiA := fA2;                              // A 上限暂存端点 2（A upper bound takes endpoint 2）
IF _fLoA > _fHiA THEN                      // 端点逆序（Endpoints in reverse order）
    _fTmp := _fLoA;                        // 暂存下限（Save the lower bound）
    _fLoA := _fHiA;                        // 下限取原上限（Lower takes the former upper）
    _fHiA := _fTmp;                        // 上限取原下限（Upper takes the former lower）
END_IF

_fLoB := fB1;                              // B 下限暂存端点 1（B lower bound takes endpoint 1）
_fHiB := fB2;                              // B 上限暂存端点 2（B upper bound takes endpoint 2）
IF _fLoB > _fHiB THEN                      // 端点逆序（Endpoints in reverse order）
    _fTmp := _fLoB;                        // 暂存下限（Save the lower bound）
    _fLoB := _fHiB;                        // 下限取原上限（Lower takes the former upper）
    _fHiB := _fTmp;                        // 上限取原下限（Upper takes the former lower）
END_IF

_fLo := MAX(_fLoA, _fLoB);                 // 重叠下限 = 两个下限的较大者（Overlap lower bound）
_fHi := MIN(_fHiA, _fHiB);                 // 重叠上限 = 两个上限的较小者（Overlap upper bound）

(*------------------------------------------------------------------------------
 * 段 4｜关系判定（判定次序写死：相等 → 相离 → 相接 → 包含 → 部分）
 *      Relation decision in the frozen order
 *   次序不可调换，理由见头注释「判定次序」段；每支都显式给出重叠长度。
 *-----------------------------------------------------------------------------*)
IF (ABS(_fHiA - _fHiB) < DL_FLOAT_EPS) AND (ABS(_fLoA - _fLoB) < DL_FLOAT_EPS) THEN
    FC_DL_RangeOverlapCheck := E_DL_RangeRelation.eEqual;   // 相等：两端点均在容差内（Both endpoints equal within epsilon）
    fOverlapSpan := _fHiA - _fLoA;         // 重叠长度 = 区间长度（Overlap equals the range length）
ELSIF (_fHiA < _fLoB - DL_FLOAT_EPS) OR (_fHiB < _fLoA - DL_FLOAT_EPS) THEN
    FC_DL_RangeOverlapCheck := E_DL_RangeRelation.eDisjoint; // 相离：存在正间隙（A positive gap exists）
    fOverlapSpan := DL_SPAN_ZERO;          // 相离无重叠（No overlap when disjoint）
ELSIF (ABS(_fHiA - _fLoB) < DL_FLOAT_EPS) OR (ABS(_fHiB - _fLoA) < DL_FLOAT_EPS) THEN
    FC_DL_RangeOverlapCheck := E_DL_RangeRelation.eTouching; // 相接：端点几何重合（Endpoints coincide geometrically）
    fOverlapSpan := DL_SPAN_ZERO;          // 相接重叠长度为零（Zero overlap on a touch）
    bTouching    := TRUE;                  // 置相接标志（Raise the touch flag）
ELSIF ((_fLoA <= _fLoB + DL_FLOAT_EPS) AND (_fHiA >= _fHiB - DL_FLOAT_EPS)) OR
      ((_fLoB <= _fLoA + DL_FLOAT_EPS) AND (_fHiB >= _fHiA - DL_FLOAT_EPS)) THEN
    FC_DL_RangeOverlapCheck := E_DL_RangeRelation.eContains; // 包含：一方完全覆盖另一方（One range covers the other）
    fOverlapSpan := _fHi - _fLo;           // 重叠长度 = 被包含区间的长度（Overlap equals the inner range length）
ELSE
    FC_DL_RangeOverlapCheck := E_DL_RangeRelation.ePartial; // 部分重叠：互不包含（Partial overlap, neither contains）
    fOverlapSpan := _fHi - _fLo;           // 重叠长度 = 交集长度（Overlap equals the intersection length）
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜重叠长度非负保护（数值安全 N2）
 *      Non-negative guard of the overlap span
 *   浮点舍入可能让理论为零的交集算出极小的负值，一律钳到 0，
 *   保证下游可直接累加与比较，不必各自打补丁。
 *-----------------------------------------------------------------------------*)
IF fOverlapSpan < DL_SPAN_ZERO THEN        // 重叠长度出现负值（A negative span appeared）
    fOverlapSpan := DL_SPAN_ZERO;          // 钳到 0，维持非负承诺（Clamp to zero, keep the promise）
END_IF
END_FUNCTION
