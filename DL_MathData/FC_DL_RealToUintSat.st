(*
    FC_DL_RealToUintSat —— REAL 到 UINT 饱和防御转换
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建函数，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R16）
    ------------------------------------------------------------------
    功能说明  : 将 REAL 输入防御性转换为 UINT 并作为返回值输出；
                非有限输入（NaN 或 ±INF）判为故障级 16#0001_0297，返回 0 且 bValid=FALSE；
                fIn < 0 时钳位至 0，置信息级 16#0001_01C6（UINT 无符号，负值不可表）；
                fIn 超出 UINT 上界 65535 时钳位至上界，置信息级 16#0001_01C7；
                钳位方向：下界 0 / 上界 65535（双侧饱和）；
                ±INF 采用平台安全幅值比较判定（阈值高于 REAL 最大有限值 3.402823E38），NaN 用 fIn <> fIn 自不等判定；
                域内转换委托平台内建 REAL_TO_UINT 语义，不重实现数学内核；
                信息级码属正常防御：bError=FALSE、bValid=TRUE，输出钳位后防御值。
    错误码    : 16#0001_0297 非有限输入（NaN 或 ±INF）——故障级，返回 0
                16#0001_01C6 负值输入，已钳位至 0——信息级，正常防御
                16#0001_01C7 输入超 UINT 上界，已钳位至 65535——信息级，正常防御
                16#0001_0298 预留禁用（故障级，不得挪用）
                16#0001_0299 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R16）
*)
FUNCTION FC_DL_RealToUintSat : UINT
VAR_INPUT
    fIn : REAL; // 待转换输入 [无量纲] / input value to convert
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_UINT16_MAX     : LREAL := 65535.0; // UINT 域上界 65535，LREAL 承载 [无量纲] / UINT upper bound 65535 carried in LREAL
    DL_REAL_INF_GUARD : LREAL := 4.0E38;  // REAL 域 ±INF 判定阈值，高于 REAL 最大有限值 3.402823E38 [无量纲] / REAL +/-INF guard above max finite REAL 3.402823E38
END_VAR
VAR
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_RealToUintSat := 0; // 故障缺省返回 0 [无量纲] / fault default returns 0
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置无效，通过防御闸后置位 / preset invalid, set TRUE after guard passes

// 段 2｜非有限防御闸 / segment 2, non-finite guard
bNonFinite := (fIn <> fIn) OR (fIn > DL_REAL_INF_GUARD) OR (fIn < -DL_REAL_INF_GUARD); // NaN 自不等判定，±INF 用安全幅值比较 [无量纲] / NaN by self-inequality, +/-INF by safe magnitude compare
IF bNonFinite THEN
    FC_DL_RealToUintSat := 0; // 故障级返回 0 [无量纲] / fault level returns 0
    eErr   := 16#0001_0297;   // 非有限输入故障码 / non-finite input fault id
    bError := TRUE;           // 置故障标志 / set fault flag
    bValid := FALSE;          // 输出无效 / output invalid
    RETURN;                   // 立即返回 / immediate return
END_IF

// 段 3｜双侧饱和钳位与主体转换（末段） / segment 3, double-side saturating clamp and main conversion (final)
IF fIn < 0.0 THEN
    FC_DL_RealToUintSat := 0;  // 负值钳位至 0（UINT 无符号语义） / negative input clamped to 0 (UINT is unsigned)
    eErr := 16#0001_01C6;      // 信息级：负值已钳零 / info level: negative input clamped to zero
ELSIF fIn > DL_UINT16_MAX THEN
    FC_DL_RealToUintSat := 16#FFFF; // 正向钳位至 UINT 上界 65535 / clamp to UINT upper bound 65535
    eErr := 16#0001_01C7;           // 信息级：超上界已钳位 / info level: above upper bound, clamped
ELSE
    FC_DL_RealToUintSat := REAL_TO_UINT(fIn); // 域内委托平台内建 _TO_ 转换语义 / in-domain delegate to built-in _TO_ conversion
    eErr := 0; // 域内无错误 / in-domain, no error
END_IF
bError := FALSE; // 信息级钳位不置故障，故障分支已提前返回 / info-level clamp never raises fault, fault branch has returned
bValid := TRUE;  // 域内或钳位输出均有效可用 / in-domain or clamped output is valid
END_FUNCTION
