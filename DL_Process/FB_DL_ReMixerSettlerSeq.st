(*
  Component : FB_DL_ReMixerSettlerSeq
  Category  : DL_Process
  Function  : 混合澄清槽单级串级状态机：进料→混合→澄清→（界面位越限延长分相）→排料
  Complexity: C4
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 xStart 启动（上升沿启动，下降沿兼作故障复位沿）、xStop 停止、xFeedPermit 进料许可、
             xFeedFlowOk 进料流量正常、xStageBypass 单级故障旁路、rFillPct 充液率 [%]、
             rFillTargetPct 目标充液率 [%]、rFillEmptyPct 排空判定充液率 [%]、rInterfacePct 界面位 [%]、
             rInterfHiPct 界面位上限 [%]、rInterfLoPct 界面位下限 [%]、rMixTimeS 混合时间 [s]、
             rSettleTimeS 澄清时间 [s]、rSepExtendS 分相延长时间 [s]、rFeedTmoS 进料中断超时 [s]、
             rDischTmoS 排料超时 [s]；输出五路独立命令、eState 当前相、xFault/nFaultCode 故障、
             nWarnCode 告警码、xBypassed 旁路生效、xSepExtended 处于延长分相。
  时序     : 同拍双窗配比约束 rSepExtendS ≥ rSettleTimeS（延长窗必须覆盖一个完整澄清窗，否则
             延长窗先生效、界面位尚未回稳即判超时），rFeedTmoS > 0、rDischTmoS > 0、rFillTargetPct > rFillEmptyPct。
  输出语义 : xStageBypass=TRUE 时本级输出全部撤销并停在 IDLE（不视为故障，由 xBypassed 表达）；
             xStop=TRUE 时全部命令撤销并回 IDLE（冻结保持不适用，本件为撤销型停车）。
  复位沿   : 故障码锁存至 xStart 下降沿（主路径）或 xStageBypass 上升（旁路路径），两路径均可达。
  码位     : 9810 进料许可缺失（信息级，不置 xFault）；9811 进料中断超时（故障级）；
             9812 界面位越限不可恢复（故障级）；9813 排料超时（故障级）；9814 参数或输入非法（故障级）。
*)
TYPE E_DL_ReStageState :
(
    IDLE      := 0,    // 待机，全部命令撤销 EN: idle, every command withdrawn
    FEED      := 10,   // 进料充液相 EN: feed and fill phase
    MIX       := 20,   // 混合相传质相 EN: mixing and mass transfer phase
    SETTLE    := 30,   // 澄清分相相 EN: settling and phase separation phase
    PHASE_SEP := 40,   // 界面位越限的延长分相相 EN: extended separation phase after an interface excursion
    DISCHARGE := 50,   // 排料相 EN: discharge phase
    FAULT     := 90    // 故障相，全部命令强制撤销 EN: fault phase, every command forced off
);
END_TYPE

FUNCTION_BLOCK FB_DL_ReMixerSettlerSeq
VAR_INPUT
    xStart         : BOOL;             // 启动（上升沿启动，下降沿复位故障） EN: start on the rising edge, reset the fault on the falling edge
    xStop          : BOOL;             // 停止（任意相生效，撤销全部命令） EN: stop, effective in every phase and withdrawing all commands
    xFeedPermit    : BOOL;             // 进料许可（上游供料就绪） EN: feed permit from the upstream supply
    xFeedFlowOk    : BOOL;             // 进料流量正常（流量开关） EN: the feed flow is normal, taken from the flow switch
    xStageBypass   : BOOL;             // 单级故障旁路（本级退出串级） EN: single stage fault bypass, this stage leaves the cascade
    rFillPct       : REAL;             // 槽内充液率 [%] EN: the filling level of the mixer settler
    rFillTargetPct : REAL := 85.0;     // 目标充液率（进料转混合判据） [%] EN: the target filling level that ends the feed phase
    rFillEmptyPct  : REAL := 5.0;      // 排空判定充液率 [%] EN: the filling level that ends the discharge phase
    rInterfacePct  : REAL;             // 界面位（澄清槽界面高度占比） [%] EN: the interface position as a percentage of the settler height
    rInterfHiPct   : REAL := 60.0;     // 界面位允许上限 [%] EN: the upper allowed interface position
    rInterfLoPct   : REAL := 40.0;     // 界面位允许下限 [%] EN: the lower allowed interface position
    rMixTimeS      : REAL := 300.0;    // 混合时间设定 [s] EN: the mixing time setting
    rSettleTimeS   : REAL := 600.0;    // 澄清时间设定 [s] EN: the settling time setting
    rSepExtendS    : REAL := 600.0;    // 分相延长时间设定 [s] EN: the extension time applied on an interface excursion
    rFeedTmoS      : REAL := 180.0;    // 进料中断超时设定 [s] EN: the feed interruption timeout
    rDischTmoS     : REAL := 300.0;    // 排料超时设定 [s] EN: the discharge timeout
END_VAR
VAR_OUTPUT
    xFeedValveCmd    : BOOL;               // 进料阀命令 EN: the feed valve command
    xMixerCmd        : BOOL;               // 混合搅拌命令 EN: the mixer command
    xSettlePlateCmd  : BOOL;               // 澄清挡板投入命令 EN: the settler plate command
    xDischargeCmd    : BOOL;               // 排料阀命令 EN: the discharge valve command
    eState           : E_DL_ReStageState;  // 当前相 EN: the current phase
    xFault           : BOOL;               // 故障标志（仅故障级码置位） EN: the fault flag, raised by fault class codes only
    nFaultCode       : INT;                // 故障码，锁存回放 EN: the fault code replayed from the latch
    nWarnCode        : INT;                // 告警码（9810 信息级） EN: the warning code, information class
    xBypassed        : BOOL;               // 旁路生效 EN: the bypass is active
    xSepExtended     : BOOL;               // 处于延长分相相 EN: the extended separation phase is active
    rSepElapsedS     : REAL;               // 本次分相已用时间 [s] EN: the separation time elapsed in this cycle
END_VAR
VAR
    tonFeed    : TON;                  // 进料中断超时定时器 EN: the feed interruption timeout
    tonMix     : TON;                  // 混合时间定时器 EN: the mixing timer
    tonSettle  : TON;                  // 澄清时间定时器 EN: the settling timer
    tonSep     : TON;                  // 延长分相总时间定时器 EN: the extended separation total timer
    tonDisch   : TON;                  // 排料超时定时器 EN: the discharge timeout
    fbStartRise: R_TRIG;               // xStart 上升沿（唯一启动沿） EN: the rising edge of xStart, the only start edge
    fbStartFall: F_TRIG;               // xStart 下降沿（主复位沿） EN: the falling edge of xStart, the main reset edge
    fbBypRise  : R_TRIG;               // 旁路上升沿（旁路复位路径） EN: the rising edge of the bypass, the secondary reset path
    xFinAll    : BOOL;                 // 全部浮点入参有限 EN: every floating input is finite
    xFinMix    : BOOL;                 // 混合时间有限 EN: the mixing time is finite
    xParamBad  : BOOL;                 // 参数或输入非法 EN: a parameter or an input is illegal
    xInterfOk  : BOOL;                 // 界面位在允许带内 EN: the interface position is inside the band
    xFillFull  : BOOL;                 // 充液到位 EN: the filling level reached the target
    xFillEmpty : BOOL;                 // 充液已排空 EN: the filling level dropped to the empty limit
    nMsMix     : UDINT := 300000;      // 混合毫秒数（缺省防首拍零 PT） EN: the mixing time in milliseconds, the default avoids a zero preset
    nMsSettle  : UDINT := 600000;      // 澄清毫秒数 EN: the settling time in milliseconds
    nMsSep     : UDINT := 1200000;     // 延长分相毫秒数 EN: the extended separation time in milliseconds
    nMsFeed    : UDINT := 180000;      // 进料超时毫秒数 EN: the feed timeout in milliseconds
    nMsDisch   : UDINT := 300000;      // 排料超时毫秒数 EN: the discharge timeout in milliseconds
    nCodeLatch : INT;                  // 故障码锁存副本 EN: the latched copy of the fault code
END_VAR
VAR CONSTANT
    DL_RMS_Z      : REAL := 0.0;       // 浮点零常量 EN: the floating point zero constant
    DL_RMS_K1000  : REAL := 1000.0;    // 秒转毫秒系数 EN: the second to millisecond factor
    DL_RMS_C_PERM : INT := 9810;       // 进料许可缺失（信息级） EN: the missing feed permit, information class
    DL_RMS_C_FEED : INT := 9811;       // 进料中断超时 EN: the feed interruption timeout
    DL_RMS_C_INTER: INT := 9812;       // 界面位越限不可恢复 EN: the interface excursion is not recoverable
    DL_RMS_C_DISCH: INT := 9813;       // 排料超时 EN: the discharge timeout
    DL_RMS_C_PARAM: INT := 9814;       // 参数或输入非法 EN: a parameter or an input is illegal
END_VAR

// 段1｜参数与采样门禁（先判后用：REAL→UDINT 换算在闸后执行，结果供段2 定时器 PT 使用）
xFinMix := (rMixTimeS = rMixTimeS) AND ((rMixTimeS - rMixTimeS) = DL_RMS_Z);                                     // 混合时间有限性 EN: the mixing time is finite
xFinAll := xFinMix
        AND (rFillPct = rFillPct) AND ((rFillPct - rFillPct) = DL_RMS_Z)
        AND (rFillTargetPct = rFillTargetPct) AND ((rFillTargetPct - rFillTargetPct) = DL_RMS_Z)
        AND (rFillEmptyPct = rFillEmptyPct) AND ((rFillEmptyPct - rFillEmptyPct) = DL_RMS_Z)
        AND (rInterfacePct = rInterfacePct) AND ((rInterfacePct - rInterfacePct) = DL_RMS_Z)
        AND (rInterfHiPct = rInterfHiPct) AND ((rInterfHiPct - rInterfHiPct) = DL_RMS_Z)
        AND (rInterfLoPct = rInterfLoPct) AND ((rInterfLoPct - rInterfLoPct) = DL_RMS_Z)
        AND (rSettleTimeS = rSettleTimeS) AND ((rSettleTimeS - rSettleTimeS) = DL_RMS_Z)
        AND (rSepExtendS = rSepExtendS) AND ((rSepExtendS - rSepExtendS) = DL_RMS_Z)
        AND (rFeedTmoS = rFeedTmoS) AND ((rFeedTmoS - rFeedTmoS) = DL_RMS_Z)
        AND (rDischTmoS = rDischTmoS) AND ((rDischTmoS - rDischTmoS) = DL_RMS_Z);                                 // 全部浮点入参有限性 EN: the finiteness of every floating input
xParamBad := (NOT xFinAll) OR (rMixTimeS <= DL_RMS_Z) OR (rSettleTimeS <= DL_RMS_Z) OR (rSepExtendS < DL_RMS_Z)
          OR (rFeedTmoS <= DL_RMS_Z) OR (rDischTmoS <= DL_RMS_Z)
          OR (rFillTargetPct <= rFillEmptyPct) OR (rFillEmptyPct < DL_RMS_Z)
          OR (rInterfHiPct <= rInterfLoPct);                                                                     // 域闸与配比约束 EN: the domain gate and the ratio constraints
IF NOT xParamBad THEN                                                                                            // 参数合法才做换算 EN: convert only when the parameters are legal
    nMsMix := REAL_TO_UDINT(rMixTimeS * DL_RMS_K1000);                                                           // 混合毫秒数 EN: the mixing milliseconds
    nMsSettle := REAL_TO_UDINT(rSettleTimeS * DL_RMS_K1000);                                                     // 澄清毫秒数 EN: the settling milliseconds
    nMsSep := REAL_TO_UDINT((rSettleTimeS + rSepExtendS) * DL_RMS_K1000);                                        // 延长分相毫秒数（澄清+延长） EN: the extended separation milliseconds
    nMsFeed := REAL_TO_UDINT(rFeedTmoS * DL_RMS_K1000);                                                          // 进料超时毫秒数 EN: the feed timeout milliseconds
    nMsDisch := REAL_TO_UDINT(rDischTmoS * DL_RMS_K1000);                                                        // 排料超时毫秒数 EN: the discharge timeout milliseconds
END_IF
xInterfOk := xFinAll AND (rInterfacePct <= rInterfHiPct) AND (rInterfacePct >= rInterfLoPct);                    // 界面位带内判据 EN: the interface band test
xFillFull := xFinAll AND (rFillPct >= rFillTargetPct);                                                           // 充液到位判据 EN: the fill completion test
xFillEmpty := xFinAll AND (rFillPct <= rFillEmptyPct);                                                           // 排空到位判据 EN: the empty completion test

// 段2｜五只定时器 + 三只边沿实例无条件周期刷新（R7；CASE 内不得调用实例）
tonFeed(IN := (eState = E_DL_ReStageState.FEED) AND (NOT xFeedFlowOk) AND xFeedPermit, PT := UDINT_TO_TIME(nMsFeed));  // 进料中断计时（无许可时暂停，避免关阀被误判中断） EN: time the feed interruption, paused while the permit is absent so a closed valve is not misread as an interruption
tonMix(IN := (eState = E_DL_ReStageState.MIX), PT := UDINT_TO_TIME(nMsMix));                                     // 混合计时 EN: time the mixing phase
tonSettle(IN := (eState = E_DL_ReStageState.SETTLE), PT := UDINT_TO_TIME(nMsSettle));                            // 澄清计时 EN: time the settling phase
tonSep(IN := (eState = E_DL_ReStageState.PHASE_SEP), PT := UDINT_TO_TIME(nMsSep));                               // 延长分相总计时 EN: time the extended separation phase
tonDisch(IN := (eState = E_DL_ReStageState.DISCHARGE), PT := UDINT_TO_TIME(nMsDisch));                            // 排料计时 EN: time the discharge phase
fbStartRise(CLK := xStart);                                                                                      // 启动沿 EN: the start edge
fbStartFall(CLK := xStart);                                                                                      // 复位沿 EN: the reset edge
fbBypRise(CLK := xStageBypass);                                                                                  // 旁路沿 EN: the bypass edge

// 段3｜输出预置（唯一预置点，CASE 内只置位；单拍信息位在此每拍清零）
xFeedValveCmd := FALSE;                                                                                          // 进料阀预置关 EN: preset the feed valve closed
xMixerCmd := FALSE;                                                                                              // 搅拌预置停 EN: preset the mixer off
xSettlePlateCmd := FALSE;                                                                                        // 挡板预置撤 EN: preset the settler plate withdrawn
xDischargeCmd := FALSE;                                                                                          // 排料阀预置关 EN: preset the discharge valve closed
xFault := FALSE;                                                                                                 // 故障标志预置假 EN: preset the fault flag false
nFaultCode := 0;                                                                                                 // 故障码预置零 EN: preset the fault code to zero
nWarnCode := 0;                                                                                                  // 告警码预置零 EN: preset the warning code to zero
xBypassed := xStageBypass;                                                                                       // 旁路状态直映 EN: mirror the bypass input
xSepExtended := FALSE;                                                                                           // 延长分相标志预置假 EN: preset the extension flag false
rSepElapsedS := DL_RMS_Z;                                                                                        // 分相已用时间预置零 [s] EN: preset the separation elapsed time to zero

// 段4｜全局闸：参数非法锁故障；xStop 撤销全部命令并回待机（复位沿作用域见头注释）
IF xParamBad THEN
    nCodeLatch := DL_RMS_C_PARAM;                                                                                // 参数非法锁存 EN: latch the parameter code
    xFault := TRUE;                                                                                              // 置故障标志 EN: raise the fault flag
    nFaultCode := DL_RMS_C_PARAM;                                                                                // 故障码出口 EN: publish the fault code
    eState := E_DL_ReStageState.FAULT;                                                                           // 迁故障相 EN: move to the fault phase
ELSIF xStop AND (eState <> E_DL_ReStageState.IDLE) THEN
    eState := E_DL_ReStageState.IDLE;                                                                            // 撤销型停车回待机 EN: a withdrawing stop returns to idle
END_IF

// 段5｜主状态机（ENUM + CASE，ELSE 兜底非法值）
IF eState <> E_DL_ReStageState.FAULT THEN
CASE eState OF
E_DL_ReStageState.IDLE:
    // 拍 N：待机；旁路时禁止启动（本级退出串级），启动需进料许可且无停车
    IF (NOT xStageBypass) AND fbStartRise.Q AND xFeedPermit AND (NOT xStop) AND (NOT xParamBad) THEN
        eState := E_DL_ReStageState.FEED;                                                                        // 本拍行为：进进料相 EN: enter the feed phase
    END_IF

E_DL_ReStageState.FEED:
    // 拍 N：进料充液；无许可只驻留告警（信息级），中断计时暂停，恢复许可后继续累计；有许可且中断累计超时判 9811
    // EN: feeding and filling; without the permit only an information warning is raised and the interruption timer is held, resuming when the permit returns; an interruption with the permit present raises 9811
    IF NOT xFeedPermit THEN
        nWarnCode := DL_RMS_C_PERM;                                                                              // 许可缺失告警，不置故障 EN: warn about the missing permit, no fault
    END_IF
    IF tonFeed.Q THEN
        nCodeLatch := DL_RMS_C_FEED;                                                                             // 进料中断超时 EN: the feed interruption timed out
        xFault := TRUE;                                                                                          // 置故障标志 EN: raise the fault flag
        nFaultCode := DL_RMS_C_FEED;                                                                             // 故障码出口 EN: publish the fault code
        eState := E_DL_ReStageState.FAULT;                                                                       // 迁故障相 EN: move to the fault phase
    ELSIF xFillFull THEN
        eState := E_DL_ReStageState.MIX;                                                                         // 本拍行为：进混合相 EN: enter the mixing phase
    END_IF

E_DL_ReStageState.MIX:
    // 拍 N：搅拌混合，混合时间到即转澄清
    IF tonMix.Q THEN
        eState := E_DL_ReStageState.SETTLE;                                                                      // 本拍行为：进澄清相 EN: enter the settling phase
    END_IF

E_DL_ReStageState.SETTLE:
    // 拍 N：静置澄清；界面位越限立即转延长分相，澄清时间到且界面位在带内才放行排料
    IF NOT xInterfOk THEN
        eState := E_DL_ReStageState.PHASE_SEP;                                                                   // 本拍行为：界面位越限转延长分相 EN: an interface excursion moves to the extended phase
    ELSIF tonSettle.Q AND xInterfOk THEN
        eState := E_DL_ReStageState.DISCHARGE;                                                                   // 本拍行为：澄清完成进排料相 EN: settling done, enter discharge
    END_IF

E_DL_ReStageState.PHASE_SEP:
    // 拍 N：延长分相；界面位回带内即放行，延长窗耗尽仍越限判 9812
    IF tonSep.Q AND (NOT xInterfOk) THEN
        nCodeLatch := DL_RMS_C_INTER;                                                                            // 界面位不可恢复 EN: the interface excursion is not recoverable
        xFault := TRUE;                                                                                          // 置故障标志 EN: raise the fault flag
        nFaultCode := DL_RMS_C_INTER;                                                                            // 故障码出口 EN: publish the fault code
        eState := E_DL_ReStageState.FAULT;                                                                       // 迁故障相 EN: move to the fault phase
    ELSIF xInterfOk THEN
        eState := E_DL_ReStageState.DISCHARGE;                                                                   // 本拍行为：界面位回稳进排料相 EN: the interface recovered, enter discharge
    END_IF

E_DL_ReStageState.DISCHARGE:
    // 拍 N：排料；排空回待机，排料超时判 9813（迁入本相已带参数闸复检）
    IF xParamBad THEN
        nCodeLatch := DL_RMS_C_PARAM;                                                                            // 参数退化锁存 EN: latch the parameter code
        xFault := TRUE;                                                                                          // 置故障标志 EN: raise the fault flag
        nFaultCode := DL_RMS_C_PARAM;                                                                            // 故障码出口 EN: publish the fault code
        eState := E_DL_ReStageState.FAULT;                                                                       // 迁故障相 EN: move to the fault phase
    ELSIF tonDisch.Q AND (NOT xFillEmpty) THEN
        nCodeLatch := DL_RMS_C_DISCH;                                                                            // 排料超时 EN: the discharge timed out
        xFault := TRUE;                                                                                          // 置故障标志 EN: raise the fault flag
        nFaultCode := DL_RMS_C_DISCH;                                                                            // 故障码出口 EN: publish the fault code
        eState := E_DL_ReStageState.FAULT;                                                                       // 迁故障相 EN: move to the fault phase
    ELSIF xFillEmpty THEN
        eState := E_DL_ReStageState.IDLE;                                                                        // 本拍行为：排空回待机 EN: discharged, back to idle
    END_IF

E_DL_ReStageState.FAULT:
    // 故障相（本段被外层 IF 排除，保留分支以满足枚举穷举）
    xFault := TRUE;                                                                                              // 保持故障标志 EN: keep the fault flag
    nFaultCode := nCodeLatch;                                                                                    // 锁存回放 EN: replay the latch

ELSE
    // 非法状态兜底：绝不停在未知相
    nCodeLatch := DL_RMS_C_PARAM;                                                                                // 非法状态归参数码 EN: treat an illegal state as a parameter code
    xFault := TRUE;                                                                                              // 置故障标志 EN: raise the fault flag
    nFaultCode := DL_RMS_C_PARAM;                                                                                // 故障码出口 EN: publish the fault code
    eState := E_DL_ReStageState.FAULT;                                                                           // 迁故障相 EN: move to the fault phase
END_CASE
END_IF

// 段6｜相独立使能出口（IDLE/FAULT 不置任何命令，天然强制撤销）
CASE eState OF
E_DL_ReStageState.FEED:
    xFeedValveCmd := xFeedPermit;                                                                                // 进料阀命令（无许可不投） EN: the feed valve command, gated by the permit
E_DL_ReStageState.MIX:
    xMixerCmd := TRUE;                                                                                           // 搅拌命令 EN: the mixer command
E_DL_ReStageState.SETTLE:
    xSettlePlateCmd := TRUE;                                                                                     // 澄清挡板投入 EN: the settler plate command
E_DL_ReStageState.PHASE_SEP:
    xSettlePlateCmd := TRUE;                                                                                     // 延长分相仍保持挡板 EN: the plate stays in during the extension
    xSepExtended := TRUE;                                                                                        // 延长分相标志 EN: the extension flag
    rSepElapsedS := TIME_TO_REAL(tonSep.ET) * 0.001;                                                             // 分相已用时间 [s] EN: the separation time elapsed
E_DL_ReStageState.DISCHARGE:
    xDischargeCmd := TRUE;                                                                                       // 排料阀命令 EN: the discharge valve command
ELSE
    // 其余相（含 IDLE/FAULT）：全部命令保持撤销
    xFeedValveCmd := FALSE;                                                                                      // 进料阀保持关 EN: keep the feed valve closed
    xMixerCmd := FALSE;                                                                                          // 搅拌保持停 EN: keep the mixer off
    xSettlePlateCmd := FALSE;                                                                                    // 挡板保持撤 EN: keep the plate withdrawn
    xDischargeCmd := FALSE;                                                                                      // 排料阀保持关 EN: keep the discharge valve closed
END_CASE

// 段7｜故障相锁存回放 + 两条复位路径（xStart 下降沿主路径 / 旁路上升沿旁路路径）
IF eState = E_DL_ReStageState.FAULT THEN
    xFault := TRUE;                                                                                              // 故障标志保持 EN: keep the fault flag
    nFaultCode := nCodeLatch;                                                                                    // 锁存回放，不按当下输入重推断 EN: replay the latch instead of re inferring
    nWarnCode := 0;                                                                                              // 故障相不报信息级码 EN: no information class code in the fault phase
    xFeedValveCmd := FALSE;                                                                                      // 进料阀强制关 EN: force the feed valve closed
    xMixerCmd := FALSE;                                                                                          // 搅拌强制停 EN: force the mixer off
    xSettlePlateCmd := FALSE;                                                                                    // 挡板强制撤 EN: force the plate withdrawn
    xDischargeCmd := FALSE;                                                                                      // 排料阀强制关 EN: force the discharge valve closed
    IF fbStartFall.Q OR fbBypRise.Q THEN
        nCodeLatch := 0;                                                                                         // 清除边：下降沿或旁路沿（头注释已声明） EN: clear on the falling edge or the bypass edge
        eState := E_DL_ReStageState.IDLE;                                                                        // 回待机 EN: back to idle
    END_IF
END_IF
END_FUNCTION_BLOCK
