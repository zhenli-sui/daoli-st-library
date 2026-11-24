(*==============================================================================
 * 组件名称 (Component)  : FB_DL_BitArrayChangeWatch
 * 所属子库 (Sublibrary) : DL_Base
 * 归属目录 (Directory)  : C:\Library\DL_Base
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 位图变化监视 · 状态机
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 R_TRIG 与位运算
 * 功能一句话 (Summary)  : 逐拍监视 DWORD 数组位图的位级变化，输出本拍变化掩码、
 *                         变化位数、首个变化位绝对位号，并累计跳变次数与判稳标志。
 * 功能描述 (Function)   : 上位机只显示「有变化」时不定位，接触不良的端子表现为
 *                         某一位反复抖动，必须单独统计跳变位数才能定位到端子与
 *                         线号。本件把「本拍变化」与「累计抖动」分开输出：变化掩码
 *                         给 HMI 做位闪烁，跳变累计给维修工排出最脏的位。
 * 与既有件边界 (Boundary): FC_DL_DualEdgeTrig 做单信号的边沿检测；FB_DL_SignalDebounce
 *                         做单信号滤波；本件做整组位图的位级变化统计，三者正交。
 * 设计要点 (Key notes)  : ① 复位沿检测实例在状态机之外无条件刷新，绝不放进分支；
 *                         ② 首拍只装载不复位跳变计数，避免上电瞬间误报全部位跳动；
 *                         ③ 跳变累计饱和不回绕：回绕会把抖动最严重的位算成最干净的位；
 *                         ④ 掉使能只清变化族，不清跳变累计，诊断证据不因停机而丢失；
 *                         ⑤ 快照赋值放在输出之后，保证下一拍才参与比较；
 *                         ⑥ 位扫描与首变位查找合并为一趟循环，避免两趟扫描的节拍差。
 * 开源溯源 (Origin)     : 来源标签 lgf-bitlogic。LGF 为免费闭源发布的公开函数库手册，
 *                         本件仅借鉴其位逻辑组把「单点位测试」与「批量监视」并列的
 *                         分类位置；许可证按其发布方条款仅作分类参考，变化检测算法、
 *                         跳变统计与饱和策略全部自有，属 clean-room 独立实现。
 * 码位说明 (Codes)      : 信息级 16#0001_012D 字数上限钳位 ｜ 16#0001_012E 判稳拍数
 *                         钳位 ｜ 16#0001_012F 跳变累计饱和；
 *                         故障级 16#0001_021A 字数小于一（组态错，锁存）｜
 *                         16#0001_021B 非法状态兜底。故障级码只在本件使用，
 *                         与全库已占码求差为空。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 R_TRIG 与
 *                         SHL / XOR / INT_TO_UDINT / UDINT_TO_INT。
 * 调用约定 (Call rules): 每扫描周期无条件调用一次；bEnable 为假时输出变化族清零，
 *                         跳变累计保持，恢复使能后继续累加。
 * 红线自检 (Redline)    : 零全局变量表依赖 ｜ 零外部变量声明 ｜ 零物理地址
 *                         纯 IEC 61131-3 ｜ 数组下标先钳位后使用 ｜ 无除法
 *                         状态机三成员全覆盖并带兜底 ｜ 边沿实例在分支外刷新
 * 修订历史 (Revision)   : 2026-11-15  v1.0.0  首版入库（Round 12 · 位图变化监视）
 *                         2026-11-15  v1.0.1  终审定点修复 A-D03：掉使能回空闲的判据补
 *                         「当前不在故障态」前置条件，杜绝使能为假时抢走复位上升沿
 *                         导致故障不可复位（eFault 主体整拍被跳过，边沿一拍即失）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_BitWatchState（归属 DL_Base，与 FB_DL_BitArrayChangeWatch 同文件）
 * 含义: 位图监视主状态。编号 0 起跳、段间隔 10，便于后续插态。
 *----------------------------------------------------------------------------*)
TYPE E_DL_BitWatchState :
(
    eIdle     := 0,      // 空闲：装载快照并清零变化族，等待使能 / Idle, snapshot loaded when enabled
    eSampling := 10,     // 采样：逐字比对、位统计、跳变累计与判稳 / Sampling, compare and accumulate every cycle
    eFault    := 99      // 故障：组态错锁存，输出冻结，复位沿退出 / Latched configuration fault, outputs frozen
);
END_TYPE

(*==============================================================================
 * 拍序示意 (Cycle sequence)：
 *   第 1 拍  空闲态装载上拍快照，本拍不比较，故不产生跳变
 *   第 2 拍  采样态比较本拍与上拍，异或结果即变化掩码，同时累计跳变位数
 *   第 3 拍  若连续无变化拍数达到判稳门限，判稳标志置真
 *   第 4 拍  快照更新为第 3 拍的位图，第 5 拍起以新快照为基准
 *   跳变累计只在采样态累加，首拍装载与掉使能期间一律不动
 *============================================================================*)

FUNCTION_BLOCK FB_DL_BitArrayChangeWatch
VAR_INPUT
    bEnable       : BOOL;                          // 使能，为假时变化族清零并退出采样 / Enable, clears the change family when false
    bReset        : BOOL;                          // 上升沿复位跳变累计与判稳计时 / Rising edge resets toggle count and settle timer
    nWordCount    : INT := 1;                      // 监视字数 [个]，域 1 到 8，越界钳位 / Watched word count, 1 to 8, clamped
    auWatch       : ARRAY[1..8] OF DWORD;          // 当前位图快照，位 0 在最低位 [位串] / Current bitmap snapshot, bit zero is the lowest bit
    nSettleCycles : INT := 2;                      // 判稳所需连续无变化拍数 [拍]，域 1 到 100 / Cycles required to declare steady, 1 to 100
END_VAR
VAR_OUTPUT
    auChangeMask  : ARRAY[1..8] OF DWORD;          // 本拍变化位掩码，按字对齐，未监视的字为零 [位串] / Per word change mask of this cycle
    nChangeBits   : INT;                           // 本拍变化位总数，逐字位计数之和 [位] / Total changed bits this cycle
    nFirstBit     : INT;                           // 首个变化位绝对位号，负一表示本拍无变化 [bit] / First changed absolute bit, minus one when none
    uToggleCount  : UDINT;                         // 累计跳变位数，由复位上升沿清零 [位次] / Accumulated toggled bits, cleared by the reset edge
    bSteady       : BOOL;                          // 连续无变化拍数达到门限为真 / No change for the settle window
    eState        : E_DL_BitWatchState;            // 主状态机当前状态，供 HMI 诊断 / Current state of the main state machine
    bError        : BOOL;                          // 故障级锁存，仅字数小于一与非法状态置位 / Latched fault, only set by the two fault codes
    uErrorId      : UDINT;                         // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    auPrev        : ARRAY[1..8] OF DWORD;          // 上拍快照，跨周期保持 [位串] / Previous snapshot kept across cycles
    auXor         : ARRAY[1..8] OF DWORD;          // 本拍异或结果 [位串] / XOR result of this cycle
    fbTrigReset   : R_TRIG;                        // 复位沿检测实例，在状态机之外无条件刷新 / Reset edge detector refreshed outside the state machine
    eStateInt     : E_DL_BitWatchState := E_DL_BitWatchState.eIdle; // 内部状态，对外经 eState 输出 / Internal state exported through eState
    bFirstScan    : BOOL := FALSE;                 // 首拍装载完成标志，初值假表示尚未装载 / First scan loaded flag, false means not yet loaded
    nWordClamped  : INT;                           // 钳位后字数 [个] / Clamped word count
    nSettleUse    : INT;                           // 生效判稳拍数 [拍] / Effective settle cycles
    nSteadyCnt    : INT;                           // 已连续无变化拍数 [拍] / Cycles already steady
    uWeight       : UDINT;                         // 单拍位计数中间量 [位] / Population count intermediate
    nBitScan      : INT;                           // 位扫描索引，0 到 31 [bit] / Bit scan index, 0 to 31
    nIdx          : INT;                           // 字下标遍历索引 [索引] / Word loop index
    nGuard        : DINT;                          // 循环守卫计数，防字循环失控 [次] / Loop guard counter for the word loop
    bAnyChange    : BOOL;                          // 本拍是否发生变化 / Any change this cycle
    bParamClamped : BOOL;                          // 参数被钳位标记，故障态退出判据之一 / Parameter clamped flag, also gates the fault exit
END_VAR
VAR CONSTANT
    DL_WORD_MAX   : INT := 8;                          // 字数上限 [个] / Word count limit
    DL_BIT_WORD   : INT := 32;                         // 单字位宽 [bit] / Bits per word
    DL_GUARD_MAX  : DINT := 64;                        // 循环守卫上限，远大于字数上限故正常不触发 [次] / Loop guard limit, never reached in normal operation
    DL_I_W        : INT := 1;                          // 数组首下标 [索引] / First array index
    DL_SETTLE_MIN : INT := 1;                          // 判稳拍数下限 [拍] / Lower settle bound
    DL_SETTLE_MAX : INT := 100;                        // 判稳拍数上限，同时兼作稳定计数饱和值 [拍] / Upper settle bound, also saturates the steady counter
    DL_TOGGLE_MAX : UDINT := 16#FFFF_FFFE;             // 跳变累计饱和值，禁止回绕 [位次] / Saturation value of the toggle counter, no wrap around
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜复位沿检测（红线）：实例在状态机之外每拍无条件刷新
 *      Reset edge detector, refreshed unconditionally outside the state machine
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 2｜事件码刷新与参数钳位（边界 B1/B2）
 *      Event code refresh and parameter clamping
 *      未锁存故障时每拍先清码，保证事件码是「本拍事件」而不是陈年旧码
 *-----------------------------------------------------------------------------*)
IF NOT bError THEN
    uErrorId := 16#0000_0000;
END_IF

nWordClamped := nWordCount;
IF nWordClamped < DL_I_W THEN
    nWordClamped  := DL_I_W;
    bParamClamped := TRUE;
    bError        := TRUE;
    uErrorId      := 16#0001_021A;   // 组态错：字数小于一，属数组域非法
ELSE
    bParamClamped := FALSE;
    IF nWordClamped > DL_WORD_MAX THEN
        nWordClamped  := DL_WORD_MAX;
        bParamClamped := TRUE;
        IF uErrorId = 16#0000_0000 THEN
            uErrorId := 16#0001_012D;   // 字数超限，已钳位到上限并照常服务
        END_IF
    END_IF
END_IF

nSettleUse := nSettleCycles;
IF nSettleUse < DL_SETTLE_MIN THEN
    nSettleUse := DL_SETTLE_MIN;
    IF uErrorId = 16#0000_0000 THEN
        uErrorId := 16#0001_012E;   // 判稳拍数过小，已钳到下限
    END_IF
ELSIF nSettleUse > DL_SETTLE_MAX THEN
    nSettleUse := DL_SETTLE_MAX;
    IF uErrorId = 16#0000_0000 THEN
        uErrorId := 16#0001_012E;   // 判稳拍数过大，已钳到上限
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜复位沿副作用：清跳变累计与判稳计时，故障退出由状态机自行处理
 *      Reset side effects: clear the toggle count and the settle timer
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q AND (eStateInt <> E_DL_BitWatchState.eFault) THEN
    uToggleCount := 0;
    nSteadyCnt   := 0;
    bSteady      := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜掉使能统一回空闲（边界 B3）：跳变累计不清，诊断证据保留
 *      Disable forces idle, the toggle counter is deliberately preserved
 *      故障态不放行：eFault 的复位沿判据必须每拍都有机会执行，若在此处无条件
 *      改写为 eIdle，CASE 只会进 eIdle 分支，故障态主体整拍被跳过、复位上升沿
 *      一拍即失（现场「停机后按复位无效」的典型成因）
 *      The fault phase is excluded so that its reset edge is never skipped
 *-----------------------------------------------------------------------------*)
IF (NOT bEnable) AND (eStateInt <> E_DL_BitWatchState.eFault) THEN
    eStateInt  := E_DL_BitWatchState.eIdle;
    bFirstScan := FALSE;
    nSteadyCnt := 0;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜主状态机（红线）：三成员全覆盖，兜底置故障并冻结输出
 *      Main state machine, every member covered, fallback latches a fault
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_BitWatchState.eIdle:
        (* 空闲：变化族清零，使能后装载快照再进采样 *)
        (* Idle: clear the change family, load the snapshot then start sampling *)
        FOR nIdx := DL_I_W TO DL_WORD_MAX DO
            auChangeMask[nIdx] := 16#0000_0000;
        END_FOR
        nChangeBits := 0;
        nFirstBit   := -1;
        bSteady     := FALSE;
        bAnyChange  := FALSE;

        IF bError THEN
            eStateInt := E_DL_BitWatchState.eFault;
        ELSIF bEnable THEN
            FOR nIdx := DL_I_W TO DL_WORD_MAX DO
                auPrev[nIdx] := 16#0000_0000;
                auXor[nIdx]  := 16#0000_0000;
            END_FOR
            FOR nIdx := DL_I_W TO nWordClamped DO
                auPrev[nIdx] := auWatch[nIdx];
            END_FOR
            bFirstScan := TRUE;
            nSteadyCnt := 0;
            eStateInt  := E_DL_BitWatchState.eSampling;
        END_IF

    E_DL_BitWatchState.eSampling:
        (* 采样：逐字异或，位扫描与首变位合并一趟 *)
        (* Sampling: per word XOR, bit counting and first bit search in one pass *)
        nChangeBits := 0;
        nFirstBit   := -1;
        uWeight     := 0;
        nGuard      := 0;
        bAnyChange  := FALSE;

        FOR nIdx := DL_I_W TO nWordClamped DO
            nGuard := nGuard + 1;
            IF nGuard > DL_GUARD_MAX THEN
                EXIT;   // 守卫触发：字循环异常，立刻停止本轮扫描
            END_IF
            auXor[nIdx]        := auWatch[nIdx] XOR auPrev[nIdx];
            auChangeMask[nIdx] := auXor[nIdx];
            FOR nBitScan := 0 TO (DL_BIT_WORD - 1) DO
                IF (auXor[nIdx] AND SHL(DWORD#1, INT_TO_UDINT(nBitScan))) <> 16#0000_0000 THEN
                    uWeight := uWeight + 1;
                    IF nFirstBit < 0 THEN
                        nFirstBit := (nIdx - DL_I_W) * DL_BIT_WORD + nBitScan;
                    END_IF
                END_IF
            END_FOR
        END_FOR

        (* 未监视的字掩码必须清零，防止调用方读到上一组态残留 *)
        (* Words outside the watched range must read zero, never stale bits *)
        FOR nIdx := DL_I_W TO DL_WORD_MAX DO
            IF nIdx > nWordClamped THEN
                auChangeMask[nIdx] := 16#0000_0000;
            END_IF
        END_FOR

        nChangeBits := UDINT_TO_INT(uWeight);
        bAnyChange  := nChangeBits > 0;

        (* 跳变累计（边界 B4）：首拍装载不累加，饱和不回绕 *)
        (* Toggle accumulation: never on the loading cycle, saturates instead of wrapping *)
        IF bFirstScan AND bAnyChange THEN
            IF (DL_TOGGLE_MAX - uToggleCount) < INT_TO_UDINT(nChangeBits) THEN
                uToggleCount := DL_TOGGLE_MAX;
                IF uErrorId = 16#0000_0000 THEN
                    uErrorId := 16#0001_012F;   // 累计饱和，须人工介入排查抖动源
                END_IF
            ELSE
                uToggleCount := uToggleCount + INT_TO_UDINT(nChangeBits);
            END_IF
        END_IF

        (* 判稳（边界 B5）：连续无变化拍数达到门限才置真 *)
        (* Settle detection: the flag rises only after the full quiet window *)
        IF bAnyChange THEN
            nSteadyCnt := 0;
            bSteady    := FALSE;
        ELSE
            IF nSteadyCnt < DL_SETTLE_MAX THEN
                nSteadyCnt := nSteadyCnt + 1;
            END_IF
            bSteady := nSteadyCnt >= nSettleUse;
        END_IF

        (* 快照更新放在输出之后，保证下一拍才参与比较 *)
        (* The snapshot is refreshed last so that it takes effect next cycle *)
        FOR nIdx := DL_I_W TO nWordClamped DO
            auPrev[nIdx] := auWatch[nIdx];
        END_FOR

    E_DL_BitWatchState.eFault:
        (* 故障：输出冻结，复位沿且组态恢复后才回空闲 *)
        (* Fault: outputs frozen, the reset edge returns to idle only when the config is sane *)
        bError     := TRUE;
        bSteady    := FALSE;
        bAnyChange := FALSE;
        nChangeBits := 0;
        nFirstBit   := -1;
        FOR nIdx := DL_I_W TO DL_WORD_MAX DO
            auChangeMask[nIdx] := 16#0000_0000;
        END_FOR
        IF fbTrigReset.Q AND (NOT bParamClamped) THEN
            bError      := FALSE;
            bFirstScan  := FALSE;
            nSteadyCnt  := 0;
            uToggleCount := 0;
            eStateInt   := E_DL_BitWatchState.eIdle;
        END_IF

    ELSE
        (* 非法状态兜底：在线改坏或跨版本不兼容时不隐式恢复，直接锁存 *)
        (* Illegal state fallback: never recover implicitly, latch and report *)
        eStateInt := E_DL_BitWatchState.eFault;
        bError    := TRUE;
        IF uErrorId = 16#0000_0000 THEN
            uErrorId := 16#0001_021B;   // 非法状态兜底码
        END_IF
        nChangeBits := 0;
        nFirstBit   := -1;
        bSteady     := FALSE;
        FOR nIdx := DL_I_W TO DL_WORD_MAX DO
            auChangeMask[nIdx] := 16#0000_0000;
        END_FOR

END_CASE

(*------------------------------------------------------------------------------
 * 段 6｜状态对外发布：单一出口，任何路径都确定
 *      Publish the state through a single exit, deterministic on every path
 *-----------------------------------------------------------------------------*)
eState := eStateInt;
END_FUNCTION_BLOCK
