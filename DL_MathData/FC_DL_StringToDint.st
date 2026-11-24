(*
    组件名称 : FC_DL_StringToDint
    所属子库 : DL_MathData
    当前版本 : 1.0.2
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : 整数字符串严格解析，补 FC_DL_StringToLReal 的整数族缺口（配方号 / 站号 / 批次号）。
              取舍 ①：不委托任何平台串转数值内建 —— 三家平台对非法字符、前导空格、符号重复的处理各不相同，
              有的返回 0、有的抛异常、有的静默截断，且都不告诉调用方错在第几位；现场最贵的不是「失败」，
              而是「成功但值不对」。本件逐字符推进，判断口径完全一致，并给出首个非法字符位置。
              取舍 ②：升位到 LINT 累加，每步先判界再落账 —— DINT 域中间量在 214748364 × 10 + 9 处已越界，
              直接在 DINT 里累加必然回绕；LINT 域足够宽，判界判的是 LINT 与 DINT 上下界的比较，安全。
              取舍 ③：负域上界取 2147483648 而非 2147483647 —— DINT_MIN 的绝对值比 DINT_MAX 大 1，
              用同一个上界会把 "-2147483648" 误判溢出（有符号整数边界必须双侧分开写，禁单侧 ABS 判据）。
              取舍 ④：溢出后返回「夹到边界」的值并置 bValid = FALSE —— 夹域值便于现场看出「方向对了但超了」，
              比返回 0 更容易定位问题；同时绝不把夹域值当有效值输出。
    开源溯源 : 原创实现（T0-5/T0-6 变体线）。字符判定与位置报错口径与库内 FC_DL_StringToLReal 同源，；本件为 IEC 61131-3 标准语义的道莅防御性实现（原创实现，零外部源码复制）。
              但字符集、累加类型、溢出判据全部按整数域重写。无外部源码参考，码位与分级 100% 自有。
    本文件内含 : FUNCTION FC_DL_StringToDint（单 POU）
                 同文件 TYPE E_DL_StrToDintState（归属本子库，全库唯一）
    依 赖 : 无 DL_ 内部依赖；Standard.library: LEN / MID / FIND
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 空串闸 + 非法字符定位 + 双侧溢出判界 + WHILE 守卫计数器
              R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ ENUM + CASE + ELSE 兜底（非法状态落 038C）
              R7 N/A 无定时器、无沿检测实例 ｜ R8 ✓ 上下界、长度上限、守卫上限全常量化
    错误码   : 16#0001_0448 [信息级] 前后空格已忽略，解析正常，bValid = TRUE
               16#0001_0449 [信息级] 预留禁用（不得挪用）
               16#0001_038A [故障级] 空串或仅符号，nErrPos = 长度 + 1，返回 0，bValid = FALSE
               16#0001_038B [故障级] 数值溢出，返回夹到边界的值，bValid = FALSE，bError = TRUE（R41 P0-3 配对补齐）
               16#0001_038C [故障级] 非法字符（含 CASE 落 ELSE 的非法状态兜底，不新占码位），返回 0，bValid = FALSE
    码位总账 : 16#0001_0448 用 / 16#0001_0449 预留 ｜ 16#0001_038A 用 / 16#0001_038B 用 / 16#0001_038C 用
    遗留假设 : ① MID 参数序按 IEC 标准为 MID(串, 长度, 位置)，库内既有件同序；若某平台改为 MID(串, 位置, 长度)，
              本件会取到错字符 —— 属已知平台差异，须在编译门槛里核对（现有库内 9 处用法同序，风险已收敛）。
              ② FIND 返回 1 基位置、未命中返回 0，为 Standard.library 口径推导，未逐平台实测。
              ③ 字符串比较只用 = 与 <>，不用 < / >（部分平台未实现 STRING 排序比较），故数字字符判定走 FIND 表查。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 3 入库
        2026-11-16  v1.0.1  R21 终审修复（轻微）：溢出分支原先只置 bOverflow / bAbort，未写 nErrPos，
                            导致 eErr = 038B（故障级）与 nErrPos = 0（「无错」哨兵）并存，现场按位置
                            指向排错时会得到「有故障但无位置」的矛盾诊断。现溢出位与非法字符位同口径
                            写入 nErrPos。对外引脚契约、返回值夹域策略、码位均不变。
        2026-11-19  v1.0.2  R41 P0-3 返修（R40 发现）：段 4 溢出出口 eErr := 16#0001_038B 原未
                            配对 bError := TRUE（R101 配对缺失），故障级码静默。现赋值行 3 行内
                            显式补配对置位，码表同步登记。VERSION/MANUAL 同步升级。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StrToDintState（归属本函数，与其同文件发布，全库唯一）
 * 含义: 逐字符解析的四态推进，成员值写死便于工程持久化
 *----------------------------------------------------------------------------*)
TYPE E_DL_StrToDintState :
(
    eLeadSpace := 0,    // 前导空格态：跳空格，遇非空格转符号态 / leading blank state, moves to the sign state on any other character
    eSign      := 10,   // 符号态：取前导正负号或直接进数字态 / sign state, consumes the leading sign or falls through to the digits
    eDigits    := 20,   // 数字态：逐位累加，遇尾随空格转结束态 / digits state, accumulates and moves to done on a trailing blank
    eDone      := 30    // 结束态：只允许尾随空格，别的字符一律非法 / done state, only trailing blanks are accepted
);
END_TYPE

FUNCTION FC_DL_StringToDint : DINT
VAR_INPUT
    sIn             : STRING;          // 待解析文本，最长 255 字符，允许前后空格 [字符] / input text, up to 255 characters, blanks allowed on both ends [char]
    bAllowSign      : BOOL := TRUE;    // 是否允许前导 +/− 号 / whether a leading sign is allowed
END_VAR
VAR_OUTPUT
    eErr            : UDINT;           // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;            // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag, TRUE on fault-level eErr
    bValid          : BOOL;            // 返回值是否可用 / result usable flag
    nErrPos         : INT;             // 首个非法字符位置（1 基），0 = 无错 [字符] / position of the first illegal character, 1 based, zero means no error [char]
END_VAR
VAR
    eState          : E_DL_StrToDintState;   // 解析状态机当前态 / current parse state
    nLen            : INT;             // 文本长度，入口锁存一次，其后全部取自该副本 [字符] / latched text length, every later bound comes from this copy [char]
    nPos            : INT;             // 字符游标（1 基）[字符] / character cursor, 1 based [char]
    nGuard          : DINT;            // WHILE 防死锁守卫计数 [次] / loop guard counter [count]
    nDigitVal       : INT;             // 当前字符的数字值，未命中为 −1 [无量纲] / numeric value of the current character, minus one when not a digit [dimensionless]
    nDigits         : INT;             // 已接受的有效数字位数 [位] / number of accepted digits [digit]
    sChar           : STRING(1);       // 当前字符，由标准 MID 取出 [字符] / current character read with the standard MID [char]
    bNeg            : BOOL;            // 负数标志，由前导符号决定 / negative flag set by the leading sign
    bAbort          : BOOL;            // 中止标志，置位后立即退出扫描 / abort flag, the scan stops as soon as it is set
    bOverflow       : BOOL;            // 溢出标志 / overflow flag
    bSpaceIgnored   : BOOL;            // 是否忽略过空格（前导或尾随）/ whether any blank was skipped, leading or trailing
    liAcc           : LINT;            // 升位累加器 [无量纲] / widened accumulator [dimensionless]
    liNext          : LINT;            // 下一拍候选累加值，先判界再落账 [无量纲] / candidate accumulator tested before it is committed [dimensionless]
    liLimit         : LINT;            // 当前符号方向下的累加上界 [无量纲] / accumulator limit for the current sign [dimensionless]
END_VAR
VAR CONSTANT
    DL_DINT_MAX         : DINT := 2147483647;        // DINT 上界，正域累加极限 [无量纲] / DINT upper bound, the positive accumulation limit [dimensionless]
    DL_DINT_MIN         : DINT := -2147483648;       // DINT 下界，负域溢出回退值 [无量纲] / DINT lower bound, the negative saturation value [dimensionless]
    DL_LINT_MAX_DINT    : LINT := 2147483647;        // 正域 LINT 判界值 [无量纲] / positive domain limit in LINT [dimensionless]
    DL_LINT_ABS_MIN     : LINT := 2147483648;        // 负域 LINT 判界值 = |DINT_MIN|，比正域大 1 [无量纲] / negative domain limit equal to the magnitude of DINT_MIN [dimensionless]
    DL_LINT_TEN         : LINT := 10;                // 十进制进位基数 [无量纲] / decimal radix [dimensionless]
    DL_STR_MAXLEN       : INT := 255;                // 文本长度上限 [字符] / text length upper bound [char]
    DL_STR_GUARD_MAX    : DINT := 600;               // 守卫上限，须大于 255 + 2 次不推进状态 / guard limit, larger than the length plus two non advancing states
    DL_STR_ONE          : INT := 1;                  // 单位哨兵 [无量纲] / unity sentinel [dimensionless]
    DL_STR_BLANK        : STRING(1) := ' ';          // 空格字符，前导与尾随都按它判 [字符] / blank character used for both ends [char]
    DL_STR_DIGITS       : STRING := '0123456789';    // 数字字符表，FIND 命中位置 − 1 即数字值 [字符] / digit table, the FIND position minus one is the value [char]
    DL_ERR_NONE         : UDINT := 16#0000_0000;     // 无故障 / no error
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset the return value and the error state
FC_DL_StringToDint := 0;                    // 故障缺省返回 0 / fault default returns zero
eErr           := DL_ERR_NONE;              // 预置无错误 / preset no error
bError         := FALSE;                    // 预置无故障 / preset no fault
bValid         := FALSE;                    // 预置结果不可用 / preset unusable
nErrPos        := 0;                        // 0 表示无错 / zero means no error
eState         := E_DL_StrToDintState.eLeadSpace;   // 起始态为前导空格态 / start in the leading blank state
nLen           := LEN(sIn);                 // 长度只锁存一次，禁循环内重复 LEN / latch the length once, never call LEN again in the loop
nPos           := DL_STR_ONE;               // 游标从 1 开始（MID 为 1 基）/ the cursor starts at one because MID is one based
nGuard         := 0;                        // 守卫清零 / clear the guard
nDigits        := 0;                        // 有效位数清零 / clear the digit count
nDigitVal      := 0;                        // 数字值清零 / clear the digit value
bNeg           := FALSE;                    // 预置正数 / preset positive
bAbort         := FALSE;                    // 预置不中止 / preset no abort
bOverflow      := FALSE;                    // 预置无溢出 / preset no overflow
bSpaceIgnored  := FALSE;                    // 预置未忽略空格 / preset no blank skipped
liAcc          := 0;                        // 累加器清零 / clear the accumulator
liNext         := 0;                        // 候选值清零 / clear the candidate
liLimit        := DL_LINT_MAX_DINT;         // 缺省按正域判界 / default to the positive limit
sChar          := '';                       // 字符缓冲清空 / clear the character buffer

// 段 2｜逐字符状态机：四态推进，ELSE 兜底拦非法状态 / segment 2, four state machine with an ELSE backstop
WHILE (nPos <= nLen) AND (NOT bAbort) AND (nGuard <= DL_STR_GUARD_MAX) DO
    sChar := MID(sIn, DL_STR_ONE, nPos);    // 取当前位置的一个字符 / take one character at the current position
    CASE eState OF
        E_DL_StrToDintState.eLeadSpace :
            IF sChar = DL_STR_BLANK THEN
                bSpaceIgnored := TRUE;                  // 前导空格已忽略 / a leading blank was skipped
                nPos := nPos + DL_STR_ONE;              // 前进一格 / advance one position
            ELSE
                eState := E_DL_StrToDintState.eSign;    // 转符号态，本拍不消费字符，下一轮重取同一字符 / move to the sign state without consuming this character
            END_IF

        E_DL_StrToDintState.eSign :
            IF (sChar = '+') OR (sChar = '-') THEN
                IF NOT bAllowSign THEN
                    eErr   := 16#0001_038C;             // 不允许符号却出现符号（故障级）/ a sign appeared although it is forbidden
                    bError := TRUE;                     // 置故障标志 / raise the fault flag
                    nErrPos := nPos;                    // 定位到符号位 / point at the sign
                    bAbort := TRUE;                     // 中止扫描 / abort the scan
                ELSE
                    bNeg := (sChar = '-');              // 负号判定 / detect the minus sign
                    IF bNeg THEN
                        liLimit := DL_LINT_ABS_MIN;     // 负域上界比正域大 1 / the negative limit is one larger
                    ELSE
                        liLimit := DL_LINT_MAX_DINT;    // 正域上界 / positive domain limit
                    END_IF
                    nPos   := nPos + DL_STR_ONE;        // 消费符号 / consume the sign
                    eState := E_DL_StrToDintState.eDigits;   // 转数字态 / move to the digit state
                END_IF
            ELSE
                eState := E_DL_StrToDintState.eDigits;  // 无符号直接进数字态 / no sign, go straight to the digits
            END_IF

        E_DL_StrToDintState.eDigits :
            IF sChar = DL_STR_BLANK THEN
                bSpaceIgnored := TRUE;                  // 尾随空格开始 / the trailing blanks begin
                eState := E_DL_StrToDintState.eDone;    // 转结束态，余下只允许空格 / move to done, only blanks may follow
                nPos   := nPos + DL_STR_ONE;            // 前进一格 / advance one position
            ELSE
                nDigitVal := FIND(DL_STR_DIGITS, sChar) - DL_STR_ONE;   // 命中 0~9，未命中 −1 / zero to nine when found, minus one otherwise
                IF nDigitVal < 0 THEN
                    eErr    := 16#0001_038C;            // 非法字符（故障级）/ illegal character, fault level
                    bError  := TRUE;                    // 置故障标志 / raise the fault flag
                    nErrPos := nPos;                    // 定位到首个非法字符 / point at the first illegal character
                    bAbort  := TRUE;                    // 中止扫描 / abort the scan
                ELSE
                    liNext := liAcc * DL_LINT_TEN + INT_TO_LINT(nDigitVal);   // 先算候选值 / compute the candidate first
                    IF liNext > liLimit THEN
                        bOverflow := TRUE;              // 越界即溢出，不落账 / beyond the limit means overflow, not committed
                        nErrPos   := nPos;              // 溢出位也必须定位，否则 nErrPos = 0 会被读成「无错」/ locate the overflowing digit, zero would read as no error
                        bAbort    := TRUE;              // 中止扫描 / abort the scan
                    ELSE
                        liAcc   := liNext;              // 落账 / commit
                        nDigits := nDigits + DL_STR_ONE;   // 有效位加一 / one more digit accepted
                        nPos    := nPos + DL_STR_ONE;   // 前进一格 / advance one position
                    END_IF
                    IF nPos > nLen THEN
                        eState := E_DL_StrToDintState.eDone;   // 已到串尾，转结束态 / reached the end, move to done
                    END_IF
                END_IF
            END_IF

        E_DL_StrToDintState.eDone :
            IF sChar = DL_STR_BLANK THEN
                bSpaceIgnored := TRUE;                  // 尾随空格继续忽略 / keep skipping the trailing blanks
                nPos := nPos + DL_STR_ONE;              // 前进一格 / advance one position
            ELSE
                eErr    := 16#0001_038C;                // 尾随非法字符（故障级）/ illegal trailing character, fault level
                bError  := TRUE;                        // 置故障标志 / raise the fault flag
                nErrPos := nPos;                        // 定位 / point at the position
                bAbort  := TRUE;                        // 中止扫描 / abort the scan
            END_IF

    ELSE
        // 非法状态兜底：枚举被外部改写或内存损伤，一律按「输入不可解析」处置（R90：不新占码位）
        eState   := E_DL_StrToDintState.eDone;          // 强制回已知态 / force back to a known state
        eErr     := 16#0001_038C;                      // 复用非法字符码 / reuse the illegal character code
        bError   := TRUE;                              // 置故障标志 / raise the fault flag
        nErrPos  := nPos;                              // 定位当前位 / point at the current position
        bAbort   := TRUE;                              // 中止扫描 / abort the scan
    END_CASE
    nGuard := nGuard + 1;                              // 守卫递增 / increment the guard
END_WHILE

// 段 3｜守卫复检：理论不可达（长度 ≤ 255，不推进状态最多 2 次）/ segment 3, guard re-check, unreachable in theory
IF nGuard > DL_STR_GUARD_MAX THEN
    FC_DL_StringToDint := 0;        // 不给可疑结果 / never emit a suspicious result
    eErr   := 16#0001_038C;         // 扫描失控按不可解析处置 / a runaway scan is treated as unparsable
    bError := TRUE;                 // 置故障标志 / raise the fault flag
    nErrPos := nPos;                // 定位 / point at the current position
    RETURN;                         // bValid 保持 FALSE / bValid stays FALSE
END_IF

// 段 4｜非法/溢出已中止：直接出口（故障行为已在扫描中定性）/ segment 4, exit when the scan was aborted
IF bAbort THEN
    IF bOverflow THEN
        IF bNeg THEN
            FC_DL_StringToDint := DL_DINT_MIN;   // 负域夹到下界 / saturate to the negative bound
        ELSE
            FC_DL_StringToDint := DL_DINT_MAX;   // 正域夹到上界 / saturate to the positive bound
        END_IF
        eErr := 16#0001_038B;        // 溢出已夹边界（故障级）/ overflow saturated, fault level
        bError := TRUE;              // 故障码配对置位（R101 配对，R41 P0-3 补齐）/ pair the fault flag with the fault code
    ELSE
        FC_DL_StringToDint := 0;     // 语法错误返回 0 / a syntax error returns zero
    END_IF
    RETURN;                          // bValid 保持 FALSE / bValid stays FALSE
END_IF

// 段 5｜空串或仅符号闸 / segment 5, empty string or sign-only gate
IF nDigits = 0 THEN
    FC_DL_StringToDint := 0;         // 无有效数字返回 0 / no digit at all, return zero
    eErr    := 16#0001_038A;         // 空串或仅符号（故障级）/ empty or sign only, fault level
    bError  := TRUE;                 // 置故障标志 / raise the fault flag
    nErrPos := nLen + DL_STR_ONE;    // 指向「串尾后一位」，与库内同族口径一致 / point past the end, consistent with the sibling component
    RETURN;                          // bValid 保持 FALSE / bValid stays FALSE
END_IF

// 段 6｜符号落定（下界情形在 LINT 域取负不会回绕）/ segment 6, apply the sign, negating inside LINT never wraps
IF bNeg THEN
    FC_DL_StringToDint := LINT_TO_DINT(-liAcc);   // 负域已在判界时放宽到 2147483648，故 DINT_MIN 可表达 / the limit was relaxed, so DINT_MIN is representable
ELSE
    FC_DL_StringToDint := LINT_TO_DINT(liAcc);    // 正域 / positive domain
END_IF

// 段 7｜空格提示与出口 / segment 7, blank hint and exit
IF bSpaceIgnored THEN
    eErr := 16#0001_0448;            // 前后空格已忽略（信息级，不置 bError）/ blanks ignored, info level
END_IF
bValid := TRUE;                      // 结果可用 / the result is usable
END_FUNCTION
