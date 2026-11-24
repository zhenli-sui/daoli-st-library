// =====================================================================
// FB_DL_ChwDifferentialPressure.st
// 冷冻水差压旁通控制（压差平滑 + 设定值重置限速 + PID 指令注入 + 阀位限幅）
// CHW differential pressure bypass control with smoothing and valve clamp
// 所属子库: DL_Algo    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0002_372E ~ 16#0002_3732 (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: hvac, chw, differential-pressure, pid
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 18)
// 分层声明: 压差平滑组合消费 DL_MathData 的 FB_DL_MovingAverage 实例;
//           设定值重置限速组合消费 DL_Algo 的 FB_DL_RateLimiter 实例
//           （斜坡防水锤）; PID 闭环本身不内联, 控制件阀位指令输出经引脚注入
// =====================================================================
FUNCTION_BLOCK FB_DL_ChwDifferentialPressure
VAR_INPUT
    bEnable        : BOOL  := FALSE;   // 使能 / Enable
    fDp_kPa        : REAL  := 0.0;     // 供回水压差 0~400 kPa / Supply-return dP [kPa]
    fDpSet_kPa     : REAL  := 120.0;   // 压差设定值 0~400 kPa / dP setpoint [kPa]
    fPidOut_Pct    : REAL  := 0.0;     // PID 阀位指令注入（控制件 fOut 语义）/ PID valve command injected [pct]
    fValveMin_Pct  : REAL  := 0.0;     // 阀位下限 0~100 百分比 / Valve lower limit [pct]
    fValveMax_Pct  : REAL  := 100.0;   // 阀位上限 0~100 百分比 / Valve upper limit [pct]
    fResetRate_kPa_s: REAL := 5.0;     // 设定值重置限速 0~100 kPa/s, 0 = 不限 / Setpoint reset rate [kPa/s]
END_VAR
VAR_OUTPUT
    fValveOut_Pct  : REAL  := 0.0;    // 旁通阀位输出 / Bypass valve output [pct]
    fDpSmooth_kPa  : REAL  := 0.0;    // 平滑后压差 / Smoothed dP [kPa]
    bByPassActive  : BOOL  := FALSE;  // 旁通投入标志 / Bypass active flag
    eErr           : UDINT := 16#0002_372E;  // 错误码 / Error code
END_VAR
VAR
    movAvg      : FB_DL_MovingAverage;  // 压差平滑实例（组合消费）/ Smoothing instance, composed
    ratSet      : FB_DL_RateLimiter;    // 设定值限速实例（组合消费）/ Setpoint rate limiter instance
    bCfgErr     : BOOL  := FALSE;   // 组态非法标记 / Configuration error flag
    bInFErr     : BOOL  := FALSE;   // 输入非有限标记 / Input non-finite flag
    bSatInfo    : BOOL  := FALSE;   // 阀位限幅饱和信息标记 / Valve saturation info flag
    fValveHold  : REAL  := 0.0;     // 阀位保持量（非有限拍保持）/ Valve hold value [pct]
    fValveCmd   : REAL  := 0.0;     // 阀位指令临时量 / Valve command temporary [pct]
    fSetUse     : REAL  := 0.0;     // 限速后设定值（诊断保持）/ Rate-limited setpoint [kPa]
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0002_372E 信息 旁通控制正常
//   16#0002_372F 故障 输入非有限（压差或 PID 指令注入非有限, 阀位保持上拍值,
//                不新增动作）; 解除式 = 输入恢复有限
//   16#0002_3730 故障 组态非法（设定值越出 0~400 kPa, 阀限幅越域或倒置,
//                重置速率越出 0~100 kPa/s）; 解除式 = 恢复合法组态
//   16#0002_3731 信息 阀位限幅饱和（PID 指令越出阀限幅, 已钳位输出）
//   16#0002_3732 信息 待机未使能（阀位回下限, 旁通关闭安全侧）
// ---------------------------------------------------------------------

// ---- 组态闸 / Configuration gate ----
bCfgErr := FALSE;
IF (fDpSet_kPa <> fDpSet_kPa) OR (fDpSet_kPa < 0.0) OR (fDpSet_kPa > 400.0) THEN
    bCfgErr := TRUE;                // 设定值越域 / Setpoint out of domain
END_IF
IF (fValveMin_Pct <> fValveMin_Pct) OR (fValveMin_Pct < 0.0) OR (fValveMin_Pct > 100.0) THEN
    bCfgErr := TRUE;                // 下限越域 / Lower limit out of domain
END_IF
IF (fValveMax_Pct <> fValveMax_Pct) OR (fValveMax_Pct < 0.0) OR (fValveMax_Pct > 100.0) THEN
    bCfgErr := TRUE;                // 上限越域 / Upper limit out of domain
END_IF
IF (NOT bCfgErr) AND (fValveMin_Pct >= fValveMax_Pct) THEN
    bCfgErr := TRUE;                // 阀限幅倒置 / Inverted valve limits
END_IF
IF (fResetRate_kPa_s <> fResetRate_kPa_s) OR (fResetRate_kPa_s < 0.0) OR (fResetRate_kPa_s > 100.0) THEN
    bCfgErr := TRUE;                // 重置速率越域 / Reset rate out of domain
END_IF

// ---- 输入非有限判 / Input finite judge ----
bInFErr := (fDp_kPa <> fDp_kPa) OR (ABS(fDp_kPa) >= 1.0E12)
        OR (fPidOut_Pct <> fPidOut_Pct) OR (ABS(fPidOut_Pct) >= 1.0E12);

// ---- 压差平滑消费（组合实例调用）/ Smoothing via composed instance ----
movAvg(fInput := fDp_kPa, nWindowSize := 8,
       bSample := bEnable AND (NOT bInFErr) AND (NOT bCfgErr),
       bEnable := bEnable, bReset := FALSE);
fDpSmooth_kPa := movAvg.fAverage;   // 平滑压差输出 / Smoothed dP output

// ---- 设定值重置限速消费（组合实例调用, 斜坡防水锤）/ Setpoint rate limit ----
ratSet(bEnable := bEnable AND (NOT bCfgErr), fIn := fDpSet_kPa,
       fRateUp := fResetRate_kPa_s, fRateDown := fResetRate_kPa_s,
       bTrack := (NOT bEnable), fTrackValue := fDpSet_kPa,
       tSampleTime := T#100MS);
fSetUse := ratSet.fOut;             // 限速后设定值保持（供上位诊断）/ Held setpoint for diagnostics

// ---- 待机安全侧: 阀位回下限（旁通关闭）/ Standby: valve to lower limit ----
IF NOT bEnable THEN
    fValveOut_Pct := fValveMin_Pct; // 关闭旁通 / Close bypass
    fValveHold := fValveMin_Pct;    // 保持量同步 / Sync hold
    bByPassActive := FALSE;         // 旁通退出 / Bypass off
    eErr := 16#0002_3732;           // 待机码 / Standby code
ELSIF bInFErr OR bCfgErr THEN
    // 非有限或组态非法: 阀位保持上拍值, 不新增动作 / Hold valve, no new action
    fValveOut_Pct := fValveHold;
    bByPassActive := FALSE;
    IF bCfgErr THEN
        eErr := 16#0002_3730;       // 组态码 / Config code
    ELSE
        eErr := 16#0002_372F;       // 非有限码 / Non-finite code
    END_IF
ELSE
    // ---- 阀位指令限幅输出 / Valve command with clamping ----
    fValveCmd := fPidOut_Pct;       // PID 指令注入 / Injected PID command
    bSatInfo := FALSE;
    IF fValveCmd > fValveMax_Pct THEN
        fValveCmd := fValveMax_Pct; // 上限钳位 / Clamp upper
        bSatInfo := TRUE;           // 置饱和信息 / Set saturation info
    END_IF
    IF fValveCmd < fValveMin_Pct THEN
        fValveCmd := fValveMin_Pct; // 下限钳位 / Clamp lower
        bSatInfo := TRUE;
    END_IF
    fValveOut_Pct := fValveCmd;     // 阀位输出 / Valve output
    fValveHold := fValveCmd;        // 更新保持量 / Update hold
    // 旁通投入判（容差比较, 浮点禁直接判等）/ Bypass active with margin
    bByPassActive := (fValveOut_Pct - fValveMin_Pct) > 0.1;
    IF bSatInfo THEN
        eErr := 16#0002_3731;       // 饱和信息 / Saturation info
    ELSE
        eErr := 16#0002_372E;       // 正常 / Normal
    END_IF
END_IF

END_FUNCTION_BLOCK
