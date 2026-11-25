(*
  ============================================================
  组件名 : FC_DL_RefCompressorCapacity
  分类   : DL_Device
  功能   : 压缩机质量流量与制冷量估算，按理论排量、转速比、容积效率与吸气密度折算
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_RefCompressorCapacity : REAL
VAR_INPUT
    rSweptVol_m3h    : REAL; // 理论排气量 [m3/h] theoretical swept volume [m3 per hour]
    rSpeed_rpm       : REAL; // 实测转速 [rpm] measured rotational speed [rpm]
    rSpeedRated_rpm  : REAL; // 额定转速 [rpm] rated rotational speed [rpm]
    rVolEff          : REAL; // 容积效率 0~1 [无量纲] volumetric efficiency from zero to one [dimensionless]
    rSuctionDens_kgm3: REAL; // 吸气密度 [kg/m3] suction gas density [kg per cubic metre]
    rDh_kJkg         : REAL; // 吸气到排气的焓差 [kJ/kg] enthalpy rise from suction to discharge [kJ per kilogram]
END_VAR
VAR_OUTPUT
    rMassFlow_kgh : REAL; // 质量流量 [kg/h] mass flow [kg per hour]
    rCapEst_kW    : REAL; // 估算制冷量 [kW] estimated cooling capacity [kW]
    bValid        : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_SEC_PER_HOUR : REAL := 3600.0; // 每小时秒数 seconds per hour
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 六输入有限性判定 finiteness verdict of the six inputs
    _rSpeedRatio : REAL := 0.0; // 转速比 [无量纲] speed ratio [dimensionless]
    _rMass : REAL := 0.0; // 质量流量中间量 [kg/h] intermediate mass flow [kg per hour]
    _rCap  : REAL := 0.0; // 制冷量中间量 [kW] intermediate capacity [kW]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_RefCompressorCapacity := 0.0; // 缺省返回零 default zero return
rMassFlow_kgh := 0.0; // 质量流量预置零 mass flow preset to zero
rCapEst_kW := 0.0; // 制冷量预置零 capacity preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rSweptVol_m3h = rSweptVol_m3h) AND (rSpeed_rpm = rSpeed_rpm) AND (rSpeedRated_rpm = rSpeedRated_rpm) AND (rVolEff = rVolEff) AND (rSuctionDens_kgm3 = rSuctionDens_kgm3) AND (rDh_kJkg = rDh_kJkg); // 六输入自反判定 self comparison of the six inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜转速与效率闸 speed and efficiency gate
IF (rSpeedRated_rpm <= 0.0) OR (rSpeed_rpm < 0.0) THEN
    RETURN; // 额定转速非正或负转速 an illegal rated or measured speed
END_IF
IF (rVolEff <= 0.0) OR (rVolEff > 1.0) THEN
    RETURN; // 容积效率越出零到一 volumetric efficiency outside the open closed interval
END_IF
IF (rSweptVol_m3h < 0.0) OR (rSuctionDens_kgm3 <= 0.0) OR (rDh_kJkg <= 0.0) THEN
    RETURN; // 排量密度或焓差非法 an illegal swept volume density or enthalpy rise
END_IF
// 段 4｜转速比与质量流量 speed ratio and the mass flow
_rSpeedRatio := rSpeed_rpm / rSpeedRated_rpm; // 转速比，除子已证为正 speed ratio over a proven positive divisor
_rMass := rSweptVol_m3h * _rSpeedRatio * rVolEff * rSuctionDens_kgm3; // 排量乘转速比效率密度 swept volume times ratio efficiency and density
rMassFlow_kgh := _rMass; // 质量流量落定 land the mass flow
// 段 5｜焓差折算制冷量 enthalpy rise converted to capacity
_rCap := _rMass * rDh_kJkg / DL_SEC_PER_HOUR; // 千焦每小时折算为千瓦 kilojoule per hour becomes kilowatt
rCapEst_kW := _rCap; // 制冷量落定 land the capacity
bValid := TRUE; // 结果可用 result usable
FC_DL_RefCompressorCapacity := _rMass; // 函数返回质量流量 return the mass flow
END_FUNCTION
