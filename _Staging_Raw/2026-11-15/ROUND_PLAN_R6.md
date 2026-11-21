# ROUND_PLAN_R6 —— Round 06 引脚级规格书（16 项）

> 轮次：R6（2026-11-15）｜ 方向：**DL_Device 阀门/驱动族深化（LBP T2-2）** + DL_Motion 回零/运动封装（T1-6 PLCopen 首次开组）+ DL_Process 行业池 9.5 节 P0 两件 + DL_Algo LGF Technology 深化
> 编制：道莅工控代码库产品总监（兜底模式）｜ 狩猎留痕：同目录 `RAW_NOTES_R6.md`（S-1~S-5）
> 执行规则：本规格书为编码阶段唯一契约；偏离必须依规则 R11 在头注释留档。
> 合规铁律（T2-2 LBP / 西门子资产）：只借功能分类与参数域，**clean-room 独立实现**；每个 `.st` 文件头「开源溯源 (Origin)」按 RAW_NOTES_R6 对应 S 条目如实标注。

---

## 第 0 节 公共约定（编码侧逐字遵守，优先级高于逐组件条款）

0.1 **R19 首扫范式**：含初始化/跟踪逻辑的 FB 首扫判据一律 `IF bTrack OR (NOT bInit) THEN ... bInit := TRUE`（bInit 初值 FALSE），禁止反序写法；验收向量必含「运行中途插入跟踪脉冲」向量。**R23 例外**：纯事件型组件（输入输出均为 BOOL 电平/脉冲，无连续量同步语义）不设 bInit，逐组件条款已标注「事件型 / 免首扫」。
0.2 **R21 信息级码**：`bFault`/`bError` 一律为显式排除信息级码的派生式；故障码表逐条标注【故障级】/【信息级】；信息级码只进 `uErrorId` 不进报警链。
0.3 **R20 量纲**：状态变量注释量纲 = 赋值表达式量纲推导结果；被限幅钳位的量，注释量纲与限幅域一致。
0.4 **双语注释**：每个引脚/枚举项声明行 `// 中文物理意义（English term）[单位] 取值范围/默认行为`。
0.5 **时间基准显式化**：连续量组件（RampSoakProfile）`tSampleTime : TIME := T#100MS` 显式引脚；纯事件型组件用 TON 超时引脚即可。
0.6 **限幅对调自修复**：参数对 `fXxxMin > fXxxMax` 时对调 + 置信息级码 + 继续计算，不中断。
0.7 **故障码段位（沿用 R5 公约 0.7）**：DL_Device `16#0003_xxxx`、DL_Motion `16#0004_xxxx`、DL_Process `16#0005_xxxx`、DL_Algo `16#0002_xxxx`。信息级 `16#0xxx_01xx`、故障级 `16#0xxx_02xx` 起。**本轮码位分配避开 R1~R5 已占码**（编码前与各子库 VERSION.md 故障码表核对一次，冲突顺延）。分配台账见第 7 节。
0.8 **非有限值防御**：FC/FB 全部 REAL 输入先做 `fX <> fX` 检测再比较；出口默认值在第一条防御 IF 之前赋值。
0.9 **零全局耦合**：时间/温湿度/反馈量一律引脚注入，禁读 CPU 钟；禁一切物理地址与全局变量表引用。
0.10 **文件头红线自检用语义描述**：头注释描述红线时**严禁出现被禁记号原文**（GVL/外部变量声明/物理地址字样一律以「零全局变量表与外部变量引用」「零物理 IO 地址直写」等语义转述），防止机检自伤（规则 R10）。
0.11 **接口契约三段式**：每个 `I_DL_*` 按「状态枚举（同文件，头注释注明归属）+ 属性（PROPERTY GET）+ 方法（METHOD）」三段定义；方法 ≤6。
0.12 **R22 接口实现块 OUT 列**：规格 OUT 列成员与接口属性同名者，实现块以只读 PROPERTY GET 承载，非接口成员保留 VAR_OUTPUT；头注释 R11 留档。
0.13 **R7 定时器/边沿**：TON/TOF/R_TRIG/F_TRIG 实例在主体最前部无条件周期刷新，严禁置于 IF/CASE 分支；实例入参一律先算成普通变量再喂实例。
0.14 **R14 语义参数变更**：TON 的 PT/相位类语义参数变化时必须显式断输入一拍使已计时归零。
0.15 **R15 故障码锁存**：锁存型故障只在解除路径清码；瞬时型告警每拍重算，不得混写。

### 泳道划分（三泳道并行编码，互不冲突）

| 泳道 | 组件 | 文件落点 | 泳道内自持契约 | 跨泳道依赖 |
|---|---|---|---|---|
| A | #1~#10（DL_Device 10 项） | `C:\Library\DL_Device\` | 4 个新接口枚举各自随接口文件发布；#1 复用既有 I_DL_Cylinder 契约 | 无 |
| B | #11~#13（DL_Motion 3 项） | `C:\Library\DL_Motion\` | E_DL_HomingMode/E_DL_HomingStep 随 #11 文件发布 | 仅依赖既有 I_DL_MotionAxis |
| C | #14~#16（DL_Process 2 + DL_Algo 1） | `DL_Process\` / `DL_Algo\` | E_DL_RampSoakPhase 随 #16 文件发布 | 仅依赖既有 FC_DL_HumidAirEnthalpy / FB_DL_TimeWindowCheck / FC_DL_DayOfWeekCalc |

三泳道之间零新增共享 DUT、零文件交集；公共依赖全部为已入库组件，天然无合并冲突。

---

## 第 1 节 泳道 A｜DL_Device 阀门/驱动族（10 项，T2-2 LBP，标签 `lbp-basic-process` / `lbp-device`）

### 1.1 `FB_DL_SingleSolenoidCyl`（功能块，实现 I_DL_Cylinder）｜DL_Device｜来源标签 `lbp-device`

功能：单电控（单线圈）弹簧复位气缸驱动。得电伸出、失电弹簧缩回；无传感器纯时间模式 + 可选磁开关反馈校验。**事件型，免首扫（R23）**。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bCmdExtend | BOOL | IN | 伸出指令（Extend command），上升沿生效；失电即弹簧缩回 |
| bSnsExtended | BOOL | IN | 可选伸出到位磁性开关（Optional extended reed switch），TRUE=到位；未接时恒 FALSE |
| bSnsRetracted | BOOL | IN | 可选缩回到位磁性开关（Optional retracted reed switch），TRUE=到位 |
| bUseSensorCheck | BOOL | IN | 反馈校验使能（Sensor check enable），TRUE=时间+磁开双重校验；FALSE=纯时间模式 |
| bInterlock | BOOL | IN | 允许动作联锁（Motion interlock），TRUE=允许伸出，默认 FALSE 线圈保持断开 |
| tStrokeTimeExt | TIME | IN | 伸出行程时间（Extend stroke time），默认 T#1S，纯时间模式据此判定到位 |
| tStrokeTimeRet | TIME | IN | 弹簧缩回行程时间（Spring return stroke time），默认 T#1S |
| tTimeoutExt | TIME | IN | 伸出到位超时（Extend timeout），默认 T#3S，0=禁用自检 |
| tDebounce | TIME | IN | 磁开防抖窗口（Sensor debounce），默认 T#20MS，0=直通 |
| bReset | BOOL | IN | 上升沿复位故障 |
| bSolenoidExt | BOOL | OUT | 伸出线圈输出（Extend solenoid coil），单线圈：得电伸出 / 失电弹簧缩回 |
| eState / bExtended / bRetracted / bFault / uErrorId | — | OUT | I_DL_Cylinder 属性映射（R22：以 PROPERTY GET 承载） |
| bMoving | BOOL | OUT | 运动中指示（Moving indicator） |
| uCycleCount | UDINT | OUT | 行程计数（Stroke count），缩回判定沿 +1 |

设计要点：
- 状态机复用 `E_DL_CylinderState`（既有契约，禁止重定义）；eRetracting 态由「线圈失电 + tStrokeTimeRet 计时」承载（弹簧复位无指令）。
- 纯时间模式（bUseSensorCheck=FALSE）：tStrokeTimeExt 计满 → eExtended；失电后 tStrokeTimeRet 计满 → eRetracted。
- 双重校验模式：计时到位后若磁开未确认 → 持续 bMoving；磁开在 tTimeoutExt 内到 → eExtended；超时 → 故障锁存。
- 单线圈无双线圈互斥问题，但出口断言：eFault/eIdle 稳态线圈必断。
- 故障集（锁存，仅 bReset 清）：`0003_0220` 伸出到位超时【故障级】、`0003_0221` 反馈校验失败（时间到位但磁开超窗未确认）【故障级】、`0003_0222` 非法状态兜底【故障级】（CASE ELSE → eFault）。
- 验收向量：V1 纯时间正常链（伸出→eExtended→失电→tStrokeTimeRet→eRetracted）；V2 双重校验磁开迟到/超时故障；V3 中途撤联锁保位；V4 非法状态兜底；V5 复位清除。

### 1.2 `I_DL_VacuumGenerator`（接口）｜DL_Device｜来源标签 `lbp-device`

功能：真空发生器（负压吸盘供气）标准抽象。DL_Process 拾放工站（PickAndPlaceStation / CellFeederVacuum）依赖注入件。

- 状态枚举（随接口同文件）`E_DL_VacuumState`：eIdle(0)/eEvacuating(10)/eVacuumOk(20)/eBlowing(30)/eFault(99)，编号步长 10、双语注释、eFault 末位。
- 属性（PROPERTY GET）：`eState`、`bVacuumOk : BOOL`（真空建立确认 Vacuum established）、`fPressure : REAL`（负压反馈值 [kPa]，0=大气压，负值=真空度）、`bFault : BOOL`、`uErrorId : UDINT`（段位 16#0003_xxxx）。
- 方法（4 个，≤6）：`CmdEvacuate() : BOOL`（建立真空指令，故障态拒绝返回 FALSE）；`CmdBlowOff() : BOOL`（破真空吹气指令，单发）；`CmdStop() : BOOL`（双阀全断保持现状）；`CmdReset() : BOOL`（复位故障）。
- 边界防错：方法在 eFault 态一律拒绝并返回 FALSE；接口层不做任何过程映像读写。

### 1.3 `FB_DL_VacuumEjector`（功能块，实现 I_DL_VacuumGenerator）｜DL_Device｜来源标签 `lbp-device`

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bCmdEvacuate | BOOL | IN | 建立真空指令（Evacuate command），上升沿生效 |
| bCmdBlowOff | BOOL | IN | 破真空吹气指令（Blow-off command），上升沿生效，输出 tBlowPulse 定宽脉冲 |
| fPressureFeedback | REAL | IN | 负压表反馈（Pressure feedback）[kPa]，0=大气，负值=真空度；非有限值防御 |
| bFbVacuumSwitch | BOOL | IN | 可选真空开关反馈（Optional vacuum switch feedback），TRUE=真空确认 |
| bUseSensorCheck | BOOL | IN | 开关反馈校验使能（Sensor check enable），TRUE=负压阈值+开关双确认 |
| fVacuumSetpoint | REAL | IN | 真空建立阈值（Vacuum setpoint）[kPa]，默认 -60.0（负压域） |
| fVacuumHysteresis | REAL | IN | 真空判定迟滞（Vacuum hysteresis）[kPa]，默认 5.0，防临界抖动 |
| tEstablishTimeout | TIME | IN | 真空建立超时（Establish timeout），默认 T#5S，0=禁用 |
| tBlowPulse | TIME | IN | 破真空吹气脉冲宽度（Blow-off pulse width），默认 T#500MS |
| tDebounce | TIME | IN | 开关反馈防抖（Switch debounce），默认 T#20MS |
| bReset | BOOL | IN | 上升沿复位故障 |
| bVacuumValve | BOOL | OUT | 真空电磁阀输出（Vacuum solenoid valve） |
| bBlowValve | BOOL | OUT | 破真空吹气阀输出（Blow-off solenoid valve） |
| eState / bVacuumOk / fPressure / bFault / uErrorId | — | OUT | 接口属性映射（R22） |
| bHolding | BOOL | OUT | 吸附保持中指示（Holding indicator），eVacuumOk 态为 TRUE |

设计要点：
- 状态机 `E_DL_VacuumState` + CASE + ELSE（ELSE → eFault，`0003_0232`）。
- 真空判定用迟滞：建立判据 `fPressureFeedback <= fVacuumSetpoint`；保持判据放宽 `fVacuumSetpoint + fVacuumHysteresis`；复用 `FC_DL_Hysteresis` 语义（clean-room 内联实现，阈值方向为负压域，注明）。
- 吹气脉冲：bCmdBlowOff 上升沿 → bBlowValve 置位 tBlowPulse 定宽后自动复位（TP 语义自实现，TON 不适用定宽脉冲——用内部时间戳累积法，注明断输入一拍规则 R14 不涉及）；吹气期间强制 bVacuumValve 断、bVacuumOk 清。
- 双确认模式（bUseSensorCheck=TRUE）：负压阈值达成 **且** 开关反馈确认 → eVacuumOk；阈值达成但开关 tEstablishTimeout 内未到 → `0003_0231` 反馈校验失败【故障级】。
- 负压表有效性：fPressureFeedback 非有限值 → 保持末次有效值 + `0003_0230`【信息级→改列故障级：传感器失效属故障级 `0003_0230`】，规格裁定为故障级（吸附安全相关）。
- 故障集：`0003_0230` 负压反馈信号无效【故障级】、`0003_0231` 真空建立超时/反馈校验失败【故障级】、`0003_0232` 非法状态【故障级】。
- 验收向量：V1 正常建立链；V2 建立超时故障；V3 吹气脉冲定宽单发；V4 双确认不一致故障；V5 非有限值注入保持末值。

### 1.4 `FB_DL_StarDeltaMotor`（功能块）｜DL_Device｜来源标签 `lbp-basic-process / lbp-device`

功能：星三角降压启动电机控制（三接触器）。星角切换安全死区时间互锁、三路接触器反馈校验、热继过载锁存、防频繁启动（复用 FB_DL_DolMotor 已确立的启动抑制参数范式）。**事件型，免首扫（R23）**。状态枚举复用 `E_DL_MotorState`（既有 I_DL_MotorDriver 契约，禁止重定义）。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bCmdStart | BOOL | IN | 启动指令（Start command），上升沿生效 |
| bCmdStop | BOOL | IN | 停止指令（Stop command），电平生效 |
| bFbMain | BOOL | IN | 主接触器反馈（Main contactor feedback），TRUE=吸合 |
| bFbStar | BOOL | IN | 星形接触器反馈（Star contactor feedback），TRUE=吸合 |
| bFbDelta | BOOL | IN | 三角形接触器反馈（Delta contactor feedback），TRUE=吸合 |
| bThermalOverload | BOOL | IN | 热继电器过载信号（Thermal overload trip），TRUE=过载 |
| bPermitStart | BOOL | IN | 启动允许联锁（Start permit），TRUE=允许 |
| tStarTime | TIME | IN | 星形运行时间（Star run time），默认 T#5S，按负载实测加速时间整定 |
| tDeadTime | TIME | IN | 星角转换死区时间（Transition dead time），默认 T#100MS，域 50~200MS，星接触器分断后角接触器方可吸合 |
| tFbWindow | TIME | IN | 指令-反馈校验窗口（Feedback check window），默认 T#500MS |
| tRestartInhibit | TIME | IN | 重启抑制冷却时间（Restart inhibit），默认 T#60S |
| bReset | BOOL | IN | 上升沿复位故障 |
| bMainContactor | BOOL | OUT | 主接触器线圈输出（Main contactor coil） |
| bStarContactor | BOOL | OUT | 星形接触器线圈输出（Star contactor coil） |
| bDeltaContactor | BOOL | OUT | 三角形接触器线圈输出（Delta contactor coil） |
| eState / bRunning / bFault / uErrorId / bRestartInhibit | — | OUT | E_DL_MotorState 属性映射（R22）；bRunning=角接触器吸合确认 |
| bStarPhase | BOOL | OUT | 星形阶段指示（Star phase active），调试/HMI 用 |
| uStartCount | UDINT | OUT | 累计启动次数（Start count） |

设计要点：
- 序列：eIdle →（启动沿）eStarting：bMain+bStar 吸合（星形降压，起动力矩约 1/3）→ tStarTime 到 → **星线圈断 + tDeadTime 死区计时**（星角互斥硬约束：此窗口内角线圈严禁输出）→ 死区满 → bDelta 吸合 → eRunning。
- **出口互斥断言（硬约束）**：`bStarContactor AND bDeltaContactor` 恒不可同真——CASE 内仅单态置一端，主体末尾断言对：同真时双线圈全断 + 故障锁存 `0003_0243`。
- 反馈校验：主/星/角接触器指令后 tFbWindow 内未吸合 → 各自拒动码 `0003_0240/0241/0242`【故障级】；运行中反馈意外断开 → 失反馈脱扣 `0003_0244`【故障级】。
- 过载锁存 `0003_0245`（仅 bReset 清）；重启抑制（tRestartInhibit 内再启动拒绝）沿用 FB_DL_DolMotor 口径 → 信息级 `0003_0102`【信息级】。
- 转换失败：死区满后 tFbWindow 内角接触器未吸合 → `0003_0246` 星角转换失败【故障级】。
- 验收向量：V1 正常星→角全链（含死区时序逐拍推演）；V2 星角反馈互锁冲突（强制同真注入）；V3 主接触器拒动；V4 转换失败；V5 过载锁存+复位；V6 重启抑制拒绝。

### 1.5 `I_DL_VfdDrive`（接口）｜DL_Device｜来源标签 `lbp-basic-process / lbp-device`

功能：通用变频器抽象接口（端子型/通信型均可适配）。风机泵类与输送线驱动底座。

- 状态枚举（随接口同文件）`E_DL_VfdState`：eDisabled(0)/eReady(10)/eRunningFwd(20)/eRunningRev(30)/eJogging(40)/eFault(99)。
- 属性（PROPERTY GET）：`eState`、`fFreqSetpoint : REAL`（频率设定 [Hz]）、`fFreqActual : REAL`（频率反馈 [Hz]）、`bRunning : BOOL`、`bFault : BOOL`、`uErrorId : UDINT`。
- 方法（6 个，达红线临界）：`CmdRun(bFwd : BOOL) : BOOL`（正/反转运行指令，电平语义）；`CmdStop() : BOOL`；`CmdJog(bFwd : BOOL) : BOOL`（点动指令，优先级高于运行）；`SetFrequency(fHz : REAL) : BOOL`（频率设定，返回合法性）；`SelectPresetSpeed(nIdx : USINT) : BOOL`（多段速选择，0=模拟量给定、1..7=段速）；`CmdReset() : BOOL`。
- 边界防错：故障态运行/点动/设定方法一律拒绝返回 FALSE；Reset 返回是否受理。

### 1.6 `FB_DL_VfdGeneric`（功能块，实现 I_DL_VfdDrive）｜DL_Device｜来源标签 `lbp-basic-process / lbp-device`

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bDriveEnable | BOOL | IN | 驱动使能/上电（Drive enable），FALSE → eDisabled 态全部输出切断 |
| bCmdRunFwd | BOOL | IN | 正转运行指令（Run forward command），电平生效 |
| bCmdRunRev | BOOL | IN | 反转运行指令（Run reverse command），电平生效；与正转同拍为真 → 冲突安全侧停止 |
| bCmdJogFwd | BOOL | IN | 正向点动指令（Jog forward command），电平生效，优先级高于运行指令 |
| bFbRunning | BOOL | IN | 运行反馈（Running feedback），TRUE=驱动输出运行中 |
| bFbFault | BOOL | IN | 驱动故障反馈（Drive fault feedback），TRUE=故障 |
| bFbAtSpeed | BOOL | IN | 频率到达反馈（At-speed feedback），TRUE=输出频率到达设定 ±容差 |
| fFreqCmd | REAL | IN | 频率设定（Frequency command）[Hz]，0..fFreqMax，越界钳位信息级 |
| fFreqActual | REAL | IN | 频率反馈（Frequency feedback）[Hz]，非有限值防御 |
| aPresetFreq | ARRAY[1..7] OF REAL | IN | 多段速频率表（Preset speed table）[Hz]，段速值由现场整定注入 |
| nPresetSel | USINT | IN | 段速选择（Preset speed select），0=模拟量给定、1..7=段速，越界按 0 处理并置码 |
| fFreqMax | REAL | IN | 频率上限（Max frequency）[Hz]，默认 50.0 |
| tFbWindow | TIME | IN | 指令-反馈校验窗口（Feedback check window），默认 T#1S |
| tFaultResetPulse | TIME | IN | 故障复位脉冲宽度（Fault reset pulse），默认 T#500MS |
| bReset | BOOL | IN | 上升沿复位故障 |
| bRunFwdOut | BOOL | OUT | 正转端子输出（Run forward terminal） |
| bRunRevOut | BOOL | OUT | 反转端子输出（Run reverse terminal） |
| bJogOut | BOOL | OUT | 点动端子输出（Jog terminal） |
| bFaultResetOut | BOOL | OUT | 故障复位端子输出（Fault reset terminal），tFaultResetPulse 定宽单发 |
| fFreqRefPercent | REAL | OUT | 频率给定模拟量输出（Frequency reference analog out）[%]，0~100 线性映射 fFreqMax |
| uPresetCode | USINT | OUT | 段速选择码输出（Preset speed code），映射 DI 多段速端子组合 0..7 |
| eState / fFreqSetpoint / fFreqActual / bRunning / bFault / uErrorId | — | OUT | 接口属性映射（R22） |

设计要点：
- 状态机 `E_DL_VfdState` + CASE + ELSE（ELSE → eFault）。正/反转端子互斥硬约束（同 LBP 电机族范式，出口断言对，冲突 → 停止 + 信息级 `0003_0103`）。
- 点动优先：bCmdJogFwd 电平为真时覆盖运行指令（bRunFwdOut 断、bJogOut 通）；点动频率取 aPresetFreq[1]（注释声明，段速 1 兼作点动频率域）。
- 多段速：nPresetSel>0 时 fFreqSetpoint := aPresetFreq[nPresetSel]，uPresetCode := nPresetSel；=0 时取 fFreqCmd 并输出 fFreqRefPercent 模拟量域。
- 故障映射：bFbFault → eFault 锁存 + `0003_0250` 驱动故障【故障级】；复位经 bFaultResetOut 定宽脉冲重试恢复。
- 启动反馈校验：运行指令后 tFbWindow 内 bFbRunning 未到 → `0003_0251` 启动反馈超时【故障级】。
- 故障集：`0003_0250` 驱动故障【故障级】、`0003_0251` 启动反馈超时【故障级】、`0003_0252` 非法状态【故障级】；信息级：`0003_0103` 正反转指令冲突、`0003_0104` 频率设定钳位/段速选择越界。
- 验收向量：V1 模拟量给定正转链；V2 段速切换；V3 点动覆盖；V4 正反转同拍冲突；V5 驱动故障锁存+复位脉冲；V6 频率越界钳位。

### 1.7 `I_DL_ProportionalValve`（接口）｜DL_Device｜来源标签 `lbp-basic-process / lbp-device`

功能：模拟量比例阀/调节阀抽象（开度指令-反馈型）。

- 状态枚举（随接口同文件）`E_DL_ValveState`：eIdle(0)/eModulating(10)/eFault(99)。
- 属性（PROPERTY GET）：`eState`、`fPosCmd : REAL`（当前阀位指令 [%]）、`fPosFeedback : REAL`（阀位反馈 [%]）、`bDeviationAlarm : BOOL`（偏差报警激活中 Deviation alarm）、`bFault : BOOL`、`uErrorId : UDINT`。
- 方法（3 个）：`SetPosition(fPos : REAL) : BOOL`（阀位指令设定 [%]，返回合法性）；`CmdStop() : BOOL`（指令保持当前值冻结输出）；`CmdReset() : BOOL`。

### 1.8 `FB_DL_AnalogValve`（功能块，实现 I_DL_ProportionalValve）｜DL_Device｜来源标签 `lbp-basic-process / lbp-device`

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| fPosSetpoint | REAL | IN | 阀位设定（Position setpoint）[%]，0..100，越界钳位信息级 |
| fPosFeedback | REAL | IN | 阀位反馈（Position feedback）[%]，0..100，来自阀位变送器；非有限值防御 |
| fZeroDeadband | REAL | IN | 零点死区补偿（Zero deadband compensation）[%]，默认 0.5，输出小于此值钳为 0 防阀芯微抖 |
| fDeviationLimit | REAL | IN | 偏差报警门限（Deviation limit）[%]，默认 5.0 |
| tDeviationDelay | TIME | IN | 偏差报警确认延时（Deviation delay），默认 T#10S，防动态调节过程误报 |
| fOutMin / fOutMax | REAL | IN | 输出限幅域（Output span endpoints）[%]，默认 0.0/100.0；对调自修复（0.6） |
| bEnable | BOOL | IN | 调节使能（Modulating enable），FALSE 时输出冻结保持 |
| bReset | BOOL | IN | 上升沿复位故障 |
| fPosOutput | REAL | OUT | 阀位指令输出（Position output）[%]，死区补偿+限幅后，量纲=限幅域（R20） |
| bDeviationAlarm / eState / fPosCmd / fPosFeedback / bFault / uErrorId | — | OUT | 接口属性映射（R22） |

设计要点：
- 透传+补偿链：设定钳位 [0,100] → 死区补偿（|fPosSetpoint| < fZeroDeadband → 0）→ 限幅域映射 → fPosOutput；本块**不含闭环**（阀位闭环由驱动器/上层 PID 完成，本块为指令整形与诊断层，职责单一）。
- 偏差报警：|fPosSetpoint − fPosFeedback| > fDeviationLimit 持续 tDeviationDelay → bDeviationAlarm 置位（信息级 `0003_0105`，不锁存，每拍重算 R15 瞬时型）；恢复自动清。
- 非有限值反馈：保持末次有效值 + `0003_0260`【故障级】锁存（阀位反馈失效属安全相关）。
- 故障集：`0003_0260` 阀位反馈信号无效【故障级】、`0003_0261` 非法状态【故障级】；信息级：`0003_0105` 设定值钳位、`0003_0106` 输出限幅域对调自修复。
- 验收向量：V1 透传+死区补偿；V2 偏差报警延时触发/恢复；V3 非有限值锁存；V4 限幅域对调；V5 使能撤除冻结。

### 1.9 `I_DL_MotorizedValve`（接口）｜DL_Device｜来源标签 `lbp-basic-process / lbp-device`

功能：电动调节阀（开/关脉冲输出、无阀位变送器）抽象。

- 状态枚举（随接口同文件）`E_DL_MotorValveState`：eIdle(0)/eOpening(10)/eClosing(20)/eOpened(30)/eClosed(40)/eFault(99)。
- 属性（PROPERTY GET）：`eState`、`fPosEstimate : REAL`（估算开度 [‰→%]，**[%]**，0~100，由行程时间积分自动估算）、`bLimOpen : BOOL`（全开限位反馈）、`bLimClosed : BOOL`（全关限位反馈）、`bFault : BOOL`、`uErrorId : UDINT`。
- 方法（4 个）：`CmdOpen() : BOOL`（开阀指令，电平语义受理）；`CmdClose() : BOOL`（关阀指令）；`CmdStop() : BOOL`（双脉冲全断保持）；`CmdReset() : BOOL`。
- 边界防错：故障态拒绝；已在端点（限位确认）的指令受理但由实现块拒绝执行并置信息级。

### 1.10 `FB_DL_ThreePointValve`（功能块，实现 I_DL_MotorizedValve）｜DL_Device｜来源标签 `lbp-basic-process / lbp-device`

功能：三点浮点式电动调节阀控制器。开/关双脉冲输出；**自动积分估算当前开度百分比**；全开/全关限位保护；行程时间参数注入。**事件型 + 连续估算混合**：开度估算为连续量 → 设 bInit 首扫（fPosEstimate 初值取限位状态推断）。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bCmdOpen | BOOL | IN | 开阀指令（Open command），电平生效 |
| bCmdClose | BOOL | IN | 关阀指令（Close command），电平生效；与开同拍为真 → 停止 + 信息级 |
| bLimOpen | BOOL | IN | 全开限位开关（Open limit switch），TRUE=已到全开端点 |
| bLimClosed | BOOL | IN | 全关限位开关（Closed limit switch），TRUE=已到全关端点 |
| tStrokeOpen | TIME | IN | 全行程开启时间（Full open stroke time），默认 T#60S，现场实测注入 |
| tStrokeClose | TIME | IN | 全行程关闭时间（Full close stroke time），默认 T#60S |
| fEstimateTol | REAL | IN | 估算-限位一致性容差（Estimate-tolerance）[%]，默认 10.0 |
| bEnable | BOOL | IN | 允许动作联锁（Motion interlock），TRUE=允许发脉冲 |
| bReset | BOOL | IN | 上升沿复位故障 |
| bOpenPulse | BOOL | OUT | 开阀脉冲输出（Open pulse output） |
| bClosePulse | BOOL | OUT | 关阀脉冲输出（Close pulse output） |
| fPosEstimate | REAL | OUT | 估算开度（Estimated position）[%]，0~100，行程时间积分（R20：量纲 [%]） |
| bOpened / bClosed | BOOL | OUT | 全开/全关确认（Fully opened/closed），限位优先 |
| eState / bLimOpen / bLimClosed / bFault / uErrorId | — | OUT | 接口属性映射（R22） |
| uTravelCount | UDINT | OUT | 全行程计数（Travel count），全关确认沿 +1 |

设计要点：
- 开度积分：bOpenPulse 期间每拍 `fPosEstimate += 100.0 × fDt / tStrokeOpen 秒值`（fDt 由 TIME 折算，与 tSampleTime 显式化不同——本块直接用行程时间折算每拍增量，注明换算式与量纲推导）；关向对称；估算值钳位 [0,100]。
- **端点限位保护（双保险）**：① 限位开关为真 → 立即停脉冲并将估算值锚定（bLimOpen → 100.0，bLimClosed → 0.0）；② 无限位开关场景下估算到 0/100 端点后拒绝继续发脉冲 + 信息级 `0003_0107` 端点指令拒绝。
- 首扫初始化（R19 范式）：首扫或 bTrack 时按限位状态推断初值（bLimOpen→100 / bLimClosed→0 / 无限位→50 中位兜底），提供 bTrack : BOOL 输入供上层强制重同步。
- 一致性监视：估算值与限位矛盾超 fEstimateTol（如估算 >10% 但 bLimClosed 持续为真）→ `0003_0270` 行程估算失准【故障级】锁存（行程时间整定错误或限位故障）。
- 限位开关物理互斥：bLimOpen AND bLimClosed 同真 → 物理不可能 → `0003_0271`【故障级】。
- 双向同拍 → 双脉冲断 + 信息级 `0003_0108`；bOpenPulse 与 bClosePulse 出口互斥断言。
- 故障集：`0003_0270` 行程估算失准【故障级】、`0003_0271` 双限位冲突【故障级】、`0003_0272` 非法状态【故障级】；信息级：`0003_0107` 端点拒绝、`0003_0108` 双向指令冲突。
- 验收向量：V1 开度积分跟踪（开 50% 行程 → 估算 ≈50）；V2 限位锚定与端点拒绝；V3 估算失准故障；V4 双向冲突；V5 中途插入 bTrack 重同步（R19 必测）；V6 行程计数。

---

## 第 2 节 泳道 B｜DL_Motion 回零/运动族（3 项，T1-6 PLCopen + T2-4 双源，标签 `plcopen-motion` / `s7-motion`）

### 2.11 `FB_DL_AxisHomingSeq`（功能块）｜DL_Motion｜来源标签 `plcopen-motion / s7-motion`

功能：标准工业回零序列状态机。经 I_DL_MotionAxis 接口驱动轴体（MoveVelocity/MoveRelative/Stop 组合出序列），复用既有契约。慢速逼近-回退-再逼近-标定原点时序（S-2 提取点②公开语义 clean-room）。**被动回零（外力移动轴监听参考事件）本轮不实现**，留矩阵扩产并在头注释声明。**含连续量行程监视 → 设 bInit 首扫**。

枚举（随块同文件，头注释注明归属）：

- `E_DL_HomingMode`：eLimitSwitch(1) 限位开关回零 / eHomeSwitch(2) 原点开关回零 / eZeroPulse(3) Z 相脉冲精定位 / eTorqueBlock(4) 扭矩堵转回零——**不用任何厂商模式数值**（S-2 提取点④：模式是组合矩阵非魔法数，本库仅取四种高频模式，其余留扩产）。
- `E_DL_HomingStep`：eIdle(0)/eApproach(10) 快速逼近/eRetreat(20) 反向回退/eReapproach(30) 爬行再逼近/eCalibrate(40) 标定原点/eStopping(50) 受控停车/eDone(60)/eAborted(70)/eFault(99)。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| iAxis | I_DL_MotionAxis | IN_OUT | 轴接口引用（Axis reference） |
| eMode | E_DL_HomingMode | IN | 回零模式（Homing mode），见 E_DL_HomingMode |
| bCmdStart | BOOL | IN | 回零启动（Homing start），上升沿生效 |
| bCmdAbort | BOOL | IN | 回零中止（Homing abort），电平生效，触发受控停车 |
| fHomingVel | REAL | IN | 快速逼近速度（Homing approach velocity）[mm/s]，默认 50.0 |
| fCreepVel | REAL | IN | 爬行再逼近速度（Creep velocity）[mm/s]，默认 2.0 |
| fAcc | REAL | IN | 回零加减速（Homing acceleration）[mm/s²] |
| fHomePosition | REAL | IN | 标定原点位置值（Home position value）[mm]，标定成功后写入轴坐标系 |
| tHomingTimeout | TIME | IN | 回零总超时（Homing timeout），默认 T#60S，0=禁用 |
| bLimPos / bLimNeg | BOOL | IN | 正/负限位开关（Positive/negative limit switch） |
| bHomeSw | BOOL | IN | 原点开关（Home switch） |
| bZeroPulse | BOOL | IN | Z 相脉冲（Encoder zero pulse），捕获上升沿 |
| bTorqueLimitReached | BOOL | IN | 堵转阈值到达信号（Torque limit reached），由驱动层注入（接口无扭矩域，外部注入声明 R11 留档） |
| bTrack | BOOL | IN | 跟踪重同步（Track resync），TRUE 时中止序列回 eIdle（R19） |
| bBusy | BOOL | OUT | 回零进行中（Homing busy） |
| bDone | BOOL | OUT | 回零完成（Homing done），eDone 态保持 |
| eStep | E_DL_HomingStep | OUT | 当前序列步（Current homing step），HMI 显示用 |
| uErrorId | UDINT | OUT | 事件码，段位 16#0004_xxxx |

设计要点：
- 四模式时序（全部经 iAxis 方法，绝不出任何自有速度输出）：
  - eLimitSwitch：朝近端限位方向 fHomingVel 逼近 → 限位上升沿 → 反向 fHomingVel 回退脱离 → 限位下降沿确认脱离 → 反向 fCreepVel 爬行再逼近 → 限位上升沿 → eCalibrate（iAxis.Stop() + 标定）→ eDone。
  - eHomeSwitch：fHomingVel 逼近 → bHomeSw 上升沿 → 减速停 → fCreepVel 反向脱离 → 下降沿 → fCreepVel 正向再逼近 → 上升沿 → 标定 → eDone。
  - eZeroPulse：fCreepVel 单向运行 → bZeroPulse 上升沿 → 停止 + 标定 → eDone。
  - eTorqueBlock：fCreepVel 朝堵转方向 → bTorqueLimitReached → 停止 + 标定 → eDone。
- 启动门禁：iAxis 不在 eStandstill → 拒绝启动（信息级 `0004_0106`）；所选模式必需信号（如 eZeroPulse 需 bZeroPulse 通道有效——以「启动时原点开关已压住」等可观测矛盾检测，信号缺失类不可观测项写头注释声明由调用方保证）。
- 双护栏（S-2 提取点⑤）：tHomingTimeout 总超时 `0004_0210`【故障级】；行程超限——启动时记录 iAxis.fPosition，任何时刻 |当前位置−起点| > fMaxTravel（新增引脚，默认 1.0E6 [mm]）→ `0004_0211` 行程超限【故障级】。
- 中止/轴故障：bCmdAbort 或 iAxis.bError → 受控 iAxis.Stop() → eAborted/eFault，码 `0004_0212`【故障级】。
- bDone 供调用方驱动坐标系建立（轴接口 bHomed 由实现块/上层联动，本块不直接写轴内部态，头注释声明）。
- 验收向量：V1 原点开关回零全链（逼近-回退-再逼近逐拍推演）；V2 Z 相精定位；V3 堵转回零；V4 超时故障；V5 行程超限；V6 启动门禁拒绝；V7 运行中途 bTrack 中止重同步（R19 必测）。

### 2.12 `FB_DL_AxisRelativeMove`（功能块）｜DL_Motion｜来源标签 `plcopen-motion / s7-motion`

功能：单轴相对定位（MC_MoveRelative 语义）与连续累加步进控制封装。**事件型 + 轮询状态，免首扫（R23）**。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| iAxis | I_DL_MotionAxis | IN_OUT | 轴接口引用（Axis reference） |
| bCmdExecute | BOOL | IN | 执行指令（Execute command），上升沿生效 |
| fDistance | REAL | IN | 相对位移（Relative distance）[mm]，带符号，负值=负向 |
| fVel | REAL | IN | 运行速度（Run velocity）[mm/s]，正值 |
| fAcc | REAL | IN | 加减速度（Acceleration）[mm/s²]，正值 |
| bChainMode | BOOL | IN | 链式步进模式（Chain mode），TRUE=到位后自动连续执行下一步 |
| nChainTarget | UDINT | IN | 链式目标步数（Chain target steps），0=单步（与 bChainMode=TRUE 组合时视为 1）；链式运行中由上层递增目标实现累加 |
| bAbort | BOOL | IN | 中止（Abort），电平生效 → iAxis.Stop() |
| bBusy | BOOL | OUT | 定位进行中（Move busy） |
| bDone | BOOL | OUT | 单步完成（Step done），每步完成置位保持至下一步启动 |
| bChainDone | BOOL | OUT | 链式目标完成（Chain target reached） |
| uStepsDone | UDINT | OUT | 累计完成步数（Steps done） |
| uErrorId | UDINT | OUT | 事件码 16#0004_xxxx |

设计要点：
- 单步流：上升沿 → 门禁检查（iAxis ∈ {eStandstill, eDiscreteMotion 拒绝新指令——本块仅在 eStandstill 发起}）→ iAxis.MoveRelative(fDist,fVel,fAcc) → 轮询 iAxis.eState 回 eStandstill → bDone + uStepsDone+1。
- 链式：bChainMode 且 uStepsDone < nChainTarget → bDone 后下一拍自动再发 MoveRelative（步间距即 fDistance，连续累加步进语义）；nChainTarget 递增即实现无上限累加。
- 指令被轴拒绝（返回 FALSE）→ `0004_0220`【故障级】锁存；bAbort 或 iAxis.bError → `0004_0221`【故障级】；fVel/fAcc 非正值/非有限值 → 拒绝启动 + 信息级 `0004_0106`（与 2.11 同码同义：参数门禁拒绝，头注释注明共用）。
- 验收向量：V1 单步往返链；V2 链式 3 步累计；V3 目标递增累加步进；V4 指令被拒；V5 中止；V6 状态门禁。

### 2.13 `FB_DL_AxisVelocityMove`（功能块）｜DL_Motion｜来源标签 `plcopen-motion / s7-motion`

功能：单轴速度模式（MC_MoveVelocity 语义）与动态变速控制封装。**事件型 + 轮询状态，免首扫（R23）**。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| iAxis | I_DL_MotionAxis | IN_OUT | 轴接口引用（Axis reference） |
| bCmdStart | BOOL | IN | 速度运行指令（Velocity start command），电平生效：TRUE=运行 / FALSE=受控停止 |
| fVelocity | REAL | IN | 目标速度（Target velocity）[mm/s]，带符号，负值=负向；运行中变更即为改速请求 |
| fAcc | REAL | IN | 加减速度（Acceleration）[mm/s²]，正值 |
| bDynamicRetarget | BOOL | IN | 动态改速使能（Dynamic retarget），TRUE=连续运动中 fVelocity 变化时自动调用改速（MC_MoveVelocity 改速语义） |
| fVelMax | REAL | IN | 速度上限（Velocity limit）[mm/s]，默认 1000.0，|fVelocity| 超限钳位信息级 |
| bBusy | BOOL | OUT | 速度模式激活（Velocity mode active） |
| bActive | BOOL | OUT | 轴处于 eContinuousMotion（Axis in continuous motion） |
| uErrorId | UDINT | OUT | 事件码 16#0004_xxxx |

设计要点：
- bCmdStart 上升沿 → 门禁（eStandstill 受理 / eContinuousMotion 改速受理）→ iAxis.MoveVelocity(fVel,fAcc)。
- 动态改速：bDynamicRetarget 且 iAxis.eState=eContinuousMotion 且 fVelocity 与上次已发值差超容差 → 重新调用 MoveVelocity（改速而非重启，接口契约 §方法语义）；改速请求在非受理态被拒 → 信息级 `0004_0107`。
- bCmdStart 下降沿 → iAxis.Stop()（受控减速停车）。
- 指令被拒/轴故障中断 → `0004_0230`【故障级】；参数门禁（非有限值、fAcc≤0）→ 信息级 `0004_0106`。
- 验收向量：V1 启动-停止链；V2 运行中改速（正向→反向无重启）；V3 改速被拒（非受理态）；V4 速度钳位；V5 轴故障中断。

---

## 第 3 节 泳道 C｜DL_Process 行业池 9.5 节 P0 两件（标签 `oscat-building / lgf-datetime / hvac`）+ DL_Algo 1 项（标签 `lgf-technology`）

### 3.14 `FB_DL_EnthalpyCompareCtrl`（功能块）｜DL_Process｜来源标签 `oscat-building / hvac`

功能：焓差比较控制执行块（行业池 9.5 节 P0 链路闭环示范）。新风/回风温湿度 → 直接调用 `FC_DL_HumidAirEnthalpy` 计算双侧焓值 → 差分焓值判据（含切换死区/迟滞）→ 新风阀位指令输出；含最小新风位硬限制（S-3 提取点③卫生通风底线）。**连续量 → 设 bInit 首扫**（首扫输出 fMinOaPos 安全值）。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| fOaTempC | REAL | IN | 新风干球温度（Outdoor air dry-bulb temp）[°C]，有效域 -30..60 |
| fOaRelHum | REAL | IN | 新风相对湿度（Outdoor air relative humidity）[%]，1..100 |
| fRaTempC | REAL | IN | 回风干球温度（Return air dry-bulb temp）[°C] |
| fRaRelHum | REAL | IN | 回风相对湿度（Return air relative humidity）[%] |
| fAtmPress | REAL | IN | 大气压（Atmospheric pressure）[kPa]，默认 101.325，透传给焓值 FC |
| fEnthalpyDeadband | REAL | IN | 焓差切换死区（Enthalpy changeover deadband）[kJ/kg]，默认 2.0，施密特迟滞半宽 |
| fMinOaPos | REAL | IN | 最小新风阀位（Minimum outdoor air damper position）[%]，默认 30.0，卫生通风硬下限 |
| fFreeCoolOaPos | REAL | IN | 经济器全开阀位（Free-cooling damper position）[%]，默认 100.0 |
| fEnthalpyHighLimit | REAL | IN | 新风焓值高限停机门限（Enthalpy high-limit trip）[kJ/kg]，默认 0=禁用（S-3 提取点④ ASHRAE 90.1 高限语义） |
| bEnableCooling | BOOL | IN | 供冷需求使能（Cooling demand enable），FALSE 时阀位恒回 fMinOaPos |
| bReset | BOOL | IN | 上升沿复位故障 |
| bTrack | BOOL | IN | 跟踪重同步（Track resync），TRUE 时输出回 fMinOaPos 并重建迟滞态（R19 必测） |
| fOaEnthalpy | REAL | OUT | 新风比焓（Outdoor air enthalpy）[kJ/kg 干空气]，供 HMI/诊断 |
| fRaEnthalpy | REAL | OUT | 回风比焓（Return air enthalpy）[kJ/kg 干空气] |
| bEconomizerActive | BOOL | OUT | 经济器激活（Economizer active），差分焓值判据通过且迟滞态为开 |
| fOaDamperCmd | REAL | OUT | 新风阀位指令（Outdoor air damper command）[%]，量纲=阀位域（R20），下限恒 ≥ fMinOaPos |
| bHighLimitTrip | BOOL | OUT | 焓值高限停机（Enthalpy high-limit trip），激活中 |
| uErrorId | UDINT | OUT | 事件码，段位 16#0005_xxxx |

设计要点：
- 每拍两次 FC_DL_HumidAirEnthalpy 调用（Oa/Ra 各一），uErrorId 取并集。
- 差分焓值判据（S-3 提取点①③）：开侧 `fOaEnthalpy < fRaEnthalpy − fEnthalpyDeadband`、关侧 `fOaEnthalpy > fRaEnthalpy + fEnthalpyDeadband`（施密特迟滞防临界抖动，S-3 提取点⑥传感器漂移防线）。
- 阀位指令：`bEconomizerActive AND bEnableCooling AND NOT bHighLimitTrip` → fFreeCoolOaPos，否则 fMinOaPos；恒有 `fOaDamperCmd >= fMinOaPos` 下限钳位（最小新风硬限制）。
- 高限停机：fEnthalpyHighLimit > 0 且 fOaEnthalpy ≥ 高限 → bHighLimitTrip（迟滞回差 fEnthalpyDeadband 防振荡）。
- 输入失效：任一温湿度非有限值/越界 → 输出冻结保持末次有效阀位 + `0005_0201`【故障级】（安全侧：经济器停用，回最小新风位语义在头注释说明——冻结的是输出值，最小新风下限由调用方阀执行层保证，本块输出 fMinOaPos 兜底值）。
- 故障集：`0005_0201` 焓值计算输入失效【故障级】、`0005_0202` 非法状态兜底【故障级】（CASE ELSE）；信息级：`0005_0103` 湿度钳位（FC 返回越界码透传）。
- 验收向量：V1 湿工况干球陷阱复现（Oa 干球低但焓高 → 不开大新风）；V2 迟滞往返（焓差在 ±死区内不抖动）；V3 高限停机；V4 最小新风位硬下限；V5 非有限值冻结保持；V6 中途 bTrack 重同步。

### 3.15 `FB_DL_OccScheduleWindow`（功能块）｜DL_Process｜来源标签 `lgf-datetime / hvac`

功能：多窗作息排程（行业池 9.5 节 P0 链路闭环示范）。内部 **4 实例复用 `FB_DL_TimeWindowCheck`** + `FC_DL_DayOfWeekCalc`（日期→星期），每日窗矩阵 + 节假日覆盖位，输出占用/预启动占位。**事件型+日切换沿，免首扫（R23：无连续量同步语义，窗判定为组合逻辑）**。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| uYear | UINT | IN | 日期注入-年（Injected date year），1980..2099，透传 FC_DL_DayOfWeekCalc |
| uMonth | USINT | IN | 日期注入-月（Injected month）1..12 |
| uDay | USINT | IN | 日期注入-日（Injected day）1..31 |
| uHourNow / uMinNow | USINT | IN | 当前时刻注入（Injected time）[h]/[min]，透传各窗实例（禁读 CPU 钟 0.9） |
| aWinEnable | ARRAY[1..4] OF BOOL | IN | 各窗使能（Window enables），窗 1..4 |
| aHourOn / aMinOn | ARRAY[1..4] OF USINT | IN | 各窗开启时刻（Window on times）[h]/[min] |
| aHourOff / aMinOff | ARRAY[1..4] OF USINT | IN | 各窗关闭时刻（Window off times），支持跨零点 |
| aWeekdayWin | ARRAY[1..4, 1..7] OF BOOL | IN | 各窗星期使能矩阵（Per-window weekday matrix），第二维索引 1=周一（ISO 序） |
| aHolidayOverride | ARRAY[1..4] OF BOOL | IN | 节假日覆盖位（Holiday overrides），TRUE=当日该窗强制关闭 |
| tPreLeadTime | TIME | IN | 预启动提前量（Pre-start lead time），默认 T#30M，占用开始前输出预启动占位 |
| bReset | BOOL | IN | 上升沿清除当拍信息级码 |
| bOccupied | BOOL | OUT | 占用中（Occupied），任一有效窗在窗内 |
| bPreStart | BOOL | OUT | 预启动占位（Pre-start placeholder），占用开始前 tPreLeadTime 内为 TRUE（提前启机预热/预冷用） |
| bPulseOnOccupy | BOOL | OUT | 占用开始沿单发（Occupancy start edge） |
| uActiveWin | USINT | OUT | 当前活动窗号（Active window index），0=无，多窗同开取最小号 |
| uErrorId | UDINT | OUT | 信息级码 16#0005_xxxx |

设计要点：
- 内部 4 个 `FB_DL_TimeWindowCheck` 实例（_fbWin1.._fbWin4）逐拍无条件刷新（R7）；星期由 FC_DL_DayOfWeekCalc(uYear,uMonth,uDay) 计算，越界（eInvalid）→ 全窗按不在窗处理 + 信息级 `0005_0210`。
- 每窗占用 = 窗实例 bInWindow AND aWinEnable[i] AND NOT aHolidayOverride[i] AND 星期矩阵位（星期矩阵经 aWeekdayEnable 单日注入引脚传入窗实例——窗实例的 aWeekdayEnable 由本块按 aWeekdayWin[i, uWeekdayNow] 展开填充）。
- 预启动占位：折算「占用开始时刻 − tPreLeadTime」分钟域判定（跨零点窗同样适用，分钟回绕处理注明推导）；bPreStart = NOT bOccupied AND 距下一窗开始 ≤ 提前量 AND 该窗今日有效。
- bPreStart/bPulseOnOccupy 的时刻折算用 UINT 分钟域防溢出（复用 FB_DL_TimeWindowCheck 的折算口径，声明一致）。
- 故障/信息集：`0005_0210` 日期非法【信息级】、`0005_0211` 窗时刻参数越界【信息级】（各窗实例 0001_0202 码不透传，本块归并为自身码，头注释注明）；本块无故障锁存位。
- 验收向量：V1 单窗占用链（开/闭沿单发）；V2 四窗并行取最小活动号；V3 节假日覆盖强制关闭；V4 预启动提前量（含跨零点窗回绕）；V5 日期越界降级；V6 星期矩阵按日生效。

### 3.16 `FB_DL_RampSoakProfile`（功能块）｜DL_Algo｜来源标签 `lgf-technology`

功能：多段 Ramp/Soak 程序曲线发生器（T2-1 LGF Technology 组曲线族深化）。段数 N 可配（1..16）、每段目标值+斜坡时间+保温时间、段切换沿输出、暂停/跳段/外部保持；作为温控区设定源，烘箱/烧结炉/化成工步共用。**连续量核心件 → tSampleTime 显式（0.5）+ bInit 首扫（R19）**。

枚举（随块同文件，头注释注明归属）`E_DL_RampSoakPhase`：eIdle(0)/eRamp(10)/eSoak(20)/eDone(30)/eFault(99)。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| tSampleTime | TIME | IN | 采样周期（Sample time），默认 T#100MS，<T#10MS 钳位并置码 |
| aTarget | ARRAY[1..16] OF REAL | IN | 各段目标值（Segment targets）[EU]，量纲由调用方工艺定义 |
| aRampTime | ARRAY[1..16] OF TIME | IN | 各段斜坡时间（Segment ramp times），0=从当前值阶跃直达该段目标（信息级） |
| aSoakTime | ARRAY[1..16] OF TIME | IN | 各段保温时间（Segment soak times），0=该段无保温直达下段 |
| nSegCount | USINT | IN | 有效段数（Active segment count）1..16，越界钳位至 1 |
| fStartValue | REAL | IN | 启动基准值（Start value）[EU]，首段斜坡起点 |
| bStart | BOOL | IN | 启动指令（Profile start），上升沿生效 |
| bHold | BOOL | IN | 外部保持（External hold），电平生效：冻结当前值与段内计时（含暂停语义） |
| bSkipSeg | BOOL | IN | 跳段指令（Skip segment），上升沿生效：当前段立即结束进入下段（斜坡起点=当前值） |
| bTrack | BOOL | IN | 跟踪使能（Track enable），TRUE 时 fSetpoint := fTrackValue（运行中途插入向量 R19 必测） |
| fTrackValue | REAL | IN | 跟踪值（Track value）[EU]，温控区实际温度回同步（无扰重启） |
| bLoopProfile | BOOL | IN | 循环运行（Loop profile），TRUE=末段完成后自动从段 1 重启（斜坡起点=当前值） |
| bReset | BOOL | IN | 上升沿复位故障并回 eIdle |
| fSetpoint | REAL | OUT | 程序设定值输出（Profile setpoint）[EU] → 温控区设定源，量纲=EU（R20） |
| nSegAct | USINT | OUT | 当前段号（Active segment）1..nSegCount，0=未启动 |
| ePhase | E_DL_RampSoakPhase | OUT | 段内相位（Phase） |
| bSegChange | BOOL | OUT | 段切换沿单发（Segment change edge），TRUE 持续一拍 |
| bDone | BOOL | OUT | 全部段完成（Profile done） |
| uErrorId | UDINT | OUT | 事件码，段位 16#0002_xxxx（编码前与 DL_Algo VERSION.md 核对） |

设计要点：
- 斜坡插值：eRamp 态每拍 `fSetpoint += (fTarget − fRampStart) × fDt / fRampTimeSec`（fRampStart=本段斜坡起点值，fDt=tSampleTime 折算秒，量纲推导 R20 注明）；到达目标（带 fTol 容差，禁浮点判等 R4 防御）→ eSoak。
- 保温：段内计时器（自实现时间戳累加，因 bHold 冻结语义 TON 不适用——TON 无保持冻结语义，头注释声明自实现理由）；计满 → 下段。
- 跳段：bSkipSeg 上升沿 → 当前段结束、fRampStart := fSetpoint（当前值）、nSegAct+1；末段跳段 → 完成（信息级 `0002_0110`）。
- 保持：bHold 电平冻结积分累加与计时，不改变段号；恢复后从冻结点继续。
- 跟踪（R19）：bTrack 优先级高于首扫与运行，`IF bTrack OR (NOT bInit) THEN fSetpoint := fTrackValue; fRampStart := fTrackValue; bInit := TRUE`；跟踪释放后从当前值继续本段（验收向量 V7 必测中途跟踪不锁死）。
- 循环：bLoopProfile 且末段完成 → nSegAct:=1、fRampStart:=fSetpoint，不回 eIdle。
- 参数防御：nSegCount 钳位 [1,16] 信息级 `0002_0111`；aRampTime=0 段阶跃直达信息级 `0002_0112`；aTarget 非有限值 → 该段目标取前段目标（不可达防御）+ `0002_0220`【故障级】；tSampleTime 钳位沿用 0.5 公约。
- 故障集：`0002_0220` 段目标非有限值【故障级】（锁存进 eFault，仅 bReset 清）；信息级：`0002_0110` 末段跳段、`0002_0111` 段数钳位、`0002_0112` 零斜坡阶跃、`0002_0113` 采样周期钳位。
- 验收向量：V1 三段 Ramp-Soak-Ramp 逐拍复算（给定 tSampleTime/斜坡时间序列，断言每拍 fSetpoint）；V2 保持冻结恢复连续；V3 跳段（含末段）；V4 中途跟踪脉冲→释放后从跟踪值继续（R19 必测）；V5 循环重启；V6 非有限值目标故障锁存；V7 零斜坡阶跃直达。

---

## 第 4 节 依赖清单（全库既有组件，本轮零新增跨泳道 DUT）

| 组件 | 依赖 | 合法性（目录契约依赖矩阵） |
|---|---|---|
| FB_DL_SingleSolenoidCyl | Standard.library；I_DL_Cylinder/E_DL_CylinderState；FB_DL_SignalDebounce（可选防抖） | Device→Base ✓ |
| FB_DL_VacuumEjector | I_DL_VacuumGenerator（随本块同族接口文件） | Device 内 ✓ |
| FB_DL_StarDeltaMotor | E_DL_MotorState（既有 I_DL_MotorDriver 契约文件） | Device 内 ✓ |
| FB_DL_VfdGeneric | I_DL_VfdDrive（本族接口文件） | Device 内 ✓ |
| FB_DL_AnalogValve | I_DL_ProportionalValve（本族接口文件） | Device 内 ✓ |
| FB_DL_ThreePointValve | I_DL_MotorizedValve（本族接口文件） | Device 内 ✓ |
| FB_DL_AxisHomingSeq / AxisRelativeMove / AxisVelocityMove | I_DL_MotionAxis/E_DL_AxisState（既有） | Motion 内 ✓ |
| FB_DL_EnthalpyCompareCtrl | FC_DL_HumidAirEnthalpy（DL_Algo） | Process→Algo ✓ |
| FB_DL_OccScheduleWindow | FB_DL_TimeWindowCheck + FC_DL_DayOfWeekCalc（DL_Base） | Process→Base ✓ |
| FB_DL_RampSoakProfile | Standard.library（无库内依赖，DL_Algo 自持） | Algo→无 ✓ |

## 第 5 节 来源标签清单（function_tags 挂载，收尾回写 INDEX_REGISTRY）

| # | 组件 | 子库 | 来源标签 |
|---|---|---|---|
| 1 | FB_DL_SingleSolenoidCyl | DL_Device | lbp-basic-process, lbp-device |
| 2 | I_DL_VacuumGenerator | DL_Device | lbp-basic-process, lbp-device |
| 3 | FB_DL_VacuumEjector | DL_Device | lbp-basic-process, lbp-device |
| 4 | FB_DL_StarDeltaMotor | DL_Device | lbp-basic-process, lbp-device |
| 5 | I_DL_VfdDrive | DL_Device | lbp-basic-process, lbp-device |
| 6 | FB_DL_VfdGeneric | DL_Device | lbp-basic-process, lbp-device |
| 7 | I_DL_ProportionalValve | DL_Device | lbp-basic-process, lbp-device |
| 8 | FB_DL_AnalogValve | DL_Device | lbp-basic-process, lbp-device |
| 9 | I_DL_MotorizedValve | DL_Device | lbp-basic-process, lbp-device |
| 10 | FB_DL_ThreePointValve | DL_Device | lbp-basic-process, lbp-device |
| 11 | FB_DL_AxisHomingSeq | DL_Motion | plcopen-motion, s7-motion |
| 12 | FB_DL_AxisRelativeMove | DL_Motion | plcopen-motion, s7-motion |
| 13 | FB_DL_AxisVelocityMove | DL_Motion | plcopen-motion, s7-motion |
| 14 | FB_DL_EnthalpyCompareCtrl | DL_Process | oscat-building, lgf-datetime, hvac |
| 15 | FB_DL_OccScheduleWindow | DL_Process | oscat-building, lgf-datetime, hvac |
| 16 | FB_DL_RampSoakProfile | DL_Algo | lgf-technology |

## 第 6 节 交付与验收（编码阶段）

1. 16 个 `.st` 落盘：DL_Device 10、DL_Motion 3、DL_Process 2、DL_Algo 1；文件名=POU 名；接口与其状态枚举同文件（头注释注明归属）。
2. 文件头「开源溯源 (Origin)」逐组件标注 RAW_NOTES_R6 对应 S 条目与来源标签；头注释红线自检用语义描述，**严禁出现被禁记号原文**（0.10）。
3. 子库 VERSION.md（DL_Device 0.1.0→0.2.0、DL_Motion 0.1.0→0.2.0、DL_Process 0.1.0→0.2.0、DL_Algo 1.1.0→1.2.0）+ MANUAL 增补 + 总库五件套 + INDEX_REGISTRY.json（72→88，v1.5.0）+ AI 语料 +16 同批落盘。
4. 自检：八条红线 + R19/R20/R21/R22/R23 + 0.1~0.15 公约逐条；机检沿用 R5 口径扩展（首扫判据文本模板 grep、bFault 派生式 grep、接口方法计数 ≤6、POU 终结符成对、CASE-ELSE 全带、限位/线圈互斥出口断言存在性）。
5. 验收向量最低集：每个状态机 FB ≥ 正常跃迁链 1 条 + 非法态兜底 1 条 + 中途插入指令/跟踪向量 1 条（0.1/0.15）；1.10 必含 bTrack 重同步向量；2.11 必含四模式各一条 + 超时/行程双护栏向量；3.16 必含逐拍数值复算向量（R13 逐扫描推演）。
6. 收尾回写 SOURCE_HUNTING_MATRIX.md 第 5 节（见 RAW_NOTES_R6 收尾清单）+ ROADMAP.md 勾选 16 项。

## 第 7 节 故障码分配台账（编码前与各子库 VERSION.md 核对，冲突顺延）

| 子库 | 已占码（R1~R5） | 本轮新分配 |
|---|---|---|
| DL_Device（0003） | 信息级 0101；故障级 0201~0211 | 信息级 0102~0108；故障级 0220~0222（#1）、0230~0232（#3）、0240~0246（#4）、0250~0252（#6）、0260~0261（#8）、0270~0272（#10） |
| DL_Motion（0004） | 信息级 0101/0102/0103/0105；故障级 0201/0202 | 信息级 0106/0107；故障级 0210~0213（#11）、0220~0221（#12）、0230（#13） |
| DL_Process（0005） | 信息级 0101/0102 | 信息级 0103（#14）、0210/0211（#15 信息级占 02xx 段：日历类无锁存故障，沿用 TimeWindowCheck 先例并头注释声明）；故障级 0201/0202（#14） |
| DL_Algo（0002） | 0001/0101/0102/0502 等（以 VERSION.md 实表为准） | 信息级 0110~0113；故障级 0220（#16） |

> DL_Process #15 信息级码占用 02xx 段为有意裁定：日历排程块全部事件均为信息级（无安全联锁），故障级段整体保留给后续工艺联锁件；头注释显式声明，避免读者误判。若终审裁定不合公约，顺延改 0005_0103~0104 并 R11 留档。
