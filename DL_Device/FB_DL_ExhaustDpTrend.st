(*
  FB_DL_ExhaustDpTrend  —  尾气管路压差趋势监视与堵塞预警 / Exhaust line differential-pressure trend and clog warning
  分类 Category : DL_Device
  码位 Code     : 16#03_2_08
  版本 Version  : 1.0.0
  溯源 Source   : LGF Measurement 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 尾气前后压差滑动窗统计（复用 FB_DL_SignalStatistics）；
                  2) 周期末均值快照对比折算趋势 [kPa/天]；
                  3) 堵塞预警分级（预警级带迟滞，严重级持续确认升级）。
  边界 Boundary : ① 风机停机时冻结趋势累计（禁把停机零流量当堵塞）；
                  ② 压差无效剔除并置掩码；
                  ③ 趋势窗样本不足不出结论；
                  ④ 预警阈值带迟滞且解除可达；
                  ⑤ 输出三行同向：压差均值 → 趋势斜率 → 堵塞预警。
  依赖 Depends  : FB_DL_SignalStatistics × 2（当前窗 / 快照窗，每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0308 故障级：组态非法（周期/门限/迟滞 <= 0）
    16#0002_0318 故障级：严重堵塞（压差持续超严重门限，锁存需复位）
    16#0002_0328 信息级：压差无效剔除 / 样本不足不出结论 / 风机停机趋势冻结（不置 bError）
*)

TYPE E_DL_ExtPhase :
(
    eIdle  := 0,  // 空闲 / Idle
    eWatch := 10, // 压差趋势监视 / DP trend watching
    eFault := 90  // 组态故障锁定 / Configuration fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_ExhaustDpTrend
VAR_INPUT
    bEnable       : BOOL;                           // 总使能，FALSE 回空闲 / Master enable
    bReset        : BOOL;                           // 复位，上升沿清故障 / Reset, clears fault
    fDpKpa        : REAL;                           // 尾气前后压差 [kPa] / Exhaust differential pressure [kPa]
    bFanRunning   : BOOL;                           // 风机运行反馈 / Fan running feedback
    uPeriodMin    : UINT := 60;                     // 趋势统计周期 [min]，域 > 0 / Trend period [min]
    fWarnKpa      : REAL := 2.5;                    // 堵塞预警门限 [kPa] / Clog warning threshold [kPa]
    fTripKpa      : REAL := 4.0;                    // 严重堵塞门限 [kPa] / Severe clog threshold [kPa]
    fHystKpa      : REAL := 0.3;                    // 预警迟滞 [kPa]，域 > 0 / Warning hysteresis [kPa]
    uTripConfirm  : UINT := 10;                     // 严重堵塞确认拍数 [拍] / Severe confirm scans
    fTaskCycle    : REAL := 1.0;                    // 任务周期 [s]，域 > 0 / Task cycle [s]
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fDpMeanKpa    : REAL;                           // 压差滑动均值 [kPa] / DP window mean [kPa]
    fTrendKpaDay  : REAL;                           // 趋势斜率 [kPa/天] / Trend slope [kPa/day]
    bClogWarn     : BOOL;                           // 堵塞预警标志（带迟滞）/ Clog warning flag
    bTrendValid   : BOOL;                           // 趋势结论有效 / Trend conclusion valid
    abMask        : BOOL;                           // 本拍压差无效掩码 / Invalid mask this scan
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code
    eStateOut     : E_DL_ExtPhase;                  // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_ExtPhase := E_DL_ExtPhase.eIdle;  // 内部状态 / Internal state
    fbStatNow     : FB_DL_SignalStatistics;         // 当前窗统计实例（无条件调用）/ Current window statistics
    fbStatOld     : FB_DL_SignalStatistics;         // 快照窗统计实例（无条件调用）/ Snapshot statistics
    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge
    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid
    bDpOk         : BOOL;                           // 压差本拍有效 / DP valid this scan
    bFrozen       : BOOL;                           // 冻结合成（无效/停机）/ Frozen aggregate
    bPeriodEdge   : BOOL;                           // 周期末沿 / Period end edge
    fAccumSec     : REAL;                           // 周期累计秒 [s] / Period accumulated seconds
    fMeanNowKpa   : REAL;                           // 当前窗均值 [kPa] / Current mean [kPa]
    fMeanOldKpa   : REAL;                           // 上一周期均值快照 [kPa] / Snapshot mean [kPa]
    bWarnUp       : BOOL;                           // 预警迟滞状态（持有）/ Warning hysteresis state
    uTripCnt      : UINT;                           // 严重堵塞确认计数 [拍] / Severe confirm counter
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_EXT_INFMAX : REAL := 1.0E30;                 // 压差有限值幅值上限 [kPa] / DP finite bound [kPa]
    DL_EXT_MINWIN : INT := 8;                       // 趋势窗最小样本数 [样本] / Minimum window samples
END_VAR

(* === 段 0 · 实例刷新 === *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸 === *)
bCfgOk := (UINT_TO_REAL(uPeriodMin) > fEps)       // 周期正域
          AND (fWarnKpa > fEps) AND (fTripKpa > fWarnKpa + fHystKpa)  // 门限不倒置且迟滞带不相交
          AND (fHystKpa > fEps) AND (fTaskCycle > fEps)
          AND (fWarnKpa = fWarnKpa) AND (fTripKpa = fTripKpa);  // NaN 自反
IF NOT bCfgOk THEN
    uFault := 16#0002_0308;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（解除路径可达）
    bWarnUp := FALSE;                             // 预警迟滞复位
    uTripCnt := UINT#0;                           // 严重确认计数复位
    fAccumSec := 0.0;                             // 周期累计清零
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零
bDpOk := (fDpKpa = fDpKpa) AND (fDpKpa >= 0.0) AND (fDpKpa < DL_EXT_INFMAX);  // 压差 NaN 自反 + 非负域闸
abMask := NOT bDpOk;                              // 无效掩码输出
bFrozen := (NOT bDpOk) OR (NOT bFanRunning);      // 停机/无效冻结（禁把停机零流量当堵塞）
IF bFrozen AND bEnable THEN
    uInfo := 16#0002_0328;                        // 信息级：无效剔除或停机趋势冻结
END_IF

(* === 段 2 · 周期累计（先于统计实例，保快照沿同拍一致）=== *)
bPeriodEdge := FALSE;                             // 周期沿本拍重算
IF (NOT bFrozen) AND bEnable AND (uFault = 16#0000) THEN
    fAccumSec := fAccumSec + fTaskCycle;          // 非冻结拍累计
    IF fAccumSec >= UINT_TO_REAL(uPeriodMin) * 60.0 THEN
        bPeriodEdge := TRUE;                      // 周期末沿
        fAccumSec := 0.0;                         // 累计清零开新周期
    END_IF
END_IF

(* === 段 3 · 统计实例（无条件调用）与趋势折算 === *)
fbStatNow(fIn := fDpKpa,                          // 当前窗统计
          bSample := bDpOk AND bFanRunning AND (NOT bFrozen),   // 冻结拍不采（停机零流量不进窗）
          nWindow := 32,                          // 统计窗 32 样本
          bClear := rtrReset.Q);                  // 复位沿清窗
fbStatOld(fIn := fMeanNowKpa,                     // 快照窗统计（输入为均值快照）
          bSample := bPeriodEdge,                 // 周期末沿采快照
          nWindow := 8,                           // 快照窗 8 周期
          bClear := rtrReset.Q);
IF bPeriodEdge THEN
    fMeanOldKpa := fMeanNowKpa;                   // 周期末均值快照
END_IF
fDpMeanKpa := 0.0;                                // 均值缺省 0
fTrendKpaDay := 0.0;                              // 趋势缺省 0
bTrendValid := FALSE;                             // 结论缺省无效
IF fbStatNow.bStatValid AND (fbStatNow.nCount >= DL_EXT_MINWIN) THEN
    fDpMeanKpa := fbStatNow.fMean;                // 当前窗均值
    IF fbStatOld.bValid AND (fbStatOld.nCount >= 2) THEN
        fTrendKpaDay := (fDpMeanKpa - fMeanOldKpa) / (UINT_TO_REAL(uPeriodMin) / 1440.0);   // 斜率 kPa/天（分母常量防零）
        bTrendValid := TRUE;                      // 趋势结论有效
    END_IF
ELSE
    uInfo := 16#0002_0328;                        // 信息级：样本不足不出结论
END_IF

(* === 段 4 · 分级预警（预警带迟滞 / 严重持续确认升级）=== *)
IF fDpMeanKpa >= fWarnKpa THEN
    bWarnUp := TRUE;                              // 越预警门限置迟滞状态
ELSIF fDpMeanKpa < fWarnKpa - fHystKpa THEN
    bWarnUp := FALSE;                             // 回差带内解除（路径可达）
END_IF
bClogWarn := bWarnUp;                             // 预警出口
IF bDpOk AND (fDpKpa >= fTripKpa) THEN
    uTripCnt := uTripCnt + UINT#1;                // 严重堵塞确认计数
    IF uTripCnt >= uTripConfirm THEN
        uFault := 16#0002_0318;                   // 故障级：严重堵塞（锁存）
    END_IF
ELSE
    uTripCnt := UINT#0;                           // 未超严重门限计数归零
END_IF

(* === 段 5 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_ExtPhase.eIdle :
    IF uFault <> 16#0000 THEN
        _eState := E_DL_ExtPhase.eFault;          // 故障优先
    ELSIF bEnable AND bCfgOk THEN
        _eState := E_DL_ExtPhase.eWatch;          // 进监视相
    END_IF

E_DL_ExtPhase.eWatch :
    IF (uFault <> 16#0000) OR (NOT bEnable) THEN
        _eState := E_DL_ExtPhase.eFault;          // 故障/失能转出
    END_IF

E_DL_ExtPhase.eFault :
    IF uFault = 16#0000 THEN
        _eState := E_DL_ExtPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_ExtPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_0308;                       // 故障级：相 ID 越界复用组态码段
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
