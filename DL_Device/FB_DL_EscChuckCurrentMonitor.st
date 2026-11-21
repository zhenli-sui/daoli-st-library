(*
    FB_DL_EscChuckCurrentMonitor —— ESC 静电吸附电流监视
    ------------------------------------------------------------------
    分类      : DL_Device / Diagnostics
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 半导体静电吸盘（ESC）自研线，clean-room 自研，无可挖开源源；
                只借公开半导体设备工程语义（吸附/建立/稳态/释放三段，失吸与打火是
                可区分的失效模式）；判据、状态机、错误分级与码位 100% 自有；
                E_DL_Ne107Status 属主为 I_DL_DeviceHealth，本件只引用不重声明（R70）
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 吸附电压施加后电流须在 tBuildTime 内落进电流窗（建立段）；之后电流须
                持续落窗（稳态段，低于下限超 tConfirmTime 判失吸）；撤电压后电流须归零
                （释放段）。失吸会导致晶圆飞片/破片，打火会烧盘面，两者在电流波形上
                是两种截然不同的特征，本件把「电流长时间偏低」与「瞬时尖峰」分开判。
                核心防御：① 阈值倒置先自动交换并置信息码，交换后仍非法才报故障级；
                ② 电流/电压非有限即故障级并冻结判定，且保持末次 bAttached——
                   把正在吸附的晶圆判成飞片会引发误停机；
                ③ 电压低于吸附门限时不判电流（电压没加上，电流当然为零），回 eIdle；
                ④ 打火只锁存并出口 eOutOfSpec，不置 bError（可继续生产但需检修）；
                ⑤ 泄漏趋势用前后半窗均值比较，只置信息级不置故障。
                职责边界：吸附电压给定与放电归静电电源件，本件只判电流形态。
    错误码    : 16#0003_016E 电流窗上下限倒置已自动交换 / 泄漏趋势上升 / 贴近边界降级运行——信息级，正常防御
                16#0003_016F 预留禁用（信息级，不得挪用）
                16#0003_0336 阈值参数非法或输入非有限——故障级，判定冻结且保持末次吸附结论
                16#0003_0337 建立超时或稳态电流失窗（判失吸）——故障级，eHealth = eFailure
                16#0003_0338 打火尖峰锁存——故障级码位且 eHealth = eOutOfSpec，但按 R13 家族裁定不置 bError
    码位总账  : 16#0003_016E 用 / 16#0003_016F 预留 ｜ 16#0003_0336 用 / 16#0003_0337 用 / 16#0003_0338 用
    状态机    : E_DL_EscState（eIdle / eBuild / eSteady / eRelease / eFault）五态，CASE 含 ELSE 兜底，
                ELSE 回 eFault 并置故障级 0336。
    采样约定  : fbTrigReset / fbBuild / fbLossConfirm 在本体首部无条件刷新——两个定时器的 IN
                由状态导出但调用绝不放进 IF 或 CASE（按段断输入是本族高危点）；
                采样周期越域即故障级，因为趋势窗与确认时间都隐含依赖采样节拍。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)

(*
    枚举 : E_DL_EscState —— 静电吸盘工作段（本文件为全库唯一属主）
*)
TYPE E_DL_EscState :
(
    eIdle    := 0,                            // 空闲：未施加吸附电压 / idle, no chuck voltage applied
    eBuild   := 1,                            // 建立段：等待电流落窗 / build phase, waiting for the current to settle
    eSteady  := 2,                            // 稳态段：电流持续落窗 / steady phase, the current stays inside the window
    eRelease := 3,                            // 释放段：等待电流归零 / release phase, waiting for the current to vanish
    eFault   := 4                             // 故障：判定冻结 / fault, evaluation frozen
);
END_TYPE

FUNCTION_BLOCK FB_DL_EscChuckCurrentMonitor
VAR_INPUT
    bEnable         : BOOL;                   // 使能，FALSE 撤销所有判定输出 / enable, FALSE withdraws every judgement output
    bReset          : BOOL;                   // 复位，上升沿清故障与趋势 / reset, rising edge clears the faults and the trend
    bChuckOn        : BOOL := FALSE;          // 吸附电压施加命令（上层给定）/ chuck voltage command from the upper layer
    fChuckCurrent   : REAL := 0.0;            // 吸附电流测量值 [uA]，范围 0.0~10000.0 / chuck current measurement [uA], range 0.0~10000.0
    fChuckVoltage   : REAL := 0.0;            // 吸附电压测量值 [V]，范围 0.0~5000.0 / chuck voltage measurement [V], range 0.0~5000.0
    fCurMin         : REAL := 5.0;            // 稳态电流窗下限 [uA]，必须 > 0 / steady window lower bound [uA], must be > 0
    fCurMax         : REAL := 500.0;          // 稳态电流窗上限 [uA]，必须 > fCurMin / steady window upper bound [uA], must be > fCurMin
    fSparkRise      : REAL := 50.0;           // 打火判据：单拍电流跳变量阈值 [uA]，必须 > 0 / spark criterion, per cycle current step [uA], must be > 0
    tBuildTime      : TIME := T#2S;           // 建立段允许时长 [ms]，范围 100~30000 / build phase allowance [ms], range 100~30000
    tConfirmTime    : TIME := T#500MS;        // 失吸确认时间 [ms]，范围 0~10000 / loss confirmation time [ms], range 0~10000
    tSampleTime     : TIME := T#10MS;         // 采样周期 [ms]，范围 1~1000 / sample time [ms], range 1~1000
END_VAR
VAR_OUTPUT
    bAttached       : BOOL;                   // 判定已吸附（建立成功且稳态落窗）/ attached, build succeeded and the steady current stays in the window
    bSpark          : BOOL;                   // 检出打火尖峰（锁存）/ spark peak detected, latched
    bLeakTrend      : BOOL;                   // 泄漏趋势上升（盘面污染或绝缘退化）/ leakage trend rising, contamination or insulation ageing
    bDegraded       : BOOL;                   // 降级运行（电流在窗内但贴近边界）/ degraded, the current is in the window but close to a bound
    eHealth         : E_DL_Ne107Status;       // 健康出口（引用唯一属主枚举）/ health output referencing the owner enumeration
    uAttachCount    : UDINT;                  // 累计成功吸附次数，饱和 [次] / accumulated successful attaches, saturating [times]
    eErr            : UDINT;                  // 错误码，0=正常 / error id, 0=ok
    bError          : BOOL;                   // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    eState          : E_DL_EscState := eIdle; // 状态机当前态 / current state machine state
    fbTrigReset     : R_TRIG;                 // 复位上升沿实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    fbBuild         : TON;                    // 建立段定时器，本体首部无条件刷新 / build phase timer, refreshed unconditionally
    fbLossConfirm   : TON;                    // 失吸确认定时器，本体首部无条件刷新 / loss confirmation timer, refreshed unconditionally
    fPrevCur        : REAL;                   // 上一拍电流，用于打火跳变判据 [uA] / previous current for the spark step test [uA]
    fTrendAcc       : REAL;                   // 后窗电流均值累加 [uA] / second window current mean accumulator [uA]
    fTrendBase      : REAL;                   // 前窗电流均值累加 [uA] / first window current mean accumulator [uA]
    uTrendCnt       : UINT;                   // 趋势取样计数 [拍] / trend sampling counter [scan]
    fCurMinEff      : REAL;                   // 交换与钳位后的电流窗下限 [uA] / effective lower bound after swap and clamp [uA]
    fCurMaxEff      : REAL;                   // 交换与钳位后的电流窗上限 [uA] / effective upper bound after swap and clamp [uA]
    fBandEff        : REAL;                   // 近边界判定带宽 [uA] / near boundary band width [uA]
    fCur            : REAL;                   // 本拍电流副本 [uA] / current copy of this cycle [uA]
    bNonFin         : BOOL;                   // 输入非有限判定标志 / non-finite input flag
    bInWindow       : BOOL;                   // 电流落窗判定 / current inside the window
    bInit           : BOOL := FALSE;          // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
END_VAR
VAR CONSTANT
    DL_ESC_CUR_ABS_MAX : REAL := 10000.0;     // 电流绝对上限（三阈值钳位用）[uA] / absolute current bound used by the clamps [uA]
    DL_ESC_VOLT_MIN    : REAL := 100.0;       // 判定「电压确实加上了」的下限 [V] / lower bound proving the voltage is really applied [V]
    DL_ESC_TREND_N     : UINT := 50;          // 趋势取样个数 [拍] / number of trend samples [scan]
    DL_ESC_BAND_RATIO  : REAL := 0.05;        // 近边界判定带宽（相对窗宽）[无量纲] / near boundary band relative to the window [dimensionless]
    DL_ESC_DT_MAX      : TIME := T#1S;        // 采样周期上限 [ms] / sample time upper bound [ms]
    DL_ESC_DT_MIN      : TIME := T#1MS;       // 采样周期下限 [ms] / sample time lower bound [ms]
    DL_FLOAT_EPS       : REAL := 1.0E-6;      // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_ESC_TWO         : REAL := 2.0;         // 二值常量，窗口折半用 [无量纲] / two, used to halve the trend window
    DL_ESC_INF_GUARD   : REAL := 1.0E38;      // 非有限幅值判定阈值 [无量纲] / non-finite magnitude guard [dimensionless]
    DL_ESC_CNT_MAX     : UDINT := 16#FFFF_FFFE; // 吸附计数饱和值 [次] / attach counter saturation value [times]
    DL_ESC_ZERO        : REAL := 0.0;         // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
END_VAR

// 段 1｜边沿与定时器实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional refresh
fbTrigReset(CLK := bReset);
fbBuild(IN := (eState = eBuild) AND bEnable, PT := tBuildTime); // 仅建立段计时 / the timer runs only during the build phase
fbLossConfirm(IN := (eState = eSteady) AND bEnable AND (fChuckCurrent < fCurMin), PT := tConfirmTime); // 仅稳态且电流低于下限时计时 / runs only in the steady phase while the current is below the bound

// 段 2｜输出与错误状态预置（bAttached / bSpark 为保持量，不预置）/ segment 2, preset outputs, the held flags are not preset
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bDegraded := FALSE;                           // 预置未降级 / preset not degraded
bLeakTrend := FALSE;                          // 预置无泄漏趋势 / preset no leakage trend
eHealth := eOk;                               // 预置健康 / preset OK

// 段 3｜首扫初始化（唯一合法范式：初值 FALSE，判据 NOT bInit）/ segment 3, first-scan initialisation
IF NOT bInit THEN
    bAttached := FALSE;                       // 首扫不判吸附 / no attach survives the first scan
    bSpark := FALSE;                          // 首扫不打火锁存 / no spark latch survives the first scan
    uAttachCount := 0;                        // 吸附计数清零 / clear the attach counter
    fPrevCur := fChuckCurrent;                // 电流基准取当前测量，避免首拍误判打火 / seed the current reference to avoid a false spark on the first scan
    uTrendCnt := 0;                          // 趋势计数清零 / clear the trend counter
    fTrendAcc := DL_ESC_ZERO;                 // 后窗累加清零 / clear the second window accumulator
    fTrendBase := DL_ESC_ZERO;                // 前窗累加清零 / clear the first window accumulator
    bInit := TRUE;                            // 首扫只做一次 / first scan runs once only
END_IF

// 段 4｜使能闸：失能撤销全部判定输出 / segment 4, enable gate
IF NOT bEnable THEN
    bAttached := FALSE;                       // 撤销吸附判定 / withdraw the attach judgement
    bDegraded := FALSE;                       // 撤销降级 / withdraw the degraded flag
    bLeakTrend := FALSE;                      // 撤销趋势 / withdraw the trend flag
    eHealth := eUnknown;                      // 失能即未知 / unknown while disabled
    RETURN;                                   // 失能即出口 / disabled is the exit
END_IF

// 段 5｜阈值交换与合法性闸（倒置先交换，交换后仍非法才报故障）/ segment 5, threshold swap and validity
fCurMinEff := fCurMin;                        // 取入参副本 / copy the input
fCurMaxEff := fCurMax;                        // 取入参副本 / copy the input
IF fCurMaxEff < fCurMinEff THEN
    fCurMinEff := fCurMax;                    // 交换：下限取原上限 / swap, the lower bound takes the former upper bound
    fCurMaxEff := fCurMin;                    // 交换：上限取原下限 / swap, the upper bound takes the former lower bound
    eErr := 16#0003_016E;                     // 信息级：上下限倒置已自动交换 / info level, the inverted bounds were swapped
END_IF
fCurMinEff := MIN(MAX(fCurMinEff, DL_ESC_ZERO), DL_ESC_CUR_ABS_MAX); // 下限收敛到物理域 / converge the lower bound into the physical domain
fCurMaxEff := MIN(MAX(fCurMaxEff, DL_ESC_ZERO), DL_ESC_CUR_ABS_MAX); // 上限收敛到物理域 / converge the upper bound into the physical domain
IF (fCurMinEff <= DL_FLOAT_EPS) OR (fCurMaxEff <= fCurMinEff) THEN
    eErr := 16#0003_0336;                     // 阈值非法故障码 / illegal threshold fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;                         // 落故障态，判定冻结 / enter the fault state, the evaluation is frozen
    eHealth := eFailure;                      // 阈值不可信即出口失效 / untrustworthy thresholds mean a failed health output
    RETURN;                                   // 故障级提前返回，bAttached 保持末值 / early return, bAttached keeps its last value
END_IF
fBandEff := DL_ESC_BAND_RATIO * (fCurMaxEff - fCurMinEff); // 近边界带宽 [uA] / near boundary band width [uA]

// 段 6｜输入非有限闸：冻结判定并保持末次吸附结论 / segment 6, non-finite gate freezes the judgement
bNonFin := (fChuckCurrent <> fChuckCurrent) OR (fChuckCurrent > DL_ESC_INF_GUARD) OR (fChuckCurrent < -DL_ESC_INF_GUARD)
        OR (fChuckVoltage <> fChuckVoltage) OR (fChuckVoltage > DL_ESC_INF_GUARD) OR (fChuckVoltage < -DL_ESC_INF_GUARD)
        OR (fSparkRise <> fSparkRise);        // 非有限判定 / non-finite detection
IF bNonFin THEN
    eErr := 16#0003_0336;                     // 输入非有限故障码 / non-finite input fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;                         // 落故障态 / enter the fault state
    eHealth := eFailure;                      // 测量不可信 / the measurement is untrustworthy
    RETURN;                                   // 保持末次 bAttached，绝不掉成未吸附 / keep the last attach state, never fall back to detached
END_IF

// 段 7｜采样周期闸（趋势窗与确认时间都依赖采样节拍）/ segment 7, sample time gate
IF (tSampleTime < DL_ESC_DT_MIN) OR (tSampleTime > DL_ESC_DT_MAX) THEN
    eErr := 16#0003_0336;                     // 采样周期非法故障码 / illegal sample time fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;                         // 落故障态 / enter the fault state
    eHealth := eFailure;                      // 节拍不可信 / the timing is untrustworthy
    RETURN;                                   // 出口 / exit
END_IF

// 段 8｜复位沿清故障与趋势（不改变已建立的吸附结论）/ segment 8, reset clears the faults and the trend
IF fbTrigReset.Q THEN
    bSpark := FALSE;                          // 清打火锁存 / clear the spark latch
    bLeakTrend := FALSE;                      // 清趋势 / clear the trend
    uTrendCnt := 0;                           // 清趋势计数 / clear the trend counter
    fTrendAcc := DL_ESC_ZERO;                 // 清后窗累加 / clear the second window
    fTrendBase := DL_ESC_ZERO;                // 清前窗累加 / clear the first window
    IF eState = eFault THEN
        eState := eIdle;                      // 故障态复位回空闲 / a reset leaves the fault state
    END_IF
END_IF

// 段 9｜电流副本与落窗判定 / segment 9, current copy and window test
fCur := fChuckCurrent;                        // 取入参副本 [uA] / copy the input [uA]
bInWindow := (fCur >= fCurMinEff) AND (fCur <= fCurMaxEff); // 落窗判定 / window test

// 段 10｜打火判据（单拍跳变 + 吸附电压在场，只锁存不置 bError）/ segment 10, spark criterion
IF bChuckOn AND (ABS(fCur - fPrevCur) > fSparkRise) THEN
    bSpark := TRUE;                           // 锁存打火 / latch the spark
    eErr := 16#0003_0338;                     // 打火故障级码位，但按家族裁定不置 bError / spark fault id without raising bError
    eHealth := eOutOfSpec;                    // 能继续吸不等于盘面完好 / still holding does not mean the chuck surface is intact
END_IF
fPrevCur := fCur;                             // 记录本拍电流供下一拍比较 / remember this cycle current

// 段 11｜降级判定：电流在窗内但贴近上下边界 / segment 11, degraded evaluation near a bound
IF bInWindow AND ((fCur <= (fCurMinEff + fBandEff)) OR (fCur >= (fCurMaxEff - fBandEff))) THEN
    bDegraded := TRUE;                        // 贴近边界即降级 / closeness to a bound is a degradation
    IF eErr = 0 THEN
        eErr := 16#0003_016E;                 // 信息级：贴近边界降级运行 / info level, running degraded near a bound
    END_IF
END_IF

// 段 12｜泄漏趋势（前后半窗均值比较，只置信息级）/ segment 12, leakage trend by half window means
IF eState = eSteady THEN
    IF uTrendCnt < (DL_ESC_TREND_N / 2) THEN
        fTrendBase := fTrendBase + fCur / (UINT_TO_REAL(DL_ESC_TREND_N) / DL_ESC_TWO); // 前窗均值累加 [uA] / accumulate the first window mean [uA]
        uTrendCnt := uTrendCnt + 1;           // 计数加一 / increment the counter
    ELSE
        fTrendAcc := fTrendAcc + fCur / (UINT_TO_REAL(DL_ESC_TREND_N) / DL_ESC_TWO);   // 后窗均值累加 [uA] / accumulate the second window mean [uA]
        uTrendCnt := uTrendCnt + 1;           // 计数加一 / increment the counter
        IF uTrendCnt >= DL_ESC_TREND_N THEN
            IF fTrendAcc > (fTrendBase + DL_ESC_BAND_RATIO * (fCurMaxEff - fCurMinEff)) THEN
                bLeakTrend := TRUE;           // 后窗显著上爬：污染或绝缘退化 / the second window creeps up, contamination or insulation ageing
                eErr := 16#0003_016E;         // 信息级：泄漏趋势上升 / info level, the leakage trend is rising
                eHealth := eMaintenanceReq;   // 需安排检修 / maintenance is required
            END_IF
            uTrendCnt := 0;                   // 窗口滑动复位 / restart the sliding window
            fTrendAcc := DL_ESC_ZERO;         // 后窗累加清零 / clear the second window
            fTrendBase := DL_ESC_ZERO;        // 前窗累加清零 / clear the first window
        END_IF
    END_IF
END_IF

// 段 13｜状态机（含 ELSE 兜底）/ segment 13, state machine with ELSE fallback
CASE eState OF
    eIdle:
        bAttached := FALSE;                   // 空闲即未吸附 / idle means detached
        IF bChuckOn AND (fChuckVoltage >= DL_ESC_VOLT_MIN) THEN
            eState := eBuild;                 // 电压确实加上才进入建立段 / enter the build phase only when the voltage is really present
        END_IF

    eBuild:
        IF bInWindow THEN
            eState := eSteady;                // 电流落窗即建立成功 / the current entering the window completes the build
            bAttached := TRUE;                // 判定已吸附 / mark it attached
            IF uAttachCount < DL_ESC_CNT_MAX THEN
                uAttachCount := uAttachCount + 1; // 饱和计数 / saturating count
            END_IF
        ELSIF fbBuild.Q THEN
            eErr := 16#0003_0337;             // 建立超时故障码 / build timeout fault id
            bError := TRUE;                   // 置故障标志 / raise the error flag
            eHealth := eFailure;              // 失吸 / the wafer is not held
            eState := eFault;                 // 落故障态 / enter the fault state
            bAttached := FALSE;               // 建立失败即未吸附 / a failed build means detached
        END_IF

    eSteady:
        bAttached := TRUE;                    // 稳态保持吸附 / the steady phase keeps the attach state
        IF NOT bChuckOn THEN
            eState := eRelease;               // 撤电压即进入释放段 / releasing the voltage enters the release phase
        ELSIF fbLossConfirm.Q THEN
            eErr := 16#0003_0337;             // 失吸确认故障码 / loss confirmation fault id
            bError := TRUE;                   // 置故障标志 / raise the error flag
            eHealth := eFailure;              // 失吸 / the wafer is lost
            eState := eFault;                 // 落故障态 / enter the fault state
            bAttached := FALSE;               // 确认失吸 / confirmed detached
        END_IF

    eRelease:
        bAttached := FALSE;                   // 释放段即不再算吸附 / the release phase is not an attached state
        IF fCur <= DL_FLOAT_EPS THEN
            eState := eIdle;                  // 电流归零即回空闲 / back to idle once the current vanishes
        ELSIF bChuckOn THEN
            eState := eBuild;                 // 释放过程中重新上电：重新建立 / re-energising during release restarts the build
        END_IF

    eFault:
        bAttached := FALSE;                   // 故障态不判吸附 / no attach judgement in the fault state
        IF NOT bChuckOn THEN
            eState := eIdle;                  // 撤电压允许退出故障态（复位亦可）/ withdrawing the voltage also leaves the fault state
        END_IF

ELSE
    eErr := 16#0003_0336;                     // 故障级：非法状态兜底 / fault level, illegal state fallback
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;                         // 回故障态 / fall back to the fault state
    eHealth := eUnknown;                      // 状态不可信 / the state is untrustworthy
END_CASE
END_FUNCTION_BLOCK
