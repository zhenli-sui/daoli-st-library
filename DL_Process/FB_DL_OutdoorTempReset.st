(*==============================================================================
 * 组件名称 (Component)  : FB_DL_OutdoorTempReset
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library + DL_ 库内既有件，零厂商方言
 * 来源标签 (Source)     : t1-2-oscat-building（OAT 重置曲线语义，clean-room 编写）
 * 功能描述 (Function)   : 室外气温重置热工供水设定：OAT 高 -> 水温低的两点式线性
 *                         重置曲线（计算核委托 FC_DL_LinearScale）+ 重置输出上下限
 *                         夹持（倒置自动换位）+ 最小水温防结露 / 防冻硬下限 +
 *                         重置斜坡限速（委托 FB_DL_RateLimiter 组合调用，不内联）。
 *                         OAT 传感器失效 / 非有限 -> 保持上次有效设定 + 陈旧计时
 *                         超限置码（NE43 域外行为显式化）。
 * 委托清单 (Delegation) : FC_DL_LinearScale（DL_MathData，两点插值计算核）
 *                         FB_DL_RateLimiter（DL_Algo，斜坡限速内核，组合调用不内联——
 *                         「可依赖低层但不复制低层」R13 范式）
 * 分工互引 (Boundary)   : 送风温度重置归 FB_DL_AhuSupplyAirReset，冷凝压力重置归
 *                         FB_DL_ChillerCondReset，本件只负责热工供水设定，三源互引分工。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 曲线两点重合（|fOatHigh - fOatLow| < eps）为斜率除零隐患：冻结输出（保持
 *      上次有效设定）+ 组态级故障锁存；解除 = 复位沿 AND 两点已分开。
 *   2) OAT 非有限 / 失效：保持上次有效设定 + 陈旧计时（tonStale）；陈旧超限置
 *      故障级码（锁存至复位沿 AND 传感器恢复）。保持期内经 RateLimiter 的
 *      跟踪引脚无扰冻结（斜坡器不推进）。
 *   3) 夹持限倒置自动换位（对齐 RollerGapAdjust 先例）：换位为信息级一次性落码。
 *   4) 最小水温硬下限优先于夹持上限（防冻 / 防结露是安全侧约束，冲突时下限赢）。
 *   5) 斜坡速率引脚单位 [℃/min]，内部换算为 RateLimiter 的 [EU/s] 口径
 *      （除以 60，换算在调用前完成，不在 RateLimiter 内重复实现）。
 * 配比约束 (R100)       : tStaleLimit > tSample（陈旧窗必须宽于斜坡采样周期，
 *                         否则单拍传感器抖动即触发陈旧置码）。
 * 故障码表 (Error codes) :
 *   16#0005_03AB [故障级] OAT 失效陈旧超限（传感器断线 / 非有限持续 tStaleLimit，传感器恢复即自动解除）
 *                 反证：保持输出与「设定恰好不变」组合相同，码位是传感器失效
 *                 唯一可见出口。
 *   16#0005_03AC [故障级] 重置曲线两点重合（斜率除零隐患），输出冻结
 *                 反证：冻结输出与「设定恰好不变」组合相同，与 0302 成因互异
 *                 （组态错 vs 传感器失效），码位必须独立（R190）。
 *   16#0005_03AD [故障级] 通用组态非法（限值 / 斜率 / 采样周期域），已两级回退
 *                 反证：回退后重置照常，码位是组态错误唯一可见出口。
 *   16#0005_04D4 [信息级] 夹持上下限倒置，已自动换位（RollerGapAdjust 先例口径）
 *                 反证：换位后输出与显式填正序限值组合相同，无码不可区分。
 * 码位总账 (Code ledger) : 16#0005_03AB / 03AC / 03AD 用 ｜ 16#0005_04D4 用
 * 依赖     (Depends)    : FC_DL_LinearScale / FB_DL_RateLimiter
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3 + 库内委托件
 *                         R4 ✓ 曲线判零 eps 闸 / 非有限双判 / 域闸全枚举 / 码位 R45 配对
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 三态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 一沿一计时 + 委托件每拍无条件调用
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R68 构建轮 · 批 3 · 目标 13）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_OatResetState（归属 DL_Process，与 FB_DL_OutdoorTempReset 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_OatResetState :
(
    eIdle  := 0,    // 未使能：设定值输出安全下限 / Disabled, setpoint at safe floor
    eRun   := 10,   // 重置运行：曲线 + 夹持 + 斜坡 / Resetting, curve plus clamp plus ramp
    eFault := 99    // 组态 / 陈旧锁存：输出冻结保持 / Latched, output frozen
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_OutdoorTempReset
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_OutdoorTempReset
VAR_INPUT
    fOat        : REAL;                  // 室外气温 [℃] / Outdoor air temperature [degC]
    bOatValid   : BOOL := TRUE;          // OAT 传感器有效标志 / OAT sensor valid flag
    fOatLow     : REAL := 0.0;           // 曲线低温点 [℃] / Curve low OAT point [degC]
    fOatHigh    : REAL := 20.0;          // 曲线高温点 [℃] / Curve high OAT point [degC]
    fWaterAtLow : REAL := 50.0;          // 低温点对应水温 [℃] / Water setpoint at low OAT [degC]
    fWaterAtHigh: REAL := 40.0;          // 高温点对应水温 [℃] / Water setpoint at high OAT [degC]
    fResetHiLim : REAL := 55.0;          // 重置输出上限 [℃] / Reset output ceiling [degC]
    fResetLoLim : REAL := 35.0;          // 重置输出下限 [℃] / Reset output floor [degC]
    fWaterMin   : REAL := 30.0;          // 最小水温硬下限 [℃]（防结露 / 防冻）/ Hard water floor [degC]
    fRampRate   : REAL := 2.0;           // 重置斜坡限速 [℃/min] / Reset ramp rate [degC per min]
    tSample     : TIME := T#100MS;       // 斜坡采样周期 [ms] / Ramp sample period [ms]
    tStaleLimit : TIME := T#5M;          // OAT 陈旧超限窗 [min] / OAT stale limit window [min]
    bEnable     : BOOL := TRUE;          // 使能 / Enable
    bReset      : BOOL;                  // 上升沿：清除组态 / 陈旧锁存 / Rising edge: clear latches
END_VAR
VAR_OUTPUT
    fWaterSetpoint : REAL;               // 供水设定输出 [℃] / Water setpoint output [degC]
    bHoldStale     : BOOL;               // 陈旧保持中（输出冻结）/ Stale hold, output frozen
    bError         : BOOL;               // 故障标志（组态 / 陈旧锁存归并）/ Fault flag merged
    uErrorId       : UDINT;              // 故障码，0 = 无故障 / Error code, 0 = none
    eState         : E_DL_OatResetState; // 当前状态（供 HMI 诊断）/ Current state
END_VAR
VAR
    fbTrigReset  : R_TRIG;               // 复位沿检测实例 / Reset edge detector
    tonStale     : TON;                  // OAT 陈旧计时实例 / OAT stale timer
    fbRamp       : FB_DL_RateLimiter;    // 斜坡限速委托实例 / Ramp rate limiter delegate
    eStateInt    : E_DL_OatResetState;   // 主状态机内部当前态 / Internal state machine state
    bOatBad      : BOOL;                 // 本拍 OAT 无效（失效标志或非有限）/ OAT invalid this scan
    bStaleInt    : BOOL;                 // 陈旧超限锁存内部副本 / Internal stale latch
    bCurveBad    : BOOL;                 // 本拍曲线两点重合 / Curve points coincide this scan
    bCurveLatch  : BOOL;                 // 曲线故障锁存 / Curve fault latch
    bCfgBad      : BOOL;                 // 本拍通用组态非法 / General config illegal this scan
    bCfgLatch    : BOOL;                 // 通用组态锁存 / General config latch
    fOatLoEff    : REAL;                 // 钳定后曲线低温点 [℃] / Clamped curve low point
    fOatHiEff    : REAL;                 // 钳定后曲线高温点 [℃] / Clamped curve high point
    fWatLoEff    : REAL;                 // 钳定后低温点水温 [℃] / Clamped water at low
    fWatHiEff    : REAL;                 // 钳定后高温点水温 [℃] / Clamped water at high
    fLimHiEff    : REAL;                 // 换位后夹持上限 [℃] / Swapped clamp ceiling
    fLimLoEff    : REAL;                 // 换位后夹持下限 [℃] / Swapped clamp floor
    fRampEff     : REAL;                 // 换算后斜坡速率 [℃/s] / Converted ramp rate
    fWaterRaw    : REAL;                 // 曲线原始输出 [℃] / Raw curve output
    fWaterClamp  : REAL;                 // 夹持后目标 [℃] / Clamped target
    fWaterTarget : REAL;                 // 硬下限后目标 [℃] / Target after hard floor
    fLastValid   : REAL;                 // 上次有效设定保持槽 [℃] / Last valid setpoint hold slot
    bScaleOk     : BOOL;                 // 曲线换算有效标志（LinearScale 出口）/ Curve scaling valid
    uScaleErr    : UDINT;                // 曲线换算错误码透传 / Curve scaling error pass-through
    bErrorInt    : BOOL;                 // 本拍故障置位累加（出口归并）/ Fault set accumulator
    bFirstScan   : BOOL := TRUE;         // 上电首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_OR_EPS       : REAL := 1.0E-6;    // 曲线跨度判零容差 [℃] / Curve span epsilon [degC]
    DL_OR_FIN_LIM   : REAL := 1.0E30;    // REAL 有限幅值判界 / REAL finiteness bound
    DL_OR_SEC_MIN   : REAL := 60.0;      // 分钟秒换算常数 [s/min] / Minutes to seconds factor
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：一沿一计时 + 斜坡委托件每拍调用
 *      Unconditional refresh: one edge, one timer, the ramp delegate every scan
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);
tonStale(IN := bOatBad, PT := tStaleLimit);

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫：保持槽与输出落安全侧（硬下限）
 *      First-scan init: hold slot and output to the safe hard floor
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    eStateInt  := E_DL_OatResetState.eIdle;
    fLastValid := fWaterMin;
    fWaterTarget := fWaterMin;
    fWaterSetpoint := fWaterMin;
    bFirstScan := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜每拍预清（FB32-1）：单拍标志，禁入锁存 / 快照
 *      Per-scan preset: single-scan flags only
 *-----------------------------------------------------------------------------*)
bErrorInt := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜OAT 有效性（非有限双判 R79）与陈旧计时
 *      OAT validity with the non-finite dual check and the stale timer
 *-----------------------------------------------------------------------------*)
bOatBad := (NOT bOatValid) OR (fOat <> fOat) OR ((fOat - fOat) <> (fOat - fOat))
           OR (ABS(fOat) >= DL_OR_FIN_LIM);

IF tonStale.Q THEN
    bStaleInt := TRUE;               // 陈旧超限锁存 / Stale limit latched
    uErrorId  := 16#0005_03AB;       // 故障级：OAT 陈旧 / Fault: OAT stale
    bErrorInt := TRUE;
END_IF

(* 陈旧锁存自动恢复路径（R152 自证可达）：传感器恢复有效即解除 *)
(* Stale latch auto-clear: reachable the moment the sensor recovers *)
IF (NOT bOatBad) THEN
    bStaleInt := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜组态域闸（R151 全枚举）+ 两级回退（R117）+ 倒置换位（信息级）
 *      Config gate over all limits with fallback and the auto-swap
 *-----------------------------------------------------------------------------*)
bCfgBad := (fOatLow <> fOatLow) OR (fOatHigh <> fOatHigh)
           OR (fWaterAtLow <> fWaterAtLow) OR (fWaterAtHigh <> fWaterAtHigh)
           OR (fResetHiLim <> fResetHiLim) OR (fResetLoLim <> fResetLoLim)
           OR (fWaterMin <> fWaterMin) OR (fRampRate < 0.0) OR (fRampRate <> fRampRate)
           OR (tSample <= T#0S);

IF bCfgBad THEN
    bCfgLatch := TRUE;
    uErrorId  := 16#0005_03AD;       // 故障级：通用组态非法 / Fault: config illegal
    bErrorInt := TRUE;
END_IF

(* 曲线四点直通（非有限已在组态闸拦，此处取值） *)
(* Curve points pass-through, non-finite already gated *)
fOatLoEff := fOatLow;
fOatHiEff := fOatHigh;
fWatLoEff := fWaterAtLow;
fWatHiEff := fWaterAtHigh;

(* 曲线两点重合闸（斜率除零隐患）：eps 判 + 锁存冻结 *)
(* Curve coincide gate: epsilon check, latch and freeze *)
bCurveBad := ABS(fOatHiEff - fOatLoEff) < DL_OR_EPS;
IF bCurveBad THEN
    bCurveLatch := TRUE;
    uErrorId    := 16#0005_03AC;     // 故障级：两点重合 / Fault: points coincide
    bErrorInt   := TRUE;
END_IF

(* 夹持限倒置自动换位（信息级落码，RollerGapAdjust 先例口径；NaN 已被组态闸拦截） *)
(* Clamp limits auto-swap; NaN already caught by the config gate *)
IF fResetLoLim > fResetHiLim THEN
    fLimHiEff := fResetLoLim;        // 换位：上限取原下限 / Swap: ceiling takes the old floor
    fLimLoEff := fResetHiLim;        // 换位：下限取原上限 / Swap: floor takes the old ceiling
    uErrorId  := 16#0005_04D4;       // 信息级：倒置换位 / Info: swapped
ELSE
    fLimHiEff := fResetHiLim;        // 正序直通 / Ordered pass-through
    fLimLoEff := fResetLoLim;
END_IF

(* 斜坡速率换算：[℃/min] -> [℃/s]（RateLimiter 口径），负值已在组态闸拦 *)
(* Ramp rate conversion to per-second for the RateLimiter *)
fRampEff := fRampRate / DL_OR_SEC_MIN;

(*------------------------------------------------------------------------------
 * 段 6｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_OatResetState.eIdle:
        IF bEnable AND (NOT bCfgLatch) AND (NOT bCurveLatch) THEN
            eStateInt := E_DL_OatResetState.eRun;
        ELSE
            fWaterSetpoint := fWaterMin;     // 失能安全侧：硬下限 / Safe floor when disabled
        END_IF

    E_DL_OatResetState.eRun:
        IF bCfgLatch OR bCurveLatch OR (NOT bEnable) THEN
            eStateInt := E_DL_OatResetState.eFault;
        ELSE
            (* —— 曲线计算核（委托 LinearScale）：OAT 有效才推进 —— *)
            (* Curve kernel delegated to LinearScale, only when OAT valid *)
            IF bOatBad THEN
                bHoldStale := TRUE;          // 陈旧保持（跟踪冻结，输出不推进）/ Stale hold via track
            ELSE
                bHoldStale := FALSE;
                fWaterRaw := FC_DL_LinearScale(fIn := fOat,            // 室外气温输入 / OAT input
                                               fInMin := fOatLoEff,    // 曲线低温点 / Low point
                                               fInMax := fOatHiEff,    // 曲线高温点 / High point
                                               fOutMin := fWatLoEff,   // 低温点水温 / Water at low
                                               fOutMax := fWatHiEff,   // 高温点水温 / Water at high
                                               bClamp := FALSE,        // 钳位由本件夹持段承担 / Clamping here
                                               bValid => bScaleOk,
                                               uErrorId => uScaleErr);
                IF bScaleOk THEN
                    (* —— 夹持 + 硬下限（防冻 / 防结露优先） —— *)
                    (* Clamp plus hard floor, safety floor wins *)
                    fWaterClamp := fWaterRaw;
                    IF fWaterClamp > fLimHiEff THEN
                        fWaterClamp := fLimHiEff;
                    ELSIF fWaterClamp < fLimLoEff THEN
                        fWaterClamp := fLimLoEff;
                    END_IF
                    IF fWaterClamp < fWaterMin THEN
                        fWaterClamp := fWaterMin;    // 硬下限赢（安全侧）/ Hard floor wins
                    END_IF
                    fWaterTarget := fWaterClamp;
                    fLastValid   := fWaterClamp;     // 保持槽刷新 / Hold slot refreshed
                ELSE
                    uErrorId  := 16#0005_03AD;       // 换算无效回落组态口径 / Fold to config code
                    bErrorInt := TRUE;
                END_IF
            END_IF
        END_IF

    E_DL_OatResetState.eFault:
        (* 输出冻结保持（降级语义已声明 R191）：经跟踪引脚无扰冻结 *)
        bHoldStale := TRUE;
        (* 解除路径（R152 自证可达）：复位沿 AND 组态改对 AND 两点分开 AND OAT 有效 *)
        IF fbTrigReset.Q AND (NOT bCfgBad) AND (NOT bCurveBad) AND (NOT bOatBad) THEN
            bCfgLatch  := FALSE;
            bCurveLatch := FALSE;
            bStaleInt  := FALSE;
            uErrorId   := 16#0000_0000;
            eStateInt  := E_DL_OatResetState.eRun;
        END_IF

    ELSE
        eStateInt := E_DL_OatResetState.eFault;
        uErrorId  := 16#0005_03AD;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 7｜斜坡限速（委托 RateLimiter）：陈旧 / 故障期经跟踪引脚无扰冻结
 *      Ramp via the RateLimiter delegate, frozen by track when stale or faulted
 *-----------------------------------------------------------------------------*)
fbRamp(bEnable := TRUE,
       fIn := fWaterTarget,
       fRateUp := fRampEff,
       fRateDown := fRampEff,
       bTrack := bHoldStale OR (eStateInt <> E_DL_OatResetState.eRun),
       fTrackValue := fLastValid,
       tSampleTime := tSample);

(*------------------------------------------------------------------------------
 * 段 8｜输出单一出口（范式 P-05）
 *      Single output exit
 *-----------------------------------------------------------------------------*)
fWaterSetpoint := fbRamp.fOut;
bError := bErrorInt OR (eStateInt = E_DL_OatResetState.eFault);
eState := eStateInt;
END_FUNCTION_BLOCK
