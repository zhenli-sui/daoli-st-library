(*
  FC_DL_SatClampLrealBand —— LREAL 区间钳位，带上下限合法性自检
  分类：DL_MathData | 复杂度：1 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：把输入钳到 [fMin, fMax]；钳位前先自检区间合法性（fMax 必须 >= fMin）与三个浮点入参的非有限性，
        任一非法即 fOut 给下限哨兵并置 xValid = FALSE。
  契约：fIn 输入、fMin / fMax 钳位区间；fOut 钳位结果；xClamped 报告发生钳位；xValid 结果可信。
  边界：① 区间倒置判非法（不静默交换，交换会掩盖上游配置错误）；② 三个浮点入参逐一非有限闸；
        ③ 零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_SatClampLrealBand : LREAL
VAR_INPUT
    fIn  : LREAL := 0.0;              // 输入值 [工程单位] / The input value
    fMin : LREAL := -1000.0;          // 钳位下限 [工程单位] / The clamp low limit
    fMax : LREAL := 1000.0;           // 钳位上限 [工程单位] / The clamp high limit
END_VAR
VAR_OUTPUT
    xClamped : BOOL;                  // 发生钳位（信息级） [—] / A clamp occurred, informational
    xValid   : BOOL;                  // 区间与输入合法 [—] / The band and the input are valid
END_VAR
VAR CONSTANT
    DL_CL_INF : LREAL := 1.0E30;      // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_CL_Z   : LREAL := 0.0;         // 浮点零常量 [工程单位] / The floating point zero constant
END_VAR

xClamped := FALSE;                                    // 钳位标志预置假 / preset the clamp flag false
xValid := FALSE;                                      // 可信位预置假 / preset the valid flag false
FC_DL_SatClampLrealBand := DL_CL_Z;                   // 返回值预置零 / preset the return zero
IF (fIn <> fIn) OR (ABS(fIn) > DL_CL_INF) THEN        // 输入非有限闸 / the input gate
    FC_DL_SatClampLrealBand := fMin;                  // 非有限输入给下限哨兵 / the low limit sentinel
ELSIF (fMin <> fMin) OR (ABS(fMin) > DL_CL_INF) THEN  // 下限非有限闸 / the low limit gate
    FC_DL_SatClampLrealBand := DL_CL_Z;               // 下限非法归零 / zero on an invalid limit
ELSIF (fMax <> fMax) OR (ABS(fMax) > DL_CL_INF) THEN  // 上限非有限闸 / the high limit gate
    FC_DL_SatClampLrealBand := DL_CL_Z;               // 上限非法归零 / zero on an invalid limit
ELSIF fMax < fMin THEN                                // 区间倒置（配置错误的显式拒绝） / the inverted band
    FC_DL_SatClampLrealBand := fMin;                  // 倒置区间给下限哨兵 / the low limit sentinel
ELSE
    IF fIn > fMax THEN                                // 上越界钳位 / clamp the high side
        FC_DL_SatClampLrealBand := fMax;              // 钳到上限 [工程单位] / clamp to the high limit
        xClamped := TRUE;                             // 置钳位标志 / raise the clamp flag
    ELSIF fIn < fMin THEN                             // 下越界钳位 / clamp the low side
        FC_DL_SatClampLrealBand := fMin;              // 钳到下限 [工程单位] / clamp to the low limit
        xClamped := TRUE;                             // 置钳位标志 / raise the clamp flag
    ELSE
        FC_DL_SatClampLrealBand := fIn;               // 界内直接输出 [工程单位] / the in range value
    END_IF
    xValid := TRUE;                                   // 区间与输入合法 / the band and the input are valid
END_IF
END_FUNCTION
