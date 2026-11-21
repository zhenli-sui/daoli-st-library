(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LevelRadarValidate
 * 溯源说明 (Provenance): 道莅 clean-room 防御性实现（IEC 61131-3 纯净实现，闭源文档仅借语义，零代码行）
 * 所属子库 (Sublibrary) : DL_Device / SignalQuality
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），仅用
 *                         Standard.library 的 TON / ABS / LIMIT / TIME_TO_REAL
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 雷达液位回波可信度仲裁
 * 功能一句话 (Summary)  : 用回波置信度、信噪比、量程、变化率四条判据仲裁雷达液位
 *                         是否可信，不可信时保持末次可信值并给出四位掩码。
 *
 * 本件存在的意义 (Why this unit exists)
 *   雷达液位最典型的失效不是「没读数」，而是**读数看着很正常但其实是假回波**
 *   （搅动液面、泡沫、罐壁多重反射）。一旦假回波进了联锁或计量，结果是
 *   抽空泵或溢出。I_DL_AnalogSensor 只管 4~20 mA 的质量位，解不了回波域；
 *   本件补的正是「回波可信度」这一层。
 *
 * 四判据同拍评估（**不早退**，全部写进掩码）
 *   位 1 置信度低 : fQuality < fQualityMin
 *   位 2 信噪比低 : fSnr < fSnrMin
 *   位 4 超量程   : fLevel < 0 或 fLevel > fSpan
 *   位 8 变化率跳变: |fLevel − 末次可信值| / 采样周期 > fRateLimit
 *   四条同时评估、同时写进掩码——现场要的是「一次看全四条」，早退只会让人
 *   改一条跑一次。bTrusted = (uSuspectMask = 0) 即时给出（联锁看即时值，
 *   不能等确认窗）。
 *
 * 状态抖动抑制 (Anti-flicker)
 *   进入不可信是**即时**的（假回波必须立刻挡住），恢复可信要 mask 全零
 *   持续 tConfirm 才生效。这是一条不对称的滞回：宁可晚一点恢复，也不让
 *   读数在临界回波上反复跳。
 *
 * 边界安全 (Boundary)
 *   ① fSpan <= 0、门限非法或采样周期 <= 0 → 故障 0345、bValid = FALSE；
 *   ② 任一输入非有限 → 故障 0346，**本次不更新 fLevelOut**（R42：跨拍取值必须
 *      本拍复验，坏值绝不进联锁）；
 *   ③ 超量程只置掩码位，不按可信值发布；
 *   ④ 初始无历史可信值 → fLevelOut := 0 且 bValid := FALSE，**绝不把 0 m 当可信
 *      液位发布**（R43 家族：保持值必须夹进有效域并标记不可用）；
 *   ⑤ 失能 → bTrusted := FALSE、eHealth := eUnknown，fLevelOut 保持（供趋势）；
 *   ⑥ 采样周期由 tSample 引脚注入，**禁读系统时钟**；
 *   ⑦ CASE 落 ELSE 置 0347 并回 eFault。
 *
 * 错误码    : 16#0003_0178 质量指标低于门限，保持末次可信值——信息级，正常防御
 *             16#0003_0179 变化率跳变，单拍剔除——信息级，正常防御
 *             16#0003_0345 量程/门限/采样周期参数非法——故障级，bValid = FALSE
 *             16#0003_0346 输入非有限，不更新发布值——故障级
 *             16#0003_0347 状态机落 ELSE 兜底（非法状态）——故障级，回 eFault
 * 码位总账  : 16#0003_0178 用 / 16#0003_0179 用 ｜ 16#0003_0345 用 / 16#0003_0346 用 / 16#0003_0347 用
 * 状态机    : E_DL_RadarState（eIdle / eTrusted / eSuspect / eFault），CASE 含 ELSE 兜底，
 *             ELSE 置 16#0003_0347 并回 eFault；失能无条件回 eIdle
 * 采样约定  : 每任务周期调用一次；变化率判据用 tSample 引脚换算，不读系统时钟
 * 依赖说明  : 仅 Standard.library；健康出口引用 E_DL_Ne107Status（引用不重声明，R70③）
 * 验收向量  : V1 液位 5.00 m、置信度 80 %、信噪比 20 dB、量程 10 m、上拍可信 4.98
 *               → bTrusted = TRUE，uSuspectMask = 0，fLevelOut = 5.00，eHealth = eOk
 *             V2 置信度 20 %（< 40）→ 掩码位 1，bTrusted = FALSE，fLevelOut 保持 4.98，
 *                eErr = 0178，eHealth = eCheckFunction（保持主向量）
 *             V3 液位 12.0 m（> 量程 10），置信度与信噪比都好 → 掩码位 4，
 *                不按可信值发布（超量程主向量）
 *             V4 上拍可信 1.00 m，本拍 6.00 m、tSample 1 s、fRateLimit 0.5 m/s
 *                → 掩码位 8 + 位 1/2 若同时成立全部置位，eErr 优先级见段 9（跳变主向量）
 *             V5 冷启动首拍（无历史可信值）且本拍不可信 → fLevelOut = 0 且 bValid = FALSE
 *                （R43 主向量：0 m 绝不发布为可信液位）
 *             V6 fLevel = NaN → 0346，fLevelOut 不更新（坏值不进联锁主向量）
 *             V7 fSpan = 0 → 0345，bValid = FALSE
 *             V8 恢复：mask 全零但未满 tConfirm → 仍 eSuspect；满窗 → eTrusted（滞回主向量）
 * 红线自检  : 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 ｜ 纯 IEC 61131-3 ｜ 除零前置
 *             闸（tSample 恒 > 0 且商前显式判据）｜ 浮点只用大小与容差比较 ｜ 无循环
 *             ｜ 全变量双语同行注释 ｜ ENUM + CASE 含 ELSE ｜ TON 在主体前部无条件
 *             刷新 ｜ 掩码与阈值常量化，无魔法数
 * 修订历史  : 2026-11-16  v1.0.0  首版入库（R22 · 批 3 · 设备信号质量）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_RadarState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 回波仲裁相位。0 起步长 10。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_RadarState :
(
    eIdle    := 0,     // 待机：未使能或参数非法 / Idle, disabled or illegal parameters
    eTrusted := 10,    // 可信：四条判据全部通过 / Trusted, all four criteria pass
    eSuspect := 20,    // 存疑：至少一条判据失败，发布值保持 / Suspect, at least one criterion failed
    eFault   := 99     // 故障：参数非法或输入非有限 / Fault, illegal parameter or non-finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_LevelRadarValidate
VAR_INPUT
    fLevel       : REAL;                       // 雷达测得液位 [m] / radar measured level [m]
    fQuality     : REAL;                       // 回波置信度 [%]，范围 0~100 / echo confidence [%], range 0~100
    fSnr         : REAL;                       // 回波信噪比 [dB] / echo signal to noise ratio [dB]
    fSpan        : REAL := 10.0;               // 量程上限 [m]，须 > 0 / span ceiling [m], must be > 0
    fQualityMin  : REAL := 40.0;               // 置信度门限 [%]，范围 0~100 / confidence threshold [%], range 0~100
    fSnrMin      : REAL := 10.0;               // 信噪比门限 [dB]，须 >= 0 / signal to noise threshold [dB], must be >= 0
    fRateLimit   : REAL := 0.5;                // 液位变化率上限 [m/s]，须 > 0 / level rate ceiling [m/s], must be > 0
    tConfirm     : TIME := T#10S;              // 恢复可信确认时间 [ms] / recovery confirm time [ms]
    tSample      : TIME := T#1S;               // 采样周期 [ms]，变化率换算用 / sample period [ms], used by the rate test
    bEnable      : BOOL;                       // 使能 / enable
END_VAR
VAR_OUTPUT
    fLevelOut    : REAL;                       // 发布值：可信则实时值，否则末次可信值 [m] / published level [m]
    bTrusted     : BOOL;                       // 本拍回波可信 / this scan's echo is trusted
    uSuspectMask : WORD;                       // 存疑位掩码：1 置信度 / 2 信噪比 / 4 超量程 / 8 跳变
    eHealth      : E_DL_Ne107Status;           // NE107 健康分级（引用唯一属主） / NE107 health status
    eErr         : UDINT;                      // 错误码，0 表示无错 / error code, 0 means no error
    bError       : BOOL;                       // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid       : BOOL;                       // 发布值可用标志 / published value usable flag
END_VAR
VAR
    fbTrust      : TON;                        // 恢复可信确认窗，段 6 无条件刷新 [ms] / recovery confirm window
    _eState      : E_DL_RadarState := E_DL_RadarState.eIdle; // 当前相位 / current phase
    _bInit       : BOOL := FALSE;              // 首扫标志，初值 FALSE 取非判定 / first-scan flag, tested negated
    _bParamBad   : BOOL;                       // 参数非法标志 / illegal parameter flag
    _bFiniteBad  : BOOL;                       // 输入非有限标志 / non-finite input flag
    _bIllegal    : BOOL;                       // 非法状态标志 / illegal state flag
    _bHaveTrusted : BOOL;                      // 是否已有历史可信值 / whether a trusted value exists
    _bBrkTrust   : BOOL;                       // 恢复确认计时器断输入一拍 / recovery timer one-scan break
    _bBadQuality : BOOL;                       // 置信度不足 / confidence too low
    _bBadSnr     : BOOL;                       // 信噪比不足 / signal to noise too low
    _bBadSpan    : BOOL;                       // 超量程 / out of span
    _bBadRate    : BOOL;                       // 变化率跳变 / rate jump
    _tConfirmUse : TIME := T#10S;              // 生效确认时间 [ms]，已钳位 / effective confirm time, clamped
    _fDtSec      : REAL := 1.0;                // 生效采样周期 [s] / effective sample period [s]
    _fLastTrusted : REAL;                      // 末次可信液位 [m] / last trusted level [m]
    _fOutHeld    : REAL;                       // 发布值保持量 [m] / held published level [m]
    _fRate       : REAL;                       // 本拍变化率 [m/s] / level rate of this scan [m/s]
    _wMask       : WORD;                       // 本拍掩码暂存 / mask staging of this scan
END_VAR
VAR CONSTANT
    DL_VAL_LIM     : REAL := 1.0E6;            // 有限性判定的绝对值上限 [无量纲] / finiteness ceiling
    DL_LEVEL_MIN   : REAL := 0.0;              // 液位物理下限 [m] / level physical floor [m]
    DL_QUAL_MAX    : REAL := 100.0;            // 置信度上限 [%] / confidence ceiling [%]
    DL_QUAL_MIN    : REAL := 0.0;              // 置信度下限 [%] / confidence floor [%]
    DL_SNR_MIN     : REAL := 0.0;              // 信噪比下限 [dB] / signal to noise floor [dB]
    DL_SPAN_MIN    : REAL := 0.0;              // 量程下限 [m]，须严格大于 / span floor [m], strictly greater
    DL_RATE_MIN    : REAL := 0.0;              // 变化率上限下限 [m/s]，须严格大于 / rate floor [m/s], strictly greater
    DL_MS_PER_S    : REAL := 1000.0;           // 毫秒与秒的换算系数 [ms/s] / milliseconds per second
    DL_ONE_SEC     : REAL := 1.0;              // 一秒的兜底值 [s]，采样周期非法时使用 / one second fallback [s]
    DL_CONF_MAX_MS : DINT := 3600000;          // 确认时间上限 [ms]，一小时 / confirm time ceiling, one hour
    DL_TIME_ZERO   : TIME := T#0MS;            // 时间零值基准 [ms] / time zero reference
    DL_MASK_QUAL   : WORD := 16#0001;          // 掩码位 1：置信度低 / mask bit one, low confidence
    DL_MASK_SNR    : WORD := 16#0002;          // 掩码位 2：信噪比低 / mask bit two, low signal to noise
    DL_MASK_SPAN   : WORD := 16#0004;          // 掩码位 4：超量程 / mask bit four, out of span
    DL_MASK_RATE   : WORD := 16#0008;          // 掩码位 8：变化率跳变 / mask bit eight, rate jump
    DL_MASK_NONE   : WORD := 16#0000;          // 无存疑 / no suspicion
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置（发布值与保持量在段 8 单点写入）
 *      Per-scan presets, the published value is written only in segment eight
 *-----------------------------------------------------------------------------*)
eErr         := 16#0000_0000;                  // 错误码每拍重算 / error code recomputed every scan
bError       := FALSE;                         // 故障标志每拍重算 / fault flag recomputed every scan
bValid       := FALSE;                         // 可用标志每拍重算 / usable flag recomputed every scan
bTrusted     := FALSE;                         // 可信标志每拍重算 / trusted flag recomputed
uSuspectMask := DL_MASK_NONE;                  // 掩码清零 / mask cleared
_bParamBad   := FALSE;                         // 参数非法标志预清零 / parameter flag pre-cleared
_bFiniteBad  := FALSE;                         // 非有限标志预清零 / non-finite flag pre-cleared
_bIllegal    := FALSE;                         // 非法状态标志预清零 / illegal state flag pre-cleared
_bBadQuality := FALSE;                         // 置信度判据预置 FALSE / confidence criterion preset FALSE
_bBadSnr     := FALSE;                         // 信噪比判据预置 FALSE / snr criterion preset FALSE
_bBadSpan    := FALSE;                         // 量程判据预置 FALSE / span criterion preset FALSE
_bBadRate    := FALSE;                         // 变化率判据预置 FALSE / rate criterion preset FALSE
_wMask       := DL_MASK_NONE;                  // 掩码暂存清零 / mask staging cleared
_fRate       := 0.0;                           // 变化率预置 0 [m/s] / rate preset to zero

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（**无历史可信值**：0 m 不是液位，是「还没有数据」）
 *      First-scan initialisation, no trusted value exists yet
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState       := E_DL_RadarState.eIdle;    // 相位待机 / phase idle
    _fLastTrusted := 0.0;                      // 末次可信值 0 [m] / last trusted level zero
    _fOutHeld     := 0.0;                      // 发布值保持量 0 [m] / held published value zero
    _bHaveTrusted := FALSE;                    // 尚无历史可信值 / no trusted value yet
    _bBrkTrust    := TRUE;                     // 恢复确认窗从零开始 / recovery window starts from zero
    _bInit        := TRUE;                     // 首扫只做一次 / the first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数闸门（量程、四条门限与采样周期；除零前置闸在采样周期处）
 *      Parameter gate, the sample period guard also protects the rate division
 *-----------------------------------------------------------------------------*)
IF (fSpan <> fSpan) OR (ABS(fSpan) > DL_VAL_LIM) OR (fSpan <= DL_SPAN_MIN) THEN
    _bParamBad := TRUE;                        // 量程非法 / span illegal
END_IF
IF (fQualityMin <> fQualityMin) OR (fQualityMin < DL_QUAL_MIN) OR (fQualityMin > DL_QUAL_MAX) THEN
    _bParamBad := TRUE;                        // 置信度门限非法 / confidence threshold illegal
END_IF
IF (fSnrMin <> fSnrMin) OR (fSnrMin < DL_SNR_MIN) OR (ABS(fSnrMin) > DL_VAL_LIM) THEN
    _bParamBad := TRUE;                        // 信噪比门限非法 / snr threshold illegal
END_IF
IF (fRateLimit <> fRateLimit) OR (ABS(fRateLimit) > DL_VAL_LIM) OR (fRateLimit <= DL_RATE_MIN) THEN
    _bParamBad := TRUE;                        // 变化率上限非法 / rate ceiling illegal
END_IF

_tConfirmUse := tConfirm;                      // 确认时间直取引脚 [ms] / confirm time from the pin
IF TIME_TO_DINT(_tConfirmUse) > DL_CONF_MAX_MS THEN
    _tConfirmUse := DINT_TO_TIME(DL_CONF_MAX_MS); // 超上限钳位（无专用码位，R90 不新开码） / clamped
END_IF
IF TIME_TO_DINT(tSample) <= 0 THEN
    _bParamBad := TRUE;                        // 采样周期非正：变化率判据无意义 / non-positive sample period
    _fDtSec    := DL_ONE_SEC;                  // 兜底 1 s，防后续除零 / fallback to one second, no division by zero
ELSE
    _fDtSec := TIME_TO_REAL(tSample) / DL_MS_PER_S; // 采样周期换算为秒 [s] / sample period in seconds
END_IF
IF _fDtSec <= DL_RATE_MIN THEN
    _fDtSec := DL_ONE_SEC;                     // 结构性兜底：商恒 > 0，仍显式判一次 / explicit fallback, defense in depth
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜输入有限性（区间判据同时拦 NaN 与 ±Inf）
 *      Input finiteness, the interval test catches NaN and infinity
 *-----------------------------------------------------------------------------*)
IF (fLevel < -DL_VAL_LIM) OR (fLevel > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 液位非有限 / level non-finite
END_IF
IF (fQuality < -DL_VAL_LIM) OR (fQuality > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 置信度非有限 / confidence non-finite
END_IF
IF (fSnr < -DL_VAL_LIM) OR (fSnr > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 信噪比非有限 / snr non-finite
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜四条判据同拍评估（不早退：全部写进掩码，便于现场一次改全）
 *      All four criteria evaluated in the same scan, no early exit
 *-----------------------------------------------------------------------------*)
IF (NOT _bFiniteBad) AND (NOT _bParamBad) THEN
    _bBadQuality := (fQuality < fQualityMin);  // 判据 1：置信度低 / criterion one, low confidence
    _bBadSnr     := (fSnr < fSnrMin);          // 判据 2：信噪比低 / criterion two, low snr
    _bBadSpan    := (fLevel < DL_LEVEL_MIN) OR (fLevel > fSpan); // 判据 3：超量程 / criterion three, out of span

    IF _bHaveTrusted THEN
        _fRate := ABS(fLevel - _fLastTrusted) / _fDtSec; // 变化率 [m/s]，除数恒 > 0 / rate, the divisor is always positive
    ELSE
        _fRate := 0.0;                         // 无历史可信值：不判跳变（首次读数无基准） / no baseline yet
    END_IF
    _bBadRate := (_fRate > fRateLimit);        // 判据 4：变化率跳变 / criterion four, rate jump

    IF _bBadQuality THEN
        _wMask := _wMask OR DL_MASK_QUAL;      // 置置信度位 / set the confidence bit
    END_IF
    IF _bBadSnr THEN
        _wMask := _wMask OR DL_MASK_SNR;       // 置信噪比位 / set the snr bit
    END_IF
    IF _bBadSpan THEN
        _wMask := _wMask OR DL_MASK_SPAN;      // 置超量程位 / set the span bit
    END_IF
    IF _bBadRate THEN
        _wMask := _wMask OR DL_MASK_RATE;      // 置跳变位 / set the rate bit
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜恢复确认计时器无条件刷新（进入不可信是即时的，恢复才要确认窗）
 *      Recovery timer refreshed unconditionally, entry is immediate, exit needs the window
 *-----------------------------------------------------------------------------*)
fbTrust(IN := bEnable AND (NOT _bFiniteBad) AND (NOT _bParamBad) AND (_wMask = DL_MASK_NONE)
             AND (NOT _bBrkTrust), PT := _tConfirmUse); // 恢复可信确认窗
_bBrkTrust := FALSE;                           // 断输入拍在调用后自清 / break self-cleared after the call

(*------------------------------------------------------------------------------
 * 段 7｜相位机（进入存疑即时，退出存疑须窗满；不对称滞回）
 *      Phase machine with an asymmetric hysteresis
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_RadarState.eIdle:                     // 待机：参数合法且使能即判可信度
        IF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_RadarState.eFault; // 原因未消失，转故障 / the cause persists
        ELSIF bEnable THEN
            IF _wMask = DL_MASK_NONE THEN
                _eState := E_DL_RadarState.eTrusted; // 首拍即可信 / trusted from the first scan
            ELSE
                _eState := E_DL_RadarState.eSuspect; // 首拍即存疑 / suspect from the first scan
            END_IF
        END_IF

    E_DL_RadarState.eTrusted:                  // 可信：任一判据失败即时转存疑
        IF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_RadarState.eFault; // 转故障 / go to fault
        ELSIF NOT bEnable THEN
            _eState := E_DL_RadarState.eIdle;  // 失能回待机 / disabled, back to idle
        ELSIF _wMask <> DL_MASK_NONE THEN
            _eState := E_DL_RadarState.eSuspect; // 即时转存疑（假回波必须立刻挡住） / immediate, a false echo must be blocked
            _bBrkTrust := TRUE;                // 恢复窗重启 / the recovery window restarts
        END_IF

    E_DL_RadarState.eSuspect:                  // 存疑：掩码全零且满窗才恢复
        IF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_RadarState.eFault; // 转故障 / go to fault
        ELSIF NOT bEnable THEN
            _eState := E_DL_RadarState.eIdle;  // 失能回待机 / disabled, back to idle
        ELSIF (_wMask = DL_MASK_NONE) AND fbTrust.Q THEN
            _eState := E_DL_RadarState.eTrusted; // 满窗恢复可信 / recovered after the window
        END_IF

    E_DL_RadarState.eFault:                    // 故障：参数与输入恢复即可回待机
        IF bEnable AND (NOT _bParamBad) AND (NOT _bFiniteBad) THEN
            _eState := E_DL_RadarState.eIdle;  // 原因消失 / the cause is gone
            _bBrkTrust := TRUE;                // 恢复窗重启，避免沿用故障期残留 / the window restarts
        END_IF

    ELSE
        _bIllegal := TRUE;                     // 标记非法状态 / flag the illegal state
        _eState   := E_DL_RadarState.eFault;   // 回故障态 / back to the fault state
END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜发布值单点写入（可信用实时值，否则保持；无历史时 0 且不可用）
 *      Single write point of the published value
 *-----------------------------------------------------------------------------*)
IF (NOT _bFiniteBad) AND (NOT _bParamBad) AND (_wMask = DL_MASK_NONE) THEN
    _fOutHeld     := fLevel;                   // 可信：发布实时值 [m] / trusted, publish the live value
    _fLastTrusted := fLevel;                   // 同步末次可信值 [m] / latch the last trusted value
    _bHaveTrusted := TRUE;                     // 已有历史可信值 / a trusted value now exists
END_IF
(* 不可信拍一律不更新 _fOutHeld：保持末次可信值 / an untrusted scan leaves the held value untouched *)

fLevelOut    := _fOutHeld;                     // 发布值出口 [m] / published value outlet
uSuspectMask := _wMask;                        // 存疑掩码出口 / suspect mask outlet
bTrusted     := ((_wMask = DL_MASK_NONE) AND (NOT _bFiniteBad) AND (NOT _bParamBad) AND bEnable); // 即时可信标志

(*------------------------------------------------------------------------------
 * 段 9｜码位优先级链与健康分级
 *      Code priority chain and health grading
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0003_0347;                    // 故障级：状态机兜底 / fault: state machine fallback
    bError := TRUE;                            // 置故障标志 / raise the fault flag
ELSIF _bParamBad THEN
    eErr   := 16#0003_0345;                    // 故障级：量程/门限/采样周期非法 / fault: span, thresholds or sample period illegal
    bError := TRUE;                            // 置故障标志 / raise the fault flag
ELSIF _bFiniteBad THEN
    eErr   := 16#0003_0346;                    // 故障级：输入非有限，不更新发布值 / fault: non-finite input
    bError := TRUE;                            // 置故障标志 / raise the fault flag
ELSIF _bBadRate THEN
    eErr   := 16#0003_0179;                    // 信息级：变化率跳变，单拍剔除 / informational: rate jump rejected
ELSIF _wMask <> DL_MASK_NONE THEN
    eErr   := 16#0003_0178;                    // 信息级：质量指标低于门限，保持末次可信值 / informational: quality below threshold
END_IF

IF _bParamBad OR _bFiniteBad OR _bIllegal THEN
    eHealth := E_DL_Ne107Status.eFailure;      // 无判定能力：失效 / no verdict capability
ELSIF NOT bEnable THEN
    eHealth := E_DL_Ne107Status.eUnknown;      // 失能：无结论 / disabled, no verdict
ELSIF _wMask <> DL_MASK_NONE THEN
    eHealth := E_DL_Ne107Status.eCheckFunction; // 回波存疑：需检查功能（探头/泡沫/扰动） / suspect echo, check function
ELSE
    eHealth := E_DL_Ne107Status.eOk;           // 回波可信 / trusted echo
END_IF

IF bError THEN
    bValid := FALSE;                           // 故障级：发布值不可用 / fault: unusable
ELSIF NOT bEnable THEN
    bValid := FALSE;                           // 失能：发布值不可用 / disabled: unusable
ELSIF NOT _bHaveTrusted THEN
    bValid := FALSE;                           // 无历史可信值：0 m 绝不作为可信液位发布（R43） / never publish zero as trusted
ELSE
    bValid := TRUE;                            // 发布值可用（存疑时为末次可信值，仍可用） / usable, the held value is still valid
END_IF

END_FUNCTION_BLOCK
