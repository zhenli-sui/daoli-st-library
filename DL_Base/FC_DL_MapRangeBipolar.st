(*
  FC_DL_MapRangeBipolar —— 双极性对称映射，中点偏置
  分类：DL_Base | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：把对称双极性输入量程 [fInMin, fInMax]（中点即零点）映射到对称输出量程 [-fOutAmp, +fOutAmp]：
        out = (in - 中点) / (半量程) * 幅值。中点偏置（输入量程中点不为零，如 4..20 mA 对应 12 为中点）自动扣除。
  契约：fIn 输入、fInMin/fInMax 输入端点、fOutAmp 输出幅值（正数，输出范围 = ±幅值）；
        fOut 映射结果；返回 TRUE 表示 fOut 可信。
  边界：① 量程退化校验（容差 DL_MR_EPS）；② fOutAmp 必须 > 0；③ 六个浮点入参逐一非有限闸；
        ④ 除零防护：除以半量程前已过退化闸；零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_MapRangeBipolar : BOOL
VAR_INPUT
    fIn     : LREAL := 0.0;            // 输入值 [输入量程单位] / The input value in the input range unit
    fInMin  : LREAL := 0.0;            // 输入量程下端点 [输入量程单位] / The input range low end
    fInMax  : LREAL := 100.0;          // 输入量程上端点 [输入量程单位] / The input range high end
    fOutAmp : LREAL := 1.0;            // 输出幅值（输出范围 ±幅值） [输出量程单位] / The output amplitude
END_VAR
VAR_OUTPUT
    fOut : LREAL;                      // 映射结果 [输出量程单位] / The mapped value in the output range unit
END_VAR
VAR
    xBad      : BOOL;                  // 参数非法标志 [—] / The parameter invalid flag
    fInClamp  : LREAL;                 // 钳位后的输入 [输入量程单位] / The clamped input value
    fSpanIn   : LREAL;                 // 输入量程跨度（双倍半量程） [输入量程单位] / The input span
    fMid      : LREAL;                 // 输入量程中点 [输入量程单位] / The input range midpoint
    fHalf     : LREAL;                 // 输入半量程 [输入量程单位] / The half span
END_VAR
VAR CONSTANT
    DL_MB_EPS : LREAL := 1.0E-9;       // 浮点比较容差 [-] / The floating point comparison tolerance
    DL_MB_INF : LREAL := 1.0E30;       // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_MB_Z   : LREAL := 0.0;          // 浮点零常量 [-] / The floating point zero constant
    DL_MB_TWO : LREAL := 2.0;          // 浮点二常量 [-] / The floating point two constant
END_VAR

FC_DL_MapRangeBipolar := FALSE;                           // 返回值预置假 / preset the return false
fOut := DL_MB_Z;                                          // 输出预置零哨兵 / preset the zero sentinel
xBad := FALSE;                                            // 非法标志预置假 / preset the invalid flag false
IF (fIn <> fIn) OR (ABS(fIn) > DL_MB_INF) THEN            // 输入非有限闸 / the input gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fInMin <> fInMin) OR (ABS(fInMin) > DL_MB_INF) THEN   // 输入下端非有限闸 / the low end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fInMax <> fInMax) OR (ABS(fInMax) > DL_MB_INF) THEN   // 输入上端非有限闸 / the high end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fOutAmp <> fOutAmp) OR (ABS(fOutAmp) > DL_MB_INF) THEN // 幅值非有限闸 / the amplitude gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF fOutAmp <= DL_MB_EPS THEN                              // 幅值非正 / the amplitude is not positive
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
fSpanIn := fInMax - fInMin;                               // 输入量程跨度 [输入量程单位] / the input span
IF ABS(fSpanIn) < DL_MB_EPS THEN                          // 输入量程退化（除零防护） / the degenerate span
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF NOT xBad THEN                                          // 参数全通过才映射 / map only when all parameters pass
    fMid := (fInMin + fInMax) / DL_MB_TWO;                // 输入量程中点（中点偏置） [输入量程单位] / the midpoint
    fHalf := fSpanIn / DL_MB_TWO;                         // 输入半量程 [输入量程单位] / the half span
    fInClamp := fIn;                                      // 输入接管 [输入量程单位] / take the input value
    IF fInClamp < fInMin THEN                             // 低于下端点 / below the low end
        fInClamp := fInMin;                               // 钳到下端点 [输入量程单位] / clamp to the low end
    END_IF
    IF fInClamp > fInMax THEN                             // 高于上端点 / above the high end
        fInClamp := fInMax;                               // 钳到上端点 [输入量程单位] / clamp to the high end
    END_IF
    fOut := ((fInClamp - fMid) / fHalf) * fOutAmp;        // 对称映射（分母已证非零） [输出量程单位] / the symmetric mapping
    FC_DL_MapRangeBipolar := TRUE;                        // 映射成功 / the mapping succeeded
ELSE
    fOut := DL_MB_Z;                                      // 非法参数输出零哨兵 [输出量程单位] / the sentinel
    FC_DL_MapRangeBipolar := FALSE;                       // 结果不可信 / the result is not valid
END_IF
END_FUNCTION
