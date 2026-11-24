# HARVEST_R77（2026-11-23 · dlf-oss-hunter）

## 1. 实采仓（4 仓 / 换仓重试 2 次）
| repo | spdx | tier | 列出/拉取/失败 | 入队 |
|---|---|---|---|---|
| zszszszsz/.config | MIT | green | 0/0/0（dotfiles 噪音仓，无 .st） | 0 |
| salaheldeenyasser/ModbusProtocolLibrary | None | yellow | 0/0/0（无 ST 后缀文件） | 0 |
| fisothemes/TwinCAT-Dynamic-String-Kit | MIT | green | 12/12/0 | 4 |
| ogunerkutay/filters | None | yellow | 0/0/0（非 ST 实现） | 0 |

第 4 轮（twincat/codesys library、crc16、analog scaling）：core 60/h 匿名限额耗尽，ZigaJavornik/ZigaLibs、mihaiginta/TcOscatBasic 全部 meta 403→null，入队 0。

## 2. 队列终态
- 净增 **+4**（未达 ≥15 目标；因 search 10/min 与 core 60/h 双限速，见 §4）
- 终态 **57 条：绿 53 / 黄 4 / 红 0**（增量全绿 MIT）
- 拒收 0、红区隔离 0；本轮未剔除任何条目，无标记操作
- 死条目 FC_DL_ReverseBitsWord：当前队列**未出现**，无需标注
- 新增 4 条均为字符串处理方向（TcDynStringKit）：
  - F_IsDigit → FC_DL_CharIsDigit；F_ByteToChar → FC_DL_ByteToChar
  - F_MallocStr → FC_DL_StrAlloc；F_IsBool → FC_DL_StrIsBool

## 3. 备份
- `candidate_queue.jsonl.backup_R77.jsonl`（57 行，含本轮增量前的历史 + 增量；本轮 0 剔除故为纯快照）

## 4. 工具缺陷复现（oss_harvest.py）
1. **无 --exclude 参数**：CLI 无法排除 R73~R76 已采仓，只能靠人工换 queries 绕行（默认 queries 内含 OSCAT/TcOpen/PLCnext-Community，不换必重复）。
2. **--max-files 失效**：argparse 接受但 harvest_repo 只用 max_files_per_repo，--max-files 从未生效（历史缺陷确认）。
3. **search 次级限速卡死**：匿名 search 10 次/分钟，4~6 连查即 403；工具仅 sleep 20s 且不退避，一轮 6 查询卡 12 分钟+（实测）。
4. **core 小时限速无解**：匿名 core 60 次/h，8 仓×(meta+tree+files) 必超；403 后 20s×3 重试无法恢复小时窗口，第 4 轮全仓 meta null（实测复现）。
5. **stdout 管道缓冲**：后台/管道运行时无进度输出（本次用 -u 缓解），排障困难。

## 5. 一句话结论
**队列不够 R78**：57 条按 300 件/日 × 50% 语料占比不足一日消耗，建议 R78 携 PAT（core 5000/h）重跑，并优先直扫 fisothemes 其余 Kit 仓与 `mihaiginta/TcOscatBasic`（黄区借骨）。
