(*
    组件名称 : FC_DL_TimeToHmsString
    所属子库 : DL_MathData
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : TIME 时长 → 'HH:MM:SS.mmm' 定宽文本，负时长统一带负号，并把总小时数单独出口供报表使用。
              取舍 ①：不委托 DINT_TO_STRING 补零 —— 各平台对「正数是否带前导空格」「负数符号位置」
              的实现互不相同（R79 家族），靠它拼定宽字段必出「_1:05:03」这类带空格的串。
              本件用数字字符表 MID 取值 + CONCAT 拼装，位数与字符完全由代码控制。
              取舍 ②：负数先取绝对值再分解，但 DINT_MIN 单独走哨兵分支 —— −(−2147483648) 在 DINT 域回绕成自身，
              直接取负会把「最大负时长」变成「最大正时长」且符号丢失；本件对下界显式夹到 DINT_MAX 并保留负号。
              取舍 ③：分解全程只用非负操作数 —— 取绝对值之后再 MOD/DIV，三平台的负数取余歧义从源头消失。
              取舍 ④：小时字段不设上限截断，只发宽度提示 —— TIME 上限约 596 小时，HMI 常见 2 位小时字段装不下，
              但截断小时会让时长错得无声无息，宁可超宽 + 信息码让上位机改字段宽度。
    开源溯源 : T2-1 LGF Converter 子族（只借「时长转定宽文本」这一行为定义）。码位、补零策略、负数口径、；本件为道莅 clean-room 防御性实现（仅借 LGF 分类事实/参数域/行为定义，零代码行与符号名复制）。
              分解顺序 100% 自有，零代码行与注释复制。
    本文件内含 : FUNCTION FC_DL_TimeToHmsString（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: LEN / MID / CONCAT
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 下界哨兵 + 小时域闸 + 分解操作数恒非负 + 输出长度自证
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 纯函数无顺序状态机，无 CASE 可写
              R7 N/A 无定时器、无沿检测实例 ｜ R8 ✓ 毫秒基数、字段宽度、小时上限全常量化
    错误码   : 16#0001_044E [信息级] 负时长已带负号输出，bValid = TRUE
               16#0001_044F [信息级] 小时超 99，HMI 两位小时字段装不下，bValid = TRUE
               16#0001_0393 [故障级] 分解中间量非法（小时超 999，理论不可达），返回 '00:00:00.000'，bValid = FALSE
               16#0001_0394 [故障级] 预留禁用（不得挪用）
               16#0001_0395 [故障级] 预留禁用（不得挪用）
    码位总账 : 16#0001_044E 用 / 16#0001_044F 用 ｜ 16#0001_0393 用 / 16#0001_0394 预留 / 16#0001_0395 预留
    遗留假设 : ① 本件依赖「平台 TIME 为 32 位有符号毫秒计数」这一口径（TIME_TO_DINT 与 TIME 同宽）。
              CODESYS / TwinCAT 3 默认如此，InoProShop 未实测；若某平台 TIME 换成 64 位 LTime 语义，
              小时上限与 DINT_MIN 哨兵都需重估。交付门槛：三平台各编译并跑 T#-1ms、T#-2147483648ms、
              T#596H 三个边界 —— 未实测，编译门槛未闭合。
              ② MID 参数序按 IEC 标准 MID(串, 长度, 位置)，与库内既有用法同序。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 3 入库
*)
FUNCTION FC_DL_TimeToHmsString : STRING
VAR_INPUT
    tIn             : TIME;   // 待格式化时长，全域（含负值）[ms] / duration to format, negative values included [ms]
END_VAR
VAR_OUTPUT
    eErr            : UDINT;  // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;   // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag, TRUE on fault-level eErr
    bValid          : BOOL;   // 返回值是否可用 / result usable flag
    bNegative       : BOOL;   // 输入是否为负时长，输出串因此带前导负号 / TRUE when the input duration is negative and the text carries a minus sign
    nTotalHours     : DINT;   // 总小时数（分解后），供报表直接取用 [h] / total hours after the decomposition [h]
END_VAR
VAR
    nMs             : DINT;   // 时长的毫秒值，取绝对值后恒非负 [ms] / duration in milliseconds, non-negative after the magnitude step [ms]
    nHours          : DINT;   // 小时数 0~999 [h] / hours, 0..999 [h]
    nMinutes        : DINT;   // 分钟数 0~59 [min] / minutes, 0..59 [min]
    nSeconds        : DINT;   // 秒数 0~59 [s] / seconds, 0..59 [s]
    nMilli          : DINT;   // 毫秒数 0~999 [ms] / milliseconds, 0..999 [ms]
    sRet            : STRING; // 结果装配缓冲 [字符] / result assembly buffer [char]
    nDigits         : INT;    // 当前字段位数，用于补零循环 [位] / digits of the current field used by the padding loops [digit]
    nPos            : INT;    // 补零循环游标 [位] / padding loop cursor [digit]
END_VAR
VAR CONSTANT
    DL_MS_PER_SEC       : DINT := 1000;                  // 每秒毫秒数 [ms] / milliseconds per second [ms]
    DL_MS_PER_MIN       : DINT := 60000;                 // 每分毫秒数 [ms] / milliseconds per minute [ms]
    DL_MS_PER_HOUR      : DINT := 3600000;               // 每小时毫秒数 [ms] / milliseconds per hour [ms]
    DL_HMS_FIELD_WARN_H : DINT := 99;                    // HMI 常见两位小时字段上限 [h] / typical two digit hour field limit [h]
    DL_HMS_HOUR_MAX     : DINT := 999;                   // 三位小时字段上限，TIME 上限 596h 结构性不越此值 [h] / three digit hour field limit [h]
    DL_HMS_MS_MAX       : DINT := 999;                   // 毫秒字段上限 [ms] / millisecond field limit [ms]
    DL_HMS_MIN_MAX      : DINT := 60;                    // 分钟/秒的进位基数 [min] / radix of the minute and second fields [min]
    DL_HMS_DIGIT_TEN    : DINT := 10;                    // 十进制位数基数 [无量纲] / decimal digit radix [dimensionless]
    DL_HMS_DIGIT_HUND   : DINT := 100;                   // 百位基数 [无量纲] / hundreds radix [dimensionless]
    DL_DIGIT_TABLE      : STRING := '0123456789';        // 数字字符表，MID 位置 = 值 + 1 [字符] / digit table, the MID position is the value plus one [char]
    DL_HMS_COLON        : STRING := ':';                 // 时分秒分隔符 [字符] / hour-minute-second separator [char]
    DL_HMS_DOT          : STRING := '.';                 // 秒与毫秒分隔符 [字符] / second-millisecond separator [char]
    DL_HMS_MINUS        : STRING := '-';                 // 负号 [字符] / minus sign [char]
    DL_HMS_ZERO_TEXT    : STRING := '00:00:00.000';      // 故障回退串，长度恒 12 [字符] / fault fallback text with a constant length of twelve [char]
    DL_HMS_ZERO_CH      : STRING := '0';                 // 单个零字符，小时字段补位用 [字符] / single zero character used to pad the hour field [char]
    DL_HMS_ONE          : INT := 1;                      // 单位哨兵，MID 位置 1 基 [无量纲] / unity sentinel, MID is one based [dimensionless]
    DL_HMS_LEN_MIN      : INT := 12;                     // 最短合法长度（两位小时、无负号）[字符] / shortest legal length with two digit hours and no sign [char]
    DL_HMS_LEN_MAX      : INT := 14;                     // 最长合法长度（负号 + 三位小时）[字符] / longest legal length with a sign and three digit hours [char]
    DL_DINT_MIN         : DINT := -2147483648;           // DINT 下界，取负会回绕，必须单独拦 [ms] / DINT lower bound whose negation wraps around [ms]
    DL_DINT_MAX         : DINT := 2147483647;            // DINT 上界，下界夹到此值 [ms] / DINT upper bound used to clamp the lower bound case [ms]
    DL_DINT_ZERO        : DINT := 0;                     // 零哨兵 [ms] / zero sentinel [ms]
    DL_ERR_NONE         : UDINT := 16#0000_0000;         // 无故障 / no error
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset the return value and the error state
FC_DL_TimeToHmsString := DL_HMS_ZERO_TEXT;   // 故障缺省返回定宽零串 / fault default returns the fixed width zero text
eErr         := DL_ERR_NONE;                 // 预置无错误 / preset no error
bError       := FALSE;                       // 预置无故障 / preset no fault
bValid       := FALSE;                       // 预置结果不可用 / preset unusable
bNegative    := FALSE;                       // 预置非负 / preset non-negative
nTotalHours  := 0;                           // 预置小时 0 / preset the hours to zero
sRet         := '';                          // 缓冲清空 / clear the buffer

// 段 2｜取值与符号处理：下界单独夹，其余直接取负 / segment 2, magnitude step with an explicit lower bound branch
nMs := TIME_TO_DINT(tIn);                    // 毫秒口径，依赖平台 TIME 为 32 位毫秒（见遗留假设）/ millisecond reading, see the assumption note
IF nMs < DL_DINT_ZERO THEN
    bNegative := TRUE;                       // 标记负时长 / mark the negative duration
    eErr      := 16#0001_044E;               // 负时长已带负号输出（信息级，不置 bError）/ negative duration, info level
    IF nMs = DL_DINT_MIN THEN
        nMs := DL_DINT_MAX;                  // 下界取负会回绕，夹到上界（差 1ms，方向与符号均保留）/ negating the lower bound wraps, clamp instead
    ELSE
        nMs := -nMs;                         // 常规取绝对值 / usual magnitude
    END_IF
END_IF

// 段 3｜分解：操作数全程非负，MOD 无符号歧义 / segment 3, decomposition with non-negative operands only
nHours   := nMs / DL_MS_PER_HOUR;                          // 小时 / hours
nMinutes := (nMs MOD DL_MS_PER_HOUR) / DL_MS_PER_MIN;      // 分钟 / minutes
nSeconds := (nMs MOD DL_MS_PER_MIN) / DL_MS_PER_SEC;       // 秒 / seconds
nMilli   := nMs MOD DL_MS_PER_SEC;                         // 毫秒 / milliseconds
nTotalHours := nHours;                                     // 出口小时数 / publish the hours
IF nHours > DL_HMS_HOUR_MAX THEN
    eErr   := 16#0001_0393;              // 分解中间量非法（故障级，理论不可达）/ illegal intermediate, fault level, unreachable in theory
    bError := TRUE;                      // 置故障标志 / raise the fault flag
    RETURN;                              // 返回定宽零串 / return the fixed width zero text
END_IF
IF (nHours > DL_HMS_FIELD_WARN_H) AND (eErr = DL_ERR_NONE) THEN
    eErr := 16#0001_044F;                // 小时超 99 字段宽度提示（信息级）/ hour field too wide, info level
END_IF

// 段 4｜小时字段：最多三位，前导零按需省略 / segment 4, hour field with at most three digits and no superfluous zeros
IF bNegative THEN
    sRet := CONCAT(sRet, DL_HMS_MINUS);  // 负号前置 / the sign comes first
END_IF
IF nHours >= DL_HMS_DIGIT_HUND THEN
    sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_HMS_ONE, DINT_TO_INT(nHours / DL_HMS_DIGIT_HUND) + DL_HMS_ONE));   // 百位 / hundreds digit
END_IF
IF nHours >= DL_HMS_DIGIT_TEN THEN
    sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_HMS_ONE, DINT_TO_INT((nHours / DL_HMS_DIGIT_TEN) MOD DL_HMS_DIGIT_TEN) + DL_HMS_ONE));   // 十位 / tens digit
ELSE
    sRet := CONCAT(sRet, DL_HMS_ZERO_CH);   // 不足两位补零，保证 HH 定宽 / pad to two digits so the hour field keeps the HH width
END_IF
sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_HMS_ONE, DINT_TO_INT(nHours MOD DL_HMS_DIGIT_TEN) + DL_HMS_ONE));   // 个位，恒输出 / units digit, always emitted
sRet := CONCAT(sRet, DL_HMS_COLON);      // 小时分隔符 / hour separator

// 段 5｜分钟与秒：两位定宽，逐位查表 / segment 5, minute and second fields, two digits each
sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_HMS_ONE, DINT_TO_INT(nMinutes / DL_HMS_DIGIT_TEN) + DL_HMS_ONE));   // 分的十位 / minute tens
sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_HMS_ONE, DINT_TO_INT(nMinutes MOD DL_HMS_DIGIT_TEN) + DL_HMS_ONE)); // 分的个位 / minute units
sRet := CONCAT(sRet, DL_HMS_COLON);      // 分隔符 / separator
sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_HMS_ONE, DINT_TO_INT(nSeconds / DL_HMS_DIGIT_TEN) + DL_HMS_ONE));   // 秒的十位 / second tens
sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_HMS_ONE, DINT_TO_INT(nSeconds MOD DL_HMS_DIGIT_TEN) + DL_HMS_ONE)); // 秒的个位 / second units
sRet := CONCAT(sRet, DL_HMS_DOT);        // 小数点 / decimal dot

// 段 6｜毫秒：三位定宽 / segment 6, millisecond field, three digits
sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_HMS_ONE, DINT_TO_INT(nMilli / DL_HMS_DIGIT_HUND) + DL_HMS_ONE));   // 百位 / hundreds
sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_HMS_ONE, DINT_TO_INT((nMilli / DL_HMS_DIGIT_TEN) MOD DL_HMS_DIGIT_TEN) + DL_HMS_ONE));   // 十位 / tens
sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_HMS_ONE, DINT_TO_INT(nMilli MOD DL_HMS_DIGIT_TEN) + DL_HMS_ONE));   // 个位 / units

// 段 7｜出口长度自证：小时 ≤ 99 且非负为 12；带负号或三位小时为 13；两者兼有为 14 / segment 7, length self proof
nDigits := LEN(sRet);                    // 实际长度 / the actual length
IF (nDigits < DL_HMS_LEN_MIN) OR (nDigits > DL_HMS_LEN_MAX) THEN
    FC_DL_TimeToHmsString := DL_HMS_ZERO_TEXT;   // 长度异常回退定宽零串 / fall back to the fixed width zero text
    eErr   := 16#0001_0393;              // 格式装配异常按分解故障处置 / an assembly fault is reported as an intermediate fault
    bError := TRUE;                      // 置故障标志 / raise the fault flag
    RETURN;                              // bValid 保持 FALSE / bValid stays FALSE
END_IF

// 段 8｜出口 / segment 8, exit
FC_DL_TimeToHmsString := sRet;           // 输出定宽时间文本 / publish the fixed width time text
bValid := TRUE;                          // 结果可用 / the result is usable
END_FUNCTION
