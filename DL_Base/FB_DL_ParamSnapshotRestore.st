// FB_DL_ParamSnapshotRestore v1.0.0
// 开源溯源：self-cleanroom / 参数管理族
(*
  道莅工业代码库 | DL_Base | FB_DL_ParamSnapshotRestore
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 参数快照/一键回滚：双缓冲（快照写入非活动缓冲区并切换），回滚时
        把最近有效快照整组复制回输出组；快照序号累加供追溯
  邻件关系: 与 DeviceParamVerify / DeviceParamWrite（参数校验/写入）同族 ——
            差异点：校验/写入件为单参数级在线动作，本件为整组快照与
            历史回滚（双缓冲），互不重叠
  时序契约: bSnap 上升沿写快照（双缓冲切换）；bRestore 上升沿回滚最近快照；
            两沿同拍时快照优先（先存后回滚，本拍回滚的是新快照）
*)
FUNCTION_BLOCK FB_DL_ParamSnapshotRestore
VAR_INPUT
    bSnap      : BOOL := FALSE;              // 快照触发（上升沿）/ Snapshot trigger, rising edge
    bRestore   : BOOL := FALSE;              // 回滚触发（上升沿）/ Restore trigger, rising edge
    aParamIn   : ARRAY[1..16] OF REAL;       // 参数输入组 [工程单位] / Parameter input group
    nCount     : INT := 16;                  // 有效参数个数 [个]，域 1..16 / Valid parameter count
END_VAR
VAR_OUTPUT
    aParamOut  : ARRAY[1..16] OF REAL;       // 参数输出组（回滚目标）[工程单位] / Parameter output group, restore target
    nSnapSeq   : UDINT;                      // 快照序号（每次快照 +1）/ Snapshot sequence number
    bSnapDone  : BOOL;                       // 快照完成脉冲（单拍自清）/ Snapshot done pulse, one cycle
    bRestDone  : BOOL;                       // 回滚完成脉冲（单拍自清）/ Restore done pulse, one cycle
    bHasSnap   : BOOL;                       // 存在可用快照 [-] / Valid snapshot available
    bValid     : BOOL;                       // 组态有效回执 [-] / Config validity receipt
    bError     : BOOL;                       // 故障标志（计数非法）/ Fault flag (invalid count)
    uErrorId   : UDINT;                      // 事件码，0 = 无事件；16#0002_2101 = 计数非法 / Event code
END_VAR
VAR
    rtrSnap    : R_TRIG;                     // 快照沿检测（每拍无条件刷新）/ Snapshot edge, refreshed every cycle
    rtrRest    : R_TRIG;                     // 回滚沿检测（每拍无条件刷新）/ Restore edge, refreshed every cycle
    aBufA      : ARRAY[1..16] OF REAL;       // 缓冲区 A [工程单位] / Buffer A
    aBufB      : ARRAY[1..16] OF REAL;       // 缓冲区 B [工程单位] / Buffer B
    bActiveA   : BOOL;                       // 最近快照在缓冲区 A [-] / Latest snapshot in buffer A
    i          : INT;                        // 复制循环索引 [个] / Copy loop index
    nCnt       : INT;                        // 钳位后生效个数 [个] / Effective clamped count
END_VAR

// —— 段 0：实例无条件刷新 + 输出缺省 —— //
rtrSnap(CLK := bSnap);                       // 快照沿每拍刷新 / Snapshot edge refreshed
rtrRest(CLK := bRestore);                    // 回滚沿每拍刷新 / Restore edge refreshed
bSnapDone := FALSE;                          // 快照脉冲单拍自清 / Snapshot pulse self-clearing
bRestDone := FALSE;                          // 回滚脉冲单拍自清 / Restore pulse self-clearing

// —— 段 1：计数域闸（下标判界，R4） —— //
bValid := (nCount >= 1) AND (nCount <= 16);  // 计数域 1..16 / Count domain
IF NOT bValid THEN
    bError   := TRUE;                        // 故障级：计数非法 / Fault level: illegal count
    uErrorId := 16#0002_2101;                // 故障码（21xx 步进）/ Fault code
    RETURN;                                  // 非法计数不动作 / No action on illegal count
END_IF
bError   := FALSE;                           // 组态恢复：故障清零（解除路径）/ Fault cleared
uErrorId := 16#0000;                         // 事件码清零 / Event code cleared
nCnt := nCount;                              // 生效个数 / Effective count

// —— 段 2：快照沿（双缓冲：写入非活动区并切换；同拍快照优先于回滚） —— //
IF rtrSnap.Q THEN
    IF bActiveA THEN                         // 当前最近快照在 A：写入 B / Latest in A: write to B
        FOR i := 1 TO nCnt DO                 // 逐元素复制（i ≤ nCnt ≤ 16 判界安全）/ Copy elements, index safe
            aBufB[i] := aParamIn[i];
        END_FOR
        bActiveA := FALSE;                   // 最近快照切到 B / Latest now in B
    ELSE                                     // 当前最近快照在 B：写入 A / Latest in B: write to A
        FOR i := 1 TO nCnt DO
            aBufA[i] := aParamIn[i];
        END_FOR
        bActiveA := TRUE;                    // 最近快照切到 A / Latest now in A
    END_IF
    bHasSnap := TRUE;                        // 存在可用快照 / Snapshot available
    nSnapSeq := nSnapSeq + 1;                // 快照序号累加（UDINT 回绕无害）/ Sequence increments
    bSnapDone := TRUE;                       // 快照完成脉冲 / Snapshot done pulse
END_IF

// —— 段 3：回滚沿（复制最近快照到输出组） —— //
IF rtrRest.Q AND bHasSnap THEN               // 有快照才回滚 / Restore only with snapshot
    IF bActiveA THEN                         // 最近快照在 A / Latest in A
        FOR i := 1 TO nCnt DO
            aParamOut[i] := aBufA[i];
        END_FOR
    ELSE                                     // 最近快照在 B / Latest in B
        FOR i := 1 TO nCnt DO
            aParamOut[i] := aBufB[i];
        END_FOR
    END_IF
    bRestDone := TRUE;                       // 回滚完成脉冲 / Restore done pulse
END_IF
END_FUNCTION_BLOCK
