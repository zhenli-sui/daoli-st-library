(* ===========================================================================
   组件名   : FC_DL_HashSdbmArray
   分类     : DL_Algo / 哈希与完整性摘要
   一句话   : sdbm 哈希，逐字节执行 h = b + (h<<6) + (h<<16) − h
   复杂度   : 1        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : adwData 待哈希数据 [1..32]；iLen 有效字数（自动钳位 0..32）
   输出契约 : 返回值 = 32 位哈希值；dwBytes 参与哈希的字节数；xValid 输入有效
   算法说明 : 移位量固定为 6 与 16，均小于 32 位宽，不触发未定义移位
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_HashSdbmArray : DWORD
VAR_INPUT
    adwData : ARRAY[1..32] OF DWORD;   // 待哈希数据字 | data words to hash
    iLen : INT := 0;                   // 有效字数 0..32 | valid word count 0..32
END_VAR
VAR_OUTPUT
    dwBytes : DWORD;                   // 参与哈希的字节数 | hashed byte count
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    dwHash : DWORD := 0;               // sdbm 累加值 | sdbm accumulator
    dwByte : DWORD;                    // 当前字节 | current byte
    iN : INT;                          // 钳位后字数 | clamped word count
    i : INT;                           // 字下标 | word index
    b : INT;                           // 字节下标 0..3 | byte index 0..3
END_VAR

// ---- 输出预置 ----
dwBytes := 0;
xValid := FALSE;
FC_DL_HashSdbmArray := 0;

// ---- 长度钳位 ----
iN := iLen;
IF iN < 0 THEN
    iN := 0;
ELSIF iN > 32 THEN
    iN := 32;
END_IF

// ---- 逐字逐字节处理 ----
FOR i := 1 TO iN DO
    FOR b := 0 TO 3 DO
        dwByte := SHR(adwData[i], b * 8) AND 16#000000FF;
        dwHash := dwByte + SHL(dwHash, 6) + SHL(dwHash, 16) - dwHash;
    END_FOR
END_FOR

dwBytes := INT_TO_DWORD(iN) * INT_TO_DWORD(4);
xValid := TRUE;
FC_DL_HashSdbmArray := dwHash;
END_FUNCTION
