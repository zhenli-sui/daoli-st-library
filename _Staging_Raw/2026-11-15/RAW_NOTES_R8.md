# RAW_NOTES_R8 —— Round 08 狩猎检索记录

> 轮次：R8（2026-11-15）｜ 方向：**DL_Motion 扩容 6 项**（电子齿轮/电子凸轮/龙门同步/力矩限制压装/色标位置锁存/梯形耗时估算）+ **DL_Process 扩容 6 项**（SMEMA 级联握手/配方管理/气密检漏/混合工艺相/CIP 清洗/多层料仓）+ **DL_Device 收尾 1 族 2 项**（安灯塔契约 + 实现）+ **DL_Algo 补 2 项**（峰值检测/分级步进控制）
> 执行人：道莅工控代码库产品总监（兜底模式；原生专家类型不可用）
> 检索时间：2026-11-15（R8 计划阶段，共 14 次 WebSearch，全部记录于下）
> 合规基线：`SOURCE_HUNTING_MATRIX.md` 第 0 节三条铁律。**闭源免费资产（西门子 LGF / LBP / 厂商手册 / 论坛教程）只提取「功能分类体系、接口参数域、命名组织方式、状态机语义」；实现全部 clean-room 独立编写，不复制任何代码行、DB 结构、注释原文。** GPL/AGPL 源本轮零引用。
> 本轮新增实证结论 3 条（均改变计划）：**①** LBP V2.8 实测无「混合 / 定量」功能组（仅 Mtr / Vlv / Ana / Cntr / Ctrl / Intlk / Msg 七类），矩阵第 2 节假设需修正；**②** LGF V1.0.1 官方文档目录显示「统计 / 峰值 / 最小最大值」落在 **Math operations 组**内，而非独立的 Measurement 组；**③** 本库 `I_DL_MotionAxis` 仅暴露实际速度/位置，无指令位置与扭矩域——电子齿轮的 MasterValueSource（指令/实际）与力矩限制的扭矩反馈必须经引脚注入，构成规格级已知限制（R11 留档）。

---

## S-1｜PLCopen MC_GearIn / MC_GearInPos 电子齿轮语义（本轮 `FB_DL_ElectronicGear`，T1-6 PLCopen 深化）

| 项 | 内容 |
|---|---|
| 来源名称 | ① PLCopen「Function blocks for motion control」V2.0 官方规范（附录 B 合规清单 3.38 MC_GearIn / 3.40 MC_GearInPos 引脚表）② infoPLC 镜像 Part 2 扩展版（MC_GearInPos 参数逐条 + 时序图 + 同步窗语义）③ Beckhoff TF5200 编程手册 MC_GearIn 命令页 ④ Unitronics UniLogic 多轴 MC 指令帮助（CatchUp / SlowDown 能量差异） |
| URL | ① https://www.plcopen.org/download_file/a42eeb14-a0d3-4163-a3f3-eac74244be21/488/ ② https://www.infoplc.net/files/documentacion/estandar_programacion/infoPLC_net_FB_MotionControl.pdf ③ https://infosys.beckhoff.com/content/1033/tf5200_programming_manual/208379531.html ④ https://www.unitronicsplc.com/Download/SoftwareHelp/!UniLogicWebhelp2024/Motion_Servo/Multi-Axes_MC_(EtherCAT).htm |
| 许可证 | ① PLCopen 规范（公开发布，版权文档，可免费下载）②③④ 公开技术文档 / 厂商帮助（版权文档，免费查阅）。**均属「可借鉴接口参数域、禁止复制代码」类** |
| 提取点 | ① **参数域三分**：`RatioNumerator / RatioDenominator`（整数比值对，非浮点 ratio——避免浮点传动比累积误差）+ `Acceleration / Deceleration / Jerk`（啮合过渡动力学，**不是**稳态动力学）+ `MasterValueSource`（指令值 / 实际值耦合）；② **输出语义分离**：`InGear`（稳态啮合）/ `Busy` / `Active` / `CommandAborted` / `Error` 五出口，啮合完成与执行中严格区分——本库映射为 `bInGear` / `bBusy` / `bActive` / `bError`；③ **连续更新**：`ContinuousUpdate` 允许运行中改传动比，未置位时新比值必须等下个 Execute 沿——本库取为 `bContinuousUpdate` 引脚 + 拒绝时信息级码；④ **GearInPos 同步窗**：`MasterStartDistance / MasterSyncPosition / SlaveSyncPosition` 定义「从轴在何处开始追赶」与「何处进入同步」，`StartSync` / `InSync` 双沿事件——本库简化为「啮合过渡段（eSynchronizing）」单态，**不实现位置对齐式（GearInPos）**，理由见下；⑤ Beckhoff 补充：比值 ≤0 或未指定时取轴默认动力学，`PhaseShift` 相位补偿在自动相位补偿模式下生效——本库相位补偿以 `fPhaseGain`（比例式，非 PID）+ `fPhaseMax` 限幅实现，避免在轴外层再套一层积分器 |
| 拟平移组件 | `FB_DL_ElectronicGear`（电子齿轮：整数比值 + 相位补偿 + 啮合/脱开状态机） |
| clean-room 声明 | 仅提取「整数比值对、过渡动力学与稳态动力学的区分、五出口语义、连续更新门控」四项**接口与语义分类**；引脚命名、枚举、故障码、状态机跃迁、相位补偿控制律 100% 本库自有设计，未复制任何 PLCopen 示例代码或厂商实现 |
| 规格级已知限制（R11） | 本库接口无「指令速度」属性，`MasterValueSource` 无法在块内切换——**统一取 `iMaster.fVelocity`（实际速度）耦合**，等效于 PLCopen 的 actual-value coupling；指令值耦合留待接口升版（不在本轮改动接口，避免破坏既有 6 实现块） |

## S-2｜PLCopen MC_CamIn 电子凸轮与飞剪相位（本轮 `FB_DL_ElectronicCam`，T1-6 PLCopen 深化）

| 项 | 内容 |
|---|---|
| 来源名称 | ① 汇川/CODESYS SoftMotion 中文指令手册 MC_CamIn 页（主从偏移、缩放、周期、触点计算公式）② ABB AC500 PLCopen 库 MC_CamIn 页（凸轮表采样公式与 MasterStartDistance 方向语义）③ PLC 技术网「S7-1500 ST 电子凸轮 + 飞剪」实战帖（MasterOffset 相位微调、同步段要求）④ 非周期追剪技术文（动态相位偏移 + 追剪触发计算） |
| URL | ① https://docs.we-con.com.cn/bin/view/Codesys%28LX6C%29/3%20Motion%20control%20instructions/3.06%20Multi-axis%20instruction/3.6.05%20MC_CamIn/ ② https://help.plc.abb.com/Libraries/AB290/ABB%20-%20AC500/Use%20Cases/Motion/ABB_MotionControl_AC500_Library/01_PLCopen/MC-MultiAxis/MC_CamIn.html ③ https://bbs.plcjs.com/thread-522441-1-460.html ④ https://www.hqwc.cn/a/1543139.html |
| 许可证 | 全部为公开技术文档 / 论坛教程 / 厂商帮助（版权文档，免费查阅），仅借鉴语义 |
| 提取点 | ① **主从位置关系式**：`SlavePos = SlaveScaling × Cam(MasterScaling × MasterPos + MasterOffset) + SlaveOffset`——本库据此定义「主轴相位归一化 → 表插值 → 缩放偏移」四段链，参数域完全同构但命名自有；② **周期语义**：`Periodic` 复位凸轮表相位（每周期回绕），非周期时到表尾置 `EndOfProfile`；③ **相位微调是飞剪核心**：`MasterOffset` 运行中平滑改动即可补偿张力/机械误差引起的切点漂移——本库落为 `fPhaseShift` 引脚（叠加在 MasterOffset 之上，二者分离：offset 为配方固定相位，phaseShift 为运行微调）；④ **凸轮表要求**：主轴值必须**单调递增**且同步段内主/从值严格对应（否则切割拉扯物料）——本库强制单调性校验并置故障码；⑤ **方向语义**：`MasterStartDistance > 0` 时主轴必须正向旋转才同步，负值需反向——本库以 `bDirNegative` 引脚显式声明期望主轴方向，方向不符即等待（信息级）不报故障；⑥ 表尾速度应为 0（从轴不做斜坡退出）；⑦ 每周期点为分段线性（`ram_in` 族属供应商扩展，**不实现**） |
| 拟平移组件 | `FB_DL_ElectronicCam`（电子凸轮：分段线性表 + 周期/非周期 + 相位偏移 + 缩放） |
| clean-room 声明 | 仅提取第 ① 条的位置关系式结构（属公开数学定义）、周期语义、相位偏移的工程作用；表结构（`VAR_IN_OUT` 双 REAL 数组 + 点数引脚）、插值实现、单调性校验、故障码、状态机均为本库自有；未复制任何 SoftMotion / ABB 源码或 XML 凸轮表格式 |
| 规格级已知限制（R11） | 不实现 `MC_CamTableSelect` 分离式表句柄（本库用数组直传，避免引入表对象与句柄生命周期管理）；不实现 `Tappets`（凸轮开关量，HMI 用）。从轴定位经 `iSlave.MoveAbsolute` 每拍一次（公约 0.13），故同步精度受扫描周期限制，头注释必须声明「逻辑层同步，非硬实时插补」 |

## S-3｜双驱龙门同步与偏斜保护（本轮 `FB_DL_GantrySyncAxis`，T1-6 / T2-4 双源深化）

| 项 | 内容 |
|---|---|
| 来源名称 | ① Industrial Monitor Direct「Beckhoff AX5000 双编码器龙门组态」（1:1 齿轮耦合、同步偏差 0.5 mm 锁存、停止类别映射）② Beckhoff TF5200 SOFT-GANTRY 章节（**两级位置差监视**：第一级可复位、第二级不可复位）③ SV-JME 论文「宽跨距龙门吊防偏斜控制器」（偏差 → 速度修正量、增益限幅）④ 西门子 840D 龙门参数（MD37110 位置公差 0.05~0.20 mm） |
| URL | ① https://industrialmonitordirect.com/it/blogs/knowledgebase/configuring-dual-encoders-on-beckhoff-ax5000-for-gantry-drives ② https://infosys.beckhoff.com/content/1033/tf5200_programming_manual/207126155.html ③ https://www.sv-jme.eu/wp-content/uploads/ns_articles/files/ojs3/1478/submission/1478-1-1976-1-2-20171103.pdf ④ https://industrialmonitordirect.com/blogs/knowledgebase/siemens-840d-alarm-300701-x2-drive-startup-troubleshooting |
| 许可证 | ①②③④ 公开技术文章 / 厂商帮助 / 公开论文（版权文档，免费查阅），仅借鉴语义与参数域 |
| 提取点 | ① **两级监视是本块骨架**：预警阈（偏差超限先降速/告警）与故障阈（超限立即双轴停）分离，且**预警阈必须 < 故障阈**——本库据此设 `fDevTolWarn` / `fDevTolFault` 双引脚并在启动做「对调自修复」（沿用 AnalogValve 先例）；② **偏差定义**：主从实际位置差 `Δ = PosMaster − PosSlave`，典型报警窗 0.5~3 mm（2000 kg 卷材龙门 1~3 mm，精龙门 0.05~0.2 mm）；③ **单轴故障时的不对称风险**：一轴报跟随误差后另一轴仍跟踪 30~35 ms，可造成 3~5 mm 额外偏移 → **本块在检测到任一轴故障时同拍输出双轴停止请求**（不做「健康侧继续」策略，安全侧保守）；④ **纠偏律**：偏差 → 从轴速度修正量（比例增益 + 修正量限幅），滞后侧加速、超前侧减速——本库以 `fCorrGain`（1/s）+ `fCorrSpeedMax` 限幅实现，且 `bCorrectEnable=FALSE` 时只监视不纠偏；⑤ 啮合建立即 1:1 齿轮耦合，联轴前必须双轴同速（本块以 `fCoupleSpeed` 慢速同步建立） |
| 拟平移组件 | `FB_DL_GantrySyncAxis`（龙门双驱同步 + 两级偏斜监视 + 双轴停 + 可选纠偏） |
| clean-room 声明 | 仅提取「两级阈值 + 偏差定义 + 单轴故障双停 + 比例纠偏限幅」四项公开工程语义；状态机、引脚命名、故障码、对调自修复策略为本库自有（对调自修复为本库既有公约，非来源） |
| 定位声明 | 本块为**逻辑层同步监视与纠偏编排**，不构成认证安全功能（公约 0.13）；机械偏斜的最终保护由硬件限位与安全回路承载 |

## S-4｜伺服力矩限制与固定挡块压装（本轮 `FB_DL_TorqueLimitControl`，T1-6 PLCopen 深化 + 压装工艺）

| 项 | 内容 |
|---|---|
| 来源名称 | ① 西门子官方支持「S7-1500(T)+V90 PN 转矩限幅及固定停止点检测」（MC_TorqueLimiting Mode=0 限幅 / Mode=1 固定挡块，InLimitation / InClamping 输出）② Industrial Monitor Direct「SINAMICS S120 MC_TorqueLimiting」（p2630~p2635 参数域：挡块力矩 30%、检测窗 10 mm、最长 30 s、力矩斜率 100%/s） |
| URL | ① https://www.ad.siemens.com.cn/productportal/Prods/V90_Document/06_TorqueControl/05_1500TOTorqueLimitAndToFixedStop/1500TOTorqueLimitAndToFixedStop.htm ② https://industrialmonitordirect.com/ro/blogs/knowledgebase/sinamics-s120-torque-limiting-with-mc-torquelimiting-on-s7-1500 |
| 许可证 | 西门子官方支持文档 + 公开技术文章（版权文档，免费查阅）；**闭源免费资产**，仅借鉴参数域与状态语义 |
| 提取点 | ① **两种模式分离**：Mode=0 纯力矩限幅（收放卷速度环饱和）、Mode=1 运行到固定挡块（压装）——本库**只做 Mode=1 语义**（压装判定），限幅本身归驱动，避免巨无霸 MODE 巨无霸块（矩阵第 3 节禁令）；② **参数域**：挡块力矩（额定百分比）、位置检测窗（mm）、到达挡块最长时限（s）、力矩上升斜率；③ **判定出口**：`InClamping` 到位 → 保持计时 → 位移窗口合格判定（压装「是否压到位」）；④ **现场提示**：软件力矩限制不是安全功能，机械限位仍是安全边界（写入本块头注释）；压装速度取接近速度的 1/10（本库以 `fApproachVel` / `fPressVel` 双引脚落地）；⑤ 到达挡块后停留计时从「力矩实际达限」起算，而非固定时间 |
| 拟平移组件 | `FB_DL_TorqueLimitControl`（力矩限制压装：接近 → 压装 → 达限保持 → 位移窗判定 → 释放） |
| clean-room 声明 | 仅提取参数域（百分比 / mm / s / 斜率）与「接近-压装-达限-保持-判定」五段语义；状态机、判定逻辑、故障码自有。**不实现 MC_TorqueLimiting 的限幅指令本身**（本库接口无扭矩域，扭矩与达限状态经引脚注入） |
| 规格级已知限制（R11） | `I_DL_MotionAxis` 无扭矩属性：`fActTorque` / `bTorqueLimitActive` / `bInClampFeedback` 三个引脚由驱动适配层注入；头注释须写明「本块为判定层，力矩限幅由驱动器参数（如 p2630 族）承担」 |

## S-5｜位置跟随误差监视（本轮决策记录：**不新建跟随误差块**，语义并入 `FB_DL_MarkPositionLatch` 与既有 `FB_DL_SoftLimitGuard`）

| 项 | 内容 |
|---|---|
| 来源名称 | ① PLCcode.ai「伺服跟随误差故障」② 西门子 SIMOTION 轴监视功能（动态跟随误差：低速常数门限 / 高速线性门限 + 警告百分比）③ 施耐德 Machine Expert `FB_Drive_PosControl`（`i_lrMaxPositionDiff` 负值即禁用监视） |
| URL | ① https://plccode.ai/servo-following-error-faults ② https://www.ad.siemens.com.cn/Download/documentdetail_7179.html ③ https://product-help.schneider-electric.com/Machine Expert/V2.1/zh/ExmLG/ExmLG/FB_Drive_PosControl-GeneralInformat-CAA8D18A.html |
| 许可证 | 公开技术文章 / 厂商帮助文档（版权，免费查阅） |
| 提取点 | ① 跟随误差 = 指令位置 − 实际位置，**门限随速度线性放大**（低速常数、高速线性）才是工程正解；② 驱动器与 NC 已内置该监视（V90 p2546、S120、TO FollowingError.Tolerance），PLC 侧重复实现价值低且永远慢一拍；③ 本库接口不暴露指令位置 → PLC 侧无法得到真实跟随误差（只能得「上一拍位置差」的伪量） |
| **决策** | **不新建 `FB_DL_FollowErrorMonitor`**。理由：① 与驱动器内置监视重复，违反「不重复造轮子」；② 本库接口无指令位置域，硬造需上层喂 `fCmdPos`，属伪需求；③ 本库已有 `FB_DL_SoftLimitGuard`（制动距离预判）+ 本轮 `FB_DL_GantrySyncAxis`（主从偏差监视）覆盖了「轴与轴之间」的偏差监视。**该结论回写 ROADMAP 作为「已评估不采纳」条目**，防止后续轮次重复立项 |

## S-6｜CODESYS Forge 配方管理（本轮 `FB_DL_RecipeManager`，**T1-4 CODESYS Forge 首次开组 ☐→◐**）

| 项 | 内容 |
|---|---|
| 来源名称 | ① CODESYS Forge 官方示例「Recipe Management」（RecipeManCommands / SimpleRecipeManagement 两个应用，演示配方读写与 `RecipeManagement` 库编程接口）② CODESYS Forge designpatterns 项目 UNLICENSE 文件页 ③ CODESYS Forge 论坛「Recipe manager need license?」（配方管理器免授权） |
| URL | ① https://forge.codesys.com/prj/codesys-example/recipe-manageme/home/Home/?version=2 ② https://www.forge.codesys.com/prj/designpatterns/code/1/tree/Tags/UNLICENSE.rst ③ https://forge.codesys.com/forge/talk/Engineering/thread/2b025dc780 |
| 许可证 | ① 示例项目（Forge 示例，页面未显式声明许可证 → 按**仅借鉴结构、不复制代码**处置）② designpatterns 项目为 **UNLICENSE（公有领域）** ③ 论坛说明（免授权，非代码） |
| 提取点 | ① **配方 = 「变量清单 + 值集」**（recipe definition 定义变量列表，recipe 为其中一组值）——本库据此定义 `ST_DL_RecipeEntry`（名称 + 参数数组 + 校验和）；② **两类接口分层**：简易命令式（读/写整份配方）与编程接口式（逐条访问）——本库只做命令式（`bLoad` / `bSave` / `bValidate`），不做文件 I/O（**文件持久化不入库**，由调用方经 `VAR_IN_OUT` 数组承担，符合「零全局耦合 + 可移植」红线）；③ 配方切换前必须校验（参数存在性 / 类型 / 越界）；④ 免授权，可放心对标 |
| 拟平移组件 | `FB_DL_RecipeManager`（配方选择 / 校验 / 应用 / 写回 / 变更审计） |
| clean-room 声明 | 仅提取「变量清单 + 值集」的配方抽象与「校验 → 应用」的顺序；**不引入 CODESYS `RecipeManagement` 库依赖、不复制任何示例代码、不实现文件读写**（保持三平台可编译）。本库以数组 + 校验和 + 越界审计实现，属独立设计 |

## S-7｜SMEMA 级联握手（本轮 `FB_DL_ConveyorLineLink`，包装 / SMT 线体工程惯例）

| 项 | 内容 |
|---|---|
| 来源名称 | ① Industrial Monitor Direct「SMEMA 信号测试仪」（SMEMA v1.2 / IPC-SMEMA-9851：BOARD_AVAILABLE 上游→下游、BOARD_REQUESTED 下游→上游，干接点，24 VDC）② 「The SMEMA Standard Explained」（14 针引脚：9/10 Machine Ready、11/12 Board Available、3/4 Good-Bad Board）③ 「SMEMA vs HERMES 指南」（消抖 20~30 ms、传递窗 200~500 ms、传输看门狗 5 s + INH 抑制上游） |
| URL | ① https://industrialmonitordirect.com/zh-hans/blogs/knowledgebase/smema-signal-tester-building-a-pcb-conveyor-communication-test-box ② https://eathealthy365.com/the-smema-standard-explained-from-pins-to-production/ ③ https://www.chuxin-smt.com/smema-vs-hermes-ultimate-guide-reflow-conveyor/ |
| 许可证 | 公开技术文章（版权文档，免费查阅）；SMEMA 标准本体已并入 IPC-SMEMA-9851（付费标准，**未获取原文，仅用第三方公开摘要的语义**） |
| 提取点 | ① **四信号握手**：Board Available（上游有板）/ Machine Ready（下游可收）/ INH（下游强制上游停送）/ Good-Bad（可选质量位）——本库落为 `bUpBoardAvailable` / `bDownMachineReady` / `bDownInhibit` / `bBoardQualityNg`；② **传输判据**：BA 与 MR 同真才启动传输；板离开上游（BA 落）且到达下游（入口光电亮）即握手复位；③ **时间域**：硬件滤波之外再加 20~30 ms 软件消抖；传递窗 200~500 ms 保持；看门狗 5 s 超时 → 报警 + 拉 INH；④ **线体节拍**：快机等慢机（等待而非堆料），这是 SMEMA 的核心价值；⑤ 命名差异大（OEM 各自定义引脚），故本库只抽象语义、不绑定引脚号 |
| 拟平移组件 | `FB_DL_ConveyorLineLink`（双向级联握手协调器：BA/MR/INH 四信号 + 消抖 + 传输看门狗 + 维护直通） |
| clean-room 声明 | 仅提取公开的四信号语义与时间域工程经验值（消抖/传递窗/看门狗）；状态机、引脚命名、故障码、与 `FB_DL_ConveyorZone` 的 `bZoneReady` 衔接方式为本库自有 |

## S-8｜压降法气密检漏（本轮 `FB_DL_LeakTestStation`，锂电 / 半导体 / 汽车通用工站）

| 项 | 内容 |
|---|---|
| 来源名称 | ① 中科光析「压力衰减泄露检测」（准备/充气/稳压/保压测量四阶段 + 温度补偿必要性 + 传感器精度 0.1% FS）② Industrial Monitor Direct「球阀压降检漏」（**测量前必须隔离所有压力源**，ΔP 计算与泄漏率 = ΔP×V/t，参考容积法）③ Zaxis「Pressure Decay 买家指南」（Fill / Stabilize / Test / Vent 四相，泄漏率 ∝ V×ΔP/Δt）④ Bravo AT「压降法基础」（理想气体换算式 Q = ΔP×V/(Patm×t)，温度是最大误差源） |
| URL | ① https://www.bjhgyjs.cn/news/qitajiance/2022/05/210017.html ② https://industrialmonitordirect.com/ar/blogs/knowledgebase/pressure-decay-leak-detection-for-ball-valves-transducer-selection-and-alternatives ③ https://zaxisinc.com/resources/pressure-decay-leak-testing-guide.html ④ https://www.bravoat.com/application-notes/leakmaster |
| 许可证 | 公开技术文章 / 厂商应用笔记（版权文档，免费查阅） |
| 提取点 | ① **四相 + 中间「隔离」动作**：充气 → 稳压（热平衡，稳定时间不足会既藏漏又造漏）→ 隔离测量 → 排气；② **泄漏率公式**：`Q ∝ ΔP × V / Δt`（本库以 `fChamberVolume` 引脚 + 常数换算为 mL/min，公式与系数写入头注释）；③ **温度补偿**：温度是最大误差源，`Q_corrected = Q × (273.15+Tref)/(273.15+T)`（一阶理想气体近似，非绝热修正，须在注释声明适用范围）；④ **大漏快判**：测量窗内压降超粗阈值立即判 NG，不必等满窗（节拍优化）；⑤ **夹具密封是测量系统一部分**：夹具未闭合禁止充气（本库 `bFixtureClosed` 门控）；⑥ 稳压结束压力必须落在目标压力 ± 容差内，否则判「充气异常」而非判工件 NG（区分设备故障与工件不良） |
| 拟平移组件 | `FB_DL_LeakTestStation`（压降检漏工站：夹具确认 → 充气 → 稳压 → 隔离测量 → 排气 → OK/NG/Abort） |
| clean-room 声明 | 仅提取公开物理公式与四相时序；状态机、引脚命名、故障码、温度补偿实现、判定策略为本库自有；不绑定任何检漏仪品牌协议（压力/温度由引脚注入） |

## S-9｜Siemens LBP V2.8 功能组实测（**修正矩阵第 2 节假设**；本轮 `FB_DL_StepController`，T2-2 LBP 深化）

| 项 | 内容 |
|---|---|
| 来源名称 | ① 西门子 SIOS 官方文档页「基本过程库 (LBP) V2.8」（109749508，含 23 个工艺块清单）② LBP V2.8 Operation 文档 PDF（Table 1-1 块清单与描述）③ PLC 技术网「西门子官方库详解·LBP 篇」（23 块按功能归类，NAMUR NE107 报警设计）④ DMC「LBP for Beginners」LBP_Vlv 详解（`cmd*` / `ind*` 命名分工、反馈矛盾与超时判故障、`indTripOk` / `indInterlock` / `indRepair` 语义） |
| URL | ① https://support.industry.siemens.com/cs/document/109749508/ ② https://support.industry.siemens.com/cs/attachments/109749508/109749508_LBP_V2.8_Operation_DOC_en.pdf ③ https://bbs.plcjs.com/thread-642513-1-4.html ④ https://www.dmcinfo.com/blog/42185/the-library-for-basic-processes-lbp-for-beginners-part-1-siemens-plcs/ |
| 许可证 | 西门子免费使用但**闭源版权**（T2-2 既定）+ 公开技术文章；仅借鉴功能分类与命名组织 |
| 提取点 | ① **实测块清单（23 块）**：`LBP_Aggr8`（8 聚合体群控）/`AnaAvg`/`AnaRead`/`ClctVal`/`CntrA`/`CntrD`/`CntrP`/`CtrlPID`/**`CtrlStp`（步进控制器）**/`Intlk8`/`Msg8`/`Mtr`/`MtrDS`/`MtrF`/`SimoDir`/`SimoRev`/`Sina`/`SinaExt`/`OpAna`/`OpDig`/`Polygon`/`Select`/`SetCrv`/`TimeSw`/`Vlv`/`VlvA`/`3wVlv`；② **矩阵第 2 节「电机 / 阀门 / 定量 / 混合 / 驱动参数化」五组假设中，「定量」「混合」在 LBP V2.8 中不存在**（定量语义在前轮已由 `FB_DL_BatchDosingControl` 经 ISA-88 相语义承载，属正确的替代路径）；③ **`CtrlStp` 步进控制器语义**：偏差 → 分级输出（多级加热器 / 多级冷却 / 多台泵与压缩机投切），与连续 PID 互补（粗分级 + 精连续）；④ `cmd*` / `ind*` 命名分离（命令域 / 反馈域）——本库既有「cmd/ind 命令-反馈分离」范式与之同构，可作为独立印证；⑤ `Aggr8` 的「8 路聚合体群控」印证本库 `FB_DL_DutyStandbyRotation` 的轮换思想 |
| 拟平移组件 | `FB_DL_StepController`（分级步进控制：级数 + 死区 + 最小驻留 + 均衡轮换 + 累积/单级两种输出拓扑） |
| clean-room 声明 | 仅提取「步进/分级控制器」的功能分类与「偏差 → 级数」映射语义；级数计算律（比例 + 双向迟滞）、驻留时间、轮换偏移、引脚命名、故障码 100% 本库自有；**未参考 LBP 源码或 DB 结构**（LBP 为闭源 FBD/SCL 块） |

## S-10｜CIP 原位清洗顺控（本轮 `FB_DL_CipCleaningSeq`，食品 / 制药 / 锂电浆料）

| 项 | 内容 |
|---|---|
| 来源名称 | ① PLC Programming「CIP Explained」（TACT 四要素、相位计时**必须被温度/电导率/流量联锁暂停**、回液电导率判冲洗终点、阀阵确认）② Aspotomasyon Wiki「CIP Automation」（1~3% NaOH / 60~85 ℃、预冲-碱洗-中冲-酸洗-终冲-消毒相序）③ Food & Bev Automation「CIP and SIP」（clean-status permissive、验收判据）④ Metromotion「F&B Automation」（ISA-88 相位复用、Abort 后须排空隔离到确定安全态） |
| URL | ① http://plcprogramming.io/blog/clean-in-place-cip-explained ② https://wiki.aspotomasyon.com/article/clean-in-place-automation ③ https://foodandbevautomation.com/knowledge/cip-sip ④ https://www.metromotioncontrols.com.au/blog/food-beverage-automation-australia |
| 许可证 | 公开技术文章 / 行业 Wiki（版权文档，免费查阅） |
| 提取点 | ① **相位计时不是墙钟计时**：温度低于下限 / 电导率低于下限（浓度不足）/ 流量低于下限（停滞）时**暂停累计**，条件恢复继续——这是 CIP 与普通定时顺控的本质区别（本库以 `bPhaseHold` + 三路联锁实现）；② **回液电导率判终点**：终冲洗不以时间到为准，而是回液电导率降到基线（本库以 `fRinseCondTarget` + 最长延时 `tRinseMax` 双判据）；③ **阀阵就绪确认**：供液/回液阀位置反馈确认后才允许启泵（`bCircuitReady` 门控）；④ **Abort 安全态**：中止必须排空并隔离到确定状态，不能停在半途；⑤ 相序固定不可跳相（跳相请求拒绝并出信息码）；⑥ 温度/电导/流量/时间四要素中温度影响最大（工艺权重注释） |
| 拟平移组件 | `FB_DL_CipCleaningSeq`（CIP 六相顺控 + TACT 联锁暂停 + 回液电导终点 + 偏差计数） |
| clean-room 声明 | 仅提取公开工艺相序与 TACT 联锁语义；状态机、引脚命名、故障码、暂停/恢复实现、参数数组结构为本库自有；不实现具体阀门矩阵布线（由调用方经 `bCircuitReady` 与输出指令接线） |

## S-11｜LGF 函数组实测目录（本轮 `FB_DL_PeakDetector`，T2-1 LGF Math/统计-峰值族深化）

| 项 | 内容 |
|---|---|
| 来源名称 | ① 西门子 LGF 官方文档 V1.0.1 PDF 目录（109479728，3.1~3.7 全部组与块清单）② PLC 技术网「LGF 库详解 06：RandomRange / SearchMinMax / StoreMinMax」③ Industrial Monitor Direct「S7-1200 读取模拟量最大最小值」（`LGF_StoreMinMax` 参数域：enable / inputValue / reset / storedMin / storedMax） |
| URL | ① https://cache.industry.siemens.com/dl/files/728/109479728/att_857591/v1/109479728_LGF_DOCU_V10_en.pdf ② https://bbs.plcjs.com/thread-643049-1-1.html ③ https://industrialmonitordirect.com/blogs/knowledgebase/reading-minmax-analog-signal-values-in-s7-1200-tia-portal |
| 许可证 | 西门子免费使用但**闭源版权**（T2-1）+ 公开技术文章；仅借鉴功能分类与参数域 |
| 提取点 | ① **实测目录修正矩阵**：V1.0.1 的组为 Date and timer / Counter / Comperator / **Math**（含 `AverageAndDeviation`、`MinMaxHistory`、`SearchMinMax`、`RandomINT/Real`、`XRoot`、矩阵运算）/ Data handling（FIFO、ShellSort）/ Converter（BCD↔Gray、`TemperatureConverter`）/ Signal generators（`Frequency`、`Impulse`、`SawTooth`）——**「统计 / 峰值 / 最小最大值」在 Math 组内，不存在独立 Measurement 组**（矩阵第 2 节的 Measurement 组行须修正为「Math 组内统计峰值子族」）；② **峰值保持参数域**：`enable`（跟踪使能）/ `inputValue` / `reset`（复位到当前值）/ `storedMin` / `storedMax`——三项引脚即可表达，验证「原子化」切分正确；③ **`MinMaxHistory` 与 `SearchMinMax` 的分工**：前者「随时间窗口保留极值」，后者「数组内检索极值 + 索引」——本库 `FB_DL_PeakDetector` 只做前者（时域极值保持 + 衰减），数组检索留扩产；④ 与本库既有 `FB_DL_SignalStatistics`（窗内均值/方差/极差统计）职责必须切清：**统计器测「窗口统计量」，峰值器测「过程极值与衰减」** |
| 拟平移组件 | `FB_DL_PeakDetector`（峰值/谷值保持 + 衰减率 + 双阈值事件 + 计数） |
| clean-room 声明 | 仅提取「enable / reset / 极值输出」参数域与「时域极值保持 vs 数组检索」的切分思路；衰减律、阈值事件、计数、故障码、引脚命名为本库自有；未复制 LGF 任何代码或注释 |

## S-12｜卷径估算（**已评估不采纳记录**：不新建 `FC_DL_WinderDiameterCalc`）

| 项 | 内容 |
|---|---|
| 来源名称 | ① Industrial Monitor Direct「Winder Control Strategies」（两种卷径估算：层数积分 `R = R_core + t × N`；速度比 `r = v/ω`）② KY Automation「Web Tension Control」（`D = v·i/(π·n)`，估算噪声 ±2~5 mm 需一阶滤波，锥度张力式）③ 机电之家「收卷张力控制系统」（低速时卷径计算须停算保持：`d = k·v/n`，低于最低线速度冻结） |
| URL | ① https://industrialmonitordirect.com/blogs/knowledgebase/winder-control-strategies-speed-vs-torque-mode-for-web-processing ② https://www.kyautomation.com/news/7050.html ③ https://www.jdzj.com/plc/article/2010-10-25/22255-1.htm |
| 许可证 | 公开技术文章（版权，免费查阅） |
| 提取点 | ① 卷径可由「层数积分」或「线速度/角速度比」两法求得，两法均有低通滤波与低速冻结需求；② 低速失效是共性问题（`v → 0` 时 `v/ω` 病态）；③ 锥度张力曲线 `T(D) = T_core × [1 − taper × (D−D_core)/(D_full−D_core)]` |
| **决策** | **不新建卷径组件**。理由：① `ROADMAP.md` 行业池已有两条更完整的待办——`FB_DL_UnwinderDiameterCalc`（层数积分递推 → DL_Motion）与 `FB_DL_WindingTraverse`（卷径 + 横动排线 → DL_Motion），本轮若在 DL_Algo 再造一个纯函数版本将造成**同名语义三处并存**；② 卷径是「运动侧状态量」（依赖轴角速度），归 DL_Motion 更符合分层；③ 本轮 DL_Motion 已有 6 项，容量已满。**结论：维持 ROADMAP 两条待办，卷径族留 R9 在 DL_Motion 一并落地（届时可直接复用本轮 `FB_DL_ElectronicGear` 的比值/相位设施）** |

## S-13｜工业安灯塔（Andon / Stack Light）驱动语义（本轮 `I_DL_TowerLight` + `FB_DL_SignalTower`，DL_Device 收尾族）

| 项 | 内容 |
|---|---|
| 来源名称 | ① Industrial Monitor Direct「Stack Light 颜色标准」（绿=自动运行 / 蓝=手动 / 黄=预警 / 红=故障；**闪烁 0.5~1.0 Hz**；红闪=未确认、红常=已确认；多灯可同亮；附 Structured Text 控制示例）② Stack-Light「What is an Andon」（颜色语义 + 内置蜂鸣 + 多行业用法）③ Digi-Key「工业塔灯安装」（闪烁语义差异：绿闪=启动中、黄闪=紧急服务请求、红闪=停机待处理；蓝闪=远程配置中）④ 剑指工控「三色塔灯定义」（**单一出口优先级**：安全闪红+鸣 > 一般故障红常 > 预警黄闪 > 人工待处理黄常 > 自动正常绿常 > 未定义灭；输入端应为一组状态位而非直接挂 Q 点） |
| URL | ① https://industrialmonitordirect.com/blogs/knowledgebase/industrial-stack-light-color-standards-for-automanual-status ② https://stack-light.com/blogs/andons-stack-lights/what-is-a-andon ③ http://ie.digikey.com/en/articles/install-easy-to-see-industrial-tower-lighting-to-alert-nearby-operators ④ https://jianzhigongkong.com/node/3432 |
| 许可证 | 公开技术文章 / 分销商技术文章（版权，免费查阅） |
| 提取点 | ① **优先级单出口**（来源④）：塔灯不是「把 Q 点接到灯上」，而是「一组状态位 → 一个唯一仲裁结果」，这是本块的核心架构约束；② **颜色语义域**：红=故障/停止、黄=预警、绿=运行/自动、蓝=人工/求助、白=自定义（本库落为 `E_DL_TowerColor` 五色 + eNone）；③ **两种闪频**：告警闪烁 0.5~1 Hz（本库默认慢闪 `T#500MS` 半周期 = 1 Hz 全周期，快闪 `T#250MS` = 2 Hz），闪烁相位由内部时基产生，**禁读 CPU 钟**（时基由 `tFlashSlow` / `tFlashFast` 引脚决定）；④ **确认语义**：未确认闪烁、已确认常亮（红）；⑤ **多灯同亮合法**：蓝 + 黄同亮 = 手动运行且有预警——故本块**不做「只允许一盏灯」的硬互斥**，仅做「红绿不同亮」的安全侧断言；⑥ **蜂鸣**：允许位 + 消音 + 消音超时自动恢复（来源②内置蜂鸣与③音频告警的存在性印证） |
| 拟平移组件 | `I_DL_TowerLight`（塔灯契约：五色 × 四种模式属性 + 3 方法）+ `FB_DL_SignalTower`（实现：优先级仲裁单出口 + 双闪频时基 + 蜂鸣消音 + 红绿互斥断言） |
| clean-room 声明 | 仅提取公开颜色/闪频/确认语义与「单出口仲裁」的架构约束；枚举、引脚、故障码、仲裁优先级顺序、时基实现为本库自有；**未复制来源④的示例代码**（其仅作语义印证） |

## S-14｜梯形速度曲线耗时估算（本轮 `FC_DL_CalcMoveTime`，DL_Motion 函数件）

| 项 | 内容 |
|---|---|
| 来源名称 | ① Mech Codex「Robot Cycle Time Estimate from Move Profile」（`t = v/a + (d − v²/a)/v`，三角退化 `t = 2√(d/a)`，`v_peak = √(a·d)`）② Firgelli「Trapezoidal Acceleration Profile Calculator」（`t_acc = v_max/a`，`d_acc = ½·a·t_acc²`，`d_const = d_total − 2·d_acc`，临界 `d_total = v_max²/a`）③ BugBotLab「Velocity Profiles」（忘记三角情形是经典 bug：短行程每次过冲） |
| URL | ① https://mechcodex.com/learn/machine-design/robot-cycle-time-estimate-from-move-profile ② https://www.firgelliauto.com/blogs/calculators/trapezoidal-acceleration-profile-calculator ③ https://www.bugbotlab.com/learn/u10-2-velocity-profiles |
| 许可证 | 公开教学 / 工程计算器文档（版权，免费查阅）；公式本身为公开运动学 |
| 提取点 | ① **临界判据**：`d ≥ v_max²/a`（等加减速）才有匀速段，否则退化为三角——**必须显式判，不得隐式假设**；② **三角峰速**：`v_peak = √(a·d)`（等加减速）/ 非等加减速时 `v_peak = √((2·a·d_dec·d + d_dec·v0²)/(a + d_dec))`；③ **初速非零的工程版**：加速段距离 `(v² − v0²)/(2a)`，本库需支持 `fVelStart`（皮带已在动的接续定位）；④ 非匀速固定开销（夹爪、稳定延时、控制器时延）常占总节拍一半以上 → 本库提供 `tSettle` 引脚，注释要求调用方显式计入；⑤ 输出同时给 `bTriangular` 标志（HMI 可判断「这段移动根本到不了设定速度」——选型诊断价值） |
| 拟平移组件 | `FC_DL_CalcMoveTime`（梯形/三角耗时估算 + 峰速回算 + 三角退化标志） |
| clean-room 声明 | 公式为公开运动学（教科书级），实现、接口、故障码、边界策略（非有限值、加速度近零、负距离取绝对值）为本库自有 |

---

## 合规汇总（本轮 14 次检索的许可证结论）

| 源类型 | 涉及 S 条目 | 许可证结论 | 处置 |
|---|---|---|---|
| PLCopen 规范（公开规范文档） | S-1、S-2 | 免费下载的公开规范，版权文档 | 借接口参数域与状态语义，实现 clean-room |
| 西门子 LGF / LBP（免费闭源） | S-9、S-11 | 免费使用、闭源版权 | 仅借功能分组与参数域，**零代码复制** |
| 西门子官方支持文档 / 厂商帮助（Beckhoff / ABB / 汇川 / 施耐德） | S-1~S-5、S-9 | 版权文档，免费查阅 | 仅借语义与参数域 |
| CODESYS Forge | S-6 | 示例项目（未显式声明，按最严处置）；designpatterns 项目为 UNLICENSE 公有领域 | 仅借结构，不复制；**不引入其库依赖** |
| 公开技术文章 / 行业 Wiki / 公开论文 / 教材 | S-3、S-7、S-8、S-10、S-12~S-14 | 版权文档，免费查阅 | 仅借工程语义与经验值 |
| GPL / AGPL | **本轮零引用** | — | — |

**本轮无任何代码行被复制入库**；`_Staging_Raw` 不保存任何原始源码文件（本轮为「语义级借鉴」，无原始代码需要暂存），故未建 `original_*.st`。所有 16 个组件的 `.st` 头注释「开源溯源 (Origin)」字段须按上表对应 S 条目如实标注「原创实现（参考 XXX 分类与参数域）」。
