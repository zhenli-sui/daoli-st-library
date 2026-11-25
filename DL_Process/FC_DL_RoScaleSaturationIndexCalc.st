(*
  Name: FC_DL_RoScaleSaturationIndexCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 RO/NF 膜法水处理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 朗格利尔饱和指数按经典四因子式解算：LSI = pH − pHs，
           其中 pHs = (9.3 + A + B) − (C + D)：
             A = (LOG10(TDS) − 1) / 10，表征溶解固体的离子强度；
             B = −13.12 · LOG10(T_K) + 34.55，温度项（T_K 为开尔文，必须做 °C→K 偏移）；
             C = LOG10(Ca 硬度) − 0.4，钙硬度项；
             D = LOG10(碱度)，碱度项。
        2) LOG10 用跨平台安全写法 LN(x) / LN(10) 实现，不依赖厂商私有 LOG10 扩展。
        3) 输出结垢风险等级整数 iRiskLvl：0 = 不结垢（偏腐蚀），1 = 轻度结垢，
           2 = 中度结垢，3 = 严重结垢；等级由 LSI 阈值判定，供加药/阻垢剂投加策略直接取用。
  边界条件：1) 非有限值闸：五路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（fLsi 强制 0.0、iRiskLvl 置 0）并置无效（R19）。
        2) 对数自变量零闸：TDS / 钙硬度 / 碱度三项都必须 ABS(x) > DL_EPS 才可进 LN，
           否则 LOG10 发散；任一项不满足判无效。
        3) 对数自变量负值闸：三量均为浓度，负值属变送器故障，判无效且不取 ABS 掩盖。
        4) 量程钳制：TDS 钳 0..60000 mg/L、钙硬度与碱度钳 0..DL_HARD_MAX(2000 mg/L)、
           pH 钳 0..14、温度钳 0..90 °C；越域钳边界值参与计算但置无效。
        5) LSI 结果饱和钳到 −5.0 ~ +5.0 的工程可观测域，防极端输入把指数推到无意义量级。
        6) 无回差环节：纯函数无状态，等级切换的迟滞由下游报警件承担。
  量纲自证：A = (LOG10(mg/L) − 1) / 10 → 无因次 [-]，LOG10 的自变量已按 mg/L 归一；
           B = −13.12 · LOG10(K) + 34.55 → 无因次 [-]，34.55 为经验截距，无单位；
           C、D 同 A 均为无因次；LSI = pH(−) − pHs(−) = 无因次指数 [-]，四项量纲一致。
*)

FUNCTION FC_DL_RoScaleSaturationIndexCalc : BOOL
VAR_INPUT
    fPh              : REAL;   // 给水 pH 值 [pH 单位] / Feed water pH [pH unit]
    fTempC           : REAL;   // 给水温度 [°C] / Feed water temperature [°C]
    fCaHardnessMgL   : REAL;   // 钙硬度（以 CaCO3 计）[mg/L] / Calcium hardness as CaCO3 [mg/L]
    fAlkalinityMgL   : REAL;   // 总碱度（以 CaCO3 计）[mg/L] / Total alkalinity as CaCO3 [mg/L]
    fTdsMgL          : REAL;   // 总溶解固体 [mg/L] / Total dissolved solids [mg/L]
END_VAR
VAR_OUTPUT
    fLsi             : REAL;   // 朗格利尔饱和指数 [-] / Langelier saturation index [-]
    iRiskLvl         : INT;    // 结垢风险等级 0..3 [-] / Scaling risk level 0..3 [-]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fPhClamp        : REAL;   // 钳制后的 pH [-] / Clamped pH [-]
    _fTClampC        : REAL;   // 钳制后的温度 [°C] / Clamped temperature [°C]
    _fCaClampMgL     : REAL;   // 钳制后的钙硬度 [mg/L] / Clamped calcium hardness [mg/L]
    _fAlkClampMgL    : REAL;   // 钳制后的碱度 [mg/L] / Clamped alkalinity [mg/L]
    _fTdsClampMgL    : REAL;   // 钳制后的 TDS [mg/L] / Clamped TDS [mg/L]
    _fTermA          : REAL;   // A 项（TDS 项）[-] / Term A, TDS term [-]
    _fTermB          : REAL;   // B 项（温度项）[-] / Term B, temperature term [-]
    _fTermC          : REAL;   // C 项（钙硬度项）[-] / Term C, calcium hardness term [-]
    _fTermD          : REAL;   // D 项（碱度项）[-] / Term D, alkalinity term [-]
    _fPhs            : REAL;   // 饱和 pH [-] / Saturation pH [-]
    _fLsiRaw         : REAL;   // 未饱和的原始 LSI [-] / Raw LSI before limiting [-]
    _bLogOk          : BOOL;   // 对数自变量合法性聚合 [-] / Logarithm argument validity aggregate
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 对数自变量零闸阈值 [-] / Logarithm argument zero gate [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_K0            : REAL := 273.15;    // 摄氏转开尔文偏移 [K] / Celsius to Kelvin offset [K]
    DL_LN10          : REAL := 2.302585093;   // LN(10)，用于实现 LOG10 [-] / LN(10) for LOG10 [-]
    DL_PH_MAX        : REAL := 14.0;      // pH 量程上限 [-] / pH range high [-]
    DL_T_HI_C        : REAL := 90.0;      // 温度量程上限 [°C] / Temperature range high [°C]
    DL_HARD_MAX      : REAL := 2000.0;    // 钙硬度/碱度量程上限 [mg/L] / Hardness range high [mg/L]
    DL_TDS_MAX       : REAL := 60000.0;   // TDS 量程上限 [mg/L] / TDS range high [mg/L]
    DL_LSI_LO        : REAL := -5.0;      // LSI 工程可观测下限 [-] / LSI observable low [-]
    DL_LSI_HI        : REAL := 5.0;       // LSI 工程可观测上限 [-] / LSI observable high [-]
    DL_LSI_L1        : REAL := 0.0;       // 等级 0/1 分界 [-] / Risk level 0-to-1 boundary [-]
    DL_LSI_L2        : REAL := 0.5;       // 等级 1/2 分界 [-] / Risk level 1-to-2 boundary [-]
    DL_LSI_L3        : REAL := 1.5;       // 等级 2/3 分界 [-] / Risk level 2-to-3 boundary [-]
END_VAR

(* —— 段 1：非有限值闸（R19：五路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fPh > -DL_BIG AND fPh < DL_BIG)
   OR NOT (fTempC > -DL_BIG AND fTempC < DL_BIG)
   OR NOT (fCaHardnessMgL > -DL_BIG AND fCaHardnessMgL < DL_BIG)
   OR NOT (fAlkalinityMgL > -DL_BIG AND fAlkalinityMgL < DL_BIG)
   OR NOT (fTdsMgL > -DL_BIG AND fTdsMgL < DL_BIG) THEN
    fLsi := 0.0;                            // 输出强制 0.0 / Output forced to zero
    iRiskLvl := 0;                          // 等级置 0（不结垢），不给误导性等级 / Risk level cleared
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_RoScaleSaturationIndexCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：对数自变量零闸 + 负值闸（R4：LN 的自变量必须先验正） —— *)
_bLogOk := (fTdsMgL > DL_EPS) AND (fCaHardnessMgL > DL_EPS) AND (fAlkalinityMgL > DL_EPS);
IF NOT _bLogOk THEN
    fLsi := 0.0;                            // 输出强制 0.0 / Output forced to zero
    iRiskLvl := 0;                          // 等级置 0 / Risk level cleared
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_RoScaleSaturationIndexCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：量程钳制（边界值参与计算，越域在段 5 判无效） —— *)
_fPhClamp := LIMIT(0.0, fPh, DL_PH_MAX);                  // pH 钳 0..14 [-]
_fTClampC := LIMIT(0.0, fTempC, DL_T_HI_C);               // 温度钳 0..90 [°C]
_fCaClampMgL := LIMIT(0.0, fCaHardnessMgL, DL_HARD_MAX);  // 钙硬度钳 [mg/L]
_fAlkClampMgL := LIMIT(0.0, fAlkalinityMgL, DL_HARD_MAX); // 碱度钳 [mg/L]
_fTdsClampMgL := LIMIT(0.0, fTdsMgL, DL_TDS_MAX);         // TDS 钳 [mg/L]

(* —— 段 4：四因子解算（LOG10 以 LN(x)/LN(10) 跨平台实现） —— *)
_fTermA := (LN(_fTdsClampMgL) / DL_LN10 - 1.0) / 10.0;                          // A 项 [-]
_fTermB := -13.12 * (LN(_fTClampC + DL_K0) / DL_LN10) + 34.55;                  // B 项 [-]
_fTermC := LN(_fCaClampMgL) / DL_LN10 - 0.4;                                    // C 项 [-]
_fTermD := LN(_fAlkClampMgL) / DL_LN10;                                         // D 项 [-]
_fPhs := (9.3 + _fTermA + _fTermB) - (_fTermC + _fTermD);                       // 饱和 pH [-]
_fLsiRaw := _fPhClamp - _fPhs;                                                  // LSI = pH − pHs [-]

(* —— 段 5：有效位单点聚合（量程校验，钳制值已参与计算） —— *)
xValid := (fPh >= 0.0) AND (fPh <= DL_PH_MAX)                                   // pH 在量程内
          AND (fTempC >= 0.0) AND (fTempC <= DL_T_HI_C)                         // 温度在量程内
          AND (fCaHardnessMgL <= DL_HARD_MAX)                                   // 钙硬度不越上限
          AND (fAlkalinityMgL <= DL_HARD_MAX)                                   // 碱度不越上限
          AND (fTdsMgL <= DL_TDS_MAX);                                          // TDS 不越上限

(* —— 段 6：风险等级分级（IF/ELSIF 单链，iRiskLvl 只在此处赋值一次） —— *)
IF _fLsiRaw < DL_LSI_L1 THEN
    iRiskLvl := 0;                          // 不结垢（偏腐蚀倾向）/ Non-scaling, corrosive tendency
ELSIF _fLsiRaw < DL_LSI_L2 THEN
    iRiskLvl := 1;                          // 轻度结垢 / Slight scaling tendency
ELSIF _fLsiRaw < DL_LSI_L3 THEN
    iRiskLvl := 2;                          // 中度结垢 / Moderate scaling tendency
ELSE
    iRiskLvl := 3;                          // 严重结垢 / Severe scaling tendency
END_IF

(* —— 段 7：输出单点写盘（LSI 饱和钳到工程可观测域） —— *)
fLsi := LIMIT(DL_LSI_LO, _fLsiRaw, DL_LSI_HI);   // LSI 钳 −5..+5 [-]
FC_DL_RoScaleSaturationIndexCalc := xValid;      // 返回码：TRUE = 计算可信

END_FUNCTION
