//==============================================================================
// 函数：FC_DL_HumidityRatioCalc ｜ 中文名称：含湿量计算（焓湿图族拆分②）
// 所属子库：DL_Algo ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：由干球温度 + 露点或相对湿度求含湿量 W = 0.621945·p_v/(p−p_v)
//           [kg 水蒸气/kg 干空气]；p_v 为实际水汽分压。露点模式取
//           p_v = p_ws(Td)（露点即饱和点），相对湿度模式取
//           p_v = RH/100·p_ws(T)。系数 0.621945 为干空气/水蒸气摩尔质量
//           比（ASHRAE Fundamentals 公开公式链 + PsychroLib 语义）。
//           饱和压一律调用族属主 FC_DL_VaporPressureSat，本件零内联公式。
// 开源溯源 (Origin)：改写自 OSCAT Building 行为定义（OSCAT 许可，仅行为定义，零代码行）——道莅 clean-room 实现
// 单位表：T[°C] / Td[°C] / p[Pa] / RH[%] / p_v[Pa] / W[kg 水蒸气/kg 干空气]
// 错误码表：16#0002_2E01 信息级（RH/露点域外已钳位照算，不置 bError）/
//           16#0002_2E10 故障级（大气压非法或输入非有限，置 bError）/
//           16#0002_2E11 故障级（露点>干球等物理矛盾，分母保护，置 bError）/
//           16#0002_2E12 故障级（输入模式枚举非法兜底，置 bError）/
//           16#0002_2E02 预留禁用（不得挪用）
// 状态机：E_DL_RhInputMode（本文件唯一定义，全库唯一属主）：eDewPoint = 0 /
//           eRelativeHumidity = 1；纯计算函数本体无跨拍状态
// 边界行为：① fPress <= 0 → 故障 2E10、bValid := FALSE、W 输出 0；② 任一
//           输入非有限 → 故障 2E10 复用（R90）；③ RH 域外（<0 或 >100）或
//           露点域外（-40~100 °C 外）→ 钳位 + 信息 2E01 + bClamped 照算；
//           ④ p_v >= p（露点 > 干球等物理矛盾）→ 故障 2E11、bValid := FALSE
//           （含湿量分母保护必须故障——与 FC_DL_RhFromDewPoint 的比值钳位
//           策略不同：本件分母直接参与除法，比值件可安全钳 100）；⑤ 枚举
//           非法值走 CASE ELSE 兜底 → 故障 2E12。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · T1-2 焓湿图族拆分②）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_RhInputMode（归属本函数，同文件发布，全库唯一定义）
 * 含义: 第二输入 fRhIn 的解释模式，决定 fRhIn 是露点还是相对湿度。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_RhInputMode :
(
    eDewPoint         := 0,  // fRhIn 解释为露点温度 [摄氏度] / fRhIn interpreted as dew-point temperature [degC]
    eRelativeHumidity := 1   // fRhIn 解释为相对湿度 [百分数] / fRhIn interpreted as relative humidity [percent]
);
END_TYPE

(*------------------------------------------------------------------------------
 * 调用示例：bOk := FC_DL_HumidityRatioCalc(fTempC := 25.0,
 *             eRhMode := E_DL_RhInputMode.eRelativeHumidity,
 *             fRhIn := 60.0, fPress := 101325.0,
 *             fHumRatio => fW, fPv => fVp, eErr => uE);
 * 注意：仅当返回 TRUE 且 eErr = 0 时 W 才可进入联锁/能量平衡运算。
 *-----------------------------------------------------------------------------*)
FUNCTION FC_DL_HumidityRatioCalc : BOOL
VAR_INPUT
    fTempC   : LREAL;                    // 干球温度 [摄氏度] / Dry-bulb temperature [degC]
    eRhMode  : E_DL_RhInputMode;         // 第二输入模式枚举 [—] / Interpretation mode of the second input
    fRhIn    : LREAL;                    // 相对湿度 [百分数] 或露点 [摄氏度]，按 eRhMode 解释 / RH [percent] or dew point [degC], per eRhMode
    fPress   : LREAL := 101325.0;        // 大气压 [Pa]，引脚注入非魔法数 / Atmospheric pressure [Pa], injected via the pin
END_VAR
VAR_OUTPUT
    fHumRatio : LREAL;                   // 含湿量 [kg 水蒸气/kg 干空气] / Humidity ratio [kg vapor per kg dry air]
    fPv       : LREAL;                   // 实际水蒸气分压 [Pa] / Actual vapor partial pressure [Pa]
    bClamped  : BOOL;                    // TRUE = 湿度/露点输入已钳位 / TRUE = humidity or dew-point input clamped
    eErr      : UDINT;                   // 错误码，0 = 无错 / Error code, 0 = no error
    bError    : BOOL;                    // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid    : BOOL;                    // 输出可用标志 / Outputs usable flag
END_VAR
VAR CONSTANT
    DL_HR_MW_RATIO : LREAL := 0.621945;  // 干空气/水蒸气摩尔质量比 [kg/kg]，ASHRAE 口径 / Molar mass ratio dry air to vapor [kg/kg], ASHRAE
    DL_HR_TD_MIN   : LREAL := -40.0;     // 露点输入钳位下限 [摄氏度]，对齐族属主有效域 / Dew-point clamp floor [degC], aligned with the family owner domain
    DL_HR_TD_MAX   : LREAL := 100.0;     // 露点输入钳位上限 [摄氏度] / Dew-point clamp ceiling [degC]
    DL_HR_RH_MIN   : LREAL := 0.0;       // 相对湿度钳位下限 [百分数] / Relative humidity clamp floor [percent]
    DL_HR_RH_MAX   : LREAL := 100.0;     // 相对湿度钳位上限 [百分数] / Relative humidity clamp ceiling [percent]
    DL_HR_EPS      : LREAL := 1.0E-6;    // 浮点判零容差 [Pa] / Float zero tolerance [Pa]
    DL_HR_INF      : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
END_VAR
VAR
    fPwsDb   : LREAL;                    // 干球温度下饱和压 [Pa]，属主件取得 / Saturation pressure at dry bulb [Pa], from the owner FC
    fPwsIn   : LREAL;                    // 第二输入对应饱和压 [Pa] / Saturation pressure of the second input [Pa]
    fRhEff   : LREAL;                    // 钳位后的生效湿度 [百分数] / Effective clamped humidity [percent]
    fTdEff   : LREAL;                    // 钳位后的生效露点 [摄氏度] / Effective clamped dew point [degC]
    fDenom   : LREAL;                    // 含湿量分母 (p − p_v) [Pa] / Humidity ratio denominator [Pa]
    bTdBad   : BOOL;                     // 露点钳位暂存标志 / Staged dew-point clamp flag
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值：入口即赋确定值
 *      Exit defaults: outputs assigned deterministically on entry
 *-----------------------------------------------------------------------------*)
FC_DL_HumidityRatioCalc := FALSE;        // 返回值默认无效 / Return value preset invalid
fHumRatio := 0.0;                        // 含湿量默认置零 / Humidity ratio preset to zero
fPv := 0.0;                              // 水汽分压默认置零 / Vapor pressure preset to zero
bClamped := FALSE;                       // 钳位标志默认 FALSE / Clamped flag preset FALSE
eErr := 16#0000_0000;                    // 错误码先清零 / Error code cleared first
bError := FALSE;                         // 故障标志先清零 / Fault flag cleared first
bValid := FALSE;                         // 可用标志先清零 / Usable flag cleared first
bTdBad := FALSE;                         // 露点钳位暂存清零 / Staged clamp flag cleared

(*------------------------------------------------------------------------------
 * 段 2｜非有限值防御：四个输入全查（含默认注入的大气压）
 *      Non-finite defense on all four inputs including the defaulted pressure
 *-----------------------------------------------------------------------------*)
IF (fTempC <> fTempC) OR (ABS(fTempC) > DL_HR_INF)
   OR (fRhIn <> fRhIn) OR (ABS(fRhIn) > DL_HR_INF)
   OR (fPress <> fPress) OR (ABS(fPress) > DL_HR_INF) THEN
    eErr   := 16#0002_2E10;              // 故障级：输入非有限复用压力非法码（R90） / Fault: non-finite input, code reused
    bError := TRUE;                      // 置故障标志（R45 配对） / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜大气压闸门：p <= 0 物理非法，直接故障（分母保护前置）
 *      Pressure gate: non-positive pressure is physically illegal
 *-----------------------------------------------------------------------------*)
IF fPress <= DL_HR_EPS THEN
    eErr   := 16#0002_2E10;              // 故障级：大气压非法 / Fault: illegal atmospheric pressure
    bError := TRUE;                      // 置故障标志 / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜模式分支：按 eRhMode 解释第二输入，饱和压一律取自族属主件
 *      Mode branch, saturation pressure always from the family owner FC
 *-----------------------------------------------------------------------------*)
CASE eRhMode OF
    E_DL_RhInputMode.eDewPoint:          // 露点模式：p_v = p_ws(Td)，Td 即饱和点
        IF (fRhIn < DL_HR_TD_MIN) OR (fRhIn > DL_HR_TD_MAX) THEN
            fTdEff := MIN(MAX(fRhIn, DL_HR_TD_MIN), DL_HR_TD_MAX); // 露点双侧钳位 / Two-sided dew-point clamp
            bTdBad := TRUE;              // 钳位暂存（信息码在出口统一写，防覆盖） / Staged flag, the info code is written once at the exit
        ELSE
            fTdEff := fRhIn;             // 合法露点原值生效 / Valid dew point applied as-is
        END_IF
        IF NOT FC_DL_VaporPressureSat(fTempC := fTdEff, fPvSat => fPwsIn) THEN
            eErr   := 16#0002_2E12;      // 故障级：属主件拒绝（其故障即本件故障），兜底码 / Fault: owner FC rejected, fallback code
            bError := TRUE;              // 置故障标志 / Raise the fault flag
            bValid := FALSE;             // 输出不可用 / Outputs unusable
            RETURN;
        END_IF
        fPv := fPwsIn;                   // 露点模式分压 = 露点饱和压 [Pa] / Dew-point mode: partial pressure equals saturation at Td

    E_DL_RhInputMode.eRelativeHumidity:  // 相对湿度模式：p_v = RH/100·p_ws(T)
        IF (fRhIn < DL_HR_RH_MIN) OR (fRhIn > DL_HR_RH_MAX) THEN
            fRhEff := MIN(MAX(fRhIn, DL_HR_RH_MIN), DL_HR_RH_MAX); // 湿度双侧钳位 / Two-sided humidity clamp
            bClamped := TRUE;            // 钳位声明置位 / Clamped flag raised
            eErr := 16#0002_2E01;        // 信息级：RH 已钳位（不置 bError） / Info: RH clamped, no fault flag
        ELSE
            fRhEff := fRhIn;             // 合法湿度原值生效 / Valid humidity applied as-is
        END_IF
        IF NOT FC_DL_VaporPressureSat(fTempC := fTempC, fPvSat => fPwsDb) THEN
            eErr   := 16#0002_2E12;      // 故障级：属主件拒绝，兜底码 / Fault: owner FC rejected, fallback code
            bError := TRUE;              // 置故障标志 / Raise the fault flag
            bValid := FALSE;             // 输出不可用 / Outputs unusable
            RETURN;
        END_IF
        fPv := (fRhEff / 100.0) * fPwsDb; // 相对湿度模式分压 [Pa] / RH mode partial pressure [Pa]

    ELSE                                 // 枚举非法值兜底（R21：CASE 必带 ELSE）
        eErr   := 16#0002_2E12;          // 故障级：输入模式枚举非法 / Fault: illegal input-mode enum
        bError := TRUE;                  // 置故障标志 / Raise the fault flag
        bValid := FALSE;                 // 输出不可用 / Outputs unusable
        RETURN;
END_CASE

IF bTdBad THEN
    bClamped := TRUE;                    // 露点钳位声明出口统一置位 / Staged dew-point clamp raised at the exit
    eErr := 16#0002_2E01;                // 信息级：露点已钳位（不置 bError） / Info: dew point clamped, no fault flag
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜物理矛盾与分母保护：p_v >= p 或分母过小 → 故障 2E11
 *      Physical contradiction and denominator guard before the division
 *-----------------------------------------------------------------------------*)
fDenom := fPress - fPv;                  // 含湿量分母 [Pa] / Denominator [Pa]
IF (fPv >= fPress) OR (fDenom <= DL_HR_EPS) THEN
    fHumRatio := 0.0;                    // 矛盾输入丢弃，输出确定值 0 / Contradictory input discarded, output zero
    eErr   := 16#0002_2E11;              // 故障级：露点>干球等物理矛盾 / Fault: physical contradiction such as dew point above dry bulb
    bError := TRUE;                      // 置故障标志 / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜含湿量主体：W = 0.621945·p_v/(p − p_v)，分母已闸
 *      Humidity ratio core, denominator already gated
 *-----------------------------------------------------------------------------*)
fHumRatio := DL_HR_MW_RATIO * fPv / fDenom; // 含湿量 [kg 水蒸气/kg 干空气] / Humidity ratio [kg vapor per kg dry air]
bValid := TRUE;                          // 输出可用 / Outputs usable
FC_DL_HumidityRatioCalc := TRUE;         // 返回 TRUE = 计算有效 / Return TRUE = computation valid
END_FUNCTION
