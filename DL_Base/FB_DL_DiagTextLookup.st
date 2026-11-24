(*==============================================================================
 * 组件名称 (Component)  : FB_DL_DiagTextLookup
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（LEN / SHR / 类型转换），零厂商方言
 * 来源标签 (Source)     : self-std
 * 功能描述 (Function)   : 诊断码到 HMI 文本的纯查表：32 位诊断码低 16 位为表内下标，
 *                         高 16 位为段位（0001 / 0003 等分段路由信息，原样导出给 HMI）。
 *                         命中返回该行文本（中英双数组，按语言选择位取一）；
 *                         未命中返回空串占位行并置 bNotFound；文本超 255 字符按
 *                         R49 四步样板先置截断码再钳长写入。
 *                         每拍重算不锁存（纯查表语义，规格明示：本件无时序状态机，
 *                         故障级码同为每拍重算，规格条款优先于锁存惯例）。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 文本数组经 VAR_IN_OUT 注入（零全局耦合）：中英两数组维度一致 [0..63]、
 *      元素 STRING(512)——源行允许长于输出上限，截断防御真实可达；
 *      输出 sText / sTextOpp 固定 STRING(255)。
 *   2) 码位高段掩码路由：nIdx = 低 16 位掩码 AND 的无符号值，段位不参与寻址；
 *      段位经 uSegment 原样导出（0001 = Base 族、0003 = Device 族等），HMI 据此分组。
 *   3) 未命中（下标越出有效行数）与组态非法（表长 <= 0）输出不同的码位与标志：
 *      未命中为信息级 + bNotFound，组态非法为故障级 + bError + 输出空串。
 *   4) 本件无定时器 / 无边沿 / 无状态驻留：每拍纯重算，失能语义即组态非法语义。
 * 故障码表 (Error codes) :
 *   16#0001_03F2 [故障级] 表长组态非法（<1 或 >64），输出空串 + bNotFound + bError
 *                 反证：该场景输出空串且 bNotFound 置位，与「未命中」输出组合
 *                 完全相同，无故障级码则组态错误会被当成普通未命中静默放过。
 *   16#0001_04B6 [信息级] 码位未命中（下标越出有效行数），返回空串占位行
 *                 反证：bNotFound 已置位，但 HMI 事件流水需要码位归档未命中
 *                 频次（高频未命中 = 表维护缺失），布尔位不承载频次。
 *   16#0001_04B7 [信息级] 命中行文本超 255 字符，已按 R49 先置码后钳长
 *                 反证：截断后的文本与真实 255 长文本输出组合相同，无码则
 *                 截断事实不可观测（R49 截断码赋值行先于钳位行，本件已按序）。
 * 码位总账 (Code ledger) : 16#0001_03F2 用 ｜ 16#0001_04B6 / 04B7 用
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: LEN / SHR
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 表长域闸 / 下标界检（LOWER/UPPER 口径）
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（纯查表，无状态机无 CASE）
 *                         R7 N/A（无定时器 / 边沿实例）
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R68 构建轮 · 批 1 · 目标 3）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_DiagTextLookup
VAR_INPUT
    uCodeIn    : UDINT := 0;    // 输入诊断码 [码]，低 16 位 = 表内下标 / Diagnostic code in, low word = index
    nTableLen  : INT   := 64;   // 有效行数 [行]，域 1..64，越界组态非法 / Valid row count, 1..64
    bEnglish   : BOOL  := FALSE;// 语言选择位：FALSE = 中文，TRUE = 英文 / Language select, FALSE Chinese
    bEnable    : BOOL  := TRUE; // 查表使能（FALSE 输出空串安全态）/ Lookup enable, FALSE safe empty
END_VAR
VAR_IN_OUT
    azhTable : ARRAY[0..63] OF STRING(512);  // 中文文本表 [0..63 行]，注入引用 / Chinese text table, injected by reference
    aenTable : ARRAY[0..63] OF STRING(512);  // 英文文本表 [0..63 行]，注入引用 / English text table, injected by reference
END_VAR
VAR_OUTPUT
    sText      : STRING(255);   // 命中文本（按语言选择位）/ Hit text per the language select
    sTextOpp   : STRING(255);   // 另一语言文本（双语 HMI 诊断用）/ Text in the other language
    bNotFound  : BOOL;          // 未命中标志（本拍重算）/ Not found flag, recomputed every scan
    bTruncated : BOOL;          // 截断标志（本拍重算，R49 先码后钳）/ Truncated flag, code set before clamp
    uSegment   : UDINT;         // 码位高段（0001 / 0003 等分段路由）/ High segment of the code for routing
    bError     : BOOL;          // 故障标志（表长组态非法，每拍重算）/ Fault flag, config class
    uErrorId   : UDINT;         // 故障码，0 = 无故障（每拍重算）/ Error code, recomputed every scan
    bValid     : BOOL;          // 本拍查表有效命中 / A valid hit this scan
END_VAR
VAR
    nIdx      : DINT;           // 低 16 位下标 [行]，DINT 承载防 0xFFFF 越界 INT / Low-word index as DINT
    sSrcSel   : STRING(512);    // 选中语言源行快照 / Selected language source row snapshot
    sSrcOpp   : STRING(512);    // 另一语言源行快照 / Other language source row snapshot
    bHit      : BOOL;           // 本拍下标命中 / Index hit this scan
    nLenSel   : INT;            // 选中行长度 [字符]，LEN 标准返回 INT / Selected row length, LEN returns INT
    nLenOpp   : INT;            // 另一语言行长度 [字符] / Other row length
END_VAR
VAR CONSTANT
    DL_DT_IDX_MASK : UDINT := 16#0000_FFFF;  // 低 16 位下标掩码 / Low-word index mask
    DL_DT_SEG_SHFT : UDINT := 16;            // 段位右移量 [bit]（< 32，结构性安全）/ Segment shift, structurally safe
    DL_DT_ROWS_MAX : INT   := 64;            // 表容量上限 [行]，与数组维度一致 / Table capacity, matches the arrays
    DL_DT_TEXT_MAX : INT   := 255;           // 输出文本上限 [字符]，LEN 同型 INT / Output text ceiling, INT like LEN
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预清（单拍 / 信息位统一出口预置，FB51-8①）
 *      Per-scan preset of all single-scan and info outputs
 *-----------------------------------------------------------------------------*)
sText      := '';
sTextOpp   := '';
bNotFound  := FALSE;
bTruncated := FALSE;
bValid     := FALSE;
bError     := FALSE;
uErrorId   := 16#0000_0000;
uSegment   := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 2｜组态域闸（R151）：表长 <1 或 >64 即非法，输出安全态（空串）
 *      Config gate: table length out of 1..64 is illegal, safe empty output
 *      组态非法为结构性分支（IF/ELSE 全覆盖），不用 RETURN 早退（失能路径清输出）
 *-----------------------------------------------------------------------------*)
IF (NOT bEnable) OR (nTableLen < 1) OR (nTableLen > DL_DT_ROWS_MAX) THEN
    (* 组态非法 / 失能：空串安全态 + 故障级码（失能与非法共用安全出口，码位区分） *)
    (* Illegal or disabled: safe empty output, fault code tells the two apart *)
    IF (nTableLen < 1) OR (nTableLen > DL_DT_ROWS_MAX) THEN
        uErrorId := 16#0001_03F2;   // 故障级：表长组态非法 / Fault: table length illegal
        bError   := TRUE;           // R45 配对 / Paired with the fault code
        bNotFound := TRUE;          // 非法态同样视为未命中语义 / Illegal also means not found
    END_IF
ELSE
    (*------------------------------------------------------------------------------
     * 段 3｜下标路由与段位导出（边界 B2）
     *      Index routing and segment export
     *      UDINT_TO_DINT：0xFFFF = 65535 超出 INT 正域，必须升位 DINT 承载（R55）
     *-----------------------------------------------------------------------------*)
    nIdx    := UDINT_TO_DINT(uCodeIn AND DL_DT_IDX_MASK);
    uSegment := SHR(uCodeIn, DL_DT_SEG_SHFT);
    bHit    := (nIdx >= 0) AND (nIdx < UDINT_TO_DINT(nTableLen));

    IF bHit THEN
        (*------------------------------------------------------------------------------
         * 段 4｜命中：双语言取行 + R49 四步截断样板
         *      Hit: fetch both rows, R49 four-step truncation template
         *      步 1 测长 -> 步 2 超限置码 -> 步 3 钳长（赋值即钳） -> 步 4 写出
         *      步 1 measure, step 2 code, step 3 clamp by assignment, step 4 write
         *-----------------------------------------------------------------------------*)
        IF bEnglish THEN
            sSrcSel := aenTable[DINT_TO_INT(nIdx)];
            sSrcOpp := azhTable[DINT_TO_INT(nIdx)];
        ELSE
            sSrcSel := azhTable[DINT_TO_INT(nIdx)];
            sSrcOpp := aenTable[DINT_TO_INT(nIdx)];
        END_IF

        nLenSel := LEN(sSrcSel);        // 标准 LEN 返回 INT / Standard LEN returns INT
        nLenOpp := LEN(sSrcOpp);

        IF nLenSel > DL_DT_TEXT_MAX THEN
            bTruncated := TRUE;          // 步 2 截断码先行（R49：码先于钳）/ Code before clamp
            uErrorId   := 16#0001_04B7;
        END_IF
        IF nLenOpp > DL_DT_TEXT_MAX THEN
            bTruncated := TRUE;          // 另一语言超限同置标志 / Other language truncation too
            IF uErrorId = 16#0000_0000 THEN
                uErrorId := 16#0001_04B7;
            END_IF
        END_IF

        sText    := sSrcSel;             // 步 3+4：赋值即按 255 钳长写出 / Clamp by assignment
        sTextOpp := sSrcOpp;
        bValid   := TRUE;
    ELSE
        (*------------------------------------------------------------------------------
         * 段 5｜未命中：空串占位行 + 信息级码（每拍重算，不锁存）
         *      Miss: empty placeholder row plus info code, recomputed per scan
         *-----------------------------------------------------------------------------*)
        sText     := '';
        sTextOpp  := '';
        bNotFound := TRUE;
        uErrorId  := 16#0001_04B6;
    END_IF
END_IF
END_FUNCTION_BLOCK
