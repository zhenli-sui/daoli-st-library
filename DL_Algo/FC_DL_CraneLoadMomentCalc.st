(*
 * FC_DL_CraneLoadMomentCalc | C2 | DL_Algo
 * 功能：载荷倾覆力矩、抗倾覆力矩与安全系数（含重心偏移附加判据）       单位：质量 [t]、长度 [m]、力矩 [t·m]、安全系数 [1]
 * 工况边界：抗倾覆力矩采用 spec 简化式 Mr=W_crane×轮距/2（整机按最不利支腿回转取轮距半宽）；重心偏移 rCgDistM 仅作为附加稳定判据（超过轮距半宽即判不安全），不进入 Mr 计算；吊重与跨距须 >0 且有限
 * 代数值回代：load=40 t @40 m → Mo=1600 t·m；crane=1000 t、轮距 16 m → Mr=1000×8=8000 t·m；SF=8000/1600=5.0 ≥1.5 → xSafe=TRUE（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_CraneLoadMomentCalc : BOOL
VAR_INPUT
    rLoadT        : REAL;            // 吊重（含吊具）| lifted load including the spreader [t]
    rOutreachM    : REAL;            // 工作幅度（回转中心至吊重）| working outreach [m]
    rCraneWeightT : REAL;            // 整机自重 | crane dead weight [t]
    rCgDistM      : REAL;            // 整机重心至回转中心距离 | centre of gravity offset from the slew centre [m]
    rWheelBaseM   : REAL := 16.0;    // 大车轮距（轨距）| rail gauge or wheel base [m]
    rSfMin        : REAL := 1.5;     // 要求最小抗倾覆安全系数 | required minimum safety factor [1]
END_VAR
VAR_OUTPUT
    rOverturnMomentTm : REAL;        // 倾覆力矩 Mo | overturning moment [t·m]
    rResistMomentTm   : REAL;        // 抗倾覆力矩 Mr | resisting moment [t·m]
    rSafetyFactor     : REAL;        // 安全系数 SF=Mr/Mo | safety factor [1]
    xSafe             : BOOL;        // 稳定判定（SF≥限值 且 重心不越界）| stable verdict
    xCgOverLimit      : BOOL;        // 重心偏移越界（信息级）| centre of gravity out of range, informational
    xValid            : BOOL;        // 输出有效 | outputs valid
END_VAR
VAR
    xFinLoad  : BOOL;                // 吊重有限性 | load is finite
    xFinOut   : BOOL;                // 幅度有限性 | outreach is finite
    xFinW     : BOOL;                // 自重有限性 | dead weight is finite
    xFinCg    : BOOL;                // 重心偏移有限性 | centre of gravity offset is finite
    xFinWb    : BOOL;                // 轮距有限性 | wheel base is finite
    xFinSf    : BOOL;                // 安全系数限值有限性 | safety factor limit is finite
END_VAR
VAR CONSTANT
    DL_CLM_EPS : REAL := 1.0E-9;     // 除零保护阈值 | division guard threshold [t·m]
END_VAR

// 段1｜非有限闸（R19）
xFinLoad := (rLoadT = rLoadT) AND ((rLoadT - rLoadT) = 0.0);
xFinOut := (rOutreachM = rOutreachM) AND ((rOutreachM - rOutreachM) = 0.0);
xFinW := (rCraneWeightT = rCraneWeightT) AND ((rCraneWeightT - rCraneWeightT) = 0.0);
xFinCg := (rCgDistM = rCgDistM) AND ((rCgDistM - rCgDistM) = 0.0);
xFinWb := (rWheelBaseM = rWheelBaseM) AND ((rWheelBaseM - rWheelBaseM) = 0.0);
xFinSf := (rSfMin = rSfMin) AND ((rSfMin - rSfMin) = 0.0);
IF (NOT xFinLoad) OR (NOT xFinOut) OR (NOT xFinW) OR (NOT xFinCg)
   OR (NOT xFinWb) OR (NOT xFinSf) THEN
    rOverturnMomentTm := 0.0;        // 安全值：力矩 0 | safe value, zero moments
    rResistMomentTm := 0.0;
    rSafetyFactor := 0.0;            // 安全值：安全系数 0（判不稳）| safe value, zero factor means unstable
    xSafe := FALSE;
    xCgOverLimit := TRUE;
    xValid := FALSE;
    FC_DL_CraneLoadMomentCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：吊重与幅度必须为正（Mo 入分母），轮距与安全系数限值必须为正
IF (rLoadT <= 0.0) OR (rOutreachM <= 0.0) OR (rWheelBaseM <= 0.0) OR (rSfMin <= 0.0) THEN
    rOverturnMomentTm := 0.0;
    rResistMomentTm := 0.0;
    rSafetyFactor := 0.0;
    xSafe := FALSE;
    xCgOverLimit := TRUE;
    xValid := FALSE;
    FC_DL_CraneLoadMomentCalc := FALSE;
    RETURN;
END_IF

// 段3｜力矩：Mo = W_load×L_out；Mr = W_crane×轮距/2（spec 简化式）
rOverturnMomentTm := rLoadT * rOutreachM;
rResistMomentTm := rCraneWeightT * (rWheelBaseM / 2.0);

// 段4｜安全系数：分母 Mo 已由段2保证 >0，仍按阈值显式防零
IF rOverturnMomentTm > DL_CLM_EPS THEN
    rSafetyFactor := rResistMomentTm / rOverturnMomentTm;
ELSE
    rSafetyFactor := 0.0;            // 理论上不可达（段2已排除），防御性兜底 | unreachable defence
END_IF

// 段5｜稳定判定：安全系数达标 且 重心不越轮距半宽（判据与出口同源于原始输入）
xCgOverLimit := rCgDistM > (rWheelBaseM / 2.0 + 1.0E-6);
xSafe := (rSafetyFactor >= rSfMin) AND (NOT xCgOverLimit);
xValid := TRUE;
FC_DL_CraneLoadMomentCalc := TRUE;
END_FUNCTION
