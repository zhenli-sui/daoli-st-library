# BATTLE_REPORT_R4 — Round 04 战报（DL_Algo 开库 · 16 组件）

> 日期：2026-11-15 ｜ 撰写：道莅工控代码库产品总监
> 配套文件：`ROUND_PLAN_R4.md`（规格）、`AUDIT_R4.md`（终审）、`RAW_NOTES_R4.md`（狩猎情报）
> 数字口径：与 `INDEX_REGISTRY.json`（total_components=56, version=1.3.0）逐项一致。

---

## 一、本轮概览

| 项目 | 值 |
|---|---|
| 轮次 | Round 04（Phase 1 第四轮） |
| 时间 | 2026-11-15 01:35 → 02:0x（约 30 分钟，完成时刻口径计入 11-15） |
| 范围 | Level 1 `DL_Algo` 开库并收口（原计划 15 项 + 矩阵扩产补充项 1 项） |
| 组件数 | **16 个**（14 FB + 2 FC） |
| 新增行数 | **4035 行**，零占位符 |
| 专家召唤模式 | **兜底模式**（原生 daoli-library-director / plc-programming-expert 两次尝试均 not available；总监规划+终审、PLC 编程专家兜底会话内编码+自检，双角色分离纪律全程未放松） |
| 库版本 | v1.2.0 → **v1.3.0**（新增组件走 MINOR） |
| 终审结论 | 16/16 PASS（10 个 PASS(修后)），修复缺陷 16 处（含致命 2 处），修后机检 ALL PASS |

## 二、新增组件清单（16 项）

| # | 组件 | 类型 | 复杂度 | 来源标签 | 一句话定位 |
|---|---|---|---|---|---|
| 1 | `FB_DL_PidController` | FB | 8 | mod-pid-control / lgf-technology / oscat-basic | 工业级 PID：积分分离、两级抗饱和、手自动真无扰 |
| 2 | `FB_DL_CascadePid` | FB | 8 | mod-pid-control / lgf-technology | 主副串级：副设定域钳位 + 参数单点注入 + 主环跟踪 |
| 3 | `FB_DL_SplitRangeControl` | FB | 5 | mod-pid-control / lgf-technology | 单输出分程分配加热/冷却双执行器，中央死区防双阀同开 |
| 4 | `FB_DL_FeedforwardComp` | FB | 6 | lgf-technology | 静态+动态前馈（惯性/超前滞后/纯滞后队列） |
| 5 | `FB_DL_SmithPredictor` | FB | 9 | lgf-technology / mod-pid-control | 一阶+纯滞后模型补偿，学习态退化不阻塞控制 |
| 6 | `FB_DL_RateLimiter` | FB | 4 | lgf-technology / lgf-signalgen | 变化率限制器（**矩阵扩产补充项**，超配立项） |
| 7 | `FB_DL_RampGenerator` | FB | 5 | lgf-signalgen / lgf-technology | 设定值斜坡：独立升降速率、暂停保持、跟踪回投 |
| 8 | `FB_DL_SCurveGenerator` | FB | 9 | lgf-signalgen / lgf-technology | 七段式 jerk 限制 S 型轨迹，剩余距离自适应截断 |
| 9 | `FB_DL_PwmDutyController` | FB | 6 | lgf-signalgen / mod-pid-control | 慢速时间比例 PWM（SSR 加热），欠脉冲跨周期累加补偿 |
| 10 | `FB_DL_Integrator` | FB | 5 | lgf-math / oscat-basic | 梯形法积分器，LREAL 累加防长时漂移 |
| 11 | `FB_DL_Differentiator` | FB | 6 | lgf-measurement / oscat-basic | 带低通的实用微分器，抑制高频噪声放大 |
| 12 | `FB_DL_LowPassFilter` | FB | 5 | lgf-measurement | 一阶低通 PT1，时间常数运行时可调 |
| 13 | `FB_DL_SecondOrderFilter` | FB | 7 | lgf-measurement | 二阶巴特沃斯 biquad，奈奎斯特自动钳位 |
| 14 | `FB_DL_HighPassFilter` | FB | 5 | lgf-measurement | 一阶高通，振动/趋势分量提取 |
| 15 | `FC_DL_DewPointCalc` | FC | 4 | oscat-basic / hvac | Magnus-Tetens 露点计算，附水汽压复用输出 |
| 16 | `FC_DL_FlowCompensate` | FC | 5 | oscat-basic / gas-metering | 气体流量温压补偿，工况 → 标况 Nm³/h |

依赖图谱：`CascadePid` 与 `SmithPredictor` 内部组合 `PidController` 实例，其余 13 个零 DL_ 内部依赖；全库反向依赖（依赖 Device/Motion/Process）= 0。

## 三、今日累计与差距分析

- **今日 30 / 200，达成率 15.0%，缺口 170**（2026-11-15 完成时刻口径；R3 跨零点计入 11-15 的 14 项 + 本轮 16 项）。
- 单轮吞吐稳定在 14~16 项 / 30~40 分钟；今日已完成 2 轮。
- **差距根因（按贡献度排序）**：
  1. **单会话串行流水线**：狩猎→规格→编码→终审→文档五段全串行，200/日 需要 ≥ 4 条并行编码线（R1 第五节方案，前置条件「文档模板化 + 机检脚本化」仍未落地）。
  2. **手册双语文档占时过半**：本轮 16 个组件的双语 MANUAL 段与终审读码合计远超编码耗时。
  3. **兜底模式尚未并行化**：兜底会话内 PLC 专家仍是单线作业。
- **结论**：吞吐瓶颈不在编码产能，在「验」与「文档」两段的结构性串行；在机检脚本化与手册模板化完成前，单日 3~4 轮（约 50~64 项/日）是质量红线内的现实上限。

## 四、总库规模与节奏预估

- **总库 56 / 10,000**（0.56%），版本 v1.3.0；Phase 1 首批 56 / 100。
- 子库进度：`DL_Base` 20/20 ✅ ｜ `DL_MathData` 20/20 ✅ ｜ **`DL_Algo` 16/15 ✅（超配 1 项收口）** ｜ `DL_Device` 0/17 ｜ `DL_Motion` 0/12 ｜ `DL_Process` 0/15。
- **节奏推算**（每轮 16 项、每日 2 轮 = 32 项/日）：
  - 剩余 10,000 − 56 = 9,944 项 → 9,944 ÷ 32 ≈ **311 天**（约 10.4 个月）。
  - 若提升到每日 4 轮（64 项/日，需并行流水线落地）→ ≈ **156 天**（约 5.2 个月）。
  - 若达成 200/日 目标 → ≈ **50 天**。
- **判读**：以当前串行流水线的 32 项/日为基线，10,000 目标约需 10 个月；并行化（R1 第五节四件事）是唯一能显著压缩周期的杠杆，其中「编译验证 P0」与「机检脚本化」必须先行——没有质量兜底的吞吐是在给 10 个月后的自己埋雷。

## 五、本轮所用源与借鉴点（逐条）

| 源 | 借鉴了什么 | 落到哪个组件 | clean-room 怎么保证 |
|---|---|---|---|
| **T2-1 LGF Signal Generators**（西门子，闭源文档） | 组内粒度按「信号形状」切分：发生器（斜坡/S 曲线/PWM）归一组；参数域与相位复位的接口惯例 | `FB_DL_RampGenerator`、`FB_DL_SCurveGenerator`、`FB_DL_PwmDutyController` | 全程只读文档不读代码；引脚名/状态机/故障码（16#0002_06xx/07xx/08xx）为本库自有体系；头注释 Origin 标注「原创实现（参考 LGF 分类与参数域）」 |
| **T2-1 LGF Technology**（同上） | LimRateOfChange 的「0 = 该方向不限速」语义；前馈/纯滞后补偿的功能语义；卷径/张力族清单（待挖储备） | `FB_DL_RateLimiter`、`FB_DL_FeedforwardComp`、`FB_DL_SmithPredictor` | 同上；RateLimiter 由组语义直接立项为矩阵扩产补充项，实现从零起草（含 0002 公共码域） |
| **T2-1 LGF Measurement**（同上） | 「滤波归测量、发生归信号」的组边界；PT1/二阶/高通的行为定义与「滤波时间常数运行时可调」惯例 | `FB_DL_LowPassFilter`、`FB_DL_SecondOrderFilter`、`FB_DL_HighPassFilter`、`FB_DL_Differentiator` | 双线性变换系数、状态机（eInit/eCoeffCalc/eRun/eTrack）为本库设计；biquad 结构是教科书通用形式，无源码对照 |
| **T2-5 Mod_PID_Control**（西门子手册，闭源） | 参数域语义：Ti/Td=0 表示关闭该项而非非法；「手自动切换必须无扰」的强制义务；死区/积分分离的参数组织 | `FB_DL_PidController`、`FB_DL_SplitRangeControl` | 抗饱和两级设计（触限停积分 + 限幅反算回填）由总监从控制理论独立推导，其中回填思想与 OSCAT FT_PIWL 同源（见下行）；手册仅提供参数域与义务清单 |
| **T1-1 OSCAT Basic**（OSCAT 许可，开源） | ① 反作用增益惯例（Kp 为负）；② FT_PIWL 限幅反算思想（clean-room 重写）；③ FT_INT2 双精度累加思想；④ Magnus-Tetens / 理想气体换算的工程边界惯例（钳位、有效域披露）；⑤ 反面教材：MODE 巨无霸块——本轮 16 个组件零模式枚举堆砌 | `FB_DL_PidController`、`FB_DL_Integrator`、`FB_DL_Differentiator`、`FC_DL_DewPointCalc`、`FC_DL_FlowCompensate` | 开源但本轮同样只取行为定义不逐行对照；公式为公开教科书公式（Stull 近似、理想气体定律）；Delta 量：本库把「一组件一语义」「信息级/故障级分离」「非有限值防御全覆盖」做成源所不具备的现场级保证 |

**合规台账**：本轮 0 行源码复制；LGF / Mod_PID_Control 为闭源资产仅借鉴分类与参数域（铁律 1）；OSCAT 为免费开源需致谢（铁律 2）；全部 16 个 .st 头注释 Origin 字段留痕，JSONL function_tags 保留来源组标签（铁律 3）。

## 六、质量与终审

- **终审 16/16 PASS**（全部逐行通读，未抽样）；10 个组件修后通过，改动 10 个文件，版本 1.0.0 → 1.0.1（PATCH：未动对外引脚契约）。
- **缺陷 16 处**，构成：
  - **致命 2 处**：`FB_DL_Integrator` / `FB_DL_SCurveGenerator` 首扫判据反向（`IF bInit OR bTrack` + `bInit:=TRUE`）——一次跟踪脉冲后每拍强制覆盖，**积分器/轨迹永久锁死**。同模板 ×3 扩散（RampGenerator 同判据但后果较轻）。
  - 工程语义 9 处：手动期历史不同步（手→自踢腿）、SCurve 到位后「先吸附再判新目标」恒差 0（新目标永不触发）、PwmDuty 首周期配额未结算（100% 加热首 10s 无输出）、SecondOrderFilter 首扫分支不可达（首拍跳零）、FlowCompensate 非有限值防御漏 3 参数（NaN 带无故障码穿透）、FeedforwardComp 把合法直通配置置码等。
  - 注释/量纲 5 处：`%` 与 `EU·s` 混写、`fTrackValue` 量纲与限幅域不符（含 1 处规格书勘误随代码修正）。
- **新范式沉淀 3 条**（本轮口径 R8~R10；正式入册编号 R19~R21，主规则库既有 R8~R18 已占用、按「编号只增不改」顺延，语义一一对应）：
  - **R8 首扫标志唯一合法范式**（→ R19）：`IF bInit OR bTrack THEN ... bInit := TRUE` 双向皆错——首扫永不触发（初值 FALSE 判据只剩 bTrack）+ 一旦触发每拍触发（bInit 恒真）。唯一合法形式 `IF bTrack OR (NOT bInit)`；并强制验收向量含「运行中途插入跟踪脉冲」向量。
  - **R9 量纲注释与算法一致**（→ R20）：变量量纲标注 = 赋值表达式量纲推导结果；跟踪/输出量纲 = 限幅域量纲；`%` 与 `EU·s` 不得混写。
  - **R10 信息级诊断码不得置 bError**（→ R21）：饱和/钳位/截断是调节常态或自愈行为，只进 uErrorId 趋势不进报警链；故障码表强制标注信息级/故障级。
- **元教训**：16 处缺陷中 6 处出自同一错误模板在三组组件间的复制扩散——公共约定以「参考上一组件写法」传递时，错误也跟着传递；R05 起规格书第 0 节固化「首扫判据文本模板 + bError 派生式模板」并进机检。
- 修后机检 ALL PASS：禁用记号 0、占位符 0、声明双语注释 100%、终结符成对、IF/CASE 配平、CASE 全带 ELSE、行数 180~360（详见 `AUDIT_R4.md` §五）。

## 七、下一轮计划（Round 05）

**方向：`DL_Device` 开库 + `DL_Algo` 补强，16 项。** 理由：DL_Process 的 15 项全部经 `I_DL_*` 接口依赖注入，`DL_Device` 四件套不开则 Level 2 永远无法启动；温控区是 R4 算法族的首个上层消费者。

| # | 组件 | 理由 |
|---|---|---|
| 1 | `I_DL_Cylinder` + `FB_DL_PneumaticCylinder` | 双电控气缸标准接口与状态机驱动——DL_Process 所有机站动作层的最小公共件，`FB_DL_PickAndPlaceStation` 直接依赖 |
| 2 | `FB_DL_SingleSolenoidCyl` | 复用 `I_DL_Cylinder` 接口证明抽象有效；无传感器纯时间模式覆盖大多数气动场景 |
| 3 | `I_DL_VfdDrive` + `FB_DL_VfdGeneric` | 通用变频器接口（频率/正反转/点动/多段速/故障码映射）——风机泵类与输送线驱动底座 |
| 4 | `I_DL_AnalogSensor` + `FB_DL_AnalogTransmitter` | 4~20mA/0~10V 变送器（量程标定 + 四级报警 + 断线诊断，内嵌 `FC_DL_LinearScale` / `FB_DL_MovingAverage`）——一切模拟量工艺块的入口 |
| 5 | `I_DL_TemperatureZone` + `FB_DL_HeatCoolZone` | 温控区对象：内嵌 `FB_DL_PidController` + `FB_DL_PwmDutyController` + `FB_DL_SplitRangeControl` + 断偶保护——**R4 算法族首个上层消费者** |
| 6 | `I_DL_VacuumGenerator` + `FB_DL_VacuumEjector` | 真空发生器（真空建立超时/破真空脉冲/负压校验）——拾放工站依赖 |
| 7 | `FB_DL_StarDeltaMotor` | 星三角降压启动（星角切换安全死区互锁）——`I_DL_MotorDriver` 系第一块拼图 |
| 8 | `I_DL_ProportionalValve` + `FB_DL_AnalogValve` | 模拟量调节阀（阀位偏差报警 + 零点死区补偿）——过程控制行业池 19 项的共同底座 |
| 9 | `FB_DL_RampSoakProfile`（DL_Algo） | Ramp/Soak 多段程序曲线——温控区设定源，烘箱/烧结炉/化成柜共用；DL_Algo 补强头牌 |
| 10 | `FB_DL_NotchFilter`（DL_Algo） | biquad 陷波变体——机械共振频率抑制，SecondOrderFilter 同族扩产（矩阵规则 2） |
| 11 | `FB_DL_GainScheduler`（DL_Algo） | 增益调度——按工作点查表平滑切换 PID 参数，防参数突跳 |
| 12 | `FB_DL_PidControllerLReal`（DL_Algo） | LREAL 高精度 PID 变体——**源矩阵扩产规则 1「类型重载」首例落地**，验证矩阵化工法 |
| 13 | `I_DL_MotorDriver` + `FB_DL_DolMotor` | 直接启动电机（接触器反馈校验 + 热继过载 + 防频繁启停） |
| 14 | `I_DL_TowerLight` + `FB_DL_SignalTower` | 三色安灯塔（闪烁模式驱动）——每个工站 HMI 之外的物理报警出口 |
| 15 | `I_DL_SafetyDoor` + `FB_DL_GuardLockDoor` | 安全门联锁（先请求停机→确认静止→解锁开门时序） |
| 16 | `I_DL_BarcodeScanner` + `FB_DL_SerialScanner` | 固定式扫码枪异步触发与超时重试封装——DL_Process 追溯类模板依赖 |

配套动作：① **P0** 建最小 CODESYS V3.5 工程，全库 56 个 POU 真实编译 + DL_Algo 验收向量回放（连续三轮 P0 顺延，本轮不再顺延）；② 规格书第 0 节固化 R19/R21 文本模板 + AUDIT_R4 三条范式候选；③ `I_DL_*` 接口契约新增「方法 + 属性 + 状态枚举」三段式规格模板；④ 源狩猎：T2-4 Motion / T2-7 PackML 标记 R5 优先（DL_Motion / DL_Process 立项前置），T1-2 OSCAT Building 在暖通行业池立项前必须先挖。

## 八、风险清单

| # | 风险 | 等级 | 状态 |
|---|---|---|---|
| 1 | **编译验证 P0 未决**：全库 56 个 POU 从未在 CODESYS V3.5 / TwinCAT 3 / InoProShop 任一环境真实编译；TIME 比较、显式类型转换、枚举作用域等方言风险只能真机暴露。本轮 2 处致命缺陷全靠人工读码抓出，机检对控制律语义失明 | **P0（连续三轮顺延，本轮起强制排期）** | Round 05 首个动作 |
| 2 | **吞吐不足 200/日**：今日 30/200（15.0%）。瓶颈在「终审读码 + 双语手册」两段串行；并行流水线的前置条件（机检脚本化、手册模板化）仍未落地 | P1 | R05 承接；10,000 目标按 32/日基线约需 311 天，并行化可压至 156 天 |
| 3 | **四个 ☐ 源未动**：T1-2 OSCAT Building / T2-4 Motion / T2-6 Rockwell AOI / T2-7 PackML 均未开挖；T2-4 与 T2-7 是 DL_Motion / DL_Process 立项的规范前置 | P1 | T2-4 / T2-7 已在源矩阵标注「R5 优先」 |
| 4 | 模板扩散缺陷形态：同一错误模板在组件间复制会放大为 N 处缺陷（本轮 6/16）；依赖规格书文本模板 + 机检 grep 双防线 | P1 | R05 规格书第 0 节固化 |
| 5 | 观察项（不改码）：PwmDuty 首周期计数 ±1 诊断口径偏差；CascadePid/SmithPredictor eFault 兜底态不刷新子块 R_TRIG（实际不可达）；滤波器核验脚本未归档（建议入库 `_Staging_Raw` 留痕） | P2 | 持续观察 |

---

*道莅工控代码库产品总监 ｜ Round 04 ｜ 2026-11-15*
