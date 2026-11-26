(*
  Component : FC_DL_CathodeSinterSoakCalc
  Category  : DL_Process
  Function  : 烧结保温时间由固相扩散长度与粒径反算，t = L² / (4D)，含最小值保护
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rDiffLenUm 目标扩散长度 [μm]、rDiffCoefUm2Min 有效扩散系数 [μm2/min]、
             rParticleD50Um 一次粒径中位径 [μm]、rSoakMinMin 保温时间下限 [min]；
             输出 rSoakCalcMin 模型计算保温时间 [min]、rSoakMin 施加下限保护后的保温时间 [min]、
             xMinApplied 触底保护生效、xValid 有效标志、nFaultCode 故障码。
  边界     : 扩散系数为分母须 >1.0E-9 [μm2/min]；扩散长度与粒径须 >0；模型 t = L²/(4D)；
             粒径小于两倍扩散长度时扩散已贯穿颗粒，模型外推无意义，rSoakMin 仍给出但不置 xValid=FALSE，
             改由 xMinApplied 与告警表达（本件不设粒径下限门限，交由上层工艺判定）。
  码位     : 9801 输入非法（故障级）；9802 扩散系数过小（故障级）。
*)
FUNCTION FC_DL_CathodeSinterSoakCalc : BOOL
VAR_INPUT
    rDiffLenUm      : LREAL := 2.0;      // 目标固相扩散长度 [μm] EN: the target solid state diffusion length
    rDiffCoefUm2Min : LREAL := 0.05;     // 有效扩散系数 [μm2/min] EN: the effective diffusion coefficient
    rParticleD50Um  : LREAL := 5.0;      // 一次粒径中位径 D50 [μm] EN: the median primary particle size
    rSoakMinMin     : LREAL := 120.0;    // 保温时间工艺下限 [min] EN: the technological lower bound of the soak time
END_VAR
VAR_OUTPUT
    rSoakCalcMin : LREAL;                // 模型计算保温时间 [min] EN: the model computed soak time
    rSoakMin     : LREAL;                // 施加下限保护后的保温时间 [min] EN: the soak time after the lower bound protection
    xMinApplied  : BOOL;                 // 触底保护生效 EN: the lower bound protection took effect
    xThrough     : BOOL;                 // 扩散已贯穿颗粒（信息级） EN: the diffusion length already spans the particle, information class only
    xValid       : BOOL;                 // 输出可信标志 EN: the outputs are valid
    nFaultCode   : INT;                  // 0=无故障 9801=输入非法 9802=扩散系数过小 EN: zero none, 9801 illegal input, 9802 diffusion coefficient too small
END_VAR
VAR
    xFinAll  : BOOL;                     // 四输入同时有限 EN: all four inputs are finite
    rDen     : LREAL;                    // 分母 4D [μm2/min] EN: the divisor, four times the diffusion coefficient
    rSq      : LREAL;                    // 扩散长度平方 [μm2] EN: the squared diffusion length
    rCalc    : LREAL;                    // 计算保温时间 [min] EN: the computed soak time
    rApply   : LREAL;                    // 施加下限后的保温时间 [min] EN: the soak time after the lower bound
END_VAR
VAR CONSTANT
    DL_CSS_Z       : LREAL := 0.0;       // 浮点零常量 EN: the floating point zero constant
    DL_CSS_FOUR    : LREAL := 4.0;       // 扩散方程几何系数 EN: the geometric factor of the diffusion equation
    DL_CSS_TWO     : LREAL := 2.0;       // 贯穿判据倍数 EN: the spanning criterion multiplier
    DL_CSS_MIN     : LREAL := 1.0E-9;    // 分母绝对值下限 [μm2/min] EN: the lower bound of the divisor magnitude
    DL_CSS_C_BAD   : INT := 9801;        // 输入非法 EN: an illegal input
    DL_CSS_C_COEF  : INT := 9802;        // 扩散系数过小 EN: the diffusion coefficient is too small
END_VAR

// 段1｜出口预置
FC_DL_CathodeSinterSoakCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rSoakCalcMin := DL_CSS_Z;               // 计算保温时间预置零 [min] EN: preset the computed soak time to zero
rSoakMin := DL_CSS_Z;                   // 施加下限后保温时间预置零 [min] EN: preset the final soak time to zero
xMinApplied := FALSE;                   // 触底标志预置假 EN: preset the lower bound flag to false
xThrough := FALSE;                      // 贯穿标志预置假 EN: preset the spanning flag to false
xValid := FALSE;                        // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                        // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：四输入全列
xFinAll := (rDiffLenUm = rDiffLenUm) AND ((rDiffLenUm - rDiffLenUm) = DL_CSS_Z)
        AND (rDiffCoefUm2Min = rDiffCoefUm2Min) AND ((rDiffCoefUm2Min - rDiffCoefUm2Min) = DL_CSS_Z)
        AND (rParticleD50Um = rParticleD50Um) AND ((rParticleD50Um - rParticleD50Um) = DL_CSS_Z)
        AND (rSoakMinMin = rSoakMinMin) AND ((rSoakMinMin - rSoakMinMin) = DL_CSS_Z);   // 四输入有限性 EN: the finiteness of all four inputs
IF NOT xFinAll THEN                                                                      // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_CSS_C_BAD;                                                          // 输入非法码 EN: the illegal input code
    RETURN;                                                                              // 早退 EN: return early
END_IF

// 段3｜域闸：扩散长度、粒径为正；扩散系数过分母下限；下限时间非负
rDen := DL_CSS_FOUR * rDiffCoefUm2Min;                                                   // 分母 4D [μm2/min] EN: the divisor, four times the diffusion coefficient
IF (rDiffLenUm <= DL_CSS_Z) OR (rParticleD50Um <= DL_CSS_Z) OR (rSoakMinMin < DL_CSS_Z)
   OR (ABS(rDen) < DL_CSS_MIN) THEN
    nFaultCode := DL_CSS_C_COEF;                                                         // 系数或域非法码 EN: the coefficient or domain code
    RETURN;                                                                              // 早退 EN: return early
END_IF

// 段4｜主体：t = L² / (4D)
rSq := rDiffLenUm * rDiffLenUm;                                                          // 扩散长度平方 [μm2] EN: the squared diffusion length
rCalc := rSq / rDen;                                                                     // 计算保温时间 [min] EN: the computed soak time
IF (rCalc <> rCalc) OR (rCalc < DL_CSS_Z) THEN                                           // 结果复检 EN: recheck the result
    nFaultCode := DL_CSS_C_COEF;                                                         // 复检失败码 EN: the recheck failure code
    RETURN;                                                                              // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF

// 段5｜最小值保护与贯穿标记
rApply := rCalc;                                                                         // 施加下限工作副本 [min] EN: the working copy for the lower bound
xMinApplied := rCalc < rSoakMinMin;                                                      // 触底判据 EN: the lower bound test
IF xMinApplied THEN                                                                      // 触底则抬到工艺下限 EN: raise to the process lower bound
    rApply := rSoakMinMin;                                                               // 施加下限 [min] EN: apply the lower bound
END_IF
xThrough := rDiffLenUm >= (rParticleD50Um / DL_CSS_TWO);                                 // 贯穿判据（信息级） EN: the spanning test, information class only

// 段6｜出口
rSoakCalcMin := rCalc;                                                                   // 计算值出口 [min] EN: the computed value output
rSoakMin := rApply;                                                                      // 最终值出口 [min] EN: the final value output
xValid := TRUE;                                                                          // 结果可信 EN: the results are valid
FC_DL_CathodeSinterSoakCalc := TRUE;                                                     // 返回真 EN: return true
END_FUNCTION
