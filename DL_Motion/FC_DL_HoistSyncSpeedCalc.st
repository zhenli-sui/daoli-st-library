(*
 * FC_DL_HoistSyncSpeedCalc | C2 | DL_Motion
 * 功能：双卷筒起升主从同步速度微调量与同步到位判定       单位：速度 [m/s]、增益 [1]、偏差 [m/s]
 * 工况边界：仅适用于主从同轴刚性/柔性双卷筒同步（不含位置闭环校正）；rTrimMaxMps 与 rDevLimitMps 须 >0 且有限，否则 xValid=FALSE 且微调量取 0；NaN/±Inf 一律拒算
 * 代数值回代：vMaster=0.50、vSlave=0.46、Kp=0.8、TrimMax=0.05、DevLimit=0.02 → dev=0.04、trim=0.032（未打限幅）、xInSync=FALSE（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_HoistSyncSpeedCalc : BOOL
VAR_INPUT
    rVMasterMps  : REAL;             // 主卷筒速度给定 | master drum speed reference [m/s]
    rVSlaveMps   : REAL;             // 从卷筒速度反馈 | slave drum speed feedback [m/s]
    rKp          : REAL := 0.8;      // 偏差比例增益（无量纲）| proportional gain on the deviation [1]
    rTrimMaxMps  : REAL := 0.05;     // 从卷筒微调量限幅 | slave trim magnitude limit [m/s]
    rDevLimitMps : REAL := 0.02;     // 同步判定偏差阈 | in-sync deviation threshold [m/s]
END_VAR
VAR_OUTPUT
    rSlaveTrimMps  : REAL;           // 从卷筒速度微调量（已限幅）| slave speed trim after limiting [m/s]
    rDevMps        : REAL;           // 主从速度偏差（主−从）| master minus slave deviation [m/s]
    rAbsDevMps     : REAL;           // 偏差绝对值（判据与告警同源）| absolute deviation shared by the criterion and the alarm [m/s]
    xInSync        : BOOL;           // 同步到位 | in-sync flag
    xTrimSaturated : BOOL;           // 微调量已打限幅（信息级）| trim saturated, informational only
    xValid         : BOOL;           // 输出有效 | outputs valid
END_VAR
VAR
    xFinM   : BOOL;                  // 主速度有限性 | master speed is finite
    xFinS   : BOOL;                  // 从速度有限性 | slave speed is finite
    xFinKp  : BOOL;                  // 增益有限性 | gain is finite
    xFinMax : BOOL;                  // 限幅有限性 | trim limit is finite
    xFinDev : BOOL;                  // 判定阈有限性 | deviation threshold is finite
    rTrimRaw: REAL;                  // 未限幅微调量 | raw trim before limiting [m/s]
END_VAR

// 段1｜非有限闸（R19：非有限一律出口取 0 并置 xValid=FALSE）
xFinM := (rVMasterMps = rVMasterMps) AND ((rVMasterMps - rVMasterMps) = 0.0);
xFinS := (rVSlaveMps = rVSlaveMps) AND ((rVSlaveMps - rVSlaveMps) = 0.0);
xFinKp := (rKp = rKp) AND ((rKp - rKp) = 0.0);
xFinMax := (rTrimMaxMps = rTrimMaxMps) AND ((rTrimMaxMps - rTrimMaxMps) = 0.0);
xFinDev := (rDevLimitMps = rDevLimitMps) AND ((rDevLimitMps - rDevLimitMps) = 0.0);
IF (NOT xFinM) OR (NOT xFinS) OR (NOT xFinKp) OR (NOT xFinMax) OR (NOT xFinDev) THEN
    rSlaveTrimMps := 0.0;            // 安全值：不加微调，从卷筒按原给定 | safe value, no trim applied
    rDevMps := 0.0;
    rAbsDevMps := 0.0;
    xInSync := FALSE;                // 不可判定即判不同步，禁止联动起升 | not judgeable means out of sync
    xTrimSaturated := FALSE;
    xValid := FALSE;
    FC_DL_HoistSyncSpeedCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：限幅与判定阈必须为正（LIMIT 边界必须有界）
IF (rTrimMaxMps <= 0.0) OR (rDevLimitMps <= 0.0) THEN
    rSlaveTrimMps := 0.0;
    rDevMps := 0.0;
    rAbsDevMps := 0.0;
    xInSync := FALSE;
    xTrimSaturated := FALSE;
    xValid := FALSE;
    FC_DL_HoistSyncSpeedCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：dev = 主 − 从；trim = LIMIT(−max, Kp*dev, max)；同步判据用未钳位的原始偏差
rDevMps := rVMasterMps - rVSlaveMps;
rAbsDevMps := ABS(rDevMps);                                // 判据与告警同源（R24）| criterion and alarm share the same source
rTrimRaw := rKp * rDevMps;
rSlaveTrimMps := LIMIT(-rTrimMaxMps, rTrimRaw, rTrimMaxMps);
xTrimSaturated := ABS(rTrimRaw) > rTrimMaxMps;             // 打限幅即置信息位 | flag saturation as information
xInSync := rAbsDevMps <= rDevLimitMps;                     // 用原始偏差判定，不受限幅影响 | judged on the raw deviation

// 段4｜出口
xValid := TRUE;
FC_DL_HoistSyncSpeedCalc := TRUE;
END_FUNCTION
