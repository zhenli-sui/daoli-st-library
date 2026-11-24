(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringCsvFieldEscape
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准字符串九函数（LEN / MID / CONCAT / FIND），零厂商私有库
 * 功能描述 (Function)   : CSV 单字段转义（RFC 4180 语义）。规则：
 *                           · 字段含逗号 / 双引号 / 换行时，整体用双引号包裹；
 *                           · 包裹时字段内每个双引号双写（" → ""）；
 *                           · 不含特殊字符时原样返回，不加引号（bQuoted=FALSE）。
 *                         用途：把 PLC 侧的批号 / 牌号 / 报警文本安全拼入 CSV 行。
 * 接口     (Interface)  : 输入 sIn 原始字段文本 [-]；
 *                         输出 sOut 转义结果、uiOutLen 结果字符数 [字符]、
 *                         bQuoted 是否已加引号、uiQuoteCount 字段内双引号个数 [个]、
 *                         eErrCode 错误码（E_DL_StrCsvErr）；
 *                         返回值 = bValid 转义有效标志（TRUE = sOut 可信）。
 * 边界     (Boundary)   : ① 属主边界：只转义单字段，不拼行、不加行尾 CR/LF、不转义分隔符本身。
 *                         ② 缓冲区可表性：转义后长度 = 原长 + 2（包裹引号）+ 引号数；
 *                         预估超 255 时判故障级 eBufferFull 并回哨兵空串（**绝不做静默截断**，
 *                         截断会破坏 CSV 语法，宁可报错交由调用方拆字段）。
 *                         ③ 换行检测依赖 IEC 字符串转义 $N（标准写法）。若某平台不解析该转义，
 *                         集合退化为两字符字面量，只会导致**多**加引号（CSV 语法仍合法），
 *                         不会漏引号——降级方向安全，已在本件显式声明。
 *                         ④ 空串合法：输出空串、bQuoted=FALSE、eOk。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_StringSplitPair` 分工：反解析归那件、本件只做正向转义；
 *                         与 `FC_DL_StringRemoveWhitespace` 分工：空白剔除会破坏 CSV 语义，不混用。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + STRING + 2×UINT + BOOL +
 *                         本文件内定义 enum E_DL_StrCsvErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 预估长度前置校验（不静默截断）+ 扫描上界钳位 + 除零无路径 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 10）
 * 验收向量 (Acceptance) : ① sIn='ABC' → sOut='ABC'（不加引号）, uiOutLen=3, bQuoted=FALSE, eOk；
 *                         ② sIn='A,B' → sOut='"A,B"'（7 字符）, uiOutLen=7, bQuoted=TRUE；
 *                         ③ sIn='A"B' → sOut='"A""B"'（7 字符）, uiQuoteCount=1, bQuoted=TRUE；
 *                         ④ sIn='' → sOut='', uiOutLen=0, bQuoted=FALSE, eOk；
 *                         ⑤ 转义后超 255 → 返回 FALSE, sOut='', eBufferFull。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StrCsvErr（CSV 字段转义错误码，归属 DL_Base，与本件同文件，全库唯一属主）
 * 分级: eBufferFull 为故障级（返回 FALSE，回哨兵空串）；其余为信息级（返回 TRUE）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_StrCsvErr :
(
    eOk         := 0,   // 信息级：转义完成（含不加引号情形） / Info: escaping done, quoting included
    eQuoteAdded := 1,   // 信息级：已加引号包裹 / Info: field wrapped in quotes
    eBufferFull := 9    // 故障级：转义后超缓冲上限，拒绝静默截断 / Fault: escaped field exceeds buffer, silent truncation refused
);
END_TYPE

FUNCTION FC_DL_StringCsvFieldEscape : BOOL
VAR_INPUT
    sIn : STRING(255);   // 原始字段文本 [-] / Raw field text
END_VAR
VAR_OUTPUT
    sOut         : STRING(255); // 转义结果 [-] / Escaped result
    uiOutLen     : UINT;        // 结果字符数 [字符] / Result character count [chars]
    bQuoted      : BOOL;        // 是否已加引号 [-] / Whether the field was quoted
    uiQuoteCount : UINT;        // 字段内双引号个数 [个] / Number of double quotes inside the field
    eErrCode     : E_DL_StrCsvErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _udLen    : UDINT;        // 输入字符数（钳位后） [字符] / Input length after clamping [chars]
    _udI      : UDINT;        // 扫描位置（1 基） [-] / Scan position, 1-based
    _udNeed   : UDINT;        // 转义后预估长度 [字符] / Estimated escaped length [chars]
    _uiQ      : UINT;         // 引号计数累加器 [个] / Quote counter accumulator
    _bSpecial : BOOL;         // 是否含需引号包裹的字符 [-] / Whether a character requiring quoting exists
    _sCur     : STRING(255);  // 当前单字符 [-] / Current single character
END_VAR
VAR CONSTANT
    DL_SCSV_DELIM : STRING(255) := ',';   // 字段分隔符（逗号） [-] / Field delimiter, comma
    DL_SCSV_QUOTE : STRING(255) := '"';   // 双引号字符 [-] / Double quote character
    DL_SCSV_QUOTE2: STRING(255) := '""';  // 双写引号（转义用） [-] / Doubled quote for escaping
    DL_SCSV_NL    : STRING(255) := '$N';  // 换行符（IEC 转义写法） [-] / Line feed via IEC escape
    DL_SCSV_LEN_MAX : UINT := 255;        // 缓冲上限（STRING(255) 契约） [字符] / Buffer ceiling [chars]
    DL_SCSV_START : UDINT := 1;           // 字符串起始位置（IEC 1 基） [-] / String start position, 1-based
    DL_SCSV_ONE_LEN: UDINT := 1;          // 单字符长度常量 [字符] / Single character length constant
    DL_SCSV_HIT_ONE: UDINT := 1;          // FIND 首位命中的比较值 [-] / Compare value for first-position hit
    DL_SCSV_WRAP   : UDINT := 2;          // 首尾包裹引号占位长度 [字符] / Wrapping quote pair length [chars]
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_StringCsvFieldEscape := FALSE;               // 返回值预置无效 / Return preset invalid
sOut         := '';                                // 结果哨兵空串 / Result sentinel
uiOutLen     := 0;                                 // 长度哨兵 0 / Length sentinel
bQuoted      := FALSE;                             // 加引号标志预置否 / Quote flag preset false
uiQuoteCount := 0;                                 // 引号计数哨兵 0 / Quote count sentinel
eErrCode     := E_DL_StrCsvErr.eBufferFull;        // 预置最严码 / Preset strictest code

(* —— 段 1：长度实测与上域钳位 —— *)
_udLen := LEN(sIn);                                // 输入字符数 / Input length
IF _udLen > UINT_TO_UDINT(DL_SCSV_LEN_MAX) THEN
    _udLen := UINT_TO_UDINT(DL_SCSV_LEN_MAX);      // 超上限钳位（仅为预估有界，不改变拒绝策略） / Clamp for bounded estimate
END_IF

(* —— 段 2：空串早退（合法零结果，不加引号） —— *)
IF _udLen = 0 THEN
    eErrCode := E_DL_StrCsvErr.eOk;                // 信息级成功 / Info success
    FC_DL_StringCsvFieldEscape := TRUE;            // 结果可信 / Result trustworthy
    RETURN;
END_IF

(* —— 段 3：扫描统计（是否需要包裹 + 引号个数） —— *)
_bSpecial := FALSE;                                // 特殊字符标志清零 / Clear special flag
_uiQ      := 0;                                    // 引号计数清零 / Clear quote counter
_udI      := DL_SCSV_START;
WHILE _udI <= _udLen DO
    _sCur := MID(sIn, DL_SCSV_ONE_LEN, _udI);      // 取第 i 个字符（1 基） / Take i-th character, 1-based
    IF FIND(DL_SCSV_DELIM, _sCur) > 0 THEN
        _bSpecial := TRUE;                         // 含分隔符需包裹 / Delimiter present: needs quoting
    END_IF
    IF FIND(DL_SCSV_QUOTE, _sCur) = DL_SCSV_HIT_ONE THEN
        _bSpecial := TRUE;                         // 含引号需包裹 / Quote present: needs quoting
        _uiQ      := _uiQ + 1;                     // 引号计数 / Count the quote
    END_IF
    IF FIND(DL_SCSV_NL, _sCur) > 0 THEN
        _bSpecial := TRUE;                         // 含换行需包裹 / Newline present: needs quoting
    END_IF
    _udI := _udI + 1;                              // 位置步进 / Advance position
END_WHILE

uiQuoteCount := _uiQ;                              // 导出引号个数 / Export quote count

(* —— 段 4：无需包裹 → 原样返回（早退，避免任何改写） —— *)
IF NOT _bSpecial THEN
    sOut     := sIn;                               // 原样返回 / Return as-is
    uiOutLen := UDINT_TO_UINT(LEN(sOut));          // 实测长度 / Measured length
    bQuoted  := FALSE;                             // 未加引号 / Not quoted
    eErrCode := E_DL_StrCsvErr.eOk;                // 信息级成功 / Info success
    FC_DL_StringCsvFieldEscape := TRUE;
    RETURN;
END_IF

(* —— 段 5：缓冲区可表性前置校验（预估超限即拒绝，绝不静默截断） —— *)
_udNeed := _udLen + DL_SCSV_WRAP + UINT_TO_UDINT(_uiQ);   // 原长 + 包裹 + 双写增量 / Original plus wrap plus doubling
IF _udNeed > UINT_TO_UDINT(DL_SCSV_LEN_MAX) THEN
    eErrCode := E_DL_StrCsvErr.eBufferFull;        // 故障级：缓冲不足 / Fault: buffer insufficient
    RETURN;                                        // 保持哨兵空串与返回 FALSE / Keep sentinel and FALSE
END_IF

(* —— 段 6：构造包裹串（先加首引号，逐字符双写，再加尾引号） —— *)
sOut := DL_SCSV_QUOTE;                             // 首引号 / Opening quote
_udI := DL_SCSV_START;
WHILE _udI <= _udLen DO
    _sCur := MID(sIn, DL_SCSV_ONE_LEN, _udI);      // 取第 i 个字符 / Take i-th character
    IF FIND(DL_SCSV_QUOTE, _sCur) = DL_SCSV_HIT_ONE THEN
        sOut := CONCAT(sOut, DL_SCSV_QUOTE2);      // 引号双写 / Double the quote
    ELSE
        sOut := CONCAT(sOut, _sCur);               // 普通字符直追加 / Append plain character
    END_IF
    _udI := _udI + 1;                              // 位置步进 / Advance position
END_WHILE
sOut := CONCAT(sOut, DL_SCSV_QUOTE);               // 尾引号 / Closing quote

(* —— 段 7：结果复检（长度必须等于预估，否则判缓冲不可信） —— *)
uiOutLen := UDINT_TO_UINT(LEN(sOut));              // 实测结果长度 / Measured result length
IF UDINT_TO_UINT(_udNeed) <> uiOutLen THEN
    sOut     := '';                                // 复检失败回哨兵 / Recheck failed: sentinel
    uiOutLen := 0;
    bQuoted  := FALSE;
    eErrCode := E_DL_StrCsvErr.eBufferFull;        // 故障级码 / Fault-level code
    RETURN;                                        // 返回 FALSE 保持 / Keep return FALSE
END_IF

(* —— 段 8：成功出口 —— *)
bQuoted  := TRUE;                                  // 已加引号 / Field quoted
eErrCode := E_DL_StrCsvErr.eQuoteAdded;            // 信息级：已包裹 / Info: wrapped
FC_DL_StringCsvFieldEscape := TRUE;                // 转义有效 / Escaping valid

END_FUNCTION
