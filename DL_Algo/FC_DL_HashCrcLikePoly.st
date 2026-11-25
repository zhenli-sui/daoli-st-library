(* ===========================================================================
   组件名   : FC_DL_HashCrcLikePoly
   分类     : DL_Algo / 哈希与完整性摘要
   一句话   : 多项式滚动哈希（不查表，逐位滚动），多项式与初值可配，位宽可配
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : adwData 待哈希数据 [1..32]；iLen 有效字数（自动钳位 0..32）
              dwPoly 生成多项式；dwInit 初值；iWidthBits 位宽 8/16/24/32
   输出契约 : 返回值 = 滚动哈希值（已按位宽掩码）；dwBytes 参与哈希的字节数
              iSteps 执行的移位步数；xValid 输入有效（位宽合法）
   算法说明 : 每字节：crc ^= byte，随后执行 8 次「判最高位 → 左移 1 位并异或多项式」，
              每步后按位宽掩码截断；最高位掩码与截断掩码由位宽 CASE 显式给出，
              彻底避免 SHL(x, 32) 这类越界移位
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_HashCrcLikePoly : DWORD
VAR_INPUT
    adwData : ARRAY[1..32] OF DWORD;   // 待哈希数据字 | data words to hash
    iLen : INT := 0;                   // 有效字数 0..32 | valid word count 0..32
    dwPoly : DWORD := 16#04C11DB7;     // 生成多项式 | generator polynomial
    dwInit : DWORD := 16#FFFFFFFF;     // 初值 | initial value
    iWidthBits : INT := 32;            // 位宽 8/16/24/32 | width in bits
END_VAR
VAR_OUTPUT
    dwBytes : DWORD;                   // 参与哈希的字节数 | hashed byte count
    iSteps : INT;                      // 执行的移位步数 | shift step count
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    dwCrc : DWORD;                     // 滚动寄存器 | rolling register
    dwByte : DWORD;                    // 当前字节 | current byte
    dwTopMask : DWORD;                 // 最高位掩码 | top bit mask
    dwWidthMask : DWORD;               // 位宽截断掩码 | width truncation mask
    iN : INT;                          // 钳位后字数 | clamped word count
    i : INT;                           // 字下标 | word index
    b : INT;                           // 字节下标 0..3 | byte index 0..3
    n : INT;                           // 位步下标 1..8 | bit step index 1..8
    _xWidthOk : BOOL;                  // 位宽合法标志 | width valid flag
END_VAR

// ---- 输出预置 ----
dwBytes := 0;
iSteps := 0;
xValid := FALSE;
FC_DL_HashCrcLikePoly := 0;

// ---- 位宽到掩码映射：用 CASE 显式给出常量，禁用 SHL(x,32) ----
_xWidthOk := TRUE;
dwTopMask := 16#80000000;
dwWidthMask := 16#FFFFFFFF;
CASE iWidthBits OF
    8:
        dwTopMask := 16#00000080;
        dwWidthMask := 16#000000FF;
    16:
        dwTopMask := 16#00008000;
        dwWidthMask := 16#0000FFFF;
    24:
        dwTopMask := 16#00800000;
        dwWidthMask := 16#00FFFFFF;
    32:
        dwTopMask := 16#80000000;
        dwWidthMask := 16#FFFFFFFF;
ELSE
    _xWidthOk := FALSE;                            // 非法位宽兜底
END_CASE
IF NOT _xWidthOk THEN
    RETURN;
END_IF

// ---- 长度钳位 ----
iN := iLen;
IF iN < 0 THEN
    iN := 0;
ELSIF iN > 32 THEN
    iN := 32;
END_IF

dwCrc := dwInit AND dwWidthMask;                   // 初值先按位宽截断

// ---- 逐字节逐位滚动 ----
FOR i := 1 TO iN DO
    FOR b := 0 TO 3 DO
        dwByte := SHR(adwData[i], b * 8) AND 16#000000FF;
        dwCrc := dwCrc XOR dwByte;
        FOR n := 1 TO 8 DO
            IF (dwCrc AND dwTopMask) <> 0 THEN
                dwCrc := SHL(dwCrc, 1) XOR dwPoly; // 移位量恒为 1，安全
            ELSE
                dwCrc := SHL(dwCrc, 1);
            END_IF
            dwCrc := dwCrc AND dwWidthMask;        // 按位宽截断，防高位爬升
            iSteps := iSteps + 1;
        END_FOR
    END_FOR
END_FOR

dwBytes := INT_TO_DWORD(iN) * INT_TO_DWORD(4);
xValid := TRUE;
FC_DL_HashCrcLikePoly := dwCrc;
END_FUNCTION
