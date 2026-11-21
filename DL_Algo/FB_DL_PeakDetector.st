(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PeakDetector
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS / LIMIT / MIN / MAX /
 *                         R_TRIG / TIME_TO_REAL），零厂商方言
 * 分类     (Category)   : 算法功能块（Function Block，时域极值跟踪族）
 * 功能描述 (Function)   : 峰值 / 谷值检测与保持。输入信号上升即刷新峰值；可选
 *                         按衰减率做时间线性回落（模拟指针式表头回落 / 峰值
 *                         滚动窗口）；可同时跟踪谷值；提供峰值变化率、峰值更新
 *                         单拍事件、谷值更新单拍事件、阈值超限电平位与峰值更新
 *                         计数（冲击次数统计）。
 *                         典型用途：液压冲击压力峰值、注塑保压峰值、振动监测
 *                         加速度峰值、称重配料瞬时超调、焊接电流峰值监控。
 * 职责边界 (Scope)     : 本块输出"过程极值"；窗口均值 / 方差 / 极差等统计量
 *                         由信号统计类组件承担，两者严格分离，不得互相替代。
 * 无状态机声明 (No FSM) : 本块为连续运算型（逐拍顺序数值运算），无顺序状态
 *                         步序，故不设状态枚举、无 CASE 分支；与库内连续运算型
 *                         先例 FB_DL_LowPassFilter 同类（红线 R6 的 ENUM + CASE
 *                         + ELSE 仅约束"存在顺序状态"的 POU）。泳道 D 契约
 *                         明确规定"无新增枚举"，故本文件不引入任何 DUT。
 *                         但首值语义仍需初始化：首扫把极值设为当前信号，采用
 *                         规格明文的首扫判据（本块无跟踪引脚，公共模板中与
 *                         跟踪相关的判据项不适用）。
 * 开源溯源 (Origin)     : 原创实现（参考西门子 LGF Math 组参数域）。来源标签
 *                         lgf-math / lgf-measurement（RAW_NOTES_R8 条目 S-11：
 *                         公开手册呈现的"峰值 / 谷值 / 平均 / 累计"统计功能
 *                         分类与参数域划分），仅借鉴功能分类与参数域；峰值
 *                         衰减模型、双阈值语义、单拍事件、计数与防御体系按本库
 *                         红线 clean-room 独立编写，未复制任何源码行。
 *                         许可证说明：LGF 为闭源免费库，其公开手册仅作功能
 *                         分类与参数域参考，本文件为独立实现，无代码复制、
 *                         无许可证传染。
 * 故障码 (Codes)        : 段位 16#0002_xxxx（已核对 DL_Algo 台账：01xx 至 18xx
 *                         为既有族段，19xx 为本轮新建"极值跟踪族"，无冲突）。
 *                         全部为【信息级】，只进 uErrorId，不置 bError：
 *                         0002_1901 输入非有限值已保持上次有效极值、
 *                         0002_1902 阈值非有限已禁用阈值事件、
 *                         0002_1903 衰减率非法按零或绝对值处理、
 *                         0002_1904 采样周期越界已钳位。
 * 公约遵循 (Convention) : 0.2 本块全部码为信息级，bError 作为显式排除信息级码
 *                         的派生式恒为 FALSE（保留引脚供上层统一接线，不参与
 *                         报警链）。0.7 无数值锁存型故障码，信息码瞬时型每拍
 *                         重算。0.9 输出默认值在第一条防御分支之前赋值，任何
 *                         早退路径输出确定。0.14 浮点一律容差比较、除法先判零。
 *                         0.16 采样上限、有限值幅值上限、浮点容差全部常量化。
 * 规格偏离 (R11 Dev.)   : D1 首扫判据按规格明文采用"未初始化即跟踪"的单项
 *                         形式（本块无 bTrack 引脚，公共模板的跟踪项不适用），
 *                         首扫与 bReset 共用同一复位赋值块，无重复代码。
 *                         D2 bError 恒 FALSE（全信息级，见公约 0.2），规格 OUT
 *                         列该引脚保留为上层统一接线占位，不构成功能缺失。
 * 验收向量 (Acceptance) :
 *   V1  信号 0 → 10 → 5（无衰减）→ fPeak=10、fValley=0、uPeakCount=1
 *   V2  无衰减且信号回落至 5 后连续多拍 → fPeak 保持 10 不回落
 *   V3  fDecayRate=2.0、tSample=T#100MS、静置 1 秒（10 拍）→ fPeak 由 10 降至 8
 *   V4  衰减后信号回升至 8（≤ 当前峰值）→ fPeak 不反超、保持 8，衰减段钳制生效
 *   V5  bThresholdEnable=TRUE、fThreshold=9、fPeak=10 → bOverThreshold=TRUE
 *       （电平型每拍重算，信号回落后随 fPeak 变化重算）
 *   V6  bReset 上升沿 → fPeak=fValley=当前信号、uPeakCount=0、双事件清零
 *   V7  fSignal 为非数（自反比较为真）→ 极值保持、本拍不更新、uErrorId=16#0002_1901
 *   V8  tSample=T#0S → 衰减步长为零、fPeakRate=0，极值只随信号上升而更新
 * 已知限制 (Limits)     : 1 衰减为时间线性回落（非常数时间衰减），衰减速率单位为
 *                         工程单位每秒，适用于缓变过程；指数回落需上层另建模型。
 *                         2 峰值变化率在衰减段为负值（峰值在下降），属正常语义。
 *                         3 输出与输入同量纲，本块不做任何单位换算与标定。
 *                         4 信息码单寄存器，同拍多条件时按固定书写顺序后者覆盖
 *                         前者（采样越界 > 输入非有限 > 衰减非法 > 阈值非法），
 *                         判读以 uErrorId 当拍值为准。
 * 红线自检 (Redline)    : 零全局变量表访问 ✓｜零外部变量声明 ✓｜零物理地址直写 ✓
 *                         纯 IEC 61131-3 ✓｜防除零 + 防越界 + 浮点容差 + 防非数穿透 ✓
 *                         全变量中英双语同行注释 ✓｜单拍事件预清零范式（R25）✓
 *                         R_TRIG 主体最前部无条件刷新 ✓
 *                         FUNCTION_BLOCK 与 END_FUNCTION_BLOCK 成对 ✓
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 08 · 泳道 D · DL_Algo 极值跟踪族 19xx）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_PeakDetector
VAR_INPUT
    bEnable          : BOOL := FALSE;              // 使能（Enable），FALSE=极值冻结不更新、事件清零 / Enable, FALSE freezes extrema and clears events
    bReset           : BOOL := FALSE;              // 复位（Reset），上升沿把极值复位到当前信号并清零计数 / Reset to current signal on rising edge
    fSignal          : REAL := 0.0;                // 输入信号（Input signal）[工程单位]，非有限值时保持上次有效值 / Input signal [EU], non-finite holds the last valid value
    tSample          : TIME := T#10MS;             // 采样周期（Sample period）[ms]，用于衰减与变化率换算，T#0S=不衰减 / Sample period [ms], T#0S disables decay
    fDecayRate       : REAL := 0.0;                // 峰值衰减率（Decay rate）[EU/s]，0=无限保持，负值取绝对值 / Peak decay rate [EU/s], 0 holds forever, negative uses ABS
    bDetectValley    : BOOL := TRUE;               // 谷值检测使能（Valley detection enable），FALSE 时 fValley 恒为 0 / Valley enable, FALSE keeps fValley at 0
    fThreshold       : REAL := 0.0;                // 事件阈值（Event threshold）[工程单位]，峰值达到即超限 / Event threshold [EU], reached by the peak
    bThresholdEnable : BOOL := FALSE;              // 阈值事件使能（Threshold event enable），FALSE 时超限位恒为假 / Threshold enable, FALSE keeps the flag low
END_VAR

VAR_OUTPUT
    fPeak            : REAL := 0.0;                // 峰值（Peak value）[工程单位]，只升不降（除衰减与复位）/ Peak value [EU], only rises except decay and reset
    fValley          : REAL := 0.0;                // 谷值（Valley value）[工程单位]，bDetectValley=FALSE 时恒为 0 / Valley value [EU], 0 when valley detection is disabled
    fPeakRate        : REAL := 0.0;                // 峰值变化率（Peak rate）[EU/s]，正值=仍在爬升 / Peak rate [EU/s], positive means still climbing
    bPeakEvent       : BOOL;                       // 峰值更新事件（Peak updated event），单拍脉冲 / Peak updated event, one-scan pulse
    bValleyEvent     : BOOL;                       // 谷值更新事件（Valley updated event），单拍脉冲 / Valley updated event, one-scan pulse
    bOverThreshold   : BOOL;                       // 峰值超阈值（Peak over threshold），电平型每拍重算 / Peak over threshold, level type recomputed each scan
    uPeakCount       : UDINT := 0;                 // 峰值更新次数（Peak update counter），可作冲击次数统计 / Peak update counter, usable as impact count
    bError           : BOOL;                       // 故障标志（Fault flag），本块全信息级故恒为 FALSE / Fault flag, always FALSE because all codes are info level
    uErrorId         : UDINT := 0;                 // 错误码（Error code），0=无错误，段位 16#0002_19xx / Error code, 0 = none, family 16#0002_19xx
END_VAR

VAR
    _bInit           : BOOL;                       // 首扫初始化完成标志（First-scan init done），初值 FALSE / First-scan init done flag, initial FALSE
    _bSigValid       : BOOL;                       // 本拍输入有效标志（Signal valid flag），非有限值为 FALSE / Signal valid flag, FALSE for non-finite input
    _fSigEff         : REAL;                       // 生效信号值（Effective signal），无效时等于上次有效值 / Effective signal, equals last valid value when invalid
    _fLastValid      : REAL;                       // 上次有效信号（Last valid signal）[工程单位] / Last valid signal [EU]
    _fDecayEff       : REAL;                       // 生效衰减率（Effective decay rate）[EU/s]，已取绝对值 / Effective decay rate [EU/s], absolute value applied
    _fDecayStep      : REAL;                       // 本拍衰减步长（Decay step this scan）[EU] / Decay step applied this scan [EU]
    _fDtSec          : REAL;                       // 采样周期秒值（Sampling period in seconds）[s] / Sampling period in seconds [s]
    _fPeakPrev       : REAL;                       // 上拍峰值（Previous peak）[工程单位]，用于变化率 / Previous peak [EU] used by the rate calculation
    _fThrEff         : REAL;                       // 生效阈值（Effective threshold）[工程单位] / Effective threshold [EU]
    _bThrEnEff       : BOOL;                       // 生效阈值使能（Effective threshold enable）/ Effective threshold enable
    _tSampleEff      : TIME;                       // 钳位后采样周期（Clamped sample period）[ms] / Clamped sample period [ms]
    _uInfoCode       : UDINT;                      // 本拍信息级码（Info code this scan），每拍重算 / Info code this scan, recomputed every scan
    _fbTrigReset     : R_TRIG;                     // 复位信号上升沿（Reset rising edge）/ Reset rising edge detector
END_VAR
VAR CONSTANT
    DL_PEAK_SAMPLE_MAX : TIME := T#10S;            // 采样周期上限（Sample period upper bound），超限钳位并置码 / Sample period upper clamp with info code
    DL_PEAK_INF_MAX    : REAL := 1.0E30;           // 有限值判定幅值上限（Finite-value magnitude bound）[EU] / Finite-value magnitude bound [EU]
    DL_PEAK_FLOAT_EPS  : REAL := 1.0E-6;           // 浮点容差（Float epsilon），替代判等 / Float epsilon replacing equality comparison
END_VAR

// ============================================================================
// 段 1｜单拍事件预清零与输出确定性默认值（R25 第一律：每拍预清零；
//       公约 0.9：默认值必须在第一条防御分支之前赋值）
//      One-scan event pre-clear plus deterministic output defaults
// ============================================================================
bPeakEvent     := FALSE;                              // 峰值事件预清零（Peak event pre-cleared）
bValleyEvent   := FALSE;                              // 谷值事件预清零（Valley event pre-cleared）
bOverThreshold := FALSE;                              // 超限位预清零（Threshold flag pre-cleared）
bError         := FALSE;                              // 本块全信息级，故障位恒 FALSE（All codes are info level）
uErrorId       := 0;                                  // 错误码预清零（Error code pre-cleared）
_uInfoCode     := 0;                                  // 信息码寄存预清零（Info register pre-cleared）

// ============================================================================
// 段 2｜边沿实例无条件周期刷新（公约 0.5：严禁置于 IF / CASE 分支内）
//      Unconditional per-cycle refresh of the reset edge instance
// ============================================================================
_fbTrigReset(CLK := bReset);

// ============================================================================
// 段 3｜采样周期域裁决与防越界（超限钳位，不中断扫描）
//      Sample period arbitration with upper clamp, scan never interrupted
// ============================================================================
_tSampleEff := tSample;                               // 先取原值（Take the raw value first）
IF tSample > DL_PEAK_SAMPLE_MAX THEN
    _tSampleEff := DL_PEAK_SAMPLE_MAX;                // 超上限钳位（Clamp to the upper bound）
    _uInfoCode  := 16#0002_1904;                      // 0002_1904 采样周期越界已钳位【信息级】/ Sample period clamped, info level
END_IF
IF _tSampleEff > T#0S THEN
    _fDtSec := TIME_TO_REAL(_tSampleEff) / 1000.0;    // 毫秒换算秒值（Convert milliseconds to seconds）
ELSE
    _fDtSec := 0.0;                                   // 零周期：不衰减且变化率置零（Zero period disables decay and rate）
END_IF

// ============================================================================
// 段 4｜输入非有限值防御（自反比较 + 幅值上限双检，防非数穿透）
//      Non-finite defense by self-comparison plus magnitude bound
// ============================================================================
_bSigValid := NOT ((fSignal <> fSignal) OR (ABS(fSignal) > DL_PEAK_INF_MAX));
IF _bSigValid THEN
    _fLastValid := fSignal;                           // 记录最近有效值（Record the last valid value）
ELSE
    IF _uInfoCode = 0 THEN
        _uInfoCode := 16#0002_1901;                   // 0002_1901 输入非有限值已保持【信息级】/ Non-finite input held, info level
    END_IF
END_IF
_fSigEff := _fLastValid;                              // 无效拍沿用上次有效值（Invalid scans reuse the last valid value）

// ============================================================================
// 段 5｜衰减率与阈值参数域裁决（非有限 / 负值 / 越界处理，均不中断扫描）
//      Decay rate and threshold arbitration, scan never interrupted
// ============================================================================
IF (fDecayRate <> fDecayRate) OR (ABS(fDecayRate) > DL_PEAK_INF_MAX) THEN
    _fDecayEff := 0.0;                                // 非有限衰减率按零处理（Non-finite decay treated as zero）
    IF _uInfoCode = 0 THEN
        _uInfoCode := 16#0002_1903;                   // 0002_1903 衰减率非法按零处理【信息级】/ Illegal decay rate, info level
    END_IF
ELSIF fDecayRate < 0.0 THEN
    _fDecayEff := ABS(fDecayRate);                    // 负值取绝对值（Negative value uses ABS）
    IF _uInfoCode = 0 THEN
        _uInfoCode := 16#0002_1903;                   // 0002_1903 衰减率非法取绝对值【信息级】/ Illegal decay rate, ABS applied, info level
    END_IF
ELSE
    _fDecayEff := fDecayRate;                         // 合法衰减率直通（Valid decay passes through）
END_IF

IF (fThreshold <> fThreshold) OR (ABS(fThreshold) > DL_PEAK_INF_MAX) THEN
    _bThrEnEff := FALSE;                              // 阈值失效等效（Threshold effectively disabled）
    _fThrEff   := 0.0;                                // 阈值归零（Threshold zeroed）
    IF _uInfoCode = 0 THEN
        _uInfoCode := 16#0002_1902;                   // 0002_1902 阈值非有限已禁用【信息级】/ Non-finite threshold disabled, info level
    END_IF
ELSE
    _bThrEnEff := bThresholdEnable;                   // 合法阈值按使能位生效（Valid threshold honours the enable pin）
    _fThrEff   := fThreshold;                         // 阈值直通（Threshold passes through）
END_IF

// ============================================================================
// 段 6｜首扫初始化与复位（极值置为当前信号、计数清零、事件清零）
//      First-scan init and reset share the same assignment block
// ============================================================================
IF (NOT _bInit) OR _fbTrigReset.Q THEN
    fPeak       := _fSigEff;                          // 峰值置为当前信号（Peak set to the current signal）
    fValley     := _fSigEff;                          // 谷值置为当前信号（Valley set to the current signal）
    uPeakCount  := 0;                                 // 峰值计数清零（Peak counter cleared）
    _fPeakPrev  := _fSigEff;                          // 变化率基线同步（Rate baseline synchronized）
    bPeakEvent   := FALSE;                            // 复位拍不出事件（No event on the reset scan）
    bValleyEvent := FALSE;                            // 复位拍不出事件（No event on the reset scan）
    _bInit      := TRUE;                              // 首扫完成（First scan done）
END_IF

// ============================================================================
// 段 7｜使能闸门：FALSE 时极值冻结、事件清零、变化率归零（极值保持不动）
//      Enable gate: FALSE freezes extrema, clears events, zeroes the rate
// ============================================================================
IF NOT bEnable THEN
    IF NOT bDetectValley THEN
        fValley := 0.0;                               // 谷值关闭时输出归零（Valley forced to zero when disabled）
    END_IF
    fPeakRate := 0.0;                                 // 冻结态变化率归零（Rate zeroed while frozen）
    uErrorId  := _uInfoCode;                          // 参数域信息码仍如实上报（Info codes still reported）
    RETURN;                                           // 提前退出，极值保持不动（Early exit keeps extrema frozen）
END_IF

// ============================================================================
// 段 8｜先衰减后比较（保证衰减不被同拍更新掩盖；衰减后钳制不低于当前信号）
//      Decay before comparison, and decay never drops the peak below the signal
// ============================================================================
IF (_fDecayEff > DL_PEAK_FLOAT_EPS) AND (_fDtSec > 0.0) THEN
    _fDecayStep := _fDecayEff * _fDtSec;              // 本拍衰减步长 = 速率 × 周期（Step = rate times period）
    fPeak := fPeak - _fDecayStep;                     // 峰值按步长回落（Peak decays by one step）
    IF fPeak < _fSigEff THEN
        fPeak := _fSigEff;                            // 衰减不得使峰值低于当前信号（Decay never undercuts the signal）
    END_IF
END_IF

// ============================================================================
// 段 9｜峰值更新（严格大于才算更新，相等不计，避免噪声使计数爆增）
//      Peak update by strict greater-than comparison
// ============================================================================
IF _bSigValid AND (_fSigEff > fPeak) THEN
    fPeak      := _fSigEff;                           // 刷新峰值（Refresh the peak）
    bPeakEvent := TRUE;                               // 单拍事件置位，本拍不再清除（R25 第二律）/ One-scan event, not cleared this scan
    uPeakCount := uPeakCount + 1;                     // 峰值更新计数累加（Peak update counter increments）
END_IF

// ============================================================================
// 段 10｜谷值更新（可选；关闭时输出恒零）
//      Valley update, optional and forced to zero when disabled
// ============================================================================
IF NOT bDetectValley THEN
    fValley := 0.0;                                   // 谷值关闭（Valley disabled）
ELSIF _bSigValid AND (_fSigEff < fValley) THEN
    fValley     := _fSigEff;                          // 刷新谷值（Refresh the valley）
    bValleyEvent := TRUE;                             // 单拍事件置位（One-scan event asserted）
END_IF

// ============================================================================
// 段 11｜阈值超限（电平型每拍重算，不做单发；需要单发由调用方加边沿）
//      Threshold flag recomputed every scan as a level signal
// ============================================================================
bOverThreshold := _bThrEnEff AND (fPeak >= _fThrEff);

// ============================================================================
// 段 12｜峰值变化率（除法前置判零，零周期直接归零）
//      Peak rate with a divide-by-zero guard
// ============================================================================
IF _fDtSec > DL_PEAK_FLOAT_EPS THEN
    fPeakRate := (fPeak - _fPeakPrev) / _fDtSec;      // 变化率 = 增量 / 周期秒值（Rate = delta over period）
ELSE
    fPeakRate := 0.0;                                 // 零周期无定义，置零（Zero period gives zero rate）
END_IF
_fPeakPrev := fPeak;                                  // 更新变化率基线（Refresh the rate baseline）

uErrorId := _uInfoCode;                               // 出口信息码映射（Info code mapped to the output）
END_FUNCTION_BLOCK
