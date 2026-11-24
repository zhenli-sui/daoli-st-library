# HARVEST R81 — 开源供料席（2026-11-24）

通道：`codeload.github.com/<owner>/<repo>/tar.gz/refs/heads/{main|master}` 整仓下载本地抽取（零 REST 配额）。
落盘：`_Staging_Raw/2026-11-24/r81/*.tgz` → `x_*/`。raw.githubusercontent 仍不可达（R79 结论延续），本轮 0 次 REST 调用。

## 1. 采集量
| 项 | 值 |
|---|---|
| 仓尝试 / 下载成功 | 6 / 6（0 次 403、0 次 422；1 次 404 分支名自纠 main→master）|
| 含文本 ST 有效仓 | 4（TcControl、dual-axis 为 MIT 有效仓但 0 增量）|
| 扫描 ST 文件 / 抽取 POU 声明 | 69 / 61 |
| 净增入队 | **+12（全绿区 MIT）**，拒收 0，重复 0 |

## 2. 终态分布
队列 **119 行 / 有效 104 条**：**绿 82 / 黄 22 / 红 0**（15 条 rejected 保留未删行）。
许可证可判定率 100%（104/104）；fp 唯一 104/104；缺 defense_gaps 条目 0。
队列深度 **104 << 200 → 红色告警**；按 300 件/日 × 50% 语料占比，仅够 **0.7 天**。

## 3. 红区零拉取声明
本轮 6 仓逐一核 LICENSE：MIT×5 + Apache-2.0×1，**无 GPL/AGPL/LGPL 仓尝试，红区代码 0 行入队**。
（对照：R80 的 FluidPyPLC GPL-3.0 仍未复采。）

## 4. R80 存量核销
R80 的 15 条绿区候选（队列末 15 行，实际位于索引 92~106，非任务书所述 15~29）**registry 命中 0 → 全部仍在库外**。
编码席已认领 4 条语义：`FB_DL_CupFillSealIndexer`(FB_Dolum)、`FB_DL_FillPreactSelfLearn`(FB_Dolum#PREACT)、
`FB_DL_AsrsSlotAllocSeq`(FB_Asrs)、`FB_DL_MeasureInputLatch`(MC_MeasuringInputFB) → 台账标 `consumed`（队列 status 未改，仍可复取）。

## 5. 缺口说明
- 空压站 / 真空吸取 / 清洗 CIP-SIP 整机：GitHub 短查询 `vacuum+ejector+plc`、`compressor+station+plc+structured`、`shuttle+warehouse+plc` **命中 0 仓**（长查询全词 AND 依旧 0）。
- CIP 本轮由 `CGainsWorks/plc-cip-batch-control` 补 4 条判据/状态机层；但**清洗球/喷淋覆盖率、SIP 蒸汽灭菌 F0 值** 仍 0 命中 → 建议 clean-room 公式自研。
- 立库方向本轮大幅补齐（堆垛机/货位/巷道/报文/工时），**多机同巷道交通管制**仍为空白（开源仅有单机版）。
- 未做：GitHub code search（需 PAT）；ORG 级 `PLCnext-Community` 查询上轮 422，未复试。

## 6. 溯源
12 条 100% 具 `source_url + license + commit 标记`；commit_sha 为 codeload 通道不可见，统一标 `refs@HEAD (codeload tar.gz)`。
备份：`candidate_queue.jsonl.backup_R81.jsonl`（119 行前 107 行原样留存，零删行）。
