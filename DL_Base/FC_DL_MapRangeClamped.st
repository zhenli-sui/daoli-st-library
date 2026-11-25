(*
  FC_DL_MapRangeClamped —— 双端量程映射并对输入钳位
  分类：DL_Base | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：把 [fInMin, fInMax] 内的输入线性映射到 [fOutMin, fOutMax]，输入越界时先钳到输入量程端点再映射。
  契约：fIn 输入 [输入量程单位]、fInMin/fInMax 输入量程端点、fOutMin/fOutMax 输出量程端点；
        fOut 映射结果 [输出量程单位]；返回 TRUE 表示 fOut 可信。
  边界：① 量程退化校验 fInMax <> fInMin（容差 DL_MR_EPS），退化时 fOut 给 fOutMin 且返回 FALSE；
        ② 除零防护：除数 fSpanIn 已过退化闸才做除法；③ 六个浮点入参逐一非有限闸；
        ④ 零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_MapRangeClamped : BOOL
VAR_INPUT
    fIn     : LREAL := 0.0;            // 输入值 [输入量程单位] / The input value in the input range unit
    fInMin  : LREAL := 0.0;            // 输入量程下端点 [输入量程单位] / The input range low end
    fInMax  : LREAL := 100.0;          // 输入量程上端点 [输入量程单位] / The input range high end
    fOutMin : LREAL := 0.0;            // 输出量程下端点 [输出量程单位] / The output range low end
    fOutMax : LREAL := 100.0;          // 输出量程上端点 [输出量程单位] / The output range high end
END_VAR
VAR_OUTPUT
    fOut : LREAL;                      // 映射结果 [输出量程单位] / The mapped value in the output range unit
END_VAR
VAR
    xBad     : BOOL;                   // 参数非法标志 [—] / The parameter invalid flag
    fInClamp : LREAL;                  // 钳位后的输入 [输入量程单位] / The clamped input value
    fSpanIn  : LREAL;                  // 输入量程跨度 [输入量程单位] / The input span
    fSpanOut : LREAL;                  // 输出量程跨度 [输出量程单位] / The output span
END_VAR
VAR CONSTANT
    DL_MR_EPS : LREAL := 1.0E-9;       // 浮点比较容差 [-] / The floating point comparison tolerance
    DL_MR_INF : LREAL := 1.0E30;       // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_MR_Z   : LREAL := 0.0;          // 浮点零常量 [-] / The floating point zero constant
    DL_MR_ONE : LREAL := 1.0;          // 浮点一常量 [-] / The floating point one constant
END_VAR

FC_DL_MapRangeClamped := FALSE;                           // 返回值预置假 / preset the return false
fOut := fOutMin;                                          // 输出预置为输出下端点哨兵 / preset the low end sentinel
xBad := FALSE;                                            // 非法标志预置假 / preset the invalid flag false
IF (fIn <> fIn) OR (ABS(fIn) > DL_MR_INF) THEN            // 输入非有限闸 / the input gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fInMin <> fInMin) OR (ABS(fInMin) > DL_MR_INF) THEN   // 输入下端非有限闸 / the low end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fInMax <> fInMax) OR (ABS(fInMax) > DL_MR_INF) THEN   // 输入上端非有限闸 / the high end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fOutMin <> fOutMin) OR (ABS(fOutMin) > DL_MR_INF) THEN // 输出下端非有限闸 / the output low end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fOutMax <> fOutMax) OR (ABS(fOutMax) > DL_MR_INF) THEN // 输出上端非有限闸 / the output high end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
fSpanIn := fInMax - fInMin;                               // 输入量程跨度 [输入量程单位] / the input span
fSpanOut := fOutMax - fOutMin;                            // 输出量程跨度 [输出量程单位] / the output span
IF ABS(fSpanIn) < DL_MR_EPS THEN                          // 输入量程退化（除零防护） / the degenerate input span
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF NOT xBad THEN                                          // 参数全通过才映射 / map only when all parameters pass
    fInClamp := fIn;                                      // 输入接管 [输入量程单位] / take the input value
    IF fSpanIn > DL_MR_Z THEN                             // 正常量程方向 / the normal range direction
        IF fInClamp < fInMin THEN                         // 低于下端点 / below the low end
            fInClamp := fInMin;                           // 钳到下端点 [输入量程单位] / clamp to the low end
        END_IF
        IF fInClamp > fInMax THEN                         // 高于上端点 / above the high end
            fInClamp := fInMax;                           // 钳到上端点 [输入量程单位] / clamp to the high end
        END_IF
    ELSE                                                  // 反向量程（上端小于下端） / the reversed range
        IF fInClamp > fInMin THEN                         // 高于下端点 / above the low end
            fInClamp := fInMin;                           // 钳到下端点 [输入量程单位] / clamp to the low end
        END_IF
        IF fInClamp < fInMax THEN                         // 低于上端点 / below the high end
            fInClamp := fInMax;                           // 钳到上端点 [输入量程单位] / clamp to the high end
        END_IF
    END_IF
    fOut := fOutMin + ((fInClamp - fInMin) / fSpanIn) * fSpanOut; // 线性映射（分母已证非零） [输出量程单位]
    FC_DL_MapRangeClamped := TRUE;                        // 映射成功 / the mapping succeeded
ELSE
    fOut := fOutMin;                                      // 非法参数输出下端点哨兵 [输出量程单位] / the sentinel
    FC_DL_MapRangeClamped := FALSE;                       // 结果不可信 / the result is not valid
END_IF
END_FUNCTION
