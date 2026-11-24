(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_StackEmissionDilute
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 排放浓度干基折算与基准氧折算（20.9% 干烟气含氧基准口径）
*)
FUNCTION FC_DL_StackEmissionDilute : BOOL
VAR_INPUT
    rMeasMgNm3 : REAL; // 实测湿基浓度 [mg/Nm3] / measured wet-basis concentration
    rO2MeasPct : REAL; // 实测含氧量 [%] / measured oxygen content
    rO2RefPct : REAL; // 折算基准含氧量 [%]，典型 6 或 11 / reference oxygen content
    rMoistPct : REAL; // 烟气含湿量 [%] / flue gas moisture content
END_VAR
VAR_OUTPUT
    rDryMgNm3 : REAL; // 干基浓度 [mg/Nm3] / dry-basis concentration
    rRefMgNm3 : REAL; // 基准氧折算浓度 [mg/Nm3] / reference-oxygen corrected concentration
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=实测氧接近基准导致分母过小 2=含湿量超域 3=基准氧非法 4=结果非有限 / event code
END_VAR
VAR CONSTANT
    rO2Air : REAL := 20.9; // 干空气含氧量 [%] / oxygen in dry air
    rO2MinGap : REAL := 0.5; // 分母最小允许间隙 [%] / minimum denominator gap
    rMoistMax : REAL := 99.0; // 含湿量上限 [%] / moisture upper bound
    rPctToFrac : REAL := 0.01; // 百分数转小数系数 [-]/[%] / percent to fraction factor
END_VAR
VAR
    rDryFactor : REAL; // 干基换算因子 [-] / dry basis factor
    rO2GapMeas : REAL; // 实测氧与空气氧差 [%] / measured oxygen gap
    rO2GapRef : REAL; // 基准氧与空气氧差 [%] / reference oxygen gap
    rDryRaw : REAL; // 未校验干基浓度 [mg/Nm3] / unchecked dry concentration
    rRefRaw : REAL; // 未校验折算浓度 [mg/Nm3] / unchecked corrected concentration
END_VAR

    // —— 段 0：全路径预清 —— //
    rDryFactor := 0.0;
    rO2GapMeas := 0.0;
    rO2GapRef := 0.0;
    rDryRaw := 0.0;
    rRefRaw := 0.0;
    rDryMgNm3 := 0.0;
    rRefMgNm3 := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_StackEmissionDilute := FALSE;
    // —— 段 1：含湿量域闸与干基换算分母闸 —— //
    IF (rMoistPct < 0.0) OR (rMoistPct > rMoistMax) THEN
        iErrCode := 2; // 含湿量超域，干基换算无意义 / moisture out of domain
        RETURN;
    END_IF;
    rDryFactor := 1.0 - rMoistPct * rPctToFrac; // 干基因子 [-] / dry basis factor
    IF rDryFactor <= 1.0E-9 THEN
        iErrCode := 2; // 干基因子退化（近全湿）/ degenerate dry factor
        RETURN;
    END_IF;
    // —— 段 2：干基浓度 = 湿基/干基因子 —— //
    rDryRaw := rMeasMgNm3 / rDryFactor; // 干基浓度 [mg/Nm3] / dry concentration
    // —— 段 3：基准氧折算分母闸（实测氧不得接近空气氧） —— //
    rO2GapMeas := rO2Air - rO2MeasPct; // 实测氧间隙 [%] / measured gap
    IF ABS(rO2GapMeas) < rO2MinGap THEN
        iErrCode := 1; // 实测氧接近 20.9%，折算分母过小 / measured oxygen too close to air value
        RETURN;
    END_IF;
    rO2GapRef := rO2Air - rO2RefPct; // 基准氧间隙 [%] / reference gap
    IF rO2GapRef <= 0.0 THEN
        iErrCode := 3; // 基准氧不得高于空气氧 / reference oxygen above air value
        RETURN;
    END_IF;
    // —— 段 4：量纲链 (mg/Nm3)*(%)/(%) = mg/Nm3 —— //
    rRefRaw := rDryRaw * rO2GapRef / rO2GapMeas; // 折算浓度 [mg/Nm3] / corrected concentration
    IF (ABS(rDryRaw) > 1.0E15) OR (ABS(rRefRaw) > 1.0E15) THEN
        iErrCode := 4; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    rDryMgNm3 := rDryRaw;
    rRefMgNm3 := rRefRaw;
    bValid := TRUE;
    FC_DL_StackEmissionDilute := TRUE;
END_FUNCTION
