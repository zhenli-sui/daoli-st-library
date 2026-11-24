//==============================================================================
// 函数：FC_DL_MixAirStateCalc ｜ 中文名称：回风/新风混合点状态计算（焓湿图族拆分⑤）
// 所属子库：DL_Algo ｜ 版本：v1.0.2 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：质量守恒加权求回风/新风混合点状态：干球温度与含湿量分别按
//           新风比加权（fMixX = fOaFrac/100·fOaX + (1−fOaFrac/100)·fRaX），
//           并内联复算混合焓 h = 1.006·T + W·(2501 + 1.86·T) [kJ/kg 干空气]；
//           结露判据用混合点水汽分压与混合温度下饱和压比较（p_v_mix >
//           p_ws(T_mix) 即越过饱和线），饱和压取自族属主
//           FC_DL_VaporPressureSat，零内联公式。ASHRAE 混风质量守恒公开
//           公式；职责边界：本件算状态点，经济器决策属 FB_DL_EnthalpyCompareCtrl。
// 开源溯源 (Origin)：改写自 OSCAT Building 行为定义（OSCAT 许可，仅行为定义，零代码行）——道莅 clean-room 实现
// 单位表：T[°C] / W[kg 水蒸气/kg 干空气] / 新风比[%] / h[kJ/kg 干空气] /
//         p[Pa] / p_v[Pa] / p_ws[Pa]
// 错误码表：16#0002_3101 信息级（新风比或含湿量域外已钳位，不置 bError）/
//           16#0002_3110 故障级（任一输入非有限，置 bError）/
//           16#0002_3102、16#0002_3111、16#0002_3112 预留禁用（不得挪用）
// 状态机：N/A（纯函数，无状态）
// 边界行为：① fOaFrac 域外（0~100 外）→ 钳位 + 信息 3101；② 任一输入
//           非有限 → 故障 3110、bValid := FALSE、输出 0；③ 含湿量输入
//           < 0 → 钳 0 + 信息 3101 复用（R90）；④ 结露仅置 bCondensation
//           预警位，不置故障（结露是工况事实不是错误）；⑤ 属主件拒绝 →
//           故障 3110 复用（R90）；异常路径输出确定值，绝不输出未初始化值。
// 依赖收窄 (R11 留档③)：DL_Algo 不得跨库调用，混合焓用本件内联等价式
//           h := 1.006·T + W·(2501 + 1.86·T)，与 FC_DL_HumidAirEnthalpy 的
//           口径一致性由本件头注释承担验证责任（常量逐一同源：1.006 /
//           2501 / 1.86，改动任一侧须同步复核另一侧）。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · T1-2 焓湿图族拆分⑤ · 族收口件）
//           v1.0.1 2026-11-17 R23 终审修复：段 2 非有限闸补查 fOaFrac
//           （原漏判 NaN 新风比会以 bValid=TRUE 放行 NaN 混合输出），契约不变。
//           v1.0.2 2026-11-23 R73 补 bValid 回执：段 6 属主件调用补收 bValid
//           局部回执，回执无效并入既有 3110 兜底分支，契约不变。
//==============================================================================

(*------------------------------------------------------------------------------
 * 调用示例：bOk := FC_DL_MixAirStateCalc(
 *             fRaTempC := 26.0, fRaHumRatio := 0.0105,
 *             fOaTempC := 33.0, fOaHumRatio := 0.0192,
 *             fOaFrac := 30.0, fPress := 101325.0,
 *             fMixTempC => fTmix, fMixHumRatio => fWmix,
 *             fMixEnthalpy => fHmix, bCondensation => bCond, eErr => uE);
 * 结露预警口径：bCondensation = TRUE 时混合点位于饱和线下游，表冷器/风道
 * 有凝水风险；该位是工况事实，上层据此决策，不作为故障联锁。
 *-----------------------------------------------------------------------------*)
FUNCTION FC_DL_MixAirStateCalc : BOOL
VAR_INPUT
    fRaTempC     : LREAL;                  // 回风干球温度 [摄氏度] / Return-air dry-bulb temperature [degC]
    fRaHumRatio  : LREAL;                  // 回风含湿量 [kg 水蒸气/kg 干空气] / Return-air humidity ratio [kg/kg dry air]
    fOaTempC     : LREAL;                  // 新风干球温度 [摄氏度] / Outdoor-air dry-bulb temperature [degC]
    fOaHumRatio  : LREAL;                  // 新风含湿量 [kg 水蒸气/kg 干空气] / Outdoor-air humidity ratio [kg/kg dry air]
    fOaFrac      : LREAL;                  // 新风比 [百分数]，有效域 0.0..100.0，域外钳位照算 / Outdoor-air fraction [percent], valid range 0.0..100.0
    fPress       : LREAL := 101325.0;      // 大气压 [Pa]，引脚注入非魔法数 / Atmospheric pressure [Pa], injected via the pin
END_VAR
VAR_OUTPUT
    fMixTempC    : LREAL;                  // 混合点干球温度 [摄氏度] / Mixed dry-bulb temperature [degC]
    fMixHumRatio : LREAL;                  // 混合点含湿量 [kg 水蒸气/kg 干空气] / Mixed humidity ratio [kg/kg dry air]
    fMixEnthalpy : LREAL;                  // 混合点比焓 [kJ/kg 干空气] / Mixed specific enthalpy [kJ/kg dry air]
    bCondensation: BOOL;                   // TRUE = 混合点越过饱和线，结露预警（非故障） / TRUE = mixing point crosses the saturation line, condensation warning, not a fault
    eErr         : UDINT;                  // 错误码，0 = 无错 / Error code, 0 = no error
    bError       : BOOL;                   // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid       : BOOL;                   // 输出可用标志 / Outputs usable flag
END_VAR
VAR CONSTANT
    DL_MIX_CP_DRY  : LREAL := 1.006;     // 干空气比热 [kJ/(kg·K)]，与 FC_DL_HumidAirEnthalpy 同源 / Dry-air specific heat [kJ/(kg*K)], same source as the enthalpy FC
    DL_MIX_HFG0    : LREAL := 2501.0;    // 0 摄氏度水汽化潜热 [kJ/kg]，同源口径 / Latent heat of vaporization at 0 degC [kJ/kg], same source
    DL_MIX_CP_VAP  : LREAL := 1.86;      // 水汽比热 [kJ/(kg·K)]，同源口径 / Vapor specific heat [kJ/(kg*K)], same source
    DL_MIX_MW      : LREAL := 0.621945;  // 干空气/水蒸气摩尔质量比 [kg/kg]，ASHRAE 口径 / Molar mass ratio dry air to vapor [kg/kg], ASHRAE
    DL_MIX_FRAC_MIN: LREAL := 0.0;       // 新风比钳位下限 [百分数] / Outdoor fraction clamp floor [percent]
    DL_MIX_FRAC_MAX: LREAL := 100.0;     // 新风比钳位上限 [百分数] / Outdoor fraction clamp ceiling [percent]
    DL_MIX_EPS     : LREAL := 1.0E-6;    // 浮点判零容差 [Pa] / Float zero tolerance [Pa]
    DL_MIX_INF     : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
END_VAR
VAR
    fFracEff   : LREAL;                  // 钳位后的生效新风比份额 [1] / Effective outdoor fraction share [1]
    fRaWEff    : LREAL;                  // 钳位后的生效回风含湿量 [kg/kg] / Effective return-air humidity ratio [kg/kg]
    fOaWEff    : LREAL;                  // 钳位后的生效新风含湿量 [kg/kg] / Effective outdoor-air humidity ratio [kg/kg]
    fPvMix     : LREAL;                  // 混合点水汽分压 [Pa] / Mixed vapor partial pressure [Pa]
    fPwsMix    : LREAL;                  // 混合温度下饱和压 [Pa]，属主件取得 / Saturation pressure at the mixed temperature [Pa]
    fDenom     : LREAL;                  // 分压反算分母 (MW + W_mix) [kg/kg] / Denominator of the partial-pressure inversion [kg/kg]
    _bPwsValid : BOOL;                   // 饱和压属主件输出可用回执 / Saturation owner FC outputs-usable receipt
    _bPwsClamped : BOOL;    // 属主件钳位回执（本件不消费，仅契约全回执） / Owner clamp receipt (unused, full-receipt contract)
    _nPwsErr     : UDINT;   // 属主件错误码回执 / Owner error-code receipt
    _bPwsError   : BOOL;    // 属主件故障级回执 / Owner fault-flag receipt
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值：入口即赋确定值
 *      Exit defaults: outputs assigned deterministically on entry
 *-----------------------------------------------------------------------------*)
FC_DL_MixAirStateCalc := FALSE;          // 返回值默认无效 / Return value preset invalid
fMixTempC := 0.0;                        // 混合温度默认置零 / Mixed temperature preset to zero
fMixHumRatio := 0.0;                     // 混合含湿量默认置零 / Mixed humidity ratio preset to zero
fMixEnthalpy := 0.0;                     // 混合焓默认置零 / Mixed enthalpy preset to zero
bCondensation := FALSE;                  // 结露预警默认 FALSE / Condensation warning preset FALSE
eErr := 16#0000_0000;                    // 错误码先清零 / Error code cleared first
bError := FALSE;                         // 故障标志先清零 / Fault flag cleared first
bValid := FALSE;                         // 可用标志先清零 / Usable flag cleared first

(*------------------------------------------------------------------------------
 * 段 2｜非有限值防御：六个输入全查（含默认注入的大气压与新风比）
 *      Non-finite defense on all six inputs
 *-----------------------------------------------------------------------------*)
IF (fRaTempC <> fRaTempC) OR (ABS(fRaTempC) > DL_MIX_INF)
   OR (fRaHumRatio <> fRaHumRatio) OR (ABS(fRaHumRatio) > DL_MIX_INF)
   OR (fOaTempC <> fOaTempC) OR (ABS(fOaTempC) > DL_MIX_INF)
   OR (fOaHumRatio <> fOaHumRatio) OR (ABS(fOaHumRatio) > DL_MIX_INF)
   OR (fOaFrac <> fOaFrac) OR (ABS(fOaFrac) > DL_MIX_INF)
   OR (fPress <> fPress) OR (ABS(fPress) > DL_MIX_INF) THEN
    eErr   := 16#0002_3110;              // 故障级：输入非有限 / Fault: non-finite input
    bError := TRUE;                      // 置故障标志（R45 配对） / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜域外钳位：新风比 0~100、含湿量 >= 0，信息级共码 3101（R90）
 *      Out-of-domain clamping with a shared info code per R90
 *-----------------------------------------------------------------------------*)
IF (fOaFrac < DL_MIX_FRAC_MIN) OR (fOaFrac > DL_MIX_FRAC_MAX) THEN
    fFracEff := MIN(MAX(fOaFrac, DL_MIX_FRAC_MIN), DL_MIX_FRAC_MAX) / 100.0; // 新风比双侧钳位并转份额 / Two-sided fraction clamp, converted to share
    eErr := 16#0002_3101;                // 信息级：新风比已钳位（不置 bError） / Info: outdoor fraction clamped, no fault flag
ELSE
    fFracEff := fOaFrac / 100.0;         // 合法新风比转份额 [1] / Valid fraction converted to share [1]
END_IF
IF fRaHumRatio < 0.0 THEN
    fRaWEff := 0.0;                      // 回风含湿量负值钳 0（物理下界） / Negative return humidity ratio clamped to zero
    eErr := 16#0002_3101;                // 信息级：含湿量已钳位复用（R90） / Info: humidity ratio clamped, code reused
ELSE
    fRaWEff := fRaHumRatio;              // 合法回风含湿量原值生效 / Valid return humidity ratio applied as-is
END_IF
IF fOaHumRatio < 0.0 THEN
    fOaWEff := 0.0;                      // 新风含湿量负值钳 0（物理下界） / Negative outdoor humidity ratio clamped to zero
    eErr := 16#0002_3101;                // 信息级：含湿量已钳位复用（R90） / Info: humidity ratio clamped, code reused
ELSE
    fOaWEff := fOaHumRatio;              // 合法新风含湿量原值生效 / Valid outdoor humidity ratio applied as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜质量守恒加权主体：干球与含湿量分别按新风比加权
 *      Mass-conservation weighting for temperature and humidity ratio
 *-----------------------------------------------------------------------------*)
fMixTempC := fFracEff * fOaTempC + (1.0 - fFracEff) * fRaTempC; // 混合干球温度 [摄氏度] / Mixed dry-bulb temperature [degC]
fMixHumRatio := fFracEff * fOaWEff + (1.0 - fFracEff) * fRaWEff; // 混合含湿量 [kg 水蒸气/kg 干空气] / Mixed humidity ratio [kg/kg dry air]

(*------------------------------------------------------------------------------
 * 段 5｜混合焓内联复算（依赖收窄，见头注释段）：h = 1.006·T + W·(2501 + 1.86·T)
 *      Inline enthalpy per the dependency-narrowing declaration
 *-----------------------------------------------------------------------------*)
fMixEnthalpy := DL_MIX_CP_DRY * fMixTempC + fMixHumRatio * (DL_MIX_HFG0 + DL_MIX_CP_VAP * fMixTempC); // 混合比焓 [kJ/kg 干空气] / Mixed specific enthalpy [kJ/kg dry air]

(*------------------------------------------------------------------------------
 * 段 6｜结露判据：p_v_mix > p_ws(T_mix) 即越过饱和线（与 Magnus 反解温度
 *       比较法等价，免内联反解公式，饱和压取自族属主件）
 *       Condensation criterion via pressure comparison, owner FC sourced
 *-----------------------------------------------------------------------------*)
fDenom := DL_MIX_MW + fMixHumRatio;      // 分压反算分母 [kg/kg]，W >= 0 时恒 >= 0.622，仍强制闸 / Denominator, always >= 0.622 for W >= 0, still gated
IF fDenom <= DL_MIX_EPS THEN
    eErr   := 16#0002_3110;              // 故障级：分母退化复用非有限码（R90） / Fault: degenerate denominator, code reused
    bError := TRUE;                      // 置故障标志 / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF
fPvMix := fMixHumRatio * fPress / fDenom; // 混合点水汽分压 [Pa] / Mixed vapor partial pressure [Pa]
IF (NOT FC_DL_VaporPressureSat(fTempC := fMixTempC, fPvSat => fPwsMix, bValid => _bPwsValid, bClamped => _bPwsClamped, eErr => _nPwsErr, bError => _bPwsError)) OR (NOT _bPwsValid) THEN
    eErr   := 16#0002_3110;              // 故障级：属主件拒绝复用（R90） / Fault: owner FC rejected, code reused
    bError := TRUE;                      // 置故障标志 / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF
bCondensation := (fPvMix > fPwsMix);     // 结露预警（工况事实，不置故障） / Condensation warning, an operating fact, not a fault

bValid := TRUE;                          // 输出可用 / Outputs usable
FC_DL_MixAirStateCalc := TRUE;           // 返回 TRUE = 计算有效 / Return TRUE = computation valid
END_FUNCTION
