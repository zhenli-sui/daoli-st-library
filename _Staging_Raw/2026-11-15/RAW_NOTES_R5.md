# RAW_NOTES_R5 —— Round 05 狩猎检索记录

> 轮次：R5（2026-11-15）｜ 方向：DL_Device 开库 + DL_Motion/DL_Process 立项前置狩猎
> 执行人：道莅工控代码库产品总监（兜底模式）
> 检索时间：2026-11-15 凌晨（R5 计划阶段，共 6 次 WebSearch）
> 合规基线：SOURCE_HUNTING_MATRIX.md 第 0 节三条铁律。闭源资产只提取「功能分类 / 接口参数域 / 状态机语义」，实现全部 clean-room。

---

## S-1｜T2-7 PackML / OMAC 17 态状态机（本轮 Process 族规范源）

| 项 | 内容 |
|---|---|
| 来源名称 | Siemens Automation Framework V2.2 文档（State Model 章节，引用 OMAC PackML / ISA-TR88.00.02） |
| URL | https://support.industry.siemens.com/cs/attachments/109817223/109817223_AutomationFramework_DOC_V2_2_2_en.pdf |
| 辅助来源 | ① https://support.industry.siemens.com/cs/attachments/109997591/109997591_DualBagPackagingMachine_DOC_V1_0_en.pdf（双袋包装机 AF 应用实例）② https://itotconvergentie.nl/en/packml（PackML 独立科普页：acting/wait 态分类、模式定义） |
| 许可证 | 西门子文档：文档版权（免费查阅，闭源）｜ PackML 本体：公开规范（ISA-TR88.00.02 技术报告，非正式标准） |
| 提取点 | ① 17 态全表及编号（Undefined=0, Clearing=1 … Completed=17）；② 11 个标准命令（Reset/Start/Stop/Hold/Unhold/Suspend/Unsuspend/Abort/Clear/Complete/StateComplete）；③ Acting 态（自动推进）与 Wait 态（等命令）两类划分——Clearing/Starting/Suspending/Unsuspending/Unholding/Holding/Completing/Stopping/Aborting/Resetting 为 acting，Stopped/Idle/Suspended/Execute/Aborted/Held/Completed 为 wait；④ Unit 模式：Production(1)/Maintenance(2)/Manual(3)/自定义(4..15)；⑤ Held（机内原因暂停）与 Suspended（机外原因暂停）的语义区分是 OEE 数据质量的根基；⑥ 模式切换只允许发生在稳定 Wait 态 |
| 拟平移组件 | FB_DL_PackMlStateMachine（17 态 + 11 命令，ENUM+CASE+ELSE，非法态兜底走 Aborting 路径）、FB_DL_PackMlCmdDecoder（多命令源优先级仲裁 + 单发化）。**clean-room 声明**：只提取状态编号、命令集合与跃迁语义（公开规范内容），不参考任何西门子 LUC 代码结构，不复制其 DINT 变量组织方式——本库用 E_DL_PackMlState 枚举而非裸 DINT，变量名/引脚名全部自有体系 |

## S-2｜T2-4 西门子 S7-1500 Motion Control（Motion 族对象模型源）

| 项 | 内容 |
|---|---|
| 来源名称 | SIMATIC S7-1500/S7-1500T Motion Control 轴功能手册 / 总览手册 / 工艺对象文档 |
| URL | ① https://support.industry.siemens.com/cs/attachments/109812057/s71500_s71500t_axis_function_manual_en-US_en-US.pdf ② https://support.industry.siemens.com/cs/attachments/109812056/s71500_s71500t_motion_control_overview_function_manual_en-US_en-US.pdf ③ https://cache.industry.siemens.com/dl/files/134/109743134/att_928448/v2/109743134_S7-1500T_TechnologyObjects_DOC_v10_en.pdf ④ StatusWord 位定义：https://www.manualslib.com/manual/1281230/Siemens-Simatic-S7-1500.html?page=351 |
| 许可证 | 文档版权（免费查阅，闭源） |
| 提取点 | ① 工艺对象分型语义：SpeedAxis（无位置反馈）/ PositioningAxis（位置闭环）/ SynchronousAxis / ExternalEncoder——本库 DL_Motion 首批只做 PositioningAxis 语义；② PLCopen 指令-动作映射：MC_Power（使能）/ MC_Reset（确认报警）/ MC_Home / MC_MoveAbsolute / MC_MoveRelative / MC_MoveVelocity / MC_MoveJog / MC_Halt / MC_Stop（停止并拒绝新任务）；③ StatusWord 关键位语义：Enable / Error / HomingDone / Done / Standstill / PositioningCommand / JogCommand——本库抽象为 bEnabled/bError/bHomed/bStandstill/bBusy 状态属性；④ PLCopen 轴状态机：Disabled → Standstill → Homing → DiscreteMotion / ContinuousMotion → Stopping → ErrorStop（源自 PLCopen 状态模型，西门子手册与中文社区帖 https://bbs.plcjs.com/thread-514953-1-499.html 双重印证） |
| 拟平移组件 | I_DL_MotionAxis（轴抽象接口：使能/复位/回零/绝对/相对/速度/停止 + 状态属性）、FB_DL_SingleAxis（PLCopen 六态状态机的 clean-room 实装，位置用虚拟积分器闭环）、FB_DL_AxisJogController（点动/寸动，低速自动切换高速 + 软限位拦截）。**clean-room 声明**：不使用 TO_/MC_ 任何西门子对象与代码，状态机按 PLCopen 公开语义独立实现，位置虚拟积分由本库自有 FB_DL_SCurveGenerator 思路扩展 |

## S-3｜T2-1 LGF · Date and Timer 组（本轮 T2 非 ST 源配额之一，开组）

| 项 | 内容 |
|---|---|
| 来源名称 | Siemens LGF（Library of General Functions）V5.2.1 / V1.0.1 手册 · 3.1 Date and timer operations 章 |
| URL | ① https://support.industry.siemens.com/cs/attachments/109479728/109479728_LGF_DOC_V5_2_1_en.pdf ② https://cache.industry.siemens.com/dl/files/728/109479728/att_858193/v1/109479728_LGF_DOCU_V1_0_1_en.pdf ③ 中文评测（时间类 9 FC 清单佐证）：https://bbs.plcjs.com/thread-642526-1-6.html |
| 许可证 | 免费使用但闭源版权（矩阵 T2-1 既定结论） |
| 提取点 | ① 多段定时开关的**参数域**：onHour/onMinute/offHour/offMinute/onWeekday(星期日=1…星期六=7)/onDay/onMonth + mode（0 常关 / 1 每日 / 2 每周 / 3 每月 / 4 每年 / 5 工作日 / 6 周末 / 10 常开）；② 状态码体系：16#7FFF 段状态 / 16#8xxx 段错误（statusWord 语义，本库故障码表借鉴分段风格）；③ LGF 时间类 FC 粒度清单：GetCalendarDay（年内第几天）、GetCalendarWeek_ISO/_US（周数）、AstroClock（日出日落）——**日历/星期计算粒度确认可拆为独立 FC**；④ LGF 定时开关依赖 RD_LOC_T 读 CPU 本地时间——本库 **禁止**此耦合（零全局耦合红线），时间一律由引脚注入 |
| 拟平移组件 | FC_DL_DayOfWeekCalc（年月日 → 星期几，ISO-8601 星期一=1…星期日=7，Sakamoto/蔡勒算法 clean-room 实现；与 LGF 的星期日=1 惯例差异在规格书中显式声明并说明理由——ISO 序号与 GB/T 及 MES 排产惯例一致）、FB_DL_TimeWindowCheck（每日/跨零点时间窗判定，时间由输入引脚注入而非读 CPU 钟；mode 巨无霸反例——本库只做「每日窗」单一语义，每周/每月窗留待矩阵扩产拆块）。**本组件族即「T2 非 ST 源」配额的 LGF 未挖掘组落地** |

## S-4｜DL_Device 器件接口参数域狩猎（气缸 / 电机）

| 项 | 内容 |
|---|---|
| 来源名称 | 工业气动气缸 FB 设计指南（社区教学资料）+ 西门子 LOGO! 气缸应用帖 + DOL 电机保护惯例 |
| URL | ① https://industrialctrls.com/?p=3599（气缸 FB 状态图/故障码/防抖/仿真模式最佳实践）② https://industrialmonitordirect.com/cs/blogs/knowledgebase/siemens-logo-8-cylinder-control-with-stroke-counting-and-reed-switches（双电控 5/2 阀 + 磁性开关 + 行程计数接线语义）③ https://bobteachestech.com/blog/tech/articles/how-to-build-an-electro-pneumatic-reciprocating-system-with-a-5-2-solenoid-valve（双线圈禁止同时得电互锁） |
| 许可证 | 公开教学文章，仅借鉴通用工程语义（气缸控制语义为行业公知，不涉专有代码） |
| 提取点 | ① 状态集合惯例：Idle/Extending/Extended/Retracting/Retracted/Fault；② 故障惯例：伸出超时 / 缩回超时 / 双传感器同时动作（位置冲突）/ 无指令位移；③ 双电控阀**双线圈互斥**硬约束；④ 磁开信号需 10~20 ms 防抖（可直接复用本库 FB_DL_SignalDebounce）；⑤ 行程计数按「缩回到位上升沿」累计；⑥ DOL 电机侧：接触器反馈校验（指令-反馈 500ms 窗）、热继电器过载锁存、防频繁启停（重启抑制冷却时间）为行业公知语义（与矩阵 T2-2 LBP 电机组语义一致，LBP 组已 ◐ 开组，本条作为参数域补采） |
| 拟平移组件 | I_DL_Cylinder + FB_DL_PneumaticCylinder（双电控）、I_DL_MotorDriver + FB_DL_DolMotor（直接启动）。**clean-room 声明**：上述来源均为语义/故障分类借鉴，接口命名、状态机、故障码全部按本库红线独立设计 |

## S-5｜NAMUR NE43 模拟量变送器诊断域（变送器/温控区参数域）

| 项 | 内容 |
|---|---|
| 来源名称 | NAMUR NE43 信号电平域（多来源交叉印证） |
| URL | ① https://www.currycontrols.com/tables/4-20-ma-reference ② https://www.ics-schneider.de/?lang=en&p=12280555（温度变送器断线 Up/Downscale 配置）③ https://episensor.com/knowledge-base/analogue-signal-commissioning ④ https://argatech.com/en/4-20-ma-troubleshooting-monitoring |
| 许可证 | 公开工业标准语义（NAMUR NE43 为公开推荐实践） |
| 提取点 | ① 有效测量域 3.8~20.5 mA；故障域 <3.6 mA（Downscale）/ >21 mA（Upscale）；0 mA = 回路断线；② 故障方向可配置且必须在 PLC 侧显式判定（不能把故障电流当过程值）；③ 断线诊断须放在**原始 mA 域**而非工程量域（工程量重标定会移动阈值）；④ 热电偶断偶（开路）= 温控区安全方向判定（升温对象 Upscale、按对象安全策略定）；⑤ 超量程 20~20.5 mA 标记而非剔除 |
| 拟平移组件 | I_DL_AnalogSensor + FB_DL_AnalogTransmitter（内嵌 FC_DL_LinearScale 标定 + FB_DL_MovingAverage 滤波 + NE43 四段诊断：<3.6 断线低 / 3.8~4 欠量程 / 20~20.5 过量程 / >21 断线高 + HH/H/L/LL 四级报警）、I_DL_TemperatureZone + FB_DL_HeatCoolZone（断偶保护方向可配置，内嵌 FB_DL_PidController + FB_DL_PwmDutyController + FB_DL_SplitRangeControl——R4 算法族首个上层消费者） |

## S-6｜T1 ST 原生源 · OSCAT Building（本轮 T1 配额，开组）

| 项 | 内容 |
|---|---|
| 来源名称 | OSCAT Building 库（HVAC 物理
计算族）+ PsychroLib 公式集（交叉印证） |
| URL | ① 功能清单：https://www.tecomat.cz/en/sw-nastroje/mosaic-programovani-plc/knihovny-rozsireni/open-source-knihovny/oscat-building ② CODESYS 官方帮助对 OSCAT Building 物理计算族的背书：https://content.helpme-codesys.com/en/libs/Building%20Automation/1.0.0.0/BuildingAutomation/Doc/other_ressourcesrst.html ③ 许可证与架构：https://oscat.readthedocs.io/en/latest/ + https://eclipse.dev/oscat/ ④ PsychroLib 函数清单：https://github.com/Martin-Yun/psychrolib/blob/master/docs/overview.md |
| 许可证 | OSCAT 现行库 EPL-2.0（可商用、需保留声明）；历史遗留库按原许可、免费使用；PsychroLib 为 MIT 类宽松许可。本库仅借鉴 AIR_ENTHALPY 的**行为定义**（输入 T/RH → 输出湿空气焓），公式本身为公开物理公式 |
| 提取点 | ① OSCAT Building 物理计算族清单：AIR_ENTHALPY（湿空气焓 0~100 ℃）/ AIR_DENSITY / DEW_TEMP / DEW_CON / SDD（饱和蒸汽压）/ WATER_ENTHALPY——确认「焓值族」为 DL_Algo/DL_Process 间的独立原子件；② PsychroLib 证实标准公式链：饱和蒸汽压 → 含湿量 W → 焓 h = 1.006·T + W·(2501 + 1.86·T) kJ/kg 干空气；③ 焓值是暖通 Economizer（ROADMAP 7.5 待办池 `FB_DL_AhuEconomizer`）的前置依赖 |
| 拟平移组件 | FC_DL_HumidAirEnthalpy（DL_Algo，来源标签 oscat-building + psychrolib）。**clean-room 声明**：只取「输入/输出行为定义 + 公开物理公式」，不读取不复制任何 OSCAT 源码行；Magnus 饱和蒸汽压实现与本库已有 FC_DL_DewPointCalc 同源不同函数（复用常量口径） |

---

## 配额核对

| 配额 | 要求 | 本轮落地 |
|---|---|---|
| ≥1 个组件族来自 T2 非 ST 源（优先 LGF 未挖掘组或 Motion/PackML） | 硬性 | **三族**：S-3 LGF Date and Timer（开组，2 项）+ S-2 Motion Control（开组，3 项）+ S-1 PackML（开组，2 项） |
| ≥1 个来自 T1 ST 原生源 | 硬性 | **一族**：S-6 OSCAT Building（开组，1 项） |
| 禁止重复挖掘已 ✔ 组 | 铁律 | 本轮新增组：LGF Date and Timer（原 ☐）、T2-4 Motion（原 ☐）、T2-7 PackML（原 ☐）、T1-2 OSCAT Building（原 ☐）；Device 四件套为 ROADMAP 既定 P1 + LBP/T2-6 参数域补采，不触碰任何已收口组 |
| RAW_NOTES 来源/URL/许可证/提取点留痕 | 铁律 | 本文件 S-1~S-6 全覆盖 |

## 收尾回写清单（编码阶段完成后执行）

1. SOURCE_HUNTING_MATRIX.md 第 5 节：T2-1 LGF·Date and Timer → ◐（FC_DL_DayOfWeekCalc、FB_DL_TimeWindowCheck）；T2-4 Motion Control → ◐（I_DL_MotionAxis、FB_DL_SingleAxis、FB_DL_AxisJogController）；T2-7 PackML → ◐（FB_DL_PackMlStateMachine、FB_DL_PackMlCmdDecoder）；T1-2 OSCAT Building → ◐（FC_DL_HumidAirEnthalpy）；T2-2 LBP → ◐ 深化备注（Device 四件套）。
2. 新组件 function_tags 挂来源组标签：packml / s7-motion / plcopen / lgf-datetime / oscat-building / psychrolib / namur-ne43 / lbp-device。
3. AGENT_EVOLUTION_LOG.md 追加 R5 章节；ROADMAP.md 待办池按矩阵第 6 节扩产。
