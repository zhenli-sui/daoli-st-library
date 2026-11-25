// FC_DL_SpeedUnitConvert v1.0.0
// 开源溯源：brOscatLib / URL https://github.com/iec-oscat-mirror / 许可证 MIT / 借鉴 MS_TO_KMH 速度互转语义，clean-room 重写
(*
  道莅工业代码库 | DL_MathData | FC_DL_SpeedUnitConvert
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 速度单位双向互转 m/s ↔ km/h（eMode 选择方向），域闸防非有限与超量程
  邻件关系: 单位换算族 Temp/Press/Flow/Angle/Torque UnitConvert 的速度类补口；
            差异点：本件为线性比例换算（×3.6），温度族为仿射换算（含偏置），
            两者口径独立不共享码位（本件 16#0002_1901）
*)
TYPE E_DL_SpeedConvMode :
(
    eMsToKmh   := 0,   // m/s → km/h（乘 3.6）/ Meter per second to kilometer per hour
    eKmhToMs   := 1    // km/h → m/s（除以 3.6）/ Kilometer per hour to meter per second
);
END_TYPE

FUNCTION FC_DL_SpeedUnitConvert : REAL
VAR_INPUT
    fValue : REAL := 0.0;                        // 输入速度值 [m/s 或 km/h，随 eMode] / Input speed value
    eMode  : E_DL_SpeedConvMode := E_DL_SpeedConvMode.eMsToKmh;   // 换算方向选择 / Conversion direction selector
END_VAR
VAR_OUTPUT
    bValid   : BOOL;                             // 结果有效回执 [-] / Result validity receipt
    uErrorId : UDINT;                            // 事件码，0 = 无事件；16#0002_1901 = 输入非有限 / Event code
END_VAR
VAR CONSTANT
    DL_SPD_KMH_PER_MS : REAL := 3.6;             // 换算系数 1 m/s = 3.6 km/h [km/h per m/s] / Conversion factor
    DL_SPD_ABSMAX     : REAL := 1.0E12;          // 超量程闸（|v| 上限，防系数放大后溢出）[m/s|km/h] / Over-range gate
END_VAR

// —— 段 0：全路径缺省 —— //
bValid   := FALSE;                               // 有效回执预清 / Validity preset
uErrorId := 16#0000;                             // 事件码预清 / Event code preset
FC_DL_SpeedUnitConvert := 0.0;                   // 返回值缺省零 / Return default zero

// —— 段 1：非有限与超量程闸 —— //
IF (fValue <> fValue) OR (ABS(fValue) >= DL_SPD_ABSMAX) THEN   // NaN 自反 + 近 Inf 幅值闸 / NaN and magnitude gate
    uErrorId := 16#0002_1901;                    // 信息级：输入非有限或超量程（不置 bError） / Info level: invalid input
    RETURN;                                      // 返回零 / Return zero
END_IF

// —— 段 2：双向换算（CASE 全枚举 + ELSE 兜底） —— //
CASE eMode OF
E_DL_SpeedConvMode.eMsToKmh :                    // m/s → km/h / m/s to km/h
    FC_DL_SpeedUnitConvert := fValue * DL_SPD_KMH_PER_MS;    // ×3.6 / Multiply by 3.6
E_DL_SpeedConvMode.eKmhToMs :                    // km/h → m/s / km/h to m/s
    FC_DL_SpeedUnitConvert := fValue / DL_SPD_KMH_PER_MS;    // ÷3.6（常量非零，无除零风险）/ Divide by nonzero constant
ELSE                                             // 非法枚举兜底 / Illegal enum fallback
    uErrorId := 16#0002_1901;                    // 信息级：模式非法，返回零 / Info level: illegal mode
    RETURN;
END_CASE
bValid := TRUE;                                  // 有效回执 / Validity receipt
END_FUNCTION
