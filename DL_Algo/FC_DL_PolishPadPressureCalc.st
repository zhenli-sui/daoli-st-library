(*
  DL Factory R88 | FC_DL_PolishPadPressureCalc
  功能：算抛光垫比压 p=F/A，A=πD²/4，N/mm² 按 ×1000 换算 kPa，并按 5~30 kPa 判带宽
  开源溯源：无（clean-room 自研，依据公开工艺公式 圆盘接触比压式 p=F/(πD²/4)，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_PolishPadPressureCalc : REAL
VAR_INPUT
    fForceN : REAL := 300.0; // 抛光下压力 F [N] / polishing down force [N]
    fDiaMm : REAL := 200.0; // 抛光垫（或工件）接触直径 D [mm] / pad or workpiece diameter [mm]
    fMinKPa : REAL := 5.0; // 比压允许下限（工艺带宽） [kPa] / lower pressure band [kPa]
    fMaxKPa : REAL := 30.0; // 比压允许上限（工艺带宽） [kPa] / upper pressure band [kPa]
END_VAR
VAR_OUTPUT
    fPressKPa : REAL; // 抛光垫比压 p [kPa] / pad specific pressure [kPa]
    xInBand : BOOL; // TRUE=比压落在允许带宽内 [-] / TRUE when inside the band [-]
END_VAR
VAR
    fAreaMm2 : REAL; // 接触面积 A=πD²/4（除零判据） [mm²] / contact area, the divisor [mm^2]
    fPressMpa : REAL; // 比压 N/mm²（数值等同 MPa） [N/mm²] / specific pressure [N/mm^2]
END_VAR

// 段 1｜出口预置
FC_DL_PolishPadPressureCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fPressKPa := 0.0; // 比压预置零 [kPa] / pressure preset zero [kPa]
xInBand := FALSE; // 带宽位预置 FALSE [-] / band flag preset false [-]
fAreaMm2 := 0.0; // 接触面积预置零 [mm²] / area preset zero [mm^2]
fPressMpa := 0.0; // 比压中间量预置零 [N/mm²] / pressure mid value preset zero [N/mm^2]

// 段 2｜非有限拦截 + 域闸
IF NOT (fForceN > -1.0E30 AND fForceN < 1.0E30) OR NOT (fDiaMm > -1.0E30 AND fDiaMm < 1.0E30) THEN
    RETURN; // 下压力/直径任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fMinKPa > -1.0E30 AND fMinKPa < 1.0E30) OR NOT (fMaxKPa > -1.0E30 AND fMaxKPa < 1.0E30) THEN
    RETURN; // 带宽上下限任一非有限则判据静默失效，故先拦 [kPa] / band limits must be finite [kPa]
END_IF
IF fForceN < 0.0 OR fDiaMm < 1.0E-9 THEN
    RETURN; // 力非负闸 + 直径正域闸（面积分母不得为零） [N, mm] / non negative force and positive diameter
END_IF
IF fMinKPa <= 0.0 OR fMaxKPa <= fMinKPa THEN
    RETURN; // 带宽自洽闸：下限须为正、上限须严格大于下限 [kPa] / band consistency gate [kPa]
END_IF

// 段 3｜计算
fAreaMm2 := 3.14159265 * fDiaMm * fDiaMm * 0.25; // 无量纲 × mm² × 0.25 = mm²，A=πD²/4（乘 0.25 替除 4） [mm²] / [mm^2]
IF fAreaMm2 < 1.0E-9 THEN
    RETURN; // 除法前分母闸：面积必须大于 1E-9 才可作除数 [mm²] / denominator gate before the division [mm^2]
END_IF
fPressMpa := fForceN / fAreaMm2; // N ÷ mm² = N/mm²（数值等同 MPa） [N/mm²] / [N] / [mm^2] = [N/mm^2]
fPressKPa := fPressMpa * 1000.0; // N/mm² × 1000 = kPa（1 N/mm²=1 MPa=1000 kPa） [kPa] / [kPa]

// 段 4｜判定与饱和
IF NOT (fPressKPa > -1.0E30 AND fPressKPa < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
xInBand := (fPressKPa >= fMinKPa) AND (fPressKPa <= fMaxKPa); // 双侧闭区间直比 [kPa] / closed two sided band compare [kPa]

// 段 5｜出口自检
IF fPressKPa < 0.0 THEN
    RETURN; // 出口自检：比压不得为负（负值说明力符号错） [kPa] / pressure must not be negative [kPa]
END_IF
FC_DL_PolishPadPressureCalc := fPressKPa; // 返回抛光垫比压 [kPa] / return the pad specific pressure [kPa]
END_FUNCTION
