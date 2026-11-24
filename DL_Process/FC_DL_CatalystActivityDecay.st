(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_CatalystActivityDecay
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 催化剂活性一阶衰减模型：活性、温度加速失活因子与剩余可用寿命 RUL
  模型: k = k0·EXP(Kt·(T-Tref))；act = EXP(-k·t)；RUL = (k·t + LN(1/0.7))/k
*)
FUNCTION FC_DL_CatalystActivityDecay : BOOL
VAR_INPUT
    rDeactBase : REAL; // 基准温度下失活速率常数 [1/h] / base deactivation rate constant
    rHoursRun : REAL; // 累计运行小时数 [h] / accumulated operating hours
    rTempC : REAL; // 实际运行温度 [°C] / actual operating temperature
    rTempRefC : REAL; // 基准温度 [°C] / reference temperature
    rKt : REAL; // 温度加速系数 [1/°C] / temperature acceleration coefficient
END_VAR
VAR_OUTPUT
    rActivity : REAL; // 相对活性 [-]，1.0 = 全新 / relative activity, 1.0 is fresh
    rRulHours : REAL; // 活性降至 0.7 的剩余小时数 [h] / remaining useful life to 70 percent activity
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=基准失活率非法 2=失活率近零无退化 3=运行小时为负 4=温度低于绝对零度 5=结果非有限 / event code
END_VAR
VAR CONSTANT
    rLnInv07 : REAL := 0.356674944; // LN(1/0.7) 寿命终点常数 [-] / LN of one over 0.7
    rActFloor : REAL := 0.0001; // 活性下限 [-]，防 LN(0) / activity floor preventing LN of zero
    rActCeil : REAL := 1.0; // 活性上限 [-]，不得高于全新 / activity ceiling, never above fresh
    rExpHi : REAL := 50.0; // EXP 指数量程上限 [-]，防溢出 / exponent ceiling guarding EXP overflow
    rExpLo : REAL := -50.0; // EXP 指数量程下限 [-] / exponent floor
    rKelvinOff : REAL := 273.15; // 开尔文偏移 [K] / kelvin offset
END_VAR
VAR
    rExpo : REAL; // 温度加速指数 [-] / temperature exponent
    rK : REAL; // 实际失活速率常数 [1/h] / effective deactivation rate constant
    rAct : REAL; // 未限幅活性 [-] / unlimited activity
    rRulRaw : REAL; // 未限幅剩余寿命 [h] / unlimited remaining life
END_VAR

    // —— 段 0：全路径预清 —— //
    rExpo := 0.0;
    rK := 0.0;
    rAct := 0.0;
    rRulRaw := 0.0;
    rActivity := rActFloor;
    rRulHours := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_CatalystActivityDecay := FALSE;
    // —— 段 1：输入域闸 —— //
    IF rDeactBase <= 0.0 THEN
        iErrCode := 1; // 基准失活率非法，衰减模型无定义 / invalid base rate, model undefined
        RETURN;
    END_IF;
    IF rHoursRun < 0.0 THEN
        iErrCode := 3; // 运行小时为负 / negative operating hours
        RETURN;
    END_IF;
    IF rTempC <= (0.0 - rKelvinOff) THEN
        iErrCode := 4; // 温度低于绝对零度，物理不可能 / temperature below absolute zero
        RETURN;
    END_IF;
    // —— 段 2：温度加速失活常数（指数先做量程钳位，防 EXP 溢出） —— //
    rExpo := rKt * (rTempC - rTempRefC); // 加速指数 [-] / acceleration exponent
    IF rExpo > rExpHi THEN
        rExpo := rExpHi; // 上限钳位 / clamp high
    ELSIF rExpo < rExpLo THEN
        rExpo := rExpLo; // 下限钳位 / clamp low
    END_IF;
    rK := rDeactBase * EXP(rExpo); // 失活速率常数 [1/h] / rate constant
    // —— 段 3：活性 = EXP(-k·t)，并限 [0.0001, 1] —— //
    rAct := EXP(0.0 - rK * rHoursRun); // 活性 [-] / activity
    IF rAct > rActCeil THEN
        rActivity := rActCeil; // 上限钳位 / clamp high
    ELSIF rAct < rActFloor THEN
        rActivity := rActFloor; // 下限钳位，保证后续 LN 有定义 / floor keeps LN defined
    ELSE
        rActivity := rAct;
    END_IF;
    // —— 段 4：RUL（分母闸：k 必须显著为正；LN 前闸：活性为正） —— //
    IF rK <= 1.0E-9 THEN
        rRulHours := 99999.0; // 失活率近零，视为无退化 / near-zero decay, treat as no degradation
        iErrCode := 2; // 信息级：无退化，寿命取哨兵值 / info: no degradation, sentinel life
        bValid := TRUE;
        FC_DL_CatalystActivityDecay := TRUE;
        RETURN;
    END_IF;
    IF rActivity <= 0.0 THEN
        iErrCode := 5; // 活性非正，LN 无定义 / non-positive activity, LN undefined
        RETURN;
    END_IF;
    // 量纲 (-)/(1/h) = h；目标时刻 LN(1/0.7)/k 减去已运行量 LN(1/act)/k
    rRulRaw := (rLnInv07 - LN(1.0 / rActivity)) / rK; // 剩余寿命 [h] / remaining life in hours
    IF ABS(rRulRaw) > 1.0E15 THEN
        rRulHours := 0.0;
        iErrCode := 5; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    IF rRulRaw < 0.0 THEN
        rRulHours := 0.0; // 已过寿命终点 / life already exhausted
    ELSE
        rRulHours := rRulRaw;
    END_IF;
    bValid := TRUE;
    FC_DL_CatalystActivityDecay := TRUE;
END_FUNCTION
