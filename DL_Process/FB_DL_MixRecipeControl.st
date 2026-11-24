(*==============================================================================
 * 组件名称 (Component)  : FB_DL_MixRecipeControl
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG）+ 既有接口
 *                         I_DL_VfdDrive（DL_Device R6 契约件，仅引用零修改）
 * 分类     (Category)   : 工艺段功能块（Function Block · ISA-88 单相语义混合搅拌）
 * 功能简述 (Function)   : 混合/搅拌工艺相控制（ISA-88 单相语义 clean-room）：
 *                         投料就绪 → 搅拌（定速/正反交替）→ 终点判据（时间
 *                         到/扭矩上升达标）→ 出料许可 → 停转；转速反馈监视、
 *                         扭矩超限保护、出料超时诊断。驱动控制全部经 I_DL_Vfd
 *                         Drive 接口引用（引脚注入），本块零硬件依赖。
 * 接口消费 (Consumes)   : I_DL_VfdDrive（既有契约，仅引用零修改）：每拍至多
 *                         一次方法调用（公约 0.13），由内部单发指令调度器串行
 *                         化——CmdStop > CmdRun > SetFrequency 优先级链；接
 *                         口无 bReady 属性，前置就绪按 NOT iDrive.bFault 判
 *                         定（R11 留档见偏离留档①）；SetFrequency 引脚值域
 *                         为 Hz，本块传入转速数值，rpm↔Hz 标定由调用方实现
 *                         块承担（既有契约语义，头注释声明）。
 * 首扫说明 (Init note)  : 顺序型组件但全部状态由指令沿/电平驱动，免首扫
 *                         （R23/公约 0.1），无 bInit。
 * 公约遵循 (Convention) : 0.2/R21 bError 仅故障级码置位；0.4 双语同行注释；
 *                         0.5/R7 实例主体最前部无条件刷新；0.7/R15 故障锁存
 *                         仅复位路径清码；0.10 定时基准由引脚给（tCycle 增补
 *                         引脚，泳道 A 同款公共约定，非逐组件条款）；0.13 接
 *                         口调用配额每拍至多一次（调度器结构保证）；0.14 非
 *                         有限值防御；0.15 转速统一 rpm、扭矩统一 % 额定；
 *                         0.16 无魔法数；0.17 终结符成对 ✓；0.19 码位同行
 *                         【级别】注释；0.20 验收向量入头注释；R25 bDone 单
 *                         拍三律。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 非有限值/除零/浮点容差 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 ENUM+CASE+ELSE ✓
 *                         R7 五实例（R_TRIG×2/TON×3）主体最前部无条件刷新 ✓
 *                         R8 全常量化 ✓｜R25 单拍标志生命周期三律 ✓
 * 设计要点 (Key notes)  : ① 接口单发调度器：状态机只登记指令请求标志，唯一
 *                           的方法调用点在段 6 调度器（Stop > Run > SetFreq
 *                           优先级链），结构上保证每拍至多一次方法调用（公约
 *                           0.13）；SetFrequency 仅在设定变化超容差时下发；
 *                         ② 交替换向三步序（禁止直接反接，防机械冲击）：
 *                           CmdStop → 等 fActSpeed < DL_MIX_STOP_EPS →
 *                           CmdRun(新方向) → 下一拍补发 SetFrequency；
 *                         ③ 转速确认窗：进入搅拌相后 tSpeedCheck 内须达 90%
 *                           设定，否则 0261（皮带断/驱动未使能类故障）；混合
 *                           计时仅在确认通过后累计（暂停期冻结）；
 *                         ④ 扭矩保护：fActTorque ≥ fTorqueLimit 立即停 + 故
 *                           障 0263（疑似卡桨/物料过稠，防烧电机）；
 *                         ⑤ 方向互斥出口断言：bDirForward 与 bDirReverse 由
 *                           同一方向寄存器派生，结构上恒互斥（切换过渡期双
 *                           FALSE）；
 *                         ⑥ fProgress 量纲推导：已混合秒值/目标秒值 [-]，双
 *                           方经 TIME 毫秒口径转 REAL 后相除（除前判零），钳
 *                           位 [0,1]。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 2 条：
 *                         ① 前置就绪判据：规格预留「若接口无 bReady 属性改
 *                           用 NOT iDrive.bFault」——既有 I_DL_VfdDrive 契
 *                           约无 bReady，本块按 NOT iDrive.bFault 实现，规格
 *                           预案内非语义偏离；
 *                         ② tCycle 增补引脚：混合计时累计与进度折算需要时
 *                           间基准，依公约 0.10 增补（泳道 A 先例，公共约定
 *                           强制项，非逐组件条款）。
 * 开源溯源 (Origin)     : 来源标签 isa-88-phase / mixing-process（RAW_NOTES_R8
 *                         S-9 LBP 实测 + S-10 相语义：ISA-88 相（Phase）公开
 *                         语义——前确认/执行/终点判据/完成的相结构与「批次数
 *                         据不进控制逻辑」的分层思想，公开技术资料，仅借鉴相
 *                         分类与参数域；状态机、交替换向三步序、码位、引脚契
 *                         约 100% 本库独立设计，clean-room 未复制源码。许可
 *                         证说明：ISA-88 为公开标准语义，本文件为本库原创实
 *                         现，随本库许可证发布）。
 * 验收向量 (Acceptance) :
 *   V1 正常混合 tMixTime → bOk + bDone 单拍 + fProgress≈1.0；
 *   V2 交替模式（30 s 换向）：方向互斥、先停后启无直接反接；
 *   V3 扭矩超限 → 立即停 + 故障 0263；
 *   V4 转速确认窗内未建立 → 0261；
 *   V5 bEndByTorque 且扭矩提前达标 → 信息码 0163 提前完成；
 *   V6 超最长混合时间 → eNg + 信息码 0162；
 *   V7 出料超时 → 0262；
 *   V8 bAbort 中途 → 停转且不出料、无 OK/NG。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 08 · DL_Process 混合工艺相件）
 *   2026-11-15  v1.0.1  R8 总监终审修复四项：① eMixing 判 NG 分支写入未声明
 *                       内部变量 _bNg（编译期未定义符号）改为出口 bNg；② 判
 *                       定保持语义补齐——eDone 相每拍置 bOk、eNg 相每拍置 bNg
 *                       （原仅转换拍脉冲，违反规格「eDone/eNg 保持」）；③ 最
 *                       长混合时间判据与目标时间判据的 ELSIF 先后倒置导致
 *                       eNg 终态不可达（tElapsed ≥ tMixMax 必先被 tElapsed ≥
 *                       tMixEff 捕获），改为「扭矩终点 → 时间模式目标终点 →
 *                       最长超时」序，恢复 V6 可达性且时间模式无回归；④ 终端
 *                       态分支内孤立空语句 `;`（非 IEC 61131-3 文法）改为纯注
 *                       释占位分支。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MixPhase（归属 FB_DL_MixRecipeControl，与其同文件发布，公约 0.18）
 *----------------------------------------------------------------------------*)
TYPE E_DL_MixPhase :
(
    eIdle      := 0,   // 空闲：等启动 / Idle, awaiting start
    ePreCheck  := 10,  // 前置确认：料已投、出料阀关、驱动就绪 / Precheck, material, outlet and drive ready
    eMixing    := 20,  // 搅拌中（含交替子计时）/ Mixing with alternate sub-timing
    eVerify    := 30,  // 终点确认：稳速确认与结果锁存 / Verify, speed stability and result latch
    eDischarge := 40,  // 出料中：等出料完成信号 / Discharging, awaiting discharge done
    eSpinDown  := 50,  // 停转：减速到零 / Spin down to standstill
    eDone      := 60,  // 完成（OK），等复位 / Done, awaiting reset
    eNg        := 70,  // 不合格（终点未达但超最长混合时间），等复位 / NG on max-time expiry, awaiting reset
    eAbort     := 80,  // 中止：立即停转，禁止出料 / Aborted, stopped and discharge forbidden
    eFault     := 99   // 故障锁存 / Fault latched
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_MixRecipeControl
VAR_INPUT
    bEnable             : BOOL;             // 使能（Enable），FALSE=停转清输出 / Enable, FALSE stops drive and clears outputs
    bStart              : BOOL;             // 启动混合相（Start），上升沿受理（空闲/完成/不合格态）/ Start edge accepted at idle/done/ng
    bAbort              : BOOL;             // 中止（Abort），电平最高优先：停转、禁止出料 / Abort level, highest priority
    bReset              : BOOL;             // 复位（Reset），上升沿受理 / Rising edge resets fault and verdicts
    bMaterialReady      : BOOL;             // 投料就绪（Material ready），前置确认项 / Material loaded interlock
    bOutletClosed       : BOOL;             // 出料阀关闭确认（Outlet closed），前置确认项 / Outlet valve closed interlock
    bDischargeDone      : BOOL;             // 出料完成（Discharge done），出料相退出条件 / Discharge completion feedback
    fSpeedSetpoint      : REAL := 300.0;    // 搅拌转速设定（Speed setpoint）[rpm]，域 1..3000，越界钳位 / Speed setpoint [rpm]
    fActSpeed           : REAL;             // 实际转速（Actual speed）[rpm]，由变频器/适配层注入 / Actual speed [rpm] injected
    fActTorque          : REAL;             // 实际扭矩（Actual torque）[% 额定] / Actual torque [% of rated]
    fTorqueLimit        : REAL := 85.0;     // 扭矩保护上限（Torque limit）[%]，超限即停 + 故障 / Torque protection limit [%]
    bEndByTorque        : BOOL;             // 以扭矩上升为终点判据（End by torque），TRUE=扭矩达标即完成 / Torque-rise end criterion enable
    fTorqueRiseTarget   : REAL := 60.0;     // 终点扭矩判据（End torque target）[%]，仅 bEndByTorque 有效 / Torque end target [%]
    tMixTime            : TIME := T#5M;     // 目标混合时间（Mix time）/ Target mix duration
    tMixTimeMax         : TIME := T#15M;    // 最长混合时间（Max mix time），超时判 NG / Maximum mix duration, expiry = NG
    bAlternate          : BOOL;             // 正反交替（Alternate direction），TRUE=每 tAlternateTime 换向 / Alternate direction enable
    tAlternateTime      : TIME := T#30S;    // 交替周期（Alternate period），仅 bAlternate 有效 / Alternate period
    tSpeedCheck         : TIME := T#5S;     // 转速到位确认窗（Speed check window），窗内须达 90% 设定 / Speed establish window
    tDischargeTimeout   : TIME := T#60S;    // 出料超时（Discharge timeout）/ Discharge timeout
    tCycle              : TIME := T#10MS;   // 任务扫描周期（Task cycle time）[ms]，由调用方按实际任务给，计时累计基准（公约 0.10）/ Task cycle time, timing base
END_VAR
VAR_OUTPUT
    fSpeedCmd           : REAL;             // 转速指令（Speed command）[rpm]，0=停 / Speed command [rpm], zero = stop
    bDirForward         : BOOL;             // 正转指令（Forward），与反转互斥 / Forward direction, exclusive with reverse
    bDirReverse         : BOOL;             // 反转指令（Reverse）/ Reverse direction
    ePhase              : E_DL_MixPhase := E_DL_MixPhase.eIdle; // 当前相位（Current phase）/ Current phase
    bBusy               : BOOL;             // 执行中（Busy），前置确认至停转态为 TRUE / TRUE from precheck to spin-down
    bDone               : BOOL;             // 完成单拍脉冲（Done pulse，OK 或 NG 进入时各一次），单拍生命周期三律 / One-scan verdict pulse
    bOk                 : BOOL;             // 混合合格（OK），完成保持态为 TRUE / OK verdict held
    bNg                 : BOOL;             // 混合不合格（NG），不合格保持态为 TRUE / NG verdict held
    fProgress           : REAL;             // 进度（Progress）[-]，0.0..1.0 = 已混合时间/目标时间（钳位）/ Mix progress dimensionless clamped
    tElapsed            : TIME := T#0S;     // 已混合时长（Elapsed mix time），仅确认通过后累计 / Elapsed mix time, accumulates after confirm
    bError              : BOOL;             // 故障锁存（Error），仅故障级码 / Latched error, fault codes only
    uErrorId            : UDINT;            // 故障码（Error code），16#0005_xxxx 段，0=无故障 / Error code, fault-level priority
END_VAR
VAR_IN_OUT
    iDrive              : I_DL_VfdDrive;    // 搅拌驱动接口引用（Mixer drive，既有契约 I_DL_VfdDrive），由上层注入实例 / Mixer drive interface reference injected by caller
END_VAR
VAR
    _ePhase             : E_DL_MixPhase := E_DL_MixPhase.eIdle;   // 内部相位（Internal phase）/ Internal phase
    _bFaultLatch        : BOOL;             // 故障锁存标志（Fault latch flag），仅复位路径清除 / Fault latch, cleared only via reset path
    _uErrorIdInt        : UDINT;            // 内部故障级码寄存（Internal fault-level register）/ Internal fault-level register
    _uInfoCode          : UDINT;            // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code
    _bCmdStopReq        : BOOL;             // 停止指令请求（Stop request flag），调度器消费 / Stop request consumed by dispatcher
    _bCmdRunReq         : BOOL;             // 运行指令请求（Run request flag），调度器消费 / Run request consumed by dispatcher
    _bCmdFreqReq        : BOOL;             // 频率设定请求（Frequency request flag），调度器消费 / Frequency request consumed by dispatcher
    _bRunFwd            : BOOL;             // 待发方向（Pending direction），TRUE=正转 / Pending direction, TRUE = forward
    _bRunIssued         : BOOL;             // 运行指令已受理锁存（Run accepted latch）/ Run accepted latch
    _bDirFwd            : BOOL := TRUE;     // 当前方向寄存（Current direction register），TRUE=正转 / Current direction, TRUE = forward
    _bConfirmed         : BOOL;             // 转速确认通过（Speed confirmed）/ Speed establish confirmed
    _bRevPending        : BOOL;             // 换向请求（Reversal pending）/ Reversal pending
    _bRevInStop         : BOOL;             // 换向停转步（Reversal stop step），等待转速落零 / Reversal stop step, waiting speed near zero
    _tElapsedInt        : TIME := T#0S;     // 内部混合计时（Internal mix elapsed），确认后每拍加 tCycle / Internal elapsed, accumulates after confirm
    _fSetEff            : REAL;             // 生效转速设定（Effective setpoint）[rpm]，钳位后值 / Sanitized setpoint [rpm]
    _fTorqueLimEff      : REAL;             // 生效扭矩上限（Effective torque limit）[%] / Sanitized torque limit [%]
    _fTorqueTgtEff      : REAL;             // 生效终点扭矩（Effective end torque target）[%] / Sanitized end torque target [%]
    _tMixEff            : TIME;             // 生效目标混合时间（Effective mix time）/ Sanitized mix duration
    _tMixMaxEff         : TIME;             // 生效最长混合时间（Effective max mix time）/ Sanitized max mix duration
    _tAltEff            : TIME;             // 生效交替周期（Effective alternate period）/ Sanitized alternate period
    _tAltLast           : TIME := T#30S;    // 上拍生效交替周期（Last alternate period），PT 变更检测基准 / Last alternate period for PT-change detection
    _bAltBreak          : BOOL := TRUE;     // 交替计时输入使能（Alternate input enable），PT 变更拍断一拍 / Alternate input enable, broken on PT change
    _fFreqReq           : REAL;             // 待发频率值（Pending frequency value），调度器消费 / Pending frequency value
    _fFreqLast          : REAL;             // 末次下发频率（Last sent frequency），变化超容差才重发 / Last sent frequency, resend on change
    _fSpeedCmdInt       : REAL;             // 内部转速指令（Internal speed command）[rpm] / Internal speed command [rpm]
    _bFiniteSpd         : BOOL;             // 转速信号有限（Speed finite verdict）/ Speed signal finite verdict
    _bFiniteTrq         : BOOL;             // 扭矩信号有限（Torque finite verdict）/ Torque signal finite verdict
    _fbTrigStart        : R_TRIG;           // 启动沿（Start edge detector）/ Start edge detector
    _fbTrigReset        : R_TRIG;           // 复位沿（Reset edge detector）/ Reset edge detector
    _fbTonPreChk        : TON;              // 前置确认窗（Precheck window）/ Precheck window timer
    _fbTonSpdChk        : TON;              // 转速确认窗（Speed establish window）/ Speed establish window timer
    _fbTonAlt           : TON;              // 交替周期（Alternate period）/ Alternate period timer
    _fbTonDischTo       : TON;              // 出料超时（Discharge timeout）/ Discharge timeout timer
END_VAR
VAR CONSTANT
    DL_MIX_REAL_MAX     : REAL := 3.4E38;   // 单精度有限值判据幅值（Finite magnitude bound）/ Finite magnitude bound for REAL inputs
    DL_MIX_EPS          : REAL := 1.0E-6;   // 浮点防零/防重发容差（Float divide-guard epsilon）/ Float epsilon
    DL_MIX_STOP_EPS     : REAL := 1.0;      // 停转判定阈（Standstill threshold）[rpm]，低于此值视为已停 / Standstill speed threshold [rpm]
    DL_MIX_FREQ_EPS     : REAL := 0.5;      // 频率重发容差（Frequency resend epsilon）[rpm]，变化超此值才下发 / Resend threshold for setpoint change
    DL_MIX_SPD_OK_FRAC  : REAL := 0.9;      // 确认转速比例（Confirm speed fraction）[-]，达设定 90% 视为建立 / Confirm at 90% of setpoint
    DL_MIX_VERIFY_FRAC  : REAL := 0.05;     // 终点稳速容差比例（Verify tolerance fraction）[-]，±5% 设定 / Verify within 5% of setpoint
    DL_MIX_DISCHARGE_SPD: REAL := 50.0;     // 出料助排慢速（Discharge assist speed）[rpm] / Slow discharge assist speed [rpm]
    DL_MIX_SPD_MIN      : REAL := 1.0;      // 转速设定域下限（Setpoint lower clamp）[rpm] / Setpoint lower clamp [rpm]
    DL_MIX_SPD_MAX      : REAL := 3000.0;   // 转速设定域上限（Setpoint upper clamp）[rpm] / Setpoint upper clamp [rpm]
    DL_MIX_ALT_FACTOR   : DINT := 2;        // 交替周期提升倍数（Alternate raise factor）[-]，提升到确认窗的此倍数 / Alternate raise factor over check window
    DL_MIX_ERR_PRECHK   : UDINT := 16#0005_0260; // 0005_0260 前置条件不成立（料/阀/驱动）【故障级】/ Precheck timeout, fault level
    DL_MIX_ERR_SPEED    : UDINT := 16#0005_0261; // 0005_0261 转速未在确认窗内建立【故障级】/ Speed not established, fault level
    DL_MIX_ERR_DISCH    : UDINT := 16#0005_0262; // 0005_0262 出料超时【故障级】/ Discharge timeout, fault level
    DL_MIX_ERR_TORQUE   : UDINT := 16#0005_0263; // 0005_0263 扭矩超保护上限（疑似卡桨）【故障级】/ Torque over protection limit, fault level
    DL_MIX_ERR_NAN      : UDINT := 16#0005_0264; // 0005_0264 转速/扭矩信号非有限值【故障级】/ Non-finite speed or torque, fault level
    DL_MIX_ERR_STATE    : UDINT := 16#0005_0265; // 0005_0265 非法状态兜底【故障级】/ Illegal state fallback, fault level
    DL_MIX_INFO_CLAMP   : UDINT := 16#0005_0160; // 0005_0160 转速设定越界钳位【信息级】/ Setpoint clamped, info level
    DL_MIX_INFO_SWAP    : UDINT := 16#0005_0161; // 0005_0161 混合时间与最长混合时间对调自修复【信息级】/ Mix times swapped, info level
    DL_MIX_INFO_MAXT    : UDINT := 16#0005_0162; // 0005_0162 最长混合时间到，判 NG【信息级】/ Max mix time reached, NG, info level
    DL_MIX_INFO_TORQEND : UDINT := 16#0005_0163; // 0005_0163 以扭矩上升为终点判据触发【信息级】/ Torque-rise end criterion, info level
    DL_MIX_INFO_ALTRAISE: UDINT := 16#0005_0164; // 0005_0164 交替周期被提升至两倍确认窗【信息级】/ Alternate period raised, info level
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all instances (R7/0.5)
// ============================================================================
_fbTrigStart(CLK := bStart);            // 启动沿（Start edge）
_fbTrigReset(CLK := bReset);            // 复位沿（Reset edge）
_fbTonPreChk(IN := (_ePhase = E_DL_MixPhase.ePreCheck), PT := tSpeedCheck);   // 前置确认窗（Precheck window）
_fbTonSpdChk(IN := (_ePhase = E_DL_MixPhase.eMixing) AND (NOT _bConfirmed), PT := tSpeedCheck); // 转速确认窗（Speed window）
_fbTonAlt(IN := (_ePhase = E_DL_MixPhase.eMixing) AND _bConfirmed AND bAlternate
          AND (NOT _bRevPending) AND (NOT _bRevInStop) AND _bAltBreak, PT := _tAltEff);  // 交替周期（Alternate period）
_fbTonDischTo(IN := (_ePhase = E_DL_MixPhase.eDischarge), PT := tDischargeTimeout); // 出料超时（Discharge timeout）

// 交替周期 PT 变更断输入一拍（R14：防改时间常数后计时不清零的幽灵故障）
// Alternate-period PT-change one-scan input break (R14)
IF _tAltEff <> _tAltLast THEN
    _bAltBreak := FALSE;                // 交替计时输入断一拍（Alternate input broken one scan）
    _tAltLast := _tAltEff;              // 登记新交替周期（Register new alternate period）
ELSE
    _bAltBreak := TRUE;                 // 恢复交替计时输入（Alternate input restored）
END_IF

// ============================================================================
// 段 2｜信息级预清零 + 出口默认赋值（0.9：任何早退路径输出确定）+ 参数防御
//      Info preset + output defaults + parameter defense
// ============================================================================
_uInfoCode := 0;                        // 信息级瞬时型每拍重算（Transient info recomputed each scan）
bDone := FALSE;                         // 完成单拍先清零（R25：置位-消费-复位同周期闭环）/ Done pulse preset FALSE (R25)
fSpeedCmd := 0.0;                       // 转速指令默认停（Speed command default stop）
bDirForward := FALSE;                   // 方向默认双 FALSE（Directions default FALSE）
bDirReverse := FALSE;
bOk := FALSE;                           // 判定默认清（Verdicts preset）
bNg := FALSE;
fProgress := 0.0;                       // 进度默认零（Progress default zero）

// 信号非有限值防御（转速/扭矩，任何执行态均监视）
// Non-finite defense on speed/torque signals
_bFiniteSpd := (fActSpeed  >= (-DL_MIX_REAL_MAX)) AND (fActSpeed  <= DL_MIX_REAL_MAX);
_bFiniteTrq := (fActTorque >= (-DL_MIX_REAL_MAX)) AND (fActTorque <= DL_MIX_REAL_MAX);
IF bEnable AND ((NOT _bFiniteSpd) OR (NOT _bFiniteTrq)) THEN
    _bFaultLatch := TRUE;               // 信号非有限值锁存（Signal defense latch）
    _uErrorIdInt := DL_MIX_ERR_NAN;     // 0005_0264 转速/扭矩非有限值【故障级】/ Non-finite signal, fault level
    _ePhase := E_DL_MixPhase.eFault;
END_IF

// 转速设定钳位（Setpoint clamp，域 1..3000）
IF (fSpeedSetpoint < DL_MIX_SPD_MIN) OR (fSpeedSetpoint > DL_MIX_SPD_MAX) THEN
    _fSetEff := LIMIT(DL_MIX_SPD_MIN, fSpeedSetpoint, DL_MIX_SPD_MAX);   // 域钳位（Domain clamp）
    _uInfoCode := DL_MIX_INFO_CLAMP;    // 0005_0160 设定越界钳位【信息级】/ Setpoint clamped, info level
ELSE
    _fSetEff := fSpeedSetpoint;         // 引脚原值（Pin value as-is）
END_IF

// 混合时间与最长混合时间对调自修复（对调后目标 ≤ 上限）
// Mix times swap self-repair (target ≤ max after swap)
IF tMixTime > tMixTimeMax THEN
    _tMixEff := tMixTimeMax;            // 对调：目标取原上限（Swap: target = old max）
    _tMixMaxEff := tMixTime;            // 对调：上限取原目标（Swap: max = old target）
    _uInfoCode := DL_MIX_INFO_SWAP;     // 0005_0161 时间对调自修复【信息级】/ Times swapped, info level
ELSE
    _tMixEff := tMixTime;               // 引脚原值（Pin values as-is）
    _tMixMaxEff := tMixTimeMax;
END_IF

// 交替周期自动提升：小于两倍确认窗时提升到两倍（防换向太频转速永远建不起来）
// Alternate period auto-raise below twice check window (prevents never-established speed)
IF tAlternateTime < tSpeedCheck * DL_MIX_ALT_FACTOR THEN
    _tAltEff := tSpeedCheck * DL_MIX_ALT_FACTOR;    // 提升到两倍确认窗（Raised to twice window）
    _uInfoCode := DL_MIX_INFO_ALTRAISE;             // 0005_0164 交替周期被提升【信息级】/ Alternate raised, info level
ELSE
    _tAltEff := tAlternateTime;         // 引脚原值（Pin value as-is）
END_IF

// 扭矩限/终点扭矩防御（非有限值/非正回默认语义域钳位）
// Torque limit/target defense
_fTorqueLimEff := LIMIT(DL_MIX_EPS, fTorqueLimit, DL_MIX_REAL_MAX);        // 上限域钳位（Limit clamped）
_fTorqueTgtEff := LIMIT(DL_MIX_EPS, fTorqueRiseTarget, _fTorqueLimEff);    // 终点目标不超过保护上限（Target ≤ limit）

// 复位路径：仅此路径可清故障锁存与判定（R15）
IF _fbTrigReset.Q THEN
    _bFaultLatch := FALSE;              // 故障锁存解除（Fault latch released）
    _uErrorIdInt := 16#0000_0000;       // 故障码清零（Fault code cleared）
    IF (_ePhase = E_DL_MixPhase.eFault) OR (_ePhase = E_DL_MixPhase.eAbort)
    OR (_ePhase = E_DL_MixPhase.eDone) OR (_ePhase = E_DL_MixPhase.eNg) THEN
        _ePhase := E_DL_MixPhase.eIdle; // 故障/中止/完成/不合格态回空闲（Terminal phases back to idle）
        _bRunIssued := FALSE;           // 运行锁存撤销（Run latch revoked）
        _bConfirmed := FALSE;
        _bRevPending := FALSE;
        _bRevInStop := FALSE;
        _tElapsedInt := T#0S;           // 计时清零（Elapsed reset）
    END_IF
END_IF

// ============================================================================
// 段 3｜中止电平与扭矩保护全局监视（优先级最高）
//      Abort level and torque protection global monitors (highest priority)
// ============================================================================
IF bEnable AND (NOT _bFaultLatch) AND (NOT bAbort)
AND ((_ePhase = E_DL_MixPhase.eMixing) OR (_ePhase = E_DL_MixPhase.eVerify)
  OR (_ePhase = E_DL_MixPhase.eDischarge) OR (_ePhase = E_DL_MixPhase.ePreCheck)) THEN
    IF _bFiniteTrq AND (fActTorque >= _fTorqueLimEff) THEN
        _bCmdStopReq := TRUE;           // 扭矩超限立即停（Torque over limit, stop now）
        _bFaultLatch := TRUE;
        _uErrorIdInt := DL_MIX_ERR_TORQUE;   // 0005_0263 扭矩超保护上限（疑似卡桨）【故障级】/ Torque over limit, fault level
        _ePhase := E_DL_MixPhase.eFault;
    END_IF
END_IF

// 中止电平：任意执行相 → 立即停转、禁止出料、判定作废（Abort level intercept）
IF bEnable AND bAbort AND (NOT _bFaultLatch)
AND (_ePhase <> E_DL_MixPhase.eIdle) AND (_ePhase <> E_DL_MixPhase.eFault)
AND (_ePhase <> E_DL_MixPhase.eAbort) THEN
    _bCmdStopReq := TRUE;               // 立即停转请求（Immediate stop request）
    _bCmdRunReq := FALSE;               // 撤销一切运动请求（Revoke motion requests）
    _bCmdFreqReq := FALSE;
    _bRevPending := FALSE;
    _bRevInStop := FALSE;
    _ePhase := E_DL_MixPhase.eAbort;    // 进入中止保持态（Enter abort hold）
END_IF

// ============================================================================
// 段 4｜核心相位状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Core phase state machine (ENUM + CASE with ELSE fallback)
// ============================================================================
IF bEnable AND (NOT _bFaultLatch) AND (NOT bAbort) THEN
    CASE _ePhase OF

        E_DL_MixPhase.eIdle: // 空闲：等启动沿
            IF _fbTrigStart.Q AND (NOT iDrive.bFault) THEN
                _ePhase := E_DL_MixPhase.ePreCheck;      // 受理启动（Start accepted）
                _tElapsedInt := T#0S;                    // 计时清零（Elapsed reset）
                tElapsed := T#0S;                        // 出口计时清零（Outlet elapsed reset）
                _bConfirmed := FALSE;
                _bRunFwd := TRUE;                        // 初始方向正转（Initial direction forward）
                _bDirFwd := TRUE;
            END_IF

        E_DL_MixPhase.ePreCheck: // 前置确认：料已投 + 出料阀关 + 驱动无故障（偏离留档①判据）
            IF bMaterialReady AND bOutletClosed AND (NOT iDrive.bFault) THEN
                _bConfirmed := FALSE;                    // 确认标志复位（Confirm flag reset）
                _fFreqLast := 0.0;                       // 末次下发频率清零（Last sent reset）
                _bCmdFreqReq := TRUE;                    // 登记频率设定（Register setpoint）
                _fFreqReq := _fSetEff;
                _bCmdRunReq := TRUE;                     // 调度器 Run 优先：本拍发运行，设定下一拍补发（Run dispatches first, setpoint follows）
                _bRunFwd := _bDirFwd;
                _ePhase := E_DL_MixPhase.eMixing;        // 进入搅拌（Enter mixing）
            ELSIF _fbTonPreChk.Q THEN
                _bFaultLatch := TRUE;                    // 前置确认超时（Precheck timeout）
                _uErrorIdInt := DL_MIX_ERR_PRECHK;       // 0005_0260 前置条件不成立【故障级】/ Precheck failed, fault level
                _ePhase := E_DL_MixPhase.eFault;
            END_IF

        E_DL_MixPhase.eMixing: // 搅拌：确认窗监视 + 计时 + 交替换向 + 终点判据
            IF (NOT _bConfirmed) AND _bFiniteSpd
            AND (fActSpeed >= _fSetEff * DL_MIX_SPD_OK_FRAC) THEN
                _bConfirmed := TRUE;                     // 转速确认通过（Speed confirmed）
            END_IF
            IF _fbTonSpdChk.Q AND (NOT _bConfirmed) THEN
                _bCmdStopReq := TRUE;                    // 确认失败停机（Stop on confirm failure）
                _bFaultLatch := TRUE;
                _uErrorIdInt := DL_MIX_ERR_SPEED;        // 0005_0261 转速未建立【故障级】/ Speed not established, fault level
                _ePhase := E_DL_MixPhase.eFault;
            ELSE
                IF _bRunIssued AND (NOT _bCmdStopReq) AND (NOT _bCmdRunReq) THEN
                    _bConfirmed := _bConfirmed AND (NOT _bRevInStop); // 停转步期间冻结确认态（Confirm frozen in stop step）
                END_IF
                IF _bConfirmed THEN
                    _tElapsedInt := _tElapsedInt + tCycle;   // 计时仅确认后累计（Elapsed accumulates after confirm）
                    tElapsed := _tElapsedInt;                // 出口计时同步（Outlet elapsed sync）
                END_IF
                // 交替换向三步序：交替周期到 → 登记换向（Alt period reached: arm reversal）
                IF _fbTonAlt.Q THEN
                    _bRevPending := TRUE;                // 换向请求登记（Reversal armed）
                END_IF
                IF _bRevPending AND (NOT _bRevInStop) THEN
                    _bRevInStop := TRUE;                 // 第一步：停转（Step 1: stop）
                    _bCmdStopReq := TRUE;
                END_IF
                IF _bRevInStop AND _bFiniteSpd AND (fActSpeed < DL_MIX_STOP_EPS) THEN
                    // 第二步：转速落零后换向再启（Step 2: restart reversed after standstill）
                    _bDirFwd := NOT _bDirFwd;            // 方向翻转（Direction toggled）
                    _bRunFwd := _bDirFwd;
                    _bCmdRunReq := TRUE;                 // 先发运行（Run first）
                    _fFreqReq := _fSetEff;               // 下一拍补发设定（Frequency follows next scan）
                    _bCmdFreqReq := TRUE;
                    _bRevPending := FALSE;               // 换向序列结束（Reversal sequence done）
                    _bRevInStop := FALSE;
                END_IF
                // 设定变化超容差补发（Resend setpoint beyond epsilon）
                IF _bConfirmed AND (NOT _bRevPending) AND (NOT _bRevInStop)
                AND (ABS(_fSetEff - _fFreqLast) > DL_MIX_FREQ_EPS) THEN
                    _fFreqReq := _fSetEff;               // 登记新设定（Register new setpoint）
                    _bCmdFreqReq := TRUE;
                END_IF
                // 终点判据（End criteria）：已达终点者优先，其次最长超时判 NG
                // 顺序不可倒置：tMixEff ≤ tMixMaxEff 恒成立（段 2 对调自修复），
                // 若「时间终点」排在「最长超时」之后，则 eNg 被完全遮蔽、终态
                // 不可达；此处显式区分终点类型，兼得可达性与时间模式无回归。
                IF bEndByTorque AND _bFiniteTrq AND (fActTorque >= _fTorqueTgtEff) THEN
                    _uInfoCode := DL_MIX_INFO_TORQEND;   // 0005_0163 扭矩终点触发【信息级】/ Torque end reached, info level
                    _ePhase := E_DL_MixPhase.eVerify;    // 进入终点确认（Enter verify）
                ELSIF (NOT bEndByTorque) AND (_tElapsedInt >= _tMixEff) THEN
                    _ePhase := E_DL_MixPhase.eVerify;    // 时间终点（Time end）
                ELSIF _tElapsedInt >= _tMixMaxEff THEN
                    _uInfoCode := DL_MIX_INFO_MAXT;      // 0005_0162 最长混合时间到【信息级】/ Max time reached, info level
                    _bCmdStopReq := TRUE;                // 判 NG 停机（Stop on NG）
                    bNg := TRUE;                         // 不合格出口（NG outlet）
                    bDone := TRUE;                       // 完成单拍（R25 本拍闭环）/ Done pulse (R25)
                    _ePhase := E_DL_MixPhase.eNg;
                END_IF
            END_IF

        E_DL_MixPhase.eVerify: // 终点确认：稳速容差内确认后锁存进料
            IF _bFiniteSpd AND (ABS(fActSpeed - _fSetEff) <= _fSetEff * DL_MIX_VERIFY_FRAC) THEN
                _fFreqReq := DL_MIX_DISCHARGE_SPD;       // 出料助排慢速设定（Discharge assist setpoint）
                _bCmdFreqReq := TRUE;                    // 登记设定（Register setpoint）
                _ePhase := E_DL_MixPhase.eDischarge;     // 进入出料（Enter discharge）
            END_IF

        E_DL_MixPhase.eDischarge: // 出料中：慢速助排，等出料完成
            IF bDischargeDone THEN
                _bCmdStopReq := TRUE;                    // 出料完成停转（Stop after discharge）
                _ePhase := E_DL_MixPhase.eSpinDown;      // 进入停转（Enter spin-down）
            ELSIF _fbTonDischTo.Q THEN
                _bCmdStopReq := TRUE;                    // 超时停机（Stop on timeout）
                _bFaultLatch := TRUE;
                _uErrorIdInt := DL_MIX_ERR_DISCH;        // 0005_0262 出料超时【故障级】/ Discharge timeout, fault level
                _ePhase := E_DL_MixPhase.eFault;
            END_IF

        E_DL_MixPhase.eSpinDown: // 停转：等待转速落零
            IF _bFiniteSpd AND (fActSpeed < DL_MIX_STOP_EPS) THEN
                bOk := TRUE;                             // 合格出口（OK outlet）
                bDone := TRUE;                           // 完成单拍（R25 本拍闭环）/ Done pulse (R25)
                _ePhase := E_DL_MixPhase.eDone;          // 进入完成保持（Enter done hold）
            END_IF

        E_DL_MixPhase.eDone: // 完成保持：判定每拍重算保持（复位路径在段 2）
            bOk := TRUE;                             // 合格保持（OK verdict held every scan）

        E_DL_MixPhase.eNg: // 不合格保持：判定每拍重算保持
            bNg := TRUE;                             // 不合格保持（NG verdict held every scan）

        E_DL_MixPhase.eAbort: // 中止保持：停转完成，禁止出料，等复位
            // 等复位（Awaiting reset）

        E_DL_MixPhase.eFault: // 故障锁存：等复位
            // 等复位（Awaiting reset）

        ELSE // 非法状态兜底（本块专用码位）
            _bCmdStopReq := TRUE;               // 非法状态立即停（Stop on illegal state）
            _bFaultLatch := TRUE;
            _uErrorIdInt := DL_MIX_ERR_STATE;   // 0005_0265 非法状态兜底【故障级】/ Illegal state fallback, fault level
            _ePhase := E_DL_MixPhase.eFault;
    END_CASE
END_IF

// ============================================================================
// 段 5｜接口单发指令调度器（公约 0.13：每拍至多一次方法调用，结构保证）
//      Interface single-shot dispatcher (0.13: at most one method call per scan)
// ============================================================================
IF NOT bEnable THEN
    _bCmdRunReq := FALSE;               // 使能撤销撤销全部请求（Disable revokes all requests）
    _bCmdFreqReq := FALSE;
    _bRunIssued := FALSE;               // 运行锁存撤销（Run latch revoked）
    IF _ePhase <> E_DL_MixPhase.eIdle THEN
        _bCmdStopReq := TRUE;           // 残余运行先停（Stop residual run）
    END_IF
END_IF

IF _bCmdStopReq THEN
    IF iDrive.CmdStop() THEN            // 停止指令无条件受理（Stop unconditionally accepted）
        _bCmdStopReq := FALSE;          // 消费请求（Consume request）
        _bCmdRunReq := FALSE;           // 停止优先：清运行/设定请求（Stop clears run/freq requests）
        _bCmdFreqReq := FALSE;
        _bRunIssued := FALSE;           // 运行锁存撤销（Run latch revoked）
        _fFreqLast := 0.0;              // 末次设定清零（Last setpoint reset）
    END_IF
ELSIF _bCmdRunReq THEN
    IF iDrive.CmdRun(bFwd := _bRunFwd) THEN   // 运行指令（Run command with direction）
        _bCmdRunReq := FALSE;           // 消费请求（Consume request）
        _bRunIssued := TRUE;            // 运行锁存登记（Run latch registered）
    END_IF
ELSIF _bCmdFreqReq THEN
    IF iDrive.SetFrequency(fHz := _fFreqReq) THEN   // 设定指令（SetFrequency command）
        _bCmdFreqReq := FALSE;          // 消费请求（Consume request）
        _fFreqLast := _fFreqReq;        // 登记末次下发（Register last sent）
    END_IF
END_IF

// ============================================================================
// 段 6｜出口派生（方向互斥断言由同源派生保证；进度折算除前判零）
//      Outlet derivation (mutual exclusion by common source; progress divide guarded)
// ============================================================================
bDirForward := _bRunIssued AND _bDirFwd;             // 正转出口（Forward outlet）
bDirReverse := _bRunIssued AND (NOT _bDirFwd);       // 反转出口（Reverse outlet），与正转同源互斥 / Mutually exclusive by source

IF (_ePhase = E_DL_MixPhase.eDischarge) AND _bRunIssued THEN
    fSpeedCmd := DL_MIX_DISCHARGE_SPD;               // 出料助排慢速（Discharge assist speed）
ELSIF _bRunIssued THEN
    fSpeedCmd := _fSetEff;                           // 搅拌设定转速（Mixing setpoint）
ELSE
    fSpeedCmd := 0.0;                                // 停转（Standstill）
END_IF

// 进度折算：已混合秒值/目标秒值 [-]，钳位 [0,1]（R20 量纲：无量纲）
// Progress: elapsed seconds / target seconds, clamped 0..1 (dimensionless per R20)
IF TIME_TO_REAL(_tMixEff) > DL_MIX_EPS THEN
    fProgress := LIMIT(0.0, TIME_TO_REAL(_tElapsedInt) / TIME_TO_REAL(_tMixEff), 1.0);
END_IF

// 判定互斥出口断言（规格 §6-8）：OK 与 NG 恒不同真，冲突时 NG 优先
// Verdict mutual-exclusion assertion: OK and NG never both TRUE, NG wins
IF bOk AND bNg THEN
    bOk := FALSE;                                    // 不合格优先（NG priority）
END_IF

bBusy := (_ePhase = E_DL_MixPhase.ePreCheck)
      OR (_ePhase = E_DL_MixPhase.eMixing)
      OR (_ePhase = E_DL_MixPhase.eVerify)
      OR (_ePhase = E_DL_MixPhase.eDischarge)
      OR (_ePhase = E_DL_MixPhase.eSpinDown);        // 执行中派生（Busy derived）

ePhase := _ePhase;                       // 相位镜像（Phase mirror）

// ============================================================================
// 段 7｜bError/uErrorId 出口（R21：bError 显式排除信息级码）
//      Outlets: bError excludes info codes (R21)
// ============================================================================
bError := _bFaultLatch;                  // 故障级派生式（Fault-level derived form）
IF _bFaultLatch THEN
    uErrorId := _uErrorIdInt;            // 故障级码优先透出（Fault-level priority）
ELSE
    uErrorId := _uInfoCode;              // 无故障时透出本拍信息级码（Transient info code）
END_IF
END_FUNCTION_BLOCK