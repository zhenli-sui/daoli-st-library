(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FlowTotalizer
 * 所属子库 (Sublibrary) : DL_Process
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准库 TON / R_TRIG / ABS / MAX / MIN，零厂商方言
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 流量累积与批控公开语义（行业池），道莅 clean-room
 *                         防御性实现，未复制任何外部源码行
 * 功能描述 (Function)   : 流量累积与批控零点件。累积量 ΔV = fFlow·Δt，Δt 取
 *                         实际运行时间差（计时器实测经过值差分，非定时器
 *                         假设值）防扫描抖动误差；清零沿先保存结算快照再
 *                         清批次；寿命累计饱和于 DL_TOTAL_MAX 防溢出。
 *                         与库内 EnergyMeterAccum 边界：该件为千瓦时电量
 *                         口径，本件为升流量口径，二者不合并。
 * 码位     (Codes)      : 16#0005_00AD 信息级：流量非有限按零积分、Δt 越界
 *                                      按上次有效值钳位、批满提示（不置
 *                                      bError，规格仅信息级）
 *                         16#0005_00AE~00B1 保留未启用（码表与实现对齐）
 *                         偏离：uErrorId 规格标 UINT，段位码超 UINT 值域，
 *                         按 32 位载体 UDINT 落地（与库内段位码惯例一致）
 * 边界防错 (Boundary)   : 1 fFlow 非有限本拍按 0 积分记信息码不中断；
 *                         2 Δt 不大于零或超扫描周期 10 倍按上次有效值钳位；
 *                         3 清零沿与积分同拍冲突先积分后清零（不丢该拍）；
 *                         4 bBatchFull 置位有销位路径：bRstBatch 清零沿；
 *                         5 TON/R_TRIG 实例每拍无条件刷新；
 *                         6 首扫同步时标基准防上电尖峰。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 15）
 *==============================================================================*)

(*==============================================================================
 * 功能块: FB_DL_FlowTotalizer
 * 调用约定: 每个扫描周期无条件调用一次；tSample 为名义采样周期（钳位判据
 *           用），实际 Δt 取计时器经过值差分。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_FlowTotalizer
VAR_INPUT
    fFlow      : REAL := 0.0;         // 瞬时流量 [升每分钟] / Instantaneous flow [L per min]
    bRstBatch  : BOOL := FALSE;        // 批次清零沿 / Batch reset edge
    bEn        : BOOL := FALSE;        // 使能 / Enable flag
    tSample    : TIME := T#1S;         // 名义采样周期 [毫秒]（钳位判据基准）/ Nominal sample period [ms], clamp basis
    fBatchLimit: REAL := 1000.0;      // 批量限值 [升]（可增引脚）/ Batch volume limit [L], added pin
END_VAR
VAR_OUTPUT
    fTotalBatch: REAL;                 // 批次累计量 [升] / Batch total [L]
    fTotalLife : REAL;                 // 寿命累计量 [升] / Lifetime total [L]
    bBatchFull : BOOL;                 // 批满标志（清零沿销位）/ Batch full flag, cleared by reset edge
    uErrorId   : UDINT;                // 信息级码，0 = 无信息（段位码 32 位载体，规格 UINT 值域不足，偏离留档）/ Info code, 0 = none, 32-bit carrier deviation
END_VAR
VAR
    rTrigRst   : R_TRIG;               // 清零沿检测，每拍无条件刷新 / Reset edge detector, refreshed every scan
    tonMeter   : TON;                  // 实际运行时标（大超时经过值表）/ Run-time meter, elapsed register
    fEtPrev    : REAL;                 // 上拍经过值 [毫秒] / Previous elapsed [ms]
    fEtNow     : REAL;                 // 本拍经过值 [毫秒] / Current elapsed [ms]
    fDtMs      : REAL;                 // 有效时间差 [毫秒] / Effective delta time [ms]
    fDtSec     : REAL;                 // 有效时间差 [秒] / Effective delta time [s]
    bFirst     : BOOL := TRUE;         // 首扫标志 / First-scan flag
    fBatchSnap : REAL;                 // 清零前结算快照 [升] / Batch snapshot before reset [L]
    bFlowBad   : BOOL;                 // 本拍流量非有限 / Flow non-finite this scan
    bDtClamp   : BOOL;                 // 本拍 Δt 越界钳位 / Delta time clamped this scan
    fFlowEff   : REAL;                 // 本拍生效流量 [升每分钟] / Effective flow [L per min]
END_VAR
VAR CONSTANT
    DL_FT_FIN     : REAL  := 1.0E30;   // REAL 有限幅值判界 / REAL finiteness magnitude bound
    DL_FT_DTMAXF  : REAL  := 10.0;     // Δt 越界倍率（名义周期十倍）/ Delta time overrange factor
    DL_FT_TOTALMAX: REAL  := 1.0E12;   // 寿命累计饱和上限 [升] / Lifetime saturation ceiling [L]
    DL_FT_SEC     : REAL  := 1000.0;   // 毫秒到秒换算系数 / Millisecond to second factor
END_VAR

// ---- 段 1｜边沿与计时实例无条件刷新（红线：禁入条件分支）----------------------
rTrigRst(CLK := bRstBatch);                           // 清零沿检测 / Reset edge detection
tonMeter(IN := bEn, PT := T#4294967MS);               // 运行时标，使能即累计 / Run-time meter, accumulates while enabled

// ---- 段 2｜实际时间差分（非定时器假设值）--------------------------------------
fEtNow := TIME_TO_REAL(tonMeter.ET);                  // 本拍经过值 [毫秒] / Current elapsed [ms]
fDtMs  := fEtNow - fEtPrev;                           // 实际时间差 [毫秒] / Real delta time [ms]
bDtClamp := FALSE;                                    // 钳位标志先清 / Clear clamp flag
IF bFirst OR (fDtMs <= 0.0) OR (fDtMs > TIME_TO_REAL(tSample) * DL_FT_DTMAXF) THEN
    fDtMs := TIME_TO_REAL(tSample);                   // 首扫或越界按名义周期钳位 / First scan or out-of-range clamped
    bDtClamp := NOT bFirst;                           // 非首扫才记钳位信息 / Clamp info only after first scan
END_IF
fEtPrev := fEtNow;                                    // 快照留痕 / Snapshot previous elapsed
bFirst := FALSE;                                      // 清首扫标志 / Clear first-scan flag
fDtSec := fDtMs / DL_FT_SEC;                          // 换算秒 [秒] / Convert to seconds

// ---- 段 3｜流量有效性（非有限按零积分不中断）----------------------------------
bFlowBad := (fFlow <> fFlow) OR (ABS(fFlow) >= DL_FT_FIN); // 流量非有限判定 / Flow non-finite detection
IF bFlowBad THEN
    fFlowEff := 0.0;                                  // 非有限按零积分 / Non-finite integrates as zero
ELSE
    fFlowEff := fFlow;                                // 有效原值 / Valid value as-is
END_IF

// ---- 段 4｜积分（先积分后清零：同拍冲突不丢该拍）------------------------------
IF bEn THEN
    fTotalBatch := fTotalBatch + fFlowEff * fDtSec / 60.0; // 批次积分 ΔV=f·Δt / Batch integrates flow over time
    IF fTotalLife < DL_FT_TOTALMAX THEN
        fTotalLife := MIN(fTotalLife + fFlowEff * fDtSec / 60.0, DL_FT_TOTALMAX); // 寿命累计饱和防溢出 / Lifetime saturates
    END_IF
END_IF

// ---- 段 5｜批满判定（置位有销位路径：清零沿）----------------------------------
IF fTotalBatch >= fBatchLimit THEN
    bBatchFull := TRUE;                               // 批满置位 / Batch full set
END_IF

// ---- 段 6｜清零沿：先保存结算快照再清批次（批满标志同拍销位）------------------
IF rTrigRst.Q THEN
    fBatchSnap  := fTotalBatch;                       // 结算快照留档 / Settlement snapshot kept
    fTotalBatch := 0.0;                               // 批次清零 / Batch cleared
    bBatchFull  := FALSE;                             // 批满标志销位 / Batch full cleared
END_IF

// ---- 段 7｜信息级码装配（不置故障标志，规格仅信息级）--------------------------
IF bFlowBad OR bDtClamp THEN
    uErrorId := 16#0005_00AD;                         // 信息级：非有限/钳位 / Info: non-finite or clamp
ELSIF bBatchFull THEN
    uErrorId := 16#0005_00AD;                         // 信息级：批满提示 / Info: batch full
ELSE
    uErrorId := 16#0000_0000;                         // 无码 / No code
END_IF
END_FUNCTION_BLOCK
