# HARVEST R78 采集简报（2026-11-23 23:20–23:35）

## 1. 扫描量
- 采集仓数：3 轮次共 8 尝试 / 8 扫描；列出文件 36、成功抓取 24、失败 0
- 抽取签名数：SRCI_CLIENT_PLC 12 条入队尝试
- 有效出料仓：1（ThorstenBrach/SRCI_CLIENT_PLC，MIT，stars=84）

## 2. 进队数
- 净增 **+7**：绿 7 / 黄 0 / 红 0
- 入队 12 → 5 条标记 `status=rejected`（垃圾名抽取：关键字 METHOD/EXTENDS 被误捕为标识符，签名正则缺陷复现，未删行）
- 拒收/隔离：stefanbesler/struckig（GPL-3.0）红区仅记录思想，零源码拉取

## 3. 队列终态
- **64 条（绿 60 / 黄 4 / 红 0）**；备份 candidate_queue.jsonl.backup_R78.jsonl（57 条）
- 队列深度 64 < 200：**红色告警**，按 300 件/日 × 50% 语料占比≈可支撑 < 1 天生产

## 4. 新发现高价值源
| 仓 | 许可 | 理由 |
|---|---|---|
| ThorstenBrach/SRCI_CLIENT_PLC | MIT | SRCI 机器人协议客户端，7 条枚举 TYPE（LogLevelEnum/AreaTypeEnum/SequenceFlagEnum/MessageLevelEnum/AbortingModeEnum/ProcessingModeEnum/ReturnMode）全绿可参考协议状态语义 |
| stefanbesler/struckig | GPL-3.0 | 红区思想源：Ramp/轨迹限幅+爬坡语义（正好对应本周限幅/爬坡族），只可提炼参数域与状态机笔记 |

## 5. 合规异常
- 红区泄漏：0 行；unknown 许可拒收：1（Dynamic-Setpoint-Profiles 无 LICENSE，黄区未入队）
- 遗留缺陷：签名正则垃圾名（R76 已报、R78 复现）——`--exclude` 与名字校验仍缺

## 6. 检索教训
- 长查询（"parity structured text IEC 61131-3" 等）GitHub 全词 AND 命中 0；短查询才出结果
- `org:PLCnext-Community` 查询一次 422（配额窗口内偶发，未重试第 3 次）

## 7. 给总监的 3 条建议
1. **本族绿区增量仍为 0**：parity/BCD/单位换算/限幅爬坡未命中任何绿区仓；R79 优先改挖 OSCAT 镜像（黄区借骨）与 PLCnext-Community org 直列（跳过 search API，直接 /orgs/repos 绕开 422/限流）
2. **修 oss_harvest.py**：签名抽取加名字白名单（`^[A-Za-z_][A-Za-z0-9_]*$` 且非关键字表），避免垃圾名再次污染队列
3. **struckig 红区思想转换**：派一个"只读思想"任务提炼 Ramp 状态机/参数域笔记进 EDGE_CASE_KB，供 clean-room 重写限幅爬坡族

## 8. 本轮语义清单（供编码席溯源）
- 7 条 MIT 枚举 TYPE：SRCI 协议日志级别 / 作业区类型 / 序列标志 / 消息级别 / 中止模式 / 处理模式 / 返回模式（DL_Base/DL_MathData/DL_Process 分域建议见 queue 行）
- 红区 struckig：仅思想，无代码
