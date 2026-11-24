# RAW_NOTES_R82 — 垂直工艺公式域定向采集（2026-11-24 上午轮）

## 0 通道说明（本轮唯一可用）
- `raw.githubusercontent.com` 不可达（HTTP 000，与前几轮一致）。
- GitHub REST `contents` 匿名配额仅约 3 仓，不足以支撑本轮。
- **实际使用**：`codeload.github.com/<owner>/<repo>/tar.gz/refs/heads/<branch>` 整仓下载 + 本地解包抽取，REST 元数据仅 12 次（1 次/仓，用于 `default_branch` + `license.spdx_id` + HEAD sha）。
- **新增杠杆**：GitHub **code search**（`/search/code`，用本机只读 token）——本轮跑 **46 条定向查询**（15 词 × st/TcPOU 双扩展名），命中 **152 个仓**，这是把「repo 关键词搜索命中率≈0」问题解开的关键。写回结果：`_r82_codesearch2.json`。
- **WebSearch 配额使用 0/3**（code search 已足够，未动用）。

## 1 采集仓台账（12 尝试 / 12 下载成功 / 6 有效出料）

| # | 仓 | 默认分支 | license | .st 文件 | 抽取块 | 判定 |
|---|---|---|---|---|---|---|
| 1 | ★FREEZONEX/ia2 | main | Apache-2.0 | 63 | 66 | **绿·有效出料**（process-control 库 50+ FB） |
| 2 | ★midea-ai/SemaPLC | main | MIT | 214 | 223 | **绿·有效出料**（ammonium-nitrates / waste_water_treatment_facility 工艺程序） |
| 3 | ★minkhanh-ng/Tc3_VN001007_VMS | main | MIT | 91 | 2 | **绿·有效出料**（泵组振动高速采样） |
| 4 | ★Dariusz791/Rybno | **dev**（main 404） | NOASSERTION | 170 | 37 | **黄·有效出料**（沼气/沼渣肥料厂：SludgeDosing、DewateringProcess、GranulationProcess、FB_Mixit、FB_DachsControl） |
| 5 | ★gione100/SCR_2ndGen | main | NOASSERTION | 289 | 289 | **黄·有效出料**（SCR DeNOx 全站 IO/参数装载） |
| 6 | ★snackmasta/Building-Automation | main | NOASSERTION | 27 | 112 | **黄·有效出料**（Wastewater Treatment Plant 整厂 PLC） |
| 7 | johannesPettersson80/trust-platform | main | Apache-2.0 | 1060 | 3966 | 绿但不入料：Rust 编译器 conformance 夹具，仅 `examples/OSCAT/filter_backwash_template` 与工艺相关且为 OSCAT 派生（黄） |
| 8 | Dariusz791/Sekwencer | main | NOASSERTION | 38 | 7 | 黄·未取（与 Rybno 同厂同族，语义邻件） |
| 9 | MECTsrl/mect_apps | mect_suite_3.0 | MIT | 813 | 812 | 绿但 0 增量：103 唯一名中绝大多数为 `abs_P/add_P/...` TestSuite 程序 |
| 10 | dweepvira/water-treatment_simulator_CPS | master | unknown | 1 | 1 | 拒收（unknown 许可 + 单文件） |
| 11 | ebbcarbon/Beckhoff_Supervisor | master | unknown | 32 | 0 | 拒收（unknown 许可，且全为 Modbus 读块） |
| 12 | ParagJinjurde0967/PLC-Based-Water-Treatment-Pump-Automation-System-Using-CODESYS | main | unknown | 0 | 0 | 拒收（0 .st + unknown） |

**红区仓**：本轮 code search 结果中未拉取任何 GPL/AGPL/LGPL 仓；`stefanbesler/struckig`（GPL）为 R78 历史记录，本轮未触碰。**红区泄漏 0 行**。

## 2 五个族命中明细（本轮最关键数据）

| 族 | 语义 | 命中 | 其中绿/黄 |
|---|---|---|---|
| F1 | 混凝絮凝沉淀 | **8** | 3 / 5 |
| F2 | 污泥脱水 | **8** | 0 / 8 |
| F3 | 湿式洗涤与催化 | **7** | 2 / 5 |
| F4 | 设备点检维护 | **8** | 6 / 2 |
| F5 | 厌氧沼气 | **9** | 0 / 9 |
| 合计 | | **40** | 12 / 28 |

## 3 registry 空白验证（证明不是重复挖）
以下关键词在 `INDEX_REGISTRY.json`（1530 组件）中命中数 **= 0**：
`Floc / PAM / Lamella / Inclined / Interface(泥位) / SludgeLevel / Cake / FilterPress / Backwash / Packing / MistElim / Reagent / CatalystActivity / CEMS / OilChange / Reorder / MTBF / Methane / Biogas / Holder / Flare / Desulf / HRT / SVI / 斜板`
说明本轮不是「OSCAT 基础数学换皮」，而是真空白区。已存在且**故意避开**（避免语义邻件重复）：`FB_DL_RatioController / CascadePid / SplitRangeControl / Vote2oo3 / FlowCompensate / RuntimeMeter / FlowTotalizer / RulEstimator / BearingVibTrend / SludgeAgeCalc / CoagulantDoseCalc / SettleTimeCalc / CentrifugeSpinSeq / BatchDoseSeq`。

结论：**通用控制层（PID/表决/分程/累计/比例）在册已饱和**，本轮 40 件全部落在「通用件的工艺参数化」外层，即 `干固量折算 / 液气比 / OLR / VFA碱度比 / 泥饼含固率 / 换油三因子` 这一类。

## 4 去重执行
- 名称：40 件逐一比对 registry 1530 名 + 队列既有名 → 0 命中。
- URL：比对队列既有 `source_url` 全量 → 0 命中。
- 指纹：`sha1(规范化名 + 排序输入类型序列)` 与队列既有 `fp` → 0 命中。
- 三项 0 重复（R79 的「只查 registry 不查队列」缺陷本轮已按三项同查修正）。
- 垃圾名：本轮新入队 0 条垃圾；历史遗留 **7 条** TcDUT Base 哈希名（`InputBase_8311D824` 等）已标 `status:"rejected"`，**未删行**。

## 5 合规
- 绿区 12 条：Apache-2.0 ×3 仓 / MIT ×3 仓；改写须保留版权声明并写入 `NOTICE`。
- 黄区 28 条：全部 `license=NOASSERTION`，`reuse_scope=signature_and_parameter_domain_only`，`code_excerpt=null`（**已机器校验：yellow 带 excerpt 条数 = 0**）。
- 红区 0 条。
- unknown 许可 3 仓全部拒收（不入队，仅台账留痕）。

## 6 文件
- 队列：`candidate_queue.jsonl`（159 行；有效 137 = 97 旧 + 40 新；rejected 22）
- 备份：`candidate_queue.jsonl.backup_R82.jsonl`（119 行，动手前）
- 脚本：`_r82_cs2.py`（code search 46 查询）、`_r82_harvest.py`（codeload 下载+签名抽取）、`_r82_queue.py`（去重+入队）
- 原始：`_r82_codesearch.json` / `_r82_codesearch2.json` / `r82/_scan_*.json`
