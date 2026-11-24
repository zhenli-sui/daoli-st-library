//==============================================================================
// 函数：FC_DL_SoundSpeedAirCalc ｜ 中文名称：空气声速（温度/湿度函数）计算
// 所属子库：DL_MathData ｜ 版本：v1.0.0 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅标准库
//       + 库内 FC_DL_VaporPressureSat）
// 功能描述：湿空气声速理想气体混合口径：干空气基准
//           c_dry = SQRT(1.4·287.05287·T_K)，湿度修正用混合摩尔质量法：
//           水汽摩尔分数 x_w = RH/100·p_ws(T)/p（饱和压取自族属主
//           FC_DL_VaporPressureSat，零内联 Magnus 常数），混合摩尔质量
//           M_mix = M_dry − x_w·(M_dry − M_w)，c = SQRT(γ·R_u·T_K/M_mix)。
//           简化声明：γ 固定取干空气值 1.4（湿空气 γ 略低，本简化使结果
//           偏保守偏低，超声流量/料位计前置换算用途可接受）。
// 开源溯源 (Origin)：原创实现（t1-2-oscat-building 建筑环境语义深化，公开
//           物理公式，零外部源码行，clean-room 独立编写）
// 公开接口清单：输入 fTempC / fRhPct / fPressPa；输出 fSoundSpeed / bValid
// 错误码表：纯函数无状态机码轨；无效输入经 bValid = FALSE 表达（哨兵返回
//           0.0），本件不占用 16#0001 段码位（邻件免让位）
// 状态机：N/A（纯函数，无状态，可重入）
// 边界行为：① 温度域 [-40, 60] °C、湿度域 [0, 100] %、总压域 [50000, 110000]
//           Pa，域外拒绝不外推；② 非有限输入 → 哨兵 0.0 返回；
//           ③ 委托属主件失败（含 bValid 回执，R72 口径）→ 哨兵 0.0 返回；
//           ④ M_mix 分母恒正（物理保证）仍做容差闸（防纪律豁免）。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 2 · 序 9）
//==============================================================================

(*------------------------------------------------------------------------------
 * 调用示例：fC := FC_DL_SoundSpeedAirCalc(fTempC := 25.0, fRhPct := 60.0,
 *                                         fPressPa := 101325.0,
 *                                         fSoundSpeed => fV, bValid => bOk);
 * 注意：仅当 bValid = TRUE 时结果可进入超声仪表换算判据。
 *-----------------------------------------------------------------------------*)
FUNCTION FC_DL_SoundSpeedAirCalc : BOOL
VAR_INPUT
    fTempC    : LREAL;                 // 干球温度 [摄氏度]，域 -40..60 / Dry-bulb temperature [degC]
    fRhPct    : LREAL;                 // 相对湿度 [百分数]，域 0..100 / Relative humidity [percent]
    fPressPa  : LREAL;                 // 大气总压 [帕]，域 50000..110000 / Total pressure [Pa]
END_VAR
VAR_OUTPUT
    fSoundSpeed : LREAL;               // 空气声速 [米每秒] / Sound speed in air [m per s]
    bValid      : BOOL;                // 输出可用标志 / Outputs usable flag
    bClamped    : BOOL;                // 湿度输入越域已钳位声明（信息级，不置故障）/ RH clamped declaration, info level
END_VAR
VAR
    fTk       : LREAL;                 // 绝对温度 [开尔文] / Absolute temperature [K]
    fPwsPa    : LREAL;                 // 饱和水汽压 [帕]，属主件取得 / Saturation vapor pressure [Pa], from the owner FC
    bPwsValid : BOOL;                  // 属主件输出可用回执（R72 口径）/ Owner outputs-usable receipt, R72 style
    _bPwsClamped : BOOL;    // 属主件钳位回执（本件不消费，仅契约全回执） / Owner clamp receipt (unused, full-receipt contract)
    _nPwsErr     : UDINT;   // 属主件错误码回执 / Owner error-code receipt
    _bPwsError   : BOOL;    // 属主件故障级回执 / Owner fault-flag receipt
    fXw       : LREAL;                 // 水汽摩尔分数 [1] / Vapor mole fraction [1]
    fMixM     : LREAL;                 // 混合摩尔质量 [克每摩尔] / Mixture molar mass [g per mol]
END_VAR
VAR CONSTANT
    DL_SS_TMIN  : LREAL := -40.0;      // 温度有效下限 [摄氏度] / Temperature valid floor [degC]
    DL_SS_TMAX  : LREAL := 60.0;       // 温度有效上限 [摄氏度] / Temperature valid ceiling [degC]
    DL_SS_RHMAX : LREAL := 100.0;      // 湿度钳位上限 [百分数] / RH clamp ceiling [percent]
    DL_SS_PMIN  : LREAL := 50000.0;    // 总压有效下限 [帕] / Pressure valid floor [Pa]
    DL_SS_PMAX  : LREAL := 110000.0;   // 总压有效上限 [帕] / Pressure valid ceiling [Pa]
    DL_SS_GAMMA : LREAL := 1.4;        // 干空气比热比 [1]（简化口径声明）/ Dry-air heat ratio [1], simplified per header
    DL_SS_RU    : LREAL := 8.31446;    // 通用气体常数 [焦每摩尔每开尔文] / Universal gas constant [J per mol per K]
    DL_SS_MDRY  : LREAL := 28.9654;    // 干空气摩尔质量 [克每摩尔] / Dry-air molar mass [g per mol]
    DL_SS_MW    : LREAL := 18.01528;   // 水汽摩尔质量 [克每摩尔] / Water vapor molar mass [g per mol]
    DL_SS_EPS   : LREAL := 1.0E-6;     // 浮点容差与分母闸 / Float tolerance and denominator gate
    DL_SS_INF   : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_SS_ZERO  : LREAL := 0.0;        // 无效哨兵输出值 / Sentinel output for invalid
END_VAR

// ---- 段 1｜出口默认值（纯函数无实例，无定时器/沿刷新义务）----
fSoundSpeed := DL_SS_ZERO;            // 声速哨兵零 / Sound speed sentinel zero
bValid := FALSE;                      // 缺省无效 / Invalid by default
bClamped := FALSE;                    // 钳位声明默认 FALSE / Clamped flag preset FALSE

// ---- 段 2｜输入防御：非有限值（NaN 自反判 + Inf 幅值判，R79）----
IF (fTempC <> fTempC) OR (ABS(fTempC) > DL_SS_INF)
   OR (fRhPct <> fRhPct) OR (ABS(fRhPct) > DL_SS_INF)
   OR (fPressPa <> fPressPa) OR (ABS(fPressPa) > DL_SS_INF) THEN
    FC_DL_SoundSpeedAirCalc := FALSE; // 返回无效 / Return invalid
    RETURN;                           // 哨兵零已预置（结构早退）/ sentinel preset, early exit
END_IF

// ---- 段 3｜域闸：温度/总压拒绝不外推；湿度越域钳位照算（信息级声明）----
IF (fTempC < DL_SS_TMIN) OR (fTempC > DL_SS_TMAX)
   OR (fPressPa < DL_SS_PMIN) OR (fPressPa > DL_SS_PMAX) THEN
    FC_DL_SoundSpeedAirCalc := FALSE; // 域外拒绝 / Out of range, refused
    RETURN;                           // 结构早退 / early exit
END_IF
IF (fRhPct < 0.0) OR (fRhPct > DL_SS_RHMAX) THEN
    fRhPct   := MIN(MAX(fRhPct, 0.0), DL_SS_RHMAX); // 湿度双侧钳位 / Two-sided RH clamp
    bClamped := TRUE;                 // 钳位声明置位 / Clamped flag raised
END_IF

// ---- 段 4｜饱和压委托族属主（含 bValid 回执，R72 口径；零内联 Magnus）----
IF NOT FC_DL_VaporPressureSat(fTempC := fTempC, fPvSat => fPwsPa, bClamped => _bPwsClamped,
                             eErr => _nPwsErr, bError => _bPwsError, bValid => bPwsValid) OR NOT bPwsValid THEN
    FC_DL_SoundSpeedAirCalc := FALSE; // 属主拒绝即本件拒绝 / Owner rejection propagates
    RETURN;                           // 结构早退（哨兵零已预置）/ early exit, sentinel preset
END_IF

// ---- 段 5｜声速主体：摩尔分数 → 混合摩尔质量 → 理想气体声速 ----
fTk := fTempC + 273.15;               // 摄氏度转开尔文 [开尔文] / Celsius to Kelvin [K]
fXw := (fRhPct / 100.0) * fPwsPa / fPressPa; // 水汽摩尔分数 [1] / Vapor mole fraction [1]
fXw := MIN(fXw, 1.0);                 // 摩尔分数物理上界钳位（饱和压越总压防护）/ Mole fraction clamped to 1.0
fMixM := DL_SS_MDRY - fXw * (DL_SS_MDRY - DL_SS_MW); // 混合摩尔质量 [克每摩尔] / Mixture molar mass [g per mol]
IF fMixM <= DL_SS_EPS THEN
    FC_DL_SoundSpeedAirCalc := FALSE; // 分母退化拒绝（物理上恒正，仍强制闸）/ Degenerate denominator, refused
    RETURN;                           // 结构早退 / early exit
END_IF
fSoundSpeed := SQRT(DL_SS_GAMMA * DL_SS_RU * fTk * 1000.0 / fMixM); // 声速 [米每秒]，克→千克单位换算 / Sound speed [m per s], gram to kg scale
bValid := TRUE;                       // 全部防御通过：输出可用 / Outputs usable
FC_DL_SoundSpeedAirCalc := TRUE;      // 返回 TRUE = 计算有效 / Return TRUE = computation valid
END_FUNCTION
