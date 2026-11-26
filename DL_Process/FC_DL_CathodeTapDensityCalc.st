(*
  Component : FC_DL_CathodeTapDensityCalc
  Category  : DL_Process
  Function  : 振实密度 = 质量 / 振实后体积，并按振次做修正
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rMassG 试样质量 [g]、rVolumeMl 振实后体积 [ml]、nTaps 实测振次 [次]、
             nRefTaps 标准振次 [次]、rTapCoef 振次修正系数 [-]；
             输出 rDensityGml 实测振实密度 [g/ml]、rDensityCorrGml 修正到标准振次的密度 [g/ml]、
             xValid 有效标志、nFaultCode 故障码。
  边界     : 体积为分母须 >1.0E-9 [ml]；振次须 ≥1（取对数的前提），标准振次须 ≥1；
             修正模型 rho_ref = rho × (1 + k × LN(nRef/nTaps))，k 须在 [0, 0.2] 内，
             越域判 9803（k 越域会把修正放大成伪数据）；1 g/ml = 1 g/cm3，单位不做换算。
  码位     : 9801 输入非法（故障级）；9802 体积过小或振次非法（故障级）；9803 修正系数越域（故障级）。
*)
FUNCTION FC_DL_CathodeTapDensityCalc : BOOL
VAR_INPUT
    rMassG    : LREAL := 100.0;    // 试样质量 [g] EN: the mass of the sample
    rVolumeMl : LREAL := 50.0;     // 振实后体积 [ml] EN: the tapped volume of the sample
    nTaps     : INT := 3000;       // 实测振次 [次] EN: the tap count actually applied
    nRefTaps  : INT := 3000;       // 标准振次 [次] EN: the reference tap count
    rTapCoef  : LREAL := 0.02;     // 振次修正系数 [-] EN: the tap count correction coefficient
END_VAR
VAR_OUTPUT
    rDensityGml     : LREAL;       // 实测振实密度 [g/ml] EN: the measured tap density
    rDensityCorrGml : LREAL;       // 修正到标准振次的密度 [g/ml] EN: the density corrected to the reference tap count
    xValid          : BOOL;        // 输出可信标志 EN: the outputs are valid
    nFaultCode      : INT;         // 0=无故障 9801=输入非法 9802=体积或振次非法 9803=系数越域 EN: zero none, 9801 illegal input, 9802 volume or taps illegal, 9803 coefficient out of range
END_VAR
VAR
    xFinAll : BOOL;                // 三个浮点入参有限 EN: the three floating inputs are finite
    rDen    : LREAL;               // 分母（振实后体积） [ml] EN: the divisor, the tapped volume
    rRho    : LREAL;               // 实测密度 [g/ml] EN: the measured density
    rLnCorr : LREAL;               // 振次比对数 [-] EN: the logarithm of the tap ratio
    rCorr   : LREAL;               // 密度修正中间值 [g/ml] EN: the interim corrected density
END_VAR
VAR CONSTANT
    DL_CTD_Z        : LREAL := 0.0;   // 浮点零常量 EN: the floating point zero constant
    DL_CTD_ONE      : LREAL := 1.0;   // 浮点壹常量 EN: the floating point one constant
    DL_CTD_COEF_MAX : LREAL := 0.2;   // 修正系数上限 [-] EN: the upper bound of the correction coefficient
    DL_CTD_MIN      : LREAL := 1.0E-9;// 分母绝对值下限 [ml] EN: the lower bound of the divisor magnitude
    DL_CTD_C_BAD    : INT := 9801;    // 输入非法 EN: an illegal input
    DL_CTD_C_DEN    : INT := 9802;    // 体积过小或振次非法 EN: the volume is too small or the taps are illegal
    DL_CTD_C_COEF   : INT := 9803;    // 修正系数越域 EN: the coefficient is out of range
END_VAR

// 段1｜出口预置
FC_DL_CathodeTapDensityCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rDensityGml := DL_CTD_Z;                 // 实测密度预置零 [g/ml] EN: preset the measured density to zero
rDensityCorrGml := DL_CTD_Z;             // 修正密度预置零 [g/ml] EN: preset the corrected density to zero
xValid := FALSE;                         // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                         // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：三浮点入参全列
xFinAll := (rMassG = rMassG) AND ((rMassG - rMassG) = DL_CTD_Z)
        AND (rVolumeMl = rVolumeMl) AND ((rVolumeMl - rVolumeMl) = DL_CTD_Z)
        AND (rTapCoef = rTapCoef) AND ((rTapCoef - rTapCoef) = DL_CTD_Z);   // 三输入有限性 EN: the finiteness of all three inputs
IF NOT xFinAll THEN                                                        // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_CTD_C_BAD;                                            // 输入非法码 EN: the illegal input code
    RETURN;                                                                // 早退 EN: return early
END_IF

// 段3｜域闸：质量为非负、体积过分母下限、振次 ≥1
rDen := rVolumeMl;                                                          // 取分母 [ml] EN: take the divisor
IF (rMassG < DL_CTD_Z) OR (ABS(rDen) < DL_CTD_MIN) OR (nTaps < 1) OR (nRefTaps < 1) THEN
    nFaultCode := DL_CTD_C_DEN;                                            // 体积或振次非法码 EN: the volume or tap code
    RETURN;                                                                // 早退 EN: return early
END_IF
IF (rTapCoef < DL_CTD_Z) OR (rTapCoef > DL_CTD_COEF_MAX) THEN               // 系数域闸 EN: the coefficient domain gate
    nFaultCode := DL_CTD_C_COEF;                                            // 系数越域码 EN: the coefficient code
    RETURN;                                                                // 早退 EN: return early
END_IF

// 段4｜主体：实测密度与振次修正（两出口同源，修正只缩放实测值不另起公式）
rRho := rMassG / rDen;                                                      // 实测振实密度 [g/ml] EN: the measured tap density
rLnCorr := LN(INT_TO_LREAL(nRefTaps) / INT_TO_LREAL(nTaps));                // 振次比对数 [-]，两者已证 ≥1 EN: the logarithm of the tap ratio
rCorr := rRho * (DL_CTD_ONE + rTapCoef * rLnCorr);                          // 修正密度 [g/ml] EN: the corrected density
IF (rCorr <> rCorr) OR (rCorr < DL_CTD_Z) THEN                              // 结果复检 EN: recheck the result
    nFaultCode := DL_CTD_C_COEF;                                            // 复检失败码 EN: the recheck failure code
    rDensityGml := rRho;                                                    // 实测值仍可给出 EN: the measured value is still published
    RETURN;                                                                // 早退 EN: return early
END_IF

// 段5｜出口
rDensityGml := rRho;                                                        // 实测密度出口 [g/ml] EN: the measured density output
rDensityCorrGml := rCorr;                                                   // 修正密度出口 [g/ml] EN: the corrected density output
xValid := TRUE;                                                             // 结果可信 EN: the results are valid
FC_DL_CathodeTapDensityCalc := TRUE;                                        // 返回真 EN: return true
END_FUNCTION
