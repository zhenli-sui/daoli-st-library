(*
  DL Factory R83 | FC_DL_ForkEntryClearanceCalc
  功能：按货位内宽、托盘宽与对中偏差算入叉左右余量，并判叉体能否进槽。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_ForkEntryClearanceCalc : REAL
VAR_INPUT
    fSlotWidMm   : REAL; // 货位立柱内侧净宽 [mm] / Slot clear width between uprights [mm]
    fPalletWidMm : REAL; // 托盘宽度 [mm] / Pallet width [mm]
    fForkWidMm   : REAL; // 货叉外廓总宽 [mm] / Fork overall width [mm]
    fOffsetMm    : REAL; // 堆垛机对中偏差（正=偏右）[mm] / Centring offset, + = right [mm]
END_VAR
VAR_OUTPUT
    fLeftMm     : REAL; // 左侧余量 [mm] / Left clearance [mm]
    fRightMm    : REAL; // 右侧余量 [mm] / Right clearance [mm]
    fMinClearMm : REAL; // 双侧最小余量（决定能否入叉）[mm] / Governing minimum clearance [mm]
    xOk         : BOOL; // 入叉判定（最小余量不低于 25 mm）/ Entry decision, at least 25 mm
    xValid      : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fGovernWidMm : REAL; // 实际占宽（托盘宽与叉宽取大者）[mm] / Governing occupied width [mm]
    fHalfGapMm   : REAL; // 名义单侧余量 [mm] / Nominal per-side clearance [mm]
END_VAR
fLeftMm := 0.0; fRightMm := 0.0; fMinClearMm := 0.0; xOk := FALSE; xValid := FALSE; // 出口预置
// 非有限拦截 + 量纲自检（R20/R21）
IF NOT (fSlotWidMm > -1.0E30 AND fSlotWidMm < 1.0E30) OR NOT (fPalletWidMm > -1.0E30 AND fPalletWidMm < 1.0E30) OR NOT (fForkWidMm > -1.0E30 AND fForkWidMm < 1.0E30) OR NOT (fOffsetMm > -1.0E30 AND fOffsetMm < 1.0E30) OR fSlotWidMm <= 0.0 OR fPalletWidMm <= 0.0 OR fForkWidMm <= 0.0 THEN
    FC_DL_ForkEntryClearanceCalc := -1.0; RETURN;  // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 实际占宽：托盘与叉体取大者（叉宽超托盘时由叉体决定余量）
IF fPalletWidMm >= fForkWidMm THEN
    fGovernWidMm := fPalletWidMm;   // 托盘占宽为主 [mm] / Pallet governs
ELSE
    fGovernWidMm := fForkWidMm;     // 叉体占宽为主 [mm] / Fork governs
END_IF
// 名义单侧余量：(净宽 - 占宽) ÷ 2，负值表示物理上装不进去
fHalfGapMm := (fSlotWidMm - fGovernWidMm) / 2.0; // 名义单侧余量 [mm] / Nominal per-side clearance
// 左右余量：对中偏差按正负拆分，同量纲（mm）加减，分解后之和恒等于 2×名义余量
fLeftMm  := fHalfGapMm - fOffsetMm;   // 左余量 [mm]，偏右时变小 / Left clearance [mm]
fRightMm := fHalfGapMm + fOffsetMm;   // 右余量 [mm]，偏右时变大 / Right clearance [mm]
// 双侧最小余量：决定可否入叉的瓶颈侧
IF fLeftMm <= fRightMm THEN
    fMinClearMm := fLeftMm;         // 左侧为瓶颈 [mm] / Left is governing
ELSE
    fMinClearMm := fRightMm;        // 右侧为瓶颈 [mm] / Right is governing
END_IF
// 入叉判定：最小余量不低于 25 mm（AGV/堆垛机通用安全余量）
xOk    := fMinClearMm >= 25.0;      // 入叉布尔 / Entry boolean
xValid := TRUE; FC_DL_ForkEntryClearanceCalc := fMinClearMm; // 返回最小余量 [mm] / Return clearance
END_FUNCTION
