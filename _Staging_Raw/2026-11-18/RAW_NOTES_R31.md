# R31 狩猎留痕（2026-11-18）

## 1. 检索结论：**零检索轮（WebSearch 0/2 次）**

理由：
1. 本轮 20 件中 **8 件来自源矩阵既有 ◐ 行「待挖」子项**（NE107 仲裁件 / LGF Math 三角·极分解 / T1-2 ROOM_CONTROL 2 件 / T1-6 外部编码器族 2 件 / 半导体 ESC 电流监视 / T1-7 PROFINET 诊断），全部为**既有源组内已拆粒度的收口件**，语义域与参数域已在历轮 RAW_NOTES 留痕，无需重复抓取外部源。
2. 其余 12 件来自 **ROADMAP §7 行业池真实空位**（经 python 全量比对 registry 消除 43 条台账滞后后的 214 条真实空位中选取），clean-room 自研线，无外部仓库可指。
3. 配额结论：满足「≥1 个 T2 组件族（NE107 + LGF Math + T1-2）」与「≥1 个 T1 组（T1-6 外部编码器族开族）」；T0 补位 0 件（P0 三条码线经查重证实已注册，属台账滞后，按「不得再造同义变体」红线不派，如实记 0 不虚账——R85 口径）。
4. 与 R24/R25/R30 同口径：零外部仓库抓取、零代码行复制，全部组件为行为定义借用或 clean-room 自研。

## 2. 本轮引用的库内事实源（非外部源）

| 引用点 | 来源 | 说明 |
|---|---|---|
| 539 件 name 基线 | `INDEX_REGISTRY.json` v2.19.0 | python 遍历 components[].name 全量提取，存 `_Staging_Raw/names_r31.txt`（539 行） |
| 码位游标 | `INDEX_REGISTRY.json` components[].code_segment | python 正则逐类取最大槽尾：03_0_→F1 / 05_0_→8E / 04_0_→62 / 01_0_→91（与 DL_Base 共池）/ 02_3_→32，实测非交接值 |
| 台账滞后筛查 | `ROADMAP.md` 270 条未勾选 × registry 539 名 | 43 条已注册未回勾；214 条真实空位 |
| NE107 六态枚举 | T2-8 行 R13 记录（`E_DL_Ne107Status` 唯一属主） | 本轮 HealthArbiter / EscChuckCurrentMon / SlurryStirrerCtrl 只引用不重声明 |
| ROOM_CONTROL 行为定义 | T1-2 行 R25 记录 | 焓值优先切换 / 夜间吹扫两子项，借行为定义零代码复制 |
| 外部编码器语义 | T1-6 行「外部编码器/凸轮动态修调待挖」+ T2-4 行「外部编码器族待挖」 | 主源记 T1-6，T2-4 不重复记账 |
| PROFINET 告警语义 | T1-7 行「PN_ALARM_DIAG 语义待挖」 | 公开规范语义，clean-room，引脚注入不绑厂商变量名 |

## 3. 无外部源因此无许可证条目

本轮未抓取任何外部仓库/网页，无新增许可证结论需要记录。历史源（OSCAT LGPL/CC-BY-SA 语义借用、PLCnext/Beckhoff Apache-2.0 公开资料、NOAA 公共领域公式等）口径沿用各矩阵行既有留痕，不重复登记。

## 4. 查重与淘汰实录（供终审复核）

- 精确匹配 grep（`grep -qx`）逐名核验 20 件：全部 **free**。
- 淘汰件（已存在于 registry，台账滞后）：`FB_DL_MfcFlowCtrl`、`FB_DL_TrackBarcodeTrace`、`FB_DL_CartonErectorStation`、`FB_DL_PalletizerStation`、`FB_DL_StringBarcodeTrace`。
- 淘汰件（未存在但同义变体红线）：`FB_DL_CartonScannerSort`（与已注册条码 trace 族同义）。
- 命名风格自查：无跨子库同音近形撞名；`I_DL_ExternalEncoder` / `FB_DL_ExternalEncoderLatch` 为契约-实现对，与既有 `FB_DL_MarkPositionLatch` 职责边界已在派单规格中强制要求写边界表。

## 5. 遗留事项（不属本轮收口范围）

- ROADMAP 43 条台账滞后需主控回勾（本轮纪律：不改 ROADMAP）。
- `StringToDTL` 仍挂编译债（矩阵 T2-1 Converter 行），不派。
- DL_MathData 162 件偏多，本轮仅 1 件矩阵待挖方向件，后续轮继续压比例。
