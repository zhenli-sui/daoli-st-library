(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FilmTensionDancer
 * 所属子库 (Sublibrary) : DL_Process
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准库 TON / F_TRIG / R_TRIG / ABS / MAX / MIN，
 *                         零厂商方言
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 张力摆辊控制公开工艺语义（行业池，放/收卷双工位），
 *                         分层思想借鉴本库 WindingTensionCtrl（零代码复制），
 *                         道莅 clean-room 防御性实现，未复制任何外部源码行
 * 功能描述 (Function)   : 张力摆辊控制双工位切换件。摆辊中位偏差经 PI 修正
 *                         速度微调 fSpdTrim（放/收卷作用方向由 eSide 归一
 *                         集中一处防符号错）；转矩给定 fTrqSet 为锥度张力
 *                         给定（规格式 fTensionSet·卷径比）；断料失效沿
 *                         冻结输出回中；摆辊超行程持续确认锁故障。
 * 职责边界 (Boundary)   : 与库内 WindingTensionCtrl 分工——该件为张力传感器
 *                         直接闭环，本件为摆辊位移反馈间接闭环，二者分层
 *                         思想一致、实现不合并。
 * 状态机   (States)     : eIdle/eCentering/eActive/eWebBreak/eFault，
 *                         CASE 带 ELSE 锁安全侧（输出回中）。
 * 码位     (Codes)      : 16#0005_00BC 信息级：输入非有限冻结评估、断料冻结
 *                                      回中（不置 bError）
 *                         16#0005_00BD 故障级：摆辊超行程（锁存）
 *                         16#0005_00BE 故障级：状态非法（ELSE 兜底，锁存）
 *                         16#0005_00BF~00C0 保留未启用（码表与实现对齐）
 * 边界防错 (Boundary)   : 1 卷径非有限或不大于零冻结锥度输出（保持末次有效值）；
 *                         2 PI 积分带反算限幅（限幅处反算 anti-windup）；
 *                         3 F_TRIG/R_TRIG/TON 实例每拍无条件刷新；
 *                         4 CASE 带 ELSE 锁安全侧；
 *                         5 故障锁存可达解除路径：撤使能回待机清码；
 *                         6 作用方向归一集中一处，符号错风险单点化。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 18）
 *                         2026-11-18 v1.0.1 R31 终审修复：超行程判定改接
 *                         tonOvt.Q（tOvtConf 持续确认生效）；待机补清积分
 *==============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_WindSide（归属本功能块，同文件发布，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_WindSide :
(
    eUnwind := 0,     // 放卷侧 / Unwind side
    eRewind := 10     // 收卷侧 / Rewind side
);
END_TYPE

(*------------------------------------------------------------------------------
 * 枚举: E_DL_DancerState（归属本功能块，同文件发布，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DancerState :
(
    eIdle      := 0,   // 待机：输出回中 / Idle, output centered
    eCentering := 10,  // 找中态：使能后回摆辊中位 / Centering, returning to dancer centre
    eActive    := 20,  // 活动态：PI 闭环修正 / Active, PI closed-loop correcting
    eWebBreak  := 30,  // 断料态：冻结输出回中 / Web break, output frozen to centre
    eFault     := 99   // 故障：超行程锁定 / Fault, overtravel latched
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_FilmTensionDancer
 * 调用约定: 每个扫描周期无条件调用一次；卷径由调用方用库内
 *           FC_DL_CoilDiameterCalc 预算后经引脚注入。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_FilmTensionDancer
VAR_INPUT
    fDancerPos : REAL := 50.0;        // 摆辊位置 [百分数，50 为中位] / Dancer position [%], 50 = centre
    fTensionSet: REAL := 50.0;        // 张力设定 [牛] / Tension setpoint [N]
    fRollD     : REAL := 200.0;      // 当前卷径 [毫米]（外部注入）/ Current roll diameter [mm], injected
    fRoll0     : REAL := 200.0;      // 锥度基准卷径 [毫米]（可增引脚）/ Taper reference diameter [mm], added pin
    eSide      : E_DL_WindSide;      // 工位侧别（放/收卷）/ Winding side selector
    bWeb       : BOOL := FALSE;      // 有料信号 / Web presence signal
    bEn        : BOOL := FALSE;      // 使能 / Enable flag
    fKp        : REAL := 2.0;        // 比例增益 [微调百分数每百分数] / Proportional gain
    fTi        : REAL := 2.0;        // 积分时间 [秒] / Integral time [s]
    fTrimMin   : REAL := -50.0;      // 速度微调下限 [百分数] / Speed trim lower limit [%]
    fTrimMax   : REAL := 50.0;       // 速度微调上限 [百分数] / Speed trim upper limit [%]
    fPosLo     : REAL := 5.0;        // 摆辊行程下限 [百分数]（可增引脚）/ Dancer travel lower [%], added pin
    fPosHi     : REAL := 95.0;       // 摆辊行程上限 [百分数]（可增引脚）/ Dancer travel upper [%], added pin
    tSample    : TIME := T#10MS;     // 采样周期 [毫秒]（可增引脚）/ Sample period [ms], added pin
    tOvtConf   : TIME := T#1S;       // 超行程确认时长 [毫秒]（可增引脚）/ Overtravel confirm [ms], added pin
END_VAR
VAR_OUTPUT
    fSpdTrim : REAL;                  // 速度微调输出 [百分数] / Speed trim output [%]
    fTrqSet  : REAL;                  // 锥度张力给定（规格式卷径比折算）/ Taper tension reference
    eState   : E_DL_DancerState;      // 控制状态 / Control state
    bError   : BOOL;                  // 故障标志，与故障级码配对（R45）/ Fault flag paired with fault codes
    uErrorId : UDINT;                 // 错误码，0 = 无错 / Error code, 0 = none
END_VAR
VAR
    rTrigEn  : R_TRIG;                // 使能沿检测，每拍无条件刷新 / Enable edge detector, refreshed every scan
    fTrigWeb : F_TRIG;                // 有料下降沿检测，每拍无条件刷新 / Web falling edge detector
    tonOvt   : TON;                   // 超行程确认计时，每拍无条件刷新 / Overtravel confirm timer
    fErr     : REAL;                  // 中位偏差 [百分数] / Centre deviation [%]
    fDirErr  : REAL;                  // 侧别归一后偏差 [百分数] / Side-normalised deviation [%]
    fDir     : REAL;                  // 作用方向系数 [+1 或 -1] / Acting direction factor
    fP       : REAL;                  // 比例项 [百分数] / Proportional term [%]
    fInteg   : REAL;                  // 积分项 [百分数] / Integral term [%]
    fDtSec   : REAL;                  // 采样周期 [秒] / Sample period [s]
    fTaper   : REAL;                  // 卷径比暂存 [1] / Diameter ratio staging [1]
    bRollOk  : BOOL;                  // 卷径有效 / Roll diameter validity
    bPosOk   : BOOL;                  // 摆辊位置有效 / Dancer position validity
    bSetOk   : BOOL;                  // 张力设定有效 / Tension setpoint validity
    bOvtNow  : BOOL;                  // 本拍超行程 / Overtravel this scan
    uCodeLatch: UDINT;                // 故障级锁存码 / Latched fault code
END_VAR
VAR CONSTANT
    DL_FTD_FIN  : REAL := 1.0E30;     // REAL 有限幅值判界 / REAL finiteness magnitude bound
    DL_FTD_EPS  : REAL := 1.0E-6;     // 积分时间防除零容差 [秒] / Integral time divide guard [s]
    DL_FTD_DCR  : REAL := 50.0;       // 摆辊中位 [百分数] / Dancer centre [%]
END_VAR

// ---- 段 1｜边沿与定时器实例无条件周期刷新（红线：禁入条件分支）----------------
rTrigEn(CLK := bEn);                                  // 使能沿检测 / Enable edge detection
fTrigWeb(CLK := bWeb);                                // 有料下降沿检测 / Web falling edge detection
tonOvt(IN := bOvtNow, PT := tOvtConf);                // 超行程确认计时 / Overtravel confirm timing

// ---- 段 2｜输入有效性与方向归一（作用方向集中一处防符号错）----------------------
bPosOk := (fDancerPos = fDancerPos) AND (ABS(fDancerPos) < DL_FTD_FIN); // 位置有限 / Position finite
bSetOk := (fTensionSet = fTensionSet) AND (fTensionSet >= 0.0) AND (ABS(fTensionSet) < DL_FTD_FIN); // 设定有限非负 / Setpoint finite non-negative
bRollOk := (fRollD = fRollD) AND (fRollD > 0.0) AND (fRollD < DL_FTD_FIN)
       AND (fRoll0 = fRoll0) AND (fRoll0 > 0.0) AND (fRoll0 < DL_FTD_FIN); // 双卷径有效 / Both diameters valid
IF eSide = eUnwind THEN
    fDir := 1.0;                                      // 放卷侧方向系数（归一单点）/ Unwind direction factor
ELSE
    fDir := -1.0;                                     // 收卷侧方向系数（归一单点）/ Rewind direction factor
END_IF

// ---- 段 3｜超行程判据 ------------------------------------------------------------
bOvtNow := bPosOk AND bEn AND ((fDancerPos < fPosLo) OR (fDancerPos > fPosHi)); // 超行程瞬时判定 / Instant overtravel

// ---- 段 4｜状态机（CASE 带 ELSE 锁安全侧：输出回中）------------------------------
CASE eState OF
    eIdle:
        fSpdTrim := 0.0;                              // 待机输出回中 / Idle centres output
        fInteg := 0.0;                                // 待机清积分防复投冲击（R28 终审）/ Idle clears integral against bump
        IF rTrigEn.Q AND bWeb AND bPosOk THEN
            eState := eCentering;                     // 使能且有料进找中 / Enabled with web, centering
        END_IF
    eCentering:
        fErr := fDancerPos - DL_FTD_DCR;              // 中位偏差 / Centre deviation
        IF fTrigWeb.Q OR (NOT bWeb) OR (NOT bPosOk) THEN
            eState := eWebBreak;                      // 断料或数据无效进冻结态 / Web loss or bad data, freeze
        ELSIF tonOvt.Q THEN
            eState := eFault;                         // 超行程持续确认满锁故障 / Overtravel confirmed latches fault
            uCodeLatch := 16#0005_00BD;               // 码位：超行程 / Code: overtravel
        ELSIF ABS(fErr) < 1.0 THEN
            eState := eActive;                        // 回中带内转活动态 / Within band, active
        ELSE
            fSpdTrim := MAX(fTrimMin, MIN(fTrimMax, -fDir * fErr)); // 找中粗调（方向归一）/ Coarse centring, normalised
        END_IF
    eActive:
        IF (NOT bWeb) OR (NOT bPosOk) OR (NOT bSetOk) THEN
            eState := eWebBreak;                      // 断料或数据无效进冻结态 / Web loss or bad data, freeze
        ELSIF tonOvt.Q THEN
            eState := eFault;                         // 超行程持续确认满锁故障 / Overtravel confirmed latches fault
            uCodeLatch := 16#0005_00BD;               // 码位：超行程 / Code: overtravel
        ELSE
            fErr := fDancerPos - DL_FTD_DCR;          // 中位偏差 / Centre deviation
            fDirErr := fDir * fErr;                   // 侧别归一偏差 / Side-normalised deviation
            fP := fKp * fDirErr;                      // 比例项 / Proportional term
            fDtSec := MAX(TIME_TO_REAL(tSample) / 1000.0, DL_FTD_EPS); // 采样秒防除零 / Sample seconds with divide guard
            fSpdTrim := fP + fInteg;                  // PI 合成 / PI composition
            fSpdTrim := MAX(fTrimMin, MIN(fTrimMax, fSpdTrim)); // 输出限幅 / Output clamping
            fInteg := fInteg + (fKp / MAX(fTi, DL_FTD_EPS)) * fDirErr * fDtSec; // 积分递推 / Integral recursion
            fInteg := MAX(fTrimMin - fP, MIN(fTrimMax - fP, fInteg)); // 反算限幅处 anti-windup / Back-calc anti-windup at clamp
        END_IF
    eWebBreak:
        fSpdTrim := 0.0;                              // 断料冻结输出回中 / Web break freezes to centre
        fInteg := 0.0;                                // 清积分防复卷冲击 / Clear integral against bump
        IF bWeb AND bPosOk THEN
            eState := eCentering;                     // 复卷重新找中 / Web back, re-center
        END_IF
    eFault:
        fSpdTrim := 0.0;                              // 故障安全侧回中 / Fault safe side centre
        IF NOT bEn THEN
            eState := eIdle;                          // 可达解除路径：撤使能回待机 / Reachable release: disable
            uCodeLatch := 16#0000_0000;               // 清锁存码 / Clear latched code
        END_IF
    ELSE
        eState := eFault;                             // 非法状态兜底 / Illegal state fallback
        uCodeLatch := 16#0005_00BE;                   // 码位：状态非法 / Code: illegal state
        fSpdTrim := 0.0;                              // 兜底回中（安全侧）/ Fallback centre
END_CASE

// ---- 段 5｜锥度张力给定（规格式，卷径无效冻结保持末次有效值）---------------------
IF bRollOk AND bSetOk THEN
    fTaper := fRollD / fRoll0;                        // 卷径比 [1] / Diameter ratio
    fTrqSet := fTensionSet * fTaper;                  // 锥度给定（规格式）/ Taper reference per spec
END_IF                                                // 卷径无效冻结保持 / Invalid diameter freezes output

// ---- 段 6｜撤使能清输出 ----------------------------------------------------------
IF NOT bEn THEN
    fSpdTrim := 0.0;                                  // 非使能回中 / Disabled centres output
END_IF

// ---- 段 7｜错误码装配：故障锁存回放优先，信息级居次 ------------------------------
IF eState = eFault THEN
    bError   := TRUE;                                 // 故障标志配对（R45）/ Fault flag paired
    uErrorId := uCodeLatch;                           // 故障码锁存回放 / Latched fault code replayed
ELSIF (NOT bRollOk) OR (NOT bPosOk) OR (NOT bSetOk) OR (eState = eWebBreak) THEN
    bError   := FALSE;                                // 信息级不置故障 / Info never sets fault
    uErrorId := 16#0005_00BC;                         // 信息级：非有限/断料冻结 / Info: non-finite or web break
ELSE
    bError   := FALSE;                                // 无错清标志 / Clear fault flag
    uErrorId := 16#0000_0000;                         // 无码 / No code
END_IF
END_FUNCTION_BLOCK
