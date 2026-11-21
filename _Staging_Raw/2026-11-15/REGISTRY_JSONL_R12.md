# R12 注册与语料落库报告

> 执行范围：18 件终审通过 `.st` 的注册登记 + 训练集落条 + 全量 186 条 sha256 真验。
> 纪律确认：未修改任何 `.st`；未修改任何既有 md；未删除既有 168 条；既有条目字段零改动（sort_keys 深比较已断言相等）。

## 1 注册表前后对比

| 项 | 变更前（备份） | 变更后 |
|---|---|---|
| 文件 | `INDEX_REGISTRY.json.backup_R12`（76,846 B） | `INDEX_REGISTRY.json` |
| version | 2.0.0 | **2.1.0** |
| total_components | 168 | **186** |
| last_updated | 2026-11-15T17:55:00+08:00 | **2026-11-15T20:30:46+08:00** |
| components 数组长度 | 168 | 186 |

六目录 counts：

| 目录 | 变更前 | 新增 | 变更后 |
|---|---|---|---|
| DL_Base | 34 | +4 | **38** |
| DL_MathData | 33 | +5 | **38** |
| DL_Algo | 25 | +2 | **27** |
| DL_Device | 40 | +4 | **44** |
| DL_Motion | 16 | +1 | **17** |
| DL_Process | 20 | +2 | **22** |
| **合计** | **168** | **+18** | **186** |

既有 168 条零改动：`json.dumps(components[:168], sort_keys=True)` 与备份结果**逐字符相等**。

## 2 新增 18 条清单

| # | 名称 | 目录 | 类型 | 码位 | 复杂度 | 标签（首个为规格书 source 组标签） |
|---|---|---|---|---|---|---|
| 1 | `FC_DL_BitArrayExtract` | DL_Base | FC | `16#0001_0125~0127(信息级)` | 5 | lgf-bitlogic, bit-extraction, bit-array, bounds-check, pure-function |
| 2 | `FC_DL_BitArrayInsert` | DL_Base | FC | `16#0001_0128~012A(信息级)` | 6 | lgf-bitlogic, bit-insertion, bit-array, mask-merge, pure-function |
| 3 | `FC_DL_IntervalMembership` | DL_Base | FC | `16#0001_012B~012C(信息级)` | 3 | lgf-comparator, interval, comparison, boundary-inclusive, pure-function |
| 4 | `FB_DL_BitArrayChangeWatch` | DL_Base | FB | `16#0001_012D~012F(信息级) / 16#0001_021A~021B(故障级)` | 5 | lgf-bitlogic, change-detection, bit-array, edge-detection, state-machine |
| 5 | `FC_DL_ArrayDiffSummary` | DL_MathData | FC | `16#0001_0134~0135(信息级)` | 4 | lgf-comparator, array-compare, diff-summary, statistics, pure-function |
| 6 | `FC_DL_StringReplaceAll` | DL_MathData | FC | `16#0001_0130~0133(信息级)` | 5 | lgf-datahandling, string, replace-all, text-processing, pure-function |
| 7 | `FB_DL_StringTokenStream` | DL_MathData | FB | `16#0001_013A~013C(信息级) / 16#0001_021C~021E(故障级)` | 6 | lgf-datahandling, string, tokenizer, stream, state-machine |
| 8 | `FC_DL_SolarPositionCalc` | DL_MathData | FC | `16#0001_0136~0137(信息级)` | 7 | lgf-datetimer, solar-geometry, astronomy, time-of-day, pure-function |
| 9 | `FC_DL_ModbusExceptionParse` | DL_MathData | FC | `16#0001_0138~0139(信息级)` | 3 | oscat-network, modbus, exception-code, protocol, decoder |
| 10 | `FC_DL_WaterEnthalpy` | DL_Algo | FC | `16#0002_2101~2102(信息级)` | 3 | oscat-building, hvac, enthalpy, thermodynamics, pure-function |
| 11 | `FB_DL_ValveCharacteristic` | DL_Algo | FB | `16#0002_2001~2003(信息级) / 16#0002_2010~2012(故障级)` | 5 | isa88-process, valve, characteristic-curve, process-control, state-machine |
| 12 | `FB_DL_DeviceParamVerify` | DL_Device | FB | `16#0003_014D~014F(信息级) / 16#0003_030D~030F(故障级)` | 6 | codesys-forge-devicereader, device-parameter, verification, range-check, state-machine |
| 13 | `FB_DL_PortDiagBoard` | DL_Device | FB | `16#0003_0149~014C(信息级) / 16#0003_0309~030C(故障级)` | 6 | plcnext-diag, roadmap-p0, port-diagnostics, profinet, state-machine |
| 14 | `FB_DL_EnergyMeterAccum` | DL_Device | FB | `16#0003_0150~0152(信息级) / 16#0003_0310~0312(故障级)` | 6 | namur-ne43, energy-meter, accumulation, signal-quality, state-machine |
| 15 | `FB_DL_VacuumGaugeMux` | DL_Device | FB | `16#0003_0153~0155(信息级) / 16#0003_0313~0315(故障级)` | 6 | namur-ne43, oscat-building, vacuum-gauge, multiplexer, signal-quality |
| 16 | `FB_DL_LineInterp2Axis` | DL_Motion | FB | `16#0004_0109~010C(信息级) / 16#0004_0204~0207(故障级)` | 8 | github-topics-motion, motion-control, interpolation, 2-axis, state-machine |
| 17 | `FB_DL_BatchPhaseBase` | DL_Process | FB | `16#0005_0104~0107(信息级) / 16#0005_0203~0206(故障级)` | 8 | isa88-batch, phase-state-machine, batch-control, isa88, state-machine |
| 18 | `FB_DL_PollTempBank` | DL_Process | FB | `16#0005_0108~010A(信息级) / 16#0005_0207~0209(故障级)` | 7 | roadmap-p0, polling-scheduler, temperature-bank, multi-channel, state-machine |

- `file_path` 形如 `C:\Library\<category>\<name>.st`，与既有 168 条同构；
- `registered_at`：2026-11-15T20:30:46 ~ 20:31:37（+08:00，逐条相隔 3 s，全部晚于 19:xx 下限）；
- 字段顺序与既有 64 条带码位记录一致：name / category / type / file_path / function_tags / complexity / registered_at / code_segment / source；
- 双源件的两个源标签均入 `function_tags`（PortDiagBoard: plcnext-diag + roadmap-p0；VacuumGaugeMux: namur-ne43 + oscat-building；PollTempBank: roadmap-p0），`source` 取规格书首个源；
- `source` 与 `function_tags` 首元素严格相等（脚本内 assert 逐件校验）。

## 3 码位校验

| 校验项 | 结果 |
|---|---|
| 规格书 1.2 节码位基数 | 85（18 件，件内连续、件间不重叠） |
| 注册表 code_segment 展开集合 | 85 |
| 与规格书逐码 diff | 交集 85，**missing 0 / extra 0** |
| 与全库 168 件已占码碰撞（R30 口径重跑） | **0** |
| 特殊位 0003_0105 / 0003_0116 / 0003_0281 触碰 | 0 |

件内逐码复核：18 个 `.st` 实扫 `16#XXXX_XXXX` 字面量，85 个分配码**全部命中、零遗漏**；
多出的字面量均为哨兵与测试向量（`16#0000_0000`、`16#FFFF_FFFF`、`16#FFFF_FFFE`、`16#1234_5678`、`16#9ABC_DEF0`、
`16#0000_000F`、`16#5FFF_FFFF`、`16#FFFF_FFFA`），非码位，按 R30 口径不计。

## 4 训练集 JSONL

| 项 | 结果 |
|---|---|
| 文件 | `_AI_Training_Dataset/daoli_st_sft_dataset.jsonl`（备份 `daoli_st_sft_dataset.jsonl.backup_R12`，3,680,204 B） |
| 行数 | 168 → **186** |
| 逐行 `json.loads` | **186/186 成功** |
| 字段集 | 186 行键集均为 instruction / architecture_thought / output 三字段 |
| output 归属 | 186 行全部唯一映射到 186 个组件（无空挂、无重复、无串行） |
| **sha256(output) == sha256(.st 原始字节)** | **186/186 一致，mismatch 0** |

`output` 取值链路：`open(path, "rb").read()` → `decode("utf-8")` → `json.dumps(ensure_ascii=False)`。
全程不经过 `splitlines()`、不做换行归一化，因此 `output.encode("utf-8")` 与磁盘文件字节流 sha256 严格相等
（含 CRLF 文件亦一致）。新增件的 instruction / architecture_thought 逐件取自 `meta/<name>.json`，未改写。

## 5 历史漂移修正记录

对**全部 186 条**（非仅新增 18 条）做字节级 sha256 比对，检出历史漂移 **2 条**：

| 组件 | 目录 | 漂移性质 | 修正前 | 修正后 |
|---|---|---|---|---|
| `FB_DL_SCurveGenerator` | DL_Algo | 行尾 CRLF→LF 归一化，正文 334 行逐行相同 | 24,362 B / 0 处 CRLF | 24,696 B / 334 处 CRLF |
| `FB_DL_PulseDirStepper` | DL_Device | 行尾 CRLF→LF 归一化，正文 564 行逐行相同 | 42,936 B / 0 处 CRLF | 43,500 B / 564 处 CRLF |

根因：历史落条脚本以文本模式读取 `.st`，Python 通用换行机制把 CRLF 折成 LF（副作用，非有意改写）。
这两个文件是全库仅有的 2 个 CRLF 文件（其余 184 个为 LF），故只有它们漂移，正文语义零变化（unified diff 空）。
处理：按 `.st` 原始字节重注入 `output`，instruction / architecture_thought 保持原值不动。
修正后全量 186/186 sha256 一致。**历史漂移条数 = 2**（占历史 168 条的 1.19%）。

## 6 本轮过程中的自查返工

首次落库后复核发现：含故障级码段的 10 条新记录，`code_segment` 从规格书表格解析时带入了 Markdown 反引号
（形如 ``16#0001_021A~021B`` 被包成带反引号的字符串）。已修正解析器（逐段 strip 反引号）并对这 10 条定向重写该字段，
其余字段与既有条目未动；修正后 `code_segment` 展开仍为 85 码、diff 0，全库 0 处反引号残留。记录于此以免误判为静默改动。

## 7 结论

- 注册表：**186 条 / v2.1.0**，六目录 38 + 38 + 27 + 44 + 17 + 22 = 186，既有 168 条零改动。
- 码位：规格书 85 ↔ 注册表 85，missing 0 / extra 0 / 旧库碰撞 0。
- 语料：**186 行**，逐行可解析，output 与 `.st` sha256 **186/186** 一致，历史漂移 **2** 条已按字节修正。
- 未触碰任何 `.st` 与既有 md；备份文件：`INDEX_REGISTRY.json.backup_R12`、`daoli_st_sft_dataset.jsonl.backup_R12`。
