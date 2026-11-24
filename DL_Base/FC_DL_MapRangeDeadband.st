(*
  FC_DL_MapRangeDeadband —— 带中心死区的量程映射，死区内输出中点
  分类：DL_Base | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：以输入量程中点为中心设置 ±fDbHalf 死区；死区内输出量程中点；
        死区外按「扣除死区后重新归一」的比例映射，保证在死区边界处连续无跳变。
  契约：fIn 输入、fInMin/fInMax 输入端点、fOutMin/fOutMax 输出端点、fDbHalf 死区半宽 [输入量程单位]；
        fOut 映射结果；返回 TRUE 表示可信。
  边界：① 量程与死区退化校验（容差 DL_MD_EPS）；死区半宽必须 >= 0 且 < 输入半量程；
        ② 六个浮点入参逐一非有限闸；③ 除零防护：归一化分母经非退化闸证明 > 0；
        ④ 零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_MapRangeDeadband : BOOL
VAR_INPUT
    fIn     : LREAL := 0.0;            // 输入值 [输入量程单位] / The input value
    fInMin  : LREAL := 0.0;            // 输入量程下端点 [输入量程单位] / The input range low end
    fInMax  : LREAL := 100.0;          // 输入量程上端点 [输入量程单位] / The input range high end
    fOutMin : LREAL := 0.0;            // 输出量程下端点 [输出量程单位] / The output range low end
    fOutMax : LREAL := 100.0;          // 输出量程上端点 [输出量程单位] / The output range high end
    fDbHalf : LREAL := 5.0;            // 死区半宽（以输入中点为心） [输入量程单位] / The dead band half width
END_VAR
VAR_OUTPUT
    fOut  : LREAL;                     // 映射结果 [输出量程单位] / The mapped value
    xInDb : BOOL;                      // 本拍输入落在死区内 [—] / The input is inside the dead band
END_VAR
VAR
    xBad    : BOOL;                    // 参数非法标志 [—] / The parameter invalid flag
    fInMid  : LREAL;                   // 输入量程中点 [输入量程单位] / The input midpoint
    fOutMid : LREAL;                   // 输出量程中点 [输出量程单位] / The output midpoint
    fInHalf : LREAL;                   // 输入半量程 [输入量程单位] / The input half span
    fOutHalf : LREAL;                  // 输出半量程 [输出量程单位] / The output half span
    fRel    : LREAL;                   // 扣除死区后的归一化比例 [归一化] / The normalised ratio beyond the band
    fDev    : LREAL;                   // 输入相对中点的偏移 [输入量程单位] / The deviation from the midpoint
END_VAR
VAR CONSTANT
    DL_MD_EPS  : LREAL := 1.0E-9;      // 浮点比较容差 [-] / The floating point comparison tolerance
    DL_MD_INF  : LREAL := 1.0E30;      // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_MD_Z    : LREAL := 0.0;         // 浮点零常量 [-] / The floating point zero constant
    DL_MD_TWO  : LREAL := 2.0;         // 浮点二常量 [-] / The floating point two constant
END_VAR

FC_DL_MapRangeDeadband := FALSE;                          // 返回值预置假 / preset the return false
fOut := fOutMin;                                          // 输出预置为输出下端点哨兵 / preset the low end sentinel
xInDb := FALSE;                                           // 死区标志预置假 / preset the dead band flag false
xBad := FALSE;                                            // 非法标志预置假 / preset the invalid flag false
IF (fIn <> fIn) OR (ABS(fIn) > DL_MD_INF) THEN            // 输入非有限闸 / the input gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fInMin <> fInMin) OR (ABS(fInMin) > DL_MD_INF) THEN   // 输入下端非有限闸 / the input low end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fInMax <> fInMax) OR (ABS(fInMax) > DL_MD_INF) THEN   // 输入上端非有限闸 / the input high end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fOutMin <> fOutMin) OR (ABS(fOutMin) > DL_MD_INF) THEN // 输出下端非有限闸 / the output low end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fOutMax <> fOutMax) OR (ABS(fOutMax) > DL_MD_INF) THEN // 输出上端非有限闸 / the output high end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fDbHalf <> fDbHalf) OR (ABS(fDbHalf) > DL_MD_INF) THEN // 死区半宽非有限闸 / the dead band gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
fInHalf := (fInMax - fInMin) / DL_MD_TWO;                 // 输入半量程 [输入量程单位] / the input half span
fOutHalf := (fOutMax - fOutMin) / DL_MD_TWO;              // 输出半量程 [输出量程单位] / the output half span
IF ABS(fInHalf) < DL_MD_EPS THEN                          // 输入量程退化 / the degenerate input span
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fDbHalf < DL_MD_Z) OR (ABS(fDbHalf) >= ABS(fInHalf)) THEN // 死区半宽越界 / the dead band is out of range
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF NOT xBad THEN                                          // 参数全通过才映射 / map only when all parameters pass
    fInMid := (fInMin + fInMax) / DL_MD_TWO;              // 输入量程中点 [输入量程单位] / the input midpoint
    fOutMid := (fOutMin + fOutMax) / DL_MD_TWO;           // 输出量程中点 [输出量程单位] / the output midpoint
    fDev := fIn - fInMid;                                 // 输入相对中点偏移 [输入量程单位] / the deviation
    IF ABS(fDev) <= fDbHalf THEN                          // 落在死区内 / inside the dead band
        fOut := fOutMid;                                  // 死区内输出中点 [输出量程单位] / output the midpoint
        xInDb := TRUE;                                    // 置死区标志 [—] / raise the dead band flag
    ELSE
        fRel := (ABS(fDev) - fDbHalf) / (ABS(fInHalf) - ABS(fDbHalf)); // 扣除死区后归一（分母已证 > 0）
        IF fRel > 1.0 THEN                                // 越出量程上界钳位 / clamp beyond the range
            fRel := 1.0;                                  // 钳到一 [归一化] / clamp to one
        END_IF
        IF fDev > DL_MD_Z THEN                            // 正向偏移 / a positive deviation
            fOut := fOutMid + fRel * fOutHalf;            // 正向落位 [输出量程单位] / the positive side
        ELSE
            fOut := fOutMid - fRel * fOutHalf;            // 负向落位 [输出量程单位] / the negative side
        END_IF
    END_IF
    FC_DL_MapRangeDeadband := TRUE;                       // 映射成功 / the mapping succeeded
ELSE
    fOut := fOutMin;                                      // 非法参数输出下端点哨兵 [输出量程单位] / the sentinel
    FC_DL_MapRangeDeadband := FALSE;                      // 结果不可信 / the result is not valid
END_IF
END_FUNCTION
