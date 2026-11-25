// FC_DL_PotlineMetalLevelCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 铝水平 = m/(ρ·A)·100 [cm]（m³/m² = m，再 ×100 转 cm），电解质水平 = 铝水平 + 电解质层厚；
        密度入参为 1.0（占位缺省，调用方未组态）时改用 2300.0 kg/m³。
  邻件/码位: 与 FC_DL_PotlineBathTempDeviationCalc 同族不同域（几何液位 vs 热状态）；
             16#0002_9217 = 非有限、面积或密度非正、层厚为负拒收。
*)
FUNCTION FC_DL_PotlineMetalLevelCalc : REAL
VAR_INPUT
    fMetalMassKg  : REAL := 10000.0;    // 槽内铝量 [kg]，域 >= 0 / Metal mass in cell [kg]
    fCavityArea   : REAL := 25.0;       // 槽膛面积 [m²]，域 > 0 / Cavity area [m^2]
    fBathDepth    : REAL := 20.0;       // 电解质层厚 [cm]，域 >= 0 / Bath layer depth [cm]
    fMetalDensity : REAL := 2300.0;     // 铝液密度 [kg/m³]，域 > 0 / Metal density [kg/m^3]
END_VAR
VAR_OUTPUT
    fMetalLevel : REAL;                 // 铝水平 [cm] / Metal level [cm]
    fBathLevel  : REAL;                 // 电解质水平 [cm] / Bath level [cm]
    bValid      : BOOL;                 // 结果有效回执 [-] / Result validity receipt
    uErrorId    : UDINT;                // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fDensity : REAL := 0.0;             // 生效密度 [kg/m³] / Effective density [kg/m^3]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fMetalLevel := 0.0;                 // 铝水平缺省零 / Metal level default zero
fBathLevel := 0.0;                  // 电解质水平缺省零 / Bath level default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_PotlineMetalLevelCalc := 0.0;         // 返回值缺省零（镜像铝水平）/ Return default zero
// 段 1：非有限闸（四入参全枚举）/ Non-finite gate over all inputs
IF (fMetalMassKg <> fMetalMassKg) OR (fCavityArea <> fCavityArea)
   OR (fBathDepth <> fBathDepth) OR (fMetalDensity <> fMetalDensity)
   OR (ABS(fMetalMassKg) >= 3.0E38) OR (ABS(fCavityArea) >= 3.0E38)
   OR (ABS(fBathDepth) >= 3.0E38) OR (ABS(fMetalDensity) >= 3.0E38) THEN
    uErrorId := 16#0002_9217;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（面积与密度为正 + 层厚非负 + 密度占位替换，R4）/ Domain gate
IF (fCavityArea <= 1.0E-6) OR (fMetalDensity <= 0.0) THEN
    uErrorId := 16#0002_9217;   // 面积或密度非正，液位不可解 / Non-positive area or density
    RETURN;
END_IF
IF fBathDepth < 0.0 THEN
    uErrorId := 16#0002_9217;   // 电解质层厚为负 / Negative bath depth
    RETURN;
END_IF
fDensity := fMetalDensity;                                      // 密度先直取 / Take density as-is
IF fDensity <= 1.0 THEN
    fDensity := 2300.0;                                         // 占位缺省替换 / Placeholder replaced
END_IF
// 段 3：主计算（质量→体积→液位）/ Main computation
fMetalLevel := fMetalMassKg / (fDensity * fCavityArea) * 100.0;     // 铝水平 [cm] / Metal level
fBathLevel := fMetalLevel + fBathDepth;                             // 电解质水平 [cm] / Bath level
// 段 4：出口闸（双输出非有限复核 + 非负复核）/ Outlet gate
IF (fMetalLevel <> fMetalLevel) OR (fBathLevel <> fBathLevel)
   OR (ABS(fMetalLevel) >= 3.0E38) OR (ABS(fBathLevel) >= 3.0E38)
   OR (fMetalLevel < 0.0) OR (fBathLevel < 0.0) THEN
    fMetalLevel := 0.0;         // 复核失败回缺省 / Fallback on recheck failure
    fBathLevel := 0.0;          // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9217;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_PotlineMetalLevelCalc := fMetalLevel;     // 返回值镜像铝水平 / Return mirrors metal level
END_FUNCTION
