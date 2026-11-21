(*
  ==================================================================
  组件名 Component  : FC_DL_BiquadCoeff
  分类   Category   : DL_Algo
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0002_373D / 373E（故障级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : 二阶节五系数生成器（低通 / 高通 / 带通 / 陷波四型，归一化
                      a0 = 1 口径），为 FB_DL_BiquadFilter / FB_DL_BiquadCascade
                      提供下发系数，闭合「设计 → 下发」链。
  开源溯源 Origin    : 公开公式 clean-room，参考 RBJ Audio EQ Cookbook 类公开二阶节
                      设计公式（biquad coefficient 公式为公开领域知识，分类与公式
                      借鉴，零代码复制），本件实现、闸门与码位 100% 自有。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术运算符；RBJ Audio EQ Cookbook 公开
                      二阶节设计公式（w0 = 2π·f0/Fs，alpha = sin(w0)/(2Q)）
  平台   Platform   : 纯 IEC 61131-3（FOR / CASE / 四则 / SIN / COS），三平台通用
  依赖   Depends    : 仅 Standard.library（SIN / COS 属标准内建）
  分工声明 Split     : FB_DL_NotchFilter（陷波一体机：内算内滤）/ FB_DL_SecondOrder
                      Filter（巴特沃斯二阶：内算内滤）为内算型；本件只产系数**不下发
                      执行**，与两个内算型互引，现场自行组合（R216）。
  归属 Ownership     : E_DL_BiquadType 属主为本文件（全库唯一定义，R264）；引用件
                      只引用不重声明。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 域闸全量枚举（R272）：fFs ≤ 0、fF0 ≤ 0 或 ≥ 0.45×fFs
                         （奈奎斯特闸）、fQ 越域 [0.1, 20.0]、任一非有限 → 五系数
                         全 0 + 故障码 373D + 三件套 + RETURN 结构早退；
                      二 枚举越域（CASE ELSE）：落 373D 同码处置——反证句（R90）：
                         枚举非法与域闸失败的出口组合完全同形（五系数全 0、bValid =
                         FALSE），无法由输出区分，按 R90 不另立码；
                      三 归一化除子 a0 = 1 + alpha：alpha > 0 结构性成立（fF0 > 0
                         已证 → w0 ∈ (0, 0.9π) → sin(w0) > 0 → alpha > 0 → a0 > 1），
                         另设 ABS(a0) < 1.0E-9 闸（码 373E）作平台数值兜底；
                      四 中间量常量提级：2π、0.45 与 Q 域界全部 VAR CONSTANT，
                         禁魔法数；
                      五 Jury 一致性声明：本件产出的系数建议由 FB_DL_BiquadFilter /
                         BiquadCascade 的 Jury 三条件闸复验；两闸口径一致
                         （|a2|<1 ∧ 1+a1+a2>0 ∧ 1−a1+a2>0，返修 R2 固化判据）；
                      六 结果复检非有限 → 三件套兜底（R258）；
                      七 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
                      八 无全局、无外部变量、无物理地址、无指针。
  错误码 Codes      :
    16#0002_373D【故障级】域闸失败（fFs / fF0 / fQ 越域或任一非有限，或类型枚举
                         非法，五系数全 0）
    16#0002_373E【故障级】归一化分母近零（ABS(a0) < 1.0E-9）或结果复检非有限
                         （后者理论上不可达的兜底分支，出口组合同形，R90 不另立）
  码位反证 Note     :
    373D 与 373E 不可合并：373D 出口五系数全 0 且未进入计算，373E 出口同样全 0 但
    已进入计算，两者处置人不同（组态工程师调参数 / 数值平台问题），且 373E 仅在
    理论上不可达路径出现，按 R90 分立两码（场景可由码值唯一还原）。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 fFs = 1000, fF0 = 100, fQ = 0.7071 低通（巴特沃斯）→ b0 ≈ 0.06745、
       b1 ≈ 0.1349、b2 ≈ 0.06745、a1 ≈ −1.1430、a2 ≈ 0.4128（公开设计值）
    V2 同参高通 → 系数为低通镜像（b0 / b2 互换语义，b1 取负）
    V3 fF0 = 0.46×fFs → 奈奎斯特闸故障早退；V4 fQ = 0 → 故障早退
    V5 fFs = 0 → 故障早退；V6 陷波型 fF0 = 50, fFs = 1000, fQ = 5 → 在 50Hz
       处增益 ≈ 0（定性向量）；V7 fQ = 25 → 越域故障早退
  修订记录 Revision  :
    2026-11-21  v1.0.0  R63 首版（批 2 · 序号 6）
  ==================================================================
*)
TYPE E_DL_BiquadType :
(
    eLowPass  := 0, // 低通：通带以下通过，截止频率以上衰减 / the low pass type passing below the cutoff
    eHighPass := 1, // 高通：截止频率以上通过，以下衰减 / the high pass type passing above the cutoff
    eBandPass := 2, // 带通：中心频率附近通过（0 dB 峰值增益口径）/ the band pass type passing around the center with a zero dB peak gain
    eNotch    := 3  // 陷波：中心频率处深衰减（挖槽）/ the notch type with a deep attenuation at the center
);
END_TYPE

FUNCTION FC_DL_BiquadCoeff : BOOL
VAR_INPUT
    eType   : E_DL_BiquadType := E_DL_BiquadType.eLowPass; // 滤波器类型 [-] / the filter type
    fFs     : LREAL := 1000.0; // 采样频率 [赫兹]，须 > 0 / the sampling frequency, must be positive
    fF0     : LREAL := 100.0;  // 中心 / 截止频率 [赫兹]，0 < fF0 < 0.45×fFs / the center or cutoff frequency below the Nyquist guard
    fQ      : LREAL := 0.7071; // 品质因数 [−]，域 [0.1, 20.0] / the quality factor inside its domain
END_VAR
VAR_OUTPUT
    fB0     : LREAL := 0.0; // 归一化前向系数 b0 [−]，a0 = 1 口径 / the normalized feed forward coefficient b0
    fB1     : LREAL := 0.0; // 归一化前向系数 b1 [−] / the normalized feed forward coefficient b1
    fB2     : LREAL := 0.0; // 归一化前向系数 b2 [−] / the normalized feed forward coefficient b2
    fA1     : LREAL := 0.0; // 归一化反馈系数 a1 [−] / the normalized feedback coefficient a1
    fA2     : LREAL := 0.0; // 归一化反馈系数 a2 [−] / the normalized feedback coefficient a2
    bValid  : BOOL := FALSE; // 结果可用 [-] / the result usable flag
    eErr    : UDINT := 16#0000_0000; // 错误码，0 = 正常 / the error code, zero is ok
    bError  : BOOL := FALSE; // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    fW0     : LREAL := 0.0; // 数字角频率 w0 = 2π·f0/Fs [弧度] / the digital angular frequency
    fCosW0  : LREAL := 0.0; // cos(w0) 中间量 [−] / the cosine intermediate
    fSinW0  : LREAL := 0.0; // sin(w0) 中间量 [−] / the sine intermediate
    fAlpha  : LREAL := 0.0; // 阻尼因子 alpha = sin(w0)/(2Q) [−]，除子 2Q 已证 > 0 / the damping factor with the proven divisor
    fA0     : LREAL := 0.0; // 归一化前分母 a0 = 1 + alpha [−] / the pre normalization denominator
    fB0Raw  : LREAL := 0.0; // 未归一化 b0 暂存 [−] / the raw b0 in staging
    fB1Raw  : LREAL := 0.0; // 未归一化 b1 暂存 [−] / the raw b1 in staging
    fB2Raw  : LREAL := 0.0; // 未归一化 b2 暂存 [−] / the raw b2 in staging
    fA1Raw  : LREAL := 0.0; // 未归一化 a1 暂存 [−] / the raw a1 in staging
    fA2Raw  : LREAL := 0.0; // 未归一化 a2 暂存 [−] / the raw a2 in staging
    fNyq    : LREAL := 0.0; // 奈奎斯特闸限 0.45×fFs [赫兹] / the Nyquist guard value
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_BQC_2PI   : LREAL := 6.283185307179586; // 2π 常量（LREAL 精度字面量，R55）/ the two pi constant at LREAL precision
    DL_BQC_NYQ   : LREAL := 0.45;   // 奈奎斯特闸系数 [−]（0.45×fFs）/ the Nyquist guard fraction
    DL_BQC_QMIN  : LREAL := 0.1;    // 品质因数下界 [−] / the quality factor floor
    DL_BQC_QMAX  : LREAL := 20.0;   // 品质因数上界 [−] / the quality factor ceiling
    DL_BQC_DENEPS: LREAL := 1.0E-9; // 归一化分母近零门限 [−] / the near zero denominator threshold
    DL_BQC_TWO   : LREAL := 2.0;    // 实数二常量 [−]（阻尼因子除子）/ the real two constant
    DL_BQC_ZERO  : LREAL := 0.0;    // 实数零常量 [−] / the real zero constant
    DL_BQC_ONE   : LREAL := 1.0;    // 实数一常量 [−] / the real one constant
    DL_BQC_HALF  : LREAL := 0.5;    // 实数半常量 [−] / the real half constant
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段：五系数全 0）/ segment 1, the preset of the return and every outlet
FC_DL_BiquadCoeff := FALSE; // 返回值预置假 / preset the return false
fB0 := DL_BQC_ZERO; // 系数 b0 预置零 [−] / preset the coefficient b0 zero
fB1 := DL_BQC_ZERO; // 系数 b1 预置零 [−] / preset the coefficient b1 zero
fB2 := DL_BQC_ZERO; // 系数 b2 预置零 [−] / preset the coefficient b2 zero
fA1 := DL_BQC_ZERO; // 系数 a1 预置零 [−] / preset the coefficient a1 zero
fA2 := DL_BQC_ZERO; // 系数 a2 预置零 [−] / preset the coefficient a2 zero
bValid := FALSE; // 可用标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the error flag false
fW0 := DL_BQC_ZERO; // 角频率预置零 [弧度] / preset the angular frequency zero
fCosW0 := DL_BQC_ZERO; // 余弦预置零 [−] / preset the cosine zero
fSinW0 := DL_BQC_ZERO; // 正弦预置零 [−] / preset the sine zero
fAlpha := DL_BQC_ZERO; // 阻尼因子预置零 [−] / preset the damping zero
fA0 := DL_BQC_ZERO; // 分母预置零 [−] / preset the denominator zero
fB0Raw := DL_BQC_ZERO; // 原始 b0 预置零 [−] / preset the raw b0 zero
fB1Raw := DL_BQC_ZERO; // 原始 b1 预置零 [−] / preset the raw b1 zero
fB2Raw := DL_BQC_ZERO; // 原始 b2 预置零 [−] / preset the raw b2 zero
fA1Raw := DL_BQC_ZERO; // 原始 a1 预置零 [−] / preset the raw a1 zero
fA2Raw := DL_BQC_ZERO; // 原始 a2 预置零 [−] / preset the raw a2 zero
fNyq := DL_BQC_ZERO; // 奈奎斯特闸限预置零 [赫兹] / preset the Nyquist guard zero

// 段 2｜域闸全量枚举（边界一，R272：fFs / fF0 / fQ 逐个点名 + 非有限双判）/ segment 2, the full domain gate naming every real pin
fNyq := DL_BQC_NYQ * fFs; // 奈奎斯特闸限（fFs 非有限时乘积亦非有限，闸随后命中）[赫兹] / the Nyquist guard, a non finite sampling frequency lands non finite and the gate catches it
IF (fFs <> fFs) OR ((fFs - fFs) <> (fFs - fFs)) OR (fFs <= DL_BQC_ZERO)
OR (fF0 <> fF0) OR ((fF0 - fF0) <> (fF0 - fF0)) OR (fF0 <= DL_BQC_ZERO) OR (fF0 >= fNyq)
OR (fQ <> fQ) OR ((fQ - fQ) <> (fQ - fQ)) OR (fQ < DL_BQC_QMIN) OR (fQ > DL_BQC_QMAX) THEN // 域闸失败 / a domain gate failure
    eErr := 16#0002_373D; // 故障级：域闸失败 / fault grade, a domain gate failure
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 结构早退：五系数已预置全 0，计算段不可达 / the structural early exit with all five coefficients preset to zero
END_IF

// 段 3｜中间量计算（除子 fFs 已证 > 0、2Q 已证 > 0.2）/ segment 3, the intermediates
fW0 := (DL_BQC_2PI * fF0) / fFs; // 数字角频率 [弧度]，除子已证 > 0 / the angular frequency with the proven divisor
fCosW0 := COS(fW0); // cos(w0) [−] / the cosine
fSinW0 := SIN(fW0); // sin(w0) [−] / the sine
fAlpha := fSinW0 / (DL_BQC_TWO * fQ); // 阻尼因子 [−]，除子已证 > 0 / the damping factor with the proven divisor
fA0 := DL_BQC_ONE + fAlpha; // 归一化前分母 [−]，结构性 > 1（边界三证明）/ the pre normalization denominator structurally above one

// 段 4｜四型未归一化系数（CASE 必带 ELSE 兜底，边界二）/ segment 4, the four raw coefficient families
CASE eType OF
    E_DL_BiquadType.eLowPass: // 低通 / the low pass family
        fB0Raw := (DL_BQC_ONE - fCosW0) * DL_BQC_HALF; // b0 = (1−cos w0)/2 [−] / the raw b0
        fB1Raw := DL_BQC_ONE - fCosW0; // b1 = 1−cos w0 [−] / the raw b1
        fB2Raw := (DL_BQC_ONE - fCosW0) * DL_BQC_HALF; // b2 = (1−cos w0)/2 [−] / the raw b2
        fA1Raw := -DL_BQC_TWO * fCosW0; // a1 = −2·cos w0 [−] / the raw a1
        fA2Raw := DL_BQC_ONE - fAlpha; // a2 = 1−alpha [−] / the raw a2
    E_DL_BiquadType.eHighPass: // 高通 / the high pass family
        fB0Raw := (DL_BQC_ONE + fCosW0) * DL_BQC_HALF; // b0 = (1+cos w0)/2 [−] / the raw b0
        fB1Raw := -(DL_BQC_ONE + fCosW0); // b1 = −(1+cos w0) [−] / the raw b1
        fB2Raw := (DL_BQC_ONE + fCosW0) * DL_BQC_HALF; // b2 = (1+cos w0)/2 [−] / the raw b2
        fA1Raw := -DL_BQC_TWO * fCosW0; // a1 = −2·cos w0 [−] / the raw a1
        fA2Raw := DL_BQC_ONE - fAlpha; // a2 = 1−alpha [−] / the raw a2
    E_DL_BiquadType.eBandPass: // 带通（0 dB 峰值增益口径）/ the band pass family
        fB0Raw := fAlpha; // b0 = alpha [−] / the raw b0
        fB1Raw := DL_BQC_ZERO; // b1 = 0 [−] / the raw b1
        fB2Raw := -fAlpha; // b2 = −alpha [−] / the raw b2
        fA1Raw := -DL_BQC_TWO * fCosW0; // a1 = −2·cos w0 [−] / the raw a1
        fA2Raw := DL_BQC_ONE - fAlpha; // a2 = 1−alpha [−] / the raw a2
    E_DL_BiquadType.eNotch: // 陷波 / the notch family
        fB0Raw := DL_BQC_ONE; // b0 = 1 [−] / the raw b0
        fB1Raw := -DL_BQC_TWO * fCosW0; // b1 = −2·cos w0 [−] / the raw b1
        fB2Raw := DL_BQC_ONE; // b2 = 1 [−] / the raw b2
        fA1Raw := -DL_BQC_TWO * fCosW0; // a1 = −2·cos w0 [−] / the raw a1
        fA2Raw := DL_BQC_ONE - fAlpha; // a2 = 1−alpha [−] / the raw a2
    ELSE // 枚举非法：落 373D 同码（反证句见码表，出口与域闸失败同形）/ an illegal enumeration under the same code
        eErr := 16#0002_373D; // 故障级：类型枚举非法（归入域闸族）/ fault grade, the type enumeration is illegal in the gate family
        bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
        bValid := FALSE; // 结果不可用 / the result is not usable
        RETURN; // 早退，五系数保持预置全 0 / early return with the preset zeros
END_CASE

// 段 5｜归一化除子闸与系数归一（边界三，禁除零）/ segment 5, the normalization with the denominator guard
IF ABS(fA0) < DL_BQC_DENEPS THEN // 分母近零（理论不可达的平台数值兜底）/ a near zero denominator, a platform numerical fallback
    eErr := 16#0002_373E; // 故障级：归一化分母近零 / fault grade, the normalization denominator is near zero
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退，五系数保持全 0 / early return with the zeros
END_IF
fB0 := fB0Raw / fA0; // 归一化 b0 [−]，除子已证 ≥ 门限 / the normalized b0
fB1 := fB1Raw / fA0; // 归一化 b1 [−] / the normalized b1
fB2 := fB2Raw / fA0; // 归一化 b2 [−] / the normalized b2
fA1 := fA1Raw / fA0; // 归一化 a1 [−] / the normalized a1
fA2 := fA2Raw / fA0; // 归一化 a2 [−] / the normalized a2

// 段 6｜结果复检兜底（三件套，R258；与 373E 同码，反证见码表）/ segment 6, the result recheck with the three part fallback
IF (fB0 <> fB0) OR ((fB0 - fB0) <> (fB0 - fB0))
OR (fB1 <> fB1) OR ((fB1 - fB1) <> (fB1 - fB1))
OR (fB2 <> fB2) OR ((fB2 - fB2) <> (fB2 - fB2))
OR (fA1 <> fA1) OR ((fA1 - fA1) <> (fA1 - fA1))
OR (fA2 <> fA2) OR ((fA2 - fA2) <> (fA2 - fA2)) THEN // 任一系数非有限（理论上不可达，防御保留）/ any non finite coefficient, unreachable by theory
    fB0 := DL_BQC_ZERO; // 系数 b0 兜底归零 [−] / the bottom line zero
    fB1 := DL_BQC_ZERO; // 系数 b1 兜底归零 [−] / the bottom line zero
    fB2 := DL_BQC_ZERO; // 系数 b2 兜底归零 [−] / the bottom line zero
    fA1 := DL_BQC_ZERO; // 系数 a1 兜底归零 [−] / the bottom line zero
    fA2 := DL_BQC_ZERO; // 系数 a2 兜底归零 [−] / the bottom line zero
    eErr := 16#0002_373E; // 故障级：结果非有限（同族一码）/ fault grade under the same family code
    bError := TRUE; // 置故障标志（R45 配对）/ raise the fault flag
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退 / early return
END_IF

// 段 7｜统一出口 / segment 7, the unified outlet
bValid := TRUE; // 结果可用 / the result is usable
FC_DL_BiquadCoeff := TRUE; // 返回成功 / return success
END_FUNCTION
