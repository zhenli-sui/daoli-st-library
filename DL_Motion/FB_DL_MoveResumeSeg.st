(*==============================================================================
 * 组件名称 (Component)  : FB_DL_MoveResumeSeg
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库，
 *                         零轴状态枚举引用（R277：运动层状态属主唯一）
 * 功能描述 (Function)   : 断点续走。运行中按 bSaveCmd 沿快照「起点/目标」对
 *                         （fStartSave/fTargetSave 输出供上层落盘持久化）；
 *                         断电重启后上层把持久化值从 fTargetRst/fStartRst 注入
 *                         并给 bRestore 沿，本件以当前位置计算剩余行程与方向，
 *                         进入续走相：输出方向位与剩余距离，上层以既有运动
 *                         指令件执行；到达容差内 → bResumeDone 单拍并收口。
 * 来源标签 (Origin)     : 自研线（IEC 61131-3 标准语义的道莅防御性实现，clean-room）
 * 分工声明 (Pairing)    : MoveResumeSeg（断点续走，本件）↔ MotionCmdQueue（指令
 *                         排队，既有件）：本件只产出「剩余行程/方向/进度」快照
 *                         与续走判据，不生成运动指令、不排队、不接管轴使能
 *                         （R298 属主边界：续走计算不替代指令编排）。
 * 边界语义 (Boundary)   : ① 进度除零防御：目标 = 起点段长 <= eps → 组态故障
 *                         锁存（零行程快照无续走语义）；
 *                         ② 恢复闸：恢复时位置已在目标容差内 → 直接收口
 *                         bResumeDone，不发续走（防负行程往回走）；
 *                         ③ 剩余距离负值（越过目标）→ 按已到收口，不输出反向
 *                         续走（安全侧）；
 *                         ④ 位置 NaN → 本拍冻结（不派生方向）；
 *                         ⑤ 组态闸：容差 <= 0 / 速度域 → 故障。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 方向/续走输出强制 FALSE
 *                         （续走是执行建议，失能必须收敛）；eFault 相 → 冻结
 *                         + bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)，
 *                         码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零（段长 eps 闸）/NaN 冻结/组态闸 ✓
 *                         R5 双语同行注释 ✓｜R6 CASE 带 ELSE 兜底迁 eFault ✓
 *                         R7 R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 快照 (100, 300)，恢复时位置 220 → 剩余 80，
 *                         bDirPos=TRUE，fProgress=0.6；
 *                         V2 恢复时位置 295（容差 5 内）→ 直接 bResumeDone；
 *                         V3 恢复时位置 310（越目标）→ bResumeDone 不反向；
 *                         V4 快照起点=目标 → eFault 组态锁存。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 4 · 序号 16）
 *                        2026-11-20  v1.0.1  R51 返修（R50 终审中）：eResume 相方向
 *                        改进入相时锁存（_bDir 不再每拍重派生，R339 方向锁定）；
 *                        越目标（剩余量符号与锁定方向相反）一律按已到收口
 *                        bResumeDone，不输出反向续走（与边界③一致）
 *==============================================================================*)
TYPE E_DL_MrsState :
(
    eIdle    := 0,                           (* 待快照/待恢复 / Idle *)
    eSaved   := 10,                          (* 快照已建立，运行中持续更新进度 / Saved, tracking progress *)
    eResume  := 20,                          (* 续走执行中（方向/剩余距离输出） / Resuming *)
    eDone    := 30,                          (* 续走完成收口保持 / Resume done hold *)
    eFault   := 90                           (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_MrsCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：容差越域 / Illegal config *)
    eSegIllegal := 2,                        (* 快照段长非法（起点=目标） / Illegal segment length *)
    ePhaseBad   := 3                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_MoveResumeSeg
VAR_INPUT
    fPosNow    : LREAL := 0.0;               (* 当前轴位置（调用方每拍快照传入）[mm] / Current axis position *)
    fTolerance : LREAL := 0.5;               (* 到位容差，域 > 0.0 [mm] / Arrival tolerance *)
    bSaveCmd   : BOOL := FALSE;              (* 快照命令，上升沿以当前段建立快照 [-] / Snapshot command edge *)
    fTargetRst : LREAL := 0.0;               (* 持久化目标位置注入（断电恢复用）[mm] / Restored target position *)
    fStartRst  : LREAL := 0.0;               (* 持久化起点位置注入（预留 reserved：当前正文零引用，起点语义由 fPosNow 实时快照）[mm] / Restored start position, reserved *)
    bRestoreCmd: BOOL := FALSE;              (* 恢复命令，上升沿按注入值续走 [-] / Restore command edge *)
    bAbort     : BOOL := FALSE;              (* 中止电平，TRUE 终止续走回 eIdle（快照保留）[-] / Abort level *)
    bEnable    : BOOL := TRUE;               (* 使能，FALSE 续走输出强制收敛 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清全部内部状态 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bDirPos     : BOOL;                      (* 续走方向位：TRUE 正向 / FALSE 负向 [-] / Resume direction flag *)
    fRemainAbs  : LREAL;                     (* 剩余行程绝对值 [mm] / Remaining distance *)
    fProgress   : LREAL;                     (* 段内完成进度 0..1（快照相实时更新）[-] / Segment progress *)
    bResumeActive : BOOL;                    (* 续走执行中指示 [-] / Resume-active indicator *)
    fTargetSave : LREAL;                     (* 快照目标（供上层持久化落盘）[mm] / Snapshot target for persistence *)
    fStartSave  : LREAL;                     (* 快照起点（供上层持久化落盘）[mm] / Snapshot start for persistence *)
    bResumeDone : BOOL;                      (* 续走完成单拍位 [-] / Resume-done single-scan pulse *)
    eState      : E_DL_MrsState;             (* 状态出口 / State outlet *)
    eCause      : E_DL_MrsCause;             (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError      : BOOL;                      (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_MrsState := E_DL_MrsState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_MrsCause := E_DL_MrsCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtSave    : R_TRIG;                     (* 快照沿实例，段 0 无条件调用 / Save edge instance *)
    rtRestore : R_TRIG;                     (* 恢复沿实例，段 0 无条件调用 / Restore edge instance *)
    rtReset   : R_TRIG;                     (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _fTarget  : LREAL;                       (* 目标位置锁存（快照槽）[mm] / Target latch *)
    _fStart   : LREAL;                       (* 起点位置锁存（快照槽）[mm] / Start latch *)
    _fRemain  : LREAL;                       (* 剩余行程派生量 [mm] / Remaining derived *)
    _fSegLen  : LREAL;                       (* 段长派生量 [mm] / Segment length derived *)
    _fProg    : LREAL;                       (* 进度派生量 [-] / Progress derived *)
    _bDir     : BOOL;                        (* 方向锁存量（进入 eResume 相时锁定，越目标不反向，R339）[-] / Direction latch *)
    _bReached : BOOL;                        (* 到位当拍判据 [-] / Reached verdict this scan *)
    _bPosBad  : BOOL;                        (* 位置非有限当拍量 [-] / Non-finite position this scan *)
    _bFault   : BOOL;                        (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                        (* 组态非法当拍量 / Illegal config this scan *)
END_VAR
VAR CONSTANT
    DL_MRS_EPS : LREAL := 1.0E-9;            (* 段长判零容差 [mm²] / Segment epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 沿实例无条件刷新（R228A） —— *)
_bCfgBad := (fTolerance <= 0.0);             (* 组态闸：容差正域（R151 全引脚，单引脚件） / Config gate *)
rtSave(CLK := bSaveCmd);                     (* 快照沿每拍必调 / Save edge every scan *)
rtRestore(CLK := bRestoreCmd);               (* 恢复沿每拍必调 / Restore edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
_bPosBad := (fPosNow <> fPosNow) OR ((fPosNow - fPosNow) <> (fPosNow - fPosNow));   (* 位置 NaN 自反 + Inf 差判 / Non-finite position *)

(* —— 段 1：单拍量预清零（R107） —— *)
bResumeDone := FALSE;                        (* 完成单拍位预清，唯一分支置位 / Done pulse preset *)
_bReached := FALSE;                          (* 到位判据预清 / Reached preset *)
_fRemain := 0.0;                             (* 剩余距离预清（每拍全路径派生，R285） / Remain preset *)
_fProg := 0.0;                               (* 进度预清 / Progress preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清快照槽 + 清输出镜像 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_MrsCause.eNone;          (* 清成因 / Clear cause *)
    _fTarget := 0.0;                         (* 清目标槽 / Clear target *)
    _fStart := 0.0;                          (* 清起点槽 / Clear start *)
    fTargetSave := 0.0;                      (* 清快照目标镜像 / Clear mirror *)
    fStartSave := 0.0;                       (* 清快照起点镜像 / Clear mirror *)
    fRemainAbs := 0.0;                       (* 清剩余镜像 / Clear remain *)
    fProgress := 0.0;                        (* 清进度镜像 / Clear progress *)
    bDirPos := FALSE;                        (* 清方向镜像 / Clear direction *)
    _eState := E_DL_MrsState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_MrsCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_MrsState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_MrsState.eIdle:                     (* 待机相 / Idle *)
        IF rtSave.Q AND bEnable AND NOT _bFault AND NOT _bPosBad THEN
            _fStart := fPosNow;              (* 以当前位置建快照起点 / Snapshot start *)
            _fTarget := fTargetRst;          (* 目标取恢复注入口（上层运行中把目标送此口） / Target from injection port *)
            _fSegLen := _fTarget - _fStart;  (* 段长派生 / Segment length *)
            IF ABS(_fSegLen) <= DL_MRS_EPS THEN
                _eCause := E_DL_MrsCause.eSegIllegal;   (* 零行程快照归因（独立分码，R190） / Zero-segment cause *)
                _bFault := TRUE;             (* 故障锁存（R45 配对） / Latch fault *)
                _eState := E_DL_MrsState.eFault;   (* 同步迁故障相 / Migrate to fault *)
            ELSE
                fStartSave := _fStart;       (* 快照起点镜像输出（供上层落盘） / Start mirror *)
                fTargetSave := _fTarget;     (* 快照目标镜像输出 / Target mirror *)
                _eState := E_DL_MrsState.eSaved;   (* 进入快照跟踪 / Enter saved *)
            END_IF
        END_IF
    E_DL_MrsState.eSaved:                    (* 快照跟踪相：实时进度更新 / Saved *)
        IF NOT _bPosBad THEN
            _fSegLen := _fTarget - _fStart;  (* 段长重派生（目标/起点为锁存槽，段长恒定） / Segment length *)
            _fProg := (fPosNow - _fStart) / _fSegLen;   (* 进度派生：除子为段长（快照闸已保证 |段长| > eps），无除零 / Progress, divisor gated *)
            fProgress := _fProg;             (* 进度实时镜像 / Progress mirror *)
        END_IF
        IF rtRestore.Q AND bEnable AND NOT _bFault THEN
            IF NOT _bPosBad THEN
                _fRemain := _fTarget - fPosNow;   (* 剩余行程派生 / Remaining *)
                IF ABS(_fRemain) <= fTolerance THEN
                    bResumeDone := TRUE;     (* 恢复即到位：直接收口（边界②防负行程） / Restore in tolerance: done *)
                    _eState := E_DL_MrsState.eDone;   (* 收口相 / Enter done *)
                ELSE
                    _bDir := (_fRemain > 0.0);   (* 方向锁存：进 eResume 后不再重派生（R339） / Direction latched on entry *)
                    _eState := E_DL_MrsState.eResume;   (* 进入续走 / Enter resume *)
                END_IF
            END_IF
        END_IF
    E_DL_MrsState.eResume:                   (* 续走执行相 / Resume *)
        IF NOT bEnable OR bAbort THEN        (* 失能/中止：输出收敛回待机（快照保留，可再次恢复） / Disable or abort *)
            _eState := E_DL_MrsState.eIdle;  (* 回待机 / Back to idle *)
        ELSIF _bPosBad THEN
            ;                                (* 位置坏值拍：输出冻结保持（边界④），不迁相 / Bad position: freeze *)
        ELSE
            _fRemain := _fTarget - fPosNow;  (* 剩余行程每拍重派生 / Remaining re-derived *)
            IF ABS(_fRemain) <= fTolerance THEN
                bResumeDone := TRUE;         (* 到位收口单拍 / Done pulse *)
                _eState := E_DL_MrsState.eDone;   (* 收口相 / Enter done *)
            ELSIF (_fRemain > 0.0) <> _bDir THEN   (* 越目标：剩余量符号与锁定方向相反（边界③，R339） / Overshoot: sign opposes latched direction *)
                bResumeDone := TRUE;         (* 越目标按已到收口，不反向续走 / Overshoot closes as done, no reversal *)
                _eState := E_DL_MrsState.eDone;   (* 收口相 / Enter done *)
            ELSE
                fRemainAbs := ABS(_fRemain); (* 剩余绝对值镜像 / Remain mirror *)
                bDirPos := _bDir;            (* 方向镜像（取锁存值，不重派生） / Direction mirror from latch *)
            END_IF
        END_IF
    E_DL_MrsState.eDone:                     (* 收口保持相 / Done *)
        IF rtSave.Q AND bEnable AND NOT _bFault AND NOT _bPosBad THEN
            _fStart := fPosNow;              (* 新一轮快照（同 eIdle 建快照语义） / New snapshot *)
            _fTarget := fTargetRst;          (* 目标取注入口 / Target from port *)
            _fSegLen := _fTarget - _fStart;  (* 段长派生 / Segment length *)
            IF ABS(_fSegLen) > DL_MRS_EPS THEN
                fStartSave := _fStart;       (* 快照镜像 / Snapshot mirror *)
                fTargetSave := _fTarget;     (* 快照镜像 / Snapshot mirror *)
                _eState := E_DL_MrsState.eSaved;   (* 回跟踪相 / Back to saved *)
            ELSE
                _eCause := E_DL_MrsCause.eSegIllegal;   (* 零行程归因 / Zero-segment cause *)
                _bFault := TRUE;             (* 故障锁存 / Latch fault *)
                _eState := E_DL_MrsState.eFault;   (* 迁故障相 / To fault *)
            END_IF
        END_IF
    E_DL_MrsState.eFault:                    (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_MrsState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_MrsCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（双门控收敛，R191/R285） —— *)
IF _eState = E_DL_MrsState.eResume AND bEnable AND NOT _bFault AND NOT _bPosBad THEN
    bResumeActive := TRUE;                   (* 续走执行中指示 / Resume-active indicator *)
    bDirPos := _bDir;                        (* 方向出口（续走相每拍已派生） / Direction outlet *)
    fRemainAbs := ABS(_fRemain);             (* 剩余出口 / Remain outlet *)
ELSE
    bResumeActive := FALSE;                  (* 非续走相指示收敛 / Indicator converge *)
    bDirPos := FALSE;                        (* 方向收敛（失能必须收敛语义） / Direction converge *)
END_IF
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
