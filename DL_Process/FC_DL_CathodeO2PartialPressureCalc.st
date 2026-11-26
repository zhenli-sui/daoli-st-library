(*
  Component : FC_DL_CathodeO2PartialPressureCalc
  Category  : DL_Process
  Function  : 烧结气氛氧分压 = 氧体积浓度 × 总压，并统一换算到 kPa
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rO2Pct 氧体积浓度 [%]、rTotalPressKpa 炉膛总压 [kPa]、rO2LowKpa 氧分压下限 [kPa]；
             输出 rPO2Kpa 氧分压 [kPa]、rO2Ppm 氧体积浓度折算 [ppm]、xO2Low 低于下限（信息级）、
             xValid 有效标志、nFaultCode 故障码。
  边界     : 氧浓度须在 0~100 [%] 内、总压须 >std 0（表压与绝压口径由调用方统一为绝压）；
             浓度 1 [%] = 10000 [ppm]，故 ppm = % × 10000；本件为绝压口径，不做大气压叠加。
  码位     : 9801 输入非有限（故障级）；9802 浓度或总压越域（故障级）。
*)
FUNCTION FC_DL_CathodeO2PartialPressureCalc : BOOL
VAR_INPUT
    rO2Pct       : LREAL := 21.0;     // 氧体积浓度 [%] EN: the oxygen volumetric concentration in percent
    rTotalPressKpa: LREAL := 101.325; // 炉膛总压（绝压口径） [kPa] EN: the furnace total pressure on the absolute scale
    rO2LowKpa    : LREAL := 0.5;      // 氧分压工艺下限 [kPa] EN: the technological lower bound of the oxygen partial pressure
END_VAR
VAR_OUTPUT
    rPO2Kpa : LREAL;                  // 氧分压 [kPa] EN: the oxygen partial pressure
    rO2Ppm  : LREAL;                  // 氧体积浓度折算值 [ppm] EN: the oxygen concentration expressed in ppm
    xO2Low  : BOOL;                   // 氧分压低于工艺下限（信息级） EN: the oxygen partial pressure is below the limit, information class only
    xValid  : BOOL;                   // 输出可信标志 EN: the outputs are valid
    nFaultCode : INT;                 // 0=无故障 9801=输入非有限 9802=浓度或总压越域 EN: zero none, 9801 non finite input, 9802 concentration or pressure out of range
END_VAR
VAR
    xFinAll : BOOL;                   // 三输入同时有限 EN: all three inputs are finite
    rFrac   : LREAL;                  // 氧体积分数 [-] EN: the oxygen volumetric fraction
    rPO2    : LREAL;                  // 氧分压中间值 [kPa] EN: the interim oxygen partial pressure
    rPpm    : LREAL;                  // ppm 中间值 [ppm] EN: the interim ppm value
END_VAR
VAR CONSTANT
    DL_COP_Z         : LREAL := 0.0;      // 浮点零常量 EN: the floating point zero constant
    DL_COP_HUNDRED   : LREAL := 100.0;    // 百分数换算系数 EN: the percent conversion factor
    DL_COP_PPM_FACT  : LREAL := 10000.0;  // 百分数转 ppm 的系数 EN: the percent to ppm factor
    DL_COP_C_BAD     : INT := 9801;       // 输入非有限 EN: a non finite input
    DL_COP_C_RANGE   : INT := 9802;       // 浓度或总压越域 EN: the concentration or the pressure is out of range
END_VAR

// 段1｜出口预置
FC_DL_CathodeO2PartialPressureCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rPO2Kpa := DL_COP_Z;                           // 氧分压预置零 [kPa] EN: preset the partial pressure to zero
rO2Ppm := DL_COP_Z;                            // ppm 预置零 [ppm] EN: preset the ppm value to zero
xO2Low := FALSE;                               // 低压标志预置假 EN: preset the low pressure flag to false
xValid := FALSE;                               // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                               // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：三输入全列（下限参与出口判据）
xFinAll := (rO2Pct = rO2Pct) AND ((rO2Pct - rO2Pct) = DL_COP_Z)
        AND (rTotalPressKpa = rTotalPressKpa) AND ((rTotalPressKpa - rTotalPressKpa) = DL_COP_Z)
        AND (rO2LowKpa = rO2LowKpa) AND ((rO2LowKpa - rO2LowKpa) = DL_COP_Z);   // 三输入有限性 EN: the finiteness of all three inputs
IF NOT xFinAll THEN                                                             // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_COP_C_BAD;                                                 // 输入非有限码 EN: the non finite code
    RETURN;                                                                     // 早退 EN: return early
END_IF

// 段3｜域闸：氧浓度 0~100 [%]、总压为正、下限非负
IF (rO2Pct < DL_COP_Z) OR (rO2Pct > DL_COP_HUNDRED) OR (rTotalPressKpa <= DL_COP_Z)
   OR (rO2LowKpa < DL_COP_Z) THEN
    nFaultCode := DL_COP_C_RANGE;                                               // 越域码 EN: the out of range code
    RETURN;                                                                     // 早退 EN: return early
END_IF

// 段4｜主体：pO2 = 浓度/100 × 总压；ppm = 浓度 × 10000
rFrac := rO2Pct / DL_COP_HUNDRED;                                               // 氧体积分数 [-] EN: the oxygen volumetric fraction
rPO2 := rFrac * rTotalPressKpa;                                                 // 氧分压 [kPa] EN: the oxygen partial pressure
rPpm := rO2Pct * DL_COP_PPM_FACT;                                               // 浓度转 ppm [ppm] EN: the concentration in ppm

// 段5｜出口
rPO2Kpa := rPO2;                                                                // 氧分压出口 [kPa] EN: the partial pressure output
rO2Ppm := rPpm;                                                                 // ppm 出口 [ppm] EN: the ppm output
xO2Low := rPO2 < rO2LowKpa;                                                     // 低压判据（信息级） EN: the low pressure test, information class only
xValid := TRUE;                                                                 // 结果可信 EN: the results are valid
FC_DL_CathodeO2PartialPressureCalc := TRUE;                                     // 返回真 EN: return true
END_FUNCTION
