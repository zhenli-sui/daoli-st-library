(*
    FC_DL_StringInsertEx —— 指定位置插入防御包装（位置钳位 + 255 截断显式置标志）
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
    功能说明  : 在 sIn 的 nPos 位序（1 基）前插入 sIns，插入后 sIns 首字
                符位于 nPos 处。处理次序写死：① 锁存源串/插入串长度；
                ② 位置钳位：nPos < 1 钳 1、nPos > len+1 钳 len+1，置 16#0001_01AE；
                ③ 前段/插入段/后段三段配额预分配，插入段配额 = 255 - 前
                段长 - 后段长，超配额时按 R37 范式先置 bTruncated=TRUE 与
                16#0001_027C 再截断；④ 逐字符三段复制，每轮带 255 越界 EXIT 守卫，
                复制后显式写空字符终止符。返回值 TRUE 表示已执行完成。
    错误码    : 0000 正常 / 16#0001_01AE 入参越界（nPos 已钳位） / 16#0001_027C 上溢下溢（结果超 255，已显式截断，bTruncated=TRUE）
    修订记录  : 2026-11-16 v1.0.0 首次入库（R15）
*)
FUNCTION FC_DL_StringInsertEx : BOOL
VAR_INPUT
    sIn  : STRING(255); // 源串 [字符] / source string [chars]
    sIns : STRING(255); // 插入串 [字符] / string to insert [chars]
    nPos : INT; // 插入位序 [字符位序]，1 基，插入后 sIns 首字符居此 / insert position [char position], 1-based, first inserted char lands here
END_VAR
VAR_OUTPUT
    sResult    : STRING(255); // 结果串 [字符] / result string [chars]
    eErr : UDINT; // 错误码，0=正常，1=位置钳位，2=超 255 截断 / error id, 0=ok, 1=position clamped, 2=explicit truncation at the 255 cap
    bError     : BOOL; // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid     : BOOL; // 输出是否有效可用 / output valid
    bTruncated : BOOL; // 截断标志，发生 255 截断时 TRUE（R37 范式） / truncation flag, TRUE when the 255 cap truncated content
END_VAR
VAR
    nI       : INT; // 循环索引 [字符位序]，1 基 / loop index [char position], 1-based
    nLen     : INT; // 锁存的源串有效长度 [字符] / latched effective source length [chars]
    nInsLen  : INT; // 锁存的插入串有效长度 [字符] / latched effective insert length [chars]
    nPosC    : INT; // 钳位后的插入位序 [字符位序] / clamped insert position [char position]
    nF       : INT; // 前段字符数 [字符]，nPos 减一 / front part char count [chars]
    nT       : INT; // 后段字符数 [字符] / rear part char count [chars]
    nInsUse  : INT; // 插入段实际复制数 [字符]，受 255 配额钳制 / chars actually copied from the insert [chars]
    nTot     : INT; // 结果总长 [字符] / total result length [chars]
END_VAR
VAR CONSTANT
    DL_IN_MAX : INT := 255; // 串型上限 [字符] / string type cap [chars]
END_VAR

// 段 1｜返回值与输出预置，任何早退路径不留脏码 / segment 1, preset return value and outputs
FC_DL_StringInsertEx := TRUE; // 返回值预置 TRUE（已执行口径） / preset return to TRUE
sResult              := ''; // 结果串预置空串 / preset result to the empty string
eErr             := 16#0000_0000; // 错误码预置正常 / preset error id to ok
bError               := FALSE; // 错误标志预置无错 / preset error flag to FALSE
bValid               := TRUE; // 有效标志预置可用 / preset valid flag to TRUE
bTruncated           := FALSE; // 截断标志预置无截断 / preset truncation flag to FALSE

// 段 2｜两串有效长度各一次锁存（空字符截止扫描 + 255 越界守卫） / segment 2, latch both effective lengths once
nI      := 1; // 索引起始 [字符位序] / index start
nLen    := 0; // 源串长度预置 [字符] / preset source length
WHILE nI <= DL_IN_MAX DO
    IF nI > DL_IN_MAX THEN    (* 越界守卫（双重保险） EN: overrun guard *)
        EXIT;
    END_IF
    IF sIn[nI] = '$00' THEN   (* 首个空字符即串结束 EN: first null char ends the string *)
        EXIT;
    END_IF
    nLen := nI; // 记录源串最后非空位序 [字符] / record the last non-null position
    nI   := nI + 1; // 每轮自增 / per-iteration increment
END_WHILE
nI      := 1; // 索引复位 / reset index
nInsLen := 0; // 插入串长度预置 [字符] / preset insert length
WHILE nI <= DL_IN_MAX DO
    IF nI > DL_IN_MAX THEN    (* 越界守卫（双重保险） EN: overrun guard *)
        EXIT;
    END_IF
    IF sIns[nI] = '$00' THEN  (* 首个空字符即串结束 EN: first null char ends the string *)
        EXIT;
    END_IF
    nInsLen := nI; // 记录插入串最后非空位序 [字符] / record the last non-null position
    nI      := nI + 1; // 每轮自增 / per-iteration increment
END_WHILE

// 段 3｜位置钳位闸：nPos < 1 钳 1，nPos > len+1 钳 len+1，置 16#0001_01AE / segment 3, position clamp gate, below 1 clamped to 1, beyond len plus 1 clamped to len plus 1, code 1
IF nPos < 1 THEN
    nPosC    := 1; // 下越界钳 1 / clamped to 1
    eErr := 16#0001_01AE; // 入参越界码 / out-of-domain code
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 钳位降级 / degraded output
ELSIF nPos > (nLen + 1) THEN
    nPosC    := nLen + 1; // 上越界钳到串尾后一位 / clamped to one past the end
    eErr := 16#0001_01AE; // 入参越界码 / out-of-domain code
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 钳位降级 / degraded output
ELSE
    nPosC := nPos; // 域内直通 / in-domain pass-through
END_IF
nF := nPosC - 1; // 前段字符数 [字符] / front part char count
nT := nLen - nF; // 后段字符数 [字符] / rear part char count

// 段 4｜插入段配额闸（R37 范式：先判定后写入，严禁静默回夹） / segment 4, insert quota gate, R37 paradigm, decide before writing
IF nInsLen > (DL_IN_MAX - nF - nT) THEN
    nInsUse := DL_IN_MAX - nF - nT; // 插入段配额，可为 0 / insert quota, may be zero
    bTruncated := TRUE; // 显式置截断标志（R37 教训） / set the truncation flag explicitly
    eErr   := 16#0001_027C; // 上溢码：超 255 已截断 / overflow code, truncated
    bError     := TRUE; // 置错误标志 / raise error flag
    bValid     := FALSE; // 截断降级结果 / degraded truncated output
ELSE
    nInsUse := nInsLen; // 域内直通 / in-domain pass-through
END_IF

// 段 5｜复制前段：FOR 循环 + 255 越界 EXIT 守卫 / segment 5, copy the front part with the overrun guard
FOR nI := 1 TO nF DO
    IF nI > DL_IN_MAX THEN        (* 越界守卫（双重保险） EN: overrun guard *)
        EXIT;
    END_IF
    sResult[nI] := sIn[nI]; // 逐字符复制 / char-by-char copy
END_FOR

// 段 6｜复制插入段：目的位序 = 前段长加索引，超 255 即退出 / segment 6, copy the insert part
FOR nI := 1 TO nInsUse DO
    IF (nF + nI) > DL_IN_MAX THEN     (* 越界守卫（双重保险） EN: overrun guard *)
        EXIT;
    END_IF
    sResult[nF + nI] := sIns[nI]; // 逐字符复制 / char-by-char copy
END_FOR

// 段 7｜复制后段：源 sIn 自 nF+1 起，目的位序顺延 / segment 7, copy the rear part from the source
FOR nI := 1 TO nT DO
    IF (nF + nInsUse + nI) > DL_IN_MAX THEN   (* 越界守卫（双重保险） EN: overrun guard *)
        EXIT;
    END_IF
    IF (nF + nI) > DL_IN_MAX THEN             (* 源侧越界守卫 EN: source overrun guard *)
        EXIT;
    END_IF
    sResult[nF + nInsUse + nI] := sIn[nF + nI]; // 逐字符复制 / char-by-char copy
END_FOR

// 段 8｜显式写终止符 / segment 8, write the terminator explicitly
nTot := nF + nInsUse + nT; // 结果总长 [字符] / total result length
IF nTot < DL_IN_MAX THEN
    sResult[nTot + 1] := '$00'; // 空字符终止符 / null terminator
END_IF
END_FUNCTION
