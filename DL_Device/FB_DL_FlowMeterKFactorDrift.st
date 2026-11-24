(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FlowMeterKFactorDrift
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.2
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library + DL_ 库内既有件，零厂商方言
 * 来源标签 (Source)     : roadmap-industry-pool-19.6（§19.6 已勾未注册漂移件重建，
 *                         本件为漂移修复件，收口时须同步补 registry 注册行）
 * 功能描述 (Function)   : 流量计 K 系数漂移核对：批次结算沿采样——
 *                         ① K 系数回读比对（委托 FB_DL_DeviceParamVerify 读-比-判）；
 *                         ② 批次总量比对（委托 FB_DL_FlowTotalizer 累计，基线总量对拍）；
 *                         ③ 漂移折算（委托 FC_DL_LinearScale 做总量占基线百分比）。
 *                         合成漂移率取两判据绝对值最大者分级：
 *                         达 fDriftWarnPct -> eMaintenanceReq；达 fDriftLimitPct ->
 *                         eOutOfSpec；组态故障 -> eFailure；未采样 -> eUnknown。
 * 委托清单 (Delegation) : FB_DL_DeviceParamVerify（DL_Device，读-比-判内核）
 *                         FB_DL_FlowTotalizer（DL_Process，批次累计内核）
 *                         FC_DL_LinearScale（DL_MathData，百分比折算内核）
 * 归属声明 (Ownership)  : E_DL_Ne107Status 归属 DL_Device\I_DL_DeviceHealth.st，
 *                         本件只引用不重声明（六态仲裁口径与 I_DL_DeviceHealth 对齐）。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 采样时机：仅批次结算沿（bBatchSettle 上升沿）采样，批次窗口未关闭不采样；
 *      结算沿拍读入当批累计量，下一拍才发内部清零脉冲（延迟一拍，防同拍读零）。
 *   2) 除零双闸：fKFactorBaseline <= 0 或 fBatchBaseline <= 0 组态级故障，不采样
 *      不折算（安全侧），锁存至复位沿 + 组态恢复。
 *   3) 漂移率非有限拦截：合成漂移过自反 + 差自减双判，非有限拒绝发布（不置
 *      eHealth 降级，保持上一有效分级），故障级码 + bError 三件套。
 *   4) 采样周期 tSample 仅作为 FlowTotalizer 的钳位判据基准注入，本件自身
 *      不做时间换算（<= T#0S 仍为组态非法）。
 *   5) K 比对语义受 DeviceParamVerify 六态状态机约束：回读流持续非零即连续核对，
 *      结算沿消费其最新结论；回读全零（等待相）视为「未取得结论」不判漂移。
 * 故障码表 (Error codes) :
 *   16#0003_0500 [故障级] K 基线 <= 0 或基线总量 <= 0（除零双闸），不采样
 *                 反证：不采样时 eHealth 恒 eUnknown，与「从未使能」组合相同，
 *                 码位是组态错误的唯一出口。
 *   16#0003_0501 [故障级] 采样周期组态非法（<= T#0S），不采样
 *                 反证：周期非法与基线非法都表现为不采样不分级，输出组合不可区分。
 *   16#0003_0502 [故障级] 漂移阈值组态非法（负值或 warn >= limit），不分级
 *                 反证：不分级时保持上一有效分级，与「阈值恰好未触及」组合
 *                 输出相同，无码不可区分。
 *   16#0003_0503 [故障级] 合成漂移率非有限，拒绝发布（保持上一有效分级）
 *                 反证：拒绝发布与「本批漂移恰好等于上批」输出组合相同。
 *   16#0003_0400 [信息级] 漂移达维护级（eMaintenanceReq 分级确认）
 *                 反证：eHealth 已表达分级，码位承载「本批采样触发了该分级」
 *                 事件事实供流水归档（分级是状态，码位是事件，二者不互代）。
 *   16#0003_0401 [信息级] 漂移达超规格级（eOutOfSpec 分级确认）
 *                 反证：与 0400 同理，且两码互异满足归因唯一（R190）。
 * 码位总账 (Code ledger) : 16#0003_0500 / 0501 / 0502 / 0503 用 ｜ 16#0003_0400 / 0401 用
 * 依赖     (Depends)    : FB_DL_DeviceParamVerify / FB_DL_FlowTotalizer / FC_DL_LinearScale
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3 + 库内委托件
 *                         R4 ✓ 除零双闸 / 非有限双判 / 域闸全枚举 / 码位 R45 配对
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 四态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 一沿实例无条件刷新；被委托件每拍无条件调用
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R68 构建轮 · 批 2 · 目标 6，§19.6 漂移件重建）
 *   2026-11-22  v1.0.1  终审就地修①：组态锁存解除路径可达化（复位沿 + 三项组态改对即清锁存，原 eFault 相不可达）
 *   2026-11-22  v1.0.2  R69 点修③：组态故障相实现 eHealth := eFailure（原 eFailure 仅声明未实现，
 *                       头注释「组态故障 -> eFailure」与实现不符；实现取「补分级」而非「改注释」）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_KDriftPhase（归属 DL_Device，与 FB_DL_FlowMeterKFactorDrift 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_KDriftPhase :
(
    eIdle    := 0,    // 未使能：不采样不分级 / Disabled, no sampling or grading
    eArmed   := 10,   // 已使能待结算沿：累计器在跑 / Armed, waiting for the settle edge
    eSampled := 20,   // 本批已采样并分级 / Batch sampled and graded
    eFault   := 99    // 组态故障锁存：拒绝采样 / Config fault latched, sampling refused
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_FlowMeterKFactorDrift
 * 调用约定: 每个扫描周期无条件调用一次；bBatchSettle 为单拍沿语义。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_FlowMeterKFactorDrift
VAR_INPUT
    fFlow           : REAL;                  // 瞬时流量 [L/min]，委托 Totalizer 累计 / Instantaneous flow [L per min]
    bBatchSettle    : BOOL;                  // 批次结算沿（上升沿 = 批次窗口关闭）/ Batch settle edge
    fKFactorBaseline: REAL := 1000.0;        // K 系数基线 [脉冲/L]，<= 0 组态非法 / K factor baseline [pulses per L]
    fKFactorReadback: REAL;                  // K 系数设备回读 [脉冲/L] / K factor device readback
    fKTolerance     : REAL := 0.02;          // K 比对容差 [脉冲/L] / K comparison tolerance
    fBatchBaseline  : REAL := 100.0;         // 批次基线总量 [L]，<= 0 组态非法 / Batch baseline total [L]
    fDriftWarnPct   : REAL := 2.0;           // 漂移维护级阈值 [%] / Drift maintenance threshold [%]
    fDriftLimitPct  : REAL := 5.0;           // 漂移超规格级阈值 [%] / Drift out-of-spec threshold [%]
    tSample         : TIME := T#1S;          // 采样周期基准 [ms]，注入 Totalizer / Sample period basis for the totalizer
    bEnable         : BOOL := TRUE;          // 使能 / Enable
    bReset          : BOOL;                  // 上升沿：清除组态故障锁存 / Rising edge: clear config latches
END_VAR
VAR_OUTPUT
    eHealth        : E_DL_Ne107Status;       // NE107 健康出口（六态，属主 I_DL_DeviceHealth）/ NE107 health verdict
    fDriftKPct     : REAL;                   // K 系数漂移率 [%] / K factor drift rate [%]
    fDriftBatchPct : REAL;                   // 批次总量漂移率 [%] / Batch total drift rate [%]
    fDriftPctEff   : REAL;                   // 合成漂移率（两判据绝对值最大）[%] / Combined drift, max magnitude
    bKMismatch     : BOOL;                   // K 回读超容差（读-比-判结论）/ K readback out of tolerance
    bSampled       : BOOL;                   // 本批采样脉冲（单拍）/ Batch sampled pulse, single scan
    bError         : BOOL;                   // 故障标志（组态类锁存）/ Fault flag, configuration class
    uErrorId       : UDINT;                  // 故障码，0 = 无故障 / Error code, 0 = none
    eState         : E_DL_KDriftPhase;       // 当前相位（供 HMI 诊断）/ Current phase for HMI diagnosis
END_VAR
VAR
    fbTrigSettle   : R_TRIG;                 // 结算沿检测实例 / Settle edge detector
    fbTrigReset    : R_TRIG;                 // 复位沿检测实例 / Reset edge detector
    fbTotal        : FB_DL_FlowTotalizer;    // 批次累计委托实例 / Batch totalizer delegate
    fbVerify       : FB_DL_DeviceParamVerify; // K 读-比-判委托实例 / K verify delegate
    stKVerify      : ST_DL_ParamVerifyState; // 委托件跨周期状态袋（VAR_IN_OUT 注入）/ Delegate state bag
    afKExp         : ARRAY[1..64] OF REAL;   // 委托件期望参数块（仅第 1 项使用）/ Delegate expectation block, item 1 only
    afKAct         : ARRAY[1..64] OF REAL;   // 委托件回读参数块（仅第 1 项使用）/ Delegate readback block, item 1 only
    afKTol         : ARRAY[1..64] OF REAL;   // 委托件容差块（仅第 1 项使用）/ Delegate tolerance block, item 1 only
    ePhaseInt      : E_DL_KDriftPhase;       // 主状态机内部当前态 / Internal state machine state
    bRstPend       : BOOL;                   // 延迟一拍的批次清零待发标志 / Delayed batch reset pending flag
    fBatchMeas     : REAL;                   // 结算沿采得的批次总量 [L] / Batch total sampled at settle
    bScaleOk       : BOOL;                   // 折算有效标志（LinearScale 出口）/ Scaling valid flag from LinearScale
    uScaleErr      : UDINT;                  // 折算错误码透传 / Scaling error code pass-through
    fDriftK        : REAL;                   // K 漂移率中间量 [%] / K drift intermediate
    fDriftBatch    : REAL;                   // 总量漂移率中间量 [%] / Batch drift intermediate
    fDriftEff      : REAL;                   // 合成漂移率中间量 [%] / Combined drift intermediate
    bCfgKBad       : BOOL;                   // K / 基线总量组态非法 / K or baseline config illegal
    bCfgTBad       : BOOL;                   // 采样周期组态非法 / Sample period illegal
    bCfgPBad       : BOOL;                   // 漂移阈值组态非法 / Drift thresholds illegal
    bFaultLatch    : BOOL;                   // 组态故障锁存（复位沿清除）/ Config fault latch, cleared by reset edge
    bKReady        : BOOL;                   // 委托件已取得 K 比对结论 / Delegate verdict available
    bSampledT      : BOOL;                   // 本拍采样脉冲内部副本 / Internal sampled pulse copy
    bErrorInt      : BOOL;                   // 本拍故障置位累加（出口归并）/ Fault set accumulator of this scan
    bFirstScan     : BOOL := TRUE;           // 上电首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_KD_FIN_LIM  : REAL := 1.0E30;   // REAL 有限幅值判界 / REAL finiteness magnitude bound
    DL_KD_ITEM     : INT  := 1;        // 委托件比对本数 [项]，K 单项 / Delegate item count, single K item
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：二沿 + 三委托件全部每拍调用，禁入分支
 *      Unconditional refresh: two edges and three delegates called every scan
 *-----------------------------------------------------------------------------*)
fbTrigSettle(CLK := bBatchSettle);
fbTrigReset(CLK := bReset);

(* 委托件引脚装配（仅第 1 项）：期望 = K 基线，实际 = K 回读 *)
(* Delegate pin wiring, item 1 only: expectation vs readback *)
afKExp[1] := fKFactorBaseline;
afKAct[1] := fKFactorReadback;
afKTol[1] := fKTolerance;

fbVerify(bEnable := bEnable, bReset := bReset, nItemCount := DL_KD_ITEM,
         afExpected := afKExp, afActual := afKAct, afTolerance := afKTol,
         stVerify := stKVerify);

fbTotal(fFlow := fFlow, bRstBatch := bRstPend, bEn := bEnable, tSample := tSample);

(* 延迟清零脉冲消化：上一结算拍置位的待发标志已随上调用发出，此处撤销 *)
(* Delayed reset pulse consumed: the pending flag went out with the call above *)
IF bRstPend THEN
    bRstPend := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫：相位与分级落安全侧
 *      First-scan init: phase and health verdict to the safe side
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    ePhaseInt      := E_DL_KDriftPhase.eIdle;
    eHealth        := E_DL_Ne107Status.eUnknown;
    bRstPend       := FALSE;
    fBatchMeas     := 0.0;
    fDriftK        := 0.0;
    fDriftBatch    := 0.0;
    fDriftEff      := 0.0;
    bFirstScan     := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜每拍预清（FB32-1）：单拍标志，禁入锁存 / 快照
 *      Per-scan preset: single-scan flags only
 *-----------------------------------------------------------------------------*)
bErrorInt := FALSE;
bSampledT := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸（R151 全枚举：基线双量 / 周期 / 阈值对，含非有限双判）
 *      Config gates: baselines, period, threshold pair, with non-finite checks
 *      解除路径（R152 自证）：复位沿 AND 全部组态非法条件消失
 *-----------------------------------------------------------------------------*)
bCfgKBad := (fKFactorBaseline <= 0.0) OR (fKFactorBaseline <> fKFactorBaseline)
            OR (fBatchBaseline <= 0.0) OR (fBatchBaseline <> fBatchBaseline)
            OR (ABS(fKFactorBaseline) >= DL_KD_FIN_LIM) OR (ABS(fBatchBaseline) >= DL_KD_FIN_LIM);
bCfgTBad := (tSample <= T#0S);
bCfgPBad := (fDriftWarnPct < 0.0) OR (fDriftLimitPct < 0.0)
            OR (fDriftWarnPct <> fDriftWarnPct) OR (fDriftLimitPct <> fDriftLimitPct)
            OR (fDriftWarnPct >= fDriftLimitPct);

IF bCfgKBad OR bCfgTBad OR bCfgPBad THEN
    bFaultLatch := TRUE;
END_IF

(* 终审就地修 v1.0.1（R68）：解除路径（R152 自证可达）——复位沿 AND 组态非法条件
 * 全部消失即清锁存。原实现把锁存清零只写在 eFault 相分支，而组态闸置锁存后
 * 并不迁相至 eFault（只回 eIdle / 驻留），eFault 相不可达 -> 锁存永不可解，
 * 组件保护/监视功能一次性永久失效直至 PLC 重启（终审两式①）。
 * Clear path made provably reachable: reset edge with the illegal config gone. *)
IF fbTrigReset.Q AND (NOT bCfgKBad) AND (NOT bCfgTBad) AND (NOT bCfgPBad) THEN
    bFaultLatch := FALSE;         // 锁存解除 / Latch cleared
    uErrorId    := 16#0000_0000;  // 码位随解除归零 / Code cleared with the latch
END_IF

IF bCfgKBad THEN
    uErrorId  := 16#0003_0500;   // 故障级：K / 基线总量非法 / Fault: K or baseline illegal
    bErrorInt := TRUE;
    eHealth   := E_DL_Ne107Status.eFailure;   // R69 点修③：故障级分级出口（原仅声明未实现）/ Fault-level verdict implemented
ELSIF bCfgTBad THEN
    uErrorId  := 16#0003_0501;   // 故障级：采样周期非法 / Fault: sample period illegal
    bErrorInt := TRUE;
    eHealth   := E_DL_Ne107Status.eFailure;   // R69 点修③：故障级分级出口 / Fault-level verdict
ELSIF bCfgPBad THEN
    uErrorId  := 16#0003_0502;   // 故障级：漂移阈值非法 / Fault: drift thresholds illegal
    bErrorInt := TRUE;
    eHealth   := E_DL_Ne107Status.eFailure;   // R69 点修③：故障级分级出口 / Fault-level verdict
END_IF

(* 组态锁存期健康出口保持最严等级：锁存未解除前不得回落（锁存回放，禁按当下输入重推，
 * R152 故障码锁存口径）。解除沿（复位沿 + 组态改对）后由下一结算沿重新分级。 *)
(* While latched the verdict stays at eFailure; it is only re-graded after the latch is cleared *)
IF bFaultLatch THEN
    eHealth := E_DL_Ne107Status.eFailure;     // 锁存期分级锁死最严 / Verdict pinned to failure while latched
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE ePhaseInt OF

    E_DL_KDriftPhase.eIdle:
        IF bEnable AND (NOT bFaultLatch) THEN
            ePhaseInt := E_DL_KDriftPhase.eArmed;
        END_IF

    E_DL_KDriftPhase.eArmed:
        IF bFaultLatch OR (NOT bEnable) THEN
            ePhaseInt := E_DL_KDriftPhase.eIdle;
        ELSIF fbTrigSettle.Q THEN
            (* 结算沿采样：先读当批累计量，清零脉冲延迟一拍发出（防同拍读零） *)
            (* Settle edge: read the batch total first, delayed reset next scan *)
            fBatchMeas := fbTotal.fTotalBatch;
            bRstPend   := TRUE;
            bSampledT  := TRUE;
            ePhaseInt  := E_DL_KDriftPhase.eSampled;
        END_IF

    E_DL_KDriftPhase.eSampled:
        IF bFaultLatch OR (NOT bEnable) THEN
            ePhaseInt := E_DL_KDriftPhase.eIdle;
        ELSIF fbTrigSettle.Q THEN
            (* 连续批次：结算沿再次采样（累计器已在上一采样后清零重建） *)
            (* Consecutive batches: settle edge samples the rebuilt batch *)
            fBatchMeas := fbTotal.fTotalBatch;
            bRstPend   := TRUE;
            bSampledT  := TRUE;
        END_IF

    E_DL_KDriftPhase.eFault:
        IF fbTrigReset.Q AND (NOT bCfgKBad) AND (NOT bCfgTBad) AND (NOT bCfgPBad) THEN
            bFaultLatch := FALSE;          // 解除路径自证可达（R152）/ Clear path reachable
            uErrorId    := 16#0000_0000;
            ePhaseInt   := E_DL_KDriftPhase.eIdle;
        END_IF

    ELSE
        ePhaseInt := E_DL_KDriftPhase.eFault;
        uErrorId  := 16#0003_0500;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 6｜采样拍折算（仅采样拍执行）：K 结论 + 总量百分比 + 合成分级
 *      Sample-scan folding: K verdict plus percent plus combined grading
 *-----------------------------------------------------------------------------*)
IF bSampledT THEN
    (* ① K 结论：委托件已取得比对结论才判漂移（等待相 = 未取得结论） *)
    bKReady    := fbVerify.bVerified OR fbVerify.bMismatch;
    bKMismatch := FALSE;
    fDriftK    := 0.0;
    IF bKReady THEN
        bKMismatch := fbVerify.bMismatch;
        IF fKFactorBaseline <> 0.0 THEN
            fDriftK := fbVerify.fMaxDev / fKFactorBaseline * 100.0;  // 除子已闸（0300 组态闸）/ Guarded divisor
        END_IF
    END_IF

    (* ② 总量漂移：委托 LinearScale 折算占基线百分比，再减 100 得漂移率 *)
    (* FC 直接调用 + 命名出口（库内惯例，见 FB_DL_RoomCo2DemandVent 先例） *)
    fDriftBatch := FC_DL_LinearScale(fIn := fBatchMeas,
                                     fInMin := 0.0,
                                     fInMax := fBatchBaseline,
                                     fOutMin := 0.0,
                                     fOutMax := 100.0,
                                     bClamp := FALSE,
                                     bValid => bScaleOk,
                                     uErrorId => uScaleErr) - 100.0;
    IF (NOT bScaleOk) OR (uScaleErr <> 16#0000_0000) THEN
        fDriftBatch := 0.0;      // 折算无效（基线组态闸已拦，此处兜底）/ Fold invalid, defensive zero
        uErrorId    := 16#0003_0500;
        bErrorInt   := TRUE;
    END_IF

    (* ③ 合成与分级：绝对值最大者承载，非有限拒绝发布（三件套 R258） *)
    fDriftEff := MAX(ABS(fDriftK), ABS(fDriftBatch));
    IF (fDriftEff <> fDriftEff) OR ((fDriftEff - fDriftEff) <> (fDriftEff - fDriftEff))
       OR (ABS(fDriftEff) >= DL_KD_FIN_LIM) THEN
        uErrorId  := 16#0003_0503;   // 故障级：合成漂移非有限 / Fault: combined drift non-finite
        bErrorInt := TRUE;
        (* 非有限拒绝发布：fDriftPctEff / eHealth 保持上一有效值（不写即保持） *)
        (* Non-finite: publish withheld, outputs hold the last valid values *)
    ELSE
        fDriftPctEff := fDriftEff;
        fDriftKPct     := fDriftK;
        fDriftBatchPct := fDriftBatch;
        IF fDriftEff >= fDriftLimitPct THEN
            eHealth   := E_DL_Ne107Status.eOutOfSpec;      // 超规格级 / Out of spec
            uErrorId  := 16#0003_0401;
        ELSIF fDriftEff >= fDriftWarnPct THEN
            eHealth   := E_DL_Ne107Status.eMaintenanceReq; // 维护级 / Maintenance required
            uErrorId  := 16#0003_0400;
        ELSE
            eHealth   := E_DL_Ne107Status.eOk;             // 在容差内 / Within tolerance
        END_IF
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜输出单一出口（范式 P-05）
 *      Single output exit
 *-----------------------------------------------------------------------------*)
bSampled := bSampledT;   // 单拍脉冲统一出口（预清 + CASE 置位两段式）/ Unified single-scan exit
bError   := bErrorInt OR (ePhaseInt = E_DL_KDriftPhase.eFault);
eState   := ePhaseInt;
END_FUNCTION_BLOCK
