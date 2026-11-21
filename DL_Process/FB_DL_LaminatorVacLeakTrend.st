(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LaminatorVacLeakTrend
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，零方言）
 * 功能描述 (Function)   : 真空泄漏率趋势诊断。仅在保压段按采样周期求压强上升速率，与
 *                         滑动基线和绝对上限比较：越基线预警、越绝对上限报警。真空**上升**
 *                         （负泄漏）不刷新基线——放气会把基线抬高，真泄漏将永不报警；基线
 *                         未满样本数时绝对报警恒不置位（不给未标定报警）。不做保压段判定
 *                         本身（由引脚注入）、不做抽气曲线包络、不做阀门控制。
 *                         交付门槛：速率换算用时间转换链，须在 CODESYS / TwinCAT / InoProShop
 *                         三平台各编译验证一次。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_LeakState / FUNCTION_BLOCK FB_DL_LaminatorVacLeakTrend
 * 依赖 (Depends)        : 无（仅 Standard.library 的 ABS / TIME_TO_LREAL）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         采样周期与上限判零防除零 ｜ 速率非有限即跳过并报信息级 ｜ 基线只
 *                         在正泄漏时刷新 ｜ 采样定时器无条件周期刷新 ｜ 枚举显式赋值 ｜ CASE 含 ELSE
 * 错误码表 (Codes)      : 16#0005_0430 就绪（无越限或非保压段）
 *                         16#0005_0431 信息级 基线样本未满，绝对报警暂不置位（不置故障级标志）
 *                         16#0005_0432 故障级 组态非法（上限 ≤0、基线倍率出域、样本数 <3、采样周期出域）
 *                         16#0005_0433 预留：本版不发码（下一轮区间起点，禁止回填）
 *                         16#0005_0434 信息级 速率非有限，本拍跳过（基线不刷新）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 3
 * 验收向量 (Acceptance) : 正向 1.0→1.05 kPa/60 s（0.05 kPa/min）、上限 0.1 → 不报警
 *                         反向 1.0→1.5 kPa/60 s（0.5 kPa/min）超上限 0.1 → bLeakAlarm；基线
 *                         0.02、当前 0.06（3 倍 > 倍率 1.1）→ bLeakWarn；上限给 0 →
 *                         16#0005_0432；压强给 NaN → 16#0005_0434 且基线不刷新
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_LeakState（归属本功能块，同文件发布，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_LeakState :
(
    eWait  := 0,    // 等待：非保压段或首样本未到 / Waiting, not in the hold phase or no first sample yet
    eTrack := 10,   // 跟踪：按采样周期求速率 / Tracking, the rate is computed per sample period
    eFault := 99    // 故障：组态非法锁存 / Fault, the configuration error is latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_LaminatorVacLeakTrend
VAR_INPUT
    bEnable        : BOOL := FALSE;       // 使能 / Enable
    bHoldPhase     : BOOL := FALSE;       // 保压段有效（仅此段计速率） / Hold phase active, the rate is computed here only
    fVac_kPa       : REAL := 1.0;         // 腔体真空 [kPa(abs)] / Chamber vacuum in kilopascal absolute
    tSampleTime    : TIME := T#100MS;     // 采样周期 [ms]，域 10~1000 / Sampling period, domain 10 to 1000 ms
    fLeakRateMax_kPamin : REAL := 0.1;    // 绝对上限 [kPa/min]，域 0.001~10 / Absolute limit, domain 0.001 to 10
    fBaseK         : REAL := 1.5;         // 基线倍率 [—]，域 1.1~5.0 / Baseline multiplier, domain 1.1 to 5.0
    uBaseSamples   : UINT := 5;           // 基线样本数 [个]，域 3~20 / Baseline sample count, domain 3 to 20
END_VAR
VAR_OUTPUT
    fLeakRate_kPamin  : REAL;             // 当前泄漏率 [kPa/min] / Current leak rate
    fLeakBase_kPamin  : REAL;             // 基线泄漏率 [kPa/min] / Baseline leak rate
    bLeakWarn      : BOOL;                // 越基线预警 / Above the baseline
    bLeakAlarm     : BOOL;                // 越绝对上限报警 / Above the absolute limit
    bError         : BOOL;                // 故障级标志，仅故障级码置位 / Fault-class flag, set on fault codes only
    eErr           : UDINT;               // 错误码，段位 16#0005_xxxx / Error code in segment 16#0005_xxxx
END_VAR
VAR
    _eState        : E_DL_LeakState := E_DL_LeakState.eWait; // 当前相位 / Current phase
    _bInit         : BOOL := FALSE;       // 首扫标志，取非判定 / First-scan flag, tested negated
    _bCfgOk        : BOOL;                // 组态合法标志 / Configuration valid flag
    _bHasSample    : BOOL := FALSE;       // 已有上一拍样本标志 / A previous sample exists
    _bFaultLatch   : BOOL := FALSE;       // 组态故障锁存 / Configuration fault latch
    _fPrev_kPa     : REAL := 0.0;         // 上一拍压强 [kPa(abs)] / Previous pressure sample
    _fDelta        : REAL;                // 本拍压强增量 [kPa] / Pressure increment of this scan
    _fMinSpan      : REAL := 0.1;         // 采样周期换算分钟 [min] / Sampling period in minutes
    _afBase        : ARRAY[1..20] OF REAL; // 基线样本环形表 [kPa/min] / Baseline ring buffer
    _uBaseIdx      : UINT := 1;           // 基线下标 / Baseline index
    _uBaseFill     : UINT := 0;           // 基线已填样本数 [个] / Number of baseline samples collected
    _fBaseSum      : REAL := 0.0;         // 基线样本和 [kPa/min] / Baseline sample sum
    _rtrigSample   : R_TRIG;              // 采样节拍上升沿 / Rising edge of the sample tick
    _tonSample     : TON;                 // 采样周期计时（自复位） / Sampling period timer, self resetting
END_VAR
VAR CONSTANT
    DL_LK_READY    : UDINT := 16#0005_0430;  // 就绪码 / Ready code
    DL_LK_BASE_OFF : UDINT := 16#0005_0431;  // 信息级基线未满码 / Info code for an incomplete baseline
    DL_LK_CFG_BAD  : UDINT := 16#0005_0432;  // 故障级组态非法码 / Fault code for bad configuration
    DL_LK_SKIP     : UDINT := 16#0005_0434;  // 信息级速率非有限码 / Info code for a non-finite rate
    DL_LK_SMP_LO   : TIME := T#10MS;         // 采样周期下限 / Sampling period lower bound
    DL_LK_SMP_HI   : TIME := T#1000MS;       // 采样周期上限 / Sampling period upper bound
    DL_LK_RATE_LO  : REAL := 0.001;          // 绝对上限下限 [kPa/min] / Absolute limit lower bound
    DL_LK_RATE_HI  : REAL := 10.0;           // 绝对上限上限 [kPa/min] / Absolute limit upper bound
    DL_LK_BASEK_LO : REAL := 1.1;            // 基线倍率下限 / Baseline multiplier lower bound
    DL_LK_BASEK_HI : REAL := 5.0;            // 基线倍率上限 / Baseline multiplier upper bound
    DL_LK_SMP_MIN  : UINT := 3;              // 基线最少样本数 [个] / Minimum baseline samples
    DL_LK_SMP_MAX  : UINT := 20;             // 基线最多样本数 [个] / Maximum baseline samples
END_VAR

// 段 1｜输出与单拍标志预置
bLeakWarn := FALSE;                                 // 预警标志预清 / Warning flag pre-cleared
bLeakAlarm := FALSE;                                // 报警标志预清 / Alarm flag pre-cleared
bError := FALSE;                                    // 故障标志预清 / Fault flag pre-cleared
eErr := 0;                                          // 错误码预清 / Error code pre-cleared

// 段 2｜采样定时器与沿实例无条件周期刷新（自复位）
_tonSample(IN := bEnable AND bHoldPhase AND (NOT _tonSample.Q), PT := tSampleTime);
_rtrigSample(CLK := _tonSample.Q);                  // 采样节拍沿 / Sample tick edge

// 段 3｜首扫初始化（判据取非，R19）
IF NOT _bInit THEN
    _eState := E_DL_LeakState.eWait;                // 相位待机起步 / Phase starts waiting
    _bInit := TRUE;                                 // 首扫只做一次 / The first scan runs once
END_IF

// 段 4｜组态闸（上限与采样周期判零防除零）
_bCfgOk := NOT ((fLeakRateMax_kPamin <> fLeakRateMax_kPamin) OR ((fLeakRateMax_kPamin - fLeakRateMax_kPamin) <> (fLeakRateMax_kPamin - fLeakRateMax_kPamin)))
        AND (fLeakRateMax_kPamin >= DL_LK_RATE_LO) AND (fLeakRateMax_kPamin <= DL_LK_RATE_HI)
        AND (fBaseK >= DL_LK_BASEK_LO) AND (fBaseK <= DL_LK_BASEK_HI)
        AND (uBaseSamples >= DL_LK_SMP_MIN) AND (uBaseSamples <= DL_LK_SMP_MAX)
        AND (tSampleTime >= DL_LK_SMP_LO) AND (tSampleTime <= DL_LK_SMP_HI);
IF NOT _bCfgOk THEN
    _bFaultLatch := TRUE;                           // 组态故障锁存 / Configuration fault latched
    eErr := DL_LK_CFG_BAD;                          // 故障级：组态非法 / Fault, bad configuration
    bError := TRUE;
    _eState := E_DL_LeakState.eFault;
END_IF
_fMinSpan := TIME_TO_LREAL(tSampleTime) / 60000.0;  // 采样周期换算分钟 [min] / Sampling period in minutes
IF _fMinSpan < 0.00001 THEN
    _fMinSpan := 0.00001;                           // 换算兜底下限 [min] / Conversion lower bound guard
END_IF

// 段 5｜基线未满闸（不给未标定报警）
IF _uBaseFill < uBaseSamples THEN
    eErr := DL_LK_BASE_OFF;                         // 信息级：基线未满，绝对报警暂不置位 / Info, the baseline is incomplete
END_IF

// 段 6｜速率求取（仅保压段 + 采样沿；非有限即跳过，基线不刷新）
CASE _eState OF
    E_DL_LeakState.eWait:
        IF bHoldPhase AND bEnable THEN
            _bHasSample := FALSE;                   // 新保压段：丢弃上一段样本 / New hold phase, drop the previous sample
            _eState := E_DL_LeakState.eTrack;
        END_IF
    E_DL_LeakState.eTrack:
        IF (NOT bHoldPhase) OR (NOT bEnable) THEN
            _bHasSample := FALSE;                   // 保压结束：样本作废 / Hold finished, the sample is dropped
            _eState := E_DL_LeakState.eWait;
        ELSIF _rtrigSample.Q THEN
            IF (fVac_kPa <> fVac_kPa) OR ((fVac_kPa - fVac_kPa) <> (fVac_kPa - fVac_kPa)) THEN
                eErr := DL_LK_SKIP;                 // 信息级：压强非有限，本拍跳过 / Info, the pressure is not finite
            ELSIF _bHasSample THEN
                _fDelta := fVac_kPa - _fPrev_kPa;           // 压强增量（正 = 泄漏上升）[kPa] / Pressure increment, positive means a leak
                fLeakRate_kPamin := (_fDelta / _fMinSpan);  // 泄漏率 [kPa/min] / Leak rate
                IF _fDelta > 0.0 THEN
                    // 正泄漏才刷新基线：真空上升（负泄漏）不刷基线，否则真泄漏永不报警
                    _fBaseSum := _fBaseSum - _afBase[_uBaseIdx];          // 换出最旧样本 [kPa/min] / Remove the oldest sample
                    _afBase[_uBaseIdx] := fLeakRate_kPamin;               // 写入新样本 [kPa/min] / Insert the new sample
                    _fBaseSum := _fBaseSum + fLeakRate_kPamin;            // 样本和更新 [kPa/min] / Update the sum
                    _uBaseIdx := _uBaseIdx + 1;
                    IF _uBaseIdx > DL_LK_SMP_MAX THEN
                        _uBaseIdx := 1;                                   // 环形回卷 / Ring wrap
                    END_IF
                    IF _uBaseFill < uBaseSamples THEN
                        _uBaseFill := _uBaseFill + 1;                     // 已填样本数 +1 [个] / Sample count incremented
                    END_IF
                    IF _uBaseFill > 0 THEN
                        fLeakBase_kPamin := _fBaseSum / UINT_TO_REAL(_uBaseFill);   // 基线均值 [kPa/min] / Baseline mean
                    END_IF
                END_IF
            END_IF
            _fPrev_kPa := fVac_kPa;                 // 样本快照（唯一写点） / Sample snapshot, the single write point
            _bHasSample := TRUE;
        END_IF
    E_DL_LeakState.eFault:
        eErr := DL_LK_CFG_BAD;                      // 故障级：组态非法保持 / Fault, the configuration error is held
        bError := TRUE;
        IF bEnable AND _bCfgOk AND (NOT bHoldPhase) THEN
            _bFaultLatch := FALSE;                  // 组态修正且退出保压后解除 / Released after the configuration is fixed and the hold phase ends
            _eState := E_DL_LeakState.eWait;
        END_IF
    ELSE
        // 非法相位兜底（故障级）
        eErr := DL_LK_CFG_BAD;
        bError := TRUE;
        _eState := E_DL_LeakState.eFault;
END_CASE

// 段 7｜判据比较（基线未满时绝对报警恒 FALSE）
IF _uBaseFill >= uBaseSamples THEN
    IF fLeakRate_kPamin > fLeakRateMax_kPamin THEN
        bLeakAlarm := TRUE;                         // 越绝对上限报警 / Above the absolute limit
    END_IF
END_IF
IF (_uBaseFill >= uBaseSamples) AND (fLeakBase_kPamin > 0.0) THEN
    IF fLeakRate_kPamin > (fLeakBase_kPamin * fBaseK) THEN
        bLeakWarn := TRUE;                          // 越基线倍率预警 / Above the baseline multiplier
    END_IF
END_IF
IF (NOT bLeakAlarm) AND (NOT bLeakWarn) AND (eErr = 0) THEN
    eErr := DL_LK_READY;                            // 无越限回就绪码 / Ready code when nothing exceeds
END_IF
END_FUNCTION_BLOCK
