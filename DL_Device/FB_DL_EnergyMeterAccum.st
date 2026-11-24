(*==============================================================================
 * 组件名称 (Component)  : FB_DL_EnergyMeterAccum
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 能源计量 · 电表冻结值累计与需量
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）语法，
 *                         仅依赖 Standard.library（R_TRIG / TON），无算术库依赖
 * 功能描述 (Function)   : 按电表冻结寄存器语义拼装 32 位电能累计值（正反向各一），
 *                         做单调性校验、换表与清零识别，并按窗口滑算平均需量与峰值
 *                         需量。输出正向、反向与净电能，以及换表次数、单拍换表脉冲。
 * 分层声明 (Layering)   : ① 本件只做「原始值拼装 + 累计 + 需量」，不做寄存器读取调度
 *                         （读取节拍归轮询主站件，本件由调用方按冻结值更新节拍调用）；
 *                         ② 不做分时电价、不做费率分段、不做报表归档；
 *                         ③ 字序入参复用 DL_MathData 既有枚举，不另立枚举、不重复声明。
 * 字序与字节序 (Order)  : 本件处理的是「字间序」——32 位电能由两个 16 位寄存器拼装，
 *                         厂家有的按高字在前、有的按低字在前；既有字节交换件处理的是
 *                         「字节内序」，两者层次不同、不可互相替代，参数切换时请勿混填。
 * 诊断分层 (Diagnosis)  : 遵循 NAMUR NE43「原始值域诊断与工程量分离」的原则：先判原始
 *                         32 位拼装值的单调性，再做工程量换算，诊断结论不依赖标定系数
 *                         ——标定系数填错只会让数值错，不会让「换表」判定失效。
 * 职责边界 (Scope)      : 不做 32 位回绕的无损续接（回绕按换表处理，属有意保守策略：
 *                         0.1 kWh 每 LSB 时满量程约 4.29 亿 kWh，真实场景回绕前必换表）。
 * 开源溯源 (Origin)     : 来源标签 namur-ne43。原创实现（参考 NAMUR NE43 的「原始值域
 *                         诊断与工程量分离」契约形态，以及电表冻结寄存器的工程惯例）。
 *                         仅借诊断分层的组织方式，拼装算法、单调性策略、窗口需量口径、
 *                         枚举、状态机与全部码位 100% 本库独立设计，clean-room 实现，
 *                         零代码行复制。NE43 为公开推荐规范（非代码），无代码复制问题。
 * 依赖     (Depends)    : E_DL_ByteOrder（DL_MathData 既有类型，本件只引用不声明）；
 *                         Standard.library: R_TRIG / TON
 * 故障码表 (Error codes):
 *   16#0003_0150【信息级】冻结值刷新抖动，差值在回退阈值内，保持上次累计不累加
 *   16#0003_0151【信息级】需量窗口小于 1 秒已按 1 秒兜底
 *   16#0003_0152【信息级】换表回退比例越界已钳到 0 至 1
 *   16#0003_0310【故障级】每 LSB 电能非正，量纲错且含除零隐患（锁存）
 *   16#0003_0311【故障级】有功功率非有限值，本拍不积分（锁存）
 *   16#0003_0312【故障级】非法状态兜底（锁存，终端安全态）
 * 码位占用 (Slot)       : 信息级 0150 / 0151 / 0152；故障级 0310 / 0311 / 0312。
 *                         全部落在 R12 本件分配块内，无跨块借用、无段外哨兵值。
 * 拍序纪律 (Cycle order) :
 *   ① ePhase     ：段 6 状态机（唯一位移点），段 8 复位分支是唯一回退点
 *   ② fImportAcc ：首拍基准装载 → 每拍单调性判定后单点写回；抖动拍保持不写
 *   ③ 窗口累加器 ：段 6 的采样分支累加，段 6 的窗口结算分支清零，两处互斥
 *   ④ uErrorId   ：段 9 单一优先级链，全拍只写一次
 * 需量口径 (Demand)     : 平均需量按「窗口内电能除以窗口秒数再乘 3600」折算为千瓦；
 *                         窗口长度取需量窗口参数，暂停期间窗口冻结、恢复后按剩余时间
 *                         续计（不重头），故暂停不会把需量摊薄。
 * 验收向量 (Acceptance) :
 *   V1 高位与低位拼装：高字 1、低字 16#86A0、每 LSB 0.1 → 原始 100000 → 正向 10000.0 kW 时
 *   V2 增量：下拍低字加 1 → 正向 10000.1、增量 0.1
 *   V3 换表：随后低字回 5 → 检出换表，单拍脉冲、换表次数 1、正向重载为 0.5 且无负增量
 *   V4 需量：有功 100 kW、窗口 15 分钟、满窗 → 平均需量 100.0、峰值 100.0
 *   V5 量纲错：每 LSB 为 0 → 故障位置位、码 0310
 * 偏离留档 (Deviation)  :
 *   ① 规格第 3.14 节的回退判据写成「低于累计值减去回退比例乘 32 位满量程乘标定系数」，
 *      该式与验收向量 V3 矛盾（满量程 4.29 亿 kWh 的 1% 远大于 10000.1，换表永远判不出）。
 *      本件改为「低于累计值乘（1 减回退比例）」，即按累计值的比例判定，与 V3 一致，
 *      也是现场对「回退比例」一词的通行理解。
 *   ② 规格要求「周期取窗口秒数除以拍数」，但首窗拍数未知。本件以常量化标称周期开窗，
 *      窗口结算时用实测拍数刷新估计值，并在头注释声明「必须放在固定周期任务中调用」。
 *   ③ 反向电能的换表不累加换表次数（次数只记正向表，避免一表两计）。
 *   ④ 规格 VAR 清单列有冻结沿实例，但本件没有与之配套的显示位输出，实例化后其输出
 *      无处消费即成为只置不用的死代码；故不实例化，bFreezePulse 引脚保留，累计逻辑
 *      每拍按原始值递推、与冻结脉冲无关（防止误把冻结沿当累加触发）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（R12 · 泳道 C · 电能累计与需量件）
 *   2026-11-15  v1.0.1  终审修复：二次及以后的暂停会拉长需量窗口。原实现用「整窗减已用
 *                       时间」保存剩余时间，但恢复后定时器的预置值已是剩余窗，ET 属于该
 *                       剩余窗，两者相减把剩余时间算大（窗口 900 s、半程暂停两次会拉长到
 *                       约 1300 s），平均需量被摊薄。改为按本拍实际预置值（tPtUse）求差
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_MeterPhase（本块相位，归属本功能块并同文件发布）
 *       Phase enumeration owned by this block and published in the same file
 *-----------------------------------------------------------------------------*)
TYPE E_DL_MeterPhase :
(
    eIdle     := 0,   // 待机：参数闸门未过或未使能，输出保持 / Idle, parameters not yet accepted or disabled
    eSampling := 10,  // 采样：拼装、换算、单调性判定、窗口积分与需量结算 / Sampling, the whole accumulation path
    eHeld     := 20,  // 冻结：掉使能，窗口停在剩余时间处，输出保持 / Held, the window is parked at its remaining time
    eFault    := 99   // 故障：量纲错、功率非有限或非法状态，需复位退出 / Fault, needs a reset to leave
);
END_TYPE

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_MeterState（跨周期状态，由调用方持有）
 *         Persistent state structure, owned by the caller
 *         说明：累计值、窗口累加器与换表计数必须跨周期保持，建议声明为保持型变量，
 *               否则重新上电会把窗口与峰值清空、并可能把首拍误判为换表
 *-----------------------------------------------------------------------------*)
TYPE ST_DL_MeterState :
STRUCT
    uImportPrev   : UDINT;      // 上次正向原始拼装值 [LSB] / Previous stitched import raw value
    uExportPrev   : UDINT;      // 上次反向原始拼装值 [LSB] / Previous stitched export raw value
    fImportAcc    : REAL;       // 正向累计电能 [kWh] / Accumulated import energy
    fExportAcc    : REAL;       // 反向累计电能 [kWh] / Accumulated export energy
    fWindowEnergy : REAL;       // 本窗口已积电能 [kWh] / Energy accumulated in the current window
    tWindowElapsed: TIME;       // 本窗口已用时间 [毫秒] / Elapsed time of the current window
    fDemandPeak   : REAL;       // 历史峰值需量 [kW]，仅复位可清 / Peak demand, cleared by reset only
    uResetCount   : UDINT;      // 换表与清零累计次数 [次] / Meter swap and clear counter
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_DL_EnergyMeterAccum
VAR_INPUT
    bEnable        : BOOL;                         // 使能，FALSE 时冻结累计与窗口 [-] / Enable, freezing accumulation and the window
    bReset         : BOOL;                         // 复位需量窗口与统计，上升沿有效 [-] / Rising edge resets the window statistics
    uImportHi      : UINT;                         // 正向有功电能高字 [LSB] / Import energy high word
    uImportLo      : UINT;                         // 正向有功电能低字 [LSB] / Import energy low word
    uExportHi      : UINT;                         // 反向有功电能高字 [LSB] / Export energy high word
    uExportLo      : UINT;                         // 反向有功电能低字 [LSB] / Export energy low word
    fActivePower   : REAL;                         // 当前有功功率 [kW] / Active power in kilowatts
    eWordOrder     : E_DL_ByteOrder := E_DL_ByteOrder.eAbcd; // 字序约定，复用既有枚举，默认大字序 [-] / Word order, defaults to the big word order
    fKwhPerLsb     : REAL := 0.1;                  // 每个 LSB 对应电能 [kWh/LSB]，域大于 0 / Kilowatt hours per LSB, must exceed zero
    tDemandWindow  : TIME := T#15M;                // 需量统计窗口 [毫秒]，域不小于 1 秒 / Demand window, at least one second
    fRegressRatio  : REAL := 0.01;                 // 判为换表的回退比例 [-]，域 0 到 1 / Regression ratio for a meter swap
    bFreezePulse   : BOOL;                         // 冻结寄存器刷新脉冲，仅用于显示锁存 [-] / Freeze register update pulse, display only
END_VAR
VAR_OUTPUT
    fImportTotal   : REAL;                         // 正向累计电能 [kWh] / Accumulated import energy
    fExportTotal   : REAL;                         // 反向累计电能 [kWh] / Accumulated export energy
    fNetTotal      : REAL;                         // 净电能，正向减反向 [kWh] / Net energy, import minus export
    fDemandAvg     : REAL;                         // 本窗口平均需量 [kW] / Average demand of the window
    fDemandPeak    : REAL;                         // 历史峰值需量 [kW]，由复位清零 / Peak demand, cleared by reset
    fWindowEnergy  : REAL;                         // 本窗口累计电能 [kWh] / Energy accumulated in the window
    bMeterReset    : BOOL;                         // 检到换表或清零，单拍脉冲 [-] / Meter swap detected, one-scan pulse
    uResetCount    : UDINT;                        // 换表与清零累计次数 [次] / Swap events counted
    bError         : BOOL;                         // 故障级锁存，仅 0310 0311 0312 置位 [-] / Latched fault, only fault level codes set it
    uErrorId       : UDINT;                        // 事件码，0 表示无事件 [代码] / Event code, zero means none
    eState         : E_DL_MeterPhase;              // 主状态机当前相位 [-] / Current phase of the main state machine
END_VAR
VAR_IN_OUT
    stMeter        : ST_DL_MeterState;             // 跨周期：上次原始值、累计基准、窗口累加器 [-] / Persistent raw values, accumulators and window state
END_VAR
VAR
    fbTrigReset    : R_TRIG;                       // 复位沿检测，主周期无条件刷新 [-] / Reset edge detector, refreshed unconditionally
    fbWindow       : TON;                          // 需量窗口计时，主周期无条件刷新 / Demand window timer, refreshed unconditionally
    ePhase         : E_DL_MeterPhase := E_DL_MeterPhase.eIdle; // 内部相位，对外经 eState 输出 [-] / Internal phase exported as eState
    bInit          : BOOL := FALSE;                // 首扫标志，初值 FALSE，判据取非 [-] / First-scan flag initialised FALSE
    bInitSync      : BOOL := FALSE;                // 累计基准已装载（首拍不产生增量）[-] / Accumulation baseline loaded flag
    bFaultLatch    : BOOL;                         // 故障锁存，仅复位分支清除 [-] / Fault latch, cleared by the reset path only
    uErrInt        : UDINT;                        // 故障级码寄存，锁存型 [代码] / Latched fault level code register
    uInfoCode      : UDINT;                        // 本拍信息级码，每拍重算 [代码] / Info level code recomputed every scan
    fLsbUse        : REAL := 1.0;                  // 生效每 LSB 电能 [kWh/LSB]，钳位后 / Effective kilowatt hours per LSB after clamping
    fRatioUse      : REAL := 0.01;                 // 生效回退比例 [-]，钳位后 / Effective regression ratio after clamping
    tWinUse        : TIME := T#15M;                // 生效窗口长度 [毫秒]，钳位后 / Effective window length after clamping
    tPtUse         : TIME := T#15M;                // 本拍窗口定时器预置值 [毫秒]，恢复模式取剩余时间 / Timer preset of this scan
    tRemain        : TIME := T#15M;                // 暂停时保存的窗口剩余时间 [毫秒] / Remaining window time saved on hold
    fWinSec        : REAL := 900.0;                // 窗口长度换算成秒 [秒] / Window length in seconds
    bWinRun        : BOOL;                         // 窗口定时器输入电平 [-] / Window timer input level
    bWinBreak      : BOOL;                         // 窗口定时器断输入一拍 [-] / One-scan break of the window timer
    bWinEnd        : BOOL;                         // 窗口到点标志 [-] / Window boundary flag
    bRestoreMode   : BOOL;                         // 恢复模式，定时器预置值取剩余时间 [-] / Restore mode, the timer uses the remaining time
    uImportRaw     : UDINT;                        // 正向电能 32 位拼装值 [LSB] / Stitched import raw value
    uExportRaw     : UDINT;                        // 反向电能 32 位拼装值 [LSB] / Stitched export raw value
    fImportNow     : REAL;                         // 本次正向电能换算值 [kWh] / Converted import value of this scan
    fExportNow     : REAL;                         // 本次反向电能换算值 [kWh] / Converted export value of this scan
    fRegressThr    : REAL;                         // 本拍回退判定阈值 [kWh] / Regression threshold of this scan
    nCycleCount    : DINT;                         // 本窗口累计拍数 [拍] / Scan counter of the current window
    fCycleEst      : REAL := 0.01;                 // 标称周期估计值 [秒] / Estimated nominal cycle in seconds
    eOrderAbcd     : E_DL_ByteOrder := E_DL_ByteOrder.eAbcd; // 字序比较基准：大字序口径（声明区取值，便于统一审查）[-] / Word order comparison baseline
    bSwap          : BOOL;                         // 本次判为换表或清零 [-] / Swap detected this scan
    bRegress       : BOOL;                         // 本次判为刷新抖动 [-] / Jitter detected this scan
    bPowerFinite   : BOOL;                         // 有功功率有限标志 [-] / Finite active power flag
END_VAR
VAR CONSTANT
    DL_MS_PER_SEC   : REAL := 1000.0;              // 每秒毫秒数 [毫秒] / Milliseconds per second
    DL_SEC_PER_HOUR : REAL := 3600.0;              // 每小时秒数 [秒] / Seconds per hour
    DL_EPS          : REAL := 1.0E-6;              // 浮点比较容差 [kWh] / Float comparison tolerance
    DL_LSB_FALLBACK : REAL := 1.0;                 // 每 LSB 电能非法时的兜底值 [kWh/LSB] / Fallback gain
    DL_PWR_MAX      : REAL := 1.0E9;               // 功率合理上限，超出视为非有限 [kW] / Power sanity limit
    DL_CYCLE_MIN    : REAL := 1.0E-3;              // 周期估计下限 [秒] / Lower cycle bound
    DL_CYCLE_MAX    : REAL := 1.0;                 // 周期估计上限 [秒] / Upper cycle bound
    DL_CYCLE_NOM    : REAL := 0.01;                // 首窗标称周期 [秒]，10 毫秒任务 / Nominal cycle for the first window
    DL_WIN_MIN      : TIME := T#1S;                // 窗口长度下限 [毫秒] / Minimum window length
    DL_TIME_ZERO    : TIME := T#0S;                // 时间零值基准 [毫秒] / Time zero reference
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出确定性默认值（单拍标志每拍预清零，R25 第一律）
 *      Deterministic defaults first, one-scan flags pre-cleared every scan
 *-----------------------------------------------------------------------------*)
bMeterReset  := FALSE;                          // 换表脉冲预清零（Swap pulse pre-cleared）
uInfoCode    := 16#0000_0000;                   // 信息级码每拍重算（Info code recomputed every scan）
bSwap        := FALSE;                          // 换表判定预清零（Swap verdict pre-cleared）
bRegress     := FALSE;                          // 抖动判定预清零（Jitter verdict pre-cleared）
bPowerFinite := FALSE;                          // 功率有限标志预清零（Finite power flag pre-cleared）

(*------------------------------------------------------------------------------
 * 段 2｜沿检测无条件刷新（红线：实例在 CASE 之外每拍必刷）
 *      Edge detection refreshed unconditionally outside the CASE
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 3｜首扫初始化（唯一合法范式：初值 FALSE，判据取非）
 *      First-scan initialisation following the single legal pattern
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    stMeter.uImportPrev    := 0;                // 上次正向原始值清零（Previous import raw cleared）
    stMeter.uExportPrev    := 0;                // 上次反向原始值清零（Previous export raw cleared）
    stMeter.fImportAcc     := 0.0;              // 正向累计清零（Import accumulation cleared）
    stMeter.fExportAcc     := 0.0;              // 反向累计清零（Export accumulation cleared）
    stMeter.fWindowEnergy  := 0.0;              // 窗口累加器清零（Window accumulator cleared）
    stMeter.tWindowElapsed := DL_TIME_ZERO;     // 窗口已用时间清零（Window elapsed cleared）
    stMeter.fDemandPeak    := 0.0;              // 峰值需量清零（Peak demand cleared）
    stMeter.uResetCount    := 0;                // 换表次数清零（Swap counter cleared）
    nCycleCount            := 0;                // 窗口拍计数清零（Window scan counter cleared）
    fCycleEst              := DL_CYCLE_NOM;     // 周期估计取标称值（Cycle estimate set to the nominal value）
    fDemandAvg             := 0.0;              // 平均需量清零（Average demand cleared）
    bWinRun                := FALSE;            // 窗口定时器停（Window timer stopped）
    bRestoreMode           := FALSE;            // 恢复模式关闭（Restore mode off）
    bInitSync              := FALSE;            // 累计基准待装载（Baseline to be loaded）
    fLsbUse                := DL_LSB_FALLBACK;  // 生效增益先给兜底值（Effective gain pre-set to the fallback）
    fRatioUse              := 0.0;              // 生效回退比例先给零（Effective ratio pre-set to zero）
    tWinUse                := DL_WIN_MIN;       // 生效窗口先给下限（Effective window pre-set to the lower bound）
    ePhase                 := E_DL_MeterPhase.eIdle; // 相位复位为待机（Phase reset to idle）
    bInit                  := TRUE;             // 首扫只做一次（First scan runs once）
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜参数闸门（量纲错属故障级，窗口与比例越界属信息级，只钳位不停机）
 *      Parameter gate, dimensional errors latch a fault while clamps stay informational
 *-----------------------------------------------------------------------------*)
IF fKwhPerLsb <= DL_EPS THEN
    fLsbUse     := DL_LSB_FALLBACK;             // 量纲错：先给兜底增益避免本拍出现零乘（Fallback gain avoids a zero product）
    bFaultLatch := TRUE;                        // 锁故障（Latch the fault）
    uErrInt     := 16#0003_0310;                // 0310 每 LSB 电能非正（Non-positive energy per LSB）
ELSE
    fLsbUse := fKwhPerLsb;                      // 合法增益直通（Valid gain passed through）
END_IF

IF tDemandWindow < DL_WIN_MIN THEN
    tWinUse   := DL_WIN_MIN;                    // 小于 1 秒按 1 秒兜底，防需量除零（Clamped to one second to avoid a zero divisor）
    uInfoCode := 16#0003_0151;                  // 0151 窗口过短已兜底（Window too short, clamped）
ELSE
    tWinUse := tDemandWindow;                   // 合法窗口直通（Valid window passed through）
END_IF

IF fRegressRatio < 0.0 THEN
    fRatioUse := 0.0;                           // 负比例无意义：钳到 0（A negative ratio is clamped to zero）
    uInfoCode := 16#0003_0152;                  // 0152 比例越界已钳位（Ratio clamped）
ELSIF fRegressRatio > 1.0 THEN
    fRatioUse := 1.0;                           // 超 1 无意义：钳到 1（A ratio above one is clamped）
    uInfoCode := 16#0003_0152;                  // 0152 比例越界已钳位（Ratio clamped）
ELSE
    fRatioUse := fRegressRatio;                 // 合法比例直通（Valid ratio passed through）
END_IF

IF tWinUse > DL_TIME_ZERO THEN
    fWinSec := DINT_TO_REAL(TIME_TO_DINT(tWinUse)) / DL_MS_PER_SEC; // 窗口秒数，防除零由上限闸门保证（Seconds of the window）
ELSE
    fWinSec := 1.0;                             // 零窗口兜底为 1 秒（Zero window falls back to one second）
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜32 位电能拼装（字间序，与字节内序件层次不同）
 *      Thirty-two bit energy stitching by word order
 *-----------------------------------------------------------------------------*)
IF eWordOrder = eOrderAbcd THEN
    uImportRaw := SHL(UINT_TO_UDINT(uImportHi), 16) OR UINT_TO_UDINT(uImportLo); // 高字在前（High word first）
    uExportRaw := SHL(UINT_TO_UDINT(uExportHi), 16) OR UINT_TO_UDINT(uExportLo); // 高字在前（High word first）
ELSE
    uImportRaw := SHL(UINT_TO_UDINT(uImportLo), 16) OR UINT_TO_UDINT(uImportHi); // 低字在前（Low word first）
    uExportRaw := SHL(UINT_TO_UDINT(uExportLo), 16) OR UINT_TO_UDINT(uExportHi); // 低字在前（Low word first）
END_IF
fImportNow := UDINT_TO_REAL(uImportRaw) * fLsbUse; // 正向工程量换算（Import engineering conversion）
fExportNow := UDINT_TO_REAL(uExportRaw) * fLsbUse; // 反向工程量换算（Export engineering conversion）

(*------------------------------------------------------------------------------
 * 段 6｜窗口计时（无条件刷新；入口电平取上一拍状态，断输入一拍重启）
 *      Window timer refreshed unconditionally, restarted by a one-scan break
 *-----------------------------------------------------------------------------*)
IF bRestoreMode THEN
    tPtUse := tRemain;                          // 恢复模式用剩余时间作预置值（Restore mode uses the remaining time）
ELSE
    tPtUse := tWinUse;                          // 正常模式用整窗作预置值（Normal mode uses the full window）
END_IF
fbWindow(IN := bWinRun AND (NOT bWinBreak), PT := tPtUse);
bWinBreak := FALSE;                             // 断输入脉冲在实例调用后自清（Break pulse self-cleared after the call）
bWinEnd   := fbWindow.Q;                        // 到点标志在实例调用后取用（Boundary flag read after the call）
stMeter.tWindowElapsed := fbWindow.ET;          // 窗口已用时间转出（Elapsed time exported）

(*------------------------------------------------------------------------------
 * 段 7｜主状态机（枚举每个成员均有标签，末尾 ELSE 兜底到终端安全态）
 *      Main state machine, one label per member plus a trailing ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE ePhase OF

    E_DL_MeterPhase.eIdle: // 待机：参数可用且使能后进入采样
        IF bFaultLatch THEN
            ePhase := E_DL_MeterPhase.eFault;   // 参数已锁故障：直接进故障态（Gate failed, enter the fault state）
        ELSIF bEnable THEN
            bWinRun := TRUE;                    // 启动窗口（Start the window）
            ePhase  := E_DL_MeterPhase.eSampling; // 进采样态（Enter the sampling state）
        END_IF

    E_DL_MeterPhase.eSampling: // 采样：单调性判定、窗口积分、需量结算
        bWinRun := TRUE;                        // 窗口持续计时（Window keeps timing）
        IF NOT bInitSync THEN
            stMeter.fImportAcc  := fImportNow;  // 首拍只装载基准，不产生增量（First scan loads the baseline only）
            stMeter.fExportAcc  := fExportNow;  // 首拍只装载基准（First scan loads the baseline only）
            stMeter.uImportPrev := uImportRaw;  // 首拍记录原始值（Raw value recorded on the first scan）
            stMeter.uExportPrev := uExportRaw;  // 首拍记录原始值（Raw value recorded on the first scan）
            bInitSync           := TRUE;        // 基准装载完成（Baseline loaded）
        ELSE
            (* 正向单调性：低于累计值乘（1 减回退比例）判换表，低于容差内判抖动 *)
            fRegressThr := stMeter.fImportAcc * (1.0 - fRatioUse); // 回退阈值按累计值比例给出（Threshold from the accumulated value）
            IF fImportNow < fRegressThr THEN
                bSwap := TRUE;                  // 先判：大幅回退，疑似换表或清零（Decide first, a large regression looks like a swap）
            ELSIF fImportNow < (stMeter.fImportAcc - DL_EPS) THEN
                bRegress := TRUE;               // 先判：小幅回退，疑似刷新抖动（Decide first, a small regression looks like jitter）
            END_IF
            IF bSwap THEN
                bMeterReset         := TRUE;    // 单拍换表脉冲（One-scan swap pulse）
                stMeter.uResetCount := stMeter.uResetCount + 1; // 换表次数累加（Swap counter incremented）
                stMeter.fImportAcc  := fImportNow; // 基准重载，不回填负增量（Baseline reloaded, never a negative increment）
            ELSIF bRegress THEN
                uInfoCode := 16#0003_0150;      // 0150 冻结值刷新抖动（Freeze refresh jitter）
            ELSE
                stMeter.fImportAcc := fImportNow; // 正常递推（Normal accumulation）
            END_IF
            (* 反向单调性：只做基准重载，不重复计入换表次数 *)
            fRegressThr := stMeter.fExportAcc * (1.0 - fRatioUse); // 反向回退阈值（Export threshold）
            IF fExportNow < fRegressThr THEN
                stMeter.fExportAcc := fExportNow; // 反向换表：基准重载（Export baseline reloaded）
            ELSIF fExportNow >= stMeter.fExportAcc THEN
                stMeter.fExportAcc := fExportNow; // 正常递推（Normal accumulation）
            END_IF
            stMeter.uImportPrev := uImportRaw;  // 记录本拍原始值（Record the raw value of this scan）
            stMeter.uExportPrev := uExportRaw;  // 记录本拍原始值（Record the raw value of this scan）
        END_IF
        (* 有功功率有限性闸门：非有限值本拍不积分，并锁故障 *)
        IF (fActivePower <> fActivePower) OR (ABS(fActivePower) > DL_PWR_MAX) THEN
            bPowerFinite := FALSE;              // 判为非法功率（Marked as invalid power）
            IF NOT bFaultLatch THEN
                bFaultLatch := TRUE;            // 只在无更早故障时锁存，保留首出码 / Latch only when no earlier fault exists
                uErrInt     := 16#0003_0311;    // 0311 有功功率非有限（Non-finite active power）
            END_IF
        ELSE
            bPowerFinite := TRUE;               // 判为合法功率（Marked as valid power）
        END_IF
        (* 窗口积分：仅合法功率参与，故障拍不污染窗口 *)
        IF bPowerFinite THEN
            stMeter.fWindowEnergy := stMeter.fWindowEnergy + (fActivePower * fCycleEst); // 电能累加，千瓦乘小时（Energy in kilowatt hours）
            nCycleCount           := nCycleCount + 1; // 窗口拍数累加（Window scan counter incremented）
        END_IF
        (* 窗口结算：平均需量、峰值需量、周期估计刷新、累加器清零 *)
        IF bWinEnd THEN
            IF fWinSec > DL_EPS THEN
                fDemandAvg := stMeter.fWindowEnergy / fWinSec * DL_SEC_PER_HOUR; // 千瓦时转千瓦（Kilowatt hours to kilowatts）
            END_IF
            IF fDemandAvg > stMeter.fDemandPeak THEN
                stMeter.fDemandPeak := fDemandAvg; // 峰值取大（Peak takes the larger value）
            END_IF
            IF nCycleCount > 0 THEN
                fCycleEst := fWinSec / DINT_TO_REAL(nCycleCount); // 用实测拍数刷新周期估计（Cycle estimate refreshed from the measured count）
                fCycleEst := LIMIT(DL_CYCLE_MIN, fCycleEst, DL_CYCLE_MAX); // 周期估计钳位（Cycle estimate clamped）
            END_IF
            stMeter.fWindowEnergy := 0.0;       // 窗口累加器清零（Window accumulator cleared）
            nCycleCount           := 0;         // 窗口拍数清零（Window scan counter cleared）
            bRestoreMode          := FALSE;     // 退出恢复模式（Leave restore mode）
            bWinBreak             := TRUE;      // 定时器断输入一拍后重启（Restart the timer after a one-scan break）
        END_IF
        IF NOT bEnable THEN
            tRemain      := tPtUse - fbWindow.ET; // 保存剩余时间：按本拍实际预置值算，恢复态取剩余窗而非整窗（Remaining time from the preset in force）
            IF tRemain < DL_WIN_MIN THEN
                tRemain := DL_WIN_MIN;          // 剩余时间下限兜底（Remaining time lower bound）
            END_IF
            bWinRun     := FALSE;               // 窗口停止推进（Window stops advancing）
            ePhase      := E_DL_MeterPhase.eHeld; // 进冻结态（Enter the held state）
        ELSIF bFaultLatch THEN
            ePhase := E_DL_MeterPhase.eFault;   // 功率非法：进故障态（Invalid power, enter the fault state）
        END_IF

    E_DL_MeterPhase.eHeld: // 冻结：输出保持，恢复后按剩余时间续计，不重头
        bWinRun := FALSE;                       // 冻结期间窗口不推进（The window does not advance while held）
        IF bEnable THEN
            bRestoreMode := TRUE;               // 进入恢复模式（Enter restore mode）
            bWinBreak    := TRUE;               // 定时器断输入一拍后按剩余时间重启（Restart with the remaining time）
            bWinRun      := TRUE;               // 窗口重新推进（The window advances again）
            ePhase       := E_DL_MeterPhase.eSampling; // 回采样态（Back to sampling）
        END_IF

    E_DL_MeterPhase.eFault: // 故障：输出保持，等复位沿（Fault, outputs held until the reset edge）
        bWinRun := FALSE;                       // 故障期间窗口停止（The window stops during a fault）

    ELSE
        bFaultLatch := TRUE;                    // 非法状态兜底锁存（Illegal state latched）
        uErrInt     := 16#0003_0312;            // 0312 非法状态兜底（Illegal state fallback code）
        ePhase      := E_DL_MeterPhase.eFault;  // 进终端安全态（Enter the terminal safe state）
END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜复位（清需量窗口与统计；累计值属电表自身读数，不清零）
 *      Reset clears the window statistics; the accumulated energy follows the meter
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    stMeter.fWindowEnergy := 0.0;               // 窗口累加器清零（Window accumulator cleared）
    stMeter.fDemandPeak   := 0.0;               // 峰值需量清零（Peak demand cleared）
    stMeter.uResetCount   := 0;                 // 换表次数清零（Swap counter cleared）
    fDemandAvg            := 0.0;               // 平均需量清零（Average demand cleared）
    nCycleCount           := 0;                 // 窗口拍数清零（Window scan counter cleared）
    bRestoreMode          := FALSE;             // 恢复模式关闭（Restore mode off）
    bWinBreak             := TRUE;              // 窗口定时器重启（Window timer restarted）
    bInitSync             := FALSE;             // 累计基准重装，复位后首拍不判换表（Baseline reloaded, no false swap after a reset）
    bFaultLatch           := FALSE;             // 清故障锁存（Clear the fault latch）
    uErrInt               := 16#0000_0000;      // 清故障码（Clear the fault code）
    IF ePhase = E_DL_MeterPhase.eFault THEN
        ePhase := E_DL_MeterPhase.eIdle;        // 故障态复位回待机（Fault returns to idle）
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜码位定级与出口（单一优先级链，全拍只写一次 uErrorId）
 *      Single priority chain and outlet mapping
 *-----------------------------------------------------------------------------*)
eState        := ePhase;                        // 相位出口（Phase outlet）
fImportTotal  := stMeter.fImportAcc;            // 正向累计出口（Import total outlet）
fExportTotal  := stMeter.fExportAcc;            // 反向累计出口（Export total outlet）
fNetTotal     := fImportTotal - fExportTotal;   // 净电能出口（Net energy outlet）
fWindowEnergy := stMeter.fWindowEnergy;         // 窗口电能出口（Window energy outlet）
fDemandPeak   := stMeter.fDemandPeak;           // 峰值需量出口（Peak demand outlet）
uResetCount   := stMeter.uResetCount;           // 换表次数出口（Swap counter outlet）

bError := bFaultLatch;                          // 故障位只反映故障级锁存（Fault bit reflects the latch only）
IF bError THEN
    uErrorId := uErrInt;                        // 故障级码优先透出（Fault level code has priority）
ELSE
    uErrorId := uInfoCode;                      // 无故障透出本拍信息级码（Info code exposed otherwise）
END_IF
END_FUNCTION_BLOCK
