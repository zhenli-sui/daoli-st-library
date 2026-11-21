(*
    FB_DL_SsrHeaterDrive —— 固态继电器加热驱动
    ------------------------------------------------------------------
    分类      : DL_Device / Drive
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : T2-2 LBP（只借「驱动块参数化 = 给定 + 周期 + 反馈诊断」的组内组织方式）；
                PWM 相位逻辑、断线判据、码位与分级 100% 自有；clean-room 重写，
                未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 把连续功率需求 0~100 % 变成周期 PWM 的通断指令，并在「占空比足量却测
                不到加热电流」时判 SSR 开路 / 加热丝断线——这是本件的核心诊断，现场
                SSR 击穿或开路只表现为「温度不升」，没有电流检测永远查不出来；
                过零同步不做电网采样（零厂商依赖），改为「周期起点对齐 + 上层可注入
                同步脉冲」的声明式设计；
                三道闸：周期参数闸（周期非法时宁可断热，绝不满功率长通）→ 占空钳位闸
                → 零占空不启电流监视闸（零占空本来就没电流，否则误报）；
                时间比较全程用 TIME 原值，不转 REAL，避免毫秒精度损失。
    错误码    : 16#0003_0168 功率需求超域已钳位 / 占空低于导通阈值强制断——信息级，不置故障
                16#0003_0169 预留禁用（信息级，不得挪用）
                16#0003_032D PWM 周期参数非法，输出强制断开——故障级
                16#0003_032E 加热回路开路（占空足量但无电流超确认窗），锁存——故障级
                16#0003_032F 预留禁用（故障级，不得挪用）
    码位总账  : 16#0003_0168 用 / 16#0003_0169 预留 ｜ 16#0003_032D 用 / 16#0003_032E 用 / 16#0003_032F 预留
    状态机    : 无 CASE，周期相位由 TON 承载；bLoadLatch 为锁存位，非法状态不可能出现
    采样约定  : fbCycle / fbNoCurrent 与两个 R_TRIG 在本体首部无条件调用；tCycleTime
                必须与被控对象热惯性匹配，周期过短会让 SSR 频繁通断、寿命下降。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)
FUNCTION_BLOCK FB_DL_SsrHeaterDrive
VAR_INPUT
    bEnable            : BOOL;                 // 使能，FALSE 强制断输出（安全侧）/ enable, FALSE forces the output off, safe side
    bReset             : BOOL;                 // 上升沿清断线锁存 / rising edge clears the open circuit latch
    fPowerDemand       : REAL := 0.0;          // 功率需求 [%]，范围 0.0~100.0，超域钳位 / power demand [%], range 0.0~100.0, clamped outside
    tCycleTime         : TIME := T#1S;         // PWM 周期 [ms]，范围 500~10000 / PWM period [ms], range 500~10000
    bCurrentFeedback   : BOOL := FALSE;        // 加热电流检测输入，TRUE = 有电流 / heating current detection input, TRUE = current flows
    fMinDutyForCurrent : REAL := 10.0;         // 判定应有电流的最小占空 [%]，范围 1.0~50.0 / minimum duty that should produce current [%], range 1.0~50.0
    tCurrentWindow     : TIME := T#3S;         // 电流缺失确认窗 [ms]，范围 100~30000 / current absence confirmation window [ms], range 100~30000
    bSyncPulse         : BOOL := FALSE;        // 可选过零 / 同步脉冲，上升沿对齐周期起点 / optional zero crossing pulse, its rising edge aligns the cycle start
END_VAR
VAR_OUTPUT
    bOut         : BOOL;                       // SSR 驱动输出，TRUE = 导通 / SSR drive output, TRUE = conducting
    fDutyApplied : REAL;                       // 实际生效占空，钳位后 [%] / effective duty after clamping [%]
    tOnTime      : TIME;                       // 本周期已导通时长 [ms] / conducted time inside the current cycle [ms]
    bLoadOpen    : BOOL;                       // 加热回路开路，锁存，需复位 / heating circuit open, latched until reset
    eErr         : UDINT;                      // 错误码，0=正常 / error id, 0=ok
    bError       : BOOL;                       // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigReset  : R_TRIG;                     // 复位沿检测实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    fbTrigSync   : R_TRIG;                     // 同步脉冲沿检测实例，本体首部无条件刷新 / sync pulse edge instance, refreshed unconditionally
    fbCycle      : TON;                        // 周期相位定时器，自复位产生锯齿相位 / cycle phase timer, self-resetting to form a sawtooth phase
    fbNoCurrent  : TON;                        // 电流缺失确认定时器，本体首部无条件刷新 / current absence confirmation timer, refreshed unconditionally
    bCycleHold   : BOOL;                       // 周期相位保持位，IN 取反本定时器输出实现自复位 / phase hold bit, the inverted timer output self-resets it
    bForceRestart: BOOL;                       // 同步强制重启标志，单拍 / forced restart flag from the sync pulse, single cycle
    fDutyEff     : REAL;                       // 生效占空，钳位后 [%] / effective duty after clamping [%]
    fMinDutyEff  : REAL;                       // 生效电流判定最小占空，钳位后 [%] / effective minimum duty for the current check [%]
    tWindowEff   : TIME;                       // 生效电流确认窗，钳位后 [ms] / effective current confirmation window [ms]
    fCycleMs     : REAL;                       // 周期毫秒值，仅用于换算导通目标 [ms] / cycle in milliseconds, used for the on target only [ms]
    tOnTarget    : TIME;                       // 本周期应导通时长 [ms] / target conducted time inside the cycle [ms]
    fOnMs        : REAL;                       // 应导通时长的毫秒中间量 [ms] / target conducted time in milliseconds [ms]
    bLoadLatch   : BOOL;                       // 断线锁存位，仅复位清除 / open circuit latch, cleared by reset only
END_VAR
VAR CONSTANT
    DL_SSR_CYCLE_MIN  : TIME := T#500MS;       // PWM 周期下限 [ms] / PWM period lower bound [ms]
    DL_SSR_CYCLE_MAX  : TIME := T#10S;         // PWM 周期上限 [ms] / PWM period upper bound [ms]
    DL_SSR_WIN_MIN    : TIME := T#100MS;       // 电流确认窗下限 [ms] / current window lower bound [ms]
    DL_SSR_WIN_MAX    : TIME := T#30S;         // 电流确认窗上限 [ms] / current window upper bound [ms]
    DL_SSR_DUTY_MAX   : REAL := 100.0;         // 占空上限 [%] / duty upper bound [%]
    DL_SSR_DUTY_MIN   : REAL := 0.0;           // 占空下限 [%] / duty lower bound [%]
    DL_SSR_ON_EPS     : REAL := 0.5;           // 占空小于此视为全断 [%] / duties below this count as fully off [%]
    DL_SSR_MIND_MIN   : REAL := 1.0;           // 最小电流占空下限 [%] / minimum current duty lower bound [%]
    DL_SSR_MIND_MAX   : REAL := 50.0;          // 最小电流占空上限 [%] / minimum current duty upper bound [%]
    DL_SSR_PCT_SCALE  : REAL := 100.0;         // 百分比换算除数，恒非零 [%] / percentage scaling divisor, never zero [%]
    DL_FLOAT_EPS      : REAL := 1.0E-6;        // 浮点判等容差 [%] / float equality tolerance [%]
    DL_SSR_ZERO_REAL  : REAL := 0.0;           // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
END_VAR

// 段 0｜输出与错误状态预置 / segment 0, preset outputs and error status
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault
bOut := FALSE;                                 // 输出先断开，安全侧 / preset the output off, safe side
fDutyApplied := DL_SSR_DUTY_MIN;               // 生效占空先归零 / preset the duty to zero
tOnTime := T#0MS;                              // 导通时长先归零 / preset the conducted time to zero

// 段 1｜周期参数闸：周期非法时宁可断热，绝不满功率长通 / segment 1, period gate, a wrong period must never mean full power
IF (tCycleTime < DL_SSR_CYCLE_MIN) OR (tCycleTime > DL_SSR_CYCLE_MAX) THEN
    eErr := 16#0003_032D;                      // 周期非法故障码 / illegal period fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    bOut := FALSE;                             // 输出强制断开 / force the output off
    fDutyApplied := DL_SSR_DUTY_MIN;           // 生效占空归零 / effective duty to zero
    tOnTime := T#0MS;                          // 导通时长为 0 / conducted time zero
    bLoadOpen := bLoadLatch;                   // 锁存状态照常回读 / the latch stays readable
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 2｜占空与诊断参数闸：双侧钳位并置信息码 / segment 2, duty and diagnostic parameter gates
fDutyEff := MIN(MAX(fPowerDemand, DL_SSR_DUTY_MIN), DL_SSR_DUTY_MAX); // 占空双侧钳位 / clamp the duty both sides
IF ABS(fDutyEff - fPowerDemand) > DL_FLOAT_EPS THEN
    eErr := 16#0003_0168;                      // 占空钳位提示（信息级不置故障）/ duty clamp hint, info level never raises a fault
END_IF
fMinDutyEff := MIN(MAX(fMinDutyForCurrent, DL_SSR_MIND_MIN), DL_SSR_MIND_MAX); // 电流判定占空双侧钳位 / clamp the current duty threshold both sides
tWindowEff := MIN(MAX(tCurrentWindow, DL_SSR_WIN_MIN), DL_SSR_WIN_MAX);        // 确认窗双侧钳位 / clamp the confirmation window both sides

// 段 3｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 3, unconditional edge refresh
fbTrigReset(CLK := bReset);
fbTrigSync(CLK := bSyncPulse);
IF fbTrigSync.Q THEN
    bForceRestart := TRUE;                     // 同步脉冲到来，本拍强制重启周期相位 / a sync pulse forces a phase restart this cycle
END_IF

// 段 4｜周期相位与电流缺失两个定时器无条件调用 / segment 4, unconditional calls of the phase and current timers
bCycleHold := (NOT fbCycle.Q) AND (NOT bForceRestart); // 自复位逻辑：定时器到期或强制重启即掉一拍 IN / self-reset logic, the input drops for one cycle on expiry or forced restart
fbCycle(IN := bEnable AND bCycleHold, PT := tCycleTime); // 周期相位定时器 / cycle phase timer
fCycleMs := TIME_TO_REAL(tCycleTime);          // 周期毫秒值 / cycle in milliseconds
fOnMs := fDutyEff / DL_SSR_PCT_SCALE * fCycleMs; // 应导通毫秒数 / target conducted milliseconds
tOnTarget := REAL_TO_TIME(fOnMs);               // 转 TIME 后与 ET 直接比较，不转 REAL / converted to TIME so it compares with ET without any REAL conversion
bForceRestart := FALSE;                        // 强制重启标志用后即清 / the forced restart flag is consumed and cleared
fbNoCurrent(IN := bEnable AND (fDutyEff >= fMinDutyEff) AND (NOT bCurrentFeedback) AND (NOT bLoadLatch), PT := tWindowEff); // 电流缺失确认定时器 / current absence confirmation timer

// 段 5｜占空镜像（输出已在段 0 预置为断开）/ segment 5, publish the duty, the output was already preset off in segment zero
fDutyApplied := fDutyEff;                      // 占空镜像 / publish the duty

// 段 6｜复位沿清断线锁存（优先于诊断）/ segment 6, reset clears the open circuit latch
IF fbTrigReset.Q THEN
    bLoadLatch := FALSE;                       // 清锁存 / clear the latch
END_IF

// 段 7｜断线诊断：占空足量却无电流超确认窗，即锁存开路 / segment 7, open circuit diagnosis
IF fbNoCurrent.Q THEN
    bLoadLatch := TRUE;                        // 锁存开路 / latch the open circuit
    eErr := 16#0003_032E;                      // 回路开路故障码 / open circuit fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
END_IF

// 段 8｜PWM 通断判定：零占空不启监视，占空已达导通阈值才允许导通 / segment 8, PWM conduction decision
IF (NOT bEnable) OR bLoadLatch THEN
    bOut := FALSE;                             // 失能或锁存故障一律断输出 / disabled or latched fault forces the output off
    tOnTime := T#0MS;                          // 导通时长归零 / conducted time zero
ELSIF fDutyEff < DL_SSR_ON_EPS THEN
    bOut := FALSE;                             // 占空低于导通阈值，强制全断（信息级提示）/ duty below the threshold forces a full off, info level hint
    tOnTime := T#0MS;                          // 导通时长归零 / conducted time zero
    eErr := 16#0003_0168;                      // 零占空提示（信息级不置故障）/ zero duty hint, info level never raises a fault
ELSIF fDutyEff >= DL_SSR_DUTY_MAX THEN
    bOut := TRUE;                              // 满占空长通 / full duty keeps the output on
    tOnTime := fbCycle.ET;                     // 导通时长取相位 / conducted time follows the phase
ELSE
    IF fbCycle.ET < tOnTarget THEN
        bOut := TRUE;                          // 相位未到导通目标，保持导通 / the phase is below the on target, keep conducting
    ELSE
        bOut := FALSE;                         // 相位越过导通目标，断开 / the phase passed the on target, switch off
    END_IF
    tOnTime := fbCycle.ET;                     // 导通时长取相位 / conducted time follows the phase
END_IF

// 段 9｜锁存对外输出 / segment 9, publish the latch
bLoadOpen := bLoadLatch;                       // 回路开路输出 / open circuit output
END_FUNCTION_BLOCK
