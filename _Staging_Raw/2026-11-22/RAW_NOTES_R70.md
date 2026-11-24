# RAW_NOTES_R70 — 选题来源留痕（零检索轮，WebSearch 0 次）

> 原则：只借骨不抄肉。T2 闭源族（Siemens LGF / Rockwell AOI / ISA / PackML）**只借功能分类体系、参数域定义、组内组件粒度**；实现、状态机、判据、码位、阈值 100% clean-room 独立编写，零代码行复制、零注释原文搬运。
> 本轮所有「源」均来自 `C:\Library\SOURCE_HUNTING_MATRIX.md` 与既有 `RAW_NOTES_*`（矩阵行号/组名可回溯），未发起任何网络检索。
> 码位（`uErrorId` 段）**不在规划轮指定**：由编码轮按各子库现行游标续取，避免规划期猜码撞段（R192 故障码单轨）。

---

## 1. 逐件来源留痕

### N1 `FB_DL_EncoderBatteryWatch` ｜ DL_Device ｜ 批 1 ｜ 低

- **来源标签**：`self-std`（设备本体健康族第三批）
- **源（矩阵行）**：`SOURCE_HUNTING_MATRIX.md` §5 台账「T2-1 LGF · Measurement ◐」不取本文；取自矩阵 §2 组映射「LGF 组内『设备寿命/维护请求』语义」+ 本库 R13 起「设备本体退化而非工艺偏差」立项主线（§19.6 扩容统计主线④）。
- **许可证**：道莅原创 MIT（`origin.mode=internal`）。
- **提取点**：无外部代码借鉴；仅沿用本库 NE107 语言（`E_DL_Ne107Status`：电池低 = `eMaintenanceReq`，掉电事件 = `eCheckFunction`）与既有 `FB_DL_RuntimeMeter` 的「累计 + 预警门限」组织方式。
- **clean-room 声明**：状态机与判据全自研。工程依据为公共常识（多圈绝对值编码器依赖电池保持多圈计数，电池失效即丢失多圈基准），不参考任何具体厂商手册文本。
- **复用约束**：只调用 Level 0 能力，不内联实现；不重复声明 NE107 枚举（唯一属主 `I_DL_DeviceHealth` 同文件）。

### N2 `FB_DL_AlarmSuppressByDesign` ｜ DL_Base ｜ 批 1 ｜ 中低

- **来源标签**：`isa-18.2`（T2-8 ISA-88 / ISA-18.2 / NE107 ◐ 行，矩阵明记「报警管理族本体待挖」）
- **源（矩阵行）**：`SOURCE_HUNTING_MATRIX.md` §5 台账第 `T2-8 ISA-88 / ISA-18.2 / NE107` 行。
- **许可证**：ISA-18.2 为**公开标准条款**（标准文本本身有版权，只采用公开条款语义：alarm suppression / designed suppression / shelving / flood 的**语义区分**，不复制条款原文表述，不声明「符合 ISA-18.2 认证」）。
- **提取点**：① 「设计抑制 ≠ 人工搁置 ≠ 泛滥限流」三态语义区分（本库分别由本件 / `AlarmShelving` / `AlarmFloodLimiter` 承载，形成三件分工，防同义撞名）；② 抑制必须**自动恢复**（越窗即解除，不依赖人工），这是 ISA-18.2 对 design suppression 的关键约束；③ 抑制期间报警**计数留痕**（现场要能证明「没报」是设计如此）。
- **clean-room 声明**：状态机（`eIdle/eSuppressed/eRestoring/eFault`）与「工况窗 + 抑制清单 + 计数」结构 100% 自有；零条款原文、零代码借用。
- **验收硬点**（交编码轮）：抑制解除路径必须可达（R28 终审第一式）；工况窗参数非法 → 进 `eFault` 而非静默不抑制；抑制中不得清 `bAlarmActive` 的真实状态位，只屏蔽「上报」。

### N3 `FB_DL_ChainElongationWatch` ｜ DL_Device ｜ 批 1 ｜ 低

- **来源标签**：`self-std`（设备本体健康族第三批）
- **源（矩阵行）**：`SOURCE_HUNTING_MATRIX.md` §5 台账「T2-2 LBP 基础工艺 ◐」的「命令 → 监视 → 判定」三段分层骨架（只借分层，不借代码）；判据源为公共机械常识（链节磨损 → 节距增大 → 同行程所需链轮转数减少）。
- **许可证**：道莅原创 MIT。
- **提取点**：① 三层结构（累计实际计数 / 与理论节距比 / 阈值分级）；② 只在「稳定速度段」取样（避免加减速段计数抖动污染趋势）；③ 拒绝用瞬时比值直接报警（需窗口趋势），防单拍毛刺误停。
- **clean-room 声明**：全部自研。与 `FB_DL_ConveyorSlipWatch`（打滑，速度偏差）分工：本件为**几何磨损趋势**，非速度同步性。

### N4 `FB_DL_NozzleClogDiag` ｜ DL_Device ｜ 批 1 ｜ 中低

- **来源标签**：`self-std`（设备本体健康族第三批）
- **源（矩阵行）**：矩阵 §5「T2-6 Rockwell AOI ◐」的「设备级粗粒度 + 每告警带确认延时」三分类诊断组织方式（R13 `AhuDamperStuckDiag` 已立先例，本件为**同族延续不重复记账**）；判据物理依据为公共流体常识（同开度下堵塞 → 上游压力升 ∧ 流量降）。
- **许可证**：道莅原创 MIT（AOI 仅借「分类 + 独立确认窗」结构，零 UDT/逻辑/注释接触）。
- **提取点**：① 双判据**同拍合取**（压力偏高 ∧ 流量偏低），单判据只降级为「疑似」；② 每类判据独立确认窗（与 `AhuDamperStuckDiag` 一致，防单拍反馈无效绕过确认）；③ 分级：疑似 → 维护请求 → 停机级。
- **clean-room 声明**：双判据形式、阈值引脚、分级枚举全自有。

### N5 `FB_DL_GripperHealthAoi` ｜ DL_Device ｜ 批 2 ｜ 中

- **来源标签**：`rockwell-aoi`（T2-6 设备级粒度族**第三件**：阀 / 电机 / 夹爪）
- **源（矩阵行）**：矩阵 §5 `T2-6 Rockwell AOI ◐` 行，原文「设备级 AOI 粒度族（阀/电机/夹爪）待挖」；R69 已交电机（`MotorHealthAoi`）与阀（`ValveIslandDiag`），**夹爪为族内唯一缺位**。
- **许可证**：Rockwell 1756-PM010 文档免费但**闭源版权** → 只借分类事实（AOI 参数四分段 / 每告警带确认延时 / ProgFault-OperFault 双类分离），零 UDT、零 rung 逻辑、零注释原文。
- **提取点**：① 三分类（夹持未到位 / 工件滑移 / 传感器失效）各带独立确认窗；② 组态类码与工艺类码**分码段**（沿用 R11 `RollerGapAdjust` 双段先例）；③ NE107 出口：磨损/滑移 = `eMaintenanceReq` 或 `eOutOfSpec`，传感器失效 = `eFailure`。
- **clean-room 声明**：状态机、判据、码位 100% 自有。
- **分工硬约束**：不做力窗判定（属 `FB_DL_GripperForceVerify`）、不做抓取放行（属 `FB_DL_RobotGripVerify`）；三件头注释互引。

### N6 `FB_DL_AdhesiveMassVerify` ｜ DL_Process ｜ 批 2 ｜ 中低

- **来源标签**：`self-std`（包装 / 3C 组装工艺族）
- **源（矩阵行）**：矩阵 §5「T2-2 LBP 基础工艺 ◐」的「命令 → 监视 → 判定」三段分层（定量给料语义），同族先例为 `FB_DL_CapperTorqueTrend` 的「多类 NG 判据 + 主判定优先级」组织方式；行业池 §19.4 已有胶量邻近方向（`JunctionBoxPottingCheck` 灌胶量），本件为**点胶口胶点级**判据，语义不同。
- **许可证**：道莅原创 MIT。
- **提取点**：① 流量积分（`FB_DL_Integrator`）与目标胶点质量比对；② 连续 N 点欠胶趋势拦截（单点超标只报警，连续超标才停线）；③ 组态参数（目标胶量、密度、允许误差）经 `VAR_INPUT` 注入，**不内联密度常数**。
- **clean-room 声明**：全部自研；与 `FB_DL_FrameSealDispenseSeq` / `FB_DL_PottingDispenseCtrl`（顺控件）分工为「校核件」，不控阀。

### N7 `FB_DL_SequentialEventLog` ｜ DL_Base ｜ 批 2 ｜ 中

- **来源标签**：`self-std`（诊断基础设施族）
- **源（矩阵行）**：矩阵 §5「T0-2 定时器 ✔」与「T2-7 PackML / OMAC ◐」不取本文；源为公共工业实践「SOE（Sequence of Events）记录」，与本库 `FB_DL_FirstOutLatch`（单因首出）、`FB_DL_StepTimeRecorder`（步耗时）构成诊断三件套。
- **许可证**：道莅原创 MIT。
- **提取点**：① 8 路首变捕获 + 时间戳（`TIME`/`UDINT ms` 由引脚决定，遵守 R66「时间注入三形态」口径）；② 队满**丢旧保新**（现场更关心最近事件）；③ 快照读出口（`VAR_OUTPUT` 数组 + 有效条数），禁 `VAR_IN_OUT` 外部直写内部缓冲。
- **clean-room 声明**：环形缓冲与排序逻辑自研；上游可复用 `FB_DL_RingBuffer` 能力但**不复制其代码**（调用而非内联）。
- **验收硬点**：同拍多路跳变必须**按通道号稳定排序**（禁依赖实现顺序）；`WHILE`/`FOR` 折叠必须带守卫计数器。

### N8 `FB_DL_CoolantConcentrationCtl` ｜ DL_Process ｜ 批 3 ｜ 中

- **来源标签**：`self-std`（金属加工公用工程族）
- **源（矩阵行）**：矩阵 §5「T2-1 LGF · Technology ◐」的「给定 → 限速 → 执行机构限幅」分层给定语义（只借分层）；工艺依据为公共机加工常识（乳化液浓度按折光仪读数维护在工艺带内）。
- **许可证**：道莅原创 MIT。
- **提取点**：① 读数 → 浓度折算（线性标定引脚注入，禁硬编码折光系数）；② 补液 = 原液 + 水按目标浓度配比，**两路累计量分别受控**（不做比值直通）；③ 浓度越窗 → 分级：提醒 / 联锁停加液 / 换液请求；④ 与流量审计件分工：本件不判流量。
- **clean-room 声明**：全部自研；配比算术为公共物理关系（质量守恒），不引任何厂商配方表。

### N9 `FB_DL_AirConsumptionBaseline` ｜ DL_Process ｜ 批 3 ｜ 中低

- **来源标签**：`self-std`（能源 / 公用工程族）
- **源（矩阵行）**：矩阵 §5「T2-1 LGF · Math ◐」的统计基线组织方式（取中位/均值窗口语义，调用库内统计件**不内联**）；同族先例 `FB_DL_PvSoilingLossRate`（基线漂移判据）。
- **许可证**：道莅原创 MIT。
- **提取点**：① 班次耗量基线（滚动窗口，剔除停机和换型段）；② 漂移判定用**相对基线百分比 + 绝对下限**双闸（防小基数放大）；③ 与 `FB_DL_AirLeakDecayTest`（停机压降法）分工：本件在线、连续、无停机要求。
- **clean-room 声明**：判据、窗口策略、分级全自研。

### N10 `FB_DL_VacuumBuildTimeTrend` ｜ DL_Device ｜ 批 3 ｜ 中低

- **来源标签**：`self-std`（设备本体健康族第三批）
- **源（矩阵行）**：矩阵 §5「T2-2 LBP 基础工艺 ◐」的「命令 → 监视 → 判定」骨架 + 「T2-1 LGF · Measurement ◐」的趋势统计语义；同族先例 `FB_DL_ChamberPumpDownProfile`（腔体抽气曲线）但**工位级点对点**语义不同。
- **许可证**：道莅原创 MIT。
- **提取点**：① 按「真空请求上升沿 → 到达阈值」测建立时长；② 时长基线与漂移分级（吸盘老化 / 管路微漏）；③ 真空度仍达标也预警（这是本件的核心价值：**达标但变慢**）。
- **clean-room 声明**：全部自研；不引用任何吸盘厂商寿命曲线。

---

## 2. 本轮拒单素材（供后续轮次复用，防重复试探）

| 候选 | 拒因类别 | 结论 |
|---|---|---|
| `FB_DL_HeaterBreakDetect` / `FB_DL_PumpDryRunGuard` / `FB_DL_ValveSeatLeakWatch` / `FB_DL_ToolLifeBudget` / `FB_DL_FrequencyGenerator` | 精确同名 | 永久拒，不得再试探 |
| `FB_DL_TrackerBacktrack*` | 同词干双前缀并存（FC + FB 各一件） | 永不再立；建议终审评估合并分工 |
| `FB_DL_HydOilConditionWatch` | 同义邻件（液压站件已覆盖） | 再立须先出边界表 |
| `FB_DL_WeldTipDressCounter` / LWORD 位段单字版 / 多段一次搬 | 凑数变体（无独立可验收判据差） | 拒，禁止以「域宽/位宽不同」为由立项 |
| `FC_DL_IntToUdintSat` / `FB_DL_ChwDifferentialPressureReset` / `FB_DL_RecipeSwitchoverSeq` | 已并案或已有属主 | 拒 |
| `FC_DL_StringToDTL` | 编译债未清 | 挂 ROADMAP 既有 DTL 条目，待实编译闸开 |
| `FB_DL_AirLeakBaseline` | 与在库压降法件同词干 | 改词干为 `AirConsumptionBaseline`（已采纳为 N9） |

---

## 3. 复用与「不内联」清单（编码轮硬约束）

| 新件 | 允许调用（Level 0 / 同层契约） | 禁止内联重写 |
|---|---|---|
| N1 | `E_DL_Ne107Status`（只引用）、`FB_DL_RuntimeMeter` | 不重造 NE107 枚举、不重造运行小时统计 |
| N2 | `FB_DL_TimeWindowCheck`（工况窗） | 不重造日/周窗判定 |
| N3 | 无（纯自研计数与比值） | 不调用运动层 |
| N4 | `FB_DL_ToleranceWindow` / `FC_DL_LimitClassify` | 不重造公差窗与分级表 |
| N5 | `E_DL_Ne107Status`、`FB_DL_ToleranceWindow` | 不重造力窗（属 `GripperForceVerify`） |
| N6 | `FB_DL_Integrator`、`FB_DL_ToleranceWindow` | 不内联密度/目标胶量常数 |
| N7 | `FB_DL_RingBuffer`（若有则调用）、`R_TRIG` | 不复制环形缓冲代码 |
| N8 | `FC_DL_LinearScale`、`FB_DL_ToleranceWindow` | 不内联折光系数 |
| N9 | `FB_DL_MovingAverage` / `FC_DL_PercentileLReal`、`FB_DL_TimeWindowCheck` | 不内联统计实现 |
| N10 | `TON`、`FB_DL_SignalStatistics` | 不重造趋势统计 |

---

## 4. 合规总表

| 源 | 性质 | 可商用 | 本轮用法 |
|---|---|---|---|
| 道莅自研（self-std） | MIT | ✅ | 主体（8 件） |
| ISA-18.2 公开条款 | 标准文本有版权，条款语义公开 | ✅（不使用原文、不声明认证） | N2 语义区分 |
| Rockwell AOI 文档（1756-PM010） | 免费但闭源版权 | 仅借鉴分类事实 | N5 分类结构 |
| Siemens LGF 文档（109479728） | 免费但闭源版权 | 仅借鉴分类/参数域 | N2/N3/N8 分层骨架（间接，经矩阵 §2 映射） |

**统一声明**：本轮无任何原始代码入 `_Staging_Raw`（零检索轮，无抓取物）；无 GPL/LGPL/AGPL 素材接触；所有 T2 借鉴均为「文档级分类事实」，实现零代码行复制。

*RAW_NOTES_R70 ｜ 2026-11-22 ｜ 道莅工控代码库产品总监*
