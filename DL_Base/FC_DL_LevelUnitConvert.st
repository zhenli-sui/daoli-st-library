(*
  FC_DL_LevelUnitConvert —— 液位换算 m/mm/%，按罐高换算
  分类：DL_Base | 复杂度：1 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：把液位统一折算到基准单位 m：m 直通、mm 乘 0.001、% 按罐高折算（% × 罐高 / 100）。
  契约：fIn 输入值 [源单位]、eUnit 源单位枚举、fTankHeight 罐内有效高度 [m]；fOut 折算结果 [m]；
        返回 TRUE 表示 fOut 可信。% 通道要求 fTankHeight > 0，否则判不可信（不除零）。
  边界：① 除零防护：仅对 100 常量做除法，罐高为 0 时 % 通道直接判不可信；② 未知枚举 / 非有限输入 → FALSE + 0.0；
        ③ 三个浮点入参逐一做非有限闸；零全局、零物理地址、零库件依赖。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_LvlUnit（液位单位，归属本文件，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_LvlUnit :
(
    eMeter    := 0,    // 米（基准单位） [m] / Metre, the base unit
    eMilliMeter := 1,  // 毫米 [mm] / Millimetre
    ePercent  := 2     // 百分比（按罐高折算） [%] / Percent of the tank height
);
END_TYPE

FUNCTION FC_DL_LevelUnitConvert : BOOL
VAR_INPUT
    fIn        : LREAL := 0.0;         // 输入值 [源单位] / The input value in the source unit
    eUnit      : E_DL_LvlUnit;         // 源单位枚举 [—] / The source unit enumeration
    fTankHeight : LREAL := 1.0;        // 罐内有效高度（% 通道必需 > 0） [m] / The effective tank height for percent
END_VAR
VAR_OUTPUT
    fOut : LREAL;                      // 折算结果 [m] / The converted value in the base unit
END_VAR
VAR CONSTANT
    DL_LV_MM   : LREAL := 0.001;       // 1 mm 折 m 的系数 [-] / millimetre to metre
    DL_LV_HUND : LREAL := 100.0;       // 百分比满量程分母 [-] / The percent full scale divisor
    DL_LV_INF  : LREAL := 1.0E30;      // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_LV_EPS  : LREAL := 1.0E-9;      // 罐高判零容差 [-] / The tank height zero tolerance
    DL_LV_Z    : LREAL := 0.0;         // 浮点零常量 [m] / The floating point zero constant
END_VAR

FC_DL_LevelUnitConvert := FALSE;                          // 返回值预置假 / preset the return false
fOut := DL_LV_Z;                                          // 输出预置零哨兵 [m] / preset the zero sentinel
IF (fIn <> fIn) OR (ABS(fIn) > DL_LV_INF) THEN            // 输入自反判 NaN 或越限判 Inf / the input gate
    fOut := DL_LV_Z;                                      // 非有限值输出零哨兵 [m] / zero the non finite input
ELSIF (fTankHeight <> fTankHeight) OR (ABS(fTankHeight) > DL_LV_INF) THEN // 罐高非有限闸 / the tank height gate
    fOut := DL_LV_Z;                                      // 罐高非法输出零哨兵 [m] / zero sentinel on an invalid height
ELSE
    CASE eUnit OF
        E_DL_LvlUnit.eMeter:                              // 基准单位直通 / the base unit passes through
            fOut := fIn;                                  // 直通不换算 [m] / pass through unchanged
            FC_DL_LevelUnitConvert := TRUE;               // 结果可信 / the result is valid
        E_DL_LvlUnit.eMilliMeter:                         // 毫米折米 / millimetre to metre
            fOut := fIn * DL_LV_MM;                       // 乘 0.001 [m] / multiply by the factor
            FC_DL_LevelUnitConvert := TRUE;               // 结果可信 / the result is valid
        E_DL_LvlUnit.ePercent:                            // 百分比按罐高折算 / percent of the tank height
            IF (fTankHeight > DL_LV_EPS) THEN             // 罐高为正才可折算（除零防护） / a positive height is required
                fOut := (fIn / DL_LV_HUND) * fTankHeight; // 先除常量 100 再乘罐高 [m] / divide then multiply
                FC_DL_LevelUnitConvert := TRUE;           // 结果可信 / the result is valid
            ELSE
                fOut := DL_LV_Z;                          // 罐高为零输出零哨兵 [m] / zero sentinel on a zero height
                FC_DL_LevelUnitConvert := FALSE;          // 不可信 / not valid
            END_IF
    ELSE
        fOut := DL_LV_Z;                                  // 未知枚举输出零哨兵 [m] / zero sentinel on an unknown unit
        FC_DL_LevelUnitConvert := FALSE;                  // 未知枚举不可信 / an unknown unit is not valid
    END_CASE
END_IF
END_FUNCTION
