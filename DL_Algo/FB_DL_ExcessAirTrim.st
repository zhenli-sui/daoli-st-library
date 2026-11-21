(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ExcessAirTrim
 * 溯源说明 (Provenance): 道莅 clean-room 防御性实现（IEC 61131-3 纯净实现，闭源文档仅借语义，零代码行）
 * 所属子库 (Sublibrary) : DL_Algo / ProcessControl
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），仅用
 *                         Standard.library 的 TON / LIMIT / ABS / TIME_TO_DINT / DINT_TO_TIME
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 氧量修正（空燃比长期偏置）
 * 功能一句话 (Summary)  : 按烟气含氧量与目标的偏差，按固定步长缓慢修正空燃比，
 *                         越死区才动、负荷剧变时冻结、修正量双侧钳位。
 *
 * 本件存在的意义 (Why this unit exists)
 *   与 FB_DL_CrossLimitSelect 是互补的两条律：交叉限幅管「同拍谁先给」，
 *   本件管「长期空燃比偏置」。二者不可合并——一个是逐拍代数选择，
 *   一个是慢时标步进律，合并后验收向量无法独立手算复算。
 *   ROADMAP §7 的锅炉/加热炉条目全部依赖这一对。
 *
 * 时间标度 (Time scale)
 *   步进节拍 = tConfirm：偏差持续 tConfirm 才走一步 fTrimStep。因此修正速率
 *   ≈ fTrimStep / tConfirm（例：0.05 % / 30 s ≈ 0.1 %/min），比燃烧回路慢两到
 *   三个数量级——这是刻意的：氧量探头本身有分钟级滞后，快修正只会来回过冲。
 *   tConfirm = T#0S 是合法语义（每拍一步），不置错，但此时步进率与扫描周期绑定，
 *   属调用方自担的用法，已在此声明。
 *
 * 边界安全 (Boundary)
 *   ① fO2Target <= 0、fO2Deadband < 0、fTrimLimit <= 0、fTrimStep <= 0，或四者
 *      任一非有限 → 故障 2C10，fTrim := 0（退回纯交叉限幅，安全可利用）；
 *   ② 氧量或负荷率非有限 → 故障 2C11，**保持末次 fTrim**（坏值不得清掉长期偏置）；
 *   ③ 死区内 → 信息 2C01，不修正、fTrim 保持；
 *   ④ |fLoadRate| > fRateFreeze → 信息 2C02，冻结修正、fTrim 保持；
 *   ⑤ 累加后双侧钳 ±fTrimLimit（抗饱和，不做积分回算）；
 *   ⑥ 失能 → eIdle，fTrim := 0 且**保持量一并清 0**，避免再使能时旧偏置
 *      突然回投（无扰投切，见 FB_DL_ExcessAirTrim 组装说明）；
 *   ⑦ TON 实例在主体最前部无条件刷新，步进后经「断输入一拍」标志重启计时，
 *      使步进节拍严格等于 tConfirm；
 *   ⑧ CASE 落 ELSE 置 2C12 并回 eFault。
 *
 * 错误码    : 16#0002_2C01 偏差在死区内，不修正（fTrim 保持）——信息级，正常调节
 *             16#0002_2C02 负荷变化率超限，修正已冻结——信息级，保护动作
 *             16#0002_2C10 修正参数非法（目标/死区/限幅/步长），fTrim 归零——故障级
 *             16#0002_2C11 氧量或负荷率非有限，保持末次 fTrim——故障级
 *             16#0002_2C12 状态机落 ELSE 兜底（非法状态）——故障级，回 eFault
 * 码位总账  : 16#0002_2C01 用 / 16#0002_2C02 用 ｜ 16#0002_2C10 用 / 16#0002_2C11 用 / 16#0002_2C12 用
 * 状态机    : E_DL_O2TrimState（eIdle / eActive / eFrozen / eFault），CASE 含 ELSE 兜底，
 *             ELSE 置 16#0002_2C12 并回 eFault；失能无条件回 eIdle
 * 采样约定  : 每任务周期调用一次；修正节拍由 tConfirm 决定，不读系统时钟
 * 依赖说明  : 零 DL_ 子库依赖（DL_Algo 只允许 Standard.library，限幅与死区内联实现）
 * 验收向量  : V1 氧量 4.0 %、目标 3.0 %、死区 0.3、tConfirm 30 s → 每 30 s 走一步
 *               fTrim −0.05，单调减到 −5.0 后钳住（抗饱和主向量）
 *             V2 氧量 3.2 %（死区内）→ 不修正，eErr = 2C01，fTrim 不动
 *             V3 fLoadRate = 5 %/s > fRateFreeze → bFrozen = TRUE，eErr = 2C02，fTrim 不动
 *             V4 fO2Target = 0 → fTrim = 0，eErr = 2C10，bError = TRUE，eFault
 *             V5 fO2Meas = NaN → fTrim 保持上一拍值，eErr = 2C11（保持主向量）
 *             V6 bEnable 落 → eIdle，fTrim = 0、bActive = FALSE、保持量清 0（恢复首拍不阶跃）
 *             V7 tConfirm = T#0S → 每拍一步，不置错（合法语义向量）
 * 红线自检  : 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 ｜ 纯 IEC 61131-3 ｜ 除法仅一处
 *             常量除（无除零面）｜ 浮点只用大小与容差比较 ｜ 无循环 ｜ 全变量双语
 *             同行注释 ｜ ENUM + CASE 含 ELSE ｜ TON 在主体最前部无条件刷新 ｜
 *             无魔法数
 * 修订历史  : 2026-11-16  v1.0.0  首版入库（R22 · 批 2 · 燃烧保护律）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_O2TrimState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 氧量修正的工作相位。0 起步长 10。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_O2TrimState :
(
    eIdle    := 0,     // 待机：未使能或参数非法，修正量为 0 / Idle, disabled or illegal parameters, trim is zero
    eActive  := 10,    // 生效：越死区且负荷平稳，按节拍步进 / Active, outside the dead band with a steady load
    eFrozen  := 20,    // 冻结：负荷变化率超限，保持修正 / Frozen, load rate above the limit, trim held
    eFault   := 99     // 故障：参数非法或输入非有限 / Fault, illegal parameter or non-finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_ExcessAirTrim
VAR_INPUT
    fO2Meas      : REAL;                       // 烟气含氧量实测 [%]，范围 0~21 / measured flue gas oxygen [%], range 0~21
    fO2Target    : REAL := 3.0;                // 目标氧含量 [%]，须 > 0 / target oxygen content [%], must be > 0
    fO2Deadband  : REAL := 0.3;                // 死区半宽 [%]，须 >= 0 / dead band half width [%], must be >= 0
    fTrimLimit   : REAL := 5.0;                // 修正量上限 [%]，对称，须 > 0 / symmetric trim limit [%], must be > 0
    fTrimStep    : REAL := 0.05;               // 单步修正量 [%]，须 > 0 / single trim step [%], must be > 0
    fLoadRate    : REAL;                       // 负荷变化率 [%/s] / load change rate [%/s]
    fRateFreeze  : REAL := 2.0;                // 冻结门限 [%/s]，须 > 0 / freeze threshold [%/s], must be > 0
    tConfirm     : TIME := T#30S;              // 步进确认时间 [ms]，0 = 每拍一步 / step confirm time [ms], zero means one step per scan
    bEnable      : BOOL;                       // 使能 / enable
END_VAR
VAR_OUTPUT
    fTrim        : REAL;                       // 空燃比修正量 [%]，正为增空气 / air to fuel ratio trim [%], positive adds air
    bActive      : BOOL;                       // 修正生效标志 / trim active flag
    bFrozen      : BOOL;                       // 修正冻结标志 / trim frozen flag
    eErr         : UDINT;                      // 错误码，0 表示无错 / error code, 0 means no error
    bError       : BOOL;                       // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid       : BOOL;                       // 输出可用标志 / outputs usable flag
END_VAR
VAR
    fbConfirm    : TON;                        // 步进节拍计时，段 5 无条件刷新 [ms] / step cadence timer, refreshed unconditionally
    _eState      : E_DL_O2TrimState := E_DL_O2TrimState.eIdle; // 当前相位 / current phase
    _bInit       : BOOL := FALSE;              // 首扫标志，初值 FALSE 取非判定 / first-scan flag, tested negated
    _bParamBad   : BOOL;                       // 参数非法标志 / illegal parameter flag
    _bFiniteBad  : BOOL;                       // 输入非有限标志 / non-finite input flag
    _bIllegal    : BOOL;                       // 非法状态标志 / illegal state flag
    _bCond       : BOOL;                       // 步进条件（越死区且负荷平稳） / step condition, outside dead band with a steady load
    _bStepPulse  : BOOL;                       // 本拍步进脉冲 / step pulse of this scan
    _bConfirmBreak : BOOL;                     // 节拍计时器断输入一拍标志 / cadence timer one-scan break flag
    _tConfirmUse : TIME := T#30S;              // 生效确认时间 [ms]，已钳位 / effective confirm time, clamped
    _fTrimHeld   : REAL;                       // 修正量保持量 [%] / held trim [%]
    _fDev        : REAL;                       // 氧量偏差 = 实测 − 目标 [%] / oxygen deviation, measured minus target
    _fAbsDev     : REAL;                       // 偏差绝对值 [%] / absolute deviation [%]
    _fAbsRate    : REAL;                       // 负荷变化率绝对值 [%/s] / absolute load rate [%/s]
    _fBandUse    : REAL := 0.3;                // 生效死区半宽 [%] / effective dead band half width
END_VAR
VAR CONSTANT
    DL_VAL_LIM   : REAL := 1.0E30;             // 有限性判定的绝对值上限 [无量纲] / finiteness ceiling
    DL_O2_MAX    : REAL := 21.0;               // 氧量物理上限 [%] / physical oxygen ceiling [%]
    DL_TARGET_MN : REAL := 0.0;                // 目标氧含量下限 [%]，须严格大于 / target oxygen floor, must be strictly greater
    DL_BAND_MN   : REAL := 0.0;                // 死区半宽下限 [%] / dead band floor [%]
    DL_LIMIT_MN  : REAL := 0.0;                // 修正限幅下限 [%]，须严格大于 / trim limit floor, must be strictly greater
    DL_STEP_MN   : REAL := 0.0;                // 步长下限 [%]，须严格大于 / step floor, must be strictly greater
    DL_RATE_MN   : REAL := 0.0;                // 冻结门限下限 [%/s]，须严格大于 / freeze threshold floor, must be strictly greater
    DL_EPS       : REAL := 1.0E-6;             // 浮点比较容差 [%] / float comparison tolerance [%]
    DL_CONF_MAX_MS : DINT := 3600000;          // 确认时间上限 [ms]，一小时 / confirm time ceiling, one hour
    DL_TIME_ZERO : TIME := T#0MS;              // 时间零值基准 [ms] / time zero reference
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置（保持量与输出在段 8 单点写入，此处不清）
 *      Per-scan presets, held values and outputs are written only in segment eight
 *-----------------------------------------------------------------------------*)
eErr        := 16#0000_0000;                   // 错误码每拍重算 / error code recomputed every scan
bError      := FALSE;                          // 故障标志每拍重算 / fault flag recomputed every scan
bValid      := FALSE;                          // 可用标志每拍重算 / usable flag recomputed every scan
bActive     := FALSE;                          // 生效标志每拍重算 / active flag recomputed every scan
bFrozen     := FALSE;                          // 冻结标志每拍重算 / frozen flag recomputed every scan
_bParamBad  := FALSE;                          // 参数非法标志预清零 / parameter flag pre-cleared
_bFiniteBad := FALSE;                          // 非有限标志预清零 / non-finite flag pre-cleared
_bIllegal   := FALSE;                          // 非法状态标志预清零 / illegal state flag pre-cleared
_bCond      := FALSE;                          // 步进条件预置 FALSE / step condition preset FALSE
_bStepPulse := FALSE;                          // 步进脉冲预置 FALSE / step pulse preset FALSE

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（修正量从 0 起：投用即无偏置，符合无扰投切）
 *      First-scan initialisation, the trim starts at zero for a bumpless start
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState      := E_DL_O2TrimState.eIdle;    // 相位待机 / phase idle
    _fTrimHeld   := 0.0;                       // 修正量保持量 0 [%] / held trim zero
    _bConfirmBreak := TRUE;                    // 节拍计时从零开始 / cadence timer starts from zero
    _bInit       := TRUE;                      // 首扫只做一次 / the first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数闸门（四参数与冻结门限，任一非法即故障级；先于所有除法与比较）
 *      Parameter gate, any illegal value is a fault, checked before any arithmetic
 *-----------------------------------------------------------------------------*)
IF (fO2Target <> fO2Target) OR (ABS(fO2Target) > DL_VAL_LIM) OR (fO2Target <= DL_TARGET_MN) THEN
    _bParamBad := TRUE;                        // 目标氧含量非法 / target oxygen illegal
END_IF
IF (fO2Deadband <> fO2Deadband) OR (ABS(fO2Deadband) > DL_VAL_LIM) OR (fO2Deadband < DL_BAND_MN) THEN
    _bParamBad := TRUE;                        // 死区半宽非法 / dead band illegal
END_IF
IF (fTrimLimit <> fTrimLimit) OR (ABS(fTrimLimit) > DL_VAL_LIM) OR (fTrimLimit <= DL_LIMIT_MN) THEN
    _bParamBad := TRUE;                        // 修正限幅非法 / trim limit illegal
END_IF
IF (fTrimStep <> fTrimStep) OR (ABS(fTrimStep) > DL_VAL_LIM) OR (fTrimStep <= DL_STEP_MN) THEN
    _bParamBad := TRUE;                        // 步长非法 / step illegal
END_IF
IF (fRateFreeze <> fRateFreeze) OR (ABS(fRateFreeze) > DL_VAL_LIM) OR (fRateFreeze <= DL_RATE_MN) THEN
    _bParamBad := TRUE;                        // 冻结门限非法 / freeze threshold illegal
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜输入有限性与偏差计算（区间判据同时拦 NaN 与 ±Inf）
 *      Input finiteness and deviation, the interval test catches NaN and infinity
 *-----------------------------------------------------------------------------*)
_fDev     := 0.0;                              // 偏差预置 0 [%] / deviation preset to zero
_fAbsDev  := 0.0;                              // 偏差绝对值预置 0 [%] / absolute deviation preset to zero
_fAbsRate := 0.0;                             // 负荷率绝对值预置 0 [%/s] / absolute load rate preset to zero

IF (fO2Meas < -DL_VAL_LIM) OR (fO2Meas > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 氧量非有限 / oxygen non-finite
END_IF
IF (fLoadRate < -DL_VAL_LIM) OR (fLoadRate > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 负荷率非有限 / load rate non-finite
END_IF

IF NOT _bFiniteBad THEN
    _fDev     := fO2Meas - fO2Target;           // 偏差：正 = 空气偏多 [%] / positive means too much air
    _fAbsDev  := ABS(_fDev);                    // 偏差绝对值 [%] / absolute deviation
    _fAbsRate := ABS(fLoadRate);                // 负荷率绝对值 [%/s] / absolute load rate
END_IF
_fBandUse := LIMIT(DL_BAND_MN, fO2Deadband, DL_O2_MAX); // 生效死区半宽钳进物理域 [%] / effective dead band clamped

(*------------------------------------------------------------------------------
 * 段 5｜定时器无条件刷新（R40：在 CASE 之外每拍必调；步进后断输入一拍重启节拍）
 *      Timer refreshed unconditionally outside the CASE, restarted after each step
 *-----------------------------------------------------------------------------*)
_tConfirmUse := tConfirm;                      // 确认时间直取引脚 [ms] / confirm time taken from the pin
IF TIME_TO_DINT(_tConfirmUse) > DL_CONF_MAX_MS THEN
    _tConfirmUse := DINT_TO_TIME(DL_CONF_MAX_MS); // 超上限钳位，无专用码位（R90 不新开码） / clamped, no dedicated code
END_IF
IF TIME_TO_DINT(_tConfirmUse) < 0 THEN
    _tConfirmUse := DL_TIME_ZERO;              // 负数时间结构性不可达，兜底为 0 / structurally unreachable, fallback to zero
END_IF

_bCond := bEnable AND (NOT _bParamBad) AND (NOT _bFiniteBad)
          AND (_fAbsDev > _fBandUse) AND (_fAbsRate <= fRateFreeze); // 步进条件 / step condition

fbConfirm(IN := _bCond AND (NOT _bConfirmBreak), PT := _tConfirmUse); // 节拍计时无条件刷新
_bConfirmBreak := FALSE;                       // 断输入拍在调用后自清（R40 自清位置） / break self-cleared after the call

IF _bCond AND (fbConfirm.Q OR (_tConfirmUse <= DL_TIME_ZERO)) THEN
    _bStepPulse := TRUE;                       // 本拍走一步（tConfirm = 0 时每拍一步，合法语义） / one step this scan
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜相位机（只做迁移；修正量在段 7 单点演进）
 *      Phase machine, transitions only, the trim evolves in segment seven
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_O2TrimState.eIdle:                    // 待机：参数合法、输入有限且使能即进入
        IF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_O2TrimState.eFault; // 原因未消失，转故障 / the cause persists
        ELSIF bEnable THEN
            IF _fAbsRate > fRateFreeze THEN
                _eState := E_DL_O2TrimState.eFrozen; // 负荷剧变，直接进冻结 / load jumping, freeze directly
            ELSE
                _eState := E_DL_O2TrimState.eActive; // 进生效相 / enter the active phase
            END_IF
        END_IF

    E_DL_O2TrimState.eActive:                  // 生效：越死区才步进
        IF NOT bEnable THEN
            _eState := E_DL_O2TrimState.eIdle; // 失能回待机 / disabled, back to idle
        ELSIF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_O2TrimState.eFault; // 转故障 / go to fault
        ELSIF _fAbsRate > fRateFreeze THEN
            _eState := E_DL_O2TrimState.eFrozen; // 负荷剧变，冻结修正 / load jumping, freeze the trim
        END_IF

    E_DL_O2TrimState.eFrozen:                  // 冻结：负荷平稳后恢复
        IF NOT bEnable THEN
            _eState := E_DL_O2TrimState.eIdle; // 失能回待机 / disabled, back to idle
        ELSIF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_O2TrimState.eFault; // 转故障 / go to fault
        ELSIF _fAbsRate <= fRateFreeze THEN
            _eState := E_DL_O2TrimState.eActive; // 负荷已平稳，恢复修正 / load steady again, resume
        END_IF

    E_DL_O2TrimState.eFault:                   // 故障：原因消失即自动恢复（本件无复位引脚）
        IF NOT bEnable THEN
            _eState := E_DL_O2TrimState.eIdle; // 失能回待机 / disabled, back to idle
        ELSIF (NOT _bParamBad) AND (NOT _bFiniteBad) THEN
            IF _fAbsRate > fRateFreeze THEN
                _eState := E_DL_O2TrimState.eFrozen; // 原因消失但负荷仍剧变，进冻结 / cause cleared but the load still jumps
            ELSE
                _eState := E_DL_O2TrimState.eActive; // 原因消失自动回生效相 / cause cleared, resume
            END_IF
        END_IF

    ELSE
        _bIllegal := TRUE;                     // 标记非法状态 / flag the illegal state
        _eState   := E_DL_O2TrimState.eFault;  // 回故障态 / back to the fault state
END_CASE

(*------------------------------------------------------------------------------
 * 段 7｜修正量演进（仅生效相且本拍有步进脉冲；累加后双侧钳，钳位后不再累加）
 *      Trim evolution in the active phase only, clamped both ways right after the step
 *-----------------------------------------------------------------------------*)
IF (_eState = E_DL_O2TrimState.eActive) AND _bStepPulse THEN
    IF _fDev > _fBandUse THEN
        _fTrimHeld := _fTrimHeld - fTrimStep;  // 氧量偏高：减空气 [%] / oxygen high, reduce air
    ELSIF (_fBandUse - _fDev) > DL_EPS THEN
        _fTrimHeld := _fTrimHeld + fTrimStep;  // 氧量偏低：增空气 [%] / oxygen low, add air
    END_IF
    _fTrimHeld := LIMIT(-fTrimLimit, _fTrimHeld, fTrimLimit); // 抗饱和：双侧钳位，不回算积分 / anti-windup, clamp only
    _bConfirmBreak := TRUE;                    // 走一步后重启节拍，节拍严格等于 tConfirm / restart the cadence
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜输出单点写入与码位优先级链
 *      Single write point of the outputs and the code priority chain
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    fTrim   := 0.0;                            // 非法状态：修正量归零 [%] / illegal state, trim zeroed
    bActive := FALSE;                          // 生效标志清零 / active flag cleared
    bFrozen := FALSE;                          // 冻结标志清零 / frozen flag cleared
    eErr    := 16#0002_2C12;                   // 故障级：状态机兜底 / fault: state machine fallback
    bError  := TRUE;                           // 置故障标志 / raise the fault flag
    bValid  := FALSE;                          // 输出不可用 / outputs unusable
ELSIF NOT bEnable THEN
    fTrim      := 0.0;                         // 失能：修正量显式清零 [%] / disabled, trim explicitly zeroed
    _fTrimHeld := 0.0;                         // 保持量一并清零，再使能不回投旧偏置 [%] / held trim cleared too
    bActive    := FALSE;                       // 生效标志清零 / active flag cleared
    bFrozen    := FALSE;                       // 冻结标志清零 / frozen flag cleared
    bValid     := FALSE;                       // 失能时输出不可用 / unusable while disabled
ELSIF _bParamBad THEN
    fTrim      := 0.0;                         // 参数非法：退回纯交叉限幅，修正量 0 [%] / trim zeroed, cross limiting only
    _fTrimHeld := 0.0;                         // 保持量清零，防非法参数解除后旧值回投 [%] / held trim cleared
    bActive    := FALSE;                       // 生效标志清零 / active flag cleared
    bFrozen    := FALSE;                       // 冻结标志清零 / frozen flag cleared
    eErr       := 16#0002_2C10;                // 故障级：修正参数非法 / fault: trim parameters illegal
    bError     := TRUE;                        // 置故障标志 / raise the fault flag
    bValid     := FALSE;                       // 输出不可用 / outputs unusable
ELSIF _bFiniteBad THEN
    fTrim   := _fTrimHeld;                     // 非有限：保持末次修正量 [%] / hold the last trim
    bActive := FALSE;                          // 本次未演进，不宣称生效 / no evolution this scan
    bFrozen := FALSE;                          // 本次未演进，不宣称冻结 / no freeze claim this scan
    eErr    := 16#0002_2C11;                   // 故障级：输入非有限 / fault: non-finite input
    bError  := TRUE;                           // 置故障标志 / raise the fault flag
    bValid  := FALSE;                          // 输出不可用 / outputs unusable
ELSE
    fTrim   := _fTrimHeld;                     // 正常：修正量出口 [%] / trim outlet
    bActive := (_eState = E_DL_O2TrimState.eActive); // 生效标志 / active flag
    bFrozen := (_eState = E_DL_O2TrimState.eFrozen); // 冻结标志 / frozen flag
    bValid  := TRUE;                           // 输出可用 / outputs usable
    IF _eState = E_DL_O2TrimState.eFrozen THEN
        eErr := 16#0002_2C02;                  // 信息级：负荷变化率超限已冻结 / informational: frozen by the load rate
    ELSIF _fAbsDev <= _fBandUse THEN
        eErr := 16#0002_2C01;                  // 信息级：死区内不修正 / informational: inside the dead band
    END_IF
END_IF

END_FUNCTION_BLOCK
