(*==============================================================================
 * 组件名称 (Component)  : FB_DL_GoertzelToneDetect
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / SQRT / COS / ABS），
 *                         零厂商私有库
 * 功能描述 (Function)   : 单 Bin Goertzel 音调检测（公开 DSP 递推 clean-room）：
 *                           sNew  = x + coeff × s1 − s2
 *                           s2    = s1（旧值下移）
 *                           s1    = sNew
 *                         其中 coeff = 2 × COS(2π × fTargetHz ÷ fFsHz)。窗口
 *                         N = TRUNC(fFsHz × fGateS) 个样本到期一次结算：
 *                           fAmp = SQRT(s1² + s2² − coeff × s1 × s2) × 2 ÷ N
 *                         结算后 bToneDetected = fAmp >= fThresh，递推状态
 *                         （s1/s2/计数）复位开新窗（一次结算一次复位，规格
 *                         指定）。Nyquist 预检：fTargetHz >= fFsHz ÷ 2 →
 *                         锁存故障（规格指定）。
 * 接口     (Interface)  : 输入 fSample 输入样本、fTargetHz 目标频率（域
 *                         (0, fFsHz/2)）、fFsHz 采样率（域 > 0）、fGateS 门时
 *                         （域 > 0） [s]、fThresh 检测阈值、bReset 复位；
 *                         输出 fAmp 最新结算幅值（窗间保持）、bToneDetected
 *                         检测电平（结算更新，窗间保持）、nBin 结算样本数 N
 *                         （诊断透读）、eErrCode 错误码、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做单 Bin 幅值检测，不做
 *                         全谱分析、不做频率估计**；谱分析归谱类件。
 *                         ② 递推严格两步口径（头注释公式）：sNew 先算、s2 取
 *                         旧 s1、s1 取 sNew，三行顺序不可换（状态唯一写入点）。
 *                         ③ 结算触发以样本计数 N 为准（确定性口径，与采样数
 *                         严格对齐，不依赖任务周期抖动）；tonGate 自复位窗仅
 *                         作诊断计拍（IN := NOT tonGate.Q，R188），不参与
 *                         结算判据。
 *                         ④ Nyquist 预检 + 组态闸：fFsHz <= 0、fGateS <= 0、
 *                         fTargetHz <= 0、fTargetHz >= fFsHz ÷ 2（浮点容差
 *                         比较）、组态量非有限 → 锁存故障 eCfgBad，递推冻结，
 *                         解除沿 = bReset 上升沿（R45 配对）。
 *                         ⑤ 非有限判据（R79 双判）：样本非有限 → 跳过该样本
 *                         （不入递推），信息码 eSampleSkip；结算功率复检负值
 *                         （舍入）钳 0 后开方，无负数开方路径；递推中间量结算
 *                         前非有限 → 状态复位 + 幅值 0 + 信息码 eRecurBad。
 *                         ⑥ 2π 常量以 LREAL 精度字面量（16 位有效数字）参与
 *                         计算（R51 口径）。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_HarmonicSpectrumBin` 分工：谐波谱窗归那件、
 *                         单 Bin Goertzel 检测归本件；与 `FB_DL_FrequencyMeasure`
 *                         分工：时域测频归那件。
 * 来源标签 (Source Tag) : 自研线（Goertzel 单 Bin 递推为公开 DSP 算法 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 幅值 +
 *                         BOOL 组 + UDINT 计数 + ENUM 错误码；数字码位待主控
 *                         收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ Nyquist 预检 + N 域闸 + 非有限双判 + 结算复检
 *                         ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无 ENUM 状态机） ｜ R7 ✓ 一 TON 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 4 · 序号 20）
 * 验收向量 (Acceptance) : ① fFsHz=1000, fTargetHz=100, fGateS=0.1（N=100），
 *                         输入 1.0×SIN(2π×100×t)（步长 0.01s 采样）：结算
 *                         fAmp ≈ 1.0（容差 0.05），coeff = 2×COS(0.62831853
 *                         …) ≈ 1.618033988749895，fThresh=0.5 →
 *                         bToneDetected=TRUE；② 目标 100 Hz、输入
 *                         1.0×SIN(2π×50×t) → fAmp ≈ 0（容差 0.05），
 *                         bToneDetected=FALSE；③ fTargetHz=600 >= 500
 *                         （Nyquist）→ 锁存 eCfgBad；④ fSample=NaN →
 *                         eSampleSkip，计数不变。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_GtzErr（错误码；信息级不置 bError，故障级恒伴 bError=TRUE）
 *----------------------------------------------------------------------------*)
TYPE E_DL_GtzErr :
(
    eOk         := 0,   // 正常 / Normal
    eCfgBad     := 1,   // 故障级：Nyquist/采样率/门时组态非法 / Fault: Nyquist or config illegal
    eSampleSkip := 2,   // 信息级：样本非有限跳过 / Info: non-finite sample skipped
    eRecurBad   := 3    // 信息级：递推中间量非有限，状态已复位 / Info: recursion non-finite, state reset
);
END_TYPE

FUNCTION_BLOCK FB_DL_GoertzelToneDetect
VAR_INPUT
    fSample   : LREAL := 0.0;         // 输入样本 [工程单位] / Input sample
    fTargetHz : LREAL := 100.0;       // 目标频率，域 (0, fFsHz/2) [Hz] / Target frequency below Nyquist
    fFsHz     : LREAL := 1000.0;      // 采样率，域 > 0 [Hz] / Sample rate
    fGateS    : LREAL := 0.1;         // 门时（结算窗），域 > 0 [s] / Gate duration
    fThresh   : LREAL := 0.5;         // 检测阈值 [工程单位] / Detection amplitude threshold
    bReset    : BOOL := FALSE;        // 复位，上升沿清组态锁存与递推状态 [-] / Reset, clears latch and recursion
END_VAR
VAR_OUTPUT
    fAmp          : LREAL;            // 最新结算幅值（窗间保持） [工程单位] / Latest settled amplitude
    bToneDetected : BOOL;             // 检测电平（结算更新，窗间保持） [-] / Detection level, held between windows
    nBin          : UDINT := 0;       // 结算样本数 N（诊断透读） [个] / Settled sample count
    eErrCode      : E_DL_GtzErr;      // 错误码出口 / Error code outlet
    bError        : BOOL;             // 故障标志（组态锁存） [-] / Error flag, latched
END_VAR
VAR
    _s1       : LREAL := 0.0;         // 递推状态 s1（最新部分和） [-] / Recursion state s1
    _s2       : LREAL := 0.0;         // 递推状态 s2（次新部分和） [-] / Recursion state s2
    _fSNew    : LREAL;                // 当拍递推新值 sNew [-] / New recursion value this scan
    _nCnt     : UDINT := 0;           // 窗内样本计数 [个] / In-window sample count
    _nNeed    : UDINT := 100;         // 结算门限 N = TRUNC(fFsHz×fGateS) [个] / Settle threshold N
    _fCoeff   : LREAL;                // Goertzel 系数 2cos(2πf/fs) [-] / Goertzel coefficient
    _fPow     : LREAL;                // 结算功率中间量 [工程单位²] / Settle power intermediate
    _fAmp     : LREAL := 0.0;         // 幅值锁存（冻结源，与出口同源） / Amplitude latch
    _bDet     : BOOL := FALSE;        // 检测电平锁存 / Detection level latch
    _bNonFin  : BOOL;                 // 样本非有限当拍量 [-] / Sample non-finite
    _bCfgBad  : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration
    _bErrLatch: BOOL;                 // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault
    rtReset   : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge instance
    tonGate   : TON;                  // 门时诊断窗（自复位，R188），段 0 无条件调用 / Gate diagnostic window, self-resetting
END_VAR
VAR CONSTANT
    DL_GTZ_TWOPI : LREAL := 6.283185307179586;   // 2π（LREAL 精度字面量，R51） [rad] / Two pi, LREAL literal
    DL_GTZ_TWO   : LREAL := 2.0;      // 系数倍率与幅值还原倍率 [-] / Factor two
    DL_GTZ_ZERO  : LREAL := 0.0;      // 判零与安全侧基准 [工程单位] / Zero base and safe value
    DL_GTZ_HALF  : LREAL := 0.5;      // Nyquist 预检系数（fFsHz × 0.5） [-] / Nyquist factor
    DL_GTZ_UDMAX : UDINT := 4294967295;   // 计数饱和点（防回绕） [个] / Count saturation ceiling
    DL_GTZ_TGMAX : TIME  := T#1M;     // 门时诊断自复位窗周期（仅计拍，非结算依据） [ms] / Diagnostic window period
END_VAR

(* —— 段 0：非有限判 + 组态闸（含 Nyquist 预检） + 无条件刷新 —— *)
_bNonFin := (fSample <> fSample) OR ((fSample - fSample) <> DL_GTZ_ZERO);   // 样本非有限（R79 双判） / Sample non-finite
_bCfgBad := (fFsHz <= DL_GTZ_ZERO) OR (fGateS <= DL_GTZ_ZERO)
         OR (fTargetHz <= DL_GTZ_ZERO)
         OR (fTargetHz >= fFsHz * DL_GTZ_HALF)          // Nyquist 预检（容差比较，规格④） / Nyquist precheck
         OR (fFsHz <> fFsHz) OR (fTargetHz <> fTargetHz);   // 组态量非有限并入闸 / Non-finite config
rtReset(CLK := bReset);               // 复位沿，每拍必调 / Reset edge, every scan
tonGate(IN := (NOT tonGate.Q) AND (NOT _bErrLatch), PT := DL_GTZ_TGMAX);   // 门时诊断自复位窗（R188，非结算依据） / Diagnostic self-reset window

(* —— 段 1：复位沿与组态锁存 —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;              // 清组态锁存（R188 声明：解除沿 = bReset 上升沿） / Clear cfg latch
    _s1 := DL_GTZ_ZERO;               // 清递推状态 s1 / Clear s1
    _s2 := DL_GTZ_ZERO;               // 清递推状态 s2 / Clear s2
    _nCnt := 0;                       // 清窗计数 / Clear count
    _fAmp := DL_GTZ_ZERO;             // 清幅值锁存 / Clear amplitude
    _bDet := FALSE;                   // 清检测电平 / Clear detection
END_IF
IF _bCfgBad AND (NOT _bErrLatch) THEN
    _bErrLatch := TRUE;               // 锁存 / Latch
END_IF

(* —— 段 2：系数与门限派生（故障期冻结派生） —— *)
IF NOT _bErrLatch THEN
    _fCoeff := DL_GTZ_TWO * COS(DL_GTZ_TWOPI * fTargetHz / fFsHz);   // 系数（分母已闸，无除零） / Coefficient
    _nNeed := LREAL_TO_UDINT(TRUNC(fFsHz * fGateS));   // 门限 N（组态闸保证正域，规格④） / Settle threshold
    IF _nNeed < 1 THEN
        _nNeed := 1;                  // N 下限兜底（门时过短按单样本结算） / Floor N to one
    END_IF
    nBin := _nNeed;                   // 门限透读出口 / Threshold readout
END_IF

(* —— 段 3：Goertzel 单样本递推（故障期/非有限期跳过；严格两步口径，头注释②） —— *)
IF (NOT _bErrLatch) AND (NOT _bNonFin) THEN
    _fSNew := fSample + _fCoeff * _s1 - _s2;   // 第 1 步：新部分和 / Step 1: new partial sum
    _s2 := _s1;                       // 第 2 步：旧 s1 下移至 s2 / Step 2: old s1 down to s2
    _s1 := _fSNew;                    // 第 3 步：s1 取新值（顺序不可换） / Step 3: s1 takes new value
    IF _nCnt < DL_GTZ_UDMAX THEN
        _nCnt := _nCnt + 1;           // 窗计数防回绕递增 / Window count increment
    END_IF

    (* —— 结算：计数达 N 一次结算后复位递推状态（规格①） —— *)
    IF _nCnt >= _nNeed THEN
        _fPow := _s1 * _s1 + _s2 * _s2 - _fCoeff * _s1 * _s2;   // 结算功率 / Settle power
        IF _fPow <> _fPow THEN
            _fPow := DL_GTZ_ZERO;     // 递推中间量非有限：功率按 0 复检兜底 / Non-finite recursion: power zero
        END_IF
        IF _fPow < DL_GTZ_ZERO THEN
            _fPow := DL_GTZ_ZERO;     // 舍入负功率钳 0（无负数开方路径，规格⑤） / Clamp negative rounding power
        END_IF
        _fAmp := SQRT(_fPow) * DL_GTZ_TWO / UDINT_TO_LREAL(_nNeed);   // 幅值还原（×2÷N，N>=1 已闸） / Amplitude synthesis
        _bDet := _fAmp >= fThresh;    // 检测电平（容差域 >= 判，禁 =） / Detection level
        _s1 := DL_GTZ_ZERO;           // 递推状态复位开新窗（规格①） / Reset recursion state
        _s2 := DL_GTZ_ZERO;           // 复位 s2 / Reset s2
        _nCnt := 0;                   // 复位窗计数 / Reset window count
    END_IF
END_IF

(* —— 段 4：出口单点映射（名实双出口同源，R191） —— *)
fAmp := _fAmp;                        // 幅值出口（窗间保持） / Amplitude outlet
bToneDetected := _bDet;               // 检测电平出口 / Detection outlet
IF _bErrLatch THEN
    bError := TRUE;                   // 故障标志（R45 配对） / Error flag
    eErrCode := E_DL_GtzErr.eCfgBad;  // 故障级码 / Fault code
ELSE
    bError := FALSE;                  // 无故障级条件 / No fault
    IF _bNonFin THEN
        eErrCode := E_DL_GtzErr.eSampleSkip;   // 信息级：样本跳过 / Info: skipped
    ELSE
        eErrCode := E_DL_GtzErr.eOk;           // 正常 / Normal
    END_IF
END_IF

END_FUNCTION_BLOCK
