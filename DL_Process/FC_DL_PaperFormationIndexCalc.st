(*
  DL Factory R84 | FC_DL_PaperFormationIndexCalc
  功能：由絮聚波长与小尺度方差比估算成形指数（0~1）并按 0.6 判良好
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_PaperFormationIndexCalc : REAL
VAR_INPUT
    fVarTotal : REAL := 1.0; // 全尺度方差（归一化） [-] / total normalised variance [-]
    fVarSmall : REAL := 0.25; // 小尺度方差分量 [-] / small scale variance component [-]
    fScaleRefMm : REAL := 1.0; // 参考絮聚尺度（像素→mm 标定） [mm] / reference floc scale [mm]
    fLambda0Mm : REAL := 2.0; // 良好成形的特征波长基准 [mm] / reference wavelength of good formation [mm]
    fIdxMin : REAL := 0.6; // 成形指数良好下限 [-] / good formation threshold [-]
END_VAR
VAR_OUTPUT
    fFlocLambda : REAL; // 估算絮聚波长 [mm] / estimated floc wavelength [mm]
    xPass : BOOL; // 成形指数判良好 [-] / formation passed [-]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fRatio : REAL; // 全尺度/小尺度方差比 [-] / total to small variance ratio [-]
    fIdxRaw : REAL; // 未钳位成形指数 [-] / unclamped formation index [-]
    fIdx : REAL; // 钳位后成形指数 [-] / clamped formation index [-]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_PaperFormationIndexCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fFlocLambda := 0.0; // 絮聚波长预置零 [mm] / floc wavelength preset zero [mm]
xPass := FALSE; // 良好位预置 FALSE [-] / pass preset false [-]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fVarTotal > -1.0E30 AND fVarTotal < 1.0E30) OR NOT (fVarSmall > -1.0E30 AND fVarSmall < 1.0E30) OR NOT (fScaleRefMm > -1.0E30 AND fScaleRefMm < 1.0E30) THEN
    RETURN; // 方差与标定尺度任一非有限即拒算 [-] / any non finite variance or scale rejected [-]
END_IF
IF NOT (fLambda0Mm > -1.0E30 AND fLambda0Mm < 1.0E30) OR NOT (fIdxMin > -1.0E30 AND fIdxMin < 1.0E30) THEN
    RETURN; // 基准波长与门限任一非有限即拒算 [-] / any non finite reference or threshold rejected [-]
END_IF
IF fVarTotal < 0.0 OR fVarSmall < 1.0E-9 OR fScaleRefMm < 1.0E-9 OR fLambda0Mm < 1.0E-9 THEN
    RETURN; // 方差非负 + 小尺度方差/尺度/基准正域分母闸（防除零） [-] / non negative variance and positive denominator gate [-]
END_IF

// 段 3｜方差比与絮聚波长估算（mm × 无量纲 = mm）
fRatio := fVarTotal / fVarSmall; // 无量纲 / [-] = [-] / [-] / [-] = [-]
fFlocLambda := fScaleRefMm * fRatio; // mm × 无量纲 = mm / [mm] × [-] = [mm]
IF NOT (fFlocLambda > -1.0E30 AND fFlocLambda < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF

// 段 4｜成形指数 = λ0 / (λ0 + λfloc)，钳位到 0~1
fIdxRaw := fLambda0Mm / (fLambda0Mm + fFlocLambda); // mm ÷ mm = 无量纲 / [mm] / [mm] = [-]
fIdx := fIdxRaw; // 先接未钳位值 [-] / take the raw index [-]
IF fIdx > 1.0 THEN
    fIdx := 1.0; // 上限钳位 [-] / clamp high [-]
END_IF
IF fIdx < 0.0 THEN
    fIdx := 0.0; // 下限钳位（指数物理区间 0~1） [-] / clamp low to the physical range [-]
END_IF

// 段 5｜良好判定与出口
xPass := fIdx >= fIdxMin; // 直比门限，禁浮点等值 [-] / direct compare against the threshold [-]
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_PaperFormationIndexCalc := fIdx; // 返回成形指数 [-] / return the formation index [-]
END_FUNCTION
