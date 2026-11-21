# ROUND_PLAN_R62（阶段一派单｜2026-11-21 15:15 起｜预算 ≤50 分钟，16:04 收尾）

> 配额裁决：R61 五抽挂账 4 项（中 2 / 轻 2）≥ 3 → R62 配额 20 → **16**。
> **本轮目标 = 返修 5 项 + 新件 11 件 = 16**（如实登记，不注水）。
> 阶段一范围：本文件仅做盘点、锁定与派单，**不改任何组件代码、不写 JSONL / registry**（阶段三执行）。

---

## 0 盘点看板（R62 阶段一实测）

| 指标 | 实测值 | 说明 |
|---|---|---|
| 总库组件数 | **1,101 / 10,000（11.01%）** | registry v2.53.0，`counts` sum = 1101，与文件树 130+253+128+197+120+273 = 1101 **三向一致** |
| 今日（11-21） | **104 / 200** | R57~R61 五轮累计；今日 500 冲刺计划已超额 |
| 距 1,200 里程碑 | **-99** | R62 完成后 1,112（新增 11 件；返修 5 件不计数），余 88（R63 起约 8 轮） |
| JSONL 语料 | 1,108 条 | 与 1,101 差 7 = R61 返修未重注入（阶段三核账） |
| 源矩阵组级覆盖 | ✔ 9 / ◐ 30 / ☐ 0（共 39 组） | **无未开组**，全部组已开但 30 组未挖尽 → 本项目前处于「组内深化」阶段 |
| 源矩阵全文标记 | ✔ 55 / ◐ 139 / ☐ 39（233 处） | ☐ 39 处为历史「☐→◐ 开组」记录，非现存未开组 |
| ROADMAP 待办 | **43 条未勾 / 544 条已勾** | > 30 条阈值 → **按纪律本轮不追加新待办**（§5 只做卫生注记） |
| 撞名拒单率 | R60/R61 = 50%~60% | 见 §2 取材策略；本轮 T0 候选 36 拟 → 实测 FREE 命中率见 §2.3 |

---

## 1 返修 5 项（批次 = R，全部 P0/P1 优先于新件）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| R1 | `FB_DL_RailPowerSequence` | DL_Base | FB_DL_ | 多轨分级上电/断电逆序时序（R61-D1 严重 + D2 中） | 内部缺陷台账 REVIEW_R61 | 中 | R |
| R2 | `FB_DL_TurretToolSelect` | DL_Motion | FB_DL_ | 刀塔换刀工具选择状态机（R61-D3 死相位） | 内部缺陷台账 REVIEW_R61 | 中 | R |
| R3 | `FB_DL_SensorPairPlausibility` | DL_Device | FB_DL_ | 双传感器偏差/漂移互校（R61-D4 环窗残留） | 内部缺陷台账 REVIEW_R61 | 中 | R |
| R4 | `FC_DL_WeightedPercentile` | DL_MathData | FC_DL_ | 加权分位计算（R61-D5 双写求值序） | 内部缺陷台账 REVIEW_R61 | 中 | R |
| R5 | `FB_DL_LineClearanceVerify` | DL_Process | FB_DL_ | 清线确认窗与残留计数（R61-D6 码 3036 口径） | 内部缺陷台账 REVIEW_R61 | 轻 | R |

> 版本：R1/R2/R3 → **v1.0.1 → v1.0.2**（R61 已发 v1.0.1，本轮续 MINOR 补丁位）；R4/R5 → **v1.0.0 → v1.0.1**（首次返修）。

---

## 2 新件 11 件（批次 1–4，按依赖切 3/3/3/2）

### 2.1 候选表

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_SaturateMul` | DL_Base | FC_DL_ | LINT 宽域饱和乘法（补 Saturate 族第三件） | `iec-std-wrapper`（T0 算术族补口） | 中 | 1 |
| 2 | `FC_DL_SaturateDiv` | DL_Base | FC_DL_ | 饱和除法（除零 / MIN÷-1 / 截断语义统一） | `iec-std-wrapper`（T0 算术族补口） | 中 | 1 |
| 3 | `FC_DL_ShiftArithEx` | DL_Base | FC_DL_ | 算术右移（符号位扩展），移位量钳位 | `iec-std-wrapper`（T0-7 位串组收口） | 中 | 1 |
| 4 | `FC_DL_SignExtendEx` | DL_Base | FC_DL_ | 任意位宽有符号/零扩展至 DINT | `iec-std-wrapper`（T0-7 位串组收口） | 中 | 2 |
| 5 | `FC_DL_RealToIntSat` | DL_MathData | FC_DL_ | LREAL→INT 饱和转换（NaN/Inf/越界 + 钳位标志） | `iec-std-wrapper`（T0-5 转换族补口） | 中 | 2 |
| 6 | `FC_DL_SignedToUdintSat` | DL_MathData | FC_DL_ | 有符号→UDINT 负值钳零 + 信息码 | `iec-std-wrapper`（T0-5 转换族补口） | 低 | 2 |
| 7 | `FC_DL_DtToTodWrap` | DL_MathData | FC_DL_ | DT→当日秒数/TOD 提取（日模 86400，基准无效闸） | `iec-std-wrapper`（T0-5 时间转换补口） | 低 | 3 |
| 8 | `FC_DL_PercentileRank` | DL_MathData | FC_DL_ | 值→百分位排名（分位件的逆运算，SPC 定位） | `iec-std-wrapper`（T0 统计族补口，委托排序） | 中 | 3 |
| 9 | `FB_DL_BiquadFilter` | DL_Algo | FB_DL_ | 二阶 IIR 通用节（稳定域闸 + 状态钳位） | `dsp-public-cookbook`（T1-8 公开二阶节设计公式 clean-room） | 高 | 3 |
| 10 | `FB_DL_VfdDcBusRipple` | DL_Device | FB_DL_ | 变频器直流母线纹波/欠压/过压监视 | `lgf-measurement`（T2-1 LGF Measurement ◐ 深化） | 中 | 4 |
| 11 | `FB_DL_IonFanInterlock` | DL_Device | FB_DL_ | 离子风机风速/平衡三级联锁（下游许可位） | `isa-ne107`（T2-8 ◐ 深化 + ROADMAP R56-1086 承接） | 中 | 4 |

### 2.2 批次依赖切分

- **批 1**（Level 0 算术/移位原子，零依赖）：1 / 2 / 3 —— 三件互为族内对照，推荐同一编码专家一次交齐，便于向量互验。
- **批 2**（Level 0→MathData 转换族，依赖批 1 无）：4 / 5 / 6 —— 全部纯函数、无状态、可并行。
- **批 3**（MathData 组合件 + Algo 有状态件）：7（依赖 `FC_DL_DateToDintDays`）/ 8（依赖 `FC_DL_SortIndexLReal`）/ 9（无依赖，但实现最重）。
- **批 4**（Device 有状态监视/联锁）：10 / 11 —— 两件均无 Level 0 新依赖，仅用 TON / 一阶均值。
- **返修批 R** 与批 1 并行启动（互不占同一文件），批 4 收尾后统一终审。

### 2.3 撞名三查实测（R214 / R61「Ex 系三后缀预查」）

查重口径：`INDEX_REGISTRY.json` 全部 1,101 条 name 转小写后全等比对 + 同义邻件人工复核 + 文件树核对，三查均通过。

| 候选 | 全库同名 | 同义邻件复核结论 | 文件树 |
|---|---|---|---|
| `FC_DL_SaturateMul` | FREE | `FC_DL_SaturateAdd` / `FC_DL_SaturateSub` 为**加法/减法属主**，乘法缺位 → 族补口，非同义 | 无同名文件 |
| `FC_DL_SaturateDiv` | FREE | `FC_DL_DivDintSafeChk`（安全除法返回 BOOL + 商出口）、`FC_DL_DivLrealSafe` 为**安全除**；本件为**宽域饱和除（钳位 + 三段码）**，分工须在头注释写死 | 无同名文件 |
| `FC_DL_ShiftArithEx` | FREE | `FC_DL_ShrEx` / `ShrLwordEx` 为**逻辑右移**；IEC 无算术右移，本件补符号扩展语义（`Arith` 0 命中） | 无同名文件 |
| `FC_DL_SignExtendEx` | FREE | 位串族 9 件均为字段提取/打包/旋转，**无位宽符号扩展**（`Sign*` 仅 Signal 族） | 无同名文件 |
| `FC_DL_RealToIntSat` | FREE | `RealToDintSat`（32 位）/ `RealToByteSat`（8 位）已存，**INT 16 位缺位** → 三段位宽补齐 | 无同名文件 |
| `FC_DL_SignedToUdintSat` | FREE | `UdintToDintChk` 为**反方向**（UDINT→DINT 溢出钳）；本件为 DINT→UDINT 负值钳零，成对 | 无同名文件 |
| `FC_DL_DtToTodWrap` | FREE | `TodAddWrap` / `TodDiffWrap` 为**TOD 运算**；`TimeToDintMs` 为 TIME 域；DT→TOD **提取**缺位（`ToTod` 仅 DintMsToTod） | 无同名文件 |
| `FC_DL_PercentileRank` | FREE | `FC_DL_PercentileLReal` / `QuantileCalc` 是**分位→值**；本件是**值→分位**（逆运算对，SPC 必需） | 无同名文件 |
| `FB_DL_BiquadFilter` | FREE | `LowPassFilter`（一阶）/ `HighPassFilter` / `NotchFilter`（陷波专用）/ `FirFilter`（FIR）均为**结构专用件**；通用二阶节（`Biquad` 0 命中）缺位 | 无同名文件 |
| `FB_DL_VfdDcBusRipple` | FREE | `BrakeResistorThermal` 为**制动电阻热模型**、`InverterGridSync` 为**并网同步**、`VfdThermalDerate` 为**降额**；母线纹波（`DcBus` 0 命中）缺位 | 无同名文件 |
| `FB_DL_IonFanInterlock` | FREE | `FB_DL_VacIonizerBalance` 为**平衡电压测量属主**、`FB_DL_AirShowerInterlockSeq` 为**风淋门联锁**；风速+平衡**合取许可位**缺位 | 无同名文件 |

> 拒单留痕（未入选，防下轮重复提案）：`FC_DL_ShlDwordEx` / `ShrDwordEx`（ROADMAP L948 自标「疑似与存量 ShlEx/ShrEx 同义」→ 立项前须先做语义差实测，本轮不占额）；`FC_DL_RealToIntSat` 的 LREAL 姊妹件（同一件用 LREAL 入参已覆盖，拆件即凑数）；`FC_DL_StringToDintChk`（`FC_DL_StringToDint` 已存）；`FB_DL_ToolLifeCounter`（`FB_DL_ToolLifeBudget` 已存）；`FB_DL_PassboxInterlockSeq` / `FB_DL_GowningRoomSeq`（**均已入库**，见 §5 卫生注记）；`FC_DL_MuxEx`（`Mux2Ex` / `Mux4Ex` / `MuxIntEx` 已覆盖）。

---

## 3 新件完整需求规格（可直接转发编码专家）

### 通用要求（T0 族八件一律适用）

1. **实现口径**：内部**委托平台内建算子/标准语义**（PLUS/MULT/DIV 等由平台实现），外围只加**防御守卫**（域闸、溢出预判、钳位、错误码、标志位）；**禁止重写数学内核**，禁止自实现大整数乘除。
2. **文件头溯源三行必写**：`开源溯源 (Origin)` 写「**IEC 61131-3 标准语义的道莅防御性实现**（clean-room，无第三方代码行）」；`许可证 License` 写 MIT（本库统一）；`参考 Reference` 写「IEC 61131-3:2013 §… 标准函数语义」。
3. **码位**：本表不给具体码值，**阶段三按子库游标实测分配**；信息级建议落子库 `0x0005_xxxx` 段、故障级 `0x0006_xxxx` 段，分配后头注释与 MANUAL 同步。
4. **注释**：100% 中文 + 同行英文；每个变量标物理意义与单位（本批全部无量纲/整数域，须标「[−]」「[位]」「[拍]」「[秒]」「[%]」）。
5. **纯函数件（FC_）**：必须 `VAR_INPUT` 全量域闸 → `RETURN` 早退路径显式置 `bValid=FALSE` / `eErr` / 返回 FALSE；三件套（返回值 + bValid + bError）与 `eErr` **逐出口赋值**，禁依赖预置残留。
6. **有状态件（FB_）**：段 0 无条件刷新全部边沿/定时器；`CASE` 必须有 `ELSE` 安全兜底；安全侧输出在故障/失能相显式清零或冻结并声明理由；首拍 `_bInit` 初始化全量内部量。
7. **浮点**：禁 `=` 判等；入参 `NaN`/`±Inf` 逐个点名闸（R151 全员闸口径）；除子与窗长入参必 `≥1` 证明注释。
8. **禁用**：`GVL` / `VAR_EXTERNAL` / `%I`/`%Q`/`%M` 绝对地址 / 厂商专有库。

---

### 批 1-① `FC_DL_SaturateMul`｜DL_Base｜FC_DL_｜复杂度 中｜来源 `iec-std-wrapper`

**功能规格**
- 语义：`nOut = clamp(nA × nB, nLo, nHi)`，LINT 64 位宽域，**溢出前判定**（禁止先乘后判）。
- 引脚：`nA, nB : LINT`（被乘/乘数 [−]）；`nLo, nHi : LINT`（输出钳位域 [−]）；输出 `nOut : LINT`、`bOvF : BOOL`（溢出发生，钳位已生效）、`bClamped : BOOL`（钳位生效，含域钳）、`bValid : BOOL`、`eErr : UDINT`、`bError : BOOL`；函数返回 `BOOL`（TRUE = 无故障）。
- 溢出判定实现口径（四个象限 + 除零防护）：
  - `nA = 0` 或 `nB = 0` → 结果 0，无溢出；
  - `nA = -1` 且 `nB = DL_SMUL_MIN`（或对称）→ 直接判溢出（`MIN` 的绝对值不可表示）；
  - 正正：`nA > DL_SMUL_MAX / nB` → 溢出；负负：`nA < DL_SMUL_MAX / nB`（nB<0）→ 溢出（符号分支逐条写，禁靠绝对值）；
  - 溢出时：按符号钳到 `nHi`（正）/ `nLo`（负），置 `bOvF` + 故障级码 + `bError`。
- 常量：`DL_SMUL_MAX : LINT := 9223372036854775807`、`DL_SMUL_MIN : LINT := -9223372036854775808`（禁魔法数，注释标 LINT 域极限）。
- 分工声明（头注释 R216）：与 `FC_DL_SaturateAdd` / `FC_DL_SaturateSub` 构成「加/减/乘」三件族，除法则由 `FC_DL_SaturateDiv` 承载；`FC_DL_SaturateAdd` 未覆盖乘法，故本件不可省。

**边界安全条件（必须逐条给验证向量）**
1. `MAX × 2` → 钳 `nHi` + `bOvF`；2. `MIN × -1` → 钳 `nHi`（正溢出）+ `bOvF`（禁回绕成 MIN）；3. `MIN × 0` → 0，`bOvF=FALSE`；4. `MIN × 1` → MIN 精确；5. `-3 × 5` → -15 精确；6. `nLo > nHi`（组态反序）→ 交换并置组态码，或判故障返回 FALSE（二选一，头注释写死，禁静默）；7. 钳位域窄于真实积（如 `nLo=nHi=100`，积 = 200）→ `bClamped=TRUE` 但 `bOvF=FALSE`（两标志语义必须可分）；8. `nA=0, nB=MIN` → 0（除零防护路径）。

---

### 批 1-② `FC_DL_SaturateDiv`｜DL_Base｜FC_DL_｜复杂度 中｜来源 `iec-std-wrapper`

**功能规格**
- 语义：`nOut = clamp(nNum ÷ nDen, nLo, nHi)`，整数除法**向零截断**（IEC 语义，显式注释；不做四舍五入，四舍入口径归 `FC_DL_RoundSat`）。
- 引脚：`nNum, nDen : LINT`；`nLo, nHi : LINT`；输出 `nOut : LINT`、`bDivZero : BOOL`、`bOvF : BOOL`、`bClamped : BOOL`、`bValid : BOOL`、`eErr : UDINT`、`bError : BOOL`；返回 `BOOL`。
- 判据顺序（严格）：① `nDen = 0` → `nOut := 0`、`bDivZero := TRUE`、故障级码、`bValid := FALSE`、返回 FALSE（**早退，禁走钳位**）；② `nNum = DL_SDIV_MIN` 且 `nDen = -1` → 溢出（`MIN ÷ -1` 不可表示），钳 `nHi` + `bOvF` + 码；③ 正常除 → 结果钳 `[nLo, nHi]`。
- 常量：复用 `DL_SDIV_MAX/MIN` 同 LINT 域极限常量（与 `FC_DL_SaturateMul` 常量名不冲突，独立命名）。
- 分工声明：`FC_DL_DivDintSafeChk` 为「安全除 + 商出口 + 布尔返回」的**判据件**，`FC_DL_DivLrealSafe` 为浮点域；本件为**宽域饱和除（LINT + 三段标志 + 钳位域）**，三者边界写进头注释。

**边界安全条件**
1. `x ÷ 0` → 0 + `bDivZero` + `bValid=FALSE`；2. `MIN ÷ -1` → 钳 `nHi` + `bOvF`；3. `MIN ÷ 1` → MIN 精确；4. `1 ÷ MIN` → 0（截断）+ `bClamped` 语义待定（建议 `bClamped=FALSE`，因未触钳位，仅截断）；5. `-7 ÷ 2` → -3（向零截断，非 -4）；6. `nLo > nHi` → 同 ① 件处置口径，两件保持一致；7. `nDen` 为极小负值（-1）与极大负值（MIN）各一条。

---

### 批 1-③ `FC_DL_ShiftArithEx`｜DL_Base｜FC_DL_｜复杂度 中｜来源 `iec-std-wrapper`

**功能规格**
- 语义：对 `DINT` 做**算术右移**（符号位扩展右移），IEC 标准只有逻辑 `SHR`，故须显式补位。
- 引脚：`diIn : DINT`（输入 [−]）；`nShift : DINT`（移位数 [位]，合法 0..31，>31 按语义饱和）；输出 `diOut : DINT`、`bSat : BOOL`（移位量越域被钳）、`eErr : UDINT`、`bError : BOOL`；返回 `BOOL`。
- 实现口径：
  - `nShift ≤ 0` → `diOut := diIn`（0 移位不改值；负值钳 0 并置 `bSat`+信息级码）；
  - `nShift ≥ 32` → 全符号位填充：`diIn < 0` → `diOut := -1`，否则 `0`；置 `bSat`；
  - `1 ≤ nShift ≤ 31` → `udw := DINT_TO_DWORD(diIn)`；`diOut := DWORD_TO_DINT( SHR(udw, nShift) OR DL_SAR_MASK[nShift] )`，其中 `DL_SAR_MASK` 为 **32 项预计算常量表**（`ARRAY[0..31] OF DWORD`，`MASK[k] = 16#FFFF_FFFF SHL (32-k)` 的显式常量，**禁运行时 `SHL(x,32)`**，防未定义行为）；
  - NaN 不适用（整数）。
- 分工声明：`FC_DL_ShrEx` / `FC_DL_ShrLwordEx` 为逻辑右移属主；本件仅补算术语义，头注释互引。

**边界安全条件**
1. `-8 >> 1` → -4；2. `-1 >> 5` → -1（全 1 保持）；3. `8 >> 31` → 0；4. `8 >> 32` → 0 + `bSat`；5. `-8 >> 32` → -1 + `bSat`；6. `x >> 0` → x 精确；7. `x >> -1` → x + `bSat`（越域钳 0，禁反向移位）；8. `MIN >> 1` → -1073741824（符号保持）。

---

### 批 2-① `FC_DL_SignExtendEx`｜DL_Base｜FC_DL_｜复杂度 中｜来源 `iec-std-wrapper`

**功能规格**
- 语义：取 `diIn` 的**低 `nWidth` 位**，按 `bSigned` 选择符号扩展或零扩展，结果落 `DINT`。
- 引脚：`diIn : DINT`；`nWidth : DINT`（位宽 [位]，1..32）；`bSigned : BOOL`（TRUE = 符号扩展，FALSE = 零扩展）；输出 `diOut : DINT`、`eErr : UDINT`、`bError : BOOL`；返回 `BOOL`。
- 实现口径：
  - `nWidth` 越域（<1 或 >32）→ `diOut := 0`、故障级码、`bError := TRUE`、返回 FALSE（**早退，禁钳后继续**：位宽错意味着调用方拼装逻辑已错，静默钳位会掩盖协议错位）；
  - 零扩展：`diOut := DWORD_TO_DINT( DWORD(diIn) AND DL_SEXT_LO[nWidth] )`（低 n 位掩码常量表，32 项）；
  - 符号扩展：先取低 n 位，再判第 n 位（`DL_SEXT_SIGN[nWidth]` 单点掩码），置位则 `OR DL_SEXT_HI[nWidth]`（高位全 1 常量表）；
  - 全表预计算，**禁运行时 `SHL(x, nWidth)` 当 `nWidth=32`**。
- 典型用途注释：Modbus 双字有符号量拼装、12/16 位 ADC 原始码还原、位域字段解包。
- 分工声明：`FC_DL_BitFieldExtract` 为**无符号位段提取**属主；`FC_DL_WordToIntSat` 为**整字宽饱和**属主；本件为**任意窄位宽的有符号/零扩展**，三者边界写死。

**边界安全条件**
1. `nWidth=1, bSigned=TRUE`：`diIn=1` → -1（单 bit 符号）；`diIn=0` → 0；2. `nWidth=8, bSigned=TRUE`：`16#0000_00FF` → -1；`16#0000_007F` → 127；3. `nWidth=16`：`16#0000_8000` → -32768；4. `nWidth=32`：任意值原样返回（两种 `bSigned` 一致）；5. `nWidth=0` → 0 + 故障码 + 返回 FALSE；6. `nWidth=33` → 同上；7. `bSigned=FALSE, nWidth=4, diIn=16#F` → 15（掩码后不扩符号）。

---

### 批 2-② `FC_DL_RealToIntSat`｜DL_MathData｜FC_DL_｜复杂度 中｜来源 `iec-std-wrapper`

**功能规格**
- 语义：`LREAL → INT(16 位)` **饱和转换**，统一三平台「部分平台饱和、部分平台回绕」的差异。
- 引脚：`fIn : LREAL`（输入量 [工程单位]）；`nLo, nHi : INT := -32768 / 32767`（目标钳位域 [−]，默认 INT 全域）；输出 `nOut : INT`、`bClamped : BOOL`、`bNonFinite : BOOL`、`bValid : BOOL`、`eErr : UDINT`、`bError : BOOL`；返回 `BOOL`。
- 判据顺序（严格）：
  1. `fIn` 非有限：`NaN` → `nOut := 0`、`bNonFinite := TRUE`、故障级码、`bValid := FALSE`、返回 FALSE；`+Inf` → 钳 `nHi` + `bNonFinite`；`-Inf` → 钳 `nLo`；
  2. 域闸 `nLo > nHi` → 交换并置组态码（或判故障，与 `FC_DL_SaturateMul` 口径**必须一致**）；
  3. `fIn < LREAL(nLo)` → `nLo` + `bClamped`；`fIn > LREAL(nHi)` → `nHi` + `bClamped`；
  4. 正常：**向零截断**取值（`LREAL_TO_INT` 前先判域，禁先转后判）；截断口径写入头注释，四舍五入口径归 `FC_DL_RoundSat`、分位/工程舍入归 `FC_DL_RoundSigFigs`。
- 分工声明：`FC_DL_RealToDintSat`（DINT 32 位）/ `FC_DL_RealToByteSat`（BYTE 8 位）为同位宽兄弟件；本件补 **INT 16 位**，三件构成位宽三分，头注释互引。

**边界安全条件**
1. `0.0` → 0；2. `-0.5` → 0（向零截断）+ `bClamped=FALSE`；3. `32767.9` → 32767；4. `32768.0` → 32767 + `bClamped`；5. `-32768.1` → -32768 + `bClamped`；6. `NaN` → 0 + `bNonFinite` + `bValid=FALSE`；7. `1.0E9` → 32767 + `bClamped`；8. `nLo > nHi` 组态反序；9. `nLo=nHi=100` 域退化 → 恒定输出 + `bClamped`。

---

### 批 2-③ `FC_DL_SignedToUdintSat`｜DL_MathData｜FC_DL_｜复杂度 低｜来源 `iec-std-wrapper`

**功能规格**
- 语义：`DINT → UDINT` 转换，负值**钳 0** 并给出信息级提示（多数平台此类隐式转换行为不一，负值可能回绕成巨大正数，是 Modbus 寄存器打包的经典故障源）。
- 引脚：`diIn : DINT`（输入 [−]）；输出 `udiOut : UDINT`、`bNegClamped : BOOL`、`bValid : BOOL`、`eErr : UDINT`、`bError : BOOL`；返回 `BOOL`。
- 判据：`diIn < 0` → `udiOut := 0`、`bNegClamped := TRUE`、**信息级码**（不锁存、不置 `bError`、`bValid` 保持 TRUE——负值钳零是合法的确定性行为，非故障）；`diIn ≥ 0` → 精确转换（DINT 正域 ⊆ UDINT 域，无溢出，注释给域包含证明 `[0, 2^31-1] ⊂ [0, 2^32-1]`）。
- 分工声明：`FC_DL_UdintToDintChk` 为**反方向**（溢出钳 + 故障码）；两件成对，头注释互引；`FC_DL_IntToUdintSat` 若后续需要 16 位入口，须**并入本件重载**而非新增文件（防同义邻件）。

**边界安全条件**
1. `0` → 0，`bNegClamped=FALSE`；2. `-1` → 0 + `bNegClamped`；3. `MIN` → 0 + `bNegClamped`；4. `MAX` → 2147483647 精确；5. 反方向向量（`2^32-1` 入 DINT 域不可能，注释说明域包含关系，无须代码分支）。

---

### 批 3-① `FC_DL_DtToTodWrap`｜DL_MathData｜FC_DL_｜复杂度 低｜来源 `iec-std-wrapper`

**功能规格**
- 语义：从 `DT` 提取**当日秒数**（0..86399）与 `TOD`，日模 86400 显式化。
- 引脚：`dtIn : DT`（时间戳 [日期时间]）；输出 `todOut : TOD`、`diSecOfDay : DINT`（当日秒数 [秒]，0..86399）、`bValid : BOOL`、`eErr : UDINT`、`bError : BOOL`；返回 `BOOL`。
- 实现口径：**委托同子库既有件** `FC_DL_DateToDintDays`（日期→天序数）+ 秒内分解，禁止内联重写日期算法（R216 不内联低层实现）；`diSecOfDay = (天序数差 × 86400 + 当日秒)` 后 `MOD 86400`；`todOut := DINT_TO_TOD(diSecOfDay × 1000)`（ms 域）或 `FC_DL_DintMsToTod` 委托（**取其一，头注释写明**）。
- 基准无效闸：`dtIn < DT#1970-01-01-00:00:00`（未初始化/非法时间戳）→ `todOut := TOD#00:00:00-000`、`diSecOfDay := 0`、信息级码、`bValid := FALSE`、返回 FALSE（禁直接把负天数 MOD 成看似合法的时刻）。
- 分工声明：`FC_DL_TodAddWrap` / `TodDiffWrap` 为 TOD 运算属主；`FC_DL_TimeToDintMs` 为 TIME 域；`FC_DL_DtToDintEpoch` 为绝对纪元秒；本件为**当日秒/TOD 提取**，四件边界写死。

**边界安全条件**
1. 基准 `DT#1970-01-01-00:00:00` → 0 s；2. `DT#2024-02-29-23:59:59` → 86399 s（闰日）；3. `DT#2024-03-01-00:00:00` → 0 s；4. `DT#0000-01-01-00:00:00`（早于基准）→ `bValid=FALSE`；5. 极端未来 `DT#2106-02-07-06:28:15` → 85935 s（跨 32 位不溢出）；6. `DT#1970-01-02-00:00:00` → 0 s（日推进不残留）。

---

### 批 3-② `FC_DL_PercentileRank`｜DL_MathData｜FC_DL_｜复杂度 中｜来源 `iec-std-wrapper`

**功能规格**
- 语义：给定样本集与一个值，求该值的**百分位排名**（0..100），即「当前值在历史分布中的位置」，SPC/过程能力定位用。
- 引脚：`afSamples : ARRAY[0..255] OF LREAL`（样本 [工程单位]）；`nCount : DINT`（有效样本数 [个]，1..256）；`fValue : LREAL`（待定位值）；`eMethod : E_DL_RankMethod := E_DL_RankMethod.eMidRank`（排名口径：`eWeak` 弱排名 / `eStrong` 强排名 / `eMidRank` 中位排名）；输出 `fPct : LREAL`（百分位 [%]，0..100）、`nBelow : DINT`（小于样本数 [个]）、`nEqual : DINT`（等于样本数 [个]）、`bValid : BOOL`、`eErr : UDINT`、`bError : BOOL`；返回 `BOOL`。
- 实现口径：
  - **委托** `FC_DL_SortIndexLReal` 取升序索引，再二分定位（禁内联全排序，R216）；委托失败位与故障码回传必须**独立变量承接**（R61-D5 教训：禁 `bValid =>` 与返回值双写同一变量）；
  - `nBelow` / `nEqual` 显式出口，`fPct` 按 `eMethod` 三口径算：`eWeak = nBelow/nEff×100`、`eStrong = (nBelow+nEqual)/nEff×100`、`eMidRank = (nBelow + nEqual/2)/nEff×100`；
  - NaN 样本逐条剔除并计数（`nNonFinite` 局部），`nEff = nCountValid`；`fValue` 为 NaN → 故障码 + `bValid=FALSE`；
  - `nCount` 越域（<1 或 >256）→ 故障码 + 早退；`eMethod` 非法枚举 → `CASE ... ELSE` 落 `eMidRank` 并置组态码（**禁静默**，`E_DL_RankMethod` 属主为本文件，声明区每个枚举项带中文同行注释）。
- 分工声明：`FC_DL_PercentileLReal`（值←分位）/ `FC_DL_WeightedPercentile`（加权分位）/ `FC_DL_QuantileCalc`（分位族通用）为**分位→值**方向；本件为**逆运算**，头注释互引并写明「SPC 定位 vs 限值设定」的选型差异。

**边界安全条件**
1. 全部样本相同、`fValue` 相等 → 三口径分别为 0 / 100 / 50（向量必须逐口径断言）；2. `fValue` 小于最小样本 → 0%；3. 大于最大样本 → 100%；4. 单样本 `nCount=1` → 三口径 0 / 100 / 50；5. 含 2 个 NaN + 6 个有效 → `nEff=6`（除子证明 ≥1）；6. `nCount=0` → 故障码 + 早退（禁除零）；7. `nCount=257` → 越域码早退；8. `eMethod = 非法值（如 99）` → 落 `eMidRank` + 组态码；9. `fValue = NaN` → 故障码 + `bValid=FALSE`。

---

### 批 3-③ `FB_DL_BiquadFilter`｜DL_Algo｜FB_DL_｜复杂度 高｜来源 `dsp-public-cookbook`

**功能规格**
- 语义：通用二阶 IIR 节（Direct Form I），系数由调用方给（归一化 `a0 = 1`），可配置为低通/高通/带通/带阻/全通，供现场自行按公开二阶节设计公式（RBJ Audio EQ Cookbook 类公开公式）算系数后下发。
- 引脚：`bEnable, bResetState : BOOL`；`fIn : LREAL`（输入 [工程单位]）；`fB0, fB1, fB2, fA1, fA2 : LREAL`（归一化系数 [−]）；`fOutMin, fOutMax : LREAL`（输出钳位域 [工程单位]）；`tSample : TIME`（采样周期 [毫秒]，仅用于系数变更判据与注释）；输出 `fOut : LREAL`、`bSat : BOOL`、`bCfgBad : BOOL`、`bValid : BOOL`、`eErr : UDINT`、`bError : BOOL`。
- 实现口径：
  - 差分方程：`w := fIn - fA1*w1 - fA2*w2`；`fOut := fB0*w + fB1*w1 + fB2*w2`；`w2 := w1`；`w1 := w`；
  - **稳定域闸**：`|fA1| < 2.0` 且 `|fA2| < 1.0` 且 `|fA2 - fA1| < 1` 的三角稳定判据（二阶极点落单位圆内的显式充分条件），越域 → `bCfgBad := TRUE` + 故障码 + `fOut` 冻结上次有效值（**不输出发散值**）；
  - 系数任一非有限（NaN/Inf）→ 同 `bCfgBad` 路径；
  - 系数变更沿（五系数任一与上拍不等，浮点比较用 `ABS(a-b) > 1.0E-9`）→ 清 `w1/w2`（防旧状态冲击新频响），并在注释声明「在线变系数为无扰切换的保守处置」；
  - **输出钳位 + 抗 windup**：`fOut` 钳 `[fOutMin, fOutMax]` 后，若被钳则 `w1 := fOut`（状态回写，防积分式累积发散），置 `bSat`；
  - `bResetState` 单拍 → `w1 := 0.0; w2 := 0.0;`（段 0 刷新后段内消费，`R_TRIG` 无条件调用）；
  - `bEnable = FALSE` → `fOut := 0.0`、状态清零（安全侧显式清零并注释理由：滤波器输出为下游控制量，失能须归零）。
- 分工声明（R216）：`FB_DL_LowPassFilter`（一阶 RC）/ `FB_DL_HighPassFilter`（一阶）/ `FB_DL_NotchFilter`（陷波专用，结构固定）/ `FB_DL_FirFilter`（FIR）为**结构专用轻量件**；本件为**通用二阶节**，适用「需要带通/带阻/可调 Q 且带 ST 系数下发的场合」。四件选型对照写入 `MANUAL_DL_Algo`。

**边界安全条件**
1. 阶跃输入、`b0=0.0675, b1=0.1349, b2=0.0675, a1=-1.1430, a2=0.4128`（公开二阶低通设计值）→ 输出单调收敛于稳态，无过冲爆炸；2. `a1 = 2.5`（不稳定）→ `bCfgBad=TRUE` + `fOut` 冻结；3. `a1 = NaN` → 同 ②；4. 在线把低通系数换成高通系数 → 状态清零，`fOut` 单拍跳变被钳位而不是发散；5. `bResetState` 单拍 → `w1=w2=0`；6. `fIn = 1.0E9` 持续 → `fOut` 钳 `fOutMax` + `bSat` + `w1` 回写（下一拍不反向冲）；7. `bEnable=FALSE` → `fOut=0.0`、状态零；8. `fOutMin > fOutMax` → 组态码 + `bCfgBad`；9. 首拍 `_bInit` → 状态零、`fOut := 0.0`（禁首拍用未初始化状态）。

---

### 批 4-① `FB_DL_VfdDcBusRipple`｜DL_Device｜FB_DL_｜复杂度 中｜来源 `lgf-measurement`

**功能规格**
- 语义：变频器直流母线电压的**均值 / 峰峰值纹波率 / 欠压 / 过压**三路监视（电解电容老化、整流缺相、制动能量回灌的早期征兆）。
- 引脚：`bEnable : BOOL`；`fUdMeas : LREAL`（母线电压实测 [V]）；`fUdNom : LREAL`（额定母线电压 [V]，须 > 0）；`tSample : TIME`（采样周期 [毫秒]）；`nWinLen : DINT := 64`（滑窗样本数 [个]，合法 2..128）；`fRippleLimPct : LREAL`（纹波率上限 [%]）；`fUnderLimPct : LREAL := 85.0`（欠压阈值 [%] 相对额定）；`fOverLimPct : LREAL := 115.0`（过压阈值 [%]）；`fHystPct : LREAL := 2.0`（判据迟滞 [%]）；输出 `fUdAvg : LREAL`（窗均值 [V]）、`fRipplePct : LREAL`（峰峰值纹波率 [%]）、`bUnder, bOver, bRippleHigh : BOOL`（三路判据，带迟滞）、`nFill : DINT`（窗已填样本数 [个]）、`bValid : BOOL`、`eErr : UDINT`、`bError : BOOL`。
- 实现口径：
  - 环形窗（`ARRAY[0..127] OF LREAL` 固定容量，禁动态分配），`_nHead` 写头 + `_nFill` 填充计数；均值除子用 **`_nFill`（钳 ≥1）** 而非 `nWinLen`（防首填阶段均值偏低——R61-D4 同类陷阱，本件出厂即正确）；
  - `nWinLen` **逐拍可变**：变更沿（`_nUse ≠ _nUsePrev`）→ 清窗 + 清头 + 清和 + `_nFill := 0`（R61-D4 修法固化）；
  - `fUdNom ≤ 0` 或非有限 → 组态码 + `bValid=FALSE`（除零防护，`fUdNom` 既作除子又作基准）；
  - 欠压/过压：`fUdAvg / fUdNom × 100` 与阈比较，迟滞 `fHystPct`（上升沿触、回落 `lim - hyst` 复原）；
  - 纹波率：`(fMax - fMin) / fUdAvg × 100`，`fUdAvg` 近零（`ABS < 1.0`）→ 故障码 + 不计算（防除零）；
  - `fUdMeas` 非有限 → 丢弃该样本、`nNonFinite` 计数超窗长一半 → 故障码 + `bValid=FALSE`；
  - `bEnable=FALSE` → 三路判据全 FALSE、`fRipplePct := 0.0`、保留 `fUdAvg` 最后有效值并注释理由（纯监视件，不驱动功率级）。
- 分工声明（R216）：`FB_DL_BrakeResistorThermal` 为制动电阻热模型、`FB_DL_VfdThermalDerate` 为降额策略、`FB_DL_InverterGridSync` 为并网同步；本件为**母线电气健康监视**，四件互引。

**边界安全条件**
1. 恒定 `fUdNom` 输入（纹波 0）→ `fRipplePct=0`、三路判据全 FALSE；2. 首个样本即判据（`_nFill=1`）→ 均值 = 单样本，`bValid=FALSE`（窗未达门限，注释声明门限 `_nFill ≥ nWinLen/2`）；3. `nWinLen` 由 64 改 16 → 窗清零、`_nFill=0`，均值不含旧样本（**R61-D4 回归向量**）；4. `fUdNom = 0` → 组态码 + `bValid=FALSE`（禁除零）；5. `fUd = 0` 且 `fUdNom > 0` → `bUnder=TRUE`，纹波率因均值近零走故障码；6. 全部样本 NaN → `bValid=FALSE` + 故障码；7. 欠压在阈值上下抖动 1%（小于迟滞）→ `bUnder` 不反复跳；8. `nWinLen=1` 或 `=129` → 越域钳位 + 组态提示（与域声明一致）。

---

### 批 4-② `FB_DL_IonFanInterlock`｜DL_Device｜FB_DL_｜复杂度 中｜来源 `isa-ne107`

**功能规格**
- 语义：离子风机「运行反馈 + 风速下限 + 平衡电压」三判据合取，输出下游设备的**许可位**（半导体/锂电装配段 ESD 防护联锁）。
- 引脚：`bEnable : BOOL`；`bFanRun : BOOL`（风机运行反馈）；`fAirSpeed : LREAL`（出风速度 [米每秒]）；`fSpeedMin : LREAL`（风速下限 [米每秒]，须 > 0）；`fBalanceV : LREAL`（离子平衡电压实测 [伏]）；`fBalanceLimV : LREAL`（平衡电压绝对上限 [伏]，须 > 0）；`tConfirm : TIME := T#3S`（判据持续确认窗 [毫秒]）；`fHystPct : LREAL := 5.0`（判据迟滞 [%]）；输出 `bPermit : BOOL`（下游允许运行，**安全侧默认 FALSE**）、`bAlarmSpeed, bAlarmBalance, bAlarmFan : BOOL`（三路分级报警，NE107 语义：`bAlarmFan` 为 Failure 级、另两路为 OutOfSpec）、`eState : E_DL_IonFanPhase`（状态机出口）、`bValid : BOOL`、`eErr : UDINT`、`bError : BOOL`。
- 实现口径：
  - 三判据：`bFanRun` 为真、`fAirSpeed ≥ fSpeedMin × (1 - fHystPct/100)`（迟滞在下限下方复原）、`ABS(fBalanceV) ≤ fBalanceLimV × (1 + fHystPct/100)`（迟滞在上限上方复原）；
  - 三判据**同时满足并持续 `tConfirm`** 才置 `bPermit := TRUE`（`TON` 段 0 无条件刷新，`IN` 串「三判据合取 AND 使能」）；任一判据失效立即 `bPermit := FALSE`（零延时撤除，安全侧要求：**许可发放可延迟，撤除不可延迟**，头注释写死该非对称性）；
  - 首拍 `_bInit` → `bPermit := FALSE`（**出厂默认 F**，禁首拍误许可）；
  - 组态域闸：`fSpeedMin ≤ 0` 或 `fBalanceLimV ≤ 0` 或 `tConfirm ≤ T#0S` → 组态码 + `bPermit := FALSE`；
  - 非有限输入：`fAirSpeed` / `fBalanceV` 非有限 → 视为判据不满足（保守）+ 对应故障码（区分「测点坏」与「真超标」——用 `bValid=FALSE` + 码表达，禁把 NaN 当合格）；
  - `E_DL_IonFanPhase`（属主本文件）：`eIdle` 空闲 / `eWarmup` 判据确认中 / `ePermit` 已许可 / `eAlarm` 判据失效报警，`CASE ... ELSE` 落 `eAlarm` 并清 `bPermit`；
  - `bEnable=FALSE` → `bPermit := FALSE`、报警位清零、状态 `eIdle`。
- 分工声明（R216）：`FB_DL_VacIonizerBalance` 为**平衡电压测量/标定属主**（本件只消费其结果或现场模拟量，不重算平衡）；`FB_DL_AirShowerInterlockSeq` 为**风淋门物流联锁**；`FB_DL_EsdGroundMonitor` 为**接地连续性**；本件为**离子风机效能联锁**，四件边界写进头注释与 `MANUAL_DL_Device`。

**边界安全条件**
1. 三判据全满足、持续 `tConfirm` 后 `bPermit=TRUE`；2. `tConfirm` 未到即撤除 → 全程 `bPermit=FALSE`；3. 许可态下 `bFanRun` 掉电 → **同拍** `bPermit=FALSE` + `bAlarmFan`（零延时撤除向量）；4. `fAirSpeed = NaN` → `bPermit=FALSE` + 码 + `bValid=FALSE`；5. `fSpeedMin = 0` → 组态码 + `bPermit=FALSE`；6. 风速在 `fSpeedMin` 上下抖动 3%（小于迟滞 5%）→ 判据不反复跳；7. 平衡电压 `+6V`（限 5V）→ `bAlarmBalance=TRUE`、`bPermit=FALSE`；回落 4.9V 但未到 `5×1.05` → 仍报警（迟滞正确方向）；8. 首拍 → `bPermit=FALSE`；9. `bEnable` 由 F→T 且三判据已满足 → 仍需完整 `tConfirm`（禁跳过确认窗）。

---

## 4 返修指令（阶段三执行，逐条现象 + 修法 + 验收向量）

### R1 `FB_DL_RailPowerSequence` v1.0.1 → v1.0.2（DL_Base · 严重 + 中）

**现象 1（D1 残口，严重）**：R61 已把 `_nStep := UDINT_TO_DINT(_nCnt) - 1` 的负值钳到 0（`IF _nStep < 0 THEN _nStep := 0`），但**语义仍错**：`_nCnt = 0`（无已上电轨）时收到断电沿，`eIdle` 仍迁入 `eRampDn`，`eRampDn` 首拍 `NOT abRailFb[0]` 成立 → `_nStep = -1` → 置 `bDone := TRUE` 迁回 `eIdle`。即**空轨断电请求会伪造一颗「完成单拍」**，上位若以 `bDone` 计轮次会多计一轮。
**修法**：`eIdle` 的 `rtOff` 分支改为**空轨早退**：`IF _nCnt = 0 THEN` 不迁移、不置 `bDone`，仅置信息级码（建议「空轨断电请求忽略」）并保持 `eIdle`；`ELSE` 才 `_nStep := UDINT_TO_DINT(_nCnt) - 1` 并迁 `eRampDn`。原钳位语句可保留作二重防御，但**不得再作为唯一防线**。`eStable` 分支的同类计算也须套同一 `_nCnt = 0` 早退口径（两处一致）。
**验收向量**：① `uRailCount=3`、`abRailFb` 全 FALSE、`bOffCmd` 上升沿 → `bDone` 全拍 FALSE、`eState` 保持 `eIdle`、`eErr` 为信息级码；② 正常上电 3 轨完成后断电 → `bDone` 恰好 1 拍 TRUE；③ `_nCnt=0` 且 `eStable`（构造异常态）→ 同 ①。

**现象 2（D2，中）**：`tonStep(IN := _bStepGo AND (NOT _bFault), ...)` 中 `_bStepGo` 是「处于步进相」的驻留派生量，整段时序连续计时、轨间不复位，故标称「单轨超时 `tStepTimeout`」实为「整段超时」，慢反馈会在第 3 轨误锁 0643。
**修法**：新增局部 `_bRailPending : BOOL`（本轨尚未响应，逐拍派生）：
- `eRampUp` 相：`_bRailPending := NOT abRailFb[_nStep]`；
- `eRampDn` 相：`_bRailPending := abRailFb[_nStep]`；
- 其余相：`_bRailPending := FALSE`；
`tonStep(IN := _bStepGo AND (NOT _bFault) AND _bRailPending, PT := tStepTimeout)` —— 本轨一响应 `IN` 落 FALSE，TON 自动复位，实现**逐轨计时**。
同时段 0 的 `rtFb` 刷新条件从「仅 `eRampUp`」扩为「`eRampUp` 或 `eRampDn`」，两相都用 `abRailFb[_nStep]`（断电相现固定刷 `abRailFb[0]`，与 `_nStep` 逆向推进不一致，属同族隐患）；非步进相维持 `abRailFb[0]` 固定刷。
**验收向量**：① 3 轨、每轨反馈延时 `tStepTimeout × 0.8` → 全序列成功、无 0643（旧版在第 3 轨误锁）；② 单轨反馈延时 `tStepTimeout × 1.2` → 该轨锁 0643；③ 断电逆序每轨延时 `0.8×` → 成功；④ 断电态第 1 轨卡住 → 单轨超时锁存。

---

### R2 `FB_DL_TurretToolSelect` v1.0.1 → v1.0.2（DL_Motion · 中 · 死相位）

**现象（D3）**：`E_DL_TurretPhase.eFault`（值 20）声明存在、头注释写「故障：组态非法，锁存待复位」，`CASE` 内也有 `eFault` 标签与「`NOT _bFault` 才迁出」的出口，但**全库无任何迁入 `eFault` 的语句**：`eIdle` / `eMoving` 的故障出口都迁 `eIdle`（L165-166、L173-174），`eFault` 恒不可达 → 死相位；现场读到 `eState=eIdle` 且 `bError=TRUE` 时无法区分「未换刀」与「组态故障」。
**修法（选定：补迁入闸，不删相）**：在段 4 状态机之后（或 `CASE` 前置段）加**统一迁移闸**：
```iecst
IF _bFault AND (_eState <> E_DL_TurretPhase.eFault) THEN // 故障锁存统一迁入闸（R274 迁入完备性）
    _eState := E_DL_TurretPhase.eFault; // 任何相检出故障一律落故障相
END_IF
```
同时把 `eIdle` / `eMoving` 里「`ELSIF _bFault THEN _eState := eIdle`」两条出口**改为 `eFault`**（否则同拍内先迁 idle 再被闸拉回，虽结果正确但语义重复，且 R274 复扫会判「出口不一致」）；`eFault` 相的自有出口保持「`NOT _bFault` 才迁 `eIdle`」不变（解除可达：`bReset` 上升沿清 `_bFault`，已由 L98 自证）。
**不删相理由**（须写入头注释与 `MANUAL_DL_Motion`）：`eFault` 是 R274 要求的状态机完整性成员，且与 `FB_DL_SingleAxis` 族故障相命名一致；删相会让「组态非法」与「空闲」在 `eState` 出口上不可分，损失诊断保真。
**验收向量**：① 组态非法（如刀位数越域）→ `eState = eFault`、`bError=TRUE` 同拍；② 故障态下 `bReset` 上升沿 → 清锁存、迁 `eIdle`；③ 正常换刀全流程 → `eState` 轨迹 `eIdle→eMoving→eIdle`，`eFault` 不出现；④ 移动相中途组态非法 → 直接落 `eFault`（不再经 `eIdle`）。

---

### R3 `FB_DL_SensorPairPlausibility` v1.0.1 → v1.0.2（DL_Device · 中 · 环窗残留）

**现象（D4）**：环窗 `_afRing` / `_fRingSum` / `_nHead` 按 `_nUse`（钳位后窗长）回卷，但 `_fRingSum` 的**减去项**始终是 `_afRing[_nHead]`。窗长由 32 缩到 8 后，`_afRing[8..31]` 的旧条目永久留在和里、再不会被覆盖（写头只在 `0..7` 回卷），漂移均值含陈旧样本 → 漂移判据失真。
**现象 2（同族，需一并修）**：首填阶段 `_nFill < _nUse` 时，均值除子已是 `_nUse`（L143 `_fRingSum / DINT_TO_LREAL(_nUse)`），前 `_nUse-1` 拍的均值系统性偏小，可能漏报启动期漂移。
**修法**：
1. 新增局部 `_nUsePrev : DINT := 8`；段 2 域闸钳位后：`IF _nUse <> _nUsePrev THEN` 清 `_fRingSum := 0.0`、`_nHead := 0`、`_nFill := 0`、`_nUsePrev := _nUse`（**窗长变更沿清窗**，R61-D4 修法固化为族规则）；
2. 新增局部 `_nFill : DINT := 0`；段 3 推入后 `IF _nFill < _nUse THEN _nFill := _nFill + 1`；
3. 均值除子改 `DINT_TO_LREAL(_nFill)`，并在 `_nFill = 0` 时跳过判据（除子证明注释须重写，禁沿用「除子 ≥ 1」旧证）；
4. 首拍/复位沿同步清 `_nFill` 与 `_nUsePrev`（加进既有复位清单，R243 口径）。
**验收向量**：① 窗 32 跑 40 拍后缩到 8 → 均值只含最近 8 个样本（旧版含陈旧项，向量值需在 REVIEW 里量化）；② 窗 8 首 3 拍（`_nFill=3`）→ 均值 = 3 样本均值（旧版除子 8，偏小 62%）；③ `_nFill=0` → 判据不执行、无除零；④ 窗长反复 8↔32 抖动 → 无残留累加漂移。

---

### R4 `FC_DL_WeightedPercentile` v1.0.0 → v1.0.1（DL_MathData · 轻 · 双写求值序）

**现象（D5）**：L149 `bSortOk := FC_DL_SortIndexLReal(... bValid => bSortOk ...)` —— 函数**返回值**赋给 `bSortOk`，同时**输出映射 `bValid =>` 也写同一变量**。IEC 未规定 REQUEST 函数返回值与输出映射的求值次序，三平台行为可能不同（CODESYS / TwinCAT / InoProShop），是典型的方言风险。
**修法（推荐 A，双信号都用上）**：
```iecst
_bSortRet := FC_DL_SortIndexLReal(afValues := afValues, nCount := nUse, aIdx => aOrd,
                                  bValid => _bSortValid, eErr => uSortEr, bError => bSortEr);
bSortOk := _bSortRet AND _bSortValid; // 返回值与可用位各自承接后合取（禁双写同一变量）
```
新增局部 `_bSortRet : BOOL`、`_bSortValid : BOOL`，均入首段预置 FALSE。**替代方案 B**（仅删 `bValid =>` 映射、只信返回值）也可，但会丢掉「委托件返回 TRUE 但 bValid=FALSE」的异常组合，抗错性弱于 A，**本轮采用 A**。
**验收向量**：① 正常 8 样本 → 结果与 v1.0.0 逐位一致（无行为回退）；② 委托件返回 FALSE → `bSortOk=FALSE`、`bValid=FALSE`、故障码（不越界写 `aOrd`）；③ 委托件返回 TRUE 但内部 `bValid=FALSE`（构造）→ `bSortOk=FALSE`（A 方案能捕获，旧版不能）。

---

### R5 `FB_DL_LineClearanceVerify` v1.0.0 → v1.0.1（DL_Process · 轻 · 码 3036 口径）

**现象（D6）**：头注释 L30 写「`16#0005_3036`【信息级】清线请求时残留计数非零（逐拍重算，不锁存）」，实现 L164 为 `_uResidue > DINT_TO_UDINT(nResidueMax)` 逐拍判据。默认 `nResidueMax = 0` 时两者在「残留非零」处重合，但语义差两处：① 触发时机「请求拍单点」vs「确认窗内每一拍」；② 判据是「非零」vs「超上限」（`nResidueMax > 0` 时实现允许残留而不报，注释却暗示非零即报）。
**修法（按 R285「口径以实现为准 + 注释订正」，不改行为）**：
1. 头注释 L30 订正为：「`16#0005_3036`【信息级】清线确认窗内**残留计数超过 `nResidueMax`** 时逐拍提示（默认 0 = 残留非零即提示）；不锁存、不置 `bError`、不阻断放行」；
2. 输入引脚 `nResidueMax` 的行内注释补「默认 0 即非零即提示；调大则该量残留仍允许放行」；
3. 段 5 判据顺序复核：`3036` 为信息级，必须**排在故障级判据之后**、且**不得覆盖**已置的故障码（`ELSIF` 链末位）；若当前在链中位，移到末位；
4. `MANUAL_DL_Process` 对应条目同步该口径（阶段三文档步）。
**验收向量**：① `nResidueMax=0`、`_uResidue=1` → `eErr=3036`、`bError=FALSE`；② `nResidueMax=3`、`_uResidue=2` → `eErr=0`（允许残留）；③ `nResidueMax=3`、`_uResidue=4` → 3036；④ 窗非法（`tConfirmWin ≤ 0`）同时残留超限 → 故障码优先，3036 不覆盖。

---

## 5 ROADMAP 卫生注记（本轮不改写 ROADMAP：未勾 43 条 > 30 条阈值，按纪律不追加）

上轮 P2 两条**已被实现但未勾选**（三向一致差额，阶段三补勾）：

| ROADMAP 行 | 条目 | 实测 | 处置 |
|---|---|---|---|
| L1087 | 「洁净室物流联锁族扩位评估：Passbox 三段联锁 / 更衣序列」 | `FB_DL_PassboxInterlockSeq` **已注册**、`FB_DL_GowningRoomSeq` **已注册** | 阶段三直接勾选，登记「已落地（实现在先，ROADMAP 滞后）」 |
| L1086 | 「ESD 设备族扩位评估：离子风机风速联锁 / ESD 接地连续性」 | `FB_DL_EsdGroundMonitor` **已注册**；离子风机联锁 = **本轮 11 号新件** | 半勾：接地件已落地，联锁件本轮落地后一并勾选 |

另记：`FB_DL_ToolLifeBudget` 已存在，故「刀具寿命计数」类候选（`ToolLifeCounter` / `ToolLifeConsum`）本轮**拒单**，避免同义邻件。

---

## 6 阶段三交接清单（不改代码、不改 registry，仅列动作）

1. 返修 5 件落盘 + 版本递增 + JSONL 对应行重注入（sha256 逐行复验 + 全量行数校验，R102）。
2. 新件 11 件落盘 + `INDEX_REGISTRY.json` 增补（counts 130/253/128/197/120/273 → 目标 **134/257/129/199/120/273**，总 **1,112**；今日 104 → **115**/200）。
3. 码位分配：阶段三按子库游标实测，**禁沿用本文件建议段**；分配后头注释 / MANUAL / registry `code_segment` 三处同改。
4. 文档五件套增量：六本 `VERSION.md`、六本 `MANUAL_DL_*.md`、`CHANGELOG.md`、`LIBRARY_MANUAL.md`、`README.md`、`SOURCE_HUNTING_MATRIX.md`（§5 台账行：T0 组状态 + T2-1 Measurement / T2-8 深化记录）。
5. ROADMAP 勾选 ≤10 条：L1086 / L1087 两条卫生项 + 本轮落地件对应条目。
6. 终审复扫：R1/R2/R3（严重/中/中）必须逐件推演；新件 11 件按五抽 + 定向扫查（闸覆盖率 / 相迁移 / 同拍竞态 / 冻结分支出口）。

---

*R62 阶段一 ｜ 2026-11-21 ｜ 道莅工控代码库产品总监*
