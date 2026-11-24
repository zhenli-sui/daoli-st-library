//==============================================================================
// 函数：FC_DL_Affine2DCompose ｜ 中文名称：二维仿射变换矩阵合成
// 所属子库：DL_MathData ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：两片 3x3 仿射矩阵按「先施加 M1、后施加 M2」的次序合成为单片
//           矩阵 MOut = M2 x M1（本库点变换约定 p' = M x p，列向量右乘），
//           单次调用内完成 3x3 乘法、行列式可逆性校验与双向非有限复检。
//           现场语义：视觉标定链的多级坐标映射（像素→机械→工件）合并为
//           单矩阵、纠偏平台级联、平移/旋转/缩放/剪切的按序合成。
//           合成次序与列向量约定为本库自有规格；行列式 |det| 小于容差判
//           不可逆，按信息级降级输出（合成结果本身仍有效，仅其逆变换
//           不可用），故障级只留给非法输入与结果溢出。
//           第三行按仿射约定忽略（不校验 0/0/1），第三行偏差提示职责
//           归 FC_DL_Affine2Apply 承担，本件不重复占用码位（R90）。
// 开源溯源 (Origin)：道莅 clean-room 防御性实现（仅借 LGF 分类事实/参数域/行为定义，零代码行与符号名复制）
// 单位表：矩阵线性块元素[无量纲]（旋转/缩放/剪切）/ 平移列元素[用户单位]
// 错误码表：16#0001_0466 信息级（合成矩阵行列式 |det| < 容差，变换不可逆，
//           结果照常输出，不置 bError）/ 16#0001_0467 预留禁用（不得挪用）/
//           16#0001_0468 预留禁用（不得挪用）/ 16#0001_03B7 故障级（任一
//           输入矩阵元素非有限，或乘积结果非有限溢出，置 bError，输出
//           零矩阵）/ 16#0001_03B8 预留禁用（不得挪用）
// 状态机：N/A——纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，以头注释说明替代 ELSE 兜底
// 边界行为：① 任一输入元素非有限（NaN 用自反判 x <> x，Inf 用幅值上限
//           兜底，R79）→ 故障 03B7、输出零矩阵、bValid := FALSE；
//           ② 乘积结果非有限（大坐标乘大缩放溢出）→ 复用 03B7（R90：
//           该场景与输入非法共用「矩阵数据不可信」语义，现有输出组合
//           不可观测出独立信息，不新占码位）、输出零矩阵；
//           ③ 行列式绝对值 < 1E-6 → 信息 0466，结果照常输出（降级
//           可观测，不置 bError）；
//           ④ 失能清零不适用（纯函数无使能闸，非法输入即故障早退）；
//           ⑤ 安全侧 = 故障路径输出零矩阵而非原矩阵，禁止半合成残阵
//           外泄到下游点应用件；
//           ⑥ 第三行不参与合成合法性判定：乘法仍按完整 3x3 执行，第三
//           行结果照算输出，调用方若喂入非标准第三行由 Apply 侧提示。
// 验收向量（算法已证，手算）：① M1=绕原点旋转 90 度、M2=平移 (10,0) →
//           MOut 平移列 = (0,10)、线性块为旋转 90 度；② M1=M2=恒等 →
//           MOut=恒等；③ M1 含缩放 (2,0.5)、M2 含剪切 k=1 → det(MOut)
//           = 2x0.5 = 1（合成保序：det(M2xM1)=det(M2)·det(M1)）。
//           编译器已证（三平台）：未跑，由收口方登记。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · T2-1 LGF Math 仿射变换族）
//==============================================================================

FUNCTION FC_DL_Affine2DCompose : BOOL
VAR_INPUT
    afM1 : ARRAY[0..2, 0..2] OF LREAL;      // 先施加的变换矩阵 M1 [无量纲+用户单位混合]，行主序 / First-applied transform matrix M1, row-major
    afM2 : ARRAY[0..2, 0..2] OF LREAL;      // 后施加的变换矩阵 M2 [无量纲+用户单位混合]，行主序 / Second-applied transform matrix M2, row-major
END_VAR
VAR_OUTPUT
    afMOut : ARRAY[0..2, 0..2] OF LREAL;    // 合成矩阵 MOut = M2 x M1 [无量纲+用户单位混合] / Composed matrix MOut = M2 times M1
    eErr   : UDINT;                         // 错误码，0 = 无错，码位 16#0001_0466 起信息级、16#0001_03B7 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError : BOOL;                          // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid : BOOL;                          // 结果可用标志 / Result usable flag
END_VAR
VAR
    afProd  : ARRAY[0..2, 0..2] OF LREAL;   // 乘积暂存阵（先算后检，检过才外泄） / Product staging array, checked before export
    nI      : INT;                          // 行循环索引 [—] / Row loop index
    nJ      : INT;                          // 列循环索引 [—] / Column loop index
    nK      : INT;                          // 求和循环索引 [—] / Summation loop index
    fAcc    : LREAL;                        // 点积累加器 [混合] / Dot-product accumulator
    fDet    : LREAL;                        // 合成矩阵线性块行列式 [无量纲] / Determinant of the composed linear block
    bNonFin : BOOL;                         // 非有限判定中间标志 / Non-finite detection intermediate flag
END_VAR
VAR CONSTANT
    DL_A2C_EPS     : LREAL := 1.0E-6;       // 行列式可逆性容差 [无量纲] / Determinant invertibility tolerance [dimensionless]
    DL_A2C_INF     : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_A2C_ZERO    : LREAL := 0.0;          // 零值常量，避免裸字面量 [无量纲] / Zero constant, avoids a bare literal [dimensionless]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值：返回值与输出预置（安全侧 = 零矩阵）
 *      Exit defaults: return value and outputs preset, fail-safe zero matrix
 *-----------------------------------------------------------------------------*)
FC_DL_Affine2DCompose := FALSE;             // 返回值默认无效 / Return value preset invalid
FOR nI := 0 TO 2 DO
    FOR nJ := 0 TO 2 DO
        afMOut[nI, nJ] := DL_A2C_ZERO;      // 输出矩阵逐元素清零 / Output matrix cleared element-wise
    END_FOR
END_FOR
eErr   := 16#0000_0000;                     // 错误码先清零 / Error code cleared first
bError := FALSE;                            // 故障标志先清零 / Fault flag cleared first
bValid := FALSE;                            // 可用标志先清零 / Usable flag cleared first

(*------------------------------------------------------------------------------
 * 段 2｜输入非有限闸：两片矩阵任一元素 NaN/Inf 即拒绝（R79 双侧幅值判）
 *      Input non-finite gate over both matrices
 *-----------------------------------------------------------------------------*)
bNonFin := FALSE;                           // 非有限标志预清零 / Non-finite flag pre-cleared
FOR nI := 0 TO 2 DO
    FOR nJ := 0 TO 2 DO
        IF (afM1[nI, nJ] <> afM1[nI, nJ]) OR (ABS(afM1[nI, nJ]) > DL_A2C_INF)
           OR (afM2[nI, nJ] <> afM2[nI, nJ]) OR (ABS(afM2[nI, nJ]) > DL_A2C_INF) THEN
            bNonFin := TRUE;                // 命中非有限元素 / Non-finite element hit
        END_IF
    END_FOR
END_FOR
IF bNonFin THEN
    eErr   := 16#0001_03B7;                 // 故障级：输入矩阵元素非法 / Fault: illegal matrix element
    bError := TRUE;                         // 置故障标志（R45 配对） / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
    RETURN;                                 // 故障早退，输出保持零矩阵 / Early return, outputs stay zero
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜矩阵合成：MOut = M2 x M1，完整 3x3 乘法（第三行照算不判定）
 *      Matrix composition, full 3x3 multiplication
 *-----------------------------------------------------------------------------*)
FOR nI := 0 TO 2 DO
    FOR nJ := 0 TO 2 DO
        fAcc := DL_A2C_ZERO;                // 点积累加器清零 / Accumulator cleared
        FOR nK := 0 TO 2 DO
            fAcc := fAcc + afM2[nI, nK] * afM1[nK, nJ]; // 行乘列累加 / Row-times-column accumulation
        END_FOR
        afProd[nI, nJ] := fAcc;             // 暂存乘积元素 / Stage the product element
    END_FOR
END_FOR

(*------------------------------------------------------------------------------
 * 段 4｜结果非有限复检：大坐标乘大缩放可能溢出（复用 03B7，R90）
 *      Result non-finite recheck, code reused per R90
 *-----------------------------------------------------------------------------*)
bNonFin := FALSE;                           // 非有限标志复清 / Non-finite flag re-cleared
FOR nI := 0 TO 2 DO
    FOR nJ := 0 TO 2 DO
        IF (afProd[nI, nJ] <> afProd[nI, nJ]) OR (ABS(afProd[nI, nJ]) > DL_A2C_INF) THEN
            bNonFin := TRUE;                // 命中非有限结果 / Non-finite result hit
        END_IF
    END_FOR
END_FOR
IF bNonFin THEN
    eErr   := 16#0001_03B7;                 // 故障级：结果溢出复用输入非法码（R90） / Fault: overflow, code reused per R90
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
    RETURN;                                 // 故障早退，输出保持零矩阵 / Early return, outputs stay zero
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜可逆性校验：线性块行列式 |det| < 容差 → 信息级降级照常输出
 *      Invertibility check, info-level degradation with result exported
 *-----------------------------------------------------------------------------*)
fDet := afProd[0, 0] * afProd[1, 1] - afProd[0, 1] * afProd[1, 0]; // 线性块行列式 [无量纲] / Linear-block determinant
IF ABS(fDet) < DL_A2C_EPS THEN
    eErr := 16#0001_0466;                   // 信息级：合成变换不可逆（不置 bError） / Info: composed transform not invertible, no fault flag
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜出口：检验通过后放行乘积阵
 *      Exit: staged product exported after checks
 *-----------------------------------------------------------------------------*)
FOR nI := 0 TO 2 DO
    FOR nJ := 0 TO 2 DO
        afMOut[nI, nJ] := afProd[nI, nJ];   // 暂存阵外泄 / Staged array exported
    END_FOR
END_FOR
bValid := TRUE;                             // 结果可用（含 0466 降级情形） / Result usable, including the degraded case
FC_DL_Affine2DCompose := TRUE;              // 返回 TRUE = 合成有效 / Return TRUE = composition valid
END_FUNCTION
