(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringToLReal
 * 所属子库 (Sublibrary) : DL_MathData
 * 归属目录 (Directory)  : C:\Library\DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 函数（FUNCTION）· 纯函数 · 带校验的数值解析
 *                         lgf-datahandling / string-parse / validated-conversion
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 LEN / MID /
 *                         FIND / LIMIT / MIN / MAX，无厂商串转换函数依赖
 * 功能一句话 (Summary)  : 把定长 ASCII 文本严格解析成 LREAL，逐字符推进，拒绝一切
 *                         可疑输入，并报出首个非法字符的位置。
 * 功能描述 (Function)   : 语法为「可选符号、整数部、可选小数部、可选指数部」。解析
 *                         过程不调用平台的隐式串转数值功能，全部字符自行判定与推进，
 *                         因此三重收益：① 非法输入的行为在三家平台上完全一致；
 *                         ② 出错时能回答「错在第几个字符」，而不是只给一个零；
 *                         ③ 前缀合法、尾部夹脏字符时仍给出前缀值，方便现场判断是
 *                         报文截断还是字段串位。典型现场用途：条码与二维码文本入库、
 *                         CSV 报文列解析、HMI 手输设定值校验、第三方仪表 ASCII 应答
 *                         的数值字段提取。
 * 为什么自带解析 (Why)  : 三家平台对「字符串转实数」的非法输入行为不一致：有的返回
 *                         零、有的抛异常、有的静默截断，且都不告诉调用方错在第几位。
 *                         现场最贵的不是「转换失败」，而是「转换成功了但值不对」。
 * 与既有件边界 (Boundary): FC_DL_HexStringToBytes 处理十六进制到字节；本件处理十进制
 *                         文本到实数。二者共用「逐字符判定、失败保留前缀信息」的
 *                         口径，但字符集与输出类型完全不同，不重叠。
 * 设计要点 (Key notes)  : ① 长度一次锁存：入口取 LEN 存成局部量，其后所有循环上界、
 *                           下标判断、消费计数全部取自该副本，全文不再读入参长度；
 *                         ② 逐字符推进，不用任何回夹写法拼结果，也不靠平台转换函数；
 *                         ③ 先用状态推进做完语法判定，再统一做数值定稿，因此「语法
 *                           错误」与「数值越界」两类事件不会互相覆盖；
 *                         ④ 出口夹域：无论成功失败，fValue 一定落在调用方给定的
 *                           上下限之间，绝不输出无穷或非数；
 *                         ⑤ 纯函数：无内部状态、无跨周期残留，同入参同结果。
 *
 * 【解析状态映射表 / Parse phase map】
 *   起始态 0 期待符号、数字或小数点 ｜ 符号态 1 符号已取 ｜ 整数态 2 整数位推进
 *   小数态 3 小数位推进 ｜ 指数标记态 4 已见指数标记 ｜ 指数符号态 5 指数符号已取
 *   指数数字态 6 指数位推进。每个状态接受的输入集合在段 3 逐个分支写明，
 *   未列出的组合一律判非法字符，不存在「落到默认分支继续跑」的可能。
 *
 * 【验收向量 / Acceptance vectors】
 *   V1  文本「负号 1 2 点 5」→ 返回真、值 负 12.5、消费 5 字符、首错位 0
 *   V2  V-B 指数开关：文本「1 点 5 E 3」允许指数 → 1500.0；
 *       禁止指数 → 返回假、首错位 4、码 0144、值保留前缀 1.5
 *   V3  V-A 域外：文本「1 2 点 5 点 3」→ 返回假、码 0222、首错位 5、消费 4 字符
 *   V4  V-B 上限：文本「1 E 4 0」→ 返回假、码 0146、值夹到上限 1.0E30（不输出无穷）
 *   V5  V-C 锁存专测（R38）：调用方在本件返回后立即改写文本缓冲，本件内部所有边界
 *       都来自入口锁存的长度，结果不受影响；纯函数天然满足，此处作为纪律声明
 *   V6  V-D 出口夹域：文本「1 E 3 0」且上限 100 → 返回真、值 100.0、码 0145
 *   V7  全空白文本 → 返回假、码 0143、消费 0 字符、值 0.0
 *
 * 开源溯源 (Origin)     : 来源标签 lgf-datahandling。LGF（Libre Graphical Framework）
 *                         为免费闭源发布的公开函数库手册，本件仅借鉴其数据处理组
 *                         「字符串与数值互转按类型分函数、单一职责」的组织方式，以及
 *                         「带校验的转换器」这一功能分类的存在性；许可证按其发布方
 *                         条款仅作分类参考，本件零代码行、零注释、零数据结构引用，
 *                         属 clean-room 独立实现，不构成衍生作品。
 * 码位说明 (Codes)      : 信息 16#0001_0143 空或无有效数字 ｜ 16#0001_0144 尾随非法字符
 *                         16#0001_0145 结果已夹域 ｜ 16#0001_0146 指数超出保护域
 *                         故障 16#0001_0222 小数点重复 ｜ 16#0001_0223 结果非有限。
 *                         取号见本轮规格 §3.2，与 CRC8 子族 0141 到 0142 不重叠。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 LEN / MID / FIND /
 *                         LIMIT / MIN / MAX 与 INT_TO_LREAL 显式转换。
 * 镜像量清单 (R38)      : nLen 是本件唯一的锁存量，入口一次导出；唯一消费点集中在
 *                         段 2 的全空白预扫、段 3 的循环上界、段 5 的消费计数三处，
 *                         三处读的都是同一个局部副本，全文不再对入参串取长度。
 * 契约前置条件 (Contract): fMin 与 fMax 必须为有限值；两者倒置时按 MIN / MAX 自动
 *                         归正，不报错也不新增码位（上下限属组态参数，非运行数据）。
 * 偏离留档 (Deviation)  : 形参的字符串长度用字面量 40 声明，逻辑区用常量 DL_S2N_MAXLEN
 *                         表达同一上界。原因：IEC 的类型声明不接受本 POU 内声明的常量，
 *                         两者必须字面一致，此处已对齐，不构成双源。
 * 红线自检 (Redline)    : 零全局变量表依赖 ｜ 零外部变量声明 ｜ 零物理地址直写
 *                         纯 IEC 61131-3 ｜ 每处除法前判除数下限 ｜ 循环上界全常量化
 *                         全变量双语同行注释 ｜ 状态机 N/A（纯函数）｜ 无定时器实例
 * 修订历史 (Revision)   : 2026-11-15  v1.0.0  首版入库（Round 13 · 泳道 B 定长串族收口）
 *============================================================================*)

(*==============================================================================
 * 逐字符推演 (Character walk-through)，以「1 2 点 5 点 3」为例：
 *   第 1 字符 数字 1，由起始态进入整数态，尾数 1，有效位计数 1
 *   第 2 字符 数字 2，整数态继续，尾数 12，有效位计数 2
 *   第 3 字符 小数点，由整数态进入小数态，小数点计数 1
 *   第 4 字符 数字 5，小数态累加，尾数 125，小数位计数 1
 *   第 5 字符 小数点，当前已在小数态，小数点计数变 2，判定重复，停在第 5 位
 *   消费字符数为 4，首错位为 5，值按尾数 125 除以 10 得 12.5 保留
 *   若调用方只看返回值会以为「全错」，看值与位置才知道是小数点写了两遍
 *============================================================================*)

FUNCTION FC_DL_StringToLReal : BOOL
VAR_INPUT
    sText     : STRING(40);         // 待解析文本 [ASCII]，定长 40，冗余位填空格或空 / Text to parse, fixed length 40
    bAllowExp : BOOL := TRUE;       // 允许指数部，真则接受大写或小写 E / Allow the exponent part, both cases accepted
    fMin      : LREAL := -1.0E30;   // 输出下限 [工程单位]，越限钳位 / Lower clamp in engineering units
    fMax      : LREAL := 1.0E30;    // 输出上限 [工程单位]，越限钳位 / Upper clamp in engineering units
END_VAR
VAR_OUTPUT
    fValue    : LREAL;              // 解析结果 [工程单位]，失败时保留已解析前缀值 / Parsed value, keeps the parsed prefix on failure
    nCharUsed : INT;                // 已消费字符数 [个]，域 0 到 40 / Characters consumed, 0 to 40
    nBadPos   : INT;                // 首个非法字符位置 [位]，1 起，0 表示全部合法 / First invalid position, one based, zero when clean
    uErrorId  : UDINT;              // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    nLen        : INT;              // 锁存的文本有效长度 [字符]，全件唯一消费点 / Latched text length, the single source of truth
    nPos        : INT;              // 字符扫描下标 [位]，1 起 / Character scan index, one based
    nI          : INT;              // 通用循环下标，用于预扫与幂次循环 [索引] / Generic loop index for the pre-scan and power loop
    nState      : INT;              // 解析阶段号 [态]，取值含义见头注释映射表 / Parse phase number, see the map in the header
    sChar       : STRING(1);        // 当前字符，由标准 MID 取出 [字符] / Current character read with the standard MID
    nDigit      : INT;              // 当前字符的数字值 [数]，非数字为负 1 / Digit value of the current character, minus one when not a digit
    fMant       : LREAL;            // 尾数累加值，按十进制逐位左移再加 [无量纲] / Mantissa accumulator
    nSig        : INT;              // 已累加的有效数字位数 [个]，有上限保护 / Accumulated significant digits, capped
    nFrac       : INT;              // 已累加的小数位数 [个]，决定尺度分母 / Accumulated fractional digits, drives the scale divisor
    nExp        : INT;              // 指数绝对值累加 [无量纲]，最多取三位 / Exponent magnitude, at most three digits
    nExpDig     : INT;              // 已累加的指数位数 [个] / Accumulated exponent digit count
    nDotCnt     : INT;              // 小数点出现次数 [次]，用于重复判定 / Decimal point occurrences
    bSign       : BOOL;             // 尾数符号，真为负 / Mantissa sign, true means negative
    bExpSign    : BOOL;             // 指数符号，真为负 / Exponent sign, true means negative
    bOk         : BOOL;             // 语法与数值均通过标记 / Syntax and numeric checks passed
    bStop       : BOOL;             // 扫描停止标记，遇首个错误后置真 / Scan stop flag, set at the first error
    bAnyVisible : BOOL;             // 文本含至少一个非空白字符标记 / At least one non blank character present
    fDiv        : LREAL;            // 小数尺度分母 [无量纲] / Fractional scale divisor
    fPow        : LREAL;            // 指数幂次中间量 [无量纲] / Exponent power accumulator
    nAbsExp     : INT;              // 指数绝对值 [无量纲]，用于幂次循环次数 / Absolute exponent, drives the power loop
    fLo         : LREAL;            // 归一后的出口下限 [工程单位] / Normalised lower bound
    fHi         : LREAL;            // 归一后的出口上限 [工程单位] / Normalised upper bound
    uCode       : UDINT;            // 码位暂存，出口单点写入 [码] / Code staging, written once at the exit
END_VAR
VAR CONSTANT
    DL_S2N_MAXLEN  : INT := 40;                     // 文本长度上限 [字符]，与形参声明一致 / Text length limit, matches the declaration
    DL_S2N_SIGMAX  : INT := 18;                     // 有效数字累加上限 [位]，覆盖双精度可表示精度 / Significant digit cap
    DL_S2N_EXPMAX  : INT := 38;                     // 指数绝对值上限 [无量纲]，超出转保护域 / Exponent magnitude limit
    DL_S2N_TEN     : LREAL := 10.0;                 // 十进制基数 [无量纲] / Decimal radix
    DL_S2N_FINITE  : LREAL := 1.0E308;              // 有限性上界 [无量纲]，用于拦无穷与非数 / Finiteness bound
    DL_S2N_DIGITS  : STRING := '0123456789';        // 数字字符表，用 FIND 定位取数值 / Digit table queried with FIND
    DL_S2N_ST_START : INT := 0;                     // 起始态，期待符号、数字或小数点 / Start phase
    DL_S2N_ST_SIGN  : INT := 1;                     // 符号态，尾数符号已取 / Mantissa sign phase
    DL_S2N_ST_INT   : INT := 2;                     // 整数态，整数位推进 / Integer phase
    DL_S2N_ST_FRAC  : INT := 3;                     // 小数态，小数位推进 / Fraction phase
    DL_S2N_ST_E     : INT := 4;                     // 指数标记态，已见指数标记 / Exponent marker phase
    DL_S2N_ST_ESIGN : INT := 5;                     // 指数符号态，指数符号已取 / Exponent sign phase
    DL_S2N_ST_EDIG  : INT := 6;                     // 指数数字态，指数位推进 / Exponent digit phase
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出预置：值、消费数、首错位、码位全部先落确定值
 *      Pre-set the outputs so every exit path publishes a deterministic result
 *-----------------------------------------------------------------------------*)
FC_DL_StringToLReal := FALSE;
fValue      := 0.0;
nCharUsed   := 0;
nBadPos     := 0;
uErrorId    := 16#0000_0000;
uCode       := 16#0000_0000;
nState      := DL_S2N_ST_START;
sChar       := '';
nDigit      := -1;
fMant       := 0.0;
nSig        := 0;
nFrac       := 0;
nExp        := 0;
nExpDig     := 0;
nDotCnt     := 0;
bSign       := FALSE;
bExpSign    := FALSE;
bOk         := FALSE;
bStop       := FALSE;
bAnyVisible := FALSE;
fDiv        := 1.0;
fPow        := 1.0;
nLen        := 0;

(*------------------------------------------------------------------------------
 * 段 2｜长度一次锁存与空文本判定（边界 B1）
 *      Latch the length once and reject empty or blank-only text
 *      锁存后所有边界判断只用 nLen，不再读入参串，这是纪律不是偏好：
 *      分拍处理时入参可能被别的任务改写，混用两种来源会切出「有效但为空」的假段
 *      Every later boundary uses the latched copy only, never the live parameter
 *-----------------------------------------------------------------------------*)
nLen := LEN(sText);
IF nLen < 0 THEN
    nLen := 0;
ELSIF nLen > DL_S2N_MAXLEN THEN
    nLen := DL_S2N_MAXLEN;
END_IF

IF nLen = 0 THEN
    uErrorId := 16#0001_0143;   // 信息级：空文本，无有效数字
    RETURN;
END_IF

FOR nI := 1 TO nLen DO
    sChar := MID(sText, 1, nI);
    IF (sChar <> ' ') AND (sChar <> '$09') AND (sChar <> '$0D') AND (sChar <> '$0A') THEN
        bAnyVisible := TRUE;    // 见到任意非空白字符即可停止判定目的 / Any visible character clears the all blank case
    END_IF
END_FOR;

IF NOT bAnyVisible THEN
    uErrorId := 16#0001_0143;   // 信息级：全空白文本，与空文本同码
    RETURN;
END_IF

bOk := TRUE;   // 语法判定从真开始，逐字符推进，遇错置假 / Starts true, each character may clear it

(*------------------------------------------------------------------------------
 * 段 3｜逐字符推进（边界 B2/B3/B4）：字符分四类处理，非数字非符号非点全判非法
 *      Character walk: four classes handled, anything else is illegal
 *      顺序硬约束：先判小数点（它改变状态），再判数字（它可能刚进入状态），
 *      再判符号（只在起始或指数标记之后合法），最后兜底一切其它字符
 *      Order matters: point first, then digit, then sign, then the catch-all
 *-----------------------------------------------------------------------------*)
FOR nPos := 1 TO nLen DO

    IF NOT bStop THEN

        sChar  := MID(sText, 1, nPos);
        nDigit := FIND(DL_S2N_DIGITS, sChar) - 1;   // 命中为 0 到 9，未命中为负 1

        IF sChar = '.' THEN
            (* 小数点只允许出现在起始、符号后、整数部之后；在小数态再次出现即重复 *)
            (* A decimal point is legal at the start, after a sign, or once after the integer part *)
            IF (nState = DL_S2N_ST_START) OR (nState = DL_S2N_ST_SIGN) OR (nState = DL_S2N_ST_INT) THEN
                nState  := DL_S2N_ST_FRAC;
                nDotCnt := nDotCnt + 1;
            ELSIF nState = DL_S2N_ST_FRAC THEN
                nDotCnt  := nDotCnt + 1;
                bOk      := FALSE;
                bStop    := TRUE;
                nBadPos  := nPos;
                nCharUsed := nPos - 1;
                uCode    := 16#0001_0222;   // 故障级：小数点重复
            ELSE
                bOk      := FALSE;
                bStop    := TRUE;
                nBadPos  := nPos;
                nCharUsed := nPos - 1;
                uCode    := 16#0001_0144;   // 信息级：小数点出现在指数部
            END_IF

        ELSIF nDigit >= 0 THEN
            (* 数字在起始态或符号态出现，即进入整数部；在指数标记或指数符号后出现，进入指数数字态 *)
            (* A digit after the start or the sign opens the integer part, after a marker it opens the exponent *)
            IF (nState = DL_S2N_ST_START) OR (nState = DL_S2N_ST_SIGN) THEN
                nState := DL_S2N_ST_INT;
            ELSIF (nState = DL_S2N_ST_E) OR (nState = DL_S2N_ST_ESIGN) THEN
                nState := DL_S2N_ST_EDIG;
            END_IF

            IF nState = DL_S2N_ST_EDIG THEN
                IF nExpDig < 3 THEN
                    nExp    := nExp * 10 + nDigit;
                    nExpDig := nExpDig + 1;
                END_IF
            ELSE
                IF nSig < DL_S2N_SIGMAX THEN
                    fMant := fMant * DL_S2N_TEN + INT_TO_LREAL(nDigit);
                    nSig  := nSig + 1;
                    IF nState = DL_S2N_ST_FRAC THEN
                        nFrac := nFrac + 1;
                    END_IF
                END_IF
            END_IF

        ELSIF (sChar = '+') OR (sChar = '-') THEN
            (* 符号只在起始位置（尾数符号）或指数标记之后（指数符号）合法 *)
            (* A sign is legal only at the start or right after the exponent marker *)
            IF nState = DL_S2N_ST_START THEN
                bSign  := (sChar = '-');
                nState := DL_S2N_ST_SIGN;
            ELSIF nState = DL_S2N_ST_E THEN
                bExpSign := (sChar = '-');
                nState   := DL_S2N_ST_ESIGN;
            ELSE
                bOk      := FALSE;
                bStop    := TRUE;
                nBadPos  := nPos;
                nCharUsed := nPos - 1;
                uCode    := 16#0001_0144;   // 信息级：符号位置非法
            END_IF

        ELSIF (sChar = 'E') OR (sChar = 'e') THEN
            (* 指数标记只允许紧跟尾数，且必须由开关放行；未放行时按尾随非法字符处理 *)
            (* The marker must follow the mantissa and must be enabled, otherwise it counts as trailing garbage *)
            IF ((nState = DL_S2N_ST_INT) OR (nState = DL_S2N_ST_FRAC)) AND bAllowExp THEN
                nState := DL_S2N_ST_E;
            ELSE
                bOk      := FALSE;
                bStop    := TRUE;
                nBadPos  := nPos;
                nCharUsed := nPos - 1;
                uCode    := 16#0001_0144;
            END_IF

        ELSE
            (* 兜底：空格、制表、回车、换行、货币符号、千分位逗号等一律判非法 *)
            (* Catch-all: blanks, tabs, carriage returns, currency signs and thousands separators are illegal *)
            bOk      := FALSE;
            bStop    := TRUE;
            nBadPos  := nPos;
            nCharUsed := nPos - 1;
            uCode    := 16#0001_0144;
        END_IF

    END_IF

END_FOR;

(*------------------------------------------------------------------------------
 * 段 4｜终态校验（边界 B5）：必须收在整数态、小数态或指数数字态，且至少一位数字
 *      Final phase check: must end inside a digit bearing phase with at least one digit
 *      只有符号、只有小数点、只有指数标记这三种「半截输入」在此统一拦下
 *      Half finished inputs such as a lone sign or a lone point are stopped here
 *-----------------------------------------------------------------------------*)
IF bOk THEN
    (* 正向条件写成「非合法终态」，避免在合法分支里做无意义的自我赋值 *)
    (* Written as a negative test so the legal branch needs no self assignment *)
    IF NOT ((((nState = DL_S2N_ST_INT) OR (nState = DL_S2N_ST_FRAC)) AND (nSig > 0))
        OR ((nState = DL_S2N_ST_EDIG) AND (nExpDig > 0))) THEN
        bOk       := FALSE;
        nBadPos   := 0;
        nCharUsed := 0;
        uCode     := 16#0001_0143;   // 信息级：无完整数字
    ELSE
        nCharUsed := nLen;           // 全部字符合法消费 / Every character was legally consumed
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜数值定稿（边界 B6/B7）：尺度、指数、符号三步依次作用，前缀值同样成立
 *      Numeric finalisation: scale, exponent and sign applied in that order
 *      语法失败时本段照跑：前缀值可能就是现场要的东西，丢掉它等于丢掉证据
 *      This stage runs even after a syntax error, the prefix value is evidence
 *-----------------------------------------------------------------------------*)
fValue := fMant;

fDiv := 1.0;
FOR nI := 1 TO nFrac DO
    fDiv := fDiv * DL_S2N_TEN;       // 分母最大 1.0E18，必然有限 / The divisor stays finite
END_FOR;
IF fDiv > 0.0 THEN
    fValue := fValue / fDiv;         // 判零后再除，除数恒不小于 1.0 / Guarded division, the divisor is at least one
END_IF

nAbsExp := nExp;   // 指数幅度：nExp 累加时只进正值，正负由 bExpSign 单独承担 / Magnitude only, the sign lives in bExpSign

IF nAbsExp > DL_S2N_EXPMAX THEN
    (* 指数超保护域：正向溢出落到有限极值，负向下溢落到零，两者都不输出无穷或非数 *)
    (* Exponent beyond the guard band: overflow lands on the finite bound, underflow on zero *)
    IF bExpSign THEN
        fValue := 0.0;               // 下溢：数值已小于可表示下限 / Underflow, the value collapsed
    ELSE
        fValue := DL_S2N_FINITE;     // 上溢：先落到有限上界 / Overflow, land on the finite bound
    END_IF
    IF uCode = 16#0000_0000 THEN
        uCode := 16#0001_0146;
    END_IF
    bOk := FALSE;
ELSIF nAbsExp > 0 THEN
    (* 指数在保护域内：正向做乘法，负向做判零后的除法，幂次循环上界不超过上限常量 *)
    (* Inside the guard band: multiply for a positive exponent, guarded divide for a negative one *)
    fPow := 1.0;
    FOR nI := 1 TO nAbsExp DO
        fPow := fPow * DL_S2N_TEN;
    END_FOR;
    IF bExpSign THEN
        IF fPow > 0.0 THEN
            fValue := fValue / fPow; // 判零后再除，除数恒不小于 10.0 / Guarded division, the divisor is at least ten
        END_IF
    ELSE
        fValue := fValue * fPow;
    END_IF
END_IF

IF bSign THEN
    fValue := -fValue;               // 符号最后作用，指数与尺度都不带符号 / The sign is applied last
END_IF

(* 有限性检查：两个比较同时成立才算有限，非数会让两个比较都为假，故此式一并拦截
 * Finiteness check: both comparisons must hold, a not-a-number fails both, so it is caught too *)
IF NOT ((fValue <= DL_S2N_FINITE) AND (fValue >= -DL_S2N_FINITE)) THEN
    bOk := FALSE;
    IF uCode = 16#0000_0000 THEN
        uCode := 16#0001_0223;       // 故障级：结果非有限
    END_IF
    fValue := 0.0;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜出口夹域（边界 B8，R43 精神）：值必须落在调用方给定区间内
 *      Exit clamp: the value always lands inside the caller supplied range
 *      上下限倒置时按 MIN / MAX 归正，组态笔误不应让输出跑到域外
 *      Inverted bounds are normalised with MIN and MAX, the output never leaves the domain
 *-----------------------------------------------------------------------------*)
fLo := MIN(fMin, fMax);
fHi := MAX(fMin, fMax);

IF fValue < fLo THEN
    fValue := fLo;
    IF uCode = 16#0000_0000 THEN
        uCode := 16#0001_0145;
    END_IF
ELSIF fValue > fHi THEN
    fValue := fHi;
    IF uCode = 16#0000_0000 THEN
        uCode := 16#0001_0145;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜码位单点写入与返回判定
 *      Single write point for the code and the return decision
 *      返回真仅限「语法通过且无码或仅夹域」；夹域后值仍可直接使用，故不判失败
 *      True only when the syntax passed and either no code or a clamp-only code
 *-----------------------------------------------------------------------------*)
uErrorId := uCode;
FC_DL_StringToLReal := bOk AND ((uCode = 16#0000_0000) OR (uCode = 16#0001_0145));
END_FUNCTION
