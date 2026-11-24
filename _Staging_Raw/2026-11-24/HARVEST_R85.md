# HARVEST_R85 · 2026-11-24 夜轮（定向：金属热处理 / 铝挤压阳极氧化 / 压铸 / 粉末冶金 / 酿造制糖）

时间盒 22 分钟。无人值守。执行者：开源供料席（daoli-oss-hunter）。

## 1. 采集量

| 项 | 数 |
|---|---|
| code search 定向查询 | **18 条**（五族 ×3 + 复杂件 2）|
| 检索命中仓（去重后） | **38**（含大量非 ST 噪音仓）|
| 进入元数据/许可判定的仓 | **6** |
| codeload 下载尝试 / 成功 | 6 尝试 / **3 成功**（Industrial-Control 2.78 MB、Extruder 89 KB、ia2 2.37 MB）；lusipad/plcopen 成功下 10.2 MB 但 **0 个 ST 文件**（纯 C++）|
| 抽取 ST 文件数 | 18（Extruder）+ 63（ia2）+ 0 + 0 = **81** |
| **有效出料（进队）** | **5** |
| 无证拒收（零代码入队，落地包已删） | **3 仓** |
| 红区（GPL/AGPL/LGPL） | **0 命中 0 拉取** |

## 2. 逐族语义命中诚实计数（命中 0 即写 0）

| 族 | 定向查询 | 原始命中 | 真实 ST 实件 | **进队** | 说明 |
|---|---|---|---|---|---|
| A 金属热处理（淬火/回火/渗碳/感应） | quench 10｜carburizing **0**｜austenitizing **0** | 10 | **0** | 3（标注 A 支撑） | quench 命中全为 `.md` 数据集与 Python/无关仓；**工艺专属件 0**。进队 3 条是热处理炉**通用支撑件**：`FB_RAMPSOAK8`（八段升温-保温曲线）、`FB_DEADTIME8`（大滞后补偿，淬火槽测温）、`FB_INTERLOCK8`（首出联锁，超温链） |
| B 铝型材挤压 + 阳极氧化 | extrusion press 17｜billet 2｜anodizing **0** | 19 | **1 仓 18 文件** | **0** | 唯一真件 `Eguono22/PLC-Extruder-project`（18 `.st`，含 `FB_ExtrusionMotor.st`）**无许可证 → 整仓拒收**；阳极氧化 0 命中（生态空白） |
| C 压铸 / 重力铸造 | die casting 1081｜diecast **0**｜shot velocity 335 | 1416 | **0** | 1（标注 C 支撑） | 1081/335 全为 LLVM / diesel / openbsd 等 C/C++ 噪音（`FUNCTION_BLOCK` 撞标识符）；**工艺专属件 0**。进队 1 条 `FB_PID_3STEP`（三步式执行器 PID，模温机/高低火位） |
| D 粉末冶金 / 烧结 | sintering **0**｜powder metallurgy 1｜dew point furnace 2 | 3 | **0** | **0** | 3 条命中全非 ST（RungProof/UIUC/LCEReborn）。**生态空白确认** |
| E 酿造 / 制糖 | brewhouse 1｜mash tun 136｜crystallizer 8｜sugar boiling 1 | 146 | **0** | **0** | brewhouse/mash tun 命中集中在 `ZzzJjt/Industrial-Control`（**3601 个 `.md`，ST 代码内嵌文档的数据集仓**）与 `ZzzJjt/IC-100`，**两仓均无许可证 → 拒收**。crystallizer/sugar boiling 同理。**糖化/煮糖专属件 0** |
| X 复杂件（渗层深度/过饱和/压射速度/面密度） | case depth 18528｜supersaturation **0** | 18528 | **0** | **0** | case depth 全为编译器/二进制分析噪音；supersaturation 0。四向**全 0** |

**净结论：本轮 5 条进队件全部是「工艺支撑通用件」，族专属工艺件 0 条。** 与 R82/R83/R84 的垂直工艺空白结论一致，且本轮新增两条实证：① 铝挤压族唯一真件卡在**无许可证**；② 酿造/制糖族唯一命中是 **.md 数据集仓**（不是可编译 ST 工程）。

## 3. 队列终态

- 采集前备份：`candidate_queue.jsonl.backup_R85_pre.jsonl`（210 行）
- 追加（未删任何行）：**+5**，终态 **215 行**
- 有效（有 url+license+defense_gaps 且非 dup_flag）：**200 条**
- 分级：**绿 163 / 黄 52 / 红 0**
- 许可：MIT 118｜NOASSERTION 30｜BSD-3-Clause 28｜MIT+OSCAT(dual) 18｜Apache-2.0 17｜WTFPL 3｜CC0-1.0 1
- 存量 `dup_flag: true` 11 行（未删）
- 队列深度 215 ≥ 200，**本轮不触发红色告警**（按 300 件/日 × 50% 语料占比 ≈ 1.4 天）

## 4. 新增可溯源条目（5 条，全绿 Apache-2.0，均来自 FREEZONEX/ia2）

| name | 语义点 | loc | 族 |
|---|---|---|---|
| FB_RAMPSOAK8 | 八段升温-保温曲线发生器，热处理/回火炉工艺曲线相序 | 228 | A |
| FB_DEADTIME8 | 八阶纯滞后补偿（Smith 预估），大滞后测温回路 | 122 | A |
| FB_INTERLOCK8 | 八路联锁首出记忆，超温/急停链因果定位 | 103 | A |
| FB_PID_3STEP | 三步式（开/关/双向）执行器 PID | 196 | C |
| FB_GAIN_SCHED3 | 三区增益调度 PID（升温段/保温段切换增益表） | 150 | A |

来源：`https://github.com/FREEZONEX/ia2`（Apache-2.0，8 star，IEC 61131-3 IDE+runtime，`library/process-control/pous/`，全库 40 个 FB，仅取 5 个未撞邻件者）。

## 5. 合规校验

- 红区泄漏：**0 行**（本轮无 GPL/AGPL/LGPL 仓进入下载队列）
- 黄区：本轮新增黄区 **0 条**
- `unknown`/无证拒收：**3 仓**（`ZzzJjt/Industrial-Control`、`ZzzJjt/IC-100`、`Eguono22/PLC-Extruder-project`）——**零代码入队**，且已**删除本地 tar.gz 与抽取文本**，仅保留计数证据（避免"落地即泄漏"争议）
- 许可证可判定率：进队件 5/5 = **100%**
- 所有进队件均写明 ≥2 条 `defense_gaps`

## 6. 通道与工具问题

1. **code search 的 `FUNCTION_BLOCK` 语法 token 对多义词失效**：`die casting`(1081)、`shot velocity`(335)、`case depth`(18528) 这类查询被 C/C++ 标识符与自然语言注释淹没，top-20 内 0 个 ST。有效做法是把工艺词换成**强工艺复合词**（`quench`、`crystallizer`）。
2. **`ZzzJjt/Industrial-Control` 是 .md 数据集仓**：3601 个 `.md` 内嵌 ST 片段，code search 会命中但 codeload 抽 `.st` 得 0。凡命中仓 `size` 大而 ST 抽 0，应立刻看后缀分布再决定是否深挖。
3. `lusipad/plcopen`（Apache-2.0，87 MB）实为 **C++ 运动控制库**，0 个 ST 文件——按 ST 口径为无效仓，勿再重踩。
4. 工具 `oss_harvest.py` 本轮未使用（改用自写 `_r85_cs.py` / `_r85_dl.py` / `_r85_enqueue.py`，规避其 `--search` 覆盖 manifest 缺陷）。codeload `main` 分支优先、`master` 兜底可稳定下载。
5. REST 元数据仅耗 **6 次**，code search 18 次（6.5 s 间隔，未触 10/min 限）。

## 7. 建议

1. **A/C/E 三族专属实件在开源 ST 生态不存在**（本轮再次实证），下轮停止对这三族做"找现成件"，直接转入 clean-room 公式件（`r85_targets.json` 中 40 个候选名已与 registry 去重，可直接投产）。
2. 铝挤压族要出料，只能靠 `Eguono22/PLC-Extruder-project` 这类无证仓 → 建议走**人工许可证裁定流程**（联系作者 / 判断是否可判 BSD-3），否则永久空白。
3. `ZzzJjt/Industrial-Control` 作为**数据集仓**（含热处理/结晶/煮糖工艺语料）可作 knowledge 源提炼 `EDGE_CASE_KB.md` 三元组，但**不得**进入代码队列。
