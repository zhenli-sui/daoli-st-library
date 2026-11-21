(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PassiveHomingMonitor
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 被动回零旁路监听（参考事件确认）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / F_TRIG / TON / ABS / MIN / MAX / LIMIT）
 * 接口依赖 (Depends)    : 无 DL_ 内部依赖。本件**不引用**轴状态枚举、**不定义**轴状态枚举，
 *                         也**不调用**任何 MC_ 运动功能块（见分层声明）。
 * 功能描述 (Function)   : 轴被外力移动时（手摇轮、另一驱动拖动、重力下落、维护推车），
 *                         旁路监听参考事件（原点开关沿 / Z 相 / 标记锁存），按「方向一致性
 *                         + 速度窗 + 多次位置一致性」三条判据确认参考点，输出建议施加的
 *                         位置偏移给上层，由上层以 MC_SetPosition 语义消费。
 * 边界（最重要）        : **不自造轴状态、不写轴状态机**。本件只有一个工艺位 bReferenced，
 *                         轴状态（Disabled / Standstill / DiscreteMotion 等）**只由运动层
 *                         拥有**——这是 R31 家族（两套状态机并存）的最高危区，本件按 R11
 *                         判例执行：输出相位 ePhase 仅供 HMI 诊断显示，**不得**被上层当作
 *                         轴状态使用，也不得反向改写轴状态位。
 *                         与 FB_DL_AxisHomingSeq 的分工：后者是**主动回零顺控**（自己发运动
 *                         指令、四模式），本件**不发任何运动指令**，只旁路监听并输出偏移；
 *                         两者可并存，但不得互相改写对方的结论位。
 * 分层声明 (Layer)      : 运动层旁路监视件。上行只为「建议偏移」，下行只有引脚采样。
 *                         零全局变量表引用、零外部变量声明、零物理 IO 地址。
 * 段序     (Segments)   : 段1 实例无条件刷新 → 段2 复位通道（CASE 前，R39）→ 段3 撤防受理 →
 *                         段4 输入防御与镜像量锁定 → 段5 布防受理（倒计置位点，R34）→
 *                         段6 事件受理（倒计递减点，与段5 相邻，R34）→ 段7 状态机 →
 *                         段8 码位单一优先级链 → 段9 出口钳位与保持语义重写。
 * 枚举映射表 (R31)      : eIdle(0)→标签 0｜eArmed(10)→标签 10｜eCaptured(20)→标签 20｜
 *                         eConfirmed(30)→标签 30｜eTimeout(40)→标签 40｜eFault(99)→标签 99。
 *                         每个成员有且仅有一个显式标签，ELSE 只接脏值（02D4）。
 * 单拍标志清单 (R25)    : bArm —— 预清零点：段1 每拍由 `_bArmReq := FALSE` 前的实例输出覆盖；
 *                         置位点：段1 `_bArmReq := _fbTrigArm.Q AND (NOT _bArmConsumed)`；
 *                         自清点：段5 消费时 `_bArmConsumed := TRUE`（撤防、超时、复位三处解除）。
 *                         bReset —— 预清零点：段1 每拍覆盖 _bResetEdge；置位点：段1 的
 *                         _fbTrigReset 实例调用；自清点：紧随实例调用的 _bResetEdge 赋值行。
 *                         bRefEvent —— 内部取上升沿（段1 实例），在段6 单点消费，无对外单拍位。
 * 保持位清单 (R27)      : bReferenced / fRefPos / fOffsetToApply —— 三者逐拍由
 *                         _bRefLatched / _fRefPosHeld / _fOffsetHeld 重写并夹域；
 *                         nEventCount 逐拍由 _nEventCount 转换重写。复位沿清结论。
 * 定时器清单 (R40)      : _fbTonArmTimeout｜IN = (相位 = eArmed 或 eCaptured) AND NOT _bArmBreak｜
 *                         断输入标志 _bArmBreak（每次布防置一拍，本拍 TON 复位 ET）｜
 *                         自清点：段3 无条件 `IF _bArmBreak THEN _bArmBreak := FALSE; END_IF`。
 *                         _fbTonNoMotion｜IN = (相位 = eArmed 或 eCaptured) AND NOT bInMotion
 *                         AND NOT _bArmBreak｜语义为「布防期间长时间静止」信息码 01C5。
 * 三元一致表 (R35)      : 速度窗下限守卫 0.01~100 mm/s / 封顶 100 / 判据 `<`（低于即降精度）｜
 *                         速度窗上限守卫 1~10000 mm/s / 封顶 10000 / 判据 `>`（高于即降精度）｜
 *                         一致性容差守卫 0.001~10 mm / 封顶 10 / 判据 `>`（超出即计数重置）。
 * 镜像量清单 (R38)      : fActPos 的唯一消费点是 _fPosSnap（段4 锁定），fActVel 的唯一消费点
 *                         是 _fVelSnap（段4 锁定）；事件受理与限幅判定全部读快照，不读实时入参。
 * 开源溯源 (Origin)     : 原创实现（参考 PLCopen Part 1 的「参考事件（reference event）」与
 *                         被动回零（passive homing）公开语义，T1-6：参考事件上升沿捕获、
 *                         方向一致性、速度窗内采信、多次事件一致性确认，全部为公开的
 *                         技术概念；实现、状态机、码位与引脚契约 100% 本库独立设计，
 *                         clean-room 编写，未复制任何源码行。许可证说明：PLCopen 规范为
 *                         公开规范条款（非代码），引用其条款语义不构成代码复制风险；
 *                         本文件为本库原创，随本库许可证发布。
 * 验收向量 (Acceptance) :
 *   V1 布防 → 正向 20 mm/s → 两次事件（100.00 / 100.05 mm）→ bReferenced = TRUE、
 *      fRefPos = 100.025（取算术均值，非取首个事件，见设计要点③）。
 *   V2（V-C 方向反转）第二次事件发生在反向 → 16#0004_01C4、计数回到 1、**不得**确认。
 *   V3（V-D 超时恢复）tArmTimeout 到 → eTimeout + 16#0004_02D2；重新 bArm 后计数从 0 重建
 *      （R41：恢复不重头，不允许沿用上次部分计数）。
 *   V4（V-A 非有限）fActVel = NaN → 16#0004_02D3、fRefPos 保持上次确认值（不写脏值）。
 *   V5（R43 出口夹域）撤防后 fOffsetToApply 保持上次值且夹进 ±1.0E6 mm；冷启动首拍输出 0.0。
 * 偏离留档 (Deviation)  :
 *   ① 「目标位置」来源：规格要求输出 fOffsetToApply = 目标 − 参考，但引脚表未给目标值引脚。
 *      本件按「参考事件处应读 0.0 mm」的通用约定输出 fOffsetToApply = 0.0 − fRefPos；若现场
 *      参考点非 0，调用方在消费时叠加其目标值（不新增引脚，避免破坏已冻结的引脚契约）。
 *   ② 速度窗上限的处置：规格给 01C3 的语义是「低于窗下限，采信但精度降级」。高于上限时
 *      定位精度同样不保（可能漏捕获相邻事件），本件并入同一信息码 01C3，语义记为「速度窗
 *      越界，已采信但精度降级」，不新增码位（码位表以规格为准）。
 *   ③ fVelMin > fVelMax 时按对调修复并保持静默（无对应码位），属参数自愈，不改变判定逻辑。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 13 · 泳道 C · DL_Motion 第 18 件，补 R8 留扩产项）
 *   2026-11-16  v1.0.1  终审修复：段6 事件受理条件补串 bEnable 与 NOT _bFaultCond ——
 *                       原实现下，非有限值检出当拍若恰有参考事件沿，零化快照会被采信，
 *                       极端情形把 0.0 锁存为参考点（坏值穿透到 bReferenced 保持位）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PassiveHomePhase（归属 FB_DL_PassiveHomingMonitor，同文件发布）
 * 用途: 仅内部相位与 HMI 诊断显示，**不是**轴状态，禁止被上层当作轴状态使用。
 *----------------------------------------------------------------------------*)
TYPE E_DL_PassiveHomePhase :
(
    eIdle      := 0,    // 空闲：未布防 / Idle, not armed
    eArmed     := 10,   // 已布防：等待首个参考事件 / Armed, awaiting the first reference event
    eCaptured  := 20,   // 已捕获：事件数未达标，等待后续一致性事件 / Captured, awaiting consistent events
    eConfirmed := 30,   // 已确认：参考点成立，结论保持 / Confirmed, reference established and held
    eTimeout   := 40,   // 超时：布防期内未捕获足够事件 / Timeout, not enough events while armed
    eFault     := 99    // 故障：位置或速度非有限 / Fault, non-finite position or velocity
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_PassiveHomingMonitor
VAR_INPUT
    bEnable          : BOOL;                // 使能（Enable），FALSE = 冻结监听并清布防；复位通道不受其屏蔽 / Enable, FALSE stops monitoring
    bReset           : BOOL;                // 复位（Reset），上升沿清结论与锁存 / Rising edge clears the verdict and latches
    bArm             : BOOL;                // 布防（Arm），上升沿开始监听，下降沿撤防 / Rising edge arms, falling edge disarms
    bRefEvent        : BOOL;                // 参考事件电平（Raw reference event），内部取上升沿 / Raw reference event, edge detected inside
    bDirForward      : BOOL := TRUE;        // 本拍运动方向（Current direction），TRUE = 正向，默认 TRUE / TRUE forward, FALSE reverse
    fActPos          : REAL;                // 实际位置（Actual position）[mm]，只读采样，域 −1E7~1E7 / Actual position [mm], read-only
    fActVel          : REAL;                // 实际速度（Actual velocity）[mm/s]，只读采样，域 −1E5~1E5 / Actual velocity [mm/s], read-only
    bInMotion        : BOOL;                // 轴在运动（Axis in motion），速度超噪声带为 TRUE / TRUE when the axis exceeds the noise band
    fVelMin          : REAL := 1.0;         // 速度窗下限（Velocity window low）[mm/s]，域 0.01~100，默认 1.0 / Velocity window low [mm/s]
    fVelMax          : REAL := 500.0;       // 速度窗上限（Velocity window high）[mm/s]，域 1~10000，默认 500.0 / Velocity window high [mm/s]
    nRequireEvents   : INT := 2;            // 需一致性确认的事件次数（Required consistent events）[次]，域 1~3，默认 2 / Required consistent events, 1 to 3
    fConsistencyTol  : REAL := 0.1;         // 事件位置一致性容差（Consistency tolerance）[mm]，域 0.001~10 / Consistency tolerance [mm]
    tArmTimeout      : TIME := T#120S;      // 布防总超时（Arming timeout），域 1 s~1 h，默认 120 s / Arming timeout, default 120 s
END_VAR

VAR_OUTPUT
    bReferenced      : BOOL;                // 参考点已确认（Referenced），保持语义（R27）/ Referenced, held until reset
    fRefPos          : REAL;                // 确认的参考点位置（Confirmed reference position）[mm]，保持语义 / Confirmed reference position [mm], held
    fOffsetToApply   : REAL;                // 建议施加的位置偏移（Offset to apply）[mm]，= 0.0 − fRefPos，夹进 ±1.0E6 / Offset to apply [mm], clamped
    nEventCount      : UINT;                // 本轮布防内已捕获事件数（Events captured in this arming）[次] / Events captured in this arming
    ePhase           : E_DL_PassiveHomePhase;   // 内部相位（Internal phase），**仅供诊断显示** / Internal phase, diagnostics only
    eHealth          : E_DL_Ne107Status;    // 健康态（NE107 health），引用属主 A1 的枚举 / NE107 health, owned by A1
    uDiagCode        : UDINT;               // 诊断码（Diagnostic code），本拍单一优先级链输出 / Diagnostic code, single priority chain
    uErrorId         : UDINT;               // 故障码（Error code），仅故障级码，0 = 无故障 / Fault-level code, 0 = no fault
    bError           : BOOL;                // 故障标志（Error），仅故障级码置位 / TRUE only for fault-level codes
END_VAR

VAR
    _ePhase          : E_DL_PassiveHomePhase := E_DL_PassiveHomePhase.eIdle; // 内部相位（Internal phase）/ Internal phase value
    _bArmReq         : BOOL;                // 布防单拍请求（Arm one-shot request）/ Arm one-shot request
    _bArmConsumed    : BOOL;                // 布防已消费（Arm consumed flag）/ Arm consumed flag
    _bArmBreak       : BOOL;                // 布防段断输入拍（Arm segment input break）/ One-scan break for the arming timers
    _bResetEdge      : BOOL;                // 复位沿单拍标志（Reset one-shot flag）/ Reset one-shot flag
    _bFaultCond      : BOOL;                // 故障条件（Fault condition）/ Fault condition flag
    _uFaultCode      : UDINT;               // 本拍故障级码（Fault-level code this scan）/ Fault-level code of this scan
    _uFaultLatched   : UDINT;               // 故障码锁存（Latched fault code），仅复位沿清除 / Latched fault code, reset only
    _uInfoCode       : UDINT;               // 本拍信息级码（Info-level code this scan）/ Info-level code of this scan
    _fPosSnap        : REAL;                // 位置快照（Position snapshot）[mm]，镜像量唯一消费点入口 / Position snapshot [mm]
    _fVelSnap        : REAL;                // 速度快照（Velocity snapshot）[mm/s]，镜像量唯一消费点入口 / Velocity snapshot [mm/s]
    _fVelAbs         : REAL;                // 速度绝对值（Absolute velocity）[mm/s] / Absolute velocity [mm/s]
    _fVelMinEff      : REAL;                // 生效速度窗下限（Effective window low）[mm/s] / Effective velocity window low [mm/s]
    _fVelMaxEff      : REAL;                // 生效速度窗上限（Effective window high）[mm/s] / Effective velocity window high [mm/s]
    _fConsTolEff     : REAL;                // 生效一致性容差（Effective consistency tolerance）[mm] / Effective consistency tolerance [mm]
    _nReqEff         : INT;                 // 生效事件次数（Effective required events）[次]，钳位 1~3 / Effective required events, clamped 1 to 3
    _nRequireRemain  : INT;                 // 剩余需确认事件数（Remaining events to confirm）[次]，倒计型（R34）/ Remaining events, countdown type (R34)
    _nEventCount     : INT;                 // 本轮已捕获事件数（Events captured this arming）[次] / Events captured this arming
    _fRefSum         : REAL;                // 事件位置累加（Sum of captured positions）[mm] / Sum of captured positions [mm]
    _fRefMean        : REAL;                // 事件位置均值（Mean of captured positions）[mm] / Mean of captured positions [mm]
    _bDirKnown       : BOOL;                // 方向已记录（Direction recorded）/ Direction recorded flag
    _bLastDir        : BOOL;                // 上一次事件方向（Last event direction）/ Direction of the last captured event
    _bRefLatched     : BOOL;                // 参考点锁存（Reference latch），仅复位沿清除 / Reference latch, reset only
    _fRefPosHeld     : REAL;                // 保持的参考位置（Held reference position）[mm] / Held reference position [mm]
    _fOffsetHeld     : REAL;                // 保持的偏移（Held offset）[mm] / Held offset [mm]
    _fbTrigArm       : R_TRIG;              // 布防上升沿（Arm rising edge）/ Arm rising edge detector
    _fbTrigArmFall   : F_TRIG;              // 撤防下降沿（Arm falling edge）/ Arm falling edge detector
    _fbTrigRefEvt    : R_TRIG;              // 参考事件上升沿（Reference event rising edge）/ Reference event rising edge
    _fbTrigReset     : R_TRIG;              // 复位上升沿（Reset rising edge）/ Reset rising edge detector
    _fbTonArmTimeout : TON;                 // 布防总超时（Arming timeout）/ Arming timeout timer
    _fbTonNoMotion   : TON;                 // 静止监视（No-motion watch）/ No-motion watch timer
END_VAR

VAR CONSTANT
    DL_PHM_REAL_MAX  : REAL := 3.4E38;      // 单精度有限值判据幅值（Finite magnitude bound）/ Finite bound for REAL inputs
    DL_PHM_EPS       : REAL := 1.0E-6;      // 浮点防零容差（Divide-guard epsilon）/ Float divide-guard epsilon
    DL_PHM_POS_MAX   : REAL := 1.0E7;       // 位置输入域（Position input bound）[mm] / Position input bound [mm]
    DL_PHM_VEL_MAX   : REAL := 1.0E5;       // 速度输入域（Velocity input bound）[mm/s] / Velocity input bound [mm/s]
    DL_PHM_VMIN_LO   : REAL := 0.01;        // 速度窗下限的下限（Window low lower clamp）[mm/s] / Lower clamp of the window low [mm/s]
    DL_PHM_VMIN_HI   : REAL := 100.0;       // 速度窗下限的上限（Window low upper clamp）[mm/s] / Upper clamp of the window low [mm/s]
    DL_PHM_VMAX_LO   : REAL := 1.0;         // 速度窗上限的下限（Window high lower clamp）[mm/s] / Lower clamp of the window high [mm/s]
    DL_PHM_VMAX_HI   : REAL := 10000.0;     // 速度窗上限的上限（Window high upper clamp）[mm/s] / Upper clamp of the window high [mm/s]
    DL_PHM_TOL_LO    : REAL := 0.001;       // 一致性容差下限（Tolerance lower clamp）[mm] / Tolerance lower clamp [mm]
    DL_PHM_TOL_HI    : REAL := 10.0;        // 一致性容差上限（Tolerance upper clamp）[mm] / Tolerance upper clamp [mm]
    DL_PHM_OFF_MAX   : REAL := 1.0E6;       // 偏移出口夹域（Offset output clamp）[mm] / Offset output clamp [mm]
    DL_PHM_EVT_MIN   : INT  := 1;           // 最少确认事件数（Minimum required events）[次] / Minimum required events
    DL_PHM_EVT_MAX   : INT  := 3;           // 最多确认事件数（Maximum required events）[次] / Maximum required events
    DL_PHM_EVT_MIN_P : INT  := 1;           // 最小捕获事件数（Minimum captured events）[次] / Minimum captured events
    DL_PHM_ERR_TIMEOUT : UDINT := 16#0004_02D2; // 0004_02D2 布防超时未捕获事件【故障级】/ Arm timeout without event, fault level
    DL_PHM_ERR_NONFIN  : UDINT := 16#0004_02D3; // 0004_02D3 位置或速度非有限【故障级】/ Non-finite position or velocity, fault level
    DL_PHM_ERR_STATE   : UDINT := 16#0004_02D4; // 0004_02D4 非法状态兜底【故障级】/ Illegal state fallback, fault level
    DL_PHM_INFO_VEL    : UDINT := 16#0004_01C3; // 0004_01C3 速度窗越界，事件已采信但精度降级【信息级】/ Velocity window exceeded, low precision, info level
    DL_PHM_INFO_DIR    : UDINT := 16#0004_01C4; // 0004_01C4 方向与上次相反，一致性计数重置【信息级】/ Direction reversed, count reset, info level
    DL_PHM_INFO_NOMOT  : UDINT := 16#0004_01C5; // 0004_01C5 布防期间长时间无运动（未超总超时）【信息级】/ No motion during arming, info level
    DL_PHM_INFO_POS    : UDINT := 16#0004_01C6; // 0004_01C6 多次事件位置超容差，计数重置【信息级】/ Position inconsistent, count reset, info level
    DL_PHM_NOMOT_TIME  : TIME  := T#10S;    // 静止判定时长（No-motion detect time）[ms]，默认 10 s / No-motion detect time, default 10 s
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF / CASE 分支内）
//      Unconditional per-cycle refresh of every instance (R7/0.5)
// ============================================================================
_fbTrigArm(CLK := bArm);                        // 布防上升沿（Arm rising edge）
_bArmReq := _fbTrigArm.Q AND (NOT _bArmConsumed);   // 布防单拍请求（R25 置位点）/ Arm one-shot request
_fbTrigArmFall(CLK := NOT bArm);                // 撤防下降沿（Arm falling edge）
_fbTrigRefEvt(CLK := bRefEvent);                // 参考事件上升沿（Reference event rising edge）
_fbTrigReset(CLK := bReset);                    // 复位上升沿（Reset rising edge）
_bResetEdge := _fbTrigReset.Q;                  // 复位单拍标志紧随实例赋值（R25 自清点）

_fbTonArmTimeout(
    IN := ((_ePhase = E_DL_PassiveHomePhase.eArmed) OR (_ePhase = E_DL_PassiveHomePhase.eCaptured))
          AND (NOT _bArmBreak),                 // 断输入拍串入 IN（R40 合规指纹）/ Segment break folded into IN
    PT := tArmTimeout
);                                              // 布防总超时（Arming timeout）
_fbTonNoMotion(
    IN := ((_ePhase = E_DL_PassiveHomePhase.eArmed) OR (_ePhase = E_DL_PassiveHomePhase.eCaptured))
          AND (NOT bInMotion) AND (NOT _bArmBreak), // 静止且布防中（Stationary while armed）
    PT := DL_PHM_NOMOT_TIME
);                                              // 静止监视（No-motion watch）

// 本拍码与条件预置（每拍重算，杜绝跨拍残留）
// Per-scan preset of codes and conditions, no cross-scan residue
_uFaultCode := _uFaultLatched;                  // 故障码以上拍锁存续用（Carry the latched fault code）
_uInfoCode  := 16#0000_0000;                    // 信息级码预清零（Info code preset to zero）
_bFaultCond := FALSE;                           // 故障条件预清零（Fault condition preset FALSE）

// ============================================================================
// 段 2｜复位通道（R39：置于 CASE 之前，且不被掉使能分支屏蔽）
//      Reset path, before CASE and never masked by the disable branch
// ============================================================================
IF _bResetEdge THEN
    _bRefLatched     := FALSE;                  // 参考点锁存清除（Reference latch cleared）
    _fRefPosHeld     := 0.0;                    // 参考位置保持值清零（Held reference position cleared）
    _fOffsetHeld     := 0.0;                    // 偏移保持值清零（Held offset cleared）
    _nEventCount     := 0;                      // 事件计数清零（Event count cleared）
    _nRequireRemain  := 0;                      // 倒计清零（Countdown cleared）
    _fRefSum         := 0.0;                    // 位置累加清零（Position sum cleared）
    _fRefMean        := 0.0;                    // 位置均值清零（Mean cleared）
    _bDirKnown       := FALSE;                  // 方向记录清除（Direction record cleared）
    _bArmConsumed    := FALSE;                  // 布防消费标志清除（Arm consumed flag cleared）
    _uFaultLatched   := 16#0000_0000;           // 故障码锁存清除（Latched fault code cleared）
    _uFaultCode      := 16#0000_0000;           // 本拍故障码随复位清空，防止段8 重新锁存旧码（Clear this scan code）
    IF _ePhase = E_DL_PassiveHomePhase.eFault THEN
        _ePhase      := E_DL_PassiveHomePhase.eIdle;    // 故障态回空闲（Fault phase back to idle）
        _uFaultCode  := 16#0000_0000;           // 故障码随复位清除（Fault code cleared）
        _bFaultCond  := FALSE;                  // 故障条件随复位清除（Fault condition cleared）
    END_IF
END_IF

// ============================================================================
// 段 3｜撤防受理与断输入拍自清（R40：断输入标志在此无条件复位）
//      Disarm handling plus the unconditional self-clear of the segment break
// ============================================================================
IF _bArmBreak THEN
    _bArmBreak := FALSE;                        // 断输入拍自清（Segment break self-cleared after one scan）
END_IF

IF _fbTrigArmFall.Q THEN
    _bArmConsumed   := FALSE;                   // 撤防允许再次布防（Disarm re-enables arming）
    _nEventCount    := 0;                       // 本轮计数作废（Counts voided）
    _nRequireRemain := 0;                       // 倒计作废（Countdown voided）
    _fRefSum        := 0.0;                     // 累加作废（Sum voided）
    _bDirKnown      := FALSE;                   // 方向记录作废（Direction record voided）
    // 撤防只改「相位显示」，且显式排除故障态与已确认态（R39 合法写法①）
    // Disarm only touches the diagnostic phase and explicitly excludes fault and confirmed
    IF (_ePhase <> E_DL_PassiveHomePhase.eFault) AND (_ePhase <> E_DL_PassiveHomePhase.eConfirmed) THEN
        _ePhase := E_DL_PassiveHomePhase.eIdle; // 回空闲（Back to idle）
    END_IF
END_IF

// ============================================================================
// 段 4｜参数钳位 + 输入防御 + 镜像量锁定（R38：每拍只锁一次，后续只读快照）
//      Parameter clamping, input defense and the single per-scan snapshot (R38)
// ============================================================================
_fVelMinEff  := LIMIT(DL_PHM_VMIN_LO, fVelMin, DL_PHM_VMIN_HI);      // 速度窗下限钳位（Window low clamped）
_fVelMaxEff  := LIMIT(DL_PHM_VMAX_LO, fVelMax, DL_PHM_VMAX_HI);      // 速度窗上限钳位（Window high clamped）
_fConsTolEff := LIMIT(DL_PHM_TOL_LO, fConsistencyTol, DL_PHM_TOL_HI); // 一致性容差钳位（Tolerance clamped）
_nReqEff     := nRequireEvents;             // 事件次数直取引脚（Required events taken as-is）
IF _nReqEff < DL_PHM_EVT_MIN THEN
    _nReqEff := DL_PHM_EVT_MIN;             // 下限钳位（Lower clamp）
ELSIF _nReqEff > DL_PHM_EVT_MAX THEN
    _nReqEff := DL_PHM_EVT_MAX;             // 上限钳位（Upper clamp）
END_IF
IF _fVelMinEff > _fVelMaxEff THEN
    _fVelAbs     := _fVelMinEff;            // 借道交换（Borrow the scratch variable to swap）
    _fVelMinEff  := _fVelMaxEff;            // 下限取原上限（Low takes the former high）
    _fVelMaxEff  := _fVelAbs;               // 上限取原下限（High takes the former low）
END_IF

// 输入防御：位置/速度必须落在域内且有限（NaN/Inf 自比不等，等价式判据）
// Input defense: position and velocity must be finite and inside the domain
IF (NOT (fActPos >= (-DL_PHM_POS_MAX) AND fActPos <= DL_PHM_POS_MAX))
OR (NOT (fActVel >= (-DL_PHM_VEL_MAX) AND fActVel <= DL_PHM_VEL_MAX)) THEN
    IF bEnable THEN
        _bFaultCond := TRUE;                // 非有限值即故障（Non-finite input is a fault）
        _uFaultCode := DL_PHM_ERR_NONFIN;   // 0004_02D3 位置或速度非有限【故障级】/ Non-finite input, fault level
    END_IF
    _fPosSnap := 0.0;                       // 快照置零，绝不用脏值（Snapshot zeroed, never the dirty value）
    _fVelSnap := 0.0;                       // 快照置零（Velocity snapshot zeroed）
ELSE
    _fPosSnap := fActPos;                   // 位置快照锁定（Position snapshot latched）
    _fVelSnap := fActVel;                   // 速度快照锁定（Velocity snapshot latched）
END_IF
_fVelAbs := ABS(_fVelSnap);                 // 速度绝对值（Absolute velocity from the snapshot）

// ============================================================================
// 段 5｜布防受理（R34 倒计置位点；R41：每次布防计数从 0 重建）
//      Arming acceptance: the countdown is preset here (R34) and rebuilt from zero (R41)
// ============================================================================
IF _bArmReq AND (NOT _bArmConsumed) AND bEnable
AND (_ePhase <> E_DL_PassiveHomePhase.eFault) THEN
    _bArmConsumed   := TRUE;                // 消费布防请求（Arm request consumed, R25 自清点）
    _ePhase         := E_DL_PassiveHomePhase.eArmed;    // 进布防相位（Enter armed phase）
    _nEventCount    := 0;                   // 计数从 0 重建，不沿用上次部分计数（R41）
    _fRefSum        := 0.0;                 // 累加从 0 重建（Sum rebuilt from zero）
    _bDirKnown      := FALSE;               // 方向记录清除（Direction record cleared）
    _nRequireRemain := _nReqEff;            // 倒计置位（R34 置位点，与段6 递减点相邻）
    _bArmBreak      := TRUE;                // 布防首拍断定时器输入一拍（R40）
END_IF

// ============================================================================
// 段 6｜参考事件受理（R34 倒计递减点，紧跟段5；三判据顺序：方向 → 位置一致性 → 采信）
//      Reference event acceptance: direction, position consistency, then capture (R34)
// ============================================================================
IF _fbTrigRefEvt.Q AND bEnable AND (NOT _bFaultCond)
AND ((_ePhase = E_DL_PassiveHomePhase.eArmed) OR (_ePhase = E_DL_PassiveHomePhase.eCaptured)) THEN
// 本拍故障（非有限）或掉使能时拒绝受理事件：快照已被置零，采信会把脏值写进结论锁存（v1.0.1 修复）
// Events are rejected on a faulted or disabled scan: the snapshot is zeroed and must never be captured

    // 6.1 方向一致性：与上次事件方向相反 → 计数重置（本条同时覆盖「反向拖动」场景）
    //     Direction consistency: a reversal resets the count
    IF _bDirKnown AND (bDirForward <> _bLastDir) THEN
        _uInfoCode      := DL_PHM_INFO_DIR;     // 0004_01C4 方向反转计数重置【信息级】/ Direction reversed, info level
        _nEventCount    := 0;                   // 计数重置（Count reset）
        _fRefSum        := 0.0;                 // 累加重置（Sum reset）
        _nRequireRemain := _nReqEff;            // 倒计重装（Countdown reloaded）
    END_IF

    // 6.2 位置一致性：与已捕获事件的均值偏差超容差 → 计数重置，本次作为首个新事件
    //     Position consistency: a deviation beyond tolerance restarts the count
    IF (_nEventCount >= DL_PHM_EVT_MIN_P) AND (ABS(_fPosSnap - _fRefMean) > _fConsTolEff) THEN
        _uInfoCode      := DL_PHM_INFO_POS;     // 0004_01C6 位置超容差计数重置【信息级】/ Position inconsistent, info level
        _nEventCount    := 0;                   // 计数重置（Count reset）
        _fRefSum        := 0.0;                 // 累加重置（Sum reset）
        _nRequireRemain := _nReqEff;            // 倒计重装（Countdown reloaded）
    END_IF

    // 6.3 采信本事件（速度窗越界不拒绝，只降精度并置信息码）
    //     Capture this event, the velocity window only degrades the precision
    _fRefSum        := _fRefSum + _fPosSnap;    // 位置累加（Position accumulated）
    _nEventCount    := _nEventCount + 1;        // 事件计数 +1（Event counted）
    _nRequireRemain := _nRequireRemain - 1;     // 倒计递减（R34 递减点，与段5 置位点相邻）
    _bDirKnown      := TRUE;                    // 方向记录建立（Direction recorded）
    _bLastDir       := bDirForward;             // 记住本次方向（Remember this direction）
    IF (_fVelAbs < _fVelMinEff) OR (_fVelAbs > _fVelMaxEff) THEN
        _uInfoCode := DL_PHM_INFO_VEL;          // 0004_01C3 速度窗越界精度降级【信息级】/ Velocity window exceeded, info level
    END_IF

    // 6.4 均值重算与结论仲裁（均值取全部已捕获事件，非取首个，见偏离留档①以外的设计要点）
    //     Recompute the mean over every captured event, then arbitrate the verdict
    IF _nEventCount > 0 THEN
        _fRefMean := _fRefSum / INT_TO_REAL(_nEventCount);  // 事件均值（Mean of captured positions），除零已由计数守卫
    END_IF
    IF _nRequireRemain <= 0 THEN
        _bRefLatched := TRUE;                   // 参考点锁存（Reference latched）
        _fRefPosHeld := _fRefMean;              // 参考位置取均值（Reference position takes the mean）
        _fOffsetHeld := 0.0 - _fRefMean;        // 偏移 = 0.0 − 参考（Offset = 0.0 minus the reference）
        _ePhase      := E_DL_PassiveHomePhase.eConfirmed;   // 进已确认相位（Enter confirmed）
    ELSE
        _ePhase := E_DL_PassiveHomePhase.eCaptured;         // 进已捕获相位（Enter captured）
    END_IF
END_IF

// ============================================================================
// 段 7｜状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      State machine with an explicit ELSE fallback
// ============================================================================
IF _bFaultCond THEN
    _ePhase := E_DL_PassiveHomePhase.eFault;    // 非有限值优先于状态机（Non-finite input outranks the machine）
END_IF

// 掉使能冻结分支：显式排除故障态（R39 合法写法①），复位通道仍可从故障态退出
// Disable branch explicitly excludes the fault state so the reset path still works
IF (NOT bEnable) AND (_ePhase <> E_DL_PassiveHomePhase.eFault) THEN
    _ePhase      := E_DL_PassiveHomePhase.eIdle;    // 冻结回空闲（Freeze back to idle）
    _bArmConsumed := FALSE;                 // 允许重新布防（Arming re-enabled）
    _nEventCount := 0;                      // 计数作废（Counts voided）
    _nRequireRemain := 0;                   // 倒计作废（Countdown voided）
END_IF

CASE _ePhase OF

    E_DL_PassiveHomePhase.eIdle: // 空闲：布防受理已在段5 完成，本分支只保留标签
        // 布防动作在 CASE 之前完成（R39 前置纪律），此处保留空标签与原因注释（R31）
        // Arming happens before CASE, so this label stays empty with its reason (R31)

    E_DL_PassiveHomePhase.eArmed: // 已布防：等首个事件或超时
        IF _fbTonArmTimeout.Q THEN
            _uFaultCode  := DL_PHM_ERR_TIMEOUT;     // 0004_02D2 布防超时【故障级】/ Arm timeout, fault level
            _bFaultCond  := TRUE;                   // 置故障条件（Raise the fault condition）
            _ePhase      := E_DL_PassiveHomePhase.eTimeout; // 进超时相位（Enter timeout）
            _bArmConsumed := FALSE;                 // 允许重新布防（Arming re-enabled）
            _nRequireRemain := 0;                   // 倒计作废（Countdown voided）
        ELSIF _fbTonNoMotion.Q THEN
            _uInfoCode := DL_PHM_INFO_NOMOT;        // 0004_01C5 布防期间长时间无运动【信息级】/ No motion while armed, info level
        END_IF

    E_DL_PassiveHomePhase.eCaptured: // 已捕获：等后续一致性事件或超时
        IF _fbTonArmTimeout.Q THEN
            _uFaultCode  := DL_PHM_ERR_TIMEOUT;     // 0004_02D2 布防超时【故障级】/ Arm timeout, fault level
            _bFaultCond  := TRUE;                   // 置故障条件（Raise the fault condition）
            _ePhase      := E_DL_PassiveHomePhase.eTimeout; // 进超时相位（Enter timeout）
            _bArmConsumed := FALSE;                 // 允许重新布防（Arming re-enabled）
            _nRequireRemain := 0;                   // 倒计作废（Countdown voided）
        ELSIF _fbTonNoMotion.Q THEN
            _uInfoCode := DL_PHM_INFO_NOMOT;        // 0004_01C5 布防期间长时间无运动【信息级】/ No motion while armed, info level
        END_IF

    E_DL_PassiveHomePhase.eConfirmed: // 已确认：结论逐拍在段9 重写，本分支只保留标签
        // 结论保持由段9 逐拍重写承担（R27），此处保留空标签与原因注释（R31）
        // The held verdict is rewritten in segment 9, so this label stays empty (R31)

    E_DL_PassiveHomePhase.eTimeout: // 超时：等重新布防（段5 受理）或复位
        // 重新布防在段5 受理，复位在段2 受理，此处保留空标签与原因注释（R31/R41）
        // Re-arming is accepted in segment 5 and reset in segment 2 (R31/R41)

    E_DL_PassiveHomePhase.eFault: // 故障：等复位沿（段2）
        // 复位通道位于 CASE 之前，此分支无需动作（R39）
        // The reset path sits before CASE, so no action is needed here (R39)

    ELSE // 兜底：非法状态
        _uFaultCode := DL_PHM_ERR_STATE;        // 0004_02D4 非法状态兜底【故障级】/ Illegal state fallback
        _bFaultCond := TRUE;                    // 置故障条件（Raise the fault condition）
        _ePhase     := E_DL_PassiveHomePhase.eFault;    // 强制回故障态（Force the fault state）
END_CASE

// ============================================================================
// 段 8｜码位单一优先级链（全拍只写一次，信息级不置 bError）
//      Single priority chain for the codes, written once per scan
// ============================================================================
IF _uFaultCode <> 16#0000_0000 THEN
    _uFaultLatched := _uFaultCode;              // 故障码锁存，跨拍保持至复位（Latched until reset）
    uErrorId  := _uFaultCode;                   // 故障级码优先（Fault-level code wins）
    uDiagCode := _uFaultCode;                   // 诊断码同源（Diagnostic code mirrors the fault）
    bError    := TRUE;                          // 故障标志置位（Error flag raised）
ELSIF _uInfoCode <> 16#0000_0000 THEN
    uErrorId  := 16#0000_0000;                  // 信息级不占故障码（Info level leaves the fault code empty）
    uDiagCode := _uInfoCode;                    // 诊断码取信息级码（Diagnostic code takes the info code）
    bError    := FALSE;                         // 信息级不置故障位（Info level never raises the error flag）
ELSE
    uErrorId  := 16#0000_0000;                  // 无码（No code）
    uDiagCode := 16#0000_0000;                  // 无码（No code）
    bError    := FALSE;                         // 无故障（No error）
END_IF

// ============================================================================
// 段 9｜出口钳位与保持语义重写（R27/R43：结论逐拍重写，每条路径一次钳位）
//      Output clamping and held-semantics rewrite (R27/R43)
// ============================================================================
bReferenced    := _bRefLatched;                                             // 参考点保持位逐拍重写（Referenced held, rewritten each scan）
fRefPos        := LIMIT(-DL_PHM_OFF_MAX, _fRefPosHeld, DL_PHM_OFF_MAX);     // 参考位置夹进 ±1.0E6（Reference position clamped）
fOffsetToApply := LIMIT(-DL_PHM_OFF_MAX, _fOffsetHeld, DL_PHM_OFF_MAX);     // 偏移夹进 ±1.0E6（Offset clamped）
nEventCount    := INT_TO_UINT(_nEventCount);                                // 事件计数逐拍重写（Event count rewritten）
ePhase         := _ePhase;                                                  // 相位仅供诊断（Phase for diagnostics only）

// 健康态仲裁（引用属主 A1 的四态语言）
// Health arbitration mapped onto the A1 health language
IF _ePhase = E_DL_PassiveHomePhase.eFault THEN
    eHealth := E_DL_Ne107Status.eFailure;       // 故障：信号不可信（Failure）
ELSIF NOT bEnable THEN
    eHealth := E_DL_Ne107Status.eUnknown;       // 未知：未使能（Unknown）
ELSIF _ePhase = E_DL_PassiveHomePhase.eTimeout THEN
    eHealth := E_DL_Ne107Status.eOutOfSpec;     // 越规：布防未取到参考点（Out of spec）
ELSIF _ePhase = E_DL_PassiveHomePhase.eIdle THEN
    eHealth := E_DL_Ne107Status.eUnknown;       // 未知：未布防（Unknown）
ELSE
    eHealth := E_DL_Ne107Status.eOk;            // 正常：监听中或已确认（OK）
END_IF

END_FUNCTION_BLOCK
