(*
    FC_DL_DintToStringTrim —— DINT 到 STRING 的防御字符串化
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（DINT → STRING，去前导空格与长度钳位）；
                委托平台内建 DINT_TO_STRING 与标准串函数 LEN / MID / LEFT，本件不重实现格式化内核；
                空格修剪、四步截断样板、目标长度闸、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 数值要拼进 CSV 行、报文帧、条码内容、文件名时，必须先字符串化。
                各平台 DINT_TO_STRING 的右对齐习惯不一：有的前置空格补齐到固定宽度，
                有的不留空格。带空格的数值混进 CSV 会多出一列，拼进报文会错位一个字节，
                而这类故障在 PLC 侧完全静默，只有上位机解析时才暴露。
                核心防御：① 逐字符定位首个非空格后一次 MID 截取，杜绝「逐字符拼串」的
                   长度与性能问题（拼串会随长度平方级增长）。
                ② 扫描用定长 FOR（上界 255），禁用 WHILE——串函数异常时 WHILE 会死循环，
                   FOR 上界结构性封顶。
                ③ 截断走四步样板（R37）：先把长度一次锁存 → 与目标宽度比较 →
                   截断标志置位先于任何写入 → 按 bAllowTrunc 分路；不允许截断时返回空串
                   并升故障级，绝不返回半截数值——半截数值形如把 12345 写成 123，
                   上位机会把它当成真实数据。
                ④ uTargetMax 引脚钳位在 1~255：0 长度目标无意义；255 是 STRING 型上限（R49 口径），
                   USINT 类型本身的 255 上界即为其第二道保险。
                职责边界：LREAL 字符串化（含非有限值统一文本）归 FC_DL_LrealToStringTrim；
                串处理九函数归 T0-6 家族；本件只管整型方向。
    编译门槛  : 主路径依赖平台内建 DINT_TO_STRING 与标准串函数 LEN / MID / LEFT。
                DINT_TO_STRING 的返回宽度平台间不同（有 11 字符起的多种取值），
                故本件不假设其宽度，一律按 LEN 实测后处理，必要时再按目标长度钳位。
    错误码    : 16#0001_0426 已修剪前导空格（bTrimmed 可查）——信息级，值可用
                16#0001_0427 发生截断且 bAllowTrunc = TRUE（bTruncated 可查）——信息级，值可用
                16#0001_0357 目标长度非法（uTargetMax = 0，或平台 USINT 上限异常）——故障级，返回空串
                16#0001_0358 需要截断但 bAllowTrunc = FALSE——故障级，返回空串
                16#0001_0359 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0426 用 / 16#0001_0427 用 ｜ 16#0001_0357 用 / 16#0001_0358 用 / 16#0001_0359 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_DintToStringTrim : STRING(255)
VAR_INPUT
    nIn              : DINT;                  // 待字符串化的数值 [无量纲]，全域 / value to serialise [dimensionless], full DINT domain
    uTargetMax       : USINT := 31;           // 目标缓冲可用长度 [字符]，1~255 / usable target length [characters], 1 to 255
    bAllowTrunc      : BOOL := FALSE;         // TRUE = 允许截断；FALSE = 需截断即故障 / TRUE allows truncation, FALSE turns it into a fault
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid           : BOOL;                  // 返回值是否可用（故障级为 FALSE）/ return usable, FALSE on fault level
    bTrimmed         : BOOL;                  // 修剪了前导空格 / leading blanks were trimmed
    bTruncated       : BOOL;                  // 超目标长度发生截断 / truncation to the target length happened
END_VAR
VAR CONSTANT
    DL_STR_CAP_MAX   : USINT := 255;          // STRING 型长度上限 [字符]，R49 口径 / STRING capacity [characters], per R49
    DL_STR_TARGET_MIN : USINT := 1;           // 目标长度下限 [字符] / target length lower bound [characters]
    DL_STR_SCAN_MAX  : INT := 255;            // 扫描上界 [字符]，与 STRING 上限一致 / scan bound [characters], equals the STRING capacity
    DL_STR_BLANK     : STRING(1) := ' ';      // 单个空格字符，修剪判据 / a single blank used by the trim test
    DL_STR_EMPTY     : STRING(1) := '';       // 空串常量，故障缺省返回 / empty string returned on faults
    DL_INT_ZERO      : INT := 0;              // 整型零常量，避免裸字面量 [字符] / integer zero constant [characters]
    DL_INT_ONE       : INT := 1;              // 整型一常量，首个非空格位置起点 [字符] / integer one constant, first non-blank position [characters]
END_VAR
VAR
    sRaw             : STRING(255);           // 内建字符串化原始结果 / raw result of the built-in conversion
    sTrim            : STRING(255);           // 修剪后的中间串 / intermediate string after the trim
    sOut             : STRING(255);           // 最终输出串 / final output string
    nLen             : INT;                   // 原始串有效长度 [字符] / effective length of the raw string [characters]
    nStart           : INT;                   // 首个非空格位置，1 起始，0 = 全为空格 / first non-blank position, 1-based, 0 means all blanks
    nIdx             : INT;                   // 扫描游标 [字符]，1 起始 / scan cursor [characters], 1-based
    nKept            : INT;                   // 修剪后保留长度，一次锁存 [字符] / retained length, latched exactly once [characters]
    nTarget          : INT;                   // 目标长度，由引脚转出 [字符] / target length derived from the pin [characters]
    bFound           : BOOL;                  // 已找到首个非空格标志 / a first non-blank has been found
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_DintToStringTrim := DL_STR_EMPTY;       // 故障缺省返回空串 / fault default returns an empty string
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
bTrimmed := FALSE;                            // 预置未修剪 / preset no trim
bTruncated := FALSE;                          // 预置未截断 / preset no truncation
sOut := DL_STR_EMPTY;                         // 输出串清零 / clear the output string
nKept := DL_INT_ZERO;                         // 保留长度清零 / clear the retained length

// 段 2｜目标长度闸：0 长度目标无意义，先判后算 / segment 2, target length gate
IF uTargetMax < DL_STR_TARGET_MIN THEN
    eErr := 16#0001_0357;                     // 故障级：目标长度非法，返回空串 / fault level, illegal target length, return an empty string
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用 / flag the return as unusable
    RETURN;                                   // 出口，不触碰内建 / exit, the built-in is never touched
END_IF
nTarget := USINT_TO_INT(uTargetMax);          // 目标长度转整型 [字符] / convert the target length into an integer [characters]
IF nTarget > USINT_TO_INT(DL_STR_CAP_MAX) THEN
    nTarget := USINT_TO_INT(DL_STR_CAP_MAX);  // 双保险：按 STRING 上限钳位 [字符] / second line of defence, clamp to the STRING capacity [characters]
END_IF

// 段 3｜主体：委托平台内建字符串化 / segment 3, delegate the built-in conversion
sRaw := DINT_TO_STRING(nIn);                  // 数值 → 原始串（可能含前导空格）/ value to raw string, possibly blank padded

// 段 4｜有效长度一次锁存并钳位 / segment 4, latch the effective length once and clamp it
nLen := LEN(sRaw);                            // 原始串长度 [字符] / raw string length [characters]
IF nLen > DL_STR_SCAN_MAX THEN
    nLen := DL_STR_SCAN_MAX;                  // 超容量按上限钳位 [字符] / clamp to the capacity [characters]
ELSIF nLen < DL_INT_ZERO THEN
    nLen := DL_INT_ZERO;                      // 负长度防御，结构性不可达 [字符] / negative length guard, structurally unreachable [characters]
END_IF

// 段 5｜前导空格修剪：定长 FOR 扫描，禁 WHILE / segment 5, leading blank trim with a bounded FOR loop
nStart := DL_INT_ZERO;                        // 0 表示尚未找到非空格 / zero means no non-blank found yet
bFound := FALSE;                              // 扫描标志预置 / preset the scan flag
FOR nIdx := DL_INT_ONE TO nLen DO
    IF NOT bFound THEN
        IF MID(sRaw, DL_INT_ONE, nIdx) <> DL_STR_BLANK THEN
            nStart := nIdx;                   // 记录首个非空格位置 [字符] / record the first non-blank position [characters]
            bFound := TRUE;                   // 扫描标志置位 / raise the scan flag
        END_IF
    END_IF
END_FOR

IF nStart = DL_INT_ZERO THEN
    sTrim := DL_STR_EMPTY;                    // 全为空格：合法的空结果，不是错误 / all blanks, a legal empty result
ELSE
    sTrim := MID(sRaw, nLen - nStart + DL_INT_ONE, nStart); // 一次截取中间段 / extract the retained segment in one call
    IF nStart > DL_INT_ONE THEN
        bTrimmed := TRUE;                     // 确实修剪了前导空格 / blanks were really trimmed
        eErr := 16#0001_0426;                 // 信息级：已修剪前导空格 / info level, leading blanks were trimmed
    END_IF
END_IF

// 段 6｜四步截断样板（R37）：长度锁存 → 宽度比较 → 标志先置 → 按允许分路 / segment 6, the four-step truncation pattern
nKept := LEN(sTrim);                          // 修剪后长度，一次锁存 [字符] / retained length, latched once [characters]
IF nKept > nTarget THEN
    bTruncated := TRUE;                       // 标志先于任何写入 / the flag precedes every write
    IF bAllowTrunc THEN
        sOut := LEFT(sTrim, nTarget);         // 允许截断：按目标长度截取 / truncation allowed, take the target length
        eErr := 16#0001_0427;                 // 信息级：发生截断，值可用 / info level, truncated, still usable
    ELSE
        eErr := 16#0001_0358;                 // 故障级：需截断但不允许 / fault level, truncation needed but not allowed
        bError := TRUE;                       // 置故障标志 / raise the error flag
        bValid := FALSE;                      // 返回值不可用 / flag the return as unusable
        FC_DL_DintToStringTrim := DL_STR_EMPTY; // 返回空串，绝不返回半截数值 / return an empty string, never a partial number
        RETURN;                               // 出口 / exit
    END_IF
ELSE
    sOut := sTrim;                            // 无需截断，直接采用修剪结果 / no truncation, take the trimmed string
END_IF

// 段 7｜发布结果 / segment 7, publish the result
FC_DL_DintToStringTrim := sOut;               // 输出最终串 / publish the final string
bValid := TRUE;                               // 修剪/截断/直通均可用 / usable in every published path
bError := FALSE;                              // 信息级不置故障（双保险）/ info level never raises a fault, second line of defence
END_FUNCTION
