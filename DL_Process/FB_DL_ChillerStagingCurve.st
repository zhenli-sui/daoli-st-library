(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ChillerStagingCurve
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，无方言）
 * 功能描述 (Function)   : 冷机加减机效率曲线选点。用单机 COP 与容量曲线求最经济负荷点，
 *                         按系统负荷率反算建议台数（N+1 冗余口径：需求台数向上取整再加一台，
 *                         下限钳 1 台、上限 8 台），与在线台数比较后在死区外、持续确认时长
 *                         满足时给单拍加/减机请求。曲线非单调或含非有限值一律**不给建议**
 *                         （错曲线的建议比不给更危险）。不做机组启停时序、不做 COP 实测、
 *                         不做负荷预测。
 *                         交付门槛：本件不含时间转换链，纯实数与整数算术，无平台相关内建。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_StageState / FUNCTION_BLOCK FB_DL_ChillerStagingCurve
 * 依赖 (Depends)        : 无（仅 Standard.library 的 ABS / LIMIT / TRUNC）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         台数判零防除零 ｜ 曲线单调性与非有限双检 ｜ 负荷非有限保持上次台数 ｜
 *                         确认定时器与沿实例无条件周期刷新 ｜ 枚举显式赋值 ｜ CASE 含 ELSE
 * 错误码表 (Codes)      : 16#0005_0449 就绪（建议已给出且曲线有效）
 *                         16#0005_044A 预留：本版不发码（下一轮区间起点，禁止回填）
 *                         16#0005_044B 故障级 曲线非单调或含非有限值，不给建议
 *                         16#0005_044C 故障级 在线台数为 0（防除零，不给建议）
 *                         16#0005_044D 信息级 负荷率非有限，保持上次台数与 COP（不置故障级标志）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 4
 *                         2026-11-17  v1.0.1  终审修复：①需求台数向上取整算式在「正好整除」
 *                                    时多算一台（TRUNC+1 把整数也进位了），改为余量判进位；
 *                                    ②负荷率与死区补域钳制（超界负荷经实数转整数溢出会让加减
 *                                    机方向翻转）；③故障解除判据原写成「失能且未锁存」永不成立，
 *                                    改为失能即解除（原写法使组态类故障永久不可恢复）· R28 · 阶段四
 * 验收向量 (Acceptance) : 正向 负荷 55 %、在线 3 台、曲线峰值在 80 %（单机 18.3 % 过轻）→
 *                         bDelReq 单拍、uStage=2、bOnCurve=TRUE
 *                         反向 曲线改为非单调 → 16#0005_044B 且 bAddReq/bDelReq 均为 FALSE；
 *                         台数给 0 → 16#0005_044C；负荷给 NaN → 16#0005_044D 且 uStage 保持
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StageState（归属本功能块，同文件发布，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StageState :
(
    eIdle    := 0,    // 待机：使能关或曲线无效 / Idle, disabled or the curve is invalid
    eEval    := 10,   // 评估：本拍算建议台数 / Evaluating the recommended unit count
    eConfirm := 20,   // 确认：偏差持续计时中 / Confirming, the deviation persists
    ePulse   := 30,   // 脉冲：本拍发出加/减机请求 / Pulse, an add or delete request is issued this scan
    eFault   := 99    // 故障：锁存码保持 / Fault, the latch code is held
);
END_TYPE

FUNCTION_BLOCK FB_DL_ChillerStagingCurve
VAR_INPUT
    bEnable       : BOOL := FALSE;        // 使能 / Enable
    fLoadPct      : REAL := 50.0;         // 系统负荷率 [%]，域 0~120 / System load in percent, domain 0 to 120
    afCopCurve    : ARRAY[1..11] OF REAL; // 单机 COP 曲线（10/20/…/100 % 十一点） / Single-unit COP curve, eleven points
    afCapCurve    : ARRAY[1..11] OF REAL; // 单机容量曲线 [kW]（十一点） / Single-unit capacity curve in kilowatt
    uUnitCnt      : UINT := 2;            // 在线台数 [台]，域 1~8 / Online unit count, domain 1 to 8
    fLoadStepPct  : REAL := 5.0;          // 加/减机死区 [%]，域 1~20 / Staging dead band in percent, domain 1 to 20
    tConfirm      : TIME := T#60S;        // 建议持续确认 [ms]，域 10 s~10 min / Suggestion confirmation time
END_VAR
VAR_OUTPUT
    uStage        : UINT := 1;            // 建议运行台数 [台]，域 1~8 / Recommended unit count
    bAddReq       : BOOL;                 // 加机请求（单拍脉冲） / Add request, a one-scan pulse
    bDelReq       : BOOL;                 // 减机请求（单拍脉冲） / Delete request, a one-scan pulse
    fCopNow       : REAL;                 // 当前负荷率推算 COP / COP derived from the present per-unit load
    fBestLoadPct  : REAL;                 // 本台数最经济负荷率 [%] / Most economic per-unit load
    bOnCurve      : BOOL;                 // 曲线单调性校验通过 / Curve monotonicity check passed
    eErr          : UDINT;                // 错误码，段位 16#0005_xxxx / Error code in segment 16#0005_xxxx
END_VAR
VAR
    _eState       : E_DL_StageState := E_DL_StageState.eIdle; // 当前相位 / Current phase
    _bInit        : BOOL := FALSE;        // 首扫标志，取非判定 / First-scan flag, tested negated
    _bCurveOk     : BOOL;                 // 曲线有效标志 / Curve valid flag
    _bLoadOk      : BOOL;                 // 负荷有限标志 / Load finite flag
    _bUpWant      : BOOL;                 // 需要加机（未确认） / Add needed before confirmation
    _bDnWant      : BOOL;                 // 需要减机（未确认） / Delete needed before confirmation
    _bFaultLatch  : BOOL := FALSE;        // 故障锁存标志 / Fault latch flag
    _uLatchCode   : UDINT;                // 锁存码载体 / Latch code carrier
    _uStageCalc   : UINT := 1;            // 本拍计算建议台数 [台] / Computed recommended count
    _uBestIdx     : UINT := 11;           // COP 峰值点下标（10..100 %） / Index of the COP peak
    _uStagePrev   : UINT := 1;            // 上次台数（非有限负荷时保持） / Previous count kept for a non-finite load
    _iLoop        : INT;                  // 曲线扫描索引 / Curve scan index
    _iGuard       : INT;                  // 防死循环计数器 / Loop guard counter
    _fBestCop     : REAL := 0.0;          // 峰值 COP / Peak COP
    _fPerUnit     : REAL;                 // 单机负荷率 [%] / Per-unit load in percent
    _fLoadEff     : REAL;                 // 域钳制后负荷率 [%]（0~120） / Load after the domain clamp
    _fStepEff     : REAL := 5.0;          // 域钳制后死区 [%]（1~20） / Dead band after the domain clamp
    _fNeedUnits   : REAL;                 // 需求台数（未取整） / Required unit count before rounding
    _fCopLocal    : REAL;                 // 当前 COP 插值结果 / Interpolated COP
    _rtrigConf    : R_TRIG;               // 确认计时满上升沿 / Rising edge of the confirmation timer
    _tonConfirm   : TON;                  // 建议持续确认计时 / Suggestion confirmation timer
END_VAR
VAR CONSTANT
    DL_CH_READY    : UDINT := 16#0005_0449;  // 就绪码 / Ready code
    DL_CH_CURVE_BAD : UDINT := 16#0005_044B; // 故障级曲线不可用码 / Fault code for an unusable curve
    DL_CH_UNIT_ZERO : UDINT := 16#0005_044C; // 故障级台数为零码 / Fault code for a zero unit count
    DL_CH_LOAD_BAD : UDINT := 16#0005_044D;  // 信息级负荷非有限码 / Info code for a non-finite load
    DL_CH_PTS      : INT := 11;              // 曲线点数 / Curve point count
    DL_CH_LOOP_MAX : INT := 20;              // 循环保护上限 / Loop guard bound
    DL_CH_STEP_LO  : REAL := 1.0;            // 死区下限 [%] / Dead band lower bound
    DL_CH_STEP_HI  : REAL := 20.0;           // 死区上限 [%] / Dead band upper bound
    DL_CH_STEP_DFLT : REAL := 5.0;           // 死区非有限时的默认值 [%] / Default dead band for a non-finite input
    DL_CH_LOAD_HI  : REAL := 120.0;          // 负荷率域上限 [%] / Load domain upper bound
    DL_CH_NEED_HI  : REAL := 100.0;          // 需求台数兜底上限 [台] / Required-unit upper bound guard
    DL_CH_STAGE_LO : UINT := 1;              // 建议台数下限 [台] / Recommended count lower bound
    DL_CH_STAGE_HI : UINT := 8;              // 建议台数上限 [台] / Recommended count upper bound
    DL_CH_UNIT_MAX : UINT := 8;              // 在线台数上限 [台] / Online count upper bound
    DL_CH_EPS      : REAL := 1.0E-6;         // 浮点判零容差 / Float zero tolerance
END_VAR

// 段 1｜输出与单拍标志预置
bAddReq := FALSE;                                   // 加机请求预清（单拍） / Add request pre-cleared
bDelReq := FALSE;                                   // 减机请求预清（单拍） / Delete request pre-cleared
bOnCurve := FALSE;                                  // 曲线校验标志预清 / Curve check flag pre-cleared
eErr := 0;                                          // 错误码预清 / Error code pre-cleared
_fCopLocal := 0.0;                                  // COP 局部量预清 / COP local pre-cleared

// 段 2｜确认定时器与沿实例无条件周期刷新
_tonConfirm(IN := bEnable AND _bCurveOk AND (_bUpWant OR _bDnWant), PT := tConfirm);
_rtrigConf(CLK := _tonConfirm.Q);                   // 确认满沿 / Confirmation edge

// 段 3｜首扫初始化（判据取非，R19）
IF NOT _bInit THEN
    uStage := 1;                                    // 建议台数起点 1 [台] / Recommended count starts at one
    _uStagePrev := 1;
    _eState := E_DL_StageState.eIdle;               // 相位待机起步 / Phase starts idle
    _bInit := TRUE;                                 // 首扫只做一次 / The first scan runs once
END_IF

// 段 4｜曲线校验（单调不减 + 全点有限；十一轮固定上界，循环带保护计数）
_bCurveOk := TRUE;
_iLoop := 1;
_iGuard := 0;
_fBestCop := 0.0 - 1.0E30;
_uBestIdx := 1;
WHILE (_iLoop <= DL_CH_PTS) AND (_iGuard < DL_CH_LOOP_MAX) DO
    IF (afCopCurve[_iLoop] <> afCopCurve[_iLoop]) OR ((afCopCurve[_iLoop] - afCopCurve[_iLoop]) <> (afCopCurve[_iLoop] - afCopCurve[_iLoop])) THEN
        _bCurveOk := FALSE;                         // COP 点非有限 / A COP point is not finite
    END_IF
    IF (afCapCurve[_iLoop] <> afCapCurve[_iLoop]) OR ((afCapCurve[_iLoop] - afCapCurve[_iLoop]) <> (afCapCurve[_iLoop] - afCapCurve[_iLoop])) THEN
        _bCurveOk := FALSE;                         // 容量点非有限 / A capacity point is not finite
    END_IF
    IF afCopCurve[_iLoop] > _fBestCop THEN
        _fBestCop := afCopCurve[_iLoop];            // 峰值刷新 / Peak refreshed
        _uBestIdx := INT_TO_UINT(_iLoop);           // 峰值下标 / Peak index
    END_IF
    IF _iLoop > 1 THEN
        IF afCopCurve[_iLoop] < afCopCurve[_iLoop - 1] THEN
            _bCurveOk := FALSE;                     // 非单调（COP 随负荷率不增）：不给建议 / Non-monotonic curve, no advice
        END_IF
        IF afCapCurve[_iLoop] < afCapCurve[_iLoop - 1] THEN
            _bCurveOk := FALSE;                     // 容量曲线非单调 / Non-monotonic capacity curve
        END_IF
    END_IF
    _iLoop := _iLoop + 1;
    _iGuard := _iGuard + 1;                         // 防死循环计数 / Loop guard incremented
END_WHILE
bOnCurve := _bCurveOk;                              // 曲线校验出口 / Curve check output
fBestLoadPct := UINT_TO_REAL(_uBestIdx) * 10.0;     // 最经济负荷率 [%] / Most economic load
IF NOT _bCurveOk THEN
    eErr := DL_CH_CURVE_BAD;                        // 故障级：曲线不可用 / Fault, the curve is unusable
    _uLatchCode := DL_CH_CURVE_BAD;
    _bFaultLatch := TRUE;
    _eState := E_DL_StageState.eFault;
END_IF

// 段 5｜台数与负荷闸（台数 0 防除零；负荷非有限保持上次台数）
IF uUnitCnt = 0 THEN
    eErr := DL_CH_UNIT_ZERO;                        // 故障级：在线台数为 0 / Fault, the online unit count is zero
    _uLatchCode := DL_CH_UNIT_ZERO;
    _bFaultLatch := TRUE;
    _eState := E_DL_StageState.eFault;
END_IF
_bLoadOk := NOT ((fLoadPct <> fLoadPct) OR ((fLoadPct - fLoadPct) <> (fLoadPct - fLoadPct)));
IF NOT _bLoadOk THEN
    eErr := DL_CH_LOAD_BAD;                         // 信息级：负荷非有限，保持上次台数 / Info, the load is not finite and the previous count is held
    uStage := _uStagePrev;
END_IF

// 段 6｜建议台数计算（N+1 冗余口径：需求台数向上取整再加 1 台，钳 1~8）
IF _bCurveOk AND _bLoadOk AND (uUnitCnt > 0) AND (fBestLoadPct > DL_CH_EPS) THEN
    _fLoadEff := LIMIT(0.0, fLoadPct, DL_CH_LOAD_HI);   // 负荷率域钳制 [%]（防实数转整数溢出翻转加减机方向） / Load clamped into the domain
    _fStepEff := fLoadStepPct;                          // 死区副本 [%] / Dead band copy
    IF (_fStepEff <> _fStepEff) OR ((_fStepEff - _fStepEff) <> (_fStepEff - _fStepEff)) THEN
        _fStepEff := DL_CH_STEP_DFLT;                   // 死区非有限：回默认值，不静默变成 0 死区 / Non-finite dead band falls back to the default
    END_IF
    _fStepEff := LIMIT(DL_CH_STEP_LO, _fStepEff, DL_CH_STEP_HI);   // 死区域钳制 [%] / Dead band clamped
    _fPerUnit := _fLoadEff / UINT_TO_REAL(uUnitCnt);    // 单机负荷率 [%] / Per-unit load
    _fNeedUnits := _fLoadEff / fBestLoadPct;            // 需求台数（未取整） / Required units before rounding
    IF _fNeedUnits < 0.0 THEN
        _fNeedUnits := 0.0;                             // 负负荷按 0 处理 / Negative load treated as zero
    END_IF
    IF _fNeedUnits > DL_CH_NEED_HI THEN
        _fNeedUnits := DL_CH_NEED_HI;                   // 上限兜底，防取整溢出 [台] / Upper bound guard against rounding overflow
    END_IF
    _uStageCalc := REAL_TO_UINT(TRUNC(_fNeedUnits));    // 先向下取整 [台] / Truncate first
    IF _fNeedUnits > UINT_TO_REAL(_uStageCalc) THEN
        _uStageCalc := _uStageCalc + 1;                 // 有小数余量才进一位（正好整除不进位） / Round up only with a fractional remainder
    END_IF
    _uStageCalc := _uStageCalc + 1;                     // N+1 冗余 [台] / One redundant unit
    uStage := LIMIT(DL_CH_STAGE_LO, _uStageCalc, DL_CH_STAGE_HI); // 建议台数钳制 [台] / Recommended count clamped
    _uStagePrev := uStage;                          // 台数快照 / Count snapshot
    // 当前负荷率下的 COP 插值（十一点等距，线性内插）
    IF _fPerUnit <= 10.0 THEN
        _fCopLocal := afCopCurve[1];                // 低于首点：取首点 / Below the first point, use the first
    ELSIF _fPerUnit >= 100.0 THEN
        _fCopLocal := afCopCurve[11];               // 高于末点：取末点 / Above the last point, use the last
    ELSE
        _iLoop := TRUNC(_fPerUnit / 10.0) + 1;      // 区间左端下标 / Left index of the interval
        IF _iLoop < 1 THEN
            _iLoop := 1;                            // 下标下限保护 / Index lower guard
        END_IF
        IF _iLoop > (DL_CH_PTS - 1) THEN
            _iLoop := DL_CH_PTS - 1;                // 下标上限保护 / Index upper guard
        END_IF
        _fCopLocal := afCopCurve[_iLoop]
                    + ((afCopCurve[_iLoop + 1] - afCopCurve[_iLoop])
                       * ((_fPerUnit - (UINT_TO_REAL(INT_TO_UINT(_iLoop)) * 10.0) + 10.0) / 10.0 - 1.0));
    END_IF
    fCopNow := _fCopLocal;                          // COP 出口 / COP output
    // 死区比较：死区外才提请求（防抖）
    _bUpWant := (_fPerUnit > (fBestLoadPct + _fStepEff)) OR (uStage > uUnitCnt);
    _bDnWant := ((_fPerUnit < (fBestLoadPct - _fStepEff)) OR (uStage < uUnitCnt)) AND (uStage >= DL_CH_STAGE_LO);
    IF uStage > uUnitCnt THEN
        _bUpWant := TRUE;                           // 建议台数高于在线台数：加机 / The recommendation exceeds the online count
        _bDnWant := FALSE;
    ELSIF uStage < uUnitCnt THEN
        _bUpWant := FALSE;                          // 建议台数低于在线台数：减机 / The recommendation is below the online count
        _bDnWant := TRUE;
    ELSE
        _bUpWant := FALSE;                          // 台数一致：不提请求 / Counts agree, no request
        _bDnWant := FALSE;
    END_IF
    eErr := DL_CH_READY;                            // 就绪码 / Ready code
END_IF

// 段 7｜请求脉冲（确认时长满才发，单拍自清）
IF (_eState <> E_DL_StageState.eFault) THEN
    IF _rtrigConf.Q THEN
        IF _bUpWant AND (uUnitCnt < DL_CH_UNIT_MAX) THEN
            bAddReq := TRUE;                        // 加机单拍脉冲 / Add pulse for one scan
        ELSIF _bDnWant AND (uUnitCnt > DL_CH_STAGE_LO) THEN
            bDelReq := TRUE;                        // 减机单拍脉冲（下限钳 1 台） / Delete pulse, the count is clamped to one
        END_IF
        _eState := E_DL_StageState.ePulse;          // 本拍脉冲相 / Pulse phase for this scan
    ELSE
        IF bEnable AND _bCurveOk AND _bLoadOk THEN
            IF _bUpWant OR _bDnWant THEN
                _eState := E_DL_StageState.eConfirm;    // 偏差存在：确认计时中 / Deviation present, confirming
            ELSE
                _eState := E_DL_StageState.eEval;       // 无偏差：常规评估 / No deviation, plain evaluation
            END_IF
        ELSE
            _eState := E_DL_StageState.eIdle;           // 禁用或输入不可用：待机 / Disabled or unusable inputs, idle
        END_IF
    END_IF
END_IF

// 段 8｜相位收口（ENUM + CASE + ELSE 兜底）
CASE _eState OF
    E_DL_StageState.eIdle:
        bAddReq := FALSE;                           // 待机不发请求 / No request while idle
        bDelReq := FALSE;
    E_DL_StageState.eEval:
        bAddReq := FALSE;                           // 评估相不发请求 / No request while evaluating
        bDelReq := FALSE;
    E_DL_StageState.eConfirm:
        bAddReq := FALSE;                           // 确认相不发请求 / No request while confirming
        bDelReq := FALSE;
    E_DL_StageState.ePulse:
        _eState := E_DL_StageState.eEval;           // 脉冲相单拍后自动转评估 / The pulse phase lasts one scan
    E_DL_StageState.eFault:
        bAddReq := FALSE;                           // 故障相不发请求 / No request in the fault phase
        bDelReq := FALSE;
        eErr := _uLatchCode;                        // 锁存码回放 / Replay the latch code
        IF NOT bEnable THEN                         // 失能即解除锁存（旧判据取反写错，故障永不可退） / A disable releases the latch
            _bFaultLatch := FALSE;                  // 锁存解除 / Latch released
            _uLatchCode := 0;                       // 锁存码清 / Latch code cleared
            eErr := DL_CH_READY;                    // 解除后回就绪码 / Ready code after the release
            _eState := E_DL_StageState.eIdle;       // 回待机 / Back to idle
        END_IF
    ELSE
        // 非法相位兜底（故障级）
        bAddReq := FALSE;
        bDelReq := FALSE;
        eErr := DL_CH_CURVE_BAD;                    // 故障级：非法相位 / Fault, illegal phase
        _uLatchCode := DL_CH_CURVE_BAD;
        _bFaultLatch := TRUE;
        _eState := E_DL_StageState.eFault;
END_CASE
END_FUNCTION_BLOCK
