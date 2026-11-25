(*
 * FC_DL_GreenSandCompactabilityCalc | C1 | DL_Process
 * 功能：由含水量反算紧实率并判定是否落在工艺带       单位：水分 [%]、紧实率 [%]、系数 [%/%、1]
 * 工况边界：w = a + b×CB 的反解 CB = (w−a)/b，b 须 >0（本件强制 b≠0，否则判 9714）；工艺带 30~45 %（含端点，浮点比较用容差）；a、b 与水分须有限
 * 代数值回代：w=3.0 %、a=1.2、b=0.04 → CB=(3.0−1.2)/0.04=45 %，落在 30~45 → xInRange=TRUE（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_GreenSandCompactabilityCalc : BOOL
VAR_INPUT
    rMoisturePct : REAL := 3.0;      // 型砂含水量 | green sand moisture [%]
    rA           : REAL := 1.2;      // 经验式截距 | empirical intercept [%]
    rB           : REAL := 0.04;     // 经验式斜率 | empirical slope [%/%]
END_VAR
VAR_OUTPUT
    rCompactabilityPct : REAL;       // 紧实率 | compactability [%]
    xInRange           : BOOL;       // 落在工艺带 30~45 | inside the process band 30 to 45
    xValid             : BOOL;       // 输出有效 | outputs valid
    nFaultCode         : INT;        // 0=无 / 9714=斜率或水分非法 | 0 none, 9714 illegal slope or moisture
END_VAR
VAR
    xFinW : BOOL;                    // 水分有限性 | moisture is finite
    xFinA : BOOL;                    // 截距有限性 | intercept is finite
    xFinB : BOOL;                    // 斜率有限性 | slope is finite
END_VAR
VAR CONSTANT
    DL_GSC_LO  : REAL := 30.0;       // 工艺带下限 | process band lower bound [%]
    DL_GSC_HI  : REAL := 45.0;       // 工艺带上限 | process band upper bound [%]
    DL_GSC_EPS : REAL := 1.0E-6;     // 浮点比较容差 | floating comparison tolerance [%]
    DL_GSC_BMIN: REAL := 1.0E-9;     // 斜率下限（防零除）| slope lower bound guarding the division [%/%]
END_VAR

// 段1｜非有限闸（R19）
xFinW := (rMoisturePct = rMoisturePct) AND ((rMoisturePct - rMoisturePct) = 0.0);
xFinA := (rA = rA) AND ((rA - rA) = 0.0);
xFinB := (rB = rB) AND ((rB - rB) = 0.0);
IF (NOT xFinW) OR (NOT xFinA) OR (NOT xFinB) THEN
    rCompactabilityPct := 0.0;       // 安全值：紧实率 0 | safe value, zero compactability
    xInRange := FALSE;
    xValid := FALSE;
    nFaultCode := 9714;
    FC_DL_GreenSandCompactabilityCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：斜率入分母必须为正，水分不得为负
IF (rB <= DL_GSC_BMIN) OR (rMoisturePct < 0.0) THEN
    rCompactabilityPct := 0.0;
    xInRange := FALSE;
    xValid := FALSE;
    nFaultCode := 9714;
    FC_DL_GreenSandCompactabilityCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：CB = (w − a)/b
rCompactabilityPct := (rMoisturePct - rA) / rB;

// 段4｜工艺带判定（判据与出口同源于原始水分推算值）
xInRange := (rCompactabilityPct >= (DL_GSC_LO - DL_GSC_EPS))
             AND (rCompactabilityPct <= (DL_GSC_HI + DL_GSC_EPS));
nFaultCode := 0;
xValid := TRUE;
FC_DL_GreenSandCompactabilityCalc := TRUE;
END_FUNCTION
