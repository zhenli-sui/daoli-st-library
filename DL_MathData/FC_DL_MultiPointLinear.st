(*==============================================================================
 * 组件名称 (Component)  : FC_DL_MultiPointLinear
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS），全 LREAL 运算，无状态
 * 功能描述 (Function)   : N 段折线查表线性插值（N = 2..16）。用于热电偶、异形卧式罐液位、
 *                         流量计非线性修正、阀门特性补偿等"两点直线表达不了"的标定场景。
 *                         二分查找定位区间（O(log2 N)），输出命中段号与外推/钳位标志；
 *                         区间外默认钳位，显式关闭钳位才做端点段线性外推。
 *
 * 【失真与语义披露 / Distortion disclosure】
 *   1) 表非法（X 非严格递增）时整表作废，返回 afY[0]。这是刻意的"整体拒绝"：
 *      重复折点是除零的根因，若做"跳过坏点"的局部修补，会在现场产生一段斜率错误
 *      却看起来正常的插值，比直接报错危险得多。
 *   2) 非法表返回 afY[0] 而不是 0.0：0.0 在液位/温度场景会被当成真实测量值参与联锁，
 *      afY[0] 至少落在量程内，异常时工艺侧只会看到"读数不动"而不会看到"读数归零"。
 *   3) 外推在传感器断线时会把 0 mA 放大成负温度，因此默认钳位。要用外推必须显式
 *      把 bClamp 置 FALSE，并在设计文件中留档理由。
 *   4) 本函数不检测 NaN/Inf：IEC 61131-3 无标准判据，强行判断会引入编译器方言。
 *
 * 开源溯源 (Origin)     : 原创实现（参考西门子 LGF 定标族的"折线表 = X/Y 双数组 + 点数"
 *                         接口形态与 LBP 折线转换的粒度，clean-room 编写，未复制任何源码）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: ABS
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3（无指针、无厂商私有符号）
 *                         R4 ✓ 点数钳位 + 单调性全校验 + 二分防死锁 + 段宽二次判零
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无状态机）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 收口批次 · R3）
 *============================================================================*)
FUNCTION FC_DL_MultiPointLinear : LREAL
VAR_IN_OUT
    afX : ARRAY[0..15] OF LREAL;          // 折点自变量表，须严格递增（上限 16 点）/ Breakpoint X table, strictly increasing, max 16
    afY : ARRAY[0..15] OF LREAL;          // 折点因变量表 [EU]（上限 16 点）/ Breakpoint Y table [EU], max 16
END_VAR
VAR_INPUT
    fIn    : LREAL;                       // 输入值 [EU] / Input value [EU]
    nCount : INT;                         // 有效折点数，合法域 2..16 / Valid point count, 2..16
    bClamp : BOOL := TRUE;                // TRUE = 区间外钳位，FALSE = 线性外推 / TRUE = clamp, FALSE = extrapolate
END_VAR
VAR_OUTPUT
    nSegment      : INT;                  // 命中段号 0..nCount-2，-1 = 无效 / Segment index, -1 = invalid
    bExtrapolated : BOOL;                 // 本次结果来自外推 / Result comes from extrapolation
    bClamped      : BOOL;                 // 本次结果被钳位 / Result was clamped
    uErrorId      : UDINT;                // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    nLo      : INT;                       // 二分下界 / Binary search low bound
    nHi      : INT;                       // 二分上界 / Binary search high bound
    nMid     : INT;                       // 二分中点 / Binary search middle
    nGuard   : INT;                       // 二分防死锁计数器 / Binary search guard counter
    nIdx     : INT;                       // 单调性校验索引 / Monotonicity check index
    fX0      : LREAL;                     // 段左折点 X / Left breakpoint X
    fX1      : LREAL;                     // 段右折点 X / Right breakpoint X
    fY0      : LREAL;                     // 段左折点 Y [EU] / Left breakpoint Y [EU]
    fY1      : LREAL;                     // 段右折点 Y [EU] / Right breakpoint Y [EU]
    fSpan    : LREAL;                     // 段宽 fX1 - fX0 / Segment span
    fRatio   : LREAL;                     // 段内归一化位置，可越 0..1（外推时）/ Normalised position, may leave 0..1
    bTableOk : BOOL;                      // 表合法性标志 / Table validity flag
    bSearchOk: BOOL;                      // 二分收敛标志 / Binary search convergence flag
END_VAR
VAR CONSTANT
    DL_MPL_PTS_MIN : INT   := 2;          // 最少折点数 / Minimum point count
    DL_MPL_PTS_MAX : INT   := 16;         // 最多折点数，等于数组维度 / Maximum point count, equals the array size
    DL_MPL_EPS     : LREAL := 1.0E-9;     // 折点严格递增容差 / Strict-increase tolerance
    DL_MPL_GUARD   : INT   := 8;          // 二分最大迭代次数，log2(16)=4 留一倍余 / Max binary iterations
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置：返回值先落到表首值，异常路径不引入"0 值"这种伪测量
 *      Safe preset: default to the first table value, never to a fake zero
 *-----------------------------------------------------------------------------*)
FC_DL_MultiPointLinear := afY[0];
nSegment               := -1;
bExtrapolated          := FALSE;
bClamped               := FALSE;
uErrorId               := 16#0000_0000;
bTableOk               := TRUE;
bSearchOk              := TRUE;

(*------------------------------------------------------------------------------
 * 段 2｜点数校验（边界 B6）：先卡死点数，后面所有循环与索引才有定义域
 *      Point-count check first, so every later loop and index is well defined
 *-----------------------------------------------------------------------------*)
IF (nCount < DL_MPL_PTS_MIN) OR (nCount > DL_MPL_PTS_MAX) THEN
    uErrorId := 16#0001_0001;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜单调性全校验（边界 B1）：整表拒绝，不做局部修补
 *      Whole-table monotonicity check: reject the whole table, never patch a bad point
 *-----------------------------------------------------------------------------*)
FOR nIdx := 1 TO (nCount - 1) DO
    IF (afX[nIdx] - afX[nIdx - 1]) <= DL_MPL_EPS THEN
        bTableOk := FALSE;
    END_IF
END_FOR

IF NOT bTableOk THEN
    uErrorId := 16#0002_000B;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜区间外处理（边界 B3）：钳位优先，外推必须显式关闭
 *      Out-of-range handling: clamping wins, extrapolation must be opted in
 *-----------------------------------------------------------------------------*)
IF (fIn < afX[0]) AND bClamp THEN
    FC_DL_MultiPointLinear := afY[0];
    nSegment               := 0;
    bClamped               := TRUE;
    RETURN;
END_IF

IF (fIn > afX[nCount - 1]) AND bClamp THEN
    FC_DL_MultiPointLinear := afY[nCount - 1];
    nSegment               := (nCount - 2);
    bClamped               := TRUE;
    RETURN;
END_IF

IF (fIn < afX[0]) OR (fIn > afX[nCount - 1]) THEN
    bExtrapolated := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜二分定位（边界 R4）：WHILE 必带防死锁计数器，超限强制收敛
 *      Binary search with a mandatory guard: over the limit it force-converges
 *      收敛判据是 nHi - nLo > 1，循环退出时必然 nLo ∈ 0..nCount-2，段号天然合法
 *-----------------------------------------------------------------------------*)
nLo := 0;
nHi := (nCount - 1);
nGuard := 0;

WHILE (nHi - nLo) > 1 DO

    nGuard := nGuard + 1;

    IF nGuard > DL_MPL_GUARD THEN
        (* 理论上不可达（4 次足够），纯防御：强制收敛并报保护触发 *)
        (* Unreachable in theory, pure defence: force convergence and report *)
        bSearchOk := FALSE;
        nHi       := (nLo + 1);
    ELSE
        nMid := (nLo + nHi) / 2;
        IF fIn >= afX[nMid] THEN
            nLo := nMid;
        ELSE
            nHi := nMid;
        END_IF
    END_IF

END_WHILE

IF NOT bSearchOk THEN
    uErrorId := 16#0001_0004;
END_IF

nSegment := nLo;

(*------------------------------------------------------------------------------
 * 段 6｜段内线性插值（边界 B4）：单调性已保证段宽 > EPS，这里仍再判一次
 *      Segment interpolation: the span is checked again, the table may be rewritten outside
 *      fIn 恰好等于折点时 fRatio = 1.0，结果等于该折点 Y，无跳变（边界 B5）
 *-----------------------------------------------------------------------------*)
fX0 := afX[nLo];
fX1 := afX[nLo + 1];
fY0 := afY[nLo];
fY1 := afY[nLo + 1];
fSpan := fX1 - fX0;

IF ABS(fSpan) > DL_MPL_EPS THEN
    fRatio := (fIn - fX0) / fSpan;
    FC_DL_MultiPointLinear := fY0 + fRatio * (fY1 - fY0);
ELSE
    (* 表在两次校验之间被外部改写：退回左折点值并报表非法 *)
    (* The table was rewritten between the checks: fall back to the left point *)
    FC_DL_MultiPointLinear := fY0;
    nSegment               := -1;
    uErrorId               := 16#0002_000B;
END_IF
END_FUNCTION
