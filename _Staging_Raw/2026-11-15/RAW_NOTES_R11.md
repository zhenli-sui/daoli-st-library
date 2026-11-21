# RAW NOTES — Round 11 源狩猎留痕

> 日期：2026-11-15 ｜ 轮次：R11 ｜ 关联计划：`ROUND_PLAN_R11.md`
> 用途：记录本轮 16 件组件的**来源、提取点、借鉴点与 clean-room 边界**，供终审与后续轮次查重（防止同一组重复立项）。
> 铁律：LGF / LBP / Rockwell 等「免费但闭源」文档来源，**只借功能分类、接口参数域、命名组织**；GPL / AGPL 类源**只读思想**；不复制任何代码行、DB 结构、注释原文。
> URL 说明：本轮所有地址均为公开已知入口，**无一条为推测或拼接**；对无法给出稳定 URL 的文档，只引用公开文档编号（如西门子条目号、Rockwell 出版物号），不写伪链接。

---

## 一、T2 类（非 ST，借分类与参数域）

### S-1 ｜ T2-1 LGF V5.3.0 —— Bit Logic 组「位段批量」与 Math 组「距离 / 随机数」

| 项 | 内容 |
|---|---|
| 来源 | 西门子 **Library of General Functions (LGF) V5.3.0** 功能手册（11 个功能组、140+ FC/FB） |
| URL / 文档 ID | 西门子工业在线支持文档条目 **109479728**（support.industry.siemens.com 公开条目，无需登录即可阅读功能清单） |
| 许可证 | **免费使用但闭源版权**（文档与库均受西门子版权约束；可随其产品免费使用，**不可**抽取代码进第三方库） |
| 提取点 | ① Bit Logic 组内「位测试 / 置位 / 位段」的**组内粒度切分**：单点、单段、批量段三层分明；② Math 组 `CalcDistance_2D` / `CalcDistance_3D` 与 `Random_*` 的**参数域**（坐标个数、种子入口、返回值域） |
| 借鉴点 | ① → #6 `FB_DL_StatusWordSegDecoder`：确认「批量段」是独立粒度层级（而非单段函数的循环调用），据此设计段表驱动接口；② → #10 `FC_DL_CalcDistance3D`（**只做 3D，2D 为退化情形，明确拒绝拆成两块**——LGF 拆两块是它自身的组织选择，本库判定为「为凑数拆变体」，矩阵第 3 节禁令优先）；③ → #13 `FC_DL_RandomNext` 的「种子进 / 种子出」参数域 |
| clean-room 边界 | 未接触任何 SCL 源码、未复制 FB/DB 结构、未沿用其引脚名与注释。位段掩码构造、LCG 常数选择（Numerical Recipes 公开参数）、距离缩放保护均为独立实现。码位 `0003_014x` / `0001_012x` / `0002_1F0x` 全部本库自有。 |

### S-2 ｜ T2-2 LBP V2.7 —— 工艺块「命令 → 监视 → 判定」三段分层

| 项 | 内容 |
|---|---|
| 来源 | 西门子 **Library of Basic Processes (LBP) V2.7**（电机控制、阀门、定量、驱动参数化等基础工艺块） |
| URL / 文档 ID | 西门子工业在线支持文档库，条目号见本库 `SOURCE_HUNTING_MATRIX.md` T2-2 行（与 LGF 同属 **109479728 系列**文档库的兄弟条目）；本轮只读到公开的块清单与参数说明页 |
| 许可证 | **免费使用但闭源版权**（同 S-1 口径） |
| 提取点 | 工艺块的**三段式组织**：命令段（cmd）/ 监视段（mon）/ 判定段（eval）职责分离，且判定段与执行段**不共享状态机**——执行态只描述「走到哪一步」，判定只回答「这一步合不合格」 |
| 借鉴点 | #1 `FB_DL_PressFitStation`：把「压装八态」与「包络/特征点判定」切成两段——状态机管推进，`uNgReason` + `stResult` 管判定；这正是本件在 `eEvaluate` 集中出结论、而不在各步内散写 `bNg` 的由来。#4 `FB_DL_EnergySavingMode` 的「模式切换」与「放行门控」分离同理 |
| clean-room 边界 | 未复制 SCL/DB、未沿用其块名与引脚名。压装四特征点算法（接触点线性插值、屈服斜率比、峰值后压降）、节能三阶段次序与门控条件全部自写；故障码 `0005_02Cx`~`02Fx` 自有分段。 |

### S-3 ｜ T2-6 Rockwell AOI —— 设备级粗粒度 + 参数四分段

| 项 | 内容 |
|---|---|
| 来源 | Rockwell / Allen-Bradley **Logix 5000 编程手册（1756-PM010）** 中的 AOI（Add-On Instruction）定义章节：参数分 In / Out / InOut / Local 四段、External Access 等级、ProgFault / OperFault 双故障类 |
| URL / 文档 ID | Rockwell 出版物号 **1756-PM010**（literature.rockwellautomation.com 公开 PDF） |
| 许可证 | **文档版权**（可自由阅读，不可复制结构定义与命名） |
| 提取点 | ① **AOI 粗粒度**：一个 AOI 覆盖「一台设备的多通道/多信号」，而不是「一个信号一个块」；② 四段参数与「组态类故障 / 工艺类故障」分离的归因习惯 |
| 借鉴点 | ① → #7 `FB_DL_NtcTempScan`：1~16 路 NTC 用**一块**覆盖（阻值数组进、温度数组出、通道故障掩码为只读诊断出口），拒绝「每通道一实例」的碎片化；② → #8 `FB_DL_RollerGapAdjust`：组态类码（`0147/0148` 参数钳位）与工艺类码（`0305` 到位超时 / `0306` 反馈丢失）**分段**，HMI 可按类分组显示；③ → #6 的段表结构承载「设备状态字多字段」 |
| clean-room 边界 | 未接触 UDT 布局、未复制 AOI 名称/参数名/内部逻辑。通道掩码语义、B 值换算、背隙两阶段逼近全部独立设计。R10 已确立的「方法 = In 段 / 只读属性 = Out 段 / 诊断结构 = InOut 段」映射本轮继续沿用，但**不新增任何来自 Rockwell 的命名**。 |

### S-4 ｜ T2-4 S7-1500 Motion Control —— 「设定值分层」而非「状态机复制」

| 项 | 内容 |
|---|---|
| 来源 | 西门子 **S7-1500 Motion Control 功能手册**（TIA 信息系统「Motion Control」章节；工艺对象 TO_PositioningAxis / TO_SpeedAxis / TO_SynchronousAxis 的参数与限幅层级） |
| URL / 文档 ID | TIA 信息系统在线帮助（公开可读）；本库台账 T2-4 行 |
| 许可证 | **文档版权** |
| 提取点 | 速度/转矩类工艺对象的**限幅层级**：给定值先经斜坡/限幅，再进闭环，最后才到执行机构限幅；且「工艺给定」与「轴状态机」分属两层，工艺块不重定义轴状态 |
| 借鉴点 | #16 `FB_DL_WindingTensionCtrl`：① 张力给定走「锥度乘子 → 摆辊修正 → 输出限幅」三层，与上述层级同构；② 本件**不新增轴状态枚举**，只用 `bInControl` 表达工艺态，轴状态仍归 `I_DL_MotionAxis`（避免两套状态机并存，R31 风险规避） |
| clean-room 边界 | 未引用任何 TO 对象名、未复制其参数表。锥度公式、摆辊纯比例修正、卷径 mm↔m 换算与降级开环策略均为自有设计；`FB_DL_PidController` 与 `FC_DL_CoilDiameterCalc` 是本库既有件，按真实契约调用。 |

### S-5 ｜ T2-7 / T2-8 PackML + ISA-88 —— 只借「态命名」与「相语义」

| 项 | 内容 |
|---|---|
| 来源 | **ISA-TR88.00.02**（PackML 技术报告，17 态与命令集）、**ISA-88**（批次 Procedure / Unit / Phase 分层） |
| URL / 文档 ID | ISA 官方标准目录（isa.org，技术报告需购买，公开摘要可读）；本库已有 `FB_DL_PackMlStateMachine` 为既有落地件 |
| 许可证 | **公开规范（付费文档）**，语义可自由实现，文本不可复制 |
| 提取点 | ① 工站级状态**最小子集**（Idle / Execute / Held / Aborted 类）而非全集；② 相（Phase）的「前置确认 → 执行 → 终点判据 → 完成」四段结构 |
| 借鉴点 | #2 `FB_DL_RotaryIndexTable` 的五态（Idle/Dwell/Indexing/Settling/Fault）与 #3 `FB_DL_AgvDockingHandshake` 的七态，均取「最小子集 + 明确终止态」；**刻意不做 17 态全集**——全集职责已由既有 `FB_DL_PackMlStateMachine` 承担，#1 的八态也不外溢到工站全集 |
| clean-room 边界 | 未复制状态编号表、未沿用命令字位域（命令字位域属既有 `FB_DL_PackMlCmdDecoder` 的自有实现）。本轮所有态编号（0/10/20/...）为**本库统一的间隔编号惯例**，与 PackML 官方编号无关。 |

---

## 二、T1 类（ST 原生 / 开源社区）

### S-6 ｜ T1-7 PLCnext Community —— port-based 诊断族

| 项 | 内容 |
|---|---|
| 来源 | Phoenix Contact **PLCnext Community** 开源组织（GitHub 组织主页）与其 PLCnext Info Center 的「Diagnostics / Port diagnostics」公开章节 |
| URL / 文档 ID | `https://github.com/PLCnext`（公开组织页）；Info Center 公开在线帮助（`plcnext-community.net` 文档区） |
| 许可证 | 组织内各仓库**许可不一**（MIT / Apache-2.0 / 无声明均有），逐仓核验；Info Center 文档为厂商文档版权 |
| 提取点 | **端口级诊断的四元组**：端口号（1 起）、链路状态（布尔）、端口诊断码（数值）、错误计数（累加器）；以及「端口故障与模块故障分层上报」的组织方式 |
| 借鉴点 | #5 `FB_DL_PortDiagAggregator`：以「掩码 + 首出端口 + 首出码」三出口聚合 8 端口，并用**窗口差分**把累加计数转成「错误风暴」判据（这是端口级诊断相对模块级诊断的独有价值）。R10 已确立的纪律本轮延续：位序与端口索引用本库自有常量，端口状态一律**引脚注入**，不绑定任何厂商系统变量名 |
| clean-room 边界 | 未复制 C++/C# 头文件、未复制其枚举名与函数名、未引用其系统变量命名。UDINT 计数回绕处理（差分为负按归零）、首出仲裁取「端口号最小」、风暴阈值判定均为独立实现；码位 `0003_014x` / `030x` 自有。 |

### S-7 ｜ T1-6 PLCopen —— 状态机分层与「不自造轴状态」

| 项 | 内容 |
|---|---|
| 来源 | **PLCopen TC2（Motion Control 功能块）** 与 TC6（XML 交换格式）公开规范 |
| URL / 文档 ID | `https://www.plcopen.org/`（规范下载需注册，公开摘要与功能块清单可读） |
| 许可证 | 规范免费（注册后下载），实现自由；规范文本不可复制 |
| 提取点 | ① 轴状态（Disabled / Standstill / Discrete Motion / Continuous Motion / ErrorStop 等）**只由运动控制层拥有**；② 工艺层与运动层的边界：工艺块只下发「指令 + 参数」，不参与轴状态判定 |
| 借鉴点 | #16 `FB_DL_WindingTensionCtrl` 只用 `bInControl` 表达「张力环是否在控」，**不定义**任何 `E_DL_AxisState` 同类枚举，也不消费轴状态；#1 的压装态是**工艺态**（Approach/Press/Dwell），与轴状态正交，二者不得混写进一个枚举 |
| clean-room 边界 | 未复制功能块接口、未沿用其状态编号。本库的 `E_DL_AxisState` 早已是自有编号（既有 `I_DL_MotionAxis` 契约），本轮不新增任何轴层类型。 |

### S-8 ｜ T1-2 OSCAT —— 行为定义写法（域外处理）

| 项 | 内容 |
|---|---|
| 来源 | **OSCAT Basic 3.3x / OSCAT Building**（开源 ST 库，暖通与物性计算族） |
| URL / 文档 ID | `https://www.oscat.de/`（官网，含库清单与函数说明） |
| 许可证 | **OSCAT 自有许可**（免费使用、需致谢；具体条款以官网发布的 LICENSE 文本为准）。R10 台账对 Building 分支记为 EPL-2.0 口径——本轮**不复用任何代码**，故不涉及条款判断 |
| 提取点 | 物性/测量函数对**域外输入的行为定义写法**：明确「越界时是保持上次值、返回 0、还是钳位」，并把单位写进引脚名（如 `_C`、`_K`、`_OHM` 类后缀习惯） |
| 借鉴点 | #7 `FB_DL_NtcTempScan`：断线/短路通道**保持上次温度**并在掩码里标出（而不是把 0 °C 当真值下发——0 °C 在锂电烘箱场景是「正常低温」的合法值，伪值会掩盖故障）；参数非法时回退默认并置 `0304`，符合 OSCAT 式「域外行为显式化」 |
| clean-room 边界 | 未复制 OSCAT 函数体、未沿用其函数名与常量名。B 值方程（`1/T = 1/T0 + ln(R/R0)/B`）为公开物理公式，实现与常量（`DL_R_OPEN` / `DL_R_SHORT` / `DL_KELVIN_OFFSET`）自有。**WATER_ENTHALPY 族本轮未采用**：与本库既有 `FC_DL_HumidAirEnthalpy` 的介质口径不同（液态水/蒸汽 vs 湿空气），若立项须先解决职责重叠，不在 R11 硬凑。 |

### S-9 ｜ T1-8 GitHub topics —— 纯函数式 PRNG 的接口形态

| 项 | 内容 |
|---|---|
| 来源 | GitHub topics：`iec-61131-3` / `structured-text` / `plc-library`（社区零散高质量组件） |
| URL / 文档 ID | `https://github.com/topics/iec-61131-3`（公开话题页） |
| 许可证 | **逐仓核验**（MIT / Apache-2.0 优先；未声明者按最严口径只读思想） |
| 提取点 | 社区实现 PRNG 的两种形态：①带内部状态的 FB（`FB_Random` 类）；②**无状态纯函数**（种子进 / 新种子出，由调用方保存种子） |
| 借鉴点 | #13 `FC_DL_RandomNext` 选形态 ②：无实例内存、序列可复现（同种子同序列），便于「通讯压力测试 / 仿真激励」的确定性回放——这是 FB 形态做不到的（FB 实例被多处调用时状态会串） |
| clean-room 边界 | 未复制任何社区实现的递推式与常数。乘子/增量取 **Numerical Recipes 公开经典参数**（1664525 / 1013904223），零种子保护、半开区间后置守卫、`bSat` 出口为本库自有加严；码位 `0001_0123` 自有。 |

---

## 三、本轮证伪 / 未采用（留痕防重复立项）

| 编号 | 候选 | 结论 | 理由 |
|---|---|---|---|
| Q1 | 把 `CalcDistance_2D` 与 `CalcDistance_3D` 拆成两个组件 | **否决** | 2D 是 3D 在 `fZ1 = fZ2` 的退化；拆分属「为凑数拆变体」，违反矩阵第 3 节与「宁少勿滥」 |
| Q2 | 用 `eMode` / `nVariant` 参数把「DWORD 版 / LWORD 版」位段解码合成一块 | **否决** | 宽度是参数域不是语义差异，用 `LWORD` 单入口 + 调用方零扩展即可；带 MODE 的巨无霸块是本库明令禁止的反面教材 |
| Q3 | `I_DL_PowerMeter` & `FB_DL_ModbusPowerMeter`（ROADMAP §4 唯一未勾选行） | **本轮不立项** | 电表本体依赖 Modbus 传输层，而传输调度已由 `FB_DL_ModbusPollMaster` 承担；若立项需先定义「电表数据模型 + 冻结/非冻结寄存器」契约，工作量与 4 件工艺工站冲突，留 R12 |
| Q4 | OSCAT `WATER_ENTHALPY` 落地 | **本轮不立项** | 与既有 `FC_DL_HumidAirEnthalpy` / `FC_DL_AirDensity` 的介质口径存在重叠风险，须先做去重论证（见 S-8 边界） |
| Q5 | 用 `FB_DL_StepSequencer` 作为 #1 压装与 #2 分度盘的基类 | **否决** | 两件的推进条件与监控量强耦合（压力/位移、到位开关），套基类会造成「工站态 + 步序态」两套状态机并存（R31 完备性风险），且基类的步超时语义无法表达包络校验 |
| Q6 | PLCnext port-based 诊断做成「端口 + 模块」双层级一块 | **否决** | 模块级已由 `FB_DL_AxiolineDiagLatch` 承担；混做会形成「一块两种数据源两种码段」，与 R10 已判定的分层冲突 |

---

## 四、配额自证（矩阵第 4 节）

| 要求 | 本轮满足情况 |
|---|---|
| ≥1 组件族来自 T2 非 ST 借鉴源 | **4 个 T2 源**：T2-1 LGF（#6 #10 #11 #12 #13 #14 共 6 件）、T2-2 LBP（#1 #4 #8）、T2-4 S7 Motion（#16）、T2-6 Rockwell AOI（#6 #7 #8） |
| ≥1 组件族来自 T1 ST 原生源 | **4 个 T1 源**：T1-7 PLCnext（#5）、T1-6 PLCopen（#16）、T1-2 OSCAT（#7）、T1-8 GitHub topics（#13） |
| 禁止重复挖掘同一组 | 5 个 LGF 组均为**横向扩族**（Bit Logic 2→3、Math 9→12、Counter 4→5、Comparator 3→4、Date & Timer 5→6），每件在计划书内写明「与既有件边界」；**未触碰** Data Handling / Converter / Signal Generators / Technology / Measurement 五组的已收口部分（Technology 仅经 #16 的锥度语义，属 ROADMAP 明列待办） |
| 每轮战报须列明源 / 借鉴 / 对应组件 | 本文件 S-1~S-9 逐条对应，共 9 条（T2 五条、T1 四条），另 Q1~Q6 六条证伪留痕 |
