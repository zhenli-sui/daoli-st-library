(*
    FC_DL_StringConcatEx —— 安全拼接防御包装（超 255 截断显式置 bTruncated，R37 范式）
    ------------------------------------------------------------------
    分类      : DL_MathData / String
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建函数，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R15）
    ------------------------------------------------------------------
    功能说明  : 将 sA 与 sB 拼接到 sResult。严禁直接 CONCAT 后不判长的
                静默截断：先锁存两串有效长度，总长 > 255 时按 R37 范式
                先置 VAR_OUTPUT bTruncated=TRUE 与 eErr=16#0001_0277 再钳位
                （B 段配额 = 255 - A 段长），杜绝静默回夹。复制采用逐字
                符 FOR 循环（跨平台口径），每轮带 255 越界 EXIT 守卫，
                复制后显式写空字符终止符。返回值 TRUE 表示已执行完成。
    错误码    : 0000 正常 / 16#0001_0277 上溢下溢（总长超 255，已显式截断，bTruncated=TRUE）
    修订记录  : 2026-11-16 v1.0.0 首次入库（R15）
*)
FUNCTION FC_DL_StringConcatEx : BOOL
VAR_INPUT
    sA : STRING(255); // 拼接前段 [字符] / front part of the concatenation [chars]
    sB : STRING(255); // 拼接后段 [字符] / rear part of the concatenation [chars]
END_VAR
VAR_OUTPUT
    sResult    : STRING(255); // 结果串 [字符]，A 段接 B 段 / result string [chars], front part followed by rear part
    eErr : UDINT; // 错误码，0=正常，2=超 255 显式截断 / error id, 0=ok, 2=explicit truncation at the 255 cap
    bError     : BOOL; // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid     : BOOL; // 输出是否有效可用，截断降级时为 FALSE / output valid, FALSE for truncated degraded results
    bTruncated : BOOL; // 截断标志，发生 255 截断时 TRUE（R37 范式） / truncation flag, TRUE when the 255 cap truncated content, R37 paradigm
END_VAR
VAR
    nI     : INT; // 循环索引 [字符位序]，1 基 / loop index [char position], 1-based
    nLenA  : INT; // 锁存的 A 段有效长度 [字符] / latched effective length of the front part [chars]
    nLenB  : INT; // 锁存的 B 段有效长度 [字符] / latched effective length of the rear part [chars]
    nTotal : INT; // 拼接总长 [字符] / total concatenated length [chars]
    nUseB  : INT; // B 段实际复制数 [字符]，受 255 配额钳制 / chars actually copied from the rear part [chars], clamped by the 255 quota
END_VAR
VAR CONSTANT
    DL_CC_MAX : INT := 255; // 串型上限 [字符] / string type cap [chars]
END_VAR

// 段 1｜返回值与输出预置，任何早退路径不留脏码 / segment 1, preset return value and outputs
FC_DL_StringConcatEx := TRUE; // 返回值预置 TRUE（已执行口径） / preset return to TRUE, executed semantics
sResult              := ''; // 结果串预置空串 / preset result to the empty string
eErr             := 16#0000_0000; // 错误码预置正常 / preset error id to ok
bError               := FALSE; // 错误标志预置无错 / preset error flag to FALSE
bValid               := TRUE; // 有效标志预置可用 / preset valid flag to TRUE
bTruncated           := FALSE; // 截断标志预置无截断 / preset truncation flag to FALSE

// 段 2｜两段有效长度各一次锁存（空字符截止扫描 + 255 越界守卫） / segment 2, latch both effective lengths once
nI    := 1; // 索引起始 [字符位序] / index start
nLenA := 0; // A 段长度预置 [字符] / preset front length
WHILE nI <= DL_CC_MAX DO
    IF nI > DL_CC_MAX THEN   (* 越界守卫（双重保险） EN: overrun guard *)
        EXIT;
    END_IF
    IF sA[nI] = '$00' THEN   (* A 段首个空字符即串结束 EN: first null char ends the front part *)
        EXIT;
    END_IF
    nLenA := nI; // 记录 A 段最后非空位序 [字符] / record the last non-null position
    nI    := nI + 1; // 每轮自增 / per-iteration increment
END_WHILE
nI    := 1; // 索引复位 / reset index
nLenB := 0; // B 段长度预置 [字符] / preset rear length
WHILE nI <= DL_CC_MAX DO
    IF nI > DL_CC_MAX THEN   (* 越界守卫（双重保险） EN: overrun guard *)
        EXIT;
    END_IF
    IF sB[nI] = '$00' THEN   (* B 段首个空字符即串结束 EN: first null char ends the rear part *)
        EXIT;
    END_IF
    nLenB := nI; // 记录 B 段最后非空位序 [字符] / record the last non-null position
    nI    := nI + 1; // 每轮自增 / per-iteration increment
END_WHILE

// 段 3｜255 截断闸（R37 范式：先判定后写入，严禁静默回夹） / segment 3, the 255 truncation gate, R37 paradigm, decide before writing, silent clipping forbidden
nTotal := nLenA + nLenB; // 拼接总长 [字符] / total length
IF nTotal > DL_CC_MAX THEN
    nUseB := DL_CC_MAX - nLenA; // B 段配额 = 255 减 A 段长，可为 0 / rear quota = 255 minus front length, may be zero
    bTruncated := TRUE; // 显式置截断标志（R37 教训） / set the truncation flag explicitly, lesson R37
    eErr   := 16#0001_0277; // 上溢码：超 255 已截断 / overflow code, truncated at the 255 cap
    bError     := TRUE; // 置错误标志 / raise error flag
    bValid     := FALSE; // 截断降级结果 / degraded truncated output
ELSE
    nUseB := nLenB; // 域内直通 / in-domain pass-through
END_IF

// 段 4｜复制 A 段：FOR 循环 + 255 越界 EXIT 守卫 / segment 4, copy the front part with the overrun guard
FOR nI := 1 TO nLenA DO
    IF nI > DL_CC_MAX THEN       (* 越界守卫（双重保险） EN: overrun guard *)
        EXIT;
    END_IF
    sResult[nI] := sA[nI]; // 逐字符复制 / char-by-char copy
END_FOR

// 段 5｜复制 B 段：目的位序 = A 段长加索引，超 255 即退出 / segment 5, copy the rear part, destination position = front length plus index
FOR nI := 1 TO nUseB DO
    IF (nLenA + nI) > DL_CC_MAX THEN   (* 越界守卫（双重保险） EN: overrun guard *)
        EXIT;
    END_IF
    sResult[nLenA + nI] := sB[nI]; // 逐字符复制 / char-by-char copy
END_FOR

// 段 6｜显式写终止符：总长未满 255 时在下一位置写空字符 / segment 6, write the terminator explicitly
IF nTotal < DL_CC_MAX THEN
    sResult[nTotal + 1] := '$00'; // 空字符终止符 / null terminator
END_IF
END_FUNCTION
