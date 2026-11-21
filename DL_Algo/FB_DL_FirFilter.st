(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FirFilter
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS），零厂商私有库
 * 功能描述 (Function)   : N 阶 FIR 直接型滤波器：抽头系数 aCoeffs[0..nTaps−1]
 *                         （aCoeffs[0] 对应最新样本，倒序卷积）：
 *                           fFiltered = Σ aCoeffs[k] × aHist[k]，k ∈ [0, nTaps−1]
 *                         样本入栈做循环移位（自深至浅倒序拷贝，防越界覆盖）。
 *                         系数和归一校验：|ΣaCoeffs − 1| < 1E-6，破约 → 锁存
 *                         故障 eCoeffSum（直流增益 ≠ 1 会引入稳态偏差，锁存
 *                         冻结输出）；N 阶钳位 [1,16]，越界钳位并置信息码
 *                         eTapsClamp；非有限样本跳过入栈并置信息码 eSampleSkip。
 * 接口     (Interface)  : 输入 fSample 输入样本、aCoeffs 抽头系数表（定长
 *                         0..15）、nTaps 有效抽头数（钳位 1~16）、bReset 复位；
 *                         输出 fFiltered 滤波输出、fCoeffSum 实测系数和
 *                         （诊断透读）、eErrCode 错误码、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做 FIR 直接型卷积，不做
 *                         系数设计、不做 IIR 递推**；系数设计离线完成。
 *                         ② 移位：FOR 自深至浅倒序拷贝 aHist[i] := aHist[i−1]
 *                         （i ∈ [1, nTaps−1]，界宽 = 钳位后 nTaps，无越界），
 *                         aHist[0] := fSample 唯一写入点。
 *                         ③ 卷积求和界宽 = 钳位后 nTaps；aHist 尾部旧样本
 *                         （从未填充）为初值 0，首窗输出为尾零卷积（头注释
 *                         声明：上电启动期输出按零历史卷积，非异常）。
 *                         ④ 系数和归一校验在每次 nTaps 钳位后按活动抽头重算；
 *                         破约锁存后冻结输出 0（安全侧），解除沿 = bReset
 *                         上升沿（故障级码配对 bError，R45）。
 *                         ⑤ 非有限判据（R79 双判）：样本跳过（不入栈不卷积），
 *                         系数域闸含逐系数非有限判（系数 NaN 直接判归一破约
 *                         路径覆盖，另设显式非有限分支置 eCoeffSum）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_MovingAverage` 分工：等权滑动平均（FIR 特例）
 *                         归那件、任意系数 FIR 归本件；与 `FB_DL_LowPassFilter`
 *                         分工：IIR 单极点归那件。
 * 来源标签 (Source Tag) : 自研线（FIR 直接型为公开 DSP 结构 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 组 +
 *                         ENUM 错误码；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 移位界宽钳位 + 归一校验锁存 + 非有限跳过 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无 ENUM 状态机） ｜ R7 ✓ 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 2 · 序号 9）
 * 验收向量 (Acceptance) : ① nTaps=2，aCoeffs=[0.5, 0.5]（Σ=1.0 过闸）：样本
 *                         序列 10, 20 → 首拍输出 0.5×10+0.5×0 = 5.0（零历史），
 *                         次拍 0.5×20+0.5×10 = 15.0，eOk；② nTaps=20 → 钳位
 *                         16，eTapsClamp；③ aCoeffs=[0.6, 0.5]（Σ=1.1）→
 *                         |1.1−1|=0.1 ≥ 1E-6 → 锁存 eCoeffSum，输出 0；
 *                         ④ 样本 NaN → uSkip 不入栈，eSampleSkip，输出不变。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FirErr（错误码；信息级不置 bError，故障级恒伴 bError=TRUE）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FirErr :
(
    eOk          := 0,   // 正常 / Normal
    eCoeffSum    := 1,   // 故障级：系数和归一破约（|Σ−1| ≥ 1E-6 或含非有限） / Fault: coefficient sum not unity
    eTapsClamp   := 2,   // 信息级：抽头数越界已钳位 [1,16] / Info: tap count clamped
    eSampleSkip  := 3    // 信息级：样本非有限已跳过 / Info: non-finite sample skipped
);
END_TYPE

FUNCTION_BLOCK FB_DL_FirFilter
VAR_INPUT
    fSample : LREAL := 0.0;                    // 输入样本 [工程单位] / Input sample
    aCoeffs : ARRAY[0..15] OF LREAL;           // 抽头系数表（[0] 对应最新样本） [-] / Tap coefficients, newest-first
    nTaps   : UDINT := 4;                      // 有效抽头数，域 [1,16]（越界钳位） [个] / Active tap count
    bReset  : BOOL := FALSE;                   // 复位，上升沿清组态锁存与历史栈 [-] / Reset, rising edge clears latch and history
END_VAR
VAR_OUTPUT
    fFiltered  : LREAL;                        // 滤波输出 [工程单位] / Filtered output
    fCoeffSum  : LREAL;                        // 实测活动抽头系数和（诊断透读） [-] / Measured coefficient sum
    eErrCode   : E_DL_FirErr;                  // 错误码出口 / Error code outlet
    bError     : BOOL;                         // 故障标志（归一破约锁存） [-] / Error flag, latched
END_VAR
VAR
    _aHist    : ARRAY[0..15] OF LREAL;         // 历史样本栈（aHist[0] 最新，初值零历史） / History stack, newest first
    _nTaps    : DINT;                          // 钳位后抽头数 [个] / Clamped tap count
    _fSum     : LREAL;                         // 系数和累计中间量 [-] / Coefficient sum intermediate
    _fAcc     : LREAL;                         // 卷积累计中间量 [工程单位] / Convolution accumulator
    _bClamp   : BOOL;                          // 本拍发生抽头钳位 [-] / Tap clamp this scan
    _bNonFin  : BOOL;                          // 样本非有限当拍量 [-] / Sample non-finite this scan
    _bCoefBad : BOOL;                          // 系数归一破约当拍量 [-] / Coefficient sum violation this scan
    _bErrLatch: BOOL;                          // 归一破约锁存位（解除沿 = bReset 上升沿） / Latched coeff-sum fault
    i         : DINT;                          // 移位/卷积循环索引 / Shift and convolution loop index
    rtReset   : R_TRIG;                        // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_FIR_NMAX   : DINT  := 16;               // 抽头定长上限 [个] / Tap count ceiling
    DL_FIR_NMIN   : DINT  := 1;                // 抽头数下限 [个] / Tap count floor
    DL_FIR_SUMTOL : LREAL := 1.0E-6;           // 系数和归一容差 [-] / Coefficient sum tolerance
    DL_FIR_ONE    : LREAL := 1.0;              // 归一目标值 [-] / Unity target
    DL_FIR_ZERO   : LREAL := 0.0;              // 判零与安全侧基准 / Zero base and safe value
END_VAR

(* —— 段 0：抽头钳位 + 非有限判 + 沿刷新 —— *)
_bClamp := FALSE;                              // 钳位量预清 / Clamp preset
_nTaps := UDINT_TO_DINT(nTaps);                // 抽头数转 DINT（越界由下步钳位） / Convert tap count
IF _nTaps > DL_FIR_NMAX THEN
    _nTaps := DL_FIR_NMAX;                     // 上越界钳 16 / Clamp high
    _bClamp := TRUE;                           // 记钳位 / Mark clamp
END_IF
IF _nTaps < DL_FIR_NMIN THEN
    _nTaps := DL_FIR_NMIN;                     // 下越界钳 1 / Clamp low
    _bClamp := TRUE;                           // 记钳位 / Mark clamp
END_IF
_bNonFin := (fSample <> fSample) OR ((fSample - fSample) <> DL_FIR_ZERO);   // 样本非有限（R79 双判） / Sample non-finite
rtReset(CLK := bReset);                        // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿（清锁存与历史栈） —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;                       // 清归一破约锁存（R188 声明：解除沿 = bReset 上升沿） / Clear latch
    FOR i := 0 TO (DL_FIR_NMAX - 1) DO
        _aHist[i] := DL_FIR_ZERO;              // 清历史栈（零历史重启） / Clear history stack
    END_FOR
END_IF

(* —— 段 2：系数和归一校验（按钳位后活动抽头重算；含系数非有限判） —— *)
_fSum := DL_FIR_ZERO;                          // 系数和起步 0 / Sum start zero
FOR i := 0 TO (_nTaps - 1) DO
    _fSum := _fSum + aCoeffs[i];               // 活动抽头逐项累计 / Sum active taps
END_FOR
fCoeffSum := _fSum;                            // 透读出口 / Readout outlet
IF (_fSum <> _fSum) OR ((_fSum - _fSum) <> DL_FIR_ZERO)
   OR (ABS(_fSum - DL_FIR_ONE) >= DL_FIR_SUMTOL) THEN
    _bCoefBad := TRUE;                         // 归一破约（含系数 NaN 令和失效） / Sum violation
ELSE
    _bCoefBad := FALSE;                        // 过闸 / Pass
END_IF
IF _bCoefBad AND (NOT _bErrLatch) THEN
    _bErrLatch := TRUE;                        // 锁存（R188） / Latch
END_IF

(* —— 段 3：样本入栈（循环移位倒序拷贝，防越界；故障期/非有限期不入栈） —— *)
IF (NOT _bErrLatch) AND (NOT _bNonFin) THEN
    FOR i := (_nTaps - 1) TO DL_FIR_NMIN BY -1 DO
        _aHist[i] := _aHist[i - 1];            // 倒序拷贝（自深至浅，界宽=nTaps） / Shift down, newest-first
    END_FOR
    _aHist[0] := fSample;                      // 最新样本入栈（唯一写入点） / Push newest sample
END_IF

(* —— 段 4：卷积输出（故障安全侧 0；正常域按活动抽头求和） —— *)
IF _bErrLatch THEN
    fFiltered := DL_FIR_ZERO;                  // 归一破约冻结输出 0（安全侧，头注释④） / Frozen zero output
ELSE
    _fAcc := DL_FIR_ZERO;                      // 卷积累计起步 0 / Accumulator start
    FOR i := 0 TO (_nTaps - 1) DO
        _fAcc := _fAcc + aCoeffs[i] * _aHist[i];   // 倒序卷积逐项 / Tap-wise convolution
    END_FOR
    fFiltered := _fAcc;                        // 滤波输出 / Filtered outlet
END_IF

(* —— 段 5：出口单点映射（错误码归约，R191） —— *)
IF _bErrLatch THEN
    bError := TRUE;                            // 故障标志（R45 配对） / Error flag
    eErrCode := E_DL_FirErr.eCoeffSum;         // 故障级码 / Fault code
ELSE
    bError := FALSE;                           // 无故障级条件 / No fault
    IF _bNonFin THEN
        eErrCode := E_DL_FirErr.eSampleSkip;   // 信息级：样本跳过 / Info: skipped
    ELSIF _bClamp THEN
        eErrCode := E_DL_FirErr.eTapsClamp;    // 信息级：抽头钳位 / Info: clamped
    ELSE
        eErrCode := E_DL_FirErr.eOk;           // 正常 / Normal
    END_IF
END_IF

END_FUNCTION_BLOCK
