# RAW NOTES R18 —— 检索与核对留痕（非纯 T0 轮）

> 轮次：**R18** ｜ 日期：2026-11-16 ｜ 记录人：工控代码库产品总监
> 性质：**非纯 T0 轮**（T0 变体 8 件 + T2-1 LGF 未挖子族 5 件 + T1/T2 混合 7 件）
> **WebSearch 调用次数：1**（预算 ≤2，留 1 次机动）。**T1/T2 检索配额：以「复用既有台账 + 单点核对」方式满足，未新增仓库抓取。**
> `_Staging_Raw` 无新增 `original_*.st`：本轮所有 T2/T1 源均为**分类/语义/参数域**级借鉴（铁律「只借骨不抄肉」），无第三方代码行进入暂存区，无新增许可证条目。

---

## 1 检索结论（如实声明）

| 项 | 结论 |
|---|---|
| 本轮是否联网检索 | **是，1 次**：CRC-16/CCITT 参数集与校验值核对（唯一需要外部事实确认的规格点） |
| 是否新增暂存区原始件 | **否**（零第三方代码行；T2-1 LGF 为闭源文档，铁律只借分类；T1-6/T2-5/T2-6/T2-7/T2-8 为公开规范条款级语义） |
| 是否新增许可证核查 | 否（无复制，不存在传染路径）；新增 0 个 `README_SOURCE.md` |
| 既有台账复用 | 是。复用 `SOURCE_HUNTING_MATRIX.md` §1 T0/T1/T2 定义 + §2 LGF 11 组映射 + §5 挖掘状态台账（T0-1/T0-2/T0-7/T2-1 四行、T2-2/T2-5/T2-6/T2-7/T2-8 五行、T1-3/T1-5/T1-6 三行）+ `AGENT_EVOLUTION_LOG.md` R45/R48/R50/R54/R57/R61 范式 |

### 1.1 唯一一次检索的详情

| 字段 | 内容 |
|---|---|
| 查询 | `CRC-16/CCITT-FALSE parameters poly 0x1021 init 0xFFFF check value 0x29B1 "123456789"` |
| 时间 | 2026-11-16 12:52 |
| 命中源 | ① `crccalc.com`（CRC-16/IBM-3740 = CCITT-FALSE 参数页 + 256 项查表）｜② `tool.io/checksum/crc-16-ccitt`｜③ `gophertrunk.org/reference/crc-16-ccitt`（三变体对照表）｜④ `bushe.co/tools/crc16-ccitt-calculator`｜⑤ `embedcalc.com/guides/crc-parameters-explained`（五参数对照表） |
| 提取点（事实性参数，非代码） | CCITT-FALSE = poly `0x1021` / init `0xFFFF` / 不反射 / xorout `0x0000` / check **`0x29B1`**；XMODEM = init `0x0000` / check **`0x31C3`**；KERMIT = 反射（右移用位反多项式 `0x8408`）/ init `0x0000` / check **`0x2189`**；MODBUS = poly `0x8005` 反射 / check `0x4B37`（**库内 `FC_DL_Crc16Modbus` 已覆盖，本轮不重做**） |
| 许可证 | 上述站点为公开技术资料/计算器页面（无代码交付），参数与校验值为公开事实，不构成版权文本；本库只采用参数与校验值，**零代码行复制** |
| 商用结论 | 可商用（事实性数据） |
| 处置 | 仅作 `FC_DL_Crc16Ccitt` 的**验收向量**依据；实现为位循环 clean-room，未采用任何查表数组 |

**为什么要检索**：R13 曾发生「CRC-8 规格向量错误」（R1 式缺陷）。16 位 CRC 的三种 `0x1021` 变体只差 init/反射，肉眼极易写错；不核对校验值就派单，等于把错误固化进 20 件批次。**1 次检索换掉一类系统性风险，划算。**

---

## 2 本轮核对动作（实测，禁止口头交接）

### 2.1 `INDEX_REGISTRY.json`（Python 解析，未落盘修改）

| 核对项 | 实测值 |
|---|---|
| `version` / `total_components` / `last_updated` | `2.6.0` / **284** / `2026-11-16T10:24:15+08:00` |
| `counts` | DL_Base 59 / DL_MathData 103 / DL_Algo 28 / DL_Device 50 / DL_Motion 18 / DL_Process 26 = **284** ✔ |
| 物理 `.st` 数 | **284**（与 registry 一一对应，无孤儿文件） |
| 今日进度 | 98 / 200（11-16 开账 186）｜总库 2.84 %｜距 500 差 **216** |
| 名称重名核查 | R18 拟立 20 名 × registry 284 名 = **交集空**；× 284 个文件名 = **交集空**；20 名自身 unique = 20 ✔ |

### 2.2 码位实测（本轮核心动作，R61 教训执行）

**测试方法**：对全部 284 个 `.st` 跑正则 `16#([0-9A-F]{4})_([0-9A-F]{4})`，按子库分组统计「大段 + 网格 + 已用值」，再对候选码逐槽反查是否占用。脚本落盘：`_probe_r18.py` / `_probe_r18b.py` / `_probe_r18c.py` / `_verify_r18.py`。

| 子库 | 实测大段 | 实测网格规则 | 已用上界 | 本轮起点 |
|---|---|---|---|---|
| DL_Base | `0001_` | 信息 `02xx` / 故障 `02F1↑`→`03xx` | 信息 `022D`（散占至 `028D`）｜故障 `0305` | 信息 `0235`｜故障 `0306` |
| DL_MathData | `0001_`（与 Base 共用） | 同上 | 同上 | 同上 |
| DL_Algo | `0002_CCSS` | `CC` = 组件序号（`01~22`），槽 `01~04` 信息 / `10~12` 故障 | `CC = 22`（`2212`） | `CC = 23~26` |
| DL_Device | `0003_` | 信息 `01xx` / 组态故障 `02xx` / 工艺故障 `03xx` | 信息 `0165`｜故障 `0329` | 信息 `0166`｜故障 `032A` |
| DL_Motion | `0004_` | 信息 `01xx` / 故障 `02xx` | 信息 `01C6`｜故障 `02D4` | 信息 `01C7`｜故障 `02D5` |
| DL_Process | `0005_` | 信息 `01xx` / 故障 `02xx` | 信息 `01D1`｜故障 `02FE` | 信息 `01D2`｜故障 `02FF` |

**`_verify_r18.py` 输出（可复跑）**

```
name dup vs registry: []   name dup vs files: []
unique count: 20
seg 0001 n=40 unique=40 CLASH= []
seg 0002 n=20 unique=20 CLASH= []
seg 0003 n=10 unique=10 CLASH= []
seg 0004 n=15 unique=15 CLASH= []
seg 0005 n=10 unique=10 CLASH= []
```

**结论**：95 个候选槽 100 % 空闲、100 % 唯一。

### 2.3 ⚠ 与指令的偏差声明（须创始人知悉，收口不得再改判）

指令给出「信息级从 `16#0001_0235` 顺延、故障级从 `16#0001_0306` 顺延，每件 5 槽」。**实测该前提只对 DL_Base / DL_MathData 成立**：库内其余四个子库各自使用独立大段（`0002_`~`0005_`），且各自有独立网格（Algo 为 `CCSS` 组件序号网格）。若强行把 20 件全塞进 `0001_`：

1. `0001_02xx` 空闲槽不足以容纳 20 件 × 2 槽（实测 `0235~02FF` 仅余 79 个散槽，但 12 件属其他子库）；
2. 更严重的是**跨段越界**：DL_Algo/Device/Motion/Process 的件写 `0001_` 会与 Base/MathData 存量件长期混段，HMI 侧无法按段归组（R30 教训：两件 BCD 原拟 `0004_` 撞 DL_Motion 段被终审改回）。

**裁定**：按「实测为准」（R61）分 5 段分配，`0001_` 只承接 8 件。已写入 `ROUND_PLAN_R18.md` §0.3 与本文件，**双向可追溯**。

### 2.4 缺口核实（本轮立族的事实依据）

| 缺口 | 核实方法 | 结论 |
|---|---|---|
| 首出锁存（First-Out）零覆盖 | registry 名称集合 grep `First\|首出` + `DL_*` 文件名 | **零命中** → #1 净新增（`PortDiagAggregator` 只有「首出端口」内部量，无独立可复用件） |
| 最小脉宽/脉冲展宽零覆盖 | grep `Stretch\|展宽\|Pulse` → 仅 `PulseGenerator`（生成而非整形） | **零命中** → #2 净新增，与 `PulseGenerator`/`TonEx` 职责已划清 |
| 沿分频零覆盖 | grep `Divider\|Divide\|分频` → 仅 `TimeDivChk`（时间除法） | **零命中** → #3 净新增 |
| 位串多段一次搬零覆盖 | grep `BitSegment\|BlockMove` + 读 `BitArrayExtract/Insert` 头注释（单段语义） | **零命中** → #4 净新增，矩阵 §5 明列「多段一次搬待挖」 |
| CRC-16 `0x1021` 族零覆盖 | grep `Crc` → 仅 `Crc8`（三变体）/`Crc16Modbus`（0x8005 反射）/`Crc32Ethernet` | **命中缺口** → #5 净新增，与 `Crc16Modbus` 参数集正交 |
| 二维插值零覆盖 | grep `Interpolate\|Table2D\|双线性` → 仅 `MultiPointLinear`（一维）/`LinearScale` | **零命中** → #6 净新增 |
| 仿射变换零覆盖 | grep `Affine\|仿射` → 零命中；矩阵 §5 T2-1 Math 行「仿射变换组合族待挖」 | **命中矩阵待办** → #7 |
| Cp/Cpk 零覆盖 | grep `Cpk\|Cp\b\|能力指数` → 零命中；仅 `SignalStatistics`（通用统计） | **零命中** → #8 净新增 |
| 增益调度零覆盖 | grep `Scheduler\|调度` → 仅 `PdiReadScheduler`（读调度，无关） | **零命中** → #9 净新增 |
| 无扰切换零覆盖 | grep `Bumpless\|无扰` → 零命中；矩阵 §5 T2-5 行明列「仅剩手自动切换手册细节」 | **命中矩阵待办** → #10 |
| 陷波滤波零覆盖 | grep `Notch\|陷波` → 零命中；滤波族仅 Low/High/SecondOrder/Median | **零命中** → #11，矩阵 Measurement 行未挖一侧 |
| I²t 热模型零覆盖 | grep `I2t\|Thermal\|热模型` → 零命中（`MotorDriver` 内无此模型） | **零命中** → #12 净新增 |
| 跟随误差监视零覆盖 | grep `FollowingError\|跟随误差` → 零命中（`GantrySyncAxis` 是双驱偏差，非单轴跟随误差） | **零命中** → #13 净新增，职责边界已写 |
| 受控停车零覆盖 | grep `Stop\|停车` → 无 `AxisStop` 类件（`SoftLimitGuard` 是限位预判） | **零命中** → #14 净新增 |
| 背隙补偿零覆盖 | grep `Backlash` → 仅 `RollerGapAdjust`（辊缝顺控，非轴级补偿） | **命中缺口** → #15，职责边界已写 |
| 夹爪契约/实现零覆盖 | grep `Gripper\|夹爪` → **零命中**；矩阵 §5 T2-6 行明列「设备级 AOI 粒度族（阀/电机/夹爪）待挖」 | **命中矩阵待办** → #16 + #17（契约-实现对） |
| SSR 加热驱动零覆盖 | grep `Ssr\|Heater\|Heat` → 仅 `HeatCoolZone`（区域控温，非驱动级 PWM + 断线诊断） | **零命中** → #18 净新增 |
| 停机原因分类零覆盖 | grep `Downtime\|停机` → 零命中（`OeeCalculator` 统计三因子，不做归因） | **零命中** → #19 净新增，职责边界已写 |
| 换型换产顺控零覆盖 | grep `Changeover\|换型` → 零命中（`RecipeManager` 管配方存取，不做换产顺控） | **零命中** → #20 净新增 |

### 2.5 ROADMAP 去重核查

`grep -n "FirstOut\|PulseStretch\|EdgeDivider\|BitSegment\|Crc16Ccitt\|Table2D\|Affine\|Cpk\|GainScheduler\|Bumpless\|Notch\|I2t\|FollowingError\|SynchronizedStop\|Backlash\|Gripper\|SsrHeater\|Downtime\|Changeover" ROADMAP.md` → **零命中**（20 件全为 ROADMAP 未注册项，符合「未注册待办」立项判据，不与既有待办重复）。

---

## 3 本轮不新增抓取的三条风险与对冲

1. **T2-1 LGF 为闭源文档**（免费使用但版权归西门子）→ 对冲：只借「组内分类 / 接口参数域 / 组件粒度」三类结构性事实（铁律 1），四件（#4 #5 #6 #7 #11）在头注释「溯源」段写明「只借分类，实现与码位自有」；#6 双线性公式取公开数学，#7 仿射合成取公开线性代数，#11 双线性变换取公开 DSP 公式。
2. **T1-6 PLCopen 语义未逐条比对最新版规范文本** → 对冲：只借「停止 / 跟随误差监视」两条最稳定的公开语义（MC_Stop/MC_Halt 家族自 2001 年起未变），且 **#13/#14/#15 三件一律不自造轴状态机、不定义轴状态枚举**（唯一属主 `FB_DL_SingleAxis`），风险被限制在「给定量生成」一层。
3. **`E_DL_Ne107Status` 跨件引用** → 对冲：#16 `I_DL_Gripper` 只**引用**该枚举，不重声明；自检第 14 项专查「`TYPE E_DL_Ne107Status` 全库只 1 处」。

---

## 4 状态一致性观测（留给收口）

- `INDEX_REGISTRY.backup_R17.json` 与 `INDEX_REGISTRY.json.backup_R18` 已存在（R18 阶段一未改 registry，两文件内容应一致，收口时核对 `total_components` 仍为 284）。
- `ROADMAP.md` 待办池 326 条，**≥30 条 → 本轮按指令不动 ROADMAP**（只在本文件留痕，缺口由 #1~#20 直接覆盖）。
- `AGENT_EVOLUTION_LOG.md` 最新为 R17 节（含 R61~R64）——本轮新增规则候选见 `ROUND_PLAN_R18.md` §0.3 与 §5（R65「码位分段必须逐子库实测，禁以单段游标覆盖全库」；R66「派单样板四段制：注释行 / 错误码 / 头注释 / 码位总账行」），**正式立规在收口轮写入 EVOLUTION LOG**。
- 三个探针／校验脚本已落 `_Staging_Raw/2026-11-16/`（`_probe_r18*.py` / `_verify_r18.py`），**不属交付物**，仅作可复跑证据。

---

## 5 本轮产出清单（阶段一 + 阶段二，零 `.st`）

| 文件 | 性质 | 说明 |
|---|---|---|
| `C:\Library\_Staging_Raw\2026-11-16\ROUND_PLAN_R18.md` | 规划（新建） | 盘点区 + 20 目标表 + 4 批划分 + 20 件引脚级规格 + 95 槽码位总账 + 四段样板原文 + 16 项自检 + 禁区表 |
| `C:\Library\_Staging_Raw\2026-11-16\RAW_NOTES_R18.md` | 留痕（本文件，新建） | 1 次检索详情 + 实测核对 + 偏差声明 + 19 条缺口证据 + 风险对冲 |
| `_probe_r18.py` / `_probe_r18b.py` / `_probe_r18c.py` / `_verify_r18.py` | 证据脚本（新建） | 码位实测与重名/占用校验，可复跑 |

**未触碰**：`INDEX_REGISTRY.json`、`*.jsonl`、`ROADMAP.md`、`SOURCE_HUNTING_MATRIX.md`、`CHANGELOG.md`、`README.md`、`LIBRARY_MANUAL.md`、各子库 `VERSION.md` / `MANUAL_DL_*.md`、任何 `DL_*/` 下的 `.st`（按指令：回写由收口完成）。

---

*R18 RAW NOTES ｜ 2026-11-16 ｜ WebSearch 1 次（CRC-16 参数核对，留 1 次机动）｜ T2/T1 复用台账，零新增抓取 ｜ 子代理 0 个*
