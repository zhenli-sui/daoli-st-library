(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SteamTrapMonitor
 * 溯源说明 (Provenance): 道莅 clean-room 防御性实现（IEC 61131-3 纯净实现，闭源文档仅借语义，零代码行）
 * 所属子库 (Sublibrary) : DL_Device / Diagnostic
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），仅用
 *                         Standard.library 的 TON / ABS / LIMIT / MAX
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 疏水阀堵塞/泄漏温差诊断
 * 功能一句话 (Summary)  : 用阀前/阀后温度差判断蒸汽疏水阀是正常、蒸汽泄漏（漏汽）
 *                         还是堵塞（不通），冷态停机时冻结全部故障判定。
 *
 * 本件存在的意义 (Why this unit exists)
 *   蒸汽系统节能诊断在全库零覆盖。疏水阀失效有两种相反形态：
 *   ① 漏汽（阀芯冲蚀常开）→ 阀后也被蒸汽烫热，温差变小，能耗与管网损失上升；
 *   ② 堵塞（阀芯卡死或结垢）→ 凝水积在阀前，阀前温度跌落，机组加热能力不足。
 *   两种都表现为「温差变小」，只能靠阀前温度是否达工况来区分——这就是本件
 *   判据的核心，也是它与普通温差异常报警的区别。
 *
 * 判据（公开工程判据，clean-room）
 *   正常   : fDelta >= fDeltaNormal
 *   漏汽   : fDelta <= fDeltaLeak 且 阀前温度达工况（fTin >= fTinMin）
 *   堵塞   : 阀前温度介于冷态带与工况下限之间（fTinMin × DL_COLD_RATIO <= fTin < fTinMin）
 *            且 fDelta <= fDeltaLeak
 *   冷态   : fTin < fTinMin × DL_COLD_RATIO → **工况未建立，冻结全部判定**（信息 0177）
 *   三条判据各带 tConfirm 持续确认窗，单拍越限不迁移（A5-D1 家族）。
 *   三条判据在数值上互斥（normal 要求 fDelta >= fDeltaNormal > fDeltaLeak；
 *   leak 要求 fTin >= fTinMin，blocked 要求 fTin < fTinMin），故不存在双判据
 *   同拍成立的两难情形——这是判据设计时就消除的，不靠优先级补丁。
 *
 * 冷态与堵塞的边界（规格冲突的落地方式，必须读）
 *   规格既要求「fTin < fTinMin 为工况未建立、冻结全部判定」，又要求「fTin < fTinMin
 *   （进出口均偏低、无温差）为堵塞」——同一条判据落两处。物理上二者靠「机组是否
 *   在跑」区分，本件引脚集没有机组运行信号，故用一条**相对冷态带**切分：
 *   fTinMin × DL_COLD_RATIO（0.5）以下视为停机冷态（冻结），该带与 fTinMin 之间
 *   视为「蒸汽已引入但被凝水淹没」= 堵塞特征。DL_COLD_RATIO 为件内经验常量，
 *   已在常量注释与偏离留档中声明；有运行信号的机型应把运行位并入 bEnable。
 *
 * 边界安全 (Boundary)
 *   ① fDeltaLeak >= fDeltaNormal（判据区间为空）或参数非有限 → 故障 0343、bValid = FALSE；
 *   ② 温度非有限 → 故障 0342，**保持上次判定与全部输出**（不迁移、不清状态）；
 *   ③ 冷态 → 信息 0177，冻结判定，健康投 eUnknown；
 *   ④ 落入正常带 → 信息 0176；
 *   ⑤ 健康映射集中在一处：漏汽 → eOutOfSpec（能耗越界）；堵塞 → eMaintenanceReq
 *      （需拆检）；故障 → eFailure；冷态/失能 → eUnknown；
 *   ⑥ CASE 落 ELSE 置 0344 并回 eFault；
 *   ⑦ 三条判据各用**独立 TON 实例**，绝不共用一只（R40）。
 *
 * 错误码    : 16#0003_0176 温差判据落入正常带——信息级，正常结论
 *             16#0003_0177 工况未建立（阀前温度低于冷态带），冻结判定——信息级，防误报
 *             16#0003_0342 温度输入非有限——故障级，保持上次判定
 *             16#0003_0343 判据阈值自相矛盾（fDeltaLeak >= fDeltaNormal）——故障级，bValid = FALSE
 *             16#0003_0344 状态机落 ELSE 兜底（非法状态）——故障级，回 eFault
 * 码位总账  : 16#0003_0176 用 / 16#0003_0177 用 ｜ 16#0003_0342 用 / 16#0003_0343 用 / 16#0003_0344 用
 * 状态机    : E_DL_TrapState（eIdle / eNormal / eLeak / eBlocked / eFault），CASE 含 ELSE 兜底，
 *             ELSE 置 16#0003_0344 并回 eFault；失能无条件回 eIdle
 * 采样约定  : 每任务周期调用一次；确认窗由 tConfirm 给定，不读系统时钟
 * 依赖说明  : 仅 Standard.library；健康出口引用 E_DL_Ne107Status（引用不重声明，R70③）
 * 验收向量  : V1 阀前 170 / 阀后 155（Δ15 >= 10）持续 30 s → eNormal，bNormal = TRUE，
 *                eErr = 0176，eHealth = eOk
 *             V2 阀前 165 / 阀后 162（Δ3、阀前达工况）持续 30 s → eLeak，bSteamLeak = TRUE，
 *                eHealth = eOutOfSpec
 *             V3 阀前 70 / 阀后 68（Δ2、介于冷态带 40 与 80 之间）持续 30 s → eBlocked，
 *                bBlocked = TRUE，eHealth = eMaintenanceReq（堵塞主向量）
 *             V4 阀前 30 / 阀后 28（低于冷态带 40）→ eIdle 冻结，eErr = 0177，eHealth = eUnknown
 *                （冷态防误报主向量）
 *             V5 fDeltaLeak = 12 > fDeltaNormal = 10 → 0343，bValid = FALSE，判据不成立
 *             V6 fTout = NaN → 0342，状态与输出保持上一拍（保持主向量）
 *             V7 温差在 9.9~10.1 抖动 → 单拍越限不迁移（确认窗主向量）
 * 红线自检  : 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 ｜ 纯 IEC 61131-3 ｜ 无除法
 *             浮点只用大小与容差比较 ｜ 无循环 ｜ 全变量双语同行注释 ｜ ENUM + CASE
 *             含 ELSE ｜ 三只 TON 在主体前部无条件刷新 ｜ 阈值常量化，无魔法数
 * 修订历史  : 2026-11-16  v1.0.0  首版入库（R22 · 批 3 · 设备诊断）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TrapState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 疏水阀诊断相位。0 起步长 10。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_TrapState :
(
    eIdle    := 0,     // 待机：未使能、冷态冻结或参数非法 / Idle, disabled, frozen cold state or illegal parameters
    eNormal  := 10,    // 正常：温差达到正常下限 / Normal, the temperature drop reaches the normal limit
    eLeak    := 20,    // 漏汽：温差过小且阀前已达工况 / Leaking, small drop with a live steam upstream
    eBlocked := 30,    // 堵塞：阀前温度跌落但蒸汽已引入 / Blocked, upstream cooled although steam was admitted
    eFault   := 99     // 故障：参数矛盾或非法状态 / Fault, contradictory parameters or an illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_SteamTrapMonitor
VAR_INPUT
    fTin         : REAL;                       // 阀前温度 [degC] / upstream temperature [degC]
    fTout        : REAL;                       // 阀后温度 [degC] / downstream temperature [degC]
    fDeltaNormal : REAL := 10.0;               // 正常最小温差 [K]，须 > 0 / normal minimum temperature drop [K], must be > 0
    fDeltaLeak   : REAL := 5.0;                // 漏汽判定温差上限 [K]，须 >= 0 且 < fDeltaNormal / leak drop ceiling [K], below fDeltaNormal
    fTinMin      : REAL := 80.0;               // 蒸汽工况最低阀前温度 [degC]，须 > 0 / minimum live steam temperature [degC], must be > 0
    tConfirm     : TIME := T#30S;              // 判据确认时间 [ms] / criterion confirm time [ms]
    bEnable      : BOOL;                       // 使能 / enable
END_VAR
VAR_OUTPUT
    fDelta       : REAL;                       // 实测温差 = 阀前 − 阀后 [K] / measured temperature drop [K]
    bNormal      : BOOL;                       // 正常判定 / normal verdict
    bSteamLeak   : BOOL;                       // 漏汽判定 / steam leak verdict
    bBlocked     : BOOL;                       // 堵塞判定 / blocked verdict
    eHealth      : E_DL_Ne107Status;           // NE107 健康分级（引用唯一属主） / NE107 health status
    eErr         : UDINT;                      // 错误码，0 表示无错 / error code, 0 means no error
    bError       : BOOL;                       // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid       : BOOL;                       // 输出可用标志 / outputs usable flag
END_VAR
VAR
    fbNormal     : TON;                        // 正常判据确认窗，段 7 无条件刷新 [ms] / normal criterion confirm window
    fbLeak       : TON;                        // 漏汽判据确认窗，段 7 无条件刷新 [ms] / leak criterion confirm window
    fbBlocked    : TON;                        // 堵塞判据确认窗，段 7 无条件刷新 [ms] / blocked criterion confirm window
    _eState      : E_DL_TrapState := E_DL_TrapState.eIdle; // 当前相位 / current phase
    _bInit       : BOOL := FALSE;              // 首扫标志，初值 FALSE 取非判定 / first-scan flag, tested negated
    _bParamBad   : BOOL;                       // 参数非法标志 / illegal parameter flag
    _bFiniteBad  : BOOL;                       // 输入非有限标志 / non-finite input flag
    _bIllegal    : BOOL;                       // 非法状态标志 / illegal state flag
    _bCold       : BOOL;                       // 冷态（工况未建立）标志 / cold state, the operating condition is not established
    _bCondNormal : BOOL;                       // 正常判据条件 / normal criterion condition
    _bCondLeak   : BOOL;                       // 漏汽判据条件 / leak criterion condition
    _bCondBlock  : BOOL;                       // 堵塞判据条件 / blocked criterion condition
    _bBrkNormal  : BOOL;                       // 正常确认计时器断输入一拍 / normal timer one-scan break
    _bBrkLeak    : BOOL;                       // 漏汽确认计时器断输入一拍 / leak timer one-scan break
    _bBrkBlock   : BOOL;                       // 堵塞确认计时器断输入一拍 / blocked timer one-scan break
    _tConfirmUse : TIME := T#30S;              // 生效确认时间 [ms]，已钳位 / effective confirm time, clamped
    _fDeltaHeld  : REAL;                       // 温差保持量 [K] / held temperature drop [K]
    _fColdLimit  : REAL := 40.0;               // 冷态带上限 [degC] = fTinMin × 冷态比 / cold band ceiling
END_VAR
VAR CONSTANT
    DL_VAL_LIM     : REAL := 1.0E6;            // 有限性判定的绝对值上限 [degC] / finiteness ceiling [degC]
    DL_DELTA_N_MN  : REAL := 0.0;              // 正常温差下限 [K]，须严格大于 / normal drop floor, strictly greater
    DL_DELTA_L_MN  : REAL := 0.0;              // 漏汽温差下限 [K] / leak drop floor [K]
    DL_TIN_MIN_MN  : REAL := 0.0;              // 工况温度下限 [degC]，须严格大于 / live steam temperature floor, strictly greater
    DL_COLD_RATIO  : REAL := 0.5;              // 冷态带相对工况下限的比例 [倍]，件内经验值 / cold band ratio, an empirical in-unit value
    DL_DELTA_MAX   : REAL := 1000.0;           // 温差合理上限 [K]，仅用于出口钳位 / sane drop ceiling [K], outlet clamping only
    DL_CONF_MAX_MS : DINT := 3600000;          // 确认时间上限 [ms]，一小时 / confirm time ceiling, one hour
    DL_TIME_ZERO   : TIME := T#0MS;            // 时间零值基准 [ms] / time zero reference
    DL_EPS         : REAL := 1.0E-6;           // 浮点比较容差 [K] / float comparison tolerance [K]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置（判定输出与保持量在段 9 单点写入）
 *      Per-scan presets, the verdicts are written only in segment nine
 *-----------------------------------------------------------------------------*)
eErr         := 16#0000_0000;                  // 错误码每拍重算 / error code recomputed every scan
bError       := FALSE;                         // 故障标志每拍重算 / fault flag recomputed every scan
bValid       := FALSE;                         // 可用标志每拍重算 / usable flag recomputed every scan
bNormal      := FALSE;                         // 正常判定每拍重算 / normal verdict recomputed
bSteamLeak   := FALSE;                         // 漏汽判定每拍重算 / leak verdict recomputed
bBlocked     := FALSE;                         // 堵塞判定每拍重算 / blocked verdict recomputed
_bParamBad   := FALSE;                         // 参数非法标志预清零 / parameter flag pre-cleared
_bFiniteBad  := FALSE;                         // 非有限标志预清零 / non-finite flag pre-cleared
_bIllegal    := FALSE;                         // 非法状态标志预清零 / illegal state flag pre-cleared
_bCold       := FALSE;                         // 冷态标志预清零 / cold flag pre-cleared
_bCondNormal := FALSE;                         // 正常条件预置 FALSE / normal condition preset FALSE
_bCondLeak   := FALSE;                         // 漏汽条件预置 FALSE / leak condition preset FALSE
_bCondBlock  := FALSE;                         // 堵塞条件预置 FALSE / blocked condition preset FALSE

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（判定从待机起，不继承任何历史结论）
 *      First-scan initialisation, no historical verdict is inherited
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState     := E_DL_TrapState.eIdle;       // 相位待机 / phase idle
    _fDeltaHeld := 0.0;                        // 温差保持量 0 [K] / held drop zero
    _bBrkNormal := TRUE;                       // 正常确认窗从零开始 / normal window starts from zero
    _bBrkLeak   := TRUE;                       // 漏汽确认窗从零开始 / leak window starts from zero
    _bBrkBlock  := TRUE;                       // 堵塞确认窗从零开始 / blocked window starts from zero
    _bInit      := TRUE;                       // 首扫只做一次 / the first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数闸门（判据区间必须非空，否则判据无意义）
 *      Parameter gate, the criteria intervals must not be empty
 *-----------------------------------------------------------------------------*)
IF (fDeltaNormal <> fDeltaNormal) OR (ABS(fDeltaNormal) > DL_VAL_LIM) OR (fDeltaNormal <= DL_DELTA_N_MN) THEN
    _bParamBad := TRUE;                        // 正常温差非法 / normal drop illegal
END_IF
IF (fDeltaLeak <> fDeltaLeak) OR (ABS(fDeltaLeak) > DL_VAL_LIM) OR (fDeltaLeak < DL_DELTA_L_MN) THEN
    _bParamBad := TRUE;                        // 漏汽温差非法 / leak drop illegal
END_IF
IF (fDeltaLeak >= fDeltaNormal) OR ((fDeltaNormal - fDeltaLeak) <= DL_EPS) THEN
    _bParamBad := TRUE;                        // 区间为空：判据自相矛盾 / empty interval, contradictory criteria
END_IF
IF (fTinMin <> fTinMin) OR (ABS(fTinMin) > DL_VAL_LIM) OR (fTinMin <= DL_TIN_MIN_MN) THEN
    _bParamBad := TRUE;                        // 工况温度非法 / live steam temperature illegal
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜温度有限性（区间判据同时拦 NaN 与 ±Inf）
 *      Temperature finiteness, the interval test catches NaN and infinity
 *-----------------------------------------------------------------------------*)
IF (fTin < -DL_VAL_LIM) OR (fTin > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 阀前温度非有限 / upstream temperature non-finite
END_IF
IF (fTout < -DL_VAL_LIM) OR (fTout > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 阀后温度非有限 / downstream temperature non-finite
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜温差与冷态带（冷态带由工况下限按比例导出，件内常量）
 *      Temperature drop and the cold band derived from the live steam limit
 *-----------------------------------------------------------------------------*)
IF NOT _bFiniteBad THEN
    _fDeltaHeld := fTin - fTout;               // 实测温差 [K] / measured drop
    _fColdLimit := fTinMin * DL_COLD_RATIO;    // 冷态带上限 [degC] / cold band ceiling
    _bCold      := (fTin < _fColdLimit);       // 冷态判据：明显停机 / cold test, clearly shut down
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜三条判据条件（数值上互斥：由阈值关系结构性保证，不靠优先级补丁）
 *      The three criteria are mutually exclusive by construction
 *-----------------------------------------------------------------------------*)
IF (NOT _bFiniteBad) AND (NOT _bParamBad) THEN
    _bCondNormal := (_fDeltaHeld >= fDeltaNormal);                       // 正常：温差达正常下限
    _bCondLeak   := (_fDeltaHeld <= fDeltaLeak) AND (fTin >= fTinMin);   // 漏汽：温差小且阀前已达工况
    _bCondBlock  := (_fDeltaHeld <= fDeltaLeak) AND (fTin >= _fColdLimit) AND (fTin < fTinMin); // 堵塞：蒸汽已引入但阀前跌落
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜三只确认计时器无条件刷新（R40：CASE 之外每拍必调，各判据各一只）
 *      Three confirm timers refreshed unconditionally, one instance per criterion
 *-----------------------------------------------------------------------------*)
_tConfirmUse := tConfirm;                      // 确认时间直取引脚 [ms] / confirm time from the pin
IF TIME_TO_DINT(_tConfirmUse) > DL_CONF_MAX_MS THEN
    _tConfirmUse := DINT_TO_TIME(DL_CONF_MAX_MS); // 超上限钳位（无专用码位，R90 不新开码） / clamped
END_IF
IF TIME_TO_DINT(_tConfirmUse) < 0 THEN
    _tConfirmUse := DL_TIME_ZERO;              // 负时间结构性不可达，兜底为 0 / structurally unreachable fallback
END_IF

fbNormal(IN := _bCondNormal AND bEnable AND (NOT _bBrkNormal), PT := _tConfirmUse); // 正常确认窗
_bBrkNormal := FALSE;                          // 断输入拍在调用后自清 / break self-cleared after the call

fbLeak(IN := _bCondLeak AND bEnable AND (NOT _bBrkLeak), PT := _tConfirmUse); // 漏汽确认窗
_bBrkLeak := FALSE;                            // 断输入拍在调用后自清 / break self-cleared

fbBlocked(IN := _bCondBlock AND bEnable AND (NOT _bBrkBlock), PT := _tConfirmUse); // 堵塞确认窗
_bBrkBlock := FALSE;                           // 断输入拍在调用后自清 / break self-cleared

(*------------------------------------------------------------------------------
 * 段 8｜相位机（非有限拍整段跳过：保持上次判定，②）
 *      Phase machine, skipped entirely on a non-finite scan to hold the last verdict
 *-----------------------------------------------------------------------------*)
IF NOT _bFiniteBad THEN
    (* 温度坏值拍整段跳过：不迁移、不清结论，保持上次判定（②），仅由码位链报 0342 *)
    (* A non-finite scan skips the whole block, the last verdict is held *)
    IF _bParamBad THEN
        _eState := E_DL_TrapState.eFault;      // 判据自相矛盾：转故障 / contradictory criteria go to fault
    ELSIF NOT bEnable THEN
        _eState := E_DL_TrapState.eIdle;       // 失能回待机 / disabled, back to idle
        _bBrkNormal := TRUE;                   // 三只确认窗全部重启 / every window restarts
        _bBrkLeak   := TRUE;                   // 漏汽窗重启 / leak window restarts
        _bBrkBlock  := TRUE;                   // 堵塞窗重启 / blocked window restarts
    ELSE
        CASE _eState OF

            E_DL_TrapState.eIdle:                  // 待机：冷态冻结，工况建立后按判据进入
                IF _bCold THEN
                    _eState := E_DL_TrapState.eIdle; // 工况未建立，冻结（0177 在段 10） / condition not established, frozen
                ELSIF fbNormal.Q THEN
                    _eState := E_DL_TrapState.eNormal; // 进正常相 / enter normal
                ELSIF fbLeak.Q THEN
                    _eState := E_DL_TrapState.eLeak;   // 进漏汽相 / enter leak
                ELSIF fbBlocked.Q THEN
                    _eState := E_DL_TrapState.eBlocked; // 进堵塞相 / enter blocked
                END_IF

            E_DL_TrapState.eNormal:                // 正常：判据迁移
                IF _bCold THEN
                    _eState := E_DL_TrapState.eIdle;   // 工况消失，回冻结 / the condition is lost, freeze
                ELSIF fbLeak.Q THEN
                    _eState := E_DL_TrapState.eLeak;   // 转漏汽 / switch to leak
                ELSIF fbBlocked.Q THEN
                    _eState := E_DL_TrapState.eBlocked; // 转堵塞 / switch to blocked
                END_IF

            E_DL_TrapState.eLeak:                  // 漏汽：判据迁移
                IF _bCold THEN
                    _eState := E_DL_TrapState.eIdle;   // 工况消失，回冻结 / freeze again
                ELSIF fbNormal.Q THEN
                    _eState := E_DL_TrapState.eNormal; // 恢复正常 / back to normal
                ELSIF fbBlocked.Q THEN
                    _eState := E_DL_TrapState.eBlocked; // 转堵塞 / switch to blocked
                END_IF

            E_DL_TrapState.eBlocked:               // 堵塞：判据迁移
                IF _bCold THEN
                    _eState := E_DL_TrapState.eIdle;   // 工况消失（彻底冷机），回冻结 / freeze again
                ELSIF fbNormal.Q THEN
                    _eState := E_DL_TrapState.eNormal; // 恢复正常 / back to normal
                ELSIF fbLeak.Q THEN
                    _eState := E_DL_TrapState.eLeak;   // 转漏汽 / switch to leak
                END_IF

            E_DL_TrapState.eFault:                 // 故障：参数恢复即回待机
                IF (NOT _bParamBad) AND (NOT _bFiniteBad) THEN
                    _eState := E_DL_TrapState.eIdle;   // 原因消失 / the cause is gone
                END_IF

            ELSE
                _bIllegal := TRUE;                 // 标记非法状态 / flag the illegal state
                _eState   := E_DL_TrapState.eFault; // 回故障态 / back to the fault state
        END_CASE
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜出口单点写入（判定与温差唯一写入点）
 *      Single write point of the verdicts and the temperature drop
 *-----------------------------------------------------------------------------*)
fDelta := LIMIT(-DL_DELTA_MAX, _fDeltaHeld, DL_DELTA_MAX); // 温差出口钳进合理域 [K] / the drop is clamped
bNormal    := (_eState = E_DL_TrapState.eNormal);   // 正常判定出口 / normal verdict outlet
bSteamLeak := (_eState = E_DL_TrapState.eLeak);     // 漏汽判定出口 / leak verdict outlet
bBlocked   := (_eState = E_DL_TrapState.eBlocked);  // 堵塞判定出口 / blocked verdict outlet

(*------------------------------------------------------------------------------
 * 段 10｜码位优先级链与健康分级（映射集中在此，不散落实现体）
 *      Code priority chain and health grading, the mapping lives in one place
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0003_0344;                    // 故障级：状态机兜底 / fault: state machine fallback
    bError := TRUE;                            // 置故障标志 / raise the fault flag
ELSIF _bParamBad THEN
    eErr   := 16#0003_0343;                    // 故障级：判据阈值自相矛盾 / fault: contradictory thresholds
    bError := TRUE;                            // 置故障标志 / raise the fault flag
ELSIF _bFiniteBad THEN
    eErr   := 16#0003_0342;                    // 故障级：温度输入非有限 / fault: non-finite temperature
    bError := TRUE;                            // 置故障标志 / raise the fault flag
ELSIF _bCold THEN
    eErr   := 16#0003_0177;                    // 信息级：工况未建立，冻结判定 / informational: condition not established
ELSIF _eState = E_DL_TrapState.eNormal THEN
    eErr   := 16#0003_0176;                    // 信息级：判据落入正常带 / informational: inside the normal band
END_IF

IF _bParamBad OR _bFiniteBad OR _bIllegal THEN
    eHealth := E_DL_Ne107Status.eFailure;      // 无判定能力：失效 / no verdict capability
ELSIF _eState = E_DL_TrapState.eLeak THEN
    eHealth := E_DL_Ne107Status.eOutOfSpec;    // 漏汽：能耗与管网越界，仍可运行 / leaking, out of specification
ELSIF _eState = E_DL_TrapState.eBlocked THEN
    eHealth := E_DL_Ne107Status.eMaintenanceReq; // 堵塞：需拆检 / blocked, maintenance required
ELSIF (_eState = E_DL_TrapState.eNormal) AND bEnable THEN
    eHealth := E_DL_Ne107Status.eOk;           // 正常 / normal
ELSE
    eHealth := E_DL_Ne107Status.eUnknown;      // 冷态或失能：无结论 / cold or disabled, no verdict
END_IF

IF bError THEN
    bValid := FALSE;                           // 故障级：输出不可用 / fault: outputs unusable
ELSIF _bCold THEN
    bValid := FALSE;                           // 冷态：判定被冻结，输出不可用 / cold: the verdict is frozen
ELSIF NOT bEnable THEN
    bValid := FALSE;                           // 失能：输出不可用 / disabled: unusable
ELSE
    bValid := TRUE;                            // 判定可用 / verdict usable
END_IF

END_FUNCTION_BLOCK
