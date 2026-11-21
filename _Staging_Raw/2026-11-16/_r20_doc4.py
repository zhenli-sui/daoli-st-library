# -*- coding: utf-8 -*-
"""R20 文档增量 4：SOURCE_HUNTING_MATRIX + ROADMAP + LIBRARY_MANUAL"""

# ---------------- 1. SOURCE_HUNTING_MATRIX ----------------
p = 'SOURCE_HUNTING_MATRIX.md'
lines = open(p, encoding='utf-8').read().split('\n')
out = []
t08 = ('| **T0-8 同步/互斥（500 快车道）** | ✔ | R20 开组并收口 | **R20 新开行**：IEC 标准 `SEMA` 的防御性包装 `FB_DL_SemaMutex`——标准 SEMA 无超时，持锁方卡死即永久死锁产线，故本行价值在「不静默持锁」：三态机（`eFree`/`eHeld`/`eTimedOutRelease`）+ ELSE 兜底、超时**强制归还**并升故障级 0369、释放沿优先于申请沿；'
       '`TON` / 两只 `R_TRIG` 本体首部无条件周期刷新；计数饱和 036B、非法状态 036A。'
       '**本行只做互斥本体，不做任务同步（事件/信号量计数）、不做跨任务通信**——那些需 OS 级原语，违反零厂商依赖红线。后续可挖：多实例优先级继承、超时归还后的所有权审计（均需先给可独立验收粒度） |')
for ln in lines:
    if ln.startswith('| **T0-2 定时器（500 快车道）**'):
        ln = ln[:-2] + ('；**R20 日历/时间算术族 9 件（T0 快车道零检索，DL_MathData +1 / DL_Base +1 跨库协作）**：'
                        '日历/纪元族 4（DtToDintEpoch / DintEpochToDt / DateToDintDays / DintDaysToDate，秒域与天数域双向、Y2038 两方向策略分立——正向饱和、反解不饱和）+ '
                        '时间算术 3（TodAddWrap / TodDiffWrap / TimeAbsSat，**回绕归一禁 MOD 走条件加减**、`−MAX−1` 单值闸）+ 日期算术 2（DateAddDays / DateDiffDays，溢出用**减法预判**双向判据）+ 闰年原子 1（LeapYearChk，`bFullRule` 显式选两律/三律）。'
                        '**收口警示**：本行日历内建链（`DT_TO_DINT` / `DINT_TO_DT` / `DATE_TO_DINT`）的平台口径差异仍未实测，编译门槛段已逐件声明 |')
    elif ln.startswith('| **T0-5 类型转换（500 快车道）**'):
        ln = ln[:-2] + ('；**R20 域转换补充 7 件（零检索变体线）**：无符号位串→有符号域 3（WordToIntSat 补码/饱和双出口、DwordToIntSat、LwordToLintSat，后两件接 `bRequireLossless` 无损违约反升故障级）+ '
                        'UDINT→LINT 升位 **round-trip 验真** 1（UdintToLintChk）+ BCD↔BYTE 位宽补口 2（BcdToByte / ByteToBcd，补齐 R16 只做 WORD/UDINT 的缺口）+ **字节序 1**（SwapBytes64，拆半区复用 SwapBytes32 后交叉合成，字节序族至此 16/32/64 位齐备） |')
    elif ln.startswith('| **T0-6 字符串（500 快车道）**'):
        ln = ln[:-2] + ('；**R20 字符串化 2 件**：DintToStringTrim / LrealToStringTrim（前导空格修剪 + R37 四步截断样板；浮点件把 NaN/±Inf 映射成统一文本 `NaN` / `Inf+` / `Inf-`，信息级不置故障）。'
                        '**终审修正**：无穷判据由近似阈值 1.79E308 改为 `(x−x)<>(x−x)` 精确判据 + LREAL 最大值兜底（R79） |')
    out.append(ln)
    if ln.startswith('| **T0-7 位串操作（500 快车道）**'):
        out.append(t08)
s = '\n'.join(out)
me5 = ('| M-E5 | 第 5 节台账 T0 行与 T2-1 / T1-x 行 | R20 派单要求「T0 对应台账行 ◐→✔ 回写（日历/时间族、BCD 补充、字节序、SEMA/同步族）」 | 实测：R20 二十件全为 **T0 快车道零检索件**（IEC 标准语义 clean-room 包装），'
       '零 LGF / OSCAT / TcOpen 源输入；且台账中原本**不存在 SEMA/同步行**，日历/时间族的 ◐ 行属于 T2-1 LGF（该组仍有在挖项） | '
       '**裁定**：① T2-1 / T1-x 各行状态列**一律不动**（零检索轮改 ✔ 即虚账，R85）；② R20 登记改为回写 T0-2 / T0-5 / T0-6 三行备注 + **新增 T0-8 同步/互斥行**（R20 开组并收口）；'
       '③ 后续凡「派单指定回写行」与实际源不符，一律按本裁定处理并在本表留痕 |')
s = s.replace('| M-E4 |', me5 + '\n| M-E4 |', 1) if False else s
# 追加到勘误表末尾（M-E4 行之后）
idx = s.index('| M-E4 |')
end = s.index('\n', idx)
s = s[:end+1] + me5 + '\n' + s[end+1:]
open(p, 'w', encoding='utf-8', newline='').write(s)
print('MATRIX ok', 'T0-8' in s, 'M-E5' in s)

# ---------------- 2. ROADMAP ----------------
p = 'ROADMAP.md'
s = open(p, encoding='utf-8').read()
s = s.replace('- [ ] `FC_DL_DtToDintEpoch` / `FC_DL_DintEpochToDt`：DT/DTL 日历族防御包装（Unix 纪元秒↔DATE_AND_TIME，秒域先判后算）→ **DL_MathData** ｜ **P0**（日历族 R17 派单时被编译门槛评估拦下，TOD_TO_DT 链跨平台行为需先实测）',
              '- [x] **（R20 收口）** `FC_DL_DtToDintEpoch` / `FC_DL_DintEpochToDt`：DT/DTL 日历族防御包装（Unix 纪元秒↔DATE_AND_TIME，秒域先判后算）→ **DL_MathData** ｜ **P0**（R17 被编译门槛评估拦下，R20 以「正向饱和 / 反解不饱和」分立策略落地，内建口径假设写进编译门槛段；实测验证仍挂在编译验证债）', 1)
r20 = '''
---

## 二十三、R20 路线图增量 / Roadmap R20 Addendum（2026-11-16）

> **R20 收口核对**：本轮 20 件（DtToDintEpoch / DintEpochToDt / DateToDintDays / DintDaysToDate / UdintToLintChk / WordToIntSat / DwordToIntSat / LwordToLintSat / BcdToByte / ByteToBcd / TodAddWrap / TodDiffWrap / SwapBytes64 / DintToStringTrim / LrealToStringTrim / DateAddDays / DateDiffDays / TimeAbsSat / LeapYearChk / SemaMutex）中，
> **§22.2 的「纪元对等」待办已于本轮勾选收口**（`DtToDintEpoch` / `DintEpochToDt`），其余 18 件为 T0 变体线新立变体、不在既有待办池，勾选不适用。

### 23.1 P0（R21 必办，先于任何新件）

- [ ] **编译验证债立项（连续 15 轮悬置，债务已扩大）**：R20 又新增 3 条日历内建链假设（`DT_TO_DINT` / `DINT_TO_DT` / `DATE_TO_DINT`），全库依赖平台内建口径的件已达两位数。R21 必须产出「最小 CODESYS V3.5 工程 + 二十件抽样编译」的一次性验证记录（含失败清单与替代实现），否则后续所有「委托内建」件都只有文本推演背书。
- [ ] **子库计数与注册表断言脚本化**：把 R86 的 Step 1 断言做成 `_verify_counts.py`（六库 VERSION 组件数 vs registry counts），每轮开轮即跑，杜绝 107/130 这类两处事实源漂移。
- [ ] **JSONL 两条 CRLF 遗留归一化**：`FB_DL_SCurveGenerator` / `FB_DL_PulseDirStepper` 源码为 CRLF、语料为 LF，字节级 sha 不匹配（内容一致）。需一次性统一换行风格并复验 344/344 字节级 MATCH。

### 23.2 P1（下两轮，与主线并行）

- [ ] **三本 Level 1 手册历史件接口表续补**：`DL_Device` 余 53 件 / `DL_Motion` 余 21 件 / `DL_Process` 余 28 件；按 ≤10 件/轮、倒序推进（R88）。
- [ ] `FC_DL_SwapBytes16` / `32` 的 64 位族反向复核：`SwapBytes64` 已复用 32 位件，需回头确认 16/32 位件的枚举域 `E_DL_ByteOrder` 是否覆盖 ABDC/BADC 等剩余排布，避免「64 位齐备而 32 位不全」的认知错觉。
- [ ] `FB_DL_SemaMutex` 所有权审计扩展（v1.1 候选）：超时强制归还后，记录「被谁持过、持了多久、归还后是否被同一调用方立刻重申」，供现场定位死锁根因。
- [ ] 日历族 `DTL` 变体评估：本批只做 `DATE_AND_TIME`（秒精度），毫秒级 `DTL` 是否需要独立件，取决于 MES 台账的时间戳精度要求，先给验收粒度再立项。

### 23.3 P2（观察池，不占本轮配额）

- [ ] `FC_DL_WordToIntSat` 故障槽全预留（只发信息级）：是否需要 `bRequireStrict` 引脚把「补码解释」升为故障级，看现场是否存在「超域即必须停机」的用例。
- [ ] `DateAddDays` 的 `DL_DATE_DAYS_MAX = 65535` 保守容器口径：三平台实测锚定后若 DATE 以秒承载，此常量需整体重定（连带四件日历/日期件），列入编译验证债的后续动作。
- [ ] `LIBRARY_MANUAL.md` 的 R18 / R19 两章仍缺（本轮只补 R20 章），按「增量优先」纪律留 R21 一并补齐。

---

*R20 收口 ｜ 2026-11-16 ｜ 道莅工控代码库产品总监*
'''
s = s.rstrip('\n') + '\n' + r20
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ROADMAP ok')

# ---------------- 3. LIBRARY_MANUAL ----------------
p = 'LIBRARY_MANUAL.md'
s = open(p, encoding='utf-8').read()
ch = '''
---

## 十六、R20 组件接入指引 / R20 Integration Guide（v2.9.0，20 组件）

> 本章为 R20 批次（20 件、2,189 行）的接入摘要，逐件引脚与码位以各子库 `MANUAL_DL_*.md` 的「R20 追加组件接口表」与 `.st` 头注释为准。
> **附**：R18 / R19 两章尚未写入本总手册（历史欠账），按「增量优先」纪律留 R21 补齐；本章不覆盖那两批组件。

### 16.1 日历 / 时间族（DL_MathData 9 + DL_Base 1，本批最大族）

| 组件 | 一句话功能 | 关键引脚 |
|---|---|---|
| `FC_DL_DtToDintEpoch` | DATE_AND_TIME → Unix 纪元秒，Y2038 超域**饱和**并升故障级 | `dtIn` → 返回 DINT |
| `FC_DL_DintEpochToDt` | 纪元秒 → DATE_AND_TIME，超域**不饱和**、返回纪元零点 | `nEpochSec` → 返回 DT |
| `FC_DL_DateToDintDays` / `FC_DL_DintDaysToDate` | 日期 ↔ 自纪元天数双向，共用容器口径 65535 | `dateIn` / `nDays` |
| `FC_DL_TodAddWrap` / `FC_DL_TodDiffWrap` | 当日时刻加减与差值，午夜回绕/跨零点**条件加减归一** | `todIn`+`tOffset` / `todEarlier`+`todLater` |
| `FC_DL_DateAddDays` / `FC_DL_DateDiffDays` | 日期 ± 天数（减法预判溢出）/ 日期差（负差如实输出） | `dateIn`+`nDays` / `dateFrom`+`dateTo` |
| `FC_DL_TimeAbsSat` | TIME 取幅值饱和，`−MAX−1` 单值闸 | `tIn` |
| `FC_DL_LeapYearChk`（DL_Base） | 闰年原子，`bFullRule` 选两律 / 三律 | `nYear`+`bFullRule` |

**接入要点**：日历族四件共用 `DL_DATE_DAYS_MAX`，**不要跨件改口径**；`DtToDintEpoch` 与 `DintEpochToDt` 的超域策略刻意相反（饱和 / 不饱和），组态注释必须写明哪一侧进了 MES 台账。

### 16.2 域转换 / 字节序 / 字符串化（DL_MathData 9）

| 组件 | 一句话功能 | 关键引脚 |
|---|---|---|
| `FC_DL_WordToIntSat` | WORD → INT，补码解释为负 / 上饱和 32767 双出口 | `uIn`+`bTwosComplement` |
| `FC_DL_DwordToIntSat` / `FC_DL_LwordToLintSat` | 位宽饱和 + `bRequireLossless` 无损违约反升故障级 | `uIn`+`bRequireLossless` |
| `FC_DL_UdintToLintChk` | UDINT → LINT 升位 + **round-trip 验真**（识别平台 32 位符号扩展缺陷） | `uIn`+`bCheckEveryCall` |
| `FC_DL_BcdToByte` / `FC_DL_ByteToBcd` | BCD ↔ BYTE 双向，非法半字节 / 超 99 分级处理 | `uBcd` / `uIn` |
| `FC_DL_SwapBytes64` | LWORD 全字节逆序（复用 `SwapBytes32` 交叉合成） | `liIn` |
| `FC_DL_DintToStringTrim` / `FC_DL_LrealToStringTrim` | 修剪 + 四步截断样板；浮点件统一 `NaN`/`Inf+`/`Inf-` 文本 | `uTargetMax`+`bAllowTrunc` |

### 16.3 同步族（DL_Base 1）

| 组件 | 一句话功能 | 关键引脚 |
|---|---|---|
| `FB_DL_SemaMutex` | IEC SEMA 防御包装：三态机 + **超时强制归还**（故障级 0369）+ 释放优先 | `bClaim`/`bRelease`/`tHoldMax` → `bBusy`/`bTimedOut` |

**接入要点**：实例必须每周期无条件调用；超时归还占用**一个**扫描拍过渡态，此拍内申请被拒，重试节拍按 1 拍延迟设计。

### 16.4 未经编译器验证声明（沿用既有表述）/ NOT COMPILER-VERIFIED

> **⚠️ 本批次 20 件同样未经真实 CODESYS / TwinCAT / InoProShop 编译器验证**（全库 344 件一致）。验证手段仍为：16 项静态机检全库回归 + 总监独立验算 + 人工时序推演 + IF/END_IF 配平。**本批次新增风险点**：4 件日历族与 3 件时间算术件依赖平台内建口径（`DT_TO_DINT` / `DINT_TO_DT` / `DATE_TO_DINT` / `TOD_TO_DINT` / `TIME_TO_DINT`），若目标平台 DATE 以秒承载而非天承载，`DL_DATE_DAYS_MAX` 的保守口径需整体重定——**生产导入前必须在目标平台空工程做全量编译与口径实测**。完整风险清单见第十五节。

---

*Last updated: 2026-11-16（R20 追加第十六节：20 组件接入指引 + 未编译验证声明；R18/R19 两章留 R21 补）｜ 道莅工控代码库产品总监*
'''
s = s.rstrip('\n') + '\n' + ch
open(p, 'w', encoding='utf-8', newline='').write(s)
print('LIBRARY_MANUAL ok')
