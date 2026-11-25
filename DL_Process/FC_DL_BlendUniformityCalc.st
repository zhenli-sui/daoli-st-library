(*
  DL Factory R84 | FC_DL_BlendUniformityCalc
  功能：由多点取样含量算均值、CV 与混合指数，并按 CV≤5% 判均匀
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_BlendUniformityCalc : REAL
VAR_INPUT
    aContentPct : ARRAY[0..15] OF REAL; // 各取样点含量（0..15 号点） [%] / sampled content per point [%]
    iSampleCnt : INT := 10; // 有效取样点数（2~16） [点] / effective sample count [points]
    fCv0Pct : REAL := 5.0; // 初始（未混合）变异系数参考 CV0 [%] / initial coefficient of variation [%]
    fCvLimitPct : REAL := 5.0; // 均匀度合格上限 [%] / uniformity acceptance limit [%]
END_VAR
VAR_OUTPUT
    fMean : REAL; // 取样均值 [%] / sample mean [%]
    fAcceptIdx : REAL; // 混合指数 1 − CV/CV0，钳位 0~1 [-] / mixing index, clamped [0,1]
    xPass : BOOL; // 均匀度判合格 [-] / uniformity passed [-]
    iN : INT; // 实际参与计算的取样点数 [点] / sample count actually used [points]
END_VAR
VAR
    i : INT; // 循环游标（0 基正向） [-] / loop cursor, forward only [-]
    fSum : REAL; // 含量累加和 [%] / running sum of content [%]
    fDev : REAL; // 单点偏差 [%] / single deviation [%]
    fSqSum : REAL; // 偏差平方和 [%²] / sum of squared deviations [%^2]
    fStd : REAL; // 样本标准差 [%] / sample standard deviation [%]
    fCvPct : REAL; // 变异系数 [%] / coefficient of variation [%]
    xFin : BOOL; // 全部取样点有限性判定 [-] / all samples finite verdict [-]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_BlendUniformityCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fMean := 0.0; // 均值预置零 [%] / mean preset zero [%]
fAcceptIdx := 0.0; // 混合指数预置零 [-] / index preset zero [-]
xPass := FALSE; // 合格位预置 FALSE [-] / pass preset false [-]
iN := 0; // 点数预置零 [点] / count preset zero [points]

// 段 2｜域闸 + 样本有限性闸（R4/R272）
IF iSampleCnt < 2 OR iSampleCnt > 16 THEN
    RETURN; // 少于两点无法算标准差 [点] / at least two points needed [points]
END_IF
IF NOT (fCv0Pct > -1.0E30 AND fCv0Pct < 1.0E30) OR NOT (fCvLimitPct > -1.0E30 AND fCvLimitPct < 1.0E30) OR fCv0Pct < 1.0E-9 OR fCvLimitPct < 1.0E-9 THEN
    RETURN; // CV0 与限值正域闸（CV0 兼作分母） [%] / positive CV0 and limit gate [%]
END_IF
xFin := TRUE; // 有限性初值置真 [-] / finiteness starts true [-]
FOR i := 0 TO 15 DO
    IF i < iSampleCnt THEN
        IF NOT (aContentPct[i] > -1.0E30 AND aContentPct[i] < 1.0E30) THEN
            xFin := FALSE; // 任一点 NaN/Inf 即整体无效 [-] / any bad point voids the batch [-]
        END_IF
    END_IF
END_FOR
IF NOT xFin THEN
    RETURN; // 含非有限取样值直接退出 [-] / exit on a non finite sample [-]
END_IF

// 段 3｜均值
fSum := 0.0; // 累加和清零 [%] / clear the sum [%]
FOR i := 0 TO 15 DO
    IF i < iSampleCnt THEN
        fSum := fSum + aContentPct[i]; // % + % = % / [%] + [%] = [%]
    END_IF
END_FOR
fMean := fSum / INT_TO_REAL(iSampleCnt); // % ÷ 无量纲 = % / [%] / [-] = [%]
IF fMean <= 1.0E-9 THEN
    RETURN; // 分母闸：均值趋零则 CV 无定义 [%] / denominator gate, zero mean [%]
END_IF

// 段 4｜样本标准差（n−1 分母）与 CV
fSqSum := 0.0; // 平方和清零 [%²] / clear the square sum [%^2]
FOR i := 0 TO 15 DO
    IF i < iSampleCnt THEN
        fDev := aContentPct[i] - fMean; // % − % = % / [%] minus [%] = [%]
        fSqSum := fSqSum + (fDev * fDev); // % × % = %² / [%] × [%] = [%^2]
    END_IF
END_FOR
fStd := SQRT(fSqSum / INT_TO_REAL(iSampleCnt - 1)); // %² ÷ 无量纲 开方 = % / sqrt([%^2] / [-]) = [%]
fCvPct := (fStd / fMean) * 100.0; // % ÷ % × 100 = % / [%] / [%] × 100 = [%]
IF NOT (fCvPct > -1.0E30 AND fCvPct < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF

// 段 5｜混合指数与合格判定
fAcceptIdx := 1.0 - (fCvPct / fCv0Pct); // 无量纲：1 − %/% = -（越界值由紧接的两条钳位语句处理） / dimensionless index 1 - [%]/[%], clamped by the two following statements
IF fAcceptIdx < 0.0 THEN
    fAcceptIdx := 0.0; // 下限钳位：方差反增说明混合退化 [-] / clamp low: mixing degraded [-]
END_IF
IF fAcceptIdx > 1.0 THEN
    fAcceptIdx := 1.0; // 上限钳位：完美混合 [-] / clamp high: perfect mixing [-]
END_IF
xPass := fCvPct <= fCvLimitPct; // 直比上限，禁浮点等值 [-] / direct compare against the limit [-]
iN := iSampleCnt; // 回填实际点数 [点] / report the count used [points]
FC_DL_BlendUniformityCalc := fCvPct; // 返回 CV [%] / return the CV [%]
END_FUNCTION
