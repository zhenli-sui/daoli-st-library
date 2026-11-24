(*
  FC_DL_MapRangePercent —— 百分比与工程值互映，枚举方向
  分类：DL_Base | 复杂度：1 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：按 eDir 方向做百分比与工程值互映：
        ePctToEng：fIn 视为百分比 0..100，映射到 [fOutMin, fOutMax]；
        eEngToPct：fIn 视为工程量，映射到百分比 0..100（先钳到量程）。
  契约：fIn 输入值、eDir 方向枚举、fEngMin/fEngMax 工程量程端点；fOut 结果 [目标单位]；返回 TRUE 表示可信。
  边界：① 量程退化校验（容差 DL_MP_EPS）；② 除零防护：分母先过退化闸；③ 浮点入参逐一非有限闸；
        ④ CASE 含 ELSE 兜底拦非法方向；零全局、零物理地址、零库件依赖。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MapDir（映射方向，归属本文件，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_MapDir :
(
    ePctToEng := 0,    // 百分比 → 工程值 [—] / Percent to engineering value
    eEngToPct := 1     // 工程值 → 百分比 [—] / Engineering value to percent
);
END_TYPE

FUNCTION FC_DL_MapRangePercent : BOOL
VAR_INPUT
    fIn     : LREAL := 0.0;            // 输入值 [源单位] / The input value in the source unit
    eDir    : E_DL_MapDir;             // 映射方向枚举 [—] / The mapping direction
    fEngMin : LREAL := 0.0;            // 工程量程下端点 [工程单位] / The engineering range low end
    fEngMax : LREAL := 100.0;          // 工程量程上端点 [工程单位] / The engineering range high end
END_VAR
VAR_OUTPUT
    fOut : LREAL;                      // 结果 [目标单位] / The result in the target unit
END_VAR
VAR
    xBad     : BOOL;                   // 参数非法标志 [—] / The parameter invalid flag
    fInClamp : LREAL;                  // 钳位后的输入 [源单位] / The clamped input value
    fEngSpan : LREAL;                  // 工程量程跨度 [工程单位] / The engineering span
END_VAR
VAR CONSTANT
    DL_MP_EPS   : LREAL := 1.0E-9;     // 浮点比较容差 [-] / The floating point comparison tolerance
    DL_MP_INF   : LREAL := 1.0E30;     // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_MP_Z     : LREAL := 0.0;        // 浮点零常量 [-] / The floating point zero constant
    DL_MP_HUND  : LREAL := 100.0;      // 百分比满量程 [-] / The percent full scale
END_VAR

FC_DL_MapRangePercent := FALSE;                           // 返回值预置假 / preset the return false
fOut := DL_MP_Z;                                          // 输出预置零哨兵 / preset the zero sentinel
xBad := FALSE;                                            // 非法标志预置假 / preset the invalid flag false
IF (fIn <> fIn) OR (ABS(fIn) > DL_MP_INF) THEN            // 输入非有限闸 / the input gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fEngMin <> fEngMin) OR (ABS(fEngMin) > DL_MP_INF) THEN // 工程下端非有限闸 / the engineering low end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fEngMax <> fEngMax) OR (ABS(fEngMax) > DL_MP_INF) THEN // 工程上端非有限闸 / the engineering high end gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
fEngSpan := fEngMax - fEngMin;                            // 工程量程跨度 [工程单位] / the engineering span
IF ABS(fEngSpan) < DL_MP_EPS THEN                         // 量程退化（除零防护） / the degenerate span
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF NOT xBad THEN                                          // 参数全通过才映射 / map only when all parameters pass
    CASE eDir OF
        E_DL_MapDir.ePctToEng:                            // 百分比转工程值 / percent to engineering value
            fInClamp := fIn;                              // 输入接管 [%] / take the input value
            IF fInClamp < DL_MP_Z THEN                    // 百分比低于零 / below zero percent
                fInClamp := DL_MP_Z;                      // 钳到零 [%] / clamp to zero
            END_IF
            IF fInClamp > DL_MP_HUND THEN                 // 百分比高于一百 / above one hundred percent
                fInClamp := DL_MP_HUND;                   // 钳到一百 [%] / clamp to one hundred
            END_IF
            fOut := fEngMin + (fInClamp / DL_MP_HUND) * fEngSpan; // 线性换算（除常量） [工程单位] / the conversion
            FC_DL_MapRangePercent := TRUE;                // 结果可信 / the result is valid
        E_DL_MapDir.eEngToPct:                            // 工程值转百分比 / engineering value to percent
            fInClamp := fIn;                              // 输入接管 [工程单位] / take the input value
            IF fEngSpan > DL_MP_Z THEN                    // 正常量程方向 / the normal span direction
                IF fInClamp < fEngMin THEN                // 低于下端点 / below the low end
                    fInClamp := fEngMin;                  // 钳到下端点 [工程单位] / clamp to the low end
                END_IF
                IF fInClamp > fEngMax THEN                // 高于上端点 / above the high end
                    fInClamp := fEngMax;                  // 钳到上端点 [工程单位] / clamp to the high end
                END_IF
            ELSE                                          // 反向量程 / the reversed span
                IF fInClamp > fEngMin THEN                // 高于下端（反向即越小越远） / above the low end
                    fInClamp := fEngMin;                  // 钳到下端点 [工程单位] / clamp to the low end
                END_IF
                IF fInClamp < fEngMax THEN                // 低于上端点 / below the high end
                    fInClamp := fEngMax;                  // 钳到上端点 [工程单位] / clamp to the high end
                END_IF
            END_IF
            fOut := ((fInClamp - fEngMin) / fEngSpan) * DL_MP_HUND; // 反向换算（分母已证非零） [%] / the conversion
            FC_DL_MapRangePercent := TRUE;                // 结果可信 / the result is valid
    ELSE
        fOut := DL_MP_Z;                                  // 非法方向输出零哨兵 / zero sentinel on an illegal direction
        FC_DL_MapRangePercent := FALSE;                   // 非法方向不可信 / an illegal direction is not valid
    END_CASE
END_IF
END_FUNCTION
