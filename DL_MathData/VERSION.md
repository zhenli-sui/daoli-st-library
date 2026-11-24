# DL_MathData — 版本记录 / Version History

> **子库定位 / Role**：Level 0 数学与数据处理层，负责标定、滤波、迟滞判决、校验与缓冲，零外部依赖。
> **兼容平台 / Platforms**：CODESYS V3.5+ ｜ TwinCAT 3 ｜ 汇川 InoProShop ｜ Schneider Machine Expert
> **依赖 / Depends**：仅 `Standard.library`（`ABS` / `MIN` / `MAX` / `SHR` / `R_TRIG`），不引用 `DL_Base` 以外的任何 `DL_` 子库。

---

## v1.32 — 2026-11-22（R71）

- R71 新增 2 件：`FC_DL_AirSpecificVolume`（湿空气比容，饱和压复用属主件常量单源）｜`FC_DL_TriangleSolveSSS`（SSS 解角三闸）。
- R71 点修 1 件：`FB_DL_ScaleRangeWatch` **v1.0.1** 增益零域组态闸（R70 挂账清）。累计 288 件。

---
## v1.31 — 2026-11-21（R59）

R59 新增 8 件：DmsAngleConvert / QuadraticSolve / DtlStringConv / AsciiFrameParse / DataResampler / FftRadix2 / ConductivityTempComp 等，覆盖单位换算、代数求解、时间串、帧解析、重采样与频域。

## 当前版本 / Current Version

| 项 / Item | 值 / Value |
|---|---|
| 子库版本 / Sublibrary Version | **v1.21.0** |
| 组件总数 / Components | **178**（registry 实测口径，R30 新增见下方增量行：161→162） |
| 发布日期 / Release Date | 2026-11-18 |
| 库总版本 / Library Version | 2.30.0 |
| 故障码段 / Error Code Family | **`16#0001_xxxx`**（R13 本批占用 `0141`~`014C` 与 `0221`~`0225`；R14 本批占用 `015A`~`015D` 与 `0227`~`022B`；R15 本批占用 `015E`~`01BD`（24 个域码）与 `024B`~`028B`（10 个后果码）；R16 本批占用 `01C0`~`01E7`（40 个信息级码）与 `028E`~`02C9`（60 个故障级码）；**R17 本批占用 `01E8`~`0207`（10 件常规落点）、改判 `0210`/`0211`/`021B`（3 件撞车改判）、`020E`/`020F` 与故障级 `02CA`~`0305`**；⚠️ R17 收口实测 `0201`/`0202`/`0210`/`0211`/`021B` 与存量件交叉撞车（见 v1.11.0 节码位台账），R18 改判专项待执行） |


## v1.20.0 ｜ 2026-11-18 ｜ R38：2 件（LinearRegression2Var / OscillationIndex）

| # | 组件 / Component | 类型 | 码位 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 3 | FC_DL_LinearRegression2Var | FC | `16#05_0_02` | t2-1-lgf-math | 二元最小二乘回归 + 共线性判据（|r12| 越限判不可辨识，不输出斜率） |
| 4 | FC_DL_OscillationIndex | FC | `16#05_0_03` | t2-4-s7-motion | 回路振荡指数（过零率 × 幅值离散度归一化 0~1），与 CpkIndex 分工：判抖 vs 判偏离 |

> R38 增量行：组件总数 → **178**（registry 实测口径）；库总版本 2.30.0。

## v1.19.0 ｜ 2026-11-18 ｜ R30 校验族补件：1 件

- `FC_DL_ChecksumSum64`：LWORD 数组 64 位累加和校验（模 2^64 自然回绕禁用 MOD + 开数组实测边界 + 空数组/单元素/回绕触发三向量；与 ChecksumSum8 构成 8/64 位宽两件，位宽变体不再扩充）（0001_048A~048D，FC 纯函数 4 槽）。

> R30 增量行：组件总数 161→**162**（registry 实测口径）；源矩阵「校验族 LWORD 累加和」待挖子项收口。

---

## v1.15.0 ｜ 2026-11-16 ｜ R21 数学安全原子 + LWORD 位域/校验 + 文本序列化 15 件 / R21 Math Safety Atoms, LWORD Bit Fields, Checksums and Text Serialization — 15 Components

**批次**：批1 数学安全原子 5 ｜ 批2 LWORD 位域+校验 5（挂 T2-1 LGF Bit Logic / Data Handling / Converter 三子族）｜ 批3 文本序列化 5
**总行数**：本子库本轮 15 件合计 **2,114 行**（全库 20 件 2,802 行）
**机检**：`check_r21.py` 15/15 PASS fail=0（嵌套注释判定升级为非贪婪成对剥离法）
**终审**：本子库抽 5 件，命中 2 件并修复（`FC_DL_DateToIsoString` **严重**·年序除数 146097→146096，`FC_DL_Crc16Generic` 中等·空帧漏输出反射），另 `FC_DL_StringToDint` 轻微修复，三件升 **v1.0.1**，对外引脚零变更
**码位游标（注册表实测）**：信息级推进至 **`045C`** ｜ 故障级推进至 **`03A8`**

| 组件 | 版本 | 类型 | 说明 |
|---|---|---|---|
| `FC_DL_ModPos` | 1.0.0 | FC | 非负取模；负数取余三平台不一致，条件加减归一，零模数闸 |
| `FC_DL_DivLrealSafe` | 1.0.0 | FC | 浮点防御除法唯一出口：微量分母闸 + 非有限闸 + 溢出等价判据 `|分子|/MAX > |分母|`（禁比较已溢出的商） |
| `FC_DL_QuantizeStep` | 1.0.0 | FC | 量化到步长；步长零/负闸，商先判界 |
| `FC_DL_PolyEvalHorner` | 1.0.0 | FC | Horner 多项式求值，系数数组边界检查 |
| `FC_DL_WrapAngleDeg` | 1.0.0 | FC | 角度回绕到 `(-180, 180]`，LREAL 精度归约常数（R51） |
| `FC_DL_LwordBitFieldExtract` | 1.0.0 | FC | LWORD 64 位段提取；移位量归一，宽 64 走常量掩码 |
| `FC_DL_LwordBitFieldInsert` | 1.0.0 | FC | LWORD 位段读改写；先算掩码再读旧值，值真变才计改动 |
| `FC_DL_LwordBitCount` | 1.0.0 | FC | 汉明重计数；定长 64 次循环，无 WHILE |
| `FC_DL_Crc16Generic` | **1.0.1** | FC | **参数化 CRC-16**（poly/init/xorout/入出反射全引脚化）；三组公开向量复算命中；空帧亦过输出反射 |
| `FC_DL_ChecksumSum8` | 1.0.0 | FC | 8 位累加和；帧长超限拒绝不截断 |
| `FC_DL_StringToDint` | **1.0.2** | FC | 整数字符串严格解析：四态机 + 非法位定位 + 升位判界（负域上界分开写）+ 守卫计数（R41 P0-3：038B 出口补 bError 配对） |
| `FC_DL_DwordToHexString` | 1.0.0 | FC | DWORD → 8 位十六进制文本，定宽补零 |
| `FC_DL_ArraySumLreal` | 1.0.0 | FC | LREAL 数组求和；非有限样本剔除 + 部分和复检 |
| `FC_DL_TimeToHmsString` | 1.0.0 | FC | TIME → `HH:MM:SS`；挂 `TIME_TO_DINT` 毫秒口径编译债 |
| `FC_DL_DateToIsoString` | **1.0.1** | FC | DATE → `YYYY-MM-DD`；Hinnant 整数算法 + **回代自校验**；修正年序除数后 2000-02-29 正常输出 |

### 码位台账（R21 新增，本子库 15 件）

| 码位 | 级别 | 语义 | 组件 |
|---|---|---|---|
---

## v1.14.0 ｜ 2026-11-16 ｜ R20 T0 日历/时间族 + 域转换补充 + 字节序 + 字符串化 18 件（T0 快车道零检索）/ R20 T0 Calendar-Time Family, Domain Conversions, Byte Order and Stringification — 18 Components

**变更性质**：MINOR（新增 18 件纯函数），无破坏性变更，无迁移动作。**终审**：8 件高风险抽样，本子库命中 1 件并修复（`FC_DL_LrealToStringTrim` 无穷判据，中等·逻辑，升 v1.0.1）。

### 新增组件（18 件）/ Added Components

| 组件 / Component | 行 | 类型 | 防御要点 / Defense |
|---|---|---|---|
| `FC_DL_DtToDintEpoch` | 105 | 日历 | DATE_AND_TIME → Unix 纪元秒：下域闸先于内建、Y2038 上域**饱和并升故障级**、2035 起信息级邻近告警、负秒第二道防线 |
| `FC_DL_DintEpochToDt` | 91 | 日历 | 纪元秒 → DATE_AND_TIME：负秒与超 Y2038 **双故障闸且不饱和**（返回纪元零点，饱和会伪造时刻毁掉故障证据） |
| `FC_DL_DateToDintDays` | 94 | 日历 | DATE → 自纪元天数：保守容器口径 65535 钳位（信息级），内建返回负天数判容器溢出 |
| `FC_DL_DintDaysToDate` | 88 | 日历 | 天数 → DATE 反向件：负天数 / 超容器域双故障闸，端点 0412 信息级 |
| `FC_DL_TodAddWrap` | 130 | 时间算术 | 当日时刻 + 偏移并回绕归一：**条件加减禁 MOD**（负数取余三平台不一致），输出 `bWrapped` 与圈数 ±1 |
| `FC_DL_TodDiffWrap` | 90 | 时间算术 | 两时刻差并处理跨零点：跨零点加一日折算 + `bCrossMidnight` |
| `FC_DL_TimeAbsSat` | 101 | 时间算术 | TIME 取幅值饱和：`nIn < −2147483647` 单值闸精确命中 INT32_MIN，饱和值经 `DINT_TO_TIME` 落地 |
| `FC_DL_DateAddDays` | 138 | 日期算术 | 日期 ± 天数：溢出**减法预判**（正向 `nWork > MAX − nBase`），±36500 天钳位信息级 |
| `FC_DL_DateDiffDays` | 84 | 日期算术 | 日期差天数：负差如实输出 + 042C 信息级（不钳零，方向信息不丢） |
| `FC_DL_UdintToLintChk` | 95 | 域转换 | UDINT → LINT 升位 + **round-trip 验真**（`bCheckEveryCall` 可关，验真失败判平台 32 位符号扩展） |
| `FC_DL_WordToIntSat` | 92 | 域转换 | WORD → INT：超域双出口——补码解释为负（0416）/ 上饱和 32767（0417），由 `bTwosComplement` 选定 |
| `FC_DL_DwordToIntSat` | 89 | 域转换 | DWORD → INT：上饱和 32767 + `bRequireLossless` 无损模式反升故障级 0342 |
| `FC_DL_LwordToLintSat` | 90 | 域转换 | LWORD → LINT：上饱和 9223372036854775807 + 无损模式反升故障级 0345 |
| `FC_DL_BcdToByte` | 90 | 编码 | BCD → BYTE：半字节 > 9 故障级拦截，满量程 99 信息级（多拨码调试残留） |
| `FC_DL_ByteToBcd` | 85 | 编码 | BYTE → BCD：> 99 按满量程 `16#99` 兜底并升故障级，端点 0/99 信息级 |
| `FC_DL_SwapBytes64` | 88 | 字节序 | 64 位全字节逆序：**拆半区复用 `FC_DL_SwapBytes32`** 再交叉合成 `(LoRev << 32) OR HiRev`，不重实现内核 |
| `FC_DL_DintToStringTrim` | 155 | 字符串化 | 整型字符串化：前导空格修剪 + R37 四步截断样板，目标长度 0 判故障 0357 |
| `FC_DL_LrealToStringTrim` | 191 | 字符串化 | 浮点字符串化：非有限值统一文本 `NaN` / `Inf+` / `Inf-`（信息级、`bValid` 仍 TRUE） |

### 终审修复（v1.0.1）/ Fixed in Final Review

- `FC_DL_LrealToStringTrim` v1.0.0→**v1.0.1**（**中等·逻辑**）：无穷幅值判据阈值 `1.79E308` 落在 LREAL 可表域内，`ABS(fIn) >= 1.79E308` 会把 `[1.79E308, 1.7976E308]` 区间的**合法有限值误判为无穷**并输出 `'Inf+'` → 改双判据：`(fIn − fIn) <> (fIn − fIn)` 精确判据（有限值 x−x 恒为 0，无穷处产 NaN，与 NaN 自反性判据同源）+ 幅值兜底阈值提到 LREAL 最大值（残余仅剩「恰为最大值」单值）。对外引脚零变更。

### 码位台账追加（R20，经终审全库求差断言复核）

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `16#0001_040C` | 信息 | Y2038 邻近告警（2035-01-01 起算告警带），值仍可用 | `FC_DL_DtToDintEpoch` |
| `16#0001_040D` | 信息 | 预留禁用 | — |
| `16#0001_040E` | 信息 | 输入恰为域端点（0 或 2147483647），上游哨兵值嫌疑 | `FC_DL_DintEpochToDt` |
| `16#0001_040F` | 信息 | 预留禁用 | — |
| `16#0001_0410` | 信息 | 天数超保守容器口径 65535，已按容器顶钳位 | `FC_DL_DateToDintDays` |
| `16#0001_0411` | 信息 | 预留禁用 | — |
| `16#0001_0412` | 信息 | 天数恰为域端点（0 或 65535），已如实还原 | `FC_DL_DintDaysToDate` |
| `16#0001_0413` | 信息 | 预留禁用 | — |
| `16#0001_0414` | 信息 | 调用方关闭逐次复核，本拍未验真 | `FC_DL_UdintToLintChk` |
| `16#0001_0415` | 信息 | 预留禁用 | — |
| `16#0001_0416` | 信息 | 超域且按补码解释为负值（升 DINT 再减偏置） | `FC_DL_WordToIntSat` |
| `16#0001_0417` | 信息 | 超域且按上饱和处理（钳位 32767） | `FC_DL_WordToIntSat` |
| `16#0001_0418` | 信息 | 超域已饱和至 32767（`bSatHigh` 可查） | `FC_DL_DwordToIntSat` |
| `16#0001_0419` | 信息 | 预留禁用 | — |
| `16#0001_041A` | 信息 | 超 LINT 域已饱和至 9223372036854775807 | `FC_DL_LwordToLintSat` |
| `16#0001_041B` | 信息 | 预留禁用 | — |
| `16#0001_041C` | 信息 | BCD 值恰为满量程 99（多拨码调试残留） | `FC_DL_BcdToByte` |
| `16#0001_041D` | 信息 | 预留禁用 | — |
| `16#0001_041E` | 信息 | 输入恰为域端点（0 或 99），已如实编码 | `FC_DL_ByteToBcd` |
| `16#0001_041F` | 信息 | 预留禁用 | — |
| `16#0001_0420` | 信息 | 发生午夜回绕（`bWrapped` 与 `nWrapCircles` 可查） | `FC_DL_TodAddWrap` |
| `16#0001_0421` | 信息 | 预留禁用 | — |
| `16#0001_0422` | 信息 | 跨零点区间（已按加一日折算，`bCrossMidnight` 可查） | `FC_DL_TodDiffWrap` |
| `16#0001_0423` | 信息 | 预留禁用 | — |
| `16#0001_0424`~`0425` | 信息 | 预留禁用（`SwapBytes64` 全域双射无信息出口） | — |
| `16#0001_0426` | 信息 | 已修剪前导空格（`bTrimmed` 可查） | `FC_DL_DintToStringTrim` |
| `16#0001_0427` | 信息 | 发生截断且 `bAllowTrunc = TRUE`（`bTruncated` 可查） | `FC_DL_DintToStringTrim` |
| `16#0001_0428` | 信息 | 非有限值已映射统一文本（`bNonFinite` 可查） | `FC_DL_LrealToStringTrim` |
| `16#0001_0429` | 信息 | 发生空格修剪或截断 | `FC_DL_LrealToStringTrim` |
| `16#0001_042A` | 信息 | 偏移超 ±36500 天（±100 年）已钳位 | `FC_DL_DateAddDays` |
| `16#0001_042B` | 信息 | 预留禁用 | — |
| `16#0001_042C` | 信息 | 差值为负（`dateTo` 早于 `dateFrom`），已如实输出 | `FC_DL_DateDiffDays` |
| `16#0001_042D` | 信息 | 预留禁用 | — |
| `16#0001_042E` | 信息 | 输入为负，已取绝对值（`bNegative` 可查） | `FC_DL_TimeAbsSat` |
| `16#0001_042F` | 信息 | 预留禁用 | — |
| `16#0001_0330` | 故障 | 输入时刻早于纪元，返回 0 | `FC_DL_DtToDintEpoch` |
| `16#0001_0331` | 故障 | 结果超 DINT 秒域（Y2038 之后），已饱和至上限 | `FC_DL_DtToDintEpoch` |
| `16#0001_0332` | 故障 | 预留禁用 | — |
| `16#0001_0333` | 故障 | 负纪元秒，返回纪元零点 | `FC_DL_DintEpochToDt` |
| `16#0001_0334` | 故障 | 超 Y2038 秒域，返回纪元零点（**不饱和**） | `FC_DL_DintEpochToDt` |
| `16#0001_0335` | 故障 | 预留禁用 | — |
| `16#0001_0336` | 故障 | 输入日期早于纪元，返回 0 天 | `FC_DL_DateToDintDays` |
| `16#0001_0337` | 故障 | DATE 非法或容器溢出（内建返回负天数） | `FC_DL_DateToDintDays` |
| `16#0001_0338` | 故障 | 预留禁用 | — |
| `16#0001_0339` | 故障 | 负天数（`nDays < 0`） | `FC_DL_DintDaysToDate` |
| `16#0001_033A` | 故障 | 天数超容器域（`nDays > 65535`） | `FC_DL_DintDaysToDate` |
| `16#0001_033B` | 故障 | 预留禁用 | — |
| `16#0001_033C` | 故障 | round-trip 验真失败：平台把中间量经 32 位有符号路径符号扩展 | `FC_DL_UdintToLintChk` |
| `16#0001_033D`~`033E` | 故障 | 预留禁用 | — |
| `16#0001_033F`~`0341` | 故障 | 预留禁用（`WordToIntSat` 只发信息级，故障槽全预留） | — |
| `16#0001_0342` | 故障 | 要求无损却发生饱和 | `FC_DL_DwordToIntSat` |
| `16#0001_0343`~`0344` | 故障 | 预留禁用 | — |
| `16#0001_0345` | 故障 | 要求无损却发生饱和 | `FC_DL_LwordToLintSat` |
| `16#0001_0346`~`0347` | 故障 | 预留禁用 | — |
| `16#0001_0348` | 故障 | 非法 BCD（某半字节 > 9） | `FC_DL_BcdToByte` |
| `16#0001_0349`~`034A` | 故障 | 预留禁用 | — |
| `16#0001_034B` | 故障 | 输入 > 99，已按满量程 `16#99` 兜底 | `FC_DL_ByteToBcd` |
| `16#0001_034C`~`034D` | 故障 | 预留禁用 | — |
| `16#0001_034E` | 故障 | 偏移模长超一日，超出本件收窄域 | `FC_DL_TodAddWrap` |
| `16#0001_034F` | 故障 | 合成路径中间量非域（基准时刻或归一后结果越界） | `FC_DL_TodAddWrap` |
| `16#0001_0350` | 故障 | 预留禁用 | — |
| `16#0001_0351`~`0353` | 故障 | 预留禁用（`TodDiffWrap` 只发信息级） | — |
| `16#0001_0354`~`0356` | 故障 | 预留禁用（`SwapBytes64` 全域双射） | — |
| `16#0001_0357` | 故障 | 目标长度非法（`uTargetMax = 0`，或平台 USINT 上限异常） | `FC_DL_DintToStringTrim` |
| `16#0001_0358` | 故障 | 需要截断但 `bAllowTrunc = FALSE` | `FC_DL_DintToStringTrim` |
| `16#0001_0359` | 故障 | 预留禁用 | — |
| `16#0001_035A` | 故障 | 需要截断但 `bAllowTrunc = FALSE` | `FC_DL_LrealToStringTrim` |
| `16#0001_035B`~`035C` | 故障 | 预留禁用 | — |
| `16#0001_035D` | 故障 | 结果早于纪元，返回纪元日（不饱和） | `FC_DL_DateAddDays` |
| `16#0001_035E` | 故障 | 结果超 DATE 容器域，返回纪元日（不饱和） | `FC_DL_DateAddDays` |
| `16#0001_035F` | 故障 | 预留禁用 | — |
| `16#0001_0360`~`0362` | 故障 | 预留禁用（`DateDiffDays` 只发信息级） | — |
| `16#0001_0363` | 故障 | −MAX−1 的绝对值不可表达，已饱和至正向上限 | `FC_DL_TimeAbsSat` |
| `16#0001_0364`~`0365` | 故障 | 预留禁用 | — |

> **R20 批次 100 槽（20 件 × 5 槽）跨文件零重叠**，终审求差断言复跑通过；`16#0001_` 段游标推进至 **信息级 `0434` / 故障级 `036C`**（与 `DL_Base` 共用同一游标）。
> **口径说明（R20 诚实更正）**：全库并非绝对零重叠——`DL_Algo` 自 R3~R4 起存在 `16#0002_00xx` **公共码子带**（参数越界已钳位等通用语义，被多件刻意共享），与 `0001_` 段的专用码体系不冲突，但「全库零重叠」这一表述在该子带上不成立。已在 `ROADMAP.md §23.1` 挂账审计。

---

## v1.13.0 ｜ 2026-11-16 ｜ R19 Level 0 补位与协议校验收口：TOD 反向对/时间比值/功率 dB 反向/交叉域饱和/Modbus 帧校验 5 件

- `FC_DL_DintMsToTod`：DINT 当日毫秒→TOD 反向转换（与 TodToDintMs 构成双向对，钳 0~86399999 ms）（码位见 .st 头注释码位总账）。
- `FC_DL_TimeRatioCalc`：TIME 比值→LREAL 百分比（除子 tB=0 故障闸，LREAL 承载防溢出）（码位见 .st 头注释码位总账）。
- `FC_DL_RatioToPwrDb`：功率型反向件 dB = 10·log10(P)（与 PwrDbToRatio 构成双向对）（码位见 .st 头注释码位总账）。
- `FC_DL_LintToUdintSat`：LINT→UDINT 交叉域饱和（负值/正向两个独立饱和闸 + bRequireLossless 无损模式）（码位见 .st 头注释码位总账）。
- `FC_DL_ModbusRtuFrameCheck`：Modbus RTU 帧 CRC16 校验与帧完整性判定（码位见 .st 头注释码位总账）。

> `16#0001_` 段游标：信息级下件起点 **040C**（04xx 子带）｜故障级下件起点 **0330**（本轮 Base+MathData 共用，6 件 30 槽）。

---

## v1.12.0 ｜ 2026-11-16 ｜ R18 场景件第 5 轮：仿射变换 + Cpk + CRC-16 三变体 + 二维插值 4 件 / R18 Scenario Lane — 4 Calibration & Checksum Components

**变更性质**：MINOR（新增 4 个组件）+ PATCH（`FC_DL_Crc16Ccitt` 空帧越界修复 v1.0.0→v1.0.1），对外引脚零变更。

### 新增组件（4 件）/ Added Components

| 组件 | 类型 | 一句话功能 | 关键引脚 |
|---|---|---|---|
| `FC_DL_AffineTransformPoint` | FC | 旋转 → 缩放 → 平移一次合成的点变换 | `fRotDeg` / `fY` |
| `FC_DL_CpkIndex` | FC | 样本数组算 Cp/Cpk/均值/样本标准差（n−1 分母） | `uCount` / `fLsl` |
| `FC_DL_Crc16Ccitt` | FC | CRC-16 三变体，`123456789`→`29B1`/`31C3`/`2189` 对拍 | `auData` / `uLen` / `eVari` |
| `FC_DL_InterpolateTable2D` | FC | 8×8 标定网格双线性插值（温压二维补偿表） | `afGridY` / `afValue` |

### 码位台账追加（R18）/ Error Code Ledger Additions (R18)

| 码位 | 级别 | 语义 | 属主 |
|---|---|---|---|
| `16#0001_023D` | 信息 | 长度超 256 已截断，仅校验前 256 字节 | `FC_DL_Crc16Ccitt` |
| `16#0001_023E` | 信息 | 预留禁用（不得挪用） | — |
| `16#0001_0313` | 故障 | 变体枚举值非法（CASE 落 ELSE），返回 0 | `FC_DL_Crc16Ccitt` |
| `16#0001_0312` / `0314` | 故障 | 预留禁用（不得挪用） | — |

> 其余 3 件码位以注册表 `code_segment` 为准；本轮信息级总区间 `0235`~`0244`、故障级 `0306`~`0314`，全库跨文件重叠复测 = 0。

## v1.11.0 ｜ 2026-11-16 ｜ R17 T0 纯函数第 4 轮：对数/dB + TIME/TOD + 精度/饱和 + LWORD 精度防御包装 16 件 / R17 T0 Pure-Function Lane #4 — 16 Defensive Wrappers

**变更性质**：MINOR（新增 16 个组件），无破坏性变更，无迁移动作。终审 **16/16 件级零缺陷 PASS**（LogBaseEx 底数退化闸 + 除子复判双保险；AmpDb/PwrDb 20/10 因子分型，功率型硬限 380 dB 按 REAL 域可表性反算；TimeToDintMs/LrealSecToTime 先判后算；DintMsToTime 无上域闸论证留档；LintToDintSat 下界 −DL_DINT_MAX−1 计算式；RealToLintSat/LrealToLintSat 升位比较 + TRUNC 向零；LwordToLrealChk 2^53 精度口径）。机检 16 规则 16/16 PASS fail=0。

### 新增组件（16 件）/ Added Components

| 批 | 组件 / Component | 类型 | 防御要点 / Defense |
|---|---|---|---|
| 批1 对数/dB | `FC_DL_LogEx` | FC | 非有限 + fIn ≤ 0 双故障闸，委托内建 LOG |
| 批1 对数/dB | `FC_DL_LogBaseEx` | FC | 换底公式 LN(fIn)/LN(fBase)；底数退化闸（\|fBase−1\|<1E-6）+ 除子复判双保险，绝不执行除法 |
| 批1 对数/dB | `FC_DL_AmpDbToRatio` | FC | 10^(dB/20)，±400 dB 双侧饱和至 1.0E±20，EXPT 结果复检复用信息码 |
| 批1 对数/dB | `FC_DL_RatioToAmpDb` | FC | 20·log10(A)，比值 ≤ 0 域闸，结果钳 ±400 dB |
| 批1 对数/dB | `FC_DL_PwrDbToRatio` | FC | 10^(dB/10)，硬限 380 dB（10^±38 在 REAL 域可表；400 dB 对应 10^40 不可表） |
| 批2 TIME/TOD | `FC_DL_TimeToDintMs` | FC | TIME 域先与 2147483647 ms 比较（先判后算），负结果钳 0 |
| 批2 TIME/TOD | `FC_DL_DintMsToTime` | FC | 负值钳 T#0S；无上域闸（DINT 正域 < TIME 域 4294967295 ms，论证留档） |
| 批2 TIME/TOD | `FC_DL_TimeToLrealSec` | FC | 负 TIME 照转仅记录（观测语义），除子 1000.0 编译期恒非零 |
| 批2 TIME/TOD | `FC_DL_LrealSecToTime` | FC | 非有限故障闸 + 负值钳 0 + 上界 4294967.295 s 先判后饱和 |
| 批2 TIME/TOD | `FC_DL_TodToDintMs` | FC | 标准链 TOD_TO_TIME→TIME_TO_DINT，结果钳 0~86399999 ms（24h−1ms） |
| 批3 精度/饱和 | `FC_DL_DintToRealChk` | FC | \|nIn\| > 2^24 精度告警（只告警不钳位），双侧比较禁 ABS 单侧式 |
| 批3 精度/饱和 | `FC_DL_UdintToRealChk` | FC | nIn > 2^24 精度告警；无符号负值分支由类型系统排除 |
| 批3 精度/饱和 | `FC_DL_LintToDintSat` | FC | 双侧饱和：LINT 域先判后转，下界 −DL_DINT_MAX−1 计算式禁负字面量直写 |
| 批3 精度/饱和 | `FC_DL_RealToLintSat` | FC | 升位先行（REAL 域界不可精确表示）+ TRUNC 向零 + 双侧饱和 |
| 批3 精度/饱和 | `FC_DL_LrealToLintSat` | FC | 与 RealToLintSat 同口径双版本（IEC 无 ANY_REAL 泛型，职责边界留档） |
| 批3 精度/饱和 | `FC_DL_LwordToLrealChk` | FC | nIn > 2^53 精度告警；无符号位串单侧比较 |

### 码位台账追加（R17 收口实测口径，全库正则复测）/ Error Code Ledger Additions (R17, registry-regex-verified)

| 码位 | 级别 | 语义 / Meaning | 组件 | 状态 |
|---|---|---|---|---|
| `16#0001_01E8`~`0201` | 信息 | 批1/批2 十件信息级逐件 2 槽（含预留） | LogEx~LintToDintSat | ⚠️ `0201` 与存量 `FC_DL_DayOfWeekCalc` 信息级撞车 |
| `16#0001_0202` | 信息 | 域外饱和按符号 | `FC_DL_RealToLintSat` | ⚠️ 与存量 `FB_DL_TimeWindowCheck` 信息级撞车 |
| `16#0001_0210` | 信息 | 预留禁用（原拟 0203 改判） | `FC_DL_RealToLintSat` | ⚠️ 与存量 `FB_DL_EventCounter` 故障级撞车 |
| `16#0001_0211` | 信息 | 域外饱和按符号（原拟 0204 改判） | `FC_DL_LrealToLintSat` | ⚠️ 与存量 `FB_DL_ModuloCounter` 故障级撞车 |
| `16#0001_021B` | 信息 | 预留禁用（原拟 0205 改判） | `FC_DL_LrealToLintSat` | ⚠️ 与存量 `FB_DL_BitArrayChangeWatch` 故障级撞车 |
| `16#0001_020E`/`020F` | 信息 | 2^53 精度告警 / 预留 | `FC_DL_LwordToLrealChk` | 空闲独占 |
| `16#0001_02CA`~`0305` | 故障 | 批1~批3 故障级逐件 3 槽（含预留） | 十件 | 空闲独占（收口实测全段无存量占用） |

> **R18 改判专项（实测落点全空闲，待执行）**：LintToDintSat `0201→0220`、RealToLintSat `0202→0215`/预留 `0210→0216`、LrealToLintSat `0211→0213`/预留 `021B→0214`（另 DL_Base ShrLwordEx `0208→0219`、ShlLwordEx `021D→0217`/`021E→0218`）。改判后 R18 新件码位游标：**信息级 `0221` 起、故障级 `0306` 起**。**立规 R61：码位游标必须以注册表正则实测为准，不得沿用上一轮战报口头交接值。**

---

## v1.10.0 ｜ 2026-11-16 ｜ R16 T0 变体线开线：饱和转换/整数+BCD/泛型选择/LIMIT+TIME 防御包装 20 件 / R16 T0 Variant Lane — 20 Defensive Wrappers

**变更性质**：MINOR（新增 20 个组件），无破坏性变更，无迁移动作。对应 Round 16「T0 变体线开线」定位（IEC 标准语义 clean-room，零检索、零 `_Staging_Raw` 源码备份，R14 三判据准入）。全部为 FC_ 纯函数，输出契约统一 `eErr / bError / bValid` 三件套。机检 16 规则 20/20 PASS（fail=0）；总监终审抽查 8 件高风险件（TimeAddSat / TimeSubSat / TimeDivChk / TimeScaleSat / SelEx / BcdToUdint / UdintToBcd / LintToLrealChk）人工逻辑复核**零缺陷 PASS**。本批错误码由 R50 三段样板内嵌派单前置规范，注册时零改码（R59 验证生效）。

### 新增组件 / Added（合计 1,436 行）

| # | 组件 / Component | 类型 | 族 | 码位 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 70 | `FC_DL_LrealToRealSat` | FC | 饱和转换 | `01C0`/`028E` | LREAL→REAL 双侧饱和 ±3.402823E38 + 非有限故障闸 / dual-side saturating LREAL→REAL |
| 71 | `FC_DL_LrealToDintSat` | FC | 饱和转换 | `01C2`/`0291` | LREAL→DINT 域判定先行 + TRUNC 向零截断 / domain-first clamp then trunc |
| 72 | `FC_DL_RealToUdintSat` | FC | 饱和转换 | `01C4`/`01C5`/`0294` | REAL→UDINT 负值钳零 + 超上界钳 16#FFFFFFFF / negative clamps to zero |
| 73 | `FC_DL_RealToUintSat` | FC | 饱和转换 | `01C6`/`01C7`/`0297` | REAL→UINT 双侧饱和（R56 双分支范式）/ dual-side saturating REAL→UINT |
| 74 | `FC_DL_RealToByteSat` | FC | 饱和转换 | `01C8`/`01C9`/`029A` | REAL→BYTE 双侧饱和（串口/PWM 字节域）/ dual-side saturating REAL→BYTE |
| 75 | `FC_DL_DintToUintSat` | FC | 整数+BCD | `01CA`/`01CB` | DINT→UINT 双侧饱和钳位 / dual-side saturating DINT→UINT |
| 76 | `FC_DL_UdintToDintChk` | FC | 整数+BCD | `01CC` | UDINT→DINT 上界单侧饱和 2147483647 / upper-bound clamp UDINT→DINT |
| 77 | `FC_DL_LintToLrealChk` | FC | 整数+BCD | `01CE` | LINT→LREAL 超 2^53 精度告警，双侧比较规避 ABS 极值回绕（R55）/ 53-bit precision notice |
| 78 | `FC_DL_BcdToUdint` | FC | 整数+BCD | `02A6` | 8 位 BCD→UDINT 逐半字节校验，校验域 k=0..7 按容器位宽收敛（R57）/ per-nibble validated BCD decode |
| 79 | `FC_DL_UdintToBcd` | FC | 整数+BCD | `01D2` | UDINT→BCD 超 99999999 饱和至 16#99999999（与 R9 WordToBcd 口径一致，域扩 4 位）/ saturating BCD encode |
| 80 | `FC_DL_SelEx` | FC | 泛型选择 | `01D4`/`02AC` | 双通道选择：未选中通道异常仅信息级记录不影响本拍输出 / SEL with idle-channel advisory |
| 81 | `FC_DL_Mux2Ex` | FC | 泛型选择 | `01D6`/`02AF` | MUX2：选择子越界钳 1 + 选中通道非有限故障闸 / MUX2 with clamped selector |
| 82 | `FC_DL_Mux4Ex` | FC | 泛型选择 | `01D8`/`02B2` | MUX4：IF/ELSIF 链实现 MUX 语义 + 越界钳 3 / MUX4 via IF/ELSIF chain |
| 83 | `FC_DL_MinEx` | FC | 泛型选择 | `02B5` | MIN 防御包装：非有限输入故障闸 / defensive MIN |
| 84 | `FC_DL_MaxEx` | FC | 泛型选择 | `02B8` | MAX 防御包装：非有限输入故障闸 / defensive MAX |
| 85 | `FC_DL_LimitEx` | FC | LIMIT+TIME | `01DE`/`02BB` | LIMIT 防御包装：上下限倒置自动交换（信息级 01DE）+ 三输入非有限闸 / LIMIT with auto-swap |
| 86 | `FC_DL_TimeAddSat` | FC | LIMIT+TIME | `01E0` | TIME 加法：减法比较溢出预判（先判后算，R54）饱和 DL_TIME_MAX / add with subtract-compare pre-check |
| 87 | `FC_DL_TimeSubSat` | FC | LIMIT+TIME | `01E2` | TIME 减法：负差钳零（TIME 无符号语义防御）/ subtract with clamp-to-zero |
| 88 | `FC_DL_TimeScaleSat` | FC | LIMIT+TIME | `01E4`/`01E5` | TIME 乘法：除法比较溢出预判（R54）+ 负乘子钳零 / multiply with divide-compare pre-check |
| 89 | `FC_DL_TimeDivChk` | FC | LIMIT+TIME | `01E6`/`02C7` | TIME 除法：除零故障闸 + 负除子 DINT 升位取模长（R55 先例）/ divide with zero guard |

### 码位台账追加（R16，经源码反算回写 code_segment，全库唯一性断言 NONE 重复）/ Error Code Ledger Additions (R16)

| 段 / Segment | 级别 | 范围 / Range | 数量 | 说明 / Note |
|---|---|---|---|---|
| `01C0`~`01E7` | 信息级 | 40 码 | 40 | 饱和/钳位/精度告警/负值钳零/选择子越界/倒置交换/TIME 溢出饱和与钳零等正常防御记录；含各件预留禁用槽（每件固定 5 槽口径） |
| `028E`~`02C9` | 故障级 | 60 码 | 60 | 非有限输入（NaN/±INF）、非法 BCD 半字节、除零故障等；含各件预留禁用槽 |

> **收口教训（R58 规则）**：manifest 生成器按「每件有效码槽」顺延计码，与源码实际的「每件固定 5 槽（含预留）」口径漂移，注册表 code_segment 先错后以源码反算修正（`_Staging_Raw/2026-11-16/fix_codeseg_r16.py`）。**规则化：code_segment 必须以源码为唯一事实源反算生成。** 下轮码位游标：信息级 `01E8` 起、故障级 `02CA` 起。

---

## v1.9.0 ｜ 2026-11-16 ｜ R15 T0 标准函数包装族开族并七组收口（20 件）/ R15 T0 Standard-Function Wrapper Family, 20 Components

**变更性质**：MINOR（新增 20 个组件），无破坏性变更，无迁移动作。对应 Round 15「T0 快车道收口」定位（IEC 标准语义 clean-room，零检索、零 `_Staging_Raw` 源码备份）。全部为 T0 四段式防御包装（R45 范式：预置 → 域闸门早退 → 委托内建 → 非有限复检）。**T0 源矩阵七组至此全部收口（7/7 ✔）**。机检 16 项 20/20 PASS（fail=0）；总监终审重点抽查 6 件（Atan2Ex / ExptEx / StringFindEx / StringInsertEx / StringDeleteEx / StringConcatEx）人工时序复核零缺陷，结论 PASS。本批错误码经派单样板（R50）前置规范：统一 `eErr : UDINT` + `16#0001_XXXX`，无 `uErrorId : UINT` 残留。

### 新增组件 / Added（合计 1,966 行）

| # | 组件 / Component | 类型 | 行数 | 码位 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 50 | `FC_DL_AbsEx` | FC | 80 | `015E`/`022C` | 绝对值防御包装：非有限复检 + 上溢钳位（|−MAXREAL| 场景）/ defensive absolute value |
| 51 | `FC_DL_SinEx` | FC | 87 | `0163` | 正弦防御包装：超大角 2π 归约（LREAL 常数，R51）/ defensive sine with LREAL-precision range reduction |
| 52 | `FC_DL_CosEx` | FC | 87 | `0168` | 余弦防御包装：同 SinEx 归约口径 / defensive cosine |
| 53 | `FC_DL_AsinEx` | FC | 78 | `016D` | 反正弦防御包装：[−1,1] 域钳位/归零 / defensive arcsin |
| 54 | `FC_DL_AcosEx` | FC | 79 | `0172` | 反余弦防御包装：[−1,1] 域钳位/归零 / defensive arccos |
| 55 | `FC_DL_AtanEx` | FC | 76 | `0177` | 反正切防御包装：全实数域、NaN/Inf 降级 / defensive arctan |
| 56 | `FC_DL_Atan2Ex` | FC | 107 | `017C`/`017E`/`024B` | 四象限反正切：双零 eps=1.0E-12 判据、y=0&x<0 → +π（R52 返回域 (-π, π]）、结果 NaN 复检 / quadrant atan2 with explicit y=0 attribution |
| 57 | `FC_DL_ExpEx` | FC | 84 | `0181`/`024F` | 指数防御包装：e^x 上溢/下溢预判钳位（饱和降级 bValid=TRUE）/ defensive exponential |
| 58 | `FC_DL_ExptEx` | FC | 137 | `0186`/`0187`/`0254`/`0255` | 幂防御包装：零底负幂、负底非整数幂（frac 容差 1E-9）、`exp*LN(|base|)` 溢出预判（零底闸前置，LN 恒安全）/ defensive power with overflow pre-check |
| 59 | `FC_DL_TruncEx` | FC | 76 | `018B`/`0259` | 截断取整防御包装：DINT 域外钳位 / defensive trunc |
| 60 | `FC_DL_FloorEx` | FC | 73 | `0190`/`025E` | 向下取整防御包装：DINT 域外钳位 / defensive floor |
| 61 | `FC_DL_CeilEx` | FC | 73 | `0195`/`0263` | 向上取整防御包装：DINT 域外钳位 / defensive ceil |
| 62 | `FC_DL_StringLenEx` | FC | 73 | 无（仅 0000） | 串长防御包装：bTrimTrailingSpace 尾空格口径可选 / defensive length with trailing-space option |
| 63 | `FC_DL_StringLeftEx` | FC | 91 | `019F`/`01A1` | 取左子串防御包装：nCount<=0 无效、越界钳串长 / defensive left |
| 64 | `FC_DL_StringRightEx` | FC | 96 | `01A4`/`01A6` | 取右子串防御包装：nCount<=0 无效、越界钳串长 / defensive right |
| 65 | `FC_DL_StringConcatEx` | FC | 111 | `0277` | 安全拼接：R37/R49 范式先置 bTruncated 再钳 B 段配额，杜绝静默回夹 / safe concat with explicit truncation flag |
| 66 | `FC_DL_StringInsertEx` | FC | 144 | `01AE`/`027C` | 定位插入：位置合法域 [1, len+1] 钳位、三段复制各带 255 越界守卫、显式 `$00` 终结（R53）/ positional insert with three-part copy guards |
| 67 | `FC_DL_StringDeleteEx` | FC | 144 | `01B3`/`01B5` | 区间删除：nCount<=0 短路原样返回、区间尾截到串尾、后段按下标重算前移 / interval delete with rear compaction |
| 68 | `FC_DL_StringFindEx` | FC | 127 | `01B8`/`01BA` | 子串查找：空针前置拦截、外层上界 len−lenN+1、失配断内层回退外层（无死循环）、未找到非错误 / substring find with bounded two-layer loop |
| 69 | `FC_DL_StringReplaceAtEx` | FC | 143 | `01BD`/`028B` | 定位覆盖替换：总长与源串一致、覆盖串超尾截断先置标志（R37）/ overwrite-at replace, length invariant |

---

## v1.7.0 ｜ 2026-11-16 ｜ R13 CRC8 子族开族 + 带校验字符串解析 + 定宽字段填充 + Matrix 子族开族（LGF Data Handling / Math 组落地，4 件）/ R13 CRC8, Validated String Parse, Fixed Field & Matrix Inverse

**变更性质**：MINOR（新增 4 个组件），无破坏性变更，无迁移动作。对应 Round 13「校验位宽补齐 + 数值解析可信化 + 定长串收口 + 矩阵子族开族」定位（来源标签 lgf-datahandling / lgf-math / oscat-network，clean-room 未复制源码）。终审 **4 件中 3 件零修改 PASS，1 件文档级修复后 PASS**（`FC_DL_Matrix3Inverse` v1.0.1 仅头注释 V7 数值勘误）；泳道 B 附**总监独立验算**：Python 复现 6 件算法、41 项断言全过——CRC8 三变体 `"123456789"` 实算 `F4`/`4B`/`B4` 与公开 CRC 目录三方一致（规格向量无 R1 式错误），位旋转 3000 组对拍、矩阵 500 组 A×A⁻¹≈I 对拍全数一致。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 39 | `FC_DL_Crc8` | FC | 233 | 1.0.0 | lgf-datahandling / oscat-network | **CRC8 子族开族**：参数化 MSB-first 逐位算法（无查表、无状态、内存恒定），覆盖 ATM（16#07/00/00，SMBus 与传感器帧）、SAE-J1850（16#1D/FF/FF，汽车与变频器状态帧）、HITAG（16#1D/FF/00）三变体；截断先置标志再钳长（R37）；变体非法回退 ATM 而非返回零，结果可与厂家工具对表；反射型 MAXIM-DOW 明确不立另件 / Parameterised MSB-first CRC-8 with three variants |
| 40 | `FC_DL_StringToLReal` | FC | 417 | 1.0.0 | lgf-datahandling | 定长 ASCII 严格解析成 LREAL：逐字符七态状态机推进，不用平台隐式串转数值——非法输入行为三平台一致、报出**首个非法字符位置**、前缀合法尾部夹脏时仍给前缀值；出口夹域绝不输出无穷或非数；指数域 ±38 保护、有效数字 18 位封顶 / Strictly validated decimal text parsing with first-bad-position reporting |
| 41 | `FC_DL_StringFixedField` | FC | 245 | 1.0.0 | lgf-datahandling | 定宽字段填充与对齐（**R37 全库样板件**）：左/右对齐 + 指定填充字符装进定宽字段，「先取长度 → 比较 → 先置截断标志 → 最后写缓冲」四步顺序可全库照抄；截断与拒绝双路均显式报码，消灭「字段看着对、内容被砍一半、日志零记录」事故；宽度是契约参数不钳位 / Fixed-width field assembly, the library-wide R37 reference |
| 42 | `FC_DL_Matrix3Inverse` | FC | 291 | **1.0.1** | lgf-math | **Matrix 子族开族**：3×3 实数矩阵伴随矩阵法解析求逆，九个分子为定长表达式（无主元选取、无嵌套循环，同输入同平台逐拍可复算）；**相对奇异判据** `|det| ≤ eps × maxAbs³`——绝对阈值在毫米级与微米级标定矩阵量纲差一千倍时必然失守，相对判据两量纲通用；非有限元素整件拒绝，失败路径逆矩阵整体置 0 不输出毒值；v1.0.1 头注释 V7 条件数粗估勘误（误记 1.0E-18 → 实算 1.0E-6），判定逻辑零变化 / Three-by-three adjugate inverse with a scale-invariant singularity test |

### 故障码台账追加（R13 码位登记，经终审全库复核 0 重叠）/ Error Code Ledger Additions (R13)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0001_0141` | 信息级 | 输入长度超 128 已显式截断（先置标志后钳长） | FC_DL_Crc8 |
| `0001_0142` | 信息级 | CRC8 变体非法，回退 ATM 参数计算 | FC_DL_Crc8 |
| `0001_0143` | 信息级 | 文本空或无有效数字 | FC_DL_StringToLReal |
| `0001_0144` | 信息级 | 尾随非法字符（前缀值保留） | FC_DL_StringToLReal |
| `0001_0145` | 信息级 | 结果已夹进出口域 | FC_DL_StringToLReal |
| `0001_0146` | 信息级 | 指数超出 ±38 保护域，值落有限上界 | FC_DL_StringToLReal |
| `0001_0147` | 信息级 | 源超宽已按允许截断（先置标志后写缓冲） | FC_DL_StringFixedField |
| `0001_0148` | 信息级 | 源超宽且不允许截断，拒绝构造（事实留痕） | FC_DL_StringFixedField |
| `0001_0149` | 信息级 | 填充串为空，退回空格 | FC_DL_StringFixedField |
| `0001_014A` | 信息级 | 矩阵病态但已给出逆（精度不保） | FC_DL_Matrix3Inverse |
| `0001_014B` | 信息级 | 矩阵含非有限元素，整件拒绝 | FC_DL_Matrix3Inverse |
| `0001_014C` | 信息级 | 相对容差非正，按默认 1.0E-9 继续 | FC_DL_Matrix3Inverse |
| `0001_0221` | 故障级 | 有效字节数小于 1 | FC_DL_Crc8 |
| `0001_0222` | 故障级 | 小数点重复（语法错误） | FC_DL_StringToLReal |
| `0001_0223` | 故障级 | 解析结果非有限 | FC_DL_StringToLReal |
| `0001_0224` | 故障级 | 字段宽度域外（0 或超 255，不钳位） | FC_DL_StringFixedField |
| `0001_0225` | 故障级 | 矩阵奇异（相对判据），逆矩阵全 0 | FC_DL_Matrix3Inverse |

---

## v1.6.0 ｜ 2026-11-15 ｜ R12 字符串全替换 + 报文分词流 + 数组逐项比对 + 太阳位置 + Modbus 异常帧（LGF Data Handling / Comparator / Date and Timer 三组落地，5 件）/ R12 String, Token Stream, Array Diff, Solar Position & Modbus Exception

**变更性质**：MINOR（新增 5 个组件），无破坏性变更，无迁移动作。对应 Round 12「字符串流 + 数组批量比对 + 天文钟 + 协议异常帧」定位（来源标签 lgf-datahandling / lgf-comparator / lgf-datetimer / oscat-network，clean-room 未复制源码）。终审 **5 件中 2 件零修改 PASS，3 件修复后 PASS**（`FC_DL_StringReplaceAll` 1 致命 1 注释级、`FB_DL_StringTokenStream` 1 严重、`FC_DL_ArrayDiffSummary` 1 中等，均升 v1.0.1）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 34 | `FC_DL_ArrayDiffSummary` | FC | 204 | **1.0.1** | lgf-comparator | **v1.0.1** —— 两组实数数组按统一绝对容差逐项比对：同出超差项数、首个超差下标、最大绝对偏差及其下标、一致性结论与非有限标志；非有限项剔除不参与统计，负容差取绝对值、零容差回落最小容差；v1.0.1 补「差本身溢出为无穷」的二次判据（R36 同源） / Per-item array diff against a unified tolerance with first offender and max deviation |
| 35 | `FC_DL_StringReplaceAll` | FC | 264 | **1.0.1** | lgf-datahandling | **v1.0.1** —— 定长串内全部出现的子串替换：一次调用给替换次数、结果串与截断标志；游标「跳到插入段之后」的推进律从算法层消灭「替换串含模式串」的自增长死循环，另叠次数上限与守卫计数两道闸；v1.0.1 补拼接超串型上限的显式截断判据（R37） / Replace-all over a fixed-length string with cursor advance and dual guards |
| 36 | `FB_DL_StringTokenStream` | FB | 317 | **1.0.1** | lgf-datahandling | **v1.0.1** —— 报文分词流：帧装载 + 取下一段请求的四相状态机，空段仍占序号（字段序号对齐的唯一保证），段长超限截断、段数超限锁故障、分隔符为空硬闸；帧变化判据用逐字符比较（等长改写无法靠长度判出）；v1.0.1 取段相位改以锁存副本长度切片（R38） / Tokenising stream over a latched frame copy with four phases |
| 37 | `FC_DL_SolarPositionCalc` | FC | 301 | 1.0.0 | lgf-datetimer | 太阳位置计算：由年月日时分、经纬度与时区偏移算赤纬、时角、高度角、方位角与均时差，满分日按当月实际天数校验（含闰年）；天顶不可辨区按阈值显式兜底而非输出跳变方位；零浮点判等、零平台时钟读取 / Solar position from civil time, latitude and longitude with leap-year date check |
| 38 | `FC_DL_ModbusExceptionParse` | FC | 210 | 1.0.0 | oscat-network | Modbus 异常帧解析：功能码最高位判异常帧，还原原始功能码、给异常码中文名、严重度分级（提示 / 告警 / 故障）与「可原样重试」标志，驱动上层重试策略；未定义异常码与非法功能码给显式兜底而非空串 / Modbus exception frame parsing with severity grading and retry advice |

### 故障码台账追加（R12 码位登记，经终审全库复核）/ Error Code Ledger Additions (R12)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0001_0130` | 信息级 | 模式串为空（长度 0），不允许替换，返回 0 次 | FC_DL_StringReplaceAll |
| `0001_0131` | 信息级 | 达到替换次数上限，结果不完整 | FC_DL_StringReplaceAll |
| `0001_0132` | 信息级 | 结果被长度上限截断（含拼接超串型上限 255），`bTruncated` 置位 | FC_DL_StringReplaceAll |
| `0001_0133` | 信息级 | 次数上限或结果长度参数越界已钳位 | FC_DL_StringReplaceAll |
| `0001_0134` | 信息级 | 比对项数越界已钳位到 1~64 | FC_DL_ArrayDiffSummary |
| `0001_0135` | 信息级 | 容差非法（非有限或过小）已回退到最小容差 | FC_DL_ArrayDiffSummary |
| `0001_0136` | 信息级 | 年月时分 / 经纬度 / 时区偏移越界，本拍判定不可信 | FC_DL_SolarPositionCalc |
| `0001_0137` | 信息级 | 日超出当月实际天数（含闰年判定），判定不可信 | FC_DL_SolarPositionCalc |
| `0001_0138` | 信息级 | 功能码非法或异常码未定义，帧可解释但语义未知 | FC_DL_ModbusExceptionParse |
| `0001_0139` | 信息级 | 本帧非异常帧（功能码最高位未置位） | FC_DL_ModbusExceptionParse |
| `0001_013A` | 信息级 | 切出空段（连续分隔符），序号照占 | FB_DL_StringTokenStream |
| `0001_013B` | 信息级 | 段长超限已截断，`sToken` 为前缀 | FB_DL_StringTokenStream |
| `0001_013C` | 信息级 | 末段之后再次取段，序号不回绕、内容置空 | FB_DL_StringTokenStream |
| `0001_021C` | 故障级 | 分隔符为空（`FIND` 空模式跨平台行为不一致），硬闸锁存 | FB_DL_StringTokenStream |
| `0001_021D` | 故障级 | 段数达到上限，继续解析会推过调用方预期，锁存并掐断游标 | FB_DL_StringTokenStream |
| `0001_021E` | 故障级 | 非法相位兜底（枚举被在线改坏或跨版本不兼容） | FB_DL_StringTokenStream |

**号段占用声明**：本批 `DL_MathData` 占用信息级 `0001_0130`~`0001_013C`（`0125`~`012F` 归 `DL_Base` 本批）与故障级 `0001_021C`~`021E`。两库共享 `16#0001_xxxx` 段，本批**先由 `DL_Base` 取 0125，`DL_MathData` 自 0130 起**，中间 012D~012F 归 `DL_Base` 的位图监视件，全序无空洞、无重叠（终审脚本复跑断言）。

### 缺陷修复 / Fixed

| 组件 / Component | 级别 | 缺陷 / Defect | 修复 / Fix |
|---|---|---|---|
| `FC_DL_StringReplaceAll` | **致命** | 结果拼接后超过串型上限 255 时被 `LEFT` 静默回夹：`bTruncated` 恒 FALSE、`uErrorId` 永不置 `0132`。验收 V5（源长 250 + 5 次 10 字符替换 → 300 字符）实测 `bTruncated=FALSE / 无事件码 / LEN=255`，与规格期望全不符；现场后果是报表模板替换被裁掉尾部字段而调用方判定「结果完整」，属静默丢字段 | 在 `CONCAT` 之前预判 `LEN(sHead) + nLenRep + LEN(sTail) > DL_STR_MAX`，超限即置 `bTruncated := TRUE` 并按首事件优先置 `0132`；回夹保留为溢出护栏 |
| `FB_DL_StringTokenStream` | **严重** | 取段相位用**实时帧长度**做边界与 `MID` 长度，却对**锁存副本**切片。调用方在「请求拍 → 取段拍」之间改写 `sFrame`：新帧更长时切出 `bValidToken=TRUE` 的空段；新帧更短时把仍有内容的锁存帧判成「已读完」并吐 `013C` | 取段相位入口重算 `nFrameLen := LEN(sFrameLatched)`；实时长度只留给帧变化检测与 ELSE 兜底掐断 |
| `FC_DL_ArrayDiffSummary` | 中等 | 两项有限值相减仍可能溢出为无穷（近满量程异号），该偏差直接参与竞争 → `fMaxDev` 被污染为无穷、`nMaxDevIdx` 指向该项 | 有限分支内补二次判据：`IF fDev > DL_FINITE_MAX` 则按非有限处置（计超差、记首差下标、`fDev := 0.0`、不参与竞争） |
| `FC_DL_StringReplaceAll` | 注释级 | `bValid` 兼「参数合法」与「结果可采信」两义，注释与规格 3.6 定义不一致 | 保留实现语义（不完整结果不可采信是本库统一口径），引脚注释改为「模式串非空、长度参数未钳位且未达次数上限」，并在头注释登记「规格偏离留档 D1」 |

### 变更说明 / Change Notes

- **字符串族三件分工**：`FC_DL_StringTrim`（首尾空白）/ `FC_DL_StringSplit`（单字符分隔一次性拆分、保留空字段）/ **本批 `FC_DL_StringReplaceAll`**（全部替换）/ **本批 `FB_DL_StringTokenStream`**（跨拍流式取段）。前两件是纯函数、一次给全结果；后两件分别是「一次改全串」与「逐拍取一段」，适用报文长度与协议节奏不同的场景，互不替代。
- **`FC_DL_PercentileLReal` 的跨段借用码维持原状**：`0002_000E` 仍为全库唯一跨段借用（观察项 O-R11-2），本批未新增任何段外码。
- **红线状态**：R1~R44 全部通过，机检 0 命中；全库码位跨文件重叠 = 0。

---

## v1.5.0 ｜ 2026-11-15 ｜ R11 区间关系 / 三维距离 / 可复现随机 / 分位数（LGF Math 与 Comparator 组续深，4 件）/ R11 Range, Geometry, Random & Percentile

**变更性质**：MINOR（新增 4 个组件），无破坏性变更，无迁移动作。对应 Round 11 泳道 A「LGF Math / Comparator 组续深」（来源标签 lgf-math / lgf-comparator，仅借鉴组粒度与参数域，clean-room 未复制源码）。终审 **PASS 14 件批次中的本库 4 件全部零修改 PASS**。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 30 | `FC_DL_RangeOverlapCheck` | FC | 254 | 1.0.0 | lgf-comparator | 两个实数区间的几何关系判定（相离 / 仅端点相接 / 部分重叠 / 包含 / 相等，六值枚举）：四点入参、无序端点自动对调、判定次序写死（有限性闸门 → 归一 → 相等 → 相离 → 相接 → 包含 → 部分重叠，不可调换）；输出重叠长度恒非负、`bTouching` 与开闭位由调用方合成「相接点是否属交集」；NaN 用区间比较取反识别，不判等 / Two-interval relation judge with fixed decision order |
| 31 | `FC_DL_CalcDistance3D` | FC | 227 | 1.0.0 | lgf-math | 三维欧氏距离（平面场景 Z 同填 0.0 即退化，不为凑数拆二维变体）：大数走缩放分支（先除最大分量再开方，规避「大数先平方」中间溢出），`bSaturated` 提示进入置信区；非有限输入返回 0.0 而非 NaN（NaN 会沿调用链污染下游滤波与比较）；同出三分量差供现场判「差在哪个轴」 / 3D Euclidean distance with scale-normalised large-number branch |
| 32 | `FC_DL_RandomNext` | FC | 210 | 1.0.0 | lgf-math | 可复现伪随机（LCG，Numerical Recipes 公开参数）：种子由 `VAR_IN_OUT` 外置回灌，函数本体无状态、可重入；输出半开区间 `[0, 1)` 并给下一拍种子 `uNextSeed`；退化参数（乘子 0 / 增量 0）回退到保底常数并置码，零种子给提示位；上界用容差钳制防 `1.0` 越界 / Stateless LCG random with externally carried seed |
| 33 | `FC_DL_PercentileLReal` | FC | 303 | 1.0.0 | lgf-math | 定长样本任意分位值（P0~P100，R-7「排序 + 线性插值」口径）：函数内拷贝排序，**调用方数组保持不变**（与库内就地排序件语义相反，已写入头注释不变性声明）；非有限样本剔除、分位点越界钳位并回显 `fActualP`、单样本不外插；`nGuard` 兼防死锁计数与性能诊断 / Percentile with copy-sort invariance and R-7 interpolation |

### 故障码台账追加（R11 码位登记，经终审全库复核）/ Error Code Ledger Additions (R11)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0001_0121` | 信息级 | 输入含非有限值（NaN / 无穷），关系不可判，返回 `eInvalid` 与重叠长度 0.0 | FC_DL_RangeOverlapCheck |
| `0001_0122` | 信息级 | 输入含非有限值，返回 0.0 且 `bValid` 置假（早退，不返回 NaN） | FC_DL_CalcDistance3D |
| `0001_0123` | 信息级 | 递推参数（乘子 / 增量）被改写为退化值，已回退到保底常数 | FC_DL_RandomNext |
| `0001_0124` | 信息级 | 分位点或样本数越界已钳位 / 非有限样本已剔除 / 结果非有限已回退 | FC_DL_PercentileLReal |
| `0001_0219` | 信息级 | 模长超缩放阈值，已按缩放式求模，结果有效但进入置信区 | FC_DL_CalcDistance3D |
| `0002_000E` | 信息级 | 有效样本为空（含全部非有限与排序保护触发），返回 0.0 | FC_DL_PercentileLReal |

**号段占用声明**：本批 `DL_MathData` 占用信息级 `0001_0121`~`0001_0124`（连续四码）与 `0001_0219`（`0001_0218` 归本批 `DL_Base`，互不越界）。`0002_000E` 为**跨段借用**：`16#0002_xxxx` 名义上归 Level 1 算法族常用段，本件「空集」事件沿用该段事件码（仅在 `FC_DL_PercentileLReal` 一个文件内出现，全库无第二处引用），已在此显式登记以免后续误判为冲突；缺陷台账如实记录，修正需走 `.st` 变更线，不在本轮文档线范围内。

### 变更说明 / Change Notes

- **与既有比较器族正交**：`FC_DL_LimitClassify`（单点 → 档位）、`FC_DL_Hysteresis`（单点 + 历史 → 开关）、`FB_DL_ToleranceWindow`（单点 → 布尔）三件均为单点判决，本批 `FC_DL_RangeOverlapCheck` 是四点 → 关系枚举，输入元数与返回类型都不同，四者不可互替。
- **几何族补齐点量**：`FC_DL_PolygonArea`（面量）/ `FC_DL_LineIntersection`（线量）/ 本批 `FC_DL_CalcDistance3D`（点量），三件覆盖面、线、点三种度量。
- **排序语义对立面留档**：`FC_DL_QuickSortLReal` 就地排序、失败时数组内容未定义；`FC_DL_PercentileLReal` 拷贝排序、调用方数组帧后不变。两者在手册中均已写明，禁止把后者当"更安全的前者"替换使用（前者零内存开销、后者多一份 64 元素副本）。
- **红线状态**：R1~R32 全部通过，机检 0 命中；全库码位跨文件重叠 = 0（`0002_000E` 单点占用，见上）。

---

## v1.4.0 ｜ 2026-11-15 ｜ R10 LGF Math 组三件（极值搜索 / N 次根 / 阶乘饱和）/ R10 LGF Math Trio

**变更性质**：MINOR（新增 3 个组件）+ PATCH（1 个本轮件终审修复 → v1.0.1），无破坏性变更，无迁移动作。对应 Round 10「DL_MathData LGF Math 组续挖」（来源标签 lgf-math，RAW_NOTES_R10 S-1：仅借鉴 LGF Math 组的组件粒度切分与「域 + 状态双出口」惯例，clean-room 未复制源码）。终审 **PASS with fixes**：`FC_DL_FactorialSat` 修复 1 处（D-17 注释级：DINT × INT 隐式类型提升，改 `INT_TO_DINT`）→ v1.0.1；`FC_DL_SearchMinMax` / `FC_DL_NthRoot` 零修改 PASS。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 27 | `FC_DL_SearchMinMax` | FC | 202 | 1.0.0 | lgf-math | LREAL 数组极值单遍扫描（值 + 索引同出）：首/末次命中语义可切、NaN 用 `x <> x` 判据跳过、全量非有限返回首个有效位索引而非 0 号位、全等容差标志 `bFlat` / Single-pass min/max scan with index reporting and NaN guard |
| 28 | `FC_DL_NthRoot` | FC | 211 | 1.0.0 | lgf-math | N 次根纯函数（Newton 迭代）：奇偶次分治（偶次拒绝负底数，禁拿绝对值冒充）、`x = 0` 与 `n ≤ 0` 守卫、迭代后结果有限性复检防发散穿透、根次域 1~64 / Nth root with odd/even branch and post-iteration finiteness check |
| 29 | `FC_DL_FactorialSat` | FC | 211 | **1.0.1** | lgf-math | 阶乘饱和函数（域 0~12）：12! 通过、13! 及以上饱和到 `DL_FACT_SAT`、负数按 0 处理、`bSat` + `nUsedN` 双出口；v1.0.1 把 `nAcc * i` 改 `nAcc * INT_TO_DINT(i)`，消除隐式类型提升（红线三） / Saturating factorial with explicit DINT promotion |

### 故障码台账追加（R10 码位登记，经终审全库复核）/ Error Code Ledger Additions (R10)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0001_0119` | 信息级 | 计数越界（< 1 早退；> 上限则钳位后继续） | FC_DL_SearchMinMax |
| `0001_011A` | 信息级 | 检测到非有限值并已跳过，个数见 `nSkipCnt` | FC_DL_SearchMinMax |
| `0001_0217` | 故障级 | 全量非有限，无有效极值，返回 FALSE | FC_DL_SearchMinMax |
| `0001_011B` | 信息级 | 根次数越界（须 1~64），返回 0，`bValid = FALSE` | FC_DL_NthRoot |
| `0001_011C` | 信息级 | 偶次根负底数 / 入参非有限 / 结果非有限，返回 0 | FC_DL_NthRoot |
| `0001_011D` | 信息级 | 入参超域（负数或 > 12），饱和输出并置 `bSat` | FC_DL_FactorialSat |

### 变更说明 / Change Notes

- **职责分离**：`FC_DL_SearchMinMax`（极值 + 索引，单遍）与既有 `FB_SignalStatistics`（窗口七元组统计）、`FB_DL_ArraySearchFirst`（首值命中计数）、`FC_DL_BinarySearchLReal`（有序查找目标值）正交；`FC_DL_NthRoot` 与 `FC_DL_PolygonArea` / `FC_DL_LineIntersection` 同属几何数学族但无重叠。
- **R10 新增编号带惯例**：本子库 R10 三件与 R9 各件共用 `0001_01xx` 信息级 / `0001_02xx` 故障级子段，逐码全库求差确认无冲突（R30 口径）。
- **红线状态**：R1~R32 全部通过，机检 0 命中；全库码位跨文件重叠 = 0。

---

## v1.3.0 ｜ 2026-11-15 ｜ R9 LGF Data Handling / Converter 两组深化（6 件 + 存量 PATCH）/ R9 Two-Group Deepening

**变更性质**：MINOR（新增 6 个组件）+ PATCH（1 个存量组件修复），无破坏性变更，无迁移动作。对应 Round 09「DL_MathData LGF 三组回补」（来源标签 lgf-datahandling / lgf-converter，RAW_NOTES_R9 S-1/S-3：仅借鉴 LGF 各组功能分类与参数域，clean-room 未复制源码）。终审 **PASS with fixes**：6 件中 5 件修复后 v1.0.1（缺陷 8 处：**D-01 致命——BinarySearchLReal 缺 uErrorId 声明致三平台编译失败**、D-03~D-05 码位冲突 9 处、D-06 码位越段撞运动轴族 3 处、D-13 强制转换写法异构），WordToBcd 零修改 PASS；另有存量 `FC_DL_Crc16Modbus` 因全库头注释内嵌注释定界符修复升 v1.0.1（R28 范式）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 21 | `FB_DL_FifoBuffer` | FB | 363 | **1.0.1** | lgf-datahandling | 定长槽位 LREAL 先进先出环形队列（通用元素队列）：压入/弹出/窥视/清空，满队丢新策略（不覆盖旧数据）、同拍弹压「先弹后压」固定次序、指针一致性断言自愈重建；与 RingBufferLReal（时间序列窗）职责分离 / Element FIFO ring queue with drop-new policy |
| 22 | `FB_DL_ArraySearchFirst` | FB | 357 | **1.0.1** | lgf-datahandling | 数组线性搜索首个命中值（不要求有序，O(n) 单遍）+ 可选全量计数模式；触发制扫描、结果族每拍先清（R25）；与 BinarySearchLReal（升序 O(log n)）职责分离 / First-hit linear array search with hit counting |
| 23 | `FC_DL_BinarySearchLReal` | FC | 211 | **1.0.1** | lgf-datahandling | 升序 LREAL 数组二分查找（纯函数，返回命中索引，未命中 -1）：nMid 防溢出写法 + 64 次守护；**v1.0.1 致命修复：补声明缺失的 uErrorId 输出引脚**（原 1.0.0 函数体 5 处读写未声明，三平台编译必败） / Binary search over sorted LREAL array with declared error pin |
| 24 | `FC_DL_TempUnitConvert` | FC | 210 | **1.0.1** | lgf-converter | ℃/℉/K 三温标两两互转（纯函数）：枚举对取代 MODE 巨无霸（3×3 查表 + 单向基准链 4 条公式）、同标直通、低于绝对零度信息级不阻断（诊断链留证） / Temperature unit conversion with enum pair selectors |
| 25 | `FC_DL_BcdToWord` | FC | 205 | **1.0.1** | lgf-converter | 16 位 BCD 码字转 UINT [0~9999]（纯函数）：逐半字节校验前置、非法码立即返回 0（零部分结果）；v1.0.1 将全库唯一强制转换写法 `UINT(uDigit)` 改为标准 `USINT_TO_UINT()` / BCD word to UINT with nibble validation |
| 26 | `FC_DL_WordToBcd` | FC | 202 | 1.0.0 | lgf-converter | UINT 转 16 位 BCD 码字（纯函数）：超 9999 溢出饱和不回绕（返回 16#9999 满量程显示值 + 置码）、除基守卫防常量误改；与 BcdToWord 构成编解码原子对 / UINT to BCD word with saturation semantics |

### 修复 / Fixed

| 组件 | 版本 | 缺陷与修法 / Defect and fix |
|---|---|---|
| `FC_DL_Crc16Modbus` | 1.0.0 → **1.0.1** | 全库注释定界符专项：头注释内嵌 `(* *)` 定界符（嵌套注释风险，非嵌套编译器会提前闭合致正文变代码）改为纯文本行——全库嵌套注释风险清零（**R28 范式**，本件为存量件唯一修复，JSONL 第 14 行 output 已按修后源码再同步） / Nested comment delimiters in header removed (R28 paradigm) |

### 故障码台账追加（R9 码位登记，经终审全库复核）/ Error Code Ledger Additions (R9)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0001_0105` | 故障级 | 非法 BCD 半字节（值 10~15），返回 0 | FC_DL_BcdToWord |
| `0001_0106` | 故障级 | 溢出饱和（uVal > 9999），返回 16#9999 | FC_DL_WordToBcd |
| `0001_0107` | 故障级 | 除基守卫命中（常量被误改为 0） | FC_DL_WordToBcd |
| `0001_010A` | 信息级 | FIFO 容量引脚越界，已钳位 2..DL_FIFO_MAX | FB_DL_FifoBuffer |
| `0001_010B` | 信息级 | 满队压入被拒（丢新策略），单拍事件 | FB_DL_FifoBuffer |
| `0001_010C` | 信息级 | 空队弹出被拒，单拍事件 | FB_DL_FifoBuffer |
| `0001_010D` | 信息级 | 空队窥视被拒，单拍事件 | FB_DL_FifoBuffer |
| `0001_010E` | 信息级 | nCount 越界，已钳位 0..DL_SRH_MAX | FB_DL_ArraySearchFirst |
| `0001_010F` | 信息级 | 二分 nCount 越界，已钳位，查找照常执行 | FC_DL_BinarySearchLReal |
| `0001_0110` | 信息级 | 归一后温度低于绝对零度（不阻断） | FC_DL_TempUnitConvert |
| `0001_0204` | 故障级 | FIFO 指针/计数一致性破坏，已自愈清空重建 | FB_DL_FifoBuffer |
| `0001_0205` | 故障级 | 线性搜索守护计数超限（理论不可达） | FB_DL_ArraySearchFirst |
| `0001_0206` | 故障级 | 二分守护超限/下标兜底，强制返回未命中 | FC_DL_BinarySearchLReal |
| `0001_0207` | 故障级 | 源温标枚举非法，返回 0.0 | FC_DL_TempUnitConvert |
| `0001_0208` | 故障级 | 目标温标枚举非法，返回 0.0 | FC_DL_TempUnitConvert |

**码位终审改判（本子库 9 处）**：`FB_DL_FifoBuffer` 原拟 0101~0104/0201 与 EventCounter/ModuloCounter/DayOfWeekCalc 撞码（5 处）；`FB_DL_ArraySearchFirst` 与 `FC_DL_BinarySearchLReal` 原拟 `0002_0101/0201` 越段撞 DL_Algo PID 族（4 处）；`FC_DL_TempUnitConvert` 原拟 `0004_0101/0201/0202` 越段撞 DL_Motion 运动轴族（3 处）——合计 6 件 15 处（全库口径）全部改判顺延至 `0001_xxxx` 段，终审后全库跨文件重叠 = 0。

### 变更说明 / Change Notes

- **D-01 致命教训**：`FC_DL_BinarySearchLReal` 是「机检七轮全过、三平台编译必败」的活证据——机检只查禁记号/分号/终结符，查不了「赋值目标声明性」；已提炼 **R29**（脚本比对全部 `^标识符 :=` 左侧与声明区并集）入 `AGENT_EVOLUTION_LOG.md`。
- **验收向量终审逐组代回**：BinarySearch V1~V5（迭代轨迹逐轮推演）、TempUnitConvert V1~V5 + P2（0K 直通）、BcdToWord V1~V5、WordToBcd V1~V5、FifoBuffer E1~E9、ArraySearchFirst A1~A7 全部由总监独立验算通过；WordBitPack V5 计划向量笔误（16#1264 → 16#12A4）经总监逐位验算裁定并勘误留痕（详见 `ROUND_PLAN_R9.md` §9 勘误块）。
- **红线状态**：R1~R8 全部通过，机检 0 命中。

---

## v1.2.0 ｜ 2026-11-15 ｜ 几何、校验与统计，Level 0 收口 / Geometry, Checksums and Statistics — Level 0 Closure

**变更性质**：MINOR（新增 10 个组件）+ 库级语法补全（Fixed，见下），无破坏性变更，无迁移动作。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 复杂度 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 11 | `FC_DL_MultiPointLinear` | FC | 6 | 1.0.0 | lgf-math+lbp-basic-process | N 段折线查表线性插值（2..16 点，二分查找），非法表整表拒绝、异常返回表首值 / Multi-segment table interpolation with whole-table rejection |
| 12 | `FC_DL_PolygonArea` | FC | 5 | 1.0.0 | lgf-math | 鞋带公式多边形面积与质心，LREAL 运算，退化时质心回退顶点均值 / Shoelace polygon area and centroid |
| 13 | `FC_DL_LineIntersection` | FC | 3 | 1.0.0 | lgf-math | 二维两直线/线段交点求解，平行容差按坐标量级配置，共线单独报码 / 2D line intersection with scale-aware tolerance |
| 14 | `FC_DL_Crc32Ethernet` | FC | 6 | 1.0.0 | oscat-network+crc32-iso-hdlc | CRC-32/ISO-HDLC（以太网 FCS）逐位法，支持分块链式调用，附 "123456789"→CBF43926 验收向量 / Bit-wise CRC-32 with chunk chaining |
| 15 | `FC_DL_LrcChecksum` | FC | 3 | 1.0.0 | oscat-network+modbus-ascii | Modbus ASCII 纵向冗余校验（LRC），帧头帧尾不参与计算，与 HexStringToBytes 组成两步收帧链 / Modbus ASCII LRC with framing exclusion |
| 16 | `FB_DL_LifoStack` | FB | 5 | 1.0.0 | lgf-datahandling | 定长 64 LIFO 栈：压栈/弹栈/窥视/清空全 O(1)，满拒写不覆盖，上溢/下溢锁存 / Fixed 64-slot LIFO with latched overflow and underflow |
| 17 | `FB_DL_MedianFilter` | FB | 6 | 1.0.0 | lgf-measurement+oscat-basic | 滑动窗口中值滤波（3..15 强制奇数），副本排序不打乱环形时间序，启动期不等装满 / Sliding median filter immune to isolated spikes |
| 18 | `FB_DL_SignalStatistics` | FB | 7 | 1.0.0 | lgf-math+oscat-basic | 滑动窗口七元组实时统计（均值/极值/峰峰值/方差/标准差/样本数），两遍法方差防灾难性抵消 / Streaming statistics with two-pass variance |
| 19 | `FC_DL_QuickSortLReal` | FC | 7 | 1.0.0 | lgf-datahandling+oscat-basic | LREAL 数组原地快速排序，显式栈替代递归（三数取中 + 小区间插入排序兜底） / Recursive-free quicksort with explicit stack |
| 20 | `FC_DL_HexStringToBytes` | FC | 4 | 1.0.0 | lgf-converter+modbus-ascii | 十六进制 ASCII 串严格解析为字节数组，先校验后写入，可选剥离 Modbus ASCII 帧 / Strict hex-string parser, validate-then-write |

### 修复 / Fixed（库级语法补全 / Library-level syntax completion）

**全库 40 个 POU 缺 `END_FUNCTION` / `END_FUNCTION_BLOCK` 终结符**：IEC 61131-3 / CODESYS 关键字规范要求 POU 声明与终结符成对出现，缺失即无法编译。该缺陷由本轮终审机检发现，涉及 R1/R2 两个批次的 26 个旧组件，已全库补齐；旧组件逐文件逻辑未变，版本号不变，JSONL 语料 `output` 已同步重建（字节级一致，机检 0 偏差）。本子库 v1.2.0 起 20 个 `.st` 全部含成对终结符。

### 变更说明 / Change Notes

- **接口契约**：10 个组件的引脚与 `ROADMAP.md` 第二章逐字一致；`E_DL_StackState`、`E_DL_MedianState`、`E_DL_StatState` 三个枚举随宿主组件同文件发布。
- **显式豁免**：`FC_DL_PolygonArea`、`FC_DL_LineIntersection` 在业务性退化（两段不相交等）时不置故障码——业务判定结果不是故障；配置类错误（奇数长度、非法字符、退化线）才置码，口径已在各头注释披露。
- **新增故障码段**：本轮起启用 `16#0002_xxxx` 故障码段（0002_0009 样本不足、0002_000A 十六进制串非法、0002_000B 折线表非法、0002_000C 多边形退化、0002_000D 两线重合），全部登记于 `LIBRARY_MANUAL.md` 故障码总表。
- **故障码复用**：`FC_DL_QuickSortLReal` 使 `16#0001_0006`（NaN/Inf）由「预留」转为实际使用（NaN 预扫描拒绝）；LIFO 上溢/下溢复用 `16#0001_0009` / `0001_000A`。
- **红线状态**：R1~R12 全部通过，机检 0 命中（含终结符成对性检查）。

### 已知限制 / Known Limitations

1. `FC_DL_MultiPointLinear` 固定 16 折点、`FC_DL_PolygonArea` 固定 32 顶点、`FC_DL_Crc32Ethernet` / `FC_DL_LrcChecksum` 固定 256 字节缓冲（数组维度硬绑定）。
2. `FC_DL_QuickSortLReal` 返回 `FALSE` 时数组内容未定义，调用方必须丢弃本轮结果；快速排序不稳定，同值相对次序不保证。
3. `FC_DL_HexStringToBytes` 不跳过空格、不跳过 `0x` 前缀、不容忍内嵌分隔符——严格模式是刻意的，宽容解析会把组帧错误吃进数据层。
4. `FB_DL_SignalStatistics` 方差口径为样本方差（n−1 分母），与 Excel `STDEV.S` 一致；n < 2 时不做除法并置 `16#0002_0009`。

---

## v1.1.0 ｜ 2026-11-14 ｜ 字节序、环形缓冲与字符串解析 / Byte Order, Buffers and Parsing

**变更性质**：MINOR（新增 5 个组件），无破坏性变更，无迁移动作。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 复杂度 | 版本 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 6 | `FC_DL_SwapBytes16` | FC | 2 | 1.0.0 | 16 位字高低字节互换，纯移位实现且自逆（换两次等于原值）/ 16-bit byte swap, shift-only and self-inverse |
| 7 | `FC_DL_SwapBytes32` | FC | 4 | 1.0.0 | 32 位量四排布（ABCD/DCBA/BADC/CDAB）归一化，非法枚举直通原值 / 32-bit four-layout normaliser that passes the raw value through on an illegal enum |
| 8 | `FB_DL_RingBufferLReal` | FB | 5 | 1.0.0 | 定长 64 的 LREAL 环形 FIFO：压入/弹出/窥视/清空，指针纯前向取模 / Fixed 64-slot LREAL ring FIFO with forward-only modulo wrap |
| 9 | `FC_DL_StringTrim` | FC | 3 | 1.0.0 | 去除首尾四类空白（空格/制表/回车/换行），双向扫描带防死锁 / Trims four whitespace classes with guarded two-way scans |
| 10 | `FC_DL_StringSplit` | FC | 6 | 1.0.0 | 单字符分隔符报文拆分，连续分隔符产生空字段（CSV 语义）/ Single-delimiter message splitter that keeps empty fields (CSV semantics) |

### 变更说明 / Change Notes

- **接口契约**：5 个组件的引脚与 `ROUND_PLAN_R2.md` 第 2 章逐字一致；`E_DL_ByteOrder` 枚举随 `FC_DL_SwapBytes32` 同文件发布。
- **显式豁免**：`FC_DL_SwapBytes16` 不设 `uErrorId`（全定义域有效，无失败路径），沿用首轮 `FC_DL_PackBitsToWord` 的 P3 先例。
- **实现选择**：`FC_DL_SwapBytes32` 四条路径全部用「移位提取 + 显式 `BYTE` 转换 + 移位重装」自洽实现，不调用 16 位互换构件，保证单文件可独立编译与单测（见该文件头注释）。
- **内存口径**：`FB_DL_RingBufferLReal` 实例占用 64 × 8 B = 512 B 存储 + 指针与边沿实例，约 0.6 KB；大容量缓存请勿复制多份实例。
- **故障码**：本轮使用 `16#0001_0001` / `0004` / `0008` / `0009` / `000A` / `000D` / `000E`，全部在库级分配表登记范围内。
- **红线状态**：R1~R12 全部通过，机检 0 命中。

### 已知限制 / Known Limitations

1. `FB_DL_RingBufferLReal` 容量固定 64（结构体维度硬绑定），不做运行时可变窗口；需要覆盖式行为时调用方先 `bPop` 再 `bPush`。
2. `FC_DL_SwapBytes32` 只输出归一化 `DWORD`，不做 `DWORD` → `REAL` 的二进制重解释（各平台浮点拼接规则不同）。
3. `FC_DL_StringTrim` 的空白字符集固定四类，全角空格等多字节字符属调用方预处理职责。
4. `FC_DL_StringSplit` 只支持单字符分隔符；多字符分隔（如 `\r\n`）需调用方先规整报文。

---

## v0.1.0 ｜ 2026-11-14 ｜ 首版冷启动 / Initial Seed Release

**变更性质**：初始发布（Initial release），无破坏性变更，无迁移动作。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 复杂度 | 一句话说明 / Summary |
|---|---|---|---|---|
| 1 | `FC_DL_LinearScale` | FC | 4 | 模拟量线性标定，防除零 + 反向量程 + 双侧钳位 / Analog scaling with divide-by-zero guard, reverse ranges and two-sided clamping |
| 2 | `FC_DL_Deadband` | FC | 3 | 移位型/归零型双语义死区，负宽取绝对值 / Shift-type and zero-type deadband, negative width taken absolute |
| 3 | `FC_DL_Hysteresis` | FC | 4 | 施密特迟滞比较，状态经 `VAR_IN_OUT` 交还调用方 / Schmitt hysteresis with caller-held state via `VAR_IN_OUT` |
| 4 | `FB_DL_MovingAverage` | FB | 6 | O(1) 递推滑动平均，两阶段启动 + 漂移校正 / O(1) recursive moving average with two-phase startup and drift correction |
| 5 | `FC_DL_Crc16Modbus` | FC | 5 | Modbus RTU CRC-16 逐位法，带实算验收向量 / Bit-wise Modbus RTU CRC-16 with verified acceptance vectors |

### 变更说明 / Change Notes

- **接口契约**：5 个组件的引脚与 `ROUND_PLAN.md` 第 2 章一致。其中 `FB_DL_MovingAverage` 按 `ROUND_PLAN` §2.13 B7 与决策 P6 **刻意收窄**：不设 `fbTrigSample` 采样沿实例，采样判据统一为 `bSample` 电平语义（详见手册 4.4 节与该文件头注释）。
- **`FC_DL_Hysteresis` 保持 `FC_` 形态**：用 `VAR_IN_OUT bState` 持有状态，而非改成 FB，以保留「可放进比较表达式」的用法（决策 P1）。
- **CRC 测试向量勘误**：`ROUND_PLAN` 给出的单字节向量 `0x0C → 0x911E` 经穷举 0..255 复算无法复现，已改为实算值 `0x0C → 0x45BF`，并在源码头注释中留档。
- **故障码**：统一使用 `16#0001_0001` ~ `16#0001_0007`，`16#0001_0006`（NaN/Inf）预留给支持检测的平台版本。
- **红线状态**：R1~R7 全部通过，机检 0 命中。

### 已知限制 / Known Limitations

1. `FB_DL_MovingAverage` 相位滞后约 `(N-1)/2` 个采样周期，安全联锁回路禁止使用大窗口滤波值（N ≤ 3）。
2. `FC_DL_Crc16Modbus` 首版只有逐位法，无 256 项查表法；查表法依赖的常量数组跨平台初始化行为尚待验证。
3. `FC_DL_LinearScale` 不做 NaN / Inf 检测（纯 IEC 无标准手段），故障码 `16#0001_0006` 预留。
4. `FC_DL_Hysteresis` 的回差上限按设定点绝对值的 50% 钳位；设定点本身接近 0 时跳过比例限幅，改用绝对量程约束。

---

## 版本号约定 / Versioning Policy

子库遵循 SemVer，且与库总版本联动：

- **MAJOR**：任一组件删除引脚、改引脚语义、改默认值、改故障码含义。
- **MINOR**：新增组件，或为已有组件新增可选输入（带默认值）。
- **PATCH**：内部实现修正、注释与手册补全、性能优化，接口与行为不变。

---

## 后续计划 / Next

`DL_MathData` 已于 v1.2.0 完成 Phase 1 全部 20 项，**Level 0 `DL_MathData` 收口（20/20）**。v1.3.0（R9）LGF Data Handling / Converter 两组深化（元素 FIFO / 线性搜索 / 二分查找 / 温标换算 / BCD 编解码原子对），v1.5.0（R11）数值统计补强（伪随机 / 任意分位值），v1.6.0（R12）字符串族三件分工（批量替换 / 分词流 / 数组差异摘要）+ 天文与协议解析两件（太阳位置 / Modbus 异常帧解析），现 42 项。

字符串族现由三件构成互不重叠的能力面：`FC_DL_StringReplaceAll` 做**全量替换**（定长就地改写、截断须显式置位，见范式 R37）、`FB_DL_StringTokenStream` 做**增量分词**（状态机逐拍吐出一个 token）、`FC_DL_ArrayDiffSummary` 做**结构级差异摘要**（不回写源数组）。后续新增能力进入 Level 1：`DL_Algo`（PID 家族、滤波族、轨迹规划）按 `ROADMAP.md` 计划推进；本子库只接受 PATCH 级修正与既有组件可选引脚扩展（变长数组与通用化缓冲族、DTL-String 族的可移植性评估见 `ROADMAP.md` 待办池），**CASE 级字符串通用化件不再新增**。

---

## v1.8.0 ｜ 2026-11-16 ｜ R14 T0 快车道：域闸门 + 委托内建数学/字符串包装 5 件（T0-4/5/6 组开收）/ R14 T0 Fast Lane — 5 Domain-Gated Math/String Wrappers

**变更性质**：MINOR（新增 5 个组件），无破坏性变更，无迁移动作。终审 **5/5 PASS**（提示级 2 处留档不改码：TanEx 结果复检条件中有限性判据被幅值判据覆盖属冗余无害；StringMidEx 255 截断闸在源串 ≤255 前提下为纵深防御死代码，头注释已声明保留语义）。

### 新增组件（5 件）/ Added Components

| 组件 / Component | T0 组 | 标准原型 | 防御要点 / Defense |
|---|---|---|---|
| `FC_DL_SqrtEx` | T0-4 | SQRT | 负数/非有限域闸门先行，域内委托内建 SQRT，NaN→0.0+故障码 |
| `FC_DL_LnEx` | T0-4 | LN | fX ≤ 0 拦截（含 0 趋 −Inf），委托内建 LN |
| `FC_DL_TanEx` | T0-4 | TAN | π/2 极点容差闸（\|cos\|<1E-12）+ 幅值 1E6 双保险（R45 四段式样板） |
| `FC_DL_RoundSat` | T0-5 | ROUND | DINT 域外钳位饱和不回绕、半值远离零取向 |
| `FC_DL_StringMidEx` | T0-6 | MID | LEN 一次锁存 → 钳位 → 越界闸 → 255 先置截断标志再钳长（R49） |

### 码位台账追加（R14 码位登记，经终审全库求差断言复核）/ Error Code Ledger Additions (R14)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `16#0001_015A` | 信息 | fX 非有限拦截 | `FC_DL_SqrtEx` |
| `16#0001_015B` | 信息 | DINT 域外溢出钳位方向记录 | `FC_DL_RoundSat` |
| `16#0001_015C` | 信息 | 参数钳位（iStart<1/iLen<0）或起点越界（含空串） | `FC_DL_StringMidEx` |
| `16#0001_015D` | 信息 | 请求子串超 255 上限显式截断 | `FC_DL_StringMidEx` |
| `16#0001_0227` | 故障 | fX < 0 域外（IEEE 下产 NaN，本库统一 0.0+码） | `FC_DL_SqrtEx` |
| `16#0001_0228` | 故障 | fX ≤ 0 域外 | `FC_DL_LnEx` |
| `16#0001_0229` | 故障 | 输入/输出非有限 | `FC_DL_LnEx` |
| `16#0001_022A` | 故障 | 极点邻域/非有限/幅值爆炸（三况同码奇点域） | `FC_DL_TanEx` |
| `16#0001_022B` | 故障 | 非有限输入 | `FC_DL_RoundSat` |

> 全库码位跨文件重叠 = 0（终审脚本求差断言复跑）；本批信息级 `015A`~`015D`、故障级 `0227`~`022B` 由本子库独占，`014D`~`0159` 与 `0226` 归 `DL_Base`。

| `16#0001_0434` | 信息 | 模数为负已取绝对值 | `FC_DL_ModPos` |
| `16#0001_0435` | 信息 | 预留禁用（不得挪用） | `FC_DL_ModPos` |
| `16#0001_036C` | 故障 | 模数为零 | `FC_DL_ModPos` |
| `16#0001_036D` | 故障 | 模数为 DINT 下界 | `FC_DL_ModPos` |
| `16#0001_036E` | 故障 | 预留禁用（不得挪用） | `FC_DL_ModPos` |
| `16#0001_0436` | 信息 | 商超有限域已饱和至 ±LREAL_MAX | `FC_DL_DivLrealSafe` |
| `16#0001_0437` | 信息 | 预留禁用（不得挪用） | `FC_DL_DivLrealSafe` |
| `16#0001_036F` | 故障 | |分母| < fDenEps（微量分母） | `FC_DL_DivLrealSafe` |
| `16#0001_0370` | 故障 | 阈值参数 fDenEps ≤ 0 | `FC_DL_DivLrealSafe` |
| `16#0001_0371` | 故障 | 输入含 NaN 或 ±INF | `FC_DL_DivLrealSafe` |
| `16#0001_0438` | 信息 | 商超精确域（> DL_QUANT_MAX_RATIO） | `FC_DL_QuantizeStep` |
| `16#0001_0439` | 信息 | 残差越半步（浮点误差提示） | `FC_DL_QuantizeStep` |
| `16#0001_0372` | 故障 | 步距 ≤ DL_FLOAT_EPS | `FC_DL_QuantizeStep` |
| `16#0001_0373` | 故障 | 输入非有限（NaN 或 ±INF） | `FC_DL_QuantizeStep` |
| `16#0001_0374` | 故障 | 量化结果超有限域已饱和 | `FC_DL_QuantizeStep` |
| `16#0001_043A` | 信息 | 前导零系数已降阶 | `FC_DL_PolyEvalHorner` |
| `16#0001_043B` | 信息 | 预留禁用（不得挪用） | `FC_DL_PolyEvalHorner` |
| `16#0001_0375` | 故障 | 阶数越界（< 0 或 > DL_POLY_MAX_ORD | `FC_DL_PolyEvalHorner` |
| `16#0001_0376` | 故障 | fX 或参与运算的系数非有限 | `FC_DL_PolyEvalHorner` |
| `16#0001_0377` | 故障 | 中间量或结果溢出 | `FC_DL_PolyEvalHorner` |
| `16#0001_043C` | 信息 | 输入超一圈已归一 | `FC_DL_WrapAngleDeg` |
| `16#0001_043D` | 信息 | 结果落零容差已归一为 +0.0 | `FC_DL_WrapAngleDeg` |
| `16#0001_0378` | 故障 | 输入非有限（NaN 或 ±INF） | `FC_DL_WrapAngleDeg` |
| `16#0001_0379` | 故障 | 超可归一域（|角度| > DL_ANGLE_ABS_MA | `FC_DL_WrapAngleDeg` |
| `16#0001_037A` | 故障 | 预留禁用（不得挪用） | `FC_DL_WrapAngleDeg` |
| `16#0001_043E` | 信息 | 起始位 + 宽超 64 | `FC_DL_LwordBitFieldExtract` |
| `16#0001_043F` | 信息 | 预留禁用（不得挪用） | `FC_DL_LwordBitFieldExtract` |
| `16#0001_037B` | 故障 | 起始位越界（< 0 或 > 63） | `FC_DL_LwordBitFieldExtract` |
| `16#0001_037C` | 故障 | 字段宽非法（≤ 0 或 > 64） | `FC_DL_LwordBitFieldExtract` |
| `16#0001_037D` | 故障 | 预留禁用（不得挪用） | `FC_DL_LwordBitFieldExtract` |
| `16#0001_0440` | 信息 | 字段值超宽高位已丢弃 | `FC_DL_LwordBitFieldInsert` |
| `16#0001_0441` | 信息 | 预留禁用（不得挪用） | `FC_DL_LwordBitFieldInsert` |
| `16#0001_037E` | 故障 | 起始位越界 | `FC_DL_LwordBitFieldInsert` |
| `16#0001_037F` | 故障 | 字段宽非法（≤ 0 或 > 64） | `FC_DL_LwordBitFieldInsert` |
| `16#0001_0380` | 故障 | 起始位 + 宽 > 64 | `FC_DL_LwordBitFieldInsert` |
| `16#0001_0442` | 信息 | 输入全零（合法工况） | `FC_DL_LwordBitCount` |
| `16#0001_0443` | 信息 | 预留禁用（不得挪用） | `FC_DL_LwordBitCount` |
| `16#0001_0381` | 故障 | 守卫超限（理论不可达 | `FC_DL_LwordBitCount` |
| `16#0001_0382` | 故障 | 预留禁用（不得挪用） | `FC_DL_LwordBitCount` |
| `16#0001_0383` | 故障 | 预留禁用（不得挪用） | `FC_DL_LwordBitCount` |
| `16#0001_0445` | 信息 | 空帧 | `FC_DL_Crc16Generic` |
| `16#0001_0444` | 信息 | 输出反射为真但多项式最高位为 0 | `FC_DL_Crc16Generic` |
| `16#0001_0384` | 故障 | 多项式为零 | `FC_DL_Crc16Generic` |
| `16#0001_0385` | 故障 | 帧长超 DL_CRC_BUF_MAX | `FC_DL_Crc16Generic` |
| `16#0001_0386` | 故障 | 预留禁用（不得挪用） | `FC_DL_Crc16Generic` |
| `16#0001_0446` | 信息 | 补码模式下结果为 0 的特例（部分协议以 0 表示无校验 | `FC_DL_ChecksumSum8` |
| `16#0001_0447` | 信息 | 空帧 | `FC_DL_ChecksumSum8` |
| `16#0001_0387` | 故障 | 帧长超 DL_SUM_BUF_MAX | `FC_DL_ChecksumSum8` |
| `16#0001_0388` | 故障 | 预留禁用（不得挪用） | `FC_DL_ChecksumSum8` |
| `16#0001_0389` | 故障 | 预留禁用（不得挪用） | `FC_DL_ChecksumSum8` |
| `16#0001_0448` | 信息 | 前后空格已忽略 | `FC_DL_StringToDint` |
| `16#0001_0449` | 信息 | 预留禁用（不得挪用） | `FC_DL_StringToDint` |
| `16#0001_038A` | 故障 | 空串或仅符号 | `FC_DL_StringToDint` |
| `16#0001_038B` | 故障 | 数值溢出 | `FC_DL_StringToDint` |
| `16#0001_038C` | 故障 | 非法字符（含 CASE 落 ELSE 的非法状态兜底 | `FC_DL_StringToDint` |
| `16#0001_044A` | 信息 | 预留禁用（不得挪用 | `FC_DL_DwordToHexString` |
| `16#0001_044B` | 信息 | 预留禁用（不得挪用） | `FC_DL_DwordToHexString` |
| `16#0001_038D` | 故障 | 结果长度与期望不符（目标串长不足已被平台截断） | `FC_DL_DwordToHexString` |
| `16#0001_038E` | 故障 | 预留禁用（不得挪用） | `FC_DL_DwordToHexString` |
| `16#0001_038F` | 故障 | 预留禁用（不得挪用） | `FC_DL_DwordToHexString` |
| `16#0001_044C` | 信息 | 部分非有限样本已剔除 | `FC_DL_ArraySumLreal` |
| `16#0001_044D` | 信息 | 元素数超上限已按上限钳位 | `FC_DL_ArraySumLreal` |
| `16#0001_0390` | 故障 | 元素数为负 | `FC_DL_ArraySumLreal` |
| `16#0001_0391` | 故障 | 无有效样本（全部非有限） | `FC_DL_ArraySumLreal` |
| `16#0001_0392` | 故障 | 累加溢出（中间量非有限） | `FC_DL_ArraySumLreal` |
| `16#0001_044E` | 信息 | 负时长已带负号输出 | `FC_DL_TimeToHmsString` |
| `16#0001_044F` | 信息 | 小时超 99 | `FC_DL_TimeToHmsString` |
| `16#0001_0393` | 故障 | 分解中间量非法（小时超 999 | `FC_DL_TimeToHmsString` |
| `16#0001_0394` | 故障 | 预留禁用（不得挪用） | `FC_DL_TimeToHmsString` |
| `16#0001_0395` | 故障 | 预留禁用（不得挪用） | `FC_DL_TimeToHmsString` |
| `16#0001_0450` | 信息 | 输出串长异常（补零逻辑防御提示） | `FC_DL_DateToIsoString` |
| `16#0001_0451` | 信息 | 预留禁用（不得挪用） | `FC_DL_DateToIsoString` |
| `16#0001_0396` | 故障 | 早于纪元或年份越 1970~9999 | `FC_DL_DateToIsoString` |
| `16#0001_0397` | 故障 | 回代自校验失败（算法自证不过） | `FC_DL_DateToIsoString` |
| `16#0001_0398` | 故障 | 预留禁用（不得挪用） | `FC_DL_DateToIsoString` |
> 全库码位跨文件重叠 = **0**（机检 + 注册表正则求差断言 CLASH=NONE 复跑）；本轮信息级至 `045C`、故障级至 `03A8`，与另一 Level 0 子库共用游标无交叉占用。
> **码位游标（注册表实测于 2026-11-16）**：信息级 `045C` ｜ 故障级 `03A8`（下一轮从 `045D` / `03A9` 起分配）。


---

## v1.16.0 ｜ 2026-11-16 ｜ R22 结构补位轮 3 件

**批次**：本子库 R22 新增 3 件（全库 20 件 6,618 行；机检 20/20 PASS fail=0）
**码位**：本子库本轮占用见各件头注释「码位总账」；收口后全库游标（注册表实测 2026-11-16）：`0001` 信息 `0466` / 故障 `03B7`、`0002` 下一 CC `2D`、`0003` 信息 `017A` / 故障 `0348`、`0004` 信息 `01DF` / 故障 `02F9`、`0005` 信息 `01E2` / 故障 `0317`
**终审结论**：R22 抽检 13 件高风险件，4 件轻微缺陷修复升 v1.0.1（MotionCmdQueue / VirtualMasterAxis / AxisBrakeSeq / BatchTransferSeq），1 件中等安全相关挂账 R23（BatchTransferSeq 中止时序），其余零缺陷 PASS
**码位跨文件冲突断言**：R22 100 槽定向复测 CLASH=NONE；JSONL 384 条全量 sha256 MATCH（本轮另修复 2 件历史换行口径漂移）

- `FC_DL_IntToFixedField`：整数→定宽零/空格填充字段（右对齐，符号位逐字符负域取模防 DINT 最小值，宽度不足拒绝编码不输出半截数字）。
- `FC_DL_FixedFieldToInt`：定宽字段→整数（LEN 一次锁存 R37/R38、前导填充剥离、非法字符 1 基定位、负域累乘 + ±2147483647 饱和哨兵；与上一件构成 round-trip 验收对）。
- `FC_DL_LrealToFixedField`：浮点→定宽定点文本（禁 `LREAL_TO_STRING`，绝对值域取整、R79 精确非有限判据 `(x−x)<>(x−x)`、整数 15 位精度承诺收窄留档；T2-1 LGF「数值→定宽字段对齐」子族 ✔ 收口）。

**终审**：本子库 3 件未列入高风险抽样（纯函数低风险），随全量机检 PASS。

---

## v1.17.0 ｜ 2026-11-17 ｜ R24 行业纵深轮：LGF 仿射变换族开族 2 件 + 风机定律 1 件

**新增 3 件**（码位 0001 段：信息 0466~046E / 故障 03B7~03BC）：

| 组件 | 版本 | 一句话功能 | 来源 |
|---|---|---|---|
| `FC_DL_Affine2DCompose` | v1.0.0 | 二维仿射矩阵按序合成 MOut = M2×M1（列向量约定）+ 行列式可逆性校验 | T2-1 LGF Math 仿射变换族（clean-room） |
| `FC_DL_Affine2Apply` | v1.0.0 | 仿射矩阵对点坐标应用（与 Compose 构成定义-应用逆对） | T2-1 LGF Math 仿射变换族（clean-room） |
| `FC_DL_FanLawRootCalc` | v1.0.0 | 风机相似定律换算（流量比∝转速比/压力比∝平方/功率比∝立方，开方域闸 + 防除零） | ROADMAP P1 §661（FB→FC 改判：纯函数归 MathData，R14 聚居判据） |

终审抽查：`FC_DL_Affine2DCompose` PASS（乘法次序 M2×M1 与列向量约定自洽、结果非有限复检复用 03B7、暂存阵先检后放）。

---

## v1.18.0 ｜ 2026-11-17 ｜ R25 R25 新增仿射逆映射 1 件，仿射「合成-应用-逆」三元闭环齐备 / R25 Batch

**批次**：本轮 20 件中本子库 **1 件**，合计 **172 行**（全库 20 件 7,097 行，终审修复后 7,174 行）
**码位游标（收口后实测）**：信息级推进至 **`0471`** ｜ 故障级推进至 **`03BF`**

| 组件 | 版本 | 一句话功能 / 终审结论 | 来源 |
|---|---|---|---|
| `FC_DL_Affine2DInvert` | v1.0.0 | 二维仿射矩阵求逆（2x2 伴随 + 平移列反算，奇异出零阵不泄半逆） | T2-1 LGF Math 仿射族补口（clean-room） |

---

## v1.20.0 ｜ 2026-11-18 ｜ R31 极坐标变换 1 件：1 件

| 组件 | 版本 | 码位起始 |
|---|---|---|
| `FC_DL_PolarTransform2D` | v1.0.0 | 16#0001_0092 |

> R31 增量行：组件总数 162→**163**（registry 实测口径）；机检 19/19 PASS fail=0；终审抽 5 件（本库 0 件），修 0 处升 v1.0.1（无）。

---

## v1.21.0 ｜ 2026-11-18 ｜ R32 T0 纯函数 9 件

| 组件 | 版本 | 码位起始 |
|---|---|---|
| `FC_DL_StringToUpperEx` | v1.0.0 | 16#0002_3058（改判自 02_3_34~37，避 `FB_DL_EtchEndpointTrend` 3033~3035） |
| `FC_DL_StringStripCharsEx` | v1.0.0 | 16#0002_304E |
| `FC_DL_BytesToHexString` | v1.0.0 | 16#0002_3040 |
| `FC_DL_HexStringToLword` | v1.0.0 | 16#0002_3044 |
| `FC_DL_ReverseBitsWord` | v1.0.0 | 16#0002_3048 |
| `FC_DL_DtAddSecondsSat` | v1.0.0 | 16#0002_3054 |
| `FC_DL_DivDintSafeChk` | v1.0.0 | 16#0002_3055 |
| `FC_DL_ModLrealSafe` | v1.0.0 | 16#0002_3050 |
| `FC_DL_BitArrayReverse` | v1.0.0 | 16#0002_304C |

> R32 增量行：组件总数 163→**172**（registry 实测口径）；机检 20/20 PASS fail=0；终审抽 1 件（`FC_DL_ModLrealSafe`）→ PASS，留 1 项提示级（`uCode` 死变量 + `DL_MLS_MAXQ` 注释提 DINT 溢出但实现无 DINT 转换），不升版。

### R33 增量（1.21.0 → 1.22.0）

| 组件 | 版本 | 码位 |
|---|---|---|
| `FB_DL_SlurryViscosityComp` | v1.0.0 | 16#02_3_5C |
| `FB_DL_ShrinkFilmUsageCalc` | v1.0.0 | 16#02_3_5D |

> R33 增量行：本库 172 → **174**；机检本库新增件全 PASS；码位全窗口独占无冲突（主控实测）。

### R34 返修

| 组件 | 版本 | 说明 |
|---|---|---|
| `FB_DL_SlurryViscosityComp` | v1.0.2 | R33 挂账两项闭环：`bRun=FALSE` 冻结末次有效粘度并置 `bDegraded`；`bClamped` 与 `xClamped` 同源赋值（接口零变更） |

## v1.22.0 — 2026-11-18（R36）
- +2：`FC_DL_HarmonicSpectrumBin`（05_0_00 首开段）、`FC_DL_CubicSplineInterp`（05_0_01）。计 62 件。

## R39（2026-11-19）— +2（FC_DL_TrendSlopeCalc / FC_DL_SphericalDistance）

- 本轮增量已入册（registry v2.31.0），机检全 PASS；详见 CHANGELOG v2.31.0。

## R40（2026-11-19）— +13（FC_DL_MaxNanEx / FC_DL_MinNanEx / FC_DL_RealEqTolEx / FC_DL_RangeCheckEx / FC_DL_RealToDintSat / FC_DL_RealToRealSat / FC_DL_RoundBankEx / FC_DL_DegToRadEx / FC_DL_RadToDegEx / FC_DL_MuxIntEx / FC_DL_StringToLowerEx / FC_DL_StringToUdintEx / FC_DL_IndexClampEx）

- 本轮增量已入册（registry v2.32.0），机检全 PASS；详见 CHANGELOG v2.32.0。

## v1.21.0 — 2026-11-19（R41 · 20 新件批次 1/2）
- 新增 4 件：FC_DL_AngleDiffWrap（角度差环绕归一 ±180°）/ FC_DL_WeightedMeanCalc（数组加权平均防除零）/ FC_DL_QuantileCalc（线性插值分位数 + 整除进位点分支）/ FB_DL_WindowExtremaStat（基于 FB_DL_RingBufferLReal 滑窗极值/均值聚合）；组件总数 193 → 197。
- 码位：段 0001 共用游标推进——故障 16#0001_03E0~03E9、信息 16#0001_04A3~04AC（本子库占用部分）。
- 事故留痕：FC_DL_AngleDiffWrap.st 曾被机检补丁脚本 wb 截断误清 0 字节，按头注释规格重建后机检 MATCH。

## v1.23.0 — 2026-11-19（R44 · 零检索轮）
- 新增 1 件：FC_DL_DewPointToPpmV（露点温度→水分含量 ppmV 换算，复用 VaporPressureSat 属主，饱和压比值法，不重复声明 Magnus 常数）；组件总数 197 → 198。
- 码位：派单建议窗口 05_0_06，registry 全文口径实测零冲突。
- 版本号注记：本库历史节存在号段错位（R36 先用 v1.22.0、R41 又记 v1.21.0），故本节顺延取 v1.23.0，向后续编以已用最大号为准（R283 总监线注记）。
- 向后兼容（纯新增，无接口破坏）。

## v1.24.0 — 2026-11-19（R45）

- R45：+1 新件（FC_DL_CubicBezierEval）｜码位 16#0001_03ED / 04B0｜6 控制点+导数纯函数


## v1.25.0 — 2026-11-19（R46）

- R46：+2 新件（FC_DL_StdDevOnline〔Welford 单遍〕/ FC_DL_MedianAbsDev〔MAD〕）｜零码位硬编码：BOOL+ENUM 出口，码位待主控统一派号｜机检 2/2 PASS
- 向后兼容（纯新增，无接口破坏）。

## v1.25.1 — 2026-11-19（R47）

- R47：+1 新件（FC_DL_CovarOnline〔在线协方差〕）｜零码位硬编码：BOOL+ENUM 出口，码位待主控统一派号｜机检 1/1 PASS
- 向后兼容（纯新增，无接口破坏）。
---

## v1.21.0 — 2026-11-20（R48）

- 新增组件 2 件：FC_DL_SimpsonQuad / FC_DL_LagrangeInterp
- 子库组件总数：**204**（registry 实测口径）
- 机检：本轮 21/21 PASS（含 FB_DL_ModulePottingVac v1.0.1 轻返修）

## v1.22.0 — 2026-11-20（R49）

- 新增组件 2 件：FC_DL_QuatRotateVec / FC_DL_GeoMeanCalc
- 子库组件总数：**206**（registry 实测口径）
- 机检：本轮 20/20 PASS（增量仅扫本轮新增件）

## v2.42.0（R49 批次入册 · R50 收口，2026-11-20）
- 新增组件 2 件：FC_DL_QuatRotateVec / FC_DL_GeoMeanCalc
- 子库组件总数：**208**（registry v2.42.0 counts 口径）
- 机检 25/25 PASS；R50 终审无本子库挂账件

## v1.23 — 2026-11-20（R52）
- 变更：+2（WrapIndexNeg 环窗下标负值归正 / LogDomainNormalize 对数域归一化）
- 子库计数：**212 件**（全库 945 / v2.44.0）
- 机检：本子库本轮新增/返修件全部 PASS（audit_r52.py，22/22 全绿）

## v1.24 — 2026-11-20（R53）

- +3：FC_DL_WetBulbCalc / FC_DL_HaversineDistance / FC_DL_PeriodJitterCalc（湿球迭代 / 球面距离 / 抖动统计）
- 机检：本轮 20/20 PASS（含 4 件 v1.0.1 返修）；JSONL 同步 962 条。

## R54 追加（2026-11-20，子库 v1.25）
- 新增：FC_DL_ChecksumLwordSum / FB_DL_HistogramBinTally
- 子库存量：217 件

## R55 追加（2026-11-20，子库 v1.26）
- 新增：FC_DL_NewtonRaphson
- 子库存量：218 件

## v1.27 — 2026-11-21（R56 追加）
- 新增 5 件（Hermite/QuatSlerp/RoundSigFigs/RTD/Kalman2D）。
- 子库累计 223 件。
## v1.29 — 2026-11-21（R57 追加）
- 新增 10 件：FC_DL_AsinSafe / AcosSafe / LogSafe / ExpSat / PowIntSat / SignumCalc / RmsCalc / ParityCalc / PeakToPeakCalc / InterpStepNearest（T0 Safe 族防御性包装 + 最近邻阶梯插值）
- 子库累计 233 件。

## v1.30 — 2026-11-21（R58 追加）
- 3 件（ThermocoupleLinearization / SkewKurtosisCalc / SolveLinear3）+ RmsCalc / PowIntSat v1.0.1 返修。
- 子库累计 236 件。

## v1.32 — 2026-11-21（R60 追加）
- 新增 5 件：FC_DL_SearchMinMaxDint / FC_DL_SearchMinMaxUdint（DINT/UDINT 极值检索对） / FC_DL_Affine2DChain（二维仿射链复合） / FC_DL_ThdCalc（总谐波失真率） / FC_DL_InterpolateTable3D（三维表三线性插值）
- 子库累计 248 件。

## v1.33 — 2026-11-21（R61 追加）
- 新增 5 件：Hypot3D / TrapezoidArea / SortIndexLReal / WeightedPercentile / MeanAbsDevCalc
- 子库累计 253 件。

## v1.34 — 2026-11-21（R62 追加）
- 新增 4 件（T0-5 转换 / 统计族补口）：`FC_DL_RealToIntSat`（LREAL→INT 16 位饱和，与 Dint/Byte 两件构成位宽三分）、`FC_DL_SignedToUdintSat`（负值钳零 + 信息级提示；`FC_DL_IntToUdintSat` 语义并入本件重载，**禁新增文件**）、`FC_DL_DtToTodWrap`（DT→当日秒 / TOD，日模 86400 + 基准无效闸）、`FC_DL_PercentileRank`（值→分位定位，弱 / 强 / 中位三口径，分位族逆运算）。
- 返修 1 件：`FC_DL_WeightedPercentile` v1.0.0 → **v1.0.1**（委托返回值与 `bValid` 分承，禁双写；R61 挂账关闭）。
- 子库累计 257 件。

## v1.35 — 2026-11-21（R63 追加）
- 新增 4 件（T0-5 BCD 位宽补口 + 统计族）：`FC_DL_BcdToDint`（8 位 BCD→DINT，逐半字节合法性闸 + 权值常量表，域证明 99999999 < DINT 上域无溢出分支）、`FC_DL_DintToBcd`（DINT→8 位 BCD，负值显式拒绝 / 越域 `bOvF` 一码区分）、`FC_DL_TrimmedMeanCalc`（双端截尾均值，NaN 逐条剔除不外显 R62-D7 口径 + 委托 `FC_DL_SortIndexLReal` 双承接 R295）、`FC_DL_PearsonCorrCalc`（皮尔逊相关，配对剔除 + `nPairs ≤ 2` 闸 + 常量通道退化故障 + `|r|>1` 钳回信息级）。
- 返修 1 件：`FC_DL_PercentileRank` v1.0.0 → **v1.0.1**（R62-D7 轻：`nNonFinite` 口径定稿「不外显」，不改接口）。
- 子库累计 261 件。
## v1.36 — 2026-11-21（R64 追加）

- 新增 6 件：`FC_DL_ArrayFindValue`（T2-1 Data Handling +1，数组首匹配 + 非有限剔除）、`FC_DL_ArraySliceCopy`（T2-1 Data Handling +1，切片拷贝 + 边界钳制）、`FC_DL_IntervalGapCalc`（T2-1 Comparator +1，区间间隙量）、`FC_DL_GcdUdintCalc`（T0 数论原子，欧几里得 + 守卫计数）、`FC_DL_RunningSumCalc`（T0 统计原子，滑动和）、`FC_DL_FlowUnitConvert`（T0-4 单位换算族三件齐）。
- **返修 1 件**：`FC_DL_FlowUnitConvert` v1.0.0 → **v1.0.1**（R64 终审 S1 严重项就地修：`DL_FUC_LMIN` 因子方向倒置 16.666667 → 0.06，L/min 换算 277.78 倍错误修正，V1~V4 向量修复后自证成立；registry / JSONL 同步重注入）。
- 主库合计 267 件（+6）。Comparator ◐→◐ 深化 +1、Data Handling ◐→◐ 深化 +1。

## v1.37 — 2026-11-22（R65 追加）

- 新增 `FC_DL_AngleUnitConvert`（deg/rad/grad 统一桥接 rad，系数预乘零除法面）。
- 子库累计 268 件。

## v1.38 — 2026-11-22（R66 追加）

- 新增 4 件：`FC_DL_CircularMeanCalc`（角度循环均值向量合成）/ `FC_DL_WeekNumIsoCalc`（ISO 8601 周号，日历族补口）/ `FC_DL_BilinearInterp`（2D 等距表双线性插值）/ `FC_DL_QuadPolyFit`（二次多项式最小二乘拟合）。
- 终审挂账：QuadPolyFit 舒尔补主元闸 + 段 4 复核扩展待 R67 点修（REVIEW_R66 M2/L1）。
- 子库累计 272 件。

## v1.38 — 2026-11-22（R67 追加）

- 新增 4 件纯函数：`FC_DL_CalcDistance2D`（Hypot 缩放防溢出）/ `FC_DL_AngleDiffRad`（跨 ±π 最短角差）/ `FC_DL_NormTo01`（三码分立归一化）/ `FC_DL_SlewRateCalc`（变化率诊断测量，lgf-technology）。
- 新增 2 件 T0 防御性包装：`FC_DL_HexToStr` / `FC_DL_StrToHex`（HEX 互转，委托平台字符串内建，IEC 标准语义溯源标注，iec-std-wrapper）。
- 点修 `FC_DL_QuadPolyFit` → v1.0.1（舒尔补主元闸 + 矩量溢出复核扩展，R66 挂账）。
- 子库累计 278 件。

## v1.39 — 2026-11-22（R68 追加）

- 新增 2 件：`FC_DL_WordFromBytes`（BYTE 数组→WORD/DWORD，四字节序 + 长度不足高段补零）｜`FC_DL_WordToBytes`（WORD/DWORD→BYTE 数组，与前者构成 round-trip 双向对）。
- 子库累计 280 件。

## v1.40 — 2026-11-22（R69 追加）
- 新增 3 件（T0 防御性包装，溯源标注「IEC 61131-3 标准语义的道莅防御性实现」，委托内建不重实现内核）：`FC_DL_TimeMulSat`（TIME 乘法饱和）｜`FC_DL_TimeClampEx`（TIME 钳位扩展）｜`FC_DL_UdintToStringTrim`（UDINT→STRING 定宽去前导零）。

## v1.32 — 2026-11-22（R70 追加）
- 新增：FC_DL_ModPosWrap（MOD 负数归正）｜FC_DL_LerpClamped（插值钳位）｜FB_DL_ScaleRangeWatch（标定区间监视）。
- 子库累计 286 件。

## v1.33 — 2026-11-23（R72 追加）

- `FC_DL_IntModChk` / `FC_DL_FiniteClassify` / `FC_DL_ArrayCumSumLreal` / `FC_DL_CharCodeConvert` / `FC_DL_WordToBinString` / `FC_DL_HmsToTodChk` 六件入册（T0 防御包装 4 + LGF 统计线 1 + 组态入口 1）；`FC_DL_AirSpecificVolume` v1.0.1 点修（补 `bValid => _bPwsVld` 全 6 形参回执，E032 契约级修复行为零变更）。

## v1.34 — 2026-11-23（R73）

- 新增/变更：FC_DL_MovingRangeCalc / FC_DL_PressureAltitudeCalc / FC_DL_SoundSpeedAirCalc / FC_DL_ExpMovingAvgCalc / FC_DL_TorqueUnitConvert + FC_DL_DewPointToPpmV 点修
- L2 编译闸：PASS（RuSTy 1.0.8 串行）

## R76 · v2.68.0 · 2026-11-23
- 新增 15 件（7 角度 + 8 三角），本库累计 **329** 件。
- 全部经本地 RuSTy L2 真编译闸 PASS（串行 jobs=1），审校 12 项扫查 + 三道去重通过。

## R77 · v2.69.0 · 2026-11-23
- 新增 23 件（单位换算 10 / 查表插值 8 / 统计 5），本库累计 **352** 件。
- 全部经本地 RuSTy L2 真编译闸 PASS（串行 jobs=1，闸席独立裁决），审校 12 项扫查 + 三道去重通过。

### R80（2026-11-24）
- 新增 4 件（统计离散 4），子库累计 420 件。
