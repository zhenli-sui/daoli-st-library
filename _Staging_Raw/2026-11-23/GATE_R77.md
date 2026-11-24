# GATE_R77 — 编译闸席裁决报告（dlf-compile-verifier）

裁决人：编译闸席（一票否决） ｜ 轮次：R77 ｜ 日期：2026-11-23
输入清单：`_Staging_Raw/2026-11-23/_r77_files.txt`（41 件）

## 汇总

**41 件 | PASS 41 | FAIL 0 | EXEMPT 0 | 通过率 100%**

裁决：**PASS（放行入库）**。L2 真编译与 L1 静态红线双门全过，无阻断项，无 EXEMPT。

## 门禁执行记录

### L2 真编译（RuSTy 1.0.8，本地，串行 jobs=1）
- 命令：`python _tools\l2_check.py <41 文件> --out _Staging_Raw\2026-11-23\_l2_gate_R77.json`
- 结果：`PASS=41 FAIL=0 TOTAL=41`，接口预筛：可用 22 / 排除 0
- 全部 41 件 `rc=0, pass=true, first_error=""`，无依赖补轮（dep_rounds=0）
- 结果文件：`_Staging_Raw/2026-11-23/_l2_gate_R77.json`（可复现）

### L1 静态红线扫查（41 件逐件，注释剥离后精确匹配）
扫查器：`_Staging_Raw/2026-11-23/_static_scan_r77.py`（一次性工具，未触碰源码/工具链）
结果文件：`_Staging_Raw/2026-11-23/_static_scan_R77.json`

| 红线 | 内容 | 命中 |
|---|---|---|
| R1 | 零 GVL / VAR_EXTERNAL / VAR_GLOBAL（代码区） | 0 |
| R2 | 零 %I / %Q / %M 物理地址 | 0 |
| R10 | 赋值右侧禁构造式转换 TYPE(...) | 0 |
| R14 | FB 内禁 PROPERTY | 0 |
| R8/R9 | METHOD↔END_METHOD 配平 + 声明位置 | 0（本轮 FB 无 METHOD，见备注） |
| R11 | VAR 声明行分号 | 0 |
| R15 | 标识符撞 IEC 保留字（大小写不敏感） | 0 |
| R5 | 声明行同行中英双语注释 | 0 |

**静态扫查命中项：无**（修正两轮假阳性后归零，见"扫查器校准记录"）。

## 扫查器校准记录（透明留痕，非源码问题）

1. 初版逐行剥离注释 → 41/41 假阳性 R1/R2（文件头 `(* ... *)` 跨行自检文本含
   "零 GVL/VAR_EXTERNAL"、"零 %I/%Q/%M" 字样）。改为跨行注释状态机后归零。
2. 初版声明正则将 `x := ...` 赋值行误判为声明并报 R5；`x : STRING(255)` 串长限定符
   被 R10 误判。改为：R5 排除 `:=`、R10 仅查赋值右侧后归零。
   `STRING(255)` 为声明行合法类型限定符，非构造式转换，不判违规。

## 备注

- 本轮 41 件均为 FB/FC，无 INTERFACE，故无 EXEMPT 判定需求；本次 L2 预筛排除数 = 0。
- R8/R9 有效：DL_Algo 7 件 FB 均无 METHOD 段（单状态机+CASE 结构），配平检查空真通过。
- L2 使用了工具链缓存（"缓存 命中"），结果 rc=0 均为 RuSTy 真实编译产物记录，缓存
  键含文件内容哈希（工具既有机制），复跑 `l2_check.py` 同清单可复核。
- 未修改任何 .st 源文件；未写 INDEX_REGISTRY.json / JSONL。

## 逐件裁决表

| 文件 | 裁决 | 错误码 | 备注 |
|---|---|---|---|
| FB_DL_DeadbandFilter | PASS | — | L2 rc=0；静态 0 命中 |
| FB_DL_GatedUpdateFilter | PASS | — | 同上 |
| FB_DL_HoldLastGoodFilter | PASS | — | 同上 |
| FB_DL_PeakHoldFilter | PASS | — | 同上 |
| FB_DL_QuantizeFilter | PASS | — | 同上 |
| FB_DL_RateOfChangeFilter | PASS | — | 同上 |
| FB_DL_RunningAverageN | PASS | — | 同上 |
| FC_DL_StringCompareNatural | PASS | — | 同上 |
| FC_DL_StringCountChar | PASS | — | 同上 |
| FC_DL_StringCsvFieldEscape | PASS | — | 同上 |
| FC_DL_StringIsNumeric | PASS | — | 同上 |
| FC_DL_StringPadLeftZeros | PASS | — | 同上 |
| FC_DL_StringRemoveWhitespace | PASS | — | 同上 |
| FC_DL_StringRepeat | PASS | — | 同上 |
| FC_DL_StringReverse | PASS | — | 同上 |
| FC_DL_StringSplitPair | PASS | — | 同上 |
| FC_DL_StringTruncEllipsis | PASS | — | 同上 |
| FC_DL_AreaUnitConvert | PASS | — | 同上 |
| FC_DL_ConcentrationUnitConvert | PASS | — | 同上 |
| FC_DL_DensityUnitConvert | PASS | — | 同上 |
| FC_DL_EnergyUnitConvert | PASS | — | 同上 |
| FC_DL_HumidityUnitConvert | PASS | — | 同上 |
| FC_DL_InterpHoldLast | PASS | — | 同上 |
| FC_DL_InterpLogLinear | PASS | — | 同上 |
| FC_DL_InterpSegmentWeight | PASS | — | 同上 |
| FC_DL_InterpTwoPointSlope | PASS | — | 同上 |
| FC_DL_LengthUnitConvert | PASS | — | 同上 |
| FC_DL_MassUnitConvert | PASS | — | 同上 |
| FC_DL_PowerUnitConvert | PASS | — | 同上 |
| FC_DL_StatsMeanStdDev | PASS | — | 同上 |
| FC_DL_StatsMinMaxWindow | PASS | — | 同上 |
| FC_DL_StatsOutlierCount | PASS | — | 同上 |
| FC_DL_StatsPercentile | PASS | — | 同上 |
| FC_DL_StatsRmsCalc | PASS | — | 同上 |
| FC_DL_StatsZeroCrossRate | PASS | — | 同上 |
| FC_DL_TableIndexBinarySearch | PASS | — | 同上 |
| FC_DL_TableLookupDescending | PASS | — | 同上 |
| FC_DL_TableLookupNearestIndex | PASS | — | 同上 |
| FC_DL_TableReverseLookupX | PASS | — | 同上 |
| FC_DL_ViscosityUnitConvert | PASS | — | 同上 |
| FC_DL_VolumeUnitConvert | PASS | — | 同上 |

## 工具链自愈记录

**无**（l2_check.py 一次通过，未触发 stub_fix / iface_stub_gen / reorder_methods / fix_end_method）。

---

# 批 B1 复裁（4 复杂件）

裁决人：dlf-compile-verifier（R77 · 批 B1）｜时间：2026-11-23｜对象：C3~C4 复杂件 4 件

## 汇总

**4 件 | PASS 2 | FAIL 2 | EXEMPT 0 | 通过率 50%**

| 层 | 命令（可复现） | 结果 |
|---|---|---|
| L1 静态 | `python /tmp/scan.py` + `/tmp/scan2.py` + `/tmp/scan3.py`（R1/R2/R5/R8/R9/R10/R11/R14/R15 + 七族配平 + CASE-ELSE + 定时器位置） | 4/4 语法与红线 0 命中；2 件逻辑级 FAIL |
| L2 真编译 | `python _tools/l2_check.py <4 件> --jobs 1 --no-cache --out _Staging_Raw\2026-11-23\_l2_gate_R77_B1.json` | **rc=0，PASS=4 FAIL=0**（串行，jobs=1） |
| L3 向量 | `ls _TESTS/` 仅 README.md | **4 件均无向量文件 → L3 未覆盖（NOT RUN，不得计为通过）** |

> L2 结论：4 件均真实编译通过（RuSTy，接口预筛排除 0，依赖回溯 0 轮）。**本次 FAIL 全部来自 L1 逻辑级复核，与编译无关**——即"能编译但不能正确运行"。

## 逐件表

| 文件 | 裁决 | 错误码 | 原因 |
|---|---|---|---|
| FB_DL_DualEncoderDeviationWatch | **FAIL** | R77-B1-01（MAJOR） | 非有限"双判"的 Inf 支路恒假：`ABS(x−x)` 对 ±Inf 得 NaN，`NaN > EPS` 恒 FALSE → `bMotorInf`/`bLoadInf` 是死谓词。首拍即 Inf 时 `bHavePrev=FALSE` 跳过跳变闸，编码器被判有效，`fDevPos` 直接输出 Inf（L197/L201）。 |
| FB_DL_MoldCoolingZoneSeq | **FAIL** | R77-B1-02（BLOCK） | **eFault 无出口**：段 3（L226-232）`bReset` 只清 `bFaultLatch` 不改 `eState`；段 4（L239）在 `eState=eFault` 时整体跳过 CASE。复位后状态机永久停在 eFault、`bFaultCut` 恒 TRUE、全阀永久关闭，只能重启 PLC。与文件头 V4（L50"bReset 且 bEStop 回落才回 eIdle"）直接矛盾。 |
| FB_DL_AnalogInputRedundancySel | PASS | — | L2 rc=0；静态 0 命中；eFault 出口 3 条（L347/349/351）可恢复；Inf 由闭区间量程闸（L154/L159）兜住，非有限不泄漏。 |
| FC_DL_ModbusRtuFrameBuild | PASS | — | L2 rc=0；CRC16 逐位实现与规范一致且 V1~V3 数值全部复算吻合；循环边界结构性不越界（详见专项）。 |

## 复杂件专项四问（逐件结论）

### 1) FB_DL_DualEncoderDeviationWatch
- **状态机 ELSE 兜底**：✅ 有。`CASE eState OF`（L276）六态 + `ELSE`（L365）非法枚举拦截并置 1008。
- **无出口驻留相**：⚠️ 无永久死锁，但**出口不对称**。eFault 唯一出口为 `bReset AND bMotorEncValid AND bLoadEncValid`（L361），其余五态均有 `NOT bEnable → eInit` 路径，**唯独 eFault 没有**。使能跌落时跳变锁存被清（L215）→ 编码器重判有效 → 段 6 落到 `ELSE`（L409）给出 `uErrorId=0 / bError=FALSE`，而 `eStateOut` 仍报 eFault → **状态与码自相矛盾**（MINOR）。另 `bFaultLvl` 被赋值 3 次（L171/L360/L372）但全库无读取点（死内部量，MINOR）。
- **TON 无条件每周期调用**：✅ 合规。tonBlank/tonWarn/tonAlarm/tonTrip 位于 L251/L267/L268/L269，全部在 `CASE`（L276）之前，均无条件调用，无条件门控包住调用本身。
- **CRC**：N/A（无 CRC 逻辑）。
- **【新增 FAIL 依据】非有限闸半失效**：L197 `bMotorInf := (ABS(fPosMotor - fPosMotor) > DL_DEW_EPS)`。IEEE-754 下 `Inf−Inf=NaN`，任何与 NaN 的比较（含 `>`）为 FALSE → 该支路对 ±Inf 永不成立，实际只有 NaN 自反判生效。首拍 Inf：L204 `bHavePrev=FALSE` 跳过跳变闸 → L230 置 `bHavePrev:=TRUE` → L240 `fDevPos := ABS(Inf − 有限值) = Inf` **非有限值泄漏到 REAL 出口**，且 `bMotorEncValid` 误报 TRUE（诊断码错为 1006/1004 而非 1002）。**最小修法**：`bMotorInf := (fPosMotor > 3.4028235E38) OR (fPosMotor < -3.4028235E38) OR (fVelMotor > 3.4028235E38) OR (fVelMotor < -3.4028235E38)`（NaN 侧仍由自反判覆盖，两判互补）。

### 2) FB_DL_MoldCoolingZoneSeq
- **状态机 ELSE 兜底**：✅ 有。八态 `CASE`（L249）+ `ELSE`（L387）置 eFault + `bFaultLatch` + 1015。
- **无出口驻留相**：❌ **有两处**。
  1. **eFault 永久死锁（BLOCK）**：全库 `eState :=` 共 16 处（L225/230/263/265/276/278/281/288/306/314/357/359/370/372/384/390），**没有任何一条从 eFault 指向 eIdle**。段 3 的 `IF bReset THEN bFaultLatch := FALSE`（L227-228）只清锁存；随后段 4 `IF eState = eFault`（L239）走清阀分支、不进 CASE，而唯一能改状态的 CASE 被跳过 → 复位后本拍与后续每拍都停在 eFault。后果：`bFaultCut := bFaultCond OR (eState = eFault)`（L402）恒 TRUE → 8 路阀与吹扫阀永久 FALSE（L410/L412），流程不可恢复；同时段 6 因条件已回落落 `ELSE`（L432）报 `uErrorId=0 / bError=FALSE`，**状态报故障、码报正常**。**最小修法**：段 3 内 `IF bReset THEN bFaultLatch := FALSE; eState := eIdle; END_IF`（加一行，且必须在段 4 之前生效）。
  2. **eBalance 无超时兜底（MAJOR）**：出口仅 `NOT bStart`（L356）与 `tonBal.Q`（L358）；`tonBal.IN = bSpreadOk`，而 bSpreadOk 要求极差 ≤ fBalTol。若某区水温恒定偏热，`tonBal.Q` 永不成立 → 在 `bStart` 保持期间**长期驻留且分区阀全开**（L292 已开的 abZoneOn 不再复位）。对比 eZoneFlow/eDegraded 均有 `tonFlow` 超时降级兜底，eBalance 缺同级兜底。**最小修法**：为 eBalance 增 `tonBalTmo`（PT 取 tBalTime 的 3~5 倍）超时转 eBlow 或 eFault 并置信息码。
- **TON / R_TRIG 无条件每周期调用**：✅ 合规。rtrStart L204、tonHeat L206、tonFlow L208、tonBal L212、tonBlow L214 全在 `CASE`（L249）之外，无条件调用。**无 FAIL 级问题。**
- **CRC**：N/A。
- **附带（MINOR）**：L189 `bTempFinite` 同样用 `ABS(fMoldTemp − fMoldTemp) > EPS` 判 Inf → 对 ±Inf 恒假；后果是 `fMoldTemp=+Inf` 时既不报 1014 也不进 eFault，而是"永不到温"驻留 ePreHeat（安全但卡死）。修法同上（阈值直比）。

### 3) FB_DL_AnalogInputRedundancySel
- **状态机 ELSE 兜底**：✅ 有。五态 `CASE`（L190）+ `ELSE`（L355）置 eFault + 1024。
- **无出口驻留相**：✅ 无。eFault 三条出口：`NOT bEnable → eInit`（L347）、`NOT bFaultLatch AND bChanAValid → eHoldA`（L349）、`… bChanBValid → eHoldB`（L351），复位后可恢复，与头 V5 一致。eInit 在 `bEnable=FALSE` 且两路皆坏时驻留属设计意图（输出冻结），不构成死锁。
- **TON / R_TRIG**：N/A（本件无定时器/边沿实例，R7 声明 N/A，实测 0 个实例，一致）。
- **CRC**：N/A。
- **备注（MINOR，不阻断）**：L196/L203/L210 的状态推进不以 `bEnable` 为门，未使能但通道有效时会从 eInit 进到 eAvg/eHoldA，随后由段 4（L371）强制冻结输出并把 `bValid` 压回 FALSE，出口行为正确；仅 `eStateOut` 会在未使能时显示非 eInit，属诊断口径小瑕疵。

### 4) FC_DL_ModbusRtuFrameBuild
- **状态机 ELSE 兜底**：N/A（纯 FUNCTION，无状态机，0 个 CASE，与头 R6 N/A 声明一致）。
- **无出口驻留相**：N/A。
- **TON / R_TRIG**：N/A（无实例）。
- **CRC16 正确性 —— 判定：✅ 正确**（本项为本轮唯一需要数值复算的专项，已独立复算）：
  - 多项式 `16#A001`（L116）、初值 `16#FFFF`（L115）、反射式逐位算法 L166-176：`wCrcReg ^= byte`（L168）→ 取 LSB 快照（L170）→ `SHR 1`（L171）→ 位为 1 则异或 `16#A001`（L173），**与 Modbus 规范逐位实现完全一致**。
  - 低字节先发：L181 掩码取低字节 → `aFrame[nContent+1]`（L183），高字节 `SHR 8` → `aFrame[nContent+2]`（L184），顺序正确。
  - 数值复算（Python 独立实现，非引用本件代码）：`01 03 00 00 00 01` → `16#0A84`（∎ 命中 V1，尾字节 `84 0A`）；`01 03 00 00 00 0A` → `16#CDC5`（∎ 命中 V2，尾字节 `C5 CD`）；`11 03` → `16#E14D`（∎ 命中 V3，尾字节 `4D E1`）。**三条验收向量 3/3 全部吻合。**
  - **循环边界防越界**：✅ 结构性安全。清缓冲 `1..64`（L130，`DL_MB_FRAME_MAX=64` = 数组上界）；数据搬运 `1..nDataLen`（L157），nDataLen 已被 L147 的 `> 32` 闸拦下 → 最大写 `aFrame[34]`；CRC 覆盖 `1..nContent`（L166），nContent ≤ 34；CRC 追加最大写 `aFrame[36]`（L184）——全部 ≤ 64，无越界可能。移位量恒为 `1`（L171）与 `8`（L182），均 < 16 位宽，规避跨平台未定义行为。
- **备注（MINOR，不阻断）**：段 7 自检下界写 `uiFrameLen < 3`（L192），而 `uiDataLen=0 且 bAppendCrc=FALSE` 时 `uiFrameLen=2` 属合法 PDU，却会被判 1034 并返回 FALSE；同时文件头边界②（L22-23）称此时"帧长 = 3"与实际 `2`（含 CRC 为 `4`）不符。建议二选一：把下界改 `2`，或把无 CRC 的 0 长度 PDU 明确列为拒绝。V1~V6 未覆盖此组合（同属 L3 向量缺口）。

## 阻断项与处置（回派编码专家）

| 编号 | 件 | 级别 | 行号 | 最小修法 |
|---|---|---|---|---|
| R77-B1-01 | FB_DL_DualEncoderDeviationWatch | MAJOR | L197, L201 | Inf 判定改阈值直比 `x > 3.4028235E38 OR x < -3.4028235E38`，与 NaN 自反判互补 |
| R77-B1-02 | FB_DL_MoldCoolingZoneSeq | **BLOCK** | L226-232, L239 | `bReset` 清锁存同拍补 `eState := eIdle`，否则 eFault 永久死锁且与 V4 矛盾 |
| R77-B1-03 | FB_DL_MoldCoolingZoneSeq | MAJOR | L356-359 | eBalance 增加超时兜底（新 TON，PT ≥ 3×tBalTime）转 eBlow/eFault |
| R77-B1-04 | FB_DL_MoldCoolingZoneSeq | MINOR | L189, L428 | 同上 Inf 直比，否则 1014 对 Inf 永不可达、ePreHeat 驻留 |
| R77-B1-05 | FB_DL_DualEncoderDeviationWatch | MINOR | L354-363, L409 | eFault 补 `NOT bEnable → eInit` 出口，消除"状态故障/码正常"矛盾；`bFaultLvl` 接 4 或删除 |
| R77-B1-06 | FC_DL_ModbusRtuFrameBuild | MINOR | L192 / 头 L22 | 帧长下界 `3` 与 0 长度无 CRC PDU（2 字节）冲突，口径统一 |

**结论**：L2 全绿（4/4 真编译通过），但 **2 件逻辑级阻断**，其中 MoldCooling 的 eFault 死锁属安全侧不可恢复缺陷，**本轮不得入库**。AnalogInput 与 Modbus 两件建议放行（Modbus 的 CRC 已数值验证，是四件中质量最高的一件）。全部 4 件 L3 向量缺失，属系统性欠账，建议下轮统一补齐（重点补 Inf、eFault 复位、eBalance 不可达、0 长度 PDU 四类用例）。

## 工具链说明（本轮无自愈、无改动）

- 未修改任何 `.st` 源文件；未写 `INDEX_REGISTRY.json` / JSONL / 文档（本节仅追加）。
- `l2_check.py` 串行（jobs=1）一次通过，未触发 stub_fix / iface_stub_gen / reorder_methods / fix_end_method。
- 四件均不在 registry（1327 条中 0 命中），故版本头 `1.0.0` 与 code_segment 交叉核对 **N/A（新增件待注册）**；码段区间 `1001-100F / 1010-101F / 1020-102F / 1030-103F` 四段互不重叠，且 registry 中 `16#0004_10xx` 占用数为 **0**，无家族冲突。
- 静态扫描为临时脚本（`/tmp/scan*.py`），未落入 `_tools/gate_fixtures/`；建议把"Inf 双判失效"与"eFault 无出口"两例固化为 `dl_gate.py` 回归反例（当前 `gate_fixtures` 尚不存在，回归集欠账）。

---

# 批 B1 修复复裁（2 件）

裁决人：dlf-compile-verifier（R77 · 批 B1 修复复裁）｜时间：2026-11-23｜对象：R77-B1-01/02/03/04 的修复件

## 汇总

**2 件 | PASS 2 | FAIL 0 → 批 B1 阻断解除**

| 层 | 命令（可复现） | 结果 |
|---|---|---|
| L1 静态 | 内联 Python 扫描（heredoc，口径同上一节：红线 + 七族配平 + CASE-ELSE + 声明分号/双语 + ENUM `:=` + 实例位置） | 2/2 零命中；4 项修复逐条核对到位 |
| L2 真编译 | `python _tools/l2_check.py DL_Motion\FB_DL_DualEncoderDeviationWatch.st DL_Process\FB_DL_MoldCoolingZoneSeq.st --jobs 1 --no-cache --out _Staging_Raw\2026-11-23\_l2_gate_R77_B1fix.json` | **PASS=2 FAIL=0 TOTAL=2**（串行 jobs=1，日志 `缓存 重建` → 真编译，非命中旧缓存） |
| L3 向量 | `ls _TESTS/` | **两件仍无向量文件 → L3 NOT RUN，不计通过**（V6/V7 仅文字验收） |

## 逐件表

| 文件 | 裁决 | 错误码（未变） | 依据行号 |
|---|---|---|---|
| FB_DL_DualEncoderDeviationWatch | **PASS**（阻断解除，挂 MINOR 3 项） | 16#0004_1001~1008 | L202-209、L232-240、L246-250、L369-371 |
| FB_DL_MoldCoolingZoneSeq | **PASS**（阻断解除，挂 MINOR 2 项） | 16#0004_1010~1016 | L198-199、L235-245（含 L241）、L226、L375-379、L422 |

## 四条修复验证（逐条 · 带行号证据）

### 1) Inf 判据 → ✅ 已改为阈值直比，NaN 自反判保留，首拍 Inf 不再泄漏
- **改法确认**：`bMotorInf := (fPosMotor > DL_DEW_RMAX) OR (fPosMotor < -DL_DEW_RMAX) OR (fVelMotor > DL_DEW_RMAX) OR (fVelMotor < -DL_DEW_RMAX)`（L203-204）；`bLoadInf` 同构（L208-209）；`DL_DEW_RMAX := 3.4028235E38`（L164）。全库已无 `ABS(x - x)` 形式的 Inf 判据。
- **NaN 侧**：仍由自反判覆盖（L202 `fPosMotor <> fPosMotor` / 速度同式；L207 负载侧），两判互补，与头注 L196-201 的口径一致。
- **首拍 Inf 闭合性（原 FAIL 的直接成因）**：Inf → `bMotorFinite=FALSE`（L205）→ `bMotorEncValid=FALSE`（L229）→ `bDevValid=FALSE`（L246）→ **L247-250 不重算**，`fDevPos` 保持上一拍（首拍为初值 0，不再是 Inf）；`eInit` 见 `NOT bDevValid` 直接进 eFault（L293-294），码 1002（L405-407）。另 L232-237 快照只收有限值、L238-240 双侧有限才建基准，坏值不污染基准。
- **MINOR（新发现，不阻断）**：`DL_DEW_RMAX` 取 FLT_MAX，恰等于 FLT_MAX 的值不判 Inf（头注已声明为"可表示上限"，口径可接受）。

### 2) eFault 出口 → ✅ 段 3 已补 `eState := eIdle`，位于所有跳过 CASE 的分支之前，bFaultCut 可落回 FALSE
- **代码位置**：段 3（L235-245）先做 `IF bFaultCond THEN … eState := eFault`（L235-237）；`ELSIF bFaultLatch THEN IF bReset THEN bFaultLatch := FALSE（L240）; **eState := eIdle（L241）**`。该分支整体位于段 4 的 `IF eState = eFault`（L252）/ `CASE`（L262）**之前**，本拍即改变段 4 的分派路径。
- **复位后链路（V6 可达性）**：eState=eIdle → 段 4 走 else 支进 CASE eIdle（L264-279），逐路清 `abZoneOn`、清位图/完成/降级、`bValid := TRUE`（L274）→ 段 5 `bFaultCut := bFaultCond OR (eState = eFault)`（L422）**落回 FALSE** → L430 出口 `abZoneOn AND NOT bFaultCut` 恢复通路；段 6：`bFaultCond=FALSE` 跳过 L438，`bTempFinite=TRUE` 跳过 L448 → L453 `uErrorId := uInfoCode(0)`、`bError := FALSE`。原「状态报故障 / 码报正常」的矛盾消除。
- **优先级正确性**：`bReset` 与 `bFaultCond` 同拍时仍走 L235 分支保持 eFault（IF/ELSIF 顺序保证安全侧优先），不会误复位。

### 3) eBalance 超时兜底 → ✅ 新增 tonBalTmo，CASE 之外无条件每周期调用，超时转入有出口状态并置信息码
- **声明**：L134 `tonBalTmo : TON;`（同行双语注释）；倍率常量 L168 `DL_MCZ_BAL_TMO_FACTOR : INT := 5`。
- **调用位置**：L226 `tonBalTmo(IN := (eState = eBalance), PT := tBalTime * DL_MCZ_BAL_TMO_FACTOR);`，位于段 2，在 `IF eState = eFault`（L252）/ `CASE`（L262）**之外**，无条件每周期刷新；IN 挂状态量，离相即自复位，不会跨流程残留。
- **出口**：L375-379 `ELSIF tonBalTmo.Q THEN uInfoCode := 16#0004_1016; eState := eBlow;` —— 转到**有出口**的 eBlow（L389-392 → eDone），流程闭环；码 1016 已在头部码表登记（L32），落在本件 1010-101F 段内，无家族冲突。
- **判序**：L373 `tonBal.Q` 先于 L375 `tonBalTmo.Q`，正常收敛（tBalTime）优先，兜底（5×tBalTime）仅在永不收敛时触发。
- **MINOR（不阻断）**：① `uInfoCode` 每拍 L175 复位为 0，故 1016 仅在跃迁那一拍可见，下一拍归 0（不锁存，诊断侧只能抓到单拍）；② 跃迁拍 `bBlowValve`（L432）已 TRUE 而 `abZoneOn` 仍是 eBalance 留下的开阀态（eBlow 的清阀 FOR 在 L385，下一拍才执行），分区阀与吹扫阀同拍重叠 1 个扫描周期——与既有 `tonBal.Q` 路径（L373-374）完全同一行为，**非本次修复引入**。

### 4) 回归：修复未引入新问题 → ✅ 全绿
- **配平**：DW `IF` 21/21、`CASE` 1/1、`FUNCTION_BLOCK` 1/1、`TYPE` 1/1；MCZ `IF` 23/23、`FOR` 8/8、`CASE` 1/1、`FUNCTION_BLOCK` 1/1、`TYPE` 1/1。
- **CASE-ELSE**：DW L373 `ELSE`（置 eFault + 1008）、MCZ L407 `ELSE`（eFault + bFaultLatch + 1015），均大小写合规、注释内不计。
- **声明**：去注释后 100% 以 `;` 结尾（含数组声明 L109/L110/L118 of MCZ），逐行双语注释缺项 **0**（中英均存在）。
- **ENUM 成员**：DW L74-79、MCZ L81-88 全部 `name := 常量` 形式，同行双语注释。
- **R10 构造式转换**：赋值右侧零 `TYPE(...)`；仅用标准函数 `WORD_TO_INT`（MCZ L314/L340）与 `SHL`（L312/L338），符合 R10 口径（同 R76 裁定）。
- **R1/R2**：无 `VAR_EXTERNAL` / `GVL`、无 `%I` `%Q` `%M`、无嵌套注释；**无 PROPERTY / METHOD**（接口预筛排除 0）。
- **R7 定时器/边沿**：DW L259/275/276/277，MCZ L214/216/218/222/224/**226**，全部在 CASE 之外无条件调用，无一被塞进分支。
- **版本头**：两件 `VERSION: 1.0.1` 与修订历史行同文件一致（DW L4/L42、MCZ L4/L42），修订说明与本次实际改动相符（非仅改号）。

## 挂账（MINOR，本轮不阻断，建议下轮清）

| 编号 | 件 | 行号 | 内容 |
|---|---|---|---|
| M1 | DW | L362-371、L405-419 | R77-B1-05 未修：eFault 仍无 `NOT bEnable → eInit` 出口；`bEnable` 跌落且编码器恢复有效时，`eStateOut=eFault` 而 `uErrorId=0/bError=FALSE`，状态与码仍不对称（诊断口径） |
| M2 | DW | L147、L173、L368、L380 | `bFaultLvl` 三处赋值、全库零读取（死内部量），接出口或删除 |
| M3 | DW | L164 | `DL_DEW_RMAX = FLT_MAX`，恰等于 FLT_MAX 的输入不判 Inf（边界口径，已在头注披露） |
| M4 | MCZ | L175、L378 | 码 1016 不锁存，仅跃迁单拍可见 |
| M5 | MCZ | L432、L385 | 跃迁拍吹扫阀与分区阀同拍重叠 1 扫描周期（既有 tonBal 路径同构） |

## 结论

**批 B1 两件修复复裁通过，解除阻断**：1 个 BLOCK（R77-B1-02 eFault 死锁）+ 2 个 MAJOR（R77-B1-01 Inf 死谓词、R77-B1-03 eBalance 无兜底）+ 1 个 MINOR（R77-B1-04 Inf 不可达）**全部按最小修法落实且未引入回归**，L2 串行真编译 2/2 PASS。**可入库**。
唯一硬性欠账：**L3 向量仍缺**（V1~V7 全部只是文字验收），按门禁模型不得以 L1+L2 替代 L3——建议下轮优先补 `_TESTS\FB_DL_DualEncoderDeviationWatch.json`（首拍 Inf / NaN / 跳变 / 复位后 1002 可清）与 `_TESTS\FB_DL_MoldCoolingZoneSeq.json`（V6 复位回 eIdle / V7 5×tBalTime 超时 / 急停与 bReset 同拍）。

## 工具链说明（本轮零改动）

- 未修改任何 `.st` 源文件；未写 `INDEX_REGISTRY.json` / JSONL / 其他文档（本节仅追加）。
- `l2_check.py` 以 `--jobs 1 --no-cache` 串行执行一次通过，日志 `缓存 重建` 证明为真编译，未触发 stub_fix / iface_stub_gen / reorder_methods / fix_end_method。
- 本轮静态扫描仍为内联 heredoc，未沉淀为 `_tools/gate_fixtures/` 回归例；「Inf 阈值直比失效」与「eFault 无出口」两反例仍为欠账，建议连同「eBalance 无兜底」一例共 3 例固化。
