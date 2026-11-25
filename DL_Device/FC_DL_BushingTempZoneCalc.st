// FC_DL_BushingTempZoneCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Device，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 漏板分区温度设定：偏移 = 梯度·(iZoneIndex − (iZoneCount−1)/2)，温度 = 基准 + 偏移；
        以区号相对中心对称取偏移，保证漏板横向温度对称分布。
  邻件/码位: 与 FC_DL_BushingDwellFlowCalc（温度→黏度→流量）上游衔接；
             16#0002_9221 = 非有限、区数非正、区号越界或温度出 1100~1350 °C 拒收。
*)
FUNCTION FC_DL_BushingTempZoneCalc : REAL
VAR_INPUT
    fBaseTemp  : REAL := 1250.0;    // 中心区设定温度 [°C] / Center zone setpoint [degC]
    fGradient  : REAL := 5.0;       // 区间梯度 [°C/区] / Per-zone gradient [degC/zone]
    iZoneIndex : INT := 0;          // 区号，0 起 [-] / Zone index, zero based
    iZoneCount : INT := 1;          // 总区数，域 > 0 [-] / Total zone count
END_VAR
VAR_OUTPUT
    fZoneTemp : REAL;               // 分区温度设定 [°C] / Zone temperature setpoint [degC]
    bValid    : BOOL;               // 结果有效回执 [-] / Result validity receipt
    uErrorId  : UDINT;              // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fCenter : REAL := 0.0;          // 中心区号（可为半整数）[-] / Center zone position
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fZoneTemp := 0.0;               // 分区温度缺省零 / Zone temperature default zero
bValid := FALSE;                // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;            // 事件码预清 / Event code preset clear
FC_DL_BushingTempZoneCalc := 0.0;       // 返回值缺省零（镜像分区温度）/ Return default zero
// 段 1：非有限闸（两实数入参；整数入参天然有限）/ Non-finite gate on real inputs
IF (fBaseTemp <> fBaseTemp) OR (fGradient <> fGradient)
   OR (ABS(fBaseTemp) >= 3.0E38) OR (ABS(fGradient) >= 3.0E38) THEN
    uErrorId := 16#0002_9221;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（区数为正 + 区号不越界）/ Domain gate
IF iZoneCount <= 0 THEN
    uErrorId := 16#0002_9221;   // 区数非正 / Non-positive zone count
    RETURN;
END_IF
IF (iZoneIndex < 0) OR (iZoneIndex >= iZoneCount) THEN
    uErrorId := 16#0002_9221;   // 区号越界 / Zone index out of range
    RETURN;
END_IF
// 段 3：主计算（中心对称偏移）/ Main computation
fCenter := INT_TO_REAL(iZoneCount - 1) / 2.0;                   // 中心区号 / Center zone position
fZoneTemp := fBaseTemp + fGradient * (INT_TO_REAL(iZoneIndex) - fCenter);   // 分区温度 / Zone temperature
// 段 4：出口闸（非有限复核 + 1100~1350 °C 工艺窗判定）/ Outlet gate
IF (fZoneTemp <> fZoneTemp) OR (ABS(fZoneTemp) >= 3.0E38) THEN
    fZoneTemp := 0.0;           // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9221;   // 出口非有限拒收 / Output non-finite reject
    RETURN;
END_IF
IF (fZoneTemp < 1100.0) OR (fZoneTemp > 1350.0) THEN
    uErrorId := 16#0002_9221;   // 信息级：温度出工艺窗 / Info: temperature out of window
    RETURN;                     // bValid 保持 FALSE / Validity stays false
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_BushingTempZoneCalc := fZoneTemp;     // 返回值镜像分区温度 / Return mirrors temperature
END_FUNCTION
