# ROUND PLAN R20 —— 阶段一盘点 + 阶段二狩猎派单（20 件 / 4 批）

> 轮次：**R20** ｜ 生成时间：2026-11-16 ｜ 编制：道莅工控代码库产品总监（daoli-library-director）
> 性质：**纯 T0 轮（快车道）**——20 件全部为 IEC 61131-3 标准语义防御性包装，**T1/T2 检索配额 0（符合 500 冲刺期减配规则 0~1）**，WebSearch **0 次**
> 本文性质：**派单规格书**（可直接编码，禁止再向规格要信息）；`.st` 落盘由批次 1-4 执行

---

## 0 盘点区（Step 1 · 状态读取 · 全部实测，不沿用口头交接）

### 0.1 总库状态（`INDEX_REGISTRY.json` 实解析 + `DL_*/*.st` glob 实测）

| 项 | 实测值 |
|---|---|
| `version` | **2.8.0** |
| `total_components` | **324** |
| `last_updated` | `2026-11-16T17:30:00+08:00` |
| 物理 `.st` 文件数 | **324**（DL_Base **64** / DL_MathData **112** / DL_Algo **36** / DL_Device **57** / DL_Motion **25** / DL_Process **30**，合计 324 ✔ 自洽） |
| 总库完成度 | **324 / 10 000 = 3.24 %** |
| 今日累计 | **120 / 200**（11-16 两轮 100+20） |
| 距 500 冲刺差额 | **176** |
| 语料条数 | 324 条（JSONL，本轮不动） |

### 0.2 R19 遗留 P1 事实确认（仅确认事实，补录在本轮文档线执行）

`MANUAL_DL_Device.md` / `MANUAL_DL_Motion.md` / `MANUAL_DL_Process.md` 三本手册实测**仅收录 R19 批次接口表**（Device 4 件 / Motion 4 件 / Process 2 件抽查命中），**历史组件（57 / 25 / 30 件）接口表全部缺失**——R19 遗留 P1「历史件接口表补录」事实成立，本轮只登记，不在编码线处理。

### 0.3 ⚠ 码位分段裁定（R61/R75 教训执行：游标当场实测，禁信口头交接）

以全库 324 个 `.st` 源码为唯一事实源实测（正则 `16#000[1-5]_[0-9A-Fa-f]{4}`，去重后 1109 个「段+偏移」占用）：

| 段 | 信息级（<0x300 及 04xx 子带）实测 | 故障级（≥0x300）实测 | 本轮裁定 |
|---|---|---|---|
| `16#0001_`（Base/MathData） | 01xx n=180（max 01FF）｜02xx n=193（**满带**，max 02FF）｜**04xx 子带 n=12，已用 0400~040B（全为 R19 件）** | 03xx n=48，**max 032F**（R19 件用至 032F） | 信息续 **`040C`** 起；故障续 **`0330`** 起 |
| `16#0002_`（Algo） | CC 网格已用 01~2A（R19 用 27~2A）+ 公共码 00xx（0001~0005）；`0002_8011` 实查**仅存在于 PdiReadScheduler 头注释示例**，非码位占用 | — | 本轮无 Algo 件，不占用 |
| `16#0003_`（Device） | 01xx max 0171 | 03xx max 033B | 本轮无 Device 件 |
| `16#0004_`（Motion） | 01xx max 01D4 | 02xx max 02E9 | 本轮无 Motion 件 |
| `16#0005_`（Process） | 01xx max 01D9 | 03xx max 030A | 本轮无 Process 件 |

**R20 裁定**：本轮 20 件全部落 `16#0001_` 段（18 件 MathData + 2 件 Base），信息级 5 槽/件中 2 槽（`040C`~`0433`）、故障级 3 槽/件（`0330`~`036B`），逐件 5 槽 = **2 信息级（1~2 用，余预留禁用）+ 3 故障级（1~3 用，余预留禁用）**。全程不回填 01xx/02xx/03xx 碎片孔洞（R65 纪律）。

---

## 1 R20 20 目标一览（锁定）

| # | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批 |
|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_DtToDintEpoch` | DL_MathData | FC_DL_ | DT → Unix 纪元秒（Y2038 域告警，MES/日志时间戳标准化） | T0-5（ROADMAP §22.2 P0 未结项） | M | 1 |
| 2 | `FC_DL_DintEpochToDt` | DL_MathData | FC_DL_ | Unix 纪元秒 → DT（与 #1 构成双向对） | T0-5（ROADMAP §22.2 P0 未结项） | M | 1 |
| 3 | `FC_DL_DateToDintDays` | DL_MathData | FC_DL_ | DATE → 自 1970-01-01 起天数（保质期/台账天数化） | T0-5 | L | 1 |
| 4 | `FC_DL_DintDaysToDate` | DL_MathData | FC_DL_ | 天数 → DATE（#3 逆运算，交付期/保养日还原） | T0-5 | L | 1 |
| 5 | `FC_DL_UdintToLintChk` | DL_MathData | FC_DL_ | UDINT→LINT 升位验真（round-trip 复核拦平台符号扩展错误） | T0-5（ROADMAP §22.2 P1 未结项） | M | 1 |
| 6 | `FC_DL_WordToIntSat` | DL_MathData | FC_DL_ | WORD→INT 双语义落地（补码解释或上饱和，Modbus 16 位量程） | T0-5 | M | 2 |
| 7 | `FC_DL_DwordToIntSat` | DL_MathData | FC_DL_ | DWORD→INT 降位饱和（长计数器进 16 位 HMI） | T0-5 | L | 2 |
| 8 | `FC_DL_LwordToLintSat` | DL_MathData | FC_DL_ | LWORD→LINT 上饱和（无符号 64 位大计数落有符号域，与 `LintToUdintSat` 对偶） | T0-5 | M | 2 |
| 9 | `FC_DL_BcdToByte` | DL_MathData | FC_DL_ | 2 位半字节 BCD（BYTE 容器 0~99）解码（拨码开关组态位） | T0-5（BCD 族 BYTE 容器缺位） | L | 2 |
| 10 | `FC_DL_ByteToBcd` | DL_MathData | FC_DL_ | 0~99 → 2 位 BCD 编码（#9 逆运算，写回拨码/仪表组态字） | T0-5 | L | 2 |
| 11 | `FC_DL_TodAddWrap` | DL_MathData | FC_DL_ | TOD + TIME 午夜回绕加法（排程偏移/班次推算） | T0-2/T0-5（TOD 算术变体缺位） | M | 3 |
| 12 | `FC_DL_TodDiffWrap` | DL_MathData | FC_DL_ | 两 TOD 之差（跨零点为正，班次工时/节拍间隔） | T0-2/T0-5 | M | 3 |
| 13 | `FC_DL_SwapBytes64` | DL_MathData | FC_DL_ | LWORD 全字节逆序（EtherCAT/CANopen 64 位计数器字节序） | T0-7（字节序族 64 位缺位） | M | 3 |
| 14 | `FC_DL_DintToStringTrim` | DL_MathData | FC_DL_ | DINT→STRING 并修剪平台前导空格 + 长度钳位（报文/CSV 防混入空格） | T0-5/T0-6（字符串化变体缺位） | M | 3 |
| 15 | `FC_DL_LrealToStringTrim` | DL_MathData | FC_DL_ | LREAL→STRING（非有限值统一文本 + 空格修剪，趋势/报警序列化跨平台一致） | T0-4/T0-5 | M | 3 |
| 16 | `FC_DL_DateAddDays` | DL_MathData | FC_DL_ | DATE + nDays → DATE（保质期/交期/下次保养日推算） | T0-5 | M | 4 |
| 17 | `FC_DL_DateDiffDays` | DL_MathData | FC_DL_ | 两 DATE 之差天数（可负，保质期余量/超期判定原子） | T0-5 | L | 4 |
| 18 | `FC_DL_TimeAbsSat` | DL_MathData | FC_DL_ | TIME 绝对值（负 TIME 平台歧义统一口径，−MAX−1 防溢出） | T0-2（R55 负 TIME 教训原子化） | L | 4 |
| 19 | `FC_DL_LeapYearChk` | DL_Base | FC_DL_ | 闰年判定原子（4/100/400 三级纯整数判定，质保/维护周期闰日修正） | T0-5（库内 YearWindowCheck 判定原子化复用） | L | 4 |
| 20 | `FB_DL_SemaMutex` | DL_Base | FB_DL_ | IEC 标准 SEMA 互斥防御包装（占用超时强制归还，防任务崩溃死锁） | T0 标准功能块（SEMA，库内未包装） | M | 4 |

**分布**：DL_MathData 18（#1~#18）｜ DL_Base 2（#19~#20）＝ **20**
**类型**：FC 19 ｜ FB 1 ｜ **复杂度**：H 0 ｜ M 10 ｜ L 10
**凑数审查**：① BCD Word/Udint 容器已占（R9/R16），BYTE 2 位拨码容器为谱系真缺位；② SwapBytes16/32 已占，64 位为真缺位；③ TIME 算术族已占，TOD 算术（回绕语义）与 TIME 绝对值为独立语义；④ 字符串九函数为「取/拼/查」族，字符串化（ToString）+ 非有限文本统一为独立语义；⑤ `UdintToLintChk` 按 R19 委托补语义——UDINT→LINT 数学上恒无损，但**平台隐式经 32 位有符号中间量转换会把 ≥2^31 值符号扩展成负数**，本件 round-trip 验真拦该错，非凑数（规格 §3.1 #5）；⑥ `ShlDwordEx/ShrDwordEx`（§22.2 P2 疑似与存量同义）**本轮不立项**，维持查重警示。

---

## 2 四批划分（每批 5 件，同子库同类内聚）

| 批 | 主题 | 件 | 码位（信息 2/件 + 故障 3/件） |
|---|---|---|---|
| 批 1 | **日历纪元族 + 升位验真**（§22.2 P0/P1 结项） | #1-5 | 信息 `040C~0415` ／ 故障 `0330~033E` |
| 批 2 | **饱和降位族 + BCD BYTE 容器** | #6-10 | 信息 `0416~041F` ／ 故障 `033F~034D` |
| 批 3 | **TOD 回绕算术 + 字节序 64 位 + 字符串化** | #11-15 | 信息 `0420~0429` ／ 故障 `034E~035C` |
| 批 4 | **日期运算 + 时间口径 + 闰年原子 + 标准 FB** | #16-20 | 信息 `042A~0433` ／ 故障 `035D~036B` |

**全局强制（逐件不再重复）**：浮点判等 `ABS(a-b) < DL_FLOAT_EPS`；除法前置防零；禁裸数值（一律 `VAR CONSTANT` 或引脚）；`R_TRIG`/`TON` 无条件前置刷新；禁 `WHILE`（本批全部可用 `IF`+算术或定长 `FOR` 实现）；纯函数头注释状态机段用 R6 N/A 句式；中英双语同行注释照 §4 样板；预留槽写 `预留禁用（不得挪用）` 且实现体不得出现该码赋值。
**日历族编译门槛预评估（§22.3 债务，批 1 编码前必做）**：#1~#4 #11 #12 #16 #17 涉 DT/DATE/TOD 内建链，编码前先在规格附注的「平台基准路径」上做门槛评估；平台无直接内建（如 `DT_TO_DINT`）时按规格给出的「天数×86400 + 当日秒」先判后算合成路径，禁止未评估直接派单。

---

## 3 批次需求规格（引脚级，可直接编码）

> 接口约定：FUNCTION 返回主值；`eErr : UDINT`（0=正常）+ `bError`（故障级 TRUE）+ `bValid`（返回值可用）三件套每件必带；错误码全部 `16#0001_XXXX` 格式。

### 3.1 批 1（日历纪元族 + 升位验真）

#### #1 `FC_DL_DtToDintEpoch` —— DT → Unix 纪元秒
- **分类**：DL_MathData / Convert ｜ **前缀**：`FC_DL_` ｜ **类型**：FUNCTION → `DINT` ｜ **复杂度**：M
- **引脚**：IN `dtIn : DATE_AND_TIME`（输入时刻，有效域 1970-01-01~2038-01-19T03:14:07）；OUT 返回纪元秒 [s] + 三件套。
- **VAR CONSTANT**：`DL_EPOCH_SEC_MAX : DINT := 2147483647`（DINT 秒域上限 = Y2038 2038-01-19T03:14:07Z）｜`DL_Y2038_WARN_SEC : DINT := 2051222400`（Y2038 告警阈值 = 2035-01-01）｜`DL_SEC_PER_DAY : DINT := 86400`
- **边界安全条件**：① 优先委托平台内建 `DT_TO_DINT`（秒口径），**平台缺该内建时走合成路径**：先经 `DT_TO_DATE`/`DT_TO_TOD` 取天数与当日秒，`nDays × 86400 + nSecOfDay`（先判后算，乘前判 `nDays < DL_EPOCH_SEC_MAX / DL_SEC_PER_DAY` 防溢出）；② `dtIn` 早于纪元 → 故障 0330，返回 0、`bValid := FALSE`；③ 结果 > `DL_EPOCH_SEC_MAX` → 饱和至上限 + 故障 0331（Y2038 溢出不容静默）；④ 结果 ≥ `DL_Y2038_WARN_SEC` → 信息 040C（Y2038 邻近告警，正常可用）；⑤ 无状态机（R6 N/A 句式）。
- **码位 5 槽**：`16#0001_040C` 信息（Y2038 邻近告警）/ `16#0001_040D` 预留禁用 ｜ `16#0001_0330` 故障（dtIn 早于纪元）/ `16#0001_0331` 故障（结果超 DINT 秒域，已饱和）/ `16#0001_0332` 预留禁用
- **来源标签**：T0-5 类型转换（ROADMAP §22.2 P0 未结项）；语义由 IEC 61131-3 DT 定义 + Unix 纪元公开约定，委托内建，零检索

#### #2 `FC_DL_DintEpochToDt` —— Unix 纪元秒 → DT
- **分类**：DL_MathData / Convert ｜ **类型**：FUNCTION → `DATE_AND_TIME` ｜ **复杂度**：M
- **引脚**：IN `nEpochSec : DINT`（纪元秒 [s]，有效域 0~2147483647）；OUT 三件套。
- **VAR CONSTANT**：`DL_EPOCH_SEC_MAX : DINT := 2147483647`｜`DL_EPOCH_SEC_ZERO : DINT := 0`
- **边界安全条件**：① `nEpochSec < 0` → 故障 0333，返回 `DT#1970-01-01-00:00:00`、`bValid := FALSE`；② `nEpochSec > DL_EPOCH_SEC_MAX` → 故障 0334（Y2038 超域），返回纪元零值、`bValid := FALSE`（**不饱和到错误时刻**，还原方向宁可不输出不可输出错值）；③ 域内委托 `DINT_TO_DT`，平台缺内建走「天数 = n / 86400、当日秒 = n MOD 86400（两操作数先判非负，余数口径安全）→ DINT_TO_DATE + DINT_TO_TOD 合成」；④ 无状态机（R6 N/A 句式）。
- **码位 5 槽**：`16#0001_040E` 信息（预留 1 用 1 备：首次转换即边界秒 0 或 MAX 时提示）/ `16#0001_040F` 预留禁用 ｜ `16#0001_0333` 故障（负纪元秒）/ `16#0001_0334` 故障（超 Y2038 域）/ `16#0001_0335` 预留禁用
- **来源标签**：T0-5（ROADMAP §22.2 P0 未结项，与 #1 双向对）；零检索

#### #3 `FC_DL_DateToDintDays` —— DATE → 天数
- **分类**：DL_MathData / Convert ｜ **类型**：FUNCTION → `DINT` ｜ **复杂度**：L
- **引脚**：IN `dateIn : DATE`（有效域 1970-01-01~平台 DATE 上限）；OUT 三件套。
- **VAR CONSTANT**：`DL_DATE_DAYS_MIN : DINT := 0`（纪元日）｜`DL_DATE_DAYS_MAX : DINT := 65535`（保守口径 = 平台 DATE 以 UINT 天数承载的上限；编码前按编译门槛预评估实测锚定，规格偏离留档）
- **边界安全条件**：① 委托内建 `DATE_TO_DINT`（天数口径）；平台缺内建按「DT 路径」评估；② `dateIn` 早于纪元 → 故障 0336，返回 0；③ 结果 > `DL_DATE_DAYS_MAX` → 信息 040A?（占用注意：本件信息槽 0410/0411）→ 信息 0410（超保守容器口径，按实测锚定值钳位）+ `bValid := TRUE`；④ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_0410` 信息（超保守天数口径已钳位）/ `16#0001_0411` 预留禁用 ｜ `16#0001_0336` 故障（早于纪元）/ `16#0001_0337` 故障（DATE 输入非法/容器溢出）/ `16#0001_0338` 预留禁用
- **来源标签**：T0-5；零检索

#### #4 `FC_DL_DintDaysToDate` —— 天数 → DATE
- **分类**：DL_MathData / Convert ｜ **类型**：FUNCTION → `DATE` ｜ **复杂度**：L
- **引脚**：IN `nDays : DINT`（0~`DL_DATE_DAYS_MAX`）；OUT 三件套。
- **边界安全条件**：① `nDays < 0` → 故障 0339，返回纪元日、`bValid := FALSE`；② `nDays > DL_DATE_DAYS_MAX` → 故障 033A（超平台容器域），返回纪元日、`bValid := FALSE`；③ 域内委托 `DINT_TO_DATE`；④ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_0412` 信息（预留 1 用 1 处）/ `16#0001_0413` 预留禁用 ｜ `16#0001_0339` 故障（负天数）/ `16#0001_033A` 故障（超容器域）/ `16#0001_033B` 预留禁用
- **来源标签**：T0-5（#3 双向对）；零检索

#### #5 `FC_DL_UdintToLintChk` —— UDINT → LINT 升位验真
- **分类**：DL_MathData / Convert ｜ **类型**：FUNCTION → `LINT` ｜ **复杂度**：M
- **引脚**：IN `uIn : UDINT`（0~4294967295）；OUT `eErr/bError/bValid` + `bRoundTripFail : BOOL`（round-trip 复核失败标志）。
- **VAR CONSTANT**：`DL_UDINT_MAX : UDINT := 16#FFFF_FFFF`
- **边界安全条件**：① 升位委托 `UDINT_TO_LINT`（数学上恒无损）；② **round-trip 验真**：`LINT_TO_UDINT(liOut) <> uIn` → 判平台把中间量经 32 位有符号路径做了错误符号扩展 → 故障 033C、`bRoundTripFail := TRUE`、`bValid := FALSE`（此为 R56「类型转换异构整改 D-13」的验真式延伸，是本件的独立防御点而非重载）；③ 验真只在**首次调用或每次调用抽查**两种模式（`bCheckEveryCall` 引脚，默认 TRUE），FALSE 时跳过复核降开销 + 信息 0414；④ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_0414` 信息（`bCheckEveryCall = FALSE` 已跳过复核）/ `16#0001_0415` 预留禁用 ｜ `16#0001_033C` 故障（round-trip 验真失败，平台符号扩展错误）/ `16#0001_033D` 故障（预留）/ `16#0001_033E` 预留禁用
- **来源标签**：T0-5（ROADMAP §22.2 P1 未结项）；立项理由已过凑数审查（见 §1 注⑤）；零检索

### 3.2 批 2（饱和降位族 + BCD BYTE 容器）

#### #6 `FC_DL_WordToIntSat` —— WORD → INT 双语义落地
- **分类**：DL_MathData / Convert ｜ **类型**：FUNCTION → `INT` ｜ **复杂度**：M
- **引脚**：IN `uIn : WORD`（0~65535）；`bTwosComplement : BOOL := FALSE`（TRUE = 32768~65535 按补码解释为 −32768~−1；FALSE = 饱和到 32767）；OUT `eErr/bError/bValid` + `bInterpreted : BOOL`（发生了补码解释或饱和）。
- **VAR CONSTANT**：`DL_INT_MAX_AS_WORD : WORD := 32767`｜`DL_TWOS_BIAS : DINT := 65536`（补码解释偏移量）
- **边界安全条件**：① `uIn <= DL_INT_MAX_AS_WORD` → 域内委托 `WORD_TO_INT`，零开销；② `bTwosComplement = TRUE` 且超域 → `nOut := DINT(WORD_TO_DINT(uIn)) - DL_TWOS_BIAS`（先升 DINT 再减，**禁在 INT 域内做减法**防中途溢出）+ 信息 0416 + `bInterpreted := TRUE`；③ `bTwosComplement = FALSE` 且超域 → 饱和 32767 + 信息 0417；④ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_0416` 信息（按补码解释为负值）/ `16#0001_0417` 信息（已饱和至 32767）/ ｜ `16#0001_033F` 故障（预留）/ `16#0001_0340` 故障（预留）/ `16#0001_0341` 故障（预留）——本件三种越界出路均为安全侧信息级（值仍可用），故障级全预留
- **来源标签**：T0-5；Modbus 16 位无符号量程 → 有符号工程量是现场高频口径；零检索

#### #7 `FC_DL_DwordToIntSat` —— DWORD → INT 降位饱和
- **分类**：DL_MathData / Convert ｜ **类型**：FUNCTION → `INT` ｜ **复杂度**：L
- **引脚**：IN `uIn : DWORD`（0~4294967295）；`bRequireLossless : BOOL := FALSE`（TRUE = 发生饱和即判故障，R19 `LintToUdintSat` 同模式）；OUT 三件套 + `bSatHigh : BOOL`。
- **边界安全条件**：① `uIn <= 32767` 域内委托；② 超域 → 饱和 32767 + 信息 0418 + `bSatHigh := TRUE`；③ `bRequireLossless AND bSatHigh` → 故障 0342、`bValid := FALSE`；④ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_0418` 信息（超域已饱和 32767）/ `16#0001_0419` 预留禁用 ｜ `16#0001_0342` 故障（要求无损却发生饱和）/ `16#0001_0343` 故障（预留）/ `16#0001_0344` 故障（预留禁用）
- **来源标签**：T0-5；长计数器低位/累计值进 16 位 HMI 高频口径；零检索

#### #8 `FC_DL_LwordToLintSat` —— LWORD → LINT 上饱和
- **分类**：DL_MathData / Convert ｜ **类型**：FUNCTION → `LINT` ｜ **复杂度**：M
- **引脚**：IN `uIn : LWORD`（0~2^64−1）；`bRequireLossless : BOOL := FALSE`；OUT 三件套 + `bSatHigh : BOOL`。
- **VAR CONSTANT**：`DL_LINT_MAX_AS_LWORD : LWORD := 2_147_483_647_000_000_000`（LINT 上限的无符号形态；编码时以字面量精确值 `9223372036854775807` 为准，此处为可读性分段，实现取精确值）
- **边界安全条件**：① 比较一律在 LWORD/LINT 字面量常量间进行，**禁隐式跨符号域比较**（R56 纪律）；② 超域 → 饱和至 `LINT_MAX` + 信息 041A；③ 无损模式 → 故障 0345；④ 域内委托 `LWORD_TO_LINT`（域外调用是回绕行为不一致根源）；⑤ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_041A` 信息（超 LINT 域已饱和）/ `16#0001_041B` 预留禁用 ｜ `16#0001_0345` 故障（要求无损却发生饱和）/ `16#0001_0346` 故障（预留）/ `16#0001_0347` 故障（预留禁用）
- **来源标签**：T0-5（与 R19 `FC_DL_LintToUdintSat` 构成 64 位交叉域对偶）；零检索

#### #9 `FC_DL_BcdToByte` —— 2 位 BCD 解码（BYTE 容器）
- **分类**：DL_MathData / Convert ｜ **类型**：FUNCTION → `USINT` ｜ **复杂度**：L
- **引脚**：IN `uBcd : BYTE`（每半字节 0~9，合计 0~99，拨码开关组态位口径）；OUT 三件套。
- **边界安全条件**：① 半字节校验：`(uBcd AND 16#0F) > 9 OR SHR(uBcd, 4) > 9` → 故障 0348，返回 0、`bValid := FALSE`（**先判后算**，域外调用平台 BCD 解码行为不一）；② 域内委托平台内建 `BCD_TO_BYTE`；平台缺内建时 `uHi*10 + uLo` 半字节乘加合成（属容器校验后合成，非重实现数学内核，规格留档）；③ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_041C` 信息（预留 1 用 1 处，建议：BCD 值 = 99 满量程提示或留空）/ `16#0001_041D` 预留禁用 ｜ `16#0001_0348` 故障（半字节 > 9，非法 BCD）/ `16#0001_0349` 故障（预留）/ `16#0001_034A` 故障（预留禁用）
- **来源标签**：T0-5（BCD 族容器谱系：Word 4 位 R9 / Udint 8 位 R16 已占，BYTE 2 位拨码容器为真缺位）；零检索

#### #10 `FC_DL_ByteToBcd` —— 2 位 BCD 编码
- **分类**：DL_MathData / Convert ｜ **类型**：FUNCTION → `BYTE` ｜ **复杂度**：L
- **引脚**：IN `uIn : USINT`（0~99）；OUT 三件套。
- **边界安全条件**：① `uIn > 99` → 故障 034B，返回 16#99（满量程 BCD）、`bValid := FALSE`（拨码写回方向宁满量程不出半错位值）；② 域内委托 `BYTE_TO_BCD`，平台缺内建按「商 10 / 余 10 拼半字节」合成（先判后算）；③ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_041E` 信息（预留 1 用 1 处）/ `16#0001_041F` 预留禁用 ｜ `16#0001_034B` 故障（输入 > 99，已按满量程 16#99 兜底）/ `16#0001_034C` 故障（预留）/ `16#0001_034D` 故障（预留禁用）
- **来源标签**：T0-5（#9 双向对）；零检索

### 3.3 批 3（TOD 回绕算术 + 字节序 64 位 + 字符串化）

#### #11 `FC_DL_TodAddWrap` —— TOD + TIME 午夜回绕加法
- **分类**：DL_MathData / TimeArith ｜ **类型**：FUNCTION → `TOD` ｜ **复杂度**：M
- **引脚**：IN `todIn : TOD`（当日时刻）；`tOffset : TIME`（偏移，可正可负 [ms]，TIME 平台为 32 位容器）；OUT `eErr/bError/bValid` + `bWrapped : BOOL`（本拍发生午夜回绕）+ `nWrapCircles : INT`（回绕圈数，可负）。
- **VAR CONSTANT**：`DL_TOD_DAY_MS : DINT := 86400000`（当日毫秒）
- **边界安全条件**：① 统一先判后算：`nSum := TOD_TO_DINT(todIn) + TIME_TO_DINT(tOffset)`（显式标准转换，禁隐式）；② 回绕**禁用 MOD**（负数取余三平台不一致，R11 RolloverCounter 纪律），改条件加减：`IF nSum >= DL_TOD_DAY_MS THEN nSum := nSum - DL_TOD_DAY_MS * k`（k = 整商，用 `nSum / DL_TOD_DAY_MS` 取整商——操作数为正，取整商口径安全）；负向同理 `WHILE nSum < 0` **禁用**，用单算式 `nSum := nSum + DL_TOD_DAY_MS * (1 - nSum / DL_TOD_DAY_MS)`（仅 |偏移| < 一日时成立，超一日先判故障 034E）；③ `nSum` 落域后委托 `DINT_TO_TOD` 返回；④ `tOffset` 模长 ≥ 一日且未先钳位 → 故障 034E（规格主动收窄：排程偏移场景不存在跨日以上偏移，宁报不用）；⑤ 回绕发生 → 信息 0420 + `bWrapped := TRUE`；⑥ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_0420` 信息（发生午夜回绕，`bWrapped` 可查）/ `16#0001_0421` 预留禁用 ｜ `16#0001_034E` 故障（偏移模长超一日，超出本件收窄域）/ `16#0001_034F` 故障（合成路径中间量非有限/溢出）/ `16#0001_0350` 故障（预留禁用）
- **来源标签**：T0-2/T0-5（TIME 算术族已占，TOD 回绕算术为独立语义）；零检索

#### #12 `FC_DL_TodDiffWrap` —— 两 TOD 之差（跨零点为正）
- **分类**：DL_MathData / TimeArith ｜ **类型**：FUNCTION → `TIME` ｜ **复杂度**：M
- **引脚**：IN `todEarlier : TOD`（区间起点）；`todLater : TOD`（区间终点）；OUT `eErr/bError/bValid` + `bCrossMidnight : BOOL`（跨零点判定）。
- **边界安全条件**：① `nDiff := TOD_TO_DINT(todLater) - TOD_TO_DINT(todEarlier)`；② `nDiff < 0` → 跨零点：`nDiff := nDiff + DL_TOD_DAY_MS`（先判后加，单次足够，两 TOD 同日内差值模长 < 一日）+ 信息 0422 + `bCrossMidnight := TRUE`；③ 返回 `DINT_TO_TIME(nDiff)`（域 0~86399999 ms）；④ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_0422` 信息（跨零点区间，已按 +一日折算）/ `16#0001_0423` 预留禁用 ｜ `16#0001_0351` 故障（预留）/ `16#0001_0352` 故障（预留禁用）/ `16#0001_0353` 故障（预留禁用）
- **来源标签**：T0-2/T0-5（班次工时/节拍间隔高频口径；`FB_DL_TimeWindowCheck` 是窗判定 FB，不提供原子差值）；零检索

#### #13 `FC_DL_SwapBytes64` —— LWORD 全字节逆序
- **分类**：DL_MathData / Convert ｜ **类型**：FUNCTION → `LWORD` ｜ **复杂度**：M
- **引脚**：IN `liIn : LWORD`；OUT 三件套。
- **边界安全条件**：① 本件为全域双射，无非法输入，**信息/故障槽全预留**（惯例允许）；② 实现路径：拆高低 32 位 `DW_HI := LWORD_TO_DWORD(SHR(liIn, 32))`、`DW_LO := LWORD_TO_DWORD(liIn AND 16#0000_0000_FFFF_FFFF)`，各自委托库内 `FC_DL_SwapBytes32`，再 `SWAP(DW_LO)` 进高位 + `SWAP(DW_HI)` 进低位合成——**委托库内既有件不重实现**（同库资产复用即合规，R12 PortDiagBoard 先例）；③ 掩码常量禁裸值；④ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_0424` 信息（预留禁用——全双射无信息出口）/ `16#0001_0425` 预留禁用 ｜ `16#0001_0354`~`16#0001_0356` 故障（三槽全预留禁用）
- **来源标签**：T0-7（SwapBytes16/32 已占，64 位为真缺位）；零检索

#### #14 `FC_DL_DintToStringTrim` —— DINT → STRING 防御字符串化
- **分类**：DL_MathData / Convert ｜ **类型**：FUNCTION → `STRING` ｜ **复杂度**：M
- **引脚**：IN `nIn : DINT`；OUT `eErr/bError/bValid` + `bTrimmed : BOOL`（修剪了前导空格）+ `bTruncated : BOOL`（超目标长度截断）。
- **VAR CONSTANT**：`DL_STR_TARGET_MAX : USINT := 31`（默认返回缓冲目标长度；引脚化 `uTargetMax` 允许 1~255）｜`DL_STR_CAP_MAX : USINT := 255`（STRING 型上限，R49 口径）
- **边界安全条件**：① 委托内建 `DINT_TO_STRING`；② 平台惯例前导空格填充 → 逐字符定位首个非空格后 `MID` 截取（委托库内 T0-6 家族语义），`bTrimmed := TRUE` + 信息 0426；③ `uTargetMax` 引脚钳位 1~255，超 255 → 故障 0357；④ 截断先置 `bTruncated` 再写入（**R37 四步样板**：LEN 一次锁存 → 宽度比较 → 标志先于任何写入 → 按 `bAllowTrunc` 分路，引脚 `bAllowTrunc : BOOL := FALSE`，TRUE 才允许截断否则故障 0358）；⑤ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_0426` 信息（修剪前导空格）/ `16#0001_0427` 信息（发生截断且 bAllowTrunc=TRUE）/ ｜ `16#0001_0357` 故障（`uTargetMax` 超 255）/ `16#0001_0358` 故障（需截断但 `bAllowTrunc = FALSE`，返回空串）/ `16#0001_0359` 故障（预留禁用）
- **来源标签**：T0-5/T0-6（字符串九函数为「取/拼/查」族，字符串化 + 填充防御为独立语义）；零检索

#### #15 `FC_DL_LrealToStringTrim` —— LREAL → STRING（非有限值统一文本）
- **分类**：DL_MathData / Convert ｜ **类型**：FUNCTION → `STRING` ｜ **复杂度**：M
- **引脚**：IN `fIn : LREAL`；`bAllowTrunc : BOOL := FALSE`；OUT `eErr/bError/bValid` + `bNonFinite : BOOL` + `bTrimmed` + `bTruncated`。
- **边界安全条件**：① 非有限输入（`fIn <> fIn` 判 NaN，或 `ABS(fIn) >= 1.79E308` 口径判 ±Inf，两判据分开置位）→ **不做内建转换**（平台对 NaN/Inf 文本不一：'NaN'/'INF'/乱码），统一输出 `'NaN'` / `'Inf+'` / `'Inf-'` 字面量 + 信息 0428 + `bNonFinite := TRUE` + `bValid := TRUE`（统一文本是可用输出，不是故障）；② 有限值 → 委托 `LREAL_TO_STRING` + 空格修剪（同 #14）+ 截断四步样板（R37）；③ `bAllowTrunc = FALSE` 且需截断 → 故障 035A；④ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_0428` 信息（非有限值已映射统一文本）/ `16#0001_0429` 信息（修剪空格或截断发生）/ ｜ `16#0001_035A` 故障（需截断但 `bAllowTrunc = FALSE`）/ `16#0001_035B` 故障（预留）/ `16#0001_035C` 故障（预留禁用）
- **来源标签**：T0-4/T0-5（趋势记录/报警文本数值序列化跨平台一致口径）；零检索

### 3.4 批 4（日期运算 + 时间口径 + 闰年原子 + 标准 FB）

#### #16 `FC_DL_DateAddDays` —— DATE + nDays
- **分类**：DL_MathData / TimeArith ｜ **类型**：FUNCTION → `DATE` ｜ **复杂度**：M
- **引脚**：IN `dateIn : DATE`；`nDays : DINT`（偏移天数，可负，有效域 −36500~36500 ≈ ±100 年）；OUT 三件套 + `bClamped : BOOL`。
- **VAR CONSTANT**：`DL_DAYS_SPAN_MAX : DINT := 36500`（±100 年跨度钳位）
- **边界安全条件**：① 统一走天数路径：`nBase := DATE_TO_DINT(dateIn)`，`nOut := nBase + nDays`——**先判后算**：`nDays` 域钳位 `−36500~36500`（超域 → 信息 042A + `bClamped := TRUE`）；`nBase + nDays` 溢出预判用减法比较（`nDays > 0 AND nOut 候选 < nBase` 不可判前，改判 `nDays > DL_DATE_DAYS_MAX - nBase` 正向 / `nDays < DL_DATE_DAYS_MIN - nBase` 负向）；② 结果 < 0 → 故障 035D（早于纪元），返回纪元日、`bValid := FALSE`；③ 结果 > `DL_DATE_DAYS_MAX`（#3 同口径常量）→ 故障 035E（超容器域）；④ 域内委托 `DINT_TO_DATE`；⑤ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_042A` 信息（`nDays` 超 ±36500 已钳位）/ `16#0001_042B` 预留禁用 ｜ `16#0001_035D` 故障（结果早于纪元）/ `16#0001_035E` 故障（结果超 DATE 容器域）/ `16#0001_035F` 故障（预留禁用）
- **来源标签**：T0-5；零检索

#### #17 `FC_DL_DateDiffDays` —— 两 DATE 之差
- **分类**：DL_MathData / TimeArith ｜ **类型**：FUNCTION → `DINT` ｜ **复杂度**：L
- **引脚**：IN `dateFrom : DATE`；`dateTo : DATE`；OUT `eErr/bError/bValid` + `bNegative : BOOL`（`dateTo < dateFrom` 时差值为负）。
- **边界安全条件**：① `nDiff := DATE_TO_DINT(dateTo) - DATE_TO_DINT(dateFrom)`（两 DATE 均在容器域内，差值模长 < 65536，DINT 承载无溢出，规格留档论证）；② 负值合法输出（保质期余量语义），`bNegative := TRUE` + 信息 042C；③ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_042C` 信息（差值为负，已如实输出）/ `16#0001_042D` 预留禁用 ｜ `16#0001_0360` 故障（预留）/ `16#0001_0361` 故障（预留禁用）/ `16#0001_0362` 故障（预留禁用）
- **来源标签**：T0-5（#16 的判定原子对）；零检索

#### #18 `FC_DL_TimeAbsSat` —— TIME 绝对值
- **分类**：DL_MathData / TimeArith ｜ **类型**：FUNCTION → `TIME` ｜ **复杂度**：L
- **引脚**：IN `tIn : TIME`（可负，TIME 平台实现为 DINT ms，R55 教训口径）；OUT 三件套 + `bNegative : BOOL`。
- **边界安全条件**：① `TIME_TO_DINT(tIn) >= 0` → 直通返回；② 负值 → `nAbs := -nIn`，但 `nIn = -2147483648`（−MAX−1 案）时负取正溢出 → **先判**：`nIn <= DL_TIME_MS_NEG_MAX := -2147483647` 边界外 → 饱和至 `T#49D17H2M47S295MS` + 故障 0363、`bValid := FALSE`；③ 正常负值取绝对值 + 信息 042E + `bNegative := TRUE`；④ `DINT_TO_TIME` 显式回转；⑤ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_042E` 信息（输入为负已取绝对值）/ `16#0001_042F` 预留禁用 ｜ `16#0001_0363` 故障（−MAX−1 绝对值不可表达，已饱和至上限）/ `16#0001_0364` 故障（预留）/ `16#0001_0365` 故障（预留禁用）
- **来源标签**：T0-2（R55 负 TIME 平台歧义口径的原子化统一出口）；零检索

#### #19 `FC_DL_LeapYearChk` —— 闰年判定原子
- **分类**：DL_Base / Calendar ｜ **类型**：FUNCTION → `BOOL` ｜ **复杂度**：L
- **引脚**：IN `nYear : UINT`（有效域 1900~2099，`bFullRule : BOOL := FALSE`——FALSE 按现场常用两律 `(y MOD 4)=0 AND (y MOD 100)<>0`；TRUE 按完整三律含 400 年律）；OUT 三件套。
- **VAR CONSTANT**：`DL_YEAR_MIN : UINT := 1900`｜`DL_YEAR_MAX : UINT := 2099`
- **边界安全条件**：① 域外年份 → 故障 0366、返回 FALSE、`bValid := FALSE`（不做静默猜测）；② 三级判定为纯整数取余比较，禁浮点禁 MOD 负数歧义（输入恒正，口径安全）；③ 本件是 R11 `FB_DL_YearWindowCheck` 内部闰年判定的**原子化复用**（库内复用即合规），不重复实现第四套闰年律；④ 无状态机（R6 N/A）。
- **码位 5 槽**：`16#0001_0430` 信息（预留 1 用 1 处）/ `16#0001_0431` 预留禁用 ｜ `16#0001_0366` 故障（年份超 1900~2099）/ `16#0001_0367` 故障（预留）/ `16#0001_0368` 故障（预留禁用）
- **来源标签**：T0-5 + 库内复用（T2-1 LGF Date and Timer 行 R11 判定语义原子化）；零检索

#### #20 `FB_DL_SemaMutex` —— IEC 标准 SEMA 互斥防御包装
- **分类**：DL_Base / Sync ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **功能**：IEC 61131-3 标准功能块 `SEMA` 的道莅防御性包装。标准语义（bClaim 上升沿置 bBusy、bRelease 复位）之上增强两点：① **占用超时强制归还**（`tHoldMax` 超时自动释放 + 故障码，防持锁任务崩溃后的永久死锁——两任务抢同一夹爪/同一打印口的现场高频故障）；② 申请/释放同拍仲裁明确化（释放优先，安全侧）。
- **引脚**：IN `bClaim : BOOL`（上升沿申请）；`bRelease : BOOL`（上升沿释放）；`tHoldMax : TIME := T#5S`（单次占用上限 [ms]，0 = 禁用超时监视）；OUT `bBusy : BOOL`；`bTimedOut : BOOL`（本拍发生超时强制释放，单周期脉冲）；`uClaimCnt : UDINT`（累计申请数，饱和）；`uReleaseCnt : UDINT`（累计释放数）；`eErr/bError`。
- **VAR CONSTANT**：`DL_SEMA_CNT_MAX : UDINT := 16#FFFF_FFFE`（计数饱和）｜`DL_SEMA_HOLD_DEF : TIME := T#5S`（默认占用上限）
- **VAR**：`fbTrigClaim : R_TRIG`｜`fbTrigRelease : R_TRIG`｜`fbHold : TON`｜`eState : E_DL_SemaState`（枚举 `eFree / eHeld / eTimedOutRelease`，同文件声明唯一属主）
- **边界安全条件**：① `R_TRIG`/`TON` 在主周期 CASE 之前无条件刷新（红线 4/5）；② CASE 三态 + **ELSE 兜底进 eFree 并置故障 036A**（红线 4）；③ 同拍 claim+release → 释放优先 + 信息 0432（安全侧：宁可还锁不可错持）；④ 超时路径：`fbHold.Q` → 状态转 `eTimedOutRelease`、`bBusy := FALSE`、故障 0369（死锁被拦截是故障级——调用方必须知道锁是被系统归还的）；⑤ `tHoldMax = 0` 禁用监视，但超长占用无监视时信息 0432 提示一次（首次持锁沿）；⑥ 计数饱和 → 036B；⑦ 状态量生命周期：故障复位（`bRelease` 沿）清除 `bTimedOut`/故障码，R39 纪律「复位通道不被屏蔽」；⑧ 无 `WHILE`。
- **码位 5 槽**：`16#0001_0432` 信息（同拍释放优先 或 超时监视被禁用提示）/ `16#0001_0433` 预留禁用 ｜ `16#0001_0369` 故障（占用超时，已强制归还——调用方必须处理）/ `16#0001_036A` 故障（非法状态兜底，已复位 eFree）/ `16#0001_036B` 故障（申请计数达饱和，统计不可信）
- **来源标签**：T0 标准功能块（IEC 61131-3 标准 FB SEMA 语义，库内未包装，T0-1/T0-3 双稳态-计数器语义的同步原语补位）；超时监视与同拍仲裁为本库防御增强，零检索

---

## 4 内嵌样板原文（R50 教训：不得只给语义描述，编码照抄此口径）

### 4.1 注释行样板（复制自 `DL_MathData/FC_DL_LintToUdintSat.st` 声明区，R19 最新 T0 件）

```iecst
    liIn            : LINT := 0;              // 输入值 [无量纲]，全域 -2^63~2^63-1 / input value [dimensionless], full LINT domain
    bRequireLossless : BOOL := FALSE;         // TRUE = 发生任何饱和即判故障（计量/累计场景）/ TRUE turns any saturation into a fault for metering use
```

```iecst
    eErr            : UDINT;                  // 错误码，0=正常 / error id, 0=ok
    bError          : BOOL;                   // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid          : BOOL;                   // 返回值是否可用（饱和且要求无损时为 FALSE）/ return usable, FALSE when saturated in lossless mode
```

段注释与码位赋值样板（同源）：

```iecst
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_LintToUdintSat := DL_UDINT_ZERO;        // 故障缺省返回 0 / fault default returns zero
eErr := 0;                                    // 预置无错误 / preset no error
```

### 4.2 错误码声明与头注释样板（完整码位块，同源复制）

头注释 `错误码` 段（五槽格式）：

```text
    错误码    : 16#0001_0406 负向饱和（输入 < 0 → 0），组态错但已安全兜底——信息级，正常防御
                16#0001_0407 正向饱和（输入 > 4294967295 → 上限）——信息级，正常防御
                16#0001_0327 调用方要求无损（bRequireLossless = TRUE）却发生饱和——故障级，bValid = FALSE
                16#0001_0328 预留禁用（故障级，不得挪用）
                16#0001_0329 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0406 用 / 16#0001_0407 用 ｜ 16#0001_0327 用 / 16#0001_0328 预留 / 16#0001_0329 预留
```

正文赋值样板：

```iecst
    eErr := 16#0001_0406;                      // 信息级：负向饱和，已兜底 / info level: negative saturation, clamped to zero
```

### 4.3 T0 四段式模板结构说明（R45 域闸门四段式，样板 `FC_DL_LogBaseEx.st`）

段序固定：**段 1 预置**（返回值缺省 + eErr/bError/bValid 清零）→ **段 2 非有限防御闸**（浮点件必设；整数件可并入段 3）→ **段 3 定义域（域门）判定**（域外早退，缺省返回 + 故障码，不触内建）→ **段 4 附加闸**（可选，如除子/底数/模长单列）→ **段 N 主体计算（永远是末段）**（域内才委托内建/标准语义，信息级钳位出口可挂末段）。纯转换件取子集（预置 → 域门 → 主体末段）；带状态机件（仅 #20）用 CASE 替代段 3，ELSE 兜底必须落故障码。

---

## 5 码位实测依据（R61/R75 教训：游标当场实测）

- 实测方法：正则扫描全部 324 个 `DL_*/*.st` 源码中的 `16#000[1-5]_[0-9A-Fa-f]{4}`，按段去重统计（共 1109 个「段+偏移」占用点）。
- `0001` 段：信息级 01xx n=180 max=`01FF`；02xx n=193 max=`02FF`（**满带，R19 已裁定禁回填**）；故障级 03xx n=48 max=`032F`；信息级 04xx 子带 n=12 已用 `0400~040B`（R19 #1~#6：DintMsToTod/TimeRatioCalc/RatioToPwrDb/LintToUdintSat/BitShiftRegister/ModbusRtuFrameCheck）。→ **本轮起点：信息 `040C`、故障 `0330`**。
- `0002` 段：CC 网格 `01~2A`（R19 用 `27~2A`），公共码 `00xx`（0001~0005）；`0002_8011` 实查仅存在于 `FB_DL_PdiReadScheduler.st` 头注释打包示例（V5 打包语义），**非码位占用**。本轮无 Algo 件。
- `0003` 段：信息 01xx max=`0171`、故障 03xx max=`033B`（R19 Device 件）。本轮无 Device 件。
- `0004` 段：信息 01xx max=`01D4`、故障 02xx max=`02E9`。本轮无 Motion 件。
- `0005` 段：信息 01xx max=`01D9`、故障 03xx max=`030A`。本轮无 Process 件。
- 收尾验证义务（编码线执行）：落盘后须复跑码位正则，断言「20 件新码位与本轮前 1109 个占用点交集为空」+「20 个新名称与 registry 324 名及 324 文件名交集为空」（R19 `_verify_r19.py` 同口径）。

---

## 6 收尾清单（编码线完成后执行，本轮不操作）

1. registry 增 20 条（`function_tags` 带对应源标签：T0 件统一含 `iec-std-wrapper`）；总库 324 → 344。
2. `DL_MathData/VERSION.md`（18 件）、`DL_Base/VERSION.md`（2 件）、两份 `MANUAL_DL_*.md`、顶层 `CHANGELOG.md`/`README.md`/`LIBRARY_MANUAL.md` 五件套同步。
3. JSONL 20 条按四步重注入（定位→替换→sha 复验→registry 同步）。
4. R19 遗留 P1：三本手册历史件接口表补录（文档线任务，非编码线）。
