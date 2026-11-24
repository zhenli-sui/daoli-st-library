(*==============================================================================
 * 组件名称 (Component)  : FC_DL_HumidAirEnthalpy
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 函数（FUNCTION）· 湿空气热力学算法 · Level 1 算法层
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library（EXP / ABS /
 *                         MIN / MAX），零厂商方言
 * 功能描述 (Function)   : 湿空气比焓 clean-room 计算。公式链：饱和蒸汽压
 *                         p_ws 用 Magnus-Tetens（Stull 参数化，与本库
 *                         FC_DL_DewPointCalc 同系数口径 a=17.625、b=243.04，
 *                         常量复用防两套公式口径漂移）；含湿量
 *                         W = 0.622·phi·p_ws / (p - phi·p_ws)；比焓
 *                         h = 1.006·T + W·(2501 + 1.86·T)。现场用途：洁净
 *                         室/干燥房表冷器与再热功率预算、焓差控制（新风
 *                         焓 < 室内焓 才引入新风）、能耗对比。
 * 出口契约 (Exit)       : 函数返回值 = 湿空气比焓（对应规格引脚表 fEnthalpy
 *                         OUT 列），uErrorId 为 VAR_OUTPUT。异常路径返回
 *                         确定值 0.0，绝不返回未初始化值。
 * 开源溯源 (Origin)     : oscat-building / psychrolib。行为定义对标 OSCAT
 *                         Building 的 AIR_ENTHALPY（0~100 摄氏度域）与
 *                         PsychroLib GetMoistAirEnthalpy 的公开物理公式链；
 *                         公开物理公式无版权义务，不读取、不复制任何源码行，
 *                         100% clean-room 重写并按本库防御规范加严。
 * 属主转移 (R23 裁定)   : Magnus-Tetens 常数（a=17.625、b=243.04）唯一属主
 *                         自 R23 起为 FC_DL_VaporPressureSat；本件内联
 *                         DL_AIR_A / DL_AIR_B 为属主口径的历史引用，本版
 *                         仅声明、逻辑零改动，口径变更以属主件为单一事实源。
 * 规格偏离留档 (R11)    : 规格引脚表 uErrorId 原标注 0001_0203；按第 0 节
 *                         公约 0.7（优先级高于逐组件条款）沿用所在子库
 *                         DL_Algo 既有故障码段 16#0002_xxxx，细分 17xx
 *                         （15xx 露点 / 16xx 流量已占用，顺延无冲突）。
 * 验收向量 (Acceptance) :
 *   V1 T=25.0 RH=60.0 p=101.325：h 约 55.39 kJ/kg 干空气（容差 0.5）；
 *   V2 T=0.0 RH=100.0：h 约 9.44 kJ/kg 干空气（容差 0.5），uErrorId=0；
 *   V3 T=40.0 RH=1.0：干空气端下界，h 约 41.41（容差 0.5）；
 *   V4 RH=0.0：钳位至 1.0，uErrorId=16#0002_1701，照算不发散；
 *   V5 T=150.0：钳位至 100.0，uErrorId=16#0002_1701；
 *   V6 fAtmPress=200.0：钳位至 110.0，uErrorId=16#0002_1702；
 *   V7 T=100.0 RH=100.0：饱和退化分母保护，uErrorId=16#0002_1703，
 *      返回有限确定值；
 *   V8 NaN 输入：拒绝并返回 0.0，uErrorId=16#0002_0004（DL_Algo 公共码）。
 * 故障码表 (Error codes):
 *   16#0002_1701【信息级】温度/湿度越界已钳位照算 / 16#0002_1702【信息级】
 *   大气压越界已钳位照算 / 16#0002_1703【信息级】饱和退化分母已保护 /
 *   16#0002_0004【信息级】输入非有限值已拒绝。全部信息级，本函数无
 *   bError 引脚，故障分级判读经 uErrorId。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 05 · OSCAT Building 开组 · DL_Algo 补强）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   fHSupply := FC_DL_HumidAirEnthalpy(fTempC := stAHU.fSupplyT,
 *                                      fRelHum := stAHU.fSupplyRh,
 *                                      uErrorId => uHErr);
 *   fHOutdoor := FC_DL_HumidAirEnthalpy(fTempC := stMet.fTemp,
 *                                       fRelHum := stMet.fRh,
 *                                       fAtmPress := 100.8);
 *   焓差控制联锁：IF (fHOutdoor < fHReturn - 2.0) THEN bFreshAirOk := TRUE;
 *   仅当 uErrorId = 0 时焓值才可用于联锁判断；钳位拍（1701/1702/1703）
 *   的结果按趋势参考处理。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 输入必须是干球温度 + 相对湿度百分数；给成湿球温度或绝对湿度会得到
 *     荒谬结果。露点请先经 FC_DL_DewPointCalc 反算而不是反复试凑本函数。
 *   2 高原/密闭厂房务必传真实大气压 fAtmPress：海拔 2000m 处大气压约
 *     79.5 kPa 已低于钳位下限 80，含湿量 W 会系统性偏小，影响表冷选型。
 *   3 返回值为「每公斤干空气」比焓，做能量平衡时风量要乘干空气密度换算，
 *     勿直接乘湿空气总流量。
 *   4 100 摄氏度/100% 附近 W 发散是物理事实（水的沸点），本函数以 1 Pa
 *     分母下限保护输出有限值，但该域结果无工程意义，勿用于工艺联锁。
 *   5 纯计算无状态，可放心放入高速任务；输入应来自滤波后的温湿度信号。
 *----------------------------------------------------------------------------*)
FUNCTION FC_DL_HumidAirEnthalpy : REAL
VAR_INPUT
    fTempC    : REAL;                    // 干球温度 [摄氏度]，有效域 0.0..100.0 / Dry-bulb temperature [degC], valid range 0.0..100.0
    fRelHum   : REAL;                    // 相对湿度 [百分数]，有效域 1.0..100.0 / Relative humidity [percent], valid range 1.0..100.0
    fAtmPress : REAL := 101.325;         // 大气压 [kPa]，默认标准大气，有效域 80.0..110.0 / Atmospheric pressure [kPa], default standard atmosphere
END_VAR
VAR_OUTPUT
    uErrorId  : UDINT;                   // 故障码，16#0002_0000 = 无故障 / Error code, 16#0002_0000 = no error
END_VAR
VAR
    fTEff     : REAL;                    // 钳位后的生效温度 [摄氏度] / Effective clamped temperature [degC]
    fRhEff    : REAL;                    // 钳位后的生效湿度 [百分数] / Effective clamped humidity [percent]
    fPEff     : REAL;                    // 钳位后的生效大气压 [kPa] / Effective clamped atmospheric pressure [kPa]
    fPws      : REAL;                    // 饱和蒸汽压 [Pa] / Saturation vapor pressure [Pa]
    fPhi      : REAL;                    // 相对湿度份额 [1] / Relative humidity fraction [1]
    fPAbs     : REAL;                    // 绝对大气压 [Pa] / Absolute atmospheric pressure [Pa]
    fPv       : REAL;                    // 水汽分压 [Pa] / Water vapor partial pressure [Pa]
    fDenom    : REAL;                    // 含湿量分母 [Pa] / Humidity ratio denominator [Pa]
    fHumRatio : REAL;                    // 含湿量 [kg 水汽/kg 干空气] / Humidity ratio [kg vapor per kg dry air]
END_VAR
VAR CONSTANT
    DL_AIR_A       : REAL := 17.625;     // Magnus 系数 a [1]，与 FC_DL_DewPointCalc 同口径 / Magnus coefficient a [1], same as dew point FC
    DL_AIR_B       : REAL := 243.04;     // Magnus 系数 b [摄氏度] / Magnus coefficient b [degC]
    DL_AIR_E0      : REAL := 611.2;      // 0 摄氏度饱和水汽压 [Pa] / Saturation vapor pressure at 0 degC [Pa]
    DL_AIR_T_MIN   : REAL := 0.0;        // 温度有效域下限 [摄氏度] / Temperature valid range low [degC]
    DL_AIR_T_MAX   : REAL := 100.0;      // 温度有效域上限 [摄氏度] / Temperature valid range high [degC]
    DL_AIR_RH_MIN  : REAL := 1.0;        // 湿度钳位下限 [百分数]，防 W 比值超线性 / Humidity clamp floor [percent]
    DL_AIR_P_MIN   : REAL := 80.0;       // 大气压钳位下限 [kPa] / Pressure clamp floor [kPa]
    DL_AIR_P_MAX   : REAL := 110.0;      // 大气压钳位上限 [kPa] / Pressure clamp ceiling [kPa]
    DL_AIR_MW      : REAL := 0.622;      // 干空气/水汽摩尔比 [kg/kg] / Molar mass ratio dry air to vapor [kg/kg]
    DL_AIR_CP_DRY  : REAL := 1.006;      // 干空气比热 [kJ/(kg·K)] / Dry air specific heat [kJ/(kg*K)]
    DL_AIR_HFG0    : REAL := 2501.0;     // 0 摄氏度水汽化潜热 [kJ/kg] / Latent heat of vaporization at 0 degC [kJ/kg]
    DL_AIR_CP_VAP  : REAL := 1.86;       // 水汽比热 [kJ/(kg·K)] / Vapor specific heat [kJ/(kg*K)]
    DL_AIR_DENOM_MIN : REAL := 1.0;      // 含湿量分母保护下限 [Pa] / Humidity ratio denominator floor [Pa]
    DL_AIR_EPS     : REAL := 1.0E-6;     // 浮点判零容差 / Float zero tolerance
    DL_AIR_INF_MAX : REAL := 1.0E30;     // 有限值判定幅值上限 / Magnitude bound for finite-value check
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值（IEC 61131-3 强制）：入口即赋确定值，任何提前 RETURN
 *      前输出已确定；异常路径返回 0.0（确定值口径）
 *      Exit defaults (mandatory): outputs assigned deterministically on entry
 *-----------------------------------------------------------------------------*)
FC_DL_HumidAirEnthalpy := 0.0;                    // 返回值（比焓）默认置零 / Return value (enthalpy) preset to zero
uErrorId := 16#0002_0000;                         // 故障码先清零 / Error code cleared first
fTEff := DL_AIR_T_MIN;                            // 温度预置域下限 / Temperature preset to domain floor
fRhEff := DL_AIR_RH_MIN;                          // 湿度预置钳位下限 / Humidity preset to clamp floor
fPEff := 101.325;                                 // 大气压预置标准值 [kPa] / Pressure preset to standard value [kPa]

(*------------------------------------------------------------------------------
 * 段 2｜非有限值防御（公约 0.8）：全部 REAL 输入（含看似常量的大气压）
 *      先做 fX <> fX 检测再比较；命中即拒绝并返回确定值
 *      Non-finite defense: all REAL inputs checked before any comparison
 *-----------------------------------------------------------------------------*)
IF (fTempC <> fTempC) OR (ABS(fTempC) > DL_AIR_INF_MAX)
   OR (fRelHum <> fRelHum) OR (ABS(fRelHum) > DL_AIR_INF_MAX)
   OR (fAtmPress <> fAtmPress) OR (ABS(fAtmPress) > DL_AIR_INF_MAX) THEN
    uErrorId := 16#0002_0004;                     // 输入非有限值已拒绝（DL_Algo 公共码）/ Non-finite input rejected
    FC_DL_HumidAirEnthalpy := 0.0;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜温度钳位 [0, 100]：越界信息级码，钳位后照算（R21：不构成故障）
 *      Temperature clamping into [0, 100], info-level code, compute on
 *-----------------------------------------------------------------------------*)
IF (fTempC < DL_AIR_T_MIN) OR (fTempC > DL_AIR_T_MAX) THEN
    fTEff := MIN(MAX(fTempC, DL_AIR_T_MIN), DL_AIR_T_MAX);  // 双侧钳位到有效域 / Two-sided clamp into valid range
    uErrorId := 16#0002_1701;                     // 温度越界已钳位 / Temperature out of range clamped
ELSE
    fTEff := fTempC;                              // 合法温度原值生效 / Valid temperature applied as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜湿度钳位 [1, 100]（公约 0.3 限幅域一致）：下限防 W 发散，上限防
 *      超饱和非物理输入；量纲注释 [百分数] 与限幅域一致（R20）
 *      Humidity clamping into [1, 100], floor guards W divergence
 *-----------------------------------------------------------------------------*)
IF (fRelHum < DL_AIR_RH_MIN) OR (fRelHum > 100.0) THEN
    fRhEff := MIN(MAX(fRelHum, DL_AIR_RH_MIN), 100.0);      // 双侧钳位 / Two-sided clamp
    uErrorId := 16#0002_1701;                     // 湿度越界已钳位 / Humidity out of range clamped
ELSE
    fRhEff := fRelHum;                            // 合法湿度原值生效 / Valid humidity applied as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜大气压钳位 [80, 110] kPa：覆盖海平面 ~ 海拔 2000m 工况域
 *      Atmospheric pressure clamping into [80, 110] kPa
 *-----------------------------------------------------------------------------*)
IF (fAtmPress < DL_AIR_P_MIN) OR (fAtmPress > DL_AIR_P_MAX) THEN
    fPEff := MIN(MAX(fAtmPress, DL_AIR_P_MIN), DL_AIR_P_MAX);  // 双侧钳位 / Two-sided clamp
    uErrorId := 16#0002_1702;                     // 大气压越界已钳位 / Pressure out of range clamped
ELSE
    fPEff := fAtmPress;                           // 合法大气压原值生效 / Valid pressure applied as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜Magnus-Tetens 饱和蒸汽压：与 FC_DL_DewPointCalc 同系数口径，
 *      常量复用防两套公式口径漂移（热平衡算得平）
 *      Magnus-Tetens saturation vapor pressure, same coefficients as dew
 *      point FC, shared constants prevent formula drift
 *-----------------------------------------------------------------------------*)
fPws := DL_AIR_E0 * EXP(DL_AIR_A * fTEff / (DL_AIR_B + fTEff));  // 饱和蒸汽压 [Pa] / Saturation vapor pressure [Pa]

(*------------------------------------------------------------------------------
 * 段 7｜含湿量 W = 0.622·phi·p_ws / (p - phi·p_ws)：分母防除零/防退化
 *      Humidity ratio with denominator guard (divide-by-zero protected)
 *-----------------------------------------------------------------------------*)
fPhi := fRhEff / 100.0;                           // 相对湿度份额 [1] / RH fraction [1]
fPAbs := fPEff * 1000.0;                          // 大气压 kPa → Pa / Pressure kPa converted to Pa
fPv := fPhi * fPws;                               // 水汽分压 [Pa] / Vapor partial pressure [Pa]
fDenom := fPAbs - fPv;                            // 含湿量分母 [Pa] / Denominator [Pa]
IF fPAbs <= DL_AIR_EPS THEN
    uErrorId := 16#0002_1702;                     // 绝对压力退化按大气压类信息级处理 / Degenerate pressure, info code
    FC_DL_HumidAirEnthalpy := 0.0;
    RETURN;
END_IF
IF fDenom <= DL_AIR_DENOM_MIN THEN
    fPv := fPAbs - DL_AIR_DENOM_MIN;              // 饱和退化保护：水汽分压钳至分母下限之上 / Saturation degenerate guard
    uErrorId := 16#0002_1703;                     // 分母退化已保护（100 度/100% 物理发散域） / Degenerate denominator protected
END_IF
fHumRatio := DL_AIR_MW * fPv / (fPAbs - fPv);     // 含湿量 [kg 水汽/kg 干空气] / Humidity ratio [kg/kg dry air]
                                                  // 分母 = fPAbs - fPv ≥ DL_AIR_DENOM_MIN，防除零成立
(*------------------------------------------------------------------------------
 * 段 8｜比焓 h = 1.006·T + W·(2501 + 1.86·T)：显热 + 水汽潜热项
 *      Specific enthalpy: sensible dry-air term plus vapor latent term
 *-----------------------------------------------------------------------------*)
FC_DL_HumidAirEnthalpy := DL_AIR_CP_DRY * fTEff + fHumRatio * (DL_AIR_HFG0 + DL_AIR_CP_VAP * fTEff);
                                                  // 湿空气比焓 [kJ/kg 干空气] / Moist air specific enthalpy [kJ/kg dry air]
END_FUNCTION
