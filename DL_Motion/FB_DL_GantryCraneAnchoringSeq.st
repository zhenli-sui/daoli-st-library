(*
 * FB_DL_GantryCraneAnchoringSeq | C4 | DL_Motion
 * 功能：大车自动锚定与防风防滑序列（风速分级→减速→夹轨→锚定→解除）；每相独立使能出口 + 独立 TON 超时，超时回 FAULT 并回退全部命令       单位：rWindMs [m/s]、rTimeoutS [s]、nFaultCode [INT 码位]
 * 工况边界：工作状态风速 0~40 m/s（GB/T 3811 分级：<13.8 正常 / 13.8~20 降速 / 20~25 停工夹轨锚定 / >25 直接锚定）；rTimeoutS 须 >0；解除仅当风速 <13.8、xRelease 有效且锚定驻留已满一个超时窗；全速许可须在 IDLE 稳定驻留满一个超时窗才恢复；风速 NaN/±Inf 一律按最不利(锚定侧)处理；IDLE/WIND_WARN/DECEL/ANCHORED 的 TON 为监督/驻留定时（驻留超时只置信息码 9106，绝不升级为锚定），CLAMPING/ANCHORING/RELEASING 的 TON 为故障超时（码表见下）；xEnable=FALSE 时两路输出回落失电安全侧（夹轨/锚定销弹簧夹紧型），但**不改变相位**
 * 代数值回代：rWindMs=22.0 → DECEL→CLAMPING→ANCHORED（20~25 区间）；rWindMs=26.0 → 直跳 ANCHORING；rWindMs=8.0 且 xRelease=TRUE → RELEASING→IDLE（与 spec 分级回代一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
(*
 * 码位总账（本件故障码全清单，逐条在实现分支中可到达；故障级锁存回放）：
 * 9101 夹轨超时 / 9102 锚定超时 / 9103 解除超时 / 9104 风速越限解除被拒 / 9105 入参非有限或状态机兜底 / 9106 降速相驻留超时（信息级，不置故障）——故障锁存，清除沿 = xEnable 下降沿（仅下降沿，不用电平）
 *)

TYPE E_DL_GcAnchorPhase :
(
    IDLE      := 0,      // 待机，允许行车，无夹轨无锚定命令 | idle, travelling permitted, no clamp and no anchor command
    WIND_WARN := 10,     // 降速相，风速 13.8~20，允许低速行车 | derated phase, wind 13.8 to 20, slow travel permitted
    DECEL     := 20,     // 减速停车相，风速 20~25，撤销行车许可 | deceleration phase, wind 20 to 25, travel permit withdrawn
    CLAMPING  := 30,     // 夹轨相，等夹轨到位反馈 | clamping phase, waiting for the rail clamp feedback
    ANCHORING := 40,     // 锚定相，等锚定到位反馈 | anchoring phase, waiting for the anchor feedback
    ANCHORED  := 50,     // 已锚定稳态，全部防风机构到位 | anchored steady state, all wind devices engaged
    RELEASING := 60,     // 解除相，等夹轨与锚定同时松开 | releasing phase, waiting for clamp and anchor to retract
    FAULT     := 90      // 故障相，全部命令回退为 FALSE，码位锁存 | fault phase, every command reverts to FALSE, the code is latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_GantryCraneAnchoringSeq
VAR_INPUT
    xEnable      : BOOL;             // 序列总使能（下降沿兼作故障复位沿）| sequence enable, its falling edge also resets a latched fault
    xRelease     : BOOL;             // 解除请求，仅风速 <13.8 时被接受 | release request, accepted only when the wind is below 13.8
    rWindMs      : REAL;             // 实测风速（3 s 均值）| measured wind speed, 3 s mean [m/s]
    xRailClampFb : BOOL;             // 夹轨到位反馈 | rail clamp engaged feedback
    xAnchorFb    : BOOL;             // 锚定销到位反馈 | anchor pin engaged feedback
    rTimeoutS    : REAL := 20.0;     // 每相超时设定 | per-phase timeout setting [s]
END_VAR
VAR_OUTPUT
    xClampCmd       : BOOL;          // 夹轨命令（仅 CLAMPING/ANCHORING/ANCHORED 为 TRUE）| rail clamp command, TRUE in CLAMPING, ANCHORING and ANCHORED only
    xAnchorCmd      : BOOL;          // 锚定命令（仅 ANCHORING/ANCHORED 为 TRUE）| anchor command, TRUE in ANCHORING and ANCHORED only
    ePhase          : E_DL_GcAnchorPhase;  // 当前相 | current phase
    xPermitTravel   : BOOL;          // 行车许可（仅 IDLE 与 WIND_WARN 为 TRUE）| travel permit, TRUE in IDLE and WIND_WARN only
    xPermitFullSpeed: BOOL;          // 全速许可（仅 IDLE 为 TRUE）| full speed permit, TRUE in IDLE only
    xFault          : BOOL;          // 故障标志（故障级码才置位）| fault flag, raised by fault-class codes only
    nFaultCode      : INT;           // 故障码，锁存至复位沿 | fault code, latched until the reset edge
END_VAR
VAR
    tonIdle     : TON;               // IDLE 相监督定时器 | supervision timer of the IDLE phase
    tonWarn     : TON;               // WIND_WARN 相驻留定时器 | dwell timer of the WIND_WARN phase
    tonDecel    : TON;               // DECEL 相减速驻留定时器 | deceleration dwell timer of the DECEL phase
    tonClampTmo : TON;               // CLAMPING 相故障超时定时器 | fault timeout of the CLAMPING phase
    tonAnchorTmo: TON;               // ANCHORING 相故障超时定时器 | fault timeout of the ANCHORING phase
    tonAnchored : TON;               // ANCHORED 相监督定时器 | supervision timer of the ANCHORED phase
    tonReleaseTmo: TON;              // RELEASING 相故障超时定时器 | fault timeout of the RELEASING phase
    fbEnableFall: F_TRIG;            // xEnable 下降沿检测（故障复位沿）| falling edge of xEnable, the fault reset edge
    xFinWind    : BOOL;              // 风速有限性 | wind speed is finite
    xWindBad    : BOOL;              // 风速非有限或超量程 | wind speed non-finite or out of range
    xParamOk    : BOOL;              // 超时参数合法（有限且 >0）| timeout parameter is legal, finite and positive
    nTmoMs      : UDINT := 20000;    // 超时毫秒数（REAL→UDINT 标准转换，缺省值防首拍 PT=0）| timeout in milliseconds with a default preventing a zero PT on the first scan
    nDecelMs    : UDINT := 3000;     // 减速驻留毫秒数 | deceleration dwell in milliseconds
    rWindChk    : REAL;              // 判定用风速（非有限时置最不利值）| wind value used for grading, forced to the worst case when non-finite
    nCodeLatch  : INT;               // 故障码锁存副本 | latched copy of the fault code
END_VAR
VAR CONSTANT
    DL_GCA_WIND_DERATE : REAL := 13.8;   // 降速风速阈 | derating wind threshold [m/s]
    DL_GCA_WIND_STOP   : REAL := 20.0;   // 停工夹轨风速阈 | stop and clamp wind threshold [m/s]
    DL_GCA_WIND_ANCHOR : REAL := 25.0;   // 强制锚定风速阈 | mandatory anchoring wind threshold [m/s]
    DL_GCA_WIND_MAX    : REAL := 40.0;   // 风速量程上限 | upper wind range limit [m/s]
    DL_GCA_DECEL_S     : REAL := 3.0;    // 减速驻留时间（变频器斜坡）| deceleration dwell matching the drive ramp [s]
    DL_GCA_C_WIND_OVER : INT := 9104;    // 风速越限解除被拒 | release refused because the wind is over limit
    DL_GCA_C_CLAMP_TMO : INT := 9101;    // 夹轨超时 | rail clamp timeout
    DL_GCA_C_ANCH_TMO  : INT := 9102;    // 锚定超时 | anchoring timeout
    DL_GCA_C_REL_TMO   : INT := 9103;    // 解除超时 | releasing timeout
    DL_GCA_C_BAD       : INT := 9105;    // 入参非有限或状态机兜底 | non-finite input or state machine fallback
    DL_GCA_I_WARN_DWELL : INT := 9106;   // 信息级：降速相驻留超时（不置 xFault）| info level, derated phase dwell expired
END_VAR

// 段1｜参数与采样门禁（先判后用：所有 REAL→UDINT 换算在闸后进行；换算结果供段2 定时器使用）
xParamOk := (rTimeoutS = rTimeoutS) AND ((rTimeoutS - rTimeoutS) = 0.0) AND (rTimeoutS > 0.0);
xFinWind := (rWindMs = rWindMs) AND ((rWindMs - rWindMs) = 0.0);
xWindBad := (NOT xFinWind) OR (rWindMs < 0.0) OR (rWindMs > DL_GCA_WIND_MAX);
IF xWindBad THEN
    rWindChk := DL_GCA_WIND_MAX;     // 风速不可信一律按最不利（锚定侧）分级 | an untrusted wind value is graded at the worst case
ELSE
    rWindChk := rWindMs;
END_IF
IF NOT xParamOk THEN
    nTmoMs := 20000;                 // 参数非法时的保守超时 | conservative timeout when the parameter is illegal
    nDecelMs := 3000;
ELSE
    nTmoMs := REAL_TO_UDINT(rTimeoutS * 1000.0);
    nDecelMs := REAL_TO_UDINT(DL_GCA_DECEL_S * 1000.0);
END_IF

// 段2｜七只定时器 + 一只边沿实例无条件周期刷新（R7：严禁放入 IF/CASE，一相一只实例不跨相复用）
// PT 取自段1 已换算的毫秒值；声明缺省值保证首拍 PT 不为 0，不会出现首拍即 Q=TRUE 的假超时
tonIdle(IN := (ePhase = E_DL_GcAnchorPhase.IDLE) AND xEnable, PT := UDINT_TO_TIME(nTmoMs));
tonWarn(IN := ePhase = E_DL_GcAnchorPhase.WIND_WARN, PT := UDINT_TO_TIME(nTmoMs));
tonDecel(IN := ePhase = E_DL_GcAnchorPhase.DECEL, PT := UDINT_TO_TIME(nDecelMs));
tonClampTmo(IN := ePhase = E_DL_GcAnchorPhase.CLAMPING, PT := UDINT_TO_TIME(nTmoMs));
tonAnchorTmo(IN := ePhase = E_DL_GcAnchorPhase.ANCHORING, PT := UDINT_TO_TIME(nTmoMs));
tonAnchored(IN := ePhase = E_DL_GcAnchorPhase.ANCHORED, PT := UDINT_TO_TIME(nTmoMs));
tonReleaseTmo(IN := ePhase = E_DL_GcAnchorPhase.RELEASING, PT := UDINT_TO_TIME(nTmoMs));
fbEnableFall(CLK := xEnable);

// 段3｜输出预置（出口唯一预置点，CASE 内只置位，绝不在其后无条件清零）
xClampCmd := FALSE;
xAnchorCmd := FALSE;
xPermitTravel := FALSE;
xPermitFullSpeed := FALSE;
xFault := FALSE;
nFaultCode := 0;

// 段4｜主状态机（ENUM + CASE，含 ELSE 兜底）
CASE ePhase OF
E_DL_GcAnchorPhase.IDLE:
    // 拍 N 进入：IDLE，夹轨与锚定均复位，行车许可有效
    xPermitTravel := TRUE;                                   // 本拍行为：行车许可（降速以上即撤）| this scan: travel permitted
    xPermitFullSpeed := tonIdle.Q;                           // 全速许可须在 IDLE 稳定驻留满一个超时窗（风速持续低于降速阈）| full speed only after a stable dwell
    IF xWindBad THEN
        ePhase := E_DL_GcAnchorPhase.ANCHORING;              // 风速不可信：跳级直锚（安全侧）| untrusted wind, anchor at once
    ELSIF rWindChk > DL_GCA_WIND_ANCHOR THEN
        ePhase := E_DL_GcAnchorPhase.ANCHORING;              // >25：直接锚定 | above 25, anchor directly
    ELSIF rWindChk > DL_GCA_WIND_STOP THEN
        ePhase := E_DL_GcAnchorPhase.DECEL;                  // 20~25：先减速再夹轨锚定 | 20 to 25, decelerate then clamp and anchor
    ELSIF rWindChk >= DL_GCA_WIND_DERATE THEN
        ePhase := E_DL_GcAnchorPhase.WIND_WARN;              // 13.8~20：降速 | 13.8 to 20, derate
    END_IF
    // 拍 N+1：若进 ANCHORING/DECEL，本拍命令仍全 FALSE（命令在目标相置位）

E_DL_GcAnchorPhase.WIND_WARN:
    // 拍 N 进入：降速相，行车许可保留、全速许可撤销
    xPermitTravel := TRUE;                                   // 本拍行为：仅保留降速行车许可 | this scan: derated travel only
    xPermitFullSpeed := FALSE;
    IF rWindChk > DL_GCA_WIND_STOP THEN
        ePhase := E_DL_GcAnchorPhase.DECEL;                  // 升过 20：转减速 | above 20, go to deceleration
    ELSIF rWindChk < DL_GCA_WIND_DERATE - 1.0 THEN
        ePhase := E_DL_GcAnchorPhase.IDLE;                   // 回落 1 m/s 滞环后恢复全速（须先于驻留判定，否则 Q 恒真致本分支永不可达）| hysteresis first, otherwise tonWarn.Q latches and blocks it
    ELSIF tonWarn.Q THEN
        nFaultCode := DL_GCA_I_WARN_DWELL;                   // 降速相驻留超时：仅置信息码，不升级为锚定（13.8~20 m/s 属降速作业区，GB/T 3811）| dwell expired, informational only, no escalation
    END_IF

E_DL_GcAnchorPhase.DECEL:
    // 拍 N 进入：减速停车，行车许可撤销，夹轨命令尚未给出
    IF tonDecel.Q THEN
        ePhase := E_DL_GcAnchorPhase.CLAMPING;               // 本拍行为：减速完成转夹轨 | deceleration done, go to clamping
    ELSIF rWindChk > DL_GCA_WIND_ANCHOR THEN
        ePhase := E_DL_GcAnchorPhase.ANCHORING;              // 超 25：跳过夹轨直锚 | above 25, skip clamping and anchor
    END_IF

E_DL_GcAnchorPhase.CLAMPING:
    // 拍 N 进入：夹轨命令置位（段5），等夹轨到位反馈
    IF xRailClampFb THEN
        ePhase := E_DL_GcAnchorPhase.ANCHORING;              // 本拍行为：夹轨到位转锚定 | clamp engaged, go to anchoring
    ELSIF tonClampTmo.Q THEN
        nCodeLatch := DL_GCA_C_CLAMP_TMO;                    // 夹轨超时：锁存 9101 | clamp timeout, latch 9101
        xFault := TRUE;
        nFaultCode := DL_GCA_C_CLAMP_TMO;
        ePhase := E_DL_GcAnchorPhase.FAULT;
    END_IF

E_DL_GcAnchorPhase.ANCHORING:
    // 拍 N 进入：夹轨 + 锚定命令同时置位（段5），等锚定销到位
    IF xAnchorFb AND xRailClampFb THEN
        ePhase := E_DL_GcAnchorPhase.ANCHORED;               // 本拍行为：双到位转锚定稳态 | both engaged, go to the anchored steady state
    ELSIF tonAnchorTmo.Q THEN
        nCodeLatch := DL_GCA_C_ANCH_TMO;                     // 锚定超时：锁存 9102 | anchoring timeout, latch 9102
        xFault := TRUE;
        nFaultCode := DL_GCA_C_ANCH_TMO;
        ePhase := E_DL_GcAnchorPhase.FAULT;
    END_IF

E_DL_GcAnchorPhase.ANCHORED:
    // 拍 N 进入：稳态锚定，行车许可全撤
    IF (NOT xAnchorFb) OR (NOT xRailClampFb) THEN
        ePhase := E_DL_GcAnchorPhase.ANCHORING;              // 反馈丢失：回锚定相重试（超时由 9102 兜底）| feedback lost, retry anchoring
    ELSIF xRelease AND tonAnchored.Q AND (rWindChk < DL_GCA_WIND_DERATE) THEN
        ePhase := E_DL_GcAnchorPhase.RELEASING;              // 本拍行为：锚定驻留满足且风速达标，转解除相 | dwell satisfied and wind low, go to releasing
    ELSIF xRelease AND (rWindChk >= DL_GCA_WIND_DERATE) THEN
        nFaultCode := DL_GCA_C_WIND_OVER;                    // 信息级：风速越限解除被拒（不置 xFault）| info: release refused because of the wind
    END_IF

E_DL_GcAnchorPhase.RELEASING:
    // 拍 N 进入：解除相，夹轨与锚定命令均撤销（段5）
    IF (NOT xAnchorFb) AND (NOT xRailClampFb) THEN
        ePhase := E_DL_GcAnchorPhase.IDLE;                   // 本拍行为：双松开转待机 | both retracted, back to idle
    ELSIF rWindChk >= DL_GCA_WIND_DERATE THEN
        nCodeLatch := DL_GCA_C_WIND_OVER;                    // 解除中风速回升：回锚定并锁 9104 | wind rose during release, re-anchor and latch 9104
        xFault := TRUE;
        nFaultCode := DL_GCA_C_WIND_OVER;
        ePhase := E_DL_GcAnchorPhase.FAULT;
    ELSIF tonReleaseTmo.Q THEN
        nCodeLatch := DL_GCA_C_REL_TMO;                      // 解除超时：锁存 9103 | releasing timeout, latch 9103
        xFault := TRUE;
        nFaultCode := DL_GCA_C_REL_TMO;
        ePhase := E_DL_GcAnchorPhase.FAULT;
    END_IF

E_DL_GcAnchorPhase.FAULT:
    // 拍 N 进入：故障相，全部命令回退 FALSE，码位锁存重发布
    xClampCmd := FALSE;                                      // 本拍行为：夹轨命令回退 | this scan: clamp command reverted
    xAnchorCmd := FALSE;                                     // 本拍行为：锚定命令回退 | this scan: anchor command reverted
    xFault := TRUE;
    nFaultCode := nCodeLatch;                                // 锁存回放，不在故障相按当下输入重推断 | republish the latch instead of re-inferring
    IF fbEnableFall.Q THEN
        nCodeLatch := 0;                                     // 清除边：仅 xEnable 下降沿（电平清除会导致故障每拍被清、锚定销周期性重击）| clear on the falling edge only
        ePhase := E_DL_GcAnchorPhase.IDLE;
    END_IF

ELSE
    // 非法状态兜底：绝不停在未知相
    nCodeLatch := DL_GCA_C_BAD;                              // 兜底锁存 9105 | fallback latches 9105
    xFault := TRUE;
    nFaultCode := DL_GCA_C_BAD;
    xClampCmd := FALSE;
    xAnchorCmd := FALSE;
    ePhase := E_DL_GcAnchorPhase.FAULT;
END_CASE

// 段5｜每相独立使能出口（故障与兜底相不置任何命令，天然强制 FALSE）
CASE ePhase OF
E_DL_GcAnchorPhase.CLAMPING:
    xClampCmd := TRUE;                                       // 夹轨相独立使能出口 | independent enable output of the clamping phase
E_DL_GcAnchorPhase.ANCHORING:
    xClampCmd := TRUE;                                       // 锚定相：夹轨保持 | anchoring, keep the clamp
    xAnchorCmd := TRUE;                                      // 锚定相独立使能出口 | independent enable output of the anchoring phase
E_DL_GcAnchorPhase.ANCHORED:
    xClampCmd := TRUE;                                       // 锚定稳态：夹轨保持 | anchored, keep the clamp
    xAnchorCmd := TRUE;                                      // 锚定稳态：锚定保持 | anchored, keep the anchor
E_DL_GcAnchorPhase.RELEASING:
    xClampCmd := FALSE;                                      // 解除相：夹轨撤销 | releasing, clamp retracted
    xAnchorCmd := FALSE;                                     // 解除相：锚定撤销 | releasing, anchor retracted
ELSE
    xClampCmd := FALSE;                                      // 其余相（含 FAULT）：命令强制 FALSE | all other phases force FALSE
    xAnchorCmd := FALSE;
END_CASE

// 段5b｜总使能门（R750）：未使能不得驱动夹轨/锚定机构
// 本件两路输出定义为失电即动作型（夹轨/锚定销弹簧夹紧、液压释放），FALSE 即安全侧，故使能撤销时回落 FALSE 是安全的
IF NOT xEnable THEN
    xClampCmd := FALSE;                                      // 未使能：夹轨命令回落失电安全侧 | disabled, clamp command falls back to the de-energised safe side
    xAnchorCmd := FALSE;                                     // 未使能：锚定命令回落失电安全侧 | disabled, anchor command falls back to the de-energised safe side
END_IF

// 段6｜出口汇总：非 IDLE/WIND_WARN 一律撤销行车许可；故障相已由段3预置为 FALSE
IF (ePhase <> E_DL_GcAnchorPhase.IDLE) AND (ePhase <> E_DL_GcAnchorPhase.WIND_WARN) THEN
    xPermitTravel := FALSE;                                  // 非行车相撤销许可 | non-travel phases withdraw the permit
    xPermitFullSpeed := FALSE;
END_IF
IF xWindBad THEN
    xPermitTravel := FALSE;                                  // 风速不可信：许可也撤 | untrusted wind withdraws the permit as well
    xPermitFullSpeed := FALSE;
END_IF
IF NOT xEnable THEN
    xPermitTravel := FALSE;                                  // 序列未使能：不给行车许可（R191 名实双出口）| sequence disabled, no travel permit
    xPermitFullSpeed := FALSE;
END_IF
END_FUNCTION_BLOCK
