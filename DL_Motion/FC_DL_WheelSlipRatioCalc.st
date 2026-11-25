// FC_DL_WheelSlipRatioCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Motion，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 轮速滑移率 den = MAX(|v_veh|, 0.05)，s = (v_wheel − v_veh)/den，
        |s| > fSlipLimit 置打滑告警；den 下限保证静止时不除零。
  邻件/码位: 与 FC_DL_DiffDriveOdometryCalc 同属底盘状态件（打滑时里程计可信度下降）；
             fSlipLimit 非法取 0.2 缺省属信息级不置错；16#0002_9207 = 非有限拒收。
*)
FUNCTION FC_DL_WheelSlipRatioCalc : REAL
VAR_INPUT
    fWheelSpeed   : REAL := 0.0;    // 轮缘线速度 [m/s] / Wheel rim speed [m/s]
    fVehicleSpeed : REAL := 0.0;    // 车体车速 [m/s] / Vehicle body speed [m/s]
    fSlipLimit    : REAL := 0.2;    // 打滑阈值 [-]，<=0 取 0.2 / Slip threshold [-]
END_VAR
VAR_OUTPUT
    fSlipRatio : REAL;              // 滑移率 s [-]，驱动正 / Slip ratio [-]
    bSlipAlarm : BOOL;              // 打滑告警 [-] / Slip alarm flag
    bValid     : BOOL;              // 结果有效回执 [-] / Result validity receipt
    uErrorId   : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fDen     : REAL := 0.0;         // 分母 MAX(|v_veh|, 0.05) [m/s] / Denominator [m/s]
    fLimitOk : REAL := 0.0;         // 生效阈值 [-] / Effective threshold [-]
    fAbsSlip : REAL := 0.0;         // 滑移率绝对值 [-] / Absolute slip ratio [-]
END_VAR
// 段 0：全路径出口安全缺省（滑移率零 + 告警清）/ Safe defaults
fSlipRatio := 0.0;              // 滑移率缺省零 / Slip ratio default zero
bSlipAlarm := FALSE;            // 告警预清 / Alarm preset clear
bValid := FALSE;                // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;            // 事件码预清 / Event code preset clear
FC_DL_WheelSlipRatioCalc := 0.0;        // 返回值缺省零 / Return default zero
// 段 1：非有限闸（三入参全枚举）/ Non-finite gate over all inputs
IF (fWheelSpeed <> fWheelSpeed) OR (fVehicleSpeed <> fVehicleSpeed) OR (fSlipLimit <> fSlipLimit)
   OR (ABS(fWheelSpeed) >= 3.0E38) OR (ABS(fVehicleSpeed) >= 3.0E38) OR (ABS(fSlipLimit) >= 3.0E38) THEN
    uErrorId := 16#0002_9207;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（阈值非法取缺省 + 分母 0.05 硬下限）/ Domain gate, R4 divide-by-zero guard
fLimitOk := fSlipLimit;                                         // 阈值先直取 / Take as-is
IF fLimitOk <= 0.0 THEN
    fLimitOk := 0.2;                                            // 非法阈值取缺省 / Fallback to default
END_IF
fDen := ABS(fVehicleSpeed);                                     // 分母取车速绝对值 / Denominator initial
IF fDen < 0.05 THEN
    fDen := 0.05;                                               // 静止时保底防除零 / Static guard
END_IF
// 段 3：主计算（滑移率 + 告警判定）/ Main computation
fSlipRatio := (fWheelSpeed - fVehicleSpeed) / fDen;             // s = (vw − vv)/den / Slip ratio
fAbsSlip := ABS(fSlipRatio);                                    // 取绝对值 / Absolute value
IF fAbsSlip > fLimitOk THEN
    bSlipAlarm := TRUE;                                         // 超阈值告警 / Alarm above threshold
END_IF
// 段 4：出口闸（滑移率非有限复核）/ Outlet gate
IF (fSlipRatio <> fSlipRatio) OR (ABS(fSlipRatio) >= 3.0E38) THEN
    fSlipRatio := 0.0;          // 复核失败回缺省 / Fallback on recheck failure
    bSlipAlarm := FALSE;        // 复核失败清告警 / Clear alarm on recheck failure
    uErrorId := 16#0002_9207;   // 出口非有限拒收 / Output non-finite reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_WheelSlipRatioCalc := fSlipRatio; // 返回值镜像滑移率 / Return mirrors slip ratio
END_FUNCTION
