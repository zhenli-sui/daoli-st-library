(*
  FC_DL_WeightedMeanCalc  —  数组加权平均（权重和防零） / Weighted mean over arrays with zero-sum guard
  分类 Category : DL_MathData
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-math — 统计底座族零检索深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 对前 nCnt 个元素计算 SUM(aVals[i] × aWeights[i]) / SUM(aWeights[i])；
                  2) LREAL 域累加；权重和 <= 0 或非有限 → 防除零拒绝，返回 0 + 故障级 03E1；
                  3) 非有限样本/权重元素跳过（不计入累加），剔除后仍有有效元素则正常出值
                  并置信息级 04A4；
                  4) nCnt <= 0 或越界（> 32）先行判界拒绝。
  边界 Boundary : ① 判界先行：nCnt 域检查在累加前完成，越界直接故障出口；
                  ② 除零防御：分母 fWSum 与 DL_WMC_TOL 比较后才做除法；
                  ③ 非有限判定用自反判（x <> x），禁近似阈值；
                  ④ 无 GVL 依赖：纯函数，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : 仅 Standard.library（ABS / LREAL 算术）
  码表 Error codes（段 0001，窗口 03E1 / 04A4）:
    16#0001_03E1 故障级：入参非法（nCnt <= 0 或 > 32，或有效权重和 <= 0 防除零拒绝），
                 返回 0，bValid = FALSE，bError = TRUE
    16#0001_04A4 信息级：非有限元素已剔除（剔除后仍有效，结果照常输出）
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 1 · 序号 4）
*)

FUNCTION FC_DL_WeightedMeanCalc : LREAL
VAR_INPUT
    aVals       : ARRAY[1..32] OF LREAL;   // 样本数组 [EU]，前 nCnt 个参与 / Sample array, first nCnt used
    aWeights    : ARRAY[1..32] OF LREAL;   // 权重数组 [无量纲]，与样本一一对应 / Weight array, one per sample
    nCnt        : INT;               // 参与元素数 [个]，域 1..32 / Element count, 1..32
END_VAR
VAR_OUTPUT
    eErr        : UDINT;             // 事件码，0 = 正常 / Event code
    bError      : BOOL;              // 故障级标志 / Fault-level flag
    bValid      : BOOL;              // 返回值是否可用 / Result usable flag
END_VAR
VAR
    nGuard      : INT;               // 循环守卫计数 [次] / Loop guard counter
    i           : INT;               // 循环游标 [索引] / Loop cursor
    fNum        : LREAL;             // 分子累加器 [EU·权] / Numerator accumulator
    fWSum       : LREAL;             // 分母权重和累加器 [无量纲] / Denominator weight accumulator
    bSkipped    : BOOL;              // 非有限元素剔除标志 / Non-finite element skipped flag
END_VAR
VAR CONSTANT
    DL_WMC_N_MAX     : INT := 32;               // 数组容量上限 [个] / Array capacity bound
    DL_WMC_GUARD_MAX : INT := 32;               // 守卫上限（须 >= N_MAX）/ Loop guard bound
    DL_WMC_TOL       : LREAL := 1.0E-12;        // 权重和有效阈 [无量纲] / Weight-sum validity threshold
    DL_WMC_ERR_IN    : UDINT := 16#0001_03E1;   // 故障级：入参非法 / Fault: invalid input
    DL_WMC_INFO_SKIP : UDINT := 16#0001_04A4;   // 信息级：非有限剔除 / Info: non-finite skipped
END_VAR

(* —— 段 1｜返回值与错误状态预置 —— *)
FC_DL_WeightedMeanCalc := 0.0;      // 缺省返回 0 / default return zero
eErr := 16#0000_0000;               // 预置无事件 / preset no event
bError := FALSE;                    // 预置无故障 / preset no fault
bValid := FALSE;                    // 预置不可用 / preset unusable
fNum := 0.0;                        // 分子清零 / clear numerator
fWSum := 0.0;                       // 分母清零 / clear denominator
bSkipped := FALSE;                  // 剔除标志清零 / clear skip flag
nGuard := 0;                        // 守卫清零（FC 局部量每次调用须显式初始化）/ clear guard
i := 0;                             // 游标清零 / clear cursor

(* —— 段 2｜判界先行：nCnt 域闸（越界直接故障出口） —— *)
IF (nCnt <= 0) OR (nCnt > DL_WMC_N_MAX) THEN
    eErr := DL_WMC_ERR_IN;          // 故障级：nCnt 界外
    bError := TRUE;                 // 故障码配对置位（R101）
    bValid := FALSE;                // 结果不可用
    RETURN;                         // 直接出口 / early exit
END_IF

(* —— 段 3｜单遍累加：非有限元素跳过，守卫计数防失控 —— *)
FOR i := 1 TO nCnt DO
    nGuard := nGuard + 1;           // 守卫递增 / guard increment
    IF nGuard > DL_WMC_GUARD_MAX THEN
        EXIT;                       // 守卫兜底退出（理论不可达）/ guard backstop
    END_IF
    IF (aVals[i] <> aVals[i]) OR (aWeights[i] <> aWeights[i])
       OR ((aVals[i] - aVals[i]) <> (aVals[i] - aVals[i]))
       OR ((aWeights[i] - aWeights[i]) <> (aWeights[i] - aWeights[i])) THEN
        bSkipped := TRUE;           // NaN 自反判 OR Inf 差值自减判：剔除非有限元素
    ELSE
        fNum := fNum + aVals[i] * aWeights[i];   // 分子累加（LREAL 域）/ numerator accumulate
        fWSum := fWSum + aWeights[i];            // 分母累加 / denominator accumulate
    END_IF
END_FOR

(* —— 段 4｜除零防御闸：有效权重和必须 > 阈值 —— *)
IF fWSum <= DL_WMC_TOL THEN
    eErr := DL_WMC_ERR_IN;          // 故障级：权重和为零（防除零拒绝）
    bError := TRUE;                 // 故障码配对置位（R101）
    bValid := FALSE;                // 结果不可用
    RETURN;                         // 直接出口 / early exit
END_IF

(* —— 段 5｜出口 —— *)
FC_DL_WeightedMeanCalc := fNum / fWSum;   // 加权平均（分母已过闸）/ weighted mean
IF bSkipped THEN
    eErr := DL_WMC_INFO_SKIP;       // 信息级：非有限剔除（不置 bError）/ info level
END_IF
bValid := TRUE;                     // 结果可用 / result usable
END_FUNCTION
