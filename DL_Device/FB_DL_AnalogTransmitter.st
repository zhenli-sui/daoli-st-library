(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AnalogTransmitter
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library，零厂商方言
 * 分类     (Category)   : 设备信号处理功能块（Function Block，实现 I_DL_AnalogSensor）
 * 功能简述 (Function)   : NAMUR NE43 语义模拟量变送器处理块。在原始物理域
 *                         （mA/0..10V，由调用方约定）执行四段诊断：故障门限外
 *                         断线（方向可配置）、欠量程段、有效测量域、超量程段，
 *                         0 域附近判回路开路；内嵌滑动平均滤波与线性标定；
 *                         故障态保持末次有效工程量；HH/H/L/LL 四级报警在
 *                         有效与欠/超量程段照常计算、故障态全部保持。
 * 接口实现 (Implements) : I_DL_AnalogSensor（属性 fValue/eQuality/bAlarmHH/
 *                         bAlarmH/bAlarmL/bAlarmLL/uErrorId，全部在本文件
 *                         尾部落地）
 * 开源溯源 (Origin)     : 来源标签 namur-ne43（RAW_NOTES_R5 S-5：NAMUR NE43
 *                         信号电平域，公开推荐实践，多来源交叉印证——有效
 *                         测量域 3.8~20.5 mA、故障域 <3.6 / >21 mA、0 mA =
 *                         回路断线、断线诊断须在原始域而非工程量域判定、
 *                         故障方向可配置、超量程标记而非剔除；仅借鉴公开
 *                         标准语义，欠/超量程段以故障门限与量程端点为界
 *                         （默认 4~20 mA 组态下对应 NE43 3.8/20.5 mA 有效
 *                         域界语义），不硬编码，clean-room 未复制任何源码行）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 防除零/防越界/NaN 自比防御 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 质量分级判定含
 *                         ELSE 兜底链 ✓｜R7 滤波实例主体无条件刷新（无定时
 *                         器/边缘实例，滤波为纯算术递推）✓
 * 公约遵循 (Convention) : 0.1 首扫判据 IF bTrack OR (NOT _bInit)，跟踪脉冲
 *                         运行中途插入时重置滤波缓冲与保持值。
 *                         0.6 量程对调自修复：对调后继续计算不中断。
 *                         0.8 全部 REAL 输入 fX <> fX 检测，默认值先赋。
 *                         0.7 故障码段位 16#0003_xxxx：【故障级】0003_0210
 *                         NE43 故障态（断线/开路/非有限输入，R15 锁存语义
 *                         由质量位持续标注，原始恢复后自动解除并保持值
 *                         重新跟随）；【信息级】0003_0102 量程对调自修复 /
 *                         0003_0103 欠/超量程提示 / 0003_0104 原始量程跨度
 *                         退化回退（仅写 uErrorId，不设任何故障位，0.2）。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 4 条：
 *                         ① fFilterTC 已按规格 1.6 定稿删除，由 uFilterWindow
 *                           : USINT := 8 滑动平均窗口替代（规格内定稿）。
 *                         ② 引脚表未列 bTrack，为落实 0.1 首扫/跟踪范式与
 *                           "运行中途插入跟踪脉冲"验收向量新增 IN 引脚。
 *                         ③ FC_DL_LinearScale / FB_DL_MovingAverage 本轮
 *                           尚未入库，标定与滤波在本文件内联等价实现（含
 *                           防除零与窗口钳位），两件入库后可无缝外移。
 *                         ④ 对调自修复码 0.6 原文为 16#0001_0001，依 0.7
 *                           段位分配 DL_Device 族取信息级 0003_0102；新增
 *                           0003_0103/0003_0104 按 0.7 之 01xx 信息段顺延。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R5 轮 · DL_Device 开库）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_BreakDir（归属 FB_DL_AnalogTransmitter，与其同文件）
 * 含义: 断线故障方向配置，由变送器实际 Downscale/Upscale 组态决定；
 *       只判配置方向，另一方向的越限不误报为断线（S-5 提取点②）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_BreakDir :
(
    eLow  := 0,    // 低断方向（Downscale）：原始值低于故障下门限判断线 / Downscale direction, raw below low fault threshold means wire break
    eHigh := 1     // 高断方向（Upscale）：原始值高于故障上门限判断线 / Upscale direction, raw above high fault threshold means wire break
) USINT;
END_TYPE

(*==============================================================================
 * 功能块主体
 *============================================================================*)
FUNCTION_BLOCK FB_DL_AnalogTransmitter IMPLEMENTS I_DL_AnalogSensor
VAR_INPUT
    fRawInput      : REAL;              // 原始输入（Raw input），已线性化的 mA/0..10V 物理域值，单位由调用方约定 / Raw physical-domain input, unit per caller config
    fRawLow        : REAL;              // 原始域量程下限（Raw span low），如 4.0 mA；对调自修复 / Raw span low endpoint, swap self-repair
    fRawHigh       : REAL;              // 原始域量程上限（Raw span high），如 20.0 mA；对调自修复 / Raw span high endpoint, swap self-repair
    fEuLow         : REAL;              // 工程量程下限（Engineering span low），如 0.0 [%] 或 [kPa] / Engineering span low endpoint
    fEuHigh        : REAL;              // 工程量程上限（Engineering span high），如 100.0 [%] 或 [kPa] / Engineering span high endpoint
    eBreakDirection: E_DL_BreakDir := E_DL_BreakDir.eLow; // 断线故障方向（Break direction），eLow=低断 / eHigh=高通，按变送器组态 / Break direction per transmitter config
    fFaultLow      : REAL := 3.6;       // NE43 故障下门限（NE43 low fault threshold），默认 3.6（原始域）/ Low fault threshold in raw domain
    fFaultHigh     : REAL := 21.0;      // NE43 故障上门限（NE43 high fault threshold），默认 21.0（原始域）/ High fault threshold in raw domain
    uFilterWindow  : USINT := 8;        // 滑动平均窗口（Moving-average window），规格定稿替代时间常数引脚，1=直通 / Moving-average window, 1 = pass-through
    bEnableFilter  : BOOL := TRUE;      // 使能滑动平均滤波（Enable moving-average filter），FALSE=直通 / FALSE bypasses filtering
    fAlarmHH       : REAL;              // 上上限报警门限（High-high alarm limit），量纲=工程量 / High-high limit in engineering unit, 非数=禁用 / NaN disables
    fAlarmH        : REAL;              // 上限报警门限（High alarm limit），量纲=工程量，非数=禁用 / High limit in engineering unit, NaN disables
    fAlarmL        : REAL;              // 下限报警门限（Low alarm limit），量纲=工程量，非数=禁用 / Low limit in engineering unit, NaN disables
    fAlarmLL       : REAL;              // 下下限报警门限（Low-low alarm limit），量纲=工程量，非数=禁用 / Low-low limit in engineering unit, NaN disables
    bTrack         : BOOL;              // 跟踪脉冲（Track pulse），上升语义电平：TRUE 拍重置滤波与保持值（R11 偏离新增，见头注释②）/ Track pulse re-primes filter and hold value
END_VAR

VAR_OUTPUT
    fValue         : REAL;              // 工程量当前值（Current engineering value），故障态保持末次有效值 / Holds last good value in fault
    eQuality       : E_DL_SignalQuality; // 信号质量分级（Signal quality grade），NE43 四段诊断 / NE43 diagnostic grade
    bAlarmHH       : BOOL;              // 上上限报警（High-high alarm），有效及欠/超量程段照常计算 / Computed in good and range-violation segments
    bAlarmH        : BOOL;              // 上限报警（High alarm）/ High alarm
    bAlarmL        : BOOL;              // 下限报警（Low alarm）/ Low alarm
    bAlarmLL       : BOOL;              // 下下限报警（Low-low alarm）/ Low-low alarm
    uErrorId       : UDINT;             // 末次故障码（Last error code），0=无故障，段位 16#0003_xxxx / Last error code, 0 = none
    bWireBreak     : BOOL;              // 断线/开路合并位（Wire break merged flag），含开路 / TRUE on wire break or open loop
    bRangeViol     : BOOL;              // 欠/超量程合并位（Range violation merged flag）/ TRUE on under-range or over-range
END_VAR

VAR
    _bInit         : BOOL := FALSE;     // 首扫初始化标志（First-scan init flag），R19 范式判据成员 / R19 paradigm member
    _fHoldEu       : REAL := 0.0;       // 末次有效工程量（Last good engineering value），保持语义载体 / Hold-semantics carrier
    _fValueOut     : REAL := 0.0;       // 输出镜像寄存（Output mirror register），属性与引脚同源 / Mirror shared by pin and property
    _eQualityInt   : E_DL_SignalQuality := E_DL_SignalQuality.eGood; // 质量分级内部寄存（Internal quality register）/ Internal quality register
    _bAlarmHH      : BOOL;              // 上上限报警内部寄存（Internal high-high alarm register）/ Internal alarm register
    _bAlarmH       : BOOL;              // 上限报警内部寄存（Internal high alarm register）/ Internal alarm register
    _bAlarmL       : BOOL;              // 下限报警内部寄存（Internal low alarm register）/ Internal alarm register
    _bAlarmLL      : BOOL;              // 下下限报警内部寄存（Internal low-low alarm register）/ Internal alarm register
    _uErrorIdInt   : UDINT := 0;        // 故障码内部寄存（Internal error code register）/ Internal error code register
    _bFaultState   : BOOL;              // NE43 故障态标志（NE43 fault state flag），断线/开路/非有限输入 / Fault state on break, open loop or non-finite input
    _fRawLoEff     : REAL;              // 对调修复后量程下限（Repaired span low）/ Repaired raw span low endpoint
    _fRawHiEff     : REAL;              // 对调修复后量程上限（Repaired span high）/ Repaired raw span high endpoint
    _bSwap         : BOOL;              // 本拍发生对调修复（Swap repair occurred this cycle）/ Swap repair occurred flag
    _bSpanDegenerate : BOOL;            // 原始量程跨度退化（Degenerate raw span），近零或非有限 / Span near zero or non-finite
    _fFaultLoEff   : REAL := 3.6;       // 防御后故障下门限（Sanitized low fault threshold）/ Sanitized low fault threshold
    _fFaultHiEff   : REAL := 21.0;      // 防御后故障上门限（Sanitized high fault threshold）/ Sanitized high fault threshold
    _fEuLoEff      : REAL := 0.0;       // 防御后工程下限（Sanitized engineering low）/ Sanitized engineering low
    _fEuHiEff      : REAL := 100.0;     // 防御后工程上限（Sanitized engineering high）/ Sanitized engineering high
    _bValid        : BOOL;              // 原始输入有效（Raw input valid），非有限值为 FALSE / FALSE when input is non-finite
    _fScaleRaw     : REAL;              // 参与标定的原始值（Raw value entering scaling），滤波输出或直通 / Filtered or pass-through raw value
    _fScaledEu     : REAL;              // 本拍标定结果（Scaled result this cycle）/ Scaled engineering result this cycle
    _fRawSpan      : REAL;              // 原始量程跨度（Raw span width）/ Raw span width
    _bFilterActive : BOOL;              // 滤波激活（Filter active），使能且窗口 >= 2 / Active when enabled and window >= 2
    _uWindowEff    : USINT;             // 钳位后有效窗口（Effective clamped window），上限 128 / Effective window clamped to 128
    _uWindowPrev   : USINT;             // 上一拍有效窗口（Previous effective window），变更检测用于缓冲重置 / Previous window for change detection
    _uBufIdx       : UINT;              // 环形缓冲写指针（Ring buffer write index），0..127 / Ring write index 0..127
    _uBufFill      : USINT;             // 有效样本数（Valid sample count），上限=有效窗口 / Valid samples, capped at effective window
    _fBufSum       : REAL := 0.0;       // 窗口样本和（Window sample sum），每拍重算 / Recomputed each cycle
    _fFillR        : REAL := 1.0;       // 样本数实型镜像（Sample count REAL mirror），供安全除法 / REAL mirror of sample count for safe division
    _afBuf         : ARRAY[0..127] OF REAL; // 滑动平均环形缓冲（Moving-average ring buffer），128 槽 / 128-slot ring buffer
    i              : UINT;              // 缓冲遍历循环索引（Buffer traversal loop index）/ Loop index for buffer traversal
    _uRingIdx      : UINT;              // 环形取数临时索引（Ring fetch temp index）/ Temporary ring fetch index
END_VAR

// ============================================================================
// 段 1｜首扫/跟踪初始化（R19 唯一合法范式：IF bTrack OR (NOT _bInit)）
//      First-scan / track initialization (R19 sole legal paradigm)
// ============================================================================
IF bTrack OR (NOT _bInit) THEN
    _uBufIdx   := 0;                          // 写指针归零（Write index reset）
    _uBufFill  := 0;                          // 有效样本清零：滤液从直通逐步重新填充（Samples cleared, filter refills from pass-through）
    _fBufSum   := 0.0;                        // 窗口和清零（Window sum cleared）
    _fHoldEu   := 0.0;                        // 保持值清零，本拍有效样本将立即回填（Hold cleared, refilled by first valid sample）
    _bFaultState := FALSE;                    // 故障态复位（Fault state released）
    _uErrorIdInt := 0;                        // 故障码清零（Error code cleared）
    _eQualityInt := E_DL_SignalQuality.eGood; // 质量复位为良好（Quality reset to good）
    _bInit      := TRUE;                      // 初始化完成（Initialization done）
END_IF

// ============================================================================
// 段 2｜窗口参数钳位与变更检测（防越界：窗口上限 128 槽缓冲）
//      Window clamping and change detection (bounds defense: 128-slot buffer)
// ============================================================================
_uWindowEff := uFilterWindow;                 // 取组态窗口（Take configured window）
IF _uWindowEff > 128 THEN
    _uWindowEff := 128;                       // 超限钳位到缓冲容量（Clamp to buffer capacity）
END_IF
IF _uWindowEff = 0 THEN
    _uWindowEff := 1;                         // 零窗口按单样本直通（Zero window treated as single-sample pass-through）
END_IF
IF _uWindowEff <> _uWindowPrev THEN           // 窗口在线变更（Window changed online）
    _uBufFill := 0;                           // 缓冲判无效重新填充（Invalidate buffer, refill from scratch）
    _uWindowPrev := _uWindowEff;              // 记录新窗口（Record new window）
END_IF
_bFilterActive := bEnableFilter AND (_uWindowEff >= 2); // 窗口 1 视为直通（Window 1 treated as pass-through）

// ============================================================================
// 段 3｜参数防御（0.8：全部 REAL 参数先做非数自比，默认值先赋）+ 0.6 对调自修复
//      Parameter sanitation (0.8 NaN self-compare, defaults first) + 0.6 swap repair
// ============================================================================
_fRawLoEff := fRawLow;                        // 量程下限镜像（Span low mirror）
_fRawHiEff := fRawHigh;                       // 量程上限镜像（Span high mirror）
_fEuLoEff  := fEuLow;                         // 工程下限镜像（Engineering low mirror）
_fEuHiEff  := fEuHigh;                        // 工程上限镜像（Engineering high mirror）
_fFaultLoEff := fFaultLow;                    // 故障下门限镜像（Low fault threshold mirror）
_fFaultHiEff := fFaultHigh;                   // 故障上门限镜像（High fault threshold mirror）

IF _fFaultLoEff <> _fFaultLoEff THEN          // 非数自比检测（NaN self-compare test）
    _fFaultLoEff := 3.6;                      // 回落 NE43 默认下门限（Fallback to NE43 default low）
END_IF
IF _fFaultHiEff <> _fFaultHiEff THEN          // 非数自比检测（NaN self-compare test）
    _fFaultHiEff := 21.0;                     // 回落 NE43 默认上门限（Fallback to NE43 default high）
END_IF
IF _fEuLoEff <> _fEuLoEff THEN                // 非数自比检测（NaN self-compare test）
    _fEuLoEff := 0.0;                         // 回落工程下限默认（Fallback engineering low default）
END_IF
IF _fEuHiEff <> _fEuHiEff THEN                // 非数自比检测（NaN self-compare test）
    _fEuHiEff := 100.0;                       // 回落工程上限默认（Fallback engineering high default）
END_IF

_bSwap := FALSE;                              // 对调标志复位（Swap flag reset）
IF _fRawLoEff > _fRawHiEff THEN               // 参数对自修复判据（Pair swap test, NaN-safe ordering）
    _fRawLoEff := fRawHigh;                   // 下限取原上限（Low takes former high）
    _fRawHiEff := fRawLow;                    // 上限取原下限（High takes former low）
    _bSwap := TRUE;                           // 登记对调修复（Register swap repair, computation continues）
END_IF

// ============================================================================
// 段 4｜非有限输入判定（0.8）与出口默认值先赋（保持语义）
//      Non-finite input test (0.8) and output defaults assigned first (hold)
// ============================================================================
_bValid := (fRawInput = fRawInput);           // 非数自比检测：等号成立即有效（NaN 时自比不等）/ NaN iff self-compare fails, TRUE means valid
_fValueOut := _fHoldEu;                       // 出口默认：保持末次有效值（Default: hold last good value）
_bFaultState := FALSE;                        // 故障态先复位，分级链中重新判定（Fault state preset FALSE, re-decided below）
_eQualityInt := E_DL_SignalQuality.eGood;     // 出口默认质量（Default quality）

// ============================================================================
// 段 5｜NE43 四段质量分级（全部在原始物理域判定，S-5 提取点③；
//       断线只判配置方向，配置外方向不误报）
//      NE43 four-band classification in raw domain, break judged only on
//      the configured direction to avoid false breaks
// ============================================================================

IF NOT _bValid THEN
    _eQualityInt := E_DL_SignalQuality.eOpenLoop;   // 非有限输入按回路开路处理（Non-finite input as open loop）
    _bFaultState := TRUE;                           // 进入故障态（Enter fault state）
ELSIF fRawInput < (_fFaultLoEff * 0.5) THEN
    _eQualityInt := E_DL_SignalQuality.eOpenLoop;   // 0 域附近判开路（0 mA 回路断开）/ Near-zero domain as open loop
    _bFaultState := TRUE;
ELSIF fRawInput < _fFaultLoEff THEN
    IF eBreakDirection = E_DL_BreakDir.eLow THEN
        _eQualityInt := E_DL_SignalQuality.eWireBreakLow; // 配置低断：判断线（Configured downscale: wire break）
        _bFaultState := TRUE;
    ELSE
        _eQualityInt := E_DL_SignalQuality.eUnderRange;   // 配置高通：欠量程段不误报断线（High config: under-range, no false break）
    END_IF
ELSIF fRawInput > _fFaultHiEff THEN
    IF eBreakDirection = E_DL_BreakDir.eHigh THEN
        _eQualityInt := E_DL_SignalQuality.eWireBreakHigh; // 配置高通：判断线（Configured upscale: wire break）
        _bFaultState := TRUE;
    ELSE
        _eQualityInt := E_DL_SignalQuality.eOverRange;     // 配置低断：超量程段不误报断线（Low config: over-range, no false break）
    END_IF
ELSIF fRawInput < _fRawLoEff THEN
    _eQualityInt := E_DL_SignalQuality.eUnderRange;   // 欠量程段（如 3.6~4.0 mA）标记不剔除（Under-range marked, not discarded）
ELSIF fRawInput > _fRawHiEff THEN
    _eQualityInt := E_DL_SignalQuality.eOverRange;    // 超量程段（如 20.0~21.0 mA）标记不剔除（Over-range marked, not discarded）
ELSE
    _eQualityInt := E_DL_SignalQuality.eGood;         // 有效测量域（Valid measurement span）
END_IF

// ============================================================================
// 段 6｜滑动平均滤波（仅有效拍推入缓冲，故障拍不污染窗口）+ 线性标定
//      Moving-average filter (push only on valid cycles) + linear scaling
// ============================================================================
IF _bFaultState THEN
    _fScaleRaw := fRawInput;                  // 故障拍标定值不使用（Unused in fault cycles, hold applies）
ELSE
    IF _bFilterActive THEN
        _afBuf[_uBufIdx] := fRawInput;        // 写入环形槽（Write ring slot, index < 128 by MOD）
        _uBufIdx := (_uBufIdx + 1) MOD 128;   // 写指针循环推进（Advance write index cyclically）
        IF _uBufFill < _uWindowEff THEN
            _uBufFill := _uBufFill + 1;       // 未满则递增有效样本（Increment fill until window reached）
        END_IF
        _fBufSum := 0.0;                      // 每拍重算窗口和（Recompute window sum each cycle）
        FOR i := 1 TO _uBufFill DO            // 固定界循环，无死循环风险（Bounded loop, no deadlock risk）
            _uRingIdx := (_uBufIdx + 128 - i) MOD 128; // 倒序取最近样本槽（Fetch latest slots in reverse order）
            _fBufSum := _fBufSum + _afBuf[_uRingIdx];  // 累加窗口样本（Accumulate window sample）
        END_FOR
        _fFillR := _uBufFill;                 // 样本数实型镜像（Sample count as REAL）
        IF _fFillR > 0.5 THEN
            _fScaleRaw := _fBufSum / _fFillR; // 窗口均值（Window mean, divisor proven >= 1）
        ELSE
            _fScaleRaw := fRawInput;          // 防除零回退直通（Divide-by-zero fallback to pass-through）
        END_IF
    ELSE
        _fScaleRaw := fRawInput;              // 滤波禁用直通（Filter disabled, pass-through）
    END_IF

    // 线性标定（内联实现，偏离留档③；除零与退化双重防御）
    _fRawSpan := _fRawHiEff - _fRawLoEff;     // 原始量程跨度（Raw span width）
    _bSpanDegenerate := (_fRawSpan <> _fRawSpan) OR (ABS(_fRawSpan) < 1E-9); // 非数或近零判退化（Degenerate on NaN or near-zero）
    IF _bSpanDegenerate THEN
        _fScaledEu := _fEuLoEff;              // 退化回退工程下限（Degenerate fallback to engineering low）
    ELSE
        _fScaledEu := _fEuLoEff + (_fScaleRaw - _fRawLoEff) * (_fEuHiEff - _fEuLoEff) / _fRawSpan; // 线性插值（Linear interpolation, denominator proven non-zero）
    END_IF
    _fValueOut := _fScaledEu;                 // 有效拍输出跟随（Output follows on valid cycles）
    _fHoldEu   := _fScaledEu;                 // 更新保持载体（Update hold carrier）
END_IF

// ============================================================================
// 段 7｜四级报警计算（有效与欠/超量程段照常计算；故障态全部保持；
//       门限为非数时该级视为未组态不报警——0.8 防御）
//      Four-level alarms (computed in good and range segments, held in
//      fault; NaN threshold disables that level)
// ============================================================================
IF NOT _bFaultState THEN
    IF fAlarmHH = fAlarmHH THEN
        _bAlarmHH := (_fValueOut >= fAlarmHH); // 上上限判定（High-high evaluation）
    ELSE
        _bAlarmHH := FALSE;                    // 门限非数=该级禁用（NaN limit disables level）
    END_IF
    IF fAlarmH = fAlarmH THEN
        _bAlarmH := (_fValueOut >= fAlarmH);   // 上限判定（High evaluation）
    ELSE
        _bAlarmH := FALSE;                     // 门限非数=该级禁用（NaN limit disables level）
    END_IF
    IF fAlarmL = fAlarmL THEN
        _bAlarmL := (_fValueOut <= fAlarmL);   // 下限判定（Low evaluation）
    ELSE
        _bAlarmL := FALSE;                     // 门限非数=该级禁用（NaN limit disables level）
    END_IF
    IF fAlarmLL = fAlarmLL THEN
        _bAlarmLL := (_fValueOut <= fAlarmLL); // 下下限判定（Low-low evaluation）
    ELSE
        _bAlarmLL := FALSE;                    // 门限非数=该级禁用（NaN limit disables level）
    END_IF
END_IF // 故障态不进入本段，四级报警输出自动保持上一拍值（Fault cycles skip this block, alarms held）

// ============================================================================
// 段 8｜故障码优先级链与合并位派生（信息级仅写 uErrorId，0.2 公约）
//      Error-code priority chain and merged flag derivation (info codes only)
// ============================================================================
IF _bFaultState THEN
    _uErrorIdInt := 16#0003_0210;             // 0003_0210 NE43 故障态（断线/开路/非有限输入）【故障级】/ NE43 fault state, fault level
ELSIF (_eQualityInt = E_DL_SignalQuality.eUnderRange) OR (_eQualityInt = E_DL_SignalQuality.eOverRange) THEN
    _uErrorIdInt := 16#0003_0103;             // 0003_0103 欠/超量程提示【信息级】/ Range violation hint, info level
ELSIF _bSwap THEN
    _uErrorIdInt := 16#0003_0102;             // 0003_0102 量程对调自修复【信息级】（0.6 公约，段位依 0.7 归 DL_Device 信息段）/ Swap self-repair, info level
ELSIF _bSpanDegenerate THEN
    _uErrorIdInt := 16#0003_0104;             // 0003_0104 原始量程跨度退化回退【信息级】/ Degenerate span fallback, info level
ELSE
    _uErrorIdInt := 0;                        // 无故障无提示（No fault, no hint）
END_IF

// ============================================================================
// 段 9｜引脚映射（属性与引脚同源于内部镜像，避免同名遮蔽）
//      Pin mapping (pin and property share internal mirrors, no shadowing)
// ============================================================================
fValue     := _fValueOut;                     // 工程量输出（Engineering value output）
eQuality   := _eQualityInt;                   // 质量分级输出（Quality output）
bAlarmHH   := _bAlarmHH;                      // 上上限输出（High-high output）
bAlarmH    := _bAlarmH;                       // 上限输出（High output）
bAlarmL    := _bAlarmL;                       // 下限输出（Low output）
bAlarmLL   := _bAlarmLL;                      // 下下限输出（Low-low output）
uErrorId   := _uErrorIdInt;                   // 故障码输出（Error code output）
bWireBreak := (_eQualityInt = E_DL_SignalQuality.eWireBreakLow)
          OR (_eQualityInt = E_DL_SignalQuality.eWireBreakHigh)
          OR (_eQualityInt = E_DL_SignalQuality.eOpenLoop);            // 断线/开路合并位（Break/open merged flag）
bRangeViol := (_eQualityInt = E_DL_SignalQuality.eUnderRange)
          OR (_eQualityInt = E_DL_SignalQuality.eOverRange);           // 欠/超量程合并位（Range violation merged flag）

(*------------------------------------------------------------------------------
 * 属性: fValue（GET）—— 工程量当前值（故障态保持末次有效值）。
 *      Property fValue (GET) - current engineering value, holds last good in fault.
 *------------------------------------------------------------------------------*)
PROPERTY fValue : REAL
fValue := _fValueOut;         // 返回输出镜像（Return output mirror）

(*------------------------------------------------------------------------------
 * 属性: eQuality（GET）—— 信号质量分级（NE43 四段诊断结果）。
 *      Property eQuality (GET) - signal quality grade per NE43 diagnostics.
 *------------------------------------------------------------------------------*)
PROPERTY eQuality : E_DL_SignalQuality
eQuality := _eQualityInt;     // 返回质量镜像（Return quality mirror）

(*------------------------------------------------------------------------------
 * 属性: bAlarmHH（GET）—— 上上限报警位。
 *      Property bAlarmHH (GET) - high-high alarm bit.
 *------------------------------------------------------------------------------*)
PROPERTY bAlarmHH : BOOL
bAlarmHH := _bAlarmHH;        // 返回上上限镜像（Return high-high mirror）

(*------------------------------------------------------------------------------
 * 属性: bAlarmH（GET）—— 上限报警位。
 *      Property bAlarmH (GET) - high alarm bit.
 *------------------------------------------------------------------------------*)
PROPERTY bAlarmH : BOOL
bAlarmH := _bAlarmH;          // 返回上限镜像（Return high mirror）

(*------------------------------------------------------------------------------
 * 属性: bAlarmL（GET）—— 下限报警位。
 *      Property bAlarmL (GET) - low alarm bit.
 *------------------------------------------------------------------------------*)
PROPERTY bAlarmL : BOOL
bAlarmL := _bAlarmL;          // 返回下限镜像（Return low mirror）

(*------------------------------------------------------------------------------
 * 属性: bAlarmLL（GET）—— 下下限报警位。
 *      Property bAlarmLL (GET) - low-low alarm bit.
 *------------------------------------------------------------------------------*)
PROPERTY bAlarmLL : BOOL
bAlarmLL := _bAlarmLL;        // 返回下下限镜像（Return low-low mirror）

(*------------------------------------------------------------------------------
 * 属性: uErrorId（GET）—— 末次故障码（0=无故障）。
 *      Property uErrorId (GET) - last error code (0 = none).
 *------------------------------------------------------------------------------*)
PROPERTY uErrorId : UDINT
uErrorId := _uErrorIdInt;     // 返回故障码镜像（Return error code mirror）
END_FUNCTION_BLOCK
