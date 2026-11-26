(*
  Component : FC_DL_TankHeatLossCalc
  Category  : DL_Base
  Function  : 立式储罐散热汇总：侧壁 + 顶盖 + 罐底三面分别计算后求和
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rDiaMm 罐内径 [mm]、rHeightMm 罐高（液位以下高度） [mm]、rLiqTempC 介质温度 [℃]、
             rAmbientC 环境温度 [℃]、rSideHWm2K 侧壁总换热系数 [W/(m2·K)]、
             rTopHWm2K 顶盖总换热系数 [W/(m2·K)]、rBottomHWm2K 罐底总换热系数 [W/(m2·K)]；
             输出 rSideAreaM2 侧壁面积 [m2]、rTopAreaM2 顶盖面积 [m2]、rBottomAreaM2 罐底面积 [m2]、
             rSideW 侧壁散热 [W]、rTopW 顶盖散热 [W]、rBottomW 罐底散热 [W]、rTotalW 总散热 [W]、
             xValid 有效标志、nFaultCode 故障码。
  边界     : 直径与高度须 >1.0E-6 [mm]；三个换热系数须 ≥0（为 0 表示该面绝热，输出 0）；
             面积换算：侧壁 = π·D·H，顶/底 = π·D²/4，D、H 折米后参与；
             散热正负随温差，负值表示吸热（冷罐），不做钳位。
  码位     : 9801 输入非有限（故障级）；9802 几何尺寸或换热系数越域（故障级）。
*)
FUNCTION FC_DL_TankHeatLossCalc : BOOL
VAR_INPUT
    rDiaMm        : LREAL := 2000.0;  // 罐内径 [mm] EN: the inner diameter of the tank
    rHeightMm     : LREAL := 3000.0;  // 罐高（液位以下） [mm] EN: the tank height below the liquid level
    rLiqTempC     : LREAL := 80.0;    // 介质温度 [℃] EN: the medium temperature
    rAmbientC     : LREAL := 20.0;    // 环境温度 [℃] EN: the ambient temperature
    rSideHWm2K    : LREAL := 2.0;     // 侧壁总换热系数 [W/(m2·K)] EN: the overall side wall heat transfer coefficient
    rTopHWm2K     : LREAL := 3.0;     // 顶盖总换热系数 [W/(m2·K)] EN: the overall top heat transfer coefficient
    rBottomHWm2K  : LREAL := 1.0;     // 罐底总换热系数 [W/(m2·K)] EN: the overall bottom heat transfer coefficient
END_VAR
VAR_OUTPUT
    rSideAreaM2  : LREAL;             // 侧壁面积 [m2] EN: the side wall area
    rTopAreaM2   : LREAL;             // 顶盖面积 [m2] EN: the top area
    rBottomAreaM2: LREAL;             // 罐底面积 [m2] EN: the bottom area
    rSideW       : LREAL;             // 侧壁散热 [W] EN: the side wall heat loss
    rTopW        : LREAL;             // 顶盖散热 [W] EN: the top heat loss
    rBottomW     : LREAL;             // 罐底散热 [W] EN: the bottom heat loss
    rTotalW      : LREAL;             // 总散热 [W] EN: the total heat loss
    xValid       : BOOL;              // 输出可信标志 EN: the outputs are valid
    nFaultCode   : INT;               // 0=无故障 9801=输入非有限 9802=尺寸或系数越域 EN: zero none, 9801 non finite, 9802 size or coefficient out of range
END_VAR
VAR
    xFinAll : BOOL;                   // 七个浮点入参有限 EN: all seven floating inputs are finite
    rDm     : LREAL;                  // 内径折米 [m] EN: the inner diameter in metres
    rHm     : LREAL;                  // 高度折米 [m] EN: the height in metres
    rDtmp   : LREAL;                  // 温差 [K] EN: the temperature difference
    rSide   : LREAL;                  // 侧壁散热中间值 [W] EN: the interim side loss
    rTop    : LREAL;                  // 顶盖散热中间值 [W] EN: the interim top loss
    rBot    : LREAL;                  // 罐底散热中间值 [W] EN: the interim bottom loss
END_VAR
VAR CONSTANT
    DL_THL_Z     : LREAL := 0.0;                  // 浮点零常量 EN: the floating point zero constant
    DL_THL_PI    : LREAL := 3.1415926535897932;   // 圆周率（LREAL 精度） [-] EN: the circle ratio at LREAL precision
    DL_THL_FOUR  : LREAL := 4.0;                  // 圆面积分母 EN: the circle area divisor
    DL_THL_K1000 : LREAL := 1000.0;               // 毫米转米系数 EN: the millimetre to metre factor
    DL_THL_MIN   : LREAL := 1.0E-6;               // 尺寸下限 [mm] EN: the lower bound of the sizes
    DL_THL_C_BAD : INT := 9801;                   // 输入非有限 EN: a non finite input
    DL_THL_C_RANG: INT := 9802;                   // 尺寸或系数越域 EN: the size or the coefficient is out of range
END_VAR

// 段1｜出口预置
FC_DL_TankHeatLossCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rSideAreaM2 := DL_THL_Z;           // 侧壁面积预置零 [m2] EN: preset the side area to zero
rTopAreaM2 := DL_THL_Z;            // 顶盖面积预置零 [m2] EN: preset the top area to zero
rBottomAreaM2 := DL_THL_Z;         // 罐底面积预置零 [m2] EN: preset the bottom area to zero
rSideW := DL_THL_Z;                // 侧壁散热预置零 [W] EN: preset the side loss to zero
rTopW := DL_THL_Z;                 // 顶盖散热预置零 [W] EN: preset the top loss to zero
rBottomW := DL_THL_Z;              // 罐底散热预置零 [W] EN: preset the bottom loss to zero
rTotalW := DL_THL_Z;               // 总散热预置零 [W] EN: preset the total loss to zero
xValid := FALSE;                   // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                   // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：七输入全列
xFinAll := (rDiaMm = rDiaMm) AND ((rDiaMm - rDiaMm) = DL_THL_Z)
        AND (rHeightMm = rHeightMm) AND ((rHeightMm - rHeightMm) = DL_THL_Z)
        AND (rLiqTempC = rLiqTempC) AND ((rLiqTempC - rLiqTempC) = DL_THL_Z)
        AND (rAmbientC = rAmbientC) AND ((rAmbientC - rAmbientC) = DL_THL_Z)
        AND (rSideHWm2K = rSideHWm2K) AND ((rSideHWm2K - rSideHWm2K) = DL_THL_Z)
        AND (rTopHWm2K = rTopHWm2K) AND ((rTopHWm2K - rTopHWm2K) = DL_THL_Z)
        AND (rBottomHWm2K = rBottomHWm2K) AND ((rBottomHWm2K - rBottomHWm2K) = DL_THL_Z);   // 七输入有限性 EN: the finiteness of all seven inputs
IF NOT xFinAll THEN                                                                        // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_THL_C_BAD;                                                            // 非有限码 EN: the non finite code
    RETURN;                                                                                // 早退 EN: return early
END_IF

// 段3｜域闸：几何尺寸为正、三个换热系数非负
IF (rDiaMm < DL_THL_MIN) OR (rHeightMm < DL_THL_MIN)
   OR (rSideHWm2K < DL_THL_Z) OR (rTopHWm2K < DL_THL_Z) OR (rBottomHWm2K < DL_THL_Z) THEN
    nFaultCode := DL_THL_C_RANG;                                                           // 越域码 EN: the out of range code
    RETURN;                                                                                // 早退 EN: return early
END_IF

// 段4｜主体：三面面积与散热
rDm := rDiaMm / DL_THL_K1000;                                                              // 内径折米 [m] EN: the diameter in metres
rHm := rHeightMm / DL_THL_K1000;                                                           // 高度折米 [m] EN: the height in metres
rDtmp := rLiqTempC - rAmbientC;                                                            // 温差 [K] EN: the temperature difference
rSideAreaM2 := DL_THL_PI * rDm * rHm;                                                      // 侧壁面积 [m2] EN: the side area
rTopAreaM2 := (DL_THL_PI * rDm * rDm) / DL_THL_FOUR;                                       // 顶盖面积 [m2] EN: the top area
rBottomAreaM2 := rTopAreaM2;                                                                // 罐底面积与顶盖相同 [m2] EN: the bottom area equals the top area
rSide := rSideHWm2K * rSideAreaM2 * rDtmp;                                                 // 侧壁散热 [W] EN: the side loss
rTop := rTopHWm2K * rTopAreaM2 * rDtmp;                                                    // 顶盖散热 [W] EN: the top loss
rBot := rBottomHWm2K * rBottomAreaM2 * rDtmp;                                              // 罐底散热 [W] EN: the bottom loss

// 段5｜结果复检与汇总出口
IF (rSide <> rSide) OR (rTop <> rTop) OR (rBot <> rBot) THEN                               // 复检：三路非有限 EN: recheck the three results
    nFaultCode := DL_THL_C_RANG;                                                           // 复检失败码 EN: the recheck failure code
    RETURN;                                                                                // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF
rSideW := rSide;                                                                           // 侧壁散热出口 [W] EN: the side loss output
rTopW := rTop;                                                                             // 顶盖散热出口 [W] EN: the top loss output
rBottomW := rBot;                                                                          // 罐底散热出口 [W] EN: the bottom loss output
rTotalW := rSide + rTop + rBot;                                                            // 总散热 [W] EN: the total heat loss
xValid := TRUE;                                                                            // 结果可信 EN: the results are valid
FC_DL_TankHeatLossCalc := TRUE;                                                             // 返回真 EN: return true
END_FUNCTION
