# REGISTRY_JSONL_R13 ｜ R13 注册与语料收口留痕

- 执行人：道莅PLC编程专家（兜底模式，注册与语料收口线）
- 日期：2026-11-16
- 依据：FINAL_REVIEW_R13_A.md / _B.md / _C.md（18/18 PASS）；ROUND_PLAN_R13.md §1.5 来源组标签表；R12 同口径脚本 `register_and_jsonl_r12.py` → 本轮 `register_and_jsonl_r13.py`
- 纪律遵守：只改动 INDEX_REGISTRY.json / daoli_st_sft_dataset.jsonl / ROADMAP.md / SOURCE_HUNTING_MATRIX.md / 本留痕与脚本；未触碰 VERSION / MANUAL / README / CHANGELOG / EVOLUTION_LOG / SHOWCASE（另由文档代理负责）

---

## 1 备份

| 对象 | 备份路径 | 大小 |
|---|---|---|
| INDEX_REGISTRY.json | `C:\Library\INDEX_REGISTRY.json.backup_R13` | 86,004 B |
| daoli_st_sft_dataset.jsonl | `C:\Library\_AI_Training_Dataset\daoli_st_sft_dataset.jsonl.backup_R13` | 4,132,886 B |

## 2 注册表 186 → 204（v2.1.0 → v2.2.0）

- 新增 18 条，字段结构沿用既有条目：name / category / type / file_path / function_tags / complexity / version / registered_at / line_count / code_segment / source
- function_tags 首位为来源组标签（ROUND_PLAN_R13.md §1.5），与 meta 既有标签合并去重
- code_segment 由终审报告码位构建，并与源码实扫集合逐件互验（16 条实现件全部一致；2 件契约件记「无（接口契约不发布故障码，码位由实现块承担）」，与 `I_DL_TowerLight` 先例同风格）
- line_count 为 `wc -l` 口径实测；18 件合计 **7,949 行**
- last_updated = 2026-11-16T00:34:03+08:00

### 2.1 新增 18 条清单

| # | 组件 | 子库 | 类型 | 版本 | 行数 | 来源组标签 |
|---|---|---|---|---|---|---|
| 1 | I_DL_DeviceHealth | DL_Device | IF | 1.0.0 | 146 | namur-ne107 |
| 2 | I_DL_PowerMeter | DL_Device | IF | 1.0.0 | 142 | namur-ne107 + forge-devicereader |
| 3 | FB_DL_ModbusPowerMeter | DL_Device | FB | **1.0.1** | 998 | namur-ne107 + modbus-meter |
| 4 | FB_DL_ValveStictionDetect | DL_Device | FB | **1.0.1** | 735 | namur-ne107 + stiction-diag |
| 5 | FB_DL_AhuDamperStuckDiag | DL_Device | FB | **1.0.1** | 615 | rockwell-aoi + namur-ne107 |
| 6 | FB_DL_PumpCavitationGuard | DL_Device | FB | **1.0.1** | 559 | namur-ne107 + lbp-basic-process |
| 7 | FC_DL_BitArrayRotate | DL_Base | FC | 1.0.0 | 252 | lgf-bitlogic |
| 8 | FC_DL_MaskCompare | DL_Base | FC | 1.0.0 | 191 | lgf-bitlogic + lgf-comparator |
| 9 | FC_DL_Crc8 | DL_MathData | FC | 1.0.0 | 233 | lgf-datahandling + oscat-network |
| 10 | FC_DL_StringToLReal | DL_MathData | FC | 1.0.0 | 417 | lgf-datahandling |
| 11 | FC_DL_StringFixedField | DL_MathData | FC | 1.0.0 | 245 | lgf-datahandling |
| 12 | FC_DL_Matrix3Inverse | DL_MathData | FC | **1.0.1** | 291 | lgf-math |
| 13 | FB_DL_FoulingResistanceEstimator | DL_Algo | FB | 1.0.0 | 558 | oscat-building + heat-transfer |
| 14 | FB_DL_PassiveHomingMonitor | DL_Motion | FB | **1.0.1** | 464 | plcopen-motion |
| 15 | FB_DL_CapperTorqueTrend | DL_Process | FB | **1.0.1** | 617 | rockwell-aoi + lbp-process |
| 16 | FB_DL_EscHeLeakCheck | DL_Process | FB | **1.0.1** | 564 | semiconductor-esc |
| 17 | FB_DL_ChamberSeasoningTrack | DL_Process | FB | 1.0.0 | 435 | semiconductor-esc + isa-88 |
| 18 | FB_DL_ReactorJacketDeltaT | DL_Process | FB | 1.0.0 | 487 | lbp-process + isa-88 |

版本与终审报告逐件核对一致（v1.0.1 共 8 件：ModbusPowerMeter / ValveStictionDetect / AhuDamperStuckDiag / PumpCavitationGuard / Matrix3Inverse / PassiveHomingMonitor / CapperTorqueTrend / EscHeLeakCheck）。

## 3 JSONL 186 → 204（字节级）

### 3.1 追加 18 条

- instruction / architecture_thought 取自 `_Staging_Raw\2026-11-15\meta\<Name>.json`（18 件 meta 两字段齐备、长度 286~534 字符，无过简需补写项）
- output 一律 bytes 级读取对应 `.st` 后 `decode('utf-8')` 注入，**禁止手抄**

### 3.2 存量再同步 20 条（bytes 级重注入 output）

| 类别 | 件 | 说明 |
|---|---|---|
| 本轮点名（2） | FB_DL_InterlockMatrix、FB_DL_AgvDockingHandshake | 本轮终审与 R39 修复改动源码（均升 v1.0.1），JSONL 替换为当前 .st 字节级内容 |
| 历史遗留漂移（18） | FC_DL_GrayToBinary、FB_DL_MovingAverage、FB_DL_LifoStack、FB_DL_MedianFilter、FB_DL_SignalStatistics、FB_DL_SplitRangeControl、FB_DL_VacuumEjector、FB_DL_StarDeltaMotor、FB_DL_VfdGeneric、FB_DL_AnalogValve、FB_DL_ThreePointValve、FB_DL_AxisHomingSeq、FB_DL_OccScheduleWindow、FB_DL_RampSoakProfile、FB_DL_SerialScanner、FB_DL_GuardLockDoor、FB_DL_BatchDosingControl、FB_DL_SoftLimitGuard | 非本轮点名；逐一 diff 抽查核实：均为注释级清理（R39/R40 修复移除孤立 `;` 语句行、`...` 省略号润色等），**磁盘 .st 为终审后真值**，JSONL 为旧快照；按「output 与 .st 字节一致」验收口径重注入，注册字段零改动 |

### 3.3 校验结果

- JSONL 204 行、每行合法 JSON、键集合恒为 `{instruction, architecture_thought, output}`
- 全量 sha256 逐件比对：**204/204 一致，0 漂移**（脚本口径：bytes 注入 → `encode('utf-8')` 回比）
- 组件归属覆盖 204/204（FUNCTION/FUNCTION_BLOCK/INTERFACE 前缀归属 + 最长名消歧）
- 磁盘 .st 计数与 registry counts 一致：DL_Base 40 / DL_MathData 42 / DL_Algo 28 / DL_Device 50 / DL_Motion 18 / DL_Process 26

## 4 ROADMAP.md 变更摘要

1. **勾选 9 条既有待办**（`- [ ]` → `- [x]`，行尾按 R12 风格加「**R13 交付** + 关键技术点 + 实测行数 + 缺陷修复号」注记）：§4 `I_DL_PowerMeter` & `FB_DL_ModbusPowerMeter`（一行两件）；§19.3 EscHeLeakCheck、ChamberSeasoningTrack；§19.4 CapperTorqueTrend；§19.5 AhuDamperStuckDiag；§19.6 ValveStictionDetect、PumpCavitationGuard、ReactorJacketDeltaT。**`DL_Device` 电表契约件就此收尾。**
2. **新增 §二十「R13 新增」**：9 件既有清单无对应条目（I_DL_DeviceHealth、BitArrayRotate、MaskCompare、Crc8、StringToLReal、StringFixedField、Matrix3Inverse、FoulingResistanceEstimator、PassiveHomingMonitor）按既有格式登记并直接勾选 + 收口统计段（18 件 7,949 行、registry 204、缺陷账、JSONL 同步账）。
3. **新增 §二十一「行业方向待办池 R13 扩容」**：+30 条（锂电 5 / 光伏 5 / 半导体 5 / 包装 5 / 暖通 5 / 过程控制 5），全部标注 `[R13 新增]`，逐条 grep 查重与既有 316 条待办及全库 204 个 POU 命中 0（唯一候选 `FB_DL_TrackerWindStow` 与 L239 既有条目撞名，已替换为 `FB_DL_PvSoilingLossRate` 后复核为 0）。
4. **「下一批重点（Round 14）」段**：① R39 规则豁免机制改进（本轮 3 处误报：复位判据文本先于前置块 / 无故障态件按有故障态口径检查，需规则层区分，不为变绿硬改语义）；② P0 编译验证第十三次提醒（本机无 CODESYS/TwinCAT，替代验证方案已按 R12 承诺落文档，风险清单持续挂账）；③ 候选组件方向（R13 池 P1 十七条首批 + R13 观察项承接）。
5. 同步刷新活状态 bullet：批处理进度 204 / 100、AI 训练集同步状态（204 条三方一致、再同步 20 件）。

## 5 SOURCE_HUNTING_MATRIX.md 第 5 节回写摘要

- 新增「**R13 一行**」配额结算（4 T2 + 2 T1 + 2 规范/自研线）
- **T2-1 LGF Bit Logic**：◐ → 追加 BitArrayRotate / MaskCompare，备注补 R13 批量层扩族（3000 组位守恒对拍）
- **T2-1 LGF Data Handling**：◐ → 追加 Crc8 / StringToLReal / StringFixedField，备注补 R13 两子族收口 + 校验族（Crc8 标注 T1-3 次源不重复记账）
- **T2-1 LGF Math**：◐ → 追加 Matrix3Inverse，**勘误 M-E4 开族**（Matrix 子族，500 组 A×A⁻¹≈I 对拍）并新增 M-E4 勘误表行
- **T2-8 ISA-88 / ISA-18.2 / NE107**：◐ → 追加 DeviceHealth / PowerMeter / ModbusPowerMeter / ValveStictionDetect / AhuDamperStuckDiag / PumpCavitationGuard 六件 NE107 语言落地（本行最大单轮扩族），备注补六件健康语义分工
- **T2-6 Rockwell AOI**：◐ → 追加 AhuDamperStuckDiag / CapperTorqueTrend（借三分类诊断语义，主源分工注明）
- **T2-2 LBP**：◐ → 追加 ReactorJacketDeltaT / PumpCavitationGuard（三段分层骨架借用，NE107 主源记 T2-8 不重复记账）
- **T1-2 OSCAT Building**：◐ → 追加 FoulingResistanceEstimator（换热健康线，heat-transfer 双源标注）
- **T1-6 PLCopen Motion**：◐ → 追加 PassiveHomingMonitor（R8 留扩产的被动回零就此收口）
- **新增行「半导体 ESC 自研（工艺专家 clean-room）」**：◐ 开线，EscHeLeakCheck / ChamberSeasoningTrack 两件
- 未触碰任何已收口组的存量语义；「待挖」描述均按 R13 起的粒度纪律拆分

## 6 收口校验终态

| 项 | 结果 |
|---|---|
| registry JSON 合法 | ✔（total_components=204，version 2.2.0，counts 六子库与磁盘一致） |
| 既有 186 条注册字段零改动 | ✔（写入前后快照逐字节比对） |
| JSONL 行数 | 204（186 存量 + 18 新增） |
| JSONL 每行合法 JSON | ✔ 204/204 |
| sha256 output vs .st | ✔ **204/204 一致**，0 漂移 |
| 磁盘 .st 计数 | 40/42/28/50/18/26 = 204 ✔ |
| ROADMAP | 勾选 9 条 + 新登记 9 件 + 池子 30 条（查重 0 冲突）+ Round 14 段 ✔ |
| SOURCE_HUNTING_MATRIX | 10 行回写 + 1 新行（ESC 自研）+ M-E4 ✔ |
| 脚本与结果 JSON | `register_and_jsonl_r13.py`、`r13_register_result.json`（本目录） |
