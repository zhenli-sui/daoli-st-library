(*==============================================================================
 * 组件名称 (Component)  : FB_DL_VfdThermalDerate
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（LBP 驱动参数化族深化）
 * 所属子库 (Sublibrary) : DL_Device / DriveProtect
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），零标准库依赖
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 变频器热/海拔双因素降容
 * 功能一句话 (Summary)  : 散热器温度与海拔两段线性降容，取小者，恢复带迟滞。
 * 边界与安全 (Boundary) : ①双因素系数取小者（最严约束优先）；
 *                         ②温度恢复带迟滞 2 ℃（防抖，规格口径）；
 *                         ③NaN 输入保持上次系数并置对应非法码；
 *                         ④系数越界钳 [0,1] 并置钳界码；
 *                         ⑤启动阈值大于等于满降阈值时该因素恒 0 防御
 *                           （参数倒置按钳界码拦截）。
 * 错误码    : 16#0003_0384 温度输入非法（NaN 或低于绝对零界）——故障级（单拍）
 *             16#0003_0385 海拔输入非法（NaN 或负值）——故障级（单拍）
 *             16#0003_0386 降容系数钳界发生（含参数倒置拦截）——故障级（单拍）
 * 码位总账  : 16#0003_0384 用 / 16#0003_0385 用 / 16#0003_0386 用
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_VfdThermalDerate
VAR_INPUT
    fHeatsinkTemp    : LREAL; // 散热器温度 [℃] / Heatsink temperature [degC]
    fAltitude        : LREAL; // 安装海拔 [m] / Installation altitude [m]
    fTempDerateStart : LREAL; // 温度降容起始 [℃]，默认 60 / Derate start temperature [degC]
    fTempDerateFull  : LREAL; // 温度满降容 [℃]，默认 80 / Full-derate temperature [degC]
    fAltDerateStart  : LREAL; // 海拔降容起始 [m]，默认 1000 / Derate start altitude [m]
    fAltDerateFull   : LREAL; // 海拔满降容 [m]，默认 4000 / Full-derate altitude [m]
END_VAR
VAR_OUTPUT
    fDerateFactor : LREAL; // 综合降容系数 0~1 / Combined derate factor 0 to 1
    bDerateActive : BOOL;  // 降容激活标志 / Derate active flag
    eErr          : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR CONSTANT
    cHysteresis : LREAL := 2.0;   // 温度恢复迟滞 [℃] / Temperature recovery hysteresis [degC]
    cAbsZero    : LREAL := -270.0; // 温度绝对下界 [℃] / Absolute temperature lower bound
END_VAR
VAR
    fTempFactor : LREAL; // 温度因素系数 / Temperature factor
    fAltFactor  : LREAL; // 海拔因素系数 / Altitude factor
    fTempGrd    : LREAL; // 温度守卫副本 / Temperature guard copy
    fAltGrd     : LREAL; // 海拔守卫副本 / Altitude guard copy
    bTempValid  : BOOL;  // 温度输入合法性 / Temperature input validity
    bAltValid   : BOOL;  // 海拔输入合法性 / Altitude input validity
    bTempDerating: BOOL; // 温度因素处于降容态（迟滞锁存）/ Temperature factor derating state
    bClamped    : BOOL;  // 本拍发生钳界 / Clamping occurred this cycle
    fDen        : LREAL; // 段宽临时量 / Span width temp
END_VAR

// ---------- 周期起点：错误码与钳界标志先清 ----------
eErr := 0;
bClamped := FALSE;

// ---------- 输入守卫副本与合法性（NaN 自反判，单拍码） ----------
fTempGrd := fHeatsinkTemp;
fAltGrd  := fAltitude;
bTempValid := (fTempGrd = fTempGrd) AND (fTempGrd >= cAbsZero);
bAltValid  := (fAltGrd = fAltGrd) AND (fAltGrd >= 0.0);
IF NOT bTempValid THEN
    eErr := 16#0003_0384;                     // 温度非法码 / Illegal temperature code
END_IF
IF NOT bAltValid THEN
    eErr := 16#0003_0385;                     // 海拔非法码 / Illegal altitude code
END_IF

// ---------- 温度因素：两段线性 + 迟滞锁存（NaN 保持上次系数） ----------
IF bTempValid THEN
    IF bTempDerating THEN
        IF fTempGrd <= fTempDerateStart - cHysteresis THEN
            bTempDerating := FALSE;           // 回差 2 ℃ 内不翻转，低于回差才退出 / Exit only below hysteresis band
        END_IF
    ELSE
        IF fTempGrd >= fTempDerateStart THEN
            bTempDerating := TRUE;            // 达起始阈值进入降容态 / Enter derating at start threshold
        END_IF
    END_IF
    IF bTempDerating THEN
        fDen := fTempDerateFull - fTempDerateStart;
        IF fDen > 0.0 THEN
            fTempFactor := 1.0 - (fTempGrd - fTempDerateStart) / fDen; // 线性下降 / Linear decay
        ELSE
            fTempFactor := 0.0;               // 参数倒置防御满降 / Inverted params full derate
            bClamped := TRUE;                 // 钳界码 / Clamp code
        END_IF
    ELSE
        fTempFactor := 1.0;                   // 未降容全系数 / Full factor
    END_IF
END_IF

// ---------- 海拔因素：两段线性（NaN 保持上次系数） ----------
IF bAltValid THEN
    IF fAltGrd <= fAltDerateStart THEN
        fAltFactor := 1.0;                    // 起始阈下全系数 / Full factor below start
    ELSE
        fDen := fAltDerateFull - fAltDerateStart;
        IF fDen > 0.0 THEN
            fAltFactor := 1.0 - (fAltGrd - fAltDerateStart) / fDen; // 线性下降 / Linear decay
        ELSE
            fAltFactor := 0.0;                // 参数倒置防御满降 / Inverted params full derate
            bClamped := TRUE;                 // 钳界码 / Clamp code
        END_IF
    END_IF
END_IF

// ---------- 双因素取小 + 系数钳界 [0,1] ----------
IF bTempValid AND bAltValid THEN
    IF fTempFactor < fAltFactor THEN
        fDerateFactor := fTempFactor;         // 取小者 / Take minimum
    ELSE
        fDerateFactor := fAltFactor;
    END_IF
ELSIF bTempValid THEN
    fDerateFactor := fTempFactor;             // 仅温度有效 / Only temperature valid
ELSIF bAltValid THEN
    fDerateFactor := fAltFactor;              // 仅海拔有效 / Only altitude valid
END_IF

IF fDerateFactor > 1.0 THEN
    fDerateFactor := 1.0;                     // 上界钳位 / Clamp upper
    bClamped := TRUE;
END_IF
IF fDerateFactor < 0.0 THEN
    fDerateFactor := 0.0;                     // 下界钳位 / Clamp lower
    bClamped := TRUE;
END_IF
IF bClamped THEN
    eErr := 16#0003_0386;                     // 钳界码（不覆盖更严非法码）/ Clamp code, stricter kept
END_IF

// ---------- 降容激活标志（与系数联动） ----------
bDerateActive := fDerateFactor < 1.0;

END_FUNCTION_BLOCK
