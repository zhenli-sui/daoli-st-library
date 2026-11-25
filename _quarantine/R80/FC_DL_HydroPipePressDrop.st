(*
  ============================================================
  组件名 : FC_DL_HydroPipePressDrop
  分类   : DL_Device
  功能   : 液压管路压降计算，由流量管径长度求流速、雷诺数、摩阻系数与压降
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C2
  版本   : 1.0.0
  ============================================================
  口径说明 : 工作介质取液压油，密度按 850 kg/m3 常量代入；黏度由 cSt 折算为 m2/s；
             层流区用 64/Re，湍流区用 Blasius 式 0.3164/Re^0.25；粗糙度引脚仅登记
             供上层记录，本件不进入摩阻判据（Colebrook 迭代属另一件边界）。
*)

FUNCTION FC_DL_HydroPipePressDrop : REAL
VAR_INPUT
    rFlow_lpm  : REAL; // 体积流量 [l/min] volume flow [l per minute]
    rDia_mm    : REAL; // 管内径 [mm] pipe inner diameter [mm]
    rLength_m  : REAL; // 管长 [m] pipe length [m]
    rVisc_cSt  : REAL; // 运动黏度 [cSt] kinematic viscosity [centistoke]
    rRough_mm  : REAL; // 管内壁粗糙度 [mm] inner wall roughness [mm]
END_VAR
VAR_OUTPUT
    rVel_m_s : REAL; // 管内流速 [m/s] pipe velocity [m per second]
    rRe      : REAL; // 雷诺数 [无量纲] Reynolds number [dimensionless]
    rDrop_bar: REAL; // 沿程压降 [bar] friction pressure drop [bar]
    bValid   : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_PI_4     : REAL := 0.7853982; // 四分之圆周率 pi divided by four
    DL_MM_TO_M  : REAL := 1000.0; // 每米毫米数 millimetres per metre
    DL_LPM_TO_M3S : REAL := 60000.0; // 升每分到立方米每秒的除数 divisor from litre per minute to cubic metre per second
    DL_CST_TO_M2S : REAL := 1.0E-6; // 厘斯到平方米每秒的乘子 multiplier from centistoke to square metre per second
    DL_DENSITY  : REAL := 850.0; // 液压油密度 [kg/m3] hydraulic oil density [kg per cubic metre]
    DL_RE_LAM   : REAL := 2300.0; // 层流上限雷诺数 laminar Reynolds ceiling
    DL_LAM_COEF : REAL := 64.0; // 层流摩阻系数分子 laminar friction numerator
    DL_BLA_COEF : REAL := 0.3164; // Blasius 式系数 Blasius coefficient
    DL_BLA_EXP  : REAL := 0.25; // Blasius 式指数 Blasius exponent
    DL_PA_TO_BAR: REAL := 100000.0; // 帕到巴换算 pascal per bar
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 五输入有限性判定 finiteness verdict of the five inputs
    _rDiaM : REAL := 0.0; // 管径折算 [m] diameter in metre [m]
    _rArea : REAL := 0.0; // 管截面面积 [m2] pipe section area [m2]
    _rNu   : REAL := 0.0; // 运动黏度折算 [m2/s] viscosity in square metre per second
    _rQ    : REAL := 0.0; // 体积流量折算 [m3/s] flow in cubic metre per second
    _rVel  : REAL := 0.0; // 流速中间量 [m/s] intermediate velocity [m per second]
    _rRe   : REAL := 0.0; // 雷诺数中间量 [无量纲] intermediate Reynolds number [dimensionless]
    _rLam  : REAL := 0.0; // 摩阻系数 [无量纲] friction factor [dimensionless]
    _rDrop : REAL := 0.0; // 压降中间量 [Pa] intermediate drop [pascal]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_HydroPipePressDrop := 0.0; // 缺省返回零 default zero return
rVel_m_s := 0.0; // 流速预置零 velocity preset to zero
rRe := 0.0; // 雷诺数预置零 Reynolds preset to zero
rDrop_bar := 0.0; // 压降预置零 drop preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rFlow_lpm = rFlow_lpm) AND (rDia_mm = rDia_mm) AND (rLength_m = rLength_m) AND (rVisc_cSt = rVisc_cSt) AND (rRough_mm = rRough_mm); // 五输入自反判定 self comparison of the five inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜几何与黏度闸 geometry and viscosity gate
IF (rDia_mm <= 0.0) OR (rLength_m < 0.0) OR (rFlow_lpm < 0.0) THEN
    RETURN; // 管径非正或负长度负流量 an illegal diameter length or flow
END_IF
IF rVisc_cSt <= 0.0 THEN
    RETURN; // 黏度非正无法算雷诺数 a non positive viscosity cannot carry Reynolds
END_IF
// 段 4｜流速与雷诺数 velocity and the Reynolds number
_rDiaM := rDia_mm / DL_MM_TO_M; // 管径折算为米 convert the diameter to metre
_rArea := DL_PI_4 * _rDiaM * _rDiaM; // 管截面面积 pipe section area
_rQ := rFlow_lpm / DL_LPM_TO_M3S; // 流量折算为立方米每秒 convert the flow
_rVel := _rQ / _rArea; // 流速，除子为已证正面积 velocity over a proven positive area
_rNu := rVisc_cSt * DL_CST_TO_M2S; // 黏度折算为平方米每秒 convert the viscosity
_rRe := _rVel * _rDiaM / _rNu; // 雷诺数，除子为已证正黏度 Reynolds over a proven positive viscosity
rVel_m_s := _rVel; // 流速落定 land the velocity
rRe := _rRe; // 雷诺数落定 land the Reynolds number
// 段 5｜零流早退：雷诺数近零时压降为零 zero flow early exit with a zero drop
IF _rRe < 1.0 THEN
    bValid := TRUE; // 零流工况结果有效 a zero flow case is still usable
    RETURN; // 压降保持零 the drop stays zero
END_IF
// 段 6｜摩阻系数分区分支 friction factor by flow regime
IF _rRe < DL_RE_LAM THEN
    _rLam := DL_LAM_COEF / _rRe; // 层流区 sixty four over Reynolds
ELSE
    IF _rRe > 1.0E30 THEN
        RETURN; // 雷诺数越出数值上限 refuse an out of scale Reynolds number
    END_IF
    _rLam := DL_BLA_COEF / EXPT(_rRe, DL_BLA_EXP); // 湍流区 Blasius 式 the Blasius form for the turbulent regime
END_IF
// 段 7｜压降与出口 drop and the exit
_rDrop := _rLam * (rLength_m / _rDiaM) * (DL_DENSITY * _rVel * _rVel / 2.0); // 沿程压降 friction pressure drop
rDrop_bar := _rDrop / DL_PA_TO_BAR; // 压降换算为巴 convert the drop to bar
bValid := TRUE; // 结果可用 result usable
FC_DL_HydroPipePressDrop := rDrop_bar; // 函数返回压降 return the drop
END_FUNCTION
