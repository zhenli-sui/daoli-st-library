(*
 * FC_DL_CoreSandBakeCurveCalc | C2 | DL_Process
 * 功能：芯砂烘干升温曲线（升温段、总时间）与保温后残余水分       单位：温度 [℃]、升温速率 [K/min]、时间 [min]、水分 [%]
 * 工况边界：升温段按线性斜坡、保温段按一阶指数衰减残余水分 res=1.5×EXP(−hold/40)；升温速率须 >0、目标温度须高于起始温度，否则判 9716；本件不含分段升温与露点控制
 * 代数值回代：target=200、start=25、rate=3 → ramp=175/3=58.33 min；total=58.33+60=118.33 min；res=1.5×EXP(−60/40)=1.5×0.2231=0.335 %（spec 记 0.33 %，一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_CoreSandBakeCurveCalc : BOOL
VAR_INPUT
    rTargetC   : REAL := 200.0;      // 目标烘干温度 | target baking temperature [℃]
    rRampKmin  : REAL := 3.0;        // 升温速率 | heating rate [K/min]
    rStartC    : REAL := 25.0;       // 起始温度 | starting temperature [℃]
    rHoldMin   : REAL := 60.0;       // 保温时间 | holding time [min]
END_VAR
VAR_OUTPUT
    rRampMin        : REAL;          // 升温段时间 | ramp duration [min]
    rTotalMin       : REAL;          // 总时间（升温+保温）| total time, ramp plus hold [min]
    rResidualMoistPct : REAL;        // 保温后残余水分 | residual moisture after holding [%]
    xValid          : BOOL;          // 输出有效 | outputs valid
    nFaultCode      : INT;           // 0=无 / 9716=温度或速率非法 | 0 none, 9716 illegal temperature or rate
END_VAR
VAR
    xFinTg  : BOOL;                  // 目标温度有限性 | target temperature is finite
    xFinRt  : BOOL;                  // 升温速率有限性 | heating rate is finite
    xFinSt  : BOOL;                  // 起始温度有限性 | starting temperature is finite
    xFinHd  : BOOL;                  // 保温时间有限性 | holding time is finite
END_VAR
VAR CONSTANT
    DL_CSB_MOIST0   : REAL := 1.5;   // 保温起始残余水分基准 | residual moisture at the start of holding [%]
    DL_CSB_TAU_MIN  : REAL := 40.0;  // 水分衰减时间常数 | moisture decay time constant [min]
END_VAR

// 段1｜非有限闸（R19）
xFinTg := (rTargetC = rTargetC) AND ((rTargetC - rTargetC) = 0.0);
xFinRt := (rRampKmin = rRampKmin) AND ((rRampKmin - rRampKmin) = 0.0);
xFinSt := (rStartC = rStartC) AND ((rStartC - rStartC) = 0.0);
xFinHd := (rHoldMin = rHoldMin) AND ((rHoldMin - rHoldMin) = 0.0);
IF (NOT xFinTg) OR (NOT xFinRt) OR (NOT xFinSt) OR (NOT xFinHd) THEN
    rRampMin := 0.0;                 // 安全值：时间 0 | safe value, zero times
    rTotalMin := 0.0;
    rResidualMoistPct := 0.0;
    xValid := FALSE;
    nFaultCode := 9716;
    FC_DL_CoreSandBakeCurveCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：速率入分母须 >0，目标须高于起始，保温时间非负
IF (rRampKmin <= 0.0) OR (rTargetC <= rStartC) OR (rHoldMin < 0.0) THEN
    rRampMin := 0.0;
    rTotalMin := 0.0;
    rResidualMoistPct := 0.0;
    xValid := FALSE;
    nFaultCode := 9716;
    FC_DL_CoreSandBakeCurveCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：ramp=(target−start)/rate；total=ramp+hold；res=1.5×EXP(−hold/40)
rRampMin := (rTargetC - rStartC) / rRampKmin;
rTotalMin := rRampMin + rHoldMin;
rResidualMoistPct := DL_CSB_MOIST0 * EXP(-rHoldMin / DL_CSB_TAU_MIN);

// 段4｜出口
nFaultCode := 0;
xValid := TRUE;
FC_DL_CoreSandBakeCurveCalc := TRUE;
END_FUNCTION
