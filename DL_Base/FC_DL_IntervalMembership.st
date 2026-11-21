(*==============================================================================
 * 组件名称 (Component)  : FC_DL_IntervalMembership
 * 所属子库 (Sublibrary) : DL_Base
 * 归属目录 (Directory)  : C:\Library\DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 函数（FUNCTION）· 纯函数 · 开闭区间归属判定
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 ABS / MIN，
 *                         无厂商扩展，无实例依赖
 * 功能一句话 (Summary)  : 判定一个实数是否落在指定开闭组合的区间内，并给出到
 *                         最近边界的有符号裕量与恰在边界标志。
 * 功能描述 (Function)   : 工艺窗口有大量半开约定，例如温度 60 到 80 左闭右开、
 *                         压力 0.4 到 0.6 左开右闭。本件把「开闭组合」做成独立
 *                         参数，四种组合各走一条判定支路，边界归属不再靠调用方
 *                         记忆，同一产线各工位判定口径由此统一。
 * 与既有件边界 (Boundary): FC_DL_ToleranceWindow 判单点对称公差带；FC_DL_LimitClassify
 *                         做四阈值五档分级；FC_DL_RangeOverlapCheck 判两个区间的关系。
 *                         本件判「单点与一端点开闭组合区间」的归属，与三者正交。
 * 设计要点 (Key notes)  : ① 有限性前置拦截：非数与非有限值直接判不可信，绝不进入
 *                           比较链（非数参与比较恒为假，会静默判成「不在区间」）；
 *                         ② 端点序校验先于一切比较，倒置区间不返回「看似合理」的假；
 *                         ③ 边界容差双向使用：闭侧把贴近值纳入，开侧把贴近值排除，
 *                           同一容差保证「既报超限又报未到」的临界矛盾不再出现；
 *                         ④ 退化区间单列一条判据，只有双闭组合才含单点；
 *                         ⑤ 纯函数：无内部状态，同入参同结果，可重入。
 * 开源溯源 (Origin)     : 来源标签 lgf-comparator。LGF 为免费闭源发布的公开函数库
 *                         手册，本件仅借鉴其比较器组把「区间判断 / 公差窗口 / 限值」
 *                         三分的分类骨架，以及区间带开闭属性的参数域设计；许可证按
 *                         其发布方条款仅作分类参考，本件零代码行、零注释引用，
 *                         属 clean-room 独立实现。容差策略为本库加严项，LGF 无此概念。
 * 码位说明 (Codes)      : 本件独占信息级码段 16#0001_012B 到 16#0001_012C，纯函数
 *                         无锁存面故不占故障级码；与同族 0125 到 012A 相邻不重叠。
 *                         012B 端点倒置 ｜ 012C 非数或非有限值。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 ABS / MIN。
 * 红线自检 (Redline)    : 零全局变量表依赖 ｜ 零外部变量声明 ｜ 零物理地址
 *                         纯 IEC 61131-3 ｜ 无除法故无除零面 ｜ 全变量双语同行注释
 *                         状态机 N/A（纯函数）｜ 枚举四成员被分支全覆盖并带兜底
 * 修订历史 (Revision)   : 2026-11-15  v1.0.0  首版入库（Round 12 · 区间判定族）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_IntervalKind（归属 DL_Base，与 FC_DL_IntervalMembership 同文件）
 * 含义: 区间的端点开闭组合。编号 0 起跳、段间隔 10，便于后续插值而不破坏既有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_IntervalKind :
(
    eClosedClosed := 0,      // 双闭：两端点都计入，退化区间仅此组合包含单点 / Both ends included, only this kind contains a single point
    eClosedOpen   := 10,     // 左闭右开：含下限不含上限，工艺窗口最常见的写法 / Left closed right open, the most common process window
    eOpenClosed   := 20,     // 左开右闭：不含下限含上限 / Left open right closed
    eOpenOpen     := 30      // 双开：两端点都不计入，退化区间为空集 / Both ends excluded, a single point is never inside
);
END_TYPE

(*==============================================================================
 * 判定示意 (Membership picture)：
 *   区间 60 到 80，取值 60 时：左闭组合判在区间内且贴界，左开组合判不在区间内
 *   区间 60 到 80，取值 80 时：右闭组合判在区间内且贴界，右开组合判不在区间内
 *   裕量口径：内正外负，恰在边界为 0；取「到下限距离」与「到上限距离」的较小者
 *   退化区间（上下限相等）：只有双闭组合在贴界时判在区间内，其余三组合恒不在
 *============================================================================*)

(*==============================================================================
 * 逐调用推演 (Call trace)：
 *   调用 1  值 60、下限 60、上限 80、左闭右开
 *     有限性通过；端点有序通过；贴下限为真，贴上限为假
 *     闭侧判据与贴近合取后通过，开侧判据通过，判定在区间内
 *     裕量取 0 与 20 的较小者，得 0，边界标志为真
 *   调用 2  值 80、同区间
 *     贴上限为真；开侧判据为「严格小于且不贴近」，故不通过
 *     判定不在区间内，裕量为 0，边界标志为真（这是本件最重要的语义）
 *   调用 3  值 59.5、同区间
 *     闭侧判据：既不大于等于下限也不贴近，不通过；裕量取 -0.5 与 20.5 的较小者
 *     输出 -0.5，符号自然表达「低于下限」
 *   调用 4  下限 80、上限 60
 *     端点序校验成立（下限大于上限加容差），早退，事件码 012B，判不在区间内
 *============================================================================*)

FUNCTION FC_DL_IntervalMembership : BOOL
VAR_INPUT
    fValue : LREAL;                                             // 被判定值 [工程单位由调用方决定] / Value under test, unit defined by the caller
    fLower : LREAL;                                             // 区间下限 [工程单位由调用方决定] / Lower bound, unit defined by the caller
    fUpper : LREAL;                                             // 区间上限 [工程单位由调用方决定] / Upper bound, unit defined by the caller
    eKind  : E_DL_IntervalKind := E_DL_IntervalKind.eClosedOpen; // 开闭组合，默认左闭右开 / Openness combination, left closed right open by default
    fEps   : LREAL := 1.0E-9;                                   // 边界判定容差，非正时按最小值生效 [工程单位由调用方决定] / Boundary tolerance, non positive falls back to the minimum
END_VAR
VAR_OUTPUT
    bInside     : BOOL;                                         // 落在区间内为真 / Inside the interval
    bOnBoundary : BOOL;                                         // 与某端点距离小于容差为真 / Within tolerance of an endpoint
    fMargin     : LREAL;                                        // 到最近边界的有符号裕量，内正外负，临界为零 [工程单位由调用方决定] / Signed margin to the nearest bound
    uErrorId    : UDINT;                                        // 事件码，0 表示无事件 / Event code, zero means none
    bValid      : BOOL;                                         // 端点有序且三值有限为真 / Bounds ordered and all values finite
END_VAR
VAR
    fEpsUse     : LREAL;                                        // 生效容差，非正输入已回退到最小值 [工程单位由调用方决定] / Effective tolerance after the fallback
    bNearLo     : BOOL;                                         // 贴近下限 / Near the lower bound
    bNearUp     : BOOL;                                         // 贴近上限 / Near the upper bound
    bLoOk       : BOOL;                                         // 下界侧通过 / Lower side passes
    bUpOk       : BOOL;                                         // 上界侧通过 / Upper side passes
    bDegenerate : BOOL;                                         // 退化区间标志，两端点距离小于容差 / Degenerate interval flag
END_VAR
VAR CONSTANT
    DL_EPS_MIN    : LREAL := 1.0E-9;    // 最小容差，容差为零时浮点永不相等故须回退 [工程单位由调用方决定] / Minimum tolerance used when the caller passes zero
    DL_FINITE_MAX : LREAL := 3.4E38;    // 有限性判定上限，超过即视为无穷大 [工程单位由调用方决定] / Finiteness ceiling, beyond this the value counts as infinite
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出预置：任何异常路径下输出确定
 *      Pre-set outputs so that every path is deterministic
 *-----------------------------------------------------------------------------*)
FC_DL_IntervalMembership := FALSE;
bInside                  := FALSE;
bOnBoundary              := FALSE;
fMargin                  := 0.0;
uErrorId                 := 16#0000_0000;
bValid                   := FALSE;

(*------------------------------------------------------------------------------
 * 段 2｜容差归一（边界 B1）：非正容差回退到最小值
 *      Normalise the tolerance: non positive input falls back to the minimum
 *      容差为零时「贴近」判据恒假，闭侧容差与开侧容差同时失效，须显式回退
 *-----------------------------------------------------------------------------*)
fEpsUse := fEps;
IF fEpsUse <= 0.0 THEN
    fEpsUse := DL_EPS_MIN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜有限性前置拦截（边界 B2）：非数与无穷大一律判不可信
 *      Non finite interception: NaN and infinity never enter the comparison chain
 *      非数判定用自比较，跨平台一致，不依赖平台扩展函数
 *-----------------------------------------------------------------------------*)
IF (fValue <> fValue) OR (fLower <> fLower) OR (fUpper <> fUpper) THEN
    uErrorId := 16#0001_012C;   // 非数值输入，判定不可信
    RETURN;
END_IF
IF (ABS(fValue) > DL_FINITE_MAX) OR (ABS(fLower) > DL_FINITE_MAX) OR (ABS(fUpper) > DL_FINITE_MAX) THEN
    uErrorId := 16#0001_012C;   // 非有限输入，判定不可信
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜端点序校验（边界 B3）：倒置区间不返回看似合理的假结果
 *      Endpoint order check: an inverted interval is reported, never guessed
 *-----------------------------------------------------------------------------*)
IF fLower > (fUpper + fEpsUse) THEN
    uErrorId := 16#0001_012B;   // 端点倒置，判不在区间内
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜边界贴近与退化判定（边界 B4）
 *      Boundary proximity and degeneracy detection
 *-----------------------------------------------------------------------------*)
bNearLo     := ABS(fValue - fLower) < fEpsUse;
bNearUp     := ABS(fValue - fUpper) < fEpsUse;
bOnBoundary := bNearLo OR bNearUp;
bDegenerate := ABS(fUpper - fLower) < fEpsUse;

(*------------------------------------------------------------------------------
 * 段 6｜按开闭组合分派四侧判据（红线：枚举四成员全覆盖并带兜底）
 *      Dispatch the two side checks by the openness combination
 *      闭侧把贴近值纳入，开侧把贴近值排除，同一容差双向使用
 *-----------------------------------------------------------------------------*)
CASE eKind OF

    E_DL_IntervalKind.eClosedClosed:
        bLoOk := (fValue >= fLower) OR bNearLo;
        bUpOk := (fValue <= fUpper) OR bNearUp;

    E_DL_IntervalKind.eClosedOpen:
        bLoOk := (fValue >= fLower) OR bNearLo;
        bUpOk := (fValue < fUpper) AND (NOT bNearUp);

    E_DL_IntervalKind.eOpenClosed:
        bLoOk := (fValue > fLower) AND (NOT bNearLo);
        bUpOk := (fValue <= fUpper) OR bNearUp;

    E_DL_IntervalKind.eOpenOpen:
        bLoOk := (fValue > fLower) AND (NOT bNearLo);
        bUpOk := (fValue < fUpper) AND (NOT bNearUp);

    ELSE
        (* 非法枚举值：不做隐式恢复，判不可信并置兜底码 *)
        (* Illegal enumerator: no implicit recovery, report and stay outside *)
        bLoOk    := FALSE;
        bUpOk    := FALSE;
        uErrorId := 16#0001_012C;
        RETURN;

END_CASE

(*------------------------------------------------------------------------------
 * 段 7｜归属合成（边界 B5）：退化区间只被双闭组合包含
 *      Membership composition: only the doubly closed kind contains a point
 *-----------------------------------------------------------------------------*)
IF bDegenerate THEN
    bInside := (eKind = E_DL_IntervalKind.eClosedClosed) AND bOnBoundary;
ELSE
    bInside := bLoOk AND bUpOk;
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜裕量（边界 B6）：取两侧距离的较小者，外侧自然为负
 *      Margin: the smaller of the two distances, negative outside by nature
 *-----------------------------------------------------------------------------*)
fMargin := MIN(fValue - fLower, fUpper - fValue);

(*------------------------------------------------------------------------------
 * 段 9｜收口：走到此处入参全部合法
 *      Close out: reaching this point means every input is legal
 *-----------------------------------------------------------------------------*)
bValid                   := TRUE;
FC_DL_IntervalMembership := bInside;
END_FUNCTION
