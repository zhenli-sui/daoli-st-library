# RAW NOTES R19 —— 狩猎 / 复用留痕（Step 2）

> 轮次：**R19** ｜ 日期：2026-11-16 ｜ 编制：道莅工控代码库产品总监
> 检索配额：**WebSearch 上限 3 次/轮 → 本轮实用 2 次**；其余 16 件全部复用既有台账与公开工程惯例（零新增抓取）
> 合规铁律：闭源/文档版权源**只借分类体系、参数域、命名组织与公开规范条款**，代码 100% clean-room；GPL/AGPL 源一律不接触实现
> 配套：派单书 `ROUND_PLAN_R19.md` ｜ 校验脚本 `_verify_r19.py`（RESULT = PASS）

---

## 1 检索 1｜PROFINET 通道诊断语义（服务 `FB_DL_ProfinetAlarmDiag`）

| 项 | 内容 |
|---|---|
| **检索词** | `PROFINET diagnosis record index 0x800a 0x800b ChannelDiagnosis ChannelErrorType ErrorType structure` |
| **次数** | 1（本轮第 1 次） |
| **命中源 1** | CODESYS Online Help · `ProfinetCommon` → `ChannelErrorType (ENUM)`<br>URL: `https://content.helpme-codesys.com/fr/libs/ProfinetCommon/Current/ProfinetCommon/Diagnosis/DataTypes/ChannelErrorType.html` |
| **命中源 2** | SIEMENS《PROFINET IO From PROFIBUS DP to PROFINET IO》编程手册（诊断记录结构章节）<br>URL: `https://iautomatica.ru/upload/uf/98c/98c87492cf1a43827b128fd8a8f91ec8/From%20PROFIBUS%20DP%20to%20PROFINET_IO_en-US.pdf` |
| **命中源 3** | Industrial Monitor Direct KB：ET200SP 健康状态监视（含 0x800A 读取与 ChannelErrorType 现场常见值表）<br>URL: `https://industrialmonitordirect.com/zh-hans/blogs/knowledgebase/monitoring-et200sp-health-status-in-wincc-runtime-with-pcs-7` |

### 提取点（全部为**公开规范条款 / 公开枚举语义**，无一行实现代码）

1. **诊断记录标识**：通道诊断记录索引 `0x800A`（ChannelDiagnosis）/ `0x800B`（ChannelDiagnosisBlockHead）/ `0x800C`；无故障时返回**长度为 0 的记录**（→ 本件 `uEntryCount = 0` 判 `eOk` 的依据）。
2. **记录内字段序列**：`BlockType / BlockLength / BlockVersion / SlotNumber / SubslotNumber / ChannelNumber / ChannelProperties / USI`，其后按故障通道逐项重复 `ChannelNumber / ChannelProperties / ChannelErrorType（/ ExtChannelErrorType / ExtChannelAddValue）`。
3. **`ChannelErrorType` 标准枚举值域**（本件解码表直接采用，常量名本库自定）：
   `0x0001` Short_circuit · `0x0002` Undervoltage · `0x0003` Overvoltage · `0x0004` Overload · `0x0005` Overtemperature · `0x0006` Line_break · `0x0007` Upper_limit_value_exceeded · `0x0008` Lower_limit_value_exceeded · `0x0009` Error · `0x000A` Simulation_active · `0x000F` Parameter_missing · `0x0010` Parameterization_fault · `0x0011` Power_supply_fault · `0x0012` Fuse_blown_or_open · `0x0013` Communication_fault · `0x0014` Ground_fault · `0x0015` Reference_point_lost · `0x0016` Process_event_lost · `0x0017` Threshold_warning · `0x0018` Output_disabled · `0x0019` FunctionalSafety_event · `0x001A` External_fault · `0x001F` Temporary_fault（另源记 Maintenance demanded，见下）· `0x8000+` 系统级（Data_transmission_impossible / Remote_Mismatch / MRP_mismatch / Sync_Mismatch / IsochronousMode_mismatch / Time_mismatch …）。
4. **⚠ 语义冲突（已落地为 R66 规范）**：`0x001F` 在 CODESYS `ProfinetCommon` 枚举中为 `Temporary_fault`，在 SIEMENS ET200SP 公开值表中为 `Maintenance demanded`（同表另有 `0x001E` Maintenance required）。**两份公开资料不一致** → 本库裁定：`0x001E` 与 `0x001F` **一律归「维护类」桶**（保守侧：宁可让运维去看，不可让产线误停），并在 `.st` 头注释并列陈述两种语义与裁定理由。
5. **维护类门限**：`0x001E / 0x001F` 属「值状态为 0 但无通道故障」的维护事件 → 支撑本件 `bMaintenanceOnly` 出口（可继续生产、需安排保养）。

### 许可证与合规结论

| 源 | 许可性质 | 本库取用方式 | 是否可商用 |
|---|---|---|---|
| CODESYS `ProfinetCommon` 帮助页 | 文档版权（厂商帮助文档） | **只取公开枚举值域与名称语义**，不复制其 ST 声明、不引用其库、不建库依赖 | ✔（枚举值由 PROFINET 规范定义，不构成表达性版权） |
| SIEMENS 编程手册 PDF | 文档版权 | **只取记录结构字段序列与「长度 0 = 无故障」的行为定义** | ✔（同上） |
| Industrial Monitor Direct KB | 第三方知识库 | 只作**交叉印证**（三方一致才采纳），不引用其代码片段 | ✔ |

**红线核对**：`.st` 内**不解析原始诊断记录字节**（需 `ANY`/指针，违红线 6），改为上游把五项字段读入数组后由本件做分类聚合；零厂商库、零 `SysLibMem`。

---

## 2 检索 2｜继电反馈自整定描述函数公式（服务 `FB_DL_AutoTuneRelay`）

| 项 | 内容 |
|---|---|
| **检索词** | `relay feedback auto-tuning ultimate gain Ku = 4d/(pi*a) describing function hysteresis formula` |
| **次数** | 1（本轮第 2 次） |
| **命中源 1** | Lund University 学位论文《Autotuning of a PID-controller》（式 2.8 / 2.9）<br>URL: `https://lup.lub.lu.se/student-papers/record/8848024/file/8859436.pdf` |
| **命中源 2** | Lund University《On Automation of the PID Tuning Procedure》（式 1.4 / 1.5，Åström & Hägglund 1984 原始方法综述）<br>URL: `https://lup.lub.lu.se/search/files/20277457/8168791.pdf` |
| **命中源 3** | Shanon Technologies 文档《Relay Autotune (Ziegler-Nichols)》——工程实现侧的**闸门清单**<br>URL: `https://www.shanon-technologies.com/docs/system-identification/relay-autotune-ziegler-nichols` |

### 提取点（公开学术公式 + 公开工程惯例）

1. **描述函数（无迟滞）**：`N(a) = 4d/(πa)`，振荡条件 `N(a)·G(iω) = −1` ⇒ **`Ku = |G(iωu)| = 4d/(πa)`**（源 1 式 2.8；源 2 式 1.4）。
2. **含迟滞 h 的负倒描述函数**：`−1/N(a) = −(π/4d)·√(a²−h²) − i·(πε/4d)` ⇒ **`Ku = 4d/(π·√(a²−h²))`**（源 2 式 1.5；源 3 同式，符号 h 与 ε 同义）。
3. **闸门 1｜迟滞必须窄于所测振荡**：`h ≥ a` 时 `√(a²−h²)` 为零或虚数，`Ku` 不可定义；工程实现侧明确「refuse the run instead of returning a number」→ 本件落为**故障 2A10**。
4. **闸门 2｜采样密度**：每半周期至少 **6 个采样点**，否则「振荡」是采样网格产物而非对象特性 → 本件落为**故障 2A11**（`uMinSamplesPerHalf` 默认 6，下限 4）。
5. **闸门 3｜幅值稳定性**：须等到极限振荡稳定（源 3 用「前半窗 vs 后半窗均值比较」判据，未收敛则拒绝）→ 本件落为**信息 2A01 + 继续测量**，超 `tMaxDuration` 落**故障 2A12**。
6. **整定规则常数（公开文本）**：Z-N 经典 `P: Kp=0.5Ku`；`PI: Kp=0.45Ku, Ti=Tu/1.2`；`PID: Kp=0.6Ku, Ti=Tu/2, Td=Tu/8`；Åström-Hägglund 无超调 `Kp=0.2Ku, Ti=Tu/2, Td=Tu/3`（源 3 表，与源 4 交叉一致）。
7. **实现侧纪律**：`d` 过大把对象推到非线性区 → 本件加 `DL_AT_AMP_RATIO_MAX = 0.2`（继电幅值 / 量程上限）作工程保守闸。

### 许可证与合规结论

| 源 | 许可性质 | 本库取用方式 | 是否可商用 |
|---|---|---|---|
| 两篇 Lund 学位论文 | 学术公开出版物（版权归作者/学校） | **只取公式与推导结论**（数学公式不构成表达性版权）；不复制论文文字、不复制任何代码 | ✔ |
| Shanon 工程文档 | 商业文档（公开网页） | 只取**闸门清单与规则常数表**（公开整定规则），不复制其实现 | ✔ |

**红线核对**：公式用 `LREAL` 中间量实现；`Ku = 4d/(π√(a²−h²))` 的根号前必须先过 `h < a` 闸（`SQRT` 入参非负由闸门保证）；`CASE eRule ... ELSE` 兜底为 2A12。**未复制任何实现代码行**。

---

## 3 零检索件：复用既有台账清单（16 件，逐件指明复用依据）

| # | 组件 | 复用依据（既有台账 / 公开惯例） | 是否需新检索 |
|---|---|---|---|
| 1 | `FC_DL_DintMsToTod` | ROADMAP §22.2 P0 承诺条；反向语义由库内 `FC_DL_TodToDintMs`（R17）既定契约对称推出；IEC 61131-3 `TOD` 定义 | 否 |
| 2 | `FC_DL_TimeRatioCalc` | ROADMAP §22.2 P0；`FC_DL_TimeDivChk`（R16）已建立「TIME 除零闸 + 负除子取模长」纪律，本件只把出口从 `TIME` 改成 `LREAL` 比值 | 否 |
| 3 | `FC_DL_RatioToPwrDb` | ROADMAP §22.2 P0；R17 `FC_DL_PwrDbToRatio`（正向）与 `FC_DL_RatioToAmpDb`（幅值型反向）为既定对偶契约；380 dB 上限口径沿用 R17 由 REAL 可表性反算的结论 | 否 |
| 4 | `FC_DL_LintToUdintSat` | ROADMAP §22.2 P1；R16 `FC_DL_DintToUintSat`（负向 + 正向双侧饱和）与 R17 `FC_DL_LintToDintSat`（仅正向）共同给出饱和族范式（R56「无符号双分支钳位」） | 否 |
| 5 | `FB_DL_BitShiftRegister` | `SOURCE_HUNTING_MATRIX` §5 T2-1 LGF · Bit Logic 行（组内三层已齐备，本件补时序层）；R48/R10 移位量纪律；R12 `BitArrayExtract/Insert` 的跨字掩码经验 | 否（T2 组分类事实已在矩阵内） |
| 6 | `FC_DL_ModbusRtuFrameCheck` | **R12 `RAW_NOTES_R12`「诊断帧解析族」台账**（功能码 01/02/03/04/05/06/08/0A/0B 语义已核）+ Modbus 应用协议规范公开条款（RTU 帧结构、异常应答定长 5、广播地址语义） | 否（同源不重复检索，符合「同源不得重复检索」） |
| 7 | `FB_DL_FlowSqrtExtract` | ROADMAP §16.6 P1；差压流量开方与低切为仪表工程公开惯例；阻尼与限幅分层的组织方式借 T1-1 OSCAT Basic 信号处理族分类（R4 台账已记） | 否 |
| 8 | `FB_DL_RatioController` | 比值控制为公开过程控制通用结构；T2-5 Mod_PID 参数域组织（R18 `BumplessTransfer` 已收口其「手自动」细节，本件不重复该语义） | 否 |
| 9 | `FB_DL_LeadLagCompensator` | 超前滞后校正为公开经典控制判据；T1-1 OSCAT Basic 控制器族分类事实（R4 台账）；Tustin 离散化为公开数字控制公式 | 否 |
| 10 | `FB_DL_DeviceHealthArbiter` | 矩阵 §5 T2-8 明列「NE107 实现块仲裁件（多源健康聚合）待挖」；`I_DL_DeviceHealth`（R13）已定「六态 + 编号即仲裁优先级」契约；首出三律复用 R11 `PortDiagAggregator` | 否 |
| 11 | `FB_DL_ProfinetAlarmDiag` | 见 §1（**唯一新增检索件**） | **是（1 次）** |
| 12 | `FB_DL_EscChuckCurrentMonitor` | 矩阵 §5「半导体 ESC 自研」行明列「ESC 静电吸附电流监视族待挖」；R13 `EscHeLeakCheck` 已建立「分段定时器按段断输入（R40）+ 阈值倒置自动交换」范式 | 否 |
| 13 | `FB_DL_DeviceParamWrite` | 矩阵 §5.1 勘误 **M-E3** 悬置项（DeviceReader 下半段）+ R12 `FB_DL_DeviceParamVerify` 三段流程骨架；许可按最严口径（示例页未声明许可 → 零代码行、零注释引用） | 否 |
| 14 | `FB_DL_ExternalEncoderScaler` | 矩阵 §5 T2-4 明列「外部编码器族待挖」；R13 `PassiveHomingMonitor`「不自造轴状态」纪律 | 否 |
| 15 | `FB_DL_CamPhaseTrim` | 矩阵 §5 T1-6 明列「凸轮动态修调待挖」；R8 `FB_DL_ElectronicCam` 为组合下游（不内联） | 否 |
| 16 | `FB_DL_FilmWebCenter` | ROADMAP §10.4（R9 扩容）P1 条；纠偏 EPC 为公开卷材处理工程结构 | 否 |
| 17 | `FB_DL_WindingLayerCounter` | ROADMAP §15.1（R10 扩容）P1 条；R10 `FC_DL_CoilDiameterCalc`「算一个值 / 做一件事」切分纪律 | 否 |
| 18 | `FB_DL_DrumLevelThreeElem` | ROADMAP §10.6（R6 扩容）P1 条；三冲量为公开锅炉控制工程结构 | 否 |
| 19 | `FB_DL_VacCupRingCtrl` | ROADMAP §10.4（R6 扩容）P1 条；`I_DL_VacuumGenerator` / `FB_DL_VacuumEjector` 作单机下游 | 否 |

> 计数说明：上表 19 行含 §1 检索件（#11）。零检索件 = **18 件**（含 `FC_DL_AutoTuneRelay` 属 §2 检索件，故检索件共 2 件：`ProfinetAlarmDiag`、`AutoTuneRelay`）。

---

## 4 每轮配额自检（`SOURCE_HUNTING_MATRIX` §4 硬性要求）

| 配额项 | 要求 | R19 实测 | 结论 |
|---|---|---|---|
| T2 非 ST 借鉴源 ≥ 1 族 | 硬性 | **T2-1 LGF · Bit Logic**（#5）、**T2-8 NE107**（#10→#11 仲裁件）、**T2-4 Motion 外部编码器族**（#15）、**T2-5 参数域次源**（#8） | ✔ 4 族 |
| T1 ST 原生源 ≥ 1 组 | 硬性 | **T1-3 OSCAT Network**（#6 帧校验收口）、**T1-7 PLCnext**（#12 PN 诊断收口）、**T1-4 CODESYS Forge**（#14 下半段收口）、**T1-6 PLCopen**（#16 凸轮修调收口）、**T1-1 OSCAT Basic 次源**（#7 #9） | ✔ 5 组 |
| 自研 / 公开规范线 | — | 半导体 ESC 自研（#13）、公开学术判据（#10）、公开工程惯例（#7 #8 #9 #17 #18 #19 #20） | ✔ |
| 检索次数 ≤ 3 | 硬性 | **2** | ✔ |
| 同源不重复检索 | 硬性 | Modbus / NE107 / DeviceReader / LGF / ESC / Motion 全部复用既有 RAW_NOTES，**未重复检索** | ✔ |
| 本轮回写矩阵挖掘状态 | 收尾必办 | 待收口执行（§5 给出逐行回写内容） | 待办 |

---

## 5 挖掘状态回写内容（交收口执行，逐行）

| 矩阵行 | 现值 | 回写为 | 回写要点 |
|---|---|---|---|
| T2-1 LGF · Bit Logic | ◐ R18 深化 | ◐ R19 深化 | 产出清单 +`FB_DL_BitShiftRegister（R19，补时序层）`；备注追加「组内四层：单点/单段/批量段/**时序移位**至此齐备；剩余仅纯重载，建议标结构性收口」 |
| T2-8 ISA-88 / NE107 | ◐ R18 深化 | ◐ R19 深化 | 产出清单 +`FB_DL_DeviceHealthArbiter（R19）`；备注追加「**NE107 实现块仲裁件已清零**（矩阵明列的最后一项）；`E_DL_Ne107Status` 仍是唯一属主，实现块只引用」 |
| T2-4 Motion Control 示例 | ◐ | ◐ R19 深化 | 产出清单 +`FB_DL_ExternalEncoderScaler`；「外部编码器族」由待挖转**收口**；剩「SynchronousAxis 深层语义」 |
| T1-3 OSCAT Network | ◐ | ◐ R19 深化 | 「RTU 帧长度/字节数一致性校验」由待挖转**收口**（`FC_DL_ModbusRtuFrameCheck`）；剩「ASCII 帧 LRC 定位」（需帧边界状态机） |
| T1-7 PLCnext | ◐ | ◐ R19 深化 | 「PROFINET 诊断（PN_ALARM_DIAG 语义）族」由待挖转**收口**（`FB_DL_ProfinetAlarmDiag`，通道级）；剩「原始诊断记录字节解析层」为下一轮评估项 |
| T1-4 CODESYS Forge | ◐ | ◐ R19 深化 | M-E3 悬置项**关闭**：「参数写回」经终审判定**属设备层**（`FB_DL_DeviceParamWrite`）；DeviceReader 族上下半段齐备 |
| T1-6 PLCopen Motion | ◐ R18 深化 | ◐ R19 深化 | 「凸轮动态修调」由待挖转**收口**（`FB_DL_CamPhaseTrim`） |
| 半导体 ESC 自研 | ◐ | ◐ R19 深化 | 产出清单 +`FB_DL_EscChuckCurrentMonitor`；剩「腔体颗粒计数族」待拆粒度 |
| T0-2/T0-4/T0-5 | ✔ 收口 + 变体 | ✔ 收口 + 补位收口 | R19 兑现 ROADMAP §22.2 四条 P0/P1 承诺（`DintMsToTod`/`TimeRatioCalc`/`RatioToPwrDb`/`LintToUdintSat`）；**T0 补位组清零**，此后 T0 线仅留 DT/DTL 日历族（R64 编译门槛挂账） |

---

## 6 本轮新增观察项（交 ROADMAP / AGENT_EVOLUTION_LOG）

1. **R65｜码位段内信息级耗尽即开新子带**：实测 `0001_` 信息级 02xx 已满至 `02FF`，`0245~028D` 只剩 **63 个碎片洞**（全部位于既有件 3 码块的间隙＝他人预留域）。**R18 交接的「下一可用 0245」是错的** → R19 起信息级开 `04xx` 子带。此条必须固化为**机检规则**（脚本已内建于 `_verify_r19.py`），停止依赖口头交接。
2. **R66｜公开资料语义冲突不得二选一硬编码**：PROFINET `0x001F` 在 CODESYS 与 SIEMENS 两份公开资料中语义不同，本库并列陈述并归保守侧（维护类）。
3. **R67｜测量类块先过采样密度闸再出结果**：自整定类块若采样过疏，测到的是采样网格而非对象特性。
4. **R68｜折算/缩放链「先减法后升位」硬纪律**：32 位计数器回绕展开必须先做 `DINT` 减法再升 `LINT`，否则回绕变巨大正数。
5. **LGF 一线结构性收口的判断依据成形**：矩阵 §2 预估 145~180 件，已出约 110 件，剩余几乎全是纯重载（`Int/UDInt` 版 `SearchMinMax`、`LWord` 累加和、`DWord` 移位显式命名对等），全部被「严禁凑数变体」拦截。**建议下一轮把 LGF 线正式标注「结构性收口」，扩产主线切到 T2-2 LBP 深化 + 行业池 P1。**
6. **许可重灾区提醒**：CODESYS Forge / Store 示例页普遍**未显式声明许可条款**（R9 R12 R19 三次遇到同类），一律按最严口径（只借结构与参数域、零代码行、零注释引用）处置，并在 `.st` 头注释写明该处置。

---

*RAW NOTES R19 ｜ 2026-11-16 15:40 ｜ WebSearch 2 次（PROFINET 诊断枚举 / 继电自整定公式）｜ 18 件零检索复用 ｜ 合规结论：全部可商用*
