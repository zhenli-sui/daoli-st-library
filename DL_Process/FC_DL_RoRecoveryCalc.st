(*
  Name: FC_DL_RoRecoveryCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 RO/NF 膜法水处理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 系统回收率按「产水占进水的百分比」计算，产水为分子、进水为分母，方向固定不可交换，
           即 fRecoveryPct = fPermeateFlowM3h / fFeedFlowM3h * 100，用于 RO/NF 段回收率监视。
        2) 浓水排放流量由容积守恒的减法式给出：进水 − 产水（同温同压下的容积近似），
           作为浓水调节阀的前馈目标值使用。
        3) 回收率同时受两个独立门限约束：物理域 0.0 ~ 100.0 %，以及设计上限
           fRecoveryMaxPct（膜厂家给定的段回收率上限）；任一越界只置 xValid=FALSE，
           数值本身钳制到物理域内后输出，绝不把越限值伪装成合格值。
  边界条件：1) 分母零闸：ABS(fFeedFlowM3h) > DL_EPS 才允许做除法，否则清零全部输出并置无效。
        2) 非有限值闸：全部实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，该式同时拦 NaN 与 Inf，
           命中即拦断实值通路（输出强制 0.0），不得只置标志而把 NaN 传给下游（R19）。
        3) 回收率物理域 0.0 ~ 100.0 %，越域钳制到域内输出并置 xValid=FALSE。
        4) 设计上限 fRecoveryMaxPct 自身须落在 (0.0, 100.0] 内，越域视为组态错误判无效。
        5) 产水量为负值（传感器反向）或大于进水量（超出守恒），均判无效，不取绝对值掩盖故障。
        6) 无回差环节：本件为纯函数无状态，不做迟滞，迟滞由下游报警件承担。
  量纲自证：fRecoveryPct = (m3/h) / (m3/h) * 100 = 无因次百分数 [%]；
           fBrineFlowM3h = (m3/h) − (m3/h) = (m3/h)，减法两侧同量纲，量纲关系合法。
*)

FUNCTION FC_DL_RoRecoveryCalc : BOOL
VAR_INPUT
    fFeedFlowM3h     : REAL;   // 系统进水体积流量 [m3/h] / Feed volumetric flow [m3/h]
    fPermeateFlowM3h : REAL;   // 系统产水体积流量 [m3/h] / Permeate volumetric flow [m3/h]
    fRecoveryMaxPct  : REAL;   // 段回收率设计上限 [%] / Design recovery upper limit [%]
END_VAR
VAR_OUTPUT
    fRecoveryPct     : REAL;   // 系统回收率 [%] / System recovery ratio [%]
    fBrineFlowM3h    : REAL;   // 浓水排放流量 [m3/h] / Brine discharge flow [m3/h]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fRecRawPct      : REAL;   // 钳制前的原始回收率 [%] / Raw recovery before limiting [%]
    _fBrineRawM3h    : REAL;   // 钳制前的原始浓水流量 [m3/h] / Raw brine flow before limiting [m3/h]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_REC_LO_PCT    : REAL := 0.0;       // 回收率物理域下限 [%] / Recovery physical domain low [%]
    DL_REC_HI_PCT    : REAL := 100.0;     // 回收率物理域上限 [%] / Recovery physical domain high [%]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路，NaN/Inf 一律不得流到输出） —— *)
IF NOT (fFeedFlowM3h > -DL_BIG AND fFeedFlowM3h < DL_BIG)
   OR NOT (fPermeateFlowM3h > -DL_BIG AND fPermeateFlowM3h < DL_BIG)
   OR NOT (fRecoveryMaxPct > -DL_BIG AND fRecoveryMaxPct < DL_BIG) THEN
    fRecoveryPct := 0.0;                    // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fBrineFlowM3h := 0.0;                   // 浓水同样强制 0.0 / Brine forced to zero as well
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_RoRecoveryCalc := FALSE;          // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：除法前先过 ABS 闸，且闸的是分母本身） —— *)
IF ABS(fFeedFlowM3h) <= DL_EPS THEN
    fRecoveryPct := 0.0;                    // 无进水即无回收率 / No feed means no recovery
    fBrineFlowM3h := 0.0;                   // 无进水即无浓水 / No feed means no brine
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_RoRecoveryCalc := FALSE;          // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出，不做无意义运算 / Early exit
END_IF

(* —— 段 3：主算式（R22 方向自核：差值/比值的基准量是进水量，不是产水量） —— *)
_fRecRawPct := fPermeateFlowM3h / fFeedFlowM3h * DL_PCT;   // 产水 / 进水 * 100 [%]
_fBrineRawM3h := fFeedFlowM3h - fPermeateFlowM3h;          // 进水 − 产水 [m3/h]

(* —— 段 4：物理域与设计上限校验（单点 BOOL 聚合，避免多处赋 FALSE 造成覆盖） —— *)
xValid := (_fRecRawPct >= DL_REC_LO_PCT)                       // 不低于物理域下限
          AND (_fRecRawPct <= DL_REC_HI_PCT)                   // 不高于物理域上限
          AND (fRecoveryMaxPct > DL_EPS)                       // 设计上限必须为正
          AND (fRecoveryMaxPct <= DL_REC_HI_PCT)               // 设计上限不得超 100 %
          AND (_fRecRawPct <= fRecoveryMaxPct)                 // 不得超出膜厂家设计上限
          AND (fPermeateFlowM3h >= 0.0)                        // 产水不得为负（传感器反向）
          AND (fPermeateFlowM3h <= fFeedFlowM3h)               // 产水不得大于进水（守恒校验）
          AND (_fBrineRawM3h >= 0.0);                          // 浓水不得为负

(* —— 段 5：输出单点写盘（数值钳制到物理域内，有效位已在段 4 定案） —— *)
fRecoveryPct := LIMIT(DL_REC_LO_PCT, _fRecRawPct, DL_REC_HI_PCT);   // 回收率钳 0..100 [%]
fBrineFlowM3h := MAX(DL_REC_LO_PCT, _fBrineRawM3h);                 // 浓水钳 >= 0 [m3/h]
FC_DL_RoRecoveryCalc := xValid;                                     // 返回码：TRUE = 计算可信

END_FUNCTION
