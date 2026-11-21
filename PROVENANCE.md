# PROVENANCE — 组件来源与合规底账

> 自动生成于 2026-11-21 23:35 ｜ 覆盖 **1135 / 1135（100%）**
> 权威记录在 `INDEX_REGISTRY.json` 的每个组件 `origin` 字段；本文件为人类可读汇总。

## 口径

| 模式 | 含义 | 代码关系 |
|---|---|---|
| internal | 道莅原创（含 IEC 标准语义的防御性实现） | 100% 自有代码 |
| classification | 借外部库的**分类体系/参数域/接口粒度** | 零代码行复用（clean-room） |
| spec | 借公开规范（PLCopen / PackML / ISA-88 / NE107） | 零代码行复用，语义重排 |
| rewrite | 改写自宽松许可源（MIT/Apache/BSD） | 保留原始版权头 + NOTICE 登记 |

## 分布

| 模式 | 许可 | 组件数 |
|---|---|---|
| internal | MIT | 579 |
| classification | proprietary-doc | 326 |
| spec | public-spec | 144 |
| classification | OSCAT-custom | 56 |
| classification | MIT | 18 |
| classification | MIT-varies | 7 |
| classification | varies | 5 |

## 合规结论

1. **当前库内不存在 GPL/AGPL 代码**：所有 `mode=classification/spec` 组件均为 clean-room 重写，仅登记提取点。
2. **零直接复用**：`code_reuse_count = 0`；历史仅 5 件标注「改写自」，均在 NOTICE 登记。
3. **闭源源（西门子 LGF/LBP、Rockwell AOI）**：只借分类与参数域，未复制代码、DB 结构或注释原文。
4. 新增外部资产（由 `oss_harvest.py` 入队）必须带 `tier/license/source_url`，经审校官复核后方可 `mode=rewrite` 入库。

## 待办

- 文件头 `开源溯源 (Origin)` 字段覆盖率约 12%（137/1135）；**登记以 registry 为准**，文件头补写按「触及即补」执行，不做一次性批量改写（避免 1135 文件大范围变动）。
