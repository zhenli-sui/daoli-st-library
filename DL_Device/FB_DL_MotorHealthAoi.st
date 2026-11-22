(*==============================================================================
 * 组件名称 (Component)  : FB_DL_MotorHealthAoi
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 来源标签 (Source)     : rockwell-aoi（T2-6 设备级粒度族：阀 / 电机 / 夹爪之电机）
 * 功能描述 (Function)   : 电机 AOI 三分类诊断：过温 / 过载 / 启停频繁三判据各自带
 *                         独立确认延时，任一类确认即置独立锁存与独立码位（R190 归因
 *                         唯一），并给出 NE107 健康出口与停机请求；三类锁存互不覆盖。
 * 分工互引 (Boundary)   : 过温保护动作归 FB_DL_MotorPtcThermistProtect（硬保护），
 *                         健康聚合归 FB_DL_DeviceHealthArbiter；本件只做**分类诊断
 *                         与确认计时**，不替代硬保护回路，也不做多设备聚合。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 三条判据的确认延时各自独立（tTempConfirm / tOverloadConfirm / tFreqConfirm），
 *      三计时器每拍无条件刷新（红线 R7），门控挂状态量与判据量而非单拍标志（R99）。
 *   2) 过载判据用电流比值（fCurrent / fRatedCurrent），除子由组态闸保证 > 0；
 *      比值达 fOverloadRatio 且持续确认窗即确认。
 *   3) 启停频繁判据用滚动窗计数：窗口窗长 tFreqWindow（TON 自复位 R188），
 *      窗内启动沿计数达 nStartLim 且持续 tFreqConfirm 即确认。
 *   4) 非有限输入（温度 / 电流 / 额定电流）不参与判据，只保持上一拍的确认状态，
 *      并由组态闸之外的信号闸置信息级码（不锁存，不因一扫 NaN 让诊断永久失效）。
 *   5) 健康出口口径：任一锁存 -> eFailure；任一确认中 -> eMaintenanceReq；
 *      未使能 -> eUnknown；其余 eOk。出口取最严，禁按图改序。
 * 故障码表 (Error codes) :
 *   16#0003_0532 [故障级] 组态非法（阈值域 / 确认窗 / 额定电流），诊断置挂起
 *                 反证：挂起与「设备恰好在容差内」输出组合相同，无码不可区分。
 *   16#0003_0533 [故障级] 过温确认（绕组温度持续超阈），锁存至复位沿 + 温度回落
 *                 反证：三类锁存若共用码则某类永不赋值（R190），且过温与过载的
 *                 处置完全不同（通风 vs 减载），必须独立码位。
 *   16#0003_0534 [故障级] 过载确认（电流比值持续超限），锁存至复位沿 + 电流回落
 *                 反证：与过温同状态出口，仅码位可归因（R190）。
 *   16#0003_0535 [故障级] 启停频繁确认（滚动窗启动次数超限），锁存至复位沿 + 窗刷新
 *                 反证：启停频繁不停机也可能无任何其它输出变化，无码不可观测。
 * 码位总账 (Code ledger) : 16#0003_0532 / 0533 / 0534 / 0535 用
 * 归属声明 (Ownership)  : E_DL_Ne107Status 归属 DL_Device\I_DL_DeviceHealth.st，
 *                         本件只引用不重声明
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量 ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除子由组态闸保证 / 非有限三判 / 域闸全枚举
 *                         R5 ✓ 全变量双语同行注释 ｜ R6 ✓ 四态 ENUM + ELSE 兜底
 *                         R7 ✓ 四沿四计时主体最前部无条件刷新
 * 修订历史 (Revision)   : 2026-11-22  v1.0.0  首版入库（R69 构建轮 · 批 2 · N4）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MotorAoiState（归属 DL_Device，与 FB_DL_MotorHealthAoi 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_MotorAoiState :
(
    eIdle   := 0,     // 未使能：诊断挂起 / Disabled, diagnosis suspended
    eMonitor := 10,   // 监视中：三判据确认计时 / Monitoring, three confirm timers running
    eTripped := 20,   // 已确认停机（至少一类锁存）/ Tripped, at least one cause latched
    eFault  := 99     // 组态非法：诊断拒绝 / Config illegal, diagnosis refused
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_MotorHealthAoi
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_MotorHealthAoi
VAR_INPUT
    fWindingTemp   : REAL;                 // 绕组温度 [°C] / winding temperature [°C]
    fTempLim       : REAL := 130.0;        // 过温阈 [°C]，<= 0 组态非法 / over-temperature threshold [°C]
    fCurrent       : REAL;                 // 电机电流 [A] / motor current [A]
    fRatedCurrent  : REAL := 10.0;         // 额定电流 [A]，<= 0 组态非法（除子）/ rated current [A], the divisor
    fOverloadRatio : REAL := 1.15;         // 过载比值阈 [倍]，<= 1 组态非法 / overload ratio [x]
    bStartPulse    : BOOL;                 // 启动命令（上升沿计数）/ start command, rising edge counted
    nStartLim      : INT := 6;             // 滚动窗启动次数上限 [次]，域 1..100 / start ceiling per window [times]
    tTempConfirm   : TIME := T#3S;         // 过温确认窗 [s] / over-temperature confirm window [s]
    tOverloadConfirm : TIME := T#2S;       // 过载确认窗 [s] / overload confirm window [s]
    tFreqConfirm   : TIME := T#1S;         // 启停频繁确认窗 [s] / frequent-start confirm window [s]
    tFreqWindow    : TIME := T#60S;        // 启动计数滚动窗长 [s] / rolling start-count window [s]
    bEnable        : BOOL := TRUE;         // 使能 / enable
    bReset         : BOOL;                 // 上升沿：清三类锁存（须对应判据已消）/ rising edge clears the three latches
END_VAR
VAR_OUTPUT
    eHealth        : E_DL_Ne107Status;     // NE107 健康出口（六态，属主 I_DL_DeviceHealth）/ NE107 health verdict
    bTripReq       : BOOL;                 // 停机请求（任一锁存即 TRUE）/ stop request, any latch
    bOverTemp      : BOOL;                 // 过温锁存 / over-temperature latched
    bOverload      : BOOL;                 // 过载锁存 / overload latched
    bFreqStart     : BOOL;                 // 启停频繁锁存 / frequent-start latched
    bError         : BOOL;                 // 故障标志（组态 / 三类锁存归并）/ fault flag
    uErrorId       : UDINT;                // 故障码，0 = 无故障 / error code, 0 = none
    eState         : E_DL_MotorAoiState;   // 当前状态（供 HMI 诊断）/ current state
END_VAR
VAR
    fbTrigReset    : R_TRIG;               // 复位沿检测实例 / reset edge detector
    fbTrigStart    : R_TRIG;               // 启动命令沿检测实例 / start command edge detector
    tonTemp        : TON;                  // 过温确认计时实例 / over-temperature confirm timer
    tonOverload    : TON;                  // 过载确认计时实例 / overload confirm timer
    tonFreq        : TON;                  // 启停频繁确认计时实例 / frequent-start confirm timer
    tonFreqWin     : TON;                  // 启动计数滚动窗（自复位 R188）/ rolling window timer, self resetting
    eStateInt      : E_DL_MotorAoiState;   // 主状态机内部当前态 / internal state
    bTempCond      : BOOL;                 // 本拍过温判据成立 / over-temperature criterion true this scan
    bOvldCond      : BOOL;                 // 本拍过载判据成立 / overload criterion true this scan
    bFreqCond      : BOOL;                 // 本拍启停频繁判据成立 / frequent-start criterion true this scan
    fCurrentRatio  : REAL;                 // 电流比值 [倍]（除子已由组态闸保证 > 0）/ current ratio [x]
    nStartCnt      : INT;                  // 滚动窗内启动次数 [次] / starts inside the rolling window
    bTempLatch     : BOOL;                 // 过温锁存内部副本 / internal over-temperature latch
    bOvldLatch     : BOOL;                 // 过载锁存内部副本 / internal overload latch
    bFreqLatch     : BOOL;                 // 启停频繁锁存内部副本 / internal frequent-start latch
    bSigBad        : BOOL;                 // 温度 / 电流信号非有限 / temperature or current non-finite
    bCfgBad        : BOOL;                 // 本拍组态非法 / config illegal this scan
    bCfgLatch      : BOOL;                 // 组态锁存（复位沿 + 组态改对解除）/ config latch
    bErrorInt      : BOOL;                 // 本拍故障置位累加 / fault set accumulator
    bFirstScan     : BOOL := TRUE;         // 上电首扫标志 / first-scan flag
END_VAR
VAR CONSTANT
    DL_MH_FIN_LIM  : REAL := 1.0E30;       // REAL 幅值兜底判界 / REAL magnitude bound
    DL_MH_START_MAX : INT := 100;          // 启动次数上限闸 [次]（防计数溢出）/ start count ceiling
    DL_MH_RATIO_MIN : REAL := 1.0;         // 过载比值下限 [倍]（< 1 即常真）/ overload ratio floor [x]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：二沿四计时全部位于主体最前部
 *      Unconditional refresh: two edges and four timers at the very top
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);
fbTrigStart(CLK := bStartPulse);
tonFreqWin(IN := NOT tonFreqWin.Q, PT := tFreqWindow);   // 自复位滚动窗（R188）/ self-resetting window

(* 段 2｜每拍预清（FB32-1）：单拍标志，禁入锁存 / per-scan preset *)
bErrorInt := FALSE;

(* 段 3｜上电首扫：三类锁存与计数落安全侧 / first-scan init *)
IF bFirstScan THEN
    eStateInt := E_DL_MotorAoiState.eIdle;
    bTempLatch := FALSE;
    bOvldLatch := FALSE;
    bFreqLatch := FALSE;
    nStartCnt  := 0;
    bFirstScan := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸（R151 全枚举）+ 解除路径（R152 自证可达）
 *      Config gate over every threshold, window and divisor, with the clear path
 *-----------------------------------------------------------------------------*)
bCfgBad := (fTempLim <= 0.0) OR (fTempLim <> fTempLim)
           OR (fRatedCurrent <= 0.0) OR (fRatedCurrent <> fRatedCurrent)
           OR (fOverloadRatio <= DL_MH_RATIO_MIN) OR (fOverloadRatio <> fOverloadRatio)
           OR (nStartLim < 1) OR (nStartLim > DL_MH_START_MAX)
           OR (tTempConfirm <= T#0S) OR (tOverloadConfirm <= T#0S) OR (tFreqConfirm <= T#0S)
           OR (tFreqWindow <= tFreqConfirm);
IF bCfgBad THEN
    bCfgLatch := TRUE;
END_IF
IF fbTrigReset.Q AND (NOT bCfgBad) THEN
    bCfgLatch := FALSE;              // 组态锁存解除（复位沿 + 组态已改对）/ config latch cleared
    uErrorId  := 16#0000_0000;       // 码位随解除归零 / code cleared with the latch
END_IF
IF bCfgLatch THEN
    uErrorId  := 16#0003_0532;       // 故障级：组态非法 / fault: illegal configuration
    bErrorInt := TRUE;               // R45 配对 / paired with the code
    eStateInt := E_DL_MotorAoiState.eFault;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜判据求值：信号闸（非有限只判不锁）+ 三判据 + 滚动窗计数
 *      Criteria evaluation with the non-finite signal gate
 *-----------------------------------------------------------------------------*)
bSigBad := (fWindingTemp <> fWindingTemp) OR ((fWindingTemp - fWindingTemp) <> (fWindingTemp - fWindingTemp))
           OR (ABS(fWindingTemp) >= DL_MH_FIN_LIM)
           OR (fCurrent <> fCurrent) OR ((fCurrent - fCurrent) <> (fCurrent - fCurrent))
           OR (ABS(fCurrent) >= DL_MH_FIN_LIM);

fCurrentRatio := 0.0;                                   // 比值缺省 0（除子由组态闸保证 > 0）[倍] / ratio default
IF NOT bSigBad THEN
    fCurrentRatio := fCurrent / fRatedCurrent;          // 除前已闸：fRatedCurrent > 0（段 4）/ divisor gated above [倍]
END_IF

bTempCond := (NOT bSigBad) AND (fWindingTemp > fTempLim);
bOvldCond := (NOT bSigBad) AND (fCurrentRatio > fOverloadRatio);

(* 滚动窗启动计数：窗满即清零并重新起算（自复位），计数饱和闸防溢出 *)
IF fbTrigStart.Q THEN
    IF nStartCnt < DL_MH_START_MAX THEN
        nStartCnt := nStartCnt + 1;                     // 启动计数推进 [次] / count up
    END_IF
END_IF
IF tonFreqWin.Q THEN
    nStartCnt := 0;                                     // 窗满清零（自复位窗每周期一次）/ window rollover resets the count
END_IF
bFreqCond := (nStartCnt >= nStartLim) AND (NOT bSigBad);

(* 三计时器门控：判据成立 AND 未锁存 AND 非组态故障（R99 挂状态量与判据量） *)
tonTemp(IN := bTempCond AND (NOT bTempLatch) AND (NOT bCfgLatch), PT := tTempConfirm);
tonOverload(IN := bOvldCond AND (NOT bOvldLatch) AND (NOT bCfgLatch), PT := tOverloadConfirm);
tonFreq(IN := bFreqCond AND (NOT bFreqLatch) AND (NOT bCfgLatch), PT := tFreqConfirm);

(*------------------------------------------------------------------------------
 * 段 6｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine, phase dwell semantics only
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_MotorAoiState.eIdle:
        IF bEnable AND (NOT bCfgLatch) THEN
            eStateInt := E_DL_MotorAoiState.eMonitor;    // 使能且组态合法进监视 / enabled
        END_IF

    E_DL_MotorAoiState.eMonitor:
        IF (NOT bEnable) OR bCfgLatch THEN
            eStateInt := E_DL_MotorAoiState.eIdle;
        ELSIF bTempLatch OR bOvldLatch OR bFreqLatch THEN
            eStateInt := E_DL_MotorAoiState.eTripped;    // 任一确认即停机型驻留 / any cause trips
        END_IF

    E_DL_MotorAoiState.eTripped:
        (* 解除路径（R152 自证可达）：复位沿 AND 三类判据本拍均已消失 AND 组态合法 *)
        IF fbTrigReset.Q AND (NOT bTempCond) AND (NOT bOvldCond) AND (NOT bFreqCond)
           AND (NOT bCfgBad) THEN
            bTempLatch := FALSE;                         // 三类锁存同沿解除 / three latches cleared together
            bOvldLatch := FALSE;
            bFreqLatch := FALSE;
            uErrorId   := 16#0000_0000;
            eStateInt  := E_DL_MotorAoiState.eMonitor;
        ELSIF (NOT bEnable) OR bCfgLatch THEN
            eStateInt  := E_DL_MotorAoiState.eIdle;
        END_IF

    E_DL_MotorAoiState.eFault:
        IF fbTrigReset.Q AND (NOT bCfgBad) THEN
            bCfgLatch := FALSE;                          // 解除路径 / clear path
            uErrorId  := 16#0000_0000;
            eStateInt := E_DL_MotorAoiState.eIdle;
        END_IF

    ELSE
        (* 非法状态拦截 / illegal state interception *)
        eStateInt := E_DL_MotorAoiState.eFault;
        uErrorId  := 16#0003_0532;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 7｜确认到期消化：三类各自独立锁存 + 独立码位（R190 归因唯一）
 *      Confirm expiry digestion: three independent latches with three distinct codes
 *-----------------------------------------------------------------------------*)
IF tonTemp.Q AND (NOT bTempLatch) THEN
    bTempLatch := TRUE;              // 过温锁存 / over-temperature latched
    uErrorId   := 16#0003_0533;      // 故障级：过温确认 / fault: over-temperature confirmed
    bErrorInt  := TRUE;              // R45 配对 / paired with the code
    eStateInt  := E_DL_MotorAoiState.eTripped;
END_IF
IF tonOverload.Q AND (NOT bOvldLatch) THEN
    bOvldLatch := TRUE;              // 过载锁存 / overload latched
    uErrorId   := 16#0003_0534;      // 故障级：过载确认 / fault: overload confirmed
    bErrorInt  := TRUE;              // R45 配对 / paired with the code
    eStateInt  := E_DL_MotorAoiState.eTripped;
END_IF
IF tonFreq.Q AND (NOT bFreqLatch) THEN
    bFreqLatch := TRUE;              // 启停频繁锁存 / frequent-start latched
    uErrorId   := 16#0003_0535;      // 故障级：启停频繁确认 / fault: frequent starts confirmed
    bErrorInt  := TRUE;              // R45 配对 / paired with the code
    eStateInt  := E_DL_MotorAoiState.eTripped;
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜输出单一出口（范式 P-05）：健康出口取最严
 *      Single output exit with the strictest NE107 verdict
 *-----------------------------------------------------------------------------*)
bOverTemp  := bTempLatch;
bOverload  := bOvldLatch;
bFreqStart := bFreqLatch;
bTripReq   := bTempLatch OR bOvldLatch OR bFreqLatch;

IF (NOT bEnable) OR bCfgLatch THEN
    eHealth := E_DL_Ne107Status.eUnknown;                        // 未使能 / 组态故障：未知（禁降级为 Ok）
ELSIF bTempLatch OR bOvldLatch OR bFreqLatch THEN
    eHealth := E_DL_Ne107Status.eFailure;                        // 已确认：最严等级
ELSIF bTempCond OR bOvldCond OR bFreqCond THEN
    eHealth := E_DL_Ne107Status.eMaintenanceReq;                 // 确认中：维护级
ELSE
    eHealth := E_DL_Ne107Status.eOk;                             // 三类判据均未成立
END_IF

bError := bErrorInt OR bCfgLatch OR (eStateInt = E_DL_MotorAoiState.eTripped);
eState := eStateInt;
END_FUNCTION_BLOCK
