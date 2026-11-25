// FC_DL_FiberDiameterFromDrawRateCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Device，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 由单孔质量流量与拉丝速度反算纤维直径：质量流量 g/h→kg/h→kg/s（除 1000、除 3600），
        除 ρ 得体积流量 [m³/s]，除以 m/s 得截面积 A [m²]，d = 2·SQRT(A/π)·1e6 [µm]。
        注：派单式原写 (m/1000/ρ)/(v/60)，缺 h→s 的 3600 换算；不补则结果恒放大 3600 倍
        （30 g/h、900 m/min、2500 kg/m³ 时得 1009 µm 而非 16.8 µm），3~30 µm 工艺窗永久不可达。
        本件按量纲一致性显式补入 3600，公式其余部分不变。
  邻件/码位: 与 FC_DL_BushingDwellFlowCalc 正串联（前件出单孔流量）；
             16#0002_9223 = 非有限、拉丝速度/密度非正、流量非正或直径出 3~30 µm。
*)
FUNCTION FC_DL_FiberDiameterFromDrawRateCalc : REAL
VAR_INPUT
    fFlowRate  : REAL := 30.0;      // 单孔质量流量 [g/h]，域 > 0 / Mass flow per orifice [g/h]
    fDrawSpeed : REAL := 900.0;     // 拉丝线速度 [m/min]，域 > 0 / Drawing speed [m/min]
    fDensity   : REAL := 2500.0;    // 玻璃密度 [kg/m³]，域 > 0 / Glass density [kg/m^3]
END_VAR
VAR_OUTPUT
    fDiameterUm : REAL;             // 纤维直径 [µm]，工艺窗 3~30 / Fiber diameter [um]
    bValid      : BOOL;             // 结果有效回执 [-] / Result validity receipt
    uErrorId    : UDINT;            // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fMassKgS : REAL := 0.0;         // 单孔质量流量 [kg/s] / Mass flow [kg/s]
    fVolRate : REAL := 0.0;         // 单孔体积流量 [m³/s] / Volumetric flow [m^3/s]
    fVelocity : REAL := 0.0;        // 拉丝线速度 [m/s] / Drawing speed [m/s]
    fArea    : REAL := 0.0;         // 单丝截面积 [m²] / Filament cross-section [m^2]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fDiameterUm := 0.0;                 // 直径缺省零 / Diameter default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_FiberDiameterFromDrawRateCalc := 0.0; // 返回值缺省零（镜像直径）/ Return default zero
// 段 1：非有限闸（三入参全枚举）/ Non-finite gate over all inputs
IF (fFlowRate <> fFlowRate) OR (fDrawSpeed <> fDrawSpeed) OR (fDensity <> fDensity)
   OR (ABS(fFlowRate) >= 3.0E38) OR (ABS(fDrawSpeed) >= 3.0E38) OR (ABS(fDensity) >= 3.0E38) THEN
    uErrorId := 16#0002_9223;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（拉丝速度与密度为正防除零 + 流量为正，R4）/ Domain gate
IF (fDrawSpeed <= 1.0E-6) OR (fDensity <= 1.0E-6) THEN
    uErrorId := 16#0002_9223;   // 拉丝速度或密度非正 / Non-positive speed or density
    RETURN;
END_IF
IF fFlowRate <= 1.0E-6 THEN
    uErrorId := 16#0002_9223;   // 流量非正（无丝可拉）/ Non-positive flow, no filament
    RETURN;
END_IF
// 段 3：主计算（质量→体积流量→截面积→直径）/ Main computation
fMassKgS := fFlowRate / 1000.0 / 3600.0;                        // 质量流量 [kg/s] / Mass flow
fVolRate := fMassKgS / fDensity;                                // 体积流量 [m³/s] / Volumetric flow
fVelocity := fDrawSpeed / 60.0;                                 // 线速度 [m/s] / Drawing speed
fArea := fVolRate / fVelocity;                                  // 截面积 [m²] / Cross-section area
fDiameterUm := 2.0 * SQRT(fArea / 3.14159265358979) * 1.0E6;    // d = 2·sqrt(A/π) [µm] / Diameter
// 段 4：出口闸（非有限复核 + 3~30 µm 工艺窗判定）/ Outlet gate
IF (fDiameterUm <> fDiameterUm) OR (ABS(fDiameterUm) >= 3.0E38) THEN
    fDiameterUm := 0.0;         // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9223;   // 出口非有限拒收 / Output non-finite reject
    RETURN;
END_IF
IF (fDiameterUm < 3.0) OR (fDiameterUm > 30.0) THEN
    uErrorId := 16#0002_9223;   // 信息级：直径出 3~30 µm 工艺窗 / Info: diameter out of window
    RETURN;                     // bValid 保持 FALSE / Validity stays false
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_FiberDiameterFromDrawRateCalc := fDiameterUm;     // 返回值镜像直径 / Return mirrors diameter
END_FUNCTION
