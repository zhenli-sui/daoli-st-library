// FC_DL_PotlineAluminaFeedRateCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 产铝率 = I[kA]·0.3355·CE/100 [kg/h]（0.3355 为铝电化学当量），
        Al2O3 理论量 = 产铝·1.889，下料率 = 理论量/(1 − 损耗率/100)。
  邻件/码位: 与 FC_DL_PotlineCurrentEfficiencyCalc 互为逆过程（本件由 CE 正算产物与下料）；
             16#0002_9212 = 非有限、CE 越界或损耗率 ≥ 100% 拒收。
*)
FUNCTION FC_DL_PotlineAluminaFeedRateCalc : REAL
VAR_INPUT
    fCurrentKA  : REAL := 400.0;    // 系列电流 [kA]，域 > 0 / Line current [kA]
    fCE         : REAL := 93.0;     // 电流效率 [%]，域 (0, 100] / Current efficiency [%]
    fLossRatio  : REAL := 2.0;      // 氧化铝损耗率 [%]，域 [0, 100) / Alumina loss ratio [%]
END_VAR
VAR_OUTPUT
    fAlRate      : REAL;            // 产铝速率 [kg/h] / Aluminium production rate [kg/h]
    fAluminaRate : REAL;            // 氧化铝下料率 [kg/h] / Alumina feed rate [kg/h]
    bValid       : BOOL;            // 结果有效回执 [-] / Result validity receipt
    uErrorId     : UDINT;           // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fLossFrac : REAL := 0.0;        // 损耗率小数 [-] / Loss ratio as fraction [-]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fAlRate := 0.0;                 // 产铝速率缺省零 / Production rate default zero
fAluminaRate := 0.0;            // 下料率缺省零 / Feed rate default zero
bValid := FALSE;                // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;            // 事件码预清 / Event code preset clear
FC_DL_PotlineAluminaFeedRateCalc := 0.0;    // 返回值缺省零（镜像产铝）/ Return default zero
// 段 1：非有限闸（三入参全枚举）/ Non-finite gate over all inputs
IF (fCurrentKA <> fCurrentKA) OR (fCE <> fCE) OR (fLossRatio <> fLossRatio)
   OR (ABS(fCurrentKA) >= 3.0E38) OR (ABS(fCE) >= 3.0E38) OR (ABS(fLossRatio) >= 3.0E38) THEN
    uErrorId := 16#0002_9212;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（电流正 / CE 区间 / 损耗率上界防除零，R4）/ Domain gate
IF fCurrentKA <= 1.0E-6 THEN
    uErrorId := 16#0002_9212;   // 电流非正 / Non-positive current
    RETURN;
END_IF
IF (fCE <= 0.0) OR (fCE > 100.0) THEN
    uErrorId := 16#0002_9212;   // 电流效率越界 / Current efficiency out of range
    RETURN;
END_IF
IF (fLossRatio < 0.0) OR (fLossRatio >= 100.0) THEN
    uErrorId := 16#0002_9212;   // 损耗率越界（分母 1−loss 近零）/ Loss ratio out of range
    RETURN;
END_IF
// 段 3：主计算（产物 → 理论氧化铝 → 损耗补正下料）/ Main computation
fAlRate := fCurrentKA * 0.3355 * fCE / 100.0;                   // 产铝 = I·当量·CE / Production rate
fLossFrac := fLossRatio / 100.0;                                // 损耗率转小数 / Loss as fraction
fAluminaRate := fAlRate * 1.889 / (1.0 - fLossFrac);            // 损耗补正下料 / Loss-compensated feed
// 段 4：出口闸（双输出非有限复核 + 非负复核）/ Outlet gate
IF (fAlRate <> fAlRate) OR (fAluminaRate <> fAluminaRate)
   OR (ABS(fAlRate) >= 3.0E38) OR (ABS(fAluminaRate) >= 3.0E38)
   OR (fAlRate < 0.0) OR (fAluminaRate < 0.0) THEN
    fAlRate := 0.0;             // 复核失败回缺省 / Fallback on recheck failure
    fAluminaRate := 0.0;        // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9212;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_PotlineAluminaFeedRateCalc := fAlRate;    // 返回值镜像产铝速率 / Return mirrors rate
END_FUNCTION
