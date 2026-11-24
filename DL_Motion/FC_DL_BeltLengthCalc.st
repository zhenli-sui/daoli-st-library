// FC_DL_BeltLengthCalc v1.0.0
// 开源溯源：self-cleanroom / 公开公式（开口带传动节线长度）
(*
  道莅工业代码库 | DL_Motion | FC_DL_BeltLengthCalc
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 开口平带/同步带节线长度：L = 2C + π(D1+D2)/2 + (D2−D1)²/(4C)，
        中心距分母域闸；D1/D2 为两轮节圆直径，大小顺序不限（公式对称）
  邻件关系: 与 FurnaceBeltTension / FanBeltSlipDiag（带张力/打滑诊断）同族 ——
            差异点：张力/打滑件为运行状态诊断，本件为选型长度计算（设计域），
            码位独立（本件 16#0002_2801）
*)
FUNCTION FC_DL_BeltLengthCalc : REAL
VAR_INPUT
    fDia1    : REAL := 50.0;    // 轮 1 节圆直径 D1 [mm]，域 >= 0 / Pitch diameter pulley 1 [mm]
    fDia2    : REAL := 50.0;    // 轮 2 节圆直径 D2 [mm]，域 >= 0 / Pitch diameter pulley 2 [mm]
    fCenter  : REAL := 200.0;   // 中心距 C [mm]，域 > 0 / Center distance [mm]
    fEps     : REAL := 1.0E-6;  // 判零容差 [mm] / Zero tolerance [mm]
END_VAR
VAR_OUTPUT
    fBeltLength : REAL;         // 节线长度 L [mm] / Pitch line length [mm]
    bValid      : BOOL;         // 结果有效回执 [-] / Result validity receipt
    uErrorId    : UDINT;        // 事件码，0 = 无事件；16#0002_2801 = 域外拒收 / Event code
END_VAR

// —— 段 0：全路径缺省 —— //
fBeltLength := 0.0;             // 长度缺省零 / Length default zero
bValid := FALSE;                // 有效回执预清 / Validity preset
uErrorId := 16#0000;            // 事件码预清 / Event code preset
FC_DL_BeltLengthCalc := 0.0;    // 返回值缺省零（镜像长度）/ Return default mirrors length

// —— 段 1：非有限闸 —— //
IF (fDia1 <> fDia1) OR (fDia2 <> fDia2) OR (fCenter <> fCenter)
   OR (ABS(fDia1) >= 3.0E38) OR (ABS(fDia2) >= 3.0E38) OR (ABS(fCenter) >= 3.0E38) THEN
    uErrorId := 16#0002_2801;   // 输入非有限拒收 / Non-finite reject
    RETURN;
END_IF

// —— 段 2：域闸（直径非负 + 中心距正数防零，R4） —— //
IF (fDia1 < 0.0) OR (fDia2 < 0.0) OR (fCenter < fEps) THEN
    uErrorId := 16#0002_2801;   // 信息级：直径为负或中心距近零（分母为零风险）/ Info level: domain violation
    RETURN;                     // 不计算返回 / Return without computation
END_IF

// —— 段 3：主计算（分母已过闸，公式对 D1/D2 对称） —— //
fBeltLength := 2.0 * fCenter
             + 3.14159265358979 * (fDia1 + fDia2) / 2.0
             + (fDia2 - fDia1) * (fDia2 - fDia1) / (4.0 * fCenter);   // L = 2C + π(D1+D2)/2 + ΔD²/(4C) / Pitch length
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_BeltLengthCalc := fBeltLength;   // 返回值 = 长度 / Return equals length
END_FUNCTION
