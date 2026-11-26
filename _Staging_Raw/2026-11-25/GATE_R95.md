# GATE_R95 · 编译闸门裁决报告（S4）

- 轮次：R95 ｜ 裁决对象：`_Staging_Raw/2026-11-25/r95_targets.json` 列出的 40 件新增件
- 实际路径：`C:\Library\<category>\<name>.st`（DL_Motion 10 / DL_Algo 10 / DL_Base 10 / DL_Device 10）
- 裁决人：S4 编译闸门官（dlf-gatekeeper，一票否决） ｜ 生成时间：2026-11-25
- 环境：RuSTy `plc.exe --check`（串行 jobs=1）＋ `iec_std_stub.st` ＋ 接口降级桩 22 个（排除 0）
- **本席不改任何 .st 业务代码**；下述修复建议均在 `_r95_fixprobe/` 副本上验证过可编译，交 S6 执行。

---

## 一、结论汇总

| 口径 | 结果 |
|---|---|
| 检件数 | **40** |
| PASS | **36** |
| FAIL | **4** |
| EXEMPT | **0** |
| **L1 通过率** | **39/40 = 97.5%** |
| **L2 通过率** | **37/40 = 92.5%**（真跑 `l2_check.py`，串行 jobs=1） |
| **L3 通过率** | **工具缺口：`dl_gate.py --numeric` 未实现**（见 §五）；改用手工代值回验 **19/19 项量纲量级一致，0 件不符** |
| 出口闸 N1–N4 | **39/40 通过**（`FB_DL_SevenSegMultiplexSeq` 不通过） |
| L1 总耗时 | 23.81 s（均件 0.595 s，max 0.810 s） |
| L2 总耗时 | 38.78 s（均件 **0.970 s**，min 0.75 / max 1.05） |
| 负向对照命中率 | **5/6（83.3%）**；其中任务必做的 5 个样本 **4/5** |

> 分层报数（硬要求）：**L1 39/40 ｜ L2 37/40 ｜ L3 工具缺失（手工 19/19）**。不得合并成单一通过率。

---

## 二、逐件裁决表

| 序号 | 组件名 | L1 | L2 | 错误码 | 判定 | 建议动作 |
|---|---|---|---|---|---|---|
| 1 | FC_DL_ArcCenterOffsetCalc | pass | pass | — | PASS | 入库 |
| 2 | FC_DL_HelicalTurnAdvanceCalc | pass | pass | — | PASS | 入库 |
| 3 | FC_DL_RtcpPivotOffsetCalc | pass | pass | — | PASS | 入库 |
| 4 | FC_DL_ToolLengthCompDeltaCalc | pass | pass | — | PASS | 入库 |
| 5 | FC_DL_RotFeedInvTimeCalc | pass | pass | — | PASS | 入库 |
| 6 | FC_DL_SagFeedLimitCalc | pass | pass | — | PASS | 入库 |
| 7 | FC_DL_SwivelHeadTiltLimitCalc | pass | pass | — | PASS | 入库 |
| 8 | FC_DL_CornerRoundingRadiusCalc | pass | pass | — | PASS | 入库 |
| 9 | FC_DL_RtcpTrackingErrCalc | pass | pass | — | PASS | 入库 |
| 10 | FB_DL_RtcpFiveAxisSeq | pass | pass | — | PASS | 入库 |
| 11 | FC_DL_BisectIterStep | pass | pass | — | PASS | 入库 |
| 12 | FC_DL_RegulaFalsiIterStep | pass | pass | — | PASS | 入库 |
| 13 | FC_DL_SecantIterStep | pass | pass | — | PASS | 入库 |
| 14 | FC_DL_IllinoisIterStep | pass | pass | — | PASS | 入库 |
| 15 | FC_DL_GoldenSectionIterStep | pass | pass | — | PASS | 入库（MINOR-3 挂账） |
| 16 | FC_DL_TernaryNarrowIterStep | pass | pass | — | PASS | 入库（MINOR-1 挂账） |
| 17 | FC_DL_ParabolaVertexIterStep | pass | pass | — | PASS | 入库（MINOR-4 挂账） |
| 18 | FC_DL_BrentBracketIterStep | pass | pass | — | PASS | 入库（MINOR-2 挂账） |
| 19 | FC_DL_IterTermJudge | pass | pass | — | PASS | 入库 |
| 20 | FB_DL_IterSolverRunner | pass | pass | — | PASS | 入库（OBS-1 登记） |
| 21 | FC_DL_SevenSegBcdDecode | pass | pass | — | PASS | 入库 |
| 22 | FC_DL_SevenSegHexCodeCalc | pass | pass | — | PASS | 入库 |
| 23 | FC_DL_SevenSegMinusFlagCalc | pass | pass | — | PASS | 入库 |
| **24** | **FC_DL_SevenSegBlankMaskCalc** | **pass** | **FAIL** | **E062**（L41） | **FAIL** | **交 S6（附已验证修法）** |
| 25 | FC_DL_SevenSegBrightnessPwmCalc | pass | pass | — | PASS | 入库 |
| 26 | FC_DL_SevenSegBlinkPhaseCalc | pass | pass | — | PASS | 入库 |
| 27 | FC_DL_SevenSegMultiplexPhaseCalc | pass | pass | — | PASS | 入库 |
| 28 | FC_DL_SevenSegGhostGuardCalc | pass | pass | — | PASS | 入库 |
| **29** | **FC_DL_SevenSegGlyphFontCalc** | **pass** | **FAIL** | **E037**（L39/46/47） | **FAIL** | **交 S6（附已验证修法，不予豁免）** |
| **30** | **FB_DL_SevenSegMultiplexSeq** | **pass** | **pass** | **—（出口闸 N2）** | **FAIL** | **交 S6（L2 无法发现，见 §四-3）** |
| 31 | FC_DL_PhSlopeEffCalc | pass | pass | — | PASS | 入库 |
| 32 | FC_DL_PhAsymmPotentialCalc | pass | pass | — | PASS | 入库 |
| 33 | FC_DL_OrpRefOffsetCalc | pass | pass | — | PASS | 入库 |
| 34 | FC_DL_TurbidityNtuCalc | pass | pass | — | PASS | 入库 |
| 35 | FC_DL_ChlorineDpdAbsorbCalc | pass | pass | — | PASS | 入库 |
| 36 | FC_DL_DoSalinityPermCalc | pass | pass | — | PASS | 入库 |
| 37 | FC_DL_KcellConstCalc | pass | pass | — | PASS | 入库 |
| 38 | FC_DL_SodiumPnaCalc | pass | pass | — | PASS | 入库 |
| 39 | FC_DL_AnalyzerRecalDaysCalc | pass | pass | — | PASS | 入库 |
| **40** | **FB_DL_AnalyzerTwopointCalSeq** | **BLOCK** | **FAIL** | **SYN_UNCLOSED / E007**（L48/L151/L188） | **FAIL** | **交 S6（附已验证修法）** |

---

## 三、FAIL 明细（文件 + 行号 + 错误码 + 最小修复建议）

> 全部 4 件的修法均已在 `_Staging_Raw/2026-11-25/_r95_fixprobe/` 的**副本**上复裁通过（L1 PASS + L2 `rc=0` 零 error）。**业务原件未被修改**。

### FAIL-1｜#24 `DL_Base/FC_DL_SevenSegBlankMaskCalc.st` — E062 @ L41

- **L1**：PASS（`DECL_*`/结构/红线全过）
- **L2 证据**：
  ```
  FC_DL_SevenSegBlankMaskCalc.st:41:22: error[E062]: Invalid type nature for generic argument. DINT is no ANY_BIT
  FC_DL_SevenSegBlankMaskCalc.st:41:29: warning[E067]: Implicit downcast from 'UINT' to 'INT'
  FC_DL_SevenSegBlankMaskCalc.st:41:29: warning[E160]: Implicit conversion from 'UINT' to 'INT' may change the sign
  ```
- **根因**：L41 `_uLowOnes := SHL(16#01, _uDigitsUse) - 16#01;` —— RuSTy 把 `SHL` 作为泛型 `ANY_BIT` 函数，字面量 `16#01` 被推断为 `DINT`（非 `ANY_BIT`）；第二实参 `UINT` 又被隐式降为 `INT`。
- **最小修法（已验证 L1 PASS + L2 rc=0）**：
  ```st
  _uLowOnes := SHL(BYTE#16#01, UINT_TO_INT(_uDigitsUse)) - BYTE#16#01;
  ```
- **建议动作**：交 S6，改 1 行；回 S4 用 `--no-cache` 复裁。

### FAIL-2｜#29 `DL_Base/FC_DL_SevenSegGlyphFontCalc.st` — E037 @ L39 / L46 / L47

- **L1**：PASS
- **L2 证据**：
  ```
  :39:41: error[E037]: Invalid assignment: cannot assign 'ARRAY[0..15] OF BYTE' to 'VARIABLE LENGTH ARRAY'
  :46:26: error[E037]: ...  :47:30: error[E037]: ...  :47:68: error[E037]: ...
  ```
- **根因**：RuSTy 1.0.8 的 `LOWER_BOUND` / `UPPER_BOUND` 只接受**变长数组**（`VARIABLE LENGTH ARRAY`）形参，对固定界 `ARRAY[0..15] OF BYTE` 报 E037。L29 声明处与 L48 求值处共 4 处命中。
- **最小修法（已验证 L1 PASS + L2 rc=0）**：数组界是编译期常量，用字面量 0 / 15 替换两个边界函数：
  ```st
  L39: IF UINT_TO_INT(uSlotCnt) > (15) THEN
  L46: FOR _nIdx := 0 TO (_nCnt - 1) DO
  L47: IF (_nIdx >= 0) AND (_nIdx <= 15) THEN
  ```
- **豁免评估（严格口径，结论：不予豁免）**：`LOWER_BOUND`/`UPPER_BOUND` 属 IEC 61131-3 标准函数，形式上可援引"编译器自身不支持的合法 IEC 语法"；但该处数组界是常量、存在**零行为变更的可移植改法**且已实测通过，豁免只会把 RuSTy 缺口永久固化进库。故判 FAIL，不占豁免额度。

### FAIL-3｜#30 `DL_Base/FB_DL_SevenSegMultiplexSeq.st` — 出口闸 N2（L2 无法发现）

- **L1**：PASS ｜ **L2**：PASS（语法/语义合规）
- **缺陷位置与行号证据**：
  - L94 `tonFrame (IN := (_eState <> E_DL_SevSegScanPhase.eIdle) AND (NOT _bFault), PT := _tFramePT);`
  - L159 `_tFramePT := DINT_TO_TIME(_nScanMs);   // 整帧看门狗 = 一帧时长`
  - L222–225 `ELSIF tonFrame.Q THEN _bFault := TRUE; _uFault := DL_SSQ_C_TMO; _eState := eFault;`
- **失效机制**：使能后状态机只在 `eBlank ↔ eSelect` 间循环、**永不回 `eIdle`**，故 `tonFrame.IN` 恒为 TRUE。IEC TON 仅在 `IN=FALSE` 时复位 ET，因此 ET 单调累加、**满一帧时长后 `Q` 永久为 TRUE**。此后任意一个 `tonSlot.Q=FALSE` 的 `eSelect` 拍都会落到 `ELSIF tonFrame.Q` 分支 → **必然误报 `uErrId=3` 并锁存 `eFault`**，扫描器在启动约一帧后停机（按头注 A1 参数：tScan=10ms，约 10ms 后必停）。
- **判据同类**：与 R527「累计看门狗误作本相超时」同族。`dl_gate` 的 R527 判据因 `IN` 用 `AND` 组合、且只含 1 个 `e*` 枚举量而**未触发**（见 §六-2 判据缺口）。
- **最小修复建议**：把整帧看门狗改成"每帧起点单拍脉冲"驱动，例如
  ```st
  tonFrame (IN := (_eState = E_DL_SevSegScanPhase.eBlank) AND (_nIdx = 0) AND (NOT _bFault),
            PT := _tFramePT);
  ```
  或改为"末位驻留计时"（`IN := (eState = eSelect) AND (_nIdx = _nCnt-1)`）。修完须补向量：**连续运行 ≥10 帧不得出现 `uErrId=3`**。
- **建议动作**：交 S6；复裁时 `l2_check.py --no-cache` + 向量门取证（L2 恒 PASS，不能作为修复依据）。

### FAIL-4｜#40 `DL_Device/FB_DL_AnalyzerTwopointCalSeq.st` — E007 @ L188（单 token 污染）

- **L1 证据**：`BLOCK`，`SYN_UNCLOSED` @ L48（FUNCTION_BLOCK 未闭合）+ @ L151（CASE 未闭合）
- **L2 证据**：
  ```
  :188:5: error[E007]: Unexpected token: expected expression but found (*
  :188:5: error[E007]: Unexpected token: expected KeywordSemicolon but found '(* 斜率 = ΔmV / ΔpH，…除子为常量非零）
      _fSlopeNew := (…'
  ```
- **根因（已逐码点确认）**：L188 注释收尾字符是**全角右括号 `）`（U+FF09）**，而非 `*)`（`0x2A 0x29`）。首字节 `(*` 成立、收尾不成立 → 注释自 L188 一路吞到 EOF，`END_CASE`(L237)、`END_FUNCTION_BLOCK`(L268) 全部落在注释内。这是典型的"单 token 污染"。
- **最小修法（已验证 L1 PASS + L2 rc=0）**：L188 末字符 `）` 改为 `*)`，即整行改为：
  ```st
  (* 斜率 = ΔmV / ΔpH，ΔpH = 7.00 − 4.00 = 3.00，除子为常量非零 *)
  ```
  附带效果：修复后 L1 的 6 条 `R526_CONST_ZERO_REF` WARN（L85/86/88/89/94/95）**同时消失**——它们是注释吞没导致的假阳性（这 6 个常量的引用点均在 L188 之后）。
- **建议动作**：交 S6（改 1 个字符）；回 S4 用 `--no-cache` 复裁。

---

## 四、出口闸专项 N1–N4（逐件人工核，40/40 已核）

判读口径：N1 非有限判据处须**同拍改写实值出口**为安全值；N2 锁存量在停车/复位时须清零；N3 保持量须有安全侧初值；N4 使能门输出不得被后段无条件赋值覆盖。

| 结论 | 件数 | 说明 |
|---|---|---|
| N1/N2/N3/N4 全项通过 | 39 | 36 个 FC 均为"段 0 出口预置安全侧 + 非有限自反闸（`x<>x` / `(x−x)<>(x−x)`）+ RETURN 保持安全值 + 单一出口裁决"结构，逐件核到行；3 个 FB（#10/#20/#30 除下述点外）锁存与复位路径完整 |
| N2 不通过 | 1 | #30 `tonFrame` 累计看门狗不可复位（FAIL-3，L94/L159/L222） |

**逐件要点（有实质发现者）**
- #10 `FB_DL_RtcpFiveAxisSeq`：N1 ✓（L184/L187/L190/L204 故障与非有限同拍落 `_fCompZ:=0`；L219–224 出口非有限→0）。N2 ✓（L124–128 复位沿清 `_bFault/_uFault/_fCompZ/_fAPrev/_fBPrev/_bAngSeen`；`bEnable=FALSE` 经 `eExit` 斜坡回 0 非冻结）。N3 ✓（L47–57 保持量全带初值）。N4 ✓（出口仅 L217–224 单点写）。
- #20 `FB_DL_IterSolverRunner`：N1 ✓（L161 非有限优先归因；L246–255 出口非有限→0）。N2 ✓（L149–153 复位沿清锁存/括号/计数/回灌位）。N3 ✓（L51–66）。N4 ✓（段 6 单点写）。**OBS-1**：`nIterMax=0` 且 `tTimeout=0` 时"双防死锁"同时失效，宿主不回灌即永驻 `eRun`（文档已声明 0=不限，属组态责任，登记不阻断）。
- #30 `FB_DL_SevenSegMultiplexSeq`：N1 ✓（L245–249 仅选位相输出段码，其余恒全灭）。N2 **✗**（FAIL-3）。N3 ✓（L59–63）。N4 ✓（段 9 单点写）。R7 ✓（三个 TON 在段 0 无条件刷新）。
- #40 `FB_DL_AnalyzerTwopointCalSeq`（**按修复后形态核**，原件因注释吞没无法形成有效判据链）：N1 ✓（L248–252 斜率出口非有限→0；L115 首扫斜率落 0）。N2 ✓（L122–129 复位沿清锁存/计数/快照；L146 出带计数清零）。N3 ✓（L68–79 保持量全带初值）。N4 ✓（L245–267 单点写）。

---

## 五、L3 层（工具缺口 + 手工代值回验）

- **`dl_gate.py` 无 `--numeric` 参数**（实测 `error: unrecognized arguments: --numeric`；源码 argparse 仅 `--all/--changed-only/--hours/--file/--round/--strict-decl/--selftest/--json-out/--fix-structural/--apply`）。**L3 官方闸本轮不存在，不予伪造**。
- 替代做法：对本轮含除法/系数的 19 个关键量按各件头注"验收"给出的典型值手工代值，核**量纲与量级**：

| 件 | 回验量 | 代值结果 | 期望 | 判 |
|---|---|---|---|---|
| 31 | 斜率 mV/pH | −59.1667 | −59.17 | ✓ |
| 31 | 效率 % | 100.011 | 100.0 | ✓ |
| 32 | 不对称电位 mV | 3.000 | 3.0 | ✓ |
| 33 | 修正量 / 偏移 mV | 199.0 / 0.0 | 199 / 0 | ✓ |
| 34 | NTU | 4.200 | 4.2 | ✓ |
| 35 | 余氯低档 / 高档 mg/L | 0.760 / 1.900 | 0.76 / 1.90 | ✓ |
| 36 | DO 无盐 / S=35 mg/L | 8.00 / 10.94 | 8.0 / 10.94 | ✓ |
| 37 | Kcell / 温补后 1/cm | 0.1413 / 0.11775 | 0.1413 / 0.1178 | ✓ |
| 38 | pNa / µg/L 量级 | 5.4936 / 73.8 | 5.494 / 量级内 | ✓ |
| 39 | 剩余天数 / 天换算 | 20.0 / 10.0 | 20 / 10 | ✓ |
| 30 | 槽时长 / 消隐 ms（A1） | 2 / 1 | 2 / 1 | ✓ |
| 24 | 低位全 1 掩码 n=3 | 7 | 7 | ✓ |
| 25 | 占空（128/255） | 128 | 128 | ✓ |

**L3 手工结论：19/19 一致，0 件量纲/量级不符。** 但这是 S4 手工回验，**不得**计入"L3 闸通过率"。

---

## 六、负向对照（闸有效性验证）

样本落在 `_Staging_Raw/2026-11-25/_r95_negctl/`，均以同一合法基座注入单一缺陷，L1+L2 双跑。

| 样本 | 注入缺陷 | L1 | L1 命中码 | L2 | L2 错误码 | 命中 |
|---|---|---|---|---|---|---|
| N1_miss_end_fb | 缺 `END_FUNCTION_BLOCK` | BLOCK | SYN_UNCLOSED | FAIL | **E007** | ✓ |
| N2_miss_end_if | 缺 `END_IF` | BLOCK | SYN_CROSS_END | FAIL | **E006**,E007 | ✓ |
| N3_real_subscript | REAL 作数组下标 | **PASS** | —（无判据） | FAIL | **E059** | ✓（仅 L2） |
| N4_nan_pass | NaN 直穿（除零直出到出口） | **PASS** | — | **PASS** | — | **✗ 双漏** |
| N5_dup_decl | 同名重复声明 | **PASS** | —（无判据） | FAIL | **E004** | ✓（仅 L2） |
| N6_token_pollute | 注释收尾 `*)`→`）` | **PASS** | —（无判据） | FAIL | E007 | ✓（仅 L2） |

- **总命中率 5/6 = 83.3%**；任务必做 5 样本 **4/5**。
- 历史勘误复核一致：缺 `END_FUNCTION_BLOCK` → **E007**；缺 `END_IF` → **E006**（+E007）。
- **漏检类：NaN 直穿** —— L1 无"除子未闸 / 出口无有限性闸"判据，L2 只查语法语义，NaN 是运行期问题。**该类唯一防线就是 §四的出口闸人工核**（本轮 40/40 已核）。这不是"闸失灵"，而是结构性覆盖缺口，须在 §七 补判据。

---

## 七、闸自身判据缺口（交 S4 自维护／工具链，非业务缺陷）

1. **`--numeric`（L3）未实现** → 本轮 L3 无法机器化，只能手工。建议按"文件内 `/(` 除子 + `VAR CONSTANT` 系数"自动取典型值回代。
2. **R527（累计看门狗）判据覆盖不全**：现行规则要求 `IN` 实参含 `OR` 且 ≥2 个 `e*` 枚举量；`#30` 的 `IN := (_eState <> eIdle) AND (NOT _bFault)` 因用 `AND`+单枚举量而漏检。建议扩展：`IN` 中出现"排除待机"式比较（`<> eIdle` / `= eRun` 等）且 PT = 整帧/整周期量 → MAJOR 提示。**改判据前须跑 `--selftest` 回归，本轮不动手。**
3. **`R17`（REAL/LREAL 作下标 → E059）未落地**：负向对照 N3 证明 L1 完全无此判据。建议加：`[` 内标识符 → 查其声明类型 ∈ {REAL,LREAL} → BLOCK。
4. **"注释吞没"无出口校验**：负向对照 N6 显示，若注释从首行起吞没全文件，L1 `verdict=PASS`（仅 1 条 VER_HEADER MINOR）——空件/全注释件可蒙过 L1。建议加两条：① 必须存在 `FUNCTION|FUNCTION_BLOCK|PROGRAM` 开块；② 注释字符占比 > 0.9 → BLOCK。
5. **`DECL_UNKNOWN_TYPE` 假噪声 17 处 / 4 件**：`TON`/`R_TRIG` 实例声明被判为未识别类型（WARN）。建议把 `TON/TOF/TP/R_TRIG/F_TRIG/SR/RS/CTU/CTD/RTC` 加入 `KEYWORDS` 或独立 `STD_FB` 集合。

---

## 八、系统性发现（≥3 件同源）

1. **版本头 `VERSION: x.y.z` 全轮缺失（40/40）** — 违反规范 §三.11"文件头必须含 `VERSION: x.y.z`"。本轮 40 件统一用 `｜ v1.0.0 ｜` 形式。全库口径：2081 件中仅 **583 件（28.0%）** 含 `VERSION: x.y.z`，**107 件（5.1%）** 用 `｜ vX.Y.Z ｜`。→ **这是"规范 vs 实现惯例"的二元分歧，不是单件缺陷**：需 S0 定口径（补头 or 扩正则）。本轮记为 MINOR，不阻断入库。
2. **MINOR 挂账 4 条（不阻断，须 S6 顺手修）**：
   - **MINOR-1** `#16 FC_DL_TernaryNarrowIterStep`：头注 L6–7 称"函数值非有限 → 原区间回传"，但段 0（L35）预置 `fAnew:=0.0; fBnew:=0.0` 且 L38 RETURN 早于 L42 的原样回传 → 实际区间被清零；`fRatio=1.0`（判据位）与实值不同源，与同族 `#11 Bisect`（L31 `fAnew:=fA; fBnew:=fB`）口径不一致。建议改段 0 预置为 `fAnew:=fA; fBnew:=fB`，或改头注。
   - **MINOR-2** `#18 FC_DL_BrentBracketIterStep`：同型。头注 L6–7"非有限 → 括号原样回传" vs L42 预置 `0.0/0.0`，RETURN(L46–49) 先于 L50 的 `fAnew:=fA`。
   - **MINOR-3** `#15 FC_DL_GoldenSectionIterStep` L28：`DL_GSD_PHI := 6.1803…E-1` 实为 **1/φ**，名（PHI）与值（1/φ）相反；注释已注明"1/φ"故非 R525 式误用，但存在"后人按名改"反向注入风险。建议改名 `DL_GSD_PHI_INV`。
   - **MINOR-4** `#17 FC_DL_ParabolaVertexIterStep` L27–29：三条声明注释无中文（`x1 − x2 [-] / Difference of …`），`DECL_NO_CJK` 真阳性。
3. **`R526_CONST_ZERO_REF` 6 条全为 #40 注释吞没的假阳性**（L85/86/88/89/94/95）—— 与 FAIL-4 同根，修 token 后自动消失，无需单列处理。
4. **无任何错误码达 ≥3 件**：E007×1 件（#40，含 2 条诊断）、E062×1、E037×1、出口闸×1。本轮缺陷呈"单点分布"，非批次性设计缺陷。

---

## 九、复现命令

```bash
# L1（逐件，23.81s）
python C:\Library\_tools\dl_gate.py --file C:\Library\DL_Base\FC_DL_SevenSegBlankMaskCalc.st --round R95

# L2（逐件串行；严禁 --jobs>1）
python C:\Library\_tools\l2_check.py C:\Library\DL_Base\FC_DL_SevenSegBlankMaskCalc.st

# 带行号全量诊断（l2_check 只回第一个 error）
C:\Library\_tools\rusty\plc.exe --check --error-format clang ^
  C:\Library\_tools\rusty\iec_std_stub.st ^
  C:\Library\_tools\rusty\_iface_stubs\_all_types.st ^
  C:\Library\DL_Base\FC_DL_SevenSegBlankMaskCalc.st

# 闸自检回归（本轮 PASS：10 反例全中 / 5 正例无误报）
python C:\Library\_tools\dl_gate.py --selftest
```

---

## 十、裁决结论

**BLOCK**：4 件不得入库、不得进 JSONL、不计产出。

- 36 件 PASS → 交 S0 入库。
- 4 件 FAIL → **直接派 S6**（不经 S3）：`FC_DL_SevenSegBlankMaskCalc`(#24) / `FC_DL_SevenSegGlyphFontCalc`(#29) / `FB_DL_SevenSegMultiplexSeq`(#30) / `FB_DL_AnalyzerTwopointCalSeq`(#40)。其中 #24/#29/#40 已给**实测可编译**的一行修法；#30 为逻辑缺陷（L2 恒 PASS），S6 修后**必须**回 S4 用 `--no-cache` 复裁并补向量门（连续 ≥10 帧无 `uErrId=3`）。
- 0 件豁免（`#29` 的豁免申请经评估后驳回，理由见 FAIL-2）。

---
---

# 【返修复裁】R95-RC ｜ 2026-11-26（S4 编译闸门官，一票否决）

- 触发：首裁 4 件 FAIL 直接派 S6（不经 S3）。S6 回改 **16 文件 / 18 处**，本席对 **40 件全量**重新独立裁决。
- 硬口径（逐条守）：L2 一律 `python C:\Library\_tools\l2_check.py <file> --no-cache --jobs 1`；本席实测输出 `缓存 重建`，**无一条结论来自缓存命中**。全程串行，未用 `--jobs>1`。
- 本席**未修改任何 .st 业务代码**；唯一修法验证在副本 `_r95rc_fixprobe/`（§十六）。
- 复核对象定位（mtime 实证，非口头转述）：

```
2026-11-26 00:09  DL_Base/FC_DL_SevenSegBlankMaskCalc.st
2026-11-26 00:10  DL_Base/FC_DL_SevenSegGlyphFontCalc.st
2026-11-26 00:10  DL_Device/FB_DL_AnalyzerTwopointCalSeq.st
2026-11-26 00:11  DL_Base/FB_DL_SevenSegMultiplexSeq.st
2026-11-26 00:11  DL_Motion/FC_DL_ArcCenterOffsetCalc.st
2026-11-26 00:11  DL_Motion/FC_DL_CornerRoundingRadiusCalc.st
2026-11-26 00:12  DL_Algo/FC_DL_BisectIterStep.st
2026-11-26 00:12  DL_Algo/FC_DL_IllinoisIterStep.st
2026-11-26 00:12  DL_Algo/FC_DL_SecantIterStep.st
2026-11-26 00:14  DL_Base/FC_DL_SevenSegMinusFlagCalc.st
2026-11-26 00:14  DL_Device/FC_DL_ChlorineDpdAbsorbCalc.st
2026-11-26 00:14  DL_Device/FC_DL_KcellConstCalc.st
2026-11-26 00:14  DL_Device/FC_DL_OrpRefOffsetCalc.st
2026-11-26 00:14  DL_Device/FC_DL_TurbidityNtuCalc.st
2026-11-26 00:15  DL_Algo/FB_DL_IterSolverRunner.st
2026-11-26 00:16  DL_Motion/FB_DL_RtcpFiveAxisSeq.st
```

> 其余 24 件 mtime 均早于首裁时点（23:55），S6 确未触及；按纪律仍全部 `--no-cache` 实跑复裁，未做"理论不受影响"的推定放行。

## 十一、返修复裁总览

| 口径 | 首裁 | **返修复裁** | 变化 |
|---|---|---|---|
| 检件数 | 40 | **40** | — |
| PASS | 36 | **39** | +3（原 4 FAIL 中 3 件修好） |
| FAIL | 4 | **1** | −3（新增 1 件，见 §十六） |
| EXEMPT | 0 | **0** | — |
| **L1** | 39/40 | **40/40** | 40/40 无 BLOCK/MAJOR（43 MINOR + 17 WARN 均非阻断项） |
| **L2** | 37/40 | **40/40** | 全部 rc=0，`--no-cache` 串行 |
| **L3** | 工具缺失（手工 19/19） | **工具缺失（脚本代值 32/32）** | 仍未机检化，见 §十四-5 |
| **出口闸 N1–N4** | 39/40 | **39/40** | #30 修好，但 #37 新判不通过 |
| **Inf 双判全量** | 0 件 | **11/30 浮点件** | 本轮 12 个浮点修复件中 **10 件全量** |
| **负向对照** | 5/6（必做 4/5） | **5/5** | 基座零误报 |
| 总耗时 | — | L1 38.6 s（40 件串行）/ L2 20.0 s（含接口缓存重建） | — |

> **分层报数（硬要求，禁合并）**：**L1 40/40 ｜ L2 40/40 ｜ L3 工具缺失（脚本 32/32，不计入闸通过率）**；出口闸 39/40。

## 十二、18 处修复点逐条验收（"修对了没 + 有没有引入新缺陷"）

| # | 文件 | 原议修法（S5/首裁） | 实际修复形态（行号） | 复裁证据 | 结论 |
|---|---|---|---|---|---|
| 1 | `FC_DL_SevenSegBlankMaskCalc` | L41 `SHL` 泛型实参定型（E062） | 新增 `_uShiftSrc:BYTE`、`_nShift:INT`（L21-22），L44-46 `_uShiftSrc:=16#01; _nShift:=UINT_TO_INT(...); SHL(_uShiftSrc,_nShift)-16#01` | L2 rc=0（E062/E067/E160 全消）；L3 n=3→掩码 7 | **修对** |
| 2 | `FC_DL_SevenSegGlyphFontCalc` | 固定界数组不用 `LOWER/UPPER_BOUND`（E037×4） | L40 `> 15`、L47 `(_nCnt-1)`、L48 `<= 15`，头注同步 R17 | L2 rc=0；L3 槽号 0x5B→2、0x71→15 | **修对** |
| 3 | `FB_DL_SevenSegMultiplexSeq` | 整帧看门狗改帧起点单拍驱动（N2） | 新增 `_bFrameWin`（L77），`tonFrame(IN := _bFrameWin AND NOT _bFault)`（L96）；帧首置位 L210-212、回卷清位 L225、故障/撤使能清位 L119/L233/L240 | 逐拍仿真（§十四-3①）：400 拍/50 帧，置位 50 次、位序 0,1,2,3 无漏扫、`uErrId=3` **零次**、撤使能帧窗清位 | **修对**（附 1 条 MINOR：码 3 转不可达） |
| 4 | `FC_DL_SevenSegMinusFlagCalc` | 加 `bCommonAnode` 或硬声明仅共阴（跨件极性断裂） | 新增 `bCommonAnode`（L17）；L35-39 归一到共阴域、L58-63 再回送调用方口径 | L3：共阴 `0x06|0x40=0x46`；共阳 `0xF9→0xB9`，bit6=**0（点亮）**不灭段；全库零调用方→无破坏面 | **修对**（附 MINOR：BcdDecode 侧未互写） |
| 5 | `FB_DL_AnalyzerTwopointCalSeq` | L188 注释收尾全角 `）`→`*)`（E007 吞文件） | L188 已为 `…除子为常量非零 *)`；END_CASE(L237)/END_FUNCTION_BLOCK(L268) 恢复可见 | L1 BLOCK→**PASS**（首裁 SYN_UNCLOSED@L48/L151 消失）；L2 rc=0；首裁 R526 假阳性 6 条同时消失 | **修对** |
| 6 | `FC_DL_OrpRefOffsetCalc` | 四入参双判 + 出口双判 | L51-54 四入参 `(x-x)<>(x-x)`；L79-84 出口双判写 0 并 RETURN | 扫描 4/4 全量；L3 199 mV/0 mV | **修对** |
| 7 | `FC_DL_TurbidityNtuCalc` | 六入参双判 + S/T 分量双判 | L45-50 六入参全量；L53-54 净量在闸后求 | 6/6 全量；L3 NTU=4.2 | **修对** |
| 8 | `FC_DL_ChlorineDpdAbsorbCalc` | 三入参双判 + 斜率域闸 | L48-50 三入参；`ABS(fAbsSpan)<=1E-6` L53 | 3/3 全量；L3 0.76 / 1.90 mg/L | **修对** |
| 9 | `FC_DL_KcellConstCalc` | 四入参双判 **＋ `_fDen` 加谱上限并入 L59** | 双判已加（L48-51）、出口复检 L78-81；**谱上限未加**（L64-65 只有下限 0.01） | 见 §十六：有限越界温度仍出伪有效值 | **半修** → **FAIL** |
| 10 | `FC_DL_ArcCenterOffsetCalc` | 半径 Inf 入闸 + 出口双判 | L41-45 五入参全量；L69-72 出口双判写 0 | 5/5 全量；L3 h=3.3166、dx=5、dy=3.3166 | **修对** |
| 11 | `FC_DL_CornerRoundingRadiusCalc` | `fJerkRatio` 改用实际采用进给（破代数恒等式） | L59 `_fVact:=fCornerFeedMmMin/60`，L60 `ratio=_fVact³/(r²·j)` | L3：修前 1.000000 → 修后 **0.0289352**（S5 期望 0.0289） | **修对** |
| 12 | `FB_DL_RtcpFiveAxisSeq` | eEnable/eInterp 补 `_bCfgBad`；`nAxisMode` 死引脚二选一 | L134 `(nAxisMode <> 0)` 判组态；L186-188 eEnable、L205-207 eInterp 复检并独立归码 1；头注 L14 声明"模式 1 未实现" | L2 rc=0；`CalcPivotComp` 拒收现仅剩软限位成因（不再误归码 3）；L3 Z=-40.19 mm | **修对** |
| 13 | `FC_DL_BisectIterStep` | 段 0 预置改 0，闸后才回传 | L31 `fAnew:=0; fBnew:=0`；L39 闸后 `:=fA/fB`；L35-36 四入参双判；头注 L5-6 同步 | 4/4 全量；L3 递增/fa<0→新下界 1.0 | **修对** |
| 14 | `FC_DL_SecantIterStep` | `fX0/fF0` 双判 + 零步告警 | L40-41 四入参全量；L61-62 结果复检落退化 | 4/4 全量；L3 x=1.25、Δ=-0.75。补记：双判后残余零步仅 `fF1=0`（该点即根，语义正确），无需另加 `fDelta=0` 判据 | **修对** |
| 15 | `FC_DL_IllinoisIterStep` | `fA/fB/fFa/fFb` 双判，命中即出口 0 | L43-45 五入参全量；L35 预置 0、L46 闸后才回传 | 5/5 全量；L3 侧码 1、停滞端 3→1.5 | **修对** |
| 16 | `FB_DL_IterSolverRunner` | 超时狗扩相 + `fXLo` Inf 双判 +（默认值或禁 0/0 组合） | L146-149 武装域= eEvalLo∨eEvalHi∨eRun；L166-167 三入参双判；L38-39 `nIterMax:=100`、`tTimeout:=T#5S` | 3/3 全量；L3 二分 30 次 ≪ 100；§十四-3② 误踢分析无命中 | **修对** |
| 17 | `FC_DL_OrpRefOffsetCalc`（MINOR 复核） | 头注"闸序即归因序"与实现不符 | **未改**（头注 L8 仍称"类型→非有限→温度"，实现为"非有限→类型→温度"） | 静态对读 | 留挂 MINOR-5 |
| 18 | `FC_DL_PhAsymm/…其他 MINOR 项` | 首裁 §八-2 的 MINOR-1~4 | 不在 S6 本轮范围（mtime 未变） | 见 §十七 | 留挂 |

> 18 处中 **16 处修对、1 处半修（#9 → FAIL）、1 处未落地（#17 头注口径）**；另有 2 处为"修法已隐含满足"（#14 零步判据）。

## 十三、逐件返修复裁表（40 件，逐件实跑）

| # | 组件 | 改否 | L1 | L2 | L3 | 出口闸 | **综合** | 错误码 | 建议动作 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | FC_DL_ArcCenterOffsetCalc | ✔ | pass | **pass** | script-pass | pass | **PASS** | — | 入库 |
| 2 | FC_DL_HelicalTurnAdvanceCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-6） |
| 3 | FC_DL_RtcpPivotOffsetCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库 |
| 4 | FC_DL_ToolLengthCompDeltaCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库 |
| 5 | FC_DL_RotFeedInvTimeCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-6） |
| 6 | FC_DL_SagFeedLimitCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-6） |
| 7 | FC_DL_SwivelHeadTiltLimitCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-6） |
| 8 | FC_DL_CornerRoundingRadiusCalc | ✔ | pass | **pass** | script-pass | pass | **PASS** | — | 入库（MINOR-7） |
| 9 | FC_DL_RtcpTrackingErrCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-6） |
| 10 | FB_DL_RtcpFiveAxisSeq | ✔ | pass | **pass** | script-pass | pass | **PASS** | — | 入库 |
| 11 | FC_DL_BisectIterStep | ✔ | pass | **pass** | script-pass | pass | **PASS** | — | 入库 |
| 12 | FC_DL_RegulaFalsiIterStep | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-6） |
| 13 | FC_DL_SecantIterStep | ✔ | pass | **pass** | script-pass | pass | **PASS** | — | 入库 |
| 14 | FC_DL_IllinoisIterStep | ✔ | pass | **pass** | script-pass | pass | **PASS** | — | 入库 |
| 15 | FC_DL_GoldenSectionIterStep | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-3/6） |
| 16 | FC_DL_TernaryNarrowIterStep | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-1/6） |
| 17 | FC_DL_ParabolaVertexIterStep | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-4/6） |
| 18 | FC_DL_BrentBracketIterStep | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-2/6） |
| 19 | FC_DL_IterTermJudge | — | pass | **pass** | n/a | pass | **PASS** | — | 入库 |
| 20 | FB_DL_IterSolverRunner | ✔ | pass | **pass** | script-pass | pass | **PASS** | — | 入库 |
| 21 | FC_DL_SevenSegBcdDecode | — | pass | **pass** | n/a | pass | **PASS** | — | 入库 |
| 22 | FC_DL_SevenSegHexCodeCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库 |
| 23 | FC_DL_SevenSegMinusFlagCalc | ✔ | pass | **pass** | script-pass | pass | **PASS** | — | 入库（MINOR-8） |
| 24 | FC_DL_SevenSegBlankMaskCalc | ✔ | pass | **pass** | script-pass | pass | **PASS**（首裁 FAIL→PASS） | — | 入库 |
| 25 | FC_DL_SevenSegBrightnessPwmCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库 |
| 26 | FC_DL_SevenSegBlinkPhaseCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-9） |
| 27 | FC_DL_SevenSegMultiplexPhaseCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-9） |
| 28 | FC_DL_SevenSegGhostGuardCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-9） |
| 29 | FC_DL_SevenSegGlyphFontCalc | ✔ | pass | **pass** | script-pass | pass | **PASS**（首裁 FAIL→PASS） | — | 入库 |
| 30 | FB_DL_SevenSegMultiplexSeq | ✔ | pass | **pass** | sim-pass | pass | **PASS**（首裁 FAIL→PASS） | — | 入库（MINOR-10） |
| 31 | FC_DL_PhSlopeEffCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-6） |
| 32 | FC_DL_PhAsymmPotentialCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-6） |
| 33 | FC_DL_OrpRefOffsetCalc | ✔ | pass | **pass** | script-pass | pass | **PASS** | — | 入库（MINOR-5） |
| 34 | FC_DL_TurbidityNtuCalc | ✔ | pass | **pass** | script-pass | pass | **PASS** | — | 入库 |
| 35 | FC_DL_ChlorineDpdAbsorbCalc | ✔ | pass | **pass** | script-pass | pass | **PASS** | — | 入库 |
| 36 | FC_DL_DoSalinityPermCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-6） |
| 37 | **FC_DL_KcellConstCalc** | ✔ | pass | **pass** | script-pass | **FAIL** | **FAIL** | **GATE_DEN_NO_UPPER（MAJOR）**L64-65 | **交 S6（1 行，附已验证修法）** |
| 38 | FC_DL_SodiumPnaCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-6） |
| 39 | FC_DL_AnalyzerRecalDaysCalc | — | pass | **pass** | n/a | pass | **PASS** | — | 入库（MINOR-6） |
| 40 | FB_DL_AnalyzerTwopointCalSeq | ✔ | pass | **pass** | script-pass | pass | **PASS**（首裁 FAIL→PASS） | — | 入库（MINOR-11 死引脚） |

**L1 分级明细（40 件）**：BLOCK 0 ／ MAJOR 0 ／ MINOR 43 ／ WARN 17。MINOR 全部为 `VER_HEADER` 40（沿用首裁口径：全库仅 28% 合规，规范 vs 惯例分歧，待 S0 定口径）+ `DECL_NO_CJK` 3（#17 `FC_DL_ParabolaVertexIterStep` L27-29，首裁 MINOR-4，未在本轮修复范围）。WARN 17 全为 `DECL_UNKNOWN_TYPE`（`TON`/`R_TRIG` 实例声明，闸自身假阳性，见首裁 §七-5）。

## 十四、必查专项

### 十四-1 Inf 双判覆盖率（30 个浮点件，逐件逐参列名）

口径：`(x <> x) OR ((x - x) <> (x - x))` 双判，缺一即记 ✗。**NaN 自反覆盖率 30/30 件、100% 参数；Inf 差值自减全量仅 11/30 件。**
（脚本 `_r95rc_infscan.py`，全库实扫 40 件，区分 FB 级入参与方法级入参；全库无一件使用 `(x-x)<>0.0` 变体，故不存在口径漏计。）

| 件 | 覆盖 | 浮点入参逐个列名（✓=双判到位 / ✗=只判 NaN） | 级别 |
|---|---|---|---|
| FC_DL_ArcCenterOffsetCalc | 5/5 | fX1✓、fY1✓、fX2✓、fY2✓、fRadiusMm✓ | 全量 |
| FC_DL_HelicalTurnAdvanceCalc | 0/4 | fPitchMmRev✗、fRadiusMm✗、fFeedProgMmMin✗、fSpindleRpm✗ | 全缺 |
| FC_DL_RtcpPivotOffsetCalc | 1/3 | fPivotLenMm✓、fTiltADeg✗、fTiltBDeg✗ | 部分 |
| FC_DL_ToolLengthCompDeltaCalc | 1/2 | fLenNewMm✓、fLenOldMm✗ | 部分 |
| FC_DL_RotFeedInvTimeCalc | 0/3 | fInvTimeVal✗、fDegPerRev✗、fFeedMaxDegMin✗ | 全缺 |
| FC_DL_SagFeedLimitCalc | 0/3 | fSagTolMm✗、fRadiusMm✗、fAccMaxMmS2✗ | 全缺 |
| FC_DL_SwivelHeadTiltLimitCalc | 2/4 | fTiltCmdDeg✓、fTiltPrevDeg✓、fRateMaxDegS✗、fDtSec✗ | 部分 |
| FC_DL_CornerRoundingRadiusCalc | 0/5 | fCornerAngleDeg✗、fSegLenAMm✗、fSegLenBMm✗、fFeedMaxMmMin✗、fJerkMaxMmS3✗ | 全缺 |
| FC_DL_RtcpTrackingErrCalc | 1/6 | fProgXmm✓、fProgYmm✗、fProgZmm✗、fActXmm✗、fActYmm✗、fActZmm✗ | 部分 |
| FB_DL_RtcpFiveAxisSeq | 3/3 | fPivotLenMm✓、fTiltADeg✓、fTiltBDeg✓ | **全量** |
| FC_DL_BisectIterStep | 4/4 | fA✓、fB✓、fFa✓、fFb✓ | **全量** |
| FC_DL_RegulaFalsiIterStep | 0/5 | fA✗、fB✗、fFa✗、fFb✗、fDenEps✗ | 全缺 |
| FC_DL_SecantIterStep | 4/4 | fX0✓、fX1✓、fF0✓、fF1✓ | **全量** |
| FC_DL_IllinoisIterStep | 5/5 | fA✓、fB✓、fFa✓、fFb✓、fXPrev✓ | **全量** |
| FC_DL_GoldenSectionIterStep | 0/3 | fA✗、fB✗、fTol✗ | 全缺 |
| FC_DL_TernaryNarrowIterStep | 0/4 | fA✗、fB✗、fF1✗、fF2✗ | 全缺 |
| FC_DL_ParabolaVertexIterStep | 0/6 | fX1✗、fX2✗、fX3✗、fF1✗、fF2✗、fF3✗ | 全缺 |
| FC_DL_BrentBracketIterStep | 0/7 | fA✗、fB✗、fFa✗、fFb✗、fXLast✗、fFxLast✗、fTol✗ | 全缺 |
| FC_DL_IterTermJudge | 2/2 | fWidth✓、fStep✓ | **全量** |
| FB_DL_IterSolverRunner | 3/3 | fXLo✓、fXHi✓、fTol✓ | **全量** |
| FC_DL_PhSlopeEffCalc | 0/4 | fMv1✗、fPh1✗、fMv2✗、fPh2✗ | 全缺 |
| FC_DL_PhAsymmPotentialCalc | 1/3 | fMvMeas✗、fPhMeas✗、fTempC✓ | 部分 |
| FC_DL_OrpRefOffsetCalc | 4/4 | fMeasMv✓、fRefNominalMv✓、fRefMeasMv✓、fSampleTempC✓ | **全量** |
| FC_DL_TurbidityNtuCalc | 6/6 | fScatterV✓、fTransmitV✓、fDarkV✓、fKScale✓、fZeroNtu✓、fNtuMax✓ | **全量** |
| FC_DL_ChlorineDpdAbsorbCalc | 3/3 | fAbsMeas✓、fAbsZero✓、fAbsSpan✓ | **全量** |
| FC_DL_DoSalinityPermCalc | 0/6 | fDoRaw✗、fTempC✗、fSalinityPpt✗、fPermK✗、fDoMax✗、fTempCoefPct✗ | 全缺 |
| FC_DL_KcellConstCalc | 4/4 | fStdUsCm✓、fRMeasOhm✓、fTempC✓、fTempCoefPct✓ | **全量** |
| FC_DL_SodiumPnaCalc | 0/2 | fMvMeas✗、fTempC✗ | 全缺 |
| FC_DL_AnalyzerRecalDaysCalc | 0/3 | fDriftRate✗、fDriftLimit✗、fDriftNow✗ | 全缺 |
| FB_DL_AnalyzerTwopointCalSeq | 1/2 | fMeasMv✓、fTempC✗ | 部分 |

- **计数**：浮点件 30 ｜ **全量 11** ｜ 部分 6 ｜ 全缺 13 ｜ 无浮点入参 10 件（4 件七段 + 6 件整型/时间件）。
- **本轮修复件口径**：12 个浮点修复件中 **10 件全量**（ArcCenter / RtcpFiveAxis / Bisect / Secant / Illinois / IterSolver / OrpRef / Turbidity / Chlorine / Kcell），1 件部分（AnalyzerTwopoint `fTempC`），1 件全缺（CornerRounding，出口闸兜住不失真 → MINOR-7）。
- **裁决说明（重要，避免误读）**：未入修复范围的 21 件 Inf 未全量件，本席**未据此判 FAIL** —— 首裁已按"出口值未失真 + 判据位诚实"归为 MINOR 并通过，返修复裁不追溯改判；但 SYS-1 缺口仍是本库最大系统性风险，**建议 S0 单独立项"Inf 通道全库扩面修"，本清单即为工单**。

### 十四-2 出口闸（VAR_OUTPUT 安全值 / OUT_NO_ASSIGN）

- `OUT_NO_ASSIGN` = **0 件**（40 件全部 VAR_OUTPUT 至少一处 `:=`，机械扫 + L1 交叉核对一致）。
- 故障/非有限分支实值改写的逐件核查：**39/40 通过**。逐类要点：
  - 11 个浮点 FC 的"段 0 预置安全侧 + 非有限闸 RETURN + 出口双判"三段结构齐备（#1/#6/#7/#8/#9/#11/#13/#14/#15/#33/#34/#35/#37/#40 逐行核到）。
  - 4 个 FB 的复位沿作用域三项齐备（`RtcpFiveAxisSeq` L124-128、`IterSolverRunner` L156-160、`MultiplexSeq` L115-121、`AnalyzerTwopointCalSeq` L122-129），且都不动 `_bInit`。
  - **不通过 1 件**：#37 `FC_DL_KcellConstCalc` —— 非"值不写"而是"写了伪有效值"（§十六）。

### 十四-3 修复引入新缺陷 —— 四问逐条取证

**① `FB_DL_SevenSegMultiplexSeq` 帧窗锁存是否真有单拍置位/清位、会否漏扫一帧**
逐拍仿真 `_r95rc_sim_ssq.py`（忠实翻译段 0~9 与 IEC TON 语义，IN=FALSE 即 ET 复位）：
- A1（tScan=10ms/4 位/1ms 拍，400 拍）：帧窗**置位 50 次 = 帧数 50**（0 漏帧）；选位序 `0,1,2,3,0,1,2,3,…` **无跳位**；`uErrId=3` **0 次**；终态 eSelect、`bScanOk=TRUE`。
- A1′（5ms 拍，120 拍）：同上无异常（换拍长不改变结论）。
- A2（tScan=200ms/8 位）：3 帧，位序 0..7 循环完整。
- A3（位数=1，末位即首位）：20 帧无一次误判。
- A5（撤使能）：`state=eIdle`、`_bFrameWin=FALSE`、`uErrId=0`、`uSegCode=0x00`。
- **结论**：单拍置位（帧首 eBlank+`_nIdx=0`）与单拍清位（末位回卷同拍）均成立，回卷后隔一拍重新武装，无漏扫、无累积误报。
- **但发现新问题（MINOR，非误报非挂死）**：码 3 分支**不可达**。A4 构造"物理不可能"组态 tScan=1ms/8 位（实际帧 8ms > 看门狗 2ms）仍**不报码 3** —— 因 `eSelect` 内 `IF tonSlot.Q … ELSIF tonFrame.Q` 的优先级使狗命中拍必被 tonSlot 掩蔽，且看门狗 PT=2×帧，正常组态帧恒 ≈tScan，永不满足。属"声明了不可达出口码"（与首裁 `RtcpTrackingErrCalc` 码 3 同型），**不阻断入库**；顺手修建议：把 `tonFrame.Q` 判据前移到 `eSelect` 段首（或 `eBlank` 段同判），PT 改 1.5×帧。

**② `FB_DL_IterSolverRunner` 超时狗扩到 eEvalLo/eEvalHi 后，正常求值会否被误踢**
- 语义正确性：`tonTotal.ET` 跨相不清零（IN 在 eEvalLo∨eEvalHi∨eRun 全程为 TRUE），这正是"**总**超时"（头注 L7-8 与码 4 定义一致），不是"本相超时"；离开三相（eDone/eFail/eFault 或 `tTimeout=T#0S`）即 IN=FALSE → ET 复位。
- 误踢量化：正常求解二分 30 次迭代（L3 实算 30），每拍最多 1 次迭代，≈30 拍；默认 `tTimeout=T#5S`，即 5 s 内完成 30 拍需拍周期 >166 ms 才会触限——常规 1~20 ms 扫描周期下**不可能误踢**。
- 事件优先性未被破坏：三相处均 `IF _bFed THEN … ELSIF tonTotal.Q`（L187/197/214），符合 R275。
- 结论：**无误踢、无新缺陷**；`nIterMax=100`/`tTimeout=5S` 默认值使"双防死锁同时失效"（S5 MAJOR#2）闭合。

**③ `FC_DL_SevenSegMinusFlagCalc` 新增 `bCommonAnode` 后，共阳输入是否真不灭段**
- 归一化链路：`_uBase := uSegCode XOR 16#FF`（L36）→ 在共阴高有效域 `OR` 修饰位（L58）→ `uSegCodeOut := _uOut XOR 16#FF`（L60）回送。
- 代值取证：共阳 `'1' = 0xF9`（g 位=0 表示亮？实际 g 未亮：`~0x06=0xF9`，bit6=1 → 灭）→ 叠加负号后 `0xB9`，**bit6=0（亮）**；共阴 `'1'=0x06` → `0x46`（bit6=1 亮）。同一逻辑段在两种口径下都"点亮 g"，**不出现叠加即灭段**。
- 冲突判定同源：L51 用归一后 `_uBase` 与 `_uWant` 求交，两种口径判据一致。
- 破坏面：全库对 `FC_DL_SevenSegMinusFlagCalc` **零代码调用**（仅 `BcdDecode` 头注文字提及），新增入参不破坏任何调用点；registry 签名需 S0 入库时同步（新增 BOOL 入参位于第 2 位）。
- 结论：**修对，无新缺陷**；MINOR-8：`BcdDecode` 头注未互写"调用本件须同传 bCommonAnode"（SYS-5 只做了单向）。

**④ `FC_DL_CornerRoundingRadiusCalc` 比率改用 `fCornerFeedMmMin/60` 后，分母为 0 是否有防除零**
- 分母 = `fRadiusMm² · fJerkMaxMmS3`。`fJerkMaxMmS3 ≤ 0` 由 L46 域闸拦截；`fRadiusMm = MIN(_fRmax, 20)`，而 `_fRmax = (min(段长)/2)·tan(θ/2)` 在 `θ∈(0,180)`、段长>0 下 >0（θ 与段长为 ±Inf/NaN 时由 L39-46 拦截/返回）。
- 若极端下溢使 `fRadiusMm = 0`：则 `_fVuse = EXPT(0,⅓) = 0` → `fCornerFeedMmMin = MIN(feed, 0) = 0` → `_fVact = 0` → `0/0 = NaN` → **L61 双判捕获并落 0**。故不存在 NaN 直穿。
- 代值取证：θ=90/段长 100/feed=5000/j=50000 → r=20 mm、v_jerk=16286.5 mm/min、feed=5000、**ratio=0.0289352**（量纲 [-]，落在 [0,1]）。
- 结论：**防除零成立（结构性兜底 + 出口双判）**；MINOR-7 建议补显式 `IF fRadiusMm <= 0 THEN fJerkRatio:=0` 以免依赖 0/0→NaN 的隐式路径。

### 十四-4 新增 ENUM 唯一性（全库各 1 处定义）

| 枚举 | 全库定义处数 | 属主文件 |
|---|---|---|
| `E_DL_SevSegScanPhase` | **1** | DL_Base/FB_DL_SevenSegMultiplexSeq.st |
| `E_DL_AnalyzerCalPhase` | **1** | DL_Device/FB_DL_AnalyzerTwopointCalSeq.st |
| `E_DL_RtcpSeqPhase` | **1** | DL_Motion/FB_DL_RtcpFiveAxisSeq.st |
| `E_DL_IterRunnerPhase` | **1** | DL_Algo/FB_DL_IterSolverRunner.st |

成员名 `eIdle/eFault/eBlank/eSelect` 在全库多件复用（如 `eIdle` 596 处、`eFault` 667 处），但均以 `E_DL_*.成员` 限定访问，且 4 个 FB 在 L2 全量编译下 rc=0 —— **无跨件枚举名冲突**。

### 十四-5 L3（工具缺口照实报）

`dl_gate.py` 仍**无 `--numeric` 参数**（argparse 仅 `--all/--changed-only/--hours/--file/--round/--strict-decl/--selftest/--json-out/--fix-structural/--apply`），首裁 §七-1 的缺口**本轮未修**。本席不伪造 L3 机检通过率，改用 `_r95rc_l3.py` 按 ST 表达式代值得 **32/32 一致**（覆盖 16 个修复件全部）：BlankMask n=3→7、GlyphFont 0x5B→2/0x71→15、Multiplex 槽 2/消隐 1/帧狗 20 ms、MinusFlag 0x46 与共阳 g=0、Analyzer −59.1667 mV/pH、OrpRef 199/0 mV、Turbidity 4.2 NTU、Chlorine 0.76/1.90 mg/L、Kcell 0.1413/0.11775 1/cm、ArcCenter h=3.3166/dx=5、Corner r=20/ratio=0.0289352、Bisect 1.0、Secant 1.25/−0.75、Illinois 侧 1/折半 1.5、IterSolver 30 次/√2、RtcpFiveAxis Z=−40.19 mm。**该项不计入机器闸通过率。**

## 十五、负向对照（闸有效性，5/5 全命中）

样本落 `_r95rc_negctl/`，同一合法基座 `N0_base.st`（含 METHOD/VAR/IF，L1 PASS + L2 rc=0，**零误报**）注入单一缺陷，L1+L2 双跑：

| 样本 | 注入缺陷 | L1 | L1 命中码@行 | L2 | L2 错误码 | 命中 |
|---|---|---|---|---|---|---|
| N1_miss_end_method | 缺 `END_METHOD` | BLOCK | SYN_CROSS_END @L30 | FAIL | **E006** `Missing expected Token [KeywordEndMethod]` | ✓ |
| N2_undeclared | 未声明符号 `_fGhost` | BLOCK | F_DECL_MISSING @L21 | FAIL | **E048** `Could not resolve reference to _fGhost` | ✓ |
| N3_miss_end_if | 缺 `END_IF` | BLOCK | SYN_CROSS_END @L30 | FAIL | **E006** `Missing expected Token [KeywordEndIf]` | ✓ |
| N4_miss_end_var | 缺 `END_VAR` | BLOCK | SYN_STRAY_END @L30 + SYN_UNCLOSED @L6 | FAIL | **E007** `expected KeywordEndVar but found VAR_OUTPUT` | ✓ |
| N5_token_pollute | 注释收尾 `*)`→全角 `）` | BLOCK | SYN_UNCLOSED @L6 | FAIL | **E007** `expected expression but found (*` | ✓ |

**命中率 5/5 = 100%**（首裁 4/5，因 N1 类样本换为任务指定的"缺 END_METHOD"后补全）；**基座无误报**。
> 仍存覆盖缺口（闸自维护项，非业务缺陷）：L1 对"NaN/Inf 直穿"无判据（首裁负向对照 N4 已证 L1/L2 双漏），唯一防线仍是出口闸人工核 + §十四-1 的脚本扫查。

## 十六、仍 FAIL 明细（唯一 1 件）

### RC-FAIL-1｜#37 `DL_Device/FC_DL_KcellConstCalc.st` — GATE_DEN_NO_UPPER（MAJOR）@ **L64-65**

- **L1**：PASS ｜ **L2**：PASS（rc=0，`--no-cache`）｜ **L3 算式**：PASS（0.1413 / 0.11775 与验收一致）
- **失败点不在编译，在域闸（出口闸 N1 类）**：S5 给本件的修法为"段 1 补双判 **＋ `_fDen` 加谱上限（如 >10 判非法）并入 L59**"。S6 只落地前半：L48-51 四入参 Inf 双判已加、L78-81 出口复检已加；**L64-65 温补分母仍只有下限 `DL_KCL_DFLOOR = 0.01`，无上限**。
- **失效机制（有限输入，非 Inf）**：
  ```st
  L64  _fDen := 1.0 + (fTempCoefPct / DL_KCL_HUND) * (fTempC - DL_KCL_TREF);
  L65  IF _fDen <= DL_KCL_DFLOOR THEN _bDen := TRUE; END IF      ← 只挡 ≤0.01，挡不住 +66
  L73  fKcellTcorr := _fK / _fDen;  uErrId := 0; RETURN TRUE
  ```
  `fTempC` 有限但越界（典型：温度通道 0.1 °C 分辨率、变送器满码 32767 → **3276.7 °C**）：
  `_fDen = 1 + 0.02×(3276.7−25) = 66.03` → `fKcellTcorr = 0.1413/66.03 = 0.00214 1/cm`（**偏低 66 倍**），而 `uErrId = 0`、返回 **TRUE**。下游按池常数换算电导率 → 全量程放大 66 倍失真且无任何码位告警，与首裁/S5 判定的"+Inf 伪有效池常数 0"是**同一 假安全 出口，只是改由有限输入触发**。
- **最小修法（1 行 + 1 条常量；已在副本 `_r95rc_fixprobe/FC_DL_KcellConstCalc.st` 实测 L1 PASS + L2 `--no-cache` rc=0）**：
  ```st
  (* L35 之后，VAR CONSTANT 内新增 *)
      DL_KCL_DHIM    : REAL := 10.0;    // 温补分母上限（谱外温度判非法）[-] / Upper bound of the temperature denominator
  (* L65 改为 *)
  IF (_fDen <= DL_KCL_DFLOOR) OR (_fDen > DL_KCL_DHIM) THEN _bDen := TRUE; END_IF
  ```
  附带：头注 L6-7「温补分母 ≤ 0.01 → 码 3」改为「≤0.01 或 >10（谱外温度）→ 码 3，温度修正值回退未修正值」；验收补一条 `T=3276.7 → 码 3、fKcellTcorr = fKcell`。
- **建议动作**：交 S6（不经 S3）；改后回 S4 用 `--no-cache` 单件复裁（预计 1 分钟）。

## 十七、挂账清单（MINOR/OBS，不阻断入库，须尽快顺手修）

| 编号 | 件 | 内容 | 行号 | 建议 |
|---|---|---|---|---|
| MINOR-1 | FC_DL_TernaryNarrowIterStep | 头注"非有限→原区间回传" vs 段 0 预置 0/0（与 #11 口径不一） | L34-35 vs 头注 L6-7 | 二选一对齐（首裁已挂，本轮未修） |
| MINOR-2 | FC_DL_BrentBracketIterStep | 头注"括号原样回传、uStepKind=0" vs 预置 0/0、闸先于回传 | L41-49 | 保留 0 安全侧并改头注 |
| MINOR-3 | FC_DL_GoldenSectionIterStep | `DL_GSD_PHI = 0.618` 实为 1/φ，名值相反 | L28 | 改名 `DL_GSD_INVPHI` |
| MINOR-4 | FC_DL_ParabolaVertexIterStep | 三条声明注释无中文（本轮 L1 仍报 `DECL_NO_CJK` 3 处） | L27-29 | 补中文物理意义 |
| MINOR-5 | FC_DL_OrpRefOffsetCalc | 头注 L8 称"闸序：类型→非有限→温度"，实现为"非有限→类型→温度" | L8 vs L48/L57/L67 | 改头注（S6 本轮漏项） |
| MINOR-6 | 13 件浮点件 | Inf 双判未全量（清单见 §十四-1「全缺」13 件） | 各件段 1 | 按 SYS-1 扩面修，建议独立成单 |
| MINOR-7 | FC_DL_CornerRoundingRadiusCalc | 5 入参 Inf 未闸；比率除零依赖 0/0→NaN 隐式兜底 | L39-46 / L60 | 补 Inf 双判 + 显式非零判据 |
| MINOR-8 | FC_DL_SevenSegMinusFlagCalc ↔ FC_DL_SevenSegBcdDecode | 极性契约单向：BcdDecode 头注未写"调用 MinusFlag 须同传 bCommonAnode" | BcdDecode L6 | 双方头注互写（SYS-5 闭环） |
| MINOR-9 | BlinkPhaseCalc / MultiplexPhaseCalc / GhostGuardCalc | 首裁 MINOR-9/10/11 原样保留（相位域注释、帧覆盖不足、DINT 加法溢出预判） | L18/L41-49/L34 | 下一轮顺手修 |
| MINOR-10 | FB_DL_SevenSegMultiplexSeq | 码 3（扫描超时）分支**不可达**（tonSlot 优先级掩蔽 + PT=2×帧） | L221-235 | 判据前移或 PT 改 1.5×帧；否则头注删除该承诺 |
| MINOR-11 | FB_DL_AnalyzerTwopointCalSeq | `fTempC` 死引脚：只入非有限闸（且仅 NaN），不参与任何换算 | L53 / L132-133 | 接入温度补偿式或删引脚 |
| OBS-1 | FB_DL_SevenSegMultiplexSeq | 时序量化：4 位/10 ms 组态实际帧 8 ms（整除 10/4=2，blank 1+slot 1） | L146-162 | 若亮度均匀性敏感，建议按余数分配槽长 |
| OBS-2 | 全 40 件 | `VERSION: x.y.z` 40/40 缺（沿用首裁口径：全库仅 28% 合规） | 文件头 | 待 S0 定口径（补头 or 扩正则） |
| OBS-3 | 4 件 FB | `DECL_UNKNOWN_TYPE` 17 处（TON/R_TRIG 实例），闸自身假阳性 | 各 VAR 段 | 把 TON/TOF/TP/R_TRIG/F_TRIG/SR/RS/CTU/CTD 加入闸的 STD_FB 集 |

## 十八、复现命令（本轮全部数字可重放）

```bash
# L1：逐件（40 件，38.6 s，驱动脚本保留在 _r95rc_drive.py）
python C:\Library\_Staging_Raw\2026-11-25\_r95rc_drive.py

# L2：40 件一次性串行 + 强制重建缓存（本席实际口径，20.0 s）
python C:\Library\_tools\l2_check.py --no-cache --jobs 1 ^
  --out C:\Library\_Staging_Raw\2026-11-25\_r95rc_l2.json ^
  <_r95rc_files2.txt 的 40 行绝对路径>

# 单件全量诊断（plc.exe 直调，可看全部 error/warning 与行号）
C:\Library\_tools\rusty\plc.exe --check --error-format clang ^
  C:\Library\_tools\rusty\iec_std_stub.st ^
  C:\Library\_tools\rusty\_iface_stubs\_all_types.st ^
  C:\Library\_tools\rusty\_iface_stubs\I_DL_*.st ^
  C:\Library\DL_Device\FC_DL_KcellConstCalc.st

# Inf 双判覆盖扫查（30 浮点件逐参列名）
python C:\Library\_Staging_Raw\2026-11-25\_r95rc_infscan.py

# L3 代值回验（32 项）
python C:\Library\_Staging_Raw\2026-11-25\_r95rc_l3.py

# FB_DL_SevenSegMultiplexSeq 逐拍时序仿真（帧窗/漏扫/码 3 可达性）
python C:\Library\_Staging_Raw\2026-11-25\_r95rc_sim_ssq.py

# 负向对照 5 样本（L1 + L2）
for f in N1_miss_end_method N2_undeclared N3_miss_end_if N4_miss_end_var N5_token_pollute; do
  python C:\Library\_tools\dl_gate.py --file C:\Library\_Staging_Raw\2026-11-25\_r95rc_negctl\$f.st --round R95RC_NEG
  python C:\Library\_tools\l2_check.py --jobs 1 C:\Library\_Staging_Raw\2026-11-25\_r95rc_negctl\$f.st
done

# Kcell 最小修法验证（副本，不改业务件）
python C:\Library\_tools\l2_check.py --no-cache --jobs 1 ^
  C:\Library\_Staging_Raw\2026-11-25\_r95rc_fixprobe\FC_DL_KcellConstCalc.st
```

## 十九、返修复裁结论

**39 件可入库（含首裁 3 件 FAIL 修复后转 PASS），1 件仍 BLOCK。**

- **可入库（39）**：`FC_DL_ArcCenterOffsetCalc`、`FC_DL_HelicalTurnAdvanceCalc`、`FC_DL_RtcpPivotOffsetCalc`、`FC_DL_ToolLengthCompDeltaCalc`、`FC_DL_RotFeedInvTimeCalc`、`FC_DL_SagFeedLimitCalc`、`FC_DL_SwivelHeadTiltLimitCalc`、`FC_DL_CornerRoundingRadiusCalc`、`FC_DL_RtcpTrackingErrCalc`、`FB_DL_RtcpFiveAxisSeq`、`FC_DL_BisectIterStep`、`FC_DL_RegulaFalsiIterStep`、`FC_DL_SecantIterStep`、`FC_DL_IllinoisIterStep`、`FC_DL_GoldenSectionIterStep`、`FC_DL_TernaryNarrowIterStep`、`FC_DL_ParabolaVertexIterStep`、`FC_DL_BrentBracketIterStep`、`FC_DL_IterTermJudge`、`FB_DL_IterSolverRunner`、`FC_DL_SevenSegBcdDecode`、`FC_DL_SevenSegHexCodeCalc`、`FC_DL_SevenSegMinusFlagCalc`、`FC_DL_SevenSegBlankMaskCalc`、`FC_DL_SevenSegBrightnessPwmCalc`、`FC_DL_SevenSegBlinkPhaseCalc`、`FC_DL_SevenSegMultiplexPhaseCalc`、`FC_DL_SevenSegGhostGuardCalc`、`FC_DL_SevenSegGlyphFontCalc`、`FB_DL_SevenSegMultiplexSeq`、`FC_DL_PhSlopeEffCalc`、`FC_DL_PhAsymmPotentialCalc`、`FC_DL_OrpRefOffsetCalc`、`FC_DL_TurbidityNtuCalc`、`FC_DL_ChlorineDpdAbsorbCalc`、`FC_DL_DoSalinityPermCalc`、`FC_DL_SodiumPnaCalc`、`FC_DL_AnalyzerRecalDaysCalc`、`FB_DL_AnalyzerTwopointCalSeq`
- **仍 BLOCK（1）**：`FC_DL_KcellConstCalc` → 直派 S6（1 行，修法已实测可编译），修后回本席单件 `--no-cache` 复裁。
- **入库纪律**：S0 只可对上述 39 件执行写入 registry / JSONL；`FC_DL_KcellConstCalc` 不得入库、不得进 JSONL、不计产出。`FC_DL_SevenSegMinusFlagCalc` 入库时须同步新增 `bCommonAnode : BOOL` 入参（第 2 位）到 registry 签名。
- 本席声明：复裁全程 `--no-cache` 串行，无一条 PASS 来自缓存命中；未修改任何 .st。
