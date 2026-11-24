(*
  DL Factory R84 | FC_DL_MtsrCalc
  功能：由当前温度与绝热温升算 MTSR，并给分解起始温度的安全裕度
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_MtsrCalc : REAL
VAR_INPUT
    fTpC : REAL := 80.0; // 当前工艺温度 [℃] / current process temperature [C]
    fDTadK : REAL := 60.0; // 绝热温升（由绝热温升计算件给出） [K] / adiabatic temperature rise [K]
    fConvertFrac : REAL := 0.6; // 已转化分数（0~1） [-] / converted fraction [0,1]
    fStartDecompC : REAL := 180.0; // 分解起始温度 [℃] / decomposition onset temperature [C]
    fMarginMinK : REAL := 20.0; // 最小安全裕度门限 [K] / minimum safety margin [K]
END_VAR
VAR_OUTPUT
    fMarginK : REAL; // 安全裕度（分解起始 − MTSR） [K] / safety margin [K]
    xRisk : BOOL; // 裕度不足风险位 [-] / insufficient margin risk flag [-]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fUnconvFrac : REAL; // 未转化分数（1 − X，钳位） [-] / unconverted fraction [-]
    fMtsrC : REAL; // MTSR 中间量 [℃] / MTSR intermediate [C]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_MtsrCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fMarginK := 0.0; // 裕度预置零 [K] / margin preset zero [K]
xRisk := FALSE; // 风险位预置 FALSE [-] / risk preset false [-]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fTpC > -1.0E30 AND fTpC < 1.0E30) OR NOT (fDTadK > -1.0E30 AND fDTadK < 1.0E30) OR NOT (fConvertFrac > -1.0E30 AND fConvertFrac < 1.0E30) OR NOT (fStartDecompC > -1.0E30 AND fStartDecompC < 1.0E30) OR NOT (fMarginMinK > -1.0E30 AND fMarginMinK < 1.0E30) THEN
    RETURN; // 任一入参为 NaN/Inf 一律拒绝 [-] / any NaN or Inf input rejected [-]
END_IF
IF fDTadK < 0.0 OR fMarginMinK < 0.0 THEN
    RETURN; // 绝热温升与裕度门限非负域闸 [K] / non negative rise and margin gate [K]
END_IF

// 段 3｜未转化分数（钳位 0~1）
fUnconvFrac := 1.0 - fConvertFrac; // 无量纲：1 − [-] = - / dimensionless one minus the fraction
IF fUnconvFrac < 0.0 THEN
    fUnconvFrac := 0.0; // 转化分数超一钳零（无剩余潜热） [-] / clamp low: no residual potential [-]
END_IF
IF fUnconvFrac > 1.0 THEN
    fUnconvFrac := 1.0; // 负转化分数钳一（按全未转化计，保守） [-] / clamp high: assume full potential [-]
END_IF

// 段 4｜MTSR = Tp + ΔTad × (1 − X)
fMtsrC := fTpC + (fDTadK * fUnconvFrac); // ℃ + K × 无量纲 = ℃（温差按同刻度计） / [C] + [K] × [-] = [C]
IF NOT (fMtsrC > -1.0E30 AND fMtsrC < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF

// 段 5｜安全裕度与风险位
fMarginK := fStartDecompC - fMtsrC; // ℃ − ℃ = K（温差） / [C] minus [C] = [K]
xRisk := fMarginK < fMarginMinK; // 直比门限，禁浮点等值 [-] / direct compare, no float equality [-]
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_MtsrCalc := fMtsrC; // 返回 MTSR [℃] / return the MTSR [C]
END_FUNCTION
