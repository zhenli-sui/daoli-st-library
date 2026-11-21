(*
    FC_DL_MaxEx —— 双值取大泛型防御包装（REAL 域）
    ------------------------------------------------------------------
    分类      : DL_MathData / MinMax
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建函数，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R16）
    ------------------------------------------------------------------
    功能说明  : 双值取大：fA > fB 时返回 fA，否则返回 fB，比较运算委托
                `>` 运算符（IEC MAX 语义），不重实现任何数学内核；
                任一输入非有限（NaN 或 ±INF）判为故障级 16#0001_02B8，
                返回 0.0 且 bValid=FALSE（非有限值参与比较语义未定义，一律拦截）；
                钳位方向：无钳位（域内值直接比较输出，异常值故障拦截）；
                ±INF 采用平台安全幅值比较判定（阈值高于 REAL 最大有限值 3.402823E38），NaN 用自不等判定；
                信息级码位全部预留禁用（本组件无信息级路径）。
    错误码    : 16#0001_02B8 任一输入非有限（NaN 或 ±INF）——故障级，返回 0.0
                16#0001_01DC 预留禁用（信息级，不得挪用）
                16#0001_01DD 预留禁用（信息级，不得挪用）
                16#0001_02B9 预留禁用（故障级，不得挪用）
                16#0001_02BA 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R16）
*)
FUNCTION FC_DL_MaxEx : REAL
VAR_INPUT
    fA : REAL; // 比较值 A [无量纲] / compare value A
    fB : REAL; // 比较值 B [无量纲] / compare value B
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_REAL_INF_GUARD : LREAL := 4.0E38; // REAL 域 ±INF 判定阈值，高于 REAL 最大有限值 3.402823E38 [无量纲] / REAL +/-INF guard above max finite REAL 3.402823E38
END_VAR
VAR
    bBad : BOOL; // 任一输入非有限判定结果 / non-finite detection result of either input
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_MaxEx := 0.0; // 故障缺省返回 0 [无量纲] / fault default returns 0
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置无效，通过防御闸后置位 / preset invalid, set TRUE after guard passes

// 段 2｜非有限防御闸 / segment 2, non-finite guard
bBad := (fA <> fA) OR (fA > DL_REAL_INF_GUARD) OR (fA < -DL_REAL_INF_GUARD)
     OR (fB <> fB) OR (fB > DL_REAL_INF_GUARD) OR (fB < -DL_REAL_INF_GUARD); // 双输入非有限判定（NaN 自不等 + 安全幅值判 ±INF） [无量纲] / both inputs non-finite check (NaN by self-inequality, +/-INF by safe magnitude)
IF bBad THEN
    FC_DL_MaxEx := 0.0;       // 故障级返回 0 [无量纲] / fault level returns 0
    eErr   := 16#0001_02B8;   // 非有限输入故障码 / non-finite input fault id
    bError := TRUE;           // 置故障标志 / set fault flag
    bValid := FALSE;          // 输出无效 / output invalid
    RETURN;                   // 立即返回 / immediate return
END_IF

// 段 3｜域内取大主体计算（末段） / segment 3, in-domain maximum main calculation (final)
IF fA > fB THEN
    FC_DL_MaxEx := fA; // A 较大，输出 A / A is larger, output A
ELSE
    FC_DL_MaxEx := fB; // B 较大或相等，输出 B（相等时二者同值） / B is larger or equal, output B (identical when equal)
END_IF
bValid := TRUE; // 域内输出有效可用 / in-domain output is valid
END_FUNCTION
