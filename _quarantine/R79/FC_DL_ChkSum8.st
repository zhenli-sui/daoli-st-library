(*==============================================================================
 * 组件名称 : FC_DL_ChkSum8 ｜ 子库 : DL_Algo ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 字节和校验（Sum-8 / LRC 的加和型）。全部字节求和后取模 256，返回单字节。
 *            仪表与老式 PLC 的 ASCII 协议最常用的帧尾校验之一。
 * 契约     : 返回 sum MOD 256；nLen 越界钳到 0~16；nLen = 0 返回 0。
 *            数组定长 ARRAY[1..16] OF BYTE（R17）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: BYTE_TO_UDINT / UDINT_TO_BYTE
 * 错误码   : R297 零码位范式：eErr 恒 0，本件结构性不置 bError
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 累加在 UDINT 域（16×255 远小于 2^32）、
 *            取模后再收窄到 BYTE，收窄前值必 < 256 ｜ R5 双语注释 R6 N/A（无状态机）
 *            R7 N/A（无定时器/沿实例）R10 标准转换 R11 全声明行分号
 *            R15 标识符零保留字冲突 R17 定长数组 R18 N/A（无 bReset）
 * 遗留假设 : 取模口径为 256（2 的幂），与 255 口径的 Fletcher 不同，对接协议前须核对。
 * 修订历史 : 2026-11-24 R79-A 首版（校验和族 4/8）
 *============================================================================*)
FUNCTION FC_DL_ChkSum8 : BYTE
VAR_INPUT
    aData   : ARRAY[1..16] OF BYTE;     // 待校验字节块，1..16 定长 [字节] / byte block of fixed length [byte]
    nLen    : INT;                      // 有效字节数 0~16，越界钳位 [字节] / effective length from zero to sixteen, clamped [byte]
END_VAR
VAR_OUTPUT
    eErr    : UDINT;                    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError  : BOOL;                     // 故障标志，本件结构性不置位 / fault flag, never raised by this component
    bValid  : BOOL;                     // 结果可用标志，空块亦可用 / TRUE even for an empty block
END_VAR
VAR CONSTANT
    DL_LEN_MAX : INT := 16;             // 字节块定长上限 [字节] / fixed block capacity [byte]
    DL_LEN_MIN : INT := 0;              // 长度下界，0 合法 [字节] / lower length bound, zero is legal [byte]
    DL_ONE     : INT := 1;              // 数组首下标 [字节] / first array index [byte]
    DL_MOD256  : UDINT := 256;          // 取模基数 [无量纲] / the modulus
    DL_ZERO_U  : UDINT := 0;            // 无符号零哨兵 / unsigned zero sentinel
END_VAR
VAR
    nSum    : UDINT;                    // 宽域累加和，收窄前必 < 256 / wide accumulator, below 256 before narrowing
    nUse    : INT;                      // 钳位后的有效长度 [字节] / effective length after clamping [byte]
    i       : INT;                      // 遍历游标 [字节] / loop cursor [byte]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_ChkSum8 := 16#00;             // 缺省 0 / default zero
eErr   := 0;                        // 零码位范式 / zero-code rule
bError := FALSE;                    // 本件不产生故障级 / this component raises no fault
bValid := TRUE;                     // 空块亦有定义 / an empty block is well defined
nSum   := DL_ZERO_U;                // 累加器清零 / clear the accumulator

// 段 2｜长度钳位：越界静默整形 / segment 2, clamp the length
nUse := nLen;
IF nUse < DL_LEN_MIN THEN
    nUse := DL_LEN_MIN;             // 下越界钳到 0 / clamp to zero
ELSIF nUse > DL_LEN_MAX THEN
    nUse := DL_LEN_MAX;             // 上越界钳到定长 / clamp to the fixed capacity
END_IF

// 段 3｜逐字节累加：16 个字节最大 4080，远小于 UDINT 上界 / segment 3, byte wise accumulation
FOR i := DL_ONE TO nUse DO
    nSum := nSum + BYTE_TO_UDINT(aData[i]);     // 宽域累加 / widen and accumulate
END_FOR

// 段 4｜出口：先取模再收窄，收窄时值必 < 256 / segment 4, take the modulus before narrowing
FC_DL_ChkSum8 := UDINT_TO_BYTE(nSum MOD DL_MOD256);
END_FUNCTION
