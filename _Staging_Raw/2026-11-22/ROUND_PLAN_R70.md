# ROUND_PLAN_R70 — 构建轮规划（阶段一：盘点与锁定目标 / 阶段二：按源矩阵选题留痕）

> 轮次：R70 构建轮｜启动：2026-11-22 17:22 (+08:00)｜模式：无人值守批处理轮（主控直跑 R335）
> 阶段职责：盘点 + 锁定 10 目标 + 撞名三查 + 选题留痕。**不写代码、不改 registry / JSONL / .st / 五件套文档**。
> 检索预算：**WebSearch = 0 次**（零检索轮），仅复用 `SOURCE_HUNTING_MATRIX.md` 与既有 `RAW_NOTES_*`。
> 配额：**新件 10 件**（R69 超时判据 R362：基线 13 −20% → 10）。不足如实少报，禁凑数变体。
> 待办纪律：ROADMAP 未勾待办 **55 条 > 30** → **本轮不补写新待办**（禁扩表）。

---

## 0. 统计口径（开工基线，实测）

| 指标 | 值 | 口径说明 |
|---|---|---|
| 总库 | **1,189 / 10,000（11.89%）** | `INDEX_REGISTRY.json` v2.61.0，`total_components`=1189；counts: Base 150 / MathData 283 / Algo 135 / Device 215 / Motion 123 / Process 283，sum=1189 断言通过 |
| 今日 11-22 已入库 | **54 件** | `registered_at` 前 10 位 = `2026-11-22` 精确统计（非估算）；按日分布 11-14 26 / 11-15 160 / 11-16 198 / 11-17 135 / 11-18 151 / 11-19 175 / 11-20 152 / 11-21 138 / 11-22 54 |
| 距 500 里程碑 | **已超额 +689** | 1189 − 500 = +689（里程碑达成率 237.8%） |
| 距 1,200 门槛 | **差 11** | 本轮若 10 件全注册 → 差 1；点修升版不增计数 |
| 源矩阵整组覆盖 | **37 组全开：◐ 26 / ✔ 11 / 整组未开 ☐ 0** | 台账 §5 组级状态行实测（T0-1~T0-8 八组 ✔；T1-1~T1-8 ◐ 除 T1-3 ✔；T2-1 十一子组 ◐ 除 Converter ✔；T2-2/T2-4/T2-5/T2-6/T2-7/T2-8、NE43、ESC 自研线均 ◐） |
| 子行 ☐ 标记 | **36 处** | 均为「子族/待挖方向」标记，非整组未开；本轮不得触碰已 ✔ 组 |

---

## 1. 值守项裁决：真实 IEC 编译器接入是否应作本轮首任务

**裁决：不作为首任务、不阻塞编码；作为并行值守探针，两轮试点后再定是否升 P0 首位。**

风险意见（供主控并行探测时参考）：

1. **方言覆盖风险（高）**：MatIEC 不支持本库大量使用的 OOP 构件——`INTERFACE` / `PROPERTY` / `METHOD` / `EXTENDS` / 命名空间隔离。全库 1,189 件中 Device/Motion/Process 三库的接口契约件（`I_DL_*`）与 NE107 契约族必然大面积报语法错，直接当闸门会产出**海量假阳性**，最终被迫整库豁免 → 闸门形同虚设。
2. **闸门可信度风险（中高）**：正确姿势是先做「方言子集白名单」——只对 `FC_DL_` 纯函数（无状态、无 OOP）与 `FB_DL_` 的扁平 ST 子集做**实编译**，其余仍走 `dl_gate.py` 结构性伪编译。若跳过白名单直接全量，第二轮就会被假阳性淹没并回退成"抽样免责"。
3. **环境可复现风险（中）**：CI 侧接入需锁版本 vendor（MatIEC 为 Python 包，随 Python 版本漂移），并须固化 `pip` 源与快照；否则「本地过、CI 挂」会变成新的挂账类别。
4. **收益时点**：编译器接入的首个可交付价值不是「拦住新件」，而是**存量类型假设证伪**（`DT_TO_DINT` / `TOD_TO_TIME` / `LREAL_TO_TIME` 三条内建链，全库两位数件依赖，已连挂 6 轮）。这类证伪只需 20 件抽样，**不需要全量闸**。
5. **结论**：本轮编码按「伪编译（结构性语法级，无类型推导）」如实标注，**不得宣称实编译**；实编译债继续挂 ROADMAP，主控并行探测结果若能在本轮内跑通「5 件纯 FC 实编译基线」，视为加分项，**不得据此改动已定 10 件清单**。

---

## 2. R70 目标总表（10 件，撞名三查已完成，见 §2.3）

> 批次切分：批 1 = 4 件（低/中低，无外部依赖，可并行起手）｜批 2 = 3 件（中低，需批 1 的时序/记录骨架先落地）｜批 3 = 3 件（中，收尾，含跨件引用）。
> 六库分布：DL_Base 2 / DL_Device 5 / DL_Process 3（MathData / Algo / Motion 本轮 **0 件**，见 §4 判据 ③）。

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| N1 | `FB_DL_EncoderBatteryWatch` | DL_Device | FB_DL_ | 绝对值编码器电池电压/寿命监视：低电压分级告警 + 掉电事件计数 + 更换窗满强制请求回零 | self-std（设备本体健康族三批） | 低 | 1 |
| N2 | `FB_DL_AlarmSuppressByDesign` | DL_Base | FB_DL_ | ISA-18.2 设计抑制：工况窗内已知报警按抑制清单屏蔽、越窗自动恢复、抑制计数留痕 | isa-18.2（T2-8 报警管理族本体） | 中低 | 1 |
| N3 | `FB_DL_ChainElongationWatch` | DL_Device | FB_DL_ | 输送链/传动链伸长监视：编码器计数与理论节距比偏差趋势 + 跳齿风险分级 | self-std（设备本体健康族三批） | 低 | 1 |
| N4 | `FB_DL_NozzleClogDiag` | DL_Device | FB_DL_ | 喷涂/点胶喷嘴堵塞诊断：同指令下「压力偏高 ∧ 流量偏低」双判据 + 清洗提醒分级 | self-std（设备本体健康族三批） | 中低 | 1 |
| N5 | `FB_DL_GripperHealthAoi` | DL_Device | FB_DL_ | 夹爪 AOI 三分类诊断：夹持未到位/工件滑移/传感器失效，三类各带独立确认窗 + NE107 出口 | rockwell-aoi（T2-6 设备级粒度族：阀/电机/夹爪之**夹爪**，矩阵明列待挖） | 中 | 2 |
| N6 | `FB_DL_AdhesiveMassVerify` | DL_Process | FB_DL_ | 点胶胶量校核：流量积分质量与目标胶点质量偏差、连续欠胶趋势拦截 | self-std（包装/3C 组装工艺族） | 中低 | 2 |
| N7 | `FB_DL_SequentialEventLog` | DL_Base | FB_DL_ | 多通道事件顺序记录（SOE）：8 路带时间戳首变排序 + 队满丢旧 + 快照读出口 | self-std（诊断基础设施族） | 中 | 2 |
| N8 | `FB_DL_CoolantConcentrationCtl` | DL_Process | FB_DL_ | 机加工冷却液浓度闭环：折光仪读数折算 + 补液/补水配比 + 浓度越窗联锁与换液提醒 | self-std（金属加工公用工程族） | 中 | 3 |
| N9 | `FB_DL_AirConsumptionBaseline` | DL_Process | FB_DL_ | 压缩空气在线耗量基线：班次耗量基线漂移判定 + 泄漏早期预警（与停机压降法件分工） | self-std（能源/公用工程族） | 中低 | 3 |
| N10 | `FB_DL_VacuumBuildTimeTrend` | DL_Device | FB_DL_ | 吸盘工位真空建立时间趋势：建立时长基线漂移 + 吸盘老化/管路微漏分级预警 | self-std（设备本体健康族三批） | 中低 | 3 |

### 2.1 工程意义（谁在什么工况用、防什么错）

| # | 使用者 / 工况 | 防的错 |
|---|---|---|
| N1 | 伺服调试/维保工程师，多圈绝对值编码器长期运行现场 | 电池耗尽导致多圈值丢失后**未被发现**即恢复生产 → 位置基准错乱撞机；同时防「换了电池没回零」 |
| N2 | 产线调试工程师，启停/换型/清洗段必然出现的已知报警 | 设计性报警在每次启停刷屏 → 淹没真故障（报警泛滥）；人工搁置又会忘记恢复 → 用「工况窗 + 抑制清单」替代人工判断 |
| N3 | 输送/窑炉/烘箱传动维保，链条长期磨损现场 | 链条伸长到极限跳齿 → 突然停机与工件堆积；趋势件让停机变成计划性换链 |
| N4 | 涂装/点胶线工艺工程师 | 喷嘴局部堵塞导致膜厚不均/胶线断点，靠目视抽检发现太晚；用「压力升 ∧ 流量降」双判据在批次内早发现 |
| N5 | 机器人上下料工站，夹爪带磁性开关/力传感 | 只做力窗校验（存量 `FB_DL_GripperForceVerify`）不够：夹持到位但工件滑移、传感器失效同样会掉件；三分类让维修知道该换夹爪还是换开关 |
| N6 | 包装糊盒/3C 点胶工艺 | 胶量少 5% 短期不显形、长期开胶客诉；用流量积分与目标胶量比对把「欠胶」提前到批次内拦截 |
| N7 | 电气/自动化故障诊断工程师，偶发停机复盘 | 只有 First-Out 单因锁存（存量 `FB_DL_FirstOutLatch`）时，多路同拍跳变无法还原时序 → SOE 提供 8 路带时间戳排序 |
| N8 | 机加工车间设备管理，冷却液浓度靠人工折光计抽检 | 浓度过低滋生细菌/锈蚀、过高伤皮肤与刀具；补液失控时自动联锁并出换液提醒 |
| N9 | 厂务能源管理，压缩空气占全厂电耗 10~20% | 管路微漏缓慢恶化无人察觉；在线耗量基线漂移预警把「停机压降法测试」的空档期补上 |
| N10 | 包装/装配吸盘搬运工位 | 吸盘老化与管路微漏表现为「真空建立时间变长」，但真空度仍达标 → 掉件突发；趋势件在达标期就预警 |

### 2.2 批次依赖与执行序

- **批 1**：N1 → N3 → N4 → N2（三个纯监视件无前置；N2 状态机独立）。四件均不引外部接口，可四路并行。
- **批 2**：N7（SOE 骨架，无前置）→ N6（引用 `FB_DL_Integrator` 低层能力需确认存量接口）→ N5（引用 `E_DL_Ne107Status` 唯一属主，**只引用不重复声明**）。
- **批 3**：N9 → N10 → N8（N10 与 N4 同族，建议复用 N4 的判据骨架；N8 含配比计算，放最后防中途超时砍件时影响低层）。
- 中途超时砍件顺序：**N8 → N6 → N10**（如实少报，禁注水）。

### 2.3 撞名三查（R327 / R214，registry 实时精确匹配，脚本读取全名清单，非凭记忆）

**查法**：① 精确同名——registry 1,189 条 `name` 全集 `in` 判定，10 候选全部 `False`；② 同义邻件——按语义族关键词（`encoder`/`battery`/`alarm`/`suppress`/`shelv`/`chain`/`nozzle`/`clog`/`gripper`/`health`/`aoi`/`adhesive`/`glue`/`mass`/`coolant`/`air`/`consum`/`vacuum`/`record`/`soe`）回扫命中清单逐条裁定；③ 文件树查——`DL_*/` 目录名匹配 10 候选，全部 `none`。

**拒单留痕（14 条，其中精确同名 5 条）**：

| # | 候选名 / 拟案 | 拒因 | 命中存量名 |
|---|---|---|---|
| 1 | `FB_DL_HeaterBreakDetect`（加热器断丝诊断） | 精确同名 | `FB_DL_HeaterBreakDetect`（DL_Device） |
| 2 | `FB_DL_PumpDryRunGuard`（泵干转保护） | 精确同名 | `FB_DL_PumpDryRunGuard` / `FB_DL_PumpDryRunProtect` 双属主 |
| 3 | `FB_DL_ValveSeatLeakWatch`（阀座泄漏） | 精确同名 | `FB_DL_ValveSeatLeakWatch` |
| 4 | `FB_DL_ToolLifeBudget`（刀具寿命） | 精确同名 + 语义等同 | `FB_DL_ToolLifeBudget` |
| 5 | `FB_DL_FrequencyGenerator`（频率发生） | 精确同名（R69 已拒过一次，二次确认） | `FB_DL_FrequencyGenerator` |
| 6 | `FB_DL_TrackerBacktrack*`（逆跟踪角） | 同义邻件：`FC_DL_` 与 `FB_DL_` **双前缀同词干同名**（2026-11-17 / 11-18 各注册一件），再立即为四件同义 | `FC_DL_TrackerBacktrackCalc` / `FB_DL_TrackerBacktrackCalc` |
| 7 | `FB_DL_HydOilConditionWatch`（液压油温/污染度） | 同义邻件：职责已被液压站件覆盖，再立需先出边界表 | `FB_DL_HydraulicPowerUnit` / `FB_DL_HydraulicAccumPreChg` |
| 8 | `FB_DL_WeldTipDressCounter`（点焊电极修磨计数） | 变体拒：与 `ToolLifeBudget` 同骨架，无可独立验收的判据差 | `FB_DL_ToolLifeBudget` / `FB_DL_BusbarWeldMonitor` |
| 9 | `FB_DL_ChwDifferentialPressureReset`（冷冻水差压重置） | 同义邻件已并案（R30 注记：引脚已纳入） | `FB_DL_ChwDifferentialPressure` |
| 10 | `FC_DL_IntToUdintSat` / INT 域饱和 | 语义已并入重载（R62 注记），禁新增文件 | `FC_DL_SignedToUdintSat` |
| 11 | `FC_DL_StringToDTL`（T2-1 Converter 待挖） | 编译债未清（DTL 内建链），本轮不碰转换类 | 无（存量缺位，挂 ROADMAP 既有 DTL 条目） |
| 12 | LWORD 位段单字版 / 多段一次搬（T2-1 Bit Logic 待挖） | 变体拒：与 `FC_DL_BitFieldExtract` / `WordBitPack` 无域宽差以外的判据差 | `FC_DL_BitFieldExtract` / `FC_DL_WordBitPack` |
| 13 | `FB_DL_RecipeSwitchoverSeq`（配方切换编排） | 同义邻件：切换交接语义已有属主；ISA-88 三层编排「明确不立」 | `FB_DL_RecipeSwitchHandover` / `FB_DL_RecipeManager` |
| 14 | `FB_DL_SuctionCupWear`（吸盘磨损直接判据） | 同义邻件风险 → 改立 N10「真空建立时间趋势」（可测量、可验收），原名弃用 | `FB_DL_VacCupRingCtrl` / `FB_DL_VacuumEjector` |

**分工声明（本轮 10 件必须写进头注释，防下轮再撞）**：
- N5 ↔ `FB_DL_GripperForceVerify`（力窗校验）/ `FB_DL_RobotGripVerify`（抓取确认）：本件只做**多类诊断仲裁**，不做力窗与抓取放行判定。
- N7 ↔ `FB_DL_FirstOutLatch`（单因首出锁存）/ `FB_DL_StepTimeRecorder`（步耗时）：本件只做**多路时序记录**，不取代二者。
- N2 ↔ `FB_DL_AlarmShelving` / `FB_DL_AlarmShelveMgmt`（人工搁置）/ `FB_DL_AlarmFloodLimiter`（泛滥限流）：本件只做**设计性抑制**（按工况窗自动恢复，无人工申请语义）。
- N9 ↔ `FB_DL_AirLeakDecayTest`（停机压降法测漏）：本件只做**在线耗量基线**，不做压降法判定。
- N4 ↔ `FB_DL_SlurrySieveClogWatch`（筛网堵塞，浆料侧）：本件为**喷嘴出口侧**双判据，判据量与工况完全不同。
- N8 ↔ `FB_DL_CoolantLoopBal`（回路水力平衡）/ `FB_DL_CoolantFlowAudit`（流量审计）：本件只做**浓度与补液**。
- N1 ↔ `FB_DL_AxisEncoderPulseLostScore`（脉冲丢失评分）/ `FB_DL_AxisLoadEncoderLossMonitor`：本件只做**电池与多圈基准**。

---

## 3. 源覆盖与「行业池已 100% 收口」实测结论

**行业池实测（重要发现）**：`ROADMAP.md` §19（31 条）、§21（30 条）、§13.x/§15.x/§16.x 各行业池行 **全部为已勾选**；本轮对三处「勾选符号损坏」行（`- [x ` 缺右括号：`FB_DL_RoomCo2DemandVent` / `FB_DL_CleaningBrushWear` / `FB_DL_TankLevelStrapping`）逐一回查 registry，**三件均已注册**（DL_Process / DL_Device / DL_Process）→ **行业池「已勾未注册」漂移差额 = 0**，与 R68 §19.6 清零结论一致。

因此「至少 3 件覆盖 ROADMAP 行业池」按**行业工艺语义**落实为 N6（包装/3C 点胶）、N8（金属加工冷却液）、N9（厂务压缩空气）三件，三者均为**行业池未覆盖的真实工况缺口**（池内无对应行，故不构成池项重复），并在 `RAW_NOTES_R70.md` 逐件记源。**须由主控在收口时知悉：这三件不是池项补勾，不得回写为 ROADMAP 池行勾选。**

**配额结构核对**：

| 要求 | 本轮落实 | 达成 |
|---|---|---|
| 新件 10 件 | 10 件（Base 2 / Device 5 / Process 3） | ✅ |
| ≥3 件覆盖行业工艺 | N6 / N8 / N9 | ✅（行业池语义，非池项） |
| ≥2 件 T2 闭源族分类借鉴 | N2（ISA-18.2 抑制语义）/ N5（AOI 三分类） | ✅ |
| 其余为 self-std / T0 | self-std 8 件（N1/N3/N4/N6/N7/N8/N9/N10），含 N2/N5 的 clean-room 声明 | ✅ |
| 零检索 | WebSearch 0 | ✅ |
| 不凑数变体 | 14 条拒单含 4 条变体/同义拒（#8/#12/#13/#14） | ✅ |

---

## 4. 配额与判据（R362 / R328 复核）

- 判据 ①：R69 编码超时 70′ > 50′ 硬顶 → 基线 13 → **10**（−20%）；本轮不再叠加其他折减（否则低于 10 会伤及行业覆盖）。
- 判据 ②：10 件中 **7 件为低/中低复杂度**（N1/N2/N3/N4/N6/N9/N10），均有库内骨架先例（监视件=R68 `FlowMeterKFactorDrift`、抑制件=ISA-18.2 搁置族、记录件=`StepTimeRecorder`、校核件=`AdhesiveMass` 类=`CapperTorqueTrend` 判据组织），可快速成件。
- 判据 ③：**MathData / Algo / Motion 本轮 0 件**——R195 编译闸未开，禁令覆盖「编解码 / 数学 / 转换类高复杂度件」，故本轮不立项该三类；此为**主动回避**，非遗漏，头部风险已在 §1 记录。
- 判据 ④：N2/N5 两件为本轮唯一「分类借鉴」件，**算法 / 状态机 / 码位 / 阈值 100% 自有**（clean-room，只借分类事实与参数域组织方式），逐件声明见 `RAW_NOTES_R70.md`。

---

## 5. 编码轮（R70 后半段）执行顺序备忘

1. 起手：`dl_gate.py --selftest` 判据回归；同时跑「先引用后声明」单文件预检（R56 挂账未清，防 `_nCurRetry` 型编译阻断）。
2. 批 1：N1 → N3 → N4 → N2，逐件 `--file` 扫描。
3. 批 2：N7 → N6 → N5。
4. 批 3：N9 → N10 → N8。
5. 收口（主控/终审执行，本轮不做）：registry 注册 + JSONL 语料 + 五件套增量（closeout 脚本合并，R219）+ 终审两式（锁存解除可达 / 整数进位点）+ 三向一致（INDEX ∪ 文件树 ∪ ROADMAP 勾选）。

---

## 6. 本轮盘点发现的台账缺陷（挂账，交主控收口处理，本轮不改）

1. **勾选符号损坏 3 处**：ROADMAP §19.5 / §21.2 / §21.6 各一行写成 `- [x `（缺 `]`），渲染为未勾选但实际已注册——三向一致脚本若按正则 `^- \[ \]` 统计会误报「未注册池项」，建议收口时统一修正为 `- [x]`。
2. **同词干双前缀并存 1 组**：`FC_DL_TrackerBacktrackCalc`（2026-11-17）与 `FB_DL_TrackerBacktrackCalc`（2026-11-18）同词干同子库；标识符不冲突（不阻断编译），但属 R214 同义邻件高危区，**后续禁止再立 Backtrack 件**，并建议终审评估二者合并（FB 承载状态机、FC 作纯函数内核时属合理分工，需在件内头注释互引）。
3. **ROADMAP 头部统计陈旧**：文件头「当前库规模 186 / 10,000（v2.1.0）」与 registry 1189 / v2.61.0 严重不一致，属历史遗留表头；建议收口时改由脚本注入，避免每轮人工核对。

*R70 阶段一+二规划 ｜ 2026-11-22 ｜ 道莅工控代码库产品总监（无人值守批处理轮，WebSearch 0）*
