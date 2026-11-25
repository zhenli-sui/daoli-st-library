// FC_DL_CabsComplexCalc v1.0.0
// 开源溯源：brOscatLib / URL https://github.com/iec-oscat-mirror / 许可证 MIT / 借鉴 CABS 复数模长语义（先判大者再缩放，防平方溢出），clean-room 重写
(*
  道莅工业代码库 | DL_MathData | FC_DL_CabsComplexCalc
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 复数模长 |z| = sqrt(re² + im²) 防溢出实现（先判 |re|,|im| 大者，缩放后再平方）
  邻件关系: 与 FC_DL_EuclidDist2DCalc（R74）同防溢出口径族；本件为复数语义命名
            （re/im 实虚部），欧氏件为几何坐标语义（x/y），口径一致不重码
*)
FUNCTION FC_DL_CabsComplexCalc : REAL
VAR_INPUT
    fRe : REAL := 0.0;   // 实部 [无量纲，与虚部同单位] / Real part, same unit as imaginary
    fIm : REAL := 0.0;   // 虚部 [无量纲，与实部同单位] / Imaginary part, same unit as real
END_VAR
VAR_OUTPUT
    bValid : BOOL;       // 结果有效回执 [-] / Result validity receipt
END_VAR
VAR
    fAbsRe : REAL;       // |re| 当拍量 [无量纲] / Absolute real part
    fAbsIm : REAL;       // |im| 当拍量 [无量纲] / Absolute imaginary part
    fMax   : REAL;       // 缩放因子 max(|re|,|im|) [无量纲] / Scaling factor max of both
    fUre   : REAL;       // 缩放后实部 [无量纲] / Scaled real part
    fUim   : REAL;       // 缩放后虚部 [无量纲] / Scaled imaginary part
    fMag   : REAL;       // 缩放域模长 [无量纲] / Magnitude in scaled domain
END_VAR

// —— 段 0：全路径缺省（FC 入口安全侧） —— //
bValid := FALSE;                                   // 有效回执预清 / Validity preset
FC_DL_CabsComplexCalc := 0.0;                      // 返回值缺省安全零 / Return default safe zero

// —— 段 1：非有限闸（NaN 自反判 + 近 Inf 幅值闸） —— //
IF (fRe <> fRe) OR (fIm <> fIm) THEN               // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive test
    RETURN;                                        // 无效返回零 / Invalid, return zero
END_IF
fAbsRe := ABS(fRe);                                // |re| 派生 / Absolute real part
fAbsIm := ABS(fIm);                                // |im| 派生 / Absolute imaginary part
IF (fAbsRe >= 3.0E38) OR (fAbsIm >= 3.0E38) THEN   // 近 Inf 幅值闸（REAL 上限兜底） / Near-Inf magnitude gate
    RETURN;                                        // 无效返回零 / Invalid, return zero
END_IF

// —— 段 2：零向量特判（缩放因子为零时直接归零） —— //
IF (fAbsRe = 0.0) AND (fAbsIm = 0.0) THEN          // 双零特判 / Zero-vector special case
    FC_DL_CabsComplexCalc := 0.0;                  // 模长为零（合法） / Magnitude zero, valid
    bValid := TRUE;                                // 有效回执 / Validity receipt
    RETURN;                                        // 提前返回 / Early return
END_IF

// —— 段 3：防溢出口径（先取大者缩放，再平方求和，杜绝大数平方上溢与小数下溢） —— //
IF fAbsRe >= fAbsIm THEN                           // 取 |re|,|im| 大者为缩放因子 / Larger of the two as factor
    fMax := fAbsRe;
ELSE
    fMax := fAbsIm;
END_IF
fUre := fRe / fMax;                                // 缩放实部 ∈ [-1,1] / Scaled real part in [-1,1]
fUim := fIm / fMax;                                // 缩放虚部 ∈ [-1,1] / Scaled imaginary part in [-1,1]
fMag := SQRT(fUre * fUre + fUim * fUim);           // 缩放域模长 ≤ sqrt(2)，不溢出 / Scaled magnitude <= sqrt(2)
FC_DL_CabsComplexCalc := fMag * fMax;              // 还原真实模长 / Restore true magnitude
bValid := TRUE;                                    // 有效回执 / Validity receipt
END_FUNCTION
