(*==============================================================================
 * 组件名称 (Component)  : FB_DL_EnthalpyChangeover
 * 所属子库 (Sublibrary) : DL_Process
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准库 TON，零厂商方言
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 空调系统新风/回风焓值优先切换公开控制语义
 *                         （T1-2 ROOM_CONTROL 族行为定义），道莅 clean-room
 *                         防御性实现，未复制任何外部源码行
 * 功能描述 (Function)   : 新风/回风焓值优先模式仲裁件（模式仲裁层）。自动态以
 *                         「新风焓 < 回风焓 − 死区」判新风优先，带回差不对称
 *                         双向判定防振荡；手动态直通锁存；每次切换经最小驻留
 *                         时间抑制频切。与已收口 FB_DL_EnthalpyCompareCtrl
 *                         （单回路执行块）的职责边界：本件只决定用哪路风源，
 *                         不执行风阀/风机动作。
 * 码位     (Codes)      : 16#0005_008F 信息级：焓值非有限保持上次选择、
 *                         fDiffMin 负值钳 0、驻留期切换请求被拒（不置 bError）
 *                         16#0005_0090~0093 故障级保留未启用（本轮无故障级条件，
 *                         码表与实现对齐，不虚声明）
 * 边界防错 (Boundary)   : 1 任一焓值非有限（x<>x 自反判加幅值界）保持上次选择；
 *                         2 fDiffMin<0 钳 0 记信息码；3 首拍初始化为回风（保守侧）；
 *                         4 TON 每拍无条件刷新，驻留重置经单拍断输入实现；
 *                         5 非法枚举走 CASE ELSE 保持现状记信息码。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 3）
 *==============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_ChangeoverMode（归属本功能块，同文件发布，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ChangeoverMode :
(
    eAuto      := 0,    // 自动态：按焓差判据仲裁 / Auto, arbitrate by enthalpy difference
    eManualOA  := 10,   // 手动新风：直通锁存新风侧 / Manual fresh air, direct select
    eManualRA  := 20    // 手动回风：直通锁存回风侧 / Manual return air, direct select
);
END_TYPE

(*------------------------------------------------------------------------------
 * 枚举: E_DL_AirSource（归属本功能块，同文件发布，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_AirSource :
(
    eOA := 0,         // 新风源 / Outside air source
    eRA := 10         // 回风源 / Return air source
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_EnthalpyChangeover
 * 调用约定: 每个扫描周期无条件调用一次；焓值由调用方用 FC_DL_HumidAirEnthalpy
 *           预算后经引脚注入，本件不做焓值计算。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_EnthalpyChangeover
VAR_INPUT
    fEnthOA    : REAL := 0.0;          // 新风焓值 [kJ/kg]，调用方预算注入 / Outside air enthalpy [kJ/kg]
    fEnthRA    : REAL := 0.0;          // 回风焓值 [kJ/kg]，调用方预算注入 / Return air enthalpy [kJ/kg]
    fDiffMin   : REAL := 2.0;          // 新风优先判据死区 [kJ/kg]，负值钳 0 / Minimum benefit deadband [kJ/kg]
    tMinDwell  : TIME := T#120S;       // 切换最小驻留 [ms]，抑制频切 / Minimum dwell time [ms] against hunting
    eMode      : E_DL_ChangeoverMode;  // 运行模式选择 / Operating mode selector
    bEn        : BOOL := FALSE;        // 使能 / Enable flag
END_VAR
VAR_OUTPUT
    eSelect    : E_DL_AirSource;       // 当前风源选择 / Selected air source
    bSwitching : BOOL;                 // 切换进行中单拍脉冲 / Switching pulse, one scan per change
    uErrorId   : UDINT;                // 信息级码，0 = 无信息 / Info code, 0 = none
END_VAR
VAR
    tonDwell   : TON;                  // 最小驻留定时器，每拍无条件刷新 / Dwell timer, refreshed every scan
    bFirstScan : BOOL := TRUE;         // 首扫初始化标志 / First-scan initialisation flag
    bDwellRst  : BOOL;                 // 本拍驻留重置请求（单拍断输入）/ One-scan dwell reset request
    bWantOA    : BOOL;                 // 本拍新风侧请求 / Fresh air request this scan
    bWantRA    : BOOL;                 // 本拍回风侧请求 / Return air request this scan
    bGrant     : BOOL;                 // 本拍请求获准切换 / Request granted this scan
    bFinite    : BOOL;                 // 焓值双端有限标志 / Both enthalpies finite flag
    fDiffEff   : REAL;                 // 钳位后生效死区 [kJ/kg] / Effective clamped deadband [kJ/kg]
    fMargin    : REAL;                 // 回风减新风焓差 [kJ/kg] / Enthalpy margin RA minus OA [kJ/kg]
    bParamClamp: BOOL;                 // 参数钳位信息标志 / Parameter clamp info flag
END_VAR
VAR CONSTANT
    DL_ECO_FIN    : REAL := 1.0E30;    // REAL 有限幅值判界 / REAL finiteness magnitude bound
    DL_ECO_BACK   : REAL := 0.5;       // 不对称回差系数：回切阈 = 死区乘该系数 / Asymmetric hysteresis factor for switching back
END_VAR

// ---- 段 1｜定时器无条件刷新（红线：禁入条件分支）------------------------------
tonDwell(IN := (NOT bDwellRst), PT := tMinDwell);     // 驻留计时，重置拍断输入 / Dwell timing, broken input on reset scan

// ---- 段 2｜首拍初始化为回风（保守侧）------------------------------------------
IF bFirstScan THEN
    eSelect    := eRA;                                // 首拍保守选回风 / Conservative return air on first scan
    bFirstScan := FALSE;                              // 清首扫标志 / Clear first-scan flag
END_IF

// ---- 段 3｜参数与输入有效性 ----------------------------------------------------
bParamClamp := FALSE;                                 // 钳位信息先清 / Clear clamp info
fDiffEff := fDiffMin;                                 // 死区原值 / Deadband as-is
IF fDiffEff < 0.0 THEN
    fDiffEff := 0.0;                                  // 负死区钳 0 / Clamp negative deadband to zero
    bParamClamp := TRUE;                              // 记参数钳位 / Record parameter clamp
END_IF
bFinite := (fEnthOA = fEnthOA) AND (fEnthRA = fEnthRA)
       AND (ABS(fEnthOA) < DL_ECO_FIN) AND (ABS(fEnthRA) < DL_ECO_FIN); // 焓值双端有限 / Both enthalpies finite

// ---- 段 4｜请求生成（非有限与非法模式一律保持现状 + 信息码）--------------------
bWantOA := FALSE;                                     // 请求先清 / Clear requests
bWantRA := FALSE;                                     // 请求先清 / Clear requests
IF NOT bFinite THEN
    uErrorId := 16#0005_008F;                         // 信息级：焓值非有限保持现状 / Info: non-finite, hold selection
ELSIF eMode = eAuto THEN
    fMargin := fEnthRA - fEnthOA;                     // 回风减新风焓差 / Enthalpy margin
    IF (eSelect = eRA) AND (fMargin > fDiffEff) THEN
        bWantOA := TRUE;                              // 进新风：收益须超死区（正向全阈）/ Enter OA only above full deadband
    ELSIF (eSelect = eOA) AND (fMargin < fDiffEff * DL_ECO_BACK) THEN
        bWantRA := TRUE;                              // 退回风：低于半阈即回（不对称回差）/ Back to RA below half threshold
    END_IF
    uErrorId := 16#0000_0000;                         // 自动态正常清码 / Clear code in normal auto
ELSIF eMode = eManualOA THEN
    bWantOA := TRUE;                                  // 手动新风直通 / Manual OA direct
    uErrorId := 16#0000_0000;                         // 手动正常清码 / Clear code in manual
ELSIF eMode = eManualRA THEN
    bWantRA := TRUE;                                  // 手动回风直通 / Manual RA direct
    uErrorId := 16#0000_0000;                         // 手动正常清码 / Clear code in manual
ELSE
    uErrorId := 16#0005_008F;                         // 非法模式兜底保持现状 / Illegal mode fallback, hold
END_IF
IF bParamClamp AND (uErrorId = 16#0000_0000) THEN
    uErrorId := 16#0005_008F;                         // 钳位信息并码（信息级槽合并复用）/ Merge clamp info into info slot
END_IF

// ---- 段 5｜驻留门控与切换执行 --------------------------------------------------
bGrant := FALSE;                                      // 获准标志先清 / Clear grant flag
IF bEn AND (bWantOA <> bWantRA) AND (tonDwell.Q) THEN
    IF bWantOA AND (eSelect = eRA) THEN
        eSelect    := eOA;                            // 切到新风 / Switch to outside air
        bGrant     := TRUE;                           // 本拍获准 / Granted this scan
    ELSIF bWantRA AND (eSelect = eOA) THEN
        eSelect    := eRA;                            // 切到回风 / Switch to return air
        bGrant     := TRUE;                           // 本拍获准 / Granted this scan
    END_IF
ELSIF bEn AND (bWantOA <> bWantRA) AND (NOT tonDwell.Q) THEN
    uErrorId := 16#0005_008F;                         // 信息级：驻留期切换请求被拒 / Info: request rejected in dwell
END_IF
bSwitching := bGrant;                                 // 切换脉冲单拍有效 / One-scan switching pulse
bDwellRst  := bGrant;                                 // 获准拍断驻留输入重置计时 / Break dwell input on granted scan

// ---- 段 6｜非使能保持：不改变选择，仅清切换脉冲 --------------------------------
IF NOT bEn THEN
    bSwitching := FALSE;                              // 非使能清脉冲 / Clear pulse when disabled
END_IF
END_FUNCTION_BLOCK
