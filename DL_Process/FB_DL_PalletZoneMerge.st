// =====================================================================
// FB_DL_PalletZoneMerge.st
// 码垛前多线合流积放（多区占用去抖 + 释放互斥节流 + 双模式仲裁 + 上区补跑）
// Pallet merge accumulation across zones with mutex release throttling
// 所属子库: DL_Process    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0005_0471 ~ 16#0005_0475 (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: packaging, conveyor, merge, accumulation
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 8)
// 语义声明: 释放输出为单拍脉冲（当拍自清）, 下游合流区须自行锁存接续;
//           上区补跑语义: 被节流/等待的占用区在条件恢复后按同一仲裁律
//           逐拍继续放出, 不丢件; 光电闪断经关断延时去抖, 短闪不丢占用
// =====================================================================
FUNCTION_BLOCK FB_DL_PalletZoneMerge
VAR_INPUT
    bEnable    : BOOL  := FALSE;    // 使能 / Enable
    abZiOcc    : ARRAY[1..4] OF BOOL;   // 各区光电占用信号 / Zone photoeye occupancy
    bMergeReq  : BOOL  := FALSE;    // 合流释放请求 / Merge release request
    tZiGapMin  : TIME  := T#500MS;  // 相邻两次释放最小间隔, 兼作占用去抖保持窗 / Min release gap, also occupancy hold
    uMergeMode : USINT := 1;        // 合流模式: 1 = 顺序, 2 = 先到先走 / Merge mode
END_VAR
VAR_OUTPUT
    abZiRelease : ARRAY[1..4] OF BOOL;  // 各区释放脉冲输出（单拍自清）/ Zone release pulse, one cycle
    bMergeBusy  : BOOL := FALSE;    // 合流进行中（有请求且有占用区等待）/ Merge busy
    uReleaseSeq : USINT := 0;       // 累计释放次数台账 / Cumulative release count
    eErr        : UDINT := 16#0005_0471;  // 错误码 / Error code
END_VAR
VAR
    aTofOcc    : ARRAY[1..4] OF TOF;    // 各区占用关断延时去抖, 每拍无条件刷新 / Zone occupancy TOF debounce, refreshed every cycle
    aRtrOcc    : ARRAY[1..4] OF R_TRIG; // 各区占用到达沿检测, 每拍无条件刷新 / Zone arrival edges, refreshed every cycle
    tonGap     : TON;               // 释放节流窗定时器, 每拍无条件刷新 / Release throttle timer, refreshed every cycle
    abOccDb    : ARRAY[1..4] OF BOOL;   // 去抖后的区占用 / Debounced occupancy
    auiArrSeq  : ARRAY[1..4] OF USINT;  // 各区到达序号, 0 = 未登记 / Zone arrival sequence, 0 = none
    uArrCnt    : USINT := 0;        // 到达序号累计器 / Arrival sequence counter
    bGapHold   : BOOL := FALSE;     // 节流窗保持标志 / Throttle window hold flag
    bModeOk    : BOOL := FALSE;     // 合流模式合法标记 / Merge mode legal flag
    uSel       : USINT := 0;        // 本拍选中释放区号 / Selected zone this cycle
    uMinSeq    : USINT := 0;        // 最小到达序号临时量 / Min arrival sequence temporary
    uZi        : INT   := 1;        // 1..4 数组下标 / Array subscript 1..4
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0005_0471 信息 合流正常（空闲或释放完成）
//   16#0005_0472 故障 合流模式非法冻结（模式值非 1 或 2, 冻结全部释放输出）,
//                解除式 = 模式值恢复合法域
//   16#0005_0473 信息 请求悬空（有合流请求但暂无去抖占用区可释放）
//   16#0005_0474 信息 释放节流窗激活（距上次释放不足最小间隔）
//   16#0005_0475 信息 待机未使能
// ---------------------------------------------------------------------

// ---- 模式合法性 / Merge mode legality ----
IF (uMergeMode = 1) OR (uMergeMode = 2) THEN
    bModeOk := TRUE;                // 合法模式 / Legal mode
ELSE
    bModeOk := FALSE;               // 非法模式冻结 / Illegal mode frozen
END_IF

// ---- 未使能待机处理 / Standby when disabled ----
IF NOT bEnable THEN
    FOR uZi := 1 TO 4 DO
        auiArrSeq[uZi] := 0;        // 清到达序号 / Clear arrival sequence
    END_FOR
    uArrCnt  := 0;                  // 清序号累计器 / Clear counter
    bGapHold := FALSE;              // 清节流标志 / Clear throttle flag
END_IF

// ---- 去抖与到达沿实例无条件周期刷新（4 实例逐个全刷新, 不进 IF 分支）
//      Unconditional refresh of all 4 TOF and 4 R_TRIG instances ----
FOR uZi := 1 TO 4 DO
    aTofOcc[uZi](IN := abZiOcc[uZi], PT := tZiGapMin);  // 闪断保持: 短于间隔窗的闪断不丢占用 / Flicker hold
    aRtrOcc[uZi](CLK := abZiOcc[uZi]);                  // 到达沿 / Arrival edge
    abOccDb[uZi] := aTofOcc[uZi].Q;                     // 去抖后占用 / Debounced occupancy
END_FOR

// ---- 到达序号登记（先到先走模式的次序依据）/ Arrival sequence registration ----
FOR uZi := 1 TO 4 DO
    IF aRtrOcc[uZi].Q AND (auiArrSeq[uZi] = 0) THEN
        uArrCnt := uArrCnt + 1;     // 序号推进 / Advance sequence
        auiArrSeq[uZi] := uArrCnt;  // 登记该区到达序号 / Register arrival
    END_IF
    IF NOT abOccDb[uZi] THEN
        auiArrSeq[uZi] := 0;        // 占用消失清序号 / Clear sequence on vacancy
    END_IF
END_FOR
// 序号累计器回绕防护: 临近上界按当前占用区号序重排 / Counter wrap protection: renumber by zone order
IF uArrCnt >= 250 THEN
    uArrCnt := 0;                   // 累计器归零 / Reset counter
    FOR uZi := 1 TO 4 DO
        auiArrSeq[uZi] := 0;        // 全清后重排 / Clear then renumber
    END_FOR
    FOR uZi := 1 TO 4 DO
        IF abOccDb[uZi] THEN
            uArrCnt := uArrCnt + 1;
            auiArrSeq[uZi] := uArrCnt;  // 按区号序重排占用区 / Renumber occupied zones
        END_IF
    END_FOR
END_IF

// ---- 释放节流窗定时器无条件刷新 / Unconditional throttle timer refresh ----
tonGap(IN := bGapHold, PT := tZiGapMin);
IF tonGap.Q THEN
    bGapHold := FALSE;              // 节流窗完成, 允许下一次释放 / Window done, allow next release
END_IF

// ---- 释放仲裁: 同拍至多一区（互斥）; 多区请求取最小区号或最先到达区
//      Release arbitration: at most one zone per cycle, mutex guaranteed ----
uSel := 0;                          // 选中区清零 / Clear selection
IF bEnable AND bModeOk AND bMergeReq AND (NOT bGapHold) THEN
    IF uMergeMode = 1 THEN
        // 顺序模式: 升序取最小区号 / Sequential: lowest zone number
        FOR uZi := 1 TO 4 DO
            IF (uSel = 0) AND abOccDb[uZi] THEN
                uSel := INT_TO_USINT(uZi);  // 选中该区 / Select zone
            END_IF
        END_FOR
    ELSE
        // 先到先走模式: 取最小到达序号 / First-arrived: min arrival sequence
        uMinSeq := 0;               // 0 表示尚未找到候选 / 0 = no candidate yet
        FOR uZi := 1 TO 4 DO
            IF abOccDb[uZi] THEN
                IF (uMinSeq = 0) OR (auiArrSeq[uZi] < uMinSeq) THEN
                    uMinSeq := auiArrSeq[uZi];  // 更新最小序号 / Update min sequence
                    uSel := INT_TO_USINT(uZi);  // 选中该区 / Select zone
                END_IF
            END_IF
        END_FOR
    END_IF
END_IF

// ---- 释放执行（单拍脉冲, 选中区置真一拍后由下拍缺省清零）
//      Release execution: one-cycle pulse on selected zone ----
FOR uZi := 1 TO 4 DO
    abZiRelease[uZi] := FALSE;      // 缺省全断 / Default all off
END_FOR
IF (uSel >= 1) AND (uSel <= 4) THEN
    abZiRelease[uSel] := TRUE;      // 选中区发释放脉冲（下标已越界守卫）/ Selected zone release pulse, index guarded
    bGapHold := TRUE;               // 启动节流窗 / Start throttle window
    uReleaseSeq := uReleaseSeq + 1; // 释放台账推进 / Advance release ledger
    auiArrSeq[uSel] := 0;           // 该区序号清零待再到达 / Clear its sequence
END_IF

// ---- 合流忙输出 / Merge busy output ----
bMergeBusy := FALSE;                // 缺省不忙 / Default idle
FOR uZi := 1 TO 4 DO
    IF bMergeReq AND abOccDb[uZi] THEN
        bMergeBusy := TRUE;         // 有请求且有占用区等待 / Request with waiting zone
    END_IF
END_FOR

// ---- 错误码仲裁 / Error arbitration ----
IF NOT bEnable THEN
    eErr := 16#0005_0475;           // 待机未使能 / Standby
ELSIF NOT bModeOk THEN
    eErr := 16#0005_0472;           // 模式非法冻结 / Illegal mode frozen
ELSIF bMergeReq AND (NOT bMergeBusy) THEN
    eErr := 16#0005_0473;           // 请求悬空 / Request dangling
ELSIF bGapHold AND bMergeReq THEN
    eErr := 16#0005_0474;           // 节流窗激活 / Throttle active
ELSE
    eErr := 16#0005_0471;           // 合流正常 / Merge normal
END_IF

END_FUNCTION_BLOCK
