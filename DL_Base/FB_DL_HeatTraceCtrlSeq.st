(*
  Component : FB_DL_HeatTraceCtrlSeq
  Category  : DL_Base
  Function  : 电伴热温控状态机：升温限速→维持带滞环→超温断输出→传感器故障保守输出→冷却
  Complexity: C4
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 xStart 启动（上升沿启动，下降沿兼故障复位沿）、xStop 停止、xSensorOk 温度传感器有效、
             rPipeTempC 管道实测温度 [℃]、rSetpointC 维持温度设定 [℃]、rBandK 维持带半宽 [K]、
             rOverTempC 超温阈值 [℃]、rPreheatRateKmin 升温速率上限 [K/min]、rCoolTargetC 冷却终点 [℃]、
             rHeatMaxS 升温允许最长 [s]、rOverHoldS 超温断输出保持时长 [s]、rCoolMaxS 冷却允许最长 [s]。
  输出     : xHeatCmd 加热使能、eState 当前相、xFault/nFaultCode 故障、nWarnCode 信息级码、
             rDevK 实测与设定偏差 [K]、xConservative 保守输出生效标志。
  输出语义 : 传感器故障（SENSOR_FAULT）时采用「保守输出 = 加热常开」——电伴热的失效后果是冻管与
             介质凝固，失热比过热更难恢复，故失测量时保持加热而不是断加热；头注释显式声明该口径，
             且同相置 xFault 与 9611，禁止「只降级不声明」。xStop=TRUE 时不冻结，转 COOLDOWN 冷却。
  时序     : 同拍双窗配比约束 rOverHoldS < rHeatMaxS（超温保持窗必须远短于升温窗，否则超温保护
             迟于升温超时生效）、rBandK < (rOverTempC − rSetpointC)（维持带必须落在超温阈值内，
             否则滞环上沿与超温阈值重叠，加热永远无法关断）。
  复位沿   : 参数类与超温类故障锁存至 xStart 下降沿；传感器类故障（9611）在 xSensorOk 恢复为真时
             于 SENSOR_FAULT 相内自清并回 MAINTAIN（恢复重入），该路径为电平判据，任何进入方式均可到达。
  码位     : 9610 升温超时（故障级）；9611 传感器断线（故障级，恢复沿自清）；9612 升温速率超限（信息级）；
             9613 超温保持耗尽（故障级）；9614 参数或采样非法（故障级）；9615 冷却未达终点（信息级）；
             9616 超温断输出计时中（信息级）。信息级码一律不置 xFault。
*)
TYPE E_DL_HeatTraceState :
(
    IDLE        := 0,    // 待机，加热撤销 EN: idle, the heating is withdrawn
    PREHEAT     := 10,   // 升温相（速率限幅） EN: the preheat phase with a rate limit
    MAINTAIN    := 20,   // 维持相（上下限滞环） EN: the maintain phase with a hysteresis band
    OVER_TEMP   := 30,   // 超温断输出相（计时保持） EN: the over temperature phase with the heating off
    SENSOR_FAULT:= 40,   // 传感器故障相（保守输出） EN: the sensor fault phase with a conservative output
    COOLDOWN    := 50,   // 冷却相 EN: the cooling phase
    FAULT       := 90    // 故障相，加热强制撤销 EN: the fault phase, the heating is forced off
);
END_TYPE

FUNCTION_BLOCK FB_DL_HeatTraceCtrlSeq
VAR_INPUT
    xStart          : BOOL;            // 启动（上升沿启动，下降沿复位故障） EN: start on the rising edge, reset the fault on the falling edge
    xStop           : BOOL;            // 停止（转冷却相） EN: stop, transferring to the cooling phase
    xSensorOk       : BOOL;            // 温度传感器有效（断线检测取反） EN: the temperature sensor is valid, the wire break detection inverted
    rPipeTempC      : REAL;            // 管道实测温度 [℃] EN: the measured pipe temperature
    rSetpointC      : REAL := 60.0;    // 维持温度设定 [℃] EN: the maintain temperature setpoint
    rBandK          : REAL := 3.0;     // 维持带半宽（滞环） [K] EN: the half width of the maintain band
    rOverTempC      : REAL := 80.0;    // 超温阈值 [℃] EN: the over temperature threshold
    rPreheatRateKmin: REAL := 5.0;     // 升温速率上限 [K/min] EN: the upper bound of the heating rate
    rCoolTargetC    : REAL := 30.0;    // 冷却终点温度 [℃] EN: the cooling end temperature
    rHeatMaxS       : REAL := 3600.0;  // 升温允许最长 [s] EN: the longest allowed heating time
    rOverHoldS      : REAL := 300.0;   // 超温断输出保持时长 [s] EN: the hold time with the heating off after an over temperature
    rCoolMaxS       : REAL := 7200.0;  // 冷却允许最长 [s] EN: the longest allowed cooling time
END_VAR
VAR_OUTPUT
    xHeatCmd       : BOOL;                 // 加热使能命令 EN: the heating enable command
    eState         : E_DL_HeatTraceState;  // 当前相 EN: the current phase
    xFault         : BOOL;                 // 故障标志（仅故障级码置位） EN: the fault flag, raised by fault class codes only
    nFaultCode     : INT;                  // 故障码，锁存回放 EN: the fault code replayed from the latch
    nWarnCode      : INT;                  // 信息级码（每拍重算） EN: the information class code recomputed every cycle
    rDevK          : REAL;                 // 实测与设定偏差 [K] EN: the deviation between the measurement and the setpoint
    xConservative  : BOOL;                 // 保守输出生效 EN: the conservative output is active
END_VAR
VAR
    tonHeat    : TON;                  // 升温时长定时器 EN: the heating timer
    tonOver    : TON;                  // 超温保持定时器 EN: the over temperature hold timer
    tonCool    : TON;                  // 冷却时长定时器 EN: the cooling timer
    fbStartRise: R_TRIG;               // xStart 上升沿（唯一启动沿） EN: the rising edge of xStart, the only start edge
    fbStartFall: F_TRIG;               // xStart 下降沿（复位沿） EN: the falling edge of xStart, the reset edge
    xFinAll    : BOOL;                 // 全部浮点入参有限 EN: every floating input is finite
    xParamBad  : BOOL;                 // 参数或采样非法 EN: a parameter or the sample is illegal
    xSampleOk  : BOOL;                 // 温度采样可用（有限且传感器有效） EN: the temperature sample is usable
    rDev       : REAL;                 // 偏差中间值 [K] EN: the interim deviation
    rAllowC    : REAL;                 // 速率限幅允许温度 [℃] EN: the temperature allowed by the rate limit
    rElapsedS  : REAL;                 // 相内已用时间 [s] EN: the elapsed time inside the phase
    rHeatBaseC : REAL;                 // 升温进相基准温度 [℃] EN: the temperature latched when heating starts
    nMsHeat    : UDINT := 3600000;     // 升温毫秒数（缺省防零 PT） EN: the heating milliseconds, the default avoids a zero preset
    nMsOver    : UDINT := 300000;      // 超温毫秒数 EN: the over temperature milliseconds
    nMsCool    : UDINT := 7200000;     // 冷却毫秒数 EN: the cooling milliseconds
    nCodeLatch : INT;                  // 故障码锁存副本 EN: the latched copy of the fault code
END_VAR
VAR CONSTANT
    DL_HTC_Z       : REAL := 0.0;      // 浮点零常量 EN: the floating point zero constant
    DL_HTC_SECMIN  : REAL := 60.0;     // 分钟换算秒系数 EN: the minute to second factor
    DL_HTC_K1000   : REAL := 1000.0;   // 秒转毫秒系数 EN: the second to millisecond factor
    DL_HTC_W_RATE  : INT := 9612;      // 升温速率超限（信息级） EN: the heating rate violation, information class
    DL_HTC_W_COOL  : INT := 9615;      // 冷却未达终点（信息级） EN: the cooling did not reach the target, information class
    DL_HTC_W_OVER  : INT := 9616;      // 超温断输出计时中（信息级） EN: the over temperature hold is running, information class
    DL_HTC_C_HEAT  : INT := 9610;      // 升温超时（故障级） EN: the heating timed out
    DL_HTC_C_SENS  : INT := 9611;      // 传感器断线（故障级） EN: the sensor wire is broken
    DL_HTC_C_OVER  : INT := 9613;      // 超温保持耗尽（故障级） EN: the over temperature hold expired
    DL_HTC_C_PARAM : INT := 9614;      // 参数或采样非法（故障级） EN: a parameter or the sample is illegal
END_VAR

// 段1｜参数与采样门禁（先判后用：换算在闸后执行，结果供段2 定时器 PT）
xFinAll := (rPipeTempC = rPipeTempC) AND ((rPipeTempC - rPipeTempC) = DL_HTC_Z)
        AND (rSetpointC = rSetpointC) AND ((rSetpointC - rSetpointC) = DL_HTC_Z)
        AND (rBandK = rBandK) AND ((rBandK - rBandK) = DL_HTC_Z)
        AND (rOverTempC = rOverTempC) AND ((rOverTempC - rOverTempC) = DL_HTC_Z)
        AND (rPreheatRateKmin = rPreheatRateKmin) AND ((rPreheatRateKmin - rPreheatRateKmin) = DL_HTC_Z)
        AND (rCoolTargetC = rCoolTargetC) AND ((rCoolTargetC - rCoolTargetC) = DL_HTC_Z)
        AND (rHeatMaxS = rHeatMaxS) AND ((rHeatMaxS - rHeatMaxS) = DL_HTC_Z)
        AND (rOverHoldS = rOverHoldS) AND ((rOverHoldS - rOverHoldS) = DL_HTC_Z)
        AND (rCoolMaxS = rCoolMaxS) AND ((rCoolMaxS - rCoolMaxS) = DL_HTC_Z);          // 九个浮点入参有限性 EN: the finiteness of all nine floating inputs
xParamBad := (NOT xFinAll) OR (rBandK <= DL_HTC_Z) OR (rPreheatRateKmin <= DL_HTC_Z)
          OR (rHeatMaxS <= DL_HTC_Z) OR (rOverHoldS <= DL_HTC_Z) OR (rCoolMaxS <= DL_HTC_Z)
          OR (rOverTempC <= (rSetpointC + rBandK)) OR (rBandK >= (rOverTempC - rSetpointC))
          OR (rOverHoldS >= rHeatMaxS) OR (rCoolTargetC >= rSetpointC);                  // 域闸与两个配比约束 EN: the domain gate and the two ratio constraints
IF NOT xParamBad THEN                                                                    // 参数合法才换算 EN: convert only when the parameters are legal
    nMsHeat := REAL_TO_UDINT(rHeatMaxS * DL_HTC_K1000);                                   // 升温毫秒数 EN: the heating milliseconds
    nMsOver := REAL_TO_UDINT(rOverHoldS * DL_HTC_K1000);                                  // 超温毫秒数 EN: the over temperature milliseconds
    nMsCool := REAL_TO_UDINT(rCoolMaxS * DL_HTC_K1000);                                   // 冷却毫秒数 EN: the cooling milliseconds
END_IF
xSampleOk := (NOT xParamBad) AND xSensorOk;                                               // 采样可用判据 EN: the sample usability test
IF NOT xParamBad THEN                                                                     // 偏差仅在参数合法时计算 EN: compute the deviation only with legal parameters
    rDev := rPipeTempC - rSetpointC;                                                      // 偏差 [K] EN: the deviation
ELSE
    rDev := DL_HTC_Z;                                                                     // 参数非法给零偏差 [K] EN: give a zero deviation
END_IF

// 段2｜三只定时器 + 三只边沿实例无条件周期刷新（CASE 内不调用实例）
tonHeat(IN := (eState = E_DL_HeatTraceState.PREHEAT), PT := UDINT_TO_TIME(nMsHeat));      // 升温计时 EN: the heating timer
tonOver(IN := (eState = E_DL_HeatTraceState.OVER_TEMP), PT := UDINT_TO_TIME(nMsOver));     // 超温保持计时 EN: the over temperature hold timer
tonCool(IN := (eState = E_DL_HeatTraceState.COOLDOWN), PT := UDINT_TO_TIME(nMsCool));      // 冷却计时 EN: the cooling timer
fbStartRise(CLK := xStart);                                                                // 启动沿 EN: the start edge
fbStartFall(CLK := xStart);                                                                // 复位沿 EN: the reset edge

// 段3｜输出预置（唯一预置点，CASE 内只置位；信息级码每拍重算）
xHeatCmd := FALSE;                  // 加热预置关 EN: preset the heating off
xFault := FALSE;                    // 故障标志预置假 EN: preset the fault flag false
nFaultCode := 0;                    // 故障码预置零 EN: preset the fault code to zero
nWarnCode := 0;                     // 信息码预置零 EN: preset the warning code to zero
xConservative := FALSE;             // 保守输出标志预置假 EN: preset the conservative flag false
rDevK := rDev;                      // 偏差出口 [K] EN: publish the deviation

// 段4｜全局安全闸：参数非法锁故障；xStop 转冷却；传感器断线转保守输出相
IF xParamBad THEN
    nCodeLatch := DL_HTC_C_PARAM;                                                          // 参数非法锁存 EN: latch the parameter code
    xFault := TRUE;                                                                        // 置故障标志 EN: raise the fault flag
    nFaultCode := DL_HTC_C_PARAM;                                                          // 故障码出口 EN: publish the fault code
    eState := E_DL_HeatTraceState.FAULT;                                                   // 迁故障相 EN: move to the fault phase
ELSIF xStop AND (eState <> E_DL_HeatTraceState.IDLE) AND (eState <> E_DL_HeatTraceState.FAULT) THEN
    eState := E_DL_HeatTraceState.COOLDOWN;                                                // 停止转冷却相（不冻结） EN: a stop transfers to cooling, nothing is frozen
ELSIF (NOT xSensorOk) AND (eState <> E_DL_HeatTraceState.IDLE) AND (eState <> E_DL_HeatTraceState.SENSOR_FAULT) THEN
    eState := E_DL_HeatTraceState.SENSOR_FAULT;                                            // 传感器断线转保守输出相 EN: a sensor break transfers to the conservative phase
END_IF

// 段5｜主状态机（ENUM + CASE，ELSE 兜底非法值）
IF eState <> E_DL_HeatTraceState.FAULT THEN
CASE eState OF
E_DL_HeatTraceState.IDLE:
    // 拍 N：待机；启动沿且传感器有效才进升温相（入相即锁存速率限幅基准温度）
    IF fbStartRise.Q AND xSensorOk AND (NOT xStop) AND (NOT xParamBad) THEN
        rHeatBaseC := rPipeTempC;                                                          // 锁存升温基准温度 [℃] EN: latch the heating base temperature
        eState := E_DL_HeatTraceState.PREHEAT;                                             // 本拍行为：进升温相 EN: enter the preheat phase
    END_IF

E_DL_HeatTraceState.PREHEAT:
    // 拍 N：升温限速加热；到达维持带下沿进维持相，速率越限只告警，超时判 9610
    rElapsedS := TIME_TO_REAL(tonHeat.ET) * 0.001;                                         // 已用时间 [s] EN: the elapsed time
    rAllowC := rHeatBaseC + rPreheatRateKmin * (rElapsedS / DL_HTC_SECMIN);                // 允许温度 [℃] EN: the temperature allowed by the rate limit
    IF rPipeTempC > (rAllowC + rBandK) THEN                                                // 速率越限判据 EN: the rate violation test
        xHeatCmd := FALSE;                                                                 // 本拍断加热 EN: switch the heating off this cycle
        nWarnCode := DL_HTC_W_RATE;                                                        // 信息级码 EN: the information class code
    ELSE
        xHeatCmd := TRUE;                                                                  // 加热允许 EN: heating allowed
    END_IF
    IF rPipeTempC >= (rSetpointC - rBandK) THEN                                            // 到达维持带下沿 EN: reached the lower edge of the maintain band
        eState := E_DL_HeatTraceState.MAINTAIN;                                            // 本拍行为：进维持相 EN: enter the maintain phase
    ELSIF tonHeat.Q THEN
        nCodeLatch := DL_HTC_C_HEAT;                                                       // 升温超时 EN: the heating timed out
        xFault := TRUE;                                                                    // 置故障标志 EN: raise the fault flag
        nFaultCode := DL_HTC_C_HEAT;                                                       // 故障码出口 EN: publish the fault code
        eState := E_DL_HeatTraceState.FAULT;                                               // 迁故障相 EN: move to the fault phase
    END_IF

E_DL_HeatTraceState.MAINTAIN:
    // 拍 N：滞环维持——低于下沿加热、高于上沿停热；越过超温阈值转超温相
    IF rPipeTempC > rOverTempC THEN                                                        // 超温判据 EN: the over temperature test
        xHeatCmd := FALSE;                                                                 // 断输出 EN: switch the heating off
        eState := E_DL_HeatTraceState.OVER_TEMP;                                           // 本拍行为：进超温相 EN: enter the over temperature phase
    ELSIF rPipeTempC < (rSetpointC - rBandK) THEN                                          // 低于下沿 EN: below the lower edge
        xHeatCmd := TRUE;                                                                  // 加热 EN: heat
    ELSIF rPipeTempC > (rSetpointC + rBandK) THEN                                          // 高于上沿 EN: above the upper edge
        xHeatCmd := FALSE;                                                                 // 停热 EN: stop heating
    ELSE
        xHeatCmd := FALSE;                                                                 // 带内保持现状（本件取停热为默认安全侧） EN: inside the band keep off as the safe default
    END_IF

E_DL_HeatTraceState.OVER_TEMP:
    // 拍 N：超温断输出并计时；回落到设定带上沿即回维持，保持耗尽仍超温判 9613
    xHeatCmd := FALSE;                                                                     // 超温强制断输出 EN: force the heating off
    nWarnCode := DL_HTC_W_OVER;                                                            // 信息级：超温计时中 EN: information class, the hold is running
    IF rPipeTempC <= (rSetpointC + rBandK) THEN                                            // 已回维持带 EN: back inside the maintain band
        eState := E_DL_HeatTraceState.MAINTAIN;                                            // 本拍行为：回维持相 EN: back to the maintain phase
    ELSIF tonOver.Q THEN
        nCodeLatch := DL_HTC_C_OVER;                                                       // 超温保持耗尽 EN: the over temperature hold expired
        xFault := TRUE;                                                                    // 置故障标志 EN: raise the fault flag
        nFaultCode := DL_HTC_C_OVER;                                                       // 故障码出口 EN: publish the fault code
        eState := E_DL_HeatTraceState.FAULT;                                               // 迁故障相 EN: move to the fault phase
    END_IF

E_DL_HeatTraceState.SENSOR_FAULT:
    // 拍 N：传感器断线——保守输出为加热常开（防冻优先，见头注释输出语义段）并置故障级 9611；
    // 传感器恢复为真（电平判据）即清码回维持相，构成可达的解除路径
    IF xSensorOk THEN
        nCodeLatch := 0;                                                                   // 传感器恢复自清 EN: clear on the sensor recovery
        eState := E_DL_HeatTraceState.MAINTAIN;                                            // 本拍行为：恢复重入维持相 EN: re enter the maintain phase
    ELSE
        xHeatCmd := TRUE;                                                                  // 保守输出：加热常开 EN: the conservative output keeps the heating on
        xConservative := TRUE;                                                             // 保守输出标志 EN: the conservative flag
        nCodeLatch := DL_HTC_C_SENS;                                                       // 传感器断线锁存 EN: latch the sensor code
        xFault := TRUE;                                                                    // 置故障标志 EN: raise the fault flag
        nFaultCode := DL_HTC_C_SENS;                                                       // 故障码出口 EN: publish the fault code
    END_IF

E_DL_HeatTraceState.COOLDOWN:
    // 拍 N：冷却——加热撤销，温度降到终点回待机；超时未达终点只报信息级 9615 后回待机
    xHeatCmd := FALSE;                                                                     // 冷却期断加热 EN: the heating stays off while cooling
    IF rPipeTempC <= rCoolTargetC THEN                                                     // 到达冷却终点 EN: the cooling target is reached
        eState := E_DL_HeatTraceState.IDLE;                                                // 本拍行为：回待机 EN: back to idle
    ELSIF tonCool.Q THEN
        nWarnCode := DL_HTC_W_COOL;                                                        // 信息级：冷却未达终点 EN: information class, the cooling target was missed
        eState := E_DL_HeatTraceState.IDLE;                                                // 回待机（不判故障） EN: back to idle without a fault
    END_IF

E_DL_HeatTraceState.FAULT:
    // 故障相（本段被外层 IF 排除，保留分支以满足枚举穷举）
    xFault := TRUE;                                                                        // 保持故障标志 EN: keep the fault flag
    nFaultCode := nCodeLatch;                                                              // 锁存回放 EN: replay the latch

ELSE
    // 非法状态兜底：绝不停在未知相
    nCodeLatch := DL_HTC_C_PARAM;                                                          // 非法状态归参数码 EN: treat an illegal state as a parameter code
    xFault := TRUE;                                                                        // 置故障标志 EN: raise the fault flag
    nFaultCode := DL_HTC_C_PARAM;                                                          // 故障码出口 EN: publish the fault code
    eState := E_DL_HeatTraceState.FAULT;                                                   // 迁故障相 EN: move to the fault phase
END_CASE
END_IF

// 段6｜故障锁存回放 + 两条复位路径（xStart 下降沿 / 传感器恢复沿）
IF eState = E_DL_HeatTraceState.FAULT THEN
    xFault := TRUE;                                                                        // 故障标志保持 EN: keep the fault flag
    nFaultCode := nCodeLatch;                                                              // 锁存回放，不按当下输入重推断 EN: replay the latch instead of re inferring
    nWarnCode := 0;                                                                        // 故障相不报信息级码 EN: no information class code in the fault phase
    xHeatCmd := FALSE;                                                                     // 加热强制关 EN: force the heating off
    xConservative := FALSE;                                                                // 故障相不对外宣称保守输出 EN: no conservative claim in the fault phase
    IF fbStartFall.Q THEN
        nCodeLatch := 0;                                                                   // 清除边：xStart 下降沿（头注释已声明） EN: clear on the falling edge of xStart
        eState := E_DL_HeatTraceState.IDLE;                                                // 回待机 EN: back to idle
    END_IF
END_IF
END_FUNCTION_BLOCK
