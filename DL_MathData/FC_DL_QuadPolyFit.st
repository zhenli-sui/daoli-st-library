(*
  ==================================================================
  组件名 Component  : FC_DL_QuadPolyFit
  分类   Category   : DL_MathData
  版本   Version    : 1.0.1
  功能   Purpose    : 二次多项式最小二乘拟合 y = a0 + a1*x + a2*x²：构造 3×3
                      正规方程（Σ 0~4 阶矩 + 0~2 阶矩与 y 的混合矩），列主元
                      Gauss 消元求解。主元 |p| < 1E-10 判奇异：不输出系数、
                      bValid=FALSE、码 03（不静默给退化系数）。三重 FOR 均
                      以常量封顶（消元 2 轮 × 选行 3 行 × 回代 3 元）。
  来源   Source     : t2-1-lgf-math（数学族：正规方程 + 列主元消元为公开
                      数值方法口径，实现零源码复制）
  互引   Cross-ref  : FC_DL_LinearRegression2Var（同族低阶拟合原子，本件为其
                      二次扩展，共用「矩累加 + 正规方程」方法论）
  平台   Platform   : 纯 IEC 61131-3 四则 + ABS/TRUNC，三平台通用
  依赖   Depends    : 无 DL_ 内部依赖；无标准库
  设计偏差 Deviation: nCount > 数组实际长度时按长度钳位接管（同族口径，头注
                      声明，不静默越界，见码位反证）；y = a0+a1x+a2x² 系数
                      排序为「常数项在前」，返回值 = fA0（名实双出口）。
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 点数闸 + 元素级非有限闸 + 矩溢出非有限复核 +
                      主元闸（禁除以近零）/R5 全变量双语同行注释
                      R6 纯函数无状态机（CASE 不适用）/R7 无定时器与沿检测
                      R8 阈值与循环界全常量化
  错误码 Codes      : 01【失效级】点数不足（钳位后 nCount < 3），返回 0
                      02【失效级】任一 x/y 非有限或矩累加溢出为非有限
                      03【失效级】正规方程奇异（列主元 < 1E-10），不输出系数
  码位反证 Note     : 01/02/03 分立依据（R90）：01 在计数面、02 在数据面、
                      03 在数值结构面可观测；03 若并入 02，则「给不给退化
                      系数」这一行为差异将不可观测，故必须分立。
  验收   Acceptance : V1 完美 y=x² 采样 → a2≈1，a0/a1≈0 ｜ V2 2 点 → 码 01
                      ｜ V3 含 NaN → 码 02 ｜ V4 全部 x 相同（奇异）→ 码 03
                      ｜ V4b 仅两个相异 x（秩 2，舒尔补奇异）→ 码 03（v1.0.1）
                      ｜ V5 带噪数据 → 残差递减于线性拟合
  变更   Revision   : 2026-11-22  v1.0.0  R66 首版（编码阶段批 2 序 6）
                      2026-11-22  v1.0.1  R67 点修（M2+L1）：段 7 回代前补
                      舒尔补主元闸 aM[2,2]（两相异 x 值正规方程秩 2 场景，
                      除零 NaN/Inf 原错归码 02 → 提前归码 03）；段 4 ABS 溢
                      出复核由 s4/t2 扩展至 s1/s2/s3/t0/t1 全部矩量。
  ==================================================================
*)
FUNCTION FC_DL_QuadPolyFit : LREAL
VAR_INPUT
    aX     : ARRAY[*] OF LREAL;  // 自变量数组 [物理单位] / the abscissa array
    aY     : ARRAY[*] OF LREAL;  // 因变量数组 [物理单位] / the ordinate array
    nCount : UDINT;              // 参与拟合点数 [个]，超出数组长度按长度钳位 / the sample count, clamped to the array length
END_VAR
VAR_OUTPUT
    fA0    : LREAL;  // 拟合系数常数项 [物理单位]（y = a0 + a1*x + a2*x²）/ the constant coefficient
    fA1    : LREAL;  // 拟合系数一次项 [斜率] / the linear coefficient
    fA2    : LREAL;  // 拟合系数二次项 [1/斜率单位] / the quadratic coefficient
    bValid : BOOL;   // 系数可用标志 [-] / the coefficients usable flag
    nErrId : UDINT;  // 错误码，0=正常，01/02/03 见头注 [码] / the error code [code]
END_VAR
VAR
    s0     : LREAL;  // Σx^0 矩 [个] / the zeroth moment
    s1     : LREAL;  // Σx^1 矩 / the first moment
    s2     : LREAL;  // Σx^2 矩 / the second moment
    s3     : LREAL;  // Σx^3 矩 / the third moment
    s4     : LREAL;  // Σx^4 矩 / the fourth moment
    t0     : LREAL;  // Σy 矩 [物理单位] / the y moment
    t1     : LREAL;  // Σxy 矩 / the xy moment
    t2     : LREAL;  // Σx²y 矩 / the x squared y moment
    fx     : LREAL;  // 当前 x 工作寄存器 / the current x working register
    fy     : LREAL;  // 当前 y 工作寄存器 / the current y working register
    fx2    : LREAL;  // 当前 x² 工作寄存器 / the current x squared register
    aM     : ARRAY[0..2, 0..2] OF LREAL; // 正规方程系数矩阵 / the normal equation coefficient matrix
    aR     : ARRAY[0..2] OF LREAL;       // 正规方程右端向量 / the normal equation right hand vector
    aSol   : ARRAY[0..2] OF LREAL;       // 解向量工作寄存器 / the solution working vector
    uUsed  : UDINT;  // 钳位后实际点数 [个] / the used count after clamping
    uLenX  : UDINT;  // aX 实际长度 [个] / the actual length of aX
    uLenY  : UDINT;  // aY 实际长度 [个] / the actual length of aY
    uLen   : UDINT;  // 双数组共同安全长度 [个] / the common safe length
    i      : UDINT;  // 采样累加循环变量 / the accumulation loop index
    k      : DINT;   // 消元主轮变量，0~1 / the elimination pass index
    p      : DINT;   // 选主元行扫描变量 / the pivot row scan index
    r      : DINT;   // 消元行扫描变量 / the elimination row scan index
    c      : DINT;   // 消元列扫描变量 / the elimination column scan index
    fPivot : LREAL;  // 当轮主元值 / the current pivot value
    iMax   : DINT;   // 当轮主元所在行 / the pivot row of this pass
    fFac   : LREAL;  // 消元因子 / the elimination factor
    fTmp   : LREAL;  // 行交换临时量 / the row swap temporary
END_VAR
VAR CONSTANT
    QPF_PIV_MIN   : LREAL := 1.0E-10;             // 主元奇异阈值 [无量纲] / the singular pivot threshold
    QPF_PTS_MIN   : UDINT := UDINT#3;             // 二次拟合最少点数 [个] / the minimum points for a quadratic fit
    QPF_FIN_MAX   : LREAL := 1.7976931348623157E308; // LREAL 有限上限 / the finite LREAL limit
    QPF_ELIM_PASS : DINT := 2;                    // 消元主轮数（3×3 方程组）/ the elimination passes for a 3 by 3 system
    QPF_DIM       : DINT := 3;                    // 方程组维数 / the system dimension
    QPF_ERR_NONE  : UDINT := 16#0000_0000;        // 无错误 [码] / no error [code]
    QPF_ERR_PTS   : UDINT := 16#0000_0001;        // 码 01：点数不足 / code 01, too few points
    QPF_ERR_NAN   : UDINT := 16#0000_0002;        // 码 02：非有限 / code 02, non finite
    QPF_ERR_SING  : UDINT := 16#0000_0003;        // 码 03：奇异 / code 03, singular
END_VAR

// 段 1｜输出预置 / segment 1, preset the outputs
FC_DL_QuadPolyFit := 0.0;  // 失效缺省返回 0（=fA0 缺省）/ fault default returns zero
fA0    := 0.0;             // 系数预置 0（奇异不输出退化系数，头注口径）/ preset zero, no degenerate coefficients on singularity
fA1    := 0.0;
fA2    := 0.0;
bValid := FALSE;           // 预置不可用 / preset unusable
nErrId := QPF_ERR_NONE;    // 预置无错误 / preset no error
s0 := 0.0; s1 := 0.0; s2 := 0.0; s3 := 0.0; s4 := 0.0;  // 矩累加器清零 / clear the moment accumulators
t0 := 0.0; t1 := 0.0; t2 := 0.0;                        // 混合矩累加器清零 / clear the mixed moment accumulators

// 段 2｜数组长度闸与点数闸（结构 RETURN 早退）/ segment 2, the length and count gates
IF UPPER_BOUND(aX, 1) >= 0 THEN                          // 防御性变长上界检查 / defensive bound check
    uLenX := DINT_TO_UDINT(1 + UPPER_BOUND(aX, 1) - LOWER_BOUND(aX, 1));  // aX 长度 / the aX length
ELSE
    uLenX := UDINT#0;
END_IF
IF UPPER_BOUND(aY, 1) >= 0 THEN
    uLenY := DINT_TO_UDINT(1 + UPPER_BOUND(aY, 1) - LOWER_BOUND(aY, 1));  // aY 长度 / the aY length
ELSE
    uLenY := UDINT#0;
END_IF
IF uLenX < uLenY THEN                                    // 双数组取共同安全长度 / the common safe length
    uLen := uLenX;
ELSE
    uLen := uLenY;
END_IF
uUsed := nCount;                                         // 先取原始点数 / take the raw count
IF uUsed > uLen THEN
    uUsed := uLen;                                       // 超长钳位接管（头注偏差声明）/ clamp, documented deviation
END_IF
IF uUsed < QPF_PTS_MIN THEN                              // 点数不足（码 01）/ too few points, code 01
    nErrId := QPF_ERR_PTS;
    RETURN;
END_IF

// 段 3｜矩累加：元素级非有限闸（码 02）+ 下标闸已证（uUsed ≤ uLen）
//      segment 3, the moment accumulation with the per element finite gate
FOR i := 0 TO UDINT_TO_DINT(uUsed) - 1 DO                // 有界 FOR / the bounded loop
    fx := aX[i];                                         // 当前 x / the current x
    fy := aY[i];                                         // 当前 y / the current y
    IF (fx <> fx) OR (fy <> fy) OR (ABS(fx) > QPF_FIN_MAX) OR (ABS(fy) > QPF_FIN_MAX) THEN
        nErrId := QPF_ERR_NAN;                           // 码 02：非有限元素 / code 02, non finite element
        RETURN;                                          // 结构早退 / structural early return
    END_IF
    fx2 := fx * fx;                                      // 当前 x² / the current x squared
    s0 := s0 + 1.0;                                      // 零阶矩累加 / the zeroth moment
    s1 := s1 + fx;                                       // 一阶矩 / the first moment
    s2 := s2 + fx2;                                      // 二阶矩 / the second moment
    s3 := s3 + fx2 * fx;                                 // 三阶矩 / the third moment
    s4 := s4 + fx2 * fx2;                                // 四阶矩 / the fourth moment
    t0 := t0 + fy;                                       // Σy / the y moment
    t1 := t1 + fx * fy;                                  // Σxy / the xy moment
    t2 := t2 + fx2 * fy;                                 // Σx²y / the x squared y moment
END_FOR

// 段 4｜矩溢出非有限复核（码 02）：极端量级下累加可能溢出 Inf，先闸后入阵
//      segment 4, the overflow recheck on the moments before entering the matrix
IF (s0 <> s0) OR (s1 <> s1) OR (s2 <> s2) OR (s3 <> s3) OR (s4 <> s4)
   OR (t0 <> t0) OR (t1 <> t1) OR (t2 <> t2)
   OR (ABS(s1) > QPF_FIN_MAX) OR (ABS(s2) > QPF_FIN_MAX)     // v1.0.1 扩展 / extended in v1.0.1
   OR (ABS(s3) > QPF_FIN_MAX) OR (ABS(s4) > QPF_FIN_MAX)     // v1.0.1 扩展 / extended in v1.0.1
   OR (ABS(t0) > QPF_FIN_MAX) OR (ABS(t1) > QPF_FIN_MAX)     // v1.0.1 扩展 / extended in v1.0.1
   OR (ABS(t2) > QPF_FIN_MAX) THEN
    nErrId := QPF_ERR_NAN;
    RETURN;
END_IF

// 段 5｜构造 3×3 正规方程 / segment 5, build the 3 by 3 normal equations
aM[0,0] := s0;  aM[0,1] := s1;  aM[0,2] := s2;           // 第一行 [a0 系数] / the first row
aM[1,0] := s1;  aM[1,1] := s2;  aM[1,2] := s3;           // 第二行 [a1 系数] / the second row
aM[2,0] := s2;  aM[2,1] := s3;  aM[2,2] := s4;           // 第三行 [a2 系数] / the third row
aR[0] := t0;  aR[1] := t1;  aR[2] := t2;                 // 右端向量 / the right hand side

// 段 6｜列主元 Gauss 消元（常量封顶双重 FOR）/ segment 6, column pivoted elimination
FOR k := 0 TO QPF_ELIM_PASS - 1 DO                       // 逐主轮 / pass by pass
    fPivot := ABS(aM[k,k]);                              // 初选对角元 / seed with the diagonal
    iMax := k;                                           // 初选行 / the seeded row
    FOR p := k + 1 TO QPF_DIM - 1 DO                     // 列内选主元 / the column pivot scan
        IF ABS(aM[p,k]) > fPivot THEN
            fPivot := ABS(aM[p,k]);                      // 更大主元 / the larger pivot
            iMax := p;                                   // 主元行 / the pivot row
        END_IF
    END_FOR
    IF fPivot < QPF_PIV_MIN THEN                         // 主元闸（码 03）：禁除以近零 / the pivot gate
        nErrId := QPF_ERR_SING;
        RETURN;                                          // 不输出系数（头注口径）/ no coefficients published
    END_IF
    IF iMax <> k THEN                                    // 行交换 / the row swap
        FOR c := 0 TO QPF_DIM - 1 DO                     // 交换系数行 / swap the coefficient row
            fTmp := aM[k,c];  aM[k,c] := aM[iMax,c];  aM[iMax,c] := fTmp;
        END_FOR
        fTmp := aR[k];  aR[k] := aR[iMax];  aR[iMax] := fTmp;  // 交换右端 / swap the right hand side
    END_IF
    FOR r := k + 1 TO QPF_DIM - 1 DO                     // 消元行扫描 / the elimination row scan
        fFac := aM[r,k] / aM[k,k];                       // 除数 = 主元，已闸 ≥ 1E-10 / the divisor is the gated pivot
        FOR c := k TO QPF_DIM - 1 DO                     // 行内消元 / the in row elimination
            aM[r,c] := aM[r,c] - fFac * aM[k,c];
        END_FOR
        aR[r] := aR[r] - fFac * aR[k];                   // 右端同步消元 / eliminate the right hand side too
    END_FOR
END_FOR

// 段 7｜回代前舒尔补主元闸（v1.0.1）：消元主轮仅覆盖第 0/1 列，aM[2,2] 为舒
//      尔补未经闸——两个相异 x 值（正规方程秩 2，传感器两态卡值可达）时
//      aM[2,2]=0，回代除零出 NaN/Inf 原落段 8 码 02，与头注码 03（奇异）
//      归因错位，故回代前按码 03 提前拦截
//      segment 7, the Schur complement pivot gate before back substitution
IF ABS(aM[2,2]) < QPF_PIV_MIN THEN                        // 舒尔补主元闸（双精度口径，阈同主元闸）/ the Schur complement pivot gate
    nErrId := QPF_ERR_SING;                               // 码 03：正规方程秩 2 奇异 / code 03, rank two singular
    RETURN;                                               // 不输出系数（bValid 段 1 已预置 FALSE）/ no coefficients published
END_IF
aSol[2] := aR[2] / aM[2,2];                              // a2 回代解（舒尔补已闸）/ the quadratic unknown, Schur complement gated
aSol[1] := (aR[1] - aM[1,2] * aSol[2]) / aM[1,1];        // a1 回代解 / the linear unknown
aSol[0] := (aR[0] - aM[0,1] * aSol[1] - aM[0,2] * aSol[2]) / aM[0,0];  // a0 回代解 / the constant unknown

// 段 8｜解的非有限复核（码 02）与出口 / segment 8, the solution finiteness recheck and exit
IF (aSol[0] <> aSol[0]) OR (aSol[1] <> aSol[1]) OR (aSol[2] <> aSol[2])
   OR (ABS(aSol[2]) > QPF_FIN_MAX) THEN
    nErrId := QPF_ERR_NAN;                               // 极端病态下回代仍可能溢出 / the substitution can still overflow in extreme ill conditioning
    RETURN;
END_IF
fA0 := aSol[0];                                          // 发布常数项 / publish the constant
fA1 := aSol[1];                                          // 发布一次项 / publish the linear term
fA2 := aSol[2];                                          // 发布二次项 / publish the quadratic term
bValid := TRUE;                                          // 系数可用 / the coefficients are usable
FC_DL_QuadPolyFit := fA0;                                // 返回值 = fA0（R191 名实双出口，头注偏差声明）/ the return mirrors fA0
END_FUNCTION
