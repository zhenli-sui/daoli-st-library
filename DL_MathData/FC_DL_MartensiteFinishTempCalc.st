(*
  Component : FC_DL_MartensiteFinishTempCalc
  Category  : DL_MathData
  Type      : FC
  Complexity: C1
  VERSION   : v1.0.0
  功能      : 马氏体转变点核算：按 C/Mn/Cr/Ni 含量经验式算 Ms 点，再按固定间隔算 Mf 点，负值统一钳位到 0 °C。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 各元素含量须落在 0~10 % 可表区间，越界返回哨兵 -1；
              ② Ms 经验式仅在常规合金钢成分域内可信，超出成分域只置 xInDomain = FALSE 不拒算；
              ③ Ms/Mf 负值一律钳位 0 °C（低于室温无工程意义）。
*)
FUNCTION FC_DL_MartensiteFinishTempCalc : REAL
VAR_INPUT
    fCarbonPct : REAL;   (* 含碳量 [%] Carbon content *)
    fMnPct     : REAL;   (* 锰含量 [%] Manganese content *)
    fCrPct     : REAL;   (* 铬含量 [%] Chromium content *)
    fNiPct     : REAL;   (* 镍含量 [%] Nickel content *)
END_VAR
VAR_OUTPUT
    fMsC       : REAL;   (* 马氏体开始转变温度 [°C] Martensite start temperature *)
    fMfC       : REAL;   (* 马氏体终了转变温度 [°C] Martensite finish temperature *)
    xInDomain  : BOOL;   (* 成分在经验式适用域内标志 [-] Composition in empirical domain *)
    xValid     : BOOL;   (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_MS_BASE : REAL := 539.0;   (* Ms 经验式常数项 [°C] Ms intercept *)
    DL_K_C     : REAL := 423.0;   (* 碳系数 [°C/%] Carbon coefficient *)
    DL_K_MN    : REAL := 30.4;    (* 锰系数 [°C/%] Manganese coefficient *)
    DL_K_CR    : REAL := 12.1;    (* 铬系数 [°C/%] Chromium coefficient *)
    DL_K_NI    : REAL := 17.7;    (* 镍系数 [°C/%] Nickel coefficient *)
    DL_MS_MF   : REAL := 215.0;   (* Ms 与 Mf 间隔 [°C] Ms-Mf interval *)
    DL_ELEM_MAX: REAL := 10.0;    (* 元素含量可表上限 [%] Element content upper bound *)
    DL_ZERO    : REAL := 0.0;     (* 零常量 [°C] Zero constant *)
END_VAR
(* 出口预置：四出口统一预置 *)
fMsC := 0.0; fMfC := 0.0; xInDomain := FALSE; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fCarbonPct <> fCarbonPct) OR ((fCarbonPct - fCarbonPct) <> 0.0)
   OR (fMnPct <> fMnPct) OR ((fMnPct - fMnPct) <> 0.0)
   OR (fCrPct <> fCrPct) OR ((fCrPct - fCrPct) <> 0.0)
   OR (fNiPct <> fNiPct) OR ((fNiPct - fNiPct) <> 0.0) THEN
    FC_DL_MartensiteFinishTempCalc := -1.0;   (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 成分域闸：负含量与超上限均视为非法输入 *)
IF (fCarbonPct < DL_ZERO) OR (fMnPct < DL_ZERO) OR (fCrPct < DL_ZERO) OR (fNiPct < DL_ZERO)
   OR (fCarbonPct > DL_ELEM_MAX) OR (fMnPct > DL_ELEM_MAX)
   OR (fCrPct > DL_ELEM_MAX) OR (fNiPct > DL_ELEM_MAX) THEN
    FC_DL_MartensiteFinishTempCalc := -1.0;   (* 哨兵 -1：成分越界 / Sentinel -1 composition out of range *)
    RETURN;
END_IF
(* Ms 经验式：Ms = 539 - 423C - 30.4Mn - 12.1Cr - 17.7Ni *)
fMsC := DL_MS_BASE
        - DL_K_C  * fCarbonPct
        - DL_K_MN * fMnPct
        - DL_K_CR * fCrPct
        - DL_K_NI * fNiPct;
(* Mf 经验式：Mf = Ms - 215，负值钳位 0 °C *)
fMfC := fMsC - DL_MS_MF;
IF fMfC < DL_ZERO THEN
    fMfC := DL_ZERO;                          (* 负值钳位 [°C] / Negative clamp *)
END_IF
IF fMsC < DL_ZERO THEN
    fMsC := DL_ZERO;                          (* 负值钳位 [°C] / Negative clamp *)
END_IF
(* 适用域标注：低碳高合金组合已超出经验式拟合区间，仅标注不拒算 *)
xInDomain := (fCarbonPct >= 0.10) AND (fCarbonPct <= 0.80);
xValid := TRUE;                               (* 链路有效 / Chain valid *)
FC_DL_MartensiteFinishTempCalc := fMsC;       (* 返回 Ms 点 [°C] / Return Ms temperature *)
END_FUNCTION
