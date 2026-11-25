// FB_DL_VocVentTrim v1.0.0
// 开源溯源：self-cleanroom / HVAC 域延伸
(*
  道莅工业代码库 | DL_Process | FB_DL_VocVentTrim
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: VOC 浓度需求通风 trim：按 VOC 实测-设定偏差比例调节新风阀开度，
        持续超限升入 boost 相全开，迟滞回落
  邻件关系: 与 RoomCo2DemandVent 同构异介质 —— 差异点：邻件介质为 CO2
            （ppm 域 ~400-2000，比例增益按人体舒适域标定），本件介质为
            VOC（ppb/ppm 域，阈值按工业卫生限值标定，boost 相出口口径
            与换气次数系数独立），控制律同构（比例 trim + 超限 boost），
            码位独立（本件 16#0002_2501，避让 CO2 件码段）
*)
TYPE E_DL_VocVentPhase :
(
    eIdle  := 0,    // 空闲（失能）/ Idle, disabled
    eTrim  := 10,   // 比例 trim 相 / Proportional trim phase
    eBoost := 20,   // 超限 boost 相（全开）/ Boost phase, full open
    eFault := 90    // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_VocVentTrim
VAR_INPUT
    bEnable      : BOOL := FALSE;             // 总使能，FALSE 阀门回最小 / Master enable
    fVocPpm      : REAL := 0.0;               // VOC 实测浓度 [ppm]，域 0..100 / Measured VOC [ppm]
    fVocSetPpm   : REAL := 10.0;              // VOC 设定阈值 [ppm]，域 > 0 / VOC setpoint [ppm]
    fBoostPpm    : REAL := 20.0;              // boost 触发阈值 [ppm]，域 > 设定 / Boost trigger threshold [ppm]
    fTrimGainPct : REAL := 10.0;              // trim 增益 [百分点每 ppm] / Trim gain [pct per ppm]
    fVentMinPct  : REAL := 0.0;               // 新风阀最小开度 [%] / Vent minimum [%]
    fVentMaxPct  : REAL := 100.0;             // 新风阀最大开度 [%] / Vent maximum [%]
    fHystPpm     : REAL := 2.0;               // boost 退出迟滞 [ppm] / Boost exit hysteresis [ppm]
END_VAR
VAR_OUTPUT
    fVentCmdPct  : REAL;                      // 新风阀开度指令 [%] / Vent command [%]
    bBoost       : BOOL;                      // boost 相标志 [-] / Boost phase flag
    bValid       : BOOL;                      // 组态有效回执 [-] / Config validity receipt
    bError       : BOOL;                      // 故障标志，与故障级码配对 / Fault flag paired with fault code
    uErrorId     : UDINT;                     // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut    : E_DL_VocVentPhase;         // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState      : E_DL_VocVentPhase := E_DL_VocVentPhase.eIdle;   // 内部状态 / Internal state
    bCfgOk       : BOOL;                      // 组态闸结果 [-] / Config gate result
    bMeasOk      : BOOL;                      // 测量域闸结果 [-] / Measurement gate result
    fError       : REAL;                      // 偏差 = 实测 - 设定 [ppm] / Error = measured - setpoint
    fCmd         : REAL;                      // 开度指令暂存 [%] / Command buffer [%]
END_VAR

// —— 段 0：全路径缺省（输出中性值） —— //
fVentCmdPct := fVentMinPct;                   // 开度缺省最小（安全位）/ Command default minimum
bBoost := FALSE;                              // boost 标志预清 / Boost preset
bValid := FALSE;                              // 有效回执预清 / Validity preset
bError := FALSE;                              // 故障预清（组态非法路径置位）/ Fault preset
uErrorId := 16#0000;                          // 事件码预清 / Event code preset

// —— 段 1：组态闸与测量域闸 —— //
bCfgOk := (fVocSetPpm > 0.0) AND (fBoostPpm > fVocSetPpm) AND (fVentMaxPct > fVentMinPct)
          AND (fHystPpm >= 0.0) AND (fVocSetPpm = fVocSetPpm) AND (fBoostPpm = fBoostPpm);   // 组态单调 + NaN 闸 / Config monotonic and NaN gate
bMeasOk := (fVocPpm >= 0.0) AND (fVocPpm <= 100.0) AND (fVocPpm = fVocPpm);   // 测量域闸 / Measurement domain gate
IF NOT bCfgOk THEN
    bValid := FALSE;                          // 组态回执降级 / Validity degraded
    bError := TRUE;                           // 故障级：组态非法 / Fault level: invalid config
    uErrorId := 16#0002_2501;                 // 故障码（25xx 步进）/ Fault code
    fVentCmdPct := fVentMinPct;               // 阀门回最小（安全位）/ Vent to minimum
    RETURN;
END_IF
bValid := TRUE;                               // 组态有效回执 / Validity receipt

// —— 段 2：主状态机（ENUM + CASE，含 ELSE 兜底） —— //
CASE _eState OF
E_DL_VocVentPhase.eIdle :
    fCmd := fVentMinPct;                      // 空闲最小开度（安全位）/ Idle minimum
    IF bEnable AND bMeasOk THEN
        _eState := E_DL_VocVentPhase.eTrim;   // 使能且测量有效进 trim 相 / Enabled with valid measurement
    END_IF

E_DL_VocVentPhase.eTrim :
    IF NOT bMeasOk THEN
        fCmd := fVentMinPct;                  // 测量失效：回安全位（本拍不推进）/ Measurement invalid: safe position
        _eState := E_DL_VocVentPhase.eIdle;   // 回空闲等有效测量（退出条件 1：前置消失）/ Exit condition 1
    ELSIF fVocPpm >= fBoostPpm THEN
        fCmd := fVentMaxPct;                  // 超限：本拍即全开（抢先行为）/ Over limit: full open immediately
        _eState := E_DL_VocVentPhase.eBoost;  // 升入 boost 相 / Enter boost
    ELSE
        fError := fVocPpm - fVocSetPpm;       // 偏差 [ppm] / Error [ppm]
        IF fError < 0.0 THEN
            fError := 0.0;                    // 负偏差不回关（通风只增不减，滞环防抖）/ Nonnegative error
        END_IF
        fCmd := fVentMinPct + fError * fTrimGainPct;   // 比例 trim 指令 / Proportional trim command
        IF fCmd > fVentMaxPct THEN
            fCmd := fVentMaxPct;              // 上限钳位 / Clamp high
        END_IF
        IF fCmd < fVentMinPct THEN
            fCmd := fVentMinPct;              // 下限钳位 / Clamp low
        END_IF
        IF NOT bEnable THEN
            _eState := E_DL_VocVentPhase.eIdle;   // 失能回空闲（退出条件 2）/ Exit condition 2
        END_IF
    END_IF

E_DL_VocVentPhase.eBoost :
    fCmd := fVentMaxPct;                      // boost 相全开 / Boost full open
    bBoost := TRUE;                           // boost 标志 / Boost flag
    IF (NOT bMeasOk) OR (NOT bEnable) THEN
        bBoost := FALSE;                      // 失效/失能退出 boost（退出条件 1）/ Exit on invalid or disabled
        _eState := E_DL_VocVentPhase.eIdle;   // 回空闲 / To idle
    ELSIF fVocPpm < (fBoostPpm - fHystPpm) THEN
        bBoost := FALSE;                      // 浓度低于阈值减迟滞退出（退出条件 2）/ Exit below threshold with hysteresis
        _eState := E_DL_VocVentPhase.eTrim;   // 回 trim 相 / Back to trim
    END_IF

E_DL_VocVentPhase.eFault :
    fCmd := fVentMinPct;                      // 故障相安全位 / Fault safe position
    IF bCfgOk THEN
        _eState := E_DL_VocVentPhase.eIdle;   // 组态恢复解锁回空闲（解除路径可达）/ Unlock on valid config
    END_IF

ELSE
    _eState := E_DL_VocVentPhase.eFault;      // 非法状态拦截 / Illegal state interception
    uErrorId := 16#0002_2501;                 // 故障级：相 ID 越界 / Fault level: phase id out of range
    fCmd := fVentMinPct;                      // 安全位 / Safe position
END_CASE

// —— 段 3：输出映射（段尾单点） —— //
IF NOT bEnable THEN
    fCmd := fVentMinPct;                      // 失能最高优先回安全位 / Disabled highest priority
END_IF
fVentCmdPct := fCmd;                          // 开度指令输出 / Command output
eStateOut := _eState;                         // 输出枚举段尾单点映射 / Tail single-point mapping
END_FUNCTION_BLOCK
