# RAW_NOTES_R4 — Round 04 狩猎检索留痕

> 日期：2026-11-15 ｜ 记录人：道莅工控代码库产品总监
> 本轮目标子库：`DL_Algo`（Level 1 首库，16 个组件）
> 合规铁律：西门子 LGF / Mod_PID 只借功能分类、参数域、命名组织，全部 clean-room 独立实现；严禁复制任何厂商源码或注释原文；OSCAT（EPL-2.0）只借算法思想与边界处理惯例，不逐行改写。

---

## 一、检索记录（7 次）

### 检索 1 ｜ LGF 官方发布页（Signal Generators / Technology / Measurement 三组定位）
- **来源**：Siemens Industry Online Support — SIMATIC S7-1500/S7-1200 Library of General Functions (LGF)
- **URL**：https://support.industry.siemens.com/cs/dk/en/view/109479728
- **许可证**：免费使用但闭源版权（应用示例许可条款），只允许借鉴分类与参数域
- **提取点**：LGF 现行版本 V5.5.0；11 个功能组官方名称与职责（Signal Generators / Technology Operations / Measurement Operations 均为独立组，本矩阵第 2 节映射成立）；V5.1.0 文档 PDF 直链（阿里云镜像）可核对块清单。
- **落到哪个组件**：RampGenerator / SCurveGenerator / PwmDutyController（SignalGen 组）；RateLimiter / FeedforwardComp / SmithPredictor（Technology 组）；LowPassFilter / SecondOrderFilter / HighPassFilter（Measurement 组）

### 检索 2 ｜ LGF 信号发生器 8 块清单与行为语义
- **来源**：PLC技术网《信号发生器全家桶｜LGF 里 8 个信号块怎么选》《博途LGF库完全指南(下)：信号发生器、统计分析篇》
- **URL**：https://bbs.plcjs.com/thread-650746-1-1.html ｜ https://bbs.plcjs.com/thread-642528-1-1.html
- **许可证**：第三方技术社区文章（引用官方手册 V5.3.0 第 4.13 节内容），仅借语义
- **提取点**：
  1. Signal Generators 组共 8 块：SinusCI / CosinusCI / RectangleCI / SawToothCI / TriangleCI / Impulse / ClockGen / Frequency；其中 Impulse 为「指定宽度与周期的脉冲串」——时间比例 PWM 的直接语义对标。
  2. `LGF_RampCI` 归属第 4.14 节工艺操作（基于插值点表的速度曲线），与本轮 RampGenerator（线性设定值斜坡）定位不同——道莅按原子化原则拆为独立线性斜坡块。
  3. `LGF_LimRateOfChangeCI / AdvancedCI`：输入跳变时输出按最大速率跟随，「保护加热元件不受热冲击」的现场语义。
  4. `LGF_Integration`（数值积分，能源计量/流量累计）、`LGF_DifferenceQuotientFB`（循环实时微分，速率监控）——积分/微分原语的行为定义。
  5. 信号发生器运行中改参数「平滑过渡、无突变」——斜坡类组件的参数热更新惯例。
- **落到哪个组件**：PwmDutyController（脉冲/占空比语义）、RampGenerator、RateLimiter、Integrator、Differentiator

### 检索 3 ｜ LGF_LimRateOfChange 参数域（Technology 组核心参数域）
- **来源**：Industrial Monitor Direct《Configuring Siemens PID_Temp Ramp Rate Control in TIA Portal》（中文版同源）
- **URL**：https://industrialmonitordirect.com/blogs/knowledgebase/configuring-siemens-pid-temp-ramp-rate-control-in-tia-portal
- **许可证**：第三方应用笔记（引用 LGF 官方行为），仅借参数域
- **提取点**：
  1. LimRateOfChange 参数域：inputValue / maxIncreaseRate / maxDecreaseRate / outputValue；速率单位为「单位/秒」而非「单位/分钟」——道莅 RateLimiter/RampGenerator 统一采用 EU/s 并在注释强制标注。
  2. 双速率独立可调（上升/下降不对称斜坡）惯例。
  3. 架构结论：斜坡应作为「给定值变化率限制」而非每拍重算的动态给定值——RateLimiter 与 RampGenerator 的工程分界依据。
- **落到哪个组件**：RateLimiter、RampGenerator

### 检索 4 ｜ Siemens PID 参数域与错误响应语义（Mod_PID_Control / PID_Compact 线）
- **来源**：西门子（中国）下载中心《PID_COMPACT 组态》+ Industrial Monitor Direct《S7-1200 PID_COMPACT Configuration》+ 西门子论坛连载 82（PIDT1 公式）
- **URL**：https://www.ad.siemens.com.cn/download/materialaggregation_5364.html ｜ https://industrialmonitordirect.com/cs/blogs/knowledgebase/s7-1200-pid-compact-configuration-complete-technical-guide ｜ https://wap.siemens.com.cn/club/bbs/post/1348511.html
- **许可证**：文档版权，只借参数域约束与行为语义
- **提取点**：
  1. 输出限幅：模拟量输出 -100.0~100.0%，PWM 输出 0.0~100.0%；手动模式给定值超限时钳位、不中断。
  2. 抗积分饱和：输出受限时「保持积分求和值不变」（条件积分法），道莅 PidController 采用同族策略 + 限幅回填。
  3. 死区宽度需手动组态（PID_Compact 无原生死区引脚，第三方做法是前置死区改 PV）——道莅直接内置 fDeadband 引脚，优于厂商实现。
  4. 采样时间必须与调用 OB 循环时间一致，PID 禁止在自由扫描 OB1 中调用——道莅以 tSampleTime 引脚显式注入 dt，杜绝隐式扫描周期积分。
  5. PWM 最短开/关时间：小于最短接通时间不输出脉冲，误差在下一采样周期累加补偿——PwmDutyController 的 tMinOn/tMinOff + 误差累加设计直接对标。
  6. 错误响应三级语义：输出 0 / 保持最后有效值 / 替代输出值——故障码表分级依据。
  7. PIDT1 公式 y=Kp[(b·w−x)+1/TI·s(w−x)+(TD·s)/(a·TD·s+1)(c·w−x)]——比例权重 b、微分延迟 a 的工程化参数域参考（道莅首版不含 b/c 权重，记入 ROADMAP 增强）。
- **落到哪个组件**：PidController（抗饱和/死区/手自动无扰/采样周期）、CascadePid（副回路限幅）、SplitRangeControl（输出域 -100~100）、PwmDutyController（最短开关时间+累加补偿）

### 检索 5 ｜ OSCAT Basic 控制器族算法思想（T1-1 ST 原生源，EPL-2.0）
- **来源**：OSCAT 官方文档（Eclipse Public License 2.0）+ DeepWiki OSCAT 控制系统章节
- **URL**：https://oscat.readthedocs.io/en/latest/ ｜ https://eclipse-oscat.github.io/oscat-basic-docs/en/pdf/oscat-basic-docs-en.pdf ｜ https://deepwiki.com/simsum/oscat/3.1-pid-controllers
- **许可证**：Eclipse Public License 2.0（可商用，需致谢；本库仅借思想，clean-room）
- **提取点**：
  1. CTRL_PID 控制律 Y = KP·(DIFF + 1/TN·∫DIFF + TV·d/dt) + OFFSET，SUP 输入为噪声死区（偏差小于 SUP 控制器不动作）——死区语义对标。
  2. 两种抗饱和策略分层：FT_PIW（到限停积分）与 FT_PIWL（限幅反算 I = LIM − P，动态回填）——道莅 PidController 同时实现两级并作为文档披露点。
  3. 梯形积分 ∫≈(x_k+x_{k−1})·Δt/2 为库内积分标准实现；FT_INT2 用双精度防长期累积误差——道莅 Integrator 采用梯形法 + LREAL 内部累加披露。
  4. 手动模式 Y = MANUAL_IN + OFFSET、RST 异步复位积分器、LIM 输出触限标志——引脚设计惯例。
  5. FT_（核心无手操）/ CTRL_（操作员级）分层命名——道莅按单一职责只做一个 PidController，手操由引脚承载，避免 OSCAT 六个 PID 变体的巨无霸化。
- **落到哪个组件**：PidController（死区/抗饱和/梯形积分）、Integrator、Differentiator、SmithPredictor（模型误差控制思想）

### 检索 6 ｜ Magnus-Tetens 露点公式系数与有效域（FC_DL_DewPointCalc）
- **来源**：Dew Point 词条（restivo.info 镜像维基百科）+ Industrial Monitor Direct《4-20mA 露点传感器配置》+ 陳國英冷凍空調《露點溫度計算完整指南》
- **URL**：http://restivo.info/wiki/Dew_Point ｜ https://industrialmonitordirect.com/zh-hans/blogs/knowledgebase/configuring-4-20ma-dew-point-sensors-for-plc-based-humidity ｜ https://www.cky.com.tw/insights/dew-point-calculation-guide
- **许可证**：公开科学知识（维基百科 CC BY-SA），公式本身为公共领域工程近似
- **提取点**：
  1. Magnus-Tetens（Stull 2011 同型）：E(T)=611.2·exp(17.625·T/(243.04+T)) [Pa]；γ=ln(RH/100)+17.625·T/(243.04+T)；Td=243.04·γ/(17.625−γ)。
  2. 有效域：0~60 °C、RH 1~100%，误差 ±0.4 °C；b=17.625/c=243.04 系数在 −40~+50 °C 最小化最大偏差。
  3. 0 °C 以下应切换冰面系数（a=21.875，b=265.5 或 a=22.587, b=265.5）——道莅首版仅做液态水露点并对 T<0 给「霜点未计算」提示码，冰面系数记入 ROADMAP。
  4. 露点 vs 霜点工程判据（冷库 −18~−40 °C 应使用霜点）——手册披露项。
- **落到哪个组件**：FC_DL_DewPointCalc（公式、系数、有效域、边界）

### 检索 7 ｜ 气体流量温压补偿公式与标准状态口径（FC_DL_FlowCompensate）
- **来源**：Sunstrand《How to Convert Gas Flow Meter Readings to Nm³/h》+ Sino-Inst《Normal vs Standard Conditions》+ 斯清泰自动化《流量单位换算》+ Mecaflux Nm³ 页
- **URL**：https://www.sfhmeter.com/?p=2414/ ｜ https://sino-inst.com?p=20545/ ｜ http://gz-sqt.com/article/32495.html ｜ https://www.mecaflux.com/en/Normaux%20metres%20cubes.htm
- **许可证**：公开工程知识，公式源自理想气体状态方程（公共领域）
- **提取点**：
  1. 普适换算 Qs = Qa × (Pa/Ps) × (Ts/Ta) × (Zs/Za)；Pa=表压+大气压（绝压），温度一律开尔文；中低压工业气体 Z≈1，道莅首版固定 Zs/Za=1 并在头注释披露适用范围。
  2. 标准状态口径表：NTP 0 °C/101.325 kPa（欧亚）、STP 20 °C/101.325 kPa（北美，与 NTP 差约 7%）、ISO 13443 15 °C——道莅以 rNormTempTs / rNormPressPs 引脚显式注入口径，默认 NTP。
  3. 算例复核：500 m³/h @ 3.5 barg / 35 °C → ≈1974 Nm³/h（绝压 4.513 bar）；0.7 MPa 表压 40 °C 10 m³/h → ≈70.2 Nm³/h——验收向量直接采用。
  4. Nm³/h 是标况体积不是工况体积；热式质量流量计无需补偿、涡街/孔板必须补偿——现场用途表述依据。
- **落到哪个组件**：FC_DL_FlowCompensate（公式、默认口径、验收向量）

### 附加检索 8 ｜（并入检索 2 的量化补充）LGF 测量评估组滤波/统计块引脚与边界
- **来源**：微信公众号《西门子博途 LGF 库详解·22 统计与平滑》《LGF_SimpleAveraging 源码级要点》（引用官方手册 109479728 · V5.3.0）+ Industrial Monitor Direct《Implementing Running Average Calculations》
- **URL**：http://mp.weixin.qq.com/s?__biz=Mzg5NTg1NTcxNw==&mid=2247485295&idx=1&sn=781352345e822332371749279c6c916e ｜ https://industrialmonitordirect.com/zh-hans/blogs/knowledgebase/implementing-running-average-calculations-in-siemens-s7-12001500-plcs
- **许可证**：第三方解读（借语义不借文本）
- **提取点**：
  1. Measurement 组平滑族清单：SimpleSmoothingFC/FB、SmoothByPolynomFC/FB（2~5 阶）、FloatingAverage（环形缓冲+填充指示+错误码 8200）、DifferenceQuotientFC/FB——阶数/窗长变体拆分的组织方式。
  2. 滤波器边界惯例：首样本输出=原值（避免报警逻辑被骗）、窗口变更延迟一拍生效、overflow 每拍重算非锁存、reset 后同样避开首拍——道莅三个滤波器的初始化无扰设计直接对标。
  3. PT1 一阶低通递推 Filtered = Factor·Raw + (1−Factor)·Filtered，Factor = 扫描时间/时间常数；状态变量必须驻留实例非临时——LowPassFilter 的系数换算公式。
  4. 差分商微分 FC 版（离线批量）与 FB 版（连续实时）的分工——道莅 Differentiator 只做 FB 实时版。
- **落到哪个组件**：LowPassFilter、SecondOrderFilter、HighPassFilter、Differentiator

---

## 二、本轮源挖掘覆盖率（矩阵第 5 节口径）

| 源 | 本轮前 | 本轮后 | 本轮产出组件 | 组累计 / 预估 | 备注 |
|---|---|---|---|---|---|
| T2-1 LGF · Signal Generators | ☐ | **◐** | RampGenerator、SCurveGenerator、PwmDutyController | 3 / 10~12 | 组首次开掘；正弦/锯齿/三角波形发生器族待挖 |
| T2-1 LGF · Technology | ☐ | **◐** | RateLimiter、FeedforwardComp、SmithPredictor | 3 / 12~15 | 组首次开掘；卷径/张力等工艺块待挖 |
| T2-5 Siemens Mod_PID_Control | ◐ | ◐ | PidController、SplitRangeControl | 4 / — | 抗饱和、手自动无扰、死区、PWM 最短开关时间四类参数域已取尽；PID 权重 b/c 记入增强 |
| T2-1 LGF · Measurement | ◐ | ◐ | LowPassFilter、SecondOrderFilter、HighPassFilter | 4 / 12~15 | 滤波阶数族已开；多项式平滑/统计族待挖 |
| T1-1 OSCAT Basic | ◐ | ◐ | DewPointCalc、FlowCompensate（另：PidController/Integrator/Differentiator 借鉴算法思想） | 2 直产 + 3 借鉴 / — | 满足「每轮至少 1 个 T1 源」配额 |

**配额自检**：本轮 16 个组件中 6 个来自 T2 非 ST 借鉴源（含两个 ☐→◐ 新开组）、5 个直接对标 T1-1 OSCAT + 3 个借用其算法思想，满足矩阵第 4 节「每轮 ≥1 个 T2 非 ST 源 + ≥1 个 T1 ST 原生源」的硬性配额。

**下轮待挖提示（供矩阵回写参考）**：LGF Signal Generators 的波形发生器族（正弦/锯齿/三角，预估 3~5 个原子块）、LGF Technology 的卷径/张力块、LGF Measurement 的多项式平滑 FB 版。
