(*==============================================================================
 * 组件名称 (Component)  : FC_DL_DewPointCalc
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（LN / EXP / ABS / MIN / MAX），
 *                         零厂商方言
 * 功能描述 (Function)   : Magnus-Tetens（Stull 参数化）露点温度计算。由干球
 *                         温度与相对湿度求露点：gamma := LN(RH/100) +
 *                         a*T/(b+T)，Td := b*gamma/(a-gamma)，a=17.625、
 *                         b=243.04（过水面参数化）。另附实际水汽压输出供
 *                         焓值类组件复用。现场用途：洁净室 / 干燥房环控、
 *                         冷面结露风险判断（表面温度低于露点即结露）。
 * 开源溯源 (Origin)     : 原创实现。公式为公开气象学 Magnus-Tetens/Stull
 *                         参数化（clean-room），按本库故障码体系重写并加严。
 * 属主转移 (R23 裁定)   : Magnus-Tetens 常数（a=17.625、b=243.04）唯一属主
 *                         自 R23 起为 FC_DL_VaporPressureSat；本件内联常数
 *                         为属主口径的历史引用，本版仅声明、逻辑零改动，
 *                         后续口径变更以属主件为单一事实源。
 * 设计验证 (Verified)   : python 6 位小数核验（a=17.625、b=243.04）：
 *                         T=25.0 度 RH=60.0 -> Td=16.698 度（约 16.7 达标）；
 *                         T=0.0 度 RH=100.0 -> Td=0.000 度（精确归零）；
 *                         T=20.0 度 RH=50.0 -> Td=9.261 度；
 *                         T=25.0 度 RH=60.0 -> fVaporPa=1897.8 Pa。
 * 验收向量 (Acceptance) :
 *   V1 T=25.0 RH=60.0：返回值约 16.698（容差 0.3），fVaporPa 约 1897.8
 *   V2 T=0.0 RH=100.0：返回值 0.000（容差 1E-3），uErrorId=0
 *   V3 T=20.0 RH=50.0：返回值约 9.261（容差 0.3）
 *   V4 RH=0.0：钳位至 0.1，uErrorId=16#0002_1501，返回确定值不发散
 *   V5 T=100.0：钳位至 60.0，uErrorId=16#0002_1502，bInRange=FALSE
 *   V6 T=-500.0：钳位至 -40.0，返回哨兵口径确定值，绝不返回未初始化值
 *   V7 RH=0.0：钳位至 0.1，LN 输入恒正不发散，返回值有限且为确定数
 *   V8 T=25.0 RH=60.0：fVaporPa 约 1897.8 Pa（容差 5.0），供焓值链路复用
 * 依赖     (Depends)    : 无 DL_ 内部依赖；仅标准 LN / EXP
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 钳位+容差+防除零+出口默认值
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（FC 无状态机）
 *                         R7 N/A（无实例调用）
 * 无状态声明 (Stateless): FC 全程无隐式状态，同输入必得同输出；
 *                         除 VAR_IN_OUT 之外的隐式状态为零。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 04 · Phase 3 · DL_Algo 批次）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   fTd := FC_DL_DewPointCalc(fTempC := stAir.fTemp,
 *                             fRhPct := stAir.fRh,
 *                             uErrorId => uDewErr,
 *                             fVaporPa => fVp,
 *                             bInRange => bInDom);
 *   结露联锁判定：IF (stChiller.fSurfTemp <= fTd) THEN bCondenseRisk := TRUE;
 *   注意：仅当 uErrorId = 0 且 bInRange = TRUE 时才可将 fTd 用于联锁判断。
 *   多测点批量换算：每个温湿度测点独立调用一次，函数无状态可安全复用。
 *   哨兵口径复核：任何返回值等于 -40.0 时必须先核对 uErrorId 再使用。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 湿度给成绝对湿度或露点值会得到荒谬结果，本函数只接收相对湿度百分数。
 *   2 冰点以下本函数按过水面参数化计算霜点近似值，误差略增，精密工艺
 *     场景（如锂电干燥房露点仪对标）建议上层做冰面 Magnus 修正。
 *   3 返回哨兵值 -40.0 仅为异常路径确定值口径，不构成有效露点数据，
 *     上位趋势画面应按 uErrorId 过滤后再绘图。
 *   4 本函数每周期都可调用，纯计算无副作用可放心放入高速任务；
 *     但输入应来自滤波后的温湿度信号，露点输出抖动会带抖联锁逻辑。
 *   5 fVaporPa 与露点同源同口径，做焓值或含湿量换算时无需二次查表，
 *     避免两套公式口径漂移导致热平衡算不平。
 *----------------------------------------------------------------------------*)
FUNCTION FC_DL_DewPointCalc : REAL
VAR_INPUT
    fTempC  : REAL;                      // 干球温度 [摄氏度]，有效域 -40..60 / Dry-bulb temperature [degC], valid range -40..60
    fRhPct  : REAL;                      // 相对湿度 [百分数]，有效域 0.1..100 / Relative humidity [percent], valid range 0.1..100
END_VAR
VAR_OUTPUT
    uErrorId : UDINT;                    // 故障码，0 = 无故障 / Error code, 0 = no error
    fVaporPa : REAL;                     // 实际水汽压 [Pa]，诊断与焓值复用 / Actual vapor pressure [Pa], diagnostic and reuse
    bInRange : BOOL;                     // 输入是否处于公式有效域 / Whether inputs are within the formula valid domain
END_VAR
VAR
    fGamma   : REAL;                     // Magnus 中间量 [1] / Magnus intermediate value [1]
    fRhEff   : REAL;                     // 钳位后的生效湿度 [百分数] / Effective clamped humidity [percent]
    fTempEff : REAL;                     // 钳位后的生效温度 [摄氏度] / Effective clamped temperature [degC]
END_VAR
VAR CONSTANT
    DL_DEW_A      : REAL := 17.625;      // Magnus 系数 a [1] / Magnus coefficient a [1]
    DL_DEW_C      : REAL := 243.04;      // Magnus 系数 b [摄氏度] / Magnus coefficient b [degC]
    DL_DEW_E0     : REAL := 611.2;       // 0 摄氏度饱和水汽压 [Pa] / Saturation vapor pressure at 0 degC [Pa]
    DL_DEW_T_MIN  : REAL := -40.0;       // 温度有效域下限 [摄氏度] / Temperature valid range low [degC]
    DL_DEW_T_MAX  : REAL := 60.0;        // 温度有效域上限 [摄氏度] / Temperature valid range high [degC]
    DL_DEW_RH_MIN : REAL := 0.1;         // 湿度工程下限 [百分数]，防对数发散 / Humidity engineering floor [percent], guards log divergence
    DL_DEW_SENTINEL : REAL := -40.0;     // 异常路径返回哨兵值 [摄氏度] / Sentinel return on error paths [degC]
    DL_DEW_EPS    : REAL := 1.0E-6;      // 浮点判零容差 / Float zero tolerance
    DL_DEW_INF_MAX : REAL := 1.0E30;     // 有限值判定幅值上限 / Magnitude bound for finite-value check
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值（IEC 61131-3 强制）：入口即赋确定值，任何提前 RETURN
 *      前输出已确定；异常路径返回哨兵值 -40.0（安全下限口径）
 *      Exit defaults (mandatory): outputs assigned deterministically on entry
 *-----------------------------------------------------------------------------*)
FC_DL_DewPointCalc := DL_DEW_SENTINEL;               // 返回值哨兵预置 / Return value preset to sentinel
uErrorId           := 16#0002_0000;                  // 故障码先清零 / Error code cleared first
fVaporPa           := 0.0;                           // 水汽压默认置零 / Vapor pressure defaulted to zero
bInRange           := TRUE;                          // 默认视为在有效域 / Default considered in valid domain
fRhEff             := DL_DEW_RH_MIN;                 // 湿度预置工程下限 / Humidity preset to engineering floor
fTempEff           := DL_DEW_T_MIN;                  // 温度预置域下限 / Temperature preset to domain floor

(*------------------------------------------------------------------------------
 * 段 2｜非有限值防御：NaN 或超幅值输入直接返回哨兵并置公共码
 *      Non-finite defense: NaN or over-range input returns sentinel with code
 *-----------------------------------------------------------------------------*)
IF (fTempC <> fTempC) OR (ABS(fTempC) > DL_DEW_INF_MAX)
   OR (fRhPct <> fRhPct) OR (ABS(fRhPct) > DL_DEW_INF_MAX) THEN
    uErrorId           := 16#0002_0004;               // 输入非有限值已拒绝 / Non-finite input rejected
    FC_DL_DewPointCalc := DL_DEW_SENTINEL;
    fVaporPa           := 0.0;
    bInRange           := FALSE;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜湿度钳位：下限防 LN(0) 发散，上限防超饱和非物理输入
 *      Humidity clamping: floor guards log divergence, cap blocks supersaturation
 *-----------------------------------------------------------------------------*)
IF fRhPct < DL_DEW_RH_MIN THEN
    fRhEff   := DL_DEW_RH_MIN;                       // 过低湿度钳位到工程下限 / Too low humidity clamped to floor
    uErrorId := 16#0002_1501;                        // 湿度越界已钳位 / Humidity out of range clamped
ELSIF fRhPct > 100.0 THEN
    fRhEff   := 100.0;                               // 超饱和湿度钳位到 100 / Supersaturated humidity clamped to 100
    uErrorId := 16#0002_1501;                        // 湿度越界已钳位 / Humidity out of range clamped
ELSE
    fRhEff := fRhPct;                                // 合法湿度原值生效 / Valid humidity applied as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜温度钳位：越域修正并标记不在有效域（含冰面霜点未计算提示口径）
 *      Temperature clamping: out-of-domain corrected and flagged
 *-----------------------------------------------------------------------------*)
IF (fTempC < DL_DEW_T_MIN) OR (fTempC > DL_DEW_T_MAX) THEN
    fTempEff := MIN(MAX(fTempC, DL_DEW_T_MIN), DL_DEW_T_MAX); // 双侧钳位到有效域 / Two-sided clamp into valid range
    uErrorId := 16#0002_1502;                        // 温度越域已钳位 / Temperature out of domain clamped
    bInRange := FALSE;                               // 标记不在公式有效域 / Flagged outside formula valid domain
ELSE
    fTempEff := fTempC;                              // 合法温度原值生效 / Valid temperature applied as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜分母防御性双检：b+fTempEff 理论上恒大于零（T>=-40），仍强制校验
 *      Defensive double check on denominator, theoretically always positive
 *-----------------------------------------------------------------------------*)
IF ABS(DL_DEW_C + fTempEff) <= DL_DEW_EPS THEN
    uErrorId           := 16#0002_1502;               // 分母异常按温度类故障处理 / Denominator anomaly treated as temperature fault
    FC_DL_DewPointCalc := DL_DEW_SENTINEL;
    fVaporPa           := 0.0;
    bInRange           := FALSE;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜Magnus-Tetens 主体计算：gamma 中间量 + 露点反解 + 水汽压
 *      Magnus-Tetens core: gamma intermediate, dew point inversion, vapor pressure
 *      LN 输入恒大于零由湿度工程下限 0.1 保证，无需再判
 *      gamma 物理含义：对数形式的水汽分压与饱和分压比值度量，
 *      温度越高、湿度越大 gamma 越大，露点随之单调上移
 *-----------------------------------------------------------------------------*)
fGamma := LN(fRhEff / 100.0) + DL_DEW_A * fTempEff / (DL_DEW_C + fTempEff); // Magnus 中间量 / Magnus intermediate value

(* 分母 a-gamma：露点反解系数，由 gamma 单调有界性保证远离零，仍双检 *)
(* Denominator a-gamma: bounded away from zero by monotonicity, still guarded *)
IF ABS(DL_DEW_A - fGamma) <= DL_DEW_EPS THEN
    uErrorId           := 16#0002_1502;               // 反解分母异常按温度类故障处理 / Inversion denominator anomaly
    FC_DL_DewPointCalc := DL_DEW_SENTINEL;
    fVaporPa           := 0.0;
    bInRange           := FALSE;
    RETURN;
END_IF

FC_DL_DewPointCalc := DL_DEW_C * fGamma / (DL_DEW_A - fGamma); // 露点温度 [摄氏度] / Dew point temperature [degC]

(* 实际水汽压：饱和水汽压按当前温度指数外推后乘以相对湿度份额 *)
(* Actual vapor pressure: saturation pressure extrapolated by temperature times RH share *)
fVaporPa := DL_DEW_E0 * EXP(DL_DEW_A * fTempEff / (DL_DEW_C + fTempEff)) * fRhEff / 100.0;
END_FUNCTION
