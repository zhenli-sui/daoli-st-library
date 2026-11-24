(*
  FC_DL_TempDiffUnitConvert —— 温差换算 K 与摄氏差值与华氏差值，无偏移项
  分类：DL_Base | 复杂度：1 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：温差（不是温度点！）折算到基准单位 K：开尔文差与摄氏差等价（1:1），
        华氏差 × 5/9。**本件不含 273.15 偏移项**——偏移只属于温度点换算，误用会引入系统偏差。
  契约：fIn 输入温差 [源单位]，eUnit 源单位枚举；fOut 折算结果 [K]；返回 TRUE 表示 fOut 可信。
  边界：① 显式声明无偏移项（分工口径）；② 未知枚举 / 非有限输入 → FALSE + 0.0 哨兵；
        ③ 乘 0.5555555555555556 代替除法，零全局、零物理地址、零库件依赖。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TdUnit（温差单位，归属本文件，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_TdUnit :
(
    eKelvin   := 0,    // 开尔文差值（基准单位） [K] / Kelvin difference, the base unit
    eCelsius  := 1,    // 摄氏差值（与开尔文差 1:1） [K] / Celsius difference, identical to kelvin difference
    eFahrenheit := 2   // 华氏差值（× 5/9） [K] / Fahrenheit difference, scaled by five ninths
);
END_TYPE

FUNCTION FC_DL_TempDiffUnitConvert : BOOL
VAR_INPUT
    fIn   : LREAL := 0.0;              // 输入温差 [源单位] / The input temperature difference
    eUnit : E_DL_TdUnit;               // 源单位枚举 [—] / The source unit enumeration
END_VAR
VAR_OUTPUT
    fOut : LREAL;                      // 折算结果 [K] / The converted difference in kelvin
END_VAR
VAR CONSTANT
    DL_TD_ONE  : LREAL := 1.0;         // 摄氏差折开尔文差的系数（1:1） [-] / Celsius difference to kelvin difference
    DL_TD_FIVE : LREAL := 0.5555555555555556; // 5/9 常数（华氏差折开尔文差） [-] / Five ninths constant
    DL_TD_INF  : LREAL := 1.0E30;      // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_TD_Z    : LREAL := 0.0;         // 浮点零常量 [K] / The floating point zero constant
END_VAR

FC_DL_TempDiffUnitConvert := FALSE;                       // 返回值预置假 / preset the return false
fOut := DL_TD_Z;                                          // 输出预置零哨兵 [K] / preset the zero sentinel
IF (fIn <> fIn) OR (ABS(fIn) > DL_TD_INF) THEN            // 自反判 NaN 或越限判 Inf / NaN or Inf
    fOut := DL_TD_Z;                                      // 非有限值输出零哨兵 [K] / zero the non finite input
ELSE
    CASE eUnit OF
        E_DL_TdUnit.eKelvin:                              // 基准单位直通 / the base unit passes through
            fOut := fIn;                                  // 直通不换算 [K] / pass through unchanged
            FC_DL_TempDiffUnitConvert := TRUE;            // 结果可信 / the result is valid
        E_DL_TdUnit.eCelsius:                             // 摄氏差与开尔文差等价 / Celsius difference is one to one
            fOut := fIn * DL_TD_ONE;                      // 乘 1.0，无偏移项 [K] / multiply by one, no offset
            FC_DL_TempDiffUnitConvert := TRUE;            // 结果可信 / the result is valid
        E_DL_TdUnit.eFahrenheit:                          // 华氏差折开尔文差 / Fahrenheit difference to kelvin
            fOut := fIn * DL_TD_FIVE;                     // 乘 5/9，无偏移项 [K] / multiply by five ninths, no offset
            FC_DL_TempDiffUnitConvert := TRUE;            // 结果可信 / the result is valid
    ELSE
        fOut := DL_TD_Z;                                  // 未知枚举输出零哨兵 [K] / zero sentinel on an unknown unit
        FC_DL_TempDiffUnitConvert := FALSE;               // 未知枚举不可信 / an unknown unit is not valid
    END_CASE
END_IF
END_FUNCTION
