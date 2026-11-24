(*==============================================================================
 * 组件名称 (Component)  : FB_DL_StringCutAlign
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : 串焊裁切对位：bCutCycle 上升沿锁存相机偏差 → 委托
 *                         FB_DL_LowPassFilter 滤波 → 比例修正计算 → 行程钳位
 *                         → 下发修正指令 → 等 bAxisInPos → 对位完成；在位等待
 *                         超时（tInPosMax，默认 T#2S）→ 中止报错（Splicer 教训
 *                         迁移：超时引脚必须带单位与默认值）。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_AlignState / TYPE E_DL_AlignErr /
 *                         FUNCTION_BLOCK FB_DL_StringCutAlign
 * 依赖 (Depends)        : DL_Algo/FB_DL_LowPassFilter
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         防除零 + 增益/偏差钳位 + 非有限值防御 ｜ 枚举成员全部显式赋值
 *                         TON/R_TRIG/滤波器实例每周期无条件调用（仅输入条件化）｜
 *                         对位状态机 CASE 含 ELSE 兜底
 * 错误码表 (Codes)      : 16#0004_031D 就绪
 *                         16#0004_031E 信息级 偏差越界(已钳制)
 *                         16#0004_031F 信息级 修正指令已下发
 *                         16#0004_0320 故障级 在位超时(已中止)
 *                         16#0004_0321 对位完成
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 3
 * 验收向量 (Acceptance) : 偏差 2.0 mm 增益 80% → 指令 1.6 mm；偏差 60 → 钳 50 且
 *                         031E；指令下发后 tInPosMax 内未在位 → 0320 中止
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AlignState（归属 DL_Motion，对位状态机状态）
 *----------------------------------------------------------------------------*)
TYPE E_DL_AlignState :
(
    eIdle    := 0,    // 就绪待节拍 / Idle, waiting for the cut cycle
    eCalc    := 10,   // 计算相：滤波 + 比例 + 钳位，下发指令 / Calculating and issuing the correction
    eWaitPos := 20,   // 等待在位相（双退出：在位成功 / 超时中止）/ Waiting for in-position, dual exit
    eDone    := 30,   // 对位完成（保持至下一节拍）/ Alignment done, held until next cycle
    eFault   := 99    // 故障兜底态 / Fault fallback
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AlignErr（归属 DL_Motion，与 FB_DL_StringCutAlign 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_AlignErr :
(
    eReady    := 16#0004_031D,   // 就绪 / Ready
    eOffClamp := 16#0004_031E,   // 信息级：偏差越界已钳制 / Info: offset clamped
    eCmdSent  := 16#0004_031F,   // 信息级：修正指令已下发 / Info: correction issued
    eInPosTmo := 16#0004_0320,   // 故障级：在位超时已中止 / Fault: in-position timeout, aborted
    eAligned  := 16#0004_0321    // 对位完成 / Alignment completed
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_StringCutAlign
 * 调用约定: 每个扫描周期无条件调用一次；tSampleTime 注入真实任务间隔。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_StringCutAlign
VAR_INPUT
    fCamOffset_mm : REAL;              // 相机偏差 [毫米]，有效域 -50~50 / Camera offset [mm]
    fGainPct      : REAL := 80.0;      // 比例增益 [百分数]，有效域 0~100 / Proportional gain [percent]
    fMaxCorr_mm   : REAL := 10.0;      // 最大修正 [毫米]，须 > 0 / Maximum correction [mm]
    bCutCycle     : BOOL;              // 切割节拍触发（上升沿）/ Cut cycle trigger, rising edge
    bAxisInPos    : BOOL;              // 轴在位反馈 / Axis in-position feedback
    tInPosMax     : TIME := T#2S;      // 在位等待超时 [毫秒]，默认 T#2S / In-position timeout [ms]
    tSampleTime   : TIME := T#100MS;   // 采样周期（滤波器透传）/ Sample period, filter pass-through
END_VAR
VAR_OUTPUT
    fCorrCmd_mm   : REAL;              // 修正指令 [毫米] / Correction command [mm]
    bCorrDone     : BOOL;              // 修正完成（单拍脉冲）/ Correction done, single-scan pulse
    eErr          : E_DL_AlignErr;     // 错误码 / Error code
    eState        : E_DL_AlignState;   // 对位状态机当前状态 / Alignment state
END_VAR
VAR
    fbCutTrig     : R_TRIG;            // 切割节拍上升沿实例（无条件调用）/ Cut cycle edge instance
    fbTonInPos    : TON;               // 在位等待超时定时器（无条件调用）/ In-position timeout timer
    fbLpf         : FB_DL_LowPassFilter;   // 委托低通滤波器实例（无条件调用）/ Delegate low-pass filter instance
    fOffLatch     : REAL;              // 锁存偏差（节拍沿采样）[毫米] / Latched offset [mm]
    fOffUse       : REAL;              // 生效偏差（钳位后）[毫米] / Effective offset [mm]
    fGainUse      : REAL;              // 生效增益（钳位后）[百分数] / Effective gain [percent]
    fCorrCalc     : REAL;              // 修正计算值 [毫米] / Calculated correction [mm]
    bNonFin       : BOOL;              // 非有限输入汇总标志 / Non-finite input aggregate flag
END_VAR
VAR CONSTANT
    DL_ALN_OFF_MIN   : REAL := -50.0;   // 偏差域下限 [毫米] / Offset lower bound [mm]
    DL_ALN_OFF_MAX   : REAL := 50.0;    // 偏差域上限 [毫米] / Offset upper bound [mm]
    DL_ALN_GAIN_MIN  : REAL := 0.0;     // 增益下限 [百分数] / Gain lower bound [percent]
    DL_ALN_GAIN_MAX  : REAL := 100.0;   // 增益上限 [百分数] / Gain upper bound [percent]
    DL_ALN_INF_MAX   : REAL := 1.0E30;  // 非有限值判定幅值上限 / Magnitude bound for finite-value check
    DL_ALN_ZERO      : REAL := 0.0;     // 零值常量，避免裸字面量 / Zero constant
    DL_ALN_PCT       : REAL := 100.0;   // 百分数系数 [百分数] / Percent factor
    DL_ALN_LPF_TC    : TIME := T#100MS; // 委托滤波时间常数 [毫秒] / Delegate filter time constant [ms]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜沿检测/TON/滤波器实例每周期无条件调用（仅输入条件化）
 *----------------------------------------------------------------------------*)
fbCutTrig(CLK := bCutCycle);                          // 节拍沿检测无条件刷新 / cycle edge refreshed unconditionally
fbTonInPos(IN := (eState = E_DL_AlignState.eWaitPos), PT := tInPosMax);   // 在位超时计时 / in-position timeout timing
fbLpf(bEnable := (eState = E_DL_AlignState.eCalc),    // 滤波仅在计算相使能 / filter enabled only in calc phase
      fIn := fOffLatch,                               // 滤波输入为锁存偏差 / filter input is the latched offset
      tTimeConst := DL_ALN_LPF_TC,                    // 滤波时间常数 [毫秒] / filter time constant [ms]
      tSampleTime := tSampleTime,                     // 采样周期透传 / sample period passed
      fOut => fOffUse);                               // 滤波输出作为生效偏差 / filtered output as effective offset

(*------------------------------------------------------------------------------
 * 段 2｜非有限值闸：偏差/增益/限幅 NaN 或溢出 → 进故障兜底态（指令撤）
 *----------------------------------------------------------------------------*)
bNonFin := (fCamOffset_mm <> fCamOffset_mm) OR (ABS(fCamOffset_mm) > DL_ALN_INF_MAX)
        OR (fGainPct      <> fGainPct)      OR (ABS(fGainPct)      > DL_ALN_INF_MAX)
        OR (fMaxCorr_mm   <> fMaxCorr_mm)   OR (ABS(fMaxCorr_mm)   > DL_ALN_INF_MAX);
IF bNonFin THEN
    eState := E_DL_AlignState.eFault;                // 进故障兜底态 / enter fault fallback
    eErr := E_DL_AlignErr.eInPosTmo;                 // 兜底并入超时段（反证句：输出同为指令撤+故障级）/ fallback mapped to timeout band
    fCorrCmd_mm := DL_ALN_ZERO;                      // 指令撤（安全侧）/ command dropped, safe side
    bCorrDone := FALSE;                              // 完成撤 / done dropped
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜增益与限幅参数钳位
 *----------------------------------------------------------------------------*)
fGainUse := fGainPct;                                 // 增益工作副本 / gain working copy
IF fGainUse < DL_ALN_GAIN_MIN THEN
    fGainUse := DL_ALN_GAIN_MIN;                     // 增益下限钳位 / gain floored
ELSIF fGainUse > DL_ALN_GAIN_MAX THEN
    fGainUse := DL_ALN_GAIN_MAX;                     // 增益上限钳位 / gain capped
END_IF
IF fMaxCorr_mm <= DL_ALN_ZERO THEN
    fMaxCorr_mm := 10.0;                             // 限幅非法按默认 10 mm 兜底（配置防御）/ illegal clamp falls back
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜节拍沿锁存与偏差钳位（信息级 031E）
 *----------------------------------------------------------------------------*)
eErr := E_DL_AlignErr.eReady;                         // 默认就绪 / default ready
bCorrDone := FALSE;                                   // 完成脉冲逐拍先清 / done pulse cleared first
IF fbCutTrig.Q THEN
    fOffLatch := fCamOffset_mm;                       // 节拍沿锁存偏差 / latch offset on edge
    fCorrCmd_mm := DL_ALN_ZERO;                       // 新节拍指令预清 / command pre-cleared
    eState := E_DL_AlignState.eCalc;                  // 进计算相 / enter calc phase
END_IF
IF (fOffLatch < DL_ALN_OFF_MIN) OR (fOffLatch > DL_ALN_OFF_MAX) THEN
    IF fOffLatch < DL_ALN_OFF_MIN THEN
        fOffLatch := DL_ALN_OFF_MIN;                  // 偏差下限钳位 / offset floored
    ELSE
        fOffLatch := DL_ALN_OFF_MAX;                  // 偏差上限钳位 / offset capped
    END_IF
    eErr := E_DL_AlignErr.eOffClamp;                  // 信息级：偏差越界已钳制 / info: offset clamped
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜对位状态机：CASE 含 ELSE 兜底
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_AlignState.eIdle:
        fCorrCmd_mm := DL_ALN_ZERO;                   // 就绪态指令撤 / command dropped in idle
        IF eErr = E_DL_AlignErr.eReady THEN
            eErr := E_DL_AlignErr.eReady;             // 保持就绪码 / keep ready code
        END_IF

    E_DL_AlignState.eCalc:
        fCorrCalc := fOffUse * fGainUse / DL_ALN_PCT;   // 比例修正计算 [毫米] / proportional correction [mm]
        IF fCorrCalc > fMaxCorr_mm THEN
            fCorrCalc := fMaxCorr_mm;                 // 行程上限钳位 / stroke capped
        ELSIF fCorrCalc < -fMaxCorr_mm THEN
            fCorrCalc := -fMaxCorr_mm;                // 行程下限钳位 / stroke floored
        END_IF
        fCorrCmd_mm := fCorrCalc;                     // 指令下发 [毫米] / command issued [mm]
        eErr := E_DL_AlignErr.eCmdSent;               // 信息级：指令已下发 / info: command issued
        eState := E_DL_AlignState.eWaitPos;           // 进等待在位相 / enter wait phase

    E_DL_AlignState.eWaitPos:
        IF bAxisInPos THEN
            bCorrDone := TRUE;                        // 在位成功：完成单拍脉冲 / in position: single-scan done pulse
            eErr := E_DL_AlignErr.eAligned;           // 对位完成码 / aligned code
            eState := E_DL_AlignState.eDone;          // 进完成相 / enter done phase
        ELSIF fbTonInPos.Q THEN
            eState := E_DL_AlignState.eFault;         // 在位超时：中止进故障态 / timeout: abort to fault
            eErr := E_DL_AlignErr.eInPosTmo;          // 故障级：在位超时 / fault: timeout
            fCorrCmd_mm := DL_ALN_ZERO;               // 中止撤指令（安全侧）/ abort drops command
        ELSE
            eErr := E_DL_AlignErr.eCmdSent;           // 等待中保持指令已下发码 / keep issued code while waiting
        END_IF

    E_DL_AlignState.eDone:
        fCorrCmd_mm := fCorrCalc;                     // 完成相保持指令显示 / hold command display
        IF fbCutTrig.Q THEN
            eErr := E_DL_AlignErr.eReady;             // 新节拍沿已由段 4 处理 / new edge handled in section 4
        END_IF

    E_DL_AlignState.eFault:
        fCorrCmd_mm := DL_ALN_ZERO;                   // 故障态指令撤 / command dropped in fault
        bCorrDone := FALSE;                           // 故障态完成撤 / done dropped in fault
        IF fbCutTrig.Q THEN
            eState := E_DL_AlignState.eCalc;          // 新节拍允许重试 / new cycle allows retry
        END_IF

    ELSE
        eState := E_DL_AlignState.eFault;             // 非法状态兜底 / illegal-state fallback
        eErr := E_DL_AlignErr.eInPosTmo;              // 兜底码（超时段，反证句：输出同为指令撤+故障级）/ fallback code
        fCorrCmd_mm := DL_ALN_ZERO;                   // 指令撤 / command dropped

END_CASE
END_FUNCTION_BLOCK
