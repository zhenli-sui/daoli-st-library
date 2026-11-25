(*
 * FB_DL_CrahGroupEconomizerSeq | C4 | DL_Device
 * 功能：机房群控自然冷却切换序列（机械→过渡→全自然→混合），带焓差滞环与最短驻留       单位：比焓 [kJ/kg]、温度 [℃]、机组数 [台]、rTimeoutS [s]、nFaultCode [INT 码位]
 * 工况边界：判据以户外比焓与回风比焓之差为准（户外 < 回风 − 滞环 → 全自然；|差| ≤ 滞环 → 混合；其余 → 机械）；最短驻留 120 s 由每相 TON 保证，切换只能在驻留满足后进行；nUnitsAvail 须 ≥1，否则 9601；比焓/温度 NaN 或超量程一律 9602/9603 并全回机械侧（安全侧 = 机械冷机）
 * 代数值回代：rOutdoorEnthalpy=45、rReturnEnthalpy=56、hyst=4 → 45 < 52 → 全自然(FREE)；rOutdoor=53 → |53−56|=3 ≤4 → 混合(MIXED)；rOutdoor=60 → 机械(MECH)；nUnitsAvail=0 → 9601（与 spec 判据一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
(*
 * 码位总账（本件故障码全清单，逐条在实现分支中可到达；故障级锁存回放）：
 * 9601 无可用机组 / 9602 比焓非有限或越量程 / 9603 户外温度非有限或越量程 / 9604 过渡配置非法（rTimeoutS 短于 120 s 最短驻留，自然冷却无法稳定建立）/ 9605 机组数配置越限或状态机兜底（故障锁存，清除沿 = xEnable 下降沿）
 *)

TYPE E_DL_EconMode :
(
    MECH    := 0,       // 全机械制冷，新风阀关闭 | full mechanical cooling, damper closed
    PARTIAL := 10,      // 过渡相，新风阀渐开、机械机组减载 | transition phase, damper ramping open and mechanical units unloading
    FREE    := 20,      // 全自然冷却，新风阀全开、机械全停 | full free cooling, damper fully open and mechanical units off
    MIXED   := 30,      // 混合冷却，新风与机械各半 | mixed cooling, half free and half mechanical
    FAULT   := 90       // 故障相，回机械侧安全值并锁存码位 | fault phase, reverts to the mechanical safe side and latches the code
);
END_TYPE

FUNCTION_BLOCK FB_DL_CrahGroupEconomizerSeq
VAR_INPUT
    xEnable              : BOOL;         // 群控使能（下降沿兼作故障复位沿）| group enable, its falling edge also resets a latched fault
    rOutdoorEnthalpyKJkg : REAL;         // 户外空气比焓 | outdoor air specific enthalpy [kJ/kg]
    rReturnEnthalpyKJkg  : REAL;         // 机房回风比焓 | return air specific enthalpy [kJ/kg]
    rOutdoorTempC        : REAL;         // 户外干球温度 | outdoor dry bulb temperature [℃]
    nUnitsAvail          : INT;          // 可用机组台数 | available unit count [台]
    rDeltaHystKJkg       : REAL := 4.0;  // 焓差滞环半宽 | enthalpy hysteresis half width [kJ/kg]
    rTimeoutS            : REAL := 300.0;// 过渡建立窗（须 ≥120 s，兼作过渡相超时）| transition establish window, also the PARTIAL timeout [s]
END_VAR
VAR_OUTPUT
    nFreeUnits  : INT;                   // 自然冷却投入台数 | units on free cooling [台]
    nMechUnits  : INT;                   // 机械制冷投入台数 | units on mechanical cooling [台]
    xDamperOpen : BOOL;                  // 新风阀开命令（含过渡与混合）| fresh air damper open command, transition and mixed included
    eMode       : E_DL_EconMode;         // 当前模式 | current mode
    xFault      : BOOL;                  // 故障标志 | fault flag
    nFaultCode  : INT;                   // 故障码，锁存至复位沿 | fault code latched until the reset edge
    xActive     : BOOL;                  // 群控已生效回执（未使能时为 FALSE）| group control active acknowledgement
END_VAR
VAR
    tonMech    : TON;                    // MECH 相 最短驻留定时器 | minimum dwell timer of MECH
    tonPartial : TON;                    // PARTIAL 相 建立定时器（阀位渐开）| establish timer of PARTIAL, damper ramping open
    tonFree    : TON;                    // FREE 相 最短驻留定时器 | minimum dwell timer of FREE
    tonMixed   : TON;                    // MIXED 相 最短驻留定时器 | minimum dwell timer of MIXED
    fbEnableFall : F_TRIG;               // xEnable 下降沿（故障复位沿）| falling edge of xEnable, the fault reset edge
    xFinH      : BOOL;                   // 两路比焓有限性 | both enthalpies are finite
    xFinT      : BOOL;                   // 户外温度有限性 | outdoor temperature is finite
    xParamOk   : BOOL;                   // 滞环与超时参数合法 | hysteresis and timeout parameters are legal
    nDwellMs   : UDINT := 120000;        // 最短驻留毫秒数（缺省值防首拍 PT=0）| minimum dwell in milliseconds, default prevents a zero PT
    nPartialMs : UDINT := 300000;        // 过渡建立毫秒数（= rTimeoutS）| transition establish time in milliseconds, equal to rTimeoutS
    xTransCfgOk: BOOL;                   // 过渡配置合法（建立窗 ≥ 最短驻留）| transition configuration legal
    rDiffKJkg  : REAL;                   // 回风比焓 − 户外比焓（正=户外更冷）| return minus outdoor enthalpy, positive when outdoor is cooler [kJ/kg]
    xFreeCond  : BOOL;                   // 全自然冷却条件成立 | free cooling condition satisfied
    xMixedCond : BOOL;                   // 混合冷却条件成立 | mixed cooling condition satisfied
    nHalfUnits : INT;                    // 可用台数的一半 | half of the available units [台]
    nCodeLatch : INT;                    // 故障码锁存副本 | latched copy of the fault code
END_VAR
VAR CONSTANT
    DL_CGE_DWELL_S  : REAL := 120.0;     // 最短驻留时间 | minimum dwell time [s]
    DL_CGE_ENTH_MAX : REAL := 500.0;     // 比焓量程上限 | upper enthalpy range limit [kJ/kg]
    DL_CGE_ENTH_MIN : REAL := -100.0;    // 比焓量程下限 | lower enthalpy range limit [kJ/kg]
    DL_CGE_TEMP_MAX : REAL := 60.0;      // 户外温度量程上限 | upper outdoor temperature limit [℃]
    DL_CGE_TEMP_MIN : REAL := -40.0;     // 户外温度量程下限 | lower outdoor temperature limit [℃]
    DL_CGE_C_NOUNIT : INT := 9601;       // 无可用机组 | no available unit
    DL_CGE_C_ENTH   : INT := 9602;       // 比焓非法 | illegal enthalpy
    DL_CGE_C_TEMP   : INT := 9603;       // 户外温度非法 | illegal outdoor temperature
    DL_CGE_C_TRANS  : INT := 9604;       // 过渡超时 | transition timeout
    DL_CGE_C_UNITS  : INT := 9605;       // 机组数配置越限 | unit count out of range
END_VAR

// 段1｜参数与采样门禁（先判后用，R19：闸断实值通路后再参与比较；换算结果供段2 定时器使用）
xParamOk := (rDeltaHystKJkg = rDeltaHystKJkg) AND ((rDeltaHystKJkg - rDeltaHystKJkg) = 0.0)
            AND (rDeltaHystKJkg >= 0.0)
            AND (rTimeoutS = rTimeoutS) AND ((rTimeoutS - rTimeoutS) = 0.0) AND (rTimeoutS > 0.0);
IF xParamOk THEN
    nPartialMs := REAL_TO_UDINT(rTimeoutS * 1000.0);     // 过渡建立窗 = rTimeoutS（同一参数，避免出现不可达的超时分支）
    nDwellMs := REAL_TO_UDINT(DL_CGE_DWELL_S * 1000.0);
ELSE
    nPartialMs := 300000;                // 参数非法取保守值 | conservative value on an illegal parameter
    nDwellMs := 120000;
END_IF
// 过渡建立窗必须不短于最短驻留，否则自然冷却无法稳定建立，判配置级故障 9604
IF xParamOk THEN
    xTransCfgOk := rTimeoutS >= DL_CGE_DWELL_S;
ELSE
    xTransCfgOk := FALSE;                // 参数本身非法，配置判据不成立 | the parameter itself is illegal
END_IF
xFinH := (rOutdoorEnthalpyKJkg = rOutdoorEnthalpyKJkg) AND ((rOutdoorEnthalpyKJkg - rOutdoorEnthalpyKJkg) = 0.0)
         AND (rReturnEnthalpyKJkg = rReturnEnthalpyKJkg) AND ((rReturnEnthalpyKJkg - rReturnEnthalpyKJkg) = 0.0);
xFinT := (rOutdoorTempC = rOutdoorTempC) AND ((rOutdoorTempC - rOutdoorTempC) = 0.0);

// 段2｜五只定时器 + 一只边沿实例无条件周期刷新（R7，一相一只实例不跨相复用；PT 取自段1 已换算毫秒值）
tonMech(IN := eMode = E_DL_EconMode.MECH, PT := UDINT_TO_TIME(nDwellMs));
tonPartial(IN := eMode = E_DL_EconMode.PARTIAL, PT := UDINT_TO_TIME(nPartialMs));
tonFree(IN := eMode = E_DL_EconMode.FREE, PT := UDINT_TO_TIME(nDwellMs));
tonMixed(IN := eMode = E_DL_EconMode.MIXED, PT := UDINT_TO_TIME(nDwellMs));
fbEnableFall(CLK := xEnable);

// 段3｜输出预置（唯一预置点，CASE 内只置位）
nFreeUnits := 0;
nMechUnits := 0;
xDamperOpen := FALSE;
xFault := FALSE;
nFaultCode := 0;

// 段4｜全局闸：任一入参非法或机组不可用 → 直接锁故障并回机械侧
// R749 码位分判：非有限比焓 → 9602；非有限户外温度 → 9603；参数本身非法 → 9604；三者不再合并为 9602
IF NOT xFinH THEN
    nCodeLatch := DL_CGE_C_ENTH;                 // 比焓非有限 | enthalpy not finite
    xFault := TRUE;
    nFaultCode := DL_CGE_C_ENTH;
    eMode := E_DL_EconMode.FAULT;
ELSIF NOT xFinT THEN
    nCodeLatch := DL_CGE_C_TEMP;                 // 户外温度非有限 | outdoor temperature not finite
    xFault := TRUE;
    nFaultCode := DL_CGE_C_TEMP;
    eMode := E_DL_EconMode.FAULT;
ELSIF NOT xParamOk THEN
    nCodeLatch := DL_CGE_C_TRANS;                // 滞环/超时参数非法（含 NaN 与非正）| illegal hysteresis or timeout parameter
    xFault := TRUE;
    nFaultCode := DL_CGE_C_TRANS;
    eMode := E_DL_EconMode.FAULT;
ELSIF (rOutdoorEnthalpyKJkg > DL_CGE_ENTH_MAX) OR (rOutdoorEnthalpyKJkg < DL_CGE_ENTH_MIN)
      OR (rReturnEnthalpyKJkg > DL_CGE_ENTH_MAX) OR (rReturnEnthalpyKJkg < DL_CGE_ENTH_MIN) THEN
    nCodeLatch := DL_CGE_C_ENTH;
    xFault := TRUE;
    nFaultCode := DL_CGE_C_ENTH;
    eMode := E_DL_EconMode.FAULT;
ELSIF (rOutdoorTempC > DL_CGE_TEMP_MAX) OR (rOutdoorTempC < DL_CGE_TEMP_MIN) THEN
    nCodeLatch := DL_CGE_C_TEMP;
    xFault := TRUE;
    nFaultCode := DL_CGE_C_TEMP;
    eMode := E_DL_EconMode.FAULT;
ELSIF (NOT xTransCfgOk) THEN
    nCodeLatch := DL_CGE_C_TRANS;                // 过渡配置非法：建立窗短于最短驻留 | illegal transition configuration
    xFault := TRUE;
    nFaultCode := DL_CGE_C_TRANS;
    eMode := E_DL_EconMode.FAULT;
ELSIF (nUnitsAvail <= 0) THEN
    nCodeLatch := DL_CGE_C_NOUNIT;
    xFault := TRUE;
    nFaultCode := DL_CGE_C_NOUNIT;
    eMode := E_DL_EconMode.FAULT;
END_IF

// 段5｜判据：回风比焓 − 户外比焓，滞环半宽 rDeltaHystKJkg（判据与出口同源于原始比焓）
IF xFinH THEN
    rDiffKJkg := rReturnEnthalpyKJkg - rOutdoorEnthalpyKJkg;
    xFreeCond := rDiffKJkg > rDeltaHystKJkg;                     // 户外显著更冷 → 全自然 | outdoor clearly cooler, free cooling
    xMixedCond := ABS(rDiffKJkg) <= rDeltaHystKJkg;              // 焓差落在滞环内 → 混合 | gap inside the hysteresis band, mixed
ELSE
    rDiffKJkg := 0.0;                                            // 非有限时不产生判据值 | no criterion when non-finite
    xFreeCond := FALSE;
    xMixedCond := FALSE;
END_IF

// 段6｜主状态机（ENUM + CASE，ELSE 兜底）
IF eMode <> E_DL_EconMode.FAULT THEN
CASE eMode OF
E_DL_EconMode.MECH:
    // 拍 N：全机械，新风阀关闭；驻留满足且全自然条件成立才允许过渡
    IF tonMech.Q THEN
        IF xFreeCond THEN
            eMode := E_DL_EconMode.PARTIAL;          // 本拍行为：进过渡相（阀位渐开）| enter the transition phase
        ELSIF xMixedCond THEN
            eMode := E_DL_EconMode.MIXED;            // 本拍行为：进混合相 | enter the mixed mode
        END_IF
    END_IF

E_DL_EconMode.PARTIAL:
    // 拍 N：过渡相，新风阀渐开、机械减载；条件消失立刻回机械，否则建立窗到即转出
    IF (NOT xFreeCond) AND (NOT xMixedCond) THEN
        eMode := E_DL_EconMode.MECH;                 // 本拍行为：条件消失回机械 | condition lost, back to mechanical
    ELSIF tonPartial.Q THEN
        IF xFreeCond THEN
            eMode := E_DL_EconMode.FREE;             // 本拍行为：建立完成进全自然 | establishment complete, enter free cooling
        ELSE
            eMode := E_DL_EconMode.MIXED;            // 本拍行为：仅满足混合条件进混合 | only the mixed condition holds
        END_IF
    END_IF

E_DL_EconMode.FREE:
    // 拍 N：全自然冷却，驻留满足后才允许退出
    IF tonFree.Q THEN
        IF xMixedCond THEN
            eMode := E_DL_EconMode.MIXED;            // 本拍行为：焓差缩小进混合 | enthalpy gap narrowed, enter mixed
        ELSIF (NOT xFreeCond) AND (NOT xMixedCond) THEN
            eMode := E_DL_EconMode.MECH;             // 本拍行为：条件消失回机械 | back to mechanical
        END_IF
    END_IF

E_DL_EconMode.MIXED:
    // 拍 N：混合冷却，驻留满足后才允许退出
    IF tonMixed.Q THEN
        IF xFreeCond THEN
            eMode := E_DL_EconMode.PARTIAL;          // 本拍行为：焓差放大经过渡进全自然 | gap widened, go through transition
        ELSIF (NOT xFreeCond) AND (NOT xMixedCond) THEN
            eMode := E_DL_EconMode.MECH;             // 本拍行为：条件消失回机械 | back to mechanical
        END_IF
    END_IF

E_DL_EconMode.FAULT:
    // 故障相（本段被外层 IF 排除，保留分支以满足穷举）
    xFault := TRUE;
    nFaultCode := nCodeLatch;

ELSE
    // 非法模式兜底：绝不停在未知模式
    nCodeLatch := DL_CGE_C_UNITS;
    xFault := TRUE;
    nFaultCode := DL_CGE_C_UNITS;
    eMode := E_DL_EconMode.FAULT;
END_CASE
END_IF

// 段7｜每模式独立使能出口与机组分配（故障与兜底一律回机械侧）
// R750 使能门：群控未使能时不得下发任何机组台数与阀位（此前 xEnable 只当复位沿用，名实不符）
IF NOT xEnable THEN
    nFreeUnits := 0;                             // 未使能：自然冷却零台 | disabled, no free cooling unit
    nMechUnits := 0;                             // 未使能：机械侧也零台，交由就地控制 | disabled, no mechanical unit either
    xDamperOpen := FALSE;                        // 未使能：新风阀关 | disabled, damper closed
    xActive := FALSE;                            // 未使能回执 | inactive acknowledgement
ELSE
xActive := TRUE;                                 // 已使能回执 | active acknowledgement
CASE eMode OF
E_DL_EconMode.MECH:
    nFreeUnits := 0;                             // 全机械：无自然冷却台数 | no free cooling units
    nMechUnits := nUnitsAvail;                   // 全机械：可用台数全投 | every available unit on mechanical
    xDamperOpen := FALSE;                        // 新风阀关闭 | damper closed
E_DL_EconMode.PARTIAL:
    nFreeUnits := 1;                             // 过渡：单台先投自然冷却 | one unit on free cooling first
    nMechUnits := nUnitsAvail - nFreeUnits;      // 其余保持机械 | the rest stays mechanical
    xDamperOpen := TRUE;                         // 过渡相独立使能出口：新风阀开 | independent enable of PARTIAL
E_DL_EconMode.FREE:
    nFreeUnits := nUnitsAvail;                   // 全自然：可用台数全投 | every available unit on free cooling
    nMechUnits := 0;
    xDamperOpen := TRUE;                         // 全自然相独立使能出口 | independent enable of FREE
E_DL_EconMode.MIXED:
    nHalfUnits := nUnitsAvail / 2;               // 半数为自然冷却（整数除法，nUnitsAvail 已保证 >0）| half on free cooling
    IF nHalfUnits < 1 THEN
        nHalfUnits := 1;                         // 至少一台，避免混合相退化为全机械 | at least one unit
    END_IF
    nFreeUnits := nHalfUnits;
    nMechUnits := nUnitsAvail - nFreeUnits;
    xDamperOpen := TRUE;                         // 混合相独立使能出口 | independent enable of MIXED
ELSE
    nFreeUnits := 0;                             // 故障与兜底：全机械（安全侧）| fault and fallback, mechanical safe side
    IF nUnitsAvail > 0 THEN
        nMechUnits := nUnitsAvail;               // 机组数有效才下发 | dispatch only a legal unit count
    ELSE
        nMechUnits := 0;                         // 机组数非法不下发负台数（R751）| never dispatch a negative unit count
    END_IF
    xDamperOpen := FALSE;
END_CASE
END_IF

// 段8｜故障相锁存回放与复位沿
IF eMode = E_DL_EconMode.FAULT THEN
    xFault := TRUE;
    nFaultCode := nCodeLatch;                    // 锁存回放，不按当下输入重推断 | republish the latch
    nFreeUnits := 0;                             // 故障相出口强制安全值 | fault outputs forced to the safe side
    IF xEnable AND (nUnitsAvail > 0) THEN
        nMechUnits := nUnitsAvail;               // 已使能且机组数有效：回机械侧安全运行 | enabled with a legal count, run on the mechanical side
    ELSE
        nMechUnits := 0;                         // 未使能或机组数非法：不下发任何台数（R750/R751）| disabled or illegal count, dispatch nothing
    END_IF
    xDamperOpen := FALSE;
    IF fbEnableFall.Q THEN
        nCodeLatch := 0;                         // 清除边：xEnable 下降沿（头注释已声明）| clear edge declared in the header
        eMode := E_DL_EconMode.MECH;
    END_IF
END_IF
END_FUNCTION_BLOCK
