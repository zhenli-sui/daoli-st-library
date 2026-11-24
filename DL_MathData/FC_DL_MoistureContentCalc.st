// FC_DL_MoistureContentCalc v1.0.0
// 开源溯源：self-cleanroom / 公开公式（失重法含水率）
(*
  道莅工业代码库 | DL_MathData | FC_DL_MoistureContentCalc
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 失重法含水率计算：(湿重 - 干重) / 湿重 × 100%，湿重分母域闸 +
        干湿重序闸（干 > 湿 判测量矛盾）
  邻件关系: 与 ElectrolyteMoistureGuard（电解液含水防护联锁）相邻 ——
            差异点：防护件为阈值联锁动作，本件为纯计算件（无联锁输出），
            工业称重/烘干域通用
*)
FUNCTION FC_DL_MoistureContentCalc : REAL
VAR_INPUT
    fWetMassG : REAL := 0.0;    // 湿重 [g]，域 > 0 / Wet mass [g], domain > 0
    fDryMassG : REAL := 0.0;    // 干重 [g]，域 >= 0 且 <= 湿重 / Dry mass [g], domain >= 0 and <= wet
    fEps      : REAL := 1.0E-6; // 判零容差 [g] / Zero tolerance [g]
END_VAR
VAR_OUTPUT
    bValid    : BOOL;           // 结果有效回执 [-] / Result validity receipt
    uErrorId  : UDINT;          // 事件码，0 = 无事件；16#0002_2001 = 域外拒收 / Event code
END_VAR

// —— 段 0：全路径缺省 —— //
bValid   := FALSE;              // 有效回执预清 / Validity preset
uErrorId := 16#0000;            // 事件码预清 / Event code preset
FC_DL_MoistureContentCalc := 0.0;   // 返回值缺省零 / Return default zero

// —— 段 1：非有限闸 —— //
IF (fWetMassG <> fWetMassG) OR (fDryMassG <> fDryMassG)
   OR (ABS(fWetMassG) >= 3.0E38) OR (ABS(fDryMassG) >= 3.0E38) THEN
    uErrorId := 16#0002_2001;   // 输入非有限拒收（域闸码复用，R90 不加码）/ Non-finite reject
    RETURN;
END_IF

// —— 段 2：域闸（湿重正数 + 干湿序 + 负干重拒收） —— //
IF (fWetMassG < fEps) OR (fDryMassG < 0.0) OR (fDryMassG > fWetMassG) THEN
    uErrorId := 16#0002_2001;   // 信息级：湿重近零/干重为负/干重超湿重（测量矛盾）/ Info level: domain violation
    RETURN;                     // 不计算返回零 / Return zero without division
END_IF

// —— 段 3：主计算（分母已过闸） —— //
FC_DL_MoistureContentCalc := (fWetMassG - fDryMassG) / fWetMassG * 100.0;   // 含水率 [%] / Moisture content [%]
bValid := TRUE;                 // 有效回执 / Validity receipt
END_FUNCTION
