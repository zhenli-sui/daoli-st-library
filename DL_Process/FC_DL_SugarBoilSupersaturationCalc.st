(*
  Component : FC_DL_SugarBoilSupersaturationCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 煮糖过饱和度核算：先按基准温度溶解度折算当前温度溶解度，再由锤度算基础过饱和度，乘纯度非糖分修正后判定晶核生成窗口。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 溶解度基准与锤度须 > 1e-9，纯度须落在 0~100 %，否则返回哨兵 -1；
              ② 溶解度温度折算 S(T)=Sref·(1+k·(T-Tref)) 后按 1e-9 硬下限钳位，防除零；
              ③ 纯度修正系数按非糖分比例线性折算并钳位 0.5~2.0；晶核窗口界须满足 下界 < 上界。
*)
FUNCTION FC_DL_SugarBoilSupersaturationCalc : REAL
VAR_INPUT
    fBrixPct       : REAL;   (* 糖膏锤度 [°Bx] Massecuite brix *)
    fPurityPct     : REAL;   (* 糖膏纯度 [%] Massecuite purity *)
    fTempC         : REAL;   (* 糖膏温度 [°C] Massecuite temperature *)
    fTempRefC      : REAL;   (* 溶解度基准温度 [°C] Reference temperature for solubility *)
    fSolubRefPct   : REAL;   (* 基准温度下纯糖溶解度（质量分数） [%] Sucrose solubility at reference temperature *)
    fNucLo         : REAL;   (* 晶核生成窗口下界 [-] Nucleation window lower bound *)
    fNucHi         : REAL;   (* 晶核生成窗口上界 [-] Nucleation window upper bound *)
END_VAR
VAR_OUTPUT
    fSupersat     : REAL;  (* 过饱和度系数 [-] Supersaturation coefficient *)
    fSolubPct     : REAL;  (* 当前温度下纯糖溶解度 [%] Sucrose solubility at current temperature *)
    fPurityFactor : REAL;  (* 纯度非糖分修正因子 [-] Purity correction factor *)
    xNucWindow    : BOOL;  (* 晶核生成窗口内标志 [-] In nucleation window flag *)
    xValid        : BOOL;  (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_PCT_BASE : REAL := 100.0;    (* 百分比基准 [%] Percent base *)
    DL_PUR_K    : REAL := 0.004;    (* 纯度修正斜率 [1/%] Purity slope *)
    DL_SOL_K    : REAL := 0.0065;   (* 溶解度温度斜率 [1/°C] Solubility temperature slope *)
    DL_PF_MIN   : REAL := 0.5;      (* 纯度因子下限 [-] Purity factor lower clamp *)
    DL_PF_MAX   : REAL := 2.0;      (* 纯度因子上限 [-] Purity factor upper clamp *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
(* 出口预置：五出口统一预置 *)
fSupersat := 0.0; fSolubPct := 0.0; fPurityFactor := 1.0; xNucWindow := FALSE; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fBrixPct <> fBrixPct) OR ((fBrixPct - fBrixPct) <> 0.0)
   OR (fPurityPct <> fPurityPct) OR ((fPurityPct - fPurityPct) <> 0.0)
   OR (fTempC <> fTempC) OR ((fTempC - fTempC) <> 0.0)
   OR (fTempRefC <> fTempRefC) OR ((fTempRefC - fTempRefC) <> 0.0)
   OR (fSolubRefPct <> fSolubRefPct) OR ((fSolubRefPct - fSolubRefPct) <> 0.0) THEN
    FC_DL_SugarBoilSupersaturationCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：溶解度基准为比例基，锤度须为正，纯度须在 0~100 %，窗口界须有序 *)
IF (fSolubRefPct <= DL_EPS) OR (fBrixPct <= DL_ZERO) OR (fPurityPct < DL_ZERO)
   OR (fPurityPct > DL_PCT_BASE) OR (fNucLo >= fNucHi) THEN
    FC_DL_SugarBoilSupersaturationCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 温度折算溶解度：S(T) = Sref·(1 + k·(T - Tref))，下限按 1e-9 钳位防除零 *)
fSolubPct := fSolubRefPct * (1.0 + DL_SOL_K * (fTempC - fTempRefC));
IF fSolubPct <= DL_EPS THEN
    fSolubPct := DL_EPS;                        (* 除零硬保护 [%] / Divide-by-zero hard floor *)
END_IF
(* 纯度修正：非糖分越多，同锤度下蔗糖实际过饱和度越低，双侧钳位 *)
fPurityFactor := 1.0 + (DL_PCT_BASE - fPurityPct) * DL_PUR_K;
IF fPurityFactor < DL_PF_MIN THEN
    fPurityFactor := DL_PF_MIN;                 (* 下限钳位 [-] / Lower clamp *)
ELSIF fPurityFactor > DL_PF_MAX THEN
    fPurityFactor := DL_PF_MAX;                 (* 上限钳位 [-] / Upper clamp *)
END_IF
(* 过饱和度：锤度 / 当前温度溶解度 × 纯度修正，除子已钳位保护 *)
fSupersat := fBrixPct / fSolubPct * fPurityFactor;
(* 晶核窗口：过饱和度落在 [下界, 上界] 内即处于起晶窗口 *)
xNucWindow := (fSupersat >= fNucLo) AND (fSupersat <= fNucHi);
xValid := TRUE;                                 (* 链路有效 / Chain valid *)
FC_DL_SugarBoilSupersaturationCalc := fSupersat;(* 返回过饱和度 [-] / Return supersaturation *)
END_FUNCTION
