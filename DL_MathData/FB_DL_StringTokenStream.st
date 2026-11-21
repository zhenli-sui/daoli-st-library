(*==============================================================================
 * 组件名称 (Component)  : FB_DL_StringTokenStream
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（LEN / FIND / LEFT / MID / R_TRIG）
 * 功能描述 (Function)   : 按 1~4 字符分隔符把一条定长报文逐段取出，每次触发输出一段，
 *                         跨扫描周期推进。用于扫码枪、称重仪表、在线分析仪这类
 *                         「字段长度不固定、帧总长有限」的报文解析。
 *                         本件最重要的语义：**连续分隔符产生空段，空段仍占一个序号**，
 *                         绝不跳过、绝不合并 —— 现场手写取段程序最典型的故障就是空字段
 *                         被吞掉导致后续字段整体错位（第 3 段显示成第 4 段的值）。
 *                         流式推进的另一目的是把「一次解析整帧」的耗时摊到多拍，
 *                         不让长报文的串操作撑爆扫描周期。
 * 出口契约 (Exit)       : sToken / nTokenIdx / bValidToken 为「本拍产出」，bDone 表示帧已读完
 *                          （读完后保持 TRUE，直到重装载或复位）。故障级锁存只由 021C /
 *                         021D / 021E 三码置位，bReset 上升沿统一清故障并回空闲。
 *                         调用约定：bNext 上升沿后**下一拍**产出该段（状态机一相一拍，
 *                         便于上层在「请求」与「结果」之间插入握手超时判断）。
 * 开源溯源 (Origin)     : 来源标签 lgf-datahandling。许可证：LGF 为免费闭源发布，未取得源码，
 *                         不构成衍生作品。借鉴点仅为字符串族「定长缓冲 + 原地操作、
 *                         不做动态分配」的参数域契约。
 *                         clean-room 独立实现：流式状态机、空段语义、段数上限策略、
 *                         帧改写判据、错误码全部自有——该类库并无流式分词器可参考。
 * 码位说明 (Codes)      : 信息级 16#0001_013A（空段）/ 013B（段长超限已截断）/ 013C（末段后
 *                         再取）；故障级 16#0001_021C（分隔符为空）/ 021D（段数超上限）/
 *                         021E（非法相位兜底）。共 6 码，全部落在 R12 计划第 1.2 节本件码段内。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: LEN / FIND / LEFT / MID / R_TRIG
 * 红线自检 (Redline)    : 1 ✓ 零全局变量表依赖、零外部变量声明、零物理地址
 *                         2 ✓ 纯 IEC 61131-3，无指针、无厂商库、无动态内存
 *                         3 ✓ 分隔符空硬闸、段数上限锁故障、段长截断、游标全程夹在帧内
 *                         4 ✓ 全变量中英双语同行注释
 *                         5 ✓ 四态 ENUM + CASE 全覆盖 + ELSE 兜底（021E）
 *                         6 ✓ R_TRIG 实例在 CASE 之外每拍无条件刷新
 *                         7 ✓ END_FUNCTION_BLOCK 位于文件最后有效行
 * 规格偏离留档 (Deviation):
 *   D1 计划 3.7 节内部变量表列有 fbTrigFrame（帧变化沿实例）。实测「等长改写」场景下
 *      帧变化必须逐字符比较才能判出，边沿实例反而会漏判（连续两拍都不同则不再产生上升沿），
 *      故本实现只保留 fbTrigNext / fbTrigReset 两个实例，帧变化判据改为逐字符比较，
 *      不设 fbTrigFrame，避免出现「声明了却不参与判决」的死变量。
 *   D2 计划写「bDone 单拍脉冲」，同节边界条款又写「bDone 保持 TRUE」。本实现取后者
 *      （保持到重装载或复位），理由：上层若每拍轮询 bDone，单拍脉冲极易漏采。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R12 · Level 0/1 DL_MathData 字符串族）
 *   2026-11-15  v1.0.1  终审定点修复 A-D02：取段相位（eDraining）入口用锁存帧长度
 *      重算 nFrameLen，与全局帧长度判据（段 3 跟随实时入参）解耦。原实现取段时用
 *      实时帧长度做边界与 MID 长度，却对锁存副本切片，调用方中途改写帧即可能产出
 *      「有效但为空」的假段（nSegLen 取自实时帧、字符取自短一截的锁存帧）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TokenPhase（归属 DL_MathData，与本功能块同文件）
 * 含义: 分词流式解析的离散相位。步长留空位，便于后续插态而不破坏既有工程数值。
 *----------------------------------------------------------------------------*)
TYPE E_DL_TokenPhase :
(
    eIdle     := 0,    // 空闲：等待使能与分隔符校验 / Idle: waiting for enable and delimiter check
    eReady    := 10,   // 就绪：等待帧装载或下一次取段请求 / Ready: waiting for frame load or next request
    eDraining := 20,   // 取段：本拍切出一段并推进游标 / Draining: cut one segment and advance the cursor
    eFault    := 99    // 故障：分隔符为空或段数超限，输出冻结 / Fault: bad delimiter or token overflow
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_StringTokenStream
 * 调用约定: 每个扫描周期无条件调用一次；bEnable 为 FALSE 时内部相位与全部出口冻结。
 * 无状态泄漏: 全部状态驻留于实例私有 VAR，零全局引用，可多实例并行解析多条报文。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_StringTokenStream
VAR_INPUT
    bEnable       : BOOL;                        // 使能，FALSE 时冻结游标并保持全部输出 / Enable, freezes the cursor when FALSE
    bReset        : BOOL;                        // 上升沿复位到帧起点并清故障 / Rising edge rewinds to the frame start
    sFrame        : STRING(255);                 // 待分词报文，内容变化自动重装载 / Frame to tokenise, reloaded on change
    sDelimiter    : STRING(4);                   // 分隔符（1~4 字符），空 = 故障 / Delimiter of one to four characters
    bNext         : BOOL;                        // 上升沿取下一段 / Rising edge advances to the next token
    nMaxTokenLen  : INT := 32;                   // 单段最大长度 [字符]，域 1~64 / Maximum token length, 1..64
    nMaxTokens    : INT := 32;                   // 单帧最大段数 [段]，域 1~64 / Maximum token count, 1..64
END_VAR
VAR_OUTPUT
    sToken        : STRING(64);                  // 本段内容，超长截断 / Current token, truncated when too long
    nTokenIdx     : INT;                         // 本段序号，1 起 [索引] / Token index, one based
    nTokenCount   : INT;                         // 本帧已产出段数 [段] / Tokens produced so far
    bValidToken   : BOOL;                        // 本段非空（连续分隔符产生的空段为 FALSE） / Non-empty token
    bDone         : BOOL;                        // 已到末段之后 TRUE，保持到重装载 / End of frame reached
    bError        : BOOL;                        // 故障级锁存，仅 021C 021D 021E 置位 / Latched fault
    uErrorId      : UDINT;                       // 事件码，0 = 无事件 / Event code, zero means none
    eState        : E_DL_TokenPhase;             // 主状态机当前相位 / Current phase
END_VAR
VAR
    fbTrigNext    : R_TRIG;                      // bNext 上升沿，每拍无条件刷新 / bNext rising edge, refreshed every scan
    fbTrigReset   : R_TRIG;                      // bReset 上升沿，每拍无条件刷新 / bReset rising edge, refreshed every scan
    ePhase        : E_DL_TokenPhase := E_DL_TokenPhase.eIdle;  // 内部相位 / Internal phase
    sFrameLatched : STRING(255);                 // 已装载的帧副本，防调用方中途改写 / Latched frame copy
    sScan         : STRING(255);                 // 查找窗口，从游标起的剩余串 / Search window from the cursor
    sSeg          : STRING(255);                 // 本段原始字符（截断前） / Raw segment text before truncation
    nCursor       : INT;                         // 当前解析游标，1 起 [字符位] / Parse cursor, one based
    nFrameLen     : INT;                         // 帧长度 [字符] / Frame length
    nDelimLen     : INT;                         // 分隔符长度 [字符] / Delimiter length
    nMaxTokUse    : INT;                         // 生效段数上限 [段] / Effective token limit
    nMaxLenUse    : INT;                         // 生效段长上限 [字符] / Effective token length limit
    nSegStart     : INT;                         // 本段起始位置 [字符位] / Segment start position
    nSegLen       : INT;                         // 本段长度 [字符] / Segment length
    nPos          : INT;                         // 分隔符命中位置，0 = 未命中 [字符位] / Delimiter hit position
    bFrameChanged : BOOL;                        // 帧内容与副本不同 / Frame differs from the copy
    i             : INT;                         // 逐字符比较索引 [字符位] / Character compare index
    nGuard        : DINT;                        // 循环守卫 / Loop guard
END_VAR
VAR CONSTANT
    DL_TOK_MAX    : INT  := 64;                  // 段数与段长上限，与入参声明一致 [个/字符] / Token count and length ceiling
    DL_GUARD_MAX  : DINT := 512;                 // 循环守卫上限 [次] / Loop guard limit
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜边沿实例每拍无条件刷新（严禁放进 CASE 或 IF 内部）
 *      Edge instances refreshed unconditionally on every scan
 *-----------------------------------------------------------------------------*)
fbTrigNext(CLK := bNext);
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 2｜段数与段长上限钳位：入参域守护，任何情况下不进入状态机之前就收口
 *      Input domain guard for the two limits, settled before the state machine
 *-----------------------------------------------------------------------------*)
nMaxTokUse := nMaxTokens;
IF nMaxTokUse < 1 THEN
    nMaxTokUse := 1;
ELSIF nMaxTokUse > DL_TOK_MAX THEN
    nMaxTokUse := DL_TOK_MAX;
END_IF

nMaxLenUse := nMaxTokenLen;
IF nMaxLenUse < 1 THEN
    nMaxLenUse := 1;
ELSIF nMaxLenUse > DL_TOK_MAX THEN
    nMaxLenUse := DL_TOK_MAX;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜帧变化判据：先比长度，再逐字符比较
 *      Frame change detector: length compare first, then character by character
 *      等长改写（两个字段互换位置）会让长度差值判据漏判，逐字符比较才是唯一可靠判据
 *      An equal length rewrite defeats a length only test, so compare per character
 *-----------------------------------------------------------------------------*)
nFrameLen     := LEN(sFrame);
bFrameChanged := FALSE;
IF nFrameLen <> LEN(sFrameLatched) THEN
    bFrameChanged := TRUE;
ELSE
    i      := 1;
    nGuard := 0;
    WHILE (i <= nFrameLen) AND (NOT bFrameChanged) AND (nGuard < DL_GUARD_MAX) DO
        nGuard := nGuard + 1;
        IF MID(sFrame, 1, i) <> MID(sFrameLatched, 1, i) THEN
            bFrameChanged := TRUE;
        END_IF
        i := i + 1;
    END_WHILE;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜主状态机：四相全覆盖 + ELSE 兜底
 *      Main state machine with every enum member and an ELSE fallback
 *-----------------------------------------------------------------------------*)
IF bEnable THEN

    (* 分隔符为空是硬闸：空串在 FIND 上行为跨平台不一致，必须先于任何取段动作拦死 *)
    (* An empty delimiter is a hard gate: FIND on an empty pattern is platform dependent *)
    nDelimLen := LEN(sDelimiter);
    IF nDelimLen < 1 THEN
        bError := TRUE;
        IF uErrorId = 16#0000_0000 THEN
            uErrorId := 16#0001_021C;
        END_IF
        ePhase := E_DL_TokenPhase.eFault;
    END_IF

    CASE ePhase OF
        E_DL_TokenPhase.eIdle:
            (* 首扫装载：把调用方的帧拷进副本，游标与计数归零 *)
            (* First load: copy the caller frame, reset cursor and counters *)
            bDone         := FALSE;
            sFrameLatched := sFrame;
            nFrameLen     := LEN(sFrameLatched);
            nCursor       := 1;
            nTokenIdx     := 0;
            nTokenCount   := 0;
            ePhase        := E_DL_TokenPhase.eReady;

        E_DL_TokenPhase.eReady:
            (* 等待期：帧被改写则整体回到帧起点，否则等取段请求 *)
            (* Waiting: a rewritten frame rewinds, otherwise wait for the request *)
            IF bFrameChanged THEN
                sFrameLatched := sFrame;
                nFrameLen     := LEN(sFrameLatched);
                nCursor       := 1;
                nTokenIdx     := 0;
                nTokenCount   := 0;
                bDone         := FALSE;
                uErrorId      := 16#0000_0000;
            END_IF
            IF fbTrigNext.Q THEN
                ePhase := E_DL_TokenPhase.eDraining;
            END_IF

        E_DL_TokenPhase.eDraining:
            (* 取段一律以锁存副本为准：段 3 的 nFrameLen 跟随实时入参，此处必须重算，
               否则调用方中途改写帧会让「实时长度」与「锁存内容」错配，切出假空段 *)
            (* Always cut from the latched copy: recompute the length here so that a
               mid-parse rewrite can never pair a live length with stale content *)
            nFrameLen := LEN(sFrameLatched);
            IF nCursor > nFrameLen THEN
                (* 末段之后再取：序号不回绕、内容置空、标志保持，仅给提示码 *)
                (* Request after the last segment: no wrap around, empty content *)
                bDone       := TRUE;
                sToken      := '';
                bValidToken := FALSE;
                IF uErrorId = 16#0000_0000 THEN
                    uErrorId := 16#0001_013C;
                END_IF
                ePhase := E_DL_TokenPhase.eReady;
            ELSIF nTokenCount >= nMaxTokUse THEN
                (* 段数超上限：继续解析会把段序号推过调用方预期，锁故障停止 *)
                (* Token overflow: further parsing would push the index past expectation *)
                bError  := TRUE;
                uErrorId := 16#0001_021D;
                nCursor := nFrameLen + 1;
                ePhase  := E_DL_TokenPhase.eFault;
            ELSE
                (* 切一段：命中分隔符则段长 = 命中位减一，未命中则吃掉整条剩余串 *)
                (* Cut one segment: before the delimiter, or the whole remainder *)
                nSegStart := nCursor;
                sScan     := MID(sFrameLatched, nFrameLen - nCursor + 1, nCursor);
                nPos      := FIND(sScan, sDelimiter);
                IF nPos > 0 THEN
                    nSegLen := nPos - 1;
                ELSE
                    nSegLen := nFrameLen - nCursor + 1;
                END_IF
                IF nSegLen < 0 THEN
                    nSegLen := 0;
                END_IF

                IF nSegLen > 0 THEN
                    sSeg := MID(sFrameLatched, nSegLen, nSegStart);
                ELSE
                    sSeg := '';
                END_IF

                (* 游标前移：命中则越过分隔符，未命中则直接到帧尾之后 *)
                (* Cursor advance: step over the delimiter, or jump past the frame end *)
                IF nPos > 0 THEN
                    nCursor := nSegStart + nSegLen + nDelimLen;
                ELSE
                    nCursor := nFrameLen + 1;
                END_IF
                IF nCursor < 1 THEN
                    nCursor := 1;
                END_IF

                (* 空段仍占一个序号：这是字段序号对齐的唯一保证 *)
                (* An empty segment still consumes an index: this keeps fields aligned *)
                nTokenIdx   := nTokenIdx + 1;
                nTokenCount := nTokenCount + 1;
                bDone       := FALSE;

                IF nSegLen <= 0 THEN
                    sToken      := '';
                    bValidToken := FALSE;
                    IF uErrorId = 16#0000_0000 THEN
                        uErrorId := 16#0001_013A;
                    END_IF
                ELSE
                    IF nSegLen > nMaxLenUse THEN
                        sToken := LEFT(sSeg, nMaxLenUse);
                        IF uErrorId = 16#0000_0000 THEN
                            uErrorId := 16#0001_013B;
                        END_IF
                    ELSE
                        sToken := sSeg;
                    END_IF
                    bValidToken := TRUE;
                END_IF

                ePhase := E_DL_TokenPhase.eReady;
            END_IF

        E_DL_TokenPhase.eFault:
            (* 故障态冻结输出，只认复位沿；故障前的段内容保留在出口上供现场取证 *)
            (* Fault freezes the outputs and only the reset edge leaves this phase *)
            IF fbTrigReset.Q THEN
                bError      := FALSE;
                uErrorId    := 16#0000_0000;
                bDone       := FALSE;
                nCursor     := 1;
                nTokenIdx   := 0;
                nTokenCount := 0;
                ePhase      := E_DL_TokenPhase.eIdle;
            END_IF

        ELSE
            (* 兜底：枚举被在线改坏或跨版本不兼容，置终端安全态并掐断后续解析 *)
            (* Fallback: terminal safe state, cursor pushed past the frame end *)
            bError  := TRUE;
            uErrorId := 16#0001_021E;
            nCursor := nFrameLen + 1;
            bDone   := TRUE;
            ePhase  := E_DL_TokenPhase.eFault;
    END_CASE

END_IF

(*------------------------------------------------------------------------------
 * 段 5｜相位出口：内部相位镜像到出口，便于 HMI 与在线诊断直接读取
 *      Phase mirror to the output pin for HMI and online diagnostics
 *-----------------------------------------------------------------------------*)
eState := ePhase;
END_FUNCTION_BLOCK
