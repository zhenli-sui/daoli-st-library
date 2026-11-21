# RAW_NOTES_R38 — 第 38 轮源与合规台账

> 轮次：R38｜日期：2026-11-18｜**WebSearch 0/3（零检索轮）**｜代码复制行数：**0**

## 一、合规铁律执行自证

1. **闭源源只借分类/参数域/命名组织**：本轮 T2 标签件（11 件）的介质类型、参数域与量纲取自公开手册与标准的**分类结构**，实现全部 clean-room 重写，未复制任何源码行。
2. **GPL/AGPL 只读思想**：本轮未引入任何 GPL/AGPL 代码；OSCAT/TcOpen/PLCopen 仅作**语义参照**（`t1-2`/`t1-5`/`t1-6` 三组），逐件在头注释 `溯源 Origin` 声明「clean-room 实现，未复制任何源码行」。
3. **RAW_NOTES 必记来源/URL/许可证/提取点**：见 §二 逐族台账；本轮为**零检索轮**，来源全部取自本地既有 `SOURCE_HUNTING_MATRIX.md` 已收口条目与 `ROADMAP.md` 真池，不新增外部 URL，故 URL 列沿用矩阵内已登记条目。

## 二、逐族来源台账（按 T 组）

| T 组 | 族 | 来源（矩阵内已登记） | 许可证 | 本轮提取点 | 本轮件 |
|---|---|---|---|---|---|
| `t2-1-lgf-math` | 数学/整定 | 西门子 LGF 数学组**分类与参数域**（Kc/Ti/Td 命名、K/T/τ 语义） | 手册（闭源，只读分类） | 参数域与量纲；SIMC 整定式为公开文献式 | 1、3、5 |
| `t2-1-lgf-technology` | 工艺/换热 | LGF 工艺组温度-流量-效能参数域；ε-NTU 公开教材式 | 手册（闭源，只读分类） | 端差/效能参数域；LMTD 退化分支自定 | 6、12、19 |
| `t2-1-lgf-measurement` | 测量 | LGF 测量组「反射比/厚度/离散度」量纲组织 | 手册（闭源，只读分类） | 双阈值带 + 迟滞 + 去抖的**组织方式**；判据自定 | 13、18 |
| `t2-2-lbp` | Library Base Pattern | LBP 的「学习补偿 + 限幅」组织（回弹学习、吸附-温控联锁） | 公开应用例（只读结构） | 学习值限幅与单向逼近结构 | 11 |
| `t2-4-s7-motion` | 运动 | S7 Motion Control 的「滞后对齐 / 振荡监视」参数域 | 手册（闭源，只读分类） | 时延/振荡指数定义；算法自定 | 4、7 |
| `t2-7-packml` | PackML | PackML 状态模型（Idle/Execute/Held/Aborted…）→ 本库 eState 子集映射 | 公开标准（OMAC） | 段推进与 Abort 语义 | 15、20 |
| `t1-2-oscat-building` | OSCAT building | OSCAT BASIC 楼宇组**语义**（风量标定、经济器、再热级联、步进风阀） | LGPL（**只读思想，零复制**） | 判据顺序与参数域；实现重写 | 10、14、16、17 |
| `t1-5-tcopen` | TcOpen | TcOpen 的「按钮组/光幕屏蔽」I/O 组织范式 | MIT | 模式枚举与恢复策略分类 | 2 |
| `t1-6-plcopen` | PLCopen MC | PLCopen Part 1/4 的 MC_ 功能块**语义**（定向停止、CamSwitch、同步） | 公开规范 | 状态机相位命名与输出语义 | 8、9 |
| T0（自研防御包装） | Base 原子 | 无外部源；IEC 61131-3 标准语义 | — | 饱和加减的宽类型比较法自定 | 1、2（部分） |

> **T0 说明**：本轮 2 件 DL_Base 属「新探明的 T0 空位」（`Saturate`/`Toggle` 词干全库 0 命中），非弃判项回填；文件头溯源统一标注「IEC 61131-3 标准语义的道莅防御性实现」。

## 三、判弃留痕（12 条，见 ROUND_PLAN §5）

主因两类：① **勾选漏账**（6 条已在 registry 在册，ROADMAP 未勾 → 属记账缺口，不是选题缺口）；② **凑数变体/同义邻件**（6 条，如 `AxisBacklashComp` vs `BacklashCompensator`、`PercentileRank` vs `PercentileLReal`）。全部未回填，本轮 13 新件均来自实测零命中候选。

## 四、矩阵台账回写

本轮涉及组：`t2-1-lgf-*`（3 子组）、`t2-2-lbp`、`t2-4-s7-motion`、`t2-7-packml`、`t1-2-oscat-building`、`t1-5-tcopen`、`t1-6-plcopen` → 状态列在 `SOURCE_HUNTING_MATRIX.md` R38 台账行统一回写（☐ → ◐/✔，按组内剩余语义量判定）。

*编制：主控（零检索轮，无外部抓取）｜2026-11-18*
