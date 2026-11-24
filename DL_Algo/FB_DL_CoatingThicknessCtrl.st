// =====================================================================
// FB_DL_CoatingThicknessCtrl.st
// 涂布面密度闭环控制（一阶滤波 + 纯滞后补偿 + 积分型无差调节）
// Coating weight closed-loop control FB
// 码位: 16#0002_371A ~ 16#0002_371E (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 4)
// =====================================================================
FUNCTION_BLOCK FB_DL_CoatingThicknessCtrl
VAR_INPUT
    bEnable            : BOOL  := FALSE;   // 使能，FALSE 冻结输出 / Enable, freeze outputs when FALSE
    bStart             : BOOL  := FALSE;   // 上升沿投入闭环 / Start on rising edge
    bReset             : BOOL  := FALSE;   // 复位故障，仅 eFault 生效 / Fault reset
    bMeasValid         : BOOL  := FALSE;   // 测厚数据有效 / Measurement valid
    fMeas_gsm          : REAL  := 0.0;     // 实测面密度 0~500 g/m² / Measured coat weight [g/m2]
    fSp_gsm            : REAL  := 120.0;   // 面密度设定 1~500 g/m² / Setpoint [g/m2]
    fBandPct           : REAL  := 0.5;     // 死区带 0~5 % / Dead band [%]
    fGain_mm_per_gsm   : REAL  := 0.01;    // 间隙-面密度增益 0.0001~1 mm/(g/m²) / Gap gain [mm/(g/m2)]
    fGapInit_mm        : REAL  := 0.250;   // 初始间隙 0.05~2.0 mm / Initial gap [mm]
    fTrimMax_mm        : REAL  := 0.100;   // 相对初始间隙最大修正 0.001~1.0 mm / Max trim [mm]
    fRateMax_mm_s      : REAL  := 0.005;   // 修正速率上限 >0 mm/s / Trim rate limit [mm/s]
    tDeadTime          : TIME  := T#30S;   // 纯滞后 T#1S~T#300S / Dead time [s]
    tCycle             : TIME  := T#100MS; // 采样周期 T#10MS~T#5S / Sample cycle [s]
END_VAR
VAR_OUTPUT
    fGapCmd_mm         : REAL;             // 模头间隙命令 0.05~2.0 mm / Gap command [mm]
    fDev_gsm           : REAL;             // 滞后补偿后偏差 g/m² / Delayed deviation [g/m2]
    fTrim_mm           : REAL;             // 当前累计修正 mm / Accumulated trim [mm]
    bInBand            : BOOL;             // 偏差在带内 / Within dead band
    bActive            : BOOL;             // 闭环投入中 / Loop active
    eState             : E_DL_CoatingState; // 状态 / State
    eErr               : UDINT;            // 错误码 / Error code
END_VAR
VAR
    rtrigStart         : R_TRIG;           // 启动上升沿检测 / Start rising-edge detector
    fFilt_gsm          : REAL;             // 一阶滤波后测厚值 / Filtered measurement [g/m2]
    fDevNow_gsm        : REAL;             // 本拍新鲜偏差 / Fresh deviation this cycle [g/m2]
    aDelayQ            : ARRAY[0..2999] OF REAL; // 延时队列（偏差历史）/ Delay queue of deviations [g/m2]
    uQHead             : UDINT;            // 队列写指针 / Queue write pointer
    uQLen              : UDINT;            // 队列有效长度 / Queue valid length
    uQLenCfg           : UDINT;            // 组态队列长度（CEIL 后）/ Configured queue length
    uIdx               : UDINT;            // 循环下标 / Loop index
    fRateStep          : REAL;             // 单拍速率步长 / Rate step per cycle [mm]
    fTrimNew           : REAL;             // 修正后临时累计值 / Tentative new trim [mm]
    fBandAbs           : REAL;             // 死区绝对带宽 / Absolute dead band [g/m2]
    tCycleS            : REAL;             // 周期秒值（钳 ≥0.01）/ Cycle in seconds, clamped [s]
    tDeadS             : REAL;             // 滞后秒值 / Dead time in seconds [s]
    xFirstScan         : BOOL := TRUE;     // 首扫标记 / First-scan flag
    tCyclePrev         : TIME  := T#0MS;   // 上拍周期快照 / Previous cycle snapshot
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0002_371A 信息 闭环运行正常 / 带内不动作
//   16#0002_371B 故障 输入非有限，或 tDeadTime/tCycle 非法（0 或超出域）
//   16#0002_371C 故障 fGain/fTrimMax/fRateMax/fSp 组态错（≤0）
//   16#0002_371D 信息 修正触限 → 停止同向积分，eState=eLimit
//   16#0002_371E 信息 测厚无效 → 冻结积分、输出保持、bActive=FALSE
// ---------------------------------------------------------------------

// ---- 时间参数转秒（TIME/1000 毫秒基准）/ Convert times to seconds ----
tCycleS := TIME_TO_REAL(tCycle) / 1000.0;   // 周期秒值 / Cycle seconds [s]
tDeadS  := TIME_TO_REAL(tDeadTime) / 1000.0; // 滞后秒值 / Dead-time seconds [s]
IF tCycleS < 0.01 THEN
    tCycleS := 0.01;    // 钳下限防步长爆炸 / Clamp minimum 10 ms
END_IF

// ---- 组态合法性检查（故障级，锁存于 eFault）/ Configuration validity check ----
IF (tCycle = T#0MS) OR (tDeadTime = T#0MS)
   OR (tDeadS > 300.0) OR (tDeadS < 1.0)
   OR (tCycleS > 5.0)
   OR (fMeas_gsm <> fMeas_gsm) OR (ABS(fMeas_gsm) >= 1.0E12)
   OR (fSp_gsm <> fSp_gsm) OR (ABS(fSp_gsm) >= 1.0E12) THEN
    // 非有限或时域非法 / Non-finite or invalid time domain
    IF eState <> E_DL_CoatingState.eFault THEN
        eState := E_DL_CoatingState.eFault;  // 进入故障态（锁存）/ Enter latched fault
    END_IF
    bActive  := FALSE;          // 闭环退出 / Loop inactive
    eErr     := 16#0002_371B;   // 故障码 / Fault code
    // 故障态输出保持，不推进 / Hold outputs, no advance
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 组态错闸（故障级）/ Configuration fault gate ----
IF (fGain_mm_per_gsm <= 0.0) OR (fTrimMax_mm <= 0.0)
   OR (fRateMax_mm_s <= 0.0) OR (fSp_gsm <= 0.0) THEN
    IF eState <> E_DL_CoatingState.eFault THEN
        eState := E_DL_CoatingState.eFault;  // 进入故障态（锁存）/ Enter latched fault
    END_IF
    bActive := FALSE;           // 闭环退出 / Loop inactive
    eErr    := 16#0002_371C;    // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 延时队列长度组态 = CEIL(tDeadTime/tCycle)，上限 3000 拍 / Delay queue length config ----
uQLenCfg := REAL_TO_UDINT(CEIL(tDeadS / tCycleS));  // 拍数 / Queue length in cycles
IF uQLenCfg > 3000 THEN
    uQLenCfg := 3000;           // 超限按 3000 防内存爆 / Cap at 3000
    IF eState <> E_DL_CoatingState.eFault THEN
        eState := E_DL_CoatingState.eFault;  // 故障锁存 / Latch fault
    END_IF
    bActive := FALSE;           // 闭环退出 / Loop inactive
    eErr    := 16#0002_371B;    // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF
IF uQLenCfg = 0 THEN
    uQLenCfg := 1;              // 至少 1 拍防零长度 / Minimum 1 cycle
END_IF

// ---- 故障复位（仅 eFault 生效）/ Fault reset only in fault state ----
IF (eState = E_DL_CoatingState.eFault) AND bReset THEN
    eState := E_DL_CoatingState.eIdle;  // 回空闲态 / Back to idle
    fTrim_mm := 0.0;            // 清累计修正 / Clear trim
    uQLen := 0;                 // 清延时队列 / Clear delay queue
    uQHead := 0;                // 指针归零 / Reset pointer
END_IF

// ---- 首扫初始化（R16 首扫纪律）/ First-scan initialization ----
IF xFirstScan THEN
    fGapCmd_mm := fGapInit_mm;  // 首扫置初始间隙 / Init gap on first scan
    fFilt_gsm  := fSp_gsm;      // 滤波器初值取设定 / Filter init at setpoint
    xFirstScan := FALSE;        // 清首扫标记 / Clear flag
    tCyclePrev := tCycle;       // 记录周期 / Record cycle
END_IF

// ---- 周期变化检测：清队列并重填当前偏差 / Cycle change: flush queue and refill ----
IF (tCyclePrev <> tCycle) AND (NOT xFirstScan) THEN
    FOR uIdx := 0 TO 2999 DO
        aDelayQ[uIdx] := 0.0;   // 清空历史脏值 / Clear stale history
    END_FOR
    fFilt_gsm := fSp_gsm;       // 滤波器重新对齐设定 / Re-align filter
    uQLen := 0;                 // 清队列长度 / Reset length
    uQHead := 0;                // 指针归零 / Reset pointer
    tCyclePrev := tCycle;       // 更新周期快照 / Update snapshot
END_IF

// ---- 启动沿：仅 eIdle 可进 eRun，非沿不重复初始化 / Start edge: idle to run only ----
rtrigStart(CLK := bStart);      // 沿检测无条件周期刷新 / Unconditional per-cycle refresh
IF rtrigStart.Q AND (eState = E_DL_CoatingState.eIdle) AND bEnable THEN
    eState    := E_DL_CoatingState.eRun;  // 投入闭环 / Activate loop
    fTrim_mm  := 0.0;           // 清累计修正 / Clear trim
    fGapCmd_mm := fGapInit_mm;  // 间隙回初始值 / Reset gap to initial
    fFilt_gsm := fSp_gsm;       // 滤波器重新对齐 / Re-align filter
    uQLen := 0;                 // 清延时队列 / Clear queue
    uQHead := 0;                // 指针归零 / Reset pointer
END_IF

// ---- 输出默认量 / Default per-cycle outputs ----
bActive := FALSE;               // 默认非投入 / Default inactive
bInBand := FALSE;               // 默认带外 / Default out of band

// ---- 状态机 / State machine ----
CASE eState OF

    E_DL_CoatingState.eIdle:    // 空闲态 / Idle state
        fGapCmd_mm := fGapInit_mm;  // 间隙保持初始 / Hold initial gap
        fTrim_mm   := 0.0;          // 修正清零 / Trim zero
        eErr       := 16#0002_371A; // 信息级：正常空闲 / Info: idle normal

    E_DL_CoatingState.eRun,     // 运行态 / Run state
    E_DL_CoatingState.eLimit:   // 限幅态 / Limit state
        bActive := TRUE;        // 闭环投入 / Loop active

        // ---- 测厚有效性：冻结积分、输出保持 / Invalid meas: freeze integral, hold output ----
        IF NOT bMeasValid THEN
            eErr    := 16#0002_371E;  // 信息级：测厚无效 / Info: meas invalid
            // fGapCmd_mm 保持不动（绝不因无测量而推进）/ Hold gap command
        ELSE
            // ---- 非有限测厚闸 / Non-finite measurement guard ----
            IF (fMeas_gsm <> fMeas_gsm) OR (ABS(fMeas_gsm) >= 1.0E12) THEN
                eErr := 16#0002_371E; // 按无效测厚处理 / Treat as invalid
            ELSE
                // ---- 一阶滤波（内联，alpha=0.2）/ Inline first-order filter ----
                fFilt_gsm := fFilt_gsm + 0.2 * (fMeas_gsm - fFilt_gsm);  // 一阶低通 / First-order LPF

                // ---- 新鲜偏差 / Fresh deviation ----
                fDevNow_gsm := fFilt_gsm - fSp_gsm;   // 偏差 / Deviation [g/m2]

                // ---- 死区判（防抖动磨模头）/ Dead band check ----
                fBandAbs := fSp_gsm * fBandPct / 100.0;  // 绝对带宽 / Absolute band [g/m2]
                IF ABS(fDevNow_gsm) <= fBandAbs THEN
                    bInBand := TRUE;    // 带内标志 / In-band flag
                    eErr    := 16#0002_371A;  // 信息级：带内不动作 / Info: in-band idle
                ELSE
                    // ---- 写入延时队列（循环缓冲）/ Write fresh deviation into delay queue ----
                    aDelayQ[uQHead] := fDevNow_gsm;   // 写入当前偏差 / Store fresh deviation
                    uQHead := uQHead + 1;             // 指针前移 / Advance pointer
                    IF uQHead >= uQLenCfg THEN
                        uQHead := 0;                  // 回绕 / Wrap around
                    END_IF
                    IF uQLen < uQLenCfg THEN
                        uQLen := uQLen + 1;           // 队列填充中 / Queue filling
                    END_IF

                    // ---- 读出滞后 tDeadTime 拍前的偏差 / Read delayed deviation ----
                    fDev_gsm := aDelayQ[uQHead];      // 滞后补偿后偏差 / Delayed deviation [g/m2]

                    // ---- 积分型无差调节：按增益换算间隙增量 / Integral-type adjustment ----
                    fRateStep := fRateMax_mm_s * tCycleS;  // 单拍速率步长 / Rate step per cycle [mm]
                    fTrimNew := fTrim_mm - fGain_mm_per_gsm * fDev_gsm;  // 目标修正 / Tentative trim [mm]

                    // ---- 增量限速 / Rate limiting ----
                    IF (fTrimNew - fTrim_mm) > fRateStep THEN
                        fTrimNew := fTrim_mm + fRateStep;  // 正向限速 / Positive slew limit
                    ELSIF (fTrimNew - fTrim_mm) < -fRateStep THEN
                        fTrimNew := fTrim_mm - fRateStep;  // 负向限速 / Negative slew limit
                    END_IF

                    // ---- 总量限幅 + 触限抗饱和 / Total clamp + anti-windup at limit ----
                    IF fTrimNew > fTrimMax_mm THEN
                        fTrimNew := fTrimMax_mm;   // 上限钳制 / Upper clamp
                        eState := E_DL_CoatingState.eLimit;  // 进入限幅态 / Enter limit state
                        eErr := 16#0002_371D;      // 信息级：触限 / Info: at limit
                    ELSIF fTrimNew < -fTrimMax_mm THEN
                        fTrimNew := -fTrimMax_mm;  // 下限钳制 / Lower clamp
                        eState := E_DL_CoatingState.eLimit;  // 进入限幅态 / Enter limit state
                        eErr := 16#0002_371D;      // 信息级：触限 / Info: at limit
                    ELSE
                        eErr := 16#0002_371A;      // 信息级：正常调节 / Info: normal
                    END_IF

                    // ---- 触限后停止同向积分：只在离限方向才更新 / Anti-windup: only move away from limit ----
                    IF (eState = E_DL_CoatingState.eLimit) AND (fTrim_mm = fTrimMax_mm) AND (fTrimNew > fTrim_mm) THEN
                        // 已在上限且继续同向：冻结 / At upper limit, same direction: freeze
                    ELSIF (eState = E_DL_CoatingState.eLimit) AND (fTrim_mm = -fTrimMax_mm) AND (fTrimNew < fTrim_mm) THEN
                        // 已在下限且继续同向：冻结 / At lower limit, same direction: freeze
                    ELSE
                        fTrim_mm := fTrimNew;      // 采纳修正 / Adopt trim
                    END_IF

                    // ---- 间隙命令 = 初始 + 修正 / Gap command = initial + trim ----
                    fGapCmd_mm := fGapInit_mm + fTrim_mm;  // 输出间隙命令 / Output gap command [mm]
                END_IF
            END_IF
        END_IF

        // ---- 限幅态回到运行态：修正脱离边界即回 eRun / Limit back to run when off boundary ----
        IF (eState = E_DL_CoatingState.eLimit)
           AND (ABS(fTrim_mm) < fTrimMax_mm) THEN
            eState := E_DL_CoatingState.eRun;  // 回运行态 / Back to run
        END_IF

    ELSE                        // 非法状态拦截 / Illegal state interception
        eState := E_DL_CoatingState.eFault;  // 落故障态 / Fall to fault
        bActive := FALSE;       // 闭环退出 / Loop inactive
        eErr := 16#0002_371B;   // 故障码 / Fault code
END_CASE

// ---- 使能撤销：冻结输出回空闲 / Disable: freeze and idle ----
IF NOT bEnable THEN
    bActive := FALSE;           // 闭环退出 / Loop inactive
    eState  := E_DL_CoatingState.eIdle;  // 回空闲 / Back to idle
END_IF

END_FUNCTION_BLOCK
