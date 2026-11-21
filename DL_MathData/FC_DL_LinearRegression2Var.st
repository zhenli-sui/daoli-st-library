(*
  FC_DL_LinearRegression2Var  —  二元最小二乘回归（3x3 正规方程）/ Two-variable least-squares linear regression
  分类 Category : DL_MathData
  码位 Code     : 16#05_0_02
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-math — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : clean-room 实现，最小二乘正规方程公开数学语义，未复制任何源码行（命名对齐既有件 FC_DL_LinearScale）
  功能 Function : 1) 由 (x1, x2, y) 样本集解 3x3 正规方程（Cramer 法则），输出双斜率 fK1/fK2、截距 fB 与拟合优度 fR2；
                  2) 共线性判据：|r12| 越限即判「不可辨识」，不输出斜率（防病态解误导）；
                  3) 每个样本做非有限值（NaN/Inf）预筛，任一非法则整批无效。
  边界 Boundary : ① nSampleCount < 4 判样本不足置码（3 参数 3 方程不可给 R²），不进入求解；
                  ② nSampleCount 超数组上界判组态错置码（防越界，循环带上限守卫）；
                  ③ |r12| > fCollinearLimit 置 bIdentifiable := FALSE 且斜率/截距/R² 全 0（不给看似可信数字）；
                  ④ 行列式 |det| < 1E-12 判退化置 bDegenerate；
                  ⑤ SStot 近零（y 全等）时 R² 置 0 并置信息码（防除零）；
                  ⑥ 解除式自证：bIdentifiable/bDegenerate 为每调用重算量，下一调用条件消失即自动解除（无锁存）。
  依赖 Depends  : 仅 Standard.library（ABS/SQRT）；参考对齐 FC_DL_LinearScale（已注册，仅命名体例）
  码表 Error codes（本件格 05_0_02，子码步进 +0x100）:
    16#0005_0102 信息级：共线性越限，判不可辨识（bIdentifiable = FALSE）
    16#0005_0202 故障级：样本不足 nSampleCount < 4 或超数组上界
    16#0005_0302 故障级：样本含非有限值（NaN/Inf），整批无效
    16#0005_0402 故障级：正规方程退化（行列式 |det| < 1E-12）
    16#0005_0502 信息级：SStot 近零，R² 置 0（y 全等，拟合优度无定义）

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

FUNCTION FC_DL_LinearRegression2Var : BOOL
VAR_INPUT
    afX1           : ARRAY[0..63] OF REAL;   // 样本 x1 组 [工程量] / Sample array x1
    afX2           : ARRAY[0..63] OF REAL;   // 样本 x2 组 [工程量] / Sample array x2
    afY            : ARRAY[0..63] OF REAL;   // 样本 y 组 [工程量] / Sample array y
    nSampleCount   : INT;                    // 有效样本数 [个]，域 4..64 / Valid sample count
    fCollinearLimit: REAL := 0.995;          // 共线性判据上限 |r12|，域 0..1 / Collinearity limit on |r12|
END_VAR
VAR_OUTPUT
    fK1            : REAL;                   // 回归斜率 1 [y 单位/x1 单位] / Regression slope k1
    fK2            : REAL;                   // 回归斜率 2 [y 单位/x2 单位] / Regression slope k2
    fB             : REAL;                   // 回归截距 [y 单位] / Regression intercept
    fR2            : REAL;                   // 拟合优度 R² [无量纲，0..1] / Coefficient of determination
    bIdentifiable  : BOOL;                   // 可辨识标志（共线性未越限）/ Identifiable flag
    bDegenerate    : BOOL;                   // 正规方程退化标志 / Degenerate normal-equation flag
    nErrId         : UDINT;                  // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    rN, rSx1, rSx2, rSy      : LREAL;        // 计数与一次矩累加器 / Count and first-moment accumulators
    rS11, rS22, rS12         : LREAL;        // 二次矩累加器 / Second-moment accumulators
    rS1y, rS2y, rSyy         : LREAL;        // 交叉矩累加器 / Cross-moment accumulators
    rM1, rM2, rMy            : LREAL;        // 均值 x1/x2/y / Means of x1, x2 and y
    rV1, rV2, rC12           : LREAL;        // 方差与协方差（中心化）/ Central variances and covariance
    rR12, rDet, rDen         : LREAL;        // 相关系数/行列式/求根分母 / Correlation, determinant, solve denominator
    rSsTot, rSsRes, rYhat    : LREAL;        // 总平方和/残差平方和/拟合值 / Total SS, residual SS, fitted value
    rDx1, rDx2, rDy          : LREAL;        // 单样本临时量（LREAL 宽域防累加误差）/ Per-sample scratch
    bFin                     : BOOL;         // 非有限值筛查标志 / Non-finite screening flag
    k                        : INT;          // 循环计数器 / Loop counter
END_VAR
VAR CONSTANT
    nMaxSmp   : INT    := 64;      // 数组上界 [个] / Array upper bound
    rDetFloor : LREAL  := 1.0E-12; // 行列式退化阈值 / Degenerate determinant threshold
    rSsFloor  : LREAL  := 1.0E-12; // SStot 近零阈值 / Near-zero SStot threshold
    rFinLim   : LREAL  := 1.0E30;  // 非有限值筛查幅值上限 / Non-finite screening magnitude cap
END_VAR

(* —— 段 1：输出缺省与样本数闸（纯函数，每调用重算） —— *)
fK1 := 0.0;  fK2 := 0.0;  fB := 0.0;  fR2 := 0.0;      // 输出缺省全 0（不给看似可信数字）
bIdentifiable := FALSE;                                  // 缺省不可辨识（安全侧）
bDegenerate   := FALSE;                                  // 缺省未退化
nErrId := 16#0000_0000;                                  // 事件码缺省无事件
FC_DL_LinearRegression2Var := FALSE;                     // 返回值缺省失败

IF (nSampleCount < 4) OR (nSampleCount > nMaxSmp) THEN
    nErrId := 16#0005_0202;                              // 故障级：样本不足或超数组上界
    RETURN;                                                // 不进入求解
END_IF

(* —— 段 2：累加矩 + 非有限值整批筛查（NaN 用 x<>x 自反判定，Inf 用幅值上限兜） —— *)
rN := LREAL(nSampleCount);
FOR k := 0 TO (nSampleCount - 1) DO
    bFin := (afX1[k] = afX1[k]) AND (afX2[k] = afX2[k]) AND (afY[k] = afY[k])
            AND (ABS(afX1[k]) < rFinLim) AND (ABS(afX2[k]) < rFinLim) AND (ABS(afY[k]) < rFinLim);
    IF NOT bFin THEN
        nErrId := 16#0005_0302;                          // 故障级：样本含非有限值，整批无效
        RETURN;                                            // 不污染统计
    END_IF
    rDx1 := LREAL(afX1[k]);  rDx2 := LREAL(afX2[k]);  rDy := LREAL(afY[k]);
    rSx1 := rSx1 + rDx1;  rSx2 := rSx2 + rDx2;  rSy := rSy + rDy;
    rS11 := rS11 + rDx1 * rDx1;  rS22 := rS22 + rDx2 * rDx2;
    rS12 := rS12 + rDx1 * rDx2;  rS1y := rS1y + rDx1 * rDy;  rS2y := rS2y + rDx2 * rDy;
    rSyy := rSyy + rDy * rDy;
END_FOR

(* —— 段 3：中心化方差/协方差与共线性判据 —— *)
rM1 := rSx1 / rN;  rM2 := rSx2 / rN;  rMy := rSy / rN;   // 均值（rN >= 4，无除零）
rV1 := rS11 - rSx1 * rM1;  rV2 := rS22 - rSx2 * rM2;  rC12 := rS12 - rSx1 * rM2;
IF (rV1 < rDetFloor) OR (rV2 < rDetFloor) THEN
    bDegenerate := TRUE;                                  // x1 或 x2 无离散：正规方程退化
    nErrId := 16#0005_0402;                               // 故障级：退化
    RETURN;
END_IF
rR12 := rC12 / SQRT(rV1 * rV2);                           // 相关系数（分母已闸）
IF ABS(rR12) > LREAL(fCollinearLimit) THEN
    nErrId := 16#0005_0102;                               // 信息级：共线性越限，判不可辨识
    bIdentifiable := FALSE;                               // 不输出斜率（防病态解误导）
    FC_DL_LinearRegression2Var := TRUE;                   // 求解已执行但结果判不可辨识
    RETURN;
END_IF

(* —— 段 4：3x3 正规方程 Cramer 求解（|det| < 1E-12 判退化） —— *)
rDet := rN * (rS11 * rS22 - rS12 * rS12)
      - rSx1 * (rSx1 * rS22 - rS12 * rSx2)
      + rSx2 * (rSx1 * rS12 - rS11 * rSx2);               // 3x3 行列式
IF ABS(rDet) < rDetFloor THEN
    bDegenerate := TRUE;                                  // 退化标志
    nErrId := 16#0005_0402;                               // 故障级：正规方程退化
    RETURN;
END_IF
fB  := REAL((rSy  * (rS11 * rS22 - rS12 * rS12)
           - rSx1 * (rS1y * rS22 - rS12 * rS2y)
           + rSx2 * (rS1y * rS12 - rS11 * rS2y)) / rDet); // 截距 b（第一列替换为 RHS 的行列式）
fK1 := REAL((rN   * (rS1y * rS22 - rS12 * rS2y)
           - rSy  * (rSx1 * rS22 - rS12 * rSx2)
           + rSx2 * (rSx1 * rS2y - rS1y * rSx2)) / rDet); // 斜率 k1（第二列替换为 RHS 的行列式）
fK2 := REAL((rN   * (rS11 * rS2y - rS1y * rS12)
           - rSx1 * (rSx1 * rS2y - rS1y * rSx2)
           + rSy  * (rSx1 * rS12 - rS11 * rSx2)) / rDet); // 斜率 k2（第三列替换为 RHS 的行列式）

(* —— 段 5：拟合优度 R²（SStot 近零防除零） —— *)
rSsTot := rSyy - rN * rMy * rMy;                          // 总平方和
IF rSsTot < rSsFloor THEN
    fR2 := 0.0;                                           // y 全等：R² 无定义，置 0 不给可信假象
    nErrId := 16#0005_0502;                               // 信息级：SStot 近零
ELSE
    rSsRes := 0.0;
    FOR k := 0 TO (nSampleCount - 1) DO
        rYhat := LREAL(fB) + LREAL(fK1) * LREAL(afX1[k]) + LREAL(fK2) * LREAL(afX2[k]);
        rSsRes := rSsRes + (LREAL(afY[k]) - rYhat) * (LREAL(afY[k]) - rYhat);
    END_FOR
    rDen := rSsTot;                                       // 分母已闸 > 1E-12
    fR2 := REAL(MAX(0.0, MIN(1.0, 1.0 - rSsRes / rDen))); // 钳到 0..1
END_IF

(* —— 段 6：出口标志与返回值 —— *)
bIdentifiable := TRUE;                                    // 走到此 = 共线性未越限且未退化
FC_DL_LinearRegression2Var := TRUE;                       // 求解成功

END_FUNCTION
