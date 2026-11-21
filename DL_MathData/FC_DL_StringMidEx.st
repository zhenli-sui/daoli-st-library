(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringMidEx
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library 的 MID / LEN / MIN 内建函数，
 *                         不重实现取子串内核，无厂商字符串方言依赖
 * 功能一句话 (Summary)  : MID 取子串防御包装：起点/长度域闸门钳位 +
 *                         255 上限截断显式置标志（R37 教训：严禁静默回夹）。
 * 功能描述 (Function)   : 从源串 sIn 的 iStart 位序（1 基）起取 iLen 个字符。
 *                         处理次序写死（R37 范式「先判定后写入」）：
 *                         ① LEN 一次锁存源串长（防调用中串被改写的时序歧义）；
 *                         ② 参数域闸门——iStart < 1 钳 1、iLen < 0 钳 0，
 *                         置信息码；③ 越界组合闸——起点超串长返回空串置码；
 *                         ④ 255 上限截断闸——请求长度超串型上限先置截断
 *                         标志再钳长，最后才委托内建 MID，杜绝静默回夹。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款）
 * 码位     (Diag Codes) : 信息级 16#0001_015C（本件独占）：
 *                           参数钳位（iStart<1 钳 1 / iLen<0 钳 0）或起点
 *                           超出串长（含空串输入，返回空串）；
 *                         信息级 16#0001_015D（本件独占）：
 *                           请求子串超串型上限 255，已显式截断（R37 教训：
 *                           定长串截断必须显式置位，严禁静默回夹）。
 * 类型裁定 (Type Note)  : 码位段 16#0001_xxxx 为全库共享 32 位段，WORD 容量不足，
 *                         故 eErr 采用 UDINT 承载（与库内 uErrorId : UDINT 惯例
 *                         一致，沿 R14 批 3 同一裁定）。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: MID / LEN / MIN
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 域闸门先行 + 截断先置标志后钳长
 *                         R5 ✓ 全变量中英双语同行注释
 *                         R6 N/A（纯函数，无 CASE/ENUM 状态机，按批 4 口径标 N/A）
 *                         R7 N/A（FC 为纯函数，无实例调用，头注释显式说明）
 * 防御行为声明 (Defense): ① 处理次序写死「锁存 → 钳位 → 越界闸 → 截断闸 →
 *                           委托内建」，截断判定先于任何写入（R37 范式，
 *                           与库内样板件 FC_DL_StringFixedField 同源）；
 *                         ② LEN 只调用一次锁存到局部变量，后续边界全部用
 *                           锁存值判定——调用拍内源串再被改写也不产生
 *                           「边界用旧长、切片用新长」的时序歧义；
 *                         ③ iStart < 1 钳 1、iLen < 0 钳 0：钳位是正常防御
 *                           行为，置信息码不置故障码；
 *                         ④ 起点超串长（含空串）返回空串并置信息码，
 *                           不调用内建 MID（部分平台对越界起点行为不一）；
 *                         ⑤ 请求长度先按可用串长取 MIN，再对串型上限 255
 *                           截断：超限先置截断标志 16#0001_015D，再钳到 255
 *                           委托内建——MID 的静默回夹绝不作为唯一防线；
 *                         ⑥ 首事件优先：多条件同拍命中时保留先置的码，
 *                           后续码不覆盖，便于现场定位第一诱因；
 *                         ⑦ 串型上限 255 提为只读常量，禁魔法数。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 4 · T0 快车道）
 *============================================================================*)
FUNCTION FC_DL_StringMidEx : STRING
VAR_INPUT
    sIn    : STRING; // 源串 [字符]，定长串型，上限 255 / Source string [chars], fixed-length type, cap 255
    iStart : INT;    // 起始位序 [字符]，1 基，< 1 钳 1 / Start position [chars], 1-based, values below 1 clamped to 1
    iLen   : INT;    // 取长 [字符]，< 0 钳 0 / Length to extract [chars], values below 0 clamped to 0
END_VAR
VAR_OUTPUT
    eErr : UDINT; // 错误码，16#0001_015C=参数钳位或起点越界，16#0001_015D=超 255 显式截断，0=无事件 / Error code, 16#0001_015C=parameter clamped or start beyond length, 16#0001_015D=explicit truncation at the 255 cap, 0=no event
END_VAR
VAR
    nSrcLen : INT; // 锁存的源串长 [字符]，LEN 只调用一次 / Latched source length [chars], LEN called exactly once
    nPos    : INT; // 钳位后起始位序 [字符]，域 >= 1 / Clamped start position [chars], domain >= 1
    nLenC   : INT; // 钳位后取长 [字符]，域 >= 0 / Clamped extraction length [chars], domain >= 0
    nAvail  : INT; // 自起点起可用字符数 [字符] / Characters available from the start position [chars]
    nReq    : INT; // 请求取长 [字符]，取长与可用长取小 / Requested length [chars], min of clamped length and available length
    nUse    : INT; // 实际委托取长 [字符]，域 0 到 255 / Length actually delegated [chars], range 0 to 255
END_VAR
VAR CONSTANT
    DL_SM_MAX : INT := 255; // 串型上限 [字符]，定长 STRING 的隐式容量 / String type cap [chars], implicit capacity of a fixed-length STRING
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与错误码预置：先归零，任何早退路径都不会留下脏码
 *      Preset return value and error code so no early-exit path leaves a stale code
 *-----------------------------------------------------------------------------*)
FC_DL_StringMidEx := '';          // 返回值预置空串 [字符] / Preset return value to the empty string
eErr              := 16#0000_0000;   // 错误码预置无事件 / Preset error code to no event

(*------------------------------------------------------------------------------
 * 段 2｜源串长一次锁存（防御声明②）：后续边界全部用锁存值，
 *      消灭「边界用旧长、切片用新长」的时序歧义
 *      Latch the source length once (defense note 2): all bounds use the
 *      latched value, eliminating stale-length versus fresh-slice races
 *-----------------------------------------------------------------------------*)
nSrcLen := LEN(sIn);   // LEN 一次锁存 [字符] / Latch LEN exactly once [chars]

(*------------------------------------------------------------------------------
 * 段 3｜参数域闸门（防御声明③）：iStart < 1 钳 1、iLen < 0 钳 0，
 *      置信息码（首事件优先，防御声明⑥）
 *      Parameter domain gate (defense note 3): iStart below 1 clamped to 1,
 *      iLen below 0 clamped to 0, informational code raised (first-event
 *      priority per defense note 6)
 *-----------------------------------------------------------------------------*)
IF iStart < 1 THEN
    nPos := 1;              // 起始位序钳 1 [字符] / Start position clamped to 1 [chars]
    eErr := 16#0001_015C;   // 信息码：起始位序越下界已钳位 / Informational: start position below the lower bound, clamped
ELSE
    nPos := iStart;         // 域内直通 [字符] / In-domain pass-through [chars]
END_IF

IF iLen < 0 THEN
    nLenC := 0;             // 取长钳 0（空串结果）[字符] / Length clamped to 0 (empty result) [chars]
    IF eErr = 16#0000_0000 THEN
        eErr := 16#0001_015C;   // 信息码：取长越下界已钳位（首事件优先不覆盖）/ Informational: length below the lower bound, clamped (first event kept)
    END_IF
ELSE
    nLenC := iLen;          // 域内直通 [字符] / In-domain pass-through [chars]
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜越界组合闸（防御声明④）：起点超锁存串长（含空串输入）返回空串，
 *      不调用内建 MID（平台对越界起点行为不一）
 *      Out-of-range combination gate (defense note 4): start beyond the latched
 *      length (including an empty input) returns the empty string without
 *      calling the built-in MID (platform behavior differs on bad starts)
 *-----------------------------------------------------------------------------*)
IF nPos > nSrcLen THEN
    FC_DL_StringMidEx := '';   // 起点越界返回空串 [字符] / Start beyond length, empty string returned
    IF eErr = 16#0000_0000 THEN
        eErr := 16#0001_015C;   // 信息码：起点超出串长（空串输入同此码）/ Informational: start beyond the string length (empty input shares this code)
    END_IF
    RETURN;                    // 早退，不进内建 / Early exit, built-in not called
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜截断闸（防御声明①⑤⑦）：先按可用长取 MIN，再对 255 上限判定——
 *      超限先置截断标志，后钳长，最后才写结果（R37 范式：先判定后写入）
 *      Truncation gate (defense notes 1, 5 and 7): MIN against the available
 *      length first, then judge the 255 cap — set the truncation flag before
 *      clamping, write the result last (R37 paradigm: decide before writing)
 *-----------------------------------------------------------------------------*)
nAvail := nSrcLen - nPos + 1;   // 自起点起可用字符数 [字符] / Characters available from the start [chars]
nReq   := MIN(nLenC, nAvail);   // 请求取长 = 钳位取长与可用长取小 [字符] / Requested length, min of clamped and available [chars]

IF nReq > DL_SM_MAX THEN
    nUse := DL_SM_MAX;          // 请求超 255，钳到串型上限 [字符] / Request beyond 255, clamped to the string cap [chars]
    IF eErr = 16#0000_0000 THEN
        eErr := 16#0001_015D;   // 信息码：超 255 显式截断（严禁静默回夹，R37 教训）/ Informational: explicit truncation at the 255 cap (silent clipping forbidden, lesson R37)
    END_IF
ELSIF nReq <= 0 THEN
    nUse := 0;                  // 取长为 0，空串结果 [字符] / Zero length, empty result [chars]
ELSE
    nUse := nReq;               // 域内直通 [字符] / In-domain pass-through [chars]
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜委托内建内核（防御声明⑤）：nUse 已锁死在 0 到 255 安全域，
 *      nPos 已锁死在 1 到锁存串长域，MID 无越界可能
 *      Delegation to the built-in kernel (defense note 5): nUse locked in
 *      0 to 255, nPos locked in 1 to the latched length, MID cannot overrun
 *-----------------------------------------------------------------------------*)
IF nUse = 0 THEN
    FC_DL_StringMidEx := '';   // 零长请求直接空串返回 [字符] / Zero-length request returns the empty string
ELSE
    FC_DL_StringMidEx := MID(sIn, nUse, nPos);   // 委托内建 MID 内核，不自实现切片 / Delegate to the built-in MID kernel, no re-implementation
END_IF
END_FUNCTION
