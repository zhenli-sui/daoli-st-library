# AUDIT_R11 —— 库级缺陷修复与全库机检审计

- 轮次：R11（增量复检轮，专治存量件「机检旧版全过、三平台编译必败」的声明性缺陷）
- 执行：PLC编程专家（受 daoli-library-director 编码规范约束）
- 机检脚本：`C:\Library\_Staging_Raw\2026-11-15\redline_check_r11.py`（9 项，R7 = 赋值目标声明性）
- 全库快照：**167 件**（存量 152 + 本轮新增已落盘 15；新增计划 16 件，审计期间仍在落盘，件数由 162→163→165→166→167→168 递增，故本报告数值绑定该 167 件快照；报告定稿时已增至 168 件，增量均为新增未注册件且全部 PASS，不影响任何结论）
- 快照时刻：2026-11-15 17:5x
- 报告性质：只出结论、不越权改码。本轮仅修改被指派 3 个存量文件；其余发现的真缺陷**只登记不修改**。

---

## 一、本轮 3 处修复明细

三处全部属历史 **D-01 同型**：赋值目标在本文件声明区内找不到（`:=` 左侧根标识符未声明）。
三平台（CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop）均在编译期报「未知标识符」，属编译阻断。

### 1. `C:\Library\DL_Device\FB_DL_PneumaticCylinder.st`

| 项 | 内容 |
|---|---|
| 原缺陷行 | L105 `_uCycleCount := _uCycleCount + 1;` |
| 语义判定 | **变量名前缀笔误**，不是缺声明。证据链：① `VAR_OUTPUT` L57 已声明 `uCycleCount : UDINT`（注释「行程计数，缩回到位上升沿 +1」）；② 该输出全文**零写入**（孤儿输出）；③ `_uCycleCount` 全文仅此 1 处出现，且无任何声明。三项互证 → 本意即写公共输出 `uCycleCount`，多打了一个下划线前缀。 |
| 改法 | `_uCycleCount` → `uCycleCount`（不含下划线） |
| 修复后行 | **L110**：`uCycleCount := uCycleCount + 1; // 完整行程 +1（One completed stroke added）` |
| 类型说明 | 无需新增声明，`UDINT` 自增不溢出（42 亿次行程）；FB 输出跨周期保持，故 `uCycleCount := uCycleCount + 1` 读自身保有值合法，不引入首扫问题。 |
| 版本 | 1.0.0 → **1.0.1**（头注释 L4），修订记录新增 v1.0.1 行 |

### 2. `C:\Library\DL_Device\FB_DL_SingleSolenoidCyl.st`

| 项 | 内容 |
|---|---|
| 原缺陷行 | L126 `_uCycleCount := _uCycleCount + 1;` |
| 语义判定 | **同上型笔误**。证据链：① `VAR_OUTPUT` L68 已声明 `uCycleCount : UDINT`（注释「行程计数，缩回判定沿 +1」）；② 该输出全文零写入；③ `_uCycleCount` 无声明且全文仅 1 处。头注释亦明示「非接口成员 bSolenoidExt/bMoving/uCycleCount 保留 VAR_OUTPUT」。 |
| 改法 | `_uCycleCount` → `uCycleCount` |
| 修复后行 | **L131**：`uCycleCount := uCycleCount + 1; // 完整行程 +1（One completed stroke added）` |
| 版本 | 1.0.0 → **1.0.1**，修订记录新增 v1.0.1 行 |

### 3. `C:\Library\DL_MathData\FC_DL_QuickSortLReal.st`

| 项 | 内容 |
|---|---|
| 原缺陷行 | L195 / 198 / 201 三处赋值；L207 / 208 两处下标引用（`afData[nPivotIdx]`） |
| 语义判定 | **真·内部状态量漏声明**，不是笔误。证据链：① 变量扮演「三数取中后枢轴所在下标」，先置默认尾位 `nHi`，再按六种大小关系改判 `nMid` / `nLo`；② 随后段 5.3a 用它做枢轴归位交换（`afData[nPivotIdx] := afData[nHi]`）；③ 无任何已声明变量可替代（`nMid` 仅中点、`nJ` 是分区边界且此处尚未赋值）。故按「补声明」处置。 |
| 改法 | `VAR` 区补声明，插在 `nMid` 之后（三数取中簇内，就近可读）：<br>`nPivotIdx     : INT;  // 三数取中后枢轴所在下标（先归位到区间末位） / Index of the median-of-three pivot, relocated to the interval tail` |
| 类型依据 | `INT`。与同簇 `nLo` / `nHi` / `nMid` / `nJ` 及数组下标 `ARRAY[0..63]` 同型；不选 `UDINT`，避免与 `nLo - 1`、`nJ + 1` 等有符号算术混算触发隐式转换（规范三：禁隐式转换）。 |
| 修复后行 | 声明 **L84**；使用点 L200 / L203 / L206 / L212 / L213（原 195/198/201/207/208，因头注释与声明各增行而整体下移） |
| 逻辑改动 | **零**。仅补声明，算法本体未动一字（避免掩盖式修复）。 |
| 版本 | 1.0.0 → **1.0.1**，修订记录新增 v1.0.1 行 |

**未采用的做法（明确排除）**：删除赋值行、把变量改成魔法数常量、把 `nPivotIdx` 折进 `nMid` 复用（会破坏六种大小关系的可读性并改变枢轴语义）。三处均保留原有赋值语义。

---

## 二、复检结果（修复后单件）

```
python redline_check_r11.py <3 个文件>
```

| 文件 | 行数 | 结果 | 硬缺陷 | 提示 |
|---|---|---|---|---|
| FB_DL_PneumaticCylinder.st | 332 | **PASS** | 0 | 0 |
| FB_DL_SingleSolenoidCyl.st | 324 | **PASS** | 0 | 0 |
| FC_DL_QuickSortLReal.st | 386 | **PASS** | 0 | 0 |

结论：3/3 PASS，硬缺陷 0，退出码 0。

---

## 三、全库机检总览（167 件快照）

| 分组 | 件数 | PASS | FAIL | 硬缺陷 | 提示 |
|---|---|---|---|---|---|
| 存量（已注册 INDEX_REGISTRY 152 件） | 152 | 151 | **1** | 2 | 22 |
| 本轮新增（未注册、仍在落盘） | 15 | 15 | 0 | 0 | 0 |
| **合计** | **167** | **166** | **1** | **2** | **22** |

按子库（167 件快照）：DL_Base 34｜DL_Device 40｜DL_MathData 33｜DL_Algo 25｜DL_Motion 16｜DL_Process 19。
与注册表 counts（32/36/29/24/15/16）之差即本轮新增已落盘份额：DL_Base +2｜DL_Device +4｜DL_MathData +4｜DL_Algo +1｜DL_Motion +1｜DL_Process +3 = 15 件。

**本轮修复贡献**：R29 检出的 3 件 5 处赋值目标性缺陷全部消除，全库硬缺陷由 5 降至 2，且剩余 2 处已定位到单一文件。

---

## 四、剩余失败项清单与原因分类

### 4.1 硬缺陷（仅 1 件，2 处，均存量）

| 文件:行 | 规则 | 报错 | 原因分类 | 裁定 |
|---|---|---|---|---|
| `DL_Process/FB_DL_LeakTestStation.st:342` | R7 | 赋值目标未在声明区找到：`_fDeltaP` | **D-01 同型真缺陷（变量名笔误）** | 待修，本轮不改 |
| `DL_Process/FB_DL_LeakTestStation.st:352` | R7 | 同上 | 同上 | 待修，本轮不改 |

**根因判定（已取证）**：`VAR_OUTPUT` L134 声明 `fDeltaP : REAL`（「测量窗压降 [kPa]，锁存」），全文**零写入**；内部声明 `_fDeltaPInt : REAL`（L156）则被正确使用；`_fDeltaP` 无声明，全文仅 L342/L352 两处，且均为 `_fDeltaP := _fDeltaPInt;`（大漏快判路径 + 测量窗到期结算路径）。
→ 与 PneumaticCylinder / SingleSolenoidCyl **完全同型**：应写公共输出 `fDeltaP`，误加下划线前缀。
→ 修复动作（下一轮）：`_fDeltaP` → `fDeltaP`（2 处），版本 1.0.0→1.0.1，勿删赋值行。
**影响**：除编译阻断外，`fDeltaP` 现恒为 0，上层读压降恒 0 —— 属功能性缺口。

### 4.2 新增件（本轮 16 件，不作缺陷结论）

- 最终快照 15 件已落盘，全部 PASS。
- 过程中 `DL_Process/FB_DL_PressFitStation.st` 曾在早期快照报 R7 `_fEnvDevMax`（同一 D-01 同型笔误，`fEnvDevMax` 为既有输出）。该文件在审计期间被作者持续改写（同一缺陷行号由 L340 漂移到 L297），到最终快照已 PASS、`_fEnvDevMax` 已不存在。
- 裁定：**属在写文件，过程态不构成缺陷结论**；但提示主控，该件曾出现同型笔误，注册前请以落盘终版再机检一次。

---

## 五、审计新增发现（真缺陷，仅登记，未修改）

### 5.1 【高】枚举成员用单冒号 `:` 代替赋值号 `:=` —— 5 行 / 3 文件，三平台编译必败

IEC 61131-3 枚举成员赋值必须写 `:=`；写成 `eXxx : 30` 会被解析为「成员名 : 类型」，30 不是类型名 → 语法错误。**此缺陷 R11 脚本不判 fail**（`ENUM_MEMBER_RE` 只认 `:=`，未匹配到的成员被静默丢弃），仅在 R8 提示级侧面漏出，与 D-01 一样属于「机检旧版全过、编译必败」。

| 文件:行 | 现状 | 应为 |
|---|---|---|
| `DL_Device/I_DL_AnalogSensor.st:39` | `eWireBreakLow : 30,` | `eWireBreakLow := 30,` |
| `DL_Device/I_DL_AnalogSensor.st:40` | `eWireBreakHigh: 40,` | `eWireBreakHigh := 40,` |
| `DL_Device/I_DL_FlowMeter.st:43` | `eFlowOk    : 20,` | `eFlowOk := 20,` |
| `DL_Device/I_DL_FlowMeter.st:44` | `eLowCutoff : 30,` | `eLowCutoff := 30,` |
| `DL_Motion/FB_DL_AxisRelativeMove.st:75` | `eMoving : 10` | `eMoving := 10` |

- 3 文件均已注册（存量），同文件其余成员写法正确（`eIdle := 0,` 等），可确认是漏敲 `=`。
- 全库扫描口径：`TYPE X :` + 下一行 `(` 起、至 `)` 止的成员行，凡「标识符 + 单冒号 + 数字」即命中；全库仅上 5 行。
- 连带效应：`FB_DL_AxisRelativeMove.st` 因 `eMoving` 未被解析为枚举成员，R8 才报出「标签不在枚举定义内」——**R8 这条提示是真缺陷的探头，不是误报**（详见 §6.2）。
- 建议：下一轮按「标点勘误」批量修 5 行，并在脚本 R8 增补「枚举成员缺 `=`」硬判，防止再次漏网。

### 5.2 【中，非编译阻断】声明后正文零引用的孤儿符号 9 个（观察项）

启发式扫描（声明区收集 VAR / VAR_OUTPUT 符号，再统计正文 + METHOD/PROPERTY 内引用次数 = 0）：

| 文件 | 符号 | 类型 | 备注 |
|---|---|---|---|
| `DL_Process/FB_DL_LeakTestStation.st` | `fDeltaP` | VAR_OUTPUT | 与 §4.1 同一根因，修笔误后自动解决 |
| `DL_Device/FB_DL_VacuumEjector.st` | `bHolding` | VAR_OUTPUT | 输出恒 FALSE，头注释却声明「真空确认态为 TRUE」→ **功能缺口，建议复核** |
| `DL_Motion/FB_DL_ElectronicGear.st` | `fNewRatio` | VAR | 死变量，仅占内存 |
| `DL_Base/FB_DL_GuardLockDoor.st` | `_bPendAuditClr` | VAR | 死变量（复位请求链可能漏接） |
| `DL_Device/FB_DL_LevelSwitchVib.st` | `_bTestPulse` | VAR | 死变量 |
| `DL_Device/FB_DL_MixRecipeControl.st` | `_fSpeedCmdInt` | VAR | 死变量（转速指令中间量疑未接线） |
| `DL_MathData/FB_DL_RecipeManager.st` | `_bBadIdxFound` / `_uSum` | VAR | 死变量（`_uSum` 疑校验和累加被绕过） |
| `DL_MathData/FC_DL_CalcDistance3D.st` | `_fSumSq` | VAR | 死变量（新增件，归一化平方和） |
| `DL_Process/FB_DL_RotaryIndexTable.st` | `nIdxVal` | VAR | 死变量（新增件） |

- 裁定：**均非红线/非编译阻断**，不列入 FAIL。其中 `bHolding`、`_fSpeedCmdInt`、`_uSum`、`_bPendAuditClr` 建议人工复核是否漏接线（可能连带功能缺陷）。
- 说明：本项为启发式扫描，未逐条人工通读，仅作下一轮线索。

---

## 六、误报与提示级逐条裁定

### 6.1 R1-INFO ×18（14 个文件）—— 全部裁定「误报—理由：开源溯源注释内的项目名」

命中词均为 **`TcOpen`**（开源 TwinCAT 组件库名，MIT/Apache-2.0），出现位置全部在头部注释块的「开源溯源 (Origin) / 许可证说明」正文里，用于交代 clean-room 参考来源与许可，**代码区零 `Tc*` 厂商对象调用**。

脚本规则 `\bTc[A-Z]\w+`（本意拦 `Tc2_Standard`、`TcXxx` 等厂商私有库）对 `TcOpen` 误命中。且该命中仅落注释区 → 计 R1-INFO，不判 fail，**现有行为正确，无需改代码，也不应为消除提示而删改溯源注释**（溯源是入库硬要求）。

| 文件 | 行 |
|---|---|
| FB_DL_LevelSwitchVib.st | 60 |
| FB_DL_PulseFlowMeter.st | 53 |
| FB_DL_RfidTagHandler.st | 35 |
| FB_DL_SerialScanner.st | 55 |
| FB_DL_SignalTower.st | 31, 37 |
| I_DL_BarcodeScanner.st | 19 |
| I_DL_FlowMeter.st | 17 |
| I_DL_LevelSwitch.st | 16 |
| I_DL_LightCurtain.st | 24 |
| I_DL_RfidReader.st | 39 |
| I_DL_SafetyDoor.st | 21 |
| I_DL_StepperOpenLoop.st | 22, 26 |
| I_DL_TowerLight.st | 25, 27, 31 |
| FB_DL_PickAndPlaceStation.st | 42 |

建议（脚本侧，不改被检代码）：把 `Tc[A-Z]` 规则限定为「必须带下划线数字段」或加白名单 `TcOpen`，可消掉 18 条噪声。

### 6.2 R8-INFO ×4 —— 3 条误报 + 1 条真缺陷探头

| 文件:行 | 报错 | 裁定 |
|---|---|---|
| `FB_DL_AxisHomingSeq.st:340` | CASE 未覆盖 `E_DL_HomingMode` 的 `eZeroPulse`、`eTorqueBlock` | **误报—理由：设计有意的子集分支。** 该 `CASE eMode OF` 位于 `eRetreat`（回退态）内，物理上只有「限位模式」「原点开关模式」会进入回退；Z 相/堵转模式进入即属逻辑非法，`ELSE` 已兜底 `uErrorId := 16#0004_0213` 并转 `eFault`。未覆盖成员不是漏写，是拒绝态。 |
| `FB_DL_AxisHomingSeq.st:390` | 同上 | **误报—理由：同上。** 位于 `eReapproach`（爬行再逼近态），`ELSE` 同样兜底 0004_0213。 |
| `FB_DL_ConveyorZone.st:232` | CASE 未覆盖 `E_DL_ZoneState` 的 `eStopped`/`eRunning`/`eAccumulating` | **误报—理由：守卫式 CASE。** 该 CASE 处于 `IF bJam OR _bFaultLatch THEN` 分支内，职责仅「卡料/故障时把状态同步到 eJamFault」；其余成员在此上下文下必须被强制改判，此处列全反而错误。同文件 L241 主状态机 CASE 已全量覆盖 4 个成员（脚本未报），可反证不是漏写。`ELSE` 亦已锁存故障 0005_0214。 |
| `FB_DL_AxisRelativeMove.st:139` | CASE 标签不在 `E_DL_RelStep` 定义内：`eMoving` | **非误报——真缺陷探头。** 根因是 §5.1 的枚举单冒号笔误 `eMoving : 10`，导致脚本没把它解析成成员。CASE 本身正确（`eIdle`/`eMoving` 二态 + ELSE 兜底）。修 §5.1 第 5 行后本条自动消失。 |

### 6.3 「…」区间记法 / 位宽特例类误报 —— 本轮 0 命中，无裁定对象

- R2 省略号规则为 ASCII `\.{3,}`（含「整行」「块注释内整行」「行尾」三种形态）。中文省略号 `…`（U+2026）、两点 `..`、以及正文中作为缩写用的 `...`（非行尾）均不命中。全库 167 件 **R2 命中 0**，脚本当前未产生此类误报。
- R1 物理地址规则 `%{I|Q|M|IX|QX|MX|MW|MD}<digit>` 在代码区 **0 命中**；注释区提及亦已被 `//` 剥离逻辑排除，未见「位宽写法（如 %MX0.0 / %MW100）」被误判的情况。
- 结论：本轮无需为这两类误报做任何让步；若后续批次出现，按同一口径（注释区提及不计、`…` 不匹配 `...`）逐条留档即可。

---

## 七、处置汇总与后续建议

| # | 事项 | 状态 | 归属 |
|---|---|---|---|
| 1 | PneumaticCylinder `_uCycleCount` 笔误 | ✅ 已修（v1.0.1） | 本轮 |
| 2 | SingleSolenoidCyl `_uCycleCount` 笔误 | ✅ 已修（v1.0.1） | 本轮 |
| 3 | QuickSortLReal `nPivotIdx` 补声明 | ✅ 已修（v1.0.1） | 本轮 |
| 4 | LeakTestStation `_fDeltaP` ×2 笔误 | ⏸ 已登记未修（超出授权文件范围） | 建议 R12 首项 |
| 5 | 3 文件 5 行枚举单冒号 `:` → `:=` | ⏸ 已登记未修 | 建议 R12 批量标点勘误 |
| 6 | 孤儿输出/死变量 9 条 | ⏸ 观察项 | 建议人工复核 4 条可疑漏接线 |
| 7 | R1 规则 `Tc[A-Z]` 误命中 `TcOpen` | 说明性，无需改代码 | 脚本侧可选优化 |
| 8 | PressFitStation 过程态 FAIL | 已自愈（落盘终版 PASS） | 主控注册前复检 |

**红线口径提醒（建议写入下一轮机检说明）**
1. R7 只校验 `:=` 左侧根标识符，**右侧**的未声明标识符不查。本轮补扫「下划线前缀标识符未声明」，全库仅命中 `_fDeltaP`（R7 已覆盖），右侧暂无漏网。
2. R8 为提示级、不判 fail，但 §5.1 表明它可能是**真缺陷的唯一探针**——建议把「枚举成员缺 `=`」升级为硬判，或至少让 R8 提示计入复核清单强制过目。
3. D-01 家族的共同指纹是「**公共输出全文零写入 + 内部名带下划线却无声明**」。建议给机检加一条轻量硬规则：`VAR_OUTPUT` 符号在正文零引用 → 提示级告警，可在编译前抓住同型缺陷（本轮 9 条观察项即由此发现）。

---

## 八、结论

- 被指派 3 件：**全部修复、全部 PASS、硬缺陷 0**，语义判定有据（2 处笔误、1 处漏声明），无掩盖式修复，均有版本号与修订记录。
- 全库存量 152 件：**151 PASS / 1 FAIL**，唯一 FAIL 为 `FB_DL_LeakTestStation.st` 的 `_fDeltaP`（已定位、已给出改法、本轮按授权未动）。
- 另发现并登记 1 类**未在指派清单内、且机检不判 fail 的真编译阻断**（枚举单冒号 5 行）。该批缺陷一旦注册入库，三平台均无法编译，建议优先于其他排期处理。
- 提示级 22 条中，21 条裁定为误报/设计有意（18 R1-INFO + 3 R8-INFO），1 条（`E_DL_RelStep`）实为真缺陷探头。**未为消除任何提示而修改被检代码。**
- 未触碰：`INDEX_REGISTRY.json`、JSONL、`ROADMAP`、本轮新增 16 件（其中 15 件已落盘并 PASS，1 件未落盘）。
