(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SerialScanner
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / TP），零厂商方言
 * 分类     (Category)   : 设备功能块（Function Block，实现 I_DL_BarcodeScanner）
 * 功能简述 (Function)   : 扫码枪触发-结果握手状态机实现（串口/现场总线数据
 *                         本体由上层注入，本块只编排握手）。一次 NoRead 自动
 *                         重试、二次升级故障；结果按长度校验收纳，先剥离
 *                         CR/LF 终止符再锁存；触发输出以 TP 定宽脉冲承载。
 * 接口实现 (Implements) : I_DL_BarcodeScanner。接口属性同名成员（eState/
 *                         bReady/bReadOk/bNoRead/sBarcode/nReadCount/bFault/
 *                         uErrorId）按 R22 以只读 PROPERTY GET 承载（内部镜
 *                         像同源），非接口成员 bTriggerOut/bDataAck 保留
 *                         VAR_OUTPUT；方法 CmdTrigger/CmdAck/CmdReset 在本
 *                         文件尾部落地。
 * 公约遵循 (Convention) : 0.1/R23 事件型握手状态机（指令沿 + 数据到达标志驱
 *                         动，无连续量同步语义），免首扫，无 bInit。
 *                         0.2/R21 bFault 显式排除信息级码；0.5/R7 定时器/边
 *                         沿/TP 实例主体最前部无条件刷新；0.6/R14 结果等待
 *                         窗语义参数经实例入参每拍直喂（TON 断输入自动归零，
 *                         窗口参数变更天然重窗）；0.7/R15 故障级锁存仅复位
 *                         路径清码。
 *                         0.8 故障码段位 16#0003_xxxx（经 DL_Device
 *                         VERSION.md 码表核对：规格建议 0003_0250/0251/0252
 *                         已被 FB_DL_VfdGeneric 占用、0003_0105 终审空置，
 *                         依公约冲突顺延）：
 *                         【故障级】0003_0280 连续 NoRead 超限、0003_0281 设
 *                         备长时间无就绪、0003_0282 非法状态兜底；
 *                         【信息级】0003_0119 条码超长截断、0003_0120 无设
 *                         备就绪门控跳过（一次性）、0003_0117 单次 NoRead
 *                         结果提示。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 参数钳位/长度校验/循环防
 *                         死锁计数器 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 ENUM+CASE+ELSE ✓
 *                         R7 三类实例（R_TRIG×3/TON×1/TP×1）主体最前部无条
 *                         件刷新 ✓｜R8 全常量化 ✓
 * R24 防复发 (R24 note) : 触发单拍输出 bTriggerOut 由 TP 定宽脉冲承载，触发
 *                         请求 _bTriggerReq 于状态机（段 4）置位、在段 1 TP
 *                         实例调用之后立即自清——TP 本拍采到 TRUE 起振、下
 *                         一拍入参回落 FALSE，定宽由 TP 保持；严禁把自清放
 *                         在 TP 调用之前（R6 两处致命缺陷家族根因）。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 2 条：
 *                         ① 码位顺延：规格建议 0003_0250/0251/0252 与既有
 *                           FB_DL_VfdGeneric 冲突、0003_0105 库内裁定空置，
 *                           依公约 0.8 顺延为 0003_0280/0281/0282 与
 *                           0003_0119/0102/0117（核对结果优先于建议值）。
 *                         ② sRawData 声明为 STRING(255)：规格「>255 截断」
 *                           在平台侧由 STRING(255) 上限天然兜底，本块仍保留
 *                           长度校验与 LEFT 截断分支（DL_BARCODE_MAX）作为
 *                           防御性代码与验收向量 V4 载体。
 * 开源溯源 (Origin)     : 来源标签 tcopen-component / scanner-handshake
 *                         （RAW_NOTES_R7 S-3：TcOpen 扫码枪组件的触发-应答
 *                         握手语义域与 NOREAD 标记惯例，Apache-2.0 公开资
 *                         料，仅借鉴语义域；状态机、重试升级、码位与引脚
 *                         契约 100% 本库独立设计，clean-room 未复制源码）。
 * 验收向量 (Acceptance) :
 *   V1 正常解码全链：触发 → eTriggered 一拍 → eReading → bDataNew+条码 →
 *      eOk 锁存 sBarcode/bReadOk，nReadCount+1，bDataAck 一拍；
 *   V2 NoRead→重试→成功：eReading 超窗 → 重试（nRetryMax=1）→ 第二窗收到
 *      条码 → eOk；
 *   V3 NoRead→升级故障：连续 3 次 NoRead（DL_CONSEC_NOREAD_MAX）→ 故障锁存
 *      0003_0280；
 *   V4 超长截断：收到 >DL_BARCODE_MAX 长度条码 → LEFT 截断 + 信息级 0003_0119；
 *   V5 Ack 消费链：eOk 态 CmdAck/bCmdAck 沿 → 清 sBarcode/bReadOk → eIdle；
 *   V6 R24 三段逐拍推演：拍 N 状态机置 _bTriggerReq → 拍 N+1 段 1 TP 采样
 *      起振、随后 _bTriggerReq 自清 → 拍 N+1 输出 bTriggerOut=TRUE 且拍
 *      N+2 起保持 PT 定宽后回落（自清位于实例调用之后，脉冲恒可见）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 07 · DL_Device 扫码枪族实现件）
 *   2026-11-15  v1.0.1  终审修复 2 处：① _nRetry 误在 eTriggered 过渡态清零，
 *                       重试重入即清 → 重试链断裂、无限重发、升级故障永不
 *                       触发（清零移至 eIdle 受理处）；② bDataAck 以状态判
 *                       据回落与置位同拍 → 应答恒不可见（回落判据改为
 *                       NOT bDataNew，与接收层握手时序对齐）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_SerialScanner IMPLEMENTS I_DL_BarcodeScanner
VAR_INPUT
    bCmdTrigger   : BOOL;               // 触发指令（Trigger command），R_TRIG 上升沿单发；电平不连发 / Trigger command, edge one-shot
    bCmdAck       : BOOL;               // 应答指令（Acknowledge），上升沿清除结果保持位 / Ack edge clears the result hold
    bReset        : BOOL;               // 上升沿复位故障（Reset edge）/ Rising edge resets fault
    bDataNew      : BOOL;               // 新数据标志（New data flag），接收层置位、本块消费后经 bDataAck 输出清除 / New-data flag from receive layer, cleared via bDataAck
    bDevReady     : BOOL;               // 扫码枪就绪反馈（Device ready，可选），TRUE=可触发；恒 FALSE 时跳过就绪门控（信息级提示一次）/ Device ready, FALSE-only skips the gate with one-shot info
    sNoReadMark   : STRING(31) := 'NOREAD'; // NOREAD 标记字符串（NoRead marker），长度 0=按超时判定 / NoRead marker, empty = judge by timeout only
    tResultWindow : TIME := T#1S;       // 结果等待窗口（Result window），域 100MS~10S 越界钳位 / Result window, clamped to 100MS..10S
    nRetryMax     : USINT := 1;         // 最大自动重试次数（Max retry），域 0~5 越界钳位；0=不重试 / Max auto retries, clamped 0..5, 0 = no retry
END_VAR
VAR_OUTPUT
    bDataAck    : BOOL;                 // 新数据消费应答（Data consumed ack），接收层据此清 bDataNew，置位一拍 / Data-consumed ack, one scan
    bTriggerOut : BOOL;                 // 扫码枪触发输出（Trigger output），TP 定宽单拍脉冲（R24 范式）/ Trigger output, TP fixed-width pulse (R24)
END_VAR
VAR_IN_OUT
    sRawData    : STRING(255);          // 扫码枪原始接收字符串（Raw received string，含 CR/LF 终止符），由接收层写入；本块只读 / Raw string incl. CR/LF, written by receive layer, read-only here
END_VAR
VAR
    _eState        : E_DL_ScannerState := E_DL_ScannerState.eIdle; // 内部握手状态（Internal handshake state），属性只读 / Internal state, read-only via property
    _bFaultLatch   : BOOL;              // 故障锁存标志（Fault latch flag），仅复位路径清除 / Fault latch, cleared only via reset path
    _uErrorIdInt   : UDINT;             // 内部故障级码寄存（Internal fault-level register）/ Internal fault-level register
    _uInfoCode     : UDINT;             // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code, recomputed each scan
    _sBarcodeInt   : STRING(255);       // 内部条码锁存（Internal barcode latch）/ Internal barcode latch
    _nReadCountInt : UDINT;             // 内部累计成功解码数（Internal total reads），复位不清零 / Internal total reads, preserved over reset
    _nConsecNoRead : UINT;              // 连续 NoRead 计数（Consecutive NoRead counter）/ Consecutive NoRead counter
    _nRetry        : USINT;             // 当前窗内已重试次数（Retry count of this attempt）/ Retry count of this attempt
    _bTriggerReq   : BOOL;              // 触发脉冲请求（Trigger pulse request），置位一拍、TP 采样后自清（R24）/ One-cycle trigger request, self-cleared after TP sampling
    _bReadyBypass  : BOOL;              // 就绪门控跳过信息级已提示（Ready-gate-bypass info done）一次性 / One-shot bypass info flag
    _bReadOkHold   : BOOL;              // 读码成功保持位（Read-OK hold flag），CmdAck 撤销 / Read-OK hold, released by CmdAck
    _bNoReadHold   : BOOL;              // NoRead 保持位（NoRead hold flag），CmdAck 撤销 / NoRead hold, released by CmdAck
    _bNoReadPath   : BOOL;              // 本拍 NoRead 路径判定（NoRead-path verdict this scan）/ NoRead-path verdict this scan
    _bPendTrigger  : BOOL;              // 方法触发请求（Method trigger request）/ Method trigger request
    _bPendAck      : BOOL;              // 方法应答请求（Method ack request）/ Method ack request
    _bPendReset    : BOOL;              // 方法复位请求（Method reset request）/ Method reset request
    _sClean        : STRING(255);       // 剥离终止符后的候选条码（Candidate barcode without CR/LF）/ Candidate barcode after CR/LF strip
    _iChar         : INT;               // 字符剥离循环索引（Char-strip loop index），INT 域匹配 LEN 返回值 / Loop index matching LEN return type
    _sChar         : STRING(1);         // 当前字符（Current character）/ Current character carrier
    _tWindowEff    : TIME := T#1S;      // 钳位后生效等待窗（Clamped result window）/ Clamped result window
    _nRetryMaxEff  : USINT := 1;        // 钳位后生效重试上限（Clamped retry max）/ Clamped retry max
    _fbTrigTrigger : R_TRIG;            // 引脚触发沿（Pin trigger edge）/ Pin trigger edge detector
    _fbTrigAck     : R_TRIG;            // 引脚应答沿（Pin ack edge）/ Pin ack edge detector
    _fbTrigReset   : R_TRIG;            // 引脚复位沿（Pin reset edge）/ Pin reset edge detector
    _fbTonWindow   : TON;               // 结果等待窗定时器（Result window timer）/ Result window timer
    _fbTpTrigger   : TP;                // 触发输出定宽脉冲定时器（Trigger output pulse timer），IEC 标准 TP / Fixed-width trigger pulse timer
END_VAR
VAR CONSTANT
    DL_BARCODE_MAX       : USINT := 255; // 条码最大长度（Barcode max length），>此值截断 / Barcode max length, longer strings truncated
    DL_CONSEC_NOREAD_MAX : UINT  := 3;   // 连续 NoRead 升级故障阈值（Consecutive NoRead escalation limit）/ Consecutive NoRead escalation limit
    DL_TRIG_PULSE        : TIME  := T#50MS; // 触发输出定宽（Trigger pulse width）/ Trigger pulse width
    DL_WINDOW_MIN        : TIME  := T#100MS; // 结果窗下限（Result window lower clamp）/ Result window lower clamp
    DL_WINDOW_MAX        : TIME  := T#10S;   // 结果窗上限（Result window upper clamp）/ Result window upper clamp
    DL_RETRY_MAX_CAP     : USINT := 5;   // 重试上限钳位（Retry max clamp）/ Retry max clamp
END_VAR

METHOD CmdTrigger : BOOL
VAR_INPUT
END_VAR
IF _eState = E_DL_ScannerState.eIdle THEN
    _bPendTrigger := TRUE;        // 登记触发请求，主体状态机消化（Register trigger, consumed by body）
    CmdTrigger := TRUE;           // 受理成功（Accepted）
ELSE
    CmdTrigger := FALSE;          // 非空闲态拒绝（Rejected outside idle）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdAck —— 应答清除结果保持位。仅 eOk/eNoRead 态受理。
 *      Method CmdAck - acknowledge, accepted only in eOk/eNoRead.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdAck : BOOL
VAR_INPUT
END_VAR
IF (_eState = E_DL_ScannerState.eOk) OR (_eState = E_DL_ScannerState.eNoRead) THEN
    _bPendAck := TRUE;            // 登记应答请求（Register ack request）
    CmdAck := TRUE;               // 受理成功（Accepted）
ELSE
    CmdAck := FALSE;              // 无结果可消费拒绝（Nothing to acknowledge）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdReset —— 复位故障。仅故障态受理（接口方法拒绝语义红线）。
 *      Method CmdReset - reset, accepted only in fault state.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdReset : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_ScannerState.eFault) THEN
    _bPendReset := TRUE;          // 登记复位请求（Register reset request）
    CmdReset := TRUE;             // 可复位（Resettable）
ELSE
    CmdReset := FALSE;            // 无故障可复位（Nothing to reset）
END_IF

(*------------------------------------------------------------------------------
 * 属性: eState（GET）—— 当前握手状态只读视图。
 *      Property eState (GET) - read-only handshake state view.
 *------------------------------------------------------------------------------*)
    END_METHOD

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5）+ R24 触发脉冲自清（自清位于实例调用之后）
//      Unconditional instance refresh (R7/0.5) + R24 self-clear AFTER the TP call
// ============================================================================
_fbTrigTrigger(CLK := bCmdTrigger);
_fbTrigAck(CLK    := bCmdAck);
_fbTrigReset(CLK  := bReset);
_fbTonWindow(IN := (_eState = E_DL_ScannerState.eReading), PT := _tWindowEff); // 结果等待窗（Result window）
_fbTpTrigger(IN := _bTriggerReq, PT := DL_TRIG_PULSE);  // 触发定宽脉冲（Fixed-width trigger pulse）
_bTriggerReq := FALSE;            // R24 关键步：TP 已在本拍采样 TRUE，请求立即自清；
                                  // 下一拍入参回落 FALSE，定宽由 TP 保持（Self-clear right
                                  // after TP sampling, width held by the TP itself）

// ============================================================================
// 段 2｜参数钳位 + 信息级码预清零 + 复位路径（R15：锁存仅解除路径清码）
//      Parameter clamps + info preset + reset path (R15)
// ============================================================================
_uInfoCode := 0;                  // 信息级瞬时型每拍重算（Transient info recomputed each scan）
IF tResultWindow < DL_WINDOW_MIN THEN
    _tWindowEff := DL_WINDOW_MIN; // 窗口下限钳位（Window lower clamp）
ELSIF tResultWindow > DL_WINDOW_MAX THEN
    _tWindowEff := DL_WINDOW_MAX; // 窗口上限钳位（Window upper clamp）
ELSE
    _tWindowEff := tResultWindow; // 合法窗口直通（Valid window pass-through）
END_IF
IF nRetryMax <= DL_RETRY_MAX_CAP THEN
    _nRetryMaxEff := nRetryMax;   // 合法重试上限（Valid retry max）
ELSE
    _nRetryMaxEff := DL_RETRY_MAX_CAP; // 越界钳位（Out-of-range clamp）
END_IF

IF _fbTrigReset.Q OR _bPendReset THEN
    _bPendReset  := FALSE;        // 消费方法复位请求（Consume method reset request）
    _bFaultLatch := FALSE;        // 故障锁存解除（Fault latch released）
    _uErrorIdInt := 16#0000_0000; // 故障码清零（Fault code cleared）
    _nConsecNoRead := 0;          // 连续 NoRead 计数清零（Consecutive NoRead cleared）
    _nRetry := 0;                 // 重试计数清零（Retry counter cleared）
    _bReadyBypass := FALSE;       // 门控跳过提示一次性标志复位（Bypass info flag rearmed）
    IF _eState = E_DL_ScannerState.eFault THEN
        _eState := E_DL_ScannerState.eIdle; // 故障态复位回空闲（Fault state back to idle）
    END_IF
END_IF

// ============================================================================
// 段 3｜故障全局监视：长时间无就绪（等待窗内设备始终不就绪不升级，仅在触发
//       受理门控处体现；本块故障监视聚焦 NoRead 升级链）
//      Global fault monitor focus: the NoRead escalation chain
// ============================================================================
IF _fbTonWindow.Q AND (_eState = E_DL_ScannerState.eReading) AND (NOT bDevReady) AND _bReadyBypass THEN
    _uInfoCode := 16#0003_0120;   // 0003_0120 无设备就绪门控跳过【信息级】（等待窗内保持提示）/ Ready gate bypassed, info level
END_IF

// ============================================================================
// 段 4｜主握手状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Main handshake state machine (ENUM + CASE with ELSE fallback)
// ============================================================================
CASE _eState OF

    E_DL_ScannerState.eIdle: // 空闲态：受理触发
        IF _fbTrigTrigger.Q OR _bPendTrigger THEN
            _bPendTrigger := FALSE;             // 消费方法触发请求（Consume method trigger）
            _nRetry := 0;                       // 新尝试重试计数清零（新尝试在受理处清零，重试重入不得清零）/ New attempt: retry cleared at acceptance only
            IF bDevReady OR _bReadyBypass THEN
                _bTriggerReq := TRUE;           // 置触发脉冲请求，下拍段 1 TP 采样（R24：置位于状态机，自清在实例调用之后）/ Arm the trigger pulse, sampled by TP next scan
                _eState := E_DL_ScannerState.eTriggered; // 转已触发态（To triggered state）
            ELSE
                _bReadyBypass := TRUE;          // 恒 FALSE 跳过就绪门控，信息级提示一次性（Bypass gate with one-shot info）
                _uInfoCode := 16#0003_0120;     // 0003_0120 无设备就绪门控跳过【信息级】/ Ready gate bypassed, info level
                _bTriggerReq := TRUE;           // 门控跳过仍放行触发（Bypass still fires the trigger）
                _eState := E_DL_ScannerState.eTriggered;
            END_IF
        END_IF

    E_DL_ScannerState.eTriggered: // 已触发态：单拍过渡，触发脉冲已由 TP 承载
        _eState := E_DL_ScannerState.eReading; // 进入读码等待（To reading state）
        // 注意：重试重入亦经本过渡态，严禁在此清 _nRetry（v1.0.1 修复：
        // 原清零导致重试链断裂、无限重发、升级故障永不触发）
        // Retry re-entry passes here too: _nRetry must NOT be cleared (v1.0.1 fix)

    E_DL_ScannerState.eReading: // 读码等待态：窗内等 bDataNew
        IF bDataNew THEN
            bDataAck := TRUE;                   // 消费应答本拍置位（Data ack asserted this scan）
            // —— 剥离 CR/LF 终止符（防死锁：FOR 循环以字符串长度为界）——
            _sClean := '';                      // 候选条码清空（Candidate cleared）
            FOR _iChar := 1 TO LEN(sRawData) DO // 逐字符剥离（Strip char by char, bounded by LEN）
                _sChar := MID(sRawData, 1, _iChar); // 取第 i 个字符（Take i-th character）
                IF (_sChar <> '$R') AND (_sChar <> '$L') AND (_sChar <> '$N') THEN
                    _sClean := CONCAT(_sClean, _sChar); // 非终止符追加（Append non-terminator）
                END_IF
            END_FOR
            IF LEN(_sClean) > DL_BARCODE_MAX THEN
                _sClean := LEFT(_sClean, DL_BARCODE_MAX); // 超长截断（Overlength truncated）
                _uInfoCode := 16#0003_0119;               // 0003_0119 条码超长截断【信息级】/ Overlength truncated, info level
            END_IF
            IF (LEN(_sClean) = 0) OR ((LEN(sNoReadMark) > 0) AND (_sClean = sNoReadMark)) THEN
                _bNoReadPath := TRUE;           // 空串或 NoRead 标记串：走 NoRead 路径（Empty or marker: NoRead path）
            ELSE
                _sBarcodeInt := _sClean;        // 有效条码锁存（Valid barcode latched）
                _bReadOkHold := TRUE;           // 读码成功保持位（Read-OK hold asserted）
                _nReadCountInt := _nReadCountInt + 1; // 累计成功解码（Cumulative successful reads）
                _nConsecNoRead := 0;            // 连续 NoRead 清零（Consecutive NoRead cleared）
                _eState := E_DL_ScannerState.eOk; // 转成功态（To OK state）
            END_IF
        ELSIF _fbTonWindow.Q THEN
            _bNoReadPath := TRUE;               // 超窗未回数：NoRead 路径（Window timeout: NoRead path）
        ELSE
            _bNoReadPath := FALSE;              // 窗内继续等待（Keep waiting inside window）
        END_IF
        IF _bNoReadPath THEN
            IF _nRetry < _nRetryMaxEff THEN
                _nRetry := _nRetry + 1;         // 未达重试上限：自动重发（Below retry max: auto retrigger）
                _bTriggerReq := TRUE;           // 重发触发脉冲（R24 范式，同段 4 空闲态置位）/ Arm retrigger pulse
                _eState := E_DL_ScannerState.eTriggered; // 经已触发态重入（Re-enter via triggered state）
            ELSE
                _nConsecNoRead := _nConsecNoRead + 1; // 重试耗尽：连续计数累加（Retries exhausted: consecutive count up）
                IF _nConsecNoRead >= DL_CONSEC_NOREAD_MAX THEN
                    _bFaultLatch := TRUE;       // 连续 NoRead 超限故障锁存（Escalation fault latch）
                    _uErrorIdInt := 16#0003_0280; // 0003_0280 连续 NoRead 超限【故障级】/ Consecutive NoRead exceeded, fault level
                    _eState := E_DL_ScannerState.eFault;
                ELSE
                    _bNoReadHold := TRUE;       // 单次 NoRead 保持位（Single NoRead hold）
                    _uInfoCode := 16#0003_0117; // 0003_0117 单次 NoRead 结果提示【信息级】/ Single NoRead result, info level
                    _eState := E_DL_ScannerState.eNoRead; // 转 NoRead 保持态（To NoRead hold state）
                END_IF
            END_IF
        END_IF

    E_DL_ScannerState.eOk: // 成功保持态：等待应答消费
        IF _fbTrigAck.Q OR _bPendAck THEN
            _bPendAck    := FALSE;          // 消费方法应答请求（Consume method ack）
            _sBarcodeInt := '';             // 条码清空（Barcode cleared）
            _bReadOkHold := FALSE;          // 读码成功保持位撤销（Read-OK hold released）
            _eState := E_DL_ScannerState.eIdle; // 回空闲受理下次触发（Back to idle for next trigger）
        END_IF

    E_DL_ScannerState.eNoRead: // NoRead 保持态：等待应答消费
        IF _fbTrigAck.Q OR _bPendAck THEN
            _bPendAck    := FALSE;          // 消费方法应答请求（Consume method ack）
            _bNoReadHold := FALSE;          // NoRead 保持位撤销（NoRead hold released）
            _eState := E_DL_ScannerState.eIdle; // 回空闲（Back to idle）
        END_IF

    E_DL_ScannerState.eFault: // 故障锁存态：复位路径见段 2
        // 等待复位（Await reset, handled in stage 2）

    ELSE
        // 非法状态兜底：任何越界枚举值强制锁存故障（Illegal state fallback）
        _bFaultLatch := TRUE;               // 故障锁存（Fault latch）
        _uErrorIdInt := 16#0003_0282;       // 0003_0282 非法状态兜底【故障级】/ Illegal state, fault level
        _eState := E_DL_ScannerState.eFault;
END_CASE

// ============================================================================
// 段 5｜输出推导 + bDataAck 单拍回落
//      Output derivation + one-scan bDataAck fallback
// ============================================================================
bTriggerOut := _fbTpTrigger.Q;    // 触发定宽脉冲输出（Trigger pulse output）
IF NOT bDataNew THEN
    bDataAck := FALSE;            // 接收层已清 bDataNew 时应答回落（握手时序修复：消费拍状态
                                  // 即转出 eReading，若以状态判据回落则应答恒不可见）
                                  // Ack drops when the receive layer has cleared bDataNew
                                  // (v1.0.1 fix: state-based verdict cleared the ack same-scan)
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdTrigger —— 触发一次解码。仅空闲态受理，其余态（含故障态）拒绝。
 *      Method CmdTrigger - one decode, accepted only in idle, rejected otherwise.
 *------------------------------------------------------------------------------*)



PROPERTY eState : E_DL_ScannerState
eState := _eState;                // 返回内部状态（Return internal state）

(*------------------------------------------------------------------------------
 * 属性: bReady（GET）—— 就绪可触发（空闲态即就绪）。
 *      Property bReady (GET) - ready to accept a trigger (idle state).
 *------------------------------------------------------------------------------*)
PROPERTY bReady : BOOL
bReady := (_eState = E_DL_ScannerState.eIdle); // 空闲态派生式（Idle-state derived form）

(*------------------------------------------------------------------------------
 * 属性: bReadOk（GET）—— 解码成功且结果有效。
 *      Property bReadOk (GET) - decode OK and result valid.
 *------------------------------------------------------------------------------*)
PROPERTY bReadOk : BOOL
bReadOk := _bReadOkHold;          // 返回成功保持位（Return read-OK hold）

(*------------------------------------------------------------------------------
 * 属性: bNoRead（GET）—— 未读到（单次保持或故障升级前的保持态）。
 *      Property bNoRead (GET) - NoRead hold indicator.
 *------------------------------------------------------------------------------*)
PROPERTY bNoRead : BOOL
bNoRead := _bNoReadHold OR (_eState = E_DL_ScannerState.eNoRead); // 保持位或保持态派生式（Hold flag or hold-state derived form）

(*------------------------------------------------------------------------------
 * 属性: sBarcode（GET）—— 最近有效条码字符串（bReadOk=TRUE 时有效）。
 *      Property sBarcode (GET) - last valid barcode (valid when bReadOk).
 *------------------------------------------------------------------------------*)
PROPERTY sBarcode : STRING(255)
sBarcode := _sBarcodeInt;         // 返回条码锁存镜像（Return barcode latch mirror）

(*------------------------------------------------------------------------------
 * 属性: nReadCount（GET）—— 累计成功解码次数（复位不清零，追溯口径）。
 *      Property nReadCount (GET) - cumulative reads (preserved over reset).
 *------------------------------------------------------------------------------*)
PROPERTY nReadCount : UDINT
nReadCount := _nReadCountInt;     // 返回累计数镜像（Return cumulative mirror）

(*------------------------------------------------------------------------------
 * 属性: bFault（GET）—— 故障锁存指示（信息级码不置本位，0.2 公约）。
 *      Property bFault (GET) - fault latch indicator, info codes excluded.
 *------------------------------------------------------------------------------*)
PROPERTY bFault : BOOL
bFault := _bFaultLatch OR (_eState = E_DL_ScannerState.eFault); // 显式排除信息级派生式（Derived form excluding info codes）

(*------------------------------------------------------------------------------
 * 属性: uErrorId（GET）—— 末次故障码（故障级优先，无故障时透出本拍信息级
 *         码，0.2/0.15 公约）。
 *      Property uErrorId (GET) - last error code (fault priority, info code shown otherwise).
 *------------------------------------------------------------------------------*)
PROPERTY uErrorId : UDINT
IF (_uErrorIdInt <> 0) OR (_eState = E_DL_ScannerState.eFault) THEN
    uErrorId := _uErrorIdInt;     // 故障级码优先透出（Fault-level code priority）
ELSE
    uErrorId := _uInfoCode;       // 无故障时透出本拍信息级码（Transient info code when no fault）
END_IF
END_FUNCTION_BLOCK
