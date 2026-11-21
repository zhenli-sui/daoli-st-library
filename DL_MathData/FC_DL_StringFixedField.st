(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringFixedField
 * 所属子库 (Sublibrary) : DL_MathData
 * 归属目录 (Directory)  : C:\Library\DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 函数（FUNCTION）· 纯函数 · 定宽字段填充与对齐
 *                         lgf-datahandling / fixed-field / r37-reference
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 LEN / MID /
 *                         CONCAT / MIN，字符串声明一律显式带长度
 * 功能一句话 (Summary)  : 把任意文本装进定宽字段（左对齐或右对齐、指定填充字符），
 *                         并在发生裁剪时显式置截断标志与事件码。
 *
 * 本件存在的意义 (Why this unit exists)：
 *   本件存在的意义是把 R37 变成可复制的写法。全库所有「往定长缓冲写串」的地方，
 *   都可以照本件的四步顺序抄：先算一次源长度，再与目标宽度比较，比较成立就先置
 *   截断标志与码，最后才写缓冲。顺序一旦颠倒（先 CONCAT 再回夹、或回夹时不置标志），
 *   现场就会出现「字段看着对、内容被砍了一半、日志里一个字都没有」的事故。
 *   本件是全库唯一一处必须在写入前预判长度的地方，因此写成了可当范本读的样子。
 *
 * 功能描述 (Function)   : 先校验宽度契约，再解析填充字符，然后一次取源长度并与宽度
 *                         比较，按允许与否决定「截断写出」或「拒绝构造」，最后用
 *                         CONCAT 把核心段与填充段拼成恰好 nWidth 个字符的字段。
 *                         典型现场用途：定长报文拼装（固定列宽协议）、CSV 列对齐、
 *                         HMI 固定列显示、条形码定长补位、打印模板的等宽排版。
 * 与既有件边界 (Boundary): FC_DL_StringTrim 去首尾空白、FC_DL_StringSplit 拆分、
 *                         FC_DL_StringReplaceAll 替换。三者都改变内容而不改宽度；
 *                         本件只改宽度与对齐，内容字符顺序不动（除裁剪尾部）。
 *                         宽度是契约参数，本件不猜、不钳、不补零。
 * 设计要点 (Key notes)  : ① 源长度只取一次（R38），其后所有比较与循环上界都用该副本；
 *                         ② 裁剪判定先于任何写入（R37），标志置位先于结果构造；
 *                         ③ 拼装只用 CONCAT 与单字符填充，绝不用取子串的函数去「凑宽度」，
 *                           也不做「先拼后夹」的回夹写法；
 *                         ④ 出口长度天然等于宽度（核心段加填充段恰好补齐），总长不超过
 *                           声明上限，故不存在赋值时的静默截断；
 *                         ⑤ 每次进入先把结果清空，杜绝上一次调用的残留字符。
 *                         ⑥ 纯函数：无内部状态、无跨周期残留，同入参同结果。
 *
 * 【R37 四步顺序（本件样板，调用方照抄即可）】
 *   第 1 步  nSrcLen := LEN(sValue)                         只取一次，锁存
 *   第 2 步  IF nSrcLen > MIN(nWidth, DL_SFF_MAXLEN) THEN  与目标宽度比较（宽度与上限取小）
 *   第 3 步      bTruncated := TRUE                          先置标志，先于任何写入
 *   第 4 步      按 bAllowTrunc 决定截断写出还是拒绝构造     最后才写缓冲
 *
 * 【验收向量 / Acceptance vectors】
 *   V1  源「ABC」、宽度 6、左对齐 → 字段「ABC 加三个空格」、写出 6、不截断
 *   V2  源「ABC」、宽度 6、右对齐 → 字段「三个空格加 ABC」、写出 6
 *   V3  V-B 主向量（R37 核心）：源「ABCDEFGHIJ」、宽度 5、允许截断
 *       → 字段「ABCDE」、截断标志为真、码 0147；裁剪发生必须有人报警
 *   V4  V-B 拒绝路：同源同宽、不允许截断 → 返回假、字段空串、写出 0、码 0148、
 *       截断标志仍为真（事实发生了，只是没写出去）
 *   V5  V-A 域外：宽度 0 或宽度 300 → 返回假、码 0224；宽度不钳位，
 *       因为宽度是契约，猜不得
 *   V6  残留专测：连续两次调用，第二次源为空串 → 字段必须是纯填充，不残留上次内容
 *   V7  V-D 填充字符纠正：填充串为空 → 退回空格并置 0149，字段仍按宽度构造
 *
 * 开源溯源 (Origin)     : 来源标签 lgf-datahandling。LGF（Libre Graphical Framework）
 *                         为免费闭源发布的公开函数库手册，本件仅借鉴其数据处理组
 *                         「定长字段填充与对齐」这一功能分类的存在性，以及「源、宽度、
 *                         填充字符、对齐方式」四参数域的组织方式；许可证按其发布方
 *                         条款仅作分类参考，本件零代码行、零注释、零数据结构引用，
 *                         属 clean-room 独立实现，不构成衍生作品。
 * 码位说明 (Codes)      : 信息 16#0001_0147 已按允许截断 ｜ 16#0001_0148 已拒绝构造
 *                         16#0001_0149 填充串长度已纠正
 *                         故障 16#0001_0224 宽度域外。取号见本轮规格 §3.2。
 *                         码位优先级：0224 最高，其次 0148，再次 0147，最后 0149。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 LEN / MID / CONCAT / MIN。
 * 镜像量清单 (R38)      : nSrcLen 是本件唯一的锁存量，入口一次导出；唯一消费点集中在
 *                         段 4 的比较与段 5 的核心段构造两处，两处读的都是同一个副本，
 *                         全文不再对入参串取长度。
 * 偏离留档 (Deviation)  : 形参的字符串长度用字面量 255 声明，逻辑区用常量
 *                         DL_SFF_MAXLEN 表达同一上界。原因：IEC 的类型声明不接受
 *                         本 POU 内声明的常量，两者必须字面一致，此处已对齐并在
 *                         依赖说明中标注，不构成双源。
 * 红线自检 (Redline)    : 零全局变量表依赖 ｜ 零外部变量声明 ｜ 零物理地址直写
 *                         纯 IEC 61131-3 ｜ 无除法故无除零面 ｜ 循环上界由已钳位标量给定
 *                         全变量双语同行注释 ｜ 状态机 N/A（纯函数）｜ 无定时器实例
 * 修订历史 (Revision)   : 2026-11-15  v1.0.0  首版入库（Round 13 · 泳道 B 定长串族收口）
 *============================================================================*)

(*==============================================================================
 * 拼装示意 (Assembly geometry)，以源「ABC」、宽度 6 为例：
 *   核心段「ABC」长 3，填充段长 6 减 3 等于 3
 *   左对齐：核心段在前，结果为「ABC」加三个填充字符
 *   右对齐：填充段在前，结果为三个填充字符加「ABC」
 *   两者长度都恰好 6，不需要任何回夹，也就不存在「回夹了但没人知道」的面
 *   若源长 10、宽度 5：核心段按字符逐个取前 5 个，裁剪标志在此之前已置真
 *============================================================================*)

FUNCTION FC_DL_StringFixedField : BOOL
VAR_INPUT
    sValue      : STRING(255);      // 源文本 [ASCII]，定长 255 / Source text, fixed 255 characters
    nWidth      : INT;              // 目标字段宽度 [字符]，域 1 到 255，域外直接拒绝 / Target field width, 1 to 255, rejected outside
    sPad        : STRING(1) := ' '; // 填充字符，只取首字符 [字符] / Pad character, only the first character is used
    bAlignRight : BOOL := FALSE;    // 对齐方式，真为右对齐（左补），默认为左对齐 / TRUE right aligns, FALSE left aligns
    bAllowTrunc : BOOL := FALSE;    // 允许截断，真则裁剪写出，假则拒绝构造 / TRUE truncates and writes, FALSE refuses
END_VAR
VAR_OUTPUT
    sField      : STRING(255);      // 定宽字段结果 [ASCII]，成功时长度恰为宽度 / Fixed width field, exactly the width on success
    bTruncated  : BOOL;             // 是否发生裁剪，裁剪发生时必须为真 / Set true whenever truncation happened
    nWritten    : INT;              // 实际字段长度 [字符]，域 0 到 255 / Field length written, 0 to 255
    uErrorId    : UDINT;            // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    sPadChar  : STRING(1);   // 生效填充字符，单字符 [字符] / Effective pad character
    sCore     : STRING(255); // 核心段，裁剪后长度不超过宽度 [ASCII] / Core segment, never longer than the width
    sRun      : STRING(255); // 填充段，长度等于宽度减核心段长 [ASCII] / Pad run, width minus core length
    nSrcLen   : INT;         // 锁存的源文本长度 [字符]，全件唯一消费点 / Latched source length, the single source of truth
    nUse      : INT;         // 核心段实际取用长度 [字符] / Core segment length actually used
    nFill     : INT;         // 填充字符个数 [个] / Number of pad characters
    nPadLen   : INT;         // 填充串声明的实际长度 [字符] / Actual length of the pad string
    nI        : INT;         // 字符构造循环下标 [索引] / Character build loop index
    uCode     : UDINT;       // 码位暂存，出口单点写入 [码] / Code staging, written once at the exit
END_VAR
VAR CONSTANT
    DL_SFF_MAXLEN : INT := 255;   // 定长上限 [字符]，与形参声明一致 / Fixed length limit, matches the declarations
    DL_SFF_ONE    : INT := 1;     // 单字符长度参数 [字符] / Single character length argument
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出预置与残留清除（边界 B1）：结果先清空，杜绝上一次调用的残留字符
 *      Pre-set and clear: the field is emptied so nothing from the previous call survives
 *      这一步必须排在所有分支之前，否则「拒绝构造」路径会露出上一次的旧字段
 *      This must run before any branch, otherwise the refusal path leaks the old field
 *-----------------------------------------------------------------------------*)
FC_DL_StringFixedField := FALSE;
sField      := '';
sCore       := '';
sRun        := '';
sPadChar    := ' ';
bTruncated  := FALSE;
nWritten    := 0;
uErrorId    := 16#0000_0000;
uCode       := 16#0000_0000;
nSrcLen     := 0;
nUse        := 0;
nFill       := 0;
nPadLen     := 0;

(*------------------------------------------------------------------------------
 * 段 2｜宽度闸门（边界 B2）：宽度是契约参数，域外直接拒绝，绝不钳位
 *      Width gate: the width is a contract value, values outside the domain are refused
 *      钳位在这里是最坏的处理方式：调用方以为拿了 5 宽，实际拿到 255 宽，
 *      定长报文的列位会整体后移，且没有任何一条日志能对得上
 *      Clamping would shift every following column of a fixed layout report
 *-----------------------------------------------------------------------------*)
IF (nWidth < 1) OR (nWidth > DL_SFF_MAXLEN) THEN
    uErrorId := 16#0001_0224;   // 故障级：宽度域外，字段保持空串、写出 0
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜填充字符解析（边界 B3）：只取首字符，空串退回空格并报纠正码
 *      Pad resolution: take the first character only, an empty pad falls back to a space
 *-----------------------------------------------------------------------------*)
nPadLen := LEN(sPad);
IF nPadLen >= DL_SFF_ONE THEN
    sPadChar := MID(sPad, DL_SFF_ONE, DL_SFF_ONE);   // 位置 1 起取一个字符 / One character starting at position one
    IF nPadLen <> DL_SFF_ONE THEN
        uCode := 16#0001_0149;   // 信息级：填充串长度不是 1，已取首字符
    END_IF
ELSE
    sPadChar := ' ';             // 空填充串：退回空格，字符本身仍合法
    uCode    := 16#0001_0149;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜源长度一次锁存与裁剪预判（边界 B4，R37 主战场）：先判后写，标志先行
 *      Latch the source length and pre-judge truncation: judge first, flag first
 *      四步顺序不可颠倒：取长度、比较、置标志、再决定写出或拒绝
 *      The four steps are order critical, a reordered version loses the evidence
 *-----------------------------------------------------------------------------*)
nSrcLen := LEN(sValue);
IF nSrcLen < 0 THEN
    nSrcLen := 0;
END_IF

(* 裁剪门限双保险：字段宽度与声明上限同时参与，两者的较小者才是界
 * Double bounded: the smaller of the field width and the declared limit is the bound
 * 宽度已在段 2 限制在 1 到 255，故此处两界等价，写法上把「比长度」这件事显式化 *)
IF nSrcLen > MIN(nWidth, DL_SFF_MAXLEN) THEN

    bTruncated := TRUE;          // 第 3 步：事实先记录，早于任何写入

    IF NOT bAllowTrunc THEN
        (* 第 4 步之拒绝路：不构造字段，把决定权交回调用方 *)
        (* Refusal path: build nothing and leave the decision to the caller *)
        uErrorId := 16#0001_0148;
        RETURN;                  // 字段保持空串，写出保持 0
    END_IF

    uCode := 16#0001_0147;       // 第 4 步之裁剪路：允许截断，码位优先于填充纠正码
    nUse  := nWidth;

ELSE

    nUse := nSrcLen;             // 源不超宽，核心段全取 / The source fits, the whole text is the core

END_IF

(*------------------------------------------------------------------------------
 * 段 5｜核心段构造（边界 B5）：未裁剪直取，裁剪时逐字符取前 nUse 个
 *      Core segment build: assign directly when short enough, else copy character by character
 *      逐个字符取而不是对源取子串后回夹：路径唯一，长度由循环次数决定，
 *      既不依赖平台的子串边界行为，也不会出现「夹了但没报」的第二种写法
 *      Copying per character keeps the length structurally equal to the loop bound
 *-----------------------------------------------------------------------------*)
IF nUse >= nSrcLen THEN
    sCore := sValue;
ELSE
    FOR nI := 1 TO nUse DO
        sCore := CONCAT(sCore, MID(sValue, DL_SFF_ONE, nI));
    END_FOR;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜填充段构造（边界 B6）：个数由宽度减核心段长决定，恒非负
 *      Pad run build: the count is width minus core length, always non-negative
 *      nUse 最大等于 nWidth，故 nFill 最小为 0，循环上界天然合法
 *-----------------------------------------------------------------------------*)
nFill := nWidth - nUse;
IF nFill < 0 THEN
    nFill := 0;                  // 结构性保证已成立，仍显式兜底
END_IF

FOR nI := 1 TO nFill DO
    sRun := CONCAT(sRun, sPadChar);
END_FOR;

(*------------------------------------------------------------------------------
 * 段 7｜拼装与出口（边界 B7）：总长恰为宽度，赋值不存在静默截断
 *      Assembly and exit: the total length equals the width, no silent truncation
 *      核心段长加填充段长恒等于宽度，且宽度已限制在 255 以内
 *      Core plus pad always equals the width, which is already bounded by 255
 *-----------------------------------------------------------------------------*)
IF bAlignRight THEN
    sField := CONCAT(sRun, sCore);
ELSE
    sField := CONCAT(sCore, sRun);
END_IF

nWritten := MIN(nWidth, DL_SFF_MAXLEN);
uErrorId := uCode;               // 码位单点写入，全拍只写一次 / Single write point for the code
FC_DL_StringFixedField := TRUE;
END_FUNCTION
