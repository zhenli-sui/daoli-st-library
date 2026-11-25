(*
  DL Factory R88 | FC_DL_GearModuleFromCpCalc
  功能：由圆周节 Cp 反算齿轮模数 m=Cp/π，并校验模数是否落在 [min,max] 允许区间
  开源溯源：无（clean-room 自研，依据公开工艺公式 圆周节-模数关系 m=Cp/π，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_GearModuleFromCpCalc : REAL
VAR_INPUT
    fCpMm : REAL := 12.56637; // 圆周节 Cp（分度圆上相邻同侧齿廓的弧长） [mm] / circular pitch [mm]
    fModuleMin : REAL := 1.0; // 模数允许下限 [mm] / lower allowed module [mm]
    fModuleMax : REAL := 10.0; // 模数允许上限 [mm] / upper allowed module [mm]
END_VAR
VAR_OUTPUT
    fModuleMm : REAL; // 反算模数 m [mm] / back calculated module [mm]
    xInRange : BOOL; // TRUE=模数落在允许区间 [-] / TRUE when module inside the band [-]
END_VAR
VAR
    fPiC : REAL; // 圆周率常数（REAL 精度装入，避免长字面量截断） [-] / pi constant in REAL precision [-]
END_VAR

// 段 1｜出口预置
FC_DL_GearModuleFromCpCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fModuleMm := 0.0; // 模数出口预置零 [mm] / module output preset zero [mm]
xInRange := FALSE; // 区间位预置 FALSE（未判定前不认合格） [-] / in-range preset false [-]
fPiC := 3.14159265; // π 常数装入，无量纲 [-] / load the pi constant, dimensionless [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fCpMm > -1.0E30 AND fCpMm < 1.0E30) OR NOT (fModuleMin > -1.0E30 AND fModuleMin < 1.0E30) OR NOT (fModuleMax > -1.0E30 AND fModuleMax < 1.0E30) THEN
    RETURN; // 三入参任一非有限（NaN/±Inf）即拒算 [-] / any non finite input rejected [-]
END_IF
IF fCpMm < 1.0E-9 THEN
    RETURN; // 周节正域闸：分母 π 恒正，此处拦非正的周节输入 [mm] / positive circular pitch gate [mm]
END_IF
IF fModuleMin < 1.0E-9 OR fModuleMax <= fModuleMin THEN
    RETURN; // 区间自洽闸：下限须为正、上限须严格大于下限 [mm] / band consistency gate [mm]
END_IF

// 段 3｜计算
fModuleMm := fCpMm / fPiC; // mm ÷ 无量纲 = mm，即 m=Cp/π / [mm] / [-] = [mm], m = Cp / pi

// 段 4｜判定与饱和
IF NOT (fModuleMm > -1.0E30 AND fModuleMm < 1.0E30) THEN
    RETURN; // 商结果非有限再拦一次，防溢出成 Inf [-] / re-check the quotient for finiteness [-]
END_IF
xInRange := (fModuleMm >= fModuleMin) AND (fModuleMm <= fModuleMax); // 双侧闭区间直比（含边界） [mm] / closed two sided band compare [mm]

// 段 5｜出口自检
IF fModuleMm < 1.0E-9 THEN
    RETURN; // 出口自检：模数须为正，否则退回哨兵 [mm] / exit self-check, module must be positive [mm]
END_IF
FC_DL_GearModuleFromCpCalc := fModuleMm; // 返回反算模数 [mm] / return the back calculated module [mm]
END_FUNCTION
