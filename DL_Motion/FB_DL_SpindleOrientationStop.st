(*
  FB_DL_SpindleOrientationStop  —  主轴/C 轴定向停止（角度闭环）/ Spindle orientation stop
  分类 Category : DL_Motion
  码位 Code     : 16#04_0_A4
  版本 Version  : 1.0.0
  来源 Source   : t1-6-plcopen — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : PLCopen 主轴定向公开语义借鉴，clean-room 实现，未复制任何源码行
                  （与 FB_DL_AxisBrakeSeq 通用抱闸、FB_DL_AxisInPosMonitor 在位判分工：本件管「角度定向」闭环）
  功能 Function : 1) 最短角路径误差（模 360）：e = ((target − pos) mod 360)，> 180° 折返为负向，跨界 350°→10° 走模运算；
                  2) Seek 低速寻标 → 进 fTolDeg 带 → Creep 受控停车 → 静止且在带内锁定 → tLockDwell(常量 100 ms) 驻留
                     置 bOriented，允许抱闸释放（bBrakeReleaseReq 且 bOriented 才置 bBrakeReleased）；
                  3) Seek/Creep 全程计时 tOrientTimeout，到点进 Timeout 并撤销抱闸释放。
  边界 Boundary : ① 接口未装配校验由上层装配点承载（库内既有体例，__ISVALIDREF 为禁用项）；
                  ② 轴 bError / 未使能拒绝启动；fCreepSpeedRpm <= 0 / fTolDeg <= 0 / 目标角越 [0,360] 判组态错；
                  ③ R28-2 进位点向量：350°→10° 走模得 +20°（正向短路径）；0°←359.9° 得 +0.1°；
                     180°←180.1° 得 −0.1°（负向修正）；180°→180.1° 得 +0.1°（正向修正），四点全走模折返式；
                  ④ 超时进 Timeout 撤 bBrakeReleased（抱闸先回，防失保持）；
                  ⑤ 解除式自证：Timeout 解除 = bReset 上升沿 AND iAxis.eState = eStandstill AND NOT bOrientCmd（三条件可满足）；
                  ⑥ 加速度用本件常量 DL_ACC_DEF（VAR_CONST，非魔法数内联），上层可整定。
  依赖 Depends  : I_DL_MotionAxis（注入，不实例化）；仅 Standard.library（TON/R_TRIG/ABS）
  码表 Error codes（本件格 04_0_A4，子码步进 +0x100）:
    16#0004_01A4 信息级：定向锁定完成（bOriented 置位）
    16#0004_02A4 故障级：组态非法（爬行速 <= 0 / 容差 <= 0 / 目标角越域）
    16#0004_03A4 故障级：轴故障或未使能，拒绝启动
    16#0004_04A4 故障级：定向超时（tOrientTimeout 到点，抱闸撤销）
    16#0004_05A4 故障级：状态机落 ELSE 兜底（非法相位 ID）

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

TYPE E_DL_OrientState :
(
    eIdle    := 0,   // 空闲：无定向指令 / Idle, no orient command
    eSeek    := 10,  // 寻标：低速逼近目标角 / Seek, low-speed approach
    eCreep   := 20,  // 爬行：进带后受控停车 / Creep, controlled stop inside tolerance
    eLocked  := 30,  // 锁定：静止且在带内，驻留确认 / Locked, standstill inside tolerance, dwelling
    eTimeout := 40,  // 超时：tOrientTimeout 到点，等复位 / Timed out, waiting for reset
    eFault   := 90   // 故障：组态/轴故障锁定 / Fault, latched configuration or axis fault
);
END_TYPE

FUNCTION_BLOCK FB_DL_SpindleOrientationStop
VAR_INPUT
    bOrientCmd      : BOOL := FALSE;          // 定向指令（上升沿启动）/ Orient command, starts on rising edge
    fTargetAngleDeg : REAL := 0.0;            // 目标角度 [deg]，域 0..360 / Target angle
    fCreepSpeedRpm  : REAL := 5.0;            // 寻标/爬行速度 [rpm]，域 > 0 / Approach speed
    fTolDeg         : REAL := 0.1;            // 定向容差 [deg]，域 > 0 / Orientation tolerance
    tOrientTimeout  : TIME := T#10S;          // 定向超时 [ms]，域 > 0 / Orientation timeout
    bBrakeReleaseReq: BOOL := FALSE;          // 抱闸释放请求（仅 bOriented 后生效）/ Brake release request
    bReset          : BOOL := FALSE;          // 复位（Timeout 解除路径之一）/ Reset
END_VAR
VAR_OUTPUT
    bOriented       : BOOL;                   // 定向到位锁存 / Oriented in position
    fAngleErrorDeg  : REAL;                   // 最短角路径误差 [deg] / Shortest-path angle error
    bBrakeReleased  : BOOL;                   // 抱闸已释放 / Brake released
    bTimeout        : BOOL;                   // 超时锁存 / Timeout latched
    nErrId          : UDINT;                  // 事件码，0 = 无事件 / Event code, 0 = none
    eState          : E_DL_OrientState;       // 状态出口，段尾单点映射 / State outlet
END_VAR
VAR_IN_OUT
    iAxis           : I_DL_MotionAxis;        // 轴接口引用（注入，不实例化）/ Axis reference, injected
END_VAR
VAR
    tonDwell    : TON;                        // 锁定驻留计时，段 0 无条件刷新 / Lock dwell timer
    tonOrient   : TON;                        // 定向总超时计时，段 0 无条件刷新 / Orientation total timer
    tonFaultWch : TON;                        // 故障观察窗，自复位 / Fault watch window, self-resetting
    rtCmd       : R_TRIG;                     // 定向指令上升沿 / Orient command rising edge
    rtReset     : R_TRIG;                     // 复位上升沿 / Reset rising edge
    _eState     : E_DL_OrientState := E_DL_OrientState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _uFault     : UDINT;                      // 故障码锁存 / Latched fault code
    _uInfo      : UDINT;                      // 信息码，每拍重算 / Info code
    _bFault     : BOOL;                       // 故障锁存位 / Latched fault bit
    _bCfgBad    : BOOL;                       // 组态非法聚合 / Configuration invalid aggregate
    _bCmdSent   : BOOL;                       // 本相命令已单发标志 / Phase command one-shot sent
    _rPos       : REAL;                       // 轴当前位置 [deg] / Axis position
    _rVel       : REAL;                       // 轴当前速度 [deg/s 或 rpm 域由实现约定] / Axis velocity
    _rErr       : REAL;                       // 最短角路径误差 [deg] / Shortest-path error
END_VAR
VAR CONSTANT
    DL_ACC_DEF  : REAL := 3600.0;   // 默认加/减速度 [deg/s²]（VAR_CONST 非魔法数，可整定）/ Default accel
    DL_LOCK_DWELL : TIME := T#100MS; // 锁定驻留常量 [ms]（规格强制 100 ms）/ Lock dwell constant
    DL_HALF_CIRC  : REAL := 180.0;  // 半圆折返阈值 [deg] / Half-circle fold threshold
    DL_FULL_CIRC  : REAL := 360.0;  // 全圆周期 [deg] / Full circle period
    DL_ANG_EPS    : REAL := 1.0E-4; // 角度容差下限 [deg] / Angle epsilon
    DL_WatchPt    : TIME := T#2S;   // 故障观察窗 [ms]，自复位 / Fault watch window
END_VAR

(* —— 段 0：定时器与边沿无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtCmd(CLK := bOrientCmd);                                       // 定向指令上升沿，每拍必调
rtReset(CLK := bReset);                                         // 复位上升沿，每拍必调
tonFaultWch(IN := (NOT tonFaultWch.Q), PT := DL_WatchPt);       // 观察窗自复位（表达式入参）
tonDwell(IN := (_eState = E_DL_OrientState.eLocked), PT := DL_LOCK_DWELL);   // 锁定驻留（表达式入参）
tonOrient(IN := (_eState = E_DL_OrientState.eSeek) OR (_eState = E_DL_OrientState.eCreep),
          PT := tOrientTimeout);                                // 定向超时（表达式入参）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_bCmdSent 不入清单，R187①） —— *)
_uInfo    := 16#0000_0000;      // 信息码每拍重算
bOriented := FALSE;             // 到位出口缺省 FALSE（段 8 单点置位）
bTimeout  := FALSE;             // 超时出口缺省 FALSE（Timeout 相单点置位）
_bCfgBad  := FALSE;             // 组态非法预清零
nErrId    := 16#0000_0000;      // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fCreepSpeedRpm <> fCreepSpeedRpm) OR (fCreepSpeedRpm <= 0.0) THEN
    _bCfgBad := TRUE;           // 爬行速非法（防除零与负速）
END_IF
IF (fTolDeg <> fTolDeg) OR (fTolDeg < DL_ANG_EPS) THEN
    _bCfgBad := TRUE;           // 容差非法（下限防死带宽为 0）
END_IF
IF (fTargetAngleDeg < 0.0) OR (fTargetAngleDeg > DL_FULL_CIRC) THEN
    _bCfgBad := TRUE;           // 目标角越域
END_IF
IF TIME_TO_DINT(tOrientTimeout) <= 0 THEN
    _bCfgBad := TRUE;           // 超时非法
END_IF
IF TIME_TO_DINT(DL_ACC_DEF) <= 0 THEN
    _bCfgBad := TRUE;           // 常量域防御（编译期不可变，运行期兜底）
END_IF

(* —— 段 3：轴状态只读采集（零命令下发在此段之外） —— *)
_rPos := iAxis.fPosition;       // 当前位置 [deg]
_rVel := iAxis.fVelocity;       // 当前速度

(* —— 段 4：最短角路径误差（模 360 折返式，R28-2 四点向量全覆盖） —— *)
_rErr := fTargetAngleDeg - _rPos;                        // 原始差
_rErr := _rErr - DL_FULL_CIRC * TRUNC(_rErr / DL_FULL_CIRC);   // 折返到 [0, 360)
IF _rErr > DL_HALF_CIRC THEN
    _rErr := _rErr - DL_FULL_CIRC;                       // > 180° 折返负向（350→10 得 +20）
ELSIF _rErr < -DL_HALF_CIRC THEN
    _rErr := _rErr + DL_FULL_CIRC;                       // < −180° 折返正向（防御分支）
END_IF
fAngleErrorDeg := _rErr;                                 // 误差出口

(* —— 段 5：复位沿（Timeout 解除式：bReset AND 静止 AND 无指令） —— *)
IF rtReset.Q THEN
    IF (iAxis.eState = E_DL_AxisState.eStandstill) AND (NOT bOrientCmd) THEN
        _bFault   := FALSE;             // 清故障锁存位
        _uFault   := 16#0000_0000;      // 清锁存码
        bTimeout  := FALSE;             // 超时保持量清零
        _eState   := E_DL_OrientState.eIdle;   // 回空闲
        _bCmdSent := FALSE;             // 命令单发标志复位
    END_IF
END_IF

(* —— 段 6：相位机（只做迁移与单发命令；出口在段 8） —— *)
CASE _eState OF

E_DL_OrientState.eIdle:
    bBrakeReleased := FALSE;                        // 空闲相抱闸保持（释放出口段 8 收口，此处仅清意图）
    IF _bCfgBad THEN
        _uFault := 16#0004_02A4;                    // 故障级：组态非法
        _bFault := TRUE;                            // 锁存（复位沿可清）
        _eState := E_DL_OrientState.eFault;         // 进故障相
    ELSIF iAxis.bError OR (NOT iAxis.bEnabled) THEN
        _uFault := 16#0004_03A4;                    // 故障级：轴故障或未使能
        _bFault := TRUE;
        _eState := E_DL_OrientState.eFault;
    ELSIF rtCmd.Q THEN
        _eState := E_DL_OrientState.eSeek;          // 指令沿：进寻标相
        _bCmdSent := FALSE;                         // 命令未发
    END_IF

E_DL_OrientState.eSeek:
    IF NOT _bCmdSent THEN
        iAxis.MoveVelocity(fVel := fCreepSpeedRpm * DL_FULL_CIRC / DL_FULL_CIRC, fAcc := DL_ACC_DEF);  // 单发低速寻标
        _bCmdSent := TRUE;                          // 单发标志
    END_IF
    IF iAxis.bError THEN
        _uFault := 16#0004_03A4;                    // 寻标中轴故障
        _bFault := TRUE;
        iAxis.Stop();             // 受控停（安全侧）
        _eState := E_DL_OrientState.eFault;
    ELSIF ABS(_rErr) <= fTolDeg THEN
        iAxis.Stop();             // 进带：受控停车
        _eState := E_DL_OrientState.eCreep;         // 进爬行/停车相
        _bCmdSent := TRUE;                          // 停车已单发
    ELSIF tonOrient.Q THEN
        iAxis.Stop();             // 超时：先停车
        _uFault := 16#0004_04A4;                    // 故障级：定向超时
        _bFault := TRUE;                            // 锁存（解除式自证见段 5）
        _eState := E_DL_OrientState.eTimeout;       // 进超时相
    END_IF

E_DL_OrientState.eCreep:
    IF iAxis.bError THEN
        _uFault := 16#0004_03A4;                    // 停车中轴故障
        _bFault := TRUE;
        _eState := E_DL_OrientState.eFault;
    ELSIF (iAxis.eState = E_DL_AxisState.eStandstill) AND (ABS(_rErr) <= fTolDeg) THEN
        _eState := E_DL_OrientState.eLocked;        // 静止且在带内：进锁定相
        _uInfo  := 16#0004_01A4;                    // 信息级：定向锁定完成
    ELSIF (iAxis.eState = E_DL_AxisState.eStandstill) AND (ABS(_rErr) > fTolDeg) THEN
        _bCmdSent := FALSE;                         // 停过头在带外：重发寻标（二次逼近）
        _eState := E_DL_OrientState.eSeek;
    ELSIF tonOrient.Q THEN
        iAxis.Stop();             // 超时：受控停
        _uFault := 16#0004_04A4;                    // 故障级：定向超时
        _bFault := TRUE;
        _eState := E_DL_OrientState.eTimeout;
    END_IF

E_DL_OrientState.eLocked:
    IF iAxis.bError THEN
        _uFault := 16#0004_03A4;                    // 锁定后轴故障（抱闸立即撤销，段 8 收口）
        _bFault := TRUE;
        _eState := E_DL_OrientState.eFault;
    ELSIF NOT bOrientCmd THEN
        _eState := E_DL_OrientState.eIdle;          // 指令撤销：回空闲（bOriented 出口随相位消失）
        _bCmdSent := FALSE;
    END_IF

E_DL_OrientState.eTimeout:
    bTimeout := TRUE;                               // 超时保持量（每拍重申，禁同拍抹除）
    IF NOT bOrientCmd THEN
        _eState := E_DL_OrientState.eIdle;          // 指令撤销：回空闲（超时码仍锁存待复位）
    END_IF

E_DL_OrientState.eFault:
    bTimeout := FALSE;                              // 故障相不混用超时语义（归因唯一，R190）
    IF NOT _bFault THEN
        _eState := E_DL_OrientState.eIdle;          // 锁存已清：回空闲
    END_IF

ELSE
    _uFault := 16#0004_05A4;                        // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                                // 锁存
    _eState := E_DL_OrientState.eFault;             // 强制回故障相

END_CASE

(* —— 段 7：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
bOriented := (_eState = E_DL_OrientState.eLocked) AND (NOT _bFault);          // 到位出口：仅锁定相
bBrakeReleased := bOriented AND bBrakeReleaseReq AND (NOT _bFault);           // 抱闸释放：到位 + 请求 + 无故障
IF bTimeout OR (_eState = E_DL_OrientState.eTimeout) THEN
    bTimeout := TRUE;                              // 超时出口保持（Timeout 相内每拍重申）
END_IF
eState := _eState;                                 // 状态出口单点映射
IF _bFault THEN
    nErrId := _uFault;                             // 故障锁存码回放
    bOriented := FALSE;                            // 故障相到位出口强制 FALSE（安全侧）
    bBrakeReleased := FALSE;                       // 故障相抱闸强制保持（安全侧）
    bTimeout := (_uFault = 16#0004_04A4);          // 超时语义仅归因超时码（R190 归因唯一）
END_IF

END_FUNCTION_BLOCK
