(*
    FC_DL_AmpDbToRatio —— 幅值型分贝到线性幅值比换算
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
    功能说明  : 幅值型分贝转过线性幅值比，按 A = 10^(dB/20) 实现，指数运算委托平台内建 EXPT，
                20 为幅值型换算因子（与功率型 10 严格区分，禁混用），不重实现指数内核；
                非有限输入判为故障级 16#0001_02D0，返回 1.0（比值中性值，避免下游乘零灭信号）；
                |dB| 超 400.0 dB 硬限时按方向饱和至 1.0E20 / 1.0E-20，置信息级 16#0001_01EC；
                EXPT 结果复检非有限（部分平台溢出行为不一致）同样按方向饱和并复用 01EC；
                钳位方向：双侧饱和（dB 域 ±400.0 dB，比值域 1.0E-20 ~ 1.0E20）。
    错误码    : 16#0001_01EC dB 值超 ±400.0 dB 硬限，已按方向饱和——信息级，正常防御
                16#0001_01ED 预留禁用（信息级，不得挪用）
                16#0001_02D0 非有限输入（NaN 或 ±INF）——故障级，返回 1.0
                16#0001_02D1 预留禁用（故障级，不得挪用）
                16#0001_02D2 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_AmpDbToRatio : REAL
VAR_INPUT
    fDb : REAL; // 幅值型分贝值，建议域 −400.0~+400.0 [dB] / amplitude decibel value, suggested domain -400.0..+400.0 [dB]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_DB_AMP_DIV     : REAL := 20.0;      // 幅值型 dB 换算除子（20·log10 的逆向） [dB] / amplitude dB divisor, inverse of 20*log10 [dB]
    DL_DB_TEN         : REAL := 10.0;      // 幂运算底数 10 [无量纲] / power base 10 [dimensionless]
    DL_DB_LIMIT       : REAL := 400.0;     // dB 域双侧硬限，对应比值 10^±20 [dB] / two-sided dB hard limit, ratio 10^+/-20 [dB]
    DL_RATIO_NEUTRAL  : REAL := 1.0;       // 比值中性值（0 dB 对应值，故障缺省返回） [比] / neutral ratio (0 dB), fault default [ratio]
    DL_RATIO_MAX      : REAL := 1.0E20;    // 幅值比上限 10^20，REAL 域可表 [比] / amplitude ratio upper bound 10^20 [ratio]
    DL_RATIO_MIN      : REAL := 1.0E-20;   // 幅值比下限 10^-20，REAL 域可表 [比] / amplitude ratio lower bound 10^-20 [ratio]
    DL_REAL_INF_GUARD : LREAL := 4.0E38;   // REAL 域 ±INF 判定阈值，高于 REAL 最大有限值 3.402823E38 [无量纲] / REAL +/-INF guard above max finite REAL
END_VAR
VAR
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_AmpDbToRatio := DL_RATIO_NEUTRAL; // 故障缺省返回 1.0 中性比值，避免下游乘零灭信号 [比] / fault default 1.0 neutral ratio, avoids killing the signal downstream [ratio]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置输出无效，通过非有限闸后置位 / preset invalid, set TRUE after the non-finite gate

// 段 2｜非有限防御闸 / segment 2, non-finite guard
bNonFinite := (fDb <> fDb) OR (fDb > DL_REAL_INF_GUARD) OR (fDb < -DL_REAL_INF_GUARD); // 非有限判定（NaN 自不等 + 安全幅值判 ±INF） [dB] / non-finite check (NaN by self-inequality, +/-INF by safe magnitude) [dB]
IF bNonFinite THEN
    eErr := 16#0001_02D0; // 非有限输入故障码 / non-finite input fault id
    bError := TRUE;       // 置故障标志 / raise error flag
    bValid := FALSE;      // 输出不可用 / output not usable
    RETURN;               // 故障级提前返回，保持缺省 1.0 / early return on fault, keep default 1.0
END_IF

// 段 3｜dB 域硬限双侧饱和 / segment 3, two-sided dB domain saturation
IF fDb > DL_DB_LIMIT THEN
    FC_DL_AmpDbToRatio := DL_RATIO_MAX; // 正超饱和至幅值比上限 1.0E20 [比] / positive overflow saturates to ratio upper bound 1.0E20 [ratio]
    eErr := 16#0001_01EC;               // 信息级：dB 超限已饱和，正常防御 / info level: dB exceeded the limit and saturated, normal defence
    bError := FALSE;                    // 信息级不置故障 / info level never raises fault
    bValid := TRUE;                     // 饱和值本身有效可用 / the saturated value itself is valid
    RETURN;                             // 饱和即出口，不进入幂运算 / saturation is the exit, no power computation
END_IF
IF fDb < -DL_DB_LIMIT THEN
    FC_DL_AmpDbToRatio := DL_RATIO_MIN; // 负超饱和至幅值比下限 1.0E-20 [比] / negative overflow saturates to ratio lower bound 1.0E-20 [ratio]
    eErr := 16#0001_01EC;               // 同一业务语义复用同一信息码 / same business semantics reuses the same info id
    bError := FALSE;                    // 信息级不置故障 / info level never raises fault
    bValid := TRUE;                     // 饱和值本身有效可用 / the saturated value itself is valid
    RETURN;                             // 饱和即出口，不进入幂运算 / saturation is the exit, no power computation
END_IF

// 段 4｜主体幂运算与结果复检（末段） / segment 4, main power computation and result re-check (final)
FC_DL_AmpDbToRatio := EXPT(DL_DB_TEN, fDb / DL_DB_AMP_DIV); // 域内委托内建 EXPT 计算 10^(dB/20) [比] / in-domain delegate to built-in EXPT for 10^(dB/20) [ratio]
IF (FC_DL_AmpDbToRatio <> FC_DL_AmpDbToRatio) OR (FC_DL_AmpDbToRatio > DL_RATIO_MAX) OR (FC_DL_AmpDbToRatio < DL_RATIO_MIN) THEN // 结果复检：NaN 自不等 + 双侧越界（±INF 亦被幅值界捕获） [比] / result re-check: NaN by self-inequality plus two-sided overflow, +/-INF also caught by the magnitude bounds [ratio]
    IF fDb >= 0.0 THEN
        FC_DL_AmpDbToRatio := DL_RATIO_MAX; // 按输入符号方向饱和至上限 [比] / saturate upward following the input sign [ratio]
    ELSE
        FC_DL_AmpDbToRatio := DL_RATIO_MIN; // 按输入符号方向饱和至下限 [比] / saturate downward following the input sign [ratio]
    END_IF
    eErr := 16#0001_01EC; // 溢出行为差异复用同一信息码，不另立码 / platform overflow difference reuses the same info id, no extra code
    bError := FALSE;      // 信息级不置故障 / info level never raises fault
    bValid := TRUE;       // 饱和值本身有效可用 / the saturated value itself is valid
    RETURN;               // 复检出口 / exit after the re-check
END_IF
eErr   := 0;     // 域内无错误 / in-domain, no error
bError := FALSE; // 信息级不置故障 / info level never raises fault
bValid := TRUE;  // 域内输出有效可用 / in-domain output is valid
END_FUNCTION
