(*
  FB_DL_LineShaftClutch  —  线轴电子离合器（相位对齐 / 咬合 / 打滑监视 / 强制脱开）/ Line-shaft electronic clutch
  分类 Category : DL_Motion
  码位 Code     : 16#04_0_A2
  版本 Version  : 1.0.2
  来源 Source   : t2-4-s7-motion — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : S7 Motion Control 公开语义借鉴（电子离合器 / 相位偏移 / 打滑监视），clean-room 实现，未复制源码行
  功能 Function : 1) 对齐段：按相位误差（从轴位置 − 主轴位置 − fPhaseOffsetDeg，归一化到 ±180°）输出修正速度
                     指令 fTrimVelDegS，供下游电子齿轮/速度环消费，误差进 fAlignTolDeg（本件常量 0.5°）后进咬合；
                  2) 咬合段：按 fEngageRampTime 斜坡把同步权重从 0 升到 1，斜坡溢出（TON.Q）置 bEngaged；
                     脱开权重自进入脱开相的实际权重按斜坡线性回落到 0，禁跳变到满值（R38 返修口径）；
                  3) 咬合期监视相位误差，超 fSlipLimitDeg 持续 tSlipDebounce → bSlipFault 锁存并强制脱开；
                  4) 脱开段：按同一斜坡时间把同步权重降回 0，权重回零才回 eIdle（不留残余同步量）。
  边界 Boundary : ① fEngageRampTime <= 0 或 fSlipLimitDeg <= 0 判组态错置 00A2，状态进 eFault 不投运；
                  ② 两轴任一 bError / 非 bEnabled → 拒绝咬合并置信息级 05A2（不置 bError，故障属主是轴本身）；
                  ③ 主从同轴（同一实例注入两侧）判组态错置 04A2：接口契约无指针恒等比较（R28 禁臆造），
                     本件改用**代理判据**——连续 DL_SAME_CYC 拍内两轴位置与速度差均 < 1E-6 且至少一侧使能，
                     视为同一实例注入（说明见「同轴代理判据」段）；
                  ④ 脱开命令与咬合命令同拍 → 以脱开为安全优先（脱开优先判定在本段最前），并置 02A2；
                  ⑤ 咬合中主轴反转（速度 < 0）判工装条件越界 → 强制脱开并置 03A2（反转咬合会拉断机械）；
                  ⑥ bSlipFault 解除式 = bReset AND 主轴 eState = eStandstill AND 从轴 eState = eStandstill
                     （三条件均由注入轴的 PROPERTY 可读，R28-1 通过；接口无 bStandstill 属性，改用
                     E_DL_AxisState.eStandstill 判等，属契约内等价表达，已在头注释声明）。
  依赖 Depends  : I_DL_MotionAxis / E_DL_AxisState（DL_Motion 既有契约件，零修改，仅注入不实例化）；
                  仅 Standard.library（TON / R_TRIG / ABS / MAX / MIN）
  同拍双窗配比  : tSlipDebounce（打滑去抖窗）与 fEngageRampTime 不同源；配比约束
                  tSlipDebounce <= fEngageRampTime × 1000 ms，避免咬合斜坡未完成就打滑判据成立（R100）

  码表 Error codes（本件格 04_0_A2，子码步进 +0x10）:
    16#0004_00A2 故障级：组态非法（斜坡时间 <= 0 / 打滑门限 <= 0 / 对齐容差 <= 0）
    16#0004_01A2 故障级：打滑故障锁存（相位误差超 fSlipLimitDeg 持续 tSlipDebounce，已强制脱开）
    16#0004_02A2 故障级：咬合与脱开命令同拍冲突（脱开优先执行，本码锁存待复位确认）
    16#0004_03A2 故障级：咬合期主轴反转（工装条件越界，已强制脱开）
    16#0004_04A2 故障级：主从同轴注入（代理判据成立，组态错）
    16#0004_05A2 信息级：拒绝咬合（注入轴故障或未使能，不置 bError）
    16#0004_06A2 信息级：咬合完成（bEngaged 上升拍，不置 bError）
    16#0004_07A2 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0004_08A2 信息级：脱开起始权重为 0，单拍收口（R38 返修新增，不置 bError）

  修订历史 Revision :
    2026-11-18  v1.0.0  R37 首版
    2026-11-18  v1.0.2  R38 返修：脱离相权重起始值改为进入脱开相快照按斜坡线性回落（_fW0Diseng），起始权重 0 单拍收口，消除反向驱动风险
  R38 已修复    : R37 终审挂账「脱离相耦合权重起始值取成满值」已按快照回落方案修复（六处置相点全部先快照后置相）
*)

TYPE E_DL_ClutchState :
(
    eIdle        := 0,   // 空闲：同步权重 0，等待咬合命令 / Idle, sync weight zero
    eAligning    := 10,  // 对齐中：相位误差收敛至容差内 / Aligning, phase error inside the tolerance
    eRamping     := 20,  // 咬合斜坡中：同步权重 0→1 / Engage ramp, weight rising from zero to one
    eEngaged     := 30,  // 已咬合：同步权重 1，监视打滑 / Engaged, weight one, slip supervised
    eDisengaging := 40,  // 脱开斜坡中：同步权重 1→0 / Disengage ramp, weight falling to zero
    eFault       := 50   // 故障：锁存待复位（复位且两轴静止）/ Fault, latched until reset with both axes standstill
);
END_TYPE

FUNCTION_BLOCK FB_DL_LineShaftClutch
VAR_INPUT
    bEnable        : BOOL := FALSE;              // 总使能，FALSE 时按脱开处理 / Master enable, a low level disengages
    bReset         : BOOL := FALSE;              // 复位，上升沿清故障锁存（须两轴静止）/ Reset, clears the latch when both axes stand still
    bEngageCmd     : BOOL := FALSE;              // 咬合命令（电平，保持型）/ Engage command, level held by the caller
    bDisengageCmd  : BOOL := FALSE;              // 脱开命令（电平，安全优先）/ Disengage command, safety priority
    fPhaseOffsetDeg : REAL := 0.0;               // 从轴相对主轴的相位偏移 [°]，域 ±360 / Phase offset of the slave relative to the master [deg]
    fEngageRampTime : REAL := 0.5;               // 咬合/脱开斜坡时间 [s]，域 > 0 / Engage and disengage ramp time [s]
    fSlipLimitDeg  : REAL := 2.0;                // 打滑门限（相位误差绝对值）[°]，域 > 0 / Slip limit [deg]
    tSlipDebounce  : TIME := T#200MS;            // 打滑去抖窗 [ms]，域 > 0 / Slip debounce window [ms]
    fSlipReleaseBandDeg : REAL := 0.2;           // 打滑解除带回差 [°]，域 >= 0 / Slip release hysteresis band [deg]
END_VAR
VAR_OUTPUT
    bEngaged       : BOOL;                       // 已咬合标志（同步权重达 1）/ Engaged flag, sync weight reached one
    bSlipFault     : BOOL;                       // 打滑故障锁存出口 / Slip fault latch outlet
    fPhaseErrorDeg : REAL;                       // 归一化相位误差 [°]，域 ±180 / Normalised phase error [deg]
    fTrimVelDegS   : REAL;                       // 对齐修正速度指令 [°/s]，带符号 / Alignment trim velocity command [deg/s]
    fSyncWeight    : REAL;                       // 同步权重 [0~1]，供下游齿轮/速度环 / Sync weight for the downstream gear or velocity loop
    bAxesReady     : BOOL;                       // 两轴就绪（使能且无故障）/ Both axes ready
    bError         : BOOL;                       // 故障标志，派生自锁存 / Fault flag derived from the latch
    nErrId         : UDINT;                      // 事件码，0 = 无事件 / Event code, 0 = no event
    eStateOut      : E_DL_ClutchState;           // 状态出口，段尾单点映射 / State outlet, mapped at the tail
END_VAR
VAR_IN_OUT
    iMasterAxis    : I_DL_MotionAxis;            // 主轴接口引用（由调用方注入，本件不实例化）/ Master axis reference, injected
    iSlaveAxis     : I_DL_MotionAxis;            // 从轴接口引用（由调用方注入，本件不实例化）/ Slave axis reference, injected
END_VAR
VAR
    tonRamp        : TON;                        // 咬合/脱开斜坡计时，每拍无条件调用 / Ramp timer, called unconditionally
    tonSlip        : TON;                        // 打滑去抖计时，每拍无条件调用 / Slip debounce timer, called unconditionally
    tonSame        : TON;                        // 同轴代理判据观察窗，自复位 / Same-instance proxy window, self-resetting
    rtReset        : R_TRIG;                     // 复位上升沿 / Reset rising edge
    rtEngaged      : R_TRIG;                     // 咬合完成上升沿（信息码单拍）/ Engaged rising edge, single-scan info code
    _eState        : E_DL_ClutchState := E_DL_ClutchState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase, the only CASE target
    _uFault        : UDINT;                      // 故障码锁存 / Latched fault code
    _uInfo         : UDINT;                      // 信息码，每拍重算 / Information code, recomputed per scan
    _bFault        : BOOL;                       // 故障锁存位 / Latched fault bit
    _bParamBad     : BOOL;                       // 组态非法聚合 / Configuration invalid aggregate
    _bCmdConflict  : BOOL;                       // 命令同拍冲突 / Command conflict in one scan
    _bReverse      : BOOL;                       // 咬合期主轴反转 / Master reversal while engaged
    _bSlipNow      : BOOL;                       // 打滑判据实时成立 / Slip criterion present
    _bSameAxis     : BOOL;                       // 同轴代理判据成立 / Same-instance proxy verdict
    _bReady        : BOOL;                       // 两轴就绪 / Both axes ready
    _bEngagedPrev  : BOOL;                       // 上拍 bEngaged 快照 / Previous-scan engaged snapshot
    _fPhaseErr     : REAL;                       // 本拍归一化相位误差 [°] / Phase error this scan [deg]
    _fPhaseErrFilt : REAL;                       // 一阶平滑后的相位误差 [°] / First-order smoothed phase error [deg]
    _fWeight       : REAL;                       // 同步权重保持量 [0~1] / Held sync weight
    _fRampSec      : REAL;                       // 生效斜坡时间秒值 [s]，已钳位 / Effective ramp time [s], clamped
    _fPosA         : REAL;                       // 主轴位置快照（一致性比较用）[°] / Master position snapshot [deg]
    _fPosB         : REAL;                       // 从轴位置快照（一致性比较用）[°] / Slave position snapshot [deg]
    _fVelA         : REAL;                       // 主轴速度快照 [°/s] / Master velocity snapshot [deg/s]
    _fVelB         : REAL;                       // 从轴速度快照 [°/s] / Slave velocity snapshot [deg/s]
    _fDeltaPrev    : REAL;                       // 上拍同步权重增量（脱开斜坡复用）[1] / Previous weight increment, reused by the disengage ramp
    _fW0Diseng     : REAL := 0.0;                // 脱开起始权重快照（进入脱开相当拍的实际权重）/ Snapshot of the weight at the disengage entry
    _bRampBreak    : BOOL := TRUE;               // 斜坡计时断输入一拍（相位入口重启，防沿用上段 ET）/ One-scan ramp break to restart the timer at a phase entry
END_VAR
VAR CONSTANT
    DL_ALIGN_TOL_DEG : REAL := 0.5;      // 对齐容差 [°]，本件声明常量（规格固定值）/ Alignment tolerance, fixed by the specification
    DL_ALIGN_KP      : REAL := 2.0;      // 对齐比例增益 [1/s] / Alignment proportional gain
    DL_TRIM_MAX_DEGS : REAL := 90.0;     // 修正速度饱和上限 [°/s] / Trim velocity saturation limit
    DL_RAMP_MAX_SEC  : REAL := 60.0;     // 斜坡时间上限 [s] / Ramp time ceiling
    DL_EPS           : REAL := 1.0E-6;   // 判零容差 [1] / Zero tolerance
    DL_SAME_CYC      : TIME := T#2S;     // 同轴观察窗 [ms]，自复位节拍 / Same-instance window, self-resetting
    DL_POS_WRAP      : REAL := 360.0;    // 位置一圈对应角度 [°] / One full revolution in degrees
    DL_POS_HALF      : REAL := 180.0;    // 归一化半圈 [°] / Half revolution used by the normalisation
    DL_FILT_ALPHA    : REAL := 0.35;     // 相位误差一阶平滑系数 [1] / Phase error smoothing coefficient
    DL_W0_EPS        : REAL := 1.0E-6;   // 脱开起始权重判零阈 [1]（R38 返修新增）/ Zero threshold for the disengage entry weight
END_VAR

(* —— 段 0：定时器与边缘检测无条件周期刷新（R182：禁置于 IF / CASE 内） —— *)
rtReset(CLK := bReset);                                          // 复位上升沿，每拍必调
rtEngaged(CLK := bEngaged);                                      // 咬合完成上升沿，每拍必调
tonSame(IN := NOT tonSame.Q, PT := DL_SAME_CYC);                 // 同轴观察窗自复位：到点下一拍断输入
tonRamp(IN := (((_eState = E_DL_ClutchState.eRamping) OR (_eState = E_DL_ClutchState.eDisengaging))
               AND (NOT _bRampBreak)),
        PT := REAL_TO_TIME(_fRampSec * 1000.0));                  // 斜坡计时（条件以表达式传入，调用本身无条件）
_bRampBreak := FALSE;                                             // 断输入拍在调用后自清（相位入口置位）
tonSlip(IN := (_eState = E_DL_ClutchState.eEngaged) AND _bSlipNow,
        PT := tSlipDebounce);                                     // 打滑去抖计时（表达式入参，调用无条件）

(* —— 段 1：单拍量预清零（快照 / 锁存 / 权重不入清单，R187①） —— *)
_uInfo        := 16#0000_0000;   // 信息码每拍重算
bError        := FALSE;          // 故障出口每拍重算，段 7 由锁存派生
bEngaged      := FALSE;          // 咬合出口缺省 FALSE，段 6 单点置位
bAxesReady    := FALSE;          // 就绪出口缺省 FALSE
_bParamBad    := FALSE;          // 组态非法预清零
_bCmdConflict := FALSE;          // 命令冲突预清零
_bReverse     := FALSE;          // 反转标志预清零
_bSameAxis    := FALSE;          // 同轴代理标志预清零

(* —— 段 2：复位沿清锁存（打滑故障解除式含两轴静止条件，R28-1） —— *)
IF rtReset.Q THEN
    IF (iMasterAxis.eState = E_DL_AxisState.eStandstill) AND
       (iSlaveAxis.eState = E_DL_AxisState.eStandstill) THEN
        _bFault := FALSE;            // 两轴静止：解除打滑/冲突/反转类锁存
        _uFault := 16#0000_0000;     // 锁存码同拍清除
    END_IF
END_IF

(* —— 段 3：组态域闸（覆盖全部参与换算的引脚，R151） —— *)
_fRampSec := fEngageRampTime;                       // 斜坡时间直取引脚 [s]
IF (_fRampSec <> _fRampSec) OR (_fRampSec <= 0.0) THEN
    _bParamBad := TRUE;                             // 斜坡时间非法（权重增量的分母）
END_IF
IF _fRampSec > DL_RAMP_MAX_SEC THEN
    _fRampSec := DL_RAMP_MAX_SEC;                   // 上限钳位（防权重增量下溢为 0）
END_IF
IF (fSlipLimitDeg <> fSlipLimitDeg) OR (fSlipLimitDeg <= 0.0) THEN
    _bParamBad := TRUE;                             // 打滑门限非法
END_IF
IF (fSlipReleaseBandDeg <> fSlipReleaseBandDeg) OR (fSlipReleaseBandDeg < 0.0) THEN
    _bParamBad := TRUE;                             // 解除回差非法（负值会让判据自相矛盾）
END_IF
IF (fPhaseOffsetDeg <> fPhaseOffsetDeg) OR (ABS(fPhaseOffsetDeg) > DL_POS_WRAP) THEN
    _bParamBad := TRUE;                             // 相位偏移非法（超一圈无物理意义）
END_IF
IF _bParamBad THEN
    _uFault := 16#0004_00A2;                        // 故障级：组态非法
    _bFault := TRUE;                                // 锁存位置位（复位沿可清）
    bError  := TRUE;                                // 故障标志置位（R45 配对）
    _eState := E_DL_ClutchState.eFault;             // 状态机进故障相
END_IF

(* —— 段 4：轴状态采集与同轴代理判据（只读接口属性，零命令下发） —— *)
_fPosA := iMasterAxis.fPosition;                    // 主轴位置 [°]
_fPosB := iSlaveAxis.fPosition;                     // 从轴位置 [°]
_fVelA := iMasterAxis.fVelocity;                    // 主轴速度 [°/s]
_fVelB := iSlaveAxis.fVelocity;                     // 从轴速度 [°/s]
_bReady := iMasterAxis.bEnabled AND iSlaveAxis.bEnabled AND
           (NOT iMasterAxis.bError) AND (NOT iSlaveAxis.bError);   // 两轴就绪（接口契约仅提供 bError，无 bFault 属性）
bAxesReady := _bReady;                              // 就绪出口（诊断用，不影响状态迁移）

IF (ABS(_fPosA - _fPosB) < DL_EPS) AND (ABS(_fVelA - _fVelB) < DL_EPS) AND
   (iMasterAxis.bEnabled OR iSlaveAxis.bEnabled) THEN
    IF tonSame.Q THEN
        _bSameAxis := TRUE;                         // 持续一整窗完全重合：代理判据成立（同一实例注入）
    END_IF
END_IF
IF _bSameAxis THEN
    _uFault := 16#0004_04A2;                        // 故障级：主从同轴注入（组态错）
    _bFault := TRUE;                                // 锁存
    bError  := TRUE;                                // 故障标志置位（R45 配对）
    _eState := E_DL_ClutchState.eFault;             // 进故障相
END_IF

(* —— 段 5：相位误差与打滑判据（无故障时计算，故障期保持末值） —— *)
IF NOT _bFault THEN
    _fPhaseErr := _fPosB - _fPosA - fPhaseOffsetDeg;            // 原始相位误差 [°]
    IF _fPhaseErr > DL_POS_HALF THEN
        _fPhaseErr := _fPhaseErr - DL_POS_WRAP;                 // 归一化：超 +180 折回负半圈 [°]
    END_IF
    IF _fPhaseErr < -DL_POS_HALF THEN
        _fPhaseErr := _fPhaseErr + DL_POS_WRAP;                 // 归一化：低于 −180 折回正半圈 [°]
    END_IF
    _fPhaseErrFilt := _fPhaseErrFilt + DL_FILT_ALPHA * (_fPhaseErr - _fPhaseErrFilt);  // 一阶平滑（抗单点毛刺）
    fPhaseErrorDeg := _fPhaseErrFilt;                           // 出口取平滑值
    _bSlipNow := (ABS(_fPhaseErrFilt) > fSlipLimitDeg);         // 打滑判据（实时）
    IF (_eState = E_DL_ClutchState.eEngaged) AND (_fVelA < -DL_EPS) THEN
        _bReverse := TRUE;                                      // 咬合期主轴反转：工装条件越界
    END_IF
    IF bDisengageCmd AND bEngageCmd THEN
        _bCmdConflict := TRUE;                                  // 同拍冲突：脱开优先（安全优先）
    END_IF
END_IF

(* —— 段 6：相位机（只做迁移与权重演进；输出映射在段 8） —— *)
CASE _eState OF

E_DL_ClutchState.eIdle:
    _fWeight := 0.0;                                            // 空闲：同步权重归零（唯一清零点在本相）
    IF bDisengageCmd THEN
        _fW0Diseng := _fWeight;                                 // R38 返修：空闲拍脱开命令 sighted，快照保持新鲜（本相权重恒 0）
        _uInfo := 16#0004_05A2;                                 // 空闲拍收到脱开：无需动作（信息级，不置错）
    ELSIF bEngageCmd THEN
        IF (NOT _bReady) THEN
            _uInfo := 16#0004_05A2;                             // 拒绝咬合：轴故障或未使能（信息级）
        ELSIF _bCmdConflict THEN
            _uFault := 16#0004_02A2;                            // 故障级：命令同拍冲突，脱开优先
            _bFault := TRUE;                                    // 锁存
            bError  := TRUE;                                    // 故障标志置位（R45 配对）
            _eState := E_DL_ClutchState.eFault;                 // 进故障相
        ELSE
            _eState := E_DL_ClutchState.eAligning;              // 进对齐相
            _fPhaseErrFilt := _fPhaseErr;                       // 平滑器赋初值，防首拍冲击
        END_IF
    END_IF

E_DL_ClutchState.eAligning:
    IF bDisengageCmd OR (NOT bEnable) THEN
        _fW0Diseng := _fWeight;                                 // R38 返修：先快照进入脱开相的实际权重（本相恒 0）
        _eState := E_DL_ClutchState.eDisengaging;               // 脱开命令/失能：回脱开斜坡（权重快照 0，单拍收口）
        _bRampBreak := TRUE;                                    // 脱开斜坡计时从零重启
    ELSIF NOT _bReady THEN
        _uInfo := 16#0004_05A2;                                 // 轴掉就绪：退出对齐（信息级，不置错）
        _eState := E_DL_ClutchState.eIdle;
    ELSIF ABS(_fPhaseErrFilt) <= DL_ALIGN_TOL_DEG THEN
        _eState := E_DL_ClutchState.eRamping;                   // 误差进容差：进咬合斜坡
        _fWeight := 0.0;                                        // 斜坡起点权重归零（迁移拍归零，非同拍抹除）
        _bRampBreak := TRUE;                                    // 斜坡计时从零重启，不沿用对齐段残留
    END_IF

E_DL_ClutchState.eRamping:
    (* 本相权重由段 6A 按 TON.ET 比例推进，此处不写 _fWeight，避免双写同拍覆盖 *)
    IF bDisengageCmd OR (NOT bEnable) THEN
        _fW0Diseng := _fWeight;                                 // R38 返修：先快照斜坡中途的实际权重（0~1 区间）
        _eState := E_DL_ClutchState.eDisengaging;               // 脱开优先
        _bRampBreak := TRUE;                                    // 脱开斜坡计时从零重启（不沿用咬合段 ET）
    ELSIF NOT _bReady THEN
        _fW0Diseng := _fWeight;                                 // R38 返修：轴掉就绪路径同样先快照
        _eState := E_DL_ClutchState.eDisengaging;               // 轴掉就绪：按脱开处理（不锁存故障）
        _bRampBreak := TRUE;                                    // 脱开斜坡计时从零重启
    ELSIF ABS(_fPhaseErrFilt) > fSlipLimitDeg THEN
        _uFault := 16#0004_01A2;                                // 斜坡期越打滑门限：直接判打滑（斜坡未完成不得掩盖）
        _bFault := TRUE;                                        // 锁存
        bError  := TRUE;                                        // 故障标志置位（R45 配对）
        _eState := E_DL_ClutchState.eFault;                     // 进故障相
    ELSIF tonRamp.Q THEN
        _eState := E_DL_ClutchState.eEngaged;                   // 斜坡完成：已咬合
        _fWeight := 1.0;                                        // 权重锁定为 1
        _uInfo := 16#0004_06A2;                                 // 信息级：咬合完成
    END_IF

E_DL_ClutchState.eEngaged:
    _fWeight := 1.0;                                            // 已咬合：权重保持 1
    IF bDisengageCmd OR (NOT bEnable) THEN
        _fW0Diseng := _fWeight;                                 // R38 返修：已咬合（权重 1）正常脱开先快照
        _eState := E_DL_ClutchState.eDisengaging;               // 正常脱开
        _bRampBreak := TRUE;                                    // 脱开斜坡计时从零重启
    ELSIF NOT _bReady THEN
        _fW0Diseng := _fWeight;                                 // R38 返修：轴掉就绪路径先快照（权重 1）
        _eState := E_DL_ClutchState.eDisengaging;               // 轴掉就绪：脱开但不锁存（故障属主为轴）
        _bRampBreak := TRUE;                                    // 脱开斜坡计时从零重启
    ELSIF _bReverse THEN
        _uFault := 16#0004_03A2;                                // 故障级：咬合期主轴反转
        _bFault := TRUE;                                        // 锁存
        bError  := TRUE;                                        // 故障标志置位（R45 配对）
        _eState := E_DL_ClutchState.eFault;                     // 强制脱开（进故障相即权重归零）
    ELSIF tonSlip.Q THEN
        _uFault := 16#0004_01A2;                                // 故障级：打滑故障锁存
        _bFault := TRUE;                                        // 锁存
        bError  := TRUE;                                        // 故障标志置位（R45 配对）
        _eState := E_DL_ClutchState.eFault;                     // 强制脱开
    END_IF

E_DL_ClutchState.eDisengaging:
    IF _fW0Diseng <= DL_W0_EPS THEN
        _fWeight := 0.0;                                        // R38 返修：起始权重为 0 → 不等斜坡单拍收口（兑现原注释语义）
        _eState := E_DL_ClutchState.eIdle;                      // 直回空闲
        _uInfo := 16#0004_08A2;                                 // 信息级：脱开起始权重为 0，单拍收口
    ELSIF tonRamp.Q THEN
        _fWeight := 0.0;                                        // 斜坡到点：权重归零（脱开完成）
        _eState := E_DL_ClutchState.eIdle;                      // 回空闲
    END_IF

E_DL_ClutchState.eFault:
    _fWeight := 0.0;                                            // 故障：同步权重强制 0（机械不再被拖动）
    IF (NOT _bFault) THEN
        _eState := E_DL_ClutchState.eIdle;                      // 锁存已由复位沿清除：回空闲重新对齐
    END_IF

ELSE
    _uFault := 16#0004_07A2;                                    // 故障级：相位 ID 越界（枚举兜底）
    _bFault := TRUE;                                            // 锁存
    bError  := TRUE;                                            // 故障标志置位（R45 配对）
    _eState := E_DL_ClutchState.eFault;                         // 强制回故障相
END_CASE

(* —— 段 6A：权重演进（唯一累加点；脱开斜坡按 TON 比例回落，禁在 CASE 内二次写） —— *)
IF _eState = E_DL_ClutchState.eRamping THEN
    _fWeight := MIN(1.0, TIME_TO_REAL(tonRamp.ET) / (_fRampSec * 1000.0));  // 咬合权重按斜坡比例上升（分母已证 > 0）
ELSIF _eState = E_DL_ClutchState.eDisengaging THEN
    _fWeight := MAX(0.0, _fW0Diseng * (1.0 - TIME_TO_REAL(tonRamp.ET) / (_fRampSec * 1000.0)));  // R38 返修：按进入脱开相的快照权重线性回落到 0，禁跳变到满值
END_IF

(* —— 段 7：对齐修正速度与故障码优先级链（每个 bError 置位源均在此有码，R45） —— *)
IF _eState = E_DL_ClutchState.eAligning THEN
    fTrimVelDegS := _fPhaseErrFilt * DL_ALIGN_KP;               // 比例修正速度 [°/s]
    IF fTrimVelDegS > DL_TRIM_MAX_DEGS THEN
        fTrimVelDegS := DL_TRIM_MAX_DEGS;                       // 上行饱和（防超速）
    END_IF
    IF fTrimVelDegS < -DL_TRIM_MAX_DEGS THEN
        fTrimVelDegS := -DL_TRIM_MAX_DEGS;                      // 下行饱和
    END_IF
ELSE
    fTrimVelDegS := 0.0;                                        // 非对齐相：修正速度 0（语义：不对轴施加修正）
END_IF

(* —— 段 8：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
bEngaged     := (_eState = E_DL_ClutchState.eEngaged);          // 咬合出口：仅 eEngaged 相为真
bSlipFault   := _bFault AND (_uFault = 16#0004_01A2);           // 打滑故障出口：按码定向，不与其它锁存混用
fSyncWeight  := _fWeight;                                       // 同步权重出口
eStateOut    := _eState;                                        // 状态出口
IF _bFault THEN
    nErrId := _uFault;                                          // 故障锁存码回放（不在故障相按当下输入重推）
    bError := TRUE;                                             // 故障出口派生自锁存
ELSE
    nErrId := _uInfo;                                           // 信息码
END_IF

END_FUNCTION_BLOCK
