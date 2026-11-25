// FB_DL_SensorGlitchFilter v1.0.0
// 开源溯源：来源 brOscatLib / URL https://github.com/iec-oscat-mirror / 许可证 MIT / 借鉴点 FT_IMP 一阶惯性滤波语义
(*==============================================================================
 * 功能描述: 传感器毛刺滤波单件。|Δ| > fGlitchBand 计为疑似毛刺并计数，连续超
 *           nFollowCnt 拍才跟随（真实阶跃），否则保持上一拍值并置 bGlitch；正常域
 *           内以一阶惯性 fAlpha 平滑跟随。非有限输入防御（保持 + bValid=FALSE），
 *           组态非法（带宽/惯性系数/计数域）防御。
 * 接口契约: 输入 fRaw/fGlitchBand/nFollowCnt/fAlpha/bEnable；
 *           输出 fFiltered/bValid/bGlitch。
 * 边界: 零定时器零沿实例（纯逐拍滤波），零全局耦合；bEnable=FALSE 时输出冻结保持。
 * 修订历史: 2026-11-23  v1.0.0  R74 首版
 *==============================================================================*)

FUNCTION_BLOCK FB_DL_SensorGlitchFilter
VAR_INPUT
    fRaw        : REAL := 0.0;     // 原始采样输入 [工程单位] / Raw sample input
    fGlitchBand : REAL := 1.0;     // 毛刺判别带宽，域 > 0 [工程单位/拍] / Glitch band [unit/scan]
    nFollowCnt  : INT := 3;        // 疑似毛刺连续计数门槛（超 N 拍才跟随）[拍] / Consecutive count threshold [scan]
    fAlpha      : REAL := 0.2;     // 一阶惯性平滑系数，域 (0,1] [-] / First-order smoothing factor
    bEnable     : BOOL := TRUE;    // 使能（FALSE 输出冻结保持）[-] / Enable, FALSE freezes output
END_VAR
VAR_OUTPUT
    fFiltered : REAL := 0.0;       // 滤波输出 [工程单位] / Filtered output
    bValid    : BOOL;              // 输出有效回执（首拍后为真）[-] / Output validity receipt
    bGlitch   : BOOL;              // 本拍毛刺判别标志（未跟随即真）[-] / Glitch flag this scan
END_VAR
VAR
    _fLast  : REAL := 0.0;         // 上一拍跟随值（锁存量）[工程单位] / Last followed value
    _nCnt   : INT := 0;            // 疑似毛刺连续计数（锁存量）[拍] / Consecutive glitch count
    _bInit  : BOOL := FALSE;       // 首拍初始化标志（锁存量） / First-scan init flag
    _fDelta : REAL := 0.0;         // 本拍增量 [工程单位] / Increment this scan
    _bCfgBad: BOOL;                // 组态非法当拍量 [-] / Illegal configuration this scan
    _bNonFin: BOOL;                // 输入非有限当拍量 [-] / Non-finite input this scan
END_VAR

(* —— 段 0：单拍量预清零（锁存量 _fLast/_nCnt/_bInit 不入清单） —— *)
bValid := FALSE;                             // 有效回执预清 / Validity preset
bGlitch := FALSE;                            // 毛刺标志预清 / Glitch preset

(* —— 段 1：组态域闸与非有限闸（覆盖全部参与引脚） —— *)
_bCfgBad := (fGlitchBand <= 0.0) OR (fGlitchBand <> fGlitchBand)   // 带宽域与 NaN 闸 / Band domain and NaN gate
         OR (nFollowCnt < 1)                            // 计数域闸 / Count domain gate
         OR (fAlpha <= 0.0) OR (fAlpha > 1.0) OR (fAlpha <> fAlpha);   // 惯性系数域与 NaN 闸 / Alpha domain and NaN gate
_bNonFin := fRaw <> fRaw;                    // 输入 NaN 自反判 / Input NaN test

(* —— 段 2：滤波主体（首拍直取；毛刺判别 → 计数 → 跟随/保持；全部逐拍无状态残留） —— *)
IF (NOT bEnable) OR _bCfgBad OR _bNonFin THEN   // 非使能/组态坏/非有限：输出冻结保持 / Frozen hold paths
    IF _bNonFin THEN                         // 非有限输入明确不宣称有效 / Non-finite invalidates receipt
        bValid := FALSE;
    ELSE
        bValid := _bInit;                    // 冻结保持沿用首拍后有效性 / Frozen hold keeps receipt
    END_IF
ELSIF NOT _bInit THEN                        // 首拍：直取输入建立基线 / First scan seeds the baseline
    _fLast := fRaw;                          // 基线装载 / Baseline seeded
    _bInit := TRUE;                          // 首拍完成 / First scan done
    _nCnt := 0;                              // 计数清零 / Count cleared
    fFiltered := _fLast;                     // 输出首拍值 / Output first value
    bValid := TRUE;                          // 有效回执 / Validity receipt
ELSE
    _fDelta := fRaw - _fLast;                // 本拍增量 [工程单位] / Increment this scan
    IF ABS(_fDelta) > fGlitchBand THEN       // 超带宽疑似毛刺 / Over band, suspected glitch
        IF _nCnt < 32000 THEN _nCnt := _nCnt + 1; END_IF   // 连续计数递增（饱和钳位防 INT 回绕） / Count up with saturation clamp
        IF _nCnt >= nFollowCnt THEN          // 连续超 N 拍 → 判真实阶跃，跟随 / Real step, follow
            _fLast := fRaw;                  // 跟随装载 / Follow the input
            _nCnt := 0;                      // 计数归零 / Count reset
            fFiltered := _fLast;             // 输出跟随值 / Output follows
            bGlitch := FALSE;                // 非毛刺（已确认为阶跃） / Not a glitch anymore
        ELSE
            bGlitch := TRUE;                 // 未达计数 → 保持并报毛刺 / Hold and flag glitch
            fFiltered := _fLast;             // 输出保持上一拍 / Output holds last
        END_IF
    ELSE
        _nCnt := 0;                          // 带宽内计数归零 / Within band, count reset
        _fLast := _fLast + fAlpha * (fRaw - _fLast);   // 一阶惯性平滑跟随 / First-order smoothing follow
        fFiltered := _fLast;                 // 输出平滑值 / Output smoothed value
    END_IF
    bValid := TRUE;                          // 有效回执 / Validity receipt
END_IF

END_FUNCTION_BLOCK
