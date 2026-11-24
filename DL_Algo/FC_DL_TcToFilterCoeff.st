//==============================================================================
// 函数：FC_DL_TcToFilterCoeff ｜ 中文名称：时间常数→离散一阶滤波系数换算原子
// 所属子库：DL_Algo ｜ 版本：v1.0.0 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop（纯标准库）
// 功能描述：α = Ts/(Ts + Tc) 离散一阶低通滤波系数换算原子（后向欧拉口径）。
//           分工声明：系数原子属本件；一阶滤波本体（驻留状态、逐拍迭代）
//           属 FB_DL_LowPassFilter，互不替代——该件头注释与本件互引，
//           上层先经本件换算 α 再注入滤波本体。
// 开源溯源 (Origin)：原创实现（自研-std 标准包装线，零外部源码行，clean-room
//           独立编写）
// 公开接口清单：输入 fTs / fTc；输出 返回值 / bValid
// 单位表：fTs / fTc [秒] / 返回值 α [1]（无量纲系数）
// 输入契约：fTs 须与实际任务周期一致（任务周期变更须重算重注入）；fTc >= 0
//           合法（0 = 直通旁路口径）。
// 输出契约：返回值为后向欧拉离散滤波系数，域 (0, 1]；bValid = FALSE 拍
//           返回哨兵 0.0，禁注入 FB_DL_LowPassFilter。
// 错误码表：纯函数无状态机码轨；无效输入经 bValid = FALSE 表达（哨兵返回
//           0.0），本件不占用 16#0002 段码位（邻件免让位）
// 状态机：N/A（纯函数，无状态，可重入）
// 边界行为：① fTs <= 0（采样周期非法）→ 拒绝（bValid := FALSE，哨兵 0.0）；
//           ② fTc < 0（时间常数非法）→ 拒绝；fTc = 0 合法（α = 1 直通）；
//           ③ 分母 (Ts + Tc) 先过正域闸再除（防除零强制闸）；
//           ④ 非有限输入 → 哨兵 0.0 返回；
//           ⑤ α 输出域 (0, 1]，数学上由分子分母同号保证，仍出口钳位兜底。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 3 · 序 17）
//==============================================================================

(*------------------------------------------------------------------------------
 * 调用示例：fA := FC_DL_TcToFilterCoeff(fTs := 0.01, fTc := 0.5,
 *                                       bValid => bOk);
 * 注意：α = 0.01/0.51 ≈ 0.0196；α 注入 FB_DL_LowPassFilter 前必须 bOk。
 * 组装说明：① 与 FB_DL_LowPassFilter 互引分工：本件出系数、该件做逐拍
 *             滤波本体，bValid = FALSE 拍 α 不得注入滤波本体；
 *           ② fTs 应与实际任务周期一致（任务周期变更须重算并重注入）；
 *           ③ fTc = 0 时 α = 1 直通（滤波旁路口径，上层据此可做旁路）。
 *-----------------------------------------------------------------------------*)
FUNCTION FC_DL_TcToFilterCoeff : LREAL
VAR_INPUT
    fTs     : LREAL;                   // 采样周期 [秒]，有效域 (0, +∞) / Sampling period [s]
    fTc     : LREAL;                   // 滤波时间常数 [秒]，有效域 [0, +∞) / Filter time constant [s]
END_VAR
VAR_OUTPUT
    bValid  : BOOL;                    // 结果有效标志，FALSE 时返回哨兵 0.0 / Result validity flag
END_VAR
VAR CONSTANT
    DL_TC_EPS  : LREAL := 1.0E-12;     // 分母正域闸容差 [秒] / Denominator gate tolerance [s]
    DL_TC_INF  : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_TC_ZERO : LREAL := 0.0;         // 无效哨兵返回值 / Sentinel return for invalid
    DL_TC_ONE  : LREAL := 1.0;         // α 上界（直通口径）/ Alpha ceiling, pass-through
END_VAR

// ---- 段 1｜出口默认值（纯函数无实例，无定时器/沿刷新义务）----
bValid := FALSE;                      // 缺省无效 / Invalid by default

// ---- 段 2｜输入防御：非有限值（NaN 自反判 + Inf 幅值判，R79）----
IF (fTs <> fTs) OR (ABS(fTs) > DL_TC_INF)
   OR (fTc <> fTc) OR (ABS(fTc) > DL_TC_INF) THEN
    FC_DL_TcToFilterCoeff := DL_TC_ZERO; // 无效输入：哨兵零返回 / Invalid input, sentinel zero return
    RETURN;                            // 结构早退 / early exit
END_IF

// ---- 段 3｜域闸：Ts 正域 + Tc 非负域（fTc = 0 合法 = α 直通）----
IF (fTs <= DL_TC_EPS) OR (fTc < 0.0) THEN
    FC_DL_TcToFilterCoeff := DL_TC_ZERO; // 域外拒绝：哨兵零返回 / Out of domain, refused
    RETURN;                            // 结构早退 / early exit
END_IF

// ---- 段 4｜换算主体：α = Ts/(Ts + Tc)，分母先过正域闸（防除零强制闸）----
IF (fTs + fTc) <= DL_TC_EPS THEN
    FC_DL_TcToFilterCoeff := DL_TC_ZERO; // 分母退化拒绝（理论上不可达，仍强制闸）/ Degenerate denominator, gated
    RETURN;                            // 结构早退 / early exit
END_IF
FC_DL_TcToFilterCoeff := fTs / (fTs + fTc); // 滤波系数 [1] / Filter coefficient [1]
IF FC_DL_TcToFilterCoeff > DL_TC_ONE THEN
    FC_DL_TcToFilterCoeff := DL_TC_ONE; // α 上界钳位兜底（浮点噪声防护）/ Alpha ceiling clamp
END_IF
bValid := TRUE;                       // 全部防御通过：结果有效 / Result valid
END_FUNCTION
