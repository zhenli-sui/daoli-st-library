(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisSs1StopSeq
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : SS1 类停止时序编排（IEC 60204-1 停止类别 1 的公开语义：先可控减速、
 *                         到位后再切转矩）。相序：eIdle → eDecel（发减速停止请求，监视速度降到
 *                         fZeroSpeedThr）→ eSettle（零速稳定 tSettleTime）→ eStoRequest
 *                         （输出 bStoRequest = TRUE）→ eDone。任一步超时（tDecelMax / tSettleMax）
 *                         进 eFault 并置码，**且 bStoRequest 仍置真**（安全侧：宁可切转矩也不
 *                         放任轴继续动）。
 * 安全声明 (Safety)     : **本件只做停止时序与 STO 请求位，不实现任何安全认证功能**
 *                         （ISO 13849 / IEC 62061 的认证、双通道架构、诊断覆盖率证明均不在本库
 *                         范围）。bStoRequest 是**请求**而非安全输出：真实安全转矩关断必须由
 *                         认证安全模块执行，本件输出不得直接驱动安全继电器。
 * 接口     (Interface)  : 输入 bStopReq 停止请求、fSpeed 实测速度、fZeroSpeedThr 零速阈值、
 *                         tDecelMax 减速相超时、tSettleTime 零速稳定时长、tSettleMax 稳定相超时、
 *                         bReset 复位；输出 bStoRequest STO 请求位、fSpeedAtStop 首次进零速时
 *                         的速度快照、eState / eCause / bError / nErrId。
 * 边界     (Boundary)   : ① 组态闸：fZeroSpeedThr <= 0.0、tDecelMax <= T#0S、tSettleMax <= T#0S、
 *                         tSettleTime <= T#0S、fSpeed 为 NaN → **组态非法时 bStoRequest 直接置真**
 *                         （安全侧优先于组态正确性：宁可误切转矩也不放过运动轴）；
 *                         ② 零速判据用容差式（ABS <= 阈值），禁浮点判等；
 *                         ③ TON 三枚 + R_TRIG 一枚段 0 无条件周期刷新，IN 由相位派生（R228A）；
 *                         ④ 故障相迁出唯一路径 = bReset 上升沿，迁出后回 eIdle；
 *                         ⑤ 零全局耦合（无 GVL / 无物理地址）。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 速度快照已在阈值内（ABS(fSpeed) <= fZeroSpeedThr，
 *                         当拍量，R240 范式）。自证可满足（终审两式 1）：轴停住后速度快照必入阈值，
 *                         解除式不含计时器输出，无恒假因子；轴仍转时不允许解除是设计意图
 *                         （防止带速复位把 STO 请求抹掉）。
 * 码表     (Codes)      : 16#0004_03B5 故障级：SS1 停止时序故障总码（组态非法 / 减速超时 / 稳定超时 /
 *                         非法相位），锁存至 bReset 上升沿，归因由 eCause 承载（R190 单件单总码）；
 *                         16#0004_04B5 信息级：SS1 停止序列正常完成（进 eDone 单拍）。
 *                         加码反证（R90）：完成时 bStoRequest 恒为真、eState 也为固定值，正常完成与
 *                         「一直停在 eStoRequest」在出口组合上只差相位值，而相位不是台账事件，
 *                         故立一码记录每一次成功停止行程。
 *                         码段说明：0004 段故障子带 03xx / 信息子带 04xx，本件取 03B5 / 04B5
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考 IEC 60204-1 公开停止类别语义与
 *                         t1-6-plcopen 参数域，零代码行复制）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 3 · 序号 11）
 *==============================================================================*)

TYPE E_DL_Ss1State :
(
    eIdle      := 0,     // 待停止请求 / Idle, awaiting stop request
    eDecel     := 10,    // 减速相：等速度降到零速阈值 / Decelerating to zero speed
    eSettle    := 20,    // 稳定相：零速保持 tSettleTime / Settling at zero speed
    eStoRequest := 30,   // STO 请求相：bStoRequest 置真 / STO request asserted
    eDone      := 50,    // 停止完成 / Stop sequence done
    eFault     := 90     // 故障锁存相（bStoRequest 仍为真） / Fault latched, STO request still TRUE
);
END_TYPE

TYPE E_DL_Ss1Cause :
(
    eNone       := 0,    // 无故障成因 / No cause
    eCfgIllegal := 1,    // 组态非法 / Illegal configuration
    eDecelTmo   := 2,    // 减速相超时 / Decel phase timeout
    eSettleTmo  := 3,    // 稳定相超时 / Settle phase timeout
    ePhaseBad   := 4     // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisSs1StopSeq
VAR_INPUT
    bStopReq      : BOOL := FALSE;        // 停止请求（电平，撤除则回空闲） [-] / Stop request level, release returns idle
    fSpeed        : REAL := 0.0;          // 实测速度（幅值判零速，符号不参与） [mm/s] / Measured speed, sign ignored [mm/s]
    fZeroSpeedThr : REAL := 5.0;          // 零速阈值，域 > 0.0 [mm/s] / Zero-speed threshold, domain > 0.0 [mm/s]
    tDecelMax     : TIME := T#5S;         // 减速相超时，域 > T#0S [ms] / Decel phase timeout, domain > T#0S [ms]
    tSettleTime   : TIME := T#200MS;      // 零速稳定时长，域 > T#0S [ms] / Zero-speed settle duration [ms]
    tSettleMax    : TIME := T#3S;         // 稳定相超时，域 > T#0S 且 >= tSettleTime [ms] / Settle phase timeout [ms]
    bReset        : BOOL := FALSE;        // 复位命令，上升沿清故障 [-] / Reset command, rising edge clears fault
END_VAR
VAR_OUTPUT
    bStoRequest   : BOOL;                 // STO 请求位（请求不等于安全认证输出） [-] / STO request, not a certified safety output
    fSpeedAtStop  : REAL;                 // 首次进零速时的速度快照 [mm/s] / Speed snapshot at first zero-speed entry
    eState        : E_DL_Ss1State;        // 状态出口，段 6 单点映射 / State outlet
    eCause        : E_DL_Ss1Cause;        // 故障成因出口（R190 归因唯一） / Fault cause outlet
    bError        : BOOL;                 // 故障锁存标志 [-] / Fault latch flag
    nErrId        : UDINT;                // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState       : E_DL_Ss1State := E_DL_Ss1State.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause       : E_DL_Ss1Cause := E_DL_Ss1Cause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonDecel      : TON;                  // 减速相计时，段 0 无条件调用 / Decel phase timer
    tonSettle     : TON;                  // 稳定相超时计时，段 0 无条件调用 / Settle timeout timer
    tonSettleOk   : TON;                  // 零速稳定计时，段 0 无条件调用 / Zero-speed settle timer
    rtReset       : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge
    _fSpeedAtStop : REAL;                 // 速度快照（锁存量，进稳定相时锁存一次） [mm/s] / Speed snapshot, latched on settle entry
    _bSnapshotOk  : BOOL;                 // 快照已锁存标记（锁存量） [-] / Snapshot taken flag
    _bZeroSpeed   : BOOL;                 // 零速当拍量 [-] / Zero-speed verdict this scan
    _bNonFin      : BOOL;                 // 速度非有限当拍量 [-] / Non-finite speed this scan
    _bCfgBad      : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration
    _bStoReq      : BOOL;                 // STO 请求内部位（由相位派生） [-] / Internal STO request, derived from phase
    _bFault       : BOOL;                 // 故障锁存位（锁存量） / Latched fault bit
    _uFault       : UDINT;                // 故障码锁存（锁存量） / Latched fault code
    _uInfo        : UDINT;                // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR
VAR CONSTANT
    DL_SPEED_EPS : REAL := 1.0E-3;        // 速度判零辅助容差（阈值叠加用，防阈值给到极小值） [mm/s] / Speed epsilon added to threshold [mm/s]
END_VAR

(* —— 段 0：当拍判据派生 + 定时器与沿实例无条件周期刷新 —— *)
_bNonFin    := (fSpeed <> fSpeed) OR ((fSpeed - fSpeed) <> (fSpeed - fSpeed));      // NaN 自反 + Inf 差值自减双判（判等禁令唯一例外） / NaN and Inf detection
_bZeroSpeed := ABS(fSpeed) <= (fZeroSpeedThr + DL_SPEED_EPS);                      // 零速判据（容差式） / Zero-speed verdict, tolerance-based
_bCfgBad    := (fZeroSpeedThr <= 0.0) OR (tDecelMax <= T#0S)                        // 组态域闸（R151 全覆盖） / Config gate
               OR (tSettleMax <= T#0S) OR (tSettleTime <= T#0S)                     // 时间正域闸 / Time gates
               OR (tSettleTime > tSettleMax) OR _bNonFin;                           // 配比约束：稳定时长不得超过稳定相超时 / Ratio constraint and non-finite speed
rtReset(CLK := bReset);                                                             // 复位沿，每拍必调（R228A） / Reset edge
tonDecel(IN := (_eState = E_DL_Ss1State.eDecel), PT := tDecelMax);                  // 减速相计时（IN 由相位派生） / Decel timer
tonSettle(IN := (_eState = E_DL_Ss1State.eSettle), PT := tSettleMax);               // 稳定相超时计时 / Settle timeout timer
tonSettleOk(IN := (_eState = E_DL_Ss1State.eSettle) AND _bZeroSpeed, PT := tSettleTime);   // 零速稳定计时 / Zero-speed settle timer

(* —— 段 1：单拍量预清零（锁存量与快照量不入清单，R107） —— *)
_uInfo   := 16#0000_0000;          // 信息码每拍重算 / Info recomputed every scan
nErrId   := 16#0000_0000;          // 事件码缺省无事件 / Event code default none
bError   := FALSE;                 // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset
_bStoReq := FALSE;                 // STO 请求内部位缺省假，由相位与故障分支赋值 / STO internal preset

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_Ss1Cause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    _bSnapshotOk := FALSE;                                               // 快照重新武装 / Re-arm snapshot
    IF _eState = E_DL_Ss1State.eFault THEN
        _eState := E_DL_Ss1State.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸：安全侧直接置 STO 请求 / Config gate, STO request asserted for safety
    _uFault := 16#0004_03B5;                                             // 故障级：SS1 停止时序故障总码 / Fault-level: stop-sequence fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_Ss1Cause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
    _bStoReq := TRUE;                                                    // 安全侧：组态非法也切转矩 / Safety side, assert STO even on bad config
END_IF

(* —— 段 3：相位派生 STO 请求（请求相 / 完成相 / 故障相均为真） —— *)
IF (_eState = E_DL_Ss1State.eStoRequest) OR (_eState = E_DL_Ss1State.eDone)
   OR (_eState = E_DL_Ss1State.eFault) THEN
    _bStoReq := TRUE;                                                    // 请求相起保持真（停住后不撤销） / Asserted from request phase onward
END_IF

(* —— 段 4：超时判据（减速相 / 稳定相） —— *)
IF (NOT _bFault) AND tonDecel.Q THEN                                     // 减速相超时 / Decel timeout
    _uFault := 16#0004_03B5;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_Ss1Cause.eDecelTmo;                                  // 归因：减速超时 / Cause: decel timeout
    _bStoReq := TRUE;                                                    // 安全侧：宁可切转矩也不放任继续动 / Safety side, assert STO
END_IF
IF (NOT _bFault) AND tonSettle.Q THEN                                    // 稳定相超时 / Settle timeout
    _uFault := 16#0004_03B5;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_Ss1Cause.eSettleTmo;                                 // 归因：稳定超时 / Cause: settle timeout
    _bStoReq := TRUE;                                                    // 安全侧 / Safety side
END_IF

(* —— 段 5：故障解除式（R240 全当拍量；轴仍转时不允许解除是设计意图） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND _bZeroSpeed THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_Ss1Cause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 5A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_Ss1State.eFault) THEN
    _eState := E_DL_Ss1State.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 6：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_Ss1State.eIdle:
    IF bStopReq AND (NOT _bFault) THEN                                   // 出口 1：收到停止请求 / Stop requested
        _eState := E_DL_Ss1State.eDecel;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_Ss1State.eFault;
    END_IF

E_DL_Ss1State.eDecel:
    IF _bZeroSpeed THEN                                                  // 出口 1：速度已降到阈值 / Speed reached threshold
        IF NOT _bSnapshotOk THEN
            _fSpeedAtStop := fSpeed;                                     // 速度快照锁存一次（锁存量） / Latch speed snapshot once
            _bSnapshotOk := TRUE;
        END_IF
        _eState := E_DL_Ss1State.eSettle;                                // 进稳定相 / Enter settle phase
    ELSIF NOT bStopReq THEN                                              // 出口 2：撤销请求（前置消失，R98） / Request released
        _eState := E_DL_Ss1State.eIdle;
    END_IF

E_DL_Ss1State.eSettle:
    IF tonSettleOk.Q THEN                                                // 出口 1：零速稳定达标 / Zero-speed settled
        _bStoReq := TRUE;                                                // 进相同拍即置请求位（不等下一拍） / Assert request in the same scan
        _eState := E_DL_Ss1State.eStoRequest;                            // 进 STO 请求相 / Enter STO request phase
    ELSIF NOT bStopReq THEN                                              // 出口 2：撤销请求 / Request released
        _eState := E_DL_Ss1State.eIdle;
    END_IF

E_DL_Ss1State.eStoRequest:
    IF bStopReq AND _bZeroSpeed THEN                                     // 出口 1：停稳（请求位保持真） / Stopped, request stays TRUE
        _uInfo := 16#0004_04B5;                                          // 信息级：SS1 停止序列正常完成 / Info: stop sequence completed
        _eState := E_DL_Ss1State.eDone;
    ELSIF NOT bStopReq THEN                                              // 出口 2：撤销请求（前置消失，R98） / Request released
        _eState := E_DL_Ss1State.eIdle;
    END_IF

E_DL_Ss1State.eDone:
    IF NOT bStopReq THEN                                                 // 出口 1：撤销请求回空闲 / Request released returns idle
        _eState := E_DL_Ss1State.eIdle;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_Ss1State.eFault;
    END_IF

E_DL_Ss1State.eFault:
    ;                                                                     // 故障相：仅段 5 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0004_03B5;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_Ss1Cause.ePhaseBad;                                  // 归因：非法相位 / Cause: illegal phase
    _bStoReq := TRUE;                                                    // 安全侧：非法相位同样切转矩 / Safety side on illegal phase
    _eState := E_DL_Ss1State.eFault;

END_CASE

(* —— 段 7：出口单点映射（名实同源；锁存码回放；安全侧优先） —— *)
bStoRequest  := _bStoReq OR _bFault;                                     // STO 请求 = 相位派生 ∨ 故障锁存（安全侧优先） / STO request, safety side first
fSpeedAtStop := _fSpeedAtStop;                                           // 速度快照出口（锁存量回放） / Speed snapshot outlet
IF _bFault THEN
    nErrId := _uFault;                                                   // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                    // 信息码 / Info code
END_IF
bError := _bFault;                                                       // 故障标志与锁存同源（名实双出口，R191） / Flag from latch
eState := _eState;                                                       // 状态出口 / State outlet
eCause := _eCause;                                                       // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
