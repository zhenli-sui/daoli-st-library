(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FB_DL_ScrubberReagentDoseSeq
  分类: DL_Process
  复杂度: C4 ｜ 版本: 1.0.0 ｜ 2026-11-24
  平台兼容: CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
  开源溯源: 无（clean-room 工程算法自研；参考公开的湿式洗涤塔 pH 反馈加碱与电导排污工艺，
            未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)

  功能职责:
    湿式洗涤塔碱液投加闭环。pH 反馈经简化 PI 调节计量泵，pH 稳定后进入保持态；
    循环液电导超限触发补排水（blowdown）；药剂罐低液位锁停计量泵并告警；
    泵运行中罐位下降率超限判泄漏疑似（安全侧）。

  输入/输出契约:
    IN  bEnable 上升沿启动（并做四项参数校验）；FALSE 撤销输出回 eIdle（R191 声明）。
    IN  bReset 上升沿是 eFault 唯一出口（还须残留故障条件消失）。
    OUT rPumpLh 计量泵冲程设定 [L/h]，仅在 eDose / eStabilize 输出，其余相为 0。
    OUT bMakeupValve / bDrainValve 仅在 eBlowdown 开，eFault 与 eTankLow 全关。

  码表 (Codes):
    31 = 药剂罐低液位（告警级；转 eTankLow，泵停，手动/上游补液）
    32 = 药液泄漏疑似（故障级；泵开时罐位下降率 > 5%/min）
    33 = 电导上限设定无效（故障级；rCondHi ≤ 0，比判据失效）
    34 = 计量泵上限无效（故障级；rPumpMaxLh ≤ 0，无饱和载体且增益不可算）
    35 = pH 测量值非法（故障级；越 0..14 或非有限）
    36 = 电导超限进入补排（信息级；blowdown 起点）
    37 = 补排次数达上限（故障级；反复补排说明补水/排污能力失效）
    38 = pH 设定值非法（故障级；rPhSp 越 0..14 或非有限）
    99 = 非法状态枚举值（ELSE 兜底）

  边界与红线:
    ① 五个定时器与两个 R_TRIG 全在 CASE 外无条件刷新（R7），CASE 内只读 .Q。
    ② tonStable / tonLow 的 IN 串本相或监测相闸并带 NOT .Q 自复位（R188）；tonLow 覆盖
       eDose/eStabilize/eBlowdown 三相，属**跨相累计看门狗**（低液位持续判定，与单相超时
       无关，红线 14 显式声明）；tonIntWin / tonDropWin 是自由运行周期窗（1 s 积分步 /
       60 s 下降率窗），不属任何相。
    ③ 积分 _rInteg 的显式清零条件：进 eIdle、进 eFault、进 eTankLow 三处即清（抗饱和载体
       同时把积分钳在 [0, rPumpMaxLh]）。
    ④ R528：bEnable 必须上升沿且泵上限/电导上限/pH 值/pH 设定四项有效才迁 eDose 或 eTankLow；
       全默认引脚时停留 eIdle，绝不直达投加相或补排相。
    ⑤ eFault 出口 = rtReset.Q AND NOT _bFaultCondNow（逐码反算残留条件，R28 可达性）。
    ⑥ 防抖硬性：电导补排出口用回差 DL_SCR_COND_HYST（禁零回差，否则在限值附近抖动会每拍
       进出补排相并迅速耗尽补排计数误报码 37）；泄漏判据 _bLeakNow 只在 60 s 窗边界采样一拍，
       禁把窗内旧差值当连续量逐拍复判（陈旧值复报会把一次骤降放大成永久故障）。
  修订历史: 2026-11-24  v1.0.0  R82-B 首版
*)

TYPE E_DL_SCRUB_STATE :
(
    eIdle      := 0,    // 空闲：等使能上升沿 / Idle: waiting for the enable rising edge
    eDose      := 1,    // 投加相：PI 调节计量泵 / Dose phase: PI control of the dosing pump
    eStabilize := 2,    // 稳定相：pH 在带内保持，等稳定确认 / Stabilize: pH inside the band, waiting for confirmation
    eBlowdown  := 3,    // 补排相：电导超限，开补水与排污阀 / Blowdown: conductivity high, makeup and drain valves open
    eTankLow   := 4,    // 低液位相：泵停告警，等罐位恢复 / Tank low: pump stopped with an alarm, waiting for recovery
    eFault     := 5     // 故障安全相：全部执行输出 FALSE / Fault safe phase: all actuator outputs FALSE
);
END_TYPE

FUNCTION_BLOCK FB_DL_ScrubberReagentDoseSeq
VAR_INPUT
    bEnable        : BOOL := FALSE;      // 使能（上升沿启动；FALSE 撤销输出回空闲）/ Enable, rising edge starts, FALSE withdraws the outputs
    bReset         : BOOL := FALSE;      // 复位（上升沿，eFault 唯一出口）/ Reset rising edge, the only fault exit
    rPh            : REAL := 0.0;        // 循环液 pH 实测 [-]/ Measured circulating liquid pH [-]
    rPhSp          : REAL := 0.0;        // pH 设定 [-]/ pH setpoint [-]
    rCondMsCm      : REAL := 0.0;        // 循环液电导率 [mS/cm] / Circulating liquid conductivity [mS/cm]
    rCondHi        : REAL := 0.0;        // 电导排污上限 [mS/cm] / Conductivity blowdown limit [mS/cm]
    rTankPct       : REAL := 0.0;        // 药剂罐余量 [%] / Reagent tank level [%]
    rTankLoPct     : REAL := 0.0;        // 药剂罐低液位阈值 [%] / Reagent tank low level threshold [%]
    rPumpMaxLh     : REAL := 0.0;        // 计量泵最大流量 [L/h] / Dosing pump maximum flow [L/h]
    tPhStable      : TIME := T#60S;      // pH 稳定确认时长，有效域 100ms..2h [s] / pH stability confirmation, valid domain 100ms..2h
    tTankLowDelay  : TIME := T#5S;       // 低液位确认时长，有效域 100ms..2h [s] / Low level confirmation, valid domain 100ms..2h
END_VAR
VAR_OUTPUT
    rPumpLh        : REAL := 0.0;        // 计量泵冲程设定 [L/h] / Dosing pump stroke setpoint [L/h]
    bPumpOn        : BOOL := FALSE;      // 计量泵运行位（单稳态，每拍重算）/ Pump run bit, monostable, recomputed every scan
    bMakeupValve   : BOOL := FALSE;      // 补水阀（仅补排相）/ Makeup valve, blowdown phase only
    bDrainValve    : BOOL := FALSE;      // 排污阀（仅补排相）/ Drain valve, blowdown phase only
    iErrCode       : INT := 0;           // 错误码（故障期锁存回放）/ Error code, latched replay during fault
    sMsg           : STRING;             // 文本提示（当前相位摘要）/ Text message, a summary of the current phase
END_VAR
VAR
    _eState        : E_DL_SCRUB_STATE := E_DL_SCRUB_STATE.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase, the only CASE write target
    _bFaultLatch   : BOOL := FALSE;      // 故障锁存位 / Fault latch
    _iErrLatch     : INT := 0;           // 锁存故障码（故障期唯一回放源）/ Latched fault code, the only replay source during fault
    _iInfoCode     : INT := 0;           // 信息级/告警级码 / Info or warning code
    _iErrTmp       : INT := 0;           // 当拍故障首因中间量 / First fault cause of this scan
    _bFaultReq     : BOOL := FALSE;      // 当拍故障请求（段 6 统一锁存）/ Fault request of this scan, latched at segment 6
    _bFaultCondNow : BOOL := FALSE;      // 残留故障条件（eFault 出口唯一附加判据）/ Residual fault condition, the only extra fault-exit criterion
    _bPhInvalid    : BOOL := FALSE;      // pH 测量值非法标志 / Measured pH invalid flag
    _bSpInvalid    : BOOL := FALSE;      // pH 设定值非法标志 / pH setpoint invalid flag
    _bStable       : BOOL := FALSE;      // 稳定确认记忆位（防 eDose↔eStabilize 每拍抖动）/ Stability memory, prevents scan-by-scan chatter
    _bLeakNow      : BOOL := FALSE;      // 泄漏疑似本拍成立（仅在 60 s 窗边界采样，防陈旧值复报）/ Leak suspicion valid in this scan, sampled only at the sixty second boundary
    _rPhCl         : REAL := 0.0;        // pH 净化副本 [-]/ Sanitised pH copy [-]
    _rSpCl         : REAL := 0.0;        // pH 设定净化副本 [-]/ Sanitised setpoint copy [-]
    _rCondCl       : REAL := 0.0;        // 电导率净化副本 [mS/cm] / Sanitised conductivity copy [mS/cm]
    _rCondExit     : REAL := 0.0;        // 补排出口门限（带回差，防抖）[mS/cm] / Blowdown exit threshold with hysteresis [mS/cm]
    _rTankCl       : REAL := 0.0;        // 罐位净化副本 [%] / Sanitised tank level copy [%]
    _rLoPct        : REAL := 0.0;        // 低液位阈值净化值 [%] / Sanitised low level threshold [%]
    _rErr          : REAL := 0.0;        // pH 误差 = 设定 - 实测 [pH] / pH error, setpoint minus measurement [pH]
    _rKp           : REAL := 0.0;        // 比例增益 [L/h per pH] / Proportional gain [L/h per pH]
    _rKi           : REAL := 0.0;        // 积分增益 [L/h per pH per s] / Integral gain [L/h per pH per s]
    _rIntMax       : REAL := 0.0;        // 积分上限（抗饱和载体）[L/h] / Integral upper limit, the anti-windup carrier [L/h]
    _rInteg        : REAL := 0.0;        // 积分项 [L/h] / Integral term [L/h]
    _rPumpCmd      : REAL := 0.0;        // 当拍泵设定 [L/h] / Pump command of this scan [L/h]
    _rPumpMax      : REAL := 0.0;        // 泵上限净化值 [L/h] / Sanitised pump maximum [L/h]
    _rDropPctMin   : REAL := 0.0;        // 罐位下降率（60 s 窗）[%/min] / Tank level drop rate over the sixty second window [%/min]
    _rTankPrevWin  : REAL := 0.0;        // 上一窗罐位快照 [%] / Tank level snapshot of the previous window [%]
    _iBlowdownCnt  : INT := 0;           // 补排次数，容量载体 DL_SCR_BD_MAX [次] / Blowdown counter, capacity carrier DL_SCR_BD_MAX [count]
    _tStable       : TIME := T#60S;      // pH 稳定确认钳定值 [s] / Clamped stability confirmation [s]
    _tLowDelay     : TIME := T#5S;       // 低液位确认钳定值 [s] / Clamped low level confirmation [s]
    rtReset        : R_TRIG;             // bReset 边沿（段 3 无条件刷新）/ bReset edge, refreshed unconditionally
    rtEnable       : R_TRIG;             // bEnable 边沿（段 3 无条件刷新，R528）/ bEnable edge, refreshed unconditionally
    tonStable      : TON;                // pH 稳定确认计时（本相单发，自复位）/ pH stability timer, single shot in its phase
    tonLow         : TON;                // 低液位累计看门狗（跨相持续判定，自复位）/ Low level cumulative watchdog across monitoring phases
    tonIntWin      : TON;                // 1 s 自由运行积分窗（自复位）/ One second free running integration window
    tonDropWin     : TON;                // 60 s 自由运行下降率窗（自复位）/ Sixty second free running drop rate window
END_VAR
VAR CONSTANT
    DL_SCR_EPS         : REAL := 1.0E-6;   // 数值闸阈值 [-]/ Numeric guard threshold [-]
    DL_SCR_FIN         : REAL := 1.0E15;   // 非有限判据阈值（ABS 比较用）[-] / Non-finite criterion threshold, compared by ABS [-]
    DL_SCR_PH_MIN      : REAL := 0.0;      // pH 有效域下限 [pH] / pH valid domain lower bound [pH]
    DL_SCR_PH_MAX      : REAL := 14.0;     // pH 有效域上限 [pH] / pH valid domain upper bound [pH]
    DL_SCR_PH_BAND     : REAL := 0.2;      // pH 稳定带宽 ±0.2 [pH] / pH stability band of plus or minus 0.2 [pH]
    DL_SCR_PH_SPAN     : REAL := 2.0;      // 比例增益折算满量程 pH 偏差 [pH] / pH deviation span used to scale the proportional gain [pH]
    DL_SCR_KI_RATIO    : REAL := 0.05;     // 积分增益 / 比例增益之比（每 1 s 步）[1/s] / Integral to proportional gain ratio per one second step [1/s]
    DL_SCR_INT_RATIO   : REAL := 1.0;      // 积分上限 / 泵上限之比 [-] / Integral limit to pump maximum ratio [-]
    DL_SCR_TANK_HYST   : REAL := 5.0;      // 低液位恢复回差 [%] / Low level recovery hysteresis [%]
    DL_SCR_DROP_LIM    : REAL := 5.0;      // 罐位下降率泄漏阈值 [%/min] / Tank drop rate leak threshold [%/min]
    DL_SCR_COND_HYST   : REAL := 0.5;      // 电导补排回差（防抖，禁零回差）[mS/cm] / Conductivity blowdown hysteresis, chatter prevention [mS/cm]
    DL_SCR_BD_MAX      : INT := 6;         // 单使能周期补排次数上限 [次] / Blowdown count limit per enable cycle [count]
    DL_SCR_ONE         : INT := 1;         // 计数步进一 [1] / Counter step of one [1]
    DL_SCR_ZERO        : INT := 0;         // 计数零基准 [-] / Counter zero base [-]
    DL_SCR_T_MIN       : TIME := T#100MS;  // 时间参数下限 [s] / Time parameter lower bound [s]
    DL_SCR_T_MAX       : TIME := T#2H;     // 时间参数上限 [s] / Time parameter upper bound [s]
    DL_SCR_T_STABLE_DEF: TIME := T#60S;    // 稳定确认默认回退值（在域内）[s] / Default stability duration inside the domain [s]
    DL_SCR_T_LOW_DEF   : TIME := T#5S;     // 低液位确认默认回退值（在域内）[s] / Default low level duration inside the domain [s]
    DL_SCR_INTWIN      : TIME := T#1S;     // 积分步长窗 [s] / Integration step window [s]
    DL_SCR_DROPWIN     : TIME := T#60S;    // 下降率测量窗 [s] / Drop rate measurement window [s]
END_VAR

(* —— 段 1：中间量预置（只清当拍扫描量，不清锁存/积分/补排计数，FB32-1） —— *)
_iErrTmp   := 0;                                    // 当拍故障首因复位 / Scan first fault cause reset
_bFaultReq := FALSE;                                // 当拍故障请求复位 / Scan fault request reset

(* —— 段 2：时间参数两级回退 + 入参域闸与非有限兜底 + 增益折算 —— *)
IF (tPhStable < DL_SCR_T_MIN) OR (tPhStable > DL_SCR_T_MAX) THEN
    _tStable := DL_SCR_T_STABLE_DEF;                // 越域：回一级默认常量 / Out of domain: fall back to the default constant
ELSE
    _tStable := tPhStable;                          // 域内：原值采用 / Inside the domain: use as given
END_IF
IF (tTankLowDelay < DL_SCR_T_MIN) OR (tTankLowDelay > DL_SCR_T_MAX) THEN
    _tLowDelay := DL_SCR_T_LOW_DEF;                 // 越域：回一级默认常量 / Out of domain: fall back to the default constant
ELSE
    _tLowDelay := tTankLowDelay;                    // 域内：原值采用 / Inside the domain: use as given
END_IF
_bPhInvalid := FALSE;                               // pH 非法标志预置 / Invalid pH flag preset
_rPhCl      := rPh;                                 // pH 副本 [-]/ pH copy [-]
IF (ABS(_rPhCl) > DL_SCR_FIN) OR (_rPhCl < DL_SCR_PH_MIN) OR (_rPhCl > DL_SCR_PH_MAX) THEN
    _bPhInvalid := TRUE;                            // 非有限或越 0..14：参与判据前必须先拦 / Non-finite or out of zero to fourteen: block it before it feeds any criterion
    _rPhCl      := DL_SCR_PH_MIN;                   // 兜底钳到域下限（值不参与结论）/ Clamp to the lower bound, the value never feeds a decision
END_IF
_bSpInvalid := FALSE;                               // 设定非法标志预置 / Invalid setpoint flag preset
_rSpCl      := rPhSp;                               // 设定副本 [-]/ Setpoint copy [-]
IF (ABS(_rSpCl) > DL_SCR_FIN) OR (_rSpCl < DL_SCR_PH_MIN) OR (_rSpCl > DL_SCR_PH_MAX) THEN
    _bSpInvalid := TRUE;                            // 非有限或越 0..14 / Non-finite or out of zero to fourteen
    _rSpCl      := DL_SCR_PH_MIN;                   // 兜底钳到域下限（值不参与结论）/ Clamp to the lower bound, the value never feeds a decision
END_IF
_rCondCl := rCondMsCm;                              // 电导率副本 [mS/cm] / Conductivity copy [mS/cm]
IF (ABS(_rCondCl) > DL_SCR_FIN) OR (_rCondCl < 0.0) THEN
    _rCondCl := 0.0;                                // 非有限或负值兜底为零 / Non-finite or negative falls back to zero
END_IF
_rCondExit := rCondHi - DL_SCR_COND_HYST;           // 量纲: (mS/cm)-(mS/cm) = mS/cm 补排出口门限 / Blowdown exit threshold in mS/cm
IF (ABS(rCondHi) > DL_SCR_FIN) OR (_rCondExit < 0.0) THEN
    _rCondExit := 0.0;                              // 非有限或负门限兜底为零（保证出口可达）/ Non-finite or negative falls back to zero so the exit stays reachable
END_IF
_rTankCl := rTankPct;                               // 罐位副本 [%] / Tank level copy [%]
IF (ABS(_rTankCl) > DL_SCR_FIN) OR (_rTankCl < 0.0) THEN
    _rTankCl := 0.0;                                // 非有限或负值兜底为零 / Non-finite or negative falls back to zero
ELSIF _rTankCl > 100.0 THEN
    _rTankCl := 100.0;                              // 罐位上限饱和 [%] / Saturate the tank level at one hundred percent
END_IF
_rLoPct := rTankLoPct;                              // 低液位阈值副本 [%] / Low level threshold copy [%]
IF (ABS(_rLoPct) > DL_SCR_FIN) OR (_rLoPct < 0.0) THEN
    _rLoPct := 0.0;                                 // 非有限或负值兜底为零 / Non-finite or negative falls back to zero
ELSIF _rLoPct > 95.0 THEN
    _rLoPct := 95.0;                                // 阈值上限饱和，保证恢复回差可达 [%] / Saturate so the recovery hysteresis stays reachable [%]
END_IF
_rPumpMax := rPumpMaxLh;                            // 泵上限副本 [L/h] / Pump maximum copy [L/h]
IF (ABS(_rPumpMax) > DL_SCR_FIN) OR (_rPumpMax < 0.0) THEN
    _rPumpMax := 0.0;                               // 非有限或负值兜底为零 / Non-finite or negative falls back to zero
END_IF
_rErr := _rSpCl - _rPhCl;                           // 误差取「设定减实测」：pH 低于设定为正 → 泵加量（碱液）/ Error is setpoint minus measurement, a low pH gives a positive dose
IF _rPumpMax > DL_SCR_EPS THEN
    _rKp     := _rPumpMax / DL_SCR_PH_SPAN;         // 量纲: (L/h)/(pH) = L/h per pH / (L/h) divided by (pH) gives L/h per pH
    _rKi     := _rKp * DL_SCR_KI_RATIO;             // 量纲: (L/h per pH)*(1/s) = L/h per pH per s / (L/h per pH) times (1/s)
    _rIntMax := _rPumpMax * DL_SCR_INT_RATIO;       // 量纲: (L/h)*(无量纲) = L/h（积分上限载体）/ (L/h) times dimensionless gives the integral carrier
ELSE
    _rKp     := 0.0;                                // 分母闸：泵上限无效时增益置零 / Denominator guard: gains are zero when the pump limit is invalid
    _rKi     := 0.0;                                // 分母闸：积分增益置零 / Denominator guard: the integral gain is zero
    _rIntMax := 0.0;                                // 分母闸：积分上限置零 / Denominator guard: the integral limit is zero
END_IF
_bFaultCondNow := FALSE;                            // 残留条件预置（eFault 出口唯一附加判据）/ Residual preset, the only extra fault-exit criterion
IF _iErrLatch = 33 THEN
    _bFaultCondNow := (ABS(rCondHi) <= DL_SCR_EPS);         // 码 33：电导上限仍无效 / Code 33: the conductivity limit is still invalid
ELSIF _iErrLatch = 34 THEN
    _bFaultCondNow := (rPumpMaxLh <= DL_SCR_EPS);           // 码 34：泵上限仍无效 / Code 34: the pump limit is still invalid
ELSIF _iErrLatch = 35 THEN
    _bFaultCondNow := _bPhInvalid;                          // 码 35：pH 测量仍非法 / Code 35: the measured pH is still invalid
ELSIF _iErrLatch = 38 THEN
    _bFaultCondNow := _bSpInvalid;                          // 码 38：pH 设定仍非法 / Code 38: the pH setpoint is still invalid
END_IF
(* 码 32（泄漏疑似）以「泵运行中的下降率」为必要条件，故障相泵已停、条件自然不再成立；
   码 37（补排次数达上限）由计数驱动。二者与码 99 均无输入残留条件，复位沿单独即可退出。 / Codes 32, 37 and 99 have no residual input condition *)

(* —— 段 3：边沿与定时器（全部在 CASE 外无条件刷新，R7；IN 带 NOT .Q 自复位，R188） —— *)
rtReset(CLK := bReset);                             // 复位边沿无条件刷新 / Reset edge refreshed unconditionally
rtEnable(CLK := bEnable);                           // 使能边沿无条件刷新（R528 起点判据）/ Enable edge refreshed unconditionally
tonStable(IN := (_eState = E_DL_SCRUB_STATE.eStabilize) AND (NOT tonStable.Q) AND (NOT _bFaultLatch),
          PT := _tStable);                          // 本相单发计时：仅稳定相 / Single-shot timer in the stabilize phase only
tonLow(IN := ((_eState = E_DL_SCRUB_STATE.eDose) OR (_eState = E_DL_SCRUB_STATE.eStabilize)
              OR (_eState = E_DL_SCRUB_STATE.eBlowdown))
             AND (_rTankCl <= _rLoPct) AND (NOT tonLow.Q) AND (NOT _bFaultLatch),
       PT := _tLowDelay);                           // 跨相累计看门狗：低液位在三监测相内持续累计，非本相超时 / Cumulative watchdog across the three monitoring phases, not a phase timeout
tonIntWin(IN := NOT tonIntWin.Q, PT := DL_SCR_INTWIN);      // 自由运行 1 s 积分步长窗 / Free running one second integration step window
tonDropWin(IN := NOT tonDropWin.Q, PT := DL_SCR_DROPWIN);   // 自由运行 60 s 下降率测量窗 / Free running sixty second drop rate window
IF tonIntWin.Q THEN
    IF (_eState = E_DL_SCRUB_STATE.eDose) AND (NOT _bFaultLatch) THEN
        // 量纲: (pH)*(L/h per pH per s)*(1 s) = L/h 积分增量（窗长即 1 s，故不再乘 dt）
        _rInteg := _rInteg + (_rErr * _rKi);        // 积分项一步累加 [L/h] / One integration step [L/h]
        IF _rInteg > _rIntMax THEN
            _rInteg := _rIntMax;                    // 抗饱和上限 / Anti-windup upper clamp
        END_IF
        IF _rInteg < 0.0 THEN
            _rInteg := 0.0;                         // 抗饱和下限 / Anti-windup lower clamp
        END_IF
    END_IF
END_IF
IF tonDropWin.Q THEN
    // 量纲: (% 窗内差) / (60 s 窗) * 60 s = %/min；窗长已是 60 s，故差值即 %/min
    _rDropPctMin  := _rTankPrevWin - _rTankCl;      // 窗内罐位下降百分点 [%/min] / Tank drop in percentage points over the window [%/min]
    _rTankPrevWin := _rTankCl;                      // 刷新下一窗快照 [%] / Refresh the snapshot for the next window [%]
END_IF

(* —— 段 4：当拍泵设定（PI 简化：pump = kp*err + integ，限幅 [0, rPumpMaxLh]） —— *)
IF _rPumpMax > DL_SCR_EPS THEN
    // 量纲: (L/h per pH)*(pH) + (L/h) = L/h
    _rPumpCmd := (_rKp * _rErr) + _rInteg;          // PI 输出 [L/h] / PI output [L/h]
    IF _rPumpCmd > _rPumpMax THEN
        _rPumpCmd := _rPumpMax;                     // 上限饱和（载体 rPumpMaxLh）/ Saturate at the pump maximum
    END_IF
    IF _rPumpCmd < 0.0 THEN
        _rPumpCmd := 0.0;                           // 下限饱和，禁负投加 / Saturate at zero, no negative dosing
    END_IF
ELSE
    _rPumpCmd := 0.0;                               // 分母闸：泵上限无效则出零 / Denominator guard: emit zero when the pump limit is invalid
END_IF
_bLeakNow := FALSE;                                 // 泄漏判据预置 / Leak criterion preset
IF tonDropWin.Q AND (_rDropPctMin > DL_SCR_DROP_LIM) AND (_rPumpCmd > DL_SCR_EPS)
   AND ((_eState = E_DL_SCRUB_STATE.eDose) OR (_eState = E_DL_SCRUB_STATE.eStabilize)) THEN
    _bLeakNow := TRUE;                              // 窗边界单拍采样：泵在开且窗内罐位骤降，泄漏疑似 / Sampled once per window boundary
END_IF

(* —— 段 5：状态机主体（唯一相位写入点；故障只置请求，锁存与迁相由段 6 执行） —— *)
CASE _eState OF
    E_DL_SCRUB_STATE.eIdle :
        (* 迁移①：拍 N 进入（使能上升沿）/ 本拍行为：四项参数校验，缺任一即故障 / 拍 N+1 转出至投加相或低液位相 *)
        IF rtEnable.Q AND (NOT _bFaultLatch) THEN
            IF rPumpMaxLh <= DL_SCR_EPS THEN
                _iErrTmp   := 34;                            // 故障级：泵上限无效 / Fault: invalid pump maximum
                _bFaultReq := TRUE;                          // 请求段 6 锁存 / Request the latch at segment 6
            ELSIF ABS(rCondHi) <= DL_SCR_EPS THEN
                _iErrTmp   := 33;                            // 故障级：电导上限无效 / Fault: invalid conductivity limit
                _bFaultReq := TRUE;                          // 请求段 6 锁存 / Request the latch at segment 6
            ELSIF _bPhInvalid THEN
                _iErrTmp   := 35;                            // 故障级：pH 测量非法 / Fault: invalid pH measurement
                _bFaultReq := TRUE;                          // 请求段 6 锁存 / Request the latch at segment 6
            ELSIF _bSpInvalid THEN
                _iErrTmp   := 38;                            // 故障级：pH 设定非法 / Fault: invalid pH setpoint
                _bFaultReq := TRUE;                          // 请求段 6 锁存 / Request the latch at segment 6
            ELSIF _rTankCl <= _rLoPct THEN
                _rInteg        := 0.0;                       // 进低液位相即清积分 / Integral cleared on entry to the low level phase
                _iBlowdownCnt  := DL_SCR_ZERO;               // 新周期补排计数归零 / New cycle: blowdown counter cleared
                _iInfoCode     := 31;                        // 告警级：起始即低液位 / Warning: low level at start
                _eState        := E_DL_SCRUB_STATE.eTankLow;  // 迁移①：进低液位相 / Move to the tank low phase
            ELSE
                _rInteg        := 0.0;                       // 新周期：清积分 / New cycle: integral cleared
                _iBlowdownCnt  := DL_SCR_ZERO;               // 新周期：补排计数归零 / New cycle: blowdown counter cleared
                _bStable       := FALSE;                     // 新周期：稳定记忆清零 / New cycle: stability memory cleared
                _iInfoCode     := 0;                         // 新周期：信息码归零 / New cycle: info code cleared
                _eState        := E_DL_SCRUB_STATE.eDose;    // 迁移①：进投加相 / Move to the dose phase
            END_IF
        END_IF

    E_DL_SCRUB_STATE.eDose :
        (* 迁移②③④：拍 N 进入 / 本拍行为：PI 输出泵设定；逐拍查低液位、电导超限 / 拍 N+1 转出 *)
        IF tonLow.Q THEN                                         // 低液位经 tTankLowDelay 确认（累计看门狗）才锁停 / Locked out only after the delay confirms
            _rInteg    := 0.0;                               // 进低液位相即清积分 / Integral cleared on entry
            _iInfoCode := 31;                                // 告警级：低液位 / Warning: low level
            _eState    := E_DL_SCRUB_STATE.eTankLow;         // 迁移②：锁停计量泵 / Stop the dosing pump
        ELSIF _rCondCl > rCondHi THEN
            _iInfoCode := 36;                                // 信息级：电导超限进补排 / Info: conductivity high, entering blowdown
            IF _iBlowdownCnt < DL_SCR_BD_MAX THEN
                _iBlowdownCnt := _iBlowdownCnt + DL_SCR_ONE; // 补排次数净额 +1，达容量上限饱和 / Net blowdown increment, saturated at capacity
            END_IF
            IF _iBlowdownCnt >= DL_SCR_BD_MAX THEN
                _iErrTmp   := 37;                            // 故障级：反复补排说明补水/排污失效 / Fault: repeated blowdown means makeup or drain has failed
                _bFaultReq := TRUE;                          // 请求段 6 锁存 / Request the latch at segment 6
            ELSE
                _eState := E_DL_SCRUB_STATE.eBlowdown;       // 迁移③：进补排相 / Move to blowdown
            END_IF
        ELSIF (ABS(_rErr) <= DL_SCR_PH_BAND) AND (NOT _bStable) THEN
            _eState := E_DL_SCRUB_STATE.eStabilize;          // 迁移④：进带内，转稳定确认相 / In band, move to the stabilize phase
        ELSE
            IF ABS(_rErr) > DL_SCR_PH_BAND THEN
                _bStable := FALSE;                           // 出带即撤销稳定确认 / Leaving the band revokes the stability memory
            END_IF
        END_IF

    E_DL_SCRUB_STATE.eStabilize :
        (* 迁移⑤⑥⑦：拍 N 进入 / 本拍行为：pH 保持在带内才计稳定；出带回投加相 / 拍 N+1 转出 *)
        IF tonLow.Q THEN                                         // 低液位经 tTankLowDelay 确认（累计看门狗）才锁停 / Locked out only after the delay confirms
            _rInteg    := 0.0;                               // 进低液位相即清积分 / Integral cleared on entry
            _iInfoCode := 31;                                // 告警级：低液位 / Warning: low level
            _eState    := E_DL_SCRUB_STATE.eTankLow;         // 迁移⑤：锁停计量泵 / Stop the dosing pump
        ELSIF _rCondCl > rCondHi THEN
            _iInfoCode := 36;                                // 信息级：电导超限进补排 / Info: conductivity high, entering blowdown
            IF _iBlowdownCnt < DL_SCR_BD_MAX THEN
                _iBlowdownCnt := _iBlowdownCnt + DL_SCR_ONE; // 补排次数净额 +1 / Net blowdown increment
            END_IF
            IF _iBlowdownCnt >= DL_SCR_BD_MAX THEN
                _iErrTmp   := 37;                            // 故障级：补排次数达上限 / Fault: blowdown count at its limit
                _bFaultReq := TRUE;                          // 请求段 6 锁存 / Request the latch at segment 6
            ELSE
                _eState := E_DL_SCRUB_STATE.eBlowdown;       // 迁移⑥：进补排相 / Move to blowdown
            END_IF
        ELSIF ABS(_rErr) > DL_SCR_PH_BAND THEN
            _bStable := FALSE;                               // 出带：撤销稳定确认 / Left the band: revoke the stability memory
            _eState  := E_DL_SCRUB_STATE.eDose;              // 迁移⑦：回投加相继续调节 / Back to dose and keep regulating
        ELSIF tonStable.Q THEN
            _bStable   := TRUE;                              // 稳定确认成立（保持态）/ Stability confirmed, hold state
            _iInfoCode := 0;                                 // 稳定达成：清信息码 / Stable: info code cleared
            _eState    := E_DL_SCRUB_STATE.eDose;            // 迁移⑦：回投加相保持 / Back to dose in the hold state
        END_IF

    E_DL_SCRUB_STATE.eBlowdown :
        (* 迁移⑧⑨：拍 N 进入 / 本拍行为：开补水与排污，泵停 / 拍 N+1 转出至投加相或低液位相 *)
        IF tonLow.Q THEN                                         // 低液位经 tTankLowDelay 确认（累计看门狗）才锁停 / Locked out only after the delay confirms
            _rInteg    := 0.0;                               // 进低液位相即清积分 / Integral cleared on entry
            _iInfoCode := 31;                                // 告警级：低液位 / Warning: low level
            _eState    := E_DL_SCRUB_STATE.eTankLow;         // 迁移⑧：补排中低液位，锁停 / Low level during blowdown, stop
        ELSIF _rCondCl < _rCondExit THEN
            _bStable := FALSE;                               // 补排结束：撤销稳定确认 / Blowdown done: revoke the stability memory
            _eState  := E_DL_SCRUB_STATE.eDose;              // 迁移⑨：电导回落到回差下，回投加相 / Conductivity fell below the hysteresis band, back to dose
        END_IF

    E_DL_SCRUB_STATE.eTankLow :
        (* 迁移⑩：拍 N 进入 / 本拍行为：泵停告警，等罐位回到 lo + 5% / 拍 N+1 转出至投加相 *)
        IF _rTankCl > (_rLoPct + DL_SCR_TANK_HYST) THEN
            _bStable   := FALSE;                             // 恢复补液：稳定需重新确认 / After refilling the stability must be re-confirmed
            _iInfoCode := 0;                                 // 恢复：清信息码 / Recovered: info code cleared
            _eState    := E_DL_SCRUB_STATE.eDose;            // 迁移⑩：回投加相 / Back to the dose phase
        END_IF

    E_DL_SCRUB_STATE.eFault :
        (* 迁移⑪：拍 N 进入 / 本拍行为：只等出口条件（复位沿 + 残留条件消失）/ 拍 N+1 转出至 eIdle *)
        IF rtReset.Q AND (NOT _bFaultCondNow) THEN
            _bFaultLatch  := FALSE;                          // 清故障锁存 / Clear the fault latch
            _iErrLatch    := 0;                              // 清锁存故障码 / Clear the latched code
            _iInfoCode    := 0;                              // 清信息码 / Clear the info code
            _rInteg       := 0.0;                            // 进 eIdle 前的积分清零 / Integral cleared before returning to idle
            _bStable      := FALSE;                          // 稳定记忆清零 / Stability memory cleared
            _iBlowdownCnt := DL_SCR_ZERO;                    // 补排计数清零 / Blowdown counter cleared
            _eState       := E_DL_SCRUB_STATE.eIdle;         // 回空闲相，不滞留 / Back to idle, never parked
        END_IF
ELSE
    (* 迁移⑫：非法枚举兜底（R6），码位赋值与锁存 3 行内配对（R45） *)
    IF NOT _bFaultLatch THEN
        _iErrLatch   := 99;                                  // 故障级：非法状态枚举值 / Fault: illegal state enum value
        _bFaultLatch := TRUE;                                // 置故障锁存 / Latch the fault
    END_IF
END_CASE

(* —— 段 6：泄漏疑似判定 + 故障锁存 + 段尾迁相 + 撤使能降级（R191 已声明） —— *)
IF _bLeakNow AND (NOT _bFaultLatch) THEN
    _iErrTmp   := 32;                                    // 故障级：泵运行中罐位骤降，泄漏疑似 / Fault: the tank level drops while pumping, a leak is suspected
    _bFaultReq := TRUE;                                  // 请求本次锁存 / Request the latch in this scan
END_IF
IF _bFaultReq AND (NOT _bFaultLatch) THEN
    _iErrLatch   := _iErrTmp;                            // 锁存当拍首因 / Latch the first cause of this scan
    _bFaultLatch := TRUE;                                // 置故障锁存 / Latch the fault
END_IF
IF _bFaultLatch AND (_eState <> E_DL_SCRUB_STATE.eFault) THEN
    _eState := E_DL_SCRUB_STATE.eFault;                  // 锁存即迁相（段尾统一执行）/ The latch forces the fault phase at the tail
END_IF
IF (NOT bEnable) AND (NOT _bFaultLatch) AND (_eState <> E_DL_SCRUB_STATE.eIdle) THEN
    _rInteg := 0.0;                                      // 撤使能：清积分（进 eIdle 条件之一）/ Disable: integral cleared
    _bStable := FALSE;                                   // 撤使能：清稳定记忆 / Disable: stability memory cleared
    _eState := E_DL_SCRUB_STATE.eIdle;                   // 撤使能：回空闲相 / Disable: back to idle
END_IF

(* —— 段 7：统一出口（单稳态每拍重算，不锁存；eFault 内全部 FALSE） —— *)
IF ((_eState = E_DL_SCRUB_STATE.eDose) OR (_eState = E_DL_SCRUB_STATE.eStabilize)) AND (NOT _bFaultLatch) THEN
    rPumpLh  := _rPumpCmd;                               // 投加相与稳定相输出泵设定 [L/h] / Dose and stabilize phases emit the pump setpoint [L/h]
    bPumpOn  := (_rPumpCmd > DL_SCR_EPS);                // 设定为正直才置运行位 / The run bit is set only for a positive setpoint
ELSE
    rPumpLh  := 0.0;                                     // 其余相（含补排、低液位、故障）：泵设定归零 / Other phases, including blowdown, low level and fault, emit zero
    bPumpOn  := FALSE;                                   // 其余相：运行位撤销 / Other phases: the run bit is withdrawn
END_IF
bMakeupValve := (_eState = E_DL_SCRUB_STATE.eBlowdown) AND (NOT _bFaultLatch);   // 补水阀仅补排相 / Makeup valve only during blowdown
bDrainValve  := (_eState = E_DL_SCRUB_STATE.eBlowdown) AND (NOT _bFaultLatch);   // 排污阀仅补排相 / Drain valve only during blowdown
IF _bFaultLatch THEN
    iErrCode := _iErrLatch;                              // 故障期回放锁存码 / Replay the latched code during fault
ELSE
    iErrCode := _iInfoCode;                              // 非故障期输出信息/告警码 / Info or warning code outside fault
END_IF
IF _eState = E_DL_SCRUB_STATE.eIdle THEN
    sMsg := 'IDLE';                                      // 空闲 / Idle
ELSIF _eState = E_DL_SCRUB_STATE.eDose THEN
    sMsg := 'DOSE';                                      // 投加 / Dosing
ELSIF _eState = E_DL_SCRUB_STATE.eStabilize THEN
    sMsg := 'STABLE';                                    // 稳定确认 / Stabilizing
ELSIF _eState = E_DL_SCRUB_STATE.eBlowdown THEN
    sMsg := 'BLOWDOWN';                                  // 补排 / Blowdown
ELSIF _eState = E_DL_SCRUB_STATE.eTankLow THEN
    sMsg := 'TANKLOW';                                   // 药罐低液位 / Reagent tank low
ELSE
    sMsg := 'FAULT';                                     // 故障 / Fault
END_IF
END_FUNCTION_BLOCK
