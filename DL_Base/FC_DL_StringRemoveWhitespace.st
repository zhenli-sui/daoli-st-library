(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringRemoveWhitespace
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准字符串九函数（LEN / MID / CONCAT / FIND），零厂商私有库
 * 功能描述 (Function)   : 剔除全部空白字符（空格 0x20 / 水平制表符 0x09），压缩 HMI 报文
 *                         与条码内容（上位机常带尾随空格或制表分隔，落盘前必须净化）。
 *                         逐字符扫描，命中空白则跳过，否则追加到输出缓冲。
 *                         空白识别用字符集常量 + FIND(集合, 单字符) > 0 判定：
 *                         集合常量内含一个字面量 TAB 字符（源码直接嵌入 0x09，
 *                         不经平台转义解析，跨平台语义一致）。
 * 接口     (Interface)  : 输入 sIn 原始字符串 [-]；
 *                         输出 sOut 净化结果、uiOutLen 结果字符数 [字符]、
 *                         uiRemoved 被剔除的空白字符数 [字符]、
 *                         eErrCode 错误码（E_DL_StrWsErr）；
 *                         返回值 = bValid 净化可信标志（TRUE = sOut 可信）。
 * 边界     (Boundary)   : ① 属主边界：只剔除空格与 TAB；CR/LF 不剔除（属协议帧结构，
 *                         由 CSV 转义件负责加引号，剔除会破坏报文语义）。
 *                         ② 长度守恒校验：LEN(sIn) = uiOutLen + uiRemoved，不守恒判故障级
 *                         eInternal 并回哨兵。
 *                         ③ 全空白输入 → 输出空串、uiOutLen=0、uiRemoved=LEN(sIn)、eOk（合法）。
 *                         ④ 扫描上界取实测长度（<=255），严格有界；全索引 1 基。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_StringPadLeftZeros` 分工：本件只管剔除，补位归那件；
 *                         与 `FC_DL_StringIsNumeric` 分工：净化后再做数值判定。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + STRING + 2×UINT +
 *                         本文件内定义 enum E_DL_StrWsErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 长度守恒复检 + 扫描上界钳位 + 字符集归类（无字符码强转） ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 6）
 * 验收向量 (Acceptance) : ① sIn=' A B '(5 字符) → sOut='AB', uiOutLen=2, uiRemoved=3, eOk, TRUE；
 *                         ② sIn='ABC' → sOut='ABC', uiOutLen=3, uiRemoved=0, eOk；
 *                         ③ sIn='   ' → sOut='', uiOutLen=0, uiRemoved=3, eOk；
 *                         ④ sIn='' → sOut='', uiOutLen=0, uiRemoved=0, eOk。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StrWsErr（空白剔除错误码，归属 DL_Base，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StrWsErr :
(
    eOk       := 0,   // 信息级：剔除完成 / Info: removal completed
    eInternal := 9    // 故障级：长度守恒校验失败，结果不可信 / Fault: length conservation failed, result untrustworthy
);
END_TYPE

FUNCTION FC_DL_StringRemoveWhitespace : BOOL
VAR_INPUT
    sIn : STRING(255);   // 原始字符串 [-] / Raw input string
END_VAR
VAR_OUTPUT
    sOut      : STRING(255);   // 净化结果 [-] / Sanitized result
    uiOutLen  : UINT;          // 结果字符数 [字符] / Result character count [chars]
    uiRemoved : UINT;          // 被剔除的空白字符数 [字符] / Removed whitespace character count [chars]
    eErrCode  : E_DL_StrWsErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _udLen   : UDINT;        // 输入字符数（钳位后） [字符] / Input length after clamping [chars]
    _udI     : UDINT;        // 扫描位置（1 基） [-] / Scan position, 1-based
    _sCur    : STRING(255);  // 当前单字符 [-] / Current single character
    _bSkip   : BOOL;         // 当前字符是否空白 [-] / Whether current character is whitespace
    _uiDrop  : UINT;         // 剔除累加器 [字符] / Removal accumulator [chars]
END_VAR
VAR CONSTANT
    (* 空白字符集合：首个字符为空格 0x20，第二个字符为字面量 TAB 0x09（直接嵌入） *)
    (* Whitespace set: first is space 0x20, second is a literal TAB 0x09 embedded directly *)
    DL_SWS_WS_SET  : STRING(255) := '	 ';   // 空白字符集（TAB + 空格） [-] / Whitespace set, TAB plus space
    DL_SWS_LEN_MAX : UINT := 255;           // 缓冲上限（STRING(255) 契约） [字符] / Buffer ceiling [chars]
    DL_SWS_START   : UDINT := 1;            // 字符串起始位置（IEC 1 基） [-] / String start position, 1-based
    DL_SWS_ONE_LEN : UDINT := 1;            // 单字符长度常量 [字符] / Single character length constant
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_StringRemoveWhitespace := FALSE;             // 返回值预置不可信 / Return preset untrustworthy
sOut      := '';                                   // 结果哨兵空串 / Result sentinel
uiOutLen  := 0;                                    // 长度哨兵 0 / Length sentinel
uiRemoved := 0;                                    // 剔除哨兵 0 / Removal sentinel
eErrCode  := E_DL_StrWsErr.eInternal;              // 预置最严码 / Preset strictest code

(* —— 段 1：长度实测与上域钳位（缓冲可表性反算） —— *)
_udLen := LEN(sIn);                                // 输入字符数 / Input length
IF _udLen > UINT_TO_UDINT(DL_SWS_LEN_MAX) THEN
    _udLen := UINT_TO_UDINT(DL_SWS_LEN_MAX);       // 超上限钳位 / Clamp to ceiling
END_IF

(* —— 段 2：空串早退（合法零结果） —— *)
IF _udLen = 0 THEN
    eErrCode := E_DL_StrWsErr.eOk;                 // 信息级成功 / Info success
    FC_DL_StringRemoveWhitespace := TRUE;
    RETURN;
END_IF

(* —— 段 3：逐字符扫描与选择性追加 —— *)
_uiDrop := 0;                                      // 剔除累加器清零 / Clear removal accumulator
_udI    := DL_SWS_START;                           // 起算位置 1 / Start at position one
sOut    := '';                                     // 输出缓冲显式清空 / Explicitly clear output buffer
WHILE _udI <= _udLen DO
    _sCur  := MID(sIn, DL_SWS_ONE_LEN, _udI);      // 取第 i 个字符（1 基） / Take i-th character, 1-based
    _bSkip := (FIND(DL_SWS_WS_SET, _sCur) > 0);    // 命中空白集合即跳过 / Skip when hit whitespace set
    IF _bSkip THEN
        _uiDrop := _uiDrop + 1;                    // 剔除累加 / Accumulate removal
    ELSE
        sOut := CONCAT(sOut, _sCur);               // 非空白追加 / Append non-whitespace character
    END_IF
    _udI := _udI + 1;                              // 位置步进 / Advance position
END_WHILE

(* —— 段 4：长度守恒复检（输入长度 = 保留 + 剔除） —— *)
uiOutLen  := UDINT_TO_UINT(LEN(sOut));             // 结果字符数 / Result length
uiRemoved := _uiDrop;                              // 剔除字符数 / Removed count
IF (UDINT_TO_UINT(_udLen) <> (uiOutLen + uiRemoved)) THEN
    sOut      := '';                               // 守恒失败回哨兵 / Conservation failed: sentinel
    uiOutLen  := 0;
    uiRemoved := 0;
    eErrCode  := E_DL_StrWsErr.eInternal;          // 故障级码 / Fault-level code
    RETURN;                                        // 返回 FALSE 保持 / Keep return FALSE
END_IF

(* —— 段 5：成功出口 —— *)
eErrCode := E_DL_StrWsErr.eOk;                     // 信息级成功 / Info success
FC_DL_StringRemoveWhitespace := TRUE;              // 净化可信 / Sanitization trustworthy

END_FUNCTION
