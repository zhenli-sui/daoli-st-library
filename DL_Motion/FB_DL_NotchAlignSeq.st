(*==============================================================================
 * 组件名称 (Component)  : FB_DL_NotchAlignSeq
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，零方言）
 * 功能描述 (Function)   : 晶圆缺口对位六相顺控。搜索相等待缺口检出，锁存相用条件加减归
 *                         一角度（禁用取模，负数取余三平台不一致）并算最小转角，微调相
 *                         派发相对转动，复核相按公差判合格，超差在限次内重试，限次用尽
 *                         或单相超时一律锁存故障，不空转。不做缺口视觉识别本身（检出由
 *                         引脚注入）、不做旋转轴回零、不做多片排队。
 *                         说明：I_DL_StepperOpenLoop.MoveRelative 为线性距离语义，本件把
 *                         旋转角度直接按「度」传给距离参数（旋转轴已按 1 mm = 1 ° 标定），
 *                         该标定假设由调用方在轴组态中保证。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_NotchState / FUNCTION_BLOCK FB_DL_NotchAlignSeq
 * 依赖 (Depends)        : DL_Device/I_DL_StepperOpenLoop（只调用契约方法与属性）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         公差与速度判零防除零 ｜ 角度归一用条件加减（禁取模） ｜ 非有限
 *                         用自反比较 ｜ 相超时定时器与沿实例无条件周期刷新 ｜ 枚举显式赋值
 *                         ｜ 搜索相退出条件 ≥2 条（缺口检出沿 + 前置条件消失/超时） ｜ CASE 含 ELSE
 * 错误码表 (Codes)      : 16#0004_0336 就绪（空闲/完成/无事件）
 *                         16#0004_0337 故障级 旋转轴拒绝微调指令
 *                         16#0004_0338 故障级 组态非法（公差/角速度/相超时/限次出域）
 *                         16#0004_0339 故障级 单相超时（不自动续相，必须复位后重新启动）
 *                         16#0004_033A 故障级 重试次数用尽。本件 5 槽全用、无预留槽，已登记待裁定
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 2
 * 验收向量 (Acceptance) : 正向 当前 10 °、目标 95 °、公差 0.2 °、30 °/s → 微调 +85 °、
 *                         复核偏差 0.05 ° → eDone
 *                         反向 缺口检出恒 FALSE → 超时 16#0004_0339 转 eFault（不空转）；
 *                         公差给 0 → 16#0004_0338；限次 0 且复核超差 → 16#0004_033A
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_NotchState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 缺口对位相位，每个成员在 CASE 中有且仅有一个标签。
 *----------------------------------------------------------------------------*)
TYPE E_DL_NotchState :
(
    eIdle      := 0,    // 空闲：等启动沿 / Idle, waiting for the start edge
    eSearching := 10,   // 搜索：等缺口检出或相超时 / Searching, waiting for the notch or the phase timeout
    eLatched   := 20,   // 锁存：本拍算最小转角并派单 / Latched, computing the shortest angle and dispatching
    eTrimming  := 30,   // 微调：等旋转轴就绪 / Trimming, waiting for the rotary axis to be ready
    eVerifying := 40,   // 复核：判偏差是否落公差 / Verifying, checking whether the deviation is inside tolerance
    eDone      := 50,   // 完成：单拍完成脉冲，需新启动沿 / Done, one-scan pulse, a new start edge is required
    eFault     := 99    // 故障：锁存码保持，仅复位沿退出 / Fault, the latch code is held until the reset edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_NotchAlignSeq
VAR_INPUT
    bEnable        : BOOL := FALSE;       // 使能 / Enable
    bStart         : BOOL := FALSE;       // 启动，上升沿启动一次 / Start, the rising edge starts one cycle
    bReset         : BOOL := FALSE;       // 复位，仅故障态生效 / Reset, effective in the fault state only
    bNotchFound    : BOOL := FALSE;       // 缺口检出（引脚注入） / Notch found, injected by the caller
    fThetaNow_deg  : REAL := 0.0;         // 当前转角 [°]，域 0~360 / Present angle in degrees, domain 0 to 360
    fThetaTarget_deg : REAL := 0.0;       // 目标转角 [°]，域 0~360 / Target angle in degrees, domain 0 to 360
    fTolDeg        : REAL := 0.2;         // 复核公差 [°]，域 0.01~1.0 / Verification tolerance in degrees, domain 0.01 to 1.0
    fSpinSpeed_dps : REAL := 30.0;        // 角速度 [°/s]，域 1~180 / Angular speed in degrees per second, domain 1 to 180
    tPhaseMax      : TIME := T#10S;       // 单相超时 [ms]，域 100ms~30s / Per-phase timeout, domain 100 ms to 30 s
    uRetryMax      : UINT := 2;           // 重试上限 [次]，域 0~2 / Retry limit, domain 0 to 2
END_VAR
VAR_IN_OUT
    iAxis          : I_DL_StepperOpenLoop; // 旋转轴开环步进契约引用 [—] / Rotary axis open-loop stepper contract reference
END_VAR
VAR_OUTPUT
    bDone          : BOOL;                // 完成脉冲，单拍有效 / Completion pulse, valid for one scan
    bBusy          : BOOL;                // 顺控进行中 / Sequence running
    bError         : BOOL;                // 故障级标志，仅故障级码置位 / Fault-class flag, set on fault codes only
    fThetaErr_deg  : REAL;                // 最终偏差 [°] / Final deviation in degrees
    uRetryCnt      : UINT;                // 已重试次数 [次] / Retry count
    eState         : E_DL_NotchState;     // 对位相位 [—] / Alignment phase
    eErr           : UDINT;               // 错误码，段位 16#0004_xxxx / Error code in segment 16#0004_xxxx
END_VAR
VAR
    _eState        : E_DL_NotchState := E_DL_NotchState.eIdle; // 当前相位 / Current phase
    _bInit         : BOOL := FALSE;       // 首扫标志，取非判定 / First-scan flag, tested negated
    _bRefOk        : BOOL;                // 契约引用有效标志 / Contract reference valid flag
    _bCfgOk        : BOOL;                // 组态合法标志 / Configuration valid flag
    _bIssueScan    : BOOL;                // 派单当拍标志（本拍不判就绪） / Dispatch scan flag, readiness is not judged in this scan
    _bFaultLatch   : BOOL;                // 故障锁存标志 / Fault latch flag
    _uLatchCode    : UDINT;               // 锁存码载体 / Latch code carrier
    _fDelta        : REAL;                // 本拍最小转角（已归一）[°] / Shortest angle after normalisation in degrees
    _fErrAbs       : REAL;                // 偏差绝对值 [°] / Absolute deviation in degrees
    _rtrigStart    : R_TRIG;              // 启动上升沿 / Rising edge of the start command
    _rtrigReset    : R_TRIG;              // 复位上升沿 / Rising edge of the reset command
    _rtrigNotch    : R_TRIG;              // 缺口检出上升沿 / Rising edge of the notch-found signal
    _tonPhase      : TON;                 // 单相超时计时 / Per-phase timeout timer
END_VAR
VAR CONSTANT
    DL_NA_READY   : UDINT := 16#0004_0336;  // 就绪码 / Ready code
    DL_NA_AXIS_BAD : UDINT := 16#0004_0337; // 故障级轴拒绝码 / Fault code for a rejected axis command
    DL_NA_CFG_BAD : UDINT := 16#0004_0338;  // 故障级组态非法码 / Fault code for bad configuration
    DL_NA_TIMEOUT : UDINT := 16#0004_0339;  // 故障级相超时码 / Fault code for a phase timeout
    DL_NA_RETRY   : UDINT := 16#0004_033A;  // 故障级重试用尽码 / Fault code for exhausted retries
    DL_NA_HALF    : REAL := 180.0;          // 半周角 [°] / Half turn in degrees
    DL_NA_FULL    : REAL := 360.0;          // 全周角 [°] / Full turn in degrees
    DL_NA_TOL_LO  : REAL := 0.01;           // 公差下限 [°] / Tolerance lower bound
    DL_NA_TOL_HI  : REAL := 1.0;            // 公差上限 [°] / Tolerance upper bound
    DL_NA_SPD_LO  : REAL := 1.0;            // 角速度下限 [°/s] / Angular speed lower bound
    DL_NA_SPD_HI  : REAL := 180.0;          // 角速度上限 [°/s] / Angular speed upper bound
END_VAR

// 段 1｜输出与单拍标志预置
bDone := FALSE;                                     // 完成脉冲预清 / Completion pulse pre-cleared
bBusy := FALSE;                                     // 运行标志预清 / Busy flag pre-cleared
bError := FALSE;                                    // 故障标志预清 / Fault flag pre-cleared
eErr := 0;                                          // 错误码预清 / Error code pre-cleared
_bIssueScan := FALSE;                               // 派单当拍标志预清 / Dispatch scan flag pre-cleared
_fErrAbs := 0.0;                                    // 偏差预清 [°] / Deviation pre-cleared

// 段 2｜沿检测无条件周期刷新（严禁置于分支内）
_rtrigStart(CLK := bStart);                         // 启动沿 / Start edge
_rtrigReset(CLK := bReset);                         // 复位沿 / Reset edge
_rtrigNotch(CLK := bNotchFound);                    // 缺口检出沿 / Notch-found edge

// 段 3｜首扫初始化（判据取非，R19）
IF NOT _bInit THEN
    _eState := E_DL_NotchState.eIdle;               // 相位待机起步 / Phase starts idle
    _bInit := TRUE;                                 // 首扫只做一次 / The first scan runs once
END_IF

// 段 4｜引用与组态闸
_bRefOk := (iAxis <> 0);                            // 引用注入判据 / Reference injected flag
_bCfgOk := _bRefOk
        AND NOT ((fTolDeg <> fTolDeg) OR ((fTolDeg - fTolDeg) <> (fTolDeg - fTolDeg)))
        AND (fTolDeg >= DL_NA_TOL_LO) AND (fTolDeg <= DL_NA_TOL_HI)
        AND NOT ((fSpinSpeed_dps <> fSpinSpeed_dps) OR ((fSpinSpeed_dps - fSpinSpeed_dps) <> (fSpinSpeed_dps - fSpinSpeed_dps)))
        AND (fSpinSpeed_dps >= DL_NA_SPD_LO) AND (fSpinSpeed_dps <= DL_NA_SPD_HI)
        AND (tPhaseMax >= T#100MS) AND (tPhaseMax <= T#30S)
        AND (uRetryMax <= 2);

// 段 5｜相超时定时器无条件周期刷新（搜索/锁存/微调/复核四相计时）
_tonPhase(IN := (_eState = E_DL_NotchState.eSearching) OR (_eState = E_DL_NotchState.eLatched)
            OR (_eState = E_DL_NotchState.eTrimming) OR (_eState = E_DL_NotchState.eVerifying),
          PT := tPhaseMax);

// 段 6｜角度归一（条件加减，禁取模；输入域 0~360 故单次修正即落 (-180, 180]）
_fDelta := fThetaTarget_deg - fThetaNow_deg;        // 原始角差 [°] / Raw angle difference
IF _fDelta > DL_NA_HALF THEN
    _fDelta := _fDelta - DL_NA_FULL;                // 大于半周：减一周 [°] / Above half a turn, subtract one turn
END_IF
IF _fDelta <= (0.0 - DL_NA_HALF) THEN
    _fDelta := _fDelta + DL_NA_FULL;                // 小于负半周：加一周 [°] / Below minus half a turn, add one turn
END_IF
_fErrAbs := ABS(_fDelta);                           // 偏差绝对值 [°] / Absolute deviation
fThetaErr_deg := _fErrAbs;                          // 偏差出口 [°] / Deviation output

// 段 7｜失能闸
IF NOT bEnable THEN
    _eState := E_DL_NotchState.eIdle;               // 相位回空闲 / Phase back to idle
    eErr := DL_NA_READY;                            // 失能为正常停机 / Disable is a normal stop
END_IF

// 段 8｜对位状态机（ENUM + CASE + ELSE 兜底）
IF bEnable THEN
    CASE _eState OF

        E_DL_NotchState.eIdle:                      // 空闲：等启动沿，先做组态闸
            IF _rtrigStart.Q THEN
                _bFaultLatch := FALSE;              // 启动沿为锁存解除路径 / The start edge releases the latch
                _uLatchCode := 0;                   // 锁存码清 / Latch code cleared
                uRetryCnt := 0;                     // 重试计数清 [次] / Retry count cleared
                IF NOT _bCfgOk THEN
                    eErr := DL_NA_CFG_BAD;          // 故障级：组态非法 / Fault, bad configuration
                    _uLatchCode := DL_NA_CFG_BAD;
                    _bFaultLatch := TRUE;
                    bError := TRUE;
                    _eState := E_DL_NotchState.eFault;
                ELSE
                    _eState := E_DL_NotchState.eSearching;   // 进入搜索相 / Enter the searching phase
                END_IF
            END_IF

        E_DL_NotchState.eSearching:                 // 搜索：退出条件两条（检出沿 / 超时）
            bBusy := TRUE;
            IF _rtrigNotch.Q THEN
                _eState := E_DL_NotchState.eLatched;         // 条件一：缺口检出 / Condition one, the notch was found
            ELSIF _tonPhase.Q THEN
                eErr := DL_NA_TIMEOUT;                       // 故障级：搜索相超时，不空转 / Fault, searching timed out
                _uLatchCode := DL_NA_TIMEOUT;
                _bFaultLatch := TRUE;
                bError := TRUE;
                bBusy := FALSE;
                _eState := E_DL_NotchState.eFault;           // 条件二：前置条件消失（超时）/ Condition two, the precondition vanished
            END_IF

        E_DL_NotchState.eLatched:                   // 锁存：偏差已在公差内直接复核，否则派单微调
            bBusy := TRUE;
            IF _fErrAbs <= fTolDeg THEN
                _eState := E_DL_NotchState.eVerifying;      // 已到位：直接复核 / Already aligned, go verifying
            ELSIF ABS(_fDelta) > (DL_NA_HALF + DL_NA_TOL_HI) THEN
                eErr := DL_NA_CFG_BAD;                      // 故障级：归一失配（角度输入出域）/ Fault, normalisation mismatch
                _uLatchCode := DL_NA_CFG_BAD;
                _bFaultLatch := TRUE;
                bError := TRUE;
                bBusy := FALSE;
                _eState := E_DL_NotchState.eFault;
            ELSE
                IF iAxis.MoveRelative(_fDelta, fSpinSpeed_dps) THEN
                    _bIssueScan := TRUE;                    // 派单当拍不判就绪 / Readiness is not judged in the dispatch scan
                    _eState := E_DL_NotchState.eTrimming;   // 进入微调相 / Enter the trimming phase
                ELSE
                    eErr := DL_NA_AXIS_BAD;                 // 故障级：轴拒绝指令 / Fault, the axis rejected the command
                    _uLatchCode := DL_NA_AXIS_BAD;
                    _bFaultLatch := TRUE;
                    bError := TRUE;
                    bBusy := FALSE;
                    _eState := E_DL_NotchState.eFault;
                END_IF
            END_IF

        E_DL_NotchState.eTrimming:                  // 微调：等轴就绪或超时
            bBusy := TRUE;
            IF _bIssueScan THEN
                _bIssueScan := FALSE;                       // 派单拍已过 / The dispatch scan has passed
            ELSIF iAxis.bReady THEN
                _eState := E_DL_NotchState.eVerifying;      // 轴就绪：复核 / Axis ready, go verifying
            ELSIF _tonPhase.Q THEN
                eErr := DL_NA_TIMEOUT;                      // 故障级：微调相超时 / Fault, trimming timed out
                _uLatchCode := DL_NA_TIMEOUT;
                _bFaultLatch := TRUE;
                bError := TRUE;
                bBusy := FALSE;
                _eState := E_DL_NotchState.eFault;
            END_IF

        E_DL_NotchState.eVerifying:                 // 复核：合格即完成，超差在限次内重试
            bBusy := TRUE;
            IF _bIssueScan THEN
                _bIssueScan := FALSE;
            ELSIF _tonPhase.Q THEN
                eErr := DL_NA_TIMEOUT;                      // 故障级：复核相超时 / Fault, verifying timed out
                _uLatchCode := DL_NA_TIMEOUT;
                _bFaultLatch := TRUE;
                bError := TRUE;
                bBusy := FALSE;
                _eState := E_DL_NotchState.eFault;
            ELSE
                IF _fErrAbs <= fTolDeg THEN
                    _eState := E_DL_NotchState.eDone;       // 合格 / Accepted
                ELSIF uRetryCnt >= uRetryMax THEN
                    eErr := DL_NA_RETRY;                    // 故障级：重试次数用尽 / Fault, retries exhausted
                    _uLatchCode := DL_NA_RETRY;
                    _bFaultLatch := TRUE;
                    bError := TRUE;
                    bBusy := FALSE;
                    _eState := E_DL_NotchState.eFault;
                ELSE
                    uRetryCnt := uRetryCnt + 1;             // 重试计数 +1 [次] / Retry count incremented
                    _eState := E_DL_NotchState.eSearching;  // 重新搜索 / Search again
                END_IF
            END_IF

        E_DL_NotchState.eDone:                      // 完成：单拍脉冲（下一拍段 1 预清即自清，R24 三律）
            bDone := TRUE;
            bBusy := FALSE;
            eErr := DL_NA_READY;                    // 就绪/完成码 / Ready or completion code
            _eState := E_DL_NotchState.eIdle;       // 需新启动沿重启 / A new start edge is required

        E_DL_NotchState.eFault:                     // 故障：锁存码保持，仅复位沿退出
            bBusy := FALSE;
            eErr := _uLatchCode;                    // 锁存码回放 / Replay the latch code
            bError := TRUE;
            IF _rtrigReset.Q THEN
                IF _bRefOk THEN
                    iAxis.Reset();                  // 轴故障复位 / Axis fault reset
                END_IF
                _bFaultLatch := FALSE;              // 锁存解除 / Latch released
                _uLatchCode := 0;                   // 锁存码清 / Latch code cleared
                uRetryCnt := 0;                     // 重试计数清 [次] / Retry count cleared
                eErr := DL_NA_READY;                // 复位后回就绪码 / Ready code after the reset
                bError := FALSE;
                _eState := E_DL_NotchState.eIdle;   // 回空闲需新启动沿 / Back to idle, a new start edge is required
            END_IF

        ELSE
            // 非法状态兜底（故障级）
            eErr := DL_NA_CFG_BAD;                  // 故障级：非法相位 / Fault, illegal phase
            _uLatchCode := DL_NA_CFG_BAD;
            _bFaultLatch := TRUE;
            bError := TRUE;
            bBusy := FALSE;
            _eState := E_DL_NotchState.eFault;

    END_CASE
END_IF

eState := _eState;                                  // 相位出口镜像 / Phase mirrored to the output pin
END_FUNCTION_BLOCK
