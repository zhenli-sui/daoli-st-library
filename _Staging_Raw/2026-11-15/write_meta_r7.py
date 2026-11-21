# -*- coding: utf-8 -*-
"""R7 阶段四：写 16 份 meta JSON（instruction / architecture_thought）"""
import json, io, sys, os
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
META = r"C:\Library\_Staging_Raw\2026-11-15\meta"

M = {
"FB_DL_EventCounter": {
 "instruction": "R7 泳道 D #1：按 ROUND_PLAN_R7 §1.1 与第 0 节公共约定编码 FB_DL_EventCounter（双向事件计数器，DINT 域），落盘 C:\\Library\\DL_Base\\FB_DL_EventCounter.st。四 R_TRIG 实例主体最前部无条件刷新（R7/0.5）；事件型免首扫（R23）；bLoad 优先级最高（同拍覆盖计数脉冲置信息级 0001_0102）；双脉冲同拍抵消极变化 0（信息级 0001_0101）；回绕/饱和双模式（bWrap 选择，越界事件一拍脉冲）；比较输出每拍重算非锁存；nMin>=nMax 故障锁存 0001_0210 仅复位路径清码（R15）；bFault 显式排除信息级（R21）。全部引脚双语同行注释，码位经 DL_Base VERSION.md 核对未占用。",
 "architecture_thought": "架构上坚持『单一语义原子』：本块只做计数这一件事，越界策略（回绕/饱和）作为可引脚切换的同层行为而非子状态机，避免事件计数引入 CASE 主状态机的时序歧义——四个边沿全部前置无条件刷新后，计数主链是纯单拍组合逻辑，可逐拍推演验收（V1~V6 向量全部单拍可复算）。溢出/下溢做成一拍事件脉冲而非锁存位，把『事件通知』与『持续状态』分离：持续状态由比较输出（每拍重算）承载，HMI 报警与事件记录各取所需。故障位派生式显式排除信息级码，信息级（抵消/装载覆盖）只进 uErrorId——与全库 R21 口径一致。"
},
"FB_DL_ModuloCounter": {
 "instruction": "R7 泳道 D #2：按 ROUND_PLAN_R7 §1.2 编码 FB_DL_ModuloCounter（循环计数器/转盘工位索引），落盘 C:\\Library\\DL_Base\\FB_DL_ModuloCounter.st。R7/0.5 四 R_TRIG 前置无条件刷新；事件型免首扫（R23）；取模回绕禁用取余运算符负数平台差异——条件加减法在 DINT 域运算后显式 DINT_TO_UINT 回写（CODESYS/TwinCAT/汇川三平台一致，注释留档）；nMod<2 故障锁存 0001_0211（除零与退化防御）；nJumpTo 越界拒绝置信息级 0001_0103；双向同拍抵消 0001_0104；bWrapped 跨零点一拍。码位经 DL_Base VERSION.md 核对。",
 "architecture_thought": "与 FB_DL_EventCounter 职责正交（通用事件计数 vs 取模索引）而非参数化复用：取模块的域不变量（uIndex 0..nMod-1）是强契约，值得用独立块承载并在每个出口做显式转换与回绕。回绕实现刻意避开取余运算符——UINT 负数取余在三目标平台行为不一，条件加减法（减 nMod/加 nMod）+ DINT 中间域 + 显式转换是可逐平台复核的写法，跨平台意图写入注释。跳步校验在沿路径拒绝而非钳位：越界跳步是操作错误，静默钳位会把操作错误变成静默错位，拒绝+信息级才能被 HMI 捕获。"
},
"I_DL_BarcodeScanner": {
 "instruction": "R7 泳道 A #3：按 ROUND_PLAN_R7 §2.1 编码 I_DL_BarcodeScanner（固定式扫码枪抽象接口，公约 0.11 三段式），落盘 C:\\Library\\DL_Device\\I_DL_BarcodeScanner.st。同文件发布 E_DL_ScannerState（eIdle=0/eTriggered=10/eReading=20/eOk=30/eNoRead=40/eFault=99，步长 10、eFault 末位、双语注释）；属性 8 个全 PROPERTY GET；方法 3 个（CmdTrigger/CmdAck/CmdReset，≤6 红线）；故障态一律拒绝方法返回 FALSE；接口层不做串口/总线收发（数据经实现块 IN_OUT 注入）。溯源标注 tcopen-component/scanner-handshake，clean-room。",
 "architecture_thought": "接口按『读侧属性 + 写侧方法最小集』切分：8 个 GET 覆盖状态/结果/诊断三维（eState 供时序联锁、bReadOk+sBarcode 供结果消费、bFault+uErrorId 供报警分组），3 个方法恰为握手闭环的最小动作集（触发/应答/复位）——NoRead 不设专门方法，因为 NoRead 是结果态而非指令，消费链与 eOk 同用 CmdAck，接口面因此最小。nReadCount 刻意声明为『复位不清零』：批次追溯口径下累计产线计数是资产数据，复位只能清握手态不能清统计。"
},
"FB_DL_SerialScanner": {
 "instruction": "R7 泳道 A #4：按 ROUND_PLAN_R7 §2.2 编码 FB_DL_SerialScanner（实现 I_DL_BarcodeScanner），落盘 C:\\Library\\DL_Device\\FB_DL_SerialScanner.st。接口属性同名成员按 R22 以只读 PROPERTY GET 承载，bTriggerOut/bDataAck 保留 VAR_OUTPUT；状态机 E_DL_ScannerState + CASE + ELSE 兜底；R24 范式：_bTriggerReq 于状态机置位、段 1 TP 实例调用之后立即自清（自清在实例调用之后，验收向量 V6 三段逐拍推演）；结果窗 TON 无条件刷新；一次 NoRead 自动重试（nRetryMax 钳 0~5）、连续 3 次升级故障 0003_0280；CR/LF 剥离 FOR 循环以 LEN 为界；超长 LEFT 截断置信级 0119；就绪门控恒 FALSE 跳过（一次性信息级 0120）。码位经 DL_Device VERSION.md 核对顺延（规格建议 0250/0251/0252 已被 VfdGeneric 占用）。",
 "architecture_thought": "握手块刻意只编排握手、不碰数据本体：sRawData 经 IN_OUT 注入、bDataNew/bDataAck 组成最小握手机，串口/总线差异全部留在接收层——本块换平台零改动。R24 缺陷（R6 两处致命根因）在结构上根治：触发脉冲请求只有一个写入者（状态机）和一个自清点（TP 实例调用之后一行），时序上不可能出现『同拍置位又自清导致 TP 恒采不到 TRUE』。NoRead 升级链做成计数器而非独立状态：单次 NoRead 是正常业务结果（信息级），连续 3 次才是设备级异常（故障级），阈值常量化并注释标定依据。"
},
"I_DL_SafetyDoor": {
 "instruction": "R7 泳道 A #5：按 ROUND_PLAN_R7 §2.3 编码 I_DL_SafetyDoor（电磁锁扣门联锁抽象接口），落盘 C:\\Library\\DL_Device\\I_DL_SafetyDoor.st。同文件发布 E_DL_SafetyDoorState（eIdle=0/eLocked=10/eStopRequested=20/eStandstillConfirmed=30/eUnlocked=40/eOpened=50/eFault=99）；属性 7 个 GET；方法 4 个（CmdRequestUnlock/CmdRelock/CmdReset/CmdAuditClear）；门开态拒绝 CmdRelock 之外全部动作；头部与注释显式声明公约 0.13「非认证安全功能」定位。溯源 tcopen-component/safety-interlock（ISO 14119 公开语义），clean-room。",
 "architecture_thought": "解锁时序的六个态全部进接口枚举而非隐藏在实现内部：上层工站与 HMI 需要按『停机请求已发/静止已确认/已解锁/门已开』分态联锁与显示，时序可见性就是契约的一部分。CmdAuditClear 独立于 CmdReset：开门审计计数是批次质量数据（收尾清零），故障复位是安全操作（只在故障态受理），两者生命周期不同必须拆分方法。定位声明写入文件头：本库安全件一律是『逻辑编排与诊断镜像层』，认证安全回路边界显式留档，防止下游误用为安全功能。"
},
"FB_DL_GuardLockDoor": {
 "instruction": "R7 泳道 A #6：按 ROUND_PLAN_R7 §2.4 编码 FB_DL_GuardLockDoor（实现 I_DL_SafetyDoor），落盘 C:\\Library\\DL_Device\\FB_DL_GuardLockDoor.st。解锁链硬约束出口断言式：bUnlockCoil 置位前提 =（bStandstill 或 tRunDown 计满）AND bDoorClosed AND bLockEngaged；防篡改冲突（门开+锁闭反馈同真）全局监视锁存 0291；静止确认超时 0290（TON 常量窗）；关门再锁定确认窗（常量 T#2S）超窗 0292；重启抑制：开门事件后必须 bReset 且门锁全确认才回 eIdle，无自动重启路径；run-down 模式信息级 0121；R7 五实例前置无条件刷新；CASE+ELSE 兜底 0293。码位顺延留档（0260/0261/0262 已被 AnalogValve 占用）。",
 "architecture_thought": "安全时序块的关键是把『硬约束』从时序状态机里剥离成出口断言：bUnlockCoil 不由状态机直接置位，而是每拍按三条件重算——即使状态机被非法态兜底打断，电磁铁输出仍由断言兜底，这是诊断镜像层能给出的最强保证。静止确认双模式（零速反馈/run-down 计时）做成引脚二选一而非两个状态机：run-down 计时器 IN 条件在段 1 无条件推导，模式切换只是换判据源。审计计数与重启抑制分离：uOpenCount 是质量数据，_bRestartInhibit 是安全语义，复位路径分别处理（复位沿清抑制，审计仅 CmdAuditClear 清）。"
},
"I_DL_LightCurtain": {
 "instruction": "R7 泳道 A #7：按 ROUND_PLAN_R7 §2.5 编码 I_DL_LightCurtain（安全光幕监控与屏蔽抽象接口），落盘 C:\\Library\\DL_Device\\I_DL_LightCurtain.st。同文件发布 E_DL_CurtainState（eClear=0/eBlocked=10/eMuting=20/eOverride=30/eFault=99）；属性 7 个 GET（含核心安全镜像位 bSafeStop）；方法 3 个（CmdOverride/CmdAck/CmdReset）；边界防错：bSafeStop 永不因屏蔽/override 置假（屏蔽态断言恒 FALSE）；公约 0.13 定位声明。溯源 tcopen-component/light-curtain-muting，clean-room。",
 "architecture_thought": "bSafeStop 在接口注释里被定义为『核心安全镜像位』并配硬边界防错条款——屏蔽/override 的全部编排价值都建立在『不削弱停机镜像』之上，这条防错写进接口而非只写在实现块，让任何实现者在落地前就面对约束。CmdAck 与 CmdReset 分工：屏蔽序列中止是工艺操作（回评估态），故障复位是安全联锁（仅故障态），合并会诱导『用复位键跳过屏蔽中止』的误操作。"
},
"FB_DL_SafetyLightCurtain": {
 "instruction": "R7 泳道 A #8：按 ROUND_PLAN_R7 §2.6 编码 FB_DL_SafetyLightCurtain（实现 I_DL_LightCurtain），落盘 C:\\Library\\DL_Device\\FB_DL_SafetyLightCurtain.st。2/4 传感器序列屏蔽步进机（电平条件级联，首遮挡传感器判向、方向锁定，序列错乱即故障 02A0 退出屏蔽）；屏蔽总时长 TON 超时 02A1；OSSD 双通道不一致 TON 容差窗 02A2；override 准入硬约束（钥匙/方法 AND 至少一传感器遮挡，无遮挡拒绝置信级 0122），硬帽 TON 到期退出置信级 0118；屏蔽灯常亮/override 闪烁（TON 振荡器 IN:=NOT Q 自实现方波，R14 不适用注释说明）；bSafeStop 出口断言（屏蔽/override/故障恒 FALSE）；复位联锁：故障源消失才解除。状态为条件派生映像（无 CASE 主状态机，偏离留档：非法状态兜底码不适用取消）。码位顺延留档（0270/0271/0272/0106 已占）。",
 "architecture_thought": "序列屏蔽用『步号 + 映射传感器』而不是四个独立状态机：方向判定一次（首遮挡传感器），之后 E1/E2/X1/X2 四个映射信号让正反向共用同一步进机，代码量减半且对称性可逐拍推演。步进机全部用电平条件级联而非沿触发——沿检测在传感器抖动下会丢步，电平条件每拍重判天然自愈；代价是错序判定也用电平（某传感器提前清离即错），保守侧宁可误报故障。override 硬帽与屏蔽超时是两把独立的钟：前者保护滞留清除操作员，后者保护序列本身。"
},
"I_DL_FlowMeter": {
 "instruction": "R7 泳道 A #9：按 ROUND_PLAN_R7 §2.7 编码 I_DL_FlowMeter（流量计抽象接口，脉冲/模拟型均可适配），落盘 C:\\Library\\DL_Device\\I_DL_FlowMeter.st。同文件发布 E_DL_FlowMeterState（eIdle=0/eMeasuring=10/eFlowOk=20/eLowCutoff=30/eFault=99，eLowCutoff=低流量截止态）；属性 6 个 GET（fFlowRate REAL [L/min] / fTotal LREAL [L] 防累计精度丢失 / nPulseCount）；方法 3 个（CmdTotalReset/CmdTotalPreset(fPreset)/CmdReset，预置非有限值/负值拒绝）。溯源 tcopen-component/flow-totalizer，clean-room。",
 "architecture_thought": "fTotal 用 LREAL 是本接口最重要的类型决策：UDINT 脉冲计数累计到 LREAL 体积，REAL 在 1E7 L 量级已丢脉冲精度，LREAL 把精度边界推到 9.0E15 并把预警职责（bTotalNearLimit 留给实现块）写进契约注释。eLowCutoff 作为独立态而非 bFlowOk 的反面：低流量截止是『有效但被截零』的计量语义（信息级），与 eFlowOk/eIdle 的状态机语义不同，HMI 需要区分『没流量』与『有流量但被截止』。"
},
"FB_DL_PulseFlowMeter": {
 "instruction": "R7 泳道 A #10：按 ROUND_PLAN_R7 §2.8 编码 FB_DL_PulseFlowMeter（实现 I_DL_FlowMeter），落盘 C:\\Library\\DL_Device\\FB_DL_PulseFlowMeter.st。R_TRIG 脉冲沿计数 → 自重触发 TON 采样窗（IN:=NOT Q）→ 窗沿双缓冲整窗交换（读侧无撕裂）→ K 系数换算 [L/min]；总量脉冲计数法 fTotal += 窗脉冲/K；除零防御三处（K 非法故障锁存 02B0、窗秒数钳位域恒非零+显式 ABS 分支）；低流量截止（输出置零 + eLowCutoff + 信息级 0113）；脉冲丢失超时（流量置零 + 0114）；窗内超 DL_PULSE_WIN_MAX 置信息级 0115（提示 HSC）；fTotal > 9.0E15 预警 bTotalNearLimit；滑动窗计数 Device 层内联（不引 DL_MathData，依赖方向合规）。码位顺延留档（0107~0109 已占）。",
 "architecture_thought": "统一窗法（放弃周期法）是跨平台简化决策：单窗脉冲数/窗秒/K 的三段除法每段都带显式 ABS 防零分支，比周期法（依赖相邻沿间隔）对抖动鲁棒且无需捕获高频沿间隔。双缓冲的理由：读侧（HMI/批控）可能在任意拍读 nPulseCount，若直接读计数缓冲会在窗中段读到半程值——窗沿整窗交换让读侧永远看到完整窗。增量累计只在窗沿发生一次，fTotal 的写频率与窗频同阶，避免每拍浮点累加误差。"
},
"I_DL_LevelSwitch": {
 "instruction": "R7 泳道 A #11：按 ROUND_PLAN_R7 §2.9 编码 I_DL_LevelSwitch（点式料位开关抽象接口，振动叉/阻旋/电容通用），落盘 C:\\Library\\DL_Device\\I_DL_LevelSwitch.st。同文件发布 E_DL_LevelState（eNoMaterial=0/eMaterial=10/eSensorLoss=20/eFault=99）与 E_DL_FailSafeMode（eHigh=0 失效报有料防溢流 / eLow=1 失效报无料防干转）；属性 6 个 GET（bMaterial 已归一、bHighAlarm/bLowAlarm 双联锁方向语义写死注释）；方法 2 个（CmdReset/CmdTest）。溯源 tcopen-component/level-switch-failsafe，clean-room。",
 "architecture_thought": "E_DL_FailSafeMode 与 E_DL_LevelState 同文件发布是刻意安排：失效方向是本接口契约的语义核心（决定失效时报警走向高点还是低点），与状态枚举同权重。bHighAlarm/bLowAlarm 双输出而非单 bAlarm+方向引脚：两个报警进不同的联锁链（高点停进料、低点停出料），调用方接线时方向语义已写死在注释，防现场反接。"
},
"FB_DL_LevelSwitchVib": {
 "instruction": "R7 泳道 A #12：按 ROUND_PLAN_R7 §2.10 编码 FB_DL_LevelSwitchVib（实现 I_DL_LevelSwitch），落盘 C:\\Library\\DL_Device\\FB_DL_LevelSwitchVib.st。防抖 TON×2 → 覆盖/裸露双延迟确认 TON×2（全部 R7 前置无条件刷新）；失效安全归一核心：bRawSwitch XOR (eFailSafeMode=eLow) 语义等价式用 IF 显式写（禁 XOR 裸用，极性约定注释写明防接反）；bEnable=FALSE 或故障时输出强制归一到安全侧（eHigh→有料/eLow→无料，出口断言式）；模式枚举越界故障锁存 02C0；传感器失效检测预留（0116 信息级 + eSensorLoss 态已登记，算法后续轮次落地，R11 留档）。码位顺延归一留档（0290 已被本轮 GuardLockDoor 顺延占用、010a 编号惯例不一致）。",
 "architecture_thought": "双级时间滤波（防抖→确认延迟）对应两种物理噪声：防抖吃触点抖动（毫秒级），确认延迟吃液面波动（秒级），合并成单 TON 会把两种整定耦合在一个引脚上。归一式用 IF 显式展开而不是 XOR 运算符：极性约定（eLow 组态 raw TRUE=无料）是现场接线契约，显式分支让接线工程师能直接对照注释核查，位运算技巧会把契约藏进表达式。失效检测本轮只留码位与状态占位——诚实声明能力边界比塞入半成品诊断算法更符合『宁减不凑』。"
},
"FB_DL_OeeCalculator": {
 "instruction": "R7 泳道 B #13：按 ROUND_PLAN_R7 §3.1 编码 FB_DL_OeeCalculator（OEE 班次统计引擎），落盘 C:\\Library\\DL_Process\\FB_DL_OeeCalculator.st。时间累计扫描周期累加式，周期基准经新增引脚 tCycleTime 注入（默认 T#10MS，非数/非正回落常量，禁读 CPU 钟）；根因位引脚注入不引组件实例；时间分账优先级计划外>计划>运行，双停机同真信息级 0110 分账入计划外；三因子除零防御（PlannedTime=0→全因子 0+信息级 0112；RunTime=0→A/P=0、Q=100；TotalCount=0→Q=100）；Performance=(节拍×总数)/运行秒×100 超 100 封顶+信息级 0111；bShiftStart 沿清零启动、bShiftEnd 沿冻结三因子；fIdealCycleTime 非数/非正故障锁存 0200。R7 七 R_TRIG 前置无条件刷新。码位经 DL_Process VERSION.md 核对顺延（0100~0102 已占）。",
 "architecture_thought": "OEE 块的架构难点是时间语义而非公式：PlannedTime 刻意定义为『不含计划停机的计划生产时间』（ISO 22400 口径），Availability 分母因此排除换型/休息——这一口径注释写死，防止现场按 oee.com 简化口径（含计划停机）误读。性能封顶是数据质量哨兵：Performance>100 数学上不可能，出现即节拍偏短或计数异常，封顶+信息级让异常可见而不污染报表。班次启停显式化（沿驱动清零/冻结）而非自动按钟：班次边界是管理语义，块内不自作主张。"
},
"FB_DL_ConveyorZone": {
 "instruction": "R7 泳道 B #14：按 ROUND_PLAN_R7 §3.2 编码 FB_DL_ConveyorZone（ZPA 积放单区），落盘 C:\\Library\\DL_Process\\FB_DL_ConveyorZone.st。消费既有接口 I_DL_VfdDrive（R6 契约件，仅引用零修改）：iDrive.CmdRun(bFwd)/CmdStop() 每拍至多一次方法调用（0.13），反馈读 iDrive.bRunning/bFault；积放单句规则 RunReq=使能 AND 无卡料 AND 无故障 AND（有料 OR 上区补跑）AND（下游允许 OR 出口空），末区语义由接线承担不内判；卡料窗（RunReq+出口遮挡超 tJamWindow）锁存仅 bReset 清，计时中信息级预警 0113；指令-反馈失配超 tStartDelay 故障 0212；iDrive.bFault 透传 0213；使能沿浪涌延迟 tStartDelay 再发令（间隔释放由多区 bZoneReady 级联天然承载）；手动放行沿短时绕过下游条件；CASE+ELSE 兜底 0214。码位顺延留档（0210/0211/0103 已占）。",
 "architecture_thought": "本块是『接口消费范式』的示范件：对 I_DL_VfdDrive 只调方法/读属性、零内部状态假设，指令-反馈失配检测（XOR 条件 + TON）完全建立在接口既有属性上——换任何 I_DL_VfdDrive 实现块本区零改动。积放规则刻意写成一行布尔式并在注释逐项标注：ZPA 的全部价值就在这一句的可读性，拆散进状态机分支反而难审。手动放行绕过下游条件但绕不过卡料/故障锁存——调试便利不得越过安全锁存。"
},
"FB_DL_BatchDosingControl": {
 "instruction": "R7 泳道 B #15：按 ROUND_PLAN_R7 §3.3 编码 FB_DL_BatchDosingControl（单料批次相配料称重控制），落盘 C:\\Library\\DL_Process\\FB_DL_BatchDosingControl.st。E_DL_DosingPhase 随本块发布（eIdle/eCoarse/eFine/eSettling/eDone/eNg/eAbort/eFault=99）；三段顺控：快加至 fSwitchCoarse（0=默认 85% 设定值）切慢加，慢加关断重量 = fSetpoint − fInflightComp（截断点公式）；落定稳窗判稳（重量变化 < fFlowDeadband），超窗重试 3 次按当前值结算+信息级 0114；结算一次性执行（判稳拍）：锁存 fFinalWeight、公差判定 bBatchOk、学习 fInflightComp += Error/2（半误差防振荡，钳位 ±fCompLimit 触限信息级 0115）；断流监视窗（给料相重量零进给超 tFlowWatch）故障锁存 0220；fWeight 非数批次中止 0221 全断；Abort 电平 CASE 首分支最高优先全断；配方参数非法 0223；CASE+ELSE 兜底 0222。R7 五实例前置无条件刷新。码位经 DL_Process VERSION.md 核对。",
 "architecture_thought": "结算与学习收敛到『判稳拍一次性执行』是本块最重要的时序决策：若放在 eDone 态每拍执行，学习值会按扫描频率重复累加、fFinalWeight 随秤漂移——半误差学习链（V2 向量 5 批收敛）只在单拍结算下成立。断流判据用『窗沿零进给 + 基准前移』而非瞬时变化率：慢加速率本就低于单扫描死区，瞬时判据会误报；窗沿比较让死区语义与整定窗解耦。Abort 做成 CASE 首分支的电平优先而非异常处理：中止是操作员意志，任何相态立即服从，恢复走显式回空闲路径。"
},
"FB_DL_SoftLimitGuard": {
 "instruction": "R7 泳道 C #16：按 ROUND_PLAN_R7 §4.1 编码 FB_DL_SoftLimitGuard（软限位电子围栏预判器），落盘 C:\\Library\\DL_Motion\\FB_DL_SoftLimitGuard.st。消费既有接口 I_DL_MotionAxis（读 iAxis.fPosition/fVelocity，R11 留档选定接口属性、弃用 fAxisSpeed 备选引脚）；预判公式 fStopDist = fSpeed×tLatency_s + fSpeed²/(2×fDecel)，tLatency TIME_TO_REAL 毫秒口径显式换算秒（默认 T#23MS=扫描 10+IO 5+驱动 8ms，注释写明三项来源）；预警/拦截两级派生（预警带=不含裕量、拦截=含 fMargin，预警⊇拦截）；bEnable=FALSE 仅监视（拦截输出强制 FALSE）；方向语义：拦截态仅允许反向指令（向内恢复豁免），输出为建议信号、拦截执行在调用方（职责边界注释写明）；fDecel 非数/趋零故障锁存 0240，行程边界非法 0241，复位联锁=离开越界区才可解除；时延默认口径一次性提示 0108。公约 0.13 定位声明。码位顺延留档（0220/0221/0106/0107 已占）。",
 "architecture_thought": "监视型预判块不用主状态机：预警/拦截全部是位置-速度的纯派生式，每拍可复算、天然无态可坏——故障锁存是唯一状态量，且复位联锁（离开越界区）写进复位路径。两级判据的分层是可解释性设计：预警（数学触碰边界）供 HMI 黄灯，拦截（含裕量越界）供调用方禁令，裕量引脚让同一物理轴可配不同保守度。位置/速度非数防御采用保持末次有效值而非清零：清零会让预判距离瞬间塌缩成『安全假象』，保持旧值让拦截判据在信号恢复前维持保守。"
},
}
for name, m in M.items():
    with open(os.path.join(META, name + '.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump(m, f, ensure_ascii=False, indent=2)
        f.write('\n')
print('meta written:', len(M))
