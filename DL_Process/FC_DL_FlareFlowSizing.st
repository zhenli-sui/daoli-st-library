(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_FlareFlowSizing
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 火炬放空管径 sizing：标态最大气量折算工况实际体积流量后按设计流速反算管径
  设计口径: 管径按「流速限值的 70%」设计（HF 设计余量），实际流速 rVelMs 用于监看是否超限
*)
FUNCTION FC_DL_FlareFlowSizing : BOOL
VAR_INPUT
    rMaxGasM3h : REAL; // 标态最大放空气量 [Nm3/h] / maximum normal-condition gas flow
    rPressBar : REAL; // 放空管绝对压力 [bar] / absolute pressure in the flare header
    rTempC : REAL; // 放空气温度 [°C] / gas temperature
    rVelLimitMs : REAL; // 允许流速上限 [m/s] / allowable velocity limit
END_VAR
VAR_OUTPUT
    rDiaM : REAL; // 建议管内径 [m] / recommended internal diameter
    rVelMs : REAL; // 按建议管径核算的实际流速 [m/s] / actual velocity for the recommended diameter
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    bOver : BOOL; // 流速越限标志 [-] / velocity over-limit flag
    iErrCode : INT; // 事件码 0=正常 1=流速上限非法 2=压力非法 3=温度超域 4=结果非有限 / event code
END_VAR
VAR CONSTANT
    rPi : REAL := 3.14159265358979; // 圆周率 [-] / pi
    rPressRefBar : REAL := 1.01325; // 标准大气压 [bar] / standard atmospheric pressure
    rKelvinOff : REAL := 273.15; // 开尔文偏移 [K] / kelvin offset
    rSecPerHour : REAL := 3600.0; // 每小时秒数 [s/h] / seconds per hour
    rTempMinC : REAL := -50.0; // 温度域下限 [°C] / temperature lower bound
    rDesignFrac : REAL := 0.7; // 设计流速占限值比例 [-] / design velocity fraction of the limit
END_VAR
VAR
    DL_FLARE_DIA_MIN : REAL := 0.08; // 工程最小放空管径 [m] / minimum practical flare diameter
    rVelDesign : REAL; // 设计流速 [m/s] / design velocity
    rQActualM3s : REAL; // 工况实际体积流量 [m3/s] / actual volumetric flow
    rAreaM2 : REAL; // 所需流通面积 [m2] / required flow area
    rDiaRaw : REAL; // 未校验管径 [m] / unchecked diameter
END_VAR

    // —— 段 0：全路径预清 —— //
    rVelDesign := 0.0;
    rQActualM3s := 0.0;
    rAreaM2 := 0.0;
    rDiaRaw := 0.0;
    rDiaM := 0.0;
    rVelMs := 0.0;
    bValid := FALSE;
    bOver := FALSE;
    iErrCode := 0;
    FC_DL_FlareFlowSizing := FALSE;
    // —— 段 1：输入域闸（流速上限、压力、温度） —— //
    IF rVelLimitMs <= 0.0 THEN
        iErrCode := 1; // 流速上限非法，管径无定义 / invalid velocity limit
        RETURN;
    END_IF;
    IF rPressBar <= 0.0 THEN
        iErrCode := 2; // 压力非法，工况折算无意义 / invalid absolute pressure
        RETURN;
    END_IF;
    IF rTempC <= rTempMinC THEN
        iErrCode := 3; // 温度超域，标态折算分母不可信 / temperature out of domain
        RETURN;
    END_IF;
    // —— 段 2：标态→工况折算（量纲 Nm3/h×(bar/bar)×(K/K) = m3/h，再 /3600 得 m3/s） —— //
    rQActualM3s := rMaxGasM3h * (rPressRefBar / rPressBar)
                   * ((rKelvinOff + rTempC) / rKelvinOff) / rSecPerHour; // 工况流量 [m3/s]
    IF rQActualM3s < 0.0 THEN
        rQActualM3s := 0.0; // 负气量防御 / negative flow guard
    END_IF;
    // —— 段 3：按设计流速反算面积与管径（分母闸：设计流速） —— //
    rVelDesign := rVelLimitMs * rDesignFrac; // 设计流速 [m/s] / design velocity
    IF rVelDesign <= 1.0E-9 THEN
        iErrCode := 1; // 设计流速退化 / degenerate design velocity
        RETURN;
    END_IF;
    rAreaM2 := rQActualM3s / rVelDesign; // 流通面积 [m2] / required area
    IF rAreaM2 < 0.0 THEN
        iErrCode := 4; // 面积不可能为负 / area cannot be negative
        RETURN;
    END_IF;
    rDiaRaw := SQRT(4.0 * rAreaM2 / rPi); // 管径 [m] / diameter
    IF ABS(rDiaRaw) > 1.0E15 THEN
        iErrCode := 4; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    rDiaM := rDiaRaw;
    // —— 段 4：按管径回算实际流速并做越限监看 —— //
    IF rDiaM > 1.0E-9 THEN
        rVelMs := rQActualM3s / (rPi * rDiaM * rDiaM / 4.0); // 实际流速 [m/s] / actual velocity
    ELSE
        rVelMs := 0.0; // 退化管径 / degenerate diameter
    END_IF;
    // 管径由限速反算，回算流速恒等于限速，故 bOver 必须改判「所需管径小于工程最小管径」
    bOver := rDiaRaw < DL_FLARE_DIA_MIN; // 需更小管径才满足限速，即实际将超速 / needs smaller dia, will over-speed
    bValid := TRUE;
    FC_DL_FlareFlowSizing := TRUE;
END_FUNCTION
