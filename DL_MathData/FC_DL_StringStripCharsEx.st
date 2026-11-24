(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringStripCharsEx
 * 所属子库 (Sublibrary) : DL_MathData
 * 归属目录 (Directory)  : C:\Library\DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 函数（FUNCTION）· 纯函数 · 自定义字符集剥离
 *                         iec-std-wrapper / string / r37-reference
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 LEN / MID / FIND
 * 溯源声明 (Provenance) : IEC 61131-3 标准语义的道莅防御性实现——内部委托平台标准库语义，
 *                         外围统一错误码 / 钳位 / 双语注释，严禁重实现数学内核。
 * 功能一句话 (Summary)  : 去除字符串两侧属于自定义字符集的字符（区别于仅去空格的
 *                         Trim），空集输入恒等返回，全程 R37 四步长度守卫。
 *
 * 功能描述 (Function)   : LEN 一次锁存源长并与 255 比较，超限按 bAllowTrunc 分路；
 *                         合法路径用 FIND 判字符归属，从左向右收缩首界、从右向左
 *                         收缩尾界，中段一次 MID 取出，出口做长度一致性校验。
 * 与既有件边界 (Boundary): FC_DL_StringTrim 只去空格且语义固定；本件字符集是契约
 *                         参数，空串字符集即为恒等变换，不做任何猜测性补剥离。
 * 码位说明 (Codes)      : 信息 16#0002_3038 有剥离发生（nStripped 大于零）
 *                         故障 16#0002_3039 源长度域外且未允许截断（防御闸）
 *                         故障 16#0002_303A 中段取出长度与预期不一致（防御校验）
 *                         段 16#02_3_38~3B 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 LEN / MID / FIND。
 * 镜像量清单 (R38)      : nSrcLen 唯一锁存量；nFirst 与 nLast 是本件的两个消费边界，
 *                         中段长度 nKeep 全部由该副本与两界导出，不重复取 LEN。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 标准库
 *                         无除法故无除零面 ｜ 全变量双语同行注释 ｜ 无定时器实例
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 1）
 *============================================================================*)

FUNCTION FC_DL_StringStripCharsEx : BOOL
VAR_INPUT
    sSrc        : STRING(255);      // 源文本 [ASCII]，定长 255 / Source text, fixed 255 characters
    sStrip      : STRING(255);      // 剥离字符集 [ASCII]，空串即恒等 / Strip charset, empty means identity
    bAllowTrunc : BOOL := FALSE;    // 允许截断，真则截断写出，假则拒绝构造 / TRUE truncates and writes, FALSE refuses
END_VAR
VAR_OUTPUT
    sOut        : STRING(255);      // 剥离结果 [ASCII] / Stripped result
    bTruncated  : BOOL;             // 截断标志，源超上限时为真 / Set true when the source exceeded the limit
    nStripped   : INT;              // 两侧剥离的字符总数 [个] / Total characters stripped from both ends
    uErrorId    : UDINT;            // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    sMid     : STRING(255); // 中段暂存 [ASCII] / Middle segment staging
    cCh      : STRING(1);   // 当前字符 [字符] / Current character
    nSrcLen  : INT;         // 锁存的源文本长度 [字符]，R38 唯一锁存量 / Latched source length
    nFirst   : INT;         // 左边界，1 起 [索引] / Left boundary, 1-based
    nLast    : INT;         // 右边界 [索引] / Right boundary
    nKeep    : INT;         // 中段长度 [字符] / Middle segment length
    uCode    : UDINT;       // 码位暂存，出口单点写入 [码] / Code staging
END_VAR
VAR CONSTANT
    DL_STS_MAXLEN : INT := 255; // 字符串上限 [字符]，与形参声明一致 / String limit, matches the declarations
    DL_STS_ONE    : INT := 1;   // 单字符长度参数 [字符] / Single character length argument
END_VAR

(* 段 1｜输出预置与残留清除 / Pre-set and clear before any branch *)
FC_DL_StringStripCharsEx := FALSE;
sOut       := '';
sMid       := '';
bTruncated := FALSE;
nStripped  := 0;
uErrorId   := 16#0000_0000;
uCode      := 16#0000_0000;

(* 段 2｜R37 第 1 步：LEN 一次锁存 / Step one: latch the length once *)
nSrcLen := LEN(sSrc);
IF nSrcLen < 0 THEN
    nSrcLen := 0;                // 防御：异常返回值钳到零 / Defensive: clamp an anomalous result
END_IF

(* 段 3｜R37 第 2、3 步：与上限比较，超限先置标志后分路 / Compare, flag first, then branch *)
IF nSrcLen > DL_STS_MAXLEN THEN
    bTruncated := TRUE;          // 事实先记录 / Record the fact first
    IF NOT bAllowTrunc THEN
        uErrorId := 16#0002_3039; // 故障级：拒绝构造 / Fault: refuse to build
        RETURN;
    END_IF
    nSrcLen := DL_STS_MAXLEN;    // 第 4 步截断路 / Truncation path
END_IF

(* 段 4｜左界收缩：首字符属于字符集则右移 / Shrink the left boundary while the first char belongs to the set *)
nFirst := 1;
WHILE (nFirst <= nSrcLen) DO
    cCh := MID(sSrc, DL_STS_ONE, nFirst);            // 取当前首字符 / Take the current first character
    IF FIND(sStrip, cCh) > 0 THEN
        nFirst := nFirst + DL_STS_ONE;               // 属集，右移 / Belongs, shift right
    ELSE
        EXIT;                                        // 非属，停 / Not belonging, stop
    END_IF
END_WHILE

(* 段 5｜右界收缩：尾字符属于字符集则左移，越左界即停 / Shrink the right boundary, stop at the left one *)
nLast := nSrcLen;
WHILE (nLast >= nFirst) DO
    cCh := MID(sSrc, DL_STS_ONE, nLast);             // 取当前尾字符 / Take the current last character
    IF FIND(sStrip, cCh) > 0 THEN
        nLast := nLast - DL_STS_ONE;                 // 属集，左移 / Belongs, shift left
    ELSE
        EXIT;                                        // 非属，停 / Not belonging, stop
    END_IF
END_WHILE

(* 段 6｜中段一次取出：长度由两界导出，空段显式置空串 / Take the middle once; an empty segment is explicitly empty *)
nKeep := nLast - nFirst + DL_STS_ONE;                // 中段长度导出 / Derive the middle length
IF nKeep < 0 THEN
    nKeep := 0;                  // 结构性非负，仍显式兜底 / Structurally non-negative, belt and braces
END_IF
IF nKeep > 0 THEN
    sMid := MID(sSrc, nKeep, nFirst);                // 一次取出中段 / Take the middle in one shot
ELSE
    sMid := '';                  // 全串被剥离，结果空串 / Whole string stripped, result empty
END_IF

(* 段 7｜写出一致性校验（防御闸）与出口装配 / Write consistency gate and exit assembly *)
IF LEN(sMid) <> nKeep THEN
    uErrorId := 16#0002_303A;    // 故障级：取出链路异常，结果作废 / Fault: extraction chain broken
    sOut := '';
    RETURN;
END_IF
nStripped := nSrcLen - nKeep;    // 剥离计数导出 / Derive the stripped count
IF nStripped > 0 THEN
    uCode := 16#0002_3038;       // 信息级：有剥离发生 / Info: stripping happened
END_IF
sOut := sMid;
uErrorId := uCode;               // 码位单点写入 / Single write point for the code
FC_DL_StringStripCharsEx := TRUE;
END_FUNCTION
