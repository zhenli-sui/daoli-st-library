# ROUND PLAN R13 ｜ 第十八件批次作战计划

> **轮次**：Phase 1 第十三轮（R13）｜ **规划时间**：2026-11-15 21:50 ｜ **执行模式**：兜底模式（原生 `daoli-library-director` / `plc-programming-expert` 均 not available）
> **阶段边界（硬性）**：本文件是**阶段一 + 阶段二**的产物。**本阶段不写任何 `.st` 代码，不改 `INDEX_REGISTRY.json`，不改 `*.jsonl`，不改 `VERSION.md` / `MANUAL` / `CHANGELOG`**。编码、注册、文档同步归阶段三及以后。
> **唯一允许的写动作**：本文件与 `RAW_NOTES_R13.md` 落盘于 `_Staging_Raw\2026-11-15\`（新文件，未覆盖旧轮）。
> **主题**：设备健康语言 + Level 0 子族收口 + 本体退化诊断 / Device Health Language · Level-0 Subfamily Closure · Asset Degradation Diagnostics

---

## 第一部分 · 阶段一：盘点

### 1.1 三份状态文件读数

| 指标 | 读数 | 口径 |
|---|---|---|
| 总库累计 | **186 / 10,000（1.86%）** | `INDEX_REGISTRY.json` `total_components=186`、`version=2.1.0`、`last_updated=2026-11-15T20:30:46+08:00` |
| 今日入库 | **160 / 200（80.0%）**，缺口 40 | `ROADMAP.md` §自我进化追踪行；R13 交付 18 件后 → **178 / 200（89.0%）**，缺口 22 |
| JSONL 语料 | **186 条** | 与索引 186、文件 186 三方一致（R12 战报 §二） |
| 库版本 | **v2.1.0** | R13 完成后预期 **v2.2.0**（18 件全部为新增，无破坏性变更 → MINOR） |
| 六子库计数 | Base 38 / MathData 38 / Algo 27 / Device 44 / Motion 17 / Process 22 | 与 `.st` 实扫一致 |

### 1.2 六子库本轮增补与目标计数

| 子库 | 现 | 本轮 | 后 | 说明 |
|---|---|---|---|---|
| `DL_Base` | 38 | +2 | **40** | 位段族收口（跨字旋转）与掩码比较器 |
| `DL_MathData` | 38 | +4 | **42** | CRC8 子族 + 定长串族收口 2 件 + 矩阵子族开族 1 件 |
| `DL_Algo` | 27 | +1 | **28** | 换热器污垢热阻（本体退化算法） |
| `DL_Device` | 44 | +6 | **50** | NE107 健康族（2 契约 + 4 实现），含 §4 唯一剩余 Phase 1 待办 |
| `DL_Motion` | 17 | +1 | **18** | 被动回零监听（R8 明确留扩产项） |
| `DL_Process` | 22 | +4 | **26** | 行业池 P1 四条落地 |
| **合计** | **186** | **+18** | **204** | 六子库**连续第三轮全部有新增** |

### 1.3 源矩阵挖掘覆盖率

| 层 | 已开组 | 未开组 | 覆盖率 | 备注 |
|---|---|---|---|---|
| **T1**（ST 原生） | T1-1、T1-2、T1-3、T1-4、T1-5、T1-6、T1-7、T1-8 = **8** | T1-9（国产平台 FB 手册） | **8/9 = 89%** | T1-9 为「文档版权 + 无 ST 接口」，只能做查漏，不能造件 |
| **T2**（非 ST 借鉴） | T2-1、T2-2、T2-4、T2-5、T2-6、T2-7、T2-8 = **7** | T2-3（西门子编程/风格指南）、T2-9（日系 FB 手册） | **7/9 = 78%** | T2-3 已作为全库规范线使用（无组件行）；T2-9 同 T1-9 |
| **合计** | **15** | **3** | **15/18 = 83%** | — |

**结构性判定（本轮最重要的盘点结论）**：第 5 节台账 16 行**全部为 ◐，已无一行 ☐**。所谓「☐ 组优先」自 R13 起**失去适用对象** —— 唯二真正未触碰的 T1-9 / T2-9 都是「手册清单线」，其价值是**查漏情报**而非组件（已执行，见 `RAW_NOTES_R13.md` §5，查出 2 个真缺口）。故 R13 起改按「**子族收口 + 开新子族**」运行，且「待挖」描述必须拆到可独立验收的粒度（R12 §5.1 方法论勘误的落地）。本轮**新开组 0、新开子族 3**（NE107 诊断族 / LGF Matrix 子族 / LGF CRC8 子族）。

### 1.4 ROADMAP 待办池盘点

| 项 | 数值 |
|---|---|
| 池内条目 | **326 条**（103 基础 + R5 32 + R6 32 + R7 32 + R9 32 + R10 32 + R11 32 + R12 31） |
| 未勾选 | **314 条**（`grep -c "^- \[ \]"` 实测） |
| Phase 1 未勾选 | **1 行 / 2 件**（`§4 I_DL_PowerMeter & FB_DL_ModbusPowerMeter`）—— 全库仅剩这一处 |
| 判定 | **≥30 条门槛：满足（314 ≫ 30），本轮不为凑数扩容 ROADMAP** |

**本轮与池子的对应关系（8/18 件直接勾选既有行，10/18 件按 R9~R12 口径登记新节）**：

| ROADMAP 位置 | 行 | 本轮组件 | 原优先级 |
|---|---|---|---|
| §4 `DL_Device` | `I_DL_PowerMeter` & `FB_DL_ModbusPowerMeter` | A2 + A3（**一行两件**） | Phase 1 收尾 |
| §19.3 半导体 | `FB_DL_EscHeLeakCheck` | C4 | P1 |
| §19.3 半导体 | `FB_DL_ChamberSeasoningTrack` | C5 | P1 |
| §19.4 包装 | `FB_DL_CapperTorqueTrend` | C3 | P1 |
| §19.5 暖通 | `FB_DL_AhuDamperStuckDiag` | A5 | P1 |
| §19.6 过程控制 | `FB_DL_ValveStictionDetect` | A4 | P1 |
| §19.6 过程控制 | `FB_DL_PumpCavitationGuard` | A6 | P2（本轮提前） |
| §19.6 过程控制 | `FB_DL_ReactorJacketDeltaT` | C6 | P1 |

> R12 战报 §六.5 点名的「P1 十四条首批候选」中，本轮吃掉 **6 条 P1 + 1 条 P2**（首选五条里 `ValveStictionDetect` / `ChamberSeasoningTrack` / `CapperTorqueTrend` / `AhuDamperStuckDiag` / `EscHeLeakCheck` **全部命中**）。

### 1.5 本轮 18 个目标组件（锁定结果）

| # | 组件 | 子库 | 来源标签 | 来源层 | 立项依据 |
|---|---|---|---|---|---|
| A1 | `I_DL_DeviceHealth` | DL_Device | `namur-ne107` | T2-8 | 全库 44 个 Device 无统一健康出口 → 契约缺口 |
| A2 | `I_DL_PowerMeter` | DL_Device | `namur-ne107` + `forge-devicereader` | T2-8 / T1-4 | §4 Phase 1 最后一行 |
| A3 | `FB_DL_ModbusPowerMeter` | DL_Device | `namur-ne107` + `modbus-meter` | T2-8 / T1-3 | §4 Phase 1 最后一行（与 A2 同行两件）；数据模型已由 `FB_DL_EnergyMeterAccum` 跑通 |
| A4 | `FB_DL_ValveStictionDetect` | DL_Device | `namur-ne107` + `stiction-diag` | T2-8 / T3 | §19.6 P1 |
| A5 | `FB_DL_AhuDamperStuckDiag` | DL_Device | `rockwell-aoi` + `namur-ne107` | T2-6 / T2-8 | §19.5 P1；借 AOI 三分类诊断 |
| A6 | `FB_DL_PumpCavitationGuard` | DL_Device | `namur-ne107` + `lbp-basic-process` | T2-8 / T2-2 | §19.6 P2（提前） |
| B1 | `FC_DL_BitArrayRotate` | DL_Base | `lgf-bitlogic` | T2-1 | Bit Logic 组「LWORD/多段搬」待挖子族 |
| B2 | `FC_DL_MaskCompare` | DL_Base | `lgf-bitlogic` + `lgf-comparator` | T2-1 | `LGF_BinaryMaskCompare` 语义域（实测目录） |
| B3 | `FC_DL_Crc8` | DL_MathData | `lgf-datahandling` + `oscat-network` | T2-1 / T1-3 | CRC 族缺 8 位（实测 `CalcCRC8` / `CalcCRC8Advanced`） |
| B4 | `FC_DL_StringToLReal` | DL_MathData | `lgf-datahandling` | T2-1 | Data Handling 字符串族收口（R12 明确待挖） |
| B5 | `FC_DL_StringFixedField` | DL_MathData | `lgf-datahandling` | T2-1 | 定长字段填充/对齐（R12 明确待挖）；**R37 样板件** |
| B6 | `FC_DL_Matrix3Inverse` | DL_MathData | `lgf-math` | T2-1 | **Matrix 子族开族**（矩阵勘误 M-E4） |
| C1 | `FB_DL_FoulingResistanceEstimator` | DL_Algo | `oscat-building` + `heat-transfer` | T1-2 | §19.6 P1 `HeatExchangerFoulingTrend` 的算法底座 |
| C2 | `FB_DL_PassiveHomingMonitor` | DL_Motion | `plcopen-motion` | T1-6 | R8 明确「被动回零留扩产」 |
| C3 | `FB_DL_CapperTorqueTrend` | DL_Process | `rockwell-aoi` + `lbp-process` | T2-6 / T2-2 | §19.4 P1 |
| C4 | `FB_DL_EscHeLeakCheck` | DL_Process | `semiconductor-esc` | 自研（源头仅立项理由） | §19.3 P1 |
| C5 | `FB_DL_ChamberSeasoningTrack` | DL_Process | `semiconductor-esc` + `isa-88` | T2-8 | §19.3 P1 |
| C6 | `FB_DL_ReactorJacketDeltaT` | DL_Process | `lbp-process` + `isa-88` | T2-2 / T2-8 | §19.6 P1 |

---

## 第二部分 · 阶段二：狩猎与配额

### 2.1 检索执行记录（6 组，全部只读）

| 组 | 查询意图 | 结论要点 | 支撑件 |
|---|---|---|---|
| S-1 | T2-1 LGF 组内块清单 | 实测含 **Matrix 七件**、`CalcCRC8/CalcCRC8Advanced`、`ShellSort` 三型、`BinaryMaskCompare`、`CountArrayElements/CountBooleanEdges/GetBitStates` | B1~B6 |
| S-2 | T2-8 NAMUR NE107 | 四态 F/C/S/M + 优先级 1/2/3/4（**优先级 ≠ 严重度**）；规范**不规定判据** | A1~A6 |
| S-3 | T2-2 LBP 23 块清单 | 复核 R8 结论：**无混合/定量组**；**无泵/阀/换热器本体诊断块** → 本体退化诊断是本库增量 | A5、C6 |
| S-4 | T2-6 Rockwell P_ValveSO | **Full Stall / Transit Stall / I-O Fault 三分类** + 每告警带确认延时 + Hand 模式为跟踪语义 | A5、C3 |
| S-5 | 阀门黏滞检测方法族 | 四类判据；**Horch 法在含积分/可压缩流体回路失效**；**椭圆法受整定影响、无单一方法 100% 可信** → 本库只用三判据并发且不承诺量化精度 | A4 |
| S-6 | T1-1/T1-2 OSCAT 行为定义 | 无孔板流量行为定义 → **原拟孔板件撤项**；CRC8 未取得块级清单 → **主源改记 T2-1，T1-3 仅记分类事实** | B3、C1 |

> 完整留痕（来源 / URL / 许可证 / 提取点 / 边界 / 三条矩阵勘误 M-E4~M-E6 / 六条反向清单）见 `RAW_NOTES_R13.md`。

### 2.2 T1 / T2 覆盖声明（硬性配额）

| 配额条款 | 本轮证据 | 判定 |
|---|---|---|
| **T1 ≥ 1 个组件族** | **T1-2 OSCAT Building**（C1，行为定义「Q / LMTD / K」组织）｜**T1-3 OSCAT Network**（B3、A3 的「校验/诊断独立成族」与帧语义分类，A3 仅次源）｜**T1-6 PLCopen Motion**（C2，被动回零的参考事件语义）｜**T1-4 CODESYS Forge**（A2 契约三段式，次源） | ✅ **满足（4 个 T1 源）** |
| **T2 ≥ 1 个组件族（硬性）** | **T2-8 NAMUR NE107 —— 首次独立成族，6 件**（A1~A6，全泳道 A 由 NE107 统一健康语言贯穿）｜**T2-1 LGF —— 6 件**（B1~B6，含 **Matrix 子族开族** 与 **CRC8 子族开族**）｜**T2-6 Rockwell AOI —— 2 件**（A5 主源三分类、C3 次源单块四段粒度）｜**T2-2 LBP —— 2 件**（A6、C6） | ✅ **满足（4 个 T2 源，NE107 为全新族）** |
| 「☐ 组优先」 | 已无 ☐ 组可开（见 1.3）；本轮以「**3 个新开子族 + 15 件子族收口**」替代 | ✅ 合规（附理由） |
| 零重复挖掘 | 逐个核对：NE107 从未独立记账；Matrix 子族矩阵从未列（M-E4）；CRC8 从未产出；`FB_DL_EnergyMeterAccum`（NE43）与本轮 A3（NE107）**诊断口径分层不同**，不构成重复 | ✅ |

### 2.3 合规铁律执行情况

1. **只借骨不抄肉**：西门子 LGF/LBP、Rockwell PlantPAx 全部**只看目录/条款/分类**，函数名、块名、参数名、UDT 布局、注释零沿用。18 件头注释统一写「原创实现（参考 XXX 分类与参数域）」。
2. **许可证隔离**：OSCAT（EPL-2.0，归档旧件另受原许可）只取**行为定义**，不取函数体；本轮**未下载任何库文件**，故不存在逐行改写风险。
3. **来源留痕**：逐件在本文件 §3 标注来源标签，并在 `RAW_NOTES_R13.md` 逐条记录来源 / URL / 许可证 / 提取点。
4. **三条撤项/不立**：孔板流量（伪 T1 归属）、CRC8 反射变体（算法族不同）、黏滞互相关/椭圆拟合（红线冲突）—— 全部写入 `RAW_NOTES_R13.md` §4 防下轮重复立项。

---

## 第三部分 · 18 件引脚级规格

### 3.0 全体通用约定（编码前必读，逐条适用）

**① 注释格式（引脚级强制）**
每条 `VAR_INPUT` / `VAR_OUTPUT` / `VAR_IN_OUT` 声明行**必须同行**写：`// 中文名（English） [单位]，范围 x~y，默认 z 行为`。枚举成员行同理。禁止只写中文或只写英文，禁止「同上」。

**② 码位分配纪律（本轮已按**实测扫描**重算，不采信 R12 台账）**
`CODE_SEGMENT_LEDGER_R12.md` 已过期（其记 DL_Device 极大 `0148/0308`、DL_Base-MathData `0124/0219`，实测为 `0155/0315`、`013C/021E`）。本轮码位以全库 186 文件实扫为准：

| 码族 | 实测已占用区间 | 本轮起号 |
|---|---|---|
| `0001`（Base + MathData） | 信息 `0101-0110`、`0112-013C`；故障 `0201-0208`、`0210-021E` | **信息 `013D` ／ 故障 `021F`** |
| `0002`（Base + MathData + Algo） | 按件带 `10xx~21xx` 已占（`2001-2003`、`2010-2012`、`2101-2102`） | **Algo 按件带 `22xx`**（`2201` 起 / 故障 `2210` 起，沿用 +0x0F 约定） |
| `0003`（Device） | 信息 `0101-0155`；故障 `0201-0315` | **信息 `0156` ／ 故障 `0316`** |
| `0004`（Motion） | 信息至 `01C2`；故障至 `02D1` | **信息 `01C3` ／ 故障 `02D2`** |
| `0005`（Process） | 信息至 `01C4`；故障至 `02F2` | **信息 `01C5` ／ 故障 `02F3`** |

**③ 三段式段序纪律（全件统一，防 R42/R39 家族）**
`段 1 参数闸门 → 段 2 定时器/边沿无条件刷新 → 段 3 有效性与数据质量判定 → 段 4 CASE 状态机 → 段 5 业务运算 → 段 6 结论/等级仲裁 → 段 7 出口钳位（R43）→ 段 8 复位通道（**置于 CASE 之前且显式排除故障态**，R39）→ 段 9 码位单一优先级链（全拍只写一次）→ 段 10 保持语义重写（R27）`。
段 8 与段 4 的先后关系是本轮 A 泳道六件的共同高危点。

**④ 验收向量强制集（每件至少四类，缺一类不放行）**
`V-A 域外早退（NaN/Inf/空串/零元素）`｜`V-B 上限截断（R37：写回定长缓冲前预判）`｜`V-C 跨段/跨相时序（R40/R42：定时器断输入、取值复验）`｜`V-D 恢复/复位首拍（R41/R43：恢复不重头、保持值夹域）`。

---

### 3.1 泳道 A —— `DL_Device` · 设备健康语言与本体退化诊断（6 件）

> 泳道主题：**给全库 44 个 Device 装上统一的健康语言**。A1 定契约（NE107 四态 + 优先级），A2/A3 补最后一块 Phase 1 拼图（电表），A4/A5/A6 是三件「设备本体退化」诊断器（阀门黏滞 / 风阀卡滞 / 泵汽蚀）。四件实现块一律以 `E_DL_Ne107Status` 为统一健康出口，**不再各自发明 `bAlarm` 家族**。

---

#### A1 ｜ `I_DL_DeviceHealth`（DL_Device · `I_DL_` 接口契约 + 同文件枚举）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_Device\I_DL_DeviceHealth.st`（同文件承载 `E_DL_Ne107Status`） |
| 类型 | `INTERFACE`（契约件，无码位） |
| 来源标签 | `namur-ne107`、`device-abstraction`、`interface-contract` |
| T 归属 | **T2-8**（公开规范条款，clean-room） |
| 码位 | **无**（接口契约不发布故障码，码位由实现块承担——沿用 `I_DL_TowerLight` 先例） |

**职责**：定义「任何设备都能回答的三个问题」——*我现在健康吗（四态）？我的证据是什么（码 + 来源槽）？这个状态持续多久了（时长 + 锁存）？* 不定义判据（NE107 明确把判据留给实现者），不定义视觉（图标/颜色属 HMI 层）。

**枚举 `E_DL_Ne107Status`（编号即优先级，数值小者优先）**

| 成员 | 值 | 中文注释（含英文） |
|---|---|---|
| `eFailure` | 0 | 失效：信号不可信，须立即处理 / Failure, signal invalid, immediate action |
| `eCheckFunction` | 10 | 功能检查：回路测试/仿真/标定中，信号**暂时**无效 / Function check, signal temporarily invalid |
| `eMaintenanceReq` | 20 | 需要维护：仍有效但已劣化，排入维护计划 / Maintenance required, still valid but degraded |
| `eOutOfSpec` | 30 | 超出规格：工艺/环境越界，测量不确定度上升 / Out of specification, uncertainty increased |
| `eOk` | 40 | 正常 / OK, no diagnostic active |
| `eUnknown` | 99 | 未知：尚未取得有效数据（冷启动首拍）/ Unknown, no valid data yet |

> 编号为**优先级序**（0 最优先），**不等于** NE107 官方图标排列顺序，头注释必须写明这句，防后人「按图改号」。

**属性段（10 条，全部只读 GET）**

| 属性 | 类型 | 说明（中 / EN） |
|---|---|---|
| `eHealth` | `E_DL_Ne107Status` | 当前健康态 / Current health state |
| `uDiagCode` | `UDINT` | 当前诊断码，0=无码，段位 `16#0003_xxxx` / Active diagnostic code |
| `uSourceId` | `UINT` | 证据来源槽号 0~65535（0=未定义；实现块自定义槽含义） / Evidence source slot |
| `tDuration` | `TIME` | 当前态已持续时长 [ms]，态切换即清零 / Duration of the current state |
| `bLatched` | `BOOL` | 是否锁存（TRUE 时只能 `CmdReset` 退出） / Latched flag |
| `bDataValid` | `BOOL` | 本拍数据是否可用（**与健康态正交**：健康但数据陈旧 = TRUE 健康 + FALSE 数据） / Data valid this scan |
| `fQuality` | `REAL` | 数据质量因子 0.0~1.0（1.0 最佳，仅作趋势参考，不作判据） / Quality factor |
| `nCodeHistory` | `UINT` | 历史码计数（仅计数不存表） / Diagnostic code change count |
| `sDeviceClass` | `STRING(16)` | 设备类别短名，如 `'VALVE'`、`'METER'`（HMI 分组用，**定长不超 16**） / Device class tag |
| `bSimulated` | `BOOL` | 仿真/强制模式（对应 `eCheckFunction` 的典型来源） / Simulation or forced mode |

**方法段（2 个，≤6 红线内）**

| 方法 | 返回 | 入参 | 语义 |
|---|---|---|---|
| `CmdAck` | `BOOL` | 无 | 应答 `eMaintenanceReq` / `eOutOfSpec`（**不得应答 `eFailure`**，返回 FALSE） |
| `CmdReset` | `BOOL` | 无 | 复位锁存；仅 `bLatched=TRUE` 时受理，否则 FALSE |

**编码要点**
1. 接口**不得**声明 `VAR` 段（IEC 接口只允许属性与方法）；`E_DL_Ne107Status` 与接口同文件、头注释写「归属说明」（公约 0.11 同文件发布惯例）。
2. 属性返回值类型必须与实现块 PROPERTY 完全一致（`UINT` / `UDINT` / `TIME` / `STRING(16)` 逐字对齐），否则三平台编译行为不一致。
3. 枚举成员一律 `:=`（**R33**），禁止单冒号。

---

#### A2 ｜ `I_DL_PowerMeter`（DL_Device · `I_DL_` 接口契约）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_Device\I_DL_PowerMeter.st` |
| 类型 | `INTERFACE`（契约件） |
| 来源标签 | `namur-ne107`、`forge-devicereader`、`meter-contract` |
| T 归属 | **T2-8**（健康出口）+ **T1-4**（契约三段式次源） |
| 码位 | **无** |
| ROADMAP | §4 行 131（与 A3 同一行） |

**职责**：三相电表的**读侧契约**——电量、电能质量、累计电能、健康。**不含**写侧（费率/需量窗口写入属配置层，另件）与通信调度（归 `FB_DL_ModbusPollMaster`）。

**属性段（11 条）**

| 属性 | 类型 | 说明（中 / EN） |
|---|---|---|
| `eState` | `E_DL_PowerMeterState`（同文件枚举） | 计量状态 / Metering state |
| `eHealth` | `E_DL_Ne107Status` | NE107 健康态（引用 A1 类型，**不重复声明**） / NE107 health |
| `uDiagCode` | `UDINT` | 诊断码 / Diagnostic code |
| `fVoltageAvg` | `REAL` | 三相平均相电压 [V]，范围 0~400 / Average phase voltage |
| `fCurrentAvg` | `REAL` | 三相平均电流 [A]，范围 0~10000 / Average phase current |
| `fActivePowerTotal` | `REAL` | 三相总有功 [kW]，**有符号**（负=反送） / Total active power, signed |
| `fReactivePowerTotal` | `REAL` | 三相总无功 [kvar] / Total reactive power |
| `fPowerFactorTotal` | `REAL` | 总功率因数 [-]，范围 −1.0~1.0 / Total power factor |
| `fFrequency` | `REAL` | 电网频率 [Hz]，范围 45~65 / Grid frequency |
| `fEnergyImport` | `LREAL` | 正向累计电能 [kWh] / Import energy |
| `fEnergyExport` | `LREAL` | 反向累计电能 [kWh] / Export energy |
| `fDemandPeak` | `REAL` | 历史峰值需量 [kW]，仅复位可清 / Peak demand |

**方法段（3 个）**：`CmdResetEnergy : BOOL`（清累计，需 `bLatched=FALSE`）、`CmdReset : BOOL`（复位锁存）、`CmdAck : BOOL`（应答维护/越规）。

**枚举 `E_DL_PowerMeterState`**：`eIdle:=0`（未使能）/ `eSampling:=10`（正常计量）/ `eDegraded:=20`（越规但可读）/ `eFault:=99`（锁存）。

**编码要点**：接口件只写契约，`E_DL_PowerMeterState` 与本接口同文件；`eHealth` 的类型 `E_DL_Ne107Status` **必须来自 A1 文件**，禁止在本文件重复定义（重复定义会导致跨文件同名异型，**R33 家族超集风险**）。

---

#### A3 ｜ `FB_DL_ModbusPowerMeter`（DL_Device · `FB_DL_`）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_Device\FB_DL_ModbusPowerMeter.st` |
| 类型 | `FUNCTION_BLOCK`，实现 `I_DL_PowerMeter` |
| 来源标签 | `namur-ne107`、`modbus-meter`、`meter-contract` |
| T 归属 | **T2-8 主源** ／ T1-3 次源（Modbus 寄存器/帧语义分类） |
| 码位 | **信息 `16#0003_0156~015B`（6）／ 故障 `16#0003_0316~031B`（6）** |
| 依赖 | `E_DL_ByteOrder`（DL_MathData 既有）、`E_DL_Ne107Status`（A1）、`Standard: R_TRIG / TON` |

**职责**：把**轮询主站已读入的原始寄存器**拼装成电表数据模型：三相电压/电流标定、有功/无功/视在换算、功率因数复算与交叉校验、电能 32 位拼装与单调性、需量窗口、电能质量分级（过压/欠压/缺相/THD/功率因数），最终输出 NE107 四态 + 单一诊断码。
**边界（写进头注释）**：① **不做通信调度**（何时读寄存器由 `FB_DL_ModbusPollMaster` 决定，本件按「冻结值更新节拍」被调用）；② **不做费率/分时**；③ 与 `FB_DL_EnergyMeterAccum`（NE43 口径，只做累计与需量）**分层**：本件是「全量数据模型 + 质量分级」，累计算法可直接复用其口径但**不得复制其码位**（NE43 与本件 NE107 是两套语言，头注释须写清两者关系）。

**VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位/范围 | 说明（中 / EN） |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 冻结计量与窗口 / Enable, freezes metering |
| `bReset` | BOOL | — | 上升沿 | 复位窗口/峰值/锁存 / Rising edge resets |
| `auVoltageRaw` | `ARRAY[1..3] OF UINT` | — | LSB | 三相相电压原始值 [LSB]，0.1 V/LSB / Raw phase voltages |
| `auCurrentRaw` | `ARRAY[1..3] OF UINT` | — | LSB | 三相电流原始值 [LSB]，0.01 A/LSB / Raw phase currents |
| `iActivePowerRaw` | DINT | — | LSB | 总有功原始值 [LSB]，0.001 kW/LSB，**有符号** / Raw total active power, signed |
| `uReactivePowerRaw` | UINT | — | LSB | 总无功原始值 [LSB]，0.001 kvar/LSB / Raw reactive power |
| `uEnergyImportHi` | UINT | — | LSB | 正向电能高字 / Import energy high word |
| `uEnergyImportLo` | UINT | — | LSB | 正向电能低字 / Import energy low word |
| `uEnergyExportHi` | UINT | — | LSB | 反向电能高字 / Export energy high word |
| `uEnergyExportLo` | UINT | — | LSB | 反向电能低字 / Export energy low word |
| `uFreqRaw` | UINT | — | LSB | 频率原始值 [LSB]，0.01 Hz/LSB / Raw frequency |
| `uThdVoltRaw` | UINT | — | LSB | 电压总谐波畸变原始值 [LSB]，0.1 %/LSB / Raw voltage THD |
| `uThdCurrRaw` | UINT | — | LSB | 电流总谐波畸变原始值 [LSB]，0.1 %/LSB / Raw current THD |
| `eWordOrder` | `E_DL_ByteOrder` | `eAbcd` | — | 32 位字序约定 / Word order convention |
| `fVoltPerLsb` | REAL | 0.1 | V/LSB | 电压标定，域 >0 / Voltage scale, >0 |
| `fCurrPerLsb` | REAL | 0.01 | A/LSB | 电流标定，域 >0 / Current scale, >0 |
| `fKwhPerLsb` | REAL | 0.1 | kWh/LSB | 电能标定，域 >0 / Energy scale, >0 |
| `fVoltNominal` | REAL | 220.0 | V | 额定相电压，范围 100~400 / Nominal phase voltage |
| `fVoltTolRatio` | REAL | 0.10 | — | 电压允许偏差比 0~0.5（默认 ±10%） / Voltage tolerance ratio |
| `fPfLimit` | REAL | 0.85 | — | 功率因数下限 0.5~1.0 / Power factor lower limit |
| `fThdLimit` | REAL | 5.0 | % | 谐波上限 1.0~50.0 / THD limit |
| `fLightLoadRatio` | REAL | 0.02 | — | 轻载判据（电流低于额定的比例），轻载不做 PF/THD 判 / Light-load ratio |
| `tDemandWindow` | TIME | `T#15M` | ms | 需量窗口，域 ≥1 s / Demand window |
| `tStaleTimeout` | TIME | `T#5S` | ms | 数据陈旧超时，超时判 **Failure** / Stale-data timeout |

**VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明（中 / EN） |
|---|---|---|---|
| `bValid` | BOOL | — | 数据模型本拍有效 / Model valid this scan |
| `eHealth` | `E_DL_Ne107Status` | — | NE107 健康态 / NE107 health |
| `uDiagCode` | UDINT | — | 当前诊断码（单一优先级链产出） / Active diagnostic code |
| `uErrorId` | UDINT | — | 末次故障码（仅故障级，R21） / Last fault code, faults only |
| `bError` | BOOL | — | 故障锁存 / Fault latched |
| `fVoltageAvg` / `fCurrentAvg` | REAL | V / A | 三相平均 / Phase averages |
| `afVoltagePhase` | `ARRAY[1..3] OF REAL` | V | 分相电压 / Per-phase voltages |
| `fActivePowerTotal` | REAL | kW | 总有功（有符号） / Total active power |
| `fReactivePowerTotal` | REAL | kvar | 总无功 / Total reactive power |
| `fApparentPower` | REAL | kVA | 视在功率 √(P²+Q²) / Apparent power |
| `fPowerFactorTotal` | REAL | — | P/S（**用复算值，不取表值**，与表值偏差 >3% 置信息码） / Recomputed PF |
| `fFrequency` | REAL | Hz | 频率 / Frequency |
| `fEnergyImport` / `fEnergyExport` / `fEnergyNet` | LREAL | kWh | 累计电能 / Accumulated energy |
| `fThdVoltageMax` / `fThdCurrentMax` | REAL | % | 三相 THD 最大 / Max THD |
| `fDemandAvg` / `fDemandPeak` | REAL | kW | 窗内平均需量 / 峰值需量 / Demand |
| `bPhaseLoss` | BOOL | — | 缺相（任一相电压 < 20% 额定且另两相正常） / Phase loss |
| `bReversePower` | BOOL | — | 反送电（有功为负且绝对值 > 5% 额定） / Reverse power |
| `uMeterSwapCount` | UDINT | 次 | 换表/清零识别次数 / Meter swap count |

**状态机（4 态，`E_DL_PowerMeterPhase` 同文件）**

```
eIdle(0) --bEnable 且标定合法--> eSampling(10)
eSampling --越规(过压/欠压/THD/PF/缺相)--> eDegraded(20) --恢复正常拍--> eSampling
eSampling --陈旧超时 / 码为故障级--> eFault(99) --bReset 且原因消失--> eIdle
ELSE --> 置 0319（兜底）并进 eFault
```
> `eDegraded` 与 `eFault` 的分界：**越规不改数据可信度 → Degraded**；**数据不可信（陈旧/自相矛盾/标定非法）→ Fault**。这是 NE107 的 S 与 F 之别，头注释必须写死。

**故障码表**

| 码 | 级别 | 含义 | NE107 映射 |
|---|---|---|---|
| `16#0003_0156` | 信息 | 三相电压不平衡度 > 2% 但未越限 / Voltage unbalance above 2% within limits | `eOk` |
| `16#0003_0157` | 信息 | 需量窗口 < 1 s 已按 1 s 兜底 / Demand window clamped to 1 s | `eOk` |
| `16#0003_0158` | 信息 | 字序参数改变，首拍强制重载累计基准 / Word order changed, baseline reloaded | `eOk` |
| `16#0003_0159` | 信息 | 轻载下 PF/THD 越限被抑制（电流 < 轻载比） / PF or THD suppressed at light load | `eOk` |
| `16#0003_015A` | 信息 | 复算功率因数与表值偏差 > 3% / Recomputed PF differs by 3% | `eDegraded` |
| `16#0003_015B` | 信息 | 频率越限但在 ±0.5 Hz 内（判 Degraded 不判 Fault） / Frequency slightly out | `eDegraded` |
| `16#0003_0316` | 故障 | 电压/电流/电能标定非正（除零隐患） / Non-positive scale | `eFailure` |
| `16#0003_0317` | 故障 | 原始寄存器全零且超陈旧超时（表掉线） / All-zero registers past stale timeout | `eFailure` |
| `16#0003_0318` | 故障 | 电能累计回退（换表或清零），已重载基准 / Energy regression, baseline reloaded | `eMaintenanceReq` |
| `16#0003_0319` | 故障 | 非法状态兜底 / Illegal state fallback | `eFailure` |
| `16#0003_031A` | 故障 | 三相电流全零而有功非零（数据自相矛盾） / Zero current with non-zero power | `eFailure` |
| `16#0003_031B` | 故障 | 有功功率拼装结果非有限 / Non-finite active power | `eFailure` |

**验收向量**
- **V1 基本换算**：三相 2200 LSB（0.1 V/LSB）→ `fVoltageAvg=220.0`；三相 1000 LSB（0.01 A/LSB）→ 10.0 A；有功 50000 LSB（0.001 kW）→ 50.0 kW。
- **V2 需量**：15 min 窗、50 kW 恒定、满窗 → `fDemandAvg=50.0`、`fDemandPeak=50.0`。
- **V3（V-C 跨相时序）**：使能中 → 摘掉原始值（全零）→ 4 s 时仍 `eDegraded`（未超时）；5 s 后转 `eFault`+`0317`；**恢复供数后必须 `bReset` 才回 `eSampling`**（锁存语义）。
- **V4（V-D 首拍）**：上电首拍 `fEnergyImport=0`、`bValid=FALSE`、`eHealth=eUnknown`，**不得**把首拍原始值当作换表（首拍只装基准，不判回退）。
- **V5（V-A 域外）**：`fKwhPerLsb=0` → `0316` 锁存，`fEnergyImport` 保持上次值且**在有效域内**（R43）。

**编码注意**：`uDiagCode` 只允许段 9 单一优先级链写一次（F > C > M > S 序）；`bError` 只由故障级码派生（R21：信息码不进 `bError`）。

---

#### A4 ｜ `FB_DL_ValveStictionDetect`（DL_Device · `FB_DL_`）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_Device\FB_DL_ValveStictionDetect.st` |
| 来源标签 | `namur-ne107`、`stiction-diag`、`asset-health` |
| T 归属 | **T2-8 主源**（健康分级）；判据族参考公开文献仅作立项理由（T3） |
| 码位 | **信息 `16#0003_015C~015E`（3）／ 故障 `16#0003_031D~031F`（3）** |
| 依赖 | `E_DL_Ne107Status`（A1）、`Standard: TON / R_TRIG` |

**职责**：用**常规运行数据**（指令 OP 与阀位 PV，无需激励试验）在线判阀门黏滞，输出**黏滞等级 + 黏滞带估计 + 停滞事件计数**，并把「需要维护」语义交给 NE107 `eMaintenanceReq`。
**三条判据（并发，缺一不升级）**：ⓐ **方向性滞后**：上升行程与下降行程在同一 OP 处 PV 之差 → 黏滞带 `fDeadbandEst`；ⓑ **停滞拍**：`|ΔOP| > fStallThr` 而 `|ΔPV| < fMoveThr` 持续 `tStallTime`；ⓒ **反转确认延迟**：方向反转后到 PV 开始移动的时间 > `tReverseTime`。
**边界（头注释必须写）**：① **不做互相关**（需长窗 FFT，违 O(1) 内存）；② **不做椭圆拟合**（需二维迭代，不可逐拍复算）；③ **输出为趋势判据，不是黏滞量的计量级量化**（文献明确无单一方法 100% 可信）；④ 不替代定位器自诊断，不做补偿。

**VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位/范围 | 说明（中 / EN） |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 时窗口冻结 / Enable, freezes the window |
| `bReset` | BOOL | — | 上升沿 | 复位锁存与统计 / Rising edge resets |
| `fCmd` | REAL | — | % 0~100 | 阀门指令（OP） 0~100% / Valve command |
| `fPos` | REAL | — | % 0~100 | 阀位反馈（PV） 0~100% / Valve position feedback |
| `bPosValid` | BOOL | TRUE | — | 反馈有效性；FALSE 时诊断挂起（**非故障**） / Feedback validity |
| `fMoveThr` | REAL | 0.5 | % | 判「阀位在动」的位移阈 0.1~5.0 / Move threshold |
| `fStallThr` | REAL | 1.0 | % | 判「指令在变」的变化阈 0.2~10.0 / Command change threshold |
| `tStallTime` | TIME | `T#2S` | ms | 停滞持续判据 100 ms~60 s / Stall duration |
| `tReverseTime` | TIME | `T#1S` | ms | 反转确认允许延迟 100 ms~30 s / Reverse confirmation delay |
| `tWindow` | TIME | `T#60S` | ms | 分析窗长 10 s~30 min / Analysis window |
| `nMinSamples` | INT | 30 | 个 | 窗口最少有效样本 5~1000 / Minimum samples |
| `fDeadbandMax` | REAL | 5.0 | % | 黏滞带上限（超此判 Severe） 0.5~20.0 / Deadband upper limit |
| `fDeadbandModerate` | REAL | 2.0 | % | 黏滞带中限（超此判 Moderate） 0.1~`fDeadbandMax` / Moderate limit |

**VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明（中 / EN） |
|---|---|---|---|
| `eHealth` | `E_DL_Ne107Status` | — | 健康态（`eNone`→`eOk`；`eSlight/Moderate`→`eMaintenanceReq`；`eSevere`→`eOutOfSpec`） / NE107 health |
| `uDiagCode` | UDINT | — | 诊断码 / Diagnostic code |
| `uErrorId` | UDINT | — | 末次故障码 / Last fault code |
| `bError` | BOOL | — | 故障锁存 / Fault latched |
| `eStiction` | `E_DL_StictionLevel`（同文件） | — | 黏滞等级 `eNone/eSlight/eModerate/eSevere` / Stiction level |
| `fDeadbandEst` | REAL | % | 黏滞带估计值 0~100 / Estimated stiction band |
| `fHysteresisRatio` | REAL | — | 方向性滞后的归一指标 = 黏滞带/全行程 0~1 / Normalised hysteresis |
| `nStallCount` | UDINT | 次 | 停滞事件累计（**锁存，仅复位清**） / Stall event count |
| `tSinceLastStall` | TIME | ms | 距上次停滞事件时长 / Time since last stall |
| `nSampleCount` | UINT | 个 | 本窗有效样本数 / Valid samples in window |
| `bStictionSuspect` | BOOL | — | 嫌疑位（任一判据成立即 TRUE，供 HMI 早期提示） / Suspect flag |

**状态机（5 态，`E_DL_StictionPhase` 同文件）**
```
eIdle(0) --使能且参数合法--> eCollect(10) --样本数≥nMinSamples--> eAnalyze(20) --> eVerdict(30) --> eCollect
eCollect/eAnalyze --反馈失效 bPosValid=FALSE--> eSuspend(40) --恢复且窗口重建--> eCollect
任何态 --参数非法/非有限--> eFault(99)
ELSE --> 031F 兜底
```

**故障码表**

| 码 | 级别 | 含义 |
|---|---|---|
| `16#0003_015C` | 信息 | 窗口样本不足，未评级（保持上次等级，R27 保持语义） / Insufficient samples, hold last level |
| `16#0003_015D` | 信息 | 反馈失效导致诊断挂起（非故障；恢复后窗口重建） / Suspended due to invalid feedback |
| `16#0003_015E` | 信息 | 阀位长期静止（工艺停机），停滞判据被抑制 / Long static position, stall suppressed |
| `16#0003_031D` | 故障 | 指令或阀位非有限值（NaN/Inf） / Non-finite command or position |
| `16#0003_031E` | 故障 | 阈值参数非法（`fDeadbandMax ≤ 0` 或 `Moderate ≥ Max`） / Illegal thresholds |
| `16#0003_031F` | 故障 | 非法状态兜底 / Illegal state fallback |

**验收向量**
- **V1（正常阀）**：OP 斜坡 0→100、PV 跟随滞后 0.3% → `eStiction=eNone`、`fDeadbandEst≈0.3`、`nStallCount=0`。
- **V2（黏滞阀）**：OP 每 2 s 步进 2%、PV 每 4 s 跳 3%（阶梯跟随）→ 判据 ⓐⓑⓒ 全成立 → `eStiction=eSevere`、`nStallCount≥2`、`eHealth=eOutOfSpec`。
- **V3（V-C 跨相复验，**R42 高危点**）**：`eAnalyze` 内缓存了 40 个样本 → 进入 `eVerdict` 当拍 `bPosValid` 被置 FALSE → **必须不发布新等级**（保持上次值 + `015D`），**不得**用缓存样本直接出结论。
- **V4（V-D 恢复首拍）**：挂起恢复首拍样本数必须从 0 重建，**不得**沿用挂起前窗口（R41 精神），且恢复首拍不得判 `eSevere`。
- **V5（V-A 域外）**：`fCmd=NaN` → `031D`，`fDeadbandEst` 保持上次值并**夹进 0~100**（R43）。

---

#### A5 ｜ `FB_DL_AhuDamperStuckDiag`（DL_Device · `FB_DL_`）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_Device\FB_DL_AhuDamperStuckDiag.st` |
| 来源标签 | `rockwell-aoi`、`namur-ne107`、`damper-diag` |
| T 归属 | **T2-6 主源**（三分类诊断的粒度与「判据须带确认延时」）+ **T2-8**（健康出口） |
| 码位 | **信息 `16#0003_0160~0161`（2）／ 故障 `16#0003_0321~0325`（5）** |
| 依赖 | `E_DL_Ne107Status`（A1）、`Standard: TON / R_TRIG` |

**职责**：风阀/电动执行器卡滞诊断，把「不动作」拆成**三种不同失效机理**（这是本件最大的价值，来自 T2-6 结构借用）：
- **Full Stall（完全不动）**：指令已变、执行器已得电，但阀位**一步未动** → 机械卡死/接线断/执行器死。
- **Transit Stall（动而未达）**：离位了但**没到目标** → 摩擦力过大/气压不足/限位错。
- **I/O Fault**：反馈信号本身失效 → 传感/接线/模块问题（**不是阀的问题**）。
外加两个工艺级判据：**Deviation（稳态偏差超限）** 与 **Slow（行程时间超标称 1.5 倍）**。

**VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位/范围 | 说明（中 / EN） |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能 / Enable |
| `bReset` | BOOL | — | 上升沿 | 复位锁存 / Rising edge resets |
| `fCmd` | REAL | — | % 0~100 | 阀位指令 0~100% / Damper command |
| `fPosFb` | REAL | — | % 0~100 | 阀位反馈 0~100% / Position feedback |
| `bFbValid` | BOOL | TRUE | — | 反馈有效（AI 断线时为 FALSE） / Feedback validity |
| `bLimitOpen` | BOOL | FALSE | — | 开到位限位（无则恒 FALSE） / Open limit |
| `bLimitClose` | BOOL | FALSE | — | 关到位限位（无则恒 FALSE） / Close limit |
| `tTravelNominal` | TIME | `T#30S` | ms | 全行程标称时间 1 s~10 min / Nominal full travel time |
| `fTolPos` | REAL | 3.0 | % | 到位容差 0.5~10.0 / In-position tolerance |
| `fDevLimit` | REAL | 10.0 | % | 稳态偏差上限 1.0~50.0 / Steady-state deviation limit |
| `tDevDelay` | TIME | `T#10S` | ms | 偏差确认延时 0.5~300 s / Deviation confirmation delay |
| `fDriftThr` | REAL | 0.2 | % | 判「有位移」的阈值 0.05~2.0 / Movement threshold |
| `tStallTime` | TIME | `T#5S` | ms | 停滞判据时长 0.5~120 s / Stall duration |
| `tIoFaultTime` | TIME | `T#3S` | ms | 反馈失效持续判据 0.2~60 s / I-O fault duration |
| `fSlowRatio` | REAL | 1.5 | — | 判 Slow 的行程倍率 1.1~3.0 / Slow ratio |

**VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明（中 / EN） |
|---|---|---|---|
| `eHealth` | `E_DL_Ne107Status` | — | `eOk` / `eMaintenanceReq`(Slow,Deviation) / `eFailure`(FullStall,TransitStall,IoFault) |
| `uDiagCode` | UDINT | — | 诊断码 / Diagnostic code |
| `uErrorId` / `bError` | UDINT / BOOL | — | 故障码与锁存（仅 Failure 类置位） |
| `eDiag` | `E_DL_DamperDiag`（同文件） | — | `eOk/eSlow/eDeviation/eFullStall/eTransitStall/eIoFault` |
| `fDeviation` | REAL | % | 指令-反馈偏差（**有符号**，正=开不足） / Signed deviation |
| `tLastTravel` | TIME | ms | 末次行程实测时间 / Last travel time |
| `nStallCount` / `nTravelCount` | UDINT | 次 | 卡滞/行程计数（锁存） / Stall and travel counters |
| `bAtOpen` / `bAtClose` | BOOL | — | 到位指示（含容差与限位或判） / In-position flags |

**状态机（5 态）**
```
eIdle(0) → eMoving(10)：|fCmd−fPosFb| > fTolPos 且 bCmdChanged
eMoving → eSettling(20)：|偏差| ≤ fTolPos（进入确认窗）
eSettling → eMoving（再次超差）｜→ eIdle（确认窗满且无判据）
eMoving/eSettling → eVerdict(30)：任一判据成立 → 出结论后回 eIdle（结论**保持**，R27）
任何态 → eFault(99)：参数非法/非法状态
```
> **`eMoving` 的进出必须与 `tTravelNominal` 挂钩**：进入时启行程定时器（`IN := (eState = eMoving)`），离开时**必须断输入一拍**（R40：`bTravelBreak` 标志在 TON 调用后自清）。

**故障码表**

| 码 | 级别 | 含义 | NE107 |
|---|---|---|---|
| `16#0003_0160` | 信息 | 无反馈运行（`bFbValid` 恒 FALSE 且未超 `tIoFaultTime`），仅用限位/时间判据 / Open-loop run | `eOk` |
| `16#0003_0161` | 信息 | 行程时间超前标称 1.5 倍但未卡死 → `eSlow` / Travel slower than nominal | `eMaintenanceReq` |
| `16#0003_0321` | 故障 | **Full Stall**：指令已变、位移 < `fDriftThr` 持续 `tStallTime` / Full stall | `eFailure` |
| `16#0003_0322` | 故障 | **Transit Stall**：已离位但未达目标，超 `tTravelNominal×fSlowRatio` / Transit stall | `eFailure` |
| `16#0003_0323` | 故障 | **Deviation**：稳态偏差 > `fDevLimit` 持续 `tDevDelay` / Steady deviation | `eMaintenanceReq`（**不置 bError**，见下） |
| `16#0003_0324` | 故障 | **I/O Fault**：`bFbValid=FALSE` 持续 `tIoFaultTime` / Feedback lost | `eFailure` |
| `16#0003_0325` | 故障 | 非法状态兜底 / Illegal state fallback | `eFailure` |

> **码位级裁定（写进头注释）**：`0323` 落在故障带 `02xx` 但语义是「维护请求」，**不置 `bError`**。这是本库首次出现「故障带码 + 不置 bError」的组合，必须在头注释用一行说明理由（`bError` 表示「不可继续运行」，偏差超限仍可运行），并在 MANUAL 的故障码表加「是否置 bError」列。

**验收向量**
- **V1 Full Stall**：`fCmd` 0→60%，`fPosFb` 恒 0 → 5 s 后 `eDiag=eFullStall`、`0321`、`eHealth=eFailure`。
- **V2 Transit Stall**：`fCmd` 0→100%，`fPosFb` 停在 45% → 45 s 后（30 s×1.5）`eTransitStall`、`0322`。
- **V3（V-C R40 定时器跨段）**：连续两次行程（第一次 20 s 完成、第二次 20 s 完成，标称 30 s）→ **行程定时器不得累加到 40 s 判超时**；断输入拍必须存在。
- **V4（V-D 恢复首拍）**：`bFbValid` 由 FALSE 恢复 → 首拍只做基准重装，**不判** Full Stall（否则必误报）。
- **V5（V-A 域外）**：`fCmd=120%`（>100）→ 钳到 100 并置 `0160`? **不得**：按「域外不静默」，`fCmd` 超 100 钳位后置 `0161`? → 最终裁定：超域钳位并置**信息码 `0161`**，同时在头注释写明「钳位不静默」。

---

#### A6 ｜ `FB_DL_PumpCavitationGuard`（DL_Device · `FB_DL_`）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_Device\FB_DL_PumpCavitationGuard.st` |
| 来源标签 | `namur-ne107`、`lbp-basic-process`、`pump-diag` |
| T 归属 | **T2-8**（分级）+ **T2-2**（「命令-监视-判定」三段分层，次源） |
| 码位 | **信息 `16#0003_0164~0165`（2）／ 故障 `16#0003_0326~0329`（4）** |
| 依赖 | `E_DL_Ne107Status`（A1）、`Standard: TON / R_TRIG` |

**职责**：泵汽蚀判据与**降速请求**（不直接给变频器频率，只给 `fDerateRatio`，执行归上层 `FB_DL_RateLimiter` / `FB_DL_VfdGeneric`）。三判据：**流量偏低 + 扬程跌落 + 振动/电流波动**，三者同拍成立才升级为锁存故障，单成立只到「嫌疑」。
**边界**：不做 NPSH 计算（需介质饱和蒸汽压与吸入侧压力，属选型设计而非在线判据）；振动阈值默认取 ISO 10816 C 区边界 `4.5 mm/s`（**公知阈值，引脚可改，头注释注明出处与「仅参考」定位**）；不声称符合 ISO 10816 认证。

**VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位/范围 | 说明（中 / EN） |
|---|---|---|---|---|
| `bEnable` / `bReset` | BOOL | — | — | 使能 / 上升沿复位 / Enable and rising-edge reset |
| `bRunning` | BOOL | — | — | 泵运行中（停泵时全部判据抑制） / Pump running |
| `fFlow` / `fHead` | REAL | — | m³/h, m | 实测流量与扬程 / Flow and head |
| `fVibration` | REAL | — | mm/s RMS | 振动速度有效值 0~50 / Vibration RMS velocity |
| `fCurrent` | REAL | — | A | 电机电流 0~10000 / Motor current |
| `fFlowNominal` / `fHeadNominal` | REAL | — | m³/h, m | 额定流量与扬程（域 >0） / Nominal flow and head |
| `fFlowLowRatio` | REAL | 0.60 | — | 流量低于额定的比例 0.2~0.95 / Low-flow ratio |
| `fHeadDropRatio` | REAL | 0.15 | — | 扬程跌落比例 0.05~0.5 / Head-drop ratio |
| `fVibLimit` | REAL | 4.5 | mm/s | 振动上限（ISO 10816 C 区边界，可改） 1~20 / Vibration limit |
| `fCurrentRippleLimit` | REAL | 0.15 | — | 电流波动率上限 0.02~0.5 / Current ripple limit |
| `tRippleWindow` | TIME | `T#2S` | ms | 电流波动统计窗 0.5~30 s / Ripple window |
| `tConfirm` | TIME | `T#3S` | ms | 三判据同拍持续判据 0.5~30 s / Confirmation time |
| `tHoldOff` | TIME | `T#30S` | ms | 降速后抑制判据的时长 5 s~10 min / Hold-off after derate |
| `fDerateStep` | REAL | 0.10 | — | 每次降速步长 0.02~0.3 / Derate step |

**VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明（中 / EN） |
|---|---|---|---|
| `eHealth` | `E_DL_Ne107Status` | — | `eOk` / `eOutOfSpec`（嫌疑）/ `eFailure`（锁存） |
| `uDiagCode` / `uErrorId` / `bError` | UDINT / UDINT / BOOL | — | 诊断码 / 故障码 / 锁存 |
| `bCavitation` | BOOL | — | 汽蚀确认（三判据同拍成立） / Cavitation confirmed |
| `bDerateRequest` | BOOL | — | 降速请求（保持语义，非单拍，R27） / Derate request, held |
| `fDerateRatio` | REAL | — | 降速比例 0.0~1.0（1.0=不降） / Derate ratio |
| `fFlowRatio` / `fHeadRatio` | REAL | — | 实测/额定 比值，钳 0~2 / Flow and head ratios |
| `fVibRatio` | REAL | — | 振动/上限 比值 / Vibration ratio |
| `nEventCount` | UDINT | 次 | 汽蚀事件累计（锁存） / Event count |
| `fRippleMeas` | REAL | — | 窗内电流波动率实测值 / Measured ripple |

**状态机（6 态）**
```
eIdle(0) --bRunning--> eMonitor(10) --任一判据--> eSuspect(20) --三判据同拍 + tConfirm--> eConfirm(30) --> eDerate(40)
eDerate --tHoldOff 满且判据消失--> eMonitor
eSuspect --判据消失--> eMonitor
任何态 --参数非法 --> eFault(99)
ELSE --> 0329
```

**故障码表**

| 码 | 级别 | 含义 | NE107 |
|---|---|---|---|
| `16#0003_0164` | 信息 | 单判据成立（嫌疑），未确认 / Single criterion, suspect only | `eOutOfSpec` |
| `16#0003_0165` | 信息 | 抑制窗内判据被忽略（降速后瞬态） / Criteria ignored in hold-off | `eOk` |
| `16#0003_0326` | 故障 | 三判据同拍成立 → 汽蚀确认（锁存） / Cavitation confirmed | `eFailure` |
| `16#0003_0327` | 故障 | 振动单点越上限 2 倍（急停级） / Vibration above twice the limit | `eFailure` |
| `16#0003_0328` | 故障 | 额定流量/扬程非正或阈值倒置 / Illegal nominals or inverted thresholds | `eFailure` |
| `16#0003_0329` | 故障 | 非法状态兜底 / Illegal state fallback | `eFailure` |

**验收向量**
- **V1**：流量 0.5×额定、扬程 0.8×额定、振动 2.0、电流平稳 → 只有流量判据 → `eSuspect` + `0164`，**不锁存**。
- **V2**：三判据同拍、持续 3 s → `eConfirm`→`eDerate`、`0326`、`fDerateRatio` 每次 −0.10（下限 0.3）。
- **V3（V-C R40）**：`tConfirm` 定时器在 `eSuspect`↔`eMonitor` 来回时**必须断输入**，否则 3 次 1 s 嫌疑会被误判为「持续 3 s」。
- **V4（V-D 恢复）**：`bReset` 后 `fDerateRatio` **不得**直接回 1.0（R41/R43：应保持当前值，由上层斜坡恢复），且必须夹进 0.3~1.0。
- **V5（V-A）**：`fFlowNominal=0` → `0328`，且 `fFlowRatio` 输出 0（不输出 Inf）。

---

### 3.2 泳道 B —— Level 0 原子族收口（6 件，`DL_Base` 2 + `DL_MathData` 4）

> 泳道主题：**把 LGF 三条待挖子族一次收口**（Bit Logic 的跨字旋转/掩码比较、Data Handling 的 CRC8 与定长串、Math 的矩阵运算开族）。泳道内**全部为无状态纯函数（FC）**——这不是偏好，是分层纪律：这六个能力都是「给一个输入必然得到一个确定输出」，做成 FB 会诱导调用方在长周期里保存中间量。

---

#### B1 ｜ `FC_DL_BitArrayRotate`（DL_Base · `FC_DL_`）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_Base\FC_DL_BitArrayRotate.st` |
| 来源标签 | `lgf-bitlogic`、`bit-manipulation`、`cross-word` |
| T 归属 | **T2-1**（Bit Logic 组「LWORD / 多段一次搬」待挖子族） |
| 码位 | **信息 `16#0001_013D~013E`（2）／ 故障 `16#0001_021F`（1）** |

**职责**：**多字整体循环移位**（1~4 个 `DWORD` 视为一条 32~128 位位串，左/右循环移 n 位）。与 `FC_DL_BitArrayExtract` / `Insert` 构成位段族三件套：**抽（读）/ 插（写）/ 转（整体旋转）**。
**为什么不用标准 `ROL`**：IEC 的 `ROL` 只在**单字内**循环，跨字无定义；本件做的是「整条位串旋转」，移出最高字的位回到最低字。
**红线**：移位量一律 `MOD 32`；**禁止 64 位移位**；`nShift` 先归一（负值转右移、绝对值 `MOD (32×nWords)`）。

**签名**

```iecst
FUNCTION FC_DL_BitArrayRotate : BOOL
VAR_INPUT
    aSrc    : ARRAY[1..DL_BAR_MAXW] OF DWORD;  // 源位图 [位]，未用字填 0 / Source bitmap, unused words zeroed
    nWords  : INT;                             // 有效字数 1~4 / Effective word count
    nShift  : INT;                             // 移位位数 −127~127，负=右移 / Shift amount, negative = right
    bLeft   : BOOL;                            // TRUE 左移（向高位）/ TRUE = rotate left
END_VAR
VAR_IN_OUT
    aDst    : ARRAY[1..DL_BAR_MAXW] OF DWORD;  // 目标位图，允许与源同址 / Destination, may alias the source
END_VAR
VAR_OUTPUT
    nEffectiveShift : INT;                     // 归一后实际移位量 0~127 / Effective shift after normalisation
    uErrorId        : UDINT;                   // 错误码 / Error code
END_VAR
```

**常量**：`DL_BAR_MAXW : INT := 4`（最大字数）、`DL_BAR_WBITS : INT := 32`。

**故障码表**

| 码 | 级别 | 含义 |
|---|---|---|
| `16#0001_013D` | 信息 | `nShift` 超 ±127，已按 `MOD (32×nWords)` 归约 / Shift reduced modulo the bitmap width |
| `16#0001_013E` | 信息 | `nWords` > 4，已钳到 4（多余字不参与） / Word count clamped to 4 |
| `16#0001_021F` | 故障 | `nWords` < 1（钳位后仍非法） / Illegal word count |

**验收向量**
- **V1**：`nWords=2`、`aSrc=[16#8000_0001, 16#0000_0000]`、`nShift=1`、左移 → `aDst=[16#0000_0002, 16#0000_0001]`（最高位回到第二字最低位）。
- **V2**：`aSrc=[16#8000_0001, 16#0000_0000]`、`nWords=2`、`nShift=1`、右移 → `aDst=[16#4000_0000, 16#8000_0000]`（最低位回到最高字最高位）。
- **V3（V-B 边界）**：`nShift=64`、`nWords=2` → 归约后 `nEffectiveShift=0`（整圈），输出等于输入，置 `013D`。
- **V4（V-A）**：`nWords=0` → 返回 FALSE、`021F`、`aDst` **原样不动**（不写入半张图）。

---

#### B2 ｜ `FC_DL_MaskCompare`（DL_Base · `FC_DL_`）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_Base\FC_DL_MaskCompare.st` |
| 来源标签 | `lgf-comparator`、`lgf-bitlogic`、`mask-compare` |
| T 归属 | **T2-1**（`LGF_BinaryMaskCompare` 的语义域，实测目录确认存在） |
| 码位 | **信息 `16#0001_013F~0140`（2）／ 故障 `16#0001_0220`（1）** |

**职责**：状态字**掩码比较**——`(uValue AND uMask) = (uExpect AND uMask)`，支持 don't-care 位（掩码置 0 的位不参与比较）、位宽裁剪（只比低 n 位），并输出差异位图 / 差异位数 / 首个差异位号。
**与既有件边界**：`FC_DL_BitFieldExtract` 是「取一段」，`FB_DL_StatusWordSegDecoder` 是「段表批量解码」；本件是「**判等 + 差异定位**」，三者互补、不重叠。
**关键实现约束**：位宽 1~32，`nWidth=32` 时掩码取 `16#FFFF_FFFF` 常量（**不得** `SHL(1,32)`，R12 已确立的未定义行为禁令）。

**签名**

```iecst
FUNCTION FC_DL_MaskCompare : BOOL          // TRUE = 匹配 / TRUE = match
VAR_INPUT
    uValue  : DWORD;                       // 待比较值 / Value under test
    uExpect : DWORD;                       // 期望值 / Expected value
    uMask   : DWORD := 16#FFFF_FFFF;       // 参与比较的位（1=比较，0=不关心）/ Care mask
    nWidth  : INT := 32;                   // 有效位宽 1~32 / Effective width
END_VAR
VAR_OUTPUT
    uDiffBits  : DWORD;                    // 差异位图（已按掩码与位宽屏蔽）/ Difference bitmap
    nDiffCount : INT;                      // 差异位数 0~32 / Difference bit count
    nFirstDiff : INT;                      // 首个差异位号 0~31，无差异=−1 / First differing bit, −1 if none
    uErrorId   : UDINT;                    // 错误码 / Error code
END_VAR
```

**故障码表**

| 码 | 级别 | 含义 |
|---|---|---|
| `16#0001_013F` | 信息 | `nWidth` > 32 已钳到 32 / Width clamped to 32 |
| `16#0001_0140` | 信息 | `uMask=0`（恒匹配），提示调用方掩码未生效 / Zero mask, always matching |
| `16#0001_0220` | 故障 | `nWidth` < 1 / Illegal width |

**验收向量**
- **V1**：`uValue=16#1234_5678`、`uExpect=16#0034_5678`、`uMask=16#00FF_FFFF` → TRUE，`nDiffCount=0`、`nFirstDiff=−1`。
- **V2**：`uExpect=16#0034_5670` → FALSE、`uDiffBits=16#0000_0008`、`nDiffCount=1`、`nFirstDiff=3`。
- **V3（V-A）**：`nWidth=0` → FALSE、`0220`、`uDiffBits=0`（不输出脏位图）。
- **V4（V-B）**：`nWidth=32`、`uMask=16#FFFF_FFFF`、`uValue=0`、`uExpect=16#8000_0000` → FALSE、`nFirstDiff=31`（验证 32 位常量掩码路径，不做 `SHL(1,32)`）。

---

#### B3 ｜ `FC_DL_Crc8`（DL_MathData · `FC_DL_`）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_MathData\FC_DL_Crc8.st`（同文件承载 `E_DL_Crc8Variant`） |
| 来源标签 | `lgf-datahandling`、`oscat-network`、`crc8` |
| T 归属 | **T2-1 主源**（`CalcCRC8` / `CalcCRC8Advanced` 的存在性与「CRC 家族参数化」的粒度事实）／ **T1-3 次源**（「校验/诊断独立成族」分类） |
| 码位 | **信息 `16#0001_0141~0142`（2）／ 故障 `16#0001_0221`（1）** |

**职责**：参数化 **MSB-first CRC-8**（逐位算法，无查表、无状态、O(1) 内存），补齐本库 CRC 族（CRC16-Modbus / CRC32-Ethernet / LRC 之后的 8 位位宽）。
**三个变体（公开多项式，均为 MSB-first）**：

| 变体 | poly | init | xorout | 典型用途 |
|---|---|---|---|---|
| `eCrc8Atm`（默认） | `16#07` | `16#00` | `16#00` | SMBus / ATM、多数传感器帧 |
| `eCrc8SaeJ1850` | `16#1D` | `16#FF` | `16#FF` | 汽车/部分变频器状态帧 |
| `eCrc8Hitag` | `16#1D` | `16#FF` | `16#00` | 同族不同的终值约定 |

**明确不立**：`CRC-8/MAXIM-DOW`（poly `16#31`，**反射 LSB-first**）——反射位序是另一套算法族，硬塞进同一枚举会让「变体」概念失真（同 R10「正弦/锯齿不合并 `eWaveform`」教训）。另立 R14 候选 `FC_DL_Crc8Reflected`。

**签名**

```iecst
FUNCTION FC_DL_Crc8 : BYTE
VAR_INPUT
    aData : ARRAY[1..DL_CRC8_MAXLEN] OF BYTE;        // 数据缓冲区 [字节] / Data buffer
    nLen  : INT;                                     // 有效字节数 1~DL_CRC8_MAXLEN / Valid byte count
    eVar  : E_DL_Crc8Variant := E_DL_Crc8Variant.eCrc8Atm; // 变体选择 / Variant selector
END_VAR
VAR_OUTPUT
    nProcessed : INT;                                // 实际参与计算的字节数 / Bytes actually processed
    bTruncated : BOOL;                               // 入参超上限被截断（**R37：必须显式置位**）/ Input truncated
    uErrorId   : UDINT;                              // 错误码 / Error code
END_VAR
```

**常量**：`DL_CRC8_MAXLEN : INT := 128`（定长上限，避免大数组进栈）。

**故障码表**

| 码 | 级别 | 含义 |
|---|---|---|
| `16#0001_0141` | 信息 | `nLen` 超上限已截断，`bTruncated=TRUE`，`nProcessed=上限`（**R37：不静默**）/ Length truncated explicitly |
| `16#0001_0142` | 信息 | 未知变体已回退 `eCrc8Atm` / Unknown variant fell back to ATM |
| `16#0001_0221` | 故障 | `nLen` < 1 / Illegal length |

**验收向量**
- **V1（ATM 标准向量）**：`aData="123456789"`、`nLen=9`、`eCrc8Atm` → `16#F4`。
- **V2（SAE-J1850）**：`aData="123456789"`、`nLen=9`、`eCrc8SaeJ1850` → `16#4B`。
- **V3（HITAG）**：`aData="123456789"`、`nLen=9`、`eCrc8Hitag` → `16#B4`。
- **V4（V-B R37）**：`nLen=200`、上限 128 → `nProcessed=128`、`bTruncated=TRUE`、`0141`；**不得**静默按 128 算却报「完整」。
- **V5（V-A）**：`nLen=0` → 返回 `16#00`、`0221`、`nProcessed=0`。

---

#### B4 ｜ `FC_DL_StringToLReal`（DL_MathData · `FC_DL_`）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_MathData\FC_DL_StringToLReal.st` |
| 来源标签 | `lgf-datahandling`、`string-parse`、`validated-conversion` |
| T 归属 | **T2-1**（Data Handling 字符串族收口：R12 行注明「字符串转数值（带校验）仍待挖」） |
| 码位 | **信息 `16#0001_0143~0146`（4）／ 故障 `16#0001_0222~0223`（2）** |

**职责**：把定长 ASCII 字段严格解析为 `LREAL`：可选符号、整数部、可选小数部、可选指数部；**逐字符状态推进**（不依赖标准库的隐式转换），拒绝多重小数点、嵌入空白、非法字符，并返回**首个非法字符位置**（现场调试最需要的信息）。
**为什么自带解析**：三平台对 `STRING_TO_REAL` 的**非法输入行为不一致**（有的返 0、有的抛异常、有的截断），且都不告诉调用方「错在第几个字符」。
**红线协同**：解析全程只用 `LEN(sText)` **一次锁存**的长度（**R38：锁存副本与实时入参不混用**）；不使用 `LEFT/ MID` 回夹（**R37 镜像面**）。

**签名**

```iecst
FUNCTION FC_DL_StringToLReal : BOOL
VAR_INPUT
    sText    : STRING(DL_S2N_MAXLEN);   // 待解析文本 [ASCII] / Text to parse
    bAllowExp: BOOL := TRUE;            // 允许指数部（E/e）/ Allow exponent part
    fMin     : LREAL := -1.0E30;        // 输出下限，越限钳位 / Lower clamp
    fMax     : LREAL :=  1.0E30;        // 输出上限，越限钳位 / Upper clamp
END_VAR
VAR_OUTPUT
    fValue   : LREAL;                   // 解析结果（失败时保持 0.0 或已解析前缀值）/ Parsed value
    nCharUsed: INT;                     // 已消费字符数 0~DL_S2N_MAXLEN / Characters consumed
    nBadPos  : INT;                     // 首个非法字符位置 1~n，0=全部合法 / First invalid position
    uErrorId : UDINT;                   // 错误码 / Error code
END_VAR
```

**常量**：`DL_S2N_MAXLEN : INT := 40`（`STRING(40)` 足够表达 17 位有效数字 + 符号 + 指数）。

**故障码表**

| 码 | 级别 | 含义 |
|---|---|---|
| `16#0001_0143` | 信息 | 空串或全空白 / Empty or blank text |
| `16#0001_0144` | 信息 | 前缀可解析、尾随有非法字符（返回 FALSE，`fValue` 保留前缀值）/ Trailing invalid characters |
| `16#0001_0145` | 信息 | 结果越 `fMin/fMax`，已钳位 / Clamped to range |
| `16#0001_0146` | 信息 | 指数绝对值 > 38，按 0 或 ±Inf 保护 / Exponent out of range |
| `16#0001_0222` | 故障 | 小数点出现 ≥2 次 / Multiple decimal points |
| `16#0001_0223` | 故障 | 数值溢出为非有限（Inf/NaN）/ Overflow to non-finite |

**验收向量**
- **V1**：`'-12.5'` → TRUE、`fValue=-12.5`、`nCharUsed=5`、`nBadPos=0`。
- **V2**：`'1.5E3'`、`bAllowExp=TRUE` → 1500.0；`bAllowExp=FALSE` → FALSE、`nBadPos=4`、`0144`。
- **V3（V-A）**：`'12.5.3'` → FALSE、`0222`、`nBadPos=5`、`nCharUsed=4`。
- **V4（V-B 上限）**：`'1E40'` → FALSE、`0146`、`fValue` 钳到 `fMax`（**不输出 Inf**）。
- **V5（R38 专测）**：调用后调用方立即改写 `sText` → 本件内部所有边界必须来自入口锁存的 `nLen`，**结果不受影响**（纯函数天然满足，但注释要写明这条纪律）。

---

#### B5 ｜ `FC_DL_StringFixedField`（DL_MathData · `FC_DL_`）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_MathData\FC_DL_StringFixedField.st` |
| 来源标签 | `lgf-datahandling`、`fixed-field`、`r37-reference` |
| T 归属 | **T2-1**（Data Handling 字符串族收口：R12 行注明「定长字段填充/对齐仍待挖」） |
| 码位 | **信息 `16#0001_0147~0149`（3）／ 故障 `16#0001_0224`（1）** |

> **本件是 R37 的「教科书样板件」**：全库唯一一处必须在**写入前**预判长度的地方。头注释第一段就写「本件存在的意义是把 R37 变成可复制的写法」。

**职责**：把任意 `STRING` 装进**定宽字段**（左/右对齐 + 填充字符），并**显式报告截断**。用于定长报文拼装、CSV 列对齐、HMI 固定列显示、条形码定长补位。

**签名**

```iecst
FUNCTION FC_DL_StringFixedField : BOOL
VAR_INPUT
    sValue     : STRING(DL_SFF_MAXLEN);  // 源文本 / Source text
    nWidth     : INT;                    // 目标字段宽度 1~255 [字符] / Target field width
    sPad       : STRING(1) := ' ';       // 填充字符（取首字符）/ Pad character
    bAlignRight: BOOL := FALSE;          // TRUE=右对齐（左补），默认左对齐 / Right alignment
    bAllowTrunc: BOOL := FALSE;          // TRUE=允许截断（仍置 bTruncated）/ Allow truncation
END_VAR
VAR_OUTPUT
    sField     : STRING(DL_SFF_MAXLEN);  // 定宽字段结果 / Fixed-width field
    bTruncated : BOOL;                   // 是否发生截断（**R37 强制显式**）/ Truncation flag
    nWritten   : INT;                    // 实际字段长度 0~255 / Field length written
    uErrorId   : UDINT;                  // 错误码 / Error code
END_VAR
```

**常量**：`DL_SFF_MAXLEN : INT := 255`（= `STRING(255)` 上限，本件的物理上界）。

**实现纪律（写进注释，编码者逐条照做）**
1. `nSrcLen := LEN(sValue);` **只算一次**（R38）。
2. `IF nSrcLen > nWidth THEN` → **先判后写**：`bTruncated := TRUE;` 再决定「截断写出」还是「拒绝构造」（依 `bAllowTrunc`）。
3. 拼装用 `CONCAT` + 常量 `sPad`，**绝不**用 `LEFT/MID` 回夹来「凑宽度」。
4. 出口 `nWritten := MIN(nWidth, DL_SFF_MAXLEN);` 且 `sField` 每次进函数先清零（`sField := '';`），防上一次残留。

**故障码表**

| 码 | 级别 | 含义 |
|---|---|---|
| `16#0001_0147` | 信息 | 源超宽、`bAllowTrunc=TRUE`，已截断并置 `bTruncated` / Truncated as allowed |
| `16#0001_0148` | 信息 | 源超宽、`bAllowTrunc=FALSE`，**拒绝构造**（`sField=''`、`nWritten=0`）/ Refused, field left empty |
| `16#0001_0149` | 信息 | `sPad` 长度 ≠1，已取首字符 / Pad length coerced to one character |
| `16#0001_0224` | 故障 | `nWidth` 域外（<1 或 >255）/ Illegal width |

**验收向量**
- **V1**：`'ABC'`、`nWidth=6`、左对齐 → `sField='ABC   '`、`nWritten=6`、`bTruncated=FALSE`。
- **V2**：`'ABC'`、`nWidth=6`、右对齐 → `'   ABC'`。
- **V3（V-B R37 主向量）**：`'ABCDEFGHIJ'`、`nWidth=5`、`bAllowTrunc=TRUE` → `sField='ABCDE'`、`bTruncated=**TRUE**`、`0147`。**此向量是本件的验收核心：裁剪发生必须有人报警。**
- **V4（V-B 拒绝路）**：`'ABCDEFGHIJ'`、`nWidth=5`、`bAllowTrunc=FALSE` → 返回 FALSE、`sField=''`、`nWritten=0`、`0148`。
- **V5（V-A）**：`nWidth=0` → FALSE、`0224`；`nWidth=300` → FALSE、`0224`（**不钳**：字段宽度是契约，猜不得）。
- **V6（残留）**：连续两次调用，第二次源为 `''` → `sField` 必须是纯填充（不得残留上次内容）。

---

#### B6 ｜ `FC_DL_Matrix3Inverse`（DL_MathData · `FC_DL_`）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_MathData\FC_DL_Matrix3Inverse.st` |
| 来源标签 | `lgf-math`、`matrix`、`affine-transform` |
| T 归属 | **T2-1**（Math 组 **Matrix 子族开族**，矩阵勘误 M-E4） |
| 码位 | **信息 `16#0001_014A~014C`（3）／ 故障 `16#0001_0225`（1）** |

**职责**：3×3 实数矩阵求逆（**伴随矩阵法**，无循环、无主元选取、逐拍可复算），用于视觉-机器人手眼标定反解、仿射变换逆映射、三传感器三角定位。
**为什么用伴随矩阵而不是高斯消元**：3×3 的解析逆是**固定 9 个表达式**，无分支、无主元交换、无循环 → 纯函数、确定性、与「逐拍复算式验收」兼容；高斯消元需 3×3 嵌套循环 + 主元选择分支，在 3×3 规模上无任何收益。
**数值判据（本件的关键设计）**：**不用绝对阈值判奇异**（矩阵元素量纲差 1000 倍时绝对阈值失效），改**相对判据**：`|det| ≤ fDetEps × (maxAbs)^3`，其中 `maxAbs` 是九个元素绝对值的最大值。这样「毫米级标定矩阵」与「微米级标定矩阵」用同一个 `fDetEps` 都能正确判奇异。此设计须在头注释用两行说明，并在 MANUAL 写明「`fDetEps` 是相对量，默认 1E-9」。

**签名**

```iecst
FUNCTION FC_DL_Matrix3Inverse : BOOL
VAR_INPUT
    afM     : ARRAY[1..9] OF LREAL;   // 行主序 3×3 矩阵 / Row-major 3x3 matrix
    fDetEps : LREAL := 1.0E-9;        // **相对**奇异判据 / Relative singularity epsilon
END_VAR
VAR_OUTPUT
    afInv   : ARRAY[1..9] OF LREAL;   // 逆矩阵（失败保持全 0）/ Inverse, zeroed on failure
    fDet    : LREAL;                  // 行列式值 / Determinant
    fCondEst: LREAL;                  // 条件数粗估 |det|/(maxAbs^3)，越小越病态 / Coarse condition estimate
    uErrorId: UDINT;                  // 错误码 / Error code
END_VAR
```

**故障码表**

| 码 | 级别 | 含义 |
|---|---|---|
| `16#0001_014A` | 信息 | `fCondEst` 接近阈值（超 10×`fDetEps` 但 < 1E-3），逆已给出但精度不保 / Ill-conditioned, inverse given |
| `16#0001_014B` | 信息 | 含非有限元素，按 0 处理后返回失败 / Non-finite element treated as zero |
| `16#0001_014C` | 信息 | `fDetEps` 非正，已用默认 1E-9 / Invalid epsilon, defaulted |
| `16#0001_0225` | 故障 | 矩阵奇异（`|det| ≤ fDetEps × maxAbs³`），逆不可得 / Singular matrix |

**验收向量**
- **V1**：单位阵 → `afInv=afM`、`fDet=1.0`、返回 TRUE。
- **V2**：`afM = [2,0,0; 0,4,0; 0,0,5]` → `afInv=[0.5,0,0;0,0.25,0;0,0,0.2]`、`fDet=40`。
- **V3（V-A 奇异，相对判据专测）**：`afM = [1,2,3; 2,4,6; 7,8,9]`（第二行 = 第一行×2）→ `fDet≈0` → FALSE、`0225`、`afInv` 全 0。
- **V4（相对判据 vs 绝对判据）**：`afM = 1E-6 × [1,2,3;2,4,6;7,8,9]` → `fDet≈0`（量级 1E-18），**绝对判据必然误判「可逆」**；本件按相对判据仍返回 FALSE、`0225`（这是本向量存在的唯一目的）。
- **V5（V-D 出口夹域）**：非有限元素 → `014B`、FALSE、`afInv` 全 0（**不输出 NaN**，R43 精神：出口值必须在声明域内）。

---

### 3.3 泳道 C —— 算法 / 运动 / 工艺（6 件，`DL_Algo` 1 + `DL_Motion` 1 + `DL_Process` 4）

> 泳道主题：**把「设备本体退化」与「工艺台账」两类高毛利需求落地**。C1 是 A4/A6 同族思路在**换热器**上的算法底座；C2 补运动层最后一个明显缺口（被动回零）；C3~C6 是行业池四条 P1 的正面交付。
> **本泳道 4 个 `DL_Process` 件的共同纪律**：**不内联底层算法**（统计归 `FB_DL_SignalStatistics`、分位归 `FC_DL_PercentileLReal`、限速归 `FB_DL_RateLimiter`、PID 归 `FB_DL_CascadePid`），一律**引脚注入或组合调用**——这是 `DL_Process` 依赖方向的硬约束，也是 R36（跨件调用必须手算退出跟踪首拍）的高发区。

---

#### C1 ｜ `FB_DL_FoulingResistanceEstimator`（DL_Algo · `FB_DL_`）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_Algo\FB_DL_FoulingResistanceEstimator.st` |
| 来源标签 | `oscat-building`、`heat-transfer`、`fouling` |
| T 归属 | **T1-2**（行为定义的「输入输出域」组织方式：温度/流量进、传热系数与污垢热阻出） |
| 码位 | **信息 `16#0002_2201~2204`（4）／ 故障 `16#0002_2210~2212`（3）**（新按件带 `22xx`） |

**职责**：由四路温度 + 两路流量算出**传热系数 K** 与**污垢热阻 Rf**，并给出**趋势斜率**与清洗建议。是 §19.6 `HeatExchangerFoulingTrend` 的算法底座（该件另立工艺件，本件只做「算一个值 + 算一个趋势」）。
**边界**：① **不做 PID**、不做阀门控制；② 不做结垢成分分析；③ 热平衡偏差过大时**拒绝更新**（数据不可信不出值，R42 精神）。

**VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位/范围 | 说明（中 / EN） |
|---|---|---|---|---|
| `bEnable` / `bReset` | BOOL | — | — | 使能 / 上升沿复位趋势 / Enable and reset trend |
| `fTinHot` / `fToutHot` | REAL | — | °C | 热侧进/出口温度 −50~300 / Hot side in/out temperature |
| `fTinCold` / `fToutCold` | REAL | — | °C | 冷侧进/出口温度 −50~300 / Cold side in/out temperature |
| `fFlowHot` / `fFlowCold` | REAL | — | m³/h | 两侧体积流量 0~10000 / Volumetric flows |
| `fCpHot` / `fCpCold` | REAL | 4.18 | kJ/(kg·K) | 两侧比热 0.5~10 / Specific heat capacities |
| `fRhoHot` / `fRhoCold` | REAL | 1000.0 | kg/m³ | 两侧密度 1~2000 / Densities |
| `fArea` | REAL | — | m² | 换热面积（域 >0） / Heat transfer area |
| `fKClean` | REAL | — | W/(m²·K) | 清洁态传热系数基准（域 >0） / Clean-condition K |
| `bCounterFlow` | BOOL | TRUE | — | TRUE=逆流，FALSE=顺流（影响 LMTD 符号） / Counter-flow flag |
| `fDtmMin` | REAL | 2.0 | K | 最小可用温差（LMTD 可信门限）0.5~20 / Minimum usable temperature difference |
| `fHeatBalTol` | REAL | 0.10 | — | 两侧热负荷允许偏差比 0.02~0.5 / Heat balance tolerance |
| `fFlowMinRatio` | REAL | 0.20 | — | 流量低于额定的比例时不出值 0.05~0.9 / Minimum flow ratio |
| `tWindow` | TIME | `T#1H` | ms | 趋势窗长 5 min~24 h / Trend window |
| `tSamplePeriod` | TIME | `T#10S` | ms | 调用周期（**必须与实际任务周期一致**） 10 ms~10 s / Task period |
| `fRfAlarm` | REAL | 3.0E-4 | m²·K/W | 污垢热阻报警阈 1E-5~5E-3 / Fouling resistance alarm |
| `fSlopeAlarm` | REAL | 2.0E-5 | m²·K/(W·h) | 污垢增长速率阈 1E-7~1E-3 / Fouling slope alarm |

**VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明（中 / EN） |
|---|---|---|---|
| `fQ` | REAL | kW | 热负荷（两侧平均） / Heat duty |
| `fLmtd` | REAL | K | 对数平均温差 / LMTD |
| `fK` | REAL | W/(m²·K) | 实测传热系数 / Measured K |
| `fRf` | REAL | m²·K/W | 污垢热阻 = 1/K − 1/K_clean / Fouling resistance |
| `fRfSlope` | REAL | m²·K/(W·h) | 窗内趋势斜率 / Trend slope |
| `bValid` | BOOL | — | 本拍输出有效 / Output valid this scan |
| `bCleanAdvice` | BOOL | — | 建议清洗（保持语义，R27）/ Cleaning advised, held |
| `eHealth` | `E_DL_Ne107Status` | — | 健康态 / NE107 health |
| `uDiagCode` / `uErrorId` / `bError` | UDINT / UDINT / BOOL | — | 码位 |
| `nUpdateCount` | UDINT | 次 | 有效更新次数 / Valid update count |

**状态机（5 态）**
```
eIdle(0) → eValid(10)：参数闸门过且首拍装基准
eValid → eTrend(20)：窗口样本数 ≥ 3
eTrend → eAdvice(30)：fRf ≥ fRfAlarm 或 fRfSlope ≥ fSlopeAlarm
任何态 → eFault(99)：参数非法 / 非有限
ELSE → 2212
```

**故障码表**

| 码 | 级别 | 含义 |
|---|---|---|
| `16#0002_2201` | 信息 | LMTD < `fDtmMin`（温差太小不可信），本拍不更新 / LMTD below usable limit |
| `16#0002_2202` | 信息 | 流量低于 `fFlowMinRatio`，本拍不更新 / Flow below minimum |
| `16#0002_2203` | 信息 | 两侧热负荷偏差 > `fHeatBalTol`，本拍不更新 / Heat balance exceeded |
| `16#0002_2204` | 信息 | 逆/顺流口径切换，趋势基准已重置 / Flow arrangement changed, trend reset |
| `16#0002_2210` | 故障 | `fArea` 或 `fKClean` 非正 / Illegal area or clean K |
| `16#0002_2211` | 故障 | LMTD ≤ 0（温度交叉，逆流非法或用错口径）/ Non-positive LMTD |
| `16#0002_2212` | 故障 | 非法状态兜底 / Illegal state fallback |

**验收向量**
- **V1**：热侧 90/70 °C、冷侧 20/40 °C、逆流 → `fLmtd≈49.7 K`（手算校验）、`fQ≈232 kW`（流量 10 m³/h × 4.18 × 20 K / 3.6）。
- **V2**：`fK=1000`、`fKClean=2000` → `fRf = 1/1000 − 1/2000 = 5.0E-4` → `bCleanAdvice=TRUE`。
- **V3（V-A 除零）**：`fArea=0` → `2210`，`fK` 保持上次值且**夹进 ≥0**（R43）。
- **V4（V-C 跨拍复验）**：进 `eTrend` 后当拍流量骤降 → **必须本拍复验流量门限**，不得用上一相结论直接算斜率（R42）。
- **V5（V-D 首拍）**：上电首拍 `bValid=FALSE`、`fRf=0`、**不得**把首拍当「清洁态」写入趋势基准（R19：首扫只装基准，不参与斜率）。

---

#### C2 ｜ `FB_DL_PassiveHomingMonitor`（DL_Motion · `FB_DL_`）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_Motion\FB_DL_PassiveHomingMonitor.st` |
| 来源标签 | `plcopen-motion`、`passive-homing`、`reference-event` |
| T 归属 | **T1-6**（PLCopen 参考事件语义；R8 明确「被动回零留扩产」） |
| 码位 | **信息 `16#0004_01C3~01C6`（4）／ 故障 `16#0004_02D2~02D4`（3）** |

**职责**：**轴被外力移动时**（手动摇轮、另一驱动、重力下落）监听参考事件（原点开关沿 / Z 相 / 标记锁存），按「**方向一致性 + 速度窗 + 多次一致性**」确认参考点，输出可施加的位置偏移 `fOffsetToApply`。
**边界（最重要的一条）**：**不自造轴状态、不写轴状态机**。本件只有 `bReferenced` 一个工艺位，轴状态（Disabled/Standstill/DiscreteMotion…）**只由运动层拥有**——这是 R31 家族（两套状态机并存）的最高危区，R11 的 `FB_DL_WindingTensionCtrl` 已立过判例。
**与 `FB_DL_AxisHomingSeq` 的分工**：后者是**主动回零顺控**（自己发运动指令、四模式）；本件**不发任何运动指令**，只旁路监听，输出偏移。两者可并存，但**不得互相改写对方的状态位**。

**VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位/范围 | 说明（中 / EN） |
|---|---|---|---|---|
| `bEnable` / `bReset` | BOOL | — | — | 使能 / 上升沿清结论 / Enable and reset |
| `bArm` | BOOL | — | 上升沿 | 布防（开始监听）；下降沿撤防 / Rising edge arms monitoring |
| `bRefEvent` | BOOL | — | — | 参考事件原始电平（内部取上升沿）/ Raw reference event, edge detected inside |
| `bDirForward` | BOOL | TRUE | — | 本拍运动方向，TRUE=正向 / Current direction |
| `fActPos` | REAL | — | mm | 实际位置（只读采样） −1E7~1E7 / Actual position |
| `fActVel` | REAL | — | mm/s | 实际速度（只读采样） −1E5~1E5 / Actual velocity |
| `bInMotion` | BOOL | — | — | 轴在运动（速度超噪声带）/ Axis in motion |
| `fVelMin` | REAL | 1.0 | mm/s | 速度窗下限（过慢则事件定位精度不保）0.01~100 / Velocity window low |
| `fVelMax` | REAL | 500.0 | mm/s | 速度窗上限（过快则可能漏捕获）1~10000 / Velocity window high |
| `nRequireEvents` | INT | 2 | 次 | 需一致性确认的事件次数 1~3 / Required consistent events |
| `fConsistencyTol` | REAL | 0.1 | mm | 多次事件位置一致性容差 0.001~10 / Consistency tolerance |
| `tArmTimeout` | TIME | `T#120S` | ms | 布防总超时 1 s~1 h / Arming timeout |

**VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明（中 / EN） |
|---|---|---|---|
| `bReferenced` | BOOL | — | 参考点已确认（**保持语义，R27**） / Referenced, held |
| `fRefPos` | REAL | mm | 确认的参考点位置 / Confirmed reference position |
| `fOffsetToApply` | REAL | mm | 建议施加的位置偏移 = 目标 − 参考（由上层 `MC_SetPosition` 语义消费）/ Offset to apply |
| `nEventCount` | UINT | 次 | 已捕获事件数（本轮布防内）/ Events captured in this arming |
| `ePhase` | `E_DL_PassiveHomePhase`（同文件） | — | 内部相位（**仅供诊断显示，不对外作轴状态**）/ Internal phase, diagnostics only |
| `eHealth` / `uDiagCode` / `uErrorId` / `bError` | — | — | 健康与码位 |

**状态机（6 态）**
```
eIdle(0) --bArm--> eArmed(10) --首事件--> eCaptured(20) --事件数达标且一致--> eConfirmed(30)
eCaptured --下次事件不一致--> eArmed（计数重置）
eArmed --tArmTimeout--> eTimeout(40) --重新 bArm--> eArmed
任何态 --位置/速度非有限--> eFault(99)
ELSE --> 02D4
```

**故障码表**

| 码 | 级别 | 含义 |
|---|---|---|
| `16#0004_01C3` | 信息 | 速度低于窗下限，事件已采信但精度标记 / Below velocity window |
| `16#0004_01C4` | 信息 | 本次方向与上次相反，一致性计数重置 / Direction reversed, count reset |
| `16#0004_01C5` | 信息 | 布防期间长时间无运动（未超总超时）/ No motion during arming |
| `16#0004_01C6` | 信息 | 多次事件位置超容差，计数重置 / Position inconsistent, count reset |
| `16#0004_02D2` | 故障 | 布防超时未捕获事件 / Arm timeout without event |
| `16#0004_02D3` | 故障 | 位置或速度非有限 / Non-finite position or velocity |
| `16#0004_02D4` | 故障 | 非法状态兜底 / Illegal state fallback |

**验收向量**
- **V1**：布防 → 正向 20 mm/s 移动 → 两次事件（位置 100.00 / 100.05 mm）→ `bReferenced=TRUE`、`fRefPos=100.025`（取均值，头注释写明取均值而非取首个）。
- **V2（V-C 方向反转）**：第二次事件发生在反向 → `01C4`、计数回到 1、**不得**确认。
- **V3（V-D 超时恢复）**：`tArmTimeout` 到 → `eTimeout`+`02D2`；重新 `bArm` 后**必须从 0 重建计数**（R41：恢复不重头 = 不允许沿用上次部分计数）。
- **V4（V-A）**：`fActVel=NaN` → `02D3`、`fRefPos` 保持上次确认值（不写脏值）。
- **V5（R43 出口夹域）**：撤防后 `fOffsetToApply` 保持上次值且**夹进 ±1E6 mm**，冷启动首拍输出 0（不得输出未初始化值）。

---

#### C3 ｜ `FB_DL_CapperTorqueTrend`（DL_Process · `FB_DL_`）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_Process\FB_DL_CapperTorqueTrend.st` |
| 来源标签 | `rockwell-aoi`、`lbp-process`、`capper-torque` |
| T 归属 | **T2-6 主源**（设备级 AOI 的「单块覆盖 指令-反馈-判定-诊断 四段」粒度）+ **T2-2**（命令-监视-判定三段分层，次源） |
| 码位 | **信息 `16#0005_01C5~01C7`（3）／ 故障 `16#0005_02F3~02F5`（3）** |
| ROADMAP | §19.4 行 826（P1） |

**职责**：旋盖扭矩**曲线特征提取 + 五类 NG 判别**：峰值、上升斜率、稳态段均值、曲线面积；判 `低扭/高扭/滑牙/歪盖/曲线异常` 五类 NG。
**边界**：① **不内联分位排序**（批次分位由 `FC_DL_PercentileLReal` 在批次层算好，以 `fBatchP10/fBatchP90` 引脚注入）；② **不内联滤波**（曲线平滑由上游 `FB_DL_MedianFilter` / `FB_DL_MovingAverage` 做完）；③ 不做拧紧轴运动控制。

**VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位/范围 | 说明（中 / EN） |
|---|---|---|---|---|
| `bEnable` / `bReset` | BOOL | — | — | 使能 / 复位判定与统计 / Enable and reset |
| `bCycleStart` | BOOL | — | 上升沿 | 单次拧紧开始（**单拍沿，R24/R25**）/ One-shot cycle start |
| `afCurve` | `ARRAY[1..DL_CAP_MAXP] OF REAL` | — | N·m | 扭矩采样曲线 0~50 N·m / Torque curve samples |
| `nPoints` | INT | — | 个 | 有效点数 2~`DL_CAP_MAXP` / Valid sample count |
| `fSpeed` | REAL | — | rpm | 拧紧转速（用于斜率换算）1~2000 / Tightening speed |
| `fPeakMin` / `fPeakMax` | REAL | — | N·m | 峰值合格窗 / Peak window |
| `fSlopeMin` / `fSlopeMax` | REAL | — | N·m/s | 上升斜率合格窗 / Slope window |
| `fSteadyTol` | REAL | 5.0 | % | 稳态段相对峰值的容差 / Steady-band tolerance |
| `fSlipDropRatio` | REAL | 0.20 | — | 滑牙判据：峰值后跌落比例 > 此值 / Slip drop ratio |
| `fCrossRatio` | REAL | 0.40 | — | 歪盖判据：上升段面积/总面积极端偏斜比 / Cross-thread ratio |
| `fBatchP10` / `fBatchP90` | REAL | 0.0 | N·m | 批次分位基线（0=未下发）/ Batch percentile baseline |
| `nBatchMin` | INT | 30 | 件 | 分位可用所需最小样本 / Minimum batch size |

**VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明（中 / EN） |
|---|---|---|---|
| `fPeak` / `fSlope` / `fSteadyMean` | REAL | N·m / N·m/s / N·m | 三特征值 / Three features |
| `eVerdict` | `E_DL_CapperVerdict`（同文件） | — | `eOk/eNgLow/eNgHigh/eNgSlip/eNgCross/eNgCurve` |
| `uNgMask` | WORD | — | NG 原因位图（可多位同置） / NG reason bitmap |
| `bVerdictValid` | BOOL | — | 判定有效（**保持语义，R27**：判完持续为真到下次 `bCycleStart`）/ Verdict held |
| `nTotal` / `nNg` | UDINT | 件 | 计数 / Counters |
| `eHealth` / `uDiagCode` / `uErrorId` / `bError` | — | — | 健康与码位 |

**状态机（5 态）**
```
eIdle(0) --bCycleStart--> eSampling(10) --采样窗满--> eEvaluate(20) --> eVerdict(30) --下次 bCycleStart--> eSampling
任何态 --点数非法/非有限--> eFault(99)
ELSE --> 02F5
```
> `eVerdict` 的结论**必须每拍重写**（R27），不得只在进入那一拍置位。

**故障码表**

| 码 | 级别 | 含义 |
|---|---|---|
| `16#0005_01C5` | 信息 | 点数不足（< 2）或 < 最小分析点数，未评级 / Insufficient points |
| `16#0005_01C6` | 信息 | 批次分位未下发（`nBatchMin` 未满足），仅用绝对阈值判 / Batch baseline unavailable |
| `16#0005_01C7` | 信息 | 曲线噪声大（峰前抖动 > 3 次），斜率可信度低 / Noisy curve, slope of low confidence |
| `16#0005_02F3` | 故障 | `nPoints` 超上限 `DL_CAP_MAXP` / Point count above the buffer |
| `16#0005_02F4` | 故障 | 曲线含非有限值 / Non-finite sample |
| `16#0005_02F5` | 故障 | 非法状态兜底 / Illegal state fallback |

**验收向量**
- **V1**：标准曲线（0→15 N·m 线性 0.5 s，稳态 2 s，回 0）→ `eOk`、`uNgMask=0`。
- **V2 滑牙**：峰值 12 后 0.2 s 内跌到 6（跌落 50% > 20%）→ `eNgSlip`、`uNgMask` 对应位置 1。
- **V3（V-C 单拍沿纪律，R24/R25）**：`bCycleStart` 在 `eSampling` 内保持 TRUE 两拍 → **不得**触发第二次判定；沿必须只在 `bCycleStart` 由 FALSE→TRUE 那一拍生效，且消费后自清（`bStartConsumed`）。
- **V4（V-D 保持）**：判定后上位机在 3 拍后才读 → `bVerdictValid` 与 `eVerdict` **必须仍有效**（R27 保持，非脉冲）。
- **V5（V-A）**：`nPoints=0` → `01C5`、`bVerdictValid=FALSE`、`eVerdict=eNgCurve`? **不得**：未评级时 `eVerdict` 保持上次值且 `bVerdictValid=FALSE`（「无结论」不等于「不合格」）。

---

#### C4 ｜ `FB_DL_EscHeLeakCheck`（DL_Process · `FB_DL_`）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_Process\FB_DL_EscHeLeakCheck.st` |
| 来源标签 | `semiconductor-esc`、`leak-rate`、`he-backside` |
| T 归属 | **自研**（无对应开源件；T2-8 只借「分级 → 维护建议」的语言） |
| 码位 | **信息 `16#0005_01C8~01CA`（3）／ 故障 `16#0005_02F6~02F8`（3）** |
| ROADMAP | §19.3 行 818（P1） |

**职责**：静电吸盘（ESC）**氦背冷泄漏率**判定：升压段（斜率限幅 + 达压确认）→ 稳压段（稳定判据）→ 测量段（压降率 → 漏率换算）→ 判定（OK / Warn / NG）。
**与 `FB_DL_LeakTestStation` 的分工（必须写进头注释）**：后者是**通用压降法工站**（充气-稳压-保压-压降换算-排气，面向工件腔体）；本件是**ESC 专用**（氦侧压力区间窄、必须温漂修正、判定带 Warn 三级、且**氦源串漏方向要单独识别**）。两者**不得合并**（合并会把两套压力量纲与判定门限塞进一个 MODE 参数 —— OSCAT 时代的老毛病）。

**VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位/范围 | 说明（中 / EN） |
|---|---|---|---|---|
| `bEnable` / `bReset` | BOOL | — | — | 使能 / 复位 / Enable and reset |
| `bStart` | BOOL | — | 上升沿 | 启动一次检测（**单拍沿，R24**）/ One-shot start |
| `fHePressure` | REAL | — | kPa | 氦侧压力 0~500 kPa / Helium pressure |
| `fHeFlow` | REAL | — | sccm | 氦侧流量 0~5000 sccm / Helium flow |
| `fChuckTemp` | REAL | — | °C | 卡盘温度 0~200 / Chuck temperature |
| `tPressurizeMax` | TIME | `T#20S` | ms | 升压段超时 / Pressurize timeout |
| `tStabilize` | TIME | `T#10S` | ms | 稳压段时长 / Stabilisation time |
| `tMeasure` | TIME | `T#30S` | ms | 测量段时长 / Measurement time |
| `fPressTarget` | REAL | 15.0 | kPa | 目标背压 1~100 / Target back pressure |
| `fPressTol` | REAL | 0.5 | kPa | 达压容差 / Pressure tolerance |
| `fLeakWarn` | REAL | 3.0 | sccm | 漏率 Warn 阈 / Leak-rate warn limit |
| `fLeakNg` | REAL | 5.0 | sccm | 漏率 NG 阈 / Leak-rate reject limit |
| `fPressRiseMax` | REAL | 2.0 | kPa/s | 升压速率上限 / Pressurise rate limit |
| `fTempCoeff` | REAL | 0.003 | 1/K | 压力温漂修正系数 / Pressure temperature coefficient |
| `fStabTol` | REAL | 0.2 | kPa | 稳压判据（窗内极差上限）/ Stabilisation tolerance |

**VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明（中 / EN） |
|---|---|---|---|
| `fLeakRate` | REAL | sccm | 换算漏率（温漂修正后）/ Corrected leak rate |
| `fPressDecay` | REAL | kPa/s | 测量段压降率 / Pressure decay rate |
| `eResult` | `E_DL_LeakResult`（同文件） | — | `eOk/eWarn/eNg/eAborted` |
| `bDone` | BOOL | — | 检测完成（**保持语义，R27**）/ Done, held |
| `bPass` | BOOL | — | 合格（保持）/ Pass, held |
| `nTestCount` / `nNgCount` | UDINT | 次 | 计数 / Counters |
| `eHealth` / `uDiagCode` / `uErrorId` / `bError` | — | — | 健康与码位 |

**状态机（6 态）**
```
eIdle(0) --bStart--> ePressurize(10) --达压--> eStabilize(20) --稳定判据--> eMeasure(30) --tMeasure 到--> eVerdict(40) --> eIdle
ePressurize --超时/升压过慢--> eFault(99)
任何态 --非有限--> eFault(99)
ELSE --> 02F8
```

**故障码表**

| 码 | 级别 | 含义 |
|---|---|---|
| `16#0005_01C8` | 信息 | 稳压段未达稳定判据，已延长一次（仅一次）/ Stabilisation extended once |
| `16#0005_01C9` | 信息 | 已启用量漂修正（`fTempCoeff` 非 0 且温差 > 1 K）/ Temperature correction active |
| `16#0005_01CA` | 信息 | 漏率落在 Warn 带（`fLeakWarn`~`fLeakNg`）/ Leak rate in warn band |
| `16#0005_02F6` | 故障 | 升压段超时或升压速率过低（供气异常）/ Pressurisation failed |
| `16#0005_02F7` | 故障 | 测量段压力**上升**（方向反：氦源串漏或阀未关）/ Pressure rising in measure phase |
| `16#0005_02F8` | 故障 | 非法状态兜底 / Illegal state fallback |

**验收向量**
- **V1**：15 kPa 达压、30 s 内压降 0.04 kPa → `fPressDecay≈0.00133 kPa/s`、`fLeakRate≈2.0 sccm` → `eOk`。
- **V2**：压降 0.12 kPa/30 s → 漏率 6.0 sccm > NG 阈 5.0 → `eNg`、`bPass=FALSE`（**保持**）。
- **V3（V-C R40 三段定时器）**：升压 10 s + 稳压 10 s + 测量 30 s，三段各用一个 `TON`，**每段切换必须断输入一拍**（R40）。若三段共用一个 `TON` 且 `IN := (state<>eIdle)`，则 50 s 会触发 `tMeasure=30S` 的超时 → **本向量必须能区分这两种实现**。
- **V4（V-D 中止恢复）**：`eMeasure` 中 `bEnable` 掉 → 回 `eIdle`、`eResult=eAborted`、`bDone` **保持**；重新 `bStart` 后计时**从 0 开始**（R41）。
- **V5（V-A）**：`fHePressure=NaN` → `02F8`、`fLeakRate` 保持上次值（不写 NaN）。

---

#### C5 ｜ `FB_DL_ChamberSeasoningTrack`（DL_Process · `FB_DL_`）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_Process\FB_DL_ChamberSeasoningTrack.st` |
| 来源标签 | `semiconductor-esc`、`seasoning`、`isa-88` |
| T 归属 | **T2-8**（批次/相语义的「台账 + 放行」，只借公开条款） |
| 码位 | **信息 `16#0005_01CB~01CE`（4）／ 故障 `16#0005_02F9~02FB`（3）** |
| ROADMAP | §19.3 行 819（P1） |

**职责**：腔体 **seasoning 片数 + 膜厚台账 + 放行判定**：每片完成后累计片数、累计工艺时长、膜厚均值与趋势；**双判据**（片数达标 **且** 时长达标）才放行；连续越窗自动降级 `eNotReady`。
**边界**：不做配方存储（`sRecipeName` 只作为**标签与校验键**传入，配方本体归 `FB_DL_RecipeManager`）；不做膜厚测量（测量值引脚注入）。

**VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位/范围 | 说明（中 / EN） |
|---|---|---|---|---|
| `bEnable` / `bReset` | BOOL | — | — | 使能 / 清台账并重开一轮 / Enable and reset |
| `bWaferDone` | BOOL | — | 上升沿 | 单片完成（**单拍沿，R24**）/ One-shot wafer done |
| `fThickness` | REAL | — | nm | 本片膜厚 0~10000 / Wafer thickness |
| `fUniformity` | REAL | — | % | 本片均匀性 0~100 / Uniformity |
| `sRecipeName` | `STRING(32)` | `''` | — | 配方名（标签与校验键，空=非法）/ Recipe tag |
| `fThickTarget` | REAL | — | nm | 膜厚目标（域 >0）/ Thickness target |
| `fThickTol` | REAL | 5.0 | % | 膜厚相对容差 0.5~50 / Thickness tolerance |
| `fUnifLimit` | REAL | 3.0 | % | 均匀性上限 0.1~20 / Uniformity limit |
| `nCountTarget` | INT | 25 | 片 | 片数目标 1~10000 / Wafer count target |
| `tTimeTarget` | TIME | `T#10H` | ms | 工艺时长目标 1 min~1000 h / Process time target |
| `nConsecNgLimit` | INT | 2 | 片 | 连续越窗降级阈值 1~10 / Consecutive out-of-window limit |
| `tProcessTime` | TIME | — | ms | 本片工艺耗时（引脚注入）/ Process time of this wafer |

**VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明（中 / EN） |
|---|---|---|---|
| `nCount` / `nNgCount` | INT | 片 | 已 seasoning 片数 / 越窗片数 / Counters |
| `tAccum` | TIME | ms | 累计工艺时长 / Accumulated process time |
| `fThickAvg` | REAL | nm | 膜厚均值 / Mean thickness |
| `fThickSlope` | REAL | nm/片 | 膜厚趋势（首末差/片数）/ Thickness trend |
| `bRelease` | BOOL | — | 放行（**保持语义，R27**）/ Release, held |
| `eQualify` | `E_DL_SeasonState`（同文件） | — | `eTracking/eQualified/eNotReady/eExpired` |
| `nRoundId` | UINT | — | 本轮编号（复位递增，供 MES 对齐）/ Round id |
| `eHealth` / `uDiagCode` / `uErrorId` / `bError` | — | — | 健康与码位 |

**状态机（5 态）**
```
eIdle(0) --bEnable 且 recipe/target 有效--> eTracking(10)
eTracking --片数与时长双达标--> eQualified(20)（bRelease 保持 TRUE）
eTracking --连续越窗 ≥ nConsecNgLimit--> eNotReady(30)
eQualified --bReset--> eTracking（新轮，计数清零）
任何态 --recipe 空 / target ≤0--> eFault(99)
ELSE --> 02FB
```

**故障码表**

| 码 | 级别 | 含义 |
|---|---|---|
| `16#0005_01CB` | 信息 | 单片越窗但未连续（不清零计数）/ Single out-of-window |
| `16#0005_01CC` | 信息 | 连续越窗达阈值 → `eNotReady` / Consecutive out-of-window |
| `16#0005_01CD` | 信息 | 片数达标但时长未达标（双判据未齐）/ Count reached, time pending |
| `16#0005_01CE` | 信息 | `sRecipeName` 超 `STRING(32)`，已显式截断并按截断后名登记台账（**R37：不静默**）/ Recipe tag truncated explicitly |
| `16#0005_02F9` | 故障 | `sRecipeName` 为空或 `fThickTarget ≤ 0` / Missing recipe or target |
| `16#0005_02FA` | 故障 | 片数/时长计数溢出 / Counter overflow |
| `16#0005_02FB` | 故障 | 非法状态兜底 / Illegal state fallback |

**验收向量**
- **V1**：25 片、每片 24 min、膜厚 100±2 nm → `tAccum=10 h`、`eQualified`、`bRelease=TRUE`。
- **V2（双判据）**：25 片但每片 10 min（总 4.2 h < 10 h）→ `01CD`、**仍 `eTracking`**、`bRelease=FALSE`。
- **V3（V-A 缺失键）**：`sRecipeName=''` → `02F9` 锁存、`bRelease` **强制 FALSE**（安全侧：台账不可信不得放行）。
- **V4（V-B 串上限，R37）**：`sRecipeName` 传入 40 字符（超 `STRING(32)`）→ 必须在**入口处判 `LEN` 并置 `16#0005_01CE`**，按截断后的名字登记台账，**不得**依赖赋值隐式截断后静默使用（R37 的核心教训）。
- **V5（V-D 复位首拍）**：`bReset` 后 `nCount=0`、`tAccum=T#0S`、`nRoundId+1`、`bRelease=FALSE`；**不得**保留上一轮 `fThickSlope` 基准（R41）。

---

#### C6 ｜ `FB_DL_ReactorJacketDeltaT`（DL_Process · `FB_DL_`）

| 项 | 内容 |
|---|---|
| 文件 | `C:\Library\DL_Process\FB_DL_ReactorJacketDeltaT.st` |
| 来源标签 | `lbp-process`、`isa-88`、`jacket-dt` |
| T 归属 | **T2-2 主源**（「给定 → 限幅 → 闭环 → 执行机构限幅」的**设定值分层**组织结构）+ **T2-8**（相语义，次源） |
| 码位 | **信息 `16#0005_01CF~01D1`（3）／ 故障 `16#0005_02FC~02FE`（3）** |
| ROADMAP | §19.6 行 846（P1） |

**职责**：放热反应的**釜温-夹套温差抑制**：以 `ΔT = 釜温 − 夹套温` 为约束量，对升温侧做**温差上限限幅**与**温差变化率限幅**，输出冷/热两路阀位给定（分程）。
**边界与纪律**：① **不内联 PID** —— 温度闭环由 `FB_DL_CascadePid` 承担，本件只做「约束层 + 分程层」，PID 输出以 `fPidOut` 引脚注入；② **不新增轴/相状态枚举**（R31 家族：相状态归 `FB_DL_BatchPhaseBase`）；③ 两路输出**必须互斥或带死区分离**，禁止「冷热同开」。
**R36 关联（必须手算）**：本件消费上层 PID 输出，若上层 PID 处于跟踪态（手动/暂停），注入的 `fPidOut` 可能刚从跟踪值切出 → 头注释必须写明「调用方须保证 `fPidOut` 已过跟踪结束首拍处理」，并在验收向量 V4 给出该场景。

**VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位/范围 | 说明（中 / EN） |
|---|---|---|---|---|
| `bEnable` / `bReset` | BOOL | — | — | 使能 / 复位锁存 / Enable and reset |
| `fReactorTemp` | REAL | — | °C | 釜温 −50~400 / Reactor temperature |
| `fJacketTemp` | REAL | — | °C | 夹套温度 −50~400 / Jacket temperature |
| `fPidOut` | REAL | — | % −100~100 | 上层 PID 输出（**已过跟踪首拍**）/ PID output from above |
| `fDeltaTMax` | REAL | 30.0 | K | 允许最大温差（超则冻结升温侧）5~150 / Max allowed delta-T |
| `fDeltaTRate` | REAL | 5.0 | K/min | 温差变化率上限 0.1~50 / Delta-T rate limit |
| `fOverTempMargin` | REAL | 5.0 | K | 超设定强制冷却的裕量 0.5~50 / Over-temperature margin |
| `fTempSetpoint` | REAL | — | °C | 釜温设定（用于超温判据）/ Reactor setpoint |
| `tRateWindow` | TIME | `T#1M` | ms | 变化率统计窗 5 s~10 min / Rate window |
| `fDeadband` | REAL | 2.0 | % | 冷热分程死区（防同开）0~10 / Split-range deadband |
| `fOutMin` / `fOutMax` | REAL | 0.0 / 100.0 | % | 输出限幅 / Output limits |

**VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明（中 / EN） |
|---|---|---|---|
| `fHeatOut` / `fCoolOut` | REAL | % | 热/冷两路阀位给定 0~100 / Heat and cool outputs |
| `fDeltaT` | REAL | K | 实测温差（有符号）/ Measured delta-T |
| `fDeltaTRateMeas` | REAL | K/min | 实测温差变化率 / Measured delta-T rate |
| `bDeltaTLimited` | BOOL | — | 温差达上限、升温侧被限（保持）/ Delta-T limiting active |
| `bOverTemp` | BOOL | — | 釜温超设定 + 裕量 / Over temperature |
| `eVerdict` | `E_DL_JacketState`（同文件） | — | `eIdle/eHeat/eCool/eHold/eFault` |
| `eHealth` / `uDiagCode` / `uErrorId` / `bError` | — | — | 健康与码位 |

**状态机（5 态，按温差与 PID 分派）**
```
eIdle(0) --bEnable 且参数合法--> eHold(30)（两路输出 0，等 PID 有效）
eHold --fPidOut > +fDeadband 且未越温差--> eHeat(10)
eHold --fPidOut < −fDeadband--> eCool(20)
eHeat --温差达上限--> eHold（冻结升温，fHeatOut 保持末次有效值并限速回 0）
eCool --釜温低于设定--> eHold
任何态 --非有限或反装--> eFault(99)
ELSE --> 02FE
```

**故障码表**

| 码 | 级别 | 含义 |
|---|---|---|
| `16#0005_01CF` | 信息 | 温差达上限，升温侧冻结 / Delta-T limit reached |
| `16#0005_01D0` | 信息 | 釜温超设定 + 裕量，强制冷却 / Over temperature, forced cooling |
| `16#0005_01D1` | 信息 | 分程重叠区被死区分离（原本会冷热同开）/ Split-range overlap separated |
| `16#0005_02FC` | 故障 | 温度或 PID 输出非有限 / Non-finite temperature or PID output |
| `16#0005_02FD` | 故障 | 温差为负且要求升温（传感器疑似反装）/ Negative delta-T while heating |
| `16#0005_02FE` | 故障 | 非法状态兜底 / Illegal state fallback |

**验收向量**
- **V1**：釜 80 °C、夹套 60 °C、`fPidOut=+40%`、`fDeltaTMax=30` → `eHeat`、`fHeatOut=40.0`、`fCoolOut=0.0`。
- **V2（约束层）**：釜温继续升、`ΔT=31 K` → `bDeltaTLimited=TRUE`、`fHeatOut` 按 `fDeltaTRate` 斜坡回 0、`01CE`。
- **V3（V-C 死区分程）**：`fPidOut=+1.0%`（< 死区 2.0）→ 两路均 0（`eHold`），**不得**两路同开。
- **V4（V-D R36 跟踪首拍）**：上层 PID 从手动跟踪切自动，首拍 `fPidOut` 由 0 跳到 +60% → 本件必须**按 `fDeltaTRate` 限速**（不是限幅），且不得因首次大跳产生 `01CF` 误报。
- **V5（V-A 反装）**：釜 80、夹套 95、`fPidOut=+50%` → `ΔT=−15` 且要求升温 → `02FD` 锁存（**这是最有价值的一条：反装传感器会被这条抓住**）。

---

## 第四部分 · 泳道分配（A / B / C 各 6 件，泳道内按目录分组）

| 泳道 | 序 | 组件 | 目录 | 类型 | 行数预估 | 主要风险点 |
|---|---|---|---|---|---|---|
| **A**（设备健康族） | 1 | `I_DL_DeviceHealth` | DL_Device | IF | 150~200 | 枚举归属与跨文件引用（R33） |
| | 2 | `I_DL_PowerMeter` | DL_Device | IF | 180~230 | 与 A1 枚举复用不得重复声明 |
| | 3 | `FB_DL_ModbusPowerMeter` | DL_Device | FB | 480~560 | R42 换表跨拍 / R39 复位通道 |
| | 4 | `FB_DL_ValveStictionDetect` | DL_Device | FB | 420~500 | **R42 结论发布前复验 / R40 停滞定时器** |
| | 5 | `FB_DL_AhuDamperStuckDiag` | DL_Device | FB | 400~470 | **R40 行程定时器跨段 / 0323 不置 bError** |
| | 6 | `FB_DL_PumpCavitationGuard` | DL_Device | FB | 430~510 | R40 确认定时器 / R43 降速比例夹域 |
| **B**（Level 0 原子族） | 1 | `FC_DL_BitArrayRotate` | DL_Base | FC | 200~250 | 无 64 位移位 / 别名同址安全 |
| | 2 | `FC_DL_MaskCompare` | DL_Base | FC | 170~220 | `nWidth=32` 常量掩码分支 |
| | 3 | `FC_DL_Crc8` | DL_MathData | FC | 190~230 | **R37 截断显式置位** |
| | 4 | `FC_DL_StringToLReal` | DL_MathData | FC | 280~340 | **R38 长度一次锁存 / 逐字符推进** |
| | 5 | `FC_DL_StringFixedField` | DL_MathData | FC | 200~250 | **R37 主战场：先判后写** |
| | 6 | `FC_DL_Matrix3Inverse` | DL_MathData | FC | 220~280 | 相对奇异判据 / 出口不含 NaN |
| **C**（算法·运动·工艺） | 1 | `FB_DL_FoulingResistanceEstimator` | DL_Algo | FB | 380~450 | R19 首扫基准 / R42 门限本拍复验 |
| | 2 | `FB_DL_PassiveHomingMonitor` | DL_Motion | FB | 380~450 | **R31 不碰轴状态 / R41 重建计数** |
| | 3 | `FB_DL_CapperTorqueTrend` | DL_Process | FB | 420~500 | **R24/R25 单拍沿 / R27 结论保持** |
| | 4 | `FB_DL_EscHeLeakCheck` | DL_Process | FB | 420~500 | **R40 三段定时器 / R41 中止恢复** |
| | 5 | `FB_DL_ChamberSeasoningTrack` | DL_Process | FB | 380~450 | **R37 配方名截断 / R27 放行保持** |
| | 6 | `FB_DL_ReactorJacketDeltaT` | DL_Process | FB | 360~430 | **R36 跟踪首拍 / R40 变化率窗** |

**合计预估 6,000~7,300 行**（R12 实测 5,880 行 / 18 件，本轮 6 个 FB 复杂度偏高，预估值上调 5~20%）。
**类型分布**：IF 2 ｜ FC 6 ｜ FB 10。**目录分布**：Base 2 ｜ MathData 4 ｜ Algo 1 ｜ Device 6 ｜ Motion 1 ｜ Process 4。

**并行纪律（沿用 R12 十二段职责分离）**
- 三泳道可并行，但**共享类型先行**：A1 的 `E_DL_Ne107Status` 是 A2~A6 与 C3/C4/C5/C6 的共同依赖 → **A1 必须先落盘并通过自检**，其余件才允许开工（否则会出现三份同名枚举定义）。
- 码位分配**按本文件 §3.0 表**执行，编码者**不得自行取号**；若发现撞号，回退改号并在此表登记，不允许「就近挪一位」。

---

## 第五部分 · 存量 28 处机检遗留清理清单（阶段三执行，具体到行与修法）

> **基线来源**：`audit_library_r12.py` 全库实跑（2026-11-15 21:5x，186 文件）→ `SUMMARY: files=186 fail=28`。
> **两条规则**：`single_colon_or_semicolon`（24 处 / 13 件）+ `placeholder`（4 处 / 4 件）。
> **统一修法原则（R26 家族）**：CASE 分支体**不得**用 `;` 做空语句占位；终端态一律**纯注释占位**。已有同行 `//` 注释的，**删 `;` 保留注释**；已有前置 `(* … *)` 注释块的，**整行删除**。
> **风险等级**：全部为**注释/空语句级**，零语义变更；但**行号会移动**，故必须**从文件底部向上改**（或一次性脚本按「原文精确匹配」替换，不用行号定位）。

### 5.1 `single_colon_or_semicolon`（24 处）

| # | 文件 | 行 | 现状 | 修法（逐条） |
|---|---|---|---|---|
| 1 | `DL_Algo/FB_DL_RampSoakProfile.st` | 226 | `            ;                        // 外部保持：冻结设定值与计时，不积分不迁移` | 删 `;`，行改为纯注释 `            // 外部保持：冻结设定值与计时，不积分不迁移` |
| 2 | `DL_Algo/FB_DL_RampSoakProfile.st` | 245 | `            ;                            // 外部保持：冻结段内计时` | 删 `;`，行改为纯注释 `            // 外部保持：冻结段内计时` |
| 3 | `DL_Algo/FB_DL_RampSoakProfile.st` | 257 | `        ;                                // 保持故障码与设定值，等待 bReset` | 删 `;`，行改为纯注释，并在注释尾部补「（终端态无动作，纯注释占位）」 |
| 4 | `DL_Algo/FB_DL_SplitRangeControl.st` | 159 | `    ;`（上一行已有 `(* 非有限值拍… *)` 双语注释） | **整行删除**（注释已在，删空语句） |
| 5 | `DL_Device/FB_DL_AnalogValve.st` | 249 | `    ;                                 // 故障级码已锁存，信息级不覆盖（…）` | 删 `;`，改纯注释 |
| 6 | `DL_Device/FB_DL_GuardLockDoor.st` | 242 | `            ;                               // 等待复位（Await reset）` | 删 `;`，改纯注释 |
| 7 | `DL_Device/FB_DL_SerialScanner.st` | 277 | `        ;                                   // 等待复位（Await reset, handled in stage 2）` | 删 `;`，改纯注释 |
| 8 | `DL_Device/FB_DL_StarDeltaMotor.st` | 171 | `                ;                     // 过载未复位：静默拒绝（…）` | 删 `;`，改纯注释 |
| 9 | `DL_Device/FB_DL_StarDeltaMotor.st` | 173 | `                ;                     // 联锁未满足：静默拒绝（…）` | 删 `;`，改纯注释 `                // 联锁未满足：静默拒绝（Permit absent: silent refusal）` |
| 10 | `DL_Device/FB_DL_ThreePointValve.st` | 262 | `                ;                             // 双向冲突：安全侧不动…` | 删 `;`，改纯注释 |
| 11 | `DL_Device/FB_DL_VacuumEjector.st` | 199 | `                ;                               // 阈值达成但开关未确认…` | 删 `;`，改纯注释 |
| 12 | `DL_Device/FB_DL_VfdGeneric.st` | 248 | `                ;                                  // 正反转同拍冲突…` | 删 `;`，改纯注释 |
| 13 | `DL_MathData/FB_DL_LifoStack.st` | 205 | `        ;`（上一行 `(* 故障锁存… *)`） | **整行删除** |
| 14 | `DL_MathData/FB_DL_MedianFilter.st` | 247 | `        ;`（`eEmpty` 分支，前有 `(* 空窗… *)`） | **整行删除** |
| 15 | `DL_MathData/FB_DL_MedianFilter.st` | 252 | `        ;`（`eFilling` 分支，前有双行注释） | **整行删除** |
| 16 | `DL_MathData/FB_DL_MedianFilter.st` | 256 | `        ;`（`eReady` 分支，前有 `(* 就绪：整窗中值 *)`） | **整行删除** |
| 17 | `DL_MathData/FB_DL_MedianFilter.st` | 260 | `        ;`（`eFault` 分支，前有 `(* 参数事件当拍… *)`） | **整行删除** |
| 18 | `DL_MathData/FB_DL_SignalStatistics.st` | 283 | `        ;`（`eEmpty` 分支，前有 `(* 无样本… *)`） | **整行删除** |
| 19 | `DL_MathData/FB_DL_SignalStatistics.st` | 288 | `        ;`（`eFilling` 分支，前有双行注释） | **整行删除** |
| 20 | `DL_MathData/FB_DL_SignalStatistics.st` | 292 | `        ;`（`eReady` 分支，前有 `(* 就绪：全部统计量有效 *)`） | **整行删除** |
| 21 | `DL_MathData/FB_DL_SignalStatistics.st` | 296 | `        ;`（`eFault` 分支，前有 `(* 参数事件当拍… *)`） | **整行删除** |
| 22 | `DL_Motion/FB_DL_SoftLimitGuard.st` | 192 | `    ;                             // 保持末次有效位置（Hold last valid position）` | 删 `;`，改纯注释 `    // 保持末次有效位置（Hold last valid position）` |
| 23 | `DL_Motion/FB_DL_SoftLimitGuard.st` | 197 | `    ;                             // 保持末次有效速度（Hold last valid velocity）` | 删 `;`，改纯注释 `    // 保持末次有效速度（Hold last valid velocity）` |
| 24 | `DL_Process/FB_DL_BatchDosingControl.st` | 384 | `            ;                               // 等待复位（Await reset）` | 删 `;`，改纯注释 |

**执行注意**
1. 第 4、13~21 号为「整行删除」，**其余 15 号为「删分号保留注释」**——两者不可混用，混用会丢注释。
2. 上表行号取自 21:5x 实跑；**若靠行号定位，必须从最大行号往小改**（否则前面的删行会让后面行号漂移）。推荐按「行原文（含缩进）」精确匹配替换。
3. 删完后**必须重跑机检**：目标 `single_colon_or_semicolon = 0`。
4. 本项**不改任何语义**，故**不升版**（版本号保持，仅在文档侧记一笔「注释规范化」）。

### 5.2 `placeholder`（4 处：注释内半角省略号 `...`）

| # | 文件 | 行 | 现状片段 | 修法 |
|---|---|---|---|---|
| 25 | `DL_Base/FC_DL_GrayToBinary.st` | 12 | `递推式 B = G XOR (G>>1) XOR (G>>2) ... XOR (G>>(w-1))，` | 把半角 `...` 换成中文省略号 `…`，并在尾部补「（递推至第 w−1 项）」 |
| 26 | `DL_MathData/FB_DL_MovingAverage.st` | 31 | `IF bBufferFull THEN ... ELSE ... END_IF` | 换成 `…` 并在句尾补「（代码骨架，示例省略）」 |
| 27 | `DL_Motion/FB_DL_AxisHomingSeq.st` | 66 | `IF fbHome.bDone THEN ... 上层联动：…` | 换成 `…` 并补「（示例省略）」 |
| 28 | `DL_Process/FB_DL_OccScheduleWindow.st` | 97 | `fbOcc.aWinEnable[1] := TRUE; fbOcc.aHourOn[1] := 8; ...      // 窗组态` | 换成 `…`，或改写为「其余 3 窗同构」——**推荐后者**（语义更明确） |

**判定口径提醒（写进脚本头注释）**：`...` 一律视为省略符（排除 `0...9` 数值上下文），**中文 `…` 不计**。故本项 4 处修完后，`placeholder` 必须为 0，且**不得**用「加白名单」的方式让它变 0。

### 5.3 收口判据

| 项 | 目标 |
|---|---|
| `single_colon_or_semicolon` | **0** |
| `placeholder` | **0** |
| 其余 10 条规则 | 维持 0（回归不得引入） |
| 全库 `fail` | **0**（`SUMMARY: files=204 fail=0`，204 = 186 + 本轮 18） |
| 码位跨文件重叠 | **0**（对本轮 18 件 × 各自码段求差集） |

---

## 第六部分 · 新增机检规则 R37~R40 检测逻辑说明（供编码与终审参照）

> **定位**：这四条是 R12 三条致命缺陷的**文本可捕获部分**。它们**不能**替代逐拍推演（R12 已证明致命缺陷多数在语义层），但能把「看起来合法、实际必然失效」的写法**在提交前拦下**。
> **实现归属**：扩写 `audit_library_r13.py`（在 R12 脚本基础上按规则名可开关），`--rules r37_left_clamp,r38_dual_source,r39_pre_case_override,r40_ton_cross_segment`。

### 6.1 `r37_left_clamp` —— 定长串回夹检测（R37）

**缺陷形态**：用 `LEFT(sBuf, N)` 把拼接结果「回夹」到上限，回夹动作**没有判据** —— 截断发生了，但 `bTruncated` 恒 FALSE、截断码永不置。

**检测逻辑（三条子规则，任一命中即 FAIL）**

| 子规则 | 正则 / 判据 | 说明 |
|---|---|---|
| `r37.1 自赋值回夹` | `^\s*(\w+)\s*:=\s*LEFT\s*\(\s*\1\b` | 同一个变量既作源又作目标 → 典型回夹写法 |
| `r37.2 拼接无上界判定` | 文件内出现 `CONCAT(` 或 `INSERT(`，且**同一文件内**不存在对 `LEN(` 结果与 `DL_STR_MAX` / `STRING(` 宽度常量的比较（`>` / `>=`） | 拼接前没算长度即视为可疑 |
| `r37.3 截断标志死码` | 声明了 `bTruncated` / `bOverflow` 类标志，但**全文无任何** `bTruncated := TRUE`（或 `:= 1`）语句 | 「标志恒假」的机器可查特征 |

**误报抑制**
- 剥离注释（`(* *)` 与 `//` 到行尾）后再匹配；剥离字符串字面量。
- `LEFT` 仅用于「取前缀且不写回原变量」的只读场景（如 `LEFT(sText, 3) = 'ABC'`）不报。
- `r37.3` 的豁免：标志由 `VAR_OUTPUT` 直接透传下层件输出的（形如 `bTruncated := fbSub.bTruncated;`）视为已置位。

**与 R12 致命对应**：`FC_DL_StringReplaceAll` 的 A-D01 三条子规则全部命中（`r37.1` + `r37.3`）。

### 6.2 `r38_dual_source` —— 锁存副本与实时镜像量双源扫描（R38）

**缺陷形态**：先锁存入参（`sFrameLatched := sFrame`），再分拍处理；处理阶段的**边界量**（长度/计数/下标/上限）却取自**实时入参**，而内容取自锁存副本 → 切出「有效但为空」的假段。

**检测逻辑（两条子规则，任一命中即 WARN，命中 `r38.a` 即 FAIL）**

| 子规则 | 判据 | 说明 |
|---|---|---|
| `r38.a 同名双源边界` | 同一文件内同时出现 `LEN(\w+Latched)`（或 `\w+Snap` / `\w+Buf` 后缀）与 `LEN(\1)` 的**同基名**实时量，且两者都参与比较/下标 | 这是 A-D02 的确切指纹 |
| `r38.b 镜像量多点消费` | 对每个形如 `_?\w+(Live|Real|Raw)` 的变量：**引用次数 > 3**（含声明行）→ 告警 | R38 要求「镜像量只能用于变化检测、须能指出唯一消费点」，>3 次引用即违背 |

**误报抑制**
- 变量名不含 `Latch/Snap/Buf/Mirror/Live/Real/Raw` 后缀的，需人工复核（不进机检硬判）。
- `LEN(` 出现在注释或字符串字面量内的剥离。
- 同一表达式内既有锁存量又有实时量但**实时量只做不等比较**（`<>`）的，视为「变化检测」合法用法，不报。

**与 R12 严重对应**：`FB_DL_StringTokenStream` 的 A-D02 命中 `r38.a`。

### 6.3 `r39_pre_case_override` —— `CASE` 前置无条件状态改写检测（R39）

**缺陷形态**：`CASE` **之前**有 `IF` 分支无条件把状态强置 `eIdle`（掉使能/停机分支），于是故障态的复位沿整拍被跳过、需二次复位。

**检测逻辑（两步，命中即 FAIL）**

```
步骤 1：定位所有「CASE 之前的顶层 IF 块」——以 CASE 语句行为界，向上扫描到上一个 END_IF 或段注释边界，
        凡块体内存在对「状态变量」的赋值，记为候选块。
步骤 2：对每个候选块，检查三件事，三者同时成立即 FAIL：
        ① 赋值目标被识别为状态变量：标识符匹配 `(?i)(state|phase|step|mode)`，
           或其声明类型匹配 `E_DL_\w*(State|Phase|Step|Mode)`;
        ② 赋的值为空闲类枚举成员：`eIdle|eStopped|eDisabled|eReset|eWait`;
        ③ 同一 IF 的条件表达式内**不含**下列任一排除写法：
           `<state> <> <Fault>` / `NOT (<state> = <Fault>)` / `<state> <= <NormalMax>`
           （即没有「显式排除故障态」的证据）
```

**误报抑制**
- 该 IF 块体内同时包含 `uErrorId := 0;` 与 `bError := FALSE;`（即**同时清码**）的，判为「完整初始化分支」→ 降为 WARN（但须人工确认复位沿是否也被清）。
- 状态变量为 `VAR_OUTPUT` 且块内**同时**把 `bReset` 沿判据写在其上方的，不报（已把复位提到前面，R39 的合法替代写法）。

**与 R12 严重对应**：`FB_DL_BitArrayChangeWatch` 的 A-D03 命中三条。

### 6.4 `r40_ton_cross_segment` —— 分段监控定时器 `IN` 跨段恒真检测（R40）

**缺陷形态**：单步/单段/单相语义的 `TON`，其 `IN` 在一个**连续态集合**内恒真，而集合内存在段推进写入 → `ET` 跨段累加，合规批次被判超时。

**检测逻辑（三步）**

```
步骤 1：收集所有 TON/TOF 实例调用，抽取 (实例名, IN 表达式, PT 表达式)。
步骤 2：对每个实例，抽取其 IN 表达式里的「根 BOOL 变量集合」S（去掉 NOT/AND/OR 结构）。
步骤 3：在所属 CASE 内统计：
        ① S 中任一变量在**同一 CASE 的不同标签分支**里被赋 TRUE → 说明它是「跨段保持型」；
        ② **全文**中该变量被赋 FALSE 的次数 == 0；
        ③ 该 CASE 内存在段推进写（形如 `<step/nSeg/nPhase> := <step> + 1` 或 `:= e<Next>`）。
        ①②③ 同时成立 → FAIL（判「跨段恒真」）。
```

**误报抑制**
- IN 表达式内含 `NOT bXxxBreak`（断输入拍标志）的，直接 PASS（这是 R40 的**合规写法**指纹）。
- IN 表达式为纯比较式（如 `IN := (fErr > fTol)`）而非状态位，不在此规则范围（其语义是「条件成立即计时」，跨段合法）。
- 总时长类定时器（`IN := bEnable` 且语义为「累计运行时长」）需人工排除：建议以「实例名含 `Watch`/`Step`/`Seg`/`Phase`」为硬判范围，其余降 WARN。

**与 R12 致命对应**：`FB_DL_BatchPhaseBase` 的 B-D01 命中三步；`FB_DL_LineInterp2Axis` 的 B-D04（恢复相转出）属 R41 家族，文本侧由「转出判据是否只用单条件」的**人工向量**兜底，本轮不做机检。

### 6.5 四条规则的本轮直接收益

| 规则 | 本轮必然命中的目标件 | 说明 |
|---|---|---|
| `r37.1/r37.3` | `FC_DL_StringFixedField`（**自检用**：本件必须能通过） | 编码时先跑，确保样板本身不含回夹 |
| `r37.2` | `FC_DL_StringToLReal`（逐字符推进，不应命中） | 若命中说明实现里混进了 `LEFT` 回夹 |
| `r38.b` | `FB_DL_Cap…` 无；`FB_DL_ValveStictionDetect`、`FB_DL_PassiveHomingMonitor`（缓存与实时量并存） | 这两件必须能**指出镜像量的唯一消费点** |
| `r39` | A 泳道六件（都有 `bEnable=FALSE` 冻结分支） | **最高危**：冻结分支不得屏蔽复位通道 |
| `r40` | `FB_DL_AhuDamperStuckDiag`（行程定时器）、`FB_DL_EscHeLeakCheck`（三段）、`FB_DL_Cavitation`（确认定时器）、`FB_DL_ValveStictionDetect`（停滞定时器） | 四件全部涉分段定时 |

---

## 第七部分 · 给编码泳道的关键注意事项（历史沉淀范式逐条点名）

> 只列**与本轮 18 件直接相关**的范式；未列出的（如 R1/R2/R3 基础红线、R28 注释不可嵌套、R29 赋值目标声明性、R30 码位自证循环、R32 写入点排序）仍为全库通用，照旧执行。

### 7.1 逐条点名（按范式编号）

| 范式 | 一句话 | 本轮命中件 | 具体要求 |
|---|---|---|---|
| **R19** 首扫标志唯一合法范式 | `bInit` 初值 FALSE，首扫判据一律 `NOT bInit`；禁止 `IF bInit OR bTrack` | `C1`（趋势基准装载）、`A3`（电能基准）、`A4`（窗口基准）、`C6`（PID 首拍）、`B4/B5/B6`（纯函数不设 bInit，**这是裁定**） | 纯函数**一律不设** `bInit`（R23 裁定的延伸：无跨周期状态即无首扫问题）；带基准装载的 FB 首扫**只装基准、不做判据** |
| **R24** 定宽脉冲/单拍触发 | 置位点在实例调用**之前**，自清紧随调用**之后** | `C3` `bCycleStart`、`C4` `bStart`、`C5` `bWaferDone`、`C2` `bArm` | 四个沿输入统一用 `R_TRIG` **在段 2 无条件刷新**，消费后置 `_bXxxConsumed`，自清语句紧随 `R_TRIG` 调用之后 |
| **R25** 单拍标志三律 | 预清零 / 实例后自清 / 消费拍与转出拍分离 | `C3`/`C4`/`C5`/`C2` 四件的沿输入（与 R24 同一批）+ `A6` `bDerateRequest`（**注意：这是保持位，不是单拍，见 R27**） | 每件在头注释列「单拍标志清单」，逐个标注「预清零点 / 置位点 / 自清点」三行 |
| **R27** 输出保持语义 | 保持态的输出必须**每拍重写**，不得只靠进入那拍的脉冲 | `C3` `eVerdict`/`bVerdictValid`、`C4` `bDone`/`bPass`、`C5` `bRelease`、`C2` `bReferenced`、`A4` `eStiction`、`A6` `bDerateRequest`/`fDerateRatio`、`A5` `eDiag` | 七件必须在**结论态内逐拍重写**出口；复位/新启动沿清除。头注释写「保持位清单」 |
| **R31** 枚举→CASE 双向映射 | 每个枚举值**有且仅有一个**显式标签；`ELSE` 只接脏值 | **全部 10 个 FB** + 2 个接口同文件枚举 | 每件随附「枚举全值 → 标签」映射表（放在头注释或 MANUAL）；动作写在 CASE 外的，**必须保留空标签分支 + 原因注释**（本轮 24 处 `;` 遗留正是这条的反面教材：空分支要写**注释**，不是写 `;`） |
| **R33** 枚举成员用 `:=` | 单冒号即编译阻断 | 本轮新增 6 个枚举（`E_DL_Ne107Status`、`E_DL_PowerMeterState`、`E_DL_StictionLevel`、`E_DL_DamperDiag`、`E_DL_Crc8Variant`、`E_DL_CapperVerdict` 等） | 全部 `成员 := 值,` + 同行双语注释；**跨文件复用**时只引用不重定义（`E_DL_Ne107Status` 唯一属主 = A1） |
| **R34** 状态量生命周期四律 | 预清零→唯一置位→**递减/消费**→自清 | `A4` `nStallCount`（只增）、`C2` `nEventCount`（本轮布防内计数，**必须有复位点**）、`C5` `nCount`（复位清零） | 「剩余次数」型变量（`C2` 的 `nRequireEvents` 倒计）**置位点与递减点同段相邻**，全文出现 ≥3 次 |
| **R35** 守卫与判据同向 | 守卫 `< MAX` 封顶就必须 `>= MAX` 判据 | `A4` `fDeadbandMax` / `fDeadbandModerate`、`A6` `fVibLimit`（×2 倍急停）、`B6` `fDetEps`、`C3` 峰值上下限、`C5` `nConsecNgLimit` | 每件随附「三元一致表」（守卫 / 封顶值 / 判据运算符）三行，写在头注释 |
| **R36** 跨件调用须手算跟踪首拍 | 按 `fInt := fOut − fP − fD` 反算残量 | `C6`（消费 `fPidOut`）、`A6`（向 `RateLimiter` 输出）、`C1`（无闭环但需 `fKClean` 基准一致性） | `C6` 头注释必须写「调用方须保证 `fPidOut` 已过跟踪首拍」；V4 向量复现该场景 |
| **R37** 定长串截断显式置位 | 写回前预判长度，超限即置标志与码；禁 `LEFT` 回夹 | **`B5`（主战场）**、`B4`（解析不带回夹）、`C5`（`sRecipeName` 32 字符截断）、`B3`（`bTruncated` 必须真置位） | `B5` 是**样板件**：`nSrcLen := LEN(sValue)` 一次 → 与 `nWidth` 比较 → `bTruncated := TRUE` → 再决定写出/拒绝。**顺序不可颠倒** |
| **R38** 锁存副本 vs 实时镜像 | 边界量必须由锁存副本自身导出 | `B4`（`nLen` 一次锁存）、`B5`（`nSrcLen` 一次锁存）、`A4`（窗口样本缓存 vs `fPos` 实时）、`C3`（`nPoints` 锁存后不再读入参）、`C2`（`fActPos` 采样点） | 每件头注释列「镜像量清单 + 唯一消费点」；机检 `r38` 两条子规则必须过 |
| **R39** 停机分支不得屏蔽复位 | `CASE` 前的强制空闲分支须排除故障态 | **A3/A4/A5/A6 四件全部高危**（都有 `bEnable=FALSE` 冻结或掉使能分支）；`C1/C2/C3/C5` 亦有 | 两种合法写法择一：①`IF NOT bEnable AND (eState <> eFault) THEN`；②把复位沿判据**提到**该分支之前。**不得**两种都不做 |
| **R40** 分段定时器按段断输入 | 段边界置断输入拍，`IN` 串 `NOT bXxxBreak` | **`A4`（停滞定时器）、`A5`（行程/偏差/IO 三个）、`A6`（确认定时器 + 抑制窗）、`C4`（升压/稳压/测量三段）、`C6`（变化率统计窗）** | 每件头注释列「定时器清单」：实例名 / `IN` 表达式 / 段边界断输入标志名 / 自清位置。**这是本轮最高密度的缺陷区** |
| **R41** 恢复转出不得只看已完成量 | 恢复须校验过程量或按剩余量分流 | `C2`（重新布防必须重建计数）、`C4`（中止重启从 0 计时）、`A4`（挂起恢复重建窗口）、`C3`（新周期重新采样） | 四件的 V4 向量必须显式覆盖「恢复首拍」 |
| **R42** 跨相取值本拍复验 | 判可用与取值同拍 | **`A4`（分析相缓存 → 判定相发布，必须本拍复验 `bPosValid`）**、`C1`（趋势相复验流量门限）、`A6`（降速相复验判据）、`A3`（换表相复验原始值） | 每条「用上一相结论」的路径，都要能指出本拍复验语句所在行号 |
| **R43** 保持替代回零须夹域 | 保持值必须 `MIN/MAX` 钳进有效域 | `A4` `fDeadbandEst`（0~100）、`A6` `fDerateRatio`（0.3~1.0）、`A5` `fDeviation`（−100~100）、`C2` `fOffsetToApply`、`B6` `afInv`（失败置 0 不置 NaN）、`C4` `fLeakRate`（≥0） | 每条输出赋值路径都能追到**一次钳位**；冷启动首拍输出域内值 |
| **R44** 周期核对信息码按周期清 | 清码点绑定「新一轮开始」 | `A3`（每个采样窗）、`C5`（每片/每轮）、`A4`（每个分析窗）、`C3`（每个拧紧周期） | 四件的清码点写在新轮起点，**不得**只在 `bReset` 沿清 |

### 7.2 本轮六条「专项纪律」（不属于既有范式，但必须执行）

1. **`E_DL_Ne107Status` 唯一属主原则**：只有 A1 的文件可以 `TYPE E_DL_Ne107Status :`。其余 9 件引用时写 `eHealth : E_DL_Ne107Status;`，**禁止复制枚举体**。编码者若在 B 泳道或 C 泳道「顺手」定义同名枚举 → 直接判废（R33 家族超集）。
2. **`0323`（A5 Deviation）不置 `bError`**：本库首次出现「故障带码 + 不置 bError」组合。头注释必须写理由（仍可运行 ≠ 可继续运行），MANUAL 故障码表必须新增「是否置 bError」列。
3. **`DL_Process` 四件不得内联底层算法**：统计 → `FB_DL_SignalStatistics`；分位 → `FC_DL_PercentileLReal`；限速 → `FB_DL_RateLimiter`；PID → `FB_DL_CascadePid`；开方/插值 → `FC_DL_NthRoot` / `FC_DL_MultiPointLinear`。**内联一次即违反依赖方向**（`DL_Process` 可依赖低层，但不能**复制**低层能力）。
4. **`DL_Motion` 只碰一个工艺位**：C2 只输出 `bReferenced`，**不定义** `E_DL_AxisState` 之类轴状态枚举，不写 `MC_Power` 语义位。轴状态归 `I_DL_MotionAxis`。
5. **纯函数不设实例状态**：B 泳道六件全部 FC，**禁止**为了「方便」改成 FB 缓存上次输入（会破坏「同输入同输出」的验收可复算性）。
6. **码位取号只认 §3.0 表**：本轮已按实扫结果重算（R12 台账已过期），编码者不得自行偏移；发现撞号的，登记在本文件 §3.0 下方「码位变更登记」小节（本轮为空）。

### 7.3 每件交付物清单（缺一不放行）

| # | 交付物 | 说明 |
|---|---|---|
| 1 | `.st` 文件 | 文件名 = POU 名，落在指定子库目录 |
| 2 | 头注释七项 | 名称 / 子库 / 版本 / 兼容性 / 功能 / 开源溯源 / 修订历史（+ 本轮增补：分层声明、段序、码位表、验收向量、偏离留档） |
| 3 | 枚举映射表 | 每个枚举全值 → CASE 标签（R31） |
| 4 | 单拍标志清单 | 预清零 / 置位 / 自清 三点（R25） |
| 5 | 保持位清单 | 逐拍重写点（R27） |
| 6 | 定时器清单 | 实例 / `IN` / 断输入标志 / 自清（R40） |
| 7 | 三元一致表 | 守卫 / 封顶 / 判据运算符（R35） |
| 8 | 验收向量 | ≥4 条，含 V-A/V-B/V-C/V-D 四类（§3.0 ④） |
| 9 | 机检报告 | `audit_library_r13.py --files <本件>`，12 + 4 条规则全 0/无 FAIL |

---

## 第八部分 · 本轮不做的事（边界声明）

| 项 | 状态 | 理由 |
|---|---|---|
| 写 `.st` 代码 | **不做** | 本阶段只到「规格可直接编码」 |
| 改 `INDEX_REGISTRY.json` | **不做** | 注册属阶段四 |
| 改 `_AI_Training_Dataset\*.jsonl` | **不做** | 语料注入属阶段四 |
| 改 `ROADMAP.md` 池子 | **不做（仅记录待勾选清单）** | 池内 314 条 ≫ 30 条门槛，无扩容必要；8 件对应行的勾选动作留阶段四随交付一并做（清单见 §1.4） |
| 改 `SOURCE_HUNTING_MATRIX.md` | **不做（仅在本文件与 RAW_NOTES 提出勘误 M-E4~M-E6）** | 矩阵回写属阶段五，避免与战报口径冲突 |
| 存量 28 处修复 | **不做（清单已出）** | 属阶段三，须与代码同批提交并重跑机检 |
| 编译验证（连续 13 轮悬置） | **不做** | 本轮无编译器环境；R13 战报须继续按 R12 口径输出「替代验证方案 + 无法替代的风险清单」，并在 `README` / `LIBRARY_MANUAL` 标注「未经编译验证」 |

---

## 第九部分 · 交付摘要

| 项 | 内容 |
|---|---|
| 本轮目标 | **18 件**（泳道 A 6 / B 6 / C 6），六子库全部有新增 |
| 覆盖配额 | **T2 4 源**（含 NE107 全新族）+ **T1 4 源** → 双向满足 |
| 新开 | 组 0（已无 ☐ 组）/ **子族 3**（NE107 / LGF Matrix / LGF CRC8） |
| 预估规模 | 6,000~7,300 行；库版本 v2.1.0 → **v2.2.0**；总库 186 → **204** |
| 今日进度 | 160 → **178 / 200（89.0%）** |
| 规格文件 | `C:\Library\_Staging_Raw\2026-11-15\ROUND_PLAN_R13.md`（本文件） |
| 留痕文件 | `C:\Library\_Staging_Raw\2026-11-15\RAW_NOTES_R13.md` |
| 存量清理清单 | 本文件 §5（28 处，含行号与逐条修法） |
| 新增机检规则 | 本文件 §6（R37~R40 四组、10 条子规则、误报抑制口径） |
| 编码前必读 | 本文件 §3.0（通用约定）+ §7（范式点名）+ 各件规格的「编码注意」 |

---

*ROUND PLAN R13 ｜ 2026-11-15 ｜ 道莅工控代码库产品总监（兜底模式）｜ 阶段一 + 阶段二交付*
