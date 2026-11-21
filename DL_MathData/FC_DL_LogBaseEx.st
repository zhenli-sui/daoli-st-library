(*
    FC_DL_LogBaseEx —— 任意底数对数防御包装
    ------------------------------------------------------------------
    分类      : DL_MathData / Log
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （接口语义由 IEC 61131-3 定义，内部委托平台内建 LN，
                  外围统一错误码 / 钳位 / 双语文档；clean-room 重写，
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R17）
    ------------------------------------------------------------------
    功能说明  : 返回以 fBase 为底的 fIn 对数，按换底公式 LN(fIn)/LN(fBase) 实现，
                两处对数均委托平台内建 LN，不重实现任何对数内核；
                非有限输入判为故障级 16#0001_02CD，返回 0.0 且 bValid=FALSE；
                定义域非法（fIn ≤ 0 或 fBase ≤ 0）判为故障级 16#0001_02CE，返回 0.0；
                底数退化（|fBase − 1| < 1.0E-6，含 fBase = 1）判为故障级 16#0001_02CF，
                返回 0.0（底数为 1 时对数无定义，贴近 1 时商发散，必须先拦不使用除法）；
                钳位方向：无钳位（三路故障均拦截并回缺省值）。
    错误码    : 16#0001_01EA 预留禁用（信息级，不得挪用）
                16#0001_01EB 预留禁用（信息级，不得挪用）
                16#0001_02CD 非有限输入（fIn 或 fBase 为 NaN / ±INF）——故障级，返回 0.0
                16#0001_02CE 定义域非法（fIn ≤ 0 或 fBase ≤ 0）——故障级，返回 0.0
                16#0001_02CF 底数退化（fBase = 1 或 |fBase − 1| < 1.0E-6）——故障级，返回 0.0
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_LogBaseEx : REAL
VAR_INPUT
    fIn   : REAL; // 待求对数的真数（须 > 0） [无量纲] / logarithm argument (must be > 0) [dimensionless]
    fBase : REAL; // 对数底数（须 > 0 且 ≠ 1；=2.0 即 log2 用法） [无量纲] / logarithm base (must be > 0 and not 1; 2.0 yields log2) [dimensionless]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_LOG_FAULT_DEF  : REAL := 0.0;       // 故障缺省返回值 log10(1)=0 [无量纲] / fault default return value log10(1)=0 [dimensionless]
    DL_LOG_BASE_EPS   : REAL := 1.0E-6;    // 底数贴近 1 的判定容差（|fBase−1| < 该值视为退化） [无量纲] / base-near-1 tolerance, below means degenerate
    DL_FLOAT_EPS      : REAL := 1.0E-6;    // 浮点除子判定容差（除法前复判） [无量纲] / floating divisor tolerance, re-checked before division
    DL_REAL_INF_GUARD : LREAL := 4.0E38;   // REAL 域 ±INF 判定阈值，高于 REAL 最大有限值 3.402823E38 [无量纲] / REAL +/-INF guard above max finite REAL 3.402823E38
END_VAR
VAR
    fLnBase    : REAL; // 底数自然对数 LN(fBase) [无量纲] / natural logarithm of the base [dimensionless]
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_LogBaseEx := DL_LOG_FAULT_DEF; // 故障缺省返回 0.0，对下游限幅链中性 [无量纲] / fault default 0.0, neutral for downstream limiting [dimensionless]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置输出无效，通过全部域门后置位 / preset invalid, set TRUE after all domain gates

// 段 2｜非有限防御闸 / segment 2, non-finite guard
bNonFinite := (fIn <> fIn) OR (fIn > DL_REAL_INF_GUARD) OR (fIn < -DL_REAL_INF_GUARD)
           OR (fBase <> fBase) OR (fBase > DL_REAL_INF_GUARD) OR (fBase < -DL_REAL_INF_GUARD); // 真数与底数双向非有限判定（NaN 自不等 + 安全幅值判 ±INF） [无量纲] / non-finite check on both argument and base (NaN by self-inequality, +/-INF by safe magnitude) [dimensionless]
IF bNonFinite THEN
    eErr := 16#0001_02CD; // 非有限输入故障码 / non-finite input fault id
    bError := TRUE;       // 置故障标志 / raise error flag
    bValid := FALSE;      // 输出不可用 / output not usable
    RETURN;               // 故障级提前返回，保持缺省 0.0 / early return on fault, keep default 0.0
END_IF

// 段 3｜定义域（域门）判定 / segment 3, domain gate
IF (fIn <= 0.0) OR (fBase <= 0.0) THEN
    eErr := 16#0001_02CE; // 定义域非法故障码（真数 ≤ 0 或底数 ≤ 0） [无量纲] / domain fault id, argument or base <= 0 [dimensionless]
    bError := TRUE;       // 置故障标志 / raise error flag
    bValid := FALSE;      // 输出不可用 / output not usable
    RETURN;               // 故障级提前返回，保持缺省 0.0 / early return on fault, keep default 0.0
END_IF

// 段 4｜底数退化闸（防 LN 除零发散） / segment 4, base degeneracy gate (prevents LN divide blow-up)
IF ABS(fBase - 1.0) < DL_LOG_BASE_EPS THEN // 底数贴近 1 时 LN(fBase) → 0，商将发散，必须先拦 [无量纲] / base near 1 makes LN(base) approach 0 and the quotient blow up, must gate first [dimensionless]
    eErr := 16#0001_02CF; // 底数退化故障码（fBase = 1 或贴近 1） / degenerate base fault id, fBase = 1 or near 1
    bError := TRUE;       // 置故障标志 / raise error flag
    bValid := FALSE;      // 输出不可用 / output not usable
    RETURN;               // 故障级提前返回，保持缺省 0.0 / early return on fault, keep default 0.0
END_IF

// 段 5｜除子整备与主体除法（末段） / segment 5, divisor preparation and main division (final)
fLnBase := LN(fBase); // 底数自然对数，委托平台内建 LN [无量纲] / natural logarithm of the base via built-in LN [dimensionless]
IF ABS(fLnBase) <= DL_FLOAT_EPS THEN // 除子复判（域闸之外的除法前第二道保险） [无量纲] / divisor re-check, second guard before division [dimensionless]
    eErr := 16#0001_02CF; // 除子趋零仍归入底数退化故障码 / near-zero divisor still reported as degenerate base
    bError := TRUE;       // 置故障标志 / raise error flag
    bValid := FALSE;      // 输出不可用 / output not usable
    RETURN;               // 除法前拦截，绝不执行除法 / blocked before division, division never executed
END_IF
FC_DL_LogBaseEx := LN(fIn) / fLnBase; // 换底公式主体，真数对数同样委托内建 LN [无量纲] / change-of-base body, argument logarithm also delegated to built-in LN [dimensionless]
eErr   := 0;     // 域内无错误 / in-domain, no error
bError := FALSE; // 信息级不置故障 / info level never raises fault
bValid := TRUE;  // 域内输出有效可用 / in-domain output is valid
END_FUNCTION
