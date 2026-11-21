# RAW_NOTES_R6 —— Round 06 狩猎检索记录

> 轮次：R6（2026-11-15）｜ 方向：DL_Device 阀门/驱动族深化（LBP T2-2）+ DL_Motion 回零族（T1-6 PLCopen）+ DL_Process 行业池 9.5 节 P0 两件 + DL_Algo LGF Technology 深化（T2-1）
> 执行人：道莅工控代码库产品总监（兜底模式）
> 检索时间：2026-11-15（R6 计划阶段，共 5 次 WebSearch）
> 合规基线：SOURCE_HUNTING_MATRIX.md 第 0 节三条铁律。闭源资产只提取「功能分类 / 接口参数域 / 状态机语义」，实现全部 clean-room，不复制任何代码行、DB 结构与注释原文。

---

## S-1｜T2-2 LBP 阀门控制族与电机启停族（本轮 Device 十项的分类骨架与参数域主源）

| 项 | 内容 |
|---|---|
| 来源名称 | Siemens LBP（Library of Basic Processes）V2.7/V2.8 功能分类综述 + LBP_Vlv 开关阀块引脚级教学解析 |
| URL | ① https://www.dmcinfo.com/blog/42185/the-library-for-basic-processes-lbp-for-beginners-part-1-siemens-plcs/（LBP_Vlv 引脚全解）② https://jianzhigongkong.com/index.php/node/3291（LBP V2.8 模块清单：LBP_Vlv / LBP_VlvA / LBP_3wVlv / LBP_Mtr / LBP_MtrF / LBP_Sina 等）③ https://industrialmonitordirect.com/it/blogs/knowledgebase/resolving-lbp-vlv-interlock-timeout-in-tia-portal-v17（LBP_Vlv 联锁超时行为：AUTO/MANUAL 模式差异）④ https://imdtouch.com/blogs/knowledgebase/siemens-tia-portal-v17-demo-projects-and-lgflbp-libraries-guide（LBP 三大子包：Basic Processes / Drive Functions / Visualization） |
| 许可证 | 西门子许可证条款（免费使用于商用项目，但闭源版权，矩阵 T2-2 既定结论） |
| 提取点 | ① **阀门块功能分类**：开关阀（LBP_Vlv，布尔开/关 + 双反馈）/ 模拟量调节阀（LBP_VlvA，开度精确控制）/ 三通阀（LBP_3wVlv）——三分法即本库「三点浮点阀 / 比例阀 / 真空与气缸」分层依据；② **LBP_Vlv 反馈校验参数域**：indClosed/indOpened 双反馈同时为真 = 合理性冲突立即故障；指令-反馈超时（timeout 引脚共用「动作超时」与「合理性冲突」两类错误）；③ **覆盖性/联锁输入族**：indTripOk（急停参与停机或旁路）、indErr/indWarn（外部错误/警告注入）、indInterlock（禁开联锁）、lockClose（反向联锁禁关）；④ **模式输入族**：indRepair（维修模式：禁控禁报）/ indLocal（就地模式：cmdLocOpen 覆盖一切）/ cmdAut + cmdAutoOpen（自动模式开/关）；⑤ **输出族**：close/open 双输出 + collectError/collectWarning/collectMaintenance 三收集位 + modeAut/reset 状态镜像 + intError 错误字（WORD）；⑥ **电机块家族分层**：LBP_Mtr（基础启停互锁）/ LBP_MtrDS（双速双向）/ LBP_MtrF（变频调速）/ LBP_Sina（G120 变频器集成）——印证「DOL/星三角/变频」三层设备抽象粒度；⑦ LBP_Vlv **无内置仿真支持**（社区需外挂 Vlv_Sim 块）——本库设计决策：驱动类组件反向引脚可被上层仿真块替代，不内嵌仿真 |
| 拟平移组件 | FB_DL_SingleSolenoidCyl / I_DL_VacuumGenerator + FB_DL_VacuumEjector / FB_DL_StarDeltaMotor / I_DL_VfdDrive + FB_DL_VfdGeneric / I_DL_ProportionalValve + FB_DL_AnalogValve / I_DL_MotorizedValve + FB_DL_ThreePointValve。**clean-room 声明**：只提取「开关阀/调节阀分类骨架、双反馈合理性冲突语义、超时共用、联锁/覆盖输入分层、电机三层粒度」等通用工程语义；接口命名（I_DL_*）、状态枚举、故障码段全部按本库红线独立设计，变量组织与 DB 结构零参考 |

## S-2｜T1-6 PLCopen 回零（Homing）方式分类（本轮 Motion 回零序列状态机的模式骨架）

| 项 | 内容 |
|---|---|
| 来源名称 | ① Siemens SIMATIC Motion Control MC_Home 模式表（Active/Passive 二分）② Beckhoff Tc3_MC2_AdvanceHoming（PLCopen Part 5 分步回零）③ REXYGEN MC_Home ④ HollySys LX PLCopen 命令手册回零模式表 ⑤ Danfoss MCO 回零参数 |
| URL | ① https://industrialmonitordirect.com/cs/blogs/knowledgebase/siemens-simatic-motion-control-active-vs-passive-homing-commands ② https://www.masterofplc.com/2025/05/detailed-guide-to-advancehoming.html ③ https://www.rexygen.com/downloads/rexygen/doc/3.0.2.16749/ENGLISH/MANUALS/BRef/MCP_Home.html ④ https://www.hollysys.com/Public/Uploads/uploadfile/files/20250212/HollySysLXHighPerformancePLCopenCommand.pdf ⑤ http://danfossbp.weisizhineng.com/company/news/itemid-8999.shtml |
| 许可证 | ①④ 文档版权（免费查阅，闭源）②③⑤ 公开技术文档/教学文章，仅借鉴语义 |
| 提取点 | ① **MC_Home 模式语义表（SIMATIC）**：Mode 2 参考开关+Z 脉冲（主动）/ Mode 3 仅参考开关 / Mode 4 仅 Z 脉冲 / Mode 5 被动（外力移动轴）/ Mode 7 单边沿主动 / Mode 10 扭矩堵转（PROFIdrive）/ Mode 12 堵转+Z 脉冲——主动/被动二分 + 参考源（凸轮/Z 脉冲/扭矩）三维分类矩阵；② **主动回零标准时序**：高速逼近参考凸轮 → 减速 → 反向脱离 → 爬行速度再逼近 → 检测 Z 脉冲 → 实际位置覆写为组态回零位（逼近-回退-再逼近三段式）；③ **Beckhoff 分步范式**：MC_StepAbsoluteSwitch / MC_StepLimitSwitch / MC_StepBlock（扭矩堵转）/ MC_StepReferencePulse + MC_FinishHoming / MC_AbortHoming——回零可拆为步进子块 + 收尾块；④ **HollySys 模式表**：按「方向 N/P × 信号源（N-OT/P-OT/HMSW/Z）× 终点（Z 脉冲/开关下降沿）」组合编号 1~35——证明回零模式是**组合矩阵**而非枚举魔法数；⑤ **防护语义**：回零过程软限位按模式选择性失效；TimeLimit/DistanceLimit 双护栏（REXYGEN）防堵转回零无限行程；Direction 引脚（正/负/最短/当前）；⑥ 被动回零（Mode 5/8）：轴被外力移动时仅监听参考事件、驱动不出力——本轮不实现（留矩阵扩产），规格声明 |
| 拟平移组件 | FB_DL_AxisHomingSeq（四种模式：限位开关回零 / 原点开关回零 / Z 相脉冲精定位 / 扭矩堵转回零；慢速逼近-回退-再逼近-标定原点时序 clean-room；复用 I_DL_MotionAxis 接口，经 MoveVelocity/MoveRelative/Stop 组合出序列）。**clean-room 声明**：不使用任何 MC_/TO_/MC_Step 厂商块，模式编号不用厂商数值（本库用自有 E_DL_HomingMode 枚举），时序按「逼近-回退-再逼近」公开语义独立实现；被动回零语义本轮不落地 |

## S-3｜空调焓值经济器（Economizer）控制判据（本轮 DL_Process 焓差比较块的判据域）

| 项 | 内容 |
|---|---|
| 来源名称 | ① AHU Economizer Control Strategy 技术指南（controlshub.tech）② IAC 工业培训手册第 8 章 HVAC（焓值切换原理图）③ Honeywell W7212 系列经济器逻辑模块数据手册 ④ calcengineer.com 湿空气焓与干球切换失效分析 ⑤ Carrier/Behler-Young 经济器控制器手册（差分焓值模式） |
| URL | ① https://controlshub.tech/en/blog/ahu-economizer-control-strategy/ ② https://iac.university/technicalDocs/industr/ch8.pdf ③ https://prod-edam.honeywell.com/content/dam/honeywell-edam/hbt/en-us/documents/literature-and-specs/datasheets/hbt-bms-W7212-W7213-W7214-Economizer-datasheet-63-2596.pdf ④ https://calcengineer.com/blog/moist-air-enthalpy-total-heat-coil-load ⑤ https://www.behler-young.com/UserFiles/Resource/AIRQSTINST00009.pdf |
| 许可证 | ③⑤ 厂商数据手册（公开查阅，版权文档）①②④ 公开技术文章/培训教材，仅借鉴判据语义 |
| 提取点 | ① **四种切换策略分级**：固定干球切换 / 固定焓值切换（单点设定）/ **差分焓值切换（differential enthalpy：OA 焓 < RA 焓 → 开大新风，否则回最小位）**——差分法最准但要求回风代表室内状态（内热源大房间失效）；② **干球切换的失效机理**：70°F 近饱和新风焓 34 Btu/lb > 75°F/50% 回风焓 28 Btu/lb——干球低不代表总热低，湿工况下干球切换反而增冷负荷（本库以焓差为判据的直接依据）；③ **最小新风位（minimum position）硬约束**：经济器关闭时新风阀不得低于最小新风位（卫生通风底线），Honeywell MIN POS 电位器语义；④ **ASHRAE 90.1 高限停机**：按气候区要求固定焓值高限 + 干球高限双门限（暖湿气候必须焓值法）——本块以可选高限引脚落地；⑤ 混风温度校验公式 (To×OA% + Tr×RA%) = Tm 可作为调试参考（不实现，仅语义引用）；⑥ 焓值传感器漂移是经济器卡在错误模式的常见根因——本块设计「焓差死区 + 有效域检查」防抖动切换 |
| 拟平移组件 | FB_DL_EnthalpyCompareCtrl（直接调用 FC_DL_HumidAirEnthalpy 计算新风/回风双侧焓值 → 差分焓值判据 + 切换死区 → 新风阀位指令 0~100% 输出，钳位最小新风位 fMinOaPos；可选焓值高限停机位）。**clean-room 声明**：判据为公开工程语义（ASHRAE 90.1 思想），实现、引脚、故障码全部自有体系，未参考任何厂商代码 |

## S-4｜变频器控制接口标准信号集（本轮 I_DL_VfdDrive 抽象接口的信号域）

| 项 | 内容 |
|---|---|
| 来源名称 | ① 变频器控制回路端子功能综述（台斯达电子，覆盖三菱/台达/汇川惯例）② Yaskawa VARISPEED-616G5 说明书控制回路端子表 ③ VFD 控制接线教学（industrialmonitordirect）④ 国产变频器端子表（机电之家） |
| URL | ① http://www.kstaian.com/content?3900.html ② https://www.yaskawa.com/delegate/getAttachment?documentId=TOE-S616-10.10D&cmd=documents&documentName=TOE-S616-10.10DVS-616G5InstructionsSpecEandV.pdf ③ https://industrialmonitordirect.com/es/blogs/knowledgebase/wiring-a-vfd-control-circuit-runstop-transformer-footswitch ④ https://www.jdzj.com/p2/2013-5-15/460227.html |
| 许可证 | ② 安川说明书（版权文档，免费查阅）①③④ 公开技术文章，仅借鉴信号分类语义 |
| 提取点 | ① **DI 标准信号集**：正转 FWD/STF、反转 REV/STR、点动 JOG、多段速 SP1~SP3 / RH/RM/RL（三端子组合 1~7 段速）、故障复位 RST/RES、外部基极封锁/自由停车；② **AI 标准信号集**：频率给定 0~10V（VI/AI1）或 4~20mA（IA/AI2），双通道主/辅切换；③ **DO/反馈标准信号集**：运行中（RUN）、零速检测、速度一致（频率到达 ±2Hz）、故障继电器（A/B/C，NO/NC 双形态）、模拟量输出频率/电流监视；④ **多段速组合语义**：N 个 DI 位组合出 2^N−1 段固定频率，段速值由驱动侧参数定义——本库接口以「段号 + 段速数组引脚」抽象，位组合由实现映射；⑤ **点动语义**：JOG 信号 ON 即按点动频率运行、OFF 即停（独立于运行指令源）；⑥ **两线/三线控制**：两线=电平保持运行、三线=瞬时启停+自锁——本库统一取电平语义（两线），三线由调用方自锁；⑦ 4~20mA 给定断线（<2mA）为独立故障——频率给定有效域检查依据 |
| 拟平移组件 | I_DL_VfdDrive（抽象接口：使能/正反转/点动/多段速/频率设定/复位 + 状态属性）+ FB_DL_VfdGeneric（通用端子型变频器驱动实现：频率设定斜坡、正反转互斥、点动优先、多段速选择器、故障码映射表、频率到达反馈校验）。**clean-room 声明**：只提取端子信号分类与多段速组合语义（行业公知），接口方法/属性/枚举/故障码全部按本库体系独立设计 |

## S-5｜星三角降压启动时序 + 三点浮点阀控制语义（本轮 Device 参数域补采）

| 项 | 内容 |
|---|---|
| 来源名称 | ① IndustrialPro 星三角 PLC 顺控教学（含互锁延时 200ms 与报警清单）② IEC/NEMA 星三角转换与定时器设定（industrialmonitordirect）③ 星三角接线与死区时间教学（wiringwork/wiringcentral） |
| URL | ① https://industrialpro.in/ladder-logic/project/star-delta-starter ② https://industrialmonitordirect.com/zh-hant/blogs/knowledgebase/wye-delta-motor-starter-wiring-transition-and-timer-setup ③ https://www.wiringwork.com/wiring-star-delta-motor-starter/ + https://www.wiringcentral.com/3-phase-motor-wiring-diagram-star-delta |
| 许可证 | 公开教学文章，仅借鉴通用工程语义（星三角时序为行业公知，不涉专有代码） |
| 提取点 | ① **星三角三层互锁**：星/角接触器电气互锁（常闭辅助触点串入对方线圈）+ 机械互锁 + **转换死区时间 50~200ms**（星接触器分断、电弧熄灭后方可合角接触器，否则相间短路）——死区为独立可调参数非魔法数；② **星形运行时间**：按负载实测加速时间整定（泵/风机典型 5~15s），过早切换电流尖峰近似 DOL；③ **接触器反馈校验**：KM1/KM2/KM3 辅助触点逐一回读，指令-反馈不匹配立即故障停机（A003）；星角转换失败（A004）独立报警；④ **过载保护**：热继电器主回路脱扣锁存、需人工确认复位；⑤ 三点浮点阀（three-point floating / step control）行业语义（结合 LBP_VlvA 与 S-1 阀门分类）：开/关/停三态脉冲输出，无阀位反馈时按行程时间积分**自动估算当前开度百分比**，全开/全关限位保护（估算到端点后停止发脉冲防电机堵转），有反馈时以脉冲宽度微调 |
| 拟平移组件 | FB_DL_StarDeltaMotor（星角切换死区互锁 + 三接触器反馈校验 + 热继过载锁存 + 防频繁启动，复用 FB_DL_DolMotor 已确立的启动抑制范式）、I_DL_MotorizedValve + FB_DL_ThreePointValve（开度积分估算 + 行程时间参数 + 端点限位保护）。**clean-room 声明**：上述均为语义/故障分类借鉴，接口命名、状态机、故障码按本库红线独立设计 |

---

## 配额核对

| 配额 | 要求 | 本轮落地 |
|---|---|---|
| ≥1 个组件族来自 T2 非 ST 源 | 硬性 | **S-1 T2-2 LBP 阀门/驱动族（10 项，深化）+ S-4 变频器端子语义补采 + S-5 星三角/三点阀补采** |
| ≥1 个来自 T1 ST 原生源 | 硬性 | **S-2 T1-6 PLCopen Motion 回零族（3 项，T1-6 首次开组）** |
| 禁止重复挖掘已 ✔ 组 | 铁律 | T1-6 PLCopen Motion 由 ☐ → ◐（首次开组）；T2-2 LBP 由 ◐ 深化（阀门组开挖，矩阵既定 R6 优先）；T2-1 LGF Technology ◐ 深化（RampSoak 归 Technology 组曲线族）；T1-2 OSCAT Building ◐ 深化（EnthalpyCompareCtrl 为 9.5 节 P0 既定上层消费者）；未触碰任何已收口组 |
| RAW_NOTES 来源/URL/许可证/提取点留痕 | 铁律 | 本文件 S-1~S-5 全覆盖 |

## 收尾回写清单（编码阶段完成后执行）

1. SOURCE_HUNTING_MATRIX.md 第 5 节：T1-6 PLCopen Motion → ◐（FB_DL_AxisHomingSeq、FB_DL_AxisRelativeMove、FB_DL_AxisVelocityMove）；T2-2 LBP → ◐ 深化备注（阀门/驱动族 10 件）；T2-1 LGF·Technology → ◐ 深化备注（RampSoakProfile）；T1-2 OSCAT Building → ◐ 深化备注（EnthalpyCompareCtrl、OccScheduleWindow）。
2. 新组件 function_tags 挂来源组标签：lbp-basic-process / lbp-device / plcopen-motion / s7-motion / oscat-building / lgf-datetime / hvac / lgf-technology。
3. AGENT_EVOLUTION_LOG.md 追加 R6 章节；ROADMAP.md 勾选 16 项并回写批处理进度。
