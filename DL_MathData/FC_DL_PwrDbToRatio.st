(*
    FC_DL_PwrDbToRatio —— 功率型分贝到线性功率比换算
    ------------------------------------------------------------------
    分类      : DL_MathData / Log
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （接口语义由 IEC 61131-3 定义，内部委托平台内建 EXPT，
                  外围统一错误码 / 钳位 / 双语文档；clean-room 重写，
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R17）
    ------------------------------------------------------------------
    功能说明  : 功率型分贝转过线性功率比，按 P = 10^(dB/10) 实现，指数运算委托平台内建 EXPT，
                10 为功率型换算因子（与幅值型 20 严格区分，禁混用），不重实现指数内核；
                非有限输入判为故障级 16#0001_02D6，返回 1.0（功率比中性值）；
                |dB| 超 380.0 dB 硬限时按方向饱和至 1.0E38 / 1.0E-38，置信息级 16#0001_01F0；
                硬限取 380.0 dB 而非 400.0 dB 的理由：功率型 400 dB 对应比值 10^40，
                超出 REAL 最大有限值 3.402823E38，饱和值本身不可表；380 dB 对应 10^±38，两端均可表；
                钳位方向：双侧饱和（dB 域 ±380.0 dB，比值域 1.0E-38 ~ 1.0E38）。
    错误码    : 16#0001_01F0 dB 值超 ±380.0 dB 硬限，已按方向饱和——信息级，正常防御
                16#0001_01F1 预留禁用（信息级，不得挪用）
                16#0001_02D6 非有限输入（NaN 或 ±INF）——故障级，返回 1.0
                16#0001_02D7 预留禁用（故障级，不得挪用）
                16#0001_02D8 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_PwrDbToRatio : REAL
VAR_INPUT
    fDb : REAL; // 功率型分贝值，建议域 −380.0~+380.0 [dB] / power decibel value, suggested domain -380.0..+380.0 [dB]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_DB_PWR_DIV     : REAL := 10.0;     // 功率型 dB 换算除子（10·log10 的逆向） [dB] / power dB divisor, inverse of 10*log10 [dB]
    DL_DB_TEN         : REAL := 10.0;     // 幂运算底数 10 [无量纲] / power base 10 [dimensionless]
    DL_DB_PWR_LIMIT   : REAL := 380.0;    // 功率型 dB 域双侧硬限，对应比值 10^±38（400 dB 会超出 REAL 域） [dB] / power dB hard limit, ratio 10^+/-38 [dB]
    DL_RATIO_NEUTRAL  : REAL := 1.0;      // 功率比中性值（0 dB 对应值，故障缺省返回） [比] / neutral power ratio (0 dB), fault default [ratio]
    DL_PWR_RATIO_MAX  : REAL := 1.0E38;   // 功率比上限 10^38，REAL 域可表 [比] / power ratio upper bound 10^38 [ratio]
    DL_PWR_RATIO_MIN  : REAL := 1.0E-38;  // 功率比下限 10^-38，REAL 域可表 [比] / power ratio lower bound 10^-38 [ratio]
    DL_REAL_INF_GUARD : LREAL := 4.0E38;  // REAL 域 ±INF 判定阈值，高于 REAL 最大有限值 3.402823E38 [无量纲] / REAL +/-INF guard above max finite REAL
END_VAR
VAR
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_PwrDbToRatio := DL_RATIO_NEUTRAL; // 故障缺省返回 1.0 功率比中性值 [比] / fault default 1.0 neutral power ratio [ratio]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置输出无效，通过非有限闸后置位 / preset invalid, set TRUE after the non-finite gate

// 段 2｜非有限防御闸 / segment 2, non-finite guard
bNonFinite := (fDb <> fDb) OR (fDb > DL_REAL_INF_GUARD) OR (fDb < -DL_REAL_INF_GUARD); // 非有限判定（NaN 自不等 + 安全幅值判 ±INF） [dB] / non-finite check (NaN by self-inequality, +/-INF by safe magnitude) [dB]
IF bNonFinite THEN
    eErr := 16#0001_02D6; // 非有限输入故障码 / non-finite input fault id
    bError := TRUE;       // 置故障标志 / raise error flag
    bValid := FALSE;      // 输出不可用 / output not usable
    RETURN;               // 故障级提前返回，保持缺省 1.0 / early return on fault, keep default 1.0
END_IF

// 段 3｜dB 域硬限双侧饱和 / segment 3, two-sided dB domain saturation
IF fDb > DL_DB_PWR_LIMIT THEN
    FC_DL_PwrDbToRatio := DL_PWR_RATIO_MAX; // 正超饱和至功率比上限 1.0E38 [比] / positive overflow saturates to power ratio upper bound 1.0E38 [ratio]
    eErr := 16#0001_01F0;                   // 信息级：dB 超限已饱和，正常防御 / info level: dB exceeded the limit and saturated, normal defence
    bError := FALSE;                        // 信息级不置故障 / info level never raises fault
    bValid := TRUE;                         // 饱和值本身有效可用 / the saturated value itself is valid
    RETURN;                                 // 饱和即出口，不进入幂运算 / saturation is the exit, no power computation
END_IF
IF fDb < -DL_DB_PWR_LIMIT THEN
    FC_DL_PwrDbToRatio := DL_PWR_RATIO_MIN; // 负超饱和至功率比下限 1.0E-38 [比] / negative overflow saturates to power ratio lower bound 1.0E-38 [ratio]
    eErr := 16#0001_01F0;                   // 同一业务语义复用同一信息码 / same business semantics reuses the same info id
    bError := FALSE;                        // 信息级不置故障 / info level never raises fault
    bValid := TRUE;                         // 饱和值本身有效可用 / the saturated value itself is valid
    RETURN;                                 // 饱和即出口，不进入幂运算 / saturation is the exit, no power computation
END_IF

// 段 4｜主体幂运算与结果复检（末段） / segment 4, main power computation and result re-check (final)
FC_DL_PwrDbToRatio := EXPT(DL_DB_TEN, fDb / DL_DB_PWR_DIV); // 域内委托内建 EXPT 计算 10^(dB/10) [比] / in-domain delegate to built-in EXPT for 10^(dB/10) [ratio]
IF (FC_DL_PwrDbToRatio <> FC_DL_PwrDbToRatio) OR (FC_DL_PwrDbToRatio > DL_PWR_RATIO_MAX) OR (FC_DL_PwrDbToRatio < DL_PWR_RATIO_MIN) THEN // 结果复检：NaN 自不等 + 双侧越界（±INF 亦被幅值界捕获） [比] / result re-check: NaN by self-inequality plus two-sided overflow, +/-INF also caught by the magnitude bounds [ratio]
    IF fDb >= 0.0 THEN
        FC_DL_PwrDbToRatio := DL_PWR_RATIO_MAX; // 按输入符号方向饱和至上限 [比] / saturate upward following the input sign [ratio]
    ELSE
        FC_DL_PwrDbToRatio := DL_PWR_RATIO_MIN; // 按输入符号方向饱和至下限 [比] / saturate downward following the input sign [ratio]
    END_IF
    eErr := 16#0001_01F0; // 溢出行为差异复用同一信息码，不另立码 / platform overflow difference reuses the same info id, no extra code
    bError := FALSE;      // 信息级不置故障 / info level never raises fault
    bValid := TRUE;       // 饱和值本身有效可用 / the saturated value itself is valid
    RETURN;               // 复检出口 / exit after the re-check
END_IF
eErr   := 0;     // 域内无错误 / in-domain, no error
bError := FALSE; // 信息级不置故障 / info level never raises fault
bValid := TRUE;  // 域内输出有效可用 / in-domain output is valid
END_FUNCTION
