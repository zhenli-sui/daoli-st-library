# ROUND PLAN R23 —— 阶段一盘点 + 阶段二狩猎派单（20 件 / 4 批）

> 轮次：**R23** ｜ 生成时间：2026-11-17 ｜ 编制：道莅工控代码库产品总监（daoli-library-director / 召唤模式：原生）
> 性质：**行业工艺站落轮 + 焓湿图族收口**——T1-2 OSCAT Building 焓湿图全参族拆分落地（源矩阵 §5 待挖项「须先拆到可独立验收粒度」本轮兑现）+ ROADMAP 未注册 P1 项 14 件 + T2-8 NE107 待挖件 1 件
> 本文性质：**派单规格书**。不写组件代码，不改 `INDEX_REGISTRY.json` / JSONL / 任何 `.st`
> 检索预算：**0 次 WebSearch / ≤3 次**（全部取材零检索：T1-2 焓湿图公式复用库内已留痕的 Magnus-Tetens / PsychroLib 口径，其余为 ROADMAP 自研线；若编码专家需核对 Stull 湿球公式可动用预算并补留痕）
> P0 附加任务：`FB_DL_BatchTransferSeq` 中止时序修复（v1.0.2，随批 1 执行，见 §4）

---

## 0 盘点区（Step 1 · 状态读取 · 全部当场实测，不沿用交接口径）

### 0.1 总库状态（`INDEX_REGISTRY.json` 实解析 + `DL_*/*.st` 源码实测）

| 项 | 实测值 | 校验 |
|---|---|---|
| `version` | **2.11.0** | ✔ |
| `total_components` | **384** | 与 counts 求和 **384** 一致 ✔ |
| `last_updated` | `2026-11-16T23:59:00+08:00` | ✔ |
| 子库分布（counts 实读） | `DL_Base` **73** ｜ `DL_MathData` **148** ｜ `DL_Algo` **38** ｜ `DL_Device` **61** ｜ `DL_Motion` **30** ｜ `DL_Process` **34** | ✔ |
| 总库完成度 | **384 / 10 000 = 3.84 %** | — |
| 今日累计（11-17） | **0 / 200 = 0 %**（当日首轮） | — |
| 距 500 里程碑 | **116 件**（本轮交付后余 96） | — |
| ROADMAP 待办池 | **346 条未勾选**（实测 `[ ]` 计数）≥ 30 → **本轮不补写** | ✔ |

### 0.2 六库占比与扩容裁定

| 子库 | 件数 | 占比 | 本轮件数 | 轮后占比 | 裁定 |
|---|---|---|---|---|---|
| `DL_MathData` | 148 | **38.5 %** | **0** | 37.7 % | **冻结**：连续两轮限额后仍近四成，本轮 0 件（R22 裁定延续） |
| `DL_Base` | 73 | 19.0 % | **0** | 19.0 % | 冻结：无 T0 缺口（八行全 ✔），不接受凑数变体 |
| `DL_Algo` | 38 | 9.9 % | **5** | 10.6 % | 扩容：T1-2 焓湿图族整族落地（一个族占一批，同模板同公式链） |
| `DL_Device` | 61 | 15.9 % | **6** | 16.4 % | 扩容：联锁/诊断/健康族（ROADMAP P1 清零 5 条 + T2-8 待挖件 1 件） |
| `DL_Motion` | 30 | 7.8 % | **2** | 8.1 % | 温和扩容：轴侧安全层 R22 刚落 5 件，本轮只接强需求 2 件 |
| `DL_Process` | 34 | 8.9 % | **7** | 9.5 % | **本轮主力扩容**：行业工艺站（锂电/光伏/包装/公用工程）整层空缺 |

### 0.3 源矩阵取源判定（逐行解析，禁重复挖已 ✔ 收口组）

| 判定项 | 实测 | 结论 |
|---|---|---|
| T0-1 ~ T0-8 八行 | **8 / 8 全 ✔ 收口** | 只允许变体线深化，本轮无 T0 缺口 → **T0 取 0 件**（不虚账，R85） |
| T1/T2/NE43/ESC | **19 行全部 ◐，☐ = 0** | 无新源可开，只做 ◐ 深化 |
| T1-2 OSCAT Building 待挖项 | 「ROOM_CONTROL / **焓湿图全参族**待挖（须先拆到可独立验收粒度）」 | 本轮**拆分落地 5 件**（批 1 整族），满足「≥1 个 T2 组件族或 1 个 T1 组」配额 |
| T2-8 ISA-88/NE107 待挖项 | 「NE107 实现块仲裁件（**多源健康聚合**）待挖」 | 本轮落地 `FB_DL_HealthAggregator` 1 件 |
| T2-1 LGF Converter 待挖项 | 仅余 `StringToDTL`（**挂 DTL 编译债**，R22 留痕） | **本轮不立项**（编译债未清，宁少勿滥） |
| ROADMAP 未注册待办 | 346 条，P1 行业池充足 | 本轮取 **14 条**（Device 5 + Process 7 + Motion 2），符合「ROADMAP 未注册项优先于源矩阵待挖组」 |

### 0.4 ⚠ 码位游标当场实测（R61/R105 铁律：禁信交接数字）

全库 384 个 `.st` 源码正则 `16#[0-9A-F]{4}_[0-9A-Fa-f]{4}` 全量扫描去重，按段/子带统计（实测脚本口径：grep + sort -u，2026-11-17 当场执行）：

| 段（属主） | 子带实测 | 已用上界 | **本轮起点** | 与 R22 交接值核对 |
|---|---|---|---|---|
| `16#0001_`（DL_Base + DL_MathData **共用命名空间**） | 信息 `04xx` / 故障 `03xx` | `0465` / `03B6` | 信息 **`0466`** / 故障 **`03B7`** | ✔ 一致（本轮两库 0 件，游标原样传递） |
| `16#0002_`（DL_Algo，CC 网格） | CC 最大 = `2C` | CC `2C` | 下一 CC = **`2D`** | ✔ 一致 |
| `16#0003_`（DL_Device） | 信息 `01xx` / 故障 `03xx` | `0179` / `0347` | **`017A`** / **`0348`** | ✔ 一致 |
| `16#0004_`（DL_Motion） | 信息 `01xx` / 故障 `02xx` | `01DE` / `02F8` | **`01DF`** / **`02F9`** | ✔ 一致 |
| `16#0005_`（DL_Process） | 信息 `01xx` / 故障 `03xx` | `01E1` / `0316` | **`01E2`** / **`0317`** | ✔ 一致（**注意：`0317` 首槽派给 BatchTransferSeq 修复件**，见 §4） |

> 结构事实延续（R22 实测，本轮继续有效）：① `0001` 为 Base/MathData 共用命名空间，两库统一顺延；② `0003` 的 `02xx` 是早期设备故障带，新件一律走 `03xx`；③ `0005` 的 `02xx` 已分段占用至 `02FF` 无连续空位，新件走 `03xx` 连续区。

### 0.5 候选名查重（实测）

20 个候选 POU 名对全库 `DL_*/*.st` 逐一 grep：**20/20 零命中**。批内码位槽按「实测上界 + 1」顺延分配，无跨段占用。

---

## 1 R23 20 目标一览（锁定，宁少勿滥）

| # | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批 |
|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_VaporPressureSat` | DL_Algo | FC_DL_ | 饱和水蒸气压计算（Magnus-Tetens 原子，全族公式基准） | T1-2 OSCAT Building（焓湿图族拆分①） | L | 1 |
| 2 | `FC_DL_HumidityRatioCalc` | DL_Algo | FC_DL_ | 含湿量计算（露点/相对湿度 → kg 水蒸气/kg 干空气） | T1-2 OSCAT Building（焓湿图族拆分②） | M | 1 |
| 3 | `FC_DL_WetBulbTempCalc` | DL_Algo | FC_DL_ | 湿球温度估算（Stull 公开经验式 + 有效域显式化） | T1-2 OSCAT Building（焓湿图族拆分③） | M | 1 |
| 4 | `FC_DL_RhFromDewPoint` | DL_Algo | FC_DL_ | 露点 → 相对湿度逆运算原子（与 DewPointCalc 构成双向对） | T1-2 OSCAT Building（焓湿图族拆分④） | L | 1 |
| 5 | `FC_DL_MixAirStateCalc` | DL_Algo | FC_DL_ | 回风/新风混合点状态计算（质量守恒加权，经济器前置） | T1-2 OSCAT Building（焓湿图族拆分⑤） | M | 1 |
| 6 | `FB_DL_HealthAggregator` | DL_Device | FB_DL_ | 多源 NE107 健康聚合仲裁（编号即优先级，最差者胜） | T2-8 NE107（待挖项「多源健康聚合」落地） | H | 2 |
| 7 | `FB_DL_OvenDoorInterlock` | DL_Device | FB_DL_ | 烘箱炉门-氮气-温区三联锁（先置换后开门） | ROADMAP 锂电 P1（§350 行）+ T2-8 互锁语义次源 | M | 2 |
| 8 | `FB_DL_ChamberGateValve` | DL_Device | FB_DL_ | 真空腔体闸阀双位置互锁驱动（开/关到位双反馈 + 抽气侧联锁） | ROADMAP 半导体 P1（§424 行） | M | 2 |
| 9 | `FB_DL_RobotGripVerify` | DL_Device | FB_DL_ | 机械手夹持确认与掉片判据（真空/夹爪双反馈置位校验） | ROADMAP 半导体 P1（§372 行）+ 自研线 | M | 2 |
| 10 | `FB_DL_FilterDpMonitor` | DL_Device | FB_DL_ | 过滤器压差寿命监视（压差趋势 + 滤芯更换预警） | ROADMAP 公用工程 P1（§394 行）+ T2-8 NE107 次源 | M | 2 |
| 11 | `FB_DL_ElectrolyteDosingSeq` | DL_Process | FB_DL_ | 电解液定量注液顺控（抽液-称重-注液-静置节拍链） | ROADMAP 锂电 P1（§409 行）+ T2-8 ISA-88 相语义次源 | H | 3 |
| 12 | `FB_DL_NailMachineSeq` | DL_Process | FB_DL_ | 极耳裁切/模切机顺控（放卷-裁切-收料节拍链） | ROADMAP 锂电 P1（§351 行） | M | 3 |
| 13 | `FB_DL_LamHeaterZoneSync` | DL_Process | FB_DL_ | 层压机加热板多温区同步跟随（区差阈值 + 链速联动） | ROADMAP 光伏 P1（§416 行） | M | 3 |
| 14 | `FB_DL_SteamCondensatePot` | DL_Process | FB_DL_ | 凝液罐液位-排放顺控（液位双限 + 排水阀间歇排放） | ROADMAP 公用工程 P1（§392 行） | M | 3 |
| 15 | `FB_DL_AirCompDutyN2` | DL_Process | FB_DL_ | 空压机/制氮机组联产轮值（负荷排序 + 优先级投切） | ROADMAP 公用工程 P1（§393 行） | M | 3 |
| 16 | `FB_DL_WaferCountAxis` | DL_Motion | FB_DL_ | 晶圆计数轴（编码器分频 + 片位同步输出） | ROADMAP 半导体 P1（§369 行） | M | 4 |
| 17 | `FB_DL_BagFeedDancerSync` | DL_Motion | FB_DL_ | 制袋供膜摆辊同步（摆辊位置 PI + 线速前馈） | ROADMAP 包装 P1（§377 行） | H | 4 |
| 18 | `FB_DL_TankN2BlanketCtrl` | DL_Device | FB_DL_ | 储罐氮封压力双分程控制（低压补氮/高压泄放） | ROADMAP P1（§396 行） | M | 4 |
| 19 | `FB_DL_BoilerThreeElement` | DL_Process | FB_DL_ | 锅炉三冲量给水控制（汽包水位主回路 + 蒸汽/给水双前馈） | ROADMAP P1（§322 行） | H | 4 |
| 20 | `FB_DL_HumidityOverride` | DL_Process | FB_DL_ | 除湿优先模式仲裁（湿度越限覆盖温度控制优先级） | ROADMAP 暖通 P1（§297 行） | M | 4 |

**分布**：`DL_Algo` **5**（#1-5）｜ `DL_Device` **6**（#6-10、#18）｜ `DL_Process` **7**（#11-15、#19-20）｜ `DL_Motion` **2**（#16-17）｜ `DL_Base` **0** ｜ `DL_MathData` **0** ＝ **20**
**类型**：FC **5**（#1-4，#4 含 #5 前 5 个均为 FC）｜ FB **15**
**复杂度**：H **4**（#6、#11、#17、#19）｜ M **14**｜ L **2**（#1、#4）

### 1.1 为什么这 20 件不是「凑数变体」（逐族辩护）

1. **#1~#5 是源矩阵明文待挖项的拆分落地**：T1-2 行「焓湿图全参族待挖（须先拆到可独立验收粒度）」——本轮拆为 5 个可独立验收的原子（饱和蒸气压 / 含湿量 / 湿球 / 露点逆运算 / 混风点），全部复用库内已留痕的 Magnus-Tetens 公式口径（`FC_DL_DewPointCalc` / `FC_DL_HumidAirEnthalpy`），公式基准原子化后全族常量只有一份属主。缺这族，焓湿图全参链（含湿量→湿球→混风→经济器）在库内断链。
2. **#6 是 T2-8 明文待挖项**：「NE107 实现块仲裁件（多源健康聚合）待挖」——现库有六态枚举属主 `E_DL_Ne107Status` 与若干单源实现块，但无聚合件；HMI 顶部健康横幅每次手写比较。
3. **#7~#10、#18 是 Device 诊断/联锁层五条实缺**：烘箱三联锁（锂电干燥环节安全前置）、真空闸阀双反馈（半导体必备）、夹持掉片判据（取放可靠性）、滤芯压差寿命（耗材预测维护）、氮封双分程（储罐安全）——全部为 ROADMAP P1 且与既有件职责边界清晰。
4. **#11~#15、#19~#20 是 Process 行业工艺站整层扩容**：锂电注液/极耳、光伏层压、公用工程凝液/空压联产、锅炉三冲量、除湿仲裁——七个 P1 全部只编排已收口低层能力（StepSequencer / DutyStandbyRotation / RampSoakProfile / PidController 由调用方注入），零新算法内核。
5. **#16~#17 是 Motion 强需求两件**：晶圆计数轴（编码器分频 + 片位同步，半导体 EAP 对账刚需）、制袋摆辊同步（线速前馈闭环，包装高频）。Motion 上轮刚扩 5 件，本轮按「宁少勿滥」只接 2 件。
6. **剔除名单（防凑数）**：`FC_DL_EnthalpyFromRh`（可由 #2+#4 组合两步得出，薄件不立）；`FB_DL_TrackerBacktrackCalc`（P2 纯几何，与 `FC_DL_SolarPositionCalc` 职责重叠风险待先评估，留待后轮）；`FB_DL_VavBoxCtrl`（需风量闭环控制器内核，与 `FB_DL_PidController` 边界未拆清，立项条件不成熟）；`FC_DL_StringToDTL`（挂 DTL 编译债，R22 已裁定不立项）。

### 1.2 来源配比（本轮取源账目）

| 源 | 件数 | 件号 | 借用层级 |
|---|---|---|---|
| **T1-2 OSCAT Building（焓湿图族整族深化）** | **5** | #1~#5 | 行为定义 + 公开物理公式链（Magnus-Tetens / PsychroLib / ASHRAE 公开公式，R5/R6 已留痕口径复用，零新检索） |
| **T2-8 NE107 / ISA-88** | **2** | #6（待挖项落地）、#7/#11（语义次源） | 六态仲裁语义 / 相-步骤语义（公开条款） |
| ROADMAP 未注册自研线（P1） | **14** | #7~#15、#16~#20 | 自研 clean-room，只组合调用已收口低层件 |
| T0 | **0** | — | 八行全 ✔，无缺口，不虚账（R85/M-E5） |
| 检索 | **0 次** | — | 全部复用既有留痕口径 + 公开文献常识；如编码专家需核对 Stull 2011 公式，动用预算并补记 RAW_NOTES |

> **配额结论**：满足「每轮至少 1 个 T2 组件族或 1 个 T1 组」（T1-2 焓湿图族 5 件整族落地）；满足源矩阵 §4「≥1 个 T2 非 ST 源 + ≥1 个 T1 ST 原生源」双向要求；**未触碰任何已 ✔ 收口组**（T0 八行 + T1-3 已收口行零接触）。

---

## 2 四批划分与码位账目

| 批 | 主题 | 件号 | 件数 | 码位段 |
|---|---|---|---|---|
| 批 1 | **T1-2 焓湿图原子族（DL_Algo）** + P0 修复件 | #1-5 + 修复 | 5+1 | `0002` CC `2D`~`31`；修复件 `0005` 故障 `0317` |
| 批 2 | **设备健康与联锁族（DL_Device）** | #6-10 | 5 | `0003` 信息 `017A`~ / 故障 `0348`~ |
| 批 3 | **行业工艺站顺控（DL_Process）** | #11-15 | 5 | `0005` 信息 `01E2`~ / 故障 `0318`~ |
| 批 4 | **运动同步 + 公用工程混合收尾** | #16-20 | 5 | `0004` 信息 `01DF`~ / 故障 `02F9`~；`0003`/`0005` 各续段 |

**槽位账目**：20 件 × 5 槽 = **100 槽**（信息 40 + 故障 60）+ 修复件故障槽 1（`0317`）= **101 槽**。
**轮后游标（供 R24 引用，届时须当场复测）**：

| 段 | 轮后信息级游标 | 轮后故障级游标 |
|---|---|---|
| `0001` | **`0466`**（本轮零占用，原样传递） | **`03B7`**（同上） |
| `0002` | **下一 CC = `32`**（`2D`~`31` 五个 CC 已派） | — |
| `0003` | **`0186`**（6 件 × 2 槽） | **`035A`**（6 件 × 3 槽） |
| `0004` | **`01E3`**（2 件 × 2 槽） | **`02FF`**（2 件 × 3 槽） |
| `0005` | **`01F0`**（7 件 × 2 槽） | **`032D`**（修复 1 + 7 件 × 3 槽） |

**逐件 5 槽码位块（派单原文，编码专家照抄，不得自选码位）**：

| # | 组件 | 信息槽 1（用） | 信息槽 2 | 故障槽 1（用） | 故障槽 2（用） | 故障槽 3 |
|---|---|---|---|---|---|---|
| F | `BatchTransferSeq` v1.0.2（修复件） | —（复用 01E0/01E1） | — | **`0005_0317`**（中止第二段关阀确认超时） | — | — |
| 1 | `VaporPressureSat` | `0002_2D01` | `2D02` | `2D10` | `2D11` | `2D12`（兜底） |
| 2 | `HumidityRatioCalc` | `2E01` | `2E02` | `2E10` | `2E11` | `2E12`（兜底） |
| 3 | `WetBulbTempCalc` | `2F01` | `2F02` | `2F10` | `2F11` | `2F12`（兜底） |
| 4 | `RhFromDewPoint` | `3001` | `3002` | `3010` | `3011` | `3012`（兜底） |
| 5 | `MixAirStateCalc` | `3101` | `3102` | `3110` | `3111` | `3112`（兜底） |
| 6 | `HealthAggregator` | `0003_017A` | `017B` | `0348` | `0349` | `034A`（兜底） |
| 7 | `OvenDoorInterlock` | `017C` | `017D` | `034B` | `034C` | `034D`（兜底） |
| 8 | `ChamberGateValve` | `017E` | `017F` | `034E` | `034F` | `0350`（兜底） |
| 9 | `RobotGripVerify` | `0180` | `0181` | `0351` | `0352` | `0353`（兜底） |
| 10 | `FilterDpMonitor` | `0182` | `0183` | `0354` | `0355` | `0356`（兜底） |
| 11 | `ElectrolyteDosingSeq` | `0005_01E2` | `01E3` | `0318` | `0319` | `031A`（兜底） |
| 12 | `NailMachineSeq` | `01E4` | `01E5` | `031B` | `031C` | `031D`（兜底） |
| 13 | `LamHeaterZoneSync` | `01E6` | `01E7` | `031E` | `031F` | `0320`（兜底） |
| 14 | `SteamCondensatePot` | `01E8` | `01E9` | `0321` | `0322` | `0323`（兜底） |
| 15 | `AirCompDutyN2` | `01EA` | `01EB` | `0324` | `0325` | `0326`（兜底） |
| 16 | `WaferCountAxis` | `0004_01DF` | `01E0` | `02F9` | `02FA` | `02FB`（兜底） |
| 17 | `BagFeedDancerSync` | `01E1` | `01E2` | `02FC` | `02FD` | `02FE`（兜底） |
| 18 | `TankN2BlanketCtrl` | `0003_0184` | `0185` | `0357` | `0358` | `0359`（兜底） |
| 19 | `BoilerThreeElement` | `0005_01EC` | `01ED` | `0327` | `0328` | `0329`（兜底） |
| 20 | `HumidityOverride` | `01EE` | `01EF` | `032A` | `032B` | `032C`（兜底） |

> **预留槽纪律（R22 沿用）**：标「预留」的槽必须在头注释错误码表内写 `预留禁用（不得挪用）`，实现体不得出现该码的任何赋值。

---

## 3 编码派单规格（引脚级，可直接编码）

> **通用接口三件套（全 20 件统一）**：`VAR_OUTPUT` 必须含 `eErr : UDINT`（0 = 无错）、`bError : BOOL`（**仅故障级置位**）、`bValid : BOOL`（输出可用）。
> **单位纪律**：每件头注释「单位表」段列出全部物理量单位；引脚注释同行 `// 中文 [单位] / English [unit]`，无单位裸数值一律驳回。
> **子库依赖纪律（本轮硬约束）**：
> - `DL_Algo` 件（#1~#5）：只依赖 `Standard.library`（纯函数），**不得引用** `DL_Base` / `DL_MathData`（R22 纪律延续）；公式常量在本文件头注释声明属主，禁魔法数。
> - `DL_Device` 件（#6~#10、#18）：默认仅 `Standard.library` + 同库契约 `E_DL_Ne107Status`（**引用不重声明**，R70 唯一属主）；ROADMAP 行明示复用的 Level 0 低层件（`FB_DL_InterlockMatrix` / `FB_DL_SignalStatistics`，均在 DL_Base/DL_MathData，Level 1→Level 0 方向合法）允许**组合调用**；**不得调用同层 `DL_Algo` 件**（#18 的分程律内联实现 + 头注释「依赖收窄」段声明，R11 留档③先例）。
> - `DL_Motion` 件（#16、#17）：**不得引用任何其他 `DL_` 子库**（R22 纪律延续），只能用 `Standard.library` + 同库 `I_DL_MotionAxis`；#17 的前馈律内联实现并声明。
> - `DL_Process` 件（#11~#15、#19、#20）：可依赖 Level 0/1（合法方向），**只允许组合调用**，不得复制低层算法；跨件调用须按 R36 手算退出跟踪首拍。

### 注释 / 错误码样板原文（R50 防漂移，全件内嵌，编码专家照抄结构）

文件头溯源短语（按源二选一，置于头注释「开源溯源 (Origin)」字段）：

```text
T0 件用：IEC 61131-3 标准语义的道莅防御性实现
T2 件用：道莅 clean-room 防御性实现
T1 件用：改写自 OSCAT Building 行为定义（OSCAT 许可，仅行为定义，零代码行）——道莅 clean-room 实现
自研件用：道莅原创实现（参考 <公开规范/工程惯例> 分类与参数域）
```

头注释骨架（每件必备九段，段名不得增删）：

```text
// 功能块：FB_DL_Xxx / 函数：FC_DL_Xxx ｜ 中文名称：xxx
// 所属子库：DL_Algo ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：<一句话>
// 开源溯源 (Origin)：<按上表短语>
// 单位表：<全部物理量与单位，如 T[°C] / P[Pa] / RH[%] / f[Hz]]
// 错误码表：16#XXXX_XXXX 信息级（不置 bError）/ 16#XXXX_XXXX 故障级（置 bError）/ 预留禁用（不得挪用）
// 状态机：E_DL_XxxState（若为 FB，枚举成员须逐一中文注释；纯函数写 N/A）
// 边界行为：<域外/非有限/越界时输出策略，显式化，不得静默塞伪值>
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单）
```

变量注释与错误码样式：

```st
fDewPoint  : LREAL;      // 露点温度 [°C] / Dew-point temperature [degC]
eErr       : UDINT;      // 错误码，0 = 无错 / Error code, 0 = no error
// 16#0002_2D10 // 输入非有限（NaN/Inf），输出饱和边界值（故障级，置 bError） / Non-finite input, output clamped (fault, bError set)
```

#### #1 `FC_DL_VaporPressureSat` —— 饱和水蒸气压（全族公式基准原子）
- **分类**：`DL_Algo / Psychrometrics` ｜ FUNCTION → `BOOL`（TRUE = 计算有效）｜ **复杂度** L
- **VAR_INPUT**：`fTempC : LREAL`（[°C] 空气温度，有效域 −40~100 °C 域外钳位算趋势参考）
- **VAR_OUTPUT**：`fPvSat : LREAL`（[Pa] 饱和水蒸气压）、`bClamped : BOOL`（TRUE = 输入已钳位）、`eErr` / `bError` / `bValid`
- **VAR CONSTANT**：`DL_PSV_TMIN : LREAL := -40.0`；`DL_PSV_TMAX : LREAL := 100.0`（[°C]， Magnus-Tetens 有效域，禁魔法数）
- **功能规格**：Magnus-Tetens 公式 `fPvSat := 610.94 * EXP(17.625 * fT / (fT + 243.04))`（[Pa]，fT 为钳位后摄氏温度）；**全族唯一属主**：#2/#3/#4/#5 一律调用本件取饱和压，**禁止各自内联公式**（常量单源，防口径漂移）。
- **边界安全条件**：① `fTempC < TMIN` → 钳到 TMIN + `bClamped := TRUE` + 信息 `2D01`（域外按趋势参考，**不得置故障**——低温干燥是合法工况）；② 非有限输入（`(x−x)<>(x−x)` 判 NaN，R79）→ 故障 `2D10`、`bValid := FALSE`、输出 0；③ 结果有限性复检（EXP 上溢拦 Abs > 1.7976931348623157E308）→ 故障 `2D10` 复用（R90 不加码，头注释写明复用理由）。
- **码位**：信息 `2D01`（温度已钳位）/ `2D02` 预留 ｜ 故障 `2D10`（非有限输入或结果溢出）/ `2D11` 预留 / `2D12` 预留
- **来源**：T1-2 OSCAT Building 焓湿图族（行为定义，Magnus-Tetens 公式为公开物理公式；与 `FC_DL_DewPointCalc` 常量口径一致，属主转移声明写进两件头注释）

#### #2 `FC_DL_HumidityRatioCalc` —— 含湿量计算
- **分类**：`DL_Algo / Psychrometrics` ｜ FUNCTION → `BOOL` ｜ **复杂度** M
- **VAR_INPUT**：`fTempC : LREAL`（[°C]）；`eRhMode : E_DL_RhInputMode`（`eDewPoint` / `eRelativeHumidity`，输入模式枚举）；`fRhIn : LREAL`（[RH %] 或 [°C 露点]，按 eRhMode 解释）；`fPress : LREAL := 101325.0`（[Pa] 大气压，引脚注入非魔法数）
- **VAR_OUTPUT**：`fHumRatio : LREAL`（[kg 水蒸气 / kg 干空气]）、`fPv : LREAL`（[Pa] 实际水蒸气分压）、`eErr` / `bError` / `bValid`
- **功能规格**：`eDewPoint` 模式：fPv := VaporPressureSat(fRhIn)（露点即饱和点）；`eRelativeHumidity` 模式：fPv := Rh/100 × VaporPressureSat(fTempC)；`fHumRatio := 0.621945 × fPv / (fPress − fPv)`（公开 ASHRAE 公式，系数 0.621945 为干空气/水蒸气摩尔质量比，头注释注明出处）。
- **边界安全条件**：① `fPress <= 0` → 故障 `2E10`、`bValid := FALSE`；② `fPv >= fPress`（露点 > 干球温度等物理矛盾）→ 故障 `2E11`（输入矛盾）、`bValid := FALSE`；③ `fRhIn` 域外（RH < 0 或 > 100）→ 钳位 + 信息 `2E01` + `bClamped` 语义输出；④ 非有限任一输入 → 故障 `2E10` 复用；⑤ 枚举非法值走 `ELSE` 兜底 → 故障 `2E12`（纯函数用判据而非状态机，头注释状态机段写 N/A）。
- **码位**：信息 `2E01`（RH 已钳位）/ `2E02` 预留 ｜ 故障 `2E10`（大气压非法/非有限输入）/ `2E11`（露点>干球物理矛盾）/ `2E12`（枚举非法兜底）
- **来源**：T1-2 焓湿图族（ASHRAE Fundamentals 公开公式链 + PsychroLib 语义，零代码行）

#### #3 `FC_DL_WetBulbTempCalc` —— 湿球温度估算
- **分类**：`DL_Algo / Psychrometrics` ｜ FUNCTION → `BOOL` ｜ **复杂度** M
- **VAR_INPUT**：`fTempC : LREAL`（[°C] 干球温度，有效域 −20~60 °C）；`fRh : LREAL`（[%RH] 1~100）；`fPress : LREAL := 101325.0`（[Pa]）
- **VAR_OUTPUT**：`fWetBulbC : LREAL`（[°C] 湿球温度）、`bClamped : BOOL`、`eErr` / `bError` / `bValid`
- **VAR CONSTANT**：`DL_WB_TMIN : LREAL := -20.0`；`DL_WB_TMAX : LREAL := 60.0`（[°C] Stull 公式有效域，域外显式声明精度不承诺）
- **功能规格**：Stull (2011) 公开经验式迭代求解：`Tw_{n+1} = Tw_n − (Tw_n×(2501 − 2361×Tw_n) − 1000×CP_AIR×(fT − Tw_n)) / (2501 − 2361×Tw_n + 1000×CP_AIR + 0.622×L_V/(P×γ))` 式不动点迭代（γ = 0.000662 [1/°C] 心理测量常数），迭代上限 `DL_WB_ITER_MAX : UINT := 20` + 收敛阈 `1E-4 [°C]`，**WHILE 防死锁计数器强制**。
- **边界安全条件**：① 温度域外 → 钳位 + 信息 `2F01` + 头注释「精度承诺收窄至 −20~60 °C」；② RH 域外 → 钳 1~100 + 信息 `2F01`；③ 迭代 20 次不收敛 → 输出末次迭代值 + `bValid := TRUE` + 信息 `2F02`（**降级可观测，不置故障**——经验式本身是近似）；④ `fPress <= 0` 或非有限 → 故障 `2F10`；⑤ 迭代发散（相邻两次差 > 100 °C）→ 故障 `2F11`、`bValid := FALSE`。
- **码位**：信息 `2F01`（输入已钳位）/ `2F02`（迭代未达收敛阈，降级输出）｜ 故障 `2F10`（大气压非法/非有限）/ `2F11`（迭代发散）/ `2F12` 预留
- **来源**：T1-2 焓湿图族（Stull 2011 公开文献经验式；编码专家如需核对公式原文可动用检索预算并补记 RAW_NOTES）

#### #4 `FC_DL_RhFromDewPoint` —— 露点 → 相对湿度逆运算
- **分类**：`DL_Algo / Psychrometrics` ｜ FUNCTION → `BOOL` ｜ **复杂度** L
- **VAR_INPUT**：`fTempC : LREAL`（[°C] 干球温度）；`fDewPointC : LREAL`（[°C] 露点温度）
- **VAR_OUTPUT**：`fRh : LREAL`（[%RH] 0~100）、`eErr` / `bError` / `bValid`
- **功能规格**：`fRh := 100 × VaporPressureSat(fDewPointC) / VaporPressureSat(fTempC)`（纯比值，两次调用 #1 属主件，本件无自带公式常量）。
- **边界安全条件**：① `fDewPointC > fTempC` → 钳 fRh := 100 + 信息 `3001`（**过饱和物理矛盾按饱和处理不置故障**，与 #2 的 2E11 策略差异在头注释写明：#2 是含湿量分母保护必须故障，本件比值语义可安全钳位）；② `fDewPointC > fTempC + DL_RHDP_OVERHYST`（[°C] 常量 5.0，超 5 K 判传感器矛盾）→ 故障 `3010`、`bValid := FALSE`；③ 非有限任一输入 → 故障 `3010` 复用；④ 干球温度域外（−40~100 °C 外）→ 钳位 + 信息 `3001` 复用（R90）。
- **码位**：信息 `3001`（露点超干球钳 100 或温度已钳位）/ `3002` 预留 ｜ 故障 `3010`（传感器矛盾 >5 K 或非有限）/ `3011` 预留 / `3012` 预留
- **来源**：T1-2 焓湿图族（与 `FC_DL_DewPointCalc` 构成双向对，round-trip 验收向量必须：DewPoint→Rh→DewPoint 误差 < 1E-3 °C）

#### #5 `FC_DL_MixAirStateCalc` —— 回风/新风混合点状态
- **分类**：`DL_Algo / Psychrometrics` ｜ FUNCTION → `BOOL` ｜ **复杂度** M
- **VAR_INPUT**：`fRaTempC / fRaHumRatio : LREAL`（回风 [°C] / [kg/kg]）；`fOaTempC / fOaHumRatio : LREAL`（新风 [°C] / [kg/kg]）；`fOaFrac : LREAL`（[%] 新风比 0~100）
- **VAR_OUTPUT**：`fMixTempC : LREAL`（[°C] 混合干球）；`fMixHumRatio : LREAL`（[kg/kg] 混合含湿量）；`fMixEnthalpy : LREAL`（[kJ/kg 干空气] 混合焓，调 `FC_DL_HumidAirEnthalpy` 语义复算）——**禁**：DL_Algo 不得跨库调用，焓值用本件内联等价式 `h := 1.006×T + fHumRatio×(2501 + 1.86×T)` 并在头注释声明与 HumidAirEnthalpy 口径一致性验证责任；`bCondensation : BOOL`（TRUE = 混合点越过饱和线，结露预警）；`eErr` / `bError` / `bValid`
- **功能规格**：质量守恒加权 `fMixX := fOaFrac/100 × fOaX + (1 − fOaFrac/100) × fRaX`（干球与含湿量分别加权）；结露判据：`fMixTempC < VaporPressureSat 反解(fMixHumRatio, fPress 内取 101325 常量引脚注入)` → bCondensation（简化判据头注释声明精度限界）。
- **边界安全条件**：① `fOaFrac` 域外 → 钳 0~100 + 信息 `3101`；② 任一输入非有限 → 故障 `3110`、`bValid := FALSE`；③ 含湿量输入 < 0 → 钳 0 + 信息 `3101` 复用；④ 结露仅置预警位**不置故障**（bCondensation 是工况事实不是错误）。
- **码位**：信息 `3101`（新风比/含湿量已钳位）/ `3102` 预留 ｜ 故障 `3110`（非有限输入）/ `3111` 预留 / `3112` 预留
- **来源**：T1-2 焓湿图族（ASHRAE 混风质量守恒公开公式；与 `FB_DL_EnthalpyCompareCtrl` 的职责边界：本件算状态点，经济器做决策）

### 3.2 批 2 规格（设备健康与联锁族，引脚级摘要）

> 5 件均为 FB，统一三件套 + 状态机 + ELSE 兜底 + `TON`/`R_TRIG` 首部无条件刷新（R40）。以下给核心引脚与边界条件，完整模板照 §3 骨架展开。

#### #6 `FB_DL_HealthAggregator` —— 多源 NE107 健康聚合仲裁
- **VAR_INPUT**：`aHealth : ARRAY[1..DL_HEALTH_MAX] OF E_DL_Ne107Status`（[—] 各源健康态，`DL_HEALTH_MAX : UINT := 16`）；`uSourceCount : UINT`（[路] 实际源数 1~16）；`bArbitrate : BOOL`（仲裁使能）
- **VAR_OUTPUT**：`eOverall : E_DL_Ne107Status`（[—] 聚合结果 = 编号最小者优先，即最差者胜）；`uWorstIdx : UINT`（[路] 最差源下标，0 = 无）；`uFailCount / uMaintCount : UINT`（[路] 各级计数）；`eErr` / `bError` / `bValid`
- **边界**：① `uSourceCount > 16` → 钳 16 + 信息 `017A`；② `uSourceCount = 0` → 故障 `0348`、`eOverall := eUnknown`；③ 数组越界访问强制 `IF uIdx <= DL_HEALTH_MAX` 二次闸；④ 全 `eUnknown` → 输出 `eUnknown` + 信息 `017B`（合法结论非错误）；⑤ 无状态跨拍锁存（纯当拍仲裁），头注释声明「聚合无迟滞，调用方如需防抖自行组合 FB_DL_SignalDebounce」。
- **码位**：信息 `017A`/`017B` ｜ 故障 `0348`/`0349` 预留/`034A` 兜底

#### #7 `FB_DL_OvenDoorInterlock` —— 烘箱炉门-氮气-温区三联锁
- **VAR_INPUT**：`bDoorClosedFb : BOOL`；`bN2PurgeOk : BOOL`（[—] 氮气置换完成）；`fZoneTempC : LREAL`（[°C] 温区实测）；`fOpenTempMaxC : LREAL := 45.0`（[°C] 允许开门温度上限）；`bDoorOpenCmd : BOOL`（开门请求）
- **VAR_OUTPUT**：`bDoorUnlock : BOOL`（[—] 开锁放行）；`eInterlockState : E_DL_OvenDoorState`（五态：`eLocked/ePurging/eTempHigh/eReleased/eFault`）；`eErr` / `bError` / `bValid`
- **边界**：① 三条件（门已关确认→氮气 OK→温度 ≤ 上限）任一失守 → 回 `eLocked` 并锁存最近失守原因码；② `fOpenTempMaxC <= 0` → 故障 `034B`（组态非法）；③ 温度非有限 → 故障 `034B` 复用 + 拒绝放行（**安全侧默认**：非法值绝不放行开门）；④ 温度迟滞用 `FC_DL_Hysteresis` 语义内联（Device→Base 组合调用合法，头注释依赖清单声明）；⑤ 状态机 ELSE 兜底 → 故障 `034D` + 回 `eLocked`。
- **码位**：信息 `017C`（放行时温度接近上限提示）/`017D` 预留 ｜ 故障 `034B`（组态/非有限）/`034C`（确认矛盾：开锁时门反馈消失）/`034D` 兜底

#### #8 `FB_DL_ChamberGateValve` —— 真空腔体闸阀双位置互锁
- **VAR_INPUT**：`bOpenCmd / bCloseCmd : BOOL`；`bOpenedFb / bClosedFb : BOOL`（开/关到位双反馈）；`bPumpingActive : BOOL`（[—] 抽气联锁：抽气中禁开）；`tFbTimeout : TIME := T#5S`（[ms] 反馈超时）
- **VAR_OUTPUT**：`bOpenOut / bCloseOut : BOOL`（双输出互斥断言）；`eValveState : E_DL_GateValveState`（六态含 `eMoving/eFault`）；`eErr` / `bError` / `bValid`
- **边界**：① 双反馈同拍为 TRUE → 故障 `034E`（到位矛盾，输出全断）；② 双命令同拍为 TRUE → 拒绝 + 信息 `017E`（关优先，安全侧）；③ 抽气中收到开命令 → 拒绝 + 信息 `017F`；④ 移动态超时无反馈 → 故障 `034F` + 输出全断；⑤ 互斥断言：任一拍 `NOT (bOpenOut AND bCloseOut)` 结构性成立。
- **码位**：信息 `017E`/`017F` ｜ 故障 `034E`/`034F`/`0350` 兜底

#### #9 `FB_DL_RobotGripVerify` —— 机械手夹持确认与掉片判据
- **VAR_INPUT**：`bVacOk / bClampOk : BOOL`（真空/夹爪双反馈）；`eGripMode : E_DL_GripMode`（`eVacuum/eClamp/eDualConfirm`）；`bGripCmd / bReleaseCmd : BOOL`；`tConfirmTime : TIME := T#200MS`（[ms] 确认窗）
- **VAR_OUTPUT**：`bGripVerified : BOOL`；`bDropSuspect : BOOL`（[—] 掉片疑似：已确认后反馈丢失）；`uDropCount : UDINT`（[次] 掉片累计）；`eErr` / `bError` / `bValid`
- **边界**：① 已确认后反馈丢失 > 确认窗 → `bDropSuspect := TRUE` + uDropCount 递增 + 故障 `0351`；② `eDualConfirm` 模式双反馈缺一 → 不确认（保守侧）；③ 释放沿后 200 ms 内反馈仍 TRUE → 信息 `0180`（粘连疑似）；④ 枚举非法 → 故障 `0353` 兜底；⑤ 计数器饱和 `4294967295` 不回绕。
- **码位**：信息 `0180`/`0181` ｜ 故障 `0351`（掉片疑似）/`0352` 预留/`0353` 兜底

#### #10 `FB_DL_FilterDpMonitor` —— 过滤器压差寿命监视
- **VAR_INPUT**：`fDpKpa : LREAL`（[kPa] 压差实测）；`fDpChangeKpa : LREAL := 0.8`（[kPa] 更换预警阈值）；`fDpAlarmKpa : LREAL := 1.5`（[kPa] 堵塞报警阈值）；`tTrendWindow : TIME := T#1H`（[ms] 趋势窗）
- **VAR_OUTPUT**：`eHealth : E_DL_Ne107Status`（引用属主枚举：正常 eOk / 预警 eMaintenanceReq / 堵塞 eOutOfSpec）；`fDpTrendKpaH : LREAL`（[kPa/h] 趋势斜率）；`bReplaceHint : BOOL`；`eErr` / `bError` / `bValid`
- **边界**：① `fDpAlarmKpa <= fDpChangeKpa` → 故障 `0354`（阈值倒置）；② 压差非有限 → 故障 `0354` 复用 + 保持末次有效健康态（不静默塞 eOk）；③ 负压差（传感器接反）→ 信息 `0182` + 按 0 处理；④ 趋势组合调用 `FB_DL_SignalStatistics`（Device→MathData Level1→Level0 合法，头注释依赖清单声明）；⑤ 健康态降级锁存：eOutOfSpec 需手动复位才回 eOk。
- **码位**：信息 `0182`/`0183` ｜ 故障 `0354`（阈值倒置/非有限）/`0355` 预留/`0356` 兜底

### 3.3 批 3 规格（行业工艺站顺控，引脚级摘要）

#### #11 `FB_DL_ElectrolyteDosingSeq` —— 电解液定量注液顺控（复杂度 H）
- **VAR_INPUT**：`bStart / bAbort : BOOL`；`fTargetMassG : LREAL`（[g] 目标注液量）；`fCoarseFineKg : LREAL := 0.95`（[倍] 粗/细切换点占目标比）；`fScaleMassG : LREAL`（[g] 电子秤实时读数）；`tSettleTime : TIME := T#2S`（[ms] 静置浸润计时）
- **VAR_OUTPUT**：`ePhase : E_DL_DosingPhase`（八态：`eIdle/eVacuumDraw/eWeighCheck/eCoarseFill/eFineFill/eSettle/eDone/eFault`）；`fDosedMassG : LREAL`（[g] 已注量）；`bDosingOut / bPumpOut : BOOL`；`eErr` / `bError` / `bValid`
- **边界**：① `fTargetMassG <= 0` → 故障 `0318`；② 称重回退（fScaleMassG 比上拍小超容差）→ 故障 `0319`（秤异常，暂停顺控保持输出）；③ **bAbort 两段化纪律照 §4 修复件样板执行**（断输出使能→惰转窗→关阀，禁单拍先停后关）；④ 八态 CASE 每态显式 + ELSE 兜底 → 故障 `031A` + 全输出断；⑤ 组合调用 `FB_DL_StepSequencer`（Process→Level 0 合法），步号映射表写头注释。
- **码位**：信息 `01E2`（粗细切换点已达）/`01E3` 预留 ｜ 故障 `0318`/`0319`/`031A` 兜底

#### #12 `FB_DL_NailMachineSeq` —— 极耳裁切/模切机顺控
- **VAR_INPUT**：`bStart / bStop : BOOL`；`bUnwinderReady / bCutterHome / bCollectorReady : BOOL`（三工位就绪反馈）；`uBatchCount : UDINT`（[片] 批量目标）；`tCutCycleMax : TIME := T#3S`（[ms] 单拍节拍上限）
- **VAR_OUTPUT**：`eSeqState : E_DL_NailSeqState`（七态）；`uCutDone : UDINT`（[片] 已切计数）；`bUnwindRun / bCutTrig / bCollectRun : BOOL`；`eErr` / `bError` / `bValid`
- **边界**：① 三就绪缺一 → 停在 `eWaitReady` 并输出缺哪个（诊断掩码）+ 信息 `01E4`；② 单拍节拍超时 → 故障 `031B` + 全停；③ 计数达批 → 回 `eIdle` + 信息 `01E5`；④ bStop 立即断裁切输出（**安全侧不停机次序假设**：模切头行程内停止由驱动层负责，头注释声明边界）；⑤ ELSE 兜底 `031D`。
- **码位**：信息 `01E4`/`01E5` ｜ 故障 `031B`（节拍超时）/`031C` 预留/`031D` 兜底

#### #13 `FB_DL_LamHeaterZoneSync` —— 层压机多温区同步跟随
- **VAR_INPUT**：`aZoneTempC : ARRAY[1..DL_ZONE_MAX] OF LREAL`（[°C] 各温区实测，`DL_ZONE_MAX : UINT := 8`）；`fZoneDiffMaxK : LREAL := 5.0`（[K] 区差阈值）；`fBeltSpeedMmS : LREAL`（[mm/s] 链速，联动跟随斜率）；`bEnable : BOOL`
- **VAR_OUTPUT**：`fMaxZoneDiffK : LREAL`（[K] 当拍最大区差）；`bSyncOk : BOOL`；`uWorstPairA / uWorstPairB : UINT`（[区] 最大温差对）；`eErr` / `bError` / `bValid`
- **边界**：① 区差 > 阈值持续 `tSyncFaultDelay := T#10S`（[ms] 确认窗）→ 故障 `031E` + `bSyncOk := FALSE`（R13 AhuDamperStuckDiag 确认窗范式复用）；② 任一温区非有限 → 该区剔除 + 信息 `01E6`（有效区数 < 2 → 故障 `031F`，无法判区差）；③ 链速为 0 → 跟随斜率冻结（不除零）；④ 区数上限钳 8 + 信息 `01E7`。
- **码位**：信息 `01E6`/`01E7` ｜ 故障 `031E`（区差超限确认）/`031F`（有效区不足）/`0320` 兜底

#### #14 `FB_DL_SteamCondensatePot` —— 凝液罐液位-排放顺控
- **VAR_INPUT**：`fLevelPct : LREAL`（[%] 液位 0~100）；`fPumpLevelHiPct / fPumpLevelLoPct : LREAL`（[%] 排放启/停液位，迟滞对）；`bDrainValveFb : BOOL`；`tDrainMax : TIME := T#30S`（[ms] 单次排放上限）
- **VAR_OUTPUT**：`bDrainOut : BOOL`；`ePotState : E_DL_CondPotState`（五态含 `eDraining/eTimeout`）；`uDrainCount : UDINT`（[次] 排放计数）；`eErr` / `bError` / `bValid`
- **边界**：① `fPumpLevelLoPct >= fPumpLevelHiPct` → 故障 `0321`（迟滞倒置）；② 排放超 tDrainMax 液位未降 → 故障 `0322`（排放堵塞）+ 关阀；③ 液位域外钳 0~100 + 信息 `01E8`；④ 排放计数饱和不回绕；⑤ ELSE 兜底 `0323`。
- **码位**：信息 `01E8`/`01E9` ｜ 故障 `0321`/`0322`/`0323` 兜底

#### #15 `FB_DL_AirCompDutyN2` —— 空压机/制氮机组联产轮值
- **VAR_INPUT**：`aN2DemandNm3H : LREAL`（[Nm³/h] 制氮需求）；`aN2SupplyNm3H : ARRAY[1..DL_UNIT_MAX] OF LREAL`（[Nm³/h] 各机组能力，`DL_UNIT_MAX : UINT := 4`）；`abUnitReady : ARRAY[1..DL_UNIT_MAX] OF BOOL`；`abUnitRunFb : ARRAY[1..DL_UNIT_MAX] OF BOOL`
- **VAR_OUTPUT**：`abUnitCmd : ARRAY[1..DL_UNIT_MAX] OF BOOL`；`uUnitsNeeded : UINT`（[台] 需投台数）；`fSupplyMarginNm3H : LREAL`（[Nm³/h] 供/需余量，负值即缺口）；`eErr` / `bError` / `bValid`
- **边界**：① 需求 > 全部已就绪能力 → `fSupplyMargin < 0` + 信息 `01EA`（缺口可观测）+ **不自动超载投切**（安全侧，头注释声明）；② 数组访问一律 `<= DL_UNIT_MAX` 双闸；③ 轮值组合调用 `FB_DL_DutyStandbyRotation` 思想**内联简化实现**（Process→Level 0 组合调用合法，直接调用亦可，二选一在头注释声明）；④ 反馈矛盾（命令 TRUE 反馈 FALSE 超 `tStartFbDelay := T#10S`）→ 该台故障 `0324` + 剔除轮值池；⑤ ELSE 兜底 `0326`。
- **码位**：信息 `01EA`（供气缺口）/`01EB` 预留 ｜ 故障 `0324`（机组启动失败）/`0325` 预留/`0326` 兜底

### 3.4 批 4 规格（运动同步 + 公用工程，引脚级摘要）

#### #16 `FB_DL_WaferCountAxis` —— 晶圆计数轴
- **VAR_INPUT**：`bEncPulse : BOOL`（编码器脉冲）；`uPulsesPerWafer : UINT := 100`（[脉冲/片] 分频比）；`bCountEnable : BOOL`；`bResetCount : BOOL`
- **VAR_OUTPUT**：`uWaferCount : UDINT`（[片] 计数）；`bWaferIndexPulse : BOOL`（[—] 片位同步单拍脉冲）；`fEstRate : LREAL`（[片/min] 估算节拍率）；`eErr` / `bError` / `bValid`
- **边界**：① `uPulsesPerWafer = 0` → 故障 `02F9`（除零前置闸）；② 计数饱和 4294967295 + 信息 `01DF` 不回绕；③ `bResetCount` 优先级最高；④ 节拍率窗口 `tRateWindow := T#10S`（[ms]），除零走窗口为 0 的构造路径保护；⑤ R_TRIG 首部无条件刷新。
- **码位**：信息 `01DF`（计数饱和）/`01E0` 预留 ｜ 故障 `02F9`（分频比为 0）/`02FA` 预留/`02FB` 兜底

#### #17 `FB_DL_BagFeedDancerSync` —— 制袋供膜摆辊同步（复杂度 H）
- **VAR_INPUT**：`fDancerPosPct : LREAL`（[%] 摆辊位置 0~100，50 = 中位）；`fLineSpeedMmS : LREAL`（[mm/s] 线速前馈源）；`fFeedKp : LREAL := 1.5`（[（mm/s）/%] 摆辊 PI 比例增益）；`fFeedKi : LREAL := 0.2`（[（mm/s）/(%·s)] 积分增益）；`fFeedMaxMmS : LREAL := 500.0`（[mm/s] 供膜速度上限）
- **VAR_OUTPUT**：`fFeedSpMmS : LREAL`（[mm/s] 供膜速度给定 = 线速前馈 + 摆辊 PI 修正）；`bDancerOk : BOOL`（摆辊信号可信）；`bTensionFault : BOOL`；`eErr` / `bError` / `bValid`
- **边界**：① 摆辊位置域外/非有限 → `bDancerOk := FALSE` + 前馈直通（PI 冻结）+ 信息 `01E1`（域外行为显式化，T1-1/T1-2 纪律次源，R11 NtcTempScan 同口径）；② PI 抗饱和：输出触顶时积分冻结；③ `fLineSpeedMmS < 0` → 钳 0 + 信息 `01E1` 复用；④ `fFeedMaxMmS <= 0` → 故障 `02FC`；⑤ 线速为 0 且摆辊持续偏离中位 > `tIdleOffTol := T#5S` → `bTensionFault := TRUE` + 故障 `02FD`（断膜/卡膜疑似）；⑥ 前馈律内联实现（Motion 不得跨库调 FeedforwardComp，头注释「依赖收窄」声明，R11 留档③）。
- **码位**：信息 `01E1`（摆辊/线速已钳位或不可信）/`01E2` 预留 ｜ 故障 `02FC`（速度上限组态非法）/`02FD`（张力疑似故障）/`02FE` 兜底

#### #18 `FB_DL_TankN2BlanketCtrl` —— 储罐氮封双分程
- **VAR_INPUT**：`fTankPressKpa : LREAL`（[kPa] 罐压，表压）；`fPressLoKpa / fPressHiKpa : LREAL`（[kPa] 分程分界：低压补氮 / 高压泄放，默认 0.5 / 2.0）；`fN2ValveOutFb : BOOL`（补氮阀开反馈）；`bEnable : BOOL`
- **VAR_OUTPUT**：`fN2ChargePct : LREAL`（[%] 补氮阀位 0~100，仅低压段有效）；`bVentCmd : BOOL`（[—] 泄放阀开关量，仅高压段）；`eBlanketState : E_DL_N2BlanketState`（五态）；`eErr` / `bError` / `bValid`
- **边界**：① `fPressHiKpa <= fPressLoKpa` → 故障 `0357`（分程倒置）；② 两段**互斥断言**：任一拍 `NOT (fN2ChargePct > 0 AND bVentCmd)` 结构性成立；③ 罐压非有限 → 全关（安全侧）+ 故障 `0357` 复用；④ 分程律内联实现（Device 不得调用 DL_Algo，头注释「依赖收窄」+ 与 `FB_DL_SplitRangeControl` 参数域一致性声明）；⑤ 压力传感器断线超 `tPressLossDelay := T#5S` → 故障 `0358`。
- **码位**：信息 `0184`（分界点附近滞环提示）/`0185` 预留 ｜ 故障 `0357`/`0358`/`0359` 兜底

#### #19 `FB_DL_BoilerThreeElement` —— 锅炉三冲量给水（复杂度 H）
- **VAR_INPUT**：`fDrumLevelPct : LREAL`（[%] 汽包水位）；`fSteamFlowTh : LREAL`（[t/h] 蒸汽流量，前馈①）；`fFeedFlowTh : LREAL`（[t/h] 给水流量，前馈②反馈）；`fLevelSpPct : LREAL := 50.0`（[%] 水位设定）；`fFwdGainSteam : LREAL := 1.0`（[（t/h）/(t/h)] 蒸汽前馈增益）；`bAutoMode : BOOL`
- **VAR_OUTPUT**：`fFeedSpTh : LREAL`（[t/h] 给水流量给定 = PID 主回路 + 双前馈）；`bAuto : BOOL`（实际自动态）；`eErr` / `bError` / `bValid`
- **边界**：① 任一流量/水位非有限 → 保持末次有效给定 + 故障 `0327`（切手动会扰动汽包，与 R22 CrossLimitSelect 同侧策略）；② `bAutoMode` 下降沿 → 无扰切手动（给定冻结为当前值）；③ 手动→自动无扰切换（给定跟踪）；④ 给水/蒸汽流量比超 `fRatioDevMax`（[倍] 常量 2.0）持续确认窗 → 信息 `01EC`（泄漏疑似，R13 三分类诊断范式）；⑤ 前馈律内联（Process 可调 DL_Algo——组合调用 `FB_DL_PidController` 合法，头注释依赖清单声明），PID 参数域 Ti/Td=0 为关闭语义照 T2-5 口径。
- **码位**：信息 `01EC`（流量比异常疑似）/`01ED` 预留 ｜ 故障 `0327`（非有限输入保持末值）/`0328` 预留/`0329` 兜底

#### #20 `FB_DL_HumidityOverride` —— 除湿优先模式仲裁
- **VAR_INPUT**：`fRhPct : LREAL`（[%RH] 实测湿度）；`fRhOverridePct : LREAL := 70.0`（[%RH] 覆盖触发阈值）；`fRhReleasePct : LREAL := 60.0`（[%RH] 释放阈值，迟滞回差）；`bTempCtrlActive : BOOL`（[—] 温控在投）
- **VAR_OUTPUT**：`bOverrideActive : BOOL`（[—] 除湿优先生效）；`eOverrideState : E_DL_HumOverrideState`（四态：`eNormal/eOverride/eReleasePending/eFault`）；`eErr` / `bError` / `bValid`
- **边界**：① `fRhReleasePct >= fRhOverridePct` → 故障 `032A`（迟滞倒置）；② 湿度非有限 → 保持末态 + 故障 `032A` 复用（不静默退出覆盖）；③ 触发/释放带 `tConfirmDelay := T#30S`（[ms] 确认窗防抖振）；④ 覆盖生效期间温度设定值由调用方处理（本件只仲裁不写设定值，头注释职责边界声明）；⑤ ELSE 兜底 `032C`。
- **码位**：信息 `01EE`（覆盖状态切换沿提示）/`01EF` 预留 ｜ 故障 `032A`/`032B` 预留/`032C` 兜底

---

## 4 P0 附加任务：`FB_DL_BatchTransferSeq` 中止时序修复（v1.0.1 → v1.0.2，随批 1 执行）

> R22 终审挂账（ROADMAP §24.1 / BATTLE_REPORT_R22 §4「中等·安全」）：bAbort 路径「先停泵后关阀」仅在单拍赋值次序上成立，泵停与关阀指令同拍发出，缺真实物理时序分隔——泵惰转期间管路残压可能经未关阀位回流。修复规格由总监给出如下，编码专家与批 1 一起执行。

**修复规格（引脚级）**：

1. **新增引脚（保留全部既有引脚契约，破坏性变更零容忍）**：
   - `xCoastStop : BOOL := TRUE` — `// TRUE = 中止走惰转两段化（推荐）/ FALSE = 兼容旧行为单拍中止（仅存量调用保留） / Coast-stop abort sequencing enabled`
   - `tPumpCoastTime : TIME := T#2S` — `// 泵惰转时间 [ms]（默认 2 s）：停泵到关阀的物理时序分隔窗 / Pump coast-down time [ms]`
2. **eAbort 两段化状态机改造**：
   - **段 A（Abort_Coast，第一段）**：abort 沿当拍 → 泵输出使能立即断（`bPumpRun := FALSE`）、**阀位保持不动**（不发关阀指令）、启动惰转计时 `TON` 实例（输入 = 段 A 激活态，PT = tPumpCoastTime，**首部无条件刷新**）。
   - **段 B（Abort_Close，第二段）**：惰转窗满（TON.Q）→ 发关阀指令；阀关到位确认；确认超时 → 新故障码 **`0005_0317`**（中止第二段关阀确认超时）+ `bError`（R45 配对）。
   - **禁令**：两段之间必须有 TON 跨拍物理时序，**禁止单拍内「停泵赋值 + 关阀赋值」连续成立**（机检新增断言：abort 拍不得出现关阀输出置位）。
3. **`xCoastStop = FALSE` 兼容路径**：保留 v1.0.1 单拍行为，头注释标注「不推荐：残压回流风险」。
4. **验收向量（修复后必测，写入头注释修订历史）**：
   - ① abort 触发拍：泵停、阀保持开、关阀输出 = FALSE；
   - ② 惰转窗未满期间：关阀输出恒 FALSE（跨拍验证）；
   - ③ 窗满拍：关阀输出置位；
   - ④ 关阀确认超时：`0317` + `bError` 置位；
   - ⑤ `xCoastStop = FALSE`：回归 v1.0.1 向量。
5. **码位**：新增故障槽 `0005_0317`（本轮 0005 故障段首槽，特批优先分配）；信息码零新增。
6. **版本与注册**：v1.0.1 → **v1.0.2**，重注册（INDEX_REGISTRY version 字段 + line_count + JSONL 重注入 + `0317` 码位登记）；`VERSION.md`（DL_Process）与 `MANUAL_DL_Process.md` 同步修订历史。

---

## 5 派单执行纪律（编码专家必读）

1. **批次顺序 1→4**，批内序号 1→5，每件独立可验收；批 1 含 P0 修复件（先修后编或并修均可，修复件优先级最高）。
2. 每件完成后立即：写 `.st`（文件名 = POU 名）→ 更新对应 `MANUAL_DL_*.md` 接口表 → 登记码位；**五件一批汇总后**由总监侧执行增量机检 + 注册表重注册 + JSONL 注入。
3. 注释样板（§3 头骨架）与码位表（§2）**逐字引用，不得自创格式**（R50 惯例漂移教训）。
4. 依赖纪律见 §3 开头四条硬约束；任何「不得不跨层」的场景必须头注释「依赖收窄」段显式声明，禁止静默内联低层算法复制。
5. 本轮零检索：Stull 湿球公式为公开文献常识；若编码阶段需核对原文，动用检索预算（≤3 次）并补记 `RAW_NOTES_R23.md`。
6. ROADMAP 待办池 346 条 ≥ 30 → 本轮**不补写** ROADMAP（轮末仅勾选已交付条目）。
7. 源矩阵回写预告（轮末执行）：T1-2 行追加焓湿图族 5 件（子族级「焓湿图全参」◐ 深化，状态列不动）；T2-8 行追加 HealthAggregator（待挖项落地）+ OvenDoor/ElectrolyteDosing 次源 2 件；T0 行零回写（M-E5：零检索不虚账）。

---

*ROUND PLAN R23 ｜ 2026-11-17 ｜ 20 件 + P0 修复 1 件 ｜ 码位游标实测与 R22 交接五段全一致 ｜ 检索 0 次*
