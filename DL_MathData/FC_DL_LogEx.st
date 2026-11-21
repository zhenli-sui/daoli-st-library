(*
    FC_DL_LogEx —— 底 10 常用对数防御包装
    ------------------------------------------------------------------
    分类      : DL_MathData / Log
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （接口语义由 IEC 61131-3 定义，内部委托平台内建 LOG，
                  外围统一错误码 / 钳位 / 双语文档；clean-room 重写，
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R17）
    ------------------------------------------------------------------
    功能说明  : 返回输入值的底 10 常用对数（IEC LOG 语义），内部委托平台内建 LOG，
                不重实现任何对数内核；
                非有限输入（NaN 或 ±INF）判为故障级 16#0001_02CA，返回 0.0 且 bValid=FALSE；
                定义域非法（输入 ≤ 0）判为故障级 16#0001_02CB，返回 0.0 且 bValid=FALSE；
                钳位方向：无钳位（两路故障均拦截并回缺省值，不做域内改造）。
    错误码    : 16#0001_01E8 预留禁用（信息级，不得挪用）
                16#0001_01E9 预留禁用（信息级，不得挪用）
                16#0001_02CA 非有限输入（NaN 或 ±INF）——故障级，返回 0.0
                16#0001_02CB 定义域非法（输入 ≤ 0）——故障级，返回 0.0
                16#0001_02CC 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_LogEx : REAL
VAR_INPUT
    fIn : REAL; // 待求对数的输入值（须 > 0） [无量纲] / input value whose logarithm is taken (must be > 0) [dimensionless]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_LOG_FAULT_DEF : REAL := 0.0;                         // 故障缺省返回值 log10(1)=0 [无量纲] / fault default return value log10(1)=0 [dimensionless]
    DL_REAL_INF_GUARD : LREAL := 4.0E38;                     // REAL 域 ±INF 判定阈值，高于 REAL 最大有限值 3.402823E38 [无量纲] / REAL +/-INF guard above max finite REAL 3.402823E38
END_VAR
VAR
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_LogEx := DL_LOG_FAULT_DEF; // 故障缺省返回 0.0，即 log10(1)，对下游限幅链中性 [无量纲] / fault default 0.0, i.e. log10(1), neutral for downstream limiting [dimensionless]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置输出无效，通过域门后置位 / preset invalid, set TRUE after domain gate

// 段 2｜非有限防御闸 / segment 2, non-finite guard
bNonFinite := (fIn <> fIn) OR (fIn > DL_REAL_INF_GUARD) OR (fIn < -DL_REAL_INF_GUARD); // 非有限判定（NaN 自不等 + 安全幅值判 ±INF） [无量纲] / non-finite check (NaN by self-inequality, +/-INF by safe magnitude) [dimensionless]
IF bNonFinite THEN
    eErr := 16#0001_02CA; // 非有限输入故障码 / non-finite input fault id
    bError := TRUE;       // 置故障标志 / raise error flag
    bValid := FALSE;      // 输出不可用 / output not usable
    RETURN;               // 故障级提前返回，保持缺省 0.0 / early return on fault, keep default 0.0
END_IF

// 段 3｜定义域（域门）判定 / segment 3, domain gate
IF fIn <= 0.0 THEN
    eErr := 16#0001_02CB; // 定义域非法故障码（输入 ≤ 0） [无量纲] / domain fault id, input <= 0 [dimensionless]
    bError := TRUE;       // 置故障标志 / raise error flag
    bValid := FALSE;      // 输出不可用 / output not usable
    RETURN;               // 故障级提前返回，保持缺省 0.0 / early return on fault, keep default 0.0
END_IF

// 段 4｜主体计算（末段） / segment 4, main calculation (final)
FC_DL_LogEx := LOG(fIn); // 域内直接委托平台内建 LOG（底 10），不复检结果 [无量纲] / delegate to built-in LOG (base 10) in-domain, no re-check [dimensionless]
eErr   := 0;     // 域内无错误 / in-domain, no error
bError := FALSE; // 信息级不置故障 / info level never raises fault
bValid := TRUE;  // 域内输出有效可用 / in-domain output is valid
END_FUNCTION
