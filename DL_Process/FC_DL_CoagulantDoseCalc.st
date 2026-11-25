(*
  ============================================================
  组件名 : FC_DL_CoagulantDoseCalc
  分类   : DL_Process
  功能   : 混凝剂投加量计算，按浊度比例前馈放大基准投加率并限幅后折算小时投加量
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_CoagulantDoseCalc : REAL
VAR_INPUT
    rFlow_m3h        : REAL; // 处理水量 [m3/h] treated water flow [m3 per hour]
    rTurbidity_Ntu   : REAL; // 实测原水浊度 [NTU] measured raw water turbidity [NTU]
    rTurbidityRef    : REAL; // 基准浊度 [NTU] reference turbidity [NTU]
    rDoseRef_mgL     : REAL; // 基准投加率 [mg/L] reference dose [mg per litre]
    rDoseMax_mgL     : REAL; // 投加率上限 [mg/L] dose ceiling [mg per litre]
    rDoseMin_mgL     : REAL; // 投加率下限 [mg/L] dose floor [mg per litre]
END_VAR
VAR_OUTPUT
    rDose_mgL     : REAL; // 实际投加率 [mg/L] applied dose [mg per litre]
    rDoseRate_kgh : REAL; // 小时投加量 [kg/h] hourly dosing rate [kg per hour]
    bValid        : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_MG_PER_KG : REAL := 1000.0; // 每千克毫克数 milligrams per kilogram
    DL_EPS_R     : REAL := 1.0E-6; // 实数零判定阈值 real zero threshold
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 五实数输入有限性判定 finiteness verdict of the five real inputs
    _rRaw  : REAL := 0.0; // 前馈投加率 [mg/L] feed forward dose [mg per litre]
    _rDose : REAL := 0.0; // 限幅后的投加率 [mg/L] limited dose [mg per litre]
    _rLo   : REAL := 0.0; // 限幅下限 [mg/L] lower limit [mg per litre]
    _rHi   : REAL := 0.0; // 限幅上限 [mg/L] upper limit [mg per litre]
    _rRate : REAL := 0.0; // 小时投加量中间量 [kg/h] intermediate hourly rate [kg per hour]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_CoagulantDoseCalc := 0.0; // 缺省返回零 default zero return
rDose_mgL := 0.0; // 投加率预置零 dose preset to zero
rDoseRate_kgh := 0.0; // 小时投加量预置零 hourly rate preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rFlow_m3h = rFlow_m3h) AND (rTurbidity_Ntu = rTurbidity_Ntu) AND (rTurbidityRef = rTurbidityRef) AND (rDoseRef_mgL = rDoseRef_mgL) AND (rDoseMax_mgL = rDoseMax_mgL) AND (rDoseMin_mgL = rDoseMin_mgL); // 六输入自反判定 self comparison of the six inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜基准与流量闸 reference and flow gate
IF (rTurbidityRef <= DL_EPS_R) OR (rFlow_m3h < 0.0) OR (rTurbidity_Ntu < 0.0) OR (rDoseRef_mgL < 0.0) THEN
    RETURN; // 基准浊度非正或负流量负浊度 an illegal reference turbidity flow or dose
END_IF
// 段 4｜前馈投加率与限幅 feed forward dose and the limitation
_rRaw := rDoseRef_mgL * (rTurbidity_Ntu / rTurbidityRef); // 按浊度比例前馈 scale the dose by the turbidity ratio
_rLo := rDoseMin_mgL; // 取下限 take the floor
_rHi := rDoseMax_mgL; // 取上限 take the ceiling
IF _rLo > _rHi THEN
    _rLo := rDoseMax_mgL; // 上下限倒置时下限取原上限 an inverted pair swaps the floor
    _rHi := rDoseMin_mgL; // 上下限倒置时上限取原下限 an inverted pair swaps the ceiling
END_IF
IF _rLo < 0.0 THEN
    _rLo := 0.0; // 负下限按零处理 a negative floor becomes zero
END_IF
_rDose := LIMIT(_rLo, _rRaw, _rHi); // 限幅到上下限之间 limit the dose between the bounds
rDose_mgL := _rDose; // 投加率落定 land the dose
// 段 5｜小时投加量与出口 hourly rate and the exit
_rRate := _rDose * rFlow_m3h / DL_MG_PER_KG; // 浓度乘流量折千克 hourly mass from the dose and the flow
rDoseRate_kgh := _rRate; // 小时投加量落定 land the hourly rate
bValid := TRUE; // 结果可用 result usable
FC_DL_CoagulantDoseCalc := _rDose; // 函数返回投加率 return the dose
END_FUNCTION
