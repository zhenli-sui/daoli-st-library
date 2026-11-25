(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringIsNumeric
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准字符串九函数（LEN / MID / FIND），零厂商私有库
 * 功能描述 (Function)   : 数值合法性校验（HMI 文本输入落盘前的语法前置闸）。
 *                         接受文法：  [sign] digits [ . digits ] [ (e|E) [sign] digits ]
 *                         逐字符扫描并用字符集常量做归类：
 *                           · 数字集 '0123456789'    → FIND(集合, 单字符) > 0
 *                           · 符号集 '+-'            → FIND(集合, 单字符) > 0
 *                           · 小数点 '.'             → FIND('.', 单字符) = 1
 *                           · 指数标记集 'eE'        → FIND(集合, 单字符) > 0
 *                         结构约束：符号仅允许出现在首位或指数标记之后；小数点至多一次
 *                         且不得出现在指数之后；指数至多一次且其前必须有尾数数字；
 *                         指数后必须至少有一位数字。任一违规判「非数值」。
 *                         本件只判语法，不做数值转换（转换归 STRING_TO_LREAL 调用方）。
 * 接口     (Interface)  : 输入 sIn 待校验字符串 [-]；
 *                         输出 bIsNumeric 是否数值 [-]、uiDigits 数字字符个数 [个]、
 *                         bHasSign 是否带符号、bHasDot 是否带小数点、bHasExp 是否带指数、
 *                         eErrCode 错误码（E_DL_StrNumErr）；
 *                         返回值 = bValid 判定可信标志（TRUE = bIsNumeric 可信）。
 * 边界     (Boundary)   : ① 属主边界：只判语法，不做取值范围 / 溢出 / NaN-Inf 字面量判定；
 *                         也不做空白的隐式剔除（调用方需先过 FC_DL_StringRemoveWhitespace）。
 *                         ② 空串判「非数值」（eEmptyInput，信息级），返回 TRUE（判定可信）。
 *                         ③ 含非法字符判「非数值」（eNotNumeric，信息级），返回 TRUE。
 *                         ④ '.5' / '5.' / '+5' / '-5' / '1e3' / '1.5E-3' 均判为数值；
 *                         'e5' / '1e' / '1e+' / '1.2.3' / '+-1' / '1e3.5' 判为非数值。
 *                         ⑤ 扫描上界取实测长度（<=255），严格有界；全索引 1 基。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_StringSplitPair` / `FC_DL_StringRemoveWhitespace` 分工：
 *                         清洗与拆分归那两件，本件只判「是否数值」；数值转换归标准库。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + 4 个 BOOL 特征位 + UINT +
 *                         本文件内定义 enum E_DL_StrNumErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 字符集归类替代字符码强转 + 扫描上界钳位 + 状态互斥约束 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机，用文法状态位） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 5）
 * 验收向量 (Acceptance) : ① sIn='-12.5e3' → bIsNumeric=TRUE, uiDigits=4, bHasSign=TRUE,
 *                         bHasDot=TRUE, bHasExp=TRUE, eOk, 返回 TRUE；
 *                         ② sIn='12a3' → bIsNumeric=FALSE, eNotNumeric, 返回 TRUE；
 *                         ③ sIn='1e' → bIsNumeric=FALSE, eNotNumeric（指数后无数字）；
 *                         ④ sIn='' → bIsNumeric=FALSE, eEmptyInput, 返回 TRUE；
 *                         ⑤ sIn='007' → bIsNumeric=TRUE, uiDigits=3, eOk。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StrNumErr（数值合法性判定码，归属 DL_Base，与本件同文件，全库唯一属主）
 * 分级: 前四项为信息级（判定结果本身可信，返回 TRUE）；eInternal 为故障级。
 *----------------------------------------------------------------------------*)
TYPE E_DL_StrNumErr :
(
    eOk        := 0,   // 信息级：语法合法，判为数值 / Info: syntax legal, judged numeric
    eNotNumeric:= 1,   // 信息级：含非法字符或结构违规，判为非数值 / Info: illegal character or structure, judged non-numeric
    eEmptyInput:= 2,   // 信息级：空串，判为非数值 / Info: empty input, judged non-numeric
    eBadFormat := 3,   // 信息级：指数/尾数结构缺失 / Info: exponent or mantissa structure incomplete
    eInternal  := 9    // 故障级：内部一致性失败，判定不可信 / Fault: internal consistency failed, verdict untrustworthy
);
END_TYPE

FUNCTION FC_DL_StringIsNumeric : BOOL
VAR_INPUT
    sIn : STRING(255);   // 待校验字符串 [-] / String to validate
END_VAR
VAR_OUTPUT
    bIsNumeric : BOOL;   // 是否数值判定结果 [-] / Whether the text is numeric
    uiDigits   : UINT;   // 数字字符个数 [个] / Number of digit characters
    bHasSign   : BOOL;   // 是否出现合法符号 [-] / Whether a legal sign appeared
    bHasDot    : BOOL;   // 是否出现小数点 [-] / Whether a decimal point appeared
    bHasExp    : BOOL;   // 是否出现指数标记 [-] / Whether an exponent mark appeared
    eErrCode   : E_DL_StrNumErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _udLen          : UDINT;      // 输入字符数（钳位后） [字符] / Input length after clamping [chars]
    _udI            : UDINT;      // 扫描位置（1 基） [-] / Scan position, 1-based
    _sCur           : STRING(255);// 当前单字符 [-] / Current single character
    _bSeenMantDigit : BOOL;       // 尾数已见数字 [-] / Mantissa digit seen
    _bSeenDot       : BOOL;       // 小数点已见 [-] / Decimal point seen
    _bSeenExp       : BOOL;       // 指数标记已见 [-] / Exponent mark seen
    _bSeenExpDigit  : BOOL;       // 指数后已见数字 [-] / Digit after exponent seen
    _bAfterExp      : BOOL;       // 刚进入指数段（符号许可窗） [-] / Just entered exponent section, sign allowed window
    _bBad           : BOOL;       // 本字符违规标志 [-] / Violation flag for current character
    _uiDig          : UINT;       // 数字累加器 [个] / Digit accumulator
END_VAR
VAR CONSTANT
    DL_SIN_SET_DIGIT : STRING(255) := '0123456789';   // 数字字符集 [-] / Digit character set
    DL_SIN_SET_SIGN  : STRING(255) := '+-';           // 符号字符集 [-] / Sign character set
    DL_SIN_SET_EXP   : STRING(255) := 'eE';           // 指数标记字符集 [-] / Exponent mark character set
    DL_SIN_DOT       : STRING(255) := '.';            // 小数点字符 [-] / Decimal point character
    DL_SIN_LEN_MAX   : UINT := 255;                   // 缓冲上限（STRING(255) 契约） [字符] / Buffer ceiling [chars]
    DL_SIN_START     : UDINT := 1;                    // 字符串起始位置（IEC 1 基） [-] / String start position, 1-based
    DL_SIN_ONE_LEN   : UDINT := 1;                    // 单字符长度常量 [字符] / Single character length constant
    DL_SIN_HIT_ONE   : UDINT := 1;                    // FIND 首位命中的比较值 [-] / Compare value for first-position hit
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_StringIsNumeric := FALSE;                    // 返回值预置不可信 / Return preset untrustworthy
bIsNumeric := FALSE;                               // 判定哨兵：非数值 / Verdict sentinel: not numeric
uiDigits   := 0;                                   // 数字计数哨兵 / Digit count sentinel
bHasSign   := FALSE;                               // 符号特征预置无 / Sign feature preset false
bHasDot    := FALSE;                               // 小数点特征预置无 / Dot feature preset false
bHasExp    := FALSE;                               // 指数特征预置无 / Exponent feature preset false
eErrCode   := E_DL_StrNumErr.eInternal;            // 预置最严码 / Preset strictest code

(* —— 段 1：长度实测与上域钳位（缓冲可表性反算，扫描严格有界） —— *)
_udLen := LEN(sIn);                                // 输入字符数 / Input length
IF _udLen > UINT_TO_UDINT(DL_SIN_LEN_MAX) THEN
    _udLen := UINT_TO_UDINT(DL_SIN_LEN_MAX);       // 超上限钳位 / Clamp to ceiling
END_IF

(* —— 段 2：空串早退（判非数值，判定本身可信） —— *)
IF _udLen = 0 THEN
    eErrCode := E_DL_StrNumErr.eEmptyInput;        // 信息级：空串 / Info: empty input
    FC_DL_StringIsNumeric := TRUE;                 // 判定可信 / Verdict trustworthy
    RETURN;
END_IF

(* —— 段 3：文法状态位预清零（不含保持量，逐次判定独立） —— *)
_bSeenMantDigit := FALSE;
_bSeenDot       := FALSE;
_bSeenExp       := FALSE;
_bSeenExpDigit  := FALSE;
_bAfterExp      := FALSE;
_bBad           := FALSE;
_uiDig          := 0;
_udI            := DL_SIN_START;

(* —— 段 4：逐字符扫描与文法约束 —— *)
WHILE _udI <= _udLen DO
    _sCur := MID(sIn, DL_SIN_ONE_LEN, _udI);       // 取第 i 个字符（1 基） / Take i-th character, 1-based
    _bBad := FALSE;                                // 每字符先清违规位 / Clear violation flag per character

    IF FIND(DL_SIN_SET_DIGIT, _sCur) > 0 THEN
        (* 数字：计数，并按所处段置位尾数/指数数字位 *)
        _uiDig := _uiDig + 1;                      // 数字计数 / Digit count
        IF _bSeenExp THEN
            _bSeenExpDigit := TRUE;                // 指数段数字 / Digit inside exponent
        ELSE
            _bSeenMantDigit := TRUE;               // 尾数段数字 / Digit inside mantissa
        END_IF
        _bAfterExp := FALSE;                       // 离开符号许可窗 / Leave sign window
    ELSIF FIND(DL_SIN_SET_SIGN, _sCur) > 0 THEN
        (* 符号：仅首位或紧指数标记之后合法 *)
        IF (_udI = DL_SIN_START) OR _bAfterExp THEN
            bHasSign   := TRUE;                    // 合法符号出现 / Legal sign recorded
            _bAfterExp := FALSE;                   // 符号用掉许可窗 / Sign consumes window
        ELSE
            _bBad := TRUE;                         // 非法位置符号 / Sign in illegal position
        END_IF
    ELSIF FIND(DL_SIN_DOT, _sCur) = DL_SIN_HIT_ONE THEN
        (* 小数点：至多一次，且不得在指数之后 *)
        IF _bSeenDot OR _bSeenExp THEN
            _bBad := TRUE;                         // 重复小数点或指数后小数点 / Duplicate dot or dot after exponent
        ELSE
            _bSeenDot := TRUE;
            bHasDot   := TRUE;
            _bAfterExp := FALSE;
        END_IF
    ELSIF FIND(DL_SIN_SET_EXP, _sCur) > 0 THEN
        (* 指数标记：至多一次，其前必须有尾数数字 *)
        IF _bSeenExp OR (NOT _bSeenMantDigit) THEN
            _bBad := TRUE;                         // 重复指数或尾数缺失 / Duplicate exponent or missing mantissa
        ELSE
            _bSeenExp  := TRUE;
            bHasExp    := TRUE;
            _bAfterExp := TRUE;                    // 打开符号许可窗 / Open sign window
        END_IF
    ELSE
        _bBad := TRUE;                             // 非法字符 / Illegal character
    END_IF

    IF _bBad THEN
        bIsNumeric := FALSE;                       // 判非数值 / Judge non-numeric
        uiDigits   := _uiDig;                      // 导出已数到的位数 / Export counted digits
        eErrCode   := E_DL_StrNumErr.eNotNumeric;  // 信息级：非法字符/结构 / Info: illegal character or structure
        FC_DL_StringIsNumeric := TRUE;             // 判定可信 / Verdict trustworthy
        RETURN;                                    // 早退 / Early exit
    END_IF

    _udI := _udI + 1;                              // 位置步进 / Advance position
END_WHILE

(* —— 段 5：收尾文法校验（尾数必须有数字；指数段必须有数字） —— *)
IF NOT _bSeenMantDigit THEN
    bIsNumeric := FALSE;                           // 无尾数数字 / No mantissa digit
    uiDigits   := _uiDig;
    eErrCode   := E_DL_StrNumErr.eBadFormat;       // 信息级：结构缺失 / Info: structure incomplete
    FC_DL_StringIsNumeric := TRUE;
    RETURN;
END_IF

IF _bSeenExp AND (NOT _bSeenExpDigit) THEN
    bIsNumeric := FALSE;                           // 指数后无数字 / No digit after exponent
    uiDigits   := _uiDig;
    eErrCode   := E_DL_StrNumErr.eBadFormat;       // 信息级：结构缺失 / Info: structure incomplete
    FC_DL_StringIsNumeric := TRUE;
    RETURN;
END_IF

(* —— 段 6：成功出口（语法合法，判为数值） —— *)
bIsNumeric := TRUE;                                // 判为数值 / Judged numeric
uiDigits   := _uiDig;                              // 导出数字个数 / Export digit count
eErrCode   := E_DL_StrNumErr.eOk;                  // 信息级成功 / Info success
FC_DL_StringIsNumeric := TRUE;                     // 判定可信 / Verdict trustworthy

END_FUNCTION
