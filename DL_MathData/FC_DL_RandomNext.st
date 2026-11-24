(*==============================================================================
 * 组件名称 (Component)  : FC_DL_RandomNext
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类     (Category)   : 随机序列函数（Function · Math / Test stimulus）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（UDINT 乘加 / 显式类型转换），零厂商方言
 * 功能描述 (Function)   : 线性同余（乘加型）伪随机序列的**单步递推**。给定当前
 *                         种子返回 [0, 1) 区间的均匀分布随机数与**新种子**，函数
 *                         内部不保存任何状态：调用方只需把 uNextSeed 回灌下一拍，
 *                         即可得到「可复现、可回溯、可插入断点」的确定序列。
 *                         用于通讯压力测试、仿真激励、算法自检与随机抽样验证。
 *
 * 【引脚契约 / Pin contract】
 *   输入 uSeed      : UDINT — 当前种子 [cnt]，首次调用由调用方给定任意值；
 *   输入 bReseed    : BOOL  — TRUE 时强制改用内置默认种子（可复现基线）；
 *   输出 uNextSeed  : UDINT — 下一拍应回灌的种子 [cnt]；
 *   输出 bZeroSeed  : BOOL  — 本次输入种子为 0，已置提示位（见下方勘误声明）；
 *   输出 bSat      : BOOL  — 结果被钳到 1.0 减容差，保证半开区间；
 *   输出 uErrorId  : UDINT — 事件码，0 = 无。本件全部码为信息级；
 *   返回  值        : REAL  — [0, 1) 均匀分布随机数。
 *
 * 【递推式与参数 / Recurrence and parameters】
 *   uNextSeed = uSeed × 1664525 + 1013904223（以 2 的 32 次方为模，无符号自然回绕）
 *   参数取自《Numerical Recipes》公开推荐的乘加型同余参数：
 *   周期为 2 的 32 次方（全周期），高 16 位统计质量良好，足够测试激励使用。
 *   本件**不显式取模**：无符号 32 位乘加的溢出回绕在三平台语义一致，
 *   显式取模反而会引入「有符号 / 无符号取模行为差异」这一类历史坑。
 *
 * 【可复现性承诺 / Reproducibility contract】
 *   同一 (uSeed, bReseed) 输入组合，在任何扫描周期、任何平台、任何时刻调用，
 *   返回值与 uNextSeed 完全一致；不存在「上电时间参与」或「内部状态漂移」。
 *   由此得到两条可用的自检关系：
 *     R1 反向复算：FLOOR(返回值 / 2.3283064E-10) 等于 uNextSeed（容差内）；
 *     R2 序列复现：把 uNextSeed 回灌，第二次调用的结果与首次运行同序号一致。
 *
 * 【归一与半开区间 / Normalisation and the half-open interval】
 *   返回值 = uNextSeed × 2.3283064E-10（即乘以 2 的 32 次方的倒数）。
 *   由于 REAL 只有 24 位尾数，极大种子在归一乘之后可能被舍入到 1.0，
 *   故在后置守卫里把「大于等于 1.0」的结果钳到 1.0 减容差并置 bSat，
 *   以此**硬保证**返回值落在 [0, 1) 半开区间——这是调用方做数组下标
 *   （乘以容量后取整）时不会越界的唯一前提。
 *
 * 【对规格原文的一处勘误 / Erratum on the specification】
 *   规格原文称「0 在乘法型同余中是吸收态，需替换为默认种子」。经复核：本件采用
 *   **增量非零**的乘加型（增量 1013904223 为奇数），零种子经一次递推即得增量本身，
 *   随后立即脱离零，并不是吸收态；若强行替换为默认种子，则与同一规格给出的
 *   验收向量「零种子 → 新种子 = 1013904223」直接矛盾。故本实现取：
 *   零种子**按原值参与递推**，同时置 bZeroSeed 供现场识别「种子未初始化」，
 *   序列既满足向量，也不产生退化。此为刻意决策，不是遗漏。
 *
 * 【边界防错清单 / Boundary guard list】
 *   B1 乘子被工具链改写为 0（理论上不可达）→ 回退到增量常数（奇数非零），
 *      置 0123，保证任何情况下序列不退化；
 *   B2 种子为 0 → 按原值递推并置 bZeroSeed（见勘误声明），不产生常数列；
 *   B3 重播种（bReseed TRUE）→ 强制从默认种子起步，优先级高于零种子提示；
 *   B4 归一结果舍入到 1.0 → 钳到 1.0 减容差并置 bSat，保证半开区间；
 *   B5 归一结果为负（理论上不可达）→ 钳到 0.0，保证下界；
 *   B6 全件无除法（用乘法倒数代替）、无数组、无循环，不存在除零、越界、死循环；
 *   B7 浮点比较只做区间与下界判断（有序比较），唯一「等于 0」的判据落在
 *      UDINT 域（整数判等合法），浮点判等红线在本件不适用。
 *
 * 【与既有件的职责边界 / Family separation】
 *   FB_DL_SineGenerator / FB_DL_SawtoothGenerator / FB_DL_PulseGenerator
 *   = 确定性**波形**发生器（周期、相位、幅值可调，输出形状固定）；
 *   本件 = **伪随机**序列且**无状态**（不占实例内存、可重入、可回溯）。
 *   波形件给「可预期的激励」，本件给「不可预期但可复现的激励」，用途正交。
 *
 * 【调用示例 / Call example（仅行注释，不嵌套块注释）】
 *   // 通讯压力测试：每拍生成一个随机报文号，种子由静态变量持有
 *   // fRand := FC_DL_RandomNext(uSeed := uMySeed, bReseed := bTestRestart,
 *   //          uNextSeed => uMySeed, bZeroSeed => bSeedBad,
 *   //          bSat => bRandSat, uErrorId => uRandErr);
 *   // uMsgNo := REAL_TO_UDINT(fRand * 1000.0);   // 0 ~ 999 的报文号
 *
 * 【平台移植注意 / Porting notes】
 *   UDINT 乘加溢出回绕在三平台一致；UDINT 到 REAL 的转换按「显式转换」写出，
 *   不做隐式提升；本件不依赖任何随机数系统函数（平台各有方言，且不可复现）。
 *
 * 【工程背景与应用场景 / Background and use cases】
 *   ① 通讯压力测试：随机长度、随机间隔的报文灌注，压出缓冲区边界缺陷；
 *   ② 仿真激励：给滤波器与统计件灌随机序列，验证极值与分位计算；
 *   ③ 算法自检：同一种子重跑同一序列，比对两次运行结果是否逐位一致；
 *   ④ 抽样巡检：从合格批次里随机抽检，种子留档后可完全复现抽检名单。
 *
 * 【局限与误用提示 / Limitations and misuse】
 *   ① 本件是**测试激励级**序列：低位相关性明显，禁止用于安全相关抽样（如安全
 *      功能抽检名单）、禁止用于加密与鉴权、禁止用于需要统计独立性的 A/B 分流；
 *   ② 序列周期为 2 的 32 次方，长时间高频调用后会出现重复，压力测试可接受，
 *      长周期仿真应由调用方按批次换种子；
 *   ③ 本件不保存状态：调用方若忘记回灌 uNextSeed，每拍都会得到同一个数，
 *      这一类「序列卡死」不是本件故障，排查时先看种子是否回灌；
 *   ④ 需并行多路序列时，各路给不同初值种子即可，本件无共享状态、无互斥需求。
 *
 * 【验收向量 / Acceptance vectors】
 *   V1 零种子：uSeed = 0 → uNextSeed = 1013904223、返回值约 0.2360680、bZeroSeed；
 *   V2 满量程种子：uSeed = 16#FFFF_FFFF → uNextSeed = 1012239698、返回值约 0.2356716；
 *   V3 确定性：同一种子连调两次（第二次回灌 uNextSeed），序列与前次运行一致；
 *   V4 半开区间：任取 1000 个种子，返回值全部满足 0.0 至 1.0 的左闭右开；
 *   V5 重播种：bReseed TRUE 时无论 uSeed 为何，uNextSeed 恒为默认种子的首步结果。
 *   V6 参数退化：把乘子视为 0 的损坏场景 → 回退后序列仍逐拍变化、uErrorId 0123。
 *
 * 【事件码表 / Event code table（全部信息级，不置报警位）】
 *   16#0001_0123  递推参数被改写为退化值，已回退到保底常数（保护性提示）。
 *
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 11 · 泳道 A · LGF Math 组）
 *============================================================================*)
FUNCTION FC_DL_RandomNext : REAL
VAR_INPUT
    uSeed    : UDINT;                      // 当前种子 [cnt]，首次调用任意值 / Current seed [cnt], any value on the first call
    bReseed  : BOOL;                       // TRUE 时强制从默认种子起步 / TRUE forces the default seed
END_VAR
VAR_OUTPUT
    uNextSeed : UDINT;                     // 下一拍应回灌的种子 [cnt] / Seed to feed back on the next call [cnt]
    bZeroSeed : BOOL;                      // 输入种子为 0 的提示位 / Notice flag for a zero input seed
    bSat      : BOOL;                      // 结果已钳到上界容差内 / Result clamped inside the upper bound
    uErrorId  : UDINT;                     // 事件码，0 = 无 / Event code, 0 = none
END_VAR
VAR
    _uWork   : UDINT;                      // 本次实际参与递推的种子 [cnt] / Seed actually used by the recurrence [cnt]
    _uMul    : UDINT;                      // 工作乘子，含退化回退 / Working multiplier with the fallback
    _uInc    : UDINT;                      // 工作增量，含退化回退 / Working increment with the fallback
    _fOut    : REAL;                       // 归一后的随机数 [-] / Normalised random number [-]
END_VAR
VAR CONSTANT
    DL_LCG_MUL      : UDINT := 1664525;        // 乘子，Numerical Recipes 公开参数 / Multiplier from the Numerical Recipes parameters
    DL_LCG_INC      : UDINT := 1013904223;     // 增量，奇数保证全周期 / Increment, odd ensures a full period
    DL_SEED_DEFAULT : UDINT := 16#0000_0001;   // 默认种子，重播种基线与零种子回退 / Default seed for reseeding and fallback
    DL_RAND_SCALE   : REAL  := 2.3283064E-10;  // 2 的 32 次方倒数，归一因子 / Reciprocal of two to the thirty-second power
    DL_FLOAT_EPS    : REAL  := 1.0E-6;         // 上界保护容差 / Upper-bound guard epsilon
    DL_ONE          : REAL  := 1.0;            // 半开区间上界 / Upper bound of the half-open interval
    DL_RAND_ZERO    : REAL  := 0.0;            // 半开区间下界 / Lower bound of the half-open interval
    DL_ERR_PARAM    : UDINT := 16#0001_0123;   // 递推参数退化回退的信息级码 / Info code for the degenerate parameter fallback
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与输出预置（函数必须先给出安全返回值）
 *      Preset the return value and the outputs
 *   返回值预置 0.0：早退路径一律给下界值，绝不给未初始化的中间量。
 *-----------------------------------------------------------------------------*)
FC_DL_RandomNext := DL_RAND_ZERO;          // 返回值预置 0（Return preset to zero）
uNextSeed := 0;                            // 新种子预置 0，段 4 覆盖（Next seed preset, overwritten in stage 4）
bZeroSeed := FALSE;                        // 零种子提示位预置（Zero-seed notice preset）
bSat      := FALSE;                        // 上限钳位标志预置（Upper clamp flag preset）
uErrorId  := 16#0000_0000;                 // 事件码预清零（Event code preset to zero）

(*------------------------------------------------------------------------------
 * 段 2｜递推参数的完整性校验（边界 B1）
 *      Integrity check of the recurrence parameters
 *   乘子为 0 会让序列退化成常数列（每拍都等于增量），这是唯一致命的参数损坏；
 *   出现时回退到增量常数（奇数且非零），并置信息码留痕，绝不静默继续。
 *-----------------------------------------------------------------------------*)
_uMul := DL_LCG_MUL;                       // 乘子工作副本接管常数（Multiplier working copy）
_uInc := DL_LCG_INC;                       // 增量工作副本接管常数（Increment working copy）

IF _uMul = 0 THEN                          // 乘子被改写为 0，序列将退化（Degenerate multiplier）
    _uMul    := DL_LCG_INC;                // 回退到增量常数，保底非零（Fall back to the non-zero increment）
    uErrorId := DL_ERR_PARAM;              // 置参数回退信息码（Raise the parameter fallback info code）
END_IF
IF _uInc = 0 THEN                          // 增量为 0 时退化为纯乘法型（Zero increment degenerates to a pure multiplier）
    _uInc    := DL_LCG_MUL;                // 回退到乘子常数，保底非零（Fall back to the non-zero multiplier）
    uErrorId := DL_ERR_PARAM;              // 置参数回退信息码（Raise the parameter fallback info code）
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜种子选择（边界 B2 / B3：重播种优先，零种子只提示不替换）
 *      Seed selection, reseed wins, a zero seed is only flagged
 *   口径见头注释的勘误声明：零种子按原值参与递推，仅置提示位。
 *-----------------------------------------------------------------------------*)
IF bReseed THEN                            // 重播种请求（Reseed requested）
    _uWork    := DL_SEED_DEFAULT;          // 强制从默认种子起步（Start from the default seed）
    bZeroSeed := FALSE;                    // 重播种时不再提示零种子（No zero-seed notice on a reseed）
ELSE                                       // 常规递推（Regular recurrence）
    _uWork := uSeed;                       // 种子原值接管（Take the input seed as-is）
    IF uSeed = 0 THEN                      // 种子为 0，提示未初始化（Zero seed noticed）
        bZeroSeed := TRUE;                 // 置提示位（Raise the notice flag）
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜单步递推（模 2 的 32 次方，无符号自然回绕，不显式取模）
 *      Single-step recurrence with natural 32-bit wraparound
 *   先乘后加，全程 UDINT 域：回绕由类型宽度自然完成，跨平台一致。
 *-----------------------------------------------------------------------------*)
uNextSeed := _uWork * _uMul + _uInc;       // 递推一步，新种子（One recurrence step, the next seed）

(*------------------------------------------------------------------------------
 * 段 5｜归一化（半开区间由后置守卫硬保证）
 *      Normalisation, the half-open interval is enforced by the guards below
 *   用乘法倒数代替除法：既避开除零，也避开「除以 2 的 32 次方」的精度损失。
 *-----------------------------------------------------------------------------*)
_fOut := UDINT_TO_REAL(uNextSeed) * DL_RAND_SCALE;   // 显式转换后乘以归一因子（Explicit cast then scale）
FC_DL_RandomNext := _fOut;                 // 结果先行落位（Result placed first）

(*------------------------------------------------------------------------------
 * 段 6｜后置守卫（边界 B4 / B5）
 *      Post guards on the returned value
 *   REAL 尾数 24 位，极大种子归一后可能被舍入到 1.0：钳到 1.0 减容差并置 bSat，
 *   这是调用方「乘以容量后取整」不越界的唯一前提。
 *-----------------------------------------------------------------------------*)
IF FC_DL_RandomNext >= DL_ONE THEN         // 舍入触及上界（Rounded up to the bound）
    FC_DL_RandomNext := DL_ONE - DL_FLOAT_EPS;  // 钳到上界内侧（Clamp inside the bound）
    bSat := TRUE;                          // 置钳位标志（Raise the clamp flag）
END_IF

IF FC_DL_RandomNext < DL_RAND_ZERO THEN    // 结果低于下界，理论上不可达（Below the bound, unreachable）
    FC_DL_RandomNext := DL_RAND_ZERO;      // 钳到下界（Clamp to the lower bound）
END_IF
END_FUNCTION
