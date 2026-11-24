(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringRepeat
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准字符串九函数（LEN / CONCAT），零厂商私有库
 * 功能描述 (Function)   : 按次数重复拼接（分隔线 "-----"、占位符 "<><><>"、缩进填充）。
 *                         先算缓冲可容最大重复次数 = 255 DIV LEN(sIn)（分母已判零，
 *                         结构性无除零），再与请求次数比较：请求超限则按最大可容次数
 *                         截断并置 bTruncated / eTruncated（信息级，结果仍可信）；
 *                         请求次数为 0 或输入空串时输出空串。
 * 接口     (Interface)  : 输入 sIn 基元字符串 [-]、uiCount 请求重复次数 [次]；
 *                         输出 sOut 拼接结果、uiOutLen 结果字符数 [字符]、
 *                         uiApplied 实际生效次数 [次]、bTruncated 截断回执、
 *                         eErrCode 错误码（E_DL_StrRepErr）；
 *                         返回值 = bValid 拼接可信标志（TRUE = sOut 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做整串重复拼接，不做单字符补位（补位归
 *                         FC_DL_StringPadLeftZeros）、不做截断加标记（归 TruncEllipsis）。
 *                         ② 除零防御：先判 LEN(sIn)=0 并早退，后才做 255 DIV LEN(sIn)。
 *                         ③ 缓冲保护：结果长度恒 <= 255（生效次数 = 255 DIV 基元长度）。
 *                         ④ uiCount=0 → 输出空串、uiApplied=0、eOk（合法零次）。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_StringPadLeftZeros` 分工：定长补位归那件、
 *                         次数重复归本件；与 `FC_DL_StringTruncEllipsis` 无调用关系。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + STRING + 3×UINT +
 *                         本文件内定义 enum E_DL_StrRepErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除零前置判零 + 缓冲上限反算 + 循环次数有界 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 8）
 * 验收向量 (Acceptance) : ① sIn='AB', uiCount=3 → sOut='ABABAB', uiOutLen=6, uiApplied=3,
 *                         bTruncated=FALSE, eOk, TRUE；
 *                         ② sIn='AB', uiCount=0 → sOut='', uiOutLen=0, uiApplied=0, eOk, TRUE；
 *                         ③ sIn='', uiCount=5 → sOut='', uiOutLen=0, uiApplied=0, eOk, TRUE；
 *                         ④ sIn='X'（1 字符）, uiCount=300 → 生效 255 次，sOut 长度 255,
 *                         bTruncated=TRUE, eTruncated；
 *                         ⑤ sIn='AB', uiCount=200 → 255 DIV 2 = 127 → uiApplied=127,
 *                         长度 254, bTruncated=TRUE。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StrRepErr（重复拼接错误码，归属 DL_Base，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StrRepErr :
(
    eOk        := 0,   // 信息级：按请求次数完成 / Info: completed as requested
    eTruncated := 1    // 信息级：超缓冲上限已按最大可容次数截断 / Info: truncated to max fitting repeat count
);
END_TYPE

FUNCTION FC_DL_StringRepeat : BOOL
VAR_INPUT
    sIn     : STRING(255);   // 基元字符串 [-] / Unit string to repeat
    uiCount : UINT;          // 请求重复次数 [次] / Requested repeat count [times]
END_VAR
VAR_OUTPUT
    sOut       : STRING(255); // 拼接结果 [-] / Concatenated result
    uiOutLen   : UINT;        // 结果字符数 [字符] / Result character count [chars]
    uiApplied  : UINT;        // 实际生效次数 [次] / Applied repeat count [times]
    bTruncated : BOOL;        // 截断回执（信息级） [-] / Truncation receipt, info level
    eErrCode   : E_DL_StrRepErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _udUnitLen : UDINT;       // 基元字符数 [字符] / Unit string length [chars]
    _udMaxRep  : UDINT;       // 缓冲可容最大重复次数 [次] / Max fitting repeat count [times]
    _uiEff     : UINT;        // 生效重复次数 [次] / Effective repeat count [times]
    _uiLoop    : UINT;        // 循环计数器 [-] / Loop counter
END_VAR
VAR CONSTANT
    DL_SRE_LEN_MAX : UINT := 255;    // 缓冲上限（STRING(255) 契约） [字符] / Buffer ceiling [chars]
    DL_SRE_ONE_LEN : UDINT := 1;     // 单字符长度常量 [字符] / Single character length constant
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_StringRepeat := FALSE;                       // 返回值预置无效 / Return preset invalid
sOut       := '';                                  // 结果哨兵空串 / Result sentinel
uiOutLen   := 0;                                   // 长度哨兵 0 / Length sentinel
uiApplied  := 0;                                   // 生效次数哨兵 0 / Applied count sentinel
bTruncated := FALSE;                               // 截断回执预置无 / Truncation receipt preset false
eErrCode   := E_DL_StrRepErr.eTruncated;           // 预置最严码（本件仅信息级码） / Preset strictest code

(* —— 段 1：基元长度实测（除零防御前置：先判零后做除法） —— *)
_udUnitLen := LEN(sIn);                            // 基元字符数 / Unit length
IF _udUnitLen = 0 THEN
    eErrCode := E_DL_StrRepErr.eOk;                // 空基元合法（零结果） / Empty unit is legal, zero result
    FC_DL_StringRepeat := TRUE;                    // 结果可信 / Result trustworthy
    RETURN;                                        // 早退，彻底规避 255 DIV 0 / Early exit, avoids division by zero entirely
END_IF

(* —— 段 2：请求次数为零早退（合法零结果） —— *)
IF uiCount = 0 THEN
    eErrCode := E_DL_StrRepErr.eOk;                // 零次合法 / Zero repeats legal
    FC_DL_StringRepeat := TRUE;
    RETURN;
END_IF

(* —— 段 3：缓冲可容最大重复次数反算（分母已确非零） —— *)
_udMaxRep := UINT_TO_UDINT(DL_SRE_LEN_MAX) / _udUnitLen;  // 255 DIV 基元长度 / Integer division by unit length
IF _udMaxRep < DL_SRE_ONE_LEN THEN
    _udMaxRep := DL_SRE_ONE_LEN;                   // 基元本身已占满缓冲：至少一次 / Unit already fills buffer: at least once
END_IF

(* —— 段 4：请求次数与可容次数比较（超限则截断并回执） —— *)
IF UINT_TO_UDINT(uiCount) > _udMaxRep THEN
    _uiEff     := UDINT_TO_UINT(_udMaxRep);         // 收敛到最大可容次数 / Converge to max fitting count
    bTruncated := TRUE;                            // 截断回执 / Truncation receipt
    eErrCode   := E_DL_StrRepErr.eTruncated;       // 信息级截断码 / Info truncation code
ELSE
    _uiEff     := uiCount;                         // 按请求次数生效 / Apply requested count
    bTruncated := FALSE;
    eErrCode   := E_DL_StrRepErr.eOk;              // 信息级成功 / Info success
END_IF

(* —— 段 5：循环拼接（次数已收敛，循环严格有界） —— *)
sOut := '';                                        // 输出缓冲显式清空 / Explicitly clear output buffer
IF _uiEff > 0 THEN
    FOR _uiLoop := 1 TO _uiEff DO
        sOut := CONCAT(sOut, sIn);                 // 每次追加一个基元 / Append one unit per iteration
    END_FOR;
END_IF

(* —— 段 6：结果复检（长度 = 基元长度 × 生效次数，且不得超缓冲） —— *)
uiOutLen  := UDINT_TO_UINT(LEN(sOut));             // 实测结果长度 / Measured result length
uiApplied := _uiEff;                               // 导出生效次数 / Export applied count
IF uiOutLen > DL_SRE_LEN_MAX THEN
    sOut      := '';                               // 超缓冲回哨兵 / Over buffer: sentinel
    uiOutLen  := 0;
    uiApplied := 0;
    eErrCode  := E_DL_StrRepErr.eTruncated;        // 保持信息级码（本件无故障级码位） / Keep info-level code
    RETURN;
END_IF

FC_DL_StringRepeat := TRUE;                        // 拼接有效 / Concatenation valid

END_FUNCTION
