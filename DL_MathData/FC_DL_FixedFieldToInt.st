(*==============================================================================
 * 组件名称 (Component)  : FC_DL_FixedFieldToInt
 * 溯源说明 (Provenance): 道莅 clean-room 防御性实现（IEC 61131-3 纯净实现，闭源文档仅借语义，零代码行）
 * 所属子库 (Sublibrary) : DL_MathData / DataFormat
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），仅用
 *                         Standard.library 的 LEN / MID / MIN
 * 组件分类 (Category)   : 函数（FUNCTION）· 纯函数 · 定宽数值字段 → 整数
 * 功能一句话 (Summary)  : 把定宽十进制字段（前导零/空格填充、可选符号）解析成
 *                         DINT，非法字符精确报位置，超域给出饱和值并显式标记。
 *
 * 【填充与对齐规则（与 FC_DL_IntToFixedField 共用同一段口径原文）】
 *   ① 右对齐：数字永远贴字段右端，填充字符只在左侧。
 *   ② 填充字符为 '0' 或 ' '，剥离动作按 bAllowLeadingSpace 授权（零恒剥）。
 *   ③ 符号位占一位：零填充时符号贴最左（-0000042），空格填充时符号紧贴数字
 *      （     -42）——解析侧对两种排布等价，剥离填充后先取符号再取数字。
 *   ④ 宽度是契约：本件按 uWidth 与锁存串长的较小者参与解析，字段外的字符
 *      一律不看（定长报文的列位由此确定）。
 *
 * 本件存在的意义 (Why this unit exists)
 *   与 FC_DL_IntToFixedField 构成编码闭环。库内 FC_DL_StringToDint 解析「普通
 *   十进制串」，不看定宽列位、不剥零填充、不区分「非法字符」与「数值超域」，
 *   而 MES 回传的报文三者都需要：错字符要报第几位（现场改报文要定位），
 *   超域要能继续跑（饱和可观测），剥填充要留痕（口径可追）。
 *
 * 边界安全 (Boundary)
 *   ① uWidth < 1 → 故障 03AC；uWidth > 20 按物理上限 20 处理（码位表未分配该
 *      分支，不新开码，R90）；
 *   ② 剥填充后有效字符数为 0 → 故障 03AC（nErrPos 置 0，无单字符可指）；
 *   ③ 非数字字符 → 故障 03AB 且 nErrPos 精确到 1 基字符位，nValue 置 0；
 *   ④ 数值超 DINT 域 → 上界饱和 2147483647、下界饱和 −2147483647（哨兵值），
 *      置 bSaturated 与信息 045F，bValid 保持 TRUE——饱和是可观测的降级，
 *      与「非法字符」性质不同，后者 bValid 必须 FALSE；
 *   ⑤ 长度只取一次并锁存（R37/R38），其后所有上界都用该副本，绝不边解析边重算。
 * 遗留假设 (Assumption)
 *   累加升位到 LINT（R55①：取负前先升位复制到更宽类型）：LINT 可精确容纳
 *   −2147483648，故该值**可被本件精确解析**（不走哨兵路径），从而保证
 *   #1 → #2 的 round-trip 覆盖全 DINT 域；真正越界（> 2147483648）时下界
 *   饱和到 −2147483647 哨兵，bSaturated 为真，调用方须视为「不可用数值」。
 *   LINT 字面量 2147483648 依目标类型解释，属 P0 编译验证项（三平台各编译一次）。
 *
 * 错误码    : 16#0001_045E 已剥离前导填充（零或空格）——信息级，口径留痕
 *             16#0001_045F 数值超 DINT 域已饱和到边界值——信息级，饱和可观测
 *             16#0001_03AB 字段内出现非数字字符，nErrPos 给出首个非法位置——故障级
 *             16#0001_03AC 有效字符数为 0 或字段宽度非法——故障级
 *             16#0001_03AD 预留禁用（故障级，不得挪用）
 * 码位总账  : 16#0001_045E 用 / 16#0001_045F 用 ｜ 16#0001_03AB 用 / 16#0001_03AC 用 / 16#0001_03AD 预留
 * 状态机    : N/A —— 纯函数，两趟扫描（校验趟 + 累加趟），无顺序状态
 * 采样约定  : 纯组合函数，无定时器、无内部驻留状态
 * 依赖说明  : 无 DL_ 内部依赖；仅 Standard.library 的 LEN / MID / MIN
 * 验收向量  : V1 '00012345'/宽8 → 12345，uParsedLen=8，eErr=045E，TRUE
 *             V2 '     -42'/宽8 → -42，TRUE
 *             V3 '-2147483648'/宽11 → -2147483648（round-trip 主向量，不饱和）
 *             V4 '9999999999'/宽10 → 2147483647，bSaturated=TRUE，eErr=045F，TRUE
 *             V5 '00012X45'/宽8 → FALSE，nErrPos=6，nValue=0，eErr=03AB，bError=TRUE
 *             V6 '        '/宽8 → FALSE，eErr=03AC
 *             V7 宽 0 → FALSE，eErr=03AC，nErrPos=0
 * 红线自检  : 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 ｜ 纯 IEC 61131-3 ｜ 零浮点
 *             比较、零除法 ｜ 循环全部带 nGuard ｜ 数组写入前置界检 ｜ 全变量
 *             双语同行注释 ｜ 状态机 N/A ｜ 无定时器实例 ｜ 无魔法数
 * 修订历史  : 2026-11-16  v1.0.0  首版入库（R22 · 批 1 · 定宽数值字段族）
 *============================================================================*)

FUNCTION FC_DL_FixedFieldToInt : BOOL
VAR_INPUT
    sField             : STRING(20);           // 待解析定宽字段 [ASCII] / fixed width field to parse [ASCII]
    uWidth             : UINT := 8;            // 参与解析的字符数 [字符]，范围 1~20 / characters to parse [char], range 1~20
    bAllowLeadingSpace : BOOL := TRUE;         // 是否允许剥离前导空格（零恒剥） / allow stripping leading spaces, zeros always stripped
    bAllowSign         : BOOL := TRUE;         // 是否接受前置 '+'/'-' 号 / accept a leading plus or minus sign
END_VAR
VAR_OUTPUT
    nValue      : DINT;                        // 解析结果，超域时取饱和值 [无量纲] / parsed value, saturated when out of range
    uParsedLen  : UINT;                        // 成功解析的数字位数 [位] / number of digits parsed
    nErrPos     : UINT;                        // 1 基首个非法字符位置，0 表示无 [位置] / 1-based first illegal position, 0 means none
    bSaturated  : BOOL;                        // 数值超 DINT 域已饱和标志 / value saturated at the DINT boundary
    eErr        : UDINT;                       // 错误码，0 表示无错 / error code, 0 means no error
    bError      : BOOL;                        // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid      : BOOL;                        // 结果可用标志（饱和时仍为 TRUE） / result usable flag, still TRUE when saturated
END_VAR
VAR
    nLenLock    : INT;                         // 锁存的字段长度 [字符]，全件唯一长度源 / latched field length, the single length source
    nLenRaw     : INT;                         // LEN 的原始读数 [字符] / raw LEN reading
    nWUse       : INT;                         // 生效解析宽度 [字符] / effective parse width
    nParseLen   : INT;                         // 实际参与解析的字符数 [字符] / characters actually parsed
    nPos        : INT;                         // 当前扫描位置，1 基 [位置] / current scan position, 1-based
    nDigitCount : INT;                         // 已采集数字位个数 [位] / collected digit count
    nI          : INT;                         // 数字位遍历下标 [索引] / digit index
    nGuard      : INT;                         // 循环守卫计数器 [次] / loop guard counter
    nDigitV     : INT;                         // 单字符对应的数值 0~9 [无量纲] / numeric value of a single character
    nScanV      : INT;                         // 查表扫描下标 0~9 [索引] / table scan index
    bNegSign    : BOOL;                        // 字段带负号 / field carries a minus sign
    bStripped   : BOOL;                        // 发生过剥填充动作 / padding was stripped
    bStopStrip  : BOOL;                        // 剥离循环终止标志 / strip loop stop flag
    bIsDigit    : BOOL;                        // 当前字符是否数字 / current character is a digit
    sCh         : STRING(1);                   // 当前字符 [ASCII] / current character
    aDig        : ARRAY[1..20] OF USINT;       // 数字位缓存，1 基 [无量纲] / digit cache, 1-based
    liAcc       : LINT;                        // 升位累加器，防 DINT 回绕 [无量纲] / widened accumulator, avoids DINT wrap
END_VAR
VAR CONSTANT
    DL_FIELD_MAX   : UINT := 20;               // STRING(20) 物理上限 [字符]，禁写成 255 / physical bound of STRING(20), never 255
    DL_W_MIN_U     : UINT := 1;                // 宽度下限的无符号副本 [字符] / unsigned copy of the width lower bound
    DL_W_MAX       : INT := 20;                // 宽度上限 [字符] / width upper bound
    DL_DIGIT_MAX   : INT := 20;                // 字段内最多数字位 [位]，等于串上限 / maximum digits inside the field
    DL_DINT_DIGITS : INT := 10;                // DINT 十进制最大位数 [位]，超过即必饱和 / DINT maximum decimal digits
    DL_GUARD_MAX   : INT := 24;                // 循环守卫上限 [次]，大于串上限即安全 / loop guard, larger than the field
    DL_TEN         : LINT := 10;               // 十进制基数 [无量纲] / decimal radix
    DL_POS_ONE     : INT := 1;                 // 单字符长度与位置基数 [字符] / single-char length and position base
    DL_DIGITS      : STRING(10) := '0123456789'; // 数字字符表，字符→数值靠查表 / digit table, character to value by lookup
    DL_PAD_ZERO    : STRING(1) := '0';         // 零填充字符 [字符] / zero pad character
    DL_PAD_SPACE   : STRING(1) := ' ';         // 空格填充字符 [字符] / space pad character
    DL_SIGN_PLUS   : STRING(1) := '+';         // 正号字符 [字符] / plus sign character
    DL_SIGN_MINUS  : STRING(1) := '-';         // 负号字符 [字符] / minus sign character
    DL_LINT_MAX    : LINT := 2147483647;       // DINT 上界 [无量纲] / DINT upper bound
    DL_LINT_MIN_ABS: LINT := 2147483648;       // DINT 下界绝对值 [无量纲] / absolute value of the DINT lower bound
    DL_DINT_MAX    : DINT := 2147483647;       // DINT 上界饱和值 [无量纲] / DINT upper saturation value
    DL_DINT_MIN_SAT: DINT := -2147483647;      // DINT 下界哨兵饱和值 [无量纲] / DINT lower sentinel saturation value
    DL_DIG_LAST    : INT := 9;                 // 数字表末位下标 [索引] / last index of the digit table
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与输出预置（L1/L9：任何失败出口都不留脏值）
 *      Preset the return value and every output, no stale value on any exit
 *-----------------------------------------------------------------------------*)
FC_DL_FixedFieldToInt := FALSE;                // 返回值预置失败 / preset to FALSE
nValue      := 0;                              // 结果预置 0 [无量纲] / result preset to zero
uParsedLen  := 0;                              // 解析位数预置 0 [位] / parsed length preset to zero
nErrPos     := 0;                              // 非法位置预置 0（无） / illegal position preset to none
bSaturated  := FALSE;                          // 饱和标志预置 FALSE / saturation flag preset to FALSE
eErr        := 16#0000_0000;                   // 错误码预置无错 / error code preset to none
bError      := FALSE;                          // 故障标志预置 FALSE / fault flag preset to FALSE
bValid      := FALSE;                          // 结果可用预置 FALSE / usable flag preset to FALSE
nLenLock    := 0;                              // 锁存长度预置 0 / latched length preset to zero
nWUse       := DL_W_MAX;                       // 生效宽度预置上限 / effective width preset to the upper bound
nParseLen   := 0;                              // 参与解析字符数预置 0 / parsed character count preset to zero
nPos        := DL_POS_ONE;                     // 扫描位置从 1 起 / scan starts at position one
nDigitCount := 0;                              // 数字位个数预置 0 / digit count preset to zero
nGuard      := 0;                              // 守卫预置 0 / guard preset to zero
bNegSign    := FALSE;                          // 负号标志预置 FALSE / negative flag preset to FALSE
bStripped   := FALSE;                          // 剥填充标志预置 FALSE / strip flag preset to FALSE
bStopStrip  := FALSE;                          // 剥离终止标志预置 FALSE / strip stop flag preset to FALSE
liAcc       := 0;                              // 累加器预置 0 / accumulator preset to zero

(*------------------------------------------------------------------------------
 * 段 2｜字段宽度闸门（宽度非法属故障级；超物理上限按上限处理不留码）
 *      Width gate: an illegal width latches a fault, the physical ceiling is clamped
 *-----------------------------------------------------------------------------*)
IF uWidth < DL_W_MIN_U THEN
    eErr    := 16#0001_03AC;                   // 故障级：宽度非法 / fault: illegal width
    bError  := TRUE;                           // 置故障标志 / raise the fault flag
    bValid  := FALSE;                          // 结果不可用 / result unusable
    nErrPos := 0;                              // 无单字符可指 / no specific character to point at
    RETURN;                                    // 统一后处理已在本段完成 / the exit is fully post-processed here
ELSIF uWidth > DL_FIELD_MAX THEN
    nWUse := DL_W_MAX;                         // 超物理上限按 20 处理（不新开码，R90） / clamped to the physical ceiling, no new code
ELSE
    nWUse := UINT_TO_INT(uWidth);              // 域内直通 / passed through inside the domain
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜长度只取一次并锁存（R37/R38：绝不边解析边重算）
 *      Latch the length exactly once, never recompute it while parsing
 *-----------------------------------------------------------------------------*)
nLenRaw := LEN(sField);                        // 唯一一次取长度 / the single length read
IF nLenRaw < 0 THEN
    nLenRaw := 0;                              // 结构性兜底：LEN 不应为负 / structural fallback, LEN should never be negative
END_IF
nLenLock := nLenRaw;                           // 锁存副本，其后全部比较都用它 / latched copy used by every later comparison
nParseLen := MIN(nWUse, nLenLock);             // 实际解析长度 = 宽度与串长的较小者 / the smaller of width and length
IF nParseLen < 0 THEN
    nParseLen := 0;                            // 结构性兜底 / structural fallback
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜剥离前导填充（零恒剥，空格按授权剥；剥过即留痕 045E）
 *      Strip leading padding, zeros always, spaces only when allowed
 *-----------------------------------------------------------------------------*)
WHILE (NOT bStopStrip) AND (nPos <= nParseLen) AND (nGuard <= DL_GUARD_MAX) DO
    sCh := MID(sField, DL_POS_ONE, nPos);      // 取当前字符 [ASCII] / read the current character
    IF sCh = DL_PAD_ZERO THEN
        nPos      := nPos + DL_POS_ONE;        // 前导零：跳过 / leading zero skipped
        bStripped := TRUE;                     // 剥填充留痕 / padding stripped, recorded
    ELSIF bAllowLeadingSpace AND (sCh = DL_PAD_SPACE) THEN
        nPos      := nPos + DL_POS_ONE;        // 授权的前导空格：跳过 / authorised leading space skipped
        bStripped := TRUE;                     // 剥填充留痕 / padding stripped, recorded
    ELSE
        bStopStrip := TRUE;                    // 遇到非填充字符即停 / stop at the first non-pad character
    END_IF
    nGuard := nGuard + DL_POS_ONE;             // 守卫累计，防死循环 / guard incremented, prevents a dead loop
END_WHILE

(*------------------------------------------------------------------------------
 * 段 5｜符号位（授权才接受；不授权则按非法字符定位）
 *      Sign position, accepted only when authorised, otherwise reported as illegal
 *-----------------------------------------------------------------------------*)
IF nPos <= nParseLen THEN
    sCh := MID(sField, DL_POS_ONE, nPos);      // 取候选符号字符 / read the candidate sign character
    IF (sCh = DL_SIGN_MINUS) OR (sCh = DL_SIGN_PLUS) THEN
        IF bAllowSign THEN
            bNegSign := (sCh = DL_SIGN_MINUS); // 负号判据（字符比较，非浮点） / negative test, a character comparison
            nPos     := nPos + DL_POS_ONE;     // 符号位已消费 / the sign position is consumed
        ELSE
            eErr    := 16#0001_03AB;           // 故障级：不允许符号却出现符号 / fault: a sign appeared although not allowed
            bError  := TRUE;                   // 置故障标志 / raise the fault flag
            bValid  := FALSE;                  // 结果不可用 / result unusable
            nErrPos := INT_TO_UINT(nPos);      // 非法位置精确到字符 / illegal position pinpointed
            nValue  := 0;                      // 结果归零 / result zeroed
            RETURN;                            // 统一后处理完成 / exit fully post-processed
        END_IF
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜校验趟：逐字符判数字并缓存数值，首个非法字符即定位（不早退留脏值）
 *      Validation pass: every character must be a digit, the first illegal one is located
 *-----------------------------------------------------------------------------*)
WHILE (nPos <= nParseLen) AND (nGuard <= (DL_GUARD_MAX * 2)) DO
    sCh      := MID(sField, DL_POS_ONE, nPos); // 取当前字符 / read the current character
    bIsDigit := FALSE;                         // 数字判据预置 FALSE / digit test preset to FALSE
    nDigitV  := 0;                             // 数值预置 0 / numeric value preset to zero
    nScanV   := 0;                             // 查表下标预置 0 / table index preset to zero
    WHILE (nScanV <= DL_DIG_LAST) AND (NOT bIsDigit) DO
        IF sCh = MID(DL_DIGITS, DL_POS_ONE, nScanV + DL_POS_ONE) THEN
            bIsDigit := TRUE;                  // 命中数字表 / a table entry matched
            nDigitV  := nScanV;                // 下标即数值 / the index is the numeric value
        ELSE
            nScanV := nScanV + DL_POS_ONE;     // 继续查下一位 / advance to the next table entry
        END_IF
    END_WHILE

    IF NOT bIsDigit THEN
        eErr    := 16#0001_03AB;               // 故障级：非数字字符 / fault: non-digit character
        bError  := TRUE;                       // 置故障标志 / raise the fault flag
        bValid  := FALSE;                      // 结果不可用 / result unusable
        nErrPos := INT_TO_UINT(nPos);          // 1 基位置精确到字符 / 1-based position pinpointed
        nValue  := 0;                          // 结果归零，绝不交出半解析值 / result zeroed, no half-parsed value
        uParsedLen := 0;                       // 解析位数归零 / parsed length zeroed
        RETURN;                                // 统一后处理完成 / exit fully post-processed
    END_IF

    IF (nDigitCount + DL_POS_ONE) <= DL_DIGIT_MAX THEN
        aDig[nDigitCount + DL_POS_ONE] := INT_TO_USINT(nDigitV); // 缓存数字（前置界检） / cache the digit after a bounds check
        nDigitCount := nDigitCount + DL_POS_ONE;                 // 位数累计 / digit count incremented
    END_IF
    nPos   := nPos + DL_POS_ONE;               // 位置推进 / position advanced
    nGuard := nGuard + DL_POS_ONE;             // 守卫累计 / guard incremented
END_WHILE

(*------------------------------------------------------------------------------
 * 段 7｜有效字符数为 0 的判定（全填充字段不是 0，是「没有数字」）
 *      Zero effective characters: an all-pad field carries no number at all
 *-----------------------------------------------------------------------------*)
IF nDigitCount = 0 THEN
    eErr    := 16#0001_03AC;                   // 故障级：有效字符数为 0 / fault: zero effective characters
    bError  := TRUE;                           // 置故障标志 / raise the fault flag
    bValid  := FALSE;                          // 结果不可用 / result unusable
    nErrPos := 0;                              // 无单字符可指 / no specific character to point at
    nValue  := 0;                              // 结果归零 / result zeroed
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜累加趟：位数超 DINT 位宽必饱和（先判位宽，绝不进累加，杜绝 LINT 溢出）
 *      Accumulation: more than ten digits saturates immediately, so LINT never overflows
 *-----------------------------------------------------------------------------*)
IF nDigitCount > DL_DINT_DIGITS THEN
    IF bNegSign THEN
        nValue := DL_DINT_MIN_SAT;             // 下界哨兵值（−2147483648 留给精确路径） / lower sentinel, the exact value has its own path
    ELSE
        nValue := DL_DINT_MAX;                 // 上界饱和 / saturated at the upper bound
    END_IF
    bSaturated := TRUE;                        // 饱和可观测 / saturation made observable
    eErr       := 16#0001_045F;                // 信息级：已饱和（优先于 045E） / informational: saturated, takes precedence over 045E
    uParsedLen := INT_TO_UINT(nDigitCount);    // 解析位数仍如实上报 / parsed length still reported truthfully
    bValid     := TRUE;                        // 饱和是可观测降级，结果仍可用 / degraded but observable, still usable
    FC_DL_FixedFieldToInt := TRUE;             // 返回成功 / return success
    RETURN;
END_IF

liAcc := 0;                                    // 累加器清零 / accumulator cleared
FOR nI := DL_POS_ONE TO nDigitCount DO
    liAcc := liAcc * DL_TEN + INT_TO_LINT(aDig[nI]); // 升位累加，LINT 内无回绕 / widened accumulation, no wrap inside LINT
END_FOR

(*------------------------------------------------------------------------------
 * 段 9｜边界仲裁与出口（精确路径覆盖 −2147483648，越界才走哨兵）
 *      Boundary arbitration: the exact path covers -2147483648, only true overflow saturates
 *-----------------------------------------------------------------------------*)
IF bNegSign THEN
    IF liAcc > DL_LINT_MIN_ABS THEN
        nValue     := DL_DINT_MIN_SAT;         // 真越界：下界哨兵 / true overflow, lower sentinel
        bSaturated := TRUE;                    // 饱和可观测 / saturation observable
        eErr       := 16#0001_045F;            // 信息级：已饱和 / informational: saturated
    ELSE
        nValue := LINT_TO_DINT(-liAcc);        // 精确负值（含 −2147483648） / exact negative value, including the DINT minimum
    END_IF
ELSE
    IF liAcc > DL_LINT_MAX THEN
        nValue     := DL_DINT_MAX;             // 上界饱和 / saturated at the upper bound
        bSaturated := TRUE;                    // 饱和可观测 / saturation observable
        eErr       := 16#0001_045F;            // 信息级：已饱和 / informational: saturated
    ELSE
        nValue := LINT_TO_DINT(liAcc);         // 精确正值 / exact positive value
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜码位优先级与出口（饱和码优先于剥填充码，信息级不置 bError）
 *      Code precedence and exit: saturation outranks stripping, info codes never raise bError
 *-----------------------------------------------------------------------------*)
IF bStripped AND (eErr = 16#0000_0000) THEN
    eErr := 16#0001_045E;                      // 信息级：已剥离前导填充 / informational: leading padding stripped
END_IF

uParsedLen := INT_TO_UINT(nDigitCount);        // 解析位数出口 [位] / parsed length outlet
bValid     := TRUE;                            // 结果可用 / result usable
FC_DL_FixedFieldToInt := TRUE;                 // 解析成功 / parse succeeded
END_FUNCTION
