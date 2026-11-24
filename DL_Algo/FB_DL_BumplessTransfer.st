(*
    FB_DL_BumplessTransfer —— 手 / 自动无扰切换
    ------------------------------------------------------------------
    分类      : DL_Algo / Control
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : T2-5 Mod_PID（源矩阵明列「参数域已取尽，后续仅剩手自动切换手册细节」，
                本件即该细节的收口件）；T1-1 OSCAT Basic 反作用增益惯例作次源对照；
                无扰过渡律、状态机、码位 100% 自有；clean-room 重写，未复制任何
                闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 手动到自动切换时，输出从「手动末值」按限斜率过渡到「PID 输出」，
                杜绝阀门 / 变频器被给定量阶跃冲击（水锤、皮带打滑、加热丝浪涌）；
                手动期持续把输出跟踪到实际反馈（反算跟踪），使自动接管时积分项不突跳；
                过渡收敛判据用「偏差不大于单拍步长加容差」，浮点判等全部带容差；
                输出限幅为双侧，只做单侧限幅是本库明令禁止的常见缺陷；
                职责边界：本件不内联 PID，PID 输出由上层注入，避免两套积分器打架。
    错误码    : 16#0002_2401 过渡中偏差超提示窗（正常现象，非故障）——信息级，不置故障
                16#0002_2402 预留禁用（信息级，不得挪用）
                16#0002_2410 斜率参数非法（不在 0.01~1000 %/s）——故障级，过渡禁用直接取 PID 输出
                16#0002_2411 给定非有限（NaN / 正负 INF）或状态机落 ELSE 兜底——故障级，保持末次输出
                16#0002_2412 预留禁用（故障级，不得挪用）
    码位总账  : 16#0002_2401 用 / 16#0002_2402 预留 ｜ 16#0002_2410 用 / 16#0002_2411 用 / 16#0002_2412 预留
    状态机    : E_DL_TransferState（eIdle / eManual / eTransfer / eAuto / eFault），
                CASE 含 ELSE 兜底，兜底固定置 eFault 与 2411
    采样约定  : fbTrigReset 在本体首部无条件刷新；单拍步长按固定任务周期常量
                DL_TR_DT 折算，必须与实际任务周期一致，周期改动须同步改该常量。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TransferState（归属本功能块，与其同文件发布）
 * 含义: 手自动无扰切换状态机离散态，步长 10 留空位，故障态取 99 排末位
 *----------------------------------------------------------------------------*)
TYPE E_DL_TransferState :
(
    eIdle     := 0,    // 空闲：输出归零，等待首次使能 / Idle, output zeroed, waiting for the first enable
    eManual   := 10,   // 手动：输出跟踪实际反馈，为接管做准备 / Manual, output tracks the actual feedback to prepare the takeover
    eTransfer := 20,   // 过渡：按限斜率逼近 PID 输出 / Transfer, approaching the PID output at the limited rate
    eAuto     := 30,   // 自动：输出直接等于 PID 输出 / Auto, output equals the PID output
    eFault    := 99    // 故障锁存：给定非有限或非法状态，保持末次输出 / Fault latched, non-finite setpoint or illegal state, holds the last output
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_BumplessTransfer
VAR_INPUT
    bEnable     : BOOL;                        // 使能，FALSE 输出 0 并清过渡 / enable, FALSE zeroes the output and clears the transfer
    bReset      : BOOL;                        // 复位，上升沿放弃过渡直接取目标值（调试用）/ reset, rising edge abandons the transfer and takes the target directly, commissioning only
    bAuto       : BOOL := FALSE;               // TRUE 自动 / FALSE 手动 / TRUE auto, FALSE manual
    fManualOut  : REAL := 0.0;                 // 手动给定，仅手动期生效 [%]，范围 -100.0~100.0 / manual setpoint, manual mode only [%], range -100.0~100.0
    fPidOut     : REAL := 0.0;                 // PID 输出，由上层注入，本件不内联 PID [%] / PID output injected by the caller, no PID inside [%]
    fTrackVal   : REAL := 0.0;                 // 手动期跟踪目标，一般接实际阀位反馈 [%]，范围 -100.0~100.0 / tracking target during manual mode, usually the actual valve position [%], range -100.0~100.0
    fRateMax    : REAL := 10.0;                // 过渡最大变化率 [%/s]，范围 0.01~1000.0 / maximum transfer rate [%/s], range 0.01~1000.0
    fDevWindow  : REAL := 5.0;                 // 过渡偏差提示窗 [%] / deviation hint window during the transfer [%]
END_VAR
VAR_OUTPUT
    fOut         : REAL;                       // 最终输出，双侧限幅 [%] / final output, clamped on both sides [%]
    bTracking    : BOOL;                       // 手动期跟踪中 / tracking during manual mode
    bInTransfer  : BOOL;                       // 自动接管过渡中 / transfer in progress
    fDeviation   : REAL;                       // 当前输出与 PID 输出的偏差 [%] / deviation between the output and the PID output [%]
    tInTransfer  : TIME;                       // 已过渡时长 [ms] / elapsed transfer time [ms]
    eErr         : UDINT;                      // 错误码，0=正常 / error id, 0=ok
    bError       : BOOL;                       // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigReset : R_TRIG;                      // 复位沿检测实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    eState      : E_DL_TransferState := E_DL_TransferState.eIdle; // 内部状态机步序 / internal state machine step
    fLastOut    : REAL;                        // 上一拍输出，过渡起点 [%] / previous cycle output, the transfer starting point [%]
    fStep       : REAL;                        // 单拍允许变化量 [%] / allowed change per cycle [%]
    tLast       : TIME;                        // 过渡累计时长 [ms] / accumulated transfer time [ms]
    tDelta      : TIME;                        // 本拍时间增量，取固定任务周期 [ms] / time increment of this cycle, the fixed task period [ms]
    bInit       : BOOL := FALSE;               // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
    bNonFin     : BOOL;                        // 给定非有限判定标志 / setpoint non-finite flag
    bRateOk     : BOOL;                        // 斜率参数合法标志 / rate parameter valid flag
    fClamped    : REAL;                        // 限幅中间量 [%] / clamping intermediate [%]
END_VAR
VAR CONSTANT
    DL_TR_MAX_RATE : REAL := 1000.0;           // 变化率上限 [%/s] / rate upper bound [%/s]
    DL_TR_MIN_RATE : REAL := 0.01;             // 变化率下限 [%/s] / rate lower bound [%/s]
    DL_TR_OUT_LIM  : REAL := 100.0;            // 输出双侧限幅 [%] / symmetrical output limit [%]
    DL_TR_DT       : TIME := T#10MS;           // 假定的任务周期，必须与实际一致 [ms] / assumed task period, must match the real one [ms]
    DL_TR_MS_SEC   : REAL := 1000.0;           // 毫秒转秒的除数，恒非零 [ms/s] / milliseconds to seconds divisor, never zero [ms/s]
    DL_FLOAT_EPS   : REAL := 1.0E-6;           // 浮点判等容差 [%] / float equality tolerance [%]
    DL_TR_INF_GUARD: REAL := 4.0E38;           // 非有限幅值判定阈值 [%] / non-finite magnitude guard [%]
    DL_TR_ZERO     : REAL := 0.0;              // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigReset(CLK := bReset);

// 段 2｜输出与错误状态预置 / segment 2, preset outputs and error status
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault
bTracking := FALSE;                            // 默认非跟踪态 / default not tracking
bInTransfer := FALSE;                          // 默认非过渡态 / default not transferring
tDelta := DL_TR_DT;                            // 本拍时间增量取固定任务周期 / this cycle increment uses the fixed task period

// 段 3｜首扫初始化（初值 FALSE，判据 NOT bInit）/ segment 3, first-scan initialisation
IF NOT bInit THEN
    eState := E_DL_TransferState.eIdle;        // 首扫落空闲态 / start in the idle state
    fLastOut := DL_TR_ZERO;                    // 输出记忆清零 / clear the output memory
    tLast := T#0MS;                            // 过渡时长清零 / clear the transfer time
    bInit := TRUE;                             // 首扫只做一次 / first scan runs once only
END_IF

// 段 4｜使能闸：失能输出 0 并清过渡 / segment 4, enable gate zeroes the output
IF NOT bEnable THEN
    eState := E_DL_TransferState.eIdle;        // 回空闲态 / back to idle
    fLastOut := DL_TR_ZERO;                    // 清输出记忆 / clear the output memory
    tLast := T#0MS;                            // 清过渡时长 / clear the transfer time
    fOut := DL_TR_ZERO;                        // 输出 0 / output zero
    fDeviation := DL_TR_ZERO;                  // 偏差 0 / deviation zero
    tInTransfer := T#0MS;                      // 过渡时长 0 / transfer time zero
    RETURN;                                    // 失能即出口 / disabled is the exit
END_IF

// 段 5｜斜率参数闸：非法即禁用过渡并直接取 PID 输出 / segment 5, rate parameter gate
bRateOk := (fRateMax >= DL_TR_MIN_RATE) AND (fRateMax <= DL_TR_MAX_RATE); // 域判定用与逻辑 / domain check by conjunction
IF NOT bRateOk THEN
    eErr := 16#0002_2410;                      // 斜率非法故障码 / illegal rate fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
END_IF

// 段 6｜给定非有限闸：任一给定非有限即落故障态，保持末次输出 / segment 6, non-finite setpoint gate
bNonFin := (fPidOut <> fPidOut) OR (fPidOut > DL_TR_INF_GUARD) OR (fPidOut < -DL_TR_INF_GUARD)
        OR (fTrackVal <> fTrackVal) OR (fTrackVal > DL_TR_INF_GUARD) OR (fTrackVal < -DL_TR_INF_GUARD)
        OR (fManualOut <> fManualOut) OR (fManualOut > DL_TR_INF_GUARD) OR (fManualOut < -DL_TR_INF_GUARD); // 三路给定同口径检查 / all three setpoints checked the same way
IF bNonFin THEN
    eErr := 16#0002_2411;                      // 给定非有限故障码 / non-finite setpoint fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    eState := E_DL_TransferState.eFault;       // 落故障态 / enter the fault state
END_IF

// 段 7｜复位沿处理：放弃过渡，直接取目标值 / segment 7, reset abandons the transfer
IF fbTrigReset.Q THEN
    tLast := T#0MS;                            // 清过渡时长 / clear the transfer time
    IF bAuto THEN
        eState := E_DL_TransferState.eAuto;    // 直接进自动态 / jump straight to auto
        fLastOut := fPidOut;                   // 直接取 PID 输出 / take the PID output directly
    ELSE
        eState := E_DL_TransferState.eManual;  // 回手动态 / back to manual
        fLastOut := fTrackVal;                 // 取跟踪目标 / take the tracking target
    END_IF
END_IF

// 段 8｜单拍步长：斜率乘秒数，斜率已过闸，除数为常量恒非零 / segment 8, per cycle step size
IF bRateOk THEN
    fStep := fRateMax * TIME_TO_REAL(tDelta) / DL_TR_MS_SEC; // 步长 [%] / step size in percent
ELSE
    fStep := DL_TR_ZERO;                       // 斜率非法时步长 0，过渡不启用 / invalid rate yields a zero step, the transfer stays disabled
END_IF

// 段 9｜状态机主体（CASE 必含 ELSE 兜底，红线）/ segment 9, state machine body
CASE eState OF
    E_DL_TransferState.eIdle :
        fLastOut := DL_TR_ZERO;                // 空闲态输出记忆为 0 / the idle state keeps a zero output memory
        tLast := T#0MS;                        // 过渡时长清零 / clear the transfer time
        IF bAuto THEN
            eState := E_DL_TransferState.eTransfer; // 已请求自动，直接进过渡 / auto requested, enter the transfer
        ELSE
            eState := E_DL_TransferState.eManual;   // 否则进手动跟踪 / otherwise enter manual tracking
        END_IF
    E_DL_TransferState.eManual :
        bTracking := TRUE;                     // 手动期跟踪标志 / tracking flag in manual mode
        fClamped := MIN(MAX(fTrackVal, -DL_TR_OUT_LIM), DL_TR_OUT_LIM); // 手动期输出跟踪实际反馈，双侧限幅 / manual output tracks the actual feedback, clamped both sides
        fLastOut := fClamped;                  // 更新输出记忆 / update the output memory
        tLast := T#0MS;                        // 过渡时长清零，接管时从 0 计时 / clear the transfer time, counted from zero on takeover
        IF bAuto THEN
            eState := E_DL_TransferState.eTransfer; // 自动请求到来即进入过渡 / an auto request starts the transfer
        END_IF
    E_DL_TransferState.eTransfer :
        bInTransfer := TRUE;                   // 过渡进行中 / transfer in progress
        IF NOT bRateOk THEN
            fLastOut := fPidOut;               // 过渡禁用，直接取 PID 输出 / transfer disabled, take the PID output
            eState := E_DL_TransferState.eAuto;// 转自动态 / switch to auto
        ELSE
            tLast := tLast + tDelta;           // 累计过渡时长 / accumulate the transfer time
            IF ABS(fPidOut - fLastOut) <= (fStep + DL_FLOAT_EPS) THEN
                fLastOut := fPidOut;           // 收敛完成，落到 PID 输出 / converged, land on the PID output
                eState := E_DL_TransferState.eAuto; // 转自动态 / switch to auto
            ELSIF fPidOut > fLastOut THEN
                fLastOut := fLastOut + fStep;  // 正向逼近一个步长 / approach upwards by one step
            ELSE
                fLastOut := fLastOut - fStep;  // 负向逼近一个步长 / approach downwards by one step
            END_IF
            IF ABS(fPidOut - fLastOut) > fDevWindow THEN
                eErr := 16#0002_2401;          // 偏差超提示窗（信息级不置故障）/ deviation above the hint window, info level never raises a fault
            END_IF
        END_IF
        IF NOT bAuto THEN
            eState := E_DL_TransferState.eManual; // 中途撤回自动，回手动跟踪 / auto revoked mid-flight, back to manual tracking
            tLast := T#0MS;                    // 过渡时长清零 / clear the transfer time
        END_IF
    E_DL_TransferState.eAuto :
        fLastOut := fPidOut;                   // 自动态输出等于 PID 输出 / in auto the output equals the PID output
        tLast := T#0MS;                        // 过渡结束，时长清零 / transfer finished, clear the time
        IF NOT bAuto THEN
            eState := E_DL_TransferState.eManual; // 手动请求，回跟踪态 / a manual request returns to tracking
        END_IF
    E_DL_TransferState.eFault :
        bInTransfer := FALSE;                  // 故障态不过渡 / no transfer in the fault state
        fLastOut := MIN(MAX(fLastOut, -DL_TR_OUT_LIM), DL_TR_OUT_LIM); // 故障态保持末次输出，仅双侧限幅 / the fault state holds the last output, clamped both sides only
ELSE
    eErr := 16#0002_2411;                      // 非法状态兜底码，与给定非有限共用同一业务语义 / fallback code sharing the business meaning of a non-finite setpoint
    bError := TRUE;                            // 置故障标志 / raise the error flag
    eState := E_DL_TransferState.eFault;       // 一律回安全故障态 / always fall back to the safe fault state
    bInTransfer := FALSE;                      // 清除过渡标志 / clear the transfer flag
END_CASE

// 段 10｜输出双侧限幅与偏差监视 / segment 10, symmetrical clamping and deviation monitoring
fClamped := MIN(MAX(fLastOut, -DL_TR_OUT_LIM), DL_TR_OUT_LIM); // 双侧限幅，绝不只做单侧 / clamp both sides, never one side only
fOut := fClamped;                              // 输出镜像 / publish the output
fDeviation := fPidOut - fClamped;              // 偏差按限幅后的实际输出计算 / the deviation uses the clamped actual output
tInTransfer := tLast;                          // 过渡时长镜像 / publish the transfer time
END_FUNCTION_BLOCK
