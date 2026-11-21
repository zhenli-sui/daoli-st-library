(*
    FC_DL_StringFindEx —— 子串查找防御包装（1 基返回位置，未找到不是错误）
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
    功能说明  : 在 sHay 中自 nStart 位序（1 基）起查找 sNeedle 首次出现
                位置，返回 1 基位序；未找到返回 0 且 eErr=0000、
                bValid=TRUE（未找到不是错误）。sNeedle 为空串返回 0 置
                16#0001_01BA；nStart < 1 钳 1 置 16#0001_01B8；nStart > 主串长返回 0 置
                16#0001_01B8。双层循环：外层起点受 主串长-子串长+1 上限约束，
                内层匹配带 255 越界 EXIT 守卫，失配即断内层回退外层下一
                起点，无死循环风险。返回值即位置。
    错误码    : 0000 正常（含未找到返回 0） / 16#0001_01B8 入参越界（nStart 钳位或超主串长） / 16#0001_01BA 无效入参（sNeedle 为空串）
    修订记录  : 2026-11-16 v1.0.0 首次入库（R15）
*)
FUNCTION FC_DL_StringFindEx : INT
VAR_INPUT
    sHay    : STRING(255); // 主串 [字符] / haystack string [chars]
    sNeedle : STRING(255); // 子串 [字符] / needle string [chars]
    nStart  : INT; // 查找起始位序 [字符位序]，1 基 / search start position [char position], 1-based
END_VAR
VAR_OUTPUT
    eErr : UDINT; // 错误码，0=正常（含未找到） / error id, 0=ok including the not-found case
    bError   : BOOL; // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid   : BOOL; // 输出是否有效可用，未找到时保持 TRUE / output valid, stays TRUE for the not-found case
END_VAR
VAR
    nI       : INT; // 外层循环索引 [字符位序]，主串起点 / outer loop index [char position], haystack start
    nJ       : INT; // 内层循环索引 [字符位序]，子串偏移 / inner loop index [char position], needle offset
    nHayLen  : INT; // 锁存的主串有效长度 [字符] / latched effective haystack length [chars]
    nNeedLen : INT; // 锁存的子串有效长度 [字符] / latched effective needle length [chars]
    nStartC  : INT; // 钳位后的查找起点 [字符位序] / clamped search start [char position]
    nLimit   : INT; // 外层起点上限 [字符位序] / outer start upper bound [char position]
    bMatch   : BOOL; // 内层匹配成功标志 / inner-loop match success flag
END_VAR
VAR CONSTANT
    DL_FD_MAX : INT := 255; // 串型上限 [字符] / string type cap [chars]
END_VAR

// 段 1｜返回值与错误状态预置，任何早退路径不留脏码 / segment 1, preset return value and error states
FC_DL_StringFindEx := 0; // 返回值预置 0（未找到口径）[字符位序] / preset return to 0, not-found semantics
eErr           := 16#0000_0000; // 错误码预置正常 / preset error id to ok
bError             := FALSE; // 错误标志预置无错 / preset error flag to FALSE
bValid             := TRUE; // 有效标志预置可用（未找到也是有效结果） / preset valid to TRUE, not-found is a valid result

// 段 2｜两串有效长度各一次锁存（空字符截止扫描 + 255 越界守卫） / segment 2, latch both effective lengths once
nI       := 1; // 索引起始 [字符位序] / index start
nHayLen  := 0; // 主串长度预置 [字符] / preset haystack length
WHILE nI <= DL_FD_MAX DO
    IF nI > DL_FD_MAX THEN    (* 越界守卫（双重保险） EN: overrun guard *)
        EXIT;
    END_IF
    IF sHay[nI] = '$00' THEN  (* 首个空字符即串结束 EN: first null char ends the string *)
        EXIT;
    END_IF
    nHayLen := nI; // 记录主串最后非空位序 [字符] / record the last non-null position
    nI      := nI + 1; // 每轮自增 / per-iteration increment
END_WHILE
nI       := 1; // 索引复位 / reset index
nNeedLen := 0; // 子串长度预置 [字符] / preset needle length
WHILE nI <= DL_FD_MAX DO
    IF nI > DL_FD_MAX THEN    (* 越界守卫（双重保险） EN: overrun guard *)
        EXIT;
    END_IF
    IF sNeedle[nI] = '$00' THEN (* 首个空字符即串结束 EN: first null char ends the string *)
        EXIT;
    END_IF
    nNeedLen := nI; // 记录子串最后非空位序 [字符] / record the last non-null position
    nI       := nI + 1; // 每轮自增 / per-iteration increment
END_WHILE

// 段 3｜无效入参闸：子串空串返回 0 置 16#0001_01BA / segment 3, invalid input gate, empty needle returns 0 with code 4
IF nNeedLen <= 0 THEN
    eErr := 16#0001_01BA; // 无效入参码 / invalid input code
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
    RETURN;
END_IF

// 段 4｜起点钳位闸：nStart < 1 钳 1 置 16#0001_01B8；nStart > 主串长返回 0 置 16#0001_01B8 / segment 4, start clamp gate
IF nStart < 1 THEN
    nStartC := 1; // 下越界钳 1 / clamped to 1
    eErr := 16#0001_01B8; // 入参越界码 / out-of-domain code
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 钳位降级 / degraded output
ELSE
    nStartC := nStart; // 域内直通 / in-domain pass-through
END_IF
IF nStartC > nHayLen THEN
    FC_DL_StringFindEx := 0; // 起点超主串长返回 0 / start beyond haystack length returns 0
    eErr := 16#0001_01B8; // 入参越界码 / out-of-domain code
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
    RETURN;
END_IF

// 段 5｜双层查找：外层起点上限 = 主串长减子串长加一，内层失配即断回退外层 / segment 5, two-layer search, outer bounded by haystack minus needle plus one, inner breaks on mismatch
nLimit := nHayLen - nNeedLen + 1; // 外层起点上限 [字符位序] / outer start upper bound
FOR nI := nStartC TO nLimit DO
    bMatch := TRUE; // 匹配标志预置成功 / preset the match flag to success
    nJ := 1; // 内层索引起始 [字符位序] / inner index start
    WHILE nJ <= nNeedLen DO
        IF (nI + nJ - 1) > DL_FD_MAX THEN    (* 主串侧越界守卫（双重保险） EN: haystack overrun guard *)
            bMatch := FALSE; // 越界即失配 / overrun means mismatch
            EXIT; // 断内层回退外层 / break the inner loop
        END_IF
        IF sHay[nI + nJ - 1] <> sNeedle[nJ] THEN   (* 逐字符比对 EN: char-by-char compare *)
            bMatch := FALSE; // 失配 / mismatch
            EXIT; // 断内层回退外层下一起点，无死循环 / break the inner loop, outer advances, no hang
        END_IF
        nJ := nJ + 1; // 内层自增 / inner increment
    END_WHILE
    IF bMatch THEN
        FC_DL_StringFindEx := nI; // 命中返回 1 基位置 / hit, return the 1-based position
        RETURN;
    END_IF
END_FOR

// 段 6｜未找到收口：返回预置 0，错误码保持 0000，bValid 保持 TRUE / segment 6, not-found closure, return the preset 0 with no error
END_FUNCTION
