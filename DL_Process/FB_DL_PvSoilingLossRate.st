(*
  FB_DL_PvSoilingLossRate  —  组件积灰损失率估算与清洗提醒 / PV soiling loss estimation and cleaning reminder
  分类 Category : DL_Process
  码位 Code     : 16#06_0_85
  版本 Version  : 1.0.0
  溯源 Source   : LGF Measurement 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 仅在「辐照/温度同窗」条件下把性能比样本纳入基线窗口，避免把天气变化当积灰；
                  2) 用窗口均值作为基线、当前性能比相对基线的衰减速率按日折算；
                  3) 衰减速率分母（评估时间窗）先判正域；辐照低于下限时冻结估算并置 bFrozen，禁以低辐照数据外推。
  边界 Boundary : ① 基线在辐照/温度同窗条件下取，同窗外样本不纳入；
                  ② 衰减速率分母时间窗 > 0（防除零），非法即冻结；
                  ③ 辐照低于下限时冻结估算并置 bFrozen，禁低辐照外推；
                  ④ 结论态三行同向：性能比 → 基线 → 冻结/提醒标志。
  依赖 Depends  : FB_DL_SignalStatistics（基线窗口统计，每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0685 故障级：组态非法（辐照下限 <= 0 / 温度带宽 <= 0 / 评估时间窗 <= 0）
    16#0002_0695 故障级：窗口样本数为 0 却进入速率相（枚举/顺序兜底路径）
    16#0002_06A5 信息级：低辐照冻结估算（信息级，不置 bError）
*)

TYPE E_DL_PvSoilPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    eCollect := 10,  // 同窗采样 / Same-window sampling
    eRate    := 20,  // 衰减速率计算 / Decay rate computation
    eAlarm   := 30,  // 清洗提醒 / Cleaning reminder
    eFrozen  := 40,  // 低辐照冻结 / Frozen at low irradiance
    eFault   := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_PvSoilingLossRate
VAR_INPUT
    bEnable        : BOOL;                        // 总使能，FALSE 回空闲 / Master enable
    bSample        : BOOL := TRUE;                // 采样使能 / Sampling enable
    bReset         : BOOL;                        // 复位，上升沿清故障与统计窗 / Reset, clears fault and window
    fPowerKw       : REAL;                        // 组件实测输出功率 [kW]，域 > 0 / Measured module power [kW]
    fPowerRefKw    : REAL := 1.0;                 // 标称峰值功率 [kW]，域 > 0（性能比分母）/ Nameplate peak power [kW]
    fIrradWm2      : REAL;                        // 平面辐照度 [W/m2]，域 0~1500 / Plane-of-array irradiance [W/m2]
    fTempC         : REAL;                        // 组件背板温度 [degC]，域 −40~120 / Module back temperature [degC]
    fIrradMinWm2   : REAL := 400.0;               // 同窗辐照下限 [W/m2]，域 > 0 / Same-window irradiance floor
    fTempBandC     : REAL := 3.0;                 // 同窗温度带宽 [degC]，域 > 0 / Same-window temperature band
    fTempRefC      : REAL := 25.0;                // 同窗温度中心 [degC] / Same-window temperature centre
    fEvalSpanH     : REAL := 24.0;                // 评估时间窗 [h]，域 > 0（速率分母）/ Evaluation span [h]
    fLossAlarmPct  : REAL := 3.0;                 // 损失率清洗门限 [%]，域 0~100 / Soiling loss cleaning limit [%]
    nWindowLen     : INT := 32;                   // 基线窗口样本数 [个]，域 2~64 / Baseline window length
    fEps           : REAL := 1.0E-6;              // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fPrNowPct      : REAL;                        // 当前性能比 [%] / Current performance ratio [%]
    fPrBasePct     : REAL;                        // 基线性能比（窗口均值）[%] / Baseline performance ratio [%]
    fLossPct       : REAL;                        // 积灰损失率 [%] = (基线 − 当前) / 基线 × 100 / Soiling loss [%]
    fDecayPctPerDay : REAL;                       // 衰减速率 [%/天] / Decay rate [percent per day]
    bFrozen        : BOOL;                        // 估算冻结标志（保持型）/ Estimation frozen, held
    bCleanReminder : BOOL;                        // 清洗提醒（保持型）/ Cleaning reminder, held
    bError         : BOOL;                        // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId       : UDINT;                       // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut      : E_DL_PvSoilPhase;            // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState        : E_DL_PvSoilPhase := E_DL_PvSoilPhase.eIdle;  // 内部状态 / Internal state
    rtrReset       : R_TRIG;                      // 复位沿 / Reset edge
    statPr         : FB_DL_SignalStatistics;      // 性能比窗口统计实例（无条件调用）/ PR window statistics
    bCfgOk         : BOOL;                        // 组态合法标志 / Configuration valid
    bWinOk         : BOOL;                        // 同窗条件满足标志 / Same-window condition met
    bIrradOk       : BOOL;                        // 辐照高于下限标志 / Irradiance above floor
    fPrPct         : REAL;                        // 性能比暂存 [%] / Performance ratio buffer [%]
    fLossBuf       : REAL;                        // 损失率暂存 [%] / Loss buffer [%]
    fSpanDay       : REAL;                        // 评估时间窗折算天数 [天] / Evaluation span in days
    uFault         : UDINT;                       // 锁存故障码 / Latched fault code
    uInfo          : UDINT;                       // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_PV_PCTMAX   : REAL := 100.0;               // 百分比满量程 [%] / Full-scale percentage [%]
    DL_PV_HOURDAY  : REAL := 24.0;                // 每日小时数 [h] / Hours per day [h]
    DL_PV_IRRMAX   : REAL := 1500.0;              // 辐照物理域上限 [W/m2] / Irradiance domain high
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸与同窗判据 === *)
bCfgOk := (fPowerRefKw > fEps) AND (fIrradMinWm2 > fEps) AND (fTempBandC > fEps)
          AND (fEvalSpanH > fEps) AND (fPowerRefKw = fPowerRefKw)
          AND (fIrradMinWm2 = fIrradMinWm2) AND (fTempBandC = fTempBandC)
          AND (fEvalSpanH = fEvalSpanH);                          // 含 NaN 自反判据
IF NOT bCfgOk THEN
    uFault := 16#0002_0685;                       // 故障级：组态非法
END_IF
IF rtrReset.Q THEN
    uFault := 16#0000;                            // 复位沿清锁存（故障复位路径）
    bCleanReminder := FALSE;                      // 清洗提醒同步复位
END_IF
bIrradOk := (fIrradWm2 = fIrradWm2) AND (fIrradWm2 >= fIrradMinWm2)
            AND (fIrradWm2 <= DL_PV_IRRMAX);  // 辐照有限 + 高于同窗下限
bWinOk := bIrradOk
          AND (fTempC = fTempC) AND (ABS(fTempC - fTempRefC) <= fTempBandC)   // 温度同窗带宽
          AND (fPowerKw = fPowerKw) AND (fPowerKw > 0.0);                     // 功率正域闸（性能比分母）
IF bWinOk THEN
    fPrPct := fPowerKw / fPowerRefKw * DL_PV_PCTMAX;   // 性能比 [%]，分母已在组态闸判正
ELSE
    fPrPct := 0.0;                                // 同窗外不计性能比（0 仅作占位，样本不采样）
END_IF
fPrNowPct := fPrPct;                              // 当前性能比输出

(* === 段 2 · 基线窗口统计实例（每拍无条件调用）=== *)
statPr(fIn := fPrPct,                             // 输入当前性能比
       bSample := bWinOk AND bSample AND bCfgOk,  // 仅同窗样本纳入基线（防把天气当积灰）
       nWindow := nWindowLen,                     // 窗口长度，块内自钳 2~64
       bClear := rtrReset.Q);                     // 复位清窗
fPrBasePct := statPr.fMean;                       // 基线 = 窗口均值
fSpanDay := fEvalSpanH / DL_PV_HOURDAY;           // 时间窗折算天数，分母为正常量 24

(* === 段 3 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_PvSoilPhase.eIdle :
    bFrozen := FALSE;                             // 空闲不冻结
    uInfo := 16#0000;                             // 信息码清零
    IF uFault = 16#0002_0685 THEN
        _eState := E_DL_PvSoilPhase.eFault;       // 组态故障优先
    ELSIF bEnable AND bSample THEN
        _eState := E_DL_PvSoilPhase.eCollect;     // 进入采样相
    END_IF

E_DL_PvSoilPhase.eCollect :
    IF NOT bIrradOk THEN
        bFrozen := TRUE;                          // 低辐照：冻结估算，禁外推
        uInfo := 16#0002_06A5;                    // 信息级：低辐照冻结
        _eState := E_DL_PvSoilPhase.eFrozen;
    ELSIF (NOT statPr.bValid) OR (NOT statPr.bStatValid) THEN
        _eState := E_DL_PvSoilPhase.eCollect;     // 基线窗口未成形：继续采样（本拍不推进）
    ELSIF bCfgOk AND (fSpanDay > fEps) THEN
        _eState := E_DL_PvSoilPhase.eRate;        // 分母（时间窗）已判正，转速率相
    ELSE
        bFrozen := TRUE;                          // 分母非法：冻结
        _eState := E_DL_PvSoilPhase.eFrozen;
    END_IF

E_DL_PvSoilPhase.eRate :
    IF ABS(fPrBasePct) > fEps THEN                // 基线上分母防除零
        fLossBuf := (fPrBasePct - fPrPct) / fPrBasePct * DL_PV_PCTMAX;   // 积灰损失率
    ELSE
        fLossBuf := 0.0;                          // 基线近零：不出损失率（判不可测）
    END_IF
    IF fLossBuf < 0.0 THEN
        fLossBuf := 0.0;                          // 负损失（清洗后更干净）截零，不作负积灰显示
    END_IF
    IF fLossBuf > DL_PV_PCTMAX THEN
        fLossBuf := DL_PV_PCTMAX;                 // 饱和硬限（满量程 100%）
    END_IF
    fLossPct := fLossBuf;                         // 损失率输出
    fDecayPctPerDay := fLossBuf / fSpanDay;       // 衰减速率 [%/天]，分母已判 > fEps
    IF fLossBuf >= fLossAlarmPct THEN
        bCleanReminder := TRUE;                   // 置位型：清洗提醒（段尾不清零）
        _eState := E_DL_PvSoilPhase.eAlarm;
    ELSE
        bCleanReminder := FALSE;                  // 未达门限：提醒解除（可到达的解除路径）
        _eState := E_DL_PvSoilPhase.eCollect;
    END_IF

E_DL_PvSoilPhase.eAlarm :
    bCleanReminder := TRUE;                       // 提醒保持，等待清洗动作
    IF fLossPct < (fLossAlarmPct * 0.5) THEN
        bCleanReminder := FALSE;                  // 损失率降到门限一半以下：解除提醒
        _eState := E_DL_PvSoilPhase.eCollect;
    END_IF

E_DL_PvSoilPhase.eFrozen :
    bFrozen := TRUE;                              // 冻结标志保持
    IF bIrradOk AND bCfgOk AND statPr.bStatValid THEN
        bFrozen := FALSE;                         // 辐照恢复 + 窗口成形：解冻（可到达的解除路径）
        uInfo := 16#0000;                         // 信息码清除
        _eState := E_DL_PvSoilPhase.eCollect;
    END_IF

E_DL_PvSoilPhase.eFault :
    bFrozen := TRUE;                              // 故障态冻结估算
    fDecayPctPerDay := 0.0;                       // 速率输出 0（安全侧）
    IF uFault = 16#0000 THEN
        _eState := E_DL_PvSoilPhase.eIdle;        // 解锁后回空闲
    END_IF

ELSE
    _eState := E_DL_PvSoilPhase.eFault;           // 非法状态拦截
    uFault := 16#0002_0695;                       // 故障级：相 ID 越界（枚举兜底路径）
END_CASE
IF NOT bEnable THEN
    _eState := E_DL_PvSoilPhase.eIdle;            // 失能最高优先回空闲
    bFrozen := FALSE;                             // 失能不算冻结
    fDecayPctPerDay := 0.0;                       // 失能速率输出 0
END_IF

(* === 段 4 · 输出映射（三行同向：性能比 → 基线 → 标志）=== *)
IF NOT statPr.bStatValid THEN
    fDecayPctPerDay := 0.0;                       // 窗口未成形：速率不出结论
END_IF
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
