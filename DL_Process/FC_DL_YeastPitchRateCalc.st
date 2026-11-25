// FC_DL_YeastPitchRateCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 酵母接种量：需活细胞 = 接种率·fPlato·麦汁体积[L] [百万个]，
        活细胞浓度 = 细胞数·活率/100 [百万/mL]（作可达性校核），
        酵母泥质量 = 需活细胞·1e6/1e9/1000 [kg]（按 1e9 cells/g 折算）。
        说明：需细胞数按派单口径体积按 hL→mL 换算后代入（非 mL 换算），与 1e9 cells/g 折算口径配套。
  邻件/码位: 与 FC_DL_WortAerationRateCalc 上游衔接（充氧量决定增殖倍率）；
             16#0002_9235 = 非有限、活率/体积/接种率/原浓非正或活细胞浓度近零拒收。
*)
FUNCTION FC_DL_YeastPitchRateCalc : REAL
VAR_INPUT
    fCellCount : REAL := 1200.0;    // 酵母细胞数 [百万/mL]，域 >= 0 / Cell count [million/mL]
    fViability : REAL := 95.0;      // 活率 [%]，域 (0, 100] / Viability [%]
    fWortVol   : REAL := 200.0;     // 麦汁量 [hL]，域 > 0 / Wort volume [hL]
    fPitchRate : REAL := 1.0;       // 目标接种率 [百万/mL/°P]，域 > 0，行业 0.75~1.0（R92 复裁修，原 10.0 致量级高 10×）/ Pitching rate
    fPlato     : REAL := 12.0;      // 麦汁浓度 [°P]，域 > 0 / Wort gravity [degP]
END_VAR
VAR_OUTPUT
    fYeastMass : REAL;              // 需酵母泥质量 [kg] / Required yeast slurry mass [kg]
    bValid     : BOOL;              // 结果有效回执 [-] / Result validity receipt
    uErrorId   : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fCellsNeed : REAL := 0.0;       // 需活细胞总数 [百万个] / Required live cells [million]
    fLiveConc  : REAL := 0.0;       // 活细胞浓度 [百万/mL] / Live concentration [million/mL]
    fVolumeMl  : REAL := 0.0;       // 麦汁体积 [mL] / Wort volume [mL]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fYeastMass := 0.0;                  // 酵母泥质量缺省零 / Yeast mass default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_YeastPitchRateCalc := 0.0;    // 返回值缺省零（镜像酵母泥质量）/ Return default zero
// 段 1：非有限闸（五入参全枚举）/ Non-finite gate over all inputs
IF (fCellCount <> fCellCount) OR (fViability <> fViability) OR (fWortVol <> fWortVol)
   OR (fPitchRate <> fPitchRate) OR (fPlato <> fPlato)
   OR (ABS(fCellCount) >= 3.0E38) OR (ABS(fViability) >= 3.0E38) OR (ABS(fWortVol) >= 3.0E38)
   OR (ABS(fPitchRate) >= 3.0E38) OR (ABS(fPlato) >= 3.0E38) THEN
    uErrorId := 16#0002_9235;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（活率/体积/接种率/原浓为正防除零，R4）/ Domain gate
IF (fViability <= 1.0E-6) OR (fViability > 100.0) THEN
    uErrorId := 16#0002_9235;   // 活率越界 / Viability out of range
    RETURN;
END_IF
IF fWortVol <= 1.0E-6 THEN
    uErrorId := 16#0002_9235;   // 麦汁量非正 / Non-positive wort volume
    RETURN;
END_IF
IF (fPitchRate <= 1.0E-6) OR (fPlato <= 1.0E-6) THEN
    uErrorId := 16#0002_9235;   // 接种率或原浓非正 / Non-positive rate or gravity
    RETURN;
END_IF
IF fCellCount < 0.0 THEN
    uErrorId := 16#0002_9235;   // 细胞数为负 / Negative cell count
    RETURN;
END_IF
// 段 3：主计算（需细胞数 → 活细胞浓度校核 → 酵母泥质量）/ Main computation
// 量纲（R92-修正）：接种率单位 百万/mL/°P，故体积须换算为 mL = hL × 100 L/hL × 1000 mL/L
// 说明：早期版本按 hL×100（即 L）代入，致需细胞数偏小 1000 倍、酵母泥质量同比例偏小
fVolumeMl := fWortVol * 100000.0;                               // 麦汁体积 [mL] / Wort volume [mL]
fCellsNeed := fPitchRate * fPlato * fVolumeMl;                  // 需活细胞 [百万个] / Required cells [million]
fLiveConc := fCellCount * fViability / 100.0;                   // 活细胞浓度 [百万/mL] / Live concentration
IF fLiveConc <= 1.0E-6 THEN
    uErrorId := 16#0002_9235;   // 活细胞浓度近零，接种无意义 / Live concentration near zero
    RETURN;
END_IF
fYeastMass := fCellsNeed * 1000000.0 / 1.0E9 / 1000.0;          // 酵母泥质量 [kg] / Slurry mass
// 段 4：出口闸（非有限复核 + 正数复核）/ Outlet gate
IF (fYeastMass <> fYeastMass) OR (ABS(fYeastMass) >= 3.0E38) OR (fYeastMass <= 0.0) THEN
    fYeastMass := 0.0;          // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9235;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_YeastPitchRateCalc := fYeastMass;         // 返回值镜像酵母泥质量 / Return mirrors mass
END_FUNCTION
