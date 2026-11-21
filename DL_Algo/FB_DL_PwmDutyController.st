(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PwmDutyController
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（MIN / MAX / ABS），零厂商方言
 * 功能描述 (Function)   : 时间比例慢速 PWM 控制器。把 0~100% 占空比调制成周期级
 *                         布尔输出，驱动固态继电器（SSR）/接触器做加热功率调节，
 *                         避免高频开关对触点与电网的冲击。周期 tPeriod 内按占空比
 *                         分配导通时间；含最短导通/关断时间抑制（过窄脉冲跨周期
 *                         累加补偿，不足差额记入债务下周期叠加）、反相输出。
 *                         输出可与 PID 输出直连（0~100% 占空比）。
 * 开源溯源 (Origin)     : 原创实现。欠脉冲跨周期补偿思想源自 PID_Compact 的
 *                         脉冲发生器公开行为定义，clean-room 编写，
 *                         未复制任何厂商私有库源码。
 * 本文件内含       : TYPE  E_DL_PwmState（配套枚举，归属 DL_Algo）
 *                    FB    FB_DL_PwmDutyController
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: MIN / MAX / ABS
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 周期/占空比/债务钳位
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 四态 ENUM+CASE+ELSE
 *                         R7 N/A（无定时器/边沿实例，相位自累加）
 * 【边界披露 / Boundary disclosure】
 *   B1 tPeriod < tMinOn + tMinOff：钳位 tPeriod := tMinOn + tMinOff 置 16#0002_0801。
 *   B2 tPeriod 低于 1s 下限：钳位到 1s 并置 16#0002_0801。
 *   B3 占空比越界钳位 0..100 置 16#0002_0001。
 *   B4 债务钳位 0..1 防无限累积；100% 占空比清空债务（全开无需补偿）。
 *   B5 使能跌落立即输出 FALSE 且债务清零，恢复后从周期起点重新计相位。
 *   B6 最短导通抑制：有效 ON 时间 < tMinOn 的窄脉冲并入债务，输出保持关断；
 *      最短关断抑制：OFF 间隙 < tMinOff 时合并为全周期导通（债务清零）。
 * 【验收向量 / Acceptance vectors】
 *   V1  fDuty=50，tPeriod=10S，tSampleTime=100MS → 每周期导通 5.0s、关断 5.0s，
 *       bPwmOut 方波占空比 50%，nCycleCount 每秒递增 0.1
 *   V2  fDuty=100 → bPwmOut 恒 TRUE、fDebt=0；fDuty=0 → 恒 FALSE
 *   V3  fDuty=0.2（ON 期望 20ms < tMinOn=500MS）→ 窄脉冲并入债务，bPwmOut 保持
 *       FALSE；连续 50 周期后债务足额释放为一个 ≥500ms 的长脉冲
 *   V4  fDuty=99.9（OFF 期望 10ms < tMinOff=500MS）→ 合并为全周期导通
 *   V5  tMinOn+tMinOff=12S > tPeriod=10S → tPeriod 钳位 12S、16#0002_0801
 *   V6  fDuty=150 → 钳位 100、16#0002_0001
 *   V7  bInvert=TRUE → bPwmOut 反相；bEnable=FALSE → bPwmOut 强制 FALSE
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 04 · Phase 3 · DL_Algo 批次）
 *   2026-11-15  v1.0.1  阶段五终审精修：首次使能当拍立即结算占空比配额，
 *                       消除首周期无条件关断；bInit 由死变量转为有效标志
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PwmState（归属 DL_Algo，与 FB_DL_PwmDutyController 同文件）
 * 含义: 慢速 PWM 相位状态机。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_PwmState :
(
    eIdle     := 0,   // 空闲态：未使能，输出关断 / Idle state, output off
    eOnPhase  := 10,  // 导通段：周期相位在有效占空比区间内 / On phase, cycle phase within effective duty
    eOffPhase := 20,  // 关断段：周期相位超出有效占空比区间 / Off phase, phase beyond effective duty
    eFault    := 99   // 故障兜底态：非法状态拦截，自动回空闲 / Fault fallback, auto recover to idle
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_PwmDutyController
 * 调用约定: 每个扫描周期无条件调用一次；占空比可在周期中途修改，下周期生效配额。
 * 无状态泄漏: 全部状态驻留于实例私有 VAR，可多实例并行互不影响。
 * 相位披露: fPhase 每拍累加 fDt/fPeriod，达到 1.0 回卷并结算本周期配额；
 *           输出与 PID 占空比直连，脉宽分辨率 = 扫描周期（慢速 PWM 语义）。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_PwmDutyController
VAR_INPUT
    bEnable     : BOOL := FALSE;      // 使能标志，FALSE 立即关断并清债务 / Enable flag, FALSE forces off and clears debt
    fDuty       : REAL := 0.0;        // 占空比输入 [%]，0..100，越界钳位 / Duty cycle input [%], 0..100 clamped
    tPeriod     : TIME := T#10S;      // PWM 周期 [s]，下限 1s 且须 >= 最短开关时间和 / PWM period [s], min 1s
    tMinOn      : TIME := T#500MS;    // 最短导通时间 [s]，窄脉冲并入债务 / Minimum on time [s], narrow pulses deferred
    tMinOff     : TIME := T#500MS;    // 最短关断时间 [s]，两者之和须 < tPeriod / Minimum off time [s]
    bInvert     : BOOL := FALSE;      // 反相输出，TRUE 时输出取反 / Invert output, TRUE inverts the boolean
    tSampleTime : TIME := T#100MS;    // 采样周期 [s]，小于 10ms 钳位为 10ms / Sample time [s], clamped to 10ms
END_VAR
VAR_OUTPUT
    bPwmOut     : BOOL;               // PWM 布尔输出（已含反相处理） / PWM boolean output, invert applied
    fDutyEff    : REAL;               // 本周期实际有效占空比 [%]，含债务补偿 / Effective duty this cycle [%] with debt
    nCycleCount : UDINT;              // 已完成周期计数 [个] / Completed cycle count
    bError      : BOOL;               // 故障标志（瞬时，逐拍重算） / Fault flag, transient, recomputed every scan
    uErrorId    : UDINT;              // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fPhase      : REAL;               // 周期相位 [0..1] / Cycle phase [0..1]
    fDutyEffInt : REAL;               // 本周期有效占空比（内部小数）[0..1] / Effective duty fraction [0..1]
    fDebt       : REAL;               // 欠脉冲债务 [0..1]，跨周期累加 / Pulse debt [0..1], accumulated across cycles
    bOnState    : BOOL;               // 原始导通状态（未反相） / Raw on state before inversion
    fPeriodSec  : REAL;               // 钳位后周期 [s] / Clamped period [s]
    fMinOnSec   : REAL;               // 最短导通时间 [s] / Minimum on time [s]
    fMinOffSec  : REAL;               // 最短关断时间 [s] / Minimum off time [s]
    fDt         : REAL;               // 折算后的采样周期 [s] / Converted sample period [s]
    fDutyC      : REAL;               // 钳位后占空比 [%] / Clamped duty [%]
    fDutyReq    : REAL;               // 本周期占空比请求（含债务）[0..1] / Duty request with debt [0..1]
    tPeriodEff  : TIME;               // 钳位后周期时刻值 / Clamped period time value
    bInit       : BOOL;               // 首扫标志，FALSE 触发配额立即结算 / First-scan flag, FALSE settles quota immediately
    eState      : E_DL_PwmState;      // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR CONSTANT
    DL_PWM_DUTY_MAX   : REAL := 100.0;  // 占空比上限 [%] / Duty cycle upper limit [%]
    DL_PWM_PERIOD_MIN : TIME := T#1S;   // 周期下限 [s] / Period lower limit [s]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜公共参数处理（通用约定 0-1）：周期钳位、故障码瞬时清零
 *      Common handling: period clamp, transient error code reset
 *-----------------------------------------------------------------------------*)
uErrorId := 16#0000_0000;               // 故障码逐拍重算 / Error code recomputed every scan
bError   := FALSE;                      // 故障标志逐拍重算 / Fault flag recomputed every scan

IF tSampleTime < T#10MS THEN
    fDt      := TIME_TO_REAL(T#10MS) / 1000.0; // 非法周期钳位为 10ms / Illegal period clamped to 10ms
    uErrorId := 16#0002_0002;           // 采样周期非法已钳位 / Sample time illegal, clamped
ELSE
    fDt      := TIME_TO_REAL(tSampleTime) / 1000.0; // 周期换算为秒 [s] / Period converted to seconds [s]
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜周期钳位（边界 B1/B2）：先保证 >= 最短开关时间和，再保证 >= 1s 下限
 *      Period clamping: ensure >= min on+off sum first, then >= 1s floor
 *-----------------------------------------------------------------------------*)
tPeriodEff := tPeriod;                  // 周期初值 / Initial period value
IF tMinOn + tMinOff > tPeriodEff THEN
    tPeriodEff := tMinOn + tMinOff;     // 周期放大到最短开关时间和 / Period raised to min on+off sum
    uErrorId   := 16#0002_0801;         // 周期小于最短开关时间和已钳位 / Period below min on+off sum, clamped
END_IF
IF tPeriodEff < DL_PWM_PERIOD_MIN THEN
    tPeriodEff := DL_PWM_PERIOD_MIN;    // 周期放大到 1s 下限 / Period raised to 1s floor
    uErrorId   := 16#0002_0801;         // 周期非法已钳位 / Period illegal, clamped
END_IF

fPeriodSec := TIME_TO_REAL(tPeriodEff) / 1000.0; // 周期换算为秒 [s] / Period converted to seconds [s]
fMinOnSec  := TIME_TO_REAL(tMinOn) / 1000.0;     // 最短导通换算为秒 [s] / Min on time in seconds [s]
fMinOffSec := TIME_TO_REAL(tMinOff) / 1000.0;    // 最短关断换算为秒 [s] / Min off time in seconds [s]

(*------------------------------------------------------------------------------
 * 段 3｜占空比钳位（边界 B3）：0..100，越界告警不中断
 *      Duty clamping: 0..100, over-range warns without stopping
 *-----------------------------------------------------------------------------*)
fDutyC := fDuty;                        // 占空比初值 / Initial duty value
IF fDutyC < 0.0 THEN
    fDutyC   := 0.0;                    // 下越界钳位 / Under-range clamped
    uErrorId := 16#0002_0001;           // 参数越界已钳位 / Parameter out of range, clamped
END_IF
IF fDutyC > DL_PWM_DUTY_MAX THEN
    fDutyC   := DL_PWM_DUTY_MAX;        // 上越界钳位 / Over-range clamped
    uErrorId := 16#0002_0001;           // 参数越界已钳位 / Parameter out of range, clamped
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜使能失效语义（边界 B5）：立即关断、清债务、相位归零、回空闲
 *      Disabled semantics: immediate off, debt cleared, phase reset, idle
 *-----------------------------------------------------------------------------*)
IF NOT bEnable THEN
    bPwmOut     := FALSE;               // 输出强制关断（反相不生效，安全优先）/ Output forced off, invert bypassed for safety
    bOnState    := FALSE;               // 原始导通状态清零 / Raw on state cleared
    fPhase      := 0.0;                 // 相位归零 / Phase reset
    fDebt       := 0.0;                 // 债务清零 / Debt cleared
    fDutyEffInt := 0.0;                 // 本周期有效占空比清零 / Effective duty cleared
    fDutyEff    := 0.0;                 // 输出占空比清零 / Output duty cleared
    eState      := eIdle;               // 强制空闲 / Force idle
    bInit       := FALSE;               // 复位首扫标志，重使能当拍立即结算配额 / Reset init flag, settle quota on re-enable
ELSE
    (*--------------------------------------------------------------------------
     * 段 5a｜相位推进与周期结算：fPhase >= 1.0 回卷，结算本周期配额
     *     Phase advance and cycle settlement: wrap at 1.0, settle quota
     *-------------------------------------------------------------------------*)
    fPhase := fPhase + fDt / fPeriodSec; // 相位累加 [0..1] / Phase accumulation [0..1]

    IF (fPhase >= 1.0) OR (NOT bInit) THEN
        IF fPhase >= 1.0 THEN
            fPhase := fPhase - 1.0;     // 相位回卷 / Phase wrapped
            IF fPhase >= 1.0 THEN
                fPhase := 0.0;          // 单拍跨度超周期时强制归零（防御）/ Forced reset if one scan exceeds period
            END_IF
        END_IF

        fDutyReq := fDutyC / DL_PWM_DUTY_MAX + fDebt; // 占空比请求含债务 [0..1] / Duty request with debt [0..1]
        fDutyEffInt := MIN(fDutyReq, 1.0);            // 本周期配额上限 100% / Cycle quota capped at 100%
        fDebt := fDutyReq - fDutyEffInt;              // 剩余债务 / Remaining debt
        fDebt := MIN(MAX(fDebt, 0.0), 1.0);           // 债务钳位防无限累积 / Debt clamped against runaway

        (* 最短导通抑制（边界 B6 前半）：窄脉冲并入债务 / Min-on suppression: narrow pulse merged into debt *)
        IF (fDutyEffInt > 0.0) AND (fDutyEffInt * fPeriodSec < fMinOnSec) THEN
            fDebt       := MIN(fDebt + fDutyEffInt, 1.0); // 窄脉冲差额记账 / Narrow pulse booked into debt
            fDutyEffInt := 0.0;                            // 本周期保持关断 / Cycle held off
        END_IF

        (* 最短关断抑制（边界 B6 后半）：OFF 间隙过窄合并为全开 / Min-off suppression: narrow gap merged to full on *)
        IF (fDutyEffInt < 1.0) AND ((1.0 - fDutyEffInt) * fPeriodSec < fMinOffSec) THEN
            fDutyEffInt := 1.0;         // 合并为全周期导通 / Merged to full-cycle on
            fDebt       := 0.0;         // 全开无需补偿，债务清零 / Debt cleared, full on needs no compensation
        END_IF

        fDutyEff := fDutyEffInt * DL_PWM_DUTY_MAX; // 有效占空比输出 [%] / Effective duty output [%]
        nCycleCount := nCycleCount + 1;             // 周期计数递增 / Cycle count incremented
        bInit := TRUE;                              // 首扫配额已结算 / Initial quota settled
    END_IF

    (*--------------------------------------------------------------------------
     * 段 5b｜主状态机（红线 R6）：四态 ENUM + CASE + ELSE 兜底，相位派生覆盖
     *     Main state machine: four-state ENUM + CASE with phase-derived coverage
     *-------------------------------------------------------------------------*)
    CASE eState OF

        eIdle:  // 空闲态：使能后按相位派生进入导通或关断段 / Idle: derive on/off phase after enable
            IF fPhase < fDutyEffInt THEN
                eState := eOnPhase;     // 相位在配额内，导通 / Phase within quota, on
            ELSE
                eState := eOffPhase;    // 相位超配额，关断 / Phase beyond quota, off
            END_IF

        eOnPhase:  // 导通段：相位越过配额即切换关断 / On phase: switch off when phase exceeds quota
            IF fPhase >= fDutyEffInt THEN
                eState := eOffPhase;    // 切换到关断段 / Switch to off phase
            END_IF

        eOffPhase:  // 关断段：新周期配额生效即切换导通 / Off phase: switch on when new quota applies
            IF fPhase < fDutyEffInt THEN
                eState := eOnPhase;     // 切换到导通段 / Switch to on phase
            END_IF

        eFault:  // 故障兜底态：无复位引脚，当拍回空闲重派生 / Fault fallback: recover to idle, re-derive
            eState := eIdle;            // 自动恢复空闲 / Auto recover to idle

        ELSE  // 非法状态拦截：任何未定义状态一律进故障态并置码 / Illegal state interception
            eState   := eFault;         // 强制故障态 / Force fault state
            uErrorId := 16#0002_0005;   // 非法状态兜底 / Illegal state fallback
            bError   := TRUE;           // 故障标志置位 / Fault flag set

    END_CASE;

    bOnState := (eState = eOnPhase);    // 原始导通状态派生 / Raw on state derived
    bPwmOut  := (bOnState <> bInvert);  // 反相处理后输出 / Output after inversion
END_IF
END_FUNCTION_BLOCK
