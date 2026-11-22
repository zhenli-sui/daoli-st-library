(*
    FC_DL_UdintToStringTrim —— UDINT 到定宽十进制字段（右对齐）的防御字符串化
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（UDINT → STRING 定宽右对齐补位，
                委托平台内建 UDINT_TO_STRING 与标准串函数 LEN / LEFT / CONCAT；
                补位、四步截断样板、目标宽度闸、错误分级与码位 100% 自有；
                clean-room 编写，未复制任何闭源厂商源码）
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R69 构建轮 · 批 1 · N3）
    ------------------------------------------------------------------
    功能说明  : R22 定宽字段族的无符号补口。库内已有 FC_DL_DintToStringTrim（有符号，
                去前导空格左对齐）与 FC_DL_LrealToStringTrim（浮点）——本件补 UDINT
                方向，且语义与有符号版**异构**，不可互相替代：
                ① 有符号版做「修剪」（去掉平台补的前导空格后左对齐）；
                   本件做「定宽右对齐」（按目标宽度左补空格，供报表 / 报文定宽字段）。
                ② 上界语义异构：DINT 上界 2147483647 为 10 位数，UDINT 上界
                   4294967295 为 10 位数但**多一个符号位宽**——若把 UDINT 值先转 DINT
                   （现场常见写法），大于 2147483647 的值会翻成负数并输出「-294967296」
                   ！本件全程在 UDINT 域内字符串化，禁止任何有符号中转（R55/R56 口径：
                   浮点 / 有符号 → 无符号必须双分支显式，此处根本不做中转）。
                ③ 目标宽度 uFieldWidth 域 1..32：0 宽度无意义（故障级）；超 32 亦为故障级
                   ——补位源是 32 字符空格常量，宽度超过补位源时 LEFT 会静默返回全长，
                   表现为「字段比要求窄」，故必须在域闸挡住而不得靠钳位；
                   宽度小于实际位数且 bAllowTrunc = FALSE 时返回空串并报故障级，
                   绝不返回半截数值（把 4294967295 写成 429 上位机会当真数据）。
                补位实现：用常量空格串 + LEFT 取 nPad 个 + CONCAT 前缀，禁 WHILE 拼串
                （拼串随长度平方级增长，且串函数异常时会死循环）。
    错误码    : 16#0001_04F8 已按目标宽度左补空格（bPadded 可查）—— 信息级，值可用
                16#0001_04F9 发生截断且 bAllowTrunc = TRUE（bTruncated 可查）—— 信息级，值可用
                16#0001_03FA 目标宽度非法（uFieldWidth = 0）—— 故障级，返回空串
                16#0001_03FB 需要截断但 bAllowTrunc = FALSE —— 故障级，返回空串
    码位总账  : 16#0001_03FA / 03FB 用 ｜ 16#0001_04F8 / 04F9 用
    状态机    : R6 标注 N/A —— 纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 无定时器 / 无沿检测 / 无跨周期状态，结论与任务周期无关
    修订记录  : 2026-11-22 v1.0.0 首次入库（R69 构建轮 · 批 1 · N3）
*)
FUNCTION FC_DL_UdintToStringTrim : STRING(255)
VAR_INPUT
    uIn          : UDINT;                      // 待字符串化的无符号值 [无量纲]，全域 0..4294967295 / unsigned value, full UDINT domain
    uFieldWidth  : USINT := 10;                // 定宽字段宽度 [字符]，域 1..32 / fixed field width [characters], 1 to 32
    bAllowTrunc  : BOOL := FALSE;              // TRUE = 允许截断；FALSE = 需截断即故障 / TRUE allows truncation
END_VAR
VAR_OUTPUT
    eErr         : UDINT;                      // 错误码，0 = 正常 / error id, 0 = ok
    bError       : BOOL;                       // 故障标志，故障级码时为 TRUE / error flag, TRUE on fault level
    bValid       : BOOL;                       // 返回值是否可用（故障级为 FALSE）/ return usable, FALSE on fault level
    bPadded      : BOOL;                       // 本次做了左补空格 / left padding happened
    bTruncated   : BOOL;                       // 本次发生截断 / truncation happened
END_VAR
VAR CONSTANT
    DL_US_CAP    : INT := 255;                 // STRING 型长度上限 [字符]（R49 口径）/ STRING capacity [characters]
    DL_US_W_MIN  : USINT := 1;                 // 目标宽度下限 [字符] / field width floor [characters]
    DL_US_W_MAX  : INT := 32;                  // 目标宽度上限 [字符]，等于补位源空格串长度（超此宽度补位不可信）/ width ceiling [characters]
    DL_US_BLANKS : STRING(32) := '                                ';  // 32 个空格常量，补位源 [字符] / 32 blanks, the padding source
    DL_US_EMPTY  : STRING(1) := '';            // 空串常量，故障缺省返回 / empty string returned on faults
    DL_US_ZERO   : INT := 0;                   // 整型零常量，避免裸字面量 [字符] / integer zero constant
END_VAR
VAR
    sRaw         : STRING(255);                // 内建字符串化原始结果 / raw result of the built-in conversion
    sPad         : STRING(32);                 // 左补空格串 / left padding string
    sOut         : STRING(255);                // 最终输出串 / final output string
    nLen         : INT;                        // 原始串有效长度，一次锁存 [字符] / latched raw length [characters]
    nWidth       : INT;                        // 目标宽度，由引脚转出 [字符] / target width from the pin [characters]
    nPad         : INT;                        // 需要补的空格个数 [字符] / number of blanks to add
END_VAR

// 段 1｜返回值与错误状态预置（实战规则 1①）/ segment 1, preset the return value and the status
FC_DL_UdintToStringTrim := DL_US_EMPTY;   // 故障缺省返回空串 / fault default returns an empty string
eErr       := 0;                          // 预置无错误 / preset no error
bError     := FALSE;                      // 预置无故障 / preset no fault
bValid     := FALSE;                      // 预置不可用 / preset unusable
bPadded    := FALSE;                      // 预置未补位 / preset unpadded
bTruncated := FALSE;                      // 预置未截断 / preset untruncated

// 段 2｜目标宽度闸：0 宽度无意义，先判后算 / segment 2, field width gate
IF uFieldWidth < DL_US_W_MIN THEN
    eErr   := 16#0001_03FA;               // 故障级：目标宽度非法 / fault level: illegal field width
    bError := TRUE;                       // R45 配对 / paired with the code
    bValid := FALSE;                      // 返回值不可用 / return unusable
    RETURN;                               // 出口，不触碰内建 / exit, the built-in is never touched
END_IF
nWidth := USINT_TO_INT(uFieldWidth);      // 宽度转整型 [字符] / width to INT [characters]
IF nWidth > DL_US_W_MAX THEN
    eErr   := 16#0001_03FA;               // 故障级：宽度超补位源上限（32），补位不可信 / fault level: width above the padding source
    bError := TRUE;                       // R45 配对 / paired with the code
    bValid := FALSE;                      // 返回值不可用 / return unusable
    RETURN;                               // 出口 / exit
END_IF

// 段 3｜主体：委托平台内建字符串化（全程无有符号中转）/ segment 3, delegate the built-in in the unsigned domain
sRaw := UDINT_TO_STRING(uIn);             // 无符号值 → 原始串，绝不先转 DINT（反例会输出负数）/ unsigned to string, never via DINT
nLen := LEN(sRaw);                        // 原始串长度，一次锁存 [字符] / latch the size exactly once [characters]
IF nLen > DL_US_CAP THEN
    nLen := DL_US_CAP;                    // 超容量按上限钳位 [字符] / clamp to the capacity [characters]
ELSIF nLen < DL_US_ZERO THEN
    nLen := DL_US_ZERO;                   // 负长度防御，结构性不可达 [字符] / negative length guard, unreachable
END_IF

// 段 4｜四步截断样板（R37）：长度已锁存 → 宽度比较 → 标志先置 → 按允许分路
// segment 4, the four-step truncation pattern: latch, compare, flag first, then branch
IF nLen > nWidth THEN
    bTruncated := TRUE;                   // 标志先于任何写入 / the flag precedes every write
    IF bAllowTrunc THEN
        sOut := LEFT(sRaw, nWidth);       // 允许截断：按宽度截取 / truncation allowed, take the width
        eErr := 16#0001_04F9;             // 信息级：发生截断，值可用 / info level: truncated, still usable
    ELSE
        eErr   := 16#0001_03FB;           // 故障级：需截断但未允许 / fault level: truncation needed but not allowed
        bError := TRUE;                   // R45 配对 / paired with the code
        bValid := FALSE;                  // 返回值不可用 / return unusable
        FC_DL_UdintToStringTrim := DL_US_EMPTY;   // 返回空串，绝不返回半截数值 / never a partial number
        RETURN;                           // 出口 / exit
    END_IF
ELSE
    // 段 5｜右对齐补位：nPad = 宽度 − 位数，LEFT 取空格 + CONCAT 前缀 / segment 5, right-align padding
    nPad := nWidth - nLen;                // 需要补的空格数 [字符] / blanks to add [characters]
    IF nPad > DL_US_ZERO THEN
        sPad := LEFT(DL_US_BLANKS, nPad); // 取 nPad 个空格（禁 WHILE 拼串）/ take the blanks with LEFT
        sOut := CONCAT(sPad, sRaw);       // 空格前缀 + 原始串 = 定宽右对齐 / padding plus the raw string
        bPadded := TRUE;                  // 补位发生 / padding happened
        eErr    := 16#0001_04F8;          // 信息级：已按宽度左补空格 / info level: left padded to the width
    ELSE
        sOut := sRaw;                     // 位数恰等于宽度：直通，无码 / exactly the width, no code
    END_IF
END_IF

// 段 6｜发布结果 / segment 6, publish the result
FC_DL_UdintToStringTrim := sOut;          // 输出最终串 / publish the final string
bValid := TRUE;                           // 补位 / 截断 / 直通三条路径均可用 / usable in every published path
bError := FALSE;                          // 信息级不置故障（双保险）/ info level never raises a fault
END_FUNCTION
