(*==============================================================================
 * 组件名称 (Component)  : FC_DL_HexStringToLword
 * 所属子库 (Sublibrary) : DL_MathData
 * 归属目录 (Directory)  : C:\Library\DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 函数（FUNCTION）· 纯函数 · 十六进制串解析
 *                         iec-std-wrapper / string / bitstring
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 LEN / MID / FIND
 * 溯源声明 (Provenance) : IEC 61131-3 标准语义的道莅防御性实现——内部委托平台标准库语义，
 *                         外围统一错误码 / 钳位 / 双语注释，严禁重实现数学内核。
 * 功能一句话 (Summary)  : 大小写十六进制串解析为 LWORD，奇偶长度、非法字符、
 *                         超长溢出三闸齐备，与 FC_DL_BytesToHexString 互补成对。
 *
 * 功能描述 (Function)   : 一次锁存串长后按序过三闸：长度大于 16 即溢出闸、
 *                         奇数长度即对齐闸、逐字符经三张码表定位失败即非法闸；
 *                         合法路径每字符左移 4 位并入半字节，空串恒等返回零值。
 * 与既有件边界 (Boundary): 本件只解析裸十六进制串，不识别 0x 前缀、不下划线
 *                         分隔；超过 16 个有效位即溢出拒绝，绝不静默截高位。
 * 码位说明 (Codes)      : 信息 16#0002_3040 空输入恒等返回（值零、解析零位）
 *                         故障 16#0002_3041 奇数长度（半个字节无法对齐）
 *                         故障 16#0002_3042 非法字符（不在 0-9 A-F a-f）
 *                         故障 16#0002_3043 超长溢出（有效位大于 16）
 *                         段 16#02_3_40~43 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 LEN / MID / FIND。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 标准库
 *                         移位量 4 恒小于 64 位宽（归一达标）｜ 无除法面
 *                         全变量双语同行注释 ｜ 无定时器实例
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 1）
 *============================================================================*)

FUNCTION FC_DL_HexStringToLword : BOOL
VAR_INPUT
    sHex : STRING(255);                 // 源十六进制串 [ASCII]，有效位最多 16 / Source hex string, at most 16 digits
END_VAR
VAR_OUTPUT
    uValue  : LWORD;                    // 解析结果 [位串]，域外拒绝时保持零 / Parsed value, zero when refused
    nParsed : INT;                      // 成功解析的有效位数 [位] / Digits parsed on success
    uErrorId: UDINT;                    // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    cCh    : STRING(1);   // 当前字符 [字符] / Current character
    nLen   : INT;         // 锁存的源串长度 [字符]，R38 唯一锁存量 / Latched source length
    nVal   : INT;         // 当前半字节值 [值]，域 0 到 15 / Current nibble value, 0 to 15
    nPos   : INT;         // 码表定位结果 [索引]，1 起 / Table position, 1-based
    nI     : INT;         // 字符循环下标 [索引] / Character loop index
    uAcc   : LWORD;       // 累积值 [位串]，出口一次性赋给 uValue / Accumulator
    uCode  : UDINT;       // 码位暂存，出口单点写入 [码] / Code staging
END_VAR
VAR CONSTANT
    DL_HTL_MAXDIG : INT := 16;  // 有效位上限 [位]，LWORD 恰好 64 位 / Digit limit, LWORD is exactly 64 bits
    DL_HTL_ONE    : INT := 1;   // 单字符长度参数 [字符] / Single character length argument
END_VAR

(* 段 1｜输出预置与残留清除 / Pre-set and clear before any branch *)
FC_DL_HexStringToLword := FALSE;
uValue   := 16#0000_0000_0000_0000;
uAcc     := 16#0000_0000_0000_0000;
nParsed  := 0;
uErrorId := 16#0000_0000;
uCode    := 16#0000_0000;

(* 段 2｜LEN 一次锁存 / Latch the length once *)
nLen := LEN(sHex);
IF nLen < 0 THEN
    nLen := 0;                   // 防御：异常返回值钳到零 / Defensive clamp
END_IF

(* 段 3｜空串恒等：信息级告知后成功返回零值 / Empty string identity: inform and succeed *)
IF nLen = 0 THEN
    uErrorId := 16#0002_3040;    // 信息级：空输入恒等返回 / Info: empty input identity
    FC_DL_HexStringToLword := TRUE;
    RETURN;
END_IF

(* 段 4｜溢出闸：有效位超过 16 直接拒绝，绝不静默截高位 / Overflow gate: refuse, never truncate silently *)
IF nLen > DL_HTL_MAXDIG THEN
    uErrorId := 16#0002_3043;    // 故障级：超长溢出 / Fault: overflow by length
    RETURN;
END_IF

(* 段 5｜对齐闸：奇数长度意味着半个字节，解析结果无法定界 / Alignment gate: odd length leaves a half byte undefined *)
IF (nLen MOD 2) = 1 THEN
    uErrorId := 16#0002_3041;    // 故障级：奇数长度 / Fault: odd length
    RETURN;
END_IF

(* 段 6｜逐字符解析：三张码表定位，失败即非法闸 / Parse per character: three tables, failure is the legality gate *)
FOR nI := 1 TO nLen DO
    cCh := MID(sHex, DL_HTL_ONE, nI);                // 取当前字符 / Take the current character
    IF (cCh >= '0') AND (cCh <= '9') THEN
        nPos := FIND('0123456789', cCh);             // 数字表定位，域内恒 1 到 10 / Digit table, 1 to 10
        nVal := nPos - DL_HTL_ONE;                   // 值 0 到 9 / Value 0 to 9
    ELSIF (cCh >= 'A') AND (cCh <= 'F') THEN
        nPos := FIND('ABCDEF', cCh);                 // 大写表定位 / Uppercase table
        nVal := 10 + (nPos - DL_HTL_ONE);            // 值 10 到 15 / Value 10 to 15
    ELSIF (cCh >= 'a') AND (cCh <= 'f') THEN
        nPos := FIND('abcdef', cCh);                 // 小写表定位 / Lowercase table
        nVal := 10 + (nPos - DL_HTL_ONE);            // 值 10 到 15 / Value 10 to 15
    ELSE
        uErrorId := 16#0002_3042;                    // 故障级：非法字符 / Fault: illegal character
        RETURN;
    END_IF
    uAcc := SHL(uAcc, 4) OR INT_TO_LWORD(nVal);      // 左移 4 位并入半字节 / Shift four and OR the nibble
    nParsed := nParsed + DL_HTL_ONE;                 // 有效位计数 / Count the digit
END_FOR

(* 段 7｜出口装配：结果与码位单点写出 / Exit: single write for result and code *)
uValue := uAcc;
uErrorId := uCode;
FC_DL_HexStringToLword := TRUE;
END_FUNCTION
