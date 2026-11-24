(*
    FC_DL_RatioToAmpDb —— 线性幅值比到幅值型分贝换算
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
    功能说明  : 线性幅值比转幅值型分贝值，按 dB = 20·log10(A) 实现，对数委托平台内建 LOG，
                20 为幅值型换算因子（与功率型 10 严格区分，禁混用），不重实现对数内核；
                非有限输入判为故障级 16#0001_02D3，返回 0.0 dB；
                定义域非法（比值 ≤ 0）判为故障级 16#0001_02D4，返回 0.0 dB；
                结果 |dB| 超 400.0 dB 时钳至 ±400.0 dB 并置信息级 16#0001_01EE
                （极小比值约 −760 dB，不钳会让下游 dB 域常量溢出）；
                钳位方向：结果双侧钳位至 ±400.0 dB。
    错误码    : 16#0001_01EE 结果超 ±400.0 dB，已钳至 dB 域硬限——信息级，正常防御
                16#0001_01EF 预留禁用（信息级，不得挪用）
                16#0001_02D3 非有限输入（NaN 或 ±INF）——故障级，返回 0.0
                16#0001_02D4 定义域非法（幅值比 ≤ 0）——故障级，返回 0.0
                16#0001_02D5 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_RatioToAmpDb : REAL
VAR_INPUT
    fRatio : REAL; // 线性幅值比（须 > 0，1.0 = 0 dB） [比] / linear amplitude ratio (must be > 0, 1.0 means 0 dB) [ratio]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_DB_FAULT_DEF   : REAL := 0.0;      // 故障缺省返回值（0 dB 中性值） [dB] / fault default return (0 dB neutral) [dB]
    DL_DB_AMP_FACTOR  : REAL := 20.0;     // 幅值型 dB 换算因子 20·log10 [dB] / amplitude dB factor 20*log10 [dB]
    DL_DB_LIMIT       : REAL := 400.0;    // dB 域双侧硬限 [dB] / two-sided dB hard limit [dB]
    DL_REAL_INF_GUARD : LREAL := 4.0E38;  // REAL 域 ±INF 判定阈值，高于 REAL 最大有限值 3.402823E38 [无量纲] / REAL +/-INF guard above max finite REAL
END_VAR
VAR
    fDb        : REAL; // dB 换算中间结果 [dB] / intermediate dB result [dB]
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_RatioToAmpDb := DL_DB_FAULT_DEF; // 故障缺省返回 0 dB 中性值 [dB] / fault default 0 dB neutral value [dB]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置输出无效，通过全部域门后置位 / preset invalid, set TRUE after all domain gates

// 段 2｜非有限防御闸 / segment 2, non-finite guard
bNonFinite := (fRatio <> fRatio) OR (fRatio > DL_REAL_INF_GUARD) OR (fRatio < -DL_REAL_INF_GUARD); // 非有限判定（NaN 自不等 + 安全幅值判 ±INF） [比] / non-finite check (NaN by self-inequality, +/-INF by safe magnitude) [ratio]
IF bNonFinite THEN
    eErr := 16#0001_02D3; // 非有限输入故障码 / non-finite input fault id
    bError := TRUE;       // 置故障标志 / raise error flag
    bValid := FALSE;      // 输出不可用 / output not usable
    RETURN;               // 故障级提前返回，保持缺省 0 dB / early return on fault, keep default 0 dB
END_IF

// 段 3｜定义域（域门）判定 / segment 3, domain gate
IF fRatio <= 0.0 THEN
    eErr := 16#0001_02D4; // 定义域非法故障码（比值 ≤ 0，零点与负数无对数） [比] / domain fault id, ratio <= 0 has no logarithm [ratio]
    bError := TRUE;       // 置故障标志 / raise error flag
    bValid := FALSE;      // 输出不可用 / output not usable
    RETURN;               // 故障级提前返回，保持缺省 0 dB / early return on fault, keep default 0 dB
END_IF

// 段 4｜主体对数换算与结果钳位（末段） / segment 4, main logarithm conversion and result clamp (final)
fDb := LOG(fRatio) * DL_DB_AMP_FACTOR; // 委托内建 LOG 后乘幅值型因子 20 [dB] / delegate to built-in LOG then multiply amplitude factor 20 [dB]
IF fDb > DL_DB_LIMIT THEN
    fDb := DL_DB_LIMIT;   // 上侧钳至 +400.0 dB [dB] / clamp upward to +400.0 dB [dB]
    eErr := 16#0001_01EE; // 信息级：结果超硬限已钳位，正常防御 / info level: result exceeded the hard limit and was clamped
ELSIF fDb < -DL_DB_LIMIT THEN
    fDb := -DL_DB_LIMIT;  // 下侧钳至 −400.0 dB（极小比值不钳会使下游常量溢出） [dB] / clamp downward to -400.0 dB, tiny ratios would overflow downstream constants [dB]
    eErr := 16#0001_01EE; // 同一业务语义复用同一信息码 / same business semantics reuses the same info id
ELSE
    eErr := 0;            // 域内无错误 / in-domain, no error
END_IF
FC_DL_RatioToAmpDb := fDb; // 输出钳位后的 dB 结果 [dB] / output the clamped dB result [dB]
bError := FALSE;           // 信息级不置故障 / info level never raises fault
bValid := TRUE;            // 域内或钳位后输出均有效可用 / in-domain or clamped output is valid
END_FUNCTION
