(*==============================================================================
 * 组件名称 (Component)  : FB_DL_StepperXyzGantry
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，零方言）
 * 功能描述 (Function)   : 三轴步进开环龙门点位运动。启动沿先做参数与软限位预检，预检
 *                         不过则一轴都不动；预检通过后按 X→Y→Z 逐轴派发相对位移，单轴
 *                         就绪即推进下一轴，每轴独立超时；三轴落定后汇总三类落点最大偏差
 *                         并给单拍完成脉冲。不做插补、不做闭环反馈、不做回零、不排队多条
 *                         目标（运行中新目标被忽略，需等待完成或中止）。
 *                         说明：接口契约 I_DL_StepperOpenLoop.MoveRelative 只接受距离与
 *                         速度，加速度由实现块组态规划，故 fAccel_mmS2 仅参与参数门禁
 *                         校验，不向下转发（规格口径已在本行登记）。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_GantryState / FUNCTION_BLOCK FB_DL_StepperXyzGantry
 * 依赖 (Depends)        : DL_Device/I_DL_StepperOpenLoop（只调用契约方法，不复制其内核）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         参考判空 + 参数域闸 + 软限位预检三重防御 ｜ 浮点比较用容差
 *                         非有限用自反比较 ｜ 枚举显式赋值 ｜ 超时定时器与沿检测无条件
 *                         周期刷新 ｜ CASE 含 ELSE 兜底
 * 错误码表 (Codes)      : 16#0004_0327 就绪（禁用/空闲/本拍无事件）
 *                         16#0004_0328 故障级 指令未被受理（参数域非法、轴索引越界、轴
 *                                    拒绝指令、状态机非法兜底）。反证句：轴拒绝与参数非法
 *                                    在输出侧同为「本拍无运动」，不可由 0329/032A 区分，
 *                                    故合并成一码并在头注释逐条列出四种来源
 *                         16#0004_0329 故障级 目标超软限位，启动沿前预检拒绝（一轴都不动）
 *                         16#0004_032A 故障级 单轴到位异常（超时或落点超公差），后续轴
 *                                    不再派单，当前轴受控停车
 *                         16#0004_032B 预留：本版不发码（下一轮区间起点，禁止回填）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 1
 *                         2026-11-17  v1.0.1  终审修复：空闲无事件相补发就绪码，消除「头注
 *                                    释声明 0327 覆盖空闲、实际输出 0」的口径不一致
 *                                    （仅输出侧，不动任何运动/判定语义）· R28 · 阶段四
 * 验收向量 (Acceptance) : 正向 X/Y 各 100 mm、Z 20 mm、50 mm/s、公差 0.01 → 逐轴推进、
 *                         偏差 ≤0.01 mm、bDone 单拍、16#0004_0327
 *                         反向 Z 目标 2500 mm（超 ±2000 软限位）→ 16#0004_0329 且三轴
 *                         位置一轴不变；速度给 0 → 16#0004_0328；单轴超时不返回就绪 →
 *                         16#0004_032A 且后续轴不再派单
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_GantryState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 龙门点位相位，每个成员在 CASE 中有且仅有一个标签。
 *----------------------------------------------------------------------------*)
TYPE E_DL_GantryState :
(
    eIdle     := 0,    // 空闲：等待启动沿与预检 / Idle, waiting for the start edge and the pre-check
    eJogging  := 10,   // 逐轴推进：每拍只对当前轴派单与判到位 / Axis stepping, one axis dispatched per scan
    eSettling := 20,   // 落定汇总：算三类落点最大偏差 / Settling, computing the maximum deviation
    eDone     := 30,   // 完成：bDone 单拍脉冲 / Done, one-scan completion pulse
    eFault    := 99    // 故障：锁存码保持，仅复位沿退出 / Fault, the latch code is held until the reset edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_StepperXyzGantry
VAR_INPUT
    bEnable      : BOOL := FALSE;         // 使能，FALSE 立即中止三轴 / Enable, FALSE aborts all three axes at once
    bStart       : BOOL := FALSE;         // 启动，上升沿启动一次（运行中被忽略） / Start, the rising edge starts one cycle and is ignored while moving
    bReset       : BOOL := FALSE;         // 复位，仅在故障态生效 / Reset, effective in the fault state only
    fTargetX_mm  : REAL := 0.0;           // X 轴目标位置 [mm]，域 ±2000 / X target position in millimetres, domain plus minus 2000
    fTargetY_mm  : REAL := 0.0;           // Y 轴目标位置 [mm]，域 ±2000 / Y target position in millimetres, domain plus minus 2000
    fTargetZ_mm  : REAL := 0.0;           // Z 轴目标位置 [mm]，域 ±2000 / Z target position in millimetres, domain plus minus 2000
    fSpeed_mmS   : REAL := 50.0;          // 运行速度 [mm/s]，域 1~500 / Run speed in millimetres per second, domain 1 to 500
    fAccel_mmS2  : REAL := 500.0;         // 加速度 [mm/s²]，域 10~5000（仅门禁校验） / Acceleration in millimetres per square second, domain 10 to 5000, gate check only
    fPosTol_mm   : REAL := 0.01;          // 落点公差 [mm]，域 0.001~1.0 / Position tolerance in millimetres, domain 0.001 to 1.0
    tAxisMax     : TIME := T#5S;          // 单轴到位超时 [ms]，域 100ms~60s / Per-axis settle timeout, domain 100 ms to 60 s
END_VAR
VAR_IN_OUT
    iAxisX       : I_DL_StepperOpenLoop;  // X 轴开环步进契约引用 [—] / X axis open-loop stepper contract reference
    iAxisY       : I_DL_StepperOpenLoop;  // Y 轴开环步进契约引用 [—] / Y axis open-loop stepper contract reference
    iAxisZ       : I_DL_StepperOpenLoop;  // Z 轴开环步进契约引用 [—] / Z axis open-loop stepper contract reference
END_VAR
VAR_OUTPUT
    fPosX_mm      : REAL;                 // X 轴实到位（指令推算）[mm] / X actual position in millimetres, open-loop derived
    fPosY_mm      : REAL;                 // Y 轴实到位（指令推算）[mm] / Y actual position in millimetres, open-loop derived
    fPosZ_mm      : REAL;                 // Z 轴实到位（指令推算）[mm] / Z actual position in millimetres, open-loop derived
    fErrMax_mm    : REAL;                 // 本次三类落点最大偏差 [mm] / Maximum deviation of the three axes in millimetres
    bDone         : BOOL;                 // 完成脉冲，单拍有效 / Completion pulse, valid for one scan
    bBusy         : BOOL;                 // 运行中 / Running
    bError        : BOOL;                 // 故障级标志，仅故障级码置位 / Fault-class flag, set on fault codes only
    eState        : E_DL_GantryState;     // 龙门相位 [—] / Gantry phase
    eErr          : UDINT;                // 错误码，段位 16#0004_xxxx / Error code in segment 16#0004_xxxx
END_VAR
VAR
    _eState       : E_DL_GantryState := E_DL_GantryState.eIdle; // 当前相位 / Current phase
    _bInit        : BOOL := FALSE;        // 首扫标志，取非判定 / First-scan flag, tested negated
    _bRefOk       : BOOL;                 // 三轴契约引用均有效标志 / All three contract references valid
    _bParamOk     : BOOL;                 // 参数门禁通过标志 / Parameter gate pass flag
    _bSoftOk      : BOOL;                 // 软限位预检通过标志 / Soft limit pre-check pass flag
    _bIssued      : BOOL;                 // 当前轴已派单标志（换轴前必清） / Current axis dispatched flag, cleared before switching axis
    _bIssueScan   : BOOL;                 // 派单当拍标志（本拍不判到位，防同拍假到位） / Dispatch scan flag, arrival is not judged in the dispatch scan
    _bSkip        : BOOL;                 // 当前轴零位移跳过标志 / Current axis skipped because the distance is zero
    _bArrived     : BOOL;                 // 当前轴就绪标志 / Current axis ready flag
    _bFaultLatch  : BOOL;                 // 故障锁存标志 / Fault latch flag
    _bAbortDone   : BOOL;                 // 失能中止已发标志（单发化） / Abort already issued flag, issued once
    _uAxisIdx     : UINT := 1;            // 当前轴索引，1=X 2=Y 3=Z / Current axis index, 1 for X, 2 for Y, 3 for Z
    _uLatchCode   : UDINT;                // 锁存码载体 / Latch code carrier
    _fAct         : REAL;                 // 当前轴回读位置 [mm] / Current axis read-back position in millimetres
    _fSpeedEff    : REAL := 50.0;         // 生效速度（下限兜底）[mm/s] / Effective speed with a lower bound guard
    _fTolEff      : REAL := 0.01;         // 生效公差（下限兜底）[mm] / Effective tolerance with a lower bound guard
    _tAxisMaxEff  : TIME := T#5S;         // 生效单轴超时（域钳制后） / Effective per-axis timeout after clamping
    _afTgt        : ARRAY[1..3] OF REAL;  // 三轴目标位置表 [mm] / Target position table of the three axes
    _afDist       : ARRAY[1..3] OF REAL;  // 三轴待走距离表 [mm] / Pending distance table of the three axes
    _afDev        : ARRAY[1..3] OF REAL;  // 三轴落点偏差表 [mm] / Deviation table of the three axes
    _rtrigStart   : R_TRIG;               // 启动上升沿 / Rising edge of the start command
    _rtrigReset   : R_TRIG;               // 复位上升沿 / Rising edge of the reset command
    _tonAxis      : TON;                  // 单轴到位超时计时 / Per-axis settle timeout timer
END_VAR
VAR CONSTANT
    DL_GTY_READY     : UDINT := 16#0004_0327;  // 就绪码 / Ready code
    DL_GTY_REJECT    : UDINT := 16#0004_0328;  // 故障级指令未受理码 / Fault code for a rejected command
    DL_GTY_LIMIT     : UDINT := 16#0004_0329;  // 故障级超软限位码 / Fault code for a soft limit violation
    DL_GTY_AXIS_BAD  : UDINT := 16#0004_032A;  // 故障级单轴到位异常码 / Fault code for an abnormal axis settle
    DL_GTY_SOFT_MM   : REAL := 2000.0;         // 软限位绝对值 [mm] / Absolute soft limit in millimetres
    DL_GTY_EPS_MM    : REAL := 0.001;          // 零位移判定容差 [mm] / Zero-distance tolerance in millimetres
    DL_GTY_SPD_LO    : REAL := 1.0;            // 速度下限 [mm/s] / Speed lower bound
    DL_GTY_SPD_HI    : REAL := 500.0;          // 速度上限 [mm/s] / Speed upper bound
    DL_GTY_ACC_LO    : REAL := 10.0;           // 加速度下限 [mm/s²] / Acceleration lower bound
    DL_GTY_ACC_HI    : REAL := 5000.0;         // 加速度上限 [mm/s²] / Acceleration upper bound
    DL_GTY_TOL_LO    : REAL := 0.001;          // 公差下限 [mm] / Tolerance lower bound
    DL_GTY_TOL_HI    : REAL := 1.0;            // 公差上限 [mm] / Tolerance upper bound
END_VAR

// 段 1｜输出与单拍标志预置（每拍重算，禁跨拍残留）
bDone := FALSE;                                     // 完成脉冲预清 / Completion pulse pre-cleared
bBusy := FALSE;                                     // 运行标志预清 / Busy flag pre-cleared
bError := FALSE;                                    // 故障标志预清 / Fault flag pre-cleared
eErr := 0;                                          // 错误码预清 / Error code pre-cleared
_bIssueScan := FALSE;                               // 派单当拍标志预清 / Dispatch scan flag pre-cleared
_bArrived := FALSE;                                 // 到位标志预清 / Arrival flag pre-cleared
_fAct := 0.0;                                       // 回读位置预清 / Read-back position pre-cleared

// 段 2｜沿检测无条件周期刷新（严禁置于分支内）
_rtrigStart(CLK := bStart);                         // 启动沿 / Start edge
_rtrigReset(CLK := bReset);                         // 复位沿 / Reset edge

// 段 3｜超时定时器无条件周期刷新（仅推进态且已派单时计时）
_tonAxis(IN := (_eState = E_DL_GantryState.eJogging) AND _bIssued, PT := _tAxisMaxEff);

// 段 4｜首扫初始化（判据取非，R19）
IF NOT _bInit THEN
    _eState := E_DL_GantryState.eIdle;              // 相位待机起步 / Phase starts idle
    _uAxisIdx := 1;                                 // 轴索引起步为 X / Axis index starts at X
    _bInit := TRUE;                                 // 首扫只做一次 / The first scan runs once
END_IF

// 段 5｜契约引用有效性（任一未注入即拒绝启动，不产生误动作）
_bRefOk := NOT ((iAxisX = 0) OR (iAxisY = 0) OR (iAxisZ = 0));

// 段 6｜参数门禁逐拍重算（非有限用自反比较，禁近似阈值）
_bParamOk := _bRefOk
         AND NOT ((fSpeed_mmS <> fSpeed_mmS) OR ((fSpeed_mmS - fSpeed_mmS) <> (fSpeed_mmS - fSpeed_mmS)))
         AND NOT ((fAccel_mmS2 <> fAccel_mmS2) OR ((fAccel_mmS2 - fAccel_mmS2) <> (fAccel_mmS2 - fAccel_mmS2)))
         AND NOT ((fPosTol_mm <> fPosTol_mm) OR ((fPosTol_mm - fPosTol_mm) <> (fPosTol_mm - fPosTol_mm)))
         AND (fSpeed_mmS >= DL_GTY_SPD_LO) AND (fSpeed_mmS <= DL_GTY_SPD_HI)
         AND (fAccel_mmS2 >= DL_GTY_ACC_LO) AND (fAccel_mmS2 <= DL_GTY_ACC_HI)
         AND (fPosTol_mm >= DL_GTY_TOL_LO) AND (fPosTol_mm <= DL_GTY_TOL_HI)
         AND (tAxisMax >= T#100MS) AND (tAxisMax <= T#60S);
_fSpeedEff := LIMIT(DL_GTY_SPD_LO, fSpeed_mmS, DL_GTY_SPD_HI);   // 生效速度钳制 [mm/s] / Effective speed after clamping
_fTolEff := LIMIT(DL_GTY_TOL_LO, fPosTol_mm, DL_GTY_TOL_HI);     // 生效公差钳制 [mm] / Effective tolerance after clamping
_tAxisMaxEff := LIMIT(T#100MS, tAxisMax, T#60S);                  // 生效超时钳制 [ms] / Effective timeout after clamping

// 段 7｜目标与软限位预检（超限位则启动沿前一拍即拒绝，一轴不动）
_afTgt[1] := fTargetX_mm;                           // X 目标入表 [mm] / X target into the table
_afTgt[2] := fTargetY_mm;                           // Y 目标入表 [mm] / Y target into the table
_afTgt[3] := fTargetZ_mm;                           // Z 目标入表 [mm] / Z target into the table
_bSoftOk := TRUE;                                   // 软限位预检假设成立 / Assume the soft limit pre-check passes
IF (fTargetX_mm <> fTargetX_mm) OR ((fTargetX_mm - fTargetX_mm) <> (fTargetX_mm - fTargetX_mm)) THEN
    _bSoftOk := FALSE;                              // X 目标非有限 / X target not finite
END_IF
IF (fTargetY_mm <> fTargetY_mm) OR ((fTargetY_mm - fTargetY_mm) <> (fTargetY_mm - fTargetY_mm)) THEN
    _bSoftOk := FALSE;                              // Y 目标非有限 / Y target not finite
END_IF
IF (fTargetZ_mm <> fTargetZ_mm) OR ((fTargetZ_mm - fTargetZ_mm) <> (fTargetZ_mm - fTargetZ_mm)) THEN
    _bSoftOk := FALSE;                              // Z 目标非有限 / Z target not finite
END_IF
IF (ABS(fTargetX_mm) > DL_GTY_SOFT_MM) THEN
    _bSoftOk := FALSE;                              // X 超软限位 / X beyond the soft limit
END_IF
IF (ABS(fTargetY_mm) > DL_GTY_SOFT_MM) THEN
    _bSoftOk := FALSE;                              // Y 超软限位 / Y beyond the soft limit
END_IF
IF (ABS(fTargetZ_mm) > DL_GTY_SOFT_MM) THEN
    _bSoftOk := FALSE;                              // Z 超软限位 / Z beyond the soft limit
END_IF

// 段 8｜实际位置回读（引用有效时每拍刷新，禁用时保持上次值）
IF _bRefOk THEN
    fPosX_mm := iAxisX.fPosition;                   // X 实到位 [mm] / X actual position
    fPosY_mm := iAxisY.fPosition;                   // Y 实到位 [mm] / Y actual position
    fPosZ_mm := iAxisZ.fPosition;                   // Z 实到位 [mm] / Z actual position
ELSE
    fPosX_mm := 0.0;                                // 引用无效：输出置 0 并随故障码上报 / Invalid reference, outputs zeroed and reported with the fault code
    fPosY_mm := 0.0;
    fPosZ_mm := 0.0;
    _bSoftOk := FALSE;                              // 引用无效一并拒绝启动 / An invalid reference also blocks the start
END_IF

// 段 9｜失能立即中止（单发停车，不清位置；状态回空闲）
IF NOT bEnable THEN
    IF NOT _bAbortDone THEN
        _bAbortDone := TRUE;                        // 中止只发一次 / The abort is issued once
        IF _bRefOk THEN
            iAxisX.Stop();                          // X 受控停车 / X controlled stop
            iAxisY.Stop();                          // Y 受控停车 / Y controlled stop
            iAxisZ.Stop();                          // Z 受控停车 / Z controlled stop
        END_IF
    END_IF
    _bIssued := FALSE;                              // 派单标志清 / Dispatch flag cleared
    _uAxisIdx := 1;                                 // 轴索引回 X / Axis index back to X
    _eState := E_DL_GantryState.eIdle;              // 相位回空闲 / Phase back to idle
    eErr := DL_GTY_READY;                           // 失能为正常停机，只回就绪码 / Disable is a normal stop, ready code only
ELSE
    _bAbortDone := FALSE;                           // 使能期清中止标志 / Abort flag cleared while enabled
END_IF

// 段 10｜龙门点位状态机（ENUM + CASE + ELSE 兜底）
CASE _eState OF

    E_DL_GantryState.eIdle:                         // 空闲：等启动沿 + 三重预检
        IF _rtrigStart.Q AND bEnable THEN
            _bFaultLatch := FALSE;                  // 新启动沿为锁存解除路径 / A new start edge is the latch release path
            _uLatchCode := 0;                       // 锁存码清 / Latch code cleared
            _bIssued := FALSE;                      // 派单标志清 / Dispatch flag cleared
            _uAxisIdx := 1;                         // 从 X 轴起步 / Start from the X axis
            _afDev[1] := 0.0;                       // 偏差表清零 [mm] / Deviation table cleared
            _afDev[2] := 0.0;
            _afDev[3] := 0.0;
            fErrMax_mm := 0.0;                      // 本次最大偏差清 [mm] / Maximum deviation cleared
            IF NOT _bRefOk THEN
                eErr := DL_GTY_REJECT;              // 故障级：契约引用未注入 / Fault, a contract reference is missing
                _uLatchCode := DL_GTY_REJECT;
                _bFaultLatch := TRUE;
                bError := TRUE;
                _eState := E_DL_GantryState.eFault;
            ELSIF NOT _bParamOk THEN
                eErr := DL_GTY_REJECT;              // 故障级：参数域非法 / Fault, parameters out of domain
                _uLatchCode := DL_GTY_REJECT;
                _bFaultLatch := TRUE;
                bError := TRUE;
                _eState := E_DL_GantryState.eFault;
            ELSIF NOT _bSoftOk THEN
                eErr := DL_GTY_LIMIT;               // 故障级：超软限位，一轴都不动 / Fault, beyond the soft limit, no axis moves
                _uLatchCode := DL_GTY_LIMIT;
                _bFaultLatch := TRUE;
                bError := TRUE;
                _eState := E_DL_GantryState.eFault;
            ELSE
                _afDist[1] := _afTgt[1] - iAxisX.fPosition;   // X 待走距离 [mm] / X pending distance
                _afDist[2] := _afTgt[2] - iAxisY.fPosition;   // Y 待走距离 [mm] / Y pending distance
                _afDist[3] := _afTgt[3] - iAxisZ.fPosition;   // Z 待走距离 [mm] / Z pending distance
                IF (ABS(_afDist[1]) <= DL_GTY_EPS_MM) AND (ABS(_afDist[2]) <= DL_GTY_EPS_MM) AND (ABS(_afDist[3]) <= DL_GTY_EPS_MM) THEN
                    _eState := E_DL_GantryState.eDone;        // 三轴零位移直通完成（零位移指令在部分平台挂死） / All distances zero, finish directly
                ELSE
                    _eState := E_DL_GantryState.eJogging;     // 进入逐轴推进 / Enter the per-axis stepping phase
                END_IF
            END_IF
        ELSE
            eErr := DL_GTY_READY;                       // 空闲无事件：回就绪码（对齐码表口径） / Idle without an event, ready code
        END_IF

    E_DL_GantryState.eJogging:                      // 逐轴推进：派单一次，判就绪或超时
        bBusy := TRUE;
        IF (_uAxisIdx < 1) OR (_uAxisIdx > 3) THEN
            eErr := DL_GTY_REJECT;                  // 故障级：轴索引越界 / Fault, axis index out of range
            _uLatchCode := DL_GTY_REJECT;
            _bFaultLatch := TRUE;
            bError := TRUE;
            bBusy := FALSE;
            _eState := E_DL_GantryState.eFault;
        ELSE
            // 派单（每轴只发一次；零位移轴跳过，不派单）
            IF NOT _bIssued THEN
                _bSkip := FALSE;                    // 跳过标志预清 / Skip flag pre-cleared
                CASE _uAxisIdx OF
                    1:
                        IF ABS(_afDist[1]) <= DL_GTY_EPS_MM THEN
                            _bSkip := TRUE;         // X 零位移跳过 / X skipped, zero distance
                        ELSE
                            _bIssued := iAxisX.MoveRelative(_afDist[1], _fSpeedEff);  // X 相对位移派发 / X relative move dispatched
                            _bIssueScan := TRUE;    // 派单当拍不判到位 / Arrival is not judged in the dispatch scan
                        END_IF
                    2:
                        IF ABS(_afDist[2]) <= DL_GTY_EPS_MM THEN
                            _bSkip := TRUE;         // Y 零位移跳过 / Y skipped, zero distance
                        ELSE
                            _bIssued := iAxisY.MoveRelative(_afDist[2], _fSpeedEff);  // Y 相对位移派发 / Y relative move dispatched
                            _bIssueScan := TRUE;    // 派单当拍不判到位 / Arrival is not judged in the dispatch scan
                        END_IF
                    3:
                        IF ABS(_afDist[3]) <= DL_GTY_EPS_MM THEN
                            _bSkip := TRUE;         // Z 零位移跳过 / Z skipped, zero distance
                        ELSE
                            _bIssued := iAxisZ.MoveRelative(_afDist[3], _fSpeedEff);  // Z 相对位移派发 / Z relative move dispatched
                            _bIssueScan := TRUE;    // 派单当拍不判到位 / Arrival is not judged in the dispatch scan
                        END_IF
                    ELSE
                        _bSkip := FALSE;            // 非 1~3 索引：交由上层索引防御拦截 / Other indices are rejected by the range guard above
                END_CASE
                IF (NOT _bIssued) AND (NOT _bSkip) THEN
                    eErr := DL_GTY_REJECT;          // 故障级：轴拒绝指令 / Fault, the axis rejected the command
                    _uLatchCode := DL_GTY_REJECT;
                    _bFaultLatch := TRUE;
                    bError := TRUE;
                    bBusy := FALSE;
                    _eState := E_DL_GantryState.eFault;
                ELSIF _bSkip THEN
                    _uAxisIdx := _uAxisIdx + 1;     // 零位移轴直接推进 / Advance past the zero-distance axis
                    IF _uAxisIdx > 3 THEN
                        _eState := E_DL_GantryState.eSettling;   // 三轴已处理完 / All three axes handled
                    END_IF
                END_IF
            END_IF

            // 到位判定（派单当拍跳过，防同拍假到位）
            IF (_eState = E_DL_GantryState.eJogging) AND _bIssued AND (NOT _bIssueScan) THEN
                CASE _uAxisIdx OF
                    1:
                        _bArrived := iAxisX.bReady;         // X 就绪（空闲且无故障） / X ready, idle and fault free
                        _fAct := iAxisX.fPosition;          // X 回读位置 [mm] / X read-back position
                    2:
                        _bArrived := iAxisY.bReady;         // Y 就绪 / Y ready
                        _fAct := iAxisY.fPosition;          // Y 回读位置 [mm] / Y read-back position
                    3:
                        _bArrived := iAxisZ.bReady;         // Z 就绪 / Z ready
                        _fAct := iAxisZ.fPosition;          // Z 回读位置 [mm] / Z read-back position
                    ELSE
                        _bArrived := FALSE;                 // 非法索引不判到位 / No arrival judgement on an illegal index
                        _fAct := 0.0;
                END_CASE
                _afDev[_uAxisIdx] := ABS(_afTgt[_uAxisIdx] - _fAct);   // 当前轴落点偏差 [mm] / Deviation of the current axis
                IF _tonAxis.Q THEN
                    _bIssued := FALSE;                  // 超时：清派单，不再发新指令 / Timeout, clear the dispatch and issue nothing further
                    CASE _uAxisIdx OF
                        1: iAxisX.Stop();               // X 受控停车 / X controlled stop
                        2: iAxisY.Stop();               // Y 受控停车 / Y controlled stop
                        3: iAxisZ.Stop();               // Z 受控停车 / Z controlled stop
                        ELSE _bArrived := FALSE;        // 非法索引无停车对象 / No stop target for an illegal index
                    END_CASE
                    eErr := DL_GTY_AXIS_BAD;            // 故障级：单轴到位超时 / Fault, per-axis settle timeout
                    _uLatchCode := DL_GTY_AXIS_BAD;
                    _bFaultLatch := TRUE;
                    bError := TRUE;
                    bBusy := FALSE;
                    _eState := E_DL_GantryState.eFault;
                ELSIF _bArrived THEN
                    IF _afDev[_uAxisIdx] > _fTolEff THEN
                        eErr := DL_GTY_AXIS_BAD;        // 故障级：落点超公差（与超时同族） / Fault, position deviation beyond tolerance
                        _uLatchCode := DL_GTY_AXIS_BAD;
                        _bFaultLatch := TRUE;
                        bError := TRUE;
                        bBusy := FALSE;
                        _eState := E_DL_GantryState.eFault;
                    ELSE
                        _bIssued := FALSE;              // 换轴前清上一轴派单标志（R27 跨轴标志） / Clear the dispatch flag before switching axis
                        _uAxisIdx := _uAxisIdx + 1;     // 推进下一轴 / Advance to the next axis
                        IF _uAxisIdx > 3 THEN
                            _eState := E_DL_GantryState.eSettling;   // 三轴落定 / All three axes settled
                        END_IF
                    END_IF
                END_IF
            END_IF
        END_IF

    E_DL_GantryState.eSettling:                     // 落定汇总：三类落点最大偏差
        bBusy := TRUE;
        IF _bRefOk THEN
            _afDev[1] := ABS(_afTgt[1] - iAxisX.fPosition);   // X 落点偏差 [mm] / X deviation
            _afDev[2] := ABS(_afTgt[2] - iAxisY.fPosition);   // Y 落点偏差 [mm] / Y deviation
            _afDev[3] := ABS(_afTgt[3] - iAxisZ.fPosition);   // Z 落点偏差 [mm] / Z deviation
        END_IF
        fErrMax_mm := _afDev[1];                    // 最大偏差初值取 X [mm] / Maximum deviation initialised with X
        IF _afDev[2] > fErrMax_mm THEN
            fErrMax_mm := _afDev[2];                // Y 更大则替换 [mm] / Replaced when Y is larger
        END_IF
        IF _afDev[3] > fErrMax_mm THEN
            fErrMax_mm := _afDev[3];                // Z 更大则替换 [mm] / Replaced when Z is larger
        END_IF
        _eState := E_DL_GantryState.eDone;          // 下一拍进入完成相 / Enter the done phase on the next scan

    E_DL_GantryState.eDone:                         // 拍 N 进入：三轴到位；本拍行为：置 bDone 单拍脉冲；
        bDone := TRUE;                              // 拍 N+1 转出并回空闲，段 1 预清即自清（R24 三律） / The pulse self-clears in the next scan
        bBusy := FALSE;
        eErr := DL_GTY_READY;                       // 正常完成只回就绪码 / A normal completion reports the ready code only
        _eState := E_DL_GantryState.eIdle;          // 相位回空闲 / Phase back to idle

    E_DL_GantryState.eFault:                        // 故障：锁存码保持，仅复位沿退出
        bBusy := FALSE;
        eErr := _uLatchCode;                        // 锁存码回放 / Replay the latch code
        bError := TRUE;                             // 故障级标志保持 / Fault flag held
        IF _rtrigReset.Q THEN
            IF _bRefOk THEN
                iAxisX.Reset();                     // X 故障复位 / X fault reset
                iAxisY.Reset();                     // Y 故障复位 / Y fault reset
                iAxisZ.Reset();                     // Z 故障复位 / Z fault reset
            END_IF
            _bFaultLatch := FALSE;                  // 锁存解除 / Latch released
            _uLatchCode := 0;                       // 锁存码清 / Latch code cleared
            _bIssued := FALSE;                      // 派单标志清 / Dispatch flag cleared
            _uAxisIdx := 1;                         // 轴索引回 X / Axis index back to X
            eErr := DL_GTY_READY;                   // 复位后回就绪码 / Ready code after the reset
            bError := FALSE;
            _eState := E_DL_GantryState.eIdle;      // 回空闲需新启动沿 / Back to idle, a new start edge is required
        END_IF

    ELSE
        // 非法状态兜底（故障级，指令未受理码承载）
        eErr := DL_GTY_REJECT;                      // 故障级：非法相位 / Fault, illegal phase
        _uLatchCode := DL_GTY_REJECT;
        _bFaultLatch := TRUE;
        bError := TRUE;
        bBusy := FALSE;
        _bIssued := FALSE;
        _eState := E_DL_GantryState.eFault;

END_CASE

eState := _eState;                                  // 相位出口镜像（只读引脚） / Phase mirrored to the output pin
END_FUNCTION_BLOCK
