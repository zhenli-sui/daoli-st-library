(*
  ============================================================
  组件名 : FC_DL_PneuCvFlowCalc
  分类   : DL_Device
  功能   : 气动元件 Cv 值流量估算，含临界压比判据与标准状态流量折算
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
  口径说明 : 流量系数 0.865 属工程选型估算口径，压力取阀前绝对压力 [bar]，
             温度取开尔文，比重取相对空气值；输出直接为标准状态体积流量 [Nm3/h]。
             该式量纲一致，用于选型估算，精确定型须以厂商流量曲线复核。
*)

FUNCTION FC_DL_PneuCvFlowCalc : REAL
VAR_INPUT
    rCv           : REAL; // 流量系数 Cv [无量纲] flow coefficient Cv [dimensionless]
    rUpPressBarA  : REAL; // 阀前绝对压力 [bar abs] upstream absolute pressure [bar abs]
    rDownPressBarA: REAL; // 阀后绝对压力 [bar abs] downstream absolute pressure [bar abs]
    rTempC        : REAL; // 气体温度 [摄氏度] gas temperature [degree celsius]
    rGasSg        : REAL; // 相对空气比重 [无量纲] specific gravity relative to air [dimensionless]
END_VAR
VAR_OUTPUT
    rFlowNm3h : REAL; // 标准状态体积流量 [Nm3/h] normal volume flow [Nm3 per hour]
    rCritical : BOOL; // 临界流（阻塞流）标志 choked flow flag
    bValid    : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_CV_COEF   : REAL := 0.865; // 选型估算系数 sizing estimation coefficient
    DL_CRIT_RATIO: REAL := 0.528; // 空气临界压比 the critical air pressure ratio
    DL_KELVIN    : REAL := 273.15; // 摄氏到开尔文偏移 celsius to kelvin offset
    DL_EPS_R     : REAL := 1.0E-6; // 实数零判定阈值 real zero threshold
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 五输入有限性判定 finiteness verdict of the five inputs
    _rTempK : REAL := 0.0; // 绝对温度 [K] absolute temperature [K]
    _rRatio : REAL := 0.0; // 压差比 pressure drop ratio [dimensionless]
    _rFlow : REAL := 0.0; // 流量中间量 [Nm3/h] intermediate flow [Nm3 per hour]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_PneuCvFlowCalc := 0.0; // 缺省返回零 default zero return
rFlowNm3h := 0.0; // 流量预置零 flow preset to zero
rCritical := FALSE; // 临界标志预置假 critical flag preset false
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rCv = rCv) AND (rUpPressBarA = rUpPressBarA) AND (rDownPressBarA = rDownPressBarA) AND (rTempC = rTempC) AND (rGasSg = rGasSg); // 五输入自反判定 self comparison of the five inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜压力与介质闸 pressure and medium gate
IF (rUpPressBarA <= 0.0) OR (rDownPressBarA < 0.0) OR (rDownPressBarA > rUpPressBarA) THEN
    RETURN; // 阀前后压力倒置或非正 an inverted or non positive pressure pair
END_IF
IF (rGasSg <= 0.0) OR (rCv < 0.0) THEN
    RETURN; // 比重非正或 Cv 为负属配置非法 an illegal specific gravity or Cv
END_IF
// 段 4｜绝对温度与压差比 absolute temperature and the drop ratio
_rTempK := rTempC + DL_KELVIN; // 摄氏折算开尔文 convert celsius to kelvin
IF _rTempK <= DL_EPS_R THEN
    RETURN; // 绝对温度非正无法开方 a non positive absolute temperature cannot be rooted
END_IF
_rRatio := (rUpPressBarA - rDownPressBarA) / rUpPressBarA; // 压差比，除子已证为正 the drop ratio over a proven positive divisor
rCritical := _rRatio >= DL_CRIT_RATIO; // 达临界压比按阻塞流口径处理 a reached ratio is treated as choked flow
// 段 5｜主体流量估算 main flow estimation
_rFlow := DL_CV_COEF * rCv * rUpPressBarA * SQRT(1.0 / (rGasSg * _rTempK)); // 选型估算式，除子已证为正 the sizing formula over a proven positive divisor
rFlowNm3h := _rFlow; // 流量落定 land the flow
bValid := TRUE; // 结果可用 result usable
FC_DL_PneuCvFlowCalc := _rFlow; // 函数返回流量 return the flow
END_FUNCTION
