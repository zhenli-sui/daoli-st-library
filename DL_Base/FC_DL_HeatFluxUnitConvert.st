(*
  FC_DL_HeatFluxUnitConvert —— 热流密度换算 W/m2 与 kcal/(h*m2)
  分类：DL_Base | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：把热流密度统一折算到基准单位 W/m2（1 kcal/(h*m2) = 1.163 W/m2）。
  契约：fIn 输入值 [源单位]，eUnit 源单位枚举；fOut 折算结果 [W/m2]；返回 TRUE 表示 fOut 可信。
  边界：未知枚举 / 非有限输入 → 返回 FALSE，fOut 给 0.0 哨兵；无除法，零全局、零物理地址、零库件依赖。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_HfxUnit（热流密度单位，归属本文件，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_HfxUnit :
(
    eWattPerM2    := 0,   // 瓦每平方米（基准单位） [W/m2] / Watt per square metre, the base unit
    eKcalPerHM2   := 1    // 千卡每小时平方米 [kcal/(h*m2)] / Kilocalorie per hour square metre
);
END_TYPE

FUNCTION FC_DL_HeatFluxUnitConvert : BOOL
VAR_INPUT
    fIn   : LREAL := 0.0;              // 输入值 [源单位] / The input value in the source unit
    eUnit : E_DL_HfxUnit;              // 源单位枚举 [—] / The source unit enumeration
END_VAR
VAR_OUTPUT
    fOut : LREAL;                      // 折算结果 [W/m2] / The converted value in the base unit
END_VAR
VAR CONSTANT
    DL_HF_KCAL : LREAL := 1.163;       // 1 kcal/(h*m2) 折 W/m2 的系数 [-] / kcal per hour square metre to watt per square metre
    DL_HF_INF  : LREAL := 1.0E30;      // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_HF_Z    : LREAL := 0.0;         // 浮点零常量 [W/m2] / The floating point zero constant
END_VAR

FC_DL_HeatFluxUnitConvert := FALSE;                       // 返回值预置假 / preset the return false
fOut := DL_HF_Z;                                          // 输出预置零哨兵 [W/m2] / preset the zero sentinel
IF (fIn <> fIn) OR (ABS(fIn) > DL_HF_INF) THEN            // 自反判 NaN 或越限判 Inf / NaN or Inf
    fOut := DL_HF_Z;                                      // 非有限值输出零哨兵 [W/m2] / zero the non finite input
ELSE
    CASE eUnit OF
        E_DL_HfxUnit.eWattPerM2:                          // 基准单位直通 / the base unit passes through
            fOut := fIn;                                  // 直通不换算 [W/m2] / pass through unchanged
            FC_DL_HeatFluxUnitConvert := TRUE;            // 结果可信 / the result is valid
        E_DL_HfxUnit.eKcalPerHM2:                         // 千卡每小时平方米 / kcal per hour square metre
            fOut := fIn * DL_HF_KCAL;                     // 乘 1.163 [W/m2] / multiply by the factor
            FC_DL_HeatFluxUnitConvert := TRUE;            // 结果可信 / the result is valid
    ELSE
        fOut := DL_HF_Z;                                  // 未知枚举输出零哨兵 [W/m2] / zero sentinel on an unknown unit
        FC_DL_HeatFluxUnitConvert := FALSE;               // 未知枚举不可信 / an unknown unit is not valid
    END_CASE
END_IF
END_FUNCTION
