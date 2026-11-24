(*
    FB_DL_LeadLagCompensator —— 一阶超前滞后相位校正器
    ------------------------------------------------------------------
    分类      : DL_Algo / ControlLaw
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 超前滞后校正 Kc·(1 + T_lead·s)/(1 + T_lag·s) 为公开经典控制判据（公共知识）；
                Tustin 双线性离散化、在线改参保状态、旁路与保持判决、错误分级与码位
                100% 自有；只借「控制器归算法层且各律独立成块」的分类组织，不复制任何
                实现代码；clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 回路振荡但相位裕度不足时给前向通道加相位超前；抑制低频扰动时加滞后。
                离散化用 Tustin：a0 = 2·T_lag/Ts + 1，b0 = Kc·(1 + 2·T_lead/Ts)/a0，
                b1 = Kc·(1 − 2·T_lead/Ts)/a0，a1 = (1 − 2·T_lag/Ts)/a0。
                核心防御：① 采样周期越域或滞后时间小于采样周期，离散化极点会出单位圆，
                   此时故障级 2910 并旁路（宁可直通，不可输出病态波形）；
                ② 归一化分母 a0 前置防零判据，绝不裸除；
                ③ 增益非有限或近零即故障级 2911 并旁路——增益 0 会把回路静默掐死，
                   比报错更危险；
                ④ 输入非有限时输出保持末次有效且不旁路（旁路会把毒值直接注入执行器）；
                ⑤ 在线改参逐项比对并重算系数，历史状态保留不清零，切换无扰；
                ⑥ 输出双侧限幅，超限置 bSaturated。
                职责边界：前馈归 FeedforwardComp，纯滞后补偿归 SmithPredictor，各类滤波另件。
    错误码    : 16#0002_2901 时间常数超域已钳位 / 在线改参已重算系数（状态保留）/ 输出限幅生效——信息级，正常防御
                16#0002_2902 预留禁用（信息级，不得挪用）
                16#0002_2910 采样周期或滞后时间非法（离散化失效），旁路输出——故障级，fOut = fIn
                16#0002_2911 增益非有限或近零、输入非有限——故障级，输出保持末次有效
                16#0002_2912 预留禁用（故障级，不得挪用）
    码位总账  : 16#0002_2901 用 / 16#0002_2902 预留 ｜ 16#0002_2910 用 / 16#0002_2911 用 / 16#0002_2912 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
                （旁路/正常由单比特判决在段内直接给出，不存在顺序态）
    采样约定  : fbTrigReset 在本体首部无条件刷新；差分式为直接 I 型（fX1 / fY1 两状态量），
                与直接 II 型转置（单状态量）数学等价，选 I 型以保留输入输出历史供 HMI
                与改参连续性观测；时间基准全部来自 tSampleTime 引脚。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)
FUNCTION_BLOCK FB_DL_LeadLagCompensator
VAR_INPUT
    bEnable         : BOOL;                   // 使能，FALSE 旁路（输出 = 输入）/ enable, FALSE bypasses the block, output equals input
    bReset          : BOOL;                   // 复位，上升沿清内部状态 / reset, rising edge clears the internal state
    fIn             : REAL := 0.0;            // 输入（一般接偏差）[用户单位] / input, usually the control error [user unit]
    fGain           : REAL := 1.0;            // 静态增益 Kc [无量纲]，范围 -1000.0~1000.0，禁 0 / static gain [dimensionless], range -1000.0~1000.0, zero forbidden
    tLeadTime       : TIME := T#100MS;        // 超前时间常数 [ms]，范围 0~60000 / lead time constant [ms], range 0~60000
    tLagTime        : TIME := T#1S;           // 滞后时间常数 [ms]，范围 1~600000，必须 ≥ 采样周期 / lag time constant [ms], range 1~600000, must be >= the sample time
    tSampleTime     : TIME := T#100MS;        // 采样周期 [ms]，范围 1~10000 / sample time [ms], range 1~10000
    fOutLimit       : REAL := 1.0E6;          // 输出幅值限幅 [用户单位]，必须 > 0 / output magnitude limit [user unit], must be > 0
END_VAR
VAR_OUTPUT
    fOut            : REAL;                   // 校正后输出 [用户单位] / compensated output [user unit]
    bBypass         : BOOL;                   // 旁路中（参数非法或未使能）/ bypassed, illegal parameters or disabled
    bSaturated      : BOOL;                   // 输出被限幅 / output clamped
    uCoeffRev       : UDINT;                   // 系数重算次数（在线改参监视）[次] / coefficient recompute count [times]
    eErr            : UDINT;                  // 错误码，0=正常 / error id, 0=ok
    bError          : BOOL;                   // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigReset     : R_TRIG;                 // 复位上升沿实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    fB0             : REAL;                   // Tustin 归一化前向零次系数 [无量纲] / normalised feedforward zero-order coefficient
    fB1             : REAL;                   // Tustin 归一化前向一次系数 [无量纲] / normalised feedforward first-order coefficient
    fA1             : REAL;                   // Tustin 归一化反馈一次系数 [无量纲] / normalised feedback first-order coefficient
    fA0             : REAL;                   // Tustin 归一化分母（防零判据对象）[无量纲] / normalisation denominator, the zero guard target
    fX1             : REAL;                   // 上一拍输入历史 [用户单位] / previous input history [user unit]
    fY1             : REAL;                   // 上一拍输出历史 [用户单位] / previous output history [user unit]
    fPrevK          : REAL;                   // 上一拍增益，改参检测用 [无量纲] / previous gain for change detection [dimensionless]
    fPrevTl         : REAL;                   // 上一拍超前时间，改参检测用 [s] / previous lead time for change detection [s]
    fPrevTg         : REAL;                   // 上一拍滞后时间，改参检测用 [s] / previous lag time for change detection [s]
    fPrevTs         : REAL;                   // 上一拍采样周期，改参检测用 [s] / previous sample time for change detection [s]
    tLeadSec        : REAL;                   // 超前时间常数的秒值 [s] / lead time constant in seconds [s]
    tLagSec         : REAL;                   // 滞后时间常数的秒值 [s] / lag time constant in seconds [s]
    tTsSec          : REAL;                   // 采样周期的秒值 [s] / sample time in seconds [s]
    fLeadEff        : REAL;                   // 钳位后的超前时间 [s] / clamped lead time [s]
    fLagEff         : REAL;                   // 钳位后的滞后时间 [s] / clamped lag time [s]
    fLimitEff       : REAL;                   // 钳位后的输出限幅 [用户单位] / clamped output limit [user unit]
    bParamChg       : BOOL;                   // 在线改参标志 / parameter change flag
    bInit           : BOOL := FALSE;          // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
    nDtMs           : DINT;                   // 采样周期毫秒整数 [ms] / sample time in integer milliseconds [ms]
END_VAR
VAR CONSTANT
    DL_LL_LEAD_MAX   : TIME := T#60S;         // 超前时间上限 [ms] / lead time upper bound [ms]
    DL_LL_LAG_MAX    : TIME := T#600S;        // 滞后时间上限 [ms] / lag time upper bound [ms]
    DL_LL_GAIN_MAX   : REAL := 1000.0;        // 增益绝对值上限 [无量纲] / gain magnitude upper bound [dimensionless]
    DL_LL_DT_MAX     : TIME := T#10S;         // 采样周期上限 [ms] / sample time upper bound [ms]
    DL_LL_DT_MIN     : TIME := T#1MS;         // 采样周期下限 [ms] / sample time lower bound [ms]
    DL_FLOAT_EPS     : REAL := 1.0E-6;        // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_LL_MICRO      : REAL := 1.0E-6;        // 微秒级容差，离散系数判定用 [无量纲] / micro tolerance for the discrete coefficients
    DL_LL_MS_PER_S   : REAL := 1000.0;        // 毫秒到秒换算因子 [ms/s] / milliseconds per second [ms/s]
    DL_LL_TWO        : REAL := 2.0;           // Tustin 分子常数 2 [无量纲] / Tustin numerator constant two [dimensionless]
    DL_LL_INF_GUARD  : REAL := 1.0E38;        // 非有限幅值判定阈值 [无量纲] / non-finite magnitude guard [dimensionless]
    DL_LL_ONE        : REAL := 1.0;           // 一值常量，归一化式用 [无量纲] / one constant used by the normalisation [dimensionless]
    DL_LL_CNT_MAX    : UDINT := 16#FFFF_FFFE; // 重算计数饱和值 [次] / recompute counter saturation value [times]
    DL_LL_ZERO       : REAL := 0.0;           // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigReset(CLK := bReset);

// 段 2｜输出与状态预置 / segment 2, preset outputs and status
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bBypass := FALSE;                             // 预置非旁路 / preset not bypassed
bSaturated := FALSE;                          // 预置未饱和 / preset not saturated

// 段 3｜首扫初始化（唯一合法范式：初值 FALSE，判据 NOT bInit）/ segment 3, first-scan initialisation
IF NOT bInit THEN
    fX1 := DL_LL_ZERO;                        // 输入历史清零 / clear the input history
    fY1 := DL_LL_ZERO;                        // 输出历史清零 / clear the output history
    fPrevK := DL_LL_GAIN_MAX;                 // 上一拍增益置哨兵值，首拍必触发重算 / sentinel forces a recompute on the first scan
    fPrevTl := -DL_LL_TWO;                    // 相同哨兵策略 / same sentinel strategy
    fPrevTg := -DL_LL_TWO;                    // 相同哨兵策略 / same sentinel strategy
    fPrevTs := -DL_LL_TWO;                    // 相同哨兵策略 / same sentinel strategy
    bInit := TRUE;                            // 首扫只做一次 / first scan runs once only
END_IF

// 段 4｜使能闸：未使能直接旁路 / segment 4, enable gate bypasses the block
IF NOT bEnable THEN
    bBypass := TRUE;                          // 标记旁路 / flag the bypass
    fOut := fIn;                              // 旁路即直通 / bypass means straight through
    RETURN;                                   // 失能即出口 / disabled is the exit
END_IF

// 段 5｜采样周期与滞后时间闸（离散化失效时宁可直通）/ segment 5, discretisation validity gate
IF (tSampleTime < DL_LL_DT_MIN) OR (tSampleTime > DL_LL_DT_MAX) THEN
    eErr := 16#0002_2910;                     // 采样周期非法故障码 / illegal sample time fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bBypass := TRUE;                          // 旁路输出 / bypass the output
    fOut := fIn;                              // 直通，不输出病态波形 / straight through, never emit a pathological waveform
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF
IF tLagTime < tSampleTime THEN
    eErr := 16#0002_2910;                     // 滞后时间小于采样周期，极点会出单位圆 / a lag shorter than the sample time pushes the pole outside the unit circle
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bBypass := TRUE;                          // 旁路输出 / bypass the output
    fOut := fIn;                              // 直通 / straight through
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 6｜增益闸（增益 0 会把回路静默掐死，必须报错并旁路）/ segment 6, gain gate
IF (fGain <> fGain) OR (fGain > DL_LL_INF_GUARD) OR (fGain < -DL_LL_INF_GUARD)
   OR (ABS(fGain) <= DL_FLOAT_EPS) OR (ABS(fGain) > DL_LL_GAIN_MAX) THEN
    eErr := 16#0002_2911;                     // 增益非法故障码 / illegal gain fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bBypass := TRUE;                          // 旁路输出 / bypass the output
    fOut := fIn;                              // 直通 / straight through
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 7｜时间常数域钳位（超上限只钳位并留信息码）/ segment 7, time constant domain clamp
fLeadEff := DINT_TO_REAL(TIME_TO_DINT(tLeadTime)) / DL_LL_MS_PER_S; // 超前时间换算为秒 [s] / lead time in seconds [s]
fLagEff := DINT_TO_REAL(TIME_TO_DINT(tLagTime)) / DL_LL_MS_PER_S;   // 滞后时间换算为秒 [s] / lag time in seconds [s]
nDtMs := TIME_TO_DINT(tSampleTime);           // 采样周期取整数毫秒 [ms] / sample time in integer milliseconds [ms]
tTsSec := DINT_TO_REAL(nDtMs) / DL_LL_MS_PER_S; // 采样周期换算为秒，除子为常量 [s] / sample time in seconds, divisor is a constant [s]
IF fLeadEff < DL_LL_ZERO THEN
    fLeadEff := DL_LL_ZERO;                   // 超前时间为负无物理意义 / a negative lead time has no physical meaning
    eErr := 16#0002_2901;                     // 信息级：已钳位 / info level, clamped
END_IF
IF fLeadEff > (DINT_TO_REAL(TIME_TO_DINT(DL_LL_LEAD_MAX)) / DL_LL_MS_PER_S) THEN
    fLeadEff := DINT_TO_REAL(TIME_TO_DINT(DL_LL_LEAD_MAX)) / DL_LL_MS_PER_S; // 超前时间超上限钳位 [s] / clamp the lead time at its upper bound [s]
    eErr := 16#0002_2901;                     // 信息级：已钳位 / info level, clamped
END_IF
IF fLagEff > (DINT_TO_REAL(TIME_TO_DINT(DL_LL_LAG_MAX)) / DL_LL_MS_PER_S) THEN
    fLagEff := DINT_TO_REAL(TIME_TO_DINT(DL_LL_LAG_MAX)) / DL_LL_MS_PER_S; // 滞后时间超上限钳位 [s] / clamp the lag time at its upper bound [s]
    eErr := 16#0002_2901;                     // 信息级：已钳位 / info level, clamped
END_IF
tLeadSec := fLeadEff;                         // 记录生效超前时间 [s] / record the effective lead time [s]
tLagSec := fLagEff;                           // 记录生效滞后时间 [s] / record the effective lag time [s]

// 段 8｜输出限幅参数域钳位（0 或负值会让输出恒 0）/ segment 8, output limit clamp
fLimitEff := fOutLimit;                       // 取入参副本 / copy the input
IF (fLimitEff <> fLimitEff) OR (fLimitEff < DL_FLOAT_EPS) THEN
    fLimitEff := DL_LL_GAIN_MAX;              // 非法限幅退回常量上限 / fall back to the constant bound
    eErr := 16#0002_2901;                     // 信息级：限幅参数已收敛 / info level, the limit was converged
END_IF

// 段 9｜在线改参检测（逐项比对，命中即重算系数并保留历史状态）/ segment 9, online parameter change detection
bParamChg := (ABS(fGain - fPrevK) > DL_FLOAT_EPS)
          OR (ABS(tLeadSec - fPrevTl) > DL_FLOAT_EPS)
          OR (ABS(tLagSec - fPrevTg) > DL_FLOAT_EPS)
          OR (ABS(tTsSec - fPrevTs) > DL_FLOAT_EPS); // 改参判定 / parameter change detection
IF bParamChg THEN
    fA0 := DL_LL_TWO * tLagSec / tTsSec + DL_LL_ONE; // 归一化分母 a0 = 2·T_lag/Ts + 1 / normalisation denominator
    IF ABS(fA0) <= DL_LL_MICRO THEN
        eErr := 16#0002_2910;                 // 分母近零，离散化不可用（前置防零）/ the denominator is near zero, the discretisation is unusable
        bError := TRUE;                       // 置故障标志 / raise the error flag
        bBypass := TRUE;                      // 旁路输出 / bypass the output
        fOut := fIn;                          // 直通 / straight through
        RETURN;                               // 故障级提前返回，绝不裸除 / early return, never divide blindly
    END_IF
    fB0 := fGain * (DL_LL_TWO * tLeadSec / tTsSec + DL_LL_ONE) / fA0; // 前向零次系数 / feedforward zero-order coefficient
    fB1 := fGain * (DL_LL_ONE - DL_LL_TWO * tLeadSec / tTsSec) / fA0; // 前向一次系数 / feedforward first-order coefficient
    fA1 := (DL_LL_ONE - DL_LL_TWO * tLagSec / tTsSec) / fA0;          // 反馈一次系数 / feedback first-order coefficient
    fPrevK := fGain;                          // 记录本拍增益 / remember the gain
    fPrevTl := tLeadSec;                      // 记录本拍超前时间 / remember the lead time
    fPrevTg := tLagSec;                       // 记录本拍滞后时间 / remember the lag time
    fPrevTs := tTsSec;                        // 记录本拍采样周期 / remember the sample time
    IF uCoeffRev < DL_LL_CNT_MAX THEN
        uCoeffRev := uCoeffRev + 1;           // 重算次数饱和加一 / saturating recompute counter
    END_IF
    IF eErr = 0 THEN
        eErr := 16#0002_2901;                 // 信息级：在线改参已重算系数，状态保留 / info level, coefficients recomputed, state kept
    END_IF
    // 历史状态 fX1 / fY1 不清零：改参瞬间无扰，避免输出台阶冲击执行器 / the history is deliberately kept, so a parameter change causes no step
END_IF

// 段 10｜输入非有限闸：输出保持末次有效，且不旁路（旁路会把毒值注入执行器）/ segment 10, non-finite input gate
IF (fIn <> fIn) OR (fIn > DL_LL_INF_GUARD) OR (fIn < -DL_LL_INF_GUARD) THEN
    eErr := 16#0002_2911;                     // 输入非有限故障码 / non-finite input fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    RETURN;                                   // 保持末次 fOut，绝不直通 / hold the last output, never pass the poison value through
END_IF

// 段 11｜复位沿清内部状态（在运算之前生效）/ segment 11, reset clears the internal state
IF fbTrigReset.Q THEN
    fX1 := DL_LL_ZERO;                        // 清输入历史 / clear the input history
    fY1 := DL_LL_ZERO;                        // 清输出历史 / clear the output history
END_IF

// 段 12｜直接 I 型差分式（两状态量，系数已归一化）/ segment 12, direct form I difference equation
fOut := fB0 * fIn + fB1 * fX1 - fA1 * fY1;    // y = b0·x + b1·x1 − a1·y1 [用户单位] / the difference equation [user unit]

// 段 13｜结果非有限复检（此时 fY1 仍是上一拍有效输出，可安全回退）/ segment 13, non-finite recheck before the state shift
IF (fOut <> fOut) OR (fOut > DL_LL_INF_GUARD) OR (fOut < -DL_LL_INF_GUARD) THEN
    eErr := 16#0002_2911;                     // 结果非有限，按输入故障同码处理 / a non-finite result shares the input fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    fOut := fY1;                              // 回退到上一拍有效输出（位移尚未发生）/ fall back to the previous valid output, the shift has not happened yet
    RETURN;                                   // 出口 / exit
END_IF
IF fOut > fLimitEff THEN
    fOut := fLimitEff;                        // 正向限幅 / clamp the positive side
    bSaturated := TRUE;                       // 标记饱和 / flag the saturation
    eErr := 16#0002_2901;                     // 信息级：输出限幅生效 / info level, the output limit is active
ELSIF fOut < -fLimitEff THEN
    fOut := -fLimitEff;                       // 负向限幅 / clamp the negative side
    bSaturated := TRUE;                       // 标记饱和 / flag the saturation
    eErr := 16#0002_2901;                     // 同一业务语义复用同一信息码 / the same semantics reuses the same info id
END_IF

// 段 15｜状态位移（顺序不可颠倒：运算与限幅全部结束后才移）/ segment 15, state shift at the very end
fX1 := fIn;                                   // 记录本拍输入 / remember this cycle input
fY1 := fOut;                                  // 记录本拍输出 / remember this cycle output
END_FUNCTION_BLOCK
