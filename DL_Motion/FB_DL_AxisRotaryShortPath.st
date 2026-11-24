(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisRotaryShortPath
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / ABS / TRUNC），零厂商私有库
 * 功能描述 (Function)   : 旋转轴（可多圈）最短路径规划。把当前任意圈数域位置归一化到 [0,360)，
 *                         再据目标角求最小转角 d：d > 180° 走反向、d < −180° 走正向；
 *                         加圈后得到绝对目标位 fTargetAbs 与圈号 nTurnIndex，并按软限做二次
 *                         校核（首选圈越限时尝试另一圈，仍越限则拒绝并置码）。
 * 角度约定 (Corner)     : **d 恰好等于 ±180° 时**：按「正方向（CW，角度增大）优先」确定为 +180°，
 *                         且 bCwOnly 为真时无论 d 正负一律转成正向等价角〔即取 +360 方向的长路径〕。
 *                         该约定写死在此处与实现一致，不得留空由调用方猜测。
 * 接口     (Interface)  : 输入 fPosAct 当前位置（可为任意圈数）、fTargetDeg 目标角（0~360）、
 *                         fSoftLoDeg / fSoftHiDeg 圈域软限、bCwOnly 单向（只允许正向）模式、
 *                         bExecute 规划触发沿、bReset 复位；输出 bShortestCw 转向建议（TRUE=正向）、
 *                         fTargetAbs 加圈后绝对目标位、nTurnIndex 目标圈号、bValid 规划有效、
 *                         eState / eCause / bError / nErrId。
 * 边界     (Boundary)   : ① 归一化一律**条件加减**，禁 MOD（负数取余在三平台不一致，R10/R48 铁律），
 *                         循环带守卫计数器，超限即置码跳出（不死循环）；
 *                         ② 圈号用 DINT 承载并带守卫上限，越界前置判，绝不静默回绕；
 *                         ③ 组态闸：fSoftHiDeg <= fSoftLoDeg、fTargetDeg 越 [0,360]、任一时恒为
 *                         NaN → 故障锁存（每个参与判据的引脚都在闸内，R151）；
 *                         ④ **整数进位点两向量已推**（R149 终审两式 2）：
 *                         向量 A：fPosAct = 720.0、fTargetDeg = 0.0 → 归一 0.0、d = 0.0，
 *                                 fTargetAbs = 720.0、nTurnIndex = 2（整除点不跳圈，不得出 1 或 3）；
 *                         向量 B：fSoftLoDeg = 0.0、fSoftHiDeg = 359.0、fTargetDeg = 360.0
 *                                 → 候选位 360.0 越上限，须尝试另一圈（0.0）并成功，**不得回绕后
 *                                 仍报越限**；
 *                         ⑤ R_TRIG 两枚（执行/复位）段 0 无条件刷新；
 *                         ⑥ 故障相迁出唯一路径 = bReset 上升沿；⑦ 零全局耦合（无 GVL / 无物理地址）。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 目标域合法 ∧ 〔当拍已求得软限内解 ∨
 *                         目标角本身落在软限区间内〕（两分支均全当拍量，R240 范式）。
 *                         自证可满足（终审两式 1）：分支 2 只依赖 fTargetDeg 与软限的当拍比较，
 *                         不依赖执行沿（若只保留依赖 _bSolved 的分支 1，未按执行时该项恒假 →
 *                         故障永久不可恢复，属 R152 恒假组合反例），故实现为双分支析取式。
 * 码表     (Codes)      : 16#0004_03B8 故障级：旋转最短路径故障总码（组态非法 / 目标角越域 /
 *                         归一化超迭代守卫 / 软限无解 / 非法相位），锁存至 bReset 上升沿，
 *                         归因由 eCause 承载（R190 单件单总码）；
 *                         16#0004_04B8 信息级：规划成功（给出转向建议与绝对目标位）。
 *                         加码反证（R90）：规划成功与「未执行」在 fTargetAbs 上可能同值（d = 0 时
 *                         目标位等于当前位置），bValid 又只是布尔位不进台账，故立一码留痕。
 *                         码段说明：0004 段故障子带 03xx / 信息子带 04xx，本件取 03B8 / 04B8
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考旋转轴最短路径与角度归约公开算法，
 *                         零代码行复制；t1-6-plcopen 族）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 3 · 序号 14）
 *==============================================================================*)

TYPE E_DL_RspState :
(
    eIdle  := 0,     // 待规划触发 / Idle, awaiting execute edge
    eRun   := 10,    // 规划结果就绪 / Plan ready
    eFault := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_RspCause :
(
    eNone       := 0,   // 无故障成因 / No cause
    eCfgIllegal := 1,   // 组态非法（软限倒置或 NaN） / Illegal configuration
    eTargetBad  := 2,   // 目标角越 [0,360] / Target angle out of domain
    eIterGuard  := 3,   // 归一化超迭代守卫 / Normalisation iteration guard tripped
    eSoftLimit  := 4,   // 软限无解（两圈均越限） / No solution inside soft limits
    eTurnGuard  := 5,   // 圈号超守卫上限 / Turn index guard tripped
    ePhaseBad   := 6    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisRotaryShortPath
VAR_INPUT
    fPosAct     : REAL := 0.0;          // 当前位置（任意圈数域，度） [deg] / Current position in any turn domain [deg]
    fTargetDeg  : REAL := 0.0;          // 目标角，有效域 0.0 ~ 360.0 [deg] / Target angle, domain 0.0..360.0 [deg]
    fSoftLoDeg  : REAL := 0.0;          // 圈域软限下限，域 < fSoftHiDeg [deg] / Turn-domain soft limit lower bound [deg]
    fSoftHiDeg  : REAL := 1080.0;       // 圈域软限上限，域 > fSoftLoDeg [deg] / Turn-domain soft limit upper bound [deg]
    bCwOnly     : BOOL := FALSE;        // 单向模式（只允许正方向 CW） [-] / CW-only mode
    bExecute    : BOOL := FALSE;        // 规划触发，上升沿受理一次 [-] / Plan trigger, rising edge accepts once
    bReset      : BOOL := FALSE;        // 复位命令，上升沿清故障 [-] / Reset command, rising edge clears fault
END_VAR
VAR_OUTPUT
    bShortestCw : BOOL;                 // 转向建议：TRUE = 正方向（CW，角度增大） [-] / Direction advice, TRUE means CW
    fTargetAbs  : REAL;                 // 加圈后的绝对目标位 [deg] / Absolute target after turn selection [deg]
    nTurnIndex  : DINT;                 // 目标圈号（DINT 钳位承载） [圈] / Target turn index carried in DINT [turn]
    bValid      : BOOL;                 // 规划结果有效 [-] / Plan valid
    eState      : E_DL_RspState;        // 状态出口，段 6 单点映射 / State outlet
    eCause      : E_DL_RspCause;        // 故障成因出口（R190 归因唯一） / Fault cause outlet
    bError      : BOOL;                 // 故障锁存标志 [-] / Fault latch flag
    nErrId      : UDINT;                // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState     : E_DL_RspState := E_DL_RspState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause     : E_DL_RspCause := E_DL_RspCause.eNone;    // 故障成因锁存（锁存量） / Latched cause
    rtExec      : R_TRIG;               // 执行沿实例，段 0 无条件调用 / Execute edge
    rtReset     : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge
    _fNorm      : REAL;                 // 归一化角（[0,360) 当拍量） [deg] / Normalised angle this scan [deg]
    _fDiff      : REAL;                 // 最小转角候选（当拍量） [deg] / Candidate shortest angle [deg]
    _fAbsCand   : REAL;                 // 候选绝对目标位（当拍量） [deg] / Candidate absolute target [deg]
    _fTmp       : REAL;                 // 圈号求解临时量（当拍量） [deg] / Temporary value for turn index
    _nIter      : DINT;                 // 归一化迭代计数（当拍量） [次] / Normalisation iteration count
    _nTurnCalc  : DINT;                 // 圈号求解值（当拍量） [圈] / Turn index solving value
    _bNonFin    : BOOL;                 // 输入非有限当拍量 [-] / Non-finite input this scan
    _bCfgBad    : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration
    _bTargetBad : BOOL;                 // 目标角越域当拍量 [-] / Target out of domain
    _bIterBad   : BOOL;                 // 迭代守卫触发当拍量 [-] / Iteration guard tripped
    _bTurnBad   : BOOL;                 // 圈号守卫触发当拍量 [-] / Turn guard tripped
    _bSolved    : BOOL;                 // 软限求解成功当拍量 [-] / Solved inside soft limits
    _bFault     : BOOL;                 // 故障锁存位（锁存量） / Latched fault bit
    _uFault     : UDINT;                // 故障码锁存（锁存量） / Latched fault code
    _uInfo      : UDINT;                // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : REAL := 1.0E-4;      // 角度判等容差（度级精度） [deg] / Angle epsilon at degree resolution [deg]
    DL_FULL_TURN : REAL := 360.0;       // 整圈角度，编译期常量 [deg] / Full turn constant [deg]
    DL_HALF_TURN : REAL := 180.0;       // 半圈角度，编译期常量 [deg] / Half turn constant [deg]
    DL_ITER_MAX  : DINT := 1000;        // 归一化迭代守卫上限 [次] / Normalisation iteration guard [count]
    DL_TURN_MAX  : DINT := 100000;      // 圈号守卫绝对值上限 [圈] / Turn index absolute guard [turn]
END_VAR

(* —— 段 0：当拍量派生 + 沿实例无条件周期刷新 —— *)
_bNonFin := (fPosAct <> fPosAct) OR (fTargetDeg <> fTargetDeg)                            // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
          OR (fSoftLoDeg <> fSoftLoDeg) OR (fSoftHiDeg <> fSoftHiDeg)                    // 软限 NaN 判 / Soft-limit NaN tests
          OR ((fPosAct - fPosAct) <> (fPosAct - fPosAct));                                // 位置 Inf 差值自减判 / Inf test
_bCfgBad := (fSoftHiDeg <= fSoftLoDeg) OR _bNonFin;                                       // 软限几何组态闸（R151） / Soft-limit geometry gate
_bTargetBad := (fTargetDeg < (0.0 - DL_FLOAT_EPS)) OR (fTargetDeg > (DL_FULL_TURN + DL_FLOAT_EPS));   // 目标角域闸 / Target domain gate
rtExec(CLK := bExecute);                                                                  // 执行沿，每拍必调（R228A） / Execute edge
rtReset(CLK := bReset);                                                                   // 复位沿，每拍必调 / Reset edge

(* —— 段 1：单拍量预清零（锁存量不入清单，R107） —— *)
_uInfo       := 16#0000_0000;      // 信息码每拍重算 / Info recomputed every scan
bValid       := FALSE;             // 有效位每拍预清 / Valid flag preset
nErrId       := 16#0000_0000;      // 事件码缺省无事件 / Event code default none
bError       := FALSE;             // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset
_bSolved     := FALSE;             // 软限求解标记预清 / Solvability marker preset

(* —— 段 2：复位沿 + 组态域闸 + 目标域闸 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_RspCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    IF _eState = E_DL_RspState.eFault THEN
        _eState := E_DL_RspState.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸 / Configuration gate
    _uFault := 16#0004_03B8;                                             // 故障级：旋转最短路径故障总码 / Fault-level: short-path fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_RspCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF

(* —— 段 3：规划求解（执行沿受理；归一化走条件加减 + 迭代守卫） —— *)
IF (NOT _bFault) AND rtExec.Q THEN                                       // 执行上升沿（当拍量） / Execute rising edge
    IF _bTargetBad THEN
        _uFault := 16#0004_03B8;                                         // 故障级：目标角越域 / Fault-level: target out of domain
        _bFault := TRUE;
        bError  := TRUE;                                                 // 故障标志同拍置位（R45 配对） / Error flag set same scan
        _eCause := E_DL_RspCause.eTargetBad;                             // 归因：目标越域 / Cause: target domain
    ELSE
        _fNorm := fPosAct;                                               // 归一化起点 / Normalisation start
        _nIter := 0;                                                     // 迭代计数清零 / Clear iteration counter
        _bIterBad := FALSE;                                              // 迭代守卫标记清 / Clear guard marker
        WHILE (_fNorm >= DL_FULL_TURN) AND (_nIter < DL_ITER_MAX) DO     // 条件减（禁 MOD，R10/R48） / Conditional subtraction, no modulo
            _fNorm := _fNorm - DL_FULL_TURN;
            _nIter := _nIter + 1;                                        // 守卫计数递增 / Guard increment
        END_WHILE
        WHILE (_fNorm < 0.0) AND (_nIter < DL_ITER_MAX) DO               // 条件加（禁 MOD） / Conditional addition, no modulo
            _fNorm := _fNorm + DL_FULL_TURN;
            _nIter := _nIter + 1;
        END_WHILE
        IF _nIter >= DL_ITER_MAX THEN                                    // 超守卫：置码跳出，不死循环 / Guard tripped
            _bIterBad := TRUE;
        END_IF
        IF _bIterBad THEN
            _uFault := 16#0004_03B8;                                     // 故障级：归一化超迭代守卫 / Fault-level: iteration guard
            _bFault := TRUE;
            bError  := TRUE;
            _eCause := E_DL_RspCause.eIterGuard;                         // 归因：迭代守卫 / Cause: iteration guard
        ELSE
            _fDiff := fTargetDeg - _fNorm;                               // 最小转角候选 / Candidate shortest angle
            IF _fDiff > (DL_HALF_TURN + DL_FLOAT_EPS) THEN               // 超半圈 → 反向走短路径 / Beyond half turn, go the other way
                _fDiff := _fDiff - DL_FULL_TURN;
            ELSIF _fDiff < (0.0 - DL_HALF_TURN - DL_FLOAT_EPS) THEN      // 低于负半圈 → 正向走短路径 / Below minus half turn, go positive
                _fDiff := _fDiff + DL_FULL_TURN;
            END_IF
            IF bCwOnly AND (_fDiff < 0.0) THEN                           // 单向模式：负向改成正向等价角 / CW-only forces the positive equivalent
                _fDiff := _fDiff + DL_FULL_TURN;
            END_IF
            _fAbsCand := fPosAct + _fDiff;                               // 首选圈绝对目标位 / Preferred absolute target
            IF (_fAbsCand >= fSoftLoDeg) AND (_fAbsCand <= fSoftHiDeg) THEN
                _bSolved := TRUE;                                        // 首选圈即在软限内 / Preferred turn inside limits
            ELSE
                _fAbsCand := _fAbsCand + DL_FULL_TURN;                   // 尝试另一圈（正向一圈） / Try the next turn, positive
                IF (_fAbsCand >= fSoftLoDeg) AND (_fAbsCand <= fSoftHiDeg) THEN
                    _fDiff := _fDiff + DL_FULL_TURN;                     // 转角同步修正，保证目标位与转角自洽 / Keep angle and target consistent
                    _bSolved := TRUE;
                ELSE
                    _fAbsCand := _fAbsCand - 2.0 * DL_FULL_TURN;         // 再试另一侧（负向一圈） / Try the other turn, negative
                    IF (_fAbsCand >= fSoftLoDeg) AND (_fAbsCand <= fSoftHiDeg) THEN
                        _fDiff := _fDiff - DL_FULL_TURN;
                        _bSolved := TRUE;
                    END_IF
                END_IF
            END_IF
            IF NOT _bSolved THEN                                         // 两圈均越限：拒绝并置码 / No turn inside limits
                _uFault := 16#0004_03B8;                                 // 故障级：软限无解 / Fault-level: no solution inside limits
                _bFault := TRUE;
                bError  := TRUE;
                _eCause := E_DL_RspCause.eSoftLimit;                     // 归因：软限无解 / Cause: soft-limit no solution
            ELSE
                _fTmp := _fAbsCand;                                      // 圈号求解起点 / Turn solving start
                _nTurnCalc := 0;
                _bTurnBad := FALSE;
                WHILE (_fTmp >= DL_FULL_TURN) AND (_nTurnCalc < DL_TURN_MAX) DO
                    _fTmp := _fTmp - DL_FULL_TURN;                       // 整除点不跳圈（向量 A 已核） / Exact multiples do not skip a turn
                    _nTurnCalc := _nTurnCalc + 1;
                END_WHILE
                WHILE (_fTmp < 0.0) AND (_nTurnCalc > (0 - DL_TURN_MAX)) DO
                    _fTmp := _fTmp + DL_FULL_TURN;
                    _nTurnCalc := _nTurnCalc - 1;
                END_WHILE
                IF (_nTurnCalc >= DL_TURN_MAX) OR (_nTurnCalc <= (0 - DL_TURN_MAX)) THEN
                    _bTurnBad := TRUE;                                   // 圈号超守卫上限 / Turn guard tripped
                END_IF
                IF _bTurnBad THEN
                    _uFault := 16#0004_03B8;                             // 故障级：圈号超守卫 / Fault-level: turn guard
                    _bFault := TRUE;
                    bError  := TRUE;
                    _eCause := E_DL_RspCause.eTurnGuard;                 // 归因：圈号守卫 / Cause: turn guard
                ELSE
                    fTargetAbs := _fAbsCand;                             // 绝对目标位定稿 / Final absolute target
                    nTurnIndex := _nTurnCalc;                            // 圈号定稿 / Final turn index
                    IF _fDiff >= 0.0 THEN
                        bShortestCw := TRUE;                             // 正向（含恰好 ±180° 的正优先约定） / CW, includes the exact-half-turn convention
                    ELSE
                        bShortestCw := FALSE;                            // 反向 / CCW
                    END_IF
                    bValid := TRUE;                                      // 规划有效 / Plan valid
                    _uInfo := 16#0004_04B8;                              // 信息级：规划成功 / Info: plan succeeded
                END_IF
            END_IF
        END_IF
    END_IF
END_IF

(* —— 段 4：故障解除式（R240 全当拍量） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bTargetBad) AND _bSolved THEN   // 分支 1：本次复位当拍已求得软限内解 / Branch 1, solved in this very scan
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_RspCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bTargetBad)                        // 分支 2：目标角本身落在软限区间内（越限条件已解除，当拍量） / Branch 2, target angle inside limits
   AND (fTargetDeg >= fSoftLoDeg) AND (fTargetDeg <= fSoftHiDeg) THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_RspCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_RspState.eFault) THEN
    _eState := E_DL_RspState.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_RspState.eIdle:
    IF rtExec.Q AND (NOT _bFault) THEN                                   // 出口 1：收到执行沿（结果由段 3 就地算出） / Execute edge received
        _eState := E_DL_RspState.eRun;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_RspState.eFault;
    END_IF

E_DL_RspState.eRun:
    IF rtReset.Q THEN                                                    // 出口 1：复位回空闲（前置消失，R98） / Reset returns idle
        _eState := E_DL_RspState.eIdle;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_RspState.eFault;
    END_IF

E_DL_RspState.eFault:
    ;                                                                     // 故障相：仅段 4 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0004_03B8;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_RspCause.ePhaseBad;                                  // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_RspState.eFault;

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放；故障相安全侧） —— *)
IF _bFault THEN
    bValid      := FALSE;                                                // 故障相规划无效 / Plan invalid in fault
    bShortestCw := FALSE;                                                // 故障相不宣称转向（保守：不给方向建议） / No direction advice in fault
    fTargetAbs  := fPosAct;                                              // 故障相目标位回落到当前位置（零位移，安全侧） / Target falls back to current position
    nTurnIndex  := 0;                                                    // 故障相圈号清零 / Turn index zeroed in fault
END_IF
IF _bFault THEN
    nErrId := _uFault;                                                   // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                    // 信息码 / Info code
END_IF
bError := _bFault;                                                       // 故障标志与锁存同源（名实双出口，R191） / Flag from latch
eState := _eState;                                                       // 状态出口 / State outlet
eCause := _eCause;                                                       // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
