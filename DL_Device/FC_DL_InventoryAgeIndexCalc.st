(*
  DL Factory R83 | FC_DL_InventoryAgeIndexCalc
  功能：把库龄与周转等级加权成 0~100 出库优先级指数，并给出优先级别与判定。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_InventoryAgeIndexCalc : REAL
VAR_INPUT
    fAgeDays    : REAL; // 当前库龄 [天] / Current inventory age [days]
    fMaxAgeDays : REAL; // 库龄归一化上限（超过按满分）[天] / Age normalisation ceiling [days]
    iTurnClass  : INT;  // 周转等级 1=快 2=中 3=慢 / Turnover class 1=fast 2=medium 3=slow
    fWeightAge  : REAL; // 库龄权重（0~1，其余给周转等级）[-]/ Age weight, remainder to turnover [-]
END_VAR
VAR_OUTPUT
    fAgeScore : REAL; // 库龄得分（0~100）[-]/ Age score [0..100]
    fAgeIdx   : REAL; // 综合库龄指数（0~100）[-]/ Composite age index [0..100]
    iPrioLvl  : INT;  // 优先级别 1=最高 2=中 3=低 / Priority level 1=highest 3=lowest
    xPriority : BOOL; // 优先出库判定（指数不低于 60）/ Priority pick flag, index at or above 60
    xValid    : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fTurnScore : REAL; // 周转等级得分（0~100）[-]/ Turnover score [0..100]
END_VAR
// 出口预置：五出口统一预置，优先级默认最低（安全侧）
fAgeScore := 0.0; fAgeIdx := 0.0; iPrioLvl := 3; xPriority := FALSE; xValid := FALSE;
// 非有限拦截 + 量纲自检 + 周转等级域闸（R20/R21）
IF NOT (fAgeDays > -1.0E30 AND fAgeDays < 1.0E30) OR NOT (fMaxAgeDays > -1.0E30 AND fMaxAgeDays < 1.0E30) OR NOT (fWeightAge > -1.0E30 AND fWeightAge < 1.0E30) OR fAgeDays < 0.0 OR fMaxAgeDays <= 0.0 OR iTurnClass < 1 OR iTurnClass > 3 OR fWeightAge < 0.0 OR fWeightAge > 1.0 THEN
    FC_DL_InventoryAgeIndexCalc := -1.0; RETURN; // 哨兵 -1：非有限或量纲/等级越界 / Sentinel -1
END_IF
// 库龄得分：库龄 ÷ 上限 × 100；超上限先判并封顶 100，避免饱和逻辑与实数上限冲突（R28）
IF fAgeDays >= fMaxAgeDays THEN
    fAgeScore := 100.0;             // 达到归一化上限，满分 / At ceiling, full score
ELSE
    fAgeScore := (fAgeDays / fMaxAgeDays) * 100.0;  // 线性归一化得分 / Linear normalised score
END_IF
// 周转等级得分：等级 1→100，2→66.7，3→33.3，即 (4 - 等级) ÷ 3 × 100
fTurnScore := (INT_TO_REAL(4 - iTurnClass) / 3.0) * 100.0;  // 周转得分 [-] / Turnover score
// 综合指数：库龄权重 × 库龄得分 + (1 - 权重) × 周转得分，权重和为 1 故仍 0~100
fAgeIdx := fWeightAge * fAgeScore + (1.0 - fWeightAge) * fTurnScore; // 综合指数 [-] / Composite index
// 优先级分档：指数越高越先出库，分界 80 / 60（严格不等，禁浮点等号）
IF fAgeIdx >= 80.0 THEN
    iPrioLvl := 1;                  // 最高优先级 / Highest priority
ELSIF fAgeIdx >= 60.0 THEN
    iPrioLvl := 2;                  // 中优先级 / Medium priority
ELSE
    iPrioLvl := 3;                  // 低优先级 / Low priority
END_IF
xPriority := fAgeIdx >= 60.0;       // 优先出库判定 / Priority pick flag
xValid := TRUE; FC_DL_InventoryAgeIndexCalc := fAgeIdx;  // 链路有效并返回综合指数 [-]
END_FUNCTION
