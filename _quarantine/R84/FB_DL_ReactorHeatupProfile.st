(*
  DL Factory R84 | FB_DL_ReactorHeatupProfile
  功能：反应釜升温程序段执行，按斜率追踪设定值并带超调抑制带与保温计时
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
TYPE E_DL_ReactorHeatState :
(
    eIdle := 0, // 空闲待启动 [-] / idle [-]
    eRamp := 1, // 升温斜率段 [-] / heating ramp phase [-]
    eHold := 2, // 保温段 [-] / holding phase [-]
    eCool := 3, // 降温段 [-] / cooling phase [-]
    eDone := 4, // 完成相 [-] / done phase [-]
    eFault := 5 // 故障锁存相 [-] / fault latched phase [-]
) := eIdle;
END_TYPE

FUNCTION_BLOCK FB_DL_ReactorHeatupProfile
VAR_INPUT
    xStart : BOOL; // 程序段启动命令 [-] / profile start command [-]
    xReset : BOOL; // 复位命令，上升沿清故障码 [-] / reset command [-]
    rPv : REAL; // 釜内实测温度 [℃] / measured batch temperature [C]
    rTargetC : REAL := 120.0; // 升温目标温度 [℃] / heating target temperature [C]
    rCoolTargetC : REAL := 40.0; // 降温目标温度 [℃] / cooling target temperature [C]
    fRampKmin : REAL := 1.0; // 升温斜率 [K/min] / heating ramp rate [K/min]
    fCoolKmin : REAL := 0.5; // 降温斜率 [K/min] / cooling ramp rate [K/min]
    fBandK : REAL := 2.0; // 超调抑制带/到位带宽 [K] / overshoot suppression band [K]
    tHoldLimit : TIME := T#30M; // 保温时长 [s] / holding duration [s]
    tScan : TIME := T#100MS; // 扫描周期 [s] / scan period [s]
END_VAR
VAR_OUTPUT
    eState : E_DL_ReactorHeatState; // 当前程序段状态 [-] / current profile state [-]
    rSetpoint : REAL; // 当前温度设定值 [℃] / current temperature setpoint [C]
    iErrCode : INT; // 故障码 0=正常，601=组态非法，602=非法相位 [-] / error code, 601 config, 602 illegal phase [code]
    xInBand : BOOL; // 实测值落在设定带内 [-] / measured value inside the band [-]
END_VAR
VAR
    rtStart : R_TRIG; // 启动上升沿实例 [-] / start rising edge instance [-]
    rtReset : R_TRIG; // 复位上升沿实例 [-] / reset edge instance [-]
    tonHold : TON; // 保温计时器 [-] / holding timer [-]
    _eState : E_DL_ReactorHeatState := E_DL_ReactorHeatState.eIdle; // 内部相位（CASE 唯一写目标） [-] / internal phase [-]
    _iErr : INT; // 故障码内部锁存 [-] / latched error code [-]
    rSp : REAL; // 设定值内部量 [℃] / internal setpoint [C]
    fDtSec : REAL; // 扫描周期秒值 [s] / scan period in seconds [s]
    fStepK : REAL; // 本拍升/降温步长 [K] / step per scan [K]
    xCfgBad : BOOL; // 组态非法当拍标志 [-] / illegal configuration flag [-]
END_VAR

// 段 0｜边沿与定时器实例无条件周期刷新（R7）
rtStart(CLK := xStart); // 启动沿每拍必调 [-] / start edge every scan [-]
rtReset(CLK := xReset); // 复位沿每拍必调 [-] / reset edge every scan [-]
tonHold(IN := _eState = E_DL_ReactorHeatState.eHold, PT := tHoldLimit); // 保温相闸 [-] / holding phase gate [-]

// 段 1｜组态闸与扫描周期派生（斜率、带宽、周期必须正域）
fDtSec := LREAL_TO_REAL(TIME_TO_LREAL(tScan) / 1000.0); // ms ÷ 1000 = s / [ms] / 1000 = [s]
xCfgBad := NOT (fBandK > 1.0E-9) OR NOT (fRampKmin > 1.0E-9) OR NOT (fCoolKmin > 1.0E-9) OR NOT (fDtSec > 1.0E-9); // 带宽/斜率/周期正域闸（防除零） [-] / positive band, ramp and period gate [-]
xCfgBad := xCfgBad OR NOT (rTargetC > -1.0E30 AND rTargetC < 1.0E30) OR NOT (rPv > -1.0E30 AND rPv < 1.0E30); // 温度非有限闸 [-] / non finite temperature gate [-]
IF xCfgBad THEN
    _iErr := 601; // 组态非法码 [-] / illegal configuration code [-]
    _eState := E_DL_ReactorHeatState.eFault; // 锁存迁故障相 [-] / latch into the fault phase [-]
END_IF

// 段 2｜复位沿：清故障码与相位（R189）
IF rtReset.Q THEN
    _iErr := 0; // 清故障码 [-] / clear error code [-]
    _eState := E_DL_ReactorHeatState.eIdle; // 回空闲相 [-] / back to idle [-]
END_IF

// 段 3｜主状态机（合法事件优先于超时迁移，R275）
CASE _eState OF
    E_DL_ReactorHeatState.eIdle: // 空闲相：设定值初始化为实测值（无扰切换） [-] / idle [-]
        rSp := rPv; // ℃ 直取，避免起步跳变 / take the measurement to avoid a bump [C]
        IF rtStart.Q THEN
            _eState := E_DL_ReactorHeatState.eRamp; // 启动沿进升温段 [-] / start edge enters the ramp [-]
        END_IF
    E_DL_ReactorHeatState.eRamp: // 升温斜率段 [-] / heating ramp [-]
        fStepK := (fRampKmin * fDtSec) / 60.0; // K/min × s ÷ 60 = K / [K/min] × [s] / 60 = [K]
        IF (rSp + fStepK) >= rTargetC THEN
            rSp := rTargetC; // 到顶钳位，抑制超调 [-] / clamp at the target, suppress overshoot [-]
        ELSE
            rSp := rSp + fStepK; // K + K = K / [K] + [K] = [K]
        END_IF
        IF (rTargetC - rSp) < 1.0E-9 THEN
            _eState := E_DL_ReactorHeatState.eHold; // 设定值到顶转保温段 [-] / setpoint reached leads to hold [-]
        END_IF
    E_DL_ReactorHeatState.eHold: // 保温段：设定值锁定为目标 [-] / holding [-]
        rSp := rTargetC; // 锁定目标值 [℃] / lock the target [C]
        IF tonHold.Q THEN
            _eState := E_DL_ReactorHeatState.eCool; // 保温时长到转降温段 [-] / hold done leads to cooling [-]
        END_IF
    E_DL_ReactorHeatState.eCool: // 降温段 [-] / cooling [-]
        fStepK := (fCoolKmin * fDtSec) / 60.0; // K/min × s ÷ 60 = K / [K/min] × [s] / 60 = [K]
        IF (rSp - fStepK) <= rCoolTargetC THEN
            rSp := rCoolTargetC; // 到底钳位，抑制过冷 [-] / clamp at the floor, suppress undershoot [-]
        ELSE
            rSp := rSp - fStepK; // K − K = K / [K] minus [K] = [K]
        END_IF
        IF (rSp - rCoolTargetC) < 1.0E-9 THEN
            _eState := E_DL_ReactorHeatState.eDone; // 降到目标转完成相 [-] / cooled down leads to done [-]
        END_IF
    E_DL_ReactorHeatState.eDone: // 完成相 [-] / done [-]
        rSp := rCoolTargetC; // 保持终值 [℃] / hold the final value [C]
        IF NOT xStart THEN
            _eState := E_DL_ReactorHeatState.eIdle; // 命令撤销回空闲 [-] / command released returns to idle [-]
        END_IF
    E_DL_ReactorHeatState.eFault: // 故障相：码值锁存回放，仅复位沿出 [-] / fault, exit only on reset [-]
        ; // 锁存回放（R28） [-] / replay the latch only [-]
ELSE
    _iErr := 602; _eState := E_DL_ReactorHeatState.eFault; // 非法相位兜底 [-] / illegal phase fallback [-]
END_CASE

// 段 4｜出口映射（名实双出口，同源赋值）
eState := _eState; // 状态出口 [-] / state outlet [-]
rSetpoint := rSp; // 设定值出口 [℃] / setpoint outlet [C]
iErrCode := _iErr; // 故障码出口（锁存值） [-] / error code outlet [-]
xInBand := (ABS(rPv - rSp) <= fBandK) AND NOT xCfgBad; // K 差值与带宽直比，组态非法时强制 FALSE（连续量出口防护） [-] / band compare with a config fault override [-]
END_FUNCTION_BLOCK
