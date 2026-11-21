// =====================================================================
// FB_DL_RackDiagSummary.st
// 机架诊断汇总与首出定位（板级状态字聚合 + 首出三律 + 诊断风暴提示）
// Rack diagnostics aggregation with first-out location and storm hint
// 所属子库: DL_Device    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0003_03ED ~ 16#0003_03F1 (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: diagnostics, axioline, first-out, rack
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 5)
// 注: 板级诊断状态字经输入引脚注入, 零外部系统变量依赖, 与库内端口诊断
//     聚合件和单板诊断锁存件的契约字段语义一一对应, 同名位语义不复定义
// =====================================================================
FUNCTION_BLOCK FB_DL_RackDiagSummary
VAR_INPUT
    auBoardStat : ARRAY[1..8] OF WORD;  // 各板卡诊断状态字注入, 非 0 即该板存在故障 / Per-board status word injected, nonzero = fault
    bReset      : BOOL  := FALSE;       // 首出复位命令 / First-out reset command
END_VAR
VAR_OUTPUT
    uwFaultMask : WORD   := 0;          // 板级故障掩码, 位 0..7 对应板 1..8 / Board fault mask, bit0..7 = board 1..8
    uFirstBoard : USINT  := 0;          // 首出板号 1~8, 0 = 无 / First-out board 1..8, 0 = none
    uFirstCode  : UDINT  := 0;          // 首出板状态字快照回放 / First-out board status snapshot replay
    bStorm      : BOOL   := FALSE;      // 诊断风暴单拍标志, 不锁存不置故障级 / Storm single-cycle flag, info only
    eErr        : UDINT  := 16#0003_03ED;  // 错误码 / Error code
END_VAR
VAR
    rtrReset    : R_TRIG;               // 复位上升沿检测, 每拍无条件刷新 / Reset edge, refreshed every cycle
    uwPrevMask  : WORD   := 0;          // 上拍故障掩码快照 / Previous cycle mask snapshot
    uNewCnt     : USINT  := 0;          // 本拍新故障板数 / New fault board count this cycle
    wBit        : WORD   := 0;          // 位测试掩码 / Bit test mask
    bAllFault   : BOOL   := FALSE;      // 全板故障标记 / All-boards-fault flag
    uZi         : INT    := 1;          // 1..8 数组下标 / Array subscript 1..8
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0003_03ED 信息 全部板卡无故障
//   16#0003_03EE 信息 诊断风暴提示（单拍新故障板数不小于 4, 仅提示, 不进入故障级）
//   16#0003_03EF 故障 存在板卡故障（掩码非零）, 解除式 = 对应板状态字归零
//   16#0003_03F0 故障 首出锁定有效（板号与状态字快照持续回放）,
//                解除式 = bReset 上升沿 且 首出板故障位已消失
//   16#0003_03F1 故障 全部 8 块板卡故障（整架失效）
// ---------------------------------------------------------------------

// ---- 逐板故障判与掩码聚合 / Per-board fault judge and mask aggregation ----
uwFaultMask := 0;                   // 掩码复位 / Reset mask
FOR uZi := 1 TO 8 DO
    IF auBoardStat[uZi] <> 0 THEN
        uwFaultMask := uwFaultMask OR SHL(WORD#1, uZi - 1);     // 移位量 0..7 小于字宽, 合规 / Shift within word width
    END_IF
END_FOR

// ---- 本拍新故障板数差分（与上拍掩码比对）/ New fault count vs previous mask ----
uNewCnt := 0;                       // 新故障计数复位 / Reset new fault count
FOR uZi := 1 TO 8 DO
    wBit := SHL(WORD#1, uZi - 1);   // 当前板位掩码 / Current board bit mask
    IF (uwFaultMask AND wBit) <> 0 THEN
        IF (uwPrevMask AND wBit) = 0 THEN
            uNewCnt := uNewCnt + 1; // 本拍新出现故障的板 / Newly faulted board this cycle
        END_IF
    END_IF
END_FOR
bStorm := uNewCnt >= 4;             // 单拍新故障板数达 4 判风暴, 单拍标志当拍自清 / Storm if 4+ new per cycle
uwPrevMask := uwFaultMask;          // 快照更新供下拍差分 / Snapshot for next cycle

// ---- 复位沿实例无条件刷新 / Unconditional reset edge refresh ----
rtrReset(CLK := bReset);

// ---- 首出三律: 未锁存才仲裁, 同拍取最小板号, 解除在仲裁后 / First-out three laws ----
IF uFirstBoard = 0 THEN
    FOR uZi := 1 TO 8 DO
        IF (uFirstBoard = 0) AND ((uwFaultMask AND SHL(WORD#1, uZi - 1)) <> 0) THEN
            uFirstBoard := INT_TO_USINT(uZi);                   // 升序扫描取最小板号 / Ascending scan picks min board
            uFirstCode  := WORD_TO_UDINT(auBoardStat[uZi]);     // 锁存首出板状态字快照 / Latch status snapshot
        END_IF
    END_FOR
END_IF
// 解除式: bReset 上升沿 且 首出板故障位已消失 / Release: reset edge AND first-out fault bit gone
IF rtrReset.Q AND (uFirstBoard <> 0)
   AND ((uwFaultMask AND SHL(WORD#1, uFirstBoard - 1)) = 0) THEN
    uFirstBoard := 0;               // 释放首出板号 / Release first-out board
    uFirstCode  := 0;               // 清状态字快照 / Clear snapshot
END_IF

// ---- 全板故障判 / All-boards-fault judge ----
bAllFault := (uwFaultMask = 16#00FF);   // 8 位全 1 即整架失效 / All 8 bits set = rack failure

// ---- 错误码仲裁 / Error arbitration ----
IF bAllFault THEN
    eErr := 16#0003_03F1;           // 整架失效 / Rack failure
ELSIF uFirstBoard <> 0 THEN
    eErr := 16#0003_03F0;           // 首出锁定回放 / First-out latch replay
ELSIF uwFaultMask <> 0 THEN
    eErr := 16#0003_03EF;           // 存在板卡故障 / Board fault present
ELSIF bStorm THEN
    eErr := 16#0003_03EE;           // 诊断风暴提示 / Storm hint
ELSE
    eErr := 16#0003_03ED;           // 全部正常 / All normal
END_IF

END_FUNCTION_BLOCK
