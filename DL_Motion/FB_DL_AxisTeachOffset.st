(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisTeachOffset
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 示教点与配方偏移管理。① 示教：bTeach 上升沿在轴静止（外部注入
 *                         bAxisStandstill 为真）时把当前 fPosAct 锁存进 _fTaughtPos；运动中
 *                         示教一律拒绝并置信息级（防采样到抖动位置，这是现场示教偏移的
 *                         首要误差源）；② 应用偏移：bApplyOffset 上升沿把 fOffsetValue 写入
 *                         配方偏移槽，写入前先算候选目标位（示教位 + 偏移）并做软限校验，
 *                         **越限则拒绝且原偏移保持不被覆盖**（先判后写，绝不先写后判）。
 * 接口     (Interface)  : 输入 fPosAct 当前实际位置、bTeach 示教命令、bApplyOffset 应用偏移命令、
 *                         fOffsetValue 待写入偏移值、fSoftLo / fSoftHi 轴软限、bAxisStandstill
 *                         外部注入的静止位、bReset 复位；输出 fTaughtPos 已示教位置、fOffsetApplied
 *                         当前生效偏移、bTeachOk 示教受理成功单拍位、eState / eCause / bError / nErrId。
 * 边界     (Boundary)   : ① 组态闸：fSoftHi <= fSoftLo 或任一浮点引脚 NaN → 故障锁存；
 *                         ② 越软限拦截按「候选目标位 = 示教位 + 待写入偏移」判定，判定通过后才
 *                         写偏移槽（写点唯一，无先写后判路径）；
 *                         ③ 非有限位置 → 故障闸，示教不受理（不把 NaN 写进示教槽，R133）；
 *                         ④ R_TRIG 三枚（示教/应用/复位）段 0 无条件周期刷新；
 *                         ⑤ 故障相迁出唯一路径 = bReset 上升沿；⑥ 零全局耦合（无 GVL / 无物理地址）。
 * 分工声明 (Scope)      : 本件只管理示教值与配方偏移，**不下发定位指令、不判断轴是否到位**；
 *                         轴状态与运动指令唯一属主为 `I_DL_MotionAxis`。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 越限条件已解除（当拍候选目标位落在
 *                         〔fSoftLo, fSoftHi〕内，全为当拍量，R240 范式）。
 *                         自证可满足（终审两式 1）：解除式只含当拍比较，偏移值或示教位修正后
 *                         即可达；不含计时器输出与锁存量比较，无恒假因子。
 * 码表     (Codes)      : 16#0004_03B6 故障级：示教偏移故障总码（组态非法 / 目标位越软限 /
 *                         非法相位），锁存至 bReset 上升沿，归因由 eCause 承载（R190 单件单总码）；
 *                         16#0004_04B6 信息级：运动中示教被拒绝（信息级，不锁故障）。
 *                         加码反证（R90）：拒绝示教时 fTaughtPos 保持旧值、bTeachOk 为假，
 *                         该否决若不留码则 HMI 上「操作员按了示教但没生效」完全不可观测
 *                         （bTeachOk 是单拍位且为假），故立一码。
 *                         码段说明：0004 段故障子带 03xx / 信息子带 04xx，本件取 03B6 / 04B6
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考示教-配方偏移现场惯例与参数域，零代码行复制；
 *                         t1-6-plcopen 族）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 3 · 序号 12）
 *==============================================================================*)

TYPE E_DL_AtoState :
(
    eIdle  := 0,     // 未示教（无有效示教值） / Idle, no valid taught position yet
    eRun   := 10,    // 示教值就绪，可应用偏移 / Taught value ready, offset applicable
    eFault := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_AtoCause :
(
    eNone       := 0,   // 无故障成因 / No cause
    eCfgIllegal := 1,   // 组态非法 / Illegal configuration
    eSoftLimit  := 2,   // 候选目标位越软限 / Candidate target outside soft limits
    eNonFinite  := 3,   // 位置或偏移非有限 / Non-finite position or offset
    ePhaseBad   := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisTeachOffset
VAR_INPUT
    fPosAct        : REAL := 0.0;         // 当前实际位置 [mm] / Current actual position [mm]
    bTeach         : BOOL := FALSE;       // 示教命令，上升沿受理一次 [-] / Teach command, rising edge accepts once
    bApplyOffset   : BOOL := FALSE;       // 应用偏移命令，上升沿受理一次 [-] / Apply-offset command, rising edge accepts once
    fOffsetValue   : REAL := 0.0;         // 待写入的偏移值 [mm] / Offset value to be written [mm]
    fSoftLo        : REAL := -100.0;      // 轴软限下限，域 < fSoftHi [mm] / Soft limit lower bound, domain < fSoftHi [mm]
    fSoftHi        : REAL := 100.0;       // 轴软限上限，域 > fSoftLo [mm] / Soft limit upper bound, domain > fSoftLo [mm]
    bAxisStandstill: BOOL := FALSE;       // 轴静止位（外部注入，示教受理前置） [-] / Axis standstill flag, injected
    bReset         : BOOL := FALSE;       // 复位命令，上升沿清故障 [-] / Reset command, rising edge clears fault
END_VAR
VAR_OUTPUT
    fTaughtPos     : REAL;                // 已示教位置（锁存量回放） [mm] / Taught position, latched replay [mm]
    fOffsetApplied : REAL;                // 当前生效偏移（锁存量回放） [mm] / Effective offset, latched replay [mm]
    bTeachOk       : BOOL;                // 示教受理成功单拍位 [-] / Teach accepted, single scan
    eState         : E_DL_AtoState;       // 状态出口，段 6 单点映射 / State outlet
    eCause         : E_DL_AtoCause;       // 故障成因出口（R190 归因唯一） / Fault cause outlet
    bError         : BOOL;                // 故障锁存标志 [-] / Fault latch flag
    nErrId         : UDINT;               // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState        : E_DL_AtoState := E_DL_AtoState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause        : E_DL_AtoCause := E_DL_AtoCause.eNone;    // 故障成因锁存（锁存量） / Latched cause
    rtTeach        : R_TRIG;              // 示教沿实例，段 0 无条件调用 / Teach rising edge
    rtApply        : R_TRIG;              // 应用沿实例，段 0 无条件调用 / Apply rising edge
    rtReset        : R_TRIG;              // 复位沿实例，段 0 无条件调用 / Reset edge
    _fTaughtPos    : REAL;                // 示教位置槽（锁存量） [mm] / Taught position slot, latched
    _fOffsetSlot   : REAL;                // 配方偏移槽（锁存量，唯一写入点） [mm] / Recipe offset slot, single write point
    _bTaughtValid  : BOOL;                // 示教槽有效标记（锁存量） [-] / Taught slot valid flag
    _fCand        : REAL;                 // 候选目标位 = 示教位 + 待写入偏移 [mm] / Candidate target, taught plus offset [mm]
    _bNonFin       : BOOL;                // 输入非有限当拍量 [-] / Non-finite input this scan
    _bCfgBad       : BOOL;                // 组态非法当拍量 [-] / Illegal configuration
    _bCandInRange  : BOOL;                // 候选目标位在软限内当拍量 [-] / Candidate target inside soft limits
    _bFault        : BOOL;                // 故障锁存位（锁存量） / Latched fault bit
    _uFault        : UDINT;               // 故障码锁存（锁存量） / Latched fault code
    _uInfo         : UDINT;               // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : REAL := 1.0E-6;        // 浮点判零容差（软限比较统一口径） [mm] / Float epsilon for zero tests [mm]
END_VAR

(* —— 段 0：当拍判据派生 + 沿实例无条件周期刷新 —— *)
_bNonFin := (fPosAct <> fPosAct) OR (fOffsetValue <> fOffsetValue)                        // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
          OR (fSoftLo <> fSoftLo) OR (fSoftHi <> fSoftHi)                                // 软限 NaN 判 / Soft limit NaN tests
          OR ((fPosAct - fPosAct) <> (fPosAct - fPosAct))                                // 位置 Inf 差值自减判 / Inf test on position
          OR ((fOffsetValue - fOffsetValue) <> (fOffsetValue - fOffsetValue));            // 偏移 Inf 差值自减判 / Inf test on offset
_bCfgBad := (fSoftHi <= fSoftLo) OR ((fSoftHi - fSoftLo) <= DL_FLOAT_EPS);                // 软限几何组态闸（R151） / Soft-limit geometry gate
_fCand  := _fTaughtPos + fOffsetValue;                                                   // 候选目标位 / Candidate target position
_bCandInRange := (_fCand >= fSoftLo) AND (_fCand <= fSoftHi);                             // 候选位在软限内当拍量 / Candidate inside soft limits
rtTeach(CLK := bTeach);                                                                   // 示教沿，每拍必调（R228A） / Teach edge, called every scan
rtApply(CLK := bApplyOffset);                                                             // 应用沿，每拍必调 / Apply edge, called every scan
rtReset(CLK := bReset);                                                                   // 复位沿，每拍必调 / Reset edge, called every scan

(* —— 段 1：单拍量预清零（锁存量不入清单，R107） —— *)
_uInfo         := 16#0000_0000;        // 信息码每拍重算 / Info recomputed every scan
bTeachOk       := FALSE;               // 示教成功位每拍预清，唯一分支置位（R44 范式） / Teach-ok preset
nErrId         := 16#0000_0000;        // 事件码缺省无事件 / Event code default none
bError         := FALSE;               // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset

(* —— 段 2：复位沿 + 组态域闸 + 非有限闸 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_AtoCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    IF _eState = E_DL_AtoState.eFault THEN
        _eState := E_DL_AtoState.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸 / Configuration gate
    _uFault := 16#0004_03B6;                                             // 故障级：示教偏移故障总码 / Fault-level: teach/offset fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_AtoCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF
IF (NOT _bFault) AND _bNonFin THEN                                       // 位置/偏移非有限 / Non-finite position or offset
    _uFault := 16#0004_03B6;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_AtoCause.eNonFinite;                                 // 归因：非有限 / Cause: non-finite
END_IF

(* —— 段 3：示教授理（静止前置 + 非有限拒收） —— *)
IF (NOT _bFault) AND rtTeach.Q THEN                                      // 示教上升沿（当拍量） / Teach rising edge
    IF bAxisStandstill THEN                                              // 静止前置满足才受理 / Accept only at standstill
        _fTaughtPos := fPosAct;                                          // 锁存当前位置（示教槽唯一写入点） / Latch current position
        _bTaughtValid := TRUE;                                           // 示教槽置有效 / Mark taught slot valid
        bTeachOk := TRUE;                                                // 单拍成功位 / Single-scan success flag
    ELSE
        _uInfo := 16#0004_04B6;                                          // 信息级：运动中示教被拒绝 / Info: teach rejected while moving
    END_IF
END_IF

(* —— 段 4：应用偏移（先判软限后写槽，绝不先写后判） —— *)
IF (NOT _bFault) AND rtApply.Q THEN                                      // 应用上升沿（当拍量） / Apply rising edge
    IF _bTaughtValid AND _bCandInRange THEN                              // 前置齐备且候选位在软限内 / Preconditions met and candidate in range
        _fOffsetSlot := fOffsetValue;                                    // 写偏移槽（唯一写入点，判定通过后才写） / Write offset slot only after the check passes
    ELSE
        _uFault := 16#0004_03B6;                                         // 故障级：候选目标位越软限（或未示教） / Fault-level: candidate outside limits or not taught
        _bFault := TRUE;
        bError  := TRUE;                                                 // 故障标志同拍置位（R45 配对） / Error flag set same scan
        _eCause := E_DL_AtoCause.eSoftLimit;                             // 归因：越软限 / Cause: soft limit
    END_IF
END_IF

(* —— 段 5：故障解除式（R240 全当拍量） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) AND (_bCandInRange OR (NOT _bTaughtValid)) THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_AtoCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 5A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_AtoState.eFault) THEN
    _eState := E_DL_AtoState.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 6：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_AtoState.eIdle:
    IF _bTaughtValid AND (NOT _bFault) THEN                              // 出口 1：示教槽已就绪 / Taught slot ready
        _eState := E_DL_AtoState.eRun;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_AtoState.eFault;
    END_IF

E_DL_AtoState.eRun:
    IF (NOT _bTaughtValid) THEN                                          // 出口 1：示教槽失效（前置消失，R98） / Taught slot invalid
        _eState := E_DL_AtoState.eIdle;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_AtoState.eFault;
    END_IF

E_DL_AtoState.eFault:
    ;                                                                     // 故障相：仅段 5 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0004_03B6;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_AtoCause.ePhaseBad;                                  // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_AtoState.eFault;

END_CASE

(* —— 段 7：出口单点映射（名实同源；锁存码回放） —— *)
fTaughtPos     := _fTaughtPos;                                           // 示教位出口（锁存量回放） / Taught position outlet
fOffsetApplied := _fOffsetSlot;                                          // 生效偏移出口（锁存量回放） / Effective offset outlet
IF _bFault THEN
    bTeachOk := FALSE;                                                   // 故障相不宣称示教成功 / No success claim in fault
    nErrId   := _uFault;                                                 // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId   := _uInfo;                                                  // 信息码 / Info code
END_IF
bError := _bFault;                                                       // 故障标志与锁存同源（名实双出口，R191） / Flag from latch
eState := _eState;                                                       // 状态出口 / State outlet
eCause := _eCause;                                                       // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
