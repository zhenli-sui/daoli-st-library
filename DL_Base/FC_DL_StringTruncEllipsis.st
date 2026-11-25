(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringTruncEllipsis
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准字符串九函数（LEN / MID / CONCAT），零厂商私有库
 * 功能描述 (Function)   : 超长截断并补省略标记（HMI 单行显示 / 报警摘要压缩）。
 *                         sIn 长度不超过 uiMaxLen 时原样返回；超长时保留前
 *                         (uiMaxLen - LEN(sMark)) 个字符并追加省略标记，最终长度
 *                         恒等于 uiMaxLen（标记有余量时）；标记本身已占满目标长度时
 *                         退化为纯截断（无标记空间）并回执 eTruncNoMark。
 *                         返回实际写入字符数 uiOutLen，供调用方做定宽对齐。
 * 接口     (Interface)  : 输入 sIn 原始字符串 [-]、uiMaxLen 目标最大长度（含标记）[字符]、
 *                         sMark 省略标记（空串则纯截断）[-]；
 *                         输出 sOut 结果字符串、uiOutLen 实际字符数 [字符]、
 *                         bTruncated 截断回执、eErrCode 错误码（E_DL_StrTruncErr）；
 *                         返回值 = bValid 输出可信标志（TRUE = sOut 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做截断 + 单标记追加，不做补位、不剔除空白。
 *                         ② uiMaxLen 合法域 1..255；> 255 钳位至 255 并置 eClampLen；
 *                         < 1 判故障级 eInvalidParam（无法产出有效结果）。
 *                         ③ 标记长度 >= uiMaxLen 时无标记余量，退化为 MID(sIn,uiMaxLen,1)
 *                         纯截断，回执 eTruncNoMark（信息级）。
 *                         ④ 全索引 1 基，截断起算位置恒 >= 1（keep >= 1 由分支保证）。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_StringPadLeftZeros` 分工：补位归那件、截断归本件，
 *                         两件互不调用；与 `FC_DL_StringRepeat` 无交集。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + STRING + UINT +
 *                         本文件内定义 enum E_DL_StrTruncErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 长度域闸 + 双侧钳位 + 起算位置下限保证 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 2）
 * 验收向量 (Acceptance) : ① sIn='ABCDEFGH'（8 字符）, uiMaxLen=6, sMark='...' →
 *                         keep=3 → sOut='ABC...'（6 字符）, uiOutLen=6, bTruncated=TRUE, eOk；
 *                         ② sIn='ABC', uiMaxLen=6 → sOut='ABC'（原样）, uiOutLen=3,
 *                         bTruncated=FALSE, eOk；
 *                         ③ sIn='ABCDEFGH', uiMaxLen=3, sMark='...' → 标记占满 →
 *                         sOut='ABC', uiOutLen=3, bTruncated=TRUE, eTruncNoMark；
 *                         ④ uiMaxLen=0 → 返回 FALSE, sOut='', eInvalidParam。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StrTruncErr（截断错误码，归属 DL_Base，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StrTruncErr :
(
    eOk           := 0,   // 信息级：标记有余量，已按目标长度截断 / Info: truncated to target length with mark
    eTruncNoMark  := 1,   // 信息级：标记无余量，退化为纯截断 / Info: no room for mark, plain truncation
    eClampLen     := 2,   // 信息级：目标长度超缓冲上限已钳位 / Info: target length clamped to buffer ceiling
    eInvalidParam := 3    // 故障级：目标长度小于 1，无法产出有效结果 / Fault: target length below 1
);
END_TYPE

FUNCTION FC_DL_StringTruncEllipsis : BOOL
VAR_INPUT
    sIn      : STRING(255);   // 原始字符串 [-] / Raw input string
    uiMaxLen : UINT;          // 目标最大长度（含省略标记），合法域 1..255 [字符] / Target max length including mark, domain 1..255 [chars]
    sMark    : STRING(255);   // 省略标记（空串则退化为纯截断） [-] / Ellipsis mark, empty means plain truncation
END_VAR
VAR_OUTPUT
    sOut       : STRING(255); // 截断结果字符串 [-] / Truncated result string
    uiOutLen   : UINT;        // 实际写入字符数 [字符] / Actual written character count [chars]
    bTruncated : BOOL;        // 截断回执（信息级） [-] / Truncation receipt, info level
    eErrCode   : E_DL_StrTruncErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _udInLen  : UDINT;        // 输入字符数（LEN 原生宽度） [字符] / Input length in native LEN width [chars]
    _udMarkLen: UDINT;        // 标记字符数 [字符] / Mark length [chars]
    _udKeep   : UDINT;        // 需保留的正文前缀字符数 [字符] / Number of leading text characters kept [chars]
    _udCopy   : UDINT;        // 实际拷贝字符数（钳位后） [字符] / Actual copied characters after clamping [chars]
END_VAR
VAR CONSTANT
    DL_STE_LEN_MAX  : UINT := 255;   // 缓冲上限（STRING(255) 契约） [字符] / Buffer ceiling per STRING(255) [chars]
    DL_STE_LEN_MIN  : UINT := 1;     // 目标长度下限 [字符] / Target length lower bound [chars]
    DL_STE_START    : UDINT := 1;    // 字符串起始位置（IEC 1 基） [-] / String start position, IEC 1-based
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_StringTruncEllipsis := FALSE;               // 返回值预置无效 / Return preset invalid
sOut       := '';                                  // 结果哨兵空串 / Result sentinel
uiOutLen   := 0;                                   // 长度哨兵 0 / Length sentinel
bTruncated := FALSE;                               // 截断回执预置无 / Truncation receipt preset false
eErrCode   := E_DL_StrTruncErr.eInvalidParam;      // 预置最严码 / Preset strictest code

(* —— 段 1：目标长度下域闸 —— *)
IF uiMaxLen < DL_STE_LEN_MIN THEN
    RETURN;                                        // 目标长度非法：保持故障码与哨兵 / Illegal target length
END_IF

(* —— 段 2：目标长度上域钳位（缓冲可表性反算） —— *)
IF uiMaxLen > DL_STE_LEN_MAX THEN
    uiMaxLen := DL_STE_LEN_MAX;                    // 钳位至缓冲上限 / Clamp to buffer ceiling
    eErrCode := E_DL_StrTruncErr.eClampLen;        // 信息级钳位码 / Info clamp code
END_IF

(* —— 段 3：实测长度（标准函数显式收窄，1 基口径） —— *)
_udInLen   := LEN(sIn);                            // 输入字符数 / Input length
_udMarkLen := LEN(sMark);                          // 标记字符数 / Mark length

(* —— 段 4：未超长：原样返回（早退，避免任何改写） —— *)
IF _udInLen <= UINT_TO_UDINT(uiMaxLen) THEN
    sOut       := sIn;                             // 原样返回 / Return as-is
    uiOutLen   := UDINT_TO_UINT(_udInLen);         // 实际长度 / Actual length
    bTruncated := FALSE;                           // 未截断 / Not truncated
    IF eErrCode <> E_DL_StrTruncErr.eClampLen THEN
        eErrCode := E_DL_StrTruncErr.eOk;          // 保留钳位码优先 / Keep clamp code if present
    END_IF
    FC_DL_StringTruncEllipsis := TRUE;             // 结果可信 / Result trustworthy
    RETURN;
END_IF

(* —— 段 5：标记余量判定（标记占满目标长度 → 退化为纯截断） —— *)
IF _udMarkLen >= UINT_TO_UDINT(uiMaxLen) THEN
    _udCopy := UINT_TO_UDINT(uiMaxLen);            // 全部长度用于正文 / All length spent on text
    sOut    := MID(sIn, _udCopy, DL_STE_START);    // 纯截断，无标记 / Plain truncation without mark
    bTruncated := TRUE;
    eErrCode := E_DL_StrTruncErr.eTruncNoMark;     // 信息级：无标记余量 / Info: no room for mark
ELSE
    _udKeep := UINT_TO_UDINT(uiMaxLen) - _udMarkLen;   // 正文保留数 = 目标 - 标记 / Text kept = target - mark
    IF _udKeep < DL_STE_START THEN
        _udKeep := DL_STE_START;                   // 起算位置下限保护（>=1） / Start position lower bound
    END_IF
    sOut    := CONCAT(MID(sIn, _udKeep, DL_STE_START), sMark);  // 正文前缀 + 标记 / Text prefix plus mark
    bTruncated := TRUE;
    eErrCode := E_DL_StrTruncErr.eOk;              // 信息级成功 / Info success
END_IF

(* —— 段 6：结果复检（长度不得超过目标；超限回哨兵） —— *)
uiOutLen := UDINT_TO_UINT(LEN(sOut));              // 实测结果长度 / Measured result length
IF uiOutLen > uiMaxLen THEN
    sOut     := '';                                // 超限回哨兵 / Over-limit to sentinel
    uiOutLen := 0;
    eErrCode := E_DL_StrTruncErr.eInvalidParam;    // 故障级码 / Fault-level code
    RETURN;                                        // 返回 FALSE 保持 / Keep return FALSE
END_IF

FC_DL_StringTruncEllipsis := TRUE;                 // 截断有效 / Truncation valid

END_FUNCTION
