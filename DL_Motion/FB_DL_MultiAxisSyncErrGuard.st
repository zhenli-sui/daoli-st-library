(*
    FB_DL_MultiAxisSyncErrGuard —— 多轴/龙门同步误差分级守护与首出诊断
    ------------------------------------------------------------------
    组件名    : FB_DL_MultiAxisSyncErrGuard
    分类      : DL_Motion / Synchronism Guard（多轴同步误差守护）
    一句话功能: 同时监控 4 个轴对的实时位置偏差，按「预警 → 降速 → 急停」三级响应，
                并在急停时锁存首出轴对编号与该对当时的误差值供诊断。
    复杂度    : C4
    版本      : v1.0.0
    开源溯源  : 无（clean-room 自研，未借鉴任何开源实现）
    平台      : 纯 IEC 61131-3（TON / R_TRIG / ABS / 标准库），目标编译器 RuSTy 1.0.8，
                兼容 CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert；
                无 PROPERTY、无 VLA、无 FOR..DOWNTO、无厂商方言转换
    ------------------------------------------------------------------
    功能说明  : ① 每拍对 4 个轴对独立求同步误差 afErr[p] = ABS(afPosA[p] - afPosB[p])；
                ② 阈值三分：预警阈值 = fMaxSyncErrMm × fWarnRatio，
                   降速阈值 = fMaxSyncErrMm × fDerateRatio，急停阈值 = fMaxSyncErrMm；
                   组态闸强制 fWarnRatio < fDerateRatio < 1.0，故三带不交叠；
                ③ 建立窗口：使能有效后 tSettleMs 内不判误差（机构入位、伺服使能瞬态），
                   窗口未满只维持监控相，既不置预警也不置跳闸；
                ④ 降速相输出派生速度比例 fSpeedScalePct ∈ [50, 100]（单位 %），
                   比例随最大误差在「降速阈值 → 急停阈值」之间线性下降并饱和钳位；
                ⑤ 急停相 fSpeedScalePct = 0（安全侧：撤掉进给许可），并锁存首出轴对
                   编号与误差，供 HMI 直接定位是哪一对先越限；
                ⑥ 任一浮点输入为 NaN / ±Inf / 超幅值域 → 直接迁 eFault，bFaultOut := TRUE。
    量纲链    : afPosA [mm] − afPosB [mm] → afErr [mm]；
                fMaxSyncErrMm [mm] × fWarnRatio [-] → fThWarn [mm]（比例无因次，乘除不混加）；
                fMaxSyncErrMm [mm] × fDerateRatio [-] → fThDerate [mm]；
                (fWorstErr − fThDerate) [mm] ÷ (fMaxSyncErrMm − fThDerate) [mm] → fRto [-]
                （mm ÷ mm 无因次，符合线性归一）；
                fSpeedScalePct = 100 [%] − (100 − 50)[%] × fRto [-] → [%]；
                fFirstOutErr [mm] 原样输出不做任何换算。
                全程不存在「异量纲相加」：温度、时间、比例均不进入位置差的加法链。
    状态机    : eIdle(0) --使能且组态合法且输入有限--> eMonitor(10)
                eMonitor --nSev=1--> eWarn(20)
                eMonitor/eWarn --nSev=2--> eDerate(30)
                eMonitor/eWarn/eDerate --nSev=3（跳闸锁存）--> eTrip(40)
                eWarn --nSev=0--> eMonitor（逐级回落，无跨级跳跃）
                eDerate --nSev=1--> eWarn；--nSev=0--> eMonitor
                任意相 --非有限或组态非法--> eFault(90)
                eTrip / eFault 的唯一解除路径 = bReset 上升沿（见段 6 注释与自证行）
    失能语义  : bEnable = FALSE 时输出降级为安全值（eState := eIdle、fSpeedScalePct := 0、
                bWarn := FALSE），不冻结末值；bTrip / bFaultOut 锁存位不清 ——
                急停与故障必须人工复位，失能不能代替复位（安全侧口径，R191）。
    复位作用域: bReset 上升沿①清 _bTripLatch / _nFirstPair / _fFirstErr；
                ②清 _bFaultLatch 并迁相回 eIdle；③不清建立窗口锁存 _bSettled ——
                使能未断时保持「已建立」，避免复位后重新等窗口掩盖仍在恶化的偏差。
                复位沿与本拍跳闸同拍时：复位先执行、跳闸判断后执行，故本拍跳闸不被抹除
                （本拍合法事件优先，R275）。
    防御口径  : NaN 用自反 f<>f 判；±Inf 用 (f−f)<>(f−f) 双判；另设幅值域闸
                ABS(f) > 1.0E30 兜住超大有限值与 Inf 的观测域，三件套同拍生效（R4 + R151）。
                除零守卫：降速比例分母 (fMaxSyncErrMm − fThDerate) 先与 DL_SG_EPS 比较才做
                除法；组态闸另强制 fDerateRatio < 1.0，使分母结构性不小于
                fMaxSyncErrMm × (1 − fDerateRatio) > 0（双重保证，不靠单点）。
    规格偏离  : 派单输出引脚写作 iFirstOutPair（INT）。本库命名规范 1.2 规定有符号整数
                前缀为 n、i 专用于接口引用，故落为 nFirstOutPair，语义与取值范围
                （1..4，0 = 无首出）一字不减；另按 R190 归因唯一补充 bCfgErr / bDataErr
                两个诊断位，使「组态非法」与「数据非有限」两条故障成因各自可观测。
    码位说明  : 本件按零码位范式交付，不分配 16# 事件码；分级与故障一律经
                eState / bWarn / bTrip / bFaultOut / bCfgErr / bDataErr 组合观测。
    修订记录  : 2026-11-24 v1.0.0 首次入库（R87 批 · #1）
*)
TYPE E_DL_SyncState :
(
    eIdle    := 0,    // 空闲：未使能，速度比例锁 0，不判误差 | idle, disabled, speed scale forced to zero
    eMonitor := 10,   // 监控：使能且建立窗口已满，逐拍判误差，速度比例 100 | monitoring, window elapsed, scale 100
    eWarn    := 20,   // 预警：最大误差超预警阈值，限速不变，仅告警 | warning, threshold exceeded, speed unchanged
    eDerate  := 30,   // 降速：最大误差超降速阈值，速度比例按比例下降 | derate, speed scale ramped down
    eTrip    := 40,   // 急停：最大误差超上限，速度比例 0，首出轴对已锁存 | trip, scale zero, first-out latched
    eFault   := 90    // 故障：输入非有限或组态非法，锁存至复位沿 | fault latched until the reset edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_MultiAxisSyncErrGuard
VAR_INPUT
    bEnable        : BOOL;                        // 使能电平，TRUE = 允许监控 | enable level, TRUE = monitoring allowed
    bReset         : BOOL;                        // 复位请求，上升沿生效 | reset request, rising-edge active
    afPosA         : ARRAY[1..4] OF REAL;         // 4 个轴对 A 侧实际位置 [mm] | actual position of the A side per pair [mm]
    afPosB         : ARRAY[1..4] OF REAL;         // 4 个轴对 B 侧实际位置 [mm] | actual position of the B side per pair [mm]
    fMaxSyncErrMm  : REAL := 1.0;                 // 同步误差上限（急停阈值）[mm] | sync error limit, trip threshold [mm]
    fWarnRatio     : REAL := 0.5;                 // 预警比例，乘上限得预警阈值 [-]，取值 (0,1) | warning ratio [dimensionless]
    fDerateRatio   : REAL := 0.8;                 // 降速比例，乘上限得降速阈值 [-]，取值 (warn,1) | derate ratio [dimensionless]
    tSettleMs      : TIME := T#200MS;             // 使能后的建立窗口，窗内不判 [ms] | settle window after enable [ms]
END_VAR
VAR_OUTPUT
    eState         : E_DL_SyncState;              // 主状态，供 HMI 与联锁使用 | main state for HMI and interlocks
    bWarn          : BOOL;                        // 预警汇总位，eWarn 或 eDerate 相为 TRUE | warning aggregate, TRUE in eWarn or eDerate
    bTrip          : BOOL;                        // 急停锁存位，复位沿前恒 TRUE | trip latch, stays TRUE until the reset edge
    fSpeedScalePct : REAL;                        // 派生速度比例指令 [%]，100 = 不限速，0 = 撤进给 | derived speed scale [%]
    nFirstOutPair  : INT;                         // 首出轴对编号 1..4，0 = 无首出 | first-out pair index 1..4, 0 = none
    fFirstOutErr   : REAL;                        // 首出轴对跳闸时的误差 [mm] | error of the first-out pair at trip [mm]
    bFaultOut      : BOOL;                        // 故障汇总位，含非有限与组态非法 | fault aggregate, covers non-finite and bad config
    bCfgErr        : BOOL;                        // 组态非法诊断位（归因唯一，R190）| bad-configuration flag, unique attribution
    bDataErr       : BOOL;                        // 数据非有限诊断位（归因唯一，R190）| non-finite data flag, unique attribution
END_VAR
VAR
    rtReset        : R_TRIG;                      // 复位上升沿实例，每拍无条件刷新 | reset rising-edge instance, refreshed every scan
    tonSettle      : TON;                         // 建立窗口计时实例，每拍无条件刷新 | settle window timer, refreshed every scan
    _eState        : E_DL_SyncState := E_DL_SyncState.eIdle; // 状态机内部当前态 | internal current state
    _bSettled      : BOOL := FALSE;               // 建立窗口已满锁存量 | settle-window elapsed latch
    _bResetLatch   : BOOL := FALSE;               // 复位沿锁存量，本拍末清除 | reset-edge latch, cleared at the end of the scan
    _bTripLatch    : BOOL := FALSE;               // 急停锁存位 | trip latch
    _bFaultLatch   : BOOL := FALSE;               // 故障锁存位 | fault latch
    _nFirstPair    : INT := 0;                    // 首出轴对编号锁存 1..4，0 = 无 | latched first-out pair index
    _fFirstErr     : REAL := 0.0;                 // 首出误差锁存 [mm] | latched first-out error [mm]
    afErr          : ARRAY[1..4] OF REAL;         // 各轴对同步误差绝对值 [mm] | absolute sync error per pair [mm]
    fThWarn        : REAL := 0.0;                 // 本拍预警阈值 [mm] | warning threshold this scan [mm]
    fThDerate      : REAL := 0.0;                 // 本拍降速阈值 [mm] | derate threshold this scan [mm]
    fWorstErr      : REAL := 0.0;                 // 本拍最大同步误差 [mm] | worst sync error this scan [mm]
    nWorstPair     : INT := 0;                    // 本拍最大误差所属轴对 1..4 | pair holding the worst error this scan
    nTripPair      : INT := 0;                    // 本拍首个越急停阈值的轴对 1..4 | lowest-index pair beyond the trip threshold
    nSev           : INT := 0;                    // 本拍严重度 0 正常 1 预警 2 降速 3 急停 | severity level this scan
    nIdx           : INT := 1;                    // 轴对遍历下标 | pair loop index
    _bBadIn        : BOOL := FALSE;               // 本拍输入非有限标志 | non-finite input flag this scan
    _bCfgBad       : BOOL := FALSE;               // 本拍组态非法标志 | bad configuration flag this scan
    fDen           : REAL := 0.0;                 // 降速比例分母（阈值带宽）[mm] | derate scaling denominator [mm]
    fRto           : REAL := 0.0;                 // 降速带内归一比例 [0..1] | normalised ratio inside the derate band
END_VAR
VAR CONSTANT
    DL_SG_PAIR_MAX   : INT := 4;                  // 轴对总数硬界，与数组上界一致 [-] | hard pair count matching the array bound
    DL_SG_EPS        : REAL := 1.0E-6;            // 浮点判零容差 [mm] | float zero tolerance [mm]
    DL_SG_MAG_MAX    : REAL := 1.0E30;            // 有限幅值域闸上限 [mm] | finite magnitude domain bound [mm]
    DL_SG_SCALE_MIN  : REAL := 50.0;              // 降速相最低速度比例 [%] | minimum derated speed scale [%]
    DL_SG_SCALE_FULL : REAL := 100.0;             // 满速比例 [%] | full speed scale [%]
END_VAR

METHOD Clamp01 : REAL
(*
    归一比例钳位：把降速带内比例钳到 [0,1]，越界一律饱和。纯函数，无跨拍状态。
    Clamp-normalised ratio: saturate the in-band ratio to [0,1]. Pure function, no cross-scan state.
*)
VAR_INPUT
    fIn : REAL;                                   // 待钳位比例 [-] | ratio to be clamped [-]
END_VAR
Clamp01 := fIn;                                   // 直通赋值，下方按两侧硬界饱和 | straight-through, saturated on both bounds below
IF Clamp01 < 0.0 THEN
    Clamp01 := 0.0;                               // 低于下限钳 0，防负比例抬高速度 | clamp low bound to zero
END_IF
IF Clamp01 > 1.0 THEN
    Clamp01 := 1.0;                               // 高于上限钳 1，防比例超上限 | clamp high bound to one
END_IF
END_METHOD

// 段 1｜定时器与沿实例无条件周期刷新（R7：严禁放入 IF / CASE 分支内部）
// segment 1, timers and edge instances refreshed unconditionally, never inside an IF or CASE branch
rtReset(CLK := bReset);
tonSettle(IN := bEnable AND (NOT _bSettled), PT := tSettleMs);
IF rtReset.Q THEN
    _bResetLatch := TRUE;                         // 复位沿先存锁存量，由段 6 统一消费 | store the reset edge, consumed in segment 6
END_IF
IF tonSettle.Q THEN
    _bSettled := TRUE;                            // 窗口到时置锁存量，本拍即可判 | window elapsed, judging allowed from this scan
END_IF
IF NOT bEnable THEN
    _bSettled := FALSE;                           // 失能即重新武装窗口，下次使能重新计时 | disarm the window so the next enable re-times
END_IF

// 段 2｜输出安全侧预置（每拍先落安全值，CASE 内只做升级赋值）
// segment 2, preset outputs to their safe values; the CASE below only upgrades them
fSpeedScalePct := 0.0;                            // 预置速度比例 0 [%]，进给许可默认撤销 | preset zero speed scale, feed permission withdrawn
bWarn := FALSE;                                   // 预置无预警 | preset no warning
_bBadIn := FALSE;                                 // 预置输入有限 | preset finite input
_bCfgBad := FALSE;                                // 预置组态合法 | preset legal configuration
nSev := 0;                                        // 预置严重度正常 | preset normal severity

// 段 3｜非有限闸：NaN 自反 + Inf 自减 + 幅值域，逐个浮点入参枚举（R4 / R151 / R272）
// segment 3, non-finite gate: NaN self-reflexive, Inf by self-subtraction, plus a magnitude bound, one entry per REAL input
FOR nIdx := 1 TO DL_SG_PAIR_MAX DO
    IF (afPosA[nIdx] <> afPosA[nIdx]) OR ((afPosA[nIdx] - afPosA[nIdx]) <> (afPosA[nIdx] - afPosA[nIdx])) THEN
        _bBadIn := TRUE;                          // A 侧 NaN 或 ±Inf | NaN or infinity on the A side
    END_IF
    IF ABS(afPosA[nIdx]) > DL_SG_MAG_MAX THEN
        _bBadIn := TRUE;                          // A 侧超幅值域 | A side beyond the magnitude domain
    END_IF
    IF (afPosB[nIdx] <> afPosB[nIdx]) OR ((afPosB[nIdx] - afPosB[nIdx]) <> (afPosB[nIdx] - afPosB[nIdx])) THEN
        _bBadIn := TRUE;                          // B 侧 NaN 或 ±Inf | NaN or infinity on the B side
    END_IF
    IF ABS(afPosB[nIdx]) > DL_SG_MAG_MAX THEN
        _bBadIn := TRUE;                          // B 侧超幅值域 | B side beyond the magnitude domain
    END_IF
END_FOR
IF (fMaxSyncErrMm <> fMaxSyncErrMm) OR ((fMaxSyncErrMm - fMaxSyncErrMm) <> (fMaxSyncErrMm - fMaxSyncErrMm)) THEN
    _bBadIn := TRUE;                              // 误差上限 NaN 或 ±Inf | limit NaN or infinity
END_IF
IF (fWarnRatio <> fWarnRatio) OR ((fWarnRatio - fWarnRatio) <> (fWarnRatio - fWarnRatio)) THEN
    _bBadIn := TRUE;                              // 预警比例 NaN 或 ±Inf | warning ratio NaN or infinity
END_IF
IF (fDerateRatio <> fDerateRatio) OR ((fDerateRatio - fDerateRatio) <> (fDerateRatio - fDerateRatio)) THEN
    _bBadIn := TRUE;                              // 降速比例 NaN 或 ±Inf | derate ratio NaN or infinity
END_IF

// 段 4｜组态闸：上限须为正、比例须严格递增且小于 1（保证三带不交叠、降速分母为正）
// segment 4, configuration gate: positive limit, strictly increasing ratios below one, keeping three disjoint bands and a positive denominator
IF (fMaxSyncErrMm <= DL_SG_EPS) OR (fWarnRatio <= DL_SG_EPS) OR (fWarnRatio >= fDerateRatio) OR (fDerateRatio >= 1.0) THEN
    _bCfgBad := TRUE;                             // 组态非法：阈值带错序或非正 | illegal configuration, band order or sign
END_IF

// 段 5｜阈值、误差与严重度裁决（每拍全量重算，无跨拍状态驻留）
// segment 5, thresholds, errors and severity decision, fully recomputed every scan with no cross-scan state
fThWarn := fMaxSyncErrMm * fWarnRatio;            // 预警阈值 [mm] = [mm] × [-] | warning threshold [mm]
fThDerate := fMaxSyncErrMm * fDerateRatio;        // 降速阈值 [mm] = [mm] × [-] | derate threshold [mm]
fWorstErr := 0.0;                                 // 清本拍最大误差 [mm] | clear the worst error
nWorstPair := 0;                                  // 清本拍最坏轴对编号 | clear the worst pair index
nTripPair := 0;                                   // 清本拍首个越限轴对编号 | clear the lowest-index tripping pair
FOR nIdx := 1 TO DL_SG_PAIR_MAX DO
    afErr[nIdx] := ABS(afPosA[nIdx] - afPosB[nIdx]); // 轴对同步误差 [mm] = [mm] − [mm] | per-pair sync error [mm]
    IF afErr[nIdx] > fWorstErr THEN
        fWorstErr := afErr[nIdx];                 // 记录本拍最大误差 [mm] | record the worst error [mm]
        nWorstPair := nIdx;                       // 记录最大误差所属轴对 | record the pair holding it
    END_IF
    IF (afErr[nIdx] > fMaxSyncErrMm) AND (nTripPair = 0) THEN
        nTripPair := nIdx;                        // 升序遍历只记首个越限对，首出不随最坏值漂移 | first tripping pair only, ascending scan
    END_IF
END_FOR
IF fWorstErr > fMaxSyncErrMm THEN
    nSev := 3;                                    // 超急停上限 | beyond the trip limit
ELSIF fWorstErr > fThDerate THEN
    nSev := 2;                                    // 超降速阈值 | beyond the derate threshold
ELSIF fWorstErr > fThWarn THEN
    nSev := 1;                                    // 超预警阈值 | beyond the warning threshold
ELSE
    nSev := 0;                                    // 三带之内正常运行 | inside all bands, normal operation
END_IF

// 段 6｜复位沿处理（唯一解除路径）：先复位后判跳闸，保证本拍新跳闸不被抹除（R275）
// segment 6, reset edge handling, the only release path; reset runs before the trip decision so a same-scan trip survives
IF _bResetLatch THEN
    _bTripLatch := FALSE;                         // 清急停锁存 | clear the trip latch
    _nFirstPair := 0;                             // 清首出轴对编号 | clear the first-out pair index
    _fFirstErr := 0.0;                            // 清首出误差 [mm] | clear the first-out error [mm]
    _bFaultLatch := FALSE;                        // 清故障锁存 | clear the fault latch
    _eState := E_DL_SyncState.eIdle;              // 迁回空闲相，下一拍按使能重新建窗 | return to idle, re-arm on the next scan
END_IF

// 段 7｜故障锁存：非有限与组态非法各自独立置位（R190 归因唯一），锁存与迁相同段完成
// segment 7, fault latches; non-finite data and bad configuration keep separate members and separate set points
IF _bBadIn AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                         // 锁存数据非有限 | latch the non-finite data fault
    _eState := E_DL_SyncState.eFault;             // 与锁存同拍迁相（R258）| migrate in the same scan as the latch
END_IF
IF _bCfgBad AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                         // 锁存组态非法 | latch the bad configuration fault
    _eState := E_DL_SyncState.eFault;             // 与锁存同拍迁相（R258）| migrate in the same scan as the latch
END_IF

// 段 8｜跳闸判据与首出锁存：与状态无关的纯判据，故放在 CASE 之前统一裁决
// segment 8, trip criterion and first-out latch; a state-independent criterion, so it is decided before the CASE
IF bEnable AND _bSettled AND (NOT _bTripLatch) AND (NOT _bFaultLatch) AND (nSev >= 3) THEN
    _bTripLatch := TRUE;                          // 置急停锁存 | raise the trip latch
    IF nTripPair > 0 THEN
        _nFirstPair := nTripPair;                 // 首出 = 首个越限轴对 | first out is the lowest-index tripping pair
    ELSE
        _nFirstPair := nWorstPair;                // 兜底取最坏轴对（结构上 nSev>=3 必有越限对）| fall back to the worst pair
    END_IF
    _fFirstErr := fWorstErr;                      // 记录当时误差 [mm] | record the error at trip [mm]
END_IF

// 段 9｜主状态机：ENUM + CASE + ELSE 兜底（R6），逐级升降，无跨级跳跃
// segment 9, main state machine with ENUM + CASE + ELSE fallback, stepwise up and down, no band skipping
CASE _eState OF
E_DL_SyncState.eIdle:
    fSpeedScalePct := 0.0;                        // 空闲相速度比例 0 [%] | idle phase keeps the scale at zero
    // 拍 N 进入：复位沿或使能撤除；本拍行为：拒绝任何分级输出，只保留锁存位；
    // 拍 N+1 转出：使能有效且组态合法且输入有限 → 监控相
    // entered on the reset edge or on disable; refuses every graded output and keeps the latches only;
    // exits to eMonitor once enabled with legal configuration and finite inputs
    IF bEnable AND (NOT _bCfgBad) AND (NOT _bBadIn) AND (NOT _bFaultLatch) THEN
        _eState := E_DL_SyncState.eMonitor;
    END_IF

E_DL_SyncState.eMonitor:
    fSpeedScalePct := DL_SG_SCALE_FULL;           // 监控相满速 100 [%] | monitoring phase runs at full scale [%]
    IF NOT bEnable THEN
        _eState := E_DL_SyncState.eIdle;           // 失能回空闲 | return to idle when disabled
    ELSIF _bTripLatch THEN
        _eState := E_DL_SyncState.eTrip;           // 本拍跳闸优先迁移 | migrate to trip when the latch is raised
    ELSIF _bSettled AND (nSev = 2) THEN
        _eState := E_DL_SyncState.eDerate;         // 升到降速相 | step up to derate
    ELSIF _bSettled AND (nSev = 1) THEN
        _eState := E_DL_SyncState.eWarn;           // 升到预警相 | step up to warning
    END_IF
    // 窗口未满时不迁移也不降级：偏差在建立窗口内无意义 | inside the settle window no migration is taken, deviation is meaningless there

E_DL_SyncState.eWarn:
    fSpeedScalePct := DL_SG_SCALE_FULL;           // 预警相不限速 100 [%] | warning phase keeps full scale [%]
    IF NOT bEnable THEN
        _eState := E_DL_SyncState.eIdle;           // 失能回空闲 | return to idle when disabled
    ELSIF _bTripLatch THEN
        _eState := E_DL_SyncState.eTrip;           // 急停优先 | trip takes priority
    ELSIF (NOT _bSettled) THEN
        _eState := E_DL_SyncState.eMonitor;        // 窗口被重新武装（使能曾断）→ 回监控等窗口 | window re-armed, wait in monitoring
    ELSIF nSev = 2 THEN
        _eState := E_DL_SyncState.eDerate;         // 恶化升相 | worsen to derate
    ELSIF nSev = 0 THEN
        _eState := E_DL_SyncState.eMonitor;        // 回落到正常带 → 降相 | back inside the bands, step down
    END_IF

E_DL_SyncState.eDerate:
    // 降速比例：误差在「降速阈值 → 急停阈值」之间线性下降到 DL_SG_SCALE_MIN [%]
    // derate scale: linear descent from the derate threshold to the trip limit, saturating at the minimum scale
    fDen := fMaxSyncErrMm - fThDerate;            // 降速带宽 [mm] = [mm] − [mm] | derate band width [mm]
    IF fDen > DL_SG_EPS THEN
        fRto := Clamp01((fWorstErr - fThDerate) / fDen); // 带内归一比例 [-] = [mm] ÷ [mm]，先判零再除 | guarded division
    ELSE
        fRto := 1.0;                              // 分母为零宽（组态闸已禁）→ 保守取满比例 | degenerate width, take the saturated ratio
    END_IF
    fSpeedScalePct := DL_SG_SCALE_FULL - (DL_SG_SCALE_FULL - DL_SG_SCALE_MIN) * fRto; // [%] − [%] × [-] | derated scale [%]
    IF NOT bEnable THEN
        _eState := E_DL_SyncState.eIdle;           // 失能回空闲 | return to idle when disabled
    ELSIF _bTripLatch THEN
        _eState := E_DL_SyncState.eTrip;           // 急停优先 | trip takes priority
    ELSIF (NOT _bSettled) THEN
        _eState := E_DL_SyncState.eMonitor;        // 窗口重新武装 → 回监控 | window re-armed, wait in monitoring
    ELSIF nSev >= 3 THEN
        _eState := E_DL_SyncState.eTrip;           // 越急停上限（锁存同拍已置）| beyond the trip limit, latch already raised
    ELSIF nSev = 0 THEN
        _eState := E_DL_SyncState.eMonitor;        // 直接回到正常带 | straight back to the normal band
    ELSIF nSev = 1 THEN
        _eState := E_DL_SyncState.eWarn;           // 缓解到预警带 | relieved into the warning band
    END_IF

E_DL_SyncState.eTrip:
    fSpeedScalePct := 0.0;                        // 急停相速度比例 0 [%]，撤进给许可 | trip phase withdraws the feed permission
    // 驻留语义：本相只能由段 6 复位沿迁出（唯一解除路径），本相不再判误差
    // dwell semantics: this phase is left only through the reset edge handled in segment 6, no error judging here

E_DL_SyncState.eFault:
    fSpeedScalePct := 0.0;                        // 故障相速度比例 0 [%] | fault phase withdraws the feed permission
    // 驻留语义：本相只能由段 6 复位沿迁出；故障码由 _bBadIn / _bCfgBad 分别观测（R190）
    // dwell semantics: left only through the reset edge in segment 6; causes observed via _bBadIn and _bCfgBad separately

ELSE
    // 非法枚举值（越界或未定义成员）：不猜、不驻留，直接置故障并回故障相
    // illegal enumerator: no guessing, latch a fault and return to the fault phase
    fSpeedScalePct := 0.0;
    _bFaultLatch := TRUE;
    _eState := E_DL_SyncState.eFault;
END_CASE;

// 段 10｜出口单点映射（锁存位在本段回放，CASE 后不再无条件清零任何 CASE 内写过的量，R187）
// segment 10, single-point output mapping; latches are replayed here and nothing written inside the CASE is cleared afterwards
eState := _eState;                                // 状态映射 | state mapping
bWarn := (_eState = E_DL_SyncState.eWarn) OR (_eState = E_DL_SyncState.eDerate); // 预警汇总，由状态派生 | warning derived from the state
bTrip := _bTripLatch;                             // 急停锁存回放 | replay the trip latch
bFaultOut := _bFaultLatch;                        // 故障锁存回放 | replay the fault latch
bCfgErr := _bCfgBad;                              // 组态非法诊断位 | bad-configuration diagnostic
bDataErr := _bBadIn;                              // 数据非有限诊断位 | non-finite data diagnostic
nFirstOutPair := _nFirstPair;                     // 首出轴对编号回放 | replay the first-out pair index
fFirstOutErr := _fFirstErr;                       // 首出误差回放 [mm] | replay the first-out error [mm]

// 段 11｜本拍消费量收尾（仅清沿锁存，不触碰任何锁存位与 CASE 内写入量）
// segment 11, end-of-scan cleanup; only the edge latch is cleared, no latch and no CASE-written identifier is touched
_bResetLatch := FALSE;
END_FUNCTION_BLOCK
