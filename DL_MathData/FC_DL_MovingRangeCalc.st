//==============================================================================
// 函数：FC_DL_MovingRangeCalc ｜ 中文名称：滑动极差（相邻样本差）原子计算
// 所属子库：DL_MathData ｜ 版本：v1.0.0 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop / Machine Expert（纯标准库）
// 功能描述：SPC 判稳前置原子：MR = |x_i − x_(i−1)|，相邻两样本的极差。
//           无状态原子：本拍新样本与上一拍样本由调用方传入，本件不驻留
//           历史样本（滑动窗管理属上层 FB，职责边界见头注释）。
// 开源溯源 (Origin)：原创实现（t2-1-lgf-measurement 测量链语义深化，零外部
//           源码行，clean-room 独立编写）
// 公开接口清单：输入 fNewSample / fPrevSample；输出 fRange / bValid
// 单位表：fNewSample / fPrevSample / 返回值 [工程单位随调用方，差值不改单位]
// 输入契约：两样本须同一工程单位同一测点（跨测点差值无物理意义）；调用方
//           负责滑动窗历史驻留与回传节奏。
// 输出契约：返回值为极差（恒非负）；bValid = FALSE 拍返回哨兵 0.0，
//           调用方禁将哨兵值计入 SPC 控制图样本。
// 错误码表：纯函数无状态机码轨；无效输入经 bValid = FALSE 表达（哨兵返回
//           0.0），本件不占用 16#0001 段码位（邻件免让位）
// 状态机：N/A（纯函数，无状态，可重入）
// 边界行为：① 任一输入非有限（NaN 自反判 + 幅值上限判）→ bValid := FALSE、
//           哨兵 0.0 返回；② 极差恒非负（ABS 内建保证）；③ 无除法无域闸。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 2 · 序 7）
//==============================================================================

(*------------------------------------------------------------------------------
 * 调用示例：fMR := FC_DL_MovingRangeCalc(fNewSample := x_i,
 *                                        fPrevSample := x_im1,
 *                                        bValid => bOk);
 * 注意：滑动窗历史驻留在上层 FB，本件只做相邻差值，两拍调用间无状态。
 * 组装说明：① 上层滑动窗管理件持有 x_(i−1) 并在下一拍回传 fPrevSample，
 *             本件零跨拍状态、可重入；
 *           ② 连续多拍极差进入 SPC 控制图判稳判据前，须校 bValid；
 *           ③ 本件输出单位与输入工程单位一致（差值不改单位）。
 *-----------------------------------------------------------------------------*)
FUNCTION FC_DL_MovingRangeCalc : LREAL
VAR_INPUT
    fNewSample  : LREAL;               // 本拍新样本 [工程单位随调用方] / New sample this scan [unit per caller]
    fPrevSample : LREAL;               // 上一拍样本 [工程单位随调用方] / Previous sample [unit per caller]
END_VAR
VAR_OUTPUT
    bValid      : BOOL;                // 结果有效标志，FALSE 时返回哨兵 0.0 / Result validity flag
END_VAR
VAR CONSTANT
    DL_MR_INF   : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_MR_ZERO  : LREAL := 0.0;        // 无效哨兵返回值 / Sentinel return for invalid
END_VAR

// ---- 段 1｜出口默认值（纯函数无实例，无定时器/沿刷新义务）----
bValid := FALSE;                      // 缺省无效 / Invalid by default

// ---- 段 2｜输入防御：非有限值（NaN 自反判 + Inf 幅值判，R79）----
IF (fNewSample <> fNewSample) OR (ABS(fNewSample) > DL_MR_INF)
   OR (fPrevSample <> fPrevSample) OR (ABS(fPrevSample) > DL_MR_INF) THEN
    FC_DL_MovingRangeCalc := DL_MR_ZERO; // 无效输入：哨兵零返回，不进入运算 / Invalid input, sentinel zero return
    RETURN;                            // 结构早退 / early exit
END_IF

// ---- 段 3｜极差主体：MR = |x_i − x_(i−1)|，恒非负 ----
FC_DL_MovingRangeCalc := ABS(fNewSample - fPrevSample); // 滑动极差 / Moving range
bValid := TRUE;                       // 全部防御通过：结果有效 / Result valid
END_FUNCTION
