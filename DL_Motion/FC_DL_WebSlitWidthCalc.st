(*
  Component : FC_DL_WebSlitWidthCalc
  Category  : DL_Motion
  Function  : 分切宽度与边料核算：母卷宽 − n×成品宽，给出最大条数、边料总量与单边余量
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rMotherWidthMm 母卷有效宽度 [mm]、rProductWidthMm 成品宽度 [mm]、nSlits 计划分条数 [条]、
             rMinTrimPerSideMm 单边最小边料 [mm]；
             输出 nSlitsMax 理论最大条数 [条]、rTrimTotalMm 边料总量 [mm]、rTrimPerSideMm 单边边料 [mm]、
             xFeasible 方案可行（边料满足单边下限）、xValid 有效标志、nFaultCode 故障码。
  边界     : 成品宽度为分母须 >1.0E-6 [mm]；母卷宽与成品宽须 >0；分条数须 0~999；
             最大条数用向下取整（TRUNC），禁向上取整（多切一条即成品超宽，属不可返工缺陷）；
             边料均分时单边 = 总量/2，奇数宽度余量取小于 0.5 mm 的尾差并入单边下限判定。
  码位     : 9801 输入非有限（故障级）；9802 宽度越域或分条数越界（故障级）。
*)
FUNCTION FC_DL_WebSlitWidthCalc : BOOL
VAR_INPUT
    rMotherWidthMm   : LREAL := 1500.0;   // 母卷有效宽度 [mm] EN: the usable mother roll width
    rProductWidthMm  : LREAL := 300.0;    // 成品宽度 [mm] EN: the finished slit width
    nSlits           : INT := 4;          // 计划分条数 [条] EN: the planned number of slits
    rMinTrimPerSideMm: LREAL := 5.0;      // 单边最小边料 [mm] EN: the minimum trim per side
END_VAR
VAR_OUTPUT
    nSlitsMax     : INT;                  // 理论最大分条数 [条] EN: the theoretical maximum slit count
    rTrimTotalMm  : LREAL;                // 边料总量 [mm] EN: the total trim width
    rTrimPerSideMm: LREAL;                // 单边边料 [mm] EN: the trim per side
    xFeasible     : BOOL;                 // 方案可行 EN: the plan is feasible
    xValid        : BOOL;                 // 输出可信标志 EN: the outputs are valid
    nFaultCode    : INT;                  // 0=无故障 9801=输入非有限 9802=宽度或分条数越域 EN: zero none, 9801 non finite, 9802 width or slit count out of range
END_VAR
VAR
    xFinAll : BOOL;                       // 三个浮点入参有限 EN: the three floating inputs are finite
    rQuot   : LREAL;                      // 母卷宽与成品宽的商 [-] EN: the quotient of the mother width and the product width
    rTrim   : LREAL;                      // 边料总量中间值 [mm] EN: the interim total trim
    rSide   : LREAL;                      // 单边边料中间值 [mm] EN: the interim trim per side
    nMax    : INT;                        // 最大条数中间值 [条] EN: the interim maximum slit count
END_VAR
VAR CONSTANT
    DL_WSW_Z        : LREAL := 0.0;       // 浮点零常量 EN: the floating point zero constant
    DL_WSW_TWO      : LREAL := 2.0;       // 单边均分系数 EN: the per side splitting factor
    DL_WSW_SLIT_MAX : INT := 999;         // 分条数上限 [条] EN: the upper bound of the slit count
    DL_WSW_SLIT_MAXF: LREAL := 999.0;     // 分条数上限的实数值（转整前兜底） [条] EN: the real valued bound used before the integer conversion
    DL_WSW_MIN      : LREAL := 1.0E-6;    // 成品宽度下限 [mm] EN: the lower bound of the product width
    DL_WSW_C_BAD    : INT := 9801;        // 输入非有限 EN: a non finite input
    DL_WSW_C_RANGE  : INT := 9802;        // 宽度或分条数越域 EN: the width or the slit count is out of range
END_VAR

// 段1｜出口预置
FC_DL_WebSlitWidthCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
nSlitsMax := 0;                    // 最大条数预置零 [条] EN: preset the maximum slit count to zero
rTrimTotalMm := DL_WSW_Z;          // 边料总量预置零 [mm] EN: preset the total trim to zero
rTrimPerSideMm := DL_WSW_Z;        // 单边边料预置零 [mm] EN: preset the trim per side to zero
xFeasible := FALSE;                // 可行标志预置假 EN: preset the feasibility flag to false
xValid := FALSE;                   // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                   // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：三浮点入参全列（单边下限参与可行性判据）
xFinAll := (rMotherWidthMm = rMotherWidthMm) AND ((rMotherWidthMm - rMotherWidthMm) = DL_WSW_Z)
        AND (rProductWidthMm = rProductWidthMm) AND ((rProductWidthMm - rProductWidthMm) = DL_WSW_Z)
        AND (rMinTrimPerSideMm = rMinTrimPerSideMm) AND ((rMinTrimPerSideMm - rMinTrimPerSideMm) = DL_WSW_Z);   // 三输入有限性 EN: the finiteness of all three inputs
IF NOT xFinAll THEN                                                                                           // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_WSW_C_BAD;                                                                               // 非有限码 EN: the non finite code
    RETURN;                                                                                                   // 早退 EN: return early
END_IF

// 段3｜域闸：两宽度为正、成品宽过分母下限、单边下限非负、分条数 0~999
IF (rMotherWidthMm <= DL_WSW_Z) OR (ABS(rProductWidthMm) < DL_WSW_MIN)
   OR (rMinTrimPerSideMm < DL_WSW_Z) OR (nSlits < 0) OR (nSlits > DL_WSW_SLIT_MAX) THEN
    nFaultCode := DL_WSW_C_RANGE;                                                                             // 越域码 EN: the out of range code
    RETURN;                                                                                                   // 早退 EN: return early
END_IF

// 段4｜最大条数：向下取整（多切一条即成品超宽，故绝不上取整）
rQuot := rMotherWidthMm / rProductWidthMm;                                                                    // 商，分母已证正 [-] EN: the quotient, the divisor is proven positive
IF rQuot > DL_WSW_SLIT_MAXF THEN                                                                             // 实数上限兜底，防转 INT 溢出 EN: bound the real value before the integer conversion
    nMax := DL_WSW_SLIT_MAX;                                                                                 // 直接取上限 [条] EN: take the upper bound
ELSE
    nMax := LREAL_TO_INT(TRUNC(rQuot));                                                                      // 向下取整 [条] EN: truncate downwards
END_IF

// 段5｜按计划条数核算边料
rTrim := rMotherWidthMm - INT_TO_LREAL(nSlits) * rProductWidthMm;                                            // 边料总量 [mm] EN: the total trim
rSide := rTrim / DL_WSW_TWO;                                                                                 // 单边边料 [mm] EN: the trim per side
IF (rTrim <> rTrim) OR (rSide <> rSide) THEN                                                                  // 复检 EN: recheck
    nFaultCode := DL_WSW_C_RANGE;                                                                             // 复检失败码 EN: the recheck failure code
    RETURN;                                                                                                   // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF

// 段6｜出口：可行判据为「条数 ≥1 且 单边边料 ≥ 单边下限」
nSlitsMax := nMax;                                                                                           // 最大条数出口 [条] EN: the maximum slit count output
rTrimTotalMm := rTrim;                                                                                        // 边料总量出口 [mm] EN: the total trim output
rTrimPerSideMm := rSide;                                                                                      // 单边边料出口 [mm] EN: the trim per side output
xFeasible := (nSlits >= 1) AND (rSide >= rMinTrimPerSideMm);                                                  // 可行性判定 EN: the feasibility verdict
xValid := TRUE;                                                                                               // 结果可信 EN: the results are valid
FC_DL_WebSlitWidthCalc := TRUE;                                                                                // 返回真 EN: return true
END_FUNCTION
