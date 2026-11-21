# ROUND_PLAN_R3 ｜ 道莅万级工业代码库 · 第三轮需求规格书

> **文档编号**：DL-RP-2026-11-14-003
> **阶段**：Phase 1 第三轮 ｜ Level 0 收口轮（DL_Base 20/20 + DL_MathData 20/20 → 40/40）
> **本轮范围**：**14 个组件**（4 个 DL_Base + 10 个 DL_MathData），名单锁定，不增不删
> **撰写人**：道莅工控代码库产品总监（Daoli Library Director）
> **下游执行**：PLC 编程专家（编码 Agent）—— **本文件不含任何 .st 实现代码，禁止在本阶段产出 .st 文件**
> **编制日期**：2026-11-14 23:40
> **情报支撑**：`C:\Library\_Staging_Raw\2026-11-14\RAW_NOTES_R3.md`（7 条检索记录）
> **上游输入**：`INDEX_REGISTRY.json`（26 条）、`ROADMAP.md`（Phase 1 未勾选项）、`SOURCE_HUNTING_MATRIX.md`（三铁律 / 11 组映射 / 5 条扩产规则 / 第 5 节台账）、`AGENT_EVOLUTION_LOG.md`（R1~R15 规则库、Round 02 第五节吞吐方案）
> **本轮性质**：只做**阶段一（盘点去重）+ 阶段二（取源与轮次计划）**。不写 `.st`、不改 `INDEX_REGISTRY.json`、不动 JSONL、不勾 `ROADMAP.md`。

---

## 0 纪律与判定口径

### 0.1 硬性纪律

| # | 纪律 | 违反后果 |
|---|---|---|
| D1 | **本轮零 `.st` 文件**。编码由下一位 PLC 编程专家执行 | 越权交付，接口与实现脱节 |
| D2 | 接口契约逐字以第 7 章为准，不得擅自增删引脚；确有缺陷走「变更申请」回写本文件 | 索引/手册/训练集三方漂移 |
| D3 | 任何组件不得引用 `DL_Algo` / `DL_Device` / `DL_Motion` / `DL_Process` 类型 | 破坏分层单向依赖 |
| D4 | `DL_MathData` 可依赖 `DL_Base`，反向禁止 | 循环依赖 |
| D5 | 命名一律 `FB_DL_` / `FC_DL_` / `E_DL_` / `ST_DL_`，文件名 = POU 名 | 索引无法自动对齐 |
| D6 | 本轮**零内部依赖**（见 §5），禁止清单外引用 | 依赖图失控 |
| D7 | 沿用 R1~R15 全部规则；本轮新增待批规则 **R16 / R17**（见 §10.3） | 质量倒退 |
| D8 | **不修改** `ROADMAP.md` 勾选、`INDEX_REGISTRY.json`、`_AI_Training_Dataset/*.jsonl` | 越权写入，阶段五再做 |

### 0.2 红线口径（沿用 R1~R15，不重定义）

R1 零全局 ｜ R2 零地址 ｜ R3 纯 IEC（无指针/引用/厂商库/隐式转换）｜ R4 防除零·防越界·浮点容差·循环防死锁 ｜ R5/R9 中文+英文+单位同行注释 ｜ R6 `ENUM`+`CASE`+`ELSE` ｜ R7 定时器/沿实例无条件刷新 ｜ R8 无魔法数 ｜ R10 注释不自伤（不写被禁符号）｜ R11 偏离须头注释留档 ｜ R12 向量实测复算 ｜ R13 时序类必须逐扫描推演 ｜ R14 语义参数变更须断输入一拍 ｜ R15 锁存码只由解除路径清除。

> **R14 本轮特别适用**：`FB_DL_MedianFilter` / `FB_DL_SignalStatistics` 的 `nWindow` 属语义参数，运行中变更必须**整窗作废重填**；`FB_DL_DutyStandbyRotation` 的 `nDemand` 变更属语义变更，须按「先加后减」重排。

---

## 1 阶段一 · 盘点结论

### 1.1 库现状（读取 `INDEX_REGISTRY.json` 与目录实测）

| 指标 | 数值 | 依据 |
|---|---|---|
| 总库累计 | **26 / 10,000** | `INDEX_REGISTRY.json.total_components = 26` |
| Phase 1（首批 100） | **26 / 100** | `ROADMAP.md` 首部 |
| Level 0 收口 | **26 / 40**（DL_Base 16/20、DL_MathData 10/20） | `ROADMAP.md` L8 |
| 今日入库 | **26 / 200**（达成率 13%） | `DAILY_STATS_R2.md` |
| 文件 / 索引 / 语料三方 | 26 = 26 = 26 | 目录实测 + JSONL 行数口径 |
| Level 1 / Level 2 | 0 / 45、0 / 15 | 六目录仅 Level 0 有 `.st` |

### 1.2 已入库 26 项的功能簇归类（去重基线）

| 簇 | 组件 | 覆盖能力 | 本轮是否触碰 |
|---|---|---|---|
| 信号整形与时序 | SignalDebounce、DualEdgeTrig、ExtendedTimer、PulseGenerator、CycleTimeMeasure、WatchdogMonitor | 抖振消除、双边沿、四模式定时、方波、周期统计、心跳 | 否（仅 TwoHandSafety 复用「TON 语义」写法，不调用） |
| 位与字操作 | BitGet、BitSet、BitCount、PackBitsToWord、UnpackWordToBits、GrayToBinary、BinaryToGray | 位索引、位统计、16 路打包/解包、格雷码 | 否 |
| 报警与顺控 | AlarmManager、StepSequencer | 16 路优先级仲裁+首出锁存、通用步引擎 | **InterlockMatrix 与之相邻，见 §1.4 辨析** |
| 运行统计 | RuntimeMeter | 累计运行时间（时/分/秒）+ 启停次数 | **DutyStandbyRotation 与之相邻，见 §1.4 辨析** |
| 数学基础 | LinearScale、Deadband、Hysteresis | 两点线性定标、死区、迟滞 | **MultiPointLinear 与之相邻，见 §1.4 辨析** |
| 滤波 | MovingAverage、RingBufferLReal | O(1) 滑动均值、FIFO 环缓 | **MedianFilter / LifoStack 与之相邻，见 §1.4 辨析** |
| 通信与字节序 | Crc16Modbus、SwapBytes16、SwapBytes32 | CRC-16/Modbus、16/32 位字节序 | **Crc32Ethernet / LrcChecksum 与之相邻，见 §1.4 辨析** |
| 字符串 | StringTrim、StringSplit | 首尾空白清理、分隔符拆分 | **HexStringToBytes 与之相邻，见 §1.4 辨析** |

### 1.3 本轮 14 项 = `ROADMAP.md` 全部未勾选 Level 0 项

逐条核对 `ROADMAP.md`（L21~L71）未勾选项，恰为 14 项，与本轮清单**完全一致**，无遗漏、无越界：

- `DL_Base` 未勾选 4 项：TwoHandSafety、InterlockMatrix、RedundantSwitch、DutyStandbyRotation
- `DL_MathData` 未勾选 10 项：MultiPointLinear、PolygonArea、LineIntersection、Crc32Ethernet、LrcChecksum、LifoStack、MedianFilter、SignalStatistics、QuickSortLReal、HexStringToBytes

### 1.4 去重论证（14 项 × 各自最接近的已入库组件）

> 判定标准：**若两项的输入域、输出语义、故障判据三者中有两项可被另一项替代，即判重复**。下表逐项给出「不可替代的那一条差异」。

| # | 本轮组件 | 最接近的已入库组件 | 不可替代的差异（去重判据） |
|---|---|---|---|
| 1 | `FB_DL_TwoHandSafety` | SignalDebounce / DualEdgeTrig | 前者输出的是**双通道同步性判定 + 防旁路状态机**（同步窗、释放窗、卡死诊断、上电禁止启动），不是单路滤波或单沿；无任何已入库组件持有「双手」语义 |
| 2 | `FB_DL_InterlockMatrix` | AlarmManager | AlarmManager 输出**报警优先级与首出报警**（面向 HMI 呈现，16 路独立报警态）；InterlockMatrix 输出**单一运行许可 `bPermitToRun`**（面向设备启动允许），带**条件极性掩码**与「复位后仍须全部恢复」的重启闭锁；两者输出契约不同，不可互替 |
| 3 | `FB_DL_RedundantSwitch` | Hysteresis / Deadband | 前者做**通道选择与无扰过渡**（选谁、怎么切、切多快、何时不许切），后两者只做**单值整形**（压死区、加回差）。冗余切换必须处理「双通道互相矛盾时不猜」这一决策分支，整形函数无此语义 |
| 4 | `FB_DL_DutyStandbyRotation` | RuntimeMeter | RuntimeMeter 是**单机计时器**（时/分/秒呈现 + 保养预警）；本组件是**8 机调度器**（排序、需求台数、最小运行/停机、故障跳过、轮值）。计时是它的内部手段而非输出目的，故不复用 RuntimeMeter（见 D-R3-05） |
| 5 | `FC_DL_MultiPointLinear` | LinearScale | LinearScale 是**单段两点定标**（量程→工程量）；本函数是 **N 段折线查表 + 二分查找 + 段号输出 + 区间外策略**。单段是 N=2 的退化情形，但 N≥3 的非线性标定无法用 LinearScale 表达 |
| 6 | `FC_DL_PolygonArea` | （无） | 全库无几何量计算组件 |
| 7 | `FC_DL_LineIntersection` | （无） | 同上 |
| 8 | `FC_DL_Crc32Ethernet` | Crc16Modbus | 位宽（32 vs 16）、多项式（`16#EDB88320` 反射 vs `16#A001`）、初值/终值异或（均 `16#FFFF_FFFF` vs 全零）三者全不同；且新增**分块链式 seed 语义**，Crc16Modbus 无此接口 |
| 9 | `FC_DL_LrcChecksum` | Crc16Modbus | LRC 是**算术补码校验**（加法 + 取补），CRC 是**多项式余数**；两者对同一帧给出不同结果，不可互算。Modbus ASCII 现场设备只认 LRC |
| 10 | `FB_DL_LifoStack` | RingBufferLReal | RingBuffer 是 **FIFO**（写头+读头双指针、回绕、可求平均）；LIFO 是**单栈顶指针、无回绕、后进先出**。同一数据序列的输出顺序完全不同，不可替代 |
| 11 | `FB_DL_MedianFilter` | MovingAverage | 均值滤波是**线性**运算，单个尖峰会被摊到整个窗口（10 个样本里 1 个 100 会把均值抬高 9）；中值是**次序统计量**，尖峰被整体剔除。二者对脉冲干扰的响应本质不同 |
| 12 | `FB_DL_SignalStatistics` | MovingAverage | MovingAverage 只输出均值；本组件输出**均值/最大/最小/峰峰值/样本方差/标准差/样本数**七元组，且方差用**两遍法**（先均值后离差平方和），不可由均值递推替代 |
| 13 | `FC_DL_QuickSortLReal` | （无） | 全库无排序能力；且本轮强制**显式栈迭代**，禁止递归（见 D-R3-01） |
| 14 | `FC_DL_HexStringToBytes` | StringTrim / StringSplit | 后两者处理**文本结构**（空白、分隔符）；本函数处理**字符到字节的数值解码**（nibble 合成 + 合法性判定 + 定位非法字符）。StringSplit 无法完成 `"1A2B"` → `16#1A, 16#2B` |

**结论**：14 项与已入库 26 项**零功能重叠**；14 项之间亦无重叠（几何两项分属「面积/质心」与「交点」，数据结构两项分属 FIFO 语义外的 LIFO，滤波两项分属线性/非线性）。

### 1.5 是否替换？—— 逐项裁决：**不替换**

任务允许「工程价值不足可替换」，逐项复核后维持原清单，理由如下（不做替换是本轮的**主动决策**，不是惰性）：

| 组件 | 价值复核 | 裁决 |
|---|---|---|
| `FC_DL_PolygonArea` / `FC_DL_LineIntersection` | 看似小众，实为**视觉引导与机器人平面作业的最小几何原语**：贴装偏转角、料框有效面积、皮带跑偏交点、两相机视场交叠区都直接调用。且二者是本库**唯一**的几何族种子，缺位则 Level 1 `DL_Motion` 的视觉纠偏只能内联实现（违反「低层能力不得内联」纪律） | 保留 |
| `FC_DL_LrcChecksum` | 老设备（电表、称重仪表、部分国产温控）仍大量使用 Modbus ASCII；与 Crc16Modbus 构成**完整 Modbus 校验族**，避免现场临时手写 | 保留 |
| `FB_DL_LifoStack` | 与 RingBuffer 是**语义对偶**，解析器/路径回溯/撤销栈的唯一正确结构；缺位会导致调用方拿 FIFO 硬凑 LIFO | 保留 |
| `FC_DL_QuickSortLReal` | 统计与报表链路（分位数、去极值均值）依赖排序；且它是本轮**唯一能沉淀「禁递归」范式**的载体 | 保留 |
| `FC_DL_HexStringToBytes` | 是 `FC_DL_LrcChecksum` 的天然前置（ASCII 帧→字节），二者配套才能完成一次 Modbus ASCII 收帧闭环 | 保留 |

### 1.6 源矩阵覆盖率（`SOURCE_HUNTING_MATRIX.md` 第 5 节台账实测）

| 指标 | R2 结束时 | R3 完成后（预期） |
|---|---|---|
| 台账行数 | 21 行 | 22 行（新增 IEC 60204-1/ISO 13851 一行，见 §8.3） |
| 已挖掘 `✔`（组已挖尽） | **0 行** | **0 行** |
| 部分挖掘 `◐` | 3 行（T1-1 OSCAT Basic、T1-3 OSCAT Network、T2-5 Mod_PID） | **11 行** |
| 覆盖率（`◐`+`✔` / 总行） | 3/21 = **14.3%** | 11/22 = **50.0%** |
| LGF 11 组「组打开率」 | 0/10（Legacy 不实现，按 10 组计） | **5/10**（math、datahandling、converter、measurement、comparator） |
| LGF「组挖尽率」 | 0% | **0%**（每组容量 15~30，本轮每组仅取 1~3 项） |

> **这是本轮最重要的产品判断**：LGF 十组在本轮之前**一组未动**，说明前两轮全靠 T1 原生源与通用规范撑起 Level 0。R3 首次打开 5 个 LGF 组，但每组只取了 1~3 个原子件——**组打开 ≠ 组挖尽**。万级目标的主战场在第 2 节的「横向重载」，而不是继续在 Level 0 里找新品类。

---

## 2 今日进度、200/日差距与追赶计划

### 2.1 今日账（截至 2026-11-14 23:40）

| 项 | 数值 | 说明 |
|---|---|---|
| 今日入库 | **26 / 200** | R1 14 项 + R2 12 项 |
| 达成率 | **13.0%** | — |
| 缺口 | **174** | 不是 174 个「没写」，而是 174 个「今天不可能再写」 |
| 今日剩余窗口 | **≈ 20 分钟** | 当前 23:40，日界 24:00 |
| 本轮 14 项落点 | **11-15 凌晨** | 计入 11-15 的 200 配额，不计入今日 |

**必须说清的结论**：今日 174 的缺口**不可能闭合**，原因不是产能，是**日历边界**。任何「今天补完 174」的计划都是自欺。真正的处置是：把 R3 作为 11-15 的**第一波**（凌晨即产 14 项），让 11-15 从 14 起步而不是从 0 起步。

### 2.2 产能模型（用实测反推，不用口号）

R2 实测口径（`AGENT_EVOLUTION_LOG.md` Round 02 第五节）：12 个组件，编码 ≈ 1.5 h，读码终审 + 双语手册 ≈ 3 h，**单组件全流程 ≈ 0.35 h（21 min）**。

| 参数 | 现状 | 200/日所需 | 差距 |
|---|---|---|---|
| 单组件全流程工时 | 0.35 h | ≤ 0.12 h（7.2 min） | **需压缩 66%** |
| 并行 Agent 数 | 1（串行） | 1 人需 8.75 并行才成立 | 加人**不经济** |
| 日有效工时 | 8 h | 8 h | — |
| 实际日产能 | 8 / 0.35 ≈ **23 项/日**（与 26 实测吻合） | 200 | **8.7×** |

> **判断**：靠「再加两个人」到不了 200/日（需 8.75 并行，协调成本会吃掉收益）。唯一可行路径是**把单组件工时压到 7 min 量级**，再配 3 并行 → 3×8/0.12 = 200。压缩的三个杠杆按收益排序：

| 杠杆 | 现状耗时 | 目标 | 手段 | 依据 |
|---|---|---|---|---|
| **L1 手册模板化** | 15 min/组件 | 5 min | 引脚表/故障码表/示例从头注释 + 索引自动抽取，只人工写「定位 / 联调要点」两段 | Round 02 第五节第 2 条 |
| **L2 R13 推演脚本化** | 终审 3 h/轮 | 40 min/轮 | `_Tests/sim/<组件>.py` + 期望值表，全量跑脚本，人工只读差异点 + 1 个最高复杂度件 | Round 02 第五节第 1、3 条 |
| **L3 规格前置 2 波缓冲** | 编码等规格 | 0 等待 | 规格书永远领先编码 2 个波次（本轮即 L3 的第一次实践：14 项规格一次出完） | 本文件 |

### 2.3 追赶计划（爬坡曲线，不用「满负荷 200」骗自己）

| 日期 | 当日目标 | 累计 | 关键动作 | 校验点 |
|---|---|---|---|---|
| 11-14（今日） | **26（实绩）** | 26 | R3 规格书 + 狩猎笔记落盘（本文档） | Level 0 规格收口 |
| 11-15 | **74** | **100** | 凌晨 R3 14 项 + 日间 3 波 × 20 项；L1/L2 杠杆上线（工时压至 0.22 h） | **Phase 1 收口 100/100** |
| 11-16 | 120 | 220 | 3 并行；工时压至 0.18 h | 单波 20 项稳定 |
| 11-17 | 160 | 380 | 规格缓冲扩至 2 波；`_Tests/sim` 覆盖时序类 100% | 返修率 < 5% |
| 11-18 | **200** | 580 | 3 并行 × 5 波 × 14 项 ≈ 210 上限 | 首次达成 200/日 |
| 11-19 起 | 200/日 | — | 稳态 | 累计 10,000 约 **2027-01-03**（26 + 50 × 200） |

**爬坡约束（写死，防止为凑数降标准）**：
1. **单组件工时压缩不得以降低红线为代价**——R1~R15 逐条照旧机检，`_Tests/sim` 未覆盖的时序类组件不得入库。
2. **每波必须至少 1 个 T2 组**（`SOURCE_HUNTING_MATRIX.md` §4 配额），否则万级之后全是同质重载，失去「组」的纵深。
3. **每波 14 项内必须 ≥ 2 个 H 级组件**（复杂度 8~9），否则库会退化成「几百个 BitSet」。

### 2.4 对 200/日 目标的诚实评价

200/日 × 50 天 = 10,000，数学成立；但**只有当 L1/L2/L3 三个杠杆同时生效**才成立。当前杠杆全部为 0（手册仍手写、`_Tests/sim` 目录不存在、规格与编码同波）。因此 11-15 的 74 项是**杠杆上线验证日**，不是「冲量日」；若 11-15 未达 74，11-18 的 200 必须顺延，**不得用降标准的组件填数**。这是产品总监对本目标的唯一承诺口径。

---

## 3 本轮目标清单（14 项，名单锁定）

| # | 组件 | 子库 | 类型 | 返回类型 | 复杂度 | 来源标签（`function_tags` 必含） | 源级别 |
|---|---|---|---|---|---|---|---|
| 1 | `FB_DL_TwoHandSafety` | DL_Base | FB | — | M（6） | `iec60204`、`iso13851` | T2 标准线 |
| 2 | `FB_DL_InterlockMatrix` | DL_Base | FB | — | M（7） | `isa18-2`、`lgf-bitlogic` | T2 |
| 3 | `FB_DL_RedundantSwitch` | DL_Base | FB | — | H（8） | `lgf-comparator`、`redundancy` | T2 |
| 4 | `FB_DL_DutyStandbyRotation` | DL_Base | FB | — | H（9） | `lbp-basic-process`、`lead-lag` | T2 |
| 5 | `FC_DL_MultiPointLinear` | DL_MathData | FC | `LREAL` | M（6） | `lgf-math`、`lbp-basic-process` | T2 |
| 6 | `FC_DL_PolygonArea` | DL_MathData | FC | `LREAL` | M（5） | `lgf-math` | T2 |
| 7 | `FC_DL_LineIntersection` | DL_MathData | FC | `BOOL` | L（3） | `lgf-math` | T2 |
| 8 | `FC_DL_Crc32Ethernet` | DL_MathData | FC | `DWORD` | M（6） | `oscat-network`、`crc32-iso-hdlc` | **T1** |
| 9 | `FC_DL_LrcChecksum` | DL_MathData | FC | `BYTE` | L（3） | `oscat-network`、`modbus-ascii` | **T1** |
| 10 | `FB_DL_LifoStack` | DL_MathData | FB | — | M（5） | `lgf-datahandling` | T2 |
| 11 | `FB_DL_MedianFilter` | DL_MathData | FB | — | M（6） | `lgf-measurement`、`oscat-basic` | T2 + T1 |
| 12 | `FB_DL_SignalStatistics` | DL_MathData | FB | — | M（7） | `lgf-math`、`oscat-basic` | T2 + T1 |
| 13 | `FC_DL_QuickSortLReal` | DL_MathData | FC | `BOOL` | M（7） | `lgf-datahandling`、`oscat-basic` | T2 + T1 |
| 14 | `FC_DL_HexStringToBytes` | DL_MathData | FC | `INT` | L（4） | `lgf-converter`、`modbus-ascii` | T2 |

### 3.1 标签体系（本轮统一定义，后续沿用）

| 标签族 | 形态 | 含义 | 本轮实例 |
|---|---|---|---|
| `lgf-<组名连写>` | T2 | 西门子 LGF 11 功能组（组名去空格小写） | `lgf-math`、`lgf-datahandling`、`lgf-converter`、`lgf-measurement`、`lgf-comparator`、`lgf-bitlogic` |
| `lbp-basic-process` | T2 | 西门子 LBP 基础过程库（电机/阀/聚合体/插值） | DutyStandbyRotation、MultiPointLinear |
| `isa18-2` | T2 | ISA-18.2 报警与首出方法论（公开规范） | InterlockMatrix |
| `iec60204` / `iso13851` | T2 | 机械安全电气与双手控制装置规范（公开标准） | TwoHandSafety |
| `oscat-basic` / `oscat-network` | T1 | OSCAT Basic / Network（EPL-2.0，可商用） | CRC32、LRC、中值、统计、排序 |
| `modbus-ascii` / `crc32-iso-hdlc` | T3 | 协议与算法目录（仅查漏与向量核对） | LRC、CRC32、HexString |

**覆盖自检**：T2 组 = `iec60204`、`isa18-2`、`lgf-comparator`、`lbp-basic-process`、`lgf-math`、`lgf-datahandling`、`lgf-measurement`、`lgf-converter`、`lgf-bitlogic` → **9 个不同 T2 标签**（其中 LGF 组 6 个）；T1 源组 = `oscat-network`、`oscat-basic` → **2 个**。满足「≥3 个 T2 组 + ≥1 个 T1 组」，实际大幅超出。

---

## 4 故障码分配（延续 `16#0001_xxxx`，本轮新开 `16#0002_xxxx` 族）

### 4.1 复用既有码（不新造同义码）

| ErrorID | 含义 | 本轮适用 |
|---|---|---|
| `16#0000_0000` | 无故障 | 全部 |
| `16#0001_0001` | 参数越界（索引/点数/窗口/长度/时间上限） | 全部 14 项 |
| `16#0001_0002` | 分母 / 量程 / 面积为零或近零 | MultiPointLinear、PolygonArea、LineIntersection |
| `16#0001_0004` | 循环 / 二分 / 栈深保护触发 | MultiPointLinear、QuickSortLReal、MedianFilter、SignalStatistics |
| `16#0001_0005` | 状态机非法状态（`ELSE` 兜底命中） | 4 个 FB 全部 |
| `16#0001_0006` | 输入非法（NaN / Inf） | MultiPointLinear、PolygonArea、LineIntersection、MedianFilter、SignalStatistics、QuickSortLReal |
| `16#0001_0007` | 数值溢出（计数器饱和/栈深溢出） | LifoStack、QuickSortLReal、DutyStandbyRotation |
| `16#0001_0008` | 时间增量非法（0 或越界） | RedundantSwitch、DutyStandbyRotation |
| `16#0001_0009` | 缓冲满 | LifoStack、HexStringToBytes |
| `16#0001_000A` | 缓冲空 | LifoStack |

### 4.2 本轮新增 10 码（`16#0002_xxxx`，全库唯一，禁止各组件自造）

| ErrorID | 含义 | 适用组件 | 锁存性 |
|---|---|---|---|
| `16#0002_0001` | 双手按钮同步窗口超时（第二只手未在窗内按下） | TwoHandSafety | **锁存**（须复位） |
| `16#0002_0002` | 双手释放不同步（循环结束后未在释放窗内全部释放） | TwoHandSafety | **锁存** |
| `16#0002_0003` | 单侧按钮卡死 / 旁路嫌疑（单侧持续按下超时） | TwoHandSafety | **锁存** |
| `16#0002_0004` | 联锁配置非法（无任何启用通道） | InterlockMatrix | **锁存** |
| `16#0002_0005` | 冗余双通道同时失效（无可用源） | RedundantSwitch | **锁存** |
| `16#0002_0006` | 冗余切换抖动（窗口内切换次数超限） | RedundantSwitch | **锁存** |
| `16#0002_0007` | 轮值无可用机组（需求 > 0 而可用 = 0） | DutyStandbyRotation | **瞬时**（可自恢复） |
| `16#0002_0008` | 轮值时间参数冲突（最小运行 + 最小停机 > 轮值周期） | DutyStandbyRotation | **锁存** |
| `16#0002_0009` | 统计样本不足（N < 2，方差无定义） | SignalStatistics | 瞬时 |
| `16#0002_000A` | 十六进制字符串非法（非 hex 字符 / 奇数长度） | HexStringToBytes | 瞬时 |
| `16#0002_000B` | 折线表 X 非严格递增（标定表非法） | MultiPointLinear | 瞬时（每次调用重算） |
| `16#0002_000C` | 多边形退化（点数 < 3 / 共线 / 面积为零） | PolygonArea | 瞬时 |
| `16#0002_000D` | 两直线平行或重合（无唯一交点） | LineIntersection | 瞬时 |

> **锁存纪律（R15）**：标「锁存」的码只能由 `bReset` 上升沿（且解除条件已满足）清除；标「瞬时」的码每拍重算、条件消失即归零。头注释必须写明该码属哪一类，禁止混用。

---

## 5 依赖声明（本轮唯一合法依赖清单）

**本轮为空**：14 个组件**零内部依赖**，全部仅依赖 `Standard.library`（`ABS` / `MIN` / `MAX` / `TON` / `R_TRIG` / `F_TRIG` / `LIMIT`）。

**决策 D-R3-03（零依赖是设计，不是巧合）**：
Level 0 的 40 个组件必须支持「任意子集导出」——OEM 只想要 `FC_DL_Crc32Ethernet` 一个函数时，不应被迫连坐引入 5 个依赖。OSCAT 的「一装一库、接近 POU 上限」正是反面教材（见 `RAW_NOTES_R3.md` 检索 5）。因此本轮的组件宁可各自内联 3~5 行边界检查，也不引入跨组件调用；下一轮 `DL_Algo` 起才允许按需依赖 Level 0。

---

## 6 编码顺序与分批（供 3 个编码 Agent 并行）

| 批次 | 组件 | 项数 | 并行位 | 共享语感 |
|---|---|---|---|---|
| **A · 纯函数·几何与校验** | #7 LineIntersection、#9 LrcChecksum、#14 HexStringToBytes、#6 PolygonArea | 4 | Agent-1 | 「先校验后计算」+ 单一返回出口 |
| **B · 纯函数·查表与编码** | #5 MultiPointLinear、#8 Crc32Ethernet、#13 QuickSortLReal | 3 | Agent-2 | 「循环必有防死锁计数器」+ 显式栈 |
| **C · 数据结构 FB** | #10 LifoStack、#11 MedianFilter、#12 SignalStatistics | 3 | Agent-3 | 「定长数组 + 单指针 + R14 语义参数变更加填」 |
| **D · 安全/可靠性 FB** | #1 TwoHandSafety、#2 InterlockMatrix、#3 RedundantSwitch、#4 DutyStandbyRotation | 4 | Agent-1/2（收尾合流） | 「ENUM+CASE+ELSE + 锁存码 + 单一输出出口」 |

- 顺序：A ∥ B ∥ C 同时开（10 项），完成后 D 拆两路（D1 = #1 #2；D2 = #3 #4）。
- **A/B/C 全部是纯函数或轻 FB，必须先完成并各自跑通自检向量**，再开 D——D 的四个块是本轮语义风险最高的部分，不能与轻组件抢注意力。
- 每批完成即落 `.st` + 手册 + 索引 + 语料（阶段五统一做），本阶段只交规格。

---

## 7 逐组件需求规格（14 项）

> 每节固定结构：**功能 → 接口契约（含内部变量与常量）→ 语义/状态机 → 故障码 → 边界与防错 → 自检向量 → 去重与来源**。
> 接口块内 `:=` 均为默认值建议；枚举可与所属 POU 同文件，头注释注明归属。
> **本阶段禁止写实现体**，算法只以自然语言 + 处理顺序描述。

---

### 7.1 `FB_DL_TwoHandSafety` ｜ DL_Base ｜ 复杂度 M（6）｜ 来源 `iec60204` + `iso13851`

**功能**：双手安全启动按钮同步性校验与防旁路状态机。要求两只手按钮在 **500 ms 同步窗**内先后按下才给出安全输出；循环结束必须**两只手都释放**才允许下一次启动；单侧按钮持续按下（胶带/卡死）在设定时间内即判「旁路嫌疑」并锁存故障。解决压力机、压装机、封口机上「一只手按、另一只手伸进模具」的经典致死场景。

> **合规披露（必须原样写入头注释，不得删改）**：本块是**标准 PLC 上的逻辑结构实现**，不是安全认证功能块。ISO 13851:2019 Type IIIC 要求的安全功能必须由安全继电器或 F-CPU 的安全程序承担；标准 PLC 的普通输出存在短路失效后**静默失效**的风险，**不得作为唯一安全措施**。本块的定位是：① 在 F-CPU 中作为经过安全论证的逻辑骨架；② 在标准 PLC 上作为**非安全**的工艺互锁与诊断辅助。

**接口契约**

```iecst
TYPE E_DL_TwoHandState :
(
    eIdle        := 0,    // 待机：双手均未按下，等待首次按下 / Idle, both released
    eWaitSecond  := 10,   // 已按下单手，等待另一手在同步窗内按下 / One pressed, waiting for the second
    eBothPressed := 20,   // 双手同步按下，安全输出有效 / Both pressed synchronously, output valid
    eWaitRelease := 30,   // 已释放一手，等待另一手在释放窗内释放 / One released, waiting for the other
    eFault       := 99    // 故障锁存，仅 bReset 且条件满足可解除 / Fault latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_TwoHandSafety
VAR_INPUT
    bLeftPressed  : BOOL;                  // 左按钮，TRUE = 按下（调用方已完成常闭取反）/ Left pressed, TRUE = pressed
    bRightPressed : BOOL;                  // 右按钮，TRUE = 按下（调用方已完成常闭取反）/ Right pressed
    bEnable       : BOOL := TRUE;          // 使能，FALSE 时输出立即复位且状态回 eIdle / Enable
    tSyncWindow   : TIME := T#500MS;       // 双手同步窗 [ms]，合法域 T#0MS~500MS / Sync window, max 500 ms
    tReleaseWindow: TIME := T#100MS;       // 双手释放差允许窗 [ms]，合法域 T#0MS~500MS / Release difference window
    tStuckTime    : TIME := T#5S;          // 单侧持续按下判卡死时间 [s] / Single-side stuck detection time
    bReset        : BOOL;                  // 上升沿：故障复位（须双手已释放）/ Rising edge: fault reset, requires both released
END_VAR
VAR_OUTPUT
    bSafeOutput   : BOOL;                  // 安全输出（双手同步按下期间为 TRUE）/ Safe output, TRUE only while both held
    bBothPressed  : BOOL;                  // 双手同时按下（无同步含义）/ Both pressed, no synchronism implied
    bSynced       : BOOL;                  // 本次启动满足同步窗 / This actuation was synchronous
    bArmed        : BOOL;                  // 已武装：自上次全部释放后尚未启动过 / Armed, no cycle since last full release
    bLeftStuck    : BOOL;                  // 左按钮卡死嫌疑 / Left button stuck
    bRightStuck   : BOOL;                  // 右按钮卡死嫌疑 / Right button stuck
    bError        : BOOL;                  // 故障标志（锁存）/ Fault flag, latched
    uErrorId      : UDINT;                 // 故障码，0 = 无故障 / Error code
    uCycleCount   : UDINT;                 // 成功完成的双手循环数（饱和）/ Completed cycles, saturating
    uAbortCount   : UDINT;                 // 同步窗超时 / 释放不同步的累计次数（饱和）/ Aborted attempts, saturating
    eState        : E_DL_TwoHandState;     // 当前状态（供 HMI 诊断）/ Current state
END_VAR
VAR
    fbTrigReset   : R_TRIG;                // 复位上升沿 / Reset rising edge
    fbTonSync     : TON;                   // 同步窗计时（单手按下期间运行）/ Sync-window timer
    fbTonRelease  : TON;                   // 释放窗计时（单手仍按下期间运行）/ Release-window timer
    fbTonStuckL   : TON;                   // 左侧卡死计时 / Left stuck timer
    fbTonStuckR   : TON;                   // 右侧卡死计时 / Right stuck timer
    eStateInt     : E_DL_TwoHandState;     // 主状态机内部当前态 / Internal state
    bSyncOkLatch  : BOOL;                  // 本次启动已通过同步判定的锁存 / Synchronism passed latch
    bArmLatch     : BOOL;                  // 武装标志锁存（上电必须为 FALSE）/ Armed latch, FALSE at power-up
    bFirstScan    : BOOL := TRUE;          // 上电首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_TH_SYNC_MAX    : TIME := T#500MS;   // 同步窗硬上限（标准上限，禁止放宽）/ Hard sync-window limit
    DL_TH_REL_MAX     : TIME := T#500MS;   // 释放窗硬上限 / Hard release-window limit
    DL_TH_STUCK_MIN   : TIME := T#1S;      // 卡死判定时间下限（防误报）/ Stuck-time lower bound
    DL_TH_CNT_MAX     : UDINT := 16#FFFF_FFFE;  // 计数器饱和值 / Counter saturation
END_VAR
```

**语义与状态机**

| 状态 | 含义 | 输出 | 跃迁条件 |
|---|---|---|---|
| `eIdle` | 双手均未按下 | `bSafeOutput := FALSE` | 单手按下 → `eWaitSecond` 并启动同步窗；双手同拍按下见 B2 |
| `eWaitSecond` | 单手按下，等另一手 | `bSafeOutput := FALSE` | 另一手在窗内按下 → `eBothPressed`（`bSynced := TRUE`、`uCycleCount++`）；同步窗到期 → `eFault` + `16#0002_0001`；先按的手先释放 → 回 `eIdle`（不计故障，`uAbortCount++`） |
| `eBothPressed` | 双手同步按下 | `bSafeOutput := TRUE` | 任一手释放 → `eWaitRelease` 并启动释放窗 |
| `eWaitRelease` | 一手已释放 | `bSafeOutput := FALSE` | 另一手在释放窗内释放 → `eIdle`、`bArmLatch := FALSE`（下次需重新同步）；释放窗到期仍有一手按下 → `eFault` + `16#0002_0002` |
| `eFault` | 故障锁存 | `bSafeOutput := FALSE`、`bError := TRUE` | `bReset` 上升沿且双手均已释放 → `eIdle`、清码；双手未释放时复位**无效**（保持锁存） |

**算法要点（每拍处理顺序，编码侧必须按此顺序）**
1. **无条件刷新区**（主体最前部）：`fbTrigReset`、`fbTonSync`、`fbTonRelease`、`fbTonStuckL`、`fbTonStuckR` 五个实例全部无条件调用，`IN` 先由状态推导为 BOOL 再传入（R7）。
2. **上电首扫**：`bArmLatch := FALSE`、`bSafeOutput := FALSE`、`eStateInt := eIdle`、`bFirstScan := FALSE`。
3. **卡死诊断（先于主状态机）**：`eIdle` 且仅单侧按下时，对应 `fbTonStuck` 计时；到期 → `eFault` + `16#0002_0003`、置对应 `bLeftStuck/bRightStuck`。双手同时按下不参与卡死计时（那是正常操作）。
4. **联网锁（arming）**：`eIdle` 且双手均释放 → `bArmLatch := TRUE`。`bArmLatch = FALSE` 时**任何按下都不得进入 `eWaitSecond`**——这是「上电时双手已被按下/短接」不启动的唯一保证。
5. **主状态机** `CASE eStateInt OF ... ELSE → eFault + 16#0001_0005`。
6. **同步判定**：`eWaitSecond` 中第二手到达时，判定依据是 `fbTonSync.Q = FALSE`（即未到期），而不是「距离上次按下的毫秒数」——用定时器 Q 判定可避免平台 `TIME` 减法差异。
7. **输出单一出口**（主体末尾统一赋值一次）：`bSafeOutput := (eStateInt = eBothPressed) AND bEnable`；`bBothPressed`、`bSynced`、`bArmed` 同处赋值。
8. **故障码口径（R15）**：锁存期保留进入故障时的码，仅复位路径清零；`bEnable = FALSE` 回 `eIdle` 时清码但不计故障。

**故障码**

| 码 | 含义 | 类型 | 现场处置 |
|---|---|---|---|
| `16#0002_0001` | 同步窗超时（单手先按超过 500 ms 才按另一手） | 锁存 | 检查双手操作习惯 / 按钮行程；确认非单手持物操作 |
| `16#0002_0002` | 释放不同步（一手释放后另一手仍按下超窗） | 锁存 | 检查按钮回弹、弹簧疲劳、按钮被异物压住 |
| `16#0002_0003` | 单侧卡死 / 旁路嫌疑 | 锁存 | **停机检查按钮机械卡滞与人为短接**，不得仅复位放行 |
| `16#0001_0001` | 时间参数越界（已钳位） | 瞬时 | 修正 `tSyncWindow` / `tReleaseWindow` / `tStuckTime` |
| `16#0001_0005` | 非法状态 | 锁存 | 程序异常，报研发 |

**边界与防错**

| # | 边界 | 要求 |
|---|---|---|
| B1 | 上电时双手已按下 | **绝不允许输出**：`bArmLatch` 上电为 FALSE，必须经历一次「双手全释放」才武装。手册列为第一测试项 |
| B2 | 双手同拍按下 | 同一扫描周期内两侧均为 TRUE：直接判定同步成功（`bSynced := TRUE`），但**仍需 `bArmLatch = TRUE`** |
| B3 | 同步窗参数越界 | `tSyncWindow > 500 ms` → **钳到 500 ms** + `16#0001_0001`（放宽窗口等于放宽安全，禁止向上放行）；`tSyncWindow = T#0MS` 合法，等价「同拍才算」 |
| B4 | 释放窗参数越界 | 同上，钳到 500 ms；`tReleaseWindow = T#0MS` 表示「必须同拍释放」，现场会频繁报 `0002_0002`，手册须警示 |
| B5 | 卡死时间过短 | `tStuckTime < 1 s` → 钳到 1 s + `16#0001_0001`（防止正常慢速点动被误判） |
| B6 | 故障态复位 | 双手未全释放时 `bReset` **不得**清锁存（否则「按住一手 + 复位」即可旁路，等于白做） |
| B7 | 计数器饱和 | `uCycleCount` / `uAbortCount` 达 `DL_TH_CNT_MAX` 后停止累加 + `16#0001_0007`（一次），不清零 |
| B8 | 单侧按钮信号抖动 | 本块**不做**输入防抖（防抖会引入额外延时，蚕食 500 ms 同步窗）；头注释明确「调用方须前置 `FB_DL_SignalDebounce`，防抖时间计入同步窗」 |
| B9 | 输出单一出口 | `bSafeOutput` 只允许在主体末尾一处赋值，分支内只改状态（P-05 范式） |

**自检向量（R12/R13，编码侧必须逐扫描复算）**

| # | 输入序列 | 期望 |
|---|---|---|
| V1 | 上电即 `L=1, R=1` 持续 10 拍 | `bSafeOutput` 全程 FALSE；状态 `eIdle`；无故障 |
| V2 | 上电 → 双释放 1 拍 → 双按下 1 拍 | V2 后 `bSafeOutput = TRUE`，`bSynced = TRUE`，`uCycleCount = 1` |
| V3 | 武装后 `L=1` @t0，`R=1` @t0+400 ms | `bSafeOutput = TRUE`（窗内） |
| V4 | 武装后 `L=1` @t0，`R=1` @t0+600 ms | `eFault` + `16#0002_0001`，`bSafeOutput = FALSE`，`uAbortCount` 不变（故障不计 abort） |
| V5 | 双手按下后仅释放 L，保持 R 超过 100 ms | `16#0002_0002`，`bSafeOutput = FALSE` |
| V6 | `eIdle` 下仅 L 持续按下 5 s（`tStuckTime = 5 s`） | `16#0002_0003`，`bLeftStuck = TRUE` |
| V7 | 故障态 `bReset` 一拍但 R 仍按下 | 锁存保持，`bError` 仍 TRUE，`uErrorId` 仍为原码 |

**来源与去重**
- 来源标签：`iec60204`、`iso13851`（T2 标准线，公开规范）。参数域取自 ISO 13851:2019 Type IIIC：同步窗 ≤ 500 ms、释放差 ≤ 100 ms、释放后重启、上电禁止启动、单侧卡死须可检出。**未复制任何实现代码**，clean-room 编写。
- 去重：见 §1.4 第 1 行。与 `FB_DL_SignalDebounce` 是**串联关系**而非替代关系（防抖在前，同步判定在后）。
- AI 语料维度：`双手安全 / 500ms 同步窗 / 防旁路 / 上电锁 / ST 状态机`。

---

### 7.2 `FB_DL_InterlockMatrix` ｜ DL_Base ｜ 复杂度 M（7）｜ 来源 `isa18-2` + `lgf-bitlogic`

**功能**：16 路安全联锁条件的汇总与**首因追踪**。输出**唯一一个运行许可位** `bPermitToRun`（全部停机级条件满足才 TRUE），并在条件失效的瞬间锁存「第一个失效的通道号 + 位图 + 全局序号」；复位后若条件仍未恢复，**复位挂起而不清锁存**。解决「停机后十个联锁同时报、维修工不知道先查哪个」与「复位键一按就放行、根因被掩盖」两类现场顽疾。

**接口契约**

```iecst
TYPE E_DL_InterlockState :
(
    eDisabled := 0,    // 未使能：许可强制 FALSE / Disabled, permit forced FALSE
    eBlocked  := 10,   // 条件不满足：许可 FALSE，等待恢复 / Blocked, waiting for conditions
    ePermitted:= 20,   // 全部停机级条件满足，许可 TRUE / Permitted
    eLatched  := 30,   // 首因已锁存，等待复位 / First-out latched, waiting for reset
    eFault    := 99    // 配置/状态非法 / Configuration or state invalid
);
END_TYPE

FUNCTION_BLOCK FB_DL_InterlockMatrix
VAR_INPUT
    abConditionOk : ARRAY[0..15] OF BOOL;  // 16 路原始条件，TRUE = 满足 / Raw condition, TRUE = OK
    auInvertMask  : WORD := 16#0000;       // 取反掩码，bit=1 表示该路原始信号需取反 / Invert mask, bit=1 inverts
    auTripMask    : WORD := 16#FFFF;       // 停机级掩码，bit=1 = 停机级，bit=0 = 提示级 / Trip-class mask
    bEnable       : BOOL := TRUE;          // 使能，FALSE 时许可 FALSE 且不清锁存 / Enable
    bReset        : BOOL;                  // 上升沿：清除首因锁存（条件仍不满足时挂起）/ Rising edge: reset first-out
END_VAR
VAR_OUTPUT
    bPermitToRun     : BOOL;               // 运行许可（唯一放行信号）/ Run permit, the only release signal
    bFirstOutValid   : BOOL;               // 首因有效 / First-out valid
    nFirstOutIndex   : INT;                // 首因通道号 0..15，-1 = 无 / First-out channel, -1 = none
    uFirstOutMask    : WORD;               // 首因位图（可多 bit，见 B4）/ First-out bitmap
    uFirstOutSeq     : UDINT;              // 首因发生的全局序号（单调递增）/ First-out global sequence
    bFirstOutSimult  : BOOL;               // 首因为同拍多点失效（扫描粒度内不可排序）/ Simultaneous first-out
    bLatchedAtStartup: BOOL;               // 首因发生在上电首扫（冷启动即不满足）/ Latched at power-up
    uTripActiveMask  : WORD;               // 当前失效的停机级通道位图 / Currently failed trip channels
    uWarnActiveMask  : WORD;               // 当前失效的提示级通道位图 / Currently failed warning channels
    bResetPending    : BOOL;               // 复位挂起：已按复位但条件未恢复，锁存保留 / Reset pending
    bError           : BOOL;               // 故障标志（配置类锁存）/ Fault flag
    uErrorId         : UDINT;              // 故障码 / Error code
    eState           : E_DL_InterlockState;// 主状态机 / Main state
END_VAR
VAR
    fbTrigReset    : R_TRIG;               // 复位上升沿 / Reset edge
    auEffOk        : ARRAY[0..15] OF BOOL; // 取反后的有效条件 / Effective conditions after invert
    uTripNow       : WORD;                 // 本拍失效的停机级位图 / Trip mask this scan
    uWarnNow       : WORD;                 // 本拍失效的提示级位图 / Warn mask this scan
    uLatchMask     : WORD;                 // 锁存的首因位图 / Latched first-out mask
    nLatchIdx      : INT;                  // 锁存的首因通道号 / Latched index
    uSeqCounter    : UDINT;                // 全局序号计数器 / Global sequence counter
    eStateInt      : E_DL_InterlockState;  // 内部状态 / Internal state
    bStartupScan   : BOOL := TRUE;         // 上电首扫标志 / First-scan flag
    nIdx           : INT;                  // 通道遍历索引 / Channel loop index
    nNewLowest     : INT;                  // 本拍首个失效通道（最低索引）/ Newly failed lowest index
    bMultiFail     : BOOL;                 // 本拍多点失效标志 / Multi-fail flag this scan
END_VAR
VAR CONSTANT
    DL_ILK_CHANNELS : INT := 16;           // 通道数，必须等于数组维度 / Channel count
    DL_ILK_IDX_NONE : INT := -1;           // 无效通道号哨兵 / No-channel sentinel
    DL_ILK_BIT15    : WORD := 16#8000;     // 最高位掩码 / MSB mask
END_VAR
```

**语义与状态机**

| 状态 | 含义 | `bPermitToRun` | 跃迁 |
|---|---|---|---|
| `eDisabled` | `bEnable = FALSE` | FALSE | `bEnable = TRUE` → `eBlocked` |
| `eBlocked` | 有停机级条件不满足，且未锁存 | FALSE | 全恢复 → `ePermitted`；出现失效 → `eLatched` + 锁存 |
| `ePermitted` | 全部条件满足 | TRUE | 任一停机级失效 → `eLatched` + 锁存首因 |
| `eLatched` | 首因已锁存 | FALSE | `bReset` 且 `uTripNow = 0` → `eBlocked`、清锁存；条件未恢复则复位挂起 |
| `eFault` | 配置非法（无任何启用通道） | FALSE | 仅 `bEnable` 重新配置后可退出（需重新使能） |

**算法要点（每拍顺序）**
1. 无条件刷新 `fbTrigReset`。
2. 上电首扫：`nLatchIdx := -1`、`uLatchMask := 0`、`bLatchedAtStartup := FALSE`、`eStateInt := eBlocked`。
3. 逐通道求有效值：`有效 = 原始 XOR 取反位`（16 次位操作，用 `SHR` + `AND 16#0001` 取位，禁止位访问方言）。
4. 逐通道分类汇总：停机级失效 → 置 `uTripNow` 对应位；提示级失效 → 置 `uWarnNow`。
5. **首因判据**：`uTripNow` 由 0 变非 0 的那一拍——扫描 `uTripNow` 求最低置位索引 `nNewLowest` 与置位总数；总数 > 1 → `bFirstOutSimult`；`uSeqCounter++`；若 `nLatchIdx = -1`（尚无锁存）则写入 `nLatchIdx`、`uLatchMask := uTripNow`、`uFirstOutSeq := uSeqCounter`。**锁存后不再被新故障覆盖**（首因就是首因）。
6. 提示级**不锁存**（避免一个「料仓低」提示把停机联锁的首因挤掉）。
7. 复位：仅 `eLatched` 且 `uTripNow = 0` 时清 `nLatchIdx / uLatchMask / bFirstOutValid`；`uTripNow <> 0` 时置 `bResetPending := TRUE` 且**保留锁存**。
8. 配置校验：`auTripMask.OR(取反后的提示级集合) = 0`（即 16 路全部既非停机级也无提示级）→ `16#0002_0004`、`eFault`、许可 FALSE。
9. 主状态机 `CASE` + `ELSE → eFault + 16#0001_0005`。
10. 输出单一出口：`bPermitToRun := (eStateInt = ePermitted) AND bEnable`。

**故障码**

| 码 | 含义 | 类型 |
|---|---|---|
| `16#0002_0004` | 配置非法：`auTripMask` 与 `auInvertMask` 组合导致无任何有效通道 | 锁存 |
| `16#0001_0005` | 非法状态（`ELSE` 兜底） | 锁存 |

**边界与防错**

| # | 边界 | 要求 |
|---|---|---|
| B1 | 无任何启用通道 | `16#0002_0004` + 许可 FALSE。**绝不因「没配置」而默认放行**（fail-safe 第一原则） |
| B2 | 上电即有多路不满足 | 首扫即锁存（不等沿），`bLatchedAtStartup := TRUE`，`uFirstOutSeq := 1`。手册写明：冷启动时的首因可能是「本来就断着」的条件，不代表本次停机原因 |
| B3 | 同拍多路失效 | 扫描粒度内无法排序 → 取**最低索引**为首因通道，`bFirstOutSimult := TRUE` 并锁存**整张位图** `uFirstOutMask`。禁止编造「谁先谁后」 |
| B4 | 首因位图多 bit | 同 B3，位图可能有多 bit；`nFirstOutIndex` 只是「最低索引」的代表值，HMI 必须显示位图 |
| B5 | 复位时条件未恢复 | 复位挂起，锁存保留。这一条是防「按复位→看码消失→误判已修好」的关键 |
| B6 | 提示级与停机级混合 | 提示级只进 `uWarnActiveMask`，不参与首因、不阻断许可 |
| B7 | 取反掩码语义 | 头注释给真值表：`raw=1, invert=1 → 有效 0（不满足）`。现场常闭接线的急停必须置 invert 位 |
| B8 | 位操作可移植 | 一律 `SHR` + `AND` 取位、`SHL` + `OR` 置位（R1 已入库 `FC_DL_BitGet/Set` 的同一写法），禁止 `%X` 位访问 |
| B9 | 通道数对齐 | 16 路与 `FC_DL_PackBitsToWord` / `FB_DL_AlarmManager` 的 16 路族一致；**刻意偏离 LBP_Intlk8 的 8 路**，理由：位图输出需与既有 16 位报警字同宽，否则现场要做两次拼接（偏离留档 R11） |

**自检向量**

| # | 场景 | 期望 |
|---|---|---|
| V1 | 上电，CH3 原始 0（trip，未取反） | `bPermitToRun = FALSE`、`nFirstOutIndex = 3`、`bLatchedAtStartup = TRUE`、`uFirstOutSeq = 1` |
| V2 | V1 后 CH3 恢复，`bReset` 一拍 | 锁存清、`eBlocked` → `ePermitted`、许可 TRUE |
| V3 | 运行中 CH5 与 CH7 同拍失效 | `nFirstOutIndex = 5`、`bFirstOutSimult = TRUE`、`uFirstOutMask = 16#00A0` |
| V4 | V3 后 `bReset` 一拍但 CH7 仍未恢复 | 锁存保持（idx=5）、`bResetPending = TRUE`、许可 FALSE |
| V5 | 全部通道 `auTripMask = 0` | `16#0002_0004`、许可 FALSE、`eFault` |
| V6 | CH0 为提示级（tripMask bit0=0）失效 | 许可保持 TRUE、`uWarnActiveMask = 16#0001`、无首因 |

**来源与去重**
- 来源标签：`isa18-2`（首出/首因方法论）、`lgf-bitlogic`（位图与掩码的组织方式，仅借鉴分类）。clean-room。
- 去重：见 §1.4 第 2 行。与 `FB_DL_AlarmManager` 的分工写进两者手册交叉引用：**AlarmManager 管「报什么警、先看哪条」；InterlockMatrix 管「能不能开机」**。

---

### 7.3 `FB_DL_RedundantSwitch` ｜ DL_Base ｜ 复杂度 H（8）｜ 来源 `lgf-comparator`

**功能**：双通道（双传感器或双执行器反馈）冗余选择器。持续比较 A/B 偏差，超限延时确认后报警；**双通道互相矛盾时不猜谁对**（按显式策略保持最后值 / 跟随指定通道 / 直接故障）；单通道失效时按停留时间与速率限制**无扰切换**到另一通道；切换频繁则抖振锁定。解决「双传感器冗余装了但程序里只接了一个」「切过去瞬间阀门跳变」两个现场通病。

**接口契约**

```iecst
TYPE E_DL_RedundancyPriority :
(
    eAuto   := 0,    // 自动：首次选 A，之后跟随当前 / Auto, A first then follow
    eForceA := 1,    // 强制 A（A 失效才允许越权）/ Force A unless A invalid
    eForceB := 2     // 强制 B / Force B
);
END_TYPE

TYPE E_DL_DeviationPolicy :
(
    eHoldLast := 0,  // 偏差超限时保持最后有效值（默认，不猜）/ Hold last valid value
    eUseA     := 1,  // 偏差超限时视为 B 漂移，跟随 A / Treat B as drifting
    eUseB     := 2,  // 视为 A 漂移，跟随 B / Treat A as drifting
    eFault    := 3   // 偏差超限即判故障（保守）/ Fail on deviation
);
END_TYPE

TYPE E_DL_ActiveChannel :
(
    eNone := 0,      // 无可用通道 / No usable channel
    eA    := 1,      // 通道 A 生效 / Channel A active
    eB    := 2       // 通道 B 生效 / Channel B active
);
END_TYPE

TYPE E_DL_RedundState :
(
    eInit    := 0,   // 初始化（首扫）/ Initialisation
    eNormal  := 10,  // 双通道一致，正常运行 / Both channels agree
    eSuspect := 20,  // 偏差超限，等待判定 / Deviation, awaiting decision
    eRamping := 30,  // 切换过渡中（限速逼近）/ Bumpless transition in progress
    eFault   := 99   // 无可用通道 / No usable channel
);
END_TYPE

FUNCTION_BLOCK FB_DL_RedundantSwitch
VAR_INPUT
    fChannelA      : REAL;                    // 通道 A 测量值 [EU] / Channel A value
    fChannelB      : REAL;                    // 通道 B 测量值 [EU] / Channel B value
    bChannelAValid : BOOL := TRUE;            // A 通道健康（无断线/超量程）/ A healthy
    bChannelBValid : BOOL := TRUE;            // B 通道健康 / B healthy
    fDeviationLimit: REAL := 1.0;             // 偏差限 [EU]，须 > 0 / Deviation limit, must be > 0
    tDeviationDelay: TIME := T#2S;            // 偏差确认延时 [s]，0 = 立即 / Deviation confirmation delay
    ePreferred     : E_DL_RedundancyPriority := eAuto;    // 首选通道策略 / Preferred channel
    eDevPolicy     : E_DL_DeviationPolicy := eHoldLast;   // 偏差处置策略 / Deviation policy
    tSwitchDwell   : TIME := T#500MS;         // 切换后抑制再次切换的停留时间 [ms] / Switch dwell
    fMaxSlewRate   : REAL := 0.0;             // 无扰过渡最大变化率 [EU/s]，0 = 直接切换 / Max slew rate
    uDeltaTimeMs   : UDINT;                   // 调用方注入的扫描间隔 [ms] / Injected scan delta
    fSafeValue     : REAL := 0.0;             // 双通道失效时的安全值 [EU] / Safe value
    bReset         : BOOL;                    // 上升沿：复位锁存故障 / Reset latched faults
END_VAR
VAR_OUTPUT
    fSelected      : REAL;                    // 选择后的输出值 [EU] / Selected output
    eActive        : E_DL_ActiveChannel;      // 当前生效通道 / Active channel
    bOutputValid   : BOOL;                    // 输出有效（非安全值替代）/ Output valid
    fDeviation     : REAL;                    // 当前偏差 |A-B| [EU] / Current deviation
    bDeviationAlarm: BOOL;                    // 偏差报警（已延时确认）/ Deviation alarm
    bRamping       : BOOL;                    // 过渡进行中 / Ramping
    uSwitchCount   : UDINT;                   // 累计切换次数（饱和）/ Switchover count
    bError         : BOOL;                    // 故障标志 / Fault flag
    uErrorId       : UDINT;                   // 故障码 / Error code
    eState         : E_DL_RedundState;        // 主状态机 / Main state
END_VAR
VAR
    fbTrigReset    : R_TRIG;                  // 复位沿 / Reset edge
    fbTonDev       : TON;                     // 偏差确认定时器 / Deviation confirm timer
    fbTonDwell     : TON;                     // 切换停留定时器 / Switch dwell timer
    fbTonChatter   : TON;                     // 抖振统计窗口定时器 / Chatter window timer
    eStateInt      : E_DL_RedundState;        // 内部状态 / Internal state
    eTarget        : E_DL_ActiveChannel;      // 过渡目标通道 / Ramp target
    fLastValid     : REAL;                    // 最后有效值 [EU] / Last valid value
    fTarget        : REAL;                    // 过渡目标值 [EU] / Ramp target value
    nChatterCnt    : INT;                     // 窗口内切换计数 / Switches in window
    bFirstScan     : BOOL := TRUE;            // 首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_RS_DEV_MIN     : REAL := 1.0E-6;       // 偏差限下限 [EU] / Minimum deviation limit
    DL_RS_CHATTER_MAX : INT  := 5;            // 窗口内允许的最大切换次数 / Max switches per window
    DL_RS_DT_MAX      : UDINT := 60000;       // 时间增量上限 [ms] / Delta clamp
END_VAR
```

**语义与状态机**

| 状态 | 进入条件 | 输出 | 退出 |
|---|---|---|---|
| `eInit` | 首扫 | `fSelected` = 首个有效通道值；双无效 → `eFault` | 有有效通道 → `eNormal` |
| `eNormal` | 双通道有效且偏差 ≤ 限 | `fSelected` 跟随生效通道 | 偏差超限且延时到 → `eSuspect`；单通道失效 → `eRamping`；双失效 → `eFault` |
| `eSuspect` | 偏差超限 | 按 `eDevPolicy`：`eHoldLast` 保持 `fLastValid`；`eUseA/eUseB` 跟随指定通道；`eFault` → `eFault` | 疑似失效通道变 `Valid = FALSE` → `eRamping` 切到健康通道；偏差回落 → `eNormal` |
| `eRamping` | 切换目标已定 | `fSelected` 以 `fMaxSlewRate × Δt` 逼近目标 | `|fSelected - fTarget| < eps` → `eNormal`；目标失效 → `eSuspect`/`eFault` |
| `eFault` | 双通道失效 | `fSelected := fSafeValue`、`bOutputValid := FALSE` | `bReset` 且至少一通道恢复 → `eInit` |

**算法要点（每拍顺序）**
1. 无条件刷新 `fbTrigReset / fbTonDev / fbTonDwell / fbTonChatter`（R7）。
2. 时间增量校验：`uDeltaTimeMs = 0` 或 `> 60000` → 钳位到 1 / 60000 + `16#0001_0008`（过渡会停走一拍，但不发散）。
3. 参数校验：`fDeviationLimit <= DL_RS_DEV_MIN` → 置 `DL_RS_DEV_MIN` + `16#0001_0001`（不能用 0，否则任何微小偏差都报警）。
4. 偏差计算：双有效时 `fDeviation := ABS(fChannelA - fChannelB)`；单有效时 `fDeviation := 0.0`（无比较对象，不得沿用旧值）。
5. 偏差计时：`fbTonDev(IN := 双有效 AND fDeviation > fDeviationLimit, PT := tDeviationDelay)`。
6. 单通道失效检测：`bChannelXValid` 下降 → 若另一通道有效则定 `eTarget` 并进入 `eRamping`（受 `fbTonDwell` 抑制，防止反复切）。
7. 过渡：`fSelected` 每拍向 `fTarget` 移动 `fMaxSlewRate × uDeltaTimeMs / 1000.0`，到界即吸附（`fMaxSlewRate = 0` 时直接赋值，等价「不做无扰」——手册必须写明这一点）。
8. 抖振统计：每次实际切换 `nChatterCnt++`；`fbTonChatter` 到期清零计数；`nChatterCnt > 5` → `16#0002_0006` 锁存 + `eFault`（判为设定错误或信号在临界点抖动）。
9. 主状态机 `CASE` + `ELSE → eFault + 16#0001_0005`。
10. 输出单一出口：`fSelected / eActive / bOutputValid / bRamping / iErrorId` 末尾统一赋值。

**故障码**

| 码 | 含义 | 类型 |
|---|---|---|
| `16#0002_0005` | 双通道同时失效，无可用源 | 锁存 |
| `16#0002_0006` | 切换抖振（窗口内 > 5 次） | 锁存 |
| `16#0001_0001` | 偏差限越界（已钳位） | 瞬时 |
| `16#0001_0008` | 时间增量非法（已钳位） | 瞬时 |
| `16#0001_0005` | 非法状态 | 锁存 |

**边界与防错**

| # | 边界 | 要求 |
|---|---|---|
| B1 | 双通道矛盾 | **默认不猜**（`eHoldLast`）。这是本组件最重要的语义：两个传感器打架时，程序没有资格替工艺判断谁对。想自动跟随便必须显式改 `eDevPolicy`，且头注释留档 |
| B2 | 单通道失效瞬间 | 直接切（不等待 `tDeviationDelay`）——通道已宣告无效，偏差比较已无意义 |
| B3 | 无扰过渡与扫描周期的耦合 | 速率是 `EU/s`，必须乘 `uDeltaTimeMs/1000`；**禁止**写成「每拍固定增量」（扫描周期一变，过渡时间就变） |
| B4 | `fMaxSlewRate = 0` | 定义为「直接切换」，不是「不切换」。头注释必须写清，否则运维会误以为切换失效 |
| B5 | 停留时间抑制 | 切换后 `tSwitchDwell` 内不再切（即使偏差超限），防止在临界点来回跳；停留期内若目标通道失效则**允许**越权切换（安全优先于稳定） |
| B6 | 双失效 | 输出安全值 + `bOutputValid := FALSE`；**不得**输出「最后有效值」——最后值在双通道失效时同样可疑 |
| B7 | 偏差限为 0 / 负 | 钳到 `1E-6` + 告警；负值取绝对值后再钳（负偏差限在现场是「填错符号」而非「反向逻辑」） |
| B8 | 通道值 NaN | 平台不支持 NaN 检测时不强行判断；头注释声明「NaN 会污染 `fSelected`，调用方须前置量程校验」。支持检测时置 `16#0001_0006` 并按无效处理 |

**自检向量**

| # | 场景 | 期望 |
|---|---|---|
| V1 | A=10.0，B=10.2，限 1.0，`eAuto` | `eNormal`、`eActive = eA`、`fSelected = 10.0`、`fDeviation ≈ 0.2` |
| V2 | A 掉 `Valid`（B 有效），`tSwitchDwell = 0` | `eRamping` → 稳定后 `eActive = eB`、`uSwitchCount = 1`、`bRamping` 先 TRUE 后 FALSE |
| V3 | A=10.0，B=20.0，限 1.0，延时 2 s，`eHoldLast` | 2 s 后 `bDeviationAlarm = TRUE`、`eSuspect`、`fSelected` 保持 10.0 |
| V4 | V3 后 B 掉 `Valid` | 切到 A，`eNormal`，报警保持（偏差已无对象，但历史已确认） |
| V5 | 双通道 `Valid = FALSE` | `16#0002_0005`、`fSelected = fSafeValue`、`bOutputValid = FALSE`、`eFault` |
| V6 | 400 ms 内交替切换 6 次 | `16#0002_0006`、`eFault` |
| V7 | `fMaxSlewRate = 100.0`，A=0 切到 B=50，`Δt = 100 ms` | 每拍 +10.0，5 拍后到位（`bRamping` 期间 TRUE） |

**来源与去重**
- 来源标签：`lgf-comparator`（公差窗口/区间判断的分类与参数域）、`redundancy`（工艺冗余惯例）。clean-room。
- 去重：见 §1.4 第 3 行。与 `FC_DL_Hysteresis` 的关系：迟滞解决「单值在阈值附近抖」，本块解决「两个值谁可信」——后者内部**不复用**前者（跨组件依赖为零，D-R3-03）。

---

### 7.4 `FB_DL_DutyStandbyRotation` ｜ DL_Base ｜ 复杂度 H（9）｜ 来源 `lbp-basic-process`

**功能**：8 台泵/风机/压缩机的**主备轮值与均衡调度**。按累计运行时间排序，把「需求台数」分给运行时间最短且满足启动条件的机组；按周期把领机降为备机、备机升为领机；故障机立即跳过；每台机受**最小运行时长**与**最小停机时长**双重保护，避免刚启就停；任何时刻不得把在运行的机组全部停掉。解决多泵系统「永远只跑 1 号泵、2 号泵锈死」和「轮值切得太勤、接触器打烂」两类对立问题。

**接口契约**

```iecst
TYPE E_DL_RotationState :
(
    eIdle          := 0,    // 未使能，命令全部撤销 / Disabled, all commands dropped
    eRunning       := 10,   // 正常调度 / Normal scheduling
    eRotatePending := 20,   // 轮值挂起：受最小运行/停机时长阻挡，待条件满足 / Rotation pending
    eFault         := 99    // 参数冲突等锁存故障 / Latched configuration fault
);
END_TYPE

FUNCTION_BLOCK FB_DL_DutyStandbyRotation
VAR_INPUT
    abUnitReady    : ARRAY[0..7] OF BOOL;   // 机组就绪（无故障、无就地、无禁止）/ Unit ready
    abUnitRunning  : ARRAY[0..7] OF BOOL;   // 运行反馈（接触器辅助/流量开关）/ Running feedback
    abUnitFault    : ARRAY[0..7] OF BOOL;   // 机组故障（跳过并允许立即停机）/ Unit fault, skip and stop at once
    nDemand        : INT := 0;              // 需求运行台数 0..8 / Required unit count
    bEnable        : BOOL := TRUE;          // 使能 / Enable
    uDeltaTimeMs   : UDINT;                 // 调用方注入的扫描间隔 [ms] / Injected scan delta
    tMinRunTime    : TIME := T#10M;         // 最小连续运行时长 [min] / Minimum run time
    tMinStopTime   : TIME := T#5M;          // 最小停机时长 [min] / Minimum stop time
    tRotateInterval: TIME := T#24H;         // 轮值周期 [h] / Rotation interval
    bForceRotate   : BOOL;                  // 上升沿：立即请求一次轮值（仍受最小时长约束）/ Rising edge: force one rotation
    bReset         : BOOL;                  // 上升沿：复位参数冲突故障并清零运行时间 / Rising edge: reset fault and clear runtimes
END_VAR
VAR_OUTPUT
    abStartCmd      : ARRAY[0..7] OF BOOL;  // 启动命令（cmd 语义）/ Start command per unit
    anRank          : ARRAY[0..7] OF INT;   // 本轮优先顺序，0 = 最高 / Priority rank, 0 = highest
    nLeadUnit       : INT;                  // 领机号 0..7，-1 = 无 / Lead unit, -1 = none
    afRuntimeHours  : ARRAY[0..7] OF LREAL; // 累计运行小时 [h] / Accumulated runtime in hours
    abBlockedByMinRun : ARRAY[0..7] OF BOOL;// 因最小运行时长被阻止停机 / Stop blocked by min run
    abBlockedByMinStop: ARRAY[0..7] OF BOOL;// 因最小停机时长被阻止启动 / Start blocked by min stop
    auStartCount    : ARRAY[0..7] OF UDINT; // 各机启动次数（饱和）/ Start count per unit
    bRotatePending  : BOOL;                 // 轮值挂起中 / Rotation pending
    bNoAvailableUnit: BOOL;                 // 无可用机组（瞬时诊断）/ No available unit
    uRotateCount    : UDINT;                // 完成的轮值次数 / Completed rotations
    bError          : BOOL;                 // 故障标志（参数冲突锁存）/ Fault flag
    uErrorId        : UDINT;                // 故障码 / Error code
    eState          : E_DL_RotationState;   // 主状态机 / Main state
END_VAR
VAR
    fbTrigReset     : R_TRIG;               // 复位沿 / Reset edge
    fbTrigForce     : R_TRIG;               // 强制轮值沿 / Force-rotate edge
    fbTonRotate     : TON;                  // 轮值周期定时器 / Rotation interval timer
    aeStateInt      : E_DL_RotationState;   // 内部状态 / Internal state
    afRunSec        : ARRAY[0..7] OF LREAL; // 运行秒累加 [s] / Runtime seconds accumulator
    afStopSec       : ARRAY[0..7] OF LREAL; // 停机秒累加 [s] / Stop seconds accumulator
    anOrder         : ARRAY[0..7] OF INT;   // 排序后的机组序列 / Sorted unit sequence
    nDesired        : INT;                  // 本拍应运行台数（已按可用数钳位）/ Desired count, clamped
    nIdx            : INT;                  // 通用索引 / Generic index
    nInner          : INT;                  // 内层索引 / Inner index
    nTmp            : INT;                  // 交换临时量 / Swap temp
    bRotateReq      : BOOL;                 // 本拍请求轮值 / Rotation requested this scan
    bAnyStart       : BOOL;                 // 本拍是否有启动命令 / Any start commanded
    nRunningCnt     : INT;                  // 当前运行台数 / Running count
    bFirstScan      : BOOL := TRUE;         // 首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_DS_UNITS    : INT   := 8;            // 机组数 / Unit count
    DL_DS_IDX_NONE : INT   := -1;           // 无效索引 / Invalid index
    DL_DS_HOUR_MAX : LREAL := 1.0E9;        // 运行小时饱和上限 [h] / Runtime saturation
    DL_DS_MS_PER_H : LREAL := 3.6E6;        // 毫秒→小时换算常数 / ms per hour
    DL_DS_DT_MAX   : UDINT := 60000;        // 时间增量上限 [ms] / Delta clamp
END_VAR
```

**语义与状态机**

| 状态 | 含义 | 行为 |
|---|---|---|
| `eIdle` | `bEnable = FALSE` | 全部 `abStartCmd := FALSE`；定时器不断输入（冻结）；运行时间**继续按反馈累加**（停机也要记账） |
| `eRunning` | 正常调度 | 每拍：累加时间 → 排序 → 定需求集 → 先启后停 → 刷新命令 |
| `eRotatePending` | 已请求轮值但被最小时长挡住 | 保持当前运行组合不变，`bRotatePending := TRUE`，每拍重试；条件满足后完成轮值 → `eRunning` |
| `eFault` | 参数冲突（最小运行 + 最小停机 > 轮值周期） | 轮值禁用，但**启停调度仍工作**（不能因为轮值配错就让泵不转）；`bError := TRUE` |

**算法要点（每拍顺序，顺序本身即安全逻辑）**
1. 无条件刷新 `fbTrigReset / fbTrigForce / fbTonRotate`（R7）。
2. 时间记账：`uDeltaTimeMs` 钳位（0 或 > 60000 → `16#0001_0008`）；对每台机按 `abUnitRunning` 分别累加 `afRunSec` 与 `afStopSec`；`afRuntimeHours := afRunSec / 3600`，超 `DL_DS_HOUR_MAX` 饱和。
3. 参数校验：`nDemand` 越界（<0 或 >8）→ 钳位 + `16#0001_0001`；`tMinRunTime + tMinStopTime > tRotateInterval` → `16#0002_0008` **锁存** + `eFault`（轮值禁用）。
4. 排序：候选 = `Ready AND NOT Fault`；按 `(运行小时升序, 索引升序)` 做**选择排序**（8 元，O(64)，带防死锁计数器）。索引升序是**确定性 tie-break**，禁止依赖排序稳定性。
5. 需求钳位：`nDesired := MIN(nDemand, 可用机组数)`；`nDemand = 0` → 全部停机（但仍受最小运行时长约束，见 B3）。
6. 轮值触发：`fbTonRotate.Q` 或 `fbTrigForce.Q` 且可用 ≥ 2 且 `nDemand ≥ 1` → `bRotateReq := TRUE`。
7. 轮值执行（**仅当所有转换条件满足才移位**）：把当前领机移到候选序列末尾，其余前移一位 → 重算目标集。若不满足最小时长 → 进 `eRotatePending`，**不改变任何命令**。
8. **先启后停**：先对目标集中未运行的机组置启动命令（受 `tMinStopTime` 与 `Ready` 约束）；**仅当在运行台数 ≥ nDesired 时**才允许发停机命令（受 `tMinRunTime` 约束）。此顺序保证任何时刻不会「先停下来再启动」造成压力/流量中断。
9. 故障跳过：`abUnitFault` 为 TRUE 的机组——若在运行，**立即**发停止（**越权跳过最小运行时长**，安全优先）；若未运行，不参与启动。故障跳过不计入 `uRotateCount`。
10. 无可用机组：`nDesired > 0` 且可用 = 0 → `bNoAvailableUnit := TRUE` + `16#0002_0007`（**瞬时码，可自恢复**，不锁存）。已在运行的机组**绝不因本条件被停**。
11. 主状态机 `CASE` + `ELSE → eFault + 16#0001_0005`。
12. 输出单一出口：命令数组、排名、领机号末尾统一赋值一次。

**故障码**

| 码 | 含义 | 类型 | 处置 |
|---|---|---|---|
| `16#0002_0007` | 无可用机组（需求 > 0、可用 = 0） | **瞬时** | 检查就绪信号与故障复位；恢复后自动继续 |
| `16#0002_0008` | 参数冲突（最小运行 + 最小停机 > 轮值周期） | **锁存** | 调小最小时长或加大轮值周期后复位 |
| `16#0001_0001` | `nDemand` 越界（已钳位） | 瞬时 | 修正 HMI 输入 |
| `16#0001_0008` | 时间增量非法（已钳位） | 瞬时 | 检查调用方 `uDeltaTimeMs` 来源 |
| `16#0001_0005` | 非法状态 | 锁存 | 报研发 |

**边界与防错**

| # | 边界 | 要求 |
|---|---|---|
| B1 | 需求台数 > 可用台数 | 钳位到可用数，`bNoAvailableUnit` 仅在可用 = 0 时置位；**不得**对着 5 台机发 8 条启动命令 |
| B2 | 最小停机时长 | 刚停的机在 `tMinStopTime` 内不得再启（防接触器高频动作）；被挡时置 `abBlockedByMinStop[i]` |
| B3 | 最小运行时长 | 在运行的机未满 `tMinRunTime` 不得停；`nDemand = 0` 也要等满（否则「点一下停」变成急停） |
| B4 | 故障机停机 | **越权**跳过最小运行时长立即停；这是 B3 的唯一例外，必须在头注释写明 |
| B5 | 绝不全部停 | 停机前必须已在运行台数 ≥ `nDesired`；这条与 B3 一起构成「先启后停」的硬保证 |
| B6 | 运行小时相同 | 按索引升序 tie-break，保证同样输入必得同样排序（可复算，R12） |
| B7 | 轮值周期到但条件不满足 | 进 `eRotatePending` 保留请求，**不丢**；每拍重试，条件满足即执行一次（不补做多次） |
| B8 | 时间增量异常 | 0 或 > 60 s → 钳位 + `16#0001_0008`；**不得**用负数或回绕值累加（会把运行时间算成负） |
| B9 | 断电保持 | `afRunSec / auStartCount` 是否保持由调用方决定（Retain 声明在调用侧）；头注释写明「不保持则每次上电从 0 起轮」 |
| B10 | 排序实现 | 选择排序，禁止 `WHILE` 无计数器；8 元固定规模，禁止动态数组 |

**自检向量**

| # | 场景 | 期望 |
|---|---|---|
| V1 | 3 台全就绪、运行时间均 0、`nDemand = 2` | 启动 0、1；`nLeadUnit = 0`；`anRank = [0,1,2]` |
| V2 | V1 后轮值周期到、最小时长已满 | 运行组合变为 {1,2}；`uRotateCount = 1`；`nLeadUnit = 1` |
| V3 | V2 瞬间 0 号机 `abUnitFault = TRUE` | 0 号立即停（不等最小运行时长）；启动 2 号；1、2 运行 |
| V4 | `nDemand = 2` 但仅 1 台 Ready | `bNoAvailableUnit = FALSE`（可用 ≠ 0）、只启 1 台、无 0002_0007 |
| V5 | `nDemand = 2` 且 0 台 Ready | `16#0002_0007`（瞬时）、`bNoAvailableUnit = TRUE`、无启动命令 |
| V6 | 要求停 0 号但 0 号刚运行 2 min（`tMinRunTime = 10 min`） | `abBlockedByMinRun[0] = TRUE`、`bRotatePending = TRUE`、0 号继续运行 |
| V7 | `tMinRunTime = 10 min`、`tMinStopTime = 5 min`、`tRotateInterval = 10 min` | 初始化即 `16#0002_0008` 锁存、`eFault`，但启停调度照常工作 |

**来源与去重**
- 来源标签：`lbp-basic-process`（LBP 以 `LBP_Aggr8` = 「最多 8 台聚合体控制」为粒度，本块沿用 8 台与 `cmd/ind` 的命令-反馈分离思想）、`lead-lag`（主备轮值工艺惯例）。clean-room，**未接触任何 LBP 源码**（闭源）。
- 去重：见 §1.4 第 4 行。**刻意不复用** `FB_DL_RuntimeMeter`：后者是「单机计时 + 保养预警」的呈现型组件（时/分/秒 + 启停次数），本块需要的是 8 路并行、秒级精度、参与排序的累加器；复用会导致二次换算与 8 个实例数组，反而更难维护（D-R3-05）。

---

### 7.5 `FC_DL_MultiPointLinear` ｜ DL_MathData ｜ 复杂度 M（6）｜ 来源 `lgf-math` + `lbp-basic-process`

**功能**：N 段折线查表线性插值（N = 2..16）。用于热电偶、异形卧式罐液位、流量计非线性修正、阀门特性补偿等**无法用两点直线表达**的标定场景。二分查找定位区间（O(log₂N)），输出所属段号与外推标志，区间外可选「钳位」或「线性外推」。

**接口契约**

```iecst
FUNCTION FC_DL_MultiPointLinear : LREAL
VAR_IN_OUT
    afX : ARRAY[0..15] OF LREAL;      // 折点自变量表，须严格递增 / Breakpoint X table, strictly increasing
    afY : ARRAY[0..15] OF LREAL;      // 折点因变量表 [EU] / Breakpoint Y table
END_VAR
VAR_INPUT
    fIn       : LREAL;                // 输入值 [EU] / Input value
    nCount    : INT;                  // 有效折点数 2..16 / Valid point count
    bClamp    : BOOL := TRUE;         // TRUE = 区间外钳位；FALSE = 线性外推 / Clamp or extrapolate
END_VAR
VAR_OUTPUT
    nSegment  : INT;                  // 命中段号 0..nCount-2，-1 = 无效 / Segment index, -1 = invalid
    bExtrapolated : BOOL;             // 本次结果来自外推 / Result extrapolated
    bClamped  : BOOL;                 // 本次结果被钳位 / Result clamped
    uErrorId  : UDINT;                // 故障码 / Error code
END_VAR
VAR
    nLo       : INT;                  // 二分下界 / Binary search low
    nHi       : INT;                  // 二分上界 / Binary search high
    nMid      : INT;                  // 二分中点 / Binary search mid
    nGuard    : INT;                  // 二分防死锁计数器 / Loop guard
    fX0       : LREAL;                // 段左折点 X / Left breakpoint X
    fX1       : LREAL;                // 段右折点 X / Right breakpoint X
    fY0       : LREAL;                // 段左折点 Y / Left breakpoint Y
    fY1       : LREAL;                // 段右折点 Y / Right breakpoint Y
    fSpan     : LREAL;                // 段宽 fX1 - fX0 / Segment span
    fRatio    : LREAL;                // 段内归一化位置 0..1 / Normalised position
    nIdx      : INT;                  // 单调性校验索引 / Monotonic check index
    bTableOk  : BOOL;                 // 表合法性标志 / Table validity flag
END_VAR
VAR CONSTANT
    DL_MPL_PTS_MIN : INT := 2;        // 最少折点数 / Minimum point count
    DL_MPL_PTS_MAX : INT := 16;       // 最多折点数（= 数组维度）/ Maximum point count
    DL_MPL_EPS     : LREAL := 1.0E-9; // 折点 X 严格递增容差 / Strict-increase tolerance
    DL_MPL_GUARD   : INT := 8;        // 二分最大迭代次数（log2(16)=4，留倍余）/ Binary search guard
END_VAR
```

**算法要点**
1. 预置返回 `afY[0]`（安全值），`nSegment := -1`，两个标志 FALSE，`uErrorId := 0`。
2. 校验 `nCount`：`< 2` 或 `> 16` → `16#0001_0001`，返回 `afY[0]`，`RETURN`。
3. 校验单调性：`FOR nIdx := 1 TO nCount-1`，要求 `afX[nIdx] - afX[nIdx-1] > DL_MPL_EPS`；不满足 → `16#0002_000B`，返回 `afY[0]`，`RETURN`（**整表作废**，不做「跳过坏点」的局部修补）。
4. 区间外处理：`fIn < afX[0]` 或 `fIn > afX[nCount-1]` → `bClamp = TRUE` 时返回端点值 + `bClamped := TRUE`；否则用**端点段**斜率外推 + `bExtrapolated := TRUE`。
5. 二分查找：`nLo := 0; nHi := nCount-1;` 循环条件 `nHi - nLo > 1`，中点取 `(nLo + nHi) / 2`（整数除法），`fIn >= afX[nMid]` 则 `nLo := nMid` 否则 `nHi := nMid`；每次循环 `nGuard++`，`nGuard > DL_MPL_GUARD` → 跳出 + `16#0001_0004`（理论上不可达，纯防御）。
6. 段内插值：`fSpan := fX1 - fX0`；`ABS(fSpan) > DL_MPL_EPS`（单调性已保证，此为二次防御）→ `fRatio := (fIn - fX0) / fSpan`；结果 `fY0 + fRatio * (fY1 - fY0)`。
7. 单出口返回。`nSegment := nLo`。

**故障码**

| 码 | 含义 | 类型 |
|---|---|---|
| `16#0001_0001` | `nCount` 越界（2..16） | 瞬时 |
| `16#0002_000B` | X 表非严格递增（重复点/逆序） | 瞬时 |
| `16#0001_0004` | 二分保护触发 | 瞬时 |
| `16#0001_0006` | `fIn` 为 NaN/Inf（平台可检测时） | 瞬时 |

**边界与防错**

| # | 边界 | 要求 |
|---|---|---|
| B1 | 重复 X 折点 | 判为非法表（除零的根因），整表拒绝，不做「取后一个 Y」的隐式选择 |
| B2 | 表非法时的返回值 | 返回 `afY[0]` 而非 0.0——0.0 在液位/温度场景会被当成真实测量值，`afY[0]` 至少落在量程内 |
| B3 | 区间外策略 | 默认**钳位**（`bClamp = TRUE`），外推必须显式关闭钳位；头注释说明「外推在传感器断线时会把 0 mA 放大成负温度」 |
| B4 | 段宽二次防御 | 单调性已保证段宽 > EPS，仍再判一次（防数组被外部改写） |
| B5 | `fIn` 恰好等于折点 | 二分收敛到左段，`fRatio = 1.0`，结果等于该折点 Y（无跳变） |
| B6 | 数组维度一致性 | `nCount ≤ 16` 由常量卡死；不做「按 `nCount` 动态索引越界」的写法 |

**自检向量**

| # | 输入 | 期望 |
|---|---|---|
| V1 | X={0,10,20,30}, Y={0,100,150,300}, `fIn=15` | 125.0，`nSegment = 1`（[10,20] 段），`bClamped = FALSE` |
| V2 | 同上，`fIn=25` | 225.0，`nSegment = 2` |
| V3 | 同上，`fIn=-5`，`bClamp=TRUE` | 0.0，`bClamped = TRUE` |
| V4 | 同上，`fIn=-5`，`bClamp=FALSE` | -50.0（用 [0,10] 段斜率 10），`bExtrapolated = TRUE` |
| V5 | X={0,10,10,30}（重复点） | `16#0002_000B`，返回 `afY[0]`，`nSegment = -1` |
| V6 | `nCount = 1` | `16#0001_0001`，返回 `afY[0]` |

**来源与去重**
- 来源标签：`lgf-math`（`LGF_ScaleLinear` 的定标族与非线性 UDT `LGF_typeNonLinSetpoints` 的**参数域形态**）、`lbp-basic-process`（`LBP_Polygon` 的「8 点折线转换」粒度）。仅借鉴「折线表 = X/Y 双数组 + 点数」这一接口形态，**算法（二分 + 段内线性）为独立实现**。
- 去重：见 §1.4 第 5 行。**刻意不调用** `FC_DL_LinearScale`（单段定标会把 LREAL 降为 REAL 再升回，且无法携带段号）。

---

### 7.6 `FC_DL_PolygonArea` ｜ DL_MathData ｜ 复杂度 M（5）｜ 来源 `lgf-math`

**功能**：平面多边形**有向面积、绝对面积与质心坐标**（鞋带公式 / Green 定理离散形式）。用于视觉定位中的料框有效面积、零件轮廓面积校验、机器人平面抓取中心计算、皮带跑偏区域判断。

**接口契约**

```iecst
FUNCTION FC_DL_PolygonArea : LREAL
VAR_IN_OUT
    afX : ARRAY[0..31] OF LREAL;      // 顶点 X 序列（无需闭合，末点不重复首点）/ Vertex X, not closed
    afY : ARRAY[0..31] OF LREAL;      // 顶点 Y 序列 / Vertex Y
END_VAR
VAR_INPUT
    nCount : INT;                     // 顶点数 3..32 / Vertex count
END_VAR
VAR_OUTPUT
    fCentroidX : LREAL;               // 质心 X [mm] / Centroid X
    fCentroidY : LREAL;               // 质心 Y [mm] / Centroid Y
    bCcw       : BOOL;                // TRUE = 逆时针（右手系）/ TRUE = counter-clockwise
    bDegenerate: BOOL;                // TRUE = 退化（共线/面积为零）/ Degenerate polygon
    uErrorId   : UDINT;               // 故障码 / Error code
END_VAR
VAR
    nI        : INT;                  // 顶点索引 / Vertex index
    nJ        : INT;                  // 下一顶点索引 (nI+1) MOD nCount / Next vertex index
    fCross    : LREAL;                // 单边叉积项 / Per-edge cross term
    fArea2    : LREAL;                // 二倍有向面积 / Twice the signed area
    fCxAcc    : LREAL;                // 质心 X 累加 / Centroid X accumulator
    fCyAcc    : LREAL;                // 质心 Y 累加 / Centroid Y accumulator
    fMeanX    : LREAL;                // 顶点算术平均 X（退化回退）/ Mean X fallback
    fMeanY    : LREAL;                // 顶点算术平均 Y / Mean Y fallback
    nGuard    : INT;                  // 循环防死锁计数器 / Loop guard
END_VAR
VAR CONSTANT
    DL_PGA_PTS_MIN : INT := 3;        // 最少顶点数 / Minimum vertices
    DL_PGA_PTS_MAX : INT := 32;       // 最多顶点数（= 数组维度）/ Maximum vertices
    DL_PGA_EPS     : LREAL := 1.0E-12;// 面积零判定容差 / Zero-area tolerance
    DL_PGA_SIX     : LREAL := 6.0;    // 质心公式分母常数 / Centroid denominator
    DL_PGA_TWO     : LREAL := 2.0;    // 面积公式分母常数 / Area denominator
END_VAR
```

**算法要点**
1. 校验 `nCount < 3` → `16#0002_000C`、返回 0、`bDegenerate := TRUE`、`RETURN`；`nCount > 32` → `16#0001_0001`、钳到 32 继续（多点比少点安全）。
2. 单遍累加：`FOR nI := 0 TO nCount-1`，`nJ := (nI + 1) MOD nCount`（`nI` 非负，`MOD` 无负数陷阱）；`fCross := afX[nI]*afY[nJ] - afX[nJ]*afY[nI]`；`fArea2 += fCross`；同时 `fCxAcc += (afX[nI] + afX[nJ]) * fCross`、`fCyAcc += (afY[nI] + afY[nJ]) * fCross`；`nGuard++`，超 `nCount + 1` 即跳出 + `16#0001_0004`。
3. 退化判定：`ABS(fArea2) <= DL_PGA_EPS`（全部顶点共线或重合）→ `bDegenerate := TRUE`、面积 0、质心回退为**顶点算术平均**（比返回 (0,0) 更有诊断价值），`16#0002_000C`。
4. 正常路径：`bCcw := (fArea2 > 0.0)`；面积 = `ABS(fArea2) / 2`；质心 `fCentroidX := fCxAcc / (DL_PGA_SIX * (fArea2 / DL_PGA_TWO))`，等价 `fCxAcc / (3.0 * fArea2)`（实现时用后者，少一次除法）。
5. 单出口返回 `ABS(fArea2) / 2`。

**故障码**

| 码 | 含义 | 类型 |
|---|---|---|
| `16#0002_000C` | 退化多边形（点数 < 3 / 共线 / 零面积） | 瞬时 |
| `16#0001_0001` | `nCount > 32`（已钳位） | 瞬时 |
| `16#0001_0004` | 循环保护触发 | 瞬时 |
| `16#0001_0006` | 顶点含 NaN/Inf | 瞬时 |

**边界与防错**

| # | 边界 | 要求 |
|---|---|---|
| B1 | 顶点越界 | `nCount ≤ 32` 硬约束；索引只用 `MOD nCount`，永不出现 `nCount` 本身 |
| B2 | 未闭合 vs 已闭合 | 约定「末点不重复首点」；若调用方重复传入首点（nCount 含重复），面积为正确值但质心偏移 → 头注释给出检测建议（首末点距离 < eps 时 nCount 减 1） |
| B3 | **自交多边形** | 鞋带公式返回**代数面积**（正负抵消），不是几何面积。头注释必须披露：「自交多边形结果无几何意义，调用方须保证简单多边形」，并给「视觉轮廓先去重、按角度排序」的调用侧提示 |
| B4 | 精度 | 必须 LREAL：32 点 × 1e6 mm 坐标的叉积累加可达 1e12，REAL 的 24 位尾数在此量级已丢 5 位有效数字 |
| B5 | 绕向 | `bCcw` 由 `fArea2` 符号给出，供调用方判断轮廓方向（视觉库常给顺时针） |
| B6 | 退化时的质心 | 返回顶点算术平均 + `bDegenerate`，**不返回 0,0**（0,0 会让机器人往原点跑） |
| B7 | 重复顶点 | 相邻重复点叉积为 0，不影响结果；不单独报错（视觉轮廓去重是调用方职责） |

**自检向量**

| # | 多边形 | 期望面积 | 质心 | 其它 |
|---|---|---|---|---|
| V1 | (0,0),(1,0),(1,1),(0,1) | 1.0 | (0.5, 0.5) | `bCcw = TRUE` |
| V2 | V1 逆序 | 1.0 | (0.5, 0.5) | `bCcw = FALSE` |
| V3 | (0,0),(4,0),(0,3) | 6.0 | (1.3333…, 1.0) | `bCcw = TRUE` |
| V4 | (0,0),(1,1),(2,2) 共线 | 0.0 | (1.0, 1.0) | `bDegenerate = TRUE`、`16#0002_000C` |
| V5 | `nCount = 2` | 0.0 | (0.5·Σ) | `16#0002_000C`，立即返回 |

**来源与去重**
- 来源标签：`lgf-math`（Math Operations 下「二维/三维距离」等平面几何族的**分类位置**）。鞋带公式为公开数学方法，独立实现。
- 去重：见 §1.4 第 6 行。

---

### 7.7 `FC_DL_LineIntersection` ｜ DL_MathData ｜ 复杂度 L（3）｜ 来源 `lgf-math`

**功能**：二维两直线（或两线段）交点求解。返回「是否存在唯一交点」的布尔量，交点坐标经 `VAR_OUTPUT` 输出。用于视觉十字标定、皮带跑偏中心线求交、两相机视场交叠区定位、机器人平面两轴交汇点计算。

**接口契约**

```iecst
FUNCTION FC_DL_LineIntersection : BOOL
VAR_INPUT
    fX1 : LREAL;                      // 线 1 起点 X [mm] / Line 1 start X
    fY1 : LREAL;                      // 线 1 起点 Y [mm] / Line 1 start Y
    fX2 : LREAL;                      // 线 1 终点 X [mm] / Line 1 end X
    fY2 : LREAL;                      // 线 1 终点 Y [mm] / Line 1 end Y
    fX3 : LREAL;                      // 线 2 起点 X [mm] / Line 2 start X
    fY3 : LREAL;                      // 线 2 起点 Y [mm] / Line 2 start Y
    fX4 : LREAL;                      // 线 2 终点 X [mm] / Line 2 end X
    fY4 : LREAL;                      // 线 2 终点 Y [mm] / Line 2 end Y
    fEps        : LREAL := 1.0E-9;    // 平行判定容差 / Parallel tolerance
    bSegmentMode: BOOL := FALSE;      // TRUE = 按线段求交（交点须落在两段内）/ Segment mode
END_VAR
VAR_OUTPUT
    fX      : LREAL;                  // 交点 X [mm]，无交点时为 0 / Intersection X, 0 when none
    fY      : LREAL;                  // 交点 Y [mm] / Intersection Y
    fT      : LREAL;                  // 线 1 参数 t（0=起点,1=终点）/ Parameter along line 1
    fU      : LREAL;                  // 线 2 参数 u / Parameter along line 2
    uErrorId: UDINT;                  // 故障码 / Error code
END_VAR
VAR
    fDen    : LREAL;                  // 行列式分母 / Determinant denominator
    fDx1    : LREAL;                  // 线 1 方向 X 分量 / Line 1 direction X
    fDy1    : LREAL;                  // 线 1 方向 Y 分量 / Line 1 direction Y
    fDx2    : LREAL;                  // 线 2 方向 X 分量 / Line 2 direction X
    fDy2    : LREAL;                  // 线 2 方向 Y 分量 / Line 2 direction Y
    fTol    : LREAL;                  // 参数区间容差 / Parameter tolerance
END_VAR
VAR CONSTANT
    DL_LI_DEADBAND : LREAL := 1.0E-6; // 零长度线判定容差 [mm] / Zero-length tolerance
END_VAR
```

**算法要点**
1. 预置 `fX := 0; fY := 0; fT := 0; fU := 0; uErrorId := 0`。
2. 退化线检测：`ABS(fX2-fX1) + ABS(fY2-fY1) <= DL_LI_DEADBAND`（线 1 退化为点）或线 2 同理 → `16#0001_0001`、返回 FALSE。
3. 容差规整：`fEps <= 0` → 取 `1.0E-9` + `16#0001_0001`（容差不能为 0 或负）。
4. 分母：`fDx1 := fX2-fX1; fDy1 := fY2-fY1; fDx2 := fX4-fX3; fDy2 := fY4-fY3; fDen := fDx1*fDy2 - fDy1*fDx2`。
5. 平行/重合：`ABS(fDen) <= fEps` → `16#0002_000D`、返回 FALSE（重合也归此类：无**唯一**交点）。
6. 参数求解：`fT := ((fX3-fX1)*fDy2 - (fY3-fY1)*fDx2) / fDen`；`fU := ((fX3-fX1)*fDy1 - (fY3-fY1)*fDx1) / fDen`。
7. 线段模式：`bSegmentMode = TRUE` 时要求 `fT ∈ [-fTol, 1+fTol]` 且 `fU ∈ [-fTol, 1+fTol]`（`fTol` 取 `fEps` 量级），否则返回 FALSE 且**不置故障码**（线段不相交是正常业务结果，不是错误）。
8. 求交：`fX := fX1 + fT*fDx1`；`fY := fY1 + fT*fDy1`（用线 1 参数化，几何上更稳定）；返回 TRUE。

**故障码**

| 码 | 含义 | 类型 |
|---|---|---|
| `16#0002_000D` | 两直线平行或重合（无唯一交点） | 瞬时 |
| `16#0001_0001` | 退化输入（零长度线 / 容差 ≤ 0） | 瞬时 |
| `16#0001_0006` | 输入含 NaN/Inf | 瞬时 |

**边界与防错**

| # | 边界 | 要求 |
|---|---|---|
| B1 | 平行判定 | 用**绝对容差** `ABS(fDen) <= fEps`；坐标量级到 1e6 时 `fDen` 也可能到 1e12，故 `fEps` 必须按坐标量级配置，头注释给出经验式「`fEps ≈ 1e-9 × 坐标量级²`」 |
| B2 | 零长度线 | 明确报错而不是返回 FALSE 了事——「起点终点填反/全 0」是视觉标定最常见的配置错误 |
| B3 | 线段模式不相交 | 返回 FALSE、`uErrorId = 0`。业务上的「不相交」不是故障，若也置码会让上位机把正常判定当异常刷屏 |
| B4 | 重合直线 | 归入平行类（`0002_000D`），因为无穷多交点无法用单一 `fX/fY` 表达 |
| B5 | 交点数值 | 一律由线 1 参数化求点（`fX1 + fT*fDx1`），不用两式平均——平均会引入 2 次额外误差 |
| B6 | 输出初值 | 无交点时 `fX/fY` 必须显式清 0（FC 局部变量在部分平台不复位，禁止依赖「默认 0」） |

**自检向量**

| # | 输入 | 期望 |
|---|---|---|
| V1 | (0,0)-(4,4) × (0,4)-(4,0) | TRUE，(2.0, 2.0)，`fT = 0.5`，`fU = 0.5` |
| V2 | (0,0)-(1,0) × (0,1)-(1,1) | FALSE，`16#0002_000D` |
| V3 | (0,0)-(10,10) × (5,5)-(15,15) 重合 | FALSE，`16#0002_000D` |
| V4 | 线段模式：(0,0)-(1,1) × (2,0)-(0,2) | TRUE，交点 (1,1)，`fU = 0.5`（端点命中） |
| V5 | 线段模式：(0,0)-(1,1) × (2,2)-(3,3) | FALSE，`uErrorId = 0`（共线平行已在 V3 覆盖；此处为平行不共线） |
| V6 | (5,5)-(5,5) 起点终点相同 | FALSE，`16#0001_0001` |

**来源与去重**
- 来源标签：`lgf-math`（平面几何族分类）。解析几何方法为公开数学，独立实现。
- 去重：见 §1.4 第 7 行。

---

### 7.8 `FC_DL_Crc32Ethernet` ｜ DL_MathData ｜ 复杂度 M（6）｜ 来源 `oscat-network`（T1）+ `crc32-iso-hdlc`

**功能**：标准 **CRC-32/ISO-HDLC**（即以太网 FCS、ZIP、PNG 使用的同一参数模型）校验码计算。支持**分块链式调用**（大报文分批算，用上次结果作 seed），用于固件包完整性校验、文件传输校验、EtherCAT/Profinet 诊断帧、上位机与 PLC 的报文签核。

**接口契约**

```iecst
FUNCTION FC_DL_Crc32Ethernet : DWORD
VAR_IN_OUT
    aabyData : ARRAY[0..255] OF BYTE;   // 待校验字节缓冲 / Data buffer
END_VAR
VAR_INPUT
    nLength   : INT;                    // 本次参与计算的字节数 0..256 / Byte count this call
    uCrcSeed  : DWORD := 16#FFFF_FFFF;  // 初值或上一块的返回值（链式）/ Initial or chained value
    bFinalXor : BOOL := TRUE;           // TRUE = 输出前异或 16#FFFF_FFFF（最后一块才置 TRUE）/ Final XOR
END_VAR
VAR_OUTPUT
    uErrorId  : UDINT;                  // 故障码 / Error code
    nBytesUsed: INT;                    // 实际参与计算的字节数（钳位后）/ Bytes actually processed
END_VAR
VAR
    uCrc   : DWORD;                     // 工作寄存器 / Working register
    nI     : INT;                       // 字节索引 / Byte index
    nBit   : INT;                       // 位计数 0..7 / Bit counter
    uByte  : DWORD;                     // 当前字节零扩展 / Current byte, zero-extended
END_VAR
VAR CONSTANT
    DL_CRC32_POLY_REFLECTED : DWORD := 16#EDB8_8320;  // IEEE 802.3 多项式 16#04C11DB7 的位反射形式 / Reflected polynomial
    DL_CRC32_INIT           : DWORD := 16#FFFF_FFFF;  // 初值全 1 / All-ones init
    DL_CRC32_XOROUT         : DWORD := 16#FFFF_FFFF;  // 终值异或 / Final XOR
    DL_CRC32_BUF_MAX        : INT   := 256;           // 缓冲上限 / Buffer limit
    DL_CRC32_BITS_PER_BYTE  : INT   := 8;             // 每字节位数 / Bits per byte
END_VAR
```

**算法要点（反射算法，逐位；禁止查表以外的任何位访问方言）**
1. `uCrc := uCrcSeed`；`nBytesUsed := 0`；`uErrorId := 0`。
2. 长度处理：`nLength < 0` → `nLength := 0` + `16#0001_0001`；`nLength > 256` → `nLength := 256` + `16#0001_0001`（钳位而非拒绝：短报文场景不会因超长缓冲炸掉）。
3. 主循环 `FOR nI := 0 TO nLength-1`：`uByte := BYTE_TO_DWORD(aabyData[nI])`；`uCrc := uCrc XOR uByte`；内层 `FOR nBit := 1 TO 8`：若 `(uCrc AND 16#0000_0001) <> 0` 则 `uCrc := SHR(uCrc,1) XOR DL_CRC32_POLY_REFLECTED`，否则 `uCrc := SHR(uCrc,1)`。
4. 终值：`IF bFinalXor THEN uCrc := uCrc XOR DL_CRC32_XOROUT; END_IF`；`nBytesUsed := nLength`；返回 `uCrc`。
5. **链式调用契约**：分块时前 n-1 块传 `bFinalXor := FALSE`，把返回值作为下一块的 `uCrcSeed`；最后一块 `bFinalXor := TRUE`。头注释给出这段调用序列的文字说明（不给实现代码）。

**故障码**

| 码 | 含义 | 类型 |
|---|---|---|
| `16#0001_0001` | 长度越界（负值或 > 256，已钳位） | 瞬时 |

**边界与防错**

| # | 边界 | 要求 |
|---|---|---|
| B1 | **多项式方向** | 必须用反射值 `16#EDB88320` 配**右移**；用 `16#04C11DB7` 配左移得到的是 CRC-32/BZIP2（`123456789` → `16#FC891918`），两者不可混搭。头注释写明「混搭是 CRC 实现第一大错」 |
| B2 | 初值与终值 | 初值 `16#FFFF_FFFF`、终值异或 `16#FFFF_FFFF`，二者缺一都是别的变体（JAMCRC 不异或终值、POSIX 初值为 0） |
| B3 | 空输入 | `nLength = 0` + 默认 seed → 结果 `16#0000_0000`，这是**正确值**而非错误，不得报错 |
| B4 | 分块 | `bFinalXor` 只在最后一块为 TRUE；中间块若误置 TRUE，结果等于多异或一次，整包校验必失败且极难定位 |
| B5 | 扫描周期 | 256 字节 × 8 位 = 2048 次内层循环，属重计算；头注释要求「放在慢任务或事件触发任务，不要放进 1 ms 高速任务」 |
| B6 | 无表实现 | 首版用逐位算法（零 RAM 开销、可读性最好）；若现场需要提速，按扩产规则「精度/性能变体」另立 `FC_DL_Crc32EthernetFast`（256 项查表），**不在本组件内加 `MODE` 开关**（禁止巨无霸） |
| B7 | 字节序披露 | CRC 结果本身是数值；以太网 FCS 上线时按**小端**（低字节先发）填入帧尾，头注释必须写明「本函数只算数值，字节序由组帧方决定」 |

**自检向量（R12，必须复算后写入手册）**

| # | 输入 | 长度 | seed | finalXor | 期望 |
|---|---|---|---|---|---|
| V1 | ASCII `"123456789"`（`31 32 33 34 35 36 37 38 39`） | 9 | `16#FFFF_FFFF` | TRUE | **`16#CBF4_3926`** |
| V2 | 空 | 0 | `16#FFFF_FFFF` | TRUE | `16#0000_0000` |
| V3 | 单字节 `00` | 1 | `16#FFFF_FFFF` | TRUE | `16#D202_EF8D` |
| V4 | 分块：`"1234"` 后 `"56789"` | 4 + 5 | 首块 seed `FFFFFFFF`，次块 seed = 首块返回值 | 首块 FALSE、次块 TRUE | **`16#CBF4_3926`**（与 V1 相同，验证链式语义） |
| V5 | `nLength = 300` | 300 | — | — | `nBytesUsed = 256`、`16#0001_0001` |

**来源与去重**
- 来源标签：`oscat-network`（OSCAT Network 的 CRC 家族提供了「校验函数按协议分族、独立成 FC」的组织方式）、`crc32-iso-hdlc`（公开参数模型与 check 值）。**未复制 OSCAT 源码**（OSCAT 数组函数用 `ADR/SIZEOF` 指针入参，本库 R3 明令禁用指针，改用 `VAR_IN_OUT` 数组——这是接口层的根本差异）。
- 去重：见 §1.4 第 8 行。与 `FC_DL_Crc16Modbus` 并列构成 CRC 族，手册交叉引用「何时用哪个」。

---

### 7.9 `FC_DL_LrcChecksum` ｜ DL_MathData ｜ 复杂度 L（3）｜ 来源 `oscat-network`（T1）+ `modbus-ascii`

**功能**：Modbus ASCII 模式的 **LRC（纵向冗余校验）** 计算：把地址、功能码、数据字节按无符号 8 位累加，取二进制补码（`0x100 - sum` 的低 8 位）。用于电表、称重仪表、老式温控器等仍走 ASCII 模式的设备的收帧校验。

**接口契约**

```iecst
FUNCTION FC_DL_LrcChecksum : BYTE
VAR_IN_OUT
    aabyData : ARRAY[0..255] OF BYTE;   // 参与校验的**解码后**字节（不含 ':' 与 CR/LF）/ Decoded bytes, no framing
END_VAR
VAR_INPUT
    nLength : INT;                      // 字节数 0..256 / Byte count
END_VAR
VAR_OUTPUT
    uSumLow : BYTE;                     // 累加和低 8 位（诊断用）/ Low byte of the sum
    uErrorId: UDINT;                    // 故障码 / Error code
END_VAR
VAR
    uSum : UDINT;                       // 累加器（宽类型防中间溢出）/ Wide accumulator
    nI   : INT;                         // 字节索引 / Byte index
END_VAR
VAR CONSTANT
    DL_LRC_MOD   : UDINT := 256;        // 模 256 / Modulus
    DL_LRC_BUF_MAX : INT := 256;        // 缓冲上限 / Buffer limit
END_VAR
```

**算法要点**
1. `uSum := 0`；长度处理同 CRC32（负值 → 0，> 256 → 256，均置 `16#0001_0001`）。
2. 累加：`uSum := uSum + BYTE_TO_UDINT(aabyData[nI])`（用 UDINT 累加，**不要**用 `BYTE` 自加依赖回绕——部分平台对 `BYTE` 溢出行为未定义）。
3. `uSumLow := DWORD_TO_BYTE(uSum AND 16#0000_00FF)`。
4. `LRC := (256 - uSumLow) AND 16#FF`，实现为 `INT_TO_BYTE((256 - BYTE_TO_INT(uSumLow)) MOD 256)`，返回值即 LRC。
5. 头注释写明**帧边界**：`':'`(0x3A) 与 CR/LF **不参与**计算；ASCII 字符必须先解码为字节再传入（配套 `FC_DL_HexStringToBytes`）。

**故障码**

| 码 | 含义 | 类型 |
|---|---|---|
| `16#0001_0001` | 长度越界（已钳位） | 瞬时 |

**边界与防错**

| # | 边界 | 要求 |
|---|---|---|
| B1 | 是否含帧头帧尾 | **不含**。传错（把 `':'` 或 `\r\n` 算进去）是现场 LRC 对不上的第一原因，头注释用加粗文字声明 |
| B2 | 传 ASCII 字符还是字节 | 必须传**解码后的字节**；若误传 ASCII 字符码（`'0'`=0x30），结果必然错。头注释给出「先 `FC_DL_HexStringToBytes` 再本函数」的两步调用顺序 |
| B3 | 空报文 | `nLength = 0` → 和为 0 → `256-0 = 256`，取低 8 位得 `16#00`。这是正确值，不报错 |
| B4 | 类型溢出 | 中间量用 `UDINT`，禁止 `BYTE` 自加回绕（跨平台差异） |
| B5 | 与 CRC 的关系 | LRC 与 CRC-16 **不可互算、不可互验**；头注释写「ASCII 模式用 LRC，RTU 模式用 CRC，同一设备切换模式时校验字段同时变」 |
| B6 | 大小写 | 输出是数值 `BYTE`；转 ASCII 十六进制字符（`"FB"` vs `"fb"`）由组帧方决定，本函数不输出字符串 |

**自检向量（R12）**

| # | 字节序列 | 和 | 期望 LRC |
|---|---|---|---|
| V1 | `01 03 00 00 00 01` | `0x05` | **`16#FB`**（标准读保持寄存器请求） |
| V2 | `01 03 02 12 34` | `0x4C` | **`16#B4`**（标准响应，寄存器值 `1234`） |
| V3 | 空（长度 0） | `0x00` | `16#00` |
| V4 | `FF FF` | `0x1FE` → 低 8 位 `FE` | `16#02` |
| V5 | `00` | `0x00` | `16#00` |

**来源与去重**
- 来源标签：`oscat-network`（校验函数族的组织方式）、`modbus-ascii`（Modbus 应用协议规范的 ASCII 传输模式定义，公开规范）。独立实现。
- 去重：见 §1.4 第 9 行。

---

### 7.10 `FB_DL_LifoStack` ｜ DL_MathData ｜ 复杂度 M（5）｜ 来源 `lgf-datahandling`

**功能**：定长 64 深度 **LIFO 栈**（后进先出），支持压栈、弹栈、窥视栈顶、清空，带**上溢/下溢锁存**与单调计数。用于：工艺路径回溯（走了哪些工位，原路退回）、嵌套配方/子程序解析、报警确认的「撤销」语义、深度优先搜索的待办表。

**接口契约**

```iecst
TYPE E_DL_StackState :
(
    eEmpty := 0,     // 空栈 / Empty
    eReady := 10,    // 有数据可弹 / Has data
    eFault := 99     // 上溢/下溢锁存，需 bClear 解除 / Overflow or underflow latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_LifoStack
VAR_INPUT
    bPush      : BOOL;                     // 上升沿：压入 fPushValue / Rising edge: push
    fPushValue : LREAL := 0.0;             // 待压入值 [EU] / Value to push
    bPop       : BOOL;                     // 上升沿：弹出栈顶 / Rising edge: pop
    bPeek      : BOOL;                     // TRUE：fTop 输出当前栈顶（不改变栈）/ TRUE: expose top without popping
    bClear     : BOOL;                     // TRUE：清空栈与锁存（保留累计计数）/ TRUE: clear stack and latches
    bEnable    : BOOL := TRUE;             // 使能，FALSE 时禁止入栈/出栈 / Enable
END_VAR
VAR_OUTPUT
    fTop       : LREAL;                    // 栈顶值 [EU]，空栈时 0.0 / Top value, 0.0 when empty
    fPopValue  : LREAL;                    // 本次弹出值 [EU]，未弹出时 0.0 / Popped value
    nCount     : INT;                      // 当前深度 0..64 / Current depth
    bEmpty     : BOOL;                     // 空栈 / Empty
    bFull      : BOOL;                     // 满栈 / Full
    bOverflow  : BOOL;                    // 上溢锁存（压栈被拒）/ Overflow latched
    bUnderflow : BOOL;                    // 下溢锁存（弹栈被拒）/ Underflow latched
    uPushCount : UDINT;                   // 累计入栈次数（饱和）/ Total pushes
    uPopCount  : UDINT;                   // 累计出栈次数（饱和）/ Total pops
    bError     : BOOL;                    // 故障标志（上溢/下溢锁存）/ Fault flag
    uErrorId   : UDINT;                   // 故障码 / Error code
    eState     : E_DL_StackState;         // 状态 / State
END_VAR
VAR
    fbTrigPush : R_TRIG;                  // 压栈沿 / Push edge
    fbTrigPop  : R_TRIG;                  // 弹栈沿 / Pop edge
    afStack    : ARRAY[0..63] OF LREAL;   // 栈体 / Stack body
    nTop       : INT;                     // 栈顶指针 = 元素个数（0 = 空）/ Top pointer = element count
    bOvfLatch  : BOOL;                    // 上溢锁存 / Overflow latch
    bUnfLatch  : BOOL;                    // 下溢锁存 / Underflow latch
    bDidPush   : BOOL;                    // 本拍已压栈 / Pushed this scan
    bDidPop    : BOOL;                    // 本拍已弹栈 / Popped this scan
    eStateInt  : E_DL_StackState;         // 内部状态 / Internal state
END_VAR
VAR CONSTANT
    DL_LIFO_CAP    : INT   := 64;         // 栈容量 / Capacity
    DL_LIFO_CNT_MAX: UDINT := 16#FFFF_FFFE; // 计数饱和值 / Counter saturation
END_VAR
```

**语义与状态机**

| 状态 | 条件 | 说明 |
|---|---|---|
| `eEmpty` | `nTop = 0` 且无锁存 | `fTop := 0.0`、`bEmpty := TRUE` |
| `eReady` | `nTop > 0` 且无锁存 | `fTop := afStack[nTop-1]` |
| `eFault` | 上溢或下溢锁存 | 仍**允许反向操作**（满栈时仍可弹、空栈时仍可压），只是 `bError := TRUE`；`bClear` 解除 |

**算法要点（每拍顺序）**
1. `fbTrigPush(CLK := bPush)`、`fbTrigPop(CLK := bPop)` 无条件刷新（R7）。
2. `bClear` 优先：指针归 0、两锁存清、`uErrorId := 0`；`uPushCount/uPopCount` **不清**（生命周期统计）。
3. **同拍压弹的裁决**：`bPush` 与 `bPop` 同时出现上升沿时，**先压后弹**（弹出的是刚压入的值）。理由：这是「写入后立即读回校验」的常见用法；若先弹后压，读回的是旧栈顶，调用方会误判。此约定必须写入手册，并置 `bSimultaneous`——本版不输出该位，改为**头注释声明**（避免接口膨胀）。
4. 压栈：`bEnable` 且 `nTop < 64` → `afStack[nTop] := fPushValue`、`nTop++`、`uPushCount++`（饱和）、`bDidPush := TRUE`；`nTop >= 64` → `bOvfLatch := TRUE`、`16#0001_0009`（**拒绝写入**，不覆盖栈底）。
5. 弹栈：`bEnable` 且 `nTop > 0` → `nTop--`、`fPopValue := afStack[nTop]`、`uPopCount++`、`bDidPop := TRUE`；`nTop = 0` → `bUnfLatch := TRUE`、`16#0001_000A`、`fPopValue := 0.0`。
6. 窥视：`bPeek` 只影响 `fTop` 的刷新时机（每拍都刷即可，`bPeek` 保留给「需要显式取值」的语义），**不得**因 `bPeek` 改变 `nTop`。
7. 状态机 `CASE eStateInt OF ... ELSE → eFault + 16#0001_0005`。
8. 输出单一出口：`nCount`、`bEmpty`、`bFull`、`bOverflow`、`bUnderflow`、`bError` 末尾统一赋值。

**故障码**

| 码 | 含义 | 类型 |
|---|---|---|
| `16#0001_0009` | 上溢：满栈压入被拒 | 锁存 |
| `16#0001_000A` | 下溢：空栈弹出被拒 | 锁存 |
| `16#0001_0005` | 非法状态 | 锁存 |

**边界与防错**

| # | 边界 | 要求 |
|---|---|---|
| B1 | 满栈压入 | **拒绝**，不覆盖最旧元素（LIFO 无「丢最旧」语义，静默覆盖会让路径回溯错位） |
| B2 | 空栈弹出 | 拒绝，`fPopValue := 0.0`（**返回 0 而不是保留上次值**，否则调用方会把旧值当新值用） |
| B3 | 同拍压弹 | 先压后弹（见算法要点 3），头注释声明 |
| B4 | 上溢后继续压 | 仍拒绝且**不重复计数**（`uPushCount` 只在真写入时增），避免「溢出一次计数暴涨」 |
| B5 | `bClear` 与锁存 | `bClear` 是唯一清锁存路径（R15）；清空后 `bError := FALSE`、`uErrorId := 0` |
| B6 | 指针越界防御 | 所有写入前判 `nTop >= 0 AND nTop < DL_LIFO_CAP`（双检），所有读取前判 `nTop > 0` |
| B7 | 与 FIFO 的区别 | `FB_DL_RingBufferLReal` 有读/写双指针与回绕，本块只有单栈顶指针、无回绕；手册给「同一序列 1,2,3 → FIFO 出 1,2,3；LIFO 出 3,2,1」对照表 |

**自检向量**

| # | 序列 | 期望 |
|---|---|---|
| V1 | push 1 → push 2 → push 3 | `nCount = 3`、`fTop = 3`、`eReady` |
| V2 | V1 → pop | `fPopValue = 3`、`nCount = 2`、`fTop = 2` |
| V3 | V2 → pop ×2 → pop | 第 3 次 pop：`nCount = 0`、`bUnderflow = TRUE`、`16#0001_000A`、`fPopValue = 0.0` |
| V4 | 连压 65 次 | 第 65 次：`nCount = 64`、`bOverflow = TRUE`、`16#0001_0009`、`uPushCount = 64` |
| V5 | 同拍 push 9 + pop | `fPopValue = 9`、`nCount` 不变（净 0 变化） |
| V6 | V3 → `bClear` 一拍 | `nCount = 0`、`bError = FALSE`、`uErrorId = 0`、`uPopCount` 保持 |

**来源与去重**
- 来源标签：`lgf-datahandling`（LGF 把 FIFO / LIFO 拆成两个独立 FB，且都带「满/空/长度」状态位——本块沿用该接口粒度）。**LGF 为闭源，仅借鉴分类与参数域，clean-room 实现。**
- 去重：见 §1.4 第 10 行。

---

### 7.11 `FB_DL_MedianFilter` ｜ DL_MathData ｜ 复杂度 M（6）｜ 来源 `lgf-measurement` + `oscat-basic`

**功能**：滑动窗口中值滤波器（窗口 3/5/7/9/11/13/15，奇数）。对**孤立脉冲干扰**（变频器干扰、接触器拉弧、单次 AD 跳变）免疫：窗口内 1 个坏点被整体剔除，而均值滤波会把坏点摊到全窗。用于称重、温度、压力、位置反馈的采集前端。

**接口契约**

```iecst
TYPE E_DL_MedianState :
(
    eEmpty  := 0,    // 未采到任何样本 / No samples yet
    eFilling:= 10,   // 窗口未满，输出已到样本的中值 / Filling, median of available samples
    eReady  := 20,   // 窗口已满 / Window full
    eFault  := 99    // 参数非法或窗口重置中 / Invalid parameter or reset
);
END_TYPE

FUNCTION_BLOCK FB_DL_MedianFilter
VAR_INPUT
    fIn     : REAL;                        // 采样输入 [EU] / Sample input
    bSample : BOOL := TRUE;                // TRUE = 本拍采一个样本（给单周期脉冲即按需采样）/ Sample this scan
    nWindow : INT := 5;                    // 窗口长度，奇数 3..15 / Window length, odd
    bClear  : BOOL;                        // TRUE：清空窗口重新填充 / Clear and refill
END_VAR
VAR_OUTPUT
    fMedian : REAL;                        // 中值 [EU] / Median
    nFilled : INT;                         // 当前有效样本数 0..15 / Valid sample count
    bValid  : BOOL;                        // 至少有 1 个样本 / At least one sample
    bWindowFull : BOOL;                    // 窗口已满 / Window full
    uErrorId: UDINT;                       // 故障码 / Error code
    eState  : E_DL_MedianState;            // 状态 / State
END_VAR
VAR
    afWindow : ARRAY[0..14] OF REAL;       // 环形样本窗 / Circular sample window
    afSort   : ARRAY[0..14] OF REAL;       // 排序副本（不破坏原窗）/ Sorting copy
    nWrite   : INT;                        // 写指针 0..14 / Write index
    nFilledInt : INT;                      // 有效样本数 / Valid count
    nWinEff  : INT;                        // 生效窗口（钳位后奇数）/ Effective odd window
    nLastWin : INT;                        // 上拍窗口（变更检测，R14）/ Previous window
    nI       : INT;                        // 外层索引 / Outer index
    nJ       : INT;                        // 内层索引 / Inner index
    fTmp     : REAL;                       // 交换临时量 / Swap temp
    nGuard   : INT;                        // 排序防死锁计数器 / Sort guard
    eStateInt: E_DL_MedianState;           // 内部状态 / Internal state
END_VAR
VAR CONSTANT
    DL_MED_WIN_MIN : INT := 3;             // 最小窗口 / Minimum window
    DL_MED_WIN_MAX : INT := 15;            // 最大窗口（= 数组维度）/ Maximum window
    DL_MED_CAP     : INT := 15;            // 容量 / Capacity
    DL_MED_EPS     : REAL := 1.0E-6;       // 浮点判零容差 / Float zero tolerance
END_VAR
```

**语义与状态机**

| 状态 | 条件 | 输出 |
|---|---|---|
| `eEmpty` | `nFilledInt = 0` | `fMedian := 0.0`、`bValid := FALSE` |
| `eFilling` | `0 < nFilledInt < nWinEff` | 输出**已有样本**的中值（不等装满，保证上电即有值） |
| `eReady` | `nFilledInt = nWinEff` | 输出整窗中值 |
| `eFault` | `nWindow` 被钳位时短暂置位 | 参数已钳位、继续运行，`uErrorId := 16#0001_0001` |

**算法要点**
1. 窗口规整：`nWindow` 越界（<3 或 >15）→ 钳到最近合法值（<3 → 3，>15 → 15）+ `16#0001_0001`；**偶数 → 加 1 变奇数**（上限 15）+ `16#0001_0001`。连续钳位不报错刷屏（只在钳位发生的那拍置码）。
2. **R14 语义参数变更**：`nWinEff <> nLastWin` → 整窗作废（`afWindow` 不必清零，但 `nFilledInt := 0`、`nWrite := 0`），并置 `16#0001_0001`；`nLastWin := nWinEff`。理由：新旧窗口混填的中值无物理意义。
3. 采样：`bSample` → 写 `afWindow[nWrite] := fIn`；`nWrite := (nWrite + 1) MOD DL_MED_CAP`；`nFilledInt := MIN(nFilledInt + 1, nWinEff)`。
4. 取有效样本：把 `afWindow` 中**最近 nFilledInt 个**复制到 `afSort`（从 `nWrite-1` 反向取，负数要先 `+ DL_MED_CAP` 再 `MOD` —— 负 MOD 陷阱，R2 已沉淀）。**禁止**复制整窗（未填区是 0，会把中值拉低）。
5. 排序：对 `afSort[0..nFilledInt-1]` 做插入排序（n ≤ 15，最坏 105 次比较），每次内层 `nGuard++`，超 `DL_MED_CAP * DL_MED_CAP` 即跳出 + `16#0001_0004`。
6. 取中值：`fMedian := afSort[nFilledInt / 2]`（整除；`nFilledInt` 为奇数时即正中）。
7. 若 `nFilledInt` 为偶数（理论上被 B2 排除，仍防御）→ 取 `(afSort[n/2-1] + afSort[n/2]) / 2.0`。
8. 主状态机 `CASE` + `ELSE → eFault + 16#0001_0005`；输出末尾统一赋值。

**故障码**

| 码 | 含义 | 类型 |
|---|---|---|
| `16#0001_0001` | 窗口非法（越界/偶数，已钳位）或窗口变更触发重填 | 瞬时 |
| `16#0001_0004` | 排序循环保护触发 | 瞬时 |
| `16#0001_0006` | 样本为 NaN/Inf（已跳过，不入窗） | 瞬时 |
| `16#0001_0005` | 非法状态 | 锁存 |

**边界与防错**

| # | 边界 | 要求 |
|---|---|---|
| B1 | 未填满 | 输出**已到样本**的中值而不是 0（上电即 0 会让 PID 认为测量为 0，直接满输出） |
| B2 | 偶数窗口 | 无唯一中值 → 强制奇数；**不得**静默取「中间两个的平均」（那会退化成均值，尖峰重新渗入） |
| B3 | 环形回退取数 | `(nWrite - 1 - k + DL_MED_CAP * 2) MOD DL_MED_CAP`，正数化后再取模（负 MOD 跨平台不一致） |
| B4 | 排序副本 | 必须排序副本，**不得**原地排序 `afWindow`（原地排序会打乱环形时间顺序） |
| B5 | 窗口运行中变更 | 整窗重填（R14）；手册写明「调试期改窗口会有一个窗口长度的空档」 |
| B6 | 尖峰与窄脉冲 | 中值剔除**孤立**尖峰；若干扰持续 ≥ 半个窗口宽度（如 3 个连续坏点配 5 窗），中值仍会被带偏 → 手册给「窗口长度应 ≥ 2 × 干扰持续采样数 + 1」的选型公式 |
| B7 | 与均值滤波的分工 | 手册对照表：稳态噪声用 `FB_DL_MovingAverage`（延迟小、平滑好）；脉冲干扰用本块（抗尖峰、有 1 拍延迟） |

**自检向量**

| # | 序列（窗口 5） | 期望 |
|---|---|---|
| V1 | 10,11,10,100,10 | 装满后 `fMedian = 10`（100 被剔除）；同序列均值 = 28.2 |
| V2 | 10,10,10（未满，窗口 5） | `nFilled = 3`、`fMedian = 10`、`eFilling` |
| V3 | 装 1,2,3,4,5 | `fMedian = 3` |
| V4 | 窗口设 4（偶数） | `nWinEff = 5`、`16#0001_0001` |
| V5 | V3 后把窗口改为 3 | 窗口重填（`nFilled` 归 0 再累）、`16#0001_0001`、中值跳变后稳定 |
| V6 | `bClear` 一拍 | `nFilled = 0`、`bValid = FALSE` |

**来源与去重**
- 来源标签：`lgf-measurement`（Measurement Operations 的「测量评估」族）、`oscat-basic`（`_ARRAY_MEDIAN` 提供了「中值 = 排序后取中」的行为定义；**OSCAT 用 `ADR/SIZEOF` 指针且会原地排序传入数组**，本库禁用指针、改用内部副本，接口与副作用均不同）。
- 去重：见 §1.4 第 11 行。

---

### 7.12 `FB_DL_SignalStatistics` ｜ DL_MathData ｜ 复杂度 M（7）｜ 来源 `lgf-math` + `oscat-basic`

**功能**：采样流实时统计分析器，窗口内输出**均值、最小、最大、峰峰值、样本方差、样本标准差、样本数**七元组。方差用**两遍法**（先求均值，再累加离差平方和），避免「平方和减均值平方」的灾难性抵消。用于 PID 整定前的噪声评估、SPC 过程能力、称重稳定性判定、振动烈度监视。

**接口契约**

```iecst
TYPE E_DL_StatState :
(
    eEmpty  := 0,    // 无样本 / No samples
    eFilling:= 10,   // 样本不足 / Filling
    eReady  := 20,   // 窗口已满，统计有效 / Window full, statistics valid
    eFault  := 99    // 参数非法或重置中 / Invalid parameter or reset
);
END_TYPE

FUNCTION_BLOCK FB_DL_SignalStatistics
VAR_INPUT
    fIn     : REAL;                        // 采样输入 [EU] / Sample input
    bSample : BOOL := TRUE;                // TRUE = 本拍采一个样本 / Sample this scan
    nWindow : INT := 32;                   // 窗口长度 2..64 / Window length
    bClear  : BOOL;                        // TRUE：清空窗口 / Clear window
END_VAR
VAR_OUTPUT
    fMean     : REAL;                      // 窗口均值 [EU] / Mean
    fMin      : REAL;                      // 窗口最小值 [EU] / Minimum
    fMax      : REAL;                      // 窗口最大值 [EU] / Maximum
    fRange    : REAL;                      // 峰峰值 fMax - fMin [EU] / Peak-to-peak
    fVariance : REAL;                      // 样本方差（n-1）[EU²] / Sample variance
    fStdDev   : REAL;                      // 样本标准差 [EU] / Sample standard deviation
    nCount    : INT;                       // 当前有效样本数 / Valid sample count
    bValid    : BOOL;                      // 至少有 1 个样本 / At least one sample
    bStatValid: BOOL;                      // 方差/标准差有效（n ≥ 2）/ Variance valid
    uErrorId  : UDINT;                     // 故障码 / Error code
    eState    : E_DL_StatState;            // 状态 / State
END_VAR
VAR
    afWindow  : ARRAY[0..63] OF REAL;      // 环形样本窗 / Circular window
    nWrite    : INT;                       // 写指针 / Write index
    nCountInt : INT;                       // 有效样本数 / Valid count
    nWinEff   : INT;                       // 生效窗口（钳位后）/ Effective window
    nLastWin  : INT;                       // 上拍窗口（R14）/ Previous window
    nI        : INT;                       // 索引 / Index
    nIdx      : INT;                       // 环形取数索引 / Ring index
    fSum      : LREAL;                     // 均值累加（宽类型）/ Sum for mean
    fMeanInt  : LREAL;                     // 均值中间量 / Mean intermediate
    fVarAcc   : LREAL;                     // 离差平方和 / Sum of squared deviations
    fTmp      : LREAL;                     // 单点离差 / Single deviation
    fTmp2     : LREAL;                     // 单点平方 / Squared deviation
    fMinInt   : REAL;                      // 增量最小值 / Incremental minimum
    fMaxInt   : REAL;                      // 增量最大值 / Incremental maximum
    nGuard    : INT;                       // 循环防死锁计数器 / Loop guard
    eStateInt : E_DL_StatState;            // 内部状态 / Internal state
END_VAR
VAR CONSTANT
    DL_STAT_WIN_MIN : INT := 2;            // 最小窗口 / Minimum window
    DL_STAT_WIN_MAX : INT := 64;           // 最大窗口（= 数组维度）/ Maximum window
    DL_STAT_CAP     : INT := 64;           // 容量 / Capacity
    DL_STAT_EPS     : LREAL := 1.0E-12;    // 方差零钳位容差 / Variance zero clamp
END_VAR
```

**语义与状态机**

| 状态 | 条件 | 输出 |
|---|---|---|
| `eEmpty` | `nCountInt = 0` | 全部统计量 0.0、`bValid := FALSE` |
| `eFilling` | `1 ≤ nCountInt < nWinEff` | 均值/极值有效，`bStatValid` 仅当 `nCountInt ≥ 2` |
| `eReady` | `nCountInt = nWinEff` | 全部有效 |
| `eFault` | 参数钳位/窗口变更当拍 | 参数已修正、继续运行 |

**算法要点**
1. 窗口规整：`nWindow < 2` → 2；`> 64` → 64；均置 `16#0001_0001`。
2. **R14**：`nWinEff <> nLastWin` → `nCountInt := 0`、`nWrite := 0`、`fMinInt/fMaxInt` 置哨兵、置 `16#0001_0001`。
3. 采样：写 `afWindow[nWrite]`、`nWrite := (nWrite+1) MOD DL_STAT_CAP`、`nCountInt := MIN(nCountInt+1, nWinEff)`；同时增量更新 `fMinInt/fMaxInt`（窗口滑动时若滑出的正是极值，**必须重算**极值——见 B3）。
4. 均值（第一遍）：`fSum := 0`，遍历最近 `nCountInt` 个样本累加（LREAL 累加，避免 REAL 漂移），`fMeanInt := fSum / nCountInt`。
5. 方差（第二遍）：`fVarAcc := 0`，再遍历一次累加 `(x - fMeanInt)²`；`fVariance := fVarAcc / (nCountInt - 1)`（`nCountInt < 2` 时 `fVariance := 0`、`bStatValid := FALSE`、`16#0002_0009`）。
6. 负方差钳位：`fVariance < 0` → 0（浮点舍入可能给出 -1e-20）。
7. `fStdDev := SQRT(fVariance)`；`fRange := fMaxInt - fMinInt`。
8. 每次遍历 `nGuard++`，超 `DL_STAT_CAP * 4` → `16#0001_0004` 并跳出（保留已算部分）。
9. 状态机 `CASE` + `ELSE → eFault + 16#0001_0005`；输出末尾统一赋值。

**故障码**

| 码 | 含义 | 类型 |
|---|---|---|
| `16#0002_0009` | 样本不足（N < 2，方差无定义） | 瞬时 |
| `16#0001_0001` | 窗口越界（已钳位）或窗口变更触发重填 | 瞬时 |
| `16#0001_0004` | 遍历保护触发 | 瞬时 |
| `16#0001_0006` | 样本 NaN/Inf（已跳过） | 瞬时 |
| `16#0001_0005` | 非法状态 | 锁存 |

**边界与防错**

| # | 边界 | 要求 |
|---|---|---|
| B1 | 方差公式 | **必须两遍法**。`E[x²] - E[x]²` 在均值远大于标准差时（如 1000.0 ± 0.01）会算出负方差或 0，是 SPC 场景的经典事故 |
| B2 | 除零 | `nCountInt < 2` 时不做除法，直接 0 + `0002_0009` |
| B3 | 极值滑出 | 窗口滑动时若滑出的样本恰为当前极值，增量维护会残留旧极值 → **每拍重算极值**（64 点代价可接受），或维护「极值计数」；本版选重算（简单、可验证） |
| B4 | 样本方差 vs 总体方差 | 明确用 **n-1**（样本方差），因为 PLC 拿到的是抽样；头注释写明「与 Excel `STDEV.S` 一致，不是 `STDEV.P`」 |
| B5 | 常数输入 | 全部样本相同 → 离差全 0 → 方差 0、标准差 0，**不是** NaN |
| B6 | 窗口变更 | 整窗重填（R14），避免新旧窗口混算 |
| B7 | 数值类型 | 累加与离差用 LREAL，输出转 REAL（接口保持 REAL 与现场 AI 卡一致）；头注释说明「内部 LREAL 仅为抗累加误差」 |
| B8 | 与 MovingAverage 的分工 | 均值可由 `FB_DL_MovingAverage` 以 O(1) 得到；本块贵在**方差/极值**。若只要均值，用前者（省扫描时间） |

**自检向量**

| # | 序列（窗口 8） | 期望 |
|---|---|---|
| V1 | 2,4,4,4,5,5,7,9 | `fMean = 5.0`、`fMin = 2`、`fMax = 9`、`fRange = 7`、`fVariance = 32/7 ≈ 4.5714`、`fStdDev ≈ 2.1381` |
| V2 | 单样本 42 | `fMean = 42`、`bStatValid = FALSE`、`fVariance = 0`、`16#0002_0009` |
| V3 | 8 个 3.0 | `fMean = 3.0`、`fVariance = 0.0`（非负、非 NaN） |
| V4 | 1000.0 与 1000.01 交替 8 个 | 方差 ≈ 2.857e-5（**远大于 0**，证明两遍法未抵消） |
| V5 | 窗口设 65 | `nWinEff = 64`、`16#0001_0001` |
| V6 | V1 后 `bClear` | `nCount = 0`、`bValid = FALSE` |

**来源与去重**
- 来源标签：`lgf-math`（Math Operations 明确含「均值标准差」）、`oscat-basic`（`ARRAY_SDV / ARRAY_VAR / ARRAY_SPR` 提供「标准差 / 方差 / 极差」的行为定义；OSCAT 为整数组一次算，本块为**流式窗口**，语义不同）。
- 去重：见 §1.4 第 12 行。

---

### 7.13 `FC_DL_QuickSortLReal` ｜ DL_MathData ｜ 复杂度 M（7）｜ 来源 `lgf-datahandling` + `oscat-basic`

**功能**：定长 LREAL 数组**原地**快速排序。**强制显式栈迭代实现，禁止递归**——ST 在部分平台（尤其嵌入式运行时与 InoProShop）递归深度受限或直接不支持，递归版在实验室跑得通、在现场 64 个元素的极端分区下栈溢出，属于「不可交付」的实现方式。用于分位数、去极值均值、报表排序、中值参考计算。

**接口契约**

```iecst
FUNCTION FC_DL_QuickSortLReal : BOOL
VAR_IN_OUT
    afData : ARRAY[0..63] OF LREAL;   // 待排序数组（原地修改）/ Array sorted in place
END_VAR
VAR_INPUT
    nCount     : INT;                 // 有效元素数 0..64 / Valid element count
    bAscending : BOOL := TRUE;        // TRUE = 升序，FALSE = 降序 / Ascending or descending
END_VAR
VAR_OUTPUT
    uCompareCount : UDINT;            // 比较次数（性能诊断，饱和）/ Comparison count
    uSwapCount    : UDINT;            // 交换次数（饱和）/ Swap count
    bUsedFallback : BOOL;             // TRUE = 触发了插入排序兜底 / Insertion-sort fallback used
    uErrorId      : UDINT;            // 故障码 / Error code
END_VAR
VAR
    anLoStack : ARRAY[0..15] OF INT;  // 显式栈：区间下界 / Explicit stack: low bounds
    anHiStack : ARRAY[0..15] OF INT;  // 显式栈：区间上界 / Explicit stack: high bounds
    nSp       : INT;                  // 栈指针（0 = 空）/ Stack pointer
    nLo       : INT;                  // 当前区间下界 / Current low
    nHi       : INT;                  // 当前区间上界 / Current high
    nI        : INT;                  // 分区扫描索引 / Partition scan index
    nJ        : INT;                  // 分区边界 / Partition boundary
    nPivotIdx : INT;                  // 枢轴索引 / Pivot index
    fPivot    : LREAL;                // 枢轴值 / Pivot value
    fTmp      : LREAL;                // 交换临时量 / Swap temp
    nMid      : INT;                  // 三点取中：中点 / Median-of-three middle
    nLeft     : INT;                  // 插入排序左端 / Insertion sort left
    nK        : INT;                  // 插入排序索引 / Insertion sort index
    nGuard    : INT;                  // 外层防死锁计数器 / Outer loop guard
    nGuard2   : INT;                  // 内层防死锁计数器 / Inner loop guard
    nIdx      : INT;                  // 预扫描索引 / Pre-scan index
    bHasNaN   : BOOL;                 // 预扫描发现 NaN/Inf / NaN detected in pre-scan
END_VAR
VAR CONSTANT
    DL_QS_CAP        : INT := 64;     // 数组容量 / Array capacity
    DL_QS_STACK_MAX  : INT := 16;     // 显式栈深度（2×log2(64)=12，留余量）/ Stack depth
    DL_QS_INSERT_TH  : INT := 8;      // 小于此长度改用插入排序 / Insertion-sort threshold
    DL_QS_GUARD      : INT := 4096;   // 外层循环防死锁上限 / Outer loop guard
    DL_QS_GUARD2     : INT := 1024;   // 内层循环防死锁上限 / Inner loop guard
END_VAR
```

**算法要点（显式栈迭代，逐条照做）**
1. 预置：`uCompareCount := 0; uSwapCount := 0; bUsedFallback := FALSE; uErrorId := 0`。
2. `nCount` 处理：`< 0` → `16#0001_0001`、返回 FALSE；`> 64` → 钳到 64 + `16#0001_0001`；`≤ 1` → 直接返回 TRUE（已有序）。
3. **NaN 预扫描**（必须先做，否则分区行为未定义）：遍历 `0..nCount-1`，任一元素不等于自身（`f <> f` 是 NaN 的唯一 IEC 可移植判据）或绝对值超 1e300 → `16#0001_0006`、返回 FALSE，**数组保持原样**（绝不把半个乱序数组留给调用方）。
4. `nSp := 0`；压入首区间 `anLoStack[0] := 0`、`anHiStack[0] := nCount-1`、`nSp := 1`。
5. **主循环**：`WHILE nSp > 0`（`nGuard++`，超 `DL_QS_GUARD` → `16#0001_0004`、退出并返回 FALSE）：
   - 弹栈：`nSp--`、`nLo := anLoStack[nSp]`、`nHi := anHiStack[nSp]`。
   - 区间长度 `nHi - nLo + 1 < DL_QS_INSERT_TH` → 对该区间做**插入排序**并 `CONTINUE`（小数组上插入排序更快且无分区退化风险）。
   - 三点取中选枢轴：比较 `afData[nLo] / afData[(nLo+nHi)/2] / afData[nHi]`，取中值对应的**值**装入 `fPivot`（不必交换到固定位置，Lomuto 分区用值即可）。
   - Lomuto 分区：`nJ := nLo`；`FOR nI := nLo TO nHi-1`（`nGuard2++`，超限跳出 + `16#0001_0004`）：若 `afData[nI] < fPivot`（升序）或 `> fPivot`（降序）则交换 `afData[nI]` 与 `afData[nJ]`、`nJ++`；每比较一次 `uCompareCount++`（饱和）。
   - 交换枢轴到位：交换 `afData[nJ]` 与 `afData[nHi]`、`uSwapCount++`。
   - **入栈两个子区间（先压大区间、后压小区间）**：这是显式栈的关键——先压大后压小，使栈深上界为 `O(log n)`；若先压小，最坏情况栈深 = n（64 > 16 直接溢出）。压栈前判 `nSp < DL_QS_STACK_MAX`；溢出 → 置 `bUsedFallback := TRUE`，对**该子区间**改走插入排序（不丢数据、不中断排序）。
6. 插入排序兜底：对 `[nLeft..nHi]` 标准插入排序，`nK` 从 `nLeft+1` 起，内层带 `nGuard2` 计数。
7. 返回 TRUE（「已排序」语义由布尔返回值承载，不另设输出位）。

**故障码**

| 码 | 含义 | 类型 |
|---|---|---|
| `16#0001_0001` | `nCount` 越界（已钳位） | 瞬时 |
| `16#0001_0006` | 数组含 NaN/Inf（未排序，原样返回） | 瞬时 |
| `16#0001_0004` | 循环保护触发（排序未完成） | 瞬时 |
| `16#0001_0007` | 显式栈溢出（已转插入排序兜底，`bUsedFallback = TRUE`） | 瞬时 |

**边界与防错（本轮重点，逐条对照 RED LINE）**

| # | 边界 | 要求 |
|---|---|---|
| B1 | **禁止递归** | 全文不得出现对 `FC_DL_QuickSortLReal` 的自调用。头注释写明理由：「ST 递归在部分平台栈深受限或不可用，64 元素的最坏分区（全等值）递归深度可达 64」 |
| B2 | **栈深上界** | 「先压大、后压小区间」是栈深 `O(log n)` 的**唯一保证**；顺序写反会让全等值数组把 16 深栈打爆。手册把这条写成加粗警示 |
| B3 | 全等值数组 | Lomuto 分区把全等值全部划到一侧 → 深度退化。必须用「全 64 个相同值」向量验证：**能终止、结果有序、`bUsedFallback` 可能为 TRUE**（这是可接受的降级，不是缺陷） |
| B4 | NaN | 先预扫描拒绝，**不得**依赖「NaN 比较为 FALSE」让分区自己乱掉——那会得到半有序数组且无任何报错 |
| B5 | 失败时数组状态 | 循环保护触发（`0001_0004`）时数组可能部分有序：头注释必须披露「返回 FALSE 时数组内容未定义，调用方应丢弃本轮结果」，禁止伪装成功 |
| B6 | 升/降序 | 单一比较方向由 `bAscending` 决定，**禁止**排完再反转（多一遍 O(n) 且丢失稳定性语义） |
| B7 | 稳定性 | 快速排序**不稳定**；头注释写明「相同值的相对次序不保证」，需要稳定排序时改用插入排序版（后续扩产） |
| B8 | 计数饱和 | `uCompareCount / uSwapCount` 达 `16#FFFF_FFFE` 后停增，不回绕 |
| B9 | 索引边界 | 所有下标访问前判 `>= 0 AND < nCount`；分区内 `nI ≤ nHi-1`、`nJ ≤ nHi` 由循环条件保证，仍加双检（R4） |

**自检向量（R12/R13）**

| # | 输入 | 期望 |
|---|---|---|
| V1 | `{3,1,2}`, n=3, 升序 | `{1,2,3}`、返回 TRUE |
| V2 | `{5,4,3,2,1}`, n=5, 降序 | `{5,4,3,2,1}`（不变）、返回 TRUE |
| V3 | 64 个 `7.0` | 返回 TRUE、全为 7.0、**有限步内终止**（`bUsedFallback` 允许 TRUE） |
| V4 | n=1 / n=0 | 返回 TRUE、数组不变、计数 0 |
| V5 | `{1.0, NaN, 3.0}` | 返回 FALSE、`16#0001_0006`、**数组仍为原顺序** |
| V6 | 已升序 64 个随机值 | 返回 TRUE、有序、`uCompareCount` 在 `O(n log n)` 量级（验证三点取中生效，未退化为 O(n²)） |
| V7 | 32 个随机值排序后，与「冒泡排序参考实现」结果逐元素比对 | 完全一致（手册须记录该比对方法，R12） |

**来源与去重**
- 来源标签：`lgf-datahandling`（LGF 排序族为 `LGF_ShellSort_DInt/_LReal/_UDInt`，按类型分族、FB 形态；本库按「原子化」原则选 FC 且换用快排+显式栈）、`oscat-basic`（`_ARRAY_SORT / SORT_1D` 提供「原地排序」的行为定义；OSCAT 用指针入参，本库用 `VAR_IN_OUT`）。
- **算法选择理由**：LGF 用希尔排序（O(n log²n)、无最坏退化、实现短）。本库选快排是因为**它必须承载「显式栈替代递归」这一范式**（万级库里会有大量分治算法：最近点对、凸包、KD 树建树），需要一个可复制的模板。希尔排序无法沉淀该范式。
- 去重：见 §1.4 第 13 行。

---

### 7.14 `FC_DL_HexStringToBytes` ｜ DL_MathData ｜ 复杂度 L（4）｜ 来源 `lgf-converter` + `modbus-ascii`

**功能**：十六进制 ASCII 字符串 → 字节数组的**严格**解析。`"1A2B3C"` → `16#1A, 16#2B, 16#3C`；可选剥离 Modbus ASCII 帧的 `':'` 与 CR/LF。用于扫码枪十六进制输出、Modbus ASCII 收帧、RFID 标签 ID 解析、固件分段校验的前置解码。

**接口契约**

```iecst
FUNCTION FC_DL_HexStringToBytes : INT
VAR_IN_OUT
    aabyOut : ARRAY[0..63] OF BYTE;   // 输出字节缓冲（失败时不写入）/ Output buffer, untouched on failure
END_VAR
VAR_INPUT
    sHex          : STRING(255);      // 十六进制字符串 / Hex string
    bStripFraming : BOOL := FALSE;    // TRUE：剥离首 ':' 与尾部 CR/LF / Strip Modbus ASCII framing
    nMaxBytes     : INT := 64;        // 允许写入的最大字节数 1..64 / Max bytes to write
END_VAR
VAR_OUTPUT
    nInvalidPos : INT;                // 首个非法字符位置（1 起），0 = 无 / First invalid char position, 1-based
    uErrorId    : UDINT;              // 故障码 / Error code
END_VAR
VAR
    nLen      : INT;                  // 原文长度 / Source length
    nStart    : INT;                  // 有效起始位置 / Effective start index
    nEnd      : INT;                  // 有效结束位置 / Effective end index
    nHexLen   : INT;                  // 有效十六进制字符数 / Effective hex char count
    nBytes    : INT;                  // 待写字节数 / Bytes to write
    nI        : INT;                  // 字符索引 / Char index
    nHiNib    : INT;                  // 高半字节 / High nibble
    nLoNib    : INT;                  // 低半字节 / Low nibble
    nNib      : INT;                  // 单字符转 nibble 结果，-1 = 非法 / Nibble value, -1 invalid
    bAllValid : BOOL;                 // 全字符合法标志 / All-chars-valid flag
END_VAR
VAR CONSTANT
    DL_HX_BUF_MAX  : INT := 64;       // 输出缓冲上限 / Output buffer limit
    DL_HX_PAIR     : INT := 2;        // 每字节字符数 / Chars per byte
    DL_HX_COLON    : BYTE := 16#3A;   // ':' / Frame start
    DL_HX_CR       : BYTE := 16#0D;   // CR
    DL_HX_LF       : BYTE := 16#0A;   // LF
    DL_HX_ASCII0   : BYTE := 16#30;   // '0'
    DL_HX_ASCII9   : BYTE := 16#39;   // '9'
    DL_HX_ASCIIAU  : BYTE := 16#41;   // 'A'
    DL_HX_ASCIIFU  : BYTE := 16#46;   // 'F'
    DL_HX_ASCIIAL  : BYTE := 16#61;   // 'a'
    DL_HX_ASCIIFL  : BYTE := 16#66;   // 'f'
    DL_HX_NIB_SHIFT: INT  := 4;       // 高半字节移位 / Nibble shift
END_VAR
```

**算法要点（严格模式：先全量校验，再一次性写入）**
1. 预置：`nInvalidPos := 0; uErrorId := 0; nBytes := 0`。
2. `nMaxBytes` 钳位：`< 1` → 1，`> 64` → 64，置 `16#0001_0001`。
3. `nLen := LEN(sHex)`；`nStart := 1`；`nEnd := nLen`（IEC 字符串 1 起）。
4. **剥离帧**（`bStripFraming = TRUE`）：首字符为 `':'` → `nStart := 2`；尾部为 CR 和/或 LF → `nEnd` 相应减 1 或 2（先判 LF 再判 CR，顺序固定）。
5. `nHexLen := nEnd - nStart + 1`；`nHexLen < 0` → 0；**空串 → 返回 0、无故障**（空报文不是格式错误）。
6. 奇数长度：`nHexLen MOD DL_HX_PAIR <> 0` → `16#0002_000A`、`nInvalidPos := nStart + nHexLen`、返回 -1。
7. **第一遍：全字符合法性**。逐字符取 `BYTE`，转 nibble（`'0'..'9'` → 0..9；`'A'..'F'`、`'a'..'f'` → 10..15；其他 → -1）。任一非法 → `16#0002_000A`、`nInvalidPos := 该字符位置`、返回 -1。**此遍不写输出**。
8. 容量检查：`nBytes := nHexLen / 2`；`nBytes > nMaxBytes` → `16#0001_0009`、返回 -1（**整帧拒绝**，不写半截——半截字节流比没有更危险）。
9. **第二遍：写入**。`FOR nI := 0 TO nBytes-1`：`nHiNib := 位置 nStart + 2*nI` 的 nibble；`nLoNib := 下一字符` nibble；`aabyOut[nI] := INT_TO_BYTE(SHL(nHiNib, DL_HX_NIB_SHIFT) OR nLoNib)`。
10. 返回 `nBytes`。

**故障码**

| 码 | 含义 | 类型 |
|---|---|---|
| `16#0002_000A` | 非 hex 字符或奇数长度 | 瞬时 |
| `16#0001_0009` | 输出缓冲不足（整帧拒绝，未写入） | 瞬时 |
| `16#0001_0001` | `nMaxBytes` 越界（已钳位） | 瞬时 |

**边界与防错**

| # | 边界 | 要求 |
|---|---|---|
| B1 | **先校验后写入** | 两遍扫描。任何失败路径**不得**留下部分写入的缓冲（调用方可能直接拿去发报文） |
| B2 | 严格模式 | **不跳过空格、不跳过 `0x` 前缀、不容忍内嵌分隔符**（`"1A 2B"` 判非法）。宽容解析会把组帧错误吃进数据层，现场表现为「校验通过但数据错」 |
| B3 | 大小写 | `a..f` 与 `A..F` 同等接受（现场两种都常见），不因此报错 |
| B4 | 奇数长度 | 判非法而非「末尾补 0」——补 0 会凭空造出一个字节 |
| B5 | 帧剥离 | 只剥 `':'` 与尾部 CR/LF，**不剥空格**；`bStripFraming = FALSE` 时传 `":0103..."` 必然因 `':'` 非法而报错（这是正确行为） |
| B6 | `STRING` 长度 | 形参显式 `STRING(255)`；头注释警示「CODESYS 默认 `STRING` 仅 80 字节，不显式声明会被静默截断」 |
| B7 | 空串 | 返回 0、`uErrorId = 0`（空报文合法，由上层判长度） |
| B8 | 输出缓冲 | 固定 64，`aabyOut` 维度必须与 `DL_HX_BUF_MAX` 一致；写入前判 `nBytes <= nMaxBytes AND nBytes <= DL_HX_BUF_MAX` |
| B9 | 位置语义 | `nInvalidPos` 为**原文 1 起**的字符位置（含被剥离的 `':'`，便于现场在报文里直接数），头注释写明 |

**自检向量**

| # | 输入 | 期望 |
|---|---|---|
| V1 | `"1A2B3C"`，`nMaxBytes = 64` | 返回 3；`[16#1A, 16#2B, 16#3C]` |
| V2 | `"1a2b"` | 返回 2；`[16#1A, 16#2B]` |
| V3 | `":010300000001FB"` + CRLF，`bStripFraming = TRUE` | 返回 7；`[01,03,00,00,00,01,FB]`（与 §7.9 V1 闭环） |
| V4 | `"1A2B3"`（奇数） | 返回 -1；`16#0002_000A`；`nInvalidPos = 6`；缓冲不变 |
| V5 | `"1G"` | 返回 -1；`16#0002_000A`；`nInvalidPos = 2` |
| V6 | 130 字符（65 字节）`nMaxBytes = 64` | 返回 -1；`16#0001_0009`；缓冲不变 |
| V7 | `""` | 返回 0；`uErrorId = 0` |

**来源与去重**
- 来源标签：`lgf-converter`（Converter Operations 的「字符串↔数值」族，提供「按类型分函数、单一职责」的组织方式）、`modbus-ascii`（ASCII 帧剥离的帧定义）。
- 去重：见 §1.4 第 14 行。与 `FC_DL_StringSplit` 的分工：后者按分隔符切字段（文本结构），本函数做 nibble 数值解码（字符→字节）。

---

## 8 源矩阵取源映射表（源 → 组 → 组件）

### 8.1 逐组件取源映射（本轮 14 项全覆盖）

| 组件 | 一级源（T2/T1） | 二级源（规范/协议） | 借鉴的**分类与参数域** | 明确**未借鉴**的部分 |
|---|---|---|---|---|
| TwoHandSafety | T2 标准线 `iec60204` | ISO 13851:2019 Type IIIC、IEC 60204-1 | 500 ms 同步窗、100 ms 释放差、释放后重启、上电禁止启动、单侧卡死须检出 | 无代码可借鉴（标准为文本）；继电器内部时序逻辑未接触 |
| InterlockMatrix | T2 `isa18-2` + `lgf-bitlogic` | — | 首出/首因方法论；位图+掩码的接口组织 | LGF 的位逻辑函数实现；`LBP_Intlk8` 的块结构（8 路改为 16 路，已留档） |
| RedundantSwitch | T2 `lgf-comparator` | — | 公差窗口/区间判断的参数域（限值 + 延时确认） | `LGF_IsValueInLimits` 的实现 |
| DutyStandbyRotation | T2 `lbp-basic-process` | — | `LBP_Aggr8` 的「8 台聚合体」粒度、`cmdXXX/indXXX` 命令-反馈分离思想 | LBP 任何源码（闭源，未获取） |
| MultiPointLinear | T2 `lgf-math` | `LBP_Polygon`（8 点插值粒度） | 折线表 = X/Y 双数组 + 点数的参数域形态 | `LGF_ScaleLinear` 与 `LBP_Polygon` 的实现；二分查找为本库自选 |
| PolygonArea | T2 `lgf-math` | — | 平面几何族的分类位置 | 无实现可借鉴（LGF 无多边形面积函数） |
| LineIntersection | T2 `lgf-math` | — | 同上 | 同上 |
| Crc32Ethernet | **T1 `oscat-network`** | IEEE 802.3 / CRC 参数目录 | 校验函数按协议分族、独立成 FC 的组织方式 | OSCAT 的 `ADR()/SIZEOF()` 指针入参与查表实现（本库禁指针，改 `VAR_IN_OUT` + 逐位算法） |
| LrcChecksum | **T1 `oscat-network`** | Modbus 应用协议规范（ASCII 模式） | 同上 | 同上 |
| LifoStack | T2 `lgf-datahandling` | — | FIFO/LIFO 拆成两个独立 FB、带「满/空/长度」状态位的粒度 | `LGF_LIFO` 的实现与 DB 结构 |
| MedianFilter | T2 `lgf-measurement` | T1 `oscat-basic`（`_ARRAY_MEDIAN` 行为定义） | 窗口评估的参数域；「中值 = 排序后取中」的行为语义 | OSCAT 的指针入参与「原地排序传入数组」的副作用（本库排序副本） |
| SignalStatistics | T2 `lgf-math` | T1 `oscat-basic`（`ARRAY_SDV/VAR/SPR` 行为定义） | 「均值/标准差/极差」的输出集合 | OSCAT 的整数组一次计算（本库为流式窗口）；两遍法为本库自选 |
| QuickSortLReal | T2 `lgf-datahandling` | T1 `oscat-basic`（`_ARRAY_SORT` 行为定义） | 排序族的组织；「原地排序」语义 | LGF 的希尔排序与 OSCAT 的指针排序；本库用快排+显式栈（为了沉淀禁递归范式） |
| HexStringToBytes | T2 `lgf-converter` | Modbus ASCII 帧定义 | 「字符串↔数值」按类型分函数的粒度 | `LGF_StringToInt` 等实现；本库为严格两遍校验 |

### 8.2 组维度统计

| LGF 组 | 本轮组件数 | 组容量（矩阵 §2 预估） | 本轮挖出比例 | 结论 |
|---|---|---|---|---|
| Math Operations | 4（MultiPointLinear、PolygonArea、LineIntersection、SignalStatistics） | 25–30 | ~14% | 已打开，仅取「插值 + 几何 + 统计」三条线 |
| Data Handling | 2（LifoStack、QuickSortLReal） | 20–25 | ~9% | 已打开，FIFO 已在 R2 由 RingBuffer 覆盖 |
| Converter Operations | 1（HexStringToBytes） | 15–20 | ~6% | 刚开门，字节序族 R2 已覆盖 2 项 |
| Measurement Operations | 1（MedianFilter） | 12–15 | ~8% | 已打开，后续可扩「峰值检测 / 回归线」 |
| Comparator Operations | 1（RedundantSwitch） | 8–10 | ~12% | 已打开 |
| Bit Logic Operations | 0.5（InterlockMatrix 借用位图组织） | 18–24 | ~3% | 实质仍未开采（R1 的 BitGet/Set/Count 属 T3 通用位操作，非 LGF 组） |
| Date and Timer / Counter / Signal Generators / Technology | 0 | 45–57 | 0% | **未打开**，是 R4+ 的主战场 |

**判断**：本轮把 LGF 的「组打开率」从 0/10 推到 5/10（含借用计 5.5），但**组挖尽率仍为 0**。下一轮若继续在 Math/DataHandling 里横向重载，边际收益会快速下降；更高价值的是**打开完全未动的四组**（Timer 的多段定时、Counter 的饱和/回绕、Signal Generators、Technology 的限速/斜坡），因为它们对应 `DL_Algo` 的核心件。

### 8.3 `SOURCE_HUNTING_MATRIX.md` 第 5 节台账回写建议（**本轮不写文件，交阶段五执行**）

| 源 | 现状态 | 建议状态 | 已产出组件（本轮新增） | 备注 |
|---|---|---|---|---|
| T2-1 LGF · Math | ☐ | **◐** | MultiPointLinear、PolygonArea、LineIntersection、SignalStatistics | 首批打开；几何线为本库独有扩展 |
| T2-1 LGF · Data Handling | ☐ | **◐** | LifoStack、QuickSortLReal | FIFO 已由 R2 RingBuffer 覆盖 |
| T2-1 LGF · Converter | ☐ | **◐** | HexStringToBytes | 仅取字符串→数值；时间/GPS/温度族未动 |
| T2-1 LGF · Measurement | ☐ | **◐** | MedianFilter | 峰值检测/回归线待挖 |
| T2-1 LGF · Comparator | ☐ | **◐** | RedundantSwitch | 公差窗口族 |
| T2-1 LGF · Bit Logic | ☐ | **◐** | InterlockMatrix（位图组织） | 实质未开采，建议下轮正面进攻 |
| T2-2 LBP 基础工艺 | ☐ | **◐** | DutyStandbyRotation（`LBP_Aggr8` 粒度）、MultiPointLinear（`LBP_Polygon` 粒度） | 闭源，仅分类与参数域 |
| T2-8 ISA-88/18.2/NE107 | ☐ | **◐** | InterlockMatrix（首因） | AlarmManager（R2）亦属此行但台账未记，建议一并补记 |
| **新增行** T2-10 IEC 60204-1 / ISO 13851 | — | **◐（新建）** | TwoHandSafety | 建议新增一行，后续 LightCurtain/GuardLockDoor 继续挂此行 |
| T1-1 OSCAT Basic | ◐ | ◐（加深） | MedianFilter、SignalStatistics、QuickSortLReal 的**行为定义**参考 | 未复制代码 |
| T1-3 OSCAT Network | ◐ | ◐（加深） | Crc32Ethernet、LrcChecksum | 同上 |

---

## 9 下游交付验收清单（编码 Agent 必须逐条自证）

### 9.1 文件级

- [ ] 14 个文件，文件名 = POU 名，落在 `DL_Base\`（4 个）与 `DL_MathData\`（10 个）
- [ ] 头注释 7 项齐全（名称/子库/版本/兼容性/功能/溯源/修订），`v1.0.0`
- [ ] 每个枚举与所属 POU 同文件时，头注释「本文件内含」注明
- [ ] `function_tags` 含本文件 §3 表指定的**来源标签**（小写连写）

### 9.2 红线级（任一不过 → 打回）

- [ ] R1/R2：全文零 `GVL` / `VAR_EXTERNAL` / 绝对地址
- [ ] R3：零 `POINTER TO` / `REFERENCE TO` / `ADR` / `SIZEOF` / 厂商类型；零隐式转换
- [ ] R4：每处除法前判分母；每处数组下标双检；浮点判等带容差；每个 `WHILE/FOR` 有计数器
- [ ] R5/R9：每个变量、每个枚举项同行「中文 + 英文 + 单位」
- [ ] R6：4 个 FB 全部 `ENUM` + `CASE` + `ELSE`；10 个 FC 标 N/A 并说明「无状态机」
- [ ] R7：`TON/R_TRIG/F_TRIG` 实例全部位于主体最前部无条件区
- [ ] R8：零裸数值（阈值/上限/容量全部常量化）
- [ ] R10：注释不书写被禁符号原文（用「绝对地址」「指针」等自然语言）
- [ ] R11：任何偏离本规格（如 InterlockMatrix 16 路 vs LBP 8 路）在头注释留档「收窄/扩展 + 依据 + 理由」
- [ ] R12/R13：§7 各节「自检向量」逐条复算，手册记录复算过程；时序类（TwoHandSafety / RedundantSwitch / DutyStandbyRotation）必须逐扫描推演
- [ ] R14：MedianFilter / SignalStatistics 窗口变更、DutyStandbyRotation 台数变更，均整窗/整组重排
- [ ] R15：锁存码与瞬时码按 §4.2 表分类，锁存码只由复位路径清除

### 9.3 契约级

- [ ] 引脚名、类型、默认值、单位与本文件逐字一致
- [ ] 4 个 FB 的输出在主体末尾**单点赋值**（分支内只改状态）
- [ ] 14 个组件零内部依赖（D-R3-03）
- [ ] `TwoHandSafety` 的合规披露段**原文保留**，不得删改
- [ ] `Crc32Ethernet` 的四条自检向量（含链式 V4）全部通过才可入库

### 9.4 文档级（同批完成，不得事后补）

- [ ] `DL_Base\VERSION.md`、`DL_MathData\VERSION.md` 组件清单 20/20
- [ ] `MANUAL_DL_Base.md` / `MANUAL_DL_MathData.md` 各新增章节（引脚表 + 故障码表 + 调用示例 + 联调要点）
- [ ] `CHANGELOG.md` / `README.md` / `LIBRARY_MANUAL.md` 三方数量一致（40）
- [ ] `INDEX_REGISTRY.json` 40 条（**阶段五执行，本阶段禁止**）
- [ ] `_AI_Training_Dataset\daoli_st_sft_dataset.jsonl` 40 条（阶段五执行，本阶段禁止）
- [ ] `ROADMAP.md` 勾选 14 项（**阶段五执行，本阶段禁止**）

---

## 10 风险与决策记录

### 10.1 决策清单

| 编号 | 决策 | 理由 |
|---|---|---|
| D-R3-01 | `QuickSortLReal` **强制显式栈迭代**，明文禁止递归 | ST 递归在 CODESYS/TwinCAT/InoProShop 的栈深与可用性不一致；最坏分区（全等值 64 元素）递归深度可达 64，属于「实验室过、现场炸」的典型。显式栈 + 先压大后压小把栈深锁在 O(log n) ≤ 12，容量取 16 |
| D-R3-02 | 故障码新开 `16#0002_xxxx` 族，`16#0001_xxxx` 只复用不扩义 | `0001` 族已被 R1/R2 的 10 个语义占满（参数/除零/符号/循环/状态/NaN/溢出/时间/满/空），继续往里塞会让同码多义，HMI 无法给出单一处置建议 |
| D-R3-03 | 本轮 14 项**零内部依赖** | Level 0 必须支持任意子集导出；OSCAT 式「一装一库」在 POU 受限平台上是硬伤（检索 5 已证）。零依赖是产品特性 |
| D-R3-04 | `InterlockMatrix` 取 16 路，**刻意偏离** `LBP_Intlk8` 的 8 路 | 位图输出须与既有 16 位报警字（`FC_DL_PackBitsToWord` / `AlarmManager`）同宽，否则现场要拼两次字。偏离已按 R11 留档 |
| D-R3-05 | `DutyStandbyRotation` **不复用** `FB_DL_RuntimeMeter` | RuntimeMeter 面向「时/分/秒呈现 + 保养预警」，本块需要 8 路秒级累加器参与排序；复用会引入二次换算与 8 实例数组，维护成本高于 20 行累加 |
| D-R3-06 | `TwoHandSafety` 明确**不是安全认证块**，合规披露段强制保留 | ISO 13851 Type IIIC 要求安全继电器/F-CPU；标准 PLC 普通输出存在短路静默失效。若不披露，OEM 会拿它当唯一安全措施，这是本库最不能承担的风险 |
| D-R3-07 | `RedundantSwitch` 偏差超限时**默认不猜**（`eHoldLast`） | 两个传感器矛盾时，程序没有资格判定谁对；猜错的代价是「用坏传感器继续闭环」。要猜必须显式改策略并留档 |
| D-R3-08 | `PolygonArea` 明确披露**自交多边形代数面积**问题，不做自交检测 | 自交检测是 O(n²) 且在 32 点内仍可做，但会把单函数复杂度从 5 推到 8；视觉轮廓去重与排序是调用方既有能力，写在手册比塞进块里更合理 |
| D-R3-09 | `Crc32Ethernet` 首版逐位、不建 256 项表 | 零 RAM 开销、可逐位复算（R12 友好）；性能需求走「性能变体」另立组件，不在本块加 `MODE` |
| D-R3-10 | `MedianFilter` 偶数窗口**强制奇数**，不取中间两值平均 | 取平均等于把中值退化回均值，尖峰重新渗入——那就失去了选它的理由 |

### 10.2 风险清单

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| 1 | 14 项中 4 个 FB 含时序语义（TwoHandSafety / RedundantSwitch / DutyStandbyRotation / InterlockMatrix 的延时确认），R13 未脚本化 | 语义错但文本合规（R2 三个缺陷全部此类） | `_Tests/sim/` 必须在本轮编码**之前**建好三个桩（双手、冗余、轮值），否则不得入库 |
| 2 | `TwoHandSafety` 被误当安全功能 | **人身安全** | 合规披露段 + 手册首段加粗 + 索引 `function_tags` 不出现 `safety-certified` |
| 3 | 单波 14 项 × 4 个 H/M 级 FB，编码侧赶工 | 引脚漂移、边界漏 | 按 §6 分 4 批、3 并行；A/B/C 必须先过自检向量才开 D |
| 4 | 200/日 目标倒逼降标准 | 库质量崩 | §2.3 三条爬坡约束写死：红线不降、每波至少 1 个 T2 组、每波 ≥2 个 H 级 |
| 5 | LGF 组「打开但未挖尽」造成虚假覆盖率 | 产品判断失真 | 台账同时记「组打开率」与「组挖尽率」，后者单独列出（当前 0%） |

### 10.3 拟新增规则（提交 `AGENT_EVOLUTION_LOG.md`，本轮不写该文件）

| 编号 | 规则 | 来源 |
|---|---|---|
| **R16** | Level 0 算法类**禁用递归**，分治一律显式栈；栈深上界须在头注释给出推导 | 本轮 QuickSortLReal（D-R3-01） |
| **R17** | 凡引用外部标准 check 值（CRC/LRC/哈希），必须**双源核对**并在手册记录两个来源；单源自证视为未验证 | 本轮 CRC32/LRC 双源（crccalc + testbench；otomasyonavm + modbus.cn） |
| **R18** | 涉及人身安全的组件，头注释必须含「非认证 / 认证边界」披露段，且 `function_tags` 不得含暗示认证的词 | 本轮 TwoHandSafety（D-R3-06） |

---

## 11 下一轮前置输入（写给产品经理自己）

1. **P0｜Phase 1 收口校验**：R3 入库后必须做一次全库 40 项交叉核对（`README` / `LIBRARY_MANUAL` / 各 `VERSION.md` / `INDEX_REGISTRY` / JSONL 五方数量与名称一致），任何漂移在进入 Level 1 前修完。Level 0 是地基，地基带裂缝不能往上盖。
2. **P0｜`_Tests/sim/` 必须落地**：本轮 4 个时序 FB 是最后一批「可以靠人眼推演」的组件；进入 `DL_Algo`（PID、滤波、斜坡）后，控制律错误表现为「能跑但稳态有偏」，人眼完全看不见。脚本化是 Level 1 的准入条件，不是优化项。
3. **P1｜`DL_Algo` 起手式**：`FB_DL_PidController`（含抗积分饱和、微分先行、手自动无扰）+ `FB_DL_LowPassFilter` + `FB_DL_RampGenerator` 三件套先行，它们是 `DL_Device` / `DL_Process` 的最高频被依赖项。源：LGF Technology（限速/斜坡，未打开）+ LBP `LBP_CtrlPID`（参数域）+ T2-5 Mod_PID（已 ◐）。
4. **P1｜打开 LGF 剩余四组**：Date and Timer、Counter、Signal Generators、Technology。这四组共 45~57 项容量，且与 `DL_Algo` 高度重叠，是最省力的扩产口。
5. **P2｜安全族纵深**：`TwoHandSafety` 打开了 IEC 60204 这条线，`DL_Device` 的 `GuardLockDoor` / `SafetyLightCurtain` 应挂同一标签族，形成「安全逻辑骨架」产品线，而不是散落成三个孤立块。
6. **P2｜三平台实测编译**：当前全部为静态语法级合规。40 项收口是把工程导入 CODESYS V3.5 SP19 / TwinCAT 3.1.4024 / InoProShop 各编译一次的最佳时点（数量可控、依赖为零）。

---

*Round 03 ｜ 2026-11-14 23:40 ｜ 道莅工控代码库产品总监*
*本轮交付：阶段一盘点去重 + 阶段二取源与轮次计划。零 `.st`、零索引改动、零 JSONL 改动、零 ROADMAP 勾选。*