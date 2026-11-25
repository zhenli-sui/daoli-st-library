(*
  FC_DL_SpecificHeatUnitConvert —— 比热容换算 kJ/(kg*K) 与 BTU/(lb*F)
  分类：DL_Base | 复杂度：1 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：把比热容统一折算到基准单位 kJ/(kg*K)（1 BTU/(lb*F) = 4.1868 kJ/(kg*K)）。
  契约：fIn 输入值 [源单位]，eUnit 源单位枚举；fOut 折算结果 [kJ/(kg*K)]；返回 TRUE 表示 fOut 可信。
  边界：未知枚举 / 非有限输入 → 返回 FALSE，fOut 给 0.0 哨兵；无除法，零全局、零物理地址、零库件依赖。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ShcUnit（比热容单位，归属本文件，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ShcUnit :
(
    eKjPerKgK  := 0,   // 千焦每千克开（基准单位） [kJ/(kg*K)] / Kilojoule per kilogram kelvin, the base unit
    eBtuPerLbF := 1    // 英热单位每磅华氏度 [BTU/(lb*F)] / British thermal unit per pound fahrenheit
);
END_TYPE

FUNCTION FC_DL_SpecificHeatUnitConvert : BOOL
VAR_INPUT
    fIn   : LREAL := 0.0;              // 输入值 [源单位] / The input value in the source unit
    eUnit : E_DL_ShcUnit;              // 源单位枚举 [—] / The source unit enumeration
END_VAR
VAR_OUTPUT
    fOut : LREAL;                      // 折算结果 [kJ/(kg*K)] / The converted value in the base unit
END_VAR
VAR CONSTANT
    DL_SC_BTU : LREAL := 4.1868;       // 1 BTU/(lb*F) 折 kJ/(kg*K) 的系数 [-] / BTU per lb F to kJ per kg K
    DL_SC_INF : LREAL := 1.0E30;       // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_SC_Z   : LREAL := 0.0;          // 浮点零常量 [kJ/(kg*K)] / The floating point zero constant
END_VAR

FC_DL_SpecificHeatUnitConvert := FALSE;                   // 返回值预置假 / preset the return false
fOut := DL_SC_Z;                                          // 输出预置零哨兵 [kJ/(kg*K)] / preset the zero sentinel
IF (fIn <> fIn) OR (ABS(fIn) > DL_SC_INF) THEN            // 自反判 NaN 或越限判 Inf / NaN or Inf
    fOut := DL_SC_Z;                                      // 非有限值输出零哨兵 [kJ/(kg*K)] / zero the non finite input
ELSE
    CASE eUnit OF
        E_DL_ShcUnit.eKjPerKgK:                           // 基准单位直通 / the base unit passes through
            fOut := fIn;                                  // 直通不换算 [kJ/(kg*K)] / pass through unchanged
            FC_DL_SpecificHeatUnitConvert := TRUE;        // 结果可信 / the result is valid
        E_DL_ShcUnit.eBtuPerLbF:                          // 英热单位每磅华氏度 / BTU per pound fahrenheit
            fOut := fIn * DL_SC_BTU;                      // 乘 4.1868 [kJ/(kg*K)] / multiply by the factor
            FC_DL_SpecificHeatUnitConvert := TRUE;        // 结果可信 / the result is valid
    ELSE
        fOut := DL_SC_Z;                                  // 未知枚举输出零哨兵 [kJ/(kg*K)] / zero sentinel on an unknown unit
        FC_DL_SpecificHeatUnitConvert := FALSE;           // 未知枚举不可信 / an unknown unit is not valid
    END_CASE
END_IF
END_FUNCTION
