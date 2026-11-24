(*
  FC_DL_VoltageUnitConvert —— 电压换算 V/mV/kV
  分类：DL_Base | 复杂度：1 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：把电压统一折算到基准单位 V：V 直通、mV 乘 0.001、kV 乘 1000。
  契约：fIn 输入值 [源单位]，eUnit 源单位枚举；fOut 折算结果 [V]；返回 TRUE 表示 fOut 可信。
  边界：未知枚举 / 非有限输入 → 返回 FALSE，fOut 给 0.0 哨兵；无除法，零全局、零物理地址、零库件依赖。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_VoltUnit（电压单位，归属本文件，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_VoltUnit :
(
    eVolt     := 0,    // 伏特（基准单位） [V] / Volt, the base unit
    eMilliV   := 1,    // 毫伏 [mV] / Millivolt
    eKiloV    := 2     // 千伏 [kV] / Kilovolt
);
END_TYPE

FUNCTION FC_DL_VoltageUnitConvert : BOOL
VAR_INPUT
    fIn   : LREAL := 0.0;              // 输入值 [源单位] / The input value in the source unit
    eUnit : E_DL_VoltUnit;             // 源单位枚举 [—] / The source unit enumeration
END_VAR
VAR_OUTPUT
    fOut : LREAL;                      // 折算结果 [V] / The converted value in the base unit
END_VAR
VAR CONSTANT
    DL_VT_MV  : LREAL := 0.001;        // 1 mV 折 V 的系数 [-] / millivolt to volt
    DL_VT_KV  : LREAL := 1000.0;       // 1 kV 折 V 的系数 [-] / kilovolt to volt
    DL_VT_INF : LREAL := 1.0E30;       // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_VT_Z   : LREAL := 0.0;          // 浮点零常量 [V] / The floating point zero constant
END_VAR

FC_DL_VoltageUnitConvert := FALSE;                        // 返回值预置假 / preset the return false
fOut := DL_VT_Z;                                          // 输出预置零哨兵 [V] / preset the zero sentinel
IF (fIn <> fIn) OR (ABS(fIn) > DL_VT_INF) THEN            // 自反判 NaN 或越限判 Inf / NaN or Inf
    fOut := DL_VT_Z;                                      // 非有限值输出零哨兵 [V] / zero the non finite input
ELSE
    CASE eUnit OF
        E_DL_VoltUnit.eVolt:                              // 基准单位直通 / the base unit passes through
            fOut := fIn;                                  // 直通不换算 [V] / pass through unchanged
            FC_DL_VoltageUnitConvert := TRUE;             // 结果可信 / the result is valid
        E_DL_VoltUnit.eMilliV:                            // 毫伏折伏 / millivolt to volt
            fOut := fIn * DL_VT_MV;                       // 乘 0.001 [V] / multiply by the factor
            FC_DL_VoltageUnitConvert := TRUE;             // 结果可信 / the result is valid
        E_DL_VoltUnit.eKiloV:                             // 千伏折伏 / kilovolt to volt
            fOut := fIn * DL_VT_KV;                       // 乘 1000 [V] / multiply by the factor
            FC_DL_VoltageUnitConvert := TRUE;             // 结果可信 / the result is valid
    ELSE
        fOut := DL_VT_Z;                                  // 未知枚举输出零哨兵 [V] / zero sentinel on an unknown unit
        FC_DL_VoltageUnitConvert := FALSE;                // 未知枚举不可信 / an unknown unit is not valid
    END_CASE
END_IF
END_FUNCTION
