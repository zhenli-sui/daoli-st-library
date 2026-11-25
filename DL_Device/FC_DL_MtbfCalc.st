(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_MtbfCalc
  分类: DL_Device
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: MTBF / MTTR / 可用率计算，含无失效样本的退化口径
*)
FUNCTION FC_DL_MtbfCalc : BOOL
VAR_INPUT
    rRunHours : REAL; // 统计窗内累计运行小时 [h] / accumulated running hours in window
    rFailCount : REAL; // 统计窗内失效次数 [次] / failure count in window
    rRepairHours : REAL; // 统计窗内累计修复停机小时 [h] / accumulated repair downtime
END_VAR
VAR_OUTPUT
    rMtbfH : REAL; // 平均无故障间隔 [h] / mean time between failures
    rMttrH : REAL; // 平均修复时间 [h] / mean time to repair
    rAvailPct : REAL; // 可用率 [%] / availability
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=失效次数为负 2=无失效样本（MTBF 取运行小时）3=结果非有限 4=运行小时非正 5=修复小时为负 / event code
END_VAR
VAR CONSTANT
    rInvPct : REAL := 100.0; // 可用率百分数系数 [%] / percentage factor
    rAvailCap : REAL := 100.0; // 可用率饱和上限 [%] / availability cap
END_VAR
VAR
    rFailUse : REAL; // 生效失效次数 [次] / effective failure count
    rMtbfRaw : REAL; // 未校验 MTBF [h] / unchecked MTBF
    rMttrRaw : REAL; // 未校验 MTTR [h] / unchecked MTTR
    rDenom : REAL; // 可用率分母 [h] / availability denominator
END_VAR

    // —— 段 0：全路径预清 —— //
    rFailUse := 0.0;
    rMtbfRaw := 0.0;
    rMttrRaw := 0.0;
    rDenom := 0.0;
    rMtbfH := 0.0;
    rMttrH := 0.0;
    rAvailPct := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_MtbfCalc := FALSE;
    // —— 段 1：失效次数域闸 —— //
    IF rFailCount < 0.0 THEN
        iErrCode := 1; // 失效次数为负，统计口径非法 / negative failure count
        RETURN;
    END_IF;
    IF rRunHours <= 0.0 THEN
        iErrCode := 4; // 运行小时非正，MTBF 无定义 / non-positive running hours
        RETURN;
    END_IF;
    IF rRepairHours < 0.0 THEN
        iErrCode := 5; // 修复小时为负，统计口径非法 / negative repair hours
        RETURN;
    END_IF;
    // —— 段 2：无失效样本退化口径（MTBF 取运行小时，MTTR 取 0） —— //
    IF rFailCount < 0.5 THEN
        rMtbfH := rRunHours; // MTBF 取运行小时 [h] / MTBF equals running hours
        rMttrH := 0.0; // 无失效则无修复时间 / no failure, no repair time
        rAvailPct := rAvailCap; // 无失效窗内可用率按 100% 计 / availability capped at 100 percent
        iErrCode := 2; // 信息级：无失效样本 / info level: no failure sample
        bValid := TRUE;
        FC_DL_MtbfCalc := TRUE;
        RETURN;
    END_IF;
    rFailUse := rFailCount; // 生效失效次数 [次] / effective failure count
    // —— 段 3：量纲链 (h)/(次) = h —— //
    rMtbfRaw := rRunHours / rFailUse; // MTBF [h] / mean time between failures
    rMttrRaw := rRepairHours / rFailUse; // MTTR [h] / mean time to repair
    IF (ABS(rMtbfRaw) > 1.0E15) OR (ABS(rMttrRaw) > 1.0E15) THEN
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    rMtbfH := rMtbfRaw;
    rMttrH := rMttrRaw;
    // —— 段 4：可用率（分母闸：MTBF+MTTR 不能为零） —— //
    rDenom := rMtbfH + rMttrH; // 分母 [h] / denominator
    IF ABS(rDenom) <= 1.0E-9 THEN
        rAvailPct := 0.0; // 分母退化，可用率置零 / degenerate denominator
        iErrCode := 3; // 信息级：可用率不可算 / info level: availability not computable
    ELSE
        rAvailPct := rMtbfH / rDenom * rInvPct; // 可用率 [%] / availability
        IF rAvailPct > rAvailCap THEN
            rAvailPct := rAvailCap; // 上限饱和 / saturate at cap
        ELSIF rAvailPct < 0.0 THEN
            rAvailPct := 0.0; // 下限钳零 / floor at zero
        END_IF
    END_IF;
    bValid := TRUE;
    FC_DL_MtbfCalc := TRUE;
END_FUNCTION
