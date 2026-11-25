(*
  道莅工业代码库 | DL_Device | FB_DL_BurnerFlameGuard
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  开源溯源: self-cleanroom（无外部来源；行业池·热工安全通用语义，零代码行复制）
  功能: 燃烧器火焰安全监督——吹扫→点火→火焰建立→运行联锁锁定状态机；点火失败/
        建立失败/运行火焰丢失/联锁丧失均故障锁存并立即关阀，故障相执行安全后吹扫。
  兼容性: CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；仅依赖标准 TON / R_TRIG，零厂商私有库
  接口: 输入 bStartCmd/bFlameOk/bInterlockOk/五段定时组态/bReset；输出 bPurgeOut/
        bIgnitionOut/bMainGasOut/bBurnerRun/bSafeShutdown/eState/eCause/bError/nErrId。
        本件无硬件地址依赖，阀与风机输出由上层映射到 %Q。
  码表: 16#0003_031C 故障级：燃烧安全总码（锁存至 bReset 上升沿，归因由 eCause 承载）
        16#0003_040D 信息级：故障相安全后吹扫完成（后吹扫窗到，风机关闭）
        码段说明：0003 段故障子带 03xx / 信息子带 04xx，槽位经全库实扫空闲。
  边界: ① 运行相主燃气阀输出挂 bFlameOk 电平直断——火焰丢失立即关阀，
        锁存经 tFlameLossTol 去抖窗确认（容忍窗内恢复则继续运行）；
        ② 吹扫相检测到火焰信号视作火焰探测器故障（吹扫必须无火）；
        ③ 待机相启动命令而联锁未就绪：拒绝启动（停留在 eIdle），不置故障；
        ④ 六个 TON + 两个 R_TRIG 实例段 0 无条件周期刷新（R7 红线）；
        ⑤ 故障解除唯一路径 = bReset 上升沿 ∧ 组态合法；⑥ 零全局耦合（无 GVL / 无 %I/%Q）。
  邻件比对: registry 扫查 burner/flame 零命中（R75 §3 留痕），无属主。
  修订历史: 2026-11-23 v1.0.0 R75 首版（复杂件批 B1 · C01）
*)

TYPE E_DL_BfgPhase :
(
    eIdle      := 0,   // 待机 | Idle
    ePurge     := 10,  // 前吹扫 | Pre-purge
    eIgnition  := 20,  // 点火试燃 | Ignition trial
    eEstablish := 30,  // 火焰建立确认 | Flame establish confirm
    eRun       := 40,  // 运行联锁锁定 | Run interlocked
    eShutdown  := 50,  // 正常停机后吹扫 | Normal post-purge
    eFault     := 90   // 故障锁存相（含安全后吹扫） | Fault latch phase with post-purge
);
END_TYPE

TYPE E_DL_BfgCause :
(
    eNone          := 0,  // 无故障 | No cause
    eCfgIllegal    := 1,  // 定时组态非法 | Illegal timer configuration
    eInterlock     := 2,  // 联锁条件丧失 | Interlock lost
    eFlameDetPurge := 3,  // 吹扫相火焰信号误现（探测器故障） | Flame signal seen during purge
    eIgnFail       := 4,  // 点火试燃窗内未建立火焰 | No flame in ignition window
    eEstablishFail := 5,  // 建立确认窗内火焰丢失 | Flame lost in establish window
    eFlameLoss     := 6   // 运行相火焰丢失 | Flame loss in run phase
);
END_TYPE

FUNCTION_BLOCK FB_DL_BurnerFlameGuard
VAR_INPUT
    bStartCmd      : BOOL := FALSE;   // 启动命令（电平，自持由上层实现）[-] | Start command level, latching by caller
    bFlameOk       : BOOL := FALSE;   // 火焰检测信号，TRUE=有火 [-] | Flame detector signal, TRUE = flame present
    bInterlockOk   : BOOL := FALSE;   // 联锁总条件（风压/气压/限位外部汇总）[-] | Interlock aggregate from field devices
    tPurgeTime     : TIME := T#60S;   // 前吹扫时长，域 > T#0S | Pre-purge duration
    tIgniteTime    : TIME := T#5S;    // 点火试燃时长，域 > T#0S | Ignition trial duration
    tEstablishTime : TIME := T#10S;   // 火焰建立确认窗，域 > T#0S | Flame establish window
    tPostPurge     : TIME := T#30S;   // 停机/故障后吹扫时长，域 > T#0S | Post-purge duration
    tFlameLossTol  : TIME := T#1S;    // 运行相火焰丢失容忍去抖，域 >= T#0S | Flame loss debounce in run
    bReset         : BOOL := FALSE;   // 复位命令，上升沿清故障 [-] | Reset command, rising edge clears fault
END_VAR
VAR_OUTPUT
    bPurgeOut     : BOOL;              // 吹扫/后吹扫风机输出 [-] | Purge air fan output
    bIgnitionOut  : BOOL;              // 点火输出（火花+引燃气）[-] | Ignition output, spark and pilot
    bMainGasOut   : BOOL;              // 主燃气阀输出（运行相挂火焰信号直断）[-] | Main gas valve output, gated by flame signal
    bBurnerRun    : BOOL;              // 燃烧运行中 [-] | Burner running
    bSafeShutdown : BOOL;              // 安全停机/故障锁存中 [-] | Safe shutdown or fault latched
    eState        : E_DL_BfgPhase;     // 相位出口 | Phase outlet
    eCause        : E_DL_BfgCause;     // 故障成因出口 | Fault cause outlet
    bError        : BOOL;              // 故障锁存标志 [-] | Fault latch flag
    nErrId        : UDINT;             // 事件码，0 = 无事件 | Event code, 0 = none
END_VAR
VAR
    _eState      : E_DL_BfgPhase := E_DL_BfgPhase.eIdle;   // 内部相位（CASE 唯一写入目标） | Internal phase, single write target
    _eCause      : E_DL_BfgCause := E_DL_BfgCause.eNone;   // 故障成因锁存 | Latched fault cause
    _bFault      : BOOL;            // 故障锁存位 | Fault latch bit
    _bPostDone   : BOOL;            // 故障相后吹扫完成保持 | Post-purge done hold in fault phase
    _bCfgBad     : BOOL;            // 组态非法当拍量 [-] | Illegal configuration this scan
    _uInfo       : UDINT;           // 信息码每拍重算 | Info code recomputed per scan
    rtStart      : R_TRIG;          // 启动沿实例，段 0 无条件刷新 | Start edge instance
    rtReset      : R_TRIG;          // 复位沿实例，段 0 无条件刷新 | Reset edge instance
    tonPurge     : TON;             // 前吹扫计时，段 0 无条件刷新 | Pre-purge timer
    tonIgnite    : TON;             // 点火试燃计时，段 0 无条件刷新 | Ignition timer
    tonEstablish : TON;             // 建立确认计时，段 0 无条件刷新 | Establish timer
    tonFlameLoss : TON;             // 运行相火焰丢失去抖，段 0 无条件刷新 | Flame loss debounce timer
    tonPostPurge : TON;             // 后吹扫计时（正常停机与故障相共用），段 0 无条件刷新 | Post-purge timer shared by shutdown and fault
END_VAR

(* —— 段 0：当拍量派生 + 定时器与沿实例无条件周期刷新（R7 红线） —— *)
_bCfgBad := (tPurgeTime <= T#0S) OR (tIgniteTime <= T#0S) OR (tEstablishTime <= T#0S)
         OR (tPostPurge <= T#0S) OR (tFlameLossTol < T#0S);                 // 定时组态域闸 / Timer configuration gate
rtStart(CLK := bStartCmd);                                                  // 启动沿每拍必调 / Start edge every scan
rtReset(CLK := bReset);                                                     // 复位沿每拍必调 / Reset edge every scan
tonPurge(IN := (_eState = E_DL_BfgPhase.ePurge), PT := tPurgeTime);         // 吹扫计时 / Pre-purge timing
tonIgnite(IN := (_eState = E_DL_BfgPhase.eIgnition), PT := tIgniteTime);    // 点火计时 / Ignition timing
tonEstablish(IN := (_eState = E_DL_BfgPhase.eEstablish), PT := tEstablishTime); // 建立计时 / Establish timing
tonFlameLoss(IN := (_eState = E_DL_BfgPhase.eRun) AND (NOT bFlameOk), PT := tFlameLossTol); // 火焰丢失去抖 / Flame loss debounce
tonPostPurge(IN := (_eState = E_DL_BfgPhase.eShutdown) OR (_eState = E_DL_BfgPhase.eFault), PT := tPostPurge); // 后吹扫 / Post-purge timing

(* —— 段 1：单拍量预清零（锁存量不入清单） —— *)
_uInfo := 16#0000_0000;                                                     // 信息码每拍重算 / Info recomputed per scan

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q AND (NOT _bCfgBad) THEN                                        // 复位沿且组态合法 / Reset edge with legal config
    _bFault    := FALSE;                                                    // 清故障锁存位 / Clear fault latch bit
    _eCause    := E_DL_BfgCause.eNone;                                      // 清成因 / Clear cause
    _bPostDone := FALSE;                                                    // 清后吹扫完成保持 / Clear post-purge hold
    IF _eState = E_DL_BfgPhase.eFault THEN
        _eState := E_DL_BfgPhase.eIdle;                                     // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                            // 组态域闸 / Configuration gate
    _bFault := TRUE;                                                        // 置故障锁存 / Latch fault
    _eCause := E_DL_BfgCause.eCfgIllegal;                                   // 归因组态非法 / Cause: illegal config
END_IF

(* —— 段 3：相位机（ENUM + CASE，ELSE 兜底） —— *)
CASE _eState OF

E_DL_BfgPhase.eIdle:
    IF rtStart.Q AND bInterlockOk AND (NOT _bFault) THEN
        _eState := E_DL_BfgPhase.ePurge;                                    // 联锁就绪进入前吹扫 / Interlock ready, enter purge
    END_IF                                                                  // 联锁未就绪拒绝启动：停留待机不置故障 / Start refused if interlock not ready

E_DL_BfgPhase.ePurge:
    IF _bFault THEN
        _eState := E_DL_BfgPhase.eFault;                                    // 故障即时迁出 / Leave on fault
    ELSIF NOT bInterlockOk THEN
        _bFault := TRUE;                                                    // 联锁丧失锁存 / Interlock lost latch
        _eCause := E_DL_BfgCause.eInterlock;                                // 归因联锁 / Cause: interlock
        _eState := E_DL_BfgPhase.eFault;
    ELSIF bFlameOk THEN
        _bFault := TRUE;                                                    // 吹扫相见火 = 探测器故障 / Flame in purge = detector fault
        _eCause := E_DL_BfgCause.eFlameDetPurge;                            // 归因探测器 / Cause: flame detector
        _eState := E_DL_BfgPhase.eFault;
    ELSIF tonPurge.Q THEN
        _eState := E_DL_BfgPhase.eIgnition;                                 // 吹扫完成进入点火 / Purge done, ignition trial
    END_IF

E_DL_BfgPhase.eIgnition:
    IF _bFault THEN
        _eState := E_DL_BfgPhase.eFault;                                    // 故障即时迁出 / Leave on fault
    ELSIF NOT bInterlockOk THEN
        _bFault := TRUE;                                                    // 联锁丧失锁存 / Interlock lost latch
        _eCause := E_DL_BfgCause.eInterlock;
        _eState := E_DL_BfgPhase.eFault;
    ELSIF bFlameOk THEN
        _eState := E_DL_BfgPhase.eEstablish;                                // 提前建火提前确认 / Early flame, early establish
    ELSIF tonIgnite.Q THEN
        _bFault := TRUE;                                                    // 点火失败锁存 / Ignition failure latch
        _eCause := E_DL_BfgCause.eIgnFail;                                  // 归因点火 / Cause: ignition fail
        _eState := E_DL_BfgPhase.eFault;
    END_IF

E_DL_BfgPhase.eEstablish:
    IF _bFault THEN
        _eState := E_DL_BfgPhase.eFault;                                    // 故障即时迁出 / Leave on fault
    ELSIF NOT bInterlockOk THEN
        _bFault := TRUE;                                                    // 联锁丧失锁存 / Interlock lost latch
        _eCause := E_DL_BfgCause.eInterlock;
        _eState := E_DL_BfgPhase.eFault;
    ELSIF NOT bFlameOk THEN
        _bFault := TRUE;                                                    // 建立窗内火焰丢失 / Flame lost in establish window
        _eCause := E_DL_BfgCause.eEstablishFail;                            // 归因建立失败 / Cause: establish fail
        _eState := E_DL_BfgPhase.eFault;
    ELSIF tonEstablish.Q THEN
        _eState := E_DL_BfgPhase.eRun;                                      // 火焰稳定进入运行锁定 / Flame stable, run interlocked
    END_IF

E_DL_BfgPhase.eRun:
    IF NOT bInterlockOk THEN
        _bFault := TRUE;                                                    // 运行相联锁丧失立即锁存 / Interlock lost in run, immediate latch
        _eCause := E_DL_BfgCause.eInterlock;
        _eState := E_DL_BfgPhase.eFault;
    ELSIF tonFlameLoss.Q THEN
        _bFault := TRUE;                                                    // 火焰丢失超容忍窗锁存 / Flame loss beyond tolerance latch
        _eCause := E_DL_BfgCause.eFlameLoss;                                // 归因火焰丢失 / Cause: flame loss
        _eState := E_DL_BfgPhase.eFault;
    ELSIF NOT bStartCmd THEN
        _eState := E_DL_BfgPhase.eShutdown;                                 // 正常停机命令进入后吹扫 / Normal stop, post-purge
    END_IF                                                                  // 容忍窗内火焰恢复则继续运行（主燃气阀已挂 bFlameOk 电平） / Recovery inside tolerance keeps running

E_DL_BfgPhase.eShutdown:
    IF tonPostPurge.Q THEN
        _eState := E_DL_BfgPhase.eIdle;                                     // 后吹扫完成回待机 / Post-purge done, back to idle
    END_IF                                                                  // 停机后吹扫期间不判联锁（燃气已关） / Interlock not judged during post-purge, gas closed

E_DL_BfgPhase.eFault:
    IF tonPostPurge.Q AND (NOT _bPostDone) THEN
        _bPostDone := TRUE;                                                 // 故障相后吹扫完成保持 / Post-purge done hold
        _uInfo := 16#0003_040D;                                             // 信息级：安全后吹扫完成 / Info: safe post-purge done
    END_IF                                                                  // 迁出唯一路径 = 段 2 复位沿 / Sole exit is reset edge in segment 2

ELSE
    _bFault := TRUE;                                                        // 非法相位兜底（R6）/ Illegal phase fallback
    _eCause := E_DL_BfgCause.eCfgIllegal;                                   // 归因归并组态 / Cause folded to config
    _eState := E_DL_BfgPhase.eFault;

END_CASE

(* —— 段 4：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_BfgPhase.eFault) THEN
    _eState := E_DL_BfgPhase.eFault;                                        // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：出口单点映射（名实同源；安全侧直断） —— *)
bPurgeOut := (_eState = E_DL_BfgPhase.ePurge)
          OR (_eState = E_DL_BfgPhase.eIgnition)
          OR (_eState = E_DL_BfgPhase.eEstablish)
          OR (_eState = E_DL_BfgPhase.eShutdown)
          OR ((_eState = E_DL_BfgPhase.eFault) AND (NOT _bPostDone));       // 风机：吹扫各相 + 故障相未完成段 / Fan in purge phases and unfinished fault purge
bIgnitionOut := ((_eState = E_DL_BfgPhase.eIgnition)
              OR (_eState = E_DL_BfgPhase.eEstablish)) AND (NOT _bFault);   // 点火输出故障即断 / Ignition cut on fault
bMainGasOut := ((_eState = E_DL_BfgPhase.eEstablish)
             OR (_eState = E_DL_BfgPhase.eRun))
             AND (NOT _bFault) AND bFlameOk AND bInterlockOk;               // 主燃气阀挂火焰电平直断（边界①）/ Main gas gated by flame level directly
bBurnerRun := (_eState = E_DL_BfgPhase.eRun) AND (NOT _bFault);             // 运行镜像 / Run mirror
bSafeShutdown := _bFault;                                                   // 安全停机镜像（名实双出口 R191）/ Safe shutdown mirror
eState := _eState;                                                          // 相位出口 / Phase outlet
eCause := _eCause;                                                          // 成因出口 / Cause outlet
bError := _bFault;                                                          // 故障标志同源 / Error flag from latch
IF _bFault THEN
    nErrId := 16#0003_031C;                                                 // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                       // 信息码 / Info code
END_IF

END_FUNCTION_BLOCK
