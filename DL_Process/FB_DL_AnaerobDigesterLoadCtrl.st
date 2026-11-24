(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FB_DL_AnaerobDigesterLoadCtrl
  分类: DL_Process
  复杂度: C4 ｜ 版本: 1.0.0 ｜ 2026-11-24
  平台兼容: CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
  开源溯源: 无（clean-room 工程算法自研；参考公开的厌氧消化 VFA/碱度比预警与产气量联动降载
            工艺经验，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)

  功能职责:
    厌氧消化罐进料负荷控制。VFA/碱度比越限（>0.4）逐窗降载至下限 20% 流量；比值落回 0.25~0.4
    进 eWatch 保持不增；产气量低于基准 70% 连续确认后直接降载（码 41）；稳定后先一步 eDerate
    再进 eRecover，每窗回升 5% 直至回满并完成两级确认才回 eNormal。
    越限降载路径是安全侧：先降流量，再报码。

  输入/输出契约:
    IN  bEnable 上升沿启动（并做四项参数校验）；FALSE 输出归零回 eIdle（R191 声明）。
    IN  bReset 上升沿是 eFault 唯一出口（还须残留故障条件消失），同时流量归 0。
    OUT rFeedOutM3h 实际进料流量 = MIN(实测, 当前限值) [m3/h]。
    OUT iLoadLevel  0~10 级负荷显式映射（每 10% 限值一级），故障/空闲为 0 级。

  码表 (Codes):
    41 = 产气骤降联动降载（信息级；gas < 0.7×基准且基准有效）
    42 = 进料流量上限无效（故障级；rFeedMaxM3h ≤ 0 或非有限，限值与级数不可算）
    43 = 降载步长越域（信息级；rStepDownPct 越 (0,50] 已回默认 10%）
    44 = VFA/碱度比越限降载（信息级；ratio > 0.4）
    45 = 碱度无效（故障级；rAlkMgL ≤ 0，除零闸）
    46 = 关键入参非有限（故障级；vfa / gas / feed 任一 ABS > 1.0E15）
    47 = 产气基准未整定（信息级；产气联动降载已禁用，仅按比值控制，降级已声明）
    48 = 降至下限仍越限（故障级；已到 20% 流量下限而比值仍越限，需人工介入）
    99 = 非法状态枚举值（ELSE 兜底）

  边界与红线:
    ① 两个定时器与两个 R_TRIG 全在 CASE 外无条件刷新（R7），CASE 内只读 .Q。
    ② tonConfirm 覆盖 eNormal / eWatch / eDerate 三相（相位无关的越限累计窗），tonRecover 覆盖
       eDerate / eRecover 两相，二者均带 NOT .Q 自复位（R188），并在此显式声明为
       **跨相累计看门狗**（红线 14）——按相拆开会漏计跨相连续的越限/稳定，属判据缺陷。
    ③ 两级确认（防抖）：连续两个 tConfirm 窗都越限才降载（_iConfCnt 容量载体
       DL_ADC_CONF_MAX）；回升到 eNormal 亦须连续两个 tRecover 窗稳定且限值回满。
    ④ 降载步进单点执行（段 5 的 _bStepReq 触发器），每窗仅一步，禁在 CASE 分支内重复乘；
       降载下限 DL_ADC_FLOOR_RATIO = 20% 流量，上限回满 100%。
    ⑤ R528：bEnable 必须上升沿且碱度、流量上限、三项信号有效性都通过才迁 eNormal；
       全默认引脚时停留 eIdle，绝不直达 eNormal / eDerate。
    ⑥ eFault 出口 = rtReset.Q AND NOT _bFaultCondNow（逐码反算残留条件，R28 可达性）。
    ⑦ 派单原文「gas < 0.7*base 且 ABS(base)>FIN」中的 ABS(base)>FIN 若照写即为死谓词
       （基准不可能大于 1E15 才生效，等于永久禁用该降载路径）；此处按工程反证改写为
       「基准非零且有限」（_bBaseOk），并把「基准未整定」显式报码 47，不静默失效。
  修订历史: 2026-11-24  v1.0.0  R82-B 首版
*)

TYPE E_DL_AD_STATE :
(
    eIdle    := 0,    // 空闲：等使能上升沿 / Idle: waiting for the enable rising edge
    eNormal  := 1,    // 正常相：满负荷进料，持续监视 / Normal: full load feeding with continuous supervision
    eWatch   := 2,    // 关注相：比值 0.25~0.4，保持不增 / Watch: ratio between 0.25 and 0.4, hold and do not increase
    eDerate  := 3,    // 降载相：按窗步进降流量 / Derate: step the flow down window by window
    eRecover := 4,    // 回升相：每窗升 5% 直至回满 / Recover: raise five percent per window up to full load
    eFault   := 5     // 故障安全相：流量归零 / Fault safe phase: the flow is forced to zero
);
END_TYPE

FUNCTION_BLOCK FB_DL_AnaerobDigesterLoadCtrl
VAR_INPUT
    bEnable       : BOOL := FALSE;     // 使能（上升沿启动；FALSE 输出归零回空闲）/ Enable, rising edge starts, FALSE zeroes the outputs
    bReset        : BOOL := FALSE;     // 复位（上升沿，eFault 唯一出口，流量归零）/ Reset rising edge, the only fault exit, the flow is zeroed
    rVfaMgL       : REAL := 0.0;       // 挥发性脂肪酸 VFA [mg/L] / Volatile fatty acids [mg/L]
    rAlkMgL       : REAL := 0.0;       // 碱度（以 CaCO3 计）[mg/L] / Alkalinity as CaCO3 [mg/L]
    rGasM3h       : REAL := 0.0;       // 产气量实测 [m3/h] / Measured biogas flow [m3/h]
    rGasBaseM3h   : REAL := 0.0;       // 产气量基准（整定值）[m3/h] / Biogas flow baseline after commissioning [m3/h]
    rFeedM3h      : REAL := 0.0;       // 进料流量实测 [m3/h] / Measured feed flow [m3/h]
    rFeedMaxM3h   : REAL := 0.0;       // 进料流量上限（100% 负荷）[m3/h] / Feed flow upper limit at one hundred percent load [m3/h]
    rStepDownPct  : REAL := 10.0;      // 单次降载步长，有效域 (0,50] [%] / Per-step derate percentage, valid domain above zero up to fifty [%]
    tConfirm      : TIME := T#60S;     // 越限确认窗，有效域 1s..2h [s] / Violation confirmation window, valid domain 1s..2h [s]
    tRecover      : TIME := T#5M;      // 回升/稳定窗，有效域 1s..2h [s] / Recovery window, valid domain 1s..2h [s]
END_VAR
VAR_OUTPUT
    rFeedOutM3h   : REAL := 0.0;       // 实际进料流量设定 [m3/h] / Actual feed flow setpoint [m3/h]
    bFeedOn       : BOOL := FALSE;     // 进料运行位（故障相强制 FALSE）/ Feed run bit, forced FALSE in the fault phase
    iLoadLevel    : INT := 0;          // 负荷等级 0~10（每 10% 一级）[级] / Load level from zero to ten, one level per ten percent [level]
    iErrCode      : INT := 0;          // 错误码（故障期锁存回放）/ Error code, latched replay during fault
    sMsg          : STRING;            // 文本提示（当前相位摘要）/ Text message, a summary of the current phase
END_VAR
VAR
    _eState        : E_DL_AD_STATE := E_DL_AD_STATE.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase, the only CASE write target
    _bFaultLatch   : BOOL := FALSE;    // 故障锁存位 / Fault latch
    _iErrLatch     : INT := 0;         // 锁存故障码（故障期唯一回放源）/ Latched fault code, the only replay source during fault
    _iInfoCode     : INT := 0;         // 信息级码 / Info code
    _iErrTmp       : INT := 0;         // 当拍故障首因中间量 / First fault cause of this scan
    _bFaultReq     : BOOL := FALSE;    // 当拍故障请求（段 6 统一锁存）/ Fault request of this scan, latched at segment 6
    _bFaultCondNow : BOOL := FALSE;    // 残留故障条件（eFault 出口唯一附加判据）/ Residual fault condition, the only extra fault-exit criterion
    _bStepReq      : BOOL := FALSE;    // 本拍降载步请求（段 5 单点执行）/ Derate step request of this scan, executed once at segment 5
    _bStepOutDom   : BOOL := FALSE;    // 降载步长越域标志（本拍已回默认）/ Derate step out-of-domain flag, the default was applied this scan
    _bRatioOk      : BOOL := FALSE;    // 比值可算标志（碱度有效且有限）/ Ratio computable flag, alkalinity valid and finite
    _bBaseOk       : BOOL := FALSE;    // 产气基准有效标志（非零且有限）/ Biogas baseline valid flag, non-zero and finite
    _bViolation    : BOOL := FALSE;    // 越限标志（比值高 或 产气骤降）/ Violation flag, high ratio or a biogas collapse
    _bRatioHigh    : BOOL := FALSE;    // 比值越限标志（ratio > 0.4）/ High ratio flag
    _bRatioWatch   : BOOL := FALSE;    // 比值关注标志（0.25 < ratio ≤ 0.4）/ Watch band flag
    _bGasLow       : BOOL := FALSE;    // 产气骤降标志（gas < 0.7×基准）/ Biogas collapse flag
    _bStableCond   : BOOL := FALSE;    // 稳定条件（ratio < 0.25 且产气回 0.9×基准）/ Stable condition, low ratio and recovered gas
    _rVfaCl        : REAL := 0.0;      // VFA 净化副本 [mg/L] / Sanitised VFA copy [mg/L]
    _rAlkCl        : REAL := 0.0;      // 碱度净化副本 [mg/L] / Sanitised alkalinity copy [mg/L]
    _rGasCl        : REAL := 0.0;      // 产气净化副本 [m3/h] / Sanitised biogas copy [m3/h]
    _rFeedCl       : REAL := 0.0;      // 进料净化副本 [m3/h] / Sanitised feed copy [m3/h]
    _rFeedMax      : REAL := 0.0;      // 流量上限净化值 [m3/h] / Sanitised feed maximum [m3/h]
    _rRatio        : REAL := 0.0;      // VFA/碱度比（无量纲）/ VFA to alkalinity ratio, dimensionless
    _rStepPct      : REAL := 10.0;     // 生效降载步长 [%] / Effective derate step [%]
    _rStepRatio    : REAL := 0.1;      // 生效降载步长折比（无量纲）/ Effective derate step as a fraction, dimensionless
    _rFloorM3h     : REAL := 0.0;      // 流量下限 = 20% 上限 [m3/h] / Flow floor at twenty percent of the maximum [m3/h]
    _rFeedLimit    : REAL := 0.0;      // 当前流量限值 [m3/h] / Current feed flow limit [m3/h]
    _rLoadPct      : REAL := 0.0;      // 当前限值占上限百分比 [%] / Current limit as a percentage of the maximum [%]
    _iLevel        : INT := 0;         // 负荷等级中间量 [级] / Intermediate load level [level]
    _iConfCnt      : INT := 0;         // 连续越限窗计数，容量载体 DL_ADC_CONF_MAX [窗] / Consecutive violation windows, capacity carrier DL_ADC_CONF_MAX [window]
    _iRecovCnt     : INT := 0;         // 连续稳定窗计数，容量载体 DL_ADC_CONF_MAX [窗] / Consecutive stable windows, capacity carrier DL_ADC_CONF_MAX [window]
    _tConfirm      : TIME := T#60S;    // 越限确认窗钳定值 [s] / Clamped violation window [s]
    _tRecover      : TIME := T#5M;     // 回升窗钳定值 [s] / Clamped recovery window [s]
    rtReset        : R_TRIG;           // bReset 边沿（段 3 无条件刷新）/ bReset edge, refreshed unconditionally
    rtEnable       : R_TRIG;           // bEnable 边沿（段 3 无条件刷新，R528）/ bEnable edge, refreshed unconditionally
    tonConfirm     : TON;              // 越限累计窗（跨相看门狗，自复位）/ Cumulative violation window, cross-phase watchdog with self reset
    tonRecover     : TON;              // 稳定累计窗（跨相看门狗，自复位）/ Cumulative stable window, cross-phase watchdog with self reset
END_VAR
VAR CONSTANT
    DL_ADC_EPS         : REAL := 1.0E-6;   // 数值闸阈值 [-]/ Numeric guard threshold [-]
    DL_ADC_FIN         : REAL := 1.0E15;   // 非有限判据阈值（ABS 比较用）[-] / Non-finite criterion threshold, compared by ABS [-]
    DL_ADC_RATIO_HI    : REAL := 0.4;      // 比值越限阈值（无量纲）/ High ratio threshold, dimensionless
    DL_ADC_RATIO_LO    : REAL := 0.25;     // 比值正常阈值（无量纲）/ Low ratio threshold, dimensionless
    DL_ADC_GAS_DROP    : REAL := 0.7;      // 产气骤降判定比（无量纲）/ Biogas collapse factor, dimensionless
    DL_ADC_GAS_REC     : REAL := 0.9;      // 产气恢复判定比（无量纲）/ Biogas recovery factor, dimensionless
    DL_ADC_STEP_DEF    : REAL := 10.0;     // 降载步长默认值 [%] / Default derate step [%]
    DL_ADC_STEP_MAX    : REAL := 50.0;     // 降载步长上限 [%] / Derate step upper limit [%]
    DL_ADC_FLOOR_RATIO : REAL := 0.2;      // 流量下限折比 20%（无量纲）/ Flow floor fraction of twenty percent, dimensionless
    DL_ADC_STEP_UP     : REAL := 0.05;     // 回升每窗步长 5%（无量纲）/ Recovery step of five percent per window, dimensionless
    DL_ADC_PCT_BASE    : REAL := 100.0;    // 百分比基准 [%] / Percentage base [%]
    DL_ADC_CONF_MAX    : INT := 2;         // 两级确认所需连续窗数 [窗] / Consecutive windows needed for the two-stage confirmation [window]
    DL_ADC_LEVEL_MAX   : INT := 10;        // 负荷等级上限 [级] / Load level upper limit [level]
    DL_ADC_ONE         : INT := 1;         // 计数步进一 [1] / Counter step of one [1]
    DL_ADC_ZERO        : INT := 0;         // 计数零基准 [-] / Counter zero base [-]
    DL_ADC_T_MIN       : TIME := T#1S;     // 时间参数下限 [s] / Time parameter lower bound [s]
    DL_ADC_T_MAX       : TIME := T#2H;     // 时间参数上限 [s] / Time parameter upper bound [s]
    DL_ADC_T_CONF_DEF  : TIME := T#60S;    // 确认窗默认回退值（在域内）[s] / Default confirmation window inside the domain [s]
    DL_ADC_T_REC_DEF   : TIME := T#5M;     // 回升窗默认回退值（在域内）[s] / Default recovery window inside the domain [s]
END_VAR

(* —— 段 1：中间量预置（只清当拍扫描量，不清锁存/限值/窗计数，FB32-1） —— *)
_iErrTmp   := 0;                                     // 当拍故障首因复位 / Scan first fault cause reset
_bFaultReq := FALSE;                                 // 当拍故障请求复位 / Scan fault request reset
_bStepReq  := FALSE;                                 // 本拍降载步请求复位 / Derate step request reset

(* —— 段 2：时间参数两级回退 + 入参净化 + 判据量折算（组态域闸覆盖每个引脚） —— *)
IF (tConfirm < DL_ADC_T_MIN) OR (tConfirm > DL_ADC_T_MAX) THEN
    _tConfirm := DL_ADC_T_CONF_DEF;                  // 越域：回一级默认常量 / Out of domain: fall back to the default constant
ELSE
    _tConfirm := tConfirm;                           // 域内：原值采用 / Inside the domain: use as given
END_IF
IF (tRecover < DL_ADC_T_MIN) OR (tRecover > DL_ADC_T_MAX) THEN
    _tRecover := DL_ADC_T_REC_DEF;                   // 越域：回一级默认常量 / Out of domain: fall back to the default constant
ELSE
    _tRecover := tRecover;                           // 域内：原值采用 / Inside the domain: use as given
END_IF
_rVfaCl := rVfaMgL;                                  // VFA 净化副本 [mg/L] / Sanitised VFA copy [mg/L]
IF (ABS(_rVfaCl) > DL_ADC_FIN) OR (_rVfaCl < 0.0) THEN
    _rVfaCl := 0.0;                                  // 非有限或负值兜底为零 / Non-finite or negative falls back to zero
END_IF
_rAlkCl := rAlkMgL;                                  // 碱度净化副本 [mg/L] / Sanitised alkalinity copy [mg/L]
IF (ABS(_rAlkCl) > DL_ADC_FIN) OR (_rAlkCl < 0.0) THEN
    _rAlkCl := 0.0;                                  // 非有限或负值兜底为零 / Non-finite or negative falls back to zero
END_IF
_rGasCl := rGasM3h;                                  // 产气净化副本 [m3/h] / Sanitised biogas copy [m3/h]
IF (ABS(_rGasCl) > DL_ADC_FIN) OR (_rGasCl < 0.0) THEN
    _rGasCl := 0.0;                                  // 非有限或负值兜底为零 / Non-finite or negative falls back to zero
END_IF
_rFeedCl := rFeedM3h;                                // 进料净化副本 [m3/h] / Sanitised feed copy [m3/h]
IF (ABS(_rFeedCl) > DL_ADC_FIN) OR (_rFeedCl < 0.0) THEN
    _rFeedCl := 0.0;                                 // 非有限或负值兜底为零 / Non-finite or negative falls back to zero
END_IF
_rFeedMax := rFeedMaxM3h;                            // 流量上限净化值 [m3/h] / Sanitised feed maximum [m3/h]
IF (ABS(_rFeedMax) > DL_ADC_FIN) OR (_rFeedMax < 0.0) THEN
    _rFeedMax := 0.0;                                // 非有限或负值兜底为零 / Non-finite or negative falls back to zero
END_IF
_rStepPct := rStepDownPct;                           // 降载步长初值 [%] / Initial derate step [%]
_bStepOutDom := FALSE;                               // 越域标志预置 / Out-of-domain flag preset
IF (ABS(_rStepPct) > DL_ADC_FIN) OR (_rStepPct <= 0.0) OR (_rStepPct > DL_ADC_STEP_MAX) THEN
    _rStepPct    := DL_ADC_STEP_DEF;                 // 越域回默认（不静默：由信息码 43 上报）/ Out of domain falls back, reported by info code 43
    _bStepOutDom := TRUE;                            // 置越域标志（段 5 报码 43）/ Raise the flag, code 43 is emitted at segment 5
END_IF
_rStepRatio := _rStepPct / DL_ADC_PCT_BASE;          // 量纲: (%)/(%) = 无量纲折比 / Percentage over percentage gives a dimensionless fraction
_bRatioOk := (_rAlkCl > DL_ADC_EPS);                 // 比值可算：碱度有效（除零闸）/ The ratio is computable when the alkalinity is valid
IF _bRatioOk THEN
    // 量纲: (mg/L)/(mg/L) = 无量纲比值，与 0.4 / 0.25 无量纲阈值直比
    _rRatio := _rVfaCl / _rAlkCl;                    // VFA/碱度比（分母已闸）/ VFA to alkalinity ratio with a guarded denominator
ELSE
    _rRatio := 0.0;                                  // 分母无效：比值出零，绝不猜值 / Invalid denominator: the ratio is zero, never guessed
END_IF
_rFloorM3h := _rFeedMax * DL_ADC_FLOOR_RATIO;        // 量纲: (m3/h)*(无量纲) = m3/h 下限 / (m3/h) times dimensionless gives the floor [m3/h]
_bBaseOk := (ABS(rGasBaseM3h) > DL_ADC_EPS) AND (ABS(rGasBaseM3h) <= DL_ADC_FIN);   // 基准有效：非零且有限 / Baseline valid: non-zero and finite
_bRatioHigh  := _bRatioOk AND (_rRatio > DL_ADC_RATIO_HI);                                     // 比值越限 / High ratio
_bRatioWatch := _bRatioOk AND (_rRatio > DL_ADC_RATIO_LO) AND (NOT _bRatioHigh);                // 关注带 / Watch band
IF _bBaseOk THEN
    // 量纲: (m3/h)*(无量纲) = m3/h 判定门限
    _bGasLow     := _rGasCl < (rGasBaseM3h * DL_ADC_GAS_DROP);                                 // 产气骤降 / Biogas collapse
    _bStableCond := (_rRatio < DL_ADC_RATIO_LO) AND (_bRatioOk) AND (_rGasCl > (rGasBaseM3h * DL_ADC_GAS_REC));   // 稳定条件 / Stable condition
ELSE
    _bGasLow     := FALSE;                                                                      // 基准无效：产气联动禁用（码 47 上报）
    _bStableCond := (_rRatio < DL_ADC_RATIO_LO) AND (_bRatioOk);                                 // 仅按比值判定稳定 / Stability by ratio alone
END_IF
_bViolation := _bRatioHigh OR _bGasLow;              // 越限 = 比值高 或 产气骤降 / Violation is a high ratio or a biogas collapse
_bFaultCondNow := FALSE;                             // 残留条件预置（eFault 出口唯一附加判据）/ Residual preset, the only extra fault-exit criterion
IF _iErrLatch = 42 THEN
    _bFaultCondNow := (rFeedMaxM3h <= DL_ADC_EPS) OR (ABS(rFeedMaxM3h) > DL_ADC_FIN);   // 码 42：上限仍无效 / Code 42: the maximum is still invalid
ELSIF _iErrLatch = 45 THEN
    _bFaultCondNow := (rAlkMgL <= DL_ADC_EPS);                                          // 码 45：碱度仍无效 / Code 45: the alkalinity is still invalid
ELSIF _iErrLatch = 46 THEN
    _bFaultCondNow := (ABS(rVfaMgL) > DL_ADC_FIN) OR (ABS(rGasM3h) > DL_ADC_FIN) OR (ABS(rFeedM3h) > DL_ADC_FIN);   // 码 46：非有限仍在 / Code 46: the non-finite input persists
ELSIF _iErrLatch = 48 THEN
    _bFaultCondNow := _bViolation;                                                       // 码 48：越限仍在 / Code 48: the violation persists
END_IF
(* 码 99（非法枚举）为内部损坏，无输入残留条件，复位沿单独即可退出。 / Code 99 has no residual input condition *)

(* —— 段 3：边沿与定时器（全部在 CASE 外无条件刷新，R7；IN 带 NOT .Q 自复位，R188） —— *)
rtReset(CLK := bReset);                              // 复位边沿无条件刷新 / Reset edge refreshed unconditionally
rtEnable(CLK := bEnable);                            // 使能边沿无条件刷新（R528 起点判据）/ Enable edge refreshed unconditionally
tonConfirm(IN := ((_eState = E_DL_AD_STATE.eNormal) OR (_eState = E_DL_AD_STATE.eWatch)
                  OR (_eState = E_DL_AD_STATE.eDerate))
                 AND _bViolation AND (NOT tonConfirm.Q) AND (NOT _bFaultLatch),
           PT := _tConfirm);                         // 跨相累计看门狗：三相内越限持续累计，非本相超时 / Cumulative watchdog over three phases, not a phase timeout
tonRecover(IN := ((_eState = E_DL_AD_STATE.eDerate) OR (_eState = E_DL_AD_STATE.eRecover))
                 AND _bStableCond AND (NOT tonRecover.Q) AND (NOT _bFaultLatch),
           PT := _tRecover);                         // 跨相累计看门狗：降载与回升两相内稳定累计 / Cumulative watchdog over the derate and recover phases
IF NOT _bViolation THEN
    _iConfCnt := DL_ADC_ZERO;                        // 越限中断：连续窗计数清零（防抖前提）/ Violation interrupted: the consecutive window counter is cleared
END_IF
IF tonConfirm.Q THEN
    IF _iConfCnt < DL_ADC_CONF_MAX THEN
        _iConfCnt := _iConfCnt + DL_ADC_ONE;         // 越限窗计数 +1，达容量上限饱和 / Violation window counter incremented and saturated at capacity
    END_IF
END_IF
IF NOT _bStableCond THEN
    _iRecovCnt := DL_ADC_ZERO;                       // 稳定中断：连续窗计数清零 / Stability interrupted: the consecutive window counter is cleared
END_IF
IF tonRecover.Q THEN
    IF _iRecovCnt < DL_ADC_CONF_MAX THEN
        _iRecovCnt := _iRecovCnt + DL_ADC_ONE;       // 稳定窗计数 +1，达容量上限饱和 / Stable window counter incremented and saturated at capacity
    END_IF
END_IF

(* —— 段 4：状态机主体（唯一相位写入点；降载步只置请求，由段 5 单点执行） —— *)
CASE _eState OF
    E_DL_AD_STATE.eIdle :
        (* 迁移①：拍 N 进入（使能上升沿）/ 本拍行为：四项参数校验，缺任一即故障 / 拍 N+1 转出至正常相 *)
        IF rtEnable.Q AND (NOT _bFaultLatch) THEN
            IF (rFeedMaxM3h <= DL_ADC_EPS) OR (ABS(rFeedMaxM3h) > DL_ADC_FIN) THEN
                _iErrTmp   := 42;                                  // 故障级：流量上限无效 / Fault: invalid feed maximum
                _bFaultReq := TRUE;                                // 请求段 6 锁存 / Request the latch at segment 6
            ELSIF NOT _bRatioOk THEN
                _iErrTmp   := 45;                                  // 故障级：碱度无效（除零闸）/ Fault: invalid alkalinity
                _bFaultReq := TRUE;                                // 请求段 6 锁存 / Request the latch at segment 6
            ELSIF (ABS(rVfaMgL) > DL_ADC_FIN) OR (ABS(rGasM3h) > DL_ADC_FIN) OR (ABS(rFeedM3h) > DL_ADC_FIN) THEN
                _iErrTmp   := 46;                                  // 故障级：关键入参非有限 / Fault: a key input is non-finite
                _bFaultReq := TRUE;                                // 请求段 6 锁存 / Request the latch at segment 6
            ELSE
                _rFeedLimit := _rFeedMax;                          // 新周期：限值回满 100% / New cycle: the limit starts at one hundred percent
                _iConfCnt   := DL_ADC_ZERO;                        // 新周期：越限窗计数清零 / New cycle: violation window counter cleared
                _iRecovCnt  := DL_ADC_ZERO;                        // 新周期：稳定窗计数清零 / New cycle: stable window counter cleared
                _iInfoCode  := 0;                                  // 新周期：信息码归零 / New cycle: info code cleared
                IF NOT _bBaseOk THEN
                    _iInfoCode := 47;                              // 信息级：基准未整定，产气联动已禁用 / Info: no baseline, the biogas link is disabled
                END_IF
                _eState := E_DL_AD_STATE.eNormal;                  // 迁移①：进正常相 / Move to normal
            END_IF
        END_IF

    E_DL_AD_STATE.eNormal :
        (* 迁移②③④：拍 N 进入 / 本拍行为：满负荷监视；越限两级确认后降载 / 拍 N+1 转出 *)
        IF _iConfCnt >= DL_ADC_CONF_MAX THEN
            IF _bGasLow THEN
                _iInfoCode := 41;                                  // 信息级：产气骤降联动降载 / Info: biogas collapse derate
            ELSE
                _iInfoCode := 44;                                  // 信息级：比值越限降载 / Info: ratio violation derate
            END_IF
            _bStepReq := TRUE;                                     // 请求段 5 执行一步降载 / Request one derate step at segment 5
            _iRecovCnt := DL_ADC_ZERO;                             // 进降载：稳定窗计数清零 / Entering derate: the stable window counter is cleared
            _eState := E_DL_AD_STATE.eDerate;                      // 迁移②：进降载相 / Move to derate
        ELSIF _bRatioWatch THEN
            _iInfoCode := 0;                                       // 关注带不降载，仅保持不增 / The watch band does not derate, it only prevents increases
            _eState := E_DL_AD_STATE.eWatch;                        // 迁移③：进关注相 / Move to watch
        END_IF

    E_DL_AD_STATE.eWatch :
        (* 迁移⑤⑥：拍 N 进入 / 本拍行为：保持当前限值不增（禁回升）/ 拍 N+1 转出至降载相或正常相 *)
        IF _iConfCnt >= DL_ADC_CONF_MAX THEN
            IF _bGasLow THEN
                _iInfoCode := 41;                                  // 信息级：产气骤降联动降载 / Info: biogas collapse derate
            ELSE
                _iInfoCode := 44;                                  // 信息级：比值越限降载 / Info: ratio violation derate
            END_IF
            _bStepReq := TRUE;                                     // 请求段 5 执行一步降载 / Request one derate step at segment 5
            _iRecovCnt := DL_ADC_ZERO;                             // 进降载：稳定窗计数清零 / Entering derate: the stable window counter is cleared
            _eState := E_DL_AD_STATE.eDerate;                      // 迁移⑤：进降载相 / Move to derate
        ELSIF (_bRatioOk) AND (_rRatio < DL_ADC_RATIO_LO) THEN
            _eState := E_DL_AD_STATE.eNormal;                      // 迁移⑥：比值回落，回正常相 / Ratio recovered, back to normal
        END_IF

    E_DL_AD_STATE.eDerate :
        (* 迁移⑦⑧⑨：拍 N 进入 / 本拍行为：每个越限确认窗限速降一步 / 拍 N+1 转出至回升相或故障相 *)
        IF _rFeedLimit <= (_rFloorM3h + DL_ADC_EPS) THEN
            IF _bViolation THEN
                _iErrTmp   := 48;                                  // 故障级：已到下限仍越限 / Fault: still violating at the floor
                _bFaultReq := TRUE;                                // 请求段 6 锁存 / Request the latch at segment 6
            END_IF
        END_IF
        IF tonConfirm.Q AND (NOT _bFaultReq) THEN
            IF _bBaseOk AND _bGasLow THEN
                _iInfoCode := 41;                                  // 信息级：产气骤降继续降载 / Info: the biogas collapse keeps derating
            ELSIF _bRatioHigh THEN
                _iInfoCode := 44;                                  // 信息级：比值继续越限降载 / Info: the ratio keeps violating
            END_IF
            _bStepReq := TRUE;                                     // 请求段 5 再执行一步降载 / Request another derate step at segment 5
        END_IF
        IF tonRecover.Q THEN
            _eState := E_DL_AD_STATE.eRecover;                     // 迁移⑧：稳定一窗，进回升相 / One stable window, move to recover
        END_IF

    E_DL_AD_STATE.eRecover :
        (* 迁移⑩⑪⑫：拍 N 进入 / 本拍行为：每个稳定窗升 5%，回满且两级确认后回正常 / 拍 N+1 转出 *)
        IF _bViolation THEN
            _iConfCnt  := DL_ADC_ZERO;                             // 回升中越限：越限窗计数从头计 / Violation during recovery restarts the window counter
            _iInfoCode := 44;                                      // 信息级：回升中止（先降后报）/ Info: recovery aborted, derate first
            _bStepReq  := TRUE;                                    // 请求段 5 执行一步降载 / Request one derate step at segment 5
            _eState    := E_DL_AD_STATE.eDerate;                   // 迁移⑩：中止回升，回降载相 / Abort recovery and go back to derate
        ELSIF tonRecover.Q THEN
            IF _rFeedLimit < _rFeedMax THEN
                // 量纲: (m3/h)*(无量纲) = m3/h 步长，累加到限值
                _rFeedLimit := _rFeedLimit + (_rFeedMax * DL_ADC_STEP_UP);   // 每窗回升 5% 上限 [m3/h] / Raise by five percent of the maximum per window [m3/h]
                IF _rFeedLimit > _rFeedMax THEN
                    _rFeedLimit := _rFeedMax;                      // 回满饱和，禁超上限 / Saturate at the maximum, never exceed it
                END_IF
                _iInfoCode := 0;                                   // 回升中：清信息码 / Recovering: info code cleared
            ELSIF _iRecovCnt >= DL_ADC_CONF_MAX THEN
                _eState := E_DL_AD_STATE.eNormal;                  // 迁移⑫：回满且两级确认，回正常相 / Full and confirmed twice, back to normal
            END_IF
        END_IF

    E_DL_AD_STATE.eFault :
        (* 迁移⑬：拍 N 进入 / 本拍行为：流量归零，只等出口条件 / 拍 N+1 转出至 eIdle *)
        IF rtReset.Q AND (NOT _bFaultCondNow) THEN
            _bFaultLatch := FALSE;                                 // 清故障锁存 / Clear the fault latch
            _iErrLatch   := 0;                                     // 清锁存故障码 / Clear the latched code
            _iInfoCode   := 0;                                     // 清信息码 / Clear the info code
            _rFeedLimit  := _rFeedMax;                             // 限值重置为满负荷（流量归零由段 7 执行）/ The limit is reset to full, the flow is zeroed at segment 7
            _iConfCnt    := DL_ADC_ZERO;                           // 越限窗计数清零 / Violation window counter cleared
            _iRecovCnt   := DL_ADC_ZERO;                           // 稳定窗计数清零 / Stable window counter cleared
            _eState      := E_DL_AD_STATE.eIdle;                   // 回空闲相，不滞留 / Back to idle, never parked
        END_IF
ELSE
    (* 迁移⑭：非法枚举兜底（R6），码位赋值与锁存 3 行内配对（R45） *)
    IF NOT _bFaultLatch THEN
        _iErrLatch   := 99;                                        // 故障级：非法状态枚举值 / Fault: illegal state enum value
        _bFaultLatch := TRUE;                                      // 置故障锁存 / Latch the fault
    END_IF
END_CASE

(* —— 段 5：降载步单点执行（每触发一次只乘一次，禁在 CASE 分支内重复乘） —— *)
IF _bStepReq THEN
    // 量纲: (m3/h)*(1 - 无量纲折比) = m3/h 新限值
    _rFeedLimit := _rFeedLimit * (1.0 - _rStepRatio);              // 一步降载 [m3/h] / One derate step [m3/h]
    IF _rFeedLimit < _rFloorM3h THEN
        _rFeedLimit := _rFloorM3h;                                 // 下限 20% 饱和（禁降为零）/ Saturate at the twenty percent floor, never at zero
    END_IF
    IF _rFeedLimit > _rFeedMax THEN
        _rFeedLimit := _rFeedMax;                                  // 上限兜底（参数抖动时不越界）/ Upper bound guard against parameter jitter
    END_IF
END_IF
IF _bStepOutDom AND (NOT _bFaultLatch) AND (_eState <> E_DL_AD_STATE.eIdle) THEN
    _iInfoCode := 43;                                              // 信息级：步长越域已回默认（不静默）/ Info: the step was out of domain and fell back, never silent
END_IF

(* —— 段 6：相位无关故障判据 + 故障锁存 + 段尾迁相 + 撤使能降级（R191 已声明） —— *)
IF (_eState <> E_DL_AD_STATE.eIdle) AND (NOT _bFaultLatch) THEN
    IF NOT _bRatioOk THEN
        _iErrTmp   := 45;                                          // 故障级：运行中碱度丢失（除零闸）/ Fault: alkalinity lost while running
        _bFaultReq := TRUE;                                        // 请求本次锁存 / Request the latch in this scan
    ELSIF (ABS(rVfaMgL) > DL_ADC_FIN) OR (ABS(rGasM3h) > DL_ADC_FIN) OR (ABS(rFeedM3h) > DL_ADC_FIN) THEN
        _iErrTmp   := 46;                                          // 故障级：运行中入参变非有限 / Fault: an input became non-finite while running
        _bFaultReq := TRUE;                                        // 请求本次锁存 / Request the latch in this scan
    END_IF
END_IF
IF _bFaultReq AND (NOT _bFaultLatch) THEN
    _iErrLatch   := _iErrTmp;                                      // 锁存当拍首因 / Latch the first cause of this scan
    _bFaultLatch := TRUE;                                          // 置故障锁存 / Latch the fault
END_IF
IF _bFaultLatch AND (_eState <> E_DL_AD_STATE.eFault) THEN
    _eState := E_DL_AD_STATE.eFault;                               // 锁存即迁相（段尾统一执行）/ The latch forces the fault phase at the tail
END_IF
IF (NOT bEnable) AND (NOT _bFaultLatch) AND (_eState <> E_DL_AD_STATE.eIdle) THEN
    _rFeedLimit := _rFeedMax;                                      // 撤使能：限值复位（流量归零由段 7 执行）/ Disable: the limit is reset, the flow is zeroed at segment 7
    _iInfoCode  := 0;                                              // 撤使能：清信息码 / Disable: info code cleared
    _eState     := E_DL_AD_STATE.eIdle;                            // 撤使能：回空闲相 / Disable: back to idle
END_IF

(* —— 段 7：统一出口（0~10 级显式映射 + 单点输出，eFault 内流量归零） —— *)
IF (_rFeedMax > DL_ADC_EPS) THEN
    // 量纲: (m3/h)/(m3/h)*(%) = % 负荷百分比
    _rLoadPct := (_rFeedLimit / _rFeedMax) * DL_ADC_PCT_BASE;      // 限值占上限百分比 [%] / Limit as a percentage of the maximum [%]
ELSE
    _rLoadPct := 0.0;                                              // 分母闸：上限无效则百分比出零 / Denominator guard: zero percentage when the maximum is invalid
END_IF
IF _rLoadPct >= 95.0 THEN
    _iLevel := 10;                                                 // 95% 以上：满级 / Ninety-five percent and above is the top level
ELSIF _rLoadPct >= 85.0 THEN
    _iLevel := 9;                                                  // 85~95%：9 级 / Level nine
ELSIF _rLoadPct >= 75.0 THEN
    _iLevel := 8;                                                  // 75~85%：8 级 / Level eight
ELSIF _rLoadPct >= 65.0 THEN
    _iLevel := 7;                                                  // 65~75%：7 级 / Level seven
ELSIF _rLoadPct >= 55.0 THEN
    _iLevel := 6;                                                  // 55~65%：6 级 / Level six
ELSIF _rLoadPct >= 45.0 THEN
    _iLevel := 5;                                                  // 45~55%：5 级 / Level five
ELSIF _rLoadPct >= 35.0 THEN
    _iLevel := 4;                                                  // 35~45%：4 级 / Level four
ELSIF _rLoadPct >= 25.0 THEN
    _iLevel := 3;                                                  // 25~35%：3 级 / Level three
ELSIF _rLoadPct >= 15.0 THEN
    _iLevel := 2;                                                  // 15~25%：2 级 / Level two
ELSIF _rLoadPct >= 5.0 THEN
    _iLevel := 1;                                                  // 5~15%：1 级 / Level one
ELSE
    _iLevel := 0;                                                  // 5% 以下：0 级 / Below five percent is level zero
END_IF
IF _iLevel > DL_ADC_LEVEL_MAX THEN
    _iLevel := DL_ADC_LEVEL_MAX;                                   // 等级上限兜底（防御性冗余，禁越 10 级）/ Defensive redundancy, never above ten
END_IF
IF _bFaultLatch OR (_eState = E_DL_AD_STATE.eIdle) THEN
    rFeedOutM3h := 0.0;                                            // 故障相与空闲相：流量归零 / Fault and idle force the flow to zero
    bFeedOn     := FALSE;                                          // 故障相与空闲相：运行位撤销 / Fault and idle withdraw the run bit
    iLoadLevel  := 0;                                              // 故障相与空闲相：0 级 / Fault and idle report level zero
ELSE
    IF _rFeedCl < _rFeedLimit THEN
        rFeedOutM3h := _rFeedCl;                                   // 实测小于限值：跟随实测 / The measurement is below the limit, follow it
    ELSE
        rFeedOutM3h := _rFeedLimit;                                // 实测超限：按限值削顶 / The measurement exceeds the limit, cap at the limit
    END_IF
    bFeedOn    := rFeedOutM3h > DL_ADC_EPS;                        // 正流量才置运行位 / The run bit is set only for a positive flow
    iLoadLevel := _iLevel;                                         // 负荷等级映射 / Load level mapping
END_IF
IF _bFaultLatch THEN
    iErrCode := _iErrLatch;                                        // 故障期回放锁存码 / Replay the latched code during fault
ELSE
    iErrCode := _iInfoCode;                                        // 非故障期输出信息码（41/43/44/47）/ Info codes outside fault
END_IF
IF _eState = E_DL_AD_STATE.eIdle THEN
    sMsg := 'IDLE';                                                // 空闲 / Idle
ELSIF _eState = E_DL_AD_STATE.eNormal THEN
    sMsg := 'NORMAL';                                              // 正常 / Normal
ELSIF _eState = E_DL_AD_STATE.eWatch THEN
    sMsg := 'WATCH';                                               // 关注 / Watch
ELSIF _eState = E_DL_AD_STATE.eDerate THEN
    sMsg := 'DERATE';                                              // 降载 / Derating
ELSIF _eState = E_DL_AD_STATE.eRecover THEN
    sMsg := 'RECOVER';                                             // 回升 / Recovering
ELSE
    sMsg := 'FAULT';                                               // 故障 / Fault
END_IF
END_FUNCTION_BLOCK
