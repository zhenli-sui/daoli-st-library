(*
    FC_DL_StringLeftEx —— 取左 n 字符防御包装（n 越界钳位 + 255 守卫逐字符复制）
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
    功能说明  : 取源串左侧 nCount 个字符到 sResult。采用逐字符 FOR 复制
                （跨平台口径，不依赖平台 LEFT 行为差异），每轮带 255 越
                界 EXIT 守卫，复制后显式写空字符终止符。nCount <= 0 返回
                空串置 16#0001_01A1；nCount > 实际长度返回全串并置 16#0001_019F（bValid=
                FALSE，截断诉求由错误码显式体现）。返回值 TRUE 表示函数
                已执行完成，结果总在 sResult 中，错误详情经 eErr 传递。
    错误码    : 0000 正常 / 16#0001_019F 入参越界（nCount 超实际长度，已返回全串） / 16#0001_01A1 无效入参（nCount <= 0）
    修订记录  : 2026-11-16 v1.0.0 首次入库（R15）
*)
FUNCTION FC_DL_StringLeftEx : BOOL
VAR_INPUT
    sIn    : STRING(255); // 源串 [字符] / source string [chars]
    nCount : INT; // 请求取左字符数 [字符]，<= 0 判无效 / requested left char count [chars], values at or below 0 invalid
END_VAR
VAR_OUTPUT
    sResult  : STRING(255); // 结果串 [字符]，左 nCount 字符 / result string [chars], left nCount chars
    eErr : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError   : BOOL; // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid   : BOOL; // 输出是否有效可用 / output valid
END_VAR
VAR
    nI   : INT; // 循环索引 [字符位序]，1 基 / loop index [char position], 1-based
    nLen : INT; // 锁存的源串有效长度 [字符] / latched effective source length [chars]
    nUse : INT; // 实际复制字符数 [字符] / chars actually copied [chars]
END_VAR
VAR CONSTANT
    DL_LF_MAX : INT := 255; // 串型上限 [字符] / string type cap [chars]
END_VAR

// 段 1｜返回值与输出预置，任何早退路径不留脏码 / segment 1, preset return value and outputs so no early exit leaves stale states
FC_DL_StringLeftEx := TRUE; // 返回值预置 TRUE（已执行口径） / preset return to TRUE, executed semantics
sResult            := ''; // 结果串预置空串 / preset result to the empty string
eErr           := 16#0000_0000; // 错误码预置正常 / preset error id to ok
bError             := FALSE; // 错误标志预置无错 / preset error flag to FALSE
bValid             := TRUE; // 有效标志预置可用 / preset valid flag to TRUE

// 段 2｜源串有效长度一次锁存（空字符截止扫描 + 255 越界守卫） / segment 2, latch the effective source length once with the null-terminated scan and overrun guard
nI   := 1; // 索引起始 [字符位序] / index start
nLen := 0; // 有效长度预置 [字符] / preset effective length
WHILE nI <= DL_LF_MAX DO
    IF nI > DL_LF_MAX THEN   (* 越界守卫（双重保险） EN: overrun guard, defense in depth *)
        EXIT;
    END_IF
    IF sIn[nI] = '$00' THEN  (* 首个空字符即串结束 EN: first null character marks the string end *)
        EXIT;
    END_IF
    nLen := nI; // 记录最后非空字符位序 [字符] / record the last non-null char position
    nI   := nI + 1; // 每轮自增 / per-iteration increment
END_WHILE

// 段 3｜入参域闸门：nCount <= 0 无效置 16#0001_01A1；nCount 超长度钳到全长置 16#0001_019F / segment 3, input domain gate, count at or below 0 invalid with code 4, count beyond length clamped to full length with code 1
IF nCount <= 0 THEN
    sResult  := ''; // 无效入参返回空串 / invalid input returns the empty string
    eErr := 16#0001_01A1; // 无效入参码 / invalid input code
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
    RETURN;
ELSIF nCount > nLen THEN
    nUse    := nLen; // 请求超长，钳到全串长 / request beyond length, clamped to full length
    eErr := 16#0001_019F; // 入参越界码：截断诉求显式置码 / out-of-domain code, truncation intent made explicit
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出为截断降级结果 / output is a degraded truncated result
ELSE
    nUse := nCount; // 域内直通 / in-domain pass-through
END_IF

// 段 4｜逐字符复制（跨平台口径）：FOR 循环 + 255 越界 EXIT 守卫 / segment 4, char-by-char copy for cross-platform portability, for loop with the 255 overrun EXIT guard
FOR nI := 1 TO nUse DO
    IF nI > DL_LF_MAX THEN       (* 越界守卫（双重保险） EN: overrun guard, defense in depth *)
        EXIT;
    END_IF
    sResult[nI] := sIn[nI]; // 逐字符复制 / char-by-char copy
END_FOR

// 段 5｜显式写终止符：nUse 未满 255 时在下一位置写空字符 / segment 5, write the terminator explicitly, at the next position when nUse is below the cap
IF nUse < DL_LF_MAX THEN
    sResult[nUse + 1] := '$00'; // 空字符终止符 / null terminator
END_IF
END_FUNCTION
