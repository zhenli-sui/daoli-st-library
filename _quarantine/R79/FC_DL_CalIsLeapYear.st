(*==============================================================================
 * 组件名称 : FC_DL_CalIsLeapYear ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 公历（格里高利历）闰年判定 —— 能被 4 整除且不能被 100 整除，或能被 400
 *            整除即为闰年。纯整数取余，无浮点、无日历库依赖。
 * 契约     : 返回 TRUE=闰年；nYear < 1583（格里高利历起点）返回 FALSE 且
 *            bValid := FALSE —— 儒略历闰年口径与本件不同，域外一律不认。
 *            纯函数无状态，同输入同输出。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达（本件结构性不置 bError）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 取余无除法歧义、域闸先判年份
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 修订历史 : 2026-11-24 R79-A 首版（日历算术族 1/9）
 *============================================================================*)
FUNCTION FC_DL_CalIsLeapYear : BOOL
VAR_INPUT
    nYear    : DINT;    // 待判定公历年，有效域 1583 及以上 [年] / Gregorian year to test, valid from 1583 [year]
END_VAR
VAR_OUTPUT
    eErr     : UDINT;   // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError   : BOOL;    // 故障标志，本件结构性不置位 / fault flag, never raised by this component
    bValid   : BOOL;    // 年份落在格里高利历域内为真 / TRUE when the year is inside the Gregorian domain
END_VAR
VAR CONSTANT
    DL_GREG_START : DINT := 1583;   // 格里高利历起点年 [年] / first Gregorian year [year]
    DL_STEP4      : DINT := 4;      // 闰年基本步长 [年] / base leap step [year]
    DL_STEP100    : DINT := 100;    // 世纪基数 [年] / century radix [year]
    DL_STEP400    : DINT := 400;    // 四世纪基数 [年] / four century radix [year]
    DL_ZERO       : DINT := 0;      // 整数零哨兵 [无量纲] / integer zero sentinel [dimensionless]
END_VAR
VAR
    nMod4    : DINT;    // 年份除 4 的余数 [无量纲] / remainder of the year divided by four [dimensionless]
    nMod100  : DINT;    // 年份除 100 的余数 [无量纲] / remainder of the year divided by one hundred [dimensionless]
    nMod400  : DINT;    // 年份除 400 的余数 [无量纲] / remainder of the year divided by four hundred [dimensionless]
END_VAR

// 段 1｜出口预置：任何路径下结果确定 / segment 1, preset the exit so that every path is deterministic
FC_DL_CalIsLeapYear := FALSE;   // 缺省非闰年 / default is not a leap year
eErr   := 0;                    // 零码位范式 / zero-code rule
bError := FALSE;                // 本件不产生故障级 / this component raises no fault
bValid := FALSE;                // 域闸通过前不认结果 / the result stays unusable until the domain gate passes

// 段 2｜域闸：1583 之前属儒略历，闰年口径不同，直接拒绝 / segment 2, the domain gate rejects years before 1583
IF nYear < DL_GREG_START THEN
    RETURN;                     // 返回 FALSE 且 bValid 保持 FALSE / return FALSE with bValid still FALSE
END_IF
bValid := TRUE;                 // 年份入域，结果可用 / the year is inside the domain, the result is usable

// 段 3｜闰年判据：先取三个余数，再做布尔合成（避免重复取余） / segment 3, the leap rule on three remainders
nMod4   := nYear MOD DL_STEP4;      // 4 年周期余数 / remainder against four years
nMod100 := nYear MOD DL_STEP100;    // 100 年周期余数 / remainder against one hundred years
nMod400 := nYear MOD DL_STEP400;    // 400 年周期余数 / remainder against four hundred years
IF ((nMod4 = DL_ZERO) AND (nMod100 <> DL_ZERO)) OR (nMod400 = DL_ZERO) THEN
    FC_DL_CalIsLeapYear := TRUE;    // 整除 4 且不整除 100，或整除 400 / divisible by four but not by one hundred, or divisible by four hundred
END_IF
END_FUNCTION
