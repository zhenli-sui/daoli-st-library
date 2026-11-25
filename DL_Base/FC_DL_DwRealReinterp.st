// FC_DL_DwRealReinterp v1.0.0
// 开源溯源：brOscatLib / URL https://github.com/iec-oscat-mirror / 许可证 MIT / 借鉴 DW_TO_REAL+REAL_TO_DW 位重解释语义（双向往返单件），clean-room 重写
(*
  道莅工业代码库 | DL_Base | FC_DL_DwRealReinterp
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: DWORD↔REAL IEEE-754 单精度位重解释，双向单件（eMode 选择方向）。
        不用 UNION/POINTER/AT，纯标准移位/掩码手工打包解包（R3 红线口径）
  邻件关系: 全库无位重解释属主（查重留痕 §3 驳回 9 条注）；与 SwapBytes16/32
            字节序族互不重叠（字节序 vs 位级重解释）
  精度边界: 打包方向次正规数钳位为零（bClamped 置位）；Inf/NaN 拒收置码；
            解包方向 e=0 次正规/零按 0 返回，e=255 Inf/NaN 拒收置码
*)
TYPE E_DL_DwRealDir :
(
    eRealToDw := 0,   // REAL → DWORD 打包 / Pack REAL to DWORD bits
    eDwToReal := 1    // DWORD → REAL 解包 / Unpack DWORD bits to REAL
);
END_TYPE

FUNCTION FC_DL_DwRealReinterp : REAL
VAR_INPUT
    fValue : REAL  := 0.0;                        // REAL 方向输入值（eMode=打包时用）/ REAL input for pack direction
    dwBits : DWORD := 16#0000_0000;               // DWORD 方向输入位型（eMode=解包时用）/ DWORD input for unpack direction
    eMode  : E_DL_DwRealDir := E_DL_DwRealDir.eRealToDw;   // 方向选择 / Direction selector
END_VAR
VAR_OUTPUT
    dwOut     : DWORD;                            // 打包输出位型 / Packed DWORD output
    fOut      : REAL;                             // 解包输出值 / Unpacked REAL output
    bValid    : BOOL;                             // 结果有效回执 [-] / Result validity receipt
    bClamped  : BOOL;                             // 次正规数钳位标志 [-] / Subnormal clamped flag
    uErrorId  : UDINT;                            // 事件码，0 = 无事件；16#0002_1B01 = 非有限拒收 / Event code
END_VAR
VAR CONSTANT
    DL_DWR_MANT_SHL : DWORD := 16#007F_FFFF;      // 尾数掩码（低 23 位）/ Mantissa mask, low 23 bits
    DL_DWR_EXP_SHL  : DWORD := 16#7F80_0000;      // 指数掩码（位 30..23）/ Exponent mask, bits 30..23
    DL_DWR_SIGN_SHL : DWORD := 16#8000_0000;      // 符号位掩码 / Sign bit mask
    DL_DWR_EXPONE   : DWORD := 16#3F80_0000;      // 指数=127（1.0 尾数基位）/ Exponent 127, mantissa 1.0 base
    DL_DWR_ABSMIN   : REAL := 1.18E-38;           // 最小正规数阈值 [无量纲] / Min normal magnitude
    DL_DWR_ABSMAX   : REAL := 3.40E38;            // 最大可表幅值阈值 [无量纲] / Max representable magnitude
END_VAR
VAR
    fAbs   : REAL;                                // 输入幅值 [无量纲] / Input magnitude
    bNeg   : BOOL;                                // 符号位 [-] / Sign flag
    fExpF  : REAL;                                // 实数域指数中间量 [1] / Real-domain exponent intermediate
    nExp   : INT;                                 // 偏置指数（域 0..254）[1] / Biased exponent, 0..254
    fMant  : REAL;                                // 尾数份额 ∈ [0,1) [1] / Mantissa fraction in [0,1)
    dwMant : DWORD;                               // 尾数位型（23 位）/ Mantissa bits
    dwExp  : DWORD;                               // 指数位型 / Exponent bits
    dwSign : DWORD;                               // 符号位型 / Sign bits
    dwAll  : DWORD;                               // 组合位型 / Combined bits
    nExpU  : INT;                                 // 解包方向指数 [1] / Unpack exponent
    fTwoE  : REAL;                                // 2^nExp 缩放因子 [1] / Scaling factor 2^nExp
    fNorm  : REAL;                                // 归一尾数值 ∈ [1,2) [1] / Normalized mantissa value
    i      : INT;                                 // 指数迭代计数 [次] / Exponent iteration counter
    dwM    : DWORD;                               // 解包方向尾数位型 / Unpack mantissa bits
    fM     : REAL;                                // 解包方向尾数份额 [1] / Unpack mantissa fraction
END_VAR

// —— 段 0：全路径缺省 —— //
bValid   := FALSE;                              // 有效回执预清 / Validity preset
bClamped := FALSE;                              // 钳位标志预清 / Clamped flag preset
uErrorId := 16#0000;                            // 事件码预清 / Event code preset
dwOut    := 16#0000_0000;                       // 打包输出缺省零位型 / Packed output default
fOut     := 0.0;                                // 解包输出缺省零 / Unpacked output default
FC_DL_DwRealReinterp := 0.0;                    // 返回值缺省零（解包方向结果镜像）/ Return default mirrors unpack result

// —— 段 1：方向分派（CASE 全枚举 + ELSE 兜底） —— //
CASE eMode OF

E_DL_DwRealDir.eRealToDw :
    // —— 打包方向：REAL → IEEE-754 位型 —— //
    IF (fValue <> fValue) OR (ABS(fValue) > DL_DWR_ABSMAX) THEN
        uErrorId := 16#0002_1B01;               // 非有限或超可表幅值：拒收置码 / Non-finite or beyond range: reject
        RETURN;
    END_IF
    IF fValue = 0.0 THEN                        // 零（含 -0.0）特判 / Zero special case
        dwOut := 16#0000_0000;                  // 零位型 / Zero bits
        bValid := TRUE;                         // 有效回执 / Validity receipt
        FC_DL_DwRealReinterp := 0.0;            // 返回零 / Return zero
        RETURN;
    END_IF
    fAbs := ABS(fValue);                        // 幅值派生 / Magnitude
    IF fAbs < DL_DWR_ABSMIN THEN                // 次正规域：钳位为零（本件精度边界）/ Subnormal domain: clamp to zero
        bClamped := TRUE;                       // 钳位标志 / Clamped flag
        dwOut := 16#0000_0000;                  // 零位型 / Zero bits
        bValid := TRUE;                         // 有效（确定行为，不发散）/ Valid, deterministic
        RETURN;
    END_IF
    bNeg := (fValue < 0.0);                     // 符号提取 / Sign extraction
    fExpF := LOG(fAbs) / 0.693147180559945;     // log2(|f|)（ln2 常数除） / log2 of magnitude
    nExp := REAL_TO_DINT(fExpF);                // 截断取整（向零）/ Truncate toward zero
    IF REAL_TO_DINT(fExpF) < 0 THEN             // 负指数截断上偏一格修正 / Negative truncation correction
        IF fExpF < DINT_TO_REAL(nExp) THEN      // 向零截断丢失进位时修正 / Correct when truncation lost carry
            nExp := nExp - 1;                   // 指数下移保证尾数 ∈ [1,2) / Shift exponent so mantissa in [1,2)
        END_IF
    END_IF
    IF nExp < -126 THEN
        nExp := -126;                           // 指数下限钳位 / Exponent lower clamp
    END_IF
    IF nExp > 127 THEN
        nExp := 127;                            // 指数上限钳位 / Exponent upper clamp
    END_IF
    fTwoE := 1.0;                               // 2^nExp 迭代初值 / Iteration base for 2^nExp
    IF nExp >= 0 THEN
        FOR i := 1 TO nExp DO                    // 正指数迭代乘 2 / Positive exponent iteration
            fTwoE := fTwoE * 2.0;
        END_FOR
    ELSE
        FOR i := 1 TO (-nExp) DO                 // 负指数迭代除 2 / Negative exponent iteration
            fTwoE := fTwoE * 0.5;
        END_FOR
    END_IF
    fNorm := fAbs / fTwoE;                      // 归一尾数 ∈ [1,2) / Normalized mantissa
    IF fNorm >= 2.0 THEN                        // LOG 取整舍入上溢一格修正 / Rounding overshoot correction
        fNorm := fNorm * 0.5;                   // 尾数减半，指数加一 / Halve mantissa, bump exponent
        nExp := nExp + 1;
        IF nExp > 127 THEN
            nExp := 127;                        // 指数上限复钳位 / Exponent re-clamp upper
        END_IF
    END_IF
    fMant := fNorm - 1.0;                       // 小数份额 ∈ [0,1) / Fractional part
    dwMant := REAL_TO_DWORD(fMant * 8388608.0); // 份额 ×2^23 取整为位型 / Fraction scaled to 23-bit bits
    dwMant := SHL(dwMant, 0) AND DL_DWR_MANT_SHL;   // 低 23 位掩码（SHL 0 防方言化）/ Mask low 23 bits
    dwExp := DINT_TO_DWORD(nExp + 127);         // 偏置指数位型 / Biased exponent bits
    dwExp := SHL(dwExp, 23) AND DL_DWR_EXP_SHL; // 移位至位 30..23 并掩码 / Shift to bits 30..23 and mask
    IF bNeg THEN
        dwSign := DL_DWR_SIGN_SHL;              // 负号置符号位 / Negative sets sign bit
    ELSE
        dwSign := 16#0000_0000;                 // 正号零位型 / Positive zero bits
    END_IF
    dwOut := dwSign OR dwExp OR dwMant;         // 三段位或组合 / Combine three fields
    bValid := TRUE;                             // 有效回执 / Validity receipt
    FC_DL_DwRealReinterp := 0.0;                // 打包方向返回值无意义，置零 / Return meaningless in pack direction

E_DL_DwRealDir.eDwToReal :
    // —— 解包方向：IEEE-754 位型 → REAL —— //
    IF (dwBits AND DL_DWR_EXP_SHL) = DL_DWR_EXP_SHL THEN     // 指数全 1：Inf/NaN 域 / All-ones exponent: Inf or NaN
        uErrorId := 16#0002_1B01;               // 非有限拒收置码 / Non-finite reject code
        RETURN;
    END_IF
    dwM := dwBits AND DL_DWR_MANT_SHL;          // 尾数位型 / Mantissa bits
    fM := DWORD_TO_REAL(SHR(dwM, 0)) / 8388608.0;   // 尾数份额 ∈ [0,1)（SHR 0 保类型）/ Mantissa fraction
    nExpU := DWORD_TO_DINT(SHR(dwBits AND DL_DWR_EXP_SHL, 23)) - 127;   // 无偏指数 / Unbiased exponent
    IF (nExpU = -127) AND (dwM = 16#0000_0000) THEN          // e=0 且尾数=0：真零 / e=0 with zero mantissa: true zero
        IF (dwBits AND DL_DWR_SIGN_SHL) <> 16#0000_0000 THEN // 负零位型 / Negative zero bits
            fOut := 0.0;                        // 负零按零返回 / Return zero
        ELSE
            fOut := 0.0;                        // 正零 / Positive zero
        END_IF
        bValid := TRUE;                         // 有效回执 / Validity receipt
        FC_DL_DwRealReinterp := fOut;           // 返回镜像 / Return mirror
        RETURN;
    END_IF
    IF nExpU = -127 THEN                        // e=0 且尾数非零：次正规（本件精度边界）/ e=0 nonzero mantissa: subnormal
        bClamped := TRUE;                       // 钳位标志 / Clamped flag
        fOut := 0.0;                            // 次正规按零返回（确定行为）/ Subnormal as zero
        bValid := TRUE;                         // 有效（确定行为）/ Valid
        FC_DL_DwRealReinterp := fOut;           // 返回镜像 / Return mirror
        RETURN;
    END_IF
    fTwoE := 1.0;                               // 2^nExpU 迭代初值 / Iteration base
    IF nExpU >= 0 THEN
        FOR i := 1 TO nExpU DO                   // 正指数迭代 / Positive iteration
            fTwoE := fTwoE * 2.0;
        END_FOR
    ELSE
        FOR i := 1 TO (-nExpU) DO                // 负指数迭代 / Negative iteration
            fTwoE := fTwoE * 0.5;
        END_FOR
    END_IF
    fOut := (1.0 + fM) * fTwoE;                 // (1+mantissa)·2^e / Normalized value
    IF (dwBits AND DL_DWR_SIGN_SHL) <> 16#0000_0000 THEN     // 符号还原 / Sign restore
        fOut := -fOut;                          // 负值 / Negative value
    END_IF
    dwOut := 16#0000_0000;                      // 解包方向打包输出无效，置零位型 / Pack output meaningless here
    bValid := TRUE;                             // 有效回执 / Validity receipt
    FC_DL_DwRealReinterp := fOut;               // 返回值 = 解包结果（调用便利）/ Return equals unpack result

ELSE
    // —— 非法枚举兜底 —— //
    uErrorId := 16#0002_1B01;                   // 信息级：模式非法 / Info level: illegal mode
    RETURN;                                     // 全缺省返回 / Return all defaults
END_CASE
END_FUNCTION
