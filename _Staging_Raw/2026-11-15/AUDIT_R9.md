# AUDIT — Round 09（R9）终审报告

> 审查人：道莅工控代码库产品总监（双签中的总监签字，本轮唯一人工语义闸口）
> 日期：2026-11-15 ｜ 规格基准：`_Staging_Raw/2026-11-15/ROUND_PLAN_R9.md`
> 规范依据：`daoli-st-standard` SKILL.md + `references/`（coding-standard / directory-contract / doc-templates）
> 审查范围：R9 十六件（DL_MathData 6 / DL_Base 5 / DL_Motion 1 / DL_Device 2 / DL_Process 2）

---

## 一、终审结论

**结论：PASS with fixes（修复后准入）**

| 指标 | 数值 |
|---|---|
| 送审文件数 | 16（送审行数 4,943） |
| 判定 PASS（零修改） | 6 |
| 判定 FAIL → 已修复 | 10 |
| 缺陷总数 | 13（致命 2 ／ 严重 8 ／ 轻微 3） |
| 其中码位冲突族 | 6 件 15 处（跨组件串台，已全部改判顺延） |
| 修复后最终行数 | **5,051**（+108，均为勘误留痕与修复注释，无功能膨胀） |
| 版本变化 | 10 件 1.0.0 → 1.0.1；6 件维持 1.0.0 |
| 剩余观察项 | 11 条（不阻断入库，留档 v1.1） |

**一句话裁定**：十六件工程口径、单拍语义、状态机拓扑与向量推导整体达标（R19/R24/R25/R26/R27 五条历史范式逐条落地），但**存在 1 处三平台编译必败（缺引脚声明）与 1 处现场静默卡死（减速段无第二出口）**，且**码位复核发现 6 件 15 处与既有组件串台**——编码者与机检脚本的"码表核对"结论全部不可采信，已按「核对结果优先」逐条改判。

---

## 二、机检结果（终审后复跑）

| 检查项 | 口径 | 结果 |
|---|---|---|
| 禁记号（全局变量表/外部变量/绝对地址） | 全文命中 = 0 | 16/16 通过（0 命中） |
| 孤立分号（R26） | `;` 独占行或行尾双分号 = 0 | 16/16 通过 |
| 终结符成对 | `END_FUNCTION_BLOCK` / `END_FUNCTION` / `END_INTERFACE` / `END_TYPE` | 16/16 通过 |
| VAR / END_VAR 平衡 | 逐块配对 | 16/16 通过 |
| 未声明标识符（左侧赋值目标全量比对） | 应 = 0 | 修复前 **1 处命中**（`FC_DL_BinarySearchLReal.uErrorId`）→ 修复后 0 |
| 类型重复声明（枚举/结构体跨文件） | 应 = 0 | 12 个 DUT 全库唯一，0 重复 |
| 码位跨文件重叠 | 应 = 0（语义唯一） | 修复前 **15 处重叠（6 件）** → 修复后 0 |

> 说明：机检脚本对"码位是否空闲"只做字面比对，不判语义；本轮 6 件冲突全部由人工逐码回溯到 `VERSION.md` 台账与总手册码表才发现。

---

## 三、逐文件裁定

| # | 文件 | 版本 | 行数 | 判定 | 结论摘要 |
|---|---|---|---|---|---|
| 1 | `DL_MathData/FB_DL_FifoBuffer.st` | 1.0.0→**1.0.1** | 363 | FAIL→修复 | 指针一致性断言 / 丢新策略 / 先弹后压次序均正确；码位 5 处与计数族、日期族串台，已顺延 |
| 2 | `DL_MathData/FB_DL_ArraySearchFirst.st` | 1.0.0→**1.0.1** | 357 | FAIL→修复 | 触发制扫描、结果族每拍先清（R25/B3）正确；码位 2 处越段且与 PID 族冲突，已顺延 |
| 3 | `DL_MathData/FC_DL_BinarySearchLReal.st` | 1.0.0→**1.0.1** | 211 | FAIL→修复 | **致命**：`uErrorId` 未声明（函数体 5 处读写）→ 三平台编译必败；码位 2 处冲突。V1~V5 向量逐组验算全部符合 |
| 4 | `DL_MathData/FC_DL_TempUnitConvert.st` | 1.0.0→**1.0.1** | 210 | FAIL→修复 | 换算基准链、同标直通、绝对零度信息级诊断全部正确（V1~V5 与 P1~P4 复核通过）；码位 3 处与运动轴族串台，已顺延 |
| 5 | `DL_MathData/FC_DL_BcdToWord.st` | 1.0.0→**1.0.1** | 205 | FAIL→修复 | 逐半字节校验前置、错误路径零部分结果正确（V1~V5 复核通过）；`UINT(uDigit)` 为全库唯一强制转换写法，改标准转换函数 |
| 6 | `DL_MathData/FC_DL_WordToBcd.st` | 1.0.0 | 202 | **PASS** | 除基取余 + 饱和不回绕 + 除基守卫齐备（V1~V5 复核通过）；码位 0106/0107 全库唯一空闲 |
| 7 | `DL_Base/FB_DL_ToleranceWindow.st` | 1.0.0→**1.0.1** | 358 | FAIL→修复 | 迟滞三态跃迁（T1~T10 逐拍复核通过）、`bDeviation` 单拍三律、故障拍清基准全部正确；码位 2 处越段（用了 `0003` 设备段）且与设备族共用码冲突 |
| 8 | `DL_Base/FC_DL_LimitClassify.st` | 1.0.0→**1.0.1** | 210 | FAIL→修复 | 四阈值五档 + 闭区间归属 + 序非法拒绝（V1~V6 复核通过）；码位 1 处越段冲突；退化组态说明文档错（正常档为空集，非"单点"） |
| 9 | `DL_Base/FC_DL_WordBitPack.st` | 1.0.0→**1.0.1** | 231 | FAIL→修复 | **参数判界漏洞**：只判 `nOffset+nWidth>16`，USINT 域 15+250 回绕成 9 可绕过校验；已补两项单项判界。V5 向量裁定见第六节 |
| 10 | `DL_Base/FB_DL_MonthWindowCheck.st` | 1.0.0 | 370 | **PASS** | 月长/闰年独立实现、窗口不跨月截断、钳位先于取负（B2）、`bWindowOpen` R_TRIG 置于主体末尾且无条件刷新（W1~W9 复核通过）；码位 0109/0203 唯一 |
| 11 | `DL_Base/FB_DL_PresetCounterSat.st` | 1.0.0→**1.0.1** | 358 | FAIL→修复(文档) | 优先级链 / 先判界后加减 / 单点出口 / `bThreshold` 三律全部正确（C1~C7 代码路径复核通过）；C6 推演文字与实现不符，已勘误 |
| 12 | `DL_Motion/FB_DL_SuperimposedMove.st` | 1.0.0 | 358 | **PASS** | 内联斜坡 + 双向幅值限幅 + 零驻留窗口 + 使能冻结不归零全部正确；eIdle/eActive/eFault 三态均有出口；`TON` 无条件刷新且无"调用前自清"缺陷 |
| 13 | `DL_Device/I_DL_StepperOpenLoop.st` | 1.0.0 | 130 | **PASS** | 属性 3 / 方法 6（恰在红线 ≤6 内）；7 条跃迁契约写死；`ST_DL_StepperCfg` 随接口发布，`E_DL_StepperState` 归实现块，无跨文件重复 |
| 14 | `DL_Device/FB_DL_PulseDirStepper.st` | 1.0.0→**1.0.1** | 564 | FAIL→修复 | **致命**：`eDecel` 无"频率归零"出口 → 残差为小数时永久卡死（无故障码、`bReady` 恒 FALSE）；接口 6 方法 + 3 属性签名逐项对齐 ✓；码位 02E0~02E4 顺延正确（避开 VacuumEjector 0230~0232） |
| 15 | `DL_Process/FB_DL_ModbusPollMaster.st` | 1.0.0 | 530 | **PASS** | WHILE 回绕找站带守卫（上限 16）、索引上下界保护、双定时器"先算后喂 + 调用后自清"正确；eIdle/eNextStn/eRequest/eWaitResp/eSttUpdate/eFault 六态全部可达可出；码位 019x/029x 唯一 |
| 16 | `DL_Process/FB_DL_AndonCallSystem.st` | 1.0.0 | 394 | **PASS** | 显式优先级仲裁（不依赖枚举数值序）、抢占重锁重建升级计时、增量式滚动均值防溢出、班次清零不清激活呼叫；四态出口齐备；码位 01Ax/02Ax 唯一 |

---

## 四、缺陷清单（含原行号）

> 行号为**修复前 v1.0.0** 行号，便于回溯；修复位置见"修法"。

### 4.1 致命（2）

**D-01 ｜ `DL_MathData/FC_DL_BinarySearchLReal.st` ｜ 接口-实现契约 / 声明缺失 ｜ 致命**
- 位置：`VAR_OUTPUT`（原 114~116 行，仅声明 `bFound`）；函数体原 138 / 150 / 178 / 198 行共 5 处读写 `uErrorId`。
- 判据：规格 §3 明列 `VAR_OUTPUT uErrorId : UDINT`；实现漏声明 → CODESYS / TwinCAT / InoProShop 三平台编译期均报未定义标识符。
- 修法：`VAR_OUTPUT` 补 `uErrorId : UDINT;`（含中英双语同行注释与码值说明）。
- 关联：这是七轮机检未捕获的类型——机检只查禁记号/分号/终结符，未做"赋值目标声明性"比对。**建议把该检查项固化进 machine_check 脚本（见第八节 P0 建议）**。

**D-02 ｜ `DL_Device/FB_DL_PulseDirStepper.st` ｜ 状态机终态可达性 ｜ 致命**
- 位置：`E_DL_StepperState.eDecel` 分支（原 361~370 行）。
- 现象：出口仅 `IF _fStepsRemain <= 1E-6`。段 8 的脉冲发生要求 `_fFreqNow > 0.1 Hz`；减速段每拍频率步进 `_fFreqStepHz = fAccel × 当量 × 周期`（默认组态 500×400×0.01 = 2000 Hz/拍）远大于峰值频率（10 ms 任务上限 50 Hz），频率一拍归零而剩余步数仍为小数（如 4000.003 → 0.003）→ 相位不再累加 → **永久停在 eDecel**：`bPulse` 恒 FALSE、`bError` FALSE、`bReady` 恒 FALSE、无任何故障码，现场表现为"轴不动、不报警、不能接新指令"。
- 修法：出口改双条件 `IF (_fStepsRemain <= EPS) OR (_fFreqNow <= DL_FREQ_EPS)`；频率归零即数学上不可能再发脉冲，一律按到位收尾，并新增信息级 `16#0003_0137` 记录"残差不足一脉冲按到位处理"（码位全库唯一）。

### 4.2 严重（8）

**D-03 ｜ `FB_DL_FifoBuffer` ｜ 码位冲突（5 处）**
`0001_0101`（容量钳位）／`0001_0102`（满队拒绝）／`0001_0103`（空队弹出拒绝）／`0001_0104`（空队窥视拒绝）／`0001_0201`（一致性破坏）分别被 `FB_DL_EventCounter`（0101 双脉冲抵消、0102 装载覆盖）、`FB_DL_ModuloCounter`（0103 跳步越界、0104 双向抵消）、`FC_DL_DayOfWeekCalc`（0201 日期参数越界）占用，且 `DL_Base/VERSION.md` 第 62~67 行与总手册码表已明文登记。
修法：顺延 `0001_010A / 010B / 010C / 010D / 0204`，文件内头注释、单拍推演、验收表 E4/E5/E8/E9、拒绝路径矩阵同步刷新。

**D-04 ｜ `FB_DL_ArraySearchFirst` ｜ 码位冲突（2 处）+ 段位越界**
`0002_0101`（原 298 行）／`0002_0201`（原 345 行）落在 `16#0002_01xx`（DL_Algo PID 族段，总手册第 123 行明示），与 `FB_DL_PidController`（0002_0101 输出饱和）、`FB_DL_CascadePid`（0002_0201 副设定钳位）撞码。
修法：改归 `0001_010E / 0001_0205`。

**D-05 ｜ `FC_DL_BinarySearchLReal` ｜ 码位冲突（2 处）** — 同 D-04，改 `0001_010F / 0001_0206`。

**D-06 ｜ `FC_DL_TempUnitConvert` ｜ 码位冲突（3 处）+ 段位越界**
`0004_0101`（低于绝对零度）／`0004_0201`（源温标非法）／`0004_0202`（目标温标非法）落在 `16#0004_xxxx`（DL_Motion 段），与 `FB_DL_SingleAxis`（0004_0101 指令丢弃、0004_0201 非法态、0004_0202 软限位越界）、`FB_DL_AxisRelativeMove` / `FB_DL_AxisVelocityMove`（0004_0201）撞码。
修法：改归 `0001_0110 / 0001_0207 / 0001_0208`（含示例代码注释、拒绝路径 R1~R3 同步）。

**D-07 ｜ `FB_DL_ToleranceWindow` ｜ 码位冲突（2 处）+ 段位越界**
`0003_0101`（回差越界钳位，原 268 行）与 `0003_0201`（公差非正，原 255 行）属 `16#0003_xxxx` 设备段：0101 为设备族"参数钳位"共用码（`FB_DL_HeatCoolZone`），0201 为设备族"非法状态"共用码（`FB_DL_DolMotor / PneumaticCylinder / StarDeltaMotor`）。本体在 DL_Base，段位与语义双错。
修法：改归 `0001_0112`（信息级）/ `0001_0213`（故障级）。

**D-08 ｜ `FC_DL_LimitClassify` ｜ 码位冲突（1 处）**
`0003_0201`（阈值序非法，原 174 行）与设备族"非法状态"共用码同码异义。
修法：改归 `0001_0214`。

**D-09 ｜ `FC_DL_WordBitPack` ｜ 数值边界（USINT 回绕绕过判界）**
原 163 行仅 `IF (nWidth = 0) OR (nOffset + nWidth > DL_WORD_BITS)`。`nOffset` / `nWidth` 形参为 USINT（域 0~255）：`nOffset=15, nWidth=250` → 求和 265 在 USINT 域回绕为 9 → 判界漏过 → 掩码走 `SHL(1, 250)`，落入平台未定义行为（部分平台结果 0、部分回绕），且返回值看似合法。
修法：判据扩为四项（宽度 0 / 宽度 > 16 / 偏移 >= 16 / 求和 > 16），单项判界置于求和判界之前；新增验收 V7 固化该路径。

### 4.3 轻微（3）

**D-10 ｜ `ROUND_PLAN_R9.md` §9 V5 向量错** — 详见第六节，计划表 `16#1264` → `16#12A4`，已勘误并留痕。

**D-11 ｜ `FC_DL_LimitClassify` ｜ 文档语义错**（原 110 行）"fLowWarn = fUpWarn = 50 → 正常档收缩为一点（仅 v = 50 判正常）"与闭区间归属次序矛盾：v = 50 会先被 `<= fLowWarn` 判 `eLowWarn`，正常档实为**空集**。已改写为准确表述（代码正确、文档错）。

**D-12 ｜ `FB_DL_PresetCounterSat` ｜ 文档语义错**（原 145~146 行）C6 称"bReset 沿 → 解除，可重新计数"：段 2 复位沿解除锁存后，同一拍段 3 复检 `nPreset < nLowLimit` 仍成立即**重新锁存**。已补前置条件（须先修正参数再复位）。

**D-13 ｜ `FC_DL_BcdToWord` ｜ 类型转换异构**（原 188 行）`UINT(uDigit)` 是全库唯一强制转换写法（其余 13 类转换一律 `X_TO_Y()`），公约三要求显式标准转换。已改 `USINT_TO_UINT(uDigit)`，数值不变。

---

## 五、码位复核表（16 件全量）

> 复核口径：逐码 `grep 16#XXXX_YYYY` 全库 `.st` + 回溯 `DL_*/VERSION.md` 台账 + `LIBRARY_MANUAL.md` 全局码表。**编码者自报的"未占用"结论全部独立推翻并重建。**

| 组件 | 段位归属 | 交付码位（终审后） | 级别 | 复核结论 |
|---|---|---|---|---|
| FB_DL_FifoBuffer | 0001（L0） | 010A / 010B / 010C / 010D / 0204 | 信息×4 + 故障×1 | **改判顺延**（原 0101~0104 / 0201 撞码） |
| FB_DL_ArraySearchFirst | 0001（L0） | 010E / 0205 | 信息 + 故障 | **改判**（原 0002_0101/0201 越段撞 PID 族） |
| FC_DL_BinarySearchLReal | 0001（L0） | 010F / 0206 | 信息 + 故障 | **改判**（同上） |
| FC_DL_TempUnitConvert | 0001（L0） | 0110 / 0207 / 0208 | 信息 + 故障×2 | **改判**（原 0004_0101/0201/0202 撞运动轴族） |
| FC_DL_BcdToWord | 0001（L0） | 0105 | 故障 | 原报 0105 **核实空闲**，保留 |
| FC_DL_WordToBcd | 0001（L0） | 0106 / 0107 | 故障×2 | 原报 0106/0107 **核实空闲**，保留 |
| FC_DL_WordBitPack | 0001（L0） | 0108 | 故障 | 原报 0108 **核实空闲**，保留 |
| FB_DL_MonthWindowCheck | 0001（L0） | 0109 / 0203 | 信息×2 | 原报 0109 + 0203 **核实空闲**，保留（原报文"0101~0104 已被计数族"不全面，实际 0105~0108 亦已占用，不影响结论） |
| FB_DL_PresetCounterSat | 0001（L0） | 0212 | 故障 | 原报 0212 **核实空闲**，保留 |
| FB_DL_ToleranceWindow | 0001（L0） | 0112 / 0213 | 信息 + 故障 | **改判**（原 0003_0101/0201 越段撞设备族） |
| FC_DL_LimitClassify | 0001（L0） | 0214 | 故障 | **改判**（原 0003_0201 越段撞设备族"非法状态"） |
| FB_DL_SuperimposedMove | 0004（L1） | 01A0~01A3 / 02B0~02B2 | 信息×4 + 故障×3 | 建议码位**核实空闲**，保留 |
| I_DL_StepperOpenLoop | — | 无 | — | 接口无码，合规 |
| FB_DL_PulseDirStepper | 0003（L1） | 0130~0137 / 02E0~02E4 | 信息×8 + 故障×5 | 泳道 C 自行顺延**复核成立**（0230~0232 确被 VacuumEjector 占用、0240~0246 被 StarDeltaMotor 占用）；新增 0137 复核空闲 |
| FB_DL_ModbusPollMaster | 0005（L2） | 0190~0193 / 0290~0292 | 信息×4 + 故障×3 | **核实空闲**，保留（0293 按偏离留档未使用，接受） |
| FB_DL_AndonCallSystem | 0005（L2） | 01A0 / 01A1 / 02A0 / 02A1 | 信息×2 + 故障×2 | **核实空闲**，保留 |

**改判明细（逐码可回溯）**：FB_DL_FifoBuffer 5 处（0101/0102/0103/0104/0201）+ FB_DL_ArraySearchFirst 2 处（0002_0101/0002_0201）+ FC_DL_BinarySearchLReal 2 处（0002_0101/0002_0201）+ FC_DL_TempUnitConvert 3 处（0004_0101/0201/0202）+ FB_DL_ToleranceWindow 2 处（0003_0101/0201）+ FC_DL_LimitClassify 1 处（0003_0201）= **6 件 15 处**。

**终审后全库码位跨文件重叠 = 0**（断言脚本已复跑；含 10 件 v1.0.1 与 6 件维持 1.0.0 的全部码位）。

---

## 六、FC_DL_WordBitPack V5 专项裁定

### 6.1 输入
`uTarget = 16#1234`，`uField = 16#AA`，`nOffset = 4`，`nWidth = 5`；计划表期望返回 `16#1264`，期望 `uExtracted = 16#0003`；编码者验算结论 `16#12A4`。

### 6.2 逐位独立验算（总监自算，不采信任一方结论）

```
uTarget           = 0001 0010 0011 0100 = 16#1234
uField            = 1010 1010           = 16#AA
nOffset = 4，nWidth = 5

① 段掩码   uMask      = ((1<<5)-1) << 4 = 0000 0001 1111 0000 = 16#01F0
② 反相     uMaskInv   = NOT uMask       = 1111 1110 0000 1111 = 16#FE0F
③ 解包     uExtracted = (16#1234 AND 16#01F0) >> 4
                      = (0001 0010 0011 0100 AND 0000 0001 1111 0000) >> 4
                      = 0000 0000 0011 0000 >> 4 = 0000 0000 0000 0011 = 16#0003  ✓ 与计划一致
④ 清段     uBase      = 16#1234 AND 16#FE0F = 0001 0010 0000 0100 = 16#1204
⑤ 字段掩码 uFieldMask = SHR(16#01F0, 4)     = 0000 0000 0001 1111 = 16#001F
⑥ 字段截断 uFieldTrim = 16#AA AND 16#1F     = 1010 1010 AND 0001 1111 = 0000 1010 = 16#0A
⑦ 对齐     uFieldAlgn = 16#0A << 4          = 0000 0000 1010 0000 = 16#00A0
⑧ 合成     返回       = 16#1204 OR 16#00A0  = 0001 0010 1010 0100 = 16#12A4
```

### 6.3 裁定

**判定：代码对、计划向量错。**
- `16#1264` 的位 4~8 = `0 0110`（字段值 6）；本组入参 `16#AA`（低 5 位 = `0 1010` = 10）、宽度 5、偏移 4，**不存在任何推导路径得到 6**（既非截高位、也非移位版本，属纯笔误）。
- 计划表其余 5 组（V1~V4、V6）逐组复核均正确，唯 V5 一处错值，符合 R8 已定性的"公式对、向量错"范式。
- 处置：
  1. `ROUND_PLAN_R9.md` §9 V5 表 `16#1264` → `16#12A4`，并在表下加**【勘误 · 终审裁定】**引用块（含完整验算链与"计划表笔误"定性留痕，不删原文口径）；
  2. `FC_DL_WordBitPack.st` 头注释 V5 注记升级为终审裁定版（保留编码者原始验算 + 总监复核链 + 处置结论）；
  3. 组件实现**零改动**（除 D-09 判界缺陷修复与 v1.0.1 版本号）。

---

## 七、验收向量独立验算记录（31 组 + 补 1 组）

> 全部由总监按实现逐拍/逐位代回，未采信编码者结论。

### 7.1 FC_DL_BinarySearchLReal（afSorted = {1.5, 2.5, 3.5, 4.5, 5.5}, nCount = 5）

| 向量 | 目标 | 迭代轨迹（nLo/nHi/nMid） | 实得 | 期望 | 判定 |
|---|---|---|---|---|---|
| V1 | 3.5 | 0/4/2 → 命中 | 2 / TRUE | 2 / TRUE | ✓ |
| V2 | 1.5 | 0/4/2(3.5>1.5)→nHi=1；0/1/0 → 命中 | 0 / TRUE | 0 / TRUE | ✓ |
| V3 | 5.5 | 0/4/2→nLo=3；3/4/3(4.5<5.5)→nLo=4；4/4/4 命中 | 4 / TRUE | 4 / TRUE | ✓ |
| V4 | 3.6 | 2(3.5<3.6)→nLo=3；3(4.5>3.6)→nHi=2；3>2 收敛 | -1 / FALSE | -1 / FALSE | ✓ |
| V5 | 0.5 | 2(3.5>0.5)→nHi=1；0(1.5>0.5)→nHi=-1 收敛 | -1 / FALSE | -1 / FALSE | ✓ |

### 7.2 FC_DL_LimitClassify（10 / 20 / 80 / 90）

| 向量 | fVal | 命中分支 | 实得 | 期望 | 判定 |
|---|---|---|---|---|---|
| V1 | 5.0 | `<= fLowLimit` | eLowTripped / 0 | 同 | ✓ |
| V2 | 15.0 | `<= fLowWarn` | eLowWarn / 0 | 同 | ✓ |
| V3 | 50.0 | 落 ELSE | eNormal / 0 | 同 | ✓ |
| V4 | 85.0 | `>= fUpWarn` | eUpWarn / 0 | 同 | ✓ |
| V5 | 95.0 | `>= fUpLimit` | eUpTripped / 0 | 同 | ✓ |
| V6 | 90/80/20/10 | `fLowLimit > fLowWarn+eps` 首判 | eInvalid / 非 0 | 同 | ✓（拒绝路径已验） |

### 7.3 FC_DL_TempUnitConvert

| 向量 | 输入 | 归一摄氏 | 输出 | 期望 | 判定 |
|---|---|---|---|---|---|
| V1 | 100 C→K | 100 | 100−(−273.15)=373.15 | 373.15 | ✓ |
| V2 | 100 C→F | 100 | 100×9/5+32=212 | 212.0 | ✓ |
| V3 | 32 F→C | (32−32)×5/9=0 | 0 | 0.0 | ✓ |
| V4 | 300 K→C | 300−273.15=26.85 | 26.85 | 26.85 | ✓ |
| V5 | −40 C→F | −40 | −40×1.8+32=−40 | −40.0 | ✓ |
| 补 P2 | 0 K→K | −273.15（不低于绝对零度，容差含等号） | 0.0，无诊断码 | 不置码 | ✓ |

### 7.4 FC_DL_BcdToWord

| 向量 | uBcd | 半字节轨迹（个/十/百/千） | 实得 | 期望 | 判定 |
|---|---|---|---|---|---|
| V1 | 16#0123 | 3/2/1/0 → 3+20+100 | 123 / 0 | 123 / 0 | ✓ |
| V2 | 16#9999 | 9/9/9/9 → 9999 | 9999 / 0 | 同 | ✓ |
| V3 | 16#0000 | 0/0/0/0 | 0 / 0 | 同 | ✓ |
| V4 | 16#001A | 十位 = A = 10 > 9 → 立即返回 | 0 / 0105 | 0 / 非 0 | ✓（拒绝路径已验） |
| V5 | 16#0999 | 9/9/9/0 → 9+90+900 | 999 / 0 | 同 | ✓ |

### 7.5 FC_DL_WordToBcd

| 向量 | uVal | 除基链（余数） | 实得 | 期望 | 判定 |
|---|---|---|---|---|---|
| V1 | 123 | 3,2,1,0 → 16#0123 | 16#0123 / 0 | 同 | ✓ |
| V2 | 9999 | 9,9,9,9 | 16#9999 / 0 | 同 | ✓ |
| V3 | 10000 | > 9999 → 饱和 | 16#9999 / 0106 | 同 | ✓（拒绝路径已验） |
| V4 | 0 | 全 0 | 16#0000 / 0 | 同 | ✓ |
| V5 | 4096 | 6,9,0,4 → 0x4000\|0x0090\|6 | 16#4096 / 0 | 同 | ✓ |

### 7.6 FC_DL_WordBitPack

| 向量 | 掩码 | 清段后 | 对齐段 | 实得返回 / 实得 uExtracted | 期望 | 判定 |
|---|---|---|---|---|---|---|
| V1 | 16#00F0 | 16#0000 | 16#0030 | 16#0030 / 16#0000 | 同 | ✓ |
| V2 | 16#00FF | 16#0000 | 16#0000 | 16#0000 / 16#00FF | 同 | ✓ |
| V3 | 16#F000 | 16#0000 | 16#F000 | 16#F000 / 16#0000 | 同 | ✓ |
| V4 | 16#00F0 | 16#1204 | 16#00A0 | 16#12A4 / 16#0003 | 同 | ✓ |
| V5 | 16#01F0 | 16#1204 | 16#00A0 | **16#12A4** / 16#0003 | 计划原载 16#1264 | **计划错，已勘误**（第六节） |
| V6 | 15+2=17>16 | — | — | 16#1234 / 0，码 0108 | 同 | ✓（拒绝路径已验） |
| 补 V7 | w=250,o=15 | 原判界回绕漏判 | — | 16#1234 / 0，码 0108 | 新增 | ✓（D-09 修复后） |

### 7.7 FB 类验收推演抽样复核（逐拍）
- **ToleranceWindow T1~T10**：使能门 → 宽阈迁出（0.56 > 0.55）→ 窄阈保持（0.52 > 0.5 保持 eHighOut）→ 窄阈回窗（0.49）→ 负向对称（−0.60 < −0.55）→ 参数非法锁 eUnKnown → 回差钳 0.25，**10 拍全部符合**。
- **MonthWindowCheck W1~W9**：12 月倒数第 3 = 29 日、窗口 [29,33]→截 31、偏移 0/2/−1、闰年 2028-02 目标 30 钳 29、年度非生效月零码、13 月/目标 0 置 0203、未使能全复位，**9 组全部符合**。
- **PresetCounterSat C1~C7**：递增链 1/2/3 单拍阈值、第 4 沿饱和吞脉冲、双沿抵消、装载优先且给单拍、复位无脉冲、参数锁存、退化域装载到达，**代码路径全部符合**（C6 表述已勘误）。
- **FifoBuffer E1~E9**：空态、压入 3、弹出 FIFO 次序、满队丢新、空队下溢、同拍弹压换尾、清空优先、容量钳位、缩容自愈，**9 组全部符合**。
- **PulseDirStepper V1~V6**：频率钳位 50 Hz、一高一低各一拍、限位同向停发并锁 02E1、复位后仍拒同向（0134）、堵转时限、Stop 压减速段、去使能无半脉冲，**6 组符合**（V5 停车路径经 D-02 修复后出口可达）。

---

## 八、必查清单逐条结论

| # | 检查项 | 结论 |
|---|---|---|
| 1 | R19 首扫唯一合法范式 | 通过。带跟踪源的件一律 `IF bTrack OR (NOT bInit)`；本批 5 件无跟踪源（Fifo/ArraySearch 无跨拍状态、Superimposed/PulseDir/Modbus/Andon 为退化式 `IF NOT _bInit THEN …`），与库内 `FB_DL_Differentiator` 既有先例一致，**未出现 `IF bInit OR bTrack` 双向皆错写法**；`bInit` 初值均 FALSE、同步后置 TRUE |
| 2 | R24 定时器自清位位置 | 通过。5 处定时/边沿"断输入一拍"自清全部在实例调用**之后**：PulseDir `_fbMoveTimer→_bMoveBreak`、Modbus `_fbPollTick→_bGapBreak` / `_fbRespWatch→_bRespBreak`、Andon `_fbAgeTimer→_bAgeBreak` / `_fbEscTimer→_bEscBreak`；无"调用前自清"缺陷 |
| 3 | R25 单拍标志三律 | 通过。`bDone / bOverflow / bUnderflow / bThreshold / bDeviation / bWindowOpen / bPulse` 逐位核对：置位点唯一、每拍预清位置正确（主体首段）、边沿基准单一来源；PresetCounter 另具备"故障拍强制清基准" |
| 4 | R26 孤立分号 | 通过（16/16 = 0 命中） |
| 5 | R27 输出保持语义 | 通过。`ToleranceWindow.eJudge/bOk/bLowOut/bHighOut`、`PresetCounter.bDone/bSatHigh/bSatLow`、`Andon.bAcked/bEscalate` 均为派生保持型，未降级为脉冲 |
| 6 | 状态机终态可达性 | **修复后通过**。PulseDir 的 eDecel 原缺"频率归零"出口（D-02 致命）已补；Superimposed（eIdle↔eActive↔eFault）、Modbus（六态）、Andon（四态，eFault 经班次清零出）全部有出口，`ELSE` 兜底齐备 |
| 7 | 数值边界 | **修复后通过**。除零守卫（当量/周期/位置换算/均值笔数）、DINT 极值 +1/−1 先判界后运算（PresetCounter/Stepper）、浮点容差（ABS + EPS）、数组索引上下界（Modbus `_uStnIdx`、Fifo 取模先判界、二分 `nMid` 兜底）、WHILE 硬上限（Modbus 16、二分 64）齐备；WordBitPack 的 USINT 回绕漏洞（D-09）已补 |
| 8 | 接口-实现契约一致性 | **修复后通过**。`I_DL_StepperOpenLoop` 3 属性（bReady/fPosition/uAlarmWord）+ 6 方法（Init/Enable/MoveRelative/Stop/Reset/GetErrorId）与 `FB_DL_PulseDirStepper` 逐项名称/类型/方向对齐，无增删参数；`ST_DL_StepperCfg` 仅接口文件、`E_DL_StepperState` 仅实现文件，零重复声明。唯一契约断裂在 BinarySearch（D-01 缺 `uErrorId`）已补 |
| 9 | 码位冲突 | **修复后通过**。16 件全覆盖复核，**6 件 15 处冲突全部改判顺延**，终审后全库跨文件重叠 = 0（见第五节） |
| 10 | 验收向量独立验算 | **31 组 + 补 1 组全部代回**（第七节）；发现 1 处计划向量笔误（WordBitPack V5），已按 R8 口径勘误留痕（第六节） |

---

## 九、观察项（不阻断入库，留档 v1.1）

| # | 文件 | 观察内容 | 建议 |
|---|---|---|---|
| O-01 | 4 件（Fifo / ArraySearch / BinarySearch / Modbus） | `VAR_IN_OUT` 数组维度引用 `VAR CONSTANT`（`DL_FIFO_MAX` 等），而常量块声明在其后。CODESYS/TwinCAT 双遍解析可编译，但可读性与跨平台稳健性欠佳 | v1.1 把 `VAR CONSTANT` 移至声明区最前 |
| O-02 | `FB_DL_ArraySearchFirst` | 段 3~5 的 IF 体未做层级缩进（直线结构可读性差）；守护兜底分支 `(_uGuard >= DL_SRH_MAX) AND (nCountEff > DL_SRH_MAX)` 恒假（`nCountEff` 已钳位），属死代码 | v1.1 统一缩进并删除/改写死代码分支 |
| O-03 | `FB_DL_ModbusPollMaster` | `bEnable` 在事务中途撤销时，当前事务仍会续跑一拍（`eWaitResp → eRequest` 重试不受 `bEnable` 约束），事务结束后才回 `eIdle`；与 V6"暂停并保持现场"表述略有差异，但不产生死锁 | v1.1 在 `eRequest / eWaitResp` 加 `NOT bEnable` 闸门（回 eIdle 且不记账） |
| O-04 | `FB_DL_ModbusPollMaster` | 异步传输层需覆写 `DoTransaction`（`_stTxn` 为私有成员，外部不可回填）；文档已声明，但集成者易只覆写 SendFrame/RecvFrame 而拿不到异步回填口 | v1.1 在 `MANUAL_DL_Process.md` 明示"异步必须覆写 DoTransaction"，或将 `_stTxn` 提升为 `VAR_IN_OUT` 事务句柄 |
| O-05 | `FB_DL_AndonCallSystem` | 抢占拍 `bEscalate` 可能多保持一拍（`_fbEscTimer.Q` 在断输入拍尚未复位，`_bEscBreak` 下一拍才生效） | v1.1 在抢占分支显式清 `bEscalate` 或引入本地 `bEscHold` |
| O-06 | `FB_DL_PulseDirStepper` | `bAlarmIn` 未消失时 `Reset()` 返回 TRUE 但未解除锁存（契约 6 允许"受理 ≠ 解除"，但调用方易误判） | v1.1 改为返回 FALSE 或保持 `uErrorId` 并置 0133 |
| O-07 | `FB_DL_SuperimposedMove` | 故障拍与 `bEnable` 下降沿落在同一拍时（`eActive` 分支先迁 eFault，下降沿已过期），需二次拨动使能才解除；窗口极窄但可复现 | v1.1 在段 4 故障置位拍记 `_bRebuildArmed`，或把 eFault 出口改为"下降沿或参数恢复" |
| O-08 | `FB_DL_FifoBuffer` | 一致性破坏自愈会**静默丢弃全部在队元素**（B6 已写死为契约行为），上位台账无法感知重建时刻 | v1.1 增 `bRebuilt` 单拍事件（与 0204 同拍），便于台账对账 |
| O-09 | `FB_DL_ToleranceWindow` | `eLowOut/eHighOut` 跨侧跳变（如从 −0.6 直跳 +0.6）需经 `eOk` 中转一拍才判对面越差，存在一拍分类滞后（迟滞语义推论，非缺陷） | v1.1 在手册"典型时序"补该跳变说明，避免现场误判 |
| O-10 | `FB_DL_PresetCounterSat` | 段 2 复位沿先于段 3 参数复检，参数未修正时当拍重锁（v1.0.1 已勘误文档）；另 `bLoad` 装载语义为"写入 nPreset 现值"而非"写入独立预置值"，与部分品牌"预置寄存器"直觉不同 | v1.1 手册增"装载 = 装上限值"显式说明，或增 `nLoadValue` 引脚 |
| O-11 | `I_DL_StepperOpenLoop` | `METHOD Stop/Reset/GetErrorId` 带空 `VAR_INPUT … END_VAR` 块，`PROPERTY` 无 `END_PROPERTY` 终结符——与 `I_DL_MotionAxis` / `FB_DL_SingleAxis` 既有先例完全一致，属库内导出惯例 | v1.1（可选）统一清理空 VAR 块；本轮**不改**以免破坏既有导出格式一致性 |

---

## 十、风险提示与流程建议（P0）

1. **P0 · 编译验证仍未启动（第八次提醒）**：本轮 D-01 是"机检七轮全过、实际三平台全编译失败"的活证据——说明现有 machine_check 的能力上限已到顶（只能查记号/分号/括号，查不了声明性与语义）。**建议在下一轮开工前落实任一可用编译环境（CODESYS 脚本模式 / TwinCAT 自动化接口 / InoProShop 命令行），否则每轮都在用人工兜"编译必败"的底。**
2. **P0 · 码表核对必须由脚本兜底**：本轮 6 件 15 处冲突中，有 4 处的编码者注释明确写了"经码表核对未占用"——**自证失效**。建议在 machine_check 增加"码位唯一性断言"（对每件 `.st` 抽取 `16#xxxx_yyyy`，与全库并集求差，非空即 FAIL 并打印撞码文件）。
3. **P1 · 增加"赋值目标声明性"静态检查**：正则抽取全部 `^\s*(\w+)\s*:=` 左侧标识符，与声明区并集比对，可直接拦截 D-01 类缺陷（零成本、零误报面）。
4. **P1 · 计划表向量应由第二人独立复算后才允许下发**：本轮 V5 笔误说明"计划拍脑袋、编码者照抄、机检不比数值"的链路缺口。

---

## 十一、产出清单

| 类型 | 路径 | 版本变化 |
|---|---|---|
| 修复 | `DL_MathData/FB_DL_FifoBuffer.st` | 1.0.0 → 1.0.1 |
| 修复 | `DL_MathData/FB_DL_ArraySearchFirst.st` | 1.0.0 → 1.0.1 |
| 修复 | `DL_MathData/FC_DL_BinarySearchLReal.st` | 1.0.0 → 1.0.1 |
| 修复 | `DL_MathData/FC_DL_TempUnitConvert.st` | 1.0.0 → 1.0.1 |
| 修复 | `DL_MathData/FC_DL_BcdToWord.st` | 1.0.0 → 1.0.1 |
| 修复 | `DL_Base/FB_DL_ToleranceWindow.st` | 1.0.0 → 1.0.1 |
| 修复 | `DL_Base/FC_DL_LimitClassify.st` | 1.0.0 → 1.0.1 |
| 修复 | `DL_Base/FC_DL_WordBitPack.st` | 1.0.0 → 1.0.1 |
| 修复 | `DL_Base/FB_DL_PresetCounterSat.st` | 1.0.0 → 1.0.1 |
| 修复 | `DL_Device/FB_DL_PulseDirStepper.st` | 1.0.0 → 1.0.1 |
| 未改动 | `DL_MathData/FC_DL_WordToBcd.st` / `DL_Base/FB_DL_MonthWindowCheck.st` / `DL_Motion/FB_DL_SuperimposedMove.st` / `DL_Device/I_DL_StepperOpenLoop.st` / `DL_Process/FB_DL_ModbusPollMaster.st` / `DL_Process/FB_DL_AndonCallSystem.st` | 1.0.0（PASS 原样） |
| 勘误 | `_Staging_Raw/2026-11-15/ROUND_PLAN_R9.md` §9 V5 表 + 勘误引用块 | — |
| 本报告 | `_Staging_Raw/2026-11-15/AUDIT_R9.md` | — |

> 未触碰：`INDEX_REGISTRY.json`、`ROADMAP.md`、`SOURCE_HUNTING_MATRIX.md`、JSONL（按分工由主控收口）。
> 请主控在文档同步时按本报告第五节码位表刷新 `DL_Base/VERSION.md`、`DL_MathData/VERSION.md`、`DL_Device/VERSION.md` 与 `LIBRARY_MANUAL.md` 码表（**10 件 v1.0.1 + 15 处码位改判**）。

---

*R9 终审报告 ｜ 2026-11-15 ｜ 道莅工控代码库产品总监（总监签字：通过，修复后准入）*
