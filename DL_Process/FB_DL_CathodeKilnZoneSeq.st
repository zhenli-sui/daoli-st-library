(*
  Component : FB_DL_CathodeKilnZoneSeq
  Category  : DL_Process
  Function  : 辊道窑多温区升温曲线执行状态机：预热→升温→保温→冷却→出料
  Complexity: C4
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 xStart 启动（上升沿启动，下降沿兼故障复位沿）、xStop 停止、xRollerOk 辊道运行正常、
             xRodBroken 断棒检测、xDischDone 出料完成、afZoneTempC 八温区实测温度定长数组 [℃]
             （ARRAY[0..7]，未用槽填零，R15 显式定长）、nZoneCount 有效温区数 [区]、
             rStartC 起始炉温 [℃]、rPreheatC 预热终点 [℃]、rSoakSetC 保温设定 [℃]、
             rRampRateKmin 升降温速率上限 [K/min]、rTempTolK 区温偏差允许带 [K]、
             rOverTempK 超温判据余量 [K]、rCoolTargetC 冷却终点 [℃]、rSoakTimeS 保温时间 [s]、
             rHeatMaxS 升温允许最长 [s]、rCoolMaxS 冷却允许最长 [s]、rDischTmoS 出料超时 [s]。
  输出     : 三路独立命令、ePhase 当前相、xFault/nFaultCode 故障、nWarnCode 信息级码、
             rZoneDevMaxK 各区相对保温设定的最大偏差 [K]、rMaxTempC/rMinTempC 区温极值 [℃]、
             xOverTemp 超温标志、xRateViol 速率越限标志。
  时序     : 同拍双窗配比约束 rHeatMaxS ≥ (rSoakSetC − rStartC) / rRampRateKmin × 60（否则升温窗
             先于工艺升温完成即超时）、rCoolMaxS ≥ (rSoakSetC − rCoolTargetC) / rRampRateKmin × 60。
  速率限幅 : 升温相以进相时刻的炉温为基准，允许温度 = 基准 + 速率 × 已用时间，实测超越即本拍断加热；
             降温相以进相时刻的炉温为基准，允许温度 = 基准 − 速率 × 已用时间，实测低于即本拍断风机。
  安全侧   : 断棒（xRodBroken）与辊道停转（NOT xRollerOk）在非待机相立即迁 FAULT 并撤销全部命令；
             断棒/停转在待机相不锁存，但阻断启动（启动条件已含两者）。
  复位沿   : 故障码锁存至 xStart 下降沿；复位后停在 IDLE，需重新给出启动上升沿才继续（不做自动再入）。
  码位     : 9820 升温速率超限（信息级）；9821 降温速率超限（信息级）；9822 区温偏差超带（信息级）；
             9823 超温转冷却（信息级）；9824 断棒（故障级）；9825 辊道停转（故障级）；
             9826 参数或温度数组非法（故障级）；9827 升温超时（故障级）；9828 冷却超时（故障级）；
             9829 出料超时（故障级）。信息级码一律不置 xFault。
*)
TYPE E_DL_KilnPhase :
(
    IDLE      := 0,    // 待机，全部命令撤销 EN: idle, every command withdrawn
    PREHEAT   := 10,   // 预热段升温 EN: the preheat ramp phase
    RAMP      := 20,   // 升温段至保温设定 EN: the ramp phase towards the soak setpoint
    SOAK      := 30,   // 保温段 EN: the soak phase
    COOL      := 40,   // 冷却段 EN: the cooling phase
    DISCHARGE := 50,   // 出料段 EN: the discharge phase
    FAULT     := 90    // 故障相，全部命令强制撤销 EN: fault phase, every command forced off
);
END_TYPE

FUNCTION_BLOCK FB_DL_CathodeKilnZoneSeq
VAR_INPUT
    xStart       : BOOL;                        // 启动（上升沿启动，下降沿复位故障） EN: start on the rising edge, reset the fault on the falling edge
    xStop        : BOOL;                        // 停止（任意相生效） EN: stop, effective in every phase
    xRollerOk    : BOOL;                        // 辊道运行正常（变频器运行反馈） EN: the roller table runs normally
    xRodBroken   : BOOL;                        // 断棒检测（安全侧信号） EN: the broken rod detection, a safety side signal
    xDischDone   : BOOL;                        // 出料完成（下游确认） EN: the discharge is complete, confirmed downstream
    afZoneTempC  : ARRAY[0..7] OF REAL;         // 八温区实测温度，未用槽填零 [℃] EN: the measured temperatures of eight zones, unused slots hold zero
    nZoneCount   : INT := 8;                    // 有效温区数 [区] EN: the number of valid zones
    rStartC      : REAL := 25.0;                // 起始炉温（升温速率基准的缺省值） [℃] EN: the starting furnace temperature used as the default ramp base
    rPreheatC    : REAL := 400.0;               // 预热终点温度 [℃] EN: the preheat end temperature
    rSoakSetC    : REAL := 800.0;               // 保温设定温度 [℃] EN: the soak setpoint temperature
    rRampRateKmin: REAL := 3.0;                 // 升降温速率上限 [K/min] EN: the upper bound of the heating and cooling rate
    rTempTolK    : REAL := 15.0;                // 区温偏差允许带 [K] EN: the allowed zone temperature deviation band
    rOverTempK   : REAL := 20.0;                // 超温判据余量（超过设定即转冷却） [K] EN: the over temperature margin above the setpoint
    rCoolTargetC : REAL := 80.0;                // 冷却终点温度 [℃] EN: the cooling end temperature
    rSoakTimeS   : REAL := 3600.0;              // 保温时间设定 [s] EN: the soak time setting
    rHeatMaxS    : REAL := 7200.0;              // 升温允许最长（预热+升温合计） [s] EN: the longest heating time covering preheat and ramp
    rCoolMaxS    : REAL := 7200.0;              // 冷却允许最长 [s] EN: the longest cooling time
    rDischTmoS   : REAL := 1800.0;              // 出料超时设定 [s] EN: the discharge timeout setting
END_VAR
VAR_OUTPUT
    xHeatCmd    : BOOL;               // 加热使能命令 EN: the heating enable command
    xFanCoolCmd : BOOL;               // 冷却风机命令 EN: the cooling fan command
    xDischCmd   : BOOL;               // 出料辊道命令 EN: the discharge conveyor command
    ePhase      : E_DL_KilnPhase;     // 当前相 EN: the current phase
    xFault      : BOOL;               // 故障标志（仅故障级码置位） EN: the fault flag, raised by fault class codes only
    nFaultCode  : INT;                // 故障码，锁存回放 EN: the fault code replayed from the latch
    nWarnCode   : INT;                // 信息级码（每拍重算） EN: the information class code recomputed every cycle
    rZoneDevMaxK: REAL;               // 各区相对保温设定的最大偏差 [K] EN: the largest zone deviation from the soak setpoint
    rMaxTempC   : REAL;               // 区温最大值 [℃] EN: the highest zone temperature
    rMinTempC   : REAL;               // 区温最小值 [℃] EN: the lowest zone temperature
    xOverTemp   : BOOL;               // 超温标志 EN: the over temperature flag
    xRateViol   : BOOL;               // 速率越限标志 EN: the rate violation flag
END_VAR
VAR
    tonHeat    : TON;                 // 升温（预热+升温）总时长定时器 EN: the total heating timer
    tonSoak    : TON;                 // 保温定时器 EN: the soak timer
    tonCool    : TON;                 // 冷却时长定时器 EN: the cooling timer
    tonDisch   : TON;                 // 出料超时定时器 EN: the discharge timeout
    fbStartRise: R_TRIG;              // xStart 上升沿（唯一启动沿） EN: the rising edge of xStart, the only start edge
    fbStartFall: F_TRIG;              // xStart 下降沿（复位沿） EN: the falling edge of xStart, the reset edge
    xFinAll    : BOOL;                // 标量浮点入参有限 EN: the scalar floating inputs are finite
    xZoneFin   : BOOL;                // 全部有效温区读数有限 EN: every valid zone reading is finite
    xParamBad  : BOOL;                // 参数或数组非法 EN: a parameter or the array is illegal
    xZoneDevOk : BOOL;                // 区温偏差在允许带内 EN: the zone deviation is inside the band
    i          : INT;                 // 温区循环索引 [区] EN: the zone loop index
    nScan      : INT;                 // 实际扫描温区数 [区] EN: the effective zone scan count
    rMax       : REAL;                // 区温最大值累加器 [℃] EN: the zone maximum accumulator
    rMin       : REAL;                // 区温最小值累加器 [℃] EN: the zone minimum accumulator
    rDev       : REAL;                // 偏差累加器 [K] EN: the deviation accumulator
    rDevMax    : REAL;                // 最大偏差 [K] EN: the largest deviation
    rHeatBaseC : REAL;                // 升温相进相基准炉温 [℃] EN: the furnace temperature latched when heating starts
    rCoolBaseC : REAL;                // 冷却相进相基准炉温 [℃] EN: the furnace temperature latched when cooling starts
    rAllowC    : REAL;                // 本拍允许温度（速率限幅） [℃] EN: the temperature allowed in this cycle by the rate limit
    rElapsedS  : REAL;                // 相内已用时间 [s] EN: the elapsed time inside the phase
    nMsSoak    : UDINT := 3600000;    // 保温毫秒数（缺省防零 PT） EN: the soak milliseconds, the default avoids a zero preset
    nMsHeat    : UDINT := 7200000;    // 升温毫秒数 EN: the heating milliseconds
    nMsCool    : UDINT := 7200000;    // 冷却毫秒数 EN: the cooling milliseconds
    nMsDisch   : UDINT := 1800000;    // 出料毫秒数 EN: the discharge milliseconds
    nCodeLatch : INT;                 // 故障码锁存副本 EN: the latched copy of the fault code
END_VAR
VAR CONSTANT
    DL_CKZ_Z      : REAL := 0.0;      // 浮点零常量 EN: the floating point zero constant
    DL_CKZ_SECMIN : REAL := 60.0;     // 分钟换算秒系数 EN: the minute to second factor
    DL_CKZ_K1000  : REAL := 1000.0;   // 秒转毫秒系数 EN: the second to millisecond factor
    DL_CKZ_IDX_MAX: INT := 7;         // 温区数组上界索引 [区] EN: the zone array upper bound index
    DL_CKZ_CNT_MAX: INT := 8;         // 温区个数上限 [区] EN: the zone count upper bound
    DL_CKZ_W_RATE : INT := 9820;      // 升温速率超限（信息级） EN: the heating rate violation, information class
    DL_CKZ_W_COOL : INT := 9821;      // 降温速率超限（信息级） EN: the cooling rate violation, information class
    DL_CKZ_W_DEV  : INT := 9822;      // 区温偏差超带（信息级） EN: the zone deviation violation, information class
    DL_CKZ_W_OVER : INT := 9823;      // 超温转冷却（信息级） EN: the over temperature transfer, information class
    DL_CKZ_C_ROD  : INT := 9824;      // 断棒（故障级） EN: the broken rod
    DL_CKZ_C_ROLL : INT := 9825;      // 辊道停转（故障级） EN: the roller table stopped
    DL_CKZ_C_PARAM: INT := 9826;      // 参数或温度数组非法（故障级） EN: a parameter or the temperature array is illegal
    DL_CKZ_C_HEAT : INT := 9827;      // 升温超时（故障级） EN: the heating timed out
    DL_CKZ_C_COOL : INT := 9828;      // 冷却超时（故障级） EN: the cooling timed out
    DL_CKZ_C_DISCH: INT := 9829;      // 出料超时（故障级） EN: the discharge timed out
END_VAR

// 段1｜参数与采样门禁：标量浮点闸 + 温区数组逐个闸（先判后用，换算在闸后）
xFinAll := (rStartC = rStartC) AND ((rStartC - rStartC) = DL_CKZ_Z)
        AND (rPreheatC = rPreheatC) AND ((rPreheatC - rPreheatC) = DL_CKZ_Z)
        AND (rSoakSetC = rSoakSetC) AND ((rSoakSetC - rSoakSetC) = DL_CKZ_Z)
        AND (rRampRateKmin = rRampRateKmin) AND ((rRampRateKmin - rRampRateKmin) = DL_CKZ_Z)
        AND (rTempTolK = rTempTolK) AND ((rTempTolK - rTempTolK) = DL_CKZ_Z)
        AND (rOverTempK = rOverTempK) AND ((rOverTempK - rOverTempK) = DL_CKZ_Z)
        AND (rCoolTargetC = rCoolTargetC) AND ((rCoolTargetC - rCoolTargetC) = DL_CKZ_Z)
        AND (rSoakTimeS = rSoakTimeS) AND ((rSoakTimeS - rSoakTimeS) = DL_CKZ_Z)
        AND (rHeatMaxS = rHeatMaxS) AND ((rHeatMaxS - rHeatMaxS) = DL_CKZ_Z)
        AND (rCoolMaxS = rCoolMaxS) AND ((rCoolMaxS - rCoolMaxS) = DL_CKZ_Z)
        AND (rDischTmoS = rDischTmoS) AND ((rDischTmoS - rDischTmoS) = DL_CKZ_Z);                        // 十一个标量入参有限性 EN: the finiteness of all eleven scalar inputs
xParamBad := (NOT xFinAll) OR (nZoneCount < 1) OR (nZoneCount > DL_CKZ_CNT_MAX)
          OR (rRampRateKmin <= DL_CKZ_Z) OR (rSoakTimeS <= DL_CKZ_Z) OR (rHeatMaxS <= DL_CKZ_Z)
          OR (rCoolMaxS <= DL_CKZ_Z) OR (rDischTmoS <= DL_CKZ_Z) OR (rTempTolK <= DL_CKZ_Z)
          OR (rOverTempK < DL_CKZ_Z) OR (rSoakSetC <= rPreheatC) OR (rPreheatC <= rStartC)
          OR (rCoolTargetC >= rSoakSetC);                                                                 // 域闸与曲线单调性约束 EN: the domain gate and the profile monotonicity
nScan := nZoneCount;                                                                                      // 扫描个数 [区] EN: the scan count
rMax := DL_CKZ_Z;                                                                                         // 最大值初值 [℃] EN: the maximum accumulator initial value
rMin := DL_CKZ_Z;                                                                                         // 最小值初值 [℃] EN: the minimum accumulator initial value
rDevMax := DL_CKZ_Z;                                                                                      // 最大偏差初值 [K] EN: the largest deviation initial value
xZoneFin := TRUE;                                                                                         // 假定温区有限 EN: assume the zones are finite
IF (nScan >= 1) AND (nScan <= DL_CKZ_CNT_MAX) THEN                                                       // 个数合法才访问数组 EN: access the array only with a legal count
    FOR i := 0 TO nScan - 1 DO                                                                           // 定长数组循环（上界已证 ≤7） EN: the fixed array loop, the bound is proven at most seven
        IF (i >= 0) AND (i <= DL_CKZ_IDX_MAX) THEN                                                       // 逐元素双边界校验 EN: the per element bound check
            IF (afZoneTempC[i] = afZoneTempC[i]) AND ((afZoneTempC[i] - afZoneTempC[i]) = DL_CKZ_Z) THEN
                IF (i = 0) OR (afZoneTempC[i] > rMax) THEN                                               // 首元素或更大值 EN: the first element or a larger value
                    rMax := afZoneTempC[i];                                                              // 更新最大值 [℃] EN: update the maximum
                END_IF
                IF (i = 0) OR (afZoneTempC[i] < rMin) THEN                                               // 首元素或更小值 EN: the first element or a smaller value
                    rMin := afZoneTempC[i];                                                              // 更新最小值 [℃] EN: update the minimum
                END_IF
                rDev := ABS(afZoneTempC[i] - rSoakSetC);                                                 // 相对保温设定的偏差 [K] EN: the deviation from the soak setpoint
                IF rDev > rDevMax THEN                                                                   // 取更大偏差 EN: keep the larger deviation
                    rDevMax := rDev;                                                                     // 更新最大偏差 [K] EN: update the largest deviation
                END_IF
            ELSE
                xZoneFin := FALSE;                                                                       // 记非有限元素 EN: mark the non finite element
            END_IF
        END_IF
    END_FOR
ELSE
    xZoneFin := FALSE;                                                                                   // 个数非法等同读数不可用 EN: an illegal count makes the readings unusable
END_IF
xParamBad := xParamBad OR (NOT xZoneFin);                                                                // 读数不可用并入参数闸（单点写入） EN: merge the unusable readings into the parameter gate
IF (NOT xParamBad) THEN                                                                                  // 参数合法才做时间换算 EN: convert only when the parameters are legal
    nMsSoak := REAL_TO_UDINT(rSoakTimeS * DL_CKZ_K1000);                                                 // 保温毫秒数 EN: the soak milliseconds
    nMsHeat := REAL_TO_UDINT(rHeatMaxS * DL_CKZ_K1000);                                                  // 升温毫秒数 EN: the heating milliseconds
    nMsCool := REAL_TO_UDINT(rCoolMaxS * DL_CKZ_K1000);                                                  // 冷却毫秒数 EN: the cooling milliseconds
    nMsDisch := REAL_TO_UDINT(rDischTmoS * DL_CKZ_K1000);                                                // 出料毫秒数 EN: the discharge milliseconds
END_IF
xZoneDevOk := (NOT xParamBad) AND (rDevMax <= rTempTolK);                                                // 区温偏差带内判据 EN: the zone deviation band test

// 段2｜四只定时器 + 两只边沿实例无条件周期刷新（CASE 内不调用实例）
tonHeat(IN := (ePhase = E_DL_KilnPhase.PREHEAT) OR (ePhase = E_DL_KilnPhase.RAMP), PT := UDINT_TO_TIME(nMsHeat));  // 升温总时长 EN: the total heating time
tonSoak(IN := (ePhase = E_DL_KilnPhase.SOAK) AND xZoneDevOk, PT := UDINT_TO_TIME(nMsSoak));                          // 保温计时（偏差在带内才累计） EN: count the soak only inside the band
tonCool(IN := (ePhase = E_DL_KilnPhase.COOL), PT := UDINT_TO_TIME(nMsCool));                                         // 冷却时长 EN: the cooling time
tonDisch(IN := (ePhase = E_DL_KilnPhase.DISCHARGE), PT := UDINT_TO_TIME(nMsDisch));                                  // 出料时长 EN: the discharge time
fbStartRise(CLK := xStart);                                                                                          // 启动沿 EN: the start edge
fbStartFall(CLK := xStart);                                                                                          // 复位沿 EN: the reset edge

// 段3｜输出预置（唯一预置点，CASE 内只置位；信息级码每拍重算）
xHeatCmd := FALSE;                        // 加热预置关 EN: preset the heating off
xFanCoolCmd := FALSE;                     // 风机预置停 EN: preset the fan off
xDischCmd := FALSE;                       // 出料预置停 EN: preset the discharge off
xFault := FALSE;                          // 故障标志预置假 EN: preset the fault flag false
nFaultCode := 0;                          // 故障码预置零 EN: preset the fault code to zero
nWarnCode := 0;                           // 信息码预置零 EN: preset the warning code to zero
xOverTemp := FALSE;                       // 超温标志预置假 EN: preset the over temperature flag false
xRateViol := FALSE;                       // 速率越限标志预置假 EN: preset the rate violation flag false
rZoneDevMaxK := rDevMax;                  // 最大偏差出口 [K] EN: publish the largest deviation
rMaxTempC := rMax;                        // 区温最大值出口 [℃] EN: publish the highest zone temperature
rMinTempC := rMin;                        // 区温最小值出口 [℃] EN: publish the lowest zone temperature

// 段4｜全局安全闸：参数非法 / 断棒 / 辊道停转 → 锁故障；xStop 撤销命令回待机
IF xParamBad THEN
    nCodeLatch := DL_CKZ_C_PARAM;                                                                        // 参数非法锁存 EN: latch the parameter code
    xFault := TRUE;                                                                                      // 置故障标志 EN: raise the fault flag
    nFaultCode := DL_CKZ_C_PARAM;                                                                        // 故障码出口 EN: publish the fault code
    ePhase := E_DL_KilnPhase.FAULT;                                                                      // 迁故障相 EN: move to the fault phase
ELSIF xRodBroken AND (ePhase <> E_DL_KilnPhase.IDLE) THEN
    nCodeLatch := DL_CKZ_C_ROD;                                                                          // 断棒锁存 EN: latch the broken rod code
    xFault := TRUE;                                                                                      // 置故障标志 EN: raise the fault flag
    nFaultCode := DL_CKZ_C_ROD;                                                                          // 故障码出口 EN: publish the fault code
    ePhase := E_DL_KilnPhase.FAULT;                                                                      // 迁故障相 EN: move to the fault phase
ELSIF (NOT xRollerOk) AND (ePhase <> E_DL_KilnPhase.IDLE) THEN
    nCodeLatch := DL_CKZ_C_ROLL;                                                                         // 辊道停转锁存 EN: latch the roller stop code
    xFault := TRUE;                                                                                      // 置故障标志 EN: raise the fault flag
    nFaultCode := DL_CKZ_C_ROLL;                                                                         // 故障码出口 EN: publish the fault code
    ePhase := E_DL_KilnPhase.FAULT;                                                                      // 迁故障相 EN: move to the fault phase
ELSIF xStop AND (ePhase <> E_DL_KilnPhase.IDLE) THEN
    ePhase := E_DL_KilnPhase.IDLE;                                                                       // 撤销型停车回待机 EN: a withdrawing stop returns to idle
END_IF

// 段5｜主状态机（ENUM + CASE，ELSE 兜底非法值）
IF ePhase <> E_DL_KilnPhase.FAULT THEN
CASE ePhase OF
E_DL_KilnPhase.IDLE:
    // 拍 N：待机；启动需辊道正常、无断棒、无停车（入相即锁存速率限幅基准炉温）
    IF fbStartRise.Q AND xRollerOk AND (NOT xRodBroken) AND (NOT xStop) AND (NOT xParamBad) THEN
        rHeatBaseC := rMax;                                                                              // 锁存升温基准炉温 [℃] EN: latch the heating base temperature
        ePhase := E_DL_KilnPhase.PREHEAT;                                                                // 本拍行为：进预热相 EN: enter the preheat phase
    END_IF

E_DL_KilnPhase.PREHEAT:
    // 拍 N：预热升温，速率越限即本拍断加热（信息级 9820），升到预热终点转升温相
    rElapsedS := TIME_TO_REAL(tonHeat.ET) * 0.001;                                                       // 已用时间 [s] EN: the elapsed time
    rAllowC := rHeatBaseC + rRampRateKmin * (rElapsedS / DL_CKZ_SECMIN);                                 // 允许温度 [℃] EN: the temperature allowed by the rate limit
    IF rMax > (rAllowC + rTempTolK) THEN                                                                 // 速率越限判据 EN: the rate violation test
        xRateViol := TRUE;                                                                               // 置越限标志 EN: raise the rate flag
        nWarnCode := DL_CKZ_W_RATE;                                                                      // 信息级码，不置故障 EN: an information class code, no fault
    ELSE
        xHeatCmd := TRUE;                                                                                // 加热允许 EN: heating allowed
    END_IF
    IF rMax >= rPreheatC THEN                                                                            // 预热到位 EN: the preheat is complete
        ePhase := E_DL_KilnPhase.RAMP;                                                                   // 本拍行为：进升温相 EN: enter the ramp phase
    ELSIF tonHeat.Q THEN
        nCodeLatch := DL_CKZ_C_HEAT;                                                                     // 升温超时 EN: the heating timed out
        xFault := TRUE;                                                                                  // 置故障标志 EN: raise the fault flag
        nFaultCode := DL_CKZ_C_HEAT;                                                                     // 故障码出口 EN: publish the fault code
        ePhase := E_DL_KilnPhase.FAULT;                                                                  // 迁故障相 EN: move to the fault phase
    END_IF

E_DL_KilnPhase.RAMP:
    // 拍 N：升温至保温设定，含速率限幅与升温超时兜底
    rElapsedS := TIME_TO_REAL(tonHeat.ET) * 0.001;                                                       // 已用时间（含预热相） [s] EN: the elapsed time including the preheat phase
    rAllowC := rHeatBaseC + rRampRateKmin * (rElapsedS / DL_CKZ_SECMIN);                                 // 允许温度 [℃] EN: the allowed temperature
    IF rMax > (rAllowC + rTempTolK) THEN                                                                 // 速率越限判据 EN: the rate violation test
        xRateViol := TRUE;                                                                               // 置越限标志 EN: raise the rate flag
        nWarnCode := DL_CKZ_W_RATE;                                                                      // 信息级码 EN: the information class code
    ELSE
        xHeatCmd := TRUE;                                                                                // 加热允许 EN: heating allowed
    END_IF
    IF rMax >= (rSoakSetC - rTempTolK) THEN                                                              // 到达保温窗口下沿 EN: reached the lower edge of the soak window
        ePhase := E_DL_KilnPhase.SOAK;                                                                   // 本拍行为：进保温相 EN: enter the soak phase
    ELSIF tonHeat.Q THEN
        nCodeLatch := DL_CKZ_C_HEAT;                                                                     // 升温超时 EN: the heating timed out
        xFault := TRUE;                                                                                  // 置故障标志 EN: raise the fault flag
        nFaultCode := DL_CKZ_C_HEAT;                                                                     // 故障码出口 EN: publish the fault code
        ePhase := E_DL_KilnPhase.FAULT;                                                                  // 迁故障相 EN: move to the fault phase
    END_IF

E_DL_KilnPhase.SOAK:
    // 拍 N：保温；超温立即转冷却（信息级 9823），偏差超带只告警（9822）且不累计保温时间
    IF rMax > (rSoakSetC + rOverTempK) THEN                                                              // 超温判据 EN: the over temperature test
        xOverTemp := TRUE;                                                                               // 置超温标志 EN: raise the over temperature flag
        nWarnCode := DL_CKZ_W_OVER;                                                                      // 超温信息级码 EN: the over temperature information code
        rCoolBaseC := rMin;                                                                              // 锁存冷却基准炉温 [℃] EN: latch the cooling base temperature
        ePhase := E_DL_KilnPhase.COOL;                                                                   // 本拍行为：立即转冷却 EN: transfer to cooling immediately
    ELSIF NOT xZoneDevOk THEN
        nWarnCode := DL_CKZ_W_DEV;                                                                       // 偏差超带告警（信息级） EN: warn about the zone deviation
        xHeatCmd := TRUE;                                                                                // 保持加热以拉回设定 EN: keep heating to recover the setpoint
    ELSE
        xHeatCmd := TRUE;                                                                                // 保温加热 EN: soak heating
        IF tonSoak.Q THEN                                                                                // 保温时间到 EN: the soak time elapsed
            rCoolBaseC := rMin;                                                                          // 锁存冷却基准炉温 [℃] EN: latch the cooling base temperature
            ePhase := E_DL_KilnPhase.COOL;                                                               // 本拍行为：进冷却相 EN: enter the cooling phase
        END_IF
    END_IF

E_DL_KilnPhase.COOL:
    // 拍 N：冷却；降温过快本拍断风机（信息级 9821），降到终点转出料，冷却超时判 9828
    rElapsedS := TIME_TO_REAL(tonCool.ET) * 0.001;                                                       // 冷却已用时间 [s] EN: the cooling elapsed time
    rAllowC := rCoolBaseC - rRampRateKmin * (rElapsedS / DL_CKZ_SECMIN);                                 // 允许温度（速率下限） [℃] EN: the allowed temperature floor
    IF rMin < (rAllowC - rTempTolK) THEN                                                                 // 降温超速率判据 EN: the over fast cooling test
        xRateViol := TRUE;                                                                               // 置越限标志 EN: raise the rate flag
        nWarnCode := DL_CKZ_W_COOL;                                                                      // 信息级码 EN: the information class code
    ELSE
        xFanCoolCmd := TRUE;                                                                             // 风机允许 EN: the fan is allowed
    END_IF
    IF rMax <= rCoolTargetC THEN                                                                         // 冷却到位 EN: the cooling is complete
        ePhase := E_DL_KilnPhase.DISCHARGE;                                                              // 本拍行为：进出料相 EN: enter the discharge phase
    ELSIF tonCool.Q THEN
        nCodeLatch := DL_CKZ_C_COOL;                                                                     // 冷却超时 EN: the cooling timed out
        xFault := TRUE;                                                                                  // 置故障标志 EN: raise the fault flag
        nFaultCode := DL_CKZ_C_COOL;                                                                     // 故障码出口 EN: publish the fault code
        ePhase := E_DL_KilnPhase.FAULT;                                                                  // 迁故障相 EN: move to the fault phase
    END_IF

E_DL_KilnPhase.DISCHARGE:
    // 拍 N：出料；下游确认回待机，超时判 9829（迁入本相已带参数闸复检）
    IF xDischDone THEN                                                                                   // 出料完成 EN: the discharge is complete
        ePhase := E_DL_KilnPhase.IDLE;                                                                   // 本拍行为：回待机 EN: back to idle
    ELSIF tonDisch.Q THEN
        nCodeLatch := DL_CKZ_C_DISCH;                                                                    // 出料超时 EN: the discharge timed out
        xFault := TRUE;                                                                                  // 置故障标志 EN: raise the fault flag
        nFaultCode := DL_CKZ_C_DISCH;                                                                    // 故障码出口 EN: publish the fault code
        ePhase := E_DL_KilnPhase.FAULT;                                                                  // 迁故障相 EN: move to the fault phase
    END_IF

E_DL_KilnPhase.FAULT:
    // 故障相（本段被外层 IF 排除，保留分支以满足枚举穷举）
    xFault := TRUE;                                                                                      // 保持故障标志 EN: keep the fault flag
    nFaultCode := nCodeLatch;                                                                            // 锁存回放 EN: replay the latch

ELSE
    // 非法状态兜底：绝不停在未知相
    nCodeLatch := DL_CKZ_C_PARAM;                                                                        // 非法状态归参数码 EN: treat an illegal state as a parameter code
    xFault := TRUE;                                                                                      // 置故障标志 EN: raise the fault flag
    nFaultCode := DL_CKZ_C_PARAM;                                                                        // 故障码出口 EN: publish the fault code
    ePhase := E_DL_KilnPhase.FAULT;                                                                      // 迁故障相 EN: move to the fault phase
END_CASE
END_IF

// 段6｜相独立使能出口（IDLE/FAULT 不置任何命令，天然强制撤销；出料相另给辊道命令）
CASE ePhase OF
E_DL_KilnPhase.DISCHARGE:
    xDischCmd := TRUE;                                                                                   // 出料辊道命令 EN: the discharge conveyor command
ELSE
    xDischCmd := FALSE;                                                                                  // 其余相撤销出料命令 EN: withdraw the discharge command elsewhere
END_CASE

// 段7｜故障相锁存回放 + 复位沿（xStart 下降沿清除，复位后停 IDLE 需重新给启动上升沿）
IF ePhase = E_DL_KilnPhase.FAULT THEN
    xFault := TRUE;                                                                                      // 故障标志保持 EN: keep the fault flag
    nFaultCode := nCodeLatch;                                                                            // 锁存回放，不按当下输入重推断 EN: replay the latch instead of re inferring
    nWarnCode := 0;                                                                                      // 故障相不报信息级码 EN: no information class code in the fault phase
    xHeatCmd := FALSE;                                                                                   // 加热强制关 EN: force the heating off
    xFanCoolCmd := FALSE;                                                                                // 风机强制停（断棒时避免热冲击） EN: force the fan off to avoid a thermal shock
    xDischCmd := FALSE;                                                                                  // 出料强制停 EN: force the discharge off
    IF fbStartFall.Q THEN
        nCodeLatch := 0;                                                                                 // 清除边：xStart 下降沿（头注释已声明） EN: clear on the falling edge of xStart
        ePhase := E_DL_KilnPhase.IDLE;                                                                   // 回待机 EN: back to idle
    END_IF
END_IF
END_FUNCTION_BLOCK
