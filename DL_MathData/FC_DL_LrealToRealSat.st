(*
    FC_DL_LrealToRealSat —— LREAL 到 REAL 定长饱和防御转换
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
    功能说明  : 将 LREAL 输入防御性转换为 REAL 并作为返回值输出；
                非有限输入（NaN 或 ±INF）判为故障级 16#0001_028E，返回 0.0 且 bValid=FALSE；
                幅值 |fIn| 超出 REAL 上限 3.402823E38 时按符号双侧饱和钳位，置信息级 16#0001_01C0；
                钳位方向：正向钳至上界 +3.402823E38，负向钳至下界 -3.402823E38（双侧饱和）；
                ±INF 采用平台安全幅值比较判定（阈值取 LREAL 最大有限幅值），NaN 用 fIn <> fIn 自不等判定；
                域内转换委托平台内建 LREAL_TO_REAL 语义，不重实现数学内核；
                信息级码属正常防御：bError=FALSE、bValid=TRUE，输出钳位后防御值。
    错误码    : 16#0001_028E 非有限输入（NaN 或 ±INF）——故障级，返回 0.0
                16#0001_01C0 幅值超 REAL 域，已按符号饱和钳位——信息级，正常防御
                16#0001_01C1 预留禁用（信息级，不得挪用）
                16#0001_028F 预留禁用（故障级，不得挪用）
                16#0001_0290 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R16）
*)
FUNCTION FC_DL_LrealToRealSat : REAL
VAR_INPUT
    fIn : LREAL; // 待转换输入 [无量纲] / input value to convert
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_REAL_MAX   : LREAL := 3.402823E38;            // REAL 域最大有限幅值 [无量纲] / maximum finite magnitude of REAL domain
    DL_LREAL_HUGE : LREAL := 1.7976931348623157E308; // LREAL 最大有限幅值，超过即判 ±INF [无量纲] / max finite LREAL magnitude, beyond means +/-INF
END_VAR
VAR
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_LrealToRealSat := 0.0; // 故障缺省返回 0 [无量纲] / fault default returns 0
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置无效，通过防御闸后置位 / preset invalid, set TRUE after guard passes

// 段 2｜非有限防御闸 / segment 2, non-finite guard
bNonFinite := (fIn <> fIn) OR (fIn > DL_LREAL_HUGE) OR (fIn < -DL_LREAL_HUGE); // NaN 自不等判定，±INF 用安全幅值比较 [无量纲] / NaN by self-inequality, +/-INF by safe magnitude compare
IF bNonFinite THEN
    FC_DL_LrealToRealSat := 0.0; // 故障级返回 0 [无量纲] / fault level returns 0
    eErr   := 16#0001_028E;      // 非有限输入故障码 / non-finite input fault id
    bError := TRUE;              // 置故障标志 / set fault flag
    bValid := FALSE;             // 输出无效 / output invalid
    RETURN;                      // 立即返回 / immediate return
END_IF

// 段 3｜饱和钳位与主体转换（末段） / segment 3, saturating clamp and main conversion (final)
IF fIn > DL_REAL_MAX THEN
    FC_DL_LrealToRealSat := DL_REAL_MAX; // 正向饱和钳至 REAL 上界 [无量纲] / saturate to REAL upper bound
    eErr := 16#0001_01C0;                // 信息级：超上界已钳位 / info level: above upper bound, clamped
ELSIF fIn < -DL_REAL_MAX THEN
    FC_DL_LrealToRealSat := -DL_REAL_MAX; // 负向饱和钳至 REAL 下界 [无量纲] / saturate to REAL lower bound
    eErr := 16#0001_01C0;                 // 信息级：超下界已钳位 / info level: below lower bound, clamped
ELSE
    FC_DL_LrealToRealSat := LREAL_TO_REAL(fIn); // 域内委托平台内建 _TO_ 转换语义 / in-domain delegate to built-in _TO_ conversion
    eErr := 0; // 域内无错误 / in-domain, no error
END_IF
bError := FALSE; // 信息级钳位不置故障，故障分支已提前返回 / info-level clamp never raises fault, fault branch has returned
bValid := TRUE;  // 域内或钳位输出均有效可用 / in-domain or clamped output is valid
END_FUNCTION
