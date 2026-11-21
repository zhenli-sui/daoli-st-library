(*
  FB_DL_RfReflectedMonitor  —  射频正反功率比监视与匹配器联动告警 / RF forward-reflected power ratio monitor
  分类 Category : DL_Process
  码位 Code     : 16#06_0_B3
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-measurement — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : clean-room 实现，射频反射比监视公开语义借鉴，未复制任何源码行（RESUME 承接 R36 §4 #18 规格）
                  （仅监视件：本件只做比值判级与请求置位，不闭环调谐——闭环调谐由匹配器本体承载，此语义为规格强制）
  功能 Function : 1) 反射比 = 反射/正向 × 100，两级阈值（Warn/Fault）带迟滞与去抖；
                  2) bMatcherRequest 在越 Warn 阈时置位并持续 tMatcherReqHold（仅请求，不闭环）；
                  3) 比值 > 100%（反射 > 正向）属异常物理值，钳到 100 并置码。
  边界 Boundary : ① fPowerFwdW <= 0 时比值不计算（防除零），输出 0 并置「无正向功率」信息码；
                  ② 组态非法（Warn >= Fault / 阈值 <= 0 / 去抖 <= 0）判组态错；
                  ③ 信号非有限（NaN 用 x<>x 自反）判无效置码，判级维持安全缺省；
                  ④ bReflFault 解除式自证：比值回落到 Warn 阈以下 AND bReset（两引脚可满足）；
                  ⑤ 本件无状态机 ENUM/CASE（监视件），判级为去抖+锁存量承载，每拍出口单点映射。
  依赖 Depends  : 仅 Standard.library（TON/TOF/ABS）；语义对齐 FB_DL_SignalStatistics / FB_DL_ToleranceWindow（已注册，不实例化）
  码表 Error codes（本件格 06_0_B3，子码步进 +0x100）:
    16#0006_01B3 信息级：无正向功率，比值不计算
    16#0006_02B3 故障级：组态非法（阈值域倒置 / 去抖 <= 0），每拍重申
    16#0006_03B3 信息级：反射功率超正向（物理异常），比值钳 100
    16#0006_04B3 信息级：匹配器请求挂起（仅请求不闭环）
    16#0006_05B3 故障级：反射比越故障阈（去抖确认，锁存至复位 + 回落）

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

FUNCTION_BLOCK FB_DL_RfReflectedMonitor
VAR_INPUT
    fPowerFwdW       : REAL := 100.0;   // 正向功率 [W] / Forward power
    fPowerReflW      : REAL := 0.0;     // 反射功率 [W] / Reflected power
    fReflRatioWarnPct: REAL := 10.0;    // 反射比预警阈 [%] / Reflected ratio warn threshold
    fReflRatioFaultPct: REAL := 20.0;   // 反射比故障阈 [%] / Reflected ratio fault threshold
    tRatioDebounce   : TIME := T#1S;    // 判级去抖 [ms]，域 > 0 / Ratio debounce
    tMatcherReqHold  : TIME := T#30S;   // 匹配器请求保持 [ms] / Matcher request hold
    bReset           : BOOL := FALSE;   // 复位（故障锁存解除路径之一）/ Reset
END_VAR
VAR_OUTPUT
    fReflRatioPct    : REAL;            // 反射比 [%] / Reflected ratio
    bReflWarn        : BOOL;            // 预警级判级 / Warn verdict
    bReflFault       : BOOL;            // 故障级判级锁存 / Fault verdict latch
    bMatcherRequest  : BOOL;            // 匹配器请求（仅请求不闭环）/ Matcher request, monitor-only
    nErrId           : UDINT;           // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonWarnDly  : TON;                   // 预警级去抖计时，段 0 无条件刷新 / Warn debounce timer
    tonFaultDly : TON;                   // 故障级去抖计时，段 0 无条件刷新 / Fault debounce timer
    tofReqHold  : TOF;                   // 匹配器请求保持（TOF 断输入延时），段 0 无条件刷新 / Request hold, falling-delay
    tonFaultWch : TON;                   // 故障观察窗，自复位 / Fault watch window, self-resetting
    rtReset     : R_TRIG;                // 复位上升沿 / Reset rising edge
    _rRatio     : REAL;                  // 比值暂存 [%] / Ratio scratch
    _bFwdOk     : BOOL;                  // 正向功率有效标志 / Forward power validity flag
    _bFin       : BOOL;                  // 非有限筛查标志 / Non-finite screening flag
    _bFaultL    : BOOL;                  // 故障级锁存保持量 / Fault verdict latch
    _bCfgBad    : BOOL;                  // 组态非法聚合 / Configuration invalid aggregate
    _uInfo      : UDINT;                 // 信息码，每拍重算 / Info code
END_VAR
VAR CONSTANT
    DL_WATCH_PT : TIME := T#2S;   // 故障观察窗 [ms]，自复位 / Fault watch window
END_VAR

(* —— 段 0：定时器与边沿无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);                                          // 复位上升沿，每拍必调
tonFaultWch(IN := (NOT tonFaultWch.Q), PT := DL_WATCH_PT);       // 观察窗自复位（表达式入参）
tonWarnDly(IN := (_rRatio > fReflRatioWarnPct) AND (NOT _bCfgBad), PT := tRatioDebounce);   // 预警去抖（表达式入参）
tonFaultDly(IN := (_rRatio > fReflRatioFaultPct) AND (NOT _bCfgBad), PT := tRatioDebounce); // 故障去抖（表达式入参）
tofReqHold(IN := (_rRatio > fReflRatioWarnPct) AND (NOT _bCfgBad) AND (NOT _bFaultL),
           PT := tMatcherReqHold);                               // 请求保持（TOF，表达式入参）

(* —— 段 1：单拍量预清零（锁存量 _bFaultL 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;              // 信息码每拍重算
bReflWarn := FALSE;                  // 预警出口缺省 FALSE（段 6 单点置位）
_bCfgBad := FALSE;                   // 组态非法预清零
nErrId := 16#0000_0000;              // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fReflRatioWarnPct <= 0.0) OR (fReflRatioFaultPct <= fReflRatioWarnPct)
   OR (TIME_TO_DINT(tRatioDebounce) <= 0) THEN
    _bCfgBad := TRUE;                // 阈值域倒置或去抖非法
    nErrId := 16#0006_02B3;          // 故障级：组态非法（每拍重申）
END_IF

(* —— 段 3：信号有效性与比值计算（防除零 + 非有限筛查） —— *)
_bFin := (fPowerFwdW = fPowerFwdW) AND (fPowerReflW = fPowerReflW)
         AND (ABS(fPowerFwdW) < 1.0E15) AND (ABS(fPowerReflW) < 1.0E15);   // NaN 用 x<>x 自反
IF (NOT _bFin) OR (fPowerFwdW <= 0.0) THEN
    _bFwdOk := FALSE;                // 正向功率无效：比值不计算（防除零，规格强制）
    _rRatio := 0.0;                  // 输出 0
    IF fPowerFwdW <= 0.0 THEN
        _uInfo := 16#0006_01B3;      // 信息级：无正向功率
    END_IF
ELSE
    _bFwdOk := TRUE;                 // 分母有效
    IF fPowerReflW > fPowerFwdW THEN
        _rRatio := 100.0;            // 反射 > 正向：异常物理值钳 100（规格强制）
        _uInfo := 16#0006_03B3;      // 信息级：物理异常已钳制
    ELSE
        _rRatio := fPowerReflW * 100.0 / fPowerFwdW;   // 反射比 [%]（分母已闸 > 0）
    END_IF
END_IF
fReflRatioPct := _rRatio;            // 比值出口

(* —— 段 4：判级与锁存（故障级锁存至复位 + 回落，解除式自证） —— *)
IF _bFwdOk AND (NOT _bCfgBad) THEN
    IF tonFaultDly.Q THEN
        _bFaultL := TRUE;            // 故障级锁存（去抖确认）
    END_IF
    IF _bFaultL THEN
        IF (_rRatio <= fReflRatioWarnPct) AND rtReset.Q THEN
            _bFaultL := FALSE;       // 解除式自证：比值回落至 Warn 阈以下 AND bReset
        END_IF
    END_IF
END_IF

(* —— 段 5：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
bReflFault := _bFaultL;              // 故障级出口 = 锁存量（置位同拍不被抹）
bReflWarn := tonWarnDly.Q AND (NOT _bFaultL);   // 预警出口（去抖确认，故障级优先）
bMatcherRequest := tofReqHold.Q AND (NOT _bCfgBad);   // 匹配器请求（仅请求不闭环，TOF 保持）
IF bMatcherRequest THEN
    _uInfo := 16#0006_04B3;          // 信息级：请求挂起
END_IF
IF _bCfgBad THEN
    bReflWarn := FALSE;              // 组态错判级出口撤销（安全侧）
    bMatcherRequest := FALSE;
    bReflFault := FALSE;
END_IF
IF (NOT _bCfgBad) THEN
    IF bReflFault THEN
        nErrId := 16#0006_05B3;      // 故障级码回放（锁存）
    ELSIF _uInfo <> 16#0000_0000 THEN
        nErrId := _uInfo;            // 信息码
    END_IF
END_IF

END_FUNCTION_BLOCK
