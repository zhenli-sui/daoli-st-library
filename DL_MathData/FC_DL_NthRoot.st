(*==============================================================================
 * 组件名称 (Component)  : FC_DL_NthRoot
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 函数（FUNCTION）· 纯函数 · N 次方根（奇偶次分治）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅用 Standard.library 的 EXP / LN /
 *                         SQRT / ABS，无任何厂商私有数学库锁定
 * 功能描述 (Function)   : 计算 x 的 n 次方根（x 的 1 除以 n 次幂）。标准库只有
 *                         SQRT（二次方根），本件补齐任意次根，覆盖几何平均、
 *                         等效值折算、按幂律反算（泵与风机相似定律反算转速比、
 *                         面积等效直径、均方根到峰值折算）等场景。
 * 与既有件边界 (Boundary): 本库无同类件；FC_DL_LinearScale 与
 *                         FC_DL_MultiPointLinear 是线性与折线映射，与幂运算
 *                         无语义交集，不得互相替代。
 * 设计要点 (Key notes)  : ① 奇偶分治是负数的唯一正确解：偶次根在实数域无解，
 *                           必须拒绝并给码，绝不能返回绝对值的结果冒充；
 *                           奇次根取绝对值求根后取反，符号必须保留；
 *                         ② 零与近零直接返回 0，绕开 LN(0) 的负无穷陷阱；
 *                         ③ 二次根特判走 SQRT，精度优于对数法；一次根特判
 *                           直接返回原值；底数为 1 特判省一次 EXP / LN；
 *                         ④ 对数法用 EXP(LN(绝对值) 除以 n)，除数恒大于等于 1
 *                           （已由根次数域校验保证），无除零面；
 *                         ⑤ 结果有限性复检：EXP 在极端入参下可能溢出为非有限值，
 *                           必须复检后置 bValid，绝不把无穷大当结果交出去；
 *                         ⑥ 明确禁用迭代牛顿法：收敛次数不定，违反 PLC 的确定性
 *                           时间约束，现场表现为「同一入参偶尔多占一个周期」。
 * 开源溯源 (Origin)     : lgf-math。参考 LGF（Libre Graphical Framework）公开
 *                         函数库「Math」分类下 N 次根函数的功能分类与参数域
 *                         （被开方数 + 根次数 两段输入，值 + 有效位 输出），
 *                         只借分类、参数域与命名习惯，算法与实现 100% 自有
 *                         clean-room，不构成衍生作品。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 EXP / LN / SQRT
 * 故障码表 (Error codes):
 *   16#0001_011B【信息级】根次数越界（须 1 到 64），返回 0，bValid = FALSE
 *   16#0001_011C【信息级】偶次根负数、入参非有限或结果非有限，返回 0，bValid = FALSE
 * 验收向量 (Acceptance) :
 *   V1 27 的 3 次根 → 3.0（容差 1E-9）
 *   V2 -27 的 3 次根 → -3.0（奇次负数根，符号保留）
 *   V3 -4 的 2 次根 → 0.0，bValid = FALSE，码 011C
 *   V4 16 的 4 次根 → 2.0
 *   V5 根次数 0 → 0.0，码 011B
 *   V6 被开方数 0 → 0.0，bValid = TRUE（不走 LN(0) 路径）
 * 红线自检 (Redline)    : R1 零全局变量表与外部变量引用 ｜ R2 零物理地址直写
 *                         R3 纯 IEC 61131-3 ｜ R4 除零守卫 + 非有限值复检 +
 *                         浮点判零用容差 ｜ R5 全变量中英双语同行注释
 *                         R6 N/A（纯函数无状态机）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 10 · Level 1 数学族回补）
 *============================================================================*)

(*==============================================================================
 * 算法推演 (Worked traces)：
 *   推演 1  fValue = 27，nRoot = 3
 *     段 2 根次数 3 在 1 到 64 域内，通过
 *     段 3 入参有限，通过
 *     段 4 绝对值 27 不小于容差，不走零分支
 *     段 5 非负，标记非负，绝对值取 27
 *     段 6 不是一次根、不是二次根、底数不为 1，走对数法：
 *           指数项为 1 除以 3 约 0.3333，自然对数 27 约 3.2958，
 *           二者相乘约 1.0986，取指数得约 3.0
 *     段 7 结果有限，通过
 *     段 8 返回 3.0，有效为真
 *   推演 2  fValue = 负 27，nRoot = 3
 *     段 5 判负成立，根次数为奇数，标记为负，绝对值取 27，余同推演 1
 *     段 6 末段把结果取反，得负 3.0
 *   推演 3  fValue = 负 4，nRoot = 2
 *     段 5 判负成立且根次数为偶数，立即置码 011C 并返回 0，不做任何开方
 *   推演 4  fValue = 0，nRoot = 5
 *     段 4 绝对值小于容差，直接返回 0 且有效为真，绕开对零取对数
 *============================================================================*)

(*==============================================================================
 * 精度与适用域说明 (Accuracy)：
 *   1 二次根走标准库平方根，误差在最低有效位量级；
 *   2 其余次根走「对数加指数」，在双精度下相对误差约 1E-15 量级，
 *     但要求被开方数不为零且根次数不极端大；
 *   3 根次数超过 64 时，底数稍大就会因指数极小而使有效位被吃掉，
 *     故域上限锁在 64，超域一律拒绝而不是硬算；
 *   4 被开方数绝对值超过 1E300 视为溢出，直接拒绝，避免指数运算溢出。
 *============================================================================*)

(*==============================================================================
 * 调用示例 (Instance guide)：
 *   风机相似定律反算转速比（流量与转速成正比，功率与转速三次方成正比）：
 *     fRoot := FC_DL_NthRoot(fValue := fPowerRatio, nRoot := 3);
 *     IF bValid AND (fRoot > 0.0) THEN
 *         fSpeedRatio := fRoot;
 *     END_IF
 *   几何平均（三测点平均直径）：
 *     fGeo := FC_DL_NthRoot(fValue := fA * fB * fC, nRoot := 3);
 *   注意：本件为纯函数，调用后必须判 bValid 再使用返回值；返回 0 既可能是
 *   真实结果（被开方数为零），也可能是域错误，二者只能靠 bValid 与 uErrorId
 *   区分，这是本库对「不返回错误数值冒充结果」红线的具体落地。
 *============================================================================*)

FUNCTION FC_DL_NthRoot : LREAL
VAR_INPUT
    fValue : LREAL := 1.0;   // 被开方数，偶次根要求大于等于 0 [无量纲或工程单位] / Radicand, must be non-negative for even roots
    nRoot  : INT := 2;       // 根次数 n，有效域 1 到 DL_ROOT_MAX（正整数）[次] / Root order, valid 1 to DL_ROOT_MAX
END_VAR
VAR_OUTPUT
    bValid   : BOOL;         // 计算有效（域合法且结果有限）[-] / TRUE when the domain is legal and the result is finite
    uErrorId : UDINT;        // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    fAbsValue : LREAL;       // 被开方数绝对值，负数路径专用 [无量纲或工程单位] / Absolute value of the radicand
    fResult   : LREAL;       // 计算结果中间量 [无量纲或工程单位] / Result temporaries
    fExpInv   : LREAL;       // 根次数的倒数（如 0.25 对应四次根）[-] / Reciprocal of the root order
    bNegative : BOOL;        // 被开方数是否为负（奇次根取反标志）[-] / TRUE when the radicand is negative
END_VAR
VAR CONSTANT
    DL_ROOT_MIN  : INT   := 1;        // 根次数下限，1 次根等于原值 [次] / Lowest root order, one means identity
    DL_ROOT_MAX  : INT   := 64;       // 根次数上限，超此域对数法精度不可控 [次] / Highest root order
    DL_FLOAT_EPS : LREAL := 1.0E-12;  // 判零与判负容差 [-] / Tolerance for zero and negative tests
    DL_BIG       : LREAL := 1.0E300;  // 非有限值兜底门限 [-] / Magnitude guard for non-finite detection
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与标志预置：任何早退路径都要给出确定的 0
 *      Pre-set return value and flags: deterministic zero on every early exit
 *-----------------------------------------------------------------------------*)
FC_DL_NthRoot := 0.0;
bValid        := FALSE;
uErrorId      := 16#0000_0000;
bNegative     := FALSE;

(*------------------------------------------------------------------------------
 * 段 2｜根次数域校验（边界 B1）：必须落在 1 到 64 的闭区间
 *      Root order bounds check (boundary B1)
 *      上限取 64 的工程理由：再大的根次数在单精度输入下有效位已耗尽，
 *      对数法误差会放大到不可接受
 *-----------------------------------------------------------------------------*)
IF (nRoot < DL_ROOT_MIN) OR (nRoot > DL_ROOT_MAX) THEN
    uErrorId := 16#0001_011B;   // 根次数越界，返回 0
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜入参有限性校验（边界 B2）：NaN 与超大幅值一律拒绝
 *      Input finiteness check (boundary B2): reject NaN and huge magnitudes
 *      NaN 判据用「不等于自身」，是可移植写法，不依赖厂商 ISNAN
 *-----------------------------------------------------------------------------*)
IF (fValue <> fValue) OR (ABS(fValue) > DL_BIG) THEN
    uErrorId := 16#0001_011C;   // 入参非有限
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜零与近零：直接返回 0，绕开 LN(0) 的负无穷
 *      Zero and near-zero: return 0 directly to bypass LN of zero
 *-----------------------------------------------------------------------------*)
IF ABS(fValue) < DL_FLOAT_EPS THEN
    FC_DL_NthRoot := 0.0;
    bValid        := TRUE;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜负数分治（边界 B3）：偶次根无解直接拒绝，奇次根取绝对值后取反
 *      Negative radicand split: even roots are rejected, odd roots keep the sign
 *-----------------------------------------------------------------------------*)
IF fValue < (-1.0 * DL_FLOAT_EPS) THEN
    IF (nRoot MOD 2) = 0 THEN
        uErrorId := 16#0001_011C;   // 偶次根负数，实数域无解，禁止拿绝对值冒充
        RETURN;
    END_IF
    bNegative := TRUE;              // 奇次根：结果保留负号
    fAbsValue := -fValue;
ELSE
    fAbsValue := fValue;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜主计算：一次根、平方根、底数为一特判，其余走对数法
 *      Main computation: identity, square root and unity shortcuts, then logs
 *      除数 nRoot 已由段 2 保证大于等于 1，不存在除零面
 *-----------------------------------------------------------------------------*)
IF nRoot = DL_ROOT_MIN THEN
    fResult := fAbsValue;                                  // 一次根等于原值
ELSIF (nRoot = 2) AND (NOT bNegative) THEN
    fResult := SQRT(fAbsValue);                            // 平方根走标准库，精度优于对数法
ELSIF ABS(fAbsValue - 1.0) < DL_FLOAT_EPS THEN
    fResult := 1.0;                                        // 底数为 1 时任何次根均为 1
ELSE
    fExpInv := 1.0 / INT_TO_LREAL(nRoot);                  // 根次数倒数，显式类型转换
    fResult := EXP(LN(fAbsValue) / INT_TO_LREAL(nRoot));   // 对数法：e 的 (ln x 除以 n) 次幂
END_IF

IF bNegative THEN
    fResult := -fResult;                                   // 奇次根：符号还原
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜结果有限性复检（边界 B4）：EXP 溢出兜底
 *      Result finiteness recheck (boundary B4): catch exponential overflow
 *-----------------------------------------------------------------------------*)
IF (fResult <> fResult) OR (ABS(fResult) > DL_BIG) THEN
    uErrorId      := 16#0001_011C;   // 结果非有限
    FC_DL_NthRoot := 0.0;
    bValid        := FALSE;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜合法收口
 *      Legal close-out
 *-----------------------------------------------------------------------------*)
FC_DL_NthRoot := fResult;
bValid        := TRUE;
END_FUNCTION
