(*
  DL Factory R84 | FC_DL_JacketAreaCalc
  功能：由所需换热量与总传热系数算夹套/盘管传热面积，含 LMTD 计算与面积校核
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_JacketAreaCalc : REAL
VAR_INPUT
    fQDutyKw : REAL := 120.0; // 所需换热量 [kW] / required heat duty [kW]
    fKWm2K : REAL := 350.0; // 总传热系数 [W/(m²·K)] / overall heat transfer coefficient [W/(m^2*K)]
    fThInC : REAL := 90.0; // 热侧进口温度 [℃] / hot side inlet temperature [C]
    fThOutC : REAL := 70.0; // 热侧出口温度 [℃] / hot side outlet temperature [C]
    fTcInC : REAL := 25.0; // 冷侧进口温度 [℃] / cold side inlet temperature [C]
    fTcOutC : REAL := 40.0; // 冷侧出口温度 [℃] / cold side outlet temperature [C]
    fAreaAvailM2 : REAL := 6.0; // 现有可用传热面积（校核用） [m²] / available heat transfer area [m^2]
END_VAR
VAR_OUTPUT
    fLmtd : REAL; // 对数平均温差 [K] / log mean temperature difference [K]
    fQreqKw : REAL; // 所需换热量回显（链路校验） [kW] / required duty echo [kW]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fDt1K : REAL; // 端差 1（热进 − 冷出） [K] / terminal difference one [K]
    fDt2K : REAL; // 端差 2（热出 − 冷进） [K] / terminal difference two [K]
    fAreaM2 : REAL; // 所需传热面积 [m²] / required area [m^2]
    xAreaOk : BOOL; // 面积是否满足（A 需求 ≤ 可用） [-] / area adequacy verdict [-]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_JacketAreaCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fLmtd := 0.0; // LMTD 预置零 [K] / LMTD preset zero [K]
fQreqKw := 0.0; // 热量回显预置零 [kW] / duty echo preset zero [kW]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fQDutyKw > -1.0E30 AND fQDutyKw < 1.0E30) OR NOT (fKWm2K > -1.0E30 AND fKWm2K < 1.0E30) OR NOT (fThInC > -1.0E30 AND fThInC < 1.0E30) OR NOT (fThOutC > -1.0E30 AND fThOutC < 1.0E30) THEN
    RETURN; // 热量/系数/热侧温度任一非有限即拒算 [-] / any non finite duty, coefficient or hot side rejected [-]
END_IF
IF NOT (fTcInC > -1.0E30 AND fTcInC < 1.0E30) OR NOT (fTcOutC > -1.0E30 AND fTcOutC < 1.0E30) OR NOT (fAreaAvailM2 > -1.0E30 AND fAreaAvailM2 < 1.0E30) THEN
    RETURN; // 冷侧温度或可用面积非有限即拒算 [-] / any non finite cold side or area rejected [-]
END_IF
IF fKWm2K < 1.0E-9 OR fQDutyKw < 0.0 OR fAreaAvailM2 < 0.0 THEN
    RETURN; // K 值正域分母闸 + 热量/面积非负闸 [W/(m²·K), kW, m²] / positive K denominator gate [-]
END_IF

// 段 3｜端差与 LMTD
fDt1K := fThInC - fTcOutC; // ℃ − ℃ = K（温差） / [C] minus [C] = [K]
fDt2K := fThOutC - fTcInC; // ℃ − ℃ = K（温差） / [C] minus [C] = [K]
IF (fDt1K < 1.0E-9) OR (fDt2K < 1.0E-9) THEN
    RETURN; // 任一端差非正：温度交叉或逆流不可行，拒算 [-] / non positive terminal difference rejected [-]
END_IF
IF ABS(fDt1K - fDt2K) < 1.0E-9 THEN
    fLmtd := fDt1K; // 两端差相等时 LMTD 退化为该端差 [K] / degenerate case, LMTD equals the difference [K]
ELSE
    fLmtd := (fDt1K - fDt2K) / LN(fDt1K / fDt2K); // K ÷ 无量纲 = K（K/K 取对数无量纲） / [K] / [-] = [K]
END_IF
IF NOT (fLmtd > 1.0E-9) OR NOT (fLmtd < 1.0E30) THEN
    RETURN; // LMTD 分母闸：必须为正有限值 [K] / LMTD must be positive and finite [K]
END_IF

// 段 4｜面积 A = Q / (K × LMTD)，并与可用面积校核
fAreaM2 := (fQDutyKw * 1000.0) / (fKWm2K * fLmtd); // (kW×1000 = W) ÷ (W/(m²·K)×K) = m² / [kW]×1000 / ([W/(m^2*K)]×[K]) = [m^2]
IF NOT (fAreaM2 > -1.0E30 AND fAreaM2 < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF
xAreaOk := fAreaM2 <= fAreaAvailM2; // m² 直比，禁浮点等值 [-] / direct compare of the areas [m^2]
fQreqKw := fQDutyKw; // 回显所需换热量 [kW] / echo the required duty [kW]
xValid := xAreaOk; // 面积不足即判无效（需加大设备或提 K 值） [-] / area shortage voids the result [-]
FC_DL_JacketAreaCalc := fAreaM2; // 返回所需面积 [m²] / return the required area [m^2]
END_FUNCTION
