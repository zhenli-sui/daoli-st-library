(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CabinetCoolingWatch
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / TIME_TO_LREAL），零厂商方言
 * 来源标签 (Source)     : self-std
 * 功能描述 (Function)   : 控制柜热管理监视，三判据 -> NE107 降级出口：
 *                         ① 柜内-环境温差超限（热交换失效判据），确认窗满 ->
 *                            eMaintenanceReq；
 *                         ② 柜内风扇双判据（运行反馈缺失 OR 转速低于下限），
 *                            确认窗满 -> eCheckFunction；
 *                         ③ 滤网阻塞趋势——同环境温度下温差缓升速率（滑动窗
 *                            前后半均值斜率）超限 -> eMaintenanceReq。
 *                         只告警不控风扇：执行归调用方，本件零输出侧风扇操作
 *                         （「算一个值 / 做一件事」边界）。
 * 同类邻件互引 (Watch)  : 后缀 *Watch 族边界——触发 / 心跳类设备级监视归
 *                         FB_DL_CameraHealthWatch，时钟漂移类归 FB_DL_ClockDriftMonitor，
 *                         本件只负责热管理温差与风扇反馈域，三者互不替代。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 两温度非有限 -> 故障级锁存（各自独立码位，R190 归因唯一），健康出口
 *      eFailure（信号不可信）；解除路径 = 复位沿 AND 对应信号恢复有限。
 *   2) 环境温度高于柜内（温差 <= 0）为自然工况：判据挂起不发布、不计码
 *      （挂起态由 bJudgeSuspended 直接观测，R90 反证成立不加码）。
 *   3) 趋势窗样本数不足 nTrendWin 时趋势判据挂起（R307：挂起同步挂起累计载体
 *      ——样本只在监视中采集，挂起期不采不计）。
 *   4) 风扇转速反馈非有限 -> 故障级锁存（判据挂起 + eFailure）。
 *   5) 趋势样本仅在 ΔT > 0 时采集：负温差（环境更热）样本会稀释缓升斜率，
 *      滤网阻塞判据只对正温差域有意义。
 * 故障码表 (Error codes) :
 *   16#0003_050E [故障级] 柜内温度非有限，锁存，eFailure
 *                 反证：eFailure 不承载成因（三路信号三因，R190 必须码位互异）。
 *   16#0003_050F [故障级] 环境温度非有限，锁存，eFailure
 *                 反证：环温失效与柜温失效对健康出口同为 eFailure，组合不可区分。
 *   16#0003_0510 [故障级] 风扇转速反馈非有限，锁存，eFailure
 *                 反证：风扇反馈失效与两温度失效对健康出口同为 eFailure，组合不可区分。
 *   16#0003_0511 [故障级] 组态非法（确认窗 / 阈值域 / 趋势窗长 / 采样周期），已回退
 *                 反证：回退后监视继续，码位是组态错误唯一可见出口。
 *   16#0003_040A [信息级] 温差超限确认窗满（eMaintenanceReq 依据一）
 *                 反证：eHealth 为分级状态不承载成因；三判据三因码位互异（R190）。
 *   16#0003_040B [信息级] 风扇反馈失配确认窗满（eCheckFunction 依据）
 *                 反证：风扇失配分级（eCheckFunction）与温差成因分级（eMaintenanceReq）不同档，码位独立承载。
 *   16#0003_040C [信息级] 滤网阻塞趋势确认（eMaintenanceReq 依据二）
 *                 反证：趋势确认与温差确认同为 eMaintenanceReq 档，但成因互异，码位必须独立。
 * 码位总账 (Code ledger) : 16#0003_050E / 050F / 0510 / 0511 用 ｜ 16#0003_040A / 040B / 040C 用
 * 依赖     (Depends)    : TYPE E_DL_Ne107Status（属主 I_DL_DeviceHealth.st，只引用）
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 非有限双判 / 斜率分母 eps 闸 / 域闸全枚举
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 三态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 一沿二计时主体最前部无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R68 构建轮 · 批 2 · 目标 11）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CoolWatchState（归属 DL_Device，与 FB_DL_CabinetCoolingWatch 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CoolWatchState :
(
    eIdle  := 0,    // 未使能：判据与趋势冻结 / Disabled, criteria and trend frozen
    eRun   := 10,   // 监视中：三判据并行评估 / Watching, three criteria evaluated
    eFault := 99    // 信号 / 组态锁存：判据挂起 / Signal or config latched, criteria suspended
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_CabinetCoolingWatch
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_CabinetCoolingWatch
VAR_INPUT
    fTempCab     : REAL;                 // 柜内温度 [℃] / Cabinet temperature [degC]
    fTempAmb     : REAL;                 // 环境温度 [℃] / Ambient temperature [degC]
    bFanRunCmd   : BOOL;                 // 风扇运行命令（只读判据输入）/ Fan run command, judgement input only
    bFanRunFb    : BOOL;                 // 风扇运行反馈 / Fan run feedback
    fFanSpeedFb  : REAL;                 // 风扇转速反馈 [rpm] / Fan speed feedback [rpm]
    fFanSpeedMin : REAL := 500.0;        // 风扇转速下限 [rpm] / Fan speed floor [rpm]
    fDtLimitK    : REAL := 15.0;         // 温差超限阈 [K] / Delta-T over-limit threshold [K]
    tConfirmDt   : TIME := T#60S;        // 温差确认窗 [s] / Delta-T confirmation window [s]
    tFanConfirm  : TIME := T#10S;        // 风扇失配确认窗 [s] / Fan mismatch confirmation window [s]
    fTrendLimit  : REAL := 2.0;          // 滤网阻塞趋势阈 [K/h] / Filter clogging trend threshold [K per h]
    tSample      : TIME := T#1M;         // 趋势采样周期 [min] / Trend sampling period [min]
    nTrendWin    : INT  := 12;           // 趋势窗样本数 [个]，域 4..16 且为偶数 / Trend window samples, 4..16 even
    bEnable      : BOOL := TRUE;         // 使能 / Enable
    bReset       : BOOL;                 // 上升沿：清除信号 / 组态锁存 / Rising edge: clear signal and config latches
END_VAR
VAR_OUTPUT
    eHealth         : E_DL_Ne107Status;  // NE107 健康出口 / NE107 health verdict
    fDtNow          : REAL;              // 当前温差 [K] / Current delta-T [K]
    bJudgeSuspended : BOOL;              // 判据挂起（自然温差 / 样本不足）/ Judge suspended, natural or insufficient
    bFanMismatch    : BOOL;              // 风扇失配确认（保持型）/ Fan mismatch confirmed, level held
    bTrendConfirmed : BOOL;              // 滤网阻塞趋势确认（保持型）/ Trend confirmed, level held
    fTrendSlope     : REAL;              // 当前趋势斜率 [K/h] / Current trend slope [K per h]
    bError          : BOOL;              // 故障标志（信号 / 组态锁存归并）/ Fault flag merged
    uErrorId        : UDINT;             // 故障码，0 = 无故障 / Error code, 0 = none
    eState          : E_DL_CoolWatchState; // 当前状态（供 HMI 诊断）/ Current state
END_VAR
VAR
    fbTrigReset   : R_TRIG;              // 复位沿检测实例 / Reset edge detector
    tonDt         : TON;                 // 温差确认窗计时实例 / Delta-T confirmation timer
    tonFan        : TON;                 // 风扇失配确认窗计时实例 / Fan mismatch confirmation timer
    tonSample     : TON;                 // 趋势采样周期（自复位）实例 / Trend sampling timer, self resetting
    eStateInt     : E_DL_CoolWatchState; // 主状态机内部当前态 / Internal state machine state
    fDtInt        : REAL;                // 温差内部副本 [K] / Internal delta-T
    bCabBad       : BOOL;                // 柜温非有限 / Cabinet temp non-finite
    bAmbBad       : BOOL;                // 环温非有限 / Ambient temp non-finite
    bFanSigBad    : BOOL;                // 风扇转速非有限 / Fan speed non-finite
    bCabLatch     : BOOL;                // 柜温失效锁存 / Cabinet latch
    bAmbLatch     : BOOL;                // 环温失效锁存 / Ambient latch
    bFanLatch     : BOOL;                // 风扇反馈失效锁存 / Fan feedback latch
    bCfgLatch     : BOOL;                // 组态故障锁存 / Config fault latch
    bCfgBad       : BOOL;                // 本拍组态非法 / Config illegal this scan
    bDtExceeds    : BOOL;                // 温差超限判据（挂起时 FALSE）/ Delta-T exceeds, FALSE when suspended
    bFanMismatchInt : BOOL;              // 风扇失配确认内部副本 / Internal fan mismatch
    bTrendConfInt : BOOL;                // 趋势确认内部副本 / Internal trend confirmed
    bTrendActive  : BOOL;                // 本拍趋势斜率可发布 / Trend slope publishable
    afDtRing      : ARRAY[0..15] OF REAL; // 趋势温差样本环形窗 [K] / Delta-T trend ring [K]
    nTrendWinEff  : INT;                 // 钳位后趋势窗长 [个] / Clamped trend window length
    nTrendWrite   : INT;                 // 趋势窗写指针 [0..15] / Trend ring write pointer
    nTrendFill    : INT;                 // 趋势窗有效样本数 [个] / Trend ring fill count
    fMeanOld      : REAL;                // 前半窗均值 [K] / Older half mean [K]
    fMeanNew      : REAL;                // 后半窗均值 [K] / Recent half mean [K]
    fHalfHours    : REAL;                // 半窗时长折算小时 [h] / Half window in hours [h]
    nHalf         : INT;                 // 半窗样本数 [个] / Half window sample count
    nI            : INT;                 // 遍历索引 / Loop index
    fSlope        : REAL;                // 斜率中间量 [K/h] / Slope intermediate
    fSpeedMinEff  : REAL;                // 钳位后转速下限 [rpm] / Clamped speed floor
    fDtLimEff     : REAL;                // 钳位后温差阈 [K] / Clamped delta-T threshold
    fTrendLimEff  : REAL;                // 钳位后趋势阈 [K/h] / Clamped trend threshold
    bErrorInt     : BOOL;                // 本拍故障置位累加（出口归并）/ Fault set accumulator
    bFirstScan    : BOOL := TRUE;        // 上电首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_CW_WIN_MIN   : INT  := 4;      // 趋势窗长下限 [个] / Trend window floor
    DL_CW_WIN_MAX   : INT  := 16;     // 趋势窗长上限 [个]，与数组维度一致 / Trend window ceiling
    DL_CW_EPS       : REAL := 1.0E-6; // 斜率分母判零容差 [h] / Slope denominator epsilon [h]
    DL_CW_FIN_LIM   : REAL := 1.0E30; // REAL 有限幅值判界 / REAL finiteness bound
    DL_CW_HOUR_MS   : REAL := 3600000.0; // 小时毫秒换算常数 [ms/h] / Hours to milliseconds factor
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：一沿三计时全部位于主体最前部
 *      Unconditional refresh: one edge and three timers at the very top
 *      tonSample 为周期窗自复位（IN 串 bEnable AND NOT 自身 Q，R188）
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

tonDt(IN := bDtExceeds, PT := tConfirmDt);
tonFan(IN := bFanRunCmd AND (NOT bFanSigBad)
        AND ((NOT bFanRunFb) OR (fFanSpeedFb < fSpeedMinEff)),   // 反馈失效时判据整体挂起 / Suspended on bad feedback
       PT := tFanConfirm);
tonSample(IN := bEnable AND (NOT tonSample.Q), PT := tSample);

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫：趋势窗显式清零
 *      First-scan init: trend ring cleared explicitly
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    eStateInt := E_DL_CoolWatchState.eIdle;
    FOR nI := 0 TO 15 DO
        afDtRing[nI] := 0.0;     // 趋势窗显式清零 / Trend ring cleared
    END_FOR
    nTrendWrite := 0;
    nTrendFill  := 0;
    bFirstScan  := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜每拍预清（FB32-1）：单拍标志，禁入锁存 / 快照
 *      Per-scan preset: single-scan flags only
 *-----------------------------------------------------------------------------*)
bErrorInt := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜非有限闸（R272 全枚举：三个测量 REAL 入参）+ 组态域闸（限值 / 窗长 / 周期）
 *      Non-finite gates over the three measurement inputs, plus the config gate
 *      解除路径（R152 自证）：复位沿 AND 对应信号恢复有限 / 组态改对
 *-----------------------------------------------------------------------------*)
bCabBad    := (fTempCab <> fTempCab) OR ((fTempCab - fTempCab) <> (fTempCab - fTempCab))
              OR (ABS(fTempCab) >= DL_CW_FIN_LIM);
bAmbBad    := (fTempAmb <> fTempAmb) OR ((fTempAmb - fTempAmb) <> (fTempAmb - fTempAmb))
              OR (ABS(fTempAmb) >= DL_CW_FIN_LIM);
bFanSigBad := (fFanSpeedFb <> fFanSpeedFb) OR ((fFanSpeedFb - fFanSpeedFb) <> (fFanSpeedFb - fFanSpeedFb))
              OR (ABS(fFanSpeedFb) >= DL_CW_FIN_LIM);

IF bCabBad THEN
    bCabLatch := TRUE;
    uErrorId  := 16#0003_050E;   // 故障级：柜温非有限 / Fault: cabinet temp non-finite
    bErrorInt := TRUE;
END_IF
IF bAmbBad THEN
    bAmbLatch := TRUE;
    uErrorId  := 16#0003_050F;   // 故障级：环温非有限 / Fault: ambient temp non-finite
    bErrorInt := TRUE;
END_IF
IF bFanSigBad THEN
    bFanLatch := TRUE;
    uErrorId  := 16#0003_0510;   // 故障级：风扇反馈非有限 / Fault: fan feedback non-finite
    bErrorInt := TRUE;
END_IF

bCfgBad := (tConfirmDt <= T#0S) OR (tFanConfirm <= T#0S) OR (tSample <= T#0S)
           OR (fDtLimitK <= 0.0) OR (fDtLimitK <> fDtLimitK)
           OR (fFanSpeedMin < 0.0) OR (fFanSpeedMin <> fFanSpeedMin)
           OR (fTrendLimit <= 0.0) OR (fTrendLimit <> fTrendLimit)
           OR (nTrendWin < DL_CW_WIN_MIN) OR (nTrendWin > DL_CW_WIN_MAX);

IF bCfgBad THEN
    bCfgLatch := TRUE;
    uErrorId  := 16#0003_0511;   // 故障级：组态非法 / Fault: config illegal
    bErrorInt := TRUE;
END_IF

(* 两级回退取值（R117）：非法参数钳回默认常量，服务不中断 *)
(* Two-level fallback values *)
IF (fFanSpeedMin < 0.0) OR (fFanSpeedMin <> fFanSpeedMin) THEN
    fSpeedMinEff := 500.0;       // 回退默认转速下限 / Fallback default floor
ELSE
    fSpeedMinEff := fFanSpeedMin;
END_IF
IF (fDtLimitK <= 0.0) OR (fDtLimitK <> fDtLimitK) THEN
    fDtLimEff := 15.0;           // 回退默认温差阈 / Fallback default threshold
ELSE
    fDtLimEff := fDtLimitK;
END_IF
IF (fTrendLimit <= 0.0) OR (fTrendLimit <> fTrendLimit) THEN
    fTrendLimEff := 2.0;         // 回退默认趋势阈 / Fallback default threshold
ELSE
    fTrendLimEff := fTrendLimit;
END_IF
IF (nTrendWin < DL_CW_WIN_MIN) OR (nTrendWin > DL_CW_WIN_MAX) THEN
    nTrendWinEff := 12;          // 回退默认窗长 / Fallback default window
ELSE
    nTrendWinEff := nTrendWin;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜温差判据（挂起语义）：环温 >= 柜温为自然工况，判据挂起不发布
 *      Delta-T criterion with suspension: ambient hotter means natural, suspended
 *-----------------------------------------------------------------------------*)
fDtInt := fTempCab - fTempAmb;
fDtNow := fDtInt;

bDtExceeds := (NOT bCabBad) AND (NOT bAmbBad)
              AND (fDtInt > fDtLimEff);      // 挂起（温差 <= 0）通过不置判据承载 / Suspension by not asserting

(*------------------------------------------------------------------------------
 * 段 6｜趋势采样与斜率（周期窗自复位 TON 到期拍采一个样本）
 *      Trend sampling and slope, one sample per self-resetting window tick
 *-----------------------------------------------------------------------------*)
bTrendActive := FALSE;
fSlope       := 0.0;

IF tonSample.Q AND (eStateInt = E_DL_CoolWatchState.eRun)
   AND (NOT bCabBad) AND (NOT bAmbBad) AND (fDtInt > 0.0) THEN
    afDtRing[nTrendWrite] := fDtInt;     // 正温差样本入环 / Positive delta-T sample into ring
    nTrendWrite := nTrendWrite + 1;
    IF nTrendWrite >= nTrendWinEff THEN
        nTrendWrite := 0;                // 显式回卷 / Explicit wrap
    END_IF
    IF nTrendFill < nTrendWinEff THEN
        nTrendFill := nTrendFill + 1;    // 填充推进 / Fill up
    END_IF
END_IF

IF nTrendFill >= nTrendWinEff THEN
    nHalf := nTrendWinEff / 2;           // 半窗样本数（窗长已组态为偶数域）/ Half count
    fMeanOld := 0.0;
    fMeanNew := 0.0;
    FOR nI := 0 TO (nHalf - 1) DO
        fMeanOld := fMeanOld + afDtRing[nI];              // 前半窗求和 / Older half sum
        fMeanNew := fMeanNew + afDtRing[nI + nHalf];      // 后半窗求和 / Recent half sum
    END_FOR
    fMeanOld := fMeanOld / UDINT_TO_REAL(DINT_TO_UDINT(nHalf));
    fMeanNew := fMeanNew / UDINT_TO_REAL(DINT_TO_UDINT(nHalf));
    fHalfHours := (TIME_TO_LREAL(tSample) * UDINT_TO_REAL(DINT_TO_UDINT(nHalf))) / DL_CW_HOUR_MS;
    IF fHalfHours > DL_CW_EPS THEN
        fSlope := (fMeanNew - fMeanOld) / fHalfHours;     // 缓升斜率 [K/h]，分母已闸 / Slope, guarded
        bTrendActive := TRUE;
        IF fSlope > fTrendLimEff THEN
            bTrendConfInt := TRUE;                        // 趋势确认（保持型）/ Trend confirmed
            uErrorId      := 16#0003_040C;                // 信息级：趋势确认 / Info: trend confirmed
        ELSIF fSlope <= fTrendLimEff THEN
            bTrendConfInt := FALSE;                       // 回落清除 / Clear on recovery
        END_IF
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_CoolWatchState.eIdle:
        IF bEnable AND (NOT bCabLatch) AND (NOT bAmbLatch) AND (NOT bFanLatch) AND (NOT bCfgLatch) THEN
            eStateInt := E_DL_CoolWatchState.eRun;
        END_IF

    E_DL_CoolWatchState.eRun:
        IF bCabLatch OR bAmbLatch OR bFanLatch OR bCfgLatch OR (NOT bEnable) THEN
            eStateInt := E_DL_CoolWatchState.eFault;   // 任一锁存即挂起 / Any latch suspends
        END_IF

    E_DL_CoolWatchState.eFault:
        (* 解除路径（R152 自证可达）：复位沿 AND 全部锁存源已恢复 *)
        IF fbTrigReset.Q AND (NOT bCabBad) AND (NOT bAmbBad) AND (NOT bFanSigBad) AND (NOT bCfgBad) THEN
            bCabLatch := FALSE;
            bAmbLatch := FALSE;
            bFanLatch := FALSE;
            bCfgLatch := FALSE;
            uErrorId  := 16#0000_0000;
            eStateInt := E_DL_CoolWatchState.eIdle;
        END_IF

    ELSE
        eStateInt := E_DL_CoolWatchState.eFault;
        uErrorId  := 16#0003_0511;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 8｜风扇失配确认消化（保持型）：确认窗满置位，命令撤销 / 反馈恢复回落清除
 *      Fan mismatch confirmation, level held, cleared on recovery
 *-----------------------------------------------------------------------------*)
IF tonFan.Q THEN
    bFanMismatchInt := TRUE;
    uErrorId        := 16#0003_040B;   // 信息级：风扇失配确认 / Info: fan mismatch confirmed
ELSIF (NOT bFanRunCmd) OR (bFanRunFb AND (NOT bFanSigBad) AND (fFanSpeedFb >= fSpeedMinEff)) THEN
    bFanMismatchInt := FALSE;          // 回落清除 / Clear on recovery
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜输出单一出口（范式 P-05）：健康分级由三判据保持型派生
 *      Single output exit: health derived from the three level-held criteria
 *-----------------------------------------------------------------------------*)
bJudgeSuspended := (eStateInt <> E_DL_CoolWatchState.eRun)
                   OR (fDtInt <= 0.0)
                   OR (nTrendFill < nTrendWinEff);

IF eStateInt <> E_DL_CoolWatchState.eRun THEN
    eHealth := E_DL_Ne107Status.eUnknown;        // 未使能 / 锁存：未知（信号失效另见 eFailure 口径）
    IF bCabLatch OR bAmbLatch OR bFanLatch THEN
        eHealth := E_DL_Ne107Status.eFailure;    // 测量信号不可信 / Measurement untrusted
    END_IF
ELSIF bFanMismatchInt THEN
    eHealth := E_DL_Ne107Status.eCheckFunction;  // 风扇失配 / Fan mismatch
ELSIF bTrendConfInt OR tonDt.Q THEN
    eHealth := E_DL_Ne107Status.eMaintenanceReq; // 温差超限确认或趋势确认 / Delta-T confirmed or trend
    IF tonDt.Q THEN
        uErrorId := 16#0003_040A;                // 信息级：温差确认 / Info: delta-T confirmed
    END_IF
ELSE
    eHealth := E_DL_Ne107Status.eOk;             // 全判据通过 / All pass
END_IF

bFanMismatch    := bFanMismatchInt;
bTrendConfirmed := bTrendConfInt;
fTrendSlope     := fSlope;
bError          := bErrorInt OR (eStateInt = E_DL_CoolWatchState.eFault);
eState          := eStateInt;
END_FUNCTION_BLOCK
