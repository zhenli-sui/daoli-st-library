(*
  FC_DL_HtcUnitConvert —— 传热系数换算 W/(m2*K) 与 kcal/(h*m2*C) 与 BTU/(h*ft2*F)
  分类：DL_Base | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：把传热系数统一折算到基准单位 W/(m2*K)：
        1 kcal/(h*m2*C) = 1.163 W/(m2*K)；1 BTU/(h*ft2*F) = 5.678263 W/(m2*K)。
  契约：fIn 输入值 [源单位]，eUnit 源单位枚举；fOut 折算结果 [W/(m2*K)]；返回 TRUE 表示 fOut 可信。
  边界：未知枚举 / 非有限输入 → 返回 FALSE，fOut 给 0.0 哨兵；无除法，零全局、零物理地址、零库件依赖。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_HtcUnit（传热系数单位，归属本文件，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_HtcUnit :
(
    eWattPerM2K    := 0,   // 瓦每平方米开（基准单位） [W/(m2*K)] / Watt per square metre kelvin, the base unit
    eKcalPerHM2C   := 1,   // 千卡每小时平方米摄氏度 [kcal/(h*m2*C)] / Kilocalorie per hour square metre celsius
    eBtuPerHFt2F   := 2    // 英热单位每小时平方英尺华氏度 [BTU/(h*ft2*F)] / BTU per hour square foot fahrenheit
);
END_TYPE

FUNCTION FC_DL_HtcUnitConvert : BOOL
VAR_INPUT
    fIn   : LREAL := 0.0;              // 输入值 [源单位] / The input value in the source unit
    eUnit : E_DL_HtcUnit;              // 源单位枚举 [—] / The source unit enumeration
END_VAR
VAR_OUTPUT
    fOut : LREAL;                      // 折算结果 [W/(m2*K)] / The converted value in the base unit
END_VAR
VAR CONSTANT
    DL_HT_KCAL : LREAL := 1.163;       // kcal/(h*m2*C) 折 W/(m2*K) 的系数 [-] / kcal to watt per square metre kelvin
    DL_HT_BTU  : LREAL := 5.678263;    // BTU/(h*ft2*F) 折 W/(m2*K) 的系数 [-] / BTU to watt per square metre kelvin
    DL_HT_INF  : LREAL := 1.0E30;      // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_HT_Z    : LREAL := 0.0;         // 浮点零常量 [W/(m2*K)] / The floating point zero constant
END_VAR

FC_DL_HtcUnitConvert := FALSE;                            // 返回值预置假 / preset the return false
fOut := DL_HT_Z;                                          // 输出预置零哨兵 [W/(m2*K)] / preset the zero sentinel
IF (fIn <> fIn) OR (ABS(fIn) > DL_HT_INF) THEN            // 自反判 NaN 或越限判 Inf / NaN or Inf
    fOut := DL_HT_Z;                                      // 非有限值输出零哨兵 [W/(m2*K)] / zero the non finite input
ELSE
    CASE eUnit OF
        E_DL_HtcUnit.eWattPerM2K:                         // 基准单位直通 / the base unit passes through
            fOut := fIn;                                  // 直通不换算 [W/(m2*K)] / pass through unchanged
            FC_DL_HtcUnitConvert := TRUE;                 // 结果可信 / the result is valid
        E_DL_HtcUnit.eKcalPerHM2C:                        // 千卡每小时平方米摄氏度 / kcal per hour square metre celsius
            fOut := fIn * DL_HT_KCAL;                     // 乘 1.163 [W/(m2*K)] / multiply by the factor
            FC_DL_HtcUnitConvert := TRUE;                 // 结果可信 / the result is valid
        E_DL_HtcUnit.eBtuPerHFt2F:                        // 英热单位每小时平方英尺华氏度 / BTU per hour square foot fahrenheit
            fOut := fIn * DL_HT_BTU;                      // 乘 5.678263 [W/(m2*K)] / multiply by the factor
            FC_DL_HtcUnitConvert := TRUE;                 // 结果可信 / the result is valid
    ELSE
        fOut := DL_HT_Z;                                  // 未知枚举输出零哨兵 [W/(m2*K)] / zero sentinel on an unknown unit
        FC_DL_HtcUnitConvert := FALSE;                    // 未知枚举不可信 / an unknown unit is not valid
    END_CASE
END_IF
END_FUNCTION
