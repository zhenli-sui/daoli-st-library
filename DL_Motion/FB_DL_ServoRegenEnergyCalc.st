(* ===========================================================================
   组件名   : FB_DL_ServoRegenEnergyCalc
   分类     : DL_Motion / 伺服再生能耗估算
   一句话   : 由减速段动能差与回馈效率估算再生功率与累积能量，超限锁存报警
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : xEnable 功能使能；fInertia 折算惯量 [kg·m²]；fVelNowRad 当前角速度 [rad/s]
              fDtSec 采样周期 [s]；fEfficiency 回馈效率 0..1；fEnergyLimitWh 累积限值 [Wh]
              xReset 超限锁存复位沿
   输出契约 : fRegenPowerW 本拍再生功率 [W]；fEnergyAccumWh 累积再生能量 [Wh]
              fKineticJ 本拍动能 [J]；xRegenActive 处于再生（减速）段
              xOverLimit 累积超限锁存；xValid 输入有效
              iErrorCode 0=正常 1=非有限 2=参数非法 3=累积超限
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION_BLOCK FB_DL_ServoRegenEnergyCalc
VAR_INPUT
    xEnable : BOOL;                     // 功能使能 | function enable
    fInertia : REAL := 0.001;           // 折算惯量 [kg·m²] | reflected inertia [kg·m²]
    fVelNowRad : REAL;                  // 当前角速度 [rad/s] | current angular velocity [rad/s]
    fDtSec : REAL := 0.004;             // 采样周期 [s] | sample period [s]
    fEfficiency : REAL := 0.85;         // 回馈效率 0..1 | regen efficiency 0..1
    fEnergyLimitWh : REAL := 50.0;      // 累积能量限值 [Wh] | energy limit [Wh]
    xReset : BOOL;                      // 超限锁存复位沿 | over-limit reset edge
END_VAR
VAR_OUTPUT
    fRegenPowerW : REAL;                // 本拍再生功率 [W] | regen power this cycle [W]
    fEnergyAccumWh : REAL;              // 累积再生能量 [Wh] | accumulated regen energy [Wh]
    fKineticJ : REAL;                   // 本拍旋转动能 [J] | kinetic energy [J]
    xRegenActive : BOOL;                // 处于再生段 | regeneration active
    xOverLimit : BOOL;                  // 累积超限锁存 | latched over-limit
    xValid : BOOL;                      // 输入有效标志 | inputs valid flag
    iErrorCode : INT;                   // 故障码 0=无故障 | error code
END_VAR
VAR
    _fKePrev : REAL;                    // 上一拍动能 [J] | previous kinetic energy [J]
    _fKeNow : REAL;                     // 本拍动能 [J] | current kinetic energy [J]
    _fDeltaJ : REAL;                    // 动能差 [J] | kinetic energy difference [J]
    _fDt : REAL;                        // 钳位后采样周期 [s] | clamped dt [s]
    _fAccum : REAL;                     // 内部累积能量 [Wh] | internal accumulator [Wh]
    _xBad : BOOL;                       // 输入非有限标志 | not-finite flag
    _xBadPar : BOOL;                    // 参数非法标志 | invalid parameter flag
    _rtReset : R_TRIG;                  // 复位上升沿 | reset rising edge
END_VAR

// ---- 无条件每周期调用：复位沿检测 ----
_rtReset(CLK := xReset);

// ---- 非有限检测 ----
_xBad := (fInertia <> fInertia) OR ((fInertia - fInertia) <> (fInertia - fInertia))
      OR (fVelNowRad <> fVelNowRad) OR ((fVelNowRad - fVelNowRad) <> (fVelNowRad - fVelNowRad))
      OR (fDtSec <> fDtSec) OR ((fDtSec - fDtSec) <> (fDtSec - fDtSec))
      OR (fEfficiency <> fEfficiency) OR ((fEfficiency - fEfficiency) <> (fEfficiency - fEfficiency));

// ---- 参数合法性：惯量非负、效率落在 (0,1]、限值为正 ----
_xBadPar := (fInertia < 0.0) OR (fEfficiency <= 0.0) OR (fEfficiency > 1.0)
         OR (fEnergyLimitWh <= 0.0) OR (fDtSec <= 0.0);

// ---- 输出预置 ----
fRegenPowerW := 0.0;
fKineticJ := 0.0;
xRegenActive := FALSE;
xValid := NOT (_xBad OR _xBadPar);
iErrorCode := 0;
IF _xBad THEN
    iErrorCode := 1;
ELSIF _xBadPar THEN
    iErrorCode := 2;
END_IF

// ---- 周期钳位：防零除与超大积分步长 ----
_fDt := fDtSec;
IF _fDt < 0.000001 THEN
    _fDt := 0.000001;
ELSIF _fDt > 0.2 THEN
    _fDt := 0.2;
END_IF

IF xValid AND xEnable THEN
    // ---- 动能计算：Ek = 0.5 * J * w^2 ----
    _fKeNow := 0.5 * fInertia * fVelNowRad * fVelNowRad;
    fKineticJ := _fKeNow;

    // ---- 再生判定：仅当本拍动能低于上拍（减速）才有能量回馈 ----
    _fDeltaJ := _fKePrev - _fKeNow;
    IF _fDeltaJ > 0.0 THEN
        xRegenActive := TRUE;
        fRegenPowerW := _fDeltaJ / _fDt * fEfficiency;        // 分母已守卫
        _fAccum := _fAccum + _fDeltaJ * fEfficiency / 3600.0;  // J -> Wh
    END_IF

    // ---- 超限置位 ----
    IF _fAccum >= fEnergyLimitWh THEN
        xOverLimit := TRUE;
    END_IF

    // ---- 状态推进：动能快照留到拍末生效 ----
    _fKePrev := _fKeNow;
END_IF

// ---- 超限锁存与唯一解除路径 ----
// 解除门要求 NOT xEnable，必须放在使能门控块之外评估，否则该路径永不可达
IF _rtReset.Q AND NOT xEnable THEN
    xOverLimit := FALSE;
    _fAccum := 0.0;
END_IF
IF xOverLimit THEN
    iErrorCode := 3;                                      // 超限锁存状态优先
END_IF

fEnergyAccumWh := _fAccum;
END_FUNCTION_BLOCK
