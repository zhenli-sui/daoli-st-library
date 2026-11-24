(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisFeedbackFailoverSeq
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 主反馈（负载侧光栅尺/全闭环编码器）失效 → 电机侧反馈降级切换序。
 *                         四段序，每段语义显式，绝无"静默降级"：
 *                           ① ePrimary 主用相：bUsePrimary=TRUE，主反馈在岗；
 *                           ② eConfirm 失主确认相：主反馈有效位为假且持续 tLossConfirm；
 *                           ③ eSwitching 切换过渡相：**两侧均不宣称可用**（bUsePrimary 与
 *                              bUseMotorSide 同为假），先撤主用再等 tSwitchDwell，让轴级看到
 *                             一个明确的"无有效反馈"过渡拍，禁止无缝瞬切造成位置基准跳变；
 *                           ④ eDegraded 降级保持相：bUseMotorSide=TRUE 且 bFailoverActive 锁存置真，
 *                             告警持续可见直到人工复位（不因主反馈恢复而自动消失——那会让
 *                             维护人员永远看不到发生过降级）。
 *                         另设 eBlocked：主反馈已失效但 bSwitchPermit 为假（轴在运动中、
 *                         未到安全位）→ 置 bSwitchForbidden 告警，两侧反馈出口同为假，
 *                         交由轴级停机；**不做"先切了再说"**。
 * 接口     (Interface)  : 输入 bPrimaryValid 主反馈有效位、bSwitchPermit 允许切换（安全前置）、
 *                         tLossConfirm 失主确认时间、tSwitchDwell 切换过渡驻留时间、bReset 复位；
 *                         输出 bUsePrimary 用主反馈、bUseMotorSide 用电机侧、bFailoverActive
 *                         降级告警锁存、bSwitchForbidden 切换被禁止告警、eState / eCause / bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件是"切换序"的唯一属主**——它决定何时撤主用、
 *                         何时上电机侧、过渡驻留多久。**判"负载侧是否可信"不是本件的职责**，
 *                         那属于 `FB_DL_AxisLoadEncoderLossMonitor`；本件只吃它的结论位
 *                         bPrimaryValid，不得内嵌断线/冻结判据（否则两件归因冲突、故障台账双记）。
 *                         ② 本件**不使能/不停止轴、不发运动指令**，只出反馈选择与告警位，
 *                         降级后的速度/位置环怎么跑由轴级 POU 决定。
 *                         ③ 组态闸：tLossConfirm <= T#0S → 故障锁存（防零时切换）。tSwitchDwell 的
 *                            "域 >= T#0S" 由类型本身保证（TIME 无符号），v1.0.1 已删除该恒假判据。
 *                         ④ 两枚 TON + 一枚 R_TRIG 段 0 无条件周期刷新，PT 语义成对写死；
 *                         切换过渡用 tonDwell（IN = 当拍位于 eSwitching），出相即 IN 落假自动复位，
 *                         无跨相累积（R228A）。
 *                         ⑤ 故障相与降级相均可迁出（R228B）：bReset 上升沿 → ePrimary。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_AxisLoadEncoderLossMonitor`（只判负载侧可信度）、
 *                         `FB_DL_AxisDualFeedbackGuard`（双侧交叉校核）三件成组：监控件出结论，
 *                         本件按结论执行切换，校核件做一致性体检。三件互不内嵌对方判据。
 * 来源标签 (Source Tag) : P1 双反馈族 / T2-4 ◐
 * 解除式   (Release)    : bReset 上升沿（人工确认）→ 回 ePrimary 并清 bFailoverActive。
 *                         自证可满足：复位是外部操作员动作，不受任何锁存量门控；不设"主反馈自动
 *                         恢复即回切"的隐式路径——那会在反馈抖动时来回切换，且会抹掉降级告警痕迹。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 BOOL（bUsePrimary / bUseMotorSide /
 *                         bFailoverActive / bSwitchForbidden / bError）+ ENUM（eState / eCause）；
 *                         数字码位待主控收口阶段统一派号（R46 码位规则）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 时间域几何闸 + 无浮点比较 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 ✓ TON/R_TRIG 段 0 无条件刷新
 * 返修记录 (Repair)     : v1.0.1（R47 P0 返修）① bError 出口增 `(_eState = eFault)` 项——原先只有禁止相
 *                         置位，故障相虽锁存却不报错，轴级不会停机；② 删除 `tSwitchDwell < T#0S` 恒假死检查
 *                         （TIME 为无符号时长量，与 0 的"小于"结构性不可达，属死判据）。
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 2 · 序号 6）
 *==============================================================================*)

TYPE E_DL_FfsState :
(
    ePrimary   := 0,    // 主反馈在岗相 / Primary feedback in service
    eConfirm   := 10,   // 失主确认相（等 tLossConfirm） / Primary-loss confirmation
    eSwitching := 20,   // 切换过渡相（两侧均不宣称可用） / Switching transition, neither side claimed
    eDegraded  := 30,   // 降级保持相（电机侧在岗，告警锁存） / Degraded hold, alarm latched
    eBlocked   := 40,   // 切换被禁止相（安全前置未满足） / Switch forbidden phase
    eFault     := 90    // 组态故障相 / Configuration fault phase
);
END_TYPE

TYPE E_DL_FfsCause :
(
    eNone           := 0,   // 无故障成因 / No cause
    eCfgIllegal     := 1,   // 组态非法（确认时间非正/驻留为负） / Illegal configuration
    ePrimaryLost    := 2,   // 主反馈失效并已确认，完成降级 / Primary lost and confirmed, degraded
    eSwitchForbidden:= 3,   // 主反馈失效但切换前置不满足 / Primary lost but switching not permitted
    ePhaseBad       := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisFeedbackFailoverSeq
VAR_INPUT
    bPrimaryValid  : BOOL := TRUE;          // 主反馈（负载侧）有效位，来自监控件 [-] / Primary feedback validity, from the monitor unit
    bSwitchPermit  : BOOL := FALSE;         // 允许切换的安全前置（轴静止/在安全位） [-] / Safety precondition permitting the switch
    tLossConfirm   : TIME := T#100MS;       // 失主确认时间，域 > T#0S [ms] / Primary-loss confirm time, domain > T#0S
    tSwitchDwell   : TIME := T#20MS;        // 切换过渡驻留时间，域 >= T#0S [ms] / Switching dwell, domain >= T#0S
    bReset         : BOOL := FALSE;         // 人工复位，上升沿回主用相并清降级告警 [-] / Manual reset, rising edge returns to primary
END_VAR
VAR_OUTPUT
    bUsePrimary     : BOOL;     // 采用主反馈（负载侧） [-] / Use primary feedback
    bUseMotorSide   : BOOL;     // 采用电机侧反馈（降级后） [-] / Use motor-side feedback
    bFailoverActive : BOOL;     // 降级告警，锁存保持到复位（显式，不静默） [-] / Failover alarm, latched until reset
    bSwitchForbidden: BOOL;     // 切换被禁止告警（当拍量） [-] / Switch-forbidden alarm, per scan
    eState          : E_DL_FfsState;    // 状态出口 [-] / State outlet
    eCause          : E_DL_FfsCause;    // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError          : BOOL;             // 故障标志（组态故障或切换被禁止） [-] / Error flag
END_VAR
VAR
    _eState    : E_DL_FfsState := E_DL_FfsState.ePrimary;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause    : E_DL_FfsCause := E_DL_FfsCause.eNone;       // 成因出口暂存（锁存语义由相位承载） / Cause staging
    tonLoss    : TON;           // 失主确认计时，段 0 无条件调用 / Primary-loss confirm timer
    tonDwell   : TON;           // 切换过渡驻留计时，段 0 无条件调用 / Switching dwell timer
    rtReset    : R_TRIG;        // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _bFailover : BOOL;          // 降级告警锁存位（锁存量，仅复位沿清） / Latched failover alarm
    _bCfgBad   : BOOL;          // 组态非法当拍量 [-] / Illegal configuration this scan
END_VAR

(* —— 段 0：判据派生 + 两 TON 一沿无条件周期刷新 —— *)
_bCfgBad := (tLossConfirm <= T#0S);                             // 时间域几何闸（v1.0.1 删 tSwitchDwell < T#0S 恒假判据：TIME 无符号） / Time-domain geometry gate
rtReset(CLK := bReset);                                          // 复位沿，每拍必调（R228A） / Reset edge, every scan
tonLoss(IN := NOT bPrimaryValid, PT := tLossConfirm);            // 失主确认：有效位为假即计时（IN 由当拍判据派生） / Loss confirm, IN derived per scan
tonDwell(IN := (_eState = E_DL_FfsState.eSwitching), PT := tSwitchDwell);   // 过渡驻留：仅在过渡相计时，出相自复位 / Dwell only in transition phase

(* —— 段 1：单拍量预清零（锁存量 _bFailover / _eCause 不入清单，R107） —— *)
bUsePrimary      := FALSE;      // 主用出口每拍预清 / Primary outlet preset
bUseMotorSide    := FALSE;      // 电机侧出口每拍预清 / Motor-side outlet preset
bFailoverActive  := FALSE;      // 降级告警每拍预清，锁存分支同拍回填 / Failover alarm preset
bSwitchForbidden := FALSE;      // 禁止切换告警每拍预清 / Forbidden alarm preset
bError           := FALSE;      // 故障标志每拍预清（R45 配对） / Error flag preset

(* —— 段 2：复位沿（唯一回主用路径，人工确认语义） —— *)
IF rtReset.Q THEN
    _bFailover := FALSE;                    // 清降级告警锁存（锁存量） / Clear latched failover alarm
    _eCause    := E_DL_FfsCause.eNone;      // 清成因 / Clear cause
    _eState    := E_DL_FfsState.ePrimary;   // 回主用相（R228B 迁出路径） / Return to primary phase
END_IF

(* —— 段 3：组态闸（先于相位机，保证每拍一致） —— *)
IF _bCfgBad THEN
    _eState := E_DL_FfsState.eFault;        // 组态非法入故障相 / Enter fault phase
    _eCause := E_DL_FfsCause.eCfgIllegal;   // 归因：组态非法 / Cause: illegal configuration
    bError  := TRUE;                        // 故障标志同拍置位 / Error flag set same scan
END_IF

(* —— 段 4：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_FfsState.ePrimary:
    IF bPrimaryValid = FALSE THEN                       // 出口 1：主反馈报失效 → 进确认相（不立即切） / Primary reported invalid, confirm first
        _eState := E_DL_FfsState.eConfirm;
    ELSIF rtReset.Q THEN                                // 出口 2：复位沿保持主用相（幂等） / Reset keeps primary, idempotent
        _eState := E_DL_FfsState.ePrimary;
    END_IF

E_DL_FfsState.eConfirm:
    IF bPrimaryValid THEN                               // 出口 1：有效位回真（抖动）→ 回主用，不留痕 / Validity returned, back to primary without a trace
        _eState := E_DL_FfsState.ePrimary;
    ELSIF tonLoss.Q THEN                                // 出口 2：确认窗到 → 看安全前置 / Confirm window elapsed, check precondition
        IF bSwitchPermit THEN
            _eState := E_DL_FfsState.eSwitching;        // 前置满足：进切换过渡 / Precondition met, enter transition
        ELSE
            _eState := E_DL_FfsState.eBlocked;          // 前置不满足：进禁止相（不硬切） / Precondition unmet, forbid the switch
        END_IF
    END_IF

E_DL_FfsState.eSwitching:
    IF rtReset.Q THEN                                   // 出口 1：过渡中人工复位 → 回主用相 / Reset during transition
        _eState := E_DL_FfsState.ePrimary;
    ELSIF NOT bSwitchPermit THEN                        // 出口 2：前置撤销（轴动起来了）→ 撤回并进禁止相 / Precondition withdrawn
        _eState := E_DL_FfsState.eBlocked;
    ELSIF tonDwell.Q THEN                               // 出口 3：驻留到 → 上电机侧并锁存告警 / Dwell elapsed, engage motor side
        _bFailover := TRUE;                             // 告警锁存（锁存量） / Latch the alarm
        _eCause    := E_DL_FfsCause.ePrimaryLost;       // 归因：主反馈失效已完成降级 / Cause: primary lost, degraded
        _eState    := E_DL_FfsState.eDegraded;
    END_IF

E_DL_FfsState.eDegraded:
    IF rtReset.Q THEN                                   // 出口：仅人工复位可离开降级相 / Only a manual reset leaves degradation
        _eState := E_DL_FfsState.ePrimary;
    END_IF

E_DL_FfsState.eBlocked:
    IF bPrimaryValid THEN                               // 出口 1：主反馈自己回来了 → 回主用（解除禁止） / Primary recovered by itself
        _eState := E_DL_FfsState.ePrimary;
    ELSIF bSwitchPermit AND tonLoss.Q THEN              // 出口 2：前置满足且确认仍在 → 进切换过渡 / Precondition now met
        _eState := E_DL_FfsState.eSwitching;
    END_IF

E_DL_FfsState.eFault:
    IF rtReset.Q AND (NOT _bCfgBad) THEN                // 出口：复位沿 + 组态已合法才迁出（R228B） / Reset edge with legal config
        _eState := E_DL_FfsState.ePrimary;
    END_IF

ELSE
    _eCause := E_DL_FfsCause.ePhaseBad;                 // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_FfsState.eFault;                    // 强拉故障相 / Force fault phase
    bError  := TRUE;                                    // 故障标志 / Error flag

END_CASE

(* —— 段 5：出口单点映射（名实同源；过渡相两侧皆假是设计意图，非缺省） —— *)
CASE _eState OF
E_DL_FfsState.ePrimary:
    bUsePrimary := TRUE;                                // 主用相：取主反馈 / Primary phase uses primary feedback
E_DL_FfsState.eDegraded:
    bUseMotorSide := TRUE;                              // 降级相：取电机侧 / Degraded phase uses motor side
E_DL_FfsState.eBlocked:
    bSwitchForbidden := TRUE;                           // 禁止相：显式告警 / Forbidden phase raises the alarm
    bError           := TRUE;                           // 禁止相属故障级（轴级据此停机） / Forbidden is fault level
ELSE
    ;                                                   // 其余相（确认/过渡/故障）：两侧均不宣称可用 / Other phases claim neither side
END_CASE
bFailoverActive := _bFailover;                          // 降级告警与锁存同源（R191） / Alarm from latch
bError          := bError OR (_eState = E_DL_FfsState.eFault);   // v1.0.1：故障相必置故障标志（原先仅禁止相置位） / Fault phase forces the error flag
eState          := _eState;                             // 状态出口 / State outlet
eCause          := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
