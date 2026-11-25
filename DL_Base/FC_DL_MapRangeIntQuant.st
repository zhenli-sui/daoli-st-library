(*
  FC_DL_MapRangeIntQuant —— 量程映射加整数量化，步长加四舍五入
  分类：DL_Base | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：先把输入线性映射到输出量程（输入越界钳位），再按 fStep 步长量化到整数刻度：
        nTick = round(mapped / step)，fOut = nTick * step；fTick 为量化后的整数刻度。
  契约：fIn 输入、fInMin/fInMax 输入端点、fOutMin/fOutMax 输出端点、fStep 步长（必须 > 0）；
        fOut 量化结果 [输出量程单位]、fTick 整数刻度；返回 TRUE 表示可信。
  边界：① 步长零 / 负值前置判（除零防护）；② 量程退化校验（容差 DL_MQ_EPS）；
        ③ 六个浮点入参逐一非有限闸；④ 转整前对刻度做 ±1.0E6 上限兜底，避免 LREAL_TO_DINT 越域；
        ⑤ 零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_MapRangeIntQuant : BOOL
VAR_INPUT
    fIn     : LREAL := 0.0;            // 输入值 [输入量程单位] / The input value
    fInMin  : LREAL := 0.0;            // 输入量程下端点 [输入量程单位] / The input range low end
    fInMax  : LREAL := 100.0;          // 输入量程上端点 [输入量程单位] / The input range high end
    fOutMin : LREAL := 0.0;            // 输出量程下端点 [输出量程单位] / The output range low end
    fOutMax : LREAL := 100.0;          // 输出量程上端点 [输出量程单位] / The output range high end
    fStep   : LREAL := 1.0;            // 量化步长（必须 > 0） [输出量程单位] / The quantisation step
END_VAR
VAR_OUTPUT
    fOut  : LREAL;                     // 量化后的结果 [输出量程单位] / The quantised result
    fTick : LREAL;                     // 量化后的整数刻度值 [刻度] / The integer tick value as a real
END_VAR
VAR
    xBad     : BOOL;                   // 参数非法标志 [—] / The parameter invalid flag
    fInSpan  : LREAL;                  // 输入量程跨度 [输入量程单位] / The input span
    fMapped  : LREAL;                  // 未量化的映射值 [输出量程单位] / The mapped value
    fTicks   : LREAL;                  // 未取整的刻度 [刻度] / The raw tick count
    diTick   : DINT;                   // 四舍五入后的整数刻度 [刻度] / The rounded tick count
END_VAR
VAR CONSTANT
    DL_MQ_EPS  : LREAL := 1.0E-9;      // 浮点比较容差 [-] / The floating point comparison tolerance
    DL_MQ_INF  : LREAL := 1.0E30;      // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_MQ_TICK : LREAL := 1.0E6;       // 转整前的刻度上限兜底 [刻度] / The tick guard before conversion
    DL_MQ_HALF : LREAL := 0.5;         // 四舍五入偏置 [-] / The rounding bias
    DL_MQ_Z    : LREAL := 0.0;         // 浮点零常量 [-] / The floating point zero constant
END_VAR

FC_DL_MapRangeIntQuant := FALSE;                          // 返回值预置假 / preset the return false
fOut := fOutMin;                                          // 输出预置为输出下端点哨兵 / preset the low end sentinel
fTick := DL_MQ_Z;                                         // 刻度预置零 [刻度] / preset the tick zero
xBad := FALSE;                                            // 非法标志预置假 / preset the invalid flag false
IF (fIn <> fIn) OR (ABS(fIn) > DL_MQ_INF) THEN            // 输入非有限闸 / the input gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fInMin <> fInMin) OR (ABS(fInMin) > DL_MQ_INF) THEN   // 输入下端非有限闸 / the input low end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fInMax <> fInMax) OR (ABS(fInMax) > DL_MQ_INF) THEN   // 输入上端非有限闸 / the input high end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fOutMin <> fOutMin) OR (ABS(fOutMin) > DL_MQ_INF) THEN // 输出下端非有限闸 / the output low end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fOutMax <> fOutMax) OR (ABS(fOutMax) > DL_MQ_INF) THEN // 输出上端非有限闸 / the output high end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fStep <> fStep) OR (ABS(fStep) > DL_MQ_INF) THEN      // 步长非有限闸 / the step gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF fStep <= DL_MQ_EPS THEN                                // 步长非正（除零防护） / the step is not positive
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
fInSpan := fInMax - fInMin;                               // 输入量程跨度 [输入量程单位] / the input span
IF ABS(fInSpan) < DL_MQ_EPS THEN                          // 输入量程退化（除零防护） / the degenerate input span
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF NOT xBad THEN                                          // 参数全通过才映射量化 / map and quantise when all pass
    fMapped := fIn;                                       // 输入接管 [输入量程单位] / take the input value
    IF fInSpan > DL_MQ_Z THEN                             // 正常量程方向 / the normal direction
        IF fMapped < fInMin THEN                          // 低于下端点 / below the low end
            fMapped := fInMin;                            // 钳到下端点 [输入量程单位] / clamp to the low end
        END_IF
        IF fMapped > fInMax THEN                          // 高于上端点 / above the high end
            fMapped := fInMax;                            // 钳到上端点 [输入量程单位] / clamp to the high end
        END_IF
    ELSE                                                  // 反向量程 / the reversed direction
        IF fMapped > fInMin THEN                          // 高于下端点 / above the low end
            fMapped := fInMin;                            // 钳到下端点 [输入量程单位] / clamp to the low end
        END_IF
        IF fMapped < fInMax THEN                          // 低于上端点 / below the high end
            fMapped := fInMax;                            // 钳到上端点 [输入量程单位] / clamp to the high end
        END_IF
    END_IF
    fMapped := fOutMin + ((fMapped - fInMin) / fInSpan) * (fOutMax - fOutMin); // 线性映射（分母已证非零）
    fTicks := fMapped / fStep;                            // 换算成刻度数（步长已证正） [刻度] / the raw tick count
    IF fTicks > DL_MQ_TICK THEN                           // 刻度上越界，转整前兜底 / the positive tick guard
        fTicks := DL_MQ_TICK;                             // 钳到刻度上限 [刻度] / clamp the tick count
    END_IF
    IF fTicks < -DL_MQ_TICK THEN                          // 刻度下越界，转整前兜底 / the negative tick guard
        fTicks := -DL_MQ_TICK;                            // 钳到刻度下限 [刻度] / clamp the tick count
    END_IF
    IF fTicks >= DL_MQ_HALF THEN                          // 非负四舍五入 / non negative rounding
        diTick := LREAL_TO_DINT(fTicks + DL_MQ_HALF);     // 加半后截断 [刻度] / add a half then truncate
    ELSIF fTicks <= -DL_MQ_HALF THEN                      // 非正四舍五入 / non positive rounding
        diTick := LREAL_TO_DINT(fTicks - DL_MQ_HALF);     // 减半后截断 [刻度] / subtract a half then truncate
    ELSE
        diTick := 0;                                      // 近零带归零 [刻度] / the near zero band
    END_IF
    fTick := DINT_TO_LREAL(diTick);                       // 整数刻度出口 [刻度] / publish the integer tick
    fOut := fTick * fStep;                                // 量化结果还原 [输出量程单位] / restore the quantised value
    FC_DL_MapRangeIntQuant := TRUE;                       // 量化成功 / the quantisation succeeded
ELSE
    fOut := fOutMin;                                      // 非法参数输出下端点哨兵 [输出量程单位] / the sentinel
    fTick := DL_MQ_Z;                                     // 刻度输出零哨兵 [刻度] / the tick sentinel
    FC_DL_MapRangeIntQuant := FALSE;                      // 结果不可信 / the result is not valid
END_IF
END_FUNCTION
