(*==============================================================================
 * 组件名称 (Component)  : FB_DL_HydrostaticLevelComp
 * 所属子库 (Sublibrary) : DL_Process
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准库 R_TRIG / ABS / MAX / MIN 与库内
 *                         FC_DL_MultiPointLinear（分段线性插值复用），
 *                         零厂商方言
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 静压式液位计介质密度温补公开工艺语义（行业池），
 *                         道莅 clean-room 防御性实现，未复制任何外部源码行
 * 功能描述 (Function)   : 静压液位介质密度温补件。介质密度由温度-密度标定表
 *                         经库内 FC_DL_MultiPointLinear 分段线性插值得到；
 *                         液位 = (压强 − 干扰管偏移) / (密度 × g)，重力加速度
 *                         g = 9.80665 米每二次方秒常量写死本头注释；表外
 *                         温度最近端点钳位记信息码。密度单位 千克每立方米、
 *                         液位单位 米 必标。
 * 依赖表   (Depends)    : FC_DL_MultiPointLinear（折线插值，IN-OUT 数组注入）。
 * 码位     (Codes)      : 16#0005_00C1 信息级：温度表外钳位照算（不置 bError）
 *                         16#0005_00C2 故障级：密度退化（插值结果不大于
 *                                      1E-6 拒算早退）与输入非有限
 *                         16#0005_00C3 故障级：标定表非单调（锁存）
 *                         16#0005_00C4 故障级：标定表空/点数不足（锁存）
 *                         16#0005_00C5 保留未启用（码表与实现对齐）
 * 边界防错 (Boundary)   : 1 密度不大于 1.0E-6 拒算早退防除零；
 *                         2 非有限全拦（x<>x 自反判加幅值界）；
 *                         3 标定表须严格递增否则组态码锁存；
 *                         4 表点数 0/1 组态非法（故障级锁存）；
 *                         5 故障锁存可达解除路径：bRst 复位沿；
 *                         6 R_TRIG 实例每拍无条件刷新。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 19）
 *==============================================================================*)

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_Pt2（归属本功能块，同文件发布，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE ST_DL_Pt2 :
STRUCT
    fX : REAL := 0.0;   // 折点自变量：温度 [摄氏度] / Breakpoint X: temperature [degC]
    fY : REAL := 0.0;   // 折点因变量：密度 [千克每立方米] / Breakpoint Y: density [kg per m3]
END_STRUCT
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_HydrostaticLevelComp
 * 调用约定: 每个扫描周期无条件调用一次；标定表经引脚数组注入（上限 16 点）。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_HydrostaticLevelComp
VAR_INPUT
    fPMeas  : REAL := 0.0;            // 静压压强实测 [千帕] / Measured hydrostatic pressure [kPa]
    fTCurve : ARRAY[1..16] OF ST_DL_Pt2; // 温度-密度标定表 [摄氏度-千克每立方米] / Temperature-density calibration table
    uPtCnt  : UINT := 16;             // 有效标定点数 [个]，合法域 2..16 / Valid point count, valid 2..16
    fTNow   : REAL := 20.0;           // 介质温度实测 [摄氏度] / Medium temperature [degC]
    fDpOffset: REAL := 0.0;           // 干扰管偏移 [千帕] / Dry-leg offset [kPa]
    bEn     : BOOL := FALSE;          // 使能 / Enable flag
    bRst    : BOOL := FALSE;          // 组态故障复位沿（可增引脚）/ Config fault reset edge, added pin
END_VAR
VAR_OUTPUT
    fLevel  : REAL;                   // 补偿后液位 [米] / Compensated level [m]
    fDensity: REAL;                   // 介质密度 [千克每立方米] / Medium density [kg per m3]
    bValid  : BOOL;                   // 输出可用标志 / Output validity flag
    bError  : BOOL;                   // 故障标志 / Error flag
    uErrorId: UDINT;                  // 错误码，0 = 无错 / Error code, 0 = none
END_VAR
VAR
    rTrigRst: R_TRIG;                 // 复位沿检测，每拍无条件刷新 / Reset edge detector, refreshed every scan
    afX     : ARRAY[0..15] OF LREAL;  // 插值件自变量表 [摄氏度] / Interpolation X table [degC]
    afY     : ARRAY[0..15] OF LREAL;  // 插值件因变量表 [千克每立方米] / Interpolation Y table [kg per m3]
    bClamped: BOOL;                   // 插值钳位标志 / Interpolation clamp flag
    bExtra  : BOOL;                   // 插值外推标志 / Interpolation extrapolation flag
    nSeg    : INT;                    // 插值命中段号 / Interpolation segment index
    uErrMPL : UDINT;                  // 插值件错误码 / Interpolation error code
    nCntEff : INT;                    // 钳位后点数 [个] / Effective point count
    bMonoOk : BOOL;                   // 表单调标志 / Table monotonic flag
    bCntOk  : BOOL;                   // 点数合法标志 / Point count legality flag
    bInOk   : BOOL;                   // 输入有效性 / Input validity flag
    fRhoL   : LREAL;                  // 插值密度（LREAL 域）[千克每立方米] / Interpolated density [kg per m3]
    fNum    : REAL;                   // 液位分子暂存 [千帕] / Level numerator staging [kPa]
    fDen    : REAL;                   // 液位分母暂存 [千帕每米] / Level denominator staging [kPa per m]
    bCfgLatch: BOOL;                  // 组态故障锁存标志 / Config fault latch flag
    uCfgCode: UDINT;                  // 组态锁存码 / Config latched code
    i       : INT;                    // 表装载循环索引 / Table load loop index
    bClampInfo: BOOL;                 // 温度钳位信息 / Temperature clamp info flag
END_VAR
VAR CONSTANT
    DL_HLC_PT_MAX : INT   := 16;      // 标定表点数上限 [个] / Calibration point upper bound
    DL_HLC_FIN    : REAL  := 1.0E30;  // REAL 有限幅值判界 / REAL finiteness magnitude bound
    DL_HLC_G      : REAL  := 9.80665; // 重力加速度常量 [米每二次方秒]，写死头注释 / Gravity constant [m per s2], fixed in header
    DL_HLC_EPS    : REAL  := 1.0E-6;  // 密度拒算下限 [千克每立方米] / Density rejection floor [kg per m3]
    DL_HLC_KPA    : REAL  := 1000.0;  // 千帕到帕换算系数 / kPa to Pa factor
END_VAR

// ---- 段 1｜边沿实例无条件刷新（红线：禁入条件分支）----------------------------
rTrigRst(CLK := bRst);                                // 复位沿检测 / Reset edge detection

// ---- 段 2｜组态校验（点数与单调性），故障锁存带可达复位通道 ----------------------
IF rTrigRst.Q THEN
    bCfgLatch := FALSE;                               // 复位清组态锁存 / Reset clears config latch
    uCfgCode := 16#0000_0000;                         // 清锁存码 / Clear latched code
END_IF
nCntEff := MIN(UINT_TO_INT(uPtCnt), DL_HLC_PT_MAX);   // 点数钳上限 / Clamp point count
bCntOk := (nCntEff >= 2);                             // 点数 0/1 组态非法 / Point count 0 or 1 illegal
bMonoOk := TRUE;                                      // 单调标志预置 / Preset monotonic
IF bCntOk THEN
    FOR i := 1 TO (nCntEff - 1) DO
        IF (fTCurve[i].fX <> fTCurve[i].fX) OR (fTCurve[i + 1].fX <> fTCurve[i + 1].fX)
           OR (fTCurve[i + 1].fX <= fTCurve[i].fX) THEN
            bMonoOk := FALSE;                         // 非严格递增判非单调 / Non-strict increase is non-monotonic
        END_IF
    END_FOR
END_IF
IF bCntOk AND bMonoOk THEN
    bCfgLatch := FALSE;                               // 组态自愈（表改好自动解除）/ Config self-heals
    uCfgCode := 16#0000_0000;                         // 清锁存码 / Clear latched code
ELSE
    IF NOT bCntOk THEN
        uCfgCode := 16#0005_00C4;                     // 码位：表空/点数不足 / Code: table empty
    ELSE
        uCfgCode := 16#0005_00C3;                     // 码位：表非单调 / Code: table non-monotonic
    END_IF
    bCfgLatch := TRUE;                                // 组态故障锁存 / Config fault latched
END_IF

// ---- 段 3｜组态合法时装载插值表并调库内折线件（IN-OUT 数组注入）------------------
bValid := FALSE;                                      // 可用标志先清 / Clear validity
IF bCfgLatch = FALSE THEN
    FOR i := 1 TO nCntEff DO
        afX[i - 1] := REAL_TO_LREAL(fTCurve[i].fX);   // 自变量装载 / Load X table
        afY[i - 1] := REAL_TO_LREAL(fTCurve[i].fY);   // 因变量装载 / Load Y table
    END_FOR
    fRhoL := FC_DL_MultiPointLinear(afX, afY,
             fIn := REAL_TO_LREAL(fTNow), nCount := nCntEff, bClamp := TRUE,
             nSegment => nSeg, bExtrapolated => bExtra, bClamped => bClamped,
             uErrorId => uErrMPL);                    // 库内折线插值取密度 / Library interpolation for density
    fDensity := LREAL_TO_REAL(fRhoL);                 // 密度落地 [千克每立方米] / Density to REAL
    bClampInfo := bClamped;                           // 表外温度钳位信息 / Temperature clamp info
END_IF

// ---- 段 4｜液位换算（非有限全拦，密度下限拒算防除零）----------------------------
bInOk := (fPMeas = fPMeas) AND (fTNow = fTNow) AND (fDpOffset = fDpOffset)
     AND (ABS(fPMeas) < DL_HLC_FIN) AND (ABS(fTNow) < DL_HLC_FIN)
     AND (ABS(fDpOffset) < DL_HLC_FIN);               // 三输入有限 / Three inputs finite
IF bCfgLatch = FALSE THEN
    IF NOT bInOk THEN
        bValid := FALSE;                              // 非有限拒输出 / Non-finite rejects output
        uErrorId := 16#0005_00C2;                     // 故障级：输入非有限 / Fault: non-finite input
    ELSIF fDensity <= DL_HLC_EPS THEN
        bValid := FALSE;                              // 密度退化拒算早退 / Degenerate density rejects
        uErrorId := 16#0005_00C2;                     // 故障级：密度退化 / Fault: density degenerate
    ELSE
        fNum := (fPMeas - fDpOffset) * DL_HLC_KPA;    // 分子换帕 [帕] / Numerator to Pa
        fDen := fDensity * DL_HLC_G / DL_HLC_KPA;     // 分母千帕每米 [千帕每米] / Denominator kPa per m
        fLevel := fNum / fDen;                        // 液位 [米]，分母已验正 / Level [m], denominator verified
        bValid := TRUE;                               // 输出可用 / Output valid
        IF bClampInfo THEN
            uErrorId := 16#0005_00C1;                 // 信息级：温度表外钳位 / Info: temperature clamped
        ELSE
            uErrorId := 16#0000_0000;                 // 无码 / No code
        END_IF
    END_IF
END_IF

// ---- 段 5｜组态锁存回放（故障级配对置位）----------------------------------------
IF bCfgLatch THEN
    bValid  := FALSE;                                 // 组态故障拒输出 / Config fault rejects output
    bError  := TRUE;                                  // 故障标志配对（R45）/ Fault flag paired
    uErrorId := uCfgCode;                             // 锁存码回放 / Latched code replayed
ELSE
    bError := (uErrorId = 16#0005_00C2);              // 仅数值故障级置故障标志 / Only numeric fault sets flag
END_IF
END_FUNCTION_BLOCK
