//==============================================================================
// 函数：FC_DL_RhFromDewPoint ｜ 中文名称：露点→相对湿度逆运算原子（焓湿图族拆分④）
// 所属子库：DL_Algo ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：RH = 100·p_ws(Td)/p_ws(T)，纯比值运算；两次调用族属主
//           FC_DL_VaporPressureSat，本件无自带公式常量（零内联公式）。
//           与 FC_DL_DewPointCalc 构成双向对，round-trip 验收向量：
//           DewPoint→Rh→DewPoint 误差 < 1E-3 °C。
// 开源溯源 (Origin)：改写自 OSCAT Building 行为定义（OSCAT 许可，仅行为定义，零代码行）——道莅 clean-room 实现
// 单位表：T[°C] / Td[°C] / RH[%] / p_ws[Pa]
// 错误码表：16#0002_3001 信息级（露点超干球钳 100 或干球温度已钳位，不置
//           bError）/ 16#0002_3010 故障级（露点超干球 > 5 K 传感器矛盾或
//           输入非有限，置 bError）/ 16#0002_3002、16#0002_3011、
//           16#0002_3012 预留禁用（不得挪用）
// 状态机：N/A（纯函数，无状态）
// 边界行为：① Td 略超 T（<= 5 K）→ 过饱和物理矛盾按饱和处理：RH 钳 100 +
//           信息 3001，不置故障（比值语义可安全钳位——与
//           FC_DL_HumidityRatioCalc 的 2E11 故障策略差异：该件分母直接
//           参与除法必须故障保护，本件纯比值无发散风险）；② Td 超干球
//           5 K 以上判传感器矛盾 → 故障 3010、bValid := FALSE；③ 输入
//           非有限 → 故障 3010 复用（R90）；④ 干球温度域外（−40~100 °C
//           外）→ 钳位 + 信息 3001 复用（R90）；⑤ 属主件拒绝 → 故障 3010
//           复用；异常路径输出确定值 0，绝不输出未初始化值。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · T1-2 焓湿图族拆分④ · 双向对闭环）
//==============================================================================

(*------------------------------------------------------------------------------
 * 调用示例：bOk := FC_DL_RhFromDewPoint(fTempC := 25.0, fDewPointC := 16.7,
 *                                       fRh => fRhPct, eErr => uE);
 * round-trip 验收：FC_DL_DewPointCalc(T, Rh) 得 Td 后经本件反解，RH 复现
 * 误差 < 1E-3 百分数；误差超限说明两件口径漂移，应停用并查常量属主。
 *-----------------------------------------------------------------------------*)
FUNCTION FC_DL_RhFromDewPoint : BOOL
VAR_INPUT
    fTempC     : LREAL;                  // 干球温度 [摄氏度]，有效域 -40.0..100.0，域外钳位照算 / Dry-bulb temperature [degC], valid range -40.0..100.0
    fDewPointC : LREAL;                  // 露点温度 [摄氏度] / Dew-point temperature [degC]
END_VAR
VAR_OUTPUT
    fRh        : LREAL;                  // 相对湿度 [百分数]，输出域 0..100 / Relative humidity [percent], output range 0..100
    eErr       : UDINT;                  // 错误码，0 = 无错 / Error code, 0 = no error
    bError     : BOOL;                   // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid     : BOOL;                   // 输出可用标志 / Outputs usable flag
END_VAR
VAR CONSTANT
    DL_RHDP_TMIN     : LREAL := -40.0;   // 干球温度钳位下限 [摄氏度]，对齐族属主有效域 / Dry-bulb clamp floor [degC], aligned with the family owner domain
    DL_RHDP_TMAX     : LREAL := 100.0;   // 干球温度钳位上限 [摄氏度] / Dry-bulb clamp ceiling [degC]
    DL_RHDP_OVERHYST : LREAL := 5.0;     // 传感器矛盾判据阈 [摄氏度]，露点超干球此值即故障 / Sensor contradiction threshold [degC]
    DL_RHDP_INF      : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
END_VAR
VAR
    fTEff    : LREAL;                    // 钳位后的生效干球温度 [摄氏度] / Effective clamped dry-bulb temperature [degC]
    fPwsDb   : LREAL;                    // 干球温度下饱和压 [Pa] / Saturation pressure at the dry bulb [Pa]
    fPwsTd   : LREAL;                    // 露点温度下饱和压 [Pa] / Saturation pressure at the dew point [Pa]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值：入口即赋确定值
 *      Exit defaults: outputs assigned deterministically on entry
 *-----------------------------------------------------------------------------*)
FC_DL_RhFromDewPoint := FALSE;           // 返回值默认无效 / Return value preset invalid
fRh := 0.0;                              // 相对湿度默认置零 / Relative humidity preset to zero
eErr := 16#0000_0000;                    // 错误码先清零 / Error code cleared first
bError := FALSE;                         // 故障标志先清零 / Fault flag cleared first
bValid := FALSE;                         // 可用标志先清零 / Usable flag cleared first

(*------------------------------------------------------------------------------
 * 段 2｜非有限值防御（NaN 用 (x<>x)，Inf 用双侧幅值判，R79）
 *      Non-finite defense per R79
 *-----------------------------------------------------------------------------*)
IF (fTempC <> fTempC) OR (ABS(fTempC) > DL_RHDP_INF)
   OR (fDewPointC <> fDewPointC) OR (ABS(fDewPointC) > DL_RHDP_INF) THEN
    eErr   := 16#0002_3010;              // 故障级：输入非有限复用传感器矛盾码（R90） / Fault: non-finite input, code reused
    bError := TRUE;                      // 置故障标志（R45 配对） / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜干球温度钳位：域外信息级照算（R90 复用 3001）
 *      Dry-bulb clamping, info code reused per R90
 *-----------------------------------------------------------------------------*)
IF (fTempC < DL_RHDP_TMIN) OR (fTempC > DL_RHDP_TMAX) THEN
    fTEff := MIN(MAX(fTempC, DL_RHDP_TMIN), DL_RHDP_TMAX); // 双侧钳位到有效域 / Two-sided clamp into valid range
    eErr := 16#0002_3001;                // 信息级：温度已钳位（不置 bError） / Info: temperature clamped, no fault flag
ELSE
    fTEff := fTempC;                     // 合法温度原值生效 / Valid temperature applied as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜传感器矛盾闸：Td 超干球 5 K 以上 → 故障；略超（<= 5 K）→ 钳 100
 *      先判重故障再判轻矛盾，两级策略次序不可反
 *      Sensor contradiction gate, severe case checked before the mild one
 *-----------------------------------------------------------------------------*)
IF fDewPointC > (fTEff + DL_RHDP_OVERHYST) THEN
    fRh := 0.0;                          // 矛盾输入丢弃，输出确定值 0 / Contradictory input discarded, output zero
    eErr   := 16#0002_3010;              // 故障级：露点超干球 > 5 K，判传感器矛盾 / Fault: dew point exceeds dry bulb by more than 5 K
    bError := TRUE;                      // 置故障标志 / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
ELSIF fDewPointC > fTEff THEN
    fRh := 100.0;                        // 过饱和物理矛盾按饱和处理（比值语义安全钳位） / Supersaturation treated as saturation, safe ratio clamp
    IF eErr = 16#0000_0000 THEN
        eErr := 16#0002_3001;            // 信息级：露点超干球钳 100（不置 bError） / Info: dew point above dry bulb, clamped to 100
    END_IF
    bValid := TRUE;                      // 输出可用（钳位结论可用） / Outputs usable
    FC_DL_RhFromDewPoint := TRUE;        // 返回 TRUE = 计算有效 / Return TRUE = computation valid
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜双向对主体：RH = 100·p_ws(Td)/p_ws(T)，两次调用族属主件
 *      Round-trip core via two owner FC calls, denominator guarded
 *-----------------------------------------------------------------------------*)
IF NOT FC_DL_VaporPressureSat(fTempC := fTEff, fPvSat => fPwsDb) THEN
    eErr   := 16#0002_3010;              // 故障级：属主件拒绝复用（R90） / Fault: owner FC rejected, code reused
    bError := TRUE;                      // 置故障标志 / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF
IF NOT FC_DL_VaporPressureSat(fTempC := fDewPointC, fPvSat => fPwsTd) THEN
    eErr   := 16#0002_3010;              // 故障级：属主件拒绝复用（R90） / Fault: owner FC rejected, code reused
    bError := TRUE;                      // 置故障标志 / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF
IF ABS(fPwsDb) <= 1.0E-6 THEN
    eErr   := 16#0002_3010;              // 故障级：分母退化复用（域内理论上恒正，仍强制闸） / Fault: degenerate denominator, guarded even if theoretically positive
    bError := TRUE;                      // 置故障标志 / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF
fRh := 100.0 * fPwsTd / fPwsDb;          // 相对湿度 [百分数] / Relative humidity [percent]
IF fRh > 100.0 THEN
    fRh := 100.0;                        // 数值越界钳回 100（浮点噪声防护） / Numerical overshoot clamped to 100
END_IF
IF fRh < 0.0 THEN
    fRh := 0.0;                          // 数值越界钳回 0（浮点噪声防护） / Numerical undershoot clamped to 0
END_IF
bValid := TRUE;                          // 输出可用 / Outputs usable
FC_DL_RhFromDewPoint := TRUE;            // 返回 TRUE = 计算有效 / Return TRUE = computation valid
END_FUNCTION
