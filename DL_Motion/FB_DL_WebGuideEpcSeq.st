(*
  Component : FB_DL_WebGuideEpcSeq
  Category  : DL_Motion
  Function  : EPC 纠偏闭环状态机：找边扫描→跟踪（死区内不动）→丢边保持→换卷回中→故障锁存
  Complexity: C4
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 xStart 启动（上升沿启动，下降沿兼故障复位沿）、xStop 停止、xWebPresent 卷材存在、
             xSensorOk 传感器信号有效、xRollChange 换卷信号、rEdgeOffsetMm 边缘偏移（正=偏右） [mm]、
             rDeadbandMm 跟踪死区 [mm]、rFindBandMm 找边判定带宽 [mm]、rMaxOffsetMm 允许最大偏移 [mm]、
             rCorrRateMmS 跟踪纠偏速度 [mm/s]、rScanRateMmS 找边扫描速度 [mm/s]、
             rSearchTmoS 找边超时 [s]、rLostTmoS 丢边保持超时 [s]、rCenterTmoS 回中超时 [s]。
  输出     : rActCmdMmS 带符号执行速度指令（正=右移） [mm/s]、xMotionEnabled 执行使能、
             eState 当前相、xFault/nFaultCode 故障、nWarnCode 信息级码、xEdgeFound 已找到边。
  输出语义 : EDGE_LOST 相为「冻结保持末值」——执行速度指令保持进相前最后一拍的 rLastCmdMmS，
             设计理由：丢边瞬间若把指令清零会造成带材在纠偏辊上突然回弹（阶跃），
             故按冻结处理并在 nWarnCode 每拍报 9602，超时后转 FAULT 并强制撤销指令。
             xStop=TRUE 时不冻结，全部命令撤销并回 IDLE（撤销型停车）。
  复位沿   : 故障码锁存至 xStart 下降沿；复位后停在 IDLE，需重新给启动上升沿（不做自动再入）。
  码位     : 9601 找边超时（故障级）；9602 丢边保持中（信息级，不置 xFault）；
             9603 回中超时（故障级）；9604 参数或采样非法（故障级）；9605 卷材缺失（故障级）；
             9606 丢边保持超时（故障级，与 9601 分属不同成因，按 R190 归因唯一独立派码）。
*)
TYPE E_DL_WebGuideState :
(
    IDLE       := 0,    // 待机，执行使能撤销 EN: idle, the motion enable is withdrawn
    EDGE_SEARCH:= 10,   // 找边扫描相 EN: the edge search phase
    TRACKING   := 20,   // 跟踪相（死区内不动） EN: the tracking phase, no motion inside the dead band
    EDGE_LOST  := 30,   // 丢边保持相（指令冻结） EN: the edge lost phase with a frozen command
    CENTERING  := 40,   // 换卷回中相 EN: the centering phase after a roll change
    FAULT      := 90    // 故障相，指令强制撤销 EN: the fault phase, the command is forced off
);
END_TYPE

FUNCTION_BLOCK FB_DL_WebGuideEpcSeq
VAR_INPUT
    xStart        : BOOL;             // 启动（上升沿启动，下降沿复位故障） EN: start on the rising edge, reset the fault on the falling edge
    xStop         : BOOL;             // 停止（任意相生效，撤销指令） EN: stop, effective in every phase and withdrawing the command
    xWebPresent   : BOOL;             // 卷材存在（穿带完成） EN: the web is present after threading
    xSensorOk     : BOOL;             // 传感器信号有效 EDGE_LOST 判据 EN: the sensor signal is valid, the edge lost criterion
    xRollChange   : BOOL;             // 换卷信号（上升沿进回中相） EN: the roll change signal entering the centering phase
    rEdgeOffsetMm : REAL;             // 边缘偏移，正表示偏右 [mm] EN: the edge offset, positive means to the right
    rDeadbandMm   : REAL := 0.5;      // 跟踪死区 [mm] EN: the tracking dead band
    rFindBandMm   : REAL := 2.0;      // 找边判定带宽（进入该带即认为找到边） [mm] EN: the find band that declares an edge found
    rMaxOffsetMm  : REAL := 20.0;     // 允许最大偏移（越界视为异常） [mm] EN: the maximum allowed offset
    rCorrRateMmS  : REAL := 5.0;      // 跟踪纠偏速度幅值 [mm/s] EN: the tracking correction velocity magnitude
    rScanRateMmS  : REAL := 2.0;      // 找边扫描速度幅值 [mm/s] EN: the edge search velocity magnitude
    rSearchTmoS   : REAL := 30.0;     // 找边超时 [s] EN: the edge search timeout
    rLostTmoS     : REAL := 3.0;      // 丢边保持超时 [s] EN: the edge lost hold timeout
    rCenterTmoS   : REAL := 20.0;     // 回中超时 [s] EN: the centering timeout
END_VAR
VAR_OUTPUT
    rActCmdMmS    : REAL;             // 带符号执行速度指令，正表示右移 [mm/s] EN: the signed actuator velocity command, positive means right
    xMotionEnabled: BOOL;             // 执行使能 EN: the motion enable
    eState        : E_DL_WebGuideState;  // 当前相 EN: the current phase
    xFault        : BOOL;             // 故障标志（仅故障级码置位） EN: the fault flag, raised by fault class codes only
    nFaultCode    : INT;              // 故障码，锁存回放 EN: the fault code replayed from the latch
    nWarnCode     : INT;              // 信息级码（每拍重算） EN: the information class code recomputed every cycle
    xEdgeFound    : BOOL;             // 已找到边（跟踪相成立） EN: the edge has been found
END_VAR
VAR
    tonSearch  : TON;                 // 找边超时定时器 EN: the edge search timeout
    tonLost    : TON;                 // 丢边保持定时器 EN: the edge lost hold timer
    tonCenter  : TON;                 // 回中超时定时器 EN: the centering timeout
    fbStartRise: R_TRIG;              // xStart 上升沿（唯一启动沿） EN: the rising edge of xStart, the only start edge
    fbStartFall: F_TRIG;              // xStart 下降沿（复位沿） EN: the falling edge of xStart, the reset edge
    fbRollRise : R_TRIG;              // 换卷上升沿 EN: the rising edge of the roll change signal
    xFinAll    : BOOL;                // 全部浮点入参有限 EN: every floating input is finite
    xParamBad  : BOOL;                // 参数或采样非法 EN: a parameter or the sample is illegal
    xSensorUse : BOOL;                // 传感器可用（有效且偏移有限） EN: the sensor is usable
    rAbsOff    : REAL;                // 偏移绝对值 [mm] EN: the offset magnitude
    rCmd       : REAL;                // 本拍指令工作值 [mm/s] EN: the working command of this cycle
    rLastCmd   : REAL;                // 上拍指令快照（丢边冻结用） [mm/s] EN: the previous command snapshot used for the freeze
    nMsSearch  : UDINT := 30000;      // 找边超时毫秒数（缺省防零 PT） EN: the search timeout in milliseconds, the default avoids a zero preset
    nMsLost    : UDINT := 3000;       // 丢边超时毫秒数 EN: the lost timeout in milliseconds
    nMsCenter  : UDINT := 20000;      // 回中超时毫秒数 EN: the centering timeout in milliseconds
    nCodeLatch : INT;                 // 故障码锁存副本 EN: the latched copy of the fault code
END_VAR
VAR CONSTANT
    DL_WGE_Z       : REAL := 0.0;     // 浮点零常量 EN: the floating point zero constant
    DL_WGE_K1000   : REAL := 1000.0;  // 秒转毫秒系数 EN: the second to millisecond factor
    DL_WGE_W_LOST  : INT := 9602;     // 丢边保持中（信息级） EN: the edge is currently lost, information class
    DL_WGE_C_SEARCH: INT := 9601;     // 找边超时（故障级） EN: the edge search timed out
    DL_WGE_C_CENTER: INT := 9603;     // 回中超时（故障级） EN: the centering timed out
    DL_WGE_C_PARAM : INT := 9604;     // 参数或采样非法（故障级） EN: a parameter or the sample is illegal
    DL_WGE_C_WEB   : INT := 9605;     // 卷材缺失（故障级） EN: the web is missing
    DL_WGE_C_LOST  : INT := 9606;     // 丢边保持超时（故障级） EN: the edge lost hold timed out
END_VAR

// 段1｜参数与采样门禁（先判后用：换算在闸后，结果供段2 定时器 PT）
xFinAll := (rEdgeOffsetMm = rEdgeOffsetMm) AND ((rEdgeOffsetMm - rEdgeOffsetMm) = DL_WGE_Z)
        AND (rDeadbandMm = rDeadbandMm) AND ((rDeadbandMm - rDeadbandMm) = DL_WGE_Z)
        AND (rFindBandMm = rFindBandMm) AND ((rFindBandMm - rFindBandMm) = DL_WGE_Z)
        AND (rMaxOffsetMm = rMaxOffsetMm) AND ((rMaxOffsetMm - rMaxOffsetMm) = DL_WGE_Z)
        AND (rCorrRateMmS = rCorrRateMmS) AND ((rCorrRateMmS - rCorrRateMmS) = DL_WGE_Z)
        AND (rScanRateMmS = rScanRateMmS) AND ((rScanRateMmS - rScanRateMmS) = DL_WGE_Z)
        AND (rSearchTmoS = rSearchTmoS) AND ((rSearchTmoS - rSearchTmoS) = DL_WGE_Z)
        AND (rLostTmoS = rLostTmoS) AND ((rLostTmoS - rLostTmoS) = DL_WGE_Z)
        AND (rCenterTmoS = rCenterTmoS) AND ((rCenterTmoS - rCenterTmoS) = DL_WGE_Z);   // 九个浮点入参有限性 EN: the finiteness of all nine floating inputs
xParamBad := (NOT xFinAll) OR (rDeadbandMm < DL_WGE_Z) OR (rFindBandMm <= rDeadbandMm)
          OR (rMaxOffsetMm <= rFindBandMm) OR (rCorrRateMmS <= DL_WGE_Z) OR (rScanRateMmS <= DL_WGE_Z)
          OR (rSearchTmoS <= DL_WGE_Z) OR (rLostTmoS <= DL_WGE_Z) OR (rCenterTmoS <= DL_WGE_Z);   // 域闸与带间配比 EN: the domain gate and the band ordering
IF NOT xParamBad THEN                                                                              // 参数合法才换算 EN: convert only when the parameters are legal
    nMsSearch := REAL_TO_UDINT(rSearchTmoS * DL_WGE_K1000);                                        // 找边毫秒数 EN: the search milliseconds
    nMsLost := REAL_TO_UDINT(rLostTmoS * DL_WGE_K1000);                                            // 丢边毫秒数 EN: the lost milliseconds
    nMsCenter := REAL_TO_UDINT(rCenterTmoS * DL_WGE_K1000);                                        // 回中毫秒数 EN: the centering milliseconds
END_IF
xSensorUse := xSensorOk AND (NOT xParamBad);                                                       // 传感器可用判据 EN: the sensor usability test
rAbsOff := ABS(rEdgeOffsetMm);                                                                     // 偏移绝对值 [mm] EN: the offset magnitude

// 段2｜三只定时器 + 三只边沿实例无条件周期刷新（CASE 内不调用实例）
tonSearch(IN := (eState = E_DL_WebGuideState.EDGE_SEARCH), PT := UDINT_TO_TIME(nMsSearch));        // 找边计时 EN: the edge search timer
tonLost(IN := (eState = E_DL_WebGuideState.EDGE_LOST), PT := UDINT_TO_TIME(nMsLost));              // 丢边保持计时 EN: the edge lost timer
tonCenter(IN := (eState = E_DL_WebGuideState.CENTERING), PT := UDINT_TO_TIME(nMsCenter));          // 回中计时 EN: the centering timer
fbStartRise(CLK := xStart);                                                                        // 启动沿 EN: the start edge
fbStartFall(CLK := xStart);                                                                        // 复位沿 EN: the reset edge
fbRollRise(CLK := xRollChange);                                                                    // 换卷沿 EN: the roll change edge

// 段3｜输出预置（唯一预置点；EDGE_LOST 冻结语义在此体现为上拍快照）
rActCmdMmS := rLastCmd;                    // 指令预置为上拍快照（冻结保持） [mm/s] EN: preset the command to the previous snapshot
xMotionEnabled := FALSE;                   // 使能预置假 EN: preset the enable false
xFault := FALSE;                           // 故障标志预置假 EN: preset the fault flag false
nFaultCode := 0;                           // 故障码预置零 EN: preset the fault code to zero
nWarnCode := 0;                            // 信息码预置零 EN: preset the warning code to zero
xEdgeFound := (eState = E_DL_WebGuideState.TRACKING);   // 已找到边直映相态 EN: mirror the found state from the phase

// 段4｜全局安全闸：参数非法 / 运行中卷材缺失 → 锁故障；xStop 撤销指令回待机
IF xParamBad THEN
    nCodeLatch := DL_WGE_C_PARAM;                                                       // 参数非法锁存 EN: latch the parameter code
    xFault := TRUE;                                                                     // 置故障标志 EN: raise the fault flag
    nFaultCode := DL_WGE_C_PARAM;                                                       // 故障码出口 EN: publish the fault code
    eState := E_DL_WebGuideState.FAULT;                                                 // 迁故障相 EN: move to the fault phase
ELSIF (NOT xWebPresent) AND (eState <> E_DL_WebGuideState.IDLE) THEN
    nCodeLatch := DL_WGE_C_WEB;                                                         // 卷材缺失锁存 EN: latch the missing web code
    xFault := TRUE;                                                                     // 置故障标志 EN: raise the fault flag
    nFaultCode := DL_WGE_C_WEB;                                                         // 故障码出口 EN: publish the fault code
    eState := E_DL_WebGuideState.FAULT;                                                 // 迁故障相 EN: move to the fault phase
ELSIF xStop AND (eState <> E_DL_WebGuideState.IDLE) THEN
    rLastCmd := DL_WGE_Z;                                                               // 撤销型停车清空冻结快照，防止重启首拍陈指令 EN: a withdrawing stop clears the frozen snapshot so a restart cannot emit a stale command
    eState := E_DL_WebGuideState.IDLE;                                                  // 撤销型停车回待机 EN: a withdrawing stop returns to idle
END_IF

// 段5｜主状态机（ENUM + CASE，ELSE 兜底非法值）
IF eState <> E_DL_WebGuideState.FAULT THEN
CASE eState OF
E_DL_WebGuideState.IDLE:
    // 拍 N：待机；启动沿且卷材存在才进找边相（入相前置条件已含卷材与传感器）
    IF fbStartRise.Q AND xWebPresent AND (NOT xStop) AND xSensorUse THEN
        eState := E_DL_WebGuideState.EDGE_SEARCH;                                    // 本拍行为：进找边相 EN: enter the edge search phase
    END_IF

E_DL_WebGuideState.EDGE_SEARCH:
    // 拍 N：按偏移符号反方向扫描找边；进入判定带即进跟踪相，超时判 9601
    xMotionEnabled := TRUE;                                                          // 找边允许动作 EN: motion allowed for the search
    IF (NOT xSensorUse) THEN
        eState := E_DL_WebGuideState.EDGE_LOST;                                      // 本拍行为：传感器失效转丢边相 EN: the sensor failed, move to the lost phase
    ELSIF rAbsOff <= rFindBandMm THEN
        eState := E_DL_WebGuideState.TRACKING;                                       // 本拍行为：找到边进跟踪相 EN: the edge is found, enter tracking
    ELSIF tonSearch.Q THEN
        nCodeLatch := DL_WGE_C_SEARCH;                                               // 找边超时 EN: the edge search timed out
        xFault := TRUE;                                                              // 置故障标志 EN: raise the fault flag
        nFaultCode := DL_WGE_C_SEARCH;                                               // 故障码出口 EN: publish the fault code
        eState := E_DL_WebGuideState.FAULT;                                          // 迁故障相 EN: move to the fault phase
    ELSE
        IF rEdgeOffsetMm > DL_WGE_Z THEN                                             // 偏右则向左扫描 EN: scan left when the web sits right
            rCmd := -rScanRateMmS;                                                   // 负向扫描速度 [mm/s] EN: the negative scan velocity
        ELSE
            rCmd := rScanRateMmS;                                                    // 正向扫描速度 [mm/s] EN: the positive scan velocity
        END_IF
        rActCmdMmS := rCmd;                                                          // 落定本拍指令 [mm/s] EN: publish the command
        rLastCmd := rCmd;                                                            // 更新快照 [mm/s] EN: update the snapshot
    END_IF

E_DL_WebGuideState.TRACKING:
    // 拍 N：死区内不动、区外按偏移符号反方向纠偏；传感器失效转丢边相，偏移越限判参数类故障
    IF (NOT xSensorUse) THEN
        eState := E_DL_WebGuideState.EDGE_LOST;                                      // 本拍行为：丢边转保持相 EN: the edge is lost, move to the hold phase
    ELSIF fbRollRise.Q THEN
        eState := E_DL_WebGuideState.CENTERING;                                      // 本拍行为：换卷进回中相 EN: a roll change enters centering
    ELSIF rAbsOff > rMaxOffsetMm THEN
        nCodeLatch := DL_WGE_C_PARAM;                                                // 偏移越最大允许值，按参数/采样非法处理 EN: the offset exceeded the allowed maximum
        xFault := TRUE;                                                              // 置故障标志 EN: raise the fault flag
        nFaultCode := DL_WGE_C_PARAM;                                                // 故障码出口 EN: publish the fault code
        eState := E_DL_WebGuideState.FAULT;                                          // 迁故障相 EN: move to the fault phase
    ELSE
        xMotionEnabled := TRUE;                                                      // 跟踪允许动作 EN: motion allowed for tracking
        IF rAbsOff <= rDeadbandMm THEN                                               // 死区内不动 EN: no motion inside the dead band
            rCmd := DL_WGE_Z;                                                        // 指令给零 [mm/s] EN: give a zero command
        ELSIF rEdgeOffsetMm > DL_WGE_Z THEN                                          // 偏右则左移 EN: move left when the web sits right
            rCmd := -rCorrRateMmS;                                                   // 负向纠偏速度 [mm/s] EN: the negative correction velocity
        ELSE
            rCmd := rCorrRateMmS;                                                    // 正向纠偏速度 [mm/s] EN: the positive correction velocity
        END_IF
        rActCmdMmS := rCmd;                                                          // 落定本拍指令 [mm/s] EN: publish the command
        rLastCmd := rCmd;                                                            // 更新快照 [mm/s] EN: update the snapshot
    END_IF

E_DL_WebGuideState.EDGE_LOST:
    // 拍 N：丢边保持——使能保持并原样输出上一拍指令（真冻结，不是等效停车）；传感器恢复即回跟踪，保持超时判 9606
    // EN: hold on a lost edge, keeping the enable and republishing the previous command so the hold is a true freeze rather than an equivalent stop; recovery returns to tracking, a hold timeout raises 9606
    xMotionEnabled := TRUE;                                                          // 丢边保持仍维持使能 EN: keep the enable during the hold
    rActCmdMmS := rLastCmd;                                                          // 原样输出上一拍指令 [mm/s] EN: republish the previous command
    nWarnCode := DL_WGE_W_LOST;                                                      // 信息级：丢边保持中 EN: information class, the edge stays lost
    IF xSensorUse THEN
        eState := E_DL_WebGuideState.TRACKING;                                       // 本拍行为：传感器恢复回跟踪 EN: the sensor recovered, back to tracking
    ELSIF tonLost.Q THEN
        nCodeLatch := DL_WGE_C_LOST;                                                 // 丢边保持超时 EN: the edge lost hold timed out
        xFault := TRUE;                                                              // 置故障标志 EN: raise the fault flag
        nFaultCode := DL_WGE_C_LOST;                                                 // 故障码出口 EN: publish the fault code
        eState := E_DL_WebGuideState.FAULT;                                          // 迁故障相 EN: move to the fault phase
    END_IF

E_DL_WebGuideState.CENTERING:
    // 拍 N：换卷回中——按偏移缓慢回中，进死区即回跟踪，超时判 9603
    IF (NOT xSensorUse) THEN
        eState := E_DL_WebGuideState.EDGE_LOST;                                      // 本拍行为：传感器失效转丢边相 EN: the sensor failed, move to the lost phase
    ELSIF rAbsOff <= rDeadbandMm THEN
        eState := E_DL_WebGuideState.TRACKING;                                       // 本拍行为：回中完成进跟踪相 EN: centering done, enter tracking
    ELSIF tonCenter.Q THEN
        nCodeLatch := DL_WGE_C_CENTER;                                               // 回中超时 EN: the centering timed out
        xFault := TRUE;                                                              // 置故障标志 EN: raise the fault flag
        nFaultCode := DL_WGE_C_CENTER;                                               // 故障码出口 EN: publish the fault code
        eState := E_DL_WebGuideState.FAULT;                                          // 迁故障相 EN: move to the fault phase
    ELSE
        xMotionEnabled := TRUE;                                                      // 回中允许动作 EN: motion allowed for centering
        IF rEdgeOffsetMm > DL_WGE_Z THEN                                             // 偏右则左移 EN: move left when the web sits right
            rCmd := -rCorrRateMmS;                                                   // 负向回中速度 [mm/s] EN: the negative centering velocity
        ELSE
            rCmd := rCorrRateMmS;                                                    // 正向回中速度 [mm/s] EN: the positive centering velocity
        END_IF
        rActCmdMmS := rCmd;                                                          // 落定本拍指令 [mm/s] EN: publish the command
        rLastCmd := rCmd;                                                            // 更新快照 [mm/s] EN: update the snapshot
    END_IF

E_DL_WebGuideState.FAULT:
    // 故障相（本段被外层 IF 排除，保留分支以满足枚举穷举）
    xFault := TRUE;                                                                  // 保持故障标志 EN: keep the fault flag
    nFaultCode := nCodeLatch;                                                        // 锁存回放 EN: replay the latch

ELSE
    // 非法状态兜底：绝不停在未知相
    nCodeLatch := DL_WGE_C_PARAM;                                                    // 非法状态归参数码 EN: treat an illegal state as a parameter code
    xFault := TRUE;                                                                  // 置故障标志 EN: raise the fault flag
    nFaultCode := DL_WGE_C_PARAM;                                                    // 故障码出口 EN: publish the fault code
    eState := E_DL_WebGuideState.FAULT;                                              // 迁故障相 EN: move to the fault phase
END_CASE
END_IF

// 段6｜故障相锁存回放 + 复位沿（xStart 下降沿清除，复位后停 IDLE）
IF eState = E_DL_WebGuideState.FAULT THEN
    xFault := TRUE;                                                                  // 故障标志保持 EN: keep the fault flag
    nFaultCode := nCodeLatch;                                                        // 锁存回放，不按当下输入重推断 EN: replay the latch instead of re inferring
    nWarnCode := 0;                                                                  // 故障相不报信息级码 EN: no information class code in the fault phase
    xMotionEnabled := FALSE;                                                         // 撤销执行使能 EN: withdraw the motion enable
    rActCmdMmS := DL_WGE_Z;                                                          // 指令强制归零 [mm/s] EN: force the command to zero
    rLastCmd := DL_WGE_Z;                                                            // 快照归零，防复位后继承旧指令 [mm/s] EN: clear the snapshot so a reset cannot inherit a stale command
    IF fbStartFall.Q THEN
        nCodeLatch := 0;                                                             // 清除边：xStart 下降沿（头注释已声明） EN: clear on the falling edge of xStart
        eState := E_DL_WebGuideState.IDLE;                                           // 回待机 EN: back to idle
    END_IF
END_IF
END_FUNCTION_BLOCK
