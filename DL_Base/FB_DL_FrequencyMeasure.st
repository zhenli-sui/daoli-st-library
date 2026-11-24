(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FrequencyMeasure
 * 溯源说明 (Provenance): 道莅 clean-room 防御性实现（IEC 61131-3 纯净实现，闭源文档仅借语义，零代码行）
 * 所属子库 (Sublibrary) : DL_Base / Timing
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），仅用
 *                         Standard.library 的 R_TRIG / TON / TIME_TO_REAL
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 门时计数测频
 * 功能一句话 (Summary)  : 用固定门时间数脉冲上升沿，算出外部脉冲的频率 [Hz]，
 *                         并把当拍分辨率与低频死区显式化。
 *
 * 本件存在的意义 (Why this unit exists)
 *   定时器族此前只有「生」没有「测」：PulseGenerator 生脉冲、SamplingTrigger
 *   生节拍、CycleTimeMeasure 测任务周期，**没有任何件测量外部脉冲频率**。
 *   脉冲流量计的 K 系数换算、编码器线速度、风机转速全部落在这一格。
 *   R21 已判「频率发生器不立」（与 PulseGenerator 重叠），但测量侧与之相反，
 *   是真实缺口：测频的不确定度、分辨率、低频死区必须显式给出，否则现场
 *   拿一个小数抖动值当转速用。
 *
 * 测量原理 (Principle)
 *   门时间内数上升沿：f = N / T_gate。分辨率 = 1 / T_gate（门越长分辨率越高、
 *   响应越慢，这是本件必须让调用方自己权衡的取舍，故做成引脚而非内部默认）。
 *   门到时立即发布、计数清零、重开门——不存在「测量间隙」的可配置语义，
 *   间隙固定为 1 个扫描周期（绝对时间不确定度见遗留假设）。
 *
 * 遗留假设 (Assumption) —— 测量不确定度，不得声称精确
 *   ① 门切换拍可能多计或漏计 **1 个沿**，故测量不确定度为 ±1 计数，
 *      折算 ±1/T_gate Hz。这是门时计数法的原理性下限，不是实现缺陷；
 *   ② 门时间以任务周期为量化单位，实际门时间 = 设定值 ± 1 个任务周期；
 *   ③ 分辨率引脚 fFreqRes 给出的是「当拍实际分辨率」= 1000 / 门毫秒数，
 *      调用方据此判断低频侧的可信度（低频 + 短门 → 分辨率极粗）；
 *   ④ 低于 fLowFreqDead 一律输出 0（信息 0465），不输出抖动小数冒充低频——
 *      停机的流量计输出 0.37 Hz 会让操作工以为还在流。
 *
 * 边界安全 (Boundary)
 *   ① tGateTime < T#1MS → 钳到 1 ms + 信息 0464；> T#10S → 钳到 10 s + 信息 0464；
 *   ② 门时间经钳位后为 0 属结构性不可达（防御纵深）→ 故障 03B4、回 eIdle；
 *   ③ 计数在门切换拍出现回退（外部改写或溢出）→ 故障 03B5、bValid = FALSE，
 *      并丢弃本门计数从零重开门（本件无复位引脚，故为自愈式处理，见实现注释）；
 *   ④ R_TRIG 与 TON 实例在主体最前部**无条件刷新**（R40 家族），门重启经
 *      「断输入一拍」标志 _bGateBreak 实现，调用后立即自清；
 *   ⑤ CASE 落 ELSE 置 03B5 并回 eIdle（非法状态兜底，与③共用一码，R90）。
 * 节律 (Cycle order)
 *   段 1 每拍预置 → 段 2 首扫初始化 → 段 3 参数钳位 → 段 4 边沿与定时器无条件
 *   刷新（含计数累加）→ 段 5 计数回退检测 → 段 6 状态机（只做迁移）→
 *   段 7 发布（eReady 相内单拍，唯一写入点）→ 段 8 迁移收尾 → 段 9 出口。
 *
 * 错误码    : 16#0001_0464 门时间越界已钳位到 1 ms~10 s——信息级，正常防御
 *             16#0001_0465 频率低于死区，已按 0 输出——信息级，不输出抖动小数
 *             16#0001_03B4 门时间钳位后仍非法（为 0），无法测频——故障级，bValid = FALSE
 *             16#0001_03B5 门内计数回退不可信（含状态机 ELSE 兜底复用，R90）——故障级
 *             16#0001_03B6 预留禁用（故障级，不得挪用）
 * 码位总账  : 16#0001_0464 用 / 16#0001_0465 用 ｜ 16#0001_03B4 用 / 16#0001_03B5 用 / 16#0001_03B6 预留
 * 状态机    : E_DL_FreqMeasState（eIdle / eGating / eReady / eFault），CASE 含 ELSE
 *             兜底，ELSE 分支置 16#0001_03B5 并回 eIdle；失能无条件回 eIdle
 * 采样约定  : 每任务周期调用一次；门时间由 tGateTime 给定，不读系统时钟
 * 依赖说明  : 无 DL_ 内部依赖；仅 Standard.library 的 R_TRIG / TON / TIME_TO_REAL
 * 验收向量  : V1 100 ms 门、1 kHz 脉冲 → fFreq ≈ 100.0，fFreqRes = 10.0，bValid = TRUE
 *             V2 100 ms 门、0.2 Hz 脉冲（死区内）→ fFreq = 0，eErr = 0465，bValid = TRUE
 *             V3 门时间 0 ms → 钳到 1 ms 且 eErr = 0464，仍返回测量（钳位主向量）
 *             V4 门时间 20 s → 钳到 10 s 且 eErr = 0464
 *             V5 门切换拍清零后立刻被外部写回大值（构造计数回退）→ eErr = 03B5，
 *                bValid = FALSE，随后自愈重开（R40 跨相主向量）
 *             V6 失能 → eIdle，bValid = FALSE，fFreq 保持末次值不跳变（恢复首拍不阶跃）
 * 红线自检  : 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 ｜ 纯 IEC 61131-3 ｜ 除法前置
 *             判零（门时恒 ≥ 1 ms，构造性非零，另设显式闸门）｜ 浮点比较只用
 *             容差与大小比较，无判等 ｜ 循环无、计数带上界饱和 ｜ 全变量双语
 *             同行注释 ｜ ENUM + CASE 含 ELSE ｜ R_TRIG / TON 在主体最前部无条件
 *             刷新 ｜ 无魔法数
 * 修订历史  : 2026-11-16  v1.0.0  首版入库（R22 · 批 1 · 定时器族第五轴）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FreqMeasState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 门时测频的离散相位。0 起步长 10，便于后续插态。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_FreqMeasState :
(
    eIdle     := 0,    // 待机：未使能或门时间非法 / Idle, disabled or gate time illegal
    eGating   := 10,   // 计数中：门时间内数上升沿 / Gating, counting rising edges inside the gate
    eReady    := 20,   // 发布相：门到后单拍发布并重开 / Ready, one scan to publish then reopen
    eFault    := 99    // 故障：门时间非法，待参数恢复 / Fault, gate time illegal until it recovers
);
END_TYPE

FUNCTION_BLOCK FB_DL_FrequencyMeasure
VAR_INPUT
    bPulse       : BOOL;                       // 待测脉冲，任意占空比 / pulse under test, any duty cycle
    bEnable      : BOOL;                       // 使能，FALSE 时停止计数并回待机 / enable, FALSE stops counting and returns to idle
    tGateTime    : TIME := T#100MS;            // 门时间 [ms]，范围 1~10000 / gate time [ms], range 1~10000
    fLowFreqDead : REAL := 0.5;                // 低频死区 [Hz]，低于此值输出 0 / low frequency dead band [Hz], output zero below it
END_VAR
VAR_OUTPUT
    fFreq        : REAL;                       // 测量频率 [Hz]，分辨率 1/tGateTime / measured frequency [Hz], resolution 1/gate time
    fFreqRes     : REAL;                       // 当拍实际分辨率 [Hz] / actual resolution of the current scan [Hz]
    uLastCount   : UDINT;                      // 上一门内上升沿个数 [个] / rising edge count of the previous gate
    bValid       : BOOL;                       // 输出可用标志 / outputs usable flag
    eErr         : UDINT;                      // 错误码，0 表示无错 / error code, 0 means no error
    bError       : BOOL;                       // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
END_VAR
VAR
    fbEdge       : R_TRIG;                     // 脉冲上升沿检测，段 4 无条件刷新 / pulse rising edge detector, refreshed unconditionally
    fbGate       : TON;                        // 门时间计时，段 4 无条件刷新 [ms] / gate timer, refreshed unconditionally
    _eState      : E_DL_FreqMeasState := E_DL_FreqMeasState.eIdle; // 当前相位 / current phase
    _bInit       : BOOL := FALSE;              // 首扫标志，初值 FALSE 取非判定 / first-scan flag, FALSE initialised and tested negated
    _tGateUse    : TIME := T#100MS;            // 生效门时间 [ms]，已钳位 / effective gate time after clamping
    _fDeadUse    : REAL := 0.5;                // 生效低频死区 [Hz]，已钳位 / effective dead band after clamping
    _uCount      : UDINT;                      // 本门内上升沿累计 [个] / rising edges accumulated inside the current gate
    _uCountPrev  : UDINT;                      // 上拍计数快照，唯一写入点在段 9 [个] / previous-scan count snapshot, single write point
    _uLastCountH : UDINT;                      // 上一门计数保持量 [个] / held edge count of the previous gate
    _fFreqHeld   : REAL;                       // 频率保持量 [Hz] / held frequency
    _fResHeld    : REAL;                       // 分辨率保持量 [Hz] / held resolution
    _bHaveMeas   : BOOL;                       // 是否已完成过一次测量 / whether one full measurement has completed
    _bGateBreak  : BOOL;                       // 门计时器断输入一拍标志 / gate timer one-scan break flag
    _bParamFault : BOOL;                       // 门时间参数非法标志 / gate time illegal flag
    _bRollback   : BOOL;                       // 计数回退标志 / counter rollback flag
    _fGateMs     : REAL;                       // 门时间毫秒数 [ms]，用于换算 / gate time in milliseconds used by the conversions
END_VAR
VAR CONSTANT
    DL_GATE_MIN_MS  : DINT := 1;               // 门时间下限 [ms] / gate time floor [ms]
    DL_GATE_MAX_MS  : DINT := 10000;           // 门时间上限 [ms] / gate time ceiling [ms]
    DL_TIME_ZERO    : TIME := T#0MS;           // 时间零值基准 [ms] / time zero reference
    DL_MS_PER_S     : REAL := 1000.0;          // 毫秒与秒的换算系数 [ms/s] / milliseconds per second
    DL_CNT_MAX      : UDINT := 16#FFFF_FFFF;   // 计数饱和上界 [个]，不回绕 / counter saturation ceiling, never wraps
    DL_DEAD_MAX     : REAL := 1000.0;          // 死区参数上限 [Hz]，防超界 / dead band parameter ceiling [Hz]
    DL_DEAD_MIN     : REAL := 0.0;             // 死区参数下限 [Hz]，负值无意义 / dead band parameter floor [Hz]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置（状态量与保持量不预置，输出在段 9 单点写入）
 *      Per-scan presets, held values and outputs are untouched here
 *-----------------------------------------------------------------------------*)
eErr         := 16#0000_0000;                  // 错误码每拍重算 / error code recomputed every scan
bError       := FALSE;                         // 故障标志每拍重算 / fault flag recomputed every scan
bValid       := FALSE;                         // 可用标志每拍重算 / usable flag recomputed every scan
_bParamFault := FALSE;                         // 参数非法标志预清零 / parameter fault flag pre-cleared
_bRollback   := FALSE;                         // 回退标志预清零 / rollback flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（R19：bInit 初值 FALSE，判据取非）
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState     := E_DL_FreqMeasState.eIdle;   // 相位待机 / phase idle
    _uCount     := 0;                          // 计数清零 / counter cleared
    _uCountPrev := 0;                          // 快照清零 / snapshot cleared
    _uLastCountH := 0;                         // 上一门计数清零 / previous gate count cleared
    _fFreqHeld  := 0.0;                        // 频率保持量清零 / held frequency cleared
    _fResHeld   := 0.0;                        // 分辨率保持量清零 / held resolution cleared
    _bHaveMeas  := FALSE;                      // 尚无测量 / no measurement yet
    _bGateBreak := TRUE;                       // 首个门从零开始计时 / the first gate starts from zero
    _bInit      := TRUE;                       // 首扫只做一次 / the first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数钳位（门时间 1 ms~10 s；死区 0~上限）
 *      Parameter clamping, gate time one millisecond to ten seconds
 *-----------------------------------------------------------------------------*)
IF TIME_TO_DINT(tGateTime) < DL_GATE_MIN_MS THEN
    _tGateUse := DINT_TO_TIME(DL_GATE_MIN_MS); // 钳到下限 1 ms / clamped to the floor
    eErr      := 16#0001_0464;                 // 信息级：门时间已钳位 / informational: gate time clamped
ELSIF TIME_TO_DINT(tGateTime) > DL_GATE_MAX_MS THEN
    _tGateUse := DINT_TO_TIME(DL_GATE_MAX_MS); // 钳到上限 10 s / clamped to the ceiling
    eErr      := 16#0001_0464;                 // 信息级：门时间已钳位 / informational: gate time clamped
ELSE
    _tGateUse := tGateTime;                    // 域内直通 / passed through inside the domain
END_IF

(* 钳位后仍为 0：结构性不可达，保留 03B4 给「门时间为 0 的构造路径」（防御纵深） *)
(* Still zero after clamping is structurally unreachable, kept as defense in depth *)
IF _tGateUse <= DL_TIME_ZERO THEN
    _tGateUse    := DINT_TO_TIME(DL_GATE_MIN_MS); // 兜底回 1 ms，防后续除零 / fallback to one millisecond, no division by zero downstream
    _bParamFault := TRUE;                      // 参数故障标志 / parameter fault flag
    eErr         := 16#0001_03B4;              // 故障级：门时间非法 / fault: illegal gate time
    bError       := TRUE;                      // 置故障标志 / raise the fault flag
END_IF

_fDeadUse := LIMIT(DL_DEAD_MIN, fLowFreqDead, DL_DEAD_MAX); // 死区钳进 0~1000 Hz / dead band clamped

(*------------------------------------------------------------------------------
 * 段 4｜边沿与定时器无条件刷新（R40：一律在 CASE 之外、每拍必调）
 *      Edge detector and timer refreshed unconditionally, outside the CASE
 *-----------------------------------------------------------------------------*)
fbEdge(CLK := bPulse);                          // 脉冲沿无条件刷新 / pulse edge refreshed unconditionally

IF fbEdge.Q AND (_eState = E_DL_FreqMeasState.eGating) THEN
    IF _uCount < DL_CNT_MAX THEN
        _uCount := _uCount + 1;                 // 门内计数，饱和不回绕 / counted inside the gate, saturating
    END_IF
END_IF

fbGate(IN := bEnable AND (_eState = E_DL_FreqMeasState.eGating) AND (NOT _bGateBreak),
       PT := _tGateUse);                        // 门计时无条件刷新 / gate timer refreshed unconditionally
_bGateBreak := FALSE;                           // 断输入拍在调用后自清（R40 自清位置） / break self-cleared right after the call

(*------------------------------------------------------------------------------
 * 段 5｜计数回退检测（本件无复位引脚，故为自愈式：弃本门、从零重开）
 *      Counter rollback detection, self-healing because there is no reset pin
 *-----------------------------------------------------------------------------*)
IF _uCount < _uCountPrev THEN
    _bRollback := TRUE;                         // 标记回退 / rollback flagged
    _uCount    := 0;                            // 丢弃不可信计数 / drop the untrustworthy count
    _bGateBreak := TRUE;                        // 门计时从零重启 / gate timer restarted from zero
    _eState    := E_DL_FreqMeasState.eIdle;     // 回待机，下一拍重新开门 / back to idle, the gate reopens next scan
    eErr       := 16#0001_03B5;                 // 故障级：计数回退不可信 / fault: counter rollback, untrustworthy
    bError     := TRUE;                         // 置故障标志 / raise the fault flag
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜相位机（只做迁移，不写保持量；ELSE 兜底置 03B5 并回 eIdle）
 *      Phase machine, transitions only, a trailing ELSE falls back to 03B5 and idle
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_FreqMeasState.eIdle:                   // 待机：参数合法且使能即开门
        IF _bParamFault THEN
            _eState := E_DL_FreqMeasState.eFault; // 参数非法转故障 / illegal parameters go to fault
        ELSIF bEnable THEN
            _uCount    := 0;                    // 新门从零计数 / a new gate starts at zero
            _bGateBreak := TRUE;                // 门计时从零开始 / gate timer starts from zero
            _eState    := E_DL_FreqMeasState.eGating; // 进计数相 / enter the gating phase
        END_IF

    E_DL_FreqMeasState.eGating:                 // 计数中：门到即转发布相
        IF NOT bEnable THEN
            _eState := E_DL_FreqMeasState.eIdle; // 失能回待机 / disabled, back to idle
        ELSIF fbGate.Q THEN
            _eState := E_DL_FreqMeasState.eReady; // 门到，转发布相（发布在段 7） / gate done, publishing happens in segment seven
        END_IF

    E_DL_FreqMeasState.eReady:                  // 发布相：段 7 发布、段 8 迁移
        IF NOT bEnable THEN
            _eState := E_DL_FreqMeasState.eIdle; // 失能中止 / disabled, abort
        END_IF

    E_DL_FreqMeasState.eFault:                  // 故障：参数恢复即回待机
        IF NOT _bParamFault THEN
            _eState := E_DL_FreqMeasState.eIdle; // 参数已恢复 / parameters recovered
        END_IF

    ELSE
        eErr    := 16#0001_03B5;                // 兜底复用：非法状态（R90 不加码） / fallback reuse: illegal state
        bError  := TRUE;                        // 置故障标志 / raise the fault flag
        _uCount := 0;                           // 计数清零，绝不带着脏计数继续 / counter cleared, never continue with a dirty count
        _bGateBreak := TRUE;                    // 门计时重启 / gate timer restarted
        _eState := E_DL_FreqMeasState.eIdle;    // 回安全态 / back to the safe state
END_CASE

(*------------------------------------------------------------------------------
 * 段 7｜发布（eReady 相内单拍；fFreq / fFreqRes / uLastCount 的唯一写入点）
 *      Publish inside the ready phase, the single write point for all three values
 *-----------------------------------------------------------------------------*)
IF _eState = E_DL_FreqMeasState.eReady THEN
    _fGateMs := TIME_TO_REAL(_tGateUse);        // 门时间换算为毫秒数 [ms] / gate time in milliseconds

    IF _fGateMs <= 0.0 THEN
        _fGateMs := DL_MS_PER_S;                // 除零兜底：结构性不可达 / division fallback, structurally unreachable
    END_IF

    _uLastCountH := _uCount;                    // 锁存本门计数 [个] / latch this gate count
    _fFreqHeld   := (UDINT_TO_REAL(_uLastCountH) / _fGateMs) * DL_MS_PER_S; // N/ms×1000 = N/s [Hz] / edges per millisecond to hertz
    _fResHeld    := DL_MS_PER_S / _fGateMs;     // 分辨率 = 1/T_gate [Hz] / resolution is one over the gate time

    IF _fFreqHeld < _fDeadUse THEN
        _fFreqHeld := 0.0;                      // 死区内输出 0，不输出抖动小数 [Hz] / inside the dead band output zero
        eErr       := 16#0001_0465;             // 信息级：低于死区按 0 输出 / informational: below the dead band, zero output
    END_IF

    _bHaveMeas := TRUE;                         // 已有一次完整测量 / one full measurement exists
    _uCount    := 0;                            // 计数清零，准备下一门 / counter cleared for the next gate
    _bGateBreak := TRUE;                        // 门计时从零重启 / gate timer restarted from zero
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜迁移收尾（发布之后才允许 eReady → eGating，顺序不可反）
 *      Advance from ready back to gating only after the publish
 *-----------------------------------------------------------------------------*)
IF _eState = E_DL_FreqMeasState.eReady THEN
    _eState := E_DL_FreqMeasState.eGating;      // 回计数相 / back to the gating phase
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜出口单点写入与可用性仲裁
 *      Single write point of the outputs and the usability arbitration
 *-----------------------------------------------------------------------------*)
fFreq      := _fFreqHeld;                       // 频率出口 [Hz] / frequency outlet
fFreqRes   := _fResHeld;                        // 分辨率出口 [Hz] / resolution outlet
uLastCount := _uLastCountH;                     // 上一门计数出口 [个] / previous gate count outlet
_uCountPrev := _uCount;                         // 快照在段末唯一写入（R45②） / snapshot written once at the end

IF bError THEN
    bValid := FALSE;                            // 故障级：输出不可用 / fault: outputs unusable
ELSIF NOT bEnable THEN
    bValid := FALSE;                            // 失能：输出不可用（值仍保持，供停机前趋势） / disabled: unusable, values still held
ELSE
    bValid := _bHaveMeas;                       // 已有完整测量才宣称可用 / usable only after a full measurement
END_IF

END_FUNCTION_BLOCK
