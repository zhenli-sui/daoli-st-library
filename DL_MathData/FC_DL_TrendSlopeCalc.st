(*
  FC_DL_TrendSlopeCalc  —  滑窗一阶最小二乘趋势斜率（纯函数）/ Sliding-window least-squares trend slope, pure function
  分类 Category : DL_MathData
  码位 Code     : 16#05_0_04
  段位说明      : 05_0 段仅占 00~03，04/05 为 R38 预留解除后的空穴，本件启用 04 格
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-math — Math 分类「趋势估计」待挖项落地
  溯源 Origin   : clean-room 实现，一阶线性最小二乘为公开经典数学方法，未复制任何源码行
  功能 Function : 1) 对调用方给定的滑窗样本 afY 做一阶最小二乘拟合 y = a + b*x，x = i*fDt；
                  2) 输出斜率 fSlope（趋势速率）、截距 fIntercept、拟合优度 fR2 与有效样本数 nValid；
                  3) 非有限样本（NaN/Inf 判据：x <> x 或幅值越限）自动剔除，不参与拟合；
                  4) 有效样本 < 2、采样间隔 <= 0、SStot 退化为零（常数窗）等边界全部给出确定输出。
  边界 Boundary : ① 纯函数无内部状态，每拍重算；滑窗由调用方持有（FB_DL_SignalStatistics /
                  自管环形窗均可），本件只做一次拟合；
                  ② 与 FB_DL_Differentiator 分工：微分件是瞬时差分、噪声敏感；本件是窗内拟合斜率，
                  供温度升速 / 压降速率 / 泄漏率等趋势判级；
                  ③ 与 FB_DL_*Trend 监视件分工：本件是纯函数估计原子，不做判级、不锁存；
                  ④ 除零守卫：fDt <= 0 直接判无效；SStot 容差判零（浮点禁 = 比较）。
  依赖 Depends  : 无 DL_ 内部依赖，纯 IEC 61131-3
  码表 Error codes（本件格 05_0_04，子码步进 +0x100）:
    16#0005_0104 信息级：非有限样本已剔除（剔后仍 >= 2，拟合照常完成）
    16#0005_0204 故障级：无拟合（有效样本 < 2 或 fDt <= 0 或输入数组非法），返回值 FALSE
    16#0005_0304 信息级：窗内样本为常数（SStot 退化），fR2 置 0，斜率/截距仍有效

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 1 · 序号 2）
*)

FUNCTION FC_DL_TrendSlopeCalc : BOOL    // 返回 TRUE = 拟合有效（斜率/截距/R2 可信）/ TRUE = fit valid
VAR_IN_OUT
    afY : ARRAY[*] OF LREAL;            // 样本窗（时间顺序，最老样本在下标小端）/ Sample window in time order, oldest at low index
END_VAR
VAR_INPUT
    fDt      : LREAL := 1.0;            // 采样间隔 [s]，x = i*fDt，域 > 0 / Sample interval [s], x equals index times fDt
    nCount   : INT := 0;                // 有效样本数声明值 [个]，2..数组维度 / Declared sample count, 2..array size
END_VAR
VAR_OUTPUT
    fSlope     : LREAL;                 // 拟合斜率 b [EU/s]，正值 = 上升趋势 / Fitted slope [EU/s], positive means rising
    fIntercept : LREAL;                 // 拟合截距 a [EU] / Fitted intercept [EU]
    fR2        : LREAL;                 // 拟合优度 R² [无量纲]，0..1，常数窗置 0 / Goodness of fit, 0..1, zero for a constant window
    nValid     : INT;                   // 剔除非有限值后的有效样本数 [个] / Valid sample count after non-finite rejection
    uErrorId   : UDINT;                 // 事件码，0 = 无事件（本件码均为单次调用瞬时，无锁存）/ Event code, transient per call
END_VAR
VAR
    nHi       : INT;                    // 数组上界换算（开放数组） / Resolved array upper bound
    nUse      : INT;                    // 参与拟合的样本数 = MIN(nCount, nHi+1) / Samples actually used
    i         : INT;                    // 遍历索引 / Traversal index
    nGood     : INT;                    // 有限样本计数 [个] / Finite sample counter
    fSumX     : LREAL;                  // Σx 累加器 [s] / Sum of x
    fSumY     : LREAL;                  // Σy 累加器 [EU] / Sum of y
    fSumXY    : LREAL;                  // Σxy 累加器 [EU·s] / Sum of x times y
    fSumX2    : LREAL;                  // Σx² 累加器 [s²] / Sum of x squared
    fDen      : LREAL;                  // 拟合分母 n*Σx² − (Σx)²（前判零）/ Fit denominator, zero-guarded
    fYMean    : LREAL;                  // 有效样本均值 [EU] / Mean of valid samples
    fSStot    : LREAL;                  // 总离差平方和 [EU²] / Total sum of squares
    fSSres    : LREAL;                  // 残差平方和 [EU²] / Residual sum of squares
    fXi       : LREAL;                  // 当前样本横坐标 [s] / Current sample abscissa
    fYi       : LREAL;                  // 当前样本值工作副本 [EU] / Current sample working copy
    fYhat     : LREAL;                  // 当前样本拟合值 [EU] / Fitted value of the current sample
    fDev      : LREAL;                  // 残差工作量 [EU] / Residual working value
END_VAR
VAR CONSTANT
    DL_TSC_N_MIN     : INT   := 2;          // 最少有效样本数 [个] / Minimum valid sample count
    DL_TSC_INF_CAP   : LREAL := 1.0E30;     // 非有限值筛查幅值上限 / Non-finite magnitude screening cap
    DL_TSC_EPS       : LREAL := 1.0E-12;    // 浮点判零容差（分母/SStot 用）/ Float zero tolerance
    DL_TSC_CNT_LIMIT : INT   := 100000;     // nCount 合理上限，防开放数组误传巨大值 / Sane count cap for open arrays
END_VAR

(* —— 段 1｜输出安全预置：任何异常路径下输出必须确定（部分平台残留上次调用值） —— *)
(* Stage 1, safe preset: outputs deterministic on every path *)
FC_DL_TrendSlopeCalc := FALSE;
fSlope     := 0.0;
fIntercept := 0.0;
fR2        := 0.0;
nValid     := 0;
uErrorId   := 16#0005_0204;             // 缺省走「无拟合」故障码，成功路径末尾改写 / Default to no-fit code, rewritten on success

(* —— 段 2｜参数与数组域闸（覆盖参与换算的全部量，R151） —— *)
(* Stage 2, parameter and array gate *)
nHi := UPPER_BOUND(afY, 1) + 1;         // 开放数组元素数 [个] / Element count of the open array
IF nHi < DL_TSC_N_MIN THEN
    RETURN;                             // 数组本身不够两点：无拟合返回 / Array itself too small, return
END_IF
IF fDt <= 0.0 THEN
    RETURN;                             // 采样间隔非法：无拟合返回（防除零口径）
END_IF
nUse := nCount;
IF nUse > nHi THEN
    nUse := nHi;                        // 声明数超过数组维度按维度截断 / Declared count clamped to array size
END_IF
IF nUse > DL_TSC_CNT_LIMIT THEN
    nUse := DL_TSC_CNT_LIMIT;           // 声明数合理上限（防御开放数组误传）/ Sane upper cap
END_IF
IF nUse < DL_TSC_N_MIN THEN
    RETURN;                             // 有效声明样本不足：无拟合返回
END_IF

(* —— 段 3｜单遍累加（剔除非有限样本：x<>x 判 NaN、差值自反判 Inf、幅值兜底） —— *)
(* Stage 3, single pass accumulation with non-finite rejection *)
fSumX  := 0.0;
fSumY  := 0.0;
fSumXY := 0.0;
fSumX2 := 0.0;
nGood  := 0;
FOR i := 0 TO nUse - 1 DO
    fYi := afY[i];                      // 取样本（下标已由 nUse 钳位防越界）/ Fetch sample, index clamped by nUse
    IF (fYi <> fYi) OR (ABS(fYi) > DL_TSC_INF_CAP) OR ((fYi - fYi) <> 0.0) THEN
        uErrorId := 16#0005_0104;       // 信息级：剔除非有限样本（继续累加其余样本）
    ELSE
        fXi   := UDINT_TO_LREAL(UDINT#0 + INT_TO_UDINT(i)) * fDt;   // x = i*fDt（索引先转无符号再乘，防负偏）/ x equals index times fDt
        fSumX  := fSumX  + fXi;
        fSumY  := fSumY  + fYi;
        fSumXY := fSumXY + fXi * fYi;
        fSumX2 := fSumX2 + fXi * fXi;
        nGood  := nGood + 1;
    END_IF
END_FOR
nValid := nGood;
IF nGood < DL_TSC_N_MIN THEN
    RETURN;                             // 有限样本不足：无拟合返回
END_IF

(* —— 段 4｜一阶最小二乘闭式解（分母容差判零，禁 = 号比浮点） —— *)
(* Stage 4, closed-form first-order least squares with zero-guarded denominator *)
fDen := UDINT_TO_LREAL(UDINT#0 + INT_TO_UDINT(nGood)) * fSumX2 - fSumX * fSumX;
IF ABS(fDen) < DL_TSC_EPS THEN
    RETURN;                             // 横坐标退化（窗口时长近零）：无拟合返回
END_IF
fSlope     := (UDINT_TO_LREAL(UDINT#0 + INT_TO_UDINT(nGood)) * fSumXY - fSumX * fSumY) / fDen;   // 斜率（分母已闸）
fIntercept := (fSumY - fSlope * fSumX) / UDINT_TO_LREAL(UDINT#0 + INT_TO_UDINT(nGood));         // 截距（分母 nGood >= 2 恒非零）

(* —— 段 5｜拟合优度 R²（SStot 容差判零；常数窗 R² 置 0 并给信息码） —— *)
(* Stage 5, goodness of fit with degenerate-window guard *)
fYMean := fSumY / UDINT_TO_LREAL(UDINT#0 + INT_TO_UDINT(nGood));
fSStot := 0.0;
fSSres := 0.0;
FOR i := 0 TO nUse - 1 DO
    fYi := afY[i];
    IF (fYi = fYi) AND (ABS(fYi) <= DL_TSC_INF_CAP) AND ((fYi - fYi) = 0.0) THEN   // 仅有效样本参与（与段 3 剔除判据同式）
        fYhat := fIntercept + fSlope * UDINT_TO_LREAL(UDINT#0 + INT_TO_UDINT(i)) * fDt;
        fDev   := fYi - fYhat;
        fSSres := fSSres + fDev * fDev;
        fDev   := fYi - fYMean;
        fSStot := fSStot + fDev * fDev;
    END_IF
END_FOR
IF fSStot < DL_TSC_EPS THEN
    fR2 := 0.0;                         // 常数窗：R² 无定义，置 0，斜率/截距仍有效
    IF uErrorId = 16#0000_0000 THEN
        uErrorId := 16#0005_0304;       // 信息级：常数窗退化（仅在无剔除码时覆盖，剔除码优先保留）
    END_IF
ELSE
    fR2 := 1.0 - fSSres / fSStot;       // R² 换算（分母已闸）
    IF fR2 < 0.0 THEN
        fR2 := 0.0;                     // 数值抖动下限钳位 / Clamp below-zero numerical noise
    END_IF
    IF fR2 > 1.0 THEN
        fR2 := 1.0;                     // 上限钳位 / Upper clamp
    END_IF
END_IF

(* —— 段 6｜成功出口：拟合有效 —— *)
(* Stage 6, success outlet *)
FC_DL_TrendSlopeCalc := TRUE;

END_FUNCTION
