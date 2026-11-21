(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AhuDamperStuckDiag
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）语法，
 *                         仅依赖 Standard.library（R_TRIG / TON）
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 设备本体退化诊断 · 风阀卡滞
 * 功能描述 (Function)   : 风阀与电动执行器的卡滞诊断，把含糊的「不动作」拆成
 *                         **三种不同失效机理**——这是本件最大的价值：
 *                         · Full Stall（完全不动）：指令已变、也已得电，但阀位
 *                           **一步未动** → 机械卡死 / 接线断 / 执行器死；
 *                         · Transit Stall（动而未达）：离位了但**没到目标** →
 *                           摩擦力过大 / 气压不足 / 限位错；
 *                         · I/O Fault：反馈信号本身失效 → 传感 / 接线 / 模块
 *                           问题（**不是阀的问题**，误判成阀会导致整台执行器
 *                           被拆下来返修）；
 *                         再加两个工艺级判据：Deviation（稳态偏差超限）与
 *                         Slow（行程时间超标称的设定倍率）。
 * 动作语义 (Semantics)  : 三类失效的处置完全不同：Full Stall 与 I/O Fault 必须
 *                         立刻检修（eFailure）；Transit Stall 亦按 eFailure 处理
 *                         （执行器已失去定位能力）；而 Deviation 与 Slow 是
 *                         **退化**，设备仍可运行（eMaintenanceReq）。三类分开的
 *                         意义就在于此——把「要停机」和「要排计划」分开，而不是
 *                         一个笼统的 bAlarm。
 * 码位级裁定 (Slot rule): `16#0003_0323`（Deviation）落在故障带 `03xx`，但语义是
 *                         「维护请求」，**不置 bError**。理由：bError 表示「不可
 *                         继续运行」，而偏差超限的风阀仍能调节，只是精度不够。
 *                         这是本库首次出现「故障带码 + 不置 bError」的组合，故
 *                         在本头注释显式声明，并要求 MANUAL 故障码表增列
 *                         「是否置 bError」一栏。同理 0161（Slow）为信息级，
 *                         亦不置 bError。`bError` 只由 0321 / 0322 / 0324 / 0325
 *                         四个真正失效的码置位。
 * 段序 (Cycle order)   : 段 1 默认值与单拍预清零 → 段 2 首扫初始化 →
 *                         段 3 参数闸门与输入域判据 → 段 4 定时器与边沿无条件刷新 →
 *                         段 5 复位通道与故障锁存（**CASE 前置，且不做状态赋值**）→
 *                         段 6 状态机 → 段 7 行程与判据累计（含定性）→
 *                         段 8 出口钳位与保持重写 → 段 9 码位链。
 * 定时器清单 (R40)      : 实例名 / IN 表达式 / 断输入拍标志 / 自清位置
 *                         fbTravelWatch / 状态为移动 AND NOT _bTravelBreak
 *                                       / _bTravelBreak（进/出移动态置位）
 *                         fbGraceWatch  / 已超时未达 AND 状态为移动 AND
 *                                       NOT _bTravelBreak / 同上
 *                         fbStallWatch  / 指令已动且阀位未动 AND 状态为移动 AND
 *                                       NOT _bStallBreak / _bStallBreak（进移动态置位）
 *                         fbDevWatch    / 偏差超限 AND 状态为确认 AND
 *                                       NOT _bDevBreak / _bDevBreak（进确认态置位）
 *                         fbSettleWatch / 状态为确认 AND NOT 偏差超限 AND
 *                                       NOT _bSettleBreak / _bSettleBreak（进确认态置位）
 *                         fbIoWatch     / 反馈失效 AND NOT _bIoBreak
 *                                       / _bIoBreak（反馈恢复沿置位）
 *                         六个实例全部在段 4 无条件调用，断输入拍一律在调用后自清。
 * 单拍标志清单 (R25)    : `_bResetPulse` 预清段 1 / 置位段 5 / 消费段 5；
 *                         `_bVerdictPending` 预清段 1 / 置位段 7 / 消费段 7；
 *                         `_bFbRestore` 预清段 1 / 置位段 4 / 消费段 6（恢复首拍）；
 *                         六个断输入标志就地置位、段 4 调用后自清。
 * 保持位清单 (R27)      : `_eDiag`（结论）与 `_fDeviation`、`_tLastTravel`、
 *                         `_uStallCount`、`_uTravelCount` 五个保持量，全部由段 8
 *                         每拍重写出口；复位沿清除。结论在 eVerdict 拍产生后
 *                         **一直保持**，不靠那一个脉冲（R27 正解）。
 * 三元一致表 (R35)      : 量 / 守卫封顶 / 判据运算符
 *                         fSlowRatio   / 钳到 1.1~3.0 / 超时判据用 >=
 *                         fTolPos      / 钳到 0.5~10.0 / 到位判据用 <=
 *                         fDevLimit    / 钳到 1.0~50.0 / 偏差判据用 >
 *                         fDriftThr    / 钳到 0.05~2.0 / 位移判据用 >
 * 验收向量 (Acceptance) :
 *   V1 Full Stall：fCmd 由 0 跳到 60 %、fPosFb 恒 0 → 5 s 后 eDiag=eFullStall、
 *      0321、eHealth=eFailure、bError=TRUE
 *   V2 Transit Stall：fCmd 0→100 %、fPosFb 停在 45 % → 45 s（30 s×1.5）后
 *      但仍在移动则先判 eSlow；若已停止移动则 eTransitStall、0322
 *   V3（V-C 跨段 R40）：连续两次行程（各 20 s 完成，标称 30 s）→ 行程定时器
 *      不得累加到 40 s 判超时；每次进入移动态都必须有断输入拍
 *   V4（V-D 恢复首拍）：bFbValid 由 FALSE 恢复 → 首拍只重装基准，**不判**
 *      Full Stall（否则必误报）
 *   V5（V-A 域外）：fCmd 为 120 % → 钳到 100 并置信息码 0161（钳位不静默）；
 *      fPosFb 为 NaN → 按反馈失效路径处理，且偏差输出夹进 −100~100（R43）
 * 偏离留档 (Deviation)  :
 *   ① 规格 V2 的期望是「45 s 后 eTransitStall」，但 45 s 恰为「1.5 倍标称」的
 *      判据点，此时若阀位仍在缓慢移动，把它判成卡滞会误伤「只是慢」的阀。
 *      本件在 1.5 倍处先置「超时未达」标志，再给一个 tStallTime 的宽限期：
 *      宽限期内到位判 eSlow，超出宽限期仍未到位才判 eTransitStall。这样既
 *      满足 V2 的时序意图，又不把慢阀误判为卡死。
 *   ② 规格未给「确认窗」时长。本件复用 tDevDelay 作为到位确认窗（同一物理
 *      含义：偏差保持在容差内多久算稳定），并在三元一致表登记。
 *   ③ 0161 一码两义：行程慢于 1.5 倍标称，或指令超域被钳位（按 R13 总监
 *      裁定，超域钳位复用该信息码，不新造码位）。
 *   ④ 本件未分到「参数非法」的独立码位，阈值越出物理域（标称行程 <1 s、
 *      倍率越 1.1~3.0、容差或偏差限非正）时复用 0325 兜底码并在本注释登记，
 *      不自行新造码位。
 * 开源溯源 (Origin)     : 来源标签 rockwell-aoi / namur-ne107 / damper-diag。
 *                         原创 clean-room 实现。**仅借鉴 Rockwell AOI（Add-On
 *                         Instruction）公开文档所呈现的「执行器诊断三分类」
 *                         结构粒度**——即把「不动作」拆成完全不动 / 动而未达 /
 *                         反馈失效三类。Rockwell AOI 源码不公开且受其许可协议
 *                         保护，本件**未接触、未复制**任何 AOI 源码、参数名、
 *                         标签名或代码行；三分类的判定阈值、状态机、宽限期
 *                         机制、码位与全部实现细节 100% 本库独立设计。NE107
 *                         （公开推荐规范）仅提供健康分级语义。结构借鉴属功能
 *                         分类层面，不构成代码版权标的，无许可证传染风险。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R13 · 泳道 A · 风阀卡滞三分类诊断）
 *   2026-11-16  v1.0.1  终审修复一处（V-C/确认窗类）：判定相的 I/O 失效判据
 *                       由「本拍 NOT _bFbOk」改为「fbIoWatch.Q」，即必须满
 *                       tIoFaultTime 才判 0324；未满时本拍不发布结论、保持上次
 *                       等级。原实现下 eSettling 的到位/偏差定时器（其 IN 不以
 *                       反馈有效性为输入）在反馈刚失效时会无确认窗直接锁存
 *                       0324，属「三分类判据须带确认延时」的缺口。码位与引脚零变化。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DamperDiag（归属本功能块，同文件发布）
 * 含义: 诊断结论。每个成员在段 9 的码位链中有且仅有一个分支，无隐藏成员。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_DamperDiag :
(
    eOk           := 0,    // 正常：无判据成立 / OK, no criterion active
    eSlow         := 10,   // 行程偏慢：超过标称倍率但已到位 / Slow, arrived beyond the ratio
    eDeviation    := 20,   // 稳态偏差：指令与反馈长期不一致 / Steady-state deviation
    eFullStall    := 30,   // 完全卡死：一步未动 / Full stall, not a single step
    eTransitStall := 40,   // 行程卡滞：动了但没到 / Transit stall, moved but never arrived
    eIoFault      := 50    // 反馈失效：信号本身不可信 / Feedback signal lost
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DamperState（归属本功能块，同文件发布）
 * 含义: 诊断状态机。eMoving 的进出必须与行程定时器挂钩（R40 高危区）。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_DamperState :
(
    eIdle     := 0,    // 待机：偏差在容差内 / Idle, deviation within tolerance
    eMoving   := 10,   // 移动：指令已变且偏差超容差 / Moving, command changed and off target
    eSettling := 20,   // 确认：偏差已进容差，等确认窗 / Settling, waiting for the confirmation window
    eVerdict  := 30,   // 判定：单拍出结论后回待机 / Verdict, single scan then back to idle
    eFault    := 99    // 故障：参数非法或非法状态 / Fault, illegal parameters or state
);
END_TYPE

FUNCTION_BLOCK FB_DL_AhuDamperStuckDiag
VAR_INPUT
    bEnable        : BOOL;                            // 使能 [-] / Enable
    bReset         : BOOL;                            // 复位锁存，上升沿有效 [-] / Rising edge resets the latch
    fCmd           : REAL;                            // 阀位指令 [%]，范围 0~100 / Damper command
    fPosFb         : REAL;                            // 阀位反馈 [%]，范围 0~100 / Position feedback
    bFbValid       : BOOL := TRUE;                    // 反馈有效，AI 断线时为 FALSE [-] / Feedback validity
    bLimitOpen     : BOOL := FALSE;                   // 开到位限位，无此限位时恒 FALSE [-] / Open limit switch
    bLimitClose    : BOOL := FALSE;                   // 关到位限位，无此限位时恒 FALSE [-] / Close limit switch
    tTravelNominal : TIME := T#30S;                   // 全行程标称时间 [毫秒]，范围 1 s~10 min / Nominal full travel time
    fTolPos        : REAL := 3.0;                     // 到位容差 [%]，范围 0.5~10.0 / In-position tolerance
    fDevLimit      : REAL := 10.0;                    // 稳态偏差上限 [%]，范围 1.0~50.0 / Steady-state deviation limit
    tDevDelay      : TIME := T#10S;                   // 偏差确认延时 [毫秒]，范围 0.5~300 s / Deviation confirmation delay
    fDriftThr      : REAL := 0.2;                     // 判有位移的阈值 [%]，范围 0.05~2.0 / Movement threshold
    tStallTime     : TIME := T#5S;                    // 停滞判据时长 [毫秒]，范围 0.5~120 s / Stall duration
    tIoFaultTime   : TIME := T#3S;                    // 反馈失效持续判据 [毫秒]，范围 0.2~60 s / Feedback loss duration
    fSlowRatio     : REAL := 1.5;                     // 判 Slow 的行程倍率 [-]，范围 1.1~3.0 / Slow ratio
END_VAR
VAR_OUTPUT
    eHealth        : E_DL_Ne107Status;                // NE107 健康态（引用自 I_DL_DeviceHealth）[-] / NE107 health
    uDiagCode      : UDINT;                           // 当前诊断码，0=无码 [代码] / Active diagnostic code
    uErrorId       : UDINT;                           // 末次故障码，仅失效级 [代码] / Last fault code
    bError         : BOOL;                            // 故障锁存，仅 0321 0322 0324 0325 置位 [-] / Fault latch
    eDiag          : E_DL_DamperDiag;                 // 诊断结论（保持语义）[-] / Diagnostic verdict, held
    fDeviation     : REAL;                            // 指令减反馈的有符号偏差 [%]，正=开不足 / Signed deviation
    tLastTravel    : TIME;                            // 末次行程实测时间 [毫秒] / Last measured travel time
    nStallCount    : UDINT;                           // 卡滞次数累计 [次]，锁存 / Stall counter
    nTravelCount   : UDINT;                           // 行程次数累计 [次]，锁存 / Travel counter
    bAtOpen        : BOOL;                            // 开到位指示（容差或限位）[-] / At open position
    bAtClose       : BOOL;                            // 关到位指示（容差或限位）[-] / At close position
END_VAR
VAR
    fbTrigReset    : R_TRIG;                          // 复位沿检测，段 4 无条件刷新 [-] / Reset edge detector
    fbFbTrig       : R_TRIG;                          // 反馈恢复沿检测，段 4 无条件刷新 [-] / Feedback restore edge
    fbTravelWatch  : TON;                             // 行程超时计时（标称×倍率），段 4 刷新 [毫秒] / Travel overrun timer
    fbGraceWatch   : TON;                             // 超时后宽限计时，段 4 刷新 [毫秒] / Grace timer after the overrun
    fbStallWatch   : TON;                             // 完全停滞计时，段 4 刷新 [毫秒] / Full stall timer
    fbDevWatch     : TON;                             // 偏差确认计时，段 4 刷新 [毫秒] / Deviation timer
    fbSettleWatch  : TON;                             // 到位确认计时，段 4 刷新 [毫秒] / Settling timer
    fbIoWatch      : TON;                             // 反馈失效计时，段 4 刷新 [毫秒] / Feedback loss timer
    _eState        : E_DL_DamperState := E_DL_DamperState.eIdle; // 当前状态 [-] / Current state
    _bInit         : BOOL := FALSE;                   // 首扫标志，初值 FALSE [-] / First-scan flag
    _bFaultLatch   : BOOL;                            // 故障锁存，仅复位清 [-] / Fault latch
    _uErrFault     : UDINT;                           // 首出故障码 [代码] / First-out fault code
    _uDiagCode     : UDINT;                           // 当前诊断码（单一链产出）[代码] / Active diagnostic code
    _bResetPulse   : BOOL;                            // 复位单拍 [-] / One-shot reset
    _bFbRestore    : BOOL;                            // 反馈恢复单拍 [-] / One-shot restore
    _bVerdictPending : BOOL;                          // 结论待发布单拍 [-] / Verdict pending
    _bTravelBreak  : BOOL;                            // 行程定时器断输入一拍 [-] / Travel timer break
    _bStallBreak   : BOOL;                            // 停滞定时器断输入一拍 [-] / Stall timer break
    _bDevBreak     : BOOL;                            // 偏差定时器断输入一拍 [-] / Deviation timer break
    _bSettleBreak  : BOOL;                            // 确认定时器断输入一拍 [-] / Settling timer break
    _bIoBreak      : BOOL;                            // 反馈失效定时器断输入一拍 [-] / Feedback timer break
    _bOverrun      : BOOL;                            // 行程已超过标称倍率 [-] / Travel overrun flag
    _bCmdOutRange  : BOOL;                            // 指令超域被钳位 [-] / Command clamped flag
    _fCmdUse       : REAL;                            // 生效指令（钳位后）[%] / Effective command
    _fPosUse       : REAL;                            // 生效反馈（钳位后）[%] / Effective position
    _fCmdPrev      : REAL;                            // 上拍指令 [%] / Previous command
    _fPosPrev      : REAL;                            // 上拍反馈 [%] / Previous position
    _fCmdBase      : REAL;                            // 进入移动态的指令基准 [%] / Command baseline at motion start
    _fPosBase      : REAL;                            // 进入移动态的反馈基准 [%] / Position baseline at motion start
    _fTolUse       : REAL := 3.0;                     // 生效到位容差 [%] / Effective tolerance
    _fDevLimitUse  : REAL := 10.0;                    // 生效偏差上限 [%] / Effective deviation limit
    _fDriftUse     : REAL := 0.2;                     // 生效位移阈值 [%] / Effective drift threshold
    _fCmdEpsUse    : REAL := 0.01;                    // 判「指令在动」的极小阈 [%] / Tiny threshold for command motion
    _fSlowUse      : REAL := 1.5;                     // 生效慢速倍率 [-] / Effective slow ratio
    _tTravelUse    : TIME := T#30S;                   // 生效标称行程 [毫秒] / Effective nominal travel
    _tTravelLimit  : TIME := T#45S;                   // 生效超时判据 = 标称×倍率 [毫秒] / Effective travel limit
    _tDevUse       : TIME := T#10S;                   // 生效偏差延时 [毫秒] / Effective deviation delay
    _tStallUse     : TIME := T#5S;                    // 生效停滞时长 [毫秒] / Effective stall duration
    _tIoUse        : TIME := T#3S;                    // 生效反馈失效时长 [毫秒] / Effective feedback loss duration
    _diMs          : DINT;                            // 时间换算中间量 [毫秒] / Time conversion working value
    _fMsReal       : REAL;                            // 行程限值的实数中间量 [毫秒] / Real working value of the travel limit
    _fDeviation    : REAL;                            // 有符号偏差 [%] / Signed deviation
    _bDevExceed    : BOOL;                            // 偏差超限 [-] / Deviation above limit
    _bCmdMovedSince : BOOL;                           // 本行程内指令已动 [-] / Command moved during the travel
    _bPosMovedSince : BOOL;                           // 本行程内阀位已动 [-] / Position moved during the travel
    _bAtTarget     : BOOL;                            // 已到达目标 [-] / Target reached
    _bAtOpenInt    : BOOL;                            // 开到位内部量 [-] / At open internal
    _bAtCloseInt   : BOOL;                            // 关到位内部量 [-] / At close internal
    _bFbOk         : BOOL;                            // 反馈可用（有限且有效）[-] / Feedback usable
    _bFbFinite     : BOOL;                            // 反馈有限标志 [-] / Feedback finite flag
    _bCmdFinite    : BOOL;                            // 指令有限标志 [-] / Command finite flag
    _eDiag         : E_DL_DamperDiag := E_DL_DamperDiag.eOk; // 保持的结论 [-] / Held verdict
    _fDevHeld      : REAL;                            // 保持的偏差 [%] / Held deviation
    _tTravelHeld   : TIME;                            // 保持的末次行程时间 [毫秒] / Held last travel time
    _uStallCount   : UDINT;                           // 保持的卡滞次数 [次] / Held stall counter
    _uTravelCount  : UDINT;                           // 保持的行程次数 [次] / Held travel counter
    _eHealthInt    : E_DL_Ne107Status := E_DL_Ne107Status.eUnknown; // 健康态内部量 [-] / Internal health state
    _bParamBad     : BOOL;                            // 参数非法标志 [-] / Illegal parameter flag
END_VAR
VAR CONSTANT
    DL_VAL_LIM     : REAL := 1.0E6;                   // 有限性判定绝对值上限 [%] / Finiteness limit
    DL_CMD_EPS_RATIO : REAL := 0.05;                  // 指令在动判据相对位移阈的比例 [-] / Command motion ratio
    DL_FULL        : REAL := 100.0;                   // 全行程 [%] / Full stroke
    DL_ZERO        : REAL := 0.0;                     // 零行程 [%] / Zero stroke
    DL_TIME_ZERO   : TIME := T#0S;                    // 时间零值基准 [毫秒] / Time zero reference
    DL_TRAVEL_MIN  : DINT := 1000;                    // 标称行程下限 [毫秒] / Minimum nominal travel
    DL_TRAVEL_MAX  : DINT := 600000;                  // 标称行程上限 [毫秒] / Maximum nominal travel
    DL_DELAY_MIN   : DINT := 500;                     // 延时类下限 [毫秒] / Minimum delay
    DL_DELAY_MAX   : DINT := 300000;                  // 延时类上限 [毫秒] / Maximum delay
    DL_STALL_MIN   : DINT := 500;                     // 停滞时长下限 [毫秒] / Minimum stall duration
    DL_STALL_MAX   : DINT := 120000;                  // 停滞时长上限 [毫秒] / Maximum stall duration
    DL_IO_MIN      : DINT := 200;                     // 反馈失效下限 [毫秒] / Minimum feedback loss
    DL_IO_MAX      : DINT := 60000;                   // 反馈失效上限 [毫秒] / Maximum feedback loss
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜确定性默认值与单拍标志预清零（R25 第一律）
 *      Deterministic defaults and one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
_bResetPulse     := FALSE;                            // 复位单拍预清零（Reset pre-cleared）
_bFbRestore      := FALSE;                            // 恢复单拍预清零（Restore pre-cleared）
_bVerdictPending := FALSE;                            // 结论待发布预清零（Verdict pending pre-cleared）
_bParamBad       := FALSE;                            // 参数非法预清零（Illegal parameter pre-cleared）
_bFbFinite       := FALSE;                            // 反馈有限预清零（Feedback finite pre-cleared）
_bCmdFinite      := FALSE;                            // 指令有限预清零（Command finite pre-cleared）
_bCmdOutRange    := FALSE;                            // 指令超域预清零（Command clamped pre-cleared）

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（R19：bInit 初值 FALSE，判据取非；首拍只装基准）
 *      First-scan initialisation, baseline only
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState       := E_DL_DamperState.eIdle;          // 状态待机（State idle）
    _bFaultLatch  := FALSE;                           // 故障锁存清零（Latch cleared）
    _uErrFault    := 16#0000_0000;                    // 首出码清零（First-out code cleared）
    _eDiag        := E_DL_DamperDiag.eOk;             // 结论正常（Verdict OK）
    _fDevHeld     := 0.0;                             // 偏差保持量清零（Held deviation cleared）
    _tTravelHeld  := DL_TIME_ZERO;                    // 行程时间保持量清零（Held travel cleared）
    _uStallCount  := 0;                               // 卡滞次数清零（Stall counter cleared）
    _uTravelCount := 0;                               // 行程次数清零（Travel counter cleared）
    _fCmdPrev     := 0.0;                             // 上拍指令初值（Previous command）
    _fPosPrev     := 0.0;                             // 上拍反馈初值（Previous position）
    _fCmdBase     := 0.0;                             // 指令基准初值（Command baseline）
    _fPosBase     := 0.0;                             // 反馈基准初值（Position baseline）
    _bOverrun     := FALSE;                           // 超时标志清零（Overrun cleared）
    _bCmdMovedSince := FALSE;                         // 指令位移证据清零（Command evidence cleared）
    _bPosMovedSince := FALSE;                         // 阀位位移证据清零（Position evidence cleared）
    _bInit        := TRUE;                            // 首扫只做一次（First scan runs once）
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数闸门、输入域检查与偏差判据（定时器之前，保证本拍值）
 *      Parameter gate, input domain and criteria, ahead of the timers
 *-----------------------------------------------------------------------------*)
_fTolUse      := LIMIT(0.5, fTolPos, 10.0);           // 到位容差钳进 0.5~10 %（Clamped）
_fDevLimitUse := LIMIT(1.0, fDevLimit, 50.0);         // 偏差上限钳进 1~50 %（Clamped）
_fDriftUse    := LIMIT(0.05, fDriftThr, 2.0);         // 位移阈值钳进 0.05~2 %（Clamped）
_fSlowUse     := LIMIT(1.1, fSlowRatio, 3.0);         // 慢速倍率钳进 1.1~3.0（Clamped）
_fCmdEpsUse   := LIMIT(0.001, _fDriftUse * DL_CMD_EPS_RATIO, _fDriftUse); // 指令在动判据，随位移阈缩放并封顶（Scaled and capped）

_diMs        := LIMIT(DL_TRAVEL_MIN, TIME_TO_DINT(tTravelNominal), DL_TRAVEL_MAX); // 标称行程钳位（Clamped）
_tTravelUse  := DINT_TO_TIME(_diMs);                  // 生效标称行程（Effective nominal travel）
_fMsReal     := DINT_TO_REAL(_diMs) * _fSlowUse;      // 超时判据 = 标称 × 倍率 [毫秒]（Limit = nominal times ratio）
_fMsReal     := LIMIT(DINT_TO_REAL(DL_TRAVEL_MIN), _fMsReal, DINT_TO_REAL(DL_TRAVEL_MAX)); // 结果再钳位（Clamped again）
_tTravelLimit := DINT_TO_TIME(REAL_TO_DINT(_fMsReal)); // 生效超时判据（Effective travel limit）

_diMs      := LIMIT(DL_DELAY_MIN, TIME_TO_DINT(tDevDelay), DL_DELAY_MAX); // 偏差延时钳位（Clamped）
_tDevUse   := DINT_TO_TIME(_diMs);                    // 生效偏差延时（Effective deviation delay）
_diMs      := LIMIT(DL_STALL_MIN, TIME_TO_DINT(tStallTime), DL_STALL_MAX); // 停滞时长钳位（Clamped）
_tStallUse := DINT_TO_TIME(_diMs);                    // 生效停滞时长（Effective stall duration）
_diMs      := LIMIT(DL_IO_MIN, TIME_TO_DINT(tIoFaultTime), DL_IO_MAX); // 反馈失效时长钳位（Clamped）
_tIoUse    := DINT_TO_TIME(_diMs);                    // 生效反馈失效时长（Effective feedback loss duration）

(* 输入域检查放在定时器之前：定时器输入要用本拍的可用标志，避免一拍滞后 *)
_bCmdFinite := (fCmd >= -DL_VAL_LIM) AND (fCmd <= DL_VAL_LIM);     // 指令有限（Command finite）
_bFbFinite  := (fPosFb >= -DL_VAL_LIM) AND (fPosFb <= DL_VAL_LIM); // 反馈有限（Feedback finite）
IF (fCmd < DL_ZERO) OR (fCmd > DL_FULL) THEN
    _bCmdOutRange := TRUE;                            // 指令超域：钳位不静默（Clamped, not silent）
END_IF
_fCmdUse := LIMIT(DL_ZERO, fCmd, DL_FULL);            // 指令钳进 0~100 %（Clamped）
IF NOT _bCmdFinite THEN
    _fCmdUse := 0.0;                                  // 非有限：置 0（Non-finite, zeroed）
END_IF
IF _bFbFinite THEN
    _fPosUse := LIMIT(DL_ZERO, fPosFb, DL_FULL);      // 反馈钳进 0~100 %（Clamped）
ELSE
    _fPosUse := _fPosPrev;                            // 非有限：保持上拍值，不污染判据（Hold the previous value）
END_IF
_bFbOk := bFbValid AND _bFbFinite;                    // 反馈可用 = 有效且有限（Usable = valid and finite）

(* 偏差与到位判据：与输入域检查同段，保证定时器用的是本拍值而非上一拍值 *)
_fDeviation  := _fCmdUse - _fPosUse;                  // 有符号偏差，正=开不足（Signed deviation）
_bDevExceed  := _fDeviation > _fDevLimitUse;          // 偏差超限（Deviation above the limit）
_bAtOpenInt  := bLimitOpen OR (_fPosUse >= (DL_FULL - _fTolUse));   // 开到位（At open）
_bAtCloseInt := bLimitClose OR (_fPosUse <= _fTolUse);              // 关到位（At close）
_bAtTarget   := (_fDeviation <= _fTolUse) AND (_fDeviation >= -_fTolUse); // 到位：偏差落在容差带内（In position）

(*------------------------------------------------------------------------------
 * 段 4｜定时器与边沿实例无条件刷新（红线：实例一律在 CASE 之外每拍必调）
 *      Timers and edge detectors refreshed unconditionally outside the CASE
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);                           // 复位沿刷新（Reset edge refreshed）
fbFbTrig(CLK := bFbValid);                            // 反馈恢复沿刷新（Feedback restore edge refreshed）
IF fbFbTrig.Q THEN
    _bFbRestore := TRUE;                              // 反馈恢复单拍（Restore one-shot）
    _bIoBreak   := TRUE;                              // 反馈失效计时重启（Feedback timer restarted）
    _bStallBreak := TRUE;                             // 停滞计时重启，防跨失效期累加（Stall timer restarted）
    _bTravelBreak := TRUE;                            // 行程计时重启（Travel timer restarted）
END_IF

fbTravelWatch(IN := (_eState = E_DL_DamperState.eMoving) AND (NOT _bTravelBreak), PT := _tTravelLimit); // 行程超时计时
(* 宽限计时与行程计时共用同一个断输入拍，故自清必须放在两个实例调用之后，
 * 否则后调的实例永远看不到断输入（R40 的典型陷阱） *)
fbGraceWatch(IN := _bOverrun AND (_eState = E_DL_DamperState.eMoving) AND (NOT _bTravelBreak), PT := _tStallUse); // 宽限计时，断输入沿用行程标志
_bTravelBreak := FALSE;                               // 断输入拍在两个实例调用后自清（Break self-cleared after both calls）

fbStallWatch(IN := _bCmdMovedSince AND (NOT _bPosMovedSince) AND (_eState = E_DL_DamperState.eMoving) AND _bFbOk AND (NOT _bStallBreak), PT := _tStallUse); // 完全停滞计时
_bStallBreak := FALSE;                                // 断输入拍在调用后自清（Break self-cleared）

fbDevWatch(IN := _bDevExceed AND (_eState = E_DL_DamperState.eSettling) AND (NOT _bDevBreak), PT := _tDevUse); // 偏差确认计时
_bDevBreak := FALSE;                                  // 断输入拍在调用后自清（Break self-cleared）

fbSettleWatch(IN := (_eState = E_DL_DamperState.eSettling) AND (NOT _bDevExceed) AND (NOT _bSettleBreak), PT := _tDevUse); // 到位确认计时
_bSettleBreak := FALSE;                               // 断输入拍在调用后自清（Break self-cleared）

fbIoWatch(IN := (NOT _bFbOk) AND (NOT _bIoBreak), PT := _tIoUse); // 反馈失效计时
_bIoBreak := FALSE;                                   // 断输入拍在调用后自清（Break self-cleared)

(*------------------------------------------------------------------------------
 * 段 5｜复位通道 + 故障锁存（CASE 前置；**不做状态变量赋值**，R39）
 *      Reset channel and fault latching before the CASE, with no state write
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    _bResetPulse := TRUE;                             // 复位单拍（One-shot reset）
END_IF

IF _bResetPulse THEN
    _bFaultLatch  := FALSE;                           // 清故障锁存（Latch cleared）
    _uErrFault    := 16#0000_0000;                    // 清首出码（First-out code cleared）
    _eDiag        := E_DL_DamperDiag.eOk;             // 结论回正常（Verdict back to OK）
    _fDevHeld     := 0.0;                             // 偏差保持量清零（Held deviation cleared）
    _uStallCount  := 0;                               // 卡滞次数清零（Stall counter cleared）
    _uTravelCount := 0;                               // 行程次数清零（Travel counter cleared）
    _bOverrun     := FALSE;                           // 超时标志清零（Overrun cleared）
    _bTravelBreak := TRUE;                            // 行程计时重启（Travel timer restarted）
    _bStallBreak  := TRUE;                            // 停滞计时重启（Stall timer restarted）
    _bDevBreak    := TRUE;                            // 偏差计时重启（Deviation timer restarted）
    _bSettleBreak := TRUE;                            // 确认计时重启（Settling timer restarted）
    _bIoBreak     := TRUE;                            // 反馈计时重启（Feedback timer restarted）
END_IF

(* 参数非法属故障级：行程标称过小会让超时判据恒真，故在闸门处直接判失效 *)
IF (tTravelNominal < T#1S) OR ((fSlowRatio < 1.1) OR (fSlowRatio > 3.0)) THEN
    _bParamBad := TRUE;                               // 参数越出物理域（Parameters outside the physical domain）
END_IF
IF (fTolPos <= 0.0) OR (fDevLimit <= 0.0) THEN
    _bParamBad := TRUE;                               // 容差或偏差限非正（Non-positive tolerance or limit）
END_IF

IF _bParamBad AND (NOT _bFaultLatch) THEN
    _uErrFault   := 16#0003_0325;                     // 0325 非法状态兜底（Illegal configuration fallback）
    _bFaultLatch := TRUE;                             // 锁存（Latched）
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜诊断状态机（5 个成员各一标签 + ELSE 兜底；进出移动态必断行程定时器）
 *      State machine, one label per member plus a trailing fallback
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_DamperState.eIdle: // 待机：偏差超容差则按「指令是否变化」分流
        IF _bFaultLatch THEN
            _eState := E_DL_DamperState.eFault;       // 已锁故障（Already latched）
        ELSIF bEnable AND (NOT _bAtTarget) THEN
            IF _bCmdOutRange OR (ABS(_fCmdUse - _fCmdPrev) > _fCmdEpsUse) THEN
                (* 指令已变：进入移动态，装基准并断行程定时器（Command changed, start a travel）
                 * 指令基准取「变化前的上一拍值」，否则基准等于新指令，位移证据永远为假，
                 * 完全停滞判据将永不成立（V1 的核心前提） *)
                _fCmdBase := _fCmdPrev;               // 指令基准取变化前值（Baseline before the change）
                _fPosBase := _fPosUse;                // 反馈基准取当前值（Position baseline）
                _bCmdMovedSince := FALSE;             // 指令位移证据清零（Command evidence cleared）
                _bPosMovedSince := FALSE;             // 阀位位移证据清零（Position evidence cleared）
                _bOverrun := FALSE;                   // 超时标志清零（Overrun cleared）
                _bTravelBreak := TRUE;                // 行程计时断输入一拍后重启（R40）
                _bStallBreak  := TRUE;                // 停滞计时重启（Stall timer restarted）
                IF _uTravelCount < 16#FFFF_FFFF THEN
                    _uTravelCount := _uTravelCount + 1; // 行程次数累加（Travel counter incremented）
                END_IF
                _eState := E_DL_DamperState.eMoving;  // 进入移动态（Enter moving）
            ELSE
                (* 指令未变而偏差超容差：属稳态偏差监视（Steady-state deviation monitoring） *)
                _bDevBreak := TRUE;                   // 偏差计时从 0 起算（Deviation timer restarted）
                _eState := E_DL_DamperState.eSettling; // 进入确认态（Enter settling）
            END_IF
        END_IF

    E_DL_DamperState.eMoving: // 移动：到位则测行程判慢；超时未达判卡滞
        IF _bFaultLatch THEN
            _eState := E_DL_DamperState.eFault;       // 转故障（Enter the fault state）
        ELSIF NOT bEnable THEN
            _bTravelBreak := TRUE;                    // 中止行程计时（Abort the travel timer）
            _eState := E_DL_DamperState.eIdle;        // 回待机（Back to idle）
        ELSIF fbIoWatch.Q THEN
            _bVerdictPending := TRUE;                 // 反馈失效确认（Feedback loss confirmed）
            _bTravelBreak := TRUE;                    // 行程计时中断（Travel timer stopped）
            _eState := E_DL_DamperState.eVerdict;     // 进判定（Enter verdict）
        ELSIF _bFbRestore THEN
            (* 恢复首拍：只重装基准，不判任何卡滞（R41 / V4） *)
            _fCmdBase := _fCmdUse;                    // 重装指令基准（Reload the command baseline）
            _fPosBase := _fPosUse;                    // 重装反馈基准（Reload the position baseline）
            _bCmdMovedSince := FALSE;                 // 位移证据清零（Evidence cleared）
            _bPosMovedSince := FALSE;                 // 位移证据清零（Evidence cleared）
            _bOverrun := FALSE;                       // 超时标志清零（Overrun cleared）
            _bTravelBreak := TRUE;                    // 行程计时重启（Travel timer restarted）
            _bStallBreak := TRUE;                     // 停滞计时重启（Stall timer restarted）
        ELSIF fbStallWatch.Q THEN
            _bVerdictPending := TRUE;                 // 完全停滞确认（Full stall confirmed）
            _bTravelBreak := TRUE;                    // 行程计时中断（Travel timer stopped）
            _eState := E_DL_DamperState.eVerdict;     // 进判定（Enter verdict）
        ELSIF _bAtTarget AND _bFbOk THEN
            _bVerdictPending := TRUE;                 // 到位：出结论（Arrived, issue the verdict）
            _bTravelBreak := TRUE;                    // 行程计时中断（Travel timer stopped）
            _eState := E_DL_DamperState.eVerdict;     // 进判定（Enter verdict）
        ELSIF fbGraceWatch.Q AND _bFbOk THEN
            _bVerdictPending := TRUE;                 // 宽限期满仍未达（Grace expired without arrival）
            _bTravelBreak := TRUE;                    // 行程计时中断（Travel timer stopped）
            _eState := E_DL_DamperState.eVerdict;     // 进判定（Enter verdict）
        END_IF
        (* 反馈暂失时不改状态：保持移动态等内存失效计时，判据由 _bFbOk 抑制 *)

    E_DL_DamperState.eSettling: // 确认：偏差回容差则计确认窗，超限则计偏差窗
        IF _bFaultLatch THEN
            _eState := E_DL_DamperState.eFault;       // 转故障（Enter the fault state）
        ELSIF NOT bEnable THEN
            _bDevBreak := TRUE;                       // 偏差计时中断（Deviation timer stopped）
            _bSettleBreak := TRUE;                    // 确认计时中断（Settling timer stopped）
            _eState := E_DL_DamperState.eIdle;        // 回待机（Back to idle）
        ELSIF _bCmdOutRange OR (ABS(_fCmdUse - _fCmdPrev) > _fCmdEpsUse) THEN
            _bDevBreak := TRUE;                       // 指令又变：回移动态（Command changed again）
            _bSettleBreak := TRUE;                    // 确认计时中断（Settling timer stopped）
            _eState := E_DL_DamperState.eMoving;      // 回移动态（Back to moving）
        ELSIF fbIoWatch.Q THEN
            _bVerdictPending := TRUE;                 // 反馈失效确认（Feedback loss confirmed）
            _eState := E_DL_DamperState.eVerdict;     // 进判定（Enter verdict）
        ELSIF fbDevWatch.Q THEN
            _bVerdictPending := TRUE;                 // 稳态偏差确认（Deviation confirmed）
            _eState := E_DL_DamperState.eVerdict;     // 进判定（Enter verdict）
        ELSIF fbSettleWatch.Q THEN
            _bVerdictPending := TRUE;                 // 确认窗满且无判据（Settled without any criterion）
            _eState := E_DL_DamperState.eVerdict;     // 进判定（Enter verdict）
        END_IF

    E_DL_DamperState.eVerdict: // 判定：结论在段 7 生成，本态只负责回到待机
        _bTravelBreak := TRUE;                        // 出行动态必断行程计时（Leave the motion phase）
        _bStallBreak  := TRUE;                        // 停滞计时重启（Stall timer restarted）
        _bDevBreak    := TRUE;                        // 偏差计时重启（Deviation timer restarted）
        _bSettleBreak := TRUE;                        // 确认计时重启（Settling timer restarted）
        IF _bFaultLatch THEN
            _eState := E_DL_DamperState.eFault;       // 已锁故障优先（Latched fault wins）
        ELSE
            _eState := E_DL_DamperState.eIdle;        // 结论保持，回待机（Verdict held, back to idle）
        END_IF

    E_DL_DamperState.eFault: // 故障：等复位
        IF _bResetPulse THEN
            _eState := E_DL_DamperState.eIdle;        // 复位受理（Reset accepted）
        END_IF

    ELSE
        _uErrFault   := 16#0003_0325;                 // 0325 非法状态兜底（Illegal state fallback）
        _bFaultLatch := TRUE;                         // 兜底锁存（Fallback latched）
        _eState      := E_DL_DamperState.eFault;      // 进终端安全态（Terminal safe state）
END_CASE

(*------------------------------------------------------------------------------
 * 段 7｜行程证据累计与判据定性（在移动/确认/判定三态内推进）
 *      Travel evidence and criterion classification
 *-----------------------------------------------------------------------------*)
IF (_eState = E_DL_DamperState.eMoving) THEN
    IF ABS(_fCmdUse - _fCmdBase) > _fDriftUse THEN
        _bCmdMovedSince := TRUE;                      // 指令已动（Command has moved）
    END_IF
    IF ABS(_fPosUse - _fPosBase) > _fDriftUse THEN
        _bPosMovedSince := TRUE;                      // 阀位已动（Position has moved）
    END_IF
    IF fbTravelWatch.Q THEN
        _bOverrun := TRUE;                            // 超过标称倍率，进入宽限期（Overrun, start the grace window）
    END_IF
END_IF

IF _bVerdictPending THEN
    IF fbIoWatch.Q THEN
        _eDiag := E_DL_DamperDiag.eIoFault;           // 反馈失效满确认窗：不是阀的问题（Feedback fault, not the valve）
        _uErrFault := 16#0003_0324;                   // 0324 I/O 反馈失效（Feedback lost）
        _bFaultLatch := TRUE;                         // 失效级锁存（Failure latch）
    ELSIF NOT _bFbOk THEN
        (* 判定拍反馈失效但未满 tIoFaultTime：本拍**不发布任何结论**，保持上次值。
         * 这是 R42 本拍复验与「三分类判据一律带确认窗」的交点：eSettling 的
         * 到位/偏差定时器不以反馈有效性为输入，若在此直接判 I/O 失效，就会用
         * 一次瞬时断线否掉整段行程；正确路径是让 fbIoWatch 计时满后再定性。 *)
    ELSIF fbStallWatch.Q THEN
        _eDiag := E_DL_DamperDiag.eFullStall;         // 完全不动（Full stall）
        _uErrFault := 16#0003_0321;                   // 0321 Full Stall（Full stall）
        _bFaultLatch := TRUE;                         // 失效级锁存（Failure latch）
        IF _uStallCount < 16#FFFF_FFFF THEN
            _uStallCount := _uStallCount + 1;         // 卡滞计数（Stall counter incremented）
        END_IF
    ELSIF _bAtTarget THEN
        _tTravelHeld := fbTravelWatch.ET;             // 实测行程时间（Measured travel time）
        IF _bOverrun THEN
            _eDiag := E_DL_DamperDiag.eSlow;          // 超时但到位：只是慢（Arrived late, merely slow）
        ELSE
            _eDiag := E_DL_DamperDiag.eOk;            // 准时到位（Arrived in time）
        END_IF
    ELSIF fbGraceWatch.Q THEN
        IF _bPosMovedSince THEN
            _eDiag := E_DL_DamperDiag.eTransitStall;  // 动而未达（Moved but never arrived）
            _uErrFault := 16#0003_0322;               // 0322 Transit Stall（Transit stall）
            _bFaultLatch := TRUE;                     // 失效级锁存（Failure latch）
        ELSE
            _eDiag := E_DL_DamperDiag.eFullStall;     // 一步未动（Not a single step）
            _uErrFault := 16#0003_0321;               // 0321 Full Stall（Full stall）
            _bFaultLatch := TRUE;                     // 失效级锁存（Failure latch）
        END_IF
        IF _uStallCount < 16#FFFF_FFFF THEN
            _uStallCount := _uStallCount + 1;         // 卡滞计数（Stall counter incremented）
        END_IF
    ELSIF fbDevWatch.Q THEN
        _eDiag := E_DL_DamperDiag.eDeviation;         // 稳态偏差：可运行，不置 bError（Deviation, still runnable）
    ELSE
        _eDiag := E_DL_DamperDiag.eOk;                // 无判据（No criterion）
    END_IF
    _bVerdictPending := FALSE;                        // 本拍结论已处理（或按确认窗规则不出结论），标志自清（Verdict consumed）
END_IF

_fDevHeld := LIMIT(-DL_FULL, _fDeviation, DL_FULL);   // 偏差保持量钳进 −100~100（R43）
_fCmdPrev := _fCmdUse;                                // 记录上拍指令（Record the previous command）
_fPosPrev := _fPosUse;                                // 记录上拍反馈（Record the previous position）

(*------------------------------------------------------------------------------
 * 段 8｜健康仲裁、出口钳位与保持重写（R27 + R43）
 *      Health arbitration, clamping and hold semantics
 *-----------------------------------------------------------------------------*)
IF _bFaultLatch THEN
    _eHealthInt := E_DL_Ne107Status.eFailure;         // 失效（Failure）
ELSIF _eDiag = E_DL_DamperDiag.eSlow THEN
    _eHealthInt := E_DL_Ne107Status.eMaintenanceReq;  // 慢：维护请求（Slow, maintenance）
ELSIF _eDiag = E_DL_DamperDiag.eDeviation THEN
    _eHealthInt := E_DL_Ne107Status.eMaintenanceReq;  // 偏差：维护请求（Deviation, maintenance）
ELSIF NOT bEnable THEN
    _eHealthInt := E_DL_Ne107Status.eUnknown;         // 未使能（Disabled）
ELSE
    _eHealthInt := E_DL_Ne107Status.eOk;              // 正常（OK）
END_IF

eHealth      := _eHealthInt;                          // 健康态出口（Health outlet）
eDiag        := _eDiag;                               // 结论保持重写（Held verdict rewritten）
fDeviation   := _fDevHeld;                            // 偏差钳位出口（Clamped deviation）
tLastTravel  := _tTravelHeld;                         // 末次行程时间出口（Last travel outlet）
nStallCount  := _uStallCount;                         // 卡滞次数出口（Stall counter outlet）
nTravelCount := _uTravelCount;                        // 行程次数出口（Travel counter outlet）
bAtOpen      := _bAtOpenInt;                          // 开到位出口（At open outlet）
bAtClose     := _bAtCloseInt;                         // 关到位出口（At close outlet）
bError       := _bFaultLatch;                         // 故障位只由失效级码置位（Failure codes only）

(*------------------------------------------------------------------------------
 * 段 9｜码位单一优先级链（全拍只写一次 uDiagCode）
 *      Single priority chain, the diagnostic code is written exactly once
 *-----------------------------------------------------------------------------*)
IF _bFaultLatch THEN
    _uDiagCode := _uErrFault;                         // 失效级优先（Failure first）
ELSIF _eDiag = E_DL_DamperDiag.eDeviation THEN
    _uDiagCode := 16#0003_0323;                       // 0323 稳态偏差：故障带码但**不置 bError**（Deviation, no bError）
ELSIF (_eDiag = E_DL_DamperDiag.eSlow) OR _bCmdOutRange THEN
    _uDiagCode := 16#0003_0161;                       // 0161 行程偏慢或指令超域钳位（Slow or clamped command）
ELSIF NOT _bFbOk THEN
    _uDiagCode := 16#0003_0160;                       // 0160 无反馈运行，尚未超失效时长（Open-loop run）
ELSE
    _uDiagCode := 16#0000_0000;                       // 无码（No code）
END_IF

uDiagCode := _uDiagCode;                              // 诊断码出口（Diagnostic code outlet）
uErrorId  := _uErrFault;                              // 末次故障码出口（Last fault code outlet）

END_FUNCTION_BLOCK
