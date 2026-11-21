(*==============================================================================
 * 组件名称 (Component)  : FC_DL_HexStringToBytes
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（LEN / MID / FIND / SHL / 显式转换），
 *                         无厂商方言，字符访问用标准 MID 函数而非下标方言
 * 功能描述 (Function)   : 十六进制 ASCII 字符串到字节数组的严格解析。
 *                         "1A2B3C" → 16#1A, 16#2B, 16#3C；可选剥离 Modbus ASCII
 *                         帧的冒号帧头与回车换行帧尾。用于扫码枪十六进制输出、
 *                         Modbus ASCII 收帧、RFID 标签 ID 解析、固件分段校验的
 *                         前置解码。与 FC_DL_LrcChecksum 组成"先解码、后校验"
 *                         的两步收帧链路。
 *                         两遍扫描严格模式：第一遍全量校验字符合法性，
 *                         第二遍才写入输出——任何失败路径不留下半截缓冲。
 *
 * 【严格模式声明 / Strict-mode statement（边界 B2）】
 *   **不跳过空格、不跳过 0x 前缀、不容忍内嵌分隔符**："1A 2B" 判非法。
 *   宽容解析会把组帧错误吃进数据层，现场表现为"校验通过但数据错"，
 *   比直接报错难查一个数量级。
 *
 * 【先校验后写入 / Validate-then-write（边界 B1）】
 *   任何失败路径不得留下部分写入的输出缓冲——调用方可能直接把缓冲
 *   拿去发报文，半截字节流比没有更危险。
 *
 * 【奇数长度 / Odd length（边界 B4）】
 *   判非法而非"末尾补 0"——补 0 会凭空造出一个字节。
 *
 * 【位置语义 / Position semantics（边界 B9）】
 *   nInvalidPos 为原文 1 起的字符位置（含被剥离的冒号），便于现场
 *   拿着报文直接数到出错字符。
 *
 * 【字符串长度警示 / String-length warning（边界 B6）】
 *   形参显式声明为 255 长度：CODESYS 系平台默认 STRING 仅 80 字节，
 *   不显式声明长度会被静默截断，长报文解析出错且无任何提示。
 *
 * 【验收向量 / Acceptance vectors】
 *   V1  "1A2B3C"，nMaxBytes = 64 → 返回 3；[16#1A, 16#2B, 16#3C]
 *   V2  "1a2b"（小写）→ 返回 2；[16#1A, 16#2B]
 *   V3  ":010300000001FB" + CR + LF，bStripFraming = TRUE
 *       → 返回 7；[01,03,00,00,00,01,FB]（与 FC_DL_LrcChecksum V1 闭环）
 *   V4  "1A2B3"（奇数长度）→ 返回 -1、16#0002_000A、nInvalidPos = 6、缓冲不变
 *   V5  "1G"（非法字符）→ 返回 -1、16#0002_000A、nInvalidPos = 2
 *   V6  130 字符（65 字节）且 nMaxBytes = 64 → 返回 -1、16#0001_0009、缓冲不变
 *   V7  空串 → 返回 0、uErrorId = 0（空报文合法，由上层判长度）
 * 开源溯源 (Origin)     : 原创实现（参考西门子 LGF 转换器组"字符串与数值互转、
 *                         按类型分函数、单一职责"的组织方式，以及 Modbus 应用
 *                         协议规范的 ASCII 帧定义，clean-room 编写，
 *                         未复制任何源码）。
 * 依赖     (Depends)    : 无 DL_ 内部依赖（配套校验见 FC_DL_LrcChecksum）
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3（MID/FIND 取字符，无下标方言、无指针）
 *                         R4 ✓ 容量钳位 + 奇数与非法字符拒绝 + 失败不写缓冲
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无状态机）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 收口批次 · R3）
 *============================================================================*)
FUNCTION FC_DL_HexStringToBytes : INT
VAR_IN_OUT
    aabyOut       : ARRAY[0..63] OF BYTE;   // 输出字节缓冲，失败时不写入 / Output buffer, untouched on failure
END_VAR
VAR_INPUT
    sHex          : STRING(255);            // 十六进制字符串，显式 255 长度防截断 / Hex string, explicit 255 length
    bStripFraming : BOOL := FALSE;          // TRUE：剥离首冒号与尾部回车换行 / TRUE: strip leading colon and trailing CR/LF
    nMaxBytes     : INT  := 64;             // 允许写入的最大字节数，1..64 / Maximum bytes to write, range 1..64
END_VAR
VAR_OUTPUT
    nInvalidPos   : INT;                    // 首个非法字符位置（原文 1 起），0 = 无 / First invalid char position, 1-based in the original
    uErrorId      : UDINT;                  // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    nLen          : INT;                    // 原文长度 / Original string length
    nStart        : INT;                    // 有效起始位置（1 起） / Effective start index, 1-based
    nEnd          : INT;                    // 有效结束位置（1 起，含） / Effective end index, 1-based inclusive
    nHexLen       : INT;                    // 有效十六进制字符数 / Effective hex character count
    nBytes        : INT;                    // 待写字节数 / Bytes to write
    nI            : INT;                    // 字符或字节循环索引 / Char or byte loop index
    nHiNib        : INT;                    // 高半字节值 0..15 / High nibble value 0..15
    nLoNib        : INT;                    // 低半字节值 0..15 / Low nibble value 0..15
    sChar         : STRING(1);              // 当前字符（标准 MID 取出） / Current char via standard MID
END_VAR
VAR CONSTANT
    DL_HX_BUF_MAX  : INT := 64;             // 输出缓冲上限，必须与数组维度一致 / Output buffer limit, must match the array
    DL_HX_PAIR     : INT := 2;              // 每字节字符数 / Chars per byte
    DL_HX_ONE      : INT := 1;              // MID 单字符长度参数 / MID single-char length
    DL_HX_SHIFT    : INT := 4;              // 高半字节左移位数 / High-nibble shift count
    DL_HX_COLON    : STRING(1) := ':';      // Modbus ASCII 帧头 / Modbus ASCII frame start
    DL_HX_CR       : STRING(1) := '$R';     // 回车 / Carriage return
    DL_HX_LF       : STRING(1) := '$L';     // 换行 / Line feed
    DL_HX_DIG_UP   : STRING := '0123456789ABCDEF'; // 大写十六进制字符表（FIND 定位） / Uppercase hex digits for FIND lookup
    DL_HX_DIG_LOW  : STRING := '0123456789abcdef'; // 小写十六进制字符表（FIND 定位） / Lowercase hex digits for FIND lookup
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置：返回值与位置码归零，先校验后写入（边界 B1）
 *      Safe preset: return and position cleared, validate before writing
 *-----------------------------------------------------------------------------*)
FC_DL_HexStringToBytes := 0;
nInvalidPos := 0;
uErrorId    := 16#0000_0000;
nBytes      := 0;

(*------------------------------------------------------------------------------
 * 段 2｜容量参数钳位：小于 1 抬到 1，大于 64 压到 64（瞬时码）
 *      Capacity clamp: raise to 1 or lower to 64, transient code
 *-----------------------------------------------------------------------------*)
IF nMaxBytes < 1 THEN
    nMaxBytes := 1;
    uErrorId  := 16#0001_0001;
ELSIF nMaxBytes > DL_HX_BUF_MAX THEN
    nMaxBytes := DL_HX_BUF_MAX;
    uErrorId  := 16#0001_0001;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜原文长度与有效区间初值（IEC 字符串位置 1 起）
 *      Original length and effective range init, IEC strings are 1-based
 *-----------------------------------------------------------------------------*)
nLen   := LEN(sHex);
nStart := 1;
nEnd   := nLen;

(*------------------------------------------------------------------------------
 * 段 4｜帧剥离（边界 B5）：只剥首冒号与尾部回车/换行，不剥空格。
 *      Framing strip: only the colon and trailing CR/LF, never spaces
 *      尾部先判换行再判回车，顺序固定，天然兼容 CRLF / LF / CR 三种结尾
 *-----------------------------------------------------------------------------*)
IF bStripFraming THEN
    IF (nLen >= 1) THEN
        sChar := MID(sHex, DL_HX_ONE, 1);
        IF sChar = DL_HX_COLON THEN
            nStart := 2;
        END_IF
    END_IF
    IF nEnd >= nStart THEN
        sChar := MID(sHex, DL_HX_ONE, nEnd);
        IF sChar = DL_HX_LF THEN
            nEnd := nEnd - 1;
        END_IF
    END_IF
    IF nEnd >= nStart THEN
        sChar := MID(sHex, DL_HX_ONE, nEnd);
        IF sChar = DL_HX_CR THEN
            nEnd := nEnd - 1;
        END_IF
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜有效长度与空串兜底：空报文是合法输入，返回 0 不报错（边界 B7）
 *      Effective length and empty-string fallback: empty is legal, return 0
 *-----------------------------------------------------------------------------*)
nHexLen := nEnd - nStart + 1;
IF nHexLen < 0 THEN
    nHexLen := 0;
END_IF
IF nHexLen = 0 THEN
    RETURN;                                 // 空报文：返回 0、无故障 / Empty payload, return 0 with no error
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜奇数长度拒绝（边界 B4）：判非法而非末尾补 0
 *      Odd length rejected: never pad a phantom byte
 *-----------------------------------------------------------------------------*)
IF (nHexLen MOD DL_HX_PAIR) <> 0 THEN
    uErrorId    := 16#0002_000A;            // 十六进制串非法 / Invalid hex string
    nInvalidPos := nStart + nHexLen;        // 指向悬空的半个字节 / Points at the dangling half byte
    FC_DL_HexStringToBytes := -1;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜第一遍：全量字符合法性校验（标准 FIND 定位，大小写同等接受）
 *      Pass 1: full character validation via standard FIND, case-insensitive
 *      此遍绝不写输出缓冲（边界 B1）
 *-----------------------------------------------------------------------------*)
FOR nI := 0 TO (nHexLen - 1) DO
    sChar  := MID(sHex, DL_HX_ONE, nStart + nI);
    nHiNib := FIND(DL_HX_DIG_UP, sChar) - 1;    // 0..15，未命中为 -1 / 0..15, -1 if not found
    IF nHiNib < 0 THEN
        nHiNib := FIND(DL_HX_DIG_LOW, sChar) - 1;
    END_IF
    IF (nHiNib < 0) OR (nHiNib > 15) THEN
        uErrorId    := 16#0002_000A;        // 非 hex 字符 / Non-hex character
        nInvalidPos := nStart + nI;         // 原文 1 起位置（边界 B9） / 1-based original position
        FC_DL_HexStringToBytes := -1;
        RETURN;
    END_IF
END_FOR;

(*------------------------------------------------------------------------------
 * 段 8｜容量检查：整帧拒绝，不写半截（边界 B1）
 *      Capacity check: reject the whole frame, never write a partial stream
 *-----------------------------------------------------------------------------*)
nBytes := nHexLen / DL_HX_PAIR;             // 整除，奇数已在段 6 排除 / Integer division, odd already rejected
IF (nBytes > nMaxBytes) OR (nBytes > DL_HX_BUF_MAX) THEN
    uErrorId := 16#0001_0009;               // 输出缓冲不足 / Output buffer insufficient
    FC_DL_HexStringToBytes := -1;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜第二遍：组装写入。高半字节左移 4 位或上低半字节，显式 INT_TO_BYTE
 *      Pass 2: assemble and write, explicit INT_TO_BYTE after the nibble shift
 *-----------------------------------------------------------------------------*)
FOR nI := 0 TO (nBytes - 1) DO
    sChar  := MID(sHex, DL_HX_ONE, nStart + (DL_HX_PAIR * nI));
    nHiNib := FIND(DL_HX_DIG_UP, sChar) - 1;
    IF nHiNib < 0 THEN
        nHiNib := FIND(DL_HX_DIG_LOW, sChar) - 1;
    END_IF
    sChar  := MID(sHex, DL_HX_ONE, nStart + (DL_HX_PAIR * nI) + 1);
    nLoNib := FIND(DL_HX_DIG_UP, sChar) - 1;
    IF nLoNib < 0 THEN
        nLoNib := FIND(DL_HX_DIG_LOW, sChar) - 1;
    END_IF
    IF (nI >= 0) AND (nI < DL_HX_BUF_MAX) THEN
        (* 写前下标双检（红线 R4）：容量已在段 8 保证，仍显式兜底 *)
        (* Index double check before writing: guaranteed by pass 8, explicit anyway *)
        aabyOut[nI] := SHL(INT_TO_BYTE(nHiNib), DL_HX_SHIFT) OR INT_TO_BYTE(nLoNib);
    END_IF
END_FOR;

(*------------------------------------------------------------------------------
 * 段 10｜成功返回：返回写入字节数；帧剥离发生时返回值不含帧字符
 *      Success return: byte count written, framing chars never counted
 *-----------------------------------------------------------------------------*)
FC_DL_HexStringToBytes := nBytes;
END_FUNCTION
