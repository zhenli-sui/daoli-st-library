# GATE_R83 — 编译验证席正式裁决（一票否决）

**轮次**：R83 ｜ **件数**：40（32 FC + 8 FB）｜ **裁决时间**：2026-11-24
**判官**：编译验证席（L1 静态闸 + L2 真编译双门，缺一不算通过）
**工具链**：RuSTy `_tools/rusty/plc.exe`（--check 语义级）｜ `_tools/dl_gate.py`
**并发口径**：**jobs=1 严格串行**，一件跑完再跑下一件（40 次独立进程，总耗时 73 s）。
未使用 `--jobs>1`；本批无 E004 假阳性（实证：串行 FAIL 仅 1 件，且该件可 8 行最小复现）。

## 复现命令（所有数字均可复算）

```bash
cd C:\Library
# L2 逐件真编译（串行，jobs=1；每件一条命令）
while read f; do python _tools/l2_check.py "$f.st"; done < _Staging_Raw\2026-11-24\_r83_l2\list.txt
# 失败件取行号级明细
_tools\rusty\plc.exe --check --error-format clang _tools\rusty\iec_std_stub.st ^
  _tools\rusty\_iface_stubs\_all_types.st DL_Process\FB_DL_DyeBatchRecipeSeq.st
# L1 逐件静态闸
python _tools\dl_gate.py --file <each>.st --round R83
# 编译器缺口最小复现（8 行）
_tools\rusty\plc.exe --check _tools\rusty\iec_std_stub.st _Staging_Raw\2026-11-24\_r83_l2\probe\p1.st
```
中间产物：`_Staging_Raw\2026-11-24\_r83_l2\`（`serial.tsv` 逐件退出码、`logs\` 单件日志、`l1\` 单件 L1 JSON、`probe\` 最小复现）。

---

## 一、逐件裁决表

| 序号 | 组件名 | 裁决 | 错误码 | 行号 | 建议动作 |
|---|---|---|---|---|---|
| 1 | FC_DL_InkViscosityTempComp | PASS | — | — | 入库 |
| 2 | FC_DL_RegisterErrorCalc | PASS | — | — | 入库 |
| 3 | FC_DL_AniloxInkTransferCalc | PASS | — | — | 入库 |
| 4 | FC_DL_SpliceOverlapWidthCalc | PASS | — | — | 入库 |
| 5 | FC_DL_CutLengthDeviationCalc | PASS | — | — | 入库 |
| 6 | FC_DL_DryerSolventLoadCalc | PASS | — | — | 入库 |
| 7 | FB_DL_SpliceCountdownCtrl | PASS | — | — | 入库 |
| 8 | FC_DL_ImpulseSealDwellCalc | PASS | — | — | 入库 |
| 9 | FC_DL_DyeLiquorRatioCalc | PASS | — | — | 入库 |
| 10 | FC_DL_FabricWeightAreaCalc | PASS | — | — | 入库 |
| 11 | FC_DL_PaddingPickupCalc | PASS | — | — | 入库 |
| 12 | FC_DL_StenterHeatSetCalc | PASS | — | — | 入库 |
| 13 | FC_DL_BeamWarpLengthCalc | PASS | — | — | 入库 |
| 14 | FB_DL_DyeBathReplenishCtrl | PASS | — | — | 入库（L1 WARN 见 §三-2） |
| 15 | FC_DL_ShadeDriftIndexCalc | PASS | — | — | 入库 |
| 16 | FC_DL_YarnCountConvert | PASS | — | — | 入库 |
| 17 | FC_DL_PlatingThicknessChargeCalc | PASS | — | — | 入库 |
| 18 | FC_DL_FaradayEfficiencyCalc | PASS | — | — | 入库 |
| 19 | FC_DL_AnodeCurrentDensityCalc | PASS | — | — | 入库 |
| 20 | FC_DL_RinseDragOutCalc | PASS | — | — | 入库 |
| 21 | FB_DL_ElectrolessBathReplenishCtrl | PASS | — | — | 入库（L1 WARN 见 §三-2） |
| 22 | FC_DL_HexChromeTriRatioCalc | PASS | — | — | 入库 |
| 23 | FC_DL_BarrelRotationRpmCalc | PASS | — | — | 入库 |
| 24 | FC_DL_SortChuteTimingCalc | PASS | — | — | 入库 |
| 25 | FC_DL_BeltThroughputCalc | PASS | — | — | 入库 |
| 26 | FC_DL_DiverterLeadTimeCalc | PASS | — | — | 入库 |
| 27 | FC_DL_ScannerReadRateCalc | PASS | — | — | 入库 |
| 28 | FC_DL_ChuteFullPredict | PASS | — | — | 入库 |
| 29 | FB_DL_ToteGapReleaseCtrl | PASS | — | — | 入库（L1 WARN 见 §三-2） |
| 30 | FC_DL_AccumulationZoneFillCalc | PASS | — | — | 入库 |
| 31 | FC_DL_SlotHeightFitCalc | PASS | — | — | 入库 |
| 32 | FC_DL_PalletOverhangCalc | PASS | — | — | 入库 |
| 33 | FC_DL_ForkEntryClearanceCalc | PASS | — | — | 入库 |
| 34 | FC_DL_AsrsCycleTimeCalc | PASS | — | — | 入库 |
| 35 | FC_DL_InventoryAgeIndexCalc | PASS | — | — | 入库 |
| 36 | FC_DL_StackerMastSwayCalc | PASS | — | — | 入库 |
| 37 | FB_DL_PrintRegisterAutoTrimSeq | PASS | — | — | 入库（L1 WARN 见 §三-2） |
| 38 | FB_DL_DyeBatchRecipeSeq | **EXEMPT** | **E037** | **L122, L123, L124**（共 6 处） | 豁免入库，但须编码席本轮内做**零行为变更**改写（见 §二 最小修法） |
| 39 | FB_DL_PlatingLineTransferSeq | PASS | — | — | 入库（L1 WARN 见 §三-2） |
| 40 | FB_DL_SortDiverterSeq | PASS | — | — | 入库（L1 WARN 见 §三-2） |

---

## 二、唯一失败件剖析：FB_DL_DyeBatchRecipeSeq（EXEMPT）

### 2.1 报错原文（RuSTy，clang 格式）

```
FB_DL_DyeBatchRecipeSeq.st:122:37: error[E037]: Invalid assignment: cannot assign 'ARRAY[0..3] OF LREAL' to 'VARIABLE LENGTH ARRAY'
FB_DL_DyeBatchRecipeSeq.st:122:86: error[E037]: Invalid assignment: cannot assign 'ARRAY[0..3] OF LREAL' to 'VARIABLE LENGTH ARRAY'
FB_DL_DyeBatchRecipeSeq.st:123:37: error[E037]: Invalid assignment: cannot assign 'ARRAY[0..3] OF TIME'  to 'VARIABLE LENGTH ARRAY'
FB_DL_DyeBatchRecipeSeq.st:123:84: error[E037]: Invalid assignment: cannot assign 'ARRAY[0..3] OF TIME'  to 'VARIABLE LENGTH ARRAY'
FB_DL_DyeBatchRecipeSeq.st:124:37: error[E037]: Invalid assignment: cannot assign 'ARRAY[0..3] OF INT'   to 'VARIABLE LENGTH ARRAY'
FB_DL_DyeBatchRecipeSeq.st:124:84: error[E037]: Invalid assignment: cannot assign 'ARRAY[0..3] OF INT'   to 'VARIABLE LENGTH ARRAY'
```
6 处全部落在 L122–L124 的 `LOWER_BOUND(...)/UPPER_BOUND(...)` 实参上，**与业务逻辑无关**。

### 2.2 豁免判定依据（三条实证，缺一不予豁免）

| # | 证据 | 结论 |
|---|---|---|
| ① | 8 行最小复现 `probe/p1.st`：仅 `VAR_INPUT afA : ARRAY[0..3] OF LREAL` + `LOWER_BOUND/UPPER_BOUND(afA,1)`，零业务代码，**同样报 E037** | 缺陷来自编译器内置函数签名，非本件代码 |
| ② | `probe/p2.st`：形参改为 `VAR_IN_OUT aArr : ARRAY[*] OF LREAL` 后 `UPPER_BOUND` **编译通过（rc=0）** | RuSTy 把 `LOWER_BOUND/UPPER_BOUND` 的第一形参实现为「仅接受变长数组(VLA)」并按严格类型匹配，固定长数组被拒 |
| ③ | `grep LOWER_BOUND\|UPPER_BOUND _tools/rusty/iec_std_stub.st _tools/rusty/_iface_stubs/*.st` → **零命中** | 该函数为 RuSTy 内置，**不是我方桩定义过窄**，排除「本席工具链自伤」 |

**IEC 合法性**：IEC 61131-3 第 3 版对 `LOWER_BOUND/UPPER_BOUND` 的形参为通用 `ANY_ARRAY`（含固定长数组）；CODESYS/TwinCAT 均接受固定长数组实参。RuSTy 报错文本 `to 'VARIABLE LENGTH ARRAY'` 恰好自陈其形参被限定为 VLA —— 属**编译器覆盖缺口**，符合豁免口径「编译器自身不支持的合法 IEC 语法」。

**旁证（库内口径）**：全库 20 件使用该函数的组件中，19 件一律经 `ARRAY[*]` 变长形参使用并全部 L2 PASS（`FC_DL_LagrangeInterp`、`FC_DL_SimpsonQuad` 头注第 ⑤ 条已明文声明「变长数组仅入 VAR_IN_OUT」）。本件是唯一把 `LOWER_BOUND` 用在 `ARRAY[0..3]` 固定长 `VAR_INPUT` 上的件 —— 属**偏离既定库约定**，故豁免必须附带改写义务。

### 2.3 最小修法（交编码席执行，本席不改业务代码）

三数组上界均为字面 `0..3`（`DL_DBR_SEG_MAX = 4` 与之配套），故把动态取界换成已声明的字面界，**行为完全等价**（无任何取值范围变化）：

```iecst
// L122–L124，把 LOWER_BOUND(x,1)/UPPER_BOUND(x,1) 换成 0 / 3
_bSegOk := (nSegCount >= 1) AND (nSegCount <= DL_DBR_SEG_MAX) AND (_nSeg >= 1) AND (_nSeg <= nSegCount)
    AND ((_nSeg - 1) >= 0) AND ((_nSeg - 1) <= 3)   // afSegTarget : ARRAY[0..3]
    AND ((_nSeg - 1) >= 0) AND ((_nSeg - 1) <= 3)   // atSegHold   : ARRAY[0..3]
    AND ((_nSeg - 1) >= 0) AND ((_nSeg - 1) <= 3);  // anSegDose   : ARRAY[0..3]
```
**已验证该修法可通过**：`probe/fix_probe.st`（本件副本，仅替换上述 6 处）单独 `--check` → **0 error，rc=0**，文件其余部分无第二个缺陷。

> 备选：保留动态取界则须把三数组移入 `VAR_IN_OUT` 并声明为 `ARRAY[*]`（与库内 19 件一致），但会改动 FB 实例化接口，代价高于上式，不推荐。

### 2.4 豁免记账

| 字段 | 值 |
|---|---|
| 错误码 | E037 |
| 豁免轮次 | **第 1 轮**（全库 GATE_R79–R82 报告 `grep E037` 零命中，无历史累计） |
| P0 升级阀 | 若 R84、R85 仍以同一 E037 豁免 → 累计 3 轮，**升级 P0 强制阻断** |
| 本轮附加义务 | 编码席须在 R83 关闭前提交 §2.3 改写；改写后本席复跑单件确认转 PASS |

---

## 三、L1 静态闸结论（40/40 PASS）

`python _tools\dl_gate.py --file <each>.st --round R83` → **PASS 40 / MAJOR 0 / BLOCK 0**。

七项红线全部零命中：无 `VAR_EXTERNAL`/`GVL`、无 `%I/%Q/%M` 直接寻址、无注释嵌套、七族开闭词计数配平、`CASE` 均含 `ELSE`、声明/引用交叉核对通过、无 R527 跨相 TON。

### 3.1 系统性 MINOR：VER_HEADER（**判据与全库约定不一致，不作逐件扣分**）

40/40 件均报 `MINOR/VER_HEADER@L0`「文件头缺 VERSION: x.x.x」。核查：

- 全库 `.st` 共 **1610 件**，含 `VERSION:` 的 **0 件**；全库既有头部写法为 `版本 v1.0.0`。
- `dl_gate.py:339` 判据正则 `VERSION\s*[:：]\s*v?(\d+\.\d+\.\d+)` 不匹配中文「版本」。

→ 这是**判据缺陷（100% 假阳性）**，不是 R83 40 件的缺陷。**建议主控裁定**二选一：
(a) 保留规则 11 → 全库统一补 `VERSION: x.y.z` 头（1610 件一次性批处理）；
(b) 放宽判据为 `(VERSION|版本)\s*[:：]?\s*v?\d+\.\d+\.\d+` → 按工具链维护职责须先跑 `python _tools\dl_gate.py --selftest` 回归（20 例）通过后方可改判据。
**本轮不改判据**（避免历史报告失去可比性），按 MINOR 挂账，不阻断入库。

### 3.2 系统性 WARN：DECL_UNKNOWN_TYPE（假阳性，已逐类型核实）

7 件报 WARN，逐类型核对后全部为**已知合法类型**，L2 亦全部编译通过，判定为闸门噪声：

| 件 | 未识别类型 | 判定 |
|---|---|---|
| FB_DL_DyeBatchRecipeSeq | TON, R_TRIG, E_DL_DbrPhase, E_DL_DbrCause | 标准 FB + 同文件内 `TYPE` 声明，合法 |
| FB_DL_PlatingLineTransferSeq | TON, R_TRIG, E_DL_PltPhase, E_DL_PltCause | 同上 |
| FB_DL_PrintRegisterAutoTrimSeq | TON, R_TRIG, E_DL_PraPhase, E_DL_PraCause | 同上 |
| FB_DL_SortDiverterSeq | TON, R_TRIG, E_DL_SdvPhase, E_DL_SdvCause | 同上 |
| FB_DL_ElectrolessBathReplenishCtrl | E_DL_BathSt | 同文件内 `STRUCT` 声明，合法 |
| FB_DL_ToteGapReleaseCtrl | TON, E_DL_GapSt | 同上 |

根因：闸门未把 IEC 标准功能块（TON/R_TRIG…）与**同文件内** `TYPE` 声明纳入符号表。属闸门覆盖面缺口，建议后续把标准 FB 名表内置、`TYPE ... END_TYPE` 先入符号表再核引用。

---

## 四、门禁总表

| 层 | 工具 | 执行状态 | 结果 |
|---|---|---|---|
| L1 静态闸 | `dl_gate.py`（tree-sitter + 7 红线 + 声明交叉核对） | **已跑，40/40** | 40 PASS / 0 MAJOR / 0 BLOCK |
| L2 真编译 | RuSTy `plc.exe --check`（串行 jobs=1） | **已跑，40/40** | 39 PASS / 1 EXEMPT(E037) / 0 FAIL |
| L3 向量门 | `_TESTS\<Name>.json` | 未纳入本轮范围（本轮为 L1/L2 逐件裁决） | — |

**verdict：PASS（有条件）** —— 39 件无条件入库；`FB_DL_DyeBatchRecipeSeq` 按 §2 豁免入库，但绑定 §2.3 改写义务与 §2.4 的 P0 升级阀。**无 BLOCK 项，注册脚本可放行。**

---

TOTAL 40 | PASS 39 | FAIL 0 | EXEMPT 1 | 通过率 97.5%
