(*
  Component : FC_DL_ReProductPurityCalc
  Category  : DL_Process
  Function  : 产品纯度 = (1 - Σ杂质/总量) × 100，并给出合格判定
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 afImpPpm 杂质浓度定长数组 [ppm]（ARRAY[0..7]，R15 显式定长）、nImpCount 有效杂质个数 [个]、
             rTotalPpm 总量基准 [ppm]、rPuritySpecPct 纯度合格下限 [%]；
             输出 rImpSumPpm 杂质合计 [ppm]、rPurityPct 产品纯度 [%]、xPass 合格、
             xClamped 本拍钳位、xValid 有效标志、nFaultCode 故障码。
  边界     : 数组固定 8 元素，nImpCount 须在 0..8 内，越界判 9803 并拒绝访问；总量基准须 >1.0E-9 [ppm] 判 9802；
             任一有效元素非有限判 9801；纯度钳位 0~100 [%]；杂质合计超过总量时纯度钳到零并置 xClamped。
  码位     : 9801 元素非有限（故障级）；9802 总量基准过小（故障级）；9803 杂质个数越界（故障级）。
*)
FUNCTION FC_DL_ReProductPurityCalc : BOOL
VAR_INPUT
    afImpPpm      : ARRAY[0..7] OF LREAL;   // 杂质浓度定长数组，未用槽填零 [ppm] EN: the fixed impurity concentration array, unused slots hold zero
    nImpCount     : INT := 8;               // 有效杂质元素个数 [个] EN: the number of valid impurity elements
    rTotalPpm     : LREAL := 1000000.0;     // 总量基准（纯度分母） [ppm] EN: the total amount used as the purity divisor
    rPuritySpecPct: LREAL := 99.5;          // 纯度合格下限 [%] EN: the lower acceptance limit of the product purity
END_VAR
VAR_OUTPUT
    rImpSumPpm : LREAL;                     // 有效杂质合计 [ppm] EN: the sum of the valid impurities
    rPurityPct : LREAL;                     // 产品纯度，域 0~100 [%] EN: the product purity clamped to zero through one hundred
    xPass      : BOOL;                      // 纯度合格判定 EN: the purity acceptance verdict
    xClamped   : BOOL;                      // 本拍发生钳位 EN: a clamp occurred in this cycle
    xValid     : BOOL;                      // 输出可信标志 EN: the outputs are valid
    nFaultCode : INT;                       // 0=无故障 9801=元素非有限 9802=总量过小 9803=个数越界 EN: zero none, 9801 non finite element, 9802 total too small, 9803 count out of range
END_VAR
VAR
    xFinAll  : BOOL;                        // 全部元素有限（仅扫有效区） EN: every scanned element is finite
    xFinEl   : BOOL;                        // 单元素有限性 EN: the finiteness of one element
    i        : INT;                         // 杂质数组循环索引 [个] EN: the impurity array loop index
    nScan    : INT;                         // 实际扫描个数 [个] EN: the effective scan count
    rSum     : LREAL;                       // 杂质累加器 [ppm] EN: the impurity accumulator
    rRatio   : LREAL;                       // 杂质占总量比例 [-] EN: the impurity fraction of the total
    rPur     : LREAL;                       // 纯度中间值 [%] EN: the interim purity value
END_VAR
VAR CONSTANT
    DL_RPP_Z        : LREAL := 0.0;         // 浮点零常量 EN: the floating point zero constant
    DL_RPP_ONE      : LREAL := 1.0;         // 浮点壹常量 EN: the floating point one constant
    DL_RPP_HUNDRED  : LREAL := 100.0;       // 百分数换算系数 EN: the percent conversion factor
    DL_RPP_IDX_MAX  : INT := 7;             // 数组上界索引 [个] EN: the array upper bound index
    DL_RPP_CNT_MAX  : INT := 8;             // 允许的杂质个数上限 [个] EN: the allowed upper bound of the impurity count
    DL_RPP_C_BAD    : INT := 9801;          // 元素非有限 EN: a non finite element
    DL_RPP_C_TOTAL  : INT := 9802;          // 总量过小 EN: the total amount is too small
    DL_RPP_C_INDEX  : INT := 9803;          // 杂质个数越界 EN: the impurity count is out of range
END_VAR

// 段1｜出口预置
FC_DL_ReProductPurityCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rImpSumPpm := DL_RPP_Z;               // 杂质合计预置零 [ppm] EN: preset the impurity sum to zero
rPurityPct := DL_RPP_Z;               // 纯度预置零 [%] EN: preset the purity to zero
xPass := FALSE;                       // 合格标志预置假 EN: preset the acceptance flag to false
xClamped := FALSE;                    // 钳位标志预置假 EN: preset the clamp flag to false
xValid := FALSE;                      // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                      // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：三个标量入参全列（合格下限参与出口判据）
xFinAll := (rTotalPpm = rTotalPpm) AND ((rTotalPpm - rTotalPpm) = DL_RPP_Z)
        AND (rPuritySpecPct = rPuritySpecPct) AND ((rPuritySpecPct - rPuritySpecPct) = DL_RPP_Z);   // 标量有限性 EN: the finiteness of the scalar inputs
IF NOT xFinAll THEN                                                                                 // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_RPP_C_BAD;                                                                     // 输入非法码 EN: the illegal input code
    RETURN;                                                                                         // 早退 EN: return early
END_IF

// 段3｜域闸：杂质个数在 0..8 内（越界一律拒绝访问，不做截断放行）
IF (nImpCount < 0) OR (nImpCount > DL_RPP_CNT_MAX) OR (ABS(rTotalPpm) < 1.0E-9) THEN                  // 索引与分母域闸 EN: the index and divisor domain gate
    IF (nImpCount < 0) OR (nImpCount > DL_RPP_CNT_MAX) THEN                                          // 区分越界与分母两类成因 EN: separate the index cause from the divisor cause
        nFaultCode := DL_RPP_C_INDEX;                                                                // 个数越界码 EN: the count out of range code
    ELSE
        nFaultCode := DL_RPP_C_TOTAL;                                                                // 总量过小码 EN: the total too small code
    END_IF
    RETURN;                                                                                          // 早退 EN: return early
END_IF

// 段4｜主体：扫有效区累加杂质，逐元素过非有限闸（非有限拒收，不参与累加）
rSum := DL_RPP_Z;                                                                                    // 累加器清零 [ppm] EN: clear the accumulator
nScan := nImpCount;                                                                                  // 扫描个数 [个] EN: the scan count
xFinAll := TRUE;                                                                                     // 假定全部有限 EN: assume every element is finite
FOR i := 0 TO nScan - 1 DO                                                                           // 定长数组循环，nScan 已证 ≤8 EN: the fixed array loop, the count is proven at most eight
    IF (i >= 0) AND (i <= DL_RPP_IDX_MAX) THEN                                                       // 逐元素双边界校验 EN: the per element bound check
        xFinEl := (afImpPpm[i] = afImpPpm[i]) AND ((afImpPpm[i] - afImpPpm[i]) = DL_RPP_Z);          // 元素有限性 EN: the element finiteness
        IF xFinEl THEN                                                                               // 有限才累加 EN: accumulate only finite values
            rSum := rSum + afImpPpm[i];                                                              // 累加杂质 [ppm] EN: accumulate the impurity
        ELSE
            xFinAll := FALSE;                                                                        // 记非有限 EN: mark the non finite element
        END_IF
    END_IF
END_FOR
IF NOT xFinAll THEN                                                                                  // 存在非有限元素 EN: some element is not finite
    nFaultCode := DL_RPP_C_BAD;                                                                      // 元素非有限码 EN: the non finite element code
    rImpSumPpm := DL_RPP_Z;                                                                          // 合计复位零哨兵 [ppm] EN: reset the sum to the zero sentinel
    RETURN;                                                                                          // 早退 EN: return early
END_IF

// 段5｜纯度：先算比例再钳位（负比例来自负杂质输入，属组态错误，钳零并留痕）
rRatio := rSum / rTotalPpm;                                                                          // 杂质比例，分母已过下限 [-] EN: the impurity fraction, the divisor passed the gate
rPur := (DL_RPP_ONE - rRatio) * DL_RPP_HUNDRED;                                                      // 纯度 [%] EN: the purity
IF rPur < DL_RPP_Z THEN                                                                              // 下钳位 EN: clamp the lower bound
    rPur := DL_RPP_Z;                                                                                // 钳到零 [%] EN: clamp to zero
    xClamped := TRUE;                                                                                // 置钳位标志 EN: raise the clamp flag
END_IF
IF rPur > DL_RPP_HUNDRED THEN                                                                        // 上钳位 EN: clamp the upper bound
    rPur := DL_RPP_HUNDRED;                                                                          // 钳到一百 [%] EN: clamp to one hundred
    xClamped := TRUE;                                                                                // 置钳位标志 EN: raise the clamp flag
END_IF

// 段6｜出口：名实双出口同源，合格判定用钳位后的纯度
rImpSumPpm := rSum;                                                                                  // 合计出口 [ppm] EN: the impurity sum output
rPurityPct := rPur;                                                                                  // 纯度出口 [%] EN: the purity output
xPass := rPur >= rPuritySpecPct;                                                                     // 合格判定 EN: the acceptance verdict
xValid := TRUE;                                                                                      // 结果可信 EN: the results are valid
FC_DL_ReProductPurityCalc := TRUE;                                                                   // 返回真 EN: return true
END_FUNCTION
