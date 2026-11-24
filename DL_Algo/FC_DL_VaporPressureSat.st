//==============================================================================
// 函数：FC_DL_VaporPressureSat ｜ 中文名称：饱和水蒸气压计算（焓湿图族公式基准原子）
// 所属子库：DL_Algo ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：Magnus-Tetens（过水面参数化）饱和水蒸气压计算，焓湿图全参族
//           （含湿量/湿球/露点逆运算/混风点）的饱和压唯一属主件，族内其余
//           四件一律调用本件取饱和压，禁止各自内联公式（常量单源，防口径
//           漂移）；与 FC_DL_DewPointCalc 系数口径一致（a=17.625、b=243.04、
//           E0=610.94 Pa），属主转移声明：露点族饱和压口径自本件起收口。
// 开源溯源 (Origin)：改写自 OSCAT Building 行为定义（OSCAT 许可，仅行为定义，零代码行）——道莅 clean-room 实现
// 单位表：T[°C] / p_ws[Pa]
// 错误码表：16#0002_2D01 信息级（温度域外已钳位照算，不置 bError）/ 16#0002_2D10
//           故障级（输入非有限或结果溢出，置 bError）/ 16#0002_2D02、16#0002_2D11、
//           16#0002_2D12 预留禁用（不得挪用）
// 状态机：N/A（纯函数，无状态；同输入必得同输出）
// 边界行为：① 温度域外（-40~100 °C 外）钳位照算 + 信息 2D01 + bClamped，
//           低温干燥是合法工况，不置故障；② 非有限输入（NaN/±Inf）→ 故障
//           2D10、bValid := FALSE、fPvSat := 0、返回 FALSE；③ EXP 上溢拦
//           （结果幅值 > 1.7976931348623157E308 复检）→ 故障 2D10 复用
//           （R90 不加码：同属"数值结果不可用"一类，头注释留档复用理由）；
//           异常路径输出为确定值 0，绝不输出未初始化值。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · T1-2 焓湿图族拆分① · 全族公式基准）
//==============================================================================

(*------------------------------------------------------------------------------
 * 调用示例：bOk := FC_DL_VaporPressureSat(fTempC := 25.0, fPvSat => fPws,
 *                                         bClamped => bC, eErr => uE);
 * 族内引用：FC_DL_HumidityRatioCalc / FC_DL_WetBulbTempCalc /
 *           FC_DL_RhFromDewPoint / FC_DL_MixAirStateCalc 一律经本件取饱和压。
 *-----------------------------------------------------------------------------*)
FUNCTION FC_DL_VaporPressureSat : BOOL
VAR_INPUT
    fTempC    : LREAL;                   // 空气温度 [摄氏度]，有效域 -40.0..100.0，域外钳位照算 / Air temperature [degC], valid range -40.0..100.0, clamped outside
END_VAR
VAR_OUTPUT
    fPvSat    : LREAL;                   // 饱和水蒸气压 [Pa] / Saturation vapor pressure [Pa]
    bClamped  : BOOL;                    // TRUE = 输入已钳位，结果按趋势参考 / TRUE = input clamped, result for trend reference only
    eErr      : UDINT;                   // 错误码，0 = 无错 / Error code, 0 = no error
    bError    : BOOL;                    // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid    : BOOL;                    // 输出可用标志 / Outputs usable flag
END_VAR
VAR CONSTANT
    DL_PSV_TMIN  : LREAL := -40.0;       // Magnus-Tetens 有效域下限 [摄氏度] / Magnus-Tetens valid range low [degC]
    DL_PSV_TMAX  : LREAL := 100.0;       // Magnus-Tetens 有效域上限 [摄氏度] / Magnus-Tetens valid range high [degC]
    DL_PSV_E0    : LREAL := 610.94;      // 0 摄氏度饱和水汽压基准 [Pa] / Reference saturation pressure at 0 degC [Pa]
    DL_PSV_A     : LREAL := 17.625;      // Magnus 系数 a [1]，与 FC_DL_DewPointCalc 同口径 / Magnus coefficient a [1], same as dew point FC
    DL_PSV_B     : LREAL := 243.04;      // Magnus 系数 b [摄氏度] / Magnus coefficient b [degC]
    DL_PSV_EPS   : LREAL := 1.0E-6;      // 浮点判零容差 / Float zero tolerance
    DL_PSV_INF   : LREAL := 1.7976931348623157E308; // LREAL 幅值上限，EXP 上溢复检基准 / LREAL magnitude ceiling, EXP overflow recheck bound
END_VAR
VAR
    fTEff   : LREAL;                     // 钳位后的生效温度 [摄氏度] / Effective clamped temperature [degC]
    fDenom  : LREAL;                     // Magnus 分母 (b+T) [摄氏度] / Magnus denominator (b+T) [degC]
    fResult : LREAL;                     // 公式原始结果 [Pa]，有限性复检前暂存 / Raw formula result [Pa], staged before the finiteness recheck
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值：入口即赋确定值，任何提前 RETURN 前输出已确定
 *      Exit defaults: outputs assigned deterministically on entry
 *-----------------------------------------------------------------------------*)
FC_DL_VaporPressureSat := FALSE;         // 返回值默认无效 / Return value preset invalid
fPvSat := 0.0;                           // 饱和压默认置零 / Saturation pressure preset to zero
bClamped := FALSE;                       // 钳位标志默认 FALSE / Clamped flag preset FALSE
eErr := 16#0000_0000;                    // 错误码先清零 / Error code cleared first
bError := FALSE;                         // 故障标志先清零 / Fault flag cleared first
bValid := FALSE;                         // 可用标志先清零 / Usable flag cleared first

(*------------------------------------------------------------------------------
 * 段 2｜非有限值防御：NaN 用 (x<>x) 判，Inf 用双侧幅值判（R79 口径）
 *      Non-finite defense: NaN via (x<>x), Inf via two-sided magnitude bound
 *-----------------------------------------------------------------------------*)
IF (fTempC <> fTempC) OR (fTempC < -DL_PSV_INF) OR (fTempC > DL_PSV_INF) THEN
    eErr   := 16#0002_2D10;              // 故障级：输入非有限（NaN/Inf） / Fault: non-finite input
    bError := TRUE;                      // 故障级码位必须同时置故障标志（R45 配对） / Fault code paired with the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;                              // 异常路径出口，fPvSat 保持确定值 0 / Error path exit, output stays deterministic zero
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜温度钳位：域外按趋势参考照算，信息级不置故障（低温干燥合法工况）
 *      Temperature clamping: out-of-domain treated as trend reference, info only
 *-----------------------------------------------------------------------------*)
IF (fTempC < DL_PSV_TMIN) OR (fTempC > DL_PSV_TMAX) THEN
    fTEff := MIN(MAX(fTempC, DL_PSV_TMIN), DL_PSV_TMAX); // 双侧钳位到有效域 / Two-sided clamp into valid range
    bClamped := TRUE;                    // 钳位声明置位 / Clamped flag raised
    eErr := 16#0002_2D01;                // 信息级：温度已钳位（不置 bError） / Info: temperature clamped, no fault flag
ELSE
    fTEff := fTempC;                     // 合法温度原值生效 / Valid temperature applied as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜Magnus-Tetens 主体：p_ws = 610.94·EXP(17.625·T/(T+243.04))
 *      分母 (b+T) 由 T >= -40 保证恒正，仍做防御性双检（防除零）
 *      Magnus-Tetens core, denominator guarded even though always positive
 *-----------------------------------------------------------------------------*)
fDenom := DL_PSV_B + fTEff;              // Magnus 分母 [摄氏度] / Magnus denominator [degC]
IF ABS(fDenom) <= DL_PSV_EPS THEN
    eErr   := 16#0002_2D10;              // 故障级：分母退化复用非有限码（R90） / Fault: degenerate denominator, code reused
    bError := TRUE;                      // 置故障标志 / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF
fResult := DL_PSV_E0 * EXP(DL_PSV_A * fTEff / fDenom); // 饱和水蒸气压原始结果 [Pa] / Raw saturation vapor pressure [Pa]

(*------------------------------------------------------------------------------
 * 段 5｜结果有限性复检：EXP 上溢拦（R90 复用 2D10，理由：同属数值结果
 *      不可用一类，不新开码位）
 *      Result finiteness recheck, EXP overflow folded into 2D10 per R90
 *-----------------------------------------------------------------------------*)
IF (fResult <> fResult) OR (fResult > DL_PSV_INF) OR (fResult < -DL_PSV_INF) THEN
    fPvSat := 0.0;                       // 溢出结果丢弃，输出确定值 0 / Overflowed result discarded, output zero
    eErr   := 16#0002_2D10;              // 故障级：结果溢出复用（R90） / Fault: result overflow, code reused
    bError := TRUE;                      // 置故障标志 / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF

fPvSat := fResult;                       // 有限结果出口 / Finite result outlet
bValid := TRUE;                          // 输出可用 / Outputs usable
FC_DL_VaporPressureSat := TRUE;          // 返回 TRUE = 计算有效 / Return TRUE = computation valid
END_FUNCTION
