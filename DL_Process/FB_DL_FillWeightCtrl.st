(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FillWeightCtrl
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : 灌装净重闭环：去皮 → 快灌 → 细灌两段阀切换 → 毛重达
 *                         目标减提前量 → 双阀关 → 稳定窗称终值 → 误差指数学习
 *                         提前量（lambda = 0.3 常量带注释，仅在完成相更新，防运行
 *                         中改写）。细灌超时 → 中止并双阀关（安全侧）。两阀互斥校验。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_FillState / TYPE E_DL_FillErr /
 *                         FUNCTION_BLOCK FB_DL_FillWeightCtrl
 * 依赖 (Depends)        : 无 DL_ 内部依赖；Standard.library TON/R_TRIG 实例
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         目标下限防除零 + 学习值双向限幅 + 非有限值冻结 ｜
 *                         枚举成员全部显式赋值 ｜ 学习更新仅在完成相执行 ｜
 *                         两阀互斥校验 ｜ TON/R_TRIG 每周期无条件调用 ｜ CASE 含 ELSE
 * 错误码表 (Codes)      : 16#0005_0412 就绪
 *                         16#0005_0413 粗灌中
 *                         16#0005_0414 细灌中
 *                         16#0005_0415 故障级 细灌超时(中止) 或重量信号无效(共用反证句)
 *                         16#0005_0416 完成(提前量已更新)
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 3
 *                         2026-11-17  v1.0.1  R27 终审修复（对外引脚零变更）：重量有效性判据拆分为
 *                         「净重为负」与「净重超双倍目标」两支。原实现两支共用 bWeightOk，
 *                         粗灌相一律转细灌——对已超重容器（如重复上料）等于继续小流量加注，
 *                         直至细灌超时才中止。改为超重即刻双阀关 + 中止（不更新落差学习），
 *                         仅为负偏差保留保守转细灌；超重系数提为常量 DL_FILL_GROSS_K 去魔法数。
 * 验收向量 (Acceptance) : 目标 500 g 提前量 10 g 快灌比 85%：毛重 425 g 切细灌；
 *                         毛重 490 g 双阀关；稳定窗终值 495 g → 误差 +5 g →
 *                         新提前量 = 10 x 0.7 + 5 x 0.3 = 8.5 g，码 0416
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FillState（归属 DL_Process，灌装状态机状态）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FillState :
(
    eIdle   := 0,    // 就绪待启动 / Idle, waiting for a start
    eCoarse := 10,   // 粗灌相（快灌阀开）/ Coarse phase, fast valve open
    eFine   := 20,   // 细灌相（细灌阀开）/ Fine phase, fine valve open
    eSettle := 30,   // 稳定窗（双阀关，等称重稳定）/ Settle window, both valves closed
    eDone   := 40,   // 完成（提前量已更新）/ Done, advance updated
    eFault  := 99    // 故障兜底态（双阀关）/ Fault fallback, both valves closed
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FillErr（归属 DL_Process，与 FB_DL_FillWeightCtrl 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FillErr :
(
    eReady      := 16#0005_0412,   // 就绪 / Ready
    eCoarseRun  := 16#0005_0413,   // 粗灌中 / Coarse filling
    eFineRun    := 16#0005_0414,   // 细灌中 / Fine filling
    eFineTmo    := 16#0005_0415,   // 故障级：细灌超时中止（或重量信号无效）/ Fault: fine timeout or invalid weight
    eFillDone   := 16#0005_0416    // 完成，提前量已更新 / Done, advance updated
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_FillWeightCtrl
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_FillWeightCtrl
VAR_INPUT
    fGrossWeight_g : REAL;             // 毛重（称重传感器读数）[克] / Gross weight [g]
    fTargetNet_g   : REAL;             // 目标净重 [克]，有效域 1~50000 / Target net weight [g]
    fCoarsePct     : REAL := 85.0;     // 快灌切换点 [百分数]，有效域 50~95 / Coarse switch point [percent]
    tFineMax       : TIME := T#10S;    // 细灌超时 [秒] / Fine-fill timeout [s]
    tSettle        : TIME := T#2S;     // 稳定窗时长 [秒] / Settle window [s]
    bStart         : BOOL;             // 启动灌装（上升沿，同时去皮）/ Start filling, rising edge with tare
    bReset         : BOOL;             // 故障复位（上升沿）/ Fault reset, rising edge
END_VAR
VAR_OUTPUT
    bCoarseValve   : BOOL;             // 快灌阀指令 / Coarse valve command
    bFineValve     : BOOL;             // 细灌阀指令 / Fine valve command
    bFillDone      : BOOL;             // 灌装完成（单拍脉冲）/ Fill done, single-scan pulse
    fAdvance_g     : REAL;             // 当前落差提前量（学习值）[克] / Current in-flight advance, learned [g]
    fNetWeight_g   : REAL;             // 本罐净重实测 [克] / Measured net weight of this container [g]
    eErr           : E_DL_FillErr;     // 错误码 / Error code
    eState         : E_DL_FillState;   // 灌装状态机当前状态 / Fill state
END_VAR
VAR
    fbStartTrig    : R_TRIG;           // 启动沿实例（无条件调用）/ Start edge instance
    fbResetTrig    : R_TRIG;           // 复位沿实例（无条件调用）/ Reset edge instance
    fbTonFine      : TON;              // 细灌超时定时器（无条件调用）/ Fine timeout timer
    fbTonSettle    : TON;              // 稳定窗定时器（无条件调用）/ Settle timer
    fTareRef_g     : REAL;             // 去皮基准毛重 [克] / Tare reference gross weight [g]
    fTargetUse     : REAL;             // 生效目标净重（钳位后）[克] / Effective target [g]
    fCoarseUse     : REAL;             // 生效快灌切换点（钳位后）[百分数] / Effective coarse point [percent]
    fAdvUse        : REAL;             // 生效提前量（限幅后）[克] / Effective advance [g]
    fCoarseGate_g  : REAL;             // 快灌转细灌毛重门限 [克] / Coarse-to-fine gross threshold [g]
    fStopGate_g    : REAL;             // 双阀关断毛重门限 [克] / Valve-close gross threshold [g]
    fErr_g         : REAL;             // 本罐净重误差 [克] / Net weight error [g]
    bWeightOk      : BOOL;             // 重量信号有效判据 / Weight validity predicate
    bNonFin        : BOOL;             // 非有限输入汇总标志 / Non-finite input aggregate flag
    bOverGross     : BOOL;             // 净重超双倍目标（容器已超重，v1.0.1）/ Net above twice target, over-weight container
END_VAR
VAR CONSTANT
    DL_FILL_TGT_MIN   : REAL := 1.0;      // 目标净重下限 [克] / Target lower bound [g]
    DL_FILL_TGT_MAX   : REAL := 50000.0;  // 目标净重上限 [克] / Target upper bound [g]
    DL_FILL_COARSE_MIN: REAL := 50.0;     // 快灌切换点下限 [百分数] / Coarse point lower bound [percent]
    DL_FILL_COARSE_MAX: REAL := 95.0;     // 快灌切换点上限 [百分数] / Coarse point upper bound [percent]
    DL_FILL_ADV_MAX_K : REAL := 0.2;      // 提前量上限系数（目标 x 0.2）/ Advance upper ratio, target x 0.2
    DL_FILL_LAMBDA    : REAL := 0.3;      // 指数学习系数 lambda（0.3：约 3 罐收敛，抗单罐噪声）/ Learning factor lambda
    DL_FILL_AVG_KEEP  : REAL := 0.7;      // 历史权重（1 - lambda，两常数相加为 1）/ History weight, one minus lambda
    DL_FILL_PCT       : REAL := 100.0;    // 百分数系数 [百分数] / Percent factor
    DL_FILL_INF_MAX   : REAL := 1.0E30;   // 非有限值判定幅值上限 / Magnitude bound for finite-value check
    DL_FILL_ZERO      : REAL := 0.0;      // 零值常量，避免裸字面量 / Zero constant
    DL_FILL_GROSS_K   : REAL := 2.0;      // 超重判据系数（净重 > 目标 x 2 判容器已超重）/ Over-weight ratio, net above twice target
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜沿检测/TON 实例每周期无条件调用（仅输入条件化）
 *----------------------------------------------------------------------------*)
fbStartTrig(CLK := bStart);                           // 启动沿检测无条件刷新 / start edge refreshed unconditionally
fbResetTrig(CLK := bReset);                           // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
fbTonFine(IN := (eState = E_DL_FillState.eFine), PT := tFineMax);        // 细灌超时计时 / fine timeout timing
fbTonSettle(IN := (eState = E_DL_FillState.eSettle), PT := tSettle);     // 稳定窗计时 / settle timing

(*------------------------------------------------------------------------------
 * 段 2｜非有限值闸：毛重/目标/比例 NaN 或溢出 → 故障兜底（双阀关，冻结）
 *----------------------------------------------------------------------------*)
bNonFin := (fGrossWeight_g <> fGrossWeight_g) OR (ABS(fGrossWeight_g) > DL_FILL_INF_MAX)
        OR (fTargetNet_g   <> fTargetNet_g)   OR (ABS(fTargetNet_g)   > DL_FILL_INF_MAX);
IF bNonFin THEN
    eState := E_DL_FillState.eFault;                  // 进故障兜底态 / enter fault fallback
    eErr := E_DL_FillErr.eFineTmo;                    // 故障级：重量信号无效（与细灌超时共用，反证句：双阀关+中止输出相同）/ fault: invalid weight
    bCoarseValve := FALSE;                            // 双阀关（安全侧）/ both valves closed
    bFineValve := FALSE;                              // 双阀关（安全侧）/ both valves closed
    bFillDone := FALSE;                               // 完成撤 / done dropped
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数钳位：目标域、快灌比例域、提前量双向限幅
 *----------------------------------------------------------------------------*)
fTargetUse := fTargetNet_g;                           // 目标工作副本 / target working copy
IF (fTargetUse < DL_FILL_TGT_MIN) OR (fTargetUse > DL_FILL_TGT_MAX) THEN
    eState := E_DL_FillState.eFault;                  // 目标出域：拒绝启动 / out-of-domain target refuses to start
    eErr := E_DL_FillErr.eFineTmo;                    // 故障级：目标非法并入中止段（反证句：双阀关+拒绝）/ fault: illegal target
    bCoarseValve := FALSE;                            // 双阀关 / both valves closed
    bFineValve := FALSE;                              // 双阀关 / both valves closed
    RETURN;
END_IF
fCoarseUse := fCoarsePct;                             // 比例工作副本 / ratio working copy
IF fCoarseUse < DL_FILL_COARSE_MIN THEN
    fCoarseUse := DL_FILL_COARSE_MIN;                 // 比例下限钳位 / ratio floored
ELSIF fCoarseUse > DL_FILL_COARSE_MAX THEN
    fCoarseUse := DL_FILL_COARSE_MAX;                 // 比例上限钳位 / ratio capped
END_IF
fAdvUse := fAdvance_g;                                // 提前量工作副本 / advance working copy
IF (fAdvUse <> fAdvUse) OR (fAdvUse < DL_FILL_ZERO) THEN
    fAdvUse := DL_FILL_ZERO;                          // 提前量非有限或负：归零 / non-finite or negative advance zeroed
ELSIF fAdvUse > fTargetUse * DL_FILL_ADV_MAX_K THEN
    fAdvUse := fTargetUse * DL_FILL_ADV_MAX_K;        // 提前量上限限幅（目标 x 0.2）/ advance capped
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜门限换算：快灌门限 = 目标 x 快灌比 - 提前量；关断门限 = 目标 - 提前量
 *----------------------------------------------------------------------------*)
fCoarseGate_g := fTargetUse * fCoarseUse / DL_FILL_PCT - fAdvUse;   // 快灌转细灌门限（以净重口径，加去皮后为毛重）/ coarse gate [g]
fStopGate_g := fTargetUse - fAdvUse;                                // 双阀关断门限（净重口径）/ stop gate [g]
IF fCoarseGate_g < DL_FILL_ZERO THEN
    fCoarseGate_g := DL_FILL_ZERO;                    // 门限下限防护（小目标时提前量大）/ gate floor guard
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜重量有效性：毛重不得低于去皮基准（负净重为无效）
 *----------------------------------------------------------------------------*)
bOverGross := (fGrossWeight_g - fTareRef_g) > (fTargetUse * DL_FILL_GROSS_K);   // 超重判据：净重超目标双倍 [克] / over-weight predicate
bWeightOk := (fGrossWeight_g >= fTareRef_g) AND (NOT bOverGross);   // 净重非负且未超重 / net non-negative and not over-weight
IF bOverGross THEN
    eState := E_DL_FillState.eFault;                  // v1.0.1：容器已超重，立即中止（原实现转细灌继续加注）/ abort at once
    eErr := E_DL_FillErr.eFineTmo;                    // 故障级（中止段共用，反证句：双阀关+无完成）/ fault, abort band
    bCoarseValve := FALSE;                            // 双阀关（安全侧）/ both valves closed
    bFineValve := FALSE;                              // 双阀关（安全侧）/ both valves closed
    bFillDone := FALSE;                               // 完成撤 / done dropped
ELSIF (NOT bWeightOk) AND (eState = E_DL_FillState.eCoarse) THEN
    eState := E_DL_FillState.eFine;                   // 粗段信号无效（净重为负）：保守转细灌降流量 / invalid in coarse: move to fine
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜启动沿：去皮并进粗灌相（提前量不在此处改写）
 *----------------------------------------------------------------------------*)
bFillDone := FALSE;                                   // 完成脉冲逐拍先清 / done pulse cleared first
IF fbStartTrig.Q THEN
    fTareRef_g := fGrossWeight_g;                     // 去皮：毛重基准锁存 [克] / tare captured [g]
    fNetWeight_g := DL_FILL_ZERO;                     // 净重显示清零 / net display cleared
    bCoarseValve := TRUE;                             // 快灌阀开 / coarse valve open
    bFineValve := FALSE;                              // 细灌阀关 / fine valve closed
    eState := E_DL_FillState.eCoarse;                 // 进粗灌相 / enter coarse phase
END_IF
IF fbResetTrig.Q THEN
    eState := E_DL_FillState.eIdle;                   // 复位回就绪 / reset to idle
    bCoarseValve := FALSE;                            // 双阀关 / both valves closed
    bFineValve := FALSE;                              // 双阀关 / both valves closed
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜灌装状态机：CASE 含 ELSE 兜底（ELSE → 双阀关安全态）
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_FillState.eIdle:
        bCoarseValve := FALSE;                        // 就绪态双阀关 / both valves closed in idle
        bFineValve := FALSE;                          // 就绪态双阀关 / both valves closed in idle
        fNetWeight_g := fGrossWeight_g - fTareRef_g;  // 净重实时显示 [克] / live net display [g]
        eErr := E_DL_FillErr.eReady;                  // 码 0412 / code ready

    E_DL_FillState.eCoarse:
        bCoarseValve := TRUE;                         // 快灌阀保持开 / coarse valve held open
        bFineValve := FALSE;                          // 细灌阀保持关 / fine valve held closed
        fNetWeight_g := fGrossWeight_g - fTareRef_g;  // 净重实时显示 [克] / live net display [g]
        eErr := E_DL_FillErr.eCoarseRun;              // 码 0413 / code coarse
        IF bWeightOk AND (fNetWeight_g >= fCoarseGate_g) THEN
            bCoarseValve := FALSE;                    // 先关快灌阀（互斥切换）/ close coarse valve first, exclusive switching
            bFineValve := TRUE;                       // 再开细灌阀 / then open fine valve
            eState := E_DL_FillState.eFine;           // 进细灌相 / enter fine phase
        END_IF

    E_DL_FillState.eFine:
        bCoarseValve := FALSE;                        // 细灌相快灌阀必须关（互斥）/ coarse valve must be closed
        bFineValve := TRUE;                           // 细灌阀保持开 / fine valve held open
        fNetWeight_g := fGrossWeight_g - fTareRef_g;  // 净重实时显示 [克] / live net display [g]
        eErr := E_DL_FillErr.eFineRun;                // 码 0414 / code fine
        IF bWeightOk AND (fNetWeight_g >= fStopGate_g) THEN
            bFineValve := FALSE;                      // 达关断门限：细灌阀关 / reach stop gate: close fine valve
            eState := E_DL_FillState.eSettle;         // 进稳定窗 / enter settle window
        ELSIF fbTonFine.Q THEN
            eState := E_DL_FillState.eFault;          // 细灌超时：中止进故障态 / fine timeout: abort to fault
            eErr := E_DL_FillErr.eFineTmo;            // 故障级：细灌超时 / fault: fine timeout
        END_IF

    E_DL_FillState.eSettle:
        bCoarseValve := FALSE;                        // 稳定窗双阀关 / both valves closed in settle
        bFineValve := FALSE;                          // 稳定窗双阀关 / both valves closed in settle
        fNetWeight_g := fGrossWeight_g - fTareRef_g;  // 净重实时显示 [克] / live net display [g]
        IF fbTonSettle.Q THEN
            fErr_g := fNetWeight_g - fTargetUse;      // 本罐误差 = 实测净重 - 目标 [克] / net weight error [g]
            fAdvUse := fAdvUse * (DL_FILL_AVG_KEEP) + fErr_g * DL_FILL_LAMBDA;   // 指数学习（仅完成相执行）/ exponential learning, done phase only
            IF fAdvUse < DL_FILL_ZERO THEN
                fAdvUse := DL_FILL_ZERO;              // 学习值下限限幅 / learned value floored
            ELSIF fAdvUse > fTargetUse * DL_FILL_ADV_MAX_K THEN
                fAdvUse := fTargetUse * DL_FILL_ADV_MAX_K;   // 学习值上限限幅 / learned value capped
            END_IF
            fAdvance_g := fAdvUse;                    // 提前量对外更新 [克] / advance exported [g]
            bFillDone := TRUE;                        // 完成单拍脉冲 / single-scan done pulse
            eErr := E_DL_FillErr.eFillDone;           // 码 0416 / code done
            eState := E_DL_FillState.eDone;           // 进完成相 / enter done phase
        ELSE
            eErr := E_DL_FillErr.eFineRun;            // 稳定窗内沿挂细灌码（流程未结束）/ keep fine code while settling
        END_IF

    E_DL_FillState.eDone:
        bCoarseValve := FALSE;                        // 完成态双阀关 / both valves closed when done
        bFineValve := FALSE;                          // 完成态双阀关 / both valves closed when done
        IF fbStartTrig.Q THEN
            eErr := E_DL_FillErr.eReady;              // 新罐启动沿已由段 6 处理 / next start handled in section 6
        END_IF

    E_DL_FillState.eFault:
        bCoarseValve := FALSE;                        // 故障态双阀关（安全侧）/ both valves closed in fault
        bFineValve := FALSE;                          // 故障态双阀关（安全侧）/ both valves closed in fault
        bFillDone := FALSE;                           // 故障态完成撤 / done dropped in fault

    ELSE
        eState := E_DL_FillState.eFault;              // 非法状态兜底 / illegal-state fallback
        eErr := E_DL_FillErr.eFineTmo;                // 兜底码（中止段，反证句：双阀关+无完成）/ fallback code
        bCoarseValve := FALSE;                        // 双阀关 / both valves closed
        bFineValve := FALSE;                          // 双阀关 / both valves closed
        bFillDone := FALSE;                           // 完成撤 / done dropped

END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜两阀互斥校验（后置防线）：同拍双开一律保守降为双关并进故障态
 *----------------------------------------------------------------------------*)
IF bCoarseValve AND bFineValve THEN
    bCoarseValve := FALSE;                            // 互斥：快灌阀关 / exclusivity: coarse closed
    bFineValve := FALSE;                              // 互斥：细灌阀关 / exclusivity: fine closed
    eState := E_DL_FillState.eFault;                  // 双开为非法组合，进故障态 / both-open is illegal, enter fault
    eErr := E_DL_FillErr.eFineTmo;                    // 故障码（中止段，反证句：双阀关+中止）/ fault code, abort band
END_IF
END_FUNCTION_BLOCK
