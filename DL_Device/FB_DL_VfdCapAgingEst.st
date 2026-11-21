(*
  ==================================================================
  组件名 Component  : FB_DL_VfdCapAgingEst
  分类   Category   : DL_Device
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0003_0725（故障级）｜ 16#0003_0726（信息级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : 母线电容老化趋势估计：纹波率实测值相对投运基线的长期比值监视
                      （电解电容容值衰减 → 纹波率单调爬升的运维预警）。
  开源溯源 Origin    : 公开公式 clean-room，参考公开电力电子运维工程口径的电解电容
                      纹波率基线比值判据（分类与公式借鉴，零代码复制），本件实现、
                      闸门与码位 100% 自有。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术运算符；纹波率基线比值公开工程定义
  平台   Platform   : 纯 IEC 61131-3（四则 / 比较），三平台通用
  依赖   Depends    : 仅 Standard.library（无库调用、无定时器）
  分工声明 Split     : FB_DL_VfdDcBusRipple（瞬时纹波，R63 返修件）/ FB_DL_Brake
                      ResistorThermal（制动热）/ FB_DL_VfdThermalDerate（降额策略）
                      互引；本件为长期老化趋势，MANUAL 写明「瞬时监视与趋势估计
                      分层使用」（R216）。本件不实例依赖 VfdDcBusRipple，只收数值。
  归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 组态闸结构早退（族② 判据，R1 同族教训出厂即正确）：
                         fRippleBasePct ≤ 0 或非有限（除子直穿防线）、fAgingLimPct ≤ 0
                         或非有限、fHystPct < 0 或非有限 → 组态码 0725 + 三件套 +
                         RETURN（除法段结构性不可达）；
                      二 fRipplePct 非有限或 < 0 → 该拍拒绝：比值冻结、迟滞态保持、
                         bValid = FALSE（丢弃 + 局部信息级计数，不外显 R62-D7 口径，
                         不影响趋势判据，禁污染物进除法）；
                      三 判据（带迟滞，两方向分别定义 R146）：fRippleRatioPct >
                         100 + fAgingLimPct 触发 bAgingHigh，回落 <
                         100 + fAgingLimPct×(1−fHystPct/100) 复原；
                      四 除子 fRippleBasePct > 0 已由段 2 结构早退证明（禁除零）；
                      五 负载可比性声明（写死）：本件假设同负载段比较，负载段切换时
                         调用方应 bEnable 短暂断开复位迟滞态——本件不自动判负载
                         （保持单一职责）；
                      六 bEnable = FALSE 的语义写死（FB33-4 声明行）：bAgingHigh 复位
                         + 比值冻结（运维趋势件，不丢历史）；
                      七 首拍 _bInit 全量初始化；无状态机（CASE N/A，R6 标注）；无
                         定时器 / 无边沿实例（段 0 无刷新对象）；无全局、无外部变量、
                         无物理地址、无指针。
  错误码 Codes      :
    16#0003_0725【故障级】组态非法（基线 ≤ 0 / 非有限；劣化阈值 ≤ 0 / 非有限；
                         迟滞 < 0 / 非有限）
    16#0003_0726【信息级】老化超限（bAgingHigh = TRUE，基线比超过 100 + 劣化阈值）
  码位反证 Note     :
    仅两码：0725 组态族为即刻判（与测点无关），0726 需比值已建立，处置人不同
    （组态工程师 / 运维），可由场景还原（R90）；fRipplePct 非有限拒绝拍不占码
    （bValid = FALSE 已足够表达，无额外处置信息，R90 不加码）。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 fRipplePct = fRippleBasePct → 比值 100%、bAgingHigh = FALSE
    V2 比值爬到 151%（限 150%）→ 触发；V3 回落 148%（迟滞未满足）→ 保持触发
    V4 回落 142% → 复原；V5 fRippleBasePct = 0 → 组态早退（R1 同族回归向量）
    V6 fRippleBasePct = NaN → 组态早退；V7 fRipplePct = NaN → 该拍拒绝不触发
    V8 fAgingLimPct = 0 → 组态早退（判据永假）
  修订记录 Revision  :
    2026-11-21  v1.0.0  R63 首版（批 4 · 序号 12）
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_VfdCapAgingEst
VAR_INPUT
    bEnable       : BOOL := TRUE;  // 使能，FALSE 时判据复位 + 比值冻结（边界六）/ the enable, false resets the criterion and freezes the ratio
    fRipplePct    : LREAL := 0.0;  // 纹波率实测 [%]，由 FB_DL_VfdDcBusRipple 出口注入 / the measured ripple rate injected from the ripple monitor
    fRippleBasePct: LREAL := 5.0;  // 投运基线纹波率 [%]，须 > 0（除子）/ the commissioned baseline ripple rate, must be positive
    fAgingLimPct  : LREAL := 50.0; // 劣化阈值 [−]，相对基线百分比（50 即 150% 判劣化）/ the aging threshold relative to the baseline
    fHystPct      : LREAL := 5.0;  // 判据迟滞 [%]，须 ≥ 0 / the criterion hysteresis in percent, non negative
END_VAR
VAR_OUTPUT
    fRippleRatioPct : LREAL := 0.0;           // 基线比 fRipplePct/fRippleBasePct×100 [%] / the baseline ratio in percent
    bAgingHigh      : BOOL := FALSE;          // 老化超限判据（带迟滞）[-] / the aging high criterion with hysteresis
    bValid          : BOOL := FALSE;          // 判据可用 [-] / the criterion is usable
    eErr            : UDINT := 16#0000_0000;  // 错误码，0 = 正常 / the error code, zero is ok
    bError          : BOOL := FALSE;          // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    _bInit      : BOOL := FALSE;   // 首拍初始化标志（R310 / FB50-2）/ the first scan flag
    _fRatio     : LREAL := 0.0;    // 基线比工作副本 [%] / the working baseline ratio
    _fRatioLast : LREAL := 0.0;    // 最近有效基线比（冻结源）[%] / the last valid ratio used while frozen
    _fTripLim   : LREAL := 0.0;    // 置警阈值 = 100 + 劣化阈值 [%] / the trip threshold
    _fReleLim   : LREAL := 0.0;    // 复原阈值 = 100 + 劣化阈值×(1−h) [%] / the release threshold
    _bAgingL    : BOOL := FALSE;   // 老化迟滞状态（跨拍保持）/ the aging hysteresis state
    _bFinBase   : BOOL := FALSE;   // 基线有限闸结果（逐拍重算）/ the baseline finiteness gate result
    _bFinLim    : BOOL := FALSE;   // 劣化阈值有限闸结果（逐拍重算）/ the threshold finiteness gate result
    _bFinHyst   : BOOL := FALSE;   // 迟滞有限闸结果（逐拍重算）/ the hysteresis finiteness gate result
    _bFinMeas   : BOOL := FALSE;   // 实测值有限闸结果（逐拍重算）/ the measurement finiteness gate result
    _bCfgBad    : BOOL := FALSE;   // 组态非法标记（逐拍重算）/ the configuration fault flag
    _nRejectCnt : DINT := 0;       // 实测值拒绝计数 [个]（仅局部留档，不外显，R62-D7 口径）/ the rejected measurement count, local only and never exposed
VAR CONSTANT
    DL_VCA_PCT   : LREAL := 100.0; // 百分比换算与基线常量 [%] / the percentage scaling and the baseline constant
    DL_VCA_ZERO  : LREAL := 0.0;   // 实数零常量 [%] / the real zero constant
    DL_VCA_ONEI  : DINT := 1;      // 整型一常量 [个] / the integer one constant
    DL_VCA_ZEROI : DINT := 0;      // 整型零常量 [个] / the integer zero constant
END_VAR

// 段 0｜本件无定时器与边沿实例（纯趋势监视器，R6 标注 N/A），无刷新对象 / segment 0, no timers and no edge instances exist here

// 段 1｜首拍初始化（FB50-2）/ segment 1, the first scan init
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _bAgingL := FALSE; // 迟滞态显式清零 / clear the hysteresis state explicitly
    _fRatioLast := DL_VCA_PCT; // 最近有效基线比显式预置 100%（首次有效计算前的安全占位）/ preset the last valid ratio to one hundred percent
    _nRejectCnt := DL_VCA_ZEROI; // 拒绝计数显式清零 [个] / clear the reject count explicitly
END_IF

// 段 2｜组态域闸结构早退（边界一，族② 判据：除子直穿防线先行，R272 全量点名）/ segment 2, the structural early exit on an illegal configuration
_bFinBase := (fRippleBasePct = fRippleBasePct) AND ((fRippleBasePct - fRippleBasePct) = (fRippleBasePct - fRippleBasePct)); // 基线有限 / the baseline is finite
_bFinLim := (fAgingLimPct = fAgingLimPct) AND ((fAgingLimPct - fAgingLimPct) = (fAgingLimPct - fAgingLimPct)); // 劣化阈值有限 / the threshold is finite
_bFinHyst := (fHystPct = fHystPct) AND ((fHystPct - fHystPct) = (fHystPct - fHystPct)); // 迟滞有限 / the hysteresis is finite
_bCfgBad := (NOT _bFinBase) OR (fRippleBasePct <= DL_VCA_ZERO)
         OR (NOT _bFinLim) OR (fAgingLimPct <= DL_VCA_ZERO)
         OR (NOT _bFinHyst) OR (fHystPct < DL_VCA_ZERO); // 组态非法 / an illegal configuration
IF _bCfgBad THEN // 组态非法：结构早退（出口三件套 + RETURN，除法段不可达）/ an illegal configuration exits structurally
    fRippleRatioPct := _fRatioLast; // 比值冻结最近有效值 [%]（禁自赋值出口，R261）/ freeze the last valid ratio
    bAgingHigh := FALSE; // 判据复位 / the criterion resets
    bValid := FALSE; // 判据不可用 / the criterion is not usable
    eErr := 16#0003_0725; // 故障级：组态非法 / fault grade, an illegal configuration
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 结构早退 / the structural early exit
END_IF

// 段 3｜失能分支：判据复位 + 比值冻结（边界六声明行）/ segment 3, the disabled branch
IF NOT bEnable THEN // 失能 / disabled
    fRippleRatioPct := _fRatioLast; // 比值冻结最近有效值 [%]（运维趋势件，不丢历史）/ freeze the last valid ratio
    bAgingHigh := FALSE; // 判据复位 / the criterion resets
    bValid := FALSE; // 失能即不可用 / the criterion is not usable while disabled
    bError := FALSE; // 失能不是故障 / a disabled device is not a fault
    eErr := 16#0000_0000; // 失能不发码 / no code is emitted while disabled
    RETURN; // 早退 / early return
END_IF

// 段 4｜实测值拒绝闸（边界二：非有限或负值拒绝，禁污染物进除法）/ segment 4, the measurement rejection gate
_bFinMeas := (fRipplePct = fRipplePct) AND ((fRipplePct - fRipplePct) = (fRipplePct - fRipplePct)); // 实测值有限 / the measurement is finite
IF (NOT _bFinMeas) OR (fRipplePct < DL_VCA_ZERO) THEN // 实测坏或负值 / a broken or a negative measurement
    _nRejectCnt := _nRejectCnt + DL_VCA_ONEI; // 拒绝计数推进（仅局部留档，不外显）/ advance the reject count, local only
    fRippleRatioPct := _fRatioLast; // 比值冻结 [%] / freeze the ratio
    bAgingHigh := _bAgingL; // 迟滞态保持（拒绝拍不影响趋势判据）/ keep the hysteresis state
    bValid := FALSE; // 该拍不可用 / the scan is not usable
    eErr := 16#0000_0000; // 拒绝拍不发码（bValid = FALSE 已足够表达，R90 不加码）/ no code for a rejected scan
    bError := FALSE; // 无故障 / no fault
    RETURN; // 早退，除法不可达 / early return, the division is unreachable
END_IF

// 段 5｜基线比计算（除子 fRippleBasePct > 0 已由段 2 证明，禁除零）/ segment 5, the baseline ratio computation
_fRatio := (fRipplePct / fRippleBasePct) * DL_VCA_PCT; // 基线比 [%]，除子已证 > 0 / the baseline ratio with the proven divisor
_fRatioLast := _fRatio; // 最近有效基线比快照 [%] / snapshot the valid ratio
_fTripLim := DL_VCA_PCT + fAgingLimPct; // 置警阈值 [%] / the trip threshold
_fReleLim := DL_VCA_PCT + (fAgingLimPct * ((DL_VCA_PCT - fHystPct) / DL_VCA_PCT)); // 复原阈值 [%] / the release threshold

// 段 6｜老化判据迟滞（边界三，两方向分别定义，R146）/ segment 6, the aging hysteresis
IF NOT _bAgingL THEN // 未报警态 / the released state
    IF _fRatio > _fTripLim THEN // 超过置警阈值 / above the trip threshold
        _bAgingL := TRUE; // 置迟滞状态 / set the hysteresis state
    END_IF
ELSE // 已报警态 / the tripped state
    IF _fRatio < _fReleLim THEN // 回落低于复原阈值 / below the release threshold
        _bAgingL := FALSE; // 复原 / release
    END_IF
END_IF

// 段 7｜统一出口（迟滞状态派生，R187 / FB51-8）/ segment 7, the unified outlet
fRippleRatioPct := _fRatio; // 基线比出口 [%] / the ratio outlet
bAgingHigh := _bAgingL; // 判据出口 / the criterion outlet
bValid := TRUE; // 判据可用 / the criterion is usable
bError := FALSE; // 无故障 / no fault
IF _bAgingL THEN // 老化超限（信息级）/ the aging is high, informational
    eErr := 16#0003_0726; // 信息级：基线比超过 100 + 劣化阈值 / informational, the ratio exceeds the aging threshold
ELSE // 无事件 / no event
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
