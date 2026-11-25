(*
  FC_DL_MapRangeHystSwitch —— 带滞环的二态阈值映射
  分类：DL_Base | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：把连续输入映射为两态输出并带滞环：fIn >= fThOn 置态；fIn <= fThOff 复位态；
        fThOff < fIn < fThOn 区间保持上拍态。状态由 VAR_IN_OUT 变量在调用方持有（FC 无内部记忆）。
  契约：fIn 输入、fThOn 置位阈值、fThOff 复位阈值（必须 fThOn > fThOff）、xState 状态输入输出；
        xOut 本拍输出；返回 TRUE 表示可信（参数合法）。
  边界：① 阈值倒置 / 相等校验（容差 DL_MH_EPS）判非法并保持上拍态；② 三个浮点入参非有限闸；
        ③ 滞环区间内显式保持，禁「按当下输入重算」；④ 零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_MapRangeHystSwitch : BOOL
VAR_INPUT
    fIn    : LREAL := 0.0;             // 输入值 [工程单位] / The input value
    fThOn  : LREAL := 80.0;            // 置位阈值（高端） [工程单位] / The set threshold, the high side
    fThOff : LREAL := 20.0;            // 复位阈值（低端） [工程单位] / The reset threshold, the low side
END_VAR
VAR_IN_OUT
    xState : BOOL;                     // 两态状态（调用方持有，跨调用保持） [—] / The two state flag held by the caller
END_VAR
VAR_OUTPUT
    xOut : BOOL;                       // 本拍两态输出 [—] / The two state output
END_VAR
VAR
    xBad : BOOL;                       // 参数非法标志 [—] / The parameter invalid flag
END_VAR
VAR CONSTANT
    DL_MH_EPS : LREAL := 1.0E-9;       // 浮点比较容差 [-] / The floating point comparison tolerance
    DL_MH_INF : LREAL := 1.0E30;       // 非有限 / 越界判据上限 [-] / The magnitude gate
END_VAR

FC_DL_MapRangeHystSwitch := FALSE;                        // 返回值预置假 / preset the return false
xOut := xState;                                           // 输出先保持上拍态 / hold the previous state first
xBad := FALSE;                                            // 非法标志预置假 / preset the invalid flag false
IF (fIn <> fIn) OR (ABS(fIn) > DL_MH_INF) THEN            // 输入非有限闸 / the input gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fThOn <> fThOn) OR (ABS(fThOn) > DL_MH_INF) THEN      // 置位阈值非有限闸 / the set threshold gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fThOff <> fThOff) OR (ABS(fThOff) > DL_MH_INF) THEN   // 复位阈值非有限闸 / the reset threshold gate
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF (fThOn - fThOff) < DL_MH_EPS THEN                      // 阈值倒置或相等，滞环宽度非正 / the band is not positive
    xBad := TRUE;                                         // 置非法标志 / raise the invalid flag
END_IF
IF NOT xBad THEN                                          // 参数合法才更新状态 / update only with valid parameters
    IF fIn >= fThOn THEN                                  // 达到置位阈值 / the set threshold is reached
        xState := TRUE;                                   // 置位（滞环高端） [—] / set the state
    ELSIF fIn <= fThOff THEN                              // 达到复位阈值 / the reset threshold is reached
        xState := FALSE;                                  // 复位（滞环低端） [—] / reset the state
    END_IF                                                // 滞环区间内不赋值，xState 自然保持上拍态 / hold inside the band
    xOut := xState;                                       // 状态发布到出口 / publish the state
    FC_DL_MapRangeHystSwitch := TRUE;                     // 参数合法，输出可信 / the parameters are valid
ELSE
    xOut := xState;                                       // 非法参数保持上拍态 [—] / hold the previous state
    FC_DL_MapRangeHystSwitch := FALSE;                    // 结果不可信 / the result is not valid
END_IF
END_FUNCTION
