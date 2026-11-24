(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_BiogasYieldCalc
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 厌氧消化沼气产量估算：进料 VS 量 × 降解率 × 单位产气率，折算日量与小时量
*)
FUNCTION FC_DL_BiogasYieldCalc : BOOL
VAR_INPUT
    rVsKgDay : REAL; // 进料挥发性固体量 [kg VS/d] / volatile solids fed per day
    rVsDestroyPct : REAL; // VS 降解率 [%] / volatile solids destruction rate
    rYieldM3KgVs : REAL; // 单位产气率 [m3/kgVS] / specific biogas yield
END_VAR
VAR_OUTPUT
    rGasM3Day : REAL; // 沼气日产量 [m3/d] / daily biogas production
    rGasM3h : REAL; // 沼气小时产量 [m3/h] / hourly biogas production
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=进料 VS 为负 2=降解率超域 3=产气率非法 4=结果非有限 / event code
END_VAR
VAR CONSTANT
    rPctToFrac : REAL := 0.01; // 百分数转小数系数 [-]/[%] / percent to fraction factor
    rHourPerDay : REAL := 24.0; // 每日小时数 [h/d] / hours per day
END_VAR
VAR
    rDestroyFrac : REAL; // 降解率小数 [-] / destruction fraction
    rGasRaw : REAL; // 未校验日产量 [m3/d] / unchecked daily production
END_VAR

    // —— 段 0：全路径预清 —— //
    rDestroyFrac := 0.0;
    rGasRaw := 0.0;
    rGasM3Day := 0.0;
    rGasM3h := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_BiogasYieldCalc := FALSE;
    // —— 段 1：输入域闸 —— //
    IF rVsKgDay < 0.0 THEN
        iErrCode := 1; // 进料 VS 为负，产气量无意义 / negative volatile solids
        RETURN;
    END_IF;
    IF (rVsDestroyPct <= 0.0) OR (rVsDestroyPct > 100.0) THEN
        iErrCode := 2; // 降解率超域 (0,100] / destruction rate out of domain
        RETURN;
    END_IF;
    IF rYieldM3KgVs <= 0.0 THEN
        iErrCode := 3; // 产气率非法，产气量无定义 / invalid specific yield
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (kgVS/d)×(-)×(m3/kgVS) = m3/d —— //
    rDestroyFrac := rVsDestroyPct * rPctToFrac; // 降解率 [-] / destruction fraction
    rGasRaw := rVsKgDay * rDestroyFrac * rYieldM3KgVs; // 日产量 [m3/d] / daily production
    IF ABS(rGasRaw) > 1.0E15 THEN
        iErrCode := 4; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    rGasM3Day := rGasRaw;
    // —— 段 3：小时量 = 日量 / 24（量纲 (m3/d)/(h/d) = m3/h） —— //
    rGasM3h := rGasM3Day / rHourPerDay; // 小时产量 [m3/h] / hourly production
    bValid := TRUE;
    FC_DL_BiogasYieldCalc := TRUE;
END_FUNCTION
