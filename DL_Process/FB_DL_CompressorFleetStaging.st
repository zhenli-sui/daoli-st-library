(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CompressorFleetStaging
 * 所属子库 (Sublibrary) : DL_Process
 * 归属目录 (Directory)  : C:\Library\DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 分类/来源标签         : 功能块（FUNCTION_BLOCK）· 公用工程 · 空压机群站编排
 *                         industry-pool / compressed-air / fleet-staging
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 TON
 * 溯源声明 (Provenance) : 道莅自研 clean-room——只借公开规范条款与工程惯例，零代码行复制。
 * 功能一句话 (Summary)  : 空压机群站加卸载编排：母管压力带定目标台数（TRUNC
 *                         进位点），错峰单台步进启停，最短运行/停止轮值防浪涌。
 *
 * 功能描述 (Function)   : 目标台数 = TRUNC((上限压力 − 母管压力) ÷ 压力带宽
 *                         × 总台数)，余量按 0.5 进位（R149 两式：先 TRUNC
 *                         再按余量进位，不写 TRUNC+1），结果钳到 0..总台数；
 *                         台数调整每错峰窗最多一台（防同时启停浪涌）；起台
 *                         轮值指针循环选机，停台优先运行时间最短者；单台
 *                         最短运行/最短停止时间由独立 TON 实例守护。
 * 与既有件边界 (Boundary): 本件只出各台加载指令，不出调节阀/变频指令；
 *                         压力闭环归调节件，本件是台数编排层。
 * 码位说明 (Codes)      : 信息 16#0006_3014 台数调整步进执行（单台错峰）
 *                         故障 16#0006_3015 压力带域外（高低倒置或带宽近零）——本拍重算，非锁存
 *                         故障 16#0006_3016 台数域外（小于 1 或大于 8）——本拍重算，非锁存
 *                         故障 16#0006_3017 压力输入非有限，编排冻结——锁存，bSigOk 恢复沿清码
 *                         段 16#06_0_14~18 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 TON / ABS。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q（台阵引脚）
 *                         除法前强制判零（带宽容差闸）｜ NaN/Inf 精确判据
 *                         ENUM 配 CASE 且 ELSE 兜底 ｜ TON 用 ARRAY 各台独立
 *                         实例且每周期无条件刷新 ｜ 全变量双语同行注释
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 3）
 *                        2026-11-18  v1.0.1  R33 返修：错峰窗自复位振荡；3015/3016 改本拍重算非锁存；3017 加恢复沿清码
 *============================================================================*)

FUNCTION_BLOCK FB_DL_CompressorFleetStaging
VAR_INPUT
    bRun        : BOOL;                     // 编排使能，假则全卸载清指针 / Enable, FALSE unloads all
    fHeaderKpa  : LREAL;                    // 母管压力 [kPa] / Header pressure
    fBandLowKpa : LREAL := 620.0;           // 压力带下限 [kPa]，低于则加台 / Band lower limit
    fBandHighKpa: LREAL := 700.0;           // 压力带上限 [kPa]，高于则减台 / Band upper limit
    nUnitsMax   : INT;                      // 可用台数 [台]，域 1 到 8 / Available units, 1 to 8
    tMinRunS    : TIME  := T#120S;          // 单台最短运行时间 [s] / Minimum run time per unit
    tMinStopS   : TIME  := T#180S;          // 单台最短停止时间 [s] / Minimum stop time per unit
    tStaggerS   : TIME  := T#30S;           // 错峰窗时长 [s]，窗内最多一台启停 / Stagger window
    fEps        : LREAL := 1.0E-6;          // 浮点判零容差 [实数域] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    aStaged : ARRAY[1..8] OF BOOL;      // 各台加载指令 [引脚]，1 到 8 台 / Per-unit load commands
    nStaged : INT;                      // 当前加载台数 [台] / Currently staged count
    bError  : BOOL;                     // 故障标志，与故障码配对 / Fault flag paired with codes
    uErrorId: UDINT;                    // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    _eState    : (eStIdle := 0, eStRegulating := 1);    // 状态机：空闲/调节 / State machine
    tonStagger : TON;           // 错峰窗定时器 [s]，每拍无条件刷新 / Stagger window timer
    aTonRun    : ARRAY[1..8] OF TON;    // 各台最短运行计时（R158 独立实例）/ Per-unit run timers
    aTonStop   : ARRAY[1..8] OF TON;    // 各台最短停止计时（R158 独立实例）/ Per-unit stop timers
    bSigOk     : BOOL;          // 压力输入有效标志 / Pressure validity flag
    bBandOk    : BOOL;          // 压力带域有效标志 / Band validity flag
    iTarget    : INT;           // 目标台数 [台] / Target count
    fNeed      : LREAL;         // 台数需求比例值 [比值] / Count demand as a ratio
    fFrac      : LREAL;         // TRUNC 后余量 [比值]，进位判据 / Remainder for the carry
    fBandW     : LREAL;         // 压力带宽 [kPa] / Band width
    nRotPtr    : INT;           // 起台轮值指针 [索引]，1 到 nUnitsMax 循环 / Rotation pointer
    nI         : INT;           // 台循环下标 [索引] / Unit loop index
    uCodeLatch : UDINT;         // 故障锁存码 [码] / Latched fault code
    uInfoCode  : UDINT;         // 信息级单拍码 [码] / One-shot info code
    uLevelCode : UDINT;         // 本拍重算级故障码，非锁存（R33 返修）/ Recomputed per-scan fault code
    bSigOkPrev : BOOL;          // 上拍压力有效快照，恢复沿判据 / Previous validity snapshot
END_VAR
VAR CONSTANT
    DL_CFS_NMAX  : INT   := 8;          // 台数上限 [台]，与数组声明一致 / Unit cap, matches the array
    DL_CFS_HALF  : LREAL := 0.5;        // 进位余量阈值 [比值] / Carry remainder threshold
END_VAR

(* 段 1｜定时器无条件刷新（红线 7）：错峰窗与各台运行/停止计时全部每拍触发
 *      Timers refreshed unconditionally: stagger window plus per-unit arrays *)
tonStagger(IN := NOT tonStagger.Q, PT := tStaggerS);    // 错峰窗自复位振荡（R33 返修）/ Self-reset oscillating window
FOR nI := 1 TO DL_CFS_NMAX DO
    aTonRun[nI](IN := aStaged[nI], PT := tMinRunS); // 运行计时随加载 / Run timing with load
    aTonStop[nI](IN := NOT aStaged[nI], PT := tMinStopS);   // 停止计时随卸载 / Stop timing with unload
END_FOR

(* 段 2｜输入有效性与压力带域闸（本拍重算级：条件消失即清，非锁存）/ Validity and band gate, recomputed *)
uLevelCode := 16#0000_0000;                 // 每拍先清，条件不满足再置（可达清零）/ Clear each scan
bSigOk := (fHeaderKpa = fHeaderKpa)                 // NaN 自反判据 / NaN reflexivity
          AND (ABS(fHeaderKpa) < 1.0E308);          // Inf 上限判据 / Inf limit
bBandOk := ((fBandHighKpa - fBandLowKpa) > fEps)    // 带宽必须为正 / Band width positive
           AND (nUnitsMax >= 1) AND (nUnitsMax <= DL_CFS_NMAX);  // 台数域约束 / Count domain
IF NOT bBandOk THEN
    uLevelCode := 16#0006_3015;         // 本拍重算：压力带域外 / Recomputed: band out of domain
    IF (nUnitsMax < 1) OR (nUnitsMax > DL_CFS_NMAX) THEN
        uLevelCode := 16#0006_3016;     // 本拍重算：台数域外便于排查 / Recomputed: count out of domain
    END_IF
END_IF

(* 段 3｜状态机主分派（ENUM 配 CASE，ELSE 兜底）/ State dispatch with ELSE interception *)
CASE _eState OF

    eStIdle:
        (* 本拍行为：全卸载；使能与域闸俱备拍 N+1 转调节 / Unload all; arm when valid *)
        FOR nI := 1 TO DL_CFS_NMAX DO
            aStaged[nI] := FALSE;       // 全卸载 / Unload all
        END_FOR
        nStaged := 0;                   // 台数清零 / Clear the count
        nRotPtr := 1;                   // 轮值指针复位 / Reset the pointer
        IF bRun AND bSigOk AND bBandOk THEN
            _eState := eStRegulating;   // 拍 N 空闲相满足，拍 N+1 转调节 / To regulating next scan
        END_IF

    eStRegulating:
        (* 本拍行为：算目标台数，错峰窗内最多调一台 / Compute the target, one unit per window *)
        IF NOT bRun THEN
            _eState := eStIdle;         // 拍 N+1 回空闲卸载 / Back to idle next scan
        ELSIF NOT bSigOk THEN
            uCodeLatch := 16#0006_3017; // 故障级：压力非有限，保持现状 / Fault: non-finite, hold
        ELSIF NOT bBandOk THEN
            (* 域闸已在段 2 报码，此处保守保持现状不调台 / Band gate holds the current staging *)
        ELSE
            fBandW := fBandHighKpa - fBandLowKpa;                       // 带宽导出 / Band width
            fNeed  := (fBandHighKpa - fHeaderKpa) / fBandW * UDINT_TO_LREAL(INT_TO_UDINT(nUnitsMax));   // 需求比例 / Demand ratio
            IF fNeed < 0.0 THEN
                fNeed := 0.0;           // 超上限压力：需求钳零 / Over-high pressure: clamp to zero
            ELSIF fNeed > UDINT_TO_LREAL(INT_TO_UDINT(nUnitsMax)) THEN
                fNeed := UDINT_TO_LREAL(INT_TO_UDINT(nUnitsMax));   // 超下限压力：需求钳满 / Over-low: clamp to full
            END_IF
            iTarget := LREAL_TO_DINT(TRUNC(fNeed));     // R149 两式：先 TRUNC / TRUNC first
            fFrac := fNeed - TRUNC(fNeed);              // 余量导出 / Remainder
            IF fFrac >= DL_CFS_HALF THEN
                iTarget := iTarget + 1;                 // 按余量进位（不是 TRUNC+1）/ Carry by remainder
            END_IF
            IF iTarget > nUnitsMax THEN
                iTarget := nUnitsMax;                   // 钳满 / Clamp full
            ELSIF iTarget < 0 THEN
                iTarget := 0;                           // 钳零 / Clamp zero
            END_IF
            (* 错峰步进：窗满且目标与现状不等时调一台，方向由目标决定
             * One unit per stagger window, direction from the target *)
            IF tonStagger.Q AND (iTarget <> nStaged) THEN
                IF iTarget > nStaged THEN
                    (* 加台：轮值指针循环找一台未加载且停止计时已满的机
                     * Stage up: rotate to a unit unloaded with its stop time served *)
                    FOR nI := 0 TO (DL_CFS_NMAX - 1) DO
                        nRotPtr := (nRotPtr MOD DL_CFS_NMAX) + 1;       // 指针循环推进 / Rotate the pointer
                        IF (NOT aStaged[nRotPtr]) AND (nRotPtr <= nUnitsMax) AND aTonStop[nRotPtr].Q THEN
                            aStaged[nRotPtr] := TRUE;   // 加载该台 / Load the unit
                            uInfoCode := 16#0006_3014;  // 信息级：步进执行 / Info: step executed
                            EXIT;                       // 单台即止 / One unit only
                        END_IF
                    END_FOR
                ELSE
                    (* 减台：找一台已加载且运行计时已满的机（最短运行守护）
                     * Stage down: a loaded unit with its run time served *)
                    FOR nI := 1 TO nUnitsMax DO
                        IF aStaged[nI] AND aTonRun[nI].Q THEN
                            aStaged[nI] := FALSE;       // 卸载该台 / Unload the unit
                            uInfoCode := 16#0006_3014;  // 信息级：步进执行 / Info: step executed
                            EXIT;                       // 单台即止 / One unit only
                        END_IF
                    END_FOR
                END_IF
                nStaged := 0;               // 台数重算 / Recount
                FOR nI := 1 TO DL_CFS_NMAX DO
                    IF aStaged[nI] THEN
                        nStaged := nStaged + 1;     // 累加实载台数 / Count the loaded units
                    END_IF
                END_FOR
            END_IF
        END_IF

ELSE
    _eState := eStIdle;                 // 非法状态拦截回空闲 / Illegal state to idle
    uCodeLatch := 16#0006_3015;         // 故障：状态越界 / Fault: state out of range
END_CASE

(* 段 4｜出口装配：3017 锁存带 bSigOk 恢复沿清码；3015/3016 本拍重算直出 / Exit assembly *)
IF (uCodeLatch = 16#0006_3017) AND bSigOk AND (NOT bSigOkPrev) THEN
    uCodeLatch := 16#0000_0000;         // 压力恢复上升沿清 3017（可达解除）/ Recovery edge clears 3017
END_IF
bSigOkPrev := bSigOk;                   // 有效标志快照 / Validity snapshot
IF NOT bRun THEN
    uCodeLatch := 16#0000_0000;         // 撤使能清故障（可达解除）/ Run drop clears faults
END_IF
IF uCodeLatch <> 16#0000_0000 THEN
    bError := TRUE;                     // 锁存故障在报 / Latched fault active
    uErrorId := uCodeLatch;             // 故障码优先 / Fault first
ELSIF uLevelCode <> 16#0000_0000 THEN
    bError := TRUE;                     // 本拍重算级故障在报 / Recomputed fault active
    uErrorId := uLevelCode;             // 域闸码本拍直出 / Band gate code this scan
ELSE
    bError := FALSE;                    // 无故障 / No fault
    uErrorId := uInfoCode;              // 信息码单拍 / Info one shot
END_IF
uInfoCode := 16#0000_0000;              // 信息码单拍消费 / Consume info code
END_FUNCTION_BLOCK
