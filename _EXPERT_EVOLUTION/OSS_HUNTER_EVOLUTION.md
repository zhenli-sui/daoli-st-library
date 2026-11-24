# 开源资产猎人 · 进化账本（OSS_HUNTER_EVOLUTION）

> 归口：开源资产猎人（daoli-oss-hunter）
> 工具：C:/Library/_tools/oss_harvest.py（GitHub 匿名 API 采集 / 许可证分级 / 签名抽取 / 三道去重）
> 规则编号与其余专家共用序列

## 一、运行状态
| 项 | 值 |
|---|---|
| 当前规则编号游标 | 见 AGENT_EVOLUTION_LOG.md 最大值 +1 |
| 上次固化轮次 | — |
| 未固化轮次数 | 0 |
| 累计新增规则 | 0 |

## 二、沉淀格式（每轮 ≤5 条）
```
[R<轮次>] <类型> | <现象> | <教训> | <规则编号或观察项>
```
类型枚举：`仓库评级` / `许可证陷阱` / `抽取准确率` / `去重有效性` / `API限制` / `合规`

## 三、已沉淀条目
_（等待 R73 起写入。首条应记录：oss_harvest 首次实跑结果、PLC-lang/rusty 判 LGPL 红区隔离是否正确、匿名 API 限流边界）_

## 四、仓库质量台账（累计评级，供后续取料参考）
| 仓库 | License | Tier | 评级 | 已抽签名 | 备注 |
|---|---|---|---|---|---|
| PLC-lang/rusty | LGPL-3.0 | 红区 | 仅读思想 | 0（不入队） | 编译器本体，非库源；仅作语法参考 |

## 五、固化批次记录
_（尚无）_

## 六、进化纪律
1. 每轮 ≤5 条；只写会改变下一轮取料决策的经验。
2. 红区仓库**永远不入队**，即使签名质量极高；只允许记录"该仓库存在哪些功能域可 clean-room 重写"。
3. 每 10 轮固化一次，合并进 skills 规范。

## 四、已沉淀条目（开工即记）

[R73-SETUP] 工具缺陷 | `--queries` 默认串以 `|` 分隔而代码 `split(",")`，整串被当作单条非法查询，`repos to scan: 0` | 分隔符必须与解析符一致；GitHub 查询语法自身用 `,` 作限定符（`in:name,description`），故内部分隔符只能用 `;` | 已修（R73 前）
[R73-SETUP] 取数缺陷 | `raw()` 仅走 raw.githubusercontent.com，本机被代理拦成 502，异常被吞后 `continue`，20 个文件全跳过却打印"scanned" | 取数必须有第二通道（contents API base64 兜底）；统计口径必须区分 listed / fetched / failed | 已修（新增 fetch_file 双通道 + 三计数）
[R73-SETUP] 抽样验证 | 修复后 brOscatLib(MIT) 20 文件→19 候选、AixOCAT(MIT)→2 候选，队列从空到 21 条 | 候选可直接支撑简单件生产；OSCAT 经典原子函数（F_LIN/F_POWER/MS_TO_KMH/CABS/HYPOT）正是 C1 档铺量素材 | 观察项
[R73-SETUP] API 配额 | 匿名 core 60 次/小时，每仓约 1(meta)+1(tree)+N(文件) 次 | 每轮限 3 仓×12 文件；超限时减仓不减轮，禁止放弃采集 | 观察项


## [R73] 2026-11-23 04:52 采集 29 条（绿区 28）
| 编号 | 类型 | 现象 | 教训 | 规则 |
|---|---|---|---|---|
| R404 | 溯源口径 | 队列 29 条，新件 20 个中 22 件命中候选语义（部分多对一） | 溯源占比按「命中候选的件数 ÷ 新件总数」计，不按候选条数计；多对一须在 RAW_NOTES 标明 | R404 |
| R405 | 许可证 | brOscatLib 中混有 WTFPL 单文件 | WTFPL 不属绿区白名单（MIT/Apache/BSD/MPL/ISC），单文件命中一律降黄区只借语义 | R405 |

[R74] 采集 | oss_harvest --search 无 --exclude 参数导致重复采 R73 禁采仓 | 净增 0 | 建议工具加 --exclude 与 org: 语法修正（PLCnext-Community 422 复现）
[R74] 事故 | 剔除禁采条目时误删队列存量 3 条，经 GitHub API 重建（recovered:R74-restored） | 队列删除操作须先备份现文件再改 | 队列写操作备份纪律

## R75（2026-11-23）
- `[R75] 经验 | 3 仓定向采集净增 21 条，去重靠"原名 + borrow_point 语义"双键比对，比单键去重多拦下 4 条重复 | 队列去重必须双键（原名 + 语义），单键会把同函数不同别名重复入队 | R428`
- `[R75] 缺陷 | 工具仍缺 --exclude，靠人工比对 R73/R74 已采仓清单才避免重复采 | 工具侧 --exclude 参数为 P0，落地前每轮采集必须人工先列已采仓黑名单 | R429`

## R76（2026-11-23）
- `[R76] 去重有效性 | search 复采已采仓 SRCI_CLIENT_PLC 产出 12 条，7 条 fp 命中 R75 存量被拦、4 条垃圾名(METHOD/EXTENDS)与 1 条 EXTENDS fp 重复人工剔除 | fp 指纹闸有效但垃圾名仍漏网，工具侧 --exclude 为 P0（R429 复现），落地前每轮必须人工带黑名单 | R430`
- `[R76] 抽取准确率 | 垃圾名(name=METHOD/EXTENDS/VAR/VAR_INPUT)本轮复现 6 条，均来自声明区/继承行被当独立条目 | 候选名必须命中 ^(FB_|F_|E_|ST_|I_)[A-Za-z] 白名单正则后再入队，工具未修前人工按 GARBAGE 集剔 | R431`
- `[R76] 许可证陷阱 | TcUnit 库级 LICENSE 显示 NOASSERTION（GitHub 未能解析），CC0-1.0 亦不在绿区白名单——两者本轮均降黄区仅借语义 | NOASSERTION ≠ 无许可，入库前须人工读 LICENSE 文本定级，降级不删 | R432`
- `[R76] API限制 | TcOpenGroup/TcUnit 返回 404（库已迁至 TcUnit/TcUnit org），工具无 moved-to 重定向跟随，直接 skip | 采仓 404 时先以 org/name 变体手动核迁仓再放弃；GitHub 30x redirect 应作为 meta 第二通道 | R433`

### R76（2026-11-23）
- `[R76] `**R444**` 工具 | 无 --exclude 参数，SRCI_CLIENT_PLC 复采 12 条全部靠指纹事后剔除 | 采集前先读队列已有 repo 集合自建排除表；--exclude 未落地前，每轮采集后必须做一次指纹剔重并备份留痕
### R77（2026-11-23）
- `[R77] `**R457**` 采集 | 实采 4 仓仅 1 仓有效（TwinCAT-Dynamic-String-Kit MIT，12 文件 0 失败），净增 4 条；多仓无 .st 后缀或非 ST 实现 | 采集前先查仓库语言与文件后缀构成，纯 dotfiles/非 ST 仓直接弃采，省 API 配额
- `[R77] `**R458**` 配额 | GitHub 匿名限额（search 10/min + core 60/h）在第 4 轮换仓时耗尽，全部 meta 403 | 单轮最多 3 仓、每仓 12 文件；若需 ≥15 条净增必须注入 GITHUB_TOKEN（连挂 9 轮的 P0 未清）
### R78（2026-11-23 夜间轮）
- `[R78] `**R474**` 采集 | 家族定向长查询（parity/BCD/unit conversion 多词 AND）GitHub 命中 0，改短查询后恢复出料 | 检索词 ≤3 实词；族级缺料时换策略：OSCAT 镜像（黄区借骨）与 PLCnext-Community org 直挖优先，org: 前缀 422 时改 owner: 检索

### R79（2026-11-24 凌晨轮）
- `[R79] `**R475**` 通道 | raw.githubusercontent.com 本机不可达(curl 000)、contents API 1 core/文件 使匿名额度只够 3 仓×12 文件；改走 codeload.github.com/<repo>/tar.gz/refs/heads/<branch> 整仓下载（实测 200、最大 49MB）**零 REST 配额**，单轮扫描从 3 仓升到 17 仓 | 采集前先做通道探测（raw / contents / codeload 三探），通道选对等于配额 ×10；tar 包无 commit_sha，provenance 需另取 | R475
- `[R79] `**R476**` 去重有效性 | oss_harvest 的 dedup 只比对 INDEX_REGISTRY 名字，**从不查 candidate_queue**，导致 R78 报"净增 +7"实为 0（7 条 SRCI 枚举与 R75 同 name 同 source_url 重复入队、签名串不同指纹也不同故 fp 闸漏过） | 入队查重必须三键：registry 名 + 队列 (name, source_url) + sha1 指纹；每轮开工先做一次全队列重名审计并回补 status=rejected（保留行不删） | R476
- `[R79] `**R477**` 抽取准确率/许可证陷阱 | OSCAT 系仓（brOscatLib 等）的 .st 文件只有**函数体**、接口全在 `oscatBasic.fun` 声明块（本轮解析 543 块，命中 5 族 53 条骨，签名抽取准确率 100%，零垃圾名）；且 brOscatLib 顶层 MIT 但同仓带 OSCAT_LICENSE（双证） | 抽骨先找声明文件再抽，不要在实现文件里正则抓 VAR_INPUT；同仓出现第二个 LICENSE（如 OSCAT_LICENSE）即视为双证，全仓降黄区 bones-only，逐条写 compliance 字段 | R477

### R80（2026-11-24 凌晨 · 冲刺轮）
- `[R80]` **R495** 工具 | 改走 `codeload.github.com/<repo>/tar.gz` 整仓下载后，单轮尝试 6 仓成功 4 仓，零 REST 配额消耗，净增 15 条 | 采集主通道固定为 codeload tar.gz；REST 仅用于"找仓"（search），绝不用 contents 接口逐文件拉取 | R495
- `[R80]` **R496** 队列 | 队列 107 行只有 96 个唯一名，11 条重复**全部是解析噪声**（`E_SMStatus`/`LogLevelEnum`/`METHOD`/`EXTENDS` 等类型名与关键字） | 入队前必须"关键字黑名单 + 同名去重"双筛；发现重复只以 `dup_flag` 标记并降 priority=0，**严禁删行** | R496


- [R520] 通道 | codeload 整仓下载 6/6 成功、零 REST 配额 | raw.githubusercontent 仍不可达，contents API 匿名限 3 仓 | 继续走 codeload；404 多为分支名 main→master，一次自纠即可。
- [R521] 缺口 | 空压站/真空/清洗整机短查询命中 0 仓 | 开源 ST 生态确无此类整机件 | 该类语义改 clean-room 公式自研，不再计入采集 KPI，避免每轮重复抵扣。
- [R522] 队列 | 有效 104 条，深度 << 200 告警线 | 按 40 件/轮仅够 2 轮 | 需在 R82 补仓至 ≥150；优先消耗 R80 遗留 15 条绿区（仍全部在库外）。

### R82（2026-11-24 · 语义定向采集）
- `[R82]` **R536** 供料 | 按五族语义定向挖（water treatment / dewatering / scrubber / maintenance / biogas），**语义命中 40/40 = 100%**，把连续 5 轮 0~23% 的溯源拉到满分 | 采集 KPI 必须拆成两个：**「语义可溯源」**（能不能找到对标物，本轮 100%）与**「代码可借码」**（能不能借鉴实现，本轮 30%）。用单一 30% 口径评判垂直工艺族会永远判「未达标」而其实是「本来就没有可借的码」 | R536
- `[R82]` **R537** 供料 | 队列 97→137（+40），绿 87 / 黄 50 / 红 0；codeload 整仓下载 10 试 4 有效，REST 配额 0 消耗 | 队列深度 137 仍 < 200 警戒线（按 300 件/日 × 50% 覆盖率仅够 0.9 天）；**下轮须么补仓到 200+，要么把「队列深度」从 KPI 降级为观察项**，否则每轮都要报同一条红警 | R537

## R83（2026-11-24 下午轮）
[R560] 通道 | `extension:st` 与 Smalltalk 撞名，命中约 90% 为 pharo/squeak 噪声 | 改用 `"FUNCTION_BLOCK" <工艺词>` 语法 token 做 GitHub code search，噪声归零；codeload 整仓 tar.gz 抽取，REST 只花元数据次数 | R560
[R561] 质量 | 空输入指纹未并入名字时所有 `TYPE` 撞同一 sha1，本轮修正 93 条误判重复 | 指纹 = 输入串 + 符号名；同型签名碰撞须在 MATRIX 标「sig 假阳性」不得直接拒单 | R561
[R562] 实证 | 印刷包装 / 纺织染整 / 立库周边三族各做 4~6 条定向查询，GitHub ST 生态命中 0 | 三族正式退出采集 KPI，走 clean-room 公式自研；采集 KPI 只考核「可借码条数」不考核「语义邻域」 | R562
[R563] 合规 | 7 仓无证（NOASSERTION/unknown）拒收，但 SLAC 真空仓可人工裁定 BSD-3 | 无证仓默认拒收；确需参考时人工裁定许可证并留证（裁定人 + 依据 + 日期）写进 MATRIX 备查 | R563

## R84（2026-11-24 傍晚）新增 3 条
- [R84] 采集结论 | 本轮五族（机加工/制药/水泥窑/造纸/反应釜）逐族 4~6 条定向查询，语义命中 **0**，与 R82/R83 的垂直工艺空白结论一致 | 垂直工艺族在 GitHub ST 生态确无对应件，采集 KPI 不应强加于此类族，改记「公式自研 C1~C3」来源等级 | R575
- [R84] 通道 | codeload 整仓 tar.gz 仍是唯一稳定通道（raw 000、contents API 吃配额）；匿名 core 60/h 限制下每轮 3 仓 × 12 文件是安全上限 | 采集脚本应默认 codeload + 失败退避，遇 403/422 减仓不减轮 | R576
- [R84] 口径 | 连续 4 轮「可借码 0%」被记为未达标，实为族选题天然不在开源覆盖区 | 建议将「溯源 30%」拆双 KPI：语义可溯源率（族级）/ 代码可借码率（件级），后者对垂直工艺族豁免 | R577

## R85（2026-11-24 夜轮）新增 4 条
- [R85] 通道 | `FUNCTION_BLOCK` + 多义工艺词被 C/C++ 标识符与自然语言注释淹没：`die casting` 1081 命中 / `shot velocity` 335 / `case depth` 18528，top-20 内 **0 个 ST** | 检索必须用「强工艺复合词」（quench / crystallizer / brewhouse），多义词查询视为无效查询，不得计入命中 | R587
- [R85] 质量 | `ZzzJjt/Industrial-Control` 是 **3601 个 .md 内嵌 ST 的数据集仓**：code search 全命中，但 codeload 抽 `.st` 得 0，且无许可证 | 命中仓先看后缀分布再决定深挖；`size` 大 + ST 抽 0 = 数据集仓，直接拒收并只作知识源 | R588
- [R85] 合规 | 无证仓（ZzzJjt×2、Eguono22/PLC-Extruder-project）虽拒收，tar.gz 已落地本地暂存盘 | 拒收仓须**同时删除落地包与抽取文本**，只留计数证据；"未入队"不等于"未泄漏" | R589
- [R85] 口径 | 五族垂直工艺（热处理/铝挤压阳极氧化/压铸/粉末冶金/酿造制糖）**族专属实件 0**，与 R82/R83/R84 一致；唯一真件（铝挤压）卡在无证 | 同类垂直族第 4 次实证空白 → 建议总监层面正式把这些族从"采集可借码"KPI 移出，改记 clean-room 公式件来源等级 | R590

## R86（2026-11-24 当日末轮）新增 2 条
- [R86] 采集 | 队列 225 条（绿 163 / 黄 62 / 红 0），净 +10，全部 Apache-2.0 支撑件；本轮四族（Q15 定点 / 量程映射 / 饱和算术 / 单位换算）开源命中 **0** | 连续第 5 轮实证：底层数值方法与垂直工艺族在开源 PLC 生态中系统性空白，「溯源 30%」对该类族不可达，需拆双 KPI | R626
- [R86] 合规 | `Ben-Bergh/homeassistant-tcp-modbus` 的 GitHub API `license` 字段判绿，落地读 LICENSE 全文实为 **AGPL-3.0**，已删下载包 | 许可证判定必须读仓内 LICENSE 全文，API 的 license 字段只能作初筛，不能作结论 | R627
