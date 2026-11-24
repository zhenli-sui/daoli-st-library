(*
    FC_DL_LrealToStringTrim —— LREAL 到 STRING 的防御字符串化（非有限值统一文本）
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.1
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（LREAL → STRING，非有限值统一文本）；
                委托平台内建 LREAL_TO_STRING 与标准串函数 LEN / MID / LEFT，本件不重实现格式化内核；
                非有限值判据与统一文本、空格修剪、四步截断样板、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 趋势记录、报警文本、报表导出都要把模拟量序列化成文本。有限值的宽度与小数位
                各平台本就不一，非有限值更糟：NaN 在有的平台是 'NaN'，有的是 '1.#QNAN'，
                ±Inf 有 'INF' / 'Infinity' / '1.#INF' / 乱码多种结果，上位机按字符串比对必然漏判。
                核心防御：① 非有限值不走内建转换，直接映射成本库统一的三个字面量
                   'NaN' / 'Inf+' / 'Inf-'：统一文本是可用输出而非故障，故发信息级、
                   bValid 仍为 TRUE——把 NaN 判成故障级会让一个采样坏点牵动整条报警链；
                ② NaN 判定用自反性（x <> x），Inf 判定用「x−x 产 NaN」精确判据 + LREAL
                   最大值幅值兜底，两判据分开置位：
                   IEEE 754 里 NaN 与任何值（含自身）比较均为假，任何容差比较对 NaN 恒假，
                   只能用自反性判据——这是本库浮点判等「一律用 ABS 容差」规则的唯一例外，
                   其余浮点比较（如符号判定）均不做判等；
                   无穷判据同源：任何有限值 x−x 恒为 0（0 <> 0 为假），无穷处 x−x 产 NaN
                   （NaN <> NaN 为真）。R20 终审修正：原判据用幅值阈值 1.79E308，该值落在
                   LREAL 可表域内，会把 [1.79E308, LREAL 最大值] 的合法有限值误判成无穷；
                   现改双判据，幅值兜底阈值提到 LREAL 最大值，残余仅剩「恰为最大值」单值；
                ③ 有限值走内建 + 空格修剪 + 四步截断样板（R37），与整型件同一口径；
                ④ 目标长度 0 结构性钳到 1 字符：零长度目标无意义，
                   钳位后必然触发截断分支，事件由 bTruncated 与信息码体现，不静默。
                职责边界：DINT 字符串化归 FC_DL_DintToStringTrim；字符串转回数值归
                FC_DL_StringToLReal；本件只管 LREAL 方向。
    编译门槛  : 主路径依赖平台内建 LREAL_TO_STRING 与标准串函数 LEN / MID / LEFT。
                LREAL_TO_STRING 的有效位数与宽度平台间不同，故本件不假设宽度，
                一律 LEN 实测后按目标长度钳位；幅值兜底阈值取 LREAL 最大值
                1.7976931348623157E308（不是 1.79E308——后者在 LREAL 域内，会把
                极大有限值误判为无穷，R20 终审修正）。
    错误码    : 16#0001_0428 非有限值已映射统一文本（bNonFinite 可查）——信息级，值可用
                16#0001_0429 发生空格修剪或截断——信息级，值可用
                16#0001_035A 需要截断但 bAllowTrunc = FALSE——故障级，返回空串
                16#0001_035B 预留（故障级，不得挪用）
                16#0001_035C 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0428 用 / 16#0001_0429 用 ｜ 16#0001_035A 用 / 16#0001_035B 预留 / 16#0001_035C 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
                2026-11-16 v1.0.1 R20 终审修正：无穷幅值判据阈值由 1.79E308 改为 LREAL 最大值
                 并补 x−x 精确判据，消除极大有限值被误判为 'Inf+' 的缺陷；对外引脚零变更
*)
FUNCTION FC_DL_LrealToStringTrim : STRING(255)
VAR_INPUT
    fIn              : LREAL;                 // 待字符串化的数值 [无量纲]，全域（含 NaN 与 ±Inf）/ value to serialise [dimensionless], full domain including NaN and infinities
    uTargetMax       : USINT := 31;           // 目标缓冲可用长度 [字符]，1~255 / usable target length [characters], 1 to 255
    bAllowTrunc      : BOOL := FALSE;         // TRUE = 允许截断；FALSE = 需截断即故障 / TRUE allows truncation, FALSE turns it into a fault
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid           : BOOL;                  // 返回值是否可用（故障级为 FALSE）/ return usable, FALSE on fault level
    bNonFinite       : BOOL;                  // 输入为非有限值（NaN 或 ±Inf）/ the input is non-finite, NaN or an infinity
    bTrimmed         : BOOL;                  // 修剪了前导空格 / leading blanks were trimmed
    bTruncated       : BOOL;                  // 超目标长度发生截断 / truncation to the target length happened
END_VAR
VAR CONSTANT
    DL_STR_CAP_MAX   : USINT := 255;          // STRING 型长度上限 [字符]，R49 口径 / STRING capacity [characters], per R49
    DL_STR_TARGET_MIN : USINT := 1;           // 目标长度下限 [字符] / target length lower bound [characters]
    DL_STR_SCAN_MAX  : INT := 255;            // 扫描上界 [字符]，与 STRING 上限一致 / scan bound [characters], equals the STRING capacity
    DL_STR_BLANK     : STRING(1) := ' ';      // 单个空格字符，修剪判据 / a single blank used by the trim test
    DL_STR_EMPTY     : STRING(1) := '';       // 空串常量，故障缺省返回 / empty string returned on faults
    DL_STR_NAN       : STRING(3) := 'NaN';    // 统一 NaN 文本 / the unified NaN text
    DL_STR_INF_POS   : STRING(4) := 'Inf+';   // 统一正无穷文本 / the unified positive infinity text
    DL_STR_INF_NEG   : STRING(4) := 'Inf-';   // 统一负无穷文本 / the unified negative infinity text
    DL_LREAL_INF_ABS : LREAL := 1.7976931348623157E308; // 无穷幅值兜底阈值＝LREAL 最大值 [无量纲] / fallback magnitude threshold equal to the LREAL maximum [dimensionless]
    DL_LREAL_ZERO    : LREAL := 0.0;          // 浮点零常量，符号判定用 [无量纲] / float zero constant used by the sign test [dimensionless]
    DL_INT_ZERO      : INT := 0;              // 整型零常量，避免裸字面量 [字符] / integer zero constant [characters]
    DL_INT_ONE       : INT := 1;              // 整型一常量，首个非空格位置起点 [字符] / integer one constant, first non-blank position [characters]
END_VAR
VAR
    sText            : STRING(255);           // 文本中间串，有限与非有限共用 / text intermediate shared by both branches
    sTrim            : STRING(255);           // 修剪后的中间串 / intermediate string after the trim
    sOut             : STRING(255);           // 最终输出串 / final output string
    sChar            : STRING(1);             // 单字符比较缓冲 / single character comparison buffer
    nLen             : INT;                   // 中间串有效长度 [字符] / effective length of the intermediate string [characters]
    nStart           : INT;                   // 首个非空格位置，1 起始，0 = 全为空格 / first non-blank position, 1-based, 0 means all blanks
    nIdx             : INT;                   // 扫描游标 [字符]，1 起始 / scan cursor [characters], 1-based
    nKept            : INT;                   // 修剪后保留长度，一次锁存 [字符] / retained length, latched exactly once [characters]
    nTarget          : INT;                   // 目标长度，由引脚转出并钳位 [字符] / target length derived and clamped [characters]
    bFound           : BOOL;                  // 已找到首个非空格标志 / a first non-blank has been found
    bNaN             : BOOL;                  // 自反性判据命中的 NaN 标志 / NaN hit by the reflexivity test
    bInf             : BOOL;                  // 幅值判据命中的无穷标志 / infinity hit by the magnitude test
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_LrealToStringTrim := DL_STR_EMPTY;      // 故障缺省返回空串 / fault default returns an empty string
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
bNonFinite := FALSE;                          // 预置有限输入 / preset finite input
bTrimmed := FALSE;                            // 预置未修剪 / preset no trim
bTruncated := FALSE;                          // 预置未截断 / preset no truncation
sText := DL_STR_EMPTY;                        // 文本中间串清零 / clear the text intermediate
nKept := DL_INT_ZERO;                         // 保留长度清零 / clear the retained length

// 段 2｜目标长度钳位（0 长度无意义，结构性钳到 1，钳位后果由截断分支显式体现）/ segment 2, target length clamp
nTarget := USINT_TO_INT(uTargetMax);          // 目标长度转整型 [字符] / convert the target length into an integer [characters]
IF nTarget < USINT_TO_INT(DL_STR_TARGET_MIN) THEN
    nTarget := USINT_TO_INT(DL_STR_TARGET_MIN); // 0 长度目标钳到 1 字符 / a zero target is clamped to one character
END_IF
IF nTarget > USINT_TO_INT(DL_STR_CAP_MAX) THEN
    nTarget := USINT_TO_INT(DL_STR_CAP_MAX);  // 双保险：按 STRING 上限钳位 [字符] / second line of defence, clamp to the STRING capacity [characters]
END_IF

// 段 3｜非有限防御闸：先判 NaN 再判无穷，两判据分开置位 / segment 3, non-finite gate with two separate tests
bNaN := fIn <> fIn;                           // IEEE 754 自反性判据：NaN 与自身比较恒假 / reflexivity test, NaN never equals itself
bInf := FALSE;                                // 无穷标志预置 / preset the infinity flag
IF NOT bNaN THEN
    bInf := ((fIn - fIn) <> (fIn - fIn)) OR (ABS(fIn) >= DL_LREAL_INF_ABS); // 双判据：x−x 在无穷处产 NaN（精确判据），幅值兜底只余「恰为最大值」单值残余 [无量纲] / dual test, x minus x yields NaN at infinity while the magnitude fallback only leaves the exact-maximum residue [dimensionless]
END_IF

IF bNaN THEN
    sText := DL_STR_NAN;                      // 统一 NaN 文本，不做内建转换 / unified NaN text, no built-in conversion
    bNonFinite := TRUE;                       // 标记非有限输入 / flag the non-finite input
    eErr := 16#0001_0428;                     // 信息级：非有限值已映射统一文本 / info level, mapped onto the unified text
ELSIF bInf THEN
    IF fIn > DL_LREAL_ZERO THEN
        sText := DL_STR_INF_POS;              // 统一正无穷文本 / unified positive infinity text
    ELSE
        sText := DL_STR_INF_NEG;              // 统一负无穷文本 / unified negative infinity text
    END_IF
    bNonFinite := TRUE;                       // 标记非有限输入 / flag the non-finite input
    eErr := 16#0001_0428;                     // 信息级：非有限值已映射统一文本 / info level, mapped onto the unified text
ELSE
    // 段 4｜有限值：委托平台内建字符串化 / segment 4, finite values go through the built-in
    sText := LREAL_TO_STRING(fIn);            // 数值 → 原始串（可能含前导空格）/ value to raw string, possibly blank padded
END_IF

// 段 5｜有效长度一次锁存并钳位 / segment 5, latch the effective length once and clamp it
nLen := LEN(sText);                           // 中间串长度 [字符] / intermediate string length [characters]
IF nLen > DL_STR_SCAN_MAX THEN
    nLen := DL_STR_SCAN_MAX;                  // 超容量按上限钳位 [字符] / clamp to the capacity [characters]
ELSIF nLen < DL_INT_ZERO THEN
    nLen := DL_INT_ZERO;                      // 负长度防御，结构性不可达 [字符] / negative length guard, structurally unreachable [characters]
END_IF

// 段 6｜前导空格修剪：定长 FOR 扫描，禁 WHILE / segment 6, leading blank trim with a bounded FOR loop
nStart := DL_INT_ZERO;                        // 0 表示尚未找到非空格 / zero means no non-blank found yet
bFound := FALSE;                              // 扫描标志预置 / preset the scan flag
FOR nIdx := DL_INT_ONE TO nLen DO
    IF NOT bFound THEN
        sChar := MID(sText, DL_INT_ONE, nIdx); // 取当前字符 / take the current character
        IF sChar <> DL_STR_BLANK THEN
            nStart := nIdx;                   // 记录首个非空格位置 [字符] / record the first non-blank position [characters]
            bFound := TRUE;                   // 扫描标志置位 / raise the scan flag
        END_IF
    END_IF
END_FOR

IF nStart = DL_INT_ZERO THEN
    sTrim := DL_STR_EMPTY;                    // 全为空格：合法的空结果，不是错误 / all blanks, a legal empty result
ELSE
    sTrim := MID(sText, nLen - nStart + DL_INT_ONE, nStart); // 一次截取中间段 / extract the retained segment in one call
    IF nStart > DL_INT_ONE THEN
        bTrimmed := TRUE;                     // 确实修剪了前导空格 / blanks were really trimmed
        eErr := 16#0001_0429;                 // 信息级：发生空格修剪 / info level, blanks were trimmed
    END_IF
END_IF

// 段 7｜四步截断样板（R37）：长度锁存 → 宽度比较 → 标志先置 → 按允许分路 / segment 7, the four-step truncation pattern
nKept := LEN(sTrim);                          // 修剪后长度，一次锁存 [字符] / retained length, latched once [characters]
IF nKept > nTarget THEN
    bTruncated := TRUE;                       // 标志先于任何写入 / the flag precedes every write
    IF bAllowTrunc THEN
        sOut := LEFT(sTrim, nTarget);         // 允许截断：按目标长度截取 / truncation allowed, take the target length
        eErr := 16#0001_0429;                 // 信息级：发生截断，值可用 / info level, truncated, still usable
    ELSE
        eErr := 16#0001_035A;                 // 故障级：需截断但不允许 / fault level, truncation needed but not allowed
        bError := TRUE;                       // 置故障标志 / raise the error flag
        bValid := FALSE;                      // 返回值不可用 / flag the return as unusable
        FC_DL_LrealToStringTrim := DL_STR_EMPTY; // 返回空串，绝不返回半截数值 / return an empty string, never a partial number
        RETURN;                               // 出口 / exit
    END_IF
ELSE
    sOut := sTrim;                            // 无需截断，直接采用修剪结果 / no truncation, take the trimmed string
END_IF

// 段 8｜发布结果 / segment 8, publish the result
FC_DL_LrealToStringTrim := sOut;              // 输出最终串 / publish the final string
bValid := TRUE;                               // 有限值与非有限统一文本均可用 / both finite and unified non-finite texts are usable
bError := FALSE;                              // 信息级不置故障（双保险）/ info level never raises a fault, second line of defence
END_FUNCTION
