// =====================================================================
// FB_DL_SiloLevelInterlock.st
// 料仓高低料位-输送联锁（防溢仓/空跑双联锁 + 卡料窗）
// Silo level interlock with conveyor, overflow/empty trips and jam window
// 所属子库: DL_Process    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0005_046C ~ 16#0005_0470 (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: process-control, silo, interlock, conveyor
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 7)
// 安全声明: 料位开关以假 = 未到达该料位为正常态（失电安全侧: 开关失电判为
//           未到达）; 输送允许输出安全侧为假; 各锁存位解除式均可达
// =====================================================================
FUNCTION_BLOCK FB_DL_SiloLevelInterlock
VAR_INPUT
    bHighLevel : BOOL := FALSE;     // 高料位开关, 真 = 到达高料位 / High level switch, TRUE = reached
    bLowLevel  : BOOL := FALSE;     // 低料位开关, 真 = 到达低料位 / Low level switch, TRUE = reached
    bConvRun   : BOOL := FALSE;     // 输送运行反馈 / Conveyor run feedback
    bRunDemand : BOOL := FALSE;     // 输送运行需求注入（上位流程给出, 供卡料判据使用）/ Run demand injected
    tJamWin    : TIME := T#5S;      // 卡料确认窗 T#100MS~T#60S / Jam confirm window [s]
    bReset     : BOOL := FALSE;     // 联锁复位命令 / Interlock reset command
END_VAR
VAR_OUTPUT
    bConvPermit   : BOOL := FALSE;  // 输送允许, 安全侧为假; 高料位联锁只停进料不停输送 / Conveyor permit, safe FALSE
    bOverflowTrip : BOOL := FALSE;  // 溢仓联锁锁存 / Overflow trip latch
    bEmptyTrip    : BOOL := FALSE;  // 空跑联锁锁存 / Empty-run trip latch
    bJamDet       : BOOL := FALSE;  // 卡料检测锁存 / Jam detection latch
    eErr          : UDINT := 16#0005_046C;  // 错误码 / Error code
END_VAR
VAR
    rtrReset  : R_TRIG;             // 复位上升沿检测, 每拍无条件刷新 / Reset edge, refreshed every cycle
    tonJam    : TON;                // 卡料确认定时器, 每拍无条件刷新 / Jam confirm timer, refreshed every cycle
    bConflict : BOOL := FALSE;      // 料位组态矛盾锁存 / Level configuration conflict latch
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0005_046C 信息 联锁正常（输送允许且无锁存事件）
//   16#0005_046D 故障 料位组态矛盾（高低料位同时有效）,
//                解除式 = 双开关恢复互斥 且 bReset 上升沿
//   16#0005_046E 故障 溢仓联锁（高料位: 停进料, 输送允许保持完成当前批次）,
//                解除式 = 高料位消失 且 bReset 上升沿
//   16#0005_046F 故障 空跑联锁（低料位: 停输送防空跑）,
//                解除式 = 低料位消失 且 bReset 上升沿
//   16#0005_0470 故障 卡料（运行需求持续而输送无反馈超窗）,
//                解除式 = 输送反馈恢复 且 bReset 上升沿
// ---------------------------------------------------------------------

// ---- 复位沿实例无条件刷新 / Unconditional reset edge refresh ----
rtrReset(CLK := bReset);

// ---- 组态矛盾与联锁锁存置位（锁存置位, 解除见各解除式）/ Conflict and trip latches ----
IF bHighLevel AND bLowLevel THEN
    bConflict := TRUE;              // 高低料位同时有效 = 组态矛盾 / Both levels active = conflict
END_IF
IF bHighLevel THEN
    bOverflowTrip := TRUE;          // 高料位置溢仓联锁 / High level sets overflow trip
END_IF
IF bLowLevel THEN
    bEmptyTrip := TRUE;             // 低料位置空跑联锁 / Low level sets empty trip
END_IF

// ---- 卡料确认定时器无条件周期刷新（有运行需求而无运行反馈才计时）/ Jam timer unconditional refresh ----
tonJam(IN := bRunDemand AND (NOT bConvRun) AND (NOT bJamDet)
        AND (NOT bConflict) AND (NOT bEmptyTrip),
       PT := tJamWin);
IF tonJam.Q THEN
    bJamDet := TRUE;                // 窗内持续无反馈判卡料 / No feedback through window = jam
END_IF

// ---- 锁存解除式（全部可达, R28 自证）/ Latch release paths, all reachable ----
IF rtrReset.Q AND (NOT (bHighLevel AND bLowLevel)) THEN
    bConflict := FALSE;             // 矛盾解除: 双开关恢复互斥 / Conflict release
END_IF
IF rtrReset.Q AND (NOT bHighLevel) THEN
    bOverflowTrip := FALSE;         // 溢仓解除: 高料位消失 / Overflow release
END_IF
IF rtrReset.Q AND (NOT bLowLevel) THEN
    bEmptyTrip := FALSE;            // 空跑解除: 低料位消失 / Empty release
END_IF
IF rtrReset.Q AND bConvRun THEN
    bJamDet := FALSE;               // 卡料解除: 运行反馈恢复 / Jam release
END_IF

// ---- 输送允许: 矛盾/空跑/卡料任一锁存即禁止; 溢仓联锁不停输送（完成当前批次）
//      Conveyor permit: blocked by conflict/empty/jam; overflow keeps conveyor ----
bConvPermit := (NOT bConflict) AND (NOT bEmptyTrip) AND (NOT bJamDet);

// ---- 错误码仲裁（联锁动作与告警码分离输出）/ Error arbitration ----
IF bConflict THEN
    eErr := 16#0005_046D;           // 组态矛盾 / Configuration conflict
ELSIF bOverflowTrip THEN
    eErr := 16#0005_046E;           // 溢仓联锁 / Overflow trip
ELSIF bEmptyTrip THEN
    eErr := 16#0005_046F;           // 空跑联锁 / Empty trip
ELSIF bJamDet THEN
    eErr := 16#0005_0470;           // 卡料 / Jam
ELSE
    eErr := 16#0005_046C;           // 联锁正常 / Interlock normal
END_IF

END_FUNCTION_BLOCK
