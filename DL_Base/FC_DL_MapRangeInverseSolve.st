(*
  FC_DL_MapRangeInverseSolve —— 由工程值反解原始量程值，含钳位
  分类：DL_Base | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：正向映射 out = fOutMin + (in - fInMin)/(fInMax - fInMin) * (fOutMax - fOutMin) 的逆解：
        raw = fInMin + (fOut - fOutMin) * (fInMax - fInMin) / (fOutMax - fOutMin)。
  契约：fEng 工程值输入 [输出量程单位]、fInMin/fInMax 原始量程端点、fOutMin/fOutMax 工程量程端点；
        fRaw 反解结果 [原始量程单位]（钳在原始量程内）；返回 TRUE 表示可信。
  边界：① 除零防护：分母 fOutSpan 过退化闸后才做除法；② 反解结果按原始量程钳位；
        ③ 五个浮点入参逐一非有限闸；④ 零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_MapRangeInverseSolve : BOOL
VAR_INPUT
    fEng    : LREAL := 0.0;            // 工程值输入 [输出量程单位] / The engineering value input
    fInMin  : LREAL := 0.0;            // 原始量程下端点 [原始量程单位] / The raw range low end
    fInMax  : LREAL := 100.0;          // 原始量程上端点 [原始量程单位] / The raw range high end
    fOutMin : LREAL := 0.0;            // 工程量程下端点 [输出量程单位] / The engineering range low end
    fOutMax : LREAL := 100.0;          // 工程量程上端点 [输出量程单位] / The engineering range high end
END_VAR
VAR_OUTPUT
    fRaw : LREAL;                      // 反解结果 [原始量程单位] / The solved raw value
END_VAR
VAR
    xBad      : BOOL;                  // 参数非法标志 [—] / The parameter invalid flag
    fEngClamp : LREAL;                 // 钳位后的工程值 [输出量程单位] / The clamped engineering value
    fOutSpan  : LREAL;                 // 工程量程跨度 [输出量程单位] / The engineering span
    fInSpan   : LREAL;                 // 原始量程跨度 [原始量程单位] / The raw span
    fRawCalc  : LREAL;                 // 未钳位的反解结果 [原始量程单位] / The unclamped solved value
END_VAR
VAR CONSTANT
    DL_MI_EPS : LREAL := 1.0E-9;       // 浮点比较容差 [-] / The floating point comparison tolerance
    DL_MI_INF : LREAL := 1.0E30;       // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_MI_Z   : LREAL := 0.0;          // 浮点零常量 [-] / The floating point zero constant
END_VAR

FC_DL_MapRangeInverseSolve := FALSE;                      // 返回值预置假 / preset the return false
fRaw := fInMin;                                           // 输出预置为原始量程下端点哨兵 / preset the raw low end sentinel
xBad := FALSE;                                            // 非法标志预置假 / preset the invalid flag false
IF (fEng <> fEng) OR (ABS(fEng) > DL_MI_INF) THEN         // 工程值非有限闸 / the engineering value gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fInMin <> fInMin) OR (ABS(fInMin) > DL_MI_INF) THEN   // 原始下端非有限闸 / the raw low end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fInMax <> fInMax) OR (ABS(fInMax) > DL_MI_INF) THEN   // 原始上端非有限闸 / the raw high end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fOutMin <> fOutMin) OR (ABS(fOutMin) > DL_MI_INF) THEN // 工程下端非有限闸 / the engineering low end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fOutMax <> fOutMax) OR (ABS(fOutMax) > DL_MI_INF) THEN // 工程上端非有限闸 / the engineering high end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
fOutSpan := fOutMax - fOutMin;                            // 工程量程跨度 [输出量程单位] / the engineering span
fInSpan := fInMax - fInMin;                               // 原始量程跨度 [原始量程单位] / the raw span
IF ABS(fOutSpan) < DL_MI_EPS THEN                         // 工程跨度退化（除零防护） / the degenerate engineering span
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF NOT xBad THEN                                          // 参数全通过才反解 / solve only when all parameters pass
    fEngClamp := fEng;                                    // 工程值接管 [输出量程单位] / take the engineering value
    IF fOutSpan > DL_MI_Z THEN                            // 正常方向 / the normal direction
        IF fEngClamp < fOutMin THEN                       // 低于工程下端点 / below the engineering low end
            fEngClamp := fOutMin;                         // 钳到工程下端点 [输出量程单位] / clamp to the low end
        END_IF
        IF fEngClamp > fOutMax THEN                       // 高于工程上端点 / above the engineering high end
            fEngClamp := fOutMax;                         // 钳到工程上端点 [输出量程单位] / clamp to the high end
        END_IF
    ELSE                                                  // 反向工程跨度 / the reversed engineering span
        IF fEngClamp > fOutMin THEN                       // 高于工程下端点 / above the engineering low end
            fEngClamp := fOutMin;                         // 钳到工程下端点 [输出量程单位] / clamp to the low end
        END_IF
        IF fEngClamp < fOutMax THEN                       // 低于工程上端点 / below the engineering high end
            fEngClamp := fOutMax;                         // 钳到工程上端点 [输出量程单位] / clamp to the high end
        END_IF
    END_IF
    fRawCalc := fInMin + ((fEngClamp - fOutMin) / fOutSpan) * fInSpan; // 反解（分母已证非零） [原始量程单位]
    IF fInMax >= fInMin THEN                              // 原始量程正常方向 / the normal raw direction
        IF fRawCalc < fInMin THEN                         // 反解低于原始下端点 / below the raw low end
            fRawCalc := fInMin;                           // 钳到原始下端点 [原始量程单位] / clamp to the low end
        END_IF
        IF fRawCalc > fInMax THEN                         // 反解高于原始上端点 / above the raw high end
            fRawCalc := fInMax;                           // 钳到原始上端点 [原始量程单位] / clamp to the high end
        END_IF
    ELSE                                                  // 原始量程反向 / the reversed raw range
        IF fRawCalc > fInMin THEN                         // 反解高于原始下端点 / above the raw low end
            fRawCalc := fInMin;                           // 钳到原始下端点 [原始量程单位] / clamp to the low end
        END_IF
        IF fRawCalc < fInMax THEN                         // 反解低于原始上端点 / below the raw high end
            fRawCalc := fInMax;                           // 钳到原始上端点 [原始量程单位] / clamp to the high end
        END_IF
    END_IF
    fRaw := fRawCalc;                                     // 反解结果出口 [原始量程单位] / publish the solved value
    FC_DL_MapRangeInverseSolve := TRUE;                   // 反解成功 / the solve succeeded
ELSE
    fRaw := fInMin;                                       // 非法参数输出原始下端点哨兵 [原始量程单位] / the sentinel
    FC_DL_MapRangeInverseSolve := FALSE;                  // 结果不可信 / the result is not valid
END_IF
END_FUNCTION
