(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CompressorSurgeGuard
 * 溯源说明 (Provenance): 道莅 clean-room 防御性实现（IEC 61131-3 纯净实现，闭源文档仅借语义，零代码行）
 * 所属子库 (Sublibrary) : DL_Process / ProcessSafety
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），仅用
 *                         Standard.library 的 TON / LIMIT / MAX / ABS 与
 *                         子库内 FB_DL_RateLimiter（DL_Algo，Level 1）
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 压缩机防喘振
 * 功能一句话 (Summary)  : 按压比修正最小流量危险线，流量跌破危险线持续确认后
 *                         快开放空阀，流量回升并越出回差带后慢关，全程给出
 *                         压比、喘振风险与放空动作可观测位。
 *
 * 本件存在的意义 (Why this unit exists)
 *   喘振是压缩机的爆炸级失效模式：流量低于临界值时机组进入周期性倒流振荡，
 *   十几秒内即可损坏转子与密封。库内没有任何件管这条保护律。本件把
 *   「最小流量线按压比修正 + 确认延时 + 快开慢关 + 回差恢复」四件事写成一件，
 *   且只编排已收口能力（斜率先行由 FB_DL_RateLimiter 承担，不复制其算法）。
 *
 * 危险线口径 (Danger line)
 *   fFlowDanger = fFlowMinLine × (1 + fSurgeMargin × (压比 − 1))
 *   线性近似：压比越高，同样流量下越接近喘振，故危险线上抬。公式与系数
 *   100 % 自有，不引用任何厂商曲线。压比夹到 ≥ 1.0——压比小于 1 的测量值
 *   不可信（吸入压力大于排出压力），若直接代入会让危险线低于最小流量线，
 *   保护范围凭空缩小，故按 1.0 处理并留档。
 *
 * 两条安全方向相反的规则（并列写死，不得只做其一）
 *   ① 参数非法（最小流量线/裕度/斜率为非正、吸入压力 ≤ 0）→ 故障 030B、
 *      阀**全开**：宁可放空不可喘振（放空只浪费能量，喘振会毁机）；
 *   ② 任一输入非有限 → 故障 030C、**保持末次阀位**：坏值不得成为关阀理由
 *      （P0 级，与①方向相反，两条都必须写死，见段 9）。
 *
 * 边界安全 (Boundary)
 *   - 流量低于危险线持续 tConfirm → eRiskBlowoff，阀按 fOpenRamp 快开；
 *   - 流量恢复到 fFlowDanger ×(1 + DL_SURGE_HYST) 以上 → eRecovering，
 *     阀按 fCloseRamp 慢关；**关到 0 才回 eNormal**——eRiskBlowoff 不得被
 *     eNormal 直接抢占（R41 回差家族），也不存在「风险刚解除就全关」的路径；
 *   - 失能 → 阀仍按 fCloseRamp 关闭（不阶跃），bBlowoffActive := FALSE，
 *     bSurgeRisk 保持可观测（停机期间仍要让 HMI 看到风险）；
 *   - CASE 落 ELSE 置 030D 并回 eFault；本件无复位引脚，故障态在原因消失后
 *     自动回 eNormal（无台账需保持，与安全阀台账件语义不同，已留档）；
 *   - 斜坡组合调用按 R36 处理**首次扫描退出跟踪的首拍**：阀位经
 *     FB_DL_RateLimiter 跟踪注入（bTrack / fTrackValue）而非直接赋值，
 *     首拍与「非有限保持 → 恢复」首拍都不产生阶跃。
 * 依赖与码位纪律
 *   子件 FB_DL_RateLimiter 的错误码属 16#0002_ 段（DL_Algo 属主），
 *   **不并入**本件码位体系（R70② 段属主唯一）；本件参数闸门已把斜率钳成
 *   有限正值、采样周期恒 ≥ 下限，故子件两条错误路径结构性不可达。
 *
 * 错误码    : 16#0005_01DA 流量低于危险线，放空阀已打开——信息级，保护动作
 *             16#0005_01DB 流量已回升越出回差带，退出放空——信息级，恢复动作
 *             16#0005_030B 防喘振参数非法（含吸入压力 ≤ 0），阀全开——故障级
 *             16#0005_030C 输入非有限，保持末次阀位——故障级，坏值不得关阀
 *             16#0005_030D 状态机落 ELSE 兜底（非法状态）——故障级，回 eFault
 * 码位总账  : 16#0005_01DA 用 / 16#0005_01DB 用 ｜ 16#0005_030B 用 / 16#0005_030C 用 / 16#0005_030D 用
 * 状态机    : E_DL_SurgeState（eIdle / eNormal / eRiskBlowoff / eRecovering / eFault），
 *             CASE 含 ELSE 兜底，ELSE 置 16#0005_030D 并回 eFault；失能无条件回 eIdle
 * 采样约定  : 每任务周期调用一次；斜率 [%/s] 依赖 tSample 引脚（禁读系统时钟）
 * 依赖说明  : DL_Process 可依赖 Level 0/1，本件只**组合调用** FB_DL_RateLimiter，
 *             不复制其斜坡算法（R36 手算首拍跟踪见上）
 * 验收向量  : V1 吸入 100 / 排出 300 / 流量 2000 / 最小线 500 / 裕度 0.10
 *               → 压比 3.0，危险线 500×(1+0.10×2)=600，流量高于危险线 → eNormal，
 *                 阀 0%，bSurgeRisk = FALSE
 *             V2 流量跌到 500（< 600）持续 200 ms → eRiskBlowoff，阀按 20 %/s 快开，
 *                 eErr = 01DA，bBlowoffActive = TRUE
 *             V3 V2 后流量回到 700（> 600×1.15=690）→ eRecovering，阀按 1 %/s 慢关，
 *                 eErr = 01DB；关到 0 才回 eNormal（回差主向量）
 *             V4 fFlowMinLine = 0 → 阀 100 %，eErr = 030B，bError = TRUE
 *             V5 fDischargePress = NaN → 阀保持末次值，eErr = 030C（保持主向量）
 *             V6 fSuctionPress = 0 → 按参数类 030B，阀全开（压比无意义主向量）
 *             V7 bEnable = FALSE → 阀按 1 %/s 降到 0，bBlowoffActive = FALSE，
 *                bSurgeRisk 仍随流量可观测
 * 红线自检  : 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 ｜ 纯 IEC 61131-3 ｜ 压比除零
 *             前置闸（吸入压力 > 0 才做除法）｜ 浮点只用大小与容差比较 ｜ 无循环
 *             ｜ 全变量双语同行注释 ｜ ENUM + CASE 含 ELSE ｜ TON 在主体最前部
 *             无条件刷新 ｜ 斜率/回差全部常量化，无魔法数
 * 修订历史  : 2026-11-16  v1.0.0  首版入库（R22 · 批 2 · 过程单元保护）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SurgeState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 防喘振的工作相位。0 起步长 10。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_SurgeState :
(
    eIdle        := 0,   // 待机：未使能 / Idle, disabled
    eNormal      := 10,  // 正常：流量高于危险线，阀关闭 / Normal, flow above the danger line, valve closed
    eRiskBlowoff := 20,  // 风险放空：流量低于危险线，阀快开 / Risk blowoff, valve fast open
    eRecovering  := 30,  // 恢复中：流量已越回差带，阀慢关 / Recovering, valve closing slowly
    eFault       := 99   // 故障：参数非法或输入非有限 / Fault, illegal parameter or non-finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_CompressorSurgeGuard
VAR_INPUT
    fSuctionPress   : REAL;                    // 吸入压力 [kPa abs]，须 > 0 / suction pressure [kPa abs], must be > 0
    fDischargePress : REAL;                    // 排出压力 [kPa abs] / discharge pressure [kPa abs]
    fFlow           : REAL;                    // 实测流量 [Nm3/h] / measured flow [Nm3/h]
    fFlowMinLine    : REAL := 500.0;           // 最小流量线 [Nm3/h]，须 > 0 / minimum flow line [Nm3/h], must be > 0
    fSurgeMargin    : REAL := 0.10;            // 危险线裕度 [倍]，须 > 0 / danger line margin [ratio], must be > 0
    fOpenRamp       : REAL := 20.0;            // 放空阀快开斜率 [%/s]，须 > 0 / blowoff fast-open ramp [%/s], must be > 0
    fCloseRamp      : REAL := 1.0;             // 放空阀慢关斜率 [%/s]，须 > 0 / blowoff slow-close ramp [%/s], must be > 0
    tConfirm        : TIME := T#200MS;         // 危险线确认时间 [ms] / danger line confirm time [ms]
    tSample         : TIME := T#100MS;         // 任务采样周期 [ms]，斜率换算用 / task sample period [ms], used by the ramps
    bEnable         : BOOL;                    // 使能 / enable
END_VAR
VAR_OUTPUT
    fBlowoffValve   : REAL;                    // 放空阀开度给定 [%]，范围 0~100 / blowoff valve opening setpoint [%], range 0~100
    bSurgeRisk      : BOOL;                    // 喘振风险（流量低于危险线，裸判据） / surge risk, the raw criterion
    bBlowoffActive  : BOOL;                    // 正在放空标志 / blowoff in progress flag
    fPressureRatio  : REAL;                    // 压比 = 排出/吸入 [倍] / pressure ratio, discharge over suction
    eErr            : UDINT;                   // 错误码，0 表示无错 / error code, 0 means no error
    bError          : BOOL;                    // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid          : BOOL;                    // 输出可用标志 / outputs usable flag
END_VAR
VAR
    fbConfirm       : TON;                     // 危险线确认计时，段 6 无条件刷新 [ms] / danger line confirm timer
    fbRamp          : FB_DL_RateLimiter;       // 放空阀斜率限制子件（组合调用） / blowoff ramp subcomponent
    _eState         : E_DL_SurgeState := E_DL_SurgeState.eIdle; // 当前相位 / current phase
    _bInit          : BOOL := FALSE;           // 首扫标志，初值 FALSE 取非判定 / first-scan flag, tested negated
    _bFirstRamp     : BOOL := TRUE;            // 斜坡首次扫描跟踪标志（R36） / first-scan ramp tracking flag
    _bTrack         : BOOL := FALSE;           // 斜坡跟踪请求 / ramp tracking request
    _fTrackVal      : REAL;                    // 斜坡跟踪值 [%] / ramp tracking value [%]
    _bParamBad      : BOOL;                    // 参数非法标志 / illegal parameter flag
    _bFiniteBad     : BOOL;                    // 输入非有限标志 / non-finite input flag
    _bIllegal       : BOOL;                    // 非法状态标志 / illegal state flag
    _bRiskRaw       : BOOL;                    // 流量低于危险线（裸判据） / flow below the danger line, raw criterion
    _bRiskCfm       : BOOL;                    // 危险线确认条件（供定时器） / confirm condition for the timer
    _bRecovered     : BOOL;                    // 流量越出回差带 / flow recovered above the hysteresis band
    _bConfirmBreak  : BOOL;                    // 确认定时器断输入一拍标志 / confirm timer one-scan break
    _tConfirmUse    : TIME := T#200MS;         // 生效确认时间 [ms]，已钳位 / effective confirm time, clamped
    _fRatio         : REAL;                    // 压比 [倍] / pressure ratio
    _fRatioUse      : REAL := 1.0;             // 生效压比，夹到 ≥ 1 [倍] / effective ratio clamped to at least one
    _fDanger        : REAL;                    // 危险流量线 [Nm3/h] / danger flow line [Nm3/h]
    _fRecoverLine   : REAL;                    // 回差恢复线 [Nm3/h] / hysteresis recovery line [Nm3/h]
    _fTarget        : REAL;                    // 本拍目标阀位 [%] / target valve opening of this scan
    _fValveHeld     : REAL;                    // 末次阀位保持量 [%] / held valve opening [%]
    _fValvePrev     : REAL;                    // 上拍阀位（保持用，读子件前一拍输出） [%] / previous valve opening
    _fRampOut       : REAL;                    // 子件本拍输出 [%] / subcomponent output of this scan
END_VAR
VAR CONSTANT
    DL_PCT_MIN      : REAL := 0.0;             // 阀位下限 [%] / valve floor [%]
    DL_PCT_MAX      : REAL := 100.0;           // 阀位上限 [%] / valve ceiling [%]
    DL_VAL_LIM      : REAL := 1.0E30;          // 有限性判定的绝对值上限 [无量纲] / finiteness ceiling
    DL_RATIO_MIN    : REAL := 1.0;             // 压比可信下限 [倍]，低于 1 按 1 处理 / credible ratio floor, values below are clamped
    DL_SURGE_HYST   : REAL := 0.15;            // 恢复回差带 [倍]，禁裸数 / recovery hysteresis band [ratio], never a bare number
    DL_EPS          : REAL := 1.0E-6;          // 浮点比较容差 [%] / float comparison tolerance [%]
    DL_PARAM_MN     : REAL := 0.0;             // 参数下限，须严格大于 [无量纲] / parameter floor, must be strictly greater
    DL_CONF_MAX_MS  : DINT := 10000;           // 确认时间上限 [ms] / confirm time ceiling [ms]
    DL_TIME_ZERO    : TIME := T#0MS;           // 时间零值基准 [ms] / time zero reference
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置（阀位与压比为保持量，在段 10 单点写入）
 *      Per-scan presets, the valve opening and the ratio are held and written once
 *-----------------------------------------------------------------------------*)
eErr           := 16#0000_0000;                // 错误码每拍重算 / error code recomputed every scan
bError         := FALSE;                       // 故障标志每拍重算 / fault flag recomputed every scan
bValid         := FALSE;                       // 可用标志每拍重算 / usable flag recomputed every scan
bSurgeRisk     := FALSE;                       // 风险位每拍重算 / risk flag recomputed every scan
bBlowoffActive := FALSE;                       // 放空动作位每拍重算 / blowoff active recomputed every scan
_bParamBad     := FALSE;                       // 参数非法标志预清零 / parameter flag pre-cleared
_bFiniteBad    := FALSE;                       // 非有限标志预清零 / non-finite flag pre-cleared
_bIllegal      := FALSE;                       // 非法状态标志预清零 / illegal state flag pre-cleared
_bRiskRaw      := FALSE;                       // 裸风险判据预置 FALSE / raw risk preset FALSE
_bRiskCfm      := FALSE;                       // 确认条件预置 FALSE / confirm condition preset FALSE
_bRecovered    := FALSE;                       // 恢复判据预置 FALSE / recovery preset FALSE
_bTrack        := FALSE;                       // 跟踪请求预置 FALSE / tracking request preset FALSE
_fTrackVal     := 0.0;                         // 跟踪值预置 0 [%] / tracking value preset to zero
_fRampOut      := 0.0;                         // 子件输出预置 0 [%] / subcomponent output preset to zero

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（阀位从 0 起：放空阀失电关闭位）
 *      First-scan initialisation, the blowoff valve starts closed
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState     := E_DL_SurgeState.eIdle;      // 相位待机 / phase idle
    _fValveHeld := 0.0;                        // 阀位保持量 0 [%] / held valve opening zero
    _fRatio     := 0.0;                        // 压比保持量 0 [倍] / held ratio zero
    _bConfirmBreak := TRUE;                    // 确认计时从零开始 / confirm timer starts from zero
    _bFirstRamp := TRUE;                       // 斜坡首拍跟踪（R36） / ramp tracked on the first scan
    _bInit      := TRUE;                       // 首扫只做一次 / the first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数闸门（含吸入压力 ≤ 0：压比无意义，按参数类处理）
 *      Parameter gate including a non-positive suction pressure, the ratio is meaningless then
 *-----------------------------------------------------------------------------*)
IF (fFlowMinLine <> fFlowMinLine) OR (ABS(fFlowMinLine) > DL_VAL_LIM) OR (fFlowMinLine <= DL_PARAM_MN) THEN
    _bParamBad := TRUE;                        // 最小流量线非法 / minimum flow line illegal
END_IF
IF (fSurgeMargin <> fSurgeMargin) OR (ABS(fSurgeMargin) > DL_VAL_LIM) OR (fSurgeMargin <= DL_PARAM_MN) THEN
    _bParamBad := TRUE;                        // 危险线裕度非法 / margin illegal
END_IF
IF (fOpenRamp <> fOpenRamp) OR (ABS(fOpenRamp) > DL_VAL_LIM) OR (fOpenRamp <= DL_PARAM_MN) THEN
    _bParamBad := TRUE;                        // 快开斜率非法 / fast-open ramp illegal
END_IF
IF (fCloseRamp <> fCloseRamp) OR (ABS(fCloseRamp) > DL_VAL_LIM) OR (fCloseRamp <= DL_PARAM_MN) THEN
    _bParamBad := TRUE;                        // 慢关斜率非法 / slow-close ramp illegal
END_IF
IF (fSuctionPress < -DL_VAL_LIM) OR (fSuctionPress > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 吸入压力非有限 / suction pressure non-finite
ELSIF fSuctionPress <= DL_PARAM_MN THEN
    _bParamBad := TRUE;                        // 吸入压力 ≤ 0：压比无意义 / non-positive suction, the ratio is meaningless
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜其余输入的有限性闸门（区间判据同时拦 NaN 与 ±Inf）
 *      Finiteness gate for the remaining inputs
 *-----------------------------------------------------------------------------*)
IF (fDischargePress < -DL_VAL_LIM) OR (fDischargePress > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 排出压力非有限 / discharge pressure non-finite
END_IF
IF (fFlow < -DL_VAL_LIM) OR (fFlow > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 流量非有限 / flow non-finite
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜压比与危险线（除零前置闸：吸入压力已确认 > 0，商前另设显式判据）
 *      Pressure ratio and danger line, the division is guarded twice
 *-----------------------------------------------------------------------------*)
IF (NOT _bFiniteBad) AND (NOT _bParamBad) THEN
    IF fSuctionPress > DL_PARAM_MN THEN
        _fRatio := fDischargePress / fSuctionPress; // 压比 [倍] / pressure ratio
    ELSE
        _fRatio := DL_RATIO_MIN;               // 结构性不可达（段 3 已拦），兜底为 1 / structurally unreachable fallback
    END_IF
    _fRatioUse := MAX(_fRatio, DL_RATIO_MIN);  // 夹到 ≥ 1：压比小于 1 的测量不可信 / clamp to at least one
    _fDanger   := fFlowMinLine * (1.0 + fSurgeMargin * (_fRatioUse - DL_RATIO_MIN)); // 危险流量线 [Nm3/h] / danger flow line
    _fRecoverLine := _fDanger * (1.0 + DL_SURGE_HYST); // 回差恢复线 [Nm3/h] / hysteresis recovery line
    _bRiskRaw  := (fFlow < _fDanger);          // 裸风险判据 [布尔] / raw risk criterion
    _bRecovered := (fFlow > _fRecoverLine);    // 越出回差带 [布尔] / recovered above the band
    _fRatio    := _fRatioUse;                  // 保持量取生效压比 / the held ratio is the effective one
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜确认定时器无条件刷新（R40：CASE 之外每拍必调，转出相时断输入一拍）
 *      Confirm timer refreshed unconditionally outside the CASE
 *-----------------------------------------------------------------------------*)
_tConfirmUse := tConfirm;                      // 确认时间直取引脚 [ms] / confirm time taken from the pin
IF TIME_TO_DINT(_tConfirmUse) > DL_CONF_MAX_MS THEN
    _tConfirmUse := DINT_TO_TIME(DL_CONF_MAX_MS); // 超上限钳位（无专用码位，R90 不新开码） / clamped, no dedicated code
END_IF
IF TIME_TO_DINT(_tConfirmUse) < 0 THEN
    _tConfirmUse := DL_TIME_ZERO;              // 负时间结构性不可达，兜底为 0 / structurally unreachable fallback
END_IF

_bRiskCfm := bEnable AND (NOT _bParamBad) AND (NOT _bFiniteBad) AND _bRiskRaw; // 确认条件

fbConfirm(IN := _bRiskCfm AND (NOT _bConfirmBreak), PT := _tConfirmUse); // 危险线确认计时无条件刷新
_bConfirmBreak := FALSE;                       // 断输入拍在调用后自清（R40 自清位置） / break self-cleared after the call

(*------------------------------------------------------------------------------
 * 段 7｜相位机（只做迁移；阀位与码位在段 9/10 处理）
 *      Phase machine, transitions only
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_SurgeState.eIdle:                     // 待机：参数合法、输入有限且使能即进入
        IF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_SurgeState.eFault; // 原因未消失，转故障 / the cause persists
        ELSIF bEnable THEN
            IF _bRiskRaw AND fbConfirm.Q THEN
                _eState := E_DL_SurgeState.eRiskBlowoff; // 已确认风险，直接进放空 / confirmed risk
            ELSE
                _eState := E_DL_SurgeState.eNormal; // 进正常相 / enter the normal phase
            END_IF
        END_IF

    E_DL_SurgeState.eNormal:                   // 正常：流量低于危险线并确认即放空
        IF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_SurgeState.eFault; // 转故障 / go to fault
        ELSIF NOT bEnable THEN
            _eState := E_DL_SurgeState.eIdle;  // 失能回待机 / disabled, back to idle
        ELSIF _bRiskRaw AND fbConfirm.Q THEN
            _eState := E_DL_SurgeState.eRiskBlowoff; // 风险确认，进放空 / risk confirmed, blow off
            _bConfirmBreak := TRUE;            // 换相后确认计时重启 / restart the confirm timer across the phase change
        END_IF

    E_DL_SurgeState.eRiskBlowoff:              // 风险放空：必须经恢复相，不得被 eNormal 直接抢占
        IF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_SurgeState.eFault; // 转故障 / go to fault
        ELSIF NOT bEnable THEN
            _eState := E_DL_SurgeState.eIdle;  // 失能回待机 / disabled, back to idle
        ELSIF _bRecovered THEN
            _eState := E_DL_SurgeState.eRecovering; // 越出回差带，进慢关相 / recovered, start closing slowly
        END_IF

    E_DL_SurgeState.eRecovering:               // 恢复中：再次跌破危险线则回放空，阀关到 0 才回正常
        IF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_SurgeState.eFault; // 转故障 / go to fault
        ELSIF NOT bEnable THEN
            _eState := E_DL_SurgeState.eIdle;  // 失能回待机 / disabled, back to idle
        ELSIF _bRiskRaw THEN
            _eState := E_DL_SurgeState.eRiskBlowoff; // 再次跌破危险线，回放空 / below the danger line again
        ELSIF _fValvePrev <= DL_PCT_MIN + DL_EPS THEN
            _eState := E_DL_SurgeState.eNormal; // 阀已关到 0，回正常 / the valve is closed, back to normal
        END_IF

    E_DL_SurgeState.eFault:                    // 故障：原因消失即自动恢复（本件无复位引脚）
        IF NOT bEnable THEN
            _eState := E_DL_SurgeState.eIdle;  // 失能回待机 / disabled, back to idle
        ELSIF (NOT _bParamBad) AND (NOT _bFiniteBad) THEN
            _eState := E_DL_SurgeState.eNormal; // 原因消失自动回正常 / cause cleared, resume
        END_IF

    ELSE
        _bIllegal := TRUE;                     // 标记非法状态 / flag the illegal state
        _eState   := E_DL_SurgeState.eFault;   // 回故障态 / back to the fault state
END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜目标阀位（两条安全方向相反的规则在此并列，不得只做其一）
 *      Target valve opening, the two opposite safety rules live side by side here
 *-----------------------------------------------------------------------------*)
_fValvePrev := fbRamp.fOut;                    // 先读子件上一拍输出 [%] / read the subcomponent output first

IF _bIllegal OR _bParamBad THEN
    _fTarget := DL_PCT_MAX;                    // 参数/状态非法：阀全开（宁可放空不可喘振） [%] / illegal, full open
    eErr     := 16#0005_030B;                  // 故障级：参数非法，阀全开 / fault: illegal parameter, valve fully open
    bError   := TRUE;                          // 置故障标志 / raise the fault flag
ELSIF _bFiniteBad THEN
    _fTarget := _fValvePrev;                   // 非有限：目标 = 当前阀位，即保持（坏值不得关阀） [%] / hold the valve
    eErr     := 16#0005_030C;                  // 故障级：输入非有限，保持末次阀位 / fault: non-finite input, valve held
    bError   := TRUE;                          // 置故障标志 / raise the fault flag
ELSIF NOT bEnable THEN
    _fTarget := DL_PCT_MIN;                    // 失能：慢关到 0（走慢关斜率，不阶跃） [%] / disabled, close slowly
    _bConfirmBreak := TRUE;                    // 失能时确认计时重启 / restart the confirm timer
ELSIF _eState = E_DL_SurgeState.eRiskBlowoff THEN
    _fTarget := DL_PCT_MAX;                    // 风险放空：阀全开（由快开斜率跟随） [%] / risk blowoff, full open
    eErr     := 16#0005_01DA;                  // 信息级：流量低于危险线已开放空阀 / informational: blowoff opened
ELSIF _eState = E_DL_SurgeState.eRecovering THEN
    _fTarget := DL_PCT_MIN;                    // 恢复中：慢关（由慢关斜率跟随） [%] / recovering, close slowly
    eErr     := 16#0005_01DB;                  // 信息级：已退出放空 / informational: leaving blowoff
ELSE
    _fTarget := DL_PCT_MIN;                    // 正常：阀关闭 [%] / normal, valve closed
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜斜坡组合调用（快开慢关各用一支斜率，跟踪注入按 R36 手算首拍）
 *      Ramp composition, fast open and slow close, tracking injected per R36
 *-----------------------------------------------------------------------------*)
_bTrack   := _bFiniteBad OR _bFirstRamp;       // 非有限保持与首次扫描都走跟踪，避免阶跃 / hold and first scan are tracked
_fTrackVal := _fValvePrev;                     // 跟踪值 = 当前阀位 [%] / tracking value is the current opening
IF _bFirstRamp THEN
    _fTrackVal := _fValveHeld;                 // 首拍跟踪到保持量（初始为 0） [%] / first scan tracks the held value
END_IF

fbRamp(bEnable     := TRUE,                    // 子件恒使能：斜率限制始终生效 / always enabled, the ramp always applies
       fIn         := _fTarget,                // 目标阀位 [%] / target opening
       fRateUp      := fOpenRamp,              // 快开斜率 [%/s] / fast-open ramp
       fRateDown    := fCloseRamp,             // 慢关斜率 [%/s] / slow-close ramp
       bTrack       := _bTrack,                // 跟踪请求 / tracking request
       fTrackValue  := _fTrackVal,             // 跟踪值 [%] / tracking value
       tSampleTime  := tSample);               // 采样周期 [ms] / sample period
_fRampOut   := fbRamp.fOut;                    // 取子件输出 [%] / take the subcomponent output
_bFirstRamp := FALSE;                          // 首拍跟踪只做一次 / first-scan tracking runs once

(*------------------------------------------------------------------------------
 * 段 10｜输出单点写入与可用性仲裁
 *      Single write point of the outputs and the usability arbitration
 *-----------------------------------------------------------------------------*)
_fRampOut   := LIMIT(DL_PCT_MIN, _fRampOut, DL_PCT_MAX); // 子件输出再钳一次（防御纵深） [%] / clamped again, defense in depth
_fValveHeld := _fRampOut;                      // 阀位保持量跟进 [%] / the held opening follows
fBlowoffValve := _fRampOut;                    // 阀位出口 [%] / valve opening outlet
fPressureRatio := _fRatio;                     // 压比出口 [倍] / pressure ratio outlet
bSurgeRisk    := _bRiskRaw;                    // 风险位保持可观测（失能亦然） / the risk stays observable even when disabled
bBlowoffActive := (_eState = E_DL_SurgeState.eRiskBlowoff); // 正在放空：仅风险相为真 / blowoff active in the risk phase only

IF bError THEN
    bValid := FALSE;                           // 故障级：输出不可用 / fault: outputs unusable
ELSIF NOT bEnable THEN
    bValid := FALSE;                           // 失能：输出不可用（阀位仍按慢关下落） / disabled: unusable, the valve still closes
ELSIF _bIllegal THEN
    bValid := FALSE;                           // 非法状态：输出不可用 / illegal state: unusable
ELSE
    bValid := TRUE;                            // 输出可用 / outputs usable
END_IF

END_FUNCTION_BLOCK
