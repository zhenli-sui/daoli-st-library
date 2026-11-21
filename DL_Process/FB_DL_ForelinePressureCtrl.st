(*
  FB_DL_ForelinePressureCtrl  —  真空前级管路压力稳定 / Vacuum foreline pressure stabilization
  分类 Category : DL_Process
  码位 Code     : 16#06_0_99
  版本 Version  : 1.0.0
  溯源 Source   : ModPID 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 前级压力闭环 PI 调节（复用 FB_DL_PidController，阀位限幅抗饱和联动）；
                  2) 抽速前馈通道叠加（前馈指令非有限拒绝并保持末次有效）；
                  3) 压力越窗分级告警（带迟滞）。
  边界 Boundary : ① 压力无效冻结输出（跟踪回投保持末次阀位）；
                  ② 设定低于量程下限钳定并置码；
                  ③ 阀位饱和与 PI 抗饱和联动（限幅反算由实例承担）；
                  ④ 前馈通道指令非有限拒绝保持末次有效（FB_DL_SuperimposedMove 同范式）；
                  ⑤ 越窗分级带迟滞；
                  ⑥ 输出三行同向：阀位 → 饱和/冻结标志 → 越窗告警。
  依赖 Depends  : FB_DL_PidController × 1（PI 调节，每拍无条件调用）

  码表 Error codes（本件子码步进 16#30 · 本格 99 与既有 9X 子码段冲突，错位至 C9/D9 避让）:
    16#0002_06C9 故障级：组态非法（量程域倒置 / 行程域倒置 / 增益 <= 0）
    16#0002_06D9 故障级：相 ID 越界（枚举兜底路径）
    16#0002_06B9 信息级：压力无效输出冻结 / 设定低于量程钳定 / 前馈非有限已拒 / 越窗提示（不置 bError）
*)

TYPE E_DL_FpcPhase :
(
    eIdle   := 0,  // 空闲（阀位回下限）/ Idle, valve at low limit
    eRun    := 10, // PI 调节运行 / PI running
    eFrozen := 20, // 压力无效冻结 / Frozen by invalid pressure
    eFault  := 90  // 组态故障锁定 / Configuration fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_ForelinePressureCtrl
VAR_INPUT
    bEnable       : BOOL;                           // 总使能，FALSE 阀位回下限 / Master enable
    bReset        : BOOL;                           // 复位，上升沿清组态故障 / Reset, clears fault
    fPressPa      : REAL;                           // 前级压力实测 [Pa] / Foreline pressure [Pa]
    fPressSpPa    : REAL := 10.0;                   // 压力设定 [Pa]，域 > 0 / Pressure setpoint [Pa]
    fRangeLoPa    : REAL := 1.0;                    // 量程下限 [Pa]，域 > 0（设定钳定域）/ Range low [Pa]
    fRangeHiPa    : REAL := 1000.0;                 // 量程上限 [Pa]，域 > 0 / Range high [Pa]
    fSpeedFfPct   : REAL;                           // 抽速前馈指令 [%] / Pumping-speed feedforward [%]
    fKp           : REAL := 2.0;                    // 比例增益 [1]，负值 = 反作用 / Proportional gain [1]
    tTi           : TIME := T#30S;                  // 积分时间 [s]，T#0S = 关闭 / Integral time, T#0S = off
    tTd           : TIME := T#0S;                   // 微分时间 [s]，T#0S = 关闭 / Derivative time, T#0S = off
    fValveMinPct  : REAL := 0.0;                    // 阀位行程域下限 [%] / Valve domain low [%]
    fValveMaxPct  : REAL := 100.0;                  // 阀位行程域上限 [%] / Valve domain high [%]
    fDevWarnPa    : REAL := 3.0;                    // 越窗提示门限 [Pa]，域 > 0 / Deviation warning limit [Pa]
    fHystPa       : REAL := 0.5;                    // 越窗迟滞 [Pa]，域 > 0 / Deviation hysteresis [Pa]
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fValveOutPct  : REAL;                           // 调节阀位输出 [%]（PI + 前馈叠加）/ Valve output [%]
    fFfUsedPct    : REAL;                           // 本拍生效前馈 [%] / Feedforward used [%]
    bSaturated    : BOOL;                           // 阀位饱和标志 / Valve saturated flag
    bFrozen       : BOOL;                           // 压力无效冻结标志 / Frozen by invalid pressure
    bDevWarn      : BOOL;                           // 越窗提示标志（带迟滞）/ Deviation warning flag
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code
    eStateOut     : E_DL_FpcPhase;                  // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_FpcPhase := E_DL_FpcPhase.eIdle;  // 内部状态 / Internal state
    fbPid         : FB_DL_PidController;            // PI 实例（无条件调用）/ PI instance
    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge
    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid
    bPressOk      : BOOL;                           // 压力本拍有效 / Pressure valid this scan
    fSpClampPa    : REAL;                           // 钳定后设定 [Pa] / Clamped setpoint [Pa]
    bSpClamped    : BOOL;                           // 设定钳定标志 / Setpoint clamped flag
    fFfHoldPct    : REAL;                           // 末次有效前馈 [%]（非有限保持）/ Last valid feedforward [%]
    bFfOk         : BOOL;                           // 前馈指令本拍有效 / Feedforward valid this scan
    bDevUp        : BOOL;                           // 越窗迟滞状态（持有）/ Deviation hysteresis state
    fValveHold    : REAL;                           // 末次有效阀位 [%]（冻结保持）/ Last valid valve [%]
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
END_VAR

(* === 段 0 · 实例刷新 === *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸 === *)
bCfgOk := (fRangeHiPa > fRangeLoPa + fEps)        // 量程域不倒置
          AND (fValveMaxPct > fValveMinPct + fEps)// 行程域不倒置
          AND (ABS(fKp) > fEps)                   // 增益非零（负值 = 反作用合法）
          AND (fDevWarnPa > fHystPa)              // 越窗门限大于迟滞（带不相交）
          AND (fPressSpPa = fPressSpPa) AND (fKp = fKp);  // NaN 自反
IF NOT bCfgOk THEN
    uFault := 16#0002_06C9;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（解除路径可达）
    bDevUp := FALSE;                              // 越窗迟滞复位
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零
bPressOk := (fPressPa = fPressPa) AND (fPressPa >= 0.0) AND (fPressPa < 1.0E30);   // 压力 NaN 自反 + 非负域闸

(* === 段 2 · 设定钳定与越窗迟滞判据（本拍重算）=== *)
fSpClampPa := fPressSpPa;                         // 设定先取组态值
bSpClamped := bPressOk AND (fSpClampPa < fRangeLoPa);   // 低于量程下限钳定标志
IF bSpClamped THEN
    fSpClampPa := fRangeLoPa;                     // 钳定量程下限
    uInfo := 16#0002_06B9;                        // 信息级：设定低于量程钳定
END_IF
bDevUp := bDevUp AND bPressOk;                    // 迟滞状态只在有效拍保持（无效拍判据挂起）
IF bPressOk THEN
    IF ABS(fPressPa - fSpClampPa) >= fDevWarnPa THEN
        bDevUp := TRUE;                           // 越窗置迟滞状态
    ELSIF ABS(fPressPa - fSpClampPa) < fDevWarnPa - fHystPa THEN
        bDevUp := FALSE;                          // 回差带内解除（路径可达）
    END_IF
END_IF
bDevWarn := bDevUp;                               // 越窗提示出口

(* === 段 3 · 前馈通道非有限拒绝（保持末次有效，SuperimposedMove 同范式）=== *)
bFfOk := (fSpeedFfPct = fSpeedFfPct) AND (ABS(fSpeedFfPct) < 1.0E30);   // 前馈 NaN 自反 + 幅值闸
IF bFfOk THEN
    fFfHoldPct := fSpeedFfPct;                    // 有效拍记账末次前馈
ELSE
    uInfo := 16#0002_06B9;                        // 信息级：前馈非有限已拒
END_IF
fFfUsedPct := fFfHoldPct;                         // 生效前馈（保持末次有效）

(* === 段 4 · PI 实例（每拍无条件调用，限幅反算抗饱和由实例承担）=== *)
fbPid(bEnable := bEnable AND bCfgOk AND bPressOk, // 压力无效/故障：PI 停调
      bManual := FALSE,                           // 自动调节
      fSetpoint := fSpClampPa,                    // 钳定后设定
      fActual := fPressPa,                        // 压力实测
      fKp := fKp,                                 // 比例增益
      tTi := tTi,                                 // 积分时间（0 = 关闭，合法语义）
      tTd := tTd,                                 // 微分时间（0 = 关闭）
      rOutMin := fValveMinPct - fFfUsedPct,       // 输出下限平移（前馈叠加域）
      rOutMax := fValveMaxPct - fFfUsedPct,       // 输出上限平移（前馈叠加域，限幅反算）
      tSampleTime := T#100MS,                     // 采样周期
      bTrack := (NOT bPressOk) OR (NOT bEnable),  // 无效/失能：跟踪回投保持阀位（无扰冻结）
      fTrackValue := fValveHold - fFfUsedPct,     // 跟踪值 = 末次阀位 − 前馈（叠加域口径）
      bReset := rtrReset.Q);                      // 复位沿透传
fValveOutPct := fbPid.fOut + fFfUsedPct;          // 阀位 = PI 输出 + 前馈叠加
IF fValveOutPct > fValveMaxPct THEN
    fValveOutPct := fValveMaxPct;                 // 钳到行程域上限
END_IF
IF fValveOutPct < fValveMinPct THEN
    fValveOutPct := fValveMinPct;                 // 钳到行程域下限
END_IF
bSaturated := fbPid.bLimitHigh OR fbPid.bLimitLow;   // 饱和标志（映射实例触限）
IF bSaturated AND bPressOk THEN
    uInfo := 16#0002_06B9;                        // 信息级：阀位饱和
END_IF

(* === 段 5 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_FpcPhase.eIdle :
    IF uFault <> 16#0000 THEN
        _eState := E_DL_FpcPhase.eFault;          // 故障优先
    ELSIF bEnable AND bCfgOk AND (NOT bPressOk) THEN
        _eState := E_DL_FpcPhase.eFrozen;         // 压力无效进冻结
    ELSIF bEnable AND bCfgOk AND bPressOk THEN
        _eState := E_DL_FpcPhase.eRun;            // 进运行相
    END_IF

E_DL_FpcPhase.eRun :
    IF (uFault <> 16#0000) OR (NOT bEnable) THEN
        _eState := E_DL_FpcPhase.eFault;          // 故障/失能转出
    ELSIF NOT bPressOk THEN
        uInfo := 16#0002_06B9;                    // 信息级：压力无效输出冻结
        _eState := E_DL_FpcPhase.eFrozen;         // 转冻结相（阀位保持末次值）
    ELSE
        fValveHold := fValveOutPct;               // 有效拍记账末次阀位（冻结保持源）
    END_IF

E_DL_FpcPhase.eFrozen :
    IF bPressOk AND bEnable AND (uFault = 16#0000) THEN
        _eState := E_DL_FpcPhase.eRun;            // 压力恢复回运行（解除路径可达，跟踪无扰）
    END_IF

E_DL_FpcPhase.eFault :
    IF uFault = 16#0000 THEN
        _eState := E_DL_FpcPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_FpcPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_06D9;                       // 故障级：相 ID 越界
END_CASE
bFrozen := (_eState = E_DL_FpcPhase.eFrozen);     // 冻结标志段尾单点映射

(* === 段 6 · 输出映射 === *)
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
