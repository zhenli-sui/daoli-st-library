(*
  FB_DL_BypassValveTrim  —  旁通阀供回水压差 PI 微调 / Bypass valve differential-pressure PI trim
  分类 Category : DL_Device
  码位 Code     : 16#03_2_09
  版本 Version  : 1.0.0
  溯源 Source   : ModPID 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 供/回水压差闭环 PI 微调（复用 FB_DL_PidController，阀位死区与限幅）；
                  2) 压差无效冻结输出保持末次阀位（跟踪回投）；
                  3) 阀位输出钳行程域并置饱和码。
  边界 Boundary : ① 两压力（压差合成源）任一无效冻结输出保持末次阀位；
                  ② 阀位输出钳行程域并置饱和标志；
                  ③ 死区带宽非法（<= 0 或倒置）出厂报码；
                  ④ PID 参数 Ti/Td = 0 按「关闭」语义不判非法（T2-5 参数域惯例）；
                  ⑤ 压差传感器量程 0 邻域防除零（换算分母域闸）；
                  ⑥ 输出三行同向：阀位微调 → 饱和标志 → 冻结标志。
  依赖 Depends  : FB_DL_PidController × 1（PI 调节，每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0309 故障级：组态非法（死区 <= 0 / 行程域倒置 / 量程 <= 0）
    16#0002_0319 故障级：相 ID 越界（枚举兜底路径）
    16#0002_0329 信息级：压差无效输出冻结 / 阀位饱和钳位（不置 bError）
*)

TYPE E_DL_BvtPhase :
(
    eIdle   := 0,  // 空闲（阀位回下限）/ Idle, valve at low limit
    eTrim   := 10, // PI 微调运行 / PI trim running
    eFrozen := 20, // 压差无效冻结 / Frozen by invalid DP
    eFault  := 90  // 组态故障锁定 / Configuration fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_BypassValveTrim
VAR_INPUT
    bEnable       : BOOL;                           // 总使能，FALSE 阀位回下限 / Master enable
    bReset        : BOOL;                           // 复位，上升沿清组态故障 / Reset, clears fault
    fDpKpa        : REAL;                           // 供/回水压差实测 [kPa] / Measured DP [kPa]
    fDpSpKpa      : REAL := 25.0;                   // 压差设定 [kPa]，域 > 0 / DP setpoint [kPa]
    fKp           : REAL := 1.5;                    // 比例增益 [1] / Proportional gain [1]
    tTi           : TIME := T#20S;                  // 积分时间 [s]，T#0S = 关闭积分 / Integral time, T#0S = off
    tTd           : TIME := T#0S;                   // 微分时间 [s]，T#0S = 关闭微分 / Derivative time, T#0S = off
    fDeadbandKpa  : REAL := 0.5;                    // 控制死区 [kPa]，域 > 0 / Control deadband [kPa]
    fValveMinPct  : REAL := 0.0;                    // 阀位行程域下限 [%] / Valve domain low [%]
    fValveMaxPct  : REAL := 100.0;                  // 阀位行程域上限 [%] / Valve domain high [%]
    fManValvePct  : REAL := 50.0;                   // 手动阀位 [%]（跟踪回投基准）/ Manual valve position [%]
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fValveOutPct  : REAL;                           // 旁通阀位输出 [%] / Bypass valve output [%]
    bSaturated    : BOOL;                           // 阀位饱和标志 / Valve saturated flag
    bFrozen       : BOOL;                           // 压差无效冻结标志 / Frozen by invalid DP
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code
    eStateOut     : E_DL_BvtPhase;                  // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_BvtPhase := E_DL_BvtPhase.eIdle;  // 内部状态 / Internal state
    fbPid         : FB_DL_PidController;            // PI 实例（无条件调用）/ PI instance
    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge
    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid
    bDpOk         : BOOL;                           // 压差本拍有效 / DP valid this scan
    fValveHold    : REAL;                           // 末次有效阀位 [%]（冻结保持）/ Last valid valve position [%]
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
END_VAR

(* === 段 0 · 实例刷新 === *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸（Ti/Td = 0 按「关闭」语义不判非法）=== *)
bCfgOk := (fDeadbandKpa > fEps)                   // 死区正域（<= 0 出厂报码）
          AND (fValveMaxPct > fValveMinPct + fEps)// 行程域不倒置
          AND (fDpSpKpa > fEps)                   // 设定正域
          AND (fDpSpKpa = fDpSpKpa) AND (fKp = fKp);  // NaN 自反（Ti/Td 为 0 合法：关闭语义）
IF NOT bCfgOk THEN
    uFault := 16#0002_0309;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（解除路径可达）
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零
bDpOk := (fDpKpa = fDpKpa) AND (fDpKpa >= 0.0) AND (fDpKpa < 1.0E30);   // 压差 NaN 自反 + 非负域闸

(* === 段 2 · PI 实例（每拍无条件调用）=== *)
fbPid(bEnable := bEnable AND bCfgOk AND bDpOk,    // 压差无效/故障：PI 停调
      bManual := FALSE,                           // 自动微调
      fSetpoint := fDpSpKpa,                      // 压差设定
      fActual := fDpKpa,                          // 压差实测
      fKp := fKp,                                 // 比例增益
      tTi := tTi,                                 // 积分时间（0 = 关闭，合法语义）
      tTd := tTd,                                 // 微分时间（0 = 关闭）
      fDeadband := fDeadbandKpa,                  // 控制死区
      rOutMin := fValveMinPct,                    // 输出下限 = 行程域下限
      rOutMax := fValveMaxPct,                    // 输出上限 = 行程域上限
      tSampleTime := T#100MS,                     // 采样周期
      bTrack := (NOT bDpOk) OR (NOT bEnable),     // 无效/失能：跟踪回投保持阀位（无扰冻结）
      fTrackValue := fValveHold,                  // 跟踪值 = 末次有效阀位
      bReset := rtrReset.Q);                      // 复位沿透传

(* === 段 3 · 输出域闸与饱和标志 === *)
fValveOutPct := fbPid.fOut;                       // 阀位输出
IF fValveOutPct > fValveMaxPct THEN
    fValveOutPct := fValveMaxPct;                 // 钳到行程域上限
END_IF
IF fValveOutPct < fValveMinPct THEN
    fValveOutPct := fValveMinPct;                 // 钳到行程域下限
END_IF
bSaturated := fbPid.bLimitHigh OR fbPid.bLimitLow;   // 饱和标志（映射实例触限）
IF bSaturated AND bDpOk THEN
    uInfo := 16#0002_0329;                        // 信息级：阀位饱和钳位
END_IF

(* === 段 4 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_BvtPhase.eIdle :
    IF uFault <> 16#0000 THEN
        _eState := E_DL_BvtPhase.eFault;          // 故障优先
    ELSIF bEnable AND bCfgOk AND (NOT bDpOk) THEN
        _eState := E_DL_BvtPhase.eFrozen;         // 压差无效进冻结
    ELSIF bEnable AND bCfgOk AND bDpOk THEN
        _eState := E_DL_BvtPhase.eTrim;           // 进微调相
    END_IF

E_DL_BvtPhase.eTrim :
    IF (uFault <> 16#0000) OR (NOT bEnable) THEN
        _eState := E_DL_BvtPhase.eFault;          // 故障/失能转出
    ELSIF NOT bDpOk THEN
        uInfo := 16#0002_0329;                    // 信息级：压差无效输出冻结
        _eState := E_DL_BvtPhase.eFrozen;         // 转冻结相（阀位保持末次值）
    ELSE
        fValveHold := fValveOutPct;               // 有效拍记账末次阀位（冻结保持源）
    END_IF

E_DL_BvtPhase.eFrozen :
    IF bDpOk AND bEnable AND (uFault = 16#0000) THEN
        _eState := E_DL_BvtPhase.eTrim;           // 压差恢复回微调（解除路径可达，跟踪无扰）
    END_IF

E_DL_BvtPhase.eFault :
    IF uFault = 16#0000 THEN
        _eState := E_DL_BvtPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_BvtPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_0319;                       // 故障级：相 ID 越界
END_CASE
bFrozen := (_eState = E_DL_BvtPhase.eFrozen);     // 冻结标志段尾单点映射

(* === 段 5 · 输出映射 === *)
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
