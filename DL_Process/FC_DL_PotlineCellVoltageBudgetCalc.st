// FC_DL_PotlineCellVoltageBudgetCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 槽电压预算：Rtot = (R_bath + R_anode)·1e-6 [Ω]，I = I[kA]·1000 [A]，
        欧姆压降 = I·Rtot，槽电压 = 反电动势 + 浓差 + 活化 + 欧姆压降；
        结果出 2.0~8.0 V 工艺窗置 bValid FALSE（工艺异常域，非计算错误）。
  邻件/码位: 与 FC_DL_PotlineAnodeEffectEnergyCalc 分域（正常电压分解 vs 效应附加电耗）；
             16#0002_9214 = 非有限、电阻为负或电流非正或电压出工艺窗。
*)
FUNCTION FC_DL_PotlineCellVoltageBudgetCalc : REAL
VAR_INPUT
    fRevEMF    : REAL := 1.20;      // 反电动势 [V] / Reversible EMF [V]
    fConcOver  : REAL := 0.10;      // 浓差过电位 [V] / Concentration overpotential [V]
    fActOver   : REAL := 0.35;      // 活化过电位 [V] / Activation overpotential [V]
    fBathRes   : REAL := 3.0;       // 电解质电阻 [µΩ]，域 >= 0 / Bath resistance [uOhm]
    fAnodeRes  : REAL := 1.5;       // 阳极气泡电阻 [µΩ]，域 >= 0 / Anode bubble resistance [uOhm]
    fCurrentKA : REAL := 400.0;     // 系列电流 [kA]，域 > 0 / Line current [kA]
END_VAR
VAR_OUTPUT
    fCellVoltage : REAL;            // 槽电压 [V]，工艺域 2.0~8.0 / Cell voltage [V]
    fOhmicDrop   : REAL;            // 欧姆压降 [V] / Ohmic voltage drop [V]
    bValid       : BOOL;            // 结果有效回执 [-] / Result validity receipt
    uErrorId     : UDINT;           // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fResTotal : REAL := 0.0;        // 总电阻 [Ω] / Total resistance [Ohm]
    fCurrentA : REAL := 0.0;        // 电流 [A] / Current [A]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fCellVoltage := 0.0;                // 槽电压缺省零 / Cell voltage default zero
fOhmicDrop := 0.0;                  // 欧姆压降缺省零 / Ohmic drop default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_PotlineCellVoltageBudgetCalc := 0.0;  // 返回值缺省零（镜像槽电压）/ Return default zero
// 段 1：非有限闸（六入参全枚举）/ Non-finite gate over all inputs
IF (fRevEMF <> fRevEMF) OR (fConcOver <> fConcOver) OR (fActOver <> fActOver)
   OR (fBathRes <> fBathRes) OR (fAnodeRes <> fAnodeRes) OR (fCurrentKA <> fCurrentKA)
   OR (ABS(fRevEMF) >= 3.0E38) OR (ABS(fConcOver) >= 3.0E38) OR (ABS(fActOver) >= 3.0E38)
   OR (ABS(fBathRes) >= 3.0E38) OR (ABS(fAnodeRes) >= 3.0E38) OR (ABS(fCurrentKA) >= 3.0E38) THEN
    uErrorId := 16#0002_9214;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（电阻非负 + 电流为正）/ Domain gate
IF (fBathRes < 0.0) OR (fAnodeRes < 0.0) THEN
    uErrorId := 16#0002_9214;   // 电阻为负，物理非法 / Negative resistance
    RETURN;
END_IF
IF fCurrentKA <= 1.0E-6 THEN
    uErrorId := 16#0002_9214;   // 电流非正 / Non-positive current
    RETURN;
END_IF
// 段 3：主计算（电阻链 → 欧姆压降 → 电压预算）/ Main computation
fResTotal := (fBathRes + fAnodeRes) * 1.0E-6;                   // 总电阻 [Ω] / Total resistance
fCurrentA := fCurrentKA * 1000.0;                               // 电流 [A] / Current in amperes
fOhmicDrop := fCurrentA * fResTotal;                            // 欧姆压降 I·R [V] / Ohmic drop
fCellVoltage := fRevEMF + fConcOver + fActOver + fOhmicDrop;    // 槽电压预算 / Cell voltage budget
// 段 4：出口闸（非有限复核 + 2.0~8.0 V 工艺域判定）/ Outlet gate
IF (fCellVoltage <> fCellVoltage) OR (fOhmicDrop <> fOhmicDrop)
   OR (ABS(fCellVoltage) >= 3.0E38) OR (ABS(fOhmicDrop) >= 3.0E38) THEN
    fCellVoltage := 0.0;        // 复核失败回缺省 / Fallback on recheck failure
    fOhmicDrop := 0.0;          // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9214;   // 出口非有限拒收 / Output non-finite reject
    RETURN;
END_IF
IF (fCellVoltage < 2.0) OR (fCellVoltage > 8.0) THEN
    uErrorId := 16#0002_9214;   // 信息级：槽电压出工艺窗 / Info: voltage out of window
    RETURN;                     // bValid 保持 FALSE / Validity stays false
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_PotlineCellVoltageBudgetCalc := fCellVoltage;     // 返回值镜像槽电压 / Return mirrors voltage
END_FUNCTION
