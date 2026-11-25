(*
  Name: FC_DL_SCurveTimeOptCalc
  Category: DL_Algo
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 运动规划算法，ST 开源生态实测 0 命中，无外部代码引入）
  功能：S 曲线七段最短时间规划（速度/加速度/加加速度三重约束），含距离不足时降速（三角速度）分支与退化处置。
  边界条件：① 三入参全部过非有限闸；速度/加速度/加加速度任一 ≤ 0 判组态非法，返回哨兵 -1（时间不可表）；
            ② 距离 ≤ 1E-9 mm 视为零行程：时间/峰值/两时长为 0、段数 0、xValid = TRUE、xDistTooShort = TRUE；
            ③ 七段可达判据：2×加速段距离 ≤ 行程 时存在匀速段（段数 7）；否则对峰值速度做 40 次二分求根，
               峰值速度收敛到 1E-6 相对精度以内（禁 EXPT 原语：拐点平方根已用 SQRT 展开，R140 委托纪律）；
            ④ 段数口径：7 = 加加速/恒加速/减加速 + 匀速 + 加减速/恒减速/减减速；6 = 无匀速且恒加速段非零；
               4 = 无匀速且恒加速段为零（三角加速）；三者互斥完备；
            ⑤ 全部钳位/饱和仅作用于量值（时长、段数），有效性由 xValid 单独表达，不伪造事实。
  量纲自证：mm/s² ÷ mm/s³ = s；mm/s ÷ mm/s² = s；mm/s × s = mm；距离[m] ÷ 速度[m/s] = s。
*)
FUNCTION FC_DL_SCurveTimeOptCalc : REAL
VAR_INPUT
    fDistMm : REAL;         (* 行程 [mm] Travel distance [mm] *)
    fVmaxMmS : REAL;        (* 速度上限 [mm/s] Velocity limit [mm/s] *)
    fAmaxMmS2 : REAL;       (* 加速度上限 [mm/s2] Acceleration limit [mm/s2] *)
    fJmaxMmS3 : REAL;       (* 加加速度上限 [mm/s3] Jerk limit [mm/s3] *)
END_VAR
VAR_OUTPUT
    fTimeS : REAL;          (* 最短时间 [s] Minimum time [s] *)
    fVpeakMmS : REAL;       (* 规划峰值速度 [mm/s] Planned peak velocity [mm/s] *)
    fTjS : REAL;            (* 加加速（jerk）段时长 [s] Jerk phase duration [s] *)
    fTaS : REAL;            (* 恒加速段时长（0 = 无） [s] Constant acceleration duration [s] *)
    nSegCount : INT;        (* 段数（0/4/6/7） [段] Segment count *)
    xValid : BOOL;          (* 计算有效性标志 [-] Calculation valid flag *)
    xDistTooShort : BOOL;   (* 距离不足以达到速度上限（已降速） [-] Velocity limit not reachable *)
END_VAR
VAR CONSTANT
    DL_SCV_EPS : REAL := 1.0E-9;        (* 判据容差 [-] Criterion tolerance *)
    DL_SCV_ITER : INT := 40;            (* 二分迭代次数（相对精度 < 1E-6） [次] Bisection iterations *)
    DL_SCV_HALF : REAL := 2.0;          (* 对称行程除数 [-] Symmetric travel divisor *)
    DL_SCV_ZNUM : INT := 0;             (* 零段数 [-] Zero segment count *)
    DL_SCV_N4 : INT := 4;               (* 四段（三角加速、无匀速） [段] Four segments *)
    DL_SCV_N6 : INT := 6;               (* 六段（恒加速段非零、无匀速） [段] Six segments *)
    DL_SCV_N7 : INT := 7;               (* 七段（含匀速段） [段] Seven segments *)
END_VAR
VAR
    fVlim : REAL := 0.0;    (* 达恒加速度所需速度（A²/J） [mm/s] Velocity to reach Amax [mm/s] *)
    fTj : REAL := 0.0;      (* 加加速段时长 [s] Jerk phase duration [s] *)
    fTa : REAL := 0.0;      (* 恒加速段时长 [s] Constant acceleration duration [s] *)
    fTv : REAL := 0.0;      (* 匀速段时长 [s] Constant velocity duration [s] *)
    fDacc : REAL := 0.0;    (* 单个加速段距离 [mm] Single acceleration distance [mm] *)
    fVpeak : REAL := 0.0;   (* 峰值速度 [mm/s] Peak velocity [mm/s] *)
    fVlo : REAL := 0.0;     (* 二分下界 [mm/s] Bisection lower bound [mm/s] *)
    fVhi : REAL := 0.0;     (* 二分上界 [mm/s] Bisection upper bound [mm/s] *)
    fVmid : REAL := 0.0;    (* 二分中点 [mm/s] Bisection midpoint [mm/s] *)
    fTjC : REAL := 0.0;     (* 候选加加速时长 [s] Candidate jerk duration [s] *)
    fTaC : REAL := 0.0;     (* 候选恒加速时长 [s] Candidate accel duration [s] *)
    fDmid : REAL := 0.0;    (* 候选中点对应加速距离 [mm] Candidate accel distance [mm] *)
    nIter : INT := 1;       (* 二分迭代计数 [-] Bisection counter *)
END_VAR
(* 出口预置：七出口统一预置（R256） *)
fTimeS := 0.0; fVpeakMmS := 0.0; fTjS := 0.0; fTaS := 0.0;
nSegCount := DL_SCV_ZNUM; xValid := FALSE; xDistTooShort := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，三入参全枚举 *)
IF (fDistMm <> fDistMm) OR ((fDistMm - fDistMm) <> 0.0)
   OR (fVmaxMmS <> fVmaxMmS) OR ((fVmaxMmS - fVmaxMmS) <> 0.0)
   OR (fAmaxMmS2 <> fAmaxMmS2) OR ((fAmaxMmS2 - fAmaxMmS2) <> 0.0)
   OR (fJmaxMmS3 <> fJmaxMmS3) OR ((fJmaxMmS3 - fJmaxMmS3) <> 0.0) THEN
    FC_DL_SCurveTimeOptCalc := -1.0;         (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：三重上限任一为 0 即退化（时间不可表），距离不得为负 *)
IF (fVmaxMmS <= DL_SCV_EPS) OR (fAmaxMmS2 <= DL_SCV_EPS) OR (fJmaxMmS3 <= DL_SCV_EPS)
   OR (fDistMm < 0.0) THEN
    FC_DL_SCurveTimeOptCalc := -1.0;         (* 哨兵 -1：三重上限退化 / Sentinel -1, degenerate limits *)
    RETURN;
END_IF
(* 零行程退化：全部输出 0，段数 0，有效性置真（零距离是合法事实，不是错误） *)
IF fDistMm <= DL_SCV_EPS THEN
    xValid := TRUE;
    xDistTooShort := TRUE;
    nSegCount := DL_SCV_ZNUM;
    FC_DL_SCurveTimeOptCalc := 0.0;
    RETURN;
END_IF
(* 达恒加速度所需速度：A²/J，量纲 mm/s *)
fVlim := (fAmaxMmS2 * fAmaxMmS2) / fJmaxMmS3;
(* 先试速度上限 V：算其加速段距离，判断是否存在匀速段 *)
IF fVmaxMmS >= fVlim THEN
    fTj := fAmaxMmS2 / fJmaxMmS3;                       (* s = (mm/s2)/(mm/s3) *)
    fTa := (fVmaxMmS / fAmaxMmS2) - fTj;                (* 恒加速段，量纲 s *)
    fDacc := fVmaxMmS * ((DL_SCV_HALF * fTj) + fTa) / DL_SCV_HALF;   (* mm/s × s = mm *)
ELSE
    fTj := SQRT(fVmaxMmS / fJmaxMmS3);                  (* 三角加速：v = J·tj² *)
    fTa := 0.0;
    fDacc := fVmaxMmS * fTj;
END_IF
IF (DL_SCV_HALF * fDacc) <= fDistMm THEN
    fVpeak := fVmaxMmS;                                 (* 速度上限可达 / Limit reachable *)
ELSE
    (* 距离不足：对峰值速度二分求根，使 2×加速段距离 = 行程（单调增，故二分收敛） *)
    fVlo := 0.0;
    fVhi := fVmaxMmS;
    FOR nIter := 1 TO DL_SCV_ITER DO
        fVmid := (fVlo + fVhi) / DL_SCV_HALF;
        IF fVmid >= fVlim THEN
            fTjC := fAmaxMmS2 / fJmaxMmS3;
            fTaC := (fVmid / fAmaxMmS2) - fTjC;
            fDmid := fVmid * ((DL_SCV_HALF * fTjC) + fTaC) / DL_SCV_HALF;
        ELSE
            fTjC := SQRT(fVmid / fJmaxMmS3);
            fTaC := 0.0;
            fDmid := fVmid * fTjC;
        END_IF
        IF (DL_SCV_HALF * fDmid) > fDistMm THEN
            fVhi := fVmid;                              (* 距离超了：峰值取小 / Too far, lower bound *)
        ELSE
            fVlo := fVmid;                              (* 距离不足：峰值取大 / Too short, raise bound *)
        END_IF
    END_FOR
    fVpeak := fVlo;                                     (* 取保守下界，保证不超行程 / Conservative bound *)
END_IF
(* 按最终峰值速度复算 tj / ta / 单段加速距离 *)
IF fVpeak >= fVlim THEN
    fTj := fAmaxMmS2 / fJmaxMmS3;
    fTa := (fVpeak / fAmaxMmS2) - fTj;
    fDacc := fVpeak * ((DL_SCV_HALF * fTj) + fTa) / DL_SCV_HALF;
ELSE
    fTj := SQRT(fVpeak / fJmaxMmS3);
    fTa := 0.0;
    fDacc := fVpeak * fTj;
END_IF
(* 匀速段：剩余行程 ÷ 峰值速度（峰值已过正性闸，绝无零除） *)
IF fVpeak <= DL_SCV_EPS THEN
    FC_DL_SCurveTimeOptCalc := -1.0;         (* 哨兵 -1：峰值速度塌零（行程过小无法表出） / Degenerate *)
    RETURN;
END_IF
fTv := (fDistMm - (DL_SCV_HALF * fDacc)) / fVpeak;
IF fTv < 0.0 THEN
    fTv := 0.0;                                         (* 二分残差导致的微负归零 / Residual to zero *)
END_IF
(* 总时间：2×(加加速 + 恒加速 + 加加速) + 匀速 = 2×(2·tj+ta) + tv，量纲 s *)
fTimeS := DL_SCV_HALF * ((DL_SCV_HALF * fTj) + fTa) + fTv;
(* 段数判定：匀速段 > 0 → 7；否则看恒加速段是否为零 → 6 或 4 *)
IF fTv > DL_SCV_EPS THEN
    nSegCount := DL_SCV_N7;
ELSIF fTa > DL_SCV_EPS THEN
    nSegCount := DL_SCV_N6;
ELSE
    nSegCount := DL_SCV_N4;
END_IF
fVpeakMmS := fVpeak;
fTjS := fTj;
fTaS := fTa;
xDistTooShort := fVpeak < (fVmaxMmS - DL_SCV_EPS);
xValid := TRUE;                                        (* 链路有效 / Chain valid *)
FC_DL_SCurveTimeOptCalc := fTimeS;
END_FUNCTION
