// FC_DL_AgvChargeDockAlignCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Motion，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 充电桩对桩对齐律：bAligned = (|Δy| ≤ tolY) AND (|Δa| ≤ tolA)；
        v = MIN(0.15, 0.3·dist)（dist 负则 0）；ω = 1.5·Δa 限幅 ±0.4 rad/s；
        已对齐强制零速零转（防贴桩抖动）。
  邻件/码位: 与 FC_DL_AgvSpeedLimitProfileCalc 分工（末端对桩 vs 巡航限速）；
             DOCK 相超时由 FB_DL_AgvPathTrackSeq 处理；16#0002_9209 = 域外或非有限拒收。
*)
FUNCTION FC_DL_AgvChargeDockAlignCalc : REAL
VAR_INPUT
    fOffsetY   : REAL := 0.0;       // 横向偏差 Δy [m]，左正 / Lateral offset [m]
    fAngleErr  : REAL := 0.0;       // 角度偏差 Δa [rad]，左正 / Angular error [rad]
    fDist      : REAL := 1.0;       // 到桩距离 [m] / Distance to dock [m]
    fAlignTolY : REAL := 0.02;      // 横向容差 [m]，负值归零 / Lateral tolerance [m]
    fAlignTolA : REAL := 0.03;      // 角度容差 [rad]，负值归零 / Angular tolerance [rad]
END_VAR
VAR_OUTPUT
    fSpeedCmd   : REAL;             // 前进速度指令 [m/s] / Forward speed command [m/s]
    fYawRateCmd : REAL;             // 转向角速度指令 [rad/s] / Yaw rate command [rad/s]
    bAligned    : BOOL;             // 对齐到位标志 [-] / Alignment reached flag
    bValid      : BOOL;             // 结果有效回执 [-] / Result validity receipt
    uErrorId    : UDINT;            // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fTolY   : REAL := 0.0;          // 生效横向容差 [m] / Effective lateral tolerance [m]
    fTolA   : REAL := 0.0;          // 生效角度容差 [rad] / Effective angular tolerance [rad]
    fYawRaw : REAL := 0.0;          // 未限幅转向指令 [rad/s] / Unsaturated yaw [rad/s]
END_VAR
// 段 0：全路径出口安全缺省（零速零转）/ Safe defaults, zero speed and zero yaw
fSpeedCmd := 0.0;               // 速度指令缺省零 / Speed command default zero
fYawRateCmd := 0.0;             // 转向指令缺省零 / Yaw command default zero
bAligned := FALSE;              // 对齐标志预清 / Alignment preset clear
bValid := FALSE;                // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;            // 事件码预清 / Event code preset clear
FC_DL_AgvChargeDockAlignCalc := 0.0;    // 返回值缺省零（镜像速度）/ Return default zero
// 段 1：非有限闸（五入参全枚举）/ Non-finite gate over all inputs
IF (fOffsetY <> fOffsetY) OR (fAngleErr <> fAngleErr) OR (fDist <> fDist)
   OR (fAlignTolY <> fAlignTolY) OR (fAlignTolA <> fAlignTolA)
   OR (ABS(fOffsetY) >= 3.0E38) OR (ABS(fAngleErr) >= 3.0E38) OR (ABS(fDist) >= 3.0E38)
   OR (ABS(fAlignTolY) >= 3.0E38) OR (ABS(fAlignTolA) >= 3.0E38) THEN
    uErrorId := 16#0002_9209;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（容差负值归零，防误判永远对齐）/ Domain gate on tolerances
fTolY := fAlignTolY;                                            // 横向容差直取 / Take tolerance
IF fTolY < 0.0 THEN
    fTolY := 0.0;                                               // 负容差归零 / Clamp negative
END_IF
fTolA := fAlignTolA;                                            // 角度容差直取 / Take tolerance
IF fTolA < 0.0 THEN
    fTolA := 0.0;                                               // 负容差归零 / Clamp negative
END_IF
// 段 3：主计算（对齐判定 + 速度/转向生成）/ Main computation
IF (ABS(fOffsetY) <= fTolY) AND (ABS(fAngleErr) <= fTolA) THEN
    bAligned := TRUE;                                           // 双容差内判对齐 / Aligned
END_IF
IF NOT bAligned THEN
    IF fDist > 0.0 THEN
        fSpeedCmd := 0.3 * fDist;                               // 距离比例降速 / Distance proportional speed
        IF fSpeedCmd > 0.15 THEN
            fSpeedCmd := 0.15;                                  // 限到对桩上限 / Clamp to docking ceiling
        END_IF
    END_IF
    fYawRaw := 1.5 * fAngleErr;                                 // 角度比例转向 / Angular proportional yaw
    IF fYawRaw > 0.4 THEN
        fYawRateCmd := 0.4;                                     // 上饱和 / Upper saturation
    ELSIF fYawRaw < -0.4 THEN
        fYawRateCmd := -0.4;                                    // 下饱和 / Lower saturation
    ELSE
        fYawRateCmd := fYawRaw;                                 // 未饱和直通 / Pass through
    END_IF
END_IF
// 段 4：出口闸（双指令非有限复核）/ Outlet gate
IF (fSpeedCmd <> fSpeedCmd) OR (fYawRateCmd <> fYawRateCmd)
   OR (ABS(fSpeedCmd) >= 3.0E38) OR (ABS(fYawRateCmd) >= 3.0E38) THEN
    fSpeedCmd := 0.0;           // 复核失败回零速 / Fallback to zero speed
    fYawRateCmd := 0.0;         // 复核失败回零转 / Fallback to zero yaw
    bAligned := FALSE;          // 复核失败撤对齐 / Clear alignment
    uErrorId := 16#0002_9209;   // 出口非有限拒收 / Output non-finite reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_AgvChargeDockAlignCalc := fSpeedCmd;      // 返回值镜像速度指令 / Return mirrors speed
END_FUNCTION
