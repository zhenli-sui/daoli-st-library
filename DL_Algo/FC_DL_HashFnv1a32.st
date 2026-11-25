(* ===========================================================================
   组件名   : FC_DL_HashFnv1a32
   分类     : DL_Algo / 哈希与完整性摘要
   一句话   : FNV-1a 32 位哈希，输入 DWORD 数组与有效长度，逐字节异或后乘质数
   复杂度   : 1        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : adwData 待哈希数据 [1..32]；iLen 有效字数（自动钳位 0..32）
   输出契约 : 返回值 = 32 位哈希值；dwBytes 参与哈希的字节数；xValid 输入有效
   算法说明 : h = 2166136261；对每个字节 b：h = (h XOR b) * 16777619；
              质数取 16#01000193，DWORD 乘法按 32 位回绕为算法预期行为
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_HashFnv1a32 : DWORD
VAR_INPUT
    adwData : ARRAY[1..32] OF DWORD;   // 待哈希数据字 | data words to hash
    iLen : INT := 0;                   // 有效字数 0..32 | valid word count 0..32
END_VAR
VAR_OUTPUT
    dwBytes : DWORD;                   // 参与哈希的字节数 | hashed byte count
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    dwHash : DWORD := 16#811C9DC5;     // FNV-1a 偏移基 | fnv offset basis
    dwByte : DWORD;                    // 当前字节 | current byte
    iN : INT;                          // 钳位后字数 | clamped word count
    i : INT;                           // 字下标 | word index
    b : INT;                           // 字节下标 0..3 | byte index 0..3
END_VAR

// ---- 输出预置：默认返回偏移基，杜绝调用方读到未初始化值 ----
dwBytes := 0;
xValid := FALSE;
FC_DL_HashFnv1a32 := 16#811C9DC5;

// ---- 长度钳位：越界长度不得直接用于循环上限 ----
iN := iLen;
IF iN < 0 THEN
    iN := 0;
ELSIF iN > 32 THEN
    iN := 32;
END_IF

// ---- 逐字逐字节处理 ----
FOR i := 1 TO iN DO
    FOR b := 0 TO 3 DO
        // 移位量 b*8 落在 0/8/16/24，始终小于 32，无需额外归一
        dwByte := SHR(adwData[i], b * 8) AND 16#000000FF;
        dwHash := (dwHash XOR dwByte) * 16#01000193;
    END_FOR
END_FOR

dwBytes := INT_TO_DWORD(iN) * INT_TO_DWORD(4);
xValid := TRUE;
FC_DL_HashFnv1a32 := dwHash;
END_FUNCTION
