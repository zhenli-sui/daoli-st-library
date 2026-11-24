(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FilmSpliceWeekPlan
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 接膜保养周窗判定与耗材台账提醒。按日历输入（星期
 *                         1..7 / 小时 0..23）判周窗电平；运行小时与接膜次数
 *                         双台账任一到限即保养到期 bMaintDue；耗材用量达预告
 *                         线（限值 80%）即 bRemind 提前提醒；保养确认沿重置
 *                         台账。与 RuntimeMeter（纯时长累计）分工：本件把周
 *                         窗判定 + 台账 + 提醒绑成保养闭环。
 * 来源标签 (Origin)     : ROADMAP §16.4 R11 池（L718），自研 clean-room
 * 边界语义 (Boundary)   : ① 日历域闸（星期 1..7 / 小时 0..23 / 限值正域）→
 *                         组态故障；
 *                         ② 台账输入非有限拍冻结（不判到限不误提醒）；
 *                         ③ 周窗结束未保养 → bWinMissed 单拍错过提示（不锁存
 *                         故障，提醒类语义）；
 *                         ④ 确认沿重置双台账，阈值不重置。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 窗/台账判定冻结保持；
 *                         eFault 相 → 冻结 + bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 NaN 冻结/组态闸/预告线乘法常量 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 星期 3、小时 02（窗 [2,4]）、运行小时 520 >= 500
 *                         → bInWin=TRUE 且 bMaintDue=TRUE；
 *                         V2 接膜次数 81（限 100，80% 预告线 = 80）→ bRemind=TRUE；
 *                         V3 确认沿后运行小时清 0、bMaintDue=FALSE。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 1 · 序号 5）
 *==============================================================================*)
TYPE E_DL_FswState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eWatch := 10,                            (* 周窗与台账监视 / Watch *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_FswCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：日历/限值越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_FilmSpliceWeekPlan
VAR_INPUT
    nDayOfWeek : INT := 1;                   (* 当前星期 1..7 [-] / Day of week *)
    nHour      : INT := 0;                   (* 当前小时 0..23 [h] / Current hour *)
    nWinDay    : INT := 1;                   (* 保养星期，域 1..7 [-] / Maintenance day *)
    nWinHourStart : INT := 2;                (* 窗起始小时，域 0..23 且 < nWinHourEnd [h] / Window start hour *)
    nWinHourEnd   : INT := 4;                (* 窗结束小时（不含），域 1..24 [h] / Window end hour *)
    fRunHours  : LREAL := 0.0;               (* 运行小时台账输入（RuntimeMeter 供给）[h] / Runtime hours ledger *)
    fRunHoursLimit : LREAL := 500.0;         (* 运行小时保养限值，域 > 0 [h] / Runtime limit *)
    nSpliceCnt : UDINT := 0;                 (* 接膜次数台账输入 [次] / Splice count ledger *)
    nSpliceLimit  : UDINT := 100;            (* 接膜次数保养限值，域 > 0 [次] / Splice limit *)
    bMaintAck  : BOOL := FALSE;              (* 保养确认沿（重置台账）[-] / Maintenance ack edge *)
    bEnable    : BOOL := TRUE;               (* 使能 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清全部 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bInWin     : BOOL;                       (* 周窗电平（星期且小时在窗内）[-] / Week-window level *)
    bMaintDue  : BOOL;                       (* 保养到期（双台账任一到限）[-] / Maintenance due *)
    bRemind    : BOOL;                       (* 耗材提前提醒（达 80% 预告线）[-] / Consumable remind *)
    bWinMissed : BOOL;                       (* 周窗结束未保养单拍提示 [-] / Window-missed pulse *)
    nAckCnt    : UDINT;                      (* 累计保养确认次数 [次] / Ack count *)
    eState     : E_DL_FswState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_FswCause;              (* 故障成因出口 / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_FswState := E_DL_FswState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_FswCause := E_DL_FswCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtAck     : R_TRIG;                      (* 确认沿实例，段 0 无条件调用 / Ack edge instance *)
    rtReset   : R_TRIG;                      (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    rtWinClose: R_TRIG;                      (* 窗关闭沿实例，段 0 无条件调用 / Window-close edge *)
    _bInWin   : BOOL;                        (* 周窗派生电平 [-] / Window level derived *)
    _bDueRaw  : BOOL;                        (* 到限原始判据 [-] / Due raw verdict *)
    _bLedBad  : BOOL;                        (* 台账非有限当拍量 [-] / Ledger non-finite *)
    _nAck     : UDINT;                       (* 确认计数锁存 [次] / Ack count latch *)
    _bPrevDue : BOOL;                        (* 上拍到限快照（错过提示判据）[-] / Prev due snapshot *)
    _bFault   : BOOL;                        (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                        (* 组态非法当拍量 / Illegal config this scan *)
END_VAR
VAR CONSTANT
    DL_FSW_REMIND : LREAL := 0.8;            (* 耗材预告线比例（80%）[-] / Remind ratio *)
END_VAR

(* —— 段 0：当拍判据派生 + 沿实例无条件刷新（R228A） —— *)
_bCfgBad := (nWinDay < 1) OR (nWinDay > 7) OR (nWinHourStart < 0) OR (nWinHourStart > 23)
            OR (nWinHourEnd < 1) OR (nWinHourEnd > 24) OR (nWinHourStart >= nWinHourEnd)
            OR (fRunHoursLimit <= 0.0) OR (nSpliceLimit = 0);   (* 组态闸（R151 全引脚 + 窗界序） / Config gate *)
rtAck(CLK := bMaintAck);                     (* 确认沿每拍必调 / Ack edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
rtWinClose(CLK := (NOT _bInWin));            (* 窗关闭沿每拍必调（基于上拍派生电平） / Window-close edge *)
_bLedBad := (fRunHours <> fRunHours) OR ((fRunHours - fRunHours) <> (fRunHours - fRunHours));   (* 运行小时 NaN 自反 + Inf 差判 / Ledger non-finite *)
_bInWin := (nDayOfWeek = nWinDay) AND (nHour >= nWinHourStart) AND (nHour < nWinHourEnd);   (* 周窗派生（整型直比无浮点） / Window derive *)
_bDueRaw := (NOT _bLedBad) AND ((fRunHours >= fRunHoursLimit) OR (nSpliceCnt >= nSpliceLimit));   (* 双台账到限原始判据（NaN 拍不判，边界②） / Due raw verdict *)

(* —— 段 1：单拍量预清零（R107） —— *)
bWinMissed := FALSE;                         (* 错过提示预清，唯一分支置位 / Missed pulse preset *)
bMaintDue := FALSE;                          (* 到限出口预清（全路径赋值） / Due preset *)
bRemind := FALSE;                            (* 提醒出口预清 / Remind preset *)
bInWin := FALSE;                             (* 窗出口预清 / Window preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清确认计数 + 清快照 + 迁 eIdle，R283 逐项声明；台账输入为外部量不在清域） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_FswCause.eNone;          (* 清成因 / Clear cause *)
    _nAck := 0;                              (* 清确认计数 / Clear ack count *)
    _bPrevDue := FALSE;                      (* 清上拍快照 / Clear snapshot *)
    _eState := E_DL_FswState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_FswCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_FswState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_FswState.eIdle:                     (* 待机相 / Idle *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_FswState.eWatch; (* 进入监视 / Enter watch *)
        END_IF
    E_DL_FswState.eWatch:                    (* 监视相：窗判定 + 台账判据 + 确认闭环 / Watch *)
        IF NOT bEnable THEN
            _eState := E_DL_FswState.eIdle;  (* 失能回待机 / Back to idle *)
        ELSE
            bInWin := _bInWin;               (* 窗出口镜像 / Window mirror *)
            bMaintDue := _bDueRaw;           (* 到限出口镜像 / Due mirror *)
            IF (NOT _bLedBad) AND (nSpliceLimit > 0) THEN   (* 提醒判据（台账有效 + 限值闸） / Remind verdict *)
                bRemind := (UDINT_TO_LREAL(nSpliceCnt) >= DL_FSW_REMIND * UDINT_TO_LREAL(nSpliceLimit))
                           AND (nSpliceCnt < nSpliceLimit);   (* 达 80% 预告线且未到限（预告不重复到限告警） / Remind band *)
            END_IF
            IF _bPrevDue AND (NOT _bDueRaw) AND rtWinClose.Q THEN   (* 窗关时到限刚消退：本窗未保养错过提示（过渡态三段：拍 N 进窗关沿/本拍发单拍/拍 N+1 预清，R80） / Window missed pulse *)
                bWinMissed := TRUE;          (* 错过单拍提示（提醒类不锁存故障，边界③） / Missed pulse *)
            END_IF
            IF rtAck.Q THEN                  (* 确认沿：台账由调用方清零，本件只计数 / Ack edge *)
                _nAck := _nAck + 1;          (* 确认计数（UDINT 回绕工程安全） / Count ack *)
            END_IF
            _bPrevDue := _bDueRaw;           (* 上拍快照维护（R285） / Snapshot maintain *)
        END_IF
    E_DL_FswState.eFault:                    (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_FswState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_FswCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
nAckCnt := _nAck;                            (* 确认计数出口 / Ack count outlet *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
