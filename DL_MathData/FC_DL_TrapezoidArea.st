(*
  ==================================================================
  组件名 Component  : FC_DL_TrapezoidArea
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  复杂度 Complexity  : 低
  版本   Version    : 1.0.0
  功能   Purpose    : 离散序列梯形法累计面积（采样周期入参，纯函数一次算完）。
  来源   Source     : self-std（公开数值积分语义自研包装）
  平台   Platform   : 纯 IEC 61131-3（FOR / 四则 / ABS），三平台通用
  分工声明 Split     : 与 FB_DL_Integrator（连续积分器属主）分工——后者跨拍
                      保持积分状态；本件为无状态纯函数，一次入参一次出面积
                      （R216 双向互引）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R61）
  归属 Ownership     : 本件无 TYPE 声明；引用件类型全部 IEC 标准原生。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 nCount < 2 无梯形可积：置信息级码、不积累，fArea = 0、
                         bValid = FALSE（信息级不置 bError，R285 口径）；
                      二 采样周期 fDtSec ≤ 0：故障级码，拒绝积分（除法无涉，
                         但零周期等于伪造面积，判故障）；
                      三 NaN 点跳过段计：非有限采样点所在梯形段整段跳过并计数
                         上报 nSkipCnt（信息级，逐点判 x <> x 自反）；
                      四 结果复检兜底同拍置 eErr + bError + bValid 三件套（R258）；
                      五 只读入参数组，不改调用方数据（PercentileLReal 纪律）；
                      六 无状态纯函数：局部量段 1 显式预置（R254）。
  错误码   Codes    :
    16#0001_0633【信息级】采样点数不足（<2），不积累
    16#0001_0634【故障级】采样周期非法（fDtSec ≤ 0），拒绝积分
    16#0001_0635【信息级】存在非有限采样点，已跳过其所在段，个数见 nSkipCnt
    16#0001_0636【故障级】结果非有限（复检兜底）
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 值 0/1/2、fDtSec=1 → 面积 2.0
    V2 nCount=1 → 码 0633、fArea=0、bValid=FALSE
    V3 fDtSec=0 → 码 0634、bError=TRUE
    V4 中间一点 NaN → 码 0635、nSkipCnt=1、有效段照常累加
  修订记录 Revision  :
    2026-11-21  v1.0.0  R61 首版（批 1 · 序号 4）
  ==================================================================
*)
FUNCTION FC_DL_TrapezoidArea : BOOL
VAR_IN_OUT
    afValues : ARRAY[0..1023] OF LREAL; // 采样序列 [工程单位]，前 nCount 个有效 / the sample series, the first nCount entries valid
END_VAR
VAR_INPUT
    nCount  : DINT;  // 采样点数 [个]，合法域 2..1024 / the sample count, legal from two to one thousand twenty four
    fDtSec  : LREAL; // 采样周期 [秒]，必须 > 0 / the sample period in seconds, must be positive
END_VAR
VAR_OUTPUT
    fArea    : LREAL; // 累计面积 [工程单位 × 秒] / the accumulated area
    nSkipCnt : UDINT; // 被跳过的梯形段数 [段] / the skipped trapezoid segment count
    bValid   : BOOL;  // 结果可用标志 [-] / the result usable flag
    eErr     : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError   : BOOL;  // 错误标志，故障级码置位（R45 配对）/ the error flag
END_VAR
VAR
    k        : DINT;  // 段循环索引 [段] / the segment loop index
    nUse     : DINT;  // 钳位后的采样点数 [个] / the clamped sample count
    fV0      : LREAL; // 段左端采样值 [工程单位] / the left sample value of the segment
    fV1      : LREAL; // 段右端采样值 [工程单位] / the right sample value of the segment
    bSkip    : BOOL;  // 本段跳过标记 [-] / the skip flag of this segment
    bClamp   : BOOL;  // 点数钳位标记 [-] / the count clamp flag
END_VAR
VAR CONSTANT
    DL_TRA_NMAX : DINT := 1024; // 采样点容量上界 [个]，与数组容量一致 / the sample capacity aligned with the array
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）+ 局部量显式预置（R254）/ segment 1, the preset
FC_DL_TrapezoidArea := FALSE; // 返回值预置假 / preset the return false
fArea := 0.0; // 面积预置零 / preset the area zero
nSkipCnt := 0; // 跳过计数预置零 / preset the skipped count zero
bValid := FALSE; // 有效标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
nUse := 0; // 采样点数预置零 / preset the count zero
fV0 := 0.0; // 左端值预置零 / preset the left value zero
fV1 := 0.0; // 右端值预置零 / preset the right value zero
bSkip := FALSE; // 跳过标记预置假 / preset the skip flag false
bClamp := FALSE; // 钳位标记预置假 / preset the clamp flag false

// 段 2｜域闸：点数下界早退与上界钳位、周期正域（边界一二）/ segment 2, the count and period gates
IF nCount < 2 THEN // 点数不足：无梯形可积（边界一）/ too few samples, no trapezoid
    eErr := 16#0001_0633; // 信息级：点数不足不积累（信息级不置 bError）/ informational, too few samples
    RETURN; // 早退：fArea 保持零、bValid 保持假 / early return with the area zero
END_IF
IF fDtSec <= 0.0 THEN // 周期非法（边界二）/ an illegal period
    eErr := 16#0001_0634; // 故障级：采样周期非法 / fault grade, the illegal period
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag
    bValid := FALSE; // 结果不可用 / the result void
    RETURN; // 早退 / early return
END_IF
nUse := nCount; // 点数域内接管 / take the count
IF nUse > DL_TRA_NMAX THEN // 超容量 / above the capacity
    nUse := DL_TRA_NMAX; // 钳到容量 / clamp to the capacity
    bClamp := TRUE; // 置钳位标记 / raise the clamp flag
END_IF

// 段 3｜梯形法逐段累加（NaN 点整段跳过并计数，边界三）/ segment 3, the segment by segment accumulation with the NaN skip
FOR k := 0 TO nUse - 2 DO // 有界段循环 / the bounded segment loop
    fV0 := afValues[k]; // 左端采样值 / the left sample
    fV1 := afValues[k + 1]; // 右端采样值 / the right sample
    bSkip := (fV0 <> fV0) OR (fV1 <> fV1)
    OR ((fV0 - fV0) <> (fV0 - fV0)) OR ((fV1 - fV1) <> (fV1 - fV1)); // 两端逐点非有限判（NaN 自反 + Inf 差值自减）/ the per point finiteness test
    IF bSkip THEN // 本段含非有限点 / this segment holds a non finite point
        nSkipCnt := nSkipCnt + 1; // 跳过计数推进 / advance the skipped count
    ELSE // 有效段照常累加 / a valid segment accumulates
        fArea := fArea + (fV0 + fV1) * 0.5 * fDtSec; // 梯形面积（除子 2.0 为常量，无除零风险）/ the trapezoid area with a constant divisor
    END_IF
END_FOR

// 段 4｜出口装配：跳过计数与钳位信息级、结果复检兜底（边界四）/ segment 4, the outlet assembly with the recheck
IF nSkipCnt > 0 THEN // 存在被跳过的段 / some segments were skipped
    eErr := 16#0001_0635; // 信息级：非有限点已跳段计数上报 / informational, the skipped segments counted
END_IF
IF (fArea <> fArea) OR ((fArea - fArea) <> (fArea - fArea)) THEN // 结果非有限（结构性不可达兜底）/ the result is not finite, kept as a guard
    fArea := 0.0; // 兜底安全值 / the bottom line safe value
    eErr := 16#0001_0636; // 故障级：结果非有限 / fault grade, the non finite result
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag
    bValid := FALSE; // 结果不可用 / the result void
    RETURN; // 早退 / early return
END_IF
bValid := TRUE; // 结果可用 / the result is usable
FC_DL_TrapezoidArea := TRUE; // 返回成功 / return success
END_FUNCTION
