(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_DewaterMassBalance
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 脱水单元干固体质量平衡：由进泥与泥饼含固率反算泥饼量、滤液量与固体回收率
*)
FUNCTION FC_DL_DewaterMassBalance : BOOL
VAR_INPUT
    rFeedM3h : REAL; // 进泥体积流量 [m3/h] / feed sludge flow
    rFeedTsPct : REAL; // 进泥含固率 [%] / feed total solids
    rCakeTsPct : REAL; // 泥饼含固率 [%] / cake total solids
    rFiltrateTsPct : REAL; // 滤液含固率 [%]，固体损失实测 / filtrate solids, measured loss
END_VAR
VAR_OUTPUT
    rCakeM3h : REAL; // 泥饼体积流量 [m3/h] / cake flow
    rFiltrateM3h : REAL; // 滤液体积流量 [m3/h] / filtrate flow
    rRecoveryPct : REAL; // 固体回收率 [%] / solids recovery
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=泥饼含固率非法或不高於进泥 2=滤液量为负已归零 3=进泥流量非法 4=结果非有限 / event code
END_VAR
VAR CONSTANT
    rRecoveryCap : REAL := 100.0; // 回收率饱和上限 [%] / recovery saturation cap
END_VAR
VAR
    rCakeRaw : REAL; // 未校验泥饼量 [m3/h] / unchecked cake flow
    rFilRaw : REAL; // 未校验滤液量 [m3/h] / unchecked filtrate flow
    rFeedSolid : REAL; // 进泥固体负荷 [%·m3/h] / feed solids product
    rLossSolid : REAL; // 滤液固体损失 [%·m3/h] / filtrate solids loss
END_VAR

    // —— 段 0：全路径预清 —— //
    rCakeRaw := 0.0;
    rFilRaw := 0.0;
    rFeedSolid := 0.0;
    rCakeM3h := 0.0;
    rFiltrateM3h := 0.0;
    rRecoveryPct := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_DewaterMassBalance := FALSE;
    // —— 段 1：分母闸与物理域闸（泥饼含固率必须高于进泥） —— //
    IF (rCakeTsPct <= 0.0) OR (rCakeTsPct <= rFeedTsPct) THEN
        iErrCode := 1; // 泥饼含固率非法或未脱水，平衡失效 / cake solids invalid or no dewatering achieved
        RETURN;
    END_IF;
    IF rFeedM3h <= 0.0 THEN
        iErrCode := 3; // 进泥流量非法 / invalid feed flow
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (%·m3/h)/(%) = m3/h —— //
    rCakeRaw := rFeedM3h * rFeedTsPct / rCakeTsPct; // 泥饼量 [m3/h] / cake flow
    IF ABS(rCakeRaw) > 1.0E15 THEN
        iErrCode := 4; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    rCakeM3h := rCakeRaw;
    // —— 段 3：滤液量 = 进泥量 - 泥饼量，负值归零并置码 —— //
    rFilRaw := rFeedM3h - rCakeM3h; // 滤液量 [m3/h] / filtrate flow
    IF rFilRaw < 0.0 THEN
        rFiltrateM3h := 0.0;
        iErrCode := 2; // 负滤液量（含固率组合不自洽）已归零 / negative filtrate clamped to zero
    ELSE
        rFiltrateM3h := rFilRaw;
    END_IF;
    // —— 段 4：回收率（分母闸：进泥固体负荷） —— //
    rFeedSolid := rFeedTsPct * rFeedM3h; // 进泥固体负荷 [%·m3/h] / feed solids
    IF ABS(rFeedSolid) <= 1.0E-9 THEN
        rRecoveryPct := 0.0; // 无固体，回收率无定义置零 / no solids, recovery undefined
    ELSE
        // 原式分子为平衡产物，恒等于 100%，改为按滤液损失实测
        IF rFiltrateTsPct < 0.0 THEN
            rFiltrateTsPct := 0.0; // 负含固率防御 / negative solids guard
        END_IF
        rLossSolid := rFiltrateTsPct * rFiltrateM3h; // 滤液带走固体 [%·m3/h] / lost solids
        rRecoveryPct := (rFeedSolid - rLossSolid) / rFeedSolid * 100.0; // 回收率 [%] / recovery by loss
        IF rRecoveryPct > rRecoveryCap THEN
            rRecoveryPct := rRecoveryCap; // 饱和 100% / saturate at 100 percent
        END_IF
    END_IF;
    bValid := TRUE;
    FC_DL_DewaterMassBalance := TRUE;
END_FUNCTION
