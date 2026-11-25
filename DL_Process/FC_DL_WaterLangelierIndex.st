(*
  ============================================================
  组件名 : FC_DL_WaterLangelierIndex
  分类   : DL_Process
  功能   : 水质朗格利尔饱和指数计算，由温度钙硬度碱度含盐量与 pH 判结垢或腐蚀倾向
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C2
  版本   : 1.0.0
  ============================================================
  口径说明 : A 为含盐量项 (log10(TDS)-1)/10，B 为温度项 -13.12*log10(T+273.15)+34.55，
             C 为钙硬度项 log10(CaHard)-0.4，D 为碱度项 log10(Alk)，pHs=(9.3+A+B)-(C+D)。
             本库 LOG 为十进制对数。指数大于 0.5 判结垢倾向，小于 -0.5 判腐蚀倾向。
*)

FUNCTION FC_DL_WaterLangelierIndex : REAL
VAR_INPUT
    rTempC      : REAL; // 水温 [摄氏度] water temperature [degree celsius]
    rCaHard_mgL : REAL; // 钙硬度（以碳酸钙计）[mg/L] calcium hardness as calcium carbonate [mg per litre]
    rAlk_mgL    : REAL; // 总碱度（以碳酸钙计）[mg/L] total alkalinity as calcium carbonate [mg per litre]
    rTds_mgL    : REAL; // 溶解性总固体 [mg/L] total dissolved solids [mg per litre]
    rPh         : REAL; // 实测 pH 值 [无量纲] measured pH value [dimensionless]
END_VAR
VAR_OUTPUT
    rLsi      : REAL; // 朗格利尔指数 [无量纲] Langelier saturation index [dimensionless]
    nTendency : INT; // 倾向 0平衡 1结垢 2腐蚀 [档] tendency 0 balanced, 1 scaling, 2 corrosive [band]
    rPhs      : REAL; // 饱和 pH 值 [无量纲] saturation pH value [dimensionless]
    bValid    : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_KELVIN    : REAL := 273.15; // 摄氏到开尔文偏移 celsius to kelvin offset
    DL_B_SLOPE   : REAL := 13.12; // 温度项斜率 the temperature term slope
    DL_B_OFFSET  : REAL := 34.55; // 温度项偏移 the temperature term offset
    DL_C_OFFSET  : REAL := 0.4; // 钙硬度项偏移 the calcium term offset
    DL_PHS_BASE  : REAL := 9.3; // 饱和 pH 基准常数 the saturation pH base constant
    DL_LSI_BAND  : REAL := 0.5; // 倾向判定带宽 [无量纲] tendency band [dimensionless]
    DL_TEN       : REAL := 10.0; // 含盐量项换算系数 the salinity term factor
    DL_EPS_R     : REAL := 1.0E-6; // 实数零判定阈值 real zero threshold
END_VAR
VAR
    _bFin : BOOL := FALSE; // 五输入有限性判定 finiteness verdict of the five inputs
    _rTempK : REAL := 0.0; // 绝对温度 [K] absolute temperature [K]
    _rA   : REAL := 0.0; // 含盐量项 [无量纲] salinity term [dimensionless]
    _rB   : REAL := 0.0; // 温度项 [无量纲] temperature term [dimensionless]
    _rC   : REAL := 0.0; // 钙硬度项 [无量纲] calcium term [dimensionless]
    _rD   : REAL := 0.0; // 碱度项 [无量纲] alkalinity term [dimensionless]
    _rPhs : REAL := 0.0; // 饱和 pH 中间量 [无量纲] intermediate saturation pH [dimensionless]
    _rLsi : REAL := 0.0; // 指数中间量 [无量纲] intermediate index [dimensionless]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_WaterLangelierIndex := 0.0; // 缺省返回零 default zero return
rLsi := 0.0; // 指数预置零 index preset to zero
nTendency := 0; // 倾向预置平衡 tendency preset balanced
rPhs := 0.0; // 饱和 pH 预置零 saturation pH preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rTempC = rTempC) AND (rCaHard_mgL = rCaHard_mgL) AND (rAlk_mgL = rAlk_mgL) AND (rTds_mgL = rTds_mgL) AND (rPh = rPh); // 五输入自反判定 self comparison of the five inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜取对数项的正值闸 positive value gate for the logarithm terms
IF (rCaHard_mgL <= DL_EPS_R) OR (rAlk_mgL <= DL_EPS_R) OR (rTds_mgL <= DL_EPS_R) THEN
    RETURN; // 浓度非正无法取对数 a non positive concentration cannot carry a logarithm
END_IF
_rTempK := rTempC + DL_KELVIN; // 摄氏折算绝对温度 celsius to absolute temperature
IF _rTempK <= DL_EPS_R THEN
    RETURN; // 绝对温度非正无法取对数 a non positive absolute temperature cannot carry a logarithm
END_IF
// 段 4｜四项折算与饱和 pH the four terms and the saturation pH
_rA := (LOG(rTds_mgL) - 1.0) / DL_TEN; // 含盐量项 salinity term
_rB := 0.0 - DL_B_SLOPE * LOG(_rTempK) + DL_B_OFFSET; // 温度项 temperature term
_rC := LOG(rCaHard_mgL) - DL_C_OFFSET; // 钙硬度项 calcium hardness term
_rD := LOG(rAlk_mgL); // 碱度项 alkalinity term
_rPhs := (DL_PHS_BASE + _rA + _rB) - (_rC + _rD); // 饱和 pH saturation pH
rPhs := _rPhs; // 饱和 pH 落定 land the saturation pH
// 段 5｜指数与倾向判定 index and the tendency verdict
_rLsi := rPh - _rPhs; // 实测 pH 减饱和 pH measured minus the saturation value
rLsi := _rLsi; // 指数落定 land the index
IF _rLsi > DL_LSI_BAND THEN
    nTendency := 1; // 结垢倾向 scaling tendency
ELSIF _rLsi < (0.0 - DL_LSI_BAND) THEN
    nTendency := 2; // 腐蚀倾向 corrosive tendency
ELSE
    nTendency := 0; // 基本平衡 nearly balanced
END_IF
bValid := TRUE; // 结果可用 result usable
FC_DL_WaterLangelierIndex := _rLsi; // 函数返回指数 return the index
END_FUNCTION
