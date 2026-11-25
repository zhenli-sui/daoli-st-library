(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_PackedBedHtu
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 填料吸收塔传质单元高度 HTU 与塔高估算（含 1.2 倍设计余量）
  假设声明: 气相摩尔质量按空气口径 29 kg/kmol 折算 kmol/h（低浓度污染物可忽略）
*)
FUNCTION FC_DL_PackedBedHtu : BOOL
VAR_INPUT
    rGasKgH : REAL; // 气相质量流量 [kg/h] / gas mass flow
    rLiquidKgH : REAL; // 液相质量流量 [kg/h] / liquid mass flow
    rKgaKmolM3h : REAL; // 体积总传质系数 Kga [kmol/(m3·h·atm)] / overall volumetric mass transfer coefficient
    rAreaM2 : REAL; // 塔截面积 [m2] / column cross-section area
    rNtu : REAL; // 传质单元数 NTU [-] / number of transfer units
    rPressAtm : REAL; // 操作压力 [atm]，Kga 为 atm 基 / operating pressure, Kga basis
END_VAR
VAR_OUTPUT
    rHtuM : REAL; // 传质单元高度 [m] / height of a transfer unit
    rHeightM : REAL; // 填料层高度（含余量）[m] / packed bed height with margin
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=Kga 非法 2=塔截面非法 3=无液相（填料未润湿）4=NTU 非法 5=结果非有限 / event code
END_VAR
VAR CONSTANT
    rMolWtGas : REAL := 29.0; // 气相平均摩尔质量 [kg/kmol] / mean gas molar mass
    rHeightMargin : REAL := 1.2; // 塔高设计余量系数 [-] / packed height design margin
END_VAR
VAR
    rGasKmolH : REAL; // 气相摩尔流量 [kmol/h] / gas molar flow
    rHtuRaw : REAL; // 未校验 HTU [m] / unchecked HTU
END_VAR

    // —— 段 0：全路径预清 —— //
    rGasKmolH := 0.0;
    rHtuRaw := 0.0;
    rHtuM := 0.0;
    rHeightM := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_PackedBedHtu := FALSE;
    // —— 段 1：分母闸（传质系数、塔截面） —— //
    IF rKgaKmolM3h <= 0.0 THEN
        iErrCode := 1; // 传质系数非法，HTU 无定义 / invalid mass transfer coefficient
        RETURN;
    END_IF;
    IF rAreaM2 <= 0.0 THEN
        iErrCode := 2; // 塔截面非法 / invalid column area
        RETURN;
    END_IF;
    // —— 段 2：液相存在性闸（无液膜则 Kga 不成立） —— //
    IF rLiquidKgH <= 0.0 THEN
        iErrCode := 3; // 无液相，填料未润湿，Kga 无效 / no liquid, packing not wetted, Kga invalid
        RETURN;
    END_IF;
    IF rNtu <= 0.0 THEN
        iErrCode := 4; // NTU 非法，塔高无意义 / invalid NTU
        RETURN;
    END_IF;
    // —— 段 3：量纲链 (kg/h)/(kg/kmol) = kmol/h；/(kmol/(m3·h)·m2) = m —— //
    rGasKmolH := rGasKgH / rMolWtGas; // 气相摩尔流量 [kmol/h] / gas molar flow
    // Kga 以 atm 为基准，故分母必须乘操作压力；漏乘 P 会把 HTU 高估 P 倍
    // 量纲: (kmol/h) / (kmol/(m3·h·atm) × m2 × atm) = m
    rHtuRaw := rGasKmolH / (rKgaKmolM3h * rAreaM2 * rPressAtm); // HTU [m] / height of transfer unit
    IF ABS(rHtuRaw) > 1.0E15 THEN
        iErrCode := 5; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    IF rHtuRaw < 0.0 THEN
        rHtuM := 0.0; // 负流量防御 / negative flow guard
    ELSE
        rHtuM := rHtuRaw;
    END_IF;
    // —— 段 4：塔高 = HTU × NTU × 余量（量纲 m×-×- = m） —— //
    rHeightM := rHtuM * rNtu * rHeightMargin; // 填料层高度 [m] / packed height
    bValid := TRUE;
    FC_DL_PackedBedHtu := TRUE;
END_FUNCTION
