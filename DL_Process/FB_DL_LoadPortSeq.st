(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LoadPortSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : LoadPort 载具对接顺控：FOUP 在位 → 对接 → 开门 →
 *                         门阀握手 → Wafer Map 逐位比对（25 片位，差异计数）→
 *                         放行/拒收 → 完成。开门与握手各自超时；任意相异常 →
 *                         ERR 并安全收拢（关门 + 撤放行）。数组界常量提取防越界。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_LoadPortPhase / TYPE E_DL_LoadPortErr /
 *                         FUNCTION_BLOCK FB_DL_LoadPortSeq
 * 依赖 (Depends)        : 无 DL_ 内部依赖；Standard.library TON/R_TRIG 实例
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         数组 25 元素固定下界常量 ｜ 枚举成员全部显式赋值 ｜
 *                         TON/R_TRIG 每周期无条件调用（仅输入条件化）｜
 *                         CASE 含 ELSE 兜底至安全态（关门 + 撤放行）｜ 相超时用状态判定
 * 错误码表 (Codes)      : 16#0005_0421 IDLE
 *                         16#0005_0422 对接/开合进行中
 *                         16#0005_0423 信息级 映射不符（差异计数见 nMapDiff，拒收）
 *                         16#0005_0424 故障级 开合或握手超时（共用反证句）
 *                         16#0005_0425 放行完成
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 4
 * 验收向量 (Acceptance) : 期望/读回 25 位全等 → bMapMatch + bReleaseOk + 0425；
 *                         第 7 位差异 → nMapDiff=1 且 0423 拒收；开门超时 → 0424
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_LoadPortPhase（归属 DL_Process，LoadPort 顺控相）
 *----------------------------------------------------------------------------*)
TYPE E_DL_LoadPortPhase :
(
    eLpIdle      := 0,    // 空闲待启动 / Idle, waiting for a start
    eLpDock      := 10,   // 对接相（载具压紧）/ Docking phase
    eLpOpen      := 20,   // 开门相（等开门到位）/ Door-open phase
    eLpHandshake := 30,   // 门阀握手相 / Door-valve handshake phase
    eLpMapCmp    := 40,   // 片位映射比对相 / Wafer map comparison phase
    eLpRelease   := 50,   // 放行相 / Release phase
    eLpDone      := 60,   // 完成相 / Done phase
    eLpErr       := 99    // 故障相（安全收拢）/ Error phase, safe collapse
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_LoadPortErr（归属 DL_Process，与 FB_DL_LoadPortSeq 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_LoadPortErr :
(
    eLpErrIdle   := 16#0005_0421,   // IDLE / Idle
    eLpErrMove   := 16#0005_0422,   // 对接/开合进行中 / Docking or opening in progress
    eLpErrMap    := 16#0005_0423,   // 信息级：映射不符（差异计数输出）/ Info: map mismatch
    eLpErrTmo    := 16#0005_0424,   // 故障级：开合或握手超时 / Fault: open or handshake timeout
    eLpErrRel    := 16#0005_0425    // 放行完成 / Release completed
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_LoadPortSeq
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_LoadPortSeq
VAR_INPUT
    bFoupPresent  : BOOL;                       // FOUP 在位传感器 / FOUP present sensor
    bDoorOpenOk   : BOOL;                       // 开门到位反馈 / Door-open feedback
    bValveAck     : BOOL;                       // 门阀握手应答 / Door-valve handshake acknowledge
    aMapExpect    : ARRAY[1..25] OF BOOL;       // 期望片位图（25 槽）/ Expected wafer map, 25 slots
    aMapRead      : ARRAY[1..25] OF BOOL;       // 读回片位图（25 槽）/ Read-back wafer map, 25 slots
    tDoorMax      : TIME := T#10S;              // 开门超时 [秒]，默认 10 / Door-open timeout [s]
    tHandMax      : TIME := T#5S;               // 握手超时 [秒]，默认 5 / Handshake timeout [s]
    bStart        : BOOL;                       // 启动（上升沿）/ Start, rising edge
    bReset        : BOOL;                       // 复位（上升沿）/ Reset, rising edge
END_VAR
VAR_OUTPUT
    ePhase        : E_DL_LoadPortPhase;         // 顺控当前相 / Current sequence phase
    bMapMatch     : BOOL;                       // 片位映射一致 / Wafer map matched
    bReleaseOk    : BOOL;                       // 放行许可 / Release permission
    nMapDiff      : UINT;                       // 映射差异数 [片位] / Map difference count [slots]
    bDoorOpenCmd  : BOOL;                       // 开门指令 / Door-open command
    bDoorCloseCmd : BOOL;                       // 关门指令（安全收拢）/ Door-close command, safe collapse
    eErr          : E_DL_LoadPortErr;           // 错误码 / Error code
END_VAR
VAR
    fbStartTrig   : R_TRIG;                     // 启动沿实例（无条件调用）/ Start edge instance
    fbResetTrig   : R_TRIG;                     // 复位沿实例（无条件调用）/ Reset edge instance
    tonDoor       : TON;                        // 开门超时定时器（无条件调用）/ Door-open timeout timer
    tonHand       : TON;                        // 握手超时定时器（无条件调用）/ Handshake timeout timer
    i             : INT;                        // 数组循环索引 / Array loop index
    uDiffAcc      : UINT;                       // 差异计数累加 [片位] / Difference accumulator [slots]
END_VAR
VAR CONSTANT
    DL_LP_SLOT_MIN : INT  := 1;                 // 片位数组下界（常量提取）/ Slot array lower bound
    DL_LP_SLOT_MAX : INT  := 25;                // 片位数组上界（25 槽固定）/ Slot array upper bound, 25 fixed
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜沿检测/TON 实例每周期无条件调用（仅输入条件化）：相超时用状态判定
 *----------------------------------------------------------------------------*)
fbStartTrig(CLK := bStart);                           // 启动沿检测无条件刷新 / start edge refreshed unconditionally
fbResetTrig(CLK := bReset);                           // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
tonDoor(IN := (ePhase = E_DL_LoadPortPhase.eLpOpen), PT := tDoorMax);        // 开门超时计时 / door timeout timing
tonHand(IN := (ePhase = E_DL_LoadPortPhase.eLpHandshake), PT := tHandMax);   // 握手超时计时 / handshake timeout timing

(*------------------------------------------------------------------------------
 * 段 2｜复位沿：安全收拢并回 IDLE
 *----------------------------------------------------------------------------*)
IF fbResetTrig.Q THEN
    ePhase := E_DL_LoadPortPhase.eLpIdle;             // 回空闲 / back to idle
    bReleaseOk := FALSE;                              // 放行撤 / release dropped
    bMapMatch := FALSE;                               // 一致标志撤 / match dropped
    bDoorOpenCmd := FALSE;                            // 开门指令撤 / open dropped
    bDoorCloseCmd := TRUE;                            // 关门指令（安全侧收拢）/ close command, safe collapse
    nMapDiff := 0;                                    // 差异计数清 / difference cleared
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜启动沿：仅在 IDLE/DONE 且 FOUP 在位允许启动
 *----------------------------------------------------------------------------*)
IF fbStartTrig.Q THEN
    IF ((ePhase = E_DL_LoadPortPhase.eLpIdle) OR (ePhase = E_DL_LoadPortPhase.eLpDone)) AND bFoupPresent THEN
        ePhase := E_DL_LoadPortPhase.eLpDock;         // 进对接相 / enter dock phase
        bReleaseOk := FALSE;                          // 放行撤 / release dropped
        bMapMatch := FALSE;                           // 一致标志撤 / match dropped
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜顺控状态机：CASE 含 ELSE 兜底（ELSE → 安全收拢：关门 + 撤放行）
 *----------------------------------------------------------------------------*)
CASE ePhase OF

    E_DL_LoadPortPhase.eLpIdle:
        bDoorOpenCmd := FALSE;                        // 空闲：开门撤 / open dropped
        bDoorCloseCmd := TRUE;                        // 空闲：关门保持（安全侧）/ close held, safe side
        bReleaseOk := FALSE;                          // 空闲：放行撤 / release dropped
        eErr := E_DL_LoadPortErr.eLpErrIdle;          // 码 0421 / code idle

    E_DL_LoadPortPhase.eLpDock:
        bDoorOpenCmd := FALSE;                        // 对接：开门撤 / open dropped
        bDoorCloseCmd := TRUE;                        // 对接：关门保持（压紧）/ close held for docking
        bReleaseOk := FALSE;                          // 对接：放行撤 / release dropped
        eErr := E_DL_LoadPortErr.eLpErrMove;          // 码 0422 / code in progress
        ePhase := E_DL_LoadPortPhase.eLpOpen;          // 对接完成进开门相 / docking done, enter open

    E_DL_LoadPortPhase.eLpOpen:
        bDoorOpenCmd := TRUE;                         // 开门指令置位 / open command set
        bDoorCloseCmd := FALSE;                       // 关门指令撤 / close dropped
        bReleaseOk := FALSE;                          // 放行撤 / release dropped
        eErr := E_DL_LoadPortErr.eLpErrMove;          // 码 0422 / code in progress
        IF bDoorOpenOk THEN
            ePhase := E_DL_LoadPortPhase.eLpHandshake;   // 开门到位：进握手相 / door open: enter handshake
        ELSIF tonDoor.Q THEN
            bDoorOpenCmd := FALSE;                    // 超时：撤开门指令 / timeout: drop open
            bDoorCloseCmd := TRUE;                    // 超时：安全收拢关门 / timeout: close for safety
            ePhase := E_DL_LoadPortPhase.eLpErr;      // 进故障相 / enter error
            eErr := E_DL_LoadPortErr.eLpErrTmo;       // 故障级：开门超时 / fault: door timeout
        END_IF

    E_DL_LoadPortPhase.eLpHandshake:
        bDoorOpenCmd := TRUE;                         // 握手：开门保持 / open held
        bDoorCloseCmd := FALSE;                       // 握手：关门撤 / close dropped
        bReleaseOk := FALSE;                          // 握手：放行撤 / release dropped
        eErr := E_DL_LoadPortErr.eLpErrMove;          // 码 0422 / code in progress
        IF bValveAck THEN
            ePhase := E_DL_LoadPortPhase.eLpMapCmp;   // 握手应答：进比对相 / ack: enter compare
        ELSIF tonHand.Q THEN
            bDoorOpenCmd := FALSE;                    // 超时：撤开门指令 / timeout: drop open
            bDoorCloseCmd := TRUE;                    // 超时：安全收拢关门 / timeout: close for safety
            ePhase := E_DL_LoadPortPhase.eLpErr;      // 进故障相 / enter error
            eErr := E_DL_LoadPortErr.eLpErrTmo;       // 故障级：握手超时（与开门超时共用，反证句：输出同为收拢+故障级）/ fault: handshake timeout
        END_IF

    E_DL_LoadPortPhase.eLpMapCmp:
        bDoorOpenCmd := TRUE;                         // 比对：开门保持 / open held
        bDoorCloseCmd := FALSE;                       // 比对：关门撤 / close dropped
        uDiffAcc := 0;                                // 差异计数清零 / difference cleared
        FOR i := DL_LP_SLOT_MIN TO DL_LP_SLOT_MAX DO
            IF aMapExpect[i] <> aMapRead[i] THEN
                uDiffAcc := uDiffAcc + 1;             // 逐位比对差异累加 [片位] / per-slot difference accumulation
            END_IF
        END_FOR
        nMapDiff := uDiffAcc;                         // 差异计数输出 [片位] / difference count output
        IF uDiffAcc = 0 THEN
            bMapMatch := TRUE;                        // 全等：映射一致 / identical: matched
            bReleaseOk := TRUE;                       // 放行许可置位 / release granted
            ePhase := E_DL_LoadPortPhase.eLpRelease;  // 进放行相 / enter release
            eErr := E_DL_LoadPortErr.eLpErrRel;       // 码 0425 / code release
        ELSE
            bMapMatch := FALSE;                       // 不符：映射不一致 / mismatch
            bReleaseOk := FALSE;                      // 不符：拒收 / rejected
            ePhase := E_DL_LoadPortPhase.eLpErr;      // 进故障相（拒收收拢）/ enter error, reject
            eErr := E_DL_LoadPortErr.eLpErrMap;       // 信息级：映射不符（含差异计数）/ info: map mismatch
        END_IF

    E_DL_LoadPortPhase.eLpRelease:
        bDoorOpenCmd := TRUE;                         // 放行：开门保持（取片）/ open held for pick
        bDoorCloseCmd := FALSE;                       // 放行：关门撤 / close dropped
        bReleaseOk := TRUE;                           // 放行许可保持 / release held
        bMapMatch := TRUE;                            // 映射一致保持 / match held
        eErr := E_DL_LoadPortErr.eLpErrRel;           // 码 0425 / code release
        ePhase := E_DL_LoadPortPhase.eLpDone;          // 放行完成进完成相 / release done, enter done

    E_DL_LoadPortPhase.eLpDone:
        bDoorOpenCmd := FALSE;                        // 完成：开门撤 / open dropped
        bDoorCloseCmd := TRUE;                        // 完成：关门收拢 / close for safe collapse
        bReleaseOk := FALSE;                          // 完成：放行撤（本循环结束）/ release dropped
        eErr := E_DL_LoadPortErr.eLpErrRel;           // 码 0425（完成态沿用放行码）/ code release held

    E_DL_LoadPortPhase.eLpErr:
        bDoorOpenCmd := FALSE;                        // 故障相：开门撤 / open dropped
        bDoorCloseCmd := TRUE;                        // 故障相：关门安全收拢 / close for safe collapse
        bReleaseOk := FALSE;                          // 故障相：放行撤 / release dropped
        bMapMatch := FALSE;                           // 故障相：一致标志撤 / match dropped

    ELSE
        ePhase := E_DL_LoadPortPhase.eLpErr;          // 非法相兜底 / illegal-phase fallback
        bDoorOpenCmd := FALSE;                        // 安全态：开门撤 / open dropped, safe side
        bDoorCloseCmd := TRUE;                        // 安全态：关门收拢 / close for safe collapse
        bReleaseOk := FALSE;                          // 安全态：放行撤 / release dropped
        bMapMatch := FALSE;                           // 安全态：一致标志撤 / match dropped
        eErr := E_DL_LoadPortErr.eLpErrTmo;           // 兜底码（超时段，反证句：输出同为收拢+撤放行）/ fallback code

END_CASE
END_FUNCTION_BLOCK
