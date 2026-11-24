(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringToUpperEx
 * 所属子库 (Sublibrary) : DL_MathData
 * 归属目录 (Directory)  : C:\Library\DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 函数（FUNCTION）· 纯函数 · 字符串大写扩展转换
 *                         iec-std-wrapper / string / r37-reference
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 LEN / MID / CONCAT / FIND
 * 溯源声明 (Provenance) : IEC 61131-3 标准语义的道莅防御性实现——内部委托平台标准库语义，
 *                         外围统一错误码 / 钳位 / 双语注释，严禁重实现数学内核。
 * 功能一句话 (Summary)  : 把 ASCII 域内小写字母映射为大写，域外字符保持原值并计数，
 *                         全程按 R37 四步样板做长度守卫与截断分路。
 *
 * 本件存在的意义 (Why this unit exists)：
 *   各平台自带的大小写转换行为不一（有的吞掉高位字符、有的整串拒绝），本件只用
 *   标准 LEN/MID/CONCAT/FIND 做逐字符查表映射：小写字母经双码表定位转大写，
 *   其余字符原样保留并以信息码告知「有保留发生」，调用方永远知道结果里混了什么。
 *
 * 功能描述 (Function)   : 第 1 步 LEN 一次锁存源长；第 2 步与 255 上限比较；第 3 步
 *                         超限先置截断标志；第 4 步按 bAllowTrunc 分路截断写出或拒绝。
 *                         合法路径逐字符取字符：落在 'a'..'z' 域内的用 FIND 在小写
 *                         码表定位后到同位大写码表取字符，域外字符保持并累计 nKept。
 * 与既有件边界 (Boundary): 本件只做 ASCII a..z 域内映射，不做 Unicode 与本地化；
 *                         与 FC_DL_StringFixedField（改宽度不改内容）正交。
 * 码位说明 (Codes)      : 信息 16#0002_3058 存在域外字符保持原值
 *                         故障 16#0002_3059 源长度域外且未允许截断（防御闸）
 *                         故障 16#0002_305A 写出计数与源长不一致（防御校验）
 *                         段 16#02_3_58~5B 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 LEN / MID / CONCAT / FIND。
 * 镜像量清单 (R38)      : nSrcLen 是本件唯一锁存量，入口一次导出，其后比较与循环
 *                         上界全部读该副本，全文不再对入参串取长度。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 标准库
 *                         无除法故无除零面 ｜ 全变量双语同行注释 ｜ 无定时器实例
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 1）
 *============================================================================*)

FUNCTION FC_DL_StringToUpperEx : BOOL
VAR_INPUT
    sSrc        : STRING(255);      // 源文本 [ASCII]，定长 255 / Source text, fixed 255 characters
    bAllowTrunc : BOOL := FALSE;    // 允许截断，真则截断写出，假则拒绝构造 / TRUE truncates and writes, FALSE refuses
END_VAR
VAR_OUTPUT
    sDst        : STRING(255);      // 大写结果 [ASCII]，域外字符保持原值 / Uppercase result, out-of-domain chars kept
    bTruncated  : BOOL;             // 截断标志，源超上限时为真 / Set true when the source exceeded the limit
    nKept       : INT;              // 保持原值的域外字符个数 [个] / Count of kept out-of-domain characters
    uErrorId    : UDINT;            // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    sTmp     : STRING(255); // 结果累积缓冲 [ASCII]，出口一次性赋给 sDst / Result staging buffer
    cCh      : STRING(1);   // 当前字符 [字符] / Current character
    sUp      : STRING(1);   // 转换后的字符 [字符] / Converted character
    nPos     : INT;         // 字符在码表中的位置 [索引]，1 起 / Character position in the code table, 1-based
    nSrcLen  : INT;         // 锁存的源文本长度 [字符]，R38 唯一锁存量 / Latched source length, the single latched quantity
    nWritten : INT;         // 写出计数 [字符]，出口与 nSrcLen 比对 / Written count compared at the exit
    uCode    : UDINT;       // 码位暂存，出口单点写入 [码] / Code staging, written once at the exit
END_VAR
VAR CONSTANT
    DL_STU_MAXLEN : INT := 255; // 字符串上限 [字符]，与形参声明一致 / String limit, matches the declarations
    DL_STU_ONE    : INT := 1;   // 单字符长度参数 [字符] / Single character length argument
END_VAR

(* 段 1｜输出预置与残留清除：先清空再分流，拒绝路不露旧值 / Pre-set and clear before any branch *)
FC_DL_StringToUpperEx := FALSE;
sDst       := '';
sTmp       := '';
bTruncated := FALSE;
nKept      := 0;
nWritten   := 0;
uErrorId   := 16#0000_0000;
uCode      := 16#0000_0000;

(* 段 2｜R37 第 1 步：LEN 一次锁存 / Step one: latch the length once *)
nSrcLen := LEN(sSrc);
IF nSrcLen < 0 THEN
    nSrcLen := 0;                // 防御：异常返回值钳到零 / Defensive: clamp an anomalous result to zero
END_IF

(* 段 3｜R37 第 2、3 步：与上限比较，超限先置标志后分路 / Steps two and three: compare, flag, then branch *)
IF nSrcLen > DL_STU_MAXLEN THEN
    bTruncated := TRUE;          // 事实先记录，早于任何写入 / Record the fact before any write
    IF NOT bAllowTrunc THEN
        uErrorId := 16#0002_3059; // 故障级配对：本函数级故障以返回假表达（R45）/ Fault level, refusal expressed by FALSE
        RETURN;                  // 拒绝构造，结果保持空串 / Refuse, result stays empty
    END_IF
    nSrcLen := DL_STU_MAXLEN;    // 第 4 步截断路：按上限截取 / Truncation path: cut to the limit
END_IF

(* 段 4｜逐字符查表映射：域内转大写，域外保持并计数 / Per-character table mapping: convert in-domain, keep and count the rest *)
FOR nI := 1 TO nSrcLen DO
    cCh := MID(sSrc, DL_STU_ONE, nI);            // 位置 nI 起取一个字符 / One character at position nI
    sUp := cCh;                                  // 默认保持原值 / Keep by default
    IF (cCh >= 'a') AND (cCh <= 'z') THEN
        nPos := FIND('abcdefghijklmnopqrstuvwxyz', cCh);     // 小写码表定位，域内恒 1 到 26 / Locate in the lowercase table
        sUp  := MID('ABCDEFGHIJKLMNOPQRSTUVWXYZ', DL_STU_ONE, nPos); // 同位取大写 / Same position in the uppercase table
    ELSE
        nKept := nKept + DL_STU_ONE;             // 域外字符保持，累计告知 / Keep and count the out-of-domain char
    END_IF
    sTmp := CONCAT(sTmp, sUp);                   // 追加写出 / Append to the staging buffer
    nWritten := nWritten + DL_STU_ONE;           // 写出计数同步累加 / Sync the written count
END_FOR

(* 段 5｜写出一致性校验（防御闸）：计数必须等于锁存源长 / Write consistency gate: count must equal the latched length *)
IF nWritten <> nSrcLen THEN
    uErrorId := 16#0002_305A;    // 故障级：写出链路异常，结果作废 / Fault: write chain broken, result voided
    sDst := '';
    RETURN;
END_IF

(* 段 6｜出口装配：结果单点写出，码位单点写入 / Exit: single write for result and code *)
sDst := sTmp;
IF nKept > 0 THEN
    uCode := 16#0002_3058;       // 信息级：存在域外字符保持原值 / Info: out-of-domain characters kept
END_IF
uErrorId := uCode;
FC_DL_StringToUpperEx := TRUE;
END_FUNCTION
