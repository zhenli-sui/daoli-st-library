(*

  FB_DL_ChillerApproachTrend  —  冷机逼近度趋势诊断与性能衰减预警 / Chiller approach trend and degradation early warning

  分类 Category : DL_Process

  码位 Code     : 16#06_0_95

  版本 Version  : 1.0.0

  溯源 Source   : OSCAT Building 暖通语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码

  功能 Function : 1) 逼近度 = 蒸发器出水温度 − 饱和蒸发温度 [K]，滑动窗统计（复用 FB_DL_SignalStatistics）；

                  2) 趋势 = 相邻统计周期均值差折算 K/天，周期末快照对比；

                  3) 性衰预警：趋势斜率超门限带迟滞置预警，解除可达。

  边界 Boundary : ① 逼近度计算分母（换热量代理量 = 负荷率）近零时改绝对差判据（防除零）；

                  ② 负荷率低于下限冻结趋势累计并置 bFrozen（禁低负荷数据污染趋势）；

                  ③ 趋势窗样本 < 最小值不出结论；

                  ④ 预警阈值带迟滞且解除可达；

                  ⑤ 输出三行同向：逼近度 → 趋势斜率 → 预警标志。

  依赖 Depends  : FB_DL_SignalStatistics × 2（当前窗 / 上一窗均值，每拍无条件调用）



  码表 Error codes（本件子码步进 16#30 · 本格 95 与既有 9X 子码段冲突，错位至 C5/D5 避让）:

    16#0002_06C5 故障级：组态非法（周期/门限 <= 0 / 负荷率下限域非法 / 预警迟滞 <= 0）

    16#0002_06D5 故障级：相 ID 越界（枚举兜底路径）

    16#0002_06B5 信息级：输入无效本拍冻结 / 趋势窗样本不足不出结论（不置 bError）

*)



TYPE E_DL_CatPhase :

(

    eIdle   := 0,  // 空闲 / Idle

    eWatch  := 10, // 逼近度监视与趋势累计 / Approach watching and trend accumulation

    eFault  := 90  // 组态故障锁定 / Configuration fault locked

);

END_TYPE



FUNCTION_BLOCK FB_DL_ChillerApproachTrend

VAR_INPUT

    bEnable       : BOOL;                           // 总使能，FALSE 回空闲 / Master enable

    bReset        : BOOL;                           // 复位，上升沿清组态故障 / Reset, clears fault

    fChwOutC      : REAL;                           // 蒸发器出水温度 [°C] / Chilled water leaving temp [degC]

    fSatEvapC     : REAL;                           // 饱和蒸发温度 [°C] / Saturated evaporating temp [degC]

    fLoadRatePct  : REAL;                           // 负荷率 [%]（换热量代理量）/ Load rate [%], heat-transfer proxy

    fLoadLoPct    : REAL := 30.0;                   // 负荷率冻结下限 [%]，域 > 0 / Load rate freeze floor [%]

    uPeriodMin    : UINT := 60;                     // 趋势统计周期 [min]，域 > 0 / Trend period [min]

    fWarnKPerDay  : REAL := 0.5;                    // 预警斜率门限 [K/天]，域 > 0 / Warning slope threshold [K/day]

    fHystKPerDay  : REAL := 0.1;                    // 预警迟滞 [K/天]，域 > 0 / Warning hysteresis [K/day]

    fAbsDiffMaxK  : REAL := 6.0;                    // 低负荷绝对差判据门限 [K] / Low-load absolute-difference limit [K]

    fTaskCycle    : REAL := 1.0;                    // 任务周期 [s]，域 > 0 / Task cycle [s]

    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance

END_VAR

VAR_OUTPUT

    fApproachK    : REAL;                           // 当前逼近度 [K] / Current approach [K]

    fTrendKPerDay : REAL;                           // 滑动趋势 [K/天] / Sliding trend [K/day]

    bDegradWarn   : BOOL;                           // 性衰预警标志（带迟滞）/ Degradation warning flag

    bFrozen       : BOOL;                           // 低负荷/输入无效冻结标志 / Frozen by low load or invalid input

    bTrendValid   : BOOL;                           // 趋势结论有效（窗样本充足）/ Trend conclusion valid

    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag

    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code

    eStateOut     : E_DL_CatPhase;                  // 状态机当前态，段尾单点映射 / Phase mapped at tail

END_VAR

VAR

    _eState       : E_DL_CatPhase := E_DL_CatPhase.eIdle;  // 内部状态 / Internal state

    fbStatNow     : FB_DL_SignalStatistics;         // 当前窗统计实例（无条件调用）/ Current window statistics

    fbStatOld     : FB_DL_SignalStatistics;         // 上一周期快照统计实例（无条件调用）/ Previous period statistics

    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge

    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid

    bInOk         : BOOL;                           // 双温度输入本拍有效 / Both temperatures valid

    bLoadOk       : BOOL;                           // 负荷率本拍有效 / Load rate valid

    bPeriodEdge   : BOOL;                           // 周期末沿 / Period end edge

    fAccumSec     : REAL;                           // 周期累计秒 [s]（非冻结拍累计）/ Period accumulated seconds

    fMeanNowK     : REAL;                           // 当前窗逼近度均值 [K] / Current window mean [K]

    fMeanOldK     : REAL;                           // 上一周期均值快照 [K] / Previous period mean snapshot [K]

    fPeriodDay    : REAL;                           // 周期折算天 [天] / Period in days

    bSlopeUp      : BOOL;                           // 斜率越门限（电平，迟滞状态持有）/ Slope over threshold, held

    uFault        : UDINT;                          // 锁存故障码 / Latched fault code

    uInfo         : UDINT;                          // 信息级码 / Information code

END_VAR

VAR CONSTANT

    DL_CAT_INFMAX : REAL := 1.0E30;                 // 温度有限值幅值上限 [°C] / Temperature finite bound [degC]

    DL_CAT_MINWIN : INT := 8;                       // 趋势窗最小样本数 [样本] / Minimum window samples

END_VAR



(* === 段 0 · 实例刷新 === *)

rtrReset(CLK := bReset);                          // 每拍刷新复位沿



(* === 段 1 · 组态闸 === *)

bCfgOk := (UINT_TO_REAL(uPeriodMin) > fEps)               // 周期正域

          AND (fWarnKPerDay > fEps) AND (fHystKPerDay > fEps)

          AND (fLoadLoPct > fEps) AND (fLoadLoPct < 100.0)      // 负荷率下限域

          AND (fTaskCycle > fEps)

          AND (fWarnKPerDay = fWarnKPerDay) AND (fAbsDiffMaxK = fAbsDiffMaxK);  // NaN 自反

IF NOT bCfgOk THEN

    uFault := 16#0002_06C5;                       // 故障级：组态非法

END_IF

IF rtrReset.Q AND bCfgOk THEN

    uFault := 16#0000;                            // 复位沿清锁存（解除路径可达）

    bDegradWarn := FALSE;                         // 预警同步复位

    bSlopeUp := FALSE;                            // 迟滞状态复位

    fAccumSec := 0.0;                             // 周期累计清零

END_IF

uInfo := 16#0000;                                 // 信息码每拍清零

bInOk := (fChwOutC = fChwOutC) AND (ABS(fChwOutC) < DL_CAT_INFMAX)

         AND (fSatEvapC = fSatEvapC) AND (ABS(fSatEvapC) < DL_CAT_INFMAX);  // 双温度 NaN 自反 + 幅值闸

bLoadOk := (fLoadRatePct = fLoadRatePct) AND (fLoadRatePct >= 0.0) AND (fLoadRatePct <= 100.0);  // 负荷率域闸

bFrozen := (NOT bInOk) OR (NOT bLoadOk) OR (bLoadOk AND (fLoadRatePct < fLoadLoPct));  // 低负荷/无效冻结（禁污染趋势）



(* === 段 2 · 逼近度折算 === *)

fApproachK := 0.0;                                // 逼近度缺省 0

IF bInOk THEN

    fApproachK := fChwOutC - fSatEvapC;           // 逼近度 = 出水 − 饱和蒸发 [K]

END_IF

fbStatNow(fIn := fApproachK,                      // 当前窗统计（无条件调用）

          bSample := bInOk AND (NOT bFrozen),     // 冻结拍不采（低负荷数据不进窗）

          nWindow := 32,                          // 统计窗 32 样本

          bClear := rtrReset.Q);                    // 复位沿清窗

fbStatOld(fIn := fMeanNowK,                       // 上一周期统计（输入为快照均值）

          bSample := bPeriodEdge,                 // 周期末沿采一个快照

          nWindow := 8,                           // 快照窗 8 个周期

          bClear := rtrReset.Q);

IF bPeriodEdge THEN

    fMeanOldK := fMeanNowK;                       // 周期末均值快照

END_IF



(* === 段 3 · 趋势折算 === *)

bPeriodEdge := FALSE;                            // 周期沿本拍重算

IF (NOT bFrozen) AND bEnable AND (uFault = 16#0000) THEN

    fAccumSec := fAccumSec + fTaskCycle;          // 非冻结拍累计时间（暂停语义）

    IF fAccumSec >= UINT_TO_REAL(uPeriodMin) * 60.0 THEN

        bPeriodEdge := TRUE;                      // 周期末沿

        fAccumSec := 0.0;                         // 累计清零开新周期

    END_IF

END_IF

fMeanNowK := 0.0;                                 // 均值缺省 0

bTrendValid := FALSE;                             // 结论缺省无效

fTrendKPerDay := 0.0;                             // 趋势缺省 0

IF fbStatNow.bStatValid AND (fbStatNow.nCount >= DL_CAT_MINWIN) THEN

    fMeanNowK := fbStatNow.fMean;                 // 当前窗均值（样本充足才取）

    IF fbStatOld.bValid AND (fbStatOld.nCount >= 2) THEN

        fPeriodDay := UINT_TO_REAL(uPeriodMin) / 1440.0;  // 周期折算天（分母常量无除零风险）

        fTrendKPerDay := (fMeanNowK - fMeanOldK) / fPeriodDay;   // 斜率折算 K/天

        bTrendValid := TRUE;                      // 趋势结论有效

    END_IF

ELSE

    uInfo := 16#0002_06B5;                        // 信息级：趋势窗样本不足不出结论

END_IF



(* === 段 4 · 预警判定（分母近零改绝对差判据 + 迟滞）=== *)

IF bTrendValid THEN

    IF fPeriodDay > fEps THEN

        IF ABS(fTrendKPerDay) >= fWarnKPerDay THEN

            bSlopeUp := TRUE;                     // 斜率越门限（迟滞置位）

        ELSIF ABS(fTrendKPerDay) < fWarnKPerDay - fHystKPerDay THEN

            bSlopeUp := FALSE;                    // 回差带内解除（解除路径可达）

        END_IF

        bDegradWarn := bSlopeUp;                  // 预警出口

    ELSE

        (* 分母近零防御：改绝对差判据 *)

        bDegradWarn := ABS(fMeanNowK - fMeanOldK) > fAbsDiffMaxK;   // 绝对差判据（防除零）

    END_IF

ELSE

    bDegradWarn := bDegradWarn AND bTrendValid;   // 结论无效不新增预警（保持至周期更新）

END_IF



(* === 段 5 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)

CASE _eState OF

E_DL_CatPhase.eIdle :

    IF uFault <> 16#0000 THEN

        _eState := E_DL_CatPhase.eFault;          // 故障优先

    ELSIF bEnable AND bCfgOk THEN

        _eState := E_DL_CatPhase.eWatch;          // 进监视相

    END_IF



E_DL_CatPhase.eWatch :

    IF (uFault <> 16#0000) OR (NOT bEnable) THEN

        _eState := E_DL_CatPhase.eFault;          // 故障/失能转出

    END_IF



E_DL_CatPhase.eFault :

    IF uFault = 16#0000 THEN

        _eState := E_DL_CatPhase.eIdle;           // 解锁回空闲

    END_IF



ELSE

    _eState := E_DL_CatPhase.eFault;              // 非法状态拦截

    uFault := 16#0002_06D5;                       // 故障级：相 ID 越界

END_CASE



(* === 段 6 · 输出映射 === *)

bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）

IF bError THEN

    uErrorId := uFault;                           // 故障级优先上报

ELSE

    uErrorId := uInfo;                            // 否则上报信息级码

END_IF

eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）

END_FUNCTION_BLOCK

