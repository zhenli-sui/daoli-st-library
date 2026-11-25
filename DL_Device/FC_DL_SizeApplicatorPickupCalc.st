// FC_DL_SizeApplicatorPickupCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Device，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 上胶率：干基量 = 浸润剂流量·固含量/100 [kg/h]（乳液密度按 1.0 kg/L，L/h 数值等同 kg/h），
        上胶率 = 100·干基量/丝束产出 [%]。
  邻件/码位: 与 FC_DL_StrandTensionAtWinderCalc 同属拉丝后端条件件（化学上胶 vs 力学张力）；
             16#0002_9225 = 非有限、产出非正、流量为负、固含量越界或上胶率出 0.1~3.0%。
*)
FUNCTION FC_DL_SizeApplicatorPickupCalc : REAL
VAR_INPUT
    fSizeFlow   : REAL := 40.0;     // 浸润剂流量 [L/h]，域 >= 0 / Size flow [L/h]
    fSizeSolids : REAL := 6.0;      // 固含量 [%]，域 (0, 100] / Solids content [%]
    fStrandRate : REAL := 120.0;    // 丝束产出 [kg/h]，域 > 0 / Strand output [kg/h]
END_VAR
VAR_OUTPUT
    fPickup  : REAL;                // 上胶率 [%]，工艺窗 0.1~3.0 / Size pickup [%]
    bValid   : BOOL;                // 结果有效回执 [-] / Result validity receipt
    uErrorId : UDINT;               // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fDryBasis : REAL := 0.0;        // 干基上胶量 [kg/h] / Dry size basis [kg/h]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fPickup := 0.0;                 // 上胶率缺省零 / Pickup default zero
bValid := FALSE;                // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;            // 事件码预清 / Event code preset clear
FC_DL_SizeApplicatorPickupCalc := 0.0;  // 返回值缺省零（镜像上胶率）/ Return default zero
// 段 1：非有限闸（三入参全枚举）/ Non-finite gate over all inputs
IF (fSizeFlow <> fSizeFlow) OR (fSizeSolids <> fSizeSolids) OR (fStrandRate <> fStrandRate)
   OR (ABS(fSizeFlow) >= 3.0E38) OR (ABS(fSizeSolids) >= 3.0E38) OR (ABS(fStrandRate) >= 3.0E38) THEN
    uErrorId := 16#0002_9225;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（产出为正防除零 + 流量非负 + 固含量区间，R4）/ Domain gate
IF fStrandRate <= 1.0E-6 THEN
    uErrorId := 16#0002_9225;   // 丝束产出非正，上胶率不可解 / Non-positive strand rate
    RETURN;
END_IF
IF fSizeFlow < 0.0 THEN
    uErrorId := 16#0002_9225;   // 流量为负 / Negative flow
    RETURN;
END_IF
IF (fSizeSolids <= 0.0) OR (fSizeSolids > 100.0) THEN
    uErrorId := 16#0002_9225;   // 固含量越界 / Solids content out of range
    RETURN;
END_IF
// 段 3：主计算（干基量 → 上胶率）/ Main computation
fDryBasis := fSizeFlow * fSizeSolids / 100.0;                   // 干基量 [kg/h] / Dry basis
fPickup := 100.0 * fDryBasis / fStrandRate;                     // 上胶率 [%] / Size pickup
// 段 4：出口闸（非有限复核 + 0.1~3.0% 工艺窗判定）/ Outlet gate
IF (fPickup <> fPickup) OR (ABS(fPickup) >= 3.0E38) OR (fPickup < 0.0) THEN
    fPickup := 0.0;             // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9225;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
IF (fPickup < 0.1) OR (fPickup > 3.0) THEN
    uErrorId := 16#0002_9225;   // 信息级：上胶率出工艺窗 / Info: pickup out of window
    RETURN;                     // bValid 保持 FALSE / Validity stays false
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_SizeApplicatorPickupCalc := fPickup;      // 返回值镜像上胶率 / Return mirrors pickup
END_FUNCTION
