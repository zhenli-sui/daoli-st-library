//==============================================================================
// 函数：FC_DL_PressureAltitudeCalc ｜ 中文名称：ISA 标准大气气压↔海拔双向换算
// 所属子库：DL_MathData ｜ 版本：v1.0.1 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop / Machine Expert（纯标准库）
// 功能描述：ISA 对流层（0~11 km）标准大气双向换算。正解（海拔→气压）：
//           p = p0·(1 − L·h/T0)^(g/(R·L))；反解（气压→海拔）：
//           h = (T0/L)·(1 − (p/p0)^(R·L/g))。常量取 ISA 公开口径：
//           p0 = 101325 Pa、T0 = 288.15 K、L = 0.0065 K/m、
//           g = 9.80665 m/s2、R = 287.05287 J/(kg·K)。
// 开源溯源 (Origin)：原创实现（t1-2-oscat-building 建筑环境语义借用，ISA
//           公开公式，零外部源码行，clean-room 独立编写）
// 公开接口清单：输入 eMode / fValue；输出 fResult / bValid
// 错误码表：纯函数无状态机码轨；无效输入经 bValid = FALSE 表达（哨兵返回
//           0.0），本件不占用 16#0001 段码位（邻件免让位）
// 状态机：E_DL_PressAltMode（本文件唯一定义，全库唯一属主）：
//           eAltToPress = 0 / ePressToAlt = 1；枚举非法值走 CASE ELSE 兜底
// 边界行为：① 海拔域 [-500, 11000] m（ISA 对流层有效域，域外不外推）；
//           ② 气压域 [22632, 107477.5] Pa（对流层两端标准值，域外不外推；
//             −500 m 端值 R73 按公式订正）；
//           ③ L 恒非零为 ISA 常量，仍按纪律做非零断言常量（编译期保护）；
//           ④ 非有限输入（NaN 自反判 + 幅值判）→ 哨兵 0.0 返回；
//           ⑤ 枚举非法值 → CASE ELSE 哨兵返回。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 2 · 序 8）
//           v1.0.1 2026-11-23 R73 返修：DL_PA_PMAX 按 ISA 标准大气公式订正
//           为 −500 m 对应值 107477.5 Pa（原 108900.0 与公式不符），边界
//           行为②同步订正。
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_PressAltMode（归属本函数，同文件发布，全库唯一属主）
 * 含义: 换算方向选择，成员与 CASE 标签双向完备。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_PressAltMode :
(
    eAltToPress  := 0,  // 正解：输入海拔 [米]，输出气压 [帕] / Forward: altitude in, pressure out
    ePressToAlt  := 1   // 反解：输入气压 [帕]，输出海拔 [米] / Inverse: pressure in, altitude out
);
END_TYPE

(*------------------------------------------------------------------------------
 * 调用示例：fP := FC_DL_PressureAltitudeCalc(
 *             eMode := E_DL_PressAltMode.eAltToPress, fValue := 1500.0,
 *             bValid => bOk);
 * 注意：仅当 bValid = TRUE 时结果可进入判据；域外输入拒绝不外推。
 *-----------------------------------------------------------------------------*)
FUNCTION FC_DL_PressureAltitudeCalc : LREAL
VAR_INPUT
    eMode    : E_DL_PressAltMode;      // 换算方向枚举 [—] / Conversion direction enum
    fValue   : LREAL;                  // 输入量：海拔 [米] 或气压 [帕]，按 eMode 解释 / Input value, altitude [m] or pressure [Pa] per eMode
END_VAR
VAR_OUTPUT
    bValid   : BOOL;                   // 结果有效标志，FALSE 时返回哨兵 0.0 / Result validity flag
END_VAR
VAR CONSTANT
    DL_PA_P0   : LREAL := 101325.0;    // 海平面标准气压 [帕] / ISA sea-level standard pressure [Pa]
    DL_PA_T0   : LREAL := 288.15;      // 海平面标准温度 [开尔文] / ISA sea-level standard temperature [K]
    DL_PA_L    : LREAL := 0.0065;      // 对流层温度直减率 [开尔文每米] / ISA tropospheric lapse rate [K per m]
    DL_PA_G    : LREAL := 9.80665;     // 标准重力加速度 [米每平方秒] / Standard gravity [m per s2]
    DL_PA_R    : LREAL := 287.05287;   // 干空气气体常数 [焦每千克每开尔文] / Dry-air gas constant [J per kg per K]
    DL_PA_HMIN : LREAL := -500.0;      // 海拔有效下限 [米]（域外不外推）/ Altitude valid floor [m], no extrapolation
    DL_PA_HMAX : LREAL := 11000.0;     // 海拔有效上限 [米]（对流层顶）/ Altitude valid ceiling [m], tropopause
    DL_PA_PMIN : LREAL := 22632.0;     // 气压有效下限 [帕]（11 km 标准值）/ Pressure valid floor [Pa], 11 km ISA value
    DL_PA_PMAX : LREAL := 107477.5;    // 气压有效上限 [帕]（-500 m ISA 标准值，R73 订正：原 108900.0 与公式不符）/ Pressure valid ceiling [Pa], ISA value at -500 m, corrected
    DL_PA_EXP1 : LREAL := 5.2558797;   // 正解指数 g/(R·L) 预算值 [1] / Forward exponent g/(R*L), precomputed
    DL_PA_EXP2 : LREAL := 0.190263236; // 反解指数 R·L/g 预算值 [1] / Inverse exponent R*L/g, precomputed
    DL_PA_INF  : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_PA_ZERO : LREAL := 0.0;         // 无效哨兵返回值 / Sentinel return for invalid
END_VAR

// ---- 段 1｜出口默认值（纯函数无实例，无定时器/沿刷新义务）----
bValid := FALSE;                      // 缺省无效 / Invalid by default

// ---- 段 2｜输入防御：非有限值（NaN 自反判 + Inf 幅值判，R79）----
IF (fValue <> fValue) OR (ABS(fValue) > DL_PA_INF) THEN
    FC_DL_PressureAltitudeCalc := DL_PA_ZERO; // 无效输入：哨兵零返回 / Invalid input, sentinel zero return
    RETURN;                            // 结构早退 / early exit
END_IF

// ---- 段 3｜双向换算主体（CASE 带 ELSE；域闸拒绝不外推）----
CASE eMode OF
    E_DL_PressAltMode.eAltToPress:     // 正解：海拔 → 气压
        IF (fValue < DL_PA_HMIN) OR (fValue > DL_PA_HMAX) THEN
            FC_DL_PressureAltitudeCalc := DL_PA_ZERO; // 海拔域外拒绝（哨兵零）/ Altitude out of range, refused
            RETURN;                    // 结构早退 / early exit
        END_IF
        FC_DL_PressureAltitudeCalc := DL_PA_P0
            * EXPT((1.0 - DL_PA_L * fValue / DL_PA_T0), DL_PA_EXP1); // 标准大气压 [帕] / ISA standard pressure [Pa]

    E_DL_PressAltMode.ePressToAlt:     // 反解：气压 → 海拔
        IF (fValue < DL_PA_PMIN) OR (fValue > DL_PA_PMAX) THEN
            FC_DL_PressureAltitudeCalc := DL_PA_ZERO; // 气压域外拒绝（哨兵零）/ Pressure out of range, refused
            RETURN;                    // 结构早退 / early exit
        END_IF
        FC_DL_PressureAltitudeCalc := (DL_PA_T0 / DL_PA_L)
            * (1.0 - EXPT((fValue / DL_PA_P0), DL_PA_EXP2)); // 标准海拔 [米] / ISA standard altitude [m]

    ELSE                               // 枚举非法值兜底（R21：CASE 必带 ELSE）
        FC_DL_PressureAltitudeCalc := DL_PA_ZERO; // 非法枚举：哨兵零返回 / Illegal enum, sentinel zero return
        RETURN;                        // 结构早退 / early exit
END_CASE

bValid := TRUE;                       // 全部防御通过：结果有效 / Result valid
END_FUNCTION
