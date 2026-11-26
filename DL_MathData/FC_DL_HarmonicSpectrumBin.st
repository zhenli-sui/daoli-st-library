(*
  FC_DL_HarmonicSpectrumBin  —  单频点 DFT 幅值·相位提取 / Single-bin DFT magnitude and phase extraction
  分类 Category : DL_MathData
  码位 Code     : 16#05_0_00
  版本 Version  : 1.0.0
  来源标签 Tag  : t2-1-lgf-math
  溯源 Source   : LGF Math 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码行
  功能 Function : 1) Goertzel 递推单频点 DFT，矩形/Hann 双窗，Hann 相干增益 0.5 做幅值修正；
                  2) 相位解卷并给贴轴归属（imag = 0 且 real < 0 归正支，返回域 (-180, 180] 度）；
                  3) 五道边界闸：窗长域 / 采样率 / 奈奎斯特 / 窗内非有限样本 / 幅值分辨力下限。
  边界 Boundary : ① nWindowSize 越 [8, 1023] 判无效置故障码，不进入循环；
                  ② fSampleRateHz <= 0 先判零再除（防除零），判零前先过非有限闸；
                  ③ fTargetFreqHz >= 奈奎斯特判无效，宁可不报也不混叠出假值；
                  ④ 窗内任一 NaN/Inf 整窗无效（自反判 NaN + 差值自减判 Inf 双判）；
                  ⑤ 幅值 < fMagFloor 输出 0 并置信息码，不置 bError。
  依赖 Depends  : FC_DL_NthRoot（开方 nRoot = 2；本件禁内联 SQRT 原语，R140 委托优先）
  纯函数声明    : 本件为纯函数，零内部状态、零跨周期驻留、零 GVL/物理地址引用

  码表 Error codes（本件格 05_0_00，子码步进 +0x10）:
    16#0005_0500 故障级：组态非法（窗长越域 / 采样率 <= 0 / 目标频率 >= 奈奎斯特 / 幅值门限 < 0 / 组态量非有限）
    16#0005_0510 信息级：窗内存在非有限样本整窗无效 / 幅值低于分辨力（不置 bError）

  修订历史 Revision :
    2026-11-18  v1.0.0  R36 首版入库（W1 窗首件）
*)

TYPE E_DL_SpectrumWindow :
(
    eRect := 0,   // 矩形窗，相干增益 1.0（频率分辨率最优，泄漏最大）/ Rectangular window, coherent gain 1.0
    eHann := 1    // Hann 窗，相干增益 0.5（抑制泄漏）/ Hann window, coherent gain 0.5
);
END_TYPE

FUNCTION FC_DL_HarmonicSpectrumBin : BOOL
VAR_INPUT
    afSampleBuffer : ARRAY[0..1023] OF LREAL;                  // 采样窗缓冲区，索引 0 为最早样本 / Sample window buffer, index 0 = oldest sample
    nWindowSize    : UINT := 0;                                // 有效窗长 [样本数]，域 8 ~ 1023 / Effective window length [samples]
    fSampleRateHz  : LREAL := 0.0;                             // 采样率 [Hz]，域 > 0 / Sampling rate [Hz], domain > 0
    fTargetFreqHz  : LREAL := 0.0;                             // 目标提取频率 [Hz]，域 [0, 奈奎斯特) / Target bin frequency [Hz]
    fMagFloor      : LREAL := 1.0E-6;                          // 幅值分辨力下限 [输入物理量单位]，域 >= 0 / Magnitude floor [EU]
    eWindowType    : E_DL_SpectrumWindow := E_DL_SpectrumWindow.eRect; // 窗型选择 / Window type selection
END_VAR
VAR_OUTPUT
    fMagnitude : LREAL;                                        // 峰值幅值输出，物理量单位随输入 [EU] / Peak magnitude [EU]
    fPhaseDeg  : LREAL;                                        // 相位输出 [deg]，域 (-180, 180] / Phase [deg]
    bValid     : BOOL;                                         // 结果有效标志，FALSE 时幅值相位均为 0 / Result valid flag
    bError     : BOOL;                                         // 故障标志，与故障级码配对 / Fault flag paired with fault code
    nErrId     : UDINT;                                        // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    nIdx          : INT;                                       // 样本循环索引 [1] / Sample loop index
    nCount        : INT;                                       // 生效窗长整型副本 [样本数] / Integer copy of window length
    fOmega        : LREAL;                                     // 数字角频率 [rad] / Digital angular frequency [rad]
    fCoeff        : LREAL;                                     // Goertzel 递推系数 2·cos(ω) [1] / Goertzel recursion coefficient
    fS0           : LREAL;                                     // 递推当前拍状态量 [EU] / Recursion state, current
    fS1           : LREAL;                                     // 递推前一拍状态量 [EU] / Recursion state, previous
    fS2           : LREAL;                                     // 递推前二拍状态量 [EU] / Recursion state, two scans back
    fWin          : LREAL;                                     // 当前样本窗权值 [1] / Window weight of current sample
    fCoherentGain : LREAL;                                     // 窗相干增益 [1]，矩形 1.0 / Hann 0.5 / Coherent gain of window
    fSample       : LREAL;                                     // 当前样本值副本 [EU] / Copy of current sample
    fPower        : LREAL;                                     // Goertzel 功率量（未开方）[EU^2] / Goertzel power term
    fMagRaw       : LREAL;                                     // 窗修正前幅值 [EU] / Magnitude before window correction
    fReal         : LREAL;                                     // 相位实部（s1 - s2·cosω）[EU] / Phase real part
    fImag         : LREAL;                                     // 相位虚部（s2·sinω）[EU] / Phase imaginary part
    fPhaseRad     : LREAL;                                     // 相位弧度中间量 [rad] / Phase in radians
    fNyquist      : LREAL;                                     // 奈奎斯特频率 fSampleRateHz / 2 [Hz] / Nyquist frequency [Hz]
    bNonFinite    : BOOL;                                      // 窗内非有限样本标志 / Non-finite sample flag
    bSqrtValid    : BOOL;                                      // 开方委托结果有效标志 / Sqrt delegation valid flag
    fSqrtOut      : LREAL;                                     // 开方委托返回值 [EU] / Sqrt delegation return value
END_VAR
VAR CONSTANT
    DL_WIN_MIN  : UINT  := 8;                      // 窗长下限 [样本数]，低于此值分辨率无工程意义 / Window length lower bound
    DL_WIN_MAX  : UINT  := 1023;                   // 窗长上限 [样本数]，等于缓冲区上界 / Window length upper bound
    DL_TWO_PI   : LREAL := 6.283185307179586477;   // 2π LREAL 精度字面量 [rad] / 2π in LREAL precision
    DL_RAD2DEG  : LREAL := 57.295779513082320877;  // 弧度转度 [deg/rad] / Radian to degree factor
    DL_EPS      : LREAL := 1.0E-12;                // 判零容差 [1] / Zero tolerance
END_VAR

(* —— 段 0：返回值与输出预置安全值（纯函数，无状态刷新） —— *)
FC_DL_HarmonicSpectrumBin := FALSE;   // 返回布尔：FALSE = 本拍无有效结果
fMagnitude   := 0.0;                  // 幅值预置 0 [EU]
fPhaseDeg    := 0.0;                  // 相位预置 0 [deg]
bValid       := FALSE;                // 有效标志预置 FALSE
bError       := FALSE;                // 故障标志预置 FALSE（故障级码赋值后 3 行内置位）
nErrId       := 0;                    // 事件码预置 0
nCount       := UINT_TO_INT(nWindowSize);  // 窗长整型副本 [样本数]
fCoherentGain := 1.0;                 // 相干增益默认矩形窗 [1]
bNonFinite   := FALSE;                // 非有限标志预置 FALSE
fNyquist     := fSampleRateHz * 0.5;  // 奈奎斯特频率 [Hz]，采样率闸命中前仅作占位

(* —— 段 1：组态域闸（R151 覆盖全部参与换算的引脚） —— *)
IF (fSampleRateHz <> fSampleRateHz) OR ((fSampleRateHz - fSampleRateHz) <> (fSampleRateHz - fSampleRateHz)) THEN
    nErrId := 16#0005_0500;           // 故障级：采样率非有限（NaN 自反 / Inf 差值自减）
    bError := TRUE;                   // 故障标志置位（R45 配对）
    RETURN;                           // 域闸命中不调内核
END_IF
IF (fTargetFreqHz <> fTargetFreqHz) OR ((fTargetFreqHz - fTargetFreqHz) <> (fTargetFreqHz - fTargetFreqHz)) THEN
    nErrId := 16#0005_0500;           // 故障级：目标频率非有限
    bError := TRUE;                   // 故障标志置位（R45 配对）
    RETURN;                           // 域闸命中不调内核
END_IF
IF (fMagFloor <> fMagFloor) OR (fMagFloor < 0.0) THEN
    nErrId := 16#0005_0500;           // 故障级：幅值门限非有限或为负
    bError := TRUE;                   // 故障标志置位（R45 配对）
    RETURN;                           // 域闸命中不调内核
END_IF
IF (nWindowSize < DL_WIN_MIN) OR (nWindowSize > DL_WIN_MAX) THEN
    nErrId := 16#0005_0500;           // 故障级：窗长越 [8, 1023] 域（下界防退化，上界防数组越界）
    bError := TRUE;                   // 故障标志置位（R45 配对）
    RETURN;                           // 不进入循环
END_IF
IF fSampleRateHz <= 0.0 THEN
    nErrId := 16#0005_0500;           // 故障级：采样率 <= 0（除零前置判定）
    bError := TRUE;                   // 故障标志置位（R45 配对）
    RETURN;                           // 域闸命中不调内核
END_IF
IF (fTargetFreqHz < 0.0) OR (fTargetFreqHz >= fNyquist) THEN
    nErrId := 16#0005_0500;           // 故障级：目标频率越 [0, 奈奎斯特) 域，拒绝混叠假值
    bError := TRUE;                   // 故障标志置位（R45 配对）
    RETURN;                           // 域闸命中不调内核
END_IF

(* —— 段 2：内核参数（角频率与递推系数），窗型决定相干增益 —— *)
fOmega := DL_TWO_PI * fTargetFreqHz / fSampleRateHz;   // 数字角频率 [rad]，采样率已证明 > 0
fCoeff := 2.0 * COS(fOmega);                           // 递推系数 [1]
IF eWindowType = E_DL_SpectrumWindow.eHann THEN
    fCoherentGain := 0.5;                              // Hann 窗相干增益 [1]
ELSE
    fCoherentGain := 1.0;                              // 矩形窗（含未知枚举值兜底）相干增益 [1]
END_IF

(* —— 段 3：Goertzel 递推主循环（样本数已钳在数组域内，循环计数器结构上有界） —— *)
fS1 := 0.0;                                            // 递推状态清零
fS2 := 0.0;                                            // 递推状态清零
FOR nIdx := 0 TO (nCount - 1) DO
    fSample := afSampleBuffer[nIdx];                   // 取样本 [EU]
    IF (fSample <> fSample) OR ((fSample - fSample) <> (fSample - fSample)) THEN
        bNonFinite := TRUE;                            // 窗内出现 NaN 或 Inf
    END_IF
    IF eWindowType = E_DL_SpectrumWindow.eHann THEN
        fWin := 0.5 - 0.5 * COS(DL_TWO_PI * INT_TO_LREAL(nIdx) / INT_TO_LREAL(nCount - 1));  // Hann 窗权值 [1]
    ELSE
        fWin := 1.0;                                   // 矩形窗权值 [1]
    END_IF
    fS0 := fWin * fSample + fCoeff * fS1 - fS2;         // 递推当前拍 [EU]
    fS2 := fS1;                                         // 状态后移
    fS1 := fS0;                                         // 状态后移
END_FOR

IF bNonFinite THEN
    nErrId := 16#0005_0510;           // 信息级：窗内非有限样本，整窗无效（信息级不置 bError）
    RETURN;                           // 不出结论
END_IF

(* —— 段 4：功率量 → 幅值（委托 FC_DL_NthRoot 开方，禁内联 SQRT），相位解卷 —— *)
fPower := fS1 * fS1 + fS2 * fS2 - fCoeff * fS1 * fS2;   // Goertzel 功率量 [EU^2]
IF fPower < 0.0 THEN
    fPower := 0.0;                                      // 数值负偏钳零（不动点舍入噪声）
END_IF
fSqrtOut := FC_DL_NthRoot(fValue := fPower, nRoot := 2, bValid => bSqrtValid);  // 委托开方
IF NOT bSqrtValid THEN
    nErrId := 16#0005_0510;           // 信息级：开方委托判无效（功率量非有限）
    RETURN;                           // 不出结论
END_IF
fMagRaw := 2.0 * fSqrtOut / INT_TO_LREAL(nCount);                        // 单边幅值（未做窗修正）[EU]
fMagnitude := fMagRaw / fCoherentGain;                                    // 窗相干增益修正后幅值 [EU]
IF (fMagnitude <> fMagnitude) OR ((fMagnitude - fMagnitude) <> (fMagnitude - fMagnitude)) THEN
    fMagnitude := 0.0;                                                    // 非有限复检兜底
    nErrId := 16#0005_0510;           // 信息级：幅值非有限
    RETURN;                           // 不出结论
END_IF

fReal := fS1 - fS2 * COS(fOmega);                       // 相位实部 [EU]
fImag := fS2 * SIN(fOmega);                             // 相位虚部 [EU]
IF (ABS(fReal) < DL_EPS) AND (ABS(fImag) < DL_EPS) THEN
    fPhaseRad := 0.0;                                   // 零幅（数值退化）相位无意义，取 0
ELSIF fImag >= 0.0 THEN
    fPhaseRad := ATAN(fImag / (ABS(fReal) + DL_EPS));    // 上支（含 imag = 0 且 real < 0）[rad]
    IF fReal < 0.0 THEN
        fPhaseRad := fPhaseRad + DL_TWO_PI * 0.5;       // 第二象限贴轴归属到正支 [rad]
    END_IF
ELSE
    fPhaseRad := ATAN(fImag / (ABS(fReal) + DL_EPS));    // 下支 [rad]
    IF fReal < 0.0 THEN
        fPhaseRad := fPhaseRad - DL_TWO_PI * 0.5;       // 第三象限贴轴归属到负支 [rad]
    END_IF
END_IF
fPhaseDeg := fPhaseRad * DL_RAD2DEG;                    // 相位 [deg]，域 (-180, 180]

(* —— 段 5：分辨力下限判定（低幅不出结论，置信息码） —— *)
IF fMagnitude < fMagFloor THEN
    fMagnitude := 0.0;                // 低于分辨力输出 0 [EU]
    nErrId := 16#0005_0510;           // 信息级：幅值低于分辨力（信息级不置 bError）
    RETURN;                           // 不出结论
END_IF

bValid := TRUE;                       // 结果有效
FC_DL_HarmonicSpectrumBin := TRUE;    // 返回布尔：TRUE = 本拍有有效结果

END_FUNCTION
