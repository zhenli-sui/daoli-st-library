//==============================================================================
// 函数：FC_DL_WetBulbTempCalc ｜ 中文名称：湿球温度估算（焓湿图族拆分③）
// 所属子库：DL_Algo ｜ 版本：v1.1.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：由干球温度 + 相对湿度 + 大气压求解湿球温度。v1.1.0 起
//           【二分法重写】（R108 挂账修复，替代 v1.0.1 定点迭代）：
//           在区间 [Tw_lo, Tw_hi] = [负 40 摄氏度, 干球温度] 上对残差
//           g(Tw) = p_ws(Tw) - gamma·p·(T - Tw) - e 做二分求根，其中
//           e = RH/100·p_ws(T)，gamma = 0.000662 [1/摄氏度]，p 由引脚
//           注入 [Pa]。g(Tw) 关于 Tw 严格单调递增（g 的导数 = p_ws 的
//           导数 + gamma·p，两项恒正），故根唯一、二分必收敛，不存在
//           v1.0.1 的结构性发散路径。收敛精度 0.05 摄氏度（区间半宽），
//           迭代上限 40 次（防死锁计数器强制；区间初宽最大 100 摄氏度，
//           理论 11 次即达精度，上限仅为防御性兜底）。
//           饱和水汽压采用 Magnus-Tetens 过水公式内联实现：
//           p_ws(T) = 610.94·EXP(17.625·T / (T + 243.04)) [Pa]，
//           与残差方程同源自洽（v1.0.1 委托 FC_DL_VaporPressureSat 的
//           依赖自 v1.1.0 起解除，本件零外部公式依赖）。
// 开源溯源 (Origin)：改写自 OSCAT Building 行为定义（OSCAT 许可，仅行为定义，零代码行）——道莅 clean-room 实现
// 单位表：T[摄氏度] / Tw[摄氏度] / RH[%] / p[Pa] / p_ws[Pa] / e[Pa] /
//         gamma·p[Pa每摄氏度]
// 错误码表：16#0002_2F01 信息级（温度/湿度域外已钳位照算，或数值解超
//           承诺域下限被钳回 [摄氏度负 20]，不置 bError）/
//           16#0002_2F02 信息级（迭代达 40 次上限仍未达 0.05 摄氏度
//           区间精度，降级输出区间中点值，不置 bError——经验式本身是
//           近似）/ 16#0002_2F10 故障级（大气压非法或任一输入非有限，
//           置 bError）/ 16#0002_2F11 故障级（输入致二分区间非法：下界
//           残差非负、或终值自洽复检超容差，置 bError——该场景不可由
//           2F10 的输入幅值类判据观测，属区间构造独立域）/
//           16#0002_2F12 预留禁用（不得挪用）
// 状态机：N/A（纯函数；二分在单次调用内完成，无跨拍状态）
// 边界行为：① 干球温度域外（负 20~60 摄氏度外）钳位照算 + 信息 2F01，
//           头注释声明精度承诺收窄至负 20~60 摄氏度（Magnus 过水公式
//           拟合域外误差不承诺）；② RH 域外钳 1~100 + 信息 2F01；
//           ③ 大气压域外（50000~110000 Pa 外）→ 故障 2F10（v1.1.0
//           收窄声明：低压组合会使下界残差失去负号证明，见收敛域声明）；
//           ④ 二分 40 次未达精度 → 输出区间中点 + bValid := TRUE +
//           信息 2F02（降级可观测，不置故障）；⑤ 区间非法或自洽复检
//           失败 → 故障 2F11、bValid := FALSE、输出 0；异常路径输出
//           确定值，绝不输出未初始化值。
// 收敛域声明（R108 判据）：输入子域 T[负 20, 60] 摄氏度、RH[1, 100]%、
//           p[50000, 110000] Pa。收敛性论证：g(Tw) 在 Tw 上严格单调递增
//           （导数 = dp_ws/dTw + gamma·p > 0，过水 Magnus 斜率域内恒正）；
//           上界 g(T) = (1 - RH/100)·p_ws(T) >= 0（RH 钳后 <= 100 保证）；
//           下界 g(负 40) <= 19.0 - 0.000662·50000·20 - 1.04 < 0（取
//           p_ws(负 40) = 19.0 Pa、p >= 50000 Pa、T >= 负 20、RH >= 1
//           的最坏组合），故根必落于区间内，二分对区间宽度指数收敛，
//           无发散路径；低压域外（p < 50000）下界残差负号不再有保证，
//           按故障 2F10 拒绝而非静默外推。
// 验收向量推演（算法已证，手算，允差 ±0.1 摄氏度）：① T=30 摄氏度、
//           RH=65%、p=101325 Pa → Tw 约 24.8 摄氏度；② T=5 摄氏度、
//           RH=80%、p=101325 Pa → Tw 约 3.6 摄氏度；③ T=负 10 摄氏度、
//           RH=20%、p=101325 Pa → Tw 约 负 12.6 摄氏度；④ RH=100% 退化
//           → Tw = T 精确（g(T) = 0，区间上界即根）。编译器已证
//           （三平台）：未跑，由收口方登记。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · T1-2 焓湿图族拆分③ · 迭代式按检索原文修正）
//           v1.0.1 2026-11-17 R23 终审挂账警示（逻辑零改动）：DL_WB_GAMMA
//           1000 倍量纲错位 + 定点迭代在 e_s'(Tw)/(gamma·p) > 1 区间
//           结构性发散，修复前禁止用于生产数据链。
//           v1.1.0 2026-11-17 R24 挂账修复：二分法重写，引脚契约不变
//           （fTempC/fRh/fPress → fWetBulbC/bClamped/eErr/bError/bValid），
//           码位 2F01/2F02/2F10/2F11/2F12 全保留，语义重映射：2F02 =
//           迭代达上限未达 0.05 K 精度、2F11 = 输入致二分区间非法；
//           饱和压改 Magnus-Tetens 内联自洽实现，解除族属主件依赖。
//==============================================================================

FUNCTION FC_DL_WetBulbTempCalc : BOOL
VAR_INPUT
    fTempC  : LREAL;                     // 干球温度 [摄氏度]，有效域 -20.0..60.0，域外钳位照算 / Dry-bulb temperature [degC], valid range -20.0..60.0
    fRh     : LREAL;                     // 相对湿度 [百分数]，有效域 1.0..100.0，域外钳位照算 / Relative humidity [percent], valid range 1.0..100.0
    fPress  : LREAL := 101325.0;         // 大气压 [Pa]，有效域 50000..110000，域外故障拒绝 / Atmospheric pressure [Pa], valid range 50000..110000
END_VAR
VAR_OUTPUT
    fWetBulbC : LREAL;                   // 湿球温度 [摄氏度] / Wet-bulb temperature [degC]
    bClamped  : BOOL;                    // TRUE = 温度或湿度输入已钳位 / TRUE = temperature or humidity input clamped
    eErr      : UDINT;                   // 错误码，0 = 无错，码位 16#0002_2F01 起信息级、16#0002_2F10 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError    : BOOL;                    // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid    : BOOL;                    // 输出可用标志 / Outputs usable flag
END_VAR
VAR CONSTANT
    DL_WB_TMIN     : LREAL := -20.0;     // 承诺域下限 [摄氏度]，域外精度不承诺 / Promised domain floor [degC], accuracy not promised outside
    DL_WB_TMAX     : LREAL := 60.0;      // 承诺域上限 [摄氏度] / Promised domain ceiling [degC]
    DL_WB_BRACKET  : LREAL := -40.0;     // 二分区间下界 [摄氏度]，收敛域声明内恒有负残差 / Bisection bracket floor [degC]
    DL_WB_RH_MIN   : LREAL := 1.0;       // 湿度钳位下限 [百分数] / Humidity clamp floor [percent]
    DL_WB_RH_MAX   : LREAL := 100.0;     // 湿度钳位上限 [百分数] / Humidity clamp ceiling [percent]
    DL_WB_PMIN     : LREAL := 50000.0;   // 大气压有效域下限 [Pa] / Pressure domain floor [Pa]
    DL_WB_PMAX     : LREAL := 110000.0;  // 大气压有效域上限 [Pa] / Pressure domain ceiling [Pa]
    DL_WB_ITER_MAX : UINT  := 40;        // 二分迭代上限 [次]，防死锁计数器强制 / Bisection iteration ceiling [count], forced deadlock guard
    DL_WB_PREC     : LREAL := 0.05;      // 收敛精度：区间半宽 [摄氏度] / Convergence precision: bracket half-width [degC]
    DL_WB_GAMMA    : LREAL := 0.000662;  // 心理测量常数 gamma [1/摄氏度]（v1.1.0 量纲已修正） / Psychrometric constant gamma [1/degC], dimension fixed in v1.1.0
    DL_WB_MAGNUS_A : LREAL := 610.94;    // Magnus-Tetens 系数 A [Pa] / Magnus-Tetens coefficient A [Pa]
    DL_WB_MAGNUS_B : LREAL := 17.625;    // Magnus-Tetens 系数 B [无量纲] / Magnus-Tetens coefficient B [dimensionless]
    DL_WB_MAGNUS_C : LREAL := 243.04;    // Magnus-Tetens 系数 C [摄氏度] / Magnus-Tetens coefficient C [degC]
    DL_WB_RES_TOL  : LREAL := 50.0;      // 终值自洽复检容差 [Pa]（0.05 摄氏度区间对应残差带的上界） / Final residual recheck tolerance [Pa]
    DL_WB_EPS      : LREAL := 1.0E-6;    // 浮点判零容差 [混合] / Float zero tolerance
    DL_WB_INF      : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
END_VAR
VAR
    fTEff    : LREAL;                    // 钳位后的生效干球温度 [摄氏度] / Effective clamped dry-bulb temperature [degC]
    fRhEff   : LREAL;                    // 钳位后的生效湿度 [百分数] / Effective clamped humidity [percent]
    fPwsT    : LREAL;                    // 干球温度下饱和压 p_ws(T) [Pa] / Saturation pressure at T [Pa]
    fVpAct   : LREAL;                    // 实际水汽压 e = RH/100·p_ws(T) [Pa] / Actual vapor pressure e [Pa]
    fGamPa   : LREAL;                    // 心理测量系数 gamma·p [Pa每摄氏度]，量纲已修正 / Psychrometric coefficient gamma times p [Pa/degC]
    fLo      : LREAL;                    // 二分区间下界 [摄氏度] / Bisection bracket low [degC]
    fHi      : LREAL;                    // 二分区间上界 [摄氏度] / Bisection bracket high [degC]
    fMid     : LREAL;                    // 二分中点 [摄氏度] / Bisection midpoint [degC]
    fResLo   : LREAL;                    // 下界残差 g(fLo) [Pa] / Bracket-low residual [Pa]
    fResMid  : LREAL;                    // 中点残差 g(fMid) [Pa] / Midpoint residual [Pa]
    fResFin  : LREAL;                    // 终值自洽复检残差 [Pa] / Final residual recheck [Pa]
    fMagDen  : LREAL;                    // Magnus 分母 (T + 243.04) [摄氏度] / Magnus denominator [degC]
    uIter    : UINT;                     // 迭代计数 [次] / Iteration counter [count]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值：入口即赋确定值
 *      Exit defaults: outputs assigned deterministically on entry
 *-----------------------------------------------------------------------------*)
FC_DL_WetBulbTempCalc := FALSE;          // 返回值默认无效 / Return value preset invalid
fWetBulbC := 0.0;                        // 湿球默认置零 / Wet bulb preset to zero
bClamped := FALSE;                       // 钳位标志默认 FALSE / Clamped flag preset FALSE
eErr := 16#0000_0000;                    // 错误码先清零 / Error code cleared first
bError := FALSE;                         // 故障标志先清零 / Fault flag cleared first
bValid := FALSE;                         // 可用标志先清零 / Usable flag cleared first

(*------------------------------------------------------------------------------
 * 段 2｜非有限值与大气压域闸门（R79 双侧幅值判 + v1.1.0 收窄域）
 *      Non-finite defense and the narrowed pressure-domain gate
 *-----------------------------------------------------------------------------*)
IF (fTempC <> fTempC) OR (ABS(fTempC) > DL_WB_INF)
   OR (fRh <> fRh) OR (ABS(fRh) > DL_WB_INF)
   OR (fPress <> fPress) OR (ABS(fPress) > DL_WB_INF) THEN
    eErr   := 16#0002_2F10;              // 故障级：输入非有限 / Fault: non-finite input
    bError := TRUE;                      // 置故障标志（R45 配对） / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF
IF (fPress < DL_WB_PMIN) OR (fPress > DL_WB_PMAX) THEN
    eErr   := 16#0002_2F10;              // 故障级：大气压域外（收敛域声明外无负残差保证） / Fault: pressure outside the convergence domain
    bError := TRUE;                      // 置故障标志 / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜输入钳位：温度 -20~60、湿度 1~100，信息级共码 2F01（R90）
 *      Input clamping, shared info code per R90
 *-----------------------------------------------------------------------------*)
IF (fTempC < DL_WB_TMIN) OR (fTempC > DL_WB_TMAX) THEN
    fTEff := MIN(MAX(fTempC, DL_WB_TMIN), DL_WB_TMAX); // 温度双侧钳位 / Two-sided temperature clamp
    bClamped := TRUE;                    // 钳位声明置位 / Clamped flag raised
    eErr := 16#0002_2F01;                // 信息级：输入已钳位（不置 bError） / Info: input clamped, no fault flag
ELSE
    fTEff := fTempC;                     // 合法温度原值生效 / Valid temperature applied as-is
END_IF
IF (fRh < DL_WB_RH_MIN) OR (fRh > DL_WB_RH_MAX) THEN
    fRhEff := MIN(MAX(fRh, DL_WB_RH_MIN), DL_WB_RH_MAX); // 湿度双侧钳位 / Two-sided humidity clamp
    bClamped := TRUE;                    // 钳位声明置位 / Clamped flag raised
    eErr := 16#0002_2F01;                // 信息级：输入已钳位 / Info: input clamped
ELSE
    fRhEff := fRh;                       // 合法湿度原值生效 / Valid humidity applied as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜系数与残差量预置：Magnus-Tetens 内联（与残差同源自洽）
 *      Coefficients preset, Magnus-Tetens inline, self-consistent
 *-----------------------------------------------------------------------------*)
fMagDen := fTEff + DL_WB_MAGNUS_C;       // Magnus 分母 [摄氏度]，域内恒 >= 203 / Magnus denominator, always >= 203 in domain
IF fMagDen <= DL_WB_EPS THEN
    eErr   := 16#0002_2F11;              // 故障级：分母退化归区间非法（域内不可达，防御兜底） / Fault: degenerate denominator folded into the bracket fault
    bError := TRUE;                      // 置故障标志 / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF
fPwsT  := DL_WB_MAGNUS_A * EXP(DL_WB_MAGNUS_B * fTEff / fMagDen); // 干球饱和压 [Pa] / Saturation pressure at T [Pa]
fVpAct := (fRhEff / 100.0) * fPwsT;      // 实际水汽压 e [Pa] / Actual vapor pressure e [Pa]
fGamPa := DL_WB_GAMMA * fPress;          // 心理测量系数 gamma·p [Pa每摄氏度] / Psychrometric coefficient [Pa/degC]

(*------------------------------------------------------------------------------
 * 段 5｜区间构造与合法性闸：g 单调增，要求 g(fLo) < 0 <= g(fHi)
 *      Bracket construction and validity gate
 *-----------------------------------------------------------------------------*)
fLo := DL_WB_BRACKET;                    // 下界 -40 摄氏度 / Bracket low
fHi := fTEff;                            // 上界取干球 / Bracket high, the dry bulb
fResLo := DL_WB_MAGNUS_A * EXP(DL_WB_MAGNUS_B * fLo / (fLo + DL_WB_MAGNUS_C))
          - fGamPa * (fTEff - fLo) - fVpAct; // 下界残差 g(fLo) [Pa] / Bracket-low residual [Pa]
IF fResLo >= DL_WB_EPS THEN
    fWetBulbC := 0.0;                    // 区间非法：丢弃结果 / Illegal bracket, result discarded
    eErr   := 16#0002_2F11;              // 故障级：输入致二分区间非法 / Fault: input-induced illegal bracket
    bError := TRUE;                      // 置故障标志 / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜二分迭代：区间半宽收敛于 0.05 摄氏度，计数器强制防死锁
 *      Bisection loop, counter-forced deadlock guard
 *-----------------------------------------------------------------------------*)
uIter := 0;                              // 迭代计数清零 / Counter cleared
WHILE ((fHi - fLo) > DL_WB_PREC) AND (uIter < DL_WB_ITER_MAX) DO
    fMid := 0.5 * (fLo + fHi);           // 区间中点 [摄氏度] / Bracket midpoint
    fMagDen := fMid + DL_WB_MAGNUS_C;    // Magnus 分母 [摄氏度] / Magnus denominator
    IF fMagDen <= DL_WB_EPS THEN
        fWetBulbC := 0.0;                // 分母退化：丢弃结果 / Degenerate denominator, result discarded
        eErr   := 16#0002_2F11;          // 故障级：退化归区间非法（R90） / Fault: degeneracy folded into the bracket fault
        bError := TRUE;                  // 置故障标志 / Raise the fault flag
        bValid := FALSE;                 // 输出不可用 / Outputs unusable
        RETURN;
    END_IF
    fResMid := DL_WB_MAGNUS_A * EXP(DL_WB_MAGNUS_B * fMid / fMagDen)
               - fGamPa * (fTEff - fMid) - fVpAct; // 中点残差 g(fMid) [Pa] / Midpoint residual [Pa]
    IF fResMid >= 0.0 THEN
        fHi := fMid;                     // 根在中点以下，上界下压 / Root below midpoint, lower the high bound
    ELSE
        fLo := fMid;                     // 根在中点以上，下界上抬 / Root above midpoint, raise the low bound
    END_IF
    uIter := uIter + 1;                  // 计数递增（防死锁强制项） / Counter increment, the forced guard
END_WHILE
fMid := 0.5 * (fLo + fHi);               // 终值取区间中点 / Final value is the bracket midpoint

(*------------------------------------------------------------------------------
 * 段 7｜终值自洽复检与输出域钳回：残差超容差归 2F11；越 -20 钳回 + 2F01
 *      Final residual recheck and output-domain clamp
 *-----------------------------------------------------------------------------*)
fMagDen := fMid + DL_WB_MAGNUS_C;        // Magnus 分母 [摄氏度] / Magnus denominator
IF fMagDen <= DL_WB_EPS THEN
    fWetBulbC := 0.0;                    // 退化：丢弃结果 / Degenerate, result discarded
    eErr   := 16#0002_2F11;              // 故障级：退化归区间非法（R90） / Fault: degeneracy folded into the bracket fault
    bError := TRUE;                      // 置故障标志 / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF
fResFin := DL_WB_MAGNUS_A * EXP(DL_WB_MAGNUS_B * fMid / fMagDen)
           - fGamPa * (fTEff - fMid) - fVpAct; // 终值残差 [Pa] / Final residual [Pa]
IF ABS(fResFin) > DL_WB_RES_TOL THEN
    fWetBulbC := 0.0;                    // 自洽复检失败：丢弃结果 / Self-consistency failed, result discarded
    eErr   := 16#0002_2F11;              // 故障级：复检失败归区间非法语义（R90） / Fault: recheck failure folded into the bracket fault
    bError := TRUE;                      // 置故障标志 / Raise the fault flag
    bValid := FALSE;                     // 输出不可用 / Outputs unusable
    RETURN;
END_IF
IF fMid < DL_WB_TMIN THEN
    fMid := DL_WB_TMIN;                  // 数值解越承诺域下限，钳回 -20 / Numerical solution below the promised floor, clamped back
    eErr := 16#0002_2F01;                // 信息级：解域下限钳回（不置 bError） / Info: solution clamped to the floor, no fault flag
END_IF
IF fMid > fTEff THEN
    fMid := fTEff;                       // 数值上溢钳回干球（湿球不超过干球） / Numerical overshoot clamped to the dry bulb
END_IF
fWetBulbC := fMid;                       // 湿球温度出口 / Wet-bulb temperature outlet
IF uIter >= DL_WB_ITER_MAX THEN
    eErr := 16#0002_2F02;                // 信息级：40 次未达精度，降级输出中点（不置故障） / Info: iteration ceiling met without precision, degraded midpoint, no fault
END_IF
bValid := TRUE;                          // 输出可用（含降级情形，见 2F02 口径） / Outputs usable, including the degraded case
FC_DL_WetBulbTempCalc := TRUE;           // 返回 TRUE = 计算有效 / Return TRUE = computation valid
END_FUNCTION
