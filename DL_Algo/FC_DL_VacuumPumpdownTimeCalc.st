(*
  DL Factory R88 | FC_DL_VacuumPumpdownTimeCalc
  功能：算抽气时间 t=(V/S)·ln(p0/p)，压力比须大于 1 才有效，超 600 s 提示抽速不足
  开源溯源：无（clean-room 自研，依据公开工艺公式 粗抽时间式 t=(V/S)·ln(p0/p)，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_VacuumPumpdownTimeCalc : REAL
VAR_INPUT
    fVolL : REAL := 100.0; // 腔室容积 V [L] / chamber volume [L]
    fPumpSpeedLps : REAL := 10.0; // 泵有效抽速 S（工作压力段平均值） [L/s] / effective pumping speed [L/s]
    fPStartPa : REAL := 101325.0; // 起始压力 p0 [Pa] / starting pressure [Pa]
    fPEndPa : REAL := 1.0; // 目标压力 p [Pa] / target pressure [Pa]
    fLimitS : REAL := 600.0; // 抽气时间上限 [s] / pumpdown time limit [s]
END_VAR
VAR_OUTPUT
    fTimeS : REAL; // 抽气时间 t [s] / pumpdown time [s]
    xTooLong : BOOL; // TRUE=抽气时间超过上限，抽速不足 [-] / TRUE when the time exceeds the limit [-]
END_VAR
VAR
    fRatio : REAL; // 压力比 p0/p（LN 自变量，须 >1） [-] / pressure ratio, the LN argument [-]
    fVolPerSpeedS : REAL; // V/S 时间常数（除零判据） [s] / time constant, the divisor [s]
END_VAR

// 段 1｜出口预置
FC_DL_VacuumPumpdownTimeCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fTimeS := 0.0; // 抽气时间预置零 [s] / pumpdown time preset zero [s]
xTooLong := FALSE; // 过久位预置 FALSE（未判定前不报警） [-] / too-long flag preset false [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fVolL > -1.0E30 AND fVolL < 1.0E30) OR NOT (fPumpSpeedLps > -1.0E30 AND fPumpSpeedLps < 1.0E30) OR NOT (fLimitS > -1.0E30 AND fLimitS < 1.0E30) THEN
    RETURN; // 容积/抽速/时间上限任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fPStartPa > -1.0E30 AND fPStartPa < 1.0E30) OR NOT (fPEndPa > -1.0E30 AND fPEndPa < 1.0E30) THEN
    RETURN; // 起始/目标压力任一非有限即拒算 [Pa] / any non finite pressure rejected [Pa]
END_IF
IF fVolL < 1.0E-9 OR fPumpSpeedLps < 1.0E-9 OR fLimitS <= 0.0 THEN
    RETURN; // 容积与抽速正域闸（分母）+ 时间上限正域闸 [L, L/s, s] / positive gates
END_IF
IF fPStartPa < 1.0E-9 OR fPEndPa < 1.0E-9 OR fPStartPa <= fPEndPa THEN
    RETURN; // 压力正域闸（LN 自变量）+ 压力比闸：p0 须大于 p，否则 LN≤0 [Pa] / pressure ratio gate [Pa]
END_IF

// 段 3｜计算
fVolPerSpeedS := fVolL / fPumpSpeedLps; // L ÷ (L/s) = s，时间常数 V/S [s] / [s]
IF fVolPerSpeedS < 1.0E-9 THEN
    RETURN; // 除法后复核：时间常数须为正，否则结果失去物理意义 [s] / the constant must stay positive [s]
END_IF
fRatio := fPStartPa / fPEndPa; // Pa ÷ Pa = 无量纲，压力比 [-] / dimensionless ratio [-]
IF fRatio <= 1.0 THEN
    RETURN; // LN 自变量闸：比值必须大于 1，否则对数为非正 [-] / the LN argument must exceed one [-]
END_IF
fTimeS := fVolPerSpeedS * LN(fRatio); // s × 无量纲 = s，抽气时间 [s] / [s] x [-] = [s]

// 段 4｜判定与饱和
IF NOT (fTimeS > -1.0E30 AND fTimeS < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
xTooLong := fTimeS > fLimitS; // 严格大于上限为过久，等于上限仍判合格 [s] / strict compare [s]

// 段 5｜出口自检
IF fTimeS < 0.0 THEN
    RETURN; // 出口自检：抽气时间不得为负（负值说明压力比给反） [s] / time must not be negative [s]
END_IF
FC_DL_VacuumPumpdownTimeCalc := fTimeS; // 返回抽气时间 [s] / return the pumpdown time [s]
END_FUNCTION
