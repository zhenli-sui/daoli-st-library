(*==============================================================================
 * 组件名称 (Component)  : FC_DL_LagrangeInterp
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（LOWER_BOUND / UPPER_BOUND / ABS），零厂商私有库
 * 功能描述 (Function)   : 小样本拉格朗日插值原语：对 2 ≤ n ≤ 8 个散点 (aX[i], aY[i])，
 *                         以拉格朗日基函数求单点插值
 *                           fYq = Σ_i aY[i] × Π_{j≠i} (fXq - aX[j]) / (aX[i] - aX[j])
 *                         适用 2~8 点传感器标定曲线（如 NTC 温度、压力标定）的非线性插值。
 * 接口     (Interface)  : 输入 aX 横坐标数组（变长数组，按引传）、aY 纵坐标数组（变长数组，
 *                         按引传）、fXq 查询横坐标；引用输出 bValid 有效标志
 *                         （REFERENCE TO BOOL，当拍写回）；返回值 = 插值结果
 *                         （bValid=FALSE 时返回 0）。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做一次静态散点求值，不装载标定表、
 *                         不缓存系数、不做外推告警**；标定表管理由调用方负责。
 *                         ② 拒算条件（任一成立返回 0 且 bValid=FALSE）：点数 < 2、两数组
 *                         长度不一致、fXq 非有限、任一点非有限（NaN 自不等 x<>x、Inf 用
 *                         (x-x)<>0 口径）、查重节点（ABS(aX[i]-aX[j]) < 节点容差，分母趋零，
 *                         浮点禁 = 判等，R28）。
 *                         ③ 点数超上限（8）按**截断语义**处理：只取前 8 点求值并在
 *                         bValid=TRUE 下照常返回，截断行为写死于此，调用方按需自校点数。
 *                         ④ 节点容差提为 VAR CONSTANT（禁魔法数）；无样条连续性要求的小
 *                         样本域适用，需要 C2 连续时改用 `FC_DL_CubicSplineInterp`。
 *                         ⑤ 变长数组仅入 VAR_IN_OUT（ARRAY[*] 传参域限定），实际上下界由
 *                         LOWER_BOUND/UPPER_BOUND 取得，不假设 0 起始。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_CubicSplineInterp` 分工：无样条连续性要求的小样本多项式
 *                         插值（本件）≠ 三次样条 C2 连续插值（那件），实现独立不复制；
 *                         与 `FC_DL_MultiPointLinear` 分工：多项式过点 ≠ 分段线性。
 * 来源标签 (Source Tag) : T2-1 LGF · Math 数学子族（公开数学定义 clean-room，拉格朗日
 *                         基函数为教科书公开公式，零代码行复制）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 插值 + BOOL 有效标志；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 节点容差查重 + 非有限前置剔除 + 点数上限钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R48 首版（批次 1 · 序号 3）
 *                         验收向量：2 点线性退化为直线；3 点过三抛物线；重节点拒算；
 *                         9 点输入按前 8 点截断求值。
 *==============================================================================*)

FUNCTION FC_DL_LagrangeInterp : LREAL
VAR_IN_OUT
    aX : ARRAY[*] OF LREAL;    // 节点横坐标数组（散点，须互异），单位随横轴 [横轴单位] / Node abscissae, distinct
    aY : ARRAY[*] OF LREAL;    // 节点纵坐标数组，单位随纵轴 [纵轴单位] / Node ordinates
END_VAR
VAR_INPUT
    fXq    : LREAL;                 // 查询横坐标（允许落在节点域外，外推不告警） [横轴单位] / Query abscissa, extrapolation allowed
    bValid : REFERENCE TO BOOL;     // 有效标志（引用传参；FALSE=拒算） [-] / Validity flag, by-reference, FALSE when rejected
END_VAR
VAR
    nLo    : DINT;                  // aX 数组实际下界索引 / Lower index of aX
    nHiX   : DINT;                  // aX 数组实际上界索引 / Upper index of aX
    nHiY   : DINT;                  // aY 数组实际上界索引 / Upper index of aY
    nCount : DINT;                  // 有效点数（截断后）/ Effective point count after truncation
    i      : DINT;                  // 基函数外层循环索引 / Outer basis loop index
    j      : DINT;                  // 基函数内层循环索引 / Inner basis loop index
    fYq    : LREAL;                 // 插值累加中间量 [纵轴单位] / Interpolation accumulator
    fTerm  : LREAL;                 // 单项基函数乘积中间量 [纵轴单位] / Single basis product term
END_VAR
VAR CONSTANT
    DL_LI_NMAX : DINT  := 8;        // 点数上限（2~8 小样本域） [点] / Point-count ceiling
    DL_LI_TOL  : LREAL := 1.0E-9;   // 查重节点容差（分母趋零闸） [横轴单位] / Duplicate-node tolerance
    DL_LI_EPS  : LREAL := 0.0;      // 非有限差值判零基准 [横轴单位] / Non-finite difference zero base
END_VAR

bValid := FALSE;                                       // 缺省拒算 / Default: invalid
FC_DL_LagrangeInterp := 0.0;                           // 拒算返回 0 / Rejected returns zero
nLo    := LOWER_BOUND(aX, 1);                          // aX 实际下界 / Actual lower bound of aX
nHiX   := UPPER_BOUND(aX, 1);                          // aX 实际上界 / Actual upper bound of aX
nHiY   := UPPER_BOUND(aY, 1);                          // aY 实际上界 / Actual upper bound of aY
IF (nHiX - nLo) <> (nHiY - LOWER_BOUND(aY, 1)) THEN
    RETURN;                                            // 两数组长度不一致：拒算 / Length mismatch: reject
END_IF
nCount := nHiX - nLo + 1;                              // 原始点数 / Raw point count
IF (fXq <> fXq) OR ((fXq - fXq) <> DL_LI_EPS) THEN
    RETURN;                                            // 查询值非有限（NaN/Inf）：拒算 / Non-finite query: reject
END_IF
IF nCount < 2 THEN
    RETURN;                                            // 点数不足 2：拒算 / Fewer than two points: reject
END_IF
IF nCount > DL_LI_NMAX THEN
    nCount := DL_LI_NMAX;                              // 超上限截断语义：只取前 8 点（声明于头注释③） / Truncate to ceiling per header clause 3
END_IF
nHiX := nLo + nCount - 1;                              // 截断后有效上界 / Effective upper bound after truncation

FOR i := nLo TO nHiX DO
    IF (aX[i] <> aX[i]) OR ((aX[i] - aX[i]) <> DL_LI_EPS)
       OR (aY[i] <> aY[i]) OR ((aY[i] - aY[i]) <> DL_LI_EPS) THEN
        RETURN;                                        // 任一点非有限：整体拒算（R245）/ Any non-finite point: reject wholly
    END_IF
END_FOR
FOR i := nLo TO (nHiX - 1) DO
    FOR j := (i + 1) TO nHiX DO
        IF ABS(aX[i] - aX[j]) < DL_LI_TOL THEN
            RETURN;                                    // 查重节点命中（分母趋零）：拒算（R28 浮点禁 =）/ Duplicate nodes: reject
        END_IF
    END_FOR
END_FOR

fYq := 0.0;                                            // 插值累加器清零 / Clear accumulator
FOR i := nLo TO nHiX DO
    fTerm := aY[i];                                    // 单项从纵坐标出发 / Term starts from ordinate
    FOR j := nLo TO nHiX DO
        IF j <> i THEN
            fTerm := fTerm * (fXq - aX[j]) / (aX[i] - aX[j]);   // 基函数因子（分母已过查重闸）/ Basis factor, denominator gate-passed
        END_IF
    END_FOR
    fYq := fYq + fTerm;                                // 累加单项 / Accumulate term
END_FOR

FC_DL_LagrangeInterp := fYq;                           // 返回插值结果 / Return interpolated value
bValid := TRUE;                                        // 求值有效 / Result valid

END_FUNCTION
