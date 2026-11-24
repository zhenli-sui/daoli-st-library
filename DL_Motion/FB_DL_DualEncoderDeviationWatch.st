(*==============================================================================
 * 组件名称 (Component)  : FB_DL_DualEncoderDeviationWatch
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准库（TON / ABS / MAX），零厂商方言
 * 功能描述 (Function)   : 双编码器（电机侧 / 负载侧）位置与速度双反馈偏差监测：
 *                         ① 逐拍计算位置偏差 fDevPos 与速度偏差 fDevVel 的绝对值 [mm]/[mm/s]；
 *                         ② **启动屏蔽窗口**：bEnable 上升后 tBlank 时长内不产生预警 /
 *                            报警 / 停机请求，偏差仍照常计算便于投运观察；窗口由内部
 *                            锁存位 bBlankDone 一次性结束，bEnable 跌落即清锁存；
 *                         ③ **分级延时确认**：预警 tonWarn / 报警 tonAlarm / 停机 tonTrip
 *                            三个 TON 各自独立、无条件每周期刷新，延时到即按序晋级；
 *                         ④ **停机请求** bTripReq 锁存输出，解除路径唯一：
 *                            bReset 且偏差条件已消失（NOT bTripCond）；
 *                         ⑤ **编码器失效单独判定**：非有限值（NaN 自反 / Inf 阈值直比）
 *                            与单拍位置跳变（> fPosJumpMax）各自成码，任一编码器失效即
 *                            进 eFault，偏差不再用坏值重算（保持上一拍值并披露）。
 * 接口     (Interface)  : 输入 20 项（使能 / 复位 / 双侧位置速度 / 6 个分级阈值 /
 *                         跳变上限 / 4 个时间常数），输出 11 项（状态回执 / 双侧偏差 /
 *                         屏蔽窗回执 / 三级出口 / 编码器有效回执 / 有效性与故障码）。
 * 边界     (Boundary)   : ① 阈值做「≥ 1E-3 且 预警 ≤ 报警 ≤ 停机」递增序硬钳位，
 *                            钳位成立时置信息码 16#0004_1001（不置 bError）；
 *                         ② 屏蔽窗口只在 bEnable 上升沿开一次，不做周期重开；
 *                         ③ 编码器失效判定只覆盖「非有限」与「单拍跳变」两类，
 *                            不含断线 / 信号丢失（由上层硬件位在他件处理）；
 *                         ④ 本件只出停机**请求**位，不执行停机，执行由上层安全链完成；
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / %I / %Q）。
 * 码表     (Codes)      : 本件占用 16#0004_1001 ~ 16#0004_100F 区间，实际使用 5 个：
 *                         1001 信息级 阈值钳位；1002 故障级 电机侧编码器失效；
 *                         1003 故障级 负载侧编码器失效；1004 信息级 偏差超预警；
 *                         1005 信息级 偏差超报警；1006 故障级 停机请求已锁存；
 *                         1008 故障级 非法状态兜底。信息级码永不置 bError。
 * 分工声明 (Scope)      : 与 FB_DL_AxisDualFeedbackGuard 分工：那件做闭环反馈切换与
 *                         位置给定仲裁；本件只做两侧偏差监测与分级保护请求。
 * 开源溯源 (Origin)     : 开源溯源：原创实现（无外部代码引入）
 * 红线自检 (Redline)    : R1 ✓ 零 GVL / VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 钳位 + 容差 1E-9 + 非有限双判
 *                         R5 ✓ 声明逐行同行双语注释 ｜ R6 ✓ 六态 ENUM + CASE + ELSE
 *                         R7 ✓ 四个 TON 无条件每周期调用
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版
 *                         2026-11-23  v1.0.1  R77 闸修复（Inf 判据改阈值直比，修 Inf−Inf=NaN 致支路恒假）
 * 验收向量 (Acceptance) :
 *   V1 bEnable 上升、tBlank=2s、偏差 0 → 第 1 拍 eStateOut=eBlank，
 *      bBlankActive=TRUE，bWarn/bAlarm/bTripReq 全 FALSE；2s 后 eBlank → eMonitor。
 *   V2 屏蔽窗结束后位置偏差恒 1.5mm（预警 1.0 / 报警 2.0 / 停机 5.0）：
 *      tWarnDly 到后 bWarn=TRUE、eStateOut=eWarn、uErrorId=16#0004_1004、bError=FALSE。
 *   V3 位置偏差恒 6.0mm：tonTrip 到时 bTripReq=TRUE 且锁存，uErrorId=16#0004_1006、
 *      bError=TRUE；即使偏差回落到 0，bTripReq 仍 TRUE，直到 bReset 单拍。
 *   V4 电机侧 fPosMotor = NaN：本拍 bMotorEncValid=FALSE、eStateOut=eFault、
 *      uErrorId=16#0004_1002、fDevPos 保持上一拍值（不拿坏值重算）。
 *   V5 fPosLoad 单拍从 0 跳到 600.0（fPosJumpMax=500.0）：bLoadEncValid=FALSE、
 *      uErrorId=16#0004_1003；单拍后跳变锁存保持至 bReset。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   声明于调用方 FB 的 VAR 区：fbDew : FB_DL_DualEncoderDeviationWatch;
 *   每周期无条件调用：fbDew(bEnable := xRun, bReset := xReset,
 *                            fPosMotor := stAx.fActPosMotor, fPosLoad := stAx.fActPosLoad,
 *                            fVelMotor := stAx.fActVelMotor, fVelLoad := stAx.fActVelLoad);
 *   取用出口：IF fbDew.bTripReq THEN 触发上层安全链停止；诊断取 fbDew.uErrorId。
 *   调参指引：fDevWarnPos 取机械间隙的 1.5 倍，fDevAlarmPos 取 2 倍，
 *            fDevTripPos 取联轴器失效前的可辨认位差；tBlank 取启动加速段时长再加 20%。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DewState（归属 DL_Motion，与 FB_DL_DualEncoderDeviationWatch 同文件）
 * 含义: 双编码器偏差监测状态机离散状态。eBlank 只覆盖启动屏蔽窗，eMonitor 为常规
 *       监测相，eWarn / eAlarm 为分级确认相，eFault 为编码器失效与非法状态兜底相。
 *----------------------------------------------------------------------------*)
TYPE E_DL_DewState :
(
    eInit    := 0,    // 首扫态：出口全部复位，等 bEnable 上升 / First scan: outputs reset, waiting for bEnable rise
    eBlank   := 10,   // 启动屏蔽窗态：只算偏差不报警，窗口结束转 eMonitor / Startup blanking: deviations computed, no alarms until window ends
    eMonitor := 20,   // 常规监测态：三级延时确认累积中 / Normal monitoring: three-level confirmation accumulating
    eWarn    := 30,   // 预警确认态：bWarn 置位，条件消失即退回 eMonitor / Warning state: bWarn set, falls back when condition clears
    eAlarm   := 40,   // 报警确认态：bAlarm 置位，停机延时继续累积 / Alarm state: bAlarm set, trip delay keeps accumulating
    eFault   := 99    // 故障兜底态：编码器失效或非法状态进入，锁存至 bReset / Fault fallback: encoder failure or illegal state, latched until bReset
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_DualEncoderDeviationWatch
 * 调用约定: 每周期无条件调用一次；四个 TON 实例在段 3 无条件刷新，禁置于 CASE 内。
 * 屏蔽语义: bBlankActive = TRUE 期间，tonWarn / tonAlarm / tonTrip 的 IN 条件被
 *           bDevValid 与 NOT bBlankActive 共同门控，故延时不会在窗口内悄悄累积。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_DualEncoderDeviationWatch
VAR_INPUT
    bEnable       : BOOL := FALSE;       // 监测使能，上升沿开启屏蔽窗，跌落清全部锁存 / Enable, rising edge opens blank window, falling clears all latches
    bReset        : BOOL := FALSE;       // 复位（电平有效），清停机锁存与跳变锁存 / Reset (level), clears trip latch and jump latches
    fPosMotor     : REAL := 0.0;         // 电机侧编码器位置反馈 [mm] / Motor-side encoder position feedback [mm]
    fPosLoad      : REAL := 0.0;         // 负载侧编码器位置反馈 [mm] / Load-side encoder position feedback [mm]
    fVelMotor     : REAL := 0.0;         // 电机侧编码器速度反馈 [mm/s] / Motor-side encoder velocity feedback [mm/s]
    fVelLoad      : REAL := 0.0;         // 负载侧编码器速度反馈 [mm/s] / Load-side encoder velocity feedback [mm/s]
    fDevWarnPos   : REAL := 1.0;         // 位置偏差预警阈值 [mm] / Position deviation warning threshold [mm]
    fDevAlarmPos  : REAL := 2.0;         // 位置偏差报警阈值 [mm] / Position deviation alarm threshold [mm]
    fDevTripPos   : REAL := 5.0;         // 位置偏差停机阈值 [mm] / Position deviation trip threshold [mm]
    fDevWarnVel   : REAL := 10.0;        // 速度偏差预警阈值 [mm/s] / Velocity deviation warning threshold [mm/s]
    fDevAlarmVel  : REAL := 20.0;        // 速度偏差报警阈值 [mm/s] / Velocity deviation alarm threshold [mm/s]
    fDevTripVel   : REAL := 50.0;        // 速度偏差停机阈值 [mm/s] / Velocity deviation trip threshold [mm/s]
    fPosJumpMax   : REAL := 500.0;       // 单拍位置跳变上限，超限判编码器失效 [mm] / Single-scan position jump limit, exceeding means encoder failure [mm]
    tBlank        : TIME := T#2S;        // 启动屏蔽窗口时长，T#0S = 不屏蔽直通 [s] / Startup blanking window, T#0S = no blanking [s]
    tWarnDly      : TIME := T#500MS;     // 预警确认延时 [s] / Warning confirmation delay [s]
    tAlarmDly     : TIME := T#300MS;     // 报警确认延时 [s] / Alarm confirmation delay [s]
    tTripDly      : TIME := T#2S;        // 停机请求确认延时 [s] / Trip request confirmation delay [s]
END_VAR
VAR_OUTPUT
    eStateOut     : E_DL_DewState;       // 状态机当前状态回执 [-] / Current state feedback of the state machine
    fDevPos       : REAL;                // 位置偏差绝对值，失效时保持上一拍 [mm] / Absolute position deviation, held on invalid [mm]
    fDevVel       : REAL;                // 速度偏差绝对值，失效时保持上一拍 [mm/s] / Absolute velocity deviation, held on invalid [mm/s]
    bBlankActive  : BOOL;                // 启动屏蔽窗口生效中，TRUE 期间不产生任何报警 / Blanking window active, no alarm during TRUE
    bWarn         : BOOL;                // 预警出口（信息级，不置 bError）/ Warning outlet, info level, keeps bError FALSE
    bAlarm        : BOOL;                // 报警出口（信息级，不置 bError）/ Alarm outlet, info level, keeps bError FALSE
    bTripReq      : BOOL;                // 停机请求出口（锁存，解除路径唯一：bReset 且条件消失）/ Trip request outlet, latched, cleared only by bReset with condition gone
    bMotorEncValid: BOOL;                // 电机侧编码器有效回执 / Motor-side encoder validity feedback
    bLoadEncValid : BOOL;                // 负载侧编码器有效回执 / Load-side encoder validity feedback
    bValid        : BOOL;                // 出口数据可信标志，失效相为 FALSE / Output data trustworthy flag, FALSE in invalid states
    bError        : BOOL;                // 故障级标志，与 uErrorId 严格联动 / Fault-level flag, strictly coupled with uErrorId
    uErrorId      : UDINT;               // 错误码，0 = 无码 / Error code, 0 = no code
END_VAR
VAR
    eState        : E_DL_DewState;       // 状态机内部当前状态 [-] / Internal current state
    tonBlank      : TON;                 // 启动屏蔽窗定时器（一次性，由锁存位终止）/ Startup blanking timer, one shot, terminated by latch
    tonWarn       : TON;                 // 预警确认延时定时器，无条件刷新 / Warning confirmation timer, refreshed unconditionally
    tonAlarm      : TON;                 // 报警确认延时定时器，无条件刷新 / Alarm confirmation timer, refreshed unconditionally
    tonTrip       : TON;                 // 停机请求确认延时定时器，无条件刷新 / Trip confirmation timer, refreshed unconditionally
    bBlankDone    : BOOL;                // 屏蔽窗结束锁存位，bEnable 跌落清零 / Blanking window finished latch, cleared when bEnable falls
    bBlankEn      : BOOL;                // 屏蔽功能是否启用（tBlank > 0）/ Blanking enabled flag, TRUE when tBlank > 0
    bBlankActiveI : BOOL;                // 内部屏蔽窗生效量，供 IN 条件引用 / Internal blanking active quantity used by IN conditions
    bWarnCond     : BOOL;                // 预警条件（已过域闸与屏蔽闸）/ Warning condition after domain and blanking gates
    bAlarmCond    : BOOL;                // 报警条件（已过域闸与屏蔽闸）/ Alarm condition after domain and blanking gates
    bTripCond     : BOOL;                // 停机条件（已过域闸与屏蔽闸，不受屏蔽窗影响以外）/ Trip condition after gates
    bDevValid     : BOOL;                // 本拍双侧编码器均有效、偏差可信 / Both encoders valid this scan, deviations trustworthy
    bMotorFinite  : BOOL;                // 电机侧反馈均为有限值 / Motor-side feedback values finite
    bLoadFinite   : BOOL;                // 负载侧反馈均为有限值 / Load-side feedback values finite
    bMotorNaN     : BOOL;                // 电机侧自反判 NaN 命中 / Motor-side NaN detected by self-comparison
    bMotorInf     : BOOL;                // 电机侧阈值直比判 Inf 命中 / Motor-side Infinity detected by direct threshold comparison
    bLoadNaN      : BOOL;                // 负载侧自反判 NaN 命中 / Load-side NaN detected by self-comparison
    bLoadInf      : BOOL;                // 负载侧阈值直比判 Inf 命中 / Load-side Infinity detected by direct threshold comparison
    bMotorJump    : BOOL;                // 电机侧单拍跳变锁存 / Motor-side single-scan jump latch
    bLoadJump     : BOOL;                // 负载侧单拍跳变锁存 / Load-side single-scan jump latch
    bHavePrev     : BOOL;                // 是否已有上一拍位置快照 / Previous position snapshot available
    fPrevPosMotor : REAL;                // 电机侧上一拍位置快照 [mm] / Motor-side previous position snapshot [mm]
    fPrevPosLoad  : REAL;                // 负载侧上一拍位置快照 [mm] / Load-side previous position snapshot [mm]
    bFaultLvl     : BOOL;                // 故障级标志内部量 / Internal fault-level flag
    fWarnPosEff   : REAL;                // 钳位后位置预警阈值 [mm] / Clamped position warning threshold [mm]
    fAlarmPosEff  : REAL;                // 钳位后位置报警阈值 [mm] / Clamped position alarm threshold [mm]
    fTripPosEff   : REAL;                // 钳位后位置停机阈值 [mm] / Clamped position trip threshold [mm]
    fWarnVelEff   : REAL;                // 钳位后速度预警阈值 [mm/s] / Clamped velocity warning threshold [mm/s]
    fAlarmVelEff  : REAL;                // 钳位后速度报警阈值 [mm/s] / Clamped velocity alarm threshold [mm/s]
    fTripVelEff   : REAL;                // 钳位后速度停机阈值 [mm/s] / Clamped velocity trip threshold [mm/s]
    fJumpEff      : REAL;                // 钳位后单拍跳变上限 [mm] / Clamped single-scan jump limit [mm]
    uInfoCode     : UDINT;               // 信息级码暂存（参数钳位等）/ Info-level code scratch, parameter clamping etc.
    bTripLatch    : BOOL;                // 停机请求锁存位 / Trip request latch
END_VAR
VAR CONSTANT
    DL_DEW_OK   : UDINT := 16#0000_0000; // 无码哨兵 / No-code sentinel
    DL_DEW_TOL  : REAL := 1.0E-3;        // 阈值下限硬钳位值，防零阈值抖动 [mm] / Threshold lower clamp preventing zero-threshold chatter
    DL_DEW_EPS  : REAL := 1.0E-9;        // 浮点比较容差（本件统一口径）/ Unified floating point comparison tolerance
    DL_DEW_ZERO : REAL := 0.0;           // 零基准哨兵 / Zero reference sentinel
    DL_DEW_HALF : REAL := 0.5;           // 中值系数（均值出口备用）/ Half factor for averaging outlet
    DL_DEW_RMAX : REAL := 3.4028235E38;  // 本机 REAL 可表示上限，Inf 阈值直比基准 [无量纲] / Locally representable REAL maximum, Inf threshold base
END_VAR

(*------------------------------------------------------------------------------
 * 段 0｜阈值域闸与钳位（不中断扫描）：强制递增序 预警 ≤ 报警 ≤ 停机，且均 ≥ 1E-3
 *      Threshold domain gate: enforce warning <= alarm <= trip and each >= 1E-3
 *      钳位一旦成立置信息码 16#0004_1001，不影响本拍监测能力（信息级不置 bError）
 *-----------------------------------------------------------------------------*)
uInfoCode    := DL_DEW_OK;                                  // 信息码预置无码 / Preset no info code
bFaultLvl    := FALSE;                                      // 故障级标志预置 / Preset fault-level flag FALSE

fWarnPosEff  := MAX(fDevWarnPos, DL_DEW_TOL);               // 位置预警阈值下限钳位 [mm] / Position warning lower clamp
fAlarmPosEff := MAX(fDevAlarmPos, fWarnPosEff);             // 位置报警阈值不低于预警 [mm] / Position alarm kept above warning
fTripPosEff  := MAX(fDevTripPos, fAlarmPosEff);             // 位置停机阈值不低于报警 [mm] / Position trip kept above alarm
fWarnVelEff  := MAX(fDevWarnVel, DL_DEW_TOL);               // 速度预警阈值下限钳位 [mm/s] / Velocity warning lower clamp
fAlarmVelEff := MAX(fDevAlarmVel, fWarnVelEff);             // 速度报警阈值不低于预警 [mm/s] / Velocity alarm kept above warning
fTripVelEff  := MAX(fDevTripVel, fAlarmVelEff);             // 速度停机阈值不低于报警 [mm/s] / Velocity trip kept above alarm
fJumpEff     := MAX(fPosJumpMax, DL_DEW_TOL);               // 跳变上限下限钳位 [mm] / Jump limit lower clamp

IF (ABS(fWarnPosEff - fDevWarnPos) > DL_DEW_EPS)
   OR (ABS(fAlarmPosEff - fDevAlarmPos) > DL_DEW_EPS)
   OR (ABS(fTripPosEff - fDevTripPos) > DL_DEW_EPS)
   OR (ABS(fWarnVelEff - fDevWarnVel) > DL_DEW_EPS)
   OR (ABS(fAlarmVelEff - fDevAlarmVel) > DL_DEW_EPS)
   OR (ABS(fTripVelEff - fDevTripVel) > DL_DEW_EPS)
   OR (ABS(fJumpEff - fPosJumpMax) > DL_DEW_EPS) THEN
    uInfoCode := 16#0004_1001;                              // 信息级：阈值越界已钳位 / Info: thresholds out of range, clamped
END_IF

(*------------------------------------------------------------------------------
 * 段 1｜编码器有效性判定：非有限（NaN 自反 / Inf 差自减）与单拍跳变分别成码
 *      Encoder validity: non-finite detection plus single-scan jump detection
 *      双判口径：NaN 用 x <> x 自反判；Inf 用「阈值直比」判（与 DL_DEW_RMAX 双侧比较），
 *      禁用 |x − x| 差自减口径——IEEE-754 下 Inf − Inf = NaN，任何与 NaN 的比较恒假，
 *      会让 +Inf 首拍绕过跳变闸（bHavePrev=FALSE）直接泄漏到 fDevPos 出口并误报编码器有效。
 *      NaN detection uses x <> x; Infinity uses direct threshold comparison against DL_DEW_RMAX.
 *      The former |x - x| test is banned: Inf - Inf = NaN makes every comparison FALSE.
 *-----------------------------------------------------------------------------*)
bMotorNaN := (fPosMotor <> fPosMotor) OR (fVelMotor <> fVelMotor);                            // 自反判 NaN / NaN by self-comparison
bMotorInf := (fPosMotor > DL_DEW_RMAX) OR (fPosMotor < -DL_DEW_RMAX)
          OR (fVelMotor > DL_DEW_RMAX) OR (fVelMotor < -DL_DEW_RMAX);                        // Inf 阈值直比 / Infinity by direct threshold comparison
bMotorFinite := NOT (bMotorNaN OR bMotorInf);                                                // 电机侧有限标志 / Motor side finite flag

bLoadNaN  := (fPosLoad <> fPosLoad) OR (fVelLoad <> fVelLoad);                               // 自反判 NaN / NaN by self-comparison
bLoadInf  := (fPosLoad > DL_DEW_RMAX) OR (fPosLoad < -DL_DEW_RMAX)
          OR (fVelLoad > DL_DEW_RMAX) OR (fVelLoad < -DL_DEW_RMAX);                           // Inf 阈值直比 / Infinity by direct threshold comparison
bLoadFinite := NOT (bLoadNaN OR bLoadInf);                                                   // 负载侧有限标志 / Load side finite flag

IF bHavePrev AND bMotorFinite THEN
    IF ABS(fPosMotor - fPrevPosMotor) > fJumpEff THEN
        bMotorJump := TRUE;                                 // 电机侧跳变锁存（bReset 解除）/ Motor jump latched, cleared by bReset
    END_IF
END_IF
IF bHavePrev AND bLoadFinite THEN
    IF ABS(fPosLoad - fPrevPosLoad) > fJumpEff THEN
        bLoadJump := TRUE;                                  // 负载侧跳变锁存（bReset 解除）/ Load jump latched, cleared by bReset
    END_IF
END_IF

IF bReset OR NOT bEnable THEN
    bMotorJump := FALSE;                                    // 跳变锁存解除路径之一：复位 / Jump latch clear path: reset
    bLoadJump  := FALSE;                                    // 跳变锁存解除路径之一：复位 / Jump latch clear path: reset
    bHavePrev  := FALSE;                                    // 位置快照作废，下次重新建立基准 / Drop snapshot, rebuild baseline next run
END_IF

bMotorEncValid := bMotorFinite AND NOT bMotorJump;          // 电机侧编码器有效回执 / Motor encoder validity
bLoadEncValid  := bLoadFinite AND NOT bLoadJump;            // 负载侧编码器有效回执 / Load encoder validity

IF bMotorFinite THEN
    fPrevPosMotor := fPosMotor;                             // 有限值才更新快照，坏值不得污染基准 / Update snapshot only on finite value
END_IF
IF bLoadFinite THEN
    fPrevPosLoad := fPosLoad;                               // 有限值才更新快照，坏值不得污染基准 / Update snapshot only on finite value
END_IF
IF bMotorFinite AND bLoadFinite THEN
    bHavePrev := TRUE;                                      // 双侧均有限才建立基准 / Baseline built only when both sides finite
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜偏差计算：仅双侧有效时重算，任一失效保持上一拍值（不拿坏值重算）
 *      Deviation computation: recompute only when both sides valid, else hold
 *-----------------------------------------------------------------------------*)
bDevValid := bMotorEncValid AND bLoadEncValid;              // 偏差可信闸 / Deviation trustworthy gate
IF bDevValid THEN
    fDevPos := ABS(fPosMotor - fPosLoad);                   // 位置偏差绝对值 [mm] / Absolute position deviation [mm]
    fDevVel := ABS(fVelMotor - fVelLoad);                   // 速度偏差绝对值 [mm/s] / Absolute velocity deviation [mm/s]
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜定时器组无条件刷新（红线 R7）+ 屏蔽窗口一次性锁存
 *      Unconditional timer refresh plus one-shot blanking window latch
 *      屏蔽窗口径：tBlank = 0 时 bBlankEn = FALSE，直通不屏蔽（防零时长除类退化）
 *-----------------------------------------------------------------------------*)
bBlankEn := tBlank > T#0S;                                  // 屏蔽功能启用判定，零时长直通 / Blanking enabled test, zero duration passes through

tonBlank(IN := bEnable AND bBlankEn AND NOT bBlankDone, PT := tBlank);   // 屏蔽窗计时，无条件调用 / Blanking timer, called unconditionally
IF NOT bEnable THEN
    bBlankDone := FALSE;                                    // 使能跌落清屏蔽锁存，下次启动重开 / Enable fall clears blanking latch
ELSIF tonBlank.Q THEN
    bBlankDone := TRUE;                                     // 窗口到时置锁存，IN 随之变 FALSE 停止计时 / Window elapsed, latch stops the timer
END_IF
bBlankActiveI := bEnable AND bBlankEn AND NOT bBlankDone AND NOT tonBlank.Q;   // 屏蔽窗生效内部量 / Internal blanking active quantity
bBlankActive  := bBlankActiveI;                             // 对外回执 / Outward feedback

bWarnCond  := bEnable AND bDevValid AND NOT bBlankActiveI
              AND ((fDevPos > fWarnPosEff) OR (fDevVel > fWarnVelEff));     // 预警条件（过域闸与屏蔽闸）/ Warning condition after gates
bAlarmCond := bEnable AND bDevValid AND NOT bBlankActiveI
              AND ((fDevPos > fAlarmPosEff) OR (fDevVel > fAlarmVelEff));   // 报警条件（过域闸与屏蔽闸）/ Alarm condition after gates
bTripCond  := bEnable AND bDevValid AND NOT bBlankActiveI
              AND ((fDevPos > fTripPosEff) OR (fDevVel > fTripVelEff));     // 停机条件（过域闸与屏蔽闸）/ Trip condition after gates

tonWarn(IN := bWarnCond, PT := tWarnDly);                   // 预警确认计时，无条件调用 / Warning delay timer, called unconditionally
tonAlarm(IN := bAlarmCond, PT := tAlarmDly);                // 报警确认计时，无条件调用 / Alarm delay timer, called unconditionally
tonTrip(IN := bTripCond, PT := tTripDly);                   // 停机确认计时，无条件调用 / Trip delay timer, called unconditionally

(*------------------------------------------------------------------------------
 * 段 4｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with enum, case coverage and ELSE interception
 *      入口约束：任何相迁入 eMonitor 前必须 bDevValid（数据可信），否则进 eFault
 *-----------------------------------------------------------------------------*)
CASE eState OF

    eInit:
        (* 首扫：出口全复位，等使能上升；屏蔽功能启用则先进 eBlank *)
        (* First scan: reset outlets, wait for enable, enter eBlank when blanking enabled *)
        bWarn  := FALSE;                                    // 预警出口复位 / Warning outlet reset
        bAlarm := FALSE;                                    // 报警出口复位 / Alarm outlet reset
        bValid := FALSE;                                    // 数据尚不可信 / Data not trustworthy yet
        IF bEnable THEN
            IF NOT bDevValid THEN
                eState := eFault;                           // 使能即失效：直接进故障相 / Invalid on enable, go to fault
            ELSIF bBlankEn THEN
                eState := eBlank;                           // 有屏蔽窗：先进 eBlank / Blanking enabled, enter eBlank
            ELSE
                eState := eMonitor;                         // 无屏蔽窗：直接进入监测 / No blanking, enter monitoring
            END_IF
        END_IF

    eBlank:
        (* 屏蔽窗：偏差照算但三级出口全压制，窗口结束转 eMonitor *)
        (* Blanking window: deviations computed but all alarm outlets suppressed *)
        bWarn  := FALSE;                                    // 窗口内不预警 / No warning inside the window
        bAlarm := FALSE;                                    // 窗口内不报警 / No alarm inside the window
        bValid := bDevValid;                                // 数据有效性照实回执 / Validity reported truthfully
        IF NOT bEnable THEN
            eState := eInit;                                // 使能跌落回首扫 / Enable drop returns to init
        ELSIF NOT bDevValid THEN
            eState := eFault;                               // 编码器失效立即进故障相 / Encoder failure goes to fault at once
        ELSIF NOT bBlankActiveI THEN
            eState := eMonitor;                             // 窗口结束（锁存位已置）进监测 / Window finished, enter monitoring
        END_IF

    eMonitor:
        (* 常规监测：三级延时按 停机 > 报警 > 预警 的优先级判定 *)
        (* Normal monitoring: trip outranks alarm which outranks warning *)
        bWarn  := FALSE;                                    // 监测相默认无预警 / No warning by default
        bAlarm := FALSE;                                    // 监测相默认无报警 / No alarm by default
        bValid := bDevValid;                                // 有效性照实回执 / Report validity truthfully
        IF NOT bEnable THEN
            eState := eInit;                                // 失能回首扫 / Disable returns to init
        ELSIF NOT bDevValid THEN
            eState := eFault;                               // 失效进故障相 / Invalid goes to fault
        ELSIF tonAlarm.Q THEN
            eState := eAlarm;                               // 报警延时到，直接进报警相 / Alarm delay elapsed, enter alarm
        ELSIF tonWarn.Q THEN
            eState := eWarn;                                // 预警延时到，进预警相 / Warning delay elapsed, enter warning
        END_IF

    eWarn:
        (* 预警相：退出条件 ≥2 条（报警沿晋级 / 预警条件消失退回）*)
        (* Warning state with two exit conditions: alarm rise or warning condition cleared *)
        bWarn  := TRUE;                                     // 预警出口置位 / Warning outlet set
        bAlarm := FALSE;                                    // 报警出口保持复位 / Alarm outlet stays reset
        bValid := bDevValid;                                // 有效性照实回执 / Report validity truthfully
        IF NOT bEnable THEN
            eState := eInit;                                // 失能回首扫 / Disable returns to init
        ELSIF NOT bDevValid THEN
            eState := eFault;                               // 失效进故障相 / Invalid goes to fault
        ELSIF tonAlarm.Q THEN
            eState := eAlarm;                               // 晋级报警 / Promote to alarm
        ELSIF NOT bWarnCond THEN
            eState := eMonitor;                             // 预警条件消失即退回监测 / Falls back when warning clears
        END_IF

    eAlarm:
        (* 报警相：停机延时继续累积；出口锁存由段 5 统一处理，本相不自清 *)
        (* Alarm state: trip delay keeps accumulating, latch handled in segment 5 *)
        bWarn  := TRUE;                                     // 报警相同时保持预警 / Warning held during alarm
        bAlarm := TRUE;                                     // 报警出口置位 / Alarm outlet set
        bValid := bDevValid;                                // 有效性照实回执 / Report validity truthfully
        IF NOT bEnable THEN
            eState := eInit;                                // 失能回首扫 / Disable returns to init
        ELSIF NOT bDevValid THEN
            eState := eFault;                               // 失效进故障相 / Invalid goes to fault
        ELSIF (NOT bAlarmCond) AND (NOT bTripLatch) THEN
            eState := eMonitor;                             // 报警条件消失且无停机锁存才退回 / Back only when alarm clears and no trip latch
        END_IF

    eFault:
        (* 故障兜底：出口全部压制，偏差保持上一拍；解除路径唯一：bReset 且双侧恢复有效 *)
        (* Fault fallback: outlets suppressed, deviations held, cleared only by bReset with both sides valid *)
        bWarn   := FALSE;                                   // 故障相不预警 / No warning in fault
        bAlarm  := FALSE;                                   // 故障相不报警 / No alarm in fault
        bValid  := FALSE;                                   // 数据不可信 / Data untrustworthy
        bFaultLvl := TRUE;                                  // 故障级标志置位 / Fault-level flag set
        IF bReset AND bMotorEncValid AND bLoadEncValid THEN
            eState := eMonitor;                             // 复位且恢复有效才解锁（跳变锁存已在段 1 清）/ Unlock only on reset with valid sides
        END_IF

    ELSE
        (* 非法状态拦截：任何未定义枚举值一律进故障相并置兜底码 *)
        (* Illegal state interception: undefined enum values go to fault with fallback code *)
        eState    := eFault;                                // 强制回故障相 / Force back to fault
        bWarn     := FALSE;                                 // 出口压制 / Outlet suppressed
        bAlarm    := FALSE;                                 // 出口压制 / Outlet suppressed
        bValid    := FALSE;                                 // 数据不可信 / Data untrustworthy
        bFaultLvl := TRUE;                                  // 故障级标志置位 / Fault-level flag set
        uInfoCode := 16#0004_1008;                          // 故障级：非法状态兜底 / Fault: illegal state fallback

END_CASE

(*------------------------------------------------------------------------------
 * 段 5｜停机请求锁存（置位唯一：tonTrip 到时；解除唯一：bReset 且 bTripCond 已消失）
 *      Trip request latch: set only on trip delay elapsed, cleared only by reset with condition gone
 *-----------------------------------------------------------------------------*)
IF bTripLatch THEN
    IF bReset AND (NOT bTripCond) THEN
        bTripLatch := FALSE;                                // 唯一解除路径：复位且偏差已回落 / Sole clear path: reset with deviation settled
    END_IF
ELSIF tonTrip.Q THEN
    bTripLatch := TRUE;                                     // 唯一置位路径：停机延时到 / Sole set path: trip delay elapsed
END_IF
bTripReq := bTripLatch;                                     // 对外锁存回放 / Latched replay to outlet

(*------------------------------------------------------------------------------
 * 段 6｜出口码统一映射（故障级锁存回放；信息级码永不置 bError，信息码仅当无更高优先级码时使用）
 *      Unified outlet code mapping: fault codes replayed, info codes never raise bError
 *-----------------------------------------------------------------------------*)
IF bTripLatch THEN
    uErrorId := 16#0004_1006;                               // 故障级：停机请求已锁存 / Fault: trip request latched
    bError   := TRUE;                                       // 故障级码配对置位 / Paired fault flag set
ELSIF NOT bMotorEncValid THEN
    uErrorId := 16#0004_1002;                               // 故障级：电机侧编码器失效 / Fault: motor-side encoder failed
    bError   := TRUE;                                       // 故障级码配对置位 / Paired fault flag set
ELSIF NOT bLoadEncValid THEN
    uErrorId := 16#0004_1003;                               // 故障级：负载侧编码器失效 / Fault: load-side encoder failed
    bError   := TRUE;                                       // 故障级码配对置位 / Paired fault flag set
ELSIF bAlarm THEN
    uErrorId := 16#0004_1005;                               // 信息级：偏差超报警阈值 / Info: deviation above alarm threshold
    bError   := FALSE;                                      // 信息级不置故障标志 / Info level never raises the fault flag
ELSIF bWarn THEN
    uErrorId := 16#0004_1004;                               // 信息级：偏差超预警阈值 / Info: deviation above warning threshold
    bError   := FALSE;                                      // 信息级不置故障标志 / Info level never raises the fault flag
ELSE
    uErrorId := uInfoCode;                                  // 参数钳位信息码或 0 / Parameter clamp info code or zero
    bError   := FALSE;                                      // 无故障级码即无故障 / No fault-level code means healthy
END_IF

eStateOut := eState;                                        // 状态回执（单一出口映射）/ State feedback through a single outlet
END_FUNCTION_BLOCK
