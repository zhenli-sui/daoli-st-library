(*
  DL Factory R84 | FC_DL_ChipLoadPerToothCalc
  功能：算每齿进给 fz 与切屑厚度 hm，并判最小切屑厚度以下的风险位
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_ChipLoadPerToothCalc : REAL
VAR_INPUT
    fVf : REAL := 800.0; // 进给速度 [mm/min] / feed rate [mm/min]
    iTeeth : INT := 4; // 刀齿数（≥1） [齿] / tooth count [teeth]
    fRpm : REAL := 6000.0; // 主轴转速 [r/min] / spindle speed [r/min]
    fKrDeg : REAL := 60.0; // 主偏角 [°] / entering angle [deg]
    fMinChipMm : REAL := 0.02; // 最小切屑厚度（颤振/摩擦判据） [mm] / minimum chip thickness [mm]
END_VAR
VAR_OUTPUT
    fChipThkMm : REAL; // 切屑厚度 hm [mm] / chip thickness [mm]
    xThinChip : BOOL; // 切屑过薄风险位（摩擦/加工硬化） [-] / thin chip risk flag [-]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fTeeth : REAL; // 齿数实数化 [齿] / tooth count as a real [teeth]
    fFzRaw : REAL; // 每齿进给中间量 [mm/z] / feed per tooth intermediate [mm/z]
    fKrRad : REAL; // 主偏角弧度值 [rad] / entering angle in radians [rad]
END_VAR
VAR CONSTANT
    DL_CHIP_DEG2RAD : REAL := 0.0174532925199433; // 度转弧度常量 [rad/°] / degree to radian constant [rad/deg]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_ChipLoadPerToothCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fChipThkMm := 0.0; // 切屑厚度预置零 [mm] / chip thickness preset zero [mm]
xThinChip := FALSE; // 过薄风险位预置 FALSE [-] / thin chip flag preset false [-]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fVf > -1.0E30 AND fVf < 1.0E30) OR NOT (fRpm > -1.0E30 AND fRpm < 1.0E30) OR NOT (fKrDeg > -1.0E30 AND fKrDeg < 1.0E30) OR NOT (fMinChipMm > -1.0E30 AND fMinChipMm < 1.0E30) THEN
    RETURN; // 任一入参为 NaN/Inf 一律拒绝 [-] / any NaN or Inf input rejected [-]
END_IF
IF iTeeth < 1 OR iTeeth > 200 OR fVf < 0.0 OR fRpm < 1.0E-9 THEN
    RETURN; // 齿数与转速正域闸（防除零） [齿, r/min] / tooth count and speed gate [teeth, r/min]
END_IF
IF fKrDeg <= 0.0 OR fKrDeg >= 180.0 THEN
    RETURN; // 主偏角开区间域闸 [°] / entering angle open interval gate [deg]
END_IF

// 段 3｜fz = vf / (z × n)
fTeeth := INT_TO_REAL(iTeeth); // 标准转换，禁构造函数式 [齿] / standard conversion only [teeth]
fFzRaw := fVf / (fTeeth * fRpm); // mm/min ÷ (齿 × r/min) = mm/z / [mm/min] / ([teeth] × [r/min]) = [mm/tooth]
IF fFzRaw < 0.0 OR NOT (fFzRaw > -1.0E30 AND fFzRaw < 1.0E30) THEN
    RETURN; // 结果非有限或负值即非法 [mm/z] / non finite or negative result [mm/z]
END_IF

// 段 4｜hm = fz × sin(Kr)
fKrRad := fKrDeg * DL_CHIP_DEG2RAD; // ° × rad/° = rad / [deg] × [rad/deg] = [rad]
fChipThkMm := fFzRaw * SIN(fKrRad); // mm/z × 无量纲 = mm / [mm/tooth] × [-] = [mm]
IF NOT (fChipThkMm > -1.0E30 AND fChipThkMm < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF
xThinChip := fChipThkMm < fMinChipMm; // 直比下限，禁浮点等值 [-] / direct compare against the floor [-]
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_ChipLoadPerToothCalc := fFzRaw; // 返回每齿进给 [mm/z] / return the feed per tooth [mm/tooth]
END_FUNCTION
