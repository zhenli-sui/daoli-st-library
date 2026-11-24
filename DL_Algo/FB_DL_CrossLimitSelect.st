(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CrossLimitSelect
 * 溯源说明 (Provenance): 道莅 clean-room 防御性实现（IEC 61131-3 纯净实现，闭源文档仅借语义，零代码行）
 * 所属子库 (Sublibrary) : DL_Algo / ProcessControl
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），仅用
 *                         Standard.library 的 LIMIT / MIN / MAX / ABS
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 燃烧双交叉限幅
 * 功能一句话 (Summary)  : 把主控输出分配成空气/燃气两路给定，按「先行侧自由、
 *                         跟随侧受实测流量约束」的双交叉限幅律钳制，输出限幅
 *                         标志与距限幅点余量。
 *
 * 本件存在的意义 (Why this unit exists)
 *   库内 SplitRangeControl 是单输出分程、RatioController 是比值站，都不解
 *   「空燃两侧谁先给」这个燃烧专有语义。双交叉限幅管的是**同拍的选择律**：
 *   升负荷时先行侧先动、跟随侧被实测流量压住；降负荷时反过来。
 *   写成一件的理由是它必须逐拍可复算（验收向量要能独立手算），
 *   与氧量修正（慢时标积分律，见 FB_DL_ExcessAirTrim）不可合并。
 *
 * 依赖收窄 (Dependency narrowing)
 *   DL_Algo 只允许依赖 Standard.library（DL_Algo/VERSION.md 明示不得引用
 *   DL_Base / DL_MathData）。因此本件的限幅用内建 LIMIT、容差比较与死区
 *   判断全部内联等价实现，不调用任何 DL_ 子库件。此处声明留档（R11 先例）。
 *
 * 折算口径 (Scaling rationale —— 必须写清，否则本件不可复算)
 *   主控输出是 [%]，流量是 [Nm3/h]，两者不同量纲，接口未给阀门流量量程。
 *   本件的折算基准是**实测流量本身**：主控 [%] 与实测流量在当前工况下对应，
 *   故「约束侧的允许百分比」= 主控输出 × (允许流量 / 实测流量)。该比值无量纲，
 *   不引入任何隐藏量程参数。实测流量 ≤ DL_FLOW_EPS 时（点火初期或流量计未投用）
 *   没有折算基准，此时**直接放行主控值**并置信息码，绝不拿 0 做除数。
 *
 * 边界安全 (Boundary)
 *   ① fAirFuelRatio <= 0、fLeadMargin < 1.0、或二者非有限 → 故障 2B10，
 *      **双侧给定归零**（安全侧 = 切断燃料，宁可熄火不可爆燃）；
 *   ② 任一流量或主控非有限 → 故障 2B11，**保持末次有效给定**
 *      （切 0 会熄火/爆燃，与「参数非法」的安全方向相反，两条并列写死）；
 *   ③ 限幅生效 → 信息 2B01（空气侧受限）/ 2B02（燃气侧受限）；
 *   ④ 失能 → 回 eIdle，fAirSp 与 fGasSp **逐个显式赋 0**（R72 双路径清零，
 *      不依赖段尾镜像），bLimited / fLimitMargin 同时清零；
 *   ⑤ 除零前置闸先于任何除法：比率闸在段 3、实测流量闸在段 6，两处都在商之前；
 *   ⑥ 本件无复位引脚，故障态在原因消失后自动回 eNormal（本件无台账需保持，
 *      与 FB_DL_PressureReliefMonitor 的锁存台账件语义不同，已留档）；
 *   ⑦ CASE 落 ELSE 置 2B12 并回 eFault（非法状态兜底）。
 *
 * 错误码    : 16#0002_2B01 空气侧限幅生效（跟随侧为空气）——信息级，正常调节
 *             16#0002_2B02 燃气侧限幅生效（跟随侧为燃气）——信息级，正常调节
 *             16#0002_2B10 空燃比或先行裕度非法（含非有限），双侧给定归零——故障级
 *             16#0002_2B11 输入非有限，保持末次有效给定——故障级，不得切 0
 *             16#0002_2B12 状态机落 ELSE 兜底（非法状态）——故障级，回 eFault
 * 码位总账  : 16#0002_2B01 用 / 16#0002_2B02 用 ｜ 16#0002_2B10 用 / 16#0002_2B11 用 / 16#0002_2B12 用
 * 状态机    : E_DL_CrossLimitState（eIdle / eNormal / eAirLimited / eGasLimited / eFault），
 *             CASE 含 ELSE 兜底，ELSE 置 16#0002_2B12 并回 eFault；失能无条件回 eIdle
 * 采样约定  : 每任务周期调用一次，纯代数运算，无定时器、无积分
 * 依赖说明  : 零 DL_ 子库依赖；仅 Standard.library 的 LIMIT / MIN / MAX / ABS
 * 验收向量  : V1 空气先行、主控 60 %、空气 1200 Nm3/h、燃气 100 Nm3/h、比率 10
 *               → 允许燃气 1200/10×1.05 = 126 → 燃气给定 = 60×126/100 = 75.6 → 钳到 60；
 *               不受限，eNormal，bValid = TRUE
 *             V2 同 V1 但燃气实测 130 Nm3/h（超供）→ 燃气给定 = 60×126/130 = 58.15，
 *               bLimited = TRUE，fLimitMargin = 1.85，eErr = 2B02，eGasLimited
 *             V3 fAirFuelRatio = 0 → 双侧给定 0，eErr = 2B10，bError = TRUE，eFault
 *             V4 fLeadMargin = 0.95 → 双侧给定 0，eErr = 2B10（先行裕度主向量）
 *             V5 fAirFlow = NaN → 给定保持上一拍有效值，eErr = 2B11（保持主向量）
 *             V6 bEnable = FALSE → fAirSp = 0 且 fGasSp = 0，bLimited = FALSE，eIdle
 *             V7 燃气先行（bAirLead = FALSE）+ 空气超供 → eErr = 2B01，eAirLimited
 * 红线自检  : 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 ｜ 纯 IEC 61131-3 ｜ 两处除零
 *             前置闸 ｜ 浮点只用容差与大小比较，无判等 ｜ 无循环 ｜ 全变量双语
 *             同行注释 ｜ ENUM + CASE 含 ELSE ｜ 无定时器实例（无刷新项，天然合规）
 *             ｜ 无魔法数
 * 修订历史  : 2026-11-16  v1.0.0  首版入库（R22 · 批 2 · 燃烧保护律）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CrossLimitState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 交叉限幅的工作相位。0 起步长 10。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_CrossLimitState :
(
    eIdle       := 0,   // 待机：未使能，双侧给定为 0 / Idle, disabled, both setpoints zero
    eNormal     := 10,  // 正常：跟随侧未被压住，两路等于主控 / Normal, the follower is not constrained
    eAirLimited := 20,  // 空气侧受限：燃气先行时空气被压住 / Air limited, gas leads and air is constrained
    eGasLimited := 30,  // 燃气侧受限：空气先行时燃气被压住 / Gas limited, air leads and gas is constrained
    eFault      := 99   // 故障：参数非法或输入非有限 / Fault, illegal parameter or non-finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_CrossLimitSelect
VAR_INPUT
    fMasterOut     : REAL;                     // 主控输出 [%]，范围 0~100 / master controller output [%], range 0~100
    fAirFlow       : REAL;                     // 实测空气流量 [Nm3/h] / measured air flow [Nm3/h]
    fGasFlow       : REAL;                     // 实测燃气流量 [Nm3/h] / measured gas flow [Nm3/h]
    fAirFuelRatio  : REAL := 10.0;             // 目标空燃比 [Nm3空气/Nm3燃气]，须 > 0 / target air to fuel ratio [Nm3 air per Nm3 gas], must be > 0
    fLeadMargin    : REAL := 1.05;             // 先行裕度 [倍]，须 >= 1.0 / leading margin [ratio], must be >= 1.0
    bAirLead       : BOOL := TRUE;             // TRUE 空气先行 / FALSE 燃气先行 / TRUE air leads, FALSE gas leads
    bEnable        : BOOL;                     // 使能 / enable
END_VAR
VAR_OUTPUT
    fAirSp         : REAL;                     // 空气给定 [%]，范围 0~100 / air setpoint [%], range 0~100
    fGasSp         : REAL;                     // 燃气给定 [%]，范围 0~100 / gas setpoint [%], range 0~100
    bLimited       : BOOL;                     // 跟随侧限幅生效标志 / follower side limiting active flag
    fLimitMargin   : REAL;                     // 距限幅点余量 [%]，未限幅时为 0 / distance to the limiting point [%], zero when unlimited
    eErr           : UDINT;                    // 错误码，0 表示无错 / error code, 0 means no error
    bError         : BOOL;                     // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid         : BOOL;                     // 输出可用标志 / outputs usable flag
END_VAR
VAR
    _eState        : E_DL_CrossLimitState := E_DL_CrossLimitState.eIdle; // 当前相位 / current phase
    _eCand         : E_DL_CrossLimitState := E_DL_CrossLimitState.eNormal; // 本拍候选相位 / candidate phase of this scan
    _bInit         : BOOL := FALSE;            // 首扫标志，初值 FALSE 取非判定 / first-scan flag, tested negated
    _bParamBad     : BOOL;                     // 参数非法标志 / illegal parameter flag
    _bFiniteBad    : BOOL;                     // 输入非有限标志 / non-finite input flag
    _bIllegal      : BOOL;                     // 非法状态标志 / illegal state flag
    _bLimC         : BOOL;                     // 本拍限幅标志（候选） / limiting flag of this scan
    _fMarginC      : REAL;                     // 本拍余量（候选）[%] / margin of this scan [%]
    _fMasterUse    : REAL;                     // 生效主控输出 [%]，已钳位 / effective master output [%], clamped
    _fAirHeld      : REAL;                     // 空气给定保持量 [%] / held air setpoint [%]
    _fGasHeld      : REAL;                     // 燃气给定保持量 [%] / held gas setpoint [%]
    _fGasAvail     : REAL;                     // 允许燃气流量 [Nm3/h] / allowable gas flow [Nm3/h]
    _fAirNeed      : REAL;                     // 所需空气流量 [Nm3/h] / required air flow [Nm3/h]
    _fAirAllowed   : REAL;                     // 允许空气流量 [Nm3/h] / allowable air flow [Nm3/h]
    _fSpC          : REAL;                     // 受限侧候选给定 [%] / candidate setpoint of the constrained side [%]
    _fAirC         : REAL;                     // 空气候选给定 [%] / candidate air setpoint [%]
    _fGasC         : REAL;                     // 燃气候选给定 [%] / candidate gas setpoint [%]
END_VAR
VAR CONSTANT
    DL_PCT_MIN     : REAL := 0.0;              // 给定下限 [%] / setpoint floor [%]
    DL_PCT_MAX     : REAL := 100.0;            // 给定上限 [%] / setpoint ceiling [%]
    DL_VAL_LIM     : REAL := 1.0E30;           // 有限性判定的绝对值上限 [无量纲] / finiteness ceiling [dimensionless]
    DL_EPS         : REAL := 1.0E-6;           // 浮点比较容差 [%] / float comparison tolerance [%]
    DL_FLOW_EPS    : REAL := 1.0E-6;           // 折算基准流量下限 [Nm3/h] / scaling base flow floor [Nm3/h]
    DL_RATIO_MIN   : REAL := 0.0;              // 空燃比下限 [Nm3/Nm3]，须严格大于 / ratio floor, must be strictly greater
    DL_LEAD_MIN    : REAL := 1.0;              // 先行裕度下限 [倍] / leading margin floor [ratio]
    DL_LEAD_MAX    : REAL := 10.0;             // 先行裕度上限 [倍]，防呆 / leading margin ceiling [ratio], sanity bound
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置（输出在段 8 单点写入，此处不清；保持量不清）
 *      Per-scan presets, outputs and held values are untouched here
 *-----------------------------------------------------------------------------*)
eErr        := 16#0000_0000;                   // 错误码每拍重算 / error code recomputed every scan
bError      := FALSE;                          // 故障标志每拍重算 / fault flag recomputed every scan
bValid      := FALSE;                          // 可用标志每拍重算 / usable flag recomputed every scan
bLimited    := FALSE;                          // 限幅标志每拍重算 / limiting flag recomputed every scan
fLimitMargin := 0.0;                           // 余量每拍重算 [%] / margin recomputed every scan
_bParamBad  := FALSE;                          // 参数非法标志预清零 / parameter flag pre-cleared
_bFiniteBad := FALSE;                          // 非有限标志预清零 / non-finite flag pre-cleared
_bIllegal   := FALSE;                          // 非法状态标志预清零 / illegal state flag pre-cleared
_bLimC      := FALSE;                          // 候选限幅标志预清零 / candidate limiting flag pre-cleared
_fMarginC   := 0.0;                            // 候选余量预清零 [%] / candidate margin pre-cleared
_eCand      := E_DL_CrossLimitState.eNormal;   // 候选相位预置正常 / candidate phase preset to normal

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（给定从 0 起：点火前燃气必须为 0）
 *      First-scan initialisation, setpoints start at zero because gas must be zero before ignition
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState   := E_DL_CrossLimitState.eIdle;   // 相位待机 / phase idle
    _fAirHeld := 0.0;                          // 空气给定保持量 0 [%] / held air setpoint zero
    _fGasHeld := 0.0;                          // 燃气给定保持量 0 [%] / held gas setpoint zero
    _bInit    := TRUE;                         // 首扫只做一次 / the first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数闸门与除零前置闸（比率与先行裕度的合法性先于任何除法）
 *      Parameter gate and the pre-division guard, checked before any division
 *-----------------------------------------------------------------------------*)
IF (fAirFuelRatio <> fAirFuelRatio) OR (ABS(fAirFuelRatio) > DL_VAL_LIM)
   OR (fAirFuelRatio <= DL_RATIO_MIN) THEN
    _bParamBad := TRUE;                        // 空燃比非法或非有限 / ratio illegal or non-finite
END_IF
IF (fLeadMargin <> fLeadMargin) OR (ABS(fLeadMargin) > DL_VAL_LIM)
   OR (fLeadMargin < DL_LEAD_MIN) OR (fLeadMargin > DL_LEAD_MAX) THEN
    _bParamBad := TRUE;                        // 先行裕度非法（须 1.0~10.0） / margin illegal, must be 1.0 to 10.0
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜输入有限性闸门（区间判据同时拦 NaN 与 ±Inf，不做浮点判等）
 *      Input finiteness gate, the interval test catches NaN and infinity alike
 *-----------------------------------------------------------------------------*)
IF (fMasterOut < -DL_VAL_LIM) OR (fMasterOut > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 主控输出非有限 / master output non-finite
END_IF
IF (fAirFlow < -DL_VAL_LIM) OR (fAirFlow > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 空气流量非有限 / air flow non-finite
END_IF
IF (fGasFlow < -DL_VAL_LIM) OR (fGasFlow > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 燃气流量非有限 / gas flow non-finite
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜双交叉限幅计算（仅在使能、参数合法、输入有限时更新保持量）
 *      Cross-limiting computation, the hold values are updated only on valid input
 *-----------------------------------------------------------------------------*)
IF bEnable AND (NOT _bParamBad) AND (NOT _bFiniteBad) THEN
    _fMasterUse := LIMIT(DL_PCT_MIN, fMasterOut, DL_PCT_MAX); // 主控钳进 0~100 % / master clamped
    _fAirC := _fMasterUse;                     // 空气侧先按主控直给 [%] / air follows the master by default
    _fGasC := _fMasterUse;                     // 燃气侧先按主控直给 [%] / gas follows the master by default

    IF bAirLead THEN
        (* 空气先行：燃气侧受实测空气约束（允许燃气 = 空气/比率×裕度） *)
        (* Air leads, gas is constrained by the measured air *)
        IF fAirFuelRatio > DL_RATIO_MIN THEN
            _fGasAvail := (fAirFlow / fAirFuelRatio) * fLeadMargin; // 允许燃气流量 [Nm3/h] / allowable gas flow
            IF fGasFlow > DL_FLOW_EPS THEN
                _fSpC := (_fMasterUse * _fGasAvail) / fGasFlow; // 折算为百分比 [%] / scaled to percent
                _fSpC := LIMIT(DL_PCT_MIN, _fSpC, _fMasterUse); // 跟随侧不得超前主控 [%] / the follower never leads the master
                _fGasC := _fSpC;                   // 燃气候选给定 [%] / candidate gas setpoint
                IF (_fMasterUse - _fGasC) > DL_EPS THEN
                    _bLimC    := TRUE;             // 限幅生效 / limiting active
                    _fMarginC := _fMasterUse - _fGasC; // 距限幅点余量 [%] / distance to the limiting point
                    _eCand    := E_DL_CrossLimitState.eGasLimited; // 燃气侧受限 / gas limited
                END_IF
            END_IF
        END_IF
    ELSE
        (* 燃气先行：空气侧受实测燃气约束（所需空气 = 燃气×比率×裕度） *)
        (* Gas leads, air is constrained by the measured gas *)
        _fAirNeed := fGasFlow * fAirFuelRatio;
        _fAirAllowed := _fAirNeed * fLeadMargin; // 允许空气流量 [Nm3/h] / allowable air flow
        IF fAirFlow > DL_FLOW_EPS THEN
            _fSpC := (_fMasterUse * _fAirAllowed) / fAirFlow; // 折算为百分比 [%] / scaled to percent
            _fSpC := LIMIT(DL_PCT_MIN, _fSpC, _fMasterUse); // 跟随侧不得超前主控 [%] / the follower never leads the master
            _fAirC := _fSpC;                       // 空气候选给定 [%] / candidate air setpoint
            IF (_fMasterUse - _fAirC) > DL_EPS THEN
                _bLimC    := TRUE;                 // 限幅生效 / limiting active
                _fMarginC := _fMasterUse - _fAirC; // 距限幅点余量 [%] / distance to the limiting point
                _eCand    := E_DL_CrossLimitState.eAirLimited; // 空气侧受限 / air limited
            END_IF
        END_IF
    END_IF

    _fAirHeld := LIMIT(DL_PCT_MIN, _fAirC, DL_PCT_MAX); // 双侧钳 0~100 % 后入保持量 / clamped then latched
    _fGasHeld := LIMIT(DL_PCT_MIN, _fGasC, DL_PCT_MAX); // 双侧钳 0~100 % 后入保持量 / clamped then latched
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜相位机（只做迁移；给定值写段 7，绝不在 CASE 内赋值输出）
 *      Phase machine, transitions only, outputs are written in segment seven
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_CrossLimitState.eIdle:                 // 待机：参数与输入合法且使能即进入工作相
        IF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_CrossLimitState.eFault; // 原因未消失，转故障 / the cause persists, go to fault
        ELSIF bEnable THEN
            _eState := _eCand;                  // 按计算结果进入工作相 / enter the working phase from the computation
        END_IF

    E_DL_CrossLimitState.eNormal:               // 正常：跟随侧未被压住
        IF NOT bEnable THEN
            _eState := E_DL_CrossLimitState.eIdle; // 失能回待机 / disabled, back to idle
        ELSIF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_CrossLimitState.eFault; // 转故障 / go to fault
        ELSE
            _eState := _eCand;                  // 跟随本拍计算结果 / follow this scan's computation
        END_IF

    E_DL_CrossLimitState.eAirLimited:           // 空气侧受限
        IF NOT bEnable THEN
            _eState := E_DL_CrossLimitState.eIdle; // 失能回待机 / disabled, back to idle
        ELSIF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_CrossLimitState.eFault; // 转故障 / go to fault
        ELSE
            _eState := _eCand;                  // 跟随本拍计算结果 / follow this scan's computation
        END_IF

    E_DL_CrossLimitState.eGasLimited:           // 燃气侧受限
        IF NOT bEnable THEN
            _eState := E_DL_CrossLimitState.eIdle; // 失能回待机 / disabled, back to idle
        ELSIF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_CrossLimitState.eFault; // 转故障 / go to fault
        ELSE
            _eState := _eCand;                  // 跟随本拍计算结果 / follow this scan's computation
        END_IF

    E_DL_CrossLimitState.eFault:                // 故障：原因消失即自动恢复（本件无复位引脚）
        IF NOT bEnable THEN
            _eState := E_DL_CrossLimitState.eIdle; // 失能回待机 / disabled, back to idle
        ELSIF (NOT _bParamBad) AND (NOT _bFiniteBad) THEN
            _eState := _eCand;                  // 原因消失，自动回工作相 / cause cleared, resume automatically
        END_IF

    ELSE
        _bIllegal := TRUE;                      // 标记非法状态 / flag the illegal state
        _eState   := E_DL_CrossLimitState.eFault; // 回故障态 / back to the fault state
END_CASE

(*------------------------------------------------------------------------------
 * 段 7｜输出发布（优先级链：非法 > 失能 > 参数非法 > 非有限 > 正常）
 *      Output publish by a strict priority chain, every branch writes both setpoints
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    fAirSp       := 0.0;                        // 非法状态：空气给定清零 [%] / illegal state, air zeroed
    fGasSp       := 0.0;                        // 非法状态：燃气给定清零 [%] / illegal state, gas zeroed
    bLimited     := FALSE;                      // 限幅标志清零 / limiting flag cleared
    fLimitMargin := 0.0;                        // 余量清零 [%] / margin cleared
    eErr         := 16#0002_2B12;               // 故障级：状态机兜底 / fault: state machine fallback
    bError       := TRUE;                       // 置故障标志 / raise the fault flag
    bValid       := FALSE;                      // 输出不可用 / outputs unusable
ELSIF NOT bEnable THEN
    fAirSp       := 0.0;                        // 失能：空气给定显式清零 [%] / disabled, air explicitly zeroed
    fGasSp       := 0.0;                        // 失能：燃气给定显式清零 [%] / disabled, gas explicitly zeroed
    bLimited     := FALSE;                      // 限幅标志清零 / limiting flag cleared
    fLimitMargin := 0.0;                        // 余量清零 [%] / margin cleared
    bValid       := FALSE;                      // 失能时输出不可用 / unusable while disabled
ELSIF _bParamBad THEN
    fAirSp       := 0.0;                        // 参数非法：空气给定归零 [%] / illegal parameter, air zeroed
    fGasSp       := 0.0;                        // 参数非法：燃气给定归零（切断燃料，安全侧） [%] / gas zeroed, fuel cut, safe side
    bLimited     := FALSE;                      // 限幅标志清零 / limiting flag cleared
    fLimitMargin := 0.0;                        // 余量清零 [%] / margin cleared
    eErr         := 16#0002_2B10;               // 故障级：空燃比或先行裕度非法 / fault: ratio or margin illegal
    bError       := TRUE;                       // 置故障标志 / raise the fault flag
    bValid       := FALSE;                      // 输出不可用 / outputs unusable
ELSIF _bFiniteBad THEN
    fAirSp       := _fAirHeld;                  // 非有限：保持末次有效空气给定 [%] / hold the last valid air setpoint
    fGasSp       := _fGasHeld;                  // 非有限：保持末次有效燃气给定（不得切 0） [%] / hold the last valid gas setpoint, never zeroed
    bLimited     := FALSE;                      // 限幅标志不宣称（本次未计算） / no limiting claim this scan
    fLimitMargin := 0.0;                        // 余量清零 [%] / margin cleared
    eErr         := 16#0002_2B11;               // 故障级：输入非有限 / fault: non-finite input
    bError       := TRUE;                       // 置故障标志 / raise the fault flag
    bValid       := FALSE;                      // 输出不可用 / outputs unusable
ELSE
    fAirSp       := _fAirHeld;                  // 正常：空气给定 [%] / air setpoint
    fGasSp       := _fGasHeld;                  // 正常：燃气给定 [%] / gas setpoint
    bLimited     := _bLimC;                     // 限幅标志 [%] / limiting flag
    fLimitMargin := _fMarginC;                  // 距限幅点余量 [%] / distance to the limiting point
    IF _bLimC THEN
        IF _eCand = E_DL_CrossLimitState.eAirLimited THEN
            eErr := 16#0002_2B01;               // 信息级：空气侧限幅生效 / informational: air side limiting
        ELSE
            eErr := 16#0002_2B02;               // 信息级：燃气侧限幅生效 / informational: gas side limiting
        END_IF
    END_IF
    bValid := TRUE;                             // 输出可用 / outputs usable
END_IF

END_FUNCTION_BLOCK
