//==============================================================================
// 函数：FC_DL_Affine2DInvert ｜ 中文名称：二维仿射变换矩阵求逆
// 所属子库：DL_MathData ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：3x3 仿射矩阵求逆——线性块取 2x2 伴随/行列式法，平移列按
//           t' = -A^(-1) x t 反算；点变换约定沿用本库 p' = M x p（列向量
//           右乘、行主序存储）。与 FC_DL_Affine2DCompose / FC_DL_Affine2DApply
//           构成定义-应用-逆三元闭环。与 Compose 的「不可逆降级照算」策略
//           分立：本件不可逆时输出全零矩阵，禁止半逆残阵外泄（半逆会被
//           下游点应用件当成有效映射，标定链错位难查）。库内已有
//           FC_DL_Matrix3Inverse，但其行列式含第三行，与仿射语义（第三行
//           恒为 0/0/1）不等价，按「库内委托须等价」纪律不委托、就地实现。
// 开源溯源 (Origin)：道莅 clean-room 防御性实现（仅借 LGF 分类事实/参数域/行为定义，零代码行与符号名复制）
// 单位表：矩阵线性块元素[无量纲]（旋转/缩放/剪切）/ 平移列元素[用户单位] / 行列式[无量纲]
// 错误码表：16#0001_046F 信息级（线性块奇异 |det| 小于相对判据，不可逆，
//           输出全零矩阵，不置 bError）/ 16#0001_0470 预留禁用（不得挪用）/
//           16#0001_03BD 故障级（任一输入元素非有限，或求逆结果非有限
//           溢出，置 bError，输出全零矩阵）/ 16#0001_03BE 预留禁用（不得挪用）
// 状态机：N/A——纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，以头注释说明替代 ELSE 兜底
// 边界行为：① 任一输入元素非有限（NaN 用自反判 x <> x，Inf 用幅值上限
//           兜底，R79）→ 故障 03BD、afMInv 全 0、bValid := FALSE；
//           ② |det| 小于等于 fDetEps 乘线性块最大绝对值平方（相对判据，
//           R13 Matrix3Inverse 口径）→ 信息 046F、afMInv 全 0、bValid :=
//           FALSE——不可逆禁止半逆外泄，与 Compose 降级照算策略分立；
//           ③ 第三行不参与求逆（R90 家族）：行列式与逆只按 2x2 线性块
//           加平移列计算，输出第三行按输入第三行原样回填，不做 0/0/1
//           校验（偏差提示职责归 Apply 侧，本件不重复占码位）；
//           ④ fDetEps 非正 → 回退默认 1.0E-6（容差引脚自愈，不置错）；
//           ⑤ 求逆结果非有限（大坐标乘大缩放溢出）→ 复用 03BD（R90：
//           与输入非法共用「矩阵数据不可信」语义，现有输出组合不可观测
//           出独立信息，不新占码位）、afMInv 全 0；
//           ⑥ 安全侧 = 故障与不可逆路径输出全零矩阵而非原矩阵或残阵；
//           ⑦ 失能清零不适用（纯函数无使能闸，非法输入即故障早退）。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.1）
//==============================================================================
FUNCTION FC_DL_Affine2DInvert : BOOL
VAR_INPUT
    afM     : ARRAY[0..2, 0..2] OF LREAL;   // 待求逆仿射矩阵 M [无量纲+用户单位混合]，行主序 / Affine matrix M to invert, row-major
    fDetEps : LREAL := 1.0E-6;              // 相对奇异判据 [无量纲]，非正回退默认 / Relative singularity threshold, non-positive falls back to default
END_VAR
VAR_OUTPUT
    afMInv  : ARRAY[0..2, 0..2] OF LREAL;   // 逆矩阵 M^(-1) [无量纲+用户单位混合]，失败时全 0 / Inverse matrix, all zero on failure
    fDet    : LREAL;                        // 线性块行列式 [无量纲] / Determinant of the linear block
    eErr    : UDINT;                        // 错误码，0 = 无错，码位 16#0001_046F 起信息级、16#0001_03BD 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError  : BOOL;                         // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid  : BOOL;                         // 结果可用标志，不可逆与非有限路径显式 FALSE / Result usable flag, explicit FALSE on singular and non-finite paths
END_VAR
VAR
    nI      : INT;                          // 行循环索引 [—] / Row loop index
    nJ      : INT;                          // 列循环索引 [—] / Column loop index
    fMaxAbs : LREAL;                        // 线性块元素绝对值最大值 [无量纲] / Max absolute value of the linear block
    fAbsK   : LREAL;                        // 当前元素绝对值暂存 [无量纲] / Absolute value of the current element
    fEpsEff : LREAL;                        // 生效奇异判据 [无量纲] / Effective singularity threshold
    fInv00  : LREAL;                        // 逆线性块 (0,0) 元素暂存 [无量纲] / Inverse linear block element (0,0)
    fInv01  : LREAL;                        // 逆线性块 (0,1) 元素暂存 [无量纲] / Inverse linear block element (0,1)
    fInv10  : LREAL;                        // 逆线性块 (1,0) 元素暂存 [无量纲] / Inverse linear block element (1,0)
    fInv11  : LREAL;                        // 逆线性块 (1,1) 元素暂存 [无量纲] / Inverse linear block element (1,1)
    fInv02  : LREAL;                        // 逆平移列 x 分量暂存 [用户单位] / Inverse translation x component
    fInv12  : LREAL;                        // 逆平移列 y 分量暂存 [用户单位] / Inverse translation y component
    bNonFin : BOOL;                         // 非有限判定中间标志 / Non-finite detection intermediate flag
END_VAR
VAR CONSTANT
    DL_A2I_CODE_INFO_1 : UDINT := 16#0001_046F;   // 信息级槽 1（线性块奇异） / info slot 1
    DL_A2I_CODE_INFO_2 : UDINT := 16#0001_0470;   // 预留禁用（不得挪用） / reserved, do not use
    DL_A2I_CODE_FLT_1  : UDINT := 16#0001_03BD;   // 故障级槽 1（输入元素非有限） / fault slot 1
    DL_A2I_CODE_FLT_2  : UDINT := 16#0001_03BE;   // 预留禁用（不得挪用） / reserved, do not use
    DL_A2I_EPS_DEF : LREAL := 1.0E-6;               // 默认相对奇异判据 [无量纲] / Default relative singularity threshold [dimensionless]
    DL_A2I_INF     : LREAL := 1.7976931348623157E308; // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling, Inf criterion
    DL_A2I_ZERO    : LREAL := 0.0;                  // 零值常量，避免裸字面量 [无量纲] / Zero constant, avoids a bare literal [dimensionless]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值先行：全零矩阵 + 无错 + 不可用（先写后算，任何早退路径出口确定）
 *----------------------------------------------------------------------------*)
FOR nI := 0 TO 2 DO
    FOR nJ := 0 TO 2 DO
        afMInv[nI, nJ] := DL_A2I_ZERO;         // 逆矩阵默认全零 / default all-zero inverse
    END_FOR
END_FOR
fDet   := DL_A2I_ZERO;                         // 行列式默认零 / determinant defaults to zero
eErr   := 16#0000_0000;                        // 错误码默认无错 / error code defaults to none
bError := FALSE;                               // 故障标志默认清除 / fault flag cleared
bValid := FALSE;                               // 可用标志默认不可用，算完并检过才置位 / usable flag FALSE until computed and checked

(*------------------------------------------------------------------------------
 * 段 2｜输入非有限全阵扫描（9 元素逐个：NaN 自反判 + Inf 幅值上限判，R79）
 *----------------------------------------------------------------------------*)
bNonFin := FALSE;                              // 非有限标志复位 / reset non-finite flag
FOR nI := 0 TO 2 DO
    FOR nJ := 0 TO 2 DO
        IF (afM[nI, nJ] <> afM[nI, nJ]) OR (ABS(afM[nI, nJ]) >= DL_A2I_INF) THEN
            bNonFin := TRUE;                   // 发现非有限元素 / non-finite element found
        END_IF
    END_FOR
END_FOR
IF bNonFin THEN
    eErr   := DL_A2I_CODE_FLT_1;               // 故障级：任一输入元素非有限 / fault: non-finite input element
    bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                           // 输出不可用 / outputs unusable
    FC_DL_Affine2DInvert := FALSE;             // 返回值 = 可用标志同口径 / return mirrors bValid
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜线性块行列式与相对奇异判据（第三行不参与，R90 家族）
 *----------------------------------------------------------------------------*)
fDet := afM[0, 0] * afM[1, 1] - afM[0, 1] * afM[1, 0];  // 2x2 线性块行列式 / 2x2 linear block determinant
fMaxAbs := ABS(afM[0, 0]);                     // 最大绝对值种子：m00 / seed max with m00
fAbsK := ABS(afM[0, 1]);                       // m01 绝对值 / absolute of m01
IF fAbsK > fMaxAbs THEN fMaxAbs := fAbsK; END_IF
fAbsK := ABS(afM[1, 0]);                       // m10 绝对值 / absolute of m10
IF fAbsK > fMaxAbs THEN fMaxAbs := fAbsK; END_IF
fAbsK := ABS(afM[1, 1]);                       // m11 绝对值 / absolute of m11
IF fAbsK > fMaxAbs THEN fMaxAbs := fAbsK; END_IF
fEpsEff := fDetEps;                            // 生效判据先取引脚 / effective threshold from pin
IF fEpsEff <= DL_A2I_ZERO THEN
    fEpsEff := DL_A2I_EPS_DEF;                 // 非正回退默认判据 / non-positive falls back to default
END_IF
IF ABS(fDet) <= fEpsEff * fMaxAbs * fMaxAbs THEN
    eErr   := DL_A2I_CODE_INFO_1;              // 信息级：线性块奇异，不可逆 / info: singular linear block, not invertible
    bError := FALSE;                           // 信息级不置 bError（R45/R101）/ info never raises bError
    bValid := FALSE;                           // 逆矩阵不可用，禁止半逆外泄 / inverse unusable, no half-inverse leak
    FC_DL_Affine2DInvert := FALSE;             // 返回值同口径 / return mirrors bValid
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜2x2 伴随求逆 + 平移列反算 t' = -A^(-1) x t（除子 fDet 已由段 3 保证非零）
 *----------------------------------------------------------------------------*)
fInv00 :=  afM[1, 1] / fDet;                   // A^(-1)(0,0) = m11/det / inverse element
fInv01 := -afM[0, 1] / fDet;                   // A^(-1)(0,1) = -m01/det / inverse element
fInv10 := -afM[1, 0] / fDet;                   // A^(-1)(1,0) = -m10/det / inverse element
fInv11 :=  afM[0, 0] / fDet;                   // A^(-1)(1,1) = m00/det / inverse element
fInv02 := -(fInv00 * afM[0, 2] + fInv01 * afM[1, 2]);  // 逆平移列 x = -(A^(-1) x t)_x / inverse translation x
fInv12 := -(fInv10 * afM[0, 2] + fInv11 * afM[1, 2]);  // 逆平移列 y = -(A^(-1) x t)_y / inverse translation y

(*------------------------------------------------------------------------------
 * 段 5｜结果非有限复检（溢出复用 03BD，见边界行为⑤）后装配输出
 *----------------------------------------------------------------------------*)
IF (fInv00 <> fInv00) OR (fInv01 <> fInv01) OR (fInv10 <> fInv10) OR (fInv11 <> fInv11)
   OR (fInv02 <> fInv02) OR (fInv12 <> fInv12)
   OR (ABS(fInv00) >= DL_A2I_INF) OR (ABS(fInv01) >= DL_A2I_INF)
   OR (ABS(fInv10) >= DL_A2I_INF) OR (ABS(fInv11) >= DL_A2I_INF)
   OR (ABS(fInv02) >= DL_A2I_INF) OR (ABS(fInv12) >= DL_A2I_INF) THEN
    FOR nI := 0 TO 2 DO
        FOR nJ := 0 TO 2 DO
            afMInv[nI, nJ] := DL_A2I_ZERO;     // 溢出路径安全侧：全零矩阵 / overflow path safe side: all-zero
        END_FOR
    END_FOR
    eErr   := DL_A2I_CODE_FLT_1;               // 故障级：求逆结果非有限溢出 / fault: non-finite inverse result
    bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                           // 输出不可用 / outputs unusable
    FC_DL_Affine2DInvert := FALSE;             // 返回值同口径 / return mirrors bValid
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜装配输出：线性块 + 平移列 + 第三行原样回填（边界行为③）
 *----------------------------------------------------------------------------*)
afMInv[0, 0] := fInv00;                        // 逆线性块 (0,0) / inverse element
afMInv[0, 1] := fInv01;                        // 逆线性块 (0,1) / inverse element
afMInv[0, 2] := fInv02;                        // 逆平移列 x / inverse translation x
afMInv[1, 0] := fInv10;                        // 逆线性块 (1,0) / inverse element
afMInv[1, 1] := fInv11;                        // 逆线性块 (1,1) / inverse element
afMInv[1, 2] := fInv12;                        // 逆平移列 y / inverse translation y
afMInv[2, 0] := afM[2, 0];                     // 第三行原样回填，不校验 / third row copied verbatim, unchecked
afMInv[2, 1] := afM[2, 1];                     // 第三行原样回填，不校验 / third row copied verbatim, unchecked
afMInv[2, 2] := afM[2, 2];                     // 第三行原样回填，不校验 / third row copied verbatim, unchecked
eErr   := 16#0000_0000;                        // 无错出口 / no-error exit
bError := FALSE;                               // 无故障 / no fault
bValid := TRUE;                                // 逆矩阵可用 / inverse usable
FC_DL_Affine2DInvert := TRUE;                  // 返回值 = 可用标志 / return mirrors bValid
END_FUNCTION
