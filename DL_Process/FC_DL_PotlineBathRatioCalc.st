// FC_DL_PotlineBathRatioCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 电解质分子比 CR = (wNaF/41.99)/(wAlF3/83.97)（41.99/83.97 为 NaF/AlF3 摩尔质量），
        过剩 AlF3 = wAlF3 − (wNaF·83.97/41.99)/2 [%]。
  邻件/码位: 与 FC_DL_PotlineBathTempDeviationCalc 构成化验→热状态链（本件出 CR）；
             16#0002_9211 = 非有限、AlF3 过低、成分和超 100% 或 CR 出 1.5~3.5 拒收。
*)
FUNCTION FC_DL_PotlineBathRatioCalc : REAL
VAR_INPUT
    fNaFWt  : REAL := 45.0;     // NaF 质量分数 [%] / NaF mass fraction [%]
    fAlF3Wt : REAL := 40.0;     // AlF3 质量分数 [%]，域 > 0.5 / AlF3 mass fraction [%]
    fCaF2Wt : REAL := 5.0;      // CaF2 质量分数 [%] / CaF2 mass fraction [%]
END_VAR
VAR_OUTPUT
    fCryoliteRatio : REAL;      // 分子比 CR [-]，典型 2.2~2.6 / Cryolite ratio [-]
    fExcessAlF3    : REAL;      // 过剩 AlF3 [%] / Excess AlF3 [%]
    bValid         : BOOL;      // 结果有效回执 [-] / Result validity receipt
    uErrorId       : UDINT;     // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fMolNaF  : REAL := 0.0;     // NaF 摩尔相对量 [mol] / NaF mole amount [mol]
    fMolAlF3 : REAL := 0.0;     // AlF3 摩尔相对量 [mol] / AlF3 mole amount [mol]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fCryoliteRatio := 0.0;          // 分子比缺省零 / Ratio default zero
fExcessAlF3 := 0.0;             // 过剩 AlF3 缺省零 / Excess default zero
bValid := FALSE;                // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;            // 事件码预清 / Event code preset clear
FC_DL_PotlineBathRatioCalc := 0.0;      // 返回值缺省零（镜像 CR）/ Return default zero
// 段 1：非有限闸（三入参全枚举）/ Non-finite gate over all inputs
IF (fNaFWt <> fNaFWt) OR (fAlF3Wt <> fAlF3Wt) OR (fCaF2Wt <> fCaF2Wt)
   OR (ABS(fNaFWt) >= 3.0E38) OR (ABS(fAlF3Wt) >= 3.0E38) OR (ABS(fCaF2Wt) >= 3.0E38) THEN
    uErrorId := 16#0002_9211;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（AlF3 下界防除零 + 组分非负 + 成分和上界，R4）/ Domain gate
IF (fNaFWt < 0.0) OR (fCaF2Wt < 0.0) OR (fAlF3Wt <= 0.5) THEN
    uErrorId := 16#0002_9211;   // 负组分或 AlF3 过低（分母近零）/ Negative or too-low AlF3
    RETURN;
END_IF
IF (fNaFWt + fAlF3Wt + fCaF2Wt) > 100.0 THEN
    uErrorId := 16#0002_9211;   // 成分和超 100%，化验数据非法 / Sum exceeds 100 percent
    RETURN;
END_IF
// 段 3：主计算（摩尔比 + 过剩 AlF3）/ Main computation
fMolNaF := fNaFWt / 41.99;                                      // NaF 摩尔相对量 / NaF mole amount
fMolAlF3 := fAlF3Wt / 83.97;                                    // AlF3 摩尔相对量 / AlF3 mole amount
fCryoliteRatio := fMolNaF / fMolAlF3;                           // CR = nNaF/nAlF3 / Cryolite ratio
// 过剩 AlF3 基准为冰晶石 CR=3（Na3AlF6 即 3NaF·AlF3），故除以 3 而非 2
// 说明（R92-修正）：早期版本除 2，致纯冰晶石组份（CR=3）输出 −20%，符号与量级双错
fExcessAlF3 := fAlF3Wt - (fNaFWt * 83.97 / 41.99) / 3.0;        // 过剩 AlF3 [%] / Excess AlF3
// 段 4：出口闸（非有限复核 + CR 工艺窗判定）/ Outlet gate
IF (fCryoliteRatio <> fCryoliteRatio) OR (fExcessAlF3 <> fExcessAlF3)
   OR (ABS(fCryoliteRatio) >= 3.0E38) OR (ABS(fExcessAlF3) >= 3.0E38) THEN
    fCryoliteRatio := 0.0;      // 复核失败回缺省 / Fallback on recheck failure
    fExcessAlF3 := 0.0;         // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9211;   // 出口非有限拒收 / Output non-finite reject
    RETURN;
END_IF
IF (fCryoliteRatio < 1.5) OR (fCryoliteRatio > 3.5) THEN
    uErrorId := 16#0002_9211;   // 信息级：CR 出工艺窗 / Info: ratio out of window
    RETURN;                     // bValid 保持 FALSE / Validity stays false
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_PotlineBathRatioCalc := fCryoliteRatio;   // 返回值镜像 CR / Return mirrors ratio
END_FUNCTION
