# RAW_NOTES_R7 —— Round 07 狩猎检索记录

> 轮次：R7（2026-11-15）｜ 方向：DL_Device 收尾件五族（扫码枪/安全门/安全光幕/脉冲流量计/振动料位开关）+ DL_Process 三件（OEE/输送线积放/批量配料）+ DL_Motion 补充件（软限位预判）+ DL_Base LGF Counter 组开组（T2 配额）
> 执行人：道莅工控代码库产品总监（兜底模式）
> 检索时间：2026-11-15（R7 计划阶段，共 11 次 WebSearch）
> 合规基线：SOURCE_HUNTING_MATRIX.md 第 0 节三条铁律。闭源资产只提取「功能分类 / 接口参数域 / 状态机语义」，实现全部 clean-room，不复制任何代码行、DB 结构与注释原文。

---

## S-1｜T2-1 LGF Counter 组开组（本轮 DL_Base 两件的分类骨架与配额主源）

| 项 | 内容 |
|---|---|
| 来源名称 | ① Siemens LGF（Library of General Functions）V1.0.1 官方文档 PDF（109479728_LGF_DOCU_V1_0_1_en.pdf，含 3.2 Counter operations 节：FC LGF_CountFallInDWord / FC LGF_CountRisInDWord）② LGF V5.3.0 下载页与功能组综述（asutp.org / plcjs 论坛，确认 Counter Operations 组语义：事件计数、循环计数） |
| URL | ① https://cache.industry.siemens.com/dl/files/728/109479728/att_858193/v1/109479728_LGF_DOCU_V1_0_1_en.pdf ② https://asutp.org/news/library_of_general_functions_lgf_step_7_basic_professional_tia_portal_simatic_s7_1200_s7_1500/2025-11-28-639 ③ https://bbs.plcjs.com/thread-652679-1-2.html |
| 许可证 | 西门子许可证条款（免费使用，闭源版权，矩阵 T2-1 既定结论） |
| 提取点 | ① **Counter 组成员粒度**：LGF 把计数类拆为「按位事件计数（CountRisInDWord/CountFallInDWord 统计 DWORD 内位跳变次数）」与「循环/事件计数（Counter Operations 组描述）」两类——印证本库「计数原子化」切分；② 组语义定位：事件计数（上/下/双向）、循环计数（回绕）、预设计数（比较输出）；③ LGF 计数块输出惯例：计数值 + 计数方向状态 + 溢出/回绕标志分离，错误不经异常通道；④ 增量计数上限语义（社区资料 FB Counter 极限 2,147,483,647 对应 DINT 饱和）——本库取 DINT/LINT 双域思路中的 DINT 优先（跨平台 DINT 安全） |
| 拟平移组件 | FB_DL_EventCounter（双向事件计数器：预设值比较输出 + 饱和/回绕可选）、FB_DL_ModuloCounter（循环计数器：0..N-1 取模回绕，转盘工位索引）。**clean-room 声明**：只提取「事件/循环/预设」三分类与「值+标志分离」输出惯例；接口命名、故障码、实现全部按本库红线独立设计，不复制任何 LGF 代码 |

## S-2｜T1-5 TcOpen 组件契约范式开组（本轮 Device 五个新接口的分层设计范式，T1 配额主源）

| 项 | 内容 |
|---|---|
| 来源名称 | ① TcOpen 官方文档 Components/TcoComponent 约定页 ② TcOpen GitHub 仓库与 Conventions.md（MIT 许可）③ soup01 TcOpen 使用教程 |
| URL | ① https://inxton.github.io/TcOpen.Documentation/articles/Conventions/Component.html ② https://inxton.github.io/TcOpen.Documentation/articles/TcOpenFramework/TcoCore/TcoComponent.html ③ https://github.com/TcOpenGroup/TcOpen ④ https://github.com/TcOpenGroup/TcOpen/blob/1821317d0200bc52659d2bb96c65de87a0bbf032/docs/Conventions.md ⑤ http://soup01.com/en/2023/04/24/beckhofflets-try-open-source-library-tcopen-in-twincat3/ |
| 许可证 | MIT（TcOpen 官方仓库 LICENSE，确认版次 2026-11） |
| 提取点 | ① **组件三段式契约**：抽象接口（ITcoReader 等）+ Config 结构（超时/参数）+ Status 结构（状态镜像）分离——本库对应「VAR_INPUT 参数域 / VAR_OUTPUT 状态域」分层，Config/Status 不混注入；② **组件抽象定位**：TcoComponent 是「控制物理或虚拟器件的 API/Driver」，组件不得含应用专用代码（可复用性红线）——印证本库「DL_* 零应用耦合」；③ **I/O 注入原则**：组件内禁 %I/%Q 地址，I/O 经 FB 实例化参数传入（VAR_IN_OUT 需引用有效性检查）——与本库红线 2 完全同构，作为独立印证源；④ 方法语义：操作方法返回任务状态对象、状态属性单周期返回（传感器电平）——本库接口「方法 ≤6 + 属性 GET」三段式的对照组；⑤ TcOpen 已有 Reader 类组件抽象（TcoCongexReader implements ITcoReader）——扫码枪接口 `I_DL_BarcodeScanner` 的「触发/结果/就绪」三分契约参照 |
| 拟平移组件 | I_DL_BarcodeScanner / I_DL_SafetyDoor / I_DL_LightCurtain / I_DL_FlowMeter / I_DL_LevelSwitch 五个接口的「属性 + 方法」分层范式。**clean-room 声明**：仅借鉴 MIT 开源框架的公开接口组织约定（文档语义级），不复制任何 TcOpen 代码行；本库命名体系（I_DL_*、E_DL_*、uErrorId 段位）独立设计 |

## S-3｜工业固定式扫码枪 PLC 集成语义（本轮扫码枪族的触发-结果握手域）

| 项 | 内容 |
|---|---|
| 来源名称 | ① lumaspecvision PLC 触发解码教学（一次性触发/结果定时/重试/报警模式）② plccode.ai 扫码枪接入 PLC（串口/现场总线/TCP 三接口、ReadCounter 新结果检测、NOREAD 语义）③ industrialmonitordirect S7-300 PROFINET 扫码枪集成（Code MV440 状态字节：Ready/ReadOK/ReadNG/MatchCompare/Warning/Error）④ 西门子官方论坛 Honeywell 扫码枪 FB 分享（触发沿、Ready 门控、Results Ack 应答、T#5S 超时） |
| URL | ① https://lumaspecvision.com/blogs/learn/trigger-a-barcode-decode-from-a-plc-tag-not-a-ui-button ② https://plccode.ai/reading-a-barcode-scanner-into-a-plc ③ https://industrialmonitordirect.com/pt/blogs/knowledgebase/s7-300-profinet-barcode-reader-integration-gsdml-and-tcp ④ https://www.ad.siemens.com.cn/club/bbs/Post_2032504_66_0_8_0_0_0__0.html |
| 许可证 | 全部为公开技术文章/论坛帖/教学文档（版权文档，免费查阅），仅借鉴握手语义 |
| 提取点 | ① **触发语义**：PLC 侧上升沿单发触发（电平触发会连发），触发后进入「等待结果」态；② **握手四信号集**：Trigger（PLC→枪）/ Ready（枪就绪可触发）/ ReadOK / ReadNG（解码成功/失败，保持到应答）；③ **结果新帧判定**：按 ReadCounter 变化判定新结果，禁止按字符串内容比对判新；④ **NOREAD 处理**：超时或空串→NOREAD 独立状态，区分「读到但内容无效」与「静默无结果」；⑤ **重试惯例**：首次 NOREAD 重触发一次、第二次升级报警（500ms 结果窗口）；⑥ **应答位**：Results Ack 确认后枪侧清除结果保持位；⑦ 触发到结果时延预算（曝光 10ms + 解码 17ms + 网络 3ms + 扫描 5ms ≈ 35ms）→ 超时默认取 500ms~5S 可配 |
| 拟平移组件 | I_DL_BarcodeScanner（接口：触发/应答方法 + 就绪/成功/失败/NOREAD 状态属性）+ FB_DL_SerialScanner（实现：触发沿 → 结果窗口 → NOREAD 一次重试 → 二次报警；成功锁存字符串 + 长度）。**clean-room 声明**：握手信号集为行业公知语义，状态机、枚举、故障码独立设计；串口/总线数据接收本体不在本块内（经 IN_OUT 注入已收包的字符串） |

## S-4｜安全门联锁与电磁锁扣时序（本轮安全门族的解锁时序域，ISO 14119 / IEC 60204-1 公开语义）

| 项 | 内容 |
|---|---|
| 来源名称 | ① shih-shin ISO 14119 电磁联锁架构解析（弹簧锁/断电解锁二分、防破解 Type 1~4、保持力 Fzh）② voxintech 冲压防护联锁教学（停机请求→制动→静止确认→解锁四步链）③ xuruiswitch 带锁扣安全门开关教学（门状态/锁状态双触点分离、允许释放判据）④ aitechdoc 带锁扣联锁防护装置术语页 |
| URL | ① https://shih-shin.com/en/industrial-safety-guard-solenoid-interlock-mechanical-locking-architecture-compliant-with-iso-14119 ② https://www.voxintech.com/?p=84543 ③ https://xuruiswitch.com/?p=141/ ④ https://aitechdoc.netlify.app/glossary/interlocking-guard-with-guard-locking |
| 许可证 | 公开技术文章/教学文档（版权文档，免费查阅），仅借鉴时序与语义 |
| 提取点 | ① **解锁四步链（本块状态机骨架）**：停机请求 → 危险源停止指令 → 静止/零速确认（或按实测停机时间整定的 run-down 计时器）→ 解锁电磁铁得电；② **双触点分离**：门位置触点（closed/open）与锁状态触点（locked/unlocked）独立监测，两者不一致 = 防篡改诊断（如门开而锁闭合 Impossible 组合）；③ **断电安全方向**：弹簧锁（power-to-unlock，断电保持锁定）为人身保护首选——本块输出语义按「断电解锁方向」注释；④ **无静止监控的降级路径**：用实测最差停机时间整定的 run-down 计时器替代零速信号（制动磨损后须重测，注释必须写明）；⑤ **困人解救**：内部紧急解锁机构属硬件安全设计，PLC 块仅预留应急解锁输入引脚并审计记录；⑥ 重启抑制：门重新关闭+锁闭+复位后允许重启，禁止自动重启 |
| 拟平移组件 | I_DL_SafetyDoor（接口）+ FB_DL_GuardLockDoor（实现：锁定→请求停机→静止确认→解锁→开门审计→关门再锁定的六态状态机）。**clean-room 声明**：本块为**标准 PLC 逻辑层**组件（状态监控与联锁编排），非认证安全功能；头部与注释显式声明「不构成 ISO 13849 安全功能，安全回路由认证安全控制器承载」，只做联锁时序的编排与诊断镜像 |

## S-5｜安全光幕屏蔽（Muting）时序（本轮光幕族的状态机域，SICK mut_p / 西门子 Sequential Muting 公开语义）

| 项 | 内容 |
|---|---|
| 来源名称 | ① industrialmonitordirect SICK mut_p 块编程教学（2/4 传感器拓扑、屏蔽超时 30s、override 条件）② lorentzzi 屏蔽三方式（X/L/T 型布置逻辑真值表）③ plccode.ai muting & blanking 综述（序列/时序/时长三要素、屏蔽灯）④ Siemens S7-1500 Sequential Muting 示例文档 V21（58793869，LMutS_SensorSequence 状态机参数域） |
| URL | ① https://industrialmonitordirect.com/blogs/knowledgebase/programming-light-curtain-override-with-sick-mut_p-block ② https://lorentzzi.com/safety-light-curtain-muting-3-methods-to-identify-goods-and-personnel/ ③ https://plccode.ai/muting-and-blanking-for-light-curtains ④ https://support.industry.siemens.com/cs/attachments/58793869/58793869_Muting_Light_Curtain_DOC_V21_en.pdf |
| 许可证 | ①②③ 公开技术文章（版权文档）④ 西门子示例文档（免费查阅，版权文档），仅借鉴时序语义 |
| 提取点 | ① **屏蔽成立三要素**：传感器按预期序列触发（正向 M11→M12→M21→M22 / 反向镜像）+ 第二传感器在容差窗内跟随 + 全程不超屏蔽总时长；② **2 传感器（平行/L 型）** 与 **4 传感器（序列/T 型）** 双拓扑——本块以 bFourSensorMode 选择引脚落地；③ **人/物判别真值**：双传感器被同时/近同时遮挡且序列合法 → 屏蔽；仅一个被遮挡或序列错乱 → 光幕被触发即停机；④ **屏蔽超时**：首末传感器触发间隔超限（1~600s，典型 30s）→ 故障停机（防物件滞留/人随之通过）；⑤ **Override（滞留物清除）语义**：钥匙开关 + 至少一个屏蔽传感器仍遮挡才允许进入 override，最长 30s 硬帽，屏蔽灯常亮/闪烁区分；⑥ **屏蔽灯输出**：屏蔽期间常亮、override 闪烁；⑦ 重启联锁：故障/override 结束后需复位按钮确认；⑧ OSSD 双通道输入（本块 bOssd1/bOssd2 独立输入 + 不一致诊断） |
| 拟平移组件 | I_DL_LightCurtain（接口）+ FB_DL_SafetyLightCurtain（实现：OSSD 监控 + 2/4 传感器序列屏蔽状态机 + 屏蔽超时 + override + 屏蔽灯输出 + 故障复位）。**clean-room 声明**：序列真值表为公开安全工程语义（ISO 13855/IEC 61496 领域公知），状态机独立编写；块定位与 S-4 相同——**逻辑编排与诊断层，非认证安全功能**，头部显式声明 |

## S-6｜脉冲输出流量计 K 系数换算（本轮流量计族的换算与累计域，T1-1 OSCAT 频率测量语义补采）

| 项 | 内容 |
|---|---|
| 来源名称 | ① industrialmonitordirect 脉冲输入转流量/总量教学（K 系数、频率法/周期法、低流量截止）② ProSense Instruments 脉冲输出综述（脉冲宽度/最大频率匹配、去抖与丢脉冲权衡、断电保持）③ industrialmonitordirect GE Fanuc 流量计算（固定窗口法 vs 频率法） |
| URL | ① https://industrialmonitordirect.com/blogs/knowledgebase/converting-pulse-input-to-flow-rate-and-volume-totalizer ② https://www.prosenseinstruments.com.au/post/flow-meter-pulse-outputs-explained-k-factors-totalisers-and-flow-rate-calculations ③ https://industrialmonitordirect.com/blogs/knowledgebase/calculating-flow-rate-from-pulse-output-in-ge-fanuc-plc |
| 许可证 | 公开技术文章（版权文档），仅借鉴换算语义（K 系数换算为行业公知物理公式） |
| 提取点 | ① **核心换算链**：瞬时流量 = f频率 / K系数（单位：pulses/L）；总量 = 累计脉冲数 / K系数——脉冲计数法累计精度优于流量积分法（推荐法 1）；② **周期法低频优势**：低流量下频率法更新慢，测周期（ms→Hz=1000/周期）更稳；③ **低流量截止**：低于阈值频率输出置零（消除噪声假读）；④ **去抖权衡**：去抖窗 > 最短脉冲间隔将丢真实脉冲——去抖时间必须引脚化并注释与最大频率的匹配关系；⑤ **溢出处理**：累计用 DINT/LINT，接近溢出须提示；⑥ **断电保持**：总量保持属调用方职责（本库零全局耦合，不内嵌掉电保持），注释声明 |
| 拟平移组件 | I_DL_FlowMeter（接口）+ FB_DL_PulseFlowMeter（实现：R_TRIG 脉冲沿计数 → 滑动窗频率估计 → K 系数换算瞬时流量 + 脉冲/单位总量累计 + 低流量截止 + 逆 K 系数防除零）。**clean-room 声明**：换算公式为公开物理关系；本库依赖方向合规——频率估计纯逻辑不引用 DL_MathData 组件（Device 层禁引高层，滑动窗计数内联实现并注明）；T1-1 OSCAT Basic 频率测量函数族（◐ 深化）作为低频/高频双口径旁证 |

## S-7｜振动叉式料位开关语义（本轮料位开关族的失效安全域）

| 项 | 内容 |
|---|---|
| 来源名称 | ① KJT Sensors 振动叉料位限位开关综述（阻尼-频移原理、溢流/干转防护）② Sitron 振动叉传感器原理与应用（fail-safe 高/低可配置）③ Hycontrol MTF 系列页（fail-safe 方向、灵敏度可调、双宽叉低粘度液体）④ NIVELCO NIVOSWITCH 产品页（覆盖/裸露双延迟、安全方向选择） |
| URL | ① https://www.kjt-sensors.com/show-12237.html ② https://www.sitron.com/pt/how-vibrating-fork-level-sensors-work-tuning-fork-principle-applications-and-advantages ③ https://www.weighingandinspection.eu/product/mtf-serie-trilniveauschakelaars ④ https://psctexas.com/product/nivoswitch-vibrating-fork-level-switch/ |
| 许可证 | 公开技术文档/产品页（版权文档，免费查阅），仅借鉴失效安全语义 |
| 提取点 | ① **原理语义**：压电激励叉体谐振 → 介质覆盖产生阻尼/频移 → 超阈值判「有料」；对介电常数/电导率不敏感（注释素材）；② **失效安全双方向**：fail-safe HIGH（断线/失效=报有料，防溢流用）与 fail-safe LOW（断线=报无料，防干转用）——本块以 eFailSafeMode 枚举引脚落地；③ **开关延迟分离**：覆盖延迟与裸露延迟独立可调（防液面波动误翻转）；④ **应用定位**：高点溢流报警 / 低点干转保护 / 桥架（bridging）检测——高/低报警联锁输出方向不同；⑤ 本块仅做**开关量信号的防抖、失效安全方向化与联锁输出编排**，谐振检测本体在传感器内部（PLC 块不实现检测算法，注释声明） |
| 拟平移组件 | I_DL_LevelSwitch（接口）+ FB_DL_LevelSwitchVib（实现：原始开关防抖 → 失效安全方向归一 → 覆盖/裸露双延迟 → 有料/无料双联锁输出 + 传感器失效诊断）。**clean-room 声明**：失效安全方向语义为 IEC 61511/行业公知工程惯例，接口与故障码独立设计 |

## S-8｜OEE 三因子计算体系（本轮 OEE 引擎的公式与口径域，T2-7 PackML 根因位深化）

| 项 | 内容 |
|---|---|
| 来源名称 | ① oee.com Calculate OEE 标准页（Planned Production Time / Run Time / 三因子公式 / 简化式等价证明）② industrialmonitordirect 实时 OEE SCADA 实现（PLC 标签结构、Performance 封顶 100%、Quality 空产 100% 边界）③ tatbeek ISO 22400-2 KPI 对齐页 |
| URL | ① http://www.oee.com/calculating-oee ② https://www.oee.com/ ③ https://industrialmonitordirect.com/blogs/knowledgebase/real-time-oee-calculation-implementation-in-scada-systems ④ https://tatbeek.com/e-solutions |
| 许可证 | 公开标准知识（OEE 公式为行业公知，ISO 22400-2 公开语义），仅借鉴口径 |
| 提取点 | ① **时间模型**：班次时长 − 计划停机（休息）= 计划生产时间；计划生产时间 − 停机时间 = 运行时间；② **三因子**：可用率 = RunTime/PlannedTime；性能率 = (理想节拍 × 总数)/RunTime，**封顶 100%**；质量率 = 合格数/总数，**零产量取 100%（不取 0）**；OEE = 三因子连乘；③ **损失分类**：计划外停机+计划停机（换型）归可用率；慢循环+微停归性能；返工+报废归质量（Nakajima 六大损失口径，与 PackML Held/Suspended 根因位对齐）；④ **换算边界**：除零防御（RunTime=0、TotalCount=0、PlannedTime=0）；⑤ 本块停机时间经 PackML 根因位（bHeldByMachine/bSuspendedByLine 语义）分账：计划停机（换型/休息）与计划外停机（故障）分列——与 FB_DL_PackMlStateMachine 17 态衔接 |
| 拟平移组件 | FB_DL_OeeCalculator（消费 PackML 状态/根因位引脚注入 + 理想节拍 + 计数脉冲沿 → 班次级三因子与 OEE 输出 + 班次复位）。**clean-room 声明**：公式为公开标准（oee.com/ISO 22400-2 口径），实现与引脚独立设计 |

## S-9｜输送线分区积放（Accumulation）与卡料判定（本轮输送段控制器的规则域）

| 项 | 内容 |
|---|---|
| 来源名称 | ① plctr.com 十二区积放线 ST 全解（分区规则一句话：有料且下游空才走、末区特殊、空区补跑、run-on 时间）② plcprogramming.io ZPA 零压积放教程（入口光电+下游状态联锁、Slug Release 间隔释放防浪涌）③ industrialmonitordirect 积放停止/级联释放教学（计数进出、级联释放链、卡料计时）④ industrialmonitordirect 六段输送线级联（上游允许/下游阻断、运行反馈失配级联故障） |
| URL | ① https://plctr.com/utilizing-plc-in-material-handling-and-conveyor-systems ② https://plcprogramming.io/blog/material-handling-plc-programming-guide ③ https://industrialmonitordirect.com/blogs/knowledgebase/conveyor-accumulation-stop-logic-for-packer-backup-control ④ https://industrialmonitordirect.com/blogs/knowledgebase/programming-omron-plcs-for-6-conveyor-lines-ladder-setup |
| 许可证 | 公开技术文章/教学文档，仅借鉴规则语义 |
| 提取点 | ① **积放单句规则**：本区运行 = 本区有料（或上区有料过渡）AND 下游区空/允许 AND 无卡料 AND 线使能——从排料端反向充满，下游停则上游柔性停；② **末区特殊**：末区运行条件来自下游工序（工位/码垛机）就绪信号，不判「下游区空」；③ **run-on 时间**：出口光电清空后再短时运行，确保箱子完全离区（TOF 语义）；④ **卡料判定**：运行指令有效 + 出口光电持续遮挡超卡料窗 → 卡料锁存（卡料窗按区长度/带速整定，禁止拍脑袋魔法数）；⑤ **间隔释放（Slug Release）**：积放解除后按区间隔 TOF 级联放行，防全线同时启动浪涌；⑥ **驱动反馈失配**：运行指令与驱动运行反馈不一致超窗 → 驱动故障（消费 I_DL_VfdDrive 的 bRunning/bFault 反馈） |
| 拟平移组件 | FB_DL_ConveyorZone（消费 I_DL_VfdDrive 接口注入 + 入口/出口光电 → 积放五态状态机 + 卡料窗 + run-on + 级联放行接口信号）。**clean-room 声明**：积放规则为行业公知，状态机与故障码独立设计 |

## S-10｜批量配料双速给料与空中落差自学习（本轮配料控制器的核心算法域，T2-2 LBP 定量族 / ISA-88 批次语义）

| 项 | 内容 |
|---|---|
| 来源名称 | ① industrialmonitordirect 沥青搅拌站批量秤空中补偿技术（In-flight Compensation：截断点 = SP − 落差补偿；自适应更新 补偿 += 误差/2 防振荡、5~10 批收敛；稳窗 500~1000ms；料位-流量双补偿查表）② thefertilizerequipment 自动配料 ±0.5% 精度综述（快加 90~95% 切慢加 + 落差修正切换点）③ 高服机械反应釜自动加料方案（双速切换阈值、落差提前量、搅拌振动滤波、过冲/堵料/断线异常处理） |
| URL | ① https://industrialmonitordirect.com/blogs/knowledgebase/inflight-compensation-for-batch-scale-control-in-asphalt-plants ② https://thefertilizerequipment.com/automated-batching-systems-how-is ③ https://www.zhendongshai.com.cn/6061.html |
| 许可证 | 公开技术文章（版权文档），仅借鉴算法思想（落差自学习为行业公知） |
| 提取点 | ① **三段给料**：快加（全速至切换点）→ 慢加（精投至截断点）→ 落定稳窗（500~1000ms）后结算；② **截断点公式**：关阀重量 = 设定值 − 落差补偿（In-flight 物料=流量×关阀时间，工程上直接学习）；③ **自学习更新规则**：误差 = 实际稳定值 − 设定值；补偿 := 补偿 + 误差/2（半误差防振荡，逐批收敛）——学习使能引脚可选；④ **异常分支**：过冲超差 → 批次 NG 锁存；给料中重量变化率长时间为零 → 料堵/断流诊断；秤信号无效 → 批次中止；⑤ **学习限幅**：补偿值上下限引脚化（防一次野值把学习带飞）；⑥ 本块不含称重模块本体——重量经 LREAL 引脚注入，执行机构抽象为快加/慢加/关断三离散输出（与给料机/闸门类型解耦） |
| 拟平移组件 | FB_DL_BatchDosingControl（重量引脚注入 + 三段顺控状态机 + 误差/2 自学习落差补偿 + 超差 NG 判定 + 断流诊断）。**clean-room 声明**：落差自学习思想为行业公知（误差/2 更新为公开教学语义），状态机、故障码、引脚独立设计；借鉴 ISA-88 批次相（Phase）抽象与 LBP 定量族分类（T2-2 ◐ 深化、T2-8 ◐ 深化） |

## S-11｜软限位预判与制动距离包络（本轮 Motion 补充件的预判公式域，T1-6 PLCopen 深化）

| 项 | 内容 |
|---|---|
| 来源名称 | ① industrialmonitordirect 伺服轴安全综述（软限位 vs 硬限位对比表、制动距离公式 d_total = v·(t_scan+t_io+t_disable) + v²/(2a)、典型时延参数表、工程示例 446mm+25% 裕量）② plctr.com Kinetix 软限位解析（去抖+驱动反应+减速距离三部分、超程后向内点动的恢复豁免语义）③ plcjs 运动控制器轴限位（软限位在硬限位内侧、FASTDEC 减速距离公式） |
| URL | ① https://industrialmonitordirect.com/web-pixels@fe0cff12w3ebd43eapaab70107m6f8ccd4d/custom/web-pixel-205717656@5/sandbox/modern/blogs/knowledgebase/servo-axis-safety-limit-switches-homing-and-current-limits ② https://plctr.com/?p=7866 ③ https://bbs.plcjs.com/thread-533434-1-6.html |
| 许可证 | 公开技术文章/论坛帖（版权文档），仅借鉴运动学公式（d=v²/2a 为物理公知） |
| 提取点 | ① **预判公式**：总停止距离 = 当前速度 ×（扫描+IO+驱动封锁时延）+ v²/(2a)；软限位触发阈值 = 行程边界 − 总停止距离 − 安全裕量%；② **方向无关性**：正/负方向独立判据，超程后仅允许反向指令（向内点动豁免语义）；③ **双层级联**：软限位（应用层，非安全等级）必须位于硬限位开关内侧，间距 ≥ 最差工况停止距离；④ **错误清单**：漏算扫描时延、用峰值速度而非实际编程速度、假设减速度等于配置减速——预判用保守（大距离）取值；⑤ 本块为预判器：输入位置/速度/减速度/行程边界 → 输出双向预警位 + 拦截建议方向；不承载认证安全功能（头部声明） |
| 拟平移组件 | FB_DL_SoftLimitGuard（软限位电子围栏预判器：双向停止距离实时计算 + 预警/拦截双阈值输出 + 方向化允许指令）。**clean-room 声明**：运动学公式物理公知；复用既有 I_DL_MotionAxis 状态接口（T1-6 ◐ 深化），故障码 0004 段顺延 |

---

## 配额核对

| 配额 | 要求 | 本轮落地 |
|---|---|---|
| ≥1 个组件族来自 T2 非 ST 源，**优先西门子 LGF 仍未挖掘（☐）的组** | 硬性 | **S-1 T2-1 LGF Counter 组由 ☐ → ◐ 开组**（DL_Base 2 件：FB_DL_EventCounter / FB_DL_ModuloCounter） |
| ≥1 个来自 T1 ST 原生源 | 硬性 | **S-2 T1-5 TcOpen 由 ☐ → ◐ 开组**（Device 五接口契约范式，MIT）+ **S-11 T1-6 PLCopen Motion ◐ 深化**（SoftLimitGuard）+ S-6 T1-1 OSCAT Basic ◐ 深化（频率测量语义旁证） |
| 禁止重复挖掘已 ✔ 收口组 | 铁律 | T2-1 LGF Counter ☐→◐ 开组；T1-5 TcOpen ☐→◐ 开组；T2-2 LBP / T2-7 PackML / T2-8 ISA-88 / T1-6 PLCopen / T1-1 OSCAT 均为 ◐ 深化；未触碰任何已收口组 |
| RAW_NOTES 来源/URL/许可证/提取点留痕 | 铁律 | 本文件 S-1~S-11 全覆盖 |

## 收尾回写清单（编码阶段完成后执行）

1. SOURCE_HUNTING_MATRIX.md 第 5 节：T2-1 LGF · Counter → ◐（FB_DL_EventCounter、FB_DL_ModuloCounter）；T1-5 TcOpen → ◐（五接口契约范式）；T1-6 PLCopen Motion → ◐ 深化（FB_DL_SoftLimitGuard）；T2-7 PackML → ◐ 深化（FB_DL_OeeCalculator 根因位分账）；T2-8 ISA-88 → ◐ 深化（FB_DL_BatchDosingControl 批次相语义）；T2-2 LBP → ◐ 深化备注（定量族思想）；T1-1 OSCAT Basic → ◐ 深化备注（频率测量旁证）。
2. 新组件 function_tags 挂来源组标签：lgf-counter / tcopen-component / scanner-handshake / safety-interlock / light-curtain-muting / flow-totalizer / level-switch-failsafe / packml-oee / conveyor-accumulation / lbp-batch-dosing / isa-88 / plcopen-motion。
3. AGENT_EVOLUTION_LOG.md 追加 R7 章节；ROADMAP.md 勾选 16 项并回写批处理进度（由终审阶段执行，本计划阶段不回写）。
