(*==============================================================================
 * 组件名称 : FC_DL_ChkParityBlock ｜ 子库 : DL_Algo ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 整块字节的偶校验结论。统计全块为 1 的比特总数，总数为偶数返回 TRUE。
 *            与逐帧奇偶校验位同源：发送端把本件结果放进校验位，接收端对「数据 + 校验位」
 *            复算应得 FALSE（偶数个 1）。用于老式 ASCII 链路、条码枪回读的一致性核验。
 * 契约     : 返回 TRUE 表示 1 的个数为偶数（偶校验成立）；nLen 越界钳到 0~16；
 *            nLen = 0 时 1 的个数为 0（偶数），返回 TRUE。
 *            数组定长 ARRAY[1..16] OF BYTE（R17）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: BYTE_TO_UDINT
 * 错误码   : R297 零码位范式：eErr 恒 0，本件结构性不置 bError
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 位计数用整除取余循环（每字节最多 8 次）、
 *            长度先钳位后进循环 ｜ R5 双语注释 R6 N/A（无状态机）
 *            R7 N/A（无定时器/沿实例）R10 标准转换 R11 全声明行分号
 *            R15 标识符零保留字冲突 R17 定长数组 R18 N/A（无 bReset）
 * 遗留假设 : 「偶校验」定义为整块比特和为偶数；若协议要求「校验位使总数成偶」，
 *            则须在接收侧把校验位一并送入本件，判据取 FALSE。
 * 修订历史 : 2026-11-24 R79-A 首版（校验和族 7/8）
 *============================================================================*)
FUNCTION FC_DL_ChkParityBlock : BOOL
VAR_INPUT
    aData   : ARRAY[1..16] OF BYTE;     // 待校验字节块，1..16 定长 [字节] / byte block of fixed length [byte]
    nLen    : INT;                      // 有效字节数 0~16，越界钳位 [字节] / effective length from zero to sixteen, clamped [byte]
END_VAR
VAR_OUTPUT
    eErr    : UDINT;                    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError  : BOOL;                     // 故障标志，本件结构性不置位 / fault flag, never raised by this component
    bValid  : BOOL;                     // 结果可用标志，空块亦可用 / TRUE even for an empty block
    nBitOnes : UDINT;                   // 整块为 1 的比特总数，供诊断 / total number of one bits, for diagnostics
END_VAR
VAR CONSTANT
    DL_LEN_MAX : INT := 16;             // 字节块定长上限 [字节] / fixed block capacity [byte]
    DL_LEN_MIN : INT := 0;              // 长度下界，0 合法 [字节] / lower length bound, zero is legal [byte]
    DL_ONE     : INT := 1;              // 数组首下标 [字节] / first array index [byte]
    DL_TWO     : UDINT := 2;            // 位提取的进制基数 [无量纲] / radix of the bit extraction
    DL_EVEN    : UDINT := 2;            // 奇偶判断的模数 [无量纲] / modulus of the parity test
    DL_ZERO_U  : UDINT := 0;            // 无符号零哨兵 / unsigned zero sentinel
END_VAR
VAR
    nByte   : UDINT;                    // 当前字节的位提取工作副本 / working copy of the current byte
    nOnes   : UDINT;                    // 累计的 1 比特数 / accumulated one bits
    nUse    : INT;                      // 钳位后的有效长度 [字节] / effective length after clamping [byte]
    i       : INT;                      // 遍历游标 [字节] / loop cursor [byte]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_ChkParityBlock := TRUE;       // 缺省偶校验成立（零个 1）/ default even parity, zero one bits
eErr     := 0;                      // 零码位范式 / zero-code rule
bError   := FALSE;                  // 本件不产生故障级 / this component raises no fault
bValid   := TRUE;                   // 空块亦有定义 / an empty block is well defined
nOnes    := DL_ZERO_U;              // 比特计数清零 / clear the bit counter
nBitOnes := DL_ZERO_U;              // 诊断出口清零 / clear the diagnostic output

// 段 2｜长度钳位：越界静默整形 / segment 2, clamp the length
nUse := nLen;
IF nUse < DL_LEN_MIN THEN
    nUse := DL_LEN_MIN;             // 下越界钳到 0 / clamp to zero
ELSIF nUse > DL_LEN_MAX THEN
    nUse := DL_LEN_MAX;             // 上越界钳到定长 / clamp to the fixed capacity
END_IF

// 段 3｜逐字节取位计数：右移一位即整除 2，最低位即取余 / segment 3, count the one bits byte by byte
FOR i := DL_ONE TO nUse DO
    nByte := BYTE_TO_UDINT(aData[i]);   // 取当前字节 / take the current byte
    WHILE nByte > DL_ZERO_U DO
        nOnes := nOnes + (nByte MOD DL_TWO);    // 最低位为 1 则加一 / add one when the low bit is set
        nByte := nByte / DL_TWO;                // 右移一位 / shift one bit right
    END_WHILE
END_FOR

// 段 4｜出口：总数为偶数即偶校验成立 / segment 4, even parity holds when the total is even
nBitOnes := nOnes;                              // 诊断出口 / the diagnostic output
FC_DL_ChkParityBlock := ((nOnes MOD DL_EVEN) = DL_ZERO_U);
END_FUNCTION
