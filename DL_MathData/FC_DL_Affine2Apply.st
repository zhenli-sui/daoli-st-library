//==============================================================================
// 函数：FC_DL_Affine2Apply ｜ 中文名称：二维仿射矩阵对点坐标应用
// 所属子库：DL_MathData ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：单片 3x3 仿射矩阵对单点坐标 (x, y) 应用变换，p' = M x [x, y, 1]^T
//           （列向量右乘，与 FC_DL_Affine2DCompose 的合成约定构成定义-应用
//           逆对：Compose 产出矩阵、Apply 消费矩阵）。现场语义：视觉像素
//           坐标到机械毫米坐标的单点映射、纠偏平台坐标换算、印刷套准偏移。
//           第三行偏差提示为本件信息级职责：喂入矩阵第三行偏离 (0, 0, 1)
//           超容差时按仿射截断（只用前两行），输出照算并提示，便于标定
//           链上游把透视矩阵误接进仿射链时尽早暴露。
// 开源溯源 (Origin)：道莅 clean-room 防御性实现（仅借 LGF 分类事实/参数域/行为定义，零代码行与符号名复制）
// 单位表：点坐标[用户单位] / 矩阵线性块[无量纲] / 平移列[用户单位]
// 错误码表：16#0001_0469 信息级（矩阵第三行偏离 (0,0,1) 超容差，按仿射截断
//           照算，不置 bError）/ 16#0001_046A 预留禁用（不得挪用）/
//           16#0001_046B 预留禁用（不得挪用）/ 16#0001_03B9 故障级（任一
//           输入非有限，或结果非有限溢出，置 bError，输出 0）/
//           16#0001_03BA 预留禁用（不得挪用）
// 状态机：N/A——纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，以头注释说明替代 ELSE 兜底
// 边界行为：① 矩阵元素或点坐标非有限（NaN 自反判 + 幅值上限兜底，R79）→
//           故障 03B9、输出 0、bValid := FALSE；② 结果非有限（大坐标乘
//           大缩放溢出）→ 复用 03B9（R90：与输入非法共用「数据不可信」
//           语义，现有输出组合不可观测出独立信息，不新占码位）；
//           ③ 第三行偏差仅提示不阻断（信息 0469），仿射截断照算；
//           ④ 失能清零不适用（纯函数无使能闸，非法输入即故障早退）；
//           ⑤ 安全侧 = 故障路径输出 0 而非原坐标，禁止未变换坐标冒充
//           已变换坐标进入下游；
//           ⑥ 恒等矩阵输入时输出等于输入（数值恒等由乘 1.0 保证，
//           非位拷贝）。
// 验收向量（算法已证，手算）：① 恒等矩阵 + (3,4) → (3,4)；② 平移
//           (10,20) + (1,1) → (11,21)；③ 旋转 90 度 + (1,0) → (0,1)。
//           编译器已证（三平台）：未跑，由收口方登记。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · T2-1 LGF Math 仿射变换族）
//==============================================================================

FUNCTION FC_DL_Affine2Apply : BOOL
VAR_INPUT
    afM : ARRAY[0..2, 0..2] OF LREAL;       // 仿射变换矩阵 [无量纲+用户单位混合]，行主序，p' = M x p / Affine transform matrix, row-major
    fX  : LREAL;                            // 源点 X [用户单位] / Source point X [user unit]
    fY  : LREAL;                            // 源点 Y [用户单位] / Source point Y [user unit]
END_VAR
VAR_OUTPUT
    fOutX  : LREAL;                         // 变换后 X [用户单位] / Transformed X [user unit]
    fOutY  : LREAL;                         // 变换后 Y [用户单位] / Transformed Y [user unit]
    eErr   : UDINT;                         // 错误码，0 = 无错，码位 16#0001_0469 起信息级、16#0001_03B9 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError : BOOL;                          // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid : BOOL;                          // 结果可用标志 / Result usable flag
END_VAR
VAR CONSTANT
    DL_A2A_EPS      : LREAL := 1.0E-6;      // 第三行偏差容差与浮点判零共用 [无量纲] / Third-row deviation and zero tolerance [dimensionless]
    DL_A2A_INF      : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_A2A_ZERO     : LREAL := 0.0;         // 零值常量，避免裸字面量 [无量纲] / Zero constant, avoids a bare literal [dimensionless]
    DL_A2A_ONE      : LREAL := 1.0;         // 单位常量，第三行齐次项期望值 [无量纲] / Unity constant, expected homogeneous entry [dimensionless]
END_VAR
VAR
    fXt     : LREAL;                        // 第一行点积暂存 [用户单位] / First-row dot product staging
    fYt     : LREAL;                        // 第二行点积暂存 [用户单位] / Second-row dot product staging
    bNonFin : BOOL;                         // 非有限判定中间标志 / Non-finite detection intermediate flag
    nI      : INT;                          // 行循环索引 [—] / Row loop index
    nJ      : INT;                          // 列循环索引 [—] / Column loop index
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值：返回值与输出预置（安全侧 = 0）
 *      Exit defaults: return value and outputs preset, fail-safe zero
 *-----------------------------------------------------------------------------*)
FC_DL_Affine2Apply := FALSE;                // 返回值默认无效 / Return value preset invalid
fOutX := DL_A2A_ZERO;                       // 输出 X 预置 0 / Preset X to zero
fOutY := DL_A2A_ZERO;                       // 输出 Y 预置 0 / Preset Y to zero
eErr   := 16#0000_0000;                     // 错误码先清零 / Error code cleared first
bError := FALSE;                            // 故障标志先清零 / Fault flag cleared first
bValid := FALSE;                            // 可用标志先清零 / Usable flag cleared first

(*------------------------------------------------------------------------------
 * 段 2｜输入非有限闸：矩阵九元素 + 点坐标（R79 双侧幅值判）
 *      Input non-finite gate over nine matrix entries and the point
 *-----------------------------------------------------------------------------*)
bNonFin := (fX <> fX) OR (ABS(fX) > DL_A2A_INF)
        OR (fY <> fY) OR (ABS(fY) > DL_A2A_INF); // 点坐标非有限判定 / Point non-finite check
FOR nI := 0 TO 2 DO
    FOR nJ := 0 TO 2 DO
        IF (afM[nI, nJ] <> afM[nI, nJ]) OR (ABS(afM[nI, nJ]) > DL_A2A_INF) THEN
            bNonFin := TRUE;                // 命中非有限矩阵元素 / Non-finite matrix entry hit
        END_IF
    END_FOR
END_FOR
IF bNonFin THEN
    eErr   := 16#0001_03B9;                 // 故障级：输入非有限 / Fault: non-finite input
    bError := TRUE;                         // 置故障标志（R45 配对） / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
    RETURN;                                 // 故障早退，输出保持 0 / Early return, outputs stay zero
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜仿射应用：只用前两行点积（第三行截断，见段 4 提示）
 *      Affine application, first two rows only
 *-----------------------------------------------------------------------------*)
fXt := afM[0, 0] * fX + afM[0, 1] * fY + afM[0, 2]; // 第一行点积 [用户单位] / First-row dot product
fYt := afM[1, 0] * fX + afM[1, 1] * fY + afM[1, 2]; // 第二行点积 [用户单位] / Second-row dot product

(*------------------------------------------------------------------------------
 * 段 4｜第三行偏差提示：偏离 (0, 0, 1) 超容差 → 信息 0469（照算不阻断）
 *      Third-row deviation notice, computation continues
 *-----------------------------------------------------------------------------*)
IF (ABS(afM[2, 0]) > DL_A2A_EPS) OR (ABS(afM[2, 1]) > DL_A2A_EPS)
   OR (ABS(afM[2, 2] - DL_A2A_ONE) > DL_A2A_EPS) THEN
    eErr := 16#0001_0469;                   // 信息级：第三行非标准仿射，已按仿射截断 / Info: non-standard third row, affine-truncated
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜结果非有限复检：大缩放乘大坐标可能溢出（复用 03B9，R90）
 *      Result non-finite recheck, code reused per R90
 *-----------------------------------------------------------------------------*)
IF (fXt <> fXt) OR (ABS(fXt) > DL_A2A_INF)
   OR (fYt <> fYt) OR (ABS(fYt) > DL_A2A_INF) THEN
    fOutX := DL_A2A_ZERO;                   // 溢出即输出 0（安全侧） / Overflow yields zero
    fOutY := DL_A2A_ZERO;                   // 溢出即输出 0 / Overflow yields zero
    eErr   := 16#0001_03B9;                 // 故障级：结果溢出复用输入非法码（R90） / Fault: overflow, code reused per R90
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
    RETURN;                                 // 故障早退 / Early return
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜出口
 *      Exit
 *-----------------------------------------------------------------------------*)
fOutX := fXt;                               // 变换后 X 出口 / Transformed X outlet
fOutY := fYt;                               // 变换后 Y 出口 / Transformed Y outlet
bValid := TRUE;                             // 结果可用（含 0469 提示情形） / Result usable, including the 0469 notice case
FC_DL_Affine2Apply := TRUE;                 // 返回 TRUE = 应用有效 / Return TRUE = application valid
END_FUNCTION
