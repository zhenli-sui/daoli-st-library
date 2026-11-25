(* ===========================================================================
   组件名   : FC_DL_StrainGaugeTempComp
   分类     : DL_Device / 应变片温度补偿
   一句话   : 按敏感栅与补偿片温差、灵敏系数温度系数对读数做灵敏度与零点双重修正
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fRawStrain 原始读数 [µε]；fTempSens 敏感栅温度 [°C]；fTempComp 补偿片温度 [°C]
              fRefTemp 参考温度 [°C]；fTkSens 灵敏系数温度系数 [1/°C]
              fTkZero 零点温度漂移系数 [µε/°C]
   输出契约 : 返回值 = 修正后应变 [µε]；fSensFactor 灵敏度修正因子
              fZeroShift 零点漂移修正量 [µε]；fDeltaTSens 敏感栅温差 [°C]；xValid 输入有效
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_StrainGaugeTempComp : REAL
VAR_INPUT
    fRawStrain : REAL;                 // 原始读数 [µε] | raw strain reading [µε]
    fTempSens : REAL := 25.0;          // 敏感栅温度 [°C] | sensing grid temperature [°C]
    fTempComp : REAL := 25.0;          // 补偿片温度 [°C] | compensation grid temperature [°C]
    fRefTemp : REAL := 20.0;           // 参考温度 [°C] | reference temperature [°C]
    fTkSens : REAL := 0.0002;          // 灵敏系数温度系数 [1/°C] | tc of gauge factor [1/°C]
    fTkZero : REAL := 1.0;             // 零点温度漂移系数 [µε/°C] | zero tc [µε/°C]
END_VAR
VAR_OUTPUT
    fSensFactor : REAL;                // 灵敏度修正因子 | sensitivity correction factor
    fZeroShift : REAL;                 // 零点漂移修正量 [µε] | zero shift correction [µε]
    fDeltaTSens : REAL;                // 敏感栅温差 [°C] | sensing grid temp delta [°C]
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    _fOut : REAL;                      // 修正结果 [µε] | corrected result [µε]
END_VAR

// ---- 输出预置 ----
fSensFactor := 1.0;
fZeroShift := 0.0;
fDeltaTSens := 0.0;
xValid := FALSE;
FC_DL_StrainGaugeTempComp := 0.0;

// ---- 非有限值拦截 ----
IF (fRawStrain <> fRawStrain) OR ((fRawStrain - fRawStrain) <> (fRawStrain - fRawStrain)) THEN
    RETURN;
END_IF
IF (fTempSens <> fTempSens) OR ((fTempSens - fTempSens) <> (fTempSens - fTempSens)) THEN
    RETURN;
END_IF
IF (fTempComp <> fTempComp) OR ((fTempComp - fTempComp) <> (fTempComp - fTempComp)) THEN
    RETURN;
END_IF
IF (fRefTemp <> fRefTemp) OR ((fRefTemp - fRefTemp) <> (fRefTemp - fRefTemp)) THEN
    RETURN;
END_IF

// ---- 温差计算：敏感栅温差用于灵敏度修正，补偿片温差用于零点修正 ----
fDeltaTSens := fTempSens - fRefTemp;
fSensFactor := 1.0 + fTkSens * fDeltaTSens;
fZeroShift := fTkZero * (fTempComp - fRefTemp);

// ---- 防除零：灵敏度因子必须显著非零 ----
IF ABS(fSensFactor) < 0.000000001 THEN
    RETURN;
END_IF

// ---- 先除灵敏度因子消去灵敏度温漂，再扣零点温漂 ----
_fOut := fRawStrain / fSensFactor - fZeroShift;     // 分母已守卫

xValid := TRUE;
FC_DL_StrainGaugeTempComp := _fOut;
END_FUNCTION
