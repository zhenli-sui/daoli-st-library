# -*- coding: utf-8 -*-
"""R20 文档增量 1：DL_MathData VERSION v1.14.0 + DL_Base VERSION v1.14.0 + 两本手册 R20 接口表"""
import io, os

# ---------------- DL_MathData / VERSION.md ----------------
p = 'DL_MathData/VERSION.md'
s = open(p, encoding='utf-8').read()
s = s.replace('| 子库版本 / Sublibrary Version | **v1.13.0** |',
              '| 子库版本 / Sublibrary Version | **v1.14.0** |', 1)
s = s.replace('| 组件总数 / Components | **107 / 20**',
              '| 组件总数 / Components | **130 / 20**', 1)
s = s.replace('+ **R17 T0 纯函数第 4 轮 16 项**）',
              '+ R17 T0 纯函数第 4 轮 16 项 + R18 4 项 + R19 5 项 + **R20 T0 日历/时间族 18 项**；'
              'R19 之前的计数口径漏计 R18 / R19 两批，本次以注册表实测校正为 130）', 1)
s = s.replace('| 库总版本 / Library Version | v2.7.0 |',
              '| 库总版本 / Library Version | v2.9.0 |', 1)

math_ver = '''## v1.14.0 ｜ 2026-11-16 ｜ R20 T0 日历/时间族 + 域转换补充 + 字节序 + 字符串化 18 件（T0 快车道零检索）/ R20 T0 Calendar-Time Family, Domain Conversions, Byte Order and Stringification — 18 Components

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

> 全库码位跨文件重叠 = 0（终审脚本求差断言复跑）；**`16#0001_` 段游标推进至：信息级 `0434` / 故障级 `036C`**（与 `DL_Base` 共用同一游标）。

---

'''
i = s.index('## v1.13.0 ｜ 2026-11-16 ｜ R19')
s = s[:i] + math_ver + s[i:]
open(p, 'w', encoding='utf-8', newline='').write(s)
print('MathData VERSION ok ->', 'v1.14.0' in s)

# ---------------- DL_Base / VERSION.md ----------------
p = 'DL_Base/VERSION.md'
s = open(p, encoding='utf-8').read()
s = s.replace('| 子库版本 / Sublibrary Version | **v1.13.0** |',
              '| 子库版本 / Sublibrary Version | **v1.14.0** |', 1)
s = s.replace('| 组件总数 / Components | **63 / 20**',
              '| 组件总数 / Components | **66 / 20**', 1)
s = s.replace('+ **R17 T0 LWORD 64 位域 4 项**）',
              '+ R17 T0 LWORD 64 位域 4 项 + R18 4 项 + R19 1 项 + **R20 闰年原子与同步族 2 项**；'
              'R19 之前的计数口径漏计 R18 / R19 两批，本次以注册表实测校正为 66）', 1)
s = s.replace('| 库总版本 / Library Version | v2.7.0 |',
              '| 库总版本 / Library Version | v2.9.0 |', 1)

base_ver = '''## v1.14.0 ｜ 2026-11-16 ｜ R20 T0 闰年原子 + 同步族互斥防御包装 2 件 / R20 T0 Leap-Year Atom and the Sync-Family Mutual-Exclusion Wrapper — 2 Components

**变更性质**：MINOR（新增 2 件），无破坏性变更，无迁移动作。**终审**：8 件高风险抽样，本子库命中 1 件并修复（`FB_DL_SemaMutex` 过渡态跨拍时序表述，注释级，升 v1.0.1，逻辑与引脚零变更）。

### 新增组件（2 件）/ Added Components

| 组件 / Component | 行 | 类型 | 防御要点 / Defense |
|---|---|---|---|
| `FC_DL_LeapYearChk` | 107 | FC·日历原子 | 闰年判定：4/100/400 三级规则，`bFullRule` 显式选择两律（仅 4 年）与三律（含整百例外）；整百年 0430 信息级——两律与三律在此处分歧，必须让调用方看得见；年份超 1900~2099 窗口判故障级 0366 |
| `FB_DL_SemaMutex` | 186 | FB·同步 | IEC 标准 SEMA 的防御包装：ENUM+CASE **三态**（`eFree` / `eHeld` / `eTimedOutRelease`）+ `ELSE` 兜底复位；超时**强制归还**并置**故障级** 0369（死锁拦截 ≠ 正常防御，必须进报警）；释放沿优先于申请沿（同拍 0432 信息级）；`TON` / 两只 `R_TRIG` 三实例本体首部无条件刷新；申请/释放计数饱和 036B，非法状态 036A |

### 终审修复（v1.0.1）/ Fixed in Final Review

- `FB_DL_SemaMutex` v1.0.0→**v1.0.1**（**注释级**）：头注释状态机段「`eTimedOutRelease` 本拍即回 `eFree`」易被读成**同拍**回零；实际为超时拍 N 进过渡态、拍 N+1 回 `eFree` 并恢复受理（过渡态恰占一个扫描拍，其间申请被拒）。逻辑零变更，仅表述改为跨拍显式口径——时序描述错一拍会让上层按错误延迟设计重试节拍。同步修正 JSONL `architecture_thought` 中「超时判 036A」的错记（应为 0369；036A 是非法状态兜底）。

### 码位台账追加（R20，经终审全库求差断言复核）

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `16#0001_0430` | 信息 | 整百年（`y MOD 100 = 0`），两律与三律在此处分歧，结论取决于 `bFullRule` | `FC_DL_LeapYearChk` |
| `16#0001_0431` | 信息 | 预留禁用 | — |
| `16#0001_0432` | 信息 | 同拍申请与释放（已按释放优先）或超时监视被禁用（`tHoldMax = 0`） | `FB_DL_SemaMutex` |
| `16#0001_0433` | 信息 | 预留禁用 | — |
| `16#0001_0366` | 故障 | 年份超出 1900~2099 窗口 | `FC_DL_LeapYearChk` |
| `16#0001_0367` | 故障 | 预留 | — |
| `16#0001_0368` | 故障 | 预留禁用 | — |
| `16#0001_0369` | 故障 | 占用超时，已强制归还（调用方必须处理） | `FB_DL_SemaMutex` |
| `16#0001_036A` | 故障 | 非法状态兜底，已复位 `eFree` | `FB_DL_SemaMutex` |
| `16#0001_036B` | 故障 | 申请或释放计数达饱和值，统计不可信（互斥本体仍工作） | `FB_DL_SemaMutex` |

> 全库码位跨文件重叠 = 0（终审脚本求差断言复跑）；**`16#0001_` 段游标推进至：信息级 `0434` / 故障级 `036C`**（与 `DL_MathData` 共用同一游标）。

---

'''
i = s.index('## v1.13.0 ｜ 2026-11-16 ｜ R19')
s = s[:i] + base_ver + s[i:]
open(p, 'w', encoding='utf-8', newline='').write(s)
print('Base VERSION ok ->', 'v1.14.0' in s)

# ---------------- MANUAL_DL_MathData.md ----------------
p = 'DL_MathData/MANUAL_DL_MathData.md'
s = open(p, encoding='utf-8').read()
old_tail = '*Last updated: 2026-11-16（R19 追加接口表）｜ 道莅工控代码库产品总监*'
math_man = '''---

## R20 追加组件接口表（2026-11-16，本子库 18 件）

> 一律 `FC_DL_` 纯函数，输出契约 `eErr` / `bError` / `bValid` 三件套（下表不再重复列出）。**日历/天数族四件共用同一容器口径常量** `DL_DATE_DAYS_MAX = 65535`，互相之间不会错位；涉及平台内建口径（DT_TO_DINT / DATE_TO_DINT / TOD_TO_DINT）的件均在头注释「编译门槛」段声明实测锚定要求。

### `FC_DL_DtToDintEpoch` / `FC_DL_DintEpochToDt`
- **功能**：Unix 纪元秒 ↔ DATE_AND_TIME 双向对。正向**饱和**（Y2038 超域钳上限并升故障级），反向**不饱和**（超域返回纪元零点）——饱和会伪造时刻、毁掉故障证据，两方向策略刻意分立。
- **输入引脚**：`dtIn`（DT）｜ `nEpochSec`（DINT，0~2147483647）
- **输出引脚**：`eErr`、`bError`、`bValid`
- **码位**：信息 `040C`/`040E`（Y2038 邻近 / 域端点）｜ 故障 `0330`~`0331` / `0333`~`0334`

### `FC_DL_DateToDintDays` / `FC_DL_DintDaysToDate`
- **功能**：DATE ↔ 自 1970-01-01 起天数双向对，供保质期、保养周期、数据库整型列落库。
- **输入引脚**：`dateIn`（DATE）｜ `nDays`（DINT）
- **输出引脚**：`eErr`、`bError`、`bValid`
- **码位**：信息 `0410`（超容器口径已钳位）/`0412`（域端点）｜ 故障 `0336`~`0337` / `0339`~`033A`

### `FC_DL_TodAddWrap` / `FC_DL_TodDiffWrap`
- **功能**：当日时刻加偏移（含午夜回绕）与两时刻差（含跨零点折算）。回绕一律**条件加减**，禁用 MOD（负数取余三平台不一致）。
- **输入引脚**：`todIn` + `tOffset`（TIME，模长须 < 一日）｜ `todEarlier` + `todLater`
- **输出引脚**：`bWrapped`、`nWrapCircles`（±1 圈）｜ `bCrossMidnight`
- **码位**：信息 `0420` / `0422` ｜ 故障 `034E`~`034F`（仅 Add 件）

### `FC_DL_DateAddDays` / `FC_DL_DateDiffDays`
- **功能**：日期 ± 天数（±36500 天钳位）、日期差天数（负差如实输出）。溢出用**减法预判**：正向判 `nWork > 上限 − nBase`，负向判 `nWork < 0 − nBase`，禁「先加再判变号」。
- **输入引脚**：`dateIn` + `nDays` ｜ `dateFrom` + `dateTo`
- **输出引脚**：`bClamped` ｜ `bNegative`
- **码位**：信息 `042A` / `042C` ｜ 故障 `035D`~`035E`（仅 Add 件）

### `FC_DL_TimeAbsSat`
- **功能**：TIME 取幅值并饱和。`nIn < −2147483647` 单值闸精确拦截 INT32_MIN（`−MAX−1` 的相反数不可表），饱和值经 `DINT_TO_TIME` 落地而非超长字面量。
- **输入引脚**：`tIn`（TIME，平台 32 位毫秒口径）
- **输出引脚**：`bNegative`
- **码位**：信息 `042E`（负输入已取幅值）｜ 故障 `0363`（不可表达，已饱和）

### `FC_DL_UdintToLintChk`
- **功能**：UDINT → LINT 升位 + **round-trip 验真**（回程比对，识别平台把中间量走 32 位有符号路径的符号扩展缺陷）。
- **输入引脚**：`uIn`（UDINT）、`bCheckEveryCall`（默认 TRUE；FALSE 时本拍不验真并置 0414）
- **输出引脚**：`bRoundTripFail`
- **码位**：信息 `0414` ｜ 故障 `033C`（验真失败）

### `FC_DL_WordToIntSat`
- **功能**：WORD → INT 超域双出口：补码解释为负值（0416）或上饱和 32767（0417），由 `bTwosComplement` 决定，**两种口径都如实登记**。
- **输入引脚**：`uIn`（WORD）、`bTwosComplement`
- **输出引脚**：`bInterpreted`
- **码位**：信息 `0416` / `0417` ｜ 故障槽全预留（本件不升故障级）

### `FC_DL_DwordToIntSat` / `FC_DL_LwordToLintSat`
- **功能**：DWORD → INT（饱和 32767）、LWORD → LINT（饱和 9223372036854775807）；`bRequireLossless = TRUE` 时一旦饱和即反升故障级（无损是调用方的硬要求，不能只发信息码）。
- **输入引脚**：`uIn`、`bRequireLossless`
- **输出引脚**：`bSatHigh`
- **码位**：信息 `0418` / `041A` ｜ 故障 `0342` / `0345`（无损违约）

### `FC_DL_BcdToByte` / `FC_DL_ByteToBcd`
- **功能**：BCD ↔ BYTE 双向。半字节 > 9 判故障级拦截；满量程 99 与域端点发信息级（多拨码开关调试残留的典型现象）。补齐 R16 的 WORD/UDINT 位宽缺口。
- **输入引脚**：`uBcd`（BCD）｜ `uIn`（0~99）
- **输出引脚**：`eErr`、`bError`、`bValid`
- **码位**：信息 `041C` / `041E` ｜ 故障 `0348` / `034B`

### `FC_DL_SwapBytes64`
- **功能**：LWORD 全字节逆序。**拆半区复用 `FC_DL_SwapBytes32`** 各自反序，再交叉合成 `(LoRev << 32) OR HiRev`——字节序族内复用而非重实现内核；全域双射，五槽码位全预留。
- **输入引脚**：`liIn`（LWORD，全域）
- **输出引脚**：`eErr`（恒 0）、`bError`（恒 FALSE）、`bValid`（恒 TRUE）
- **码位**：`16#0001_0424`~`0425` / `0354`~`0356` 全预留

### `FC_DL_DintToStringTrim` / `FC_DL_LrealToStringTrim`
- **功能**：整型 / 浮点字符串化：前导空格修剪 + R37 四步截断样板（长度锁存 → 宽度比较 → 标志先置 → 按允许分路）。浮点件把非有限值映射成统一文本 `NaN` / `Inf+` / `Inf-`（信息级、`bValid` 仍 TRUE——采样坏点不该牵动整条报警链）。
- **输入引脚**：`nIn` / `fIn`、`uTargetMax`（1~255 字符）、`bAllowTrunc`
- **输出引脚**：`bTrimmed`、`bTruncated` ｜ 浮点件另有 `bNonFinite`
- **码位**：信息 `0426`~`0429` ｜ 故障 `0357`~`0358` / `035A`
- **用法要点**：`bAllowTrunc = FALSE` 时宁可返回空串也不返回半截数值；`LrealToStringTrim` 的无穷判据为 `(x−x) <> (x−x)` + LREAL 最大值兜底（v1.0.1，勿改回单一 1.79E308 阈值）。


'''
s = s.replace(old_tail, math_man + old_tail.replace('（R19 追加接口表）', '（R20 追加接口表）'), 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('MathData MANUAL ok ->', 'R20 追加组件接口表' in s)

# ---------------- MANUAL_DL_Base.md ----------------
p = 'DL_Base/MANUAL_DL_Base.md'
s = open(p, encoding='utf-8').read()
old_tail = '*Last updated: 2026-11-16（R19 追加接口表）｜ 道莅工控代码库产品总监*'
base_man = '''---

## R20 追加组件接口表（2026-11-16，本子库 2 件）

### `FC_DL_LeapYearChk`
- **功能**：闰年原子判定，供年窗 / 天数族共用，不做纯算术的重复实现。`bFullRule` 显式选择两律（仅 4 年整除，LGF / OSCAT 部分实现的默认口径）与三律（4/100/400，ISO-8601 口径）。
- **输入引脚**：`nYear`（1900~2099 窗口）、`bFullRule`
- **输出引脚**：`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0001_0430`（整百年——两律与三律在此处分歧，必须让调用方看得见）｜ 故障 `16#0001_0366`（年份超窗口）

### `FB_DL_SemaMutex`
- **功能**：IEC 标准 SEMA 的防御包装，解决「标准 SEMA 不带超时、持锁方卡死会永久锁死产线」。**三态状态机**（`eFree` / `eHeld` / `eTimedOutRelease`）+ `ELSE` 兜底；超时**强制归还**并按故障级 0369 上报；释放沿优先于申请沿（安全侧：宁可多还一次，不可错持一次）；`TON` + 两只 `R_TRIG` 三实例在本体首部无条件周期刷新。
- **输入引脚**：`bClaim`、`bRelease`（均上升沿有效）、`tHoldMax`（默认 `T#5S`，`0` = 禁用超时监视）
- **输出引脚**：`bBusy`（由状态派生，不独立锁存）、`bTimedOut`（单周期脉冲）、`uClaimCnt`、`uReleaseCnt`（饱和计数）
- **码位**：信息 `16#0001_0432`（同拍仲裁释放优先 / 监视被禁用）｜ 故障 `16#0001_0369`（超时强制归还）、`036A`（非法状态兜底）、`036B`（计数饱和）
- **用法要点**：超时归还的时序是「超时拍 N 进 `eTimedOutRelease` → 拍 N+1 回 `eFree` 并恢复受理」，过渡态恰占**一个**扫描拍且此拍申请被拒——上层重试节拍按 1 拍延迟设计，别按同拍设计；实例必须每周期无条件调用。


'''
s = s.replace(old_tail, base_man + old_tail.replace('（R19 追加接口表）', '（R20 追加接口表）'), 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('Base MANUAL ok ->', 'R20 追加组件接口表' in s)
