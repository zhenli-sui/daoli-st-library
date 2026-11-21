(*==============================================================================
 * 组件名称 (Component)  : FC_DL_BytesToHexString
 * 所属子库 (Sublibrary) : DL_MathData
 * 归属目录 (Directory)  : C:\Library\DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 函数（FUNCTION）· 纯函数 · 字节数组十六进制编码
 *                         iec-std-wrapper / string / bitstring
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 LEN / MID / CONCAT
 * 溯源声明 (Provenance) : IEC 61131-3 标准语义的道莅防御性实现——内部委托平台标准库语义，
 *                         外围统一错误码 / 钳位 / 双语注释，严禁重实现数学内核。
 * 功能一句话 (Summary)  : 字节数组编码为定宽大写十六进制串，每字节恒出两字符，
 *                         空数组返回空串，计数域外与写出异常双重防御。
 *
 * 功能描述 (Function)   : 先做计数域闸（0 到 127），再逐字节拆高低半字节，
 *                         经 '0123456789ABCDEF' 码表定位拼出两字符，出口校验
 *                         写出长度恰为两倍计数；与 DwordToHexString 互补，
 *                         覆盖变长缓冲的报文与日志场景。
 * 与既有件边界 (Boundary): FC_DL_HexStringToLword 为反向解析单字；本件面向
 *                         数组整体编码，不做前缀、不做分隔符、不做小写。
 * 码位说明 (Codes)      : 信息 16#0002_303C 空数组恒等返回（结果空串）
 *                         故障 16#0002_303D 计数域外（小于 0 或大于 127）
 *                         故障 16#0002_303E 写出长度与两倍计数不一致（防御校验）
 *                         段 16#02_3_3C~3F 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 LEN / MID / CONCAT。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 标准库
 *                         无除法故无除零面 ｜ 移位量 4 与 8 恒小于位宽（归一达标）
 *                         全变量双语同行注释 ｜ 无定时器实例
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 1）
 *============================================================================*)

FUNCTION FC_DL_BytesToHexString : BOOL
VAR_INPUT
    aBytes  : ARRAY[0..127] OF BYTE;    // 源字节数组 [字节]，最多 127 字节 / Source byte array, at most 127 bytes
    nCount  : INT;                      // 参与编码的字节个数 [字节]，域 0 到 127 / Number of bytes to encode, 0 to 127
END_VAR
VAR_OUTPUT
    sHex     : STRING(255);             // 大写十六进制结果 [ASCII]，长度恰为两倍计数 / Uppercase hex result, twice the count
    nWritten : INT;                     // 写出字符数 [字符] / Characters written
    uErrorId : UDINT;                   // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    sTmp   : STRING(255); // 结果累积缓冲 [ASCII] / Result staging buffer
    bCur   : BYTE;        // 当前字节 [字节] / Current byte
    nHi    : INT;         // 高半字节码表下标 [索引] / High nibble table index
    nLo    : INT;         // 低半字节码表下标 [索引] / Low nibble table index
    nI     : INT;         // 字节循环下标 [索引] / Byte loop index
    uCode  : UDINT;       // 码位暂存，出口单点写入 [码] / Code staging
END_VAR
VAR CONSTANT
    DL_BTH_MAXN : INT := 127;               // 最大字节数 [字节]，两倍后仍在 255 内 / Max bytes, doubled stays within 255
    DL_BTH_ONE  : INT := 1;                 // 单字符长度参数 [字符] / Single character length argument
END_VAR

(* 段 1｜输出预置与残留清除 / Pre-set and clear before any branch *)
FC_DL_BytesToHexString := FALSE;
sHex     := '';
sTmp     := '';
nWritten := 0;
uErrorId := 16#0000_0000;
uCode    := 16#0000_0000;

(* 段 2｜计数域闸：契约参数不钳位，域外直接拒绝 / Count gate: a contract value is never clamped *)
IF (nCount < 0) OR (nCount > DL_BTH_MAXN) THEN
    uErrorId := 16#0002_303D;    // 故障级：计数域外 / Fault: count out of domain
    RETURN;
END_IF

(* 段 3｜空数组恒等：信息级告知后直接成功返回 / Empty array identity: inform and succeed *)
IF nCount = 0 THEN
    uErrorId := 16#0002_303C;    // 信息级：空数组恒等返回 / Info: empty array, identity return
    FC_DL_BytesToHexString := TRUE;
    RETURN;
END_IF

(* 段 4｜逐字节编码：高低半字节各查一次码表 / Encode byte by byte: one table lookup per nibble *)
FOR nI := 0 TO (nCount - 1) DO
    bCur := aBytes[nI];                              // 取当前字节 / Take the current byte
    nHi  := BYTE_TO_INT(SHR(bCur, 4));               // 高半字节 0 到 15 / High nibble, 0 to 15
    nLo  := BYTE_TO_INT(bCur AND 16#0F);             // 低半字节 0 到 15 / Low nibble, 0 to 15
    sTmp := CONCAT(sTmp, MID('0123456789ABCDEF', DL_BTH_ONE, nHi + DL_BTH_ONE)); // 高位字符，下标偏 1 / High char, index shifted
    sTmp := CONCAT(sTmp, MID('0123456789ABCDEF', DL_BTH_ONE, nLo + DL_BTH_ONE)); // 低位字符 / Low char
    nWritten := nWritten + 2;                        // 每字节恒两字符 / Exactly two chars per byte
END_FOR

(* 段 5｜写出一致性校验（防御闸）：长度必须恰为两倍计数 / Consistency gate: length must be twice the count *)
IF (LEN(sTmp) <> nWritten) OR (nWritten <> (2 * nCount)) THEN
    uErrorId := 16#0002_303E;    // 故障级：写出链路异常，结果作废 / Fault: write chain broken, voided
    sHex := '';
    RETURN;
END_IF

(* 段 6｜出口装配：结果与码位单点写出 / Exit: single write for result and code *)
sHex := sTmp;
uErrorId := uCode;
FC_DL_BytesToHexString := TRUE;
END_FUNCTION
