# RAW_NOTES_R26 —— R26 轮次检索留痕

- 轮次：R26 ｜ 日期：2026-11-17 ｜ WebSearch 实际使用：**0 次**（预算 ≤2，剩余全部让渡终审）
- 合规口径：本轮 20 件 = **3 件 T0 零检索变体线 + 17 件已登记 ◐ 组深化/ROADMAP 已登记缺口**，未新开任何 ☐ 源组，未重复检索任何已 ✔ 收口组（T1-3 OSCAT Network 不碰）。深化件的提取点沿用 `C:\Library\SOURCE_HUNTING_MATRIX.md` 已留痕的来源行，无需新增网络检索。

## 留痕清单（来源名 / URL / 许可证 / 提取点）

| 规划序号 | 来源标签 | 来源名 / URL | 许可证 | 提取点 | 性质 |
|---|---|---|---|---|---|
| 1~3 | t0-1/2/3/6 变体线 | 无外部源（IEC 61131-3 第三版标准语义） | IEC 标准语义引用（不复制文本） | 定时器/计数器/字符串的标准行为边界 + 道莅防御性扩展 | T0 零检索 |
| 4~5 | t2-1-lgf-measurement | Siemens LGF V5.3.0，文档 ID 109479728（matrix 第 1~4 节已登记） | 免费使用、闭源版权 | 「Measurement 组统计族待挖」分类骨架；闭源仅借分类与参数域，代码 clean-room | 已登记 ◐ 深化 |
| 6 | t2-1-lgf-technology | 同 LGF 上行 | 同上 | Technology 组参数表组织惯例（查表插值接口形态） | 已登记 ◐ 深化 |
| 7~8, 19 | t2-2-lbp | Siemens LBP V2.7（matrix 已登记） | 免费使用、闭源版权 | 阀/电机/驱动工艺接口分层与诊断分级组织；clean-room | 已登记 ◐ 深化 |
| 9, 16 | t1-2-oscat-building + roadmap L350 | OSCAT Building 3.3.x，https://oscat.de（matrix 已登记） | OSCAT 免费许可（需致谢） | 罐/泵族行为定义惯例；roadmap §L350 为库内登记缺口 | 已登记 ◐ 深化 |
| 10, 18 | t1-2-oscat-building | 同上 | 同上 | 泵风机族（干转/传动打滑判据的参数域组织） | 已登记 ◐ 深化 |
| 11~12 | t1-6-plcopen | PLCopen TC2/TC3（matrix 已登记） | PLCopen 规范免费 | 轴监视与凸轮表接口契约（MC 语义映射纪律） | 已登记 ◐ 深化 |
| 13 | t2-8-isa18.2 | ISA-18.2 报警管理公开规范（matrix 已登记） | 公开规范（借思想不复制文本） | 搁置/屏蔽生命周期（限时、超时强制恢复、台账） | 已登记 ◐ 深化 |
| 14 | roadmap L259 | 库内 ROADMAP.md 第 259 行已登记缺口 | — | 组件名与目标层由 ROADMAP 预登记 | 库内登记 |
| 15, 17 | t2-7-packml | PackML / OMAC 公开规范（matrix 已登记） | 公开规范 | 换型编排命名组织、KPI 聚合接口组织 | 已登记 ◐ 深化 |
| 20 | roadmap L363 | 库内 ROADMAP.md 第 363 行已登记缺口 | — | 组件名与目标层由 ROADMAP 预登记 | 库内登记 |

## 合规铁律执行声明

1. 闭源源（LGF / LBP）只借分类、参数域与接口组织；无任何函数体、函数名、常量名复制，全部 clean-room 重写。
2. GPL/AGPL 类源本轮未接触；OSCAT 按其许可要求在手册致谢（沿用既有手册已写致谢条款）。
3. ISA-18.2 / PackML / PLCopen 仅借公开规范思想与状态语义，不复制规范文本。

## 检索预算说明

WebSearch 0/2：全部取材均在 `_Staging_Raw` 与 `SOURCE_HUNTING_MATRIX.md` 已留痕范围内闭环，无新增外部事实需求；剩余预算全部留给终审复核使用。
