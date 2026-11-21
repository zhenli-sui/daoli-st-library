(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LoopAuditTrailWindow
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 回路整定审计时间窗与变更留痕。维护窗电平内、双人
 *                         确认位同时成立时变更申请放行并留痕（计数 + 锁存）；
 *                         单人确认或窗外申请一律拒绝（独立成因分码 R190），
 *                         窗外申请计数另记审计。与 RecipeManager（参数快照）
 *                         分工：本件管维护窗内变更留痕与双人确认位，是审计
 *                         生命周期管理。
 * 来源标签 (Origin)     : ROADMAP §16.6 R11 池（L736），自研 clean-room
 * 边界语义 (Boundary)   : ① 双人确认 = 双确认位同拍同时电平（单确认位申请
 *                         拒绝成因 eOneOp 独立成员）；
 *                         ② 窗外申请不锁存故障（业务拒绝态），计数 nOutsideCnt
 *                         供审计；
 *                         ③ 留痕锁存 bTrailLatch 至复位沿（审计资产不随窗
 *                         关闭消失）；
 *                         ④ 纯布尔/整型域，无浮点量。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 放行出口 FALSE（审计放行
 *                         失能必须收敛）；eFault 相 → 放行 FALSE + bError。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 无浮点域/计数有界 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 窗内 + 双确认 + 申请沿 → bChangeAllow 单拍 +
 *                         nChangeCnt+1 + bTrailLatch=TRUE；
 *                         V2 窗内仅确认位 1 → 拒绝，eDeny=eOneOp；
 *                         V3 窗外申请沿 → 拒绝，eDeny=eOutOfWin，
 *                         nOutsideCnt+1。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 2 · 序号 9）
 *==============================================================================*)
TYPE E_DL_LawDeny :
(
    eNone     := 0,                          (* 无拒绝（已放行或无申请） / No deny *)
    eOutOfWin := 1,                          (* 窗外申请拒绝 / Outside window *)
    eOneOp    := 2                           (* 单人确认拒绝 / Single-operator deny *)
);
END_TYPE

TYPE E_DL_LawState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eAudit := 10,                            (* 审计判定运行 / Audit run *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_LawCause :
(
    eNone     := 0,                          (* 无故障成因 / No cause *)
    ePhaseBad := 3                           (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_LoopAuditTrailWindow
VAR_INPUT
    bInAuditWin : BOOL := FALSE;             (* 维护窗电平（上层窗判定供给）[-] / Audit-window level *)
    bChangeReq  : BOOL := FALSE;             (* 变更申请电平（上升沿判）[-] / Change request *)
    bConfirmOp1 : BOOL := FALSE;             (* 操作员 1 确认位电平 [-] / Operator 1 confirm *)
    bConfirmOp2 : BOOL := FALSE;             (* 操作员 2 确认位电平 [-] / Operator 2 confirm *)
    bEnable     : BOOL := TRUE;              (* 使能 [-] / Enable *)
    bReset      : BOOL := FALSE;             (* 复位命令，上升沿清全部（含留痕锁存与计数）[-] / Reset command *)
END_VAR
VAR_OUTPUT
    bChangeAllow : BOOL;                     (* 变更放行单拍位 [-] / Change-allow pulse *)
    eDeny        : E_DL_LawDeny;             (* 拒绝成因（信息级逐拍重算，R189） / Deny cause *)
    bTrailLatch  : BOOL;                     (* 窗内变更已留痕锁存（复位沿清，R152） / Trail latch *)
    nChangeCnt   : UDINT;                    (* 窗内变更留痕计数 [次] / In-window change count *)
    nOutsideCnt  : UDINT;                    (* 窗外申请计数（审计）[次] / Outside request count *)
    nDenyCnt     : UDINT;                    (* 拒绝总计数（审计）[次] / Deny count *)
    eState       : E_DL_LawState;            (* 状态出口 / State outlet *)
    eCause       : E_DL_LawCause;            (* 故障成因出口 / Fault cause outlet *)
    bError       : BOOL;                     (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState    : E_DL_LawState := E_DL_LawState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause    : E_DL_LawCause := E_DL_LawCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtReq      : R_TRIG;                     (* 申请沿实例，段 0 无条件调用 / Request edge instance *)
    rtReset    : R_TRIG;                     (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _nInWin    : UDINT;                      (* 窗内变更计数锁存 [次] / In-window count latch *)
    _nOutside  : UDINT;                      (* 窗外申请计数锁存 [次] / Outside count latch *)
    _nDeny     : UDINT;                      (* 拒绝计数锁存 [次] / Deny count latch *)
    _bTrail    : BOOL;                       (* 留痕锁存量 [-] / Trail latch work *)
    _bAllow    : BOOL;                       (* 放行单拍量 [-] / Allow pulse work *)
    _bFault    : BOOL;                       (* 故障锁存位 / Latched fault bit *)
END_VAR

(* —— 段 0：沿实例无条件刷新（R228A；纯布尔/整型域无浮点组态闸） —— *)
rtReq(CLK := bChangeReq);                    (* 申请沿每拍必调 / Request edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bAllow := FALSE;                            (* 放行脉冲预清，唯一分支置位 / Allow preset *)
bChangeAllow := FALSE;                       (* 放行出口预清 / Allow outlet preset *)
eDeny := E_DL_LawDeny.eNone;                 (* 拒绝成因预清（信息级逐拍重算） / Deny preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清留痕锁存 + 清三计数 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_LawCause.eNone;          (* 清成因 / Clear cause *)
    _bTrail := FALSE;                        (* 清留痕锁存 / Clear trail latch *)
    bTrailLatch := FALSE;                    (* 清留痕出口 / Clear trail outlet *)
    _nInWin := 0;                            (* 清窗内计数 / Clear in-window count *)
    _nOutside := 0;                          (* 清窗外计数 / Clear outside count *)
    _nDeny := 0;                             (* 清拒绝计数 / Clear deny count *)
    _eState := E_DL_LawState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_LawState.eIdle:                     (* 待机相 / Idle *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_LawState.eAudit; (* 进入审计 / Enter audit *)
        END_IF
    E_DL_LawState.eAudit:                    (* 审计相：申请沿三分支判定 / Audit *)
        IF NOT bEnable THEN
            _eState := E_DL_LawState.eIdle;  (* 失能回待机 / Back to idle *)
        ELSIF rtReq.Q THEN                   (* 申请沿判定 / On request edge *)
            IF NOT bInAuditWin THEN
                eDeny := E_DL_LawDeny.eOutOfWin;   (* 成因：窗外（独立成员，R190） / Cause: outside *)
                _nOutside := _nOutside + 1;      (* 窗外计数（UDINT 回绕工程安全） / Count outside *)
                _nDeny := _nDeny + 1;            (* 拒绝总计数 / Count deny *)
            ELSIF NOT (bConfirmOp1 AND bConfirmOp2) THEN   (* 双人确认闸（同拍同时电平，边界①） / Two-operator gate *)
                eDeny := E_DL_LawDeny.eOneOp;    (* 成因：单人（独立成员，R190） / Cause: single op *)
                _nDeny := _nDeny + 1;            (* 拒绝总计数 / Count deny *)
            ELSE
                _bAllow := TRUE;             (* 放行单拍 / Allow pulse *)
                _nInWin := _nInWin + 1;      (* 留痕计数 / Count change *)
                _bTrail := TRUE;             (* 留痕锁存置位（复位沿清，边界③） / Set trail latch *)
            END_IF
        END_IF
    E_DL_LawState.eFault:                    (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_LawState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_LawCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bChangeAllow := _bAllow;                     (* 放行脉冲出口 / Allow outlet *)
bTrailLatch := _bTrail;                      (* 留痕锁存出口 / Trail outlet *)
nChangeCnt := _nInWin;                       (* 窗内计数出口 / In-window outlet *)
nOutsideCnt := _nOutside;                    (* 窗外计数出口 / Outside outlet *)
nDenyCnt := _nDeny;                          (* 拒绝计数出口 / Deny outlet *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
