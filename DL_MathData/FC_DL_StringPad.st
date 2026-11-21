(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringPad
 * 溯源说明 (Provenance) : IEC 61131-3 标准语义的道莅防御性实现（零检索变体线）
 * 所属子库 (Sublibrary) : DL_MathData / StringOps
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），仅用标准字符串函数 LEN/CONCAT
 * 组件分类 (Category)   : 函数（TYPE E_DL_PadSide :
(
    eLeft   := 0, // 左填充 / Left padding
    eRight  := 1, // 右填充 / Right padding
    eCenter := 2  // 居中填充 / Center padding
);
END_TYPE

FUNCTION）· 字符串定长填充（无状态纯函数）
 * 功能一句话 (Summary)  : 左/右/居中填充至目标长度；越界显式截断并置标志。
 * 边界与安全 (Boundary) : ①目标长度大于 255 → 钳 255 并置 bTruncated；
 *                         ②源串超长按目标长度截断并置 bTruncated（禁静默回夹）；
 *                         ③填充字符取首字符，空串降级为空格并置信息码；
 *                         ④居中奇偶差一优先填左侧（规格验收向量 ③）；
 *                         ⑤非法枚举侧别按右填充防御降级（03C2 保留不赋值）；
 *                         ⑥纯函数：每个输出在全部路径（含提前返回）上赋值。
 * 错误码    : 16#0001_03C1 填充字符为空（已按空格降级）——信息级
 *             16#0001_03C2 保留禁用（不得挪用，本件零赋值）
 * 码位总账  : 16#0001_03C1 用 ｜ 16#0001_03C2 预留
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
FUNCTION FC_DL_StringPad : BOOL
VAR_INPUT
    sIn         : STRING; // 源字符串 / Source string
    sPadChar    : STRING; // 填充字符（取首字符，空则降级空格）/ Pad char (first char, empty degrades to space)
    nTargetLen  : UINT;   // 目标长度 0~255 / Target length 0 to 255
    eSide       : E_DL_PadSide; // 填充侧别：左/右/居中 / Pad side: left, right or center
END_VAR
VAR_OUTPUT
    sOut        : STRING; // 填充结果字符串 / Padded result string
    bTruncated  : BOOL;  // 发生截断（源超长或目标超界钳 255）/ Truncation occurred
    eErr        : UDINT;  // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR
    iTarget : INT; // 目标长度有效值（钳 255 后）/ Effective target length after clamp
    iSrcLen : INT; // 源串实际长度 / Actual source length
    iLeft   : INT; // 左侧填充字符数 / Left pad char count
    iRight  : INT; // 右侧填充字符数 / Right pad char count
    i       : INT; // 循环游标 / Loop cursor
    sPadOne : STRING; // 单个填充字符（首字符或降级空格）/ Single pad char
    sPadL   : STRING; // 左侧填充串 / Left pad string
    sPadR   : STRING; // 右侧填充串 / Right pad string
END_VAR

// ---------- 全路径赋值原则：先给输出安全缺省 ----------
sOut       := '';
bTruncated := FALSE;
eErr       := 0;
FC_DL_StringPad := TRUE; // 函数返回值：TRUE=已执行（防御缺省）/ Function result: TRUE = executed

// ---------- 目标长度钳位：超 255 显式截断标记 ----------
IF nTargetLen > 255 THEN
    iTarget    := 255;                        // 超界钳 255 / Clamp over-range to 255
    bTruncated := TRUE;                       // 显式置截断标志，禁静默回夹 / Explicit truncation flag
ELSE
    iTarget := UINT_TO_INT(nTargetLen);       // 合法目标长度 / Legal target length
END_IF

// ---------- 填充字符取首字符；空串降级为空格并置信息码 ----------
IF LEN(sPadChar) <= 0 THEN
    sPadOne := ' ';                           // 降级为空格 / Degrade to space
    eErr    := 16#0001_03C1;                  // 信息级：填充字符为空已降级 / info: empty pad char degraded
ELSE
    sPadOne := MID(sPadChar, 1, 1);           // 取首字符 / Take first char
END_IF

// ---------- 源串长度与超长截断 ----------
iSrcLen := LEN(sIn);
IF iSrcLen > iTarget THEN
    sOut       := LEFT(sIn, iTarget);         // 按目标长度截断 / Truncate to target
    bTruncated := TRUE;                       // 显式截断标志 / Explicit truncation flag
    RETURN;                                   // 提前返回路径：输出已全赋值 / Early return: outputs all assigned
END_IF

// ---------- 按侧别计算左右填充量 ----------
CASE eSide OF
    E_DL_PadSide.eLeft:                       // 左填充 / Left padding
        iLeft  := iTarget - iSrcLen;          // 全部填左侧 / All padding on the left
        iRight := 0;
    E_DL_PadSide.eRight:                      // 右填充 / Right padding
        iLeft  := 0;
        iRight := iTarget - iSrcLen;          // 全部填右侧 / All padding on the right
    E_DL_PadSide.eCenter:                     // 居中：奇偶差一填左侧 / Center: odd remainder goes left
        iLeft  := (iTarget - iSrcLen + 1) / 2; // 左侧含奇余 / Left side takes odd remainder
        iRight := (iTarget - iSrcLen) / 2;     // 右侧取偶商 / Right side takes even quotient
    ELSE                                      // 非法侧别防御降级为右填充 / Illegal side degrades to right
        iLeft  := 0;
        iRight := iTarget - iSrcLen;
END_CASE

// ---------- 逐字符构造填充串（标准 CONCAT，避免方言拼接符） ----------
sPadL := '';
FOR i := 1 TO iLeft DO
    sPadL := CONCAT(sPadL, sPadOne);          // 累积左侧填充 / Accumulate left padding
END_FOR
sPadR := '';
FOR i := 1 TO iRight DO
    sPadR := CONCAT(sPadR, sPadOne);          // 累积右侧填充 / Accumulate right padding
END_FOR

// ---------- 组装输出：左填充串 + 源串 + 右填充串 ----------
IF iLeft > 0 THEN
    sOut := CONCAT(sPadL, sIn);               // 先贴左填充 / Attach left padding first
ELSE
    sOut := sIn;                              // 无左填充直接用源串 / No left pad, use source
END_IF
IF iRight > 0 THEN
    sOut := CONCAT(sOut, sPadR);              // 再贴右填充 / Then attach right padding
END_IF

END_FUNCTION
