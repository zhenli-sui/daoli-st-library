(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ChillerYearWinStart
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 冷机年度启停窗与保养互锁。启动申请仅在「年窗电平
 *                         内 + 保养完成互锁成立」时放行 bRun，否则拒绝并按
 *                         独立成因（非窗 / 保养未完）给出 bBlocked 电平与
 *                         eBlock 成因（R190 归因唯一）；运行中可随时停止。
 *                         与 YearWindowCheck（年窗原子）分工：本件叠加
 *                         「非窗禁启」的设备控制语义。
 * 来源标签 (Origin)     : ROADMAP §16.5 R11 池（L725），自研 clean-room
 * 边界语义 (Boundary)   : ① 启动判据全组合闸（窗电平 / 保养互锁 / 无故障），
 *                         拒启不锁存故障（拒绝是正常业务态）；
 *                         ② 保养互锁输入非有限无涉（布尔域），无浮点量；
 *                         ③ eBlock 成因独立成员逐拍重算（拒绝成因随当前
 *                         条件实时回放，信息级允许每拍重算，R189）。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → bRun 强制 FALSE（启停
 *                         出口失能必须收敛）；eFault 相 → bRun FALSE + bError。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 无浮点域/组态无涉 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 窗内 + 保养完 + 申请沿 → bRun=TRUE，bBlocked=FALSE；
 *                         V2 窗外申请沿 → bRun=FALSE，bBlocked=TRUE，
 *                         eBlock=eNotInWin；
 *                         V3 窗内但保养未完 → eBlock=eMaintDue（非窗成因
 *                         不再误报）。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 2 · 序号 7）
 *==============================================================================*)
TYPE E_DL_CwsBlock :
(
    eNone     := 0,                          (* 无拒绝（已放行或无申请） / No block *)
    eNotInWin := 1,                          (* 非年窗禁启 / Not in year window *)
    eMaintDue := 2                           (* 保养未完禁启 / Maintenance interlock open *)
);
END_TYPE

TYPE E_DL_CwsState :
(
    eIdle  := 0,                             (* 停机待窗 / Idle *)
    eRun   := 10,                            (* 运行 / Running *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_CwsCause :
(
    eNone     := 0,                          (* 无故障成因 / No cause *)
    ePhaseBad := 3                           (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_ChillerYearWinStart
VAR_INPUT
    bInWin     : BOOL := FALSE;              (* 年窗电平（上层 YearWindowCheck 供给）[-] / Year-window level *)
    bMaintOk   : BOOL := TRUE;               (* 保养完成互锁电平 [-] / Maintenance interlock *)
    bStartReq  : BOOL := FALSE;              (* 启动申请电平 [-] / Start request *)
    bStopReq   : BOOL := FALSE;              (* 停止申请电平（运行中随时可停）[-] / Stop request *)
    bEnable    : BOOL := TRUE;               (* 使能 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清全部 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bRun       : BOOL;                       (* 冷机运行出口 [-] / Run outlet *)
    bStartOk   : BOOL;                       (* 本次申请放行单拍位 [-] / Start-allowed pulse *)
    bBlocked   : BOOL;                       (* 申请被拒电平（申请期实时）[-] / Blocked level *)
    eBlock     : E_DL_CwsBlock;              (* 拒绝成因（信息级逐拍重算，R189） / Block cause *)
    nRunCycles : UDINT;                      (* 累计启动次数 [次] / Run cycle count *)
    eState     : E_DL_CwsState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_CwsCause;              (* 故障成因出口 / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_CwsState := E_DL_CwsState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_CwsCause := E_DL_CwsCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtStart   : R_TRIG;                      (* 启动申请沿实例，段 0 无条件调用 / Start edge instance *)
    rtStop    : R_TRIG;                      (* 停止申请沿实例，段 0 无条件调用 / Stop edge instance *)
    rtReset   : R_TRIG;                      (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _nCycles  : UDINT;                       (* 启动计数锁存 [次] / Cycle count latch *)
    _bStartOk : BOOL;                        (* 放行单拍量 [-] / Start-allowed work *)
    _bFault   : BOOL;                        (* 故障锁存位 / Latched fault bit *)
END_VAR

(* —— 段 0：沿实例无条件刷新（R228A；纯布尔域无浮点组态闸） —— *)
rtStart(CLK := bStartReq);                   (* 启动沿每拍必调 / Start edge every scan *)
rtStop(CLK := bStopReq);                     (* 停止沿每拍必调 / Stop edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bStartOk := FALSE;                          (* 放行脉冲预清，唯一分支置位 / Start-ok preset *)
bStartOk := FALSE;                           (* 放行出口预清 / Start-ok outlet preset *)
bBlocked := FALSE;                           (* 拒绝电平预清 / Blocked preset *)
eBlock := E_DL_CwsBlock.eNone;               (* 拒绝成因预清（判定分支覆盖） / Block cause preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清计数 + 迁 eIdle（bRun 随相位收敛），R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_CwsCause.eNone;          (* 清成因 / Clear cause *)
    _nCycles := 0;                           (* 清启动计数 / Clear count *)
    _eState := E_DL_CwsState.eIdle;          (* 迁停机相 / Back to idle *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_CwsState.eIdle:                     (* 停机相 / Idle *)
        IF rtStart.Q AND bEnable THEN        (* 申请沿：判组合闸 / On start edge *)
            IF NOT bInWin THEN
                bBlocked := TRUE;            (* 拒绝电平 / Blocked level *)
                eBlock := E_DL_CwsBlock.eNotInWin;   (* 成因：非窗（独立成员，R190） / Cause: not in window *)
            ELSIF NOT bMaintOk THEN
                bBlocked := TRUE;            (* 拒绝电平 / Blocked level *)
                eBlock := E_DL_CwsBlock.eMaintDue;   (* 成因：保养未完 / Cause: maintenance *)
            ELSE
                _bStartOk := TRUE;           (* 放行单拍 / Start-ok pulse *)
                _nCycles := _nCycles + 1;    (* 启动计数（UDINT 回绕工程安全） / Count start *)
                _eState := E_DL_CwsState.eRun;   (* 进入运行 / Enter run *)
            END_IF
        END_IF
    E_DL_CwsState.eRun:                      (* 运行相：停止沿随时出 / Run *)
        IF rtStop.Q OR (NOT bEnable) THEN    (* 停止沿或失能：回停机 / Stop or disable *)
            _eState := E_DL_CwsState.eIdle;  (* 回停机相 / Back to idle *)
        END_IF
    E_DL_CwsState.eFault:                    (* 故障相：仅复位沿出（bRun 随段 5 收敛） / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_CwsState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_CwsCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bRun 与相位同源同义，R191 名实双出口） —— *)
bRun := (_eState = E_DL_CwsState.eRun) AND bEnable AND (NOT _bFault);   (* 运行出口（失能/故障收敛 FALSE） / Run outlet *)
bStartOk := _bStartOk;                       (* 放行脉冲出口 / Start-ok outlet *)
nRunCycles := _nCycles;                      (* 启动计数出口 / Count outlet *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
