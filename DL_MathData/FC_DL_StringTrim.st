(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringTrim
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library 的标准串函数（LEN / MID）
 * 功能描述 (Function)   : 去除字符串首尾空白字符。空白集恰为四类：空格 / 制表 / 回车 /
 *                         换行，中间位置的空白原样保留（这是与"删除全部空白"的本质区别）。
 *                         双向扫描：先从头部找首个非空白位置，再从尾部找末个非空白位置，
 *                         最后一次性截取中间段，避免逐字符拼接带来的长度与性能问题。
 *                         全空白或空串输入返回空串并如实报告去除数量——这是合法结果而非错误。
 *                         扫码枪、CSV 报文、视觉结果字符串入库比对前的标准清洗步。
 * 开源溯源 (Origin)     : 原创实现。首尾裁剪为公开经典字符串处理需求；
 *                         空白字符集与位置口径依据 IEC 61131-3 标准串函数定义，
 *                         未复制任何源码。
 * 本文件内含       : FC    FC_DL_StringTrim（单 POU，无配套类型）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: LEN / MID
 * 红线自检 (Redline)    : R1 ✓ 禁用全局存储与物理寻址 ｜ R2 ✓ 无地址直写
 *                         R3 ✓ 仅标准串函数 ｜ R4 ✓ 双循环防死锁计数 + 截取长度结构性保证
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（纯函数，无状态机）
 *                         R7 N/A（无定时器/边沿实例）｜ R8 ✓ 长度上限与循环上限全常量化
 *
 * 【长度声明警告 / Explicit length warning（边界 B1）】
 *   输入与返回一律显式声明字符串最大长度。省略长度时平台默认上限远小于 255，
 *   超长报文会被静默截断，而截断点在运行期无任何迹象——这是串口设备集成的高频事故源。
 *
 * 【字符集边界 / Character-set boundary（边界 B2）】
 *   仅处理上述四类单字节空白。全角空格等多字节字符不属本函数职责，
 *   应在调用方做编码归一后再进入本函数。
 *
 * 【位置口径 / Position convention（边界 B3）】
 *   全程按 IEC 标准串函数口径，位置从 1 开始计数，不是从 0。
 *
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 第二轮 · Level 0 批次 A）
 *============================================================================*)
FUNCTION FC_DL_StringTrim : STRING(255)
VAR_INPUT
    sIn      : STRING(255);   // 原始字符串，最大 255 字符 / Source string, 255 characters max
END_VAR
VAR_OUTPUT
    bValid   : BOOL;          // 处理完整标志，FALSE = 循环保护触发 / Complete flag, FALSE = the loop guard tripped
    uTrimmed : UINT;          // 被去除的空白字符总数 [个] / Total whitespace characters removed [count]
    uErrorId : UDINT;         // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    nLen     : INT;           // 输入有效长度 [字符] / Effective input length [characters]
    nStart   : INT;           // 首个非空白位置（1 起始） / First non-blank position, 1-based
    nEnd     : INT;           // 末个非空白位置（1 起始） / Last non-blank position, 1-based
    nKept    : INT;           // 保留段长度 [字符] / Length of the retained segment [characters]
    sChar    : STRING(1);     // 当前检查字符 / Current character under check
    bRun     : BOOL;          // 循环继续标志 / Loop continuation flag
    nGuard   : DINT;          // 循环防死锁计数器 [次] / Loop deadlock guard counter [count]
END_VAR
VAR CONSTANT
    DL_STR_MAX_LEN  : INT  := 255;    // 串长度上限 [字符]，与类型声明一致 / Max length [characters], must match the type
    DL_STR_LOOP_MAX : DINT := 255;    // 循环防死锁上限 [次] / Loop guard limit [count]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜结果预置（P-01 范式）：先给空串与成功标志，异常路径也必有确定返回值
 *      Safe preset: an empty result and a success flag, every path returns something
 *-----------------------------------------------------------------------------*)
FC_DL_StringTrim := '';
bValid   := TRUE;
uErrorId := 16#0000_0000;
uTrimmed := UINT#0;
nKept    := 0;

(*------------------------------------------------------------------------------
 * 段 2｜有效长度（边界 B1）：先钳位再用，后续所有位置判断都基于这一个值
 *      Effective length: clamped once and reused by every position test
 *-----------------------------------------------------------------------------*)
nLen := LEN(sIn);

IF nLen > DL_STR_MAX_LEN THEN
    nLen := DL_STR_MAX_LEN;
ELSIF nLen < 0 THEN
    nLen := 0;
END_IF

nStart := 1;
nEnd   := nLen;

(*------------------------------------------------------------------------------
 * 段 3｜头部扫描（边界 B4）：四类空白逐一比较，循环带防死锁计数
 *      Head scan: four whitespace classes compared one by one, with a loop guard
 *      全空白时 nStart 会越过 nLen，由段 5 的区间判据自然得到空串结果
 *      On an all-blank input nStart passes nLen, stage 5 then yields an empty result
 *-----------------------------------------------------------------------------*)
bRun   := (nLen > 0);
nGuard := 0;

WHILE bRun DO

    sChar := MID(sIn, 1, nStart);

    IF (sChar = ' ') OR (sChar = '$09') OR (sChar = '$0D') OR (sChar = '$0A') THEN
        nStart := nStart + 1;
        IF nStart > nLen THEN
            bRun := FALSE;
        END_IF
    ELSE
        bRun := FALSE;
    END_IF

    (* 防死锁：位置必然单调递增，仍设上限兜底，防止平台串函数异常导致位置不前进 *)
    (* Deadlock guard: the position always advances, the cap is a second line of defence *)
    nGuard := nGuard + 1;
    IF nGuard > DL_STR_LOOP_MAX THEN
        bRun     := FALSE;
        bValid   := FALSE;
        uErrorId := 16#0001_0004;
    END_IF

END_WHILE;

(*------------------------------------------------------------------------------
 * 段 4｜尾部扫描（边界 B4）：从末位向前，遇到非空白即停
 *      Tail scan: walk backwards and stop at the first non-blank
 *-----------------------------------------------------------------------------*)
IF (nStart <= nLen) AND (nEnd >= nStart) THEN

    bRun   := TRUE;
    nGuard := 0;

    WHILE bRun DO

        sChar := MID(sIn, 1, nEnd);

        IF (sChar = ' ') OR (sChar = '$09') OR (sChar = '$0D') OR (sChar = '$0A') THEN
            nEnd := nEnd - 1;
            IF nEnd < nStart THEN
                bRun := FALSE;
            END_IF
        ELSE
            bRun := FALSE;
        END_IF

        nGuard := nGuard + 1;
        IF nGuard > DL_STR_LOOP_MAX THEN
            bRun     := FALSE;
            bValid   := FALSE;
            uErrorId := 16#0001_0004;
        END_IF

    END_WHILE;

END_IF

(*------------------------------------------------------------------------------
 * 段 5｜截取（边界 B5/B6）：区间判据成立才调 MID，长度为 0 直接返回空串
 *      Extraction: MID is called only when the interval is valid, zero length returns empty
 *      区间判据是结构性保证（头部扫描保证 nStart 是首个非空白、尾部扫描保证 nEnd
 *      是末个非空白），此处再断言一次属于双保险，不承担主要防御职责
 *      The interval is structurally guaranteed; this assertion is a second line of defence
 *-----------------------------------------------------------------------------*)
IF (nStart >= 1) AND (nStart <= nLen) AND (nEnd >= nStart) AND (nEnd <= nLen) THEN

    nKept := nEnd - nStart + 1;

    IF nKept > 0 THEN
        FC_DL_StringTrim := MID(sIn, nKept, nStart);
    END_IF

ELSE
    (* 空串或全空白：合法的空结果，不是错误（边界 B5） *)
    (* Empty or all-blank input: a legal empty result, not an error *)
    nKept := 0;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜去除计数：原始有效长度减去保留长度，覆盖全部路径且不会为负
 *      Removed count: original length minus retained length, never negative
 *-----------------------------------------------------------------------------*)
IF nKept < 0 THEN
    nKept := 0;
END_IF

IF nLen >= nKept THEN
    uTrimmed := INT_TO_UINT(nLen - nKept);
ELSE
    uTrimmed := UINT#0;
END_IF
END_FUNCTION
