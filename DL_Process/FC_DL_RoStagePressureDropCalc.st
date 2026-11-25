(*
  Name: FC_DL_RoStagePressureDropCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 RO/NF 膜法水处理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 段间压降按湍流平方律计算：ΔP = k · Q²，其中 k 为段阻力系数（bar/(m3/h)²），
           Q 为段流量（m3/h）。平方律的依据是湍流区沿程与局部损失均与流速平方成正比，
           而流速与容积流量成正比，故压降对流量呈二次关系，不是线性关系。
        2) 与压降上限 fDropLimitBar 比对给出超限报警 xAlarm。超限是膜段污堵/浓水通道阻塞的
           早期特征（流量不变而压降上升），因此报警取「大于等于上限」而非「大于」，
           上限触点本身即算到达报警点。
  边界条件：1) 非有限值闸：三路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（fDropBar 强制 0.0、xAlarm 强制 FALSE）并置无效（R19）。
        2) 组态零闸：ABS(fResistCoef) > DL_EPS 与 ABS(fDropLimitBar) > DL_EPS 都必须成立，
           阻力系数为 0 表示未标定、上限为 0 表示未组态，两者都判无效（不做除零以外的默认替代）。
        3) 负值闸：段流量为负判无效（传感器反向）；阻力系数为负判无效（系数不可为负）；
           压降上限为负判无效。
        4) 饱和钳制：段流量先钳到 0 ~ DL_FLOW_MAX(1000 m3/h)，压降结果再钳到 0 ~ DL_DROP_MAX(50 bar)，
           防止平方项在小数域溢出或给出无物理意义的巨值。
        5) 报警只在 xValid 为 TRUE 时才可能为 TRUE，无效数据不得触发工艺报警（防误停）。
        6) 无回差环节：本件为纯函数无状态，报警回差由下游 FB 承担。
  量纲自证：ΔP = (bar/(m3/h)²) × (m3/h)² = bar，平方项与系数分母量纲对消，量纲闭合；
           报警比较两侧同为 bar，量纲一致，禁止与 kPa 混比。
*)

FUNCTION FC_DL_RoStagePressureDropCalc : BOOL
VAR_INPUT
    fStageFlowM3h    : REAL;   // 段内体积流量 [m3/h] / Stage volumetric flow [m3/h]
    fResistCoef      : REAL;   // 段阻力系数 [bar/(m3/h)²] / Stage resistance coefficient [bar/(m3/h)^2]
    fDropLimitBar    : REAL;   // 段间压降报警上限 [bar] / Pressure drop alarm limit [bar]
END_VAR
VAR_OUTPUT
    fDropBar         : REAL;   // 段间压降 [bar] / Stage pressure drop [bar]
    xAlarm           : BOOL;   // 压降超限报警 [bool] / Pressure drop over-limit alarm [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fFlowClampM3h   : REAL;   // 钳制后的段流量 [m3/h] / Clamped stage flow [m3/h]
    _fDropRawBar     : REAL;   // 未饱和的原始压降 [bar] / Raw pressure drop [bar]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 组态零闸阈值 [-] / Configuration zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_FLOW_MAX      : REAL := 1000.0;    // 段流量饱和钳制上限 [m3/h] / Stage flow saturation ceiling [m3/h]
    DL_DROP_MAX      : REAL := 50.0;      // 压降饱和钳制上限 [bar] / Pressure drop saturation ceiling [bar]
END_VAR

(* —— 段 1：非有限值闸（R19：三路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fStageFlowM3h > -DL_BIG AND fStageFlowM3h < DL_BIG)
   OR NOT (fResistCoef > -DL_BIG AND fResistCoef < DL_BIG)
   OR NOT (fDropLimitBar > -DL_BIG AND fDropLimitBar < DL_BIG) THEN
    fDropBar := 0.0;                        // 输出强制 0.0 / Output forced to zero
    xAlarm := FALSE;                        // 报警强制 FALSE，无效数据不得触发停运 / Alarm forced off
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_RoStagePressureDropCalc := FALSE; // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：组态零闸（阻力系数与报警上限都必须已标定，0 值视为未组态） —— *)
IF (ABS(fResistCoef) <= DL_EPS) OR (ABS(fDropLimitBar) <= DL_EPS) THEN
    fDropBar := 0.0;                        // 输出强制 0.0 / Output forced to zero
    xAlarm := FALSE;                        // 报警强制 FALSE / Alarm forced off
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_RoStagePressureDropCalc := FALSE; // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（流量反向 / 系数为负 / 上限为负，三者均属组态或传感器故障） —— *)
IF (fStageFlowM3h < 0.0) OR (fResistCoef < 0.0) OR (fDropLimitBar < 0.0) THEN
    fDropBar := 0.0;                        // 输出强制 0.0 / Output forced to zero
    xAlarm := FALSE;                        // 报警强制 FALSE / Alarm forced off
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_RoStagePressureDropCalc := FALSE; // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：平方律主算式（R22 方向自核：流量平方乘系数，非系数除流量） —— *)
_fFlowClampM3h := LIMIT(0.0, fStageFlowM3h, DL_FLOW_MAX);    // 流量钳 0..1000 [m3/h]
_fDropRawBar := fResistCoef * _fFlowClampM3h * _fFlowClampM3h;   // ΔP = k·Q² [bar]

(* —— 段 5：输出单点写盘（先饱和钳制，再据此判报警，保证判据用的是同一个值） —— *)
fDropBar := LIMIT(0.0, _fDropRawBar, DL_DROP_MAX);           // 压降钳 0..50 [bar]
xValid := (fResistCoef > DL_EPS)                             // 系数已标定且为正
          AND (fDropLimitBar > DL_EPS)                       // 上限已组态且为正
          AND (fStageFlowM3h >= 0.0);                        // 流量非负
xAlarm := xValid AND (fDropBar >= fDropLimitBar);            // 到达上限即报警（含触点）

(* —— 段 6：返回码（TRUE = 计算可信，与 xValid 同源） —— *)
FC_DL_RoStagePressureDropCalc := xValid;

END_FUNCTION
