(*
  FC_DL_ConcUnitConvert —— 浓度换算 ppm 与 % 与 mg/L
  分类：DL_Base | 复杂度：1 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：把三种浓度单位统一折算到基准单位 mg/L（稀溶液口径：1 ppm ≈ 1 mg/L；1 % = 10000 mg/L）。
  契约：fIn 输入值 [源单位]，eUnit 源单位枚举；fOut 折算结果 [mg/L]；返回 TRUE 表示 fOut 可信。
  边界：① 稀溶液近似已显式声明，高浓度 / 非水基介质不得直接套用；② 未知枚举 / 非有限输入 → FALSE + 0.0 哨兵；
        ③ 无除法，零全局、零物理地址、零库件依赖。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CncUnit（浓度单位，归属本文件，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CncUnit :
(
    eMgPerL   := 0,    // 毫克每升（基准单位，稀溶液近似等于 ppm） [mg/L] / Milligram per litre, the base unit
    ePpm      := 1,    // 百万分之一（体积比，稀溶液按 1 mg/L 折算） [ppm] / Parts per million, approximated
    ePercent  := 2     // 百分比浓度（= 10000 mg/L） [%] / Percent concentration
);
END_TYPE

FUNCTION FC_DL_ConcUnitConvert : BOOL
VAR_INPUT
    fIn   : LREAL := 0.0;              // 输入值 [源单位] / The input value in the source unit
    eUnit : E_DL_CncUnit;              // 源单位枚举 [—] / The source unit enumeration
END_VAR
VAR_OUTPUT
    fOut : LREAL;                      // 折算结果 [mg/L] / The converted value in the base unit
END_VAR
VAR CONSTANT
    DL_CN_PPM : LREAL := 1.0;          // 1 ppm 折 mg/L 的系数（稀溶液） [-] / ppm to mg per litre, dilute solution
    DL_CN_PCT : LREAL := 10000.0;      // 1 % 折 mg/L 的系数 [-] / percent to mg per litre
    DL_CN_INF : LREAL := 1.0E30;       // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_CN_Z   : LREAL := 0.0;          // 浮点零常量 [mg/L] / The floating point zero constant
END_VAR

FC_DL_ConcUnitConvert := FALSE;                           // 返回值预置假 / preset the return false
fOut := DL_CN_Z;                                          // 输出预置零哨兵 [mg/L] / preset the zero sentinel
IF (fIn <> fIn) OR (ABS(fIn) > DL_CN_INF) THEN            // 自反判 NaN 或越限判 Inf / NaN or Inf
    fOut := DL_CN_Z;                                      // 非有限值输出零哨兵 [mg/L] / zero the non finite input
ELSE
    CASE eUnit OF
        E_DL_CncUnit.eMgPerL:                             // 基准单位直通 / the base unit passes through
            fOut := fIn;                                  // 直通不换算 [mg/L] / pass through unchanged
            FC_DL_ConcUnitConvert := TRUE;                // 结果可信 / the result is valid
        E_DL_CncUnit.ePpm:                                // 百万分之一（体积比） / parts per million
            fOut := fIn * DL_CN_PPM;                      // 按稀溶液 1:1 折算 [mg/L] / dilute solution conversion
            FC_DL_ConcUnitConvert := TRUE;                // 结果可信 / the result is valid
        E_DL_CncUnit.ePercent:                            // 百分比浓度 / percent concentration
            fOut := fIn * DL_CN_PCT;                      // 乘 10000 [mg/L] / multiply by the factor
            FC_DL_ConcUnitConvert := TRUE;                // 结果可信 / the result is valid
    ELSE
        fOut := DL_CN_Z;                                  // 未知枚举输出零哨兵 [mg/L] / zero sentinel on an unknown unit
        FC_DL_ConcUnitConvert := FALSE;                   // 未知枚举不可信 / an unknown unit is not valid
    END_CASE
END_IF
END_FUNCTION
