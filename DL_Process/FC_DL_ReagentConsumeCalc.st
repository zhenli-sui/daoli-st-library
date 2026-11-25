(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_ReagentConsumeCalc
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 按进出口浓度差与化学计量比折算药剂消耗速率、日耗量与药罐可用天数
*)
FUNCTION FC_DL_ReagentConsumeCalc : BOOL
VAR_INPUT
    rGasNm3h : REAL; // 标态烟气量 [Nm3/h] / flue gas flow at normal conditions
    rInMgNm3 : REAL; // 入口污染物浓度 [mg/Nm3] / inlet pollutant concentration
    rOutMgNm3 : REAL; // 出口污染物浓度 [mg/Nm3] / outlet pollutant concentration
    rStoichRatio : REAL; // 药剂与污染物的质量化学计量比 [kg/kg] / stoichiometric mass ratio
    rTankKg : REAL; // 药罐当前存量 [kg] / reagent inventory in tank
END_VAR
VAR_OUTPUT
    rKgH : REAL; // 药剂小时消耗量 [kg/h] / reagent consumption per hour
    rKgDay : REAL; // 药剂日消耗量 [kg/d] / reagent consumption per day
    rDaysLeft : REAL; // 存量可用天数 [d] / inventory remaining in days
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=药罐存量非法 2=无脱除量无法推算天数 3=结果非有限 / event code
END_VAR
VAR CONSTANT
    rMgToKg : REAL := 1.0E-6; // 毫克转公斤系数 [kg/mg] / milligram to kilogram factor
    rHourPerDay : REAL := 24.0; // 每日小时数 [h/d] / hours per day
END_VAR
VAR
    rRemovalMgNm3 : REAL; // 净脱除浓度差 [mg/Nm3] / net removed concentration
    rKgHRaw : REAL; // 未校验小时消耗 [kg/h] / unchecked hourly consumption
END_VAR

    // —— 段 0：全路径预清 —— //
    rRemovalMgNm3 := 0.0;
    rKgHRaw := 0.0;
    rKgH := 0.0;
    rKgDay := 0.0;
    rDaysLeft := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_ReagentConsumeCalc := FALSE;
    // —— 段 1：药罐存量域闸 —— //
    IF rTankKg <= 0.0 THEN
        iErrCode := 1; // 药罐存量非法，可用天数置零 / invalid inventory, days left zeroed
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (mg/Nm3)*(Nm3/h)*(kg/mg) = kg/h；× (kg/kg) 仍为 kg/h —— //
    rRemovalMgNm3 := rInMgNm3 - rOutMgNm3; // 脱除浓度差 [mg/Nm3] / removed concentration
    IF rRemovalMgNm3 < 0.0 THEN
        rRemovalMgNm3 := 0.0; // 出口高于入口（仪表漂移）按零脱除 / outlet above inlet treated as no removal
    END_IF;
    rKgHRaw := rRemovalMgNm3 * rGasNm3h * rMgToKg * rStoichRatio; // 药剂消耗 [kg/h] / reagent consumption
    IF ABS(rKgHRaw) > 1.0E15 THEN
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    rKgH := rKgHRaw;
    // —— 段 3：日耗量 = 小时量 × 24（量纲 kg/h × h/d = kg/d） —— //
    rKgDay := rKgH * rHourPerDay; // 日耗量 [kg/d] / daily consumption
    // —— 段 4：可用天数（分母闸：日耗必须为正） —— //
    IF rKgDay <= 1.0E-9 THEN
        iErrCode := 2; // 无脱除量，天数无法推算，置零 / no consumption, days not derivable
        bValid := TRUE;
        FC_DL_ReagentConsumeCalc := TRUE;
        RETURN;
    END_IF;
    rDaysLeft := rTankKg / rKgDay; // 可用天数 [d] / remaining days
    IF ABS(rDaysLeft) > 1.0E15 THEN
        rDaysLeft := 0.0;
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    bValid := TRUE;
    FC_DL_ReagentConsumeCalc := TRUE;
END_FUNCTION
