(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_CakeSolidsCalc
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 由进泥与出泥体积做干固体质量平衡，反算泥饼含固率与固体回收率（同密度近似）
*)
FUNCTION FC_DL_CakeSolidsCalc : BOOL
VAR_INPUT
    rFeedTsPct : REAL; // 进泥含固率 [%] / feed total solids
    rFeedM3h : REAL; // 进泥体积流量 [m3/h] / feed flow
    rCakeM3h : REAL; // 出泥饼体积流量 [m3/h] / cake flow
    rFiltrateTsPct : REAL; // 滤液含固率 [%]，固体损失实测 / filtrate solids, measured loss
END_VAR
VAR_OUTPUT
    rCakeTsPct : REAL; // 泥饼含固率 [%] / cake total solids
    rRecoveryPct : REAL; // 固体回收率 [%] / solids recovery
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=泥饼流量非法 2=体积不守恒 3=进泥流量非法 4=进泥含固率非法 5=结果非有限 / event code
END_VAR
VAR CONSTANT
    rRecoveryCap : REAL := 100.0; // 回收率饱和上限 [%] / recovery saturation cap
END_VAR
VAR
    rCakeTsRaw : REAL; // 未限幅泥饼含固率 [%] / unlimited cake solids
    rFeedSolid : REAL; // 进泥固体负荷 [%·m3/h] / feed solids product
    rCakeSolid : REAL; // 泥饼固体负荷 [%·m3/h] / cake solids product
    rRecoveryRaw : REAL; // 未限幅回收率 [%] / unlimited recovery
    rLossSolid : REAL; // 滤液固体损失 [%·m3/h] / filtrate solids loss
END_VAR

    // —— 段 0：全路径预清 —— //
    rCakeTsRaw := 0.0;
    rFeedSolid := 0.0;
    rCakeSolid := 0.0;
    rRecoveryRaw := 0.0;
    rCakeTsPct := 0.0;
    rRecoveryPct := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_CakeSolidsCalc := FALSE;
    // —— 段 1：分母闸（泥饼体积、进泥体积） —— //
    IF rCakeM3h <= 0.0 THEN
        iErrCode := 1; // 泥饼流量非法，含固率无定义 / invalid cake flow, cake solids undefined
        RETURN;
    END_IF;
    IF rFeedM3h <= 0.0 THEN
        iErrCode := 3; // 进泥流量非法 / invalid feed flow
        RETURN;
    END_IF;
    // —— 段 2：体积守恒预检（出泥体积不得大于进泥体积） —— //
    IF rCakeM3h > rFeedM3h THEN
        iErrCode := 2; // 体积不守恒，物料平衡失效 / volume not conserved, balance invalid
        RETURN;
    END_IF;
    // —— 段 3：量纲链 (%·m3/h)/(m3/h) = %（同密度近似消去 kg/m3） —— //
    rCakeTsRaw := rFeedTsPct * rFeedM3h / rCakeM3h; // 泥饼含固率 [%] / cake total solids
    IF ABS(rCakeTsRaw) > 1.0E15 THEN
        iErrCode := 5; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    rCakeTsPct := rCakeTsRaw;
    // —— 段 4：固体回收率（分母闸：进泥含固率必须为正） —— //
    IF rFeedTsPct <= 0.0 THEN
        iErrCode := 4; // 进泥含固率非法，回收率置零 / invalid feed solids, recovery set to zero
        bValid := TRUE;
        FC_DL_CakeSolidsCalc := TRUE;
        RETURN;
    END_IF;
    rFeedSolid := rFeedTsPct * rFeedM3h; // 进泥固体负荷 [%·m3/h] / feed solids product
    IF rFiltrateTsPct < 0.0 THEN
        rFiltrateTsPct := 0.0; // 负含固率防御 / negative solids guard
    END_IF
    rCakeSolid := rCakeTsPct * rCakeM3h; // 泥饼固体负荷 [%·m3/h] / cake solids product
    // 原式 cakeSolid/feedSolid 恒等于 1（cakeTs 由平衡反算），改为按滤液固体损失实测：
    // 量纲: (m3/h)*(%) / ((m3/h)*(%)) = 无量纲，乘 100 得 %
    rLossSolid := rFiltrateTsPct * (rFeedM3h - rCakeM3h); // 滤液带走固体 [%·m3/h] / solids lost with filtrate
    rRecoveryRaw := (rFeedSolid - rLossSolid) / rFeedSolid * 100.0; // 回收率 [%] / recovery by loss
    IF rRecoveryRaw > rRecoveryCap THEN
        rRecoveryPct := rRecoveryCap; // 超 100% 饱和（仪表误差口径）/ saturate at 100 percent
    ELSIF rRecoveryRaw < 0.0 THEN
        rRecoveryPct := 0.0; // 负值防御 / negative guard
    ELSE
        rRecoveryPct := rRecoveryRaw;
    END_IF;
    bValid := TRUE;
    FC_DL_CakeSolidsCalc := TRUE;
END_FUNCTION
