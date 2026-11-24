(*
    FC_DL_StringLenEx —— 字符串有效长度防御包装（空字符截止 + 尾空格可选回退）
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
    功能说明  : 返回输入字符串的有效长度。自位序 1 扫描至 255，遇第一个
                空字符即截止（长度取最后非空字符位序）；随后按入参
                bTrimTrailingSpace 决定是否回退尾部空格（TRUE 回退、FALSE
                计入）。WHILE 循环每轮带 255 越界 EXIT 守卫，空格回退循环
                用嵌套 IF 结构避免对短路求值的依赖。长度 0 为正常结果
                （eErr=0000、bValid=TRUE），不置任何错误码。
    错误码    : 0000 正常（含空串长度 0 的正常输出）
    修订记录  : 2026-11-16 v1.0.0 首次入库（R15）
*)
FUNCTION FC_DL_StringLenEx : INT
VAR_INPUT
    sIn                : STRING(255); // 输入字符串 [字符] / input string [chars]
    bTrimTrailingSpace : BOOL; // TRUE=尾部空格不计入长度，FALSE=尾部空格计入 / TRUE=trailing spaces not counted, FALSE=trailing spaces counted
END_VAR
VAR_OUTPUT
    eErr : UDINT; // 错误码，本件仅 0=正常 / error id, this unit only 0=ok
    bError   : BOOL; // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid   : BOOL; // 输出是否有效可用 / output valid
END_VAR
VAR
    nI   : INT; // 循环索引 [字符位序]，1 基 / loop index [char position], 1-based
    nLen : INT; // 有效长度 [字符]，最后非空字符位序 / effective length [chars], position of the last non-null char
END_VAR
VAR CONSTANT
    DL_SL_MAX : INT := 255; // 串型上限 [字符]，定长 STRING 的隐式容量 / string type cap [chars], implicit capacity of a fixed-length STRING
END_VAR

// 段 1｜返回值与错误状态预置，任何早退路径不留脏码 / segment 1, preset return value and error states
FC_DL_StringLenEx := 0; // 返回值预置 0 [字符] / preset return to 0
eErr          := 16#0000_0000; // 错误码预置正常 / preset error id to ok
bError            := FALSE; // 错误标志预置无错 / preset error flag to FALSE
bValid            := TRUE; // 有效标志预置可用 / preset valid flag to TRUE

// 段 2｜空字符截止扫描：WHILE 循环 + 每轮自增 + 255 越界 EXIT 守卫 / segment 2, null-terminated scan, while loop with per-iteration increment and the 255 overrun EXIT guard
nI   := 1; // 索引自位序 1 起始 [字符位序] / index starts at position 1
nLen := 0; // 有效长度预置 0（空串口径）[字符] / preset effective length to 0 for the empty-string case
WHILE nI <= DL_SL_MAX DO
    IF nI > DL_SL_MAX THEN   (* 越界守卫（双重保险，严禁越界索引） EN: overrun guard, defense in depth, no out-of-bound indexing *)
        EXIT;
    END_IF
    IF sIn[nI] = '$00' THEN  (* 首个空字符即串结束 EN: first null character marks the string end *)
        EXIT;
    END_IF
    nLen := nI; // 记录最后非空字符位序 [字符] / record the last non-null char position
    nI   := nI + 1; // 每轮自增 [字符位序] / per-iteration increment
END_WHILE

// 段 3｜尾部空格回退（可选）：嵌套 IF 结构，不依赖短路求值，nLen=0 时安全终止 / segment 3, optional trailing space trim, nested-if structure without short-circuit reliance, safe at zero length
IF bTrimTrailingSpace THEN
    WHILE nLen > 0 DO
        IF sIn[nLen] = ' ' THEN
            nLen := nLen - 1; // 尾部空格回退一格 [字符] / trim one trailing space
        ELSE
            EXIT; // 非空格字符，回退结束 / non-space char reached, trimming done
        END_IF
    END_WHILE
END_IF

// 段 4｜输出有效长度 / segment 4, output the effective length
FC_DL_StringLenEx := nLen; // 输出有效长度 [字符] / output the effective length
END_FUNCTION
