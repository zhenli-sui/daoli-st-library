(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_SviCalc
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 污泥容积指数 SVI 计算（30 min 沉降体积法），含合理域告警与上限饱和
*)
FUNCTION FC_DL_SviCalc : BOOL
VAR_INPUT
    rSettledVolMl : REAL; // 30 min 沉降污泥体积（每升混合液）[mL/L] / settled sludge volume per litre
    rMlssMgL : REAL; // 混合液悬浮固体浓度 [mg/L] / mixed liquor suspended solids
END_VAR
VAR_OUTPUT
    rSviMlg : REAL; // 污泥容积指数 [mL/g] / sludge volume index
    bValid : BOOL; // 结果有效位（合理域外仅告警，仍为 TRUE）[-] / valid flag, TRUE even when out of the typical band
    iErrCode : INT; // 事件码 0=正常 1=MLSS 非法 2=超合理域告警（40~500）3=结果非有限 / event code
END_VAR
VAR CONSTANT
    rMlToL : REAL := 0.001; // 毫升转升系数 [L/mL] / millilitre to litre factor
    rMgToG : REAL := 0.001; // 毫克转克系数 [g/mg] / milligram to gram factor
    rSviLo : REAL := 40.0; // SVI 合理域下限 [mL/g] / lower bound of typical SVI band
    rSviHi : REAL := 500.0; // SVI 合理域上限 [mL/g] / upper bound of typical SVI band
    rSviCap : REAL := 999.0; // SVI 输出饱和上限 [mL/g] / output saturation cap
END_VAR
VAR
    rVolMl : REAL; // 沉降体积（负值已钳零）[mL/L] / settled volume clamped at zero
    rSviRaw : REAL; // 未限幅 SVI [mL/g] / unlimited SVI
END_VAR

    // —— 段 0：全路径预清 —— //
    rVolMl := 0.0;
    rSviRaw := 0.0;
    rSviMlg := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_SviCalc := FALSE;
    // —— 段 1：分母闸（MLSS 必须为正） —— //
    IF rMlssMgL <= 0.0 THEN
        iErrCode := 1; // MLSS 非法，SVI 无定义 / invalid MLSS, SVI undefined
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (mL/L)*(L/mL) /( (mg/L)*(g/mg) ) = (g/L)/(g/L) = mL/g —— //
    IF rSettledVolMl > 0.0 THEN
        rVolMl := rSettledVolMl; // 取输入正值 / take positive input
    END_IF;
    rSviRaw := rVolMl * rMlToL / (rMlssMgL * rMgToG); // SVI [mL/g] / sludge volume index
    // —— 段 3：结果域闸与上限饱和 —— //
    IF ABS(rSviRaw) > 1.0E15 THEN
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    IF rSviRaw > rSviCap THEN
        rSviMlg := rSviCap; // 超 999 饱和（工程上已属膨胀污泥）/ saturate at the cap
    ELSE
        rSviMlg := rSviRaw;
    END_IF;
    // —— 段 4：合理域告警（仅信息级，不影响有效位） —— //
    IF (rSviRaw < rSviLo) OR (rSviRaw > rSviHi) THEN
        iErrCode := 2; // 信息级：超出 40~500 正常带，检查污泥性状 / info: outside typical band, check sludge condition
    END_IF;
    bValid := TRUE;
    FC_DL_SviCalc := TRUE;
END_FUNCTION
