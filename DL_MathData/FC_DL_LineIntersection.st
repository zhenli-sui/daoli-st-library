(*==============================================================================
 * 组件名称 (Component)  : FC_DL_LineIntersection
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS），全 LREAL 运算，无状态
 * 功能描述 (Function)   : 二维两直线（或两线段）交点求解。返回"是否存在唯一交点"的布尔量，
 *                         交点坐标与两个线段参数经状态输出给出，双通道并存的目的是让调用方
 *                         既能直接用作条件判断，也能拿到参数做端点命中判据。
 *                         用于视觉十字标定、皮带跑偏中心线求交、两台相机视场交叠区定位、
 *                         机器人平面两轴交汇点计算。
 *
 * 【失真与语义披露 / Distortion disclosure】
 *   1) 线段模式返回 FALSE 时 uErrorId = 0：业务上的"两段不相交"是正常判定结果，
 *      不是故障。若也置故障码，上位机会把正常判定当异常刷屏，真正的配置错误就被淹了。
 *   2) 重合直线归入平行类（16#0002_000D）：无穷多交点无法用单一坐标表达，
 *      与其随机给一个点，不如明确说"没有唯一交点"。线段模式下"平行且不共线"的两段
 *      永远不可能相交，属于正常业务判定，返回 FALSE 且不置码；只有重合（共线）才报码。
 *   3) 平行判据用绝对容差，而坐标量级到 1e6 时行列式 fDen 可到 1e12，因此 fEps 必须
 *      按坐标量级配置，经验式 fEps ≈ 1e-9 × 坐标量级²。用 1e-9 去判 1e12 量级的行列式，
 *      等于把平行判据关掉了。
 *   4) 本函数不检测 NaN/Inf：IEC 61131-3 无标准判据，强行判断会引入编译器方言。
 *
 * 开源溯源 (Origin)     : 原创实现（参考西门子 LGF 数学功能组中平面几何族的分类位置，
 *                         解析几何求交为公开数学方法，clean-room 独立实现）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: ABS
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3（无指针、无厂商私有符号）
 *                         R4 ✓ 零长度线判据 + 容差规整 + 行列式判零 + 无交点显式清 0
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无状态机）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 收口批次 · R3）
 *============================================================================*)
FUNCTION FC_DL_LineIntersection : BOOL
VAR_INPUT
    fX1         : LREAL;                  // 线 1 起点 X [mm] / Line 1 start X [mm]
    fY1         : LREAL;                  // 线 1 起点 Y [mm] / Line 1 start Y [mm]
    fX2         : LREAL;                  // 线 1 终点 X [mm] / Line 1 end X [mm]
    fY2         : LREAL;                  // 线 1 终点 Y [mm] / Line 1 end Y [mm]
    fX3         : LREAL;                  // 线 2 起点 X [mm] / Line 2 start X [mm]
    fY3         : LREAL;                  // 线 2 起点 Y [mm] / Line 2 start Y [mm]
    fX4         : LREAL;                  // 线 2 终点 X [mm] / Line 2 end X [mm]
    fY4         : LREAL;                  // 线 2 终点 Y [mm] / Line 2 end Y [mm]
    fEps        : LREAL := 1.0E-9;        // 平行判定容差（须按坐标量级配置）/ Parallel tolerance, scale with the coordinate range
    bSegmentMode: BOOL := FALSE;          // TRUE = 按线段求交，交点须落在两段内 / TRUE = segment mode
END_VAR
VAR_OUTPUT
    fX       : LREAL;                     // 交点 X [mm]，无交点时为 0 / Intersection X [mm], 0 when none
    fY       : LREAL;                     // 交点 Y [mm]，无交点时为 0 / Intersection Y [mm], 0 when none
    fT       : LREAL;                     // 线 1 参数 t，0 = 起点、1 = 终点 / Parameter along line 1
    fU       : LREAL;                     // 线 2 参数 u，0 = 起点、1 = 终点 / Parameter along line 2
    uErrorId : UDINT;                     // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fDen  : LREAL;                        // 行列式分母 / Determinant denominator
    fDx1  : LREAL;                        // 线 1 方向 X 分量 [mm] / Line 1 direction X [mm]
    fDy1  : LREAL;                        // 线 1 方向 Y 分量 [mm] / Line 1 direction Y [mm]
    fDx2  : LREAL;                        // 线 2 方向 X 分量 [mm] / Line 2 direction X [mm]
    fDy2  : LREAL;                        // 线 2 方向 Y 分量 [mm] / Line 2 direction Y [mm]
    fEpsEff : LREAL;                      // 规整后的容差 / Normalised tolerance
    fTol  : LREAL;                        // 线段模式的参数区间容差 / Parameter tolerance in segment mode
    fNumT : LREAL;                        // t 的分子 / Numerator of t
    fNumU : LREAL;                        // u 的分子 / Numerator of u
    bLineDegenerate : BOOL;               // 任一线退化为点（起终点重合）/ Either line degenerated to a point
    bCoincident : BOOL;                   // 两线共线（重合），平行判定后的细分 / The two lines are coincident
END_VAR
VAR CONSTANT
    DL_LI_DEADBAND : LREAL := 1.0E-6;     // 零长度线判定容差 [mm] / Zero-length line tolerance [mm]
    DL_LI_EPS_MIN  : LREAL := 1.0E-12;    // 容差下限，防止把容差填成 0 / Tolerance floor
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置（边界 B6）：无交点时输出必须显式清 0，禁止依赖"局部变量默认值"
 *      Safe preset: outputs are explicitly zeroed, local defaults are never trusted
 *      部分平台的 FC 局部变量不保证每拍复位，靠默认值会让上一次的交点粘住
 *-----------------------------------------------------------------------------*)
FC_DL_LineIntersection := FALSE;
fX       := 0.0;
fY       := 0.0;
fT       := 0.0;
fU       := 0.0;
uErrorId := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 2｜退化线检测（边界 B2）：起点终点重合/填反是最常见的标定配置错误，必须报码
 *      Degenerate-line check: start equal to end is the most common calibration mistake
 *      用曼哈顿距离判零长度：比平方和开方便宜，且对 LREAL 无溢出风险
 *-----------------------------------------------------------------------------*)
bLineDegenerate := ((ABS(fX2 - fX1) + ABS(fY2 - fY1)) <= DL_LI_DEADBAND)
                   OR ((ABS(fX4 - fX3) + ABS(fY4 - fY3)) <= DL_LI_DEADBAND);

IF bLineDegenerate THEN
    uErrorId := 16#0001_0001;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜容差规整（边界 B1）：容差不能为 0 或负，否则平行判据失效
 *      Tolerance normalisation: zero or negative would disable the parallel test
 *-----------------------------------------------------------------------------*)
fEpsEff := fEps;

IF fEpsEff <= 0.0 THEN
    fEpsEff  := 1.0E-9;
    uErrorId := 16#0001_0001;
END_IF

IF fEpsEff < DL_LI_EPS_MIN THEN
    fEpsEff := DL_LI_EPS_MIN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜方向向量与行列式（边界 B5）：分母只算一次，两条参数方程共用
 *      Direction vectors and determinant, computed once for both parametric equations
 *-----------------------------------------------------------------------------*)
fDx1 := fX2 - fX1;
fDy1 := fY2 - fY1;
fDx2 := fX4 - fX3;
fDy2 := fY4 - fY3;

fDen := (fDx1 * fDy2) - (fDy1 * fDx2);

(*------------------------------------------------------------------------------
 * 段 5｜平行/重合判定（边界 B3/B4）：无唯一交点
 *      Parallel or coincident: no unique intersection
 *      线段模式下"平行且不共线"的两段永远不相交，属正常业务判定，不置故障码；
 *      重合则有无穷多交点，仍是配置/数据问题，必须报码
 *      In segment mode, parallel non-collinear segments are a normal verdict, not a fault
 *-----------------------------------------------------------------------------*)
IF ABS(fDen) <= fEpsEff THEN

    bCoincident := (ABS(((fX3 - fX1) * fDy1) - ((fY3 - fY1) * fDx1)) <= fEpsEff);

    IF bSegmentMode AND (NOT bCoincident) THEN
        RETURN;
    END_IF

    uErrorId := 16#0002_000D;
    RETURN;

END_IF

(*------------------------------------------------------------------------------
 * 段 6｜参数求解：克拉默法则，分母在段 5 已判非零
 *      Parameter solution by Cramer's rule, the denominator was proven non-zero
 *-----------------------------------------------------------------------------*)
fNumT := (((fX3 - fX1) * fDy2) - ((fY3 - fY1) * fDx2));
fNumU := (((fX3 - fX1) * fDy1) - ((fY3 - fY1) * fDx1));

fT := fNumT / fDen;
fU := fNumU / fDen;

(*------------------------------------------------------------------------------
 * 段 7｜线段模式判定（边界 B3）：交点须落在两段的参数区间内
 *      Segment mode: the intersection must lie inside both parameter ranges
 *      端点命中算相交（容差取 fEpsEff 量级），否则相邻两段共端点时会被判成"不相交"；
 *      判定失败时 fT / fU 保留实际参数，便于上位机判断"差多远"，但坐标清 0
 *-----------------------------------------------------------------------------*)
IF bSegmentMode THEN

    fTol := fEpsEff;

    IF (fT < (0.0 - fTol)) OR (fT > (1.0 + fTol)) THEN
        (* 业务判定，不置故障码：线段不相交是正常结果 *)
        (* A business verdict, not a fault: disjoint segments are perfectly normal *)
        RETURN;
    END_IF

    IF (fU < (0.0 - fTol)) OR (fU > (1.0 + fTol)) THEN
        RETURN;
    END_IF

END_IF

(*------------------------------------------------------------------------------
 * 段 8｜交点求值（边界 B5）：一律由线 1 参数化，两式取平均会多引入一次误差
 *      Evaluate with line 1 only: averaging both equations adds error instead of removing it
 *-----------------------------------------------------------------------------*)
fX := fX1 + (fT * fDx1);
fY := fY1 + (fT * fDy1);

FC_DL_LineIntersection := TRUE;
END_FUNCTION
