(*
  FC_DL_EnthalpyUnitConvert —— 比焓换算 kJ/kg 与 kcal/kg 与 BTU/lb
  分类：DL_Base | 复杂度：1 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：把三种比焓单位统一折算到基准单位 kJ/kg（1 kcal/kg = 4.1868 kJ/kg；1 BTU/lb = 2.326 kJ/kg）。
  契约：fIn 输入值 [源单位]，eUnit 源单位枚举；fOut 折算结果 [kJ/kg]；返回 TRUE 表示 fOut 可信。
  边界：未知枚举 / 非有限输入（NaN 自反判、Inf 用 1.0E30 绝对上限判）→ 返回 FALSE，fOut 给 0.0 哨兵；
        无除法（纯乘法定标），零全局、零物理地址、零库件依赖。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_EnthUnit（比焓单位，归属本文件，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_EnthUnit :
(
    eKjPerKg   := 0,   // 千焦每千克（基准单位） [kJ/kg] / Kilojoule per kilogram, the base unit
    eKcalPerKg := 1,   // 千卡每千克 [kcal/kg] / Kilocalorie per kilogram
    eBtuPerLb  := 2    // 英热单位每磅 [BTU/lb] / British thermal unit per pound
);
END_TYPE

FUNCTION FC_DL_EnthalpyUnitConvert : BOOL
VAR_INPUT
    fIn   : LREAL := 0.0;              // 输入值 [源单位] / The input value in the source unit
    eUnit : E_DL_EnthUnit;             // 源单位枚举 [—] / The source unit enumeration
END_VAR
VAR_OUTPUT
    fOut : LREAL;                      // 折算结果 [kJ/kg] / The converted value in the base unit
END_VAR
VAR CONSTANT
    DL_EU_KCAL : LREAL := 4.1868;      // 1 kcal/kg 折 kJ/kg 的系数 [-] / kcal per kg to kJ per kg
    DL_EU_BTU  : LREAL := 2.326;       // 1 BTU/lb 折 kJ/kg 的系数 [-] / BTU per lb to kJ per kg
    DL_EU_INF  : LREAL := 1.0E30;      // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_EU_Z    : LREAL := 0.0;         // 浮点零常量 [kJ/kg] / The floating point zero constant
END_VAR

FC_DL_EnthalpyUnitConvert := FALSE;                       // 返回值预置假 / preset the return false
fOut := DL_EU_Z;                                          // 输出预置零哨兵 [kJ/kg] / preset the zero sentinel
IF (fIn <> fIn) OR (ABS(fIn) > DL_EU_INF) THEN            // 自反判 NaN 或越限判 Inf / NaN or Inf
    fOut := DL_EU_Z;                                      // 非有限值输出零哨兵 [kJ/kg] / zero the non finite input
ELSE
    CASE eUnit OF
        E_DL_EnthUnit.eKjPerKg:                           // 基准单位直通 / the base unit passes through
            fOut := fIn;                                  // 直通不换算 [kJ/kg] / pass through unchanged
            FC_DL_EnthalpyUnitConvert := TRUE;            // 结果可信 / the result is valid
        E_DL_EnthUnit.eKcalPerKg:                         // 千卡每千克 / kilocalorie per kilogram
            fOut := fIn * DL_EU_KCAL;                     // 乘 4.1868 [kJ/kg] / multiply by the factor
            FC_DL_EnthalpyUnitConvert := TRUE;            // 结果可信 / the result is valid
        E_DL_EnthUnit.eBtuPerLb:                          // 英热单位每磅 / British thermal unit per pound
            fOut := fIn * DL_EU_BTU;                      // 乘 2.326 [kJ/kg] / multiply by the factor
            FC_DL_EnthalpyUnitConvert := TRUE;            // 结果可信 / the result is valid
    ELSE
        fOut := DL_EU_Z;                                  // 未知枚举输出零哨兵 [kJ/kg] / zero sentinel on an unknown unit
        FC_DL_EnthalpyUnitConvert := FALSE;               // 未知枚举不可信 / an unknown unit is not valid
    END_CASE
END_IF
END_FUNCTION
