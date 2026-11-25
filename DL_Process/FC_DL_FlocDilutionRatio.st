(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_FlocDilutionRatio
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 絮凝剂由高浓度母液稀释到目标浓度的稀释比与所需母液体积
*)
FUNCTION FC_DL_FlocDilutionRatio : BOOL
VAR_INPUT
    rStockPct : REAL; // 母液质量浓度 [%] / stock solution mass concentration
    rTargetPct : REAL; // 目标使用质量浓度 [%] / target working concentration
    rTankVolL : REAL; // 配液罐有效容积 [L] / dilution tank working volume
END_VAR
VAR_OUTPUT
    rRatio : REAL; // 稀释比 = 目标浓度/母液浓度 [L母液/L配液] / dilution ratio, stock litres per litre of batch
    rStockVolL : REAL; // 需投母液体积 [L] / required stock volume
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=母液浓度非法 2=目标浓度高于母液已按 1:1 饱和 3=结果非有限 / event code
END_VAR
VAR
    rRatioUse : REAL; // 实际使用稀释比（含饱和修正）[L/L] / dilution ratio actually applied
END_VAR

    // —— 段 0：全路径预清 —— //
    rRatioUse := 0.0;
    rRatio := 0.0;
    rStockVolL := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_FlocDilutionRatio := FALSE;
    // —— 段 1：分母闸（母液浓度） —— //
    IF ABS(rStockPct) <= 1.0E-9 THEN
        iErrCode := 1; // 母液浓度非法，稀释比无定义 / bad stock concentration, ratio undefined
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (%),(%) 同量纲相除得无量纲比 [L母液/L配液] —— //
    rRatioUse := rTargetPct / rStockPct; // 稀释比 [-] / raw dilution ratio
    // —— 段 3：目标浓度不得高于母液（无法靠稀释提浓），按 1:1 饱和 —— //
    IF rTargetPct > rStockPct THEN
        rRatioUse := 1.0; // 饱和为纯母液 / saturate to neat stock
        iErrCode := 2; // 信息级：目标浓度超母液，已按 1:1 处理 / info: target above stock, clamped to 1:1
    END_IF;
    IF rRatioUse < 0.0 THEN
        rRatioUse := 0.0; // 负浓度输入防御 / negative concentration guard
    END_IF;
    rRatio := rRatioUse;
    // —— 段 4：配液体积换算与结果域闸 —— //
    rStockVolL := rTankVolL * rRatio; // 需母液体积 [L] / required stock volume
    IF (ABS(rStockVolL) > 1.0E15) OR (ABS(rRatio) > 1.0E15) THEN
        rStockVolL := 0.0;
        rRatio := 0.0;
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    bValid := TRUE;
    FC_DL_FlocDilutionRatio := TRUE;
END_FUNCTION
