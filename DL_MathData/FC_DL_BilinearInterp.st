(*
  ==================================================================
  组件名 Component  : FC_DL_BilinearInterp
  分类   Category   : DL_MathData
  版本   Version    : 1.0.0
  功能   Purpose    : 双线性插值：在等距网格表上按 (fX, fY) 求插值。
                      越界策略=「钳位到边界单元并置码不静默」（头注定稿口径）：
                      fX/fY 超出 [fX0, fX0+(n-1)*d] 时钳到边界单元继续插值，
                      输出有效但带码 02；末端格点用 1E-9 容差处理防 i1 越界
                      一行（fU 恰好等于上界时 i0 退到 n-2、tx 收满 1.0，
                      n=1 退化为常量直通）。
  来源   Source     : t2-1-lgf-math（数学族：双线性插值为公开数值方法口径，
                      实现零源码复制）
  互引   Cross-ref  : FC_DL_InterpolateTable3D（同族三维插值原子，本件为其
                      二维退化对偶，可级联使用）
  平台   Platform   : 纯 IEC 61131-3 四则 + TRUNC，三平台通用
  依赖   Depends    : 无 DL_ 内部依赖；无标准库
  表格口径 Table    : aTable 为定长容量数组（NY_MAX × NX_MAX 见常量段），
                      实际使用 ny=nRows / nx=nCols 由输入给定，容量外元素
                      永不访问（下标闸先行）；行序 = [y 索引][x 索引]。
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 步距≤0 与行列数<1 配置闸 + 元素级非有限闸（含四角
                      值）+ 越界钳位显式置码 + 除法分母已闸
                      R5 全变量双语同行注释/R6 纯函数无状态机（CASE 不适用）
                      R7 无定时器与沿检测/R8 容差与容量常量化
  错误码 Codes      : 01【失效级】配置非法（nRows/nCols < 1 或步距 ≤ 0 或
                      行列数超容量），返回 0
                      02【信息级】fX/fY 越界已钳位到边界单元（输出有效）
                      03【失效级】任一输入或四角表值非有限，返回 0
  码位反证 Note     : 02 与 03 分立依据（R90）：02 时 bValid=TRUE 带码、
                      03 时 bValid=FALSE，双通道可唯一区分；01 与 03 分立：
                      01 在配置面可观测、03 在数据面可观测，入口不同。
  验收   Acceptance : V1 网格中心点 → 精确双线性值 ｜ V2 fX 超上界 → 钳边界
                      + 码 02 ｜ V3 fDx=0 → 码 01 ｜ V4 nCols=1 → y 向插值
                      常量直通 ｜ V5 表值 NaN → 码 03 ｜ V6 末端格点容差 →
                      不越界不置 02
  变更   Revision   : 2026-11-22  v1.0.0  R66 首版（编码阶段批 2 序 5）
  ==================================================================
*)
FUNCTION FC_DL_BilinearInterp : LREAL
VAR_INPUT
    aTable : ARRAY[0..BIL_NY_MAX - 1, 0..BIL_NX_MAX - 1] OF LREAL; // 容量网格表 [表值]（实际 ny/nx 由 nRows/nCols 给定，行序=[y][x]）/ the capacity grid table
    nRows  : UDINT;  // 实际行数（y 向格点数）[个]，≥1 / the actual rows, at least one
    nCols  : UDINT;  // 实际列数（x 向格点数）[个]，≥1 / the actual columns, at least one
    fX     : LREAL;  // 查询点 x 坐标 [物理单位同表] / the query x coordinate
    fY     : LREAL;  // 查询点 y 坐标 [物理单位同表] / the query y coordinate
    fX0    : LREAL;  // x 起始格点坐标 [物理单位同表] / the x grid origin
    fDx    : LREAL;  // x 步距 [物理单位同表]，须 > 0 / the x step, must be positive
    fY0    : LREAL;  // y 起始格点坐标 [物理单位同表] / the y grid origin
    fDy    : LREAL;  // y 步距 [物理单位同表]，须 > 0 / the y step, must be positive
END_VAR
VAR_OUTPUT
    bValid : BOOL;   // 输出可用标志（码 02 时仍 TRUE）[-] / the output usable flag, true also with code 02
    nErrId : UDINT;  // 错误码，0=正常，01/02/03 见头注 [码] / the error code [code]
END_VAR
VAR
    fU     : LREAL;  // x 向规格化浮点下标 [格] / the normalized floating x index [cell]
    fV     : LREAL;  // y 向规格化浮点下标 [格] / the normalized floating y index [cell]
    fXmax  : LREAL;  // x 上边界格点坐标 [物理单位] / the x upper boundary coordinate
    fYmax  : LREAL;  // y 上边界格点坐标 [物理单位] / the y upper boundary coordinate
    ix0    : UDINT;  // x 向左格点下标 [格] / the left x cell index
    ix1    : UDINT;  // x 向右格点下标 [格] / the right x cell index
    iy0    : UDINT;  // y 向下格点下标 [格] / the lower y cell index
    iy1    : UDINT;  // y 向上格点下标 [格] / the upper y cell index
    fTx    : LREAL;  // x 向格内分数 0~1 [-] / the in cell x fraction
    fTy    : LREAL;  // y 向格内分数 0~1 [-] / the in cell y fraction
    v00    : LREAL;  // 左下角值 [表值] / the lower left corner value
    v10    : LREAL;  // 右下角值 [表值] / the lower right corner value
    v01    : LREAL;  // 左上角值 [表值] / the upper left corner value
    v11    : LREAL;  // 右上角值 [表值] / the upper right corner value
    fRes   : LREAL;  // 插值结果工作寄存器 [表值] / the interpolation working register
END_VAR
VAR CONSTANT
    BIL_NY_MAX   : UDINT := 32;               // 容量行数上限 [行]（头注表格口径）/ the capacity row limit
    BIL_NX_MAX   : UDINT := 32;               // 容量列数上限 [列]（头注表格口径）/ the capacity column limit
    BIL_EPS      : LREAL := 1.0E-9;           // 末端格点容差 [格] / the end cell tolerance [cell]
    BIL_FIN_MAX  : LREAL := 1.7976931348623157E308; // LREAL 有限上限 [无量纲] / the finite LREAL limit
    BIL_ERR_NONE : UDINT := 16#0000_0000;     // 无错误 [码] / no error [code]
    BIL_ERR_CFG  : UDINT := 16#0000_0001;     // 码 01：配置非法 / code 01, illegal configuration
    BIL_ERR_CLAMP: UDINT := 16#0000_0002;     // 码 02：越界钳位（信息级）/ code 02, clamped, info level
    BIL_ERR_NAN  : UDINT := 16#0000_0003;     // 码 03：非有限 / code 03, non finite
END_VAR

// 段 1｜返回值与输出预置 / segment 1, preset the return and outputs
FC_DL_BilinearInterp := 0.0;  // 失效缺省返回 0 / fault default returns zero
bValid := FALSE;              // 预置不可用 / preset unusable
nErrId := BIL_ERR_NONE;       // 预置无错误 / preset no error

// 段 2｜配置闸（码 01，结构 RETURN 早退）：行列数 ≥1 且不超容量 + 双步距 > 0
//      segment 2, the configuration gate, dimensions inside capacity and positive steps
IF (nRows < UDINT#1) OR (nCols < UDINT#1) OR (nRows > BIL_NY_MAX) OR (nCols > BIL_NX_MAX)
   OR (fDx <= 0.0) OR (fDy <= 0.0) THEN
    nErrId := BIL_ERR_CFG;
    RETURN;
END_IF

// 段 3｜标量输入非有限闸（码 03）：查询点/原点/步距全套（R272 闸参数全覆盖）
//      segment 3, the scalar finiteness gate over every floating input
IF (fX <> fX) OR (fY <> fY) OR (fX0 <> fX0) OR (fY0 <> fY0)
   OR (ABS(fX) > BIL_FIN_MAX) OR (ABS(fY) > BIL_FIN_MAX)
   OR (ABS(fX0) > BIL_FIN_MAX) OR (ABS(fY0) > BIL_FIN_MAX) THEN
    nErrId := BIL_ERR_NAN;
    RETURN;
END_IF

// 段 4｜越界钳位：先算边界坐标再钳查询点，钳位即置码 02 不静默
//      segment 4, the range clamp with the explicit code, never silent
fXmax := fX0 + DINT_TO_LREAL(UDINT_TO_DINT(nCols) - 1) * fDx;   // x 上边界坐标 / the x upper boundary
fYmax := fY0 + DINT_TO_LREAL(UDINT_TO_DINT(nRows) - 1) * fDy;   // y 上边界坐标 / the y upper boundary
IF (fX < fX0) OR (fX > fXmax) OR (fY < fY0) OR (fY > fYmax) THEN
    nErrId := BIL_ERR_CLAMP;                                    // 码 02（信息级，bValid 仍 TRUE）/ code 02, still valid
END_IF
IF fX < fX0 THEN fX := fX0; END_IF                              // x 下钳 / clamp x low
IF fX > fXmax THEN fX := fXmax; END_IF                          // x 上钳 / clamp x high
IF fY < fY0 THEN fY := fY0; END_IF                              // y 下钳 / clamp y low
IF fY > fYmax THEN fY := fYmax; END_IF                          // y 上钳 / clamp y high

// 段 5｜规格化浮点下标：分母步距已闸 > 0 / segment 5, normalized indices, steps gated positive
fU := (fX - fX0) / fDx;                                         // x 浮点下标 [格] / the floating x index
fV := (fY - fY0) / fDy;                                         // y 浮点下标 [格] / the floating y index

// 段 6｜末端格点容差处理（防 i1 越界一行）+ n=1 退化闸，二者合一避免 UDINT 回绕：
//      fU 恰为上界时左格点退到 n-2、分数收满 1.0；n=1 时下标收 0、分数归零
//      segment 6, the end cell tolerance and the single cell degeneration, merged so no UDINT wraparound occurs
ix0 := DINT_TO_UDINT(LREAL_TO_DINT(TRUNC(fU)));                 // 截断得左格点（标准转换链）/ truncate to the left cell, standard conversion chain
iy0 := DINT_TO_UDINT(LREAL_TO_DINT(TRUNC(fV)));                // 截断得下格点 / truncate to the lower cell
IF nCols = UDINT#1 THEN                                         // 单列退化：常量直通 / the single column degeneration
    ix0 := UDINT#0;                                             // 下标收 0 / the index to zero
    fTx := 0.0;                                                 // 分数归零 → 只用左值 / the fraction to zero
ELSIF ix0 >= nCols - UDINT#1 THEN                               // 落在末端格点（含 1E-9 抖动）/ landed on the last cell
    ix0 := nCols - UDINT#2;                                     // 退到倒数第二格（n≥2 时安全）/ step back one cell, safe for n at least two
    fTx := 1.0;                                                 // 分数收满 = 右格点值 / full fraction picks the right value
ELSE
    fTx := fU - DINT_TO_LREAL(UDINT_TO_DINT(ix0));              // 格内分数 / the in cell fraction
END_IF
IF nRows = UDINT#1 THEN                                         // 单行退化 / the single row degeneration
    iy0 := UDINT#0;
    fTy := 0.0;
ELSIF iy0 >= nRows - UDINT#1 THEN
    iy0 := nRows - UDINT#2;
    fTy := 1.0;
ELSE
    fTy := fV - DINT_TO_LREAL(UDINT_TO_DINT(iy0));
END_IF

// 段 7｜右/上格点下标（段 6 已保证 ix0 ≤ nCols-2 或 ix0=0 且 nCols=1，ix1 恒 < nCols）
//      segment 7, the right and upper indices, proven inside the table by segment 6
IF ix0 >= nCols - UDINT#1 THEN                                  // 兜底（结构性不可达，留档）/ defensive, unreachable by construction
    ix1 := ix0;                                                 // 收敛为同格 / collapse to the same cell
ELSE
    ix1 := ix0 + UDINT#1;                                       // 正常右格点 / the normal right cell
END_IF
IF iy0 >= nRows - UDINT#1 THEN
    iy1 := iy0;
ELSE
    iy1 := iy0 + UDINT#1;
END_IF

// 段 8｜四角表值非有限闸（码 03）：下标闸已在段 6/7 完成（ix1<nCols，iy1<nRows）
//      segment 8, the four corner finiteness gate, index gates already proven
v00 := aTable[iy0, ix0];                                        // 左下角 / the lower left corner
v10 := aTable[iy0, ix1];                                        // 右下角 / the lower right corner
v01 := aTable[iy1, ix0];                                        // 左上角 / the upper left corner
v11 := aTable[iy1, ix1];                                        // 右上角 / the upper right corner
IF (v00 <> v00) OR (v10 <> v10) OR (v01 <> v01) OR (v11 <> v11)
   OR (ABS(v00) > BIL_FIN_MAX) OR (ABS(v10) > BIL_FIN_MAX)
   OR (ABS(v01) > BIL_FIN_MAX) OR (ABS(v11) > BIL_FIN_MAX) THEN
    nErrId := BIL_ERR_NAN;
    RETURN;
END_IF

// 段 9｜双线性合成（先 x 后 y，分数均在 [0,1] 域内，凸组合有界）
//      segment 9, the bilinear blend, all fractions inside zero to one
fRes := (1.0 - fTx) * v00 + fTx * v10;                          // y0 行内插 [表值] / the lower row blend
fRes := fRes * (1.0 - fTy) + ((1.0 - fTx) * v01 + fTx * v11) * fTy;  // 行间加权 / the row to row blend

// 段 10｜出口 / segment 10, exit
FC_DL_BilinearInterp := fRes;                                   // 发布插值结果 / publish the result
bValid := TRUE;                                                 // 结果可用（含码 02 场景）/ the result is usable, also with code 02
END_FUNCTION
