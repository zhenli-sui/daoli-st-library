(* ============================================================
   DL_Motion / FB_DL_RtcpFiveAxisSeq ｜ v1.0.0 ｜ 2026-11-25
   功能：五轴 RTCP 补偿相序机：eIdle → ePivotCal（摆角稳定窗 200ms + 超时狗 5s）
         → eEnable（摆角软限位校验）→ eInterp（插补补偿）→ eExit（补偿斜坡回 0）→ eIdle；
         软限位越界/补偿越限/非有限/标定超时/非法相位一律 eFault 锁存并回放码。
   边界：① 故障唯一解除 = bReset 上升沿（R152 可达）；② bReset 作用域三项：
         清锁存、迁 eIdle、清累计量与快照（不动 _bInit）；③ bEnable=FALSE 语义 =
         降级为安全值 + 置标志（经 eExit 退补到 0，非冻结保持，R191/N2）；
         ④ 同拍双窗配比：tCalTmo(5s) > tCalSettle(200ms)（R100）；
         ⑤ 出口补偿量非有限即写 0，禁 NaN 直穿 REAL（N1）。
   依赖：仅 IEC 61131-3（TON/R_TRIG/SIN/COS/ABS/MIN/MAX/LIMIT）
   溯源：DLF-A-RTCP（内部原创线）｜枚举归属：E_DL_RtcpSeqPhase 唯一属主（R264）
   码位：零 16# 范式；uErrId 0 无 / 1 组态 / 2 非有限 / 3 软限位 / 4 补偿越限 /
         5 标定超时 / 6 非法相位（码 1 含 nAxisMode ≠ 0 即工件坐标模式未实现）
   ============================================================ *)
TYPE E_DL_RtcpSeqPhase :
(
    eIdle     := 0,    // 待机：补偿关闭 / Idle with compensation off
    ePivotCal := 10,   // 枢轴标定：稳定窗 + 超时狗 / Pivot calibration window
    eEnable   := 20,   // 使能确认：软限位校验 / Enable confirmation with soft limits
    eInterp   := 30,   // 插补补偿：逐拍输出并监视越限 / Compensation output with overrun watch
    eExit     := 40,   // 退出：补偿斜坡回 0 / Exit ramp back to zero
    eFault    := 90    // 故障：锁存至复位沿 / Fault latched until the reset edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_RtcpFiveAxisSeq
VAR_INPUT
    bEnable     : BOOL;   // 补偿使能电平，FALSE 触发退补 [-] / Compensation enable level
    bReset      : BOOL;   // 故障复位，上升沿解除锁存 [-] / Fault reset on the rising edge
    fPivotLenMm : REAL;   // 枢轴长度 [mm] / Pivot length in millimeters
    fTiltADeg   : REAL;   // 摆动轴 A 角反馈 [deg] / Swivel axis A angle feedback
    fTiltBDeg   : REAL;   // 摆动轴 B 角反馈 [deg] / Swivel axis B angle feedback
    nAxisMode   : DINT;   // 五轴模式 0=刀尖跟随（本件已实现）/ 1=工件坐标（未实现，判组态非法）[-] / Five axis mode selector
END_VAR
VAR_OUTPUT
    bCompActive : BOOL;   // 补偿生效（仅插补相）[-] / Compensation active in the interpolation phase
    bError      : BOOL;   // 故障锁存标志 [-] / Latched fault flag
    fCompZmm    : REAL;   // Z 向补偿量本拍生效值 [mm] / Z compensation amount in effect
    uErrId      : UDINT;  // 事件码锁存值，0 = 无事件 [-] / Latched event code
    nPhase      : INT;    // 相位号镜像 0/10/20/30/40/90 [-] / Phase number mirror
END_VAR
VAR
    rtReset      : R_TRIG;                                        // 复位沿实例，段 0 无条件刷新 / Reset edge
    tonCalSettle : TON;                                           // 标定稳定窗，段 0 无条件刷新 / Settle window
    tonCalTmo    : TON;                                           // 标定超时狗，段 0 无条件刷新 / Timeout watchdog
    _eState      : E_DL_RtcpSeqPhase := E_DL_RtcpSeqPhase.eIdle;  // 内部相位 / Internal phase
    _bInit       : BOOL := FALSE;                                 // 首扫初始化已执行 [-] / First scan init done
    _bFault      : BOOL := FALSE;                                 // 故障锁存位 [-] / Latched fault bit
    _uFault      : UDINT := 0;                                    // 故障码锁存 [-] / Latched fault code
    _bCfgBad     : BOOL;                                          // 组态非法当拍量 [-] / Illegal configuration flag
    _bNonFin     : BOOL;                                          // 入参非有限当拍量 [-] / Non-finite argument flag
    _bAngSeen    : BOOL := FALSE;                                 // 摆角前值已建立 [-] / Angle snapshot established
    _bAngStable  : BOOL := FALSE;                                 // 本拍摆角稳定 [-] / Angles stable this scan
    _fAPrev      : REAL := 0.0;                                   // 上拍 A 角快照 [deg] / Previous A snapshot
    _fBPrev      : REAL := 0.0;                                   // 上拍 B 角快照 [deg] / Previous B snapshot
    _fCompZ      : LREAL := 0.0;                                  // Z 向补偿量内部值 [mm] / Internal Z compensation
END_VAR
VAR CONSTANT
    DL_RTCP_SOFTLIM : LREAL := 110.0;                // 摆角软限位 [deg] / Soft limit of the swivel angle
    DL_RTCP_COMPLIM : LREAL := 50.0;                 // 补偿量硬限 [mm] / Hard limit of the compensation
    DL_RTCP_RAMP    : LREAL := 5.0;                  // 退补斜坡每拍步长 [mm/拍] / Exit ramp step
    DL_RTCP_STABLEPS : REAL := 0.05;                 // 摆角稳定判据带 [deg] / Angle stability tolerance
    DL_RTCP_T_SETTLE : TIME := T#200MS;              // 稳定窗时长 [ms] / Settle window duration
    DL_RTCP_T_CAL    : TIME := T#5S;                 // 标定相超时 [ms] / Calibration timeout
    DL_RTCP_C_CFG    : UDINT := 1;                   // 码 1：组态非法 / Code one, illegal configuration
    DL_RTCP_C_FIN    : UDINT := 2;                   // 码 2：入参非有限 / Code two, non-finite argument
    DL_RTCP_C_SOFT   : UDINT := 3;                   // 码 3：超软限位 / Code three, soft limit violated
    DL_RTCP_C_COMP   : UDINT := 4;                   // 码 4：补偿越限 / Code four, compensation overrun
    DL_RTCP_C_TMO    : UDINT := 5;                   // 码 5：标定超时 / Code five, calibration timeout
    DL_RTCP_C_ILL    : UDINT := 6;                   // 码 6：非法相位 / Code six, illegal phase fallback
END_VAR

(* 方法 CalcPivotComp：求 Z 向补偿量并做软限位判定；返回 TRUE = 可信。
   方法内不驻留跨拍状态，入参全经引脚传入（R3 方法设计准则）。 *)
METHOD CalcPivotComp : BOOL
VAR_INPUT
    fLenMm : REAL;   // 枢轴长度 [mm] / Pivot length
    fADeg  : REAL;   // 摆动轴 A 角 [deg] / Swivel axis A angle
    fBDeg  : REAL;   // 摆动轴 B 角 [deg] / Swivel axis B angle
END_VAR
VAR_IN_OUT
    fZmm   : LREAL;  // 计算所得 Z 补偿量（本方法写回）[mm] / Computed Z compensation written back
END_VAR
VAR
    _fAr : LREAL;  // A 角弧度 [rad] / Angle A in radians
    _fBr : LREAL;  // B 角弧度 [rad] / Angle B in radians
    _fCz : LREAL;  // Z 投影 = L×(cosA·cosB − 1) [mm] / Z projection of the pivot offset
END_VAR
VAR CONSTANT
    DL_M_PI     : LREAL := 3.14159265358979324;  // 圆周率（全精度）[-] / Pi at full precision
    DL_M_SOFT   : LREAL := 110.0;                // 摆角软限位 [deg] / Soft limit of the swivel angle
END_VAR

CalcPivotComp := FALSE;  fZmm := 0.0;            // 出口先落安全值
IF (fADeg <> fADeg) OR (fBDeg <> fBDeg) OR (fLenMm <> fLenMm)
   OR ((fLenMm - fLenMm) <> (fLenMm - fLenMm)) THEN
    RETURN;
END_IF
IF fLenMm <= 0.0 THEN RETURN; END_IF             // 组态域闸
IF (ABS(fADeg) > LREAL_TO_REAL(DL_M_SOFT)) OR (ABS(fBDeg) > LREAL_TO_REAL(DL_M_SOFT)) THEN
    RETURN;                                      // 软限位用原始角度判定（禁先夹后判）
END_IF
_fAr := REAL_TO_LREAL(fADeg) * DL_M_PI / 180.0;
_fBr := REAL_TO_LREAL(fBDeg) * DL_M_PI / 180.0;
_fCz := REAL_TO_LREAL(fLenMm) * (COS(_fAr) * COS(_fBr) - 1.0);
IF (_fCz <> _fCz) OR ((_fCz - _fCz) <> (_fCz - _fCz)) THEN
    fZmm := 0.0;  RETURN;
END_IF
fZmm := _fCz;                                     // 原值回传，越限判定归主体（保码 4 可达）
CalcPivotComp := TRUE;
END_METHOD

(* 段 0：沿实例与定时器无条件每拍刷新（R7） *)
rtReset (CLK := bReset);
tonCalSettle (IN := (_eState = E_DL_RtcpSeqPhase.ePivotCal) AND _bAngStable AND (NOT _bFault),
              PT := DL_RTCP_T_SETTLE);
tonCalTmo (IN := (_eState = E_DL_RtcpSeqPhase.ePivotCal) AND (NOT _bFault), PT := DL_RTCP_T_CAL);

(* 段 1：单拍量预清零（锁存量与快照不入清单，R107） *)
_bCfgBad := FALSE;  _bNonFin := FALSE;  _bAngStable := FALSE;

(* 段 2：首扫与复位沿同款初始化（作用域：清锁存/迁相位/清累计与快照，R310/R311） *)
IF (NOT _bInit) OR rtReset.Q THEN
    _bInit := TRUE;  _bFault := FALSE;  _uFault := 0;
    _fCompZ := 0.0;  _fAPrev := 0.0;  _fBPrev := 0.0;  _bAngSeen := FALSE;
    _eState := E_DL_RtcpSeqPhase.eIdle;
END_IF

(* 段 3：组态闸与非有限闸（覆盖全部参与换算的引脚，R272）
   模式引脚参与判据：本件换算 = A+B 双摆动 Z 投影（模式 0 刀尖跟随）；模式 1 工件坐标
   的换算分支本轮未实现，判组态非法并置码 1——禁「入闸不换算」的死引脚与两模式同形输出
   （R190 归因唯一，禁静默给出位形相同的补偿量） *)
IF (fPivotLenMm <= 0.0) OR (nAxisMode <> 0) THEN
    _bCfgBad := TRUE;
END_IF
IF (fPivotLenMm <> fPivotLenMm) OR (fTiltADeg <> fTiltADeg) OR (fTiltBDeg <> fTiltBDeg)
   OR ((fPivotLenMm - fPivotLenMm) <> (fPivotLenMm - fPivotLenMm))
   OR ((fTiltADeg - fTiltADeg) <> (fTiltADeg - fTiltADeg))
   OR ((fTiltBDeg - fTiltBDeg) <> (fTiltBDeg - fTiltBDeg)) THEN
    _bNonFin := TRUE;
END_IF

(* 段 4：摆角稳定判据与快照（快照与锁存同寿命，复位沿清零） *)
IF _bAngSeen AND (NOT _bNonFin)
   AND (ABS(fTiltADeg - _fAPrev) <= DL_RTCP_STABLEPS)
   AND (ABS(fTiltBDeg - _fBPrev) <= DL_RTCP_STABLEPS) THEN
    _bAngStable := TRUE;
END_IF
IF NOT _bNonFin THEN
    _fAPrev := fTiltADeg;  _fBPrev := fTiltBDeg;  _bAngSeen := TRUE;   // 唯一写入点
END_IF

(* 段 5：主状态机（六相全覆盖 + ELSE 非法相位兜底） *)
CASE _eState OF

E_DL_RtcpSeqPhase.eIdle:
    _fCompZ := 0.0;
    (* 非有限与组态非法分别归因（R190：成因与码一一对应，禁共码） *)
    IF _bNonFin THEN
        _bFault := TRUE;  _uFault := DL_RTCP_C_FIN;  _eState := E_DL_RtcpSeqPhase.eFault;
    ELSIF _bCfgBad THEN
        _bFault := TRUE;  _uFault := DL_RTCP_C_CFG;  _eState := E_DL_RtcpSeqPhase.eFault;
    ELSIF bEnable AND (NOT _bFault) THEN
        _eState := E_DL_RtcpSeqPhase.ePivotCal;      // 拍 N+1 转出到标定相
    END_IF

E_DL_RtcpSeqPhase.ePivotCal:
    IF _bNonFin THEN
        _bFault := TRUE;  _uFault := DL_RTCP_C_FIN;  _eState := E_DL_RtcpSeqPhase.eFault;
    ELSIF _bCfgBad THEN
        _bFault := TRUE;  _uFault := DL_RTCP_C_CFG;  _eState := E_DL_RtcpSeqPhase.eFault;
    ELSIF NOT bEnable THEN
        _eState := E_DL_RtcpSeqPhase.eExit;          // 撤能使：不驻留标定相
    ELSIF tonCalTmo.Q THEN
        _bFault := TRUE;  _uFault := DL_RTCP_C_TMO;  _eState := E_DL_RtcpSeqPhase.eFault;
    ELSIF tonCalSettle.Q THEN
        _eState := E_DL_RtcpSeqPhase.eEnable;        // 拍 N+1 转出：标定完成
    END_IF

E_DL_RtcpSeqPhase.eEnable:
    (* 迁入执行相前的全量闸位复检（R274）：非有限与组态非法分别归因，禁误归软限位码 3 *)
    IF _bNonFin THEN
        _fCompZ := 0.0;  _bFault := TRUE;  _uFault := DL_RTCP_C_FIN;
        _eState := E_DL_RtcpSeqPhase.eFault;
    ELSIF _bCfgBad THEN
        _bFault := TRUE;  _uFault := DL_RTCP_C_CFG;
        _eState := E_DL_RtcpSeqPhase.eFault;
    ELSIF ABS(fTiltADeg) > LREAL_TO_REAL(DL_RTCP_SOFTLIM) THEN
        _bFault := TRUE;  _uFault := DL_RTCP_C_SOFT;  _eState := E_DL_RtcpSeqPhase.eFault;
    ELSIF ABS(fTiltBDeg) > LREAL_TO_REAL(DL_RTCP_SOFTLIM) THEN
        _bFault := TRUE;  _uFault := DL_RTCP_C_SOFT;  _eState := E_DL_RtcpSeqPhase.eFault;
    ELSIF NOT bEnable THEN
        _eState := E_DL_RtcpSeqPhase.eExit;
    ELSE
        _eState := E_DL_RtcpSeqPhase.eInterp;        // 迁入执行相：闸位已全量复检（R274）
    END_IF

E_DL_RtcpSeqPhase.eInterp:
    IF NOT bEnable THEN
        _eState := E_DL_RtcpSeqPhase.eExit;
    ELSIF _bNonFin THEN
        _fCompZ := 0.0;  _bFault := TRUE;  _uFault := DL_RTCP_C_FIN;
        _eState := E_DL_RtcpSeqPhase.eFault;
    ELSIF _bCfgBad THEN
        _fCompZ := 0.0;  _bFault := TRUE;  _uFault := DL_RTCP_C_CFG;
        _eState := E_DL_RtcpSeqPhase.eFault;         // 运行中组态非法（模式改号）：独立归因
    ELSIF NOT CalcPivotComp(fLenMm := fPivotLenMm, fADeg := fTiltADeg, fBDeg := fTiltBDeg, fZmm := _fCompZ) THEN
        _fCompZ := 0.0;  _bFault := TRUE;  _uFault := DL_RTCP_C_SOFT;
        _eState := E_DL_RtcpSeqPhase.eFault;         // 方法拒收：归因软限位
    ELSIF ABS(_fCompZ) > DL_RTCP_COMPLIM THEN
        _fCompZ := 0.0;  _bFault := TRUE;  _uFault := DL_RTCP_C_COMP;
        _eState := E_DL_RtcpSeqPhase.eFault;         // 补偿越限：独立归因（R190）
    END_IF

E_DL_RtcpSeqPhase.eExit:
    IF _fCompZ > 0.0 THEN
        _fCompZ := MAX(0.0, _fCompZ - DL_RTCP_RAMP);
    ELSIF _fCompZ < 0.0 THEN
        _fCompZ := MIN(0.0, _fCompZ + DL_RTCP_RAMP);
    ELSE
        _fCompZ := 0.0;  _eState := E_DL_RtcpSeqPhase.eIdle;   // 补偿归零才迁出
    END_IF

E_DL_RtcpSeqPhase.eFault:
    _fCompZ := 0.0;                                              // 故障相：补偿压 0（N1/N3）
    IF rtReset.Q THEN _eState := E_DL_RtcpSeqPhase.eIdle; END_IF // 唯一解除路径

ELSE
    _bFault := TRUE;  _uFault := DL_RTCP_C_ILL;  _eState := E_DL_RtcpSeqPhase.eFault;
END_CASE

(* 段 6：故障迁相闸（置于解除段之后，R274） *)
IF _bFault AND (_eState <> E_DL_RtcpSeqPhase.eFault) THEN
    _eState := E_DL_RtcpSeqPhase.eFault;
END_IF

(* 段 7：统一出口段（判据位与实值单点裁决，N4/R191） *)
bCompActive := (_eState = E_DL_RtcpSeqPhase.eInterp);
bError := _bFault;  uErrId := _uFault;
IF (_eState = E_DL_RtcpSeqPhase.eInterp) AND (_fCompZ = _fCompZ)
   AND ((_fCompZ - _fCompZ) = (_fCompZ - _fCompZ)) THEN
    fCompZmm := LREAL_TO_REAL(_fCompZ);
ELSE
    fCompZmm := 0.0;                                            // 非插补相或非有限：落 0（N1）
END_IF

(* 相位号镜像：单一 CASE 映射，禁多分支重复写同一状态（R20） *)
CASE _eState OF
    E_DL_RtcpSeqPhase.eIdle:     nPhase := 0;
    E_DL_RtcpSeqPhase.ePivotCal: nPhase := 10;
    E_DL_RtcpSeqPhase.eEnable:   nPhase := 20;
    E_DL_RtcpSeqPhase.eInterp:   nPhase := 30;
    E_DL_RtcpSeqPhase.eExit:     nPhase := 40;
    E_DL_RtcpSeqPhase.eFault:    nPhase := 90;
ELSE
    nPhase := 90;
END_CASE
END_FUNCTION_BLOCK
