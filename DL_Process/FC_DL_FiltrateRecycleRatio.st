(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_FiltrateRecycleRatio
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 滤液回流比计算与随滤液返回的固体负荷核算，回流过高告警
*)
FUNCTION FC_DL_FiltrateRecycleRatio : BOOL
VAR_INPUT
    rFiltrateM3h : REAL; // 滤液回流流量 [m3/h] / filtrate recycle flow
    rFeedM3h : REAL; // 进泥（进料）流量 [m3/h] / feed flow
    rFiltrateTsPct : REAL; // 滤液含固率 [%] / filtrate total solids
END_VAR
VAR_OUTPUT
    rRatio : REAL; // 回流比 = 滤液/进料 [-]，无量纲 / recycle ratio, dimensionless
    rSolidRecycleKgH : REAL; // 随滤液返回的固体负荷 [kg/h] / solids returned with filtrate
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=进料流量非法 2=回流比过高（>0.5）3=结果非有限 / event code
END_VAR
VAR CONSTANT
    rRhoLiquid : REAL := 1000.0; // 液相近似密度 [kg/m3] / approximate liquid density
    rPctToFrac : REAL := 0.01; // 百分数转小数系数 [-]/[%] / percent to fraction factor
    rRatioHi : REAL := 0.5; // 回流比告警上限 [-] / recycle ratio alarm limit
END_VAR
VAR
    rRatioRaw : REAL; // 未限幅回流比 [-] / unlimited recycle ratio
    rTsFrac : REAL; // 滤液含固质量分数 [-] / filtrate solids mass fraction
END_VAR

    // —— 段 0：全路径预清 —— //
    rRatioRaw := 0.0;
    rTsFrac := 0.0;
    rRatio := 0.0;
    rSolidRecycleKgH := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_FiltrateRecycleRatio := FALSE;
    // —— 段 1：分母闸（进料流量） —— //
    IF rFeedM3h <= 0.0 THEN
        iErrCode := 1; // 进料流量非法，回流比无定义 / invalid feed flow, ratio undefined
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (m3/h)/(m3/h) = 无量纲 —— //
    rRatioRaw := rFiltrateM3h / rFeedM3h; // 回流比 [-] / recycle ratio
    IF ABS(rRatioRaw) > 1.0E15 THEN
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    IF rRatioRaw < 0.0 THEN
        rRatio := 0.0; // 负流量防御 / negative flow guard
    ELSE
        rRatio := rRatioRaw;
    END_IF;
    // —— 段 3：回流比过高告警（信息级，数值照给） —— //
    IF rRatio > rRatioHi THEN
        iErrCode := 2; // 信息级：回流比过高，注意固体累积 / info: recycle too high, solids build-up risk
    END_IF;
    // —— 段 4：量纲链 (m3/h)*(kg/m3)*(%)*(0.01) = kg/h —— //
    rTsFrac := rFiltrateTsPct * rPctToFrac; // 质量分数 [-] / mass fraction
    IF rTsFrac < 0.0 THEN
        rTsFrac := 0.0; // 负含固率防御 / negative solids guard
    END_IF;
    rSolidRecycleKgH := rFiltrateM3h * rRhoLiquid * rTsFrac; // 返回固体负荷 [kg/h] / returned solids
    IF ABS(rSolidRecycleKgH) > 1.0E15 THEN
        rSolidRecycleKgH := 0.0;
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    bValid := TRUE;
    FC_DL_FiltrateRecycleRatio := TRUE;
END_FUNCTION
