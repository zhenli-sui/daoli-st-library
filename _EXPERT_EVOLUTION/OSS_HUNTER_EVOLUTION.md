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
