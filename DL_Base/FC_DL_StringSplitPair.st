(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringSplitPair
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准字符串九函数（LEN / MID / FIND），零厂商私有库
 * 功能描述 (Function)   : key=value 单对拆分（HMI 参数设置报文 "Speed=1500" 解析）。
 *                         以首个分隔符位置为界：左侧为键、右侧为值（值可含分隔符，
 *                         故只按首个分隔符切分）。缺分隔符、空键均置无效回执（返回 FALSE），
 *                         空值合法（代表「置空」语义，回执 bHasValue=FALSE 但不判故障）。
 *                         分隔符为可配字符串（默认 '='），支持 ':=' / '->' 等双字符分隔。
 * 接口     (Interface)  : 输入 sIn 待拆分字符串 [-]、sSep 分隔符（空串回落 '='）[-]；
 *                         输出 sKey 键、sValue 值、uiKeyLen 键长 [字符]、uiValueLen 值长 [字符]、
 *                         bHasValue 是否存在值段、eErrCode 错误码（E_DL_StrSplitErr）；
 *                         返回值 = bValid 拆分有效标志（TRUE = sKey/sValue 可信）。
 * 边界     (Boundary)   : ① 属主边界：只拆单对，不遍历多对、不去引号、不做类型转换。
 *                         ② 缺分隔符 → 故障级 eNoSeparator，sKey=sIn 原样、sValue=''、返回 FALSE。
 *                         ③ 分隔符在首位（空键）→ 故障级 eEmptyKey，sKey=''、sValue=右段。
 *                         ④ 分隔符在末位（空值）→ 信息级 eEmptyValue，bHasValue=FALSE、返回 TRUE。
 *                         ⑤ MID 起算位置 = 分隔符位置 + 1，且仅当剩余长度 >= 1 时才取，
 *                         结构上无 0 长度 / 0 位置取值路径。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_StringCountChar` 分工：计数归那件、拆分归本件；
 *                         与 `FC_DL_StringCsvFieldEscape` 分工：CSV 转义归那件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + 2×STRING + 2×UINT +
 *                         本文件内定义 enum E_DL_StrSplitErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 分隔符缺失/空键域闸 + 取值位置下限保护 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 7）
 * 验收向量 (Acceptance) : ① sIn='Speed=1500', sSep='=' → sKey='Speed', sValue='1500',
 *                         uiKeyLen=5, uiValueLen=4, bHasValue=TRUE, eOk, TRUE；
 *                         ② sIn='Speed1450', sSep='=' → bFound 无效：返回 FALSE, eNoSeparator, sValue=''；
 *                         ③ sIn='=1500' → 返回 FALSE, eEmptyKey, sKey='';
 *                         ④ sIn='Speed=' → sKey='Speed', sValue='', bHasValue=FALSE,
 *                         返回 TRUE, eEmptyValue；
 *                         ⑤ sIn='A=B=C' → sKey='A', sValue='B=C'（只按首个分隔符切分）；
 *                         ⑥ sIn='', sSep='=' → 返回 FALSE, eNoSeparator。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StrSplitErr（key=value 拆分错误码，归属 DL_Base，与本件同文件，全库唯一属主）
 * 分级: eEmptyValue 为信息级（返回 TRUE）；eNoSeparator / eEmptyKey 为故障级（返回 FALSE）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_StrSplitErr :
(
    eOk          := 0,   // 信息级：键值均非空，拆分完成 / Info: both key and value non-empty
    eEmptyValue  := 1,   // 信息级：值段为空（置空语义） / Info: empty value section
    eNoSeparator := 2,   // 故障级：未找到分隔符 / Fault: separator not found
    eEmptyKey    := 3    // 故障级：分隔符在首位，键为空 / Fault: separator at head, empty key
);
END_TYPE

FUNCTION FC_DL_StringSplitPair : BOOL
VAR_INPUT
    sIn  : STRING(255);   // 待拆分字符串 [-] / String to split
    sSep : STRING(255);   // 分隔符（空串回落 '='） [-] / Separator, empty falls back to '='
END_VAR
VAR_OUTPUT
    sKey       : STRING(255); // 键段 [-] / Key section
    sValue     : STRING(255); // 值段 [-] / Value section
    uiKeyLen   : UINT;        // 键字符数 [字符] / Key character count [chars]
    uiValueLen : UINT;        // 值字符数 [字符] / Value character count [chars]
    bHasValue  : BOOL;        // 是否存在值段 [-] / Whether value section exists
    eErrCode   : E_DL_StrSplitErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _sSepUse  : STRING(255);  // 生效分隔符 [-] / Effective separator
    _udLen    : UDINT;        // 输入字符数（钳位后） [字符] / Input length after clamping [chars]
    _udPos    : UDINT;        // 分隔符位置（1 基，0 = 未找到） [-] / Separator position, 0 means not found
    _udRemain : UDINT;        // 分隔符右侧剩余字符数 [字符] / Remaining characters after separator [chars]
    _udStart  : UDINT;        // 值段起算位置（1 基） [-] / Value section start position, 1-based
END_VAR
VAR CONSTANT
    DL_SSP_SEP_DFLT : STRING(255) := '=';   // 默认分隔符 [-] / Default separator
    DL_SSP_LEN_MAX  : UINT := 255;          // 缓冲上限（STRING(255) 契约） [字符] / Buffer ceiling [chars]
    DL_SSP_START    : UDINT := 1;           // 字符串起始位置（IEC 1 基） [-] / String start position, 1-based
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_StringSplitPair := FALSE;                    // 返回值预置无效 / Return preset invalid
sKey       := '';                                  // 键哨兵空串 / Key sentinel
sValue     := '';                                  // 值哨兵空串 / Value sentinel
uiKeyLen   := 0;                                   // 键长哨兵 0 / Key length sentinel
uiValueLen := 0;                                   // 值长哨兵 0 / Value length sentinel
bHasValue  := FALSE;                               // 值段存在性预置无 / Value presence preset false
eErrCode   := E_DL_StrSplitErr.eNoSeparator;       // 预置最严码 / Preset strictest code

(* —— 段 1：分隔符归一（空串回落默认 '='） —— *)
IF LEN(sSep) = 0 THEN
    _sSepUse := DL_SSP_SEP_DFLT;                   // 回落默认分隔符 / Fall back to default separator
ELSE
    _sSepUse := sSep;                              // 使用调用方给定分隔符 / Use caller-supplied separator
END_IF

(* —— 段 2：输入长度实测与上域钳位 —— *)
_udLen := LEN(sIn);                                // 输入字符数 / Input length
IF _udLen > UINT_TO_UDINT(DL_SSP_LEN_MAX) THEN
    _udLen := UINT_TO_UDINT(DL_SSP_LEN_MAX);       // 超上限钳位 / Clamp to ceiling
END_IF

(* —— 段 3：定位首个分隔符（FIND 返回 0 表示未找到） —— *)
_udPos := FIND(sIn, _sSepUse);                     // 首个分隔符位置（1 基） / First separator position, 1-based

(* —— 段 4：缺分隔符早退（故障级：整体原样回键，值置空） —— *)
IF _udPos = 0 THEN
    sKey     := sIn;                               // 原样回键便于调用方诊断 / Echo input to key for diagnosis
    uiKeyLen := UDINT_TO_UINT(LEN(sKey));          // 键长实测 / Measured key length
    sValue   := '';                                // 值置空 / Value cleared
    eErrCode := E_DL_StrSplitErr.eNoSeparator;     // 故障级码 / Fault-level code
    RETURN;                                        // 返回 FALSE 保持 / Keep return FALSE
END_IF

(* —— 段 5：空键闸（分隔符在首位） —— *)
IF _udPos = DL_SSP_START THEN
    sKey     := '';                                // 键为空 / Empty key
    _udRemain := _udLen - _udPos;                  // 右侧剩余长度 / Remaining length on the right
    IF _udRemain >= DL_SSP_START THEN
        sValue     := MID(sIn, _udRemain, _udPos + DL_SSP_START);  // 取分隔符之后全部字符 / Take all after separator
        uiValueLen := UDINT_TO_UINT(_udRemain);
        bHasValue  := TRUE;
    END_IF
    eErrCode := E_DL_StrSplitErr.eEmptyKey;        // 故障级码 / Fault-level code
    RETURN;                                        // 返回 FALSE 保持 / Keep return FALSE
END_IF

(* —— 段 6：键段提取（位置 1 起，长度 = 分隔符位置 - 1 >= 1） —— *)
sKey     := MID(sIn, _udPos - DL_SSP_START, DL_SSP_START);   // 分隔符左侧 / Left of separator
uiKeyLen := UDINT_TO_UINT(LEN(sKey));              // 键长实测 / Measured key length

(* —— 段 7：值段提取（起算位置 = 分隔符位置 + 1，仅剩余 >= 1 时取） —— *)
_udRemain := _udLen - _udPos;                      // 右侧剩余长度 / Remaining length on the right
IF _udRemain >= DL_SSP_START THEN
    _udStart   := _udPos + DL_SSP_START;           // 值段起算位置 / Value start position
    sValue     := MID(sIn, _udRemain, _udStart);   // 取右侧全部字符 / Take all characters on the right
    uiValueLen := UDINT_TO_UINT(LEN(sValue));      // 值长实测 / Measured value length
    bHasValue  := TRUE;                            // 存在值段 / Value section exists
    eErrCode   := E_DL_StrSplitErr.eOk;            // 信息级成功 / Info success
ELSE
    sValue     := '';                              // 分隔符在末位：值段为空 / Separator at tail: empty value
    uiValueLen := 0;
    bHasValue  := FALSE;
    eErrCode   := E_DL_StrSplitErr.eEmptyValue;    // 信息级：置空语义 / Info: clear semantics
END_IF

(* —— 段 8：键长复检（键不得为空，否则判内部不一致） —— *)
IF uiKeyLen = 0 THEN
    sKey     := '';                                // 回哨兵 / Back to sentinel
    sValue   := '';
    eErrCode := E_DL_StrSplitErr.eEmptyKey;        // 故障级码 / Fault-level code
    RETURN;
END_IF

FC_DL_StringSplitPair := TRUE;                     // 拆分有效 / Split valid

END_FUNCTION
