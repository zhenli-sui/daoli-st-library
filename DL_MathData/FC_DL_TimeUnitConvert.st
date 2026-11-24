(*==============================================================================
 * 组件名称 : FC_DL_TimeUnitConvert ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-23
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 时间单位 s / min / h 两两互转。源/目标由枚举对单向选择，
 *            单向基准链（先归一到 s）使公式域固定为 3+3 条分支。
 * 契约     : 返回换算结果 [目标单位]；枚举非法（越界值）返回 0.0；
 *            除数为编译期非零常量，无除零风险；纯函数无状态。
 * 依赖     : 无 DL_ 内部依赖（本批自足实现）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 枚举越界拒收返 0 + 常量除数
 *            R5 全变量与枚举项双语同行注释 R6 N/A（无状态机） R7 N/A
 * 修订历史 : 2026-11-23 R78-B1 工程单位换算族模板派生首版
 *============================================================================*)
TYPE E_DL_TimeUnit :
(
    eSec := 0,      // 秒 [s] / Second
    eMin,           // 分 [min] / Minute
    eHour           // 时 [h] / Hour
);
END_TYPE

FUNCTION FC_DL_TimeUnitConvert : REAL
VAR_INPUT
    fValue : REAL;         // 输入数值 [源单位] / Input value in source unit
    eSrc : E_DL_TimeUnit;  // 源单位选择 / Source unit selector
    eDst : E_DL_TimeUnit;  // 目标单位选择 / Destination unit selector
END_VAR
VAR
    fBase : REAL;          // 归一化中间值 [s] / Normalized intermediate in seconds
END_VAR
FC_DL_TimeUnitConvert := 0.0;   // 缺省返回 0 / Default return 0
CASE eSrc OF                    // 段 1：归一到基准 s / Normalize to base seconds
    E_DL_TimeUnit.eSec: fBase := fValue;                // 基准直通 / Base pass-through
    E_DL_TimeUnit.eMin: fBase := fValue * 60.0;         // 1 min = 60 s
    E_DL_TimeUnit.eHour: fBase := fValue * 3600.0;      // 1 h = 3600 s
    ELSE FC_DL_TimeUnitConvert := 0.0; RETURN;          // 源枚举非法返 0 / Invalid source returns 0
END_CASE
CASE eDst OF                    // 段 2：基准到目标 / Base to destination
    E_DL_TimeUnit.eSec: FC_DL_TimeUnitConvert := fBase;             // 基准直通 / Base pass-through
    E_DL_TimeUnit.eMin: FC_DL_TimeUnitConvert := fBase / 60.0;      // s 到 min
    E_DL_TimeUnit.eHour: FC_DL_TimeUnitConvert := fBase / 3600.0;   // s 到 h
    ELSE FC_DL_TimeUnitConvert := 0.0;                  // 目标枚举非法返 0 / Invalid destination returns 0
END_CASE
END_FUNCTION
