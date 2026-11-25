(* ===========================================================================
   组件名   : FC_DL_HashXorFold
   分类     : DL_Algo / 哈希与完整性摘要
   一句话   : 异或折叠哈希：先把每个 DWORD 的四字节折叠成单字节，再与累加值混合
   复杂度   : 1        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : adwData 待哈希数据 [1..32]；iLen 有效字数（自动钳位 0..32）
   输出契约 : 返回值 = 32 位哈希值；dwBytes 参与哈希的字节数；xValid 输入有效
   算法说明 : fold = b0^b1^b2^b3；h = (h ^ fold) * 16#01000193；h = h ^ (h>>13)
              折叠保留了各字节奇偶信息，混合步保证低位扩散
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_HashXorFold : DWORD
VAR_INPUT
    adwData : ARRAY[1..32] OF DWORD;   // 待哈希数据字 | data words to hash
    iLen : INT := 0;                   // 有效字数 0..32 | valid word count 0..32
END_VAR
VAR_OUTPUT
    dwBytes : DWORD;                   // 参与哈希的字节数 | hashed byte count
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    dwHash : DWORD := 16#811C9DC5;     // 哈希累加值 | hash accumulator
    dwFold : DWORD;                    // 单字折叠值 | folded byte of one word
    dwByte : DWORD;                    // 当前字节 | current byte
    iN : INT;                          // 钳位后字数 | clamped word count
    i : INT;                           // 字下标 | word index
    b : INT;                           // 字节下标 0..3 | byte index 0..3
END_VAR

// ---- 输出预置 ----
dwBytes := 0;
xValid := FALSE;
FC_DL_HashXorFold := 16#811C9DC5;

// ---- 长度钳位 ----
iN := iLen;
IF iN < 0 THEN
    iN := 0;
ELSIF iN > 32 THEN
    iN := 32;
END_IF

// ---- 折叠 + 混合 ----
FOR i := 1 TO iN DO
    dwFold := 0;
    FOR b := 0 TO 3 DO
        dwByte := SHR(adwData[i], b * 8) AND 16#000000FF;
        dwFold := dwFold XOR dwByte;               // 四字节异或折叠
    END_FOR
    dwHash := (dwHash XOR dwFold) * 16#01000193;   // 与折叠值混合
    dwHash := dwHash XOR SHR(dwHash, 13);          // 高位回灌低位
END_FOR

dwBytes := INT_TO_DWORD(iN) * INT_TO_DWORD(4);
xValid := TRUE;
FC_DL_HashXorFold := dwHash;
END_FUNCTION
