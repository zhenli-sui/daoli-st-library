(*
 * FC_DL_AisleLeakageMixCalc | C2 | DL_Device
 * 功能：冷热通道旁通泄漏的混合温度与冷量损失温差       单位：温度 [℃]、泄漏比例 [1]、温差 [K]
 * 工况边界：线性混合模型（无相变、无风机温升），适用于同一机房冷热通道压差稳定的场合；泄漏比例按 [0,1] 物理域钳位，越界仅置信息位（判据取自未钳位原值，R5/R24）；温度须有限
 * 代数值回代：cold=22、hot=35、leak=0.15 → Tmix=0.15×35+0.85×22=23.95 ℃；冷量损失温差=23.95−22=1.95 K（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_AisleLeakageMixCalc : BOOL
VAR_INPUT
    rColdC     : REAL := 22.0;       // 冷通道送风温度 | cold aisle supply temperature [℃]
    rHotC      : REAL := 35.0;       // 热通道回风温度 | hot aisle return temperature [℃]
    rLeakRatio : REAL := 0.15;       // 旁通泄漏比例 | bypass leakage ratio [1]
END_VAR
VAR_OUTPUT
    rMixedC            : REAL;       // 混合后进柜温度 | mixed rack inlet temperature [℃]
    rColdSupplyDeficitK: REAL;       // 冷量损失温差（混合−冷通道）| cooling loss temperature difference [K]
    rLeakUsed          : REAL;       // 实际参与计算的泄漏比例（已钳位）| leakage ratio actually used, clamped [1]
    xLeakClamped       : BOOL;       // 泄漏比例越界被钳位（信息级）| ratio out of range and clamped, informational
    xValid             : BOOL;       // 输出有效 | outputs valid
END_VAR
VAR
    xFinC : BOOL;                    // 冷通道温度有限性 | cold aisle temperature is finite
    xFinH : BOOL;                    // 热通道温度有限性 | hot aisle temperature is finite
    xFinL : BOOL;                    // 泄漏比例有限性 | leakage ratio is finite
END_VAR
VAR CONSTANT
    DL_ALM_RATIO_LO : REAL := 0.0;   // 泄漏比例下限 | leakage ratio lower bound [1]
    DL_ALM_RATIO_HI : REAL := 1.0;   // 泄漏比例上限 | leakage ratio upper bound [1]
END_VAR

// 段1｜非有限闸（R19）
xFinC := (rColdC = rColdC) AND ((rColdC - rColdC) = 0.0);
xFinH := (rHotC = rHotC) AND ((rHotC - rHotC) = 0.0);
xFinL := (rLeakRatio = rLeakRatio) AND ((rLeakRatio - rLeakRatio) = 0.0);
IF (NOT xFinC) OR (NOT xFinH) OR (NOT xFinL) THEN
    rMixedC := 0.0;                  // 安全值：混合温度 0（下游按无效丢弃）| safe value, downstream discards it
    rColdSupplyDeficitK := 0.0;
    rLeakUsed := 0.0;
    xLeakClamped := FALSE;
    xValid := FALSE;
    FC_DL_AisleLeakageMixCalc := FALSE;
    RETURN;
END_IF

// 段2｜域钳位：泄漏比例物理域 [0,1]，越界标志取自未钳位原值（R24）
IF rLeakRatio < DL_ALM_RATIO_LO THEN
    xLeakClamped := TRUE;
    rLeakUsed := DL_ALM_RATIO_LO;
ELSIF rLeakRatio > DL_ALM_RATIO_HI THEN
    xLeakClamped := TRUE;
    rLeakUsed := DL_ALM_RATIO_HI;
ELSE
    xLeakClamped := FALSE;
    rLeakUsed := rLeakRatio;
END_IF

// 段3｜算法：Tmix = leak×hot + (1−leak)×cold
rMixedC := rLeakUsed * rHotC + (1.0 - rLeakUsed) * rColdC;
rColdSupplyDeficitK := rMixedC - rColdC;

// 段4｜出口
xValid := TRUE;
FC_DL_AisleLeakageMixCalc := TRUE;
END_FUNCTION
