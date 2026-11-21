# ROUND_PLAN R60（2026-11-21 · 固化批次轮）

> 规划依据：INDEX_REGISTRY v2.51.0（1073 件）实测读盘 ｜ SOURCE_HUNTING_MATRIX R56~R59 台账 ｜ DIRECTOR_EVOLUTION R276~R280 ｜ PLC_EXPERT_EVOLUTION R271~R275 ｜ ROADMAP 未勾 33 条逐条过筛。
> 本轮硬约束已执行：WebSearch 0/3 ｜ T0 新件 = 0 ｜ 撞名三查全跑（registry 精确/子串/近义三遍 + ROADMAP 本体行正则 0 命中 + 邻件扫描）。

## 一、盘点

| 项 | 实测值 | 口径 |
|---|---|---|
| 总库进度 | **1073 / 10,000（10.7%）** | INDEX_REGISTRY v2.51.0 total_components=1073，直接读盘核实 |
| 500 冲刺 | **1073 / 500，超额 +573** | 已封账，只跟踪 10,000 主线 |
| 今日产量 | **76 / 200**（R56 20 + R57 20 + R58 16 + R59 20） | 主控口径，本轮为今日第 5 轮 |
| 源矩阵覆盖 | **✔ 8（T0 八组全 ✔，余量 0）/ ◐ 26 / ☐ 11** | 主表逐行实测 ✔8 + ◐26；R59 台账口径 ◐24，**差额 2 条挂收口核对**（疑似 R51/R55 子族收口标记行未迁移，不阻断本规划） |
| T0 状态 | **8/8 ✔ 且余量 0 → 本轮 T0 = 0** | R278 已转回归维护，只接返修与机检闸维护 |
| ROADMAP 待办 | 33 条未勾 | 其中组件类本体行仅 2 条（ShlDwordEx/ShrDwordEx 疑似同义、DTL 变体挂编译债），**池已实质枯竭**（R233 预警兑现） |
| 池脏项 | 2 条（详见第五节拒单 #1/#2） | ROADMAP §1083 热电偶件、§1087 更衣序列件均已在册未勾（R231 在册反向核验发现） |

## 二、本轮配额裁决

- **R280 固化债到期**：R60 必须执行固化批次（承接 R59 机检增补 3 项：R271 三族开闭词配对 / R272 闸参数覆盖率 / R275 同拍竞态）。按 R280「固化批次期间新件配额减半」→ 基准 20 → **10**。
- **R277 族内深化补 2 件**：本轮 12 件中 7 件为矩阵台账明文记载的「仍待挖」族内缺口，2 件为族内组合件，3 件为既有族邻位原子——全部满足 R277 三类优先（变体/组合件/升版邻位），无需新开族，故按 R277 补至 **12 件，分 3 批 × 4 件**。
- **为何不补满 20**：①固化批次合并与负样本对照本身占收口预算（R280 原文）；②本轮三查候选富余度恰触 R228 的 2:1 线（24 候选收 12 拒 12），无凑满 20 的合格弹药；③Process/Algo 候选池是拒单重灾区（见第五节），硬凑必降标准。宁少勿滥，如实减配。

## 三、目标清单（12 件）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FC_DL_SearchMinMaxDint | DL_MathData | FC | DINT 数组最小/最大值 + 双索引同出（NaN 按 `x<>x` 判并排除） | t2-1-lgf-math | L | 1 |
| 2 | FC_DL_SearchMinMaxUdint | DL_MathData | FC | UDINT 数组最小/最大值 + 双索引同出（与 DINT 版无符号域同构） | t2-1-lgf-math | L | 1 |
| 3 | FB_DL_RolloverCounterUdint | DL_Base | FB | UDINT 域回绕计数器（比较+赋值回绕、圈数饱和、上限非法退化冻结） | t2-1-lgf-counter | M | 1 |
| 4 | FB_DL_ReqAckHandshake | DL_Base | FB | 通用请求-应答握手原子（应答窗超时锁存故障码 + 重试计数饱和） | self-std | M | 1 |
| 5 | FC_DL_BitFieldExtractLword | DL_Base | FC | LWORD 单字段提取（64 位域全程零移位：拆半区 + 常量掩码） | t2-1-lgf-bitlogic | M | 2 |
| 6 | FC_DL_Affine2DChain | DL_MathData | FC | N 级仿射链一次合成（MOut=Mn×…×M1，次序显式 + 奇异中间阵检测） | t2-1-lgf-math | M | 2 |
| 7 | FC_DL_ThdCalc | DL_MathData | FC | 总谐波失真率 THD = √(Σh₂..hN²)/\|h₁\|（除零/非有限双闸） | self-std | L | 2 |
| 8 | FB_DL_InputShaperZv | DL_Algo | FB | ZV 双脉冲输入整形器（按 ζ/ωn 合成脉冲序列卷积指令，抑残余振动） | self-std（公开控制理论） | M | 2 |
| 9 | FC_DL_InterpolateTable3D | DL_MathData | FC | 3D 表三线性插值（轴向量钳位 + 单调性校验码 + 输入有限闸） | t2-1-lgf-math | H | 3 |
| 10 | FB_DL_ValveTerminalDiag | DL_Device | FB | 阀岛级 N 站位命令-反馈一致性诊断 + NE107 最差者胜岛级聚合 | t2-6-rockwell-aoi + t2-2-lbp | M | 3 |
| 11 | FB_DL_AxisCmdArbiter | DL_Motion | FB | 轴驱动命令源优先级仲裁（安全 > 手动 > 自动 > 上位，每拍全量重判） | t1-6-plcopen | M | 3 |
| 12 | FB_DL_ShiftHandoverCheck | DL_Process | FB | 班次交接检查（运行快照 + 未决事项确认窗 + 超窗升级码） | self-std | M | 3 |

> 分类核账：MathData 5 / Base 3 / Algo 1 / Device 1 / Motion 1 / Process 1 = 12，六库全覆盖 ✔；占比最高库 Process = 1 ≤ 3 ✔（R245 配额令）；单库最大 MathData 5 ≤ 6 ✔。新开族 = 0（全部矩阵既有 ◐ 行族内深化），无「新族理由」条款需求。

## 四、分批派单要点

### 批次 1（变体与纯函数，L~M）
1. **FC_DL_SearchMinMaxDint**（L）：接口 `aValues : ARRAY[*] OF DINT, nCount, bIgnoreInvalid` → `fMin/fMax + uMinIdx/uMaxIdx + bValid`。边界：nCount=0/越界钳位、全量无效不返回 0 号位（沿用 SearchMinMax LREAL 属主纪律）；NaN 判据用 `x <> x`（R79）。易错：FC 局部计数/标志段 1 显式预置（R254），回钳量禁再判越界（R241）。分工声明：与 `FC_DL_SearchMinMax`（LREAL 属主）互引，本件为 DINT 域重载（矩阵 Math 行明文待挖项）。
2. **FC_DL_SearchMinMaxUdint**（L）：同 1 的无符号域同构件，注意无符号下溢比较只允许 `<=/>=` 全序判式；与 1 号件共用规格向量表、码位段同带连号；头注释与 1 号件互引（R216 三条同批满足）。
3. **FB_DL_RolloverCounterUdint**（M）：`bCount/bLoad/nPreset/uUpper + bRoll` 出口；回绕一律「比较+赋值」禁 MOD（负数取余三平台歧义，沿 RolloverCounter 属主纪律）；上限非法 → 退化冻结 + 独立码位，不静默。易错：UDINT 自增回绕是 0→Max 反向事故源，回绕判据须在自增**前**判 `= uUpper`（整数进位点自证：uUpper 恰被整除与 uUpper+1 两向量）；枚举初值 `:=`（R263）。分工：与 `FB_DL_RolloverCounter`（INT 属主）、`FB_DL_ModuloCounter`（取模索引）三角互引。
4. **FB_DL_ReqAckHandshake**（M）：`bReq → bAck` 握手：请求沿武装 → 应答窗 tAck → 超时锁存故障码 → 重试计数饱和 + bRetry 单拍脉冲。边界：tAck 与 tRetry 两窗配比约束句进头注释并在段 3 组态闸落锁存（R239/R100）；单拍输出统一出口预置 FALSE、分支只写 TRUE（R256）；首拍零假沿自证（R257）。分工：与 `FB_DL_AgvDockingHandshake`（工艺级对接）声明「本件为无工艺语义的时序原子」。

### 批次 2（族内深化，M 为主）
5. **FC_DL_BitFieldExtractLword**（M）：`uSrc : LWORD, uStart, uWidth` → `uField : LWORD + bTrunc/bErr`。铁律：**全程零 64 位移位**——拆高低半区（高 32 位走 `LWORD_TO_DWORD` 右半 + `DWORD_TO_LWORD` 升位），`nWidth=64` 走常量掩码，移位量 `MOD 32`；非 32 对齐下「宽 64 跨两字」物理不可达 → 主动收窄并写偏离段（R12 E-1 先例）。易错：TRUNC 禁令不适用（纯位域无浮点），但禁裸赋值窄化（R262）。分工：与 `FC_DL_BitFieldExtract`（32 位属主）互引。
6. **FC_DL_Affine2DChain**（M）：`aMats : ARRAY[*] OF ST_DL_Affine2D（若属主结构体存在则引用不重声明，R264）` → `MOut`；合成次序固定 MOut=Mn×…×M1 并在头注释写死列向量约定；中间任一奇异（相对判据，沿 Matrix3Inverse 的 fDetEps×maxAbs³ 口径）→ 传播标记不泄半结果。易错：链长 0/1 退化分支显式处理；非有限输入与结果溢出双闸。分工：与 `FC_DL_Affine2DCompose`（两级属主）声明「N 级链 vs 两级」互补（矩阵 Math 行明文「多级链合成仍待挖」）。
7. **FC_DL_ThdCalc**（L）：`aHarm : ARRAY[*] OF LREAL, nHarm` → `fThd : LREAL + bValid + eErr`。判据：`|h1| < 1E-9` 或非有限 → 置码三件套不除零（R258 口径）；幅值负值取绝对值（幅值域约定写头注释）；nHarm 钳位 `[2, nCount]`。分工：与 `FC_DL_HarmonicSpectrumBin`（频点分箱属主）、`FC_DL_FftRadix2`（变换属主）声明「聚合层」定位。
8. **FB_DL_InputShaperZv**（M）：注入 `fWn [rad/s]、fZeta [-]` → 双脉冲幅值 `1/(1+A)、A/(1+A)`，A=exp(−ζπ/√(1−ζ²))，时间间隔 Δt=π/(ωn√(1−ζ²))；ζ 域闸 `[0, 0.95)` 钳位 + **全部 LREAL 入参枚举进 `_bFin` 有限闸，逐个点名（R272 是本轮最高危模板缺陷）**；`bConv`（卷积就绪）输出。易错：Δt 换算走秒口径单一化（R342：`TIME_TO_LREAL/1000.0`，禁跨日历类型链）；出口延迟半个 Δt 的采样约定写头注释。分工：与 `FB_DL_NotchFilter`（反馈侧频域抑制）声明「前馈指令整形 vs 在线滤波」边界。

### 批次 3（高复杂度状态/组合件）
9. **FC_DL_InterpolateTable3D**（H）：`aX/aY/aZ 轴向量 + aTable 三维数组 + fX/fY/fZ` → 三线性插值。边界：轴向量升序校验（乱序置码不插值）、索引钳位到 `[0, n-2]`（整数进位点自证：fX 恰落在末节点与越界一格两向量）、输入与结果非有限双闸（R272 全枚举 + R273 出口防污染）；只读轴数组不改调用方数据（PercentileLReal 纪律）。分工：与 `FC_DL_InterpolateTable2D`（2D 属主）、`FB_DL_LineInterp2Axis` 声明维度族谱。
10. **FB_DL_ValveTerminalDiag**（M）：N 站位（`nStations` 钳位）每拍比对命令字 vs 反馈字 → 每位独立不一致锁存 + 岛级聚合最差者胜。铁律：NE107 契约枚举引用既有属主、数值最小最差口径唯一真源（R226），禁另造一套；头注释写「归属 Ownership：引用 <属主文件>，本件只引用不重声明」（R264）；**每拍全量重判、无相位机**须显式声明（R227）——与 HealthStatusArbiter 同范式。分工：与 `FB_DL_ControlValveDiag`（单阀机理诊断）声明「岛级一致性 vs 单阀特性」。
11. **FB_DL_AxisCmdArbiter**（M）：命令源 `eSafe/eJog/eAuto/eHost` 四级 → `eWinner + stWinnerCmd`。铁律：迁入「放行」语义不涉相迁移（纯组合件，R227 声明每拍全量重判防陈旧）；单拍切换输出走统一出口预置 FALSE（R256）；不自造轴状态枚举（PLCopen 纪律，R11）；输出命令字必须携带源标签防「赢了仲裁丢了身份」。分工：与 `FB_DL_ModeArbiter`（模式级）声明「轴驱动源 vs 单元模式」两层。
12. **FB_DL_ShiftHandoverCheck**（M）：交班窗 tHandover 内快照运行数据（产量/报警计数）→ 未决事项清单逐条确认 → 全确认置 bHandoverDone。边界：进入/退出条件逐条取反对偶（R259，窗末退出与失能并列）；tStart=tEnd 零长窗判 eCfgBad 显式分支（R253）；快照「最近一次」类出口纳入复位清单（R243）；**窗口超时迁移判据让位于本拍确认沿——先消化输入再消化超时（R275 同拍竞态是本轮必查模板）**。分工：与 `FB_DL_ShiftMonthReport`（报表属主）、`FB_DL_ChangeoverSequence`（产品换型）双向声明。

### 批次共性（三批通用）
- 码位：各件故障码沿本子库既有码段**连续号段**分配，与子库既有段不连续时头注释写分段理由（R192）；落盘前由编码侧重跑精确名三查（本文件为规划期三查）。
- 交付资格：R271 三族开闭词配对自证 + R265 命名-类型一致性 + 禁止词扫查（R244）逐件过闸；闸参数覆盖清单逐件对照 R272 定向扫查点自查。

## 五、撞名三查留痕

**候选 24 / 收录 12 / 拒单 12**（富余度恰 2:1，未破 R228 阈值但触线；按 R267/R276 记按族分布）。

| # | 拒单 | 族 | 一句理由 |
|---|---|---|---|
| 1 | 热电偶线性化件（ROADMAP §1083 池项） | 转换/线性化族 | **池脏项**：registry 已有 `FC_DL_ThermocoupleLinearization`，R231 在册反向核验拒收，请收口按本体行补勾注记 |
| 2 | 更衣序列件（ROADMAP §1087 池项） | 联锁顺控族 | **池脏项**：registry 已有 `FB_DL_GowningRoomSeq`，同上拒收 |
| 3 | `FC_DL_ShlDwordEx`/`FC_DL_ShrDwordEx`（§948） | 位串族 | R232 改判：存量 ShlEx/ShrEx 已覆盖 DWORD 域，自标「疑似同义」成立，不立项 |
| 4 | `StringToDTL`（矩阵 Converter 行） | 转换族 | 挂 DTL 编译债未清，禁派（既有挂账） |
| 5 | CRC-16 反射 / LWORD 累加和 | 校验族 | R267 族连续两轮拒单 ≥2 标「挖潜低」，本轮主动避让 |
| 6 | `FB_DL_MimoDecouple2x2` | Algo 解耦族 | registry 已有 `FB_DL_Decouple2x2`，同义精确命中 |
| 7 | `FB_DL_SterilizeF0Seq` | Process 灭菌族 | registry 已有 `FB_DL_AutoclaveSterilSeq`，本体近似命中 |
| 8 | `FB_DL_PulseDivider` | Base 脉冲族 | registry 已有 `FB_DL_EdgeDivider`，同义邻件命中（R214 三查救回一次） |
| 9 | `FB_DL_AxisThermalGrowthComp` | Motion 热补偿族 | registry 已有 `FB_DL_AxisThermalComp`，同义近邻命中 |
| 10 | `FB_DL_AxisFeedOverride` | Motion 倍率族 | registry 已有 `FB_DL_OverrideSelector`，近邻风险保守拒（分工面不足以自证互补） |
| 11 | `FB_DL_NotchFilter` / `FB_DL_CascadePid` | Algo 滤波/PID 族 | 拟题时 registry 精确命中在册（规划初稿自纠），撤销候选 |
| 12 | `FB_DL_DowntimeParetoTally` | Process 统计族 | `FB_DL_DowntimeClassifier` 近邻，差异化不足，拒 |

按族分布：Base 脉冲族 1 ｜ Motion 2 ｜ Algo 解耦/滤波/PID 3 ｜ Process 2 ｜ 位串 1 ｜ 转换/校验避让 2 ｜ 池脏项 1（§1083）。**Algo 与 Process 是拒单重灾区**——候选富余度 2:1 恰触线，符合 R277 概念饱和判断，支撑本轮减配不补满。

## 六、风险与下轮建议

1. **R228 触线**：候选富余度恰 2:1，Process/Algo 候选池实质枯竭——建议下轮规划同步产出「工艺口述补池清单」（R233 条款兑现），优先 R57 后新增设备族的邻位原子与既有件参数域变体，而非继续开题海。
2. **三向一致差额**：本轮发现 2 条池脏项（#1/#2）+ 源矩阵 ✔/◐ 计数差 2 条（主表 26 vs 台账 24），合计 4 条记账项，建议主控收口时一次性回写（R217 阈值内挂账即可）。
3. **R272 是本轮头号终审靶**：12 件中 6 件含 LREAL 参数闸（ThdCalc/InterpolateTable3D/InputShaperZv/Affine2DChain 等），固化批次新增的「闸参数覆盖率」机检规则请对这 6 件全量跑，不抽检。
4. **承接提醒**：`FB_DL_TwoStepConfirm` 同拍竞态 v1.0.1 返修在编码侧清单（R275/P0），不在本 12 件内；两线并行时返修件触发 R249 降件令的口径由主控裁决。
5. **码位游标**：派号后请收口回写两库 VERSION 码位游标（信息级/故障级），防 R18 式交叉撞车复发。
