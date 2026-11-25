//==============================================================================
// 函数：FC_DL_TorqueUnitConvert ｜ 中文名称：转矩单位换算（枚举选路 + 域闸）
// 所属子库：DL_MathData ｜ 版本：v1.0.0 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop / Machine Expert（纯标准库）
// 功能描述：转矩单位双向换算原子：N·m ↔ kgf·m ↔ lb·ft。换算因子取国际
//           公开口径：1 kgf·m = 9.80665 N·m；1 lb·ft = 1.35582 N·m。
//           允许带符号输入（正/负转矩均合法），换算为纯线性乘法。
// 开源溯源 (Origin)：候选队列 MS_TO_KMH（oscatBasic，MIT 许可，
//           https://github.com/tkucic/brOscatLib/blob/main/oscatBasic/MS_TO_KMH.st）
//           ——单位换算族行为定义参考；原名 MS_TO_KMH → 道莅
//           FC_DL_TorqueUnitConvert，clean-room 独立重写（枚举选路 + 域闸
//           增强为道莅防御规范增量，零源码行复制）
// 公开接口清单：输入 eMode / fValue；输出 fResult / bValid
// 错误码表：纯函数无状态机码轨；无效输入经 bValid = FALSE 表达（哨兵返回
//           0.0），本件不占用 16#0001 段码位（邻件免让位）
// 状态机：E_DL_TorqueUnit（本文件唯一定义，全库唯一属主）：
//           eNmToKgm = 0 / eKgmToNm = 1 / eNmToLbFt = 2 / eLbFtToNm = 3；
//           枚举非法值走 CASE ELSE 兜底
// 边界行为：① 任一输入非有限 → 哨兵 0.0 返回；
//           ② 幅值越 LREAL 可表域 → 哨兵 0.0 返回；
//           ③ 枚举非法值 → CASE ELSE 哨兵返回；
//           ④ 纯线性乘法无除法（乘法因子均为常量非零）。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 3 · 序 11）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_TorqueUnit（归属本函数，同文件发布，全库唯一属主）
 * 含义: 换算方向选择，成员与 CASE 标签双向完备。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_TorqueUnit :
(
    eNmToKgm  := 0,   // 牛米 → 千克力米 / N·m to kgf·m
    eKgmToNm  := 1,   // 千克力米 → 牛米 / kgf·m to N·m
    eNmToLbFt := 2,   // 牛米 → 磅英尺 / N·m to lb·ft
    eLbFtToNm := 3    // 磅英尺 → 牛米 / lb·ft to N·m
);
END_TYPE

(*------------------------------------------------------------------------------
 * 调用示例：fT := FC_DL_TorqueUnitConvert(
 *             eMode := E_DL_TorqueUnit.eNmToKgm, fValue := 25.0,
 *             bValid => bOk);
 * 注意：仅当 bValid = TRUE 时结果可进入判据；带符号转矩均合法。
 *-----------------------------------------------------------------------------*)
FUNCTION FC_DL_TorqueUnitConvert : LREAL
VAR_INPUT
    eMode    : E_DL_TorqueUnit;        // 换算方向枚举 [—] / Conversion direction enum
    fValue   : LREAL;                  // 输入转矩值 [源单位]，带符号合法 / Torque value [source unit], signed allowed
END_VAR
VAR_OUTPUT
    bValid   : BOOL;                   // 结果有效标志，FALSE 时返回哨兵 0.0 / Result validity flag
END_VAR
VAR CONSTANT
    DL_TQ_KGM  : LREAL := 9.80665;     // 千克力米→牛米因子 [牛米每千克力米] / kgf·m to N·m factor
    DL_TQ_LBFT : LREAL := 1.35582;     // 磅英尺→牛米因子 [牛米每磅英尺] / lb·ft to N·m factor
    DL_TQ_INF  : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_TQ_ZERO : LREAL := 0.0;         // 无效哨兵返回值 / Sentinel return for invalid
END_VAR

// ---- 段 1｜出口默认值（纯函数无实例，无定时器/沿刷新义务）----
bValid := FALSE;                      // 缺省无效 / Invalid by default

// ---- 段 2｜输入防御：非有限值（NaN 自反判 + Inf 幅值判，R79）----
IF (fValue <> fValue) OR (ABS(fValue) > DL_TQ_INF) THEN
    FC_DL_TorqueUnitConvert := DL_TQ_ZERO; // 无效输入：哨兵零返回 / Invalid input, sentinel zero return
    RETURN;                            // 结构早退 / early exit
END_IF

// ---- 段 3｜换算主体（CASE 带 ELSE；纯线性乘法，因子常量非零）----
CASE eMode OF
    E_DL_TorqueUnit.eNmToKgm:          // 牛米 → 千克力米（除以因子，幅值只减不溢）
        FC_DL_TorqueUnitConvert := fValue / DL_TQ_KGM; // 千克力米 [kgf·m] / kgf·m result

    E_DL_TorqueUnit.eKgmToNm:          // 千克力米 → 牛米（乘因子，幅值放大先闸）
        IF ABS(fValue) > (DL_TQ_INF / DL_TQ_KGM) THEN
            FC_DL_TorqueUnitConvert := DL_TQ_ZERO; // 乘积越表域哨兵返回（预检防 Inf 污染）/ Product would overflow, sentinel return
            RETURN;                    // 结构早退 / early exit
        END_IF
        FC_DL_TorqueUnitConvert := fValue * DL_TQ_KGM; // 牛米 [N·m] / N·m result

    E_DL_TorqueUnit.eNmToLbFt:         // 牛米 → 磅英尺（除以因子，幅值只减不溢）
        FC_DL_TorqueUnitConvert := fValue / DL_TQ_LBFT; // 磅英尺 [lb·ft] / lb·ft result

    E_DL_TorqueUnit.eLbFtToNm:         // 磅英尺 → 牛米（乘因子，幅值放大先闸）
        IF ABS(fValue) > (DL_TQ_INF / DL_TQ_LBFT) THEN
            FC_DL_TorqueUnitConvert := DL_TQ_ZERO; // 乘积越表域哨兵返回（预检防 Inf 污染）/ Product would overflow, sentinel return
            RETURN;                    // 结构早退 / early exit
        END_IF
        FC_DL_TorqueUnitConvert := fValue * DL_TQ_LBFT; // 牛米 [N·m] / N·m result

    ELSE                               // 枚举非法值兜底（R21：CASE 必带 ELSE）
        FC_DL_TorqueUnitConvert := DL_TQ_ZERO; // 非法枚举：哨兵零返回 / Illegal enum, sentinel zero return
        RETURN;                        // 结构早退 / early exit
END_CASE

bValid := TRUE;                       // 全部防御通过：结果有效 / Result valid
END_FUNCTION
