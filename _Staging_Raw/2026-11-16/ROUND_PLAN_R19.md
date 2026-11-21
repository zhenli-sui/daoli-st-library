# ROUND PLAN R19 —— 阶段一盘点 + 阶段二狩猎派单（20 件 / 4 批）

> 轮次：**R19** ｜ 生成时间：2026-11-16 15:35 ｜ 编制：道莅工控代码库产品总监（daoli-library-director）
> 性质：**非纯 T0 轮**（T0 补位 4 件 + 薄库扩族 16 件：Algo 4 / Device 4 / Motion 4 / Process 2 / Base 1 / MathData 5）
> 检索：**WebSearch 2 次**（PROFINET ChannelErrorType 公开语义核对；继电自整定描述函数公式核对），其余全部复用既有台账
> 本文性质：**派单规格书**（可直接编码，禁止再向规格要信息）；`.st` 落盘由批次 1-4 执行

---

## 0 盘点区（Step 1 · 状态读取 · 全部实测，不沿用口头交接）

### 0.1 总库状态（`INDEX_REGISTRY.json` 实解析 + `DL_*/*.st` glob 实测）

| 项 | 实测值 |
|---|---|
| `version` | **2.7.0** |
| `total_components` | **304** |
| `last_updated` | `2026-11-16T13:20:00+08:00` |
| `counts` | DL_Base **63** / DL_MathData **107** / DL_Algo **32** / DL_Device **53** / DL_Motion **21** / DL_Process **28**（合计 304 ✔ 自洽） |
| 物理 `.st` 文件数 | **304**（`ls DL_*/*.st` 实测，与 registry 一一对应） |
| 总库完成度 | **304 / 10 000 = 3.04 %** |
| 今日累计 | **100 / 200**（11-16 开账 186 → 304） |
| 距 500 冲刺差额 | **196** |
| 语料条数 | **304 条**（`_AI_Training_Dataset/daoli_st_sft_dataset.jsonl`） |

### 0.2 源矩阵覆盖率与薄库判定

| 库 | 件数 | 判定 | 本轮配比 |
|---|---|---|---|
| DL_Base | 63 | 厚（Level 0 已饱和） | 1 |
| DL_MathData | 107 | 厚（T0 主战场） | 5（其中 4 件为 T0 补位承诺件） |
| **DL_Algo** | **32** | **薄** | 4 |
| **DL_Device** | **53** | 中 | 4 |
| **DL_Motion** | **21** | **最薄** | 4 |
| **DL_Process** | **28** | **薄** | 2 |

**配比结论**：`DL_Motion 21 / DL_Process 28 / DL_Algo 32` 三薄库合计拿 **10/20**，Level 0 只承接 4 件 ROADMAP §22.2 已承诺的 T0 补位 + 1 件 LGF 位串扩族。

### 0.3 ⚠ 码位分段裁定（R61 教训执行：**实测为准，禁口头交接**）

**本轮最重要的盘点发现：R18 交接的「`0001_` 信息级下一可用 = `0245`」是错的。**

以源码为唯一事实源实测（`_verify_r19.py`，已落盘可复跑）：`16#0001_` 段**信息级 02xx 区已被 R15~R17 件占满**——`0240~0244` 属 R18 件，`024B / 024F / 0254 / 0255 / 0259 / 025E / 0263 / 0277 / 027C / 028B` 及 **`028E~02FF` 连续占满**（R16/R17 饱和转换族、对数 dB 族、TIME/TOD 族、LWORD 移位族，每件 3 码）。实扫结果：

```
0001 段：信息级(<0x300) max = 02FF，故障级(>=0x300) max = 031D
0001 段 0245~02FF 空闲槽：63 个，但呈 15 段碎片（1~19 个/段），无连续 ≥8 的可用块
```

即：**若照 R18 交接的 `0245` 顺延 12 个信息码，将踩进 `024B/024F/0254` 等既有件的码域**（R30 越段撞车复现）。

**R19 裁定（规格级主动收窄，收口时不得再改判）**：

| 段 | 既有惯例（实测） | **R19 起新规** | 本轮起点 |
|---|---|---|---|
| `16#0001_`（Base / MathData） | 信息级 01xx/02xx，故障级 02xx→03xx | **02xx 信息级已耗尽 → 信息级开子带 `04xx`**；故障级续 `03xx` | 信息 **`0400`**；故障 **`031E`** |
| `16#0002_`（Algo） | `CCSS` 网格，CC = 组件序号 01~26 | 续用，CC = `27 / 28 / 29 / 2A` | CC **`27`** |
| `16#0003_`（Device） | 信息 01xx（至 `0169`）、故障 02xx 组态 / 03xx 工艺（至 `032F`） | 续用 | 信息 **`016A`**；故障 **`0330`** |
| `16#0004_`（Motion） | 信息 01xx（至 `01CC`）、故障 02xx（至 `02DD`） | 续用 | 信息 **`01CD`**；故障 **`02DE`** |
| `16#0005_`（Process） | 信息 01xx（至 `01D5`）、故障 02xx/03xx（至 `0304`） | 续用 | 信息 **`01D6`**；故障 **`0305`** |

**两条新纪律（拟入册 R65 / R66，见 §8）**：

- **R65｜段内信息级耗尽即开新子带，禁止回填他人预留孔洞**。`0001_` 段 `0245~028D` 那 63 个碎片洞属既有件「预留禁用（不得挪用）」域，回填等于挪用他人预留，后续审计无法区分「谁真正占用」。
- **不做**「把 R15~R17 的 02xx 码整体迁到 04xx」的存量改判——那是 R18 已做过的改判专项，再迁一次会把 304 件的码位账本搅乱，收益为零。

> 校验脚本：`_Staging_Raw/2026-11-16/_verify_r19.py`（本轮 100 个候选码位 **CLASH 全为空**；20 个新名称与 registry 304 名 + 304 个文件名交集为空）。实跑输出见 §7。

---

## 1 R19 20 目标一览（锁定）

| # | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批 |
|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_DintMsToTod` | DL_MathData | FC_DL_ | DINT 当日毫秒 → TOD（钳 0~86 399 999 ms，与 `TodToDintMs` 构成双向对） | T0-5 补位（ROADMAP §22.2 P0） | L | 1 |
| 2 | `FC_DL_TimeRatioCalc` | DL_MathData | FC_DL_ | 两个 TIME 之比 → LREAL 比值/百分比（除子零闸 + 比值饱和） | T0-2 补位（ROADMAP §22.2 P0） | M | 1 |
| 3 | `FC_DL_RatioToPwrDb` | DL_MathData | FC_DL_ | 功率比值 → dB（10·log10），与 `PwrDbToRatio` 构成双向对 | T0-4 补位（ROADMAP §22.2 P0） | M | 1 |
| 4 | `FC_DL_LintToUdintSat` | DL_MathData | FC_DL_ | LINT → UDINT 双向饱和（负值饱和到 0，超顶饱和到 4 294 967 295） | T0-5 补位（ROADMAP §22.2 P1） | M | 1 |
| 5 | `FB_DL_BitShiftRegister` | DL_Base | FB_DL_ | 宽度可组态的位串移位寄存器（输送线工件跟踪：每工位一脉冲移一位） | T2-1 LGF Bit Logic 位串批量扩族 | M | 1 |
| 6 | `FC_DL_ModbusRtuFrameCheck` | DL_MathData | FC_DL_ | Modbus RTU 帧一致性校验（长度/功能码/字节数域/异常帧四路互校，不重算 CRC） | T1-3 OSCAT Network 明列「RTU 帧长度校验」收口 | H | 2 |
| 7 | `FB_DL_FlowSqrtExtract` | DL_Algo | FB_DL_ | 差压流量开方 + 小信号切除（迟滞）+ 一阶阻尼 + 满量程标定 | ROADMAP §16.6 P1 `FB_DL_FlowSqrtExtract` 勾选 | M | 2 |
| 8 | `FB_DL_RatioController` | DL_Algo | FB_DL_ | 比值控制站（从动给定 = 主动×比率+偏置，主动低限保护 + 斜率限制） | 自研（过程控制通用律）+ T2-5 参数域次源 | H | 2 |
| 9 | `FB_DL_LeadLagCompensator` | DL_Algo | FB_DL_ | 一阶超前滞后相位校正（Tustin 离散，在线改参保状态，输出限幅） | 自研（公开控制工程判据）+ T1-1 控制器族次源 | H | 2 |
| 10 | `FB_DL_AutoTuneRelay` | DL_Algo | FB_DL_ | 继电反馈自整定（测 Tu/a → Ku → Z-N / Åström-Hägglund 出 Kp/Ti/Td） | 公开学术判据（Åström-Hägglund 1984）+ WebSearch 1 次核对 | H | 2 |
| 11 | `FB_DL_DeviceHealthArbiter` | DL_Device | FB_DL_ | NE107 多源健康聚合仲裁（最高级 + 首出通道 + 分级位图，Unknown 不遮蔽） | T2-8 矩阵明列「NE107 实现块仲裁件待挖」 | M | 3 |
| 12 | `FB_DL_ProfinetAlarmDiag` | DL_Device | FB_DL_ | PROFINET 通道诊断聚合（首出通道 + 八类分类计数 + 维护类单列 + NE107 出口） | T1-7 矩阵明列「PN_ALARM_DIAG 语义族待挖」+ WebSearch 1 次 | H | 3 |
| 13 | `FB_DL_EscChuckCurrentMonitor` | DL_Device | FB_DL_ | ESC 静电吸附电流监视（建立/稳态/释放三段 + 失吸/打火双判据） | 半导体 ESC 自研线明列待挖（clean-room） | H | 3 |
| 14 | `FB_DL_DeviceParamWrite` | DL_Device | FB_DL_ | 设备参数写回（备份 → 白名单写 → 读回复核 → 失败回滚） | T1-4 CODESYS Forge `DeviceReader` 族下半段（M-E3 判定为设备层） | H | 3 |
| 15 | `FB_DL_ExternalEncoderScaler` | DL_Motion | FB_DL_ | 外部编码器折算（分辨率/传动比/导程 → 工程量，含计数回绕展开） | T2-4 矩阵明列「外部编码器族待挖」 | M | 3 |
| 16 | `FB_DL_CamPhaseTrim` | DL_Motion | FB_DL_ | 凸轮相位在线修调（限速率渐进 + 限幅 + 标记沿一次性补偿） | T1-6 矩阵明列「凸轮动态修调待挖」 | M | 4 |
| 17 | `FB_DL_FilmWebCenter` | DL_Motion | FB_DL_ | 膜卷纠偏 EPC（偏差 → 纠偏辊给定，死区/限速/断料保持/行程限幅） | ROADMAP §10.4 P1 `FB_DL_FilmWebCenter` 勾选 | M | 4 |
| 18 | `FB_DL_WindingLayerCounter` | DL_Motion | FB_DL_ | 卷绕层数计数（卷径递推 + 圈计数交叉校核，饱和与不一致提示） | ROADMAP §15.1 P1 `FB_DL_WindingLayerCounter` 勾选 | M | 4 |
| 19 | `FB_DL_DrumLevelThreeElem` | DL_Process | FB_DL_ | 汽包水位三冲量轻量版（水位偏差 + 蒸汽前馈 − 给水反馈 → 给水给定） | ROADMAP §10.6 P1 `FB_DL_DrumLevelThreeElem` 勾选 | H | 4 |
| 20 | `FB_DL_VacCupRingCtrl` | DL_Process | FB_DL_ | 多吸盘组分档拾放（逐通道吸附确认 + 分组释放 + 少吸降级判据） | ROADMAP §10.4 P1 `FB_DL_VacCupRingCtrl` 勾选 | H | 4 |

**分布**：DL_Base 1（#5）｜ DL_MathData 5（#1-4、#6）｜ DL_Algo 4（#7-10）｜ DL_Device 4（#11-14）｜ DL_Motion 4（#15-18）｜ DL_Process 2（#19-20）= **20**
**类型**：FB **15** ｜ FC **5**
**复杂度**：H **9** ｜ M **10** ｜ L **1**
**凑数审查**：20 件逐件附「独立防御点」于 §3，无一件是纯类型重载；`FC_DL_LintToUdintSat` 曾被列为 P1，本轮立项理由 = 负值饱和方向与正向饱和方向是两个独立闸门（与 `LintToDintSat` 只有正向饱和不同），并新增「无损要求下饱和即故障」模式（`bRequireLossless`）。

## 2 四批划分（每批 5 件，按域内聚 + 依赖方向从低到高）

| 批 | 主题 | 件 | 码段 |
|---|---|---|---|
| 批 1 | **Level 0 T0 补位组 + 位串扩族** | #1-5 | `0001_0400~0409` / `0001_031E~032C` |
| 批 2 | **协议校验收口 → Level 1 控制律（Algo）** | #6-10 | `0001_040A~040B` / `0001_032D~032F` + `0002_27xx~2Axx` |
| 批 3 | **Level 1 设备健康/诊断抽象 → 运动折算** | #11-15 | `0003_016A~0171` / `0003_0330~033B` + `0004_01CD~01CE` / `0004_02DE~02E0` |
| 批 4 | **Level 1 运动补偿/计数 → Level 2 工艺模板** | #16-20 | `0004_01CF~01D4` / `0004_02E1~02E9` + `0005_01D6~01D9` / `0005_0305~030A` |

---

## 3 批次需求规格（引脚级，可直接编码）

> 规格约定（**全批强制，逐件不再重复**）：
> - 所有 `REAL`/`LREAL` 物理量在注释中带**单位**与**取值域**；阈值/限幅/超时**禁止裸数值**，一律 `VAR CONSTANT` 或输入引脚。
> - `TON`/`TOF`/`TP`/`R_TRIG`/`F_TRIG` **在 `CASE` 之前无条件刷新**（红线 4/5，R1 规则）。本批含定时器/边沿件：#5 #8 #10 #13 #14 #19 #20，评审必查。
> - 浮点判等一律 `ABS(a-b) < DL_FLOAT_EPS`；除法一律前置防零；数组一律先判界后索引；循环一律 `FOR` + 定长上界，**禁 `WHILE`**（本批无一件需要 `WHILE`）。
> - 纯函数无顺序状态机时，头注释 `状态机` 段固定写 `R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现`。
> - 每件 5 槽码位：**2 信息级（1 用 1 预留）+ 3 故障级（1~3 用，余下预留）**；预留槽在头注释写 `预留禁用（不得挪用）`，**实现体内不得出现该码赋值**。
> - 接口/枚举唯一属主纪律：`E_DL_Ne107Status` 由 `I_DL_DeviceHealth` 唯一属主（R13），#11 #12 #13 只引用不重声明。

### 3.1 批 1（Level 0：T0 补位组 + 位串扩族）

---

#### #1 `FC_DL_DintMsToTod` —— DINT 当日毫秒 → TOD

- **分类**：DL_MathData / Convert ｜ **前缀**：`FC_DL_` ｜ **类型**：FUNCTION → `TOD` ｜ **复杂度**：L
- **功能**：把「自当日 00:00 起的毫秒数」还原成 `TOD`，是 `FC_DL_TodToDintMs` 的严格逆运算。现场语义：MES 下发的「班次累计毫秒」「配方段起始偏移」要变成 `TOD` 才能进定时器/排程件比较。**委托内建 `DINT_TO_TOD`，不重实现时基换算**（T0 判据 2）。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `nMsOfDay` | DINT | 0 | ms | 当日毫秒，有效域 0~86 399 999；可接受域 -86 400 000~172 799 999（含跨日一圈） |
| `bClampSilently` | BOOL | TRUE | — | TRUE = 越界钳位并只置信息码；FALSE = 越界置故障级并置 `bValid := FALSE` |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `eErr` | UDINT | — | 错误码，0 = 正常 |
| `bError` | BOOL | — | 故障标志 |
| `bValid` | BOOL | — | 返回值可用 |
| `bClamped` | BOOL | — | 本拍发生钳位 |

- **VAR CONSTANT**：`DL_TOD_MS_MAX : DINT := 86399999`（当日最大毫秒，= 24 h − 1 ms）｜`DL_TOD_MS_MIN_EXT : DINT := -86400000`（可接受下界，跨日回退一圈）｜`DL_TOD_MS_MAX_EXT : DINT := 172799999`（可接受上界，跨日超前一圈）
- **边界安全条件**：① 负值（上一日回退）按「日模」折回当日：`WHILE` **禁用**，用单算式 `nMs := nMs + 86400000 * (1 - (nMs / 86400000))` —— 本件改为**先判后算**：`IF nMs < 0 THEN nMs := nMs + DL_TOD_DAY_MS * (1 - nMs / DL_TOD_DAY_MS)` 仅在 `|nMs| < 86400000` 时成立，超出一圈直接判故障级 031F；② 一轮内合法输入不进钳位分支；③ 钳位在 0 / `DL_TOD_MS_MAX` 两端，**永不对非法值直接调内建**；④ 无状态机（纯函数，R6 N/A 句式）。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0001_0400` | 信息 | 输入越当日域已被钳位到 0 或 86 399 999 ms（`bClamped := TRUE`） |
| `16#0001_0401` | 信息 | **预留禁用（不得挪用）** |
| `16#0001_031E` | 故障 | 输入超可接受域（< −86 400 000 或 > 172 799 999 ms），返回 `T#0S`、`bValid := FALSE` |
| `16#0001_031F` | 故障 | 调用方要求不静默（`bClampSilently = FALSE`）且发生钳位，返回钳位值但 `bValid := FALSE` |
| `16#0001_0320` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T0-5 类型转换补位（ROADMAP §22.2 P0 承诺件）；语义由 IEC 61131-3 `TOD` 定义，实现委托内建 `DINT_TO_TOD`，零检索、零外部源

---

#### #2 `FC_DL_TimeRatioCalc` —— TIME 比值计算

- **分类**：DL_MathData / Convert ｜ **前缀**：`FC_DL_` ｜ **类型**：FUNCTION → `LREAL`（比值）｜ **复杂度**：M
- **功能**：算 `tA / tB` 的**无量纲比值**（可选 ×100 出百分比）。节拍分析、稼动率、循环时间偏差、加速比全都要这个数，但库内 `FC_DL_TimeDivChk` 只出 `TIME`（整数毫秒商，小数全丢）。本件用 `LREAL` 承载，保留 15 位有效数字。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `tNumerator` | TIME | T#0S | ms | 分子时长，域 −24 h~+24 h（TIME 平台实现为 DINT ms，可带符号） |
| `tDenominator` | TIME | T#1S | ms | 分母时长，域 −24 h~+24 h，**模长必须 ≥ 1 ms** |
| `bAsPercent` | BOOL | FALSE | — | TRUE = 结果 ×100（%） |
| `fRatioSpan` | LREAL | 1.0E6 | — | 比值饱和上限（模长），域 1.0~1.0E12 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |
| `bValid` | BOOL | — | 返回值可用 |
| `fRatioAbs` | LREAL | [无量纲] | 比值绝对值（便于 HMI 只看量级） |
| `bSaturated` | BOOL | — | 比值已饱和到 `fRatioSpan` |

- **VAR CONSTANT**：`DL_FLOAT_EPS : REAL := 1.0E-6`｜`DL_TR_MIN_DEN_MS : DINT := 1`（分母模长下限 [ms]）
- **边界安全条件**：① `tDenominator` 毫秒值为 0 → 故障 0321，返回 0.0、`bValid := FALSE`（**除零唯一出口**）；② 分母模长 < 1 ms → 视为过小，比值饱和到 `fRatioSpan` + 信息 0402（1 ms 以下的分母在任何现场都无意义，且会让比值爆炸）；③ 分子/分母为负（TIME 平台差异，R55 教训）→ **按模长参与运算** + 信息 0402，方向差异写进头注释；④ 比值模长 > `fRatioSpan` → 钳位 + 信息 0403；⑤ 中间量一律 `LREAL`（`TIME_TO_LREAL` 显式换算，禁隐式）；⑥ 结果非有限 → 0322；⑦ 无状态机（R6 N/A 句式）。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0001_0402` | 信息 | 分母模长 < 1 ms 或输入为负，已按模长运算/饱和 |
| `16#0001_0403` | 信息 | 比值超 `fRatioSpan` 已钳位（`bSaturated := TRUE`） |
| `16#0001_0321` | 故障 | 分母为 0（除零），返回 0.0 |
| `16#0001_0322` | 故障 | 结果非有限（NaN/±INF） |
| `16#0001_0323` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T0-2 定时器变体补位（ROADMAP §22.2 P0 承诺件）；语义为公开算术定义，零检索

---

#### #3 `FC_DL_RatioToPwrDb` —— 功率比值 → dB

- **分类**：DL_MathData / Convert ｜ **前缀**：`FC_DL_` ｜ **类型**：FUNCTION → `LREAL`（dB）｜ **复杂度**：M
- **功能**：`dB = 10·log10(P1/P2)`，功率型（10 因子）反向件。R17 落了幅值型反向 `FC_DL_RatioToAmpDb`（20 因子）与功率型正向 `FC_DL_PwrDbToRatio`，**功率型反向缺位**——射频电源、加热功率、光伏组串失配损耗都要「查表得比值 → 报 dB」。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `fP1` | LREAL | 1.0 | W | 分子功率，域 0.0~1.0E30（0 合法，得 −∞ 语义 → 走下限） |
| `fP2` | LREAL | 1.0 | W | 分母功率（参考功率），**必须 > 0** |
| `fDbSpan` | LREAL | 380.0 | dB | dB 绝对值上限，域 1.0~1000.0（380 dB 由 LREAL 可表性反算，R17 同口径） |
| `fDbFloor` | LREAL | -380.0 | dB | `fP1 = 0` 时的下限替代值，域 −1000.0~0.0 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |
| `bValid` | BOOL | — | 返回值可用 |
| `bSaturated` | BOOL | — | 结果被钳位 |
| `bZeroPower` | BOOL | — | `fP1 = 0`（真 −∞，已按 `fDbFloor` 输出） |

- **VAR CONSTANT**：`DL_DB_PWR_FACTOR : LREAL := 10.0`（功率型因子）｜`DL_LOG_BASE10 : LREAL := 10.0`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `fP2 <= 0` → 故障 0324，返回 0.0（**分母非正是本件的首要闸**）；② `fP1 < 0` → 故障 0324（负功率表示方向而非幅值，比值语义失效）；③ `fP1 = 0`（用 `ABS(fP1) <= EPS`）→ 直接输出 `fDbFloor` + 信息 0404 + `bZeroPower := TRUE`（**不取对数**，定义域闸优于事后判 −∞）；④ 结果超 `±fDbSpan` → 钳位 + 信息 0405；⑤ 对数一律委托内建 `LOG`（底 e）后换底 `LN(x)/LN(10)`，**禁重实现多项式**（T0 判据 2）；⑥ 非有限输入 → 0325；⑦ 无状态机（R6 N/A 句式）。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0001_0404` | 信息 | `fP1 = 0`，已按 `fDbFloor` 输出（真 −∞ 的工程替代） |
| `16#0001_0405` | 信息 | 结果超 `±fDbSpan` 已钳位（`bSaturated := TRUE`） |
| `16#0001_0324` | 故障 | 功率非法（`fP2 <= 0` 或 `fP1 < 0`） |
| `16#0001_0325` | 故障 | 输入或中间结果非有限（NaN/±INF） |
| `16#0001_0326` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T0-4 数学变体补位（ROADMAP §22.2 P0 承诺件）；dB 定义为公开工程约定，实现委托内建 `LOG`，零检索

---

#### #4 `FC_DL_LintToUdintSat` —— LINT → UDINT 双向饱和

- **分类**：DL_MathData / Convert ｜ **前缀**：`FC_DL_` ｜ **类型**：FUNCTION → `UDINT` ｜ **复杂度**：M
- **功能**：LINT（64 位有符号）→ UDINT（32 位无符号）的**双向**饱和：负值饱和到 0，超顶饱和到 4 294 967 295。R17 的 `LintToDintSat` 只有「正向饱和」一个闸，本件补的是「**负值落到无符号域**」这一独立方向——两向饱和的判据、出口与业务语义完全不同（负计数一律是组态错，超顶才是量程溢出）。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `liIn` | LINT | 0 | [无量纲] | 输入，全域 −2^63~2^63−1 |
| `bRequireLossless` | BOOL | FALSE | — | TRUE = 发生任何饱和即判故障（计量/累计值场景不容许静默截断） |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |
| `bValid` | BOOL | — | 返回值可用（饱和且 `bRequireLossless` 时 FALSE） |
| `bSatLow` | BOOL | — | 负向饱和发生（输入 < 0） |
| `bSatHigh` | BOOL | — | 正向饱和发生（输入 > 4 294 967 295） |

- **VAR CONSTANT**：`DL_UDINT_MAX_AS_LINT : LINT := 4294967295`（UDINT 上限的 LINT 形态）｜`DL_LINT_ZERO : LINT := 0`
- **边界安全条件**：① `liIn < 0` → 返回 0、`bSatLow := TRUE` + 信息 0406；② `liIn > DL_UDINT_MAX_AS_LINT` → 返回 `16#FFFF_FFFF`、`bSatHigh := TRUE` + 信息 0407；③ **域内才调内建 `LINT_TO_UDINT`**——域外调用是三平台回绕行为不一致的根源（R56「无符号双分支钳位」同纪律）；④ 比较用 `LINT` 字面量常量，**不把 `UDINT` 上限直接写成 UDINT 再比**（会隐式升位，跨平台风险）；⑤ `bRequireLossless AND (bSatLow OR bSatHigh)` → 0327；⑥ 无状态机（R6 N/A 句式）。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0001_0406` | 信息 | 负向饱和（输入 < 0 → 0），组态错但已安全兜底 |
| `16#0001_0407` | 信息 | 正向饱和（输入 > 4 294 967 295 → 上限） |
| `16#0001_0327` | 故障 | 调用方要求无损（`bRequireLossless = TRUE`）却发生饱和 |
| `16#0001_0328` | 故障 | **预留禁用（不得挪用）** |
| `16#0001_0329` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T0-5 类型转换补位（ROADMAP §22.2 P1 承诺件）；语义由 IEC 61131-3 类型定义，域内委托内建，零检索；**立项理由已过「纯重载」审查**：双向饱和为两个独立闸门，且新增 `bRequireLossless` 模式

---

#### #5 `FB_DL_BitShiftRegister` —— 宽度可组态的位串移位寄存器

- **分类**：DL_Base / Bit string ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **功能**：一个移位脉冲把 `bShiftIn` 从一端移入，另一端溢出为 `bShiftOut`。现场语义：输送线上「哪个工位有料」的经典做法——每个工位到位脉冲移一位，末端溢出的位就是「出料口有料」。库内 `BitArrayRotate` 是**循环**旋转（不丢位），`BitSegmentBlockMove` 是**段搬运**，都不提供「逐拍移位 + 溢出位」语义。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 冻结寄存器并清输出脉冲 |
| `bReset` | BOOL | — | — | 上升沿把寄存器与计数清零 |
| `bShift` | BOOL | — | — | 移位请求（**上升沿有效**，一拍只移一位） |
| `bShiftIn` | BOOL | FALSE | — | 移入位（TRUE = 置位） |
| `uWidth` | UINT | 16 | bit | 有效位宽，域 1~32；超 32 无法用 DWORD 承载 |
| `bClearAll` | BOOL | FALSE | — | TRUE = 整寄存器清零（**优先于 `bShift`**，同拍清空） |
| `bDirLeft` | BOOL | TRUE | — | TRUE = 向高位方向移（bit0 → bit(n-1)），FALSE = 反向 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `uReg` | DWORD | — | 寄存器镜像（bit0 = 最旧位） |
| `bShiftOut` | BOOL | — | 本拍溢出位（单周期脉冲） |
| `bAnySet` | BOOL | — | 任一位为 1 |
| `uSetCount` | UINT | 个 | 置位总数（复用 `FC_DL_BitCount` 语义，本件内联 8 行循环，不跨层调用纯函数） |
| `uShiftCnt` | UDINT | 次 | 累计移位次数（饱和） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR CONSTANT**：`DL_SR_WIDTH_MIN : UINT := 1`｜`DL_SR_WIDTH_MAX : UINT := 32`｜`DL_SR_CNT_MAX : UDINT := 16#FFFF_FFFE`（计数饱和值）｜`DL_SR_MASK32 : DWORD := 16#FFFF_FFFF`
- **VAR**：`fbTrigShift : R_TRIG`｜`fbTrigReset : R_TRIG`｜`uWidthEff : UINT`｜`uMask : DWORD`｜`bOutBit : BOOL`
- **边界安全条件**：① `uWidth = 0 OR uWidth > 32` → 032A，寄存器清零、`bShiftOut := FALSE`、**不索引任何位**；② 宽度掩码 `uMask := SHL(1, uWidthEff) - 1`，但 `uWidthEff = 32` 时必须走常量 `DL_SR_MASK32`（**禁 `SHL(x, 32)`**，R48/R10 纪律）；③ 溢出位取 `uReg AND SHL(1, uWidthEff-1)`，`uWidthEff = 32` 时用 `16#8000_0000` 常量；④ 移位后 `uReg := uReg AND uMask`（**截断到有效宽度**，否则旧位会残留在高位造成假置位——这是本件最易漏的缺陷）；⑤ `bClearAll` 与 `bShift` 同拍 → 清空优先 + 信息 0408（安全侧：宁可丢一位不可留脏位）；⑥ `R_TRIG` 周期首部无条件刷新；⑦ 无 `CASE`：`bShiftOut` 是单周期脉冲量、`uReg` 是保持量，非法状态不可能出现，头注释按 R6 句式写「无顺序状态机」；⑧ `uShiftCnt` 饱和时置 032B（计数饱和不是致命故障，但 HMI 需知道统计已不可信）。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0001_0408` | 信息 | 同拍 `bClearAll` 与 `bShift`，已按清空优先；或 `bDirLeft` 方向变更已重排 |
| `16#0001_0409` | 信息 | **预留禁用（不得挪用）** |
| `16#0001_032A` | 故障 | 位宽非法（`uWidth` 不在 1~32），寄存器清零 |
| `16#0001_032B` | 故障 | 移位计数达饱和值，统计量已不可信（寄存器本体仍正常工作） |
| `16#0001_032C` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T2-1 LGF · Bit Logic（矩阵 §5 本行「组内三层：单点 / 单段 / 批量段」已齐备，本件补**时序层**：位串随节拍推进；只借「位串批量操作归 Bit Logic 组」的分类事实，掩码/截断/清空优先序/码位 100% 自有）；T0-7 位串移位闸门纪律复用（R48）

---

### 3.2 批 2（Level 0 协议校验收口 → Level 1 控制律）

---

#### #6 `FC_DL_ModbusRtuFrameCheck` —— Modbus RTU 帧一致性校验

- **分类**：DL_MathData / Protocol ｜ **前缀**：`FC_DL_` ｜ **类型**：FUNCTION → `BOOL`（TRUE = 帧结构自洽）｜ **复杂度**：H
- **功能**：对已收到的 RTU 帧做**结构一致性**校验，**不重算 CRC**（CRC 已有 `FC_DL_Crc16Modbus`）。四路互校：① 总长与功能码声明是否匹配；② 字节数域与调用方声明的数量 `uQty` 是否自洽；③ 异常帧（功能码 bit7 = 1）长度必须恰为 5；④ 广播地址 0 只对写类功能码合法。矩阵 §5 T1-3 明列「RTU 帧长度 / 字节数一致性校验」待挖——这是把「解析异常帧」（R12 已收口）补成「**先验帧，再解帧**」的完整链路。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `auFrame` | ARRAY[0..255] OF BYTE | — | — | 帧缓冲区（定长 256，超长由 `uLen` 截断） |
| `uLen` | UINT | 0 | 字节 | 实际收到长度，域 0~256 |
| `eFc` | `E_DL_ModbusFc` | `eFcUnknown` | — | 调用方读到的功能码（低 7 位语义，异常位由本件处理） |
| `uQty` | UINT | 0 | 个/位 | 调用方声明的寄存器数（03/04/01/02）或写入数量（0F/10），域 0~125 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |
| `bValid` | BOOL | — | 校验结论可信（故障态 FALSE，结论无意义） |
| `uByteCount` | UINT | 字节 | 从帧内解析出的字节数域（无字节数域的功能码回 0） |
| `bIsException` | BOOL | — | 该帧是异常应答帧 |
| `bBroadcast` | BOOL | — | 地址域为 0（广播） |

- **枚举（同文件定义，本文件为唯一属主）**：`E_DL_ModbusFc : ( eFcUnknown, eFc01, eFc02, eFc03, eFc04, eFc05, eFc06, eFc0F, eFc10 )`——**只覆盖本件能判长度的 8 个功能码**，其余（08 诊断、0B 等）一律 `eFcUnknown` 交给上层，本件不猜
- **VAR CONSTANT**：`DL_RTU_MIN_LEN : UINT := 4`（最短帧：地址 + 功能码 + CRC×2）｜`DL_RTU_MAX_LEN : UINT := 256`（协议上限）｜`DL_RTU_EXC_LEN : UINT := 5`（异常帧定长）｜`DL_RTU_FC_EXC_BIT : BYTE := 16#80`｜`DL_RTU_ADDR_BROADCAST : BYTE := 16#00`
- **VAR**：`uQtyCalc : UINT`｜`bWriteFc : BOOL`
- **边界安全条件**：① `uLen < DL_RTU_MIN_LEN OR uLen > DL_RTU_MAX_LEN` → 032D（**先判长度再索引数组**，绝不越界）；② 异常帧分支：`(功能码 AND 16#80) <> 0` → `bIsException := TRUE`，要求 `uLen = 5`，否则 032F，**并直接返回 TRUE/ FALSE 结论不再做字节数互校**（异常帧没有字节数域）；③ 正常帧互校表（**公开协议条款，非厂商私有**）：`03/04` → `uLen = 5 + 2·uQty`；`01/02` → `uLen = 5 + ⌈uQty/8⌉`（用 `(uQty+7)/8` 整数式，**禁浮点**）；`05/06` → `uLen = 8`（**`uQty` 必须为 1**）；`0F/10` → `uLen = 9 + …`（请求帧含字节数域，本件只校验 `uLen ≥ 9` 且字节数域 = 与 `uQty` 匹配的值）；不一致 → 032E；④ `eFc = eFcUnknown` → 只做长度域检查，返回 TRUE 并置信息 040A（未知功能码不阻断上层解析）；⑤ 地址 0 → `bBroadcast := TRUE`，若功能码是读类（01/02/03/04）→ 040B（**广播读在协议上无意义**，几乎肯定是站号配错；只提示不报故障，因为有些网关会这样转发）；⑥ `CASE eFc ... ELSE` 兜底走 `eFcUnknown` 分支（**红线 4：枚举必须有 ELSE**）；⑦ 无状态机（R6 N/A 句式）。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0001_040A` | 信息 | 功能码未纳入长度校验表（`eFcUnknown`），只做长度域检查 |
| `16#0001_040B` | 信息 | 广播地址配读类功能码（疑似站号组态错，已放行） |
| `16#0001_032D` | 故障 | 帧长非法（< 4 或 > 256 字节），不索引缓冲区 |
| `16#0001_032E` | 故障 | 字节数域 / 帧长与声明的数量 `uQty` 不自洽 |
| `16#0001_032F` | 故障 | 异常帧（bit7 置位）长度不等于 5 |

- **来源标签**：T1-3 OSCAT Network（只借「协议帧解析 / 校验在库里独立成族」的分类事实，矩阵 §5 明列本项为待挖）；校验规则全部取自 **Modbus 应用协议规范公开条款**（RTU 帧结构、功能码、异常应答、广播语义），本件不引用任何实现代码；判定表组织、错误分级、枚举范围 100% 自有。**零新增检索**（R12 `ModbusExceptionParse` 台账已覆盖功能码语义）

---

#### #7 `FB_DL_FlowSqrtExtract` —— 差压流量开方 + 小信号切除

- **分类**：DL_Algo / Process control ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **功能**：差压式流量计的标准处理链：**开方 → 小信号切除（带迟滞）→ 一阶阻尼 → 满量程标定**。现场痛点：孔板流量在 5% 以下差压时开方后噪声被放大 4~5 倍，HMI 上流量在零附近乱跳，操作工据此判断「有没有流量」必然误判；切除点做硬切又会在切点附近反复跳。本件把「迟滞切除」做进块内。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 输出 0 并冻结阻尼状态 |
| `bReset` | BOOL | — | — | 上升沿清阻尼状态与切除锁存 |
| `fDp` | REAL | 0.0 | 用户单位（Pa 或 %） | 差压输入，域 −10.0~110.0（允许轻微负漂移） |
| `fDpSpan` | REAL | 100.0 | 同 `fDp` | 差压满量程（对应流量满量程），**必须 > 0** |
| `fFlowSpan` | REAL | 100.0 | m³/h | 流量满量程，域 > 0 |
| `fCutPercent` | REAL | 1.0 | % | 切除点（差压满量程百分比），域 0.0~20.0；0 = 不切除 |
| `fCutHystPercent` | REAL | 0.3 | % | 切除迟滞带宽度（相对满量程），域 0.0~10.0 |
| `fDampCoef` | REAL | 0.2 | — | 一阶阻尼系数 α，域 0.0~1.0（0 = 不阻尼，1 = 冻结） |
| `tSampleTime` | TIME | T#100MS | ms | 采样周期，域 1~10 000 ms |
| `bSquareRoot` | BOOL | TRUE | — | TRUE = 开方（差压型）；FALSE = 线性（已开方变送器，只做阻尼与切除） |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `fFlow` | REAL | m³/h | 输出流量，域 0.0~`fFlowSpan` |
| `bCutoff` | BOOL | — | 当前处于切除区（输出被强制 0） |
| `bSaturated` | BOOL | — | 输出被满量程钳位 |
| `uCutCount` | UDINT | 次 | 切除进入次数（抖动监视） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |
| `bValid` | BOOL | — | 输出可用 |

- **VAR CONSTANT**：`DL_FSQ_CUT_MAX : REAL := 20.0`（切除点上限 [%]）｜`DL_FSQ_HYST_MAX : REAL := 10.0`｜`DL_FSQ_DAMP_MAX : REAL := 1.0`｜`DL_FSQ_DT_MAX : TIME := T#10S`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **VAR**：`bCutLatch : BOOL`｜`fDamped : REAL`｜`fRatio : REAL`｜`fRaw : REAL`｜`fPrevDp : REAL`
- **边界安全条件**：① `fDpSpan <= EPS` 或 `fFlowSpan <= EPS` → 故障 2710，输出 0、`bValid := FALSE`；② 切除点 ≥ 满量程（`fCutPercent >= 100.0`）或 `fCutPercent > DL_FSQ_CUT_MAX` → 钳位 + 信息 2701（切除点吃掉整个量程等于把表废掉）；③ `fDp < 0` → 取 0 参与运算 + 信息 2701（差压变送器零点负漂是常态，直接开方会出现 NaN）；④ **迟滞切除**：`fDpPercent >= fCutPercent` 时退出切除、`< fCutPercent - fCutHystPercent` 时进入切除，带内保持上一状态——这是本件的核心防御，也是与「硬切」的语义分界；⑤ 开方委托内建 `SQRT`（**禁牛顿迭代重实现**，T0 判据 2），入参已由 ③ 保证非负；⑥ 阻尼 `fDamped := fDamped + α·(fRaw − fDamped)`，`α = 1.0` 时等价冻结、`α = 0.0` 直通；⑦ `tSampleTime` 越域 → 故障 2710（阻尼系数 α 隐含依赖采样周期，周期未知则阻尼律不可信，头注释写明）；⑧ 输出 `MIN(MAX(fFlow, 0.0), fFlowSpan)` **双侧**钳位，超顶置 `bSaturated`；⑨ 非有限输入 → 故障 2711，保持末次有效输出（**不输出 0**——零流量与信号故障在联锁上是两个结论）；⑩ 无 `CASE` 状态机（纯组合 + 单比特锁存），头注释按 R6 句式写。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0002_2701` | 信息 | 切除点超域已钳位 / 差压负漂已取 0 / 切除迟滞带保持中 |
| `16#0002_2702` | 信息 | **预留禁用（不得挪用）** |
| `16#0002_2710` | 故障 | 量程或采样周期参数非法，输出 0 |
| `16#0002_2711` | 故障 | 差压输入非有限，保持末次有效输出 |
| `16#0002_2712` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：ROADMAP §16.6 P1 `FB_DL_FlowSqrtExtract`（勾选收口）；开方与切除为公开仪表工程惯例（差压流量测量通用判据），**迟滞切除、阻尼律、码位 100% 自有**；T1-1 OSCAT Basic 信号处理族次源（只借「阻尼与限幅同层」组织，零代码行）

---

#### #8 `FB_DL_RatioController` —— 比值控制站

- **分类**：DL_Algo / Process control ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：H
- **功能**：从动流量给定 = 主动流量 × 比率 + 偏置。**本件不算 PID**（环路闭合归 `FB_DL_PidController`，职责边界写进头注释）。核心防御是「主动流量低限保护」：主动流量接近 0 时按比例算出的从动给定也趋 0，操作工看到的是「两个流量都归零」，而真正的故障源（主动侧断料）被掩盖——本件在低限以下直接切到安全给定并置位 `bMasterLow`。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 输出限幅下限 |
| `bReset` | BOOL | — | — | 上升沿清限幅锁存与斜率状态 |
| `fMasterFlow` | REAL | 0.0 | m³/h | 主动流量（测量值） |
| `fRatio` | REAL | 1.0 | [无量纲] | 比率，域 `fRatioMin`~`fRatioMax` |
| `fRatioMin` | REAL | 0.01 | [无量纲] | 比率下限，**必须 > 0**（比率 0 等于关闭从动侧，应走停机逻辑而非比值站） |
| `fRatioMax` | REAL | 10.0 | [无量纲] | 比率上限 |
| `fBias` | REAL | 0.0 | m³/h | 偏置量 |
| `fMasterLowLimit` | REAL | 1.0 | m³/h | 主动流量低限，域 0.0~`fMasterFlow` 量级 |
| `fMasterLowSp` | REAL | 0.0 | m³/h | 低限以下的安全给定 |
| `fOutMin` | REAL | 0.0 | m³/h | 输出下限 |
| `fOutMax` | REAL | 100.0 | m³/h | 输出上限 |
| `fRateMax` | REAL | 50.0 | m³/h/s | 输出最大变化率，域 0.001~1.0E6 |
| `tSampleTime` | TIME | T#100MS | ms | 采样周期，域 1~10 000 ms |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `fSlaveSp` | REAL | m³/h | 从动侧给定 |
| `bMasterLow` | BOOL | — | 主动流量低于低限，给定已切到安全值 |
| `bRatioClamped` | BOOL | — | 比率被限幅 |
| `bOutClamped` | BOOL | — | 输出被上下限或斜率限制 |
| `fEffectiveRatio` | REAL | [无量纲] | 实际生效比率（含限幅） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |
| `bValid` | BOOL | — | 给定可用 |

- **VAR**：`eState : E_DL_RatioState`（同文件枚举 `eIdle`/`eRunning`/`eMasterLow`/`eFault`）｜`fLastSp : REAL`｜`fStep : REAL`｜`fDtSec : REAL`｜`fRatioEff : REAL`｜`fbTrigReset : R_TRIG`
- **VAR CONSTANT**：`DL_RTO_RATIO_EPS : REAL := 1.0E-6`｜`DL_RTO_RATE_MIN : REAL := 0.001`｜`DL_RTO_RATE_MAX : REAL := 1.0E6`｜`DL_RTO_DT_MAX : TIME := T#10S`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `fRatioMin <= EPS` 或 `fRatioMax <= fRatioMin` → 故障 2811（限值区间自相矛盾，比率域不存在）；② `fOutMax <= fOutMin` → 故障 2811；③ `fRatio` 越 `[fRatioMin, fRatioMax]` → 钳位 + 信息 2801 + `bRatioClamped := TRUE`（比率超出工艺窗是常见的「待调整」，不是故障）；④ `fMasterFlow < fMasterLowLimit` → `fSlaveSp := fMasterLowSp`、`bMasterLow := TRUE` + 信息 2801，**不按比例算**（这是本件的核心语义）；⑤ 斜率限制 `fStep := fRateMax · dt`，`dt <= 0`（首拍）时 `fStep := 0.0`，**不用 0 除**；`fRateMax` 越域 → 故障 2810；⑥ 输出双侧钳位 `MIN(MAX(x, fOutMin), fOutMax)`（只做单侧是常见缺陷，头注释明写双侧）；⑦ 任一输入非有限 → 故障 2810，`fSlaveSp` **保持末次有效值**（切到 0 会直接停料）；⑧ **`CASE` + `ELSE` 兜底**：`ELSE` → `eFault` + 2812；⑨ `fbTrigReset` 周期首部无条件刷新。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0002_2801` | 信息 | 比率被限幅 / 主动流量低于低限已切安全给定 |
| `16#0002_2802` | 信息 | **预留禁用（不得挪用）** |
| `16#0002_2810` | 故障 | 输入非有限或斜率参数非法，给定保持末次有效 |
| `16#0002_2811` | 故障 | 限值区间自相矛盾（比率域或输出域非法） |
| `16#0002_2812` | 故障 | 状态机落 `ELSE` 兜底（非法状态，回 `eIdle` 并保持末值） |

- **来源标签**：自研（比值控制为公开过程控制通用结构；「低限切安全给定」的语义划分与迟滞/斜率/兜底纪律为本库自有）；T2-5 Mod_PID 只借「参数域约束」组织方式（矩阵判定其参数域已取尽）；**零检索**

---

#### #9 `FB_DL_LeadLagCompensator` —— 一阶超前滞后相位校正

- **分类**：DL_Algo / Control law ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：H
- **功能**：实现 `Kc·(1 + T_lead·s)/(1 + T_lag·s)` 的离散形式。现场用途：回路振荡但相位裕度不足时给前向通道加相位超前；或抑制低频扰动时加滞后。库内已有 `FeedforwardComp`（前馈）、`SmithPredictor`（纯滞后补偿）、四类滤波，**但没有可调相位形状的校正器**——这是调过一个真实回路的工程师才会来找的块。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 旁路（输出 = 输入） |
| `bReset` | BOOL | — | — | 上升沿清内部状态 |
| `fIn` | REAL | 0.0 | 用户单位 | 输入（一般接偏差） |
| `fGain` | REAL | 1.0 | [无量纲] | 静态增益 Kc，域 −1000.0~1000.0，**禁 0** |
| `tLeadTime` | TIME | T#100MS | ms | 超前时间常数，域 0~60 000 ms |
| `tLagTime` | TIME | T#1S | ms | 滞后时间常数，域 1~600 000 ms，**必须 ≥ 采样周期** |
| `tSampleTime` | TIME | T#100MS | ms | 采样周期，域 1~10 000 ms |
| `fOutLimit` | REAL | 1.0E6 | 用户单位 | 输出幅值限幅，域 > 0 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `fOut` | REAL | 用户单位 | 校正后输出 |
| `bBypass` | BOOL | — | 旁路中（参数非法或未使能） |
| `bSaturated` | BOOL | — | 输出被限幅 |
| `uCoeffRev` | UDINT | 次 | 系数重算次数（在线改参监视） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR**：`fbTrigReset : R_TRIG`｜`fA0/fA1/fB0/fB1 : REAL`（Tustin 归一化系数）｜`fX1 / fY1 : REAL`（历史值）｜`fPrevK/fPrevTl/fPrevTg/fPrevTs : REAL`（改参检测）｜`tLeadSec / tLagSec / tTsSec : REAL`
- **VAR CONSTANT**：`DL_LL_LEAD_MAX : TIME := T#60S`｜`DL_LL_LAG_MAX : TIME := T#600S`｜`DL_LL_GAIN_MAX : REAL := 1000.0`｜`DL_LL_DT_MAX : TIME := T#10S`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `tSampleTime < T#1MS` 或 `> DL_LL_DT_MAX` → 故障 2910，**旁路**（离散化失效时宁可直通，不可输出病态波形）；② `tLagTime < tSampleTime` → 故障 2910（滞后时间小于采样周期时 Tustin 离散化极点会出单位圆）；③ `tLeadTime > DL_LL_LEAD_MAX` / `tLagTime > DL_LL_LAG_MAX` → 钳位 + 信息 2901；④ `fGain` 非有限或 `ABS(fGain) <= EPS` → 故障 2911，旁路（增益 0 会把回路静默掐死，比报错更危险）；⑤ Tustin 归一化系数 `a0 := 2·T_lag + Ts`，**前置防零判据**（`ABS(a0) > EPS` 才除，否则 2910）；⑥ 在线改参（`fPrevK/fPrevTl/fPrevTg/fPrevTs` 逐项 `ABS(diff) > EPS`）→ 重算系数、**保留历史状态不清零** + 信息 2901；⑦ 输出双侧限幅 `MIN(MAX(y, -fOutLimit), fOutLimit)`，超限置 `bSaturated` + 信息 2901；⑧ 差分式用直接 II 型减状态量（`y = b0·x + z1; z1 = b1·x − a1·y`），头注释声明；⑨ 输入非有限 → 故障 2911，`fOut` 保持末次有效（**不旁路**——旁路会把毒值直接注入执行器）；⑩ `fbTrigReset` 周期首部无条件刷新。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0002_2901` | 信息 | 时间常数超域已钳位 / 在线改参已重算系数（状态保留）/ 输出限幅生效 |
| `16#0002_2902` | 信息 | **预留禁用（不得挪用）** |
| `16#0002_2910` | 故障 | 采样周期或滞后时间非法（离散化失效），旁路输出 |
| `16#0002_2911` | 故障 | 增益非有限或近零、输入非有限，输出保持末次有效 |
| `16#0002_2912` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：自研（超前滞后校正为公开经典控制判据，`Kc(1+T_lead·s)/(1+T_lag·s)` 属公共知识；Tustin 离散化、改参保状态、旁路判决、码位 100% 自有）；T1-1 OSCAT Basic 控制器族次源（只借「控制器归 Algo 且各律独立成块」的分类，**不复制任何实现**）；**零检索**

---

#### #10 `FB_DL_AutoTuneRelay` —— 继电反馈自整定

- **分类**：DL_Algo / Control law ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：H
- **功能**：把 `±d` 继电（可带迟滞 `h`）接入回路，等振幅稳定后测极限振荡周期 `Tu` 与幅值 `a`，按公开描述函数算临界增益 `Ku`，再按选定整定规则给出 `Kp/Ti/Td`。**本件不闭环控制**：只输出 `bRelayOut`（给上层的手动通道）与整定结果；测量合理性五项闸门（幅值稳定、采样密度、`h < a`、超时、非有限）全部做进块内。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 中止实验并清 `bRelayOut` |
| `bStart` | BOOL | — | — | 上升沿启动实验（运行中忽略） |
| `bAbort` | BOOL | — | — | 上升沿中止（回 `eIdle`，不置故障） |
| `fPv` | REAL | 0.0 | 用户单位 | 过程测量（被控量） |
| `fSp` | REAL | 0.0 | 用户单位 | 目标值（实验围绕此点进行） |
| `fRelayAmp` | REAL | 5.0 | 用户单位 | 继电幅值 `d`，域 > 0 且 < 满量程 20%（工程惯例上限，超了会激励非线性） |
| `fRelayHyst` | REAL | 0.2 | 用户单位 | 继电迟滞 `h`，域 0.0~`fRelayAmp`（含等号即非法） |
| `uCyclesRequired` | UINT | 4 | 周期 | 需要观察的完整振荡周期数，域 2~20 |
| `uMinSamplesPerHalf` | UINT | 6 | 拍 | 每半周期最少采样数，域 4~100（**从源头防采样失真**） |
| `tMaxDuration` | TIME | T#300S | s | 实验总超时，域 10 s~2 h |
| `fStabTolPercent` | REAL | 2.0 | % | 幅值稳定判据：前后半窗均值差百分比上限，域 0.1~20.0 |
| `eRule` | `E_DL_TuneRule` | `eZnPid` | — | 整定规则（同文件枚举 `eZnP`/`eZnPi`/`eZnPid`/`eAhNoOvershoot`） |
| `tSampleTime` | TIME | T#100MS | ms | 采样周期，域 1~10 000 ms |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `bRelayOut` | BOOL | — | 继电输出（TRUE = 加 `+d`），接上层手动通道 |
| `bBusy` | BOOL | — | 实验进行中 |
| `bDone` | BOOL | — | 完成（单周期脉冲，结果有效） |
| `fOscAmp` | REAL | 用户单位 | 测得振荡幅值 `a` |
| `tUltPeriod` | TIME | s | 测得极限周期 `Tu` |
| `fUltGain` | REAL | [无量纲] | 临界增益 `Ku` |
| `fKp` / `fTi` / `fTd` | REAL | — / s / s | 整定结果（`Ti = 0` 表示纯 P，`Td = 0` 表示无微分） |
| `uCycleDone` | UINT | 周期 | 已完成的有效振荡周期数 |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |
| `bValid` | BOOL | — | 结果可用 |

- **VAR**：`eState : E_DL_TuneState`（同文件枚举 `eIdle`/`eRelay`/`eMeasure`/`eDone`/`eFault`）｜`fbTrigStart / fbTrigAbort : R_TRIG`｜`fbTimeout : TON`｜`bRelayPrev : BOOL`｜`fPeakHi / fPeakLo : REAL`｜`tEdgeLast / tHalfPrev / tHalf : TIME`｜`uHalfCount : UINT`｜`fAmpSum1 / fAmpSum2 : REAL`｜`uAmpCnt1 / uAmpCnt2 : UINT`
- **VAR CONSTANT**：`DL_AT_MIN_CYCLES : UINT := 2`｜`DL_AT_MAX_CYCLES : UINT := 20`｜`DL_AT_MIN_SAMPLES : UINT := 4`｜`DL_AT_PI : REAL := 3.14159265`｜`DL_AT_AMP_RATIO_MAX : REAL := 0.2`（继电幅值 / 满量程上限）｜`DL_AT_DT_MAX : TIME := T#10S`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `fRelayAmp <= EPS` 或非有限 → 故障 2A10（`d = 0` 时 `Ku = 0`，整定结果是无意义的 0）；② **`fRelayHyst >= fOscAmp` → 拒绝出结果**（故障 2A10）：迟滞不小于实测幅值时描述函数分母 `√(a²−h²)` 为零/虚数，Ku 不可定义——公开资料一致要求「迟滞必须窄于所测振荡」；③ 每半周期采样数 `tHalf / tSampleTime < uMinSamplesPerHalf` → 故障 2A11（采样太疏时测出的「振荡」是采样网格产物，不是对象特性）；④ 幅值稳定判据：把最后 `2·uCyclesRequired` 个半周期的幅值切成前后两窗，两窗均值相对差 > `fStabTolPercent` → 判未收敛，继续测（置信息 2A01），超 `tMaxDuration` → 故障 2A12；⑤ `Ku = 4d/(π·√(a²−h²))`（含迟滞）/ `4d/(π·a)`（无迟滞），全部用 `LREAL` 中间量；`Ku` 非有限或 ≤ 0 → 故障 2A12；⑥ 整定规则（**公开规则文本**）：`eZnP` → `Kp = 0.5·Ku`；`eZnPi` → `Kp = 0.45·Ku, Ti = Tu/1.2`；`eZnPid` → `Kp = 0.6·Ku, Ti = Tu/2, Td = Tu/8`；`eAhNoOvershoot` → `Kp = 0.2·Ku, Ti = Tu/2, Td = Tu/3`；`CASE ... ELSE` 兜底 → 故障 2A12；⑦ `tSampleTime` 越域 → 故障 2A10；⑧ `fbTimeout` / `R_TRIG` 周期首部无条件刷新；⑨ `bAbort` → `eIdle`，**不置故障**（人为中止是合法操作）且 `bRelayOut := FALSE`（**必须撤继电，否则回路会一直振荡**——本件最高危点，头注释加粗写明）。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0002_2A01` | 信息 | 振荡未收敛，继续测量（已完成周期数 / 等待稳定） |
| `16#0002_2A02` | 信息 | **预留禁用（不得挪用）** |
| `16#0002_2A10` | 故障 | 继电参数非法（`d` 非正/非有限、`h ≥ a`、采样周期越域） |
| `16#0002_2A11` | 故障 | 半周期采样密度不足（< 6 拍/半周期），振荡不可信 |
| `16#0002_2A12` | 故障 | 超时未收敛 / `Ku` 不可表示 / 整定规则落 `ELSE` 兜底 |

- **来源标签**：公开学术判据 —— Åström & Hägglund 继电反馈法（1984）描述函数 `N(a) = 4d/(πa)`、含迟滞 `-1/N(a) = -(π/4d)·√(a²−h²) − i·πε/(4d)`；整定规则取 Ziegler-Nichols 与 Åström-Hägglund 公开文本。**只借公开公式与规则常数**（公式属公共知识，不构成代码版权），测量闸门、状态机、码位、引脚契约 100% 自有。经 **WebSearch 1 次**核对公式与「迟滞必须窄于所测振荡、每半周期 ≥ 6 采样、幅值需稳定」三条工程闸门（见 `RAW_NOTES_R19.md` §2）

---

### 3.3 批 3（Level 1 设备健康/诊断抽象 → 运动折算）

---

#### #11 `FB_DL_DeviceHealthArbiter` —— NE107 多源健康聚合仲裁

- **分类**：DL_Device / Diagnostics ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **功能**：把 N 路设备健康状态（来自阀/电机/仪表/变频器的 `E_DL_Ne107Status`）聚合成一个整机健康结论 + 首出通道。现场必须回答两个问题：「现在最严重的是哪一类」和「是谁先报的」。矩阵 §5 T2-8 明列「NE107 实现块仲裁件（多源健康聚合）待挖」——这是 NE107 语言落地的最后一块（枚举属主 `I_DL_DeviceHealth` 已有，实现块一直没有）。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 输出 `eUnknown` 并冻结首出 |
| `bReset` | BOOL | — | — | 上升沿清首出锁存（健康结论仍实时刷新） |
| `aeHealth` | ARRAY[0..15] OF `E_DL_Ne107Status` | — | — | 各源健康态（**枚举由 `I_DL_DeviceHealth` 唯一属主，本件只引用不重声明**） |
| `auChannelId` | ARRAY[0..15] OF UINT | — | — | 各源对外通道号（用于首出定位，可为 0） |
| `uSrcCount` | UINT | 16 | 路 | 有效源数，域 1~16 |
| `bIncludeMaintenance` | BOOL | TRUE | — | TRUE = 维护/校验类参与聚合；FALSE = 只聚 Failure / OutOfSpec |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `eAggHealth` | `E_DL_Ne107Status` | — | 聚合后健康结论 |
| `uFirstIdx` | UINT | — | 首出源索引 0~15，无则 `DL_HARB_NONE`(16#FFFF) |
| `uFirstChannel` | UINT | — | 首出源对外通道号 |
| `auLevelMask` | ARRAY[0..5] OF WORD | — | 分级位图：按 `eFailure/eCheckFunction/eMaintenanceReq/eOutOfSpec/eOk/eUnknown` 六态分桶，bit N = 源 N |
| `uFaultSrcCount` | UINT | 路 | 处于 Failure 或 OutOfSpec 的源数 |
| `bDegraded` | BOOL | — | 存在维护/校验类但无故障类（可继续运行但需安排处理） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR CONSTANT**：`DL_HARB_SRC_MAX : UINT := 16`｜`DL_HARB_NONE : UINT := 16#FFFF`｜`DL_HARB_LEVELS : UINT := 6`｜`DL_HARB_BIT_MAX : UINT := 15`
- **VAR**：`uIdx : UINT`｜`eBest : E_DL_Ne107Status`｜`uBestIdx : UINT`｜`bAnyKnown : BOOL`
- **边界安全条件**：① `uSrcCount = 0 OR > DL_HARB_SRC_MAX` → 故障 0330，`eAggHealth := eUnknown`、**不索引数组**；② 仲裁次序 = **枚举编号即优先级**（`I_DL_DeviceHealth` 已把编号定为仲裁序，本件不得自造第二套优先级——R31 家族纪律）；③ **Unknown 不遮蔽**：只要有任一源为已知非 OK 态，聚合结论不得为 `eUnknown`（现场最常见误判：一路通道没配好导致整机显示「未知」，把真故障压掉）；④ `bIncludeMaintenance = FALSE` 时 `eMaintenanceReq/eCheckFunction` 不计入聚合，但仍进位图（HMI 仍要看得到）；⑤ 首出：仅当未锁存时仲裁，同拍多源取**源索引最小**；复位沿在仲裁之后生效当拍即空（R11 `PortDiagAggregator` 首出三律同口径）；⑥ 枚举变量读入非法值（平台越界写入）→ 落 `ELSE` 分支归 `eUnknown` + 故障 0331（**红线 4：枚举 `CASE` 必须 `ELSE`**）；⑦ `FOR` 循环上界 `uSrcCount`（已由 ① 钳 1~16），无需额外守卫计数。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0003_016A` | 信息 | 同拍多源同级别，已按源索引最小仲裁 / 存在 Unknown 源但未遮蔽已知故障 |
| `16#0003_016B` | 信息 | **预留禁用（不得挪用）** |
| `16#0003_0330` | 故障 | 源数量越界（不在 1~16），聚合结论置 `eUnknown` |
| `16#0003_0331` | 故障 | 健康枚举值非法（`CASE` 落 `ELSE`），该源按 `eUnknown` 处理 |
| `16#0003_0332` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T2-8 NAMUR NE107（**只借公开的六态健康语言与「编号即仲裁优先级」的组织事实**，不复制任何条款文本）；聚合算法、位图结构、首出三律、码位 100% 自有；枚举唯一属主 `I_DL_DeviceHealth`（R13）**只引用不重声明**；**零检索**

---

#### #12 `FB_DL_ProfinetAlarmDiag` —— PROFINET 通道诊断聚合

- **分类**：DL_Device / Diagnostics ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：H
- **功能**：把上游已读出的通道诊断项（通道号 / 通道属性 / `ChannelErrorType` / `ExtChannelErrorType` / `ExtChannelAddValue`）分类成八类工程语义（短路 / 断线 / 过载 / 过温 / 超上限 / 欠下限 / 组态错 / 维护类），给出故障掩码、首出通道、分类计数与 NE107 健康出口。矩阵 §5 T1-7 明列「PROFINET 诊断（PN_ALARM_DIAG 语义）族待挖」。
- **输入引脚（诊断项数组，**不做原始字节解析**——零指针、零厂商库）**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `auChannelNo` | ARRAY[0..15] OF UINT | — | — | 通道号（协议域 0~32767，0 表示子模块级） |
| `auChannelProp` | ARRAY[0..15] OF WORD | — | — | 通道属性（协议位域，本件原样透传不解释） |
| `auErrType` | ARRAY[0..15] OF WORD | — | — | `ChannelErrorType`（公开枚举，见头注释解码表） |
| `auExtErrType` | ARRAY[0..15] OF WORD | — | — | `ExtChannelErrorType`（厂商扩展，本件只透传不解释） |
| `audAddValue` | ARRAY[0..15] OF UDINT | — | — | `ExtChannelAddValue`（附加上下文值） |
| `uEntryCount` | UINT | 0 | 项 | 有效诊断项数，域 0~16 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `uChannelMask` | WORD | — | 有诊断的项位图（bit N = 项 N） |
| `uFirstChannel` | UINT | — | 首出通道号（同拍取通道号最小） |
| `uFirstErrType` | WORD | — | 首出项的 `ChannelErrorType` 原值（HMI 可直接查表） |
| `auClassCount` | ARRAY[0..7] OF UINT | 次 | 八类计数（0 短路 / 1 断线 / 2 过载 / 3 过温 / 4 超上限 / 5 欠下限 / 6 组态错 / 7 维护类） |
| `bMaintenanceOnly` | BOOL | — | 只有维护类条目（可继续生产，需安排保养） |
| `bSystemLevel` | BOOL | — | 存在系统级码（`>= 16#8000`，总线/同步类问题，不是通道问题） |
| `eHealth` | `E_DL_Ne107Status` | — | NE107 健康出口（引用唯一属主枚举） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |
| `bValid` | BOOL | — | 结论可用 |

- **VAR CONSTANT（公开枚举值，头注释附解码表）**：`DL_PN_E_SHORT : WORD := 16#0001`｜`DL_PN_E_UNDERV : WORD := 16#0002`｜`DL_PN_E_OVERV : WORD := 16#0003`｜`DL_PN_E_OVERLOAD : WORD := 16#0004`｜`DL_PN_E_OVERTEMP : WORD := 16#0005`｜`DL_PN_E_WIREBREAK : WORD := 16#0006`｜`DL_PN_E_UPPER : WORD := 16#0007`｜`DL_PN_E_LOWER : WORD := 16#0008`｜`DL_PN_E_GENERIC : WORD := 16#0009`｜`DL_PN_E_PARAM_MISS : WORD := 16#000F`｜`DL_PN_E_PARAM_FAULT : WORD := 16#0010`｜`DL_PN_E_MAINT_REQ : WORD := 16#001E`｜`DL_PN_E_MAINT_DEM : WORD := 16#001F`｜`DL_PN_E_SYS_MIN : WORD := 16#8000`｜`DL_PN_CH_MAX : UINT := 32767`｜`DL_PN_ENTRY_MAX : UINT := 16`
- **边界安全条件**：① `uEntryCount > DL_PN_ENTRY_MAX` → 故障 0333，**钳位到 16 处理**（不越界读）；② `auChannelNo[i] > DL_PN_CH_MAX` → 故障 0334，该项跳过并计入 `uClassCount[6]`；③ 未识别的 `ChannelErrorType`（含厂商自定义域）→ 归「其他/组态错」桶 + 信息 016C（**协议允许厂商自定义，未识别不等于故障**）；④ **`16#001F` 语义冲突显式化**：CODESYS `ProfinetCommon` 把 `0x001F` 定义为 `Temporary_fault`，而西门子 ET200SP 公开表把它写作 `Maintenance demanded`。**本库裁定按「维护类」处理并置 `bMaintenanceOnly` 保守侧**，头注释并列两种语义与裁定理由（**不得二选一硬编码**，见 R66）；⑤ `>= 16#8000` 的系统级码**不占通道掩码**，单列 `bSystemLevel`（总线同步/网络组件类问题，运维处理路径完全不同）；⑥ 首出：同拍多条目取通道号最小；⑦ `CASE` 分类必须带 `ELSE` 兜底走「其他」桶；⑧ 非有限值不适用（全整数域）；⑨ `uEntryCount = 0` → 输出全空、`eHealth := eOk`、`bValid := TRUE`（协议合法：诊断记录长度 0 表示无故障）。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0003_016C` | 信息 | 未识别的 `ChannelErrorType`（厂商自定义域），已归「其他」桶 |
| `16#0003_016D` | 信息 | **预留禁用（不得挪用）** |
| `16#0003_0333` | 故障 | 诊断条目数超上限（> 16），已钳位处理 |
| `16#0003_0334` | 故障 | 通道号越界（> 32767），该项已跳过并计入组态错桶 |
| `16#0003_0335` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T1-7 PLCnext Community（只借「PROFINET 诊断寄存器位语义可独立成族」的提取点）；解码表取自 **PROFINET 公开规范的 `ChannelErrorType` 枚举**（见 `RAW_NOTES_R19.md` §1，经 **WebSearch 1 次**核对，三方一致）；**不解析原始诊断记录字节**、不使用任何厂商诊断对象/系统库（零厂商依赖红线）；聚合结构、首出律、八类分桶、码位 100% 自有

---

#### #13 `FB_DL_EscChuckCurrentMonitor` —— ESC 静电吸附电流监视

- **分类**：DL_Device / Diagnostics ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：H
- **功能**：半导体静电吸盘（ESC）吸附电流的三段判据：**建立段**（施加吸附电压后电流须在 `tBuildTime` 内落进电流窗）、**稳态段**（电流持续落窗 + 泄漏趋势）、**释放段**（撤电压后电流须归零）。失吸会直接导致晶圆飞片/破片，打火会烧盘面——两者在电流波形上是两种截然不同的特征，本件把「电流长时间偏低」与「瞬时尖峰」分开判。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 撤销所有判定输出 |
| `bReset` | BOOL | — | — | 上升沿清故障与趋势 |
| `bChuckOn` | BOOL | FALSE | — | 吸附电压施加命令（上层给定） |
| `fChuckCurrent` | REAL | 0.0 | µA | 吸附电流测量值，域 0.0~10 000.0 |
| `fChuckVoltage` | REAL | 0.0 | V | 吸附电压测量值，域 0.0~5 000.0 |
| `fCurMin` | REAL | 5.0 | µA | 稳态电流窗下限，域 > 0 |
| `fCurMax` | REAL | 500.0 | µA | 稳态电流窗上限，**必须 > `fCurMin`** |
| `fSparkRise` | REAL | 50.0 | µA | 打火判据：单拍电流跳变量阈值，域 > 0 |
| `tBuildTime` | TIME | T#2S | s | 建立段允许时长，域 100 ms~30 s |
| `tConfirmTime` | TIME | T#500MS | ms | 失吸确认时间，域 0~10 s |
| `tSampleTime` | TIME | T#10MS | ms | 采样周期，域 1~1000 ms |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `bAttached` | BOOL | — | 判定已吸附（建立成功且稳态落窗） |
| `bSpark` | BOOL | — | 检出打火尖峰（锁存） |
| `bLeakTrend` | BOOL | — | 泄漏趋势上升（电流缓慢单调上爬，预示盘面污染/绝缘退化） |
| `bDegraded` | BOOL | — | 降级运行（电流在窗内但贴近边界） |
| `eHealth` | `E_DL_Ne107Status` | — | 健康出口（引用唯一属主枚举） |
| `uAttachCount` | UDINT | 次 | 累计成功吸附次数（饱和） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR**：`eState : E_DL_EscState`（同文件枚举 `eIdle`/`eBuild`/`eSteady`/`eRelease`/`eFault`）｜`fbTrigReset : R_TRIG`｜`fbBuild : TON`｜`fbLossConfirm : TON`｜`fPrevCur : REAL`｜`fTrendAcc : REAL`｜`uTrendCnt : UINT`
- **VAR CONSTANT**：`DL_ESC_CUR_ABS_MAX : REAL := 10000.0`｜`DL_ESC_VOLT_MIN : REAL := 100.0`（判定「电压确实加上了」的下限 [V]）｜`DL_ESC_TREND_N : UINT := 50`（趋势取样个数）｜`DL_ESC_BAND_RATIO : REAL := 0.05`（近边界判定带宽，相对窗宽）｜`DL_ESC_DT_MAX : TIME := T#1S`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `fCurMin <= EPS` 或 `fCurMax <= fCurMin` → 故障 0336（阈值倒置时先**自动交换** + 信息 016E；交换后仍非法才报故障）；② 电流/电压非有限 → 故障 0336，判定冻结并保持末次 `bAttached`（**不得掉成未吸附**——会把在吸的晶圆判成飞片）；③ 建立段超时（`fbBuild.Q` 且 `bAttached = FALSE`）→ 故障 0337 + `eHealth := eFailure`；④ 稳态段电流低于下限超 `tConfirmTime` → 故障 0337（失吸）；⑤ 单拍跳变 `ABS(fChuckCurrent − fPrevCur) > fSparkRise` 且 `bChuckOn` → `bSpark := TRUE` 锁存 + 故障 0338 + `eHealth := eOutOfSpec`（**能继续吸 ≠ 盘面完好**，与 R13 裁定「故障带码不置 bError」家族一致：打火不立即置 `bError`，只置 `eOutOfSpec` 与锁存位）；⑥ `bChuckVoltage < DL_ESC_VOLT_MIN` 时不判电流（电压没加上，电流当然为零）→ 回 `eIdle`；⑦ 泄漏趋势：取最近 `DL_ESC_TREND_N` 拍的电流做前后半窗均值比较，后半窗均值持续高出前半窗 `DL_ESC_BAND_RATIO × 窗宽` → `bLeakTrend := TRUE`（信息级，不置故障）；⑧ `fbBuild` / `fbLossConfirm` / `fbTrigReset` 周期首部无条件刷新（**按段断输入，R40 家族高危点**：两个定时器各自 `IN` 由状态决定，不得把调用放进 `IF`）；⑨ `CASE` + `ELSE` 兜底 → `eFault` + 0336；⑩ 三阈值上限均需 `MIN` 钳到 `DL_ESC_CUR_ABS_MAX`。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0003_016E` | 信息 | 电流窗上下限倒置已自动交换 / 泄漏趋势上升 / 贴近边界降级运行 |
| `16#0003_016F` | 信息 | **预留禁用（不得挪用）** |
| `16#0003_0336` | 故障 | 阈值参数非法或输入非有限，判定冻结 |
| `16#0003_0337` | 故障 | 建立超时或稳态电流失窗（判失吸，`eHealth = eFailure`） |
| `16#0003_0338` | 故障 | 打火尖峰锁存（`eHealth = eOutOfSpec`，可继续但需检修） |

- **来源标签**：半导体 ESC 自研线（矩阵 §5 明列「ESC 静电吸附电流监视族待挖」）；**无外部开源源可挖，全部 clean-room 自研**，只借公开半导体设备工程语义（ESC 吸附/释放三段、失吸与打火是可区分的失效模式）；判据/状态机/码位 100% 自有；**零检索**

---

#### #14 `FB_DL_DeviceParamWrite` —— 设备参数写回

- **分类**：DL_Device / Device access ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：H
- **功能**：`FB_DL_DeviceParamVerify`（读 → 比 → 判）的**下半段**：备份快照 → 白名单逐项写 → 读回复核 → 不一致即回滚。矩阵 §5.1 勘误 **M-E3** 留了个未决问题：「参数写回属设备层还是工艺层」——**本轮裁定为设备层**（写回是设备访问能力，工艺层只应下发语义参数），并把裁定理由写进头注释，关闭该悬置项。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 中止并撤 `bBusy` |
| `bExecute` | BOOL | — | — | 上升沿启动一次写回事务 |
| `bAbort` | BOOL | — | — | 上升沿中止（**不触发回滚**，由调用方决定） |
| `bReset` | BOOL | — | — | 上升沿清故障与 `bRollback` |
| `auIndex` | ARRAY[0..15] OF UINT | — | — | 参数索引，域 1~65535 |
| `afWriteValue` | ARRAY[0..15] OF REAL | — | 用户单位 | 待写值 |
| `abWritable` | ARRAY[0..15] OF BOOL | — | — | **白名单**：FALSE = 只读项，禁止写 |
| `uCount` | UINT | 0 | 项 | 有效项数，域 1~16 |
| `fVerifyTol` | REAL | 0.001 | 用户单位 | 读回值容差，域 ≥ 0（0 = 严格相等，不推荐） |
| `tWriteTimeout` | TIME | T#5S | s | 单项写超时，域 100 ms~60 s |
| `tVerifyTimeout` | TIME | T#5S | s | 读回复核超时，域 100 ms~60 s |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `bBusy` | BOOL | — | 事务进行中 |
| `bDone` | BOOL | — | 全部写入并复核通过（单周期脉冲） |
| `bRollback` | BOOL | — | 发生过回滚（锁存） |
| `uWritten` | UINT | 项 | 实际写入并复核通过的项数 |
| `uSkipped` | UINT | 项 | 因白名单/越界被跳过的项数 |
| `uFailedIdx` | UINT | — | 首个失败项索引，`DL_DPW_NONE`(16#FFFF) = 无 |
| `afReadback` | ARRAY[0..15] OF REAL | 用户单位 | 复核读回值 |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR**：`eState : E_DL_ParamWriteState`（同文件枚举 `eIdle`/`eBackup`/`eWrite`/`eVerify`/`eRollback`/`eDone`/`eFault`）｜`fbTrigExec / fbTrigAbort / fbTrigReset : R_TRIG`｜`fbWrite / fbVerify : TON`｜`uIdx : UINT`｜`afBackup : ARRAY[0..15] OF REAL`
- **VAR CONSTANT**：`DL_DPW_ITEM_MAX : UINT := 16`｜`DL_DPW_NONE : UINT := 16#FFFF`｜`DL_DPW_TMO_MIN : TIME := T#100MS`｜`DL_DPW_TMO_MAX : TIME := T#60S`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `uCount = 0 OR > 16` → 故障 0339，事务不启动、不索引数组；② 白名单外项（`abWritable[i] = FALSE`）→ 跳过 + `uSkipped + 1` + 信息 0170（**绝不写只读项**：写只读项在多数设备上会被静默忽略或引发参数区校验失败，后者会让整块参数失效）；③ 写超时（`fbWrite.Q`）→ 故障 033A，转 `eRollback`；④ 读回偏差 `ABS(afReadback[i] − afWriteValue[i]) > fVerifyTol` → 故障 033A + 转 `eRollback`（**写进去但没保持住 = 参数区有问题，必须回滚**）；⑤ 回滚过程中再失败 → 故障 033B **锁存并禁止自动重试**（安全侧：参数区已不可信，必须人工介入）；⑥ 写值非有限 → 故障 033A，该项不写；⑦ `CASE` + `ELSE` 兜底 → `eFault` + 033B；⑧ 两个定时器与三个 `R_TRIG` 周期首部无条件刷新；⑨ `bAbort` → `eIdle`、`bBusy := FALSE`，**不置故障、不自动回滚**（中止是人为决策，回滚由调用方再发一次事务决定，头注释写明）；⑩ `bDone` 单周期脉冲，`bRollback` 保持锁存直到 `bReset`。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0003_0170` | 信息 | 白名单外项已跳过（`uSkipped` 非 0） |
| `16#0003_0171` | 信息 | **预留禁用（不得挪用）** |
| `16#0003_0339` | 故障 | 项数越界（不在 1~16），事务不启动 |
| `16#0003_033A` | 故障 | 写超时 / 读回复核不一致 / 写值非有限，已转回滚 |
| `16#0003_033B` | 故障 | 回滚失败或状态机兜底——参数区不可信，须人工介入（锁存） |

- **来源标签**：T1-4 CODESYS Forge `DeviceReader` 族（只借「设备参数读 → 比 → 判」三段流程骨架的**下半段划分**，示例页面未显式声明许可 → **按最严口径处置：零代码行、零注释引用**）；M-E3 裁定「写回归设备层」于本件关闭；状态机、白名单机制、回滚策略、码位 100% 自有；**零检索**

---

#### #15 `FB_DL_ExternalEncoderScaler` —— 外部编码器折算

- **分类**：DL_Motion / Feedback ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **功能**：把外部编码器原始计数折算成工程量（mm / °），含分辨率、传动比、导程三段折算与**计数回绕展开**（32 位计数器每转一圈就回零，不展开的话多圈坐标会跳变）。矩阵 §5 T2-4 明列「外部编码器族待挖」。**不消费、不自造轴状态**（R13 `PassiveHomingMonitor` 纪律）。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 输出冻结 |
| `bReset` | BOOL | — | — | 上升沿清多圈展开与零点 |
| `diRawCount` | DINT | 0 | count | 原始计数（编码器直接读出的 32 位值） |
| `uCountsPerRev` | UDINT | 4096 | count/rev | 每转计数，**必须 > 0** |
| `fPitch` | REAL | 5.0 | mm/rev | 每转行程（丝杠导程 / 辊周长），**必须 > 0** |
| `iGearNum` | INT | 1 | — | 传动比分子，**必须 ≠ 0** |
| `iGearDen` | INT | 1 | — | 传动比分母，**必须 ≠ 0** |
| `bInvert` | BOOL | FALSE | — | TRUE = 方向取反 |
| `fOffset` | REAL | 0.0 | mm | 零点偏置 |
| `nMultiTurnBits` | INT | 32 | bit | 计数器位宽，域 8~32（用于回绕判据的半量程计算） |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `fPosition` | REAL | mm | 折算后工程量 |
| `liTotalCount` | LINT | count | 展开后的多圈累计计数 |
| `bWrapped` | BOOL | — | 本拍检测到回绕（单周期脉冲） |
| `uWrapCount` | UDINT | 次 | 累计回绕次数（饱和） |
| `fVelocity` | REAL | mm/s | 由相邻拍差分得的估计速度（仅供监视，不参与控制） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |
| `bValid` | BOOL | — | 输出可用 |

- **VAR**：`fbTrigReset : R_TRIG`｜`diPrevRaw : DINT`｜`liAccum : LINT`｜`nHalfSpan : DINT`｜`bInit : BOOL`｜`fPrevPos : REAL`｜`tPrev : TIME`
- **VAR CONSTANT**：`DL_EES_CPR_MIN : UDINT := 1`｜`DL_EES_BITS_MIN : INT := 8`｜`DL_EES_BITS_MAX : INT := 32`｜`DL_EES_CNT_MAX : UDINT := 16#FFFF_FFFE`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `uCountsPerRev = 0` 或 `fPitch <= EPS` 或非有限 → 故障 02DE，输出冻结（**除零唯一出口**）；② `iGearNum = 0 OR iGearDen = 0` → 故障 02DF；③ `nMultiTurnBits` 不在 8~32 → 钳位 + 信息 01CD（钳位后回绕判据仍可用，不必停功能）；④ **回绕展开**：`nDelta := diRawCount − diPrevRaw`（**必须先做 DINT 减法再升 LINT**——先升位再减会让 32 位回绕变成巨大正数，这是本件最易错的一行）；`IF nDelta > nHalfSpan THEN nDelta := nDelta − 2·nHalfSpan; ELSIF nDelta < −nHalfSpan THEN nDelta := nDelta + 2·nHalfSpan; END_IF`，然后 `liAccum := liAccum + DINT_TO_LINT(nDelta)` + 信息 01CD + `bWrapped := TRUE`；⑤ 折算链 `fPos := liAccum(升 REAL) / uCountsPerRev · fPitch · (iGearNum / iGearDen) · (bInvert ? −1 : 1) + fOffset`，分母已由 ① ② 保证非零；⑥ 首拍 `bInit = FALSE` 时只装初值、不产生 `bWrapped`；⑦ 输出非有限（LINT→REAL 溢出或乘法溢出）→ 故障 02E0，保持末次有效位置（**掉成 0 会被上层当成真实回零**）；⑧ 无 `CASE` 状态机（纯折算 + 单比特 `bInit`），头注释按 R6 句式写。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0004_01CD` | 信息 | 检测到计数回绕已展开 / 位宽参数超域已钳位 |
| `16#0004_01CE` | 信息 | **预留禁用（不得挪用）** |
| `16#0004_02DE` | 故障 | 分辨率或导程非法（为 0 / 非有限），输出冻结 |
| `16#0004_02DF` | 故障 | 传动比分子或分母为 0 |
| `16#0004_02E0` | 故障 | 折算结果非有限，保持末次有效位置 |

- **来源标签**：T2-4 S7-1500 Motion 示例（只借「外部编码器属运动层反馈、可独立成块」的分类事实，矩阵 §5 明列待挖）；回绕展开算法、折算链顺序、码位 100% 自有；**不自造轴状态、不发运动指令**；**零检索**

---

### 3.4 批 4（Level 1 运动补偿/计数 → Level 2 工艺模板）

---

#### #16 `FB_DL_CamPhaseTrim` —— 凸轮相位在线修调

- **分类**：DL_Motion / Cam ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **功能**：运行中在线修调凸轮相位，输出一个相位偏移量**注入** `FB_DL_ElectronicCam` 的相位输入（**组合而非内联**——R13 纪律：可依赖低层，但不复制低层）。现场语义：飞剪/横切/贴标的「切点对位」——用色标或标记传感器测到实际相位偏差，运行中一点点修，修的过程必须限速率且不能突变（突变等于给机械一个冲击）。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 偏移归 0（限速率回零） |
| `bReset` | BOOL | — | — | 上升沿立即清偏移（**检修专用**，会跳变） |
| `fPhaseOffsetCmd` | REAL | 0.0 | ° | 目标相位偏移，域 −180.0~180.0 |
| `fRateMax` | REAL | 30.0 | °/s | 偏移变化率上限，域 0.1~3600.0 |
| `fPhaseLimit` | REAL | 90.0 | ° | 偏移绝对值上限，域 1.0~180.0 |
| `bTrimOnMark` | BOOL | FALSE | — | TRUE = 除常驻偏移外，再叠加标记沿的一次性补偿 |
| `fMarkCorrection` | REAL | 0.0 | ° | 单次标记补偿量，域 −10.0~10.0 |
| `bMarkPulse` | BOOL | FALSE | — | 标记传感器脉冲（上升沿有效） |
| `tSampleTime` | TIME | T#10MS | ms | 采样周期，域 1~1000 ms |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `fPhaseOffset` | REAL | ° | 实际输出相位偏移（注入凸轮块） |
| `bTrimming` | BOOL | — | 正在趋近目标 |
| `bLimited` | BOOL | — | 受速率或幅值限制 |
| `uMarkCount` | UDINT | 次 | 已受理的标记补偿次数（饱和） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR**：`fbTrigReset / fbTrigMark : R_TRIG`｜`eState : E_DL_TrimState`（同文件枚举 `eIdle`/`eRamping`/`eHold`/`eFault`）｜`fOffset : REAL`｜`fTarget : REAL`｜`fStep : REAL`｜`fDtSec : REAL`｜`bMarkArmed : BOOL`
- **VAR CONSTANT**：`DL_CPT_LIMIT_MAX : REAL := 180.0`｜`DL_CPT_RATE_MAX : REAL := 3600.0`｜`DL_CPT_RATE_MIN : REAL := 0.1`｜`DL_CPT_MARK_MAX : REAL := 10.0`｜`DL_CPT_DT_MAX : TIME := T#1S`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `fPhaseLimit <= 0 OR > 180.0` → 故障 02E1（相位域物理上限 360°，偏移超半周在凸轮上等于换一相，语义完全不同）；② `fRateMax` 不在 0.1~3600 °/s → 故障 02E1（速率 0 会让修调永久卡住、速率过大等于允许突变）；③ `fPhaseOffsetCmd` 超 `±fPhaseLimit` → 钳位 + 信息 01CF；④ **一次性补偿每标记沿只加一次**，且必须 `bMarkArmed`（上一周期已复位）才能受理——否则高频标记会在一拍内累加成大跳变（本件最高危点）；⑤ 相位归一用条件加减（`IF x > 180.0 THEN x := x − 360.0;`），**禁浮点 `MOD`**；⑥ `tSampleTime` 越域 → 故障 02E1；⑦ 输入非有限 → 故障 02E2，`fPhaseOffset` 保持末次有效（**归 0 会导致切点瞬间错位，切出废品**）；⑧ `CASE` + `ELSE` 兜底 → 02E3；⑨ `R_TRIG` 周期首部无条件刷新；⑩ `bReset` 立即清偏移（唯一允许跳变的路径，头注释写明「检修专用」）。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0004_01CF` | 信息 | 目标偏移超限已钳位 / 单次标记补偿已生效 |
| `16#0004_01D0` | 信息 | **预留禁用（不得挪用）** |
| `16#0004_02E1` | 故障 | 限幅或速率或采样周期参数非法，修调冻结 |
| `16#0004_02E2` | 故障 | 指令或补偿量非有限，偏移保持末次有效 |
| `16#0004_02E3` | 故障 | 状态机落 `ELSE` 兜底（非法状态，回 `eIdle` 并保持偏移） |

- **来源标签**：T1-6 PLCopen Motion（只借「凸轮相位可在线修调属运动层能力」的公开语义，矩阵 §5 明列待挖）；**不自造轴状态、不内联凸轮算法**（组合 `FB_DL_ElectronicCam`）；限速率渐进、标记一次性受理、码位 100% 自有；**零检索**

---

#### #17 `FB_DL_FilmWebCenter` —— 膜卷纠偏（EPC）

- **分类**：DL_Motion / Guide ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **功能**：边缘/中心偏差 → 纠偏辊位置给定。核心防御三条：**死区内保持**（偏差在死区内不动，防辊子随噪声来回磨）、**限速率**（纠偏动作过快会造成膜起皱甚至跑偏振荡）、**断料保持**（膜断了还继续纠偏，辊子会一路顶到机械极限，复产后第一次穿膜直接撞限位）。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 输出保持末值（**不归零**） |
| `bReset` | BOOL | — | — | 上升沿回中位并清状态 |
| `bAuto` | BOOL | FALSE | — | TRUE = 自动纠偏 / FALSE = 手动（走 `fManualOffset`） |
| `fDeviation` | REAL | 0.0 | mm | 边缘/中心偏差（正 = 偏向驱动侧） |
| `fGain` | REAL | 1.0 | mm/mm | 偏差 → 位置给定增益，域 0.1~20.0 |
| `fManualOffset` | REAL | 0.0 | mm | 手动偏置，域 `fTravelMin`~`fTravelMax` |
| `fDeadband` | REAL | 0.3 | mm | 死区半宽，域 0.0~10.0 |
| `fRateMax` | REAL | 5.0 | mm/s | 给定最大变化率，域 0.01~100.0 |
| `fTravelMin` | REAL | -50.0 | mm | 行程下限 |
| `fTravelMax` | REAL | 50.0 | mm | 行程上限，**必须 > `fTravelMin`** |
| `bWebPresent` | BOOL | TRUE | — | 膜在位信号（FALSE = 断料） |
| `tSampleTime` | TIME | T#20MS | ms | 采样周期，域 1~1000 ms |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `fPositionSp` | REAL | mm | 纠偏辊位置给定 |
| `bInDeadband` | BOOL | — | 偏差在死区内（给定保持） |
| `bLimited` | BOOL | — | 受行程或速率限制 |
| `bWebLost` | BOOL | — | 断料保持中 |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |
| `bValid` | BOOL | — | 给定可用 |

- **VAR**：`fbTrigReset : R_TRIG`｜`eState : E_DL_WebState`（同文件枚举 `eIdle`/`eManual`/`eAuto`/`eWebLost`/`eFault`）｜`fLastSp : REAL`｜`fStep : REAL`｜`fDtSec : REAL`
- **VAR CONSTANT**：`DL_EPC_GAIN_MIN : REAL := 0.1`｜`DL_EPC_GAIN_MAX : REAL := 20.0`｜`DL_EPC_RATE_MIN : REAL := 0.01`｜`DL_EPC_RATE_MAX : REAL := 100.0`｜`DL_EPC_DT_MAX : TIME := T#1S`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `fTravelMax <= fTravelMin` → 故障 02E4（行程域不存在）；② `fGain` 不在 0.1~20.0 或 `fRateMax` 不在 0.01~100.0 → 故障 02E4（增益过大是纠偏振荡的头号原因，硬限比"相信现场"更安全）；③ **`bWebPresent = FALSE` → `fPositionSp` 保持末值、置 `bWebLost` + 信息 01D1，绝不追 0**（断料后追 0 等于让辊子穿膜位置全错）；④ 死区内 `ABS(fDeviation) <= fDeadband` → 给定保持 + `bInDeadband`（**不是**把给定设成 0）；⑤ 给定双侧钳位 `MIN(MAX(x, fTravelMin), fTravelMax)`，超限置 `bLimited`；⑥ 斜率限制 `fStep := fRateMax·dt`，首拍 `dt <= 0` 时 `fStep := 0.0`（不用 0 除）；⑦ 偏差非有限 → 故障 02E5，`fPositionSp` 保持末次有效；⑧ `CASE` + `ELSE` 兜底 → 02E6；⑨ `fbTrigReset` 周期首部无条件刷新。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0004_01D1` | 信息 | 断料保持中 / 偏差在死区内给定保持 |
| `16#0004_01D2` | 信息 | **预留禁用（不得挪用）** |
| `16#0004_02E4` | 故障 | 增益/速率/行程参数非法，纠偏冻结在中心位 |
| `16#0004_02E5` | 故障 | 偏差输入非有限，给定保持末次有效 |
| `16#0004_02E6` | 故障 | 状态机落 `ELSE` 兜底（非法状态，回 `eIdle` 并保持给定） |

- **来源标签**：ROADMAP §10.4 P1 `FB_DL_FilmWebCenter`（勾选收口）；纠偏为公开卷材处理工程结构（EPC/CPC），**死区保持、断料保持、限速率、码位 100% 自有**；与 `FB_DL_WindingTraverse`（排线往复）、`FB_DL_BacklashCompensator`（背隙修正）职责严格分离；**零检索**

---

#### #18 `FB_DL_WindingLayerCounter` —— 卷绕层数计数

- **分类**：DL_Motion / Winding ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **功能**：由「卷径 + 芯径 + 材料厚度」推算已绕层数与剩余层数，并**与圈计数交叉校核**（两者差超过 1 层说明有打滑/叠绕，只提示不报故障——打滑在薄膜/极片卷绕里是常态）。换卷重置，层数饱和钳位。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 冻结层数 |
| `bReset` | BOOL | — | — | 上升沿清零（换卷） |
| `bNewRoll` | BOOL | — | — | 上升沿视为换卷（同 `bReset` 但保留累计统计） |
| `fCoilDiameter` | REAL | 76.2 | mm | 当前卷径（外部卷径件/测距给出） |
| `fCoreDiameter` | REAL | 76.2 | mm | 芯径，**必须 > 0** |
| `fThickness` | REAL | 0.1 | mm | 材料厚度（含隔膜/铜箔），**必须 > 0** |
| `diRevCount` | DINT | 0 | 圈 | 卷轴累计圈计数（方向敏感，用于交叉校核） |
| `uLayerMax` | UINT | 5000 | 层 | 层数饱和上限，域 10~60 000 |
| `bDirPositive` | BOOL | TRUE | — | 当前旋转方向（反向时圈计数取负） |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `uLayerDone` | UINT | 层 | 已绕层数（由卷径推算） |
| `uLayerRemain` | UINT | 层 | 剩余层数（相对 `uLayerMax`） |
| `bLayerEdge` | BOOL | — | 层数变化单周期脉冲 |
| `bInconsistent` | BOOL | — | 圈计数与卷径推算不一致（> 1 层） |
| `fThicknessEst` | REAL | mm | 由卷径与圈数反推的等效厚度（工艺监视用） |
| `uRollCount` | UDINT | 卷 | 累计换卷次数（饱和） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR**：`fbTrigReset / fbTrigNewRoll : R_TRIG`｜`uLayerPrev : UINT`｜`uRollCnt : UDINT`｜`fLayerFloat : REAL`
- **VAR CONSTANT**：`DL_WLC_LAYER_MIN : UINT := 10`｜`DL_WLC_LAYER_MAX : UINT := 60000`｜`DL_WLC_CNT_MAX : UDINT := 16#FFFF_FFFE`｜`DL_WLC_TOL_LAYER : REAL := 1.0`（交叉校核容差 [层]）｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `fThickness <= EPS` 或非有限 → 故障 02E7，层数冻结（**除零唯一出口**：厚度在分母上）；② `fCoreDiameter <= EPS` → 故障 02E7；③ `fCoilDiameter < fCoreDiameter` → 故障 02E8（卷径小于芯径物理上不可能，通常是测距件故障或参数填反，此时硬算会得到负层数）；④ 层数 `fLayerFloat := (fCoilDiameter − fCoreDiameter) / (2.0 · fThickness)`，超 `uLayerMax` → 钳位 + 信息 01D3；⑤ **交叉校核**：`|fLayerFloat − |diRevCount|| > DL_WLC_TOL_LAYER` → `bInconsistent := TRUE` + 信息 01D3（**只提示不报故障**：打滑/叠绕/测距噪声都会造成偏差，报故障会误停整条线）；⑥ 等效厚度反推 `fThicknessEst := (fCoilDiameter − fCoreDiameter) / (2.0 · max(|diRevCount|, 1))`，分母用 `MAX(...,1)` 而非除零闸（圈数为 0 是开机常态）；⑦ `uLayerMax` 越 10~60 000 → 钳位 + 信息 01D3；⑧ `bDirPositive = FALSE` 时圈计数取模长参与校核（层数是标量）；⑨ 无 `CASE` 状态机（纯计数 + 边沿），头注释按 R6 句式写。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0004_01D3` | 信息 | 层数超上限已钳位 / 圈计数与卷径推算不一致（打滑/叠绕，仅提示） |
| `16#0004_01D4` | 信息 | **预留禁用（不得挪用）** |
| `16#0004_02E7` | 故障 | 厚度或芯径非法（≤ 0 / 非有限），层数冻结 |
| `16#0004_02E8` | 故障 | 卷径非有限或小于芯径（含测距件故障） |
| `16#0004_02E9` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：ROADMAP §15.1 P1 `FB_DL_WindingLayerCounter`（勾选收口）；层数递推为公开几何关系，与 `FC_DL_CoilDiameterCalc`（算直径）构成「算一个值 / 数一件事」的职责切分（R10 纪律）；交叉校核、饱和、码位 100% 自有；**零检索**

---

#### #19 `FB_DL_DrumLevelThreeElem` —— 汽包水位三冲量（单泵轻量版）

- **分类**：DL_Process / Boiler ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：H
- **功能**：汽包水位的三冲量给定：水位偏差（主） + 蒸汽流量前馈（负荷扰动前馈） − 给水流量反馈（内回路快速抑制）。**本件不出 PID 输出**，只出「给水流量给定」由上层 `FB_DL_PidController` 闭合流量小回路（职责边界写进头注释，防与 `CascadePid` 打架）。现场价值：单冲量在负荷突变时水位会「假水位」反向摆动，三冲量能压住。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 给定保持末值 |
| `bReset` | BOOL | — | — | 上升沿清限幅锁存与联锁 |
| `fLevel` | REAL | 0.0 | mm | 汽包水位（相对正常水位线），域 −300.0~300.0 |
| `fLevelSp` | REAL | 0.0 | mm | 水位目标，域 −100.0~100.0 |
| `fSteamFlow` | REAL | 0.0 | t/h | 蒸汽流量，域 0.0~1.0E4 |
| `fFeedFlow` | REAL | 0.0 | t/h | 给水流量，域 0.0~1.0E4 |
| `fLevelGain` | REAL | 0.05 | t/h/mm | 水位偏差增益，域 0.001~10.0 |
| `fSteamGain` | REAL | 1.0 | t/h per t/h | 蒸汽前馈系数，域 0.0~3.0 |
| `fFeedGain` | REAL | 0.5 | t/h per t/h | 给水反馈系数，域 0.0~2.0 |
| `fLevelLow` | REAL | -150.0 | mm | 低水位报警/联锁门限 |
| `fLevelHigh` | REAL | 150.0 | mm | 高水位报警/联锁门限，**必须 > `fLevelLow`** |
| `fOutMin` | REAL | 0.0 | t/h | 给定下限 |
| `fOutMax` | REAL | 500.0 | t/h | 给定上限，**必须 > `fOutMin`** |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `fFeedSp` | REAL | t/h | 给水流量给定（送 PID 作设定值） |
| `bLevelLow` | BOOL | — | 低水位（`fLevel <= fLevelLow`） |
| `bLevelHigh` | BOOL | — | 高水位（`fLevel >= fLevelHigh`） |
| `bInterlockTrip` | BOOL | — | 联锁触发建议（越限锁存，需 `bReset`） |
| `bLimited` | BOOL | — | 给定被上下限限制 |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |
| `bValid` | BOOL | — | 给定可用 |

- **VAR**：`fbTrigReset : R_TRIG`｜`eState : E_DL_DrumState`（同文件枚举 `eIdle`/`eRunning`/`eLowTrip`/`eHighTrip`/`eFault`）｜`fLastSp : REAL`
- **VAR CONSTANT**：`DL_DL3_LEVEL_ABS_MAX : REAL := 1000.0`｜`DL_DL3_GAIN_MAX : REAL := 10.0`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `fLevelLow >= fLevelHigh` → 故障 0306（**水位限值矛盾 = 联锁彻底失效，比水位本身危险**，直接回 `eFault` 且给定保持末值）；② `fOutMax <= fOutMin` → 故障 0306；③ `fLevel` / `fSteamFlow` / `fFeedFlow` 非有限 → 故障 0305，给定保持末次有效（切 0 等于停给水泵，汽包会在十几秒内烧干）；④ 给定累加式 `fSp := fLastSp + fLevelGain·(fLevel − fLevelSp) + fSteamGain·fSteamFlow − fFeedGain·fFeedFlow`（**增量式而非绝对式**：三冲量在工程上带积分性质，绝对式会让水位缓慢收敛到偏置点，这是本件的算法要点，头注释写明）；⑤ 输出双侧钳位 `MIN(MAX(fSp, fOutMin), fOutMax)`，超限置 `bLimited` + 信息 01D6；⑥ 越限锁存：`fLevel <= fLevelLow` → `eLowTrip` + `bInterlockTrip`（锁存，不随水位恢复自动解除，须 `bReset`——**汽包低水位是安全事件，不能自恢复**）；⑦ `CASE` + `ELSE` 兜底 → 0307；⑧ `fbTrigReset` 周期首部无条件刷新。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0005_01D6` | 信息 | 给定被上下限限制 / 水位接近报警门限 |
| `16#0005_01D7` | 信息 | **预留禁用（不得挪用）** |
| `16#0005_0305` | 故障 | 水位或流量输入非有限，给定保持末次有效 |
| `16#0005_0306` | 故障 | 水位限值或输出限值区间矛盾（联锁失效） |
| `16#0005_0307` | 故障 | 状态机落 `ELSE` 兜底（非法状态，回 `eIdle` 并保持给定） |

- **来源标签**：ROADMAP §10.6 P1 `FB_DL_DrumLevelThreeElem`（勾选收口）；三冲量为公开锅炉控制工程结构（水位 + 蒸汽前馈 + 给水反馈），**增量式给定、限值矛盾闸、越限锁存、码位 100% 自有**；`FB_DL_PidController` / `FB_DL_CascadePid` 只作下游组合，**不内联 PID**；**零检索**

---

#### #20 `FB_DL_VacCupRingCtrl` —— 多吸盘组分档拾放

- **分类**：DL_Process / Handling ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：H
- **功能**：一组（1~8 个）真空吸盘的拾放控制：逐通道吸附确认、**吸盘数不足时判拾取失败**（安全侧，禁止带着少吸的料上轴）、可选降级放行（少吸但降速）、分组释放（先外圈后内圈，防料被甩）。与 `FB_DL_VacuumEjector`（单个真空发生器）的分界：本件是**组级工艺编排**，单机控制仍归 Device 层。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 撤销所有阀输出 |
| `bReset` | BOOL | — | — | 上升沿清故障与降级锁存 |
| `bCmdPick` | BOOL | — | — | 拾取命令（上升沿启动） |
| `bCmdRelease` | BOOL | — | — | 释放命令（上升沿启动） |
| `auVacuumOk` | ARRAY[0..7] OF BOOL | — | — | 各吸盘真空到位开关 |
| `afVacuum` | ARRAY[0..7] OF REAL | — | kPa | 各吸盘真空度（负值），域 −101.3~0.0 |
| `uCupCount` | UINT | 4 | 个 | 有效吸盘数，域 1~8 |
| `uMinCupsRequired` | UINT | 4 | 个 | 最少需吸附的吸盘数，域 1~`uCupCount` |
| `fVacMin` | REAL | -40.0 | kPa | 真空度合格门限（负值，绝对值越大越紧） |
| `tConfirmTime` | TIME | T#500MS | ms | 吸附确认时间，域 0~10 s |
| `bAllowDegrade` | BOOL | FALSE | — | TRUE = 允许少吸降级放行（须 `uMinCupsRequired` 满足） |
| `bReleaseOuterFirst` | BOOL | TRUE | — | TRUE = 先释放偶数通道（视为外圈） |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `auValveOut` | ARRAY[0..7] OF BOOL | — | 各吸盘真空阀输出（由上层映射到物理点） |
| `bPicked` | BOOL | — | 已拾取（吸附确认通过） |
| `bReleased` | BOOL | — | 已释放完成 |
| `uOkCups` | UINT | 个 | 当前确认到位的吸盘数 |
| `bDegraded` | BOOL | — | 降级运行中（少吸放行） |
| `bPickFailed` | BOOL | — | 拾取失败（锁存，需 `bReset`） |
| `uPickCount` | UDINT | 次 | 累计成功拾取次数（饱和） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR**：`fbTrigReset / fbTrigPick / fbTrigRelease : R_TRIG`｜`eState : E_DL_VacRingState`（同文件枚举 `eIdle`/`ePicking`/`eHolding`/`eReleasing`/`eDegraded`/`eFault`）｜`fbConfirm : TON`｜`uIdx : UINT`｜`uOk : UINT`｜`uPhase : UINT`（释放分组相）
- **VAR CONSTANT**：`DL_VRC_CUP_MAX : UINT := 8`｜`DL_VRC_VAC_ABS_MAX : REAL := 101.3`｜`DL_VRC_CNT_MAX : UDINT := 16#FFFF_FFFE`｜`DL_VRC_DT_MAX : TIME := T#10S`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `uCupCount = 0 OR > 8` → 故障 0308，全部阀输出 FALSE、**不索引数组**；② `uMinCupsRequired > uCupCount` → 故障 0308（要求吸的比装的还多，参数矛盾）；③ `fVacMin >= 0` 或 `|fVacMin| > 101.3` → 故障 0308（真空门限必须为负且物理可达，填正数会让「真空到位」永远不成立）；④ 吸附确认：逐通道 `auVacuumOk[i] AND afVacuum[i] <= fVacMin`，通道数 `< uMinCupsRequired` 且 `fbConfirm.Q` → **判拾取失败** 0309 + `bPickFailed` 锁存（**这是安全侧**：少吸的料上轴会在加速时掉落）；⑤ `bAllowDegrade = TRUE` 且通道数 `< uCupCount` 但 `>= uMinCupsRequired` → 降级放行 `eDegraded` + `bDegraded` + 信息 01D8（降级是工艺决策，须显式允许）；⑥ 真空值非有限 → 该通道按"未到位"处理 + 故障 0309（**不得当成"到位"**）；⑦ 分组释放：`bReleaseOuterFirst` 决定通道遍历顺序，两相释放（第一相释放一半，`tConfirmTime` 后第二相），**相内不改变吸附判据**；⑧ `CASE` + `ELSE` 兜底 → 030A；⑨ `fbConfirm` / 三个 `R_TRIG` 周期首部无条件刷新；⑩ `uPickCount` 饱和置信息 01D8。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0005_01D8` | 信息 | 降级放行（少吸但达最低要求）/ 拾取计数饱和 |
| `16#0005_01D9` | 信息 | **预留禁用（不得挪用）** |
| `16#0005_0308` | 故障 | 吸盘数或真空门限参数非法，阀输出全部撤销 |
| `16#0005_0309` | 故障 | 吸附确认失败（通道数不足 / 真空值非有限 / 确认超时），锁存 |
| `16#0005_030A` | 故障 | 状态机落 `ELSE` 兜底（非法状态，回 `eIdle` 并撤销阀输出）——**用途固定，不得改作他用** |

- **来源标签**：ROADMAP §10.4 P1 `FB_DL_VacCupRingCtrl`（勾选收口）；多吸盘拾放为公开搬运工程结构，**逐通道确认、少吸失败判据、分组释放相、降级放行、码位 100% 自有**；`I_DL_VacuumGenerator` / `FB_DL_VacuumEjector` 作单机下游，不内联；**零检索**

---

## 4 码位总账（100 槽，逐槽列明；分 5 大段，实测空闲已核）

### 4.1 `16#0001_`（DL_Base / DL_MathData，6 件）

> **信息级开子带 `04xx`**（`02xx` 已满至 `02FF`，见 §0.3），故障级续 `03xx`。

| # | 组件 | 信息-用 | 信息-预留 | 故障-用 | 故障-预留 |
|---|---|---|---|---|---|
| 1 | `FC_DL_DintMsToTod` | `0400` | `0401` | `031E` `031F` | `0320` |
| 2 | `FC_DL_TimeRatioCalc` | `0402` | `0403` | `0321` `0322` | `0323` |
| 3 | `FC_DL_RatioToPwrDb` | `0404` | `0405` | `0324` `0325` | `0326` |
| 4 | `FC_DL_LintToUdintSat` | `0406` | `0407` | `0327` | `0328` `0329` |
| 5 | `FB_DL_BitShiftRegister` | `0408` | `0409` | `032A` `032B` | `032C` |
| 6 | `FC_DL_ModbusRtuFrameCheck` | `040A` | `040B` | `032D` `032E` `032F` | `—` |

**0001_ 段游标终点**：信息级 **`040B`**（下一件起点 `040C`）；故障级 **`032F`**（下一件起点 `0330`）。

> **【R19 终审更正注记（2026-11-16 裁定）】**：本表 #2 `FC_DL_TimeRatioCalc` 与 #3 `FC_DL_RatioToPwrDb` 的「信息-预留」槽（0403 / 0405）与 §3 批次规格冲突——§3 定义两件各有两个信息级实用码。**裁定：编码按 §3 执行**，即 0403 / 0405 为实用槽（非预留），实际文件码位总账已按 0402 用/0403 用、0404 用/0405 用落账；故障侧与本表一致。本表不再改版，以本注记为准（追加式更正，不重写原表）。


### 4.2 `16#0002_`（DL_Algo，组件序号网格，4 件）

| # | 组件 | 序号 CC | 信息-用 | 信息-预留 | 故障-用 | 故障-预留 |
|---|---|---|---|---|---|---|
| 7 | `FB_DL_FlowSqrtExtract` | `27` | `2701` | `2702` | `2710` `2711` | `2712` |
| 8 | `FB_DL_RatioController` | `28` | `2801` | `2802` | `2810` `2811` `2812` | `—` |
| 9 | `FB_DL_LeadLagCompensator` | `29` | `2901` | `2902` | `2910` `2911` | `2912` |
| 10 | `FB_DL_AutoTuneRelay` | `2A` | `2A01` | `2A02` | `2A10` `2A11` `2A12` | `—` |

**0002_ 段游标终点**：组件序号 **`CC = 2A`**（下一件 `CC = 2B`，实测 `2B00~2BFF` 空闲）。

### 4.3 `16#0003_`（DL_Device，4 件）

| # | 组件 | 信息-用 | 信息-预留 | 故障-用 | 故障-预留 |
|---|---|---|---|---|---|
| 11 | `FB_DL_DeviceHealthArbiter` | `016A` | `016B` | `0330` `0331` | `0332` |
| 12 | `FB_DL_ProfinetAlarmDiag` | `016C` | `016D` | `0333` `0334` | `0335` |
| 13 | `FB_DL_EscChuckCurrentMonitor` | `016E` | `016F` | `0336` `0337` `0338` | `—` |
| 14 | `FB_DL_DeviceParamWrite` | `0170` | `0171` | `0339` `033A` `033B` | `—` |

**0003_ 段游标终点**：信息级 **`0171`**（下一件 `0172`）；故障级 **`033B`**（下一件 `033C`）。

### 4.4 `16#0004_`（DL_Motion，4 件）

| # | 组件 | 信息-用 | 信息-预留 | 故障-用 | 故障-预留 |
|---|---|---|---|---|---|
| 15 | `FB_DL_ExternalEncoderScaler` | `01CD` | `01CE` | `02DE` `02DF` `02E0` | `—` |
| 16 | `FB_DL_CamPhaseTrim` | `01CF` | `01D0` | `02E1` `02E2` | `02E3` |
| 17 | `FB_DL_FilmWebCenter` | `01D1` | `01D2` | `02E4` `02E5` | `02E6` |
| 18 | `FB_DL_WindingLayerCounter` | `01D3` | `01D4` | `02E7` `02E8` | `02E9` |

**0004_ 段游标终点**：信息级 **`01D4`**（下一件 `01D5`）；故障级 **`02E9`**（下一件 `02EA`）。

### 4.5 `16#0005_`（DL_Process，2 件）

| # | 组件 | 信息-用 | 信息-预留 | 故障-用 | 故障-预留 |
|---|---|---|---|---|---|
| 19 | `FB_DL_DrumLevelThreeElem` | `01D6` | `01D7` | `0305` `0306` | `0307`（兜底专用） |
| 20 | `FB_DL_VacCupRingCtrl` | `01D8` | `01D9` | `0308` `0309` | `030A`（兜底专用） |

**0005_ 段游标终点**：信息级 **`01D9`**（下一件 `01DA`）；故障级 **`030A`**（下一件 `030B`）。

### 4.6 全局游标汇总（交接收口）

| 段 | 信息级下一可用 | 故障级下一可用 | 本轮占用槽数 |
|---|---|---|---|
| `0001_` | `040C`（04xx 子带） | `0330` | 30 |
| `0002_` | `CC = 2B` | `CC = 2B` | 20 |
| `0003_` | `0172` | `033C` | 20 |
| `0004_` | `01D5` | `02EA` | 20 |
| `0005_` | `01DA` | `030B` | 10 |
| **合计** | | | **100** |

---

## 5 样板原文（R50 教训：**派单必须内嵌原文，不得只写「照既有惯例」**）

以下四段为**逐字符可复制基线**，四批 20 件一律照抄后替换 `<…>` 占位与业务主体，**禁止改造结构**。

### 5.1 样板 A｜注释行样板（`// 中文注释 / English comment` 双语，带单位/域）

```iecst
VAR_INPUT
    bEnable     : BOOL;                       // 使能，FALSE 时输出复位到安全值 / enable, FALSE resets outputs to safe values
    bReset      : BOOL;                       // 上升沿复位故障 / rising edge clears faults
    fSetpoint   : REAL := 0.0;                // 目标值 [mm]，范围 0.0~1000.0 / setpoint [mm], range 0.0~1000.0
    tTimeout    : TIME := T#3S;               // 超时时间 [ms]，0 表示不监控 / timeout [ms], 0 disables monitoring
    uSrcCount   : UINT := 16;                 // 有效源数 [路]，范围 1~16 / valid source count [ch], 1~16
END_VAR
VAR_OUTPUT
    bActive     : BOOL;                       // 运行中标志 / active flag
    eErr        : UDINT;                      // 错误码，0=正常 / error id, 0=ok
    bError      : BOOL;                       // 故障标志，eErr 为故障级时置位 / error flag, TRUE on fault-level eErr
    fActual     : REAL;                       // 实际输出值 [mm] / actual output [mm]
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS   : REAL := 1.0E-6;          // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_MAX_LOOP    : DINT := 10000;           // 循环防死锁上限 [次] / loop guard limit [count]
END_VAR
```

**规则**：① 每行以 `//` 起中文注释，末尾 `/` + 英文；② 物理量必带 `[单位]`，无量纲写 `[无量纲]`/`[dimensionless]`；③ 有域的量必写「范围 a~b」或「域」；④ 常量全大写下划线，同样带单位注释；⑤ 对齐列 = 变量名后至少 2 空格。

### 5.2 样板 B｜错误码声明样板（`eErr : UDINT` + `16#000X_XXXX` 每件 5 槽）

```iecst
VAR_OUTPUT
    eErr    : UDINT;                          // 错误码，0=正常 / error id, 0=ok
    bError  : BOOL;                           // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid  : BOOL;                           // 输出是否有效可用 / output valid flag
END_VAR
```

```iecst
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_<Name> := <DEFAULT_SAFE_VALUE>;         // 故障缺省返回安全值 / fault default safe value
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置输出无效，通过闸门后置位 / preset invalid, set TRUE after gates

// 段 2｜<第一道防御闸> / segment 2, first defence gate
IF <ILLEGAL_CONDITION> THEN
    eErr   := 16#0001_<FAULT_CODE>;           // <中文语义> / <english meaning>
    bError := TRUE;                           // 置故障标志 / raise error flag
    bValid := FALSE;                          // 输出不可用 / output not usable
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF
```

**每件头注释「错误码」段固定 5 行，逐槽列全（含预留）**，格式照抄（**R19 起 `0001_` 段信息级用 `04xx`、故障级用 `03xx`**）：

```iecst
    错误码    : 16#0001_0400 <中文语义>——信息级，正常防御
                16#0001_0401 预留禁用（信息级，不得挪用）
                16#0001_031E <中文语义>——故障级，<出口行为>
                16#0001_031F <中文语义>——故障级，<出口行为>
                16#0001_0320 预留禁用（故障级，不得挪用）
```

**规则**：① 信息级**永不置 `bError`**（头注释明写）；② 预留槽写「预留禁用（不得挪用）」，实现体内**不得**出现该码赋值；③ 故障级码必须出现在头注释**且**在实现体内有唯一赋值点（可追溯，`bError` 置位源必须能在 `eErr` 找到对应码）；④ 单一业务语义上下两个方向**共用一个信息码**时，方向差异写进头注释（照 `FC_DL_RealToLintSat` 022E 惯例）。

### 5.3 样板 C｜头注释结构样板（20 件统一）

```iecst
(*
    <POU_NAME> —— <中文短名>
    ------------------------------------------------------------------
    分类      : DL_<Category> / <子域，如 Signal / Convert / Motion>
    前缀      : <FB_DL_ / FC_DL_>
    版本      : 1.0.0
    溯源      : <T 源标签>；<原始协议 / 公开规范>；
                <借鉴点一句话：只借什么，不借什么>；clean-room 重写，
                未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · <总监 / PLC编程专家>（R19）
    ------------------------------------------------------------------
    功能说明  : <3~6 行：解决什么现场问题 → 输入输出语义 → 核心防御手段 → 与库内相邻件的职责边界>
    错误码    : <5 行，见样板 B>
    状态机    : <有状态机：E_DL_XXXState 的态清单 + 声明「CASE 含 ELSE 兜底」/ 无状态机：R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现>
    采样约定  : <定时器/边沿在周期首部无条件刷新；时间基准来自 tSampleTime 引脚；扫描周期依赖声明>
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)
```

### 5.4 样板 D｜码位总账行（`.st` 内注释形式，紧接头注释「错误码」段，机检正则 `16#[0-9A-F]{4}_[0-9A-F]{4}` 抓取）

```iecst
(*
    码位总账 : 16#0001_0400 用 / 16#0001_0401 预留 ｜ 16#0001_031E 用 / 16#0001_031F 用 / 16#0001_0320 预留
*)
```

**规则**：该行必须包含全部 5 个 `16#XXXX_XXXX` 形态的裸码（带 `16#` 前缀），漏一个即机检不过。

---

## 6 入库自检清单（每件逐条打勾，任一不过禁止入库）

| # | 检查项 | 机检手段 |
|---|---|---|
| 1 | 文件名 = POU 名（含前缀），无拼写漂移 | `ls DL_*/*.st` 对 registry `file_path` |
| 2 | 头注释七项齐全（分类/前缀/版本/溯源/平台/作者/修订 + 功能/错误码/状态机/采样约定） | 正则抓 `分类|前缀|版本|溯源|平台|错误码|状态机|修订` |
| 3 | 声明区每行变量带中文 + 英文同行注释（含 `VAR CONSTANT`） | 逐行 `//` 存在性检查 |
| 4 | 物理量带单位、带域 | 抓 `[` `]` 与「范围/域」 |
| 5 | 零 `GVL` / 零 `VAR_EXTERNAL` / 零 `%I` `%Q` `%M` | `grep -nE "GVL\.|VAR_EXTERNAL|%[IQM][XBWDL]?[0-9]"` |
| 6 | 零厂商库 / 零 `POINTER TO` / 零 `REFERENCE TO` / 零 `SysLibMem` | `grep -nE "Sys[A-Z]\|Tc[A-Z]\|SM3_\|POINTER TO\|REFERENCE TO"` |
| 7 | 有状态机必 `ENUM` + `CASE` + `ELSE` 兜底；无状态机必写 R6 `N/A` 句式 | 抓 `CASE` 内 `ELSE` + `状态机` 段 |
| 8 | `TON`/`R_TRIG`/`F_TRIG` 在主周期无条件刷新（不在 `IF` 内） | 人工逐件（定时器/边沿件：#5 #8 #10 #13 #14 #19 #20） |
| 9 | 浮点无 `=` 判等（全 `ABS(..) < EPS`） | `grep -nE "f[A-Za-z]+ *= *f[A-Za-z]+"` + 人工 |
| 10 | 除法前置防零；数组先判界；循环有守卫；禁 `WHILE` | 人工（#5 掩码、#6 长度闸、#7 分母闸、#9 `a0` 闸、#15 减法顺序、#18 厚度闸、#20 通道闸） |
| 11 | 码位账实一致（5 槽全出现在文件内，预留槽无赋值） | `_verify_r19.py` 反向正则 |
| 12 | 无魔法数（阈值/限幅/超时全在 `VAR CONSTANT` 或引脚） | 抓裸字面量（排除 0/1/2/16# 掩码） |
| 13 | 依赖方向合法（低层不引高层；`I_DL_`/枚举只引用不重声明） | 抓 `I_DL_` 引用清单 + `grep "TYPE E_DL_Ne107Status"` 应只 1 处 |
| 14 | `E_DL_Ne107Status` 唯一属主不重声明（#11 #12 #13 只引用） | 同上 |
| 15 | 子库 `VERSION.md` / `MANUAL_DL_*.md` / 顶层 `CHANGELOG.md` / `README.md` / `LIBRARY_MANUAL.md` 五处同步 | 收口脚本比对计数 |
| 16 | registry / JSONL 同步 + sha256 复验 + `code_segment` 以源码反算 | `closeout_r19.py` |

## 7 禁区表（本轮明确不做，防下轮重复立项）

| 禁区 | 理由 |
|---|---|
| 纯类型复制变体（`FC_DL_AbsLreal` / `FC_DL_MinDint` / `FC_DL_ShlDwordEx` 等） | 无新增防御逻辑、无独立工况语义 = 凑数；`ShlDwordEx/ShrDwordEx` 与存量 `ShlEx/ShrEx` 同义（ROADMAP §22.2 已自标「疑似同义，立项前必过 R61 查重」），**本轮判定为重复，不立** |
| `FC_DL_DtToDintEpoch` / `FC_DL_DintEpochToDt` | R17 已判 P1 延后，须先评估三平台 `DT_TO_DTL` 内链行为（R64 门槛），本轮**不碰** |
| `FC_DL_UdintToLintChk` | UDINT 全域必然装得进 LINT，此「检查」恒为真，属无防御意义的补位，**不立**（由 `FC_DL_LintToUdintSat` 单向收口） |
| `LWord 累加和` / 17 态 PackML 全集第二套 / OEE 三因子第二套 / `E_DL_Ne107Status` 重声明 / 轴状态枚举 | 同 R18 禁区，纪律不变 |
| 回填 `0001_` 段 `0245~028D` 的 63 个碎片洞 | **R65 新纪律**：碎片洞属既有件「预留禁用」域，回填等于挪用他人预留 |
| 存量码位二次改判（把 R15~R17 的 02xx 迁到 04xx） | R18 已做过一次改判专项；再迁一次收益为零、风险极高 |
| `SysFile` / 文件系统 / 指针 / 厂商诊断对象 | 违反零厂商依赖红线 |

---

## 8 双视角进化（Step 6 预置：本轮拟入册规范）

| 编号 | 新规范 | 触发事实 |
|---|---|---|
| **R65** | **码位段内信息级耗尽即开新子带，禁止回填他人预留孔洞** | 实测 `0001_` 信息级 02xx 已满至 `02FF`，R18 交接的 `0245` 是错的；`0245~028D` 只剩 63 个碎片洞且全部位于既有件 3 码块的间隙 |
| **R66** | **同源两份公开资料对同一枚举值语义冲突时，不得二选一硬编码，须并列陈述并归入保守侧** | PROFINET `16#001F`：CODESYS `ProfinetCommon` 记为 `Temporary_fault`，西门子 ET200SP 公开表记为 `Maintenance demanded`（#12 落地） |
| **R67** | **测量类块（自整定/辨识）必须先过「采样密度闸」再出结果** | 继电自整定的公开工程实践要求每半周期 ≥ 6 拍；采样过疏时测到的「振荡」是采样网格产物（#10 落地） |
| **R68** | **折算/缩放链中「先减法后升位」是硬纪律** | 32 位计数器回绕展开若先升 LINT 再相减，回绕会变成巨大正数；#15 已把该行写成注释级警戒 |

**产品经理视角（ROADMAP 下一轮 P0/P1/P2）**：
- **P0**：`0001_` 段码位子带规范回写 `SOURCE_HUNTING_MATRIX` §5 与 `AGENT_EVOLUTION_LOG`（本轮 R65 已实测，须固化为机检规则，防下轮又被口头交接误导）。
- **P1**：`FB_DL_ProfinetAlarmDiag` 的 PN 诊断记录**原始字节解析**层仍缺（需 `ANY`/字节数组 + 记录索引），属下一轮评估项；`E_DL_Ne107Status` 的**反向映射**（聚合结论 → 指示灯/图标序）可作为 HMI 侧组件立项。
- **P2**：LGF 一线剩余几乎全是纯重载（矩阵 §2 预估 145~180，已出 ~110），**建议把 LGF 线正式标注为「结构性收口」**，扩产主线转向 T2-2 LBP 深化与行业池 P1。

---

*ROUND PLAN R19 ｜ 2026-11-16 15:35 ｜ 20 件锁定 ｜ WebSearch 2 次 ｜ 码位 100 槽实测空闲 ｜ 待编码*
