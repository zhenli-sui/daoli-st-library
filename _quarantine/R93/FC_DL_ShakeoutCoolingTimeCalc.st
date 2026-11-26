(*
 * FC_DL_ShakeoutCoolingTimeCalc | C1 | DL_Process
 * 功能：落砂后铸件在空气中的冷却时间（Chvorinov 模数法）与模数       单位：体积 [cm³]、表面积 [cm²]、时间 [min]、模数 [cm]
 * 工况边界：Chvorinov 式 t = B×(V/A)²，B 取 2.5 min/cm²，仅适用于砂型落砂后在静止空气中的自然冷却（无强制风冷）；体积须 >0、表面积须 >0（入分母），否则判 9715；B 换成钢/球铁件须重标
 * 代数值回代：V=2000 cm³、A=1200 cm² → 模数 1.667 cm；t=2.5×1.667²=6.94 min（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_ShakeoutCoolingTimeCalc : BOOL
VAR_INPUT
    rVolumeCm3      : REAL := 2000.0;  // 铸件体积 | casting volume [cm³]
    rSurfaceCm2     : REAL := 1200.0;  // 铸件散热表面积 | casting heat transfer surface [cm²]
    rModulusCoeffB  : REAL := 2.5;     // Chvorinov 系数 | Chvorinov coefficient [min/cm²]
END_VAR
VAR_OUTPUT
    rCoolingMin : REAL;                // 冷却时间 | cooling time [min]
    rModulusCm  : REAL;                // 凝固模数 V/A | solidification modulus [cm]
    xValid      : BOOL;                // 输出有效 | outputs valid
    nFaultCode  : INT;                 // 0=无 / 9715=体积或表面积非法 | 0 none, 9715 illegal volume or surface
END_VAR
VAR
    xFinV  : BOOL;                     // 体积有限性 | volume is finite
    xFinA  : BOOL;                     // 表面积有限性 | surface is finite
    xFinB  : BOOL;                     // 系数有限性 | coefficient is finite
END_VAR
VAR CONSTANT
    DL_SCT_AREA_MIN : REAL := 1.0E-6;  // 表面积下限（防零除）| surface lower bound guarding the division [cm²]
END_VAR

// 段1｜非有限闸（R19）
xFinV := (rVolumeCm3 = rVolumeCm3) AND ((rVolumeCm3 - rVolumeCm3) = 0.0);
xFinA := (rSurfaceCm2 = rSurfaceCm2) AND ((rSurfaceCm2 - rSurfaceCm2) = 0.0);
xFinB := (rModulusCoeffB = rModulusCoeffB) AND ((rModulusCoeffB - rModulusCoeffB) = 0.0);
IF (NOT xFinV) OR (NOT xFinA) OR (NOT xFinB) THEN
    rCoolingMin := 0.0;                // 安全值：冷却时间 0 | safe value, zero time
    rModulusCm := 0.0;
    xValid := FALSE;
    nFaultCode := 9715;
    FC_DL_ShakeoutCoolingTimeCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：体积与表面积须为正（面积入分母），系数须 >0
IF (rVolumeCm3 <= 0.0) OR (rSurfaceCm2 <= DL_SCT_AREA_MIN) OR (rModulusCoeffB <= 0.0) THEN
    rCoolingMin := 0.0;
    rModulusCm := 0.0;
    xValid := FALSE;
    nFaultCode := 9715;
    FC_DL_ShakeoutCoolingTimeCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：模数 M=V/A；t = B×M²
rModulusCm := rVolumeCm3 / rSurfaceCm2;
rCoolingMin := rModulusCoeffB * rModulusCm * rModulusCm;

// 段4｜出口
nFaultCode := 0;
xValid := TRUE;
FC_DL_ShakeoutCoolingTimeCalc := TRUE;
END_FUNCTION
