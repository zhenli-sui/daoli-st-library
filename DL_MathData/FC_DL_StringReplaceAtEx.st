(*
    FC_DL_StringReplaceAtEx —— 定位定长替换防御包装（与 StringReplaceAll 全局替换职责区分）
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
    功能说明  : 与既有 FC_DL_StringReplaceAll（全串搜索全局替换）职责明
                确区分：本件为定位置定长覆盖——自 nPos 位序（1 基）起用
                sRep 覆盖，不搜索、不改变总长，sRep 超出串尾部分被截断。
                nPos < 1 钳 1 置 16#0001_01BD；nPos > len 原样返回置 16#0001_01BD；覆盖长
                度 = MIN(sRep 长, len-nPos+1)，sRep 被截断时按 R37 范式显
                式置 bTruncated=TRUE 与 16#0001_028B。先整串复制再覆盖（各轮带
                255 越界 EXIT 守卫），复制后显式写空字符终止符。返回值
                TRUE 表示已执行完成。
    错误码    : 0000 正常 / 16#0001_01BD 入参越界（nPos 钳位或超串长，超长时原样返回） / 16#0001_028B 上溢下溢（sRep 超串尾被截断，bTruncated=TRUE）
    修订记录  : 2026-11-16 v1.0.0 首次入库（R15）
*)
FUNCTION FC_DL_StringReplaceAtEx : BOOL
VAR_INPUT
    sIn  : STRING(255); // 源串 [字符] / source string [chars]
    sRep : STRING(255); // 覆盖串 [字符]，超串尾部分被截断 / replacement string [chars], tail beyond the source end truncated
    nPos : INT; // 覆盖起始位序 [字符位序]，1 基 / overwrite start position [char position], 1-based
END_VAR
VAR_OUTPUT
    sResult    : STRING(255); // 结果串 [字符]，总长与源串一致 / result string [chars], same length as the source
    eErr : UDINT; // 错误码，0=正常，1=位置钳位/超长，2=覆盖串截断 / error id, 0=ok, 1=position clamped or beyond length, 2=replacement truncated
    bError     : BOOL; // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid     : BOOL; // 输出是否有效可用 / output valid
    bTruncated : BOOL; // 截断标志，sRep 超串尾被截断时 TRUE（R37 范式） / truncation flag, TRUE when the replacement was tail-truncated
END_VAR
VAR
    nI      : INT; // 循环索引 [字符位序]，1 基 / loop index [char position], 1-based
    nLen    : INT; // 锁存的源串有效长度 [字符] / latched effective source length [chars]
    nRepLen : INT; // 锁存的覆盖串有效长度 [字符] / latched effective replacement length [chars]
    nPosC   : INT; // 钳位后的覆盖起始位序 [字符位序] / clamped overwrite start position [char position]
    nAvail  : INT; // 自起点起可用字符数 [字符] / chars available from the start position [chars]
    nUseRep : INT; // 覆盖串实际复制数 [字符] / chars actually copied from the replacement [chars]
END_VAR
VAR CONSTANT
    DL_RA_MAX : INT := 255; // 串型上限 [字符] / string type cap [chars]
END_VAR

// 段 1｜返回值与输出预置，任何早退路径不留脏码 / segment 1, preset return value and outputs
FC_DL_StringReplaceAtEx := TRUE; // 返回值预置 TRUE（已执行口径） / preset return to TRUE
sResult                 := ''; // 结果串预置空串 / preset result to the empty string
eErr                := 16#0000_0000; // 错误码预置正常 / preset error id to ok
bError                  := FALSE; // 错误标志预置无错 / preset error flag to FALSE
bValid                  := TRUE; // 有效标志预置可用 / preset valid flag to TRUE
bTruncated              := FALSE; // 截断标志预置无截断 / preset truncation flag to FALSE

// 段 2｜两串有效长度各一次锁存（空字符截止扫描 + 255 越界守卫） / segment 2, latch both effective lengths once
nI      := 1; // 索引起始 [字符位序] / index start
nLen    := 0; // 源串长度预置 [字符] / preset source length
WHILE nI <= DL_RA_MAX DO
    IF nI > DL_RA_MAX THEN    (* 越界守卫（双重保险） EN: overrun guard *)
        EXIT;
    END_IF
    IF sIn[nI] = '$00' THEN   (* 首个空字符即串结束 EN: first null char ends the string *)
        EXIT;
    END_IF
    nLen := nI; // 记录源串最后非空位序 [字符] / record the last non-null position
    nI   := nI + 1; // 每轮自增 / per-iteration increment
END_WHILE
nI      := 1; // 索引复位 / reset index
nRepLen := 0; // 覆盖串长度预置 [字符] / preset replacement length
WHILE nI <= DL_RA_MAX DO
    IF nI > DL_RA_MAX THEN    (* 越界守卫（双重保险） EN: overrun guard *)
        EXIT;
    END_IF
    IF sRep[nI] = '$00' THEN  (* 首个空字符即串结束 EN: first null char ends the string *)
        EXIT;
    END_IF
    nRepLen := nI; // 记录覆盖串最后非空位序 [字符] / record the last non-null position
    nI      := nI + 1; // 每轮自增 / per-iteration increment
END_WHILE

// 段 3｜位置闸门：nPos < 1 钳 1 置 16#0001_01BD；nPos > len 原样返回置 16#0001_01BD / segment 3, position gate, below 1 clamped to 1, beyond length returns the original with code 1
IF nPos < 1 THEN
    nPosC := 1; // 下越界钳 1 / clamped to 1
    eErr := 16#0001_01BD; // 入参越界码 / out-of-domain code
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 钳位降级 / degraded output
ELSE
    nPosC := nPos; // 域内直通 / in-domain pass-through
END_IF
IF nPosC > nLen THEN
    FOR nI := 1 TO nLen DO
        IF nI > DL_RA_MAX THEN   (* 越界守卫（双重保险） EN: overrun guard *)
            EXIT;
        END_IF
        sResult[nI] := sIn[nI]; // 位置超长原样返回 / position beyond length, original returned
    END_FOR
    IF nLen < DL_RA_MAX THEN
        sResult[nLen + 1] := '$00'; // 空字符终止符 / null terminator
    END_IF
    eErr := 16#0001_01BD; // 入参越界码（首事件优先不覆盖钳位码） / out-of-domain code, first event kept
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
    RETURN;
END_IF

// 段 4｜覆盖配额闸（R37 范式：先判定后写入，严禁静默回夹） / segment 4, overwrite quota gate, R37 paradigm, decide before writing
nAvail := nLen - nPosC + 1; // 自起点起可用字符数 [字符] / chars available from the start
IF nRepLen > nAvail THEN
    nUseRep := nAvail; // 覆盖串截到串尾 / replacement clipped to the string end
    bTruncated := TRUE; // 显式置截断标志（R37 教训） / set the truncation flag explicitly
    eErr   := 16#0001_028B; // 上溢码：sRep 超串尾已截断 / overflow code, replacement tail-truncated
    bError     := TRUE; // 置错误标志 / raise error flag
    bValid     := FALSE; // 截断降级结果 / degraded truncated output
ELSE
    nUseRep := nRepLen; // 域内直通 / in-domain pass-through
END_IF

// 段 5｜整串复制：FOR 循环 + 255 越界 EXIT 守卫 / segment 5, copy the whole source with the overrun guard
FOR nI := 1 TO nLen DO
    IF nI > DL_RA_MAX THEN       (* 越界守卫（双重保险） EN: overrun guard *)
        EXIT;
    END_IF
    sResult[nI] := sIn[nI]; // 逐字符复制 / char-by-char copy
END_FOR

// 段 6｜定长覆盖：目的位序 = nPos 起顺延，超 255 即退出 / segment 6, fixed-position overwrite
FOR nI := 1 TO nUseRep DO
    IF (nPosC + nI - 1) > DL_RA_MAX THEN   (* 目的侧越界守卫 EN: destination overrun guard *)
        EXIT;
    END_IF
    IF nI > DL_RA_MAX THEN                 (* 源侧越界守卫 EN: source overrun guard *)
        EXIT;
    END_IF
    sResult[nPosC + nI - 1] := sRep[nI]; // 逐字符覆盖 / char-by-char overwrite
END_FOR

// 段 7｜显式写终止符：总长与源串一致 / segment 7, write the terminator explicitly, total length equals the source
IF nLen < DL_RA_MAX THEN
    sResult[nLen + 1] := '$00'; // 空字符终止符 / null terminator
END_IF
END_FUNCTION
