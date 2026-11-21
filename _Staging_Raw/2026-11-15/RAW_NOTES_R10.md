# RAW NOTES — Round 10（R10）狩猎留痕

> 日期：2026-11-15 ｜ 配套计划：`_Staging_Raw/2026-11-15/ROUND_PLAN_R10.md` ｜ 记录人：道莅工控代码库产品总监（兜底模式）
> 记录口径：沿用 `SOURCE_HUNTING_MATRIX.md` 第 0 节三条铁律——每个来源必填「来源名称 / URL / 许可证 / 提取点」；闭源资料**只借功能分类体系、接口参数域定义、命名组织方式**，实现一律 clean-room；GPL/AGPL 类源**零代码行接触**（本轮未涉及任何 GPL 源）。
> 检索工具：WebSearch × 6 组（超出「3~5 组」下限要求）｜ 抓取行为：**零原始代码下载**（全部为公开手册/文档的语义级阅读，无 `original_*.st` 落盘）

---

## 0 本轮总体合规声明

1. 本轮 16 个组件全部为「**只借分类 / 参数域 / 命名组织，clean-room 实现**」：未复制任何来源的代码行、DB/UDT 结构布局、注释原文；引脚契约、枚举编号、状态机、故障码位 100% 本库自有设计。
2. 闭源版权资料（Siemens LGF V5.5.0 手册、Rockwell 1756-PM010）仅提取**公开文档中的功能分类与参数域定义**（组名、函数粒度、参数取值范围惯例、故障分类命名），不提取任何实现细节。
3. 开源/公开规范资料（PLCnext 官方在线帮助、OSCAT 文档、公开物理公式）仅借鉴公开语义与参数域；OSCAT 属「免费使用需致谢」许可，本库按最严口径处置为**只读行为定义与公式链，独立实现**。
4. 本轮**未接触任何 GPL/AGPL 源**（OpenPLC / Beremiz / MatIEC 未在检索路径上出现），无许可证传染风险。
5. 本轮 16 件预估 6,180 行，全部按道莅八条红线 + R1~R30 规则库重构（详见 ROUND_PLAN_R10.md 通用要求节）。

---

## 1 本轮来源清单（按源矩阵 T 编号）

| # | 来源名称 | URL | 许可证 | 提取点 | 对应组件 |
|---|---|---|---|---|---|
| **S-1** | Siemens **LGF V5.5.0**（Library of General Functions，SIOS 文档 ID 109479728）· Math operations 组公开手册 | `https://support.industry.siemens.com/cs/attachments/109479728/109479728_LGF_DOC_V5_5_0_en.pdf`（PDF 目录页命中：`LGF_NthRoot (FC/3.0.1) p.90`、`LGF_GetFactorial (FC/3.0.1) p.81`、`LGF_SearchMinMax (FC/3.0.1) p.108` + `_DInt/_LReal/_UDInt` 三个重载件 p.111/113/115） | 免费使用但**闭源版权**（文档版权） | ① Math 组的**组件粒度切分**：把「N 次根 / 阶乘 / 距离 / 极值搜索 / 随机数」切成 5 个独立 FC 而非一个 `Math` 巨块——本库据此把 5 个族各自立项（本轮落 #4~#6，距离/随机留下轮）；② 参数域：「自然数 n 域 0~12、超域置 error + status」的**域 + 状态双出口惯例**（本库改为 `bSat` + `uErrorId`，码位自有）；③ `SearchMinMax` 的「值 + 索引同出」参数域启发本库 #4 的双索引出口 | ④`FC_DL_SearchMinMax` ⑤`FC_DL_NthRoot` ⑥`FC_DL_FactorialSat`（`lgf-math`） |
| **S-2** | Siemens LGF V5.5.0 · **Signal Generators** 组（组内公开函数名清单：正弦/锯齿/脉冲/频率发生） | 同上（组名清单页 + 社区公开解读页 `https://bbs.plcjs.com/thread-652679-1-2.html`） | 同上 | 组内**按「波形形状」切分**的粒度依据（正弦 / 锯齿 / 脉冲 / 频率 各自独立），以及「发生器归本组、限幅归 Technology 组」的组边界——本库据此把 #7 正弦与 #8 锯齿**拆成两块**，并明确禁用 `eWaveform` 枚举合并 | ⑦`FB_DL_SineGenerator` ⑧`FB_DL_SawtoothGenerator`（`lgf-signalgen`） |
| **S-3** | Siemens LGF V5.5.0 · **Technology operations** 组（`LGF_LimRateOfChangeBasic` 等）与 **Bit Logic / Counter / Date and Timer** 组 | 同上（组名与函数清单页） | 同上 | 「位段操作」「双向计数」「周数计算」三组的**功能存在性与参数域**（用确认「这些族尚未被本库收口」，避免重复立项）；Bit Logic 组把「打包 / 提取 / 测试 / 置位」分成 4 类原子操作 → 本库 #1 提取件立项依据 | ①`FC_DL_BitFieldExtract` ②`FC_DL_WeekOfYearCalc` ③`FB_DL_BidirectionalCounter`（`lgf-bitlogic` / `lgf-datetime` / `lgf-counter`） |
| **S-4** | 卷绕工艺公开工程资料（复卷机卷径实时计算原理 / Winder control strategies / Web tension taper） | `https://www.janbochina.com/news/1268.html`；`https://industrialmonitordirect.com/blogs/knowledgebase/winder-control-strategies-speed-vs-torque-mode-for-web-processing`；`https://www.kyautomation.com/news/7050.html` | 公开技术文章（文档版权，仅取公开公式与工程惯例） | ① 三种卷径算法分类：**线速度-角速度法** `r = v/ω`、**长度累积法** `r = sqrt(r₀² + L·h/π)`、直接测量法；② 层厚积分递推 `R = R_core + h·N`；③ 现场纪律：转速过低时编码器量化使直径跳 ±2~5 mm → **必须低速保护 + 一阶低通**（本库 #9 第 2/5 条、#15 第 5 条据此写死）；④ 卷径变化率与锥度张力 `T(D) = T_core·[1 − taper%·(D−D_core)/(D_full−D_core)]`（下轮张力族预留） | ⑨`FC_DL_CoilDiameterCalc`（`lgf-technology`）⑮`FB_DL_WindingTraverse`（次源记 `s7-motion`） |
| **S-5** | **OSCAT** Building 库 `AIR_DENSITY` 行为定义（AixOCAT wiki + OSCAT Building 英文文档） | `https://github.com/RWTH-EBC/AixOCAT/wiki/OSCAT-BASIC-ControlModules`（第 23.36 节）；`https://manualzilla.com/doc/5935136/oscat-building--library-documentation-in-english`（§5.1） | OSCAT 许可（免费使用，需致谢） | ① 行为定义：输入 **T [°C] / P [Pa] / RH [%]**，输出 **空气密度 [kg/m³]**——参数域与单位口径直接采用（本库引脚名 `fTempC/fPressPa/fRh` 自有）；② 饱和蒸汽压用 Tetens/Magnus 式、分压叠加法 `ρ = p_d/(R_d·T) + p_v/(R_v·T)` 为**公开物理公式**（另与 Wikipedia「Density of air」、Buck 1981 口径互证），非 OSCAT 专有算法；③ 本库**收窄声明**：精度承诺仅 -10~50 °C 域（R11 留档），超出域标「趋势参考」 | ⑩`FC_DL_AirDensity`（`oscat-building`） |
| **S-6** | **PLCnext Community** 官方在线帮助 · Axioline F **诊断状态寄存器 / 诊断参数寄存器**系统变量页 | `https://www.plcnext-community.net/robohelp/infocenter/te/Programming/IEC_61131-3/System_variables_Axioline_F.htm` | 官方在线文档（文档版权；系统变量语义公开） | ① 状态寄存器**位语义**：`PF` 外围故障 / `PW` 外围警告 / `BUS` 总线错误 / `RUN` 数据传输中 / `ACT` 组态就绪 / `RDY` 总线就绪 / `SYSFAIL` 系统故障；② 参数寄存器给**错误码**、扩展参数寄存器给**错误位置槽号（从 1 起）**；③ 特例：**无法定位的接口错误显示 128**（bit7 置位）——本库 #13 的 128 特例分支据此写死（不得伪装成 128 号槽）；④ 位序处理：本库以自有 `DL_BIT_*` 常量 + IO 层映射对照表落地，**不猜字节序** | ⑬`FB_DL_AxiolineDiagLatch`（`plcnext-community`） |
| **S-7** | **PLCnext Community** 官方在线帮助 · RSC Axioline Services（**PDI 无环通信**） | `https://www.plcnext-community.net/robohelp/infocenter/te/Communication_interfaces/Remote_Service_Calls_RSC/RSC_Axioline_Services.htm`；社区帖 `https://forum.plcnext-community.net/t/acknowledgment-of-diagnostics-in-i-o-modules-on-right-hand-side/10278` | 官方在线文档（文档版权） | ① **PDI = Parameters, Diagnostics and Information** 术语定义；② `PdiParam` 参数域：`Slot`（设备号）/ `Subslot`（子设备号）/ `Index`（对象索引）/ `Subindex`（对象子索引）；③ `PdiResult` **双码域**：`ErrorCode` + `AddInfo`；④ 工程纪律：「RSC 服务执行耗时长，**避免在实时任务中直接调用**」→ 本库 #14 落为「单拍只发一条 + 忙时拒绝不排队」 | ⑭`FB_DL_PdiReadScheduler`（`plcnext-community`） |
| **S-8** | **Rockwell Automation** · Logix 5000 Controllers Add-On Instructions（出版号 **1756-PM010**，2023-11 版） | `http://literature.rockwellautomation.com/idc/groups/literature/documents/pm/1756-pm010_-en-p.pdf`；官方文档页 `https://www.rockwellautomation.com/en-us/docs/studio-5000-logix-designer/38-00/contents-ditamap/studio-5000-logix-designer/import-and-export/import-add-on-instruction-considerations.html` | 文档版权（免费公开） | ① **参数四分段范式**：`In`（指令）/ `Out`（状态）/ `InOut`（调用方内存别名）/ `Local`（不对外中间量）；② **外部访问等级**表（Input 只读 / Output 只读 / InOut 无外部访问 / Local 可读写）→ 本库映射为「方法 = In 段，只读 PROPERTY = Out 段，诊断结构整体回读 = InOut 段等价物」；③ 设计规划问题清单（指令目的 / 传入什么 / 什么必须外部可见 / 是否需要别名参数 / 参数显示顺序）→ 直接作为 #11 接口设计检查表；④ 「ProgFault / OperFault」双类故障分离思路（组态类 vs 工艺类）→ #12 的 `02F0~02F1` vs `02F2~02F3` 码段划分依据 | ⑪`I_DL_RfidReader` ⑫`FB_DL_RfidTagHandler`（`tcopen-component` + `rockwell-aoi`） |
| **S-9** | **TcOpen** 契约-实现分层范式（本库已开组，R7 沉淀，本轮仅复用范式不新增提取点） | `https://github.com/TcOpenGroup/TcOpen` | Apache-2.0 | 「契约（接口）/ 实现（FB）分离 + 只读属性 + 单发方法 + 命令-应答握手」四件套范式——本轮 #11/#12 沿用它组织 RFID 族，#16 沿用它注入轴/真空引用 | ⑪⑫⑯（范式复用） |
| **S-10** | **PackML / OMAC** 工站状态语义（ISA-TR88.00.02 公开规范 + OMAC 工站建模惯例） | 矩阵 T2-7 台账锚点（公开规范） | 公开规范 | 工站级状态最小子集（Idle / Starting / Execute / Holding/Held / Stopping / Aborted）与「执行态内再分工序步」的层次关系——本库 #16 落 7 态 + 九步序，**刻意不做 17 态全集**（全集已由 `FB_DL_PackMlStateMachine` 承担，避免两套全状态机冲突） | ⑯`FB_DL_PickAndPlaceStation`（`packml-omac`） |
| **S-11** | 本库已入库组件（不作为来源，仅作边界参照） | `C:\Library\DL_*\*.st` | 本库自有 | 与 `FC_DL_WordBitPack` / `FC_DL_DayOfWeekCalc` / `FB_DL_EventCounter` / `FB_DL_ModuloCounter` / `FB_DL_PresetCounterSat` / `FB_DL_SignalStatistics` / `FB_DL_PeakDetector` / `FC_DL_HumidAirEnthalpy` / `FC_DL_DewPointCalc` / `FB_DL_ModbusPollMaster` / `I_DL_BarcodeScanner` / `FB_DL_PackMlStateMachine` 的**职责边界**逐条写出（ROUND_PLAN_R10.md 各件「与既有件边界」小节），确保新增件不与已收口件语义重叠 | 全 16 件 |

---

## 2 许可证与合规裁决一览

| 来源 | 许可证类型 | 处置口径 | 文件头溯源措辞要求 |
|---|---|---|---|
| S-1/S-2/S-3 西门子 LGF 手册 | 免费使用但闭源版权 | 只借功能分类 / 参数域 / 组内粒度；clean-room | 「参考西门子 LGF V5.5.0 公开手册（SIOS 109479728）的功能分类与参数域，clean-room 实现，不构成衍生作品」 |
| S-4 卷绕公开工程文章 | 文档版权 | 只取**公开物理公式**与现场工程惯例（低速保护/低通/层厚积分），不引用原文表述 | 「卷径公式为公开物理关系 `D = v·i/(π·n)`；低速保护与滤波惯例参考公开工程资料」 |
| S-5 OSCAT Building | OSCAT 许可（免费，需致谢） | 只读**行为定义与公式链**，独立实现；常量口径与本库既有件一致但在本件内联 | 「参考 OSCAT Building `AIR_DENSITY` 的输入输出行为定义（T/P/RH → kg/m³），公式为公开 Magnus-Tetens + 分压叠加，独立实现」 |
| S-6/S-7 PLCnext 官方帮助 | 文档版权（语义公开） | 只借位语义 / 参数域 / 工程纪律；**不绑定任何厂商系统变量名**（本库经引脚注入 `uStatusWord/uErrCode/uErrSlot`） | 「参考 PLCnext 官方在线帮助公开的 Axioline 诊断寄存器位语义与 PDI 参数域，本库位序/枚举/码位自有，不绑定厂商对象」 |
| S-8 Rockwell 1756-PM010 | 文档版权 | 只借**参数分段与访问等级思想** + ProgFault/OperFault 分类；UDT 布局/命名/内部逻辑零接触 | 「参考 Rockwell 1756-PM010 公开的参数分段与访问等级思想与故障双分类，clean-room 实现」 |
| S-9 TcOpen | Apache-2.0 | 范式复用（R7 已合规沉淀），可致谢 | 「参考 TcOpen（Apache-2.0）契约-实现分层范式」 |
| S-10 PackML/OMAC | 公开规范 | 状态语义与层次关系提取；全部状态机/枚举自有 | 「参考 ISA-TR88.00.02 公开工站状态语义，状态机实现独立设计」 |

**红线复述**：以上全部来源均**未提供任何可复制的代码行**（S-1/S-6/S-7/S-8 为 PDF/HTML 文档，S-4/S-5 为公式与行为描述），因此本轮**无「改写自 XXX 源码」的组件**，全部 16 件均为「原创实现（参考 XXX 分类与参数域）」。

---

## 3 检索过程记录（6 组定向检索，含被否决的路径）

| 组 | 检索式 | 命中要点 | 否决/降级判断 |
|---|---|---|---|
| Q1 | `Siemens LGF "Library of General Functions" Math group MIN MAX with index factorial nth root distance random number` | 命中 LGF **V5.5.0 官方 PDF 目录**（函数名 + 页码 + 版本号），确认 `NthRoot`/`GetFactorial`(0~12, status 16#8101)/`SearchMinMax` 四重载/`CalcDistance_2D/_3D`/`Random_*` 全部存在 | 采纳。**否决**「用社区解读页作为唯一依据」——社区页仅用于交叉验证组件清单，参数域一律以官方 PDF 目录 + 官方函数名为准 |
| Q2 | `PLCnext Community github open source function block library structured text Phoenix Contact` | 命中 PLCnext 官方社区站与编程信息中心；确认「GitHub 上有开源示例（C++/C#/MQTT/Node-RED/Docker 为主）」 | **降级**：PLCnext GitHub 以 C++/C# 示例为主，**ST 原生开源库稀少**，故本库 T1-7 的提取点从「抄 ST 组件」改为「借官方公开的**诊断寄存器语义与 PDI 参数域**」——这是一个诚实的降级，已写入矩阵回写备注 |
| Q3 | `Rockwell Add-On Instruction ProgFaults OperFaults parameters 1756-PM010 design considerations` | 命中 1756-PM010 原文 PDF 片段：参数分段（In/Out/InOut/Local）、External Access 等级表、设计规划问题清单 | 采纳（仅分类思想）。**否决**「按 AOI 的 UDT 成员逐项仿写」——那是结构复制，违反铁律 1 |
| Q4 | `OSCAT Basic library AIR_DENSITY humid air density formula source code` | 命中 AixOCAT wiki §23.36 `AIR_DENSITY(T[°C], P[Pa], RH[%]) → kg/m³` 与 OSCAT Building 文档 §5.1；同时命中 Wikipedia/Buck 的公开密度公式链 | 采纳行为定义 + 公开公式。**否决**「下载 OSCAT 源码逐行改写」——OSCAT 许可要求致谢且本库按最严口径只读行为定义 |
| Q5 | `PLCnext Axioline module diagnostics status word PDI port quality GOOD BAD UNCERTAIN` | 命中 `System_variables_Axioline_F` 页（PF/PW/BUS/RUN/ACT/RDY/SYSFAIL 位语义 + 参数寄存器 + 槽号 + 128 特例）；同时发现 **PDI = Parameters/Diagnostics/Information**（并非「质量码」） | **规格修正**：初稿设想的「PDI 质量码聚合器（GOOD/BAD/UNCERTAIN）」被证伪——PLCnext 的 PDI 是参数/诊断/信息对象而非 OPC UA 式质量码。**改为** `FB_DL_AxiolineDiagLatch`（诊断寄存器解析）+ `FB_DL_PdiReadScheduler`（PDI 对象读取调度）。此修正记录于此，防止下轮重复立项（R30 精神：以核对结果为准） |
| Q6 | `winding roll diameter calculation line speed angular velocity formula unwind rewind traverse` | 命中 `r = v/ω`、`D = MPM/(RPM·π)`、层厚积分 `R = R_core + h·N`、低速量化噪声 ±2~5 mm 需低通、锥度张力公式 | 采纳为公开物理关系。**否决**「直接搬某驱动器厂商的卷径功能块参数表」（闭源且带品牌语义） |

**检索总量**：6 组检索式 → 命中有效来源 8 个（S-1~S-8）+ 规范 2 个（S-9/S-10）→ 产出 16 件规格。**1 条规格被证伪并当场修正**（Q5 的 PDI 质量码假设）。

---

## 4 矩阵回写计划（`SOURCE_HUNTING_MATRIX.md` 第 5 节，入库后执行；本轮不改矩阵本体）

| 矩阵行 | 状态变更 | 新增组件 | 备注（写入矩阵第 5 节「备注」列的原文） |
|---|---|---|---|
| T2-1 LGF · Bit Logic | ◐→◐ 深化 | `FC_DL_BitFieldExtract`（累计 3） | 与 `FC_DL_WordBitPack` 构成「打包-提取」逆运算对；DWORD/LWORD 数组批量位段族仍待挖 |
| T2-1 LGF · Date and Timer | ◐→◐ 深化 | `FC_DL_WeekOfYearCalc`（累计 5） | ISO-8601 周四归属法；跨年归属（12-31 属次年第 1 周）为独立语义，勿与 `DayOfWeekCalc` 合并；年窗/天文钟族待挖 |
| T2-1 LGF · Counter | ◐→◐ 深化 | `FB_DL_BidirectionalCounter`（累计 4） | CTUD 全语义（CU+CD+双预设）；与 `PresetCounterSat` 的「倒置冻结 vs 倒置不冻结」策略差异已文档化 |
| T2-1 LGF · Math | ◐→◐ 深化 | `FC_DL_SearchMinMax`、`FC_DL_NthRoot`、`FC_DL_FactorialSat`（累计 9） | LGF V5.5 官方 4 个 `SearchMinMax*` 重载中，LREAL 主线落地；DInt/UDInt 重载、`CalcDistance_2D/_3D`、`Random_*` 六件、矩阵运算族待挖 |
| T2-1 LGF · Signal Generators | ◐→◐ 深化 | `FB_DL_SineGenerator`、`FB_DL_SawtoothGenerator`（累计 5） | 按「波形形状」切块，禁 `eWaveform` 合并；频率发生/脉冲族待挖（脉冲已有 `FB_DL_PulseGenerator`，需评估职责） |
| T2-1 LGF · Technology | ◐→◐ 深化 | `FC_DL_CoilDiameterCalc`（累计 11） | 卷径速度比法；层厚递推 + 排线执行落 `FB_DL_WindingTraverse`（主源本行、次源 T2-4）；锥度张力族待挖（ROADMAP `FB_DL_WindingTensionCtrl`） |
| **T2-6 Rockwell AOI** | **☐→◐ 开组** | `I_DL_RfidReader` + `FB_DL_RfidTagHandler`（累计 2） | AOI 参数四分段 + External Access 等级 → 本库「方法/只读属性/诊断结构/局部」四段；ProgFault/OperFault → 组态类/工艺类双码段；1756-PM010 文档版权，clean-room；设备级 AOI 粒度族（阀/电机/夹爪）待挖 |
| **T1-7 PLCnext Community** | **☐→◐ 开组** | `FB_DL_AxiolineDiagLatch`、`FB_DL_PdiReadScheduler`（累计 2） | **实测降级**：PLCnext GitHub 以 C++/C# 示例为主，ST 原生库稀少 → 提取点定为「官方公开的诊断寄存器位语义 + PDI（Parameters/Diagnostics/Information）参数域 + 无环通信纪律」；**纠正**：PDI 并非「质量码」，原设想的质量码聚合件已撤销（见 RAW_NOTES_R10 Q5）；PROFINET 诊断（PN_ALARM_DIAG 语义）、port-based 诊断族待挖 |
| T1-2 OSCAT Building | ◐→◐ 深化 | `FC_DL_AirDensity`（累计 4） | AIR_DENSITY 行为定义落地；`WATER_ENTHALPY` / `DEW_TEMP` 族待挖（后者需评估与 `FC_DL_DewPointCalc` 职责重叠） |
| T1-5 TcOpen | ◐（不新增件） | — | 本轮 #11/#12 主源记 T2-6 行，本行仅记「范式复用」，**不重复记账**（沿用 R8/R9 记账纪律） |
| T2-4 S7-1500 Motion | ◐（次源） | — | `FB_DL_WindingTraverse` 的排线轴往复 + 端点 dwell 语义参考 S7 TO 的 positioning 行为，主源记 LGF Technology 行 |
| T2-7 PackML / OMAC | ◐→◐ 深化 | `FB_DL_PickAndPlaceStation`（累计 5） | 工站级 7 态最小子集 + 执行态内九步序；**刻意不做 17 态全集**（全集已由 `FB_DL_PackMlStateMachine` 承担）；配方切换/批次编排（ISA-88 衔接）仍待挖 |

---

## 5 配额自检（矩阵第 4 节硬性要求）

- **T2 非 ST 源 ≥ 1 组件族**：LGF 五组深化（Bit Logic / Date and Timer / Counter / Math / Signal Generators / Technology 共 6 组）+ **T2-6 Rockwell AOI 首次开组**（2 件）+ T2-7 PackML（1 件）→ **满足**。
- **T1 ST 原生源 ≥ 1 组件族**：**T1-7 PLCnext Community 首次开组**（2 件）+ T1-2 OSCAT Building 深化（1 件）+ T1-5 TcOpen 范式（2 件）→ **满足**。
- **禁止重复挖掘同一组**：涉及组全部为「横向扩族 / 首次开组」，每件与同组已入库件的职责边界在规格内逐条写死（`ROUND_PLAN_R10.md` 各件「与既有件边界」）；未触碰任何已收口组 → **满足**。
- **扩产 5 规则使用**：数据类型重载 0 次（避免与 R9 已收口重载族撞）/ 阶数变体 1 次（#8 对称度参数化）/ 协议方言 0 次 / 行业工况 1 次（#16 通用工站）/ 精度变体 1 次（#4 双索引出口 + 非有限过滤）。**全部 16 件无 `MODE`/`eMode` 型多职责巨无霸参数** → **满足**（#15 的 `bUseInjectedDia` 为单一数据源仲裁，非模式枚举，已在规格中声明）。

---

## 6 留痕归档

- 本文件：`C:\Library\_Staging_Raw\2026-11-15\RAW_NOTES_R10.md`（与 `ROUND_PLAN_R10.md` 同日归档；R4~R9 历史文件原样保留，未覆盖）。
- 各组件 `.st` 头「开源溯源 (Origin)」字段措辞须与本文件第 1 节逐一对应（第 2 节给出句式模板），入库终审逐件核对。
- **本轮零原始代码抓取** → 不新建 `_Staging_Raw\<来源>_<日期>\original_*.st` 子目录；若终审裁定某件需补原始对照，届时按目录契约补 `README_SOURCE.md`（必填：来源 URL / 版本锚点 / 抓取时间 / 原始协议 / 商用结论 / 处置）。
- **被证伪的规格已留痕**（第 3 节 Q5）：初稿「PDI 质量码聚合器」→ 撤销，改为诊断寄存器解析 + PDI 读取调度；此条同时作为 R31 候选规则素材：**「来源术语先证伪再立项：凡以缩写（PDI/AR/LGF 组名）为立项依据的组件，必须先核实该缩写在来源文档中的定义，禁止凭缩写联想设计」**（待 R10 复盘会正式入册）。

---

*Round 10 狩猎留痕 ｜ 2026-11-15 ｜ 道莅工控代码库产品总监（兜底模式）*