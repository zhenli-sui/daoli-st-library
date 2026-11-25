// FB_DL_PotlineAnodeChangeSeq v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 换极十相顺控：IDLE→APPROACH→UNCLAMP→LIFT→WITHDRAW→NEWANODE→CLAMP→COVER→VERIFY→IDLE。
        联锁①LIFT 相必须 xClampOpened，违例锁存；②COVER 仅在 xClampClosed 后允许（CLAMP 后才可 COVER）；
        ③VERIFY 相阳极电流低于目标持续 30 s → 故障「新极未导通」；④FAULT 相执行器全清并锁存，仅 xReset 解除。
        fCycleS 用于相位驻留累计 _fPhaseElapsed，作 TON 之外的冗余超时判据（VERIFY 相 35 s 二次确认）。
  邻件: 与打壳机 FC_DL_PotlineCrustBreakerEnergyCalc、母线 FC_DL_PotlineBusbarShuntCalc 同族但为顺控件，不调用任何 FC。
  码表: 9321 入参非有限｜9322 组态非法(fCycleS/fCurrentTargetKA≤0)｜9323 相超时(30/10/20/30/10/60 s)
        9323 相超时（各相通用）｜9324 新极未导通｜9325 联锁违例｜9326 非法相位落 ELSE 兜底｜9327 信息级换极完成。故障码锁存至 xReset 上升沿。
  边界: 无方法块/无属性块/无全局变量/无物理 IO 地址；七 TON 单相独占且无条件刷新；xClampCmd 仅两态（TRUE 夹紧）。
*)
TYPE E_DL_AnodeChangePhase :
(
    IDLE     := 0,      // 空闲：等换极指令 [-] / Idle, waiting change command
    APPROACH := 10,     // 对位：天车移向目标槽位 [-] / Crane approaching cell
    UNCLAMP  := 20,     // 松卡具：等卡具打开反馈 [-] / Unclamping
    LIFT     := 30,     // 提极：提升残极 [-] / Lifting spent anode
    WITHDRAW := 40,     // 移出：残极移出槽位 [-] / Withdrawing anode
    NEWANODE := 50,     // 装新极：等新极就位反馈 [-] / New anode positioning
    CLAMP    := 60,     // 紧卡具：等卡具闭合反馈 [-] / Clamping
    COVER    := 70,     // 覆盖：铺保温料 [-] / Covering with crust
    VERIFY   := 80,     // 确认：新极电流导通确认 [-] / Verifying conduction
    FAULT    := 90      // 故障：锁存，仅复位沿可出 [-] / Fault latched
);
END_TYPE
FUNCTION_BLOCK FB_DL_PotlineAnodeChangeSeq
VAR_INPUT
    xEnable          : BOOL := FALSE;   // 使能，FALSE 时冻结在 IDLE [-] / Enable gate
    xStart           : BOOL := FALSE;   // 换极启动，上升沿有效 [-] / Start rising edge
    xReset           : BOOL := FALSE;   // 复位，上升沿清故障锁存 [-] / Reset rising edge
    xAtPosition      : BOOL := FALSE;   // 天车到位反馈 [-] / Crane in position
    xClampOpened     : BOOL := FALSE;   // 卡具已打开反馈 [-] / Clamp opened
    xClampClosed     : BOOL := FALSE;   // 卡具已闭合反馈 [-] / Clamp closed
    xLiftDone        : BOOL := FALSE;   // 提升完成反馈 [-] / Lift done
    xWithdrawDone    : BOOL := FALSE;   // 移出完成反馈 [-] / Withdraw done
    xNewAnodeReady   : BOOL := FALSE;   // 新极就位反馈 [-] / New anode ready
    xCoverDone       : BOOL := FALSE;   // 覆盖完成反馈 [-] / Cover done
    fAnodeCurrentKA  : REAL := 0.0;     // 实测阳极电流 [kA] / Measured anode current [kA]
    fCurrentTargetKA : REAL := 30.0;    // 目标阳极电流 [kA]，域 > 0 / Target current [kA]
    fCycleS          : REAL := 0.01;    // 任务周期 [s]，域 > 0 / Task cycle time [s]
END_VAR
VAR_OUTPUT
    ePhase       : E_DL_AnodeChangePhase;   // 相位出口，段尾单点映射 [-] / Phase outlet
    xCraneEnable : BOOL;                    // 天车使能（对位至覆盖相为真）[-] / Crane enable
    xClampCmd    : BOOL;                    // 卡具指令 TRUE 夹紧 / FALSE 松开 [-] / Clamp command
    xLiftCmd     : BOOL;                    // 提升指令（仅 LIFT 相）[-] / Lift command
    xWithdrawCmd : BOOL;                    // 移出指令（仅 WITHDRAW 相）[-] / Withdraw command
    xCoverCmd    : BOOL;                    // 覆盖指令（仅 COVER 相）[-] / Cover command
    xDone        : BOOL;                    // 换极完成单拍脉冲 [-] / Done one-shot pulse
    xFault       : BOOL;                    // 故障锁存标志 [-] / Fault latch flag
    uErrorId     : UDINT;                   // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonApproach : TON;                      // 对位相超时 30 s，无条件刷新 / Approach timeout
    tonUnclamp  : TON;                      // 松卡具相超时 10 s，无条件刷新 / Unclamp timeout
    tonLift     : TON;                      // 提升相超时 20 s，无条件刷新 / Lift timeout
    tonWithdraw : TON;                      // 移出相超时 30 s，无条件刷新 / Withdraw timeout
    tonClamp    : TON;                      // 紧卡具相超时 10 s，无条件刷新 / Clamp timeout
    tonVerify   : TON;                      // 导通确认窗 30 s，无条件刷新 / Conduction window
    tonVerifyTo : TON;                      // 确认相总超时 60 s，无条件刷新 / Verify timeout
    tonNewAnode : TON;                      // 新极就位超时 90 s（R92 新增，防无限等待）/ New anode timeout
    tonCover    : TON;                      // 覆盖相超时 120 s（R92 新增，防铺料执行器长通）/ Cover timeout
    rtStart     : R_TRIG;                   // 启动沿实例，无条件刷新 / Start edge instance
    rtReset     : R_TRIG;                   // 复位沿实例，无条件刷新 / Reset edge instance
    _ePhase     : E_DL_AnodeChangePhase := E_DL_AnodeChangePhase.IDLE;  // 内部相位，CASE 唯一写入 / Internal phase
    _ePhasePrev : E_DL_AnodeChangePhase := E_DL_AnodeChangePhase.IDLE;  // 上拍相位快照 [-] / Previous phase snapshot
    _fElapsed   : REAL := 0.0;              // 相位驻留累计 [s]，跨周期驻留量 / Phase dwell accumulator [s]
    _xCrane     : BOOL := FALSE;            // 天车使能内部量 [-] / Internal crane enable
    _xClamp     : BOOL := FALSE;            // 卡具指令内部量 [-] / Internal clamp command
    _xLift      : BOOL := FALSE;            // 提升指令内部量 [-] / Internal lift command
    _xWithdraw  : BOOL := FALSE;            // 移出指令内部量 [-] / Internal withdraw command
    _xCover     : BOOL := FALSE;            // 覆盖指令内部量 [-] / Internal cover command
    _bFault     : BOOL := FALSE;            // 故障锁存位（锁存量，仅复位沿清）/ Latched fault bit
    _uFault     : UDINT := 16#0000;         // 故障码锁存（锁存量，仅复位沿清）/ Latched fault code
    _uInfo      : UDINT := 16#0000;         // 信息码，每拍重算 / Transient info code
END_VAR
// 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内，R7/R188）/ Unconditional refresh
rtStart(CLK := xStart);                                                     // 启动沿每拍必调 / Start edge
rtReset(CLK := xReset);                                                     // 复位沿每拍必调 / Reset edge
tonApproach(IN := (_ePhase = E_DL_AnodeChangePhase.APPROACH), PT := T#30S); // 对位超时 / Approach
tonUnclamp(IN := (_ePhase = E_DL_AnodeChangePhase.UNCLAMP), PT := T#10S);   // 松卡具超时 / Unclamp
tonLift(IN := (_ePhase = E_DL_AnodeChangePhase.LIFT), PT := T#20S);         // 提升超时 / Lift
tonWithdraw(IN := (_ePhase = E_DL_AnodeChangePhase.WITHDRAW), PT := T#30S); // 移出超时 / Withdraw
tonClamp(IN := (_ePhase = E_DL_AnodeChangePhase.CLAMP), PT := T#10S);       // 紧卡具超时 / Clamp
tonVerify(IN := (_ePhase = E_DL_AnodeChangePhase.VERIFY) AND (fAnodeCurrentKA < fCurrentTargetKA), PT := T#30S);
tonVerifyTo(IN := (_ePhase = E_DL_AnodeChangePhase.VERIFY), PT := T#60S);   // 确认相总超时 / Verify timeout
tonNewAnode(IN := (_ePhase = E_DL_AnodeChangePhase.NEWANODE), PT := T#90S);  // 新极就位超时 / New anode
tonCover(IN := (_ePhase = E_DL_AnodeChangePhase.COVER), PT := T#120S);     // 覆盖相超时 / Cover
// 段 1：单拍量与执行器量预清（锁存量 _bFault/_uFault/_fElapsed 不入清单，R187）/ One-shot clear
_uInfo := 16#0000;                  // 信息码每拍重算 / Info code recomputed
xDone := FALSE;                     // 完成脉冲缺省清 / Done pulse clear
_xCrane := FALSE;                   // 天车使能缺省关 / Crane default off
_xClamp := FALSE;                   // 卡具指令缺省松开 / Clamp default open
_xLift := FALSE;                    // 提升指令缺省关 / Lift default off
_xWithdraw := FALSE;                // 移出指令缺省关 / Withdraw default off
_xCover := FALSE;                   // 覆盖指令缺省关 / Cover default off
// 段 2：非有限闸与组态域闸（归因唯一，逐因独立码，R190）/ Gate stage
IF (fAnodeCurrentKA <> fAnodeCurrentKA) OR (fCurrentTargetKA <> fCurrentTargetKA) OR (fCycleS <> fCycleS)
   OR (ABS(fAnodeCurrentKA) >= 3.0E38) OR (ABS(fCurrentTargetKA) >= 3.0E38) OR (ABS(fCycleS) >= 3.0E38) THEN
    _uFault := 16#0002_9321;        // 故障级：入参非有限 / Fault: non-finite input
    _bFault := TRUE;                // 置故障锁存（R45 配对）/ Set fault latch
END_IF
IF (fCurrentTargetKA <= 1.0E-6) OR (fCycleS <= 1.0E-6) THEN
    _uFault := 16#0002_9322;        // 故障级：组态非法 / Fault: illegal configuration
    _bFault := TRUE;                // 置故障锁存（R45 配对）/ Set fault latch
END_IF
// 段 3：相位驻留累计（跨周期驻留量，切换拍清零）/ Phase dwell accumulation
IF _ePhase <> _ePhasePrev THEN
    _fElapsed := 0.0;               // 相位切换清零 / Reset on phase change
    _ePhasePrev := _ePhase;         // 更新快照 / Update snapshot
ELSE
    _fElapsed := _fElapsed + fCycleS;   // 同相累加周期 / Accumulate cycle
END_IF
// 段 4：复位沿（FAULT 唯一解除路径）/ Reset edge, only exit from fault
IF rtReset.Q THEN                   // rtReset.Q = 当拍量 / Reset edge per scan
    IF _ePhase = E_DL_AnodeChangePhase.FAULT THEN
        _ePhase := E_DL_AnodeChangePhase.IDLE;      // 故障相迁出回空闲 / Fault exits to idle
    END_IF
    _fElapsed := 0.0;               // 驻留累计清零（锁存量解除）/ Dwell cleared on reset
    _bFault := FALSE;               // 清故障锁存位（仅此解除沿可清）/ Clear latched bit
    _uFault := 16#0000;             // 清故障锁存码（仅此解除沿可清）/ Clear latched code
END_IF
// 段 5：相位机（本拍合法事件优先于超时，R275）/ Phase machine
CASE _ePhase OF
E_DL_AnodeChangePhase.IDLE:
    IF _bFault THEN
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 聚合故障进故障相 / Enter fault
    ELSIF rtStart.Q AND xEnable THEN
        _ePhase := E_DL_AnodeChangePhase.APPROACH;  // 启动：进对位相 / Start, approach
    END_IF
E_DL_AnodeChangePhase.APPROACH:
    _xCrane := TRUE;                                // 天车使能（同相保持）/ Crane enabled
    IF _bFault THEN
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _ePhase := E_DL_AnodeChangePhase.IDLE;      // 使能撤销回空闲 / Enable dropped
    ELSIF xAtPosition THEN
        _ePhase := E_DL_AnodeChangePhase.UNCLAMP;   // 到位：进松卡具相 / In position, unclamp
    ELSIF tonApproach.Q THEN
        _uFault := 16#0002_9323;                    // 故障级：对位相超时 / Approach timeout
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 进故障相 / Enter fault
    END_IF
E_DL_AnodeChangePhase.UNCLAMP:
    _xCrane := TRUE;                                // 天车使能保持 / Crane enabled
    _xClamp := FALSE;                               // 卡具松开指令 / Clamp open command
    IF _bFault THEN
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _ePhase := E_DL_AnodeChangePhase.IDLE;      // 使能撤销回空闲（安全侧，R92 复裁补）/ Enable dropped
    ELSIF xClampOpened THEN
        _ePhase := E_DL_AnodeChangePhase.LIFT;      // 卡具已开：进提升相 / Opened, lift
    ELSIF tonUnclamp.Q THEN
        _uFault := 16#0002_9323;                    // 故障级：松卡具相超时 / Unclamp timeout
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 进故障相 / Enter fault
    END_IF
E_DL_AnodeChangePhase.LIFT:
    _xCrane := TRUE;                                // 天车使能保持 / Crane enabled
    _xClamp := FALSE;                               // 卡具保持松开 / Clamp stays open
    IF _bFault THEN
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _ePhase := E_DL_AnodeChangePhase.IDLE;      // 使能撤销回空闲（安全侧，R92 复裁补）/ Enable dropped
    ELSIF NOT xClampOpened THEN
        _uFault := 16#0002_9325;                    // 故障级：提升时卡具未开 / Interlock violation
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 进故障相 / Enter fault
    ELSIF xLiftDone THEN
        _ePhase := E_DL_AnodeChangePhase.WITHDRAW;  // 提升完成：进移出相 / Lift done, withdraw
    ELSIF tonLift.Q THEN
        _uFault := 16#0002_9323;                    // 故障级：提升相超时 / Lift timeout
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 进故障相 / Enter fault
    ELSE
        _xLift := TRUE;                             // 提升指令（仅本相）/ Lift command
    END_IF
E_DL_AnodeChangePhase.WITHDRAW:
    _xCrane := TRUE;                                // 天车使能保持 / Crane enabled
    IF _bFault THEN
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _ePhase := E_DL_AnodeChangePhase.IDLE;      // 使能撤销回空闲（安全侧，R92 复裁补）/ Enable dropped
    ELSIF xWithdrawDone THEN
        _ePhase := E_DL_AnodeChangePhase.NEWANODE;  // 移出完成：进新极相 / Withdrawn, new anode
    ELSIF tonWithdraw.Q THEN
        _uFault := 16#0002_9323;                    // 故障级：移出相超时 / Withdraw timeout
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 进故障相 / Enter fault
    ELSE
        _xWithdraw := TRUE;                         // 移出指令（仅本相）/ Withdraw command
    END_IF
E_DL_AnodeChangePhase.NEWANODE:
    _xCrane := TRUE;                                // 天车使能保持 / Crane enabled
    IF _bFault THEN
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _ePhase := E_DL_AnodeChangePhase.IDLE;      // 使能撤销回空闲（安全侧，R92 复裁补）/ Enable dropped
    ELSIF xNewAnodeReady THEN
        _ePhase := E_DL_AnodeChangePhase.CLAMP;     // 新极就位：进紧卡具相 / Ready, clamp
    ELSIF tonNewAnode.Q THEN
        _uFault := 16#0002_9323;                    // 故障级：相超时（新极就位，R92 复裁统一归 9323）/ Phase timeout
        _bFault := TRUE;                            // 置故障锁存 / Set latch
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 进故障相 / Enter fault
    END_IF
E_DL_AnodeChangePhase.CLAMP:
    _xCrane := TRUE;                                // 天车使能保持 / Crane enabled
    _xClamp := TRUE;                                // 卡具夹紧指令 / Clamp close command
    IF _bFault THEN
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _ePhase := E_DL_AnodeChangePhase.IDLE;      // 使能撤销回空闲（安全侧，R92 复裁补）/ Enable dropped
    ELSIF xClampClosed THEN
        _ePhase := E_DL_AnodeChangePhase.COVER;     // 卡具已合：进覆盖相（CLAMP 后才可 COVER）/ Go cover
    ELSIF tonClamp.Q THEN
        _uFault := 16#0002_9323;                    // 故障级：紧卡具相超时 / Clamp timeout
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 进故障相 / Enter fault
    END_IF
E_DL_AnodeChangePhase.COVER:
    _xCrane := TRUE;                                // 天车使能保持 / Crane enabled
    _xClamp := TRUE;                                // 卡具保持夹紧 / Clamp stays closed
    IF _bFault THEN
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _ePhase := E_DL_AnodeChangePhase.IDLE;      // 使能撤销回空闲（安全侧，R92 复裁补）/ Enable dropped
    ELSIF NOT xClampClosed THEN
        _uFault := 16#0002_9325;                    // 故障级：覆盖前卡具未合 / Interlock violation
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 进故障相 / Enter fault
    ELSIF xCoverDone THEN
        _ePhase := E_DL_AnodeChangePhase.VERIFY;    // 覆盖完成：进确认相 / Covered, verify
    ELSIF tonCover.Q THEN
        _uFault := 16#0002_9323;                    // 故障级：相超时（覆盖相，铺料长通，R92 复裁统一归 9323）/ Phase timeout
        _bFault := TRUE;                            // 置故障锁存 / Set latch
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 进故障相 / Enter fault
    ELSE
        _xCover := TRUE;                            // 覆盖指令（仅本相）/ Cover command
    END_IF
E_DL_AnodeChangePhase.VERIFY:
    _xClamp := TRUE;                                // 卡具保持夹紧 / Clamp stays closed
    IF _bFault THEN
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _ePhase := E_DL_AnodeChangePhase.IDLE;      // 使能撤销回空闲（安全侧，R92 复裁补）/ Enable dropped
    ELSIF fAnodeCurrentKA >= fCurrentTargetKA THEN
        xDone := TRUE;                              // 导通确认：完成脉冲单拍 / Conduction confirmed
        _uInfo := 16#0002_9327;                     // 信息级：换极完成 / Info: cycle done
        _ePhase := E_DL_AnodeChangePhase.IDLE;      // 回空闲 / Return to idle
    ELSIF tonVerify.Q OR (_fElapsed > 35.0) THEN
        _uFault := 16#0002_9324;                    // 故障级：新极未导通持续 30 s / Not conducting
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 进故障相 / Enter fault
    ELSIF tonVerifyTo.Q THEN
        _uFault := 16#0002_9323;                    // 故障级：确认相总超时 / Verify timeout
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_AnodeChangePhase.FAULT;     // 进故障相 / Enter fault
    END_IF
E_DL_AnodeChangePhase.FAULT:
    IF rtReset.Q THEN
        _ePhase := E_DL_AnodeChangePhase.IDLE;      // 复位沿解除（段 4 已清锁存）/ Reset releases
    END_IF
ELSE
    _uFault := 16#0002_9326;                        // 故障级：非法相位兜底（唯一占用 9326）/ Illegal phase id
    _bFault := TRUE;                                // 置故障锁存（R45 配对）/ Set latch
    _ePhase := E_DL_AnodeChangePhase.FAULT;         // 强制进故障相 / Force into fault
END_CASE
// 段 6：出口单点映射（名实双出口，R191；故障侧执行器再硬清零）/ Outlet mapping
ePhase := _ePhase;                                  // 相位出口单点映射 / Phase outlet
IF (_ePhase = E_DL_AnodeChangePhase.FAULT) OR _bFault THEN
    xCraneEnable := FALSE;                          // 故障侧天车硬零 / Fault crane hard zero
    xClampCmd := FALSE;                             // 故障侧卡具硬零 / Fault clamp hard zero
    xLiftCmd := FALSE;                              // 故障侧提升硬零 / Fault lift hard zero
    xWithdrawCmd := FALSE;                          // 故障侧移出硬零 / Fault withdraw hard zero
    xCoverCmd := FALSE;                             // 故障侧覆盖硬零 / Fault cover hard zero
    xFault := TRUE;                                 // 故障锁存回放 / Replay latched flag
    uErrorId := _uFault;                            // 故障码锁存回放 / Replay latched code
ELSE
    xCraneEnable := _xCrane;                        // 天车使能出口 / Crane enable outlet
    xClampCmd := _xClamp;                           // 卡具指令出口 / Clamp command outlet
    xLiftCmd := _xLift;                             // 提升指令出口 / Lift command outlet
    xWithdrawCmd := _xWithdraw;                     // 移出指令出口 / Withdraw command outlet
    xCoverCmd := _xCover;                           // 覆盖指令出口 / Cover command outlet
    xFault := FALSE;                                // 无故障 / No fault
    uErrorId := _uInfo;                             // 信息码每拍重算 / Transient info code
END_IF
END_FUNCTION_BLOCK
