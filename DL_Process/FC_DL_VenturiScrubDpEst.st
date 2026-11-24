(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_VenturiScrubDpEst
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 文丘里洗涤器喉口压降估算（干气流速头 × 液气动量耦合系数）
  简化式声明: ΔP[kPa] = (ρg·v²/2)·(1 + 0.10·(L/Q)[L每m3]) / 1000；
              0.10 为厂商公开资料常用的液气动量耦合经验系数，非热力学严格值
*)
FUNCTION FC_DL_VenturiScrubDpEst : BOOL
VAR_INPUT
    rGasM3h : REAL; // 实际工况烟气量 [m3/h] / actual gas flow
    rThroatDm : REAL; // 喉口直径 [dm] / throat diameter in decimetre
    rLiquidLM3h : REAL; // 喷液量 [L/h] / sprayed liquid flow
    rRhoGas : REAL; // 工况气体密度 [kg/m3] / gas density at working conditions
END_VAR
VAR_OUTPUT
    rDpKpa : REAL; // 喉口压降 [kPa] / throat pressure drop
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=喉口直径非法 2=烟气量非法 3=气体密度非法 4=结果非有限 / event code
END_VAR
VAR CONSTANT
    rPi : REAL := 3.14159265358979; // 圆周率 [-] / pi
    rDmToM : REAL := 0.1; // 分米转米系数 [m/dm] / decimetre to metre factor
    rSecPerHour : REAL := 3600.0; // 每小时秒数 [s/h] / seconds per hour
    rPaToKpa : REAL := 0.001; // 帕转千帕系数 [kPa/Pa] / pascal to kilopascal factor
    rLgCoef : REAL := 0.10; // 液气动量耦合经验系数 [-] / empirical liquid-gas momentum coefficient
    rM3ToL : REAL := 1000.0; // 立方米转升系数 [L/m3] / cubic metre to litre factor
END_VAR
VAR
    rDmM : REAL; // 喉口直径 [m] / throat diameter in metre
    rAreaM2 : REAL; // 喉口截面积 [m2] / throat area
    rVelMs : REAL; // 喉口气速 [m/s] / throat gas velocity
    rLgRatio : REAL; // 液气比 [L/m3] / liquid to gas ratio
    rDpPa : REAL; // 压降 [Pa] / pressure drop in pascal
END_VAR

    // —— 段 0：全路径预清 —— //
    rDmM := 0.0;
    rAreaM2 := 0.0;
    rVelMs := 0.0;
    rLgRatio := 0.0;
    rDpPa := 0.0;
    rDpKpa := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_VenturiScrubDpEst := FALSE;
    // —— 段 1：分母闸（喉口直径、烟气量）与密度域闸 —— //
    IF rThroatDm <= 0.0 THEN
        iErrCode := 1; // 喉口直径非法，截面积无定义 / invalid throat diameter
        RETURN;
    END_IF;
    IF rGasM3h <= 0.0 THEN
        iErrCode := 2; // 烟气量非法，气速无定义 / invalid gas flow, velocity undefined
        RETURN;
    END_IF;
    IF rRhoGas <= 0.0 THEN
        iErrCode := 3; // 气体密度非法 / invalid gas density
        RETURN;
    END_IF;
    // —— 段 2：喉口几何与气速（量纲 (m3/h)/(s/h)/(m2) = m/s） —— //
    rDmM := rThroatDm * rDmToM; // 喉口直径 [m] / throat diameter
    rAreaM2 := rPi * rDmM * rDmM / 4.0; // 喉口面积 [m2] / throat area
    IF rAreaM2 <= 1.0E-9 THEN
        iErrCode := 1; // 面积退化，视为直径非法 / degenerate area, treat as invalid diameter
        RETURN;
    END_IF;
    rVelMs := rGasM3h / rSecPerHour / rAreaM2; // 喉口气速 [m/s] / throat velocity
    rLgRatio := rLiquidLM3h / rGasM3h * rM3ToL; // 液气比 [L/m3] / liquid to gas ratio
    // —— 段 3：压降估算（量纲 (kg/m3)*(m2/s2) = Pa） —— //
    rDpPa := (rRhoGas * rVelMs * rVelMs / 2.0) * (1.0 + rLgCoef * rLgRatio); // 压降 [Pa] / pressure drop
    IF ABS(rDpPa) > 1.0E15 THEN
        iErrCode := 4; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    // —— 段 4：单位换算与负值防御 —— //
    IF rDpPa < 0.0 THEN
        rDpKpa := 0.0; // 负输入防御 / negative input guard
    ELSE
        rDpKpa := rDpPa * rPaToKpa; // 压降 [kPa] / pressure drop in kPa
    END_IF;
    bValid := TRUE;
    FC_DL_VenturiScrubDpEst := TRUE;
END_FUNCTION
