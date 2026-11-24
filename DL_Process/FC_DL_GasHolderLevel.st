(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_GasHolderLevel
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 湿式气柜储气量标态折算与可释放能量估算
  口径声明: 能量按厂内标定简化系数 0.55 kWh/(m3·单位甲烷份额)×CH4 假设 0.6 计，
            非热力学严格值（严格口径为 9.94 kWh/m3 纯甲烷），仅供储量看板同比使用
*)
FUNCTION FC_DL_GasHolderLevel : BOOL
VAR_INPUT
    rPressKpa : REAL; // 柜内表压 [kPa] / gauge pressure in the holder
    rTempC : REAL; // 柜内气体温度 [°C] / gas temperature
    rVolM3 : REAL; // 气柜几何容积 [m3] / geometric holder volume
    rLevelPct : REAL; // 有效储气液位/行程 [%] / effective storage level
END_VAR
VAR_OUTPUT
    rNormM3 : REAL; // 标态储气量 [Nm3] / normalised stored volume
    rEnergyKwh : REAL; // 可释放能量估算 [kWh] / estimated releasable energy
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=温度超域 2=容积非法 3=压力非法 4=结果非有限 / event code
END_VAR
VAR CONSTANT
    rKelvinOff : REAL := 273.15; // 开尔文偏移 [K] / kelvin offset
    rPressRefKpa : REAL := 101.325; // 标准大气压 [kPa] / standard atmospheric pressure
    rTempMinC : REAL := -50.0; // 温度域下限 [°C] / temperature lower bound
    rPctToFrac : REAL := 0.01; // 百分数转小数系数 [-]/[%] / percent to fraction factor
    rKwhPerM3 : REAL := 0.55; // 能量简化系数 [kWh/m3] / simplified energy coefficient
    rCh4Assumed : REAL := 0.6; // 甲烷份额假设 [-] / assumed methane fraction
END_VAR
VAR
    rTempK : REAL; // 柜内绝对温度 [K] / absolute temperature
    rVolUseM3 : REAL; // 有效储气体积 [m3] / effective stored volume
    rNormRaw : REAL; // 未校验标态量 [Nm3] / unchecked normalised volume
END_VAR

    // —— 段 0：全路径预清 —— //
    rTempK := 0.0;
    rVolUseM3 := 0.0;
    rNormRaw := 0.0;
    rNormM3 := 0.0;
    rEnergyKwh := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_GasHolderLevel := FALSE;
    // —— 段 1：温度域闸（同时保护标态折算分母 273.15+T） —— //
    IF rTempC <= rTempMinC THEN
        iErrCode := 1; // 温度超域，标态折算无意义 / temperature out of domain
        RETURN;
    END_IF;
    IF rVolM3 <= 0.0 THEN
        iErrCode := 2; // 容积非法 / invalid holder volume
        RETURN;
    END_IF;
    // —— 段 2：压力域闸（表压需为正，绝对压 = 表压 + 大气压） —— //
    IF rPressKpa <= 0.0 THEN
        iErrCode := 3; // 压力非法，绝对压不可信 / invalid gauge pressure
        RETURN;
    END_IF;
    // —— 段 3：有效储气体积按液位折算，再作标态换算（量纲 m3×kPa/K÷kPa = Nm3） —— //
    rVolUseM3 := rVolM3 * rLevelPct * rPctToFrac; // 有效体积 [m3] / effective volume
    IF rVolUseM3 < 0.0 THEN
        rVolUseM3 := 0.0; // 负液位防御 / negative level guard
    END_IF;
    rTempK := rKelvinOff + rTempC; // 绝对温度 [K] / absolute temperature
    rNormRaw := rVolUseM3 * (rPressRefKpa + rPressKpa) * rKelvinOff / (rTempK * rPressRefKpa); // 标态量 [Nm3]
    IF ABS(rNormRaw) > 1.0E15 THEN
        iErrCode := 4; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    rNormM3 := rNormRaw;
    // —— 段 4：能量估算（量纲 Nm3 × kWh/m3 × - = kWh） —— //
    rEnergyKwh := rNormM3 * rKwhPerM3 * rCh4Assumed; // 能量估算 [kWh] / estimated energy
    bValid := TRUE;
    FC_DL_GasHolderLevel := TRUE;
END_FUNCTION
