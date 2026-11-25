# R76 采集报告（2026-11-23 15:56，oss_harvest 真采集轮）

## 1. 扫描概况
- 尝试仓 6：TcOpenGroup/TcUnit（404 已迁仓）、TcUnit/TcUnit（✔ 20 文件全取）、zhouyongh/codesys-sync（0 ST 文件弃采）、ThorstenBrach/SRCI_CLIENT_PLC（复采命中，全部剔重）、FellowWithLaptop/FB_CaseStateMachine（✔ 3/3）、KIT-77/codesys-option-activation（✔ 1/1，许可证 None）
- 汇总：**listed 24 / fetched 24 / failed 0**（未遇 403/422，core 限额尚余 ~30）

## 2. 入队与分区
- 工具原始入队 17 条 → 剔重后 **净增 3 条**，队列累计 **53 条**（绿 49 / 黄 4 / 红 0）
- 新增明细（均为黄区，只借语义）：
  1. `E_XmlError` — TcUnit/TcUnit，NOASSERTION，15 行
  2. `ST_AdsLogStringMessage` — TcUnit/TcUnit，NOASSERTION，13 行
  3. `E_MainStateMachine` — FellowWithLaptop/FB_CaseStateMachine，CC0-1.0（不在绿区白名单，降黄区），21 行

## 3. 剔除台账（备份 candidate_queue.jsonl.backup_R76.jsonl，67 行全量留痕）
- SRCI_CLIENT_PLC 复采 12 条：7 条 fp 命中 R75 存量（LogLevelEnum/AreaTypeEnum/SequenceFlagEnum/MessageLevelEnum/AbortingModeEnum/ProcessingModeEnum/ReturnMode）+ 1 条 EXTENDS 重复 + 4 条垃圾名（METHOD×2/EXTENDS×2）→ 全部剔除
- 其他仓垃圾名 2 条：VAR（FB_CaseStateMachine 内声明区）、VAR_INPUT（FB_CodeActivation.st 声明区）
- 合计剔除 14 条；未直接删行，备份先行 ✅

## 4. 许可证分级
- 绿区（MIT/Apache 等）：本轮 0 净增；存量 49
- 黄区（NOASSERTION/CC0/WTFPL）：本轮 +3；TcUnit NOASSERTION 需人工核 LICENSE 文件后再定级
- 红区：0（无 GPL/AGPL/LGPL 仓库命中，无需隔离）

## 5. 工具缺陷（延续 R429）
- `--exclude` 仍缺失：search 两轮均可能复采已采仓，本轮 SRCI 12 条复采即因此
- 垃圾名抽取仍存在：`METHOD/EXTENDS/VAR/VAR_INPUT` 被当作 name（R75 已记，复现）
- 新缺陷：TcOpenGroup/TcUnit 404 后无重定向跟随（GitHub moved-to 未处理）

## 6. 语义族参考（供编码席派生，来自 TcUnit/Fellow 黄区 + 存量绿区）
- 日志文本族：`AdsLogStringMessage` → 建议 `FmtAdsLogLine` / `LogTextTruncate` / `ErrCodeToText`
- XML 错误族：`XmlErrorEnum` → 建议 `XmlErrClassify` / `XmlFaultToString`
- 主状态机族：`MainStateMachine` 枚举相序 → 建议 `CaseSeqAdvance` / `SeqStateGuard` / `StepTimeoutWatch`
- 存量绿区可派生（R75 遗留）：哈希族 `HashKeyNormalize`/`BucketIndexCalc`；饱和四则 `SaturatePow`；泛型分配 `FreeGenericPair`

## 7. 下一轮建议仓
- `TcUnit/TcUnit` 深挖 PRG/FB 层（本轮仅抽到 DUT 层 2 条，20 文件未出 FB 候选，需 --max-files 提升或指定子目录）
- `CODESYS-Samples` / `PLCnext-Community` 单仓定向（org: 查询 422 待修）
- `Roebert/...`? 未验证——建议先核 license 再采；若黄区超标可转 TcOpen 生态未采子仓（TcUnit-Adapter 等）
