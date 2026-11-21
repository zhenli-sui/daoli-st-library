(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringReplaceAll
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library 标准串函数（LEN / FIND / LEFT / MID / CONCAT）
 * 功能描述 (Function)   : 定长字符串内「全部出现」的子串替换，一次调用给出替换次数、
 *                         结果串与截断标志。用于条码前缀规范化、报表模板占位符替换
 *                         （百分号包裹的批次号与日期占位符）、设备商旧机型代号批量改新代号。
 *                         现场手写 WHILE + FIND + DELETE + INSERT 的典型事故是「替换串里
 *                         含模式串」时缓冲自增长、永不退出扫描，本件用「替换后游标跳到
 *                         插入段之后」的推进律从算法层消灭该类死循环，并叠加次数上限与
 *                         守卫计数器两道闸。
 * 出口契约 (Exit)       : 函数返回值 = 实际替换次数（与出口 nReplaced 同值）；异常路径返回 0。
 *                         任何路径（含早退）sResult 均有确定内容，绝不返回未初始化串。
 * 开源溯源 (Origin)     : 来源标签 lgf-datahandling。许可证：LGF 为免费闭源发布，未取得源码，
 *                         不构成衍生作品。借鉴点仅为「Data Handling 组把 FIFO/LIFO、数组检索、
 *                         排序、字符串并列成数据操作族」的分类骨架，以及字符串族「定长缓冲 +
 *                         原地操作、不做动态分配」的参数域约定。
 *                         clean-room 独立实现：算法、切分策略、游标推进律、计数语义、错误码
 *                         全部自有，零代码行、零注释、零结构体复制。
 * 码位说明 (Codes)      : 信息级 16#0001_0130（模式串为空）/ 0131（达替换次数上限）/
 *                         0132（结果被长度上限截断）/ 0133（长度参数越界已钳位）。
 *                         共 4 码，全部落在 R12 计划第 1.2 节分配给本件的码段内，无段外码。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: LEN / FIND / LEFT / MID / CONCAT
 * 红线自检 (Redline)    : 1 ✓ 零全局变量表依赖、零外部变量声明、零物理地址
 *                         2 ✓ 纯 IEC 61131-3 跨平台语法，无指针、无厂商库
 *                         3 ✓ 模式空硬闸、数组与串长先判界、每轮回夹、双闸防死循环
 *                         4 ✓ 全变量中英双语同行注释
 *                         5 N/A 纯函数无状态机 ｜ 6 N/A 无定时器与边沿实例
 *                         7 ✓ END_FUNCTION 位于文件最后有效行
 * 规格偏离留档 (Deviation):
 *   D1 计划 3.6 节把 bValid 定义为「模式串非空且长度参数合法」。本实现多收一环：
 *      达替换次数上限（码 0131，结果不完整）时 bValid 亦为假。理由：bValid 在本库
 *      统一承载「结果可否直接采信」，不完整的替换结果采信即等于静默丢字段；
 *      完整性细粒度判据由调用方读 uErrorId 与 bTruncated 取得。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R12 · Level 0 DL_MathData 字符串族）
 *   2026-11-15  v1.0.1  终审定点修复 A-D01：拼接长度超串型上限（255）时原实现由
 *      LEFT 静默回夹，bTruncated 与 0132 永不置位（验收向量 V5 期望的截断标志恒假）；
 *      补「拼接长度预判」，超限即置 bTruncated 与 0132，杜绝静默丢字符
 *============================================================================*)
FUNCTION FC_DL_StringReplaceAll : INT
VAR_INPUT
    sSource      : STRING(255);          // 源串，最长 255 字符 / Source string, up to 255 characters
    sPattern     : STRING(32);           // 被替换子串，长度 0 视为非法 / Pattern to replace, empty is illegal
    sReplace     : STRING(64);           // 替换子串，允许为空（即删除） / Replacement, empty means delete
    nMaxReplace  : INT := 32;            // 替换次数上限 [次]，域 0~255，0 = 不限 / Replacement limit, zero means unlimited
    nMaxLen      : INT := 255;           // 结果串长度上限 [字符]，域 1~255 / Result length limit, 1..255
END_VAR
VAR_OUTPUT
    sResult      : STRING(255);          // 替换结果，超长时按 nMaxLen 截断 / Result, truncated to nMaxLen
    nReplaced    : INT;                  // 实际替换次数 [次] / Replacement count
    bTruncated   : BOOL;                 // 结果被长度上限截断 TRUE / Result was truncated
    uErrorId     : UDINT;                // 事件码，0 = 无事件 / Event code, zero means none
    bValid       : BOOL;                 // 模式串非空、长度参数未钳位且未达替换次数上限 = TRUE（结果可直接采信） / Pattern non-empty, lengths legal and the count limit not hit, the result may be trusted as is
END_VAR
VAR
    sBuf         : STRING(255);          // 工作缓冲，逐轮就地改写 / Working buffer, rewritten in place
    sHead         : STRING(255);         // 本次替换位置之前的头部片段 / Head fragment before the hit
    sTail        : STRING(255);          // 本次替换位置之后的尾部片段 / Tail fragment after the hit
    sScan        : STRING(255);          // 查找窗口，从 nSearchFrom 起的剩余串 / Search window starting at nSearchFrom
    nPos         : INT;                  // 当前命中位置，1 起，0 = 未命中 [字符位] / Current hit position, one based
    nSearchFrom  : INT;                  // 下一轮查找起点，1 起 [字符位] / Next search start position
    nLenBuf      : INT;                  // 当前缓冲长度 [字符] / Current buffer length
    nLenPat      : INT;                  // 模式串长度 [字符] / Pattern length
    nLenRep      : INT;                  // 替换串长度 [字符] / Replacement length
    nTailStart   : INT;                  // 尾部片段起始位置 [字符位] / Tail fragment start position
    nMaxRepUse   : INT;                  // 生效替换次数上限 [次] / Effective replacement limit
    nMaxLenUse   : INT;                  // 生效结果长度上限 [字符] / Effective result length limit
    nGuard       : DINT;                 // 循环守卫，防串函数异常导致死循环 / Loop guard against endless looping
END_VAR
VAR CONSTANT
    DL_STR_MAX   : INT  := 255;          // 单字节串长度上限，与类型声明一致 [字符] / Single byte string ceiling
    DL_PAT_MAX   : INT  := 32;           // 模式串长度上限，与入参声明一致 [字符] / Pattern ceiling
    DL_REP_MAX   : INT  := 64;           // 替换串长度上限，与入参声明一致 [字符] / Replacement ceiling
    DL_GUARD_MAX : DINT := 512;          // 循环守卫上限 [次] / Loop guard limit
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜结果预置（P-01 范式）：先给全部出口与全部中间量确定值
 *      Safe preset: every output and every intermediate gets a defined value
 *-----------------------------------------------------------------------------*)
FC_DL_StringReplaceAll := 0;
sResult    := '';
nReplaced  := 0;
bTruncated := FALSE;
uErrorId   := 16#0000_0000;
bValid     := FALSE;
sBuf       := '';
sHead      := '';
sTail      := '';
sScan      := '';
nPos       := 0;
nSearchFrom := 1;
nLenBuf    := 0;
nLenPat    := 0;
nLenRep    := 0;
nTailStart := 0;
nMaxRepUse := 0;
nMaxLenUse := 1;
nGuard     := 0;

(*------------------------------------------------------------------------------
 * 段 2｜参数闸门：串长快照 + 两个长度上限钳位（信息级，钳位后照常执行）
 *      Parameter gates: string snapshots and the two length clamps (informational)
 *-----------------------------------------------------------------------------*)
nLenPat := LEN(sPattern);
IF nLenPat > DL_PAT_MAX THEN
    nLenPat := DL_PAT_MAX;
END_IF
nLenRep := LEN(sReplace);
IF nLenRep > DL_REP_MAX THEN
    nLenRep := DL_REP_MAX;
END_IF

nMaxRepUse := nMaxReplace;
IF nMaxRepUse < 0 THEN
    nMaxRepUse := 0;
    uErrorId := 16#0001_0133;
ELSIF nMaxRepUse > DL_STR_MAX THEN
    nMaxRepUse := DL_STR_MAX;
    IF uErrorId = 16#0000_0000 THEN
        uErrorId := 16#0001_0133;
    END_IF
END_IF
IF nMaxRepUse = 0 THEN
    nMaxRepUse := DL_STR_MAX;
END_IF

nMaxLenUse := nMaxLen;
IF nMaxLenUse < 1 THEN
    nMaxLenUse := 1;
    IF uErrorId = 16#0000_0000 THEN
        uErrorId := 16#0001_0133;
    END_IF
ELSIF nMaxLenUse > DL_STR_MAX THEN
    nMaxLenUse := DL_STR_MAX;
    IF uErrorId = 16#0000_0000 THEN
        uErrorId := 16#0001_0133;
    END_IF
END_IF

bValid := (uErrorId = 16#0000_0000);
sBuf   := LEFT(sSource, DL_STR_MAX);

(*------------------------------------------------------------------------------
 * 段 3｜模式串硬闸：长度 0 直接早退，绝不进入查找循环
 *      Hard gate on the pattern: a zero length pattern never reaches the loop
 *      空模式在 FIND 上的行为跨平台不一致，且会让游标推进律失效，必须在算法入口拦死
 *      An empty pattern makes FIND platform dependent and breaks cursor advance
 *-----------------------------------------------------------------------------*)
IF nLenPat <= 0 THEN
    bValid   := FALSE;
    uErrorId := 16#0001_0130;
ELSE

    (*--------------------------------------------------------------------------
     * 段 4｜主替换循环：三闸并行 —— 次数上限、守卫计数、游标只前进
     *      Main replace loop guarded by the count limit, the guard counter and a
     *      strictly advancing cursor
     *      切分口径：头部保留 + 替换串 + 尾部保留，拼装后立即按串上限回夹
     *      Split policy: head kept, replacement inserted, tail kept, then re-clamped
     *      回夹前必须预判长度：静默回夹等于丢字符，bTruncated 与 0132 必须同时置位
     *      The length is predicted before clamping so truncation is never silent
     *-----------------------------------------------------------------------*)
    nSearchFrom := 1;
    nReplaced   := 0;
    nGuard      := 0;

    WHILE (nReplaced < nMaxRepUse) AND (nGuard < DL_GUARD_MAX) DO
        nGuard  := nGuard + 1;
        nLenBuf := LEN(sBuf);
        nPos    := 0;

        IF (nSearchFrom >= 1) AND (nSearchFrom <= nLenBuf) THEN
            sScan := MID(sBuf, nLenBuf - nSearchFrom + 1, nSearchFrom);
            nPos  := FIND(sScan, sPattern);
            IF nPos > 0 THEN
                nPos := nPos + nSearchFrom - 1;
            END_IF
        END_IF

        IF nPos <= 0 THEN
            EXIT;
        END_IF

        IF nPos > 1 THEN
            sHead := LEFT(sBuf, nPos - 1);
        ELSE
            sHead := '';
        END_IF

        nTailStart := nPos + nLenPat;
        IF nTailStart <= nLenBuf THEN
            sTail := MID(sBuf, nLenBuf - nTailStart + 1, nTailStart);
        ELSE
            sTail := '';
        END_IF

        (* 拼接长度预判：超出串型上限即属截断，先置标志与事件码，绝不静默丢字符 *)
        (* Predict the joined length: exceeding the string ceiling is a truncation *)
        IF (LEN(sHead) + nLenRep + LEN(sTail)) > DL_STR_MAX THEN
            bTruncated := TRUE;
            IF uErrorId = 16#0000_0000 THEN
                uErrorId := 16#0001_0132;
            END_IF
        END_IF
        sBuf := CONCAT(sHead, sReplace);
        sBuf := CONCAT(sBuf, sTail);
        sBuf := LEFT(sBuf, DL_STR_MAX);

        nReplaced := nReplaced + 1;

        (* 游标跳到「已插入替换串之后」：替换串含模式串时天然跳过新插入段 *)
        (* Cursor jumps past the inserted replacement: self growing patterns are safe *)
        nSearchFrom := nPos + nLenRep;
        IF nSearchFrom < 1 THEN
            nSearchFrom := 1;
        END_IF
    END_WHILE;

    (*--------------------------------------------------------------------------
     * 段 5｜上限判定：达到次数上限且剩余串内仍有模式串，说明结果不完整
     *      Limit verdict: hitting the count limit with the pattern still present
     *      means the result is incomplete and must be reported, never silently cut
     *-----------------------------------------------------------------------*)
    nLenBuf := LEN(sBuf);
    IF nReplaced >= nMaxRepUse THEN
        nPos := 0;
        IF (nSearchFrom >= 1) AND (nSearchFrom <= nLenBuf) THEN
            sScan := MID(sBuf, nLenBuf - nSearchFrom + 1, nSearchFrom);
            nPos  := FIND(sScan, sPattern);
        END_IF
        IF nPos > 0 THEN
            bValid := FALSE;
            IF uErrorId = 16#0000_0000 THEN
                uErrorId := 16#0001_0131;
            END_IF
        END_IF
    END_IF

END_IF

(*------------------------------------------------------------------------------
 * 段 6｜结果截断（两条路径共用）：超长按上限裁剪并置标志，事件码首事件优先
 *      Shared truncation step: crop to the limit and keep the first event code
 *-----------------------------------------------------------------------------*)
nLenBuf := LEN(sBuf);
IF nLenBuf > nMaxLenUse THEN
    sBuf       := LEFT(sBuf, nMaxLenUse);
    bTruncated := TRUE;
    IF uErrorId = 16#0000_0000 THEN
        uErrorId := 16#0001_0132;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜结果落地：返回值与出口同源，保证「同入参同结果」的可重入语义
 *      Result publication: the return value and the output share one source
 *-----------------------------------------------------------------------------*)
sResult := sBuf;
FC_DL_StringReplaceAll := nReplaced;
END_FUNCTION
