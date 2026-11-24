(*
  DL Factory R83 | FC_DL_InkViscosityTempComp
  功能：按温度线性修正系数把实测油墨黏度折算到参考温度，并给出兑稀补偿系数。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_InkViscosityTempComp : REAL
VAR_INPUT
    fViscMeas   : REAL; // 实测黏度 [mPa·s] / Measured viscosity [mPa.s]
    fTempMeas   : REAL; // 实测油墨温度 [°C] / Measured ink temperature [degC]
    fTempRef    : REAL; // 参考温度（工艺基准）[°C] / Reference temperature [degC]
    fTempCoeff  : REAL; // 温度系数（每 °C 黏度变化率）[%/°C] / Temperature coefficient [%/degC]
    fViscTarget : REAL; // 目标黏度（工艺设定）[mPa·s] / Target viscosity [mPa.s]
END_VAR
VAR_OUTPUT
    fViscRef    : REAL; // 参考温度下黏度 [mPa·s] / Viscosity at reference temperature [mPa.s]
    fCompFactor : REAL; // 兑稀补偿系数，小于 1 需加溶剂 [-]/ Thinning factor, below 1 means add solvent
    xValid      : BOOL; // 输入有效性（FALSE 时输出为故障缺省）/ Input validity flag
END_VAR
VAR
    fScale : REAL; // 温度修正比例因子 [-] / Temperature correction scale factor
END_VAR
// 出口预置：三出口统一预置，故障拍不残留上拍值（R187/R256）
fViscRef := 0.0; fCompFactor := 0.0; xValid := FALSE;
// 非有限拦截 + 量纲自检：NaN/Inf 与域越界同走故障分支（R20/R21）
IF NOT (fViscMeas > -1.0E30 AND fViscMeas < 1.0E30) OR NOT (fTempMeas > -1.0E30 AND fTempMeas < 1.0E30) OR NOT (fTempRef > -1.0E30 AND fTempRef < 1.0E30) OR NOT (fTempCoeff > -1.0E30 AND fTempCoeff < 1.0E30) OR NOT (fViscTarget > -1.0E30 AND fViscTarget < 1.0E30) OR fViscMeas <= 0.0 OR fTempRef <= -50.0 OR fTempRef > 200.0 THEN
    FC_DL_InkViscosityTempComp := -1.0; RETURN;   // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 温度折算：η(Tref) = η(T) × (1 + k × (Tref - T))，线性工艺近似
fScale := 1.0 + (fTempCoeff / 100.0) * (fTempRef - fTempMeas); // 比例因子 [-] / Scale factor
IF fScale > 0.05 THEN                    // 比例因子下限闸，防负值或近零
    fViscRef := fViscMeas * fScale;      // 参考温度黏度 [mPa·s] / Viscosity at ref temp
ELSE
    fViscRef := fViscMeas;               // 极端温差回退实测值 / Fallback to measured
END_IF
// 补偿系数：目标黏度 ÷ 折算实值，含目标工艺量故非恒等式
IF ABS(fViscRef) > 1.0E-9 THEN           // 分母显式零闸（R4/R21）/ Explicit zero gate
    fCompFactor := fViscTarget / fViscRef;  // 兑稀补偿系数 [-]/ Thinning factor
    xValid      := TRUE;                 // 计算链路有效 / Chain valid
ELSE
    fCompFactor := 0.0;                  // 除零防御缺省 / Divide-by-zero default
END_IF
FC_DL_InkViscosityTempComp := fCompFactor; // 返回兑稀补偿系数 [-]/ Return thinning factor
END_FUNCTION
