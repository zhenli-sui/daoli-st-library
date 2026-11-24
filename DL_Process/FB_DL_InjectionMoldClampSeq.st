(*
  道莅工业代码库 | DL_Process | FB_DL_InjectionMoldClampSeq
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  开源溯源: self-cleanroom（无外部来源；行业池·塑机工艺通用语义，零代码行复制）
  功能: 注塑机五段工艺序列——低压护模→高压锁模→射胶→保压→冷却→开模；
        锁模力段间闸（高压锁模后须实测力达下限才放行射胶）与护模/锁模/
        射胶/开模超时出口；中止命令走开模安全撤离（不置故障不计数）。
  兼容性: CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；仅依赖标准 TON / R_TRIG，零厂商私有库
  接口: 输入启动/限位/实测力/实测射压/熔胶到位/各段定时/中止/复位；输出各段
        驱动输出、循环完成单拍、循环计数、eState/eCause/bError/nErrId。
  码表: 16#0005_03B7 故障级：合模序列故障总码（锁存至复位沿，归由 eCause）
        16#0005_04DA 信息级：循环完成台账（eDone 相单拍，uCycleCnt 定稿）
        16#0005_04DB 信息级：中止撤离完成（eOpen 相开到位，不计数）
        码段说明：0005 段故障子带 03xx / 信息子带 04xx，槽位经全库实扫空闲。
  边界: ① 锁模力闸：bMoldClosedLim 已到位而 fClampForceAct 低于下限 →
        等待 tForceGateWait，超时判闸失败（eCause eForceGateTimeout）；
        ② 实测力/射压 NaN 时比较恒 FALSE → 挂等待窗，超时走对应故障出口
        （NaN 不穿透段间闸，结构性防御）；
        ③ ①完成脉冲经 rtDone R_TRIG 单拍化（内部状态置位 → 统一出口映射单拍）；
        ④ 八个 TON + 三个 R_TRIG 段 0 无条件周期刷新；
        ⑤ 故障解除唯一路径 = bReset 上升沿 ∧ 组态合法；⑥ 零全局耦合。
  邻件比对: PileClampCtrl（打桩夹桩，行业域不同），无注塑合模属主（R75 §3 留痕）。
  修订历史: 2026-11-23 v1.0.0 R75 首版（复杂件批 B1 · C02）
*)

TYPE E_DL_IcsPhase :
(
    eIdle      := 0,   // 待机 | Idle
    eClampLp   := 10,  // 低压护模 | Low-pressure mold protect
    eClampHp   := 20,  // 高压锁模 | High-pressure clamp
    eInject    := 30,  // 射胶 | Injection
    eHold      := 40,  // 保压 | Packing hold
    eCool      := 50,  // 冷却 | Cooling
    eOpen      := 60,  // 开模 | Mold open
    eDone      := 70,  // 循环完成单拍相 | Cycle done one-shot phase
    eFault     := 90   // 故障锁存相 | Fault latch phase
);
END_TYPE

TYPE E_DL_IcsCause :
(
    eNone            := 0,  // 无故障 | No cause
    eCfgIllegal      := 1,  // 组态非法 | Illegal configuration
    eClampLpTimeout  := 2,  // 低压护模超时 | Low-pressure protect timeout
    eClampHpTimeout  := 3,  // 高压锁模超时 | High-pressure clamp timeout
    eForceGateTimeout:= 4,  // 锁模力段间闸等待超时 | Clamp force gate wait timeout
    eInjectTimeout   := 5,  // 射胶（含熔胶等待）超时 | Injection incl melt wait timeout
    eOpenTimeout     := 6   // 开模超时 | Mold open timeout
);
END_TYPE

FUNCTION_BLOCK FB_DL_InjectionMoldClampSeq
VAR_INPUT
    bStartCmd       : BOOL := FALSE;   // 循环启动命令（电平）[-] | Cycle start command level
    bMoldClosedLim  : BOOL := FALSE;   // 模具合到位限位 [-] | Mold closed limit switch
    bMoldOpenLim    : BOOL := FALSE;   // 模具开到位限位 [-] | Mold open limit switch
    fClampForceAct  : REAL := 0.0;     // 实测锁模力 [kN] | Actual clamp force
    fClampForceMin  : REAL := 500.0;   // 锁模力段间闸下限，域 > 0 [kN] | Clamp force gate threshold
    bMeltReady      : BOOL := FALSE;   // 熔胶计量到位（射胶前置）[-] | Melt metering ready precondition
    fInjPressAct    : REAL := 0.0;     // 实测射胶压力 [bar] | Actual injection pressure
    fInjPressSp     : REAL := 800.0;   // 射胶压力切换点设定，域 > 0 [bar] | Injection switchover pressure setpoint
    tClampLpTimeout : TIME := T#10S;   // 低压护模允许时长，域 > T#0S | LP protect allow time
    tClampHpTimeout : TIME := T#5S;    // 高压锁模允许时长，域 > T#0S | HP clamp allow time
    tForceGateWait  : TIME := T#5S;    // 锁模力闸等待超时，域 > T#0S | Force gate wait timeout
    tInjectTimeout  : TIME := T#15S;   // 射胶允许时长，域 > T#0S | Injection allow time
    tHoldTime       : TIME := T#8S;    // 保压时长，域 > T#0S | Hold duration
    tCoolTime       : TIME := T#30S;   // 冷却时长，域 > T#0S | Cooling duration
    tOpenTimeout    : TIME := T#15S;   // 开模允许时长，域 > T#0S | Open allow time
    bCycleAbort     : BOOL := FALSE;   // 循环中止命令（电平）[-] | Cycle abort command level
    bReset          : BOOL := FALSE;   // 复位命令，上升沿清故障 [-] | Reset command, rising edge
END_VAR
VAR_OUTPUT
    bClampFwd  : BOOL;                 // 合模输出（低压+高压段）[-] | Clamp forward output
    bClampHigh : BOOL;                 // 高压锁模输出 [-] | High-pressure clamp output
    bInjectOut : BOOL;                 // 射胶输出 [-] | Injection output
    bHoldOut   : BOOL;                 // 保压输出 [-] | Hold output
    bCoolOut   : BOOL;                 // 冷却输出 [-] | Cooling output
    bOpenOut   : BOOL;                 // 开模输出 [-] | Open output
    bCycleDone : BOOL;                 // 循环完成单拍脉冲 [-] | Cycle done one-shot pulse
    uCycleCnt  : UDINT;                // 完成循环计数 [次] | Completed cycle count
    eState     : E_DL_IcsPhase;        // 相位出口 | Phase outlet
    eCause     : E_DL_IcsCause;        // 故障成因出口 | Fault cause outlet
    bError     : BOOL;                 // 故障锁存标志 [-] | Fault latch flag
    nErrId     : UDINT;                // 事件码，0 = 无事件 | Event code, 0 = none
END_VAR
VAR
    _eState    : E_DL_IcsPhase := E_DL_IcsPhase.eIdle;    // 内部相位（CASE 唯一写入目标） | Internal phase
    _eCause    : E_DL_IcsCause := E_DL_IcsCause.eNone;    // 成因锁存 | Latched cause
    _bFault    : BOOL;                 // 故障锁存位 | Fault latch bit
    _bAbort    : BOOL;                 // 中止撤离标记（eOpen 相区分出口）[-] | Abort evacuation flag
    _bCfgBad   : BOOL;                 // 组态非法当拍量 [-] | Illegal configuration
    _uInfo     : UDINT;                // 信息码每拍重算 | Info code per scan
    _uCycleCnt : UDINT;                // 循环计数锁存量 [次] | Cycle count latch
    rtStart    : R_TRIG;               // 启动沿实例，段 0 无条件刷新 | Start edge
    rtReset    : R_TRIG;               // 复位沿实例，段 0 无条件刷新 | Reset edge
    rtDone     : R_TRIG;               // 完成相沿实例（单拍化），段 0 无条件刷新 | Done phase edge for one-shot
    tonClampLp : TON;                  // 低压护模计时，段 0 无条件刷新 | LP protect timer
    tonClampHp : TON;                  // 高压锁模计时，段 0 无条件刷新 | HP clamp timer
    tonForce   : TON;                  // 锁模力闸等待计时，段 0 无条件刷新 | Force gate wait timer
    tonInject  : TON;                  // 射胶计时，段 0 无条件刷新 | Injection timer
    tonHold    : TON;                  // 保压计时，段 0 无条件刷新 | Hold timer
    tonCool    : TON;                  // 冷却计时，段 0 无条件刷新 | Cooling timer
    tonOpen    : TON;                  // 开模计时，段 0 无条件刷新 | Open timer
END_VAR
VAR CONSTANT
    DL_ICS_CNT_MAX : UDINT := 16#FFFF_FFFE;   // 计数饱和上限（留加 1 裕度）[次] | Count saturation limit
END_VAR

(* —— 段 0：当拍量派生 + 定时器与沿实例无条件周期刷新（R7 红线） —— *)
_bCfgBad := (tClampLpTimeout <= T#0S) OR (tClampHpTimeout <= T#0S) OR (tForceGateWait <= T#0S)
         OR (tInjectTimeout <= T#0S) OR (tHoldTime <= T#0S) OR (tCoolTime <= T#0S)
         OR (tOpenTimeout <= T#0S) OR (fClampForceMin <= 0.0) OR (fInjPressSp <= 0.0);  // 组态域闸 / Configuration gate
rtStart(CLK := bStartCmd);                                          // 启动沿每拍必调 / Start edge every scan
rtReset(CLK := bReset);                                             // 复位沿每拍必调 / Reset edge every scan
rtDone(CLK := (_eState = E_DL_IcsPhase.eDone));                     // 完成相沿每拍必调（单拍化） / Done edge every scan
tonClampLp(IN := (_eState = E_DL_IcsPhase.eClampLp), PT := tClampLpTimeout);   // 护模计时 / LP protect timing
tonClampHp(IN := (_eState = E_DL_IcsPhase.eClampHp), PT := tClampHpTimeout);   // 锁模计时 / HP clamp timing
tonForce(IN := (_eState = E_DL_IcsPhase.eClampHp) AND bMoldClosedLim AND (fClampForceAct < fClampForceMin), PT := tForceGateWait); // 力闸等待 / Force gate wait timing
tonInject(IN := (_eState = E_DL_IcsPhase.eInject), PT := tInjectTimeout);      // 射胶计时 / Injection timing
tonHold(IN := (_eState = E_DL_IcsPhase.eHold), PT := tHoldTime);               // 保压计时 / Hold timing
tonCool(IN := (_eState = E_DL_IcsPhase.eCool), PT := tCoolTime);               // 冷却计时 / Cooling timing
tonOpen(IN := (_eState = E_DL_IcsPhase.eOpen), PT := tOpenTimeout);            // 开模计时 / Open timing

(* —— 段 1：单拍量预清零（锁存量不入清单） —— *)
_uInfo := 16#0000_0000;                                             // 信息码每拍重算 / Info recomputed per scan
bCycleDone := rtDone.Q;                                             // 完成单拍出口（R_TRIG 单拍化） / Done one-shot outlet

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q AND (NOT _bCfgBad) THEN                                // 复位沿且组态合法 / Reset with legal config
    _bFault := FALSE;                                               // 清故障锁存位 / Clear fault latch
    _eCause := E_DL_IcsCause.eNone;                                 // 清成因 / Clear cause
    IF _eState = E_DL_IcsPhase.eFault THEN
        _eState := E_DL_IcsPhase.eIdle;                             // 故障相迁出唯一路径 / Sole fault exit
    END_IF
END_IF
IF _bCfgBad THEN                                                    // 组态域闸 / Configuration gate
    _bFault := TRUE;                                                // 置故障锁存 / Latch fault
    _eCause := E_DL_IcsCause.eCfgIllegal;                           // 归因组态 / Cause: config
END_IF

(* —— 段 3：中止优先拦截（安全撤离不置故障） —— *)
IF (NOT _bFault) AND bCycleAbort
   AND ((_eState = E_DL_IcsPhase.eClampLp) OR (_eState = E_DL_IcsPhase.eClampHp)
     OR (_eState = E_DL_IcsPhase.eInject)  OR (_eState = E_DL_IcsPhase.eHold)
     OR (_eState = E_DL_IcsPhase.eCool)) THEN
    _bAbort := TRUE;                                                // 中止标记置位（eOpen 出口区分） / Abort flag set
    _eState := E_DL_IcsPhase.eOpen;                                 // 直接进入开模安全撤离 / Enter open for safe evacuation
END_IF

(* —— 段 4：相位机（ENUM + CASE，ELSE 兜底） —— *)
CASE _eState OF

E_DL_IcsPhase.eIdle:
    IF rtStart.Q AND bMoldOpenLim AND (NOT _bFault) THEN
        _bAbort := FALSE;                                           // 新循环清中止标记 / Clear abort flag for new cycle
        _eState := E_DL_IcsPhase.eClampLp;                          // 开到位才允许启动 / Start only from fully open
    END_IF

E_DL_IcsPhase.eClampLp:
    IF _bFault THEN
        _eState := E_DL_IcsPhase.eFault;                            // 故障即时迁出 / Leave on fault
    ELSIF bMoldClosedLim THEN
        _eState := E_DL_IcsPhase.eClampHp;                          // 护模段合到位转高压 / Closed, switch to HP clamp
    ELSIF tonClampLp.Q THEN
        _bFault := TRUE;                                            // 护模超时出口（模具障碍） / LP protect timeout exit
        _eCause := E_DL_IcsCause.eClampLpTimeout;
        _eState := E_DL_IcsPhase.eFault;
    END_IF

E_DL_IcsPhase.eClampHp:
    IF _bFault THEN
        _eState := E_DL_IcsPhase.eFault;                            // 故障即时迁出 / Leave on fault
    ELSIF bMoldClosedLim AND (fClampForceAct >= fClampForceMin) THEN
        _eState := E_DL_IcsPhase.eInject;                           // 锁模力段间闸放行（边界①）/ Force gate passes, inject allowed
    ELSIF tonClampHp.Q AND (NOT bMoldClosedLim) THEN
        _bFault := TRUE;                                            // 锁模超时（未合到位） / HP clamp timeout, not closed
        _eCause := E_DL_IcsCause.eClampHpTimeout;
        _eState := E_DL_IcsPhase.eFault;
    ELSIF tonForce.Q THEN
        _bFault := TRUE;                                            // 力闸等待超时（含 NaN 挂窗路径，边界②）/ Force gate wait timeout
        _eCause := E_DL_IcsCause.eForceGateTimeout;
        _eState := E_DL_IcsPhase.eFault;
    END_IF

E_DL_IcsPhase.eInject:
    IF _bFault THEN
        _eState := E_DL_IcsPhase.eFault;                            // 故障即时迁出 / Leave on fault
    ELSIF fInjPressAct >= fInjPressSp THEN
        _eState := E_DL_IcsPhase.eHold;                             // 压力到切换点转保压 / Pressure at switchover, hold
    ELSIF tonInject.Q THEN
        _bFault := TRUE;                                            // 射胶超时（含熔胶未到位等待） / Injection timeout
        _eCause := E_DL_IcsCause.eInjectTimeout;
        _eState := E_DL_IcsPhase.eFault;
    END_IF

E_DL_IcsPhase.eHold:
    IF _bFault THEN
        _eState := E_DL_IcsPhase.eFault;                            // 故障即时迁出 / Leave on fault
    ELSIF tonHold.Q THEN
        _eState := E_DL_IcsPhase.eCool;                             // 保压时间到转冷却 / Hold elapsed, cool
    END_IF

E_DL_IcsPhase.eCool:
    IF _bFault THEN
        _eState := E_DL_IcsPhase.eFault;                            // 故障即时迁出 / Leave on fault
    ELSIF tonCool.Q THEN
        _eState := E_DL_IcsPhase.eOpen;                             // 冷却时间到开模 / Cool elapsed, open
    END_IF

E_DL_IcsPhase.eOpen:
    IF bMoldOpenLim THEN
        IF _bAbort THEN
            _uInfo := 16#0005_04DB;                                 // 信息级：中止撤离完成 / Info: abort evacuation done
            _bAbort := FALSE;                                       // 清中止标记 / Clear abort flag
            _eState := E_DL_IcsPhase.eIdle;                         // 撤离完成回待机（不计数） / Evacuated, no count
        ELSE
            _eState := E_DL_IcsPhase.eDone;                         // 正常开到位进完成相 / Normal open done
        END_IF
    ELSIF tonOpen.Q THEN
        _bFault := TRUE;                                            // 开模超时 / Open timeout
        _eCause := E_DL_IcsCause.eOpenTimeout;
        _eState := E_DL_IcsPhase.eFault;
    END_IF

E_DL_IcsPhase.eDone:
    IF _uCycleCnt < DL_ICS_CNT_MAX THEN
        _uCycleCnt := _uCycleCnt + 1;                               // 完成计数递增（本相仅驻留一拍） / Count increment, one-scan phase
    END_IF
    _uInfo := 16#0005_04DA;                                         // 信息级：循环完成台账 / Info: cycle done ledger
    _eState := E_DL_IcsPhase.eIdle;                                 // 完成即回待机（bCycleDone 由 rtDone 单拍化） / Back to idle, one-shot via rtDone

E_DL_IcsPhase.eFault:
    ;                                                               // 仅段 2 复位沿可迁出 / Only reset edge leaves

ELSE
    _bFault := TRUE;                                                // 非法相位兜底（R6）/ Illegal phase fallback
    _eCause := E_DL_IcsCause.eCfgIllegal;                           // 归因归并组态 / Cause folded to config
    _eState := E_DL_IcsPhase.eFault;

END_CASE

(* —— 段 5：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_IcsPhase.eFault) THEN
    _eState := E_DL_IcsPhase.eFault;                                // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
bClampFwd  := (_eState = E_DL_IcsPhase.eClampLp) OR (_eState = E_DL_IcsPhase.eClampHp);  // 合模输出两段 / Clamp output both segments
bClampHigh := (_eState = E_DL_IcsPhase.eClampHp);               // 高压输出 / HP output
bInjectOut := (_eState = E_DL_IcsPhase.eInject);                // 射胶输出 / Injection output
bHoldOut   := (_eState = E_DL_IcsPhase.eHold);                  // 保压输出 / Hold output
bCoolOut   := (_eState = E_DL_IcsPhase.eCool);                  // 冷却输出 / Cooling output
bOpenOut   := (_eState = E_DL_IcsPhase.eOpen);                  // 开模输出 / Open output
uCycleCnt  := _uCycleCnt;                                       // 计数镜像（锁存回放） / Count mirror
eState     := _eState;                                          // 相位出口 / Phase outlet
eCause     := _eCause;                                          // 成因出口 / Cause outlet
bError     := _bFault;                                          // 故障标志同源 / Error flag from latch
IF _bFault THEN
    nErrId := 16#0005_03B7;                                     // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                           // 信息码 / Info code
END_IF

END_FUNCTION_BLOCK
