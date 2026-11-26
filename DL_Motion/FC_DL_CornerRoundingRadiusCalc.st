(* ============================================================
   DL_Motion / FC_DL_CornerRoundingRadiusCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：拐角圆弧过渡半径 [mm] 与拐角通过速度 [mm/min]：
         r ≤ min(段长)/2 × tan(θ/2)（切线长约束，另受 20 mm 工艺硬上限）；
         v ≤ (j·r²)^(1/3)（jerk 约束，再与编程进给取小）
   边界：θ∉(0,180)° / 段长≤0 / 进给≤0 / jerk≤0 或非有限 → 半径与速度写 0（N1/N3）；
         fJerkRatio = v_use³/(r²·j) ∈ [0,1]，v_use = 实际采用进给（mm/s），
         = 1 表示 jerk 用满、< 1 表示受编程进给限制（N5 系数回代）
   依赖：仅 IEC 61131-3（SQRT / EXPT / TAN / MIN） ｜ 溯源：DLF-A-RTCP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_CornerRoundingRadiusCalc : BOOL
VAR_INPUT
    fCornerAngleDeg : LREAL;  // 拐角夹角，域 (0,180) [deg] / Corner included angle
    fSegLenAMm      : LREAL;  // 前一段长度，域 > 0 [mm] / Length of the incoming segment
    fSegLenBMm      : LREAL;  // 后一段长度，域 > 0 [mm] / Length of the outgoing segment
    fFeedMaxMmMin   : LREAL;  // 编程进给上限，域 > 0 [mm/min] / Programmed feed ceiling
    fJerkMaxMmS3    : LREAL;  // 允许 jerk 上限，域 > 0 [mm/s³] / Allowed jerk ceiling
END_VAR
VAR_OUTPUT
    fRadiusMm        : LREAL;  // 过渡圆弧半径 [mm] / Rounding arc radius
    fCornerFeedMmMin : LREAL;  // 拐角通过速度 [mm/min] / Corner pass-through feed rate
    fJerkRatio       : REAL;   // jerk 使用率 [0,1] [-] / Jerk utilization ratio
END_VAR
VAR
    _fThetaRad : LREAL;  // 夹角弧度值 [rad] / Included angle in radians
    _fRmax     : LREAL;  // 段长约束下的半径上限 [mm] / Radius ceiling from segment lengths
    _fVuse     : LREAL;  // jerk 约束允许速度 [mm/s] / Speed allowed by the jerk limit
    _fVact     : LREAL;  // 实际采用进给（换算到 mm/s）[mm/s] / Adopted feed rate in millimeters per second
END_VAR
VAR CONSTANT
    DL_CRN_PI : LREAL := 3.14159265358979324;  // 圆周率（LREAL 全精度）[-] / Pi at full precision
END_VAR

(* 段 0：出口预置安全侧（半径 0 = 不做过渡，N3） *)
FC_DL_CornerRoundingRadiusCalc := FALSE;
fRadiusMm := 0.0;  fCornerFeedMmMin := 0.0;  fJerkRatio := 0.0;

(* 段 1：非有限闸 + 五域闸（夹角开区间、四个正值域） *)
IF (fCornerAngleDeg <> fCornerAngleDeg) OR (fSegLenAMm <> fSegLenAMm)
   OR (fSegLenBMm <> fSegLenBMm) OR (fFeedMaxMmMin <> fFeedMaxMmMin)
   OR (fJerkMaxMmS3 <> fJerkMaxMmS3) THEN
    RETURN;
END_IF
IF (fCornerAngleDeg <= 0.0) OR (fCornerAngleDeg >= 180.0) THEN RETURN; END_IF
IF (fSegLenAMm <= 0.0) OR (fSegLenBMm <= 0.0) THEN RETURN; END_IF
IF (fFeedMaxMmMin <= 0.0) OR (fJerkMaxMmS3 <= 0.0) THEN RETURN; END_IF

(* 段 2：半径上限（切线长 T = r/tan(θ/2) ≤ 最短段长/2）与硬上限 *)
_fThetaRad := fCornerAngleDeg * DL_CRN_PI / 180.0;
_fRmax := (MIN(fSegLenAMm, fSegLenBMm) / 2.0) * TAN(_fThetaRad / 2.0);
fRadiusMm := MIN(_fRmax, 20.0);                          // 20 mm 工艺硬上限

(* 段 3：jerk 约束速度 v = (j·r²)^(1/3) [mm/s]，再与编程进给取小 *)
_fVuse := EXPT(fJerkMaxMmS3 * fRadiusMm * fRadiusMm, 0.33333333333333333);
fCornerFeedMmMin := MIN(fFeedMaxMmMin, _fVuse * 60.0);   // mm/s → mm/min

(* 段 4：jerk 使用率（按实际采用进给回代：v_use = fCornerFeedMmMin/60；
   代 _fVuse 回代会代数恒等为 1.000000，输出无信息量，故改用采用值） *)
_fVact := fCornerFeedMmMin / 60.0;                       // mm/min → mm/s
fJerkRatio := LREAL_TO_REAL((_fVact * _fVact * _fVact) / (fRadiusMm * fRadiusMm * fJerkMaxMmS3));
IF (fJerkRatio <> fJerkRatio) OR ((fJerkRatio - fJerkRatio) <> (fJerkRatio - fJerkRatio))
   OR (fJerkRatio < 0.0) THEN fJerkRatio := 0.0; END_IF
IF fJerkRatio > 1.0 THEN fJerkRatio := 1.0; END_IF

(* 段 5：结果复检 + 单一出口裁决（N4） *)
IF (fRadiusMm <> fRadiusMm) OR ((fRadiusMm - fRadiusMm) <> (fRadiusMm - fRadiusMm))
   OR (fCornerFeedMmMin <> fCornerFeedMmMin)
   OR ((fCornerFeedMmMin - fCornerFeedMmMin) <> (fCornerFeedMmMin - fCornerFeedMmMin)) THEN
    fRadiusMm := 0.0;  fCornerFeedMmMin := 0.0;  fJerkRatio := 0.0;  RETURN;
END_IF
FC_DL_CornerRoundingRadiusCalc := TRUE;
END_FUNCTION
