// FC_DL_EuclidDist2DCalc v1.0.0
// 开源溯源：来源 brOscatLib / URL https://github.com/iec-oscat-mirror / 许可证 MIT / 借鉴点 HYPOT 防溢出语义（先缩放再平方，杜绝大数平方溢出）
(*==============================================================================
 * 功能描述: 二维欧氏距离 sqrt(x²+y²) 安全计算。采用 HYPOT 防溢出口径：先以
 *           max(|x|,|y|) 归一缩放再平方求和，避免大数平方溢出与小数平方下溢。
 *           输入非有限（NaN/Inf）或两输入同时为零域外 → bValid=FALSE 并返回 0。
 * 接口契约: 输入 fX/fY；输出 bValid 回执，返回值为距离。
 * 修订历史: 2026-11-23  v1.0.0  R74 首版
 *==============================================================================*)

FUNCTION FC_DL_EuclidDist2DCalc : REAL
VAR_INPUT
    fX : REAL := 0.0;   // X 分量 [工程单位与 Y 一致] / X component, same unit as Y
    fY : REAL := 0.0;   // Y 分量 [工程单位与 X 一致] / Y component, same unit as X
END_VAR
VAR_OUTPUT
    bValid : BOOL;      // 结果有效回执 [-] / Result validity receipt
END_VAR
VAR
    fMag  : REAL;       // 归一缩放因子 max(|x|,|y|) [工程单位] / Scaling factor max of absolute components
    fUx   : REAL;       // 缩放后 x 分量 [无量纲] / Scaled x component
    fUy   : REAL;       // 缩放后 y 分量 [无量纲] / Scaled y component
    fAbsX : REAL;       // |x| 当拍量 [工程单位] / Absolute x
    fAbsY : REAL;       // |y| 当拍量 [工程单位] / Absolute y
END_VAR

(* —— 段 0：全路径赋值缺省（先判无效再计算，FC 入口安全侧） —— *)
bValid := FALSE;                            // 有效回执预清 / Validity preset
FC_DL_EuclidDist2DCalc := 0.0;              // 返回值缺省安全零 / Result default safe zero

(* —— 段 1：非有限闸（NaN 自反判 + 常量上限 Inf 换算判） —— *)
IF (fX <> fX) OR (fY <> fY) THEN            // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
    RETURN;                                 // 无效直接返回零 / Invalid, return zero
END_IF
fAbsX := ABS(fX);                           // |x| 派生 / Absolute x
fAbsY := ABS(fY);                           // |y| 派生 / Absolute y
IF (fAbsX >= 3.0E38) OR (fAbsY >= 3.0E38) THEN   // 近 Inf 幅值闸（REAL 上限兜底） / Near-Inf magnitude gate
    RETURN;                                 // 无效直接返回零 / Invalid, return zero
END_IF

(* —— 段 2：HYPOT 防溢出口径计算（先缩放再平方，杜绝大数平方溢出） —— *)
IF (fAbsX = 0.0) AND (fAbsY = 0.0) THEN     // 零向量特判（缩放因子为零） / Zero vector special case
    FC_DL_EuclidDist2DCalc := 0.0;          // 距离为零（合法） / Distance zero, valid
    bValid := TRUE;                         // 有效回执 / Validity receipt
    RETURN;                                 // 提前返回 / Early return
END_IF
IF fAbsX >= fAbsY THEN                      // 取较大分量为缩放因子 / Larger component as factor
    fMag := fAbsX;
ELSE
    fMag := fAbsY;
END_IF
fUx := fX / fMag;                           // 归一化 x [无量纲] / Normalised x
fUy := fY / fMag;                           // 归一化 y [无量纲] / Normalised y
FC_DL_EuclidDist2DCalc := fMag * SQRT(fUx * fUx + fUy * fUy);   // 缩放域平方和再还原（分母 fMag 已闸非零） / Scaled square sum restored
bValid := TRUE;                             // 有效回执 / Validity receipt

END_FUNCTION
