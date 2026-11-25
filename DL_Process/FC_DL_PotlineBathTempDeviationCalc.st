// FC_DL_PotlineBathTempDeviationCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 初晶温度简化线性工程近似式（非相图严格解）：
        T_liq = 961.0 − 12.5·(CR − 2.0) − 3.5·(CaF2/100·100)/8.0 − 2.0·(MgF2/8.0)，
        过热度 = 槽温 − 初晶温度，> 12 °C 置 bOverheat。961.0 为 CR=2.0 无添加剂的基准初晶温度。
  邻件/码位: 与 FC_DL_PotlineBathRatioCalc 串联（前件出 CR）；与 FC_DL_PotlineMetalLevelCalc 同族不同域；
             16#0002_9216 = 非有限、CR 出 1.5~3.5 或添加剂为负拒收。
*)
FUNCTION FC_DL_PotlineBathTempDeviationCalc : REAL
VAR_INPUT
    fBathTemp : REAL := 960.0;      // 槽温（电解质温度）[°C] / Bath temperature [degC]
    fCR       : REAL := 2.30;       // 分子比 CR [-]，域 1.5~3.5 / Cryolite ratio [-]
    fCaF2     : REAL := 5.0;        // CaF2 质量分数 [%] / CaF2 mass fraction [%]
    fMgF2     : REAL := 0.5;        // MgF2 质量分数 [%] / MgF2 mass fraction [%]
END_VAR
VAR_OUTPUT
    fLiquidus  : REAL;              // 初晶温度 [°C] / Liquidus temperature [degC]
    fSuperheat : REAL;              // 过热度 [°C] / Superheat [degC]
    bOverheat  : BOOL;              // 过热告警（> 12 °C）[-] / Overheat alarm flag
    bValid     : BOOL;              // 结果有效回执 [-] / Result validity receipt
    uErrorId   : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fLiquidus := 0.0;               // 初晶温度缺省零 / Liquidus default zero
fSuperheat := 0.0;              // 过热度缺省零 / Superheat default zero
bOverheat := FALSE;             // 过热告警预清 / Overheat preset clear
bValid := FALSE;                // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;            // 事件码预清 / Event code preset clear
FC_DL_PotlineBathTempDeviationCalc := 0.0;  // 返回值缺省零（镜像过热度）/ Return default zero
// 段 1：非有限闸（四入参全枚举）/ Non-finite gate over all inputs
IF (fBathTemp <> fBathTemp) OR (fCR <> fCR) OR (fCaF2 <> fCaF2) OR (fMgF2 <> fMgF2)
   OR (ABS(fBathTemp) >= 3.0E38) OR (ABS(fCR) >= 3.0E38)
   OR (ABS(fCaF2) >= 3.0E38) OR (ABS(fMgF2) >= 3.0E38) THEN
    uErrorId := 16#0002_9216;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（CR 工艺区间，防线性式外推失真 + 添加剂非负）/ Domain gate
IF (fCR < 1.5) OR (fCR > 3.5) THEN
    uErrorId := 16#0002_9216;   // CR 出 1.5~3.5，线性式不适用 / CR out of valid range
    RETURN;
END_IF
IF (fCaF2 < 0.0) OR (fMgF2 < 0.0) THEN
    uErrorId := 16#0002_9216;   // 添加剂质量分数为负 / Negative additive fraction
    RETURN;
END_IF
// 段 3：主计算（线性初晶温度式 + 过热度；CaF2 保留原式形态）/ Main computation
fLiquidus := 961.0
           - 12.5 * (fCR - 2.0)
           - 3.5 * (fCaF2 / 100.0 * 100.0) / 8.0
           - 2.0 * (fMgF2 / 8.0);                               // 初晶温度线性近似 / Linear liquidus
fSuperheat := fBathTemp - fLiquidus;                            // 过热度 = 槽温 − 初晶 / Superheat
IF fSuperheat > 12.0 THEN
    bOverheat := TRUE;          // 过 12 °C 告警 / Alarm above 12 degC
END_IF
// 段 4：出口闸（双输出非有限复核）/ Outlet gate
IF (fLiquidus <> fLiquidus) OR (fSuperheat <> fSuperheat)
   OR (ABS(fLiquidus) >= 3.0E38) OR (ABS(fSuperheat) >= 3.0E38) THEN
    fLiquidus := 0.0;           // 复核失败回缺省 / Fallback on recheck failure
    fSuperheat := 0.0;          // 复核失败回缺省 / Fallback on recheck failure
    bOverheat := FALSE;         // 复核失败清告警 / Clear alarm on recheck failure
    uErrorId := 16#0002_9216;   // 出口非有限拒收 / Output non-finite reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_PotlineBathTempDeviationCalc := fSuperheat;   // 返回值镜像过热度 / Return mirrors superheat
END_FUNCTION
