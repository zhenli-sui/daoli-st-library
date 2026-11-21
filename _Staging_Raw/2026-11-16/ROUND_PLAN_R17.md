# R17 轮次规划（ROUND PLAN R17）—— T0 快车道第 4 轮：T0-4/T0-5/T0-7 域补齐 20 件

> 规划人：工控代码库产品总监 ｜ 日期：2026-11-16 ｜ 轮次：R17（阶段一+二，只规划不编码）
> 性质：**纯 T0 轮**（T0 = IEC 61131-3 标准函数防御性包装）。四族全部零检索，WebSearch **0 次**，T1/T2 **未动用**（本轮配额减配至 0）。
> 文件头溯源统一「IEC 61131-3 标准语义的道莅防御性实现」；`function_tags` 必含 `iec-std-wrapper`。
> 依据：R16 战报「下轮 P0 = T0 变体线续作（LOG、LWORD 位域等有意义族）」+ 源矩阵 T0-4/T0-5/T0-7 行 + registry v2.5.0 反查缺口。
> 本轮产出全部为 **纯函数（FC_）**，落 `DL_MathData`（15 件）/ `DL_Base`（4 件）/ `DL_MathData`（LWORD 精度 1 件，见批 4 说明）。

---

## 0 本轮硬性口径（编码者逐条照抄，无需再查任何惯例文件）

### 0.1 T0 四条红线（违反任一条 = 返工，不允许「先入库后修补」）

1. **只包装，不造轮子**：内部一律**委托平台内建函数**（`LOG` / `LN` / `EXPT` / `TIME_TO_DINT` / `TRUNC` / `SHL` / `ROL` 等）。**严禁**自实现级数展开、对数/指数逼近、日历算法、BCD 除基以外的数学内核。
2. **溯源统一**：文件头 `溯源` 字段固定写「**IEC 61131-3 标准语义的道莅防御性实现**」，加一行「接口语义由 IEC 61131-3 定义，内部委托平台内建 <内建清单>，clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可」。**头注释内不得出现任何被禁记号字面**（全局变量容器名、外部变量声明关键字、物理 IO 地址通配式），一律以「零全局耦合、零硬编码地址」文字表述。
3. **`function_tags`**：每件必含 `iec-std-wrapper`，再附加族标签（`log-scale` / `db-convert` / `time-convert` / `precision-chk` / `sat-convert` / `lword-bitstring`）。
4. **统一三件套**：错误码统一走 `eErr : UDINT`（0 = 正常）+ `bError : BOOL` + `bValid : BOOL`；钳位方向必须在头注释 `功能说明` 里写明；注释 100% 中英双语同行。

### 0.2 码位总账（**R50 教训：逐件写死具体码值，编码者不得自创**）

**类段裁定（必读，本轮指令与库内惯例的冲突处理）**：

- 库内错误码类段按子库划分：`16#0001_` = DL_Base / DL_MathData（存量已用至 `02C9`），`16#0002_` = DL_Algo（存量已用 `0001`~`04xx`、`1D01`~`2212`），`0003_` Device / `0004_` Motion / `0005_` Process。
- 本轮 20 件**全部落 DL_Base / DL_MathData**，故类段一律 `16#0001_`；其内部再分**信息子段 `0x01xx`**、**故障子段 `0x02xx`**。
- 指令样板中的「`16#0002_XXXX`（故障级）」在本批**等价写作 `16#0001_02XX`**（故障级码）。理由：若强行按 `0002_` 字面，20 件需整体迁入 DL_Algo 类段，与存量 `0002_0001`~`0002_04xx` / `0002_1D01`~`0002_2212` 撞车，破坏「子库类段」既定分类学。**此裁定已留痕，如创始人要求严格字面，则整批改判并需重排类段，报请裁定。**
- **每件固定 5 槽**：信息级 2 槽（`01E8 + 2i`、`01E8 + 2i + 1`）+ 故障级 3 槽（`02CA + 3i`、`+1`、`+2`），`i` 为件号 0~19。逐件码值见 §2 与 §4，**表中写「预留禁用」的槽不得挪用**（预留槽用于同件后续缺陷修复时新增分支，避免跨件改码）。

**游标交接**：

| 项 | 本轮起点 | 本轮占用 | R18 起点 |
|---|---|---|---|
| 信息级 | `16#0001_01E8` | 40 码（`01E8`~`01FF` + `0200`~`020F`） | `16#0001_0210` |
| 故障级 | `16#0001_02CA` | 60 码（`02CA`~`0305`） | `16#0001_0306` |

> **注意（收口必查）**：本轮信息级 40 码跨入 `0x0200`~`0x020F` 小块，与故障级 `02CA+` 无重叠。收口时按 **R58「源码是唯一事实源」** 反算 `code_segment` 并执行全库唯一性断言（NONE 重复），不得按 manifest 计数口径回写。

### 0.3 文件头注释块样板（**原文照抄，仅替换 `<>` 内容**）

```iecst
(*
    <POU 名> —— <中文标题>
    ------------------------------------------------------------------
    分类      : <子库 / 族名>
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （接口语义由 IEC 61131-3 定义，内部委托平台内建 <内建清单>，
                  外围统一错误码 / 钳位 / 双语文档；clean-room 重写，
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R17）
    ------------------------------------------------------------------
    功能说明  : <3~6 行：做什么 / 域门与钳位方向 / 委托哪个内建 / 信息级与故障级各自的业务含义>
    错误码    : <5 行，逐槽列出，格式见 §0.5>
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
```

**全局禁写**：头注释与正文均不得出现全局变量容器名、外部变量声明关键字、物理 IO 绝对地址记法（百分号 + 区号的输入区/输出区/存储区位串写法）；不得出现厂商专有库对象名。统一以「零全局耦合、零硬编码地址」文字表述。

> **溯源 3 行逐字照抄**：`溯源` 字段的三行原文（首行结论 + 括号内两行说明）**一字不改**，仅把 `<内建清单>` 替换为 §4 该件「委托内建」列的内容（例：`LOG` / `LN` / `EXPT` / `TIME_TO_DINT`）。

### 0.4 段注释与行内注释样板（**原文照抄**）

**行内双语注释**（每个变量声明行、每条关键逻辑行都必须有）：

```iecst
    fIn : REAL; // 待求对数的输入值（须 > 0） [无量纲] / input value whose logarithm is taken (must be > 0) [dimensionless]
```

格式铁律：`// 中文（含定义域或取值范围） [工程单位] / English description [unit]`，**中文与英文同一行，中间以 ` / ` 分隔**；`[单位]` 不得省略（无量纲写 `[无量纲]`）。禁止 R15 之前出现过的 `(* 中文 EN: xxx *)` 写法。

**段分隔注释**（每件 3~4 段，段号 + 中英标题，末段标 `final`）：

```iecst
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜非有限防御闸 / segment 2, non-finite guard
// 段 3｜定义域（域门）判定 / segment 3, domain gate
// 段 4｜主体计算（末段） / segment 4, main calculation (final)
```

### 0.5 错误码样板（**原文照抄，5 槽一行不落**）

头注释 `错误码` 段固定 5 行，槽序固定为「信息 1 / 信息 2 / 故障 1 / 故障 2 / 故障 3」，**码值逐件见 §4**：

```iecst
    错误码    : 16#0001_01E8 预留禁用（信息级，不得挪用）
                16#0001_01E9 预留禁用（信息级，不得挪用）
                16#0001_02CA 非有限输入（NaN 或 ±INF）——故障级，返回 0.0
                16#0001_02CB 定义域非法（输入 ≤ 0）——故障级，返回 0.0
                16#0001_02CC 预留禁用（故障级，不得挪用）
```

正文中写法固定：`eErr := 16#0001_02CA; // 非有限输入故障码 / non-finite input fault id`。

### 0.6 变量声明区样板骨架（**原文照抄结构，逐件实参见 §4**）

```iecst
FUNCTION FC_DL_<Name> : <返回类型>
VAR_INPUT
    <引脚声明 1>
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    <带单位常量，全部 DL_ 前缀、全大写>
END_VAR
VAR
    <中间量，全部带中文同行注释>
END_VAR
```

纪律：**纯函数无 `VAR_IN_OUT`**；常量一律 `DL_` 前缀 + 全大写 + 单位注释；**无魔法数**（阈值/位宽/域界全部提常量）；`VAR_OUTPUT` 顺序固定 `eErr → bError → bValid`。

> **样板边界（防误抄）**：§4 每件的「(c) 变量声明区样板原文」**只覆盖声明区**（到最后一个 `END_VAR` 为止，故意不含函数体与终结符）；函数体按 §0.8 收尾纪律编写，文件末尾必须补 `END_FUNCTION`。

### 0.7 纯函数状态机 N/A 声明（R60 标准文本，原样照抄）

```iecst
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
```

### 0.8 函数体收尾纪律（每件必须）

- 首段：返回值预置（故障缺省值）+ `eErr := 0` + `bError := FALSE` + `bValid := FALSE`；
- 故障分支：置码 + `bError := TRUE` + `bValid := FALSE` + `RETURN`（提前返回，**故障级优先**）；
- 末段：`bError := FALSE; bValid := TRUE;`（信息级不置故障）；
- 文件末尾 `END_FUNCTION` 必须有终结符（R3 全库补修教训）。

---

## 1 立项取舍说明（否决与调整记录，防下轮重复立项）

1. **T0-4 真缺口确认**：矩阵 §1 T0-4 列明 12 个标准数学函数，R14/R15 实交 12 件但**其中 `LOG`（底 10）缺席、另以 `ATAN2` 补位**。故 `FC_DL_LogEx` 属**真缺口**而非变体，本批第 1 件，优先级最高。
2. **`FC_DL_Log2Ex` 否决**：`FC_DL_LogBaseEx` 传入 `fBase = 2.0` 即得 log2（倍频程/位宽估计场景全覆盖），单独立件属凑数变体。
3. **`FC_DL_RatioToPwrDb`（功率反向件）延后 P1**：与 `FC_DL_RatioToAmpDb` 仅常数因子差异（10 vs 20），同批并列会使两件验收向量重叠 > 90%；按「宁少勿滥」本批只保功率**正向**件（现场「按 dB 设定反算功率」多于「功率反推 dB」）。缺口登记 ROADMAP P1。
4. **`FC_DL_DintMsToTod`（当日毫秒→TOD）延后 P1**：需 TOD 日历域钳位，与日历族同批做验收更省事；本批只取 `TodToDintMs`（班次/排程刚需方向）。
5. **日历族（DT / DTL / DATE 分解与差值）整族延后 P1**：核心依赖平台 `DT_TO_DTL` 可用性，须先过 CODESYS / TwinCAT / InoProShop 三平台编译验证；未验证就立项等于把可移植性红线押在未证实前提上。**登记 ROADMAP P1，标注「需三平台编译验证门槛」**。
6. **`Sel/Mux/Limit` 整型域变体否决**：R16 已覆盖浮点域，整型域无 NaN/±INF 语义，变体只剩「换类型」，验收向量与原件重叠，工程增量近零。
7. **LWORD 族准入依据**：库内 `FC_DL_BitArrayExtract` / `FC_DL_BitArrayInsert`（R12）**已在用 `LWORD` 类型变量与 `SHL(LWORD#1, …)`**，`DL_MASK64_ALL` 常量亦已存在 → LWORD 移位族**无新增平台风险**；`LWORD` 位移量 ≥ 64 的未定义行为与 R14 `FC_DL_ShlEx` 的 32 位口径同源（R10/R48 先例），属正当防御域。
8. **`FC_DL_UdintToLrealChk` 否决（并写入正文防误立）**：UDINT 全域 ≤ 2^32 < 2^53，转 LREAL 恒无损，无告警语义。

---

## 2 20 件派单总表

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次(1-4) |
|---|---|---|---|---|---|---|---|
| 1 | FC_DL_LogEx | DL_MathData/Log | FC_DL_ | IEC LOG 底 10 防御包装：非有限 + 定义域双闸 | iec-std-wrapper, log-scale | 低 | 1 |
| 2 | FC_DL_LogBaseEx | DL_MathData/Log | FC_DL_ | 任意底数对数 LN(x)/LN(b)，底数退化（b=1）拦截 | iec-std-wrapper, log-scale | 中 | 1 |
| 3 | FC_DL_AmpDbToRatio | DL_MathData/Log | FC_DL_ | 幅值型 dB→线性幅值比 10^(dB/20)，超限饱和 | iec-std-wrapper, db-convert | 低 | 1 |
| 4 | FC_DL_RatioToAmpDb | DL_MathData/Log | FC_DL_ | 线性幅值比→幅值型 dB 20·LOG(x)，非正值域闸 | iec-std-wrapper, db-convert | 低 | 1 |
| 5 | FC_DL_PwrDbToRatio | DL_MathData/Log | FC_DL_ | 功率型 dB→线性功率比 10^(dB/10)，±380 dB 硬限饱和 | iec-std-wrapper, db-convert | 低 | 1 |
| 6 | FC_DL_TimeToDintMs | DL_MathData/TimeConv | FC_DL_ | TIME→DINT 毫秒，超 DINT 域饱和 + 负值钳零 | iec-std-wrapper, time-convert | 中 | 2 |
| 7 | FC_DL_DintMsToTime | DL_MathData/TimeConv | FC_DL_ | DINT 毫秒→TIME，负值钳 T#0S | iec-std-wrapper, time-convert | 低 | 2 |
| 8 | FC_DL_TimeToLrealSec | DL_MathData/TimeConv | FC_DL_ | TIME→LREAL 秒（节拍/速度算法用） | iec-std-wrapper, time-convert | 低 | 2 |
| 9 | FC_DL_LrealSecToTime | DL_MathData/TimeConv | FC_DL_ | LREAL 秒→TIME，非有限/负值/超上限三路防御 | iec-std-wrapper, time-convert | 中 | 2 |
| 10 | FC_DL_TodToDintMs | DL_MathData/TimeConv | FC_DL_ | TOD→当日毫秒偏移（班次/排程），域外钳位 | iec-std-wrapper, time-convert | 中 | 2 |
| 11 | FC_DL_DintToRealChk | DL_MathData/Convert | FC_DL_ | DINT→REAL 超 2^24 精度告警（值照转） | iec-std-wrapper, precision-chk | 低 | 3 |
| 12 | FC_DL_UdintToRealChk | DL_MathData/Convert | FC_DL_ | UDINT→REAL 超 2^24 精度告警（值照转） | iec-std-wrapper, precision-chk | 低 | 3 |
| 13 | FC_DL_LintToDintSat | DL_MathData/Convert | FC_DL_ | LINT→DINT 双向域外饱和（宽→窄） | iec-std-wrapper, sat-convert | 低 | 3 |
| 14 | FC_DL_RealToLintSat | DL_MathData/Convert | FC_DL_ | REAL→LINT 非有限拦截 + 域外饱和 + 向零截断 | iec-std-wrapper, sat-convert | 中 | 3 |
| 15 | FC_DL_LrealToLintSat | DL_MathData/Convert | FC_DL_ | LREAL→LINT 非有限拦截 + 域外饱和 + 向零截断 | iec-std-wrapper, sat-convert | 中 | 3 |
| 16 | FC_DL_ShlLwordEx | DL_Base/BitString | FC_DL_ | LWORD 左移：移位量 ≥64 超宽置零 | iec-std-wrapper, lword-bitstring | 低 | 4 |
| 17 | FC_DL_ShrLwordEx | DL_Base/BitString | FC_DL_ | LWORD 逻辑右移：移位量 ≥64 超宽置零 | iec-std-wrapper, lword-bitstring | 低 | 4 |
| 18 | FC_DL_RolLwordEx | DL_Base/BitString | FC_DL_ | LWORD 循环左移：移位量 MOD 64 归一 | iec-std-wrapper, lword-bitstring | 低 | 4 |
| 19 | FC_DL_RorLwordEx | DL_Base/BitString | FC_DL_ | LWORD 循环右移：移位量 MOD 64 归一 | iec-std-wrapper, lword-bitstring | 低 | 4 |
| 20 | FC_DL_LwordToLrealChk | DL_MathData/Convert | FC_DL_ | LWORD→LREAL 超 2^53 精度告警（无符号镜像） | iec-std-wrapper, precision-chk | 低 | 4 |

**码位速查（5 槽/件，逐件写死）**

| 序号 | 组件 | 信息槽 A | 信息槽 B | 故障槽 A | 故障槽 B | 故障槽 C |
|---|---|---|---|---|---|---|
| 1 | LogEx | `01E8` 预留 | `01E9` 预留 | `02CA` 非有限 | `02CB` 域外(≤0) | `02CC` 预留 |
| 2 | LogBaseEx | `01EA` 预留 | `01EB` 预留 | `02CD` 非有限 | `02CE` 定义域非法 | `02CF` 底数退化 |
| 3 | AmpDbToRatio | `01EC` dB 超限饱和 | `01ED` 预留 | `02D0` 非有限 | `02D1` 预留 | `02D2` 预留 |
| 4 | RatioToAmpDb | `01EE` dB 超限钳位 | `01EF` 预留 | `02D3` 非有限 | `02D4` 比值 ≤0 | `02D5` 预留 |
| 5 | PwrDbToRatio | `01F0` dB 超限饱和 | `01F1` 预留 | `02D6` 非有限 | `02D7` 预留 | `02D8` 预留 |
| 6 | TimeToDintMs | `01F2` 超 DINT 域饱和 | `01F3` 结果为负已钳零 | `02D9` 预留 | `02DA` 预留 | `02DB` 预留 |
| 7 | DintMsToTime | `01F4` 负值钳 T#0S | `01F5` 预留 | `02DC` 预留 | `02DD` 预留 | `02DE` 预留 |
| 8 | TimeToLrealSec | `01F6` 负 TIME 记录 | `01F7` 预留 | `02DF` 预留 | `02E0` 预留 | `02E1` 预留 |
| 9 | LrealSecToTime | `01F8` 负值钳 T#0S | `01F9` 超上限饱和 | `02E2` 非有限 | `02E3` 预留 | `02E4` 预留 |
| 10 | TodToDintMs | `01FA` 域外钳位 | `01FB` 预留 | `02E5` 预留 | `02E6` 预留 | `02E7` 预留 |
| 11 | DintToRealChk | `01FC` 2^24 精度告警 | `01FD` 预留 | `02E8` 预留 | `02E9` 预留 | `02EA` 预留 |
| 12 | UdintToRealChk | `01FE` 2^24 精度告警 | `01FF` 预留 | `02EB` 预留 | `02EC` 预留 | `02ED` 预留 |
| 13 | LintToDintSat | `0200` 上溢饱和 | `0201` 下溢饱和 | `02EE` 预留 | `02EF` 预留 | `02F0` 预留 |
| 14 | RealToLintSat | `0202` 域外饱和 | `0203` 预留 | `02F1` 非有限 | `02F2` 预留 | `02F3` 预留 |
| 15 | LrealToLintSat | `0204` 域外饱和 | `0205` 预留 | `02F4` 非有限 | `02F5` 预留 | `02F6` 预留 |
| 16 | ShlLwordEx | `0206` 超宽置零 | `0207` 预留 | `02F7` 预留 | `02F8` 预留 | `02F9` 预留 |
| 17 | ShrLwordEx | `0208` 超宽置零 | `0209` 预留 | `02FA` 预留 | `02FB` 预留 | `02FC` 预留 |
| 18 | RolLwordEx | `020A` 移位量 ≥64 已归一 | `020B` 预留 | `02FD` 预留 | `02FE` 预留 | `02FF` 预留 |
| 19 | RorLwordEx | `020C` 移位量 ≥64 已归一 | `020D` 预留 | `0300` 预留 | `0301` 预留 | `0302` 预留 |
| 20 | LwordToLrealChk | `020E` 2^53 精度告警 | `020F` 预留 | `0303` 预留 | `0304` 预留 | `0305` 预留 |

> 上表码值均为 `16#0001_XXXX` 完整形（例：`16#0001_01EC`、`16#0001_02CA`）。故障槽写「预留」者，正文头注释仍须逐行列出并标「预留禁用（故障级，不得挪用）」。

---

## 3 批次依赖说明

四批均为 **Level 0 纯函数，批间零编译依赖**（无相互调用、无 `VAR_IN_OUT`、无实例内存），按批切分仅为并行派单与验收节奏；批内同族同模板，便于「模板复用 → 边际成本趋零」。

| 批 | 族 | 落盘目录 | 件数 | 主要委托内建 |
|---|---|---|---|---|
| 1 | 对数与 dB 换算（T0-4 补齐） | DL_MathData | 5 | `LOG` / `LN` / `EXPT` |
| 2 | TIME / TOD 标量转换（T0-5） | DL_MathData | 5 | `TIME_TO_DINT` / `TIME_TO_LREAL` / `DINT_TO_TIME` / `TOD_TO_TIME` |
| 3 | 精度告警与宽窄域饱和（T0-5） | DL_MathData | 5 | `DINT_TO_REAL` / `UDINT_TO_REAL` / `LINT_TO_DINT` / `TRUNC` / `LREAL_TO_LINT` |
| 4 | LWORD 64 位位串（T0-7 重载）+ LWORD 精度 | DL_Base（4）+ DL_MathData（1） | 5 | `SHL` / `SHR` / `ROL` / `ROR` / `LWORD_TO_LREAL` |

**批 4 跨目录说明**：16~19 属矩阵 T0-7「位串操作 → DL_Base」既有归属；20 属数值精度域（Converter），按分层契约落 DL_MathData。两目录均 Level 0，互不引用，依赖方向无冲突。

---

## 4 逐件规格（引脚级 + 三段样板原文）

### 批 1｜对数与 dB 换算族（DL_MathData / Log，5 件，T0-4 补齐）

> 族内纪律：全部委托 `LOG()` / `LN()` / `EXPT()`；`dB` 换算的 `20` / `10` 因子一律提为带单位常量（幅值型 vs 功率型**必须显式区分**，这是现场最常混用的 10/20 因子陷阱）；所有除子为编译期常量，天然满足除零红线。

#### 4.1.1 `FC_DL_LogEx` —— 底 10 常用对数防御包装

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_MathData / Log |
| 前缀 / 返回类型 | `FC_DL_` / `REAL` |
| 复杂度 / 批次 | 低 / 批 1 |
| function_tags | `iec-std-wrapper`, `log-scale` |
| 委托内建 | `LOG()`（IEC 61131-3 常用对数，**严禁**自实现级数展开） |
| 码位 | 信息 `16#0001_01E8`（预留）/ `16#0001_01E9`（预留）；故障 `16#0001_02CA`（非有限）/ `16#0001_02CB`（定义域 ≤0）/ `16#0001_02CC`（预留） |

**语义**：返回 `LOG(fIn)`（底 10 常用对数）。故障缺省返回 `0.0`（即 `log10(1)`，对下游限幅链是中性的安全值）。

**防御点**：
1. 非有限（NaN 自不等 / ±INF 安全幅值判）→ 故障 `02CA`，返回 `0.0`；
2. `fIn ≤ 0.0`（含 0，`LOG(0)` 在部分平台返回 −INF、部分平台报错）→ 故障 `02CB`，返回 `0.0`；
3. 域内直接委托内建，不复检结果（`log10` 在 `(0, +∞)` 上恒有限，正数域最小可表数 1.18E−38 → 结果约 −37.9，无溢出路径）。

**分支段骨架**：段 1 预置 → 段 2 非有限闸（`RETURN`）→ 段 3 定义域闸（`RETURN`）→ 段 4 主体 `LOG(fIn)`（末段）。

**(a) 注释样板原文**

```iecst
    功能说明  : 返回输入值的底 10 常用对数（IEC LOG 语义），内部委托平台内建 LOG，
                不重实现任何对数内核；
                非有限输入（NaN 或 ±INF）判为故障级 16#0001_02CA，返回 0.0 且 bValid=FALSE；
                定义域非法（输入 ≤ 0）判为故障级 16#0001_02CB，返回 0.0 且 bValid=FALSE；
                钳位方向：无钳位（两路故障均拦截并回缺省值，不做域内改造）。
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜非有限防御闸 / segment 2, non-finite guard
// 段 3｜定义域（域门）判定 / segment 3, domain gate
// 段 4｜主体计算（末段） / segment 4, main calculation (final)
    fIn : REAL; // 待求对数的输入值（须 > 0） [无量纲] / input value whose logarithm is taken (must be > 0) [dimensionless]
bNonFinite := (fIn <> fIn) OR (fIn > DL_REAL_INF_GUARD) OR (fIn < -DL_REAL_INF_GUARD); // 非有限判定（NaN 自不等 + 安全幅值判 ±INF） [无量纲] / non-finite check (NaN by self-inequality, +/-INF by safe magnitude)
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_01E8 预留禁用（信息级，不得挪用）
                16#0001_01E9 预留禁用（信息级，不得挪用）
                16#0001_02CA 非有限输入（NaN 或 ±INF）——故障级，返回 0.0
                16#0001_02CB 定义域非法（输入 ≤ 0）——故障级，返回 0.0
                16#0001_02CC 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_LogEx : REAL
VAR_INPUT
    fIn : REAL; // 待求对数的输入值（须 > 0） [无量纲] / input value whose logarithm is taken (must be > 0) [dimensionless]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_LOG_FAULT_DEF : REAL := 0.0;                         // 故障缺省返回值 log10(1)=0 [无量纲] / fault default return value log10(1)=0 [dimensionless]
    DL_REAL_INF_GUARD : LREAL := 4.0E38;                     // REAL 域 ±INF 判定阈值，高于 REAL 最大有限值 3.402823E38 [无量纲] / REAL +/-INF guard above max finite REAL 3.402823E38
END_VAR
VAR
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR
```

---

#### 4.1.2 `FC_DL_LogBaseEx` —— 任意底数对数防御包装

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_MathData / Log |
| 前缀 / 返回类型 | `FC_DL_` / `REAL` |
| 复杂度 / 批次 | 中 / 批 1 |
| function_tags | `iec-std-wrapper`, `log-scale` |
| 委托内建 | `LN()`（两处：`LN(fIn)` / `LN(fBase)`），**严禁**自实现内核；`log2` 场景由 `fBase = 2.0` 覆盖，不另立件 |
| 码位 | 信息 `16#0001_01EA`（预留）/ `16#0001_01EB`（预留）；故障 `16#0001_02CD`（非有限）/ `16#0001_02CE`（定义域非法）/ `16#0001_02CF`（底数退化） |

**语义**：返回 `log_fBase(fIn) = LN(fIn) / LN(fBase)`。**本件 3 个故障槽全部启用，无预留故障槽**（三路故障语义互不包含，合并会丢信息），信息级 2 槽预留。

**防御点**：
1. `fIn` 或 `fBase` 任一非有限 → 故障 `02CD`，返回 `0.0`；
2. `fIn ≤ 0.0` 或 `fBase ≤ 0.0` → 故障 `02CE`，返回 `0.0`；
3. `ABS(fBase - 1.0) < DL_LOG_BASE_EPS`（`1.0E-6`）→ 故障 `02CF`（底数为 1 时对数无意义；贴近 1 时 `LN(fBase) → 0`，结果会爆炸，必须先拦不使用除法）；
4. 除法前显式复判 `ABS(fLnBase) > DL_FLOAT_EPS`，双保险后才做除法（红线：除法前判除子）。

**分支段骨架**：段 1 预置 → 段 2 非有限闸 → 段 3 定义域闸 → 段 4 底数退化闸 → 段 5 除子整备与主体除法（末段）。

**(a) 注释样板原文**

```iecst
    功能说明  : 返回以 fBase 为底的 fIn 对数，按换底公式 LN(fIn)/LN(fBase) 实现，
                两处对数均委托平台内建 LN，不重实现任何对数内核；
                非有限输入判为故障级 16#0001_02CD，返回 0.0 且 bValid=FALSE；
                定义域非法（fIn ≤ 0 或 fBase ≤ 0）判为故障级 16#0001_02CE，返回 0.0；
                底数退化（|fBase − 1| < 1.0E-6，含 fBase = 1）判为故障级 16#0001_02CF，
                返回 0.0（底数为 1 时对数无定义，贴近 1 时商发散，必须先拦不使用除法）；
                钳位方向：无钳位（三路故障均拦截并回缺省值）。
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜非有限防御闸 / segment 2, non-finite guard
// 段 3｜定义域（域门）判定 / segment 3, domain gate
// 段 4｜底数退化闸（防 LN 除零发散） / segment 4, base degeneracy gate (prevents LN divide blow-up)
// 段 5｜除子整备与主体除法（末段） / segment 5, divisor preparation and main division (final)
    fBase : REAL; // 对数底数（须 > 0 且 ≠ 1；=2.0 即 log2 用法） [无量纲] / logarithm base (must be > 0 and not 1; 2.0 yields log2)
IF ABS(fLnBase) <= DL_FLOAT_EPS THEN // 除子复判（域闸之外的除法前第二道保险） [无量纲] / divisor re-check, second guard before division
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_01EA 预留禁用（信息级，不得挪用）
                16#0001_01EB 预留禁用（信息级，不得挪用）
                16#0001_02CD 非有限输入（fIn 或 fBase 为 NaN / ±INF）——故障级，返回 0.0
                16#0001_02CE 定义域非法（fIn ≤ 0 或 fBase ≤ 0）——故障级，返回 0.0
                16#0001_02CF 底数退化（fBase = 1 或 |fBase − 1| < 1.0E-6）——故障级，返回 0.0
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_LogBaseEx : REAL
VAR_INPUT
    fIn   : REAL; // 待求对数的真数（须 > 0） [无量纲] / logarithm argument (must be > 0) [dimensionless]
    fBase : REAL; // 对数底数（须 > 0 且 ≠ 1；=2.0 即 log2 用法） [无量纲] / logarithm base (must be > 0 and not 1; 2.0 yields log2) [dimensionless]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_LOG_FAULT_DEF  : REAL := 0.0;       // 故障缺省返回值 log10(1)=0 [无量纲] / fault default return value log10(1)=0 [dimensionless]
    DL_LOG_BASE_EPS   : REAL := 1.0E-6;    // 底数贴近 1 的判定容差（|fBase−1| < 该值视为退化） [无量纲] / base-near-1 tolerance, below means degenerate
    DL_FLOAT_EPS      : REAL := 1.0E-6;    // 浮点除子判定容差（除法前复判） [无量纲] / floating divisor tolerance, re-checked before division
    DL_REAL_INF_GUARD : LREAL := 4.0E38;   // REAL 域 ±INF 判定阈值，高于 REAL 最大有限值 3.402823E38 [无量纲] / REAL +/-INF guard above max finite REAL 3.402823E38
END_VAR
VAR
    fLnBase    : REAL; // 底数自然对数 LN(fBase) [无量纲] / natural logarithm of the base [dimensionless]
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR
```

---

#### 4.1.3 `FC_DL_AmpDbToRatio` —— 幅值型 dB → 线性幅值比

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_MathData / Log |
| 前缀 / 返回类型 | `FC_DL_` / `REAL` |
| 复杂度 / 批次 | 低 / 批 1 |
| function_tags | `iec-std-wrapper`, `db-convert` |
| 委托内建 | `EXPT(10.0, fDb / 20.0)`（IEC 幂函数），**严禁**自实现指数内核 |
| 码位 | 信息 `16#0001_01EC`（dB 超限饱和）/ `16#0001_01ED`（预留）；故障 `16#0001_02D0`（非有限）/ `16#0001_02D1`（预留）/ `16#0001_02D2`（预留） |

**语义**：`A = 10^(dB/20)`，幅值型（电压/电流/振幅/位移）dB 换算，**因子 20 提为常量 `DL_DB_AMP_DIV`**。

**防御点**：
1. `fDb` 非有限 → 故障 `02D0`，返回 `1.0`（比值中性值 = 0 dB，比返回 0.0 更安全，避免下游乘 0 灭掉信号）；
2. `ABS(fDb) > DL_DB_LIMIT (400.0 dB)` → 饱和：正超 → `DL_RATIO_MAX (1.0E20)`，负超 → `DL_RATIO_MIN (1.0E-20)`，置信息 `01EC`（`bError=FALSE`、`bValid=TRUE`；±400 dB 对应 10^±20，REAL 全域可表，故取 400 为硬限）；
3. `EXPT` 结果复检非有限（平台 `EXPT` 溢出行为不一致）→ 按方向饱和 + 同一信息码 `01EC`（同一业务语义不另立码）。

**分支段骨架**：段 1 预置 → 段 2 非有限闸 → 段 3 dB 域硬限饱和（`RETURN`）→ 段 4 主体 `EXPT` + 结果复检（末段）。

**(a) 注释样板原文**

```iecst
    功能说明  : 幅值型分贝转过线性幅值比，按 A = 10^(dB/20) 实现，指数运算委托平台内建 EXPT，
                20 为幅值型换算因子（与功率型 10 严格区分，禁混用），不重实现指数内核；
                非有限输入判为故障级 16#0001_02D0，返回 1.0（比值中性值，避免下游乘零灭信号）；
                |dB| 超 400.0 dB 硬限时按方向饱和至 1.0E20 / 1.0E-20，置信息级 16#0001_01EC；
                EXPT 结果复检非有限（部分平台溢出行为不一致）同样按方向饱和并复用 01EC；
                钳位方向：双侧饱和（dB 域 ±400.0 dB，比值域 1.0E-20 ~ 1.0E20）。
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜非有限防御闸 / segment 2, non-finite guard
// 段 3｜dB 域硬限双侧饱和 / segment 3, two-sided dB domain saturation
// 段 4｜主体幂运算与结果复检（末段） / segment 4, main power computation and result re-check (final)
    fDb : REAL; // 幅值型分贝值，建议域 −400.0~+400.0 [dB] / amplitude decibel value, suggested domain -400.0..+400.0 [dB]
FC_DL_AmpDbToRatio := EXPT(DL_DB_TEN, fDb / DL_DB_AMP_DIV); // 域内委托内建 EXPT 计算 10^(dB/20) [比] / in-domain delegate to built-in EXPT for 10^(dB/20) [ratio]
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_01EC dB 值超 ±400.0 dB 硬限，已按方向饱和——信息级，正常防御
                16#0001_01ED 预留禁用（信息级，不得挪用）
                16#0001_02D0 非有限输入（NaN 或 ±INF）——故障级，返回 1.0
                16#0001_02D1 预留禁用（故障级，不得挪用）
                16#0001_02D2 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_AmpDbToRatio : REAL
VAR_INPUT
    fDb : REAL; // 幅值型分贝值，建议域 −400.0~+400.0 [dB] / amplitude decibel value, suggested domain -400.0..+400.0 [dB]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_DB_AMP_DIV     : REAL := 20.0;      // 幅值型 dB 换算除子（20·log10 的逆向） [dB] / amplitude dB divisor, inverse of 20*log10 [dB]
    DL_DB_TEN         : REAL := 10.0;      // 幂运算底数 10 [无量纲] / power base 10 [dimensionless]
    DL_DB_LIMIT       : REAL := 400.0;     // dB 域双侧硬限，对应比值 10^±20 [dB] / two-sided dB hard limit, ratio 10^+/-20 [dB]
    DL_RATIO_NEUTRAL  : REAL := 1.0;       // 比值中性值（0 dB 对应值，故障缺省返回） [比] / neutral ratio (0 dB), fault default [ratio]
    DL_RATIO_MAX      : REAL := 1.0E20;    // 幅值比上限 10^20，REAL 域可表 [比] / amplitude ratio upper bound 10^20 [ratio]
    DL_RATIO_MIN      : REAL := 1.0E-20;   // 幅值比下限 10^-20，REAL 域可表 [比] / amplitude ratio lower bound 10^-20 [ratio]
    DL_REAL_INF_GUARD : LREAL := 4.0E38;   // REAL 域 ±INF 判定阈值，高于 REAL 最大有限值 3.402823E38 [无量纲] / REAL +/-INF guard above max finite REAL
END_VAR
VAR
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR
```

---

#### 4.1.4 `FC_DL_RatioToAmpDb` —— 线性幅值比 → 幅值型 dB

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_MathData / Log |
| 前缀 / 返回类型 | `FC_DL_` / `REAL` |
| 复杂度 / 批次 | 低 / 批 1 |
| function_tags | `iec-std-wrapper`, `db-convert` |
| 委托内建 | `LOG(fRatio) * 20.0`（IEC 常用对数 × 常量因子） |
| 码位 | 信息 `16#0001_01EE`（dB 超限钳位）/ `16#0001_01EF`（预留）；故障 `16#0001_02D3`（非有限）/ `16#0001_02D4`（比值 ≤0）/ `16#0001_02D5`（预留） |

**语义**：`dB = 20 · log10(A)`，`A` 为线性幅值比（须 > 0）。故障缺省返回 `0.0` dB。

**防御点**：
1. `fRatio` 非有限 → 故障 `02D3`，返回 `0.0`；
2. `fRatio ≤ 0.0` → 故障 `02D4`，返回 `0.0`（`log10(0)` / 负数无定义）；
3. 结果 `ABS(fDb) > DL_DB_LIMIT` → 钳至 ±400.0 dB + 信息 `01EE`（正常防御：极小比值如 1E−38 → 约 −760 dB 必须钳位，否则下游 dB 域常量溢出）。

**分支段骨架**：段 1 预置 → 段 2 非有限闸 → 段 3 定义域闸（`≤ 0`）→ 段 4 主体 `LOG × 20.0` + 结果钳位（末段）。

**(a) 注释样板原文**

```iecst
    功能说明  : 线性幅值比转幅值型分贝值，按 dB = 20·log10(A) 实现，对数委托平台内建 LOG，
                20 为幅值型换算因子（与功率型 10 严格区分，禁混用），不重实现对数内核；
                非有限输入判为故障级 16#0001_02D3，返回 0.0 dB；
                定义域非法（比值 ≤ 0）判为故障级 16#0001_02D4，返回 0.0 dB；
                结果 |dB| 超 400.0 dB 时钳至 ±400.0 dB 并置信息级 16#0001_01EE
                （极小比值约 −760 dB，不钳会让下游 dB 域常量溢出）；
                钳位方向：结果双侧钳位至 ±400.0 dB。
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜非有限防御闸 / segment 2, non-finite guard
// 段 3｜定义域（域门）判定 / segment 3, domain gate
// 段 4｜主体对数换算与结果钳位（末段） / segment 4, main logarithm conversion and result clamp (final)
    fRatio : REAL; // 线性幅值比（须 > 0，1.0 = 0 dB） [比] / linear amplitude ratio (must be > 0, 1.0 means 0 dB) [ratio]
FC_DL_RatioToAmpDb := LOG(fRatio) * DL_DB_AMP_FACTOR; // 委托内建 LOG 后乘幅值型因子 20 [dB] / delegate to built-in LOG then multiply amplitude factor 20 [dB]
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_01EE 结果超 ±400.0 dB，已钳至 dB 域硬限——信息级，正常防御
                16#0001_01EF 预留禁用（信息级，不得挪用）
                16#0001_02D3 非有限输入（NaN 或 ±INF）——故障级，返回 0.0
                16#0001_02D4 定义域非法（幅值比 ≤ 0）——故障级，返回 0.0
                16#0001_02D5 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_RatioToAmpDb : REAL
VAR_INPUT
    fRatio : REAL; // 线性幅值比（须 > 0，1.0 = 0 dB） [比] / linear amplitude ratio (must be > 0, 1.0 means 0 dB) [ratio]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_DB_FAULT_DEF   : REAL := 0.0;      // 故障缺省返回值（0 dB 中性值） [dB] / fault default return (0 dB neutral) [dB]
    DL_DB_AMP_FACTOR  : REAL := 20.0;     // 幅值型 dB 换算因子 20·log10 [dB] / amplitude dB factor 20*log10 [dB]
    DL_DB_LIMIT       : REAL := 400.0;    // dB 域双侧硬限 [dB] / two-sided dB hard limit [dB]
    DL_REAL_INF_GUARD : LREAL := 4.0E38;  // REAL 域 ±INF 判定阈值，高于 REAL 最大有限值 3.402823E38 [无量纲] / REAL +/-INF guard above max finite REAL
END_VAR
VAR
    fDb        : REAL; // dB 换算中间结果 [dB] / intermediate dB result [dB]
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR
```

---

#### 4.1.5 `FC_DL_PwrDbToRatio` —— 功率型 dB → 线性功率比

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_MathData / Log |
| 前缀 / 返回类型 | `FC_DL_` / `REAL` |
| 复杂度 / 批次 | 低 / 批 1 |
| function_tags | `iec-std-wrapper`, `db-convert` |
| 委托内建 | `EXPT(10.0, fDb / 10.0)` |
| 码位 | 信息 `16#0001_01F0`（dB 超限饱和）/ `16#0001_01F1`（预留）；故障 `16#0001_02D6`（非有限）/ `16#0001_02D7`（预留）/ `16#0001_02D8`（预留） |

**语义**：`P = 10^(dB/10)`，功率型（声功率/射频功率/加热功率/损耗）dB 换算，**因子 10 提为常量 `DL_DB_PWR_DIV`**。

**防御点**：
1. `fDb` 非有限 → 故障 `02D6`，返回 `1.0`；
2. `ABS(fDb) > DL_DB_PWR_LIMIT (380.0 dB)` → 饱和至 `1.0E38` / `1.0E-38` + 信息 `01F0`。**硬限取 380 而非 400 的理由必须写进头注释**：功率型 400 dB 对应比值 10^40，超出 REAL 最大有限值 3.402823E38，饱和值本身不可表；380 dB ↔ 10^±38，两端均在 REAL 域内。
3. 结果复检非有限 → 按方向饱和 + 复用 `01F0`。

**(a) 注释样板原文**

```iecst
    功能说明  : 功率型分贝转过线性功率比，按 P = 10^(dB/10) 实现，指数运算委托平台内建 EXPT，
                10 为功率型换算因子（与幅值型 20 严格区分，禁混用），不重实现指数内核；
                非有限输入判为故障级 16#0001_02D6，返回 1.0（功率比中性值）；
                |dB| 超 380.0 dB 硬限时按方向饱和至 1.0E38 / 1.0E-38，置信息级 16#0001_01F0；
                硬限取 380.0 dB 而非 400.0 dB 的理由：功率型 400 dB 对应比值 10^40，
                超出 REAL 最大有限值 3.402823E38，饱和值本身不可表；380 dB 对应 10^±38，两端均可表；
                钳位方向：双侧饱和（dB 域 ±380.0 dB，比值域 1.0E-38 ~ 1.0E38）。
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜非有限防御闸 / segment 2, non-finite guard
// 段 3｜dB 域硬限双侧饱和 / segment 3, two-sided dB domain saturation
// 段 4｜主体幂运算与结果复检（末段） / segment 4, main power computation and result re-check (final)
    fDb : REAL; // 功率型分贝值，建议域 −380.0~+380.0 [dB] / power decibel value, suggested domain -380.0..+380.0 [dB]
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_01F0 dB 值超 ±380.0 dB 硬限，已按方向饱和——信息级，正常防御
                16#0001_01F1 预留禁用（信息级，不得挪用）
                16#0001_02D6 非有限输入（NaN 或 ±INF）——故障级，返回 1.0
                16#0001_02D7 预留禁用（故障级，不得挪用）
                16#0001_02D8 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_PwrDbToRatio : REAL
VAR_INPUT
    fDb : REAL; // 功率型分贝值，建议域 −380.0~+380.0 [dB] / power decibel value, suggested domain -380.0..+380.0 [dB]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_DB_PWR_DIV     : REAL := 10.0;     // 功率型 dB 换算除子（10·log10 的逆向） [dB] / power dB divisor, inverse of 10*log10 [dB]
    DL_DB_TEN         : REAL := 10.0;     // 幂运算底数 10 [无量纲] / power base 10 [dimensionless]
    DL_DB_PWR_LIMIT   : REAL := 380.0;    // 功率型 dB 域双侧硬限，对应比值 10^±38（400 dB 会超出 REAL 域） [dB] / power dB hard limit, ratio 10^+/-38 [dB]
    DL_RATIO_NEUTRAL  : REAL := 1.0;      // 功率比中性值（0 dB 对应值，故障缺省返回） [比] / neutral power ratio (0 dB), fault default [ratio]
    DL_PWR_RATIO_MAX  : REAL := 1.0E38;   // 功率比上限 10^38，REAL 域可表 [比] / power ratio upper bound 10^38 [ratio]
    DL_PWR_RATIO_MIN  : REAL := 1.0E-38;  // 功率比下限 10^-38，REAL 域可表 [比] / power ratio lower bound 10^-38 [ratio]
    DL_REAL_INF_GUARD : LREAL := 4.0E38;  // REAL 域 ±INF 判定阈值，高于 REAL 最大有限值 3.402823E38 [无量纲] / REAL +/-INF guard above max finite REAL
END_VAR
VAR
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR
```

### 批 2｜TIME / TOD 标量转换族（DL_MathData / TimeConv，5 件，T0-5）

> 族内纪律：**TIME 无负语义**（负值只可能来自非法减法，处理方向统一为「钳 0 + 信息级记录」，与 R16 `FC_DL_TimeSubSat` 负差钳零口径完全一致）；**TIME 与整数域大小关系必须先判后用**（R54「比较预判、先判后算」）：TIME 域上限 4,294,967,295 ms（`T#49D17H2M47S295MS`），DINT 正域上限仅 2,147,483,647 ms（`T#24D20H31M23S647MS`），**两者不等价**，任何 TIME→DINT 都必须在 TIME 域先比较再转换，否则超 24.8 天的时间会经内建转换静默变成负数。

#### 4.2.1 `FC_DL_TimeToDintMs` —— TIME → DINT 毫秒（超域饱和）

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_MathData / TimeConv |
| 前缀 / 返回类型 | `FC_DL_` / `DINT` |
| 复杂度 / 批次 | 中 / 批 2 |
| function_tags | `iec-std-wrapper`, `time-convert` |
| 委托内建 | `TIME_TO_DINT()`（仅在其可表域内调用） |
| 码位 | 信息 `16#0001_01F2`（超 DINT 域饱和）/ `16#0001_01F3`（结果为负已钳零）；故障 `16#0001_02D9`/`02DA`/`02DB`（三槽全预留，TIME 为值类型无故障态） |

**语义**：返回 `tIn` 对应的毫秒整数。**溢出预判先行**：先在 TIME 域与 `DL_TIME_DINT_MAX`（2147483647 ms）比较，超限直接饱和输出 `DL_DINT_MAX`，**绝不把超限值送进 `TIME_TO_DINT`**（部分平台此时给负值）。

**防御点**：
1. `tIn > DL_TIME_DINT_MAX` → 输出 `2147483647` + 信息 `01F2`；
2. 转换结果为负（平台 TIME 内部为负/回绕，或上游用 `-` 直接减法得到负时间）→ 钳 `0` + 信息 `01F3`；
3. 无故障级路径（整数与 TIME 域均无 NaN/±INF 态），三个故障槽全部预留并在头注释声明。

**(a) 注释样板原文**

```iecst
    功能说明  : 将 TIME 值防御性转换为 DINT 毫秒数并作为返回值输出，域内委托平台内建 TIME_TO_DINT；
                溢出预判先行：先在 TIME 域与 2147483647 ms（T#24D20H31M23S647MS）比较，
                超限直接饱和输出 2147483647 并置信息级 16#0001_01F2，
                严禁把超限值送进 TIME_TO_DINT（部分平台此时返回负值，静默翻转语义）；
                转换结果为负（负 TIME 或平台回绕）时钳 0 并置信息级 16#0001_01F3；
                钳位方向：上界饱和至 2147483647 ms，下界钳 0 ms；
                纯值类型域无 NaN/±INF 态，故无故障级路径（三个故障槽预留）。
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜上界预判与饱和（先判后算，禁先转换） / segment 2, upper bound pre-check and saturation (compare before convert)
// 段 3｜域内委托转换与负值钳零（末段） / segment 3, in-domain delegated conversion and negative clamp (final)
    tIn : TIME; // 待转换时间值，有效域 0 ms ~ 4294967295 ms [ms] / time value to convert, domain 0 ms .. 4294967295 ms [ms]
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_01F2 输入超 DINT 毫秒域（> 2147483647 ms），已饱和——信息级，正常防御
                16#0001_01F3 转换结果为负（负 TIME 或平台回绕），已钳 0——信息级，正常防御
                16#0001_02D9 预留禁用（故障级，不得挪用）
                16#0001_02DA 预留禁用（故障级，不得挪用）
                16#0001_02DB 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_TimeToDintMs : DINT
VAR_INPUT
    tIn : TIME; // 待转换时间值，有效域 0 ms ~ 4294967295 ms [ms] / time value to convert, domain 0 ms .. 4294967295 ms [ms]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_TIME_DINT_MAX : TIME := T#24D20H31M23S647MS; // DINT 正域可承载的最大毫秒数 2147483647 ms [ms] / max ms a DINT can carry, 2147483647 ms [ms]
    DL_DINT_MAX_MS   : DINT := 2147483647;          // 上界饱和输出值 [ms] / upper saturation output [ms]
    DL_MS_MIN        : DINT := 0;                   // 下界钳位值（TIME 无负语义） [ms] / lower clamp, TIME has no negative semantics [ms]
END_VAR
VAR
    nOut : DINT; // 域内转换中间结果 [ms] / in-domain conversion intermediate [ms]
END_VAR
```

---

#### 4.2.2 `FC_DL_DintMsToTime` —— DINT 毫秒 → TIME（负值钳零）

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_MathData / TimeConv |
| 前缀 / 返回类型 | `FC_DL_` / `TIME` |
| 复杂度 / 批次 | 低 / 批 2 |
| function_tags | `iec-std-wrapper`, `time-convert` |
| 委托内建 | `DINT_TO_TIME()` |
| 码位 | 信息 `16#0001_01F4`（负值钳 T#0S）/ `16#0001_01F5`（预留）；故障 `16#0001_02DC`/`02DD`/`02DE`（三槽全预留） |

**语义**：返回 `nMs` 对应 TIME。**结构性命中声明（必须写进头注释）**：DINT 正域上限 2,147,483,647 ms < TIME 域上限 4,294,967,295 ms，故**只有负值需要防御，上溢结构性不可能**——不需要也不允许写 `> TIME 上限` 的假分支。

**防御点**：
1. `nMs < 0` → 输出 `T#0S` + 信息 `01F4`（TIME 无负语义）；
2. 无上溢分支（结构性证明写进头注释，防下轮误加）；
3. 无故障级路径。

**(a) 注释样板原文**

```iecst
    功能说明  : 将 DINT 毫秒数防御性转换为 TIME 并作为返回值输出，域内委托平台内建 DINT_TO_TIME；
                负值（TIME 无负语义）钳为 T#0S 并置信息级 16#0001_01F4；
                上溢结构性不可能：DINT 正域上限 2147483647 ms 小于 TIME 域上限 4294967295 ms，
                故本件不设上界饱和分支（该结论已在此声明，后续轮次不得误加上溢假分支）；
                钳位方向：下界钳 0 ms，上界无需要钳；
                纯值类型域无 NaN/±INF 态，故无故障级路径（三个故障槽预留）。
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜负值防御闸（TIME 无负语义） / segment 2, negative guard (TIME has no negative semantics)
// 段 3｜域内委托转换（末段） / segment 3, in-domain delegated conversion (final)
    nMs : DINT; // 毫秒数，有效域 0 ~ 2147483647 ms [ms] / milliseconds, valid domain 0 .. 2147483647 ms [ms]
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_01F4 负毫秒输入（TIME 无负语义），已钳 T#0S——信息级，正常防御
                16#0001_01F5 预留禁用（信息级，不得挪用）
                16#0001_02DC 预留禁用（故障级，不得挪用）
                16#0001_02DD 预留禁用（故障级，不得挪用）
                16#0001_02DE 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_DintMsToTime : TIME
VAR_INPUT
    nMs : DINT; // 毫秒数，有效域 0 ~ 2147483647 ms（负值钳 0） [ms] / milliseconds, valid domain 0 .. 2147483647 ms, negative clamps to 0 [ms]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_TIME_ZERO : TIME := T#0S; // TIME 零值（负值钳位结果与故障缺省） [ms] / TIME zero value, negative clamp and fault default [ms]
END_VAR
```

---

#### 4.2.3 `FC_DL_TimeToLrealSec` —— TIME → LREAL 秒

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_MathData / TimeConv |
| 前缀 / 返回类型 | `FC_DL_` / `LREAL` |
| 复杂度 / 批次 | 低 / 批 2 |
| function_tags | `iec-std-wrapper`, `time-convert` |
| 委托内建 | `TIME_TO_LREAL()` 后除 `DL_MS_PER_SEC`（1000.0，编译期常量恒非零） |
| 码位 | 信息 `16#0001_01F6`（负 TIME 记录）/ `16#0001_01F7`（预留）；故障 `16#0001_02DF`/`02E0`/`02E1`（三槽全预留） |

**语义**：返回秒（LREAL），供节拍计算、速度（mm/s）、加速度等后续算法直接使用，省去每个调用点自己写 `/1000.0`（现场单位混用高频错误源）。

**防御点**：
1. 无上溢风险：TIME 最大 4,294,967,295 ms ≪ 2^53，LREAL 精确可表（结构性声明写进头注释）；
2. 负 TIME → **照转**（LREAL 可承载负值，且此处是「观测/记录」语义，钳零会掩盖上游非法减法）并置信息 `01F6`，`bValid=TRUE`；
3. 除法除子为常量 `1000.0`，编译期非零，满足除零红线（头注释声明）。

**(a) 注释样板原文**

```iecst
    功能说明  : 将 TIME 值转换为 LREAL 秒数并作为返回值输出（节拍/速度/加速度算法的标准入口）；
                先委托平台内建 TIME_TO_LREAL 取毫秒数值，再除以常量 1000.0 得秒；
                除子为编译期常量 1000.0 恒非零，结构性满足除法前判除子非零红线；
                无上溢风险：TIME 域上限 4294967295 ms 远小于 2^53，LREAL 精确可表；
                负 TIME 照转不钳零（本件为观测语义，钳零会掩盖上游非法减法）并置信息级 16#0001_01F6；
                钳位方向：无钳位（仅记录负值，输出值与输入严格等价）。
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜毫秒数值整备与负值记录 / segment 2, millisecond preparation and negative value recording
// 段 3｜毫秒转秒（末段） / segment 3, milliseconds to seconds (final)
    tIn : TIME; // 待转换时间值 [ms] / time value to convert [ms]
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_01F6 负 TIME 输入（照转不钳零，仅记录）——信息级，正常防御
                16#0001_01F7 预留禁用（信息级，不得挪用）
                16#0001_02DF 预留禁用（故障级，不得挪用）
                16#0001_02E0 预留禁用（故障级，不得挪用）
                16#0001_02E1 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_TimeToLrealSec : LREAL
VAR_INPUT
    tIn : TIME; // 待转换时间值，有效域 0 ms ~ 4294967295 ms [ms] / time value to convert, domain 0 ms .. 4294967295 ms [ms]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_MS_PER_SEC : LREAL := 1000.0; // 毫秒/秒换算除子（编译期常量，恒非零） [ms/s] / ms-per-second divisor, compile-time constant, never zero [ms/s]
END_VAR
VAR
    fMsL : LREAL; // 毫秒数值（LREAL 承载） [ms] / millisecond value carried in LREAL [ms]
END_VAR
```

---

#### 4.2.4 `FC_DL_LrealSecToTime` —— LREAL 秒 → TIME（三路防御）

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_MathData / TimeConv |
| 前缀 / 返回类型 | `FC_DL_` / `TIME` |
| 复杂度 / 批次 | 中 / 批 2 |
| function_tags | `iec-std-wrapper`, `time-convert` |
| 委托内建 | `LREAL_TO_TIME()`（仅在其可表域内调用） |
| 码位 | 信息 `16#0001_01F8`（负值钳 T#0S）/ `16#0001_01F9`（超上限饱和）；故障 `16#0001_02E2`（非有限）/ `16#0001_02E3`（预留）/ `16#0001_02E4`（预留） |

**语义**：秒（LREAL，来自 HMI 录入、配方、比例运算）→ TIME。**溢出预判先行**：先在 LREAL 域与 `4294967.295 s` 比较，超限饱和至 `T#49D17H2M47S295MS`，**之后**才乘 1000 并转 TIME。

**防御点**：
1. 非有限（NaN / ±INF）→ 故障 `02E2`，返回 `T#0S`；
2. `fSec < 0.0` → 钳 `T#0S` + 信息 `01F8`；
3. `fSec > DL_SEC_MAX (4294967.295 s)` → 饱和 `T#49D17H2M47S295MS` + 信息 `01F9`；
4. 三路判定顺序固定：非有限 → 负值 → 超上限（先严后宽，故障优先 `RETURN`）。

**(a) 注释样板原文**

```iecst
    功能说明  : 将 LREAL 秒数防御性转换为 TIME 并作为返回值输出，域内委托平台内建 LREAL_TO_TIME；
                非有限输入（NaN 或 ±INF）判为故障级 16#0001_02E2，返回 T#0S 且 bValid=FALSE；
                负值（TIME 无负语义）钳为 T#0S 并置信息级 16#0001_01F8；
                溢出预判先行：先在 LREAL 域与 4294967.295 s（对应 4294967295 ms）比较，
                超限直接饱和输出 T#49D17H2M47S295MS 并置信息级 16#0001_01F9，
                严禁把超限值乘 1000 后送进 LREAL_TO_TIME（先算后判必溢出）；
                钳位方向：下界钳 0 s，上界饱和至 TIME 域上限。
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜非有限防御闸 / segment 2, non-finite guard
// 段 3｜负值闸与上界预判饱和 / segment 3, negative gate and upper-bound pre-check saturation
// 段 4｜域内换算委托转换（末段） / segment 4, in-domain scaling and delegated conversion (final)
    fSec : LREAL; // 秒数，有效域 0.0 ~ 4294967.295 s [s] / seconds, valid domain 0.0 .. 4294967.295 s [s]
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_01F8 负秒输入（TIME 无负语义），已钳 T#0S——信息级，正常防御
                16#0001_01F9 秒数超 TIME 域上限（4294967.295 s），已饱和——信息级，正常防御
                16#0001_02E2 非有限输入（NaN 或 ±INF）——故障级，返回 T#0S
                16#0001_02E3 预留禁用（故障级，不得挪用）
                16#0001_02E4 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_LrealSecToTime : TIME
VAR_INPUT
    fSec : LREAL; // 秒数，有效域 0.0 ~ 4294967.295 s（负值钳 0，超限饱和） [s] / seconds, valid domain 0.0 .. 4294967.295 s, negative clamps, overflow saturates [s]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_SEC_MAX        : LREAL := 4294967.295;                     // TIME 域上限对应秒数（4294967295 ms） [s] / seconds equal to the TIME upper bound, 4294967295 ms [s]
    DL_SEC_MIN        : LREAL := 0.0;                             // 秒域下界 [s] / seconds lower bound [s]
    DL_MS_PER_SEC     : LREAL := 1000.0;                          // 秒转毫秒乘子（编译期常量） [ms/s] / seconds-to-milliseconds multiplier [ms/s]
    DL_TIME_MAX       : TIME  := T#49D17H2M47S295MS;              // TIME 域上限 4294967295 ms [ms] / TIME upper bound, 4294967295 ms [ms]
    DL_TIME_ZERO      : TIME  := T#0S;                            // TIME 零值（负值钳位与故障缺省） [ms] / TIME zero value, negative clamp and fault default [ms]
    DL_LREAL_HUGE     : LREAL := 1.7976931348623157E308;          // LREAL 最大有限幅值，超过即判 ±INF [无量纲] / max finite LREAL magnitude, beyond means +/-INF [dimensionless]
END_VAR
VAR
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR
```

---

#### 4.2.5 `FC_DL_TodToDintMs` —— TOD → 当日毫秒偏移

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_MathData / TimeConv |
| 前缀 / 返回类型 | `FC_DL_` / `DINT` |
| 复杂度 / 批次 | 中 / 批 2 |
| function_tags | `iec-std-wrapper`, `time-convert` |
| 委托内建 | `TOD_TO_TIME()` → `TIME_TO_DINT()`（**标准转换链，严禁自行 `h*3600000 + m*60000` 累加**） |
| 码位 | 信息 `16#0001_01FA`（域外钳位）/ `16#0001_01FB`（预留）；故障 `16#0001_02E5`/`02E6`/`02E7`（三槽全预留） |

**语义**：TOD（当日时刻）→ 当日 0 点起的毫秒偏移，有效域 `0 ~ 86399999`。班次/排程/时窗判定（`FB_DL_TimeWindowCheck` 家族的配套件）的整数入口。

**防御点**：
1. 转换结果 `< 0` → 钳 `0` + 信息 `01FA`；
2. 转换结果 `> DL_TOD_MAX_MS (86399999)` → 钳 `86399999` + 信息 `01FA`（同一业务语义「TOD 域外」，不另立码）；
3. **编译验证门槛（强制）**：本件依赖 `TOD_TO_TIME` 链，交付前必须在 CODESYS / TwinCAT / InoProShop **各编译一次**；若某平台缺该转换，改用 `TIME_TO_DINT(todIn)` 隐式口径并在 `RAW_NOTES_R17.md` 留痕（不得自实现时分秒累加）。

**(a) 注释样板原文**

```iecst
    功能说明  : 将 TOD（当日时刻）转换为当日 0 点起的毫秒偏移并作为返回值输出，
                内部委托标准转换链 TOD_TO_TIME 再 TIME_TO_DINT，不自行按小时/分/秒累加
                （自实现累加会把时区、闰秒、平台 TOD 精度差异一并写进业务代码）；
                结果越出 0 ~ 86399999 ms 时按方向钳位并置信息级 16#0001_01FA；
                钳位方向：下界 0 ms，上界 86399999 ms（24h − 1 ms）；
                纯值类型域无 NaN/±INF 态，故无故障级路径（三个故障槽预留）；
                交付门槛：本件因依赖 TOD_TO_TIME 链，须在 CODESYS / TwinCAT / InoProShop 三平台各编译验证一次。
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜标准转换链整备 / segment 2, standard conversion chain preparation
// 段 3｜当日毫秒域钳位（末段） / segment 3, day-millisecond domain clamp (final)
    todIn : TOD; // 当日时刻，有效域 00:00:00 ~ 23:59:59.999 [ms since 00:00:00] / time of day, domain 00:00:00 .. 23:59:59.999 [ms since midnight]
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_01FA TOD 转换结果越出 0 ~ 86399999 ms，已按方向钳位——信息级，正常防御
                16#0001_01FB 预留禁用（信息级，不得挪用）
                16#0001_02E5 预留禁用（故障级，不得挪用）
                16#0001_02E6 预留禁用（故障级，不得挪用）
                16#0001_02E7 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_TodToDintMs : DINT
VAR_INPUT
    todIn : TOD; // 当日时刻，有效域 00:00:00 ~ 23:59:59.999 [ms since 00:00:00] / time of day, domain 00:00:00 .. 23:59:59.999 [ms since midnight]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_TOD_MAX_MS : DINT := 86399999; // 当日毫秒上界（24h − 1 ms） [ms] / day upper bound, 24h minus 1 ms [ms]
    DL_TOD_MIN_MS : DINT := 0;        // 当日毫秒下界 [ms] / day lower bound [ms]
END_VAR
VAR
    nMs : DINT; // 当日毫秒偏移中间结果 [ms] / intermediate day-millisecond offset [ms]
END_VAR
```

### 批 3｜精度告警与宽窄域饱和族（DL_MathData / Convert，5 件，T0-5）

> 族内纪律：**两种业务语义必须分开**——「精度告警」= 值照转 + 信息级（`bError=FALSE`、`bValid=TRUE`，R16 `FC_DL_LintToLrealChk` 先例）；「域外饱和」= 值钳位 + 信息级；「非有限」= 故障级 `bValid=FALSE`。**有符号极值的单侧比较一律用双侧比较式，禁用 `ABS()`**（R55：`ABS(LINT 最小值)` 会回绕漏判）。**整数下限常量不得写字面量 `-2147483648` / `-9223372036854775808`**（部分编译器把负号解析为对一个越界正字面量取负），一律用 `-DL_XXX_MAX - 1` 计算式。

#### 4.3.1 `FC_DL_DintToRealChk` —— DINT → REAL 精度告警

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_MathData / Convert |
| 前缀 / 返回类型 | `FC_DL_` / `REAL` |
| 复杂度 / 批次 | 低 / 批 3 |
| function_tags | `iec-std-wrapper`, `precision-chk` |
| 委托内建 | `DINT_TO_REAL()` |
| 码位 | 信息 `16#0001_01FC`（超 2^24 精度告警）/ `16#0001_01FD`（预留）；故障 `16#0001_02E8`/`02E9`/`02EA`（三槽全预留，整数域与 REAL 目标域均无故障路径） |

**语义**：`REAL` 尾数 24 位 → 整数仅 `|x| ≤ 2^24 = 16,777,216` 可精确表示；超此域**值照转**（转成最近可表值）并置信息级告警 —— 典型现场：累计流量/总产量/位置脉冲数（DINT）转 REAL 后末几位静默丢精度。

**防御点**：
1. `nIn > DL_F24_MAX` 或 `nIn < -DL_F24_MAX`（**双侧比较，禁 `ABS()`**）→ 值照转 + 信息 `01FC`，`bValid=TRUE`；
2. 无故障级路径（整数输入无 NaN/±INF 态，REAL 目标全域含 DINT 全域）；
3. 头注释必须写明「本件只告警不钳位」，防下游误以为值被改。

**(a) 注释样板原文**

```iecst
    功能说明  : 将 DINT 防御性转换为 REAL 并作为返回值输出，转换委托平台内建 DINT_TO_REAL；
                |nIn| 超过 2^24（16777216，REAL 尾数 24 位可精确表示的整数上界）时，
                值照常转换输出，仅置信息级 16#0001_01FC 提示低位精度损失（bError=FALSE、bValid=TRUE）；
                极值对称性防御：采用双侧比较 nIn > 上界 OR nIn < -上界，
                禁用 ABS(nIn) 单侧比较（对 DINT 最小值无回绕，但保持与 R16 LintToLrealChk 同范式，避免后续升位改造引入回绕）；
                钳位方向：无钳位（信息级仅记录，转换结果为最接近的可表值）。
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜24 位尾数精度极限判定与主体转换（末段） / segment 2, 24-bit significand precision check and main conversion (final)
    nIn : DINT; // 待转换整数值 [无量纲] / integer value to convert [dimensionless]
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_01FC |nIn| 超 2^24 精度极限，转换值低位可能失真——信息级，正常防御
                16#0001_01FD 预留禁用（信息级，不得挪用）
                16#0001_02E8 预留禁用（故障级，不得挪用）
                16#0001_02E9 预留禁用（故障级，不得挪用）
                16#0001_02EA 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_DintToRealChk : REAL
VAR_INPUT
    nIn : DINT; // 待转换整数值，建议域 ±2147483647 [无量纲] / integer value to convert, suggested domain +/-2147483647 [dimensionless]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_F24_MAX : DINT := 16777216; // REAL 尾数 24 位可精确表示的整数上界 2^24 [无量纲] / 2^24 exact-integer bound of REAL's 24-bit significand [dimensionless]
    DL_REAL_ZERO : REAL := 0.0;    // 返回值预置零（本件无故障路径，仅作预置约定） [无量纲] / preset zero, no fault path in this component [dimensionless]
END_VAR
```

---

#### 4.3.2 `FC_DL_UdintToRealChk` —— UDINT → REAL 精度告警

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_MathData / Convert |
| 前缀 / 返回类型 | `FC_DL_` / `REAL` |
| 复杂度 / 批次 | 低 / 批 3 |
| function_tags | `iec-std-wrapper`, `precision-chk` |
| 委托内建 | `UDINT_TO_REAL()` |
| 码位 | 信息 `16#0001_01FE`（超 2^24 精度告警）/ `16#0001_01FF`（预留）；故障 `16#0001_02EB`/`02EC`/`02ED`（三槽全预留） |

**语义**：无符号版精度告警。UDINT 全域 `0 ~ 4294967295` 远超 2^24，**累计电量/总脉冲/累计流量（UDINT）转 REAL 是精度丢失重灾区**。

**防御点**：
1. `nIn > DL_F24_MAX_U (16777216)` → 值照转 + 信息 `01FE`；
2. 无负值分支（无符号类型系统保证，需在头注释声明「负值分支结构性不存在」）；
3. **头注释必须写明「`UDINT → LREAL` 恒无损（≤2^32 < 2^53），本族不立该件」**，防下轮重复立项。

**(a) 注释样板原文**

```iecst
    功能说明  : 将 UDINT 防御性转换为 REAL 并作为返回值输出，转换委托平台内建 UDINT_TO_REAL；
                nIn 超过 2^24（16777216，REAL 尾数 24 位可精确表示的整数上界）时，
                值照常转换输出，仅置信息级 16#0001_01FE 提示低位精度损失（bError=FALSE、bValid=TRUE）；
                负值分支结构性不存在（UDINT 为无符号类型，由类型系统保证），故无下界比较；
                本件只对 REAL 目标域立项：UDINT 全域 ≤ 2^32 远小于 2^53，转 LREAL 恒无损，
                故不设 UDINT 到 LREAL 的告警件（该结论在此声明，后续轮次不得重复立项）；
                钳位方向：无钳位（信息级仅记录，转换结果为最接近的可表值）。
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜24 位尾数精度极限判定与主体转换（末段） / segment 2, 24-bit significand precision check and main conversion (final)
    nIn : UDINT; // 待转换无符号整数值，建议域 0 ~ 4294967295 [无量纲] / unsigned integer to convert, suggested domain 0 .. 4294967295 [dimensionless]
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_01FE nIn 超 2^24 精度极限，转换值低位可能失真——信息级，正常防御
                16#0001_01FF 预留禁用（信息级，不得挪用）
                16#0001_02EB 预留禁用（故障级，不得挪用）
                16#0001_02EC 预留禁用（故障级，不得挪用）
                16#0001_02ED 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_UdintToRealChk : REAL
VAR_INPUT
    nIn : UDINT; // 待转换无符号整数值，建议域 0 ~ 4294967295 [无量纲] / unsigned integer to convert, suggested domain 0 .. 4294967295 [dimensionless]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_F24_MAX_U : UDINT := 16777216; // REAL 尾数 24 位可精确表示的无符号整数上界 2^24 [无量纲] / 2^24 exact-integer bound of REAL's 24-bit significand [dimensionless]
    DL_REAL_ZERO : REAL  := 0.0;      // 返回值预置零（本件无故障路径，仅作预置约定） [无量纲] / preset zero, no fault path in this component [dimensionless]
END_VAR
```

---

#### 4.3.3 `FC_DL_LintToDintSat` —— LINT → DINT 双向域外饱和

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_MathData / Convert |
| 前缀 / 返回类型 | `FC_DL_` / `DINT` |
| 复杂度 / 批次 | 低 / 批 3 |
| function_tags | `iec-std-wrapper`, `sat-convert` |
| 委托内建 | `LINT_TO_DINT()`（**仅在其可表域内调用**；界值直接取常量，不调转换） |
| 码位 | 信息 `16#0001_0200`（上溢饱和）/ `16#0001_0201`（下溢饱和）；故障 `16#0001_02EE`/`02EF`/`02F0`（三槽全预留，整数域无故障态） |

**语义**：64 位有符号累计量（长周期产量、累计脉冲、微秒时间戳）→ 32 位寄存器/引脚域（DINT），**域外饱和不回绕**。这是 R16 `FC_DL_UdintToDintChk`（无符号源）与 `FC_DL_DintToUintSat`（有符号源 → 无符号目标）之外的**有符号宽→有符号窄**缺口件。

**防御点**：
1. `nIn > DL_DINT_MAX_L (2147483647)` → 输出 `DL_DINT_MAX` + 信息 `0200`；
2. `nIn < DL_DINT_MIN_L (-2147483648)` → 输出 `-DL_DINT_MAX - 1`（**计算式，禁字面量 `-2147483648`**）+ 信息 `0201`；
3. 双侧比较，**禁用 `ABS()`**（R55）；
4. 无故障级路径。

**(a) 注释样板原文**

```iecst
    功能说明  : 将 LINT 防御性转换为 DINT 并作为返回值输出，域内转换委托平台内建 LINT_TO_DINT；
                nIn 超 DINT 上界 2147483647 时饱和输出 2147483647 并置信息级 16#0001_0200；
                nIn 低于 DINT 下界 −2147483648 时饱和输出 −2147483648 并置信息级 16#0001_0201；
                下界输出采用计算式 -DL_DINT_MAX - 1，禁用 -2147483648 字面量
                （部分编译器把负号解析为对一个越界正字面量取负，产生告警或错误结果）；
                极值比较采用双侧比较，禁用 ABS(nIn)（R55：有符号极值取绝对值会回绕漏判）；
                钳位方向：双侧饱和（−2147483648 ~ 2147483647），绝不回绕；
                纯整数域无 NaN/±INF 态，故无故障级路径（三个故障槽预留）。
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜上界预判与饱和 / segment 2, upper bound pre-check and saturation
// 段 3｜下界预判与饱和 / segment 3, lower bound pre-check and saturation
// 段 4｜域内委托转换（末段） / segment 4, in-domain delegated conversion (final)
    nIn : LINT; // 待转换 64 位有符号整数 [无量纲] / signed 64-bit integer to convert [dimensionless]
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_0200 nIn 超 DINT 上界，已饱和至 2147483647——信息级，正常防御
                16#0001_0201 nIn 低于 DINT 下界，已饱和至 −2147483648——信息级，正常防御
                16#0001_02EE 预留禁用（故障级，不得挪用）
                16#0001_02EF 预留禁用（故障级，不得挪用）
                16#0001_02F0 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_LintToDintSat : DINT
VAR_INPUT
    nIn : LINT; // 待转换 64 位有符号整数，建议域 ±9223372036854775807 [无量纲] / signed 64-bit integer to convert, suggested domain +/-9223372036854775807 [dimensionless]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_DINT_MAX_L : LINT := 2147483647;  // DINT 上界，用 LINT 承载以便域外比较 [无量纲] / DINT upper bound carried in LINT for out-of-domain comparison [dimensionless]
    DL_DINT_MIN_L : LINT := -2147483648; // DINT 下界，用 LINT 承载以便域外比较 [无量纲] / DINT lower bound carried in LINT for out-of-domain comparison [dimensionless]
    DL_DINT_MAX   : DINT := 2147483647;  // 上界饱和输出值 [无量纲] / upper saturation output [dimensionless]
    DL_DINT_ZERO  : DINT := 0;           // 返回值预置零（本件无故障路径） [无量纲] / preset zero, no fault path in this component [dimensionless]
END_VAR
```

---

#### 4.3.4 `FC_DL_RealToLintSat` —— REAL → LINT 域外饱和

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_MathData / Convert |
| 前缀 / 返回类型 | `FC_DL_` / `LINT` |
| 复杂度 / 批次 | 中 / 批 3 |
| function_tags | `iec-std-wrapper`, `sat-convert` |
| 委托内建 | `REAL_TO_LREAL()` 升位（**先升位再比较**）+ `TRUNC()` + `LREAL_TO_LINT()` |
| 码位 | 信息 `16#0001_0202`（域外饱和）/ `16#0001_0203`（预留）；故障 `16#0001_02F1`（非有限）/ `16#0001_02F2`（预留）/ `16#0001_02F3`（预留） |

**语义**：REAL 源（HMI 录入、比例运算结果）→ LINT（64 位计数器/时间戳域），向零截断。

**防御点**：
1. 非有限 → 故障 `02F1`，返回 `0`；
2. **升位先行**：`fLr := REAL_TO_LREAL(fIn)` 后再与 LREAL 域界比较 —— REAL 只有 24 位尾数，直接用 REAL 常量比较会因界值本身不可表而漏判；
3. 超上界 → 饱和 `DL_LINT_MAX` + 信息 `0202`；低于下界 → 饱和 `-DL_LINT_MAX - 1` + 信息 `0202`（同一业务语义「域外饱和」，上下共用一码，方向写进头注释）；
4. 域内 `LREAL_TO_LINT(TRUNC(fLr))` —— 先 `TRUNC` 成整值 LREAL 再转，**避免 `LREAL_TO_LINT` 的舍入取向差异**；
5. 取整取向声明：**向零截断**（TRUNC 语义），头注释必须写明（R16 `LrealToDintSat` 同口径）。

**(a) 注释样板原文**

```iecst
    功能说明  : 将 REAL 防御性转换为 LINT 并作为返回值输出；
                非有限输入（NaN 或 ±INF）判为故障级 16#0001_02F1，返回 0 且 bValid=FALSE；
                取整取向声明：向零截断（TRUNC 语义）后钳位，与 R16 FC_DL_LrealToDintSat 同口径；
                升位先行：先 REAL_TO_LREAL 升位再与 LREAL 域界比较，
                禁用 REAL 常量直接比较（REAL 尾数仅 24 位，域界值本身不可精确表示，会漏判）；
                域外按方向饱和（上界 9223372036854775807 / 下界 −9223372036854775808）
                并置信息级 16#0001_0202；下界用 -DL_LINT_MAX - 1 计算式，禁字面量；
                钳位方向：双侧饱和，绝不回绕。
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜非有限防御闸 / segment 2, non-finite guard
// 段 3｜升位与域外判定饱和 / segment 3, widening and out-of-domain saturation
// 段 4｜域内向零截断与委托转换（末段） / segment 4, in-domain truncate-toward-zero and delegated conversion (final)
    fIn : REAL; // 待转换浮点值，建议域 ±9.2E18 [无量纲] / floating value to convert, suggested domain +/-9.2E18 [dimensionless]
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_0202 输入超 LINT 域，已按符号饱和——信息级，正常防御
                16#0001_0203 预留禁用（信息级，不得挪用）
                16#0001_02F1 非有限输入（NaN 或 ±INF）——故障级，返回 0
                16#0001_02F2 预留禁用（故障级，不得挪用）
                16#0001_02F3 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_RealToLintSat : LINT
VAR_INPUT
    fIn : REAL; // 待转换浮点值，建议域 ±9.2E18（非有限拦截，域外饱和） [无量纲] / floating value to convert, suggested domain +/-9.2E18 [dimensionless]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_LINT_MAX_LR : LREAL := 9.2233720368547758E18;  // LINT 域上界在 LREAL 域的精确可表近似值 [无量纲] / LINT upper bound represented in LREAL [dimensionless]
    DL_LINT_MAX    : LINT  := 9223372036854775807;    // LINT 上界饱和输出值 [无量纲] / LINT upper saturation output [dimensionless]
    DL_LINT_ZERO   : LINT  := 0;                      // 故障缺省返回值 [无量纲] / fault default return value [dimensionless]
    DL_REAL_INF_GUARD : LREAL := 4.0E38;              // REAL 域 ±INF 判定阈值，高于 REAL 最大有限值 3.402823E38 [无量纲] / REAL +/-INF guard above max finite REAL
END_VAR
VAR
    fLr        : LREAL; // 升位后的 LREAL 中间量 [无量纲] / widened LREAL intermediate [dimensionless]
    bNonFinite : BOOL;  // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR
```

---

#### 4.3.5 `FC_DL_LrealToLintSat` —— LREAL → LINT 域外饱和

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_MathData / Convert |
| 前缀 / 返回类型 | `FC_DL_` / `LINT` |
| 复杂度 / 批次 | 中 / 批 3 |
| function_tags | `iec-std-wrapper`, `sat-convert` |
| 委托内建 | `TRUNC()` + `LREAL_TO_LINT()` |
| 码位 | 信息 `16#0001_0204`（域外饱和）/ `16#0001_0205`（预留）；故障 `16#0001_02F4`（非有限）/ `16#0001_02F5`（预留）/ `16#0001_02F6`（预留） |

**语义**：LREAL 源版，无需升位（源已是 64 位浮点）。**与 4.3.4 的职责边界必须写进两件头注释**：源类型不同（IEC 61131-3 无 `ANY_REAL` 泛型），库内既定为双版本策略（R16 `FC_DL_LrealToDintSat` 先例）。

**防御点**：
1. 非有限 → 故障 `02F4`，返回 `0`；
2. 超 `±9.2233720368547758E18` → 饱和 + 信息 `0204`（下界 `-DL_LINT_MAX - 1`）；
3. 域内 `LREAL_TO_LINT(TRUNC(fIn))`，向零截断取向声明。

**(a) 注释样板原文**

```iecst
    功能说明  : 将 LREAL 防御性转换为 LINT 并作为返回值输出；
                非有限输入（NaN 或 ±INF）判为故障级 16#0001_02F4，返回 0 且 bValid=FALSE；
                取整取向声明：向零截断（TRUNC 语义）后钳位，与 FC_DL_RealToLintSat 及
                R16 FC_DL_LrealToDintSat 同口径；
                与 FC_DL_RealToLintSat 的职责边界：源类型不同（IEC 61131-3 无 ANY_REAL 泛型），
                双版本是库内既定策略（R16 饱和转换族先例），不做类型合并；
                域外按方向饱和（上界 9223372036854775807 / 下界 −9223372036854775808）
                并置信息级 16#0001_0204；下界用 -DL_LINT_MAX - 1 计算式，禁字面量；
                钳位方向：双侧饱和，绝不回绕。
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜非有限防御闸 / segment 2, non-finite guard
// 段 3｜域外判定饱和与域内截断转换（末段） / segment 3, out-of-domain saturation and in-domain truncate conversion (final)
    fIn : LREAL; // 待转换 64 位浮点值，建议域 ±9.2E18 [无量纲] / 64-bit floating value to convert, suggested domain +/-9.2E18 [dimensionless]
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_0204 输入超 LINT 域，已按符号饱和——信息级，正常防御
                16#0001_0205 预留禁用（信息级，不得挪用）
                16#0001_02F4 非有限输入（NaN 或 ±INF）——故障级，返回 0
                16#0001_02F5 预留禁用（故障级，不得挪用）
                16#0001_02F6 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_LrealToLintSat : LINT
VAR_INPUT
    fIn : LREAL; // 待转换 64 位浮点值，建议域 ±9.2E18（非有限拦截，域外饱和） [无量纲] / 64-bit floating value to convert, suggested domain +/-9.2E18 [dimensionless]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_LINT_MAX_LR    : LREAL := 9.2233720368547758E18;          // LINT 域上界在 LREAL 域的精确可表近似值 [无量纲] / LINT upper bound represented in LREAL [dimensionless]
    DL_LINT_MAX       : LINT  := 9223372036854775807;            // LINT 上界饱和输出值 [无量纲] / LINT upper saturation output [dimensionless]
    DL_LINT_ZERO      : LINT  := 0;                              // 故障缺省返回值 [无量纲] / fault default return value [dimensionless]
    DL_LREAL_HUGE     : LREAL := 1.7976931348623157E308;         // LREAL 最大有限幅值，超过即判 ±INF [无量纲] / max finite LREAL magnitude, beyond means +/-INF [dimensionless]
END_VAR
VAR
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR
```

### 批 4｜LWORD 64 位数据域（DL_Base 位串 4 件 + DL_MathData 精度 1 件，T0-7 重载）

> 族内纪律：**移位量 ≥ 位宽一律走常量路径，绝不送进内建 `SHL/SHR`**（部分编译器对移位量 ≥ 位宽属未定义行为，与 R14 `FC_DL_ShlEx` 的 32 位口径完全同源）；**位移/循环件不返回值以外的诊断口径差异**，全部沿用 `eErr/bError/bValid` 三件套（**禁止**沿用 R14 时期的 `uDiag` 单出口写法，R15 惯例一致性整改已固化）；LWORD 为 IEC 61131-3 标准 64 位位串，库内 `FC_DL_BitArrayExtract` / `FC_DL_BitArrayInsert`（R12）已有 `LWORD` 类型变量与 `SHL(LWORD#1, …)` 先例，**无新增平台风险**。

#### 4.4.1 `FC_DL_ShlLwordEx` —— LWORD 左移（超宽置零）

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_Base / BitString |
| 前缀 / 返回类型 | `FC_DL_` / `LWORD` |
| 复杂度 / 批次 | 低 / 批 4 |
| function_tags | `iec-std-wrapper`, `lword-bitstring` |
| 委托内建 | `SHL(uIn, nN)`（**仅当 `nN < 64` 时调用**） |
| 码位 | 信息 `16#0001_0206`（移位量 ≥64 结果置零）/ `16#0001_0207`（预留）；故障 `16#0001_02F7`/`02F8`/`02F9`（三槽全预留，位串域无故障态） |

**语义**：LWORD 左移。`nN ≥ 64` 走常量路径直接输出 `16#0000_0000_0000_0000` + 信息 `0206`；`nN < 64` 委托内建 `SHL`。纯函数无状态。

**防御点**：
1. `nN >= DL_LW_WIDTH (64)` → 输出零 + 信息 `0206`，**不调用** `SHL`（头注释必须写明理由）；
2. `nN` 为 `USINT`，负移位量由类型系统结构性排除（头注释声明「无负移位量分支」）；
3. 位宽 `64` 提为常量 `DL_LW_WIDTH`，禁魔法数；
4. 输出与诊断首段双预置，任何路径不留脏值。

**(a) 注释样板原文**

```iecst
    功能说明  : LWORD 位串左移防御包装：移位量 nN 大于等于 64（位宽）时走常量路径直接输出全零，
                并置信息级 16#0001_0206，严禁把 nN ≥ 64 送进内建 SHL
                （部分编译器对该移位量属未定义行为或结果歧义，与 R14 FC_DL_ShlEx 的 32 位口径同源）；
                nN < 64 时委托平台内建 SHL，不重实现移位内核；
                nN 为 USINT 类型天然非负，负移位量结构性不可能（无负值防御分支）；
                位宽 64 提为只读常量，禁魔法数；
                钳位方向：移位量超宽按「结果置 0」处理（不做移位量截断，截断会静默改变语义）。
// 段 1｜输出与错误状态预置 / segment 1, preset output and error status
// 段 2｜移位量闸门（超宽走常量路径，不调内建） / segment 2, shift amount gate (oversized takes the constant path, built-in not called)
// 段 3｜域内委托移位（末段） / segment 3, in-domain delegated shift (final)
    nN : USINT; // 移位量 [bit]，USINT 天然非负，范围 0~255 / shift amount [bit], USINT is non-negative by type, range 0..255
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_0206 移位量 ≥ 64（位宽），结果已置全零——信息级，正常防御
                16#0001_0207 预留禁用（信息级，不得挪用）
                16#0001_02F7 预留禁用（故障级，不得挪用）
                16#0001_02F8 预留禁用（故障级，不得挪用）
                16#0001_02F9 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_ShlLwordEx : LWORD
VAR_INPUT
    uIn : LWORD; // 被移位位串 [位] / bit string to be shifted [bit]
    nN  : USINT; // 移位量 [bit]，USINT 天然非负，范围 0~255 / shift amount [bit], USINT is non-negative by type, range 0..255
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_LW_WIDTH : USINT := 64;                        // LWORD 位宽常量 [bit] / LWORD width constant [bit]
    DL_LW_ZERO  : LWORD := 16#0000_0000_0000_0000;     // 超宽移位结果零值 [位串] / zero result of an oversized shift [bit string]
END_VAR
```

---

#### 4.4.2 `FC_DL_ShrLwordEx` —— LWORD 逻辑右移（超宽置零）

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_Base / BitString |
| 前缀 / 返回类型 | `FC_DL_` / `LWORD` |
| 复杂度 / 批次 | 低 / 批 4 |
| function_tags | `iec-std-wrapper`, `lword-bitstring` |
| 委托内建 | `SHR(uIn, nN)`（**仅当 `nN < 64` 时调用**） |
| 码位 | 信息 `16#0001_0208`（移位量 ≥64 结果置零）/ `16#0001_0209`（预留）；故障 `16#0001_02FA`/`02FB`/`02FC`（三槽全预留） |

**语义**：LWORD 逻辑右移（高位补 0，非算术右移；`LWORD` 本身无符号，故与算术右移等价，头注释须点明「本件无符号位扩展语义」）。

**防御点**：同 4.4.1（`nN >= 64` → 零 + `0208`）；额外声明「不做符号位扩展，输入端为无符号位串」。

**(a) 注释样板原文**

```iecst
    功能说明  : LWORD 位串逻辑右移防御包装：移位量 nN 大于等于 64（位宽）时走常量路径直接输出全零，
                并置信息级 16#0001_0208，严禁把 nN ≥ 64 送进内建 SHR；
                nN < 64 时委托平台内建 SHR，不重实现移位内核；
                LWORD 为无符号位串，逻辑右移与算术右移等价，本件不做符号位扩展
                （若调用方需要符号语义，请先用 INT_TO_... 显式转换，不得在本件内隐式判断）；
                nN 为 USINT 类型天然非负，负移位量结构性不可能；
                钳位方向：移位量超宽按「结果置 0」处理。
// 段 1｜输出与错误状态预置 / segment 1, preset output and error status
// 段 2｜移位量闸门（超宽走常量路径，不调内建） / segment 2, shift amount gate (oversized takes the constant path, built-in not called)
// 段 3｜域内委托移位（末段） / segment 3, in-domain delegated shift (final)
    uIn : LWORD; // 被移位位串（无符号位串，无符号位扩展语义） [位] / bit string to be shifted, unsigned, no sign extension [bit]
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_0208 移位量 ≥ 64（位宽），结果已置全零——信息级，正常防御
                16#0001_0209 预留禁用（信息级，不得挪用）
                16#0001_02FA 预留禁用（故障级，不得挪用）
                16#0001_02FB 预留禁用（故障级，不得挪用）
                16#0001_02FC 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_ShrLwordEx : LWORD
VAR_INPUT
    uIn : LWORD; // 被移位位串（无符号位串，无符号位扩展语义） [位] / bit string to be shifted, unsigned, no sign extension [bit]
    nN  : USINT; // 移位量 [bit]，USINT 天然非负，范围 0~255 / shift amount [bit], USINT is non-negative by type, range 0..255
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_LW_WIDTH : USINT := 64;                        // LWORD 位宽常量 [bit] / LWORD width constant [bit]
    DL_LW_ZERO  : LWORD := 16#0000_0000_0000_0000;     // 超宽移位结果零值 [位串] / zero result of an oversized shift [bit string]
END_VAR
```

---

#### 4.4.3 `FC_DL_RolLwordEx` —— LWORD 循环左移（MOD 64 归一）

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_Base / BitString |
| 前缀 / 返回类型 | `FC_DL_` / `LWORD` |
| 复杂度 / 批次 | 低 / 批 4 |
| function_tags | `iec-std-wrapper`, `lword-bitstring` |
| 委托内建 | `ROL(uIn, nShift)`（归一后移位量） |
| 码位 | 信息 `16#0001_020A`（移位量 ≥64 已按 MOD 64 归一）/ `16#0001_020B`（预留）；故障 `16#0001_02FD`/`02FE`/`02FF`（三槽全预留） |

**语义**：循环左移与左移的**语义差异必须写清**：循环移位量按位宽取模仍等价，故 `nN ≥ 64` **归一而非置零**（与 4.4.1 相反，这是 R14 `FC_DL_RolEx` 的既有口径，必须逐字延续）。

**防御点**：
1. `nN >= 64` → `nShift := nN MOD DL_LW_WIDTH`（除子为常量 64，恒非零）+ 信息 `020A`；
2. 归一后 `nShift = 0` 时直接输出 `uIn`（避免调用 `ROL(x, 0)` 的平台差异）；
3. 无故障级路径。

**(a) 注释样板原文**

```iecst
    功能说明  : LWORD 位串循环左移防御包装：移位量 nN 大于等于 64（位宽）时按 MOD 64 归一，
                并置信息级 16#0001_020A（循环移位对位宽取模仍等价，故归一而非置零——
                与左移/右移件的「超宽置零」口径刻意相反，二者语义不可混用）；
                归一后移位量为 0 时直接输出原值，不调用内建 ROL（规避零移位量的平台差异）；
                域内委托平台内建 ROL，不重实现移位内核；
                MOD 除子为常量 64（编译期恒非零），结构性满足除法前判除子非零红线；
                钳位方向：移位量按位宽取模归一（0~63），结果位宽严格保持 64 位。
// 段 1｜输出与错误状态预置 / segment 1, preset output and error status
// 段 2｜移位量归一（MOD 位宽） / segment 2, shift amount normalization (modulo width)
// 段 3｜零移位量与域内委托循环移位（末段） / segment 3, zero-shift pass-through and in-domain delegated rotate (final)
    nN : USINT; // 循环移位量 [bit]，USINT 天然非负，范围 0~255 / rotate amount [bit], USINT is non-negative by type, range 0..255
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_020A 移位量 ≥ 64（位宽），已按 MOD 64 归一——信息级，正常防御
                16#0001_020B 预留禁用（信息级，不得挪用）
                16#0001_02FD 预留禁用（故障级，不得挪用）
                16#0001_02FE 预留禁用（故障级，不得挪用）
                16#0001_02FF 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_RolLwordEx : LWORD
VAR_INPUT
    uIn : LWORD; // 被循环移位位串 [位] / bit string to be rotated [bit]
    nN  : USINT; // 循环移位量 [bit]，USINT 天然非负，范围 0~255 / rotate amount [bit], USINT is non-negative by type, range 0..255
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_LW_WIDTH : USINT := 64; // LWORD 位宽常量，兼作 MOD 除子（编译期恒非零） [bit] / LWORD width constant, also the MOD divisor, never zero [bit]
END_VAR
VAR
    nShift : USINT; // 归一后的实际移位量 0~63 [bit] / normalized shift amount 0..63 [bit]
END_VAR
```

---

#### 4.4.4 `FC_DL_RorLwordEx` —— LWORD 循环右移（MOD 64 归一）

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_Base / BitString |
| 前缀 / 返回类型 | `FC_DL_` / `LWORD` |
| 复杂度 / 批次 | 低 / 批 4 |
| function_tags | `iec-std-wrapper`, `lword-bitstring` |
| 委托内建 | `ROR(uIn, nShift)` |
| 码位 | 信息 `16#0001_020C`（移位量 ≥64 已按 MOD 64 归一）/ `16#0001_020D`（预留）；故障 `16#0001_0300`/`0301`/`0302`（三槽全预留） |

**语义 / 防御点**：与 4.4.3 镜像；`nN >= 64` → `MOD 64` + 信息 `020C`；归一为 0 时直通原值。

**(a) 注释样板原文**

```iecst
    功能说明  : LWORD 位串循环右移防御包装：移位量 nN 大于等于 64（位宽）时按 MOD 64 归一，
                并置信息级 16#0001_020C（与循环左移件同口径，与左移/右移件的「超宽置零」刻意相反）；
                归一后移位量为 0 时直接输出原值，不调用内建 ROR；
                域内委托平台内建 ROR，不重实现移位内核；
                MOD 除子为常量 64（编译期恒非零），结构性满足除法前判除子非零红线；
                钳位方向：移位量按位宽取模归一（0~63），结果位宽严格保持 64 位。
// 段 1｜输出与错误状态预置 / segment 1, preset output and error status
// 段 2｜移位量归一（MOD 位宽） / segment 2, shift amount normalization (modulo width)
// 段 3｜零移位量与域内委托循环移位（末段） / segment 3, zero-shift pass-through and in-domain delegated rotate (final)
    uIn : LWORD; // 被循环移位位串 [位] / bit string to be rotated [bit]
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_020C 移位量 ≥ 64（位宽），已按 MOD 64 归一——信息级，正常防御
                16#0001_020D 预留禁用（信息级，不得挪用）
                16#0001_0300 预留禁用（故障级，不得挪用）
                16#0001_0301 预留禁用（故障级，不得挪用）
                16#0001_0302 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_RorLwordEx : LWORD
VAR_INPUT
    uIn : LWORD; // 被循环移位位串 [位] / bit string to be rotated [bit]
    nN  : USINT; // 循环移位量 [bit]，USINT 天然非负，范围 0~255 / rotate amount [bit], USINT is non-negative by type, range 0..255
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_LW_WIDTH : USINT := 64; // LWORD 位宽常量，兼作 MOD 除子（编译期恒非零） [bit] / LWORD width constant, also the MOD divisor, never zero [bit]
END_VAR
VAR
    nShift : USINT; // 归一后的实际移位量 0~63 [bit] / normalized shift amount 0..63 [bit]
END_VAR
```

---

#### 4.4.5 `FC_DL_LwordToLrealChk` —— LWORD → LREAL 精度告警

| 项 | 值 |
|---|---|
| 分类 / 子库 | DL_MathData / Convert |
| 前缀 / 返回类型 | `FC_DL_` / `LREAL` |
| 复杂度 / 批次 | 低 / 批 4 |
| function_tags | `iec-std-wrapper`, `lword-bitstring`, `precision-chk` |
| 委托内建 | `LWORD_TO_LREAL()` |
| 码位 | 信息 `16#0001_020E`（超 2^53 精度告警）/ `16#0001_020F`（预留）；故障 `16#0001_0303`/`0304`/`0305`（三槽全预留） |

**语义**：`FC_DL_LintToLrealChk`（R16）的**无符号镜像件**：LWORD 全域 `0 ~ 1.8446744E19` 远超 2^53（`9.007199254740992E15`），超域**值照转** + 信息级告警。64 位寄存器拼装的累计量（双字计费表、64 位时间戳）转 LREAL 是典型的静默丢精度场景。

**防御点**：
1. `nIn > DL_LW_F53_MAX` → 值照转 + 信息 `020E`，`bValid=TRUE`；
2. **无负值分支**（无符号类型系统保证），故**不需要** R16 `LintToLrealChk` 的双侧比较（该件的双侧比较正是为了规避 `ABS(LINT 最小值)` 回绕）；
3. 头注释写明与 `FC_DL_LintToLrealChk` 的职责边界（无符号 vs 有符号源）。

**(a) 注释样板原文**

```iecst
    功能说明  : 将 LWORD 防御性转换为 LREAL 并作为返回值输出，转换委托平台内建 LWORD_TO_LREAL；
                nIn 超过 2^53（9007199254740992，双精度浮点尾数 53 位精度极限）时，
                值照常转换输出，仅置信息级 16#0001_020E 提示低位精度损失（bError=FALSE、bValid=TRUE）；
                与 FC_DL_LintToLrealChk 的职责边界：本件源类型为无符号 64 位位串，
                LWORD 无负值分支（类型系统保证），故不需要该件的双侧比较式；
                钳位方向：无钳位（信息级仅记录，转换结果为最接近的可表值）。
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
// 段 2｜53 位精度极限判定与主体转换（末段） / segment 2, 53-bit precision limit check and main conversion (final)
    nIn : LWORD; // 待转换 64 位无符号位串 [位] / 64-bit unsigned bit string to convert [bit]
```

**(b) 错误码样板原文**

```iecst
    错误码    : 16#0001_020E nIn 超 2^53 精度极限，转换值低位可能失真——信息级，正常防御
                16#0001_020F 预留禁用（信息级，不得挪用）
                16#0001_0303 预留禁用（故障级，不得挪用）
                16#0001_0304 预留禁用（故障级，不得挪用）
                16#0001_0305 预留禁用（故障级，不得挪用）
```

**(c) 变量声明区样板原文**

```iecst
FUNCTION FC_DL_LwordToLrealChk : LREAL
VAR_INPUT
    nIn : LWORD; // 待转换 64 位无符号位串，建议域 0 ~ 16#FFFF_FFFF_FFFF_FFFF [位] / 64-bit unsigned bit string to convert, suggested domain 0 .. 16#FFFF_FFFF_FFFF_FFFF [bit]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_LW_F53_MAX : LWORD := 9007199254740992; // 双精度浮点尾数 53 位精度极限 2^53 [无量纲] / double-precision 53-bit mantissa precision limit 2^53 [dimensionless]
    DL_LREAL_ZERO : LREAL := 0.0;              // 返回值预置零（本件无故障路径，仅作预置约定） [无量纲] / preset zero, no fault path in this component [dimensionless]
END_VAR
```

---

## 5 编码者交付前自检清单（16 项机检 + 3 点惯例 grep，任一项不过禁止提交）

**A. 机检 16 项（对 20 件增量逐件执行）**

1. 文件名 = POU 名，前缀 `FC_DL_`，PascalCase，落盘目录与 §2 分类一致；
2. 文件头 10 项齐全（组件名称 / 分类 / 前缀 / 版本 / 溯源 / 平台 / 作者 / 功能说明 / 错误码 / 状态机 / 修订记录），`溯源` 首行必为「IEC 61131-3 标准语义的道莅防御性实现」；
3. 头注释 `错误码` 段**恰好 5 行**，码值与 §2 码位速查表**逐字一致**（含「预留禁用」字样）；
4. 每个 `VAR_INPUT` / `VAR_OUTPUT` / `VAR` / `VAR CONSTANT` 声明行均有同行双语注释，且含 `[单位]`；
5. `VAR_OUTPUT` 顺序固定 `eErr → bError → bValid`，`eErr : UDINT`；
6. 零全局耦合与零硬编码地址：三点独立 grep —— 全局变量容器引用 / 外部变量声明关键字 / 物理 IO 绝对地址记法（`%` + 区号），**三项必须 NONE 命中**；
7. 无厂商专有库对象（`Sys*` / `Tc*` / `SM*` / `__SYSTEM` 等）NONE 命中；
8. 无指针类型与引用类型声明（两类关键字 NONE 命中，改用 `VAR_IN_OUT` 或接口注入——本轮 20 件均为纯函数，两者都不需要）；
9. 无隐式类型转换：`INT_TO_REAL` / `REAL_TO_LREAL` / `LWORD_TO_LREAL` 等一律显式书写；
10. 每个除法/模除，除子均为编译期常量或在除法前显式判非零（本批 20 件全部为常量除子，逐件在头注释声明）；
11. 浮点判等一律容差式（`ABS(a-b) < eps`），NONE 出现 `fA = fB`；
12. 有符号极值比较一律双侧式，`ABS(` 在 13/14/15 三件中 NONE 出现（R55）；
13. 整数下限一律 `-DL_XXX_MAX - 1` 计算式，字面量 `-2147483648` / `-9223372036854775808` NONE 出现；
14. 移位量闸门：16/17 两件 `nN >= 64` 必须走常量路径（**函数体内 `SHL`/`SHR` 调用点必须在闸门之后**）；18/19 两件必须 `MOD 64`；
15. 每件文件末有 `END_FUNCTION` 终结符（R3 教训）；
16. 每件段注释编号连续、末段标 `final`，段数与 §4 骨架一致。

**B. 惯例一致性 3 点 grep（R15 升格的第 17 项终审检查，机检 16 项对此全盲）**

- `grep -c "// .* / .*"`：双语同行格式，20 件全部 ≥ 声明行数；`(* 中文 EN:` 写法 NONE 命中；
- `grep "eErr   : UDINT"`：20 件全命中，`uErrorId : UINT` / `uDiag` NONE 命中；
- `grep -o "16#[0-9A-F]\{4\}_[0-9A-F]\{4\}"`：20 件全部落在 `16#0001_01E8`~`16#0001_0305` 区间，与 §2 表逐件对齐。

**C. 编译可移植性门槛**

- 20 件在 CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop **各编译一次**（批 2 第 5 件 `FC_DL_TodToDintMs` 因依赖 `TOD_TO_TIME` 链为**强制门槛件**，其余为常规门槛）；
- 编译告警（非错误）须全部留痕到 `RAW_NOTES_R17.md`。

---

## 6 本轮明确不做（禁区，防下轮误判为遗漏）

| 不做项 | 理由 | 去向 |
|---|---|---|
| DT / DTL / DATE 日历族（分解、差值、加减） | 核心依赖平台 `DT_TO_DTL` 可用性，须先过三平台编译验证；未验证即立项 = 把可移植性红线押在未证实前提上 | ROADMAP P1（标注「需三平台编译验证门槛」） |
| `FC_DL_RatioToPwrDb`（功率型反向件） | 与 `FC_DL_RatioToAmpDb` 仅常数因子差异，验收向量重叠 > 90% | ROADMAP P1 |
| `FC_DL_DintMsToTod`（当日毫秒 → TOD） | 需 TOD 日历域钳位，与日历族同批验收更省事 | ROADMAP P1 |
| `FC_DL_Log2Ex` | `FC_DL_LogBaseEx(fBase := 2.0)` 完全覆盖 | 不立 |
| `FC_DL_UdintToLrealChk` | UDINT 全域 ≤ 2^32 < 2^53，转 LREAL 恒无损，无告警语义 | 不立（已在 4.3.2 头注释留痕） |
| `Sel/Mux/Limit` 整型域变体 | 整型无 NaN/±INF 语义，变体仅换类型，工程增量近零 | 不立 |
| 任何 FB（带状态） | 本轮 20 件全部为纯函数，保证批间零依赖、可并行验收 | 本轮不做 |
| 任何与物理 IO / 全局数据关联的组件 | 违反零全局耦合与零硬编码地址红线 | 永不做 |

---

## 7 交付与回写约定（由后续收口执行，本轮不动作）

1. 20 件落盘后依次：16 规则机检 → R58 源码反算 `code_segment` → registry v2.5.0 → v2.6.0（264 → 284）→ JSONL +20（sha256 校验）→ 子库 `VERSION.md` / `MANUAL_DL_Base.md` / `MANUAL_DL_MathData.md` → 顶层 `CHANGELOG.md` / `README.md` / `LIBRARY_MANUAL.md` → `SOURCE_HUNTING_MATRIX.md` §5 三行回写（T0-4 / T0-5 / T0-7 变体线）+ §4 配额实测 R17 行 → `AGENT_EVOLUTION_LOG.md` Round 17 节。
2. 本轮**不修改** `INDEX_REGISTRY.json` / JSONL / `ROADMAP.md` / `SOURCE_HUNTING_MATRIX.md`（按指令，回写由收口完成）。
3. 码位交接：信息级 R18 起点 `16#0001_0210`，故障级 R18 起点 `16#0001_0306`。

---

*R17 ｜ 2026-11-16 ｜ 道莅工控代码库产品总监（阶段一+二：只规划不编码；WebSearch 0 次；T1/T2 未动用）*
