(*
  FB_DL_HydronicDeltaTGuard  —  水系统大/小温差失衡诊断 / Hydronic delta-T imbalance diagnostic guard
  分类 Category : DL_Process
  码位 Code     : 16#06_0_94
  版本 Version  : 1.0.0
  溯源 Source   : OSCAT Building 暖通语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 供/回水温差带判定：大温差（低流量征兆）/ 小温差（旁通泄漏征兆）/ 正常三档；
                  2) 旁通泄漏判据：旁通开度大且温差小持续 N 分钟（确认窗）才判泄漏；
                  3) 判据全部带迟滞防抖（回差带电平判定）。
  边界 Boundary : ① 两温度任一无效：冻结判定保持上次输出，不塞伪值；
                  ② 温差 = 0 邻域（|ΔT| < 0.5 K）判「无有效流量」而非除零算比率；
                  ③ 大/小温差判据带迟滞防抖；
                  ④ 失衡解除路径自证可达（恢复窗内即解除，泄漏需旁通关小确认）；
                  ⑤ 输出三行同向：温差档位 → 泄漏标志 → 诊断码。
  依赖 Depends  : FC_DL_Hysteresis（回差带判定，函数调用，状态由调用方持有）

  码表 Error codes（本件子码步进 16#30 · 本格 94 与既有 9X 子码段冲突，错位至 C4/D4 避让）:
    16#0002_06C4 故障级：组态非法（温差门限倒置 / 迟滞 <= 0 / 确认窗 <= 0 / 旁通门限域非法）
    16#0002_06D4 故障级：相 ID 越界（枚举兜底路径）
    16#0002_06B4 信息级：温度无效判定冻结 / 无有效流量(|ΔT|<0.5K)档（不置 bError）
*)

TYPE E_DL_HdtBand :
(
    eNormal   := 0,  // 温差正常 / Normal delta-T
    eBigDt    := 10, // 大温差（低流量征兆）/ Large delta-T, low flow sign
    eSmallDt  := 20, // 小温差（旁通泄漏征兆）/ Small delta-T, bypass leak sign
    eNoFlow   := 30, // 无有效流量（|ΔT| < 0.5 K）/ No effective flow
    eFrozen   := 40  // 温度无效冻结 / Frozen by invalid temperature
);
END_TYPE

TYPE E_DL_HdtPhase :
(
    eIdle  := 0,   // 空闲 / Idle
    eWatch := 10,  // 温差带监视 / Delta-T band watching
    eFault := 90   // 组态故障锁定 / Configuration fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_HydronicDeltaTGuard
VAR_INPUT
    bEnable       : BOOL;                           // 总使能，FALSE 回空闲 / Master enable
    bReset        : BOOL;                           // 复位，上升沿清组态故障 / Reset, clears fault
    fSupplyC      : REAL;                           // 供水温度 [°C] / Supply water temperature [degC]
    fReturnC      : REAL;                           // 回水温度 [°C] / Return water temperature [degC]
    fBypassPct    : REAL;                           // 旁通阀开度 [%] / Bypass valve opening [%]
    fBigDtK       : REAL := 12.0;                   // 大温差门限 [K]（超过判大温差）/ Large delta-T threshold [K]
    fSmallDtK     : REAL := 4.0;                    // 小温差门限 [K]（低于判小温差）/ Small delta-T threshold [K]
    fHystK        : REAL := 1.0;                    // 迟滞回差 [K]，域 > 0 / Hysteresis band [K]
    fBypassHiPct  : REAL := 60.0;                   // 旁通开度门限 [%] / Bypass opening threshold [%]
    uLeakMin      : UINT := 10;                     // 泄漏确认窗 [min] / Leak confirm window [min]
    fTaskCycle    : REAL := 1.0;                    // 任务周期 [s]，域 > 0 / Task cycle [s]
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    eBandOut      : E_DL_HdtBand;                   // 温差档位出口 / Delta-T band output
    fDeltaTK      : REAL;                           // 当前温差 [K] / Current delta-T [K]
    bBypassLeak   : BOOL;                           // 旁通泄漏标志（确认窗后锁存）/ Bypass leak flag, latched after confirm
    bFrozen       : BOOL;                           // 判定冻结标志 / Judgment frozen flag
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code
    eStateOut     : E_DL_HdtPhase;                  // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_HdtPhase := E_DL_HdtPhase.eIdle;  // 内部状态 / Internal state
    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge
    bHystBig      : BOOL;                           // 大温差迟滞状态（FC_DL_Hysteresis 持有量）/ Big-delta-T hysteresis state
    bHystSmall    : BOOL;                           // 小温差迟滞状态 / Small-delta-T hysteresis state
    tonLeak       : TON;                            // 泄漏确认窗定时器 / Leak confirm window timer
    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid
    bTempOk       : BOOL;                           // 双温度本拍有效 / Both temperatures valid
    bBypassOk     : BOOL;                           // 旁通开度本拍有效 / Bypass opening valid
    fUpInfo       : REAL;                           // 迟滞函数上阈值回读 [K] / Hysteresis upper trip readback [K]
    fLoInfo       : REAL;                           // 迟滞函数下阈值回读 [K] / Hysteresis lower trip readback [K]
    uErrH1        : UDINT;                          // 迟滞函数错误码回读 / Hysteresis error readback
    uErrH2        : UDINT;                          // 第二迟滞错误码回读 / Second hysteresis error readback
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_HDT_INFMAX : REAL := 1.0E30;                 // 温度有限值幅值上限 [°C] / Temperature finite bound [degC]
    DL_HDT_NOFLOW : REAL := 0.5;                    // 无有效流量邻域 [K] / No-effective-flow band [K]
END_VAR

(* === 段 0 · 实例刷新 === *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸 === *)
bCfgOk := (fBigDtK > fSmallDtK + fHystK)          // 门限不倒置且迟滞带不相交
          AND (fHystK > fEps) AND (fTaskCycle > fEps)
          AND (fBypassHiPct > fEps) AND (fBypassHiPct < 100.0)   // 旁通门限域
          AND (uLeakMin >= UINT#1)                // 确认窗下限
          AND (fBigDtK = fBigDtK) AND (fSmallDtK = fSmallDtK);   // NaN 自反
IF NOT bCfgOk THEN
    uFault := 16#0002_06C4;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（解除路径可达）
    bBypassLeak := FALSE;                         // 泄漏标志同步复位
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零
bTempOk := (fSupplyC = fSupplyC) AND (ABS(fSupplyC) < DL_HDT_INFMAX)
           AND (fReturnC = fReturnC) AND (ABS(fReturnC) < DL_HDT_INFMAX);  // 双温度 NaN 自反 + 幅值闸
bBypassOk := (fBypassPct = fBypassPct) AND (fBypassPct >= 0.0) AND (fBypassPct <= 100.0);  // 旁通域闸

(* === 段 2 · 温差折算与迟滞档位判定 === *)
fDeltaTK := 0.0;                                  // 温差缺省 0
eBandOut := E_DL_HdtBand.eFrozen;                 // 档位缺省冻结（无效时保持语义由下段覆盖）
IF bTempOk THEN
    fDeltaTK := fSupplyC - fReturnC;              // 温差 = 供 − 回 [K]
    IF ABS(fDeltaTK) < DL_HDT_NOFLOW THEN
        eBandOut := E_DL_HdtBand.eNoFlow;         // 零邻域：无有效流量档（不除零算比率）
        uInfo := 16#0002_06B4;                    // 信息级：无有效流量档
        bHystBig := FALSE;                        // 迟滞状态同步复位
        bHystSmall := FALSE;
    ELSE
        FC_DL_Hysteresis(fIn := fDeltaTK,         // 大温差迟滞判定（状态由本件持有）
                         fThreshold := fBigDtK,   // 设定点 = 大温差门限
                         fHysteresis := fHystK,   // 回差带
                         bState := bHystBig,      // 持有状态回传（IN_OUT）
                         fUpperTrip => fUpInfo, fLowerTrip => fLoInfo,
                         uErrorId => uErrH1);     // 输出取值用 => 显式接收
        FC_DL_Hysteresis(fIn := fDeltaTK,         // 小温差迟滞判定
                         fThreshold := fSmallDtK,
                         fHysteresis := fHystK,
                         bState := bHystSmall,
                         fUpperTrip => fUpInfo, fLowerTrip => fLoInfo,
                         uErrorId => uErrH2);
        IF bHystBig THEN
            eBandOut := E_DL_HdtBand.eBigDt;      // 大温差档（回差带内保持，防抖）
        ELSIF bHystSmall THEN
            eBandOut := E_DL_HdtBand.eSmallDt;    // 小温差档
        ELSE
            eBandOut := E_DL_HdtBand.eNormal;     // 正常档
        END_IF
    END_IF
ELSE
    (* 温度无效：保持上次档位输出（不塞伪值，冻结标志由段尾映射） *)
    uInfo := 16#0002_06B4;                        // 信息级：温度无效判定冻结
END_IF

(* === 段 3 · 旁通泄漏确认窗（泄漏需持续 N 分钟才判）=== *)
tonLeak(IN := bTempOk AND bBypassOk AND (eBandOut = E_DL_HdtBand.eSmallDt)
             AND (fBypassPct >= fBypassHiPct),    // 小温差 + 旁通大开度同时成立才计时
        PT := REAL_TO_TIME(UINT_TO_REAL(uLeakMin) * 60.0 * 1000.0));   // 确认窗换算 [ms]（UINT 扩宽 REAL 防溢出）
IF tonLeak.Q THEN
    bBypassLeak := TRUE;                          // 确认窗满：泄漏锁存
END_IF
IF bTempOk AND bBypassOk AND ((eBandOut = E_DL_HdtBand.eNormal)
    OR (eBandOut = E_DL_HdtBand.eBigDt) OR (fBypassPct < fBypassHiPct - fEps)) THEN
    bBypassLeak := FALSE;                         // 恢复正常档或旁通关小：解除（路径可达）
END_IF

(* === 段 4 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_HdtPhase.eIdle :
    IF uFault <> 16#0000 THEN
        _eState := E_DL_HdtPhase.eFault;          // 故障优先
    ELSIF bEnable AND bCfgOk THEN
        _eState := E_DL_HdtPhase.eWatch;          // 进监视相
    END_IF

E_DL_HdtPhase.eWatch :
    IF (uFault <> 16#0000) OR (NOT bEnable) THEN
        _eState := E_DL_HdtPhase.eFault;          // 故障/失能转出
    END_IF

E_DL_HdtPhase.eFault :
    IF uFault = 16#0000 THEN
        _eState := E_DL_HdtPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_HdtPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_06D4;                       // 故障级：相 ID 越界
END_CASE
bFrozen := (NOT bTempOk) OR (_eState = E_DL_HdtPhase.eFault);   // 冻结标志段尾单点映射

(* === 段 5 · 输出映射 === *)
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
