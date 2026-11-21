(*
  FB_DL_TrapSealTrend  —  枕式包装封口温度随线速前馈重置 / Pillow-pack seal temperature feedforward with line-speed reset
  分类 Category : DL_Process
  码位 Code     : 16#06_0_86
  版本 Version  : 1.0.1
  溯源 Source   : Modular PID 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  修订 Revision : v1.0.1 (R34 终审抽检) — ① 判停改按原始线速 bSpeedStop，修正「零速保持相在曾运行后不可达」
                  （原以 fSpeedUse 判停，而 fSpeedUse 是末次有效线速替代值，恒 > 0 致 bHold 永假）；
                  ② 输入引脚 fSpeedValid 更名 bSpeedValid（BOOL 前缀红线 1，v1.0.0 无下游调用方，不构成破坏性变更）；
                  ③ 删段 7 自赋值空语句 uInfo := uInfo。接口语义与码表不变。
  功能 Function : 1) 线速前馈：封温设定 = 基准设定 + 线速偏差 × 前馈增益，线速经斜坡限速后进 PID 设定；
                  2) 线速为 0 时不得外推封温设定，改用末次有效线速并置 bHold（禁按零速反推冷设定）；
                  3) 封温设定钳到工艺窗口上下限，越限只钳位 + 报码不拒算；重置斜率须与 PID 采样周期配比，超调即判组态非法。
  边界 Boundary : ① 线速为 0 不得外推封温设定（末次有效线速 + bHold）；
                  ② 重置限速斜率与 PID 采样周期配比（每采样步进 <= fSpStepMaxC），非法即组态报码；
                  ③ 封温设定钳到工艺窗口上下限，越限只钳位 + 报码不拒算；
                  ④ 安全侧三行同向：PID 输出限 0 → 设定保持末值 → bHold 置位。
  依赖 Depends  : FB_DL_PidController（封温闭环）、FB_DL_RateLimiter（设定斜坡），均每拍无条件调用

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0686 故障级：组态非法（工艺窗口上/下限倒置、增益或斜率 <= 0、采样周期 <= 0）
    16#0002_0696 故障级：前馈斜率与采样周期配比超调（单步进料过大）
    16#0002_06A6 信息级：封温设定已钳位（不置 bError，照算）
*)

TYPE E_DL_TstPhase :
(
    eIdle   := 0,   // 空闲 / Idle
    eTrack  := 10,  // 线速跟踪 / Line-speed tracking
    eHold   := 20,  // 零速保持 / Zero-speed hold
    eRun    := 30,  // 闭环调节 / Closed-loop control
    eFault  := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_TrapSealTrend
VAR_INPUT
    bEnable      : BOOL;                          // 总使能，FALSE 回空闲 / Master enable
    bReset       : BOOL;                          // 复位，上升沿清故障 / Reset, clears fault
    fLineSpeedMpm: REAL;                          // 包装线速 [m/min]，域 >= 0 / Packaging line speed [m/min]
    bSpeedValid  : BOOL := TRUE;                  // 线速信号有效标志 / Line speed signal valid
    fSealTempC   : REAL;                          // 封口实测温度 [degC]，域 0~300 / Measured seal temperature [degC]
    fSealBaseC   : REAL := 150.0;                 // 基准封温设定 [degC] / Base seal temperature setpoint [degC]
    fFfGainCpm   : REAL := 0.8;                   // 线速前馈增益 [degC per m/min]，域 > 0 / Feedforward gain
    fSealWinLoC  : REAL := 120.0;                 // 工艺窗口下限 [degC] / Process window low [degC]
    fSealWinHiC  : REAL := 200.0;                 // 工艺窗口上限 [degC] / Process window high [degC]
    fSpRiseRate  : REAL := 20.0;                  // 设定上升限速 [degC/s]，域 > 0 / Setpoint rise rate [degC/s]
    fSpFallRate  : REAL := 20.0;                  // 设定下降限速 [degC/s]，域 > 0 / Setpoint fall rate [degC/s]
    fSpStepMaxC  : REAL := 5.0;                   // 单采样步进上限 [degC]，域 > 0 / Step limit per sample [degC]
    tPidSample   : TIME := T#100MS;               // PID 采样周期 [ms]，域 > 0 / PID sample period [ms]
    fKp          : REAL := 2.0;                   // 比例增益 [1] / Proportional gain
    tTi          : TIME := T#30S;                 // 积分时间 [ms] / Integral time [ms]
    tTd          : TIME := T#5S;                  // 微分时间 [ms] / Derivative time [ms]
    fEps         : REAL := 1.0E-6;                // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fSealSpC     : REAL;                          // 封温设定 [degC]，经前馈 + 限速 + 钳位 / Seal setpoint [degC]
    fPidOutPct   : REAL;                          // 加热输出 [%] / Heater output [%]
    fSpeedHold   : REAL;                          // 生效线速 [m/min]，零速时保持末次有效 / Effective line speed
    bHold        : BOOL;                          // 零速保持标志 / Zero-speed hold flag
    bClamped     : BOOL;                          // 设定钳位标志 / Setpoint clamped flag
    bError       : BOOL;                          // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId     : UDINT;                         // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut    : E_DL_TstPhase;                 // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState      : E_DL_TstPhase := E_DL_TstPhase.eIdle;  // 内部状态 / Internal state
    rtrReset     : R_TRIG;                        // 复位沿 / Reset edge
    fbPid        : FB_DL_PidController;           // 封温闭环实例（无条件调用）/ Seal loop PID
    fbSpRamp     : FB_DL_RateLimiter;             // 设定斜坡实例（无条件调用）/ Setpoint ramp limiter
    bCfgOk       : BOOL;                          // 组态合法标志 / Configuration valid
    bRatioOk     : BOOL;                          // 斜率/周期配比合法 / Slope-period ratio valid
    fSpeedUse    : REAL;                          // 前馈用线速 [m/min] / Speed used for feedforward
    bSpeedStop   : BOOL;                          // 线速判停标志（按原始线速判，非替代值）/ Line stopped per raw speed
    fSpRawC      : REAL;                          // 前馈原始设定 [degC] / Raw feedforward setpoint [degC]
    fSampleS     : REAL;                          // 采样周期折算秒 [s] / Sample period in seconds
    fStepC       : REAL;                          // 单采样最大步进 [degC] / Max step per sample [degC]
    uFault       : UDINT;                         // 锁存故障码 / Latched fault code
    uInfo        : UDINT;                         // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_TST_MSPS    : REAL := 1000.0;              // 毫秒折算秒系数 [ms/s] / Milliseconds per second
    DL_TST_TMAXC   : REAL := 300.0;               // 封温物理域上限 [degC] / Temperature domain high
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用，禁入 CASE 分支）=== *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸：窗口配比 / 增益正域 / 斜率-周期配比 === *)
fSampleS := TIME_TO_LREAL(tPidSample) / DL_TST_MSPS;   // 采样周期折算秒，标准转换函数
bCfgOk := (fSealWinHiC > fSealWinLoC) AND (fFfGainCpm > fEps) AND (fSpRiseRate > fEps)
          AND (fSpFallRate > fEps) AND (fSpStepMaxC > fEps) AND (fSampleS > fEps)
          AND (fSealBaseC > 0.0) AND (fSealBaseC < DL_TST_TMAXC)
          AND (fSealWinHiC = fSealWinHiC) AND (fSealWinLoC = fSealWinLoC);   // NaN 自反判据
fStepC := fSpRiseRate * fSampleS;                 // 单采样步进 = 斜率 × 周期
bRatioOk := (fStepC <= fSpStepMaxC + fEps);       // 配比闸：单步进不得超过工艺允许步进（超调即非法）
IF NOT bCfgOk THEN
    uFault := 16#0002_0686;                       // 故障级：组态非法
END_IF
IF NOT bRatioOk THEN
    uFault := 16#0002_0696;                       // 故障级：斜率与采样周期配比超调
END_IF
IF rtrReset.Q AND bCfgOk AND bRatioOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（故障复位路径可达）
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零

(* === 段 2 · 线速域闸：零速/无效速保持末次有效，不外推 === *)
bSpeedStop := (NOT bSpeedValid) OR (fLineSpeedMpm <> fLineSpeedMpm) OR (fLineSpeedMpm <= fEps);  // 判停只看原始线速（NaN 自反捕获）
IF NOT bSpeedStop
   AND (ABS(fLineSpeedMpm) < 1.0E6) THEN
    fSpeedUse := fLineSpeedMpm;                   // 有效线速直接采用
    fSpeedHold := fLineSpeedMpm;                  // 记入末次有效线速
ELSE
    fSpeedUse := fSpeedHold;                      // 零速/无效：用末次有效线速，禁按 0 反推
END_IF
fSpRawC := fSealBaseC + fSpeedUse * fFfGainCpm;   // 前馈原始设定 [degC]

(* === 段 3 · 设定斜坡实例（每拍无条件调用，限斜率）=== *)
fbSpRamp(bEnable := TRUE,                         // 斜坡常开
         fIn := fSpRawC,                          // 前馈原始设定
         fRateUp := fSpRiseRate,                  // 上升限速 [degC/s]
         fRateDown := fSpFallRate,                // 下降限速 [degC/s]
         bTrack := (NOT bEnable) OR (uFault <> 16#0000),   // 失能/故障：跟踪到基准设定
         fTrackValue := fSealBaseC,               // 跟踪目标 = 基准设定
         tSampleTime := tPidSample);              // 采样周期
fSealSpC := fbSpRamp.fOut;                        // 斜坡后设定

(* === 段 4 · 封温窗口钳位（越限只钳位 + 报码，不拒算）=== *)
bClamped := FALSE;                                // 钳位标志每拍重算
IF fSealSpC > fSealWinHiC THEN
    fSealSpC := fSealWinHiC;                      // 钳到上限
    bClamped := TRUE;                             // 钳位置位
    uInfo := 16#0002_06A6;                        // 信息级：设定已钳位
ELSIF fSealSpC < fSealWinLoC THEN
    fSealSpC := fSealWinLoC;                      // 钳到下限
    bClamped := TRUE;                             // 钳位置位
    uInfo := 16#0002_06A6;                        // 信息级：设定已钳位
END_IF

(* === 段 5 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_TstPhase.eIdle :
    bHold := FALSE;                               // 空闲不保持
    IF uFault <> 16#0000 THEN
        _eState := E_DL_TstPhase.eFault;          // 故障优先
    ELSIF bEnable THEN
        _eState := E_DL_TstPhase.eTrack;          // 进入跟踪相
    END_IF

E_DL_TstPhase.eTrack :
    IF bSpeedStop THEN                            // 判停按原始线速（不按前馈替代值）
        bHold := TRUE;                            // 零速：置保持，禁止外推冷设定
        _eState := E_DL_TstPhase.eHold;
    ELSE
        bHold := FALSE;                           // 有速：正常调节
        _eState := E_DL_TstPhase.eRun;
    END_IF

E_DL_TstPhase.eHold :
    bHold := TRUE;                              // 保持标志维持
    IF NOT bSpeedStop THEN
        bHold := FALSE;                          // 线速恢复即解除保持（可到达的解除路径）
        _eState := E_DL_TstPhase.eRun;
    END_IF

E_DL_TstPhase.eRun :
    IF bSpeedStop THEN                           // 判停按原始线速，与 eTrack 同源
        bHold := TRUE;                            // 线速降到 0：回保持
        _eState := E_DL_TstPhase.eHold;
    ELSIF NOT bEnable THEN
        _eState := E_DL_TstPhase.eIdle;           // 失能回空闲
    ELSIF uFault <> 16#0000 THEN
        _eState := E_DL_TstPhase.eFault;          // 故障拦截
    END_IF

E_DL_TstPhase.eFault :
    bHold := TRUE;                                // 故障态保持（安全侧）
    IF uFault = 16#0000 THEN
        _eState := E_DL_TstPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_TstPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_0686;                       // 故障级：相 ID 越界（枚举兜底路径）
END_CASE

(* === 段 6 · 封温闭环实例（每拍无条件调用）=== *)
fbPid(bEnable := bEnable AND (NOT bHold) AND (uFault = 16#0000),   // 保持/故障时禁调节
      bManual := FALSE,                           // 自动模式
      fManualValue := 0.0,                        // 手动值未用
      fSetpoint := fSealSpC,                      // 设定 = 钳位后封温
      fActual := fSealTempC,                      // 实测封温
      fKp := fKp,                                 // 比例增益
      tTi := tTi,                                 // 积分时间
      tTd := tTd,                                 // 微分时间
      fDeadband := 0.5,                           // 控制死区 [degC]，防抖
      bIncremental := FALSE,                      // 位置式
      rOutMin := 0.0,                             // 输出下限 0%（安全侧）
      rOutMax := 100.0,                           // 输出上限 100%
      tSampleTime := tPidSample,                  // 采样周期
      bTrack := bHold OR (uFault <> 16#0000),     // 保持/故障：跟踪 0 输出
      fTrackValue := 0.0,                         // 跟踪值 0（断加热）
      bReset := rtrReset.Q);                      // 复位沿清积分

(* === 段 7 · 输出映射（安全三行同向）=== *)
IF bHold OR (uFault <> 16#0000) THEN
    fPidOutPct := 0.0;                            // 保持/故障：加热输出 0（驱动方向安全）
    bHold := TRUE;                                // 保持判据与输出同向（设定同步冻结在段 3/4 末值）
ELSE
    fPidOutPct := fbPid.fOut;                     // 正常：取 PID 输出
END_IF
IF NOT bEnable THEN
    fPidOutPct := 0.0;                            // 失能输出 0
END_IF
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
