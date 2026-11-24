# HARVEST R74（2026-11-23）· oss_harvest 真采集轮（追加式）

> 工具：`C:\Library\_tools\oss_harvest.py --search --max-repos 2 --max-files-per-repo 10`
> 结论先行：**真跑成功**，但采集的 2 仓均为 R73 禁采名单仓，2 条新增候选全部为重复 → **本轮净增 0 条**。队列终态 29 条（绿区 MIT 28 / 黄区 WTFPL 1 / 红区 0）。

## 1 错误与异常记录（按时间序，均为追加）

1. `rate-limited, sleep 20s` × 2 次（GitHub search API 触发二次限流，工具自动退避后继续，未失败）。
2. `HTTP 422 https://api.github.com/search/repositories?q=org%3APLCnext-Community` —— org 语法被 search API 拒绝（R73 同因复现）。工具跳过该 query，未阻塞。
3. **工具选仓命中禁采名单**：`OttoMeister/Siemens-Tia-Portal-PID-Controller`（WTFPL）与 `RWTH-EBC/AixOCAT`（MIT）均在总监 R73 禁采 4 仓之内。工具无 `--exclude` 参数，无法在运行前规避，只能运行后剔除。
4. **新增候选均为重复，已剔除**：
   - `VAR_INPUT`（OttoMeister，WTFPL）= R73 已修复重命名为 `FB_PI_Regler_Legacy` 的同一条目，工具按原始关键字名重复抓取 → 剔除。
   - `E_SMStatus`（AixOCAT，MIT）= R73 已入队条目重复 → 剔除。
   - 工具自报 `rejected(name dup): 0`，但其去重仅比对指纹文件，未比对队列内既有条目 → 去重逻辑缺口（不修工具，仅记录）。
5. `raw.githubusercontent.com` 连接被重置（SSL handshake reset，curl exit 35，重试 3 次失败）→ 改走 `api.github.com contents` 接口成功。疑似网络侧拦截，非 GitHub 限流。
6. `_harvest_manifest.json` 写在 `C:\Library\_Staging_Raw\`（上一级），不在本次日期目录内 —— 路径与文档预期不一致，仅记录。

## 2 事故与恢复（本文件最重要的一段）

R74 剔除禁采仓新增条目时，**误删了队列中 R73 存量的 3 条同源条目**（第 20-22 行，按 source_url 匹配禁采仓时波及存量）。恢复过程：

- 备份排查：各轮 `jsonl.backup_R*.jsonl`、2026-11-21 队列、git 历史均无这 3 条 → 无法直接回滚。
- 依 HARVEST_R73.md 第 3 节 + `_dedup_fingerprints.json` 锁定 3 条为：`E_SMStatus`、`CONTROL_MODE`（AixOCAT/MIT）、`FB_PI_Regler_Legacy`（OttoMeister/WTFPL）。
- 经 `api.github.com contents` 重新取回 3 个源文件（本地留存 `_r74_E_SMStatus.xml` / `_r74_CONTROL_MODE.xml` / `_r74_fb_PI_Regler.scl`），按真实内容重建签名后追加入队，并打 `"recovered":"R74-restored"` 标记。
- `FB_PI_Regler_Legacy` 为黄区 WTFPL，**只收录接口签名/参数域/防御缺口，未复制任何实现**（红区铁律同款纪律执行）。
- 恢复后队列回到 **29 条**，与 R73 终态一致。指纹恢复 2 条（fp 与指纹文件原值一致）；`FB_PI_Regler_Legacy` 的 fp 无法按原算法复现，标 `recovered_R74`，待编码专家取件时人工复核。

## 3 终态统计

- 队列总条数：**29**（R73 终态 29，本轮净增 **0**）
- 绿区（MIT）：**28** ｜ 黄区（WTFPL）：**1** ｜ 红区：**0** ｜ unknown：**0**
- 红区剔除：**0 条**（本轮工具未采到任何 GPL/AGPL/LGPL 内容，`red_quarantine: []`）
- 扫描仓数：2（均在禁采名单）｜ 文件：8+10 listed，18 fetched，0 failed

## 4 队列深度告警

深度 29 < 200 → **红色告警**：按 300 件/日 × 50% 语料占比估算，仅可支撑约 **0.2 天**。但本轮 2 仓为禁采重扫，属无效供料。

## 5 给总监的 3 条建议

1. **给 oss_harvest.py 加 `--exclude` 参数**（禁采名单热更新），并让其去重比对候选队列全量既有条目而非仅指纹文件 —— 本轮 2/2 新增均为重复的直接根因。
2. **下一批优先挖**：`PLCnext-Community`（用非 org: 语法修正 query，多为 MIT）、`nanomodbus`(MIT)、`CANopenNode`(Apache-2.0)；search query 里对 OSCAT 镜像与 TcOpen 派生仓加排除词，避免再命中禁采名单。
3. **修 search API 422**：`org:` 语法在该端点不可用，改用 `user:` 或直接定向 `repos/<owner>/<repo>` 元数据（R73/R74 连续两轮同因失败）。
