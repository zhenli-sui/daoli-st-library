(*
  Component : FC_DL_FlatWallHeatLossCalc
  Category  : DL_Base
  Function  : 多层平壁复合导热 + 表面对流：q = ΔT / (Σ(ti/λi) + 1/h)
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rTiC 内侧温度 [℃]、rToC 外侧环境温度 [℃]、afThickMm 各层厚度定长数组 [mm]
             （ARRAY[0..3]，未用层填零）、afLambdaWmK 各层导热系数定长数组 [W/(m·K)]、
             nLayers 有效层数 [层]、rHWm2K 外表面换热系数 [W/(m2·K)]、rAreaM2 传热面积 [m2]；
             输出 rFluxWm2 热流密度 [W/m2]、rResistM2KW 总热阻 [m2·K/W]、rPowerW 总散热功率 [W]、
             xValid 有效标志、nFaultCode 故障码。
  边界     : 层数须 1~4；每层厚度须 >0、导热系数须 >0（零厚度或零导热视为组态错误判 9803）；
             换热系数须 >1.0E-6；总热阻为分母须 >1.0E-9；面积须 ≥0；
             数组固定 4 元素，访问前逐元素双边界校验（R4）。
  码位     : 9801 输入非有限（故障级）；9802 层数越界（故障级）；9803 层参数或换热系数越域（故障级）。
*)
FUNCTION FC_DL_FlatWallHeatLossCalc : BOOL
VAR_INPUT
    rTiC        : LREAL := 120.0;                    // 内侧温度 [℃] EN: the inner surface temperature
    rToC        : LREAL := 25.0;                     // 外侧环境温度 [℃] EN: the outer ambient temperature
    afThickMm   : ARRAY[0..3] OF LREAL;              // 各层厚度，未用层填零 [mm] EN: the layer thicknesses, unused layers hold zero
    afLambdaWmK : ARRAY[0..3] OF LREAL;              // 各层导热系数 [W/(m·K)] EN: the layer thermal conductivities
    nLayers     : INT := 2;                          // 有效层数 [层] EN: the number of valid layers
    rHWm2K      : LREAL := 10.0;                     // 外表面换热系数 [W/(m2·K)] EN: the outer surface heat transfer coefficient
    rAreaM2     : LREAL := 1.0;                      // 传热面积 [m2] EN: the heat transfer area
END_VAR
VAR_OUTPUT
    rFluxWm2     : LREAL;                            // 热流密度 [W/m2] EN: the heat flux density
    rResistM2KW  : LREAL;                            // 总热阻 [m2·K/W] EN: the total thermal resistance
    rPowerW      : LREAL;                            // 总散热功率 [W] EN: the total heat loss power
    xValid       : BOOL;                             // 输出可信标志 EN: the outputs are valid
    nFaultCode   : INT;                              // 0=无故障 9801=输入非有限 9802=层数越界 9803=层参数越域 EN: zero none, 9801 non finite, 9802 layer count out of range, 9803 layer parameter out of range
END_VAR
VAR
    xFinAll : BOOL;                                  // 标量浮点入参有限 EN: the scalar floating inputs are finite
    xLayerOk: BOOL;                                  // 各层参数合法 EN: every layer parameter is legal
    i       : INT;                                   // 层循环索引 [层] EN: the layer loop index
    nScan   : INT;                                   // 实际扫描层数 [层] EN: the effective layer scan count
    rRes    : LREAL;                                 // 导热热阻累加器 [m2·K/W] EN: the conduction resistance accumulator
    rRtot   : LREAL;                                 // 总热阻 [m2·K/W] EN: the total resistance
    rFlux   : LREAL;                                 // 热流密度中间值 [W/m2] EN: the interim heat flux
END_VAR
VAR CONSTANT
    DL_FWH_Z       : LREAL := 0.0;                   // 浮点零常量 EN: the floating point zero constant
    DL_FWH_K1000   : LREAL := 1000.0;                // 毫米转米系数 EN: the millimetre to metre factor
    DL_FWH_LAY_MAX : INT := 4;                       // 层数上限 [层] EN: the upper bound of the layer count
    DL_FWH_IDX_MAX : INT := 3;                       // 数组上界索引 [层] EN: the array upper bound index
    DL_FWH_MIN     : LREAL := 1.0E-9;                // 总热阻与换热系数的下限 EN: the lower bound of the total resistance and the transfer coefficient
    DL_FWH_C_BAD   : INT := 9801;                    // 输入非有限 EN: a non finite input
    DL_FWH_C_LAY   : INT := 9802;                    // 层数越界 EN: the layer count is out of range
    DL_FWH_C_PARAM : INT := 9803;                    // 层参数或换热系数越域 EN: a layer parameter or the transfer coefficient is out of range
END_VAR

// 段1｜出口预置
FC_DL_FlatWallHeatLossCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rFluxWm2 := DL_FWH_Z;                  // 热流预置零 [W/m2] EN: preset the flux to zero
rResistM2KW := DL_FWH_Z;               // 总热阻预置零 [m2·K/W] EN: preset the total resistance to zero
rPowerW := DL_FWH_Z;                   // 功率预置零 [W] EN: preset the power to zero
xValid := FALSE;                       // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                       // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：标量入参全列
xFinAll := (rTiC = rTiC) AND ((rTiC - rTiC) = DL_FWH_Z)
        AND (rToC = rToC) AND ((rToC - rToC) = DL_FWH_Z)
        AND (rHWm2K = rHWm2K) AND ((rHWm2K - rHWm2K) = DL_FWH_Z)
        AND (rAreaM2 = rAreaM2) AND ((rAreaM2 - rAreaM2) = DL_FWH_Z);   // 四标量输入有限性 EN: the finiteness of the four scalar inputs
IF NOT xFinAll THEN                                                     // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_FWH_C_BAD;                                         // 非有限码 EN: the non finite code
    RETURN;                                                             // 早退 EN: return early
END_IF

// 段3｜层数域闸：1~4，越界一律拒绝访问数组
IF (nLayers < 1) OR (nLayers > DL_FWH_LAY_MAX) THEN                     // 层数域闸 EN: the layer count domain gate
    nFaultCode := DL_FWH_C_LAY;                                         // 层数越界码 EN: the layer count code
    RETURN;                                                             // 早退 EN: return early
END_IF

// 段4｜逐层累加导热热阻，逐层过非有限与正值闸
rRes := DL_FWH_Z;                                                        // 热阻累加器清零 [m2·K/W] EN: clear the resistance accumulator
xLayerOk := TRUE;                                                        // 假定各层合法 EN: assume every layer is legal
nScan := nLayers;                                                        // 扫描层数 [层] EN: the scan count
FOR i := 0 TO nScan - 1 DO                                               // 定长数组循环（层数已证 ≤4） EN: the fixed array loop, the count is proven at most four
    IF (i >= 0) AND (i <= DL_FWH_IDX_MAX) THEN                           // 逐元素双边界校验 EN: the per element bound check
        IF (afThickMm[i] = afThickMm[i]) AND ((afThickMm[i] - afThickMm[i]) = DL_FWH_Z)
           AND (afLambdaWmK[i] = afLambdaWmK[i]) AND ((afLambdaWmK[i] - afLambdaWmK[i]) = DL_FWH_Z)
           AND (afThickMm[i] > DL_FWH_Z) AND (afLambdaWmK[i] > DL_FWH_Z) THEN
            rRes := rRes + (afThickMm[i] / DL_FWH_K1000) / afLambdaWmK[i];   // 累加 t/λ，[m2·K/W] EN: accumulate the thickness over the conductivity
        ELSE
            xLayerOk := FALSE;                                                   // 某层非法 EN: some layer is illegal
        END_IF
    END_IF
END_FOR
IF NOT xLayerOk THEN                                                             // 层参数非法 EN: a layer parameter is illegal
    nFaultCode := DL_FWH_C_PARAM;                                                // 层参数越域码 EN: the layer parameter code
    RETURN;                                                                      // 早退 EN: return early
END_IF

// 段5｜加表面对流热阻并求热流：q = ΔT / (ΣR + 1/h)
IF (ABS(rHWm2K) < DL_FWH_MIN) OR (rAreaM2 < DL_FWH_Z) THEN                       // 换热系数与面积闸 EN: the coefficient and area gate
    nFaultCode := DL_FWH_C_PARAM;                                                // 越域码 EN: the out of range code
    RETURN;                                                                      // 早退 EN: return early
END_IF
rRtot := rRes + (1.0 / rHWm2K);                                                   // 总热阻 [m2·K/W] EN: the total resistance
IF ABS(rRtot) < DL_FWH_MIN THEN                                                   // 总热阻分母下限 EN: the total resistance gate
    nFaultCode := DL_FWH_C_PARAM;                                                 // 越域码 EN: the out of range code
    RETURN;                                                                       // 早退 EN: return early
END_IF
rFlux := (rTiC - rToC) / rRtot;                                                    // 热流密度，正负随温差 [W/m2] EN: the flux carrying the temperature difference sign
IF rFlux <> rFlux THEN                                                            // 结果复检 EN: recheck the result
    nFaultCode := DL_FWH_C_PARAM;                                                 // 复检失败码 EN: the recheck failure code
    RETURN;                                                                       // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF

// 段6｜出口
rFluxWm2 := rFlux;                                                                // 热流密度出口 [W/m2] EN: the flux output
rResistM2KW := rRtot;                                                             // 总热阻出口 [m2·K/W] EN: the total resistance output
rPowerW := rFlux * rAreaM2;                                                       // 总散热功率 [W] EN: the total power
xValid := TRUE;                                                                   // 结果可信 EN: the results are valid
FC_DL_FlatWallHeatLossCalc := TRUE;                                               // 返回真 EN: return true
END_FUNCTION
