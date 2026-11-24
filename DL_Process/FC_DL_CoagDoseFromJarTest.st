(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_CoagDoseFromJarTest
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 由烧杯试验最佳投加量反算混凝剂计量泵体积流量 [L/h]，含母液浓度换算、人工修正与上限饱和
*)
FUNCTION FC_DL_CoagDoseFromJarTest : BOOL
VAR_INPUT
    rJarDoseMgL : REAL; // 罐试最佳投加量（以进水体积计）[mg/L] / jar-test optimum dose per litre of raw water
    rFlowM3h : REAL; // 处理水量 [m3/h] / treated water flow
    rDoseTrim : REAL; // 人工修正系数 [1]，1.0 = 不修正 / manual trim factor, 1.0 = no trim
    rDoseMaxLh : REAL; // 计量泵投加体积上限 [L/h] / dosing pump volumetric upper limit
    rStockGL : REAL; // 母液有效浓度 [g/L] / stock solution effective concentration
END_VAR
VAR_OUTPUT
    rDoseLh : REAL; // 投加体积流量 [L/h] / dosing volumetric flow
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=母液浓度非法 2=水量非法 3=超上限饱和 4=结果非有限 / event code
END_VAR
VAR
    rDoseGh : REAL; // 药剂质量流量中间量 [g/h] / intermediate coagulant mass flow
END_VAR

    // —— 段 0：全路径预清 —— //
    rDoseGh := 0.0;
    rDoseLh := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_CoagDoseFromJarTest := FALSE;
    // —— 段 1：分母闸（母液浓度、水量） —— //
    IF ABS(rStockGL) <= 1.0E-9 THEN
        iErrCode := 1; // 母液浓度非法，无法由质量流量换算体积流量 / bad stock concentration, volume flow not derivable
        RETURN;
    END_IF;
    IF rFlowM3h <= 0.0 THEN
        iErrCode := 2; // 无处理水量，投加量保持零 / no water flow, dose held at zero
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (mg/L)*(m3/h) = (g/m3)*(m3/h) = g/h；再 /(g/L) 得 L/h —— //
    rDoseGh := rJarDoseMgL * rFlowM3h; // 药剂质量流量 [g/h] / coagulant mass flow
    rDoseLh := rDoseGh / rStockGL * rDoseTrim; // 投加体积流量 [L/h] / dosing volumetric flow
    // —— 段 3：结果域闸（非有限即归零） —— //
    IF ABS(rDoseLh) > 1.0E15 THEN
        rDoseLh := 0.0;
        iErrCode := 4; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    // —— 段 4：限幅 [0, rDoseMaxLh]，负值归零、超上限饱和并置码 —— //
    IF rDoseLh < 0.0 THEN
        rDoseLh := 0.0; // 负投加无物理意义 / negative dose is unphysical
    END_IF;
    IF rDoseLh > rDoseMaxLh THEN
        rDoseLh := MAX(rDoseMaxLh, 0.0); // 饱和到泵上限（上限为负时取零）/ saturate to pump limit, floor zero
        iErrCode := 3; // 信息级：超上限已饱和 / info level: saturated at upper limit
    END_IF;
    bValid := TRUE;
    FC_DL_CoagDoseFromJarTest := TRUE;
END_FUNCTION
