(*==============================================================================
 * 组件名称 : FC_DL_ChkXor8 ｜ 子库 : DL_Algo ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 字节块异或校验（BCC / XOR-8）。全字节逐位异或，返回单字节结果。
 *            最简单的一类校验：对单比特翻转敏感，对字节顺序不敏感，
 *            常用于仪表 ASCII 协议的帧尾校验（模数恒为 256，天然无溢出）。
 * 契约     : 返回全字节异或值；nLen 越界钳到 0~16；nLen = 0 返回 0（空块异或为 0）。
 *            数组定长 ARRAY[1..16] OF BYTE（R17）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，本件结构性不置 bError
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 BYTE 异或天然模 256，无溢出面、
 *            长度先钳位后进循环 ｜ R5 双语注释 R6 N/A（无状态机）
 *            R7 N/A（无定时器/沿实例）R10 无类型转换 R11 全声明行分号
 *            R15 标识符零保留字冲突 R17 定长数组 R18 N/A（无 bReset）
 * 修订历史 : 2026-11-24 R79-A 首版（校验和族 3/8）
 *============================================================================*)
FUNCTION FC_DL_ChkXor8 : BYTE
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
    DL_BYTE_ZERO : BYTE := 16#00;       // 字节零哨兵，异或单位元 / byte zero, the identity of the exclusive or
END_VAR
VAR
    nAcc    : BYTE;                     // 异或累加器 / exclusive or accumulator
    nUse    : INT;                      // 钳位后的有效长度 [字节] / effective length after clamping [byte]
    i       : INT;                      // 遍历游标 [字节] / loop cursor [byte]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_ChkXor8 := DL_BYTE_ZERO;      // 缺省 0，空块异或即 0 / default zero, the identity of the operation
eErr   := 0;                        // 零码位范式 / zero-code rule
bError := FALSE;                    // 本件不产生故障级 / this component raises no fault
bValid := TRUE;                     // 空块亦有定义 / an empty block is well defined
nAcc   := DL_BYTE_ZERO;             // 累加器取异或单位元 / seed the accumulator with the identity

// 段 2｜长度钳位：越界静默整形 / segment 2, clamp the length
nUse := nLen;
IF nUse < DL_LEN_MIN THEN
    nUse := DL_LEN_MIN;             // 下越界钳到 0 / clamp to zero
ELSIF nUse > DL_LEN_MAX THEN
    nUse := DL_LEN_MAX;             // 上越界钳到定长 / clamp to the fixed capacity
END_IF

// 段 3｜逐字节异或：BYTE 域内运算，天然模 256 / segment 3, byte wise exclusive or
FOR i := DL_ONE TO nUse DO
    nAcc := nAcc XOR aData[i];      // 异或累积 / accumulate by exclusive or
END_FOR

// 段 4｜出口 / segment 4, exit
FC_DL_ChkXor8 := nAcc;              // 单字节结果 / the single byte result
END_FUNCTION
