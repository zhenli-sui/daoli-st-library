(*
  FC_DL_CurrentUnitConvert —— 电流换算 A/mA/kA
  分类：DL_Base | 复杂度：1 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：把电流统一折算到基准单位 A：A 直通、mA 乘 0.001、kA 乘 1000。
  契约：fIn 输入值 [源单位]，eUnit 源单位枚举；fOut 折算结果 [A]；返回 TRUE 表示 fOut 可信。
  边界：未知枚举 / 非有限输入 → 返回 FALSE，fOut 给 0.0 哨兵；无除法，零全局、零物理地址、零库件依赖。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CurUnit（电流单位，归属本文件，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CurUnit :
(
    eAmpere   := 0,    // 安培（基准单位） [A] / Ampere, the base unit
    eMilliAmp := 1,    // 毫安 [mA] / Milliampere
    eKiloAmp  := 2     // 千安 [kA] / Kiloampere
);
END_TYPE

FUNCTION FC_DL_CurrentUnitConvert : BOOL
VAR_INPUT
    fIn   : LREAL := 0.0;              // 输入值 [源单位] / The input value in the source unit
    eUnit : E_DL_CurUnit;              // 源单位枚举 [—] / The source unit enumeration
END_VAR
VAR_OUTPUT
    fOut : LREAL;                      // 折算结果 [A] / The converted value in the base unit
END_VAR
VAR CONSTANT
    DL_CU_MA  : LREAL := 0.001;        // 1 mA 折 A 的系数 [-] / milliampere to ampere
    DL_CU_KA  : LREAL := 1000.0;       // 1 kA 折 A 的系数 [-] / kiloampere to ampere
    DL_CU_INF : LREAL := 1.0E30;       // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_CU_Z   : LREAL := 0.0;          // 浮点零常量 [A] / The floating point zero constant
END_VAR

FC_DL_CurrentUnitConvert := FALSE;                        // 返回值预置假 / preset the return false
fOut := DL_CU_Z;                                          // 输出预置零哨兵 [A] / preset the zero sentinel
IF (fIn <> fIn) OR (ABS(fIn) > DL_CU_INF) THEN            // 自反判 NaN 或越限判 Inf / NaN or Inf
    fOut := DL_CU_Z;                                      // 非有限值输出零哨兵 [A] / zero the non finite input
ELSE
    CASE eUnit OF
        E_DL_CurUnit.eAmpere:                             // 基准单位直通 / the base unit passes through
            fOut := fIn;                                  // 直通不换算 [A] / pass through unchanged
            FC_DL_CurrentUnitConvert := TRUE;             // 结果可信 / the result is valid
        E_DL_CurUnit.eMilliAmp:                           // 毫安折安 / milliampere to ampere
            fOut := fIn * DL_CU_MA;                       // 乘 0.001 [A] / multiply by the factor
            FC_DL_CurrentUnitConvert := TRUE;             // 结果可信 / the result is valid
        E_DL_CurUnit.eKiloAmp:                            // 千安折安 / kiloampere to ampere
            fOut := fIn * DL_CU_KA;                       // 乘 1000 [A] / multiply by the factor
            FC_DL_CurrentUnitConvert := TRUE;             // 结果可信 / the result is valid
    ELSE
        fOut := DL_CU_Z;                                  // 未知枚举输出零哨兵 [A] / zero sentinel on an unknown unit
        FC_DL_CurrentUnitConvert := FALSE;                // 未知枚举不可信 / an unknown unit is not valid
    END_CASE
END_IF
END_FUNCTION
