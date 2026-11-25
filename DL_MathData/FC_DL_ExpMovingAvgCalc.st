//==============================================================================
// 函数：FC_DL_ExpMovingAvgCalc ｜ 中文名称：指数移动平均（EMA）无状态原子
// 所属子库：DL_MathData ｜ 版本：v1.0.0 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop / Machine Expert（纯标准库）
// 功能描述：EMA 无状态原子：fNewAvg = fOldAvg + α·(fNewSample − fOldAvg)。
//           历史均值驻留在调用方（本件不驻留任何跨拍状态，可重入），
//           α 引脚注入（0 < α ≤ 1），平滑度与 α 成反比。
//           同族分工：有状态滤波本体（历史均值自驻留）属 FB_DL_EwmaFilter；
//           本件为无状态可重入原子（历史均值由调用方持有回传），互不替代（R73 互引）。
// 开源溯源 (Origin)：原创实现（t2-1-lgf-math 数学链语义深化，零外部源码行，
//           clean-room 独立编写）
// 公开接口清单：输入 fNewSample / fOldAvg / fAlpha；输出 返回值 / bValid
// 单位表：fNewSample / fOldAvg / 返回值 [工程单位随调用方] / fAlpha[1]
// 输入契约：fAlpha 有效域 (0, 1]，须与采样周期配套（α = Ts/(Ts+Tc) 口径
//           经 FC_DL_TcToFilterCoeff 换算）；三输入须同一工程单位。
// 输出契约：返回值为新均值（与输入同域）；bValid = FALSE 拍返回哨兵 0.0，
//           调用方须保持旧均值不更新（哨兵禁回写历史）。
// 错误码表：纯函数无状态机码轨；无效输入经 bValid = FALSE 表达（哨兵返回
//           0.0），本件不占用 16#0001 段码位（邻件免让位）
// 状态机：N/A（纯函数，无状态，可重入）
// 边界行为：① α 域 (0, 1]：α <= 0 或 α > 1 → 拒绝（bValid := FALSE，
//           哨兵 0.0）；② 任一输入非有限 → 哨兵 0.0 返回；
//           ③ 无除法无饱和（输出域与输入同域）。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 2 · 序 10）
//==============================================================================

(*------------------------------------------------------------------------------
 * 调用示例：fAvg := FC_DL_ExpMovingAvgCalc(fNewSample := x,
 *             fOldAvg := fAvgPrev, fAlpha := 0.1, bValid => bOk);
 * 注意：调用方持有 fAvgPrev 并在下一拍回传，本件零跨拍状态。
 * 组装说明：① α 与采样周期配套：α = Ts/(Ts + Tc) 口径请先经
 *             FC_DL_TcToFilterCoeff 换算后注入，两件互引分工已声明；
 *           ② bValid = FALSE 拍调用方须保持旧均值不更新（本件哨兵 0.0
 *             不得回写历史均值）；
 *           ③ 冷启动口径：首拍令 fOldAvg = fNewSample（α 任意合法值）。
 *-----------------------------------------------------------------------------*)
FUNCTION FC_DL_ExpMovingAvgCalc : LREAL
VAR_INPUT
    fNewSample : LREAL;                // 新样本 [工程单位随调用方] / New sample [unit per caller]
    fOldAvg    : LREAL;                // 旧均值 [工程单位随调用方] / Previous average [unit per caller]
    fAlpha     : LREAL;                // 平滑系数 [1]，有效域 (0, 1] / Smoothing factor [1], valid range (0, 1]
END_VAR
VAR_OUTPUT
    bValid     : BOOL;                 // 结果有效标志，FALSE 时返回哨兵 0.0 / Result validity flag
END_VAR
VAR CONSTANT
    DL_EA_ALPHA_MIN : LREAL := 1.0E-9; // 平滑系数有效下限（开区间语义按容差闸）/ Alpha valid floor, open-interval via tolerance
    DL_EA_ALPHA_MAX : LREAL := 1.0;    // 平滑系数有效上限（含 1 = 直通）/ Alpha valid ceiling, 1 = pass-through
    DL_EA_INF  : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_EA_ZERO : LREAL := 0.0;         // 无效哨兵返回值 / Sentinel return for invalid
END_VAR

// ---- 段 1｜出口默认值（纯函数无实例，无定时器/沿刷新义务）----
bValid := FALSE;                      // 缺省无效 / Invalid by default

// ---- 段 2｜输入防御：非有限值（NaN 自反判 + Inf 幅值判，R79）----
IF (fNewSample <> fNewSample) OR (ABS(fNewSample) > DL_EA_INF)
   OR (fOldAvg <> fOldAvg) OR (ABS(fOldAvg) > DL_EA_INF)
   OR (fAlpha <> fAlpha) OR (ABS(fAlpha) > DL_EA_INF) THEN
    FC_DL_ExpMovingAvgCalc := DL_EA_ZERO; // 无效输入：哨兵零返回 / Invalid input, sentinel zero return
    RETURN;                            // 结构早退 / early exit
END_IF

// ---- 段 3｜α 域闸：(0, 1] 域外拒绝（直通与停更均非法，交上层决断）----
IF (fAlpha <= DL_EA_ALPHA_MIN) OR (fAlpha > DL_EA_ALPHA_MAX) THEN
    FC_DL_ExpMovingAvgCalc := DL_EA_ZERO; // α 域外拒绝：哨兵零返回 / Alpha out of range, refused
    RETURN;                            // 结构早退 / early exit
END_IF

// ---- 段 4｜EMA 主体：fNewAvg = fOldAvg + α·(新样本 − 旧均值) ----
FC_DL_ExpMovingAvgCalc := fOldAvg + fAlpha * (fNewSample - fOldAvg); // 新均值 / New average
bValid := TRUE;                       // 全部防御通过：结果有效 / Result valid
END_FUNCTION
