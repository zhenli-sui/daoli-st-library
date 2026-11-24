(*
  FC_DL_MapRangePiecewise3 —— 三段折线映射，分段斜率加断点连续校验
  分类：DL_Base | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：由 4 个断点（afX 单调递增）与对应 4 个输出值构造三段折线，按输入落在哪一段做线性插值；
        断点单调性即保证折线在断点处连续（左段右端值 = 右段左端值 = afY[i]）。
  契约：fIn 输入、afX 断点横坐标（必须严格递增）、afY 断点纵坐标；fOut 折线输出；返回 TRUE 表示可信。
  边界：① 断点严格递增校验（容差 DL_MW_EPS），否则判非法；② 所有断点与输入做非有限闸；
        ③ 输入越两端断点时钳到端点（不外插）；④ 除零防护：段跨度经单调性闸后恒 > 0；
        ⑤ 零全局、零物理地址、零库件依赖；数组为显式定长（R15）。
*)
FUNCTION FC_DL_MapRangePiecewise3 : BOOL
VAR_INPUT
    fIn  : LREAL := 0.0;                             // 输入值 [输入量程单位] / The input value
    afX  : ARRAY[0..3] OF LREAL;                     // 四个断点横坐标（严格递增） [输入量程单位] / The breakpoints
    afY  : ARRAY[0..3] OF LREAL;                     // 四个断点纵坐标 [输出量程单位] / The breakpoint outputs
END_VAR
VAR_OUTPUT
    fOut  : LREAL;                                   // 折线输出 [输出量程单位] / The piecewise output
    nSeg  : INT;                                     // 命中段号（0..2） [下标] / The hit segment index
END_VAR
VAR
    xBad  : BOOL;                                    // 参数非法标志 [—] / The parameter invalid flag
    xFound : BOOL;                                   // 命中段查找标志 [—] / The hit segment search flag
    i     : INT;                                     // 遍历索引 [下标] / The traversal index
    k     : INT;                                     // 命中段索引 [下标] / The hit segment index
    fSpan : LREAL;                                   // 命中段的横坐标跨度 [输入量程单位] / The segment span
END_VAR
VAR CONSTANT
    DL_MW_EPS  : LREAL := 1.0E-9;                    // 浮点比较容差 [-] / The floating point comparison tolerance
    DL_MW_INF  : LREAL := 1.0E30;                    // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_MW_Z    : LREAL := 0.0;                       // 浮点零常量 [-] / The floating point zero constant
    DL_MW_N    : INT := 3;                           // 折线段数 [段] / The number of segments
    DL_MW_I0   : INT := 0;                           // 下标零 [下标] / The index zero
END_VAR

FC_DL_MapRangePiecewise3 := FALSE;                    // 返回值预置假 / preset the return false
fOut := DL_MW_Z;                                      // 输出预置零哨兵 / preset the zero sentinel
nSeg := DL_MW_I0;                                     // 段号预置零 [下标] / preset the segment index zero
xBad := FALSE;                                        // 非法标志预置假 / preset the invalid flag false
IF (fIn <> fIn) OR (ABS(fIn) > DL_MW_INF) THEN        // 输入非有限闸 / the input gate
    xBad := TRUE;                                     // 置非法标志 / raise the invalid flag
END_IF
FOR i := DL_MW_I0 TO DL_MW_N DO                       // 四个断点逐一校验 / check every breakpoint
    IF (afX[i] <> afX[i]) OR (ABS(afX[i]) > DL_MW_INF) THEN // 横坐标非有限 / the abscissa is not finite
        xBad := TRUE;                                 // 置非法标志 / raise the invalid flag
    END_IF
    IF (afY[i] <> afY[i]) OR (ABS(afY[i]) > DL_MW_INF) THEN // 纵坐标非有限 / the ordinate is not finite
        xBad := TRUE;                                 // 置非法标志 / raise the invalid flag
    END_IF
END_FOR
FOR i := DL_MW_I0 TO DL_MW_N - 1 DO                   // 相邻断点严格递增校验 / strictly increasing check
    IF (afX[i + 1] - afX[i]) < DL_MW_EPS THEN         // 跨度非正（含重合断点） / a non positive span
        xBad := TRUE;                                 // 置非法标志 / raise the invalid flag
    END_IF
END_FOR
IF NOT xBad THEN                                      // 参数全通过才插值 / interpolate when all parameters pass
    IF fIn <= afX[DL_MW_I0] THEN                      // 低于最低断点，钳到端点 / below the lowest breakpoint
        fOut := afY[DL_MW_I0];                        // 取最低断点输出 [输出量程单位] / take the lowest output
        nSeg := DL_MW_I0;                             // 段号记零 [下标] / the segment index is zero
    ELSIF fIn >= afX[DL_MW_N] THEN                    // 高于最高断点，钳到端点 / above the highest breakpoint
        fOut := afY[DL_MW_N];                         // 取最高断点输出 [输出量程单位] / take the highest output
        nSeg := DL_MW_N - 1;                          // 段号记末段 [下标] / the last segment index
    ELSE
        k := DL_MW_I0;                                // 段索引从零起 / the segment index starts at zero
        xFound := FALSE;                              // 命中标志预置假 / preset the hit flag false
        WHILE (k <= DL_MW_N - 1) AND NOT xFound DO    // 显式递增查找命中段（有界） / find the hit segment
            IF fIn < afX[k + 1] THEN                  // 落在第 k 段内 / inside the k th segment
                xFound := TRUE;                       // 置命中标志 / raise the hit flag
            ELSE
                k := k + 1;                           // 继续下一段 / advance to the next segment
            END_IF
        END_WHILE
        IF k > DL_MW_N - 1 THEN                       // 命中段上越界兜底 / the hit index fallback
            k := DL_MW_N - 1;                         // 钳到末段 [下标] / clamp to the last segment
        END_IF
        fSpan := afX[k + 1] - afX[k];                 // 命中段跨度（已证 > 容差） [输入量程单位] / the segment span
        fOut := afY[k] + ((fIn - afX[k]) / fSpan) * (afY[k + 1] - afY[k]); // 段内线性插值 [输出量程单位]
        nSeg := k;                                    // 段号出口 [下标] / publish the hit segment
    END_IF
    FC_DL_MapRangePiecewise3 := TRUE;                 // 插值成功 / the interpolation succeeded
ELSE
    fOut := DL_MW_Z;                                  // 非法参数输出零哨兵 [输出量程单位] / the sentinel
    FC_DL_MapRangePiecewise3 := FALSE;                // 结果不可信 / the result is not valid
END_IF
END_FUNCTION
