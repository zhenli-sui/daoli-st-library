(*
  DL Factory R84 | FC_DL_RefinerFreenessCalc
  功能：由比边缘负荷与比能耗线性估算打浆度 CSF 并给目标偏差
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_RefinerFreenessCalc : REAL
VAR_INPUT
    fEdgeLoadJm : REAL := 1.2; // 比边缘负荷实测值 [J/m] / measured specific edge load [J/m]
    fSecKwhT : REAL := 120.0; // 比能耗 [kWh/t] / specific energy consumption [kWh/t]
    fCsfBaseMl : REAL := 650.0; // 基准打浆度（未打浆） [mL] / base freeness [mL]
    fKEffJm : REAL := 30.0; // 比边缘负荷影响系数 [mL·m/J] / edge load sensitivity [mL*m/J]
    fKEffKwhT : REAL := 0.6; // 比能耗影响系数 [mL/(kWh/t)] / energy sensitivity [mL/(kWh/t)]
    fCsfMinMl : REAL := 100.0; // 打浆度下限（钳位） [mL] / lower clamp [mL]
    fCsfMaxMl : REAL := 750.0; // 打浆度上限（钳位） [mL] / upper clamp [mL]
    fCsfTargetMl : REAL := 350.0; // 目标打浆度 [mL] / target freeness [mL]
END_VAR
VAR_OUTPUT
    fSelJm : REAL; // 比边缘负荷回显（链路校验） [J/m] / specific edge load echo [J/m]
    fDevMl : REAL; // 与目标打浆度偏差 [mL] / deviation from the target [mL]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fCsfRawMl : REAL; // 未钳位估算打浆度 [mL] / unclamped freeness estimate [mL]
    fCsfMl : REAL; // 钳位后打浆度 [mL] / clamped freeness [mL]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_RefinerFreenessCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fSelJm := 0.0; // 负荷回显预置零 [J/m] / load echo preset zero [J/m]
fDevMl := 0.0; // 偏差预置零 [mL] / deviation preset zero [mL]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fEdgeLoadJm > -1.0E30 AND fEdgeLoadJm < 1.0E30) OR NOT (fSecKwhT > -1.0E30 AND fSecKwhT < 1.0E30) OR NOT (fCsfBaseMl > -1.0E30 AND fCsfBaseMl < 1.0E30) THEN
    RETURN; // 负荷/能耗/基准值任一非有限即拒算 [-] / any non finite load, energy or base rejected [-]
END_IF
IF NOT (fKEffJm > -1.0E30 AND fKEffJm < 1.0E30) OR NOT (fKEffKwhT > -1.0E30 AND fKEffKwhT < 1.0E30) OR NOT (fCsfTargetMl > -1.0E30 AND fCsfTargetMl < 1.0E30) THEN
    RETURN; // 系数与目标值任一非有限即拒算 [-] / any non finite coefficient or target rejected [-]
END_IF
IF fEdgeLoadJm < 0.0 OR fSecKwhT < 0.0 OR fCsfBaseMl <= 0.0 OR fCsfTargetMl < 0.0 THEN
    RETURN; // 负荷/能耗非负 + 基准与目标正域闸 [J/m, kWh/t, mL] / non negative load and positive base gate [-]
END_IF
IF NOT (fCsfMinMl < fCsfMaxMl) THEN
    RETURN; // 钳位区间组态闸：下限必须严格小于上限 [mL] / clamp band config gate [mL]
END_IF

// 段 3｜线性估算：CSF = 基准 − k1×SEL − k2×SEC
fCsfRawMl := (fCsfBaseMl - (fKEffJm * fEdgeLoadJm)) - (fKEffKwhT * fSecKwhT); // mL − (mL·m/J × J/m) − (mL/(kWh/t) × kWh/t) = mL / [mL] terms subtracted, result in [mL]
IF NOT (fCsfRawMl > -1.0E30 AND fCsfRawMl < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF

// 段 4｜上下限钳位（线性近似仅在工艺区间内可信）
fCsfMl := fCsfRawMl; // 先接未钳位值 [mL] / take the raw estimate [mL]
IF fCsfMl > fCsfMaxMl THEN
    fCsfMl := fCsfMaxMl; // 上限钳位：过度打浆不成立 [mL] / clamp high, over refining is not physical [mL]
END_IF
IF fCsfMl < fCsfMinMl THEN
    fCsfMl := fCsfMinMl; // 下限钳位：湿重打浆极限 [mL] / clamp low, wet freeness floor [mL]
END_IF

// 段 5｜偏差与出口
fDevMl := fCsfMl - fCsfTargetMl; // mL − mL = mL / [mL] minus [mL] = [mL]
IF NOT (fDevMl > -1.0E30 AND fDevMl < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF
fSelJm := fEdgeLoadJm; // 回显实测比边缘负荷 [J/m] / echo the measured edge load [J/m]
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_RefinerFreenessCalc := fCsfMl; // 返回打浆度 [mL] / return the freeness [mL]
END_FUNCTION
