(*
 * FC_DL_FreeCoolingHoursCalc | C2 | DL_Device
 * 功能：逐时干球温度法统计自然冷却可用小时数（含滞环）       单位：温度 [℃]、滞环 [K]、小时 [h]、格数 [1]
 * 工况边界：固定 24 格逐时数组（禁变长数组），每格代表 1 h；判据 outdoor < return − hyst；任一小时数据 NaN/±Inf 或超量程即判 xValid=FALSE 并把可用小时数与最低温度置安全值 0；本件为温度法简化，工程定案须用焓差法复核
 * 代数值回代：return=30 ℃、hyst=2 K → 阈值 28 ℃；若 24 格中 10 格 <28 ℃ → 可用 10 h、nFreeBins=10、rMinOutdoorC=各格最小值（与 spec 1 h/格计数一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_FreeCoolingHoursCalc : BOOL
VAR_INPUT
    arOutdoorC : ARRAY[1..24] OF REAL;  // 逐时户外干球温度 | hourly outdoor dry bulb temperature [℃]
    rReturnC   : REAL := 30.0;          // 机房回风温度 | room return air temperature [℃]
    rHystK     : REAL := 2.0;           // 自然冷却投入滞环 | free cooling hysteresis [K]
END_VAR
VAR_OUTPUT
    rFreeHours  : REAL;                 // 自然冷却可用小时数 | free cooling available hours [h]
    nFreeBins   : INT;                  // 可用小时格数 | number of free cooling bins [格]
    rMinOutdoorC: REAL;                 // 全年最低户外温度（诊断用）| minimum outdoor temperature for diagnostics [℃]
    xValid      : BOOL;                 // 输出有效 | outputs valid
END_VAR
VAR
    nIdx      : INT;                    // 数组下标 | array index [1]
    nBadBins  : INT;                    // 非法数据格数 | count of non-finite or out-of-range bins [格]
    xFinRet   : BOOL;                   // 回风温度有限性 | return temperature is finite
    xFinHyst  : BOOL;                   // 滞环有限性 | hysteresis is finite
    xBinFin   : BOOL;                   // 单格有限性 | this bin is finite
    rThreshC  : REAL;                   // 自然冷却投入阈值 | free cooling threshold temperature [℃]
    rValC     : REAL;                   // 当前格温度 | current bin temperature [℃]
END_VAR
VAR CONSTANT
    DL_FCH_TEMP_MAX : REAL := 60.0;     // 温度量程上限 | upper temperature limit [℃]
    DL_FCH_TEMP_MIN : REAL := -60.0;    // 温度量程下限 | lower temperature limit [℃]
    DL_FCH_HOUR_PER_BIN : REAL := 1.0;  // 每格代表小时数 | hours represented by one bin [h]
END_VAR

// 段1｜非有限闸：回风温度与滞环（R19）
xFinRet := (rReturnC = rReturnC) AND ((rReturnC - rReturnC) = 0.0);
xFinHyst := (rHystK = rHystK) AND ((rHystK - rHystK) = 0.0);
IF (NOT xFinRet) OR (NOT xFinHyst) OR (rHystK < 0.0) THEN
    rFreeHours := 0.0;                  // 安全值：可用小时 0 | safe value, zero hours
    nFreeBins := 0;
    rMinOutdoorC := 0.0;
    xValid := FALSE;
    FC_DL_FreeCoolingHoursCalc := FALSE;
    RETURN;
END_IF

// 段2｜逐格统计（禁变长数组，固定 1..24）
rThreshC := rReturnC - rHystK;
nFreeBins := 0;
nBadBins := 0;
rMinOutdoorC := arOutdoorC[1];          // 以首格初始化，后续逐格比较 | initialised with the first bin
FOR nIdx := 1 TO 24 DO
    rValC := arOutdoorC[nIdx];
    xBinFin := (rValC = rValC) AND ((rValC - rValC) = 0.0);
    IF (NOT xBinFin) OR (rValC > DL_FCH_TEMP_MAX) OR (rValC < DL_FCH_TEMP_MIN) THEN
        nBadBins := nBadBins + 1;       // 非法格不计入可用，也不参与最低值 | invalid bins are excluded from both statistics
    ELSE
        IF rValC < rThreshC THEN
            nFreeBins := nFreeBins + 1; // 该格计入可用小时 | this bin counts as free cooling time
        END_IF
        IF rValC < rMinOutdoorC THEN
            rMinOutdoorC := rValC;      // 追踪最低温度 | track the minimum
        END_IF
    END_IF
END_FOR

// 段3｜结果：任一杯坏数据即整表判无效（不发布半可信统计）
IF nBadBins > 0 THEN
    rFreeHours := 0.0;                  // 安全值：可用小时 0 | safe value, zero hours
    nFreeBins := 0;
    rMinOutdoorC := 0.0;
    xValid := FALSE;
    FC_DL_FreeCoolingHoursCalc := FALSE;
    RETURN;
END_IF
rFreeHours := INT_TO_REAL(nFreeBins) * DL_FCH_HOUR_PER_BIN;

// 段4｜出口
xValid := TRUE;
FC_DL_FreeCoolingHoursCalc := TRUE;
END_FUNCTION
