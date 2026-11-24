(*==============================================================================
 * 组件名称 (Component)  : FB_DL_InertPurgeSeq
 * 溯源说明 (Provenance): 道莅 clean-room 防御性实现（IEC 61131-3 纯净实现，闭源文档仅借语义，零代码行）
 * 所属子库 (Sublibrary) : DL_Process / Sequence
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），仅用
 *                         Standard.library 的 TON / TIME_TO_DINT / DINT_TO_TIME
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 氮气置换顺控
 * 功能一句话 (Summary)  : 抽真空 → 充氮 → 保压取样 三相同循环置换，氧含量达目标
 *                         即放行，循环耗尽未达标则锁定失败，中止任意拍立即停。
 *
 * 本件存在的意义 (Why this unit exists)
 *   可燃溶剂场合点火/投料前的氮气置换是强制步骤，也是审核最容易被问的
 *   一条。它的逻辑不难，但「相转出必须断输入」这一点几乎每份手写代码都会
 *   踩：三相共用一只 TON，抽真空相残留的 ET 会让充氮相提前结束，或者
 *   保压相一进就走。本件把每相各一只 TON、相转出断输入一拍写成结构约束
 *   （R40 家族第三次事故的共同形态就在这一格）。
 *
 * 单循环定义 (One cycle)
 *   eEvacuate   : 抽真空阀开，tEvac 时间到**且**真空达 fVacOk → 进充氮
 *   eFillN2     : 充氮阀开，tFill 时间到 → 进保压取样
 *   eHoldVerify : 全阀关（保持压力），tHold 后读取氧含量
 *                 ≤ fO2Target → eComplete（信息 01DF）
 *                 否则循环数 +1：未达 uMaxCycles → eCycleDone → 回抽真空（信息 01DE）
 *                 已达 uMaxCycles → eFailed（故障 0313）
 *
 * 中止语义（三件顺控件共用同一段口径）
 *   bAbort **任意拍**生效：先清全部执行输出（三相阀），再回 eIdle；
 *   **不排队、不回退重来、不自动续跑**——中止是人的决定，重启必须由新的
 *   bStart 重新开始。原因：自动续跑会让操作工以为按了一次中止就断电了，
 *   实际设备又自己动起来，这是顺控件最危险的一类行为（R34 家族）。
 *
 * 边界安全 (Boundary)
 *   ① fO2Target <= 0、uMaxCycles = 0 或任一 TIME = 0 → 故障 0311、回 eIdle；
 *   ② bO2SensorOk = FALSE → 故障 0312、**禁止放行**（bDone 恒 FALSE）、三阀全关；
 *      氧分析仪坏掉时置换结果无从判断，继续循环只是白烧氮气；
 *   ③ 循环耗尽未达标 → bFailed := TRUE + 故障 0313；
 *   ④ 抽真空相 tEvac 到而真空未达 → 重新计时继续抽，连续 DL_EVAC_RETRY 次仍未达
 *      → 按「置换无法建立」处理，复用 0313（R90 不加码，理由见头注释）；
 *   ⑤ 三相各一只 TON，相转出以「断输入一拍」标志重启，绝不跨相复用实例；
 *   ⑥ 三阀输出互斥，段 1 先全清、段 7 按状态最多置一路（R72）；
 *   ⑦ CASE 落 ELSE 置 0313 并回 eIdle（兜底复用，R90）；
 *   ⑧ 放空阀编排约定：仅在 eComplete（置换合格）后打开以便泄压放行；
 *      eFailed 与其它相一律关闭——置换失败时保持惰化封闭，交人工处置。
 *
 * 引脚补全声明 (Pin completion)
 *   规格正文要求「真空达 fVacOk」判据，但引脚表未列真空度实测，故补
 *   fVacMeas : REAL [kPa g]。缺此引脚则「抽真空到位」无从判断，只能退化成
 *   纯定时，与本件语义不符。
 *
 * 错误码    : 16#0005_01DE 单循环未达标，进入下一循环——信息级
 *             16#0005_01DF 取样窗内氧含量已达目标——信息级，放行前置条件满足
 *             16#0005_0311 置换参数非法（目标/循环数/时长）——故障级，回 eIdle
 *             16#0005_0312 氧分析仪无效，禁止放行——故障级，三阀全关
 *             16#0005_0313 置换循环耗尽未达标（含状态机兜底与真空建立失败复用，R90）——故障级
 * 码位总账  : 16#0005_01DE 用 / 16#0005_01DF 用 ｜ 16#0005_0311 用 / 16#0005_0312 用 / 16#0005_0313 用
 * 状态机    : E_DL_PurgeState（eIdle / eEvacuate / eFillN2 / eHoldVerify / eCycleDone /
 *             eComplete / eFailed / eFault），CASE 含 ELSE 兜底，ELSE 置 16#0005_0313 并回 eIdle
 * 采样约定  : 每任务周期调用一次；各相时长由引脚给定，不读系统时钟
 * 依赖说明  : 只做组合编排，不复制低层算法；无 DL_ 子库调用
 * 验收向量  : V1 启动 → 抽真空 60 s 且真空 −85 kPa（< −80）→ 充氮 60 s → 保压 30 s
 *               读到 O2 1.2 %（≤ 2.0）→ eComplete，bDone = TRUE，eErr = 01DF
 *             V2 保压后 O2 3.5 %（> 2.0）、uMaxCycles = 3 → uCycleDone = 1，eErr = 01DE，
 *                回抽真空继续（循环主向量）
 *             V3 V2 连续三次未达标 → eFailed，bFailed = TRUE，eErr = 0313（耗尽主向量）
 *             V4 抽真空相 bAbort = TRUE → 三阀同拍全 FALSE，回 eIdle，不续跑（中止主向量）
 *             V5 bO2SensorOk = FALSE → eFault，三阀全关，bDone 恒 FALSE，eErr = 0312
 *             V6 uMaxCycles = 0 → eFault，eErr = 0311，回 eIdle
 *             V7 抽真空 3 次定时到但真空只有 −50 kPa → eFailed，eErr = 0313（真空建立失败复用）
 *             V8 eComplete 且 bStart 仍为 TRUE → 保持 eComplete（不放行丢失）；bStart 落 → eIdle
 * 红线自检  : 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 ｜ 纯 IEC 61131-3 ｜ 无除法
 *             浮点只用大小比较 ｜ 无循环 ｜ 全变量双语同行注释 ｜ ENUM + CASE 含 ELSE
 *             ｜ 三只 TON 在主体前部无条件刷新且各相各一只 ｜ 单拍标志全部预清零
 *             ｜ 阈值常量化，无魔法数
 * 修订历史  : 2026-11-16  v1.0.0  首版入库（R22 · 批 3 · 批处理顺控）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PurgeState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 氮气置换顺控相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_PurgeState :
(
    eIdle       := 0,   // 待机：未启动或已复位 / Idle, not started or already reset
    eEvacuate   := 10,  // 抽真空相：真空阀开 / Evacuation, vacuum valve open
    eFillN2     := 20,  // 充氮相：氮气阀开 / Nitrogen fill, nitrogen valve open
    eHoldVerify := 30,  // 保压取样相：全阀关，读氧含量 / Hold and verify, all valves closed
    eCycleDone  := 40,  // 单循环结束（单拍相），随后回抽真空 / Cycle done, one scan then back to evacuation
    eComplete   := 50,  // 置换合格：放行 / Complete, production released
    eFailed     := 60,  // 置换失败锁定：循环耗尽 / Failed, cycles exhausted and latched
    eFault      := 99   // 故障：参数非法或氧分析仪无效 / Fault, illegal parameters or an invalid oxygen analyser
);
END_TYPE

FUNCTION_BLOCK FB_DL_InertPurgeSeq
VAR_INPUT
    bStart       : BOOL;                       // 启动请求，电平有效 / start request, level active
    bAbort       : BOOL;                       // 中止请求，任意拍生效 / abort request, effective on any scan
    fO2Meas      : REAL;                       // 氧含量实测 [%] / measured oxygen content [%]
    bO2SensorOk  : BOOL;                       // 氧分析仪有效性 / oxygen analyser validity
    fO2Target    : REAL := 2.0;                // 目标氧含量 [%]，须 > 0 / target oxygen content [%], must be > 0
    uMaxCycles   : UINT := 3;                  // 最大置换循环数 [次]，须 > 0 / maximum purge cycles [count], must be > 0
    tEvac        : TIME := T#60S;              // 抽真空时长 [ms]，须 > 0 / evacuation duration [ms], must be > 0
    tFill        : TIME := T#60S;              // 充氮时长 [ms]，须 > 0 / nitrogen fill duration [ms], must be > 0
    tHold        : TIME := T#30S;              // 保压取样时长 [ms]，须 > 0 / hold and verify duration [ms], must be > 0
    fVacOk       : REAL := -80.0;              // 抽真空到位阈值 [kPa g]，读数须 <= 本值 / vacuum target [kPa g]
    fVacMeas     : REAL;                       // 真空度实测 [kPa g]（引脚补充，见头注释） / measured vacuum [kPa g]
END_VAR
VAR_OUTPUT
    bVacValveCmd  : BOOL;                      // 抽真空阀指令 / vacuum valve command
    bN2ValveCmd   : BOOL;                      // 氮气阀指令 / nitrogen valve command
    bVentValveCmd : BOOL;                      // 放空阀指令（仅合格后打开） / vent valve command, opened only when qualified
    uCycleDone    : UINT;                      // 已完成置换循环数 [次] / completed purge cycles [count]
    bDone         : BOOL;                      // 置换合格放行 / purge qualified, production released
    bFailed       : BOOL;                      // 置换失败锁定 / purge failed, latched
    eErr          : UDINT;                     // 错误码，0 表示无错 / error code, 0 means no error
    bError        : BOOL;                      // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid        : BOOL;                      // 输出可用标志 / outputs usable flag
END_VAR
VAR
    fbEvac       : TON;                        // 抽真空相计时，段 5 无条件刷新 [ms] / evacuation timer
    fbFill       : TON;                        // 充氮相计时，段 5 无条件刷新 [ms] / nitrogen fill timer
    fbHold       : TON;                        // 保压取样相计时，段 5 无条件刷新 [ms] / hold and verify timer
    _eState      : E_DL_PurgeState := E_DL_PurgeState.eIdle; // 当前相位 / current phase
    _bInit       : BOOL := FALSE;              // 首扫标志，初值 FALSE 取非判定 / first-scan flag, tested negated
    _bParamBad   : BOOL;                       // 参数非法标志 / illegal parameter flag
    _bSensorBad  : BOOL;                       // 氧分析仪无效标志 / invalid analyser flag
    _bIllegal    : BOOL;                       // 非法状态标志 / illegal state flag
    _bEvacBreak  : BOOL;                       // 抽真空计时器断输入一拍 / evacuation timer one-scan break
    _bFillBreak  : BOOL;                       // 充氮计时器断输入一拍 / fill timer one-scan break
    _bHoldBreak  : BOOL;                       // 保压计时器断输入一拍 / hold timer one-scan break
    _bVacOk      : BOOL;                       // 真空到位判据 / vacuum reached
    _bQualified  : BOOL;                       // 本拍取样合格 / qualified this scan
    _bCycleEvent : BOOL;                       // 本拍单循环结束事件 / cycle finished this scan
    _uCycleAcc   : UINT;                       // 已完成循环数保持量 [次] / held completed cycle count
    _uEvacRetry  : UINT;                       // 抽真空重试计数 [次] / evacuation retry counter
    _bFailedAcc  : BOOL;                       // 失败锁存保持量 / held failure latch
END_VAR
VAR CONSTANT
    DL_VAL_LIM     : REAL := 1.0E6;            // 有限性判定的绝对值上限 [无量纲] / finiteness ceiling
    DL_O2_MIN      : REAL := 0.0;              // 目标氧含量下限 [%]，须严格大于 / target oxygen floor, strictly greater
    DL_CYCLE_MIN   : UINT := 0;                // 循环数下限 [次] / cycle floor [count]
    DL_EVAC_RETRY  : UINT := 3;                // 抽真空最大重试次数 [次] / maximum evacuation retries
    DL_TIME_ZERO   : TIME := T#0MS;            // 时间零值基准 [ms] / time zero reference
    DL_CNT_MAX     : UINT := 65535;            // 循环计数饱和上界 [次] / cycle count saturation ceiling
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：三阀**先全清**（R72），单拍标志预清零（R25 第一律）
 *      Both commands cleared first, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
bVacValveCmd  := FALSE;                        // 抽真空阀先清 / vacuum valve cleared first
bN2ValveCmd   := FALSE;                        // 氮气阀先清 / nitrogen valve cleared first
bVentValveCmd := FALSE;                        // 放空阀先清 / vent valve cleared first
bDone         := FALSE;                        // 放行标志每拍重算 / release flag recomputed
bFailed       := FALSE;                        // 失败标志每拍重算 / failure flag recomputed
bValid        := FALSE;                        // 可用标志每拍重算 / usable flag recomputed
eErr          := 16#0000_0000;                 // 错误码每拍重算 / error code recomputed
bError        := FALSE;                        // 故障标志每拍重算 / fault flag recomputed
_bParamBad    := FALSE;                        // 参数非法标志预清零 / parameter flag pre-cleared
_bSensorBad   := FALSE;                        // 分析仪无效标志预清零 / analyser flag pre-cleared
_bIllegal     := FALSE;                        // 非法状态标志预清零 / illegal state flag pre-cleared
_bVacOk       := FALSE;                        // 真空到位判据预置 FALSE / vacuum reached preset FALSE
_bQualified   := FALSE;                        // 合格判据预置 FALSE / qualified preset FALSE
_bCycleEvent  := FALSE;                        // 循环事件预置 FALSE / cycle event preset FALSE

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（循环计数与失败锁存从零起）
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState      := E_DL_PurgeState.eIdle;     // 相位待机 / phase idle
    _uCycleAcc   := 0;                         // 循环计数清零 [次] / cycle count cleared
    _uEvacRetry  := 0;                         // 重试计数清零 [次] / retry counter cleared
    _bFailedAcc  := FALSE;                     // 失败锁存清零 / failure latch cleared
    _bEvacBreak  := TRUE;                      // 抽真空计时从零开始 / evacuation timer starts from zero
    _bFillBreak  := TRUE;                      // 充氮计时从零开始 / fill timer starts from zero
    _bHoldBreak  := TRUE;                      // 保压计时从零开始 / hold timer starts from zero
    _bInit       := TRUE;                      // 首扫只做一次 / the first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数闸门（目标氧含量、循环数、三相时长）
 *      Parameter gate for the target, the cycle count and the three durations
 *-----------------------------------------------------------------------------*)
IF (fO2Target <> fO2Target) OR (ABS(fO2Target) > DL_VAL_LIM) OR (fO2Target <= DL_O2_MIN) THEN
    _bParamBad := TRUE;                        // 目标氧含量非法 / target oxygen illegal
END_IF
IF uMaxCycles <= DL_CYCLE_MIN THEN
    _bParamBad := TRUE;                        // 循环数为 0，置换无从进行 / zero cycles, nothing to run
END_IF
IF (TIME_TO_DINT(tEvac) <= 0) OR (TIME_TO_DINT(tFill) <= 0) OR (TIME_TO_DINT(tHold) <= 0) THEN
    _bParamBad := TRUE;                        // 任一相时长为 0 / a phase duration is zero
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜氧分析仪有效性与真空判据（分析仪坏掉时禁止放行）
 *      Analyser validity and the vacuum test
 *-----------------------------------------------------------------------------*)
IF NOT bO2SensorOk THEN
    _bSensorBad := TRUE;                       // 分析仪无效 / the analyser is invalid
END_IF
_bVacOk := (fVacMeas <= fVacOk);               // 真空到位：读数不高于阈值（越负越真空） / reached when the reading is deep enough

(*------------------------------------------------------------------------------
 * 段 5｜三只计时器无条件刷新（R40：CASE 之外每拍必调；**一相一只，绝不共用**）
 *      Three timers refreshed unconditionally, one per phase, never shared
 *-----------------------------------------------------------------------------*)
fbEvac(IN := (_eState = E_DL_PurgeState.eEvacuate) AND (NOT _bEvacBreak), PT := tEvac); // 抽真空相计时
_bEvacBreak := FALSE;                          // 断输入拍在调用后自清 / break self-cleared after the call

fbFill(IN := (_eState = E_DL_PurgeState.eFillN2) AND (NOT _bFillBreak), PT := tFill); // 充氮相计时
_bFillBreak := FALSE;                          // 断输入拍在调用后自清 / break self-cleared after the call

fbHold(IN := (_eState = E_DL_PurgeState.eHoldVerify) AND (NOT _bHoldBreak), PT := tHold); // 保压取样相计时
_bHoldBreak := FALSE;                          // 断输入拍在调用后自清 / break self-cleared after the call

(*------------------------------------------------------------------------------
 * 段 6｜相位机（只做迁移；阀输出在段 7）
 *      Phase machine, transitions only, the valve commands are set in segment seven
 *-----------------------------------------------------------------------------*)
IF bAbort THEN
    (* 中止：任意拍生效，先清输出（段 1 已清）再回待机，不排队不回退 *)
    (* Abort takes effect on any scan, no queuing and no rollback *)
    _eState     := E_DL_PurgeState.eIdle;
    _uEvacRetry := 0;                          // 重试计数清零 [次] / retry counter cleared
    _bEvacBreak := TRUE;                       // 三相计时全部重启 / every timer restarts
    _bFillBreak := TRUE;
    _bHoldBreak := TRUE;
ELSIF _bParamBad THEN
    _eState := E_DL_PurgeState.eFault;         // 参数非法：转故障 / illegal parameters go to fault
    _bEvacBreak := TRUE;                       // 计时重启，避免把故障期算进相时长 / timers restart
    _bFillBreak := TRUE;
    _bHoldBreak := TRUE;
ELSIF _bSensorBad THEN
    _eState := E_DL_PurgeState.eFault;         // 分析仪无效：转故障，三阀全关（段 7 自然全关） / invalid analyser
    _bEvacBreak := TRUE;                       // 计时重启 / timers restart
    _bFillBreak := TRUE;
    _bHoldBreak := TRUE;
ELSE
    CASE _eState OF

        E_DL_PurgeState.eIdle:                 // 待机：启动即从第一个循环开始
            IF bStart THEN
                _uCycleAcc  := 0;              // 新任务循环数从零起 [次] / a new job starts at zero cycles
                _uEvacRetry := 0;              // 重试计数清零 [次] / retry counter cleared
                _bFailedAcc := FALSE;          // 失败锁存清零 / failure latch cleared
                _bEvacBreak := TRUE;           // 抽真空计时从零开始 / the evacuation timer starts from zero
                _eState     := E_DL_PurgeState.eEvacuate; // 进抽真空相 / enter evacuation
            END_IF

        E_DL_PurgeState.eEvacuate:             // 抽真空：时间到且真空到位才转充氮
            IF NOT bStart THEN
                _eState := E_DL_PurgeState.eIdle; // 启动撤销，回待机（等价于中止） / start dropped
            ELSIF fbEvac.Q AND _bVacOk THEN
                _uEvacRetry := 0;              // 本次抽真空成功，重试计数清零 / evacuation succeeded
                _bFillBreak := TRUE;           // 充氮计时从零开始（相转出断输入） / the fill timer starts from zero
                _eState     := E_DL_PurgeState.eFillN2; // 进充氮相 / enter the fill phase
            ELSIF fbEvac.Q THEN
                _uEvacRetry := _uEvacRetry + 1; // 时间到但真空未达：重试累计 / elapsed without vacuum, retry counted
                _bEvacBreak := TRUE;           // 抽真空计时重启 / the evacuation timer restarts
                IF _uEvacRetry >= DL_EVAC_RETRY THEN
                    _bFailedAcc := TRUE;       // 真空建立失败：按失败锁定处理 / the vacuum cannot be established
                    _eState     := E_DL_PurgeState.eFailed;
                END_IF
            END_IF

        E_DL_PurgeState.eFillN2:               // 充氮：时间到即转保压取样
            IF NOT bStart THEN
                _eState := E_DL_PurgeState.eIdle; // 启动撤销，回待机 / start dropped
            ELSIF fbFill.Q THEN
                _bHoldBreak := TRUE;           // 保压计时从零开始（相转出断输入） / the hold timer starts from zero
                _eState     := E_DL_PurgeState.eHoldVerify; // 进保压取样相 / enter hold and verify
            END_IF

        E_DL_PurgeState.eHoldVerify:           // 保压取样：窗满读氧含量
            IF NOT bStart THEN
                _eState := E_DL_PurgeState.eIdle; // 启动撤销，回待机 / start dropped
            ELSIF fbHold.Q THEN
                _bCycleEvent := TRUE;          // 单循环结束事件（段 7 消费） / the cycle finished
            END_IF

        E_DL_PurgeState.eCycleDone:            // 单循环结束（单拍相）：回抽真空
            _bEvacBreak := TRUE;               // 抽真空计时从零开始（相转出断输入） / the evacuation timer restarts
            _uEvacRetry := 0;                  // 重试计数按循环清零 [次] / retries reset per cycle
            _eState     := E_DL_PurgeState.eEvacuate; // 进下一循环 / next cycle
        E_DL_PurgeState.eComplete:             // 合格：等启动撤销才可复位
            IF NOT bStart THEN
                _eState := E_DL_PurgeState.eIdle; // 启动撤销，回待机 / back to idle once the start drops
            END_IF

        E_DL_PurgeState.eFailed:               // 失败锁定：等启动撤销才可复位
            IF NOT bStart THEN
                _eState := E_DL_PurgeState.eIdle; // 启动撤销，回待机 / back to idle once the start drops
            END_IF

        E_DL_PurgeState.eFault:                // 故障：参数与分析仪恢复且未启动才回待机
            IF (NOT _bParamBad) AND (NOT _bSensorBad) AND (NOT bStart) THEN
                _eState := E_DL_PurgeState.eIdle; // 原因消失 / the cause is gone
            END_IF

        ELSE
            _bIllegal := TRUE;                 // 标记非法状态 / flag the illegal state
            _bEvacBreak := TRUE;               // 三相计时重启 / every timer restarts
            _bFillBreak := TRUE;
            _bHoldBreak := TRUE;
            _eState := E_DL_PurgeState.eIdle;  // 回安全态 / back to the safe state
        END_CASE
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜单循环判定与阀输出（互斥：段 1 已全清，此处最多置一路）
 *      Cycle verdict and valve commands, at most one is set here
 *-----------------------------------------------------------------------------*)
IF _bCycleEvent THEN
    _bQualified := (fO2Meas <= fO2Target);     // 氧含量达目标即合格 [布尔] / qualified when the oxygen reaches the target
    IF _bQualified THEN
        _eState := E_DL_PurgeState.eComplete;  // 合格：放行 / qualified, release
    ELSE
        IF _uCycleAcc < DL_CNT_MAX THEN
            _uCycleAcc := _uCycleAcc + 1;      // 循环数 +1（饱和不回绕） [次] / cycle count incremented
        END_IF
        IF _uCycleAcc >= uMaxCycles THEN
            _bFailedAcc := TRUE;               // 循环耗尽：失败锁定 / cycles exhausted, latch the failure
            _eState     := E_DL_PurgeState.eFailed;
        ELSE
            _eState := E_DL_PurgeState.eCycleDone; // 进下一循环 / next cycle
        END_IF
    END_IF
    _bHoldBreak := TRUE;                       // 离开保压相，计时重启 / leave hold, restart the timer
END_IF

CASE _eState OF
    E_DL_PurgeState.eEvacuate:                 // 抽真空阀开 / vacuum valve open
        bVacValveCmd := TRUE;
    E_DL_PurgeState.eFillN2:                   // 氮气阀开 / nitrogen valve open
        bN2ValveCmd := TRUE;
    E_DL_PurgeState.eComplete:                 // 合格后放空泄压放行 / vent only when qualified
        bVentValveCmd := TRUE;
    ELSE
        bVacValveCmd  := FALSE;                // 其余相：显式重申全关（R72 双路径） / explicitly re-asserted closed
        bN2ValveCmd   := FALSE;
        bVentValveCmd := FALSE;
END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜码位优先级链与出口
 *      Code priority chain and exit
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    _bFailedAcc := TRUE;                       // 非法状态按失败锁定处理 / an illegal state latches a failure
END_IF

IF _bParamBad THEN
    eErr   := 16#0005_0311;                    // 故障级：置换参数非法 / fault: purge parameters illegal
    bError := TRUE;                            // 置故障标志 / raise the fault flag
    _eState := E_DL_PurgeState.eIdle;          // 明确回待机（参数非法不谈顺控） / back to idle
ELSIF _bSensorBad THEN
    eErr   := 16#0005_0312;                    // 故障级：氧分析仪无效，禁止放行 / fault: analyser invalid, release forbidden
    bError := TRUE;                            // 置故障标志 / raise the fault flag
    bVacValveCmd  := FALSE;                    // 三阀显式全关（禁止放行的实际动作） / all valves explicitly closed
    bN2ValveCmd   := FALSE;
    bVentValveCmd := FALSE;
ELSIF (_eState = E_DL_PurgeState.eFailed) OR _bFailedAcc THEN
    eErr   := 16#0005_0313;                    // 故障级：循环耗尽未达标（兜底与真空失败复用） / fault: cycles exhausted
    bError := TRUE;                            // 置故障标志 / raise the fault flag
ELSIF _bIllegal THEN
    eErr   := 16#0005_0313;                    // 故障级：非法状态兜底（同一码，R90） / fault: illegal state fallback
    bError := TRUE;                            // 置故障标志 / raise the fault flag
ELSIF _eState = E_DL_PurgeState.eComplete THEN
    eErr   := 16#0005_01DF;                    // 信息级：取样窗内氧含量已达目标 / informational: the target was reached
ELSIF _bCycleEvent THEN
    eErr   := 16#0005_01DE;                    // 信息级：单循环未达标，进入下一循环 / informational: next cycle
END_IF

uCycleDone := _uCycleAcc;                      // 已完成循环数出口 [次] / completed cycles outlet
bDone      := (_eState = E_DL_PurgeState.eComplete); // 放行出口：仅合格相为真 / release outlet
bFailed    := (_eState = E_DL_PurgeState.eFailed) OR _bFailedAcc; // 失败出口 / failure outlet

IF bError OR _bSensorBad THEN
    bValid := FALSE;                           // 故障级或分析仪无效：输出不可用 / fault or invalid analyser: unusable
ELSIF _bParamBad THEN
    bValid := FALSE;                           // 参数非法：输出不可用 / illegal parameters: unusable
ELSE
    bValid := TRUE;                            // 输出可用（顺控进行中亦可用） / usable, also while running
END_IF

END_FUNCTION_BLOCK
