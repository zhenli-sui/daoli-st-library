(*==============================================================================
 * 组件名称 (Component)  : FB_DL_NgBinDosing
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : NG 料返投称重定量。粗投/精投两相：粗投阀至「目标 -
 *                         粗投提前量」切精投，精投至「目标 - 提前关断量」双
 *                         阀关，稳定窗到时结算投料量并按过冲自学习修正提前
 *                         关断量（bLearnDisable = TRUE 时学习冻结禁用——学习
 *                         禁用组态，修正量保持人工组态值）。与 BatchDosingControl
 *                         （正向定量）分工：本件复用单料相做 NG 返投并带学习
 *                         禁用组态，方向与组态均新。
 * 来源标签 (Origin)     : ROADMAP §9.6 P2（L471），自研 clean-room
 * 边界语义 (Boundary)   : ① 提前关断量两级回退（FB32-3）：< 0 回默认 0，>
 *                         粗投提前量钳至粗投提前量；
 *                         ② 提前关断量学习域钳 [0, 粗投提前量]（防发散）；
 *                         ③ 结算除法无涉（纯加减乘）；权重 NaN 拍冻结推进；
 *                         ④ 组态闸：目标/提前量正域 + 粗投提前量 < 目标 → 故障。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 双阀输出强制 FALSE（阀类
 *                         出口失能必须收敛，投料中止回待机）；eFault 相 → 阀
 *                         全关 + bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零无涉/NaN 冻结/两级回退/组态闸 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 TON/R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 目标 5.0、粗投提前 0.8、提前关断 0.1：粗投至
 *                         4.2 切精投、至 4.9 双关，稳定后结算 fDosedWt；
 *                         V2 结算过冲 +0.15 且学习未禁用 → fPreactOut 增至
 *                         0.25（钳 [0, 0.8]）；
 *                         V3 bLearnDisable=TRUE → 过冲不修正（学习冻结）。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 4 · 序号 19）
 *==============================================================================*)
TYPE E_DL_NbdState :
(
    eIdle   := 0,                            (* 待机（阀全关） / Idle *)
    eCoarse := 10,                           (* 粗投相 / Coarse dosing *)
    eFine   := 20,                           (* 精投相 / Fine dosing *)
    eSettle := 30,                           (* 稳定结算相 / Settling *)
    eFault  := 90                            (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_NbdCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：目标/提前量越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_NgBinDosing
VAR_INPUT
    fWtNow        : LREAL := 0.0;            (* 秤实时重量 [kg] / Scale weight now *)
    fTarget       : LREAL := 5.0;            (* 目标投料量，域 > eps [kg] / Target dose *)
    fCourseDelta  : LREAL := 0.8;            (* 粗投提前量（粗/精切换点余量），域 > 0 且 < fTarget [kg] / Coarse switchover delta *)
    fPreactSet    : LREAL := 0.1;            (* 提前关断量人工组态值，域 [0, fCourseDelta] [kg] / Manual preact *)
    fLearnGain    : LREAL := 1.0;            (* 学习增益，域 (0, 1] [-] / Learn gain *)
    tSettle       : TIME := T#2S;            (* 稳定窗时长，域 > T#0S [ms] / Settle time *)
    bDoseReq      : BOOL := FALSE;           (* 投料申请沿 [-] / Dose request edge *)
    bLearnDisable : BOOL := FALSE;           (* 学习禁用组态（TRUE 冻结提前量学习）[-] / Learn disable config *)
    bEnable       : BOOL := TRUE;            (* 使能 [-] / Enable *)
    bReset        : BOOL := FALSE;           (* 复位命令，上升沿清全部（含学习量）[-] / Reset command *)
END_VAR
VAR_OUTPUT
    bCoarseValve  : BOOL;                    (* 粗投阀输出 [-] / Coarse valve outlet *)
    bFineValve    : BOOL;                    (* 精投阀输出 [-] / Fine valve outlet *)
    bDoseDone     : BOOL;                    (* 投料完成单拍位 [-] / Dose-done pulse *)
    fDosedWt      : LREAL;                   (* 本次结算投料量 [kg] / Settled dose weight *)
    fPreactOut    : LREAL;                   (* 当前生效提前关断量（学习后）[kg] / Effective preact *)
    nDoseCnt      : UDINT;                   (* 累计投料次数 [次] / Dose count *)
    eState        : E_DL_NbdState;           (* 状态出口 / State outlet *)
    eCause        : E_DL_NbdCause;           (* 故障成因出口 / Fault cause outlet *)
    bError        : BOOL;                    (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_NbdState := E_DL_NbdState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_NbdCause := E_DL_NbdCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtReq     : R_TRIG;                      (* 申请沿实例，段 0 无条件调用 / Request edge instance *)
    rtReset   : R_TRIG;                      (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonSettle : TON;                         (* 稳定窗计时（相驻留使能，R145），段 0 无条件调用 / Settle timer *)
    _fWtStart : LREAL;                       (* 本次投料起点重量锁存 [kg] / Start weight latch *)
    _fPreact  : LREAL := 0.1;                (* 提前关断量锁存（学习量，域 [0, fCourseDelta]）[kg] / Preact latch *)
    _fDosed   : LREAL;                       (* 结算投料量派生 [kg] / Settled dose derived *)
    _bDone    : BOOL;                        (* 完成内部量（两段式脉冲，R189）[-] / Done work *)
    _nDoses   : UDINT;                       (* 投料计数锁存 [次] / Dose count latch *)
    _bWtBad   : BOOL;                        (* 重量非有限当拍量 [-] / Non-finite weight *)
    _bFault   : BOOL;                        (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                        (* 组态非法当拍量 / Illegal config this scan *)
END_VAR
VAR CONSTANT
    DL_NBD_EPS : LREAL := 1.0E-9;            (* 目标判零容差 [kg] / Target epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (fTarget <= DL_NBD_EPS) OR (fCourseDelta <= 0.0) OR (fCourseDelta >= fTarget)
            OR (fLearnGain <= 0.0) OR (fLearnGain > 1.0) OR (tSettle <= T#0S);   (* 组态闸（R151 全引脚 + 域序） / Config gate *)
rtReq(CLK := bDoseReq);                      (* 申请沿每拍必调 / Request edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
_bWtBad := (fWtNow <> fWtNow) OR ((fWtNow - fWtNow) <> (fWtNow - fWtNow));   (* 重量 NaN 自反 + Inf 差判 / Non-finite weight *)
tonSettle(IN := (_eState = E_DL_NbdState.eSettle), PT := tSettle);   (* 稳定窗：纯相驻留使能（R145） / Settle timer, phase-residency *)
IF _fPreact < 0.0 THEN                       (* 两级回退一级：负值回 0（FB32-3） / Preact fallback lower *)
    _fPreact := 0.0;                         (* 回默认下界 / Fallback to zero *)
ELSIF _fPreact > fCourseDelta THEN
    _fPreact := fCourseDelta;                (* 两级回退二级：钳粗投提前量（同拍钳定行） / Clamp to coarse delta *)
END_IF

(* —— 段 1：单拍量预清零（R107） —— *)
_fDosed := 0.0;                              (* 结算量预清（结算拍派生，R285） / Settled preset *)
_bDone := FALSE;                             (* 完成内部量预清，唯一分支置位 / Done work preset *)
bDoseDone := FALSE;                          (* 完成出口预清 / Done outlet preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清学习量 + 清计数 + 清结算出口 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_NbdCause.eNone;          (* 清成因 / Clear cause *)
    _fPreact := fPreactSet;                  (* 学习量回人工组态值（两级回退同拍适用） / Preact back to manual *)
    _nDoses := 0;                            (* 清投料计数 / Clear count *)
    fDosedWt := 0.0;                         (* 清结算出口 / Clear settled outlet *)
    fPreactOut := _fPreact;                  (* 提前量出口回组态 / Preact outlet *)
    _eState := E_DL_NbdState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_NbdCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_NbdState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_NbdState.eIdle:                     (* 待机相 / Idle *)
        IF rtReq.Q AND bEnable AND (NOT _bFault) AND (NOT _bWtBad) THEN
            _fWtStart := fWtNow;             (* 锁存起点重量 / Latch start weight *)
            _eState := E_DL_NbdState.eCoarse;   (* 进入粗投 / Enter coarse *)
        END_IF
    E_DL_NbdState.eCoarse:                   (* 粗投相：至切换点切精投 / Coarse *)
        IF NOT bEnable THEN
            _eState := E_DL_NbdState.eIdle;  (* 失能中止回待机 / Abort to idle *)
        ELSIF NOT _bWtBad THEN
            IF (fWtNow - _fWtStart) >= (fTarget - fCourseDelta) THEN
                _eState := E_DL_NbdState.eFine;   (* 达切换点进精投 / Switchover to fine *)
            END_IF
        END_IF                               (* 重量坏值拍：冻结推进（边界③） / Bad weight: freeze *)
    E_DL_NbdState.eFine:                     (* 精投相：至提前关断点双关 / Fine *)
        IF NOT bEnable THEN
            _eState := E_DL_NbdState.eIdle;  (* 失能中止回待机 / Abort to idle *)
        ELSIF NOT _bWtBad THEN
            IF (fWtNow - _fWtStart) >= (fTarget - _fPreact) THEN
                _eState := E_DL_NbdState.eSettle;   (* 达关断点进稳定窗 / To settle *)
            END_IF
        END_IF
    E_DL_NbdState.eSettle:                   (* 稳定结算相：窗到结算与学习 / Settle *)
        IF NOT bEnable THEN
            _eState := E_DL_NbdState.eIdle;  (* 失能中止回待机 / Abort to idle *)
        ELSIF tonSettle.Q THEN               (* 稳定窗到：结算 + 学习（过渡态三段：本拍发单拍/下拍预清，R80） / Settle expired *)
            _fDosed := fWtNow - _fWtStart;   (* 结算投料量（减法无除零） / Settle dose *)
            fDosedWt := _fDosed;             (* 结算出口 / Settled outlet *)
            IF (NOT bLearnDisable) AND (NOT _bWtBad) THEN   (* 学习未禁用才修正（学习禁用组态语义，R191 声明） / Learn when enabled *)
                _fPreact := _fPreact + fLearnGain * (_fDosed - fTarget);   (* 过冲学习修正（乘法无除零） / Overshoot learn *)
                IF _fPreact < 0.0 THEN
                    _fPreact := 0.0;         (* 学习域钳下界（边界②） / Learn clamp lower *)
                ELSIF _fPreact > fCourseDelta THEN
                    _fPreact := fCourseDelta;   (* 学习域钳上界 / Learn clamp upper *)
                END_IF
            END_IF
            fPreactOut := _fPreact;          (* 提前量出口刷新 / Preact outlet *)
            _bDone := TRUE;                  (* 完成内部量置位（R189 两段式） / Internal done set *)
            _nDoses := _nDoses + 1;          (* 投料计数（UDINT 回绕工程安全） / Count dose *)
            _eState := E_DL_NbdState.eIdle;  (* 回待机 / Back to idle *)
        END_IF
    E_DL_NbdState.eFault:                    (* 故障相：阀全关（段 5 收敛），仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_NbdState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_NbdCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（阀与相位同源，R191） —— *)
bCoarseValve := (_eState = E_DL_NbdState.eCoarse) AND bEnable AND (NOT _bFault);   (* 粗投阀出口 / Coarse valve outlet *)
bFineValve := (_eState = E_DL_NbdState.eFine) AND bEnable AND (NOT _bFault);       (* 精投阀出口 / Fine valve outlet *)
bDoseDone := _bDone;                         (* 完成单拍出口 / Done outlet *)
nDoseCnt := _nDoses;                         (* 投料计数出口 / Dose count outlet *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
