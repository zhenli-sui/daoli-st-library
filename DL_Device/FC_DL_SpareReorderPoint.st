(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_SpareReorderPoint
  分类: DL_Device
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 备件订货点与缺料量计算，触发补货判定
*)
FUNCTION FC_DL_SpareReorderPoint : BOOL
VAR_INPUT
    rDailyUse : REAL; // 日均消耗量 [件/d] / average daily consumption
    rLeadDays : REAL; // 采购提前期 [d] / procurement lead time in days
    rSafetyDays : REAL; // 安全库存天数 [d] / safety stock in days
    rOnHand : REAL; // 当前在手库存 [件] / stock on hand
END_VAR
VAR_OUTPUT
    rRop : REAL; // 订货点 [件] / reorder point
    rShortQty : REAL; // 相对订货点的缺口量 [件] / shortage against the reorder point
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    bReorder : BOOL; // 补货标志（在手 ≤ 订货点）[-] / reorder flag
    iErrCode : INT; // 事件码 0=正常 1=日耗为负 2=提前期为负已归零 3=安全天数为负已归零 4=结果非有限 / event code
END_VAR
VAR
    rLeadUse : REAL; // 生效提前期 [d] / effective lead time
    rSafetyUse : REAL; // 生效安全天数 [d] / effective safety days
    rCoverDays : REAL; // 合计覆盖天数 [d] / total coverage days
    rRopRaw : REAL; // 未校验订货点 [件] / unchecked reorder point
    rShortRaw : REAL; // 未校验缺口量 [件] / unchecked shortage
END_VAR

    // —— 段 0：全路径预清 —— //
    rLeadUse := 0.0;
    rSafetyUse := 0.0;
    rCoverDays := 0.0;
    rRopRaw := 0.0;
    rShortRaw := 0.0;
    rRop := 0.0;
    rShortQty := 0.0;
    bValid := FALSE;
    bReorder := FALSE;
    iErrCode := 0;
    FC_DL_SpareReorderPoint := FALSE;
    // —— 段 1：日耗域闸（负消耗无物理意义） —— //
    IF rDailyUse < 0.0 THEN
        iErrCode := 1; // 日耗为负，订货点不可信 / negative daily use
        RETURN;
    END_IF;
    // —— 段 2：天数负值归零（配置错误宽容处理） —— //
    IF rLeadDays < 0.0 THEN
        rLeadUse := 0.0;
        iErrCode := 2; // 提前期为负已归零 / negative lead time clamped
    ELSE
        rLeadUse := rLeadDays;
    END_IF;
    IF rSafetyDays < 0.0 THEN
        rSafetyUse := 0.0;
        iErrCode := 3; // 安全天数为负已归零 / negative safety days clamped
    ELSE
        rSafetyUse := rSafetyDays;
    END_IF;
    // —— 段 3：量纲链 (件/d)×(d) = 件 —— //
    rCoverDays := rLeadUse + rSafetyUse; // 覆盖天数 [d] / coverage days
    rRopRaw := rDailyUse * rCoverDays; // 订货点 [件] / reorder point
    IF ABS(rRopRaw) > 1.0E15 THEN
        iErrCode := 4; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    rRop := rRopRaw;
    // —— 段 4：缺口量 = MAX(0, 订货点-在手) 与补货判定 —— //
    rShortRaw := rRop - rOnHand; // 缺口 [件] / shortage
    IF rShortRaw < 0.0 THEN
        rShortQty := 0.0; // 库存充足，缺口为零 / enough stock
    ELSE
        rShortQty := rShortRaw;
    END_IF;
    bReorder := rOnHand <= rRop; // 补货标志 [-] / reorder flag
    bValid := TRUE;
    FC_DL_SpareReorderPoint := TRUE;
END_FUNCTION
