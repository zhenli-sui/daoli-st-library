(*
  Name: FC_DL_PreheaterStageEfficiencyCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 水泥窑篦冷机与预热器，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 预热器单级换热效率按「气体放热占理论最大放热的比例」计算：
           eff = (T_gasIn − T_gasOut) / (T_gasIn − T_matIn) * 100，
           分母是气体入口温度与物料入口温度之差，即可传给物料的温度势上限；
           方向固定不可交换（气体为热源、物料为受热体）。
        2) 派生输出：气体温降 fGasDropK 与出口逼近温差 fApproachK = T_gasOut − T_matIn，
           后者是级间结皮/堵塞的早期征兆量（逼近温差过小意味着换热面积不足或物料短路）。
        3) 效率物理域校验：效率必须落在 0.0 ~ 100.0 % 且不超过该级设计上限 fEffMaxPct；
           超上限在热力学上不可能，判为温度测点故障而非换热优异。
  边界条件：1) 非有限值闸：四路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（全部输出强制 0.0），不得只置标志（R19）。
        2) 分母零闸：温度势 |T_gasIn − T_matIn| <= DL_EPS 时不做除法（进出口等温即无势差），
           全部输出清零并判无效。
        3) 温度势方向闸：T_gasIn 必须严格高于 T_matIn，否则热流反向（物料比气体还热），判无效。
        4) 设计上限域闸：fEffMaxPct 必须落在 (0.0, 100.0] 内，越域视为未组态判无效，不做钳制。
        5) 判据取原始值（R24）：效率越限判定使用钳制前的 _fEffRawPct，不得先钳再判。
        6) 物理域钳制：效率钳 0.0 ~ 100.0 %；温降与逼近温差钳 >= 0（负值属测点反向，另由 xValid 拦截）。
  量纲自证：fGasDropK = (degC) − (degC) = (K)；fApproachK = (degC) − (degC) = (K)；
           fEffPct = (K)/(K)*100 = 无因次百分数 [%]，比量两侧同为温差量纲，量纲关系合法。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_PreheaterStageEfficiencyCalc : BOOL
VAR_INPUT
    fGasInC          : REAL;   // 该级进口气体温度 [degC] / Stage inlet gas temperature [degC]
    fGasOutC         : REAL;   // 该级出口气体温度 [degC] / Stage outlet gas temperature [degC]
    fMatInC          : REAL;   // 该级进口物料温度 [degC] / Stage inlet material temperature [degC]
    fEffMaxPct       : REAL;   // 该级设计换热效率上限 [%] / Design efficiency upper limit [%]
END_VAR
VAR_OUTPUT
    fEffPct          : REAL;   // 单级换热效率 [%] / Single-stage heat exchange efficiency [%]
    fGasDropK        : REAL;   // 气体温降 [K] / Gas temperature drop [K]
    fApproachK       : REAL;   // 出口气体与进口物料的逼近温差 [K] / Outlet approach temperature [K]
    xEffOver         : BOOL;   // 效率超设计上限标志 [bool] / Efficiency over design limit flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fPotentialK     : REAL;   // 温度势（气体入口 − 物料入口）[K] / Temperature potential [K]
    _fDropRawK       : REAL;   // 钳制前的气体温降 [K] / Raw gas temperature drop [K]
    _fApproachRawK   : REAL;   // 钳制前的逼近温差 [K] / Raw approach temperature [K]
    _fEffRawPct      : REAL;   // 钳制前的原始效率 [%] / Raw efficiency before limiting [%]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_EFF_LO_PCT    : REAL := 0.0;       // 效率物理域下限 [%] / Efficiency physical domain low [%]
    DL_EFF_HI_PCT    : REAL := 100.0;     // 效率物理域上限 [%] / Efficiency physical domain high [%]
    DL_ZERO_K        : REAL := 0.0;       // 温差零基准 [K] / Zero temperature-difference reference [K]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fGasInC > -DL_BIG AND fGasInC < DL_BIG)
   OR NOT (fGasOutC > -DL_BIG AND fGasOutC < DL_BIG)
   OR NOT (fMatInC > -DL_BIG AND fMatInC < DL_BIG)
   OR NOT (fEffMaxPct > -DL_BIG AND fEffMaxPct < DL_BIG) THEN
    fEffPct := 0.0;                         // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fGasDropK := 0.0;                       // 温降强制 0.0 / Gas drop forced to zero
    fApproachK := 0.0;                      // 逼近温差强制 0.0 / Approach forced to zero
    xEffOver := FALSE;                      // 失效侧超限位保持假 / Overrun stays false when invalid
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_PreheaterStageEfficiencyCalc := FALSE;   // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：温度势方向闸与分母零闸（分母为温度势，必须先验方向再验量级） —— *)
_fPotentialK := fGasInC - fMatInC;                                                // 温度势 [K]
IF (_fPotentialK <= DL_EPS) THEN                                                  // 势差为零或反向：无换热驱动力
    fEffPct := 0.0;                         // 无势差即无效率 / No potential, no efficiency
    fGasDropK := 0.0;                       // 温降不可算 / Drop not computable
    fApproachK := 0.0;                      // 逼近温差不可算 / Approach not computable
    xEffOver := FALSE;                      // 失效侧超限位保持假 / Overrun stays false
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_PreheaterStageEfficiencyCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fDropRawK := fGasInC - fGasOutC;                                                 // 气体温降 [K]
_fApproachRawK := fGasOutC - fMatInC;                                             // 逼近温差 [K]
_fEffRawPct := _fDropRawK / _fPotentialK * DL_PCT;                                // 原始效率 [%]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xEffOver := (_fEffRawPct > fEffMaxPct);                                           // 超该级设计上限
xValid := (fEffMaxPct > DL_EPS)                                                   // 设计上限必须为正
          AND (fEffMaxPct <= DL_EFF_HI_PCT)                                       // 设计上限不得超过 100 %
          AND (_fEffRawPct >= DL_EFF_LO_PCT)                                      // 不低于物理域下限
          AND (_fEffRawPct <= DL_EFF_HI_PCT)                                      // 不高于物理域上限
          AND (_fDropRawK >= DL_ZERO_K)                                           // 气体必须降温（方向固定）
          AND (_fApproachRawK > DL_ZERO_K);                                       // 出口气体仍须高于进口物料

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fEffPct := LIMIT(DL_EFF_LO_PCT, _fEffRawPct, DL_EFF_HI_PCT);                       // 效率钳 0..100 [%]
fGasDropK := MAX(DL_ZERO_K, _fDropRawK);                                           // 温降钳 >= 0 [K]
fApproachK := MAX(DL_ZERO_K, _fApproachRawK);                                      // 逼近温差钳 >= 0 [K]
FC_DL_PreheaterStageEfficiencyCalc := xValid;                                      // 返回码：TRUE = 计算可信

END_FUNCTION
