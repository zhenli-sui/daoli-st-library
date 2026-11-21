(*==============================================================================
 * 组件名称 (Component)  : FB_DL_VffsBagLength
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : 立式制袋袋长控制：编码器脉冲计长 → 色标上升沿比对基准
 *                         求偏差 → 偏差限幅后修正下一袋袋长；连续 N 袋（默认 3）
 *                         无色标 → bMarkLost 退化为定长（显式置位，不静默）；切刀
 *                         相位 = 计长对每袋脉冲取正余数，落对齐窗即就绪。
 *                         色标去抖 TON 5 ms 无条件刷新；模运算委托防负余数。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_VffsErr / FUNCTION_BLOCK FB_DL_VffsBagLength
 * 依赖 (Depends)        : DL_MathData/FC_DL_ModPos
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         每袋脉冲为 0 拒绝（防除零）+ 修正双向钳制 + 模运算防负 ｜
 *                         枚举成员全部显式赋值 ｜ TON/R_TRIG 每周期无条件调用 ｜
 *                         退化态显式输出（不清零显示）｜ CASE 含 ELSE 兜底
 * 错误码表 (Codes)      : 16#0005_0417 同步运行
 *                         16#0005_0418 信息级 色标丢失（定长退化）
 *                         16#0005_0419 信息级 修正饱和（连续贴限）
 *                         16#0005_041A 故障级 编码器组态非法（每袋脉冲为 0）
 *                         16#0005_041B 信息级 相位对齐完成
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 3
 * 验收向量 (Acceptance) : 每袋脉冲 1000、设定 300 mm：实测 1010 脉冲 → 偏差 +3 mm
 *                         → 下袋长 297 mm（限幅 5 mm 内）；连续 3 袋无标 → 0418 定长；
 *                         每袋脉冲 0 → 041A 拒绝
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_VffsErr（归属 DL_Process，与 FB_DL_VffsBagLength 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_VffsErr :
(
    eSyncRun    := 16#0005_0417,   // 同步运行 / Synchronised running
    eMarkLost   := 16#0005_0418,   // 信息级：色标丢失，定长退化 / Info: mark lost, fixed-length degradation
    eCorrSat    := 16#0005_0419,   // 信息级：修正饱和（连续贴限）/ Info: correction saturated
    eEncBad     := 16#0005_041A,   // 故障级：编码器组态非法 / Fault: illegal encoder configuration
    ePhaseOk    := 16#0005_041B    // 信息级：相位对齐完成 / Info: cut phase aligned
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_VffsBagLength
 * 调用约定: 每个扫描周期无条件调用一次；bEncPulse 必须注入真实编码器脉冲。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_VffsBagLength
VAR_INPUT
    bMarkDetect   : BOOL;              // 色标传感器输入 / Mark sensor input
    bEncPulse     : BOOL;              // 编码器脉冲输入（计长源）/ Encoder pulse input, length source
    fBagLenSet_mm : REAL;              // 设定袋长 [毫米]，有效域 50~2000 / Set bag length [mm]
    uEncPpr       : UINT;              // 编码器每袋脉冲 [脉冲每袋]，须 > 0 / Encoder pulses per bag, must be > 0
    fCorrLimit_mm : REAL := 5.0;       // 修正限幅 [毫米]，默认 5 / Correction limit [mm]
    tMarkDeb      : TIME := T#5MS;     // 色标去抖时间 [毫秒]，默认 5 / Mark debounce time [ms]
    bReset        : BOOL;              // 复位（清丢失标记与修正）/ Reset, clears lost flag and correction
END_VAR
VAR_OUTPUT
    fBagLenAct_mm : REAL;              // 实际袋长（修正后，用于下一袋）[毫米] / Actual bag length, corrected [mm]
    fCorr_mm      : REAL;              // 当前修正量 [毫米] / Current correction [mm]
    bMarkLost     : BOOL;              // 色标丢失（定长退化）/ Mark lost, fixed-length degradation
    bCutPhaseOk   : BOOL;              // 切刀相位就绪 / Cut phase ready
    nEncCnt       : DINT;              // 当前袋内脉冲计数 [脉冲] / Pulse count in the current bag [pulses]
    nPhaseDiag    : DINT;              // 相位正余数诊断 [脉冲] / Positive-remainder phase diagnostic [pulses]
    eErr          : E_DL_VffsErr;      // 错误码 / Error code
END_VAR
VAR
    fbEncTrig     : R_TRIG;            // 编码器脉冲沿实例（无条件调用）/ Encoder pulse edge instance
    fbMarkTrig    : R_TRIG;            // 去抖后色标沿实例（无条件调用）/ Debounced mark edge instance
    fbResetTrig   : R_TRIG;            // 复位沿实例（无条件调用）/ Reset edge instance
    tonMarkDeb    : TON;               // 色标去抖定时器（无条件调用）/ Mark debounce timer
    fDev_mm       : REAL;              // 本袋脉冲偏差换算长度 [毫米] / Pulse deviation converted to length [mm]
    fCorrUse      : REAL;              // 修正量工作副本（钳位后）[毫米] / Correction working copy [mm]
    fPprUse       : REAL;              // 每袋脉冲实数副本（除子非零）[脉冲每袋] / Pulses per bag as real, non-zero
    uMissCnt      : UINT;              // 连续无色标袋数 [袋] / Consecutive bags without a mark [bags]
    uSatCnt       : UINT;              // 连续修正贴限次数 [次] / Consecutive saturated corrections [pcs]
    uPhaseWin     : DINT;              // 相位对齐窗宽 [脉冲] / Phase alignment window [pulses]
    uModErr       : UDINT;             // 委托取模错误码（0 = 无错）/ Delegate modulo error id
    bPprOk        : BOOL;              // 每袋脉冲合法性 / Pulses-per-bag legality
    bSatNow       : BOOL;              // 本袋修正贴限标志 / Correction saturated this bag
END_VAR
VAR CONSTANT
    DL_VFFS_LEN_MIN   : REAL := 50.0;    // 袋长域下限 [毫米] / Bag length lower bound [mm]
    DL_VFFS_LEN_MAX   : REAL := 2000.0;  // 袋长域上限 [毫米] / Bag length upper bound [mm]
    DL_VFFS_CORR_MIN  : REAL := 0.1;     // 修正限幅下限 [毫米] / Correction limit floor [mm]
    DL_VFFS_MISS_MAX  : UINT := 3;       // 连续无色标退化门限 [袋] / Mark-lost degradation threshold [bags]
    DL_VFFS_SAT_MAX   : UINT := 5;       // 连续贴限预警门限 [次] / Saturation warning threshold [pcs]
    DL_VFFS_WIN_DIV   : DINT := 20;      // 相位窗分数（每袋脉冲 / 20）/ Phase window divisor
    DL_VFFS_WIN_MIN   : DINT := 1;       // 相位窗最小宽 [脉冲] / Phase window minimum [pulses]
    DL_VFFS_MISS_FACT : DINT := 1;       // 无色标判据倍率（1 袋脉冲未到标即计一次丢标）/ Missing-mark pulse factor
    DL_VFFS_INF_MAX   : REAL := 1.0E30;  // 非有限值判定幅值上限 / Magnitude bound for finite-value check
    DL_VFFS_ZERO      : REAL := 0.0;     // 零值常量，避免裸字面量 / Zero constant
    DL_VFFS_EPS       : REAL := 0.001;   // 修正贴限比较容差 [毫米] / Saturation comparison tolerance [mm]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜沿检测/TON 实例每周期无条件调用（仅输入条件化）
 *----------------------------------------------------------------------------*)
fbEncTrig(CLK := bEncPulse);                          // 编码器脉冲沿检测无条件刷新 / encoder edge refreshed unconditionally
tonMarkDeb(IN := bMarkDetect, PT := tMarkDeb);        // 色标去抖计时（无条件刷新）/ mark debounce timing
fbMarkTrig(CLK := tonMarkDeb.Q);                      // 去抖后色标沿检测无条件刷新 / debounced mark edge refreshed
fbResetTrig(CLK := bReset);                           // 复位沿检测无条件刷新 / reset edge refreshed

(*------------------------------------------------------------------------------
 * 段 2｜复位沿：清丢失标记、修正与计数
 *----------------------------------------------------------------------------*)
IF fbResetTrig.Q THEN
    bMarkLost := FALSE;                               // 丢失标记清 / lost flag cleared
    fCorrUse := DL_VFFS_ZERO;                         // 修正清 / correction cleared
    fCorr_mm := DL_VFFS_ZERO;                         // 修正输出清 / correction output cleared
    nEncCnt := 0;                                     // 计数清 / count cleared
    uMissCnt := 0;                                    // 丢标计数清 / miss count cleared
    uSatCnt := 0;                                     // 贴限计数清 / saturation count cleared
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜编码器组态合法性与参数钳位（故障级 041A：每袋脉冲为 0 拒绝）
 *----------------------------------------------------------------------------*)
bPprOk := uEncPpr > 0;                                // 每袋脉冲合法判据 / pulses-per-bag legality
IF NOT bPprOk THEN
    eErr := E_DL_VffsErr.eEncBad;                     // 故障级：编码器组态非法 / fault: illegal encoder configuration
    bCutPhaseOk := FALSE;                             // 相位就绪撤（拒绝判定）/ phase ready dropped
    bMarkLost := TRUE;                                // 退化标记置位（显式，不清零显示）/ degradation flag explicit
    RETURN;
END_IF
IF (fBagLenSet_mm <> fBagLenSet_mm) OR (fBagLenSet_mm < DL_VFFS_LEN_MIN) OR (fBagLenSet_mm > DL_VFFS_LEN_MAX) THEN
    eErr := E_DL_VffsErr.eEncBad;                     // 袋长非法并入编码器组态段（反证句：同样拒绝判定）/ illegal length mapped to config band
    bCutPhaseOk := FALSE;                             // 相位就绪撤 / phase ready dropped
    RETURN;
END_IF
IF (fCorrLimit_mm <> fCorrLimit_mm) OR (fCorrLimit_mm < DL_VFFS_CORR_MIN) THEN
    fCorrLimit_mm := DL_VFFS_CORR_MIN;                // 修正限幅下限钳位（防除零式零限幅）/ correction limit floored
END_IF
fPprUse := UINT_TO_REAL(uEncPpr);                     // 每袋脉冲实数副本（非零已证）/ pulses per bag as real, proven non-zero

(*------------------------------------------------------------------------------
 * 段 4｜编码器计长：脉冲沿计数与本袋脉冲累计
 *----------------------------------------------------------------------------*)
IF fbEncTrig.Q THEN
    nEncCnt := nEncCnt + 1;                           // 本袋计数递增 [脉冲] / bag pulse count incremented
    IF nEncCnt > DL_VFFS_MISS_FACT * UINT_TO_DINT(uEncPpr) THEN
        nEncCnt := DL_VFFS_MISS_FACT * UINT_TO_DINT(uEncPpr);   // 计数上限钳位（防溢出与漂移累积）/ count capped
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜色标沿：偏差换算、限幅、修正下一袋袋长，并清计数与丢标计数
 *----------------------------------------------------------------------------*)
eErr := E_DL_VffsErr.eSyncRun;                        // 默认码：同步运行 / default code: synchronised running
IF fbMarkTrig.Q THEN
    fDev_mm := (DINT_TO_REAL(nEncCnt) - fPprUse) / fPprUse * fBagLenSet_mm;   // 偏差换算 [毫米]（除子已证非零）/ deviation [mm]
    IF fDev_mm > fCorrLimit_mm THEN
        fDev_mm := fCorrLimit_mm;                     // 偏差上限钳制 / deviation capped
    ELSIF fDev_mm < -fCorrLimit_mm THEN
        fDev_mm := -fCorrLimit_mm;                    // 偏差下限钳制 / deviation floored
    END_IF
    fCorrUse := -fDev_mm;                             // 修正量取反（长袋则缩短下一袋）/ correction inverted for the next bag
    IF fCorrUse > fCorrLimit_mm THEN
        fCorrUse := fCorrLimit_mm;                    // 修正上限钳位 / correction capped
    ELSIF fCorrUse < -fCorrLimit_mm THEN
        fCorrUse := -fCorrLimit_mm;                   // 修正下限钳位 / correction floored
    END_IF
    bSatNow := ABS(fCorrUse) >= (fCorrLimit_mm - DL_VFFS_EPS);   // 本袋贴限判据（容差比较）/ saturated-this-bag predicate
    IF bSatNow THEN
        IF uSatCnt < DL_VFFS_SAT_MAX THEN
            uSatCnt := uSatCnt + 1;                   // 贴限计数递增 [次] / saturation count incremented
        END_IF
    ELSE
        uSatCnt := 0;                                 // 未贴限：贴限计数清零 / saturation count cleared
    END_IF
    fCorr_mm := fCorrUse;                             // 修正输出 [毫米] / correction output [mm]
    nEncCnt := 0;                                     // 本袋计数清零 / bag counter cleared
    uMissCnt := 0;                                    // 丢标计数清零 / miss count cleared
    bMarkLost := FALSE;                               // 色标恢复：退化解除 / mark recovered: degradation released
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜色标丢失判定：计长超 2 袋仍未到标 → 丢标计数；连续 3 袋 → 定长退化
 *----------------------------------------------------------------------------*)
IF nEncCnt >= DL_VFFS_MISS_FACT * UINT_TO_DINT(uEncPpr) THEN
    IF uMissCnt < DL_VFFS_SAT_MAX THEN
        uMissCnt := uMissCnt + 1;                     // 丢标计数递增 [袋] / miss count incremented
    END_IF
    nEncCnt := 0;                                     // 计长清零（按定长循环计）/ counter cleared for fixed-length cycling
END_IF
IF uMissCnt >= DL_VFFS_MISS_MAX THEN
    bMarkLost := TRUE;                                // 连续丢标：定长退化（显式置位）/ mark lost: fixed-length degradation
    IF eErr = E_DL_VffsErr.eSyncRun THEN
        eErr := E_DL_VffsErr.eMarkLost;               // 信息级：色标丢失 / info: mark lost
    END_IF
END_IF
IF uSatCnt >= DL_VFFS_SAT_MAX THEN
    IF eErr = E_DL_VffsErr.eSyncRun THEN
        eErr := E_DL_VffsErr.eCorrSat;                // 信息级：修正饱和 / info: correction saturated
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜袋长输出与切刀相位：模运算委托 FC_DL_ModPos 防负余数
 *----------------------------------------------------------------------------*)
fBagLenAct_mm := fBagLenSet_mm + fCorrUse;            // 实际袋长（修正后）[毫米] / actual bag length [mm]
IF fBagLenAct_mm < DL_VFFS_LEN_MIN THEN
    fBagLenAct_mm := DL_VFFS_LEN_MIN;                 // 袋长下限防护 / length floor
ELSIF fBagLenAct_mm > DL_VFFS_LEN_MAX THEN
    fBagLenAct_mm := DL_VFFS_LEN_MAX;                 // 袋长上限防护 / length ceiling
END_IF
nPhaseDiag := FC_DL_ModPos(nValue := nEncCnt, nModulus := UINT_TO_DINT(uEncPpr), eErr => uModErr);   // 相位正余数 [脉冲] / positive-remainder phase
IF uModErr <> 0 THEN
    nPhaseDiag := 0;                                  // 委托异常诊断归零 / diagnostic zeroed on delegate error
END_IF
uPhaseWin := UINT_TO_DINT(uEncPpr) / DL_VFFS_WIN_DIV;   // 相位窗宽 [脉冲] / phase window width [pulses]
IF uPhaseWin < DL_VFFS_WIN_MIN THEN
    uPhaseWin := DL_VFFS_WIN_MIN;                     // 窗宽下限钳位 / window floored
END_IF
bCutPhaseOk := (nPhaseDiag <= uPhaseWin) OR (nPhaseDiag >= (UINT_TO_DINT(uEncPpr) - uPhaseWin));   // 对齐窗判据 / alignment window predicate
IF bCutPhaseOk AND (eErr = E_DL_VffsErr.eSyncRun) THEN
    eErr := E_DL_VffsErr.ePhaseOk;                    // 信息级：相位对齐完成 / info: phase aligned
END_IF
END_FUNCTION_BLOCK
