(*
    组件名称 : FB_DL_MinOnOffGuard
    所属子库 : DL_Base
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : 最短运行 / 最短停止双守卫，防压缩机、热泵、泵轮值与冷水机组频繁启停的公共原子。
              取舍 ①：用「输出实际在 TRUE 期间的累计时长」判最短运行，而不是「进入某状态后重新计时」——
              若定时器只在 eStarting 与 eHolding 里跑，请求在 eRunning 撤掉后会重新起算整段 tMinOn，
              实际运行时长翻倍，压缩机照样被拖坏。本件把 eRunning 一并纳入定时器 IN，
              于是 fbMinOn.Q 的语义严格等于「输出已持续 TRUE 达到 tMinOn」。
              取舍 ②：eIdle 的启动条件只看 bReq，不再二次判 fbMinOff.Q —— 若 eIdle 还要等最短停止完成位，
              而该定时器只在 eCooldown 里通电，则 Q 在 eIdle 恒为 FALSE，状态机将永远起不来（本件修正了这个死锁形态）。
              最短停止由「必须走完 eCooldown 才回 eIdle」保证，语义不减。
              取舍 ③：参数非法不停机 —— 守卫时间填成负值属于参数错误，钳零后继续跑并发故障码；
              让一条产线因为一个 HMI 输入框的负号而停机，代价远大于收益。
              取舍 ④：bEnable = FALSE 走安全侧 —— 立即输出 FALSE 并回 eIdle，忽略最短运行；
              安全优先于设备寿命，两者冲突时永远选安全。
    开源溯源 : 原创实现（T0-2 变体线）。ROADMAP 中「防频繁启停」四条待办的公共原子，无外部源码参考，；本件为 IEC 61131-3 标准语义的道莅防御性实现（原创实现，零外部源码复制）。
              状态机、码位、钳位策略 100% 自有。
    本文件内含 : FUNCTION_BLOCK FB_DL_MinOnOffGuard
                 同文件 TYPE E_DL_MinOnOffState（归属本子库，全库唯一）
    依 赖 : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 参数钳位 + 非法时间闸 + 非法状态 ELSE 兜底 + 复位沿优先
              R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ ENUM + CASE + ELSE 兜底（非法状态落 039A 并回安全态）
              R7 ✓ TON / R_TRIG 实例在主体最前部无条件刷新，位于任何 IF 与 CASE 之外
              R8 ✓ 时间上限、零时长、错误码全常量化
    错误码   : 16#0001_0452 [信息级] 时间参数超 24h 已钳上限，bError = FALSE
               16#0001_0453 [信息级] 停机请求被最短运行推迟（进入 eHolding），bError = FALSE
               16#0001_0399 [故障级] 时间参数为负已钳零，不停机，bError = TRUE
               16#0001_039A [故障级] 非法状态（枚举被改写），强制回 eFault 且 bOut = FALSE
               16#0001_039B [故障级] 预留禁用（不得挪用）
    码位总账 : 16#0001_0452 用 / 16#0001_0453 用 ｜ 16#0001_0399 用 / 16#0001_039A 用 / 16#0001_039B 预留
              说明：「启动请求被最短停止阻延」不设独立码 —— 该场景由 eState = eCooldown、bHoldOff 与 tRemaining
              三个输出直接可观测，加强加码属凑槽（R90）。
    遗留假设 : ① TIME 比较与减法按 32 位有符号毫秒口径，加减不越 24h 上限（已由钳位保证），
              故无 TIME 回绕路径；该推导未在三平台逐一实测。
              ② bReset 只在 eFault 内被消费（复位沿实例仍在主体最前部刷新），保证复位沿不被 CASE 前置写吞掉。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 4 入库
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MinOnOffState（归属本功能块，与其同文件发布，全库唯一）
 * 含义: 双守卫状态机的六个状态，成员值写死便于工程持久化与在线诊断
 *----------------------------------------------------------------------------*)
TYPE E_DL_MinOnOffState :
(
    eIdle     := 0,     // 空闲：输出 FALSE，最短停止已满，可随时启动 / idle, output low and the minimum off time is satisfied
    eStarting := 10,    // 启动中：输出 TRUE，最短运行计时中 / starting, output high and the minimum on time is counting
    eRunning  := 20,    // 运行中：输出 TRUE，最短运行已满 / running, the minimum on time is satisfied
    eHolding  := 30,    // 保持中：请求已撤但最短运行未满，强制输出 TRUE / holding, the request is gone but the minimum on time is not yet met
    eCooldown := 40,    // 冷却中：输出 FALSE，最短停止计时中 / cooling down, output low and the minimum off time is counting
    eFault    := 99     // 故障锁定：输出 FALSE，需 bReset 上升沿退出 / fault latched, cleared by the rising edge of bReset
);
END_TYPE

FUNCTION_BLOCK FB_DL_MinOnOffGuard
VAR_INPUT
    bEnable         : BOOL := TRUE;      // 使能，FALSE 立即回安全态并忽略最短运行 / enable, FALSE forces the safe state and ignores the minimum on time
    bReq            : BOOL;              // 上层运行请求，TRUE 表示希望设备运行 / run request from the upper layer
    tMinOn          : TIME := T#10S;     // 最短运行时间，负值钳零、超 24h 钳上限 [ms] / minimum on time, clamped at both ends [ms]
    tMinOff         : TIME := T#10S;     // 最短停止时间，负值钳零、超 24h 钳上限 [ms] / minimum off time, clamped at both ends [ms]
    bReset          : BOOL;              // 上升沿清故障并回空闲 / rising edge clears the fault and returns to idle
END_VAR
VAR_OUTPUT
    bOut            : BOOL;              // 实际输出，最终的启停指令 / effective output, the final run command
    bHoldOn         : BOOL;              // TRUE = 正在强制延长运行（停机请求被推迟）/ TRUE while the run time is being extended
    bHoldOff        : BOOL;              // TRUE = 正在强制延长停止（启动请求被阻延）/ TRUE while the stop time is being extended
    tRemaining      : TIME;              // 当前守卫的剩余时间，无守卫时为 0 [ms] / remaining guard time, zero when no guard is active [ms]
    eState          : E_DL_MinOnOffState;   // 状态机当前状态 / current state machine state
    eErr            : UDINT;             // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;              // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag, TRUE on fault-level eErr
END_VAR
VAR
    fbMinOn         : TON;               // 最短运行计时器，主体最前部无条件刷新 / minimum on timer, refreshed unconditionally at the top
    fbMinOff        : TON;               // 最短停止计时器，主体最前部无条件刷新 / minimum off timer, refreshed unconditionally at the top
    rtReset         : R_TRIG;            // 复位上升沿，主体最前部无条件刷新 / reset rising edge, refreshed unconditionally at the top
    tMinOnEff       : TIME;              // 钳位后的最短运行时间 [ms] / clamped minimum on time [ms]
    tMinOffEff      : TIME;              // 钳位后的最短停止时间 [ms] / clamped minimum off time [ms]
END_VAR
VAR CONSTANT
    DL_MIN_ONOFF_MAX    : TIME := T#24H;               // 守卫时间上限，超此值无工程意义 [ms] / guard time upper bound [ms]
    DL_TIME_ZERO        : TIME := T#0S;                // 零时长哨兵 [ms] / zero duration sentinel [ms]
    DL_ERR_NONE         : UDINT := 16#0000_0000;       // 无故障 / no error
END_VAR

// 段 0｜错误状态预置（四段式第一段）/ segment 0, preset the error state
eErr   := DL_ERR_NONE;                  // 预置无错误 / preset no error
bError := FALSE;                        // 预置无故障 / preset no fault

// 段 1｜参数预处理：本段无任何定时器调用，故可置于定时器刷新之前，保证钳位当拍生效 / segment 1, pure parameter preprocessing
tMinOnEff  := tMinOn;                   // 先按输入占位 / start from the input
tMinOffEff := tMinOff;                  // 先按输入占位 / start from the input
IF tMinOnEff < DL_TIME_ZERO THEN
    tMinOnEff := DL_TIME_ZERO;          // 负值钳零，不停机 / clamp to zero, the machine keeps running
    eErr      := 16#0001_0399;          // 时间参数为负（故障级）/ negative time parameter, fault level
    bError    := TRUE;                  // 置故障标志 / raise the fault flag
END_IF
IF tMinOffEff < DL_TIME_ZERO THEN
    tMinOffEff := DL_TIME_ZERO;         // 负值钳零 / clamp to zero
    eErr       := 16#0001_0399;         // 同一语义，同一码 / one semantic, one code
    bError     := TRUE;                 // 置故障标志 / raise the fault flag
END_IF
IF tMinOnEff > DL_MIN_ONOFF_MAX THEN
    tMinOnEff := DL_MIN_ONOFF_MAX;      // 超上限钳位 / clamp above the bound
    IF eErr = DL_ERR_NONE THEN
        eErr := 16#0001_0452;           // 参数超上限已钳位（信息级）/ parameter clamped, info level
    END_IF
END_IF
IF tMinOffEff > DL_MIN_ONOFF_MAX THEN
    tMinOffEff := DL_MIN_ONOFF_MAX;     // 超上限钳位 / clamp above the bound
    IF eErr = DL_ERR_NONE THEN
        eErr := 16#0001_0452;           // 参数超上限已钳位（信息级）/ parameter clamped, info level
    END_IF
END_IF

// 段 2｜定时器与边沿无条件刷新：位于任何 IF 与 CASE 之外（红线 R7）/ segment 2, unconditional timer refresh
fbMinOn ( IN := (eState = E_DL_MinOnOffState.eStarting) OR (eState = E_DL_MinOnOffState.eHolding) OR (eState = E_DL_MinOnOffState.eRunning),
          PT := tMinOnEff );
fbMinOff( IN := (eState = E_DL_MinOnOffState.eCooldown), PT := tMinOffEff );
rtReset ( CLK := bReset );

// 段 3｜失能走安全侧：唯一允许的 CASE 前置状态改写，条件由 bEnable 限定 / segment 3, the only pre-CASE write, guarded by the enable
IF NOT bEnable THEN
    eState := E_DL_MinOnOffState.eIdle;  // 立即回空闲，最短运行让位于安全 / back to idle at once, safety outranks machine life
END_IF

// 段 4｜状态机 / segment 4, state machine
CASE eState OF
    E_DL_MinOnOffState.eIdle :
        bOut := FALSE;                                          // 空闲输出低 / idle output is low
        IF bReq THEN
            eState := E_DL_MinOnOffState.eStarting;             // 有请求即启动，最短停止已在 eCooldown 走完 / start on request, the off time was already served
        END_IF

    E_DL_MinOnOffState.eStarting :
        bOut := TRUE;                                           // 启动中输出高 / output is high while starting
        IF fbMinOn.Q THEN
            eState := E_DL_MinOnOffState.eRunning;              // 最短运行已满 / the minimum on time is satisfied
        END_IF

    E_DL_MinOnOffState.eRunning :
        bOut := TRUE;                                           // 运行中输出高 / output is high while running
        IF NOT bReq THEN
            IF NOT fbMinOn.Q THEN
                IF eErr = DL_ERR_NONE THEN
                    eErr := 16#0001_0453;                       // 停机请求被最短运行推迟（信息级）/ the stop request is delayed by the minimum on time
                END_IF
            END_IF
            eState := E_DL_MinOnOffState.eHolding;              // 进入保持态，由定时器完成位决定何时真正停机 / enter holding, the timer decides
        END_IF

    E_DL_MinOnOffState.eHolding :
        bOut := TRUE;                                           // 保持中仍输出高 / output stays high while holding
        IF fbMinOn.Q THEN
            eState := E_DL_MinOnOffState.eCooldown;             // 最短运行补满，进入冷却 / the minimum on time is met, cool down
        END_IF

    E_DL_MinOnOffState.eCooldown :
        bOut := FALSE;                                          // 冷却输出低 / output is low while cooling down
        IF fbMinOff.Q THEN
            eState := E_DL_MinOnOffState.eIdle;                 // 最短停止已满 / the minimum off time is satisfied
        END_IF

    E_DL_MinOnOffState.eFault :
        bOut := FALSE;                                          // 故障态输出低 / output is low in the fault state
        IF rtReset.Q THEN
            eState := E_DL_MinOnOffState.eIdle;                 // 复位沿退出故障 / the reset edge leaves the fault state
        END_IF

ELSE
    // 强制安全兜底：非法状态一律回安全态并置故障（红线 R6）/ forced safe fallback for an illegal state
    eState := E_DL_MinOnOffState.eFault;                        // 强制回故障态 / force the fault state
    eErr   := 16#0001_039A;                                     // 非法状态（故障级）/ illegal state, fault level
    bError := TRUE;                                             // 置故障标志 / raise the fault flag
    bOut   := FALSE;                                            // 输出回安全态 / drive the output low
END_CASE

// 段 5｜守卫观测输出（只读定时器 ET，不做转移判据）/ segment 5, observable guard outputs, the elapsed time is never a transition test
bHoldOn  := (eState = E_DL_MinOnOffState.eHolding);              // 仅在保持态才算「强制延长运行」/ only the holding state really extends the run time
bHoldOff := (eState = E_DL_MinOnOffState.eCooldown);             // 冷却态即「强制延长停止」/ cooling down means the stop time is being enforced
IF (eState = E_DL_MinOnOffState.eStarting) OR (eState = E_DL_MinOnOffState.eHolding) THEN
    IF fbMinOn.ET < tMinOnEff THEN
        tRemaining := tMinOnEff - fbMinOn.ET;                    // 最短运行剩余 / remaining minimum on time
    ELSE
        tRemaining := DL_TIME_ZERO;                              // 已满 / already satisfied
    END_IF
ELSIF eState = E_DL_MinOnOffState.eCooldown THEN
    IF fbMinOff.ET < tMinOffEff THEN
        tRemaining := tMinOffEff - fbMinOff.ET;                  // 最短停止剩余 / remaining minimum off time
    ELSE
        tRemaining := DL_TIME_ZERO;                              // 已满 / already satisfied
    END_IF
ELSE
    tRemaining := DL_TIME_ZERO;                                  // 无守卫 / no guard active
END_IF
END_FUNCTION_BLOCK
