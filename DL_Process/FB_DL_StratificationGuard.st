(*
  FB_DL_StratificationGuard  —  水箱温度分层监视与混温抑制 / Tank thermal stratification monitor with mixing suppression
  分类 Category : DL_Process
  码位 Code     : 16#06_0_88
  版本 Version  : 1.0.0
  溯源 Source   : Modular PID 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 上下点温差带迟滞判据（起动门限 > 停止门限），防混水泵频繁启停；
                  2) 两点任一无效时冻结判定并保持上次输出；
                  3) 混温请求与主机启动命令互斥仲裁，同拍双真取安全侧（抑制混温、让主机优先）。
  边界 Boundary : ① 温差判据带迟滞（fDiffOnC 必须 > fDiffOffC，否则组态报码）；
                  ② 两点任一无效时冻结判定并保持上次输出（bFreeze）；
                  ③ 混温请求与主机启动命令互斥仲裁，同拍双真取安全侧；
                  ④ 仲裁态三行同向：混温请求 → 温差记录 → 冻结标志。
  依赖 Depends  : None

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0688 故障级：迟滞门限非法（fDiffOnC <= fDiffOffC 或门限 <= 0）
    16#0002_0698 故障级：相 ID 越界（枚举兜底路径）
    16#0002_06A8 信息级：仲裁互斥生效（主机启动优先，混温请求被抑制，不置 bError）
*)

TYPE E_DL_StratPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    eMonitor := 10,  // 温差监视 / Differential monitoring
    eMixOn   := 20,  // 混温运行 / Mixing active
    eFreeze  := 30,  // 无效点冻结 / Frozen by invalid points
    eFault   := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_StratificationGuard
VAR_INPUT
    bEnable      : BOOL;                          // 总使能，FALSE 回空闲停泵 / Master enable
    bReset       : BOOL;                          // 复位，上升沿清故障 / Reset, clears fault
    fTempTopC    : REAL;                          // 水箱上部温度 [degC]，域 −20~120 / Upper tank temperature [degC]
    bTopValid    : BOOL := TRUE;                  // 上部温度通道有效 / Upper channel valid
    fTempBotC    : REAL;                          // 水箱下部温度 [degC]，域 −20~120 / Lower tank temperature [degC]
    bBotValid    : BOOL := TRUE;                  // 下部温度通道有效 / Lower channel valid
    fDiffOnC     : REAL := 5.0;                   // 混温起动温差门限 [degC]，域 > 0 / Mixing start threshold [degC]
    fDiffOffC    : REAL := 2.0;                   // 混温停止温差门限 [degC]，域 > 0 且 < 起动门限 / Mixing stop threshold
    fDiffMaxC    : REAL := 30.0;                  // 温差物理域上限 [degC]，超此值判传感器异常 / Differential domain high
    bHostStartCmd: BOOL;                          // 主机启动命令（互斥仲裁输入）/ Host start command for arbitration
    fEps         : REAL := 1.0E-6;                // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fDiffC       : REAL;                          // 上下点温差 [degC]（上 − 下）/ Top-minus-bottom differential [degC]
    bMixPumpReq  : BOOL;                          // 混温泵请求 [开关] / Mixing pump request
    bFreeze      : BOOL;                          // 判定冻结标志（保持型）/ Judgment frozen, held
    bArbitActive : BOOL;                          // 仲裁互斥生效标志 / Arbitration active flag
    bError       : BOOL;                          // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId     : UDINT;                         // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut    : E_DL_StratPhase;               // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState      : E_DL_StratPhase := E_DL_StratPhase.eIdle;  // 内部状态 / Internal state
    rtrReset     : R_TRIG;                        // 复位沿 / Reset edge
    bPtsOk       : BOOL;                          // 两点均有效 / Both points valid
    bCfgOk       : BOOL;                          // 门限组态合法 / Thresholds valid
    bMixLatched  : BOOL;                          // 混温请求锁存（迟滞用）/ Mixing request latch for hysteresis
    fDiffBuf     : REAL;                          // 本拍温差 [degC] / Differential this scan
    uFault       : UDINT;                         // 锁存故障码 / Latched fault code
    uInfo        : UDINT;                         // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_STR_TMIN  : REAL := -20.0;                 // 温度物理域下限 [degC] / Temperature domain low
    DL_STR_TMAX  : REAL := 120.0;                 // 温度物理域上限 [degC] / Temperature domain high
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸与测点域闸 === *)
bCfgOk := (fDiffOnC > fEps) AND (fDiffOffC > fEps) AND (fDiffOnC > fDiffOffC + fEps)
          AND (fDiffMaxC > fDiffOnC) AND (fDiffOnC = fDiffOnC) AND (fDiffOffC = fDiffOffC);   // 含 NaN 自反
IF NOT bCfgOk THEN
    uFault := 16#0002_0688;                       // 故障级：迟滞门限非法（倒置或非正）
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（复位路径可达）
END_IF
bPtsOk := bTopValid AND bBotValid
          AND (fTempTopC = fTempTopC) AND (fTempBotC = fTempBotC)          // NaN 自反判据
          AND (ABS(fTempTopC) < 1.0E30) AND (ABS(fTempBotC) < 1.0E30)      // Inf 上限兜底
          AND (fTempTopC >= DL_STR_TMIN) AND (fTempTopC <= DL_STR_TMAX)     // 上点物理域
          AND (fTempBotC >= DL_STR_TMIN) AND (fTempBotC <= DL_STR_TMAX);    // 下点物理域
IF bPtsOk THEN
    fDiffBuf := fTempTopC - fTempBotC;            // 温差 = 上 − 下（正 = 上部更热，分层成立）
ELSE
    fDiffBuf := fDiffC;                           // 无效点：温差保持上次值，不参与判定
END_IF
IF ABS(fDiffBuf) > fDiffMaxC THEN
    uInfo := 16#0002_06A8;                        // 信息级：温差超物理域，疑似传感器异常
    bPtsOk := FALSE;                              // 超域按无效处理，冻结判定
END_IF
fDiffC := fDiffBuf;                               // 温差输出

(* === 段 2 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_StratPhase.eIdle :
    bMixPumpReq := FALSE;                         // 空闲停泵
    bFreeze := FALSE;                             // 冻结标志复位
    bMixLatched := FALSE;                         // 迟滞锁存复位
    uInfo := 16#0000;                             // 信息码清零（本拍异常会重新置位）
    IF uFault <> 16#0000 THEN
        _eState := E_DL_StratPhase.eFault;        // 故障优先
    ELSIF bEnable AND (NOT bPtsOk) THEN
        bFreeze := TRUE;                          // 上电即无效：直接冻结
        _eState := E_DL_StratPhase.eFreeze;
    ELSIF bEnable THEN
        _eState := E_DL_StratPhase.eMonitor;      // 进入监视相
    END_IF

E_DL_StratPhase.eMonitor :
    IF NOT bPtsOk THEN
        bFreeze := TRUE;                          // 任一测点无效：冻结判定
        _eState := E_DL_StratPhase.eFreeze;
    ELSE
        bFreeze := FALSE;                         // 两点有效：解冻
        IF (NOT bMixLatched) AND (fDiffC >= fDiffOnC) THEN
            bMixLatched := TRUE;                  // 越起动门限：置请求锁存
            bMixPumpReq := TRUE;                  // 混温请求输出
            _eState := E_DL_StratPhase.eMixOn;
        END_IF
    END_IF

E_DL_StratPhase.eMixOn :
    bMixPumpReq := TRUE;                          // 混温运行
    IF NOT bPtsOk THEN
        bFreeze := TRUE;                          // 测点无效：冻结（请求保持上次值）
        _eState := E_DL_StratPhase.eFreeze;
    ELSIF fDiffC <= fDiffOffC THEN
        bMixLatched := FALSE;                     // 降到停止门限以下：解除（迟滞回差生效）
        bMixPumpReq := FALSE;                     // 停泵
        _eState := E_DL_StratPhase.eMonitor;
    END_IF

E_DL_StratPhase.eFreeze :
    bFreeze := TRUE;                              // 冻结标志保持
    IF bPtsOk THEN
        bFreeze := FALSE;                         // 两点恢复有效：解冻（可到达的解除路径）
        uInfo := 16#0000;                         // 信息码清除
        _eState := E_DL_StratPhase.eMonitor;
    END_IF

E_DL_StratPhase.eFault :
    bMixPumpReq := FALSE;                         // 故障态停泵（安全侧）
    bFreeze := TRUE;                              // 冻结判定
    bMixLatched := FALSE;                         // 迟滞锁存复位
    IF uFault = 16#0000 THEN
        _eState := E_DL_StratPhase.eIdle;         // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_StratPhase.eFault;            // 非法状态拦截
    uFault := 16#0002_0698;                       // 故障级：相 ID 越界（枚举兜底路径）
    bMixPumpReq := FALSE;                         // 安全侧停泵
END_CASE

(* === 段 3 · 互斥仲裁：混温请求 vs 主机启动命令（同拍双真取安全侧）=== *)
bArbitActive := FALSE;                            // 仲裁标志每拍重算
IF bHostStartCmd AND bMixPumpReq THEN
    bMixPumpReq := FALSE;                         // 安全侧：主机启动优先，抑制混温
    bMixLatched := FALSE;                         // 迟滞锁存同步复位，防下一拍立即复启
    bArbitActive := TRUE;                         // 仲裁互斥生效
    uInfo := 16#0002_06A8;                        // 信息级：仲裁互斥（不置 bError）
END_IF

(* === 段 4 · 输出映射（三行同向：请求 → 温差 → 冻结标志）=== *)
IF NOT bEnable THEN
    bMixPumpReq := FALSE;                         // 失能最高优先停泵
    bArbitActive := FALSE;                        // 失能不算仲裁
END_IF
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
