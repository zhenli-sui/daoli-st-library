(* ===========================================================================
   组件名   : FB_DL_HashBucketIndex
   分类     : DL_Algo / 哈希桶索引映射
   一句话   : 把 32 位哈希映射到桶号，支持掩码模式并要求桶数为 2 的幂，桶数为 0 时拒绝
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : dwHash 32 位哈希值；iBucketCount 桶数 1..32767；xUseMask TRUE=掩码模式
   输出契约 : iBucket 桶号 0..iBucketCount−1；dwMask 生效掩码（掩码模式）
              xMaskMode 实际使用掩码；xValid 输入有效
              iErrorCode 0=正常 1=桶数非正 2=掩码模式下桶数非 2 的幂
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION_BLOCK FB_DL_HashBucketIndex
VAR_INPUT
    dwHash : DWORD := 0;               // 32 位哈希值 | 32 bit hash value
    iBucketCount : INT := 16;          // 桶数 1..32767 | bucket count 1..32767
    xUseMask : BOOL := TRUE;           // TRUE=掩码模式 | TRUE=mask mode
END_VAR
VAR_OUTPUT
    iBucket : INT;                     // 映射得到的桶号 | mapped bucket index
    dwMask : DWORD;                    // 生效掩码 | effective mask
    xMaskMode : BOOL;                  // 是否实际使用掩码 | mask actually used
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
    iErrorCode : INT;                  // 故障码 0=无故障 | error code
END_VAR
VAR
    dwCount : DWORD;                   // 桶数无符号形式 | bucket count as dword
    dwM : DWORD;                       // 候选掩码 | candidate mask
    dwBucket : DWORD;                  // 桶号工作值 | bucket working value
    _xPow2 : BOOL;                     // 桶数是否 2 的幂 | bucket count is power of two
END_VAR

// ---- 输出预置 ----
iBucket := 0;
dwMask := 0;
xMaskMode := FALSE;
xValid := FALSE;
iErrorCode := 0;

// ---- 桶数为 0 保护：直接拒绝，禁止进入任何除法/取模 ----
IF iBucketCount <= 0 THEN
    iErrorCode := 1;
ELSE
    dwCount := INT_TO_DWORD(iBucketCount);

    // ---- 掩码模式：桶数必须是 2 的幂，否则掩码无意义 ----
    IF xUseMask THEN
        dwM := dwCount - 1;
        _xPow2 := ((dwCount AND dwM) = 0) AND (dwCount > 1);
        IF _xPow2 THEN
            dwMask := dwM;
            xMaskMode := TRUE;
            dwBucket := dwHash AND dwM;            // 掩码取低位
            xValid := TRUE;
        ELSE
            iErrorCode := 2;                       // 非 2 的幂，掩码模式不可用
        END_IF
    ELSE
        // ---- 取模模式：桶数已保证非零，UDINT 取模避免有符号溢出 ----
        dwBucket := UDINT_TO_DWORD(DWORD_TO_UDINT(dwHash) MOD DWORD_TO_UDINT(dwCount));
        xValid := TRUE;
    END_IF

    IF xValid THEN
        // ---- 结果钳位：防御性保证桶号落在 [0, 桶数−1] ----
        IF dwBucket >= dwCount THEN
            dwBucket := dwCount - 1;
        END_IF
        iBucket := DWORD_TO_INT(dwBucket);         // 已小于 32767，转换安全
    END_IF
END_IF
END_FUNCTION_BLOCK
