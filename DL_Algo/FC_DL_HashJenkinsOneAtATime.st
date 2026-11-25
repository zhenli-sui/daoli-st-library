(* ===========================================================================
   组件名   : FC_DL_HashJenkinsOneAtATime
   分类     : DL_Algo / 哈希与完整性摘要
   一句话   : Jenkins one-at-a-time 哈希，逐字节累加与移位混合，末尾再做终混
   复杂度   : 1        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : adwData 待哈希数据 [1..32]；iLen 有效字数（自动钳位 0..32）
   输出契约 : 返回值 = 32 位哈希值；dwBytes 参与哈希的字节数；xValid 输入有效
   算法说明 : 逐字节 h += b；h += h<<10；h ^= h>>6。终混 h += h<<3；h ^= h>>11；h += h<<15
              全部移位量固定且小于 32 位宽
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_HashJenkinsOneAtATime : DWORD
VAR_INPUT
    adwData : ARRAY[1..32] OF DWORD;   // 待哈希数据字 | data words to hash
    iLen : INT := 0;                   // 有效字数 0..32 | valid word count 0..32
END_VAR
VAR_OUTPUT
    dwBytes : DWORD;                   // 参与哈希的字节数 | hashed byte count
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    dwHash : DWORD := 0;               // 哈希累加值 | hash accumulator
    dwByte : DWORD;                    // 当前字节 | current byte
    iN : INT;                          // 钳位后字数 | clamped word count
    i : INT;                           // 字下标 | word index
    b : INT;                           // 字节下标 0..3 | byte index 0..3
END_VAR

// ---- 输出预置 ----
dwBytes := 0;
xValid := FALSE;
FC_DL_HashJenkinsOneAtATime := 0;

// ---- 长度钳位 ----
iN := iLen;
IF iN < 0 THEN
    iN := 0;
ELSIF iN > 32 THEN
    iN := 32;
END_IF

// ---- 正文混合 ----
FOR i := 1 TO iN DO
    FOR b := 0 TO 3 DO
        dwByte := SHR(adwData[i], b * 8) AND 16#000000FF;
        dwHash := dwHash + dwByte;
        dwHash := dwHash + SHL(dwHash, 10);        // 左移 10 位，小于位宽
        dwHash := dwHash XOR SHR(dwHash, 6);       // 右移 6 位，小于位宽
    END_FOR
END_FOR

// ---- 终混：用于把末字节的影响扩散到全字 ----
dwHash := dwHash + SHL(dwHash, 3);
dwHash := dwHash XOR SHR(dwHash, 11);
dwHash := dwHash + SHL(dwHash, 15);

dwBytes := INT_TO_DWORD(iN) * INT_TO_DWORD(4);
xValid := TRUE;
FC_DL_HashJenkinsOneAtATime := dwHash;
END_FUNCTION
