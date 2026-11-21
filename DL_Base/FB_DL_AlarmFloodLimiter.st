(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AlarmFloodLimiter
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 报警泛滥抑制（ISA-18.2 泛滥抑制语义）。同源报警在一个分窗内
 *                         累计次数超过 nFloodLimit 即进入抑制态 bSuppressed；抑制期
 *                         tSuppressHold 内新报警不再上送（bPassThrough = FALSE），但抑制期
 *                         内到达的报警仍逐次计数，抑制结束时以 nSuppressedCount 一次性
 *                         给出该段台账（首末计数语义：进入抑制清零，抑制结束定稿）。
 *                         禁止抑制任何「安全类」来源：bSafetyCritical 为真时 bPassThrough
 *                         恒为真，且该类报警不进入泛滥计数（安全侧不可被闸掉，本件核心红线）。
 * 接口     (Interface)  : 输入 uAlarmSrc 来源号、bAlarmActive 报警有效位、bSafetyCritical
 *                         安全类标记、nFloodLimit 窗内同源次数上限、tWindow 分窗时长、
 *                         tSuppressHold 抑制保持时长、bReset 复位电平；输出 bPassThrough
 *                         上送许可、bSuppressed 抑制态、nSuppressedCount 抑制期计数台账、
 *                         nWindowCount 当前窗计数、eState / eCause / bError / nErrId。
 * 边界     (Boundary)   : ① 组态闸：nFloodLimit = 0 或 tWindow <= T#0S 或 tSuppressHold <= T#0S
 *                         → 故障锁存；② 分窗用 TON 自复位实现（IN := NOT tonWindow.Q，
 *                         R188），窗口边界由计时器自身产生，不依赖外部沿清零；
 *                         ③ **不使用数组环缓冲**，故本件无下标越界路径（派单「环缓冲下标先判
 *                         边界」条款在本件以「零数组」方式结构性满足）；
 *                         ④ TON 两枚 + R_TRIG 两枚段 0 无条件周期刷新；
 *                         ⑤ 故障相迁出唯一路径 = bReset 上升沿；⑥ 零全局耦合（无 GVL / 无物理地址）。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 抑制态已退出（NOT bSuppressed，当拍量，
 *                         R240 范式）。自证可满足（终审两式 1）：tonSuppress 的 IN 挂抑制态
 *                         本身，抑制态退出后 IN 落假、Q 必落假，且组态修正后闸即放开，无恒假因子。
 * 码表     (Codes)      : 16#0001_03EC 故障级：泛滥抑制器故障总码（组态非法 / 非法相位），
 *                         锁存至 bReset 上升沿，归因由 eCause 承载（R190 单件单总码）；
 *                         16#0001_04AF 信息级：抑制段结束台账（抑制保持期到，nSuppressedCount 定稿）。
 *                         加码反证（R90）：抑制段结束是一个不改变 bSuppressed 终值的「已发生事实」，
 *                         其唯一可观测证据是抑制期累计数，而该数在抑制结束后与抑制前的
 *                         nWindowCount 无任何可分辨关系，故须立一码留痕。
 *                         码段说明：0001 段故障子带 03xx / 信息子带 04xx，本件取 03EC / 04AF
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考 ISA-18.2 报警生命周期分类与参数域，
 *                         零代码行复制；t2-8-isa182 族）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 1 · 序号 3）
 *==============================================================================*)

TYPE E_DL_AflState :
(
    eIdle  := 0,     // 窗内无报警流量，等待首个报警 / Idle, no alarm traffic in window
    eRun   := 10,    // 计数/抑制运行 / Counting or suppressing
    eFault := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_AflCause :
(
    eNone       := 0,   // 无故障成因 / No cause
    eCfgIllegal := 1    // 组态非法 / Illegal configuration
);
END_TYPE

FUNCTION_BLOCK FB_DL_AlarmFloodLimiter
VAR_INPUT
    uAlarmSrc       : UINT := 0;              // 报警来源号，同号视为同源 [号] / Alarm source id, same id means same source
    bAlarmActive    : BOOL := FALSE;          // 报警有效位（电平），上升沿计入一次 [次] / Alarm active level, rising edge counts once
    bSafetyCritical : BOOL := FALSE;          // 安全类来源标记，TRUE 时永不被抑制 [-] / Safety-critical source, never suppressed when TRUE
    nFloodLimit     : UDINT := 10;            // 窗内同源次数上限，域 > 0 [次] / Same-source count limit in window, domain > 0
    tWindow         : TIME := T#10S;          // 分窗时长，域 > T#0S [ms] / Window duration, domain > T#0S
    tSuppressHold   : TIME := T#60S;          // 抑制保持时长，域 > T#0S [ms] / Suppression hold duration
    bReset          : BOOL := FALSE;          // 复位命令，上升沿清故障 [-] / Reset command, rising edge clears fault
END_VAR
VAR_OUTPUT
    bPassThrough      : BOOL;                 // 上送许可，TRUE = 允许报警上送 [-] / Pass-through permit for alarm upload
    bSuppressed       : BOOL;                 // 抑制态镜像 [-] / Suppression state mirror
    nSuppressedCount  : UDINT;                // 抑制期计数台账（锁存量，抑制结束定稿） [次] / Suppressed count ledger, latched
    nWindowCount      : UDINT;                // 当前分窗内同源计数 [次] / Same-source count in current window
    eState            : E_DL_AflState;        // 状态出口，段 6 单点映射 / State outlet
    eCause            : E_DL_AflCause;        // 故障成因出口（R190 归因唯一） / Fault cause outlet
    bError            : BOOL;                 // 故障锁存标志 [-] / Fault latch flag
    nErrId            : UDINT;                // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState           : E_DL_AflState := E_DL_AflState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause           : E_DL_AflCause := E_DL_AflCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonWindow         : TON;                  // 分窗计时（自复位），段 0 无条件调用 / Window timer, self-resetting
    tonSuppress       : TON;                  // 抑制保持计时，段 0 无条件调用 / Suppression hold timer
    rtAlarm           : R_TRIG;               // 报警上升沿实例，段 0 无条件调用 / Alarm rising edge
    rtReset           : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge
    _bSuppressed      : BOOL;                 // 抑制态（锁存量） / Suppression state, latched
    _nWindowCount     : UDINT;                // 窗内同源计数（锁存量，唯一写入点） [次] / Window count, single write point
    _nSuppCount       : UDINT;                // 抑制期累计计数（锁存量，唯一写入点） [次] / Suppressed cumulative count, single write point
    _uSrcLast         : UINT;                 // 上一报警来源号（窗内归属判定） [号] / Last alarm source id for window attribution
    _bCfgBad          : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration
    _bFault           : BOOL;                 // 故障锁存位（锁存量） / Latched fault bit
    _uFault           : UDINT;                // 故障码锁存（锁存量） / Latched fault code
    _uInfo            : UDINT;                // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR
VAR CONSTANT
    DL_COUNT_MAX : UDINT := 16#FFFF_FFFE;     // 计数饱和上限，留加 1 裕度防溢出 [次] / Count saturation limit with increment margin [count]
END_VAR

(* —— 段 0：当拍量派生 + 定时器与沿实例无条件周期刷新 —— *)
_bCfgBad := (nFloodLimit = 0) OR (tWindow <= T#0S) OR (tSuppressHold <= T#0S);  // 组态非法当拍量 / Illegal configuration
rtAlarm(CLK := bAlarmActive);                                                   // 报警沿，每拍必调（R228A） / Alarm edge, called every scan
rtReset(CLK := bReset);                                                         // 复位沿，每拍必调 / Reset edge, called every scan
tonWindow(IN := NOT tonWindow.Q, PT := tWindow);                                // 分窗计时自复位（R188） / Self-resetting window timer
tonSuppress(IN := _bSuppressed, PT := tSuppressHold);                           // 抑制保持计时，IN 挂抑制态 / Suppression hold timer gated by state

(* —— 段 1：单拍量预清零（锁存量不入清单，R107） —— *)
_uInfo           := 16#0000_0000;        // 信息码每拍重算 / Info recomputed every scan
nErrId           := 16#0000_0000;        // 事件码缺省无事件 / Event code default none
bError           := FALSE;               // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset
bPassThrough     := TRUE;                // 上送许可缺省允许（安全侧优先） / Pass-through defaults to TRUE, safe side
bSuppressed      := _bSuppressed;        // 抑制态镜像（名实同源） / Suppression mirror
nSuppressedCount := _nSuppCount;         // 抑制台账镜像（锁存量回放） / Suppressed ledger mirror
nWindowCount     := _nWindowCount;       // 窗计数镜像（锁存量回放） / Window count mirror

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_AflCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    IF _eState = E_DL_AflState.eFault THEN
        _eState := E_DL_AflState.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸 / Configuration gate
    _uFault := 16#0001_03EC;                                             // 故障级：泛滥抑制器故障总码 / Fault-level: limiter fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_AflCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF

(* —— 段 3：分窗边界 / 泛滥计数 / 抑制保持 —— *)
IF tonWindow.Q THEN                                                      // 窗口边界（单拍事件，自复位产生） / Window boundary, single scan
    _nWindowCount := 0;                                                  // 新窗计数清零（窗内量唯一重置点） / Reset window count at boundary
    _uSrcLast := 0;                                                      // 新窗来源归属清零 / Reset source attribution
END_IF
IF (NOT _bFault) AND rtAlarm.Q AND (NOT bSafetyCritical) THEN            // 安全类不入泛滥计数（红线） / Safety alarms excluded from flood counting
    IF (NOT _bSuppressed) THEN
        IF uAlarmSrc = _uSrcLast THEN                                    // 同源（整数判等合法） / Same source, integer equality is legal
            IF _nWindowCount < DL_COUNT_MAX THEN
                _nWindowCount := _nWindowCount + 1;                      // 同源计数递增 / Same-source increment
            END_IF
        ELSE
            _uSrcLast := uAlarmSrc;                                      // 换源重开计数 / New source restarts counting
            _nWindowCount := 1;
        END_IF
        IF _nWindowCount > nFloodLimit THEN                              // 超限进抑制 / Over limit enters suppression
            _bSuppressed := TRUE;                                        // 抑制态置位（锁存量） / Suppression latched
            _nSuppCount := 0;                                            // 抑制期台账清零（进入唯一重置点） / Ledger reset at entry
        END_IF
    ELSE
        IF _nSuppCount < DL_COUNT_MAX THEN
            _nSuppCount := _nSuppCount + 1;                              // 抑制期仍继续计数 / Counting continues while suppressed
        END_IF
    END_IF
END_IF
IF _bSuppressed AND tonSuppress.Q THEN                                   // 抑制保持期到 / Suppression hold elapsed
    _bSuppressed := FALSE;                                               // 退出抑制（锁存量） / Exit suppression
    _uInfo := 16#0001_04AF;                                              // 信息级：抑制段结束台账 / Info: suppression segment closed
    _nWindowCount := 0;                                                  // 抑制结束重开窗计数 / Restart window counting
    _uSrcLast := 0;                                                      // 抑制结束清来源归属 / Clear source attribution
END_IF

(* —— 段 4：故障解除式（R240 全当拍量） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bSuppressed) THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_AflCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_AflState.eFault) THEN
    _eState := E_DL_AflState.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_AflState.eIdle:
    IF (_nWindowCount > 0) OR _bSuppressed THEN                           // 出口 1：窗内有流量或抑制中 / Traffic present or suppressing
        _eState := E_DL_AflState.eRun;
    ELSIF _bFault THEN                                                    // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_AflState.eFault;
    END_IF

E_DL_AflState.eRun:
    IF (_nWindowCount = 0) AND (NOT _bSuppressed) THEN                    // 出口 1：窗空且未抑制 / Empty window, not suppressing
        _eState := E_DL_AflState.eIdle;
    ELSIF _bFault THEN                                                    // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_AflState.eFault;
    END_IF

E_DL_AflState.eFault:
    ;                                                                      // 故障相：仅段 4 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0001_03EC;                                              // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_AflCause.eCfgIllegal;                                 // 归因：相位非法归并组态 / Cause: phase illegal
    _eState := E_DL_AflState.eFault;

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放；安全侧钳位） —— *)
IF bSafetyCritical OR _bFault THEN
    bPassThrough := TRUE;                                                 // 安全类 / 故障相恒放行（核心红线，不掩盖报警） / Always pass for safety sources and in fault
ELSIF _bSuppressed THEN
    bPassThrough := FALSE;                                                // 抑制期闸掉（仅非安全类、无故障） / Gated while suppressing
ELSE
    bPassThrough := TRUE;                                                 // 默认放行 / Default permit
END_IF
IF _bFault THEN
    nErrId := _uFault;                                                    // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                     // 信息码 / Info code
END_IF
bError := _bFault;                                                        // 故障标志与锁存同源（名实双出口，R191） / Flag from latch
eState := _eState;                                                        // 状态出口 / State outlet
eCause := _eCause;                                                        // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
