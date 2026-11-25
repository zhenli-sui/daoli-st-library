// FC_DL_WortAerationRateCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 麦汁溶解氧：供氧质量 = 风量·1.429·氧体积分数·吸收效率 [kg/h]（1.429 为标况氧密度），
        麦汁体积 = 流量[hL/h]·100 [L/h]，溶解氧 = 供氧/体积 [g/L]→×1000 [mg/L]（等值 ppm）。
  邻件/码位: 位于煮沸之后、接种之前；与 FC_DL_YeastPitchRateCalc 的接种量直接相关；
             16#0002_9232 = 非有限、麦汁流量非正、空气流量为负、效率或氧分数越界、氧超 20 mg/L。
*)
FUNCTION FC_DL_WortAerationRateCalc : REAL
VAR_INPUT
    fWortFlow  : REAL := 200.0;     // 麦汁流量 [hL/h]，域 > 0 / Wort flow [hL/h]
    fAirFlow   : REAL := 1.71;      // 无菌空气流量 [Nm³/h]，域 >= 0（缺省 1.71 → 约 9.0 mg/L 落 8~10 工艺窗，R92 复裁修）/ Sterile air flow [Nm^3/h]
    fO2Frac    : REAL := 0.21;      // 氧体积分数 [-]，域 (0, 1] / Oxygen fraction
    fAbsorbEff : REAL := 0.35;      // 吸收效率 [-]，域 (0, 1] / Absorption efficiency
END_VAR
VAR_OUTPUT
    fO2ppm   : REAL;                // 溶解氧 [mg/L]（等值 ppm）/ Dissolved oxygen [mg/L]
    bValid   : BOOL;                // 结果有效回执 [-] / Result validity receipt
    uErrorId : UDINT;               // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fVolLh : REAL := 0.0;           // 麦汁体积流量 [L/h] / Wort volume flow [L/h]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fO2ppm := 0.0;                      // 溶解氧缺省零 / Dissolved oxygen default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_WortAerationRateCalc := 0.0;  // 返回值缺省零（镜像溶解氧）/ Return default zero
// 段 1：非有限闸（四入参全枚举）/ Non-finite gate over all inputs
IF (fWortFlow <> fWortFlow) OR (fAirFlow <> fAirFlow)
   OR (fO2Frac <> fO2Frac) OR (fAbsorbEff <> fAbsorbEff)
   OR (ABS(fWortFlow) >= 3.0E38) OR (ABS(fAirFlow) >= 3.0E38)
   OR (ABS(fO2Frac) >= 3.0E38) OR (ABS(fAbsorbEff) >= 3.0E38) THEN
    uErrorId := 16#0002_9232;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（麦汁流量正防除零 + 空气非负 + 效率与氧分数区间，R4）/ Domain gate
IF fWortFlow <= 1.0E-6 THEN
    uErrorId := 16#0002_9232;   // 麦汁流量非正 / Non-positive wort flow
    RETURN;
END_IF
IF fAirFlow < 0.0 THEN
    uErrorId := 16#0002_9232;   // 空气流量为负 / Negative air flow
    RETURN;
END_IF
IF (fAbsorbEff <= 0.0) OR (fAbsorbEff > 1.0) THEN
    uErrorId := 16#0002_9232;   // 吸收效率越界 / Absorption efficiency out of range
    RETURN;
END_IF
IF (fO2Frac <= 0.0) OR (fO2Frac > 1.0) THEN
    uErrorId := 16#0002_9232;   // 氧体积分数越界 / Oxygen fraction out of range
    RETURN;
END_IF
// 段 3：主计算（供氧质量 → 麦汁体积 → 溶解氧）/ Main computation
fVolLh := fWortFlow * 100.0;                                    // 麦汁体积 [L/h] / Wort volume flow
fO2ppm := fAirFlow * 1.429 * fO2Frac * fAbsorbEff * 1000.0 / fVolLh * 1000.0;  // [mg/L] / Dissolved oxygen
// 段 4：出口闸（非有限复核 + 20 mg/L 工艺界判定）/ Outlet gate
IF (fO2ppm <> fO2ppm) OR (ABS(fO2ppm) >= 3.0E38) OR (fO2ppm < 0.0) THEN
    fO2ppm := 0.0;              // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9232;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
IF fO2ppm > 20.0 THEN
    uErrorId := 16#0002_9232;   // 信息级：溶解氧超 20 mg/L / Info: oxygen above bound
    RETURN;                     // bValid 保持 FALSE / Validity stays false
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_WortAerationRateCalc := fO2ppm;           // 返回值镜像溶解氧 / Return mirrors oxygen
END_FUNCTION
