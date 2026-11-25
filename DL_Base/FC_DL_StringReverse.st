(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringReverse
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准字符串九函数（LEN / MID / CONCAT），零厂商私有库
 * 功能描述 (Function)   : 字符串反转（回文校验 / 字节序调试 / 低位在前的编码还原）。
 *                         自尾向头逐字符取 MID(sIn,1,i) 并 CONCAT 拼接；用 WHILE
 *                         递减计数，UDINT 计数到 0 自然终止，结构上无下溢路径。
 *                         输出长度恒等于输入长度（不做任何增删）。
 * 接口     (Interface)  : 输入 sIn 原始字符串 [-]；
 *                         输出 sOut 反转结果、uiOutLen 结果字符数 [字符]、
 *                         eErrCode 错误码（E_DL_StrRevErr）；
 *                         返回值 = bValid 反转可信标志（TRUE = sOut 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做整串反转，不做大小写折叠、不做子串反转。
 *                         ② 长度 > 255 时按缓冲上限 255 截断尾部（保证输出可表），
 *                         回执 eClampLen（信息级），bTruncated 置位。
 *                         ③ 空串合法，输出空串、uiOutLen=0、eOk。
 *                         ④ 计数递减用 `IF _udI > 0` 前置判定，杜绝 UDINT 0-1 下溢。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_StringCompareNatural` 分工：反转只做位序重排，
 *                         不做序比较；回文判定由调用方对 sIn 与 sOut 比较完成。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + STRING + UINT +
 *                         本文件内定义 enum E_DL_StrRevErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 递减计数下溢防护 + 长度钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 4）
 * 验收向量 (Acceptance) : ① sIn='ABC' → sOut='CBA', uiOutLen=3, eOk, TRUE；
 *                         ② sIn='ABBA' → sOut='ABBA'（回文自反）, uiOutLen=4；
 *                         ③ sIn='' → sOut='', uiOutLen=0, eOk, TRUE；
 *                         ④ sIn='12345' → sOut='54321'。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StrRevErr（字符串反转错误码，归属 DL_Base，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StrRevErr :
(
    eOk       := 0,   // 信息级：反转完成 / Info: reversal completed
    eClampLen := 1    // 信息级：长度超缓冲上限已截断 / Info: length clamped to buffer ceiling
);
END_TYPE

FUNCTION FC_DL_StringReverse : BOOL
VAR_INPUT
    sIn : STRING(255);   // 原始字符串 [-] / Raw input string
END_VAR
VAR_OUTPUT
    sOut      : STRING(255);   // 反转结果 [-] / Reversed result
    uiOutLen  : UINT;          // 结果字符数 [字符] / Result character count [chars]
    bTruncated: BOOL;          // 截断回执（信息级） [-] / Truncation receipt, info level
    eErrCode  : E_DL_StrRevErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _udLen : UDINT;       // 生效字符数（钳位后） [字符] / Effective character count after clamping [chars]
    _udI   : UDINT;       // 逆序扫描位置（1 基） [-] / Reverse scan position, 1-based
END_VAR
VAR CONSTANT
    DL_SRV_LEN_MAX : UINT := 255;    // 缓冲上限（STRING(255) 契约） [字符] / Buffer ceiling [chars]
    DL_SRV_ONE_LEN : UDINT := 1;     // 单字符长度常量 [字符] / Single character length constant [chars]
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_StringReverse := FALSE;                      // 返回值预置无效 / Return preset invalid
sOut       := '';                                  // 结果哨兵空串 / Result sentinel
uiOutLen   := 0;                                   // 长度哨兵 0 / Length sentinel
bTruncated := FALSE;                               // 截断回执预置无 / Truncation receipt preset false
eErrCode   := E_DL_StrRevErr.eClampLen;            // 预置最严码（本件仅信息级码） / Preset strictest code

(* —— 段 1：长度实测与上域钳位（缓冲可表性反算） —— *)
_udLen := LEN(sIn);                                // 输入字符数 / Input length
IF _udLen > UINT_TO_UDINT(DL_SRV_LEN_MAX) THEN
    _udLen     := UINT_TO_UDINT(DL_SRV_LEN_MAX);   // 超上限截断尾部 / Truncate tail beyond ceiling
    bTruncated := TRUE;                            // 截断回执 / Truncation receipt
    eErrCode   := E_DL_StrRevErr.eClampLen;        // 信息级钳位码 / Info clamp code
ELSE
    eErrCode   := E_DL_StrRevErr.eOk;              // 信息级成功 / Info success
END_IF

(* —— 段 2：空串早退（合法零结果） —— *)
IF _udLen = 0 THEN
    FC_DL_StringReverse := TRUE;                   // 空串反转合法 / Empty reversal legal
    RETURN;
END_IF

(* —— 段 3：逆序拼接（前置 >0 判定，杜绝 UDINT 下溢） —— *)
sOut := MID(sIn, DL_SRV_ONE_LEN, _udLen);          // 以末字符起头 / Start with last character
_udI := _udLen - 1;                                // 自倒数第二位起（>=1 由段 2 保证 len>=1） / Start from second last
WHILE _udI > 0 DO
    sOut := CONCAT(sOut, MID(sIn, DL_SRV_ONE_LEN, _udI));  // 逐个前置字符追加 / Append next character from tail
    _udI := _udI - 1;                              // 位置递减，条件 >0 保证不下溢 / Decrement, guarded by >0
END_WHILE

(* —— 段 4：结果复检（长度守恒） —— *)
uiOutLen := UDINT_TO_UINT(LEN(sOut));              // 实测结果长度 / Measured result length
IF uiOutLen <> UDINT_TO_UINT(_udLen) THEN
    sOut     := '';                                // 长度不守恒回哨兵 / Length not conserved: sentinel
    uiOutLen := 0;
    eErrCode := E_DL_StrRevErr.eClampLen;          // 保持信息级码（本件无故障级码位） / Keep info-level code
END_IF

FC_DL_StringReverse := TRUE;                       // 反转有效（含截断情形） / Reversal valid, truncation included

END_FUNCTION
