(*
    FB_DL_AxisSynchronizedStop —— 受控同步停车
    ------------------------------------------------------------------
    分类      : DL_Motion / Motion
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : T1-6 PLCopen Motion（只借 MC_Stop / MC_Halt 的公开「按减速度停车 +
                完成确认」语义；不实现运动核、不定义轴状态机）；停止距离解析式与
                状态映射 100% 自有；clean-room 重写，未复制任何闭源厂商源码，
                参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 给上层运动接口生成「按固定减速度斜坡停车」的指令序列，并预估停止距离
                与停止位置；用于安全门打开、料尽、下游堵塞等需要「减速停而非自由滑行」
                的工况；本件不直接驱动伺服，零全局耦合，也不承担急停（急停由安全
                回路直连，不经本件，头注释显式声明）；
                三道闸：减速度闸（减速度为 0 或负会让「停车」永不完成，首要防御）→
                快照非有限闸 → 状态机 ELSE 兜底闸（02DA 为本件专用兜底码）；
                启动时已静止则跳过硬坡直接判完成，避免定时器空转产生假 Done。
    错误码    : 16#0004_01C9 启动时已静止（速度低于阈值），跳过斜坡直接判完成——信息级，不置故障
                16#0004_01CA 预留禁用（信息级，不得挪用）
                16#0004_02D8 减速度非法（小于 1 mm/s2），停车不可完成——故障级，转故障态
                16#0004_02D9 速度或位置快照非有限（NaN / 正负 INF）——故障级，转故障态
                16#0004_02DA 状态机落 ELSE 兜底（非法状态，一律回安全态）——用途固定，不得改作他用
    码位总账  : 16#0004_01C9 用 / 16#0004_01CA 预留 ｜ 16#0004_02D8 用 / 16#0004_02D9 用 / 16#0004_02DA 用
    状态机    : E_DL_StopState（eIdle / eRamping / eSettling / eDone / eFault），
                CASE 含 ELSE 兜底，兜底固定置 eFault、位号 99 与 02DA
    采样约定  : 三个 R_TRIG 与 fbSettle 在本体首部无条件调用；fbSettle 的 IN 引脚取上一拍
                状态判据，属正常的单拍延迟，不影响完成确认的正确性。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StopState（归属本功能块，与其同文件发布）
 * 含义: 受控停车状态机离散态，步长 10 留空位，故障态取 99 排末位
 *----------------------------------------------------------------------------*)
TYPE E_DL_StopState :
(
    eIdle     := 0,    // 空闲：未收到停车请求 / Idle, no stop request received
    eRamping  := 10,   // 减速中：等待速度跌到判静止阈值以下 / Ramping, waiting for the speed to fall below the standstill threshold
    eSettling := 20,   // 稳定确认中：速度已达阈值，等待稳定窗到期 / Settling, the speed reached the threshold and the settle window is running
    eDone     := 30,   // 完成：已静止且稳定窗到期 / Done, stopped and the settle window expired
    eFault    := 99    // 故障：减速度或快照非法、被中止、或落入兜底 / Fault, illegal deceleration or snapshot, aborted, or fell into the fallback
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_AxisSynchronizedStop
VAR_INPUT
    bEnable        : BOOL;                     // 使能，FALSE 清指令并回空闲 / enable, FALSE clears the command and returns to idle
    bExecute       : BOOL;                     // 上升沿启动停车序列 / rising edge starts the stop sequence
    bAbort         : BOOL;                     // 上升沿中止并转故障态（急停由安全回路直连，不经本件）/ rising edge aborts into the fault state, the emergency stop is hardwired elsewhere
    bReset         : BOOL;                     // 上升沿清故障回空闲 / rising edge clears the fault and returns to idle
    fActVelocity   : REAL := 0.0;              // 当前速度，由运动层注入 [mm/s] / current speed injected by the motion layer [mm/s]
    fActPosition   : REAL := 0.0;              // 当前位置，用于算停止点 [mm] / current position used for the stop point [mm]
    fDeceleration  : REAL := 500.0;            // 停车减速度 [mm/s2]，范围 1.0~1.0E5 / stop deceleration [mm/s2], range 1.0~1.0E5
    tDelayTime     : TIME := T#100MS;          // 从发出到实际减速的传动延迟 [ms]，范围 0~2000 / drive train delay from command to real deceleration [ms], range 0~2000
    fVelocityEps   : REAL := 0.5;              // 判静止的速度阈值 [mm/s]，范围 0.01~100.0 / standstill speed threshold [mm/s], range 0.01~100.0
END_VAR
VAR_OUTPUT
    bBusy         : BOOL;                      // 停车进行中 / stop in progress
    bDone         : BOOL;                      // 已完成，单周期脉冲 / completed, single-cycle pulse
    bStopped      : BOOL;                      // 已静止（速度低于阈值且稳定窗到期）/ stopped, the speed is below the threshold and the settle window expired
    fStopDistance : REAL;                      // 预估停止距离（延迟段加减速段）[mm] / estimated stop distance, delay segment plus ramp segment [mm]
    fStopPosition : REAL;                      // 预估停止位置 [mm] / estimated stop position [mm]
    uState        : UINT;                      // 状态镜像 0 空闲 / 10 减速 / 20 稳定 / 30 完成 / 99 故障，仅供 HMI / state mirror for the HMI only
    eErr          : UDINT;                     // 错误码，0=正常 / error id, 0=ok
    bError        : BOOL;                      // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigExec   : R_TRIG;                     // 启动沿检测实例，本体首部无条件刷新 / execute edge instance, refreshed unconditionally
    fbTrigAbort  : R_TRIG;                     // 中止沿检测实例，本体首部无条件刷新 / abort edge instance, refreshed unconditionally
    fbTrigReset  : R_TRIG;                     // 复位沿检测实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    fbSettle     : TON;                        // 稳定窗定时器，本体首部无条件刷新 / settle window timer, refreshed unconditionally
    eState       : E_DL_StopState := E_DL_StopState.eIdle; // 内部状态机步序 / internal state machine step
    fDecelEff    : REAL;                       // 生效减速度，钳位后使用 [mm/s2] / effective deceleration after clamping [mm/s2]
    fStopDistCalc: REAL;                       // 停止距离计算中间量 [mm] / stop distance intermediate [mm]
    tRampCalc    : TIME;                       // 理论减速段时长，供 HMI 排程 [ms] / theoretical ramp duration for HMI scheduling [ms]
    fAbsVel      : REAL;                       // 速度绝对值 [mm/s] / absolute speed [mm/s]
    fDelaySec    : REAL;                       // 传动延迟秒值 [s] / drive train delay in seconds [s]
    fVelEpsEff   : REAL;                       // 生效判静止阈值 [mm/s] / effective standstill threshold [mm/s]
    bNonFin      : BOOL;                       // 快照非有限判定标志 / snapshot non-finite flag
END_VAR
VAR CONSTANT
    DL_STOP_DEC_MIN   : REAL := 1.0;           // 减速度下限 [mm/s2] / deceleration lower bound [mm/s2]
    DL_STOP_DEC_MAX   : REAL := 1.0E5;         // 减速度上限，超此值钳位但不判故障（高减速度是合法急停辅助）[mm/s2] / deceleration upper bound, clamped without a fault because a high value is a legal stop aid [mm/s2]
    DL_STOP_VEL_MIN   : REAL := 0.01;          // 判静止阈值下限 [mm/s] / standstill threshold lower bound [mm/s]
    DL_STOP_VEL_MAX   : REAL := 100.0;         // 判静止阈值上限 [mm/s] / standstill threshold upper bound [mm/s]
    DL_STOP_SETTLE    : TIME := T#100MS;       // 稳定确认窗 [ms] / settle confirmation window [ms]
    DL_STOP_MS_SEC    : REAL := 1000.0;        // 毫秒转秒的除数，恒非零 [ms/s] / milliseconds to seconds divisor, never zero [ms/s]
    DL_STOP_TWO       : REAL := 2.0;           // 减速段距离式的常数二 [无量纲] / constant two of the ramp distance formula [dimensionless]
    DL_FLOAT_EPS      : REAL := 1.0E-6;        // 浮点判等容差 [mm/s] / float equality tolerance [mm/s]
    DL_STOP_INF_GUARD : REAL := 4.0E38;        // 非有限幅值判定阈值 [mm] / non-finite magnitude guard [mm]
    DL_STOP_UI_IDLE   : UINT := 0;             // 状态镜像：空闲 / state mirror, idle
    DL_STOP_UI_RAMP   : UINT := 10;            // 状态镜像：减速中 / state mirror, ramping
    DL_STOP_UI_SETTLE : UINT := 20;            // 状态镜像：稳定确认中 / state mirror, settling
    DL_STOP_UI_DONE   : UINT := 30;            // 状态镜像：完成 / state mirror, done
    DL_STOP_UI_FAULT  : UINT := 99;            // 状态镜像：故障 / state mirror, fault
    DL_STOP_ZERO      : REAL := 0.0;           // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
END_VAR

// 段 1｜边沿与定时器实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional refresh of the edges and the timer
fbTrigExec(CLK := bExecute);
fbTrigAbort(CLK := bAbort);
fbTrigReset(CLK := bReset);
fbSettle(IN := (eState = E_DL_StopState.eSettling), PT := DL_STOP_SETTLE); // IN 取上一拍状态，属正常单拍延迟 / the IN pin uses the previous cycle state, a normal one-cycle lag

// 段 2｜输出与错误状态预置 / segment 2, preset outputs and error status
bDone := FALSE;                                // 完成脉冲先清 / clear the done pulse first
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault

// 段 3｜使能闸：失能清指令回空闲 / segment 3, enable gate returns to idle
IF NOT bEnable THEN
    eState := E_DL_StopState.eIdle;            // 回空闲态 / back to idle
    bBusy := FALSE;                            // 清忙标志 / clear the busy flag
    bStopped := FALSE;                         // 清静止标志 / clear the stopped flag
    uState := DL_STOP_UI_IDLE;                 // 状态镜像回 0 / state mirror back to zero
    RETURN;                                    // 失能即出口 / disabled is the exit
END_IF

// 段 4｜减速度闸：0 或负会让停车永不完成，是本件首要防御 / segment 4, deceleration gate
IF fDeceleration < DL_STOP_DEC_MIN THEN
    fDecelEff := DL_STOP_DEC_MIN;              // 给安全值，避免后续除零 / use the safe value so later divisions stay legal
    eErr := 16#0004_02D8;                      // 减速度非法故障码 / illegal deceleration fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    eState := E_DL_StopState.eFault;           // 转故障态 / enter the fault state
ELSIF fDeceleration > DL_STOP_DEC_MAX THEN
    fDecelEff := DL_STOP_DEC_MAX;              // 超上限钳位，不判故障 / clamp above the upper bound without a fault
ELSE
    fDecelEff := fDeceleration;                // 域内沿用 / use the value inside the domain
END_IF
fVelEpsEff := MIN(MAX(fVelocityEps, DL_STOP_VEL_MIN), DL_STOP_VEL_MAX); // 判静止阈值双侧钳位 / clamp the standstill threshold both sides

// 段 5｜快照非有限闸：速度或位置非法即转故障态 / segment 5, non-finite snapshot gate
bNonFin := (fActVelocity <> fActVelocity)
        OR (fActVelocity > DL_STOP_INF_GUARD) OR (fActVelocity < -DL_STOP_INF_GUARD)
        OR (fActPosition <> fActPosition)
        OR (fActPosition > DL_STOP_INF_GUARD) OR (fActPosition < -DL_STOP_INF_GUARD); // 双快照同口径检查 / both snapshots checked the same way
IF bNonFin THEN
    eErr := 16#0004_02D9;                      // 快照非有限故障码 / non-finite snapshot fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    eState := E_DL_StopState.eFault;           // 转故障态 / enter the fault state
END_IF

// 段 6｜中止与复位沿（中止优先于复位；中止是人為合法操作，不额外置参数码）/ segment 6, abort and reset edges
IF fbTrigAbort.Q THEN
    eState := E_DL_StopState.eFault;           // 中止转故障态 / an abort enters the fault state
    bBusy := FALSE;                            // 清忙标志 / clear the busy flag
    bStopped := FALSE;                         // 清静止标志 / clear the stopped flag
END_IF
IF fbTrigReset.Q THEN
    eState := E_DL_StopState.eIdle;            // 复位回空闲 / reset returns to idle
    eErr := 0;                                 // 复位清错误码 / reset clears the error id
    bError := FALSE;                           // 复位清故障标志 / reset clears the error flag
END_IF

// 段 7｜速度绝对值与停止距离预备 / segment 7, absolute speed and stop distance preparation
fAbsVel := ABS(fActVelocity);                  // 速度绝对值 / absolute speed
fDelaySec := TIME_TO_REAL(tDelayTime) / DL_STOP_MS_SEC; // 传动延迟秒值 / drive train delay in seconds

// 段 8｜状态机主体（CASE 必含 ELSE 兜底，红线）/ segment 8, state machine body
CASE eState OF
    E_DL_StopState.eIdle :
        bBusy := FALSE;                        // 空闲不忙 / idle is not busy
        bStopped := FALSE;                     // 空闲不算静止 / idle does not count as stopped
        uState := DL_STOP_UI_IDLE;             // 状态镜像 / state mirror
        IF fbTrigExec.Q THEN
            fStopDistCalc := fAbsVel * fDelaySec
                           + (fAbsVel * fAbsVel) / (DL_STOP_TWO * fDecelEff); // 延迟段加减速段，分母已由段 4 保证非零 / delay segment plus ramp segment, the divisor passed the gate in segment four
            fStopDistance := fStopDistCalc;    // 对外发布停止距离 / publish the stop distance
            IF fActVelocity >= DL_STOP_ZERO THEN
                fStopPosition := fActPosition + fStopDistCalc; // 正向运动，停止点在当前位之前 / moving positive, the stop point lies ahead
            ELSE
                fStopPosition := fActPosition - fStopDistCalc; // 反向运动 / moving negative
            END_IF
            tRampCalc := REAL_TO_TIME(fAbsVel / fDecelEff * DL_STOP_MS_SEC); // 理论减速段时长 / theoretical ramp duration
            IF fAbsVel <= fVelEpsEff THEN
                eState := E_DL_StopState.eSettling; // 本来已停，直接进稳定确认 / already stopped, go straight to settling
                eErr := 16#0004_01C9;          // 已静止提示（信息级不置故障）/ already stopped hint, info level never raises a fault
            ELSE
                eState := E_DL_StopState.eRamping; // 需要真实减速段 / a real ramp is required
            END_IF
        END_IF
    E_DL_StopState.eRamping :
        bBusy := TRUE;                         // 减速中 / ramping
        uState := DL_STOP_UI_RAMP;             // 状态镜像 / state mirror
        IF fAbsVel <= fVelEpsEff THEN
            eState := E_DL_StopState.eSettling; // 速度已跌到阈值以下，进稳定确认 / the speed fell below the threshold, settle
        END_IF
    E_DL_StopState.eSettling :
        bBusy := TRUE;                         // 稳定确认中仍算忙 / settling still counts as busy
        uState := DL_STOP_UI_SETTLE;           // 状态镜像 / state mirror
        IF fbSettle.Q THEN
            eState := E_DL_StopState.eDone;    // 稳定窗到期即完成 / the settle window expiring completes the stop
            bDone := TRUE;                     // 完成单拍脉冲 / the single-cycle done pulse
            bStopped := TRUE;                  // 已静止标志 / the stopped flag
            bBusy := FALSE;                    // 完成后不忙 / no longer busy after completion
        END_IF
    E_DL_StopState.eDone :
        bBusy := FALSE;                        // 完成态不忙 / the done state is not busy
        bStopped := TRUE;                      // 保持静止标志 / keep the stopped flag
        uState := DL_STOP_UI_DONE;             // 状态镜像 / state mirror
    E_DL_StopState.eFault :
        bBusy := FALSE;                        // 故障态不忙 / the fault state is not busy
        bStopped := FALSE;                     // 故障态不宣称静止 / the fault state never claims a standstill
        uState := DL_STOP_UI_FAULT;            // 状态镜像 / state mirror
ELSE
    eState := E_DL_StopState.eFault;           // 非法状态一律回安全故障态 / any illegal state falls back to the safe fault state
    eErr := 16#0004_02DA;                      // 本件专用兜底码，用途固定不得改作他用 / the dedicated fallback code, its purpose is fixed
    bError := TRUE;                            // 置故障标志 / raise the error flag
    bBusy := FALSE;                            // 清忙标志 / clear the busy flag
    bStopped := FALSE;                         // 清静止标志 / clear the stopped flag
    uState := DL_STOP_UI_FAULT;                // 状态镜像 / state mirror
END_CASE
END_FUNCTION_BLOCK
