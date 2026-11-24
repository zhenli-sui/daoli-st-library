(*
  DL Factory R84 | FC_DL_GranuleSizeD50Calc
  功能：由累积粒径分布线性插值求 D10/D50/D90 并算跨径距 span
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_GranuleSizeD50Calc : REAL
VAR_INPUT
    aSizeUm : ARRAY[0..15] OF REAL; // 各档粒径（0..15 号档，单调递增） [µm] / sieve size bins, ascending [um]
    aCumPct : ARRAY[0..15] OF REAL; // 各档累积通过百分比（单调递增） [%] / cumulative passing per bin [%]
    iSampleCnt : INT := 10; // 有效档数（2~16） [档] / effective bin count [bins]
END_VAR
VAR_OUTPUT
    fD10 : REAL; // 10% 通过径 [µm] / size at ten percent passing [um]
    fD90 : REAL; // 90% 通过径 [µm] / size at ninety percent passing [um]
    fSpan : REAL; // 跨径距 (D90−D10)/D50 [-] / span of the distribution [-]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    i : INT; // 循环游标（1 基起，需访问 i−1 档） [-] / loop cursor starting at one [-]
    fDen : REAL; // 档间累积差（分母，已加下限闸） [%] / inter bin cumulative difference [%]
    fD50 : REAL; // D50 中间量 [µm] / median size intermediate [um]
    xGot10 : BOOL; // 已命中 10% 档标志 [-] / ten percent bin found [-]
    xGot50 : BOOL; // 已命中 50% 档标志 [-] / fifty percent bin found [-]
    xGot90 : BOOL; // 已命中 90% 档标志 [-] / ninety percent bin found [-]
    xFin : BOOL; // 数组有限性判定 [-] / array finiteness verdict [-]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_GranuleSizeD50Calc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fD10 := 0.0; // D10 预置零 [µm] / D10 preset zero [um]
fD90 := 0.0; // D90 预置零 [µm] / D90 preset zero [um]
fSpan := 0.0; // span 预置零 [-] / span preset zero [-]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]
xGot10 := FALSE; // 命中标志显式清零（FC 局部量不依赖初值） [-] / explicit reset of the hit flag [-]
xGot50 := FALSE; // 命中标志显式清零 [-] / explicit reset of the hit flag [-]
xGot90 := FALSE; // 命中标志显式清零 [-] / explicit reset of the hit flag [-]

// 段 2｜域闸 + 数组有限性闸（R4/R272）
IF iSampleCnt < 2 OR iSampleCnt > 16 THEN
    RETURN; // 少于两档无法插值 [档] / at least two bins needed [bins]
END_IF
xFin := TRUE; // 有限性初值置真 [-] / finiteness starts true [-]
FOR i := 0 TO 15 DO
    IF i < iSampleCnt THEN
        IF NOT (aSizeUm[i] > -1.0E30 AND aSizeUm[i] < 1.0E30) OR NOT (aCumPct[i] > -1.0E30 AND aCumPct[i] < 1.0E30) THEN
            xFin := FALSE; // 任一档非有限即整体无效 [-] / any bad bin voids the result [-]
        END_IF
    END_IF
END_FOR
IF NOT xFin THEN
    RETURN; // 含非有限档值直接退出 [-] / exit on a non finite bin [-]
END_IF

// 段 3｜线性插值定位 D10/D50/D90（首档已越限则直接取首档）
IF aCumPct[0] >= 10.0 THEN
    fD10 := aSizeUm[0]; // 首档已超 10%：D10 取下界 [µm] / first bin above ten percent [um]
    xGot10 := TRUE; // 置命中标志 [-] / mark as found [-]
END_IF
FOR i := 1 TO 15 DO
    IF i < iSampleCnt THEN
        fDen := aCumPct[i] - aCumPct[i - 1]; // % − % = %（档间累积差） / [%] minus [%] = [%]
        IF fDen < 1.0E-9 THEN
            fDen := 1.0E-9; // 分母闸：平台档按极小值兜底，避免除零 [%] / denominator floor [%]
        END_IF
        IF (NOT xGot10) AND (aCumPct[i] >= 10.0) THEN
            fD10 := aSizeUm[i - 1] + ((10.0 - aCumPct[i - 1]) * (aSizeUm[i] - aSizeUm[i - 1])) / fDen; // µm + % × µm ÷ % = µm / [um] + [%] × [um] / [%] = [um]
            xGot10 := TRUE; // 置命中标志 [-] / mark as found [-]
        END_IF
        IF (NOT xGot50) AND (aCumPct[i] >= 50.0) THEN
            fD50 := aSizeUm[i - 1] + ((50.0 - aCumPct[i - 1]) * (aSizeUm[i] - aSizeUm[i - 1])) / fDen; // µm + % × µm ÷ % = µm / [um] + [%] × [um] / [%] = [um]
            xGot50 := TRUE; // 置命中标志 [-] / mark as found [-]
        END_IF
        IF (NOT xGot90) AND (aCumPct[i] >= 90.0) THEN
            fD90 := aSizeUm[i - 1] + ((90.0 - aCumPct[i - 1]) * (aSizeUm[i] - aSizeUm[i - 1])) / fDen; // µm + % × µm ÷ % = µm / [um] + [%] × [um] / [%] = [um]
            xGot90 := TRUE; // 置命中标志 [-] / mark as found [-]
        END_IF
    END_IF
END_FOR
IF (NOT xGot10) OR (NOT xGot50) OR (NOT xGot90) THEN
    RETURN; // 三点未全部命中（分布不完整）拒算 [-] / incomplete distribution rejected [-]
END_IF
IF fD50 < 1.0E-9 THEN
    RETURN; // 分母闸：D50 趋零则 span 无意义 [µm] / denominator gate on D50 [um]
END_IF

// 段 4｜跨径距 span = (D90 − D10) / D50
fSpan := (fD90 - fD10) / fD50; // µm ÷ µm = 无量纲 / [um] / [um] = [-]
IF NOT (fSpan > -1.0E30 AND fSpan < 1.0E30) OR NOT (fD50 > -1.0E30 AND fD50 < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_GranuleSizeD50Calc := fD50; // 返回 D50 [µm] / return the median size [um]
END_FUNCTION
