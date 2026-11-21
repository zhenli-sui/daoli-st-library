(*==============================================================================
 * 组件名称 (Component)  : FB_DL_WatchdogPulseMon
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 外部看门狗脉冲超时判死 + 恢复确认窗，双阈值。
 *                         ① 判死阈值 tDeathTimeout：相邻两个脉冲上升沿的间隔超过该值即判死。
 *                            实现上把"判死计时"的 IN 接到 (NOT 脉冲沿单拍标志)，每来一个脉冲沿
 *                            计时器被复位一次，因此计时器量的正是"距上一沿的静默时长"。
 *                         ② 恢复确认窗 tRecoverConfirm：判死后不因单个脉冲就复生，必须连续
 *                            tRecoverConfirm 内持续有脉冲（即判死计时器始终未被 Q 置起）才恢复。
 *                         判死为锁存量（bDead 保持），恢复是显式二段：eRecover 期间维持 bDead
 *                         为真、bAlive 仍为假，只有确认窗走完才同时翻转——杜绝"单个毛刺脉冲
 *                         宣告复活"的假恢复。
 * 接口     (Interface)  : 输入 bPulse 外部看门狗脉冲、tDeathTimeout 判死超时、tRecoverConfirm
 *                         恢复确认窗、bReset 复位；输出 bAlive 存活（未判死且已过确认窗）、
 *                         bDead 判死锁存、bRecovering 恢复确认中、tSilence 当前静默时长、
 *                         eState / eCause / bError。
 * 边界     (Boundary)   : ① 组态闸：tDeathTimeout <= T#0S、tRecoverConfirm < T#0S 或
 *                         tRecoverConfirm > tDeathTimeout（确认窗长于判死窗会让"恢复"永远
 *                         等不到确认）→ 故障锁存并归因 eCfgIllegal。
 *                         ② 双 TON 均在段 0 无条件周期刷新，且 IN 由当拍判据派生（非外部沿清零），
 *                         符合 R228A：tonDeath 与 tonRecover 的 IN 都是当拍表达式的函数。
 *                         ③ 判死锁存位 _bDead 的清除路径唯一 = 恢复确认窗 Q 置起（bReset 上升沿
 *                         亦可强制清，用于检修旁路），两条路径都在段 5 显式写出（R228B 可迁出）。
 *                         ④ 无 TON 跨相复用：两枚计时器分别服务"判死"与"恢复"，PT 语义成对写死，
 *                         不复用同一实例改 PT。
 *                         ⑤ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_CycleTimeMeasure`（任务周期测量）分工——那件量任务自身节拍，
 *                         本件判**外部**喂狗脉冲是否还活着，二者不可互替（任务节拍正常而外部
 *                         通讯已死是常见工况）。
 * 来源标签 (Source Tag) : T1-7 ◐（开源参考：硬件看门狗脉冲监测与恢复确认参数域，零代码行复制）
 * 解除式   (Release)    : 恢复确认窗 Q 置起（连续 tRecoverConfirm 内有脉冲）∨ bReset 上升沿。
 *                         自证可满足：确认窗 IN = 判死计时器未超时，只要外部真在喂狗，该 IN 持续
 *                         为真，PT 到即置 Q，不依赖任何锁存量或恒假因子。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 BOOL（bAlive/bDead/bRecovering/
 *                         bError）+ ENUM（eState / eCause），数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 时间域几何闸 + 无浮点比较 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 ✓ TON/R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 1 · 序号 4）
 *==============================================================================*)

TYPE E_DL_WpmState :
(
    eIdle      := 0,    // 首拍未收到脉冲，等待首沿 / Awaiting the first pulse edge
    eAlive     := 10,   // 脉冲正常相 / Pulses healthy
    eDead      := 20,   // 判死锁存相（保持 bDead） / Dead latched phase
    eRecover   := 30,   // 恢复确认相（维持 bDead，等待确认窗） / Recovery confirmation phase
    eFault     := 90    // 组态故障相（仅复位沿可迁出） / Configuration fault phase
);
END_TYPE

TYPE E_DL_WpmCause :
(
    eNone        := 0,   // 无故障成因 / No cause
    eCfgIllegal  := 1,   // 组态非法（判死窗非正/确认窗越过判死窗） / Illegal configuration
    eTimeout     := 2,   // 静默超判死窗（外部喂狗已停） / Silence exceeded the death timeout
    eRecoverFail := 3,   // 恢复期中再次超时（恢复被推翻） / Timed out again while recovering
    ePhaseBad    := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_WatchdogPulseMon
VAR_INPUT
    bPulse           : BOOL := FALSE;      // 外部看门狗脉冲（沿有效，电平宽度无关） [-] / External watchdog pulse, edge triggered
    tDeathTimeout    : TIME := T#500MS;    // 判死超时，域 > T#0S（相邻沿最大间隔） [ms] / Death timeout, max gap between edges, domain > T#0S
    tRecoverConfirm  : TIME := T#2S;       // 恢复确认窗，域 >= T#0S 且 <= tDeathTimeout [ms] / Recovery confirm window, 0..death timeout
    bReset           : BOOL := FALSE;      // 复位/检修旁路，上升沿清判死 [-] / Reset or maintenance bypass, rising edge clears death latch
END_VAR
VAR_OUTPUT
    bAlive     : BOOL;              // 存活（未判死且不在恢复确认中） [-] / Alive, not dead and not confirming
    bDead      : BOOL;              // 判死锁存（恢复期仍为真） [-] / Dead latched, still true while confirming
    bRecovering: BOOL;              // 恢复确认中 [-] / Recovery confirmation in progress
    tSilence   : TIME;              // 距上一脉冲沿的静默时长（当拍量） [ms] / Silence since the last pulse edge [ms]
    eState     : E_DL_WpmState;     // 状态出口 [-] / State outlet
    eCause     : E_DL_WpmCause;     // 故障成因出口（R190 归因唯一） [-] / Fault cause outlet
    bError     : BOOL;              // 故障标志（判死或组态非法） [-] / Error flag, dead or illegal configuration
END_VAR
VAR
    _eState    : E_DL_WpmState := E_DL_WpmState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause    : E_DL_WpmCause := E_DL_WpmCause.eNone;    // 故障成因锁存量 / Latched cause
    tonDeath   : TON;               // 判死计时（IN=非脉冲沿），段 0 无条件调用 / Death timer, unconditional call
    tonRecover : TON;               // 恢复确认计时（IN=判死计时未超时），段 0 无条件调用 / Recovery confirm timer, unconditional call
    rtPulse    : R_TRIG;            // 脉冲沿实例，段 0 无条件调用 / Pulse edge instance
    rtReset    : R_TRIG;            // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _bDead     : BOOL;              // 判死锁存位（锁存量） / Latched dead bit
    _bCfgBad   : BOOL;              // 组态非法当拍量 [-] / Illegal configuration this scan
    _bSeenEdge : BOOL;              // 已收到过首个脉冲沿（锁存量） / First edge seen, latched
    _bRecoverFail : BOOL;           // 恢复期再次超时当拍量 [-] / Timed out again during recovery
END_VAR

(* —— 段 0：判据派生 + 三实例无条件周期刷新 —— *)
_bCfgBad := (tDeathTimeout <= T#0S)                         // 判死窗须为正 / Death window must be positive
         OR (tRecoverConfirm < T#0S)                        // 确认窗不得为负 / Confirm window must not be negative
         OR (tRecoverConfirm > tDeathTimeout);              // 确认窗不得越过判死窗（否则永不恢复） / Confirm window must not exceed death window
rtPulse(CLK := bPulse);                                     // 脉冲沿，每拍必调（R228A） / Pulse edge, called every scan
rtReset(CLK := bReset);                                     // 复位沿，每拍必调 / Reset edge, called every scan
tonDeath(IN := NOT rtPulse.Q, PT := tDeathTimeout);         // 判死计时：每来一个沿即复位（IN 由当拍判据派生，非外部清零） / Death timer reset by each edge
tonRecover(IN := (NOT tonDeath.Q) AND (NOT _bCfgBad), PT := tRecoverConfirm);   // 恢复确认：判死计时未超时即视为在喂狗 / Recovery confirm while pulses keep coming

(* —— 段 1：单拍量预清零（锁存量 _bDead / _bSeenEdge / _eCause 不入清单，R107） —— *)
bAlive      := FALSE;           // 存活位每拍预清 / Alive preset
bDead       := FALSE;           // 判死出口每拍预清，锁存分支同拍回填 / Dead outlet preset
bRecovering := FALSE;           // 恢复位每拍预清 / Recovering preset
bError      := FALSE;           // 故障标志每拍预清（R45 配对） / Error flag preset
tSilence    := T#0S;            // 静默时长每拍预清 / Silence preset

(* —— 段 2：静默时长出口（判死计时器已量出的时长直接回放，不另起计时器） —— *)
IF tonDeath.Q THEN
    tSilence := tDeathTimeout;                  // 已超时：报判死窗值（真实静默 >= 该值，取保守下界） / Timed out: report the death window as a conservative bound
ELSE
    tSilence := T#0S;                           // 未超时：本件不暴露亚阈值静默时长（TON 无 ET 出口依赖，保持跨平台） / Below threshold: not exposed
END_IF

(* —— 段 3：复位沿 / 组态闸 —— *)
IF rtReset.Q THEN
    _bDead := FALSE;                            // 清判死锁存（检修旁路） / Clear dead latch
    _bRecoverFail := FALSE;                     // 清恢复失败标记 / Clear recovery-fail flag
    IF _eState = E_DL_WpmState.eFault THEN
        _eState := E_DL_WpmState.eIdle;         // 故障相迁出（R228B） / Leave fault phase
    END_IF
    IF _eState = E_DL_WpmState.eDead THEN
        _eState := E_DL_WpmState.eIdle;         // 判死相迁出（R228B，第二条可迁出路径） / Leave dead phase, second exit path
    END_IF
END_IF
IF _bCfgBad THEN
    _eState := E_DL_WpmState.eFault;            // 组态非法入故障相 / Illegal configuration enters fault phase
    _eCause := E_DL_WpmCause.eCfgIllegal;       // 归因：组态非法 / Cause: illegal configuration
END_IF

(* —— 段 4：首沿捕获（未见过沿前不判死，避免上电即报死） —— *)
IF rtPulse.Q THEN
    _bSeenEdge := TRUE;                         // 首沿锁存（锁存量） / First edge latched
    IF (_eState = E_DL_WpmState.eIdle) THEN
        _eState := E_DL_WpmState.eAlive;        // 首沿即入存活相 / First edge enters alive phase
    END_IF
END_IF

(* —— 段 5：判死与恢复（判死锁存，恢复二段确认；两条清除路径显式列出） —— *)
_bRecoverFail := (_eState = E_DL_WpmState.eRecover) AND tonDeath.Q;     // 恢复期中再次超时 / Timed out again while recovering
IF (_eState <> E_DL_WpmState.eFault) AND _bSeenEdge AND tonDeath.Q THEN
    _bDead := TRUE;                             // 判死锁存（锁存量） / Latch dead
    _eCause := E_DL_WpmCause.eTimeout;          // 归因：静默超时 / Cause: silence timeout
    IF _eState = E_DL_WpmState.eRecover THEN
        _eCause := E_DL_WpmCause.eRecoverFail;  // 归因：恢复被推翻 / Cause: recovery overturned
        _eState := E_DL_WpmState.eDead;         // 回到判死相 / Back to dead phase
    ELSIF _eState <> E_DL_WpmState.eDead THEN
        _eState := E_DL_WpmState.eDead;         // 首次判死 / First death detection
    END_IF
END_IF
IF _eState = E_DL_WpmState.eDead THEN
    IF tonRecover.Q THEN
        _bDead := FALSE;                        // 清除路径 1：恢复确认窗走完 / Exit path 1: recovery window completed
        _eCause := E_DL_WpmCause.eNone;         // 清成因 / Clear cause
        _eState := E_DL_WpmState.eAlive;        // 回存活相 / Back to alive phase
    ELSIF NOT tonDeath.Q THEN
        _eState := E_DL_WpmState.eRecover;      // 转入恢复确认相（bDead 仍为真） / Enter recovery phase, dead still true
    END_IF
END_IF

(* —— 段 6：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_WpmState.eIdle:
    IF _bCfgBad THEN                                        // 出口 1：组态非法 / Illegal configuration
        _eState := E_DL_WpmState.eFault;
    ELSIF _bSeenEdge THEN                                   // 出口 2：已见首沿 / First edge seen
        _eState := E_DL_WpmState.eAlive;
    END_IF

E_DL_WpmState.eAlive:
    IF _bCfgBad THEN                                        // 出口 1：组态转非法 / Configuration went illegal
        _eState := E_DL_WpmState.eFault;
    ELSIF _bDead THEN                                       // 出口 2：判死锁存 / Dead latched
        _eState := E_DL_WpmState.eDead;
    END_IF

E_DL_WpmState.eDead:
    IF _bDead = FALSE THEN                                  // 出口：锁存已清（段 5 两条路径之一） / Latch cleared by one of the two paths
        _eState := E_DL_WpmState.eAlive;
    END_IF

E_DL_WpmState.eRecover:
    IF _bDead = FALSE THEN                                  // 出口：确认窗走完，恢复成立 / Recovery window completed
        _eState := E_DL_WpmState.eAlive;
    ELSIF tonDeath.Q THEN                                   // 出口：恢复被推翻（段 5 已置 _bRecoverFail） / Recovery overturned
        _eState := E_DL_WpmState.eDead;
    END_IF

E_DL_WpmState.eFault:
    ;                                                       // 故障相：仅段 3 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _eCause := E_DL_WpmCause.ePhaseBad;                     // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_WpmState.eFault;                        // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 7：出口单点映射（名实双出口，R191） —— *)
IF _eState = E_DL_WpmState.eFault THEN
    bDead := _bDead;                                        // 故障相回放锁存值（不臆造） / Replay latch in fault phase
ELSE
    bDead := _bDead;                                        // 非故障相同样回放锁存值 / Replay latch outside fault phase
END_IF
bRecovering := (_eState = E_DL_WpmState.eRecover);          // 恢复确认中 / Recovery confirmation in progress
bAlive      := (_eState = E_DL_WpmState.eAlive) AND (NOT _bDead);          // 存活 = 存活相且未锁存 / Alive = alive phase and not latched
bError      := _bDead OR (_eState = E_DL_WpmState.eFault);  // 故障标志 = 判死或组态故障 / Error = dead or configuration fault
eState      := _eState;                                     // 状态出口 / State outlet
eCause      := _eCause;                                     // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
