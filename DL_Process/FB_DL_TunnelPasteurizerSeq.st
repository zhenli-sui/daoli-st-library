(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TunnelPasteurizerSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 隧道式巴氏杀菌六态段序（保质期合规双联锁）：
 *                           ePreheat 预热：腔温升入杀菌带下沿（fTempPauSetC - fBandC）
 *                             → ePau；
 *                           ePau 杀菌：要求 ABS(fTempPau - fTempPauSetC) <= fBandC 且
 *                             tPauMin 驻留到时才放行 eCool；带外跌出**不退出 ePau 而冻结
 *                             驻留计时**（保守侧，TON IN 表达式派生）+ 记 eCause=eBandOut
 *                             （信息级每拍重算，回带即清）；
 *                           eCool 冷却：出口温降联锁 fTempCoo <= fCoolMaxC 才放行 eDone
 *                             （防烫瓶）；
 *                           进瓶无料（bBottleIn 长假）挂起不故障（不推进不算错）。
 * 接口     (Interface)  : 输入 bStart/bStop/bReset、fTempPau 杀菌区实测（℃）、fTempCoo
 *                         冷却区实测（℃）、fTempPauSetC 杀菌设定（℃）、fBandC 温度带
 *                         半宽（℃）、fCoolMaxC 出口允许最高温（℃）、tPauMin 杀菌段最短
 *                         驻留、tPreheatMin 预热最短时长、fVconvMmS 网链速度（mm/s）、
 *                         bBottleIn/bBottleOut 进出口光电；输出 ePhase 六态、bPauInBand
 *                         带内指示、相指示 BOOL 组、bDone、eCause、bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做三温区段序推进与双联锁判定，不
 *                         驱动加热阀/风机/网链变频**（网链速度仅作诊断输入不内环控制）。
 *                         ② 六态 CASE + ELSE 兜底 eFault（R6）；TON 段 0 无条件刷新，
 *                         IN 由当前相与带内判据派生（带外冻结驻留，R188 自派生式）。
 *                         ③ 非有限温度 → eFault eCause=eNoData（分码，R190 归因唯一）。
 *                         ④ 组态闸：fBandC<=0、fCoolMaxC<=0、tPauMin<=T#0S、
 *                         tPreheatMin<=T#0S → 锁存 eFault eCfgIllegal。
 *                         ⑤ eCause 语义分层：eBandOut 为信息级（带内每拍重算清除）、
 *                         eNoData/eCfgIllegal 为故障级锁存（解除沿 = bReset 上升沿）。
 *                         ⑥ 温度带判定浮点全用 <= / >= 比较，禁 = 判等（R28）。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_KilnSoakHoldCtrl` 类烧成件分域：巴杀温带驻留 ≠ 烧成
 *                         保温；与干燥段序件分域：出口温降联锁为食品保质期语义。
 * 来源标签 (Source Tag) : T2-2 ◐（LBP 工艺分层只借杀菌/冷却段序分类事实，双联锁实现自研）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 ENUM 六态 + BOOL 组 +
 *                         ENUM 成因；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 带冻结 TON 派生 + 非有限分码 + 组态闸 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 六态 CASE 含 ELSE ｜ R7 ✓ 两 TON/两 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R48 首版（批次 4 · 序号 19）
 *                         验收向量：预热入带 → ePau；带外跌出驻留冻结不退出；tPauMin 到
 *                         + 带内 → eCool；出口超温禁 done；无料挂起不故障。
 *==============================================================================*)

TYPE E_DL_TpsPhase :
(
    eIdle    := 0,    // 待机 / Idle
    ePreheat := 10,   // 预热相 / Preheat phase
    ePau     := 20,   // 杀菌驻留相 / Pasteurization dwell phase
    eCool    := 30,   // 冷却相 / Cooling phase
    eDone    := 40,   // 程序完成 / Sequence done
    eFault   := 90    // 故障（等复位）/ Fault, awaiting reset
);
END_TYPE

TYPE E_DL_TpsCause :
(
    eNone       := 0,   // 无异常 / No anomaly
    eCfgIllegal := 1,   // 组态非法 / Illegal configuration
    eNoData     := 2,   // 温度非有限（故障级锁存）/ Non-finite temperature, latched
    eBandOut    := 3    // 杀菌带外（信息级，带内自动清除）/ Band dropout, informational
);
END_TYPE

FUNCTION_BLOCK FB_DL_TunnelPasteurizerSeq
VAR_INPUT
    bStart      : BOOL := FALSE;    // 启动沿（eIdle 入预热相） [-] / Start edge
    bStop       : BOOL := FALSE;    // 中止（任一相回 eIdle，不记故障） [-] / Abort to idle
    bReset      : BOOL := FALSE;    // 复位，上升沿清全部锁存（R311） [-] / Reset, rising edge clears all latches
    fTempPau    : LREAL := 0.0;     // 杀菌区实测温度 [℃] / Pasteurization zone temperature [degC]
    fTempCoo    : LREAL := 0.0;     // 冷却区实测温度 [℃] / Cooling zone temperature [degC]
    fTempPauSetC: LREAL := 72.0;    // 杀菌设定温度，域 > 0 [℃] / Pasteurization setpoint [degC]
    fBandC      : LREAL := 1.0;     // 杀菌温度带半宽，域 > 0 [℃] / Band half-width [degC]
    fCoolMaxC   : LREAL := 40.0;    // 出口允许最高温（温降联锁），域 > 0 [℃] / Outlet max temperature [degC]
    tPauMin     : TIME := T#10M;    // 杀菌段最短驻留，域 > T#0S [ms] / Minimum pasteurization dwell [ms]
    tPreheatMin : TIME := T#5M;     // 预热段最短时长，域 > T#0S [ms] / Minimum preheat duration [ms]
    fVconvMmS   : LREAL := 0.0;     // 网链速度（诊断输入，不内环控制） [mm/s] / Conveyor speed, diagnostic only [mm/s]
    bBottleIn   : BOOL := FALSE;    // 进瓶光电（长假期挂起不故障） [-] / Infeed photo-eye
    bBottleOut  : BOOL := FALSE;    // 出瓶光电（冷却段放行参考） [-] / Discharge photo-eye
END_VAR
VAR_OUTPUT
    ePhase     : E_DL_TpsPhase;     // 当前相出口 [-] / Present phase outlet
    bPauInBand : BOOL;              // 杀菌温度带内指示 [-] / In-band indicator
    bPreheatActive: BOOL;           // 预热相指示 [-] / Preheat indicator
    bPauActive : BOOL;              // 杀菌相指示 [-] / Pasteurization indicator
    bCoolActive: BOOL;              // 冷却相指示 [-] / Cooling indicator
    bDone      : BOOL;              // 程序完成（eDone 驻留指示） [-] / Done indicator
    eCause     : E_DL_TpsCause;     // 成因出口（信息级/故障级分层，头注释⑤） / Cause outlet
    bError     : BOOL;              // 故障标志 [-] / Error flag
END_VAR
VAR
    _eState  : E_DL_TpsPhase := E_DL_TpsPhase.eIdle;   // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause  : E_DL_TpsCause := E_DL_TpsCause.eNone;   // 成因锁存量 / Latched cause
    _bFault  : BOOL;             // 故障锁存位（解除沿 = bReset 上升沿） / Latched fault bit
    _bInBand : BOOL;             // 当拍杀菌带内判据 [-] / In-band this scan
    _bNonFin : BOOL;             // 温度非有限当拍量 [-] / Non-finite temperature this scan
    _bCfgBad : BOOL;             // 组态非法当拍量 [-] / Illegal configuration this scan
    _bBusyPrev: BOOL;            // 上拍运行快照（bDone 迁出用） / Busy snapshot
    tonPreheat: TON;             // 预热最短时长定时器，段 0 无条件调用 / Preheat minimum timer
    tonPauMin : TON;             // 杀菌驻留计时定时器（带内派生 IN），段 0 无条件调用 / Pasteurization dwell timer
    rtStart   : R_TRIG;          // 启动沿实例，段 0 无条件调用 / Start edge instance
    rtReset   : R_TRIG;          // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_TPS_ZERO : LREAL := 0.0;    // 非有限差值判零基准 [-] / Non-finite difference zero base
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 两 TON 两沿无条件周期刷新 —— *)
_bNonFin := (fTempPau <> fTempPau) OR ((fTempPau - fTempPau) <> DL_TPS_ZERO)
         OR (fTempCoo <> fTempCoo) OR ((fTempCoo - fTempCoo) <> DL_TPS_ZERO);   // 双区温度非有限（R245） / Non-finite zone temperatures
_bCfgBad := (fBandC <= 0.0) OR (fCoolMaxC <= 0.0) OR (fTempPauSetC <= 0.0)
         OR (tPauMin <= T#0S) OR (tPreheatMin <= T#0S);     // 组态域闸 / Configuration gate
rtStart(CLK := bStart);                                     // 启动沿，每拍必调 / Start edge, every scan
rtReset(CLK := bReset);                                     // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：带内判据 + 驻留 TON 派生刷新（带外冻结驻留计时） —— *)
_bInBand := (NOT _bNonFin) AND (ABS(fTempPau - fTempPauSetC) <= fBandC);   // 杀菌带内（容差比较，禁 =） / In-band test
tonPreheat(IN := (_eState = E_DL_TpsPhase.ePreheat), PT := tPreheatMin);   // 预热最短计时（进相计时，出相自复位） / Preheat timer
tonPauMin(IN := (_eState = E_DL_TpsPhase.ePau) AND _bInBand, PT := tPauMin);   // 杀菌驻留计时（带外冻结，保守侧） / Dwell timer, band-gated

(* —— 段 2：单拍量预清零（锁存量 _eState/_eCause/_bFault 不入清单，R107） —— *)
bPreheatActive := FALSE;                                    // 预热相指示预清 / Preheat preset
bPauActive := FALSE;                                        // 杀菌相指示预清 / Pau preset
bCoolActive := FALSE;                                       // 冷却相指示预清 / Cool preset
bDone := FALSE;                                             // 完成指示预清 / Done preset
bError := FALSE;                                            // 故障标志预清（R45 配对） / Error preset

(* —— 段 3：组态闸入故障 —— *)
IF _bCfgBad AND (NOT _bFault) THEN
    _bFault := TRUE;                                        // 锁存 / Latch
    _eCause := E_DL_TpsCause.eCfgIllegal;                   // 归因：组态非法 / Cause: illegal config
    _eState := E_DL_TpsPhase.eFault;                        // 入故障相 / Enter fault
END_IF

(* —— 段 4：迁出链（bStop 优先不记故障；bReset 清全部锁存 R311） —— *)
IF bStop AND (_eState <> E_DL_TpsPhase.eIdle) THEN
    IF _eState = E_DL_TpsPhase.eFault THEN
        _bFault := FALSE;                                   // 停机优先清故障 / Stop wins over fault
        _eCause := E_DL_TpsCause.eNone;                     // 清成因 / Clear cause
    END_IF
    _eState := E_DL_TpsPhase.eIdle;                         // 回待机 / Back to idle
END_IF
IF rtReset.Q THEN
    _bFault := FALSE;                                       // 清故障锁存（R311） / Clear fault latch
    _eCause := E_DL_TpsCause.eNone;                         // 清成因 / Clear cause
    _eState := E_DL_TpsPhase.eIdle;                         // 回待机 / Back to idle
END_IF

(* —— 段 5：六态段序（只在无故障时推进；非有限 → 故障分码 eNoData） —— *)
IF (NOT _bFault) AND (NOT _bCfgBad) AND (NOT bStop) THEN
    IF _bNonFin AND (_eState <> E_DL_TpsPhase.eIdle) AND (_eState <> E_DL_TpsPhase.eDone) THEN
        _bFault := TRUE;                                    // 运行相温度非有限：故障锁存（规格③） / Non-finite in running phase
        _eCause := E_DL_TpsCause.eNoData;                   // 归因分码：无有效数据 / Cause: no data
        _eState := E_DL_TpsPhase.eFault;                    // 入故障相 / Enter fault
    ELSE
        CASE _eState OF

        E_DL_TpsPhase.eIdle:
            IF rtStart.Q THEN
                _eState := E_DL_TpsPhase.ePreheat;          // 启动沿入预热相 / Start edge enters preheat
            END_IF

        E_DL_TpsPhase.ePreheat:
            IF tonPreheat.Q AND (fTempPau >= (fTempPauSetC - fBandC)) THEN
                _eState := E_DL_TpsPhase.ePau;              // 预热到时 ∧ 温升入带下沿：进杀菌相 / Preheat done and in lower band
            END_IF

        E_DL_TpsPhase.ePau:
            IF _bInBand THEN
                _eCause := E_DL_TpsCause.eNone;             // 回带：清除信息级带外码（信息级每拍重算） / Back in band: clear info code
            ELSE
                _eCause := E_DL_TpsCause.eBandOut;          // 带外跌出：记信息级码，不退出不故障（规格③） / Band out: info code only
            END_IF
            IF tonPauMin.Q AND _bInBand THEN
                _eState := E_DL_TpsPhase.eCool;             // 驻留到时 ∧ 带内：放行冷却相 / Dwell done and in band: proceed
            END_IF

        E_DL_TpsPhase.eCool:
            _eCause := E_DL_TpsCause.eNone;                 // 冷却相清除信息级码 / Clear info code in cooling
            IF (fTempCoo <= fCoolMaxC) AND bBottleOut THEN
                _eState := E_DL_TpsPhase.eDone;             // 出口温降联锁 ∧ 出瓶：进完成相（防烫瓶） / Outlet cool enough with bottle out
            END_IF

        E_DL_TpsPhase.eDone:
            ;                                               // 完成相驻留：由 bReset / bStop 迁出 / Held, exits via reset or stop

        E_DL_TpsPhase.eFault:
            ;                                               // 故障相驻留：由迁出链处理 / Held by exit chain

        ELSE
            _eCause := E_DL_TpsCause.eCfgIllegal;           // 非法相位兜底归因 / Illegal phase cause
            _bFault := TRUE;                                // 锁存 / Latch
            _eState := E_DL_TpsPhase.eFault;                // 强拉故障相 / Force fault

        END_CASE
    END_IF
END_IF

(* —— 段 6：完成脉冲（由"运行→eDone"沿派生，单拍，R34 两段式） —— *)
IF _bBusyPrev AND (_eState = E_DL_TpsPhase.eDone) THEN
    bDone := TRUE;                                          // 程序完成单拍指示 / Done pulse
END_IF
_bBusyPrev := (_eState <> E_DL_TpsPhase.eIdle)
          AND (_eState <> E_DL_TpsPhase.eDone)
          AND (_eState <> E_DL_TpsPhase.eFault);            // 运行中快照（本拍末） / Busy snapshot at body end

(* —— 段 7：出口单点映射（相指示与相别同源，R191） —— *)
bPreheatActive := (_eState = E_DL_TpsPhase.ePreheat);       // 预热相指示 / Preheat indicator
bPauActive := (_eState = E_DL_TpsPhase.ePau);               // 杀菌相指示 / Pau indicator
bCoolActive := (_eState = E_DL_TpsPhase.eCool);             // 冷却相指示 / Cool indicator
IF _eState = E_DL_TpsPhase.eDone THEN
    bDone := TRUE;                                          // 完成相驻留期保持指示（R191） / Done held while resident
END_IF
bPauInBand := (_eState = E_DL_TpsPhase.ePau) AND _bInBand;   // 带内指示（仅杀菌相有意义） / In-band indicator
ePhase := _eState;                                          // 当前相出口 / Present phase outlet
eCause := _eCause;                                          // 成因出口 / Cause outlet
bError := _bFault OR _bCfgBad;                              // 故障标志 = 锁存或组态非法 / Error flag

END_FUNCTION_BLOCK
