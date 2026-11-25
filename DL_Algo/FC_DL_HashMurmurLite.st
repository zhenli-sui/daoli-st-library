(* ===========================================================================
   组件名   : FC_DL_HashMurmurLite
   分类     : DL_Algo / 哈希与完整性摘要
   一句话   : Murmur 简化版（不含尾部字节处理），含 32 位循环移位与终混雪崩
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : adwData 待哈希数据 [1..32]；iLen 有效字数（自动钳位 0..32）
              dwSeed 种子值
   输出契约 : 返回值 = 32 位哈希值；dwBytes 参与哈希的字节数；xValid 输入有效
   算法说明 : 循环左移用 SHL(x,n) OR SHR(x,32−n) 拼合实现，n 与 32−n 均小于 32；
              c1=16#CC9E2D51、c2=16#1B873593，终混取 16#85EBCA6B 与 16#C2B2AE35
              简化点：不处理非 4 字节整数倍的尾部，调用方须补齐零字节
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_HashMurmurLite : DWORD
VAR_INPUT
    adwData : ARRAY[1..32] OF DWORD;   // 待哈希数据字 | data words to hash
    iLen : INT := 0;                   // 有效字数 0..32 | valid word count 0..32
    dwSeed : DWORD := 0;               // 哈希种子 | hash seed
END_VAR
VAR_OUTPUT
    dwBytes : DWORD;                   // 参与哈希的字节数 | hashed byte count
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    dwH : DWORD;                       // 哈希累加值 | hash accumulator
    dwK : DWORD;                       // 单字混合值 | per word mix value
    iN : INT;                          // 钳位后字数 | clamped word count
    i : INT;                           // 字下标 | word index
END_VAR

// ---- 输出预置 ----
dwBytes := 0;
xValid := FALSE;
FC_DL_HashMurmurLite := 0;

// ---- 长度钳位 ----
iN := iLen;
IF iN < 0 THEN
    iN := 0;
ELSIF iN > 32 THEN
    iN := 32;
END_IF

dwH := dwSeed;

// ---- 正文：逐字混合 ----
FOR i := 1 TO iN DO
    dwK := adwData[i];
    dwK := dwK * 16#CC9E2D51;                      // 乘 c1
    dwK := SHL(dwK, 15) OR SHR(dwK, 17);           // 循环左移 15 位
    dwK := dwK * 16#1B873593;                      // 乘 c2

    dwH := dwH XOR dwK;
    dwH := SHL(dwH, 13) OR SHR(dwH, 19);           // 循环左移 13 位
    dwH := dwH * 5 + 16#E6546B64;
END_FOR

// ---- 长度混合：把字数折算成字节数并入哈希 ----
dwH := dwH XOR (INT_TO_DWORD(iN) * INT_TO_DWORD(4));

// ---- 终混：保证末位变化可扩散到全字 ----
dwH := dwH XOR SHR(dwH, 16);
dwH := dwH * 16#85EBCA6B;
dwH := dwH XOR SHR(dwH, 13);
dwH := dwH * 16#C2B2AE35;
dwH := dwH XOR SHR(dwH, 16);

dwBytes := INT_TO_DWORD(iN) * INT_TO_DWORD(4);
xValid := TRUE;
FC_DL_HashMurmurLite := dwH;
END_FUNCTION
