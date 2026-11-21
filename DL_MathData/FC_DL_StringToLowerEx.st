(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringToLowerEx
 * 所属子库 (Sublibrary) : DL_MathData
 * 归属目录 (Directory)  : C:\Library\DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 函数（FUNCTION）· 纯函数 · 字符串小写扩展转换
 *                         iec-std-wrapper / string / r40-reference
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 LEN / MID / CONCAT / FIND
 * 溯源声明 (Provenance) : IEC 61131-3 标准语义的道莅防御性实现——内部委托平台标准库语义，
 *                         外围统一错误码 / 钳位 / 双语注释，严禁重实现数学内核。
 * 功能一句话 (Summary)  : 把 ASCII 域内大写字母映射为小写，域外字符保持原值并计数，
 *                         超长按截断标志显式分路，空串原样直通。
 * 本件存在的意义 (Why this unit exists)：
 *   各平台自带的大小写转换行为不一（有的吞掉高位字符、有的整串拒绝），本件只用
 *   标准 LEN/MID/CONCAT/FIND 做逐字符查表映射：大写字母经双码表定位转小写，
 *   其余字符原样保留并以信息码告知「有保留发生」，调用方永远知道结果里混了什么。
 * 功能描述 (Function)   : 第 1 步 LEN 一次锁存源长；第 2 步与 255 上限比较；第 3 步
 *                         超限先置截断标志（255 上限显式化，不依赖平台隐式截断）；
 *                         第 4 步按 bAllowTrunc 分路截断写出或拒绝。
 *                         空串直通：源长为 0 时不进循环、写出计数 0 等于源长 0，
 *                         出口装配返回 TRUE 且不占任何码位。
 *                         合法路径逐字符取字符：落在 'A'..'Z' 域内的用 FIND 在大写
 *                         码表定位后到同位小写码表取字符，域外字符保持并累计 nKept。
 * 与既有件边界 (Boundary): 本件为 FC_DL_StringToUpperEx 的严格对偶件（映射方向互逆、
 *                         四步样板与分路口径逐条对应），只做 ASCII A..Z 域内映射，
 *                         不做 Unicode 与本地化。
 * 码位说明 (Codes)      : 信息 16#0001_0499 源超 255 上限，已按上限截断写出
 *                         故障 16#0001_03D4 源超上限且未允许截断（防御闸拒绝）
 *                         故障 16#0001_03D5 写出计数与源长不一致（防御校验）
 *                         （R90 反证句：截断事实无法由 sDst 观测——截断与正常写出
 *                           结果均为合法串且返回值同为 TRUE，故截断侧须占码；
 *                           计数不一致属写出链路异常，与截断、保留场景的输出组合
 *                           （空串加故障码）均不同，故独立占码）
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 LEN / MID / CONCAT / FIND。
 * 镜像量清单 (R38)      : nSrcLen 是本件唯一锁存量，入口一次导出，其后比较与循环
 *                         上界全部读该副本，全文不再对入参串取长度。
 * 遗留假设 (Legacy)     : 字符比较使用 >= / <= 排序比较（与库内 FC_DL_StringToUpperEx
 *                         同口径）；若某平台未实现 STRING 排序比较，须在编译门槛里
 *                         核对后改走 FIND 查表判定。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 标准库
 *                         无除法故无除零面 ｜ 全变量双语同行注释 ｜ 无定时器实例
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  首版入库（R40 · 批 3 · T0 快车道）
 *============================================================================*)

FUNCTION FC_DL_StringToLowerEx : BOOL
VAR_INPUT
    sSrc        : STRING(255);      // 源文本 [ASCII]，定长 255 ｜ source text, fixed 255 characters
    bAllowTrunc : BOOL := FALSE;    // 允许截断，真则截断写出，假则拒绝构造 ｜ TRUE truncates and writes, FALSE refuses
END_VAR
VAR_OUTPUT
    sDst        : STRING(255);      // 小写结果 [ASCII]，域外字符保持原值 ｜ lowercase result, out-of-domain chars kept
    bTruncated  : BOOL;             // 截断标志，源超上限时为真 ｜ set true when the source exceeded the limit
    nKept       : INT;              // 保持原值的域外字符个数 [个] ｜ count of kept out-of-domain characters
    uErrorId    : UDINT;            // 事件码，0 表示无事件 ｜ event code, zero means none
END_VAR
VAR
    sTmp     : STRING(255); // 结果累积缓冲 [ASCII]，出口一次性赋给 sDst ｜ result staging buffer, assigned to sDst once at the exit
    cCh      : STRING(1);   // 当前字符 [字符] ｜ current character
    sLo      : STRING(1);   // 转换后的字符 [字符] ｜ converted character
    nPos     : INT;         // 字符在码表中的位置 [索引]，1 起 ｜ character position in the code table, 1-based
    nSrcLen  : INT;         // 锁存的源文本长度 [字符]，本件唯一锁存量 ｜ latched source length, the single latched quantity
    nWritten : INT;         // 写出计数 [字符]，出口与 nSrcLen 比对 ｜ written count compared at the exit
    uCode    : UDINT;       // 码位暂存，出口单点写入 [码] ｜ code staging, written once at the exit
END_VAR
VAR CONSTANT
    DL_STL_MAXLEN : INT := 255; // 字符串上限 [字符]，与形参声明一致 ｜ string limit, matches the declarations
    DL_STL_ONE    : INT := 1;   // 单字符长度参数 [字符] ｜ single character length argument
END_VAR

// 段 1｜输出预置与残留清除：先清空再分流，拒绝路不露旧值 ｜ preset and clear before any branch, the refusal path exposes no stale value
FC_DL_StringToLowerEx := FALSE; // 预置返回失败 ｜ preset return FALSE
sDst       := '';        // 结果清空 ｜ clear the result
sTmp       := '';        // 暂存清空 ｜ clear the staging buffer
bTruncated := FALSE;     // 截断标志清零 ｜ clear the truncation flag
nKept      := 0;         // 保留计数清零 ｜ clear the kept count
nWritten   := 0;         // 写出计数清零 ｜ clear the written count
uErrorId   := 16#0000_0000; // 事件码清零 ｜ clear the event code
uCode      := 16#0000_0000; // 码位暂存清零 ｜ clear the code staging

// 段 2｜LEN 一次锁存 ｜ latch the length once
nSrcLen := LEN(sSrc);        // 源长只取一次，循环内禁重复 LEN ｜ latch the length once, never call LEN again in the loop
IF nSrcLen < 0 THEN
    nSrcLen := 0;            // 防御：异常返回值钳到零 ｜ defensive: clamp an anomalous result to zero
END_IF

// 段 3｜与上限比较，超限先置标志后分路 ｜ compare with the limit, flag first, then branch
IF nSrcLen > DL_STL_MAXLEN THEN
    bTruncated := TRUE;      // 事实先记录，早于任何写入 ｜ record the fact before any write
    IF NOT bAllowTrunc THEN
        uErrorId := 16#0001_03D4; // 故障级配对：拒绝截断以返回假表达（R45）｜ fault level, refusal expressed by FALSE
        RETURN;             // 拒绝构造，结果保持空串 ｜ refuse, result stays empty
    END_IF
    nSrcLen := DL_STL_MAXLEN; // 截断路：按上限截取 ｜ truncation path: cut to the limit
END_IF

// 段 4｜逐字符查表映射：域内转小写，域外保持并计数 ｜ per-character table mapping: convert in-domain, keep and count the rest
FOR nI := 1 TO nSrcLen DO
    cCh := MID(sSrc, DL_STL_ONE, nI);            // 位置 nI 起取一个字符 ｜ one character at position nI
    sLo := cCh;                                  // 默认保持原值 ｜ keep by default
    IF (cCh >= 'A') AND (cCh <= 'Z') THEN
        nPos := FIND('ABCDEFGHIJKLMNOPQRSTUVWXYZ', cCh);     // 大写码表定位，域内恒 1 到 26 ｜ locate in the uppercase table
        sLo  := MID('abcdefghijklmnopqrstuvwxyz', DL_STL_ONE, nPos); // 同位取小写 ｜ same position in the lowercase table
    ELSE
        nKept := nKept + DL_STL_ONE;             // 域外字符保持，累计告知 ｜ keep and count the out-of-domain char
    END_IF
    sTmp := CONCAT(sTmp, sLo);                   // 追加写出 ｜ append to the staging buffer
    nWritten := nWritten + DL_STL_ONE;           // 写出计数同步累加 ｜ sync the written count
END_FOR

// 段 5｜写出一致性校验（防御闸）：计数必须等于锁存源长 ｜ write consistency gate: the count must equal the latched length
IF nWritten <> nSrcLen THEN
    uErrorId := 16#0001_03D5;    // 故障级：写出链路异常，结果作废 ｜ fault: write chain broken, result voided
    sDst := '';                  // 结果作废清空 ｜ void and clear the result
    RETURN;                      // 返回假，bTruncated 保持已记录事实 ｜ return FALSE, the truncation fact stays recorded
END_IF

// 段 6｜出口装配：结果单点写出，码位单点写入 ｜ exit: single write for the result and the code
sDst := sTmp;                    // 暂存结果单点写出 ｜ write the staged result once
IF bTruncated THEN
    uCode := 16#0001_0499;       // 信息级：源超上限已截断 ｜ info level: source beyond the limit, truncated
END_IF
uErrorId := uCode;               // 码位单点写入 ｜ write the code once
FC_DL_StringToLowerEx := TRUE;   // 构造成功 ｜ construction succeeded
END_FUNCTION
