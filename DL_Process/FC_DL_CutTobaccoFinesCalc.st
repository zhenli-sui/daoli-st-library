(*
 * FC_DL_CutTobaccoFinesCalc | C1 | DL_Process
 * 功能：碎丝率（≤0.5 mm 占比）与整丝率（≥2.5 mm 占比）       单位：质量 [g]、占比 [%]
 * 工况边界：样品质量须 >0（入分母）；两率之和 >100 % 说明筛分数据自相矛盾，判 9511；筛网规格固定为 0.5 mm 与 2.5 mm，更换筛网须重新标定；中间档丝（0.5~2.5 mm）占比作为信息量输出
 * 代数值回代：m=100 g、fines=8 g、long=85 g → 碎丝率 8.0 %、整丝率 85.0 %、中间档 7.0 %（合计 100 %，与 spec 判定式一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_CutTobaccoFinesCalc : BOOL
VAR_INPUT
    rSampleG : REAL := 100.0;        // 样品总质量 | total sample mass [g]
    rFinesG  : REAL;                 // 碎丝质量（≤0.5 mm）| fines mass, 0.5 mm and below [g]
    rLongG   : REAL;                 // 整丝质量（≥2.5 mm）| long strands, 2.5 mm and above [g]
END_VAR
VAR_OUTPUT
    rFinesPct : REAL;                // 碎丝率 | fines ratio [%]
    rLongPct  : REAL;                // 整丝率 | long strand ratio [%]
    rMidPct   : REAL;                // 中间档占比（信息量）| middle fraction ratio, informational [%]
    xValid    : BOOL;                // 输出有效 | outputs valid
    nFaultCode: INT;                 // 0=无 / 9511=样品或筛分数据非法 | 0 none, 9511 illegal sample or sieve data
END_VAR
VAR
    xFinS : BOOL;                    // 样品质量有限性 | sample mass is finite
    xFinF : BOOL;                    // 碎丝质量有限性 | fines mass is finite
    xFinL : BOOL;                    // 整丝质量有限性 | long strand mass is finite
    rSumPct : REAL;                  // 两率之和 | sum of the two ratios [%]
END_VAR
VAR CONSTANT
    DL_CTF_PCT     : REAL := 100.0;  // 百分数换算系数 | percentage factor [%]
    DL_CTF_S_MIN   : REAL := 1.0E-6; // 样品质量下限（防零除）| sample mass lower bound [g]
    DL_CTF_SUM_MAX : REAL := 100.0;  // 两率之和上限 | upper bound of the summed ratios [%]
    DL_CTF_EPS     : REAL := 1.0E-6; // 浮点比较容差 | floating comparison tolerance [%]
END_VAR

// 段1｜非有限闸（R19）
xFinS := (rSampleG = rSampleG) AND ((rSampleG - rSampleG) = 0.0);
xFinF := (rFinesG = rFinesG) AND ((rFinesG - rFinesG) = 0.0);
xFinL := (rLongG = rLongG) AND ((rLongG - rLongG) = 0.0);
IF (NOT xFinS) OR (NOT xFinF) OR (NOT xFinL) THEN
    rFinesPct := 0.0;                // 安全值：两率 0 | safe value, zero ratios
    rLongPct := 0.0;
    rMidPct := 0.0;
    xValid := FALSE;
    nFaultCode := 9511;
    FC_DL_CutTobaccoFinesCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：样品质量入分母必须 >0，两档质量不得为负
IF (rSampleG <= DL_CTF_S_MIN) OR (rFinesG < 0.0) OR (rLongG < 0.0) THEN
    rFinesPct := 0.0;
    rLongPct := 0.0;
    rMidPct := 0.0;
    xValid := FALSE;
    nFaultCode := 9511;
    FC_DL_CutTobaccoFinesCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：两率各按样品总量计算
rFinesPct := rFinesG / rSampleG * DL_CTF_PCT;
rLongPct := rLongG / rSampleG * DL_CTF_PCT;
rSumPct := rFinesPct + rLongPct;

// 段4｜数据自洽校验：两率之和不得超过 100 %
IF rSumPct > (DL_CTF_SUM_MAX + DL_CTF_EPS) THEN
    rMidPct := 0.0;                  // 安全值：中间档置 0 | safe value, middle fraction zeroed
    xValid := FALSE;
    nFaultCode := 9511;
    FC_DL_CutTobaccoFinesCalc := FALSE;
    RETURN;
END_IF

// 段5｜中间档与出口
rMidPct := DL_CTF_SUM_MAX - rSumPct;
nFaultCode := 0;
xValid := TRUE;
FC_DL_CutTobaccoFinesCalc := TRUE;
END_FUNCTION
