(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_ScrewPressThroughput
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 螺旋压榨机干固体（DS）处理量换算：小时量与按日运行小时数折算的日总量
*)
FUNCTION FC_DL_ScrewPressThroughput : BOOL
VAR_INPUT
    rFlowM3h : REAL; // 进泥体积流量 [m3/h] / sludge feed flow
    rTsPct : REAL; // 进泥含固率 [%] / feed total solids content
    rRunHours : REAL; // 日运行小时数 [h/d] / daily running hours
END_VAR
VAR_OUTPUT
    rDsKgH : REAL; // 干固体小时处理量 [kg/h] / dry solids throughput per hour
    rDsKgDay : REAL; // 干固体日处理量 [kg/d] / dry solids throughput per day
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=含固率超域 2=运行小时超域 3=结果非有限 / event code
END_VAR
VAR CONSTANT
    rRhoSludge : REAL := 1000.0; // 污泥近似密度 [kg/m3] / approximate sludge density
    rPctToFrac : REAL := 0.01; // 百分数转小数系数 [-]/[%] / percent to fraction factor
    rHourPerDay : REAL := 24.0; // 每日小时数 [h/d] / hours per day
END_VAR
VAR
    rDsRaw : REAL; // 未校验小时量 [kg/h] / unchecked hourly throughput
END_VAR

    // —— 段 0：全路径预清 —— //
    rDsRaw := 0.0;
    rDsKgH := 0.0;
    rDsKgDay := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_ScrewPressThroughput := FALSE;
    // —— 段 1：含固率域闸 (0, 100]% —— //
    IF (rTsPct <= 0.0) OR (rTsPct > 100.0) THEN
        iErrCode := 1; // 含固率超域，干固体量无意义 / TS out of domain, dry solids meaningless
        RETURN;
    END_IF;
    // —— 段 2：日运行小时域闸 (0, 24]h —— //
    IF (rRunHours <= 0.0) OR (rRunHours > rHourPerDay) THEN
        iErrCode := 2; // 运行小时超域 / running hours out of domain
        RETURN;
    END_IF;
    // —— 段 3：量纲链 (m3/h)*(kg/m3)*(%)*(0.01) = kg/h —— //
    rDsRaw := rFlowM3h * rRhoSludge * rTsPct * rPctToFrac; // 干固体量 [kg/h] / dry solids per hour
    IF ABS(rDsRaw) > 1.0E15 THEN
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    IF rDsRaw < 0.0 THEN
        rDsKgH := 0.0; // 负流量防御 / negative flow guard
    ELSE
        rDsKgH := rDsRaw;
    END_IF;
    // —— 段 4：日总量 = 小时量 × 日运行小时（量纲 kg/h × h/d = kg/d） —— //
    rDsKgDay := rDsKgH * rRunHours; // 日处理量 [kg/d] / dry solids per day
    bValid := TRUE;
    FC_DL_ScrewPressThroughput := TRUE;
END_FUNCTION
