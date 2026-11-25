(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SingleAxis
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 单轴运动控制 · PLCopen 状态机
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library，零厂商方言
 * 功能描述 (Function)   : 实现 I_DL_MotionAxis 的单轴运动控制功能块，内含
 *                         PLCopen 轴状态机语义（eDisabled + 六态）的
 *                         clean-room 实现。bUseVirtualKinematics=TRUE 时
 *                         位置由内部梯形段积分器生成（仿真）；FALSE 时位置
 *                         直接取上层每拍注入值（真实驱动），同一状态机适配
 *                         两种模式。
 * 设计要点 (Key notes)  : ① 指令仲裁 Absolute>Relative>Velocity，落选者丢弃
 *                           置信息级 0101；eStopping/eErrorStop 拒绝一切运动
 *                           指令（MC_Stop 语义）；
 *                         ② 软限位越限预判拦截（0202）；驱动故障 → eErrorStop
 *                           锁存（R15，仅 Reset 清）；非法状态 CASE+ELSE 兜底
 *                           （0201）；
 *                         ③ bError 派生式仅反映 eErrorStop，信息级码只进
 *                           uErrorId（R21）；
 *                         ④ 首扫/跟踪判据唯一合法范式 IF bTrack OR (NOT bInit)
 *                           （R5 公约 0.1）：中途跟踪脉冲 → 位置重同步并受控
 *                           停车（验收向量 V3）。
 * 输出实现 (Out mapping): 规格引脚表 OUT 列以接口 PROPERTY GET 形式实现并
 *                         与引脚表一一对应（接口契约映射），避免接口属性与
 *                         同名输出变量在编译器内重名冲突。
 * 开源溯源 (Origin)     : plcopen / s7-motion。仅提取 PLCopen 轴状态机公开
 *                         状态语义与 S7-1500 Motion Control 手册公开参数域；
 *                         状态机与梯形积分 100% 自有 clean-room，未调用任何
 *                         厂商轴控功能块，未参考任何厂商源码行。
 * 验收向量 (Acceptance) :
 *   V1 正常链：Enable→eStandstill→MoveAbsolute(120)→eDiscreteMotion→到位回
 *      eStandstill，fPosition 终值 120±0.01；
 *   V2 非法态兜底：内部状态破坏 → CASE+ELSE 兜底 → eErrorStop，码 0004_0201；
 *   V3 中途插入跟踪脉冲：bTrack=TRUE 一拍 → 位置重同步 fActPosition，运动转
 *      eStopping（0.1 公约必测向量）；V4~V6：仲裁丢弃 0101 / 目标超限拒绝
 *      0202 / 驱动故障锁存 0203 仅 Reset 可清。
 * 故障码表 (Error codes):
 *   16#0004_0101/0103/0104/0105【信息级】指令仲裁丢弃 / 参数对调兜底修复 /
 *   采样周期钳位 / 软限位预判降速停车；16#0004_0201/0202/0203【故障级】
 *   非法状态兜底 / 软限位越界（目标拒绝为瞬态码，实际越限为锁存）/
 *   驱动故障反馈锁存。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 05 · DL_Motion 开库）
 *============================================================================*)
(* 调用示例：fbAxis.fSoftLimitPos := 800.0（组态期赋值）；周期调用
 * fbAxis(bUseVirtualKinematics := TRUE, bDriveReady := TRUE)；真实驱动模式
 * 下层每拍写 fActPosition；HMI 取状态经属性 eState / fPosition / uErrorId。 *)
FUNCTION_BLOCK FB_DL_SingleAxis IMPLEMENTS I_DL_MotionAxis
VAR_INPUT
    fSoftLimitPos         : REAL := 1000000.0;  // 软限位上限（Soft limit positive）[mm]，默认 +1E6
    fSoftLimitNeg         : REAL := -1000000.0; // 软限位下限（Soft limit negative）[mm]，默认 -1E6
    fVelMax               : REAL := 1000.0;     // 速度物理上限（Max velocity）[mm/s]
    fAccMax               : REAL := 10000.0;    // 加速度物理上限（Max acceleration）[mm/s²]
    fDecMax               : REAL := 10000.0;    // 减速度物理上限（Max deceleration）[mm/s²]
    fPosTolerance         : REAL := 0.01;       // 到位容差（Position tolerance）[mm]
    tSampleTime           : TIME := T#100MS;    // 虚拟积分采样周期（Sample time），<T#10MS 钳位（公约 0.5）
    bDriveReady           : BOOL := FALSE;      // 驱动就绪反馈（Drive ready feedback），TRUE=可上使能
    bDriveFault           : BOOL := FALSE;      // 驱动故障反馈（Drive fault feedback），TRUE=故障
    fActPosition          : REAL := 0.0;        // 实际位置注入（Actual position injection）[mm]，真实驱动由上层每拍写入
    bUseVirtualKinematics : BOOL := TRUE;       // 虚拟运动学开关（Virtual kinematics），TRUE=无硬件仿真模式
    bTrack                : BOOL := FALSE;      // 跟踪脉冲（Tracking pulse），电平生效重同步位置（R5 公约 0.1）
END_VAR
VAR
    bInit                 : BOOL := FALSE;      // 首扫标志（First-scan flag，R19 范式配套）
    bReqEnable            : BOOL := FALSE;      // 使能电平请求（Enable level request）
    bReqReset             : BOOL := FALSE;      // 复位单发请求（Reset pulse request）
    bReqStop              : BOOL := FALSE;      // 停止单发请求（Stop pulse request）
    bReqMoveAbs           : BOOL := FALSE;      // 绝对定位单发请求（MoveAbsolute pulse request）
    bReqMoveRel           : BOOL := FALSE;      // 相对定位单发请求（MoveRelative pulse request）
    bReqMoveVel           : BOOL := FALSE;      // 速度模式单发请求（MoveVelocity pulse request）
    _eState               : E_DL_AxisState := E_DL_AxisState.eDisabled; // 内部状态机步序（Internal axis state）
    _fPosition            : REAL := 0.0;        // 内部当前位置（Internal position）[mm]
    _fVelocity            : REAL := 0.0;        // 内部当前速度（Internal velocity）[mm/s]
    _bEnabled             : BOOL := FALSE;      // 内部使能标志（Internal enabled flag）
    _bHomed               : BOOL := FALSE;      // 内部回原标志（Internal homed flag），本轮占位 FALSE
    _bError               : BOOL := FALSE;      // 内部故障派生位（Internal derived error flag）
    _uErrorId             : UDINT := 0;         // 内部末次事件码（Internal last error code）
    fTgtPosition          : REAL := 0.0;        // 定位目标位置（Target position）[mm]
    fRelDist              : REAL := 0.0;        // 相对位移暂存（Relative distance buffer）[mm]
    fTgtVelocity          : REAL := 0.0;        // 目标速度幅值（Target speed magnitude）[mm/s]，恒正
    fTgtVelSigned         : REAL := 0.0;        // 速度模式带符号目标（Signed velocity target）[mm/s]
    fTgtAccel             : REAL := 0.0;        // 生效加速度（Effective acceleration）[mm/s²]
    fTgtDecel             : REAL := 0.0;        // 生效减速度（Effective deceleration）[mm/s²]
    fVelCmd               : REAL := 0.0;        // 带符号速度指令（Signed velocity command）[mm/s]
    fLimPos               : REAL := 1000000.0;  // 生效软限位上限（Effective soft limit high）[mm]
    fLimNeg               : REAL := -1000000.0; // 生效软限位下限（Effective soft limit low）[mm]
    fVelLim               : REAL := 1000.0;     // 生效速度上限（Effective velocity limit）[mm/s]
    fAccLim               : REAL := 10000.0;    // 生效加速度上限（Effective acceleration limit）[mm/s²]
    fDecLim               : REAL := 10000.0;    // 生效减速度上限（Effective deceleration limit）[mm/s²]
    fDt                   : REAL := 0.1;        // 生效采样周期（Effective sample time）[s]
    fDelta                : REAL := 0.0;        // 剩余位移中间量（Remaining distance）[mm]
    fDir                  : REAL := 1.0;        // 运动方向系数（Direction factor）[1]，+1/-1
    fStopDist             : REAL := 0.0;        // 当前速度制动距离（Braking distance）[mm]
    fDistToLim            : REAL := 0.0;        // 沿运动方向距限位距离（Distance to limit）[mm]
    fVelMag               : REAL := 0.0;        // 速度幅值中间量（Velocity magnitude temp）[mm/s]
    bCmdAbsArb            : BOOL := FALSE;      // 仲裁胜出：绝对定位（Arbitration winner: absolute）
    bCmdRelArb            : BOOL := FALSE;      // 仲裁胜出：相对定位（Arbitration winner: relative）
    bCmdVelArb            : BOOL := FALSE;      // 仲裁胜出：速度模式（Arbitration winner: velocity）
    rtrigReqAbs           : R_TRIG;             // 绝对定位请求沿检测（Rising edge of MoveAbsolute request）
    rtrigReqRel           : R_TRIG;             // 相对定位请求沿检测（Rising edge of MoveRelative request）
    rtrigReqVel           : R_TRIG;             // 速度模式请求沿检测（Rising edge of MoveVelocity request）
    rtrigReqStop          : R_TRIG;             // 停止请求沿检测（Rising edge of Stop request）
    rtrigReqReset         : R_TRIG;             // 复位请求沿检测（Rising edge of Reset request）
END_VAR
VAR CONSTANT
    DL_AX_INF_MAX         : REAL := 1.0E30;     // 有限值判定幅值上限（Finite-value magnitude bound）[mm]
    DL_AX_EPS             : REAL := 1.0E-6;     // 浮点判零容差（Float zero tolerance）
    DL_AX_VEL_FLOOR       : REAL := 1.0E-3;     // 速度完成判据下限（Velocity completion floor）[mm/s]
    DL_AX_PARAM_FLOOR     : REAL := 1.0E-3;     // 动态参数下限兜底（Dynamic parameter floor）[mm/s 或 mm/s²]
    DL_AX_DT_MIN          : REAL := 0.010;      // 采样周期钳位下限（Sample time clamp low）[s]
    DL_AX_DT_MAX          : REAL := 1.0;        // 采样周期钳位上限（Sample time clamp high）[s]
END_VAR

METHOD Enable : BOOL
VAR_INPUT
    bOn : BOOL;                                  // 使能电平（Enable on/off），TRUE=上使能请求
END_VAR
IF bOn AND ((_eState = E_DL_AxisState.eErrorStop) OR bDriveFault OR (NOT bDriveReady)) THEN
    Enable := FALSE;                             // 故障/未就绪拒绝上使能（MC_Power 语义）
ELSE
    bReqEnable := bOn;
    Enable := TRUE;
END_IF
    END_METHOD

METHOD Reset : BOOL
VAR_INPUT
END_VAR
Reset := FALSE;
IF _eState = E_DL_AxisState.eErrorStop THEN
    bReqReset := TRUE;                           // 复位请求单发化，主体 eErrorStop 分支消费
    Reset := TRUE;
END_IF
    END_METHOD

METHOD Stop
VAR_INPUT
END_VAR
IF _bEnabled AND (_eState <> E_DL_AxisState.eErrorStop) THEN
    bReqStop := TRUE;                            // MC_Stop 语义：受控停车并拒绝新任务
END_IF
    END_METHOD

METHOD MoveAbsolute : BOOL
VAR_INPUT
    fPos : REAL;                                 // 目标绝对位置（Target absolute position）[mm]
    fVel : REAL;                                 // 运行速度（Run velocity）[mm/s]，正值
    fAcc : REAL;                                 // 加/减速度（Acceleration and deceleration）[mm/s²]，正值
END_VAR
MoveAbsolute := FALSE;
IF _eState <> E_DL_AxisState.eStandstill THEN RETURN; END_IF  // 非待机态拒绝
IF (fPos <> fPos) OR (fVel <> fVel) OR (fAcc <> fAcc) OR (ABS(fPos) > DL_AX_INF_MAX)
   OR (fVel <= DL_AX_PARAM_FLOOR) OR (fAcc <= DL_AX_PARAM_FLOOR) THEN RETURN; END_IF  // 参数非法/非有限值拒绝（0.8 公约）
IF (fPos > fLimPos) OR (fPos < fLimNeg) THEN
    _uErrorId := 16#0004_0202;                   // 软限位预判拦截：目标位超限直接拒绝
    RETURN;
END_IF
fTgtPosition := fPos;  fTgtVelocity := MIN(fVel, fVelLim);           // 目标位置 [mm] / 速度钳位 [mm/s]
fTgtAccel := MIN(fAcc, fAccLim);  fTgtDecel := MIN(fAcc, fDecLim);   // 加/减速度钳位 [mm/s²]
bReqMoveAbs := TRUE;
MoveAbsolute := TRUE;
    END_METHOD

METHOD MoveRelative : BOOL
VAR_INPUT
    fDist : REAL;                                // 相对位移（Relative distance）[mm]，带符号
    fVel  : REAL;                                // 运行速度（Run velocity）[mm/s]，正值
    fAcc  : REAL;                                // 加/减速度（Acceleration and deceleration）[mm/s²]，正值
END_VAR
MoveRelative := FALSE;
IF _eState <> E_DL_AxisState.eStandstill THEN RETURN; END_IF
IF (fDist <> fDist) OR (fVel <> fVel) OR (fAcc <> fAcc) OR (ABS(fDist) > DL_AX_INF_MAX)
   OR (fVel <= DL_AX_PARAM_FLOOR) OR (fAcc <= DL_AX_PARAM_FLOOR) THEN RETURN; END_IF  // 参数非法/非有限值拒绝（0.8 公约）
IF (_fPosition + fDist > fLimPos) OR (_fPosition + fDist < fLimNeg) THEN
    _uErrorId := 16#0004_0202;                   // 相对目标落点越限拒绝（预判）
    RETURN;
END_IF
fRelDist := fDist;  fTgtVelocity := MIN(fVel, fVelLim);              // 相对位移暂存 [mm] / 速度钳位
fTgtAccel := MIN(fAcc, fAccLim);  fTgtDecel := MIN(fAcc, fDecLim);
bReqMoveRel := TRUE;
MoveRelative := TRUE;
    END_METHOD

METHOD MoveVelocity : BOOL
VAR_INPUT
    fVel : REAL;                                 // 目标速度（Target velocity）[mm/s]，带符号
    fAcc : REAL;                                 // 加/减速度（Acceleration and deceleration）[mm/s²]，正值
END_VAR
MoveVelocity := FALSE;
IF (_eState <> E_DL_AxisState.eStandstill) AND (_eState <> E_DL_AxisState.eContinuousMotion) THEN
    RETURN;                                      // 待机/连续运动两态可进（连续运动中允许改速）
END_IF
IF (fVel <> fVel) OR (fAcc <> fAcc) OR (fAcc <= DL_AX_PARAM_FLOOR) THEN RETURN; END_IF
fTgtVelSigned := MAX(MIN(fVel, fVelLim), -fVelLim);  // 带符号速度钳位 [mm/s]
fTgtAccel := MIN(fAcc, fAccLim);  fTgtDecel := MIN(fAcc, fDecLim);
bReqMoveVel := TRUE;
MoveVelocity := TRUE;
(* 属性实现（PROPERTY GET）：与规格引脚表 OUT 列一一对应（接口契约映射）。 *)
    END_METHOD

// 段 1｜沿检测与单发化消费：R_TRIG 无条件周期刷新（R7 红线），标志本拍即清
rtrigReqAbs(CLK := bReqMoveAbs);  rtrigReqRel(CLK := bReqMoveRel);
rtrigReqVel(CLK := bReqMoveVel);  rtrigReqStop(CLK := bReqStop);
rtrigReqReset(CLK := bReqReset);
IF bReqMoveAbs THEN bReqMoveAbs := FALSE; END_IF   // 防标志滞留丢边沿
IF bReqMoveRel THEN bReqMoveRel := FALSE; END_IF
IF bReqMoveVel THEN bReqMoveVel := FALSE; END_IF
IF bReqStop THEN bReqStop := FALSE; END_IF
IF bReqReset THEN bReqReset := FALSE; END_IF

// 段 2｜R19 首扫/跟踪同步：判据唯一合法范式 IF bTrack OR (NOT bInit)
IF bTrack OR (NOT bInit) THEN
    IF (fActPosition = fActPosition) AND (ABS(fActPosition) <= DL_AX_INF_MAX) THEN _fPosition := fActPosition; END_IF // 位置重同步 [mm]
    fVelCmd := 0.0;                              // 首扫/跟踪清除速度指令 [mm/s]
    IF bInit AND ((_eState = E_DL_AxisState.eDiscreteMotion) OR (_eState = E_DL_AxisState.eContinuousMotion)) THEN
        _eState := E_DL_AxisState.eStopping;     // 中途插入跟踪脉冲 → 受控停车（验收向量 V3）
    END_IF
    bInit := TRUE;
END_IF

// 段 3｜参数防御与对调自修复（公约 0.6/0.8）：信息级码，不置 _bError（R21）
IF fSoftLimitPos < fSoftLimitNeg THEN
    fLimPos := fSoftLimitNeg;  fLimNeg := fSoftLimitPos;  _uErrorId := 16#0004_0103; // 对调修复
ELSE
    fLimPos := fSoftLimitPos;  fLimNeg := fSoftLimitNeg;
END_IF
IF (fVelMax > DL_AX_PARAM_FLOOR) AND (fVelMax < DL_AX_INF_MAX) THEN fVelLim := fVelMax;
ELSE fVelLim := 1000.0;  _uErrorId := 16#0004_0103; END_IF   // 非法速度上限兜底 [mm/s]
IF (fAccMax > DL_AX_PARAM_FLOOR) AND (fAccMax < DL_AX_INF_MAX) THEN fAccLim := fAccMax;
ELSE fAccLim := 10000.0;  _uErrorId := 16#0004_0103; END_IF  // 非法加速度上限兜底 [mm/s²]
IF (fDecMax > DL_AX_PARAM_FLOOR) AND (fDecMax < DL_AX_INF_MAX) THEN fDecLim := fDecMax;
ELSE fDecLim := 10000.0;  _uErrorId := 16#0004_0103; END_IF  // 非法减速度上限兜底 [mm/s²]
IF tSampleTime < T#10MS THEN fDt := DL_AX_DT_MIN;  _uErrorId := 16#0004_0104;   // 周期下限钳位 [s]
ELSIF tSampleTime > T#1S THEN fDt := DL_AX_DT_MAX;  _uErrorId := 16#0004_0104;  // 周期上限钳位 [s]
ELSE fDt := TIME_TO_REAL(tSampleTime) / 1000.0; END_IF                           // 合法周期换算 [s]

// 段 4｜驱动故障最高优先级锁存（R15：仅 Reset 可清）
IF bDriveFault THEN _eState := E_DL_AxisState.eErrorStop;  _uErrorId := 16#0004_0203; END_IF

// 段 5｜停止请求前置处理（MC_Stop 语义：使能运动/静止态均可进入停止）
IF rtrigReqStop.Q AND _bEnabled AND (_eState <> E_DL_AxisState.eStopping)
   AND (_eState <> E_DL_AxisState.eErrorStop) THEN
    _eState := E_DL_AxisState.eStopping;
END_IF

// 段 6｜同拍多指令仲裁：Absolute > Relative > Velocity，落选者丢弃
bCmdAbsArb := rtrigReqAbs.Q AND (_eState = E_DL_AxisState.eStandstill);
bCmdRelArb := (NOT bCmdAbsArb) AND rtrigReqRel.Q AND (_eState = E_DL_AxisState.eStandstill);
bCmdVelArb := (NOT bCmdAbsArb) AND (NOT bCmdRelArb) AND rtrigReqVel.Q
             AND ((_eState = E_DL_AxisState.eStandstill) OR (_eState = E_DL_AxisState.eContinuousMotion));
IF (rtrigReqAbs.Q AND (rtrigReqRel.Q OR rtrigReqVel.Q)) OR (rtrigReqRel.Q AND rtrigReqVel.Q) THEN
    _uErrorId := 16#0004_0101;                   // 信息级：指令丢弃提示（R21：不置故障）
END_IF

// 段 7｜PLCopen 轴状态机（ENUM + CASE + ELSE 兜底）
CASE _eState OF
    E_DL_AxisState.eDisabled:                    // 禁用态：等待上使能
        _bEnabled := FALSE;
        fVelCmd := 0.0;
        IF bReqEnable AND bDriveReady AND (NOT bDriveFault) THEN _bEnabled := TRUE;  _eState := E_DL_AxisState.eStandstill; END_IF
    E_DL_AxisState.eStandstill:                  // 待机态：接收运动指令
        IF NOT bReqEnable THEN
            _eState := E_DL_AxisState.eDisabled; // 下使能
        ELSIF bCmdAbsArb THEN _eState := E_DL_AxisState.eDiscreteMotion;
        ELSIF bCmdRelArb THEN
            fTgtPosition := _fPosition + fRelDist;         // 相对目标落位时现算 [mm]
            IF (fTgtPosition > fLimPos) OR (fTgtPosition < fLimNeg) THEN _uErrorId := 16#0004_0202; // 目标越限拒绝（瞬态码）
            ELSE _eState := E_DL_AxisState.eDiscreteMotion; END_IF
        ELSIF bCmdVelArb THEN _eState := E_DL_AxisState.eContinuousMotion;
        END_IF
    E_DL_AxisState.eDiscreteMotion:              // 离散运动：梯形速度规划（简化 S 曲线思想）
        fDelta := fTgtPosition - _fPosition;
        IF (ABS(fDelta) <= fPosTolerance) AND (ABS(fVelCmd) <= DL_AX_VEL_FLOOR) THEN
            fVelCmd := 0.0;                      // 到位：容差 + 速度收敛双判据
            _eState := E_DL_AxisState.eStandstill;
        ELSE
            fDir := 1.0;
            IF fDelta < 0.0 THEN fDir := -1.0; END_IF
            fStopDist := (fVelCmd * fVelCmd) / (2.0 * MAX(fTgtDecel, DL_AX_PARAM_FLOOR)); // 制动距离 [mm]，防除零
            IF fStopDist >= ABS(fDelta) THEN fVelMag := MAX(ABS(fVelCmd) - fTgtDecel * fDt, 0.0);  // 减速段 [mm/s]
            ELSE fVelMag := MIN(ABS(fVelCmd) + fTgtAccel * fDt, fTgtVelocity); END_IF              // 加速/恒速段 [mm/s]
            fVelCmd := fDir * fVelMag;
        END_IF
    E_DL_AxisState.eContinuousMotion:            // 连续运动：速度斜坡 + 软限位预判
        IF (_fPosition > fLimPos) OR (_fPosition < fLimNeg) THEN _uErrorId := 16#0004_0202;  // 实际位置越限：故障级
        _eState := E_DL_AxisState.eErrorStop;
        ELSE
            IF fTgtVelSigned > 0.0 THEN fDistToLim := fLimPos - _fPosition;    // 正向距限位 [mm]
            ELSIF fTgtVelSigned < 0.0 THEN fDistToLim := _fPosition - fLimNeg; // 负向距限位 [mm]
            ELSE fDistToLim := fPosTolerance; END_IF
            fStopDist := (fVelCmd * fVelCmd) / (2.0 * MAX(fTgtDecel, DL_AX_PARAM_FLOOR)); // 防除零
            IF fDistToLim <= fStopDist THEN
                fTgtVelSigned := 0.0;            // 预判进入警戒区 → 强制减速（信息级 0004_0105）
                _uErrorId := 16#0004_0105;
            END_IF
            IF fVelCmd < fTgtVelSigned THEN fVelCmd := MIN(fVelCmd + fTgtAccel * fDt, fTgtVelSigned);      // 速度斜坡收敛
            ELSIF fVelCmd > fTgtVelSigned THEN fVelCmd := MAX(fVelCmd - fTgtDecel * fDt, fTgtVelSigned); END_IF
            IF (ABS(fTgtVelSigned) <= DL_AX_EPS) AND (ABS(fVelCmd) <= DL_AX_VEL_FLOOR) THEN
                fVelCmd := 0.0;                  // 限位停车完成
                _eState := E_DL_AxisState.eStandstill;
            END_IF
        END_IF
    E_DL_AxisState.eStopping:                    // 受控停止：按生效减速度斜坡归零
        fVelMag := MAX(ABS(fVelCmd) - MAX(fTgtDecel, DL_AX_PARAM_FLOOR) * fDt, 0.0);
        IF fVelCmd < 0.0 THEN fVelCmd := -fVelMag; ELSE fVelCmd := fVelMag; END_IF
        IF fVelMag <= DL_AX_VEL_FLOOR THEN fVelCmd := 0.0;  _eState := E_DL_AxisState.eStandstill; END_IF  // 停稳
    E_DL_AxisState.eHoming:                      // 预留态：回原序列由后续轮次 FB_DL_AxisHomingSeq 承载
        IF NOT bReqEnable THEN _eState := E_DL_AxisState.eDisabled; END_IF  // 防御驻留：仅下使能退出
    E_DL_AxisState.eErrorStop:                   // 故障停机：报警锁存，仅 Reset 可退回
        fVelCmd := 0.0;
        _bEnabled := FALSE;
        IF rtrigReqReset.Q AND (NOT bDriveFault) THEN
            _uErrorId := 0;                      // 复位清码
            IF bReqEnable AND bDriveReady THEN _eState := E_DL_AxisState.eStandstill;   // 使能保持回待机
            ELSE _eState := E_DL_AxisState.eDisabled; END_IF                            // 否则回禁用
        END_IF

    ELSE
        // 非法状态兜底（故障级）
        _uErrorId := 16#0004_0201;  _eState := E_DL_AxisState.eErrorStop;
END_CASE

// 段 8｜位置/速度出口：虚拟积分与真实注入共用同一状态机
IF bUseVirtualKinematics THEN
    _fPosition := _fPosition + fVelCmd * fDt;    // 虚拟运动学：位置积分 [mm]
ELSIF (fActPosition = fActPosition) AND (ABS(fActPosition) <= DL_AX_INF_MAX) THEN
    _fPosition := fActPosition;                  // 真实驱动：上层每拍注入 [mm]
END_IF                                           // 非有限值注入 → 保持上一拍位置（0.8 公约）
_fVelocity := fVelCmd;                           // 速度出口 = 带符号速度指令 [mm/s]
_bError := (_eState = E_DL_AxisState.eErrorStop); // bError 派生式（R21：信息级码不进 bError）

(*-----------------------------------------------------------------------------
 * 方法实现（METHOD）：全部非阻塞，仅置内部请求标志，跨周期动作由主体状态机
 * 执行（OOP 方法设计准则）；接口方法共 6 个达红线临界，不得再增。
 *-----------------------------------------------------------------------------*)






PROPERTY eState : E_DL_AxisState
eState := _eState;
END_PROPERTY
PROPERTY fPosition : REAL
fPosition := _fPosition;
END_PROPERTY
PROPERTY fVelocity : REAL
fVelocity := _fVelocity;
END_PROPERTY
PROPERTY bEnabled : BOOL
bEnabled := _bEnabled;
END_PROPERTY
PROPERTY bHomed : BOOL
bHomed := _bHomed;
END_PROPERTY
PROPERTY bError : BOOL
bError := _bError;
END_PROPERTY
PROPERTY uErrorId : UDINT
uErrorId := _uErrorId;
END_PROPERTY
END_FUNCTION_BLOCK
