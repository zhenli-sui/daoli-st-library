(*==============================================================================
 * 组件名称 : FC_DL_CalQuarterIndex ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 月份 → 季度序号。整月整除实现：quarter = (month − 1) DIV 3 + 1，
 *            纯整数、无分支表、无浮点。1~3→Q1，4~6→Q2，7~9→Q3，10~12→Q4。
 * 契约     : 返回 1~4；nMonth 不在 1~12 时返回 0、bError := TRUE、bValid := FALSE。
 *            纯函数无状态，同输入同输出，可重入。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 月份域闸先行、除数恒为常量 3
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 修订历史 : 2026-11-24 R79-A 首版（日历算术族 7/9）
 *============================================================================*)
FUNCTION FC_DL_CalQuarterIndex : DINT
VAR_INPUT
    nMonth      : DINT;  // 月份 1~12，越界即故障 [月] / month from one to twelve, out of range is a fault [month]
END_VAR
VAR_OUTPUT
    eErr        : UDINT; // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError      : BOOL;  // 月份越界为真 / TRUE when the month is out of range
    bValid      : BOOL;  // 结果可用标志 / result usable flag
END_VAR
VAR CONSTANT
    DL_MONTH_MIN : DINT := 1;   // 月份下界 [月] / lower month bound [month]
    DL_MONTH_MAX : DINT := 12;  // 月份上界 [月] / upper month bound [month]
    DL_MON_PER_Q : DINT := 3;   // 每季度月数 [月] / months per quarter [month]
    DL_Q_MIN     : DINT := 1;   // 季度下界 [季] / lower quarter bound [quarter]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_CalQuarterIndex := 0;     // 缺省 0 / default zero
eErr   := 0;                    // 零码位范式 / zero-code rule
bError := FALSE;                // 预置无故障 / preset no fault
bValid := FALSE;                // 域闸前不认结果 / unusable until the domain gate passes

// 段 2｜月份域闸：唯一故障出口 / segment 2, the month domain gate is the only fault exit
IF (nMonth < DL_MONTH_MIN) OR (nMonth > DL_MONTH_MAX) THEN
    bError := TRUE;             // 月份越界 / the month is out of range
    RETURN;                     // 返回 0 / return zero
END_IF

// 段 3｜季度换算：先减一归零基再整除，避免 3、6、9、12 月落到下一季 / segment 3, zero based division
FC_DL_CalQuarterIndex := ((nMonth - DL_MONTH_MIN) / DL_MON_PER_Q) + DL_Q_MIN;   // 1~4 / one to four
bValid := TRUE;                                                                 // 月份入域，结果可用 / the month is legal and the result is usable
END_FUNCTION
