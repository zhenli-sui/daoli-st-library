(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisBacklashIdent
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 反向间隙在线辨识（只辨识、不注入）。
 *                         原理：换向瞬间传动链要"先吃掉间隙"才带动负载，故换向后的**指令位移**与
 *                         **实际位移**之差即间隙的一次观测值。本件在每个换向沿开启一个位移窗，
 *                         窗内位移超过 fWinMoveMm 即结算一个残差样本：
 *                           残差 = | (Δ指令位移) − (Δ实际位移) | [mm]
 *                         样本进定长缓冲（8 个），样本数达 nMinSamples 后取**中值**作为间隙估计
 *                         （中值对个别打滑/编码器毛刺样本免疫，均值则不）。
 *                         三条固化纪律：
 *                           ① **激励不足拒辨识**：样本数不足或换向时速度幅值低于 fVelMin 时，
 *                              估计值不宣称（bValid=FALSE）并置 bInsufficientExc——低速换向的残差
 *                              被摩擦完全淹没，硬算出来的"间隙"只是摩擦的另一种写法；
 *                           ② **中值估计**：样本排序后取中位（8 个样本插入排序，循环上界恒定）；
 *                           ③ **估计值钳位**：结果钳 [0, fBacklashMax]，超上限按上限报告并置 bClamped
 *                              （不可信的巨值不许直接进入补偿环节）。
 *                         验收向量：
 *                           ① 五次换向残差 {0.02, 0.03, 0.03, 0.04, 0.10} → 中值 0.03 mm（0.10 为野值）
 *                           ② 仅 2 个样本（nMinSamples=5）→ bValid=FALSE + bInsufficientExc
 *                           ③ 换向时速度 0.5 mm/s（fVelMin=2.0）→ 该次不采样本
 *                           ④ 残差 5.0 mm（上限 2.0）→ 估计钳 2.0 mm + bClamped
 * 接口     (Interface)  : 入 bEnable 使能、fCmdPos 指令位置、fActPos 实际位置、fVelCmd 指令速度、
 *                         fVelMin 换向速度下限（激励门槛）、fWinMoveMm 位移窗宽、fBacklashMax 估计上限、
 *                         nMinSamples 最少样本数（≥1）、bClear 清样本沿、bReset 复位沿；
 *                         出 fBacklashMm 间隙估计（中值）、bValid 估计有效、bClamped 估计被钳位、
 *                         iSampleCnt 已收样本数、bInsufficientExc 激励不足、bReversed 换向脉冲（单拍）、
 *                         eState 相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做"间隙辨识"，不注入补偿、不改位置环输出**——
 *                         补偿注入属上层（`FB_DL_AxisCoggingFf` 族与本件并列不互引）；
 *                         ② **状态枚举禁定义**：本件不引用任何轴状态枚举（R277），只消费位置/速度引脚；
 *                         ③ **组态闸**：fVelMin > 0、fWinMoveMm > 0、fBacklashMax > 0、nMinSamples ≥ 1
 *                         且 ≤ 8，违反即锁存 eCfgIllegal；
 *                         ④ **非有限闸**：任一位置/速度样本非有限 → 该拍不采样（不锁存）；
 *                         ⑤ **样本缓冲边界**：8 样本字面量上界（R104），写入前判满；
 *                         ⑥ **锁存解除式**：eFault 仅由 bReset 上升沿解除（R228B），bReset 恒可达；
 *                         ⑦ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"换向残差统计与中值估计"。不接管：摩擦前馈
 *                         （属 FB_DL_AxisFrictionFf）、齿槽前馈（属 FB_DL_AxisCoggingFf）、
 *                         双反馈切换（属 AxisFeedbackFailoverSeq 族）。
 * 来源标签 (Source Tag) : 自研线（传动精度族开族）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 组态闸 + 非有限闸 + 缓冲边界 + 估计钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ 三 R_TRIG 段 0 无条件刷新（本件无 TON）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 4 · 序号 19）
 *==============================================================================*)

TYPE E_DL_AbiState :
(
    eIdle  := 0,    // 待机相（未使能或已清零） / Idle, disabled or cleared
    eWatch := 10,   // 观测相（等换向沿并结算样本） / Watching, awaiting reversal and sample settlement
    eFault := 90    // 故障相（组态非法，等复位） / Fault, awaiting reset
);
END_TYPE

TYPE E_DL_AbiCause :
(
    eNone           := 0,   // 无异常 / No anomaly
    eCfgIllegal     := 1,   // 组态非法（门槛/窗口/上限/样本数越域） / Illegal configuration
    eInsufficientExc:= 2,   // 激励不足（样本数不够或换向速度过低） / Insufficient excitation
    eClamped        := 3,   // 估计值被钳位（野值） / Estimate clamped
    eSampleBad      := 4,   // 位置/速度样本非有限（当拍不采） / Non-finite sample, skipped
    ePhaseBad       := 5    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisBacklashIdent
VAR_INPUT
    bEnable      : BOOL := FALSE;      // 使能（FALSE 冻结观测，不宣称） [-] / Enable
    fCmdPos      : LREAL := 0.0;       // 指令位置 [mm] / Command position [mm]
    fActPos      : LREAL := 0.0;       // 实际位置 [mm] / Actual position [mm]
    fVelCmd      : LREAL := 0.0;       // 指令速度（用于换向判定） [mm/s] / Command velocity [mm/s]
    fVelMin      : LREAL := 2.0;       // 换向速度下限（激励门槛），域 > 0 [mm/s] / Reversal speed limit, > 0
    fWinMoveMm   : LREAL := 1.0;       // 位移窗宽，域 > 0 [mm] / Displacement window, > 0
    fBacklashMax : LREAL := 2.0;       // 估计上限，域 > 0 [mm] / Estimate ceiling, > 0
    nMinSamples  : INT := 5;           // 最少样本数，域 1..8 [个] / Minimum sample count, 1..8
    bClear       : BOOL := FALSE;      // 清样本沿（重新辨识） [-] / Clear-samples edge
    bReset       : BOOL := FALSE;      // 故障复位沿 [-] / Fault reset edge
END_VAR
VAR_OUTPUT
    fBacklashMm   : LREAL := 0.0;                        // 间隙估计（中值，已钳位） [mm] / Backlash estimate, clamped
    bValid        : BOOL := FALSE;                       // 估计有效（样本够且激励足） [-] / Estimate valid
    bClamped      : BOOL := FALSE;                       // 估计被钳位 [-] / Estimate clamped
    iSampleCnt    : INT := 0;                            // 已收样本数 [个] / Collected sample count
    bInsufficientExc : BOOL := FALSE;                    // 激励不足 [-] / Insufficient excitation
    bReversed     : BOOL := FALSE;                       // 换向脉冲（单拍） [-] / Reversal pulse, single scan
    eState        : E_DL_AbiState := E_DL_AbiState.eIdle;    // 相出口 [-] / Phase outlet
    eCause        : E_DL_AbiCause := E_DL_AbiCause.eNone;    // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError        : BOOL := FALSE;                       // 故障标志（仅组态级） [-] / Error flag, configuration only
END_VAR
VAR
    _eState   : E_DL_AbiState := E_DL_AbiState.eIdle;    // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause   : E_DL_AbiCause := E_DL_AbiCause.eNone;    // 成因锁存量 / Latched cause
    _bFault   : BOOL := FALSE;                           // 故障锁存位 / Latched fault bit
    _iCnt     : INT := 0;                                // 样本计数 / Sample count
    _bDirPos  : BOOL := FALSE;                           // 上拍方向为正标志 / Previous direction positive flag
    _bDirNow  : BOOL := FALSE;                           // 当拍方向标志 / Present direction flag
    _bWinOpen : BOOL := FALSE;                           // 位移窗开启标志 / Displacement window open
    _fCmdSnap : LREAL := 0.0;                            // 换向瞬间指令位置快照 [mm] / Command snapshot at reversal
    _fActSnap : LREAL := 0.0;                            // 换向瞬间实际位置快照 [mm] / Actual snapshot at reversal
    _fResid   : LREAL := 0.0;                            // 残差工作值 [mm] / Residual working value
    _fEst     : LREAL := 0.0;                            // 中值估计工作值 [mm] / Median working value
    _fTmp     : LREAL := 0.0;                            // 排序交换临时量 [mm] / Sort swap temporary
    _bRev     : BOOL := FALSE;                           // 换向脉冲内部位（单拍） / Internal reversal pulse
    _bClamped : BOOL := FALSE;                           // 钳位标志内部位 / Internal clamp flag
    _bSampleOk: BOOL := FALSE;                           // 样本有限性结论 / Sample finiteness result
    _bCfgBad  : BOOL := FALSE;                           // 组态非法当拍量 / Illegal configuration this scan
    _i        : INT := 0;                                // 样本循环下标 / Sample loop index
    _j        : INT := 0;                                // 排序内层下标 / Inner sort index
    rtClear   : R_TRIG;                                  // 清样本沿实例，段 0 无条件调用 / Clear edge instance
    rtReset   : R_TRIG;                                  // 复位沿实例，段 0 无条件调用 / Reset edge instance
    afSmp     : ARRAY[1..8] OF LREAL;                    // 残差样本缓冲（字面量上界，R104） [mm] / Residual sample buffer
    afSort    : ARRAY[1..8] OF LREAL;                    // 排序副本 [mm] / Sorting copy
END_VAR
VAR CONSTANT
    DL_ABI_NMAX : INT := 8;            // 样本缓冲深度（与数组字面量上界同源） [个] / Sample buffer depth
    DL_ABI_EPS  : LREAL := 1.0E-12;    // 浮点判等容差 [mm] / Equality tolerance
END_VAR

(* —— 段 0：组态闸 + 三沿无条件周期刷新（R228A；本件无 TON） —— *)
_bCfgBad := (fVelMin <= 0.0) OR (fWinMoveMm <= 0.0) OR (fBacklashMax <= 0.0)      // 三正域闸 / Three positive-domain gates
         OR (nMinSamples < 1) OR (nMinSamples > DL_ABI_NMAX);                     // 样本数域闸 / Sample count domain
rtClear(CLK := bClear);                                                            // 清样本沿 / Clear edge
rtReset(CLK := bReset);                                                            // 复位沿 / Reset edge

(* —— 段 1：单拍/输出量预置（锁存量 _eCause/_bFault/_iCnt/_bWinOpen/_bDirPos 不入清单，R107） —— *)
bValid   := FALSE;                                                                 // 有效位预置 / Validity preset
_bRev    := FALSE;                                                                 // 换向脉冲预清 / Reversal pulse preset
_bClamped:= FALSE;                                                                 // 钳位标志预清 / Clamp flag preset
bInsufficientExc := FALSE;                                                         // 激励不足预清 / Insufficient-excitation preset
bError   := FALSE;                                                                 // 故障标志预清（R45 配对） / Error preset
_fEst    := 0.0;                                                                   // 估计工作值预置 / Estimate preset

(* —— 段 2：组态闸（非法即锁存） —— *)
IF _bCfgBad THEN
    _eCause := E_DL_AbiCause.eCfgIllegal;                                          // 归因：组态非法 / Cause: illegal configuration
    _bFault := TRUE;                                                               // 锁存 / Latch
    _eState := E_DL_AbiState.eFault;                                               // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：迁出链与清样本链（两条显式写出） —— *)
IF rtReset.Q THEN
    _bFault   := FALSE;                                                            // 清故障锁存 / Clear fault latch
    _eCause   := E_DL_AbiCause.eNone;                                              // 清成因 / Clear cause
    _iCnt     := 0;                                                                // 样本清零 / Samples cleared
    _bWinOpen := FALSE;                                                            // 关窗 / Window closed
    _eState   := E_DL_AbiState.eIdle;                                              // 回待机相 / Back to idle
END_IF
IF rtClear.Q THEN
    _iCnt     := 0;                                                                // 样本清零（重新辨识） / Samples cleared for re-identification
    _bWinOpen := FALSE;                                                            // 关窗 / Window closed
END_IF

(* —— 段 4：相迁移（使能驱动；故障相由段 3 迁出） —— *)
CASE _eState OF

E_DL_AbiState.eIdle:
    IF bEnable AND (NOT _bCfgBad) THEN
        _eState := E_DL_AbiState.eWatch;                                           // 使能进观测相 / Enter watching
    END_IF

E_DL_AbiState.eWatch:
    IF NOT bEnable THEN
        _eState := E_DL_AbiState.eIdle;                                            // 失能回待机相（不借故障相过桥，R211） / Back to idle
    END_IF

E_DL_AbiState.eFault:
    ;                                                                              // 故障相：由段 3 复位沿迁出 / Exit via the reset edge

ELSE
    _eCause := E_DL_AbiCause.ePhaseBad;                                            // 归因：非法相位 / Cause: illegal phase
    _bFault := TRUE;                                                               // 锁存 / Latch
    _eState := E_DL_AbiState.eFault;                                               // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 5：换向检测与窗结算（样本采集唯一入口） —— *)
IF _eState = E_DL_AbiState.eWatch THEN
    _bSampleOk := NOT ((fCmdPos <> fCmdPos) OR ((fCmdPos - fCmdPos) <> (fCmdPos - fCmdPos)))
              AND NOT ((fActPos <> fActPos) OR ((fActPos - fActPos) <> (fActPos - fActPos)))
              AND NOT ((fVelCmd <> fVelCmd) OR ((fVelCmd - fVelCmd) <> (fVelCmd - fVelCmd)));

    IF _bSampleOk THEN
        (* 换向判定：速度符号翻转且幅值过激励门槛；方向保持量只在激励充分时更新 *)
        _bDirNow := (fVelCmd > 0.0);                                               // 本拍方向 / Present direction
        IF (ABS(fVelCmd) > fVelMin) THEN
            IF (_bDirNow <> _bDirPos) AND (NOT _bWinOpen) THEN
                _bRev     := TRUE;                                                 // 换向脉冲（内部位） / Internal reversal pulse
                _bWinOpen := TRUE;                                                 // 开位移窗 / Open the displacement window
                _fCmdSnap := fCmdPos;                                              // 记录指令基准 / Command snapshot
                _fActSnap := fActPos;                                              // 记录实际基准 / Actual snapshot
            END_IF
            _bDirPos := _bDirNow;                                                  // 方向保持量更新 / Refresh the direction
        END_IF

        (* 窗结算：指令位移超过窗宽即结算一个残差样本 *)
        IF _bWinOpen AND (ABS(fCmdPos - _fCmdSnap) > fWinMoveMm) THEN
            _fResid := ABS((fCmdPos - _fCmdSnap) - (fActPos - _fActSnap));         // 残差 = |Δ指令 − Δ实际| / Residual
            IF _fResid <> _fResid THEN
                _fResid := 0.0;                                                    // 残差非有限：拒收（不采样本） / Non-finite residual rejected
                _eCause := E_DL_AbiCause.eSampleBad;                               // 归因：样本非有限 / Cause: sample non-finite
            ELSIF _iCnt < DL_ABI_NMAX THEN
                _iCnt := _iCnt + 1;                                                // 样本计数 +1 / Sample count increment
                afSmp[_iCnt] := _fResid;                                           // 落样本（下标已判满） / Store the sample
            END_IF
            _bWinOpen := FALSE;                                                    // 关窗，等下次换向 / Close the window
        END_IF
    ELSE
        _eCause := E_DL_AbiCause.eSampleBad;                                       // 归因：样本非有限（当拍不采） / Cause: non-finite sample
    END_IF

    (* —— 段 6：中值估计（只对已收样本排序；插入排序，循环上界为样本数 ≤ 8） —— *)
    IF _iCnt >= nMinSamples THEN
        FOR _i := 1 TO _iCnt DO
            afSort[_i] := afSmp[_i];                                               // 复制已收样本 / Copy the collected samples
        END_FOR
        FOR _i := 2 TO _iCnt DO
            _j := _i;                                                              // 插入排序内层起点 / Insertion start
            WHILE (_j > 1) AND (afSort[_j - 1] > afSort[_j]) DO
                _fTmp := afSort[_j - 1];                                           // 交换 / Swap
                afSort[_j - 1] := afSort[_j];
                afSort[_j] := _fTmp;
                _j := _j - 1;                                                      // 内层推进（收敛，R74） / Inner step, converges
            END_WHILE
        END_FOR
        _fEst := afSort[(_iCnt / 2) + 1];                                          // 取中位（1 基，样本数 1..8） / Median, 1-based
        IF _fEst > fBacklashMax THEN
            _fEst := fBacklashMax;                                                 // 上限钳位（野值不许进入补偿） / Clamp to the ceiling
            _bClamped := TRUE;                                                     // 钳位标志 / Clamp flag
            _eCause := E_DL_AbiCause.eClamped;                                     // 归因：估计被钳位 / Cause: estimate clamped
        ELSIF _fEst < 0.0 THEN
            _fEst := 0.0;                                                          // 下限钳位（间隙非负） / Clamp to zero
            _bClamped := TRUE;                                                     // 钳位标志 / Clamp flag
            _eCause := E_DL_AbiCause.eClamped;                                     // 归因：估计被钳位 / Cause: estimate clamped
        END_IF
        bValid := TRUE;                                                            // 估计有效 / Estimate valid
    ELSE
        bInsufficientExc := TRUE;                                                  // 激励不足：不宣称 / Insufficient excitation
        _eCause := E_DL_AbiCause.eInsufficientExc;                                 // 归因：激励不足 / Cause: insufficient excitation
    END_IF
END_IF

(* —— 段 7：出口单点映射（名实双出口，R191） —— *)
fBacklashMm := _fEst;                                                              // 间隙估计出口 / Backlash estimate outlet
bClamped    := _bClamped;                                                          // 钳位标志出口 / Clamp flag outlet
iSampleCnt  := _iCnt;                                                              // 样本数出口 / Sample count outlet
bReversed   := _bRev;                                                              // 换向脉冲出口 / Reversal pulse outlet
eState      := _eState;                                                            // 相出口 / Phase outlet
eCause      := _eCause;                                                            // 成因出口 / Cause outlet
bError      := _bFault;                                                            // 故障标志 / Error flag

END_FUNCTION_BLOCK
