(*
  DL Factory R83 | FC_DL_AnodeCurrentDensityCalc
  功能：按阳极几何尺寸与遮蔽系数算有效阳极面积，并换算阳极电流密度。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_AnodeCurrentDensityCalc : REAL
VAR_INPUT
    fTotalCurrentA : REAL; // 整流器总电流 [A] / Rectifier total current [A]
    fAnodeWMm      : REAL; // 单片阳极宽度 [mm] / Anode plate width [mm]
    fAnodeHMm      : REAL; // 单片阳极浸没高度 [mm] / Anode immersed height [mm]
    nAnodeCnt      : INT;  // 阳极片数 [片] / Number of anode plates [-]
    fShadowPct     : REAL; // 有效面积系数（遮蔽后，0~100）[%] / Effective area factor [%]
END_VAR
VAR_OUTPUT
    fAreaGrossDm2 : REAL; // 阳极几何总面积 [dm²] / Gross anode area [dm^2]
    fAreaEffDm2   : REAL; // 有效阳极面积（乘遮蔽系数）[dm²] / Effective anode area [dm^2]
    fJADm2        : REAL; // 阳极电流密度 [A/dm²] / Anodic current density [A/dm^2]
    xValid        : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
// 出口预置：四出口统一预置（R256）
fAreaGrossDm2 := 0.0; fAreaEffDm2 := 0.0; fJADm2 := 0.0; xValid := FALSE;
// 非有限拦截 + 量纲自检 + 阳极片数域闸（R20/R21）
IF NOT (fTotalCurrentA > -1.0E30 AND fTotalCurrentA < 1.0E30) OR NOT (fAnodeWMm > -1.0E30 AND fAnodeWMm < 1.0E30) OR NOT (fAnodeHMm > -1.0E30 AND fAnodeHMm < 1.0E30) OR NOT (fShadowPct > -1.0E30 AND fShadowPct < 1.0E30) OR fAnodeWMm <= 0.0 OR fAnodeHMm <= 0.0 OR nAnodeCnt < 1 OR fShadowPct <= 0.0 THEN
    FC_DL_AnodeCurrentDensityCalc := -1.0; RETURN; // 哨兵 -1：非有限或量纲/片数越界 / Sentinel -1
END_IF
// 遮蔽系数域闸：0~100% 之外钳位，保证有效面积不超几何面积
IF fShadowPct > 100.0 THEN
    fShadowPct := 100.0;            // 上限钳位 [%] / Clamp upper bound to 100 percent
END_IF
// 几何面积：mm² × 片数 ÷ 10000 = cm²，再 ÷ 100 = dm²（1 dm² = 100 cm²，量纲自洽）
fAreaGrossDm2 := fAnodeWMm * fAnodeHMm * INT_TO_REAL(nAnodeCnt) / 10000.0 / 100.0; // 总面积 [dm²]
// 有效面积：几何面积 × 遮蔽系数（阴影与挂具遮挡后的真实导电面）
fAreaEffDm2 := fAreaGrossDm2 * (fShadowPct / 100.0); // 有效面积 [dm²] / Effective area [dm^2]
// 电流密度：A ÷ dm² = A/dm²，有效面积分母显式零闸（R4/R21）
IF ABS(fAreaEffDm2) > 1.0E-9 THEN    // 面积分母显式零闸 / Explicit zero gate on area
    fJADm2 := fTotalCurrentA / fAreaEffDm2; // 阳极电流密度 [A/dm²] / Anodic current density
ELSE
    fJADm2 := 0.0;                  // 除零防御缺省 / Divide-by-zero default
END_IF
xValid := TRUE;                                // 链路有效 / Chain valid
FC_DL_AnodeCurrentDensityCalc := fJADm2;       // 返回阳极电流密度 [A/dm²] / Return [A/dm^2]
END_FUNCTION
