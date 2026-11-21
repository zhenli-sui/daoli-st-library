# RAW NOTES R12 ｜ 第 12 轮取源与合规留痕

> **轮次**：R12（2026-11-15）｜ **编制**：道莅工控代码库产品总监（兜底承担）
> **配套文件**：`ROUND_PLAN_R12.md`（同目录）
> **用途**：记录本轮每个组件的来源、许可证、提取点与处置方式，供后续审计与法务核查。
> **取证方式说明（必须先读）**：本轮为**离线无人值守轮次**，**未发起新的网络抓取**。下列「来源」分两类：
> ① **本地权威台账**（`SOURCE_HUNTING_MATRIX.md` 第 1/2/5 节、`ROADMAP.md`、`INDEX_REGISTRY.json`）——这些是前序轮次已完成的检索成果，本轮以「查阅台账」的方式取证；
> ② **公开规范与官方文档编号**（Siemens 文档 ID、Modbus 应用协议规范、IEC 61512、NAMUR NE43）——引用其**公开条款与分类**，不引用任何代码。
> 凡标注「未复核」的条目，表示本轮未重新打开源页面确认版本锚点，**不得**据此声称「已从某仓库获取代码」。宁可不写，不编造 commit。

---

## 1 来源记录（逐条一行）

| # | 来源 | URL / 文档 ID | 许可证 | 提取点 | 对应本轮组件 | 本轮取证方式 |
|---|---|---|---|---|---|---|
| S1 | Siemens **LGF V5.3.0**（Library of General Functions） | 文档 ID `109479728` | 免费使用、**闭源版权** | 「Bit Logic」组内「位测试 / 位串批量」的三层分类（单点 → 单段 → 批量段）；`Set_Bit`/`Reset_Bit` 的「打包-提取成对」组织 | `FC_DL_BitArrayExtract`、`FC_DL_BitArrayInsert`、`FB_DL_BitArrayChangeWatch` | 查阅矩阵第 2 节 LGF 11 组映射行；未重新下载手册 |
| S2 | Siemens **LGF V5.3.0** · Data Handling 组 | 文档 ID `109479728` | 同上（闭源） | 数据操作组把「FIFO/LIFO、数组搜索、排序、字符串」并列的分组方式；字符串函数「定长缓冲、无动态内存」的参数域约定 | `FC_DL_StringReplaceAll`、`FB_DL_StringTokenStream` | 同上 |
| S3 | Siemens **LGF V5.3.0** · Comparator 组 | 文档 ID `109479728` | 同上（闭源） | 「区间判断 / 公差窗口 / 限值」三分法；「开闭区间」作为区间函数的参数属性 | `FC_DL_IntervalMembership`、`FC_DL_ArrayDiffSummary` | 同上 |
| S4 | Siemens **LGF V5.3.0** · Date and Timer 组（天文钟族） | 文档 ID `109479728` | 同上（闭源） | 「日历天数周数 / 天文钟 / 多段定时」并列的组内切分；天文钟「本地时间 + 经纬度 → 太阳位置」的参数域 | `FC_DL_SolarPositionCalc` | 同上 |
| S5 | Siemens **LBP V2.7**（Library of Basic Processes） | 矩阵第 1 节 T2-2 行登记 | 免费使用、闭源 | 阀门/驱动类「命令 → 监视 → 判定」三段分层；阀特性作为**设备工艺参数**而非算法分支的组织方式 | `FB_DL_ValveCharacteristic`（只借参数域与分层） | 查阅矩阵 T2-2 行与 R11 台账；未复核 V2.7/V2.8 版次差异（矩阵内已存在两处版次口径不一致的记载，本轮不引用细节） |
| S6 | **ISA-88 / IEC 61512**（批次控制标准）· 相状态模型 | 公开标准条款（IEC 61512-1 相状态集合） | 公开规范（标准文本版权，条款可引用） | 相状态 11 态集合（Idle/Running/Complete/Holding/Held/Restarting/Stopping/Stopped/Aborting/Aborted）；「暂停在步骤边界生效」「恢复不重头」两条语义 | `FB_DL_BatchPhaseBase` | 公开规范条款，非代码；未引用任何厂商实现 |
| S7 | **Modbus 应用协议规范**（Modbus Application Protocol Specification V1.1b3）· 异常码表 | 公开规范（modbus.org） | 公开规范 | 异常响应判定（功能码 bit7）、异常码 01/02/03/04/05/06/08/0A/0B 的语义 | `FC_DL_ModbusExceptionParse` | 公开规范条款；中文名与分级判据为本库自有 |
| S8 | **NAMUR NE43**（模拟量故障电平）/ **NE107**（诊断分级） | 公开推荐规范 | 公开规范 | 「原始值域诊断与工程量分离」原则；多段有效域 + 越域即诊断的契约形态 | `FB_DL_EnergyMeterAccum`、`FB_DL_VacuumGaugeMux` | 查阅矩阵 NAMUR 行 + R5 `I_DL_AnalogSensor` 既有实现口径 |
| S9 | **OSCAT Network**（OSCAT 3.3x 网络库） | 矩阵第 1 节 T1-3 行登记 | OSCAT 许可（免费，需致谢） | 「协议帧解析 / CRC / 诊断」独立成族的分类方式；「函数码 + 异常码」两入参的参数域 | `FC_DL_ModbusExceptionParse` | 查阅矩阵 T1-3 行（该行原文标注「诊断帧解析族待挖」）；**未复制任何函数体/函数名/常量名** |
| S10 | **OSCAT Building**（AIR_ENTHALPY / WATER_ENTHALPY 行为定义） | 矩阵第 1 节 T1-2 行登记 | OSCAT 许可（免费，需致谢）；矩阵记载与 PsychroLib 的 EPL-2.0 公式链有关联 | `WATER_ENTHALPY` 的**行为定义**（输入温度、输出比焓、0 °C 基准）；「物性函数单独成件、不做 MODE 分支」的切分 | `FC_DL_WaterEnthalpy`、`FB_DL_VacuumGaugeMux`（域外行为显式化写法） | 查阅矩阵 T1-2 行；**未复制任何函数体**，多项式系数为公开饱和液水比热三点拟合 |
| S11 | **CODESYS Forge / Store** 免费库 · `DeviceReader` 族 | 矩阵第 1 节 T1-4 行登记 | 页面**未显式声明**许可条款 → 按最严口径处置 | 「设备参数读出 → 与工程组态比对 → 差异报告」三段流程骨架与参数域 | `FB_DL_DeviceParamVerify` | 查阅矩阵 T1-4 行（原文标注「DeviceReader / SysFile 族待挖」）；**零代码行复制、零注释引用** |
| S12 | **GitHub topics**：`motion` / `structured-text` / `iec-61131-3` | 矩阵第 1 节 T1-8 行登记 | 逐仓各异（MIT/Apache-2.0 优先）→ 本轮**未逐仓复核** | 开源两轴插补的**共同形态**：单位向量分解 → 合成速度限幅 → 梯形/三角自适应 | `FB_DL_LineInterp2Axis` | 查阅矩阵 T1-8 行结论（「其余 topics motion/packml/modbus 逐线开组待挖」）；按最严口径只借结构与参数域 |
| S13 | **T1-7 PLCnext Community** · port-based 诊断语义 | 矩阵第 1 节 T1-7 行 + R11 台账 | 各异（公开示例） | 「端口号 / 链路状态 / 诊断码 / 错误计数」四元组数据模型；错误槽号从 1 起 | `FB_DL_PortDiagBoard` | 查阅矩阵 T1-7 行与 R11 `PortDiagAggregator` 实现口径（同库内复用即合规） |
| S14 | 本地 `SOURCE_HUNTING_MATRIX.md` 第 2 / 5 节 | `C:\Library\SOURCE_HUNTING_MATRIX.md` | 本库自有文档 | LGF 11 组 → 六目录映射表；第 5 节十行台账中标注「待挖」的四类子族（DWORD/LWORD 数组批量位段、字符串族、开闭区间与数组批量比较、天文钟族） | 本轮 8 件 T2 组件的取源依据 | 直接读取 |
| S15 | 本地 `ROADMAP.md` 第七 / 十三 / 十五节 | `C:\Library\ROADMAP.md` | 本库自有文档 | 行业待办池条目：`FB_DL_PortDiagBoard`（§15.3，P0）、`FB_DL_PollTempBank`（§13.6，P0）、`FB_DL_ValveCharacteristic`（§7.6）、`FB_DL_VacuumGaugeMux`（§7.3） | 4 件行业件 | 直接读取 |
| S16 | 本地 `INDEX_REGISTRY.json`（168 条）+ 168 个 `.st` | `C:\Library\INDEX_REGISTRY.json` | 本库自有 | `code_segment` / `function_tags` 全量提取，用于码位避让与命名避让 | 18 件全部 | 脚本实扫 |

> 说明：S1~S4 同属一份文档（Siemens LGF 手册），拆行是为了让「哪一组对应哪些组件」可逐条追溯；S14~S16 为本库内部台账，列入是为了说明「本轮取源不是凭空而来」。

---

## 2 clean-room 边界：哪些是独立实现、哪些只借了分类

### 2.1 全部 18 件均为 clean-room 独立实现（无一行代码来自外部）

| 组件 | 独立实现的部分 | 只借了什么（不做代码级引用） |
|---|---|---|
| `FC_DL_BitArrayExtract` | 跨字拼接、掩码常量分支、截断策略、错误码 | LGF Bit Logic 组的**分类层次**与「源/起位/宽度」三段参数域 |
| `FC_DL_BitArrayInsert` | 双字展开、读改写时序、改动计数、撕裂防护 | 同族「打包-提取成对」的组织习惯 |
| `FC_DL_IntervalMembership` | 四组合判定表、容差策略、退化区间语义、裕量定义 | Comparator 组「开闭区间」的**参数属性**概念（LGF 无容差概念，容差为本库加严） |
| `FB_DL_BitArrayChangeWatch` | 异或 + 位计数单趟扫描、首变位定位、跳变饱和策略 | 位组「批量监视」在组内的分类位置 |
| `FC_DL_ArrayDiffSummary` | 逐项偏差、最大偏差与下标、非有限值处理 | Comparator 组「数组批量比较」子域的存在（LGF 不输出最大偏差与下标） |
| `FC_DL_StringReplaceAll` | 全替换循环、自增长防死循环、每轮回夹、双闸退出 | Data Handling 组字符串族的**定长无动态内存**参数域 |
| `FB_DL_StringTokenStream` | 流式状态机、空段占序号语义、逐字符帧变化判据 | 同上（LGF 无流式分词器，本件为新形态） |
| `FC_DL_SolarPositionCalc` | NOAA 公式实现、归一策略、`ASIN` 钳位、天顶方位角约定 | Date and Timer 组天文钟的**参数域**（时间 + 经纬度） |
| `FC_DL_ModbusExceptionParse` | 中文异常名、分级判据、可重试判据、未定义码处置 | OSCAT Network 的「帧解析独立成族」分类 + Modbus 规范的**公开异常码语义** |
| `FC_DL_WaterEnthalpy` | 三点拟合系数、多项式阶数、精度声明、域外早退 | OSCAT `WATER_ENTHALPY` 的**行为定义**（输入/输出/基准，非实现） |
| `FB_DL_ValveCharacteristic` | 三特性反解公式、限幅/死区、状态机、码位 | ISA-88 / LBP 的「阀特性属设备工艺参数」组织方式 |
| `FB_DL_DeviceParamVerify` | 逐项容差、结论锁存、超时、六态状态机 | Forge `DeviceReader` 示例的**三段流程骨架**（读/比/判） |
| `FB_DL_PortDiagBoard` | 跨组仲裁、Top3 稳定排序、掩码屏蔽、复位时序 | T1-7 的端口诊断**四元组数据模型** + ROADMAP P0 需求定义 |
| `FB_DL_EnergyMeterAccum` | 32 位拼装、单调性判据、换表识别、窗口需量 | NE43 的「原始域诊断与工程量分离」原则 |
| `FB_DL_VacuumGaugeMux` | 迟滞切换、十倍程交叉校验、融合规则、质量码映射 | NE43 多段有效域契约 + OSCAT 的「域外行为显式化」写法 |
| `FB_DL_LineInterp2Axis` | 速度剖面、临界判据、暂停策略、位置给定 | GitHub motion 线开源库的**共同三段结构** |
| `FB_DL_BatchPhaseBase` | 11 态状态机实现、命令优先级、边界暂停、超时、单拍请求 | ISA-88 **公开状态模型与两条语义**（暂停在边界/恢复不重头） |
| `FB_DL_PollTempBank` | 行级编排、通道质量掩码、摘除/恢复策略 | ROADMAP P0 需求定义 + Forge ModbusFB 的「调度与传输分层」 |

### 2.2 三类处置的明确划分

1. **clean-room 独立实现（18/18）**：本轮**没有任何一件**来自源码级改写。所有 `.st` 文件都必须由编码者从零书写，头注释 `开源溯源` 字段写「原创实现（参考 XXX 分类与参数域）」。
2. **只借分类与参数域（10 件）**：`BitArrayExtract`、`BitArrayInsert`、`BitArrayChangeWatch`、`ArrayDiffSummary`、`StringReplaceAll`、`StringTokenStream`、`SolarPositionCalc`、`WaterEnthalpy`、`ValveCharacteristic`、`DeviceParamVerify` —— 借的是「LGF/OSCAT 怎么把库切成组」「函数吃哪几个参数」，不借实现。
3. **只借公开规范条款（4 件）**：`IntervalMembership`（开闭区间的组合语义）、`ModbusExceptionParse`（异常码语义）、`BatchPhaseBase`（相状态模型）、`EnergyMeterAccum` / `VacuumGaugeMux`（NE43 诊断原则）—— 规范是公开文本，条款可引用，实现 100% 自有。
4. **库内复用（1 件）**：`FB_DL_PollTempBank` 实例化既有 `FB_DL_ModbusPollMaster` 与 `FB_DL_MovingAverage`（本库自有资产，复用即合规，且符合「行业模板只编排 Level 0/1 能力」的硬规则）。

---

## 3 合规铁律执行记录（逐条对照 `SOURCE_HUNTING_MATRIX.md` 第 0 节）

| 铁律 | 本轮执行情况 | 证据 |
|---|---|---|
| **只借骨，不抄肉** | 西门子 LGF/LBP 与 Rockwell AOI 均为免费但闭源。本轮 8 件 T2 组件**只取功能分组、接口参数域、命名组织**；无任何 DB 结构、无注释原文、无代码行 | `ROUND_PLAN_R12.md` 每件「来源与借鉴」段均写明「零代码行、零注释、零 DB 结构」；本文件 2.1 表逐件列出「只借了什么」 |
| **许可证隔离** | 本轮未接触 GPL/AGPL 源。OSCAT 为免费需致谢许可（非 GPL），CODESYS Forge 示例许可不明 → 按最严口径「只借结构、零复制」 | S9 / S10 / S11 行；`DeviceParamVerify` 头注释须写明「示例页面未声明许可，按最严口径处置」 |
| **来源留痕** | 每件 `.st` 头注释 `开源溯源` 字段 + 本文件 + `ROUND_PLAN_R12.md` 三处一致 | 本文件第 1 节 16 行；计划文件 3.1~3.18 节 |
| **不做能力越界声明** | `FB_DL_BatchPhaseBase` 不声明「符合 ISA-88 认证」，只写「采用公开相状态模型」；`FB_DL_PortDiagBoard` 不声明「替代厂商诊断」；安全相关件（本轮无）不声明「安全认证」 | 计划文件 3.13 / 3.17 节「边界」段 |
| **不编造来源** | 本轮未发起网络抓取，故**不写任何 commit hash / tag**；矩阵中已存在的版次矛盾（LBP V2.7 vs V2.8）本轮不引用细节，只引「分层骨架」这一稳定结论 | 本文件开头「取证方式说明」；S5 行备注 |

---

## 4 本轮未能完成 / 遗留的取证事项（下轮接手清单）

| # | 事项 | 影响 | 建议处置 |
|---|---|---|---|
| Q1 | LGF 手册未重新下载核对版次（矩阵记载 V5.3.0，未验证是否有更新） | 低（只借分类，分类多年稳定） | 有网络时核对文档 ID `109479728` 的最新版次，更新矩阵第 1 节 T2-1 行 |
| Q2 | CODESYS Forge `DeviceReader` 页面许可条款未复核 | 中（许可不明已按最严口径处置，不影响合规，但影响「能否写致谢」） | 复核页面许可；若确为 MIT/Apache，可在头注释增加致谢行 |
| Q3 | GitHub `motion` topics 各仓许可未逐条复核 | 中（同上，已按最严口径） | 逐仓核对；仅允许在「确认 MIT/Apache」后写「参考 XXX 仓库结构」 |
| Q4 | LBP V2.7 / V2.8 两处版次记载矛盾（矩阵第 1 节 T2-2 行 vs 第 5 节 R8 备注） | 低（本轮只用「命令-监视-判定」分层结论） | 由文档线统一为「以最新实测版次为准」，并在矩阵内加一行勘误说明 |
| Q5 | ISA-88 完整批次模型（Procedure / Unit / Recipe 三层编排）本轮只落「相」这一层 | 中（`FB_DL_RecipeManager` 与 `BatchPhaseBase` 尚未联调） | 下轮若做「配方 → 相 → 步骤」编排件，必须先给「与两件既有件的职责边界表」，否则不许立项（已入计划文件第 5 节拒绝清单 #8） |
| Q6 | 温控器 PV/SV 寄存器地址约定（`uStartAddr=0`、`uQuantity=2`）为默认假设 | 中（不同机型寄存器映射不同） | 在 `FB_DL_PollTempBank` 头注释与 MANUAL 写明「默认值仅为示例，实际映射由调用方填 `aPollTable`」 |

---

## 5 本轮「不挖」的明确结论（回写矩阵时的依据）

矩阵第 5 节有四行标注了「待挖」子族，本轮处理结论如下，回写台账时须逐行落实：

| 矩阵行 | 原「待挖」描述 | 本轮结论 |
|---|---|---|
| T2-1 LGF · Bit Logic | 「DWORD/LWORD 数组批量位段族仍待挖」 | **部分收口**：数组批量位段的「读（Extract）/ 写（Insert）/ 监视（ChangeWatch）」三件落地，该子族收口；组内仍有「LWORD 单字版」「位段批量搬运（多段一次搬）」未做，标为 ◐ 仍待挖但不属本轮范围 |
| T2-1 LGF · Data Handling | 「字符串族仍待挖」 | **部分收口**：全替换 + 流式分词两件落地；「字符串转数值（带校验）」「定长字段填充/对齐」仍待挖 |
| T2-1 LGF · Comparator | 「开闭区间组合与数组批量比较族待挖」 | **收口**：开闭区间成员判定 + 数组批量比对两件落地，该子族收口 |
| T2-1 LGF · Date and Timer | 「天文钟族待挖」 | **收口**：太阳位置计算落地；「月相/日出日落时刻表」不单独立项（可由本件二分求解，写进 MANUAL 示例） |
| T2-8 ISA-88 | 「完整批次模型（Procedure/Unit/Recipe）与报警管理族本体待挖」 | **相层收口、编排层仍待挖**：`BatchPhaseBase` 落地；Procedure/Unit/Recipe 三层编排与报警生命周期本体**明确不立**（见计划文件第 5 节 #6 / #8 拒绝理由） |
| T1-3 OSCAT Network | 「诊断帧解析族待挖」 | **部分收口**：异常帧解析落地；「RTU 帧长度/字节数一致性校验」「ASCII 帧 LRC 定位」仍待挖 |
| T1-4 CODESYS Forge | 「DeviceReader / SysFile 族待挖」 | **部分收口**：DeviceReader 的「读-比-判」流程以 `DeviceParamVerify` 落地；SysFile 族**不立**（需文件系统访问，违反零厂商依赖红线） |
| T1-8 GitHub topics | 「其余 topics（motion、packml、modbus）逐线开组待挖」 | **motion 线开组**（`LineInterp2Axis`）；packml 线已有 17 态全集件，modbus 线已有 `ModbusPollMaster`，两线**判定为已覆盖，不再开组**（避免重复件） |

---

## 6 编码者注意（与本文件相关的三条硬提醒）

1. **不要为了让「溯源」好看而写假 commit**：本轮无网络抓取，头注释只允许写「参考 <分类/规范> 的功能分类与参数域」，**禁止**出现「改写自 <仓库> @ <hash>」除非确有可商用源码在手。
2. **不要复制 LGF/OSCAT 的函数名与常量名**：本轮已刻意让命名与它们不同（如 LGF 的 `Set_Bit` 对应本库无同名件；OSCAT 的 `WATER_ENTHALPY` 对应本库 `FC_DL_WaterEnthalpy` 且引脚名全不同）。
3. **不要在本轮引入任何新的外部依赖**：`FB_DL_PollTempBank` 已用满「复用既有件」的配额（两个），其余 17 件一律只用 `Standard.library`。

---

*RAW NOTES R12 ｜ 2026-11-15 ｜ 道莅工控代码库产品总监（兜底模式）*
