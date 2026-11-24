(*==============================================================================
 * 组件名称 (Component)  : FC_DL_IntToFixedField
 * 溯源说明 (Provenance): 道莅 clean-room 防御性实现（IEC 61131-3 纯净实现，闭源文档仅借语义，零代码行）
 * 所属子库 (Sublibrary) : DL_MathData / DataFormat
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），仅用
 *                         Standard.library 的 MID / CONCAT / LEN
 * 组件分类 (Category)   : 函数（FUNCTION）· 纯函数 · 整数 → 定宽数值字段
 * 功能一句话 (Summary)  : 把 DINT 整数编码成恰好 uWidth 个字符的定宽字段
 *                         （右对齐，零填充或空格填充，可选强制正号），
 *                         供 MES 流水号与 ASCII 定长报文拼装使用。
 *
 * 本件存在的意义 (Why this unit exists)
 *   库内 FC_DL_StringFixedField 解决「定长串填充与对齐」（内容不定），
 *   FC_DL_DintToStringTrim 解决「数值→文本去空格」（不定宽）。二者之间有一个
 *   真实缺口：数值 → **定宽零填充字段**（00012345）与它的逆运算。
 *   MES 流水号、秤重报文、ASCII 定长十进制域全部落在这一格，缺件则报文层
 *   拼不出列位对齐的数字域。本件与 FC_DL_FixedFieldToInt 构成编码对。
 *
 * 【填充与对齐规则（与 FC_DL_FixedFieldToInt 共用同一段口径原文）】
 *   ① 右对齐：数字永远贴字段右端，填充字符只在左侧。
 *   ② 填充字符由 bZeroPad 决定：TRUE 用 '0'，FALSE 用 ' '。
 *   ③ 符号位占一位：零填充时符号贴最左（-0000042），空格填充时符号紧贴数字
 *      （     -42）——这是 C printf 的 %08d / %8d 口径，两种写法的字段长度
 *      都恰好等于 uWidth，任何时刻不会出现半截字段。
 *   ④ 宽度是契约：不够装就**拒绝编码**，绝不截断成半截数字（截断出来的
 *      「1234」与真实「123456」在报文里无法区分，是账实不符的根因）。
 *
 * 边界安全 (Boundary)
 *   ① uWidth < 1 或 > 20 → 钳到 1 / 20 并置信息 045C（宽度可钳，内容不可钳）；
 *   ② 可用数字位（宽度扣掉符号位）不足以容纳全部数字 → 故障 03A8、拒绝编码、
 *      sField 保持空串、uFieldLen 保持 0；
 *   ③ 整数分解**全程走负域**：nValue = -2147483648 若先取绝对值再取模会回绕，
 *      故负值直接进负域、正值先取反进负域，循环内 nWork 恒 ≤ 0，
 *      `-(nWork MOD 10)` 恒得 0~9（IEC：MOD 结果符号随被除数）；
 *   ④ sField 声明 STRING(20) 与本件宽度上限一致，宽度钳位后总长恒 ≤ 20，
 *      写入不存在隐式截断；出口另做 LEN 复检兜底（防御纵深）。
 * 遗留假设 (Assumption)
 *   MOD 的负余数口径按 IEC 61131-3（结果符号随被除数）与 C 语言一致，
 *   本件依赖该口径实现负域分解；CODESYS / TwinCAT / InoProShop 三平台一致。
 *
 * 错误码    : 16#0001_045C 字段宽度越界已钳位到 1~20——信息级，正常防御
 *             16#0001_045D 预留禁用（信息级，不得挪用）
 *             16#0001_03A8 可用宽度不足以容纳完整数值，拒绝编码（不输出半截数字）——故障级，返回 FALSE
 *             16#0001_03A9 预留禁用（故障级，不得挪用）
 *             16#0001_03AA 预留禁用（故障级，不得挪用）
 * 码位总账  : 16#0001_045C 用 / 16#0001_045D 预留 ｜ 16#0001_03A8 用 / 16#0001_03A9 预留 / 16#0001_03AA 预留
 * 状态机    : N/A —— 纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
 * 采样约定  : 纯组合函数，无定时器、无内部驻留状态，调用即出结果
 * 依赖说明  : 无 DL_ 内部依赖；仅 Standard.library 的 MID / CONCAT / LEN
 * 验收向量  : V1 12345/宽8/零填 → '00012345'，写 8，TRUE
 *             V2 -42/宽8/空格填 → '     -42'，写 8，TRUE
 *             V3 0/宽4/零填 → '0000'
 *             V4 -2147483648/宽11 → '-2147483648'，写 11（负域分解主向量）
 *             V5 123456/宽4 → FALSE，sField=''，uFieldLen=0，eErr=03A8，bError=TRUE
 *             V6 宽 0 → 钳到 1 且 eErr=045C，bError 保持 FALSE
 *             V7 round-trip：#1 编码 → #2 解析，全 DINT 域逐值回原值
 * 红线自检  : 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 ｜ 纯 IEC 61131-3 ｜ 防除零
 *             （本件无除法）· 浮点无比较 · 循环带 nGuard ｜ 全变量双语同行注释
 *             状态机 N/A ｜ 无定时器实例 ｜ 无魔法数（阈值全部 VAR CONSTANT）
 * 修订历史  : 2026-11-16  v1.0.0  首版入库（R22 · 批 1 · 定宽数值字段族）
 *============================================================================*)

FUNCTION FC_DL_IntToFixedField : BOOL
VAR_INPUT
    nValue      : DINT;                        // 待编码整数，全 DINT 域 / integer to encode, full DINT range
    uWidth      : UINT := 8;                   // 字段宽度 [字符]，范围 1~20 / field width [char], range 1~20
    bZeroPad    : BOOL := TRUE;                // TRUE 零填充 / FALSE 空格填充 / TRUE zero padding, FALSE space padding
    bForceSign  : BOOL := FALSE;               // 正数是否强制 '+' 号 / force '+' sign on positive values
END_VAR
VAR_OUTPUT
    sField      : STRING(20);                  // 编码结果，右对齐 [字符] / encoded field, right aligned [char]
    uFieldLen   : UINT;                        // 实际写入字符数 [字符] / actual written length [char]
    eErr        : UDINT;                       // 错误码，0 表示无错 / error code, 0 means no error
    bError      : BOOL;                        // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid      : BOOL;                        // 结果可用标志 / result usable flag
END_VAR
VAR
    nWUse       : INT;                         // 生效字段宽度 [字符]，已钳位 1~20 / effective width, clamped to 1~20
    nDigitsAvail: INT;                         // 扣符号位后可用数字位 [字符] / digits available after the sign position
    nDigitCount : INT;                         // 实际数字位个数 [位] / actual digit count
    nPadCount   : INT;                         // 填充字符个数 [字符] / pad character count
    nGuard      : INT;                         // 循环守卫计数器 [次] / loop guard counter
    nWork       : DINT;                        // 负域分解工作值，恒 ≤ 0 [无量纲] / negative-domain working value, always <= 0
    nDigit      : DINT;                        // 当前最低位数字 0~9 [无量纲] / current least significant digit
    bNeg        : BOOL;                        // 输入为负数 / input is negative
    bNeedSign   : BOOL;                        // 本字段是否输出符号字符 / whether a sign character is emitted
    sDigits     : STRING(20);                  // 数字段，高位在前 [ASCII] / digit segment, most significant first
    sPad        : STRING(20);                  // 填充段，贴在数字左侧 [ASCII] / pad segment, left of the digits
    sSign       : STRING(1);                   // 符号段，单字符 [ASCII] / sign segment, single character
    sDigitCh    : STRING(1);                   // 单字符数字，由数字表取出 [ASCII] / single digit character taken from the table
END_VAR
VAR CONSTANT
    DL_FIELD_MAX : UINT := 20;                 // STRING(20) 物理上限 [字符]，禁写成 255 / physical bound of STRING(20), never 255
    DL_W_MIN_U   : UINT := 1;                  // 宽度下限的无符号副本 [字符]，用于 UINT 域比较 / unsigned copy of the width lower bound
    DL_W_MIN     : INT := 1;                   // 宽度下限 [字符] / width lower bound [char]
    DL_W_MAX     : INT := 20;                  // 宽度上限 [字符]，与 DL_FIELD_MAX 同值同义 / width upper bound, same value as DL_FIELD_MAX
    DL_DIGIT_MAX : INT := 10;                  // DINT 十进制最大位数 [位] / maximum decimal digits of DINT
    DL_GUARD_MAX : INT := 12;                  // 分解循环守卫上限 [次]，大于位数即安全 / decomposition loop guard, larger than the digit count
    DL_TEN       : DINT := 10;                 // 十进制基数 [无量纲] / decimal radix
    DL_POS_ONE   : INT := 1;                   // MID 的位置基数与单字符长度 [字符] / MID position base and single-char length
    DL_DIGITS    : STRING(10) := '0123456789'; // 数字字符表，经 MID 按下标取值 [ASCII] / digit table indexed through MID
    DL_PAD_ZERO  : STRING(1) := '0';           // 零填充字符 [字符] / zero pad character
    DL_PAD_SPACE : STRING(1) := ' ';           // 空格填充字符 [字符] / space pad character
    DL_SIGN_PLUS : STRING(1) := '+';           // 正号字符 [字符] / plus sign character
    DL_SIGN_MINUS: STRING(1) := '-';           // 负号字符 [字符] / minus sign character
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与输出预置（任何早退路径不留脏值，L1/L9）
 *      Preset the return value and every output so no early exit leaves stale data
 *-----------------------------------------------------------------------------*)
FC_DL_IntToFixedField := FALSE;                // 返回值预置失败，成功路径末段置 TRUE / preset to FALSE, set TRUE only on success
sField      := '';                             // 字段清空，拒绝编码时保持空串 / field cleared, stays empty on refusal
uFieldLen   := 0;                              // 写入字符数预置 0 [字符] / written length preset to zero
eErr        := 16#0000_0000;                   // 错误码预置无错 / error code preset to none
bError      := FALSE;                          // 故障标志预置 FALSE / fault flag preset to FALSE
bValid      := FALSE;                          // 结果可用标志预置 FALSE / usable flag preset to FALSE
nWUse       := DL_W_MIN;                       // 生效宽度预置下限 / effective width preset to the lower bound
nDigitsAvail := 0;                             // 可用数字位预置 0 / available digits preset to zero
nDigitCount := 0;                              // 数字位个数预置 0 / digit count preset to zero
nPadCount   := 0;                              // 填充个数预置 0 / pad count preset to zero
nGuard      := 0;                              // 循环守卫预置 0 / guard preset to zero

(*------------------------------------------------------------------------------
 * 段 2｜宽度闸门（越界只钳位不拒绝：宽度可钳，内容不可钳）
 *      Width gate: clamping the width is safe, clamping the content is not
 *-----------------------------------------------------------------------------*)
IF uWidth < DL_W_MIN_U THEN
    nWUse := DL_W_MIN;                         // 钳到下限 1 / clamped to the lower bound
    eErr  := 16#0001_045C;                     // 信息级：宽度已钳位 / informational: width clamped
ELSIF uWidth > DL_FIELD_MAX THEN
    nWUse := DL_W_MAX;                         // 钳到上限 20 / clamped to the upper bound
    eErr  := 16#0001_045C;                     // 信息级：宽度已钳位 / informational: width clamped
ELSE
    nWUse := UINT_TO_INT(uWidth);              // 域内直通 / passed through inside the domain
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜符号判定与可用数字位（符号位先占，再谈数字装不装得下）
 *      Sign decision and available digit positions
 *-----------------------------------------------------------------------------*)
bNeg      := (nValue < 0);                      // 负值判据，DINT 全域成立 / negative test, valid over the whole DINT range
bNeedSign := bNeg OR bForceSign;                // 负号必需，正号由引脚决定 / minus always needed, plus only if forced
IF bNeedSign AND (nWUse >= (DL_W_MIN + DL_POS_ONE)) THEN
    nDigitsAvail := nWUse - DL_POS_ONE;         // 宽度至少 2 才谈得上符号 + 一位数字 / at least two positions for sign plus one digit
ELSIF bNeedSign THEN
    nDigitsAvail := 0;                         // 宽度 1 且要符号：无数字位可装 / width one with sign leaves no digit position
ELSE
    nDigitsAvail := nWUse;                     // 无符号：全部位可装数字 / no sign, every position carries a digit
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜负域逐位分解（本件核心防错：-**不取绝对值**）
 *      Negative-domain digit decomposition, the absolute value is never taken
 *      nValue = -2147483648 取绝对值即回绕，故负值直接进负域、正值取反进负域
 *      ABS(-2147483648) wraps, so negatives stay negative and positives are negated
 *-----------------------------------------------------------------------------*)
IF nValue < 0 THEN
    nWork := nValue;                            // 已属负域，原样使用 / already negative, used as is
ELSE
    nWork := -nValue;                           // 正数升到负域，最大 2147483647 → -2147483647 无溢出 / positive moved to the negative domain, no overflow
END_IF

sDigits := '';                                  // 数字段清空 / digit segment cleared
IF nWork = 0 THEN
    sDigits     := MID(DL_DIGITS, DL_POS_ONE, DL_POS_ONE); // 零值特例：单个字符 '0' / zero special case, a single character
    nDigitCount := 1;                           // 零视为一位 / zero counts as one digit
END_IF

WHILE (nWork <> 0) AND (nGuard <= DL_GUARD_MAX) DO
    nDigit   := -(nWork MOD DL_TEN);            // 负域取模得 0~-9，取反得 0~9 / negative remainder negated into 0~9
    sDigitCh := MID(DL_DIGITS, DL_POS_ONE, DINT_TO_INT(nDigit) + DL_POS_ONE); // 数字 → 字符，查表不靠字符码算术 / digit to character through the table
    sDigits  := CONCAT(sDigitCh, sDigits);      // 前插，保证高位在前 / prepended so the most significant digit leads
    nDigitCount := nDigitCount + DL_POS_ONE;    // 位数累计 / digit count incremented
    nWork    := nWork / DL_TEN;                 // 向零整除，负域同样正确 / truncating division, correct in the negative domain
    nGuard   := nGuard + DL_POS_ONE;            // 守卫累计，防死循环 / guard incremented, prevents a dead loop
END_WHILE

(*------------------------------------------------------------------------------
 * 段 5｜容量闸门（装不下就拒绝，绝不输出半截数字）
 *      Capacity gate: refuse when it does not fit, never emit a truncated number
 *-----------------------------------------------------------------------------*)
IF (nDigitCount > nDigitsAvail) OR (nDigitCount > DL_DIGIT_MAX) OR (nGuard > DL_GUARD_MAX) THEN
    eErr     := 16#0001_03A8;                   // 故障级：宽度不足，拒绝编码 / fault: insufficient width, encoding refused
    bError   := TRUE;                           // 置故障标志 / raise the fault flag
    bValid   := FALSE;                          // 结果不可用 / result unusable
    sField   := '';                             // 字段保持空串 / field stays empty
    uFieldLen := 0;                             // 写入长度保持 0 / written length stays zero
    FC_DL_IntToFixedField := FALSE;             // 返回失败 / return failure
    RETURN;                                     // 早退路径已统一后处理 / the early exit is fully post-processed
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜填充段构造（个数 = 可用位 − 实际位数，恒非负）
 *      Pad segment build: available positions minus actual digits, never negative
 *-----------------------------------------------------------------------------*)
nPadCount := nDigitsAvail - nDigitCount;        // 段 5 已保证 nDigitCount ≤ nDigitsAvail / guaranteed non-negative by segment five
sPad      := '';                                // 填充段清空 / pad segment cleared
nGuard    := 0;                                 // 守卫复用前先清零 / guard cleared before reuse
WHILE (nPadCount > 0) AND (nGuard <= DL_W_MAX) DO
    IF bZeroPad THEN
        sPad := CONCAT(sPad, DL_PAD_ZERO);      // 零填充 / zero padding
    ELSE
        sPad := CONCAT(sPad, DL_PAD_SPACE);     // 空格填充 / space padding
    END_IF
    nPadCount := nPadCount - DL_POS_ONE;        // 剩余个数递减 / remaining count decremented
    nGuard    := nGuard + DL_POS_ONE;           // 守卫累计，上界为宽度上限 / guard bounded by the width limit
END_WHILE

(*------------------------------------------------------------------------------
 * 段 7｜符号段与拼装（对齐口径见头注释）
 *      Sign segment and assembly, alignment per the header rules
 *-----------------------------------------------------------------------------*)
IF bNeedSign THEN
    IF bNeg THEN
        sSign := DL_SIGN_MINUS;                 // 负号 / minus sign
    ELSE
        sSign := DL_SIGN_PLUS;                  // 强制正号 / forced plus sign
    END_IF
ELSE
    sSign := '';                                // 无符号段 / no sign segment
END_IF

IF bNeedSign AND bZeroPad THEN
    sField := CONCAT(sSign, CONCAT(sPad, sDigits)); // 零填充：符号贴最左 -0000042 / zero pad, sign on the far left
ELSE
    sField := CONCAT(sPad, CONCAT(sSign, sDigits)); // 空格填充：符号紧贴数字      -42 / space pad, sign next to the digits
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜长度复检与出口（结构性不可能命中，纯防御纵深，R94 统一后处理）
 *      Length recheck and exit, structurally unreachable, pure defense in depth
 *-----------------------------------------------------------------------------*)
IF LEN(sField) <> nWUse THEN
    eErr     := 16#0001_03A8;                   // 复检不符：按同一故障码拒绝（不新增码位，R90） / recheck mismatch, same fault code, no new code
    bError   := TRUE;                           // 置故障标志 / raise the fault flag
    bValid   := FALSE;                          // 结果不可用 / result unusable
    sField   := '';                             // 字段回空，绝不交出不完整字段 / field emptied, never hand out an incomplete one
    uFieldLen := 0;                             // 写入长度回 0 / written length back to zero
    FC_DL_IntToFixedField := FALSE;             // 返回失败 / return failure
    RETURN;
END_IF

uFieldLen := INT_TO_UINT(nWUse);                // 写入字符数 = 生效宽度 / written length equals the effective width
bValid    := TRUE;                              // 结果可用 / result usable
FC_DL_IntToFixedField := TRUE;                  // 编码成功 / encoding succeeded
END_FUNCTION
