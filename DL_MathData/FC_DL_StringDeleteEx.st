(*
    FC_DL_StringDeleteEx —— 删除指定区间防御包装（区间越界钳位，删除只缩不长）
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
    功能说明  : 删除 sIn 自 nPos 位序（1 基）起的 nCount 个字符。删除只
                会缩短串长，结果恒不超 255，无截断标志需求。处理次序：
                ① 锁存源串长；② nCount <= 0 原样返回置 16#0001_01B5；③ nPos < 1
                钳 1 置 16#0001_01B3；④ nPos > len 原样返回置 16#0001_01B3；⑤ 区间尾
                nPos+nCount-1 > len 截到串尾置 16#0001_01B3（bValid=FALSE）；
                ⑥ 前段 + 后段逐字符复制（每轮 255 越界 EXIT 守卫），复制
                后显式写空字符终止符。返回值 TRUE 表示已执行完成。
    错误码    : 0000 正常 / 16#0001_01B3 入参越界（nPos 钳位/超长，区间尾截到串尾） / 16#0001_01B5 无效入参（nCount <= 0，原样返回）
    修订记录  : 2026-11-16 v1.0.0 首次入库（R15）
*)
FUNCTION FC_DL_StringDeleteEx : BOOL
VAR_INPUT
    sIn    : STRING(255); // 源串 [字符] / source string [chars]
    nPos   : INT; // 删除起始位序 [字符位序]，1 基 / delete start position [char position], 1-based
    nCount : INT; // 删除字符数 [字符]，<= 0 判无效 / char count to delete [chars], values at or below 0 invalid
END_VAR
VAR_OUTPUT
    sResult  : STRING(255); // 结果串 [字符] / result string [chars]
    eErr : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError   : BOOL; // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid   : BOOL; // 输出是否有效可用 / output valid
END_VAR
VAR
    nI     : INT; // 循环索引 [字符位序]，1 基 / loop index [char position], 1-based
    nLen   : INT; // 锁存的源串有效长度 [字符] / latched effective source length [chars]
    nPosC  : INT; // 钳位后的删除起始位序 [字符位序] / clamped delete start position [char position]
    nEnd   : INT; // 删除区间尾位序 [字符位序]，已截到串尾 / delete end position, clipped to the string end [char position]
    nF     : INT; // 前段字符数 [字符] / front part char count [chars]
    nT     : INT; // 后段字符数 [字符] / rear part char count [chars]
END_VAR
VAR CONSTANT
    DL_DE_MAX : INT := 255; // 串型上限 [字符] / string type cap [chars]
END_VAR

// 段 1｜返回值与输出预置，任何早退路径不留脏码 / segment 1, preset return value and outputs
FC_DL_StringDeleteEx := TRUE; // 返回值预置 TRUE（已执行口径） / preset return to TRUE
sResult              := ''; // 结果串预置空串 / preset result to the empty string
eErr             := 16#0000_0000; // 错误码预置正常 / preset error id to ok
bError               := FALSE; // 错误标志预置无错 / preset error flag to FALSE
bValid               := TRUE; // 有效标志预置可用 / preset valid flag to TRUE

// 段 2｜源串有效长度一次锁存（空字符截止扫描 + 255 越界守卫） / segment 2, latch the effective source length once
nI   := 1; // 索引起始 [字符位序] / index start
nLen := 0; // 有效长度预置 [字符] / preset effective length
WHILE nI <= DL_DE_MAX DO
    IF nI > DL_DE_MAX THEN   (* 越界守卫（双重保险） EN: overrun guard *)
        EXIT;
    END_IF
    IF sIn[nI] = '$00' THEN  (* 首个空字符即串结束 EN: first null char ends the string *)
        EXIT;
    END_IF
    nLen := nI; // 记录最后非空位序 [字符] / record the last non-null position
    nI   := nI + 1; // 每轮自增 / per-iteration increment
END_WHILE

// 段 3｜无效入参闸：nCount <= 0 原样返回置 16#0001_01B5 / segment 3, invalid input gate, count at or below 0 returns the original with code 4
IF nCount <= 0 THEN
    FOR nI := 1 TO nLen DO
        IF nI > DL_DE_MAX THEN   (* 越界守卫（双重保险） EN: overrun guard *)
            EXIT;
        END_IF
        sResult[nI] := sIn[nI]; // 原样逐字符复制 / copy the original char by char
    END_FOR
    IF nLen < DL_DE_MAX THEN
        sResult[nLen + 1] := '$00'; // 空字符终止符 / null terminator
    END_IF
    eErr := 16#0001_01B5; // 无效入参码 / invalid input code
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
    RETURN;
END_IF

// 段 4｜位置钳位与越界组合闸：nPos < 1 钳 1；nPos > len 原样返回 / segment 4, position clamp and out-of-range combination gate
IF nPos < 1 THEN
    nPosC := 1; // 下越界钳 1 / clamped to 1
    eErr := 16#0001_01B3; // 入参越界码 / out-of-domain code
    bError := TRUE; // 置错误标志 / raise error flag
    bValid := FALSE; // 钳位降级 / degraded output
ELSE
    nPosC := nPos; // 域内直通 / in-domain pass-through
END_IF
IF nPosC > nLen THEN
    FOR nI := 1 TO nLen DO
        IF nI > DL_DE_MAX THEN   (* 越界守卫（双重保险） EN: overrun guard *)
            EXIT;
        END_IF
        sResult[nI] := sIn[nI]; // 起点超长原样返回 / start beyond length, original returned
    END_FOR
    IF nLen < DL_DE_MAX THEN
        sResult[nLen + 1] := '$00'; // 空字符终止符 / null terminator
    END_IF
    eErr := 16#0001_01B3; // 入参越界码（首事件优先不覆盖 16#0001_01B5） / out-of-domain code, first event kept
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
    RETURN;
END_IF

// 段 5｜区间尾截断闸：nPos+nCount-1 超 len 截到串尾置 16#0001_01B3 / segment 5, interval end clipping gate, end beyond the length clipped with code 1
nEnd := nPosC + nCount - 1; // 原始区间尾 [字符位序] / raw interval end
IF nEnd > nLen THEN
    nEnd := nLen; // 截到串尾 / clipped to the string end
    eErr := 16#0001_01B3; // 入参越界码 / out-of-domain code
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 区间被截短，输出降级 / interval clipped, degraded output
END_IF
nF := nPosC - 1; // 前段字符数 [字符] / front part char count
nT := nLen - nEnd; // 后段字符数 [字符] / rear part char count

// 段 6｜复制前段：FOR 循环 + 255 越界 EXIT 守卫 / segment 6, copy the front part with the overrun guard
FOR nI := 1 TO nF DO
    IF nI > DL_DE_MAX THEN       (* 越界守卫（双重保险） EN: overrun guard *)
        EXIT;
    END_IF
    sResult[nI] := sIn[nI]; // 逐字符复制 / char-by-char copy
END_FOR

// 段 7｜复制后段：源自 nEnd+1 起，目的位序顺延 / segment 7, copy the rear part
FOR nI := 1 TO nT DO
    IF (nF + nI) > DL_DE_MAX THEN    (* 目的侧越界守卫 EN: destination overrun guard *)
        EXIT;
    END_IF
    IF (nEnd + nI) > DL_DE_MAX THEN  (* 源侧越界守卫 EN: source overrun guard *)
        EXIT;
    END_IF
    sResult[nF + nI] := sIn[nEnd + nI]; // 逐字符复制 / char-by-char copy
END_FOR

// 段 8｜显式写终止符 / segment 8, write the terminator explicitly
IF (nF + nT) < DL_DE_MAX THEN
    sResult[nF + nT + 1] := '$00'; // 空字符终止符 / null terminator
END_IF
END_FUNCTION
