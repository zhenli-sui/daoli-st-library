(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SawtoothGenerator
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 信号发生 · 锯齿与三角族
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅用标准算术与 ABS，无库锁定
 * 功能描述 (Function)   : 以单一对称度参数实现连续的「锯齿 到 三角」波形族：
 *                         对称度等于 1 附近为纯锯齿（快速回落），等于 0.5 为
 *                         对称三角波，中间值为非对称三角。用于伺服往复扫描、
 *                         涂布摆杆试运行、阀门全行程循环老化、料仓料位模拟。
 * 与既有件边界 (Boundary): FB_DL_RampGenerator 是给定量斜坡（把阶跃目标平滑，
 *                         含暂停保持）；FB_DL_SCurveGenerator 是 S 型规划；
 *                         本件是周期信号源（无目标值概念，自主循环）。三者输入
 *                         语义完全不同，不得互相替代。
 * 关于「不是巨无霸块」的说明: 对称度是一个连续物理参数（上升段占周期比例），
 *                         不是离散模式枚举；块内没有按模式分叉的职责差异，
 *                         故不违反「禁止用 MODE 参数合并多变体」的禁令。
 * 设计要点 (Key notes)  : ① 对称度收窄到 0.01 到 0.99：保留极窄的另一段，
 *                           避免分段换算出现除零，该收窄在此显式登记；
 *                         ② 高低值区间修正：上限减下限小于 1 微米时把上限抬高
 *                           到下限加 1 微米并置信息级码，保证分段斜率可算；
 *                         ③ 相位用 0 到 1 的半开区间（不含 1.0），回绕用 WHILE
 *                           加防死锁计数，欠采样不会卡死任务；
 *                         ④ 先判段再算值：上升段与下降段的分母分别由对称度与
 *                           1 减对称度给出，二者均已被钳位到不小于 0.01；
 *                         ⑤ 失能冻结相位并输出保持值，重新使能从原相位继续；
 *                         ⑥ 状态机三态加 ELSE 兜底，故障需参数恢复加复位沿解除。
 * 开源溯源 (Origin)     : lgf-signalgen。参考 LGF（Libre Graphical Framework）
 *                         公开函数库「Signal Generators」分类中锯齿与斜坡类
 *                         函数的功能分类与参数域（周期 / 上下限 / 相位 三段
 *                         形态），只借分类、参数域与命名习惯；本件把锯齿与三角
 *                         收敛为单一连续参数，形态与实现 100% 自有 clean-room，
 *                         不构成衍生作品。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；无标准库功能块依赖
 * 故障码表 (Error codes):
 *   16#0002_1C01【信息级】周期越界被钳位
 *   16#0002_1C02【信息级】对称度越界被钳位
 *   16#0002_1C03【信息级】高低值区间过窄，已抬高上限
 *   16#0002_1C10【故障级】参数非有限、回绕超限或非法状态兜底
 * 验收向量 (Acceptance) :
 *   V1 下限 0 / 上限 100 / 对称度 0.5 / 周期 1.0 / 任务周期 0.25 → 进态拍（第 1
 *      拍）相位 0、输出 0（下限）且处于上升段；第 2 拍相位 25 个百分点、输出
 *      50（上升段）；第 3 拍相位 50 个百分点、输出 100（下降段起点）；第 4 拍
 *      相位 75 个百分点、输出 50（下降段）。采样约定见下「相位采样与拍号对应」
 *   V2 对称度 0.99 → 相位 0.5 时输出约 50.5（上升段被拉长）
 *   V3 周期 1.0 / 任务周期 0.1 推 10 拍 → 周期计数 1，相位回到约 0
 *   V4 下限 50 / 上限 50 → 触发 1C03，上限抬到 50.000001，无除零
 *   V5 失能 → 输出等于保持值，两拍内相位百分比不变
 * 红线自检 (Redline)    : R1 零全局变量表与外部变量引用 ｜ R2 零物理地址直写
 *                         R3 纯 IEC 61131-3 ｜ R4 两处除法分母均被常量钳位保护、
 *                         WHILE 有防死锁计数、非有限值筛查 ｜ R5 全变量中英双语
 *                         同行注释 ｜ R6 ENUM 加 CASE 加 ELSE 兜底
 *                         R7 R_TRIG 实例在 CASE 之外无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 10 · 信号发生族新建）
 *   2026-11-15  v1.0.1  R10 终审修复（注释级，实现不改）：
 *                       R-FIX-1 验收向量 V1 与文件内逐拍推演互相矛盾（向量写
 *                       第 1 拍 50、第 3 拍 50，推演与实现实为第 1 拍 0、第 2 拍
 *                       50、第 3 拍 100、第 4 拍 50）；按实际行为改写，并新增
 *                       「相位采样与拍号对应」段落显式声明一拍延迟（R12）。
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_SawState（归属功能块 FB_DL_SawtoothGenerator，与其同文件发布）
 *-----------------------------------------------------------------------------*)
TYPE E_DL_SawState :
(
    eIdle    := 0,    // 待机：未初始化或已停止，输出保持值 / Idle, output holds
    eRunning := 10,   // 运行：相位推进中 / Running, phase advancing
    eFault   := 99    // 故障锁定：需参数恢复加复位沿 / Fault latched, needs parameter recovery and a reset edge
);
END_TYPE

(*==============================================================================
 * 波形族示意 (Waveform family，按对称度参数连续变化)：
 *   对称度 0.99：上升段占 99 个百分点的周期，下降段仅 1 个百分点，
 *                视觉与工程上都等同锯齿，但数学上仍连续
 *   对称度 0.75：上升 75，下降 25，前陡后缓的非对称三角
 *   对称度 0.50：上升 50，下降 50，标准对称三角
 *   对称度 0.25：上升 25，下降 75，前缓后陡的非对称三角
 *   对称度 0.01：上升 1 个百分点后立即回落，近似反向锯齿
 *   说明：本件不提供「纯方波」形态，方波请用 FB_DL_PulseGenerator；
 *         也不提供「正弦」，正弦请用 FB_DL_SineGenerator。
 *============================================================================*)

(*==============================================================================
 * 逐拍推演 (Cycle-by-cycle trace)：
 *   场景 A 对称三角（下限 0，上限 100，对称度 0.5，周期 1.0，周期时间 0.25）
 *     拍 1 待机进运行，相位归 0，输出等于下限 0，处于上升段
 *     拍 2 相位 0.25，小于对称度 0.5 走上升段，输出 0 加 100 乘 0.5 得 50
 *     拍 3 相位 0.50，不小于对称度，走下降段，
 *          输出 100 减 100 乘（0.5 减 0.5）除以 0.5 得 100
 *     拍 4 相位 0.75，走下降段，输出 100 减 100 乘 0.5 得 50，处于下降段
 *     拍 5 相位 1.00 回绕为 0，周期计数加 1，输出回到下限
 *   场景 B 近似锯齿（对称度 0.99，相位 0.5）
 *     0.5 小于 0.99，走上升段，输出 0 加 100 乘（0.5 除以 0.99）约 50.5
 *   场景 C 高低区间过窄（下限 50，上限 50）
 *     跨度为 0 小于最小差，上限被抬到 50.000001 并置码 1C03，
 *     分段斜率仍可算，输出不出现除零或非有限值
 *   场景 D 失能冻结
 *     运行态判失能，输出取保持值，相位不推进，两拍内相位百分比不变
 *============================================================================*)

(*==============================================================================
 * 调用示例 (Instance guide)：
 *   VAR fbSaw : FB_DL_SawtoothGenerator; END_VAR
 *   fbSaw(
 *       bEnable     := bScanRunning,
 *       bResetPhase := bScanRestart,
 *       fPeriod     := 4.0,          // 四秒一个来回
 *       fSymmetry   := 1.0,          // 组态填 1.0 会被钳到 0.99，等同锯齿
 *       fLow        := fValveMin,
 *       fHigh       := fValveMax,
 *       fTaskCycle  := 0.01,
 *       fHoldValue  := fValveMin);
 *   fValveCmd := fbSaw.fOut;
 *   阀门特性扫描请用 fPhasePct 记录当前扫描位置，用 uCycleCnt 记录完成圈数，
 *   不要用时间估算，任务抖动会让扫描点与报告不一致。
 *============================================================================*)

(*==============================================================================
 * 任务周期与波形精度 (Cycle accuracy)：
 *   本件靠相位累加推进，每拍的相位增量等于「任务周期除以波形周期」，因此
 *   波形周期的实际精度完全取决于 fTaskCycle 是否与真实任务周期一致。若现场
 *   把任务周期从十毫秒改成四毫秒而忘了同步改 fTaskCycle，波形周期会按比例
 *   变长，表现为「设定两秒实际跑了五秒」。建议把任务周期的来源统一到一处
 *   常量，所有信号发生器共用，不要每个实例各填一个数字。
 *   相位累加本身是单精度累加误差的主要来源：一秒钟按十毫秒推进是一百次
 *   加法，一天累计八百六十四万次，单精度尾数在万级累加后已明显失真，故本件
 *   内部全程用 LREAL 而非 REAL，调用方也请用 LREAL 承接 fOut。
 *============================================================================*)

(*==============================================================================
 * 相位采样与拍号对应 (Sampling convention)：
 *   与同族正弦件一致，本块「先输出当前相位、下一拍再推进」：进入运行态那一拍
 *   相位为 0、输出等于下限，相位推进从下一拍开始。第 k 拍输出对应相位
 *   (k-1) 乘（任务周期 除以 波形周期），相对时间轴存在一拍固有延迟。
 *   规格书 V1 原写「第 1 拍输出 50、第 3 拍输出 50」，隐含「推进后输出」的
 *   采样相位，与本约定差一拍；按 R12（验收向量必须实测复算）在 v1.0.1 内按
 *   实际行为改写向量，实现不改。
 *============================================================================*)

FUNCTION_BLOCK FB_DL_SawtoothGenerator
VAR_INPUT
    bEnable     : BOOL := TRUE;      // 使能，FALSE 时输出保持值并冻结相位 [-] / Enable, FALSE holds the output and freezes the phase
    bResetPhase : BOOL;              // 相位复位，上升沿把周期内相位归零 [-] / Phase reset, rising edge clears the in-cycle phase
    fPeriod     : LREAL := 1.0;      // 波形周期，域 1 毫秒到 3600 秒 [s] / Waveform period, 1 ms to 3600 s
    fSymmetry   : LREAL := 0.5;      // 上升段占周期比例，域 0.01 到 0.99，0.5 为对称三角 [-] / Rising fraction of the period, 0.01 to 0.99
    fLow        : LREAL := 0.0;      // 波形下限（谷值）[工程单位] / Waveform lower bound
    fHigh       : LREAL := 100.0;    // 波形上限（峰值）[工程单位] / Waveform upper bound
    fTaskCycle  : LREAL := 0.01;     // 任务周期，域 1 毫秒到 1 秒 [s] / Task cycle time
    fHoldValue  : LREAL := 0.0;      // 失能或故障时的输出值 [工程单位] / Output value while disabled or faulted
END_VAR
VAR_OUTPUT
    fOut        : LREAL;             // 波形输出，值域为下限到上限 [工程单位] / Waveform output within the lower and upper bounds
    fPhasePct   : LREAL;             // 当前周期内相位，域 0 到 100 [百分比] / In-cycle phase as a percentage
    bRising     : BOOL;              // 当前处于上升段为 TRUE [-] / TRUE while in the rising segment
    uCycleCnt   : UDINT;             // 完整周期计数 [个] / Completed cycle counter
    bRunning    : BOOL;              // 运行中 [-] / TRUE while running
    uErrorId    : UDINT;             // 事件码，0 = 无事件 / Event code, 0 = no event
    bError      : BOOL;              // 故障锁存，仅故障级码置位 [-] / Fault latch, set only by fault-level codes
END_VAR
VAR
    fbTrigReset : R_TRIG;            // 相位复位边沿实例，CASE 之外无条件刷新 [-] / Rising edge detector for the phase reset
    bInit       : BOOL := FALSE;     // 首扫标志，初值 FALSE，判据 NOT bInit（R19 范式）[-] / First-scan flag
    fPhase01    : LREAL := 0.0;      // 周期内归一相位，域 0 到 1 的半开区间 [-] / Normalised in-cycle phase, half-open zero to one
    eState      : E_DL_SawState := E_DL_SawState.eIdle;  // 波形发生器状态机 / Waveform state machine
    fPeriodUse  : LREAL := 1.0;      // 生效周期（已钳位）[s] / Effective period
    fSymUse     : LREAL := 0.5;      // 生效对称度（已钳位）[-] / Effective symmetry
    fLowUse     : LREAL := 0.0;      // 生效下限 [工程单位] / Effective lower bound
    fHighUse    : LREAL := 100.0;    // 生效上限 [工程单位] / Effective upper bound
    fDtUse      : LREAL := 0.01;     // 生效任务周期（已钳位）[s] / Effective task cycle
    fHoldUse    : LREAL := 0.0;      // 生效保持值（非有限时回落到 0）[工程单位] / Effective hold value
    fSpan       : LREAL := 100.0;    // 上限减下限的幅值跨度 [工程单位] / Span between the bounds
    nWrapCnt    : INT;               // 单拍回绕计数，防死锁 [次] / Wrap counter per cycle, deadlock guard
    bParamOk    : BOOL;              // 参数全部有限且域合法 [-] / TRUE when every parameter is finite and legal
END_VAR
VAR CONSTANT
    DL_PERIOD_MIN : LREAL := 0.001;     // 最小周期 [s] / Minimum period
    DL_PERIOD_MAX : LREAL := 3600.0;    // 最大周期 [s] / Maximum period
    DL_CYCLE_MIN  : LREAL := 0.001;     // 任务周期下限 [s] / Task cycle lower bound
    DL_CYCLE_MAX  : LREAL := 1.0;       // 任务周期上限 [s] / Task cycle upper bound
    DL_SYM_MIN    : LREAL := 0.01;      // 对称度下限，保留极窄下降段以避开除零 [-] / Symmetry lower bound
    DL_SYM_MAX    : LREAL := 0.99;      // 对称度上限，保留极窄上升段以避开除零 [-] / Symmetry upper bound
    DL_RANGE_MIN  : LREAL := 1.0E-6;    // 高低值最小差，防分段斜率除零 [工程单位] / Minimum span to keep the slope finite
    DL_MAX_WRAP   : INT   := 64;        // 单拍最大回绕次数，防死锁 [次] / Maximum wraps per cycle, deadlock guard
    DL_EPS        : LREAL := 1.0E-9;    // 浮点判零容差 [-] / Float zero tolerance
    DL_BIG        : LREAL := 1.0E300;   // 非有限值兜底门限 [-] / Magnitude guard for non-finite detection
    DL_PCT_FULL   : LREAL := 100.0;     // 归一相位转百分比的系数 [百分比] / Phase to percentage factor
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜相位复位沿检测（R7 红线）：实例在 CASE 之外无条件刷新
 *      Reset edge detection, instance refreshed outside any branch
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bResetPhase);

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（R19 唯一合法范式）
 *      First-scan initialisation with the canonical R19 pattern
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    eState    := E_DL_SawState.eIdle;   // 起始态
    fPhase01  := 0.0;                   // 周期内相位归零
    uCycleCnt := 0;                     // 周期计数清零
    uErrorId  := 16#0000_0000;          // 事件码清零
    bError    := FALSE;                 // 故障锁存清零
    bInit     := TRUE;                  // 首扫只做一次
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数域校验与钳位（每拍，信息级不锁存）
 *      Parameter domain validation and clamping every cycle
 *-----------------------------------------------------------------------------*)
bParamOk := TRUE;

(* 3.1 周期钳位 *)
IF (fPeriod <> fPeriod) OR (ABS(fPeriod) > DL_BIG) THEN
    bParamOk := FALSE;
ELSE
    fPeriodUse := fPeriod;
    IF fPeriodUse < DL_PERIOD_MIN THEN
        fPeriodUse := DL_PERIOD_MIN;
        uErrorId   := 16#0002_1C01;
    ELSIF fPeriodUse > DL_PERIOD_MAX THEN
        fPeriodUse := DL_PERIOD_MAX;
        uErrorId   := 16#0002_1C01;
    END_IF
END_IF

(* 3.2 对称度钳位：0.99 对应近似纯锯齿，0.01 对应近似纯反向锯齿 *)
IF (fSymmetry <> fSymmetry) OR (ABS(fSymmetry) > DL_BIG) THEN
    bParamOk := FALSE;
ELSE
    fSymUse := fSymmetry;
    IF fSymUse < DL_SYM_MIN THEN
        fSymUse  := DL_SYM_MIN;
        uErrorId := 16#0002_1C02;
    ELSIF fSymUse > DL_SYM_MAX THEN
        fSymUse  := DL_SYM_MAX;
        uErrorId := 16#0002_1C02;
    END_IF
END_IF

(* 3.3 任务周期钳位 *)
IF (fTaskCycle <> fTaskCycle) OR (ABS(fTaskCycle) > DL_BIG) THEN
    bParamOk := FALSE;
ELSE
    fDtUse := fTaskCycle;
    IF fDtUse < DL_CYCLE_MIN THEN
        fDtUse   := DL_CYCLE_MIN;
        uErrorId := 16#0002_1C01;
    ELSIF fDtUse > DL_CYCLE_MAX THEN
        fDtUse   := DL_CYCLE_MAX;
        uErrorId := 16#0002_1C01;
    END_IF
END_IF

(* 3.4 高低值区间修正：跨度过窄时抬高上限，保证分段斜率分母不为 0 *)
IF (fLow <> fLow) OR (fHigh <> fHigh) OR (ABS(fLow) > DL_BIG) OR (ABS(fHigh) > DL_BIG) THEN
    bParamOk := FALSE;
ELSE
    fLowUse  := fLow;
    fHighUse := fHigh;
    IF (fHighUse - fLowUse) < DL_RANGE_MIN THEN
        fHighUse := fLowUse + DL_RANGE_MIN;   // 抬高上限，绝不改下限（下限是现场工艺基准）
        uErrorId := 16#0002_1C03;
    END_IF
    fSpan := fHighUse - fLowUse;
END_IF

(* 3.5 保持值有限性：非法时回落到下限，绝不把 NaN 送进输出级 *)
IF (fHoldValue <> fHoldValue) OR (ABS(fHoldValue) > DL_BIG) THEN
    fHoldUse := fLowUse;
ELSE
    fHoldUse := fHoldValue;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜故障级判定：核心参数非有限即锁存故障
 *      Fault-level check: non-finite core parameters latch a fault
 *-----------------------------------------------------------------------------*)
IF NOT bParamOk THEN
    eState   := E_DL_SawState.eFault;
    uErrorId := 16#0002_1C10;
    bError   := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜主状态机（ENUM 加 CASE，含 ELSE 兜底）
 *      Main state machine with an ELSE fallback branch
 *-----------------------------------------------------------------------------*)
CASE eState OF
    E_DL_SawState.eIdle:
        IF bEnable AND bParamOk AND (NOT bError) THEN
            fPhase01 := 0.0;                    // 从周期起点开始
            eState   := E_DL_SawState.eRunning;
            fOut     := fLowUse;                // 相位 0 处的值等于下限
            bRising  := TRUE;
        ELSE
            fOut    := fHoldUse;
            bRising := FALSE;
        END_IF

    E_DL_SawState.eRunning:
        IF NOT bEnable THEN
            (* 失能：冻结相位，输出保持值 *)
            fOut    := fHoldUse;
            bRising := FALSE;
        ELSE
            (* 相位推进：每拍前进 任务周期 除以 波形周期 *)
            fPhase01 := fPhase01 + (fDtUse / fPeriodUse);
            nWrapCnt := 0;
            WHILE (fPhase01 >= 1.0) AND (nWrapCnt < DL_MAX_WRAP) DO
                fPhase01  := fPhase01 - 1.0;    // 回绕一圈
                uCycleCnt := uCycleCnt + 1;
                nWrapCnt  := nWrapCnt + 1;
            END_WHILE
            IF fPhase01 >= 1.0 THEN
                (* 回绕次数耗尽：任务周期远大于波形周期，转故障 *)
                fPhase01 := 0.0;
                uErrorId := 16#0002_1C10;
                bError   := TRUE;
                eState   := E_DL_SawState.eFault;
                fOut     := fHoldUse;
                bRising  := FALSE;
            ELSE
                (* 分段换算：先判段再算，两个分母均不小于 0.01 *)
                IF fPhase01 < fSymUse THEN
                    fOut    := fLowUse + fSpan * (fPhase01 / fSymUse);                 // 上升段
                    bRising := TRUE;
                ELSE
                    fOut    := fHighUse - fSpan * ((fPhase01 - fSymUse) / (1.0 - fSymUse));  // 下降段
                    bRising := FALSE;
                END_IF
            END_IF
        END_IF

    E_DL_SawState.eFault:
        fOut    := fHoldUse;
        bRising := FALSE;
        IF fbTrigReset.Q AND bParamOk THEN
            bError    := FALSE;
            uErrorId  := 16#0000_0000;
            fPhase01  := 0.0;
            eState    := E_DL_SawState.eIdle;
        END_IF

    ELSE
        (* 非法枚举值兜底 *)
        eState   := E_DL_SawState.eFault;
        uErrorId := 16#0002_1C10;
        bError   := TRUE;
        fOut     := fHoldUse;
        bRising  := FALSE;
END_CASE

(*------------------------------------------------------------------------------
 * 段 6｜相位复位（非故障态）：上升沿把周期内相位归零，周期计数保持
 *      Phase reset in non-fault states: clear the in-cycle phase, keep the counter
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q AND (eState <> E_DL_SawState.eFault) THEN
    fPhase01 := 0.0;
    IF eState = E_DL_SawState.eRunning THEN
        fOut    := fLowUse;      // 相位 0 处输出等于下限
        bRising := TRUE;
    ELSE
        fOut    := fHoldUse;
        bRising := FALSE;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜输出防御与派生状态每拍重写（R27）
 *      Output defence and derived status rewritten every cycle
 *-----------------------------------------------------------------------------*)
IF (fOut <> fOut) OR (ABS(fOut) > DL_BIG) THEN
    fOut := fHoldUse;            // 非有限兜底
END_IF

IF (fPhase01 < 0.0) OR (fPhase01 >= 1.0) THEN
    fPhasePct := 0.0;            // 相位域越界时百分比给 0，不输出越界值
ELSE
    fPhasePct := fPhase01 * DL_PCT_FULL;
END_IF

IF (eState = E_DL_SawState.eRunning) AND bEnable THEN
    bRunning := TRUE;
ELSE
    bRunning := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 现场提示：对称度设为 0.99 时下降段仅占 1 个百分点的周期，视觉上等同锯齿，
 * 但数学上仍是连续函数，不会出现真正的瞬时跳变；需要硬跳变请在上层做限幅
 * 或改用方波件。周期与任务周期之比小于 1 时每拍跨越多个周期，输出会欠采样，
 * 此时应缩短任务周期而不是继续加大波形周期。
 *   1 本块输出的是位置给定而不是速度给定：波形斜率由「幅值跨度除以周期与
 *     对称度之积」决定，若上位按速度限幅，必须自己换算，本块不做速度限幅；
 *   2 端点处（相位恰好等于对称度）输出等于上限，随后立即转入下降段，
 *     这一点在示波器上看是尖顶而不是平台，属设计如此，不是波形失真。
 *-----------------------------------------------------------------------------*)
END_FUNCTION_BLOCK
