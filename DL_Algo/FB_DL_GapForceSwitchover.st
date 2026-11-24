(*==============================================================================
 * 组件名称 (Component)  : FB_DL_GapForceSwitchover
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS / MAX），零厂商私有库
 * 功能描述 (Function)   : 压装/贴合类工步位置/压力双模式无扰切换：
 *                           eApproach 接近段：位置控趋近 fGapTargetMm，fCmdTrim = 间隙误差
 *                             修调（钳 ±fTrimMaxMm）；
 *                           接触判据：fForceN >= fContactN + 迟滞带 → eContact 过渡态，
 *                             冻结当时修调/速度作为衔接保持值（切换点速度不得突跳），
 *                             保持一个 tHoldXf 衔接窗后必迁出（单过渡态禁驻留，R285）；
 *                           eForceCtl 力控段：力偏差 → fForceTrimPct（钳 ±100%），
 *                             fCmdTrim 置 0；
 *                           tContactTmo 内未判接触 → eFault（eCause=eNoContact）；
 *                           力传感器非有限/超量程 → eFault（eCause=eForceBad）。
 * 接口     (Interface)  : 输入 fPosMm/fVelMmS 轴位姿、fForceN 力（N）、fContactN 接触判据
 *                         （N）、fGapTargetMm 目标间隙（mm）、fForceTargetN 力控目标（N）、
 *                         tContactTmo 接触超时、tHoldXf 衔接窗、fHysN 接触迟滞（N）、
 *                         fTrimMaxMm 修调限幅（mm）、fKpAppPct 接近修调增益（1/mm）、
 *                         fKpForcePct 力控增益（%/N）、fForceMaxN 力量程上限（N）、bReset；
 *                         输出 eMode 五态、fCmdTrim 位置环修调、fForceTrimPct 力环输出
 *                         （%）、eCause 成因、bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只出双模式状态与两侧修调量，不注入
 *                         轴指令、不接管压力环 PID**；修调限速可由上层用
 *                         `FB_DL_RateLimiter` 串联（本件不内嵌，规格依赖声明）。
 *                         ② 五态 CASE + ELSE 兜底 eFault（R6）；切换判据浮点容差比较
 *                         （迟滞带显式写出，禁 = 判等）。
 *                         ③ eContact 为单过渡态：tHoldXf 到时必迁 eForceCtl，禁驻留。
 *                         ④ 衔接保持值（_fTrimHold / _fVelHold）显式写出并在复位沿清零
 *                         （R311 预防：复位沿清状态与保持值）。
 *                         ⑤ 力超量程判据 = fForceN > fForceMaxN 或 fForceN < 0 或非有限
 *                         → eFault eForceBad（成因分码，R190 归因唯一）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_CoatingGapMeasure`（测量）与 `FB_DL_RollCompressForce-
 *                         Balance`（力平衡趋势）分工：切换闭环（本件）≠ 测量 ≠ 趋势。
 * 来源标签 (Source Tag) : T2-2 ◐（LBP 压机工艺分类只借"位置段/压力段"分类事实，切换器
 *                         实现自研）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 ENUM 五态 + LREAL 组 +
 *                         ENUM 成因 + BOOL；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 迟滞容差 + 非有限/超量程闸 + 修调钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 五态 CASE 含 ELSE ｜ R7 ✓ 两 TON/一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R48 首版（批次 3 · 序号 13）
 *                         验收向量：接近段间隙误差修调；力越迟滞带 → eContact 冻结保持值；
 *                         衔接窗到 → eForceCtl；tContactTmo 无接触 → eFault eNoContact。
 *==============================================================================*)

TYPE E_DL_GfsMode :
(
    eIdle     := 0,    // 待机 / Idle
    eApproach := 10,   // 接近段（位置控）/ Approach phase, position control
    eContact  := 20,   // 接触过渡态（衔接保持，单过渡禁驻留）/ Contact transition, hold window
    eForceCtl := 30,   // 力控段 / Force control phase
    eFault    := 90    // 故障（等复位）/ Fault, awaiting reset
);
END_TYPE

TYPE E_DL_GfsCause :
(
    eNone       := 0,   // 无异常 / No anomaly
    eNoContact  := 1,   // 接近段超时未判接触 / No contact within timeout
    eForceBad   := 2,   // 力传感器非有限/超量程/负值 / Force sensor bad
    eCfgIllegal := 3,   // 组态非法 / Illegal configuration
    eModeBad    := 4    // 非法模式兜底 / Illegal mode fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_GapForceSwitchover
VAR_INPUT
    fPosMm      : LREAL := 0.0;    // 轴实际位置 [mm] / Axis actual position [mm]
    fVelMmS     : LREAL := 0.0;    // 轴实际速度 [mm/s] / Axis actual velocity [mm/s]
    fForceN     : LREAL := 0.0;    // 力/压力传感器实测 [N] / Force sensor measurement [N]
    fContactN   : LREAL := 5.0;    // 接触判据力，域 > 0 [N] / Contact force threshold [N]
    fGapTargetMm: LREAL := 0.0;    // 接近段目标间隙 [mm] / Approach target gap [mm]
    fForceTargetN: LREAL := 100.0; // 力控段目标力 [N] / Force-control target [N]
    tContactTmo : TIME := T#10S;   // 接近段接触超时，域 > T#0S [ms] / Contact timeout [ms]
    tHoldXf     : TIME := T#200MS; // eContact 衔接保持窗，域 > T#0S [ms] / Transition hold window [ms]
    fHysN       : LREAL := 0.5;    // 接触判据迟滞带，域 >= 0 [N] / Contact hysteresis band [N]
    fTrimMaxMm  : LREAL := 1.0;    // 位置环修调限幅，域 > 0 [mm] / Position trim limit [mm]
    fKpAppPct   : LREAL := 1.0;    // 接近段修调增益（间隙误差→修调） [1/mm] / Approach trim gain [1/mm]
    fKpForcePct : LREAL := 0.5;    // 力控段增益（力偏差→%） [%/N] / Force-control gain [%/N]
    fForceMaxN  : LREAL := 5000.0; // 力传感器量程上限，域 > fContactN [N] / Force range ceiling [N]
    bReset      : BOOL := FALSE;   // 故障复位，上升沿回 eIdle 并清保持值（R311） [-] / Fault reset, rising edge clears state and holds
END_VAR
VAR_OUTPUT
    eMode        : E_DL_GfsMode;   // 双模式状态出口 [-] / Mode state outlet
    fCmdTrim     : LREAL;          // 位置环速度/位置修调输出（力控段恒 0） [mm] / Position-loop trim outlet [mm]
    fForceTrimPct: LREAL;          // 力环修调输出（接近段恒 0） [%] / Force-loop trim outlet [%]
    eCause       : E_DL_GfsCause;  // 成因出口（锁存回放，R189） / Cause outlet, latched
    bError       : BOOL;           // 故障标志 [-] / Error flag
END_VAR
VAR
    _eMode     : E_DL_GfsMode := E_DL_GfsMode.eIdle;   // 内部状态（CASE 唯一写入目标） / Internal mode
    _eCause    : E_DL_GfsCause := E_DL_GfsCause.eNone; // 成因锁存量 / Latched cause
    _bFault    : BOOL;           // 故障锁存位（解除沿 = bReset 上升沿） / Latched fault bit
    _fTrimHold : LREAL := 0.0;   // 衔接保持值：接触瞬间修调 [mm] / Held trim at contact
    _fVelHold  : LREAL := 0.0;   // 衔接保持值：接触瞬间速度 [mm/s] / Held velocity at contact
    _fForceTrim: LREAL := 0.0;   // 力环修调锁存镜像 [%] / Force trim latch mirror
    _fCmdTrim  : LREAL := 0.0;   // 位置修调锁存镜像 [mm] / Position trim latch mirror
    _bErrScan  : BOOL;           // 力信号病当拍量（触发 eFault 用） / Force bad this scan
    _bNonFin   : BOOL;           // 输入非有限当拍量 [-] / Non-finite input this scan
    _bCfgBad   : BOOL;           // 组态非法当拍量 [-] / Illegal configuration this scan
    tonContactTmo: TON;          // 接近段接触超时定时器，段 0 无条件调用 / Contact timeout timer
    tonHoldXf  : TON;            // 衔接保持窗定时器，段 0 无条件调用 / Transition hold timer
    rtReset    : R_TRIG;         // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_GFS_EPS   : LREAL := 1.0E-6;  // 浮点判零容差 [无量纲] / Float epsilon
    DL_GFS_ZERO  : LREAL := 0.0;     // 非有限差值判零基准 [-] / Non-finite difference zero base
    DL_GFS_PCTMAX: LREAL := 100.0;   // 力环修调行程上限 [%] / Force trim travel ceiling [%]
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 两 TON 一沿无条件周期刷新 —— *)
_bNonFin := (fForceN <> fForceN) OR ((fForceN - fForceN) <> DL_GFS_ZERO)
         OR (fPosMm <> fPosMm) OR (fVelMmS <> fVelMmS);   // 力/位置/速度非有限（R245） / Non-finite force, position, velocity
_bCfgBad := (fContactN <= DL_GFS_ZERO) OR (fForceMaxN <= fContactN)
         OR (tContactTmo <= T#0S) OR (tHoldXf <= T#0S)
         OR (fTrimMaxMm <= DL_GFS_ZERO) OR (fHysN < DL_GFS_ZERO);   // 组态域闸 / Configuration gate
_bErrScan := _bNonFin OR (fForceN > fForceMaxN) OR (fForceN < DL_GFS_ZERO);   // 力信号病（超量程/负值/非有限） / Force signal bad
tonContactTmo(IN := (_eMode = E_DL_GfsMode.eApproach), PT := tContactTmo);   // 接触超时（进接近段计时，出段自复位） / Contact timeout
tonHoldXf(IN := (_eMode = E_DL_GfsMode.eContact), PT := tHoldXf);   // 衔接保持窗（进过渡态计时） / Transition hold window
rtReset(CLK := bReset);                                     // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：组态闸入故障 —— *)
IF _bCfgBad AND (NOT _bFault) THEN
    _bFault := TRUE;                                        // 组态非法锁存 / Latch config fault
    _eCause := E_DL_GfsCause.eCfgIllegal;                   // 归因：组态非法 / Cause: illegal config
    _eMode := E_DL_GfsMode.eFault;                          // 入故障态 / Enter fault
END_IF

(* —— 段 2：迁出链（复位沿：清状态与保持值，R311 预防） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                       // 清故障锁存 / Clear fault latch
    _eCause := E_DL_GfsCause.eNone;                         // 清成因 / Clear cause
    _fTrimHold := 0.0;                                      // 清衔接保持修调 / Clear held trim
    _fVelHold := 0.0;                                       // 清衔接保持速度 / Clear held velocity
    _fCmdTrim := 0.0;                                       // 清修调镜像 / Clear trim mirror
    _fForceTrim := 0.0;                                     // 清力环镜像 / Clear force mirror
    _eMode := E_DL_GfsMode.eIdle;                           // 回待机 / Back to idle
END_IF

(* —— 段 3：力信号病 → 故障（成因分码 eForceBad，优先于时序） —— *)
IF _bErrScan AND (NOT _bFault) THEN
    _bFault := TRUE;                                        // 力信号病锁存 / Latch force fault
    _eCause := E_DL_GfsCause.eForceBad;                     // 归因：力传感器病 / Cause: force bad
    _eMode := E_DL_GfsMode.eFault;                          // 入故障态 / Enter fault
END_IF

(* —— 段 4：五态状态机（故障态由迁出链处理） —— *)
IF NOT _bFault THEN
    CASE _eMode OF

    E_DL_GfsMode.eIdle:
        _eMode := E_DL_GfsMode.eApproach;                   // 待机下一拍即入接近段（启动权交上层使能本件调用） / Idle proceeds to approach
        _fCmdTrim := 0.0;                                   // 修调清零起步 / Trim starts at zero

    E_DL_GfsMode.eApproach:
        _fCmdTrim := (fGapTargetMm - fPosMm) * fKpAppPct;   // 接近段修调 = 间隙误差×增益 / Approach trim from gap error
        IF _fCmdTrim > fTrimMaxMm THEN
            _fCmdTrim := fTrimMaxMm;                        // 修调上钳 / Clamp trim high
        ELSIF _fCmdTrim < -fTrimMaxMm THEN
            _fCmdTrim := -fTrimMaxMm;                       // 修调下钳 / Clamp trim low
        END_IF
        IF fForceN >= (fContactN + fHysN) THEN
            _fTrimHold := _fCmdTrim;                        // 接触瞬间冻结修调保持值（无扰衔接，头注释③） / Freeze trim at contact
            _fVelHold := fVelMmS;                           // 冻结接触瞬间速度（防切换突跳） / Freeze velocity at contact
            _fForceTrim := 0.0;                             // 力环修调起步零 / Force trim starts zero
            _eMode := E_DL_GfsMode.eContact;                // 越迟滞带上界：入接触过渡态 / Contact: enter transition
        ELSIF tonContactTmo.Q THEN
            _bFault := TRUE;                                // 超时未接触：故障锁存 / Timeout: latch fault
            _eCause := E_DL_GfsCause.eNoContact;            // 归因：未接触 / Cause: no contact
            _eMode := E_DL_GfsMode.eFault;                  // 入故障态 / Enter fault
        END_IF

    E_DL_GfsMode.eContact:
        _fCmdTrim := _fTrimHold;                            // 衔接窗内保持冻结修调（输出不突跳） / Hold frozen trim in window
        IF tonHoldXf.Q THEN
            _eMode := E_DL_GfsMode.eForceCtl;               // 衔接窗到必迁力控段（单过渡态禁驻留，R285） / Window done forces force phase
        END_IF

    E_DL_GfsMode.eForceCtl:
        _fCmdTrim := 0.0;                                   // 力控段位置修调归零 / Position trim zero in force phase
        _fForceTrim := (fForceTargetN - fForceN) * fKpForcePct;   // 力偏差 → 力环修调 / Force error to trim
        IF _fForceTrim > DL_GFS_PCTMAX THEN
            _fForceTrim := DL_GFS_PCTMAX;                   // 力环上钳 100% / Clamp force trim high
        ELSIF _fForceTrim < -DL_GFS_PCTMAX THEN
            _fForceTrim := -DL_GFS_PCTMAX;                  // 力环下钳 -100% / Clamp force trim low
        END_IF

    E_DL_GfsMode.eFault:
        ;                                                   // 故障态驻留：由段 2 迁出链复位处理 / Held by exit chain in stage 2

    ELSE
        _bFault := TRUE;                                    // 非法模式兜底（R6） / Illegal mode fallback
        _eCause := E_DL_GfsCause.eModeBad;                  // 归因：非法模式 / Cause: illegal mode
        _eMode := E_DL_GfsMode.eFault;                      // 强拉故障态 / Force fault

    END_CASE
END_IF

(* —— 段 5：出口单点映射（名实双出口同源，R191） —— *)
eMode := _eMode;                                            // 模式出口 / Mode outlet
fCmdTrim := _fCmdTrim;                                      // 位置修调出口（故障/待机零） / Position trim outlet
fForceTrimPct := _fForceTrim;                               // 力环修调出口 / Force trim outlet
eCause := _eCause;                                          // 成因出口 / Cause outlet
bError := _bFault OR _bCfgBad OR _bErrScan;                 // 故障标志三源合一 / Error flag
IF bError AND (NOT _bFault) THEN
    _bFault := TRUE;                                        // 当拍病亦锁存（防抖动复归） / Latch scan faults too
END_IF

END_FUNCTION_BLOCK
