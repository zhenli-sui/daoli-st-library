(*
    组件名称 : FC_DL_StringToUdintEx
    所属子库 : DL_MathData
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    溯源声明 : IEC 61131-3 标准语义的道莅防御性实现
              （解析口径复用库内 FC_DL_StringToDint 的四态状态机与判界结构，
                按无符号域重写判界；零外部源码复制，参考实现仅限 MIT/Apache 许可）
    功能描述 : 无符号整数字符串严格解析（UDINT 域，配方号 / 计数器预置 / 批次号）。
              取舍 ①：不委托任何平台串转数值内建——三家平台对非法字符、前导空格、
              符号重复的处理各不相同，有的返回 0、有的抛异常、有的静默截断，且都
              不告诉调用方错在第几位；本件逐字符推进，判断口径完全一致，并给出
              首个非法字符位置。
              取舍 ②：空格一律按非法字符拒绝（与 FC_DL_StringToDint 的「忽略空格
              并提示」口径刻意分叉）——UDINT 域多为机器写入值，隐式吞空格易掩盖
              脏数据，从严拒绝并在 nErrPos 定位。
              取舍 ③：升位到 LINT 累加，每步先判界再落账——UDINT 域中间量在
              429496729 × 10 + 5 处已越界，直接在 UDINT/DINT 里累加必然回绕
              （R241 口径：跨类型降型禁靠隐式回绕兜底）；LINT 域足够宽，判界
              判的是 LINT 与 UDINT 上界的比较，安全。
              取舍 ④：溢出后返回「夹到上界」的值并置 bValid = FALSE——夹域值便于
              现场看出「方向对了但超了」；同时绝不把夹域值当有效值输出。
              取舍 ⑤：负号一律判越域拒绝（含 −0）——UDINT 无负域，负号属语义错误
              而非语法错误，独立占码与非法字符区分。
    本文件内含 : FUNCTION FC_DL_StringToUdintEx（单 POU）
                 同文件 TYPE E_DL_StrToUdintState（归属本函数，全库唯一）
    依 赖    : 无 DL_ 内部依赖；Standard.library: LEN / MID / FIND
    错误码   : 16#0001_03D6 [故障级] 空串或仅符号，nErrPos = 长度 + 1，返回 0，bValid = FALSE
               16#0001_03D7 [故障级] 负值越 UDINT 域（含 −0，从严拒绝），返回 0，bValid = FALSE
               16#0001_03D8 [故障级] 数值溢出，返回夹到上界的值，bValid = FALSE
               16#0001_03D9 [故障级] 非法字符（含 CASE 落 ELSE 的非法状态兜底与扫描失控复用，
                             不新占码位），返回 0，bValid = FALSE
               （R90 反证句：四类故障场景的输出组合互不相同——空串与非法字符返回 0、
                 溢出返回上界夹域值、负值返回 0 但 nErrPos 定位在符号位；返回值加
                 nErrPos 无法唯一还原「空串」与「负值」（同为 0），故两场景各自占码）
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 空串闸 + 非法字符定位 + 先判界后落账 + WHILE 守卫计数器
              R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ ENUM + CASE + ELSE 兜底（非法状态复用 03D9）
              R7 N/A 无定时器、无沿检测实例 ｜ R8 ✓ 上下界、长度上限、守卫上限全常量化
    修订历史 :
        2026-11-19  v1.0.0  首版，R40 批次 3 入库
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StrToUdintState（归属本函数，与其同文件发布，全库唯一）
 * 含义: 逐字符解析的四态推进，成员值写死便于工程持久化
 *----------------------------------------------------------------------------*)
TYPE E_DL_StrToUdintState :
(
    eLeadSpace := 0,    // 起始态：空格按非法字符拒绝，遇其余字符转符号态 ｜ start state, blanks are rejected as illegal, any other character moves to the sign state
    eSign      := 10,   // 符号态：取前导 +/− 号或直接进数字态 ｜ sign state, consumes the leading sign or falls through to the digits
    eDigits    := 20,   // 数字态：逐位累加，遇非数字一律非法 ｜ digits state, accumulates digit by digit, any non-digit is illegal
    eDone      := 30    // 结束态：串尾守卫态，任何字符均非法 ｜ done state, an end-of-string guard, any character here is illegal
);
END_TYPE

FUNCTION FC_DL_StringToUdintEx : UDINT
VAR_INPUT
    sIn             : STRING;           // 待解析文本，最长 255 字符，不允许任何空格 [字符] ｜ input text, up to 255 characters, no blanks allowed [char]
    bAllowSign      : BOOL := FALSE;    // 是否允许前导 +/− 号，UDINT 口径缺省禁止 ｜ whether a leading sign is allowed, the UDINT mode forbids it by default
END_VAR
VAR_OUTPUT
    eErr            : UDINT;           // 错误码，0=正常；16#0001_03XX 故障级 ｜ error id, 0=ok, 16#0001_03XX=fault level
    bError          : BOOL;            // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE ｜ fault flag, TRUE on fault-level eErr
    bValid          : BOOL;            // 返回值是否可用 ｜ result usable flag
    nErrPos         : INT;             // 首个非法字符位置（1 基），0 = 无错 [字符] ｜ position of the first illegal character, 1 based, zero means no error [char]
END_VAR
VAR
    eState          : E_DL_StrToUdintState;  // 解析状态机当前态 ｜ current parse state
    nLen            : INT;             // 文本长度，入口锁存一次，其后全部取自该副本 [字符] ｜ latched text length, every later bound comes from this copy [char]
    nPos            : INT;             // 字符游标（1 基）[字符] ｜ character cursor, 1 based [char]
    nGuard          : DINT;            // WHILE 防死锁守卫计数 [次] ｜ loop guard counter [count]
    nDigitVal       : INT;             // 当前字符的数字值，未命中为 −1 [无量纲] ｜ numeric value of the current character, minus one when not a digit [dimensionless]
    nDigits         : INT;             // 已接受的有效数字位数 [位] ｜ number of accepted digits [digit]
    sChar           : STRING(1);       // 当前字符，由标准 MID 取出 [字符] ｜ current character read with the standard MID [char]
    bNeg            : BOOL;            // 负号标志，由前导符号决定 ｜ negative flag set by the leading sign
    bAbort          : BOOL;            // 中止标志，置位后立即退出扫描 ｜ abort flag, the scan stops as soon as it is set
    bOverflow       : BOOL;            // 溢出标志 ｜ overflow flag
    liAcc           : LINT;            // 升位累加器 [无量纲] ｜ widened accumulator [dimensionless]
    liNext          : LINT;            // 下一拍候选累加值，先判界再落账 [无量纲] ｜ candidate accumulator tested before it is committed [dimensionless]
END_VAR
VAR CONSTANT
    DL_UDINT_MAX_LI    : LINT := 4294967295;     // UDINT 上界的 LINT 判界值 [无量纲] ｜ UDINT upper bound as the LINT test limit [dimensionless]
    DL_LINT_TEN        : LINT := 10;             // 十进制进位基数 [无量纲] ｜ decimal radix [dimensionless]
    DL_STR_MAXLEN      : INT := 255;             // 文本长度上限 [字符] ｜ text length upper bound [char]
    DL_STR_GUARD_MAX   : DINT := 600;            // 守卫上限，须大于 255 + 2 次不推进状态 ｜ guard limit, larger than the length plus two non advancing states
    DL_STR_ONE         : INT := 1;               // 单位哨兵 [无量纲] ｜ unity sentinel [dimensionless]
    DL_STR_DIGITS      : STRING := '0123456789'; // 数字字符表，FIND 命中位置 − 1 即数字值 [字符] ｜ digit table, the FIND position minus one is the value [char]
    DL_ERR_NONE        : UDINT := 16#0000_0000;  // 无故障 ｜ no error
END_VAR

// 段 1｜返回值与错误状态预置 ｜ segment 1, preset the return value and the error state
FC_DL_StringToUdintEx := 0;                   // 故障缺省返回 0 ｜ fault default returns zero
eErr           := DL_ERR_NONE;                // 预置无错误 ｜ preset no error
bError         := FALSE;                      // 预置无故障 ｜ preset no fault
bValid         := FALSE;                      // 预置结果不可用 ｜ preset unusable
nErrPos        := 0;                          // 0 表示无错 ｜ zero means no error
eState         := E_DL_StrToUdintState.eLeadSpace;  // 起始态 ｜ start in the start state
nLen           := LEN(sIn);                   // 长度只锁存一次，禁循环内重复 LEN ｜ latch the length once, never call LEN again in the loop
nPos           := DL_STR_ONE;                 // 游标从 1 开始（MID 为 1 基）｜ the cursor starts at one because MID is one based
nGuard         := 0;                          // 守卫清零 ｜ clear the guard
nDigits        := 0;                          // 有效位数清零 ｜ clear the digit count
nDigitVal      := 0;                          // 数字值清零 ｜ clear the digit value
bNeg           := FALSE;                      // 预置无负号 ｜ preset no negative sign
bAbort         := FALSE;                      // 预置不中止 ｜ preset no abort
bOverflow      := FALSE;                      // 预置无溢出 ｜ preset no overflow
liAcc          := 0;                          // 累加器清零 ｜ clear the accumulator
liNext         := 0;                          // 候选值清零 ｜ clear the candidate
sChar          := '';                         // 字符缓冲清空 ｜ clear the character buffer

// 段 2｜逐字符状态机：四态推进，ELSE 兜底拦非法状态 ｜ segment 2, four state machine with an ELSE backstop
WHILE (nPos <= nLen) AND (NOT bAbort) AND (nGuard <= DL_STR_GUARD_MAX) DO
    sChar := MID(sIn, DL_STR_ONE, nPos);    // 取当前位置的一个字符 ｜ take one character at the current position
    CASE eState OF
        E_DL_StrToUdintState.eLeadSpace :
            // 起始态：空格从严拒绝（取舍 ②），其余字符转符号态 ｜ start state: blanks are strictly rejected, any other character moves to the sign state
            IF sChar = ' ' THEN
                eErr    := 16#0001_03D9;    // 空格按非法字符拒绝（故障级）｜ a blank is rejected as an illegal character
                bError  := TRUE;            // 置故障标志 ｜ raise the fault flag
                nErrPos := nPos;            // 定位到空格位 ｜ point at the blank
                bAbort  := TRUE;            // 中止扫描 ｜ abort the scan
            ELSE
                eState := E_DL_StrToUdintState.eSign;  // 转符号态，本拍不消费字符，下一轮重取同一字符 ｜ move to the sign state without consuming this character
            END_IF

        E_DL_StrToUdintState.eSign :
            IF (sChar = '+') OR (sChar = '-') THEN
                IF NOT bAllowSign THEN
                    eErr   := 16#0001_03D9;     // 不允许符号却出现符号（故障级）｜ a sign appeared although it is forbidden
                    bError := TRUE;             // 置故障标志 ｜ raise the fault flag
                    nErrPos := nPos;            // 定位到符号位 ｜ point at the sign
                    bAbort := TRUE;             // 中止扫描 ｜ abort the scan
                ELSE
                    bNeg   := (sChar = '-');    // 负号判定（取舍 ⑤：负号在出口判越域）｜ detect the minus sign (rejected as out-of-domain at the exit)
                    nPos   := nPos + DL_STR_ONE;   // 消费符号 ｜ consume the sign
                    eState := E_DL_StrToUdintState.eDigits;  // 转数字态 ｜ move to the digit state
                END_IF
            ELSE
                eState := E_DL_StrToUdintState.eDigits;  // 无符号直接进数字态 ｜ no sign, go straight to the digits
            END_IF

        E_DL_StrToUdintState.eDigits :
            // 数字态：数字先判界后落账，非数字一律非法（空格含在内，从严口径）｜ digit state: digits are tested before commit, any non-digit is illegal (blanks included, strict mode)
            nDigitVal := FIND(DL_STR_DIGITS, sChar) - DL_STR_ONE;   // 命中 0~9，未命中 −1 ｜ zero to nine when found, minus one otherwise
            IF nDigitVal < 0 THEN
                eErr    := 16#0001_03D9;            // 非法字符（故障级）｜ illegal character, fault level
                bError  := TRUE;                    // 置故障标志 ｜ raise the fault flag
                nErrPos := nPos;                    // 定位到首个非法字符 ｜ point at the first illegal character
                bAbort  := TRUE;                    // 中止扫描 ｜ abort the scan
            ELSE
                liNext := liAcc * DL_LINT_TEN + INT_TO_LINT(nDigitVal);   // 先算候选值 ｜ compute the candidate first
                IF liNext > DL_UDINT_MAX_LI THEN
                    bOverflow := TRUE;              // 越界即溢出，不落账 ｜ beyond the limit means overflow, not committed
                    nErrPos   := nPos;              // 溢出位也必须定位，否则 nErrPos = 0 会被读成「无错」｜ locate the overflowing digit, zero would read as no error
                    bAbort    := TRUE;              // 中止扫描 ｜ abort the scan
                ELSE
                    liAcc   := liNext;              // 落账 ｜ commit
                    nDigits := nDigits + DL_STR_ONE;   // 有效位加一 ｜ one more digit accepted
                    nPos    := nPos + DL_STR_ONE;   // 前进一格 ｜ advance one position
                END_IF
                IF nPos > nLen THEN
                    eState := E_DL_StrToUdintState.eDone;   // 已到串尾，转结束态守卫 ｜ reached the end, move to the done guard
                END_IF
            END_IF

        E_DL_StrToUdintState.eDone :
            // 结束态：本件从严口径，任何尾随字符（含空格）均非法 ｜ done state: in strict mode any trailing character (blanks included) is illegal
            eErr    := 16#0001_03D9;                // 尾随非法字符（故障级）｜ illegal trailing character, fault level
            bError  := TRUE;                        // 置故障标志 ｜ raise the fault flag
            nErrPos := nPos;                        // 定位 ｜ point at the position
            bAbort  := TRUE;                        // 中止扫描 ｜ abort the scan

    ELSE
        // 非法状态兜底：枚举被外部改写或内存损伤，一律按「输入不可解析」处置（R90：复用非法字符码，不新占码位）
        eState   := E_DL_StrToUdintState.eDone;          // 强制回已知态 ｜ force back to a known state
        eErr     := 16#0001_03D9;                        // 复用非法字符码 ｜ reuse the illegal character code
        bError   := TRUE;                               // 置故障标志 ｜ raise the fault flag
        nErrPos  := nPos;                               // 定位当前位 ｜ point at the current position
        bAbort   := TRUE;                               // 中止扫描 ｜ abort the scan
    END_CASE
    nGuard := nGuard + 1;                              // 守卫递增 ｜ increment the guard
END_WHILE

// 段 3｜守卫复检：理论不可达（长度 ≤ 255，不推进状态最多 2 次）｜ segment 3, guard re-check, unreachable in theory
IF nGuard > DL_STR_GUARD_MAX THEN
    FC_DL_StringToUdintEx := 0;        // 不给可疑结果 ｜ never emit a suspicious result
    eErr   := 16#0001_03D9;            // 扫描失控复用非法字符码（不新占码位）｜ a runaway scan reuses the illegal character code
    bError := TRUE;                    // 置故障标志 ｜ raise the fault flag
    nErrPos := nPos;                   // 定位 ｜ point at the current position
    RETURN;                            // bValid 保持 FALSE ｜ bValid stays FALSE
END_IF

// 段 4｜非法/溢出已中止：直接出口（故障行为已在扫描中定性）｜ segment 4, exit when the scan was aborted
IF bAbort THEN
    IF bOverflow THEN
        FC_DL_StringToUdintEx := 4294967295; // 溢出夹到 UDINT 上界 ｜ overflow saturated to the UDINT upper bound
        eErr := 16#0001_03D8;        // 溢出已夹上界（故障级）｜ overflow saturated, fault level
        bError := TRUE;              // 置故障标志（R45 配对，扫描内溢出只置 bOverflow，出口统一配对）｜ raise the fault flag (R45 pairing)
    ELSE
        FC_DL_StringToUdintEx := 0;  // 语法错误返回 0 ｜ a syntax error returns zero
    END_IF
    RETURN;                          // bValid 保持 FALSE ｜ bValid stays FALSE
END_IF

// 段 5｜空串或仅符号闸 ｜ segment 5, empty string or sign-only gate
IF nDigits = 0 THEN
    FC_DL_StringToUdintEx := 0;         // 无有效数字返回 0 ｜ no digit at all, return zero
    eErr    := 16#0001_03D6;            // 空串或仅符号（故障级）｜ empty or sign only, fault level
    bError  := TRUE;                    // 置故障标志（R45 配对）｜ raise the fault flag (R45 pairing)
    nErrPos := nLen + DL_STR_ONE;       // 指向「串尾后一位」，与库内同族口径一致 ｜ point past the end, consistent with the sibling component
    RETURN;                             // bValid 保持 FALSE ｜ bValid stays FALSE
END_IF

// 段 6｜负值越域闸（取舍 ⑤：负号含 −0 一律从严拒绝）｜ segment 6, negative out-of-domain gate (a minus sign including minus zero is strictly rejected)
IF bNeg THEN
    FC_DL_StringToUdintEx := 0;         // 负值越域返回 0 ｜ out-of-domain negative returns zero
    eErr    := 16#0001_03D7;            // 负值越 UDINT 域（故障级）｜ negative beyond the UDINT domain, fault level
    bError  := TRUE;                    // 置故障标志（R45 配对）｜ raise the fault flag (R45 pairing)
    nErrPos := DL_STR_ONE;              // 定位到符号位（第 1 位）｜ point at the sign position (position one)
    RETURN;                             // bValid 保持 FALSE ｜ bValid stays FALSE
END_IF

// 段 7｜出口装配：累加器域内单点落账 ｜ segment 7, exit assembly: the accumulator is in-domain, commit once
FC_DL_StringToUdintEx := LINT_TO_UDINT(liAcc); // 判界已保证 liAcc ≤ UDINT 上界，降型安全 ｜ the domain test guarantees the accumulator is within the UDINT bound, the down-conversion is safe
bValid := TRUE;                      // 结果可用 ｜ the result is usable
END_FUNCTION
