(*
 * FC_DL_BatteryBackupTimeCalc | C2 | DL_Device
 * 功能：电池组恒功率放电后备时间（含寿命末期与放电效率修正）       单位：容量 [Ah]、电压 [V]、功率 [kW]、时间 [min]、修正系数 [1]
 * 工况边界：恒功率简化模型（不含 Peukert 效应与温度修正，温度影响由 rDerate 吸收）；负载功率须 >0（入分母），容量、电压须 >0，两修正系数须在 (0,1]；电池组按串联单体电压和计算
 * 代数值回代：C=200 Ah、V=480 V、P=100 kW、derate=0.85、eol=0.8 → 200×480×0.85×0.8=65280 Wh；65280/100000=0.6528 h=39.17 min（spec 记 39.2 min，一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_BatteryBackupTimeCalc : BOOL
VAR_INPUT
    rCapacityAh : REAL := 200.0;     // 电池组额定容量 | battery string rated capacity [Ah]
    rStringV    : REAL := 480.0;     // 电池组标称电压 | battery string nominal voltage [V]
    rLoadKw     : REAL := 100.0;     // 放电负载功率 | discharge load power [kW]
    rDerate     : REAL := 0.85;      // 放电效率与温度综合修正 | combined discharge efficiency and temperature derating [1]
    rEolFactor  : REAL := 0.8;       // 寿命末期容量保持率 | end of life capacity retention [1]
END_VAR
VAR_OUTPUT
    rBackupMin : REAL;               // 后备时间 | backup time [min]
    rEnergyWh  : REAL;               // 可用能量 | usable energy [Wh]
    xValid     : BOOL;               // 输出有效 | outputs valid
END_VAR
VAR
    xFinC   : BOOL;                  // 容量有限性 | capacity is finite
    xFinV   : BOOL;                  // 电压有限性 | voltage is finite
    xFinP   : BOOL;                  // 功率有限性 | load power is finite
    xFinDr  : BOOL;                  // 效率修正有限性 | derating factor is finite
    xFinEol : BOOL;                  // 寿命修正有限性 | end of life factor is finite
    rPW     : REAL;                  // 负载功率（W）| load power in watts [W]
END_VAR
VAR CONSTANT
    DL_BBT_MIN_PER_HOUR : REAL := 60.0;    // 小时转分系数 | hours to minutes factor [min/h]
    DL_BBT_W_PER_KW     : REAL := 1000.0;  // 千瓦转瓦系数 | kilowatts to watts factor [W/kW]
    DL_BBT_P_MIN        : REAL := 1.0E-9;  // 负载功率下限（防零除）| load power lower bound [W]
END_VAR

// 段1｜非有限闸（R19）
xFinC := (rCapacityAh = rCapacityAh) AND ((rCapacityAh - rCapacityAh) = 0.0);
xFinV := (rStringV = rStringV) AND ((rStringV - rStringV) = 0.0);
xFinP := (rLoadKw = rLoadKw) AND ((rLoadKw - rLoadKw) = 0.0);
xFinDr := (rDerate = rDerate) AND ((rDerate - rDerate) = 0.0);
xFinEol := (rEolFactor = rEolFactor) AND ((rEolFactor - rEolFactor) = 0.0);
IF (NOT xFinC) OR (NOT xFinV) OR (NOT xFinP) OR (NOT xFinDr) OR (NOT xFinEol) THEN
    rBackupMin := 0.0;               // 安全值：后备时间 0 | safe value, zero backup time
    rEnergyWh := 0.0;
    xValid := FALSE;
    FC_DL_BatteryBackupTimeCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：容量/电压/功率须为正，两修正系数须在 (0,1]
IF (rCapacityAh <= 0.0) OR (rStringV <= 0.0) OR (rLoadKw <= 0.0)
   OR (rDerate <= 0.0) OR (rDerate > 1.0) OR (rEolFactor <= 0.0) OR (rEolFactor > 1.0) THEN
    rBackupMin := 0.0;
    rEnergyWh := 0.0;
    xValid := FALSE;
    FC_DL_BatteryBackupTimeCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：可用能量 Wh 与后备时间 min
rEnergyWh := rCapacityAh * rStringV * rDerate * rEolFactor;
rPW := rLoadKw * DL_BBT_W_PER_KW;
IF rPW > DL_BBT_P_MIN THEN
    rBackupMin := rEnergyWh / rPW * DL_BBT_MIN_PER_HOUR;
ELSE
    rBackupMin := 0.0;               // 理论不可达（段2已排除），防御性兜底 | unreachable defence
END_IF

// 段4｜出口
xValid := TRUE;
FC_DL_BatteryBackupTimeCalc := TRUE;
END_FUNCTION
