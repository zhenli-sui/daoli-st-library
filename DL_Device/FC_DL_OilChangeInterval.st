(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_OilChangeInterval
  分类: DL_Device
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 按负荷、温度、污染三因子修正换油周期，并给出剩余小时与到期判定
*)
FUNCTION FC_DL_OilChangeInterval : BOOL
VAR_INPUT
    rBaseHours : REAL; // 基准换油周期 [h] / base oil change interval
    rLoadFactor : REAL; // 负荷修正因子 [-]，域 (0.1, 5.0] / load correction factor
    rTempFactor : REAL; // 温度修正因子 [-]，域 (0.1, 5.0] / temperature correction factor
    rContamFactor : REAL; // 污染修正因子 [-]，域 (0.1, 5.0] / contamination correction factor
    rHoursSince : REAL; // 上次换油后已运行小时 [h] / hours since last oil change
END_VAR
VAR_OUTPUT
    rIntervalH : REAL; // 修正后换油周期 [h] / corrected interval
    rRemainH : REAL; // 剩余可用小时 [h]，可为负（已超期）/ remaining hours, negative when overdue
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    bDue : BOOL; // 到期标志（剩余 ≤ 0）[-] / due flag
    iErrCode : INT; // 事件码 0=正常 1=修正因子超域 2=基准周期非法 3=结果非有限 / event code
END_VAR
VAR CONSTANT
    rFactorLo : REAL := 0.1; // 因子域下限（不含）[-] / factor domain lower bound, exclusive
    rFactorHi : REAL := 5.0; // 因子域上限（含）[-] / factor domain upper bound, inclusive
END_VAR
VAR
    rIntervalRaw : REAL; // 未校验周期 [h] / unchecked interval
END_VAR

    // —— 段 0：全路径预清 —— //
    rIntervalRaw := 0.0;
    rIntervalH := 0.0;
    rRemainH := 0.0;
    bValid := FALSE;
    bDue := FALSE;
    iErrCode := 0;
    FC_DL_OilChangeInterval := FALSE;
    // —— 段 1：三因子域闸（含非正因子，防周期符号翻转） —— //
    IF (rLoadFactor <= rFactorLo) OR (rLoadFactor > rFactorHi)
       OR (rTempFactor <= rFactorLo) OR (rTempFactor > rFactorHi)
       OR (rContamFactor <= rFactorLo) OR (rContamFactor > rFactorHi) THEN
        iErrCode := 1; // 修正因子超域，周期不可信 / correction factor out of domain
        RETURN;
    END_IF;
    // —— 段 2：基准周期域闸 —— //
    IF rBaseHours <= 0.0 THEN
        iErrCode := 2; // 基准周期非法，周期无定义 / invalid base interval
        RETURN;
    END_IF;
    // —— 段 3：量纲链 (h)×(-)×(-)×(-) = h —— //
    rIntervalRaw := rBaseHours * rLoadFactor * rTempFactor * rContamFactor; // 修正周期 [h] / corrected interval
    IF ABS(rIntervalRaw) > 1.0E15 THEN
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    rIntervalH := rIntervalRaw;
    // —— 段 4：剩余小时（可为负，负值即超期量）与到期判定 —— //
    rRemainH := rIntervalH - rHoursSince; // 剩余小时 [h] / remaining hours
    bDue := rRemainH <= 0.0; // 到期判定 [-] / due test
    bValid := TRUE;
    FC_DL_OilChangeInterval := TRUE;
END_FUNCTION
