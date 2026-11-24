//==============================================================================
// 功能块：FB_DL_FormationChannelMgr ｜ 中文名称：化成/分容柜通道调度
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：化成/分容柜多通道调度：空闲通道分配（跳过隔离与故障通道）→ 批次启动命令 →
//           异常通道隔离锁存 → 批次完成/中止 → 台账计数（完成数/故障数）。
//           本件只做「调度层」，绝不内联充放电工步机（工步归序号 15 的 BatteryTestCycler）：
//           两者以布尔快照（abChBusy / abChFault / abChDone）与指令握手位
//           （abChCmdStart）交互，本件不产生任何电流/电压设定，也不判任何工艺终止条件。
//           无空闲通道属产线常态，挂起等待并给信息码，绝不升格为故障。
// 开源溯源 (Origin)：道莅原创实现（参考 公开工程惯例 分类与参数域）
// 单位表：通道数[路] / 通道号[号] / 计数[路] / 布尔快照[—]
// 错误码表：16#0005_040E 信息级（无空闲通道，分配挂起，不置 bError）/
//           16#0005_040F 信息级（异常通道已隔离并记账，锁存至 bReset，不置 bError）/
//           16#0005_0357 故障级（通道数非法/数组域越界，置 bError）/ 16#0005_0358
//           故障级（重复分配：上一分配尚未启动又发新请求，防双工步叠加烧电芯，置 bError）/
//           16#0005_0359 故障级兜底（状态机落 ELSE 非法状态，置 bError）。码位 16#0005 段。
// 状态机：E_DL_FormationChState（eIdle=0 待机 / eStandby=10 可分配待命 / eBatchRun=20
//           批次运行 / eBatchDone=30 批次完成 / eFault=99 故障兜底），CASE 含 ELSE 兜底，
//           ELSE 置 0359 且撤全通道启动指令、许可撤。
// 边界行为：① 无空闲通道 → bAllocOk := FALSE + 信息 040E，挂起等待不置故障（产线常态）；
//           ② 故障通道 → 隔离锁存 abChBlocked + 信息 040F（锁存至 bReset，防止自动复用
//           坏通道）；③ nChannelCount 域 1~16，越界 → 故障 0357；④ 上一分配未启动又发
//           新分配请求 → 故障 0358（防同一通道双工步叠加）；⑤ bBatchAbort → 撤全通道
//           启动指令 + bBatchAborted（中止优先于完成）；⑥ 失能 → 撤指令 + bValid := FALSE
//           （R72）；⑦ 数组一律按 nChannelCount 上界遍历（域已闸），不做越界下标访问。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.19，与 §4.15 件布尔握手分层）
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_FormationChState（归属 DL_Process，与 FB_DL_FormationChannelMgr 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FormationChState :
(
    eIdle      := 0,   // 待机：失能，全通道启动指令撤 / Idle, all channel start commands dropped
    eStandby   := 10,  // 待命：可接受分配请求 / Standby, allocation requests accepted
    eBatchRun  := 20,  // 批次运行：已启动通道在跑 / Batch running
    eBatchDone := 30,  // 批次完成：全部已启动通道报完成 / Batch completed
    eFault     := 99   // 故障兜底：通道数非法/重复分配/非法状态 / Fault fallback
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_FormationChannelMgr
 * 调用约定: 每个扫描周期无条件调用一次；通道快照由柜体通信层刷新。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_FormationChannelMgr
VAR_INPUT
    abChBusy         : ARRAY[0..15] OF BOOL;       // 通道忙快照（柜体层刷新）/ Channel busy snapshot
    abChFault        : ARRAY[0..15] OF BOOL;       // 通道故障快照 / Channel fault snapshot
    abChDone         : ARRAY[0..15] OF BOOL;       // 通道完成快照 / Channel done snapshot
    nChannelCount    : INT := 16;                  // 有效通道数 [路]，合法域 1~16 / Usable channel count, domain 1..16
    bAllocReq        : BOOL;                       // 分配请求（取上升沿）/ Allocation request, rising edge
    bBatchStart      : BOOL;                       // 批次启动（取上升沿）/ Batch start, rising edge
    bBatchAbort      : BOOL;                       // 批次中止（取上升沿，优先于完成）/ Batch abort, rising edge, outranks completion
    bEnable          : BOOL;                       // 总使能 / Master enable
    bReset           : BOOL;                       // 复位，上升沿清隔离锁存与台账 / Reset, rising edge clears the isolation latches and the ledger
END_VAR
VAR_OUTPUT
    nAllocatedCh     : INT;                        // 已分配通道号 [号]，-1 = 未分配 / Allocated channel, -1 = none
    bAllocOk         : BOOL;                       // 分配成功（单拍脉冲）/ Allocation succeeded, single-scan pulse
    abChBlocked      : ARRAY[0..15] OF BOOL;       // 通道隔离掩码（锁存至 bReset）/ Channel isolation mask, latched
    abChCmdStart     : ARRAY[0..15] OF BOOL;       // 通道启动指令 / Channel start command
    nDoneCount       : INT;                        // 完成通道数 [路] / Completed channels
    nFaultCount      : INT;                        // 故障通道数 [路] / Faulted channels
    bBatchDone       : BOOL;                       // 批次完成 / Batch completed
    bBatchAborted    : BOOL;                       // 批次已中止 / Batch aborted
    eErr             : UDINT;                      // 错误码，0 = 无错，码位 16#0005_040E 起信息级、16#0005_0357 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError           : BOOL;                       // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid           : BOOL;                       // 调度输出可用标志，失能/故障闸显式 FALSE / Schedule usable flag, explicit FALSE on disable/fault gates
    eState           : E_DL_FormationChState;      // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbReset          : R_TRIG;                     // 复位上升沿检测实例 / Reset rising edge detector
    fbAlloc          : R_TRIG;                     // 分配请求上升沿检测实例 / Allocation request rising edge detector
    fbStart          : R_TRIG;                     // 批次启动上升沿检测实例 / Batch start rising edge detector
    fbAbort          : R_TRIG;                     // 批次中止上升沿检测实例 / Batch abort rising edge detector
    abCmdInt         : ARRAY[0..15] OF BOOL;       // 启动指令内部副本 / Internal command copy
    nLoop            : INT;                        // 遍历索引 [—] / Loop index
    nFreeCh          : INT;                        // 候选空闲通道号 [号] / Candidate free channel
    bAllocPending    : BOOL;                       // 已分配但尚未启动（重复分配判据）/ Allocated but not started, the duplicate-allocation predicate
    bIsoNew          : BOOL;                       // 本拍新隔离通道标志 / A channel was newly isolated this scan
    bAnyCmd          : BOOL;                       // 存在启动指令 / Any start command active
    bAllDone         : BOOL;                       // 已启动通道全部报完成 / Every started channel reports done
    bNonFree         : BOOL;                       // 本拍无空闲通道 / No free channel this scan
    bFirstScan       : BOOL := TRUE;               // 上电首拍标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_FCM_CODE_INFO_1 : UDINT := 16#0005_040E;    // 信息级槽 1（无空闲通道，分配挂起） / info slot 1
    DL_FCM_CODE_INFO_2 : UDINT := 16#0005_040F;    // 信息级槽 2（异常通道已隔离并记账） / info slot 2
    DL_FCM_CODE_FLT_1  : UDINT := 16#0005_0357;    // 故障级槽 1（通道数非法/数组域越界） / fault slot 1
    DL_FCM_CODE_FLT_2  : UDINT := 16#0005_0358;    // 故障级槽 2（重复分配） / fault slot 2
    DL_FCM_CODE_FLT_3  : UDINT := 16#0005_0359;    // 故障级槽 3（非法状态兜底） / fault slot 3
    DL_FCM_CH_MAX      : INT := 16;                // 通道上限 [路]，必须等于数组维度 / Channel ceiling, must match the arrays
    DL_FCM_CH_MIN      : INT := 1;                 // 通道下限 [路] / Channel floor
    DL_FCM_IDX_NONE    : INT := -1;                // 无效通道号哨兵 [号] / Invalid channel sentinel
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：四条沿检测在任意分支之外周期调用
 *----------------------------------------------------------------------------*)
bAllocOk := FALSE;                                 // 分配成功为单拍脉冲，逐拍先清 / single-scan pulse cleared first
fbReset(CLK := bReset);                            // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
fbAlloc(CLK := bAllocReq);                         // 分配请求沿检测无条件刷新 / allocation edge refreshed unconditionally
fbStart(CLK := bBatchStart);                       // 批次启动沿检测无条件刷新 / start edge refreshed unconditionally
fbAbort(CLK := bBatchAbort);                       // 批次中止沿检测无条件刷新 / abort edge refreshed unconditionally

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）：清隔离锁存与台账
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState := E_DL_FormationChState.eIdle;
    eErr   := 16#0000_0000;                        // 复位清码 / reset clears the code
    bError := FALSE;                               // 复位清故障 / reset clears the fault
    bBatchDone := FALSE;                           // 批次完成标志清 / batch-done flag cleared
    bBatchAborted := FALSE;                        // 中止标志清 / aborted flag cleared
    bAllocPending := FALSE;                        // 待启动分配清 / pending allocation cleared
    nDoneCount := 0;                               // 完成计数清 / done count cleared
    nFaultCount := 0;                              // 故障计数清 / fault count cleared
    nAllocatedCh := DL_FCM_IDX_NONE;               // 分配通道清 / allocated channel cleared
    FOR nLoop := 0 TO DL_FCM_CH_MAX - 1 DO
        abChBlocked[nLoop] := FALSE;               // 隔离锁存清除 / isolation latch cleared
        abCmdInt[nLoop] := FALSE;                  // 启动指令内部副本清 / internal command cleared
        abChCmdStart[nLoop] := FALSE;              // 启动指令出口清 / command outlet cleared
    END_FOR
    bFirstScan := TRUE;                            // 重新首拍化 / re-initialize first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜通道数域闸（先闸后遍历：后续所有循环都以 nChannelCount 为上界）
 *----------------------------------------------------------------------------*)
IF (nChannelCount < DL_FCM_CH_MIN) OR (nChannelCount > DL_FCM_CH_MAX) THEN
    eState := E_DL_FormationChState.eFault;        // 进故障相 / enter fault state
    eErr   := DL_FCM_CODE_FLT_1;                   // 故障级：通道数非法/数组域越界 / fault: channel count out of range
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 调度不可用 / schedule unusable
    bAllocOk := FALSE;                             // 分配不成立 / allocation void
    nAllocatedCh := DL_FCM_IDX_NONE;               // 通道号清 / channel cleared
    FOR nLoop := 0 TO DL_FCM_CH_MAX - 1 DO
        abChCmdStart[nLoop] := FALSE;              // 全撤启动指令安全侧 / every command dropped
    END_FOR
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜通道隔离记账（锁存至 bReset）：故障通道一经发现立即隔离，
 *       并计入故障台账；隔离是「不再自动复用坏通道」的唯一手段
 *----------------------------------------------------------------------------*)
bIsoNew := FALSE;                                  // 本拍隔离标志初值 / isolation seed
nFaultCount := 0;                                  // 故障计数重数 / fault count recounted
FOR nLoop := 0 TO nChannelCount - 1 DO
    IF abChFault[nLoop] THEN
        nFaultCount := nFaultCount + 1;            // 故障通道计数 [路] / faulted channel counted
        IF NOT abChBlocked[nLoop] THEN
            abChBlocked[nLoop] := TRUE;            // 隔离锁存（首次）/ isolation latched on first detection
            bIsoNew := TRUE;                       // 本拍有新隔离 / newly isolated this scan
        END_IF
    END_IF
END_FOR

(*------------------------------------------------------------------------------
 * 段 5｜重复分配闸：上一分配已占通道但尚未启动批次，又来新的分配请求 → 0358
 *       （同一通道被两次工步叠加会烧电芯，属安全级）
 *----------------------------------------------------------------------------*)
IF fbAlloc.Q AND bAllocPending THEN
    eState := E_DL_FormationChState.eFault;        // 进故障相 / enter fault state
    eErr   := DL_FCM_CODE_FLT_2;                   // 故障级：重复分配 / fault: duplicate allocation
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 调度不可用 / schedule unusable
    bAllocOk := FALSE;                             // 分配不成立 / allocation void
    FOR nLoop := 0 TO nChannelCount - 1 DO
        abChCmdStart[nLoop] := FALSE;              // 全撤启动指令安全侧 / every command dropped
    END_FOR
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜分配：首个「未忙、未隔离、无故障」通道；无空闲 → 040E 挂起（不置故障）
 *----------------------------------------------------------------------------*)
nFreeCh := DL_FCM_IDX_NONE;                        // 候选通道初值 / candidate seed
FOR nLoop := 0 TO nChannelCount - 1 DO
    IF (NOT abChBlocked[nLoop]) AND (NOT abChFault[nLoop]) AND (NOT abChBusy[nLoop])
       AND (nFreeCh = DL_FCM_IDX_NONE) THEN
        nFreeCh := nLoop;                          // 取首个「未忙、未隔离、无故障」通道 [号] / first free channel wins
    END_IF
END_FOR
bNonFree := (nFreeCh = DL_FCM_IDX_NONE);           // 无空闲通道判据 / no-free-channel predicate
IF fbAlloc.Q AND (NOT bAllocPending) THEN
    IF bNonFree THEN
        bAllocOk := FALSE;                         // 分配不成立（挂起）/ allocation suspended
        nAllocatedCh := DL_FCM_IDX_NONE;           // 通道号保持无效 / channel stays invalid
        eErr := DL_FCM_CODE_INFO_1;                // 信息级：无空闲通道，分配挂起（产线常态，不置故障）/ info: no free channel, suspended
        bError := FALSE;                           // 信息级不置 bError（R45/R101）/ info never raises bError
    ELSE
        nAllocatedCh := nFreeCh;                   // 落定分配通道 [号] / the allocation settles
        bAllocOk := TRUE;                          // 分配成功单拍脉冲 / single-scan success pulse
        bAllocPending := TRUE;                     // 待启动（重复分配判据置位）/ pending, the duplicate predicate raises
        bBatchAborted := FALSE;                    // 新分配开启新批次：中止标志撤 / a new allocation clears the abort flag
        bBatchDone := FALSE;                       // 新分配开启新批次：完成标志撤 / a new allocation clears the done flag
        eErr := 16#0000_0000;                      // 分配成功不占码位 / no code on success
        bError := FALSE;                           // 无故障 / no fault
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜批次启动/中止握手：启动只作用于已分配通道；中止撤全部通道指令，
 *       且中止优先于完成判定（安全侧）
 *----------------------------------------------------------------------------*)
IF fbStart.Q AND bAllocPending AND (nAllocatedCh >= 0) AND (nAllocatedCh < nChannelCount) THEN
    abCmdInt[nAllocatedCh] := TRUE;                // 启动已分配通道 / start the allocated channel
    bAllocPending := FALSE;                        // 该分配已启动，解除待启动 / allocation consumed
    eState := E_DL_FormationChState.eBatchRun;     // 进批次运行相 / enter the batch-run state
END_IF
IF fbAbort.Q THEN
    FOR nLoop := 0 TO nChannelCount - 1 DO
        abCmdInt[nLoop] := FALSE;                  // 中止：撤全通道启动指令 / abort drops every command
    END_FOR
    bAllocPending := FALSE;                        // 待启动分配作废 / pending allocation voided
    bBatchAborted := TRUE;                         // 中止标志置位（优先于完成）/ aborted outranks done
    bBatchDone := FALSE;                           // 完成标志不得冒充 / done must not pose
    eState := E_DL_FormationChState.eStandby;      // 回待命 / back to standby
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜完成判定：曾有指令且已启动通道全部报完成 → 批次完成（bBatchAborted 时不成立）
 *----------------------------------------------------------------------------*)
bAnyCmd := FALSE;                                  // 指令存在标志初值 / command-presence seed
bAllDone := TRUE;                                  // 全部完成判据初值 / all-done seed
FOR nLoop := 0 TO nChannelCount - 1 DO
    IF abCmdInt[nLoop] THEN
        bAnyCmd := TRUE;                           // 存在启动指令 / a command exists
        IF NOT abChDone[nLoop] THEN
            bAllDone := FALSE;                     // 有通道未完成 / a channel is not done
        END_IF
    END_IF
END_FOR
IF bAnyCmd AND bAllDone AND (NOT bBatchAborted) THEN
    bBatchDone := TRUE;                            // 批次完成 / batch completed
    eState := E_DL_FormationChState.eBatchDone;    // 进完成相 / enter the done state
    FOR nLoop := 0 TO nChannelCount - 1 DO
        abCmdInt[nLoop] := FALSE;                  // 完成即撤指令（工步机自会收尾）/ commands dropped on completion
    END_FOR
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜台账计数：完成/故障通道数按 nChannelCount 上界遍历统计（域已闸）
 *----------------------------------------------------------------------------*)
nDoneCount := 0;                                   // 完成计数重数 / done count recounted
FOR nLoop := 0 TO nChannelCount - 1 DO
    IF abChDone[nLoop] THEN
        nDoneCount := nDoneCount + 1;              // 完成通道计数 [路] / completed channel counted
    END_IF
END_FOR

(*------------------------------------------------------------------------------
 * 段 10｜状态机：CASE 含 ELSE 兜底（非法状态 → 0359 + 全撤指令 + 许可撤）
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_FormationChState.eIdle:
        bValid := FALSE;                           // 失能闸显式不可用（R72）/ explicit FALSE on the disable gate
        bBatchDone := FALSE;                       // 完成标志撤 / done flag withdrawn
        bBatchAborted := FALSE;                    // 中止标志撤 / aborted flag withdrawn
        nAllocatedCh := DL_FCM_IDX_NONE;           // 分配通道清 / allocated channel cleared
        bAllocPending := FALSE;                    // 待启动分配清 / pending cleared
        eErr := 16#0000_0000;                      // 待机无错 / no error in idle
        bError := FALSE;                           // 待机无故障 / no fault in idle
        FOR nLoop := 0 TO DL_FCM_CH_MAX - 1 DO
            abCmdInt[nLoop] := FALSE;              // 待机撤指令 / commands dropped in idle
        END_FOR
        IF bEnable THEN
            eState := E_DL_FormationChState.eStandby;   // 使能进待命 / enable enters standby
            bFirstScan := FALSE;                   // 首拍标志清除 / first-scan flag cleared
        END_IF

    E_DL_FormationChState.eStandby:
        bValid := TRUE;                            // 调度可用 / schedule usable
        bError := FALSE;                           // 待命无故障 / no fault in standby
        IF bIsoNew THEN
            eErr := DL_FCM_CODE_INFO_2;            // 信息级：异常通道已隔离并记账 / info: channel isolated and booked
        ELSIF bNonFree AND fbAlloc.Q THEN
            eErr := DL_FCM_CODE_INFO_1;            // 信息级：无空闲通道，分配挂起 / info: no free channel, suspended
        ELSIF eErr <> DL_FCM_CODE_INFO_1 THEN
            eErr := 16#0000_0000;                  // 其余情况清码（挂起提示保持一拍）/ otherwise clear, keeping the hint for one scan
        END_IF
        IF NOT bEnable THEN
            eState := E_DL_FormationChState.eIdle; // 失能回待机 / disable returns to idle
            bValid := FALSE;                       // 失能闸显式不可用 / explicit FALSE on the disable gate
        END_IF

    E_DL_FormationChState.eBatchRun:
        bValid := TRUE;                            // 调度可用 / schedule usable
        bError := FALSE;                           // 运行相无故障 / no fault while running
        eErr := 16#0000_0000;                      // 运行相先清码 / clear the code first
        IF bIsoNew THEN
            eErr := DL_FCM_CODE_INFO_2;            // 信息级：异常通道已隔离 / info: channel isolated
        END_IF
        IF NOT bEnable THEN
            eState := E_DL_FormationChState.eIdle; // 失能回待机（退出条件一）/ disable, first exit
            bValid := FALSE;                       // 失能闸显式不可用 / explicit FALSE on the disable gate
            FOR nLoop := 0 TO nChannelCount - 1 DO
                abCmdInt[nLoop] := FALSE;          // 失能撤全部指令 / every command dropped
            END_FOR
        ELSIF NOT bAnyCmd THEN
            eState := E_DL_FormationChState.eStandby;   // 无指令回待命（退出条件二）/ no command left, second exit
        END_IF

    E_DL_FormationChState.eBatchDone:
        bValid := TRUE;                            // 完成台账可用 / the completed ledger is usable
        bBatchDone := TRUE;                        // 完成标志保持到下次分配 / done held until the next allocation
        bError := FALSE;                           // 完成相无故障 / no fault when done
        eErr := 16#0000_0000;                      // 完成无错 / no error when done
        IF NOT bEnable THEN
            eState := E_DL_FormationChState.eIdle; // 失能回待机（退出条件一）/ disable, first exit
            bValid := FALSE;                       // 失能闸显式不可用 / explicit FALSE on the disable gate
            bBatchDone := FALSE;                   // 完成标志撤 / done flag withdrawn
        ELSIF fbAlloc.Q THEN
            bBatchDone := FALSE;                   // 新分配即结束上一批（退出条件二）/ a new allocation closes the batch
            eState := E_DL_FormationChState.eStandby;   // 回待命 / back to standby
        END_IF

    E_DL_FormationChState.eFault:
        bValid := FALSE;                           // 故障闸显式不可用（R72）/ explicit FALSE on the fault gate
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        bAllocOk := FALSE;                         // 分配不成立 / allocation void
        bAllocPending := FALSE;                    // 待启动分配作废 / pending allocation voided
        FOR nLoop := 0 TO DL_FCM_CH_MAX - 1 DO
            abCmdInt[nLoop] := FALSE;              // 故障撤全通道指令（安全值而非上次值）/ every command dropped
        END_FOR
        IF eErr = 16#0000_0000 THEN
            eErr := DL_FCM_CODE_FLT_3;             // 入口无码时按非法状态兜底（R45：bError 必须有对应码）/ illegal-state fallback
        END_IF
        IF bEnable AND (nChannelCount >= DL_FCM_CH_MIN) AND (nChannelCount <= DL_FCM_CH_MAX) THEN
            eState := E_DL_FormationChState.eIdle; // 通道数合法且使能才回待机（退出条件 ≥2）/ recover only when the count is sane
        END_IF

    ELSE
        eState := E_DL_FormationChState.eFault;    // 非法状态兜底 / illegal-state fallback
        eErr := DL_FCM_CODE_FLT_3;                 // 故障级兜底：非法状态 / fault fallback: illegal state
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        bValid := FALSE;                           // 调度不可用 / schedule unusable
        bAllocOk := FALSE;                         // 分配不成立 / allocation void
        FOR nLoop := 0 TO DL_FCM_CH_MAX - 1 DO
            abCmdInt[nLoop] := FALSE;              // 全撤启动指令安全侧 / every command dropped
        END_FOR

END_CASE

(*------------------------------------------------------------------------------
 * 段 11｜出口装配：内部副本落到输出数组；失能/故障一律全撤（安全值而非上次值）
 *----------------------------------------------------------------------------*)
FOR nLoop := 0 TO DL_FCM_CH_MAX - 1 DO
    IF nLoop < nChannelCount AND bEnable AND bValid THEN
        abChCmdStart[nLoop] := abCmdInt[nLoop];    // 正常调度：透传内部副本 / pass the internal copy through
    ELSE
        abChCmdStart[nLoop] := FALSE;              // 失能/故障/域外：全撤安全侧 / drop everything, safe side
    END_IF
END_FOR
END_FUNCTION_BLOCK
