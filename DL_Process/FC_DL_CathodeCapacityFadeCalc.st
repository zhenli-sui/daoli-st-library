(*
  Component : FC_DL_CathodeCapacityFadeCalc
  Category  : DL_Process
  Function  : 容量衰减 = 1 − Qn/Q0，并按模型选择给出线性或平方根预测衰减
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rQ0Ah 初始容量 [Ah]、rQnAh 第 n 圈容量 [Ah]、nCycles 循环圈数 [圈]、
             rFadePerCyclePct 线性模型每圈衰减率 [%/圈]、rSqrtCoefPct 平方根模型系数 [%/圈^0.5]、
             eModel 模型选择枚举；输出 rFadePct 实测衰减 [%]、rFadePredPct 模型预测衰减 [%]、
             xValid 有效标志、nFaultCode 故障码。
  边界     : 初始容量为分母须 >1.0E-9 [Ah]；圈数须 ≥1；两个模型系数须 ≥0；
             平方根模型用 SQRT(圈数) 实现，禁用幂运算方言；模型枚举未知值走 ELSE 兜底判 9803。
  码位     : 9801 输入非有限（故障级）；9802 初始容量或圈数非法（故障级）；9803 模型枚举未知或系数越域（故障级）。
*)
TYPE E_DL_CathodeFadeModel :
(
    eLinear := 0,    // 线性衰减模型：fade = k × n EN: the linear fade model
    eSqrt   := 1     // 平方根衰减模型：fade = c × √n EN: the square root fade model
);
END_TYPE

FUNCTION FC_DL_CathodeCapacityFadeCalc : BOOL
VAR_INPUT
    rQ0Ah          : LREAL := 5.0;     // 初始容量 [Ah] EN: the initial capacity of the cell
    rQnAh          : LREAL := 4.5;     // 第 n 圈容量 [Ah] EN: the capacity after the given number of cycles
    nCycles        : INT := 500;       // 循环圈数 [圈] EN: the number of cycles applied
    rFadePerCyclePct: LREAL := 0.02;   // 线性模型每圈衰减率 [%/圈] EN: the per cycle fade rate of the linear model
    rSqrtCoefPct   : LREAL := 0.4;     // 平方根模型系数 [%/圈^0.5] EN: the coefficient of the square root model
    eModel         : E_DL_CathodeFadeModel;   // 衰减模型选择 [-] EN: the fade model selection
END_VAR
VAR_OUTPUT
    rFadePct     : LREAL;              // 实测容量衰减 [%] EN: the measured capacity fade
    rFadePredPct : LREAL;              // 模型预测容量衰减 [%] EN: the capacity fade predicted by the selected model
    xValid       : BOOL;               // 输出可信标志 EN: the outputs are valid
    nFaultCode   : INT;                // 0=无故障 9801=输入非有限 9802=初始容量或圈数非法 9803=模型或系数越域 EN: zero none, 9801 non finite, 9802 capacity or cycles illegal, 9803 model or coefficient out of range
END_VAR
VAR
    xFinAll : BOOL;                    // 浮点入参同时有限 EN: the floating inputs are finite
    rDen    : LREAL;                   // 分母（初始容量） [Ah] EN: the divisor, the initial capacity
    rFade   : LREAL;                   // 实测衰减中间值 [%] EN: the interim measured fade
    rPred   : LREAL;                   // 预测衰减中间值 [%] EN: the interim predicted fade
    rN      : LREAL;                   // 圈数的实数形式 [圈] EN: the cycle count as a real number
    rSqrtN  : LREAL;                   // 圈数平方根 [圈^0.5] EN: the square root of the cycle count
END_VAR
VAR CONSTANT
    DL_CCF_Z        : LREAL := 0.0;    // 浮点零常量 EN: the floating point zero constant
    DL_CCF_ONE      : LREAL := 1.0;    // 浮点壹常量 EN: the floating point one constant
    DL_CCF_HUNDRED  : LREAL := 100.0;  // 百分数换算系数 EN: the percent conversion factor
    DL_CCF_MIN      : LREAL := 1.0E-9; // 分母绝对值下限 [Ah] EN: the lower bound of the divisor magnitude
    DL_CCF_C_BAD    : INT := 9801;     // 输入非有限 EN: a non finite input
    DL_CCF_C_DEN    : INT := 9802;     // 初始容量或圈数非法 EN: the initial capacity or the cycle count is illegal
    DL_CCF_C_MODEL  : INT := 9803;     // 模型或系数越域 EN: the model or the coefficient is out of range
END_VAR

// 段1｜出口预置
FC_DL_CathodeCapacityFadeCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rFadePct := DL_CCF_Z;                     // 实测衰减预置零 [%] EN: preset the measured fade to zero
rFadePredPct := DL_CCF_Z;                 // 预测衰减预置零 [%] EN: preset the predicted fade to zero
xValid := FALSE;                          // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                          // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：浮点入参全列（两模型系数参与换算，漏则模型输出可为 NaN）
xFinAll := (rQ0Ah = rQ0Ah) AND ((rQ0Ah - rQ0Ah) = DL_CCF_Z)
        AND (rQnAh = rQnAh) AND ((rQnAh - rQnAh) = DL_CCF_Z)
        AND (rFadePerCyclePct = rFadePerCyclePct) AND ((rFadePerCyclePct - rFadePerCyclePct) = DL_CCF_Z)
        AND (rSqrtCoefPct = rSqrtCoefPct) AND ((rSqrtCoefPct - rSqrtCoefPct) = DL_CCF_Z);   // 四浮点输入有限性 EN: the finiteness of the four floating inputs
IF NOT xFinAll THEN                                                                          // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_CCF_C_BAD;                                                              // 非有限码 EN: the non finite code
    RETURN;                                                                                  // 早退 EN: return early
END_IF

// 段3｜域闸：初始容量过分母下限、圈数 ≥1、容量非负、系数非负
rDen := rQ0Ah;                                                                               // 取分母 [Ah] EN: take the divisor
IF (ABS(rDen) < DL_CCF_MIN) OR (nCycles < 1) OR (rQnAh < DL_CCF_Z) THEN                      // 容量与圈数闸 EN: the capacity and cycle gate
    nFaultCode := DL_CCF_C_DEN;                                                              // 非法码 EN: the illegal code
    RETURN;                                                                                  // 早退 EN: return early
END_IF
IF (rFadePerCyclePct < DL_CCF_Z) OR (rSqrtCoefPct < DL_CCF_Z) THEN                           // 模型系数闸 EN: the model coefficient gate
    nFaultCode := DL_CCF_C_MODEL;                                                            // 系数越域码 EN: the coefficient code
    RETURN;                                                                                  // 早退 EN: return early
END_IF

// 段4｜实测衰减：fade = (1 − Qn/Q0) × 100，不钳位（负衰减表达容量回升，方向信息保留）
rFade := (DL_CCF_ONE - (rQnAh / rDen)) * DL_CCF_HUNDRED;                                     // 实测衰减 [%] EN: the measured fade

// 段5｜模型预测：ENUM + CASE 且 ELSE 兜底
rN := INT_TO_LREAL(nCycles);                                                                 // 圈数转实数 [圈] EN: the cycle count as a real number
CASE eModel OF
    E_DL_CathodeFadeModel.eLinear:
        rPred := rFadePerCyclePct * rN;                                                      // 线性模型 [%] EN: the linear model
    E_DL_CathodeFadeModel.eSqrt:
        rSqrtN := SQRT(rN);                                                                  // 圈数平方根，圈数已证 ≥1 [圈^0.5] EN: the square root, the count is proven at least one
        rPred := rSqrtCoefPct * rSqrtN;                                                      // 平方根模型 [%] EN: the square root model
ELSE
    nFaultCode := DL_CCF_C_MODEL;                                                            // 未知模型码 EN: the unknown model code
    rFadePct := rFade;                                                                       // 实测值仍可给出 [%] EN: the measured value is still published
    RETURN;                                                                                  // 早退 EN: return early
END_CASE

// 段6｜结果复检与出口
IF (rFade <> rFade) OR (rPred <> rPred) THEN                                                 // 复检：两路输出非有限 EN: recheck both outputs for a non finite value
    nFaultCode := DL_CCF_C_MODEL;                                                            // 复检失败码 EN: the recheck failure code
    RETURN;                                                                                  // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF
rFadePct := rFade;                                                                           // 实测衰减出口 [%] EN: the measured fade output
rFadePredPct := rPred;                                                                       // 预测衰减出口 [%] EN: the predicted fade output
xValid := TRUE;                                                                              // 结果可信 EN: the results are valid
FC_DL_CathodeCapacityFadeCalc := TRUE;                                                       // 返回真 EN: return true
END_FUNCTION
