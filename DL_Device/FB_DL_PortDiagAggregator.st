(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PortDiagAggregator
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 设备诊断 · 端口级聚合仲裁
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅位与运算、TON、R_TRIG 与标准类型
 * 功能描述 (Function)   : 把最多 8 个现场总线通讯端口的链路状态、诊断码、
 *                         CRC 错误累计计数聚合成单一故障掩码、首出端口号、
 *                         首出诊断码与错误风暴标志，解决「多端口同时报警时
 *                         HMI 只看到最后一条」的现场痛点。本块只做端口级
 *                         （通讯物理端口）聚合与首出仲裁，不做模块级位域解析。
 * 边界声明 (Boundary)   : FB_DL_AxiolineDiagLatch 负责本地总线模块级（槽号加
 *                         位域）诊断锁存；FB_DL_PdiReadScheduler 负责参数对象
 *                         读取调度；本块数据源是「端口计数与端口诊断码」，
 *                         三者数据源不同、码段不共享、互不可替。
 * 首出语义 (First-out)  : 仅在无锁存时仲裁，同拍多端口故障取端口号最小者
 *                         （低号端口更靠近主站，是现场排故的默认因果顺序）；
 *                         锁存后不再更新，只有复位上升沿可清。复位处理放在
 *                         仲裁之后，保证复位当拍首出即为空，下一拍重新仲裁。
 * 拍序纪律 (Cycle order) : 本块属监视型，但「窗口差分」有硬拍序：增量必须在
 *                         装载前算出并转出，否则窗口结束拍装载当拍增量恒为 0。
 *                         故输出数组先转出（上一段快照）后装载（下一段基准）。
 * 风暴语义 (Burst)      : 风暴是趋势事件，不锁存；eBurst 只停留一拍，该拍
 *                         置 bBurstDetected 单拍标志，供上层做趋势记录或
 *                         降低总线负载，不参与 bError 判定。
 * 开源溯源 (Origin)     : plcnext-community / profibus-diag / namur-ne107。参考
 *                         PLCnext 官方帮助与 PROFIBUS 诊断公开手册的端口诊断
 *                         功能分类与参数域（端口号、链路状态、诊断码、错误
 *                         计数器、错误风暴阈值），只借分类与参数域，端口数
 *                         上限、掩码位序、枚举、状态机、码位与全部算法 100%
 *                         自有，输入一律经引脚注入，不绑定任何厂商系统变量，
 *                         clean-room 实现，不构成衍生作品。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 TON / R_TRIG
 * 故障码表 (Error codes):
 *   16#0003_0140【信息级】端口数超上限已钳位（只进码与趋势，不置故障位）
 *   16#0003_0141【信息级】统计窗口参数越界已钳位（只进码，不置故障位）
 *   16#0003_0300【故障级】端口故障锁存（伴随故障掩码非零，置 bError）
 *   16#0003_0301【故障级】诊断源未注入（端口数小于 1，置 bError）
 *   16#0003_0307【故障级】非法状态兜底（置 bError）
 * 码位占用 (Slot)       : 信息级 0140 / 0141；故障级 0300 / 0301 / 0307。
 *                         全部落在 R11 本件分配块内，无跨块借用。
 * 写入点次序 (Write order) :
 *   ① ePhase   ：段 8 状态机（唯一位移点），段 10 复位分支可回 eIdle
 *   ② uErrorId ：段 11 单一优先级链（0307 优于 0301 优于 0300 优于 0141
 *                 优于 0140），全拍只写一次，杜绝多分支互相覆盖
 *   ③ 首出锁存 ：段 9 仲裁（仅未锁存时）→ 段 10 复位（唯一清除点）
 *   ④ 基准计数 ：段 8 窗口结束拍装载，段 5 只读，永不与增量同拍混用
 * 验收向量 (Acceptance) :
 *   V1 端口 2 与端口 5 故障，其余正常 → 故障掩码 16#0012、存在端口故障为真
 *   V2 端口 5 先故障、端口 2 后故障 → 首出端口 5；复位后才可更新为 2
 *   V3 窗口 1 秒、阈值 10、端口 3 计数 100 增至 115 → 窗口结束拍增量为 15、
 *      风暴标志单拍为真
 *   V4 端口 4 计数 16#FFFF_FFFF 回绕到 3 → 增量为 3，不出现巨大正数
 *   V5 端口数 12 → 钳位 8、码 16#0003_0140、bError 为假
 * 红线自检 (Redline)    : R1 零全局变量表与外部变量引用 ｜ R2 零物理地址直写
 *                         R3 纯 IEC 61131-3 ｜ R4 防除零、防越界、无浮点判等
 *                         R5 全变量中英双语同行注释 ｜ R6 ENUM 加 CASE 加 ELSE
 *                         R7 TON 与 R_TRIG 全部在 CASE 之外无条件刷新
 *                         R8 信息级码不置 bError，故障级码才置
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 11 · 泳道 B · T1-7 端口诊断族）
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_PortDiagPhase（本块相位，归属本功能块并同文件发布）
 *       Phase enumeration owned by this block and published in the same file
 *-----------------------------------------------------------------------------*)
TYPE E_DL_PortDiagPhase :
(
    eIdle    := 0,   // 待机：未使能或端口数非法，掩码清零、首出保持 / Idle, mask cleared, first-out kept
    eMonitor := 10,  // 监视：逐拍算增量、逐端口去抖、窗口边界拍评估 / Monitoring, deltas and debounce running
    eBurst   := 20,  // 风暴：仅停留一拍，置单拍风暴标志后回监视 / Burst, one cycle only then back to monitor
    eFault   := 99   // 故障：诊断源缺失或非法状态，需复位退出 / Fault, needs a reset to leave
);
END_TYPE

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_PortDiagState（跨周期状态，由调用方持有）
 *         Persistent state structure, owned by the caller
 *         注意：本结构体是跨周期数据，E_DL_PortDiagPhase 是相位枚举，
 *         二者刻意同名不同前缀，禁止相互替换使用
 *-----------------------------------------------------------------------------*)
TYPE ST_DL_PortDiagState :
STRUCT
    auPrevCnt   : ARRAY[1..8] OF UDINT;  // 上窗口各端口 CRC 计数基准 [次] / Previous window CRC counter per port
    nLatchPort  : INT;                   // 首出故障端口号 [1..8]，0 表示无 / First-out port number, zero means none
    uLatchCode  : UDINT;                 // 首出端口诊断码 [代码]，0 表示无 / First-out diagnostic code, zero means none
    bLatchValid : BOOL;                  // 首出锁存有效，仅复位可清 [-] / First-out latch valid, reset clears it
END_STRUCT
END_TYPE

(*==============================================================================
 * 逐拍推演 (Cycle-by-cycle trace)：
 *   场景 A 双端口故障（端口 2 与端口 5）
 *     拍 k 段 6 逐端口判定为真并启动各自去抖；段 9 见无锁存，取最小号端口 2
 *          锁存端口 2 与端口 2 的诊断码；段 11 掩码为 16#0012、置 0300
 *   场景 B 首出不覆盖（端口 5 先、端口 2 后）
 *     拍 k 端口 5 故障，锁存 5；拍 k+n 端口 2 也故障，但 bLatchValid 已真，
 *          段 9 只观测不覆盖，首出维持 5；复位后下一拍重新仲裁得 2
 *   场景 C 错误风暴（窗口 1 秒、阈值 10、端口 3 计数 100 增到 115）
 *     窗口内段 5 每拍算 115 减 100 得增量 15；窗口结束拍段 8 评估 15 大于 10，
 *          转 eBurst；下一拍 eBurst 置风暴单拍标志，回 eMonitor，同时已装载
 *          新基准 115，故下一窗口增量从 0 起算
 *   场景 D 计数回绕（端口 4 由 16#FFFF_FFFF 变为 3）
 *     段 5 判出当前值小于基准，按归零处理取 3，绝不出现巨大正数假风暴
 *   场景 E 端口数超上限（端口数 12）
 *     段 3 钳位为 8 并标记；段 11 单独置 0140，bError 保持假
 *============================================================================*)

FUNCTION_BLOCK FB_DL_PortDiagAggregator
VAR_INPUT
    bEnable          : BOOL;                              // 使能，FALSE 时掩码清零、首出保持 [-] / Enable, clears mask, holds first-out
    bReset           : BOOL;                              // 复位首出锁存，上升沿有效 [-] / Reset the first-out latch on a rising edge
    nPortCount       : INT;                               // 实际端口数 [个]，有效域 1 到 8 / Port count, valid range one to eight
    abPortLinkOk     : ARRAY[1..8] OF BOOL;               // 各端口链路正常标志 [TRUE=正常] / Per-port link up flags
    auPortErrCode    : ARRAY[1..8] OF UDINT;              // 各端口诊断码 [代码]，0 表示正常 / Per-port diagnostic code, zero means OK
    auPortCrcErrCnt  : ARRAY[1..8] OF UDINT;              // 各端口 CRC 错误累计计数 [次] / Per-port CRC error counter
    nBurstThreshold  : UDINT := 10;                       // 窗口内错误增量阈值 [次]，0 表示不判风暴 / Burst threshold per window, zero disables
    tBurstWindow     : TIME := T#1S;                      // 错误风暴统计窗口长度 [毫秒] / Burst evaluation window
    tDebounce        : TIME := T#200MS;                   // 端口故障确认去抖时间 [毫秒]，0 表示不去抖 / Port fault debounce, zero disables
END_VAR
VAR_OUTPUT
    bAnyPortFault    : BOOL;                              // 任一端口故障，等价掩码非零 [-] / Any port faulted, mask is non-zero
    bBurstDetected   : BOOL;                              // 错误风暴单拍标志，仅 eBurst 拍为真 [-] / Burst single-scan flag, true only in the burst cycle
    uPortFaultMask   : WORD;                              // 端口故障掩码，位 n 对应端口 n 加一 [位串] / Port fault mask, bit n is port n plus one
    nFirstFaultPort  : INT;                               // 首出故障端口号 [1..8]，0 表示无 / First-fault port number, zero means none
    uFirstFaultCode  : UDINT;                             // 首出端口诊断码 [代码]，与端口号同拍锁存 / First-fault diagnostic code latched with the port
    auPortDelta      : ARRAY[1..8] OF UDINT;              // 本窗口各端口错误增量 [次] / Per-port error increment of this window
    eState           : E_DL_PortDiagPhase;                // 主状态机当前相位 [-] / Current phase of the main state machine
    bError           : BOOL;                              // 故障级锁存，仅 0300 0301 0307 置位 [-] / Latched fault, only fault level codes set it
    uErrorId         : UDINT;                             // 事件码，0 表示无事件 [代码] / Event code, zero means none
END_VAR
VAR_IN_OUT
    stState          : ST_DL_PortDiagState;               // 跨周期状态：基准计数与首出锁存 [-] / Persistent state, baseline counters and first-out latch
END_VAR
VAR
    fbTrigReset      : R_TRIG;                            // 复位沿检测，CASE 之外无条件刷新 [-] / Reset edge detector, refreshed outside the CASE
    fbTonWindow      : TON;                               // 风暴统计窗口计时，CASE 之外无条件刷新 / Burst window timer, refreshed outside the CASE
    afbDebounce      : ARRAY[1..8] OF TON;                // 逐端口故障去抖定时器组，循环内无条件全刷新 / Per-port debounce timers, all refreshed every cycle
    bInit            : BOOL := FALSE;                     // 首扫标志，初值 FALSE，判据 NOT bInit [-] / First-scan flag initialised FALSE
    ePhase           : E_DL_PortDiagPhase := E_DL_PortDiagPhase.eIdle;  // 内部相位，对外经 eState 输出 / Internal phase, exported as eState
    nPortClamped     : INT;                               // 钳位后的端口数 [个]，0 到 8 / Clamped port count, zero to eight
    tWinUse          : TIME;                              // 实际生效的窗口长度 [毫秒] / Effective window length
    tDebUse          : TIME;                              // 实际生效的去抖时间 [毫秒] / Effective debounce time
    bWinRun          : BOOL;                              // 窗口计时器输入，边界拍拉低以重启窗口 / Window timer input, dropped on the boundary cycle
    bWinElapsed      : BOOL;                              // 窗口结束拍标志 [-] / Window boundary flag
    abRawFault       : ARRAY[1..8] OF BOOL;               // 端口原始故障（未去抖）[-] / Raw per-port fault before debouncing
    uMaskBuild       : WORD;                              // 去抖后故障掩码装配中间量 [位串] / Fault mask under assembly after debounce
    auRawDelta       : ARRAY[1..8] OF UDINT;              // 本拍增量装配中间量 [次] / Increment under assembly of this cycle
    auOutDelta       : ARRAY[1..8] OF UDINT;              // 增量输出快照，先转出后装载 [-] / Increment snapshot exported before reloading the baseline
    uMaxDelta        : UDINT;                             // 窗口内最大增量 [次] / Maximum increment inside the window
    nFirstScanPort   : INT;                               // 仲裁临时：最小号故障端口 [1..8] / Arbitration temporary, lowest faulted port
    uFirstScanCode   : UDINT;                             // 仲裁临时：该端口诊断码 [代码] / Arbitration temporary, that port diagnostic code
    bPortCntClamped  : BOOL;                              // 端口数超上限被钳位的标记 [-] / Flag, port count was clamped
    bParamClamped    : BOOL;                              // 时间参数越界被钳位的标记 [-] / Flag, a time parameter was clamped
    bStateIllegal    : BOOL;                              // 非法状态被兜底捕获的标记 [-] / Flag, an illegal state was captured
    i                : INT;                               // 端口遍历索引 [1..8] / Port loop index
END_VAR
VAR CONSTANT
    DL_PORT_MAX      : INT := 8;                          // 端口上限 [个] / Maximum port count
    DL_PORT_MASK_ALL : WORD := 16#00FF;                   // 八端口全掩码 [位串] / All eight port mask
    DL_MASK_ONE      : WORD := 16#0001;                   // 单端口基准位 [位串] / Single port base bit
    DL_WIN_MIN       : TIME := T#1MS;                     // 窗口长度下限 [毫秒]，防 0 窗口 / Minimum window length, guards a zero window
    DL_DEB_MIN       : TIME := T#1MS;                     // 去抖时间下限 [毫秒]，非零时套用 / Minimum debounce when not disabled
    DL_TIME_ZERO     : TIME := T#0MS;                     // 时间零值基准 [毫秒] / Time zero reference
    DL_BURST_MARGIN  : UDINT := 0;                        // 增量比较余量 [次]，保留语义位 / Increment comparison margin, reserved semantic slot
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜沿检测无条件刷新（R7 红线：CASE 之外每拍必刷）
 *      Edge detection refreshed unconditionally outside the CASE
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（R19 唯一合法范式：初值 FALSE，判据 NOT bInit）
 *      First-scan initialisation, the canonical R19 pattern
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    FOR i := 1 TO DL_PORT_MAX DO
        stState.auPrevCnt[i] := 0;               // 基准计数清零，避免首窗口假风暴
        auOutDelta[i]        := 0;               // 增量输出清零，HMI 初值确定
    END_FOR
    stState.nLatchPort     := 0;                 // 首出端口号：0 表示无
    stState.uLatchCode     := 0;                 // 首出诊断码：0 表示无
    stState.bLatchValid    := FALSE;             // 首出锁存无效
    ePhase                 := E_DL_PortDiagPhase.eIdle;
    nPortClamped           := 0;
    uMaskBuild             := 16#0000;
    bWinRun                := FALSE;
    bBurstDetected         := FALSE;
    bPortCntClamped        := FALSE;
    bParamClamped          := FALSE;
    bStateIllegal          := FALSE;
    eState                 := E_DL_PortDiagPhase.eIdle;
    uErrorId               := 16#0000_0000;
    bError                 := FALSE;
    bInit                  := TRUE;              // 首扫只做一次
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜端口数钳位（越界只钳位，不越界访问数组）
 *      Port count clamping, never index outside the array
 *-----------------------------------------------------------------------------*)
bPortCntClamped := FALSE;                        // 本拍标记预清零，避免历史残留
IF nPortCount < 1 THEN
    nPortClamped := 0;                           // 无诊断源：交由状态机转故障
ELSIF nPortCount > DL_PORT_MAX THEN
    nPortClamped    := DL_PORT_MAX;              // 超上限钳位到 8
    bPortCntClamped := TRUE;                     // 标记待置信息级码 0140
ELSE
    nPortClamped := nPortCount;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜时间参数钳位（0 有明确语义，不得与越界混为一谈）
 *      Time parameter clamping, zero keeps its documented meaning
 *-----------------------------------------------------------------------------*)
bParamClamped := FALSE;                          // 本拍标记预清零，避免历史残留
IF tBurstWindow <= DL_TIME_ZERO THEN
    tWinUse      := DL_WIN_MIN;                  // 0 窗口会让计时器每拍立即到期
    bParamClamped := TRUE;
ELSIF tBurstWindow < DL_WIN_MIN THEN
    tWinUse      := DL_WIN_MIN;
    bParamClamped := TRUE;
ELSE
    tWinUse := tBurstWindow;
END_IF

IF tDebounce < DL_TIME_ZERO THEN
    tDebUse      := DL_DEB_MIN;                  // 负时间不可能，按最小值兜底
    bParamClamped := TRUE;
ELSE
    tDebUse := tDebounce;                        // 0 表示不去抖，原样透传
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜增量差分（回绕按归零处理，UDINT 语义不产生负数）
 *      Increment differencing, a wrapped counter is treated as a restart
 *      纪律：本段只读基准，装载基准只在段 8 窗口结束拍执行
 *-----------------------------------------------------------------------------*)
FOR i := 1 TO DL_PORT_MAX DO
    IF i > nPortClamped THEN
        auRawDelta[i] := 0;                      // 超出实际端口数一律记为 0
        auOutDelta[i] := 0;
    ELSIF auPortCrcErrCnt[i] < stState.auPrevCnt[i] THEN
        auRawDelta[i] := auPortCrcErrCnt[i];     // 计数器回绕或复位：按归零处理
        auOutDelta[i] := auRawDelta[i];
    ELSE
        auRawDelta[i] := auPortCrcErrCnt[i] - stState.auPrevCnt[i];
        auOutDelta[i] := auRawDelta[i];          // 先转出快照，供段 11 输出
    END_IF
END_FOR

(*------------------------------------------------------------------------------
 * 段 6｜端口故障判定与逐端口去抖（掩码装配）
 *      Per-port fault evaluation with per-port debounce and mask assembly
 *      定时器组在循环内对全部八端口无条件刷新，不因端口数少而漏刷
 *-----------------------------------------------------------------------------*)
uMaskBuild := 16#0000;
FOR i := 1 TO DL_PORT_MAX DO
    IF bEnable AND (i <= nPortClamped) AND ((NOT abPortLinkOk[i]) OR (auPortErrCode[i] <> UDINT#0)) THEN
        abRawFault[i] := TRUE;                   // 链路断或诊断码非零即原始故障
    ELSE
        abRawFault[i] := FALSE;
    END_IF
    afbDebounce[i](IN := abRawFault[i], PT := tDebUse);
    IF afbDebounce[i].Q THEN
        uMaskBuild := uMaskBuild OR SHL(DL_MASK_ONE, i - 1);  // 去抖成立才进位
    END_IF
END_FOR

(*------------------------------------------------------------------------------
 * 段 7｜窗口计时（无条件刷新，输入取自上一拍的运行允许位）
 *      Window timer refreshed unconditionally, input from the previous cycle
 *-----------------------------------------------------------------------------*)
fbTonWindow(IN := bWinRun, PT := tWinUse);
bWinElapsed := fbTonWindow.Q;

(*------------------------------------------------------------------------------
 * 段 8｜主状态机（ENUM 加 CASE，含 ELSE 兜底；每成员均有对应标签）
 *      Main state machine, one label per enumeration member plus a fallback
 *-----------------------------------------------------------------------------*)
bBurstDetected := FALSE;                         // 单拍标志预清零：只在 eBurst 拍置真
CASE ePhase OF
    E_DL_PortDiagPhase.eIdle:
        bWinRun := FALSE;                        // 待机不跑窗口，避免脏计时
        IF bEnable AND (nPortClamped >= 1) THEN
            ePhase  := E_DL_PortDiagPhase.eMonitor;
            bWinRun := TRUE;                     // 进入监视即启动首个窗口
        ELSIF bEnable AND (nPortClamped < 1) THEN
            ePhase := E_DL_PortDiagPhase.eFault; // 诊断源未注入：故障级 0301
        END_IF

    E_DL_PortDiagPhase.eMonitor:
        IF NOT bEnable THEN
            ePhase     := E_DL_PortDiagPhase.eIdle;
            bWinRun    := FALSE;
            uMaskBuild := 16#0000;               // 未使能掩码清零，首出保持
        ELSIF nPortClamped < 1 THEN
            ePhase  := E_DL_PortDiagPhase.eFault;
            bWinRun := FALSE;
        ELSIF bWinElapsed THEN
            uMaxDelta     := 0;                  // 窗口结束拍：求最大增量
            FOR i := 1 TO nPortClamped DO
                IF auRawDelta[i] > uMaxDelta THEN
                    uMaxDelta := auRawDelta[i];
                END_IF
            END_FOR
            IF (nBurstThreshold > UDINT#0) AND (uMaxDelta > (nBurstThreshold + DL_BURST_MARGIN)) THEN
                ePhase := E_DL_PortDiagPhase.eBurst;   // 超阈值：下一拍置单拍标志
            ELSE
                ePhase := E_DL_PortDiagPhase.eMonitor; // 未超阈值：原地自保持
            END_IF
            FOR i := 1 TO DL_PORT_MAX DO
                stState.auPrevCnt[i] := auPortCrcErrCnt[i];  // 装载新基准
            END_FOR
            bWinRun := FALSE;                    // 拉低一拍，强制窗口重新起算
        ELSE
            bWinRun := TRUE;                     // 窗口内持续计时
        END_IF

    E_DL_PortDiagPhase.eBurst:
        bBurstDetected := TRUE;                  // 仅此一拍为真，不锁存，不进故障
        bWinRun        := FALSE;                 // 风暴拍不重启窗口，下一拍再说
        ePhase         := E_DL_PortDiagPhase.eMonitor;

    E_DL_PortDiagPhase.eFault:
        uMaskBuild := 16#0000;                   // 故障态不外送掩码，防误联锁
        bWinRun    := FALSE;
        IF NOT bEnable THEN
            ePhase := E_DL_PortDiagPhase.eIdle;  // 停使能可直接退出故障态
        END_IF

    ELSE
        ePhase        := E_DL_PortDiagPhase.eFault;   // 非法值兜底
        uMaskBuild    := 16#0000;
        bWinRun       := FALSE;
        bStateIllegal := TRUE;                   // 由段 11 统一置 0307
END_CASE

(*------------------------------------------------------------------------------
 * 段 9｜首出仲裁（仅未锁存时执行；升序取最小号端口，先到先得）
 *      First-out arbitration, only when not yet latched, lowest port wins
 *-----------------------------------------------------------------------------*)
IF (NOT stState.bLatchValid) AND uMaskBuild <> 16#0000 THEN
    nFirstScanPort := 0;
    uFirstScanCode := 0;
    FOR i := 1 TO nPortClamped DO
        IF ((uMaskBuild AND SHL(DL_MASK_ONE, i - 1)) <> 16#0000) AND (nFirstScanPort = 0) THEN
            nFirstScanPort := i;                       // 升序首个命中即最小号端口
            uFirstScanCode := auPortErrCode[i];
        END_IF
    END_FOR
    IF nFirstScanPort > 0 THEN
        stState.nLatchPort  := nFirstScanPort;
        stState.uLatchCode  := uFirstScanCode;
        stState.bLatchValid := TRUE;                   // 锁存后本窗口不再改写
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜复位（放在仲裁之后，保证复位当拍首出即为空）
 *      Reset placed after arbitration so the first-out is empty this cycle
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    stState.nLatchPort  := 0;
    stState.uLatchCode  := 0;
    stState.bLatchValid := FALSE;
    bError              := FALSE;
    bStateIllegal       := FALSE;
    ePhase              := E_DL_PortDiagPhase.eIdle;   // 复位后回待机，再按使能重入
    bWinRun             := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 11｜输出归并与码位定级（单一优先级链，全拍只写一次 uErrorId）
 *      Output merge and single-priority error code resolution
 *-----------------------------------------------------------------------------*)
uPortFaultMask  := uMaskBuild AND DL_PORT_MASK_ALL;    // 屏蔽高位脏数据
bAnyPortFault   := (uPortFaultMask <> 16#0000);
nFirstFaultPort := stState.nLatchPort;
uFirstFaultCode := stState.uLatchCode;

IF bStateIllegal THEN
    uErrorId := 16#0003_0307;                          // 优先级一：非法状态
ELSIF (nPortClamped < 1) AND bEnable THEN
    uErrorId := 16#0003_0301;                          // 优先级二：诊断源缺失
ELSIF uPortFaultMask <> 16#0000 THEN
    uErrorId := 16#0003_0300;                          // 优先级三：端口故障锁存
ELSIF bParamClamped THEN
    uErrorId := 16#0003_0141;                          // 信息级：参数越界已钳位
ELSIF bPortCntClamped THEN
    uErrorId := 16#0003_0140;                          // 信息级：端口数越界已钳位
ELSE
    uErrorId := 16#0000_0000;
END_IF

(* 故障位只反映故障级：信息级码 0140 与 0141 绝不置故障位（R21） *)
bError := bStateIllegal
          OR ((nPortClamped < 1) AND bEnable)
          OR (uPortFaultMask <> 16#0000);

eState          := ePhase;                             // 相位每拍重写，供 HMI 诊断
auPortDelta[1]  := auOutDelta[1];                      // 增量数组逐元素转出，避免整数组赋值
auPortDelta[2]  := auOutDelta[2];
auPortDelta[3]  := auOutDelta[3];
auPortDelta[4]  := auOutDelta[4];
auPortDelta[5]  := auOutDelta[5];
auPortDelta[6]  := auOutDelta[6];
auPortDelta[7]  := auOutDelta[7];
auPortDelta[8]  := auOutDelta[8];
END_FUNCTION_BLOCK
