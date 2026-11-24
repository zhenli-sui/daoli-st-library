# ROUND_PLAN_R67 — 批处理巡检规划（2026-11-22 05:58 启动，50 分钟硬顶 06:48）

> 阶段一：规划 + 点修需求规格。主控直跑（R335），未做编码。R309 分散型配额 12（R66 挂账 4 处分散 3 族单族 <2）。
> 选题纪律：全部 12 目标已过「全库同名 + 同义邻件 + 文件树」三查（INDEX_REGISTRY v2.58.0 + Glob），零撞名。

## 1. 看板统计（任务 A）

| 指标 | 值 |
|---|---|
| 总库 | **1,155 / 10,000（11.55%）**（registry total_components=1155；counts 143/272/134/207/121/278） |
| 今日 11-22 已产 | **20 / 200**（R65 续作 10 + R66 10） |
| 距 1,200 里程碑差额 | **45** |
| JSONL | 1,179 条 bad=0 |
| ROADMAP 未勾待办 | 47 条（≥30 → 本轮不补条，任务 E 跳过） |
| 游标 | R324 |

## 2. 12 目标总表（任务 B）

| # | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FC_DL_QuadPolyFit **v1.0.1（点修）** | MathData | FC_DL_ | 舒尔补主元闸 + 溢出复核扩展（规格见 §3.1） | self-std（R66 REVIEW 挂账） | 点修 | 1 |
| 2 | FB_DL_LotMergeGate **v1.0.1（点修）** | Process | FB_DL_ | eFault 死迁出式删除 + L2 留档口径登记（§3.2） | self-std（R66 REVIEW 挂账） | 点修 | 1 |
| 3 | FB_DL_TaktPaceMonitor **v1.0.2（点修）** | Process | FB_DL_ | fExpectR 闸界前移至 DINT 域（§3.3） | self-std（R66 REVIEW 挂账） | 点修 | 1 |
| 4 | FC_DL_CalcDistance2D | MathData | FC_DL_ | 2D 平面两点距离（√(Δx²+Δy²)，大坐标防溢出域闸），与 `FC_DL_CalcDistance3D` 头注互引分工 | t2-1-lgf-math | 低 | 2 |
| 5 | FC_DL_AngleDiffRad | MathData | FC_DL_ | 两弧度角最短带符号差（归一至 −π..π），与 `FC_DL_AngleDiffWrap` / `FC_DL_WrapAngleDeg` 互引分工（弧度口径属主） | t2-1-lgf-math | 低 | 2 |
| 6 | FC_DL_NormTo01 | MathData | FC_DL_ | 值域线性归一化至 0..1（fMin/fMax 输入，反向域与除零双闸） | t2-1-lgf-math | 低 | 2 |
| 7 | FC_DL_SlewRateCalc | MathData | FC_DL_ | 采样间变化率（工程单位/s），周期 ≤0 闸 + 非有限拦截 | t2-1-lgf-technology | 低中 | 2 |
| 8 | FC_DL_HexToStr | MathData | FC_DL_ | 字节串→HEX 文本（255 上限截断标志，复用 T0-6 四步截断样板 R49） | iec-std-wrapper（T0-6） | 低 | 2 |
| 9 | FC_DL_StrToHex | MathData | FC_DL_ | HEX 文本→字节串，非法字符 / 奇数长度显式错误码 | iec-std-wrapper（T0-6） | 中 | 3 |
| 10 | FB_DL_TriangleGenerator | Algo | FB_DL_ | 三角波发生器（频率/幅值/相位复位输入），与 `FB_DL_SineGenerator` / `FB_DL_SawtoothGenerator` 头注互引 | t2-1-lgf-signalgen | 中 | 3 |
| 11 | FB_DL_LastGoodValueHold | Base | FB_DL_ | 信号质量失效时保持最后有效值 + 陈旧时长计时，超限置码（NE43 语义） | t2-8-ne43 | 中 | 3 |
| 12 | FB_DL_ImpulseRelay | Base | FB_DL_ | 沿触发定宽脉冲输出（按钮/点动→固定时长），与 `FB_DL_TpEx` / `FB_DL_PulseStretch` 头注互引分工 | t1-1-oscat-basic | 低中 | 3 |

来源配额：T2-1 LGF 五族 5 件 + T2-8 NE43 1 件 + T0-6 包装 2 件 + T1-1 OSCAT 1 件 + self-std 点修 3 件 → 满足「≥1 T2 非 ST 源 + ≥1 T1 ST 源」；本轮为减配轮（12 件），无凑数变体（AngleDiffRad 为既有角度族的口径属主补口，非重载凑数）。

## 3. P0 点修需求规格（交编码专家，任务 B 重点）

### 3.1 FC_DL_QuadPolyFit（`C:\Library\DL_MathData\FC_DL_QuadPolyFit.st`）v1.0.0 → v1.0.1
- **缺陷 M2（REVIEW_R66）**：段 7 回代的列主元闸只覆盖第 0/1 列（消元主轮 2 轮），`aM[2,2]` 舒尔补未闸。两个相异 x 值（传感器两态卡值，可达）时正规方程秩 2，回代除零出 NaN/Inf 落码 02，与头注声明的码 03（奇异）归因错位。安全行为不变（不输出系数、bValid=FALSE）。
- **修复要求**：段 7 回代前补 `IF ABS(aM[2,2]) < QPF_PIV_MIN THEN 置码 03 + bValid=FALSE + RETURN`（常量随既有主元闸命名风格提级，双精度口径注释）。
- **缺陷 L1（合并点修）**：段 4 ABS 溢出复核仅覆盖 s4/t2，扩展至 s1/s2/s3/t0/t1 全部矩量（Inf 提前归因，不等段 8 回代兜底）。
- **收口动作**：版本 v1.0.1 + registry 行同步 + CHANGELOG MINOR。

### 3.2 FB_DL_LotMergeGate（`C:\Library\DL_Process\FB_DL_LotMergeGate.st`）v1.0.0 → v1.0.1
- **缺陷 L3（REVIEW_R66）**：eFault 分支 `IF NOT _bFaultLatch → eIdle` 迁出式不可达（迁入 eFault 必伴锁存，清锁存的复位沿同拍已置 eIdle）——死代码。
- **修复要求**：删除该死迁出式；eFault 相出口仅保留锁存解除路径。eIdle 相 `uLotQty > LMG_U_MAX` 留档型防御（L2）**保留不动**，仅在头注按「结构性不可达防御统一记账口径」补一行登记。
- **收口动作**：版本 v1.0.1 + registry 同步 + JSONL 语料重注入（R248，连同目标 3 的 v1.0.1）。

### 3.3 FB_DL_TaktPaceMonitor（`C:\Library\DL_Process\FB_DL_TaktPaceMonitor.st`）v1.0.1 → v1.0.2
- **缺陷 L4（REVIEW_R66 上报定位点 5）**：fExpectR 闸界 4.294967295E9（UDINT 域）与转换链 `TIME_TO_DINT` 的 DINT 中转域 2^31−1 不齐；窗/目标比 >2.1e9 s 组态下可达。
- **修复要求**：闸界常量前移至 **2147483647**（DINT 域上界），头注域界声明同步；不得改动 M1 已修的码 01 判式（`(NOT _bTgtOk) OR (NOT _bTimeOk)`）。
- **注意**：M1 已在 R66 就地修至 v1.0.1，本轮为 **v1.0.2**，勿回退 M1。

### 3.4 批 1 附加收口（不占新件配额）
- `FB_DL_AnalogOutFailsafe` / `FB_DL_TaktPaceMonitor` v1.0.1 **JSONL 语料重注入**（R248，ROADMAP 已挂账）。
- 注入引脚「三形态选型表」固化 coding-standard：ROADMAP 已登记（R66 新增待办第 5 行），**无需重复追加**，由编码/收口轮执行。

## 4. 批次划分（任务 B，按依赖与复杂度）

- **批 1（点修）**：目标 1/2/3 + §3.4 语料重注入 —— 3 件，先行收口。
- **批 2（低复杂度纯函数，FC ×5）**：目标 4/5/6/7/8 —— DL_MathData 集中，互相无依赖。
- **批 3（FB / 中复杂度 ×4）**：目标 9/10/11/12 —— StrToHex 依赖 HexToStr 风格样板；TriangleGenerator / LastGoodValueHold / ImpulseRelay 相互独立。

## 5. 预算执行声明

- 规划阶段耗时 <10 分钟（05:58 启动窗口内完成），未整库全量扫描：仅读矩阵节选、REVIEW/BATTLE_R66 全文、ROADMAP 尾部与 §4 计数、registry 概算（4 次 python -c）。
- WebSearch **0/1**（零检索轮：全部来源复用矩阵既有组与 R66 REVIEW 挂账，未开新源，符合「同源不重复检索」）。
- 剩余预算留给编码/终审/收口阶段；R309 配额 12 件不追加。

## 6. 文件动作清单（本规划轮）

| 动作 | 文件 |
|---|---|
| 新建 | `_Staging_Raw\2026-11-22\ROUND_PLAN_R67.md`（本文件） |
| 新建 | `_Staging_Raw\2026-11-22\RAW_NOTES_R67.md`（来源留痕） |
| 增量追加 1 行 | `SOURCE_HUNTING_MATRIX.md` §4 实测列表（R67 规划行，编码收口后正式回写状态列） |
| 增量注记 3 行 | `ROADMAP.md` R66 挂账三行加「R67 批 1 认领」标记（任务 E：未勾 47 条 ≥30，不补新条） |

*R67 规划线 ｜ 2026-11-22 05:58 ｜ 道莅工控代码库产品总监（主控直跑 R335）*
