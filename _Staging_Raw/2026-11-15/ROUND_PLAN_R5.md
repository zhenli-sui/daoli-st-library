# ROUND_PLAN_R5 —— Round 05 引脚级规格书（16 项）

> 轮次：R5（2026-11-15）｜ 方向：**DL_Device 开库** + DL_Motion / DL_Process 立项 + DL_Base/DL_Algo 补强
> 编制：道莅工控代码库产品总监（兜底模式）｜ 狩猎留痕：同目录 `RAW_NOTES_R5.md`
> 执行规则：本规格书为编码阶段唯一契约；偏离必须依规则 R11 在头注释留档。

---

## 第 0 节 公共约定（编码侧逐字遵守，优先级高于逐组件条款）

0.1 **R8 首扫范式**：所有含初始化/跟踪逻辑的 FB，首扫判据一律 `IF bTrack OR (NOT bInit) THEN ... bInit := TRUE`，禁止 `IF bInit OR bTrack`；验收向量必含「运行中途插入跟踪脉冲」向量。
0.2 **R19 信息级码**：`bError` 一律为显式排除信息级码的派生式；故障码表逐条标注【故障级】/【信息级】；信息级码（钳位、饱和、自适应修正）只进 `uErrorId` 不进 `bError`。
0.3 **R20 量纲**：每个状态变量量纲标注 = 赋值表达式量纲推导结果；被限幅钳位的量，注释量纲与限幅域一致。
0.4 **双语注释**：每个引脚/枚举项声明行 `// 中文物理意义（English term）[单位] 取值范围/默认行为`。规格书引脚表给出中英语义基线，编码侧照此补全。
0.5 **时间基准显式化**：凡含积分/滤波/超时判定的组件，`tSampleTime : TIME := T#100MS` 显式引脚（仅对连续量组件适用；纯事件型组件用 TON 超时引脚即可）。
0.6 **限幅对调自修复**：参数对 `fXxxMin > fXxxMax` 时对调 + 置 `16#0001_0001`（段码见 0.7）+ 继续计算，不中断。
0.7 **故障码段位分配（R5 起）**：DL_Device 族 `16#0003_xxxx`，DL_Motion 族 `16#0004_xxxx`，DL_Process 族 `16#0005_xxxx`，DL_Base/DL_Algo 补强件沿用所在子库既有段（编码前与各子库 VERSION.md 故障码表核对一次，冲突顺延）。信息级码统一 `16#0xxx_01xx`，故障级 `16#0xxx_02xx` 起段。
0.8 **非有限值防御**：FC 全部 REAL 输入（含"看似常量"参数）先做 `fX <> fX` 检测再比较；出口默认值在第一条防御 IF 之前赋值。
0.9 **零全局耦合**：时间、温度、压力等环境量一律引脚注入，禁止读 CPU 钟 / `RD_LOC_T` / `__SYSTEM`；禁止 `%I/%Q/%M` 与 GVL。
0.10 **目录前置**：`C:\Library\DL_Motion` 与 `C:\Library\DL_Process` 物理目录已存在但为空，**编码阶段创建**各 `VERSION.md`（初始 0.1.0）与 `MANUAL_DL_Motion.md` / `MANUAL_DL_Process.md` 手册骨架；`DL_Device` 同理（0.1.0 起版）。入库后同步 INDEX_REGISTRY.json / AI 语料 / 总库五件套。
0.11 **接口契约三段式**：本规格每个 `I_DL_*` 按「属性（PROPERTY GET/SET）+ 方法（METHOD）+ 状态枚举」三段定义；接口方法 ≤6 个（红线：超 6 即拆）。

---

## 第 1 节 DL_Device 开库四件套（8 项）

### 1.1 `I_DL_Cylinder`（接口）｜DL_Device｜来源标签 `lbp-device`

功能：双电控气缸标准抽象。DL_Process 全部机站动作层的最小公共件。

- 状态枚举（随接口同文件，头注释注明归属）`E_DL_CylinderState`：eIdle(0)/eExtending(10)/eExtended(20)/eRetracting(30)/eRetracted(40)/eFault(99)，各项带编号显式赋值与双语注释。
- 属性（PROPERTY GET）：`eState : E_DL_CylinderState`（当前状态）；`bExtended : BOOL`（伸出到位磁开反馈）；`bRetracted : BOOL`（缩回到位磁开反馈）；`bFault : BOOL`（故障锁存中）；`uErrorId : UDINT`（末次故障码）。
- 方法（METHOD）：`CmdExtend()`（伸出指令，单发）；`CmdRetract()`（缩回指令，单发）；`CmdStop()`（双线圈全断，保持当前位置）；`CmdReset() : BOOL`（复位故障，返回是否可复位）。
- 边界防错：方法在 eFault 态一律拒绝并返回 FALSE；禁止方法内做任何 I/O 访问（由实现块映射）。

### 1.2 `FB_DL_PneumaticCylinder`（功能块，实现 I_DL_Cylinder）｜DL_Device｜来源标签 `lbp-device`

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bCmdExtend | BOOL | IN | 伸出指令（Extend command），上升沿生效 |
| bCmdRetract | BOOL | IN | 缩回指令（Retract command），上升沿生效 |
| bSnsExtended | BOOL | IN | 伸出到位磁性开关（Extended reed switch），TRUE=到位 |
| bSnsRetracted | BOOL | IN | 缩回到位磁性开关（Retracted reed switch），TRUE=到位 |
| bInterlock | BOOL | IN | 允许动作联锁（Motion interlock），TRUE=允许，默认 FALSE 不动 |
| tTimeoutExt | TIME | IN | 伸出到位超时（Extend timeout），默认 T#2S，0=禁用自检 |
| tTimeoutRet | TIME | IN | 缩回到位超时（Retract timeout），默认 T#2S |
| tDebounce | TIME | IN | 磁开防抖窗口（Sensor debounce），默认 T#20MS，0=直通 |
| bReset | BOOL | IN | 上升沿复位故障 |
| bSolenoidExt | BOOL | OUT | 伸出线圈输出（Extend solenoid coil） |
| bSolenoidRet | BOOL | OUT | 缩回线圈输出（Retract solenoid coil） |
| eState / bExtended / bRetracted / bFault / uErrorId | — | OUT | 与接口属性一一对应；bMoving : BOOL（运动中指示） |
| uCycleCount | UDINT | OUT | 行程计数（Stroke count），缩回到位上升沿 +1 |

设计要点：
- 状态机 `E_DL_CylinderState` + CASE + ELSE（ELSE → eFault，码 `16#0003_0201` 非法状态）。
- **双线圈互斥硬约束**：`bSolenoidExt AND bSolenoidRet` 恒不可同真（CASE 内仅单态置一端，并在出口断言对调）。
- TON/R_TRIG 周期首部无条件刷新（R7）；磁开防抖内嵌 `FB_DL_SignalDebounce` 双通道。
- 故障集：伸出超时 `0003_0202`、缩回超时 `0003_0203`、双传感器同时动作 `0003_0204`（位置冲突，锁存）、非法状态 `0003_0201`；全部锁存，仅 bReset 可清（R15）。

### 1.3 `I_DL_MotorDriver`（接口）｜DL_Device｜来源标签 `lbp-device`

- 枚举 `E_DL_MotorState`：eIdle(0)/eStarting(10)/eRunning(20)/eStopping(30)/eTripOverload(40)/eFault(99)。
- 属性 GET：`eState`、`bRunning`（运行反馈）、`bFault`、`uErrorId`、`bRestartInhibit`（重启抑制激活中）。
- 方法：`CmdStart() : BOOL`（启动，被抑制/故障态返回 FALSE）；`CmdStop()`（停止）；`CmdReset() : BOOL`（复位过载/故障）。

### 1.4 `FB_DL_DolMotor`（功能块，实现 I_DL_MotorDriver）｜DL_Device｜来源标签 `lbp-device`

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bCmdStart | BOOL | IN | 启动指令（Start command），上升沿生效 |
| bCmdStop | BOOL | IN | 停止指令（Stop command），电平生效 |
| bFbContactor | BOOL | IN | 接触器辅助触点反馈（Contactor feedback），TRUE=吸合 |
| bThermalOverload | BOOL | IN | 热继电器过载信号（Thermal overload trip），TRUE=过载 |
| bPermitStart | BOOL | IN | 启动允许联锁（Start permit），TRUE=允许 |
| tFbWindow | TIME | IN | 指令-反馈校验窗口（Feedback check window），默认 T#500MS |
| tMinRunTime | TIME | IN | 最短运行时间（Min run time），默认 T#5S |
| tRestartInhibit | TIME | IN | 重启抑制冷却时间（Restart inhibit），默认 T#60S |
| uMaxStartsPerHour | USINT | IN | 每小时最大启动次数（Max starts/hour），默认 6 |
| bReset | BOOL | IN | 上升沿复位故障 |
| bContactorCmd | BOOL | OUT | 接触器线圈输出（Contactor coil command） |
| eState / bRunning / bFault / uErrorId / bRestartInhibit | — | OUT | 接口属性映射 |
| uStartCount | UDINT | OUT | 累计启动次数（Start count） |

设计要点：
- 启动后 tFbWindow 内反馈未吸合 → `0003_0205` 接触器拒动；运行中反馈意外断开 → `0003_0206` 失反馈脱扣。
- 防频繁启停双保险：小时窗计数（60s 滑窗近似为每小时计数桶）超限 → `0003_0207`（信息级拒绝启动）；停机后 tRestartInhibit 内再启动被拒 → `0003_0208`。
- 过载锁存 `0003_0209` 仅 bReset 可清；运行不足 tMinRunTime 重复启停 → `0003_020A`。

### 1.5 `I_DL_AnalogSensor`（接口）｜DL_Device｜来源标签 `namur-ne43`

- 枚举 `E_DL_SignalQuality`：eGood(0)/eUnderRange(10)/eOverRange(20)/eWireBreakLow(30)/eWireBreakHigh(40)/eOpenLoop(50)。
- 属性 GET：`fValue : REAL`（工程量当前值，NaN 防御后输出）；`eQuality : E_DL_SignalQuality`（信号质量分级）；`bAlarmHH/H/L/LL : BOOL`（四级报警位组——属性逐个 GET）；`uErrorId : UDINT`。

### 1.6 `FB_DL_AnalogTransmitter`（功能块，实现 I_DL_AnalogSensor）｜DL_Device｜来源标签 `namur-ne43`

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| fRawInput | REAL | IN | 原始输入（Raw input），已线性化的 mA/0~10V 物理域值，单位注释由调用方约定 |
| fRawLow / fRawHigh | REAL | IN | 原始域量程（Raw span endpoints），如 4.0/20.0 mA；对调自修复（0.6） |
| fEuLow / fEuHigh | REAL | IN | 工程量程（Engineering span endpoints），如 0.0/100.0 [%] 或 [kPa] |
| eBreakDirection | E_DL_BreakDir | IN | 断线故障方向（Break direction）：eLow(0)按<3.6mA低断判定 / eHigh(1)按>21mA高通断判定，由变送器实际配置决定 |
| fFaultLow / fFaultHigh | REAL | IN | NE43 故障门限（NE43 fault thresholds），默认 3.6 / 21.0（原始域） |
| fFilterTC | TIME | IN | 滤波时间常数，默认 T#1S，0=直通（内嵌 FB_DL_MovingAverage 替代——见设计要点） |
| fAlarmHH/H/L/LL | REAL | IN | 四级报警门限（Alarm limits），量纲=工程量 |
| bEnableFilter | BOOL | IN | 使能滑动平均滤波，默认 TRUE |
| fValue / eQuality / bAlarmHH/H/L/LL / uErrorId | — | OUT | 接口属性映射；另出 bWireBreak : BOOL、bRangeViol : BOOL（欠/超量程合并位） |

设计要点：
- 标定走 `FC_DL_LinearScale`（除零/对调保护继承）；滤波走 `FB_DL_MovingAverage`（窗口 `uFilterWindow : USINT := 8` 替代 TC 引脚，规格定稿为 `uFilterWindow`，删除 fFilterTC）。
- **诊断在原始 mA 域判定**（S-5 提取点③）：fRawInput < fFaultLow → eWireBreakLow；> fFaultHigh → eWireBreakHigh；0 域附近判 eOpenLoop（<0.5×fFaultLow）；3.8~4 段 eUnderRange、20~20.5 段 eOverRange（按量程比例内插两门限，不硬编码）。
- 故障态 fValue 保持**末次有效值**并置 eQuality（S-5「hold last good value」语义），uErrorId 同步；四级报警在 eGood/eUnderRange/eOverRange 时照常计算，故障态全部保持并置 `0003_0210`。
- 非有限值防御按 0.8；eBreakDirection 不匹配方向时不误报（只判配置方向）。

### 1.7 `I_DL_TemperatureZone`（接口）｜DL_Device｜来源标签 `lbp-device`

- 枚举 `E_DL_TempZoneState`：eIdle(0)/eAutoTuning?(不做)/eHeating(10)/eCooling(20)/eHolding(30)/eSensorBreak(40)/eFault(99)。
- 属性 GET：`fTempActual : REAL`（实测温度 [°C]）、`fPowerOut : REAL`（输出功率 [-100..100 %]）、`eState`、`bFault`、`uErrorId`。
- 方法：`SetSetpoint(fTemp : REAL) : BOOL`（设定目标温度 [°C]，返回合法性）；`CmdEnable(bOn : BOOL)`（投运/退出）；`CmdReset() : BOOL`。

### 1.8 `FB_DL_HeatCoolZone`（功能块，实现 I_DL_TemperatureZone）｜DL_Device｜来源标签 `lbp-device`

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| iTempSensor | I_DL_AnalogSensor | IN_OUT | 温度信号源接口引用（Sensor interface reference），由上层注入 FB_DL_AnalogTransmitter 实例 |
| fTempSetpoint | REAL | IN | 目标温度（Setpoint）[°C]，范围由 fTempMin/Max 钳位 |
| fTempMin / fTempMax | REAL | IN | 设定值边界（Setpoint bounds）[°C]，默认 0.0/300.0 |
| fbPid | FB_DL_PidController | IN_OUT | 温度 PID 实例（由调用方组态注入，参数外置） |
| fbPwmHeat / fbPwmCool | FB_DL_PwmDutyController | IN_OUT | 加热/冷却 SSR PWM 实例 |
| fSplitLow / fSplitHigh | REAL | IN | 分程切换点（Split-range crossover）[%]，默认 50.0 对称 |
| eBreakAction | E_DL_BreakAction | IN | 断偶动作方向（Break action）：eHeatOff(0) 切断加热 / eCoolOff(1) 切断冷却，按对象安全策略配置 |
| bEnable | BOOL | IN | 投运使能（Zone enable） |
| bHeaterOut / bCoolerOut | BOOL | OUT | 加热/冷却执行通道（映射 PWM 占空后布尔量由 fbPwm* 输出，此处为调用便利镜像） |
| fTempActual / fPowerOut / eState / bFault / uErrorId | — | OUT | 接口属性映射 |

设计要点：
- **R4 算法族首个上层消费者**：PID（含抗饱和）→ SplitRangeControl（热/冷通道分配）→ 两路 PwmDutyController（SSR 驱动）；三实例均经引脚注入，本块零内嵌组态、零魔法数。
- 断偶保护：`iTempSensor.eQuality ∈ {eWireBreak*, eOpenLoop, eSensorBreak}` → 按 eBreakAction 切断对应通道并锁存 eSensorBreak 态 `0003_0211`；退出需 CmdReset 且质量恢复 eGood。
- 设定值经 fTempMin/Max 钳位（信息级 `0003_0101` 钳位提示，不置 bError）；fPowerOut 注释量纲 `[%]`（R20）。
- 采样周期 tSampleTime 显式引脚（0.5），传给内嵌 PID/PWM。

---

## 第 2 节 DL_Motion 族（3 项，T2-4 Motion + T1-6 PLCopen 双源）｜目录编码阶段创建

### 2.1 `I_DL_MotionAxis`（接口）｜DL_Motion｜来源标签 `s7-motion / plcopen`

- 枚举 `E_DL_AxisState`：eDisabled(0)/eStandstill(10)/eHoming(20)/eDiscreteMotion(30)/eContinuousMotion(40)/eStopping(50)/eErrorStop(60)——PLCopen 六态 + 禁用态，编号显式，双语注释（S-2 提取点④）。
- 属性 GET：`eState`、`fPosition : REAL`（当前位置 [mm 或 度，单位由组态注释]）、`fVelocity : REAL`（当前速度 [mm/s 或 度/s]）、`bEnabled`、`bHomed`、`bError`、`uErrorId : UDINT`。
- 方法：`Enable(bOn : BOOL)`（MC_Power 语义）；`Reset() : BOOL`（MC_Reset 语义，确认报警）；`Stop()`（MC_Stop 语义：停止并拒绝新任务）；`MoveAbsolute(fPos : REAL, fVel : REAL, fAcc : REAL) : BOOL`；`MoveRelative(fDist : REAL, fVel : REAL, fAcc : REAL) : BOOL`；`MoveVelocity(fVel : REAL, fAcc : REAL) : BOOL`。方法共 6 个，达红线临界——Homing 由 `FB_DL_AxisHomingSeq`（后续轮）承载，不入本接口。

### 2.2 `FB_DL_SingleAxis`（功能块，实现 I_DL_MotionAxis）｜DL_Motion｜来源标签 `plcopen / s7-motion`

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| fSoftLimitPos / fSoftLimitNeg | REAL | IN | 软限位上下限（Soft limits）[mm]，默认 ±1E6；非有限值防御 |
| fVelMax / fAccMax / fDecMax | REAL | IN | 速度/加/减速度物理上限（Dynamic limits）[mm/s]、[mm/s²] |
| fPosTolerance | REAL | IN | 到位容差（Position tolerance）[mm]，默认 0.01 |
| bDriveReady | BOOL | IN | 驱动就绪反馈（Drive ready feedback） |
| bDriveFault | BOOL | IN | 驱动故障反馈（Drive fault feedback），TRUE=故障 |
| fActPosition | REAL | IN | 实际位置注入（Actual position injection），真实驱动由上层每拍写入；未接驱动时内部虚拟积分自算 |
| bUseVirtualKinematics | BOOL | IN | 虚拟运动学开关（Virtual kinematics），TRUE=无硬件仿真模式，位置由内部积分器生成 |
| eState / fPosition / fVelocity / bEnabled / bHomed / bError / uErrorId | — | OUT | 接口属性映射 |

设计要点：
- 状态机 = PLCopen 六态 + eDisabled，CASE + ELSE（ELSE → eErrorStop，码 `0004_0201`）；方法指令全部单发化（R_TRIG 周期首部刷新）。
- 虚拟运动学：位置积分复用本库 SCurve 限 jerk 思想的简化梯形段（加减速钳位 fAccMax/fDecMax），`bUseVirtualKinematics=FALSE` 时 fPosition 直接取 fActPosition——**同一状态机适配真实驱动与仿真**。
- 指令互斥：同拍多条 Move 指令按 Absolute>Relative>Velocity 优先级仲裁并置信息级 `0004_0101` 指令丢弃提示；eStopping/eErrorStop 态拒绝一切运动指令（MC_Stop 语义）。
- bDriveFault → eErrorStop 锁存，仅 Reset 清（R15）；软限位越界预判拦截（目标位超限直接拒绝，`0004_0202`）。

### 2.3 `FB_DL_AxisJogController`（功能块）｜DL_Motion｜来源标签 `s7-motion`

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| iAxis | I_DL_MotionAxis | IN_OUT | 轴接口引用（Axis reference） |
| bJogPos / bJogNeg | BOOL | IN | 正/负向点动（Jog forward/backward），电平生效 |
| fJogSlow | REAL | IN | 低速点动速度（Slow jog velocity）[mm/s]，默认 5.0 |
| fJogFast | REAL | IN | 高速点动速度（Fast jog velocity）[mm/s]，默认 50.0 |
| bFastSelect | BOOL | IN | 高速选择（Fast select），TRUE 且按住 ≥ tFastDelay 自动切高速 |
| tFastDelay | TIME | IN | 低→高速切换延时（Fast switch delay），默认 T#1S |
| fSoftLimitPos / fSoftLimitNeg | REAL | IN | 点动软限位（Jog soft limits）[mm]，独立于轴组态以便现场收紧 |
| fAcc | REAL | IN | 点动加减速度（Jog acceleration）[mm/s²] |

设计要点：
- 点动 = 长按低速、tFastDelay 后自动升高速、松开即停（连续性：升/降速均走 iAxis 速度域限幅，不做阶跃）。
- 软限位拦截：接近限位 tGuardDist（由 fVel 与 fAcc 现算制动距离）内强制降为低速并在限位处拒绝继续（S-2 软限位预判语义的简化版）。
- 双向同按 → 停止 + 信息级 `0004_0102`；iAxis 不在 eStandstill/eContinuousMotion → 指令拒绝。

---

## 第 3 节 DL_Process 族（2 项，T2-7 PackML）｜目录编码阶段创建

### 3.1 `FB_DL_PackMlStateMachine`（功能块）｜DL_Process｜来源标签 `packml`

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| eMode | E_DL_UnitMode | IN | 单元模式（Unit mode）：eInvalid(0)/eProduction(1)/eMaintenance(2)/eManual(3)/eUserDef4..15——S-1 提取点④ |
| eCmd | E_DL_PackMlCmd | IN | 标准命令（Standard command），由 FB_DL_PackMlCmdDecoder 供给，单发化 |
| bStateComplete | BOOL | IN | 子工序完成信号（State complete），acting 态推进用 |
| bInterlockOk | BOOL | IN | 工艺联锁（Process interlock），Execute 态保持条件 |
| bProcessAbort | BOOL | IN | 工艺级急停触发（Process abort trigger），如安全门/急停链 |
| eState / ePrevState | E_DL_PackMlState | OUT | 当前/前一状态（Current/previous state） |
| bInExecute | BOOL | OUT | Execute 态指示（In execute）——OEE 计时用 |
| bHeldByMachine / bSuspendedByLine | BOOL | OUT | 机内保持（Held）/机外挂起（Suspended）区分指示——S-1 提取点⑤ OEE 根因语义 |
| uErrorId | UDINT | OUT | 故障码 |

枚举（随块同文件）：`E_DL_PackMlState` 17 项（eUndefined(0)…eCompleted(17)，编号严格对齐 S-1 提取点①，逐项双语注释 acting/wait 属性）；`E_DL_PackMlCmd` 11 项（eUndefined(0)…eStateComplete(11)）；`E_DL_UnitMode`（eInvalid/eProduction/eMaintenance/eManual/eUser4..eUser15）。

设计要点：
- 跃迁表严格按 S-1 提取点：命令驱动 + acting 态由 bStateComplete 自动推进（Idle→Start→Starting→(SC)→Execute 等）；acting/wait 分类写进枚举注释。
- 一态一职责（一 FB 一主状态机红线天然满足）；Aborting 为最高优先级出口：bProcessAbort 或非法态 → eAborting（CASE ELSE 兜底同向，0.1/0.2 公约落实）；Clearing 完成后必经 eStopped（S-1「abort 后强制去污步」语义）。
- 模式切换仅允许 eStopped/eIdle/eCompleted 稳态（S-1 提取点⑥），其余态下 eMode 变更被拒并置信息级 `0005_0101`。
- bProcessAbort → Abort 路径时保留 ePrevState 供 HMI 复盘；Completed→Reset→Resetting→Idle 闭环。
- 本块**不编排任何具体工艺动作**——纯状态机框架，动作由调用方按态派发（Level 2 依赖注入原则）。

### 3.2 `FB_DL_PackMlCmdDecoder`（功能块）｜DL_Process｜来源标签 `packml`

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bCmdReset / bCmdStart / bCmdStop / bCmdHold / bCmdUnhold / bCmdSuspend / bCmdUnsuspend / bCmdAbort / bCmdClear / bCmdComplete | BOOL | IN | 十个离散命令源（HMI/MES/联锁均可接），电平生效 |
| uCmdWord | WORD | IN | 可选命令字入口（Optional command word），bit0..bit9 与离散源一一对应；离散源任一为 TRUE 时命令字被忽略 |
| tMinPulse | TIME | IN | 最小命令脉宽（Min command pulse），默认 T#100MS，防抖动误触发 |
| eCmd | E_DL_PackMlCmd | OUT | 单发化命令输出（One-shot command），持续一拍 |
| bCmdConflict | BOOL | OUT | 命令冲突指示（Command conflict），同拍多命令 |
| uLastCmd | E_DL_PackMlCmd | OUT | 末次有效命令（Last accepted command） |

设计要点：
- 同拍多命令 → 冲突位 + 全部丢弃（信息级 `0005_0102`，安全侧选择「不猜」）；优先级仅用于**显示**仲裁（Abort 显示最上），不用于执行——执行侧拒绝是状态机的职责，解码器不做跃迁判断（职责单一）。
- 单发化经 R_TRIG + tMinPulse 展宽；命令字位域注释逐位双语（bit0=Reset … bit9=Complete）。

---

## 第 4 节 DL_Base 补强族（2 项，T2-1 LGF Date and Timer 开组）

### 4.1 `FC_DL_DayOfWeekCalc`（函数）｜DL_Base｜来源标签 `lgf-datetime`

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| uYear | UINT | IN | 年份（Year），1980..2099 |
| uMonth | USINT | IN | 月（Month）1..12 |
| uDay | USINT | IN | 日（Day）1..31，按月天数校验含闰年 |
| eWeekday | E_DL_Weekday | OUT | 星期几（Day of week）：eMonday(1)..eSunday(7)，**ISO-8601 序（周一=1）** |
| uErrorId | UDINT | OUT | 参数非法码 `0001_0201`（日期越界），返回 0 值枚举 eInvalid(0) |

设计要点：
- Sakamoto/蔡勒算法 clean-room（S-3：只取 LGF「星期计算是独立原子 FC」的粒度结论与星期编号惯例的**差异声明**——LGF 用周日=1，本库取 ISO 周一=1 并在规格与手册注明理由：与 GB/T 7408、MES 排产、E_DL_UnitMode 无关性）。
- 闰年判定（4/100/400）；uMonth/uDay/uYear 越界一律 `0001_0201` 且输出 eInvalid(0)；无浮点、无循环（纯分段计算，无 WHILE 防死锁义务但保留机检说明）。
- 枚举 `E_DL_Weekday`：eInvalid(0)/eMonday(1)/…/eSunday(7)，随 FC 同文件。

### 4.2 `FB_DL_TimeWindowCheck`（功能块）｜DL_Base｜来源标签 `lgf-datetime`

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| uHourNow / uMinNow | USINT | IN | 当前时刻注入（Injected local time），0..23 / 0..59——**禁读 CPU 钟（0.9）** |
| bEnableDay | BOOL | IN | 本日窗使能（Day window enable），与星期表配合 |
| aWeekdayEnable | ARRAY[1..7] OF BOOL | IN | 周一~周日各日使能表（Weekday enable table），索引 1=周一（ISO 序，与 4.1 一致） |
| uHourOn / uMinOn | USINT | IN | 窗口开启时刻（Window on time） |
| uHourOff / uMinOff | USINT | IN | 窗口关闭时刻（Window off time）；支持跨零点（如 22:00→06:00） |
| bReset | BOOL | IN | — |
| bInWindow | BOOL | OUT | 当前处于窗口内（In window） |
| bPulseOnWindowOpen / bPulseOnWindowClose | BOOL | OUT | 窗口开/闭沿单发（Window open/close edge） |
| uErrorId | UDINT | OUT | 时刻非法 `0001_0202`（信息级：越界时刻按 FALSE 处理） |

设计要点：
- 跨零点判定：uOn > uOff 时窗口 = `t≥On OR t<Off`；uOn = uOff 视为 24h 全开（语义写注释）。
- LGF mode 巨无霸反例的落实：本块**只做每日窗单一语义**；每周/每月/每年窗按矩阵扩产规则拆独立块（ROADMAP 扩产条目，禁止塞 MODE 参数）。
- 输入时刻越界按信息级处理并钳位（0.2 公约）；沿单发用 R_TRIG 周期首部刷新。

---

## 第 5 节 DL_Algo 补强（1 项，T1-2 OSCAT Building 开组）

### 5.1 `FC_DL_HumidAirEnthalpy`（函数）｜DL_Algo｜来源标签 `oscat-building / psychrolib`

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| fTempC | REAL | IN | 干球温度（Dry-bulb temperature）[°C]，有效域 0.0..100.0 |
| fRelHum | REAL | IN | 相对湿度（Relative humidity）[%]，有效域 1.0..100.0 |
| fEnthalpy | REAL | OUT | 湿空气比焓（Moist air specific enthalpy）[kJ/kg 干空气] |
| uErrorId | UDINT | OUT | 输入越界/非有限值 `0001_0203`（信息级：钳位后照算） |

设计要点：
- 公式链 clean-room（S-6）：饱和蒸汽压 p_ws 用 Magnus-Tetens（与本库 FC_DL_DewPointCalc 同系数口径，常量复用）；含湿量 W = 0.622·φ·p_ws/(p - φ·p_ws)，大气压 fAtmPress : REAL := 101.325 [kPa] 作为引脚（默认值、非魔法数）；焓 h = 1.006·T + W·(2501 + 1.86·T)。
- 非有限值防御覆盖 fTempC/fRelHum/fAtmPress 全部 REAL 输入（0.8，FlowCompensate 教训）；fRelHum 钳位 [1,100]（防 p_ws 超线性和 W 发散）；fAtmPress 越界钳 [80,110] 并置码。
- 行为定义对标 OSCAT Building AIR_ENTHALPY（0~100 ℃ 域）与 PsychroLib GetMoistAirEnthalpy；不读取任何源码行，公开物理公式无版权义务，头注释如实标注。

---

## 第 6 节 交付与验收（编码阶段）

1. 16 个 `.st` 落盘：DL_Device 8、DL_Motion 3、DL_Process 2、DL_Base 2、DL_Algo 1；文件名=POU 名；接口与其枚举同文件（头注释注明归属）。
2. 新目录建档：DL_Device/DL_Motion/DL_Process 各创建 VERSION.md（0.1.0）+ MANUAL 骨架；总库五件套 + INDEX_REGISTRY.json + AI 语料同步（0.10）。
3. 自检：八条红线 + R19/R20/R21 + 0.1~0.9 公约逐条；机检脚本沿用 R4 的 `machine_check_r4.py` 口径扩展（新增：首扫判据文本模板 grep、bError 派生式 grep、接口方法计数 ≤6）。
4. 验收向量最低集：每个带状态机的 FB 至少含正常跃迁链 1 条 + 非法态兜底 1 条 + 中途插入指令向量 1 条（0.1）；FB_DL_PneumaticCylinder 必含双传感器冲突向量；FB_DL_AnalogTransmitter 必含 NE43 四段全电平扫描向量；FB_DL_PackMlStateMachine 必含 Abort→Clear→Reset 全恢复链向量。
5. 收尾回写 SOURCE_HUNTING_MATRIX.md 第 5 节四个 ◐ 组 + LBP 深化备注（见 RAW_NOTES_R5 收尾清单）。

## 预算与排期

- 本轮 16 项 ≥ 前两轮节奏（R3 14 项 / R4 16 项）；今日累计入库预计 30 → 46。
- 追赶 200/日缺口的增量手段按 ROADMAP 吞吐缺口条：编译验证固化为轮内动作（R5 起执行第 6.3 节机检扩展）+ 文档段并行化。
