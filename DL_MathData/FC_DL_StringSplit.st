(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringSplit
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library 的标准串函数（LEN / FIND / LEFT / DELETE）
 * 功能描述 (Function)   : 按单字符分隔符把报文拆分为字段数组。返回实际拆分出的字段数，
 *                         字段写入调用方提供的持久数组（引用型输入输出）。
 *                         采用"定位 → 取字段 → 吃掉已处理段"的标准循环，全库统一口径，
 *                         替代各项目各写一套的重复劳动（主流平台均无内置拆分函数）。
 *                         相邻分隔符产生空字段，符合 CSV 语义，不跳过、不合并；
 *                         字段数超出调用方上限时，剩余整段并入末字段并置截断标志，
 *                         结果不静默丢弃。
 * 开源溯源 (Origin)     : 原创实现。定位取段的处理范式为公开通行做法；
 *                         空字段语义与截断语义为本库差异化设计，未复制任何源码。
 * 本文件内含       : FC    FC_DL_StringSplit（单 POU，无配套类型）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: LEN / FIND / LEFT / DELETE
 * 红线自检 (Redline)    : R1 ✓ 禁用全局存储与物理寻址 ｜ R2 ✓ 无地址直写
 *                         R3 ✓ 仅标准串函数 ｜ R4 ✓ 主循环防死锁 + 字段数钳位 + 下标双检
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（纯函数，无状态机）
 *                         R7 N/A（无定时器/边沿实例）｜ R8 ✓ 字段上限与循环上限全常量化
 *
 * 【输出缓冲纪律 / Output buffer discipline（边界 B7，反例警告）】
 *   字段数组为引用型输入输出，调用方必须传入持久数组并在每次调用前自行清场。
 *   反例：把临时变量或每次新构造的数组传进来，上一次调用的残留字段会留在数组里，
 *   本次字段数变少时旧字段仍然可见，表现为"配方里凭空多出几个字段"的诡异故障。
 *   正确做法：一个报文一个专用数组，调用前用循环把数组元素清成空串。
 *
 * 【内存要求 / Memory requirement（边界 B10）】
 *   调用方需持有 16 × 256 字节约 4KB 的字段缓冲。单次调用最坏 16 次定位/取段/删除，
 *   无嵌套循环，耗时与报文长度呈线性关系。
 *
 * 【单字符锁定 / Single-character delimiter（边界 B1，决策 D-R2-18）】
 *   分隔符长度必须恰好为 1，否则直接拒绝且不拆分。多字符分隔会同时复杂化
 *   定位语义与截断语义，单字符已覆盖 CSV / 分号 / 竖线全部主流场景。
 *
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 第二轮 · Level 0 批次 A）
 *============================================================================*)
FUNCTION FC_DL_StringSplit : INT
VAR_INPUT
    sSource    : STRING(255);                 // 待拆分报文，最大 255 字符 / Source message, 255 characters max
    sDelimiter : STRING(1) := ',';            // 分隔符（单字符） / Single-character delimiter
    uMaxFields : INT := 16;                   // 最大输出字段数 [个]，合法域 1..16 / Max output fields [count], valid 1..16
END_VAR
VAR_IN_OUT
    aFields    : ARRAY[0..15] OF STRING(255); // 输出字段缓冲，调用方持有并复用 / Caller-owned reusable output buffer
END_VAR
VAR_OUTPUT
    bValid     : BOOL;                        // 拆分完整标志，FALSE = 发生截断 / Complete flag, FALSE = truncated
    uErrorId   : UDINT;                       // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    sTmp       : STRING(255);   // 剩余段工作副本，源串全程只读 / Working copy of the remaining segment
    nDelimPos  : INT;           // 分隔符位置（1 起始，0 = 未找到） / Delimiter position, 1-based, 0 = not found
    nFieldIdx  : INT;           // 当前字段索引 [个] / Current field index [count]
    nFieldLen  : INT;           // 当前字段长度 [字符] / Current field length [characters]
    nDelimLen  : INT;           // 分隔符长度校验值 [字符] / Delimiter length check value [characters]
    nMaxEff    : INT;           // 钳位后的最大字段数 [个] / Clamped max fields [count]
    nSrcLen    : INT;           // 源串有效长度 [字符] / Effective source length [characters]
    bRun       : BOOL;          // 循环继续标志 / Loop continuation flag
    nGuard     : DINT;          // 循环防死锁计数器 [次] / Loop deadlock guard counter [count]
    nLoop      : INT;           // 主循环索引 [次] / Main loop index [count]
END_VAR
VAR CONSTANT
    DL_SP_MAX_FIELDS : INT  := 16;   // 字段数上限 [个]，与数组维度一致 / Field cap [count], must match the array
    DL_SP_LOOP_MAX   : DINT := 64;   // 主循环防死锁上限 [次]，字段数 × 余量 / Loop guard limit [count]
    DL_SP_LEN_MAX    : INT  := 255;  // 报文字符上限 [字符]，与类型声明一致 / Message length cap [characters]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜结果预置（P-01 范式）：先给 0 字段与成功标志
 *      Safe preset: zero fields and a success flag
 *-----------------------------------------------------------------------------*)
FC_DL_StringSplit := 0;
bValid   := TRUE;
uErrorId := 16#0000_0000;
nFieldIdx := 0;
nFieldLen := 0;
nMaxEff   := uMaxFields;

(*------------------------------------------------------------------------------
 * 段 2｜分隔符合法性（边界 B1）：长度不为 1 直接拒绝，不进入拆分流程
 *      Delimiter validity: any length other than one is rejected before splitting
 *-----------------------------------------------------------------------------*)
nDelimLen := LEN(sDelimiter);

IF nDelimLen <> 1 THEN
    bValid   := FALSE;
    uErrorId := 16#0001_0008;
    FC_DL_StringSplit := 0;
ELSE

    (*--------------------------------------------------------------------------
     * 段 3｜字段数钳位（边界 B2）：越界钳位后继续拆分，不停机
     *      Field count clamping: clamp and keep splitting, never stop the machine
     *-------------------------------------------------------------------------*)
    IF nMaxEff < 1 THEN
        nMaxEff  := 1;
        uErrorId := 16#0001_0001;
    ELSIF nMaxEff > DL_SP_MAX_FIELDS THEN
        nMaxEff  := DL_SP_MAX_FIELDS;
        uErrorId := 16#0001_0001;
    END_IF

    (* 源串长度先钳位再用：超长报文的尾部按截断处理，绝不越界读 *)
    (* Source length clamped first: an over-length message is treated as truncated *)
    nSrcLen := LEN(sSource);
    IF nSrcLen > DL_SP_LEN_MAX THEN
        nSrcLen := DL_SP_LEN_MAX;
    ELSIF nSrcLen < 0 THEN
        nSrcLen := 0;
    END_IF

    IF nSrcLen = 0 THEN
        (* 空源串是合法结果而非错误（边界 B3） *)
        (* An empty source is a legal result, not an error *)
        FC_DL_StringSplit := 0;
    ELSE

        (*----------------------------------------------------------------------
         * 段 4｜主循环（边界 B4/B5/B6）：定位、取段、删除已处理段
         *      Main loop: locate, extract, then drop the handled prefix
         *      已到最后一个可用字段而串内仍有分隔符时，剩余整段并入末字段并置截断标志
         *      On the last usable field with delimiters left, the whole remainder is kept
         *      并在置位截断标志，调用方据此识别"字段没拆完"
         *      and the truncation flag is raised so the caller can tell fields were cut
         *---------------------------------------------------------------------*)
        sTmp   := sSource;
        nLoop  := 0;
        bRun   := TRUE;
        nGuard := 0;

        WHILE bRun DO

            IF nFieldIdx >= nMaxEff THEN
                bRun := FALSE;
            ELSE
                nDelimPos := FIND(sTmp, sDelimiter);

                IF (nDelimPos > 0) AND ((nFieldIdx + 1) < nMaxEff) THEN
                    (*----------------------------------------------------------
                     * 段 4a｜常规切分：字段 = 分隔符之前的部分，然后吃掉分隔符
                     *      Normal split: the field precedes the delimiter, which is dropped
                     *      连续分隔符会自然产生长度为 0 的空字段，不跳过（边界 B6）
                     *      Consecutive delimiters yield empty fields, never skipped
                     *---------------------------------------------------------*)
                    nFieldLen := nDelimPos - 1;

                    IF nFieldLen < 0 THEN
                        nFieldLen := 0;
                    END_IF

                    IF (nFieldIdx >= 0) AND (nFieldIdx < DL_SP_MAX_FIELDS) THEN
                        aFields[nFieldIdx] := LEFT(sTmp, nFieldLen);
                    END_IF

                    sTmp      := DELETE(sTmp, nDelimPos, nDelimLen);
                    nFieldIdx := nFieldIdx + 1;

                ELSE
                    (*----------------------------------------------------------
                     * 段 4b｜末段落地：无分隔符，或已到最后一个可用字段
                     *      Final segment: no delimiter left, or the last usable field
                     *      后者若串内仍有分隔符即为截断，剩余整段并入末字段并告警
                     *      The latter with a delimiter present is a truncation and is flagged
                     *---------------------------------------------------------*)
                    IF (nFieldIdx >= 0) AND (nFieldIdx < DL_SP_MAX_FIELDS) THEN
                        aFields[nFieldIdx] := sTmp;
                    END_IF

                    nFieldIdx := nFieldIdx + 1;

                    IF nDelimPos > 0 THEN
                        bValid   := FALSE;
                        uErrorId := 16#0001_000D;
                    END_IF

                    sTmp := '';
                    bRun := FALSE;
                END_IF

            END_IF

            (* 防死锁：每轮字段索引必然递增，仍设上限兜底防止异常串函数导致死循环 *)
            (* Deadlock guard: the index always advances, the cap is a second line of defence *)
            nGuard := nGuard + 1;
            nLoop  := nLoop + 1;

            IF (nGuard > DL_SP_LOOP_MAX) OR (nLoop > DL_SP_MAX_FIELDS) THEN
                bRun     := FALSE;
                bValid   := FALSE;
                IF uErrorId = 16#0000_0000 THEN
                    uErrorId := 16#0001_0004;
                END_IF
            END_IF

        END_WHILE;

        (*----------------------------------------------------------------------
         * 段 5｜返回值：实际字段数，异常路径返回已完成的数量（P-01）
         *      Return value: the actual field count, partial counts on abnormal paths
         *---------------------------------------------------------------------*)
        IF nFieldIdx < 0 THEN
            FC_DL_StringSplit := 0;
        ELSIF nFieldIdx > DL_SP_MAX_FIELDS THEN
            FC_DL_StringSplit := DL_SP_MAX_FIELDS;
        ELSE
            FC_DL_StringSplit := nFieldIdx;
        END_IF

    END_IF
END_IF
END_FUNCTION
