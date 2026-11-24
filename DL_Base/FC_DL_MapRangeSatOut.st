(*
  FC_DL_MapRangeSatOut —— 输入量程映射后对输出独立饱和限幅
  分类：DL_Base | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：先做 [fInMin, fInMax] → [fOutMin, fOutMax] 的线性映射（输入先钳到量程），
        再把映射结果独立钳到执行机构允许的 [fSatMin, fSatMax]（该区间可比输出量程更窄）。
  契约：fIn 输入、fInMin/fInMax 输入端点、fOutMin/fOutMax 输出端点、fSatMin/fSatMax 输出饱和限；
        fOut 结果；xSat 报告输出侧发生饱和；返回 TRUE 表示可信。
  边界：① 输入量程与饱和区间双退化校验（容差 DL_MS_EPS）；② 八个浮点入参逐一非有限闸；
        ③ 除零防护：除以 fInSpan 前已过退化闸；④ 零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_MapRangeSatOut : BOOL
VAR_INPUT
    fIn     : LREAL := 0.0;            // 输入值 [输入量程单位] / The input value
    fInMin  : LREAL := 0.0;            // 输入量程下端点 [输入量程单位] / The input range low end
    fInMax  : LREAL := 100.0;          // 输入量程上端点 [输入量程单位] / The input range high end
    fOutMin : LREAL := 0.0;            // 输出量程下端点 [输出量程单位] / The output range low end
    fOutMax : LREAL := 100.0;          // 输出量程上端点 [输出量程单位] / The output range high end
    fSatMin : LREAL := 0.0;            // 输出饱和下限 [输出量程单位] / The output saturation low limit
    fSatMax : LREAL := 100.0;          // 输出饱和上限 [输出量程单位] / The output saturation high limit
END_VAR
VAR_OUTPUT
    fOut : LREAL;                      // 结果（含输出侧饱和） [输出量程单位] / The saturated result
    xSat : BOOL;                       // 输出侧发生饱和 [—] / The output stage saturated
END_VAR
VAR
    xBad      : BOOL;                  // 参数非法标志 [—] / The parameter invalid flag
    fInClamp  : LREAL;                 // 钳位后的输入 [输入量程单位] / The clamped input
    fInSpan   : LREAL;                 // 输入量程跨度 [输入量程单位] / The input span
    fMapped   : LREAL;                 // 未限幅的映射结果 [输出量程单位] / The mapped value before limiting
END_VAR
VAR CONSTANT
    DL_MS_EPS : LREAL := 1.0E-9;       // 浮点比较容差 [-] / The floating point comparison tolerance
    DL_MS_INF : LREAL := 1.0E30;       // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_MS_Z   : LREAL := 0.0;          // 浮点零常量 [-] / The floating point zero constant
END_VAR

FC_DL_MapRangeSatOut := FALSE;                            // 返回值预置假 / preset the return false
fOut := fOutMin;                                          // 输出预置为输出下端点哨兵 / preset the low end sentinel
xSat := FALSE;                                            // 饱和标志预置假 / preset the saturation flag false
xBad := FALSE;                                            // 非法标志预置假 / preset the invalid flag false
IF (fIn <> fIn) OR (ABS(fIn) > DL_MS_INF) THEN            // 输入非有限闸 / the input gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fInMin <> fInMin) OR (ABS(fInMin) > DL_MS_INF) THEN   // 输入下端非有限闸 / the input low end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fInMax <> fInMax) OR (ABS(fInMax) > DL_MS_INF) THEN   // 输入上端非有限闸 / the input high end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fOutMin <> fOutMin) OR (ABS(fOutMin) > DL_MS_INF) THEN // 输出下端非有限闸 / the output low end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fOutMax <> fOutMax) OR (ABS(fOutMax) > DL_MS_INF) THEN // 输出上端非有限闸 / the output high end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fSatMin <> fSatMin) OR (ABS(fSatMin) > DL_MS_INF) THEN // 饱和下限非有限闸 / the saturation low gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fSatMax <> fSatMax) OR (ABS(fSatMax) > DL_MS_INF) THEN // 饱和上限非有限闸 / the saturation high gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
fInSpan := fInMax - fInMin;                               // 输入量程跨度 [输入量程单位] / the input span
IF ABS(fInSpan) < DL_MS_EPS THEN                          // 输入量程退化（除零防护） / the degenerate input span
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF fSatMax < fSatMin THEN                                 // 饱和区间倒置 / the saturated band is inverted
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF NOT xBad THEN                                          // 参数全通过才映射 / map only when all parameters pass
    fInClamp := fIn;                                      // 输入接管 [输入量程单位] / take the input value
    IF fInSpan > DL_MS_Z THEN                             // 正常量程方向 / the normal direction
        IF fInClamp < fInMin THEN                         // 低于下端点 / below the low end
            fInClamp := fInMin;                           // 钳到下端点 [输入量程单位] / clamp to the low end
        END_IF
        IF fInClamp > fInMax THEN                         // 高于上端点 / above the high end
            fInClamp := fInMax;                           // 钳到上端点 [输入量程单位] / clamp to the high end
        END_IF
    ELSE                                                  // 反向量程 / the reversed direction
        IF fInClamp > fInMin THEN                         // 高于下端点 / above the low end
            fInClamp := fInMin;                           // 钳到下端点 [输入量程单位] / clamp to the low end
        END_IF
        IF fInClamp < fInMax THEN                         // 低于上端点 / below the high end
            fInClamp := fInMax;                           // 钳到上端点 [输入量程单位] / clamp to the high end
        END_IF
    END_IF
    fMapped := fOutMin + ((fInClamp - fInMin) / fInSpan) * (fOutMax - fOutMin); // 线性映射（分母已证非零）
    fOut := fMapped;                                      // 映射值接入输出侧限幅 [输出量程单位] / take the mapped value
    IF fMapped > fSatMax THEN                             // 输出侧上饱和 / the output stage saturates high
        fOut := fSatMax;                                  // 钳到饱和上限 [输出量程单位] / clamp to the high limit
        xSat := TRUE;                                     // 置饱和标志 [—] / raise the saturation flag
    END_IF
    IF fMapped < fSatMin THEN                             // 输出侧下饱和 / the output stage saturates low
        fOut := fSatMin;                                  // 钳到饱和下限 [输出量程单位] / clamp to the low limit
        xSat := TRUE;                                     // 置饱和标志 [—] / raise the saturation flag
    END_IF
    FC_DL_MapRangeSatOut := TRUE;                         // 映射成功 / the mapping succeeded
ELSE
    fOut := fOutMin;                                      // 非法参数输出下端点哨兵 [输出量程单位] / the sentinel
    FC_DL_MapRangeSatOut := FALSE;                        // 结果不可信 / the result is not valid
END_IF
END_FUNCTION
