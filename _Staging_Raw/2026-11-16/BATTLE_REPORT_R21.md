# BATTLE REPORT R21 — 2026-11-16

> 道莅工控代码库 ｜ Round 21 ｜ 执行窗口 20:37 ~ 21:2x ｜ 召唤模式：**原生召唤**
> 主题：**数学安全原子 + LWORD 位域/校验 + 文本序列化 + 守卫 FB 20 件**（T0 变体线 + T2-1 LGF 三子族）

---

## 一、目标完成情况（20 / 20，4 批全收口）

| 批次 | 子库 | 件数 | 组件 | 行数 | 挂源 |
|---|---|---|---|---|---|
| 批1 数学安全原子 | DL_MathData | 5 | `FC_DL_ModPos` / `DivLrealSafe` / `QuantizeStep` / `PolyEvalHorner` / `WrapAngleDeg` | 约 640 | T0 变体线（自研） |
| 批2 LWORD 位域 + 校验 | DL_MathData | 5 | `FC_DL_LwordBitFieldExtract` / `Insert` / `LwordBitCount` / `Crc16Generic` / `ChecksumSum8` | 约 700 | **T2-1 LGF** Bit Logic + Data Handling + Converter |
| 批3 文本序列化 | DL_MathData | 5 | `FC_DL_StringToDint` / `DwordToHexString` / `ArraySumLreal` / `TimeToHmsString` / `DateToIsoString` | 约 774 | T0-6 字符串变体 + **T2-1 LGF Converter** |
| 批4 守卫 FB | DL_Base | 5 | `FB_DL_MinOnOffGuard` / `SignalChangeCounter` / `SamplingTrigger` / `SignalFrozenDetect` / `PulseWidthFilter` | 约 688 | 自研（工程惯例 + NE107 语义次源） |
| **合计** | 2 子库 | **20** | — | **2,802** | T0 变体线 + T2-1 三子族 ×6 件 + NE107 语义 ×1 |

## 二、库体指标

- 今日（11-16）累计 **178 / 200（89.0%）**；总库 **364 / 10,000（3.64%）**；距 **500** 冲刺差 **136 件**。
- registry **344 → 364**（`v2.10.0`，counts `71/145/36/57/25/30`），备份 `_Staging_Raw/2026-11-16/INDEX_REGISTRY.backup_R21`。
- JSONL **344 → 364 条**，全量 sha256 **MATCH**；修复重注入 4 行（v1.0.1）字节级复验通过。
- 码位：全库唯一性求差断言 **CLASH = NONE**；游标推进至 **信息 `045C` / 故障 `03A8`**。

## 三、机检 / 终审结果

- 机检 `check_r21.py`：**20/20 PASS，fail = 0**，轮内重复 0。本轮把嵌套注释判定由单条跨块正则升级为**非贪婪成对剥离法**，修正旧正则的假阳性（沉淀 R91）。
- 终审定向抽查 **7 件**（数值算法 2 / 时序状态机 2 / 退化分支 1 / 接口契约 1 / 校验算法 1，满足 R71 五类配额）：命中 **3 件 + 轻微 1 件，全部当轮修复**。

| 组件 | 版本 | 级别 | 缺陷一句话 |
|---|---|---|---|
| `FC_DL_DateToIsoString` | →1.0.1 | **严重** | 年序除数 146097 应为 146096 → **2000-02-29 等世纪闰日误判 0397 故障**并回退 `1970-01-01` |
| `FC_DL_Crc16Generic` | →1.0.1 | 中等 | 空帧早退分支漏输出反射 → 非回文初值 + `bReflectOut` 必错 |
| `FB_DL_PulseWidthFilter` | →1.0.1 | 轻微 | `bReset` 电平清零与引脚注释「上升沿」不符（按住在 HMI 上即冻结统计） |
| `FC_DL_StringToDint` | →1.0.1 | 轻微 | 溢出分支未写 `nErrPos`，与「0 = 无错」哨兵冲突 |

- 四处主动偏离裁定：① `MinOnOffGuard` 样板死锁形态修正 **采纳**（TON 的 `Q` 在 `IN=FALSE` 时恒 FALSE，旧形态必死锁）；② `PulseWidthFilter` `T#2MS` 代理阈值 **条件采纳**（三句声明在场 + 挂债）；③ `StringToDint` ELSE 复用 038C **采纳**（R90 不加码）；④ CRC 向量「脚本命中」**采纳挂债、驳回「已验证」口径**（R96 双列验收）。

## 四、专家进化

- 新增规则 **8 条**：总监 3（**R89** 公开算法常数逐项对表 / **R91** 成对剥离式机检 / **R93** 溯源双固定句）｜ PLC 5（**R90** 不加码反证 / **R92** 「同上」全域禁用 / **R94** 早退分支同构后处理 / **R95** 代理阈值三句声明 / **R96** 双列验收）。
- 游标 **R75（账面陈旧）→ 实测 R88 → 推进至 R97**；未固化 **18 条**，距 20 阈值差 2，预计 **R22 末**触发第二批固化。

## 五、编译验证债（新增 3 条，连续 16 轮悬置）

1. `FC_DL_TimeToHmsString`：`TIME_TO_DINT` 毫秒口径未实测。
2. `FC_DL_DateToIsoString`：`DATE_TO_DINT` 纪元口径（1970-01-01 = 0）未实测，已由回代自校验兜成可观测故障。
3. `FC_DL_LwordBitFieldExtract`：`WORD` 容器 `SHL` 语义（16 位截断 vs 32 位提升）未实测。

> 判定：**编译债已成为库体最大的系统性风险，优先级高于任何单件缺陷**。R22 起建议把「最小空工程编译一次」列为 P0 交付物，哪怕只编一个子库。

## 六、下轮（R22）计划

1. **P0**：启动最小工程编译验证（目标：`DL_Base` 全量 + 本轮 4 件 v1.0.1），把 16 轮债务先砍掉一半（编译口径比新增 20 件更有价值）。
2. **P1**：T2-1 LGF 剩余子族续挖——Data Handling「LWORD 多段一次搬」、Converter「数值 → 定宽字段对齐」、Bit Logic「单字 64 位多段」；T0 变体线补「字符串 ↔ 数值」反向族（`DintToString` 已有，缺 `LrealToString` 定点/科学计数口径）。
3. **P2**：三本 Level 1 手册历史件接口表续补 ≤10 件/轮；`MinOnOffGuard` 失能恢复不继承最短停止的手册提示（盘车风险）。
4. 凑数检查：本轮 ROADMAP 池 356 条充足，20 项不在池内故无勾选；建议 R22 池扩 ≤10 条（编译验证债转独立泳道 + 上述 P1 子族）。

---

*归档：`_Staging_Raw/2026-11-16/BATTLE_REPORT_R21.md` ｜ 道莅工控代码库产品总监*
