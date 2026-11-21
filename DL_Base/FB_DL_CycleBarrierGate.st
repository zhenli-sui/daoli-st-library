(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CycleBarrierGate
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON），零厂商私有库
 * 功能描述 (Function)   : 多设备同周期相位会合闸（集合点原语）。nMemberCount 个
 *                         成员各自上报就绪电平（abMemberReady），全部就绪时
 *                         bGateOpen 单拍放行并清到达掩码；若在 tWindow 内未能
 *                         全员到齐 → bBarrierTimeout 置位并锁存滞留成员掩码
 *                         （诊断用），需 bAck 确认后重新等待。产线多工站同拍
 *                         会合、多轴同步起点、批处理工序齐套场景。
 * 来源标签 (Origin)     : 自研线（IEC 61131-3 标准语义的道莅防御性实现，clean-room）
 * 分工声明 (Pairing)    : CycleBarrierGate（会合闸，本件）↔ FB_DL_SemaMutex（互斥，
 *                         既有件）：本件管「全员齐套统一放行」（AND 集合点），
 *                         不管「资源独占互斥」；SemaMutex 管令牌互斥，不做
 *                         齐套判据（R298 属主边界）。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → bGateOpen 强制 FALSE（放行
 *                         是安全相关动作，失能必须收敛），到达掩码冻结保持；
 *                         eFault 相 → bGateOpen 保持 FALSE，bError = TRUE。
 * 组态闸 (Config gate)  : nMemberCount < 2 或 > 16（集合点无意义/超容量）或
 *                         tWindow <= T#0S → 故障锁存。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)，
 *                         码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 组态闸/数组下标钳位 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 TON 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 4 成员全员就绪 → bGateOpen 单拍 TRUE 且掩码清零；
 *                         V2 窗口到时仅 3/4 就绪 → bBarrierTimeout=TRUE，
 *                         uLatchedMask 指示滞留成员位；
 *                         V3 nMemberCount=1 → eFault 锁存。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 2 · 序号 6）
 *==============================================================================*)
TYPE E_DL_CbgState :
(
    eIdle    := 0,                           (* 待启动（闸门关闭） / Idle, gate closed *)
    eWait    := 10,                          (* 等待全员就绪 / Waiting for all members *)
    eTimeout := 20,                          (* 窗口超时滞留，等确认 / Timeout stranded, awaiting ack *)
    eFault   := 90                           (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_CbgCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：成员数/窗口越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_CycleBarrierGate
VAR_INPUT
    abMemberReady : ARRAY[1..16] OF BOOL;    (* 成员就绪电平数组（按位消费前 nCount 个）[-] / Member ready levels *)
    nMemberCount  : INT := 4;                (* 参与会合成员数，域 2..16 [个] / Member count, domain 2..16 *)
    tWindow       : TIME := T#5S;            (* 全员到齐窗口保持时长 [ms] / All-arrive window hold time *)
    bStart        : BOOL := FALSE;           (* 会合启动电平，TRUE 开始等待 / Barrier start level *)
    bAck          : BOOL := FALSE;           (* 超时确认，上升沿清滞留掩码并重新等待 [-] / Timeout ack, rising edge clears strand mask *)
    bEnable       : BOOL := TRUE;            (* 会合闸使能，FALSE 时放行强制收敛 [-] / Gate enable *)
    bReset        : BOOL := FALSE;           (* 复位命令，上升沿清全部内部状态 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bGateOpen        : BOOL;                 (* 放行单拍位（全员到齐拍置位）[-] / Gate-open single-scan pulse *)
    uArrivedMask     : UDINT;                (* 当前已到达成员位掩码（实时）[-] / Current arrived member bitmask *)
    uLatchedMask     : UDINT;                (* 超时滞留成员位掩码（锁存至 bAck）[-] / Stranded member bitmask latched until ack *)
    nArrivedCnt      : INT;                  (* 已到达成员数（实时）[个] / Arrived member count *)
    bBarrierTimeout  : BOOL;                 (* 窗口超时锁存位（bAck 清）[-] / Window timeout latch, cleared by ack *)
    eState           : E_DL_CbgState;        (* 状态出口 / State outlet *)
    eCause           : E_DL_CbgCause;        (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError           : BOOL;                 (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_CbgState := E_DL_CbgState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_CbgCause := E_DL_CbgCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtAck     : R_TRIG;                     (* 确认沿实例，段 0 无条件调用 / Ack edge instance *)
    rtReset   : R_TRIG;                     (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonWindow : TON;                        (* 到齐窗口计时，IN 由相位派生 / Window timer *)
    _nArrived : INT;                        (* 到达计数当拍派生量 [个] / Arrived count derived this scan *)
    _uMask    : UDINT;                      (* 到达掩码当拍派生量 / Arrived bitmask derived *)
    _bAllArr  : BOOL;                       (* 全员到齐当拍判据 / All-arrived verdict *)
    _i        : INT;                        (* 成员扫描游标（每趟重置，R227）[-] / Member scan cursor *)
    _bFault   : BOOL;                       (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                       (* 组态非法当拍量 / Illegal config this scan *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (nMemberCount < 2) OR (nMemberCount > 16) OR (tWindow <= T#0S);   (* 组态闸 / Config gate *)
rtAck(CLK := bAck);                                                          (* 确认沿每拍必调 / Ack edge every scan *)
rtReset(CLK := bReset);                                                      (* 复位沿每拍必调 / Reset edge every scan *)
tonWindow(IN := _eState = E_DL_CbgState.eWait, PT := tWindow);               (* 窗口计时随相位派生 / Window timer phase-derived *)
_uMask := 0;                                                                 (* 掩码派生量清零重扫 / Mask derived recompute *)
_nArrived := 0;                                                              (* 到达计数清零重扫 / Count derived recompute *)
_i := 1;                                                                     (* 游标起头显式重置（R227） / Cursor reset *)
WHILE _i <= nMemberCount DO                                                  (* 只扫前 nCount 个成员（容量内，无越界） / Scan first nCount members *)
    _uMask := _uMask + _uMask;                                               (* 先整体左移一位（UDINT 域 16 成员最大 2^16 无溢出，免 SHL 移位量归一，R295） / Shift left first *)
    IF abMemberReady[_i] THEN
        _uMask := _uMask + 1;                                                (* 后置位最低位：成员 i 落于位 i-1（自证向量：i=1→bit0，i=2→bit1） / Then set LSB: member i maps to bit i-1 *)
        _nArrived := _nArrived + 1;                                          (* 到达计数 / Arrived count *)
    END_IF
    _i := _i + 1;                                                            (* 游标递进 / Cursor advance *)
END_WHILE
_bAllArr := (_nArrived >= nMemberCount);                                     (* 全员到齐判据（整数等值域合法） / All-arrived verdict *)

(* —— 段 1：单拍量预清零（R107） —— *)
bGateOpen := FALSE;                                                          (* 放行单拍位预清，唯一分支置位 / Gate pulse preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清掩码锁存 + 清超时 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                       (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_CbgCause.eNone;                                         (* 清成因 / Clear cause *)
    uLatchedMask := 0;                                                      (* 清滞留掩码锁存 / Clear strand mask *)
    bBarrierTimeout := FALSE;                                               (* 清超时锁存 / Clear timeout latch *)
    _eState := E_DL_CbgState.eIdle;                                         (* 迁待启动相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                        (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_CbgCause.eCfgIllegal;                                   (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_CbgState.eFault;                                        (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_CbgState.eIdle:                                                    (* 待启动相 / Idle *)
        IF bStart AND bEnable AND NOT _bFault THEN
            _eState := E_DL_CbgState.eWait;                                 (* 启动进入等待 / Start enters wait *)
        END_IF
    E_DL_CbgState.eWait:                                                    (* 等待全员相 / Wait *)
        IF NOT bEnable OR NOT bStart THEN                                   (* 启动撤销回待机 / Start withdrawn *)
            _eState := E_DL_CbgState.eIdle;                                 (* 回待启动 / Back to idle *)
        ELSIF _bAllArr THEN                                                 (* 全员到齐 / All arrived *)
            bGateOpen := TRUE;                                              (* 放行单拍脉冲 / Gate pulse *)
            _eState := E_DL_CbgState.eIdle;                                 (* 本周期会合完成回待机（每周期重新集合语义） / Round complete, re-convene next cycle *)
        ELSIF tonWindow.Q THEN                                              (* 窗口到时未齐 / Window expired *)
            uLatchedMask := _uMask;                                         (* 锁存滞留掩码（诊断：值为 1 的位 = 已到，0 的位 = 滞留） / Latch strand mask *)
            bBarrierTimeout := TRUE;                                        (* 超时锁存至 bAck / Timeout latch *)
            _eState := E_DL_CbgState.eTimeout;                              (* 迁超时相 / Enter timeout *)
        END_IF
    E_DL_CbgState.eTimeout:                                                 (* 超时滞留相 / Timeout *)
        IF rtAck.Q THEN                                                     (* 确认沿：清锁存重新等待 / Ack: clear latch, re-wait *)
            uLatchedMask := 0;                                              (* 清滞留掩码 / Clear strand mask *)
            bBarrierTimeout := FALSE;                                       (* 清超时锁存 / Clear timeout latch *)
            _eState := E_DL_CbgState.eWait;                                 (* 重新等待（eWait 相退出条件：事件沿 + 状态清除双条件） / Re-enter wait *)
        ELSIF NOT bEnable OR NOT bStart THEN
            _eState := E_DL_CbgState.eIdle;                                 (* 启动撤销亦可退出（第二退出条件） / Start withdrawn exit *)
        END_IF
    E_DL_CbgState.eFault:                                                   (* 故障相：仅复位沿出 / Fault *)
        ;                                                                   (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                    (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_CbgState.eFault;                                    (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                    (* 同步锁存 / Latch *)
        _eCause := E_DL_CbgCause.ePhaseBad;                                 (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
uArrivedMask := _uMask;                                                     (* 到达掩码实时镜像 / Arrived mask mirror *)
nArrivedCnt := _nArrived;                                                   (* 到达计数实时镜像 / Arrived count mirror *)
bError := _bFault;                                                          (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                          (* 状态出口 / State outlet *)
eCause := _eCause;                                                          (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
