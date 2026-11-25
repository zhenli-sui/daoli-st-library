(*
  DL Factory R84 | FC_DL_TabletWeightRsdCalc
  功能：按滚动窗口片重算均值、样本标准差与相对标准偏差 RSD 并按 2% 限判合格
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_TabletWeightRsdCalc : REAL
VAR_INPUT
    aWeightMg : ARRAY[0..15] OF REAL; // 片重窗口样本（0..15 号槽） [mg] / tablet weight window [mg]
    iSampleCnt : INT := 10; // 有效样本数（2~16） [个] / effective sample count [count]
    fRsdLimitPct : REAL := 2.0; // RSD 合格上限 [%] / RSD acceptance limit [%]
END_VAR
VAR_OUTPUT
    fMean : REAL; // 样本均值 [mg] / sample mean [mg]
    fStd : REAL; // 样本标准差（n−1） [mg] / sample standard deviation [mg]
    xPass : BOOL; // RSD 判合格 [-] / RSD passed [-]
    iN : INT; // 实际参与计算的样本数 [个] / sample count actually used [count]
END_VAR
VAR
    i : INT; // 循环游标（0 基正向） [-] / loop cursor, forward only [-]
    fSum : REAL; // 累加和 [mg] / running sum [mg]
    fDev : REAL; // 单体偏差 [mg] / single deviation [mg]
    fSqSum : REAL; // 偏差平方和 [mg²] / sum of squared deviations [mg^2]
    fRsdPct : REAL; // RSD 中间量 [%] / RSD intermediate [%]
    xFin : BOOL; // 全部样本有限性判定 [-] / all samples finite verdict [-]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_TabletWeightRsdCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fMean := 0.0; // 均值预置零 [mg] / mean preset zero [mg]
fStd := 0.0; // 标准差预置零 [mg] / deviation preset zero [mg]
xPass := FALSE; // 合格位预置 FALSE [-] / pass preset false [-]
iN := 0; // 样本数预置零 [个] / count preset zero [count]

// 段 2｜域闸 + 样本有限性闸（R4/R272）
IF iSampleCnt < 2 OR iSampleCnt > 16 THEN
    RETURN; // 样本数不足两件无法算样本标准差 [个] / at least two samples needed [count]
END_IF
IF NOT (fRsdLimitPct > -1.0E30 AND fRsdLimitPct < 1.0E30) OR fRsdLimitPct <= 0.0 THEN
    RETURN; // 限值域闸（正域） [%] / positive limit gate [%]
END_IF
xFin := TRUE; // 有限性初值置真 [-] / finiteness starts true [-]
FOR i := 0 TO 15 DO
    IF i < iSampleCnt THEN
        IF NOT (aWeightMg[i] > -1.0E30 AND aWeightMg[i] < 1.0E30) THEN
            xFin := FALSE; // 任一样本 NaN/Inf 即整体无效 [-] / any bad sample voids the batch [-]
        END_IF
    END_IF
END_FOR
IF NOT xFin THEN
    RETURN; // 含非有限样本直接退出 [-] / exit on a non finite sample [-]
END_IF

// 段 3｜均值（kg 类量纲按 mg 计，mg × 1 = mg）
fSum := 0.0; // 累加和清零 [mg] / clear the sum [mg]
FOR i := 0 TO 15 DO
    IF i < iSampleCnt THEN
        fSum := fSum + aWeightMg[i]; // mg + mg = mg / [mg] + [mg] = [mg]
    END_IF
END_FOR
fMean := fSum / INT_TO_REAL(iSampleCnt); // mg ÷ 无量纲 = mg / [mg] / [-] = [mg]
IF fMean <= 1.0E-9 THEN
    RETURN; // 分母闸：均值趋零则 RSD 无定义 [mg] / denominator gate, zero mean [mg]
END_IF

// 段 4｜样本标准差（n−1 分母）
fSqSum := 0.0; // 平方和清零 [mg²] / clear the square sum [mg^2]
FOR i := 0 TO 15 DO
    IF i < iSampleCnt THEN
        fDev := aWeightMg[i] - fMean; // mg − mg = mg / [mg] minus [mg] = [mg]
        fSqSum := fSqSum + (fDev * fDev); // mg × mg = mg² / [mg] × [mg] = [mg^2]
    END_IF
END_FOR
fStd := SQRT(fSqSum / INT_TO_REAL(iSampleCnt - 1)); // mg² ÷ 无量纲 开方 = mg / sqrt([mg^2] / [-]) = [mg]

// 段 5｜RSD 与合格判定
fRsdPct := (fStd / fMean) * 100.0; // mg ÷ mg × 100 = % / [mg] / [mg] × 100 = [%]
IF NOT (fRsdPct > -1.0E30 AND fRsdPct < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF
xPass := fRsdPct <= fRsdLimitPct; // 直比上限，禁浮点等值 [-] / direct compare, no float equality [-]
iN := iSampleCnt; // 回填实际样本数 [个] / report the count used [count]
FC_DL_TabletWeightRsdCalc := fRsdPct; // 返回 RSD [%] / return the RSD [%]
END_FUNCTION
