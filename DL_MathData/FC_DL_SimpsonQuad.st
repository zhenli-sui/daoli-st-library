(*==============================================================================
 * 组件名称 (Component)  : FC_DL_SimpsonQuad
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（LOWER_BOUND / UPPER_BOUND / MOD），零厂商私有库
 * 功能描述 (Function)   : 复合辛普森 1/3 数值积分原语：对 n+1 个等距节点纵坐标（n 为偶数，
 *                         即节点数 >= 3 且区间数为偶）按公式
 *                           fI = fDx/3 × (aY[0] + 4×Σ奇节点 + 2×Σ偶内点 + aY[n])
 *                         单遍求积，返回积分值。适用功率-时间曲线求能、流量累计复核等
 *                         叶子级数值积分场景。
 * 接口     (Interface)  : 输入 aY 等距节点纵坐标数组（变长数组，按引传）、fDx 节点步长；
 *                         引用输出 bValid 有效标志（REFERENCE TO BOOL，当拍写回）；
 *                         返回值 = 积分值（bValid=FALSE 时返回 0）。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做一次静态数组求积，不采样、不缓存、
 *                         不做时间触发**；采样与节点装载由调用方负责。
 *                         ② 奇偶判据用整数 MOD 2，禁浮点判奇偶。
 *                         ③ 拒算条件（任一成立返回 0 且 bValid=FALSE）：区间数 < 2（节点数
 *                         < 3）、区间数为奇数、fDx <= 容差、任一节点纵坐标非有限
 *                         （NaN 用自不等 x<>x 口径、Inf 用 (x-x)<>0 口径，R245）。
 *                         非有限值逐点前置剔除并**整体拒算**：部分积分结果不可信。
 *                         ④ 等距性由调用方保证（IN 语义声明）：本件不做步长一致性校验，
 *                         fDx 取相邻节点间距的名义值。
 *                         ⑤ 变长数组仅入 VAR_IN_OUT（IEC 61131-3 第 3 版对 ARRAY[*] 的
 *                         传参域限定），LOWER_BOUND/UPPER_BOUND 取实际上下界，不假设 0 起始。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_PolyEvalHorner` 分工：多项式求值 ≠ 数值求积；与
 *                         `FC_DL_MultiPointLinear` 分工：分段线性插值 ≠ 积分。全库数值
 *                         积分原语由本件开族。
 * 来源标签 (Source Tag) : T2-1 LGF · Math 数学子族（公开数学定义 clean-room，复合辛普森
 *                         1/3 法则为教科书公开公式，零代码行复制）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 积分值 + BOOL 有效标志；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 步长容差闸 + 非有限前置剔除 + 奇偶整数判据 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R48 首版（批次 1 · 序号 2）
 *                         验收向量：3 节点 y=[0,1,0]、dx=1 → 4/3；4 节点（奇区间数）拒算；
 *                         含 NaN 节点整体拒算；dx=0 拒算。
 *==============================================================================*)

FUNCTION FC_DL_SimpsonQuad : LREAL
VAR_IN_OUT
    aY : ARRAY[*] OF LREAL;    // 等距节点纵坐标数组（长度 n+1，n 偶），单位随被积量 [被积量纲] / Ordinates at equidistant nodes
END_VAR
VAR_INPUT
    fDx    : LREAL;                 // 节点步长，域 > 容差；等距性由调用方保证（IN 语义） [横轴单位] / Node spacing, > epsilon, uniformity by caller
    bValid : REFERENCE TO BOOL;     // 有效标志（引用传参；FALSE=拒算） [-] / Validity flag, by-reference, FALSE when rejected
END_VAR
VAR
    nLo  : DINT;                    // 数组实际下界索引 / Actual lower array index
    nHi  : DINT;                    // 数组实际上界索引 / Actual upper array index
    nInt : DINT;                    // 区间数 = 节点数 - 1，须为正偶数 / Interval count, positive even
    i    : DINT;                    // 求和循环索引 / Summation loop index
    fSum : LREAL;                   // 括号内加权和中间量 / Weighted sum accumulator
END_VAR
VAR CONSTANT
    DL_SQ_EPS : LREAL := 1.0E-12;   // 步长判零容差 [横轴单位] / Spacing zero epsilon
    DL_SQ_W4  : LREAL := 4.0;       // 辛普森奇节点权重 [-] / Simpson odd-node weight
    DL_SQ_W2  : LREAL := 2.0;       // 辛普森偶内点权重 [-] / Simpson even-interior weight
    DL_SQ_W3  : LREAL := 3.0;       // 1/3 法则除数 [-] / Divisor of the one-third rule
END_VAR

bValid := FALSE;                                       // 缺省拒算 / Default: invalid
FC_DL_SimpsonQuad := 0.0;                              // 拒算返回 0 / Rejected returns zero
nLo  := LOWER_BOUND(aY, 1);                            // 取实际下界，不假设 0 起始 / Actual lower bound, no zero assumption
nHi  := UPPER_BOUND(aY, 1);                            // 取实际上界 / Actual upper bound
nInt := nHi - nLo;                                     // 区间数 / Interval count
IF (nInt < 2) OR ((nInt MOD 2) <> 0) OR (fDx <= DL_SQ_EPS) THEN
    RETURN;                                            // 区间数不足 / 奇区间数 / 步长非正：拒算（整数奇偶判据）/ Too few or odd intervals or bad spacing: reject
END_IF
FOR i := nLo TO nHi DO
    IF (aY[i] <> aY[i]) OR ((aY[i] - aY[i]) <> 0.0) THEN
        RETURN;                                        // 任一节点非有限（NaN 自不等 / Inf 差非零）：整体拒算（R245）/ Any non-finite node: reject wholly
    END_IF
END_FOR

fSum := aY[nLo] + aY[nHi];                             // 两端节点权重 1 / End nodes carry weight one
FOR i := (nLo + 1) TO (nHi - 1) DO
    IF ((i - nLo) MOD 2) <> 0 THEN
        fSum := fSum + DL_SQ_W4 * aY[i];               // 奇节点权重 4 / Odd nodes weight four
    ELSE
        fSum := fSum + DL_SQ_W2 * aY[i];               // 偶内点权重 2 / Even interior nodes weight two
    END_IF
END_FOR

FC_DL_SimpsonQuad := fSum * fDx / DL_SQ_W3;            // 除数为常量 3，无除零 / Constant divisor three, no zero division
bValid := TRUE;                                        // 求积有效 / Result valid

END_FUNCTION
