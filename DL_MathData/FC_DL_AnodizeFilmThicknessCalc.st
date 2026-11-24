(*
  Component : FC_DL_AnodizeFilmThicknessCalc
  Category  : DL_MathData
  Type      : FC
  Complexity: C1
  VERSION   : v1.0.0
  功能      : 阳极氧化膜厚-电量换算：按法拉第定律由电量密度与膜密度算膜厚 μm，并按电流密度反算达目标膜厚所需时间。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 膜密度、摩尔质量、转移电子数须 > 1e-9，效率须在 (0,100] % 内，否则返回哨兵 -1；
              ② 反算时间需电流密度 > 1e-9，电流密度为 0 时时间回 0（不下发 inf）；
              ③ 量纲链：g/dm² ÷ g/cm³ = cm³/dm²，除 dm² 面积 100 cm² 得 cm 厚，再乘 1e4 得 μm。
*)
FUNCTION FC_DL_AnodizeFilmThicknessCalc : REAL
VAR_INPUT
    fChgDensAsDm2 : REAL;   (* 电量密度 [A·s/dm²] Charge density *)
    fMolarMassGmol: REAL;   (* 氧化物摩尔质量 [g/mol] Oxide molar mass *)
    fDensityGcm3  : REAL;   (* 膜层密度 [g/cm³] Film density *)
    nElectrons    : INT;    (* 反应转移电子数 [个] Transferred electrons *)
    fEffPct       : REAL;   (* 电流效率 [%] Current efficiency *)
    fCurrDensADm2 : REAL;   (* 电流密度 [A/dm²] Current density *)
    fThickTargetUm: REAL;   (* 目标膜厚 [μm] Target film thickness *)
END_VAR
VAR_OUTPUT
    fFilmUm        : REAL;  (* 膜厚 [μm] Film thickness *)
    fMassGdm2      : REAL;  (* 单位面积氧化膜质量 [g/dm²] Film mass per area *)
    fTimeForTargetS: REAL;  (* 达目标膜厚所需时间 [s] Time to reach target thickness *)
    xValid         : BOOL;  (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_FARADAY  : REAL := 96485.332;(* 法拉第常数 [C/mol] Faraday constant *)
    DL_CM_PER_DM: REAL := 100.0;    (* dm² 对应 cm² 数 [cm²/dm²] cm2 per dm2 *)
    DL_PCT_BASE : REAL := 100.0;    (* 百分比基准 [%] Percent base *)
    DL_UM_PER_CM: REAL := 10000.0;  (* 厘米转微米系数 [μm/cm] Micrometres per centimetre *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
VAR
    fEffUnit : REAL;   (* 效率折算系数 [-] Efficiency as fraction *)
    fMoles   : REAL;   (* 单位面积反应摩尔数 [mol/dm²] Moles per area *)
END_VAR
(* 出口预置：四出口统一预置 *)
fFilmUm := 0.0; fMassGdm2 := 0.0; fTimeForTargetS := 0.0; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fChgDensAsDm2 <> fChgDensAsDm2) OR ((fChgDensAsDm2 - fChgDensAsDm2) <> 0.0)
   OR (fMolarMassGmol <> fMolarMassGmol) OR ((fMolarMassGmol - fMolarMassGmol) <> 0.0)
   OR (fDensityGcm3 <> fDensityGcm3) OR ((fDensityGcm3 - fDensityGcm3) <> 0.0)
   OR (fEffPct <> fEffPct) OR ((fEffPct - fEffPct) <> 0.0)
   OR (fCurrDensADm2 <> fCurrDensADm2) OR ((fCurrDensADm2 - fCurrDensADm2) <> 0.0) THEN
    FC_DL_AnodizeFilmThicknessCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：膜密度、摩尔质量、转移电子数、效率、电量密度非负 *)
IF (fDensityGcm3 <= DL_EPS) OR (fMolarMassGmol <= DL_EPS) OR (nElectrons < 1)
   OR (fEffPct <= DL_ZERO) OR (fEffPct > DL_PCT_BASE) OR (fChgDensAsDm2 < DL_ZERO) THEN
    FC_DL_AnodizeFilmThicknessCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
fEffUnit := fEffPct / DL_PCT_BASE;             (* 效率折算 [-] / Efficiency as fraction *)
(* 单位面积摩尔数：n = q / (z·F)，电量密度为 C/dm² *)
fMoles := fChgDensAsDm2 / (INT_TO_REAL(nElectrons) * DL_FARADAY);
(* 单位面积质量：m = n·M [g/dm²]，乘效率得实际成膜量 *)
fMassGdm2 := fMoles * fMolarMassGmol * fEffUnit;
(* 厚度换算：g/dm² ÷ g/cm³ = cm³/dm²，除 100 cm² 得 cm，再乘 1e4 得 μm *)
fFilmUm := (fMassGdm2 / fDensityGcm3) / DL_CM_PER_DM * DL_UM_PER_CM;
(* 反算时间：t = 目标膜厚 / (电流密度 × 单位电量膜厚系数)，电流密度为 0 时回 0 *)
IF (fCurrDensADm2 > DL_EPS) AND (fThickTargetUm > DL_ZERO) THEN
    fTimeForTargetS := fThickTargetUm * INT_TO_REAL(nElectrons) * DL_FARADAY * fDensityGcm3
                       / (fCurrDensADm2 * fMolarMassGmol * fEffUnit * DL_CM_PER_DM);
END_IF
xValid := TRUE;                                (* 链路有效 / Chain valid *)
FC_DL_AnodizeFilmThicknessCalc := fFilmUm;     (* 返回膜厚 [μm] / Return film thickness *)
END_FUNCTION
