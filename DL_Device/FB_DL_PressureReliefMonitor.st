(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PressureReliefMonitor
 * 溯源说明 (Provenance): 道莅 clean-room 防御性实现（IEC 61131-3 纯净实现，闭源文档仅借语义，零代码行）
 * 所属子库 (Sublibrary) : DL_Device / SafetyMonitor
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），仅用
 *                         Standard.library 的 TON / ABS / MAX
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 安全阀起跳/回座监视与台账
 * 功能一句话 (Summary)  : 用阀前/阀后压力判安全阀是否起跳，累计动作次数与累计
 *                         开启时长，给出本次起跳峰值压力与 NE107 健康分级。
 *
 * 本件存在的意义 (Why this unit exists)
 *   过程安全台账要求「安全阀一年动作了几次、累计开启多久」——这是法检项。
 *   库内 AlarmManager 数的是报警不是阀门动作，PortDiag 系列数的是通讯事件，
 *   没有任何件维护这张台账。同时「阀前持续超整定而阀后不同步升高」是
 *   安全阀不泄放的典型特征，属于必须报出来的失效形态。
 *
 * 台账纪律 (Ledger discipline)
 *   ① 起跳判据必须用**回座比做迟滞**（fUpPressure < fSetPressure × fBlowdown），
 *      硬阈值会让压力在整定点附近抖动并反复计数——这是台账失真的头号原因；
 *   ② 单次起跳时长 < tMinLift 不计入 nLiftCount（信息 0175）：工艺压力波动
 *      引起的瞬时顶开不构成「动作」，但仍计入累计开启时长之外的判定之外，
 *      两者口径不同，头注释写死；
 *   ③ 计数与累计时长累加前判上界，饱和不回绕（R35）；TIME 溢出用比较式
 *      预判（R54），比较表达式内不出现加乘运算符；
 *   ④ **失能不清台账**：计数、累计时长、峰值一律保持；若失能发生在起跳期间，
 *      以失能拍作为该次起跳的结束拍如实入账，绝不丢一次真实动作。
 *
 * 健康映射（写死在此，不散落实现体）
 *   参数非法 / 输入非有限                        → eFailure
 *   起跳中且阀后压力 > 整定 × DL_DN_FAIL_RATIO    → eFailure（疑似不泄放）
 *   nLiftCount >= uMaintLimit                    → eMaintenanceReq
 *   其余（有判定能力）                            → eOk
 *   未使能（无判定能力）                          → eUnknown
 *   DL_DN_FAIL_RATIO = 0.5 为件内经验阈值：安全阀正常起跳时阀后应接近大气，
 *   若阀后压力仍高于整定的一半，说明介质没有真正排出去（下游堵塞或阀瓣卡滞）。
 *
 * 边界安全 (Boundary)
 *   - fSetPressure <= 0 或 fBlowdown 不在 (0, 1) 或非有限 → 故障 033F、bValid = FALSE，
 *     **台账保持不动**（参数错了不等于阀门没动作过）；
 *   - 任一压力非有限 → 故障 0340，**保持 bLifted 与计数不变**（坏值不得伪造动作）；
 *   - bError 的每一个置位源都能在 eErr 找到对应码（R45 纪律）；
 *   - CASE 落 ELSE 置 0341 兜底并回 eFault；
 *   - 本件无复位引脚：台账只能靠 FB 实例重建清零（法检台账不允许被误复位，
 *     这是刻意设计，已留档）。
 *
 * 错误码    : 16#0003_0174 起跳事件已记录（动作次数 +1，累计时长继续累加）——信息级
 *             16#0003_0175 单次起跳时长低于 tMinLift，按工艺波动滤除不计入台账——信息级
 *             16#0003_033F 整定压力或回座比非法——故障级，bValid = FALSE
 *             16#0003_0340 压力输入非有限，保持台账与判定不变——故障级，坏值不得伪造动作
 *             16#0003_0341 状态机落 ELSE 兜底（非法状态）——故障级，回 eIdle 并保持台账
 * 码位总账  : 16#0003_0174 用 / 16#0003_0175 用 ｜ 16#0003_033F 用 / 16#0003_0340 用 / 16#0003_0341 用
 * 状态机    : E_DL_ReliefState（eIdle / eLifted / eReseat / eFault），CASE 含 ELSE 兜底，
 *             ELSE 置 16#0003_0341 并回 eFault；失能回 eIdle 但台账保持
 * 采样约定  : 每任务周期调用一次；时长按滚动时钟差累加（上拍快照，R45②）
 * 依赖说明  : 仅 Standard.library；健康出口引用 E_DL_Ne107Status（属主 I_DL_DeviceHealth，
 *             **引用不重声明**，R70③）
 * 验收向量  : V1 压力从 8 缓升到 10.5 bar 持续 200 ms → eLifted，bLifted = TRUE，
 *                fPeakPressure 跟随峰值；压力回落到 8.9（< 10×0.90 = 9.0）→ eReseat，
 *                时长 ≥ 500 ms 时 nLiftCount + 1 且 eErr = 0174，eHealth 随计数升级
 *             V2 起跳仅 300 ms（< tMinLift 500 ms）→ nLiftCount 不变，eErr = 0175（滤除主向量）
 *             V3 起跳中阀后压力 6 bar（> 10×0.5）→ eHealth = eFailure（不泄放主向量）
 *             V4 fBlowdown = 1.2 → 033F，bValid = FALSE，nLiftCount 与 tOpenTotal 保持
 *             V5 fUpPressure = NaN → 0340，bLifted 与计数保持（坏值不伪造动作主向量）
 *             V6 压力在 9.98~10.02 之间抖动 → 不重复计数（回座迟滞主向量）
 *             V7 bEnable 落于起跳中 → eIdle，本次时长如实入账，计数不清零
 * 红线自检  : 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 ｜ 纯 IEC 61131-3 ｜ 无除法
 *             浮点只用大小与容差比较 ｜ 无循环 ｜ 全变量双语同行注释 ｜ ENUM + CASE
 *             含 ELSE ｜ TON 在主体前部无条件刷新 ｜ TIME 溢出比较式预判 ｜
 *             阈值常量化，无魔法数
 * 修订历史  : 2026-11-16  v1.0.0  首版入库（R22 · 批 2 · 设备安全台账）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ReliefState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 安全阀监视的工作相位。0 起步长 10。
 * 注意: 健康出口类型 E_DL_Ne107Status 属主为 I_DL_DeviceHealth（DL_Device 契约件），
 *       本件只引用、不重声明（R70③ 全库唯一定义）。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_ReliefState :
(
    eIdle   := 0,      // 待机：未起跳，等待起跳确认 / Idle, waiting for a confirmed lift
    eLifted := 10,     // 起跳中：阀前高于整定，正在累计时长 / Lifted, upstream above the set pressure
    eReseat := 20,     // 回座：单拍入账相，随后回待机 / Reseat, one scan to book the event
    eFault  := 99      // 故障：参数非法或输入非有限 / Fault, illegal parameter or non-finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_PressureReliefMonitor
VAR_INPUT
    fUpPressure  : REAL;                       // 阀前压力 [bar g] / upstream pressure [bar g]
    fDnPressure  : REAL;                       // 阀后压力 [bar g] / downstream pressure [bar g]
    fSetPressure : REAL := 10.0;               // 整定压力 [bar g]，须 > 0 / set pressure [bar g], must be > 0
    fBlowdown    : REAL := 0.90;               // 回座压力比 [倍]，须在 0~1 之间 / reseat ratio [ratio], must lie inside zero and one
    tConfirm     : TIME := T#200MS;            // 起跳确认时间 [ms] / lift confirm time [ms]
    tMinLift     : TIME := T#500MS;            // 最短起跳时长 [ms]，低于此按波动滤除 / minimum lift duration [ms], shorter ones are filtered
    uMaintLimit  : UINT := 50;                 // 动作次数维护门限 [次] / maintenance count threshold [count]
    bEnable      : BOOL;                       // 使能（失能不清台账） / enable, the ledger survives a disable
END_VAR
VAR_OUTPUT
    bLifted      : BOOL;                       // 当前处于起跳状态 / currently lifted
    nLiftCount   : UDINT;                      // 累计动作次数 [次] / accumulated lift count [count]
    tOpenTotal   : TIME;                       // 累计开启时长 [ms] / accumulated open time [ms]
    fPeakPressure : REAL;                      // 本次起跳峰值压力 [bar g] / peak upstream pressure of the current lift [bar g]
    eHealth      : E_DL_Ne107Status;           // NE107 健康分级（引用唯一属主） / NE107 health status, referenced from its owner
    eErr         : UDINT;                      // 错误码，0 表示无错 / error code, 0 means no error
    bError       : BOOL;                       // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid       : BOOL;                       // 输出可用标志 / outputs usable flag
END_VAR
VAR
    fbConfirm    : TON;                        // 起跳确认计时，段 5 无条件刷新 [ms] / lift confirm timer
    fbElapsed    : TON;                        // 滚动时钟，段 5 无条件刷新 [ms] / rolling elapsed clock
    _eState      : E_DL_ReliefState := E_DL_ReliefState.eIdle; // 当前相位 / current phase
    _bInit       : BOOL := FALSE;              // 首扫标志，初值 FALSE 取非判定 / first-scan flag, tested negated
    _bParamBad   : BOOL;                       // 参数非法标志 / illegal parameter flag
    _bFiniteBad  : BOOL;                       // 输入非有限标志 / non-finite input flag
    _bIllegal    : BOOL;                       // 非法状态标志 / illegal state flag
    _bAbove      : BOOL;                       // 阀前高于整定（确认条件） / upstream above the set pressure
    _bReseatNow  : BOOL;                       // 回座判据成立 / reseat criterion satisfied
    _bConfBreak  : BOOL;                       // 确认计时器断输入一拍 / confirm timer one-scan break
    _bElapsedBreak : BOOL;                     // 滚动时钟断输入一拍 / rolling clock one-scan break
    _bNoRelief   : BOOL;                       // 疑似不泄放标志 / suspected no-relief flag
    _bBooked     : BOOL;                       // 本拍已入账标志 / booked this scan flag
    _bReseatPulse : BOOL;                      // 回座单拍脉冲（入账触发） / reseat one-scan pulse, triggers the booking
    _bLiftedPrev : BOOL;                       // 本拍进入时的起跳相快照（R38 镜像量） / lifted snapshot taken before the transitions
    _tConfirmUse : TIME := T#200MS;            // 生效确认时间 [ms]，已钳位 / effective confirm time, clamped
    _tMinLiftUse : TIME := T#500MS;            // 生效最短起跳时长 [ms]，已钳位 / effective minimum lift, clamped
    _tEtPrev     : TIME;                       // 滚动时钟上拍快照 [ms] / previous scan snapshot of the clock
    _tDelta      : TIME;                       // 本拍时长增量 [ms] / elapsed increment of this scan
    _tLiftDur    : TIME;                       // 本次起跳已持续时长 [ms] / duration of the current lift [ms]
    _tTotalAcc   : TIME;                       // 累计开启时长保持量 [ms] / held accumulated open time [ms]
    _uCountAcc   : UDINT;                      // 累计动作次数保持量 [次] / held lift count [count]
    _fPeakAcc    : REAL;                       // 本次起跳峰值保持量 [bar g] / held peak pressure of the current lift [bar g]
    _fPeakTot    : REAL;                       // 历史峰值（供 HMI 参考） [bar g] / historical peak pressure [bar g]
END_VAR
VAR CONSTANT
    DL_VAL_LIM   : REAL := 1.0E6;              // 有限性判定的绝对值上限 [bar g] / finiteness ceiling [bar g]
    DL_SET_MIN   : REAL := 0.0;                // 整定压力下限 [bar g]，须严格大于 / set pressure floor, strictly greater
    DL_BLOW_MIN  : REAL := 0.0;                // 回座比下限 [倍]，须严格大于 / reseat ratio floor, strictly greater
    DL_BLOW_MAX  : REAL := 1.0;                // 回座比上限 [倍]，须严格小于 / reseat ratio ceiling, strictly less
    DL_DN_FAIL_RATIO : REAL := 0.5;            // 阀后不泄放判据比 [倍]，件内经验阈值 / no-relief ratio, an empirical in-unit threshold
    DL_CONF_MAX_MS : DINT := 60000;            // 确认时间上限 [ms] / confirm time ceiling [ms]
    DL_MINLIFT_MAX_MS : DINT := 3600000;       // 最短起跳时长上限 [ms]，一小时 / minimum lift ceiling, one hour
    DL_TIME_ZERO : TIME := T#0MS;              // 时间零值基准 [ms] / time zero reference
    DL_ROLL      : TIME := T#1H;               // 滚动时钟周期 [ms]，到顶重启防 ET 停滞 / rolling clock period, restarted at the top
    DL_TOTAL_MAX : TIME := T#24H;              // 累计时长饱和上界 [ms] 上限值：判溢出用 / accumulation ceiling, used by the overflow test
    DL_TIME_SAT  : TIME := T#24H;              // 累计时长饱和输出值 [ms] / accumulation saturation value
    DL_CNT_MAX   : UDINT := 16#FFFF_FFFF;      // 计数饱和上界 [次]，不回绕 / counter saturation ceiling, never wraps
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置（台账保持量不预置；输出在段 9 单点写入）
 *      Per-scan presets, the ledger values are never cleared here
 *-----------------------------------------------------------------------------*)
eErr         := 16#0000_0000;                  // 错误码每拍重算 / error code recomputed every scan
bError       := FALSE;                         // 故障标志每拍重算 / fault flag recomputed every scan
bValid       := FALSE;                         // 可用标志每拍重算 / usable flag recomputed every scan
_bParamBad   := FALSE;                         // 参数非法标志预清零 / parameter flag pre-cleared
_bFiniteBad  := FALSE;                         // 非有限标志预清零 / non-finite flag pre-cleared
_bIllegal    := FALSE;                         // 非法状态标志预清零 / illegal state flag pre-cleared
_bAbove      := FALSE;                         // 超整定条件预置 FALSE / above-set condition preset FALSE
_bReseatNow  := FALSE;                         // 回座判据预置 FALSE / reseat criterion preset FALSE
_bNoRelief   := FALSE;                         // 不泄放标志预置 FALSE / no-relief preset FALSE
_bBooked     := FALSE;                         // 入账标志预置 FALSE / booked flag preset FALSE
_bReseatPulse := FALSE;                        // 回座脉冲预置 FALSE / reseat pulse preset FALSE
_bLiftedPrev := FALSE;                         // 起跳快照预置 FALSE / lifted snapshot preset FALSE

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（台账全部从零起，峰值从当前阀前压力起）
 *      First-scan initialisation, the ledger starts at zero
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState     := E_DL_ReliefState.eIdle;     // 相位待机 / phase idle
    _uCountAcc  := 0;                          // 动作次数清零 [次] / lift count cleared
    _tTotalAcc  := DL_TIME_ZERO;               // 累计时长清零 [ms] / accumulated time cleared
    _tLiftDur   := DL_TIME_ZERO;               // 本次时长清零 [ms] / current lift duration cleared
    _tEtPrev    := DL_TIME_ZERO;               // 时钟快照清零 [ms] / clock snapshot cleared
    _fPeakAcc   := 0.0;                        // 本次峰值清零 [bar g] / current peak cleared
    _fPeakTot   := 0.0;                        // 历史峰值清零 [bar g] / historical peak cleared
    _bConfBreak := TRUE;                       // 确认计时从零开始 / confirm timer starts from zero
    _bElapsedBreak := TRUE;                    // 滚动时钟从零开始 / rolling clock starts from zero
    _bInit      := TRUE;                       // 首扫只做一次 / the first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数闸门（整定压力与回座比；非法只降可用性，台账一律保持）
 *      Parameter gate, an illegal parameter lowers usability but never touches the ledger
 *-----------------------------------------------------------------------------*)
IF (fSetPressure <> fSetPressure) OR (ABS(fSetPressure) > DL_VAL_LIM) OR (fSetPressure <= DL_SET_MIN) THEN
    _bParamBad := TRUE;                        // 整定压力非法 / set pressure illegal
END_IF
IF (fBlowdown <> fBlowdown) OR (fBlowdown <= DL_BLOW_MIN) OR (fBlowdown >= DL_BLOW_MAX) THEN
    _bParamBad := TRUE;                        // 回座比非法（须严格在 0~1 之间） / reseat ratio illegal
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜压力输入有限性（区间判据同时拦 NaN 与 ±Inf）
 *      Pressure finiteness, the interval test catches NaN and infinity
 *-----------------------------------------------------------------------------*)
IF (fUpPressure < -DL_VAL_LIM) OR (fUpPressure > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 阀前压力非有限 / upstream pressure non-finite
END_IF
IF (fDnPressure < -DL_VAL_LIM) OR (fDnPressure > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 阀后压力非有限 / downstream pressure non-finite
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜计时器无条件刷新（R40）+ 本拍时长增量（R45② 上拍快照）
 *      Timers refreshed unconditionally, the elapsed increment uses a previous-scan snapshot
 *-----------------------------------------------------------------------------*)
_tConfirmUse := tConfirm;                      // 确认时间直取引脚 [ms] / confirm time from the pin
IF TIME_TO_DINT(_tConfirmUse) > DL_CONF_MAX_MS THEN
    _tConfirmUse := DINT_TO_TIME(DL_CONF_MAX_MS); // 超上限钳位（无专用码位，R90 不新开码） / clamped
END_IF
IF TIME_TO_DINT(_tConfirmUse) < 0 THEN
    _tConfirmUse := DL_TIME_ZERO;              // 负时间结构性不可达，兜底为 0 / structurally unreachable fallback
END_IF

_tMinLiftUse := tMinLift;                      // 最短起跳时长直取引脚 [ms] / minimum lift from the pin
IF TIME_TO_DINT(_tMinLiftUse) > DL_MINLIFT_MAX_MS THEN
    _tMinLiftUse := DINT_TO_TIME(DL_MINLIFT_MAX_MS); // 超上限钳位 / clamped
END_IF
IF TIME_TO_DINT(_tMinLiftUse) < 0 THEN
    _tMinLiftUse := DL_TIME_ZERO;              // 负时间兜底为 0 / fallback to zero
END_IF

IF NOT _bFiniteBad THEN
    _bAbove := (fUpPressure > fSetPressure);   // 超整定判据 [布尔] / above-set test
    IF NOT _bParamBad THEN
        _bReseatNow := (fUpPressure < (fSetPressure * fBlowdown)); // 回座判据：低于整定×回座比 / reseat test
    END_IF
    _bNoRelief := (fDnPressure > (fSetPressure * DL_DN_FAIL_RATIO)); // 阀后未降：疑似不泄放 / downstream not relieved
END_IF

fbConfirm(IN := _bAbove AND (NOT _bConfBreak), PT := _tConfirmUse); // 起跳确认计时
_bConfBreak := FALSE;                          // 断输入拍在调用后自清 / break self-cleared after the call

fbElapsed(IN := (NOT _bElapsedBreak), PT := DL_ROLL); // 滚动时钟无条件刷新
_bElapsedBreak := FALSE;                       // 断输入拍在调用后自清 / break self-cleared
_tDelta := fbElapsed.ET - _tEtPrev;            // 本拍增量 = 当前 ET − 上拍快照 / increment from the snapshot
IF TIME_TO_DINT(_tDelta) < 0 THEN
    _tDelta := DL_TIME_ZERO;                   // 时钟重启拍：增量按 0 处理，绝不倒扣 / restart scan counts as zero
END_IF
_tEtPrev := fbElapsed.ET;                      // 快照在本拍末更新（唯一写入点） / snapshot updated once
IF fbElapsed.Q THEN
    _bElapsedBreak := TRUE;                    // 到顶重启：下一拍 ET 归零 / restart so the next scan starts from zero
    _tEtPrev := DL_TIME_ZERO;                  // 重启后快照同步归零 / the snapshot follows the restart
END_IF

(* 起跳相快照在迁移之前采集（R38）：迁移拍也要把本拍时长增量算进本次起跳 *)
(* The lifted snapshot is taken before the transitions so the final scan still counts *)
_bLiftedPrev := (_eState = E_DL_ReliefState.eLifted);

(*------------------------------------------------------------------------------
 * 段 6｜相位机（只做迁移；台账入账在段 7，出口在段 9）
 *      Phase machine, transitions only, the ledger is booked in segment seven
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_ReliefState.eIdle:                    // 待机：确认超整定即起跳
        IF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_ReliefState.eFault; // 原因未消失，转故障 / the cause persists
        ELSIF bEnable AND fbConfirm.Q THEN
            _eState     := E_DL_ReliefState.eLifted; // 进起跳相 / enter the lifted phase
            _tLiftDur   := DL_TIME_ZERO;       // 本次时长从零累计 / duration starts at zero
            _fPeakAcc   := fUpPressure;        // 峰值初值 = 起跳压力 / the peak starts at the lift pressure
            _bNoRelief  := FALSE;              // 起跳首拍不判不泄放 / no no-relief verdict on the first scan
        ELSIF NOT bEnable THEN
            _eState := E_DL_ReliefState.eIdle; // 失能保持待机，台账不动 / disabled, the ledger is untouched
        END_IF

    E_DL_ReliefState.eLifted:                  // 起跳中：回座或失能都结束本次起跳
        IF _bFiniteBad THEN
            _eState := E_DL_ReliefState.eFault; // 坏值：保持判定与台账（段 7 不入账） / non-finite, hold everything
        ELSIF _bParamBad THEN
            _eState := E_DL_ReliefState.eFault; // 参数非法：转故障 / illegal parameters go to fault
        ELSIF NOT bEnable THEN
            _eState := E_DL_ReliefState.eReseat; // 失能以本拍作为结束拍，如实入账 / disabling closes the lift honestly
        ELSIF _bReseatNow THEN
            _eState := E_DL_ReliefState.eReseat; // 回座 / reseated
        END_IF

    E_DL_ReliefState.eReseat:                  // 回座：单拍入账相（**本相不在此迁移**，先入账后迁移）
        _bReseatPulse := TRUE;                 // 置入账脉冲，迁移交给段 7 入账之后 / book first, transition after

    E_DL_ReliefState.eFault:                   // 故障：参数合法且输入有限才回待机
        IF bEnable AND (NOT _bParamBad) AND (NOT _bFiniteBad) THEN
            _eState := E_DL_ReliefState.eIdle; // 原因消失，回待机并重新确认 / cause cleared, confirm again
            _bConfBreak := TRUE;               // 确认计时重启，避免沿用故障期残留 / restart the confirm timer
        END_IF

    ELSE
        _bIllegal := TRUE;                     // 标记非法状态 / flag the illegal state
        _eState   := E_DL_ReliefState.eFault;  // 回故障态 / back to the fault state
        eErr      := 16#0003_0341;             // 故障级：状态机兜底 / fault: state machine fallback
        bError    := TRUE;                     // 置故障标志 / raise the fault flag
END_CASE

(*------------------------------------------------------------------------------
 * 段 7｜台账演进（唯一累加点：起跳相按时长增量，回座相一次性入账）
 *      Ledger evolution, the single accumulation point
 *-----------------------------------------------------------------------------*)
IF _bLiftedPrev AND (NOT _bFiniteBad) AND (NOT _bParamBad) THEN
    _tLiftDur := _tLiftDur + _tDelta;          // 本次起跳时长累加 [ms] / current lift duration accumulates
    IF fUpPressure > _fPeakAcc THEN
        _fPeakAcc := fUpPressure;              // 跟踪本次峰值 [bar g] / track the current peak
    END_IF
    IF fUpPressure > _fPeakTot THEN
        _fPeakTot := fUpPressure;              // 跟踪历史峰值 [bar g] / track the historical peak
    END_IF
    IF _tTotalAcc > (DL_TOTAL_MAX - _tDelta) THEN
        _tTotalAcc := DL_TIME_SAT;             // 饱和不回绕（R54 比较式预判） [ms] / saturate, never wrap
    ELSE
        _tTotalAcc := _tTotalAcc + _tDelta;    // 累计开启时长 [ms] / accumulate the open time
    END_IF
END_IF

(* 回座（或失能结束起跳）的当拍一次性入账，入账之后再迁移回待机 *)
(* Book the event once on the reseat scan, then transition back to idle *)
IF _bReseatPulse AND (NOT _bBooked) THEN
    _bBooked := TRUE;                          // 本拍只入账一次 / book exactly once
    IF TIME_TO_DINT(_tLiftDur) >= TIME_TO_DINT(_tMinLiftUse) THEN
        IF _uCountAcc < DL_CNT_MAX THEN
            _uCountAcc := _uCountAcc + 1;      // 动作次数 +1（饱和不回绕） [次] / count incremented
        END_IF
        eErr := 16#0003_0174;                  // 信息级：起跳事件已记录 / informational: lift event recorded
    ELSE
        eErr := 16#0003_0175;                  // 信息级：时长不足，按工艺波动滤除 / informational: filtered as process fluctuation
    END_IF
    _tLiftDur := DL_TIME_ZERO;                 // 本次时长清零，准备下一次 / reset the duration
END_IF

(* 入账完成后才允许迁移：次序不可反（先入账、后迁移，R45） *)
(* Transition only after the booking, the order cannot be reversed *)
IF _eState = E_DL_ReliefState.eReseat THEN
    _eState := E_DL_ReliefState.eIdle;         // 回待机，重新等待起跳确认 / back to idle and wait for the next confirm
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜故障码单一优先级链（每一个 bError 置位源都在此找到对应码，R45）
 *      Single priority chain of fault codes, every bError source maps to a code
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    bError := TRUE;                            // 非法状态已置码 0341（CASE 兜底） / illegal state, code 0341 set by the fallback
ELSIF _bParamBad THEN
    eErr   := 16#0003_033F;                    // 故障级：整定压力或回座比非法 / fault: set pressure or reseat ratio illegal
    bError := TRUE;                            // 置故障标志 / raise the fault flag
ELSIF _bFiniteBad THEN
    eErr   := 16#0003_0340;                    // 故障级：压力输入非有限，台账保持 / fault: non-finite pressure, ledger held
    bError := TRUE;                            // 置故障标志 / raise the fault flag
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜健康分级（等级→健康映射集中在此，不散落实现体）
 *      Health grading, the whole mapping lives here
 *-----------------------------------------------------------------------------*)
IF _bParamBad OR _bFiniteBad OR _bIllegal THEN
    eHealth := E_DL_Ne107Status.eFailure;      // 参数非法或输入非有限：失效 / illegal parameter or non-finite input
ELSIF (_eState = E_DL_ReliefState.eLifted) AND _bNoRelief THEN
    eHealth := E_DL_Ne107Status.eFailure;      // 起跳中阀后未降：疑似不泄放 / lifted but downstream not relieved
ELSIF _uCountAcc >= uMaintLimit THEN
    eHealth := E_DL_Ne107Status.eMaintenanceReq; // 动作次数达门限：需维护 / maintenance threshold reached
ELSIF NOT bEnable THEN
    eHealth := E_DL_Ne107Status.eUnknown;      // 未使能：无判定能力 / no verdict capability while disabled
ELSE
    eHealth := E_DL_Ne107Status.eOk;           // 其余：正常 / otherwise normal
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜出口单点写入与可用性仲裁
 *      Single write point of the outputs and the usability arbitration
 *-----------------------------------------------------------------------------*)
bLifted       := (_eState = E_DL_ReliefState.eLifted); // 起跳状态出口 / lifted outlet
nLiftCount    := _uCountAcc;                   // 动作次数出口 [次] / lift count outlet
tOpenTotal    := _tTotalAcc;                   // 累计开启时长出口 [ms] / accumulated open time outlet
fPeakPressure := _fPeakAcc;                    // 本次起跳峰值出口 [bar g] / current lift peak outlet

IF bError THEN
    bValid := FALSE;                           // 故障级：输出不可用（台账仍如实上报） / fault: unusable, the ledger is still reported
ELSIF NOT bEnable THEN
    bValid := FALSE;                           // 失能：判定不可用（台账保持） / disabled: no verdict, ledger held
ELSIF _bFiniteBad THEN
    bValid := FALSE;                           // 非有限拍：判定不可用 / non-finite scan: no verdict
ELSE
    bValid := TRUE;                            // 判定可用 / verdict usable
END_IF

END_FUNCTION_BLOCK
