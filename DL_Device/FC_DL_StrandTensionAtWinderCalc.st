// FC_DL_StrandTensionAtWinderCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Device，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 有效总张力 = 总张力 − 导纱摩擦损失 + 线密度·加速度 [N]（惯性力项 m'·a），
        单束张力 = 有效总张力/丝束根数，×100 换算为 cN。
  邻件/码位: 与 FC_DL_SizeApplicatorPickupCalc 同属拉丝后端件（力学面 vs 化学面）；
             16#0002_9226 = 非有限、根数 < 1、摩擦/线密度为负或有效总张力非正拒收。
*)
FUNCTION FC_DL_StrandTensionAtWinderCalc : REAL
VAR_INPUT
    fTotalTension : REAL := 60.0;  // 总张力 [N]，域 > 0 / Total tension [N]
    iStrandCount  : INT := 400;     // 丝束根数，域 >= 1 [根] / Strand count
    fFrictionDrop : REAL := 2.0;    // 导纱摩擦损失 [N]，域 >= 0 / Guide friction drop [N]
    fAccel        : REAL := 0.5;    // 卷绕加速度 [m/s²] / Winding acceleration [m/s^2]
    fMassPerLen   : REAL := 0.02;   // 线密度 [kg/m]，域 >= 0 / Linear mass density [kg/m]
END_VAR
VAR_OUTPUT
    fTensionPerStrand : REAL;       // 单束张力 [cN] / Tension per strand [cN]
    bValid            : BOOL;       // 结果有效回执 [-] / Result validity receipt
    uErrorId          : UDINT;      // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fEffective : REAL := 0.0;       // 有效总张力 [N] / Effective total tension [N]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fTensionPerStrand := 0.0;           // 单束张力缺省零 / Per-strand default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_StrandTensionAtWinderCalc := 0.0;     // 返回值缺省零（镜像单束张力）/ Return default zero
// 段 1：非有限闸（四实数入参；整数入参天然有限）/ Non-finite gate on real inputs
IF (fTotalTension <> fTotalTension) OR (fFrictionDrop <> fFrictionDrop)
   OR (fAccel <> fAccel) OR (fMassPerLen <> fMassPerLen)
   OR (ABS(fTotalTension) >= 3.0E38) OR (ABS(fFrictionDrop) >= 3.0E38)
   OR (ABS(fAccel) >= 3.0E38) OR (ABS(fMassPerLen) >= 3.0E38) THEN
    uErrorId := 16#0002_9226;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（根数下限防除零 + 摩擦/线密度非负，R4）/ Domain gate
IF iStrandCount < 1 THEN
    uErrorId := 16#0002_9226;   // 根数不足 1，单束张力不可解 / Strand count below one
    RETURN;
END_IF
IF (fFrictionDrop < 0.0) OR (fMassPerLen < 0.0) THEN
    uErrorId := 16#0002_9226;   // 摩擦损失或线密度为负 / Negative friction or density
    RETURN;
END_IF
// 段 3：主计算（有效总张力 → 单束张力 → cN）/ Main computation
fEffective := fTotalTension - fFrictionDrop + fMassPerLen * fAccel;     // 有效总张力 [N] / Effective tension
IF fEffective <= 1.0E-6 THEN
    uErrorId := 16#0002_9226;   // 有效总张力非正，物理不可达 / Effective tension non-positive
    RETURN;
END_IF
fTensionPerStrand := fEffective / INT_TO_REAL(iStrandCount) * 100.0;    // 单束张力 [cN] / Per strand
// 段 4：出口闸（非有限复核 + 正数复核）/ Outlet gate
IF (fTensionPerStrand <> fTensionPerStrand) OR (ABS(fTensionPerStrand) >= 3.0E38)
   OR (fTensionPerStrand <= 0.0) THEN
    fTensionPerStrand := 0.0;   // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9226;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_StrandTensionAtWinderCalc := fTensionPerStrand;   // 返回值镜像单束张力 / Return mirrors tension
END_FUNCTION
