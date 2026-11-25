// FC_DL_PotlineCurrentEfficiencyCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 电流效率反算：理论产铝 = I[kA]·0.3355·t[h] [kg]，CE = 100·实测/理论 [%]；
        CE > 105% 判计量异常（产物称重或电流计量故障）。
  邻件/码位: 与 FC_DL_PotlineAluminaFeedRateCalc 互为逆过程（本件由实测反推 CE）；
             16#0002_9215 = 非有限、理论量近零或 CE 越 105% 上限。
*)
FUNCTION FC_DL_PotlineCurrentEfficiencyCalc : REAL
VAR_INPUT
    fActualAlKg : REAL := 1000.0;   // 统计期内实测产铝 [kg]，域 >= 0 / Measured mass [kg]
    fCurrentKA  : REAL := 400.0;    // 系列电流 [kA]，域 > 0 / Line current [kA]
    fHours      : REAL := 24.0;     // 统计时长 [h]，域 > 0 / Statistics window [h]
END_VAR
VAR_OUTPUT
    fCE      : REAL;                // 电流效率 [%] / Current efficiency [%]
    bValid   : BOOL;                // 结果有效回执 [-] / Result validity receipt
    uErrorId : UDINT;               // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fTheory : REAL := 0.0;          // 理论产铝量 [kg] / Theoretical mass [kg]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fCE := 0.0;                     // 电流效率缺省零 / Current efficiency default zero
bValid := FALSE;                // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;            // 事件码预清 / Event code preset clear
FC_DL_PotlineCurrentEfficiencyCalc := 0.0;  // 返回值缺省零（镜像 CE）/ Return default zero
// 段 1：非有限闸（三入参全枚举）/ Non-finite gate over all inputs
IF (fActualAlKg <> fActualAlKg) OR (fCurrentKA <> fCurrentKA) OR (fHours <> fHours)
   OR (ABS(fActualAlKg) >= 3.0E38) OR (ABS(fCurrentKA) >= 3.0E38) OR (ABS(fHours) >= 3.0E38) THEN
    uErrorId := 16#0002_9215;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（实测非负 + 电流与时长为正防除零，R4）/ Domain gate
IF fActualAlKg < 0.0 THEN
    uErrorId := 16#0002_9215;   // 实测产铝为负 / Negative measured mass
    RETURN;
END_IF
IF (fCurrentKA <= 1.0E-6) OR (fHours <= 1.0E-6) THEN
    uErrorId := 16#0002_9215;   // 电流或时长非正 / Non-positive current or window
    RETURN;
END_IF
// 段 3：主计算（理论量 → CE）/ Main computation
fTheory := fCurrentKA * 0.3355 * fHours;                        // 理论产铝量 / Theoretical mass
IF fTheory <= 1.0E-6 THEN
    uErrorId := 16#0002_9215;   // 理论量近零，CE 不可解 / Theoretical mass too small
    RETURN;
END_IF
fCE := 100.0 * fActualAlKg / fTheory;                           // CE = 100·实测/理论 / Efficiency
// 段 4：出口闸（非有限复核 + 105% 计量异常判定）/ Outlet gate
IF (fCE <> fCE) OR (ABS(fCE) >= 3.0E38) THEN
    fCE := 0.0;                 // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9215;   // 出口非有限拒收 / Output non-finite reject
    RETURN;
END_IF
IF fCE > 105.0 THEN
    uErrorId := 16#0002_9215;   // 信息级：CE 超 105% 判计量异常 / Info: metrology anomaly
    RETURN;                     // bValid 保持 FALSE / Validity stays false
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_PotlineCurrentEfficiencyCalc := fCE;      // 返回值镜像 CE / Return mirrors efficiency
END_FUNCTION
