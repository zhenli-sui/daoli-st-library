// FB_DL_ValveStrokeTimeWatch v1.0.0
(*==============================================================================
 * 功能描述: 阀门行程时间监视。开/关指令上升沿起 TON 计测，到限位反馈即记录
 *           本次行程时间 fStrokeTime [s]；行程未在 tMax 内到位 → bSlow 告警锁存；
 *           指令撤销（中途回退）即复位计时。开/关双向独立监视，bSlow 仅由 bReset
 *           复位沿解除（正常行程不清除既有告警）。
 * 接口契约: 输入 bOpenCmd/bCloseCmd/bOpenedLim/bClosedLim/tMax/bReset；
 *           输出 fStrokeTime/bSlow/bMoving/bError（恒假兼容出口）/nErrId。
 * 边界: ① 四枚 R_TRIG + 两枚 TON 段 0 无条件周期刷新；② 开/关命令互斥（同拍双真
 *           以开优先，暂不报专用码位）；③ tMax <= T#0S → 视为无效组态，PT 即时到
 *           时（bSlow 直告），恢复监视需改回有效组态；
 *           ④ 零全局耦合。
 * 码表: 16#0007_0309 信息级：慢行程告警（bSlow 并行，每拍重算）；故障相无锁存
 *       （bSlow 为告警级，随正常行程或复位沿解除）。
 * 修订历史: 2026-11-23  v1.0.0  R74 首版
 *==============================================================================*)

FUNCTION_BLOCK FB_DL_ValveStrokeTimeWatch
VAR_INPUT
    bOpenCmd   : BOOL := FALSE;    // 开阀指令 [-] / Open command
    bCloseCmd  : BOOL := FALSE;    // 关阀指令 [-] / Close command
    bOpenedLim : BOOL := FALSE;    // 开到位限位反馈 [-] / Opened limit feedback
    bClosedLim : BOOL := FALSE;    // 关到位限位反馈 [-] / Closed limit feedback
    tMax       : TIME := T#30S;    // 行程时间上限，域 > T#0S [ms] / Stroke time upper limit
    bReset     : BOOL := FALSE;    // 复位，上升沿清 bSlow 锁存 [-] / Reset edge clears slow latch
END_VAR
VAR_OUTPUT
    fStrokeTime : REAL := 0.0;     // 最近一次完成行程时间 [s] / Last completed stroke time [s]
    bSlow       : BOOL;            // 慢行程告警锁存 [-] / Slow stroke latch
    bMoving     : BOOL;            // 行进中标志（指令且未到限位）[-] / Moving flag
    bError      : BOOL;            // 故障锁存出口（本件无故障级，恒假，兼容出口口径）[-] / Fault outlet, always FALSE here
    nErrId      : UDINT;           // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    rtOpen    : R_TRIG;            // 开指令上升沿实例，段 0 无条件刷新 / Open command rising edge
    rtClose   : R_TRIG;            // 关指令上升沿实例，段 0 无条件刷新 / Close command rising edge
    rtReset   : R_TRIG;            // 复位沿实例，段 0 无条件刷新 / Reset edge instance
    tonOpen   : TON;               // 开行程计时，段 0 无条件刷新 / Open stroke timer
    tonClose  : TON;               // 关行程计时，段 0 无条件刷新 / Close stroke timer
    _bCfgBad  : BOOL;              // 组态非法当拍量 [-] / Illegal configuration this scan
    _bCmdDual : BOOL;              // 开关命令同拍双真当拍量 [-] / Dual command this scan
    _bOpenRun : BOOL;              // 开行程计测中（锁存量）[-] / Open timing in progress
    _bClsRun  : BOOL;              // 关行程计测中（锁存量）[-] / Close timing in progress
    _uInfo    : UDINT;             // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR

(* —— 段 0：沿实例与定时器无条件周期刷新（禁置于 IF/CASE 内） —— *)
rtOpen(CLK := bOpenCmd);                                           // 开沿，每拍必调 / Open edge every scan
rtClose(CLK := bCloseCmd);                                         // 关沿，每拍必调 / Close edge every scan
rtReset(CLK := bReset);                                            // 复位沿，每拍必调 / Reset edge every scan
tonOpen(IN := _bOpenRun, PT := tMax);                              // 开行程计时（计测中刷新）/ Open stroke timer while timing
tonClose(IN := _bClsRun, PT := tMax);                              // 关行程计时（计测中刷新）/ Close stroke timer while timing

(* —— 段 1：单拍量预清零（锁存量 _bOpenRun/_bClsRun/bSlow/fStrokeTime 不入清单） —— *)
bMoving := FALSE;                                                  // 行进标志预清（计测相同拍回填） / Moving preset
bError := FALSE;                                                   // 兼容出口预清（本件无故障级，恒假） / Compatibility preset
_uInfo := 16#0000_0000;                                            // 信息码每拍重算 / Info recomputed every scan
nErrId := 16#0000_0000;                                            // 事件码缺省无事件 / Event code default none
_bCfgBad := tMax <= T#0S;                                          // 时间域闸（上限非正判组态非法） / Time domain gate
_bCmdDual := bOpenCmd AND bCloseCmd;                               // 命令互斥当拍量 / Dual command this scan

(* —— 段 2：开向行程计测（沿起测 → 限位记录 / 超时告警 / 撤令复位） —— *)
IF rtOpen.Q THEN                                                   // 开沿起测 / Open edge starts timing
    _bOpenRun := TRUE;                                             // 置计测中 / Timing in progress
END_IF
IF _bOpenRun THEN                                                  // 开计测分支 / Open timing branch
    IF (NOT bOpenCmd) THEN                                         // 指令中途撤销 → 复位计测（不记时） / Command withdrawn, timing reset
        _bOpenRun := FALSE;                                        // 清计测中 / Timing cleared
        _uInfo := 16#0007_0309;                                    // 信息级：行程中止 / Info: stroke aborted
    ELSIF bOpenedLim THEN                                          // 到开限位 → 记录行程时间 / Reached limit, record time
        fStrokeTime := DINT_TO_REAL(TIME_TO_DINT(tonOpen.ET)) / 1000.0;   // ET 毫秒换算秒 [s]（标准 TIME_TO_DINT，非 TIME_TO_DWORD） / ET in ms converted to seconds
        _bOpenRun := FALSE;                                        // 清计测中 / Timing cleared
        IF tonOpen.Q THEN                                          // 超窗到位 → 慢行程告警锁存 / Over limit, slow latch
            bSlow := TRUE;                                         // 置慢告警 / Raise slow latch
            _uInfo := 16#0007_0309;                                // 信息级：慢行程 / Info: slow stroke
        ELSE
            _uInfo := 16#0000_0000;                                // 正常行程清告警信息 / Normal stroke
        END_IF
    END_IF
END_IF

(* —— 段 3：关向行程计测（同构双向独立） —— *)
IF rtClose.Q THEN                                                  // 关沿起测 / Close edge starts timing
    _bClsRun := TRUE;                                              // 置计测中 / Timing in progress
END_IF
IF _bClsRun THEN                                                   // 关计测分支 / Close timing branch
    IF (NOT bCloseCmd) THEN                                        // 指令中途撤销 → 复位计测 / Command withdrawn, timing reset
        _bClsRun := FALSE;                                         // 清计测中 / Timing cleared
        _uInfo := 16#0007_0309;                                    // 信息级：行程中止 / Info: stroke aborted
    ELSIF bClosedLim THEN                                          // 到关限位 → 记录行程时间 / Reached limit, record time
        fStrokeTime := DINT_TO_REAL(TIME_TO_DINT(tonClose.ET)) / 1000.0;   // ET 毫秒换算秒 [s] / ET in ms converted to seconds
        _bClsRun := FALSE;                                         // 清计测中 / Timing cleared
        IF tonClose.Q THEN                                         // 超窗到位 → 慢行程告警锁存 / Over limit, slow latch
            bSlow := TRUE;                                         // 置慢告警 / Raise slow latch
            _uInfo := 16#0007_0309;                                // 信息级：慢行程 / Info: slow stroke
        ELSE
            _uInfo := 16#0000_0000;                                // 正常行程清告警信息 / Normal stroke
        END_IF
    END_IF
END_IF

(* —— 段 4：告警解除路径（复位沿清锁存；正常行程已在段 2/3 随拍清） —— *)
IF rtReset.Q THEN                                                  // 复位沿 / Reset edge
    bSlow := FALSE;                                                // 清慢告警锁存 / Clear slow latch
    _bOpenRun := FALSE;                                            // 清开计测 / Clear open timing
    _bClsRun := FALSE;                                             // 清关计测 / Clear close timing
END_IF

(* —— 段 5：出口单点映射（名实同源） —— *)
bMoving := _bOpenRun OR _bClsRun;                                  // 行进标志（双向任一计测中） / Moving if either timing
nErrId := _uInfo;                                                  // 信息码出口（本件无故障级） / Info outlet, no fault level

END_FUNCTION_BLOCK
