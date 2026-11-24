(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CheckweighZeroTrack
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，零方言）
 * 功能描述 (Function)   : 动态称重零点跟踪与温漂补偿。仅在「空载且无冲击且连续静载满
 *                         静载稳定窗」时更新零点，零点取中值滤波后的原始重量；温漂量按
 *                         (温度 − 标定温度) × 温漂系数 求取并作为诊断量与超限判据输出。
 *                         净重 = 原始重量 − 零点。不做称重采样本身、不做动态滤波调参、
 *                         不做多秤头合并。
 *                         设计反证：温漂量只作为诊断量输出、**不**在净重里二次扣减——零点
 *                         跟踪已把当时的原始值吃进零点，二次扣减会让同一次温漂被扣两遍，
 *                         空载净重出现 ±温漂量 的假残差（本例 0.2 g），正好把真故障掩盖。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_ZeroTrackState / FUNCTION_BLOCK FB_DL_CheckweighZeroTrack
 * 依赖 (Depends)        : DL_MathData/FB_DL_MedianFilter（只调用，不复制其内核）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         零点漂移限判零防除零 ｜ 非有限用自反比较且保持上次补偿值 ｜
 *                         静载窗定时器与沿实例无条件周期刷新 ｜ 枚举显式赋值 ｜ CASE 含 ELSE
 *                         冻结状态量带解除路径（失能一拍解除），无只置不销状态
 * 错误码表 (Codes)      : 16#0003_03A7 就绪（跟踪正常，含零点未更新但无故障）
 *                         16#0003_03A8 故障级 输入/组态非法（温度非有限、漂移限 ≤0、稳定窗
 *                                    出域）。反证句：温度丢值与「真实 0 ℃ 冷库工况」在数值
 *                                    上同为 0，只能靠非有限判据区分，故必须独立成码
 *                         16#0003_03A9 故障级 相对标定累计漂移超限，零点跟踪冻结（继续跟踪
 *                                    会把误差吃进零点）。反证句：超限事实无法由 03AA「窗未
 *                                    满足」观测，故独立成码
 *                         16#0003_03AA 信息级 跟踪窗未满足，零点保持（不置故障级标志）
 *                         16#0003_03AB 预留：本版不发码（下一轮区间起点，禁止回填）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 1
 * 验收向量 (Acceptance) : 正向 空载原始 200.0 g 连续静载 1 s、温度 20→30 ℃、系数
 *                         0.02 g/K → 漂移 +0.2 g、零点取 200.0 g、净重 0.0 g、跟踪计数 +1
 *                         反向 空载判据为假且放 500 g 砝码 30 s → 零点不动、净重 500 g；
 *                         温度给 NaN → 16#0003_03A8 且漂移量保持上次值；漂移限给 0 →
 *                         16#0003_03A8；漂移 0.2 g 超限 0.1 g → 16#0003_03A9 且跟踪冻结
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ZeroTrackState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 零点跟踪相位，每个成员在 CASE 中有且仅有一个标签。
 *----------------------------------------------------------------------------*)
TYPE E_DL_ZeroTrackState :
(
    eIdle    := 0,    // 未跟踪：窗条件不满足或禁用 / Not tracking, the window condition is unsatisfied or the function is disabled
    eWatching := 10,  // 窗口计时中：静载计时未满 / Watching, the static window is still counting
    eTracked := 20,   // 本窗已落零点：等条件消失后再开新窗 / Zero latched for this window, waiting for the condition to disappear
    eFrozen  := 99    // 冻结：漂移超限，零点禁止更新 / Frozen, the drift limit was exceeded and the zero must not be updated
);
END_TYPE

FUNCTION_BLOCK FB_DL_CheckweighZeroTrack
VAR_INPUT
    bEnable        : BOOL := FALSE;       // 使能 / Enable
    fWeightRaw_g   : REAL := 0.0;         // 原始毛重 [g]，域 ±50000 / Raw gross weight in grammes, domain plus minus 50000
    bBeltEmpty     : BOOL := FALSE;       // 空载判据（皮带无料） / Belt empty criterion
    bShockActive   : BOOL := FALSE;       // 冲击抑制窗有效（本拍禁止跟踪） / Shock suppression window active, tracking forbidden
    tStableWin     : TIME := T#1S;        // 静载稳定窗 [ms]，域 200ms~10s / Static stability window, domain 200 ms to 10 s
    fTemp_C        : REAL := 20.0;        // 传感器温度 [℃]，域 -20~80 / Sensor temperature in degrees Celsius, domain minus 20 to 80
    fTempRef_C     : REAL := 20.0;        // 标定温度 [℃]，域 -20~80 / Calibration temperature in degrees Celsius
    fDriftCoef_gK  : REAL := 0.02;        // 温漂系数 [g/K]，域 ±0.5 / Temperature drift coefficient in grammes per kelvin, domain plus minus 0.5
    fZeroDevMax_g  : REAL := 5.0;         // 零点漂移限 [g]，域 0.1~50 / Zero drift limit in grammes, domain 0.1 to 50
END_VAR
VAR_OUTPUT
    fZeroOut_g     : REAL;                // 当前零点 [g] / Current zero offset in grammes
    fNetOut_g      : REAL;                // 去皮净重 [g] / Net weight after tare in grammes
    bInWindow      : BOOL;                // 处于合法跟踪窗 / Inside the legal tracking window
    uTrackCnt      : UDINT;               // 零点更新次数 [次] / Zero update count
    fDriftTotal_g  : REAL;                // 相对标定累计温漂 [g]（诊断量，不在净重里二次扣减） / Accumulated temperature drift in grammes, diagnostic only
    bError         : BOOL;                // 故障级标志，仅故障级码置位 / Fault-class flag, set on fault codes only
    eErr           : UDINT;               // 错误码，段位 16#0003_xxxx / Error code in segment 16#0003_xxxx
END_VAR
VAR
    _eState        : E_DL_ZeroTrackState := E_DL_ZeroTrackState.eIdle; // 当前相位 / Current phase
    _bInit         : BOOL := FALSE;       // 首扫标志，取非判定 / First-scan flag, tested negated
    _bWindowOk     : BOOL;                // 窗条件成立（空载 + 无冲击 + 使能） / Window condition satisfied
    _bFrozen       : BOOL;                // 漂移超限冻结状态量（冻结门控挂状态，不挂单拍标志） / Drift freeze state quantity, never a one-shot flag
    _bCfgOk        : BOOL;                // 组态合法标志 / Configuration valid flag
    _fZero         : REAL := 0.0;         // 零点内部副本 [g] / Internal zero offset copy
    _fDrift        : REAL := 0.0;         // 漂移内部副本（非有限时保持）[g] / Internal drift copy, held when the input is not finite
    _fSample       : REAL := 0.0;         // 参与跟踪的重量样本 [g] / Weight sample used for tracking
    _tStableWinEff : TIME := T#1S;        // 生效静载窗（域钳制后） / Effective stability window after clamping
    _tonStable     : TON;                 // 静载窗计时 / Static window timer
    _rtrigWin      : R_TRIG;              // 静载窗计时满上升沿 / Rising edge of the window-full signal
    _fbFilter      : FB_DL_MedianFilter;  // 中值滤波委托实例 / Delegated median filter instance
END_VAR
VAR CONSTANT
    DL_ZT_READY     : UDINT := 16#0003_03A7;  // 就绪码 / Ready code
    DL_ZT_INPUT_BAD : UDINT := 16#0003_03A8;  // 故障级输入/组态非法码 / Fault code for a bad input or configuration
    DL_ZT_DRIFT     : UDINT := 16#0003_03A9;  // 故障级漂移超限码 / Fault code for drift overflow
    DL_ZT_WIN_OFF   : UDINT := 16#0003_03AA;  // 信息级窗未满足码 / Info code for an unsatisfied window
    DL_ZT_WIN_LO    : TIME := T#200MS;        // 静载窗下限 / Stability window lower bound
    DL_ZT_WIN_HI    : TIME := T#10S;          // 静载窗上限 / Stability window upper bound
    DL_ZT_DEV_LO    : REAL := 0.1;            // 漂移限下限 [g] / Drift limit lower bound
    DL_ZT_DEV_HI    : REAL := 50.0;           // 漂移限上限 [g] / Drift limit upper bound
    DL_ZT_COEF_HI   : REAL := 0.5;            // 温漂系数绝对值上限 [g/K] / Absolute drift coefficient bound
    DL_ZT_TEMP_LO   : REAL := -20.0;          // 温度下限 [℃] / Temperature lower bound
    DL_ZT_TEMP_HI   : REAL := 80.0;           // 温度上限 [℃] / Temperature upper bound
END_VAR

// 段 1｜输出与单拍标志预置
bError := FALSE;                                    // 故障标志预清 / Fault flag pre-cleared
eErr := 0;                                          // 错误码预清 / Error code pre-cleared
bInWindow := FALSE;                                 // 窗标志预清 / Window flag pre-cleared

// 段 2｜沿检测无条件周期刷新（严禁置于分支内）
_rtrigWin(CLK := _tonStable.Q);                     // 静载窗计时满沿 / Window-full edge

// 段 3｜首扫初始化（判据取非，R19）：首扫以当前原始重量作为零点起点
IF NOT _bInit THEN
    _fZero := fWeightRaw_g;                         // 零点初始取当前原始值 [g] / The zero starts from the present raw value
    fZeroOut_g := _fZero;                           // 零点出口 [g] / Zero output
    _eState := E_DL_ZeroTrackState.eIdle;           // 相位待机起步 / Phase starts idle
    _bInit := TRUE;                                 // 首扫只做一次 / The first scan runs once
END_IF

// 段 3.5｜冻结解除路径（本件无独立复位引脚，约定「失能一拍」为复位路径，防状态量只置不销）
IF NOT bEnable THEN
    _bFrozen := FALSE;                              // 失能即解除冻结，再使能后重新评估漂移 / A disable pulse releases the freeze, the drift is re-evaluated after re-enabling
END_IF

// 段 4｜中值滤波委托（无条件调用；窗口 5 点，禁用拍不出新样本）
_fbFilter(fIn := fWeightRaw_g, bSample := (bEnable AND NOT bShockActive), nWindow := 5, bClear := FALSE);
_fSample := fWeightRaw_g;                           // 缺省样本取原始值 [g] / The default sample is the raw weight
IF _fbFilter.bValid THEN
    _fSample := _fbFilter.fMedian;                  // 滤波有效则取中值 [g] / Use the median when the filter is valid
END_IF

// 段 5｜组态合法性（漂移限判零防除零；稳定窗与系数出域即组态错）
_bCfgOk := NOT ((fZeroDevMax_g <> fZeroDevMax_g) OR ((fZeroDevMax_g - fZeroDevMax_g) <> (fZeroDevMax_g - fZeroDevMax_g)))
        AND (fZeroDevMax_g >= DL_ZT_DEV_LO) AND (fZeroDevMax_g <= DL_ZT_DEV_HI)
        AND (ABS(fDriftCoef_gK) <= DL_ZT_COEF_HI)
        AND (tStableWin >= DL_ZT_WIN_LO) AND (tStableWin <= DL_ZT_WIN_HI)
        AND (fTempRef_C >= DL_ZT_TEMP_LO) AND (fTempRef_C <= DL_ZT_TEMP_HI);
_tStableWinEff := LIMIT(DL_ZT_WIN_LO, tStableWin, DL_ZT_WIN_HI);   // 生效静载窗钳制 [ms] / Effective stability window after clamping

// 段 6｜温漂求取（温度非有限 → 保持上次漂移值 + 故障码，绝不写 0 掩盖故障）
IF (fTemp_C <> fTemp_C) OR ((fTemp_C - fTemp_C) <> (fTemp_C - fTemp_C)) OR (fTemp_C < DL_ZT_TEMP_LO) OR (fTemp_C > DL_ZT_TEMP_HI) THEN
    eErr := DL_ZT_INPUT_BAD;                        // 故障级：温度非有限或出域，漂移值保持上次 / Fault, temperature not finite, drift held
    bError := TRUE;
ELSE
    _fDrift := (fTemp_C - fTempRef_C) * fDriftCoef_gK;  // 相对标定温度的温漂量 [g] / Drift referred to the calibration temperature
END_IF
IF NOT _bCfgOk THEN
    eErr := DL_ZT_INPUT_BAD;                        // 故障级：组态非法 / Fault, bad configuration
    bError := TRUE;
END_IF
fDriftTotal_g := _fDrift;                           // 漂移诊断量出口 [g] / Drift diagnostic output

// 段 7｜漂移超限闸（超限即冻结零点跟踪；冻结门控挂状态量，不挂单拍标志）
IF ABS(_fDrift) > fZeroDevMax_g THEN
    _bFrozen := TRUE;                               // 冻结状态置位（状态量保持） / Freeze state set and held
    _eState := E_DL_ZeroTrackState.eFrozen;         // 相位转冻结 / Phase to frozen
    eErr := DL_ZT_DRIFT;                            // 故障级：累计漂移超限 / Fault, accumulated drift beyond the limit
    bError := TRUE;
END_IF

// 段 8｜静载窗计时无条件刷新（仅窗条件成立时计时）
_bWindowOk := bEnable AND bBeltEmpty AND (NOT bShockActive) AND _bCfgOk
          AND NOT ((fWeightRaw_g <> fWeightRaw_g) OR ((fWeightRaw_g - fWeightRaw_g) <> (fWeightRaw_g - fWeightRaw_g)));
_tonStable(IN := _bWindowOk AND (NOT _bFrozen), PT := _tStableWinEff);
bInWindow := _bWindowOk AND (NOT _bFrozen);         // 合法跟踪窗标志 / Legal tracking window flag

// 段 9｜零点跟踪状态机（ENUM + CASE + ELSE 兜底）
CASE _eState OF

    E_DL_ZeroTrackState.eIdle:                      // 未跟踪：窗条件成立则开窗计时
        IF bInWindow THEN
            _eState := E_DL_ZeroTrackState.eWatching;   // 进入窗口计时 / Enter the window counting phase
        ELSE
            IF bEnable THEN
                eErr := DL_ZT_WIN_OFF;              // 信息级：窗未满足，零点保持 / Info, the window is unsatisfied and the zero is held
            ELSE
                eErr := DL_ZT_READY;                // 禁用为正常停机 / Disable is a normal stop
            END_IF
        END_IF

    E_DL_ZeroTrackState.eWatching:                  // 窗口计时中：计时满即落零点
        IF NOT bInWindow THEN
            _eState := E_DL_ZeroTrackState.eIdle;   // 条件消失：退出本月窗口 / Condition lost, leave the window
            eErr := DL_ZT_WIN_OFF;                  // 信息级：窗未满足，零点保持 / Info, the window is unsatisfied and the zero is held
        ELSIF _rtrigWin.Q THEN
            _fZero := _fSample;                     // 落零点 = 窗内中值 [g] / Latch the zero from the window median
            fZeroOut_g := _fZero;                   // 零点出口 [g] / Zero output
            uTrackCnt := uTrackCnt + 1;             // 跟踪计数 +1 [次] / Tracking count incremented
            _eState := E_DL_ZeroTrackState.eTracked; // 本窗已落点 / Zero latched for this window
            eErr := DL_ZT_READY;                    // 就绪码 / Ready code
        END_IF

    E_DL_ZeroTrackState.eTracked:                   // 本窗已落点：等条件消失后再开新窗（防同窗重复落点）
        IF NOT bInWindow THEN
            _eState := E_DL_ZeroTrackState.eIdle;   // 条件消失：允许下一次跟踪 / Condition lost, the next tracking may start
        END_IF

    E_DL_ZeroTrackState.eFrozen:                    // 冻结：零点禁止更新，漂移回落后由复位路径解除
        IF NOT _bFrozen THEN
            _eState := E_DL_ZeroTrackState.eIdle;   // 冻结已解除（外部复位后） / Freeze released after an external reset
        ELSE
            eErr := DL_ZT_DRIFT;                    // 故障级：冻结保持 / Fault, the freeze is held
            bError := TRUE;
        END_IF

    ELSE
        // 非法状态兜底（故障级，组态非法码承载）
        eErr := DL_ZT_INPUT_BAD;                    // 故障级：非法相位 / Fault, illegal phase
        bError := TRUE;
        _eState := E_DL_ZeroTrackState.eIdle;

END_CASE

// 段 10｜净重与零点出口（净重单点写入；零点在跟踪路径写入，此处保持）
fZeroOut_g := _fZero;                               // 零点出口（单点回放）[g] / Zero output replayed from the internal copy
fNetOut_g := fWeightRaw_g - _fZero;                 // 去皮净重 [g] / Net weight after tare in grammes
END_FUNCTION_BLOCK
