(*
  ==================================================================
  组件名 Component  : FC_DL_ThdCalc
  分类   Category   : DL_MathData
  复杂度 Complexity  : 低
  版本   Version    : 1.0.0
  功能   Purpose    : 总谐波失真率 THD = √(Σ h₂..hN²) / |h₁|。输入为幅值序列
                      （0 号位基波，1..N-1 为各次谐波），基波近零或非有限立即
                      置码并拒绝相除，谐波幅值按绝对值域参与（幅值约定）。
  来源   Source     : self-std（IEC 61131-3 标准数学语义自研聚合层）
  溯源   Origin     : THD 定义属公开电能质量语义，道莅 clean-room 自研实现，
                      未复制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（SQRT / ABS / FOR），三平台通用
  分工声明 Split     : 与 FC_DL_HarmonicSpectrumBin（频点分箱属主）与
                      FC_DL_FftRadix2（变换属主）分工——本件只做幅值序列的
                      聚合比值，不分箱、不做变换、不判谐波次数合法性。
  作者   Author     : 道莅代码库 · PLC 编程专家（R60）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 基波判据：|h₁| < 1E-9 判不可算，置故障级码并返回 0，
                         全程不执行除法（除零前置拦截）；
                      二 非有限判据：基波与参与谐波逐个用 x <> x（NaN）与
                         (x−x) <> (x−x)（Inf）双判，命中即三件套置位（R258）；
                      三 幅值域约定：谐波幅值取绝对值参与平方和，负幅值视为
                         相位翻转的幅值等价（本函数只出比值，不保留符号）；
                      四 计数钳位 [2, 元素容量]：少于 2 个元素无谐波可算，置
                         信息级码并返回 0；超容量钳位续算并置同一信息级码；
                      五 只读输入数组，不改调用方数据。
  错误码   Codes    :
    16#0001_0623【信息级】谐波计数越域已钳位（<2 或 >64）
    16#0001_0624【故障级】基波幅值近零（< 1E-9），THD 不可算
    16#0001_0625【故障级】样本含非有限值，THD 不可算
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 h = 100 / 10 / 10，个数 3 → THD = 0.141421（√200/100）
    V2 h = 100 / 0，个数 2 → THD = 0.0，bValid = TRUE
    V3 h₁ = 0 → 码 0624、bValid = FALSE、fThd = 0
    V4 h₂ = NaN → 码 0625、bValid = FALSE、fThd = 0
  修订记录 Revision  :
    2026-11-21  v1.0.0  R60 首版（批 2 · 序号 7）
  ==================================================================
*)
FUNCTION FC_DL_ThdCalc : LREAL
VAR_IN_OUT
    afHarm : ARRAY[0..63] OF LREAL; // 幅值序列 [幅值]，0 号位基波 / the amplitude series with the fundamental at the entry zero
END_VAR
VAR_INPUT
    nCount : DINT; // 幅值元素数（含基波）[个]，合法域 2..64 / the element count including the fundamental, legal from two to sixty four
END_VAR
VAR_OUTPUT
    bValid : BOOL;  // 结果可用标志 [-] / the result usable flag
    eErr   : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;  // 错误标志，eErr 非 0 时为真 / the error flag, true when eErr is nonzero
    nUsed  : DINT;  // 实际参与元素数 [个] / the element count actually used
END_VAR
VAR
    nI      : DINT;  // 遍历索引 [个] / the loop index
    fBase   : LREAL; // 基波幅值绝对值 [幅值] / the absolute fundamental amplitude
    fSqSum  : LREAL; // 谐波平方和 [幅值平方] / the harmonic square sum
    fV      : LREAL; // 当前谐波幅值工作副本 [幅值] / the current harmonic amplitude copy
    bNonFin : BOOL; // 非有限命中标志 [-] / the non finite hit flag
    bClamp  : BOOL; // 计数钳位标记 [-] / the count clamp flag
END_VAR
VAR CONSTANT
    DL_THD_NMAX   : DINT := 64;    // 元素容量上界 [个]，与数组容量一致 / the element capacity aligned with the array
    DL_THD_FLOOR  : LREAL := 1.0E-9; // 基波近零判据 [幅值] / the fundamental near zero criterion
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）+ 局部量显式预置（R254）/ segment 1, the preset of the return, the codes and the local guards
FC_DL_ThdCalc := 0.0; // 返回值预置安全值零 / preset the return to zero
bValid := FALSE; // 有效标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
nUsed := 0; // 参与元素数预置零 / preset the used count zero
fBase := 0.0; // 基波幅值预置零 / preset the fundamental zero
fSqSum := 0.0; // 平方和预置零 / preset the square sum zero
fV := 0.0; // 谐波副本预置零 / preset the harmonic copy zero
bNonFin := FALSE; // 非有限标志预置假 / preset the non finite flag false
bClamp := FALSE; // 钳位标记预置假 / preset the clamp flag false

// 段 2｜计数域闸（少于 2 早退，超容量钳位，边界四）/ segment 2, the count domain gate
IF nCount < 2 THEN // 无谐波可算 / no harmonic exists
    eErr := 16#0001_0623; // 信息级：计数越域已钳位 / informational, the count clamped
    bError := TRUE; // 置错误标志（信息级随事件置位惯例）/ raise the error flag
    RETURN; // 早退：bValid 保持假、返回 0 / early return with the validity false
END_IF
nUsed := nCount; // 域内接管 / take the count inside the domain
IF nUsed > DL_THD_NMAX THEN // 超容量 / above the capacity
    nUsed := DL_THD_NMAX; // 钳到容量 / clamp to the capacity
    bClamp := TRUE; // 置钳位标记 / raise the clamp flag
    eErr := 16#0001_0623; // 信息级：计数越域已钳位 / informational, the count clamped
    bError := TRUE; // 置错误标志 / raise the error flag
END_IF

// 段 3｜基波有限性与近零闸（除零前置拦截，边界一二）/ segment 3, the fundamental finiteness and near zero gate
fBase := ABS(afHarm[0]); // 基波取绝对值（幅值域约定，边界三）/ take the absolute fundamental amplitude
IF (fBase <> fBase) OR ((fBase - fBase) <> (fBase - fBase)) THEN // 基波非有限（NaN 自反 + Inf 差值自减）/ the fundamental is not finite
    bNonFin := TRUE; // 置非有限标志 / raise the non finite flag
END_IF
IF bNonFin THEN // 非有限即拒算 / refuse the computation on a non finite value
    eErr := 16#0001_0625; // 故障级：样本含非有限值 / fault grade, a non finite sample exists
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag, paired with the fault code
    bValid := FALSE; // 结果不可用 / the result void
    RETURN; // 早退：三件套已置（R258）/ early return with the triple raised
END_IF
IF fBase < DL_THD_FLOOR THEN // 基波近零，不可相除 / the fundamental near zero cannot divide
    eErr := 16#0001_0624; // 故障级：基波幅值近零 / fault grade, the fundamental near zero
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag, paired with the fault code
    bValid := FALSE; // 结果不可用 / the result void
    RETURN; // 早退：全程未执行除法 / early return without any division
END_IF

// 段 4｜谐波平方和累加（逐个非有限剔除为拒算，不静默跳过）/ segment 4, the harmonic square sum with an explicit refusal
FOR nI := 1 TO nUsed - 1 DO // 有界循环（nUsed 已钳 ≤64）/ the bounded loop
    fV := ABS(afHarm[nI]); // 谐波取绝对值 / take the absolute amplitude
    IF (fV <> fV) OR ((fV - fV) <> (fV - fV)) THEN // 谐波非有限 / a non finite harmonic
        bNonFin := TRUE; // 置非有限标志 / raise the non finite flag
    ELSE // 有限谐波参与累加 / a finite harmonic participates
        fSqSum := fSqSum + fV * fV; // 平方累加 / accumulate the square
    END_IF
END_FOR
IF bNonFin THEN // 任一谐波非有限 / any harmonic is not finite
    eErr := 16#0001_0625; // 故障级：样本含非有限值 / fault grade, a non finite sample exists
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag, paired with the fault code
    bValid := FALSE; // 结果不可用 / the result void
    FC_DL_ThdCalc := 0.0; // 返回值回安全值（不泄半结果）/ the return back to the safe zero
    RETURN; // 早退 / early return
END_IF

// 段 5｜比值计算与结果复检（除子已证 ≥ 1E-9）/ segment 5, the ratio and the result recheck
FC_DL_ThdCalc := SQRT(fSqSum) / fBase; // THD = √Σh² / |h₁|（除子已证非零）/ the ratio with a proven nonzero divisor
IF (FC_DL_ThdCalc <> FC_DL_ThdCalc) OR ((FC_DL_ThdCalc - FC_DL_ThdCalc) <> (FC_DL_ThdCalc - FC_DL_ThdCalc)) THEN // 结果非有限兜底（R258 三件套）/ the non finite result guard
    FC_DL_ThdCalc := 0.0; // 兜底安全值 / the bottom-line safe value
    eErr := 16#0001_0625; // 故障级：结果非有限（平方和溢出）/ fault grade, the non finite result
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag, paired with the fault code
    bValid := FALSE; // 结果不可用 / the result void
ELSE // 结果有限 / a finite result
    bValid := TRUE; // 结果可用 / the result is usable
END_IF
END_FUNCTION
