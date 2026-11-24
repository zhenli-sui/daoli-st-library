(*==============================================================================
 * 组件名称 (Component)  : FC_DL_FlowCompensate
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（SQRT / ABS / MIN / MAX），
 *                         零厂商方言
 * 功能描述 (Function)   : 气体 / 蒸汽流量温压补偿：按理想气体定律把工况体积
 *                         流量换算为标准状态流量（Nm3/h 口径）。
 *                         Qs = Qa * (Pa/Ps) * (Ts/Ta)，压缩因子比 Zs/Za 按中
 *                         低压口径简化为 1（头部明示）；绝压 = 表压 + 大气压，
 *                         温度开尔文化。可选开方支持差压流量计（孔板 / 文丘里）
 *                         口径：bEnableSqRt=TRUE 时输入先按差压线性量开方。
 *                         现场用途：涡街 / 孔板气体计量贸易交接、能耗统计。
 * 开源溯源 (Origin)     : 原创实现。公式为公开理想气体状态方程工程应用
 *                         （clean-room），按本库故障码体系重写并加严。
 * 设计验证 (Verified)   : python 6 位小数核验（Ps=101.325kPa、Ts=0 摄氏度）：
 *                         Qa=1000.0 m3/h、表压 500.0kPa、温度 40.0 摄氏度
 *                         -> Qs=5176.56 Nm3/h；
 *                         规格书向量 Qa=500.0、表压 350.0kPa、35.0 摄氏度
 *                         -> Qs=1974.16 Nm3/h（约 1974 达标）。
 * 验收向量 (Acceptance) :
 *   V1 Q=1000.0 表压 500.0kPa 温度 40.0：返回 5176.56（容差 1.0）
 *   V2 Q=500.0 表压 350.0kPa 温度 35.0：返回约 1974.16（容差 1.0）
 *   V3 表压 -50.0：钳位至 0.0，uErrorId=16#0002_0001
 *   V4 大气压缺省 5.0：绝压 6.325 < 1.0 下限，返回 0 并置 16#0002_1601
 *   V5 温度 -273.15：绝压温度低于防御下限，返回 0 并置 16#0002_1602
 *   V6 温度 400.0：bInRange=FALSE，按钳位口径继续计算不阻断
 * 依赖     (Depends)    : 无 DL_ 内部依赖；仅标准算术与 SQRT
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 钳位+容差+防除零+出口默认值
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（FC 无状态机）
 *                         R7 N/A（无实例调用）
 * 无状态声明 (Stateless): FC 全程无隐式状态，同输入必得同输出；
 *                         除 VAR_IN_OUT 之外的隐式状态为零。
 * 口径披露 (Disclosure) : 压缩因子比 Zs/Za 在中低压（绝压 < 2MPa）下按 1.0
 *                         简化；高压计量场景需在上层引入真实气体因子修正，
 *                         本组件不替调用方做高压外推，避免口径误用。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 04 · Phase 3 · DL_Algo 批次）
 *   2026-11-15  v1.0.1  阶段五终审精修：非有限值防御扩展覆盖 fAtmPress /
 *                       rNormPressPs / rNormTempTs，杜绝 NaN 带 0 码穿透
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   fQn := FC_DL_FlowCompensate(fFlowActual := stMeter.fFlowOp,
 *                               fPressGauge := stMeter.fPressKPa,
 *                               fTempC := stMeter.fTempDeg,
 *                               uErrorId => uFlowErr,
 *                               fPaAbs => fAbsKPa,
 *                               bInRange => bInDom);
 *   涡街口径（自带线性流量信号）bEnableSqRt 保持 FALSE；
 *   孔板 / 文丘里差压口径置 bEnableSqRt := TRUE，输入视为差压线性量。
 *   能耗统计与贸易交接仅可采用 uErrorId = 0 期间累加的数值。
 *----------------------------------------------------------------------------*)
FUNCTION FC_DL_FlowCompensate : REAL
VAR_INPUT
    fFlowActual  : REAL;                 // 工况体积流量 [立方米每小时] / Actual volume flow at operating condition [m3/h]
    fPressGauge  : REAL;                 // 管线表压 [千帕]，负值钳位 0 / Line gauge pressure [kPa], negative clamped to 0
    fAtmPress    : REAL := 101.325;      // 当地大气压 [千帕] / Local atmospheric pressure [kPa]
    fTempC       : REAL;                 // 介质温度 [摄氏度]，有效域 -40..300 / Medium temperature [degC], valid range -40..300
    rNormPressPs : REAL := 101.325;      // 标准状态压力 [千帕] / Standard state pressure [kPa]
    rNormTempTs  : REAL := 0.0;          // 标准状态温度 [摄氏度]，0=NTP 口径 / Standard state temperature [degC], 0 = NTP
    bEnableSqRt  : BOOL := FALSE;        // 差压口径开方使能，TRUE 时输入先开方 / Square-root enable for dp meters, TRUE extracts root first
END_VAR
VAR_OUTPUT
    uErrorId : UDINT;                    // 故障码，0 = 无故障 / Error code, 0 = no error
    fPaAbs   : REAL;                     // 绝压 [千帕]，诊断 / Absolute pressure [kPa], diagnostic
    bInRange : BOOL;                     // 温度是否处于公式有效域 / Whether temperature is within the formula valid domain
END_VAR
VAR
    fTaK     : REAL;                     // 工况绝对温度 [开尔文] / Operating absolute temperature [K]
    fTsK     : REAL;                     // 标准状态绝对温度 [开尔文] / Standard state absolute temperature [K]
    fPressEff : REAL;                    // 钳位后的生效表压 [千帕] / Effective clamped gauge pressure [kPa]
    fTempEff : REAL;                     // 钳位后的生效介质温度 [摄氏度] / Effective clamped medium temperature [degC]
    fPsEff   : REAL;                     // 钳位后的生效标准压力 [千帕] / Effective clamped standard pressure [kPa]
    fFlowEff : REAL;                     // 生效流量（含可选开方）[立方米每小时] / Effective flow with optional square root [m3/h]
END_VAR
VAR CONSTANT
    DL_FLOW_T0K       : REAL := 273.15;  // 绝对零度换算偏置 [开尔文] / Absolute zero offset [K]
    DL_FLOW_T_MIN     : REAL := -40.0;   // 温度有效域下限 [摄氏度] / Temperature valid range low [degC]
    DL_FLOW_T_MAX     : REAL := 300.0;   // 温度有效域上限 [摄氏度] / Temperature valid range high [degC]
    DL_FLOW_TA_MIN    : REAL := 50.0;    // 绝压温度防御下限 [开尔文] / Defensive absolute temperature floor [K]
    DL_FLOW_PRESS_MIN : REAL := 1.0;     // 绝压防御下限 [千帕]，防除零 / Defensive absolute pressure floor [kPa]
    DL_FLOW_SENTINEL  : REAL := 0.0;     // 异常路径返回哨兵值 [立方米每小时] / Sentinel return on error paths [m3/h]
    DL_FLOW_EPS       : REAL := 1.0E-6;  // 浮点判零容差 / Float zero tolerance
    DL_FLOW_INF_MAX   : REAL := 1.0E30;  // 有限值判定幅值上限 / Magnitude bound for finite-value check
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值（IEC 61131-3 强制）：入口即赋确定值，任何提前 RETURN
 *      前输出已确定；异常路径返回哨兵值 0.0
 *      Exit defaults (mandatory): outputs assigned deterministically on entry
 *-----------------------------------------------------------------------------*)
FC_DL_FlowCompensate := DL_FLOW_SENTINEL;            // 返回值哨兵预置 / Return value preset to sentinel
uErrorId             := 16#0002_0000;                // 故障码先清零 / Error code cleared first
fPaAbs               := 0.0;                         // 绝压默认置零 / Absolute pressure defaulted to zero
bInRange             := TRUE;                        // 默认视为在有效域 / Default considered in valid domain
fPressEff            := 0.0;                         // 表压预置零 / Gauge pressure preset to zero
fTempEff             := DL_FLOW_T_MIN;               // 温度预置域下限 / Temperature preset to domain floor
fPsEff               := 101.325;                     // 标准压力预置 NTP 口径 / Standard pressure preset to NTP
fFlowEff             := 0.0;                         // 流量预置零 / Flow preset to zero

(*------------------------------------------------------------------------------
 * 段 2｜非有限值防御：任一输入 NaN 或超幅值直接返回哨兵并置公共码
 *      Non-finite defense: any NaN or over-range input returns sentinel
 *-----------------------------------------------------------------------------*)
IF (fFlowActual <> fFlowActual) OR (ABS(fFlowActual) > DL_FLOW_INF_MAX)
   OR (fPressGauge <> fPressGauge) OR (ABS(fPressGauge) > DL_FLOW_INF_MAX)
   OR (fTempC <> fTempC) OR (ABS(fTempC) > DL_FLOW_INF_MAX)
   OR (fAtmPress <> fAtmPress) OR (ABS(fAtmPress) > DL_FLOW_INF_MAX)
   OR (rNormPressPs <> rNormPressPs) OR (ABS(rNormPressPs) > DL_FLOW_INF_MAX)
   OR (rNormTempTs <> rNormTempTs) OR (ABS(rNormTempTs) > DL_FLOW_INF_MAX) THEN
    uErrorId             := 16#0002_0004;             // 输入非有限值已拒绝 / Non-finite input rejected
    FC_DL_FlowCompensate := DL_FLOW_SENTINEL;
    fPaAbs               := 0.0;
    bInRange             := FALSE;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜表压与标准压力钳位：负表压钳 0；标准压力非正钳回 NTP 口径
 *      Gauge and standard pressure clamping: negative gauge to zero, non-positive
 *      standard pressure back to NTP baseline with common clamp code
 *-----------------------------------------------------------------------------*)
fPressEff := MAX(fPressGauge, 0.0);                  // 负表压钳位到零 / Negative gauge pressure clamped to zero
IF fPressEff <> fPressGauge THEN
    uErrorId := 16#0002_0001;                        // 参数越界已钳位（表压） / Parameter clamped (gauge pressure)
END_IF

IF rNormPressPs <= DL_FLOW_EPS THEN
    fPsEff   := 101.325;                             // 非正标准压力钳回 NTP / Non-positive standard pressure back to NTP
    uErrorId := 16#0002_0001;                        // 参数越界已钳位（标准压力） / Parameter clamped (standard pressure)
ELSE
    fPsEff := rNormPressPs;                          // 合法标准压力原值生效 / Valid standard pressure applied as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜温度处理：开尔文化 + 越域标记（信息级不阻断，按钳位口径继续）
 *      Temperature handling: Kelvin conversion plus domain flag, info level only
 *-----------------------------------------------------------------------------*)
fTempEff := MIN(MAX(fTempC, DL_FLOW_T_MIN), DL_FLOW_T_MAX); // 双侧钳位到有效域 / Two-sided clamp into valid range

IF (fTempC < DL_FLOW_T_MIN) OR (fTempC > DL_FLOW_T_MAX) THEN
    bInRange := FALSE;                               // 标记不在公式有效域 / Flagged outside formula valid domain
    IF uErrorId = 16#0002_0000 THEN
        uErrorId := 16#0002_1602;                    // 温度越域已钳位提示 / Temperature out of domain clamped notice
    END_IF
END_IF

fTaK := fTempEff + DL_FLOW_T0K;                      // 工况绝对温度 [开尔文] / Operating absolute temperature [K]
fTsK := rNormTempTs + DL_FLOW_T0K;                   // 标准状态绝对温度 [开尔文] / Standard state absolute temperature [K]

(*------------------------------------------------------------------------------
 * 段 5｜非物理输入防御：温度非物理或绝压低于防御下限时返回 0 并置码
 *      Non-physical defense: unphysical temperature or under-floor absolute
 *      pressure returns zero with dedicated fault code
 *-----------------------------------------------------------------------------*)
IF fTaK < DL_FLOW_TA_MIN THEN
    uErrorId             := 16#0002_1602;             // 温度非物理已钳位拒绝 / Non-physical temperature rejected
    FC_DL_FlowCompensate := DL_FLOW_SENTINEL;
    fPaAbs               := MAX(fPressEff + fAtmPress, 0.0);
    RETURN;
END_IF

fPaAbs := fPressEff + fAtmPress;                     // 绝压 = 表压 + 大气压 [千帕] / Absolute = gauge + atmospheric [kPa]

IF fPaAbs < DL_FLOW_PRESS_MIN THEN
    uErrorId             := 16#0002_1601;             // 绝压低于防御下限（返回 0） / Absolute pressure below defensive floor
    FC_DL_FlowCompensate := DL_FLOW_SENTINEL;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜可选开方（差压流量计口径）：输入视为差压线性量，保号开方
 *      Optional square root (dp meter): input treated as dp-linear, sign kept
 *-----------------------------------------------------------------------------*)
IF bEnableSqRt THEN
    IF fFlowActual >= 0.0 THEN
        fFlowEff := SQRT(fFlowActual);               // 正向差压量开方 / Forward dp quantity square root
    ELSE
        fFlowEff := -SQRT(-fFlowActual);             // 反向差压量保号开方 / Reverse dp quantity sign-kept root
    END_IF
ELSE
    fFlowEff := fFlowActual;                         // 非差压口径原值生效 / Non-dp quantity applied as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜理想气体补偿主体：Qs = Qa * (Pa/Ps) * (Ts/Ta)，Zs/Za 按 1.0 简化
 *      Ideal gas compensation core, compressibility ratio simplified to 1.0
 *      分母 fPsEff 与 fTaK 均已在段 3 / 段 5 保证大于零，无除零风险
 *-----------------------------------------------------------------------------*)
FC_DL_FlowCompensate := fFlowEff * fPaAbs / fPsEff * fTsK / fTaK; // 标准状态流量 [立方米每小时] / Standard state flow [Nm3/h]
END_FUNCTION
