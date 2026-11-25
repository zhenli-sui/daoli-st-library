// FC_DL_BushingDwellFlowCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Device，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 漏孔玻璃液质量流量（Hagen-Poiseuille 圆管层流）：r = d/2/1000，L = len/1000，
        Q = π·Δp·r⁴/(8·μ·L) [m³/s]，单孔 = Q·ρ·3.6e6 [g/h]，总流量 = 单孔·孔数/1000 [kg/h]。
  邻件/码位: 与 FC_DL_FiberDiameterFromDrawRateCalc 直接串联（本件出单孔流量）；
             16#0002_9222 = 非有限、黏度/孔径/孔长/密度非正或孔数 < 1 拒收。
*)
FUNCTION FC_DL_BushingDwellFlowCalc : REAL
VAR_INPUT
    fDeltaP    : REAL := 5000.0;    // 漏板上下压差 [Pa]，域 > 0 / Pressure differential [Pa]
    fHoleDia   : REAL := 1.6;       // 漏孔直径 [mm]，域 > 0 / Orifice diameter [mm]
    fDwellLen  : REAL := 4.0;       // 漏孔长度 [mm]，域 > 0 / Orifice length [mm]
    fViscosity : REAL := 500.0;     // 玻璃液黏度 [Pa·s]，域 > 0 / Glass viscosity [Pa s]
    iHoleCount : INT := 800;        // 漏孔数，域 >= 1 [个] / Orifice count
    fDensity   : REAL := 2500.0;    // 玻璃液密度 [kg/m³]，域 > 0 / Glass density [kg/m^3]
END_VAR
VAR_OUTPUT
    fFlowPerHole : REAL;            // 单孔质量流量 [g/h] / Mass flow per orifice [g/h]
    fFlowTotal   : REAL;            // 总质量流量 [kg/h] / Total mass flow [kg/h]
    bValid       : BOOL;            // 结果有效回执 [-] / Result validity receipt
    uErrorId     : UDINT;           // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fRadius  : REAL := 0.0;         // 漏孔半径 [m] / Orifice radius [m]
    fLenM    : REAL := 0.0;         // 漏孔长度 [m] / Orifice length [m]
    fVolFlow : REAL := 0.0;         // 单孔体积流量 [m³/s] / Volumetric flow [m^3/s]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fFlowPerHole := 0.0;                // 单孔流量缺省零 / Per-orifice default zero
fFlowTotal := 0.0;                  // 总流量缺省零 / Total flow default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_BushingDwellFlowCalc := 0.0;  // 返回值缺省零（镜像单孔流量）/ Return default zero
// 段 1：非有限闸（五实数入参；整数入参天然有限）/ Non-finite gate on real inputs
IF (fDeltaP <> fDeltaP) OR (fHoleDia <> fHoleDia) OR (fDwellLen <> fDwellLen)
   OR (fViscosity <> fViscosity) OR (fDensity <> fDensity)
   OR (ABS(fDeltaP) >= 3.0E38) OR (ABS(fHoleDia) >= 3.0E38) OR (ABS(fDwellLen) >= 3.0E38)
   OR (ABS(fViscosity) >= 3.0E38) OR (ABS(fDensity) >= 3.0E38) THEN
    uErrorId := 16#0002_9222;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（黏度/孔径/孔长/密度为正防除零 + 孔数下限，R4）/ Domain gate
IF (fViscosity <= 1.0E-6) OR (fHoleDia <= 1.0E-6) OR (fDwellLen <= 1.0E-6) OR (fDensity <= 1.0E-6) THEN
    uErrorId := 16#0002_9222;   // 黏度、孔径、孔长或密度非正 / Non-positive physical input
    RETURN;
END_IF
IF iHoleCount < 1 THEN
    uErrorId := 16#0002_9222;   // 孔数不足 1 / Orifice count below one
    RETURN;
END_IF
// 段 3：主计算（半径/长度换算 → 体积流量 → 质量流量）/ Main computation
fRadius := fHoleDia / 2.0 / 1000.0;                             // 半径 [m] / Radius in metres
fLenM := fDwellLen / 1000.0;                                    // 孔长 [m] / Length in metres
fVolFlow := 3.14159265358979 * fDeltaP * fRadius * fRadius * fRadius * fRadius
          / (8.0 * fViscosity * fLenM);                         // Q = πΔp r⁴/(8μL) / Poiseuille flow
fFlowPerHole := fVolFlow * fDensity * 3600.0 * 1000.0;          // 单孔 [g/h] / Per-orifice mass flow
fFlowTotal := fFlowPerHole * INT_TO_REAL(iHoleCount) / 1000.0;  // 总流量 [kg/h] / Total mass flow
// 段 4：出口闸（双输出非有限复核 + 非负复核）/ Outlet gate
IF (fFlowPerHole <> fFlowPerHole) OR (fFlowTotal <> fFlowTotal)
   OR (ABS(fFlowPerHole) >= 3.0E38) OR (ABS(fFlowTotal) >= 3.0E38)
   OR (fFlowPerHole < 0.0) OR (fFlowTotal < 0.0) THEN
    fFlowPerHole := 0.0;        // 复核失败回缺省 / Fallback on recheck failure
    fFlowTotal := 0.0;          // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9222;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_BushingDwellFlowCalc := fFlowPerHole;     // 返回值镜像单孔流量 / Return mirrors flow
END_FUNCTION
