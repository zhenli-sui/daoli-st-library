(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FB_DL_CoagDoseJarTestSeq
  分类: DL_Process
  复杂度: C4 ｜ 版本: 1.0.0 ｜ 2026-11-24
  平台兼容: CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
  开源溯源: 无（clean-room 工程公式自研；参考公开的混凝烧杯试验与投加量换算工艺公式，
            未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)

  功能职责:
    水厂混凝加药闭环。前馈按进水浊度三段给投加基准，烧杯试验结果到达后修正基准，
    沉后浊度复核超限则再整定（单次限幅 ±20%，最多 3 轮）。
    相序: eIdle →（bEnable 上升沿）eFeedForward → eJarTestWait → eTrim → eVerify
          →（达标 / 轮次耗尽）eHold；eJarTestWait 超时 → eFault（码 11）。

  输入/输出契约:
    IN  bEnable 上升沿启动；FALSE 撤销执行位 bDoseOn 并回 eIdle（设定值保留，见 R191 声明）。
    IN  bReset  上升沿是 eFault 的唯一出口（还须残留故障条件消失）。
    OUT rDoseLh 投加量设定 [L/h]，故障相与保持相输出「最后有效投加」而不掉零。
    OUT bDoseOn 投加执行位，故障相与 eHold 之外的活动相为 TRUE。

  码表 (Codes):
    11 = 烧杯结果等待超时（故障级；执行位 FALSE，但投加设定保持最后有效值不掉零）
    12 = 复核整定轮次耗尽（告警级；转 eHold 保持最后有效投加，不置故障相）
    13 = 烧杯结果非法（信息级；本拍跳过修正，基准不变）
    14 = 进水流量无效（故障级，rFlowM3h ≤ 0，投加量无法换算）
    15 = 母液浓度无效（故障级，rStockGL ≤ 0，除零闸拦截）
    16 = 沉后浊度设定无效（故障级，rOutNtuSp ≤ 0，复核倍率不可信）
    17 = 投加上限无效（故障级，rDoseMaxLh ≤ 0，无饱和载体）
    99 = 非法状态枚举值（ELSE 兜底）

  边界与红线:
    ① 两个 TON（tonJar / tonSettle）与三个 R_TRIG 全部在 CASE 外无条件刷新（R7），CASE 内只读 .Q。
    ② 两个 TON 的 IN 各自串本相闸（eJarTestWait / eVerify）并带 NOT .Q 自复位（R188），
       属「本相单发计时」而非跨相累计看门狗（红线 14 声明）。
    ③ R528：eIdle 只在 bEnable 上升沿且母液浓度/流量/投加上限三项均有效时才迁 eFeedForward；
       全默认引脚（全 0）时停留 eIdle，绝不直达前馈或投加相。
    ④ eFault 出口 = rtReset.Q AND NOT _bFaultCondNow（残留条件按锁存码逐条反算，R28 可达性）。
    ⑤ 单一状态机内联实现：无方法级封装、无属性段、无倒序循环、无数组透传
  修订历史: 2026-11-24  v1.0.0  R82-B 首版
*)

TYPE E_DL_COAG_STATE :
(
    eIdle        := 0,    // 空闲：等使能上升沿 / Idle: waiting for the enable rising edge
    eFeedForward := 1,    // 前馈相：按进水浊度三段给基准 / Feed-forward: base dose from three inlet turbidity bands
    eJarTestWait := 2,    // 烧杯等待相：等结果沿，超时转故障 / Jar test wait: waiting for the result edge, timeout goes to fault
    eTrim        := 3,    // 修正相：按烧杯结果单次限幅修正基准 / Trim: bounded correction of the base by the jar test result
    eVerify      := 4,    // 复核相：沉后浊度与设定比较 / Verify: compare the settled turbidity with the setpoint
    eHold        := 5,    // 保持相：保持最后有效投加等复位 / Hold: keep the last valid dose until reset
    eFault       := 6     // 故障安全相：执行位撤销，设定保持 / Fault safe phase: run bit withdrawn, setpoint kept
);
END_TYPE

FUNCTION_BLOCK FB_DL_CoagDoseJarTestSeq
VAR_INPUT
    bEnable         : BOOL := FALSE;      // 使能（上升沿启动；FALSE 撤销执行位回空闲）/ Enable, rising edge starts, FALSE withdraws the run bit
    bReset          : BOOL := FALSE;      // 复位（上升沿，eFault 唯一出口）/ Reset rising edge, the only fault exit
    bJarResultReady : BOOL := FALSE;      // 烧杯结果到达（上升沿有效）/ Jar test result ready, rising edge only
    rJarResultMgL   : REAL := 0.0;        // 烧杯试验最优投加浓度 [mg/L] / Jar test optimum dose concentration [mg/L]
    rInNtu          : REAL := 0.0;        // 进水浊度 [NTU] / Inlet turbidity [NTU]
    rOutNtu         : REAL := 0.0;        // 沉后浊度实测 [NTU] / Settled outlet turbidity [NTU]
    rOutNtuSp       : REAL := 0.0;        // 沉后浊度设定 [NTU] / Settled turbidity setpoint [NTU]
    rFlowM3h        : REAL := 0.0;        // 进水流量 [m3/h] / Inlet flow [m3/h]
    rStockGL        : REAL := 0.0;        // 母液浓度 [g/L]（1 g/L = 1 kg/m3）/ Stock concentration [g/L]
    rDoseMaxLh      : REAL := 0.0;        // 投加泵上限 [L/h] / Dosing pump upper limit [L/h]
    tSettleTime     : TIME := T#15M;      // 沉后稳定等待，有效域 100ms..2h [s] / Settling wait, valid domain 100ms..2h
    tVerifyTimeout  : TIME := T#30M;      // 烧杯结果等待超时，有效域 100ms..2h [s] / Jar result timeout, valid domain 100ms..2h
END_VAR
VAR_OUTPUT
    rDoseLh         : REAL := 0.0;        // 投加量设定 [L/h] / Dose setpoint [L/h]
    bDoseOn         : BOOL := FALSE;      // 投加执行位（故障相强制 FALSE）/ Dose run bit, forced FALSE in the fault phase
    iErrCode        : INT := 0;           // 错误码（故障期锁存回放，非故障期为信息码）/ Error code, latched replay during fault
    sMsg            : STRING;             // 文本提示（当前相位摘要）/ Text message, a summary of the current phase
END_VAR
VAR
    _eState         : E_DL_COAG_STATE := E_DL_COAG_STATE.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase, the only CASE write target
    _bFaultLatch    : BOOL := FALSE;      // 故障锁存位（仅复位出口清除）/ Fault latch, cleared only at the reset exit
    _iErrLatch      : INT := 0;           // 锁存故障码（故障期唯一回放源）/ Latched fault code, the only replay source during fault
    _iInfoCode      : INT := 0;           // 信息级/告警级码（永不进故障锁存）/ Info or warning code, never latched as a fault
    _iErrTmp        : INT := 0;           // 当拍故障首因中间量 / First fault cause of this scan
    _bFaultReq      : BOOL := FALSE;      // 当拍故障请求（段 7 统一锁存）/ Fault request of this scan, latched at segment 7
    _bFaultCondNow  : BOOL := FALSE;      // 残留故障条件（eFault 出口唯一附加判据）/ Residual fault condition, the only extra fault-exit criterion
    _rBaseMgL       : REAL := 0.0;        // 当前投加基准浓度 [mg/L] / Current base dose concentration [mg/L]
    _rDoseCmd       : REAL := 0.0;        // 当拍换算投加量 [L/h] / Dose computed this scan [L/h]
    _rDoseLastGood  : REAL := 0.0;        // 最后有效投加量 [L/h]（不掉零载体）/ Last valid dose [L/h], the never-zero carrier
    _rInNtuCl       : REAL := 0.0;        // 进水浊度净化副本 [NTU] / Sanitised inlet turbidity copy [NTU]
    _rOutNtuCl      : REAL := 0.0;        // 沉后浊度净化副本 [NTU] / Sanitised settled turbidity copy [NTU]
    _rDelta         : REAL := 0.0;        // 基准修正相对偏差（无量纲）/ Relative correction of the base, dimensionless
    _rRatio         : REAL := 0.0;        // 浊度复核倍率（无量纲）/ Turbidity verification ratio, dimensionless
    _iTrimCnt       : INT := 0;           // 整定轮次计数，容量载体 DL_CDJ_CYCLE_MAX [次] / Trim round counter, capacity carrier DL_CDJ_CYCLE_MAX [count]
    _tSettle        : TIME := T#15M;      // 沉后稳定等待钳定值 [s] / Clamped settling wait [s]
    _tVerify        : TIME := T#30M;      // 烧杯超时钳定值 [s] / Clamped jar timeout [s]
    rtReset         : R_TRIG;             // bReset 边沿（段 3 无条件刷新）/ bReset edge, refreshed unconditionally at segment 3
    rtEnable        : R_TRIG;             // bEnable 边沿（段 3 无条件刷新）/ bEnable edge, refreshed unconditionally at segment 3
    rtJar           : R_TRIG;             // 烧杯结果边沿（段 3 无条件刷新）/ Jar result edge, refreshed unconditionally at segment 3
    tonJar          : TON;                // 烧杯等待计时（本相单发，自复位）/ Jar wait timer, single shot in its phase with self reset
    tonSettle       : TON;                // 沉后稳定计时（本相单发，自复位）/ Settling timer, single shot in its phase with self reset
END_VAR
VAR CONSTANT
    DL_CDJ_EPS         : REAL := 1.0E-6;      // 除零闸阈值 [-] / Divide-by-zero guard threshold [-]
    DL_CDJ_FIN         : REAL := 1.0E15;      // 非有限判据阈值（ABS 比较用）[-] / Non-finite criterion threshold, compared by ABS [-]
    DL_CDJ_NTU_SPLIT1  : REAL := 20.0;        // 进水浊度第一分段阈值 [NTU] / First inlet turbidity band threshold [NTU]
    DL_CDJ_NTU_SPLIT2  : REAL := 50.0;        // 进水浊度第二分段阈值 [NTU] / Second inlet turbidity band threshold [NTU]
    DL_CDJ_MGL_LOW     : REAL := 8.0;         // 低浊段基准投加浓度 [mg/L] / Base dose concentration of the low band [mg/L]
    DL_CDJ_MGL_MID     : REAL := 15.0;        // 中浊段基准投加浓度 [mg/L] / Base dose concentration of the mid band [mg/L]
    DL_CDJ_MGL_HIGH    : REAL := 25.0;        // 高浊段基准投加浓度 [mg/L] / Base dose concentration of the high band [mg/L]
    DL_CDJ_TRIM_LIM    : REAL := 0.2;         // 单次修正限幅 ±20%（无量纲）/ Per-round correction limit of plus or minus twenty percent, dimensionless
    DL_CDJ_NTU_RATIO   : REAL := 1.15;        // 复核超限倍率（无量纲）/ Verification exceed factor, dimensionless
    DL_CDJ_CYCLE_MAX   : INT := 3;            // 整定轮次上限 [次] / Trim round upper limit [count]
    DL_CDJ_ONE         : INT := 1;            // 计数步进一 [1] / Counter step of one [1]
    DL_CDJ_ZERO        : INT := 0;            // 计数零基准 [-] / Counter zero base [-]
    DL_CDJ_T_MIN       : TIME := T#100MS;     // 时间参数下限 [s] / Time parameter lower bound [s]
    DL_CDJ_T_MAX       : TIME := T#2H;        // 时间参数上限 [s] / Time parameter upper bound [s]
    DL_CDJ_T_SETTLE_DEF: TIME := T#15M;       // 沉后等待默认回退值（本身在域内）[s] / Default settling wait, already inside the domain [s]
    DL_CDJ_T_VERIFY_DEF: TIME := T#30M;       // 烧杯超时默认回退值（本身在域内）[s] / Default jar timeout, already inside the domain [s]
END_VAR

(* —— 段 1：中间量预置（只清当拍扫描量，不清锁存/基准/最后有效投加，FB32-1） —— *)
_iErrTmp   := 0;                              // 当拍故障首因复位 / Scan first fault cause reset
_bFaultReq := FALSE;                          // 当拍故障请求复位 / Scan fault request reset

(* —— 段 2：时间参数两级回退 + 入参非有限兜底 + 残留故障条件反算 —— *)
IF (tSettleTime < DL_CDJ_T_MIN) OR (tSettleTime > DL_CDJ_T_MAX) THEN
    _tSettle := DL_CDJ_T_SETTLE_DEF;          // 越域：回一级默认常量 / Out of domain: fall back to the default constant
ELSE
    _tSettle := tSettleTime;                  // 域内：原值采用 / Inside the domain: use as given
END_IF
IF (tVerifyTimeout < DL_CDJ_T_MIN) OR (tVerifyTimeout > DL_CDJ_T_MAX) THEN
    _tVerify := DL_CDJ_T_VERIFY_DEF;          // 越域：回一级默认常量 / Out of domain: fall back to the default constant
ELSE
    _tVerify := tVerifyTimeout;               // 域内：原值采用 / Inside the domain: use as given
END_IF
_rInNtuCl := rInNtu;                          // 进水浊度副本，参与前馈分段 / Inlet turbidity copy used by the feed-forward bands
IF (ABS(_rInNtuCl) > DL_CDJ_FIN) OR (_rInNtuCl < 0.0) THEN
    _rInNtuCl := 0.0;                         // 非有限或负值兜底为零（非有限判据用 ABS>FIN）/ Non-finite or negative falls back to zero
END_IF
_rOutNtuCl := rOutNtu;                        // 沉后浊度副本，参与复核倍率 / Settled turbidity copy used by the verification ratio
IF (ABS(_rOutNtuCl) > DL_CDJ_FIN) OR (_rOutNtuCl < 0.0) THEN
    _rOutNtuCl := 0.0;                        // 非有限或负值兜底为零 / Non-finite or negative falls back to zero
END_IF
_bFaultCondNow := FALSE;                      // 残留条件预置（eFault 出口唯一附加判据）/ Residual preset, the only extra fault-exit criterion
IF _iErrLatch = 14 THEN
    _bFaultCondNow := (rFlowM3h <= 0.0);      // 码 14：流量仍未恢复 / Code 14: flow still invalid
ELSIF _iErrLatch = 15 THEN
    _bFaultCondNow := (rStockGL <= DL_CDJ_EPS);      // 码 15：浓度仍未恢复 / Code 15: concentration still invalid
ELSIF _iErrLatch = 16 THEN
    _bFaultCondNow := (ABS(rOutNtuSp) <= DL_CDJ_EPS);  // 码 16：设定仍未恢复 / Code 16: setpoint still invalid
ELSIF _iErrLatch = 17 THEN
    _bFaultCondNow := (rDoseMaxLh <= DL_CDJ_EPS);    // 码 17：上限仍未恢复 / Code 17: upper limit still invalid
END_IF
(* 码 11（等待超时）是一次性已消费事件、码 99 是内部枚举损坏，二者均无残留输入条件，
   故复位沿单独即可退出故障相；此两条可达路径在上表已显式穷举，无死锁。 / Codes 11 and 99 leave no residual input condition *)

(* —— 段 3：边沿与定时器（全部在 CASE 外无条件刷新，R7；IN 带 NOT .Q 自复位，R188） —— *)
rtReset(CLK := bReset);                       // 复位边沿无条件刷新 / Reset edge refreshed unconditionally
rtEnable(CLK := bEnable);                     // 使能边沿无条件刷新（R528 起点判据）/ Enable edge refreshed unconditionally
rtJar(CLK := bJarResultReady);                // 烧杯结果边沿无条件刷新 / Jar result edge refreshed unconditionally
tonJar(IN := (_eState = E_DL_COAG_STATE.eJarTestWait) AND (NOT tonJar.Q) AND (NOT _bFaultLatch),
       PT := _tVerify);                       // 本相单发计时：仅等待相计时，超时即迁故障 / Single-shot timer in the wait phase only
tonSettle(IN := (_eState = E_DL_COAG_STATE.eVerify) AND (NOT tonSettle.Q) AND (NOT _bFaultLatch),
          PT := _tSettle);                    // 本相单发计时：仅复核相计时，与等待相无关 / Single-shot timer in the verify phase only

(* —— 段 4：状态机主体（唯一相位写入点；故障只置请求，锁存与迁相由段 7 执行） —— *)
CASE _eState OF
    E_DL_COAG_STATE.eIdle :
        (* 迁移①：拍 N 进入（使能上升沿）/ 本拍行为：三项参数有效性校验，任一无效即进故障 / 拍 N+1 转出至前馈相 *)
        IF rtEnable.Q AND (NOT _bFaultLatch) THEN
            IF rStockGL <= DL_CDJ_EPS THEN
                _iErrTmp   := 15;                                  // 故障级：母液浓度无效（除零闸）/ Fault: invalid stock concentration
                _bFaultReq := TRUE;                                 // 请求段 7 锁存 / Request the latch at segment 7
            ELSIF rFlowM3h <= 0.0 THEN
                _iErrTmp   := 14;                                  // 故障级：进水流量无效 / Fault: invalid inlet flow
                _bFaultReq := TRUE;                                 // 请求段 7 锁存 / Request the latch at segment 7
            ELSIF rDoseMaxLh <= DL_CDJ_EPS THEN
                _iErrTmp   := 17;                                  // 故障级：投加上限无效 / Fault: invalid pump upper limit
                _bFaultReq := TRUE;                                 // 请求段 7 锁存 / Request the latch at segment 7
            ELSE
                _iTrimCnt  := DL_CDJ_ZERO;                          // 新周期：整定轮次归零 / New cycle: trim counter cleared
                _iInfoCode := 0;                                    // 新周期：信息码归零 / New cycle: info code cleared
                _eState    := E_DL_COAG_STATE.eFeedForward;         // 迁移①：进前馈相 / Move to feed-forward
            END_IF
        END_IF

    E_DL_COAG_STATE.eFeedForward :
        (* 迁移②：拍 N 进入 / 本拍行为：按进水浊度三段给投加基准 / 拍 N+1 转出至烧杯等待相 *)
        IF _rInNtuCl <= DL_CDJ_NTU_SPLIT1 THEN
            _rBaseMgL := DL_CDJ_MGL_LOW;                            // 低浊段基准 [mg/L] / Low band base [mg/L]
        ELSIF _rInNtuCl <= DL_CDJ_NTU_SPLIT2 THEN
            _rBaseMgL := DL_CDJ_MGL_MID;                            // 中浊段基准 [mg/L] / Mid band base [mg/L]
        ELSE
            _rBaseMgL := DL_CDJ_MGL_HIGH;                           // 高浊段基准 [mg/L] / High band base [mg/L]
        END_IF
        _eState := E_DL_COAG_STATE.eJarTestWait;                    // 迁移②：进等待相 / Move to the jar wait phase

    E_DL_COAG_STATE.eJarTestWait :
        (* 迁移③：本拍合法事件（结果沿）优先于超时（R275）/ 拍 N 进入 / 拍 N+1 转出至修正相或故障相 *)
        IF rtJar.Q THEN
            _eState := E_DL_COAG_STATE.eTrim;                       // 迁移③：进修正相 / Move to the trim phase
        ELSIF tonJar.Q THEN
            _iErrTmp   := 11;                                       // 故障级：等待超时（设定保持不掉零）/ Fault: wait timeout, the setpoint is kept
            _bFaultReq := TRUE;                                     // 请求段 7 锁存 / Request the latch at segment 7
        END_IF

    E_DL_COAG_STATE.eTrim :
        (* 迁移④：拍 N 进入 / 本拍行为：按烧杯结果单次限幅 ±20% 修正基准、轮次饱和计数 / 拍 N+1 转出至复核相 *)
        _iInfoCode := 0;                                            // 进入修正：信息码归零 / Entering trim: info code cleared
        IF _iTrimCnt < DL_CDJ_CYCLE_MAX THEN
            _iTrimCnt := _iTrimCnt + DL_CDJ_ONE;                    // 轮次净额 +1，达容量上限即饱和 / Net round increment, saturated at capacity
        END_IF
        // NaN 与任何数比较均为假，故用 NOT(正向域) 做兜底，NaN 必落进非法分支
        IF NOT ((rJarResultMgL > DL_CDJ_EPS) AND (rJarResultMgL <= DL_CDJ_FIN)) THEN
            _iInfoCode := 13;                                       // 信息级：结果非法，本拍不改基准 / Info: illegal result, the base is untouched
        ELSIF _rBaseMgL > DL_CDJ_EPS THEN
            // 量纲: (mg/L - mg/L)/(mg/L) = 无量纲相对偏差，乘基准得新基准 [mg/L]
            _rDelta := (rJarResultMgL - _rBaseMgL) / _rBaseMgL;      // 相对偏差（分母已闸）/ Relative deviation, the denominator is guarded
            IF ABS(_rDelta) > DL_CDJ_FIN THEN
                _rDelta := 0.0;                                      // 偏差非有限即弃用，保基准 / non-finite deviation discarded
            END_IF
            IF _rDelta > DL_CDJ_TRIM_LIM THEN
                _rDelta := DL_CDJ_TRIM_LIM;                         // 正向限幅 +20% / Positive clamp at plus twenty percent
            END_IF
            IF _rDelta < -(DL_CDJ_TRIM_LIM) THEN
                _rDelta := -(DL_CDJ_TRIM_LIM);                      // 负向限幅 -20% / Negative clamp at minus twenty percent
            END_IF
            _rBaseMgL := _rBaseMgL * (1.0 + _rDelta);               // 量纲: (mg/L)*(无量纲) = mg/L / (mg/L) times dimensionless gives mg/L
        END_IF
        _eState := E_DL_COAG_STATE.eVerify;                         // 迁移④：进复核相 / Move to the verify phase

    E_DL_COAG_STATE.eVerify :
        (* 迁移⑤⑥：拍 N 进入 / 本拍行为：稳定后比较沉后浊度与设定，超 1.15 倍回修正 / 拍 N+1 转出至修正或保持相 *)
        IF tonSettle.Q THEN
            IF ABS(rOutNtuSp) <= DL_CDJ_EPS THEN
                _iErrTmp   := 16;                                   // 故障级：设定无效，倍率不可信 / Fault: invalid setpoint, the ratio is untrustworthy
                _bFaultReq := TRUE;                                 // 请求段 7 锁存 / Request the latch at segment 7
            ELSE
                // 量纲: (NTU)/(NTU) = 无量纲倍率，与 1.15 无量纲阈值直比
                _rRatio := _rOutNtuCl / rOutNtuSp;                  // 复核倍率（分母已闸）/ Verification ratio with a guarded denominator
                IF _rRatio > DL_CDJ_NTU_RATIO THEN
                    IF _iTrimCnt >= DL_CDJ_CYCLE_MAX THEN
                        _iInfoCode := 12;                           // 告警级：轮次耗尽，转保持 / Warning: rounds exhausted, go to hold
                        _eState    := E_DL_COAG_STATE.eHold;        // 迁移⑥：保持最后有效投加 / Keep the last valid dose
                    ELSE
                        _eState := E_DL_COAG_STATE.eTrim;           // 迁移⑤：回修正相再整定 / Back to trim for another round
                    END_IF
                ELSE
                    _iInfoCode := 0;                                // 达标：清信息码 / Passed: info code cleared
                    _eState    := E_DL_COAG_STATE.eHold;            // 迁移⑤：达标转保持相 / Passed, go to hold
                END_IF
            END_IF
        END_IF

    E_DL_COAG_STATE.eHold :
        (* 迁移⑦：拍 N 进入（复核达标或轮次耗尽）/ 本拍行为：执行位保持、设定保持 / 拍 N+1 转出至 eIdle（复位沿） *)
        IF rtReset.Q THEN
            _iInfoCode := 0;                                        // 复位：清信息码 / Reset: info code cleared
            _eState    := E_DL_COAG_STATE.eIdle;                    // 迁移⑦：回空闲相，不滞留 / Back to idle, never parked
        END_IF

    E_DL_COAG_STATE.eFault :
        (* 迁移⑧：拍 N 进入 / 本拍行为：只等出口条件（复位沿 + 残留条件消失）/ 拍 N+1 转出至 eIdle *)
        IF rtReset.Q AND (NOT _bFaultCondNow) THEN
            _bFaultLatch := FALSE;                                  // 清故障锁存 / Clear the fault latch
            _iErrLatch   := 0;                                      // 清锁存故障码 / Clear the latched code
            _iInfoCode   := 0;                                      // 清信息码 / Clear the info code
            _iTrimCnt    := DL_CDJ_ZERO;                            // 整定轮次清零 / Trim counter cleared
            _eState      := E_DL_COAG_STATE.eIdle;                  // 回空闲相 / Back to idle
        END_IF
ELSE
    (* 迁移⑨：非法枚举兜底（R6），码位赋值与锁存 3 行内配对（R45） *)
    IF NOT _bFaultLatch THEN
        _iErrLatch   := 99;                                         // 故障级：非法状态枚举值 / Fault: illegal state enum value
        _bFaultLatch := TRUE;                                       // 置故障锁存 / Latch the fault
    END_IF
END_CASE

(* —— 段 5：投加量换算（CASE 之后单点重算，使本拍更新的基准立刻生效，FB33-1） —— *)
IF (rStockGL > DL_CDJ_EPS) AND (rFlowM3h > 0.0) THEN
    // 量纲: (mg/L)*(m3/h)/1000 = kg/h 干药剂；(kg/h) / (g/L = kg/m3) * 1000 L/m3 = L/h 母液
    _rDoseCmd := _rBaseMgL * rFlowM3h / rStockGL;                   // 投加体积流量 [L/h] / Dosing volume flow [L/h]
    IF _rDoseCmd > rDoseMaxLh THEN
        _rDoseCmd := rDoseMaxLh;                                    // 上限饱和（载体 rDoseMaxLh）/ Saturate at the pump limit
    END_IF
    IF _rDoseCmd < 0.0 THEN
        _rDoseCmd := 0.0;                                           // 下限饱和 / Saturate at zero
    END_IF
ELSE
    _rDoseCmd := 0.0;                                               // 分母或流量无效：出零不猜值 / Invalid denominator or flow: emit zero, never guess
END_IF

(* —— 段 6：最后有效投加跟踪（不掉零载体，仅活动相且命令为正值时刷新） —— *)
IF (NOT _bFaultLatch) AND (_rDoseCmd > 0.0) THEN
    IF (_eState = E_DL_COAG_STATE.eFeedForward) OR (_eState = E_DL_COAG_STATE.eJarTestWait)
       OR (_eState = E_DL_COAG_STATE.eTrim) OR (_eState = E_DL_COAG_STATE.eVerify) THEN
        _rDoseLastGood := _rDoseCmd;                                // 每次相迁移与在线运行均刷新 / Refreshed on every phase move and while running
    END_IF
END_IF

(* —— 段 7：故障锁存 + 段尾故障迁相 + 撤使能降级（R191：已声明为「降级 + 设定保留」） —— *)
IF _bFaultReq AND (NOT _bFaultLatch) THEN
    _iErrLatch   := _iErrTmp;                                       // 锁存当拍首因 / Latch the first cause of this scan
    _bFaultLatch := TRUE;                                           // 置故障锁存 / Latch the fault
END_IF
IF _bFaultLatch AND (_eState <> E_DL_COAG_STATE.eFault) THEN
    _eState := E_DL_COAG_STATE.eFault;                              // 锁存即迁相（段尾统一执行）/ The latch forces the fault phase at the tail
END_IF
IF (NOT bEnable) AND (NOT _bFaultLatch) AND (_eState <> E_DL_COAG_STATE.eIdle) THEN
    _eState := E_DL_COAG_STATE.eIdle;                               // 撤使能：回空闲，设定值保留 / Disable: back to idle with the setpoint kept
END_IF

(* —— 段 8：统一出口（单点映射，禁在 CASE 后无条件清零 CASE 内赋值标识符，FB33-1） —— *)
bDoseOn := (NOT _bFaultLatch) AND ((_eState = E_DL_COAG_STATE.eFeedForward)
           OR (_eState = E_DL_COAG_STATE.eJarTestWait) OR (_eState = E_DL_COAG_STATE.eTrim)
           OR (_eState = E_DL_COAG_STATE.eVerify) OR (_eState = E_DL_COAG_STATE.eHold));  // 执行位：故障相强制 FALSE / Run bit, forced FALSE in fault
IF _bFaultLatch OR (_eState = E_DL_COAG_STATE.eHold) THEN
    rDoseLh := _rDoseLastGood;                                      // 故障相与保持相：设定保持最后有效值不掉零 / Fault and hold keep the last valid setpoint
ELSE
    rDoseLh := _rDoseCmd;                                           // 活动相：输出当拍换算值 / Active phases emit the freshly computed dose
END_IF
IF _bFaultLatch THEN
    iErrCode := _iErrLatch;                                         // 故障期回放锁存码 / Replay the latched code during fault
ELSE
    iErrCode := _iInfoCode;                                         // 非故障期输出信息/告警码 / Info or warning code outside fault
END_IF
IF _eState = E_DL_COAG_STATE.eIdle THEN
    sMsg := 'IDLE';                                                 // 空闲 / Idle
ELSIF _eState = E_DL_COAG_STATE.eFeedForward THEN
    sMsg := 'FEEDFWD';                                              // 前馈给定 / Feed-forward
ELSIF _eState = E_DL_COAG_STATE.eJarTestWait THEN
    sMsg := 'JARWAIT';                                              // 等烧杯结果 / Waiting for the jar result
ELSIF _eState = E_DL_COAG_STATE.eTrim THEN
    sMsg := 'TRIM';                                                 // 基准修正 / Base trimming
ELSIF _eState = E_DL_COAG_STATE.eVerify THEN
    sMsg := 'VERIFY';                                               // 沉后复核 / Settled verification
ELSIF _eState = E_DL_COAG_STATE.eHold THEN
    sMsg := 'HOLD';                                                 // 保持 / Holding
ELSE
    sMsg := 'FAULT';                                                // 故障 / Fault
END_IF
END_FUNCTION_BLOCK
