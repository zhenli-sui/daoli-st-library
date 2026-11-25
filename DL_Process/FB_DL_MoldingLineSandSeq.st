(*
 * FB_DL_MoldingLineSandSeq | C4 | DL_Process
 * 功能：造型线「回砂→磁选→冷却→混砂→松砂→造型→浇注」序列控制；每相独立使能出口 + 独立 TON 超时，冷却相按砂温判据转出、浇注相按许可驻留       单位：温度 [℃]、rTimeoutS [s]、码位 [INT]
 * 工况边界：COOLING 只在 rSandTempC ≤ rSandTempMaxC 时转 MULLING，超时判 9701；POURING 无 xPourPermit 时驻留并只发告警 9702（告警级，不置 xFault），浇注相超时判 9709；砂温 NaN/±Inf 或越量程（-20~200 ℃）判 9708；rTimeoutS 须 >0；xStart 只用上升沿启动，xStop 按逆序（浇注→造型→松砂→混砂→冷却→磁选→回砂）撤令
 * 代数值回代：rSandTempC=42.0 ≤ rSandTempMaxC=45 → 冷却完成转混砂；rSandTempC=52.0 >45 → 驻留冷却直至 9701（与 spec 判据一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
(*
 * 码位总账（本件故障码全清单，逐条在实现分支中可到达；故障级锁存回放）：
 * 9701 冷却温度超时 / 9702 浇注许可缺失（告警级，不置 xFault）/ 9703 回砂相就绪丢失 / 9704 磁选相回砂就绪丢失 / 9705 混砂相供砂就绪丢失 / 9706 松砂相造型机未就绪 / 9707 造型相就绪未建立 / 9708 砂温或参数非法 / 9709 浇注超时（故障锁存，清除沿 = xStart 下降沿）；MAGNET/MULLING/AERATING 正常以驻留定时转出，其码位仅在就绪丢失时置位
 *)

TYPE E_DL_SandLinePhase :
(
    IDLE        := 0,    // 待机，全部命令撤销 | idle, every command withdrawn
    RETURN_SAND := 10,   // 回砂相，旧砂输送 | return sand conveying
    MAGNET      := 20,   // 磁选相，除铁器投入 | magnetic separation
    COOLING     := 30,   // 冷却相，沸腾冷却床 | cooling bed
    MULLING     := 40,   // 混砂相，混砂机加水加膨润土 | mulling
    AERATING    := 50,   // 松砂相，松砂机打散 | aerating
    MOLDING     := 60,   // 造型相，造型机射砂压实 | molding
    POURING     := 70,   // 浇注相，等待浇注许可 | pouring, waiting for the permit
    FAULT       := 90    // 故障相，全部命令强制 FALSE，码位锁存 | fault phase, all commands forced FALSE, the code is latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_MoldingLineSandSeq
VAR_INPUT
    xStart        : BOOL;            // 启动（下降沿兼作故障复位沿）| start, its falling edge also resets a latched fault
    xStop         : BOOL;            // 停止（任意相生效，逆序停车）| stop, effective in any phase and stopping in reverse order
    xSandReady    : BOOL;            // 回砂段就绪 | return sand section ready
    xMoldReady    : BOOL;            // 造型机就绪 | molding machine ready
    xPourPermit   : BOOL;            // 浇注许可（来自浇注机/行车）| pouring permit from the pouring device
    rSandTempC    : REAL;            // 型砂温度 | molding sand temperature [℃]
    rSandTempMaxC : REAL := 45.0;    // 允许混砂的最高砂温 | maximum sand temperature for mulling [℃]
    rTimeoutS     : REAL := 90.0;    // 每相超时设定 | per-phase timeout setting [s]
END_VAR
VAR_OUTPUT
    xReturnCmd : BOOL;               // 回砂命令（RETURN_SAND 相独立使能）| return sand command, independent enable
    xMagnetCmd : BOOL;               // 磁选命令（MAGNET 相独立使能）| magnet command, independent enable
    xCoolCmd   : BOOL;               // 冷却命令（COOLING 相独立使能）| cooling command, independent enable
    xMullerCmd : BOOL;               // 混砂命令（MULLING 相独立使能）| mulling command, independent enable
    xAerateCmd : BOOL;               // 松砂命令（AERATING 相独立使能）| aerating command, independent enable
    xMoldCmd   : BOOL;               // 造型命令（MOLDING 相独立使能）| molding command, independent enable
    xPourCmd   : BOOL;               // 浇注命令（POURING 相且许可到位独立使能）| pouring command, independent enable when permitted
    ePhase     : E_DL_SandLinePhase; // 当前相 | current phase
    xFault     : BOOL;               // 故障标志（仅故障级码置位）| fault flag, fault-class codes only
    nFaultCode : INT;                // 故障码，锁存至复位沿 | fault code latched until the reset edge
    nWarnCode  : INT;                // 告警码（9702 浇注许可缺失，信息级不置 xFault）| warning code for the missing pouring permit
END_VAR
VAR
    tonReturn : TON;                 // RETURN_SAND 相超时定时器 | timeout of RETURN_SAND
    tonMagnet : TON;                 // MAGNET 相超时定时器 | timeout of MAGNET
    tonCool   : TON;                 // COOLING 相超时定时器 | timeout of COOLING
    tonMull   : TON;                 // MULLING 相超时定时器 | timeout of MULLING
    tonAerate : TON;                 // AERATING 相超时定时器 | timeout of AERATING
    tonMold   : TON;                 // MOLDING 相超时定时器 | timeout of MOLDING
    tonPour   : TON;                 // POURING 相超时定时器 | timeout of POURING
    fbStartRise : R_TRIG;            // xStart 上升沿（唯一启动沿）| rising edge of xStart, the single start edge
    fbStartFall : F_TRIG;            // xStart 下降沿（故障复位沿）| falling edge of xStart, the fault reset edge
    xParamOk  : BOOL;                // 超时与砂温上限参数合法 | timeout and sand temperature limit are legal
    xFinTemp  : BOOL;                // 砂温有限性 | sand temperature is finite
    xTempBad  : BOOL;                // 砂温非有限或越量程 | sand temperature non-finite or out of range
    xCoolDone : BOOL;                // 冷却到位（砂温 ≤ 上限）| cooling done, temperature within the limit
    nTmoMs    : UDINT := 90000;      // 超时毫秒数（缺省值防首拍 PT=0 假超时）| timeout in milliseconds, default prevents a zero PT
    nCodeLatch: INT;                 // 故障码锁存副本 | latched copy of the fault code
END_VAR
VAR CONSTANT
    DL_SLS_TEMP_MAX : REAL := 200.0; // 砂温量程上限 | upper sand temperature limit [℃]
    DL_SLS_TEMP_MIN : REAL := -20.0; // 砂温量程下限 | lower sand temperature limit [℃]
    DL_SLS_C_COOL   : INT := 9701;   // 冷却温度超时 | cooling temperature timeout
    DL_SLS_C_PERMIT : INT := 9702;   // 浇注许可缺失（告警级）| missing pouring permit, warning class
    DL_SLS_C_RETURN : INT := 9703;   // 回砂超时 | return sand timeout
    DL_SLS_C_MAGNET : INT := 9704;   // 磁选超时 | magnet timeout
    DL_SLS_C_MULL   : INT := 9705;   // 混砂超时 | mulling timeout
    DL_SLS_C_AERATE : INT := 9706;   // 松砂超时 | aerating timeout
    DL_SLS_C_MOLD   : INT := 9707;   // 造型超时 | molding timeout
    DL_SLS_C_BAD    : INT := 9708;   // 砂温或参数非法 | sand temperature or parameter illegal
    DL_SLS_C_POUR   : INT := 9709;   // 浇注超时 | pouring timeout
END_VAR

// 段1｜参数与采样门禁（先判后用：REAL→UDINT 换算在闸后进行，结果供段2 定时器使用）
xParamOk := (rTimeoutS = rTimeoutS) AND ((rTimeoutS - rTimeoutS) = 0.0) AND (rTimeoutS > 0.0)
            AND (rSandTempMaxC = rSandTempMaxC) AND ((rSandTempMaxC - rSandTempMaxC) = 0.0);
IF xParamOk THEN
    nTmoMs := REAL_TO_UDINT(rTimeoutS * 1000.0);
ELSE
    nTmoMs := 90000;                 // 参数非法取保守值 | conservative value on an illegal parameter
END_IF
xFinTemp := (rSandTempC = rSandTempC) AND ((rSandTempC - rSandTempC) = 0.0);
xTempBad := (NOT xFinTemp) OR (rSandTempC > DL_SLS_TEMP_MAX) OR (rSandTempC < DL_SLS_TEMP_MIN);
xCoolDone := (NOT xTempBad) AND (rSandTempC <= rSandTempMaxC);

// 段2｜七只定时器 + 两只边沿实例无条件周期刷新（R7，一相一只实例不跨相复用；PT 取自段1 已换算毫秒值）
tonReturn(IN := ePhase = E_DL_SandLinePhase.RETURN_SAND, PT := UDINT_TO_TIME(nTmoMs));
tonMagnet(IN := ePhase = E_DL_SandLinePhase.MAGNET, PT := UDINT_TO_TIME(nTmoMs));
tonCool(IN := ePhase = E_DL_SandLinePhase.COOLING, PT := UDINT_TO_TIME(nTmoMs));
tonMull(IN := ePhase = E_DL_SandLinePhase.MULLING, PT := UDINT_TO_TIME(nTmoMs));
tonAerate(IN := ePhase = E_DL_SandLinePhase.AERATING, PT := UDINT_TO_TIME(nTmoMs));
tonMold(IN := ePhase = E_DL_SandLinePhase.MOLDING, PT := UDINT_TO_TIME(nTmoMs));
tonPour(IN := ePhase = E_DL_SandLinePhase.POURING, PT := UDINT_TO_TIME(nTmoMs));
fbStartRise(CLK := xStart);
fbStartFall(CLK := xStart);

// 段3｜输出预置（唯一预置点，CASE 内只置位）
xReturnCmd := FALSE;
xMagnetCmd := FALSE;
xCoolCmd := FALSE;
xMullerCmd := FALSE;
xAerateCmd := FALSE;
xMoldCmd := FALSE;
xPourCmd := FALSE;
xFault := FALSE;
nFaultCode := 0;
nWarnCode := 0;

// 段4｜全局闸：参数/砂温非法 → 锁故障；xStop → 逆序停车
IF (NOT xParamOk) OR xTempBad THEN
    nCodeLatch := DL_SLS_C_BAD;
    xFault := TRUE;
    nFaultCode := DL_SLS_C_BAD;
    ePhase := E_DL_SandLinePhase.FAULT;
ELSIF xStop AND (ePhase <> E_DL_SandLinePhase.IDLE) THEN
    xPourCmd := FALSE;               // 逆序停车第 1 步：浇注先停 | reverse stop step 1, pouring first
    xMoldCmd := FALSE;               // 逆序停车第 2 步：造型 | step 2, molding
    xAerateCmd := FALSE;             // 逆序停车第 3 步：松砂 | step 3, aerating
    xMullerCmd := FALSE;             // 逆序停车第 4 步：混砂 | step 4, mulling
    xCoolCmd := FALSE;               // 逆序停车第 5 步：冷却 | step 5, cooling
    xMagnetCmd := FALSE;             // 逆序停车第 6 步：磁选 | step 6, magnet
    xReturnCmd := FALSE;             // 逆序停车第 7 步：回砂最后停（下游优先，同拍置假）| step 7, return sand last
    ePhase := E_DL_SandLinePhase.IDLE;
END_IF

// 段5｜主状态机（ENUM + CASE，ELSE 兜底）
IF ePhase <> E_DL_SandLinePhase.FAULT THEN
CASE ePhase OF
E_DL_SandLinePhase.IDLE:
    // 拍 N：待机，仅 xStart 上升沿且回砂就绪时启动（防停车后自恢复）
    IF fbStartRise.Q AND xSandReady AND (NOT xStop) THEN
        ePhase := E_DL_SandLinePhase.RETURN_SAND;     // 本拍行为：进回砂相 | enter return sand
    END_IF

E_DL_SandLinePhase.RETURN_SAND:
    // 拍 N：回砂输送到位由驻留定时判完成；期间回砂就绪丢失即报 9703（启动条件已含 xSandReady，故不以其为转出条件）
    IF NOT xSandReady THEN
        nCodeLatch := DL_SLS_C_RETURN;                // 回砂就绪丢失 | return sand readiness lost
        xFault := TRUE;
        nFaultCode := DL_SLS_C_RETURN;
        ePhase := E_DL_SandLinePhase.FAULT;
    ELSIF tonReturn.Q THEN
        ePhase := E_DL_SandLinePhase.MAGNET;          // 本拍行为：进磁选相 | enter magnet
    END_IF

E_DL_SandLinePhase.MAGNET:
    // 拍 N：磁选除铁，回砂段中断即报 9704；正常由驻留定时转冷却
    IF NOT xSandReady THEN
        nCodeLatch := DL_SLS_C_MAGNET;                // 回砂段中断，磁选无法维持 | return sand interrupted
        xFault := TRUE;
        nFaultCode := DL_SLS_C_MAGNET;
        ePhase := E_DL_SandLinePhase.FAULT;
    ELSIF tonMagnet.Q THEN
        ePhase := E_DL_SandLinePhase.COOLING;         // 本拍行为：进冷却相 | enter cooling
    END_IF

E_DL_SandLinePhase.COOLING:
    // 拍 N：沸腾冷却，砂温降到上限以下才进混砂；超时判 9701
    IF xCoolDone THEN
        ePhase := E_DL_SandLinePhase.MULLING;         // 本拍行为：砂温达标进混砂 | sand cool enough, enter mulling
    ELSIF tonCool.Q THEN
        nCodeLatch := DL_SLS_C_COOL;                  // 冷却温度超时 | cooling temperature timeout
        xFault := TRUE;
        nFaultCode := DL_SLS_C_COOL;
        ePhase := E_DL_SandLinePhase.FAULT;
    END_IF

E_DL_SandLinePhase.MULLING:
    // 拍 N：混砂（加水、加膨润土），供砂中断即报 9705；正常由驻留定时转松砂
    IF NOT xSandReady THEN
        nCodeLatch := DL_SLS_C_MULL;                  // 供砂中断，混砂配比失真 | sand supply interrupted, the batch would be off-ratio
        xFault := TRUE;
        nFaultCode := DL_SLS_C_MULL;
        ePhase := E_DL_SandLinePhase.FAULT;
    ELSIF tonMull.Q THEN
        ePhase := E_DL_SandLinePhase.AERATING;        // 本拍行为：进松砂相 | enter aerating
    END_IF

E_DL_SandLinePhase.AERATING:
    // 拍 N：松砂打散，造型机未就绪即报 9706（砂无去处）；正常由驻留定时转造型
    IF NOT xMoldReady THEN
        nCodeLatch := DL_SLS_C_AERATE;                // 造型机未就绪，松砂后无处送 | molding machine not ready, no destination
        xFault := TRUE;
        nFaultCode := DL_SLS_C_AERATE;
        ePhase := E_DL_SandLinePhase.FAULT;
    ELSIF tonAerate.Q THEN
        ePhase := E_DL_SandLinePhase.MOLDING;         // 本拍行为：进造型相 | enter molding
    END_IF

E_DL_SandLinePhase.MOLDING:
    // 拍 N：造型射砂压实，等造型机就绪确认与时间窗
    IF tonMold.Q AND xMoldReady THEN
        ePhase := E_DL_SandLinePhase.POURING;         // 本拍行为：进浇注相 | enter pouring
    ELSIF tonMold.Q AND (NOT xMoldReady) THEN
        nCodeLatch := DL_SLS_C_MOLD;                  // 造型就绪始终未建立 | molding readiness never established
        xFault := TRUE;
        nFaultCode := DL_SLS_C_MOLD;
        ePhase := E_DL_SandLinePhase.FAULT;
    END_IF

E_DL_SandLinePhase.POURING:
    // 拍 N：等浇注许可；无许可只驻留并告警 9702，不置故障
    IF NOT xPourPermit THEN
        nWarnCode := DL_SLS_C_PERMIT;                 // 告警级：许可缺失（信息级码永不置 bError）| warning class, never raises the fault flag
        IF tonPour.Q THEN
            nCodeLatch := DL_SLS_C_POUR;              // 浇注超时：锁存 9709 | pouring timeout, latch 9709
            xFault := TRUE;
            nFaultCode := DL_SLS_C_POUR;
            ePhase := E_DL_SandLinePhase.FAULT;
        END_IF
    ELSIF tonPour.Q THEN
        ePhase := E_DL_SandLinePhase.IDLE;            // 本拍行为：浇注完成回待机 | pouring done, back to idle
    END_IF

E_DL_SandLinePhase.FAULT:
    // 故障相（本段被外层 IF 排除，保留分支以满足穷举）
    xFault := TRUE;
    nFaultCode := nCodeLatch;

ELSE
    // 非法状态兜底：绝不停在未知相
    nCodeLatch := DL_SLS_C_BAD;
    xFault := TRUE;
    nFaultCode := DL_SLS_C_BAD;
    ePhase := E_DL_SandLinePhase.FAULT;
END_CASE
END_IF

// 段6｜每相独立使能出口（IDLE/FAULT 不置任何命令，天然强制 FALSE）
CASE ePhase OF
E_DL_SandLinePhase.RETURN_SAND:
    xReturnCmd := TRUE;                           // 回砂相独立使能出口 | independent enable of RETURN_SAND
E_DL_SandLinePhase.MAGNET:
    xMagnetCmd := TRUE;                           // 磁选相独立使能出口 | independent enable of MAGNET
E_DL_SandLinePhase.COOLING:
    xCoolCmd := TRUE;                             // 冷却相独立使能出口 | independent enable of COOLING
E_DL_SandLinePhase.MULLING:
    xMullerCmd := TRUE;                           // 混砂相独立使能出口 | independent enable of MULLING
E_DL_SandLinePhase.AERATING:
    xAerateCmd := TRUE;                           // 松砂相独立使能出口 | independent enable of AERATING
E_DL_SandLinePhase.MOLDING:
    xMoldCmd := TRUE;                             // 造型相独立使能出口 | independent enable of MOLDING
E_DL_SandLinePhase.POURING:
    xPourCmd := xPourPermit;                      // 浇注相独立使能出口（无许可不浇注）| independent enable of POURING, gated by the permit
ELSE
    xReturnCmd := FALSE;                          // 其余相（含 FAULT）：命令强制 FALSE | all other phases force FALSE
    xMagnetCmd := FALSE;
    xCoolCmd := FALSE;
    xMullerCmd := FALSE;
    xAerateCmd := FALSE;
    xMoldCmd := FALSE;
    xPourCmd := FALSE;
END_CASE

// 段7｜故障相锁存回放 + 复位沿（xStart 下降沿清除）
IF ePhase = E_DL_SandLinePhase.FAULT THEN
    xFault := TRUE;
    nFaultCode := nCodeLatch;                     // 锁存回放，不按当下输入重推断 | republish the latch
    xReturnCmd := FALSE;
    xMagnetCmd := FALSE;
    xCoolCmd := FALSE;
    xMullerCmd := FALSE;
    xAerateCmd := FALSE;
    xMoldCmd := FALSE;
    xPourCmd := FALSE;
    nWarnCode := 0;
    IF fbStartFall.Q THEN
        nCodeLatch := 0;                          // 清除边：xStart 下降沿（头注释已声明）| clear edge declared in the header
        ePhase := E_DL_SandLinePhase.IDLE;
    END_IF
END_IF
END_FUNCTION_BLOCK
