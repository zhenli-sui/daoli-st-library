(*==============================================================================
 * 组件名称 (Component)  : FB_DL_DosingPumpCalib
 * 所属子库 (Sublibrary) : DL_Device
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准库 R_TRIG / ABS，零厂商方言
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 计量泵脉冲当量标定公开工艺语义（半导体/化工通用），
 *                         道莅 clean-room 防御性实现，未复制任何外部源码行
 * 功能描述 (Function)   : 计量泵标定与脉冲当量校验件。由标定容积与实测容积
 *                         反算实测当量（毫升每脉冲），与组态当量比偏差，
 *                         超差给出告警码并输出按偏差反向修正、夹在组态
 *                         0.5~2.0 倍带内的修正当量，供泵组态直接替换。
 * 状态机   (States)     : eIdle 待机 / eRun 单拍计算 / eDone 单拍完成脉冲 /
 *                         eFault 故障锁定（CASE 带 ELSE 兜底）。
 * 码位     (Codes)      : 16#0003_00F7 信息级：中止请求提示（不置 bError）
 *                         16#0003_00F8 故障级：样本不足（脉冲数低于下限）
 *                         16#0003_00F9 故障级：容积非法（标定/实测容积非有限
 *                                      或不大于零）
 *                         16#0003_00FA 故障级：组态当量非法（非有限或不大于零）
 *                         16#0003_00FB 告警级：当量偏差超差（仅告警不置
 *                                      bError，规格 §5.2 条目 6 优先于槽位
 *                                      通则，头注释留档）
 * 边界防错 (Boundary)   : 1 脉冲数低于下限判样本不足拒绝出结果；
 *                         2 组态当量非法或非有限锁故障并冻结输出（保持末次
 *                           有效值，禁零值覆盖）；
 *                         3 分母（脉冲数）为零防护：与样本不足同槽拒绝；
 *                         4 bAbort 立即清忙、不产出半结果、不置完成；
 *                         5 bDone 为新沿后单拍脉冲（R27 输出保持语义：
 *                           跨拍须清零）；
 *                         6 故障锁存的可达解除路径：下一次 bStart 上升沿
 *                           重新受理（故障态下仍受理启动，复位即重试）。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 7，
 *                         替代原 EscChuckCurrentMon 派单，见派单勘误 §5.2）
 *==============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_DpcState（归属本功能块，同文件发布，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DpcState :
(
    eIdle  := 0,    // 待机：等待启动沿 / Idle, waiting for start edge
    eRun   := 10,   // 计算态：单拍完成标定计算 / Run, calibration computed in one scan
    eDone  := 20,   // 完成态：单拍完成脉冲后回待机 / Done, one-scan pulse then idle
    eFault := 99    // 故障态：锁存等待重试 / Fault, latched awaiting retry
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_DosingPumpCalib
 * 调用约定: 每个扫描周期无条件调用一次；标定数据经引脚单次注入。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_DosingPumpCalib
VAR_INPUT
    bStart             : BOOL := FALSE;  // 启动沿（含故障态重试受理）/ Start edge, also retries from fault
    bAbort             : BOOL := FALSE;  // 中止请求，任意拍生效 / Abort request, effective on any scan
    fCalVolumeMl       : REAL := 100.0;  // 标定容积 [毫升] / Calibration volume [mL]
    fMeasuredMl        : REAL := 0.0;    // 实测收集容积 [毫升] / Measured collected volume [mL]
    uPulseCount        : UDINT := 0;     // 标定脉冲总数 [个] / Total pulse count [count]
    fNominalMlPerPulse : REAL := 0.1;    // 组态当量 [毫升每脉冲] / Configured equivalent [mL per pulse]
    fTolPct            : REAL := 2.0;    // 偏差告警限 [百分数] / Deviation alarm limit [%]
    uMinPulses         : UDINT := 100;   // 最小样本脉冲数 [个] / Minimum sample pulse count [count]
END_VAR
VAR_OUTPUT
    bBusy              : BOOL;           // 忙标志（计算当拍）/ Busy flag during compute scan
    bDone              : BOOL;           // 完成单拍脉冲（R27）/ Done one-scan pulse
    bError             : BOOL;           // 故障标志，与故障级码配对（R45）/ Fault flag paired with fault codes
    fMeasuredMlPerPulse : REAL;          // 实测当量 [毫升每脉冲] / Measured equivalent [mL per pulse]
    fDeviationPct      : REAL;           // 当量偏差 [百分数] / Equivalent deviation [%]
    fCorrectedMlPerPulse : REAL;         // 修正当量（反向修正并夹带）[毫升每脉冲] / Corrected equivalent [mL per pulse]
    uErrorId           : UDINT;          // 错误码，0 = 无错 / Error code, 0 = none
END_VAR
VAR
    rTrigStart         : R_TRIG;         // 启动沿检测，每拍无条件刷新 / Start edge detector, refreshed every scan
    eState             : E_DL_DpcState;  // 内部状态机 / Internal state machine
    bVolOk             : BOOL;           // 容积对有效性 / Volume pair validity
    bNomOk             : BOOL;           // 组态当量有效性 / Nominal equivalent validity
    bCntOk             : BOOL;           // 样本量有效性 / Sample count validity
    fMeasEquiv         : REAL;           // 计算暂存实测当量 [毫升每脉冲] / Staged measured equivalent [mL per pulse]
    fDevPct            : REAL;           // 计算暂存偏差 [百分数] / Staged deviation [%]
    fCorrEquiv         : REAL;           // 计算暂存修正当量 [毫升每脉冲] / Staged corrected equivalent [mL per pulse]
    fNomAbs            : REAL;           // 组态当量幅值夹带基准 [毫升每脉冲] / Nominal magnitude clamp base [mL per pulse]
    uCodeLatch         : UDINT;          // 故障级锁存码 / Latched fault code
END_VAR
VAR CONSTANT
    DL_DPC_FIN  : REAL  := 1.0E30;       // REAL 有限幅值判界 / REAL finiteness magnitude bound
    DL_DPC_LO   : REAL  := 0.5;          // 修正当量夹带下限系数（组态倍数）/ Corrected clamp low factor
    DL_DPC_HI   : REAL  := 2.0;          // 修正当量夹带上限系数（组态倍数）/ Corrected clamp high factor
    DL_DPC_PCT  : REAL  := 100.0;        // 百分数换算系数 / Percent conversion factor
END_VAR

// ---- 段 1｜边沿实例无条件刷新（红线：禁入条件分支）----------------------------
rTrigStart(CLK := bStart);                            // 启动沿检测 / Start edge detection

// ---- 段 2｜中止请求：立即清忙、不产出半结果、不置完成（信息级提示）--------------
IF bAbort AND ((eState = eRun) OR (eState = eDone)) THEN
    eState    := eIdle;                               // 中止回待机 / Abort returns to idle
    bBusy     := FALSE;                               // 立即清忙 / Clear busy at once
    bDone     := FALSE;                               // 不置完成 / Never set done
    uErrorId  := 16#0003_00F7;                        // 信息级：中止提示 / Info: abort notice
END_IF

// ---- 段 3｜完成脉冲收尾（单拍语义，跨拍清零）------------------------------------
IF eState = eDone THEN
    bDone  := TRUE;                                   // 完成单拍脉冲 / One-scan done pulse
    bBusy  := FALSE;                                  // 完成态清忙 / Clear busy in done
    eState := eIdle;                                  // 下拍回待机 / Back to idle next scan
ELSIF eState = eRun THEN
    bBusy := TRUE;                                    // 计算当拍置忙 / Busy during compute scan
END_IF

// ---- 段 4｜启动沿受理（含故障态重试）--------------------------------------------
IF rTrigStart.Q AND ((eState = eIdle) OR (eState = eFault)) THEN
    bVolOk := (fCalVolumeMl = fCalVolumeMl) AND (fMeasuredMl = fMeasuredMl)
          AND (ABS(fCalVolumeMl) < DL_DPC_FIN) AND (ABS(fMeasuredMl) < DL_DPC_FIN)
          AND (fCalVolumeMl > 0.0) AND (fMeasuredMl > 0.0); // 容积对有限且大于零 / Volumes finite and positive
    bNomOk := (fNominalMlPerPulse = fNominalMlPerPulse)
          AND (ABS(fNominalMlPerPulse) < DL_DPC_FIN)
          AND (fNominalMlPerPulse > 0.0);             // 组态当量有限且大于零 / Nominal finite and positive
    bCntOk := (uPulseCount >= uMinPulses) AND (uPulseCount > 0); // 样本量达标且分母为正 / Sample count adequate, denominator positive
    IF NOT bNomOk THEN
        eState    := eFault;                          // 组态当量非法锁故障 / Illegal nominal latches fault
        uCodeLatch := 16#0003_00FA;                   // 码位：当量非法 / Code: illegal equivalent
        bError    := TRUE;                            // 故障级配对置位（R45）/ Fault flag paired
        uErrorId  := 16#0003_00FA;                    // 故障码回放 / Fault code replayed
    ELSIF NOT bVolOk THEN
        eState    := eFault;                          // 容积非法锁故障 / Illegal volume latches fault
        uCodeLatch := 16#0003_00F9;                   // 码位：容积非法 / Code: illegal volume
        bError    := TRUE;                            // 故障级配对置位 / Fault flag paired
        uErrorId  := 16#0003_00F9;                    // 故障码回放 / Fault code replayed
    ELSIF NOT bCntOk THEN
        eState    := eFault;                          // 样本不足锁故障 / Insufficient sample latches fault
        uCodeLatch := 16#0003_00F8;                   // 码位：样本不足 / Code: insufficient sample
        bError    := TRUE;                            // 故障级配对置位 / Fault flag paired
        uErrorId  := 16#0003_00F8;                    // 故障码回放 / Fault code replayed
    ELSE
        fMeasEquiv := fMeasuredMl / UDINT_TO_REAL(uPulseCount); // 实测当量，分母已验正 / Measured equivalent, denominator verified
        fDevPct := (fMeasEquiv - fNominalMlPerPulse) / fNominalMlPerPulse * DL_DPC_PCT; // 偏差百分数 / Deviation percent
        fNomAbs := ABS(fNominalMlPerPulse);           // 夹带基准幅值 / Clamp base magnitude
        fCorrEquiv := fNominalMlPerPulse * fNominalMlPerPulse / fMeasEquiv; // 反向修正：实测偏大则当量调小 / Inverse correction
        fCorrEquiv := MIN(MAX(fCorrEquiv, DL_DPC_LO * fNomAbs), DL_DPC_HI * fNomAbs); // 夹在组态 0.5~2.0 倍带内 / Clamp to 0.5..2.0x band
        fMeasuredMlPerPulse   := fMeasEquiv;          // 输出实测当量 / Emit measured equivalent
        fDeviationPct         := fDevPct;             // 输出偏差 / Emit deviation
        fCorrectedMlPerPulse  := fCorrEquiv;          // 输出修正当量 / Emit corrected equivalent
        bError    := FALSE;                           // 计算成功清故障 / Clear fault on success
        uCodeLatch := 16#0000_0000;                   // 清锁存码 / Clear latched code
        IF ABS(fDevPct) > fTolPct THEN
            uErrorId := 16#0003_00FB;                 // 告警级：偏差超限（不置 bError）/ Alarm: deviation out of band
        ELSE
            uErrorId := 16#0000_0000;                 // 无码 / No code
        END_IF
        eState := eDone;                              // 转完成态发单拍脉冲 / To done for one-scan pulse
        bBusy  := TRUE;                               // 计算当拍置忙（下拍由完成态清）/ Busy during compute scan
    END_IF
END_IF

// ---- 段 5｜故障态输出冻结回放（保持末次有效值，禁零值覆盖）----------------------
IF eState = eFault THEN
    bBusy    := FALSE;                                // 故障态清忙 / Clear busy in fault
    bDone    := FALSE;                                // 故障态不置完成 / Never done in fault
    bError   := TRUE;                                 // 故障标志保持 / Fault flag held
    uErrorId := uCodeLatch;                           // 故障码锁存回放 / Latched fault code replayed
END_IF

// ---- 段 6｜待机态默认清零（R27 输出保持语义：非保持量逐拍重算）------------------
IF eState = eIdle THEN
    bBusy  := FALSE;                                  // 待机清忙 / Idle clears busy
    bDone  := FALSE;                                  // 待机清完成脉冲 / Idle clears done pulse
    IF uErrorId = 16#0003_00F7 THEN
        uErrorId := 16#0000_0000;                     // 中止信息码单拍回落 / Abort info code single-scan fallback
    END_IF
END_IF
END_FUNCTION_BLOCK
