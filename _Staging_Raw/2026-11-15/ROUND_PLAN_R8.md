# ROUND_PLAN_R8 —— Round 08 引脚级规格书（16 项）

> 轮次：R8（2026-11-15）｜ 方向：**DL_Motion 扩容 6 项**（电子齿轮 / 电子凸轮 / 龙门同步 / 力矩限制压装 / 色标位置锁存 / 梯形耗时估算）+ **DL_Process 扩容 6 项**（SMEMA 级联握手 / 配方管理 / 气密检漏 / 混合工艺相 / CIP 清洗 / 多层料仓）+ **DL_Device 收尾 1 族 2 项**（安灯塔契约 + 实现）+ **DL_Algo 补 2 项**（峰值检测 / 分级步进控制）
> 编制：道莅工控代码库产品总监（兜底模式）｜ 狩猎留痕：同目录 `RAW_NOTES_R8.md`（S-1~S-14，共 14 次真实检索）
> 执行规则：**本规格书为编码阶段唯一契约**；任何偏离必须在 `.st` 头注释按规则 R11 留档（写「规格偏离 + 理由 + 影响」三段），并在战报汇总。
> 合规铁律：闭源免费资产（LGF / LBP / 厂商手册 / 论坛教程）只借「功能分类 / 接口参数域 / 命名组织 / 状态语义」，**clean-room 独立实现**；每个 `.st` 头「开源溯源 (Origin)」按 `RAW_NOTES_R8` 对应 S 条目如实标注。
> 计划声明：16 项全部为真实工程缺口（`ROADMAP.md` 待办池直取 12 项 + 4 项经本轮检索新立项），**无凑数变体、无 MODE 巨无霸**。若编码/终审阶段裁定某项不具备高质量落地条件，宁减不凑（允许 14~15 项交付，须在战报注明原因）。
> 总库现状（本轮起点）：v1.6.0 ｜ 104 组件 ｜ counts = Base 24 / MathData 20 / Algo 18 / Device 28 / Motion 7 / Process 7 ｜ 今日已入库 78/200。

---

## 第 0 节 公共约定（编码侧逐字遵守，优先级高于逐组件条款）

0.1 **首扫范式（R19/R23）**：含初始化或跟踪逻辑的 FB 首扫判据一律 `IF bTrack OR (NOT bInit) THEN ... bInit := TRUE`（`bInit` 初值 FALSE），禁止反序写法；验收向量必须含「运行中途插入跟踪脉冲」向量。**纯事件型 / 连续运算型组件标注「免首扫」并在头注释声明**（本轮免首扫：`FB_DL_MarkPositionLatch`、`FB_DL_ConveyorLineLink`、`FB_DL_PeakDetector`、`FB_DL_StepController`、`FB_DL_SignalTower`）。

0.2 **信息级码（R21）**：`bFault` / `bError` 一律为**显式排除信息级码的派生式**；故障码表逐条标注【故障级】/【信息级】；信息级码只进 `uErrorId`，不进报警链、不置故障位。

0.3 **量纲（R20）**：状态变量注释量纲 = 赋值表达式推导量纲；被限幅钳位的量，注释量纲与限幅域一致（例：`fSlaveSpeedCmd` 经 `fVelLimit` 钳位，注释写 [mm/s]，限幅域同单位）。

0.4 **双语注释**：每个引脚 / 枚举项声明行 `// 中文物理意义（English term）[单位] 取值范围 / 默认行为`。

0.5 **定时器与边沿（R7/0.5）**：`TON` / `TOF` / `R_TRIG` / `F_TRIG` 实例一律在主体**最前部无条件周期刷新**，严禁置于 `IF` / `CASE` 分支内；实例入参先算成普通变量再喂实例。

0.6 **语义参数变更（R14）**：`TON` 的 `PT` 或相位类语义参数变化时，必须显式断输入一拍使已计时归零（防「改时间常数后计时不清零」的幽灵故障）。

0.7 **锁存与瞬态分离（R15）**：锁存型故障只在解除路径清码；瞬时型告警每拍重算；两类码不得混写同一个寄存器。

0.8 **码位段（沿用库级公约）**：DL_Base `16#0001_xxxx` ｜ DL_Algo `16#0002_xxxx` ｜ DL_Device `16#0003_xxxx` ｜ DL_Motion `16#0004_xxxx` ｜ DL_Process `16#0005_xxxx`。信息级 `01xx` 起、故障级 `02xx` 起。**本规格给出的码位已与各子库 `VERSION.md` 台账核对（见第 5 节），编码前仍须再核一次；冲突依公约 0.8「核对结果优先」顺延并留档。**

0.9 **非有限值防御**：全部 REAL / LREAL 输入先做自比检测（`fX <> fX` 或 `NOT (fX >= -DL_REAL_MAX AND fX <= DL_REAL_MAX)` 等价式）再做比较；出口默认值必须在第一条防御 `IF` **之前**赋值，保证任何早退路径输出确定。

0.10 **零全局耦合 + 零被禁记号**：时间 / 反馈 / 位置 / 状态一律引脚注入，**禁读 CPU 钟**；**禁止出现三类被禁记号**——全局变量表访问、外部变量声明、物理输入输出地址前缀（文件头红线自检时必须用语义转述描述，**不得把这些记号的字面量写进任何注释或字符串**）。定时基准一律由引脚给（`tSample` / `tFlash*` / `tCycle`）。

0.11 **接口契约三段式**：每个 `I_DL_*` 按「状态枚举（随文件发布，头注释注明归属）+ 属性（`PROPERTY` GET，只读）+ 方法（`METHOD`，≤6 个）」三段定义。

0.12 **接口实现块 OUT 列（R22）**：规格 OUT 列成员与接口属性同名者，实现块以只读 `PROPERTY GET` 承载，非接口成员保留 `VAR_OUTPUT`；头注释 R11 留档。

0.13 **接口调用配额**：每个接口引用每拍**至多一次**方法调用（`MoveVelocity` / `MoveAbsolute` / `SetFrequency` 等），禁止同拍重复下发；需要「改速」时走同一方法的连续调用语义，而不是先停再启。安全/联锁类组件头注释须声明「本库为**标准 PLC 逻辑编排与诊断镜像层**，不构成 ISO 13849 / IEC 62061 认证安全功能，安全回路由认证安全控制器承载」。

0.14 **浮点与除法**：浮点禁 `=` 判等（用 `ABS(fA - fB) < DL_FLOAT_EPS`）；一切除法带 `ABS(分母) > DL_FLOAT_EPS` 防零分支并置码；`WHILE` 必须带防死锁计数器（`DL_MAX_LOOP`）；数组存取必须做上下界检查后再索引。

0.15 **单位标注**：位置 mm、速度 mm/s、加速度 mm/s²、比值无量纲、压力 kPa 或 mbar（引脚注释固定一种）、流量 L/min 或 m³/h（引脚注释固定一种）、电导率 mS/cm、温度 ℃、时间 `TIME` 字面量。**同一 FB 内不得混用两种同类单位**。

0.16 **无魔法数**：一切阈值、限幅、超时、重试次数提为 `VAR CONSTANT`（`DL_` 前缀大写）或输入引脚。

0.17 **POU 终结符（硬性）**：每个 `FUNCTION_BLOCK` 必须以 `END_FUNCTION_BLOCK` 终结、每个 `FUNCTION` 以 `END_FUNCTION` 终结、每个 `INTERFACE` 以 `END_INTERFACE` 终结、每个 `TYPE ... END_TYPE` 成对。**文件头自检行必须显式写出「终结符成对 ✓」**。

0.18 **一文件一 POU**：`VAR_IN_OUT` 内的结构体 / 枚举若为本组件首次定义，随宿主文件发布并在子库 `VERSION.md` 登记「随 X 同文件发布」，禁止在其他文件重复声明。

0.19 **码位注释格式**：`.st` 内码位常量必须写成 `16#0004_0130` 形式并在同行注释标注【信息级】/【故障级】与语义，故障码表与常量表**逐条一致**。

0.20 **每个组件的验收向量（V1..Vn）必须在头注释「验收向量」段列出**，与规格第 6 节对应；终审按向量逐条推演。

### 泳道划分（四泳道并行编码，零文件交集、零新增共享 DUT）

| 泳道 | 组件 | 文件落点 | 泳道内自持契约 | 跨泳道 / 跨库依赖 |
|---|---|---|---|---|
| A | #1~#6（DL_Motion 6 项） | `C:\Library\DL_Motion\` | 4 个枚举随宿主发布：`E_DL_GearState`（#1）、`E_DL_CamState`（#2）、`E_DL_GantryState`（#3）、`E_DL_PressState`（#4）、`E_DL_MarkState`（#5） | 仅引用既有接口 `I_DL_MotionAxis`（2 个引用/块，**零修改**） |
| B | #7~#12（DL_Process 6 项） | `C:\Library\DL_Process\` | 6 个枚举 + 1 结构体随宿主发布：`E_DL_LineLinkState`、`E_DL_RecipeState`+`ST_DL_RecipeEntry`、`E_DL_LeakPhase`、`E_DL_MixPhase`、`E_DL_CipPhase`、`E_DL_MagState`+`E_DL_SlotState` | #12 无接口依赖（层位置信号引脚注入）；#10 引用既有 `I_DL_VfdDrive`（零修改）；#9 引用既有 `FB_DL_PidController`？**否——本块仅出阀位/泵指令，不内嵌 PID** |
| C | #13~#14（DL_Device 2 项） | `C:\Library\DL_Device\` | 3 个枚举随 `I_DL_TowerLight` 发布：`E_DL_TowerColor`、`E_DL_TowerPattern`、`E_DL_TowerState` | 零库内依赖（`FB_DL_SignalTower` 仅依赖 `TON` + 枚举） |
| D | #15~#16（DL_Algo 2 项） | `C:\Library\DL_Algo\` | 无新增枚举 | 零库内依赖（仅 `Standard.library`） |

> 泳道 B 的 #9（检漏）与 #10（混合）都可消费 Level 1，#11（CIP）与 #12（料仓）只做逻辑编排——**均不新增对 DL_Device 的强制依赖**，避免 Level 2 组件因 Device 组件缺失而无法单独导入。

---

## 第 1 节 泳道 A｜DL_Motion 扩容 6 项

### 1.1 `FB_DL_ElectronicGear`（功能块）｜DL_Motion｜来源标签 `plcopen-motion` / `lgf-technology`｜RAW_NOTES S-1

**功能**：电子齿轮耦合（MC_GearIn 语义 clean-room）。从轴速度指令 = 主轴实际速度 × 传动比 + 相位补偿项；整数比值对（分子/分母）避免浮点累积误差；啮合过渡按 `fAcc` / `fDec` 限幅平滑建立，脱开时从轴受控停止。

**随本块发布的枚举** `E_DL_GearState`：

| 枚举项 | 值 | 注释基线 |
|---|---|---|
| `eIdle` | 0 | 空闲：从轴不受本块控制，输出指令清零 |
| `eSynchronizing` | 10 | 啮合过渡：从轴速度向目标比值速度斜坡逼近 |
| `eInGear` | 20 | 已啮合：主从速度比稳定保持（`bInGear` 唯一来源） |
| `eDisengaging` | 30 | 脱开：按 `fDec` 受控降速至零 |
| `eFault` | 99 | 故障锁存：仅 `bReset` 上升沿可退出 |

**引脚表**：

| 引脚 | 类型 | 方向 | 默认 | 注释基线 |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | FALSE | 耦合总使能（Coupling enable），FALSE=脱开并清零输出；电平语义 |
| `bExecute` | BOOL | IN | FALSE | 建立耦合指令（Engage command），上升沿受理；`eInGear` 期间忽略新沿 |
| `bDisengage` | BOOL | IN | FALSE | 脱开指令（Disengage command），上升沿受理，优先于 `bExecute` |
| `nRatioNum` | DINT | IN | 1 | 传动比分子（Gear ratio numerator）[-]，域 1..1000000；≤0 判参数非法 |
| `nRatioDen` | DINT | IN | 1 | 传动比分母（Gear ratio denominator）[-]，域 1..1000000；**=0 防除零故障** |
| `bContinuousUpdate` | BOOL | IN | FALSE | 运行中改比值使能（Continuous update），FALSE 时 `eInGear` 内改比值被拒并出信息码 |
| `fAcc` | REAL | IN | 500.0 | 啮合过渡加速度（Engage acceleration）[mm/s²]，域 0.1..100000，非有限值→默认 |
| `fDec` | REAL | IN | 500.0 | 脱开减速度（Disengage deceleration）[mm/s²]，同上 |
| `fVelLimit` | REAL | IN | 0.0 | 从轴速度绝对上限（Slave speed limit）[mm/s]，0=不限；>0 时对指令双向钳位 |
| `fPhaseGain` | REAL | IN | 0.0 | 相位修正增益（Phase correction gain）[1/s]，0=关闭相位补偿 |
| `fPhaseMax` | REAL | IN | 5.0 | 相位修正量上限（Phase correction limit）[mm/s]，只在使用相位补偿时有效 |
| `bReset` | BOOL | IN | FALSE | 复位故障（Fault reset），上升沿受理 |
| `bInGear` | BOOL | OUT | — | 已啮合标志（In gear），仅 `eInGear` 态为 TRUE |
| `bBusy` | BOOL | OUT | — | 执行中（Busy），`eSynchronizing` / `eInGear` / `eDisengaging` 为 TRUE |
| `bActive` | BOOL | OUT | — | 本块持有从轴控制权（Active），`eSynchronizing` / `eInGear` 为 TRUE |
| `bError` | BOOL | OUT | — | 故障锁存（Error），**仅故障级码置位**（R21），派生式 |
| `uErrorId` | UDINT | OUT | 0 | 故障码（Error code），`16#0004_xxxx`，0=无故障 |
| `fRatio` | REAL | OUT | 0.0 | 实际生效传动比（Effective ratio）[-] = `nRatioNum / nRatioDen` |
| `fSlaveSpeedCmd` | REAL | OUT | 0.0 | 下发给从轴的速度指令（Slave speed command）[mm/s]，带符号 |
| `fPhaseError` | REAL | OUT | 0.0 | 相位累计误差（Accumulated phase error）[mm]，= ∫(主速×比值 − 从速)dt |
| `iMaster` | `I_DL_MotionAxis` | IN_OUT | — | 主轴接口引用（Master axis），由调用方注入实例 |
| `iSlave` | `I_DL_MotionAxis` | IN_OUT | — | 从轴接口引用（Slave axis），由调用方注入实例 |

**功能语义（逐拍顺序，编码侧不得调整顺序）**：
1. 定时器/边沿无条件刷新 → 参数防御（非有限值回默认、`nRatioNum/nRatioDen ≤ 0` 判故障、`fAcc/fDec ≤ 0` 回默认、`fVelLimit < 0` 取 ABS）→ 出口默认赋值。
2. `bDisengage` 沿优先：`eSynchronizing`/`eInGear` → `eDisengaging`。
3. 主状态机 `CASE eState OF ... ELSE` 兜底。
4. `eSynchronizing`：目标速度 = 主速 × 比值（+相位项），从轴速度指令按 `fAcc` 限斜率逼近目标；`|cmd − target| < fVelLimit` 或绝对值超差 < `DL_FLOAT_EPS×10` 时进入 `eInGear`。
5. `eInGear`：每拍重算目标（主速可实时变化）；**同拍至多一次** `iSlave.MoveVelocity(fVel := cmd, fAcc := fAcc)`，且仅在 `|cmd − 上次下发| > DL_GEAR_RESEND_EPS` 时下发（防每拍刷指令洪水）。
6. 相位补偿：`fPhaseError` 累计 = 主轴位移增量×比值 − 从轴位移增量；补偿量 = `fPhaseGain × fPhaseError`，钳到 ±`fPhaseMax`；`fPhaseGain = 0` 时补偿恒 0（关闭）。
7. `eDisengaging`：指令按 `fDec` 降到 0，`ABS(cmd) < DL_FLOAT_EPS` 时 `iSlave.Stop()` 一次并回 `eIdle`。

**边界与防错（逐条必须落地）**：
- `nRatioDen = 0` → 故障锁存 `0004_0250`【故障级】，回 `eIdle` 并清指令。
- `nRatioNum ≤ 0` 或 `nRatioDen < 0` → 同上码（比值非正无工程意义）。
- 主轴静止（`ABS(fMaster.fVelocity) < DL_FLOAT_EPS`）且从轴未静止 → 不报警，仅置信息码 `0130`（主静止、相位不可跟踪，属正常工况）；相位积累冻结。
- `eInGear` 中改比值且 `bContinuousUpdate = FALSE` → 拒绝（沿用旧比值）并置信息码 `0131`。
- 从轴指令被轴拒绝（`MoveVelocity` 返回 FALSE）→ 故障锁存 `0004_0251`【故障级】。
- 从轴 `iSlave.bError = TRUE` → 故障锁存 `0004_0252`【故障级】（透传，语义：从轴故障中断耦合）。
- `fVelLimit > 0` 且目标超限 → 钳位 + 信息码 `0132`（提示配方比值与限速矛盾，每拍重算，不置故障）。
- 主轴与从轴为同一实例（`iMaster` 与 `iSlave` 指向同一对象）**不可在块内检测**，头注释必须声明「调用方保证主从不指向同一实例，否则轴自身仲裁」，列为已知限制。

**故障码表**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0004_0130` | 信息级 | 主轴静止、相位跟踪冻结 |
| `0004_0131` | 信息级 | 未开放连续更新时改比值被拒 |
| `0004_0132` | 信息级 | 从轴速度指令被限速钳位 |
| `0004_0250` | 故障级 | 传动比参数非法（分母为 0 / 分子非正），锁存 |
| `0004_0251` | 故障级 | 从轴速度指令被拒，锁存 |
| `0004_0252` | 故障级 | 从轴故障中断耦合（透传），锁存 |
| `0004_0299` | 故障级 | 非法状态兜底（`CASE ELSE`，本块专用，勿与其他块共用） |

**验收向量**：V1 正常啮合（比值 1:2，主速 100 → 从速 200，过渡段斜率不超 `fAcc`）；V2 比值 3:7 分数比长期运行相位无漂移；V3 分母 0 → 故障锁存且指令清零；V4 `bContinuousUpdate=FALSE` 改比值被拒 + 信息码；V5 相位补偿开（`fPhaseGain=2`，人为注入 1 mm 相位差 → 补偿量 ≤ `fPhaseMax` 且误差收敛）；V6 脱开受控降速、`Stop` 单发一次；V7 从轴故障透传；V8 主轴静止时冻结不报故障。

---

### 1.2 `FB_DL_ElectronicCam`（功能块）｜DL_Motion｜来源标签 `plcopen-motion`｜RAW_NOTES S-2

**功能**：电子凸轮（MC_CamIn 语义 clean-room）。以「主轴相位归一化 → 分段线性表插值 → 缩放与偏移」链计算从轴目标位置，支持周期/非周期、相位偏移微调（飞剪切点补偿）、单调性校验与啮合过渡。

**随本块发布的枚举** `E_DL_CamState`：

| 枚举项 | 值 | 注释基线 |
|---|---|---|
| `eIdle` | 0 | 空闲：未建立耦合 |
| `eWaiting` | 10 | 等待起步条件：主轴方向不符或未达起步相位 |
| `eEngaging` | 20 | 啮合过渡：从轴按 `fVelLimit/fAcc` 趋近凸轮目标 |
| `eInSync` | 30 | 同步中：从轴每拍跟随凸轮目标（`bInSync` 唯一来源） |
| `eDisengaging` | 40 | 脱开：受控降速 |
| `eComplete` | 50 | 非周期模式走完表尾（`bEndOfProfile`），需新沿重启 |
| `eFault` | 99 | 故障锁存 |

**引脚表**：

| 引脚 | 类型 | 方向 | 默认 | 注释基线 |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | FALSE | 总使能，FALSE 立即脱开并清指令 |
| `bExecute` | BOOL | IN | FALSE | 建立凸轮耦合（Engage），上升沿受理；`eComplete`/`eIdle` 受理，其余态拒绝 |
| `bDisengage` | BOOL | IN | FALSE | 脱开（Disengage），上升沿受理，优先 |
| `bPeriodic` | BOOL | IN | TRUE | 周期模式（Periodic），TRUE=表尾回绕到表头（旋转刀/连续送料）；FALSE=单程到表尾置 `bEndOfProfile` |
| `bDirNegative` | BOOL | IN | FALSE | 期望主轴方向（Expected master direction），FALSE=正向，TRUE=负向；方向不符进 `eWaiting` 并出信息码 |
| `fMasterOffset` | REAL | IN | 0.0 | 主轴相位固定偏移（Master offset）[mm 或 deg，与轴单位一致]，配方级参数 |
| `fPhaseShift` | REAL | IN | 0.0 | 运行相位微调（Phase shift）[同 offset 单位]，飞剪切点在线补偿，与 offset 相加 |
| `fSlaveOffset` | REAL | IN | 0.0 | 从轴位置偏移（Slave offset）[mm]，叠加在表输出之上 |
| `fMasterScaling` | REAL | IN | 1.0 | 主轴缩放（Master scaling）[-]，域 0.001..100；≤0 或非有限值→默认 |
| `fSlaveScaling` | REAL | IN | 1.0 | 从轴缩放（Slave scaling）[-]，域 0.001..100 |
| `fVelLimit` | REAL | IN | 200.0 | 从轴速度上限（Slave velocity limit）[mm/s]，域 0.1..100000，用于 MoveAbsolute 的 fVel |
| `fAcc` | REAL | IN | 1000.0 | 从轴加速度（Slave acceleration）[mm/s²] |
| `fDec` | REAL | IN | 1000.0 | 从轴减速度（Slave deceleration）[mm/s²] |
| `nCamPoints` | UINT | IN | 2 | 凸轮表有效点数（Active cam points）[-]，域 2..`DL_CAM_MAX_POINTS`；<2 判参数非法 |
| `bReset` | BOOL | IN | FALSE | 复位故障，上升沿 |
| `bInSync` | BOOL | OUT | — | 同步中（In sync），仅 `eInSync` 为 TRUE |
| `bBusy` | BOOL | OUT | — | `eWaiting`/`eEngaging`/`eInSync`/`eDisengaging` 为 TRUE |
| `bEndOfProfile` | BOOL | OUT | — | 非周期模式走完表尾（End of profile），保持到下次受理 |
| `bError` | BOOL | OUT | — | 故障锁存（仅故障级码） |
| `uErrorId` | UDINT | OUT | 0 | 故障码 `16#0004_xxxx` |
| `fMasterPhase` | REAL | OUT | 0.0 | 归一化主轴相位（Normalized master phase）[-]，0.0..1.0，HMI 用 |
| `fSlavePosCmd` | REAL | OUT | 0.0 | 从轴目标位置指令（Slave position command）[mm] |
| `fCamSlaveTarget` | REAL | OUT | 0.0 | 表插值原始输出（Raw cam output）[mm]，未加偏移，调试用 |
| `iMaster` | `I_DL_MotionAxis` | IN_OUT | — | 主轴接口引用 |
| `iSlave` | `I_DL_MotionAxis` | IN_OUT | — | 从轴接口引用 |
| `afCamMaster` | `ARRAY[0..DL_CAM_MAX_POINTS-1] OF REAL` | IN_OUT | — | 凸轮表主轴点（Cam master points）[mm]，**必须单调递增**（周期模式允许末点回绕） |
| `afCamSlave` | `ARRAY[0..DL_CAM_MAX_POINTS-1] OF REAL` | IN_OUT | — | 凸轮表从轴点（Cam slave points）[mm]，与主轴点一一对应 |
| `fCamMasterPeriod` | REAL | IN_OUT | 0.0 | 周期长度（Master period）[mm]，仅 `bPeriodic=TRUE` 有效；≤0 判参数非法（周期模式） |

**功能语义**：
1. 归一化：`phaseRaw = (iMaster.fPosition + fMasterOffset + fPhaseShift) / fCamMasterPeriod`（周期模式）或 `(pos + offset + shift − fMasterPoint0)`（非周期模式）；`fMasterPhase` = `phaseRaw` 的小数部分（`phaseRaw − FLOOR(phaseRaw)`，**用条件加减实现，禁负数取余**）。
2. 表内展宽主轴值：`masterKey = fSlaveScaling` 不参与，主轴键 = `fMasterPhase × (afCamMaster[nCamPoints-1] − afCamMaster[0]) + afCamMaster[0]`（周期模式）；非周期模式主轴键 = 现值钳到 `[afCamMaster[0], afCamMaster[nCamPoints−1]]`。
3. 分段线性插值：二分或线性扫描查找区间（**必须带 `nGuard` 防死锁**），斜率 = `(S[i+1]−S[i])/(M[i+1]−M[i])`，除零防护后求值；输出 `fCamSlaveTarget`。
4. 从轴目标：`fSlavePosCmd = fSlaveScaling × fCamSlaveTarget + fSlaveOffset`。
5. `eWaiting`：主轴方向与 `bDirNegative` 不符，或非周期模式下主轴未进入表首区（`< afCamMaster[0]`）→ 停留等待（信息码 `0140`，不报警）。
6. `eEngaging`：从轴相对目标位置差 > `DL_CAM_ENGAGE_BAND` 时用 `MoveAbsolute(fPos := target, fVel := fVelLimit, fAcc := fAcc)` 追赶（每拍至多一次），入带后进 `eInSync`。
7. `eInSync`：每拍一次 `MoveAbsolute`；周期模式下相位回绕是天然行为（目标连续跨越），非周期模式下到达末点 → `eComplete` + `bEndOfProfile`。
8. `eDisengaging`：`MoveVelocity(0, fDec)` 一次 → `ABS(iSlave.fVelocity) < DL_FLOAT_EPS` 时 `Stop()` 一次 → `eIdle`。

**边界与防错**：
- `nCamPoints < 2` 或 `> DL_CAM_MAX_POINTS` → 故障 `0004_0260`【故障级】。
- 表单调性校验：`afCamMaster[i+1] ≤ afCamMaster[i]` 任一成立 → 故障 `0004_0261`【故障级】（**启动时全表扫一遍**，运行中只校验当前区间，避免每拍全扫）。
- 周期模式 `fCamMasterPeriod ≤ 0` 或非有限值 → 故障 `0004_0262`【故障级】。
- 表值非有限值（任一参与运算的节点）→ 故障 `0004_0263`【故障级】。
- `fMasterScaling`/`fSlaveScaling` 近零 → 回默认 1.0 + 信息码 `0141`（每拍重算）。
- 从轴指令被拒 → 故障 `0004_0264`【故障级】；从轴故障 → 故障 `0004_0265`【故障级】。
- 相位微调量 `fPhaseShift` 突变（`|Δ| > DL_CAM_PHASE_JUMP`）→ 不报故障，置信息码 `0142`（提示切点补偿步进过大，可能造成从轴速度冲击），并在注释说明「平滑由调用方斜坡化」。
- 相位偏移绝对值超 `fCamMasterPeriod` → 按周期取模（条件加减），不报错。
- **禁止**在 `eWaiting`/`eEngaging` 期间调用 `iSlave.Stop()`，否则会与追赶指令打架。

**故障码表**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0004_0140` | 信息级 | 主轴方向不符 / 未进表首区，等待中 |
| `0004_0141` | 信息级 | 缩放系数非法回默认 |
| `0004_0142` | 信息级 | 相位微调突变超限提示 |
| `0004_0260` | 故障级 | 凸轮点数非法，锁存 |
| `0004_0261` | 故障级 | 凸轮表主轴点非单调递增，锁存 |
| `0004_0262` | 故障级 | 周期长度非法（周期模式），锁存 |
| `0004_0263` | 故障级 | 凸轮表含非有限值，锁存 |
| `0004_0264` | 故障级 | 从轴定位指令被拒，锁存 |
| `0004_0265` | 故障级 | 从轴故障中断耦合（透传），锁存 |
| `0004_0298` | 故障级 | 非法状态兜底（本块专用） |

**验收向量**：V1 简单 3 点表（0/0、180/90、360/0）周期运行，从轴位置连续无跳变；V2 非周期到末点 → `eComplete` + `bEndOfProfile`；V3 主轴点等值（非单调）→ 故障 0261；V4 `nCamPoints=1` → 故障 0260；V5 反向主轴 + `bDirNegative=TRUE` 正常，FALSE 时等待 + 信息码；V6 `fPhaseShift` 步进 5 mm → 切点前移且出信息码 0142；V7 缩放 0 → 回默认 + 0141；V8 空表值含 NaN → 故障 0263。

---

### 1.3 `FB_DL_GantrySyncAxis`（功能块）｜DL_Motion｜来源标签 `plcopen-motion` / `s7-motion`｜RAW_NOTES S-3

**功能**：双驱龙门同步与偏斜保护。主轴（主动侧）与从轴（从动侧）1:1 速度耦合，实时监视主从位置偏差；两级阈值（预警/故障）分别触发降速与双轴停止；可选比例纠偏（滞后侧加速、超前侧减速）；任一轴故障同拍双轴停。

**随本块发布的枚举** `E_DL_GantryState`：

| 枚举项 | 值 | 注释基线 |
|---|---|---|
| `eIdle` | 0 | 空闲：未耦合，输出全清 |
| `eCoupling` | 10 | 耦合建立：双轴同速慢速趋同 |
| `eRun` | 20 | 运行：1:1 跟随 + 偏差监视 |
| `eCorrecting` | 30 | 纠偏中：偏差超预警且纠偏使能 |
| `eStopping` | 40 | 双轴停止中：偏差超故障阈或任一轴故障 |
| `eFault` | 99 | 故障锁存 |

**引脚表**：

| 引脚 | 类型 | 方向 | 默认 | 注释基线 |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | FALSE | 总使能，FALSE=停止并清指令 |
| `bReset` | BOOL | IN | FALSE | 复位故障（须偏差已回到预警阈内才真正复位），上升沿 |
| `fDevTolWarn` | REAL | IN | 0.5 | 偏差预警阈（Deviation warn tolerance）[mm]，域 0.001..50；**必须 < `fDevTolFault`**，否则自动对调 + 信息码 |
| `fDevTolFault` | REAL | IN | 2.0 | 偏差故障阈（Deviation fault tolerance）[mm]，域 0.01..100 |
| `tDevDelay` | TIME | IN | T#50MS | 偏差确认延时（Deviation confirm delay），超阈须持续此时间才动作（抗单拍毛刺） |
| `bCorrectEnable` | BOOL | IN | TRUE | 纠偏使能（Correction enable），FALSE=只监视不纠偏 |
| `fCorrGain` | REAL | IN | 2.0 | 纠偏比例增益（Correction gain）[1/s]，域 0..50；0=纠偏关闭 |
| `fCorrSpeedMax` | REAL | IN | 20.0 | 纠偏速度修正上限（Correction speed limit）[mm/s]，域 0.1..500 |
| `fCoupleSpeed` | REAL | IN | 10.0 | 耦合建立慢速（Coupling speed）[mm/s]，域 0.1..1000，双轴以此速度趋同 |
| `fAcc` | REAL | IN | 500.0 | 加/减速度（Acceleration）[mm/s²] |
| `bInSync` | BOOL | OUT | — | 同步中（In sync），`eRun`/`eCorrecting` 且偏差 ≤ 预警阈 |
| `fDeviation` | REAL | OUT | 0.0 | 实时偏差（Deviation）[mm] = 主轴位置 − 从轴位置，带符号 |
| `bDevWarn` | BOOL | OUT | — | 偏差预警（Deviation warning），延时确认后置位，回差内自动清（瞬态型） |
| `bFault` | BOOL | OUT | — | 故障锁存（仅故障级码） |
| `uErrorId` | UDINT | OUT | 0 | 故障码 `16#0004_xxxx` |
| `bStopBothCmd` | BOOL | OUT | — | 双轴停止请求（Stop both request），供上层安全链与 HMI 监视 |
| `fCorrSpeedCmd` | REAL | OUT | 0.0 | 纠偏速度修正量（Correction speed）[mm/s]，带符号，叠加到从轴指令 |
| `iMasterAxis` | `I_DL_MotionAxis` | IN_OUT | — | 主动侧轴引用（驱动侧） |
| `iSlaveAxis` | `I_DL_MotionAxis` | IN_OUT | — | 从动侧轴引用（跟随侧） |

**功能语义**：
1. 偏差 = `iMasterAxis.fPosition − iSlaveAxis.fPosition`（带符号，取 `ABS` 做阈值比较，保留符号供方向判断）。
2. `eCoupling`：从轴按 `fCoupleSpeed` 跟随主速（`MoveVelocity` 一次/拍），当 `|主速 − 从速| < DL_FLOAT_EPS×10` 且偏差 ≤ 预警阈 → `eRun`。
3. `eRun`：每拍 `MoveVelocity(masterVel + corr, fAcc)`，`corr` 为 0（`bCorrectEnable=FALSE` 或 `fCorrGain=0`）。
4. `eCorrecting`：偏差超预警阈且纠偏使能 → `corr = LIMIT(fCorrGain × fDeviation, ±fCorrSpeedMax)`（**方向：偏差为正即主轴在前 → 从轴加速追**）。偏差回到预警阈 80% 以内（回差）→ 回 `eRun`。
5. `eStopping`：偏差故障阈超时确认，或任一轴 `bError` → 同拍对**两轴各发一次** `Stop()`，`bStopBothCmd := TRUE`；两轴速度均 < `DL_FLOAT_EPS` 后进 `eFault`（锁存）。
6. `bFault` 复位路径：`bReset` 沿 + `ABS(fDeviation) ≤ fDevTolWarn` → 清码回 `eIdle`；偏差未回位则拒绝复位并置信息码 `0150`（人工须先手动消除机械偏差）。

**边界与防错**：
- `fDevTolWarn ≥ fDevTolFault` → **自动对调**并置信息码 `0151`（沿用库内 AnalogValve 对调自修复先例；对调后须重算，不得静默）。
- 任一阈值 ≤0 或非有限值 → 故障 `0004_0270`【故障级】。
- `tDevDelay = T#0S` → 按单拍确认（允许，但注释须警告毛刺风险）。
- `fCorrSpeedMax ≤ 0` → 回默认 20.0 + 信息码 `0152`。
- 纠偏长期饱和（`|corr| ≥ fCorrSpeedMax×0.98` 持续超 `tCorrSatLimit`（常量 T#3S））→ 故障 `0004_0271`【故障级】（语义：机械卡滞或增益不足，继续纠偏无意义）。
- 单轴 `bError` → 不等待偏差阈值，直接 `eStopping`（不对称风险优先，S-3 提取点③）。
- 两轴位置任一非有限值 → 故障 `0004_0272`【故障级】，立即双停。
- 本块**不做**安全认证声明：头注释按公约 0.13 写「逻辑层同步监视，机械与人身保护由硬件限位与安全回路承担」。

**故障码表**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0004_0150` | 信息级 | 偏差未回预警阈内，复位被拒 |
| `0004_0151` | 信息级 | 预警/故障阈值对调自修复 |
| `0004_0152` | 信息级 | 纠偏速度上限非法回默认 |
| `0004_0270` | 故障级 | 偏差阈值非法（≤0 / 非有限值），锁存 |
| `0004_0271` | 故障级 | 纠偏长时间饱和（疑似卡滞），锁存 |
| `0004_0272` | 故障级 | 轴位置信号非有限值，锁存 |
| `0004_0273` | 故障级 | 偏差超故障阈（双轴停止），锁存 |
| `0004_0274` | 故障级 | 单轴故障（双轴停止，透传），锁存 |
| `0004_0297` | 故障级 | 非法状态兜底（本块专用） |

**验收向量**：V1 正常耦合 → `eRun`，`bInSync=TRUE`；V2 人为注入 1 mm 偏差 → 纠偏收敛、`fCorrSpeedCmd` ≤ 上限；V3 偏差 3 mm（> 故障阈 2 mm）持续 60 ms → 双轴停 + 锁存 0273；V4 单轴 `bError` → 同拍双停 0274；V5 阈值对调输入（warn 5 / fault 1）→ 自动对调 + 0151；V6 纠偏饱和 3 s → 0271；V7 偏差未回位时 `bReset` → 拒绝 + 0150；V8 位置 NaN → 0272 并双停。

---

### 1.4 `FB_DL_TorqueLimitControl`（功能块）｜DL_Motion｜来源标签 `plcopen-motion` / `s7-motion`｜RAW_NOTES S-4

**功能**：力矩限制压装判定（Travel-to-fixed-stop 语义 clean-room）。接近 → 慢速压装 → 力矩达限判定到位 → 保持计时 → 位移窗口合格判定 → 释放归位；区分「设备异常（未达限超时 / 信号无效）」与「工件不合格（到位但位移超窗）」。**本块只做判定与流程编排，力矩限幅本身由驱动器参数承担**（头注释必写，S-4 提取点④）。

**随本块发布的枚举** `E_DL_PressState`：

| 枚举项 | 值 | 注释基线 |
|---|---|---|
| `eIdle` | 0 | 空闲：未启动，输出清零 |
| `eApproach` | 10 | 接近：以 `fApproachVel` 走向压装起点 |
| `ePress` | 20 | 压装：以 `fPressVel` 慢速压入，等力矩达限 |
| `eClamp` | 30 | 达限保持：力矩达限后保持 `tClampTime`（应力松弛） |
| `eRelease` | 40 | 释放：退回安全位 |
| `eDone` | 50 | 完成：`bJudgeOk` / `bJudgeNg` 有效，等新启动沿 |
| `eFault` | 99 | 故障锁存 |

**引脚表**：

| 引脚 | 类型 | 方向 | 默认 | 注释基线 |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | FALSE | 总使能，FALSE=中止并清输出 |
| `bStart` | BOOL | IN | FALSE | 启动压装周期（Start），上升沿受理（`eIdle`/`eDone` 受理） |
| `bAbort` | BOOL | IN | FALSE | 中止（Abort），电平最高优先，立即释放退回 |
| `bReset` | BOOL | IN | FALSE | 复位故障与判定结果，上升沿 |
| `fPressStartPos` | REAL | IN | 0.0 | 压装起点位置（Press start position）[mm]，接近段目标 |
| `fPressEndPos` | REAL | IN | 0.0 | 压装终点位置（Press end position）[mm]，**必须 > 起点**（方向由调用方按轴坐标系给出），否则故障 |
| `fPosWindowLow` | REAL | IN | 0.0 | 到位位移窗下限（Position window low）[mm] |
| `fPosWindowHigh` | REAL | IN | 0.0 | 到位位移窗上限（Position window high）[mm]；`low ≥ high` → 对调自修复 + 信息码 |
| `fTorqueLimit` | REAL | IN | 30.0 | 达限判定力矩（Torque limit）[% 额定]，域 1..150；>100 置信息码（超额定，机械风险提示） |
| `fApproachVel` | REAL | IN | 50.0 | 接近速度（Approach velocity）[mm/s]，域 0.1..1000 |
| `fPressVel` | REAL | IN | 5.0 | 压装速度（Press velocity）[mm/s]，域 0.1..100，建议 ≤ 接近速度 1/10（现场经验） |
| `fAcc` | REAL | IN | 200.0 | 加/减速度（Acceleration）[mm/s²] |
| `tClampTime` | TIME | IN | T#300MS | 达限保持时间（Clamp hold time），域 T#0S..T#10S |
| `tPressTimeout` | TIME | IN | T#10S | 压装超时（Press timeout），域 T#100MS..T#60S |
| `tReleaseTimeout` | TIME | IN | T#5S | 释放超时（Release timeout） |
| `fActTorque` | REAL | IN | 0.0 | 实际力矩（Actual torque）[% 额定]，由驱动适配层注入（本库接口无扭矩域） |
| `bTorqueLimitActive` | BOOL | IN | FALSE | 驱动器力矩限制已激活反馈（Drive in limitation），由适配层注入 |
| `bInClampFeedback` | BOOL | IN | FALSE | 驱动器「到达固定挡块」状态反馈（Fixed stop reached），可选 |
| `bJudgeOk` | BOOL | OUT | — | 判定合格（Judge OK），`eDone` 内保持 |
| `bJudgeNg` | BOOL | OUT | — | 判定不合格（Judge NG），`eDone` 内保持；**与 `bJudgeOk` 互斥，NG 优先** |
| `bInClamp` | BOOL | OUT | — | 已达限压紧（In clamp），`eClamp` 为 TRUE |
| `bBusy` | BOOL | OUT | — | 周期执行中 |
| `bDone` | BOOL | OUT | — | 周期结束单拍脉冲（进入 `eDone` 那一拍） |
| `fPosAtClamp` | REAL | OUT | 0.0 | 达限瞬间位置（Position at clamp）[mm]，锁存 |
| `fTorqueAtClamp` | REAL | OUT | 0.0 | 达限瞬间力矩（Torque at clamp）[%]，锁存 |
| `bError` | BOOL | OUT | — | 故障锁存（仅故障级码） |
| `uErrorId` | UDINT | OUT | 0 | 故障码 `16#0004_xxxx` |
| `nCycleCount` | UDINT | OUT | 0 | 完成周期计数（Cycle counter），`eDone` 每进入一次 +1 |
| `iAxis` | `I_DL_MotionAxis` | IN_OUT | — | 压装轴接口引用 |

**功能语义**：
1. `eApproach`：`MoveAbsolute(fPressStartPos, fApproachVel, fAcc)`（每拍一次）；`|fPos − fPressStartPos| ≤ DL_PRESS_POS_BAND（0.05 mm 常量）` → `ePress`。
2. `ePress`：`MoveAbsolute(fPressEndPos, fPressVel, fAcc)`（每拍一次）；达限判据 = `bTorqueLimitActive` **或** `fActTorque ≥ fTorqueLimit` **或** `bInClampFeedback`（三者任一，OR 语义，注释写清三源等价）；达限时锁存 `fPosAtClamp` / `fTorqueAtClamp` → `eClamp`。
3. `eClamp`：`MoveVelocity(0, fAcc)` 保位（每拍一次）；`tClampTime` 到期 → 位移窗判定 → `eRelease`（判定结果在两处都算：`eClamp` 结束时算出并锁存，`eDone` 内保持）。
4. 位移窗判定：`fPosAtClamp` 落在 `[fPosWindowLow, fPosWindowHigh]` 内 → OK；否则 NG（越界方向写入 `uErrorId` 为信息码，便于区分「压深了」/「没压到」）。
5. `eRelease`：`MoveAbsolute(fPressStartPos − DL_PRESS_RETRACT（常量 5.0 mm）… ` 实际改为 `fReleasePos` 引脚？**规格定：释放目标取 `fPressStartPos`（回压装起点），本块不引入额外引脚**；到位或 `tReleaseTimeout` 到期 → `eDone`（超时置故障 `0281`，不静默）。
6. `eDone`：输出判定保持，`bDone` 单拍；等 `bStart` 新沿或 `bReset`。

**边界与防错**：
- `fPressEndPos ≤ fPressStartPos` → 故障 `0004_0280`【故障级】（方向组态错误，S-4 现场高发）。
- `fPosWindowLow ≥ fPosWindowHigh` → 对调自修复 + 信息码 `0160`（继续运行）。
- `fTorqueLimit > 100` → 信息码 `0161`（超额定力矩，机械风险提示），仍按值执行。
- `fApproachVel ≤ 0` / `fPressVel ≤ 0` / `fPressVel > fApproachVel` → 后者仅信息码 `0162`（压装快于接近，工艺反常但非致命）。
- 压装段超 `tPressTimeout` 未达限 → 故障 `0004_0282`【故障级】（工件过软/未到位/信号失效）。
- `fActTorque` 非有限值 → 故障 `0004_0283`【故障级】（信号无效，判定不可信）。
- `bAbort` → 任意态立即 `Stop()` 一次 → `eIdle`，判定输出清（不置 NG，避免误判工件）。
- `bJudgeOk` 与 `bJudgeNg` 同真防护：判定分支内**先清两者再置一**，出口断言 `bJudgeOk AND bJudgeNg` 为假（注释写明 NG 优先）。
- 头注释必须声明：**「软件力矩限制不是安全功能；机械限位与安全回路仍是最终边界」**（S-4 提取点④）。

**故障码表**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0004_0160` | 信息级 | 位移窗上下限对调自修复 |
| `0004_0161` | 信息级 | 达限力矩超额定 |
| `0004_0162` | 信息级 | 压装速度高于接近速度（工艺反常） |
| `0004_0163` | 信息级 | 到位但位移低于窗下限（压浅，NG 方向提示） |
| `0004_0164` | 信息级 | 到位但位移高于窗上限（压深，NG 方向提示） |
| `0004_0280` | 故障级 | 压装终点 ≤ 起点（方向组态错误），锁存 |
| `0004_0281` | 故障级 | 释放超时，锁存 |
| `0004_0282` | 故障级 | 压装超时未达限，锁存 |
| `0004_0283` | 故障级 | 力矩信号非有限值，锁存 |
| `0004_0284` | 故障级 | 轴指令被拒 / 轴故障，锁存 |
| `0004_0296` | 故障级 | 非法状态兜底（本块专用） |

**验收向量**：V1 正常压装（限位 20.5 mm，窗 20.0~21.0）→ OK；V2 压到 19.5 → NG + 0163；V3 压到 21.5 → NG + 0164；V4 达限超时 10 s → 0282；V5 终点 ≤ 起点 → 0280；V6 位移窗对调 → 0160 且仍能判定；V7 `bAbort` 中途 → 立即退回且不置 NG；V8 `fActTorque=NaN` → 0283。

---

### 1.5 `FB_DL_MarkPositionLatch`（功能块）｜DL_Motion｜来源标签 `plcopen-motion` / `registration-mark`｜RAW_NOTES S-2（相位补偿前置件）/ S-14（节拍链）

**功能**：外部标记（色标 / 探针 / 光电）触发瞬间锁存轴位置与速度，输出与上次锁存的增量，供定长切割、切点相位校正、定长计米使用；带布防窗、缺失标记超时诊断、最近 N 次历史环形缓冲。**事件型，免首扫（R23）**。

**随本块发布的枚举** `E_DL_MarkState`：

| 枚举项 | 值 | 注释基线 |
|---|---|---|
| `eIdle` | 0 | 空闲：未布防，忽略触发 |
| `eArmed` | 10 | 已布防：等待标记沿 |
| `eLatched` | 20 | 已锁存：本周期结果有效，等应答/新布防 |
| `eMissed` | 30 | 标记缺失：布防窗内无沿（诊断态，非故障） |
| `eFault` | 99 | 故障锁存 |

**引脚表**：

| 引脚 | 类型 | 方向 | 默认 | 注释基线 |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | FALSE | 使能（Enable），FALSE=清布防与结果，不影响历史缓冲 |
| `bArm` | BOOL | IN | FALSE | 布防（Arm），上升沿进入 `eArmed`；`eLatched`/`eMissed` 下再次上升沿即重新布防 |
| `bTrigger` | BOOL | IN | FALSE | 标记输入（Mark input），上升沿为有效标记 |
| `tArmWindow` | TIME | IN | T#10S | 布防有效窗（Arm window），超时未触发 → `eMissed`；T#0S=不限 |
| `bClearHistory` | BOOL | IN | FALSE | 清历史缓冲（Clear history），上升沿 |
| `bReset` | BOOL | IN | FALSE | 复位故障 / 退出 `eMissed`，上升沿 |
| `nHistoryDepth` | UINT | IN | 4 | 历史深度（History depth）[-]，域 1..8，超域钳位 + 信息码 |
| `bLatched` | BOOL | OUT | — | 已锁存（Latched），`eLatched` 为 TRUE |
| `fLatchedPos` | REAL | OUT | 0.0 | 锁存位置（Latched position）[mm] |
| `fLatchedSpeed` | REAL | OUT | 0.0 | 锁存瞬间速度（Latched velocity）[mm/s] |
| `fDeltaPos` | REAL | OUT | 0.0 | 与上次锁存的位置增量（Delta position）[mm]，无上次时为 0 |
| `bMarkMissed` | BOOL | OUT | — | 标记缺失（Mark missed），`eMissed` 为 TRUE；瞬态型，重新布防后清 |
| `uMarkCount` | UDINT | OUT | 0 | 累计有效标记数（Mark counter），`bClearHistory` 不清此计数 |
| `afHistoryPos` | `ARRAY[0..DL_MARK_HIST_MAX-1] OF REAL` | OUT | — | 最近 N 次锁存位置（History positions）[mm]，索引 0=最新 |
| `bError` | BOOL | OUT | — | 故障锁存（仅故障级码） |
| `uErrorId` | UDINT | OUT | 0 | 故障码 `16#0004_xxxx` |
| `iAxis` | `I_DL_MotionAxis` | IN_OUT | — | 被采样轴接口引用 |

**功能语义**：
1. 边沿刷新：`_fbTrigArm(bArm)`、`_fbTrigTrig(bTrigger)`、`_fbTrigClr(bClearHistory)`、`_fbTrigReset(bReset)` 全部在主体最前部无条件刷新。
2. `eArmed` + `_fbTrigTrig.Q` → 一次读 `iAxis.fPosition` / `iAxis.fVelocity` 锁存（**同一拍内各读一次，保证位置与速度同拍一致**），`fDeltaPos = fLatchedPos − _fLastPos`（首次锁存时 `_fLastPos` 取当前值且 `fDeltaPos := 0.0`），历史缓冲头插、`uMarkCount + 1` → `eLatched`。
3. `eArmed` + `tArmWindow` 到期 → `eMissed`（`bMarkMissed := TRUE`），不停机不故障。
4. 历史缓冲：定长 `DL_MARK_HIST_MAX = 8`，整体前移写法（**禁 `WHILE` 无界循环，用 `FOR` + 深度钳位**），`nHistoryDepth` 控制有效项数；`bClearHistory` 沿清零全部并置 `_bHistValid := FALSE`。
5. 非有限值（`fPosition` / `fVelocity`）→ 不锁存、进 `eFault` + `0004_0290`【故障级】。

**边界与防错**：
- `nHistoryDepth = 0` 或 `> DL_MARK_HIST_MAX` → 钳位到 `[1, DL_MARK_HIST_MAX]` + 信息码 `0170`（每拍重算）。
- `tArmWindow` 极短（< 2 × 典型扫描周期）→ 注释警告，本块不判（扫描周期不可知）。
- 标记连击（同一布防窗内多次触发）：只受理**第一沿**（`eLatched` 后不再受理，`eArmed` 由重新布防恢复）——注释写明这是「一次布防一次锁存」的语义，不做去抖（去抖交由上游 `FB_DL_SignalDebounce`）。
- `bTrigger` 电平持续为真不影响（只取沿）。
- 不得在本块内累计位置（不要另建积分），位置一律来自轴接口（避免双积分漂移）。

**故障码表**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0004_0170` | 信息级 | 历史深度越界钳位 |
| `0004_0171` | 信息级 | 布防窗内无标记（缺失提示，与 `bMarkMissed` 同源） |
| `0004_0290` | 故障级 | 轴位置/速度非有限值，锁存 |
| `0004_0295` | 故障级 | 非法状态兜底（本块专用） |

**验收向量**：V1 布防 → 触发 → 锁存位置与增量正确；V2 连续两次布防触发，`fDeltaPos` 等于两次位置差；V3 布防超窗 → `eMissed` + `bMarkMissed`；V4 重新布防清 `eMissed`；V5 `nHistoryDepth=0` → 钳位 1 + 0170；V6 `bClearHistory` 清历史但 `uMarkCount` 保留；V7 位置 NaN → 0290；V8 同窗连击只锁一次。

---

### 1.6 `FC_DL_CalcMoveTime`（函数）｜DL_Motion｜来源标签 `plcopen-motion` / `motion-kinematics`｜RAW_NOTES S-14

**功能**：梯形 / 三角速度曲线点到点定位的理论耗时估算，用于产线节拍仿真与「该段移动能否达到设定速度」的选型诊断。**纯函数，无状态、无 POU 内实例**。

**签名**：

```
FUNCTION FC_DL_CalcMoveTime : BOOL
```

返回值语义：`TRUE` = 参数合法且结果有效；`FALSE` = 参数非法（此时 `tMove := T#0S`、`bTriangular := FALSE`、`uErrorId` 出码），**调用方必须先判返回值再用 `tMove`**。

**引脚表**：

| 引脚 | 类型 | 方向 | 默认 | 注释基线 |
|---|---|---|---|---|
| `fDistance` | REAL | IN | 0.0 | 移动距离（Travel distance）[mm]，可负（取绝对值，符号不影响耗时）；0 时 `tMove = tSettle` |
| `fVelMax` | REAL | IN | 100.0 | 速度上限（Max velocity）[mm/s]，域 0.001..100000；≤0 / 非有限值 → 返回 FALSE |
| `fAcc` | REAL | IN | 500.0 | 加速度（Acceleration）[mm/s²]，域 0.001..1.0E6 |
| `fDec` | REAL | IN | 500.0 | 减速度（Deceleration）[mm/s²]，域 0.001..1.0E6 |
| `fVelStart` | REAL | IN | 0.0 | 起始速度（Start velocity）[mm/s]，带符号但仅用绝对值；接续定位时非零 |
| `tSettle` | TIME | IN | T#0S | 到位稳定延时（Settle time），直接计入总耗时（夹爪/整定开销） |
| `tMove` | TIME | OUT | T#0S | 总移动耗时（Total move time）[ms]，含 `tSettle` |
| `tAccPhase` | TIME | OUT | T#0S | 加速段耗时（Acceleration phase time）[ms] |
| `tCruisePhase` | TIME | OUT | T#0S | 匀速段耗时（Cruise phase time）[ms]；三角曲线时为 T#0S |
| `tDecPhase` | TIME | OUT | T#0S | 减速段耗时（Deceleration phase time）[ms] |
| `fVelPeak` | REAL | OUT | 0.0 | 实际峰值速度（Achieved peak velocity）[mm/s]；三角曲线时 < `fVelMax` |
| `bTriangular` | BOOL | OUT | FALSE | 三角退化标志（Triangular profile），TRUE=距离不足无法达到 `fVelMax`（选型警示） |
| `uErrorId` | UDINT | OUT | 0 | 参数错误码 `16#0004_xxxx`（本函数仅信息级语义，不置任何故障位） |

**计算契约（编码侧逐式实现，不得化简为近似）**：

设 `d = ABS(fDistance)`，`v0 = ABS(fVelStart)`，`a = fAcc`，`dec = fDec`，`vmax = fVelMax`。

1. 参数校验：`vmax ≤ DL_FLOAT_EPS`、`a ≤ DL_FLOAT_EPS`、`dec ≤ DL_FLOAT_EPS` 或任一非有限值 → `uErrorId := 16#0004_0180`，返回 FALSE。
2. 临界距离（能否达到 `vmax`）：`dCrit = (vmax² − v0²) / (2×a) + vmax² / (2×dec)`。
   - 若 `v0 > vmax`（起始速度超上限）：**先按纯减速处理**，`tAccPhase := T#0S`，`tCruisePhase := T#0S`，`tDecPhase := (v0 − 0)/dec` 的对应距离校验：若 `(v0²)/(2×dec) ≥ d` 则实际是「边减速边到点」：`vEnd = SQRT(v0² − 2×dec×d)`，`tMove = (v0 − vEnd)/dec + tSettle`，置信息码 `0183`。
3. 若 `d ≥ dCrit`（梯形）：
   - `tAcc = (vmax − v0)/a`；`dAcc = (vmax² − v0²)/(2a)`；`dDec = vmax²/(2·dec)`；`tDec = vmax/dec`；
   - `tCruise = (d − dAcc − dDec)/vmax`（**必须判 `tCruise ≥ 0`，否则按三角分支重算**）；
   - `fVelPeak := vmax`；`bTriangular := FALSE`。
4. 否则（三角）：
   - `fVelPeak := SQRT( (2·a·dec·d + dec·v0²) / (a + dec) )`（`a + dec > 0` 已由校验保证）；
   - `tAcc = (fVelPeak − v0)/a`（若 `fVelPeak < v0` 则 `tAcc := T#0S`）；`tDec = fVelPeak/dec`；
   - `bTriangular := TRUE`；`tCruisePhase := T#0S`。
5. `tMove := tAcc + tCruise + tDec + tSettle`，三段耗时分别以 `REAL_TO_TIME(x × 1000.0)` 输出（**注释写明换算：秒 → 毫秒**，并说明 `REAL_TO_TIME` 的舍入意图为「向下取整到毫秒」）。

**边界与防错**：
- 全部除法前先做分母近零判定（`a`、`dec`、`vmax`、`a+dec`）。
- `tCruise < 0` 的浮点残差（`d` 恰好等于 `dCrit`）→ 钳为 `T#0S` 并置信息码 `0181`（临界点提示）。
- `d = 0` → `tMove := tSettle`，`fVelPeak := v0`，`bTriangular := FALSE`，信息码 `0182`。
- 结果上限防护：`tMove` 超 `DL_CALC_TIME_MAX`（常量，`T#24H`）→ 钳位 + 信息码 `0184`（防参数错填导致 HMI 溢出）。
- **函数内禁止任何边沿/定时器实例**（函数不可持有状态）。

**错误码表（本函数仅信息级语义）**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0004_0180` | 信息级 | 参数非法（速度/加减速度近零或非有限值） |
| `0004_0181` | 信息级 | 临界距离浮点残差，匀速段钳零 |
| `0004_0182` | 信息级 | 距离为零，耗时等于稳定延时 |
| `0004_0183` | 信息级 | 起始速度超上限，按减速到点计算 |
| `0004_0184` | 信息级 | 结果超上限钳位 |

**验收向量**：V1 `d=100, vmax=30, a=dec=20` → `fVelPeak=30`、`bTriangular=FALSE`、`tAcc=T#1500MS`、`tDec=T#1500MS`、`tCruise=T#2500MS`（≈ 100−22.5=77.5 mm 匀速）；V2 `d=20` 同参数 → `bTriangular=TRUE`、`fVelPeak≈14.14`；V3 `v0=10, d=100` → 加速段缩短、峰速仍达 30；V4 `a=0` → 返回 FALSE + 0180；V5 `d=0` → `tMove=tSettle` + 0182；V6 `v0=50 > vmax=30` → 0183 且耗时为纯减速；V7 参数极大 → 0184 钳位。

---

## 第 2 节 泳道 B｜DL_Process 扩容 6 项

### 2.1 `FB_DL_ConveyorLineLink`（功能块）｜DL_Process｜来源标签 `smema` / `conveyor-handshake`｜RAW_NOTES S-7

**功能**：相邻机台 / 线体段之间的级联握手协调器（SMEMA 语义 clean-room）。把「上游有料（BA）」「下游可收（MR）」「强制抑制（INH）」三类干接点信号抽象为与供应商无关的状态机，内置消抖、传递看门狗、维护直通。**事件型，免首扫（R23）**。

**随本块发布的枚举** `E_DL_LineLinkState`：

| 枚举项 | 值 | 注释基线 |
|---|---|---|
| `eIdle` | 0 | 空闲：无料，等上游 BA |
| `eBoardReady` | 10 | 待放行：上游有料且本机可收，等下游 MR |
| `eTransferring` | 20 | 传递中：已握手，看门狗计时 |
| `eComplete` | 30 | 传递完成：料已离开本段，等复位 |
| `eInhibited` | 40 | 被抑制：下游 INH 有效，禁止启动传递 |
| `eJamFault` | 99 | 传递超时锁存（仅 `bReset` 清） |

**引脚表**：

| 引脚 | 类型 | 方向 | 默认 | 注释基线 |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | FALSE | 本链使能，FALSE=全部输出置安全侧（不放行、不请求） |
| `bUpBoardAvailable` | BOOL | IN | FALSE | 上游有料（Board available，上游→本机 BA 信号），电平语义 |
| `bDownMachineReady` | BOOL | IN | FALSE | 下游可接收（Machine ready，下游→本机 MR 信号），电平语义 |
| `bDownInhibit` | BOOL | IN | FALSE | 下游强制抑制（Inhibit，下游→本机 INH），TRUE=禁止放行 |
| `bBoardAtEntry` | BOOL | IN | FALSE | 本段入口光电（Entry photoeye），TRUE=料已进入本段 |
| `bBoardAtExit` | BOOL | IN | FALSE | 本段出口光电（Exit photoeye），TRUE=料仍在本段出口 |
| `bBoardQualityNg` | BOOL | IN | FALSE | 来料质量 NG 标志（Good/Bad board，可选），仅透传到输出供下游分选 |
| `bUpstreamRequest` | BOOL | IN | FALSE | 上游请求放料（Board requested，可选），与 BA 二选一接线 |
| `tDebounce` | TIME | IN | T#30MS | 输入消抖时间（Input debounce），域 T#0MS..T#1S；S-7 经验值 20~30 ms |
| `tTransferTimeout` | TIME | IN | T#5S | 传递看门狗（Transfer watchdog），域 T#100MS..T#60S；S-7 经验值 5 s |
| `bBypass` | BOOL | IN | FALSE | 维护直通（Maintenance bypass），TRUE=恒放行且不报卡料（须审计记录，头注释警告） |
| `bReset` | BOOL | IN | FALSE | 复位超时锁存，上升沿 |
| `bBoardAvailableOut` | BOOL | OUT | — | 向下游宣告有料（BA out），消抖后 `bUpBoardAvailable` 且本段已就绪 |
| `bMachineReadyOut` | BOOL | OUT | — | 向上游宣告可收（MR out），本段空且无故障且非抑制 |
| `bRequestBoard` | BOOL | OUT | — | 向上游请求送料（Request），本段空且下游可收 |
| `bInhibitUpstream` | BOOL | OUT | — | 抑制上游（INH out），本段故障 / 卡料 / 传递超时时为 TRUE |
| `bTransferring` | BOOL | OUT | — | 传递中（Transferring），`eTransferring` 为 TRUE |
| `bTransferDone` | BOOL | OUT | — | 传递完成单拍脉冲（Transfer done） |
| `bTransferTimeout` | BOOL | OUT | — | 传递超时（Timeout），`eJamFault` 保持期内为 TRUE |
| `bQualityNgOut` | BOOL | OUT | — | 质量 NG 透传（NG pass-through），保持下游可见 |
| `bFault` | BOOL | OUT | — | 故障标志（仅故障级码） |
| `uErrorId` | UDINT | OUT | 0 | 故障码 `16#0005_xxxx` |
| `nTransferCount` | UDINT | OUT | 0 | 累计传递次数（Transfer counter），`bTransferDone` 每拍 +1 |

**功能语义**：
1. 三路输入各配 `TON` 消抖（**实例在主体最前部无条件刷新**，`IN` 取原信号，`PT := tDebounce`；`Q` 为稳定值）；`tDebounce = T#0MS` 时直接取原信号（注释说明「零消抖」）。
2. 握手判据：`_bTransferStart = 上游有料（消抖后 BA 或 Request）AND 本段空（NOT bBoardAtEntry AND NOT bBoardAtExit）AND 下游可收（MR 消抖）AND NOT INH AND bEnable AND NOT 故障`。
3. `eTransferring`：看门狗 `TON` 计时（`PT := tTransferTimeout`）；料进入本段（`bBoardAtEntry` 上升沿）→ 视为受理，继续等料离开；料离开本段（`bBoardAtEntry` 与 `bBoardAtExit` 均落，即全清）→ `eComplete` + `bTransferDone` 单拍 + `nTransferCount + 1`；
4. 看门狗到期仍在 `eTransferring` → `eJamFault` 锁存 `0005_0230`【故障级】，`bInhibitUpstream := TRUE`。
5. `eInhibited`：`bDownInhibit` 有效时进入，输出不放行；抑制解除后回 `eIdle`（信息码 `0130`）。
6. `bBypass` 有效：强制 `bInhibitUpstream := FALSE` 且不判超时（信息码 `0131` 每拍重算，提示维护直通中）。
7. 同拍冲突（BA 与 Request 同真，或 MR 与 INH 同真）：**保守侧（不放行）**，置信息码 `0132`，不猜。

**边界与防错**：
- `tTransferTimeout < tDebounce×2` → 自动提升到 `tDebounce×2` + 信息码 `0133`（防消抖窗吃掉整个看门狗）。
- `bUpBoardAvailable` 与 `bUpstreamRequest` 同时接线且都恒 TRUE（接线错误）→ 不报故障，靠信息码 0132 暴露。
- 故障态下 `bMachineReadyOut` 必须 FALSE（禁止把坏料放进本段）。
- 出口断言（注释内写明并由 `IF` 保证）：`bMachineReadyOut` 与 `bInhibitUpstream` 不得同真。
- **与 `FB_DL_ConveyorZone` 的衔接**：本块 `bMachineReadyOut` 可直接接到下游区块的 `bDownstreamReady`，下游区块 `bZoneReady` 可接到本块 `bDownMachineReady`——注释给出接线示例（不引组件实例，避免耦合）。

**故障码表**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0005_0130` | 信息级 | 下游抑制解除，恢复放行 |
| `0005_0131` | 信息级 | 维护直通生效（每拍重算） |
| `0005_0132` | 信息级 | 握手信号同拍冲突（保守侧不放行） |
| `0005_0133` | 信息级 | 看门狗被提升至消抖窗两倍 |
| `0005_0230` | 故障级 | 传递超时（卡料），锁存 |
| `0005_0231` | 故障级 | 非法状态兜底（本块专用） |

**验收向量**：V1 完整握手（BA→MR→料进→料出）一次；V2 下游 INH 有效时不放行；V3 传递超时 → 锁存 0230 + INH 输出；V4 `bReset` 清锁存；V5 BA 与 Request 同真 → 不放行 + 0132；V6 `bBypass` 直通且不超时；V7 消抖：20 ms 毛刺被滤掉；V8 故障态 MR 输出恒 FALSE。

---

### 2.2 `FB_DL_RecipeManager`（功能块）｜DL_Process｜来源标签 `codesys-forge` / `recipe-management`｜RAW_NOTES S-6（**T1-4 CODESYS Forge 首次开组**）

**功能**：通用配方管理器。以「参数清单 + 值集 + 校验和」承载多品种配方；提供选择、校验、应用（写入运行参数）、写回（采集当前参数为新配方）、切换防呆（仅稳态允许）、变更审计（次数 + 时间戳注入）。**零文件 I/O、零全局耦合**——持久化由调用方自行完成（`VAR_IN_OUT` 数组可整体存取）。

**随本块发布的结构体与枚举**：

```
TYPE ST_DL_RecipeEntry :
STRUCT
    sName        : STRING[32];                                  // 配方名（Recipe name）
    bEnabled     : BOOL;                                        // 配方启用（Enabled）
    nParamCount  : UINT;                                        // 有效参数个数（Active param count）
    afValue      : ARRAY[0..DL_RECIPE_MAX_PARAM-1] OF REAL;     // 参数值集（Parameter values）
    uChecksum    : UDINT;                                       // 校验和（CRC32 或累加和，由调用方生成/校验）
END_STRUCT
END_TYPE
```

`E_DL_RecipeState`：`eIdle`(0) / `eValidating`(10) / `eApplying`(20) / `eVerifying`(30) / `eDone`(40) / `eFault`(99)。

**引脚表**：

| 引脚 | 类型 | 方向 | 默认 | 注释基线 |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | FALSE | 使能，FALSE=中止并保持当前运行参数不变 |
| `bLoad` | BOOL | IN | FALSE | 加载所选配方到运行参数（Load），上升沿受理 |
| `bSave` | BOOL | IN | FALSE | 把当前运行参数写回所选配方（Save/Teach），上升沿受理 |
| `bValidate` | BOOL | IN | FALSE | 仅校验不应用（Validate），上升沿受理，结果出 `bValid` |
| `bMachineStopped` | BOOL | IN | TRUE | 机台稳态确认（Machine stopped），FALSE 时拒绝加载（切换防呆） |
| `bReset` | BOOL | IN | FALSE | 复位故障，上升沿 |
| `nSelectRecipe` | UINT | IN | 0 | 选中配方号（Selected recipe index）[-]，域 0..`DL_RECIPE_MAX_COUNT-1` |
| `nParamCount` | UINT | IN | 1 | 本机参数个数（Param count）[-]，域 1..`DL_RECIPE_MAX_PARAM` |
| `afParamMin` | `ARRAY[0..DL_RECIPE_MAX_PARAM-1] OF REAL` | IN | — | 参数下限（Param lower limits），逐项与配方值比较 |
| `afParamMax` | `ARRAY[0..DL_RECIPE_MAX_PARAM-1] OF REAL` | IN | — | 参数上限（Param upper limits）；`min ≥ max` 视为该参数未启用校验（注释写明） |
| `tNow` | TIME | IN | T#0S | 时间戳注入（Timestamp injection）[ms]，禁止读 CPU 钟；用于审计记录 |
| `bLoaded` | BOOL | OUT | — | 加载完成（Loaded），`eDone` 且操作类型为 Load 时为 TRUE |
| `bSaved` | BOOL | OUT | — | 写回完成（Saved），`eDone` 且操作为 Save 时为 TRUE |
| `bValid` | BOOL | OUT | — | 校验通过（Valid），校验型操作结果，保持到下次操作 |
| `bParamOutOfRange` | BOOL | OUT | — | 存在越界参数（Out of range），瞬态型，每拍重算 |
| `nOutOfRangeIndex` | UINT | OUT | 0 | 首个越界参数索引（First bad index），`bParamOutOfRange` 时有效 |
| `nActiveRecipe` | UINT | OUT | 0 | 当前生效配方号（Active recipe） |
| `uActiveChecksum` | UDINT | OUT | 0 | 当前运行参数校验和（Active checksum），供上层比对 |
| `uChangeCount` | UDINT | OUT | 0 | 配方变更次数（Change counter），每次成功 Load/Save +1 |
| `tLastChange` | TIME | OUT | T#0S | 末次变更时间戳（Last change time），取注入的 `tNow` |
| `bBusy` | BOOL | OUT | — | 执行中 |
| `bDone` | BOOL | OUT | — | 操作完成单拍脉冲 |
| `bError` | BOOL | OUT | — | 故障锁存（仅故障级码） |
| `uErrorId` | UDINT | OUT | 0 | 故障码 `16#0005_xxxx` |
| `astRecipe` | `ARRAY[0..DL_RECIPE_MAX_COUNT-1] OF ST_DL_RecipeEntry` | IN_OUT | — | 配方库（Recipe library），由调用方持有与持久化 |
| `afParamActual` | `ARRAY[0..DL_RECIPE_MAX_PARAM-1] OF REAL` | IN_OUT | — | 当前运行参数（Live parameters），Save 时被读、Load 时被写 |

**功能语义**：
1. 校验（`eValidating`）：① `nSelectRecipe` 在域内；② `astRecipe[nSelectRecipe].bEnabled = TRUE`；③ `nParamCount` 与 `astRecipe[..].nParamCount` 一致（不一致 → 故障 `0005_0241`）；④ 逐参数：非有限值 → 拒绝（故障 `0005_0242`）；`afParamMin[i] < afParamMax[i]` 时判 `min ≤ v ≤ max`（越界记录首个索引，故障 `0005_0243`）；⑤ 校验和：`astRecipe[..].uChecksum ≠ 0` 时与重算值比对，不等 → 故障 `0005_0244`（配方损坏）；`= 0` 视为「未启用校验」（信息码 `0140`）。
2. 应用（`eApplying`）：**逐参数写入 `afParamActual`**（单拍全写，不逐拍增量，防半套参数生效）。
3. 复核（`eVerifying`）：回读 `afParamActual` 重算校验和，与目标比对；不等 → 故障 `0005_0245`（写入异常）。
4. 写回（Save）：把 `afParamActual` 拷入 `astRecipe[nSelectRecipe].afValue`，`nParamCount` 同步，`uChecksum` 置 0（**校验和必须由调用方重新生成**，本块不伪造校验和，头注释写明）。
5. 审计：成功 Load/Save 后 `uChangeCount + 1`、`tLastChange := tNow`。
6. 切换防呆：`bLoad` 且 `bMachineStopped = FALSE` → 拒绝，信息码 `0141`（**不置故障**，属正常联锁）。

**边界与防错**：
- `nSelectRecipe ≥ DL_RECIPE_MAX_COUNT` 或配方 `bEnabled = FALSE` → 故障 `0005_0240`【故障级】。
- 所有数组索引必须先判域再取值（防越界）。
- 同时来两个操作沿（Load 与 Save 同拍）→ 两操作都丢弃，信息码 `0142`（"不猜"原则）。
- `nParamCount > DL_RECIPE_MAX_PARAM` → 钳位 + 信息码 `0143`。
- 校验和算法固定为 **32 位累加异或**（`uSum := uSum XOR (uSum SHL 5 + REAL_TO_UDINT(v×1000))` 形式），注释写明「与上层持久化格式必须一致」；不得引用 `FC_DL_Crc32Ethernet`（避免跨子库依赖 Level 0 的循环依赖风险……**实际允许**：DL_Process 可依赖 Level 0，编码者可复用 `FC_DL_Crc32Ethernet`，二选一但必须在头注释写明选了哪个）。
- 非有限值参数不得写入 `afParamActual`（保持原值 + 故障）。

**故障码表**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0005_0140` | 信息级 | 配方未启用校验和（`uChecksum = 0`） |
| `0005_0141` | 信息级 | 机台非稳态，加载被拒 |
| `0005_0142` | 信息级 | Load/Save 同拍冲突，双丢弃 |
| `0005_0143` | 信息级 | 参数个数越界钳位 |
| `0005_0240` | 故障级 | 配方号越界 / 配方未启用，锁存 |
| `0005_0241` | 故障级 | 参数个数与配方定义不一致，锁存 |
| `0005_0242` | 故障级 | 配方参数含非有限值，锁存 |
| `0005_0243` | 故障级 | 参数越界（出 `nOutOfRangeIndex`），锁存 |
| `0005_0244` | 故障级 | 校验和不匹配（配方损坏），锁存 |
| `0005_0245` | 故障级 | 应用后复核失败（写入异常），锁存 |
| `0005_0246` | 故障级 | 非法状态兜底（本块专用） |

**验收向量**：V1 正常 Load（3 参数，域内）→ `bLoaded`、`uActiveChecksum` 正确；V2 参数越界 → 0243 + `nOutOfRangeIndex` 指向首个；V3 校验和错 → 0244；V4 `bMachineStopped=FALSE` 加载 → 拒绝 + 0141；V5 Save 后 `uChangeCount + 1` 且 `tLastChange` 等于注入 `tNow`；V6 Load+Save 同拍 → 双丢弃 + 0142；V7 参数含 NaN → 0242；V8 配方号越界 → 0240。

---

### 2.3 `FB_DL_LeakTestStation`（功能块）｜DL_Process｜来源标签 `leak-test` / `pressure-decay`｜RAW_NOTES S-8

**功能**：压降法气密检漏工站。夹具确认 → 充气 → 稳压 → 隔离测量 → 排气 → PASS/NG/Abort；内置温度补偿、大漏快判、设备异常与工件不良分离判定。

**随本块发布的枚举** `E_DL_LeakPhase`：

| 枚举项 | 值 | 注释基线 |
|---|---|---|
| `eIdle` | 0 | 空闲：等启动 |
| `eClampCheck` | 10 | 夹具确认：等夹具闭合信号 |
| `eFill` | 20 | 充气：充气阀开，至目标压力 |
| `eStabilize` | 30 | 稳压：隔离保温，等热平衡 |
| `eMeasure` | 40 | 测量：隔离测压降 |
| `eVent` | 50 | 排气：排气阀开，泄压到安全位 |
| `ePass` | 60 | 合格：结果保持，等复位/新周期 |
| `eFail` | 70 | 不合格：结果保持，等复位 |
| `eAbort` | 80 | 中止：操作员/上游中止，安全排气 |
| `eFault` | 99 | 设备故障锁存 |

**引脚表**：

| 引脚 | 类型 | 方向 | 默认 | 注释基线 |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | FALSE | 工站使能，FALSE=安全排气并清输出 |
| `bStart` | BOOL | IN | FALSE | 启动测试周期，上升沿（`eIdle`/`ePass`/`eFail` 受理） |
| `bAbort` | BOOL | IN | FALSE | 中止（Abort），电平最高优先 → 安全排气 |
| `bReset` | BOOL | IN | FALSE | 复位故障与结果，上升沿 |
| `bFixtureClosed` | BOOL | IN | FALSE | 夹具闭合确认（Fixture closed），FALSE 禁止充气（S-8 提取点⑤） |
| `bTempCompEnable` | BOOL | IN | TRUE | 温度补偿使能（Temp compensation），FALSE=按原始压降计算 |
| `fTestPressure` | REAL | IN | 300.0 | 目标测试压力（Test pressure）[kPa]，域 1..10000 |
| `fPressureTol` | REAL | IN | 5.0 | 稳压结束压力容差（Pressure tolerance）[kPa]，域 0.1..100；超容差判设备异常 |
| `fActPressure` | REAL | IN | 0.0 | 实际压力（Actual pressure）[kPa]，由变送器/适配层注入 |
| `fActTemp` | REAL | IN | 25.0 | 实际温度（Actual temperature）[℃]，温度补偿用 |
| `fRefTemp` | REAL | IN | 25.0 | 基准温度（Reference temperature）[℃]，补偿基准 |
| `fChamberVolume` | REAL | IN | 100.0 | 被测腔容积（Chamber volume）[mL]，泄漏率换算用 |
| `fLeakLimit` | REAL | IN | 10.0 | 泄漏率上限（Leak rate limit）[mL/min]，≤ 此值为 PASS |
| `fGrossLeakDrop` | REAL | IN | 20.0 | 大漏快判压降（Gross leak drop）[kPa]，测量窗内压降超此值立即 NG；0=禁用快判 |
| `tFill` | TIME | IN | T#3S | 充气时长（Fill time） |
| `tStabilize` | TIME | IN | T#5S | 稳压时长（Stabilize time），S-8：过短会既藏漏又造漏 |
| `tMeasure` | TIME | IN | T#10S | 测量时长（Measure time） |
| `tFillTimeout` | TIME | IN | T#20S | 充气超时（Fill timeout） |
| `tVentTimeout` | TIME | IN | T#10S | 排气超时（Vent timeout） |
| `bCmdFillValve` | BOOL | OUT | — | 充气阀指令（Fill valve） |
| `bCmdIsolateValve` | BOOL | OUT | — | 隔离阀指令（Isolate valve），测量期间为 TRUE（S-8：测量前必须隔离气源） |
| `bCmdVentValve` | BOOL | OUT | — | 排气阀指令（Vent valve） |
| `ePhase` | `E_DL_LeakPhase` | OUT | `eIdle` | 当前相位（Current phase） |
| `bBusy` | BOOL | OUT | — | 周期执行中 |
| `bDone` | BOOL | OUT | — | 周期结束单拍脉冲 |
| `bPass` | BOOL | OUT | — | 判定合格（PASS），`ePass` 内保持 |
| `bFail` | BOOL | OUT | — | 判定不合格（FAIL），`eFail` 内保持 |
| `fLeakRate` | REAL | OUT | 0.0 | 计算泄漏率（Leak rate）[mL/min]，已含温度补偿 |
| `fDeltaP` | REAL | OUT | 0.0 | 测量窗压降（Pressure drop）[kPa]，锁存 |
| `bError` | BOOL | OUT | — | 设备故障锁存（仅故障级码；**工件 NG 不置此位**） |
| `uErrorId` | UDINT | OUT | 0 | 故障码 `16#0005_xxxx` |
| `nPartCount` | UDINT | OUT | 0 | 测试件数（Part counter），每次判定 +1 |
| `nRejectCount` | UDINT | OUT | 0 | 不合格件数（Reject counter） |

**功能语义**：
1. `eClampCheck`：`bFixtureClosed` 为 TRUE → `eFill`（夹具未闭超 `tFillTimeout` → 故障 `0005_0250`）。
2. `eFill`：`bCmdFillValve := TRUE`；`fActPressure ≥ fTestPressure × (1 − DL_LEAK_FILL_TOL)`（常量 0.02）→ `eStabilize`；超 `tFillTimeout` 未达压 → 故障 `0005_0251`（设备/工件大漏，方向注释说明「大漏通常表现为充不上压」）。
3. `eStabilize`：关充气阀、开隔离阀，保持 `tStabilize`；结束时记录 `fP0 = fActPressure`、`fT0 = fActTemp`；若 `ABS(fP0 − fTestPressure) > fPressureTol` → 故障 `0005_0252`（**设备异常，不判工件 NG**，S-8 提取点⑥）。
4. `eMeasure`：`fP1 = fActPressure` 实时跟踪；`fDeltaP = fP0 − fP1`；大漏快判 `fGrossLeakDrop > 0 AND fDeltaP ≥ fGrossLeakDrop` → 立即 NG（`eFail`，信息码 `0153`）；`tMeasure` 到期 → 结算。
5. 泄漏率换算：`Q = fDeltaP × fChamberVolume / (tMeasure 秒数)`（单位自然导出为 kPa·mL/s）→ 乘 `DL_LEAK_UNIT_FACTOR`（常量 60.0）转 `mL/min` 量纲口径，**注释必须完整写出量纲推导与「该系数为工艺约定换算，非严格气体动力学」声明**。温度补偿（使能时）：`Q := Q × (273.15 + fRefTemp) / (273.15 + fT0)`（一阶理想气体近似，注释声明适用域）。
6. 判定：`Q ≤ fLeakLimit` → `ePass`，否则 `eFail`；`nPartCount + 1`，NG 时 `nRejectCount + 1`；`bDone` 单拍。
7. `eVent`（PASS/NG 后进入，或在 Abort 时直接进入）：`bCmdVentValve := TRUE`，`fActPressure < DL_LEAK_VENT_DONE`（常量 2.0 kPa）→ `eIdle`；超 `tVentTimeout` → 故障 `0005_0253`。
8. `bAbort` 任意态 → 立即关充气/隔离、开排气 → `eAbort` → 排气完成回 `eIdle`；判定输出清（不记 NG）。

**边界与防错**：
- 全部 REAL 输入非有限值 → 故障 `0005_0254`【故障级】（压力/温度/容积/阈值）。
- `fChamberVolume ≤ 0` → 故障 `0005_0255`（除零防护）。
- `fLeakLimit < 0` → 取 ABS + 信息码 `0150`；`tMeasure = T#0S` → 故障 `0005_0256`（无法测量）。
- 测量窗内压力上升（ΔP < 0，可能是温度回升）→ 按 0 处理并置信息码 `0151`（不判 NG）。
- `bPass` / `bFail` 出口断言互斥（先清后置）。
- 头注释必须声明：「本工站为**流程编排与判定层**，检漏仪精度与夹具密封属测量系统，不在本块职责内」。

**故障码表**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0005_0150` | 信息级 | 泄漏率上限为负，取绝对值 |
| `0005_0151` | 信息级 | 测量窗压力回升（ΔP<0），按 0 处理 |
| `0005_0152` | 信息级 | 温度补偿已关闭，按原始压降判定 |
| `0005_0153` | 信息级 | 大漏快判触发（提前判 NG） |
| `0005_0250` | 故障级 | 夹具闭合超时，锁存 |
| `0005_0251` | 故障级 | 充气超时未达压，锁存 |
| `0005_0252` | 故障级 | 稳压结束压力超容差（设备异常），锁存 |
| `0005_0253` | 故障级 | 排气超时，锁存 |
| `0005_0254` | 故障级 | 压力/温度/容积输入非有限值，锁存 |
| `0005_0255` | 故障级 | 腔容积非法（≤0），锁存 |
| `0005_0256` | 故障级 | 测量时长为零，锁存 |
| `0005_0257` | 故障级 | 非法状态兜底（本块专用） |

**验收向量**：V1 合格件（ΔP 对应 Q < 限值）→ PASS；V2 大漏件（充不上压）→ 0251；V3 测量窗 ΔP 超快判阈 → 立即 FAIL + 0153；V4 稳压结束压力超容差 → 0252 且不判 NG；V5 温度 35 ℃ 时补偿后 Q 下降（比值 298.15/308.15）；V6 `bAbort` 测量中 → 立即排气不记 NG；V7 `fChamberVolume=0` → 0255；V8 排气超时 → 0253。

---

### 2.4 `FB_DL_MixRecipeControl`（功能块）｜DL_Process｜来源标签 `isa-88-phase` / `mixing-process`｜RAW_NOTES S-9（LBP 实测）/ S-10（相语义）

**功能**：混合 / 搅拌工艺相控制（ISA-88 单相语义 clean-room）。投料就绪 → 搅拌（定速 / 正反交替）→ 终点判据（时间到 / 扭矩上升达标）→ 出料许可 → 停转；转速反馈监视、扭矩超限保护、出料超时诊断。

**随本块发布的枚举** `E_DL_MixPhase`：

| 枚举项 | 值 | 注释基线 |
|---|---|---|
| `eIdle` | 0 | 空闲：等启动 |
| `ePreCheck` | 10 | 前置确认：料已投、出料阀关、驱动就绪 |
| `eMixing` | 20 | 搅拌中（含交替子计时） |
| `eVerify` | 30 | 终点确认：稳速确认与结果锁存 |
| `eDischarge` | 40 | 出料中（等出料完成信号） |
| `eSpinDown` | 50 | 停转：减速到零 |
| `eDone` | 60 | 完成（OK），等复位 |
| `eNg` | 70 | 不合格（终点未达但超最长混合时间），等复位 |
| `eAbort` | 80 | 中止：立即停转，禁止出料 |
| `eFault` | 99 | 故障锁存 |

**引脚表**：

| 引脚 | 类型 | 方向 | 默认 | 注释基线 |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | FALSE | 使能，FALSE=停转清输出 |
| `bStart` | BOOL | IN | FALSE | 启动混合相，上升沿（`eIdle`/`eDone`/`eNg` 受理） |
| `bAbort` | BOOL | IN | FALSE | 中止（电平最高优先）：停转、禁止出料 |
| `bReset` | BOOL | IN | FALSE | 复位，上升沿 |
| `bMaterialReady` | BOOL | IN | FALSE | 投料就绪（Material ready），前置确认项 |
| `bOutletClosed` | BOOL | IN | FALSE | 出料阀关闭确认（Outlet closed），前置确认项 |
| `bDischargeDone` | BOOL | IN | FALSE | 出料完成（Discharge done），`eDischarge` 退出条件 |
| `fSpeedSetpoint` | REAL | IN | 300.0 | 搅拌转速设定（Speed setpoint）[rpm]，域 1..3000 |
| `fActSpeed` | REAL | IN | 0.0 | 实际转速（Actual speed）[rpm]，由变频器/适配层注入 |
| `fActTorque` | REAL | IN | 0.0 | 实际扭矩（Actual torque）[% 额定] |
| `fTorqueLimit` | REAL | IN | 85.0 | 扭矩保护上限（Torque limit）[%]，超限即停 + 故障 |
| `bEndByTorque` | BOOL | IN | FALSE | 以扭矩上升为终点判据（End by torque），TRUE=扭矩达 `fTorqueRiseTarget` 即认为混合完成 |
| `fTorqueRiseTarget` | REAL | IN | 60.0 | 终点扭矩判据（End torque target）[%]，仅 `bEndByTorque` 有效 |
| `tMixTime` | TIME | IN | T#5M | 目标混合时间（Mix time） |
| `tMixTimeMax` | TIME | IN | T#15M | 最长混合时间（Max mix time），超时判 NG |
| `bAlternate` | BOOL | IN | FALSE | 正反交替（Alternate direction），TRUE=每 `tAlternateTime` 换向 |
| `tAlternateTime` | TIME | IN | T#30S | 交替周期（Alternate period），仅 `bAlternate` 有效 |
| `tSpeedCheck` | TIME | IN | T#5S | 转速到位确认窗（Speed check window），设定后须在此窗内达 90% 设定 |
| `tDischargeTimeout` | TIME | IN | T#60S | 出料超时（Discharge timeout） |
| `fSpeedCmd` | REAL | OUT | 0.0 | 转速指令（Speed command）[rpm]，0=停 |
| `bDirForward` | BOOL | OUT | — | 正转指令（Forward），与 `bDirReverse` 互斥 |
| `bDirReverse` | BOOL | OUT | — | 反转指令（Reverse） |
| `ePhase` | `E_DL_MixPhase` | OUT | `eIdle` | 当前相位 |
| `bBusy` | BOOL | OUT | — | 执行中 |
| `bDone` | BOOL | OUT | — | 完成单拍脉冲（OK 或 NG 进入时各一次） |
| `bOk` | BOOL | OUT | — | 混合合格（`eDone` 保持） |
| `bNg` | BOOL | OUT | — | 混合不合格（`eNg` 保持） |
| `fProgress` | REAL | OUT | 0.0 | 进度（Progress）[-]，`0.0..1.0` = 已混合时间 / `tMixTime`（钳位） |
| `tElapsed` | TIME | OUT | T#0S | 已混合时长（Elapsed mix time） |
| `bError` | BOOL | OUT | — | 故障锁存（仅故障级码） |
| `uErrorId` | UDINT | OUT | 0 | 故障码 `16#0005_xxxx` |
| `iDrive` | `I_DL_VfdDrive` | IN_OUT | — | 搅拌驱动接口引用（既有契约，零修改）：`SetFrequency` 出转速、`CmdRun(bFwd)` 出方向、`CmdStop()` 停 |

**功能语义**：
1. `ePreCheck`：`bMaterialReady AND bOutletClosed AND iDrive.bReady`（若接口无 bReady 属性，改用 `NOT iDrive.bFault`，头注释 R11 留档说明）→ `eMixing`；不满足超 `tSpeedCheck` → 故障 `0005_0260`（前置条件不成立）。
2. `eMixing`：每拍一次 `iDrive.SetFrequency(fSpeedSetpoint)`（**仅当设定变化超容差时下发**），方向由 `bAlternate` 决定（`tAlternateTime` 到时换向，换向顺序：先 `CmdStop()` → 等 `fActSpeed < DL_MIX_STOP_EPS` → 再 `CmdRun(新方向)`，**禁止直接反接**，注释写明防机械冲击）；
3. 转速确认：进入 `eMixing` 后 `tSpeedCheck` 内 `fActSpeed ≥ 0.9 × fSpeedSetpoint`，否则故障 `0005_0261`（转速未建立，皮带断/变频器未使能）。
4. 混合计时：仅在「转速确认通过」后开始累计（`tElapsed`）；`bEndByTorque = TRUE` 时以 `fActTorque ≥ fTorqueRiseTarget` 为完成条件（信息码 `0163` 提示「扭矩终点」），否则以 `tElapsed ≥ tMixTime` 为完成。
5. `tElapsed ≥ tMixTimeMax` 仍未达终点 → `eNg`，`bNg := TRUE`，信息码 `0162`（最长混合时间到）。
6. `eVerify`：`|fActSpeed − fSpeedSetpoint| ≤ 0.05×设定` 稳定确认 → 锁存结果 → `eDischarge`。
7. `eDischarge`：`fSpeedCmd := DL_MIX_DISCHARGE_SPEED`（常量，如 50 rpm 慢速助排）→ `bDischargeDone` → `eSpinDown`；超 `tDischargeTimeout` → 故障 `0005_0262`。
8. `eSpinDown`：`iDrive.CmdStop()` 一次 → `fActSpeed < DL_MIX_STOP_EPS` → `eDone` + `bOk` + `bDone`。
9. `bAbort` → 任意态：`CmdStop()` 一次 → `eAbort`，**禁止出料**（`bOk/bNg` 均 FALSE），等 `bReset`。

**边界与防错**：
- `fActTorque ≥ fTorqueLimit` → 立即 `CmdStop()` + 故障 `0005_0263`【故障级】（搅拌桨卡死/物料过稠，防烧电机）。
- `fSpeedSetpoint ≤ 0` 或 > 3000 → 钳位 + 信息码 `0160`。
- `tMixTime > tMixTimeMax` → 自动交换 + 信息码 `0161`（对调自修复）。
- `fActSpeed` / `fActTorque` 非有限值 → 故障 `0005_0264`【故障级】。
- 方向互斥断言：`bDirForward AND bDirReverse` 恒 FALSE（切换过程两方向均 FALSE）。
- 交替周期 `tAlternateTime < 2×tSpeedCheck` → 注释警告（换向太频导致转速永远建不起来），并自动提升到 `2×tSpeedCheck` + 信息码 `0164`。

**故障码表**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0005_0160` | 信息级 | 转速设定越界钳位 |
| `0005_0161` | 信息级 | 混合时间与最长混合时间对调自修复 |
| `0005_0162` | 信息级 | 最长混合时间到，判 NG |
| `0005_0163` | 信息级 | 以扭矩上升为终点判据触发 |
| `0005_0164` | 信息级 | 交替周期被提升至两倍转速确认窗 |
| `0005_0260` | 故障级 | 前置条件不成立（料/阀/驱动），锁存 |
| `0005_0261` | 故障级 | 转速未在确认窗内建立，锁存 |
| `0005_0262` | 故障级 | 出料超时，锁存 |
| `0005_0263` | 故障级 | 扭矩超保护上限（疑似卡桨），锁存 |
| `0005_0264` | 故障级 | 转速/扭矩信号非有限值，锁存 |
| `0005_0265` | 故障级 | 非法状态兜底（本块专用） |

**验收向量**：V1 正常混合 5 min → `bOk`、`fProgress≈1.0`；V2 交替模式（30 s 换向）方向互斥且无直反接；V3 扭矩超限 → 立即停 + 0263；V4 转速未建立 → 0261；V5 `bEndByTorque` 且扭矩提前达 60% → 0163 提前完成；V6 超最长混合时间 → `eNg` + 0162；V7 出料超时 → 0262；V8 `bAbort` 中途 → 停转且不出料、无 OK/NG。

---

### 2.5 `FB_DL_CipCleaningSeq`（功能块）｜DL_Process｜来源标签 `cip-cleaning` / `isa-88-phase`｜RAW_NOTES S-10

**功能**：CIP 原位清洗六相顺控（预冲洗 → 碱洗 → 中间冲洗 → 酸洗 → 终冲洗 → 消毒）。核心：**相位计时受 TACT 联锁暂停**（温度 / 电导率 / 流量不达标不计时）；终冲洗以回液电导率判终点（时间兜底）；阀阵就绪门控；中止即排空隔离；偏差计数供审计。

**随本块发布的枚举** `E_DL_CipPhase`：

| 枚举项 | 值 | 注释基线 |
|---|---|---|
| `eIdle` | 0 | 空闲：等启动 |
| `ePreRinse` | 10 | 预冲洗（Pre-rinse） |
| `eCaustic` | 20 | 碱洗（Caustic wash） |
| `eIntRinse` | 30 | 中间冲洗（Intermediate rinse） |
| `eAcid` | 40 | 酸洗（Acid wash） |
| `eFinalRinse` | 50 | 终冲洗（Final rinse） |
| `eSanitize` | 60 | 消毒（Sanitize） |
| `eDone` | 70 | 完成（`bCipComplete`），等复位 |
| `eAbort` | 80 | 中止：排空隔离 |
| `eFault` | 99 | 故障锁存 |

**引脚表**：

| 引脚 | 类型 | 方向 | 默认 | 注释基线 |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | FALSE | 使能，FALSE=停泵停止加药（不主动排空） |
| `bStart` | BOOL | IN | FALSE | 启动 CIP 周期，上升沿（`eIdle`/`eDone` 受理） |
| `bAbort` | BOOL | IN | FALSE | 中止（电平最高优先）→ 停泵 + 开排空 + 隔离 |
| `bReset` | BOOL | IN | FALSE | 复位，上升沿 |
| `bCircuitReady` | BOOL | IN | FALSE | 回路就绪（供货/回液阀位置确认），FALSE 禁止启泵（S-10 提取点③） |
| `abPhaseEnable` | `ARRAY[0..DL_CIP_PHASE_MAX-1] OF BOOL` | IN | — | 各相启用（Phase enable）：0 预冲 / 1 碱 / 2 中冲 / 3 酸 / 4 终冲 / 5 消毒 |
| `atPhaseTime` | `ARRAY[0..DL_CIP_PHASE_MAX-1] OF TIME` | IN | — | 各相目标计时（Phase time），仅达标计时累计 |
| `afPhaseTempMin` | `ARRAY[0..DL_CIP_PHASE_MAX-1] OF REAL` | IN | — | 各相温度下限（Temp min）[℃]，0=不校验 |
| `afPhaseCondMin` | `ARRAY[0..DL_CIP_PHASE_MAX-1] OF REAL` | IN | — | 各相电导率下限（Conductivity min）[mS/cm]，0=不校验 |
| `afPhaseFlowMin` | `ARRAY[0..DL_CIP_PHASE_MAX-1] OF REAL` | IN | — | 各相流量下限（Flow min）[m³/h]，0=不校验 |
| `fActTemp` | REAL | IN | 0.0 | 实际温度（Actual temperature）[℃] |
| `fActCond` | REAL | IN | 0.0 | 实际电导率（Actual conductivity）[mS/cm]，供液或回液由调用方选择接点 |
| `fActFlow` | REAL | IN | 0.0 | 实际流量（Actual flow）[m³/h] |
| `fRinseCondTarget` | REAL | IN | 0.1 | 终冲洗回液电导率终点（Rinse conductivity target）[mS/cm] |
| `tHoldLimit` | TIME | IN | T#300S | 单相联锁暂停上限（Hold limit），超时判该相失败 |
| `tRinseMax` | TIME | IN | T#15M | 终冲洗最长延时（Rinse max time），电导率未达标的兜底上限 |
| `tDrainTime` | TIME | IN | T#60S | 中止后排空时长（Drain time） |
| `tTempSetDelay` | TIME | IN | T#0S | 升温/降温等待（Temp set delay），相开始时先等待此窗不计时 |
| `ePhase` | `E_DL_CipPhase` | OUT | `eIdle` | 当前相位 |
| `bBusy` | BOOL | OUT | — | 周期执行中 |
| `bDone` | BOOL | OUT | — | 周期完成单拍 |
| `bOk` | BOOL | OUT | — | 全相完成且无偏差（`eDone` 保持） |
| `bPhaseHold` | BOOL | OUT | — | 相位暂停中（TACT 未达标），计时冻结 |
| `bPhaseFail` | BOOL | OUT | — | 当前相失败（暂停超限 / 终点未达） |
| `bCipComplete` | BOOL | OUT | — | CIP 完成许可（供上层放行生产，S-10 提取点③ clean-status） |
| `bCmdSupplyPump` | BOOL | OUT | — | 供液泵指令 |
| `bCmdReturnPump` | BOOL | OUT | — | 回液泵指令 |
| `bCmdDosing` | BOOL | OUT | — | 加药泵指令（电导率低于下限时脉冲式请求） |
| `bCmdHeat` | BOOL | OUT | — | 加热（蒸汽阀）指令 |
| `bCmdDrain` | BOOL | OUT | — | 排空阀指令（中止/换相时） |
| `fTempSetpoint` | REAL | OUT | 0.0 | 温度设定（Temp setpoint）[℃]，取当前相下限（略高 2 ℃ 裕量，注释写明） |
| `tPhaseElapsed` | TIME | OUT | T#0S | 当前相已累计计时（Phase elapsed），仅达标时段 |
| `nDeviationCount` | UDINT | OUT | 0 | 偏差计数（Deviation counter），每次暂停/失败 +1，供审计 |
| `bError` | BOOL | OUT | — | 故障锁存（仅故障级码） |
| `uErrorId` | UDINT | OUT | 0 | 故障码 `16#0005_xxxx` |

**功能语义**：
1. 相序：`ePreRinse → eCaustic → eIntRinse → eAcid → eFinalRinse → eSanitize → eDone`；`abPhaseEnable[i] = FALSE` 的相跳过（跳相由参数决定，**运行中的跳相指令一律拒绝**，信息码 `0170`）。
2. 相内联锁（每拍判定，三路任一不满足 → 暂停计时）：
   - 温度：`afPhaseTempMin[i] > 0 AND fActTemp < afPhaseTempMin[i]` → 暂停 + `bCmdHeat := TRUE`；
   - 电导率：`afPhaseCondMin[i] > 0 AND fActCond < afPhaseCondMin[i]` → 暂停 + `bCmdDosing := TRUE`（脉冲式，每 5 s 一拍，常量）；
   - 流量：`afPhaseFlowMin[i] > 0 AND fActFlow < afPhaseFlowMin[i]` → 暂停（防停滞计时，S-10 提取点①）。
   暂停时 `bPhaseHold := TRUE`，累计计时不增；恢复自动继续；暂停累计超 `tHoldLimit` → `bPhaseFail := TRUE` + 故障 `0005_0270`【故障级】（**判相失败而非继续等**）。
3. 计时：仅在「联锁全达标」且「`tTempSetDelay` 已过」时 `tPhaseElapsed` 累加；`tPhaseElapsed ≥ atPhaseTime[i]` → 下一相。
4. 终冲洗特殊判据：`eFinalRinse` 以 `fActCond ≤ fRinseCondTarget` 为完成条件（**不以时间到为准**），并以 `tRinseMax` 兜底（超时 → 故障 `0005_0271`）。
5. 泵/阀：相开始时 `bCmdSupplyPump := bCmdReturnPump := bCircuitReady`（回路未就绪禁止启泵，信息码 `0171`）；相切换时先停泵 `DL_CIP_SWITCH_PAUSE`（常量 T#2S）再切阀（注释说明防混液）。
6. `eDone`：全部启用相完成 → `bCipComplete := TRUE`，`bOk := TRUE`（`nDeviationCount = 0` 时）。`bReset` 后 `bCipComplete` 清零。
7. `bAbort`：停泵、关加药、开排空 `tDrainTime` → `eAbort` → `bCipComplete := FALSE`（**中止即失去清洁许可**，S-10 提取点④）。

**边界与防错**：
- `fActTemp` / `fActCond` / `fActFlow` 非有限值 → 暂停（视为不达标，**保守侧**）+ 信息码 `0172`（不立即故障，避免单点传感器抖动打断整批）。
- `atPhaseTime[i] = T#0S` 且该相启用 → 故障 `0005_0272`【故障级】（零时长相无意义，疑似配方错误）。
- 所有相位数组索引必须先判 `< DL_CIP_PHASE_MAX`。
- `fTempSetpoint` 取 `afPhaseTempMin[i] + DL_CIP_TEMP_MARGIN`（常量 2.0 ℃），并注释说明「裕量为工艺经验值」。
- `bPhaseHold` 与 `bPhaseFail` 出口断言不同真（失败后暂停解除并锁存）。
- 头注释声明：本块**不实现**阀门矩阵/混流防护的物理设计（属机械与管路设计），仅做就绪门控与指令编排。

**故障码表**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0005_0170` | 信息级 | 运行中跳相请求被拒 |
| `0005_0171` | 信息级 | 回路未就绪，泵指令被抑制 |
| `0005_0172` | 信息级 | TACT 信号非有限值，保守侧暂停 |
| `0005_0173` | 信息级 | 相切换停泵间隔中 |
| `0005_0270` | 故障级 | 单相联锁暂停超限，相失败，锁存 |
| `0005_0271` | 故障级 | 终冲洗超最长延时仍未达电导终点，锁存 |
| `0005_0272` | 故障级 | 启用相的目标时长为零，锁存 |
| `0005_0273` | 故障级 | 回路未就绪启动（`bCircuitReady=FALSE` 强行启动），锁存 |
| `0005_0274` | 故障级 | 非法状态兜底（本块专用） |

**验收向量**：V1 六相全启用正常走完 → `bCipComplete`；V2 碱洗段温度低于下限 → 计时冻结 + `bPhaseHold`，温度恢复后计时继续；V3 暂停 300 s → 0270 相失败；V4 终冲洗回液电导降到终点 → 立即完成（不等 `atPhaseTime`）；V5 终冲洗超 `tRinseMax` → 0271；V6 `abPhaseEnable[3]=FALSE` → 跳过酸洗；V7 `bAbort` → 停泵排空 + `bCipComplete=FALSE`；V8 启用相 `atPhaseTime=0` → 0272。

---

### 2.6 `FB_DL_BufferMagazine`（功能块）｜DL_Process｜来源标签 `material-handling` / `magazine-stocker`｜RAW_NOTES S-7（线体节拍）/ S-13（状态指示联动）

**功能**：多层料仓 / 弹夹升降存取调度器。管理各层槽位状态（空 / 满 / NG / 预留），按「取料优先最低满层、存料优先最低空层、NG 优先最近空层」策略选层，输出升降方向与到位联锁，统计满/空/NG 数，支持手动指定层。

**随本块发布的枚举**：

```
E_DL_SlotState : eEmpty(0) / eFull(10) / eNg(20) / eReserved(30)
E_DL_MagState  : eIdle(0) / eSelect(10) / eMoving(20) / eArrived(30) / eHandling(40) / eDone(50) / eFault(99)
```

**引脚表**：

| 引脚 | 类型 | 方向 | 默认 | 注释基线 |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | FALSE | 使能，FALSE=停止升降输出并清请求 |
| `bReset` | BOOL | IN | FALSE | 复位故障，上升沿 |
| `bReqFetch` | BOOL | IN | FALSE | 取料请求（Fetch request），上升沿受理 |
| `bReqStore` | BOOL | IN | FALSE | 存料请求（Store request），上升沿受理 |
| `bReqStoreNg` | BOOL | IN | FALSE | 存 NG 料（Store NG），与 `bReqStore` 同沿时按 NG 处理 |
| `nManualLayer` | UINT | IN | 0 | 手动指定层（Manual layer）[-]，0=自动选层，1..`nLayerCount`=指定 |
| `nLayerCount` | UINT | IN | 8 | 层数（Layer count）[-]，域 1..`DL_MAG_MAX_LAYERS`；越界钳位 |
| `nLiftAtLayer` | UINT | IN | 0 | 升降当前层位置（Lift current layer）[-]，由限位/编码器注入，0=未知 |
| `bLiftInPosition` | BOOL | IN | FALSE | 升降到位确认（Lift in position） |
| `bHandlingDone` | BOOL | IN | FALSE | 取放动作完成（Handling done），`eHandling` 退出条件 |
| `tMoveTimeout` | TIME | IN | T#20S | 升降超时（Move timeout），按层间行程整定 |
| `tHandlingTimeout` | TIME | IN | T#10S | 取放超时（Handling timeout） |
| `tDebounce` | TIME | IN | T#50MS | 到位信号消抖（In-position debounce） |
| `bMoveUp` | BOOL | OUT | — | 上升指令（Move up） |
| `bMoveDown` | BOOL | OUT | — | 下降指令（Move down） |
| `nTargetLayer` | UINT | OUT | 0 | 目标层（Target layer）[-]，0=无目标 |
| `eState` | `E_DL_MagState` | OUT | `eIdle` | 主状态 |
| `bBusy` | BOOL | OUT | — | 调度中 |
| `bDone` | BOOL | OUT | — | 存取完成单拍 |
| `bMagFull` | BOOL | OUT | — | 料仓全满（无空槽），瞬态型 |
| `bMagEmpty` | BOOL | OUT | — | 料仓全空（无满槽），瞬态型 |
| `nFullCount` | UINT | OUT | 0 | 满槽数（每拍重算） |
| `nEmptyCount` | UINT | OUT | 0 | 空槽数 |
| `nNgCount` | UINT | OUT | 0 | NG 槽数 |
| `bFault` | BOOL | OUT | — | 故障锁存（仅故障级码） |
| `uErrorId` | UDINT | OUT | 0 | 故障码 `16#0005_xxxx` |
| `aeSlot` | `ARRAY[0..DL_MAG_MAX_LAYERS-1] OF E_DL_SlotState` | IN_OUT | — | 各层槽位状态（Slot states），索引 0 = 第 1 层；由本块维护 |

**功能语义**：
1. 每拍重算 `nFullCount` / `nEmptyCount` / `nNgCount`（`FOR` 循环 + 层数钳位，**禁无界 WHILE**），并派生 `bMagFull` / `bMagEmpty`（瞬态型）。
2. 选层（`eSelect`）：
   - 取料：最低的 `eFull` 层；无满层 → 拒绝 + 信息码 `0180`（全空），回 `eIdle`；
   - 存料（OK）：最低的 `eEmpty` 层；无空层 → 拒绝 + 信息码 `0181`（全满）；
   - 存 NG：最低的 `eEmpty` 或 `eReserved` 层（NG 优先占预留位，注释说明「NG 料优先占隔离位」）；无 → 信息码 `0182`；
   - `nManualLayer > 0` 且 ≤ `nLayerCount`：强制用指定层（手动优先），若该层状态与请求不匹配 → 拒绝 + 信息码 `0183`。
3. 移动（`eMoving`）：`nLiftAtLayer < nTargetLayer` → `bMoveUp := TRUE`；`>` → `bMoveDown := TRUE`；到达（`nLiftAtLayer = nTargetLayer` 且 `bLiftInPosition` 消抖后为 TRUE）→ `eArrived`；超 `tMoveTimeout` → 故障 `0005_0280`。
4. 取放（`eHandling`）：等待 `bHandlingDone`；完成时更新槽位：取料 `eFull → eEmpty`，存 OK `eEmpty → eFull`，存 NG `eEmpty/eReserved → eNg`；超 `tHandlingTimeout` → 故障 `0005_0281`。
5. `eDone`：`bDone` 单拍 → `eIdle`。
6. 方向互斥断言：`bMoveUp AND bMoveDown` 恒 FALSE。

**边界与防错**：
- `nLayerCount = 0` 或 `> DL_MAG_MAX_LAYERS` → 钳位到 `[1, DL_MAG_MAX_LAYERS]` + 信息码 `0184`。
- `nLiftAtLayer > nLayerCount` → 视为位置未知（0），故障 `0005_0282`（限位/编码器异常）。
- 槽位数组索引一律先判域。
- 手动层与自动层切换运行中（`bBusy` 时改 `nManualLayer`）→ 本周期不生效，下周期生效 + 信息码 `0185`。
- 取/存请求同拍到达 → 双丢弃 + 信息码 `0186`（不猜）。
- 头注释说明：本块**不做**夹具/机械手动作编排（只给层目标与到位联锁），动作由调用方分段编排。

**故障码表**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0005_0180` | 信息级 | 无满槽可取（料仓空） |
| `0005_0181` | 信息级 | 无空槽可存（料仓满） |
| `0005_0182` | 信息级 | 无 NG 隔离位可用 |
| `0005_0183` | 信息级 | 手动指定层与请求类型不匹配 |
| `0005_0184` | 信息级 | 层数越界钳位 |
| `0005_0185` | 信息级 | 运行中改手动层，下周期生效 |
| `0005_0186` | 信息级 | 取/存请求同拍冲突，双丢弃 |
| `0005_0280` | 故障级 | 升降超时未到位，锁存 |
| `0005_0281` | 故障级 | 取放动作超时，锁存 |
| `0005_0282` | 故障级 | 升降层位置越界（限位/编码器异常），锁存 |
| `0005_0283` | 故障级 | 非法状态兜底（本块专用） |

**验收向量**：V1 8 层全空，存料 → 选第 1 层，槽位变 `eFull`；V2 连续存至全满 → `bMagFull`、再存 → 0181；V3 取料选最低满层；V4 存 NG 占预留位；V5 手动指定第 5 层取料但该层空 → 0183；V6 升降超时 → 0280；V7 取/存同拍 → 0186；V8 `nLayerCount=0` → 钳位 1 + 0184。

---

## 第 3 节 泳道 C｜DL_Device 安灯塔收尾族（2 项）

### 3.1 `I_DL_TowerLight`（接口）｜DL_Device｜来源标签 `tcopen-component` / `stack-light`｜RAW_NOTES S-13

**功能**：工业安灯塔（Andon / 三色或四色塔灯 + 蜂鸣）标准抽象契约。按本库接口三段式（属性 GET + 方法 ≤6 + 状态枚举）组织；上层面板 / 工站 / PackML 状态机只需注入本接口，即可适配直驱型（每色一路 DO）、模块化型（XVU 类）与总线型（IO-Link 塔灯）。

**随接口同文件发布的枚举**：

```
E_DL_TowerColor   : eNone(0) / eRed(10) / eAmber(20) / eGreen(30) / eBlue(40) / eWhite(50)
E_DL_TowerPattern : eOff(0) / eSteady(10) / eFlashSlow(20) / eFlashFast(30) / eRotate(40)
E_DL_TowerState   : eNormal(0) / eWarning(10) / eFaultAck(20) / eFaultUnack(30) / eSafety(40) / eManual(50) / eCall(60)
```

**属性（`PROPERTY` GET，只读，共 10 个）**：

| 属性 | 类型 | 注释基线 |
|---|---|---|
| `eState` | `E_DL_TowerState` | 当前显示状态（Displayed state），等于仲裁结果的语义分类 |
| `eRed` / `eAmber` / `eGreen` / `eBlue` / `eWhite` | `E_DL_TowerPattern` | 各色当前模式（Per-color pattern），`eOff`=不亮 |
| `bBuzzer` | BOOL | 蜂鸣器当前输出（Buzzer active） |
| `bSilenced` | BOOL | 已消音（Silenced），消音窗内为 TRUE |
| `bError` | BOOL | 故障锁存（仅故障级码） |
| `uErrorId` | UDINT | 故障码 `16#0003_xxxx` |

**方法（3 个，≤6）**：

| 方法 | 签名 | 语义 |
|---|---|---|
| `SetColor` | `METHOD SetColor : BOOL`，入参 `eColor : E_DL_TowerColor`、`ePattern : E_DL_TowerPattern` | 请求置某色某模式；返回 FALSE 表示当前被更高优先级占用或被消音策略拒绝 |
| `SilenceBuzzer` | `METHOD SilenceBuzzer : BOOL` | 消音（一次性，超时自动恢复），非蜂鸣期调用返回 FALSE |
| `Reset` | `METHOD Reset : BOOL` | 复位故障锁存；非 `eFault` 态返回 FALSE |

**边界防错**：接口层不做任何电平输出（物理输出由实现块 `VAR_OUTPUT` 给出）；接口层不读任何物理输入（状态由实现块引脚注入）；**红绿互斥**属实现块职责（接口只声明属性语义）。

### 3.2 `FB_DL_SignalTower`（功能块，实现 `I_DL_TowerLight`）｜DL_Device｜来源标签 `tcopen-component` / `stack-light`｜RAW_NOTES S-13

**功能**：塔灯集中驱动程序。以一组设备状态位为输入，按**唯一优先级出口**仲裁出五色与蜂鸣输出（S-13 提取点①）；未确认告警闪烁、已确认常亮；双闪频时基由引脚给定（禁读 CPU 钟）；蜂鸣支持允许 / 消音 / 消音超时自动恢复；红绿互斥安全侧断言；多色同亮合法（蓝+黄）。

**优先级（自高到低，编码侧不得改序）**：

| 级 | 条件 | 红 | 黄 | 绿 | 蓝 | 白 | 蜂鸣 |
|---|---|---|---|---|---|---|---|
| 1 | `bSafetyEvent` | 快闪 | 灭 | 灭 | 灭 | 灭 | 鸣 |
| 2 | `bFaultActive AND NOT bFaultAck` | 慢闪 | 灭 | 灭 | 灭 | 灭 | 鸣 |
| 3 | `bFaultActive AND bFaultAck` | 常亮 | 灭 | 灭 | 灭 | 灭 | 灭 |
| 4 | `bWarnActive AND NOT bWarnAck` | 灭 | 慢闪 | 灭 | 灭 | 灭 | 灭 |
| 5 | `bWarnActive AND bWarnAck` | 灭 | 常亮 | 灭 | 灭 | 灭 | 灭 |
| 6 | `bManualMode` | 灭 | — | 灭 | 常亮 | 灭 | 灭 |
| 7 | `bAutoRunning` | 灭 | — | 常亮 | 灭 | 灭 | 灭 |
| 8 | `bOperatorCall` | 灭 | — | 灭 | 快闪 | 灭 | 灭 |
| 9 | 其余（待机） | 灭 | 灭 | 灭 | 灭 | 灭 | 灭 |

> **叠加规则**：级 1~5 为「互斥主级」（只亮主色）；级 6~8 为「可叠加辅级」——手动（蓝常亮）可与预警（黄）同时亮，运行（绿）可与求助（蓝快闪）同时亮。级 1~5 生效时辅级全部熄灭（安全优先）。**红与绿永不共存**（出口断言）。

**引脚表**：

| 引脚 | 类型 | 方向 | 默认 | 注释基线 |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | FALSE | 使能，FALSE=全灯灭、蜂鸣停（清输出） |
| `bSafetyEvent` | BOOL | IN | FALSE | 安全事件（Safety event，急停/安全门/光幕触发镜像），最高优先 |
| `bFaultActive` | BOOL | IN | FALSE | 故障存在（Fault active） |
| `bFaultAck` | BOOL | IN | FALSE | 故障已确认（Fault acknowledged），TRUE=红常亮 |
| `bWarnActive` | BOOL | IN | FALSE | 预警存在（Warning active） |
| `bWarnAck` | BOOL | IN | FALSE | 预警已确认（Warning acknowledged） |
| `bManualMode` | BOOL | IN | FALSE | 手动模式（Manual mode），蓝常亮 |
| `bAutoRunning` | BOOL | IN | FALSE | 自动运行中（Auto running），绿常亮 |
| `bOperatorCall` | BOOL | IN | FALSE | 操作员求助（Operator call），蓝快闪 |
| `bStandbyIndicate` | BOOL | IN | FALSE | 待机指示（Standby indication），白常亮（可选） |
| `bBuzzerEnable` | BOOL | IN | TRUE | 蜂鸣允许（Buzzer enable），FALSE 时永不鸣 |
| `bSilenceCmd` | BOOL | IN | FALSE | 消音指令（Silence），上升沿受理 |
| `tSilenceTime` | TIME | IN | T#60S | 消音保持时长（Silence hold time），到期自动恢复蜂鸣 |
| `tFlashSlow` | TIME | IN | T#500MS | 慢闪半周期（Slow flash half period），默认 500 ms → 1 Hz 全周期 |
| `tFlashFast` | TIME | IN | T#250MS | 快闪半周期（Fast flash half period），默认 250 ms → 2 Hz |
| `bReset` | BOOL | IN | FALSE | 复位故障，上升沿 |
| `bRed` | BOOL | OUT | — | 红（Red） |
| `bAmber` | BOOL | OUT | — | 黄（Amber） |
| `bGreen` | BOOL | OUT | — | 绿（Green） |
| `bBlue` | BOOL | OUT | — | 蓝（Blue） |
| `bWhite` | BOOL | OUT | — | 白（White） |
| `bBuzzer` | BOOL | OUT | — | 蜂鸣器（Buzzer） |
| `bSilenced` | BOOL | OUT | — | 消音中（Silenced） |
| `eState` | `E_DL_TowerState` | OUT | `eNormal` | 显示状态（Displayed state），仲裁结果语义 |
| `bFault` | BOOL | OUT | — | 故障锁存（仅故障级码：参数非法/输出断言冲突） |
| `uErrorId` | UDINT | OUT | 0 | 故障码 `16#0003_xxxx` |

**功能语义**：
1. **时基**（禁读 CPU 钟）：`_fbTonSlow(IN := NOT _bSlowPhase, PT := tFlashSlow)` 与 `_fbTonFast(...)` 无条件刷新，`Q` 到来即翻转相位标志 `_bSlowPhase` / `_bFastPhase`；慢闪输出 = `_bSlowPhase`，快闪输出 = `_bFastPhase`。`tFlashSlow/tFlashFast = T#0S` → 该闪频退化为常亮（信息码 `0123`）。
2. 仲裁：按上表优先级逐级 `IF/ELSIF`（**不得写成并列 IF 覆盖**，必须单一出口），结果写入内部 `_eRed/_eAmber/...` 模式变量，再统一映射到 `bRed/bAmber/...` 与 `E_DL_TowerPattern` 属性镜像。
3. 蜂鸣：主级 1~2（安全事件 / 未确认故障）且 `bBuzzerEnable` 且未消音 → `bBuzzer := TRUE`；`bSilenceCmd` 沿 → `_fbTonSilence(PT := tSilenceTime)` 计时，`bSilenced := TRUE`；到期 → 自动恢复 `bBuzzer := TRUE` 并置信息码 `0124`（提示消音到期恢复）。
4. 出口断言：`IF bRed AND bGreen THEN bGreen := FALSE; uErrorId := 16#0003_02D0;`（安全侧保红，注释写明「红绿同亮为逻辑错误，保红灭绿」）。同理 `bAmber AND bGreen` 允许（黄绿同亮无安全含义歧义），但 `bRed AND bAmber` 由仲裁表天然不成立（主级互斥）。
5. `bEnable = FALSE`：全部输出 FALSE，模式属性回 `eOff`，`eState := eNormal`。

**边界与防错**：
- `tSilenceTime = T#0S` → 视为「不自动恢复」（消音永续，须人再按），信息码 `0125`（注释警告：安全事件仍可强制鸣——**级 1 安全事件不受消音约束**，实现上 `bSafetyEvent` 时强制 `bBuzzer := TRUE`）。
- `tFlashSlow/tFlashFast` 与扫描周期关系不可知 → 注释要求 `tFlash* ≥ 5 × 扫描周期`，本块不校验。
- 多条件同真：`bManualMode AND bAutoRunning` → 手动优先（级 6 先于 7），信息码 `0126`（模式冲突提示）。
- 所有输入均为 BOOL，无常量魔法数（周期全部引脚化）。
- `FB_DL_SignalTower` 必须**声明实现 `I_DL_TowerLight`**，10 个属性全部以只读 `PROPERTY GET` 落地（与接口同名成员不得重复声明为 `VAR_OUTPUT`，R22 公约）。

**故障码表**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0003_0123` | 信息级 | 闪频参数为零，退化为常亮 |
| `0003_0124` | 信息级 | 消音到期自动恢复蜂鸣 |
| `0003_0125` | 信息级 | 消音时长为零（消音永续） |
| `0003_0126` | 信息级 | 手动/自动模式同真，手动优先 |
| `0003_02D0` | 故障级 | 红绿同亮断言冲突（保红灭绿），锁存 |
| `0003_02D1` | 故障级 | 非法状态兜底（本块专用） |

**验收向量**：V1 安全事件 → 红快闪 + 鸣（即使已消音）；V2 未确认故障 → 红慢闪 + 鸣；V3 确认后 → 红常亮不鸣；V4 预警未确认/已确认 → 黄慢闪/黄常亮；V5 手动 + 预警 → 蓝常亮 + 黄常亮（叠加合法）；V6 消音 60 s 后自动恢复 + 0124；V7 人为触发红绿同真（构造输入）→ 绿被灭 + 02D0；V8 `bEnable=FALSE` → 全灭。

---

## 第 4 节 泳道 D｜DL_Algo 补 2 项

### 4.1 `FB_DL_PeakDetector`（功能块）｜DL_Algo｜来源标签 `lgf-math` / `lgf-measurement`｜RAW_NOTES S-11

**功能**：峰值 / 谷值检测与保持（时域极值跟踪）。输入信号上升即更新峰值，可选按 `fDecayRate` 衰减（模拟表针回落 / 峰值窗口滚动）；可同时检测谷值；双阈值穿越事件（单拍脉冲）；阈值超限保持位；峰值计数。**连续运算型，无状态机（免 CASE / 免首扫）**——与库内 `FB_DL_LowPassFilter` 同类先例；职责与 `FB_DL_SignalStatistics`（窗口统计量）严格分离：本块输出**过程极值**，不做均值/方差。

**引脚表**：

| 引脚 | 类型 | 方向 | 默认 | 注释基线 |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | FALSE | 使能，FALSE=保持当前极值不动、事件清零 |
| `bReset` | BOOL | IN | FALSE | 复位极值到当前输入（Reset to current），上升沿 |
| `fSignal` | REAL | IN | 0.0 | 输入信号（Input signal）[工程单位]，非有限值时保持上次有效值 |
| `tSample` | TIME | IN | T#10MS | 采样周期（Sample period）[ms]，用于衰减计算；`T#0S` → 不衰减 |
| `fDecayRate` | REAL | IN | 0.0 | 峰值衰减率（Decay rate）[工程单位/s]，0=无限保持；<0 取 ABS |
| `bDetectValley` | BOOL | IN | TRUE | 同时检测谷值（Detect valley） |
| `fThreshold` | REAL | IN | 0.0 | 事件阈值（Event threshold）[工程单位]，峰值上穿即出脉冲 |
| `bThresholdEnable` | BOOL | IN | FALSE | 阈值事件使能（Threshold event enable） |
| `fPeak` | REAL | OUT | 0.0 | 峰值（Peak value）[工程单位] |
| `fValley` | REAL | OUT | 0.0 | 谷值（Valley value）[工程单位]，`bDetectValley=FALSE` 时恒为 0 |
| `fPeakRate` | REAL | OUT | 0.0 | 峰值变化率（Peak rate）[工程单位/s]，用于判断峰值是否仍在爬升 |
| `bPeakEvent` | BOOL | OUT | — | 峰值更新事件（Peak updated），单拍脉冲 |
| `bValleyEvent` | BOOL | OUT | — | 谷值更新事件，单拍脉冲 |
| `bOverThreshold` | BOOL | OUT | — | 峰值超阈值（Peak over threshold），电平型每拍重算 |
| `uPeakCount` | UDINT | OUT | 0 | 峰值更新次数（Peak update counter），可用于「冲击次数」统计 |
| `bError` | BOOL | OUT | — | 参数故障锁存（本块仅参数级故障） |
| `uErrorId` | UDINT | OUT | 0 | 故障码 `16#0002_xxxx` |

**功能语义（逐拍，顺序固定）**：
1. 非有限值检测：`fSignal` 非有限 → 保持 `_fLastValid`，置信息码 `1901`（每拍重算），**不更新极值**。
2. 衰减（先衰减后比较，保证衰减不被同拍更新掩盖）：`IF fDecayRate > 0 AND tSample > T#0S THEN fPeak := fPeak − fDecayRate × TIME_TO_REAL(tSample)/1000.0; IF fPeak < fSignal THEN fPeak := fSignal; END_IF`（注释：衰减不得使峰值低于当前信号）。
3. 峰值更新：`IF fSignal > fPeak THEN fPeak := fSignal; bPeakEvent := TRUE; uPeakCount := uPeakCount + 1;`（**用 `>` 严格比较，相等不算更新**，避免噪声导致计数爆增）。
4. 谷值更新：`IF bDetectValley AND fSignal < fValley THEN fValley := fSignal; bValleyEvent := TRUE;`。
5. 阈值：`bOverThreshold := bThresholdEnable AND fPeak ≥ fThreshold`（**电平型每拍重算**，不做单发——单发由调用方加边沿）。
6. `fPeakRate`：= `(fPeak − _fPeakPrev) / (tSample 秒)`，`tSample = 0` 时置 0。
7. `bReset` 沿：`fPeak := fSignal; fValley := fSignal; uPeakCount := 0;` 并清事件。

**边界与防错**：
- `fThreshold` 非有限值 → `bThresholdEnable := FALSE` 等效（阈值失效）+ 信息码 `1902`。
- `fDecayRate` 非有限值或负 → 取 ABS / 0 + 信息码 `1903`。
- `tSample > DL_PEAK_SAMPLE_MAX`（常量 T#10S）→ 钳位 + 信息码 `1904`（采样周期异常，衰减步长失真）。
- 初始化：`_bInit` 首拍（R19 范式 `IF (NOT bInit) THEN fPeak := fSignal; fValley := fSignal; bInit := TRUE;`）——**本块虽无状态机，但仍有初值语义，必须首扫初始化**（此为对「免首扫」的例外说明：无 CASE，但有初值，采用 R19 范式）。
- 极值输出与输入同量纲，注释必须写明调用方单位（不做单位换算）。

**故障码表（全信息级）**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0002_1901` | 信息级 | 输入非有限值，保持上次有效极值 |
| `0002_1902` | 信息级 | 阈值非有限值，阈值事件禁用 |
| `0002_1903` | 信息级 | 衰减率非法，按 0 / 绝对值处理 |
| `0002_1904` | 信息级 | 采样周期越界钳位 |

**验收向量**：V1 信号 0→10→5，峰值 10、谷值 0；V2 无衰减时峰值保持不回落；V3 `fDecayRate=2`、`tSample=100ms`，静置 1 s 峰值降 2；V4 衰减后信号回升 ≤ 峰值时峰值不反超（步骤 2 的钳制）；V5 阈值上穿 → `bOverThreshold`；V6 `bReset` 后极值=当前信号、计数清零；V7 NaN 输入 → 保持 + 1901；V8 `tSample=T#0S` → 不衰减。

### 4.2 `FB_DL_StepController`（功能块）｜DL_Algo｜来源标签 `lbp-step-controller` / `lgf-technology`｜RAW_NOTES S-9

**功能**：分级步进控制器（LBP_CtrlStp 语义 clean-room）。偏差 → 级数（0..`nStages`），带级间死区（上升/下降双向迟滞防抖）、最小驻留时间（防频繁投切）、可选均衡轮换（多台同型设备轮流投切，均摊磨损）；输出拓扑二选一：**累积型**（多级加热器组：`abStage[i] = i ≤ nActiveStage`）或**单级型**（多台泵/压缩机选一台：仅第 n 级为 TRUE）。**连续运算型，无状态机（免 CASE）**；`bCumulative` 属**输出接线拓扑选择**，不构成算法变体——**禁止再叠加其他模式参数**（矩阵第 3 节禁令）。

**引脚表**：

| 引脚 | 类型 | 方向 | 默认 | 注释基线 |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | FALSE | 使能，FALSE=全部级复位为 0 |
| `bReset` | BOOL | IN | FALSE | 复位级数与轮换偏移到 0，上升沿 |
| `fSetpoint` | REAL | IN | 0.0 | 设定值（Setpoint）[工程单位] |
| `fActual` | REAL | IN | 0.0 | 实际值（Actual value）[工程单位]，同量纲 |
| `nStages` | UINT | IN | 4 | 级数（Stage count）[-]，域 1..`DL_STEP_MAX_STAGES`（=8）；越界钳位 |
| `fBandSpan` | REAL | IN | 100.0 | 级带宽（Band span）[工程单位]，偏差绝对值的满量程（对应全部级投入）；≤0 或非有限值 → 回默认 |
| `fDeadband` | REAL | IN | 2.0 | 级间死区（Stage deadband）[工程单位]，迟滞半宽；<0 取 ABS |
| `tMinDwell` | TIME | IN | T#10S | 最小驻留时间（Min dwell time），级切换后须停留此时间才允许再切 |
| `bCumulative` | BOOL | IN | TRUE | 累积输出拓扑（Cumulative topology），TRUE=多级依次投入；FALSE=单级互斥 |
| `bRotate` | BOOL | IN | FALSE | 均衡轮换（Rotation），TRUE=每级投切时轮换物理设备偏移 |
| `nRotateStep` | UINT | IN | 1 | 轮换步长（Rotation step）[-]，CTU 计数用，通常 1 |
| `nActiveStage` | UINT | OUT | 0 | 当前投入级数（Active stage）[-]，0..`nStages` |
| `abStage` | `ARRAY[0..DL_STEP_MAX_STAGES-1] OF BOOL` | OUT | — | 各级输出（Stage outputs），索引 0=第 1 级；累积型下为前缀真 |
| `nRotateOffset` | UINT | OUT | 0 | 轮换偏移（Rotation offset）[-]，0..`nStages-1`，供 HMI 与接线映射 |
| `nSwitchCount` | UDINT | OUT | 0 | 投切次数（Switch counter），每次 `nActiveStage` 变化 +1 |
| `bAtMaxStage` | BOOL | OUT | — | 已达最大级（At max stage），满出力警示 |
| `bAtMinStage` | BOOL | OUT | — | 已回零级（At min stage） |
| `bError` | BOOL | OUT | — | 参数故障锁存（仅故障级码） |
| `uErrorId` | UDINT | OUT | 0 | 故障码 `16#0002_xxxx` |

**功能语义**：
1. 偏差：`fErr := fSetpoint − fActual`（注释写明方向：正偏差=需要加热/加压/加速）。
2. 比例级数：`nReq := REAL_TO_UINT( LIMIT( ABS(fErr) / fBandSpan × nStages, 0, nStages ) )`（**先除后乘？此处为先除后乘不涉及跨度退化**；`fBandSpan ≤ DL_FLOAT_EPS` 已回默认）。
3. 双向迟滞（关键）：设 `nCur := nActiveStage`，
   - 若 `nReq > nCur`：仅当 `ABS(fErr) ≥ (nCur + 1) × fBandSpan/nStages + fDeadband` 才加级（加 1 级/拍，**不跨级跳变**）；
   - 若 `nReq < nCur`：仅当 `ABS(fErr) ≤ nCur × fBandSpan/nStages − fDeadband` 才减级（减 1 级/拍）。
4. 最小驻留：`_fbTonDwell(IN := _bStageChanged, PT := tMinDwell)`；`_bStageChanged = FALSE` 时驻留计时清零；未到驻留期拒绝换级（信息码 `1A01` 每拍重算）。
5. 轮换：`nActiveStage` 每次变化时 `nRotateOffset := (nRotateOffset + nRotateStep) MOD nStages`（**用条件减法实现，禁负数取余**）；`bRotate=FALSE` 时 `nRotateOffset := 0`。
6. 输出映射：`nOut := (nActiveStage = 0) ? 0 : ((nActiveStage − 1 + nRotateOffset) MOD nStages + 1)`；累积型：`abStage[i] := (i < nOut)`；单级型：`abStage[i] := (i = nOut − 1)`（`nOut = 0` 时全 FALSE）。**用 `FOR i := 0 TO DL_STEP_MAX_STAGES-1` 统一清零后再置位**（避免残留）。
7. 出口派生：`bAtMaxStage := nActiveStage ≥ nStages`；`bAtMinStage := nActiveStage = 0`。

**边界与防错**：
- `nStages = 0` 或 `> DL_STEP_MAX_STAGES` → 钳位 `[1, 8]` + 信息码 `1A02`。
- `fBandSpan ≤ 0` / 非有限 → 回默认 100.0 + 信息码 `1A03`（**必须回默认，否则除零**）。
- `fDeadband ≥ fBandSpan/(2×nStages)` → 迟滞吃掉整级带宽，**注定无法换级**：自动钳到「半级带」+ 信息码 `1A04`（这是本块最容易踩的坑，必须实现）。
- `fSetpoint` / `fActual` 非有限值 → 保持上次级数 + 信息码 `1A05`（不跳级，避免误投切）。
- `tMinDwell < 2×扫描周期`：不可知，注释警告；`T#0S` 允许（等价无驻留，注释说明风险）。
- 相邻级**不得同时为 TRUE**（单级型天然满足；累积型是前缀真，语义不同——断言只对单级型成立，注释写明）。
- `nRotateStep > nStages` → 取模归约。

**故障码表（全信息级，本块不做故障锁存，仅 `1A06` 为参数级锁存）**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0002_1A01` | 信息级 | 最小驻留未到，换级被拒 |
| `0002_1A02` | 信息级 | 级数越界钳位 |
| `0002_1A03` | 信息级 | 级带宽非法回默认 |
| `0002_1A04` | 信息级 | 死区吃掉整级带宽，钳至半级带 |
| `0002_1A05` | 信息级 | 设定/实际非有限值，级数保持 |
| `0002_1A06` | 故障级 | 级数非法（钳位后仍无法运算的极端值），锁存 |

**验收向量**：V1 偏差 0 → 0 级；偏差 25%（4 级带 100）→ 1 级；V2 逐级上升不跨级跳变；V3 死区 5 起作用：偏差在级界 ±5 内不换级；V4 驻留 10 s 内连续请求 → 拒绝 + 1A01；V5 `bCumulative=FALSE` 单级型：仅第 n 级 TRUE；V6 轮换：两次投切后 `nRotateOffset` 递增且输出物理级位移；V7 `fBandSpan=0` → 回默认 + 1A03；V8 死区设大（30）→ 1A04 钳位后半级带。

---

## 第 5 节 码位登记与既有台账核对结论

**核对依据**：`DL_Base/VERSION.md`（`0001_` 段）、`DL_Algo/VERSION.md`（`0002_` 段，01xx~18xx 分组件族段）、`DL_Device/VERSION.md`（`0003_` 段，信息级已用到 `0122`、故障级已用到 `02C0`）、`DL_Motion/VERSION.md`（`0004_` 段，信息级已用到 `0108`、故障级已用到 `0241`）、`DL_Process/VERSION.md`（`0005_` 段，信息级已用到 `0115`、故障级已用到 `0223`）。

| 组件 | 子库 | 信息级段 | 故障级段 | 与既有码冲突核查 |
|---|---|---|---|---|
| `FB_DL_ElectronicGear` | DL_Motion | `0130`~`0132` | `0250`~`0252`、`0299` | 无冲突（Motion 信息级 ≤0108、故障级 ≤0241） |
| `FB_DL_ElectronicCam` | DL_Motion | `0140`~`0142` | `0260`~`0265`、`0298` | 无冲突 |
| `FB_DL_GantrySyncAxis` | DL_Motion | `0150`~`0152` | `0270`~`0274`、`0297` | 无冲突 |
| `FB_DL_TorqueLimitControl` | DL_Motion | `0160`~`0164` | `0280`~`0284`、`0296` | 无冲突 |
| `FB_DL_MarkPositionLatch` | DL_Motion | `0170`~`0171` | `0290`、`0295` | 无冲突 |
| `FC_DL_CalcMoveTime` | DL_Motion | `0180`~`0184` | —（纯函数无故障级） | 无冲突 |
| `FB_DL_ConveyorLineLink` | DL_Process | `0130`~`0133` | `0230`~`0231` | 无冲突（Process 信息级 ≤0115、故障级 ≤0223） |
| `FB_DL_RecipeManager` | DL_Process | `0140`~`0143` | `0240`~`0246` | 无冲突 |
| `FB_DL_LeakTestStation` | DL_Process | `0150`~`0153` | `0250`~`0257` | 无冲突 |
| `FB_DL_MixRecipeControl` | DL_Process | `0160`~`0164` | `0260`~`0265` | 无冲突 |
| `FB_DL_CipCleaningSeq` | DL_Process | `0170`~`0173` | `0270`~`0274` | 无冲突 |
| `FB_DL_BufferMagazine` | DL_Process | `0180`~`0186` | `0280`~`0283` | 无冲突 |
| `I_DL_TowerLight` + `FB_DL_SignalTower` | DL_Device | `0123`~`0126` | `02D0`~`02D1` | 无冲突（Device 信息级 ≤0122、故障级 ≤02C0） |
| `FB_DL_PeakDetector` | DL_Algo | `1901`~`1904` | —（全信息级） | 无冲突（Algo 已用族段 01xx~18xx；`19xx` 为新建族段「峰值检测/极值跟踪族」） |
| `FB_DL_StepController` | DL_Algo | `1A01`~`1A05` | `1A06` | 无冲突（`1Axx` 为新建族段「分级步进控制族」） |

**族段划分声明（须写入各子库 `VERSION.md`）**：
- `DL_Motion` 新增三个族段：`013x/025x`（同步耦合族：齿轮/凸轮/龙门…本轮 3 块占 `0130-0152`）、`016x/028x`（压装与力矩族）、`017x/029x`（标记锁存族 + 兜底码 `029x`）。
- `DL_Process` 新增六个族段：`013x/023x`（线体握手）、`014x/024x`（配方）、`015x/025x`（检漏）、`016x/026x`（混合）、`017x/027x`（CIP）、`018x/028x`（物料调度）。
- `DL_Device` 新增族段：`012x/02Dx`（状态指示族）。
- `DL_Algo` 新增族段：`19xx`（极值跟踪族，全信息级）、`1Axx`（分级步进族）。
- **兜底码约定延续**：每块用本族段末位（`0295`~`0299` / `0231`~`0283` / `02D1` / `1A06`）作「非法状态兜底」，**禁止跨块共用**（R6 教训：族段是 HMI 报警分组契约）。

---

## 第 6 节 终审要点（编码完成后的自检清单）

1. **POU 终结符**：16 个文件全部 `END_FUNCTION_BLOCK` / `END_FUNCTION` / `END_INTERFACE` / `END_TYPE` 成对；机检正则扫描零缺失。
2. **被禁记号零出现**：三类被禁记号（全局变量表访问、外部变量声明、物理地址前缀）在 16 个 `.st` 的代码与注释中**零出现**；文件头红线自检行用语义转述。
3. **状态机**：14 个含状态机的 FB 全部 `ENUM + CASE + ELSE`；2 个连续运算型（`FB_DL_PeakDetector` / `FB_DL_StepController`）在头注释显式声明「无状态机原因」并给出先例（`FB_DL_LowPassFilter`）。
4. **定时器/边沿**：所有 `TON`/`R_TRIG` 在主体最前部；`IF`/`CASE` 内零实例调用。
5. **接口配额**：`FB_DL_ElectronicGear` / `FB_DL_ElectronicCam` / `FB_DL_GantrySyncAxis` / `FB_DL_TorqueLimitControl` / `FB_DL_MarkPositionLatch` 对轴接口每拍 ≤1 次方法调用；`FB_DL_MixRecipeControl` 对 `I_DL_VfdDrive` 每拍 ≤1 次。
6. **数值防御**：全部除法有防零；浮点无 `=` 判等；数组有界；`FOR`/`WHILE` 有上限。
7. **单拍脉冲范式（R24/R25）**：`bDone` / `bPeakEvent` / `bTransferDone` 等单拍标志**不得在同一扫描内被自身清除**（R25：单拍重启标志永不自清）；清除动作必须在实例调用之后或下一拍。
8. **判定互斥**：`bJudgeOk/bJudgeNg`、`bPass/bFail`、`bOk/bNg`、`bRed/bGreen` 全部「先清后置 + 出口断言」。
9. **文档同步（收尾阶段）**：三个子库 `VERSION.md`（Motion 0.3.0→0.4.0、Process 0.3.0→0.4.0、Device 0.3.0→0.4.0、Algo 1.2.0→1.3.0）+ `MANUAL_DL_*.md` + 顶层 `CHANGELOG.md` / `README.md` / `LIBRARY_MANUAL.md` / `INDEX_REGISTRY.json`（104 → 120）。
10. **头注释「开源溯源」**：逐块按 `RAW_NOTES_R8` 对应 S 条目写「原创实现（参考 XXX 分类与参数域）」，**禁止写「改写自 XXX」**（本轮无代码复制）。

---

## 第 7 节 转告编码者的文件头与注释硬性要求（原文转告）

1. **严禁出现被禁记号原文**：三类被禁记号（全局变量表访问、外部变量声明、物理输入 / 输出地址前缀）的**字面量不得出现在任何注释、字符串或头注释自检行中**；一律改用语义描述（例：「本块零全局变量表访问」「零物理地址直写」）。
2. **每个 POU 必须有成对终结符**：`FUNCTION_BLOCK` ↔ `END_FUNCTION_BLOCK`、`FUNCTION` ↔ `END_FUNCTION`、`INTERFACE` ↔ `END_INTERFACE`、`TYPE` ↔ `END_TYPE`。头注释「红线自检」行须写明「终结符成对 ✓」。
3. **头注释七项齐全**：组件名称 / 所属子库 / 当前版本 / 兼容性 / 功能描述 / 开源溯源 / 修订历史；另加「验收向量」「已知限制」「规格偏离（R11）」三段。
4. **每个变量与枚举项同行中文注释**，含单位与取值范围/默认行为；物理量缺单位视为不合格。
5. **错误码常量与故障码表逐条一致**；信息级 / 故障级标注齐全；`bFault` 为排除信息级的派生式。
6. **不得新增任何接口方法**（`I_DL_MotionAxis` 已 6 个达红线；`I_DL_VfdDrive` 已 6 个达红线）；不得修改既有接口文件。

---

## 附：本轮工序与后续

| 阶段 | 内容 | 产出 |
|---|---|---|
| 阶段一（本轮已完成） | 全景盘点：ROADMAP 待办池 217 条未勾选 / 87 条已勾选；各子库码位段核对；注册表 104 组件去重 | 本文件 + `RAW_NOTES_R8.md` |
| 阶段二（本轮已完成） | 源矩阵狩猎：14 次真实检索，T1 两组（T1-4 CODESYS Forge 开组 + T1-6 PLCopen 深化）、T2 两组（T2-1 LGF Math 峰值族 + T2-2 LBP 步进控制族） | 同上 + 第 5 节码位登记 |
| 阶段三（下一会话） | 编码 16 项（四泳道并行）→ 机检 → 终审 | 16 个 `.st` + 机检脚本 |
| 阶段四 | 入库 / 注册 / 文档五件套同步 / 战报 | `INDEX_REGISTRY.json` 120、库版本 v1.7.0、`BATTLE_REPORT_R8.md` |
