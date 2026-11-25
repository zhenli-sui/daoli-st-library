(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_PolymerDoseCalc
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: PAM 絮凝剂按干固体单耗折算质量投加量与母液体积投加量
  近似说明: 母液按「1 kg 溶液 ≈ 1 L」折算（浓度 ≤1% 时误差 <1%），已在公式处声明
*)
FUNCTION FC_DL_PolymerDoseCalc : BOOL
VAR_INPUT
    rDsKgH : REAL; // 干固体处理量 [kg/h] / dry solids throughput
    rDoseKgT : REAL; // PAM 单耗（每吨干固体）[kg/t] / polymer dose per tonne of dry solids
    rStockPct : REAL; // 母液配制浓度 [%] / stock solution concentration
END_VAR
VAR_OUTPUT
    rPolyKgH : REAL; // PAM 纯质投加量 [kg/h] / neat polymer mass flow
    rPolyLh : REAL; // PAM 母液体积投加量 [L/h] / stock solution volumetric flow
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=母液浓度超域 2=单耗为负 3=结果非有限 / event code
END_VAR
VAR CONSTANT
    rKgPerT : REAL := 1000.0; // 每吨公斤数 [kg/t] / kilograms per tonne
    rPctToFrac : REAL := 0.01; // 百分数转小数系数 [-]/[%] / percent to fraction factor
END_VAR
VAR
    rDsTh : REAL; // 干固体处理量 [t/h] / dry solids in tonnes per hour
    rPolyRaw : REAL; // 未限幅纯质投加 [kg/h] / unchecked neat polymer flow
    rStockFrac : REAL; // 母液质量分数 [-] / stock mass fraction
END_VAR

    // —— 段 0：全路径预清 —— //
    rDsTh := 0.0;
    rPolyRaw := 0.0;
    rStockFrac := 0.0;
    rPolyKgH := 0.0;
    rPolyLh := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_PolymerDoseCalc := FALSE;
    // —— 段 1：母液浓度域闸 (0, 100]% 兼分母闸 —— //
    IF (rStockPct <= 0.0) OR (rStockPct > 100.0) THEN
        iErrCode := 1; // 母液浓度超域，体积流量无定义 / stock concentration out of domain
        RETURN;
    END_IF;
    IF rDoseKgT < 0.0 THEN
        iErrCode := 2; // 单耗为负，拒绝换算 / negative dose rejected
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (kg/h)/(kg/t) = t/h；(t/h)*(kg/t) = kg/h —— //
    rDsTh := rDsKgH / rKgPerT; // 干固体 [t/h] / dry solids in t/h
    rPolyRaw := rDsTh * rDoseKgT; // 纯质 PAM [kg/h] / neat polymer flow
    IF ABS(rPolyRaw) > 1.0E15 THEN
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    IF rPolyRaw < 0.0 THEN
        rPolyKgH := 0.0; // 负干固体防御 / negative dry solids guard
    ELSE
        rPolyKgH := rPolyRaw;
    END_IF;
    // —— 段 3：母液体积 = 纯质量 / 质量分数（1 kg 溶液 ≈ 1 L 近似） —— //
    rStockFrac := rStockPct * rPctToFrac; // 质量分数 [-] / stock mass fraction
    rPolyLh := rPolyKgH / rStockFrac; // 母液体积 [L/h] / stock volumetric flow
    IF ABS(rPolyLh) > 1.0E15 THEN
        rPolyLh := 0.0;
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    bValid := TRUE;
    FC_DL_PolymerDoseCalc := TRUE;
END_FUNCTION
