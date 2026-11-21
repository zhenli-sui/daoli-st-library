(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ReactorYearWinClean
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 反应釜年度清洗窗与批次投料闸门。清洗窗内 CIP 完成
 *                         电平置「本窗已洗」锁存；窗内未洗或过窗未洗时投料
 *                         申请一律拒绝（批次闸门，拒绝成因独立分码 R190）；
 *                         窗关闭沿若整窗未洗 → bCleanOverdue 告警电平保持至
 *                         下窗。与 CipCleaningSeq（清洗执行顺控）分工：本件
 *                         职责在「门」不在「洗」——只判过窗未洗禁投料。
 * 来源标签 (Origin)     : ROADMAP §16.6 R11 池（L733），自研 clean-room
 * 边界语义 (Boundary)   : ① 「本窗已洗」锁存随窗开启沿清零（每窗独立判定）；
 *                         ② 窗电平输入为布尔域，无浮点量（无 NaN/除零域）；
 *                         ③ 窗内申请拒绝不锁存故障（业务拒绝态）；
 *                         ④ 过窗未洗告警清除路径 = 下窗开启沿或复位沿（头
 *                         注释声明）。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 闸门出口强制 FALSE（拒绝
 *                         投料安全侧）；eFault 相 → 闸门 FALSE + bError。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 无浮点域 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 窗内 + CIP 完成电平 → _bCleaned=TRUE，窗内申请
 *                         → bBatchAllow=TRUE；
 *                         V2 窗内未洗申请 → bBatchBlocked=TRUE，eDeny=eNotCleaned；
 *                         V3 窗关沿整窗未洗 → bCleanOverdue=TRUE 保持至下窗
 *                         开启沿清零。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 2 · 序号 8）
 *==============================================================================*)
TYPE E_DL_RycDeny :
(
    eNone       := 0,                        (* 无拒绝（已放行或无申请） / No deny *)
    eNotCleaned := 1,                        (* 窗内未洗禁投 / Not cleaned this window *)
    eOverdue    := 2                         (* 过窗未洗禁投（告警期） / Overdue not cleaned *)
);
END_TYPE

TYPE E_DL_RycState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eGate  := 10,                            (* 闸门判定运行 / Gate run *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_RycCause :
(
    eNone     := 0,                          (* 无故障成因 / No cause *)
    ePhaseBad := 3                           (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_ReactorYearWinClean
VAR_INPUT
    bInCleanWin : BOOL := FALSE;             (* 年度清洗窗电平（上层窗判定供给）[-] / Clean-window level *)
    bCleanDone  : BOOL := FALSE;             (* CIP 清洗完成电平（CipCleaningSeq 供给）[-] / Clean-done level *)
    bBatchReq   : BOOL := FALSE;             (* 投料申请电平 [-] / Batch request *)
    bEnable     : BOOL := TRUE;              (* 使能 [-] / Enable *)
    bReset      : BOOL := FALSE;             (* 复位命令，上升沿清全部 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bBatchAllow  : BOOL;                     (* 投料放行电平（申请期实时）[-] / Batch allow level *)
    bBatchBlocked: BOOL;                     (* 投料拒绝电平（申请期实时）[-] / Batch blocked level *)
    eDeny        : E_DL_RycDeny;             (* 拒绝成因（信息级逐拍重算，R189） / Deny cause *)
    bCleanOverdue: BOOL;                     (* 过窗未洗告警电平（下窗开启沿或复位沿清，R152） / Overdue alarm *)
    nCleanWins   : UDINT;                    (* 累计完成清洗的窗数 [窗] / Cleaned window count *)
    eState       : E_DL_RycState;            (* 状态出口 / State outlet *)
    eCause       : E_DL_RycCause;            (* 故障成因出口 / Fault cause outlet *)
    bError       : BOOL;                     (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState    : E_DL_RycState := E_DL_RycState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause    : E_DL_RycCause := E_DL_RycCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtWinOpen  : R_TRIG;                     (* 窗开启沿实例，段 0 无条件调用 / Window-open edge *)
    rtWinClose : R_TRIG;                     (* 窗关闭沿实例，段 0 无条件调用 / Window-close edge *)
    rtReset    : R_TRIG;                     (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bCleaned  : BOOL;                       (* 本窗已洗锁存 [-] / Cleaned-this-window latch *)
    _nWins     : UDINT;                      (* 完成清洗窗数锁存 [窗] / Cleaned-window count *)
    _bFault    : BOOL;                       (* 故障锁存位 / Latched fault bit *)
END_VAR

(* —— 段 0：沿实例无条件刷新（R228A；纯布尔域无浮点组态闸） —— *)
rtWinOpen(CLK := bInCleanWin);               (* 窗开启沿每拍必调 / Window-open edge every scan *)
rtWinClose(CLK := NOT bInCleanWin);          (* 窗关闭沿每拍必调 / Window-close edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)

(* —— 段 1：单拍量预清零（R107） —— *)
bBatchAllow := FALSE;                        (* 放行电平预清（判定分支覆盖） / Allow preset *)
bBatchBlocked := FALSE;                      (* 拒绝电平预清 / Blocked preset *)
eDeny := E_DL_RycDeny.eNone;                 (* 拒绝成因预清（信息级逐拍重算） / Deny preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清已洗锁存 + 清告警 + 清窗数 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_RycCause.eNone;          (* 清成因 / Clear cause *)
    _bCleaned := FALSE;                      (* 清已洗锁存 / Clear cleaned latch *)
    bCleanOverdue := FALSE;                  (* 清过窗告警（复位沿清除路径之一，边界④） / Clear overdue *)
    _nWins := 0;                             (* 清窗数 / Clear count *)
    _eState := E_DL_RycState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_RycState.eIdle:                     (* 待机相 / Idle *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_RycState.eGate;  (* 进入闸门 / Enter gate *)
        END_IF
    E_DL_RycState.eGate:                     (* 闸门相：窗沿 + 已洗锁存 + 投料判定 / Gate *)
        IF NOT bEnable THEN
            _eState := E_DL_RycState.eIdle;  (* 失能回待机 / Back to idle *)
        ELSE
            IF rtWinOpen.Q THEN              (* 窗开启沿：本窗判定重置（边界①） + 上窗告警清除路径 / On window open *)
                _bCleaned := FALSE;          (* 清本窗已洗 / Reset cleaned latch *)
                bCleanOverdue := FALSE;      (* 清过窗告警（下窗开启沿清除路径，边界④） / Clear overdue *)
            END_IF
            IF bInCleanWin AND bCleanDone THEN
                _bCleaned := TRUE;           (* 窗内 CIP 完成：置已洗锁存（电平置位锁存语义） / Set cleaned latch *)
            END_IF
            IF rtWinClose.Q AND (NOT _bCleaned) THEN   (* 窗关沿整窗未洗：告警置位 / Overdue on close *)
                bCleanOverdue := TRUE;       (* 过窗未洗告警（保持至下窗/复位，R152） / Overdue alarm *)
            END_IF
            IF rtWinClose.Q AND _bCleaned THEN
                _nWins := _nWins + 1;        (* 完成清洗窗数（UDINT 回绕工程安全） / Count cleaned window *)
            END_IF
            IF bBatchReq THEN                (* 申请期实时判定（业务拒绝态不锁存故障，边界③） / On request *)
                IF bInCleanWin AND (NOT _bCleaned) THEN
                    bBatchBlocked := TRUE;   (* 窗内未洗拒绝 / Blocked *)
                    eDeny := E_DL_RycDeny.eNotCleaned;   (* 成因：未洗（独立成员，R190） / Cause: not cleaned *)
                ELSIF bCleanOverdue THEN
                    bBatchBlocked := TRUE;   (* 过窗未洗期拒绝 / Blocked *)
                    eDeny := E_DL_RycDeny.eOverdue;   (* 成因：过窗（独立成员） / Cause: overdue *)
                ELSE
                    bBatchAllow := TRUE;     (* 放行 / Allow *)
                END_IF
            END_IF
        END_IF
    E_DL_RycState.eFault:                    (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_RycState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_RycCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
nCleanWins := _nWins;                        (* 窗数出口 / Count outlet *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
