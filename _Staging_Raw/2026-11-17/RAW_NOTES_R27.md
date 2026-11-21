# RAW_NOTES_R27（来源台账，≤100 行）

## 1 检索声明
- 本轮 WebSearch：**0 次**。依据：全部目标取自 ROADMAP.md 既有未勾条目（L242/L249/L261/L270/L274/L275/L277/L279/L281/L282/L296/L298/L302/L563/L645/L660/L672/L712/L845 + §24.1）与 SOURCE_HUNTING_MATRIX 既有条目语义；公式类（孔板流量、理想气体密度、卷径递推）按公开标准语义（ISO 5167 孔板公式框架、理想气体定律）直接实现，属公有领域物理公式，不检索。
- 本轮零代码行复制：所有组件 100% clean-room 自写，无任何上游函数体/符号名复制。

## 2 逐件来源台账
| 组件 | 来源标签 | 来源名 / 条款 | 许可证 | 仅借鉴点 |
|---|---|---|---|---|
| FC_DL_OrificeFlowCalc | roadmap-L845 / 公开标准 | ISO 5167 孔板流量公式框架（公开物理公式语义） | 无代码依赖（公式为公有领域） | 参数域组织（ΔP/P/T 三输入+K 系数）；公式本体自有实现 |
| FC_DL_WaferCountYield | roadmap-L712 / 自研 | SEMI 良率口径常识（公开定义） | — | 良率分档区间组织；判定逻辑自有 |
| FC_DL_GasFlowSqrt | roadmap-L645 / T0 | 平台内建数学语义（委托本库 FC_DL_NthRoot / FC_DL_FlowCompensate） | 本库自有（MIT 道莅） | 仅委托组合；无外部语义 |
| FC_DL_AirDensityFanPower | roadmap-L660 / T0 | 风机定律 ρ 比例修正（公开工程公式） | 公有领域 | P∝ρ/ρ0 行为定义；常量 ρ0=1.225 kg/m3 标注单位 |
| FB_DL_LoopWaveInject | roadmap-L672 / T0 | 自研（委托 FB_DL_RateLimiter） | 本库自有 | 无外部语义 |
| FB_DL_FanArrayStageCtrl | roadmap-L302 / T1-5 | TcOpen 组件范式（一级/二级设备抽象分层思想） | Apache-2.0 | 仅借鉴「设备抽象引脚组织」范式；N+1 轮值逻辑自有 |
| FB_DL_FrostProtectFreeze | roadmap-L298 / T1-2 | OSCAT Building 滞环纪律（域外行为显式化） | LGPL（仅借鉴行为，零复制） | 回差判据组织 + TRIP 安全侧保持纪律 |
| FB_DL_MfcFlowCtrl | roadmap-L249 / 自研 | 半导体 MFC 通用校验语义（公开工程惯例） | — | 斜率/超调/稳定三判据参数域；实现自有 |
| FB_DL_DateCoderSync | roadmap-L281 / T1-5 | TcOpen 扫码/打印外设范式（引脚组织） | Apache-2.0 | 仅引脚组织范式；分频/偏移逻辑自有 |
| FB_DL_SealIntegrityMonitor | roadmap-L277 / T2-8 | ISA-88 参数窗语义（clean-room） | 标准文本语义，无代码 | 三参数配方窗判定组织；码位/状态机 100% 自有 |
| FB_DL_UnwinderDiameterCalc | roadmap-L279 / 公开公式 | 卷径递推 d²=d0²−4tL/π（公开几何公式） | 公有领域 | 公式语义；实现与冻结语义自有 |
| FB_DL_StringCutAlign | roadmap-L242 / T1-6 | PLCopen 对位微调语义（InPosition 确认纪律） | 标准语义，无代码 | 在位确认+超时中止纪律（R22 已沉淀）；实现自有 |
| FB_DL_StepperZLiftMicron | roadmap-L563 / T1-8 | GitHub topics 步进当量组态常识 | 多为 MIT，未复制任何代码 | 当量组态参数域；实现自有 |
| FB_DL_FillWeightCtrl | roadmap-L274 / 自研 | 落差提前量学习为包装行业公开工程惯例 | — | 指数学习行为自有；λ=0.3 常量带注释 |
| FB_DL_VffsBagLength | roadmap-L275 / T2-7 | PackML 相语义（色标同步相命名组织，clean-room） | 标准语义，无代码 | 相命名组织；同步逻辑自有 |
| FB_DL_CartonErectSeq | roadmap-L270 / 自研 | 开箱四相为公开工程常识 | — | 全自有 |
| FB_DL_LoadPortSeq | roadmap-L261 / T2-8 | SEMI E84/E87 握手语义（公开标准行为定义，clean-room） | 标准语义，无代码 | 对接/握手/映射比对相组织；实现与码位 100% 自有 |
| FB_DL_PumpChangeoverSeq | roadmap-L296 / T1-2 | OSCAT 轮值纪律（同 R17 DutyStandbyRotation 线） | LGPL（零复制） | 轮值选台纪律复用本库自有沉淀 |
| FB_DL_MachineGuardAudit | roadmap-L282 / T2-7 | PackML Holding/Held 状态语义（OMAC 公开状态定义，clean-room） | 标准语义，无代码 | 仅 Holding/Held 两态语义组织；审计/锁定实现自有；17 态属主仍为 FB_DL_PackMlStateMachine |
| FB_DL_SplicerAutoJoint v1.1.0 | ROADMAP §24.1 P0 欠账 | 本库自有 v1.0.x 修订 | 本库自有 | 验收向量沿用 §24.1 定义 |

## 3 合规结论
- 全部 20 件可商用：来源为 roadmap 既有条目、公开物理/行业标准语义（clean-room 借鉴）或本库自有组件修订；无 GPL/AGPL 接触，无加密狗绑定代码。
- clean-room 声明：T2-7/T2-8/SEMI/ISA/PLCopen 相关件仅借「状态命名与参数域组织」，未复制任何代码行、函数名、常量名；本轮无新增外部仓库抓取，`_Staging_Raw` 不新增源码备份。
