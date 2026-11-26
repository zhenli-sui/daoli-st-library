(*==============================================================================
 * 组件名称 (Component)  : FC_DL_LrealToFixedField
 * 溯源说明 (Provenance): 道莅 clean-room 防御性实现（IEC 61131-3 纯净实现，闭源文档仅借语义，零代码行）
 * 所属子库 (Sublibrary) : DL_MathData / DataFormat
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），仅用
 *                         Standard.library 的 MID / CONCAT / LEN / ABS / TRUNC / LIMIT
 * 组件分类 (Category)   : 函数（FUNCTION）· 纯函数 · 浮点 → 定宽定点文本
 * 功能一句话 (Summary)  : 把 LREAL 按指定整数位宽与小数位数输出成定宽定点文本
 *                         （四舍五入或截断、可选强制正号），非有限输入拒绝输出。
 *
 * 【填充与对齐规则（与 FC_DL_IntToFixedField 共用同一段口径原文）】
 *   ① 右对齐：数值永远贴字段右端，填充字符只在左侧。
 *   ② 本件无 bZeroPad 引脚，整数部分统一用**空格**填充到 uIntDigits 位
 *      ——即 #1 的 bZeroPad = FALSE 分支口径；领先零一律压成空格，
 *      但至少保留一位数字（0.5 输出 "0.500" 而非 ".500"）。
 *   ③ 符号位占一位：**恒留一格**（无符号时填空格），故字段总宽恒为
 *      1 + uIntDigits + (uDecDigits > 0 ? 1 + uDecDigits : 0) ≤ 23，
 *      定长报文的列位由此确定，不随数值正负漂移。
 *   ④ 宽度是契约：uIntDigits / uDecDigits 越界只钳位（0460 信息级）；
 *      整数部分装不下时不截断，直接饱和到全 9 并置 bSaturated。
 *
 * 本件存在的意义 (Why this unit exists)
 *   MES 称重/流量报文要的是「固定小数位、列位对齐」的数值域（"  1234.567"）。
 *   平台内建 LREAL_TO_STRING 的小数位口径与科学计数法门槛三平台不一致
 *   （CODESYS / TwinCAT / InoProShop 对同一值可能给出不同尾数与指数形式），
 *   故本件**禁用** LREAL_TO_STRING，自行按 10 的幂分解：绝对值域取整 → 逐位
 *   分解 → 拼接，末位再加符号，天然对称，输出可在三平台逐字节比对。
 *
 * 边界安全 (Boundary)
 *   ① 非有限输入：NaN 用自不等判据 (x−x) <>(x−x)，±Inf 用 ABS(x) > DBL_MAX
 *      精确判据（R79，禁近似阈值）→ 故障 03AE、bValid = FALSE，
 *      **绝不输出 'NaN' / 'Inf' 冒充合法报文**；
 *   ② uIntDigits 钳 1~15、uDecDigits 钳 0~6，越界钳位 + 信息 0460；
 *   ③ 字段装不下（1 + 整数位 + 1 + 小数位 > 24）→ 故障 03AF。钳位后最大为
 *      23，本分支结构性不可达，属纯防御纵深（R94 统一后处理）；
 *   ④ 整数部分有效位超 uIntDigits → 饱和全 9 + bSaturated + 信息 0461，
 *      bValid 保持 TRUE（饱和可观测，与「非有限」性质不同）；
 *   ⑤ 四舍五入实际进位导致整数位溢出 → 同一饱和路径（复用 0461，不新开码，R90）；
 *   ⑥ 舍入进位未溢出整数位 → 信息 0460 复用（R90 不加码，头注释写明复用理由）；
 *   ⑦ 全部取整只用 TRUNC 作用于**小于 10 的商与小于 10^d 的余数**，绝不 TRUNC
 *      大数，因此任何平台都不会在内建转换上溢出。
 * 遗留假设 (Assumption)
 *   整数部分超过 15 位十进制时 LREAL 已无精确表示（2^53 ≈ 9.007E15），
 *   本件按「输入本身已失真」处理，不承诺末位准确；这也是把
 *   uIntDigits 上限定为 15 的原因（DL_FF_INTMAX）。
 *   逐位分解的商与余数为浮点运算，末位可能受二进制表示误差影响 ±1 个最小
 *   单位（已在四舍五入阈值中吸收），不承诺与十进制手算逐位一致。
 *
 * 错误码    : 16#0001_0460 整数位/小数位已钳位，或四舍五入发生进位——信息级，正常防御
 *             16#0001_0461 整数部分有效位超出字段宽度，已饱和为全 9——信息级，饱和可观测
 *             16#0001_03AE 输入非有限（NaN / ±Inf），拒绝输出——故障级，返回 FALSE
 *             16#0001_03AF 字段宽度装不下（整数位+小数位+符号+小数点超上限）——故障级
 *             16#0001_03B0 预留禁用（故障级，不得挪用）
 * 码位总账  : 16#0001_0460 用 / 16#0001_0461 用 ｜ 16#0001_03AE 用 / 16#0001_03AF 用 / 16#0001_03B0 预留
 * 状态机    : N/A —— 纯函数无顺序状态机
 * 采样约定  : 纯组合函数，无定时器、无内部驻留状态
 * 依赖说明  : 无 DL_ 内部依赖；仅 Standard.library 的 MID / CONCAT / LEN / ABS / TRUNC / LIMIT
 * 验收向量  : V1 1234.5678/整数6/小数3/四舍五入 → '  1234.568'，写 11，TRUE
 *             V2 -42.5/整数6/小数3/截断 → '   -42.500'，写 11，TRUE
 *             V3 0.5/整数2/小数2 → '  0.50'，写 6，TRUE（领先零压成空格但保留一位）
 *             V4 999999.9999/整数6/小数3/四舍五入 → 饱和全 9 ' 999999.999'，
 *                bSaturated=TRUE，eErr=0461，TRUE（进位溢出主向量）
 *             V5 NaN → FALSE，sField=''，eErr=03AE，bError=TRUE
 *             V6 +Inf → FALSE，eErr=03AE
 *             V7 整数位 0 / 小数位 9 → 钳到 1 / 6 且 eErr=0460，仍返回 TRUE
 *             V8 1.0E16/整数15/小数0 → 饱和全 9（失真声明主向量）
 * 红线自检  : 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 ｜ 纯 IEC 61131-3（零厂商转换）
 *             浮点无判等比较（仅自不等 NaN 判据与容差阈值）｜ 除法前置判零
 *             （fPow 恒 ≥ 1.0，构造性非零）｜ 循环全部带守卫 ｜ 数组下标前置界检
 *             全变量双语同行注释 ｜ 状态机 N/A ｜ 无定时器实例 ｜ 无魔法数
 * 修订历史  : 2026-11-16  v1.0.0  首版入库（R22 · 批 1 · 定宽数值字段族）
 *============================================================================*)

FUNCTION FC_DL_LrealToFixedField : BOOL
VAR_INPUT
    fValue      : LREAL;                       // 待编码浮点值，任意有限值 / value to encode, any finite value
    uIntDigits  : UINT := 6;                   // 整数部分最少字符数 [字符]，范围 1~15 / minimum integer characters, range 1~15
    uDecDigits  : UINT := 3;                   // 小数位数 [位]，范围 0~6 / decimal digits, range 0~6
    bRound      : BOOL := TRUE;                // TRUE 四舍五入 / FALSE 向零截断 / TRUE rounds half up, FALSE truncates
    bForceSign  : BOOL := FALSE;               // 正数是否强制 '+' 号 / force '+' sign on positive values
END_VAR
VAR_OUTPUT
    sField      : STRING(24);                  // 定宽定点文本，右对齐 [ASCII] / fixed width fixed point text, right aligned
    uFieldLen   : UINT;                        // 实际写入字符数 [字符] / actual written length [char]
    bSaturated  : BOOL;                        // 整数部分已饱和为全 9 / integer part saturated to all nines
    eErr        : UDINT;                       // 错误码，0 表示无错 / error code, 0 means no error
    bError      : BOOL;                        // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid      : BOOL;                        // 结果可用标志（饱和时仍为 TRUE） / result usable flag, still TRUE when saturated
END_VAR
VAR
    nIntUse     : INT;                         // 生效整数位宽 [字符]，已钳位 1~15 / effective integer width, clamped
    nDecUse     : INT;                         // 生效小数位数 [位]，已钳位 0~6 / effective decimal digits, clamped
    nTotal      : INT;                         // 字段总宽 [字符] / total field width
    nLead       : INT;                         // 首个非零整数位下标 [索引]，0 表示全零 / index of the first non-zero integer digit, 0 when all zero
    nI          : INT;                         // 通用循环下标 [索引] / general loop index
    nJ          : INT;                         // 升序循环变量（镜像下标用）[索引] / ascending loop var for mirrored index
    nGuard      : INT;                         // 循环守卫计数器 [次] / loop guard counter
    nFracMax    : LINT;                        // 小数位满量 10^nDecUse [无量纲] / full range of the decimal part
    liFrac      : LINT;                        // 小数部分放大后的整数值 [无量纲] / scaled integer value of the decimal part
    liDig       : LINT;                        // 单步取位结果 [无量纲] / single digit extraction result
    bNeg        : BOOL;                        // 输入为负 / input is negative
    bNeedSign   : BOOL;                        // 是否输出符号字符 / whether a sign character is emitted
    bAllNine    : BOOL;                        // 饱和全 9 路径 / saturated all-nines path
    bCarry      : BOOL;                        // 舍入发生进位 / rounding produced a carry
    bPropagate  : BOOL;                        // 进位仍在传播 / the carry is still propagating
    fAbs        : LREAL;                       // 输入绝对值 [无量纲] / absolute value of the input
    fRem        : LREAL;                       // 未分解的剩余量 [无量纲] / remaining undecomposed value
    fPow        : LREAL;                       // 当前位的 10 的幂 [无量纲] / power of ten of the current position
    fIntLimit   : LREAL;                       // 整数部分容量 10^nIntUse [无量纲] / integer capacity
    fFracScaled : LREAL;                       // 放大后的小数部分 [无量纲] / scaled decimal part
    fDiff       : LREAL;                       // NaN 自不等判据的中间量 [无量纲] / intermediate for the NaN self-inequality test
    aInt        : ARRAY[1..15] OF USINT;       // 整数位数字缓存，1 基 [无量纲] / integer digit cache, 1-based
    aDec        : ARRAY[1..6] OF USINT;        // 小数位数字缓存，1 基 [无量纲] / decimal digit cache, 1-based
    sInt        : STRING(15);                  // 整数段（含空格填充）[ASCII] / integer segment including space padding
    sFrac       : STRING(6);                   // 小数段 [ASCII] / decimal segment
    sSign       : STRING(1);                   // 符号段，无符号时填空格 [ASCII] / sign segment, a space when unsigned
    sDigitCh    : STRING(1);                   // 单字符数字，由数字表取出 [ASCII] / single digit character taken from the table
END_VAR
VAR CONSTANT
    DL_FF_MAXLEN   : UINT := 24;               // STRING(24) 物理上限 [字符]，禁写成 255 / physical bound of STRING(24), never 255
    DL_FF_INTMAX   : UINT := 15;               // 整数位宽上限 [字符]，受 2^53 精度约束 / integer width ceiling, bounded by 2^53
    DL_FF_DECMAX   : UINT := 6;                // 小数位数上限 [位] / decimal digit ceiling
    DL_FF_MAXLEN_I : INT := 24;                // 字段上限的 INT 副本 [字符] / INT copy of the field ceiling
    DL_INT_MIN     : INT := 1;                 // 整数位宽下限 [字符] / integer width floor
    DL_DEC_MIN     : INT := 0;                 // 小数位数下限 [位] / decimal digit floor
    DL_INT_MAX     : INT := 15;                // 整数位宽上限的 INT 副本 [字符] / INT copy of the integer width ceiling
    DL_DEC_MAX     : INT := 6;                 // 小数位数上限的 INT 副本 [位] / INT copy of the decimal digit ceiling
    DL_U_ZERO      : UINT := 0;                // 无符号零值 [无量纲] / unsigned zero
    DL_U_ONE       : UINT := 1;                // 无符号一值 [无量纲] / unsigned one
    DL_ONE_I       : INT := 1;                 // 整型一，用于 FOR 起始 [无量纲] / integer one used as a FOR start
    DL_SIGN_RES    : INT := 1;                 // 符号位恒留宽度 [字符] / reserved sign position width
    DL_POINT_W     : INT := 1;                 // 小数点占位宽度 [字符] / decimal point width
    DL_DIG_LAST    : INT := 9;                 // 单个数字位最大值 [无量纲] / maximum single digit value
    DL_GUARD_MAX   : INT := 20;                // 循环守卫上限 [次] / loop guard ceiling
    DL_TEN_I       : INT := 10;                // 十进制基数的 INT 副本 [无量纲] / INT copy of the decimal radix
    DL_TEN_L       : LINT := 10;               // 十进制基数的 LINT 副本 [无量纲] / LINT copy of the decimal radix
    DL_TEN_R       : LREAL := 10.0;            // 十进制基数的 LREAL 副本 [无量纲] / LREAL copy of the decimal radix
    DL_ONE_R       : LREAL := 1.0;             // 实型一，幂循环起点 [无量纲] / real one, power loop start
    DL_HALF_R      : LREAL := 0.5;             // 四舍五入偏置 [无量纲] / half-up rounding offset
    DL_LREAL_MAX   : LREAL := 1.7976931348623157E308; // LREAL 最大有限值，±Inf 精确判据 / maximum finite LREAL, exact infinity test
    DL_DIGITS      : STRING(10) := '0123456789'; // 数字字符表，经 MID 取值 [ASCII] / digit table read through MID
    DL_POINT_CH    : STRING(1) := '.';         // 小数点字符 [字符] / decimal point character
    DL_SPACE_CH    : STRING(1) := ' ';         // 空格填充字符 [字符] / space pad character
    DL_SIGN_PLUS   : STRING(1) := '+';         // 正号字符 [字符] / plus sign character
    DL_SIGN_MINUS  : STRING(1) := '-';         // 负号字符 [字符] / minus sign character
    DL_CH_ONE      : INT := 1;                 // MID 的单字符长度 [字符] / single character length for MID
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与输出预置（L1/L9：任何早退路径不留脏值）
 *      Preset the return value and every output, no stale value on any exit
 *-----------------------------------------------------------------------------*)
FC_DL_LrealToFixedField := FALSE;              // 返回值预置失败 / preset to FALSE
sField      := '';                             // 字段清空 / field cleared
uFieldLen   := 0;                              // 写入长度预置 0 [字符] / written length preset to zero
bSaturated  := FALSE;                          // 饱和标志预置 FALSE / saturation preset to FALSE
eErr        := 16#0000_0000;                   // 错误码预置无错 / error code preset to none
bError      := FALSE;                          // 故障标志预置 FALSE / fault flag preset to FALSE
bValid      := FALSE;                          // 结果可用预置 FALSE / usable flag preset to FALSE
nIntUse     := DL_INT_MIN;                     // 整数位宽预置下限 / integer width preset to the floor
nDecUse     := DL_DEC_MIN;                     // 小数位数预置下限 / decimal digits preset to the floor
nTotal      := 0;                              // 总宽预置 0 / total width preset to zero
nLead       := 0;                              // 领先零位置预置 0 / leading position preset to zero
nGuard      := 0;                              // 守卫预置 0 / guard preset to zero
nFracMax    := 1;                              // 小数满量预置 1 / decimal full range preset to one
liFrac      := 0;                              // 小数整数化预置 0 / scaled decimal preset to zero
liDig       := 0;                              // 取位结果预置 0 / digit result preset to zero
bNeg        := FALSE;                          // 负号标志预置 FALSE / negative flag preset to FALSE
bNeedSign   := FALSE;                          // 符号标志预置 FALSE / sign flag preset to FALSE
bAllNine    := FALSE;                          // 饱和路径预置 FALSE / saturation path preset to FALSE
bCarry      := FALSE;                          // 进位标志预置 FALSE / carry flag preset to FALSE
bPropagate  := FALSE;                          // 进位传播预置 FALSE / propagation preset to FALSE
fAbs        := 0.0;                            // 绝对值预置 0 / absolute value preset to zero
fRem        := 0.0;                            // 剩余量预置 0 / remainder preset to zero
fPow        := DL_ONE_R;                       // 幂预置 1 / power preset to one
fIntLimit   := DL_ONE_R;                       // 整数容量预置 1 / integer capacity preset to one
fFracScaled := 0.0;                            // 放大值预置 0 / scaled value preset to zero
sSign       := DL_SPACE_CH;                    // 符号段预置空格（符号位恒留一格） / sign segment preset to a space, the position is always reserved

(*------------------------------------------------------------------------------
 * 段 2｜非有限输入闸门（R79 精确判据：NaN 自不等 + ±Inf 与 DBL_MAX 直比）
 *      Non-finite gate with exact criteria, no approximate thresholds
 *-----------------------------------------------------------------------------*)
fDiff := fValue - fValue;                      // 有限值得 0，NaN 得 NaN / zero for finite input, NaN for NaN input
IF fDiff <> fDiff THEN
    eErr   := 16#0001_03AE;                    // 故障级：NaN 输入 / fault: NaN input
    bError := TRUE;                            // 置故障标志 / raise the fault flag
    bValid := FALSE;                           // 结果不可用 / result unusable
    sField := '';                              // 绝不输出 'NaN' 冒充合法报文 / never emit NaN as a legal field
    RETURN;                                    // 早退路径已统一后处理 / the early exit is fully post-processed
END_IF
IF ABS(fValue) > DL_LREAL_MAX THEN
    eErr   := 16#0001_03AE;                    // 故障级：±Inf 输入 / fault: infinity input
    bError := TRUE;                            // 置故障标志 / raise the fault flag
    bValid := FALSE;                           // 结果不可用 / result unusable
    sField := '';                              // 绝不输出 'Inf' 冒充合法报文 / never emit Inf as a legal field
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜位宽钳位（越界只钳位；信息级码不置 bError）
 *      Width clamping, out-of-range values are clamped and never raise bError
 *-----------------------------------------------------------------------------*)
IF uIntDigits < DL_U_ONE THEN
    nIntUse := DL_INT_MIN;                     // 钳到下限 1 / clamped to the floor
    eErr    := 16#0001_0460;                   // 信息级：整数位已钳位 / informational: integer width clamped
ELSIF uIntDigits > DL_FF_INTMAX THEN
    nIntUse := DL_INT_MAX;                     // 钳到上限 15 / clamped to the ceiling
    eErr    := 16#0001_0460;                   // 信息级：整数位已钳位 / informational: integer width clamped
ELSE
    nIntUse := UINT_TO_INT(uIntDigits);         // 域内直通 / passed through inside the domain
END_IF

IF uDecDigits > DL_FF_DECMAX THEN
    nDecUse := DL_DEC_MAX;                     // 钳到上限 6 / clamped to the ceiling
    eErr    := 16#0001_0460;                   // 信息级：小数位已钳位 / informational: decimal digits clamped
ELSE
    nDecUse := UINT_TO_INT(uDecDigits);         // 域内直通（无符号量无下限问题） / passed through, no floor issue for unsigned
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜字段容量闸门（防御纵深：钳位后最大 23，本分支结构性不可达）
 *      Capacity gate, structurally unreachable after clamping, pure defense in depth
 *-----------------------------------------------------------------------------*)
nTotal := DL_SIGN_RES + nIntUse;                // 符号位恒留一格 + 整数位 / reserved sign plus integer width
IF nDecUse > DL_DEC_MIN THEN
    nTotal := nTotal + DL_POINT_W + nDecUse;    // 有小数位时加小数点与小数位 / add the point and the decimal digits
END_IF
IF nTotal > DL_FF_MAXLEN_I THEN
    eErr   := 16#0001_03AF;                     // 故障级：字段装不下 / fault: the field cannot hold the value
    bError := TRUE;                             // 置故障标志 / raise the fault flag
    bValid := FALSE;                            // 结果不可用 / result unusable
    sField := '';                               // 字段保持空串 / field stays empty
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜符号判定、整数量级与饱和预判（先判容量，绝不 TRUNC 大数）
 *      Sign, integer magnitude and saturation pre-check, never TRUNC a large value
 *-----------------------------------------------------------------------------*)
bNeg      := (fValue < 0.0);                    // 负值判据 / negative test
bNeedSign := bNeg OR bForceSign;                // 负号必需，正号由引脚决定 / minus always needed, plus only when forced
IF bNeedSign THEN
    IF bNeg THEN
        sSign := DL_SIGN_MINUS;                 // 负号 / minus sign
    ELSE
        sSign := DL_SIGN_PLUS;                  // 强制正号 / forced plus sign
    END_IF
ELSE
    sSign := DL_SPACE_CH;                       // 无符号：占位填空格，保持字段恒宽 / unsigned, a space keeps the width constant
END_IF

fAbs := ABS(fValue);                            // 绝对值域运算，末位再加符号，正负对称 / absolute domain, the sign is added at the end
fIntLimit := DL_ONE_R;                          // 容量初值 1 / capacity starts at one
FOR nI := DL_ONE_I TO nIntUse DO
    fIntLimit := fIntLimit * DL_TEN_R;          // 容量 = 10^nIntUse，nIntUse ≤ 15 在 LREAL 精确域内 / capacity, exact for n <= 15
END_FOR
IF fAbs >= fIntLimit THEN
    bAllNine := TRUE;                           // 整数部分装不下：饱和全 9，不进分解 / overflow, saturate to all nines
    eErr     := 16#0001_0461;                   // 信息级：整数部分已饱和 / informational: integer part saturated
    bSaturated := TRUE;                         // 饱和可观测 / saturation observable
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜整数位逐位分解（TRUNC 只作用于小于 10 的商）
 *      Integer digit decomposition, TRUNC only ever sees a quotient below ten
 *-----------------------------------------------------------------------------*)
IF NOT bAllNine THEN
    fRem := fAbs;                               // 从绝对值开始分解 / decomposition starts from the absolute value
    fPow := DL_ONE_R;                           // 最高位幂初值 1 / highest power starts at one
    FOR nI := DL_ONE_I TO (nIntUse - DL_ONE_I) DO
        fPow := fPow * DL_TEN_R;                // 幂升到 10^(nIntUse-1) / raise to the highest power
    END_FOR
    FOR nI := DL_ONE_I TO nIntUse DO
        IF fPow > 0.0 THEN
            liDig := TRUNC(fRem / fPow);        // 商恒 0~9，TRUNC 永不溢出 / quotient always 0~9, TRUNC never overflows
        ELSE
            liDig := 0;                         // 构造性不可达的兜底 / structurally unreachable fallback
        END_IF
        IF liDig < 0 THEN
            liDig := 0;                         // 下界夹紧 / clamped low
        ELSIF liDig > DL_DIG_LAST THEN
            liDig := DL_DIG_LAST;               // 上界夹紧 / clamped high
        END_IF
        aInt[nI] := LINT_TO_USINT(liDig);       // 缓存本位数 / cache this digit
        fRem := fRem - LINT_TO_LREAL(liDig) * fPow; // 扣掉已分解部分 / subtract the decomposed part
        fPow := fPow / DL_TEN_R;                // 幂降一位 / step down one power
    END_FOR
    IF fRem < 0.0 THEN
        fRem := 0.0;                            // 浮点误差兜底，剩余量恒非负 / floating point fallback, the remainder stays non-negative
    END_IF

    (* 小数部分：放大到整数域后取整，四舍五入加 0.5（负值已处理成绝对值，天然对称） *)
    (* Decimal part, scaled to the integer domain, half-up adds 0.5 in the absolute domain *)
    nFracMax := 1;                              // 小数满量初值 1 / full range starts at one
    FOR nI := DL_ONE_I TO nDecUse DO
        nFracMax := nFracMax * DL_TEN_L;        // 满量 = 10^nDecUse，nDecUse ≤ 6 / full range, n <= 6
    END_FOR
    fFracScaled := fRem * LINT_TO_LREAL(nFracMax);// 放大到小数满量 [无量纲] / scaled up to the decimal range
    IF bRound THEN
        fFracScaled := fFracScaled + DL_HALF_R;  // 四舍五入偏置 / half-up offset
    END_IF
    liFrac := TRUNC(fFracScaled);                // 取值恒 ≤ 10^nDecUse < 1.0E7，TRUNC 安全 / always below 1E7, TRUNC is safe
    IF liFrac < 0 THEN
        liFrac := 0;                             // 下界夹紧 / clamped low
    END_IF
    IF liFrac >= nFracMax THEN
        liFrac := liFrac - nFracMax;             // 满量即归零 / wrapped to zero
        bCarry := TRUE;                          // 向整数位进位 / carry into the integer part
    END_IF

    (* 进位传播：从最低整数位向前逐位加一，全 9 则整体饱和 *)
    (* Carry propagation from the least significant integer digit, all nines saturate everything *)
    IF bCarry THEN
        eErr        := 16#0001_0460;             // 信息级：舍入进位（复用 0460，R90 不加码） / informational: rounding carried, code reused
        nLead       := nIntUse;                  // 传播从最低位开始 / propagation starts at the lowest digit
        bPropagate  := TRUE;                     // 传播仍在进行 / the carry is still propagating
        nGuard      := 0;                        // 守卫清零 / guard cleared
        WHILE bPropagate AND (nLead >= DL_ONE_I) AND (nGuard <= DL_GUARD_MAX) DO
            IF aInt[nLead] < DL_DIG_LAST THEN
                aInt[nLead] := aInt[nLead] + 1;  // 本位加一，传播结束 / increment and stop propagating
                bPropagate  := FALSE;
            ELSE
                aInt[nLead] := 0;                // 本位满 9 归零，继续向前 / wrap to zero and keep propagating
                nLead := nLead - DL_ONE_I;
            END_IF
            nGuard := nGuard + DL_ONE_I;         // 守卫累计 / guard incremented
        END_WHILE
        IF bPropagate THEN
            bAllNine := TRUE;                    // 整数位全部溢出：饱和全 9 / every integer digit overflowed
            eErr     := 16#0001_0461;            // 信息级：整数部分已饱和 / informational: integer part saturated
            bSaturated := TRUE;                  // 饱和可观测 / saturation observable
        END_IF
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜饱和路径填 9（整数位与小数位同时置 9，语义为「超出可表示范围」）
 *      Saturation path fills nines, meaning the value exceeds the representable range
 *-----------------------------------------------------------------------------*)
IF bAllNine THEN
    FOR nI := DL_ONE_I TO nIntUse DO
        aInt[nI] := INT_TO_USINT(DL_DIG_LAST);   // 整数位全 9 / integer digits all nine
    END_FOR
    FOR nI := DL_ONE_I TO nDecUse DO
        aDec[nI] := INT_TO_USINT(DL_DIG_LAST);   // 小数位全 9 / decimal digits all nine
    END_FOR
    liFrac := 0;                                 // 小数整数化量不再使用 / the scaled decimal value is no longer used
ELSE
    (* 小数位逐位分解：从小到大取余，负域无需用（值恒非负） *)
    (* Decimal digit decomposition, the value is always non-negative here *)
    FOR nJ := DL_ONE_I TO nDecUse DO
        nI := nDecUse - nJ + DL_ONE_I;       // 镜像下标：R509 禁 DOWNTO / mirrored index, DOWNTO unsupported
        aDec[nI] := LINT_TO_USINT(liFrac MOD DL_TEN_L); // 取最低位 / take the least significant digit
        liFrac   := liFrac / DL_TEN_L;           // 降一位 / step down
    END_FOR
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜领先零定位（压成空格，但至少保留一位数字）
 *      Locate the leading zeros, replaced by spaces while keeping at least one digit
 *-----------------------------------------------------------------------------*)
nLead := 0;                                      // 0 表示尚未找到非零位 / zero means no non-zero digit found yet
FOR nI := DL_ONE_I TO nIntUse DO
    IF (nLead = 0) AND (aInt[nI] <> 0) THEN
        nLead := nI;                             // 记录首个非零位 / remember the first non-zero position
    END_IF
END_FOR
IF nLead = 0 THEN
    nLead := nIntUse;                            // 全零：最后一位仍输出 '0' / all zero, the last position still prints a zero
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜拼装（整数段 + 小数点 + 小数段，符号段恒占一格）
 *      Assembly, integer segment plus point plus decimals, the sign position is always reserved
 *-----------------------------------------------------------------------------*)
sInt := '';                                      // 整数段清空 / integer segment cleared
FOR nI := DL_ONE_I TO nIntUse DO
    IF nI < nLead THEN
        sInt := CONCAT(sInt, DL_SPACE_CH);        // 领先零压成空格 / a leading zero becomes a space
    ELSE
        sDigitCh := MID(DL_DIGITS, DL_CH_ONE, USINT_TO_INT(aInt[nI]) + DL_CH_ONE); // 数字 → 字符（查表） / digit to character by table
        sInt := CONCAT(sInt, sDigitCh);           // 追加数字 / append the digit
    END_IF
END_FOR

sFrac := '';                                     // 小数段清空 / decimal segment cleared
FOR nI := DL_ONE_I TO nDecUse DO
    sDigitCh := MID(DL_DIGITS, DL_CH_ONE, USINT_TO_INT(aDec[nI]) + DL_CH_ONE); // 数字 → 字符（查表） / digit to character by table
    sFrac := CONCAT(sFrac, sDigitCh);             // 追加小数位 / append the decimal digit
END_FOR

sField := CONCAT(sSign, sInt);                   // 符号位 + 整数段 / sign position plus integer segment
IF nDecUse > DL_DEC_MIN THEN
    sField := CONCAT(sField, DL_POINT_CH);        // 小数点 / decimal point
    sField := CONCAT(sField, sFrac);              // 小数段 / decimal segment
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜长度复检与出口（结构性不可达，纯防御纵深）
 *      Length recheck and exit, structurally unreachable, pure defense in depth
 *-----------------------------------------------------------------------------*)
IF LEN(sField) <> nTotal THEN
    eErr   := 16#0001_03AF;                       // 复检不符：按字段容量故障处理 / recheck mismatch, capacity fault
    bError := TRUE;                               // 置故障标志 / raise the fault flag
    bValid := FALSE;                              // 结果不可用 / result unusable
    sField := '';                                 // 字段回空，绝不交出不完整字段 / field emptied
    uFieldLen := 0;                               // 写入长度回 0 / written length back to zero
    RETURN;
END_IF

uFieldLen := INT_TO_UINT(nTotal);                  // 写入字符数 = 设计总宽 / written length equals the designed width
bValid    := TRUE;                                 // 结果可用（饱和亦为可用，降级可观测） / usable even when saturated
FC_DL_LrealToFixedField := TRUE;                   // 编码成功 / encoding succeeded
END_FUNCTION
