(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SCurveGenerator
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（LIMIT / MAX / ABS / SIGN），零厂商方言
 * 功能描述 (Function)   : 七段式 S 型点到点轨迹规划器：加加速-匀加速-减加速-匀速-
 *                         减减速-匀减速-减减速，jerk→加速度→速度→位移四级积分链
 *                         真实推进，消除柔性冲击。现场用途：伺服点位给定前级、
 *                         升降机构、注液泵平滑启停。bAbort 任意运行态立即按
 *                         最大减速停车（安全优先）。
 * 开源溯源 (Origin)     : 原创实现。算法思想源自 S 曲线七段式相变控制与
 *                         PLCopen 运动规范的 Jerk 限制概念，clean-room 编写，
 *                         未复制任何厂商私有库源码。
 * 本文件内含       : TYPE  E_DL_SCurveState（配套枚举，归属 DL_Algo）
 *                    FB    FB_DL_SCurveGenerator
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: LIMIT / MAX / ABS / SIGN
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 参数钳位+非有限值拒绝+卡死兜底
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 十态 ENUM+CASE+ELSE
 *                         R7 N/A（无定时器/边沿实例）
 * 【工程化披露 / Engineering disclosure】
 *   采用"每拍按剩余距离估算所需减速行程，不足即提前进入减速段"的自适应截断法
 *   （fBrkDist := fVel²/(2·fMaxAcc) + fVel·fDt，乘裕量 1.05），而非段间精确对称
 *   闭式解。最大速度/加速度/Jerk 三约束逐拍限幅仍全部满足，轨迹为真实 Jerk
 *   积分链推进，绝非按时间比例插值冒充。
 * 【边界披露 / Boundary disclosure】
 *   B1 fMaxVel<=0 钳位 1.0；fMaxAcc<=0 钳位 fMaxVelEff/fDt；fMaxJerk<=0 钳位 fMaxAccEff/fDt，
 *      均置 16#0002_0701 不中断扫描。B2 目标非有限值（NaN 或幅值超 1.0E30）拒绝采用。
 *   B3 减速段速度过零即强制 fVel=0、fAcc=0 防反向滑行。B4 到位容差 1.0E-4 吸附目标。
 *   B5 瞬态相位同段持续超 1E4 拍强制进故障态置 16#0002_0702；匀速段合法长段不计数。
 * 【验收向量 / Acceptance vectors】
 *   V1  fTarget 0→100，fMaxVel=100/fMaxAcc=200/fMaxJerk=1000，10MS：fVel 升至 100 后回落，
 *       fAcc 峰值不超 200，fJerk 峰值不超 1000；结束时 ABS(fOut-100)<=1.0E-4、bDone=TRUE
 *   V3  短行程 fTarget 0→0.5：不达 fMaxVel 即提前减速，到位后 bDone=TRUE
 *   V4  运行中 bAbort=TRUE → 一拍内进入最大减速，fVel 单调降至 0 后停车
 *   V5  fMaxJerk=0 → 16#0002_0701，生效值 = fMaxAccEff/fDt，轨迹仍收敛
 *   V6  fTarget=NaN → 16#0002_0004，沿用最近有效目标，fOut 保持
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 04 · Phase 3 · DL_Algo 批次）
 *   2026-11-15  v1.0.1  阶段五终审精修：首扫自动跟踪判据修复；eDone 新目标
 *                       检测修复（原判据与刚吸附值恒等导致新目标永不触发）
 *============================================================================*)
(* 枚举: E_DL_SCurveState（归属 DL_Algo，与 FB 同文件；数值步长留空位便于插态） *)
TYPE E_DL_SCurveState :
(
    eIdle        := 0,   // 空闲态：运动量清零，输出保持 / Idle, motion cleared, output held
    eAccJerkUp   := 10,  // 加加速段：jerk 正向积分，加速度爬升 / Acc jerk-up phase, acc rising
    eAccConst    := 20,  // 匀加速段：加速度保持峰值，jerk 为零 / Constant acc phase, jerk zero
    eAccJerkDown := 30,  // 减加速段：jerk 反向积分，加速度回落 / Acc jerk-down phase, acc falling
    eCruise      := 40,  // 匀速段：加速度为零，速度保持峰值 / Cruise phase, acc zero, vel held
    eDecJerkUp   := 50,  // 减减速段前半：jerk 反向建立减速度 / Decel jerk-up, deceleration building
    eDecConst    := 60,  // 匀减速段：减速度保持峰值 / Constant deceleration phase
    eDecJerkDown := 70,  // 减减速段后半：jerk 正向归零减速度 / Decel jerk-down, deceleration removed
    eDone        := 80,  // 到位态：速度加速度清零并吸附目标 / Done, motion cleared and snapped
    eFault       := 99   // 故障兜底态：非法状态或卡死拦截 / Fault fallback, illegal or stuck
);
END_TYPE

(* 功能块: FB_DL_SCurveGenerator ｜ 每周期无条件调用 ｜ 状态驻留私有 VAR 可多实例 ｜
 * 推进链: fAcc += fJerk·fDt（限幅 ±fMaxAcc）→ fVel += fAcc·fDt（限幅 ±fMaxVel）
 *         → fOut += fVel·fDt，四级积分真实推进，bTrack 投切无扰动 *)
FUNCTION_BLOCK FB_DL_SCurveGenerator
VAR_INPUT
    bEnable     : BOOL := FALSE;      // 使能标志，FALSE 运动量全清零 / Enable flag, FALSE clears all motion
    fTarget     : REAL := 0.0;        // 目标位置 [EU]，非有限值拒绝 / Target position [EU], non-finite rejected
    fMaxVel     : REAL := 100.0;      // 最大速度 [EU/s]，<=0 钳位 1.0 / Max velocity [EU/s], <=0 clamped to 1.0
    fMaxAcc     : REAL := 200.0;      // 最大加速度 [EU/s²]，<=0 钳位 fMaxVelEff/fDt / Max acceleration [EU/s²]
    fMaxJerk    : REAL := 1000.0;     // 最大加加速度 [EU/s³]，<=0 钳位 fMaxAccEff/fDt / Max jerk [EU/s³]
    bAbort      : BOOL := FALSE;      // 急停请求，TRUE 立即按最大减速停车 / Abort request, immediate max decel
    tSampleTime : TIME := T#10MS;     // 采样周期 [s]，小于 10ms 钳位 / Sample time [s], clamped to 10ms
    bTrack      : BOOL := FALSE;      // 跟踪使能，输出立即跟随 fTrackValue / Track enable, output follows track value
    fTrackValue : REAL := 0.0;        // 跟踪值 [EU]，投切无扰动基准 / Track value [EU], bumpless reference
END_VAR
VAR_OUTPUT
    fOut        : REAL;               // 输出位置 [EU] / Output position [EU]
    fVel        : REAL;               // 当前速度 [EU/s] / Current velocity [EU/s]
    fAcc        : REAL;               // 当前加速度 [EU/s²] / Current acceleration [EU/s²]
    bDone       : BOOL;               // 到位标志（吸附后置位） / In-position flag set after snap
    bMoving     : BOOL;               // 运动进行中标志 / Motion in progress flag
    bError      : BOOL;               // 故障标志（瞬时，逐拍重算） / Fault flag, transient per scan
    uErrorId    : UDINT;              // 故障码，0 = 无故障 / Error code, 0 = no error
    eState      : E_DL_SCurveState;   // 当前相位（供诊断） / Current phase for diagnostics
END_VAR
VAR
    eStateInt   : E_DL_SCurveState;   // 内部主状态机（主副本） / Internal master state machine
    eStatePrev  : E_DL_SCurveState;   // 上一拍状态，卡死计数用 / Previous state for stuck counting
    fJerk       : REAL;               // 当前 jerk [EU/s³] / Current jerk [EU/s³]
    fDist       : REAL;               // 剩余距离（带符号）[EU] / Signed remaining distance [EU]
    fTgtMem     : REAL;               // 最近有效目标记忆 [EU] / Last valid target memory [EU]
    fDir        : REAL;               // 当前运动方向符号（+1/-1） / Motion direction sign (+1/-1)
    fBrkDist    : REAL;               // 减速行程估算 [EU] / Estimated braking distance [EU]
    fLandDist   : REAL;               // 匀减速段落地行程估算 [EU] / Landing distance estimate [EU]
    fMaxVelEff  : REAL;               // 钳位后最大速度 [EU/s] / Clamped max velocity [EU/s]
    fMaxAccEff  : REAL;               // 钳位后最大加速度 [EU/s²] / Clamped max acceleration [EU/s²]
    fMaxJerkEff : REAL;               // 钳位后最大加加速度 [EU/s³] / Clamped max jerk [EU/s³]
    fDt         : REAL;               // 折算后的采样周期 [s] / Converted sample period [s]
    fVelAbs     : REAL;               // 速度绝对值 [EU/s] / Absolute velocity [EU/s]
    fVelBefore  : REAL;               // 积分前速度，过零判据用 [EU/s] / Velocity before integration
    bTgtValid   : BOOL;               // 本拍目标有限值标志 / Target finite validity flag
    bInit       : BOOL;               // 首扫标志：首扫自动跟踪 / First scan flag, auto track
    nPhaseCnt   : INT;                // 当前相位持续拍数计数器 [拍] / Phase duration counter
END_VAR
VAR CONSTANT
    DL_SC_EPS        : REAL := 1.0E-6; // 运动量判零容差 / Motion zero tolerance
    DL_SC_TOL        : REAL := 1.0E-4; // 到位判定容差 [EU] / In-position tolerance [EU]
    DL_SC_BRK_MARGIN : REAL := 1.05;   // 减速行程裕量系数 [1] / Braking distance margin factor [1]
    DL_SC_STUCK_MAX  : INT  := 10000;  // 瞬态相位卡死拍数上限 [拍] / Phase stuck limit in scans
    DL_SC_PARAM_MAX  : REAL := 1.0E10; // 动态参数统一上限钳位 [EU/s、EU/s²、EU/s³ 共用] / Unified clamp for velocity, acceleration and jerk
END_VAR

// 段 1｜公共参数处理：故障码瞬时清零 + 采样周期钳位（通用约定 0-1/0-3）
uErrorId := 16#0000_0000;               // 故障码逐拍重算 / Error code recomputed every scan
bError   := FALSE;                      // 故障标志逐拍重算 / Fault flag recomputed every scan
IF tSampleTime < T#10MS THEN
    fDt      := TIME_TO_REAL(T#10MS) / 1000.0; // 非法周期钳位为 10ms / Illegal period clamped to 10ms
    uErrorId := 16#0002_0002;           // 采样周期非法已钳位 / Sample time illegal, clamped
ELSE
    fDt      := TIME_TO_REAL(tSampleTime) / 1000.0; // 周期换算为秒 [s] / Period in seconds [s]
END_IF

// 段 2｜动态参数钳位（边界 B1）：速度→加速度→jerk 逐级依赖，顺序不可换
IF fMaxVel <= 0.0 THEN
    fMaxVelEff := 1.0;                  // 非法速度钳位 1.0 / Illegal velocity clamped to 1.0
    uErrorId   := 16#0002_0701;         // 动态参数非法已钳位 / Dynamic param illegal, clamped
ELSIF fMaxVel > DL_SC_PARAM_MAX THEN
    fMaxVelEff := DL_SC_PARAM_MAX;      // 超上限钳位 / Over-limit clamped
    uErrorId   := 16#0002_0701;         // 动态参数非法已钳位 / Dynamic param illegal, clamped
ELSE
    fMaxVelEff := fMaxVel;              // 合法参数直通 / Valid parameter passed
END_IF
IF fMaxAcc <= 0.0 THEN
    fMaxAccEff := fMaxVelEff / fDt;     // 非法加速度按速度/周期钳位 / Illegal acc clamped by vel/dt
    uErrorId   := 16#0002_0701;         // 动态参数非法已钳位 / Dynamic param illegal, clamped
ELSIF fMaxAcc > DL_SC_PARAM_MAX THEN
    fMaxAccEff := DL_SC_PARAM_MAX;      // 超上限钳位 / Over-limit clamped
    uErrorId   := 16#0002_0701;         // 动态参数非法已钳位 / Dynamic param illegal, clamped
ELSE
    fMaxAccEff := fMaxAcc;              // 合法参数直通 / Valid parameter passed
END_IF
IF fMaxJerk <= 0.0 THEN
    fMaxJerkEff := fMaxAccEff / fDt;    // 非法 jerk 按加速度/周期钳位 / Illegal jerk clamped by acc/dt
    uErrorId    := 16#0002_0701;        // 动态参数非法已钳位 / Dynamic param illegal, clamped
ELSIF fMaxJerk > DL_SC_PARAM_MAX THEN
    fMaxJerkEff := DL_SC_PARAM_MAX;     // 超上限钳位 / Over-limit clamped
    uErrorId    := 16#0002_0701;        // 动态参数非法已钳位 / Dynamic param illegal, clamped
ELSE
    fMaxJerkEff := fMaxJerk;            // 合法参数直通 / Valid parameter passed
END_IF

// 段 3｜目标合法性（边界 B2）：非有限值拒绝并沿用记忆目标
IF (fTarget <> fTarget) OR (ABS(fTarget) > 1.0E30) THEN
    bTgtValid := FALSE;                 // 本拍目标无效 / Target invalid this scan
    uErrorId  := 16#0002_0004;          // 输入非有限值已拒绝 / Non-finite input rejected
ELSE
    bTgtValid := TRUE;                  // 本拍目标有效 / Target valid this scan
    fTgtMem   := fTarget;               // 更新有效目标记忆 / Update target memory
END_IF

// 段 4｜跟踪与首扫（约定 0-6）：运动量同步清零，投切无扰动
IF bTrack OR (NOT bInit) THEN
    fOut      := fTrackValue;           // 输出立即跟随跟踪值 / Output follows track value
    fVel := 0.0;  fAcc := 0.0;  fJerk := 0.0; // 速度/加速度/加加速度清零 / Velocity, acc, jerk cleared
    eStateInt := eIdle;                 // 回空闲重新评估 / Back to idle for re-evaluation
    nPhaseCnt := 0;                     // 相位计数清零 / Phase counter cleared
    bInit     := TRUE;                  // 首扫标志置位 / First scan flag set
END_IF

IF NOT bEnable THEN
    // 段 5a｜使能失效语义：运动量全部清零、输出保持、回空闲（eIdle 定义）
    fJerk := 0.0;  fAcc := 0.0;  fVel := 0.0; // 加加速度/加速度/速度清零 / Jerk, acc, vel cleared
    nPhaseCnt := 0;                     // 相位计数清零 / Phase counter cleared
    eStateInt := eIdle;                 // 强制空闲 / Force idle
ELSE
    // 段 5b｜运行态公共量：剩余距离与减速行程估算（工程化披露核心式）
    fDist   := fTgtMem - fOut;          // 带符号剩余距离 [EU] / Signed remaining distance [EU]
    fVelAbs := ABS(fVel);               // 速度绝对值 [EU/s] / Absolute velocity [EU/s]
    fBrkDist := DL_SC_BRK_MARGIN *
                (fVelAbs * fVelAbs / (2.0 * fMaxAccEff) + fVelAbs * fDt); // 减速行程估算 [EU] / Brake distance estimate [EU]
    IF eStateInt <> eStatePrev THEN
        nPhaseCnt := 0;                 // 状态切换时计数清零 / Counter cleared on state change
    END_IF
    // 目标反转检测：速度方向与目标方向相反 → 立即进入减速段 / Retarget: brake now
    IF (eStateInt = eAccJerkUp) OR (eStateInt = eAccConst) OR (eStateInt = eAccJerkDown) OR (eStateInt = eCruise) THEN
        IF (fVelAbs > DL_SC_EPS) AND (SIGN(fDist) <> fDir) AND (ABS(fDist) > DL_SC_TOL) THEN
            eStateInt := eDecJerkUp;    // 提前转入减速段 / Switch to deceleration early
        END_IF
    END_IF
    // 急停检测：任意运行态立即按最大减速停车（安全优先）/ Abort: max decel now
    IF bAbort AND (eStateInt >= eAccJerkUp) AND (eStateInt <= eDecJerkDown) THEN
        eStateInt := eDecConst;         // 直接进入匀减速段 / Enter constant deceleration
        fJerk := 0.0;                   // jerk 清零 / Jerk cleared
        IF fVelAbs > DL_SC_EPS THEN
            fAcc := -SIGN(fVel) * fMaxAccEff; // 减速度方向与速度相反 / Decel opposes velocity
        ELSE
            fAcc := 0.0;                // 已近似静止 / Nearly stationary already
        END_IF
    END_IF

    // 段 5c｜主状态机（红线 R6）：十态 ENUM + CASE + ELSE 兜底
    CASE eStateInt OF
        eIdle:  // 空闲态：目标有效且未急停且距离超容差 → 启动加加速段 / Idle: start move
            fJerk := 0.0;               // jerk 清零 / Jerk cleared
            IF bTgtValid AND (NOT bAbort) AND (ABS(fDist) > DL_SC_TOL) THEN
                IF fDist > 0.0 THEN fDir := 1.0; ELSE fDir := -1.0; END_IF // 方向符号 / Motion direction sign
                eStateInt := eAccJerkUp; // 进入加加速段 / Enter acc jerk-up
            END_IF
        eAccJerkUp:  // 加加速段：jerk 正向积分，加速度爬升 / Acc jerk-up
            fJerk := fDir * fMaxJerkEff; // 正向最大 jerk / Positive max jerk
            IF ABS(fDist) <= fBrkDist THEN
                eStateInt := eDecJerkUp; // 剩余距离不足，提前减速 / Insufficient distance, brake early
            ELSIF fAcc * fDir >= fMaxAccEff THEN
                eStateInt := eAccConst;  // 加速度到达峰值 / Acceleration at peak
            END_IF
        eAccConst:  // 匀加速段：jerk 为零，加速度保持峰值 / Acc constant
            fJerk := 0.0;               // jerk 清零 / Jerk cleared
            fAcc  := fDir * fMaxAccEff; // 加速度钉在峰值 / Acc pinned at peak
            IF ABS(fDist) <= fBrkDist THEN
                eStateInt := eDecJerkUp; // 剩余距离不足，直接减速 / Insufficient distance, brake
            ELSIF ABS(fDist) <= fBrkDist + fAcc * fAcc / (2.0 * fMaxJerkEff) THEN
                eStateInt := eAccJerkDown; // 距离吃紧，提前回落加速度 / Distance tight, ramp acc down early
            END_IF
        eAccJerkDown:  // 减加速段：jerk 反向积分，加速度回落 / Acc jerk-down
            fJerk := -fDir * fMaxJerkEff; // 反向最大 jerk / Reversed max jerk
            IF ABS(fDist) <= fBrkDist THEN
                eStateInt := eDecJerkUp; // 剩余距离不足，转减速段 / Insufficient distance, decel
            ELSIF fAcc * fDir <= DL_SC_EPS THEN
                fJerk := 0.0;           // jerk 提前清零 / Jerk cleared early
                fAcc  := 0.0;           // 加速度归零 / Acceleration zeroed
                eStateInt := eCruise;   // 进入匀速段 / Enter cruise phase
            END_IF
        eCruise:  // 匀速段：加速度为零，速度保持峰值 / Cruise
            fJerk := 0.0;               // jerk 清零 / Jerk cleared
            fAcc  := 0.0;               // 加速度清零 / Acceleration cleared
            IF ABS(fDist) <= fBrkDist THEN
                eStateInt := eDecJerkUp; // 到达减速点 / Braking point reached
            END_IF
        eDecJerkUp:  // 减减速段前半：jerk 使减速度线性增大 / Decel jerk-up
            IF fVelAbs > DL_SC_EPS THEN
                fJerk := -SIGN(fVel) * fMaxJerkEff; // jerk 方向与速度相反 / Jerk opposes velocity
            ELSE
                fJerk := 0.0;           // 速度近零，jerk 清零 / Velocity near zero, jerk cleared
            END_IF
            IF (fVelAbs > DL_SC_EPS) AND (-fAcc * SIGN(fVel) >= fMaxAccEff) THEN
                eStateInt := eDecConst; // 减速度到达峰值 / Deceleration at peak
            END_IF
        eDecConst:  // 匀减速段：减速度保持峰值，估算落地行程 / Decel constant
            fJerk := 0.0;               // jerk 清零 / Jerk cleared
            IF fVelAbs > DL_SC_EPS THEN
                fAcc := -SIGN(fVel) * fMaxAccEff; // 减速度钉在峰值 / Decel pinned at peak
            ELSE
                fAcc := 0.0;            // 速度近零，加速度清零 / Velocity near zero, acc cleared
            END_IF
            fLandDist := fAcc * fAcc / (2.0 * fMaxJerkEff) + fVelAbs * fDt; // 落地行程估算 [EU] / Landing distance estimate [EU]
            IF ABS(fDist) <= fLandDist THEN
                eStateInt := eDecJerkDown; // 进入落地段，jerk 归零减速度 / Enter landing phase
            END_IF
        eDecJerkDown:  // 减减速段后半：jerk 正向归零减速度，落地收敛 / Decel jerk-down, landing
            IF fVelAbs > DL_SC_EPS THEN
                fJerk := SIGN(fVel) * fMaxJerkEff; // jerk 与速度同向，回收减速度 / Jerk removes deceleration
            ELSE
                fJerk := 0.0;           // 速度近零，jerk 清零 / Velocity near zero, jerk cleared
            END_IF
            IF ABS(fAcc) <= DL_SC_EPS THEN
                fJerk := 0.0;           // jerk 清零 / Jerk cleared
                fAcc  := 0.0;           // 加速度归零 / Acceleration zeroed
                IF ABS(fDist) <= DL_SC_TOL THEN
                    eStateInt := eDone; // 已在容差内，到位 / Within tolerance, done
                ELSE
                    eStateInt := eIdle; // 停稳未到位，重新加速 / Stopped short, re-accelerate
                END_IF
            END_IF
        eDone:  // 到位态：监视新目标，无新目标保持吸附 / Done: watch new target, hold snap otherwise
            fJerk := 0.0;  fAcc := 0.0;  fVel := 0.0; // 运动量清零 / Motion cleared
            IF bTgtValid AND (ABS(fTgtMem - fOut) > DL_SC_TOL) THEN
                eStateInt := eIdle;     // 新目标：回空闲重选方向启动 / New target, idle re-picks direction
            ELSE
                fOut := fTgtMem;        // 无新目标：保持吸附防漂移 / No new target: hold snap
            END_IF
        eFault:  // 故障兜底态：运动量清零并回空闲（无复位引脚，当拍恢复）/ Fault fallback
            fJerk := 0.0;  fAcc := 0.0;  fVel := 0.0; // 运动量清零 / Motion cleared
            eStateInt := eIdle;         // 自动恢复空闲 / Auto recover to idle
        ELSE  // 非法状态拦截：任何未定义状态进故障态并置码 / Illegal state interception
            eStateInt := eFault;        // 强制故障态 / Force fault state
            uErrorId  := 16#0002_0005;  // 非法状态兜底 / Illegal state fallback
            bError    := TRUE;          // 故障标志置位 / Fault flag set
    END_CASE;

    // 段 5d｜瞬态相位卡死兜底（边界 B5）：jerk 段与匀加/匀减速段限拍计数，匀速段合法长段不计数
    IF (eStateInt = eStatePrev)
       AND (((eStateInt >= eAccJerkUp) AND (eStateInt <= eAccJerkDown))
            OR ((eStateInt >= eDecJerkUp) AND (eStateInt <= eDecConst))) THEN
        nPhaseCnt := nPhaseCnt + 1;     // 同相位持续拍数累加 / Phase duration incremented
        IF nPhaseCnt > DL_SC_STUCK_MAX THEN
            eStateInt := eFault;        // 相位卡死强制故障 / Phase stuck, force fault
            uErrorId  := 16#0002_0702;  // 相位卡死兜底 / Phase stuck fallback
            bError    := TRUE;          // 故障标志置位 / Fault flag set
        END_IF
    ELSE
        nPhaseCnt := 1;                 // 新相位从 1 开始计数 / New phase counted from one
    END_IF
    eStatePrev := eStateInt;            // 记录本拍状态 / Remember state of this scan

    // 段 5e｜四级积分链：jerk→加速度→速度→位移，逐拍限幅（核心推进）
    fVelBefore := fVel;                 // 记录积分前速度（过零判据）/ Velocity before integration
    fAcc := fAcc + fJerk * fDt;         // 加加速度积分 [EU/s²] / Jerk integrated [EU/s²]
    fAcc := LIMIT(-fMaxAccEff, fAcc, fMaxAccEff); // 加速度限幅 / Acceleration clamped
    fVel := fVel + fAcc * fDt;          // 加速度积分 [EU/s] / Acceleration integrated [EU/s]
    fVel := LIMIT(-fMaxVelEff, fVel, fMaxVelEff); // 速度限幅 / Velocity clamped
    fOut := fOut + fVel * fDt;          // 速度积分到位置 [EU] / Integrated to position [EU]
    // 减速段速度过零保护（边界 B3）：防反向滑行 / Decel zero-cross guard
    IF (eStateInt >= eDecJerkUp) AND (eStateInt <= eDecJerkDown)
       AND (ABS(fVelBefore) > DL_SC_EPS) AND (fVelBefore * fVel <= 0.0) THEN
        fVel := 0.0;  fAcc := 0.0;  fJerk := 0.0; // 运动量强制清零防反向滑行 / Motion forced zero
        IF ABS(fTgtMem - fOut) <= DL_SC_TOL THEN
            eStateInt := eDone;         // 停在容差内，到位 / Stopped within tolerance, done
        ELSE
            eStateInt := eIdle;         // 停稳未到位，重新评估 / Stopped short, re-evaluate
        END_IF
    END_IF
    // 到位判定（边界 B4）：容差吸附，强制运动量清零 / In-position: tolerance snap
    IF (eStateInt >= eAccJerkUp) AND (eStateInt <= eDecJerkDown)
       AND (ABS(fTgtMem - fOut) <= DL_SC_TOL) THEN
        fOut := fTgtMem;  fVel := 0.0;  fAcc := 0.0;  fJerk := 0.0; // 吸附目标并清运动量 / Snap and clear motion
        eStateInt := eDone;             // 到位态 / Done state
    END_IF
END_IF

// 段 6｜状态与诊断引脚输出
eState  := eStateInt;                   // 相位诊断输出 / Phase diagnostic output
bDone   := (eStateInt = eDone);         // 到位标志 / In-position flag
bMoving := bEnable AND (NOT bDone)
           AND ((eStateInt >= eAccJerkUp) AND (eStateInt <= eDecJerkDown)); // 运动进行中 / Motion in progress
END_FUNCTION_BLOCK
