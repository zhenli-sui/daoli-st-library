(*
  ==================================================================
  组件名 Component  : FC_DL_FftRadix2
  分类   Category   : DL_MathData
  复杂度 Complexity  : 重
  版本   Version    : 1.0.0
  功能   Purpose    : 基-2 FFT 频谱变换（就地算法）。2^N 点（2..256）位反转
                      序内排 + 蝶形运算，可选 Hann 窗（bWinEn）；非有限样本
                      拦截置 bError（禁静默吞）。输出实部/虚部数组供幅谱/谐
                      波分析后继使用。OSCAT Basic 数值域公开语义 clean-room，
                      与 FC_DL_HarmonicSpectrumBin 谐波定 bins 分工互引。
  来源   Source     : T1-1-oscat-basic（数值域公开语义）
  溯源   Origin     : Cooley-Tukey 基-2 FFT 为公开数值算法，clean-room 自研
                      实现，未复制 OSCAT 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
  分工声明 Split     : 与 FC_DL_HarmonicSpectrumBin 分工——后者做指定 bins
                      谐波幅值提取，本件做全谱基-2 变换。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 点数闸：nPoints ∈ [2..256] 且为 2 的幂（位判据
                         (n AND (n-1)) = 0），超 256 截为 256 并置 bTrunc，
                         非法置 bError；
                      二 非有限拦截：输入样本逐点自反双判据，命中置 bError
                         早退，输出保持安全侧零（纪律②）；
                      三 蝶形三角因子逐点 COS/SIN 生成（无查表依赖，跨平台
                         可移植）；WHILE 环长度倍增有界终止；
                      四 无除法无开方（纯乘加与三角函数，无除零风险）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 4 · 序号 16）
  ==================================================================
*)

FUNCTION FC_DL_FftRadix2 : BOOL
VAR_INPUT
    aIn     : ARRAY[0..255] OF LREAL; // 输入样本组 [工程单位] / the input samples [engineering unit]
    nPoints : DINT := 256;  // 变换点数 [点]，2 的幂，域 2..256 / the transform points, a power of two
    bWinEn  : BOOL := TRUE; // Hann 窗使能 [-] / the Hann window enable
END_VAR
VAR_OUTPUT
    aRe     : ARRAY[0..255] OF LREAL; // 频谱实部组 [工程单位] / the spectrum real parts
    aIm     : ARRAY[0..255] OF LREAL; // 频谱虚部组 [工程单位] / the spectrum imaginary parts
    bValid  : BOOL := FALSE; // 变换受理且完成 [-] / the transform accepted and done
    bTrunc  : BOOL := FALSE; // 点数截断标志（超 256 截为 256）[-] / the points truncation flag
    bError  : BOOL := FALSE; // 故障标志（点数非法或非有限样本）[-] / the fault flag
END_VAR
VAR CONSTANT
    DL_FFT_NMAX   : DINT  := 256;           // 点数上界 [点] / the points ceiling
    DL_FFT_TWOPI  : LREAL := 6.28318530717959; // 2π [弧度] / the two pi in radian
END_VAR
VAR
    nN     : DINT;  // 有效点数工作副本 [点] / the effective points work copy
    nI     : DINT;  // 通用索引一 [点] / the general index one
    nJ     : DINT;  // 通用索引二 [点] / the general index two
    nBit   : DINT;  // 位反转步进位 [位] / the bit reversal stepping bit
    nLen   : DINT;  // 蝶形环长度 [点] / the butterfly block length
    nHalf  : DINT;  // 环半长 [点] / the block half length
    nBase  : DINT;  // 环基址 [点] / the block base index
    fArg   : LREAL; // 旋转因子角 [弧度] / the twiddle angle [radian]
    fWr    : LREAL; // 旋转因子实部 [无量纲] / the twiddle real part
    fWi    : LREAL; // 旋转因子虚部 [无量纲] / the twiddle imaginary part
    fTr    : LREAL; // 蝶形实部暂存 [工程单位] / the butterfly real temp
    fTi    : LREAL; // 蝶形虚部暂存 [工程单位] / the butterfly imaginary temp
    bFin   : BOOL;  // 样本有限工作量 [-] / the sample finiteness work flag
END_VAR

// 段 1｜返回值与输出预置（四段式第一段，R45）/ segment 1, preset the return and the outputs
FC_DL_FftRadix2 := FALSE; // 受理预置假 / preset the accepted false
bValid := FALSE; // 有效预置假 / preset the valid false
bTrunc := FALSE; // 截断预置假 / preset the trunc false
bError := FALSE; // 故障预置假 / preset the fault false
FOR nI := 0 TO DL_FFT_NMAX - 1 DO // 输出全清（安全侧零基线）/ clear the outputs
    aRe[nI] := 0.0; // 实部清零 / clear the real
    aIm[nI] := 0.0; // 虚部清零 / clear the imaginary
END_FOR

// 段 2｜点数闸（域 + 2 的幂位判据，边界一）/ segment 2, the points gates
nN := nPoints; // 装载工作副本 / load the work copy
IF nN > DL_FFT_NMAX THEN // 超上界截断 / beyond the ceiling, truncate
    nN := DL_FFT_NMAX; // 截为 256 / truncate to the ceiling
    bTrunc := TRUE; // 置截断标志 / raise the truncation
END_IF
IF (nN < 2) OR ((nN AND (nN - 1)) <> 0) THEN // 下界或非 2 幂 / below the floor or not a power of two
    bError := TRUE; // 置故障 / raise the fault
    RETURN; // 早退 / return early
END_IF

// 段 3｜非有限样本拦截（逐点自反双判据，边界二）/ segment 3, the non finite sample interception
FOR nI := 0 TO nN - 1 DO // 逐点扫描 / per point scan
    bFin := (aIn[nI] = aIn[nI]) AND ((aIn[nI] - aIn[nI]) = (aIn[nI] - aIn[nI])); // 自反双判据（R79）/ the dual verdicts
    IF NOT bFin THEN // 非有限命中 / a non finite hit
        bError := TRUE; // 置故障（纪律②）/ raise the fault
        RETURN; // 早退（输出保持安全侧零）/ return early
    END_IF
END_FOR

// 段 4｜Hann 窗预加重与实部装填（虚部清零）/ segment 4, the Hann window and the loading
FOR nI := 0 TO nN - 1 DO // 逐点装填 / per point load
    IF bWinEn THEN // 加窗使能 / the window enabled
        aRe[nI] := aIn[nI] * (0.5 * (1.0 - COS(DL_FFT_TWOPI * DINT_TO_LREAL(nI) / DINT_TO_LREAL(nN - 1)))); // Hann 权重（nN ≥ 2 保证除子非零）/ the Hann weight, the divisor nonzero
    ELSE // 直通 / the pass through
        aRe[nI] := aIn[nI]; // 样本直通 / the sample direct
    END_IF
    aIm[nI] := 0.0; // 虚部清零 / clear the imaginary
END_FOR

// 段 5｜位反转序内排（CP 公开算法 ST 化）/ segment 5, the in place bit reversal
nJ := 0; // 反转索引清零 / clear the reversal index
FOR nI := 1 TO nN - 1 DO // 逐点重排 / per point reorder
    nBit := nN SHR 1; // 步进位起步 / start the stepping bit
    WHILE (nJ AND nBit) <> 0 DO // 逐位回退 / the bit rollback
        nJ := nJ - nBit; // 位清 / clear the bit
        nBit := nBit SHR 1; // 位右移 / shift the bit
    END_WHILE
    nJ := nJ + nBit; // 位置位 / set the bit
    IF nI < nJ THEN // 交换对（就地）/ the swap pair, in place
        fTr := aRe[nI];  aRe[nI] := aRe[nJ];  aRe[nJ] := fTr; // 实部交换 / swap the real
        fTi := aIm[nI];  aIm[nI] := aIm[nJ];  aIm[nJ] := fTi; // 虚部交换 / swap the imaginary
    END_IF
END_FOR

// 段 6｜基-2 蝶形主环（环长倍增有界终止，边界三）/ segment 6, the radix two butterfly main loop
nLen := 2; // 环长起步 / start the block length
WHILE nLen <= nN DO // 倍增推进 / the doubling advance
    nHalf := nLen SHR 1; // 环半长 / the half length
    fArg := -DL_FFT_TWOPI / DINT_TO_LREAL(nLen); // 基元旋转角（负向，正变换约定）/ the primitive angle, negative forward
    nBase := 0; // 环基址起步 / start the base
    WHILE nBase < nN DO // 环扫描 / the block scan
        FOR nJ := 0 TO nHalf - 1 DO // 半环内蝶形 / per butterfly in the half block
            fWr := COS(fArg * DINT_TO_LREAL(nJ)); // 旋转因子实部 / the twiddle real
            fWi := SIN(fArg * DINT_TO_LREAL(nJ)); // 旋转因子虚部 / the twiddle imaginary
            fTr := (aRe[nBase + nJ + nHalf] * fWr) - (aIm[nBase + nJ + nHalf] * fWi); // 上蝶实部 / the upper real
            fTi := (aRe[nBase + nJ + nHalf] * fWi) + (aIm[nBase + nJ + nHalf] * fWr); // 上蝶虚部 / the upper imaginary
            aRe[nBase + nJ + nHalf] := aRe[nBase + nJ] - fTr; // 下蝶写回 / the lower write back
            aIm[nBase + nJ + nHalf] := aIm[nBase + nJ] - fTi; // 下蝶写回 / the lower write back
            aRe[nBase + nJ] := aRe[nBase + nJ] + fTr; // 上蝶写回 / the upper write back
            aIm[nBase + nJ] := aIm[nBase + nJ] + fTi; // 上蝶写回 / the upper write back
        END_FOR
        nBase := nBase + nLen; // 环基址推进 / advance the base
    END_WHILE
    nLen := nLen + nLen; // 环长倍增（有界终止保证）/ double the block length, the bounded termination
END_WHILE
bValid := TRUE; // 变换完成 / the transform done
FC_DL_FftRadix2 := TRUE; // 受理 / accept
END_FUNCTION
