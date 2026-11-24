# RAW_NOTES R83 —— 开源供料席（2026-11-24 下午轮）

## 1. 本轮通道实测（先量通道再采集）

| 通道 | 结果 | 结论 |
|---|---|---|
| `api.github.com`（匿名） | 200，core 60/h、search 10/min | 元数据可用 |
| `raw.githubusercontent.com` | **000（不可达）** | 弃用（与 R79–R82 一致） |
| `codeload.github.com` tar.gz | 200 | **主通道**，零 REST 配额 |
| `api.github.com/search/code`（带只读 token） | 200 | 本轮主检索通道，10/min |

## 2. 检索式与命中（3 轮，共 34 条查询）

轮 1（`extension:st` 族词 12 条）：**`.st` 与 Smalltalk 撞名**，命中大量 pharo/squeak 噪声（pharo-project/pharo、dynabook 等），有效仓仅 2 个。
轮 2（ST 语法 token 14 条，`"FUNCTION_BLOCK" <工艺词>`）：噪声大幅下降，有效仓 6 个。
轮 3（补 F2/F3 8 条 + 仓库级 search 6 条）：**F2/F3 在 GitHub ST 生态近乎不存在**（见 §5）。

## 3. 尝试清单与许可证裁定（14 尝试 → 4 有效出料）

| 仓库 | stars | spdx | tier | ST 文件 | 解析块 | 裁定 |
|---|---|---|---|---|---|---|
| ★`chetto1983/Twinova` | 3.8MB | Apache-2.0 | 绿 | 88 | 62→8 唯一 | **采纳 8**，输送元件运动学（皮带/辊道/链式移载/顶升平移/挡停/转盘） |
| ★`pcdshub/lcls-twincat-vacuum-sim` (SLAC) | 48 | NOASSERTION | 绿（人工裁定） | 48 | 48 | **采纳 33**，真空系统：MKS 真空计量程换算/涡轮泵/粗抽泵/腔室压力 |
| ★`Q3son/Concurso_PLC` | 6.3MB | MIT | 绿 | 26 | 21→6 唯一 | **采纳 6**，色彩分拣（WheelSorter/Pusher/FeederStation/ColorDiverter/ColorFromSensors/MachiningCenter） |
| `malgaroshy-maker/factoryforge` | 10.7MB | MIT | 绿 | 40 | 42→0 | 仅 3 个字转换族函数，与在册 `FC_DL_WordsToDword` 族语义重复，全拒 |
| `Open-Industry-Project/Open-Industry-Project` | 63MB | MIT | 绿 | 3 | 0 | 浏览器仿真器，无 IEC 块 |
| `huuhuannt1998/CPSForge` | 5.7MB | MIT | 绿 | 27 | 0 | 仅有 PROGRAM（OpenPLC 示例），无 FB/FC |
| `oaiz-io/polint` | 106MB | MIT | 绿 | 0 | 0 | ST 解析器（Rust），无 ST 资产 |
| `DeLuAle/FRAMEWORK_PARSER` | 9.2MB | **无 LICENSE** | 拒 | 835 | 11 | S7-1500 真实产线导出（`34_Area04/50_Tracking`），**无证按铁律拒收**，仅记「跟踪域按区位分块导出」的目录组织思想 |
| `warmjademe/plc_generation_empirical_study` | 13.9MB | 无 LICENSE | 拒 | 4397 | 60 | 安全模式基准集（四级优先/2oo3/旁路许可），无证拒收 |
| `Juunary/body_measure` | 2.3MB | 无 LICENSE | 拒 | 5 | 10 | OpenPLC 工位计数，无证拒收 |
| `yatharthMogra/Mini-Conveyors-Automation` | 0.4MB | 无 LICENSE | 拒 | 10 | 11 | FB_Conveyor/Divert/JamDetection——内容对路但**无证，拒** |
| `enesuslu15/Advanced-PLC-Dyeing-System` | 0.03MB | 无 LICENSE | 拒 | 1 | 0 | **唯一的纺织染整仓**，无证 + 无块，拒 |
| `rmoorewrs/sorter_demo` | 0.3MB | 无 LICENSE | 拒 | 0 | 0 | 拒 |
| `feleastefan05-ai/PLC_Automation_Sorting_Station` | 4.4MB | 无 LICENSE | 拒 | 1 | 0 | 拒 |

**红区（GPL/AGPL/LGPL）本轮 0 个命中，零拉取。**

## 4. 许可证裁定依据（唯一一条人工裁定）

`pcdshub/lcls-twincat-vacuum-sim`：GitHub 标 `NOASSERTION`，但仓内 LICENSE 正文为 SLAC/Stanford 三条款 BSD
（"Redistribution and use in source and binary forms, with or without modification, are permitted provided that..."）。
按「许可证可判定」原则裁定为 **BSD-3-Clause 绿区**，`license_basis` 已写入 manifest 与每个候选的 `note`。

其余 6 个无 LICENSE 仓（含唯一的染整仓、835 文件的 S7 跟踪工程）一律 `unknown` → **拒收，零代码入队**。

## 5. 五族语义命中（诚实计数）

| 族 | 命中 | 说明 |
|---|---|---|
| F1 印刷包装 | **0** | 4 条定向查询（web guide / flexo / anilox / ink / register）有效命中全 0；在册已饱和于 film/tension/carton/shrink/wrap |
| F2 纺织染整 | **0** | 6 条查询；GitHub 全站仅 `enesuslu15/Advanced-PLC-Dyeing-System` 1 仓且无证 → **实证空白** |
| F3 表面处理（含真空镀膜支撑） | 28 | 电镀专属 **0**（plating/anodize/rectifier/cathode 查询全 0）；28 件全部为真空镀膜线支撑（真空计/泵组/腔室） |
| F4 物料输送分拣 | 11 | 色彩分拣站 6 + 输送元件运动学 5（Twinova 的 8 个 behaviour 中 5 个通过语义闸） |
| F5 仓储立库周边 | **0** | shuttle/stacker/stretch wrapper 查询 0 有效仓；R81 已把 ASRS 打满 |
| 未归类（通用） | 2 | ST_MechPump / ST_Volume（真空系统数据契约） |

## 6. 拒收明细（139 条，零删行）

| 拒因 | 条数 |
|---|---|
| fingerprint-dup（同名块跨文件重复：Twinova 54 + factoryforge 39 等） | 54 |
| semantic-dup（字转换族 / 报警管理者 / FIFO 四件 / KPI 聚合） | 42 |
| declaration-only-thin（<3 字段的器件数据壳） | 21 |
| no-increment（无逻辑且无可守缺口） | 8 |
| unknown-license（整仓拒，含候选数） | 7 仓 |

## 7. 存量队列重复（第 3 条任务）

扫描既有 159 行，发现 **11 行**（同 name 或同 fp）为历史重复 → 标 `dup_flag=true` + `dup_reason`，
原文**逐行追加**到 `C:\Library\_Staging_Raw\queue_dup_backup_R83.jsonl`（11 行），**未删任何行**。

## 8. 产物路径

- 队列：`C:\Library\_Staging_Raw\2026-11-24\candidate_queue.jsonl`（159 → **200 行**）
- 采前备份：`candidate_queue.jsonl.backup_R83_pre.jsonl`
- 重复备份：`C:\Library\_Staging_Raw\queue_dup_backup_R83.jsonl`
- 采集清单：`C:\Library\_Staging_Raw\_harvest_manifest.json`（R83 节 + 逐仓裁定；旧轮 repos 已合并保留）
- 原始抓取记录：`_Staging_Raw\2026-11-24\r83\*.json`（每仓一块体快照，含 body 片段供缺口复核）
- 脚本：`_r83_harvest.py` / `_r83_queue.py` / `_r83_write.py` / `_r83_cs{,2,3}.py`
