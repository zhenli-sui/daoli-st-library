# HARVEST R75（2026-11-23）· oss_harvest 定向真采集轮（追加式）

> 结论先行：**净增 21 条**（SRCI×13 + 手工抽签×4 + BeckhoffHttpClient×4），队列终态 **50 条**（绿区 MIT 49 / 黄区 WTFPL 1 / 红区 0 / unknown 0）。全部仓与许可证均来自真实 GitHub API 响应。

## 1 实跑命令与每仓响应

前置核查：`python C:\Library\_tools\oss_harvest.py --help` → **无 `--exclude` 参数**（维持 R74 记录），改用定向 `--repo` 逐个采。

| # | 命令 | API 响应 | 结果 |
|---|---|---|---|
| 0 | `curl api.github.com/rate_limit` | core 60/60, search 10/10 | 额度满开局 |
| 1 | `--repo ThorstenBrach/SRCI_CLIENT_PLC`（首次误用 `--max-files 12`） | spdx=MIT stars=84，20 listed / 20 fetched / 0 failed | 工具按默认 20 采（见 §3 缺陷①），超预算 8 件，如实保留未回删 |
| 2 | `--repo fisothemes/TwinCat-Dynamic-Collections --max-files-per-repo 12` | spdx=MIT stars=89，12 listed / 12 fetched / 0 failed，added=0 | 前 12 文件按树序全为 `T_*` ALIAS 声明，签名正则零命中；手工定向拉 4 个核心文件补救 |
| 3 | `--repo fbarresi/BeckhoffHttpClient --max-files-per-repo 9` | spdx=MIT stars=83，7 listed / 7 fetched / 0 failed | added=4（HttpClient 核心 FB loc=94 + 3 件版本元信息函数） |

候选仓搜索（search API 3 次，均 200 OK）：`topic:packml`（15 total）、`topic:codesys`（271 total）、`topic:twincat`（339 total）。手工补拉：`contents` API 4 次（Dynamic Collections），全程 0 次 403/422，终态 core 余量 ≈ 12。

## 2 仓筛选与排除（全部来自真实 API 元数据）

| 仓 | spdx（API 实测） | 处置 |
|---|---|---|
| ThorstenBrach/SRCI_CLIENT_PLC | MIT | ✔ 采（989 个 .st，SRCI 机器人指令语义密集） |
| fisothemes/TwinCat-Dynamic-Collections | MIT | ✔ 采（86 ST + 59 TcPOU，动态集合语义） |
| fbarresi/BeckhoffHttpClient | MIT | ✔ 采（9 ST，HTTP/JSON 协议层） |
| stefandreyer/CODESYS-MQTT | MIT | ✘ 树检弃采：35 文件无任何 ST 文本，代码全在二进制 `.library/.project` 内 |
| MichielVanwelsenaere/HomeAutomation.CoDeSys3 | MIT | ✘ 树检弃采：180 文件仅 1 个 .st，其余为二进制工程 |
| peacefighter1996/Open.PackML | MIT | ✘ 树检弃采：55 个 .cs 纯 C#，无 ST |
| stefanbesler/struckig | **GPL-3.0（红区）** | ✘ 仅记录存在，零文件拉取，零语义笔记（ruckig 运动规划器 ST 移植，下轮如需只读思想） |

**禁采名单遵守确认**：本轮 0 仓与 R73/R74 已采仓（brOscatLib / iec-oscat-mirror / AixOCAT / TcOpenGroup-TcOpen / OttoMeister PID / PLCnext-Community 相关）重叠。

## 3 工具缺陷（不修工具，仅记录）

1. **`--max-files` 参数失效**：`harvest_repo()` 第 270 行实际传 `a.max_files_per_repo`，`--max-files` 被静默忽略 → SRCI 按默认 20 采，超出本轮 12 件预算（8 件超采已入队，未回删以免重演 R74 误删事故）。
2. **垃圾名抽取缺陷复现**（R74 `VAR_INPUT` 同类）：新增 20 条中 7 条名为 `METHOD`×2 / `EXTENDS`×5，其中含重复 fp `441a518d`（×2）与 `ddc93c79`（×3）→ 备份后按名精准剔除 7 条（`queue.backup_R75.jsonl` 留痕），剔除前断言旧段 29 条无该名。
3. **文件选择无偏移参数**：Dynamic Collections 按树序抓到的全是 ALIAS 声明 → added=0，手工 `contents` API 补拉 4 个 FB/FUNCTION 文件（留存 `_r75/`）。
4. 工具去重仍只比对指纹文件不比对队列既有条目（R74 缺陷②未修复）；本轮手工入队前对 registry 1252 件名 + 队列全量名 + 指纹文件 54 条做了三道复核。

## 4 净增明细与队列终态

- 净增 **21 条**：SRCI_CLIENT_PLC ×13（LogLevelEnum / AreaTypeEnum / SequenceFlagEnum / MessageLevelEnum / AbortingModeEnum / ProcessingModeEnum / ReturnMode / CreateServerLogParCmd / ReadSafeReferencePositionParCmd / SafeReferencingOutCmd / ReadSafeReferencePositionOutCmd / ReadAnalogOutputParCmd / MoveDirectCamOutCmd，13/13 对 registry 无撞名）＋ 手工抽签 ×4（FB_Hash_Map / FB_Tree_Map / F_Murmur3_Hash / F_Malloc_Generic）＋ BeckhoffHttpClient ×4（HttpClient / F_GetCompany / F_GetTitle / F_GetVersion）。
- 队列终态 **50 条**：绿区（MIT）**49** ｜ 黄区（WTFPL）**1** ｜ 红区 **0** ｜ unknown **0**。
- 本轮 21 条全部含任务要求的 `name/repo/url/license/zone/borrow_point/round=R75` 字段（工具自动入队 17 条已回填）。
- 队列深度告警：50 < 200 → **红色告警**维持（按 300 件/日 × 50% 语料占比估算 ≈ 0.3 天），但本轮 21/21 为真实增量源（R74 净增 0 的局面已扭转）。

## 5 前 10 条候选映射（供 PLC 编码专家取件）

| # | 原名 | 语义 | 建议道莅命名 |
|---|---|---|---|
| 1 | FB_Hash_Map | 闭式寻址哈希映射（负载因子 0.75、不可变键值视图） | FB_DL_HashMapStore |
| 2 | FB_Tree_Map | 迭代式 AVL 有序映射（四遍历序枚举） | FB_DL_AvlSortedMap |
| 3 | F_Murmur3_Hash | ANY 泛型 Murmur3 32 位散列 | FC_DL_Murmur3HashCalc |
| 4 | F_Malloc_Generic | 泛型动态分配（bSuccess/Error 双通道） | FC_DL_GenericMemAlloc |
| 5 | HttpClient | TwinCAT HTTP 客户端 + JSON 转换 | FB_DL_HttpClientCmd |
| 6 | SafeReferencingOutCmd | 安全回参考点指令（SRCI 使能/完成语义） | FB_DL_SafeRefHomeCmd |
| 7 | ReadSafeReferencePositionParCmd / OutCmd | 安全参考位读参/读出指令对 | FB_DL_SafeRefPosReadCmd |
| 8 | MoveDirectCamOutCmd | 凸轮直移指令（CamMode 选择域） | FB_DL_CamDirectMoveCmd |
| 9 | CreateServerLogParCmd / ReadServerLog | 机器人控制器日志读取指令族 | FB_DL_ServerLogReadCmd |
| 10 | ReadAnalogOutputParCmd | 模拟量输出参数回读指令 | FB_DL_AnalogOutParReadCmd |

（LogLevelEnum / MessageLevelEnum / AbortingModeEnum / ReturnMode 等枚举域件建议随 #6/#9 取件时一并借鉴参数域，不单独立件。）

## 6 给总监的 3 条建议

1. **下一批优先挖**：`Aliazzzz/Applied-Design-Patterns-in-CODESYS-V3`（Unlicense，100 stars，纯 ST 设计模式，需先确认 Unlicense 归绿区口径）；`johannesPettersson80/trust-platform`（Apache-2.0，IEC 61131-3 ST 工具套件）；`bengeisler/TcLog`（MIT，日志 FB 族）。三仓均需先树检确认为纯文本 ST。
2. **修工具三缺陷**：①`harvest_repo` 第 270 行 `a.max_files_per_repo` 改为 `min(a.max_files, a.max_files_per_repo)` 并让 `--max-files` 生效；②文件选择加 `--offset`/`--include` 支持（避免再撞 ALIAS-only 段）；③去重比对队列全量既有条目（连续三轮同因）。
3. **SRCI 是富矿**：989 个 ST 文件本轮只采 20，运动指令族（Move* / Jog* / Search*）、帧换算（Frame / Ori / CircPlane）语义密集且全部 MIT，建议 R76 起专项深挖（配 `--include MC_` 过滤更高效）。

## 7 合规声明

- 红区泄漏：**0 行**。struckig(GPL-3.0) 仅在台账记录元数据，未拉取任何文件。
- 黄区：无新增。本轮 21 条全部 MIT 绿区。
- unknown 许可拒收：0（候选搜索阶段已过滤 NONE/NOASSERTION/LGPL/GPL 命中，如 XzuluX/EtherCAT.NET LGPL-3.0、TcUnit NOASSERTION、runtimevic NONE、feecat/OpenSML GPL-3.0 均未采）。
- 全部仓/许可证/星标数据来自真实 API 响应，零虚构。
