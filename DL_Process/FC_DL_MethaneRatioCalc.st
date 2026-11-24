(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_MethaneRatioCalc
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 沼气组分平衡求甲烷含量与低位热值 LHV，含 H2S 腐蚀告警
*)
FUNCTION FC_DL_MethaneRatioCalc : BOOL
VAR_INPUT
    rCo2Pct : REAL; // 二氧化碳体积分数 [%] / CO2 volume fraction
    rN2Pct : REAL; // 氮气体积分数 [%] / N2 volume fraction
    rO2Pct : REAL; // 氧气体积分数 [%] / O2 volume fraction
    rH2sPpm : REAL; // 硫化氢浓度 [ppm] / H2S concentration in ppm
END_VAR
VAR_OUTPUT
    rCh4Pct : REAL; // 甲烷体积分数 [%] / methane volume fraction
    rLhvMJm3 : REAL; // 低位热值 [MJ/m3] / lower heating value
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=组分和超 100（甲烷按 0 饱和）2=H2S 超 500ppm 告警 3=结果非有限 / event code
END_VAR
VAR CONSTANT
    rPctFull : REAL := 100.0; // 组分满量程 [%] / full scale of volume fraction
    rCh4Lhv : REAL := 35.8; // 纯甲烷低位热值 [MJ/m3] / LHV of pure methane
    rH2sLimit : REAL := 500.0; // H2S 腐蚀告警门槛 [ppm] / H2S corrosion alarm threshold
    rPctToFrac : REAL := 0.01; // 百分数转小数系数 [-]/[%] / percent to fraction factor
END_VAR
VAR
    rSumPct : REAL; // 非甲烷组分之和 [%] / sum of non-methane fractions
    rCh4Raw : REAL; // 未饱和甲烷含量 [%] / unlimited methane fraction
END_VAR

    // —— 段 0：全路径预清 —— //
    rSumPct := 0.0;
    rCh4Raw := 0.0;
    rCh4Pct := 0.0;
    rLhvMJm3 := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_MethaneRatioCalc := FALSE;
    // —— 段 1：量纲链 (% + % + %) = % —— //
    rSumPct := rCo2Pct + rN2Pct + rO2Pct; // 非甲烷组分和 [%] / non-methane sum
    // —— 段 2：组分和非负性与满量程闸 —— //
    IF rSumPct < 0.0 THEN
        iErrCode := 1; // 组分和为负，分析仪故障 / negative sum, analyser fault
        RETURN;
    END_IF;
    rCh4Raw := rPctFull - rSumPct; // 甲烷 = 100 - 其余 [%] / methane by difference
    // —— 段 3：甲烷负值饱和为 0 并置信息码 —— //
    IF (rCo2Pct < 0.0) OR (rN2Pct < 0.0) OR (rO2Pct < 0.0) THEN
        iErrCode := 4; // 组分负值：传感器非法，甲烷不可信 / negative component: invalid sensor
        bValid := FALSE;
        FC_DL_MethaneRatioCalc := TRUE;
        RETURN;
    END_IF
    IF rCh4Raw > 100.0 THEN
        rCh4Pct := 100.0; // 组分和偏低导致外推超 100%，饱和 / extrapolated above 100 percent, clamp
    ELSIF rCh4Raw < 0.0 THEN
        rCh4Pct := 0.0;
        iErrCode := 1; // 组分和超 100%，甲烷按零饱和 / sum above 100 percent, methane floored at zero
    ELSE
        rCh4Pct := rCh4Raw;
    END_IF;
    // —— 段 4：热值 (MJ/m3) = 甲烷份额 × 纯甲烷 LHV；H2S 告警 —— //
    rLhvMJm3 := rCh4Pct * rPctToFrac * rCh4Lhv; // 低位热值 [MJ/m3] / lower heating value
    IF ABS(rLhvMJm3) > 1.0E15 THEN
        rLhvMJm3 := 0.0;
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    IF rH2sPpm > rH2sLimit THEN
        iErrCode := 2; // 信息级：H2S 超限，注意脱硫与腐蚀 / info: H2S high, check desulfurisation
    END_IF;
    bValid := TRUE;
    FC_DL_MethaneRatioCalc := TRUE;
END_FUNCTION
