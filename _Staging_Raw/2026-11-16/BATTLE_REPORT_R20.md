# BATTLE REPORT — Round 20（2026-11-16）

> 道莅工控代码库 ｜ 轮次：R20（T0 快车道 · 日历/时间族 + 域转换 + 字节序 + 同步族）｜ 召唤模式：**原生召唤连续第 7 轮**

## 1 目标与完成情况（20 / 20，分 4 批）

| 批 | 主题 | 落库 | 件数 | 行数 |
|---|---|---|---|---|
| 批 1 | 日历 / 纪元族 | DL_MathData：DtToDintEpoch / DintEpochToDt / DateToDintDays / DintDaysToDate / LeapYearChk（DL_Base） | 5 | 485 |
| 批 2 | 时间算术 + 日期算术 | DL_MathData：TodAddWrap / TodDiffWrap / TimeAbsSat / DateAddDays / DateDiffDays | 5 | 543 |
| 批 3 | 域转换 + BCD 补口 | DL_MathData：UdintToLintChk / WordToIntSat / DwordToIntSat / LwordToLintSat / BcdToByte | 5 | 456 |
| 批 4 | 字节序 + 字符串化 + 同步族 | DL_MathData：ByteToBcd / SwapBytes64 / DintToStringTrim / LrealToStringTrim ｜ DL_Base：SemaMutex | 5 | 705 |
| **合计** | | DL_MathData 18 ｜ DL_Base 2 | **20** | **2,189** |

- 落盘路径：`C:\Library\DL_MathData\` 18 件 + `C:\Library\DL_Base\` 2 件；文件名 = POU 名，注册收口齐备。
- 机检：16 规则 **20/20 PASS，fail = 0**（红线违规 0）。

## 2 计数（本轮后）

| 指标 | 值 |
|---|---|
| 今日入库 | **140 / 200（70.0%）**，2026-11-16 开账 |
| 总库 | **344 / 10,000**（全库 79,956 行） |
| 距 500 冲刺目标 | 差 **156 件**（按 20 件/轮约 8 轮） |
| 子库分布 | DL_Base 66 ｜ DL_MathData 130 ｜ DL_Algo 36 ｜ DL_Device 57 ｜ DL_Motion 25 ｜ DL_Process 30 |
| 注册表 / 语料 | `INDEX_REGISTRY.json` 344 件 / v2.9.0 ｜ JSONL **344 条** |
| 码位游标 | 信息级 **0434** / 故障级 **036C**（R20 批 100 槽零重叠；全库另有 `DL_Algo 0002_00xx` 公共码子带为刻意共享，已挂账审计） |

## 3 所用源

**T0 快车道零检索**（沿用 R14 三判据：逐引脚对应 IEC 标准语义 + 委托内建/标准语义 + clean-room 溯源）。本轮零 LGF / OSCAT / TcOpen / Forge 输入，故源矩阵 **T2-1 / T1-x 各行状态列一律不动**（零检索轮改 ✔ 即虚账，R85），登记回写 T0-2 / T0-5 / T0-6 三行并**新增 T0-8 同步/互斥行**，裁定留痕 `M-E5`。

## 4 终审（8 件高风险定向抽样：6 PASS + 2 命中）

| 件 | 结论 | 要点 |
|---|---|---|
| FC_DL_DtToDintEpoch | PASS | 下域闸先于内建、Y2038 饱和升故障级、负秒第二道防线 |
| FC_DL_DintEpochToDt | PASS | 「合成路径」写在编译门槛的**降级段**，与正文不矛盾（审读陷阱，非缺陷） |
| FC_DL_TodAddWrap | PASS | 禁 MOD 真落实；`|offset|<一日 ∧ nBase∈[0,一日)` ⇒ 一次条件加减足够 |
| FC_DL_DateAddDays | PASS | 减法预判双向方向正确（两向比较符相反但均对，本轮最易误判点） |
| FC_DL_LrealToStringTrim | **FAIL→修** | **中等·逻辑**：无穷阈值 1.79E308 落在 LREAL 域内，极大有限值被输出成 `'Inf+'` |
| FC_DL_SwapBytes64 | PASS | `(LoRev<<32) OR HiRev = B0..B7` 逐字节验真翻转 |
| FC_DL_TimeAbsSat | PASS | `nIn < −2147483647` 精确命中 INT32_MIN，非负直通在边界闸前 |
| FB_DL_SemaMutex | **措辞→修** | **注释级**：三态/兜底/首部刷新/先清后置/未吞复位沿均正确；「本拍即回 eFree」跨拍语义不精确 |

**修复（2 件，均升 v1.0.1，对外引脚零变更）**
1. `FC_DL_LrealToStringTrim`：改 `(fIn − fIn) <> (fIn − fIn)` 精确判据 + LREAL 最大值兜底，消除 7.7E305 宽度的假阳性带。
2. `FB_DL_SemaMutex`：过渡态注释改「拍 N 进 / 拍 N+1 出 / 本拍拒绝申请」三段式；同步修正 JSONL `architecture_thought` 的码位错记（036A→0369）。
3. 语料重注入：2 行按「定位 → 替换 output → 复核 thought → sha 复验 → registry 同步」五步执行；**342/344 字节级 MATCH + 2 条 CRLF 遗留（内容归一化后一致）**。
4. 元数据债（如实登记，本轮不动）：`line_count` 全库两种历史口径（102 条物理行 / 56 条含尾空行，R20 批内亦不一致）；`DL_Algo 0002_00xx` 公共码子带使「全库码位零重叠」表述不成立。两项均进 `ROADMAP §23.1`。

**历史教训自查**：漏 VAR_OUTPUT 0 ｜ 注释嵌套 0 ｜ 枚举单冒号 0 ｜ 锁存副本 vs 实时镜像混用 0 ｜ 单拍标志只置不清（R25）0 ｜ TP 自清（R24）不适用 ｜ CASE 前置改写吞复位沿（R45）0。

## 5 专家进化

PLC 账本 **+5 条（R79~R83）**：判据阈值须落不可达域 / 过渡态注释三段式 / 反解方向不饱和 / ≥64 位字节序复用+交叉合成 / 双游标子带纪律。
总监账本 **+5 条（R84~R88）**：域端点三点推演准入 / 零检索轮台账不虚账 / 子库计数与注册表断言 / JSONL thought 纳入修复流程 / 手册补录每轮 ≤10 件。
**本轮合计 10 条，编号接续 R79→R88。** 固化评估：R71~R83 未固化 13 条，距 20 条阈值差 7 条，**本轮不触发固化**（预计 R22 末~R23 初）。

## 6 文档增量（追加式，零整篇重写）

`README.md`（徽章 324→344 + Round 20 区块）｜ `CHANGELOG.md`（v2.9.0 条目）｜ `DL_MathData/VERSION.md` → v1.14.0 ｜ `DL_Base/VERSION.md` → v1.14.0（两库组件数口径校正 107→130 / 63→66）｜ `MANUAL_DL_MathData.md` + `MANUAL_DL_Base.md`（R20 接口表 18+2 件）｜ `MANUAL_DL_Device.md` / `Motion` / `Process`（**R19 遗留 P1 补录 10 件**，剩余 53/21/28 件注明下轮续补）｜ `AGENT_EVOLUTION_LOG.md`（R20 节）｜ `SOURCE_HUNTING_MATRIX.md`（T0 三行登记 + 新增 T0-8 + M-E5 裁定）｜ `ROADMAP.md`（§22.2 纪元对等勾选 + §23 新增 ≤10 条）｜ `LIBRARY_MANUAL.md`（第十六节 R20 章 + 未编译验证声明沿用）。

## 7 下轮计划（R21）

1. **P0 编译验证债立项**（连续 15 轮悬置，本轮又增 3 条日历内建链假设，债务在扩大）：最小 CODESYS V3.5 工程 + 20 件抽样编译记录。
2. P0：子库计数断言脚本化（`_verify_counts.py`）+ JSONL 两条 CRLF 归一化。
3. 主线：20 件（建议 T0 剩余变体线 + `SwapBytes16/32` 排布补齐），守住 20 件/轮节奏。
4. 持续：三本 Level 1 手册历史件续补 ≤10 件/轮；`LIBRARY_MANUAL` 补 R18/R19 两章。
