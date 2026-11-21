# ROUND PLAN R21 —— 阶段一盘点 + 阶段二狩猎派单（20 件 / 4 批）

> 轮次：**R21** ｜ 生成时间：2026-11-16 20:38 ｜ 编制：道莅工控代码库产品总监（daoli-library-director）
> 性质：**T0 变体线为主 + T2-1 LGF 待挖子族补位**——15 件 `DL_MathData` + 5 件 `DL_Base`，其中批 2 五件挂 **T2-1 LGF（Bit Logic / Data Handling / CRC）**，满足「≥1 个 T2 组件族」配额；**WebSearch 2 次**（LGF 闭源文档分类核对），其余 18 件零检索
> 本文性质：**派单规格书**（编码专家可直接照抄，禁止再向规格要信息）；`.st` 落盘、registry 回填、JSONL 同步、VERSION/MANUAL 台账由批次 1-4 与收口阶段执行
> **本轮阶段一/二不改任何 `.st` / `INDEX_REGISTRY.json` / JSONL**（按派单纪律：规格先行，代码后置）

---

## 0 盘点区（Step 1 · 状态读取 · 全部当场实测，不沿用口头交接）

### 0.1 总库状态（`INDEX_REGISTRY.json` 实解析 + `DL_*/*.st` glob 实测）

| 项 | 实测值 |
|---|---|
| `version` | **2.9.0** |
| `total_components` | **344** |
| `last_updated` | `2026-11-16T18:20:00+08:00` |
| 物理 `.st` 文件数 | **344**（与 registry 自洽 ✔） |
| 子库分布（`counts` 实读） | `DL_Base` **66** ｜ `DL_MathData` **130** ｜ `DL_Algo` **36** ｜ `DL_Device` **57** ｜ `DL_Motion` **25** ｜ `DL_Process` **30** |
| 总库完成度 | **344 / 10 000 = 3.44 %** |
| 今日累计（按 `registered_at` 日期聚合实测） | **158 / 200 = 79 %**（11-14 26 件 / 11-15 160 件 / 11-16 158 件） |
| 距今日 200 目标 | **42 件** |
| 距 500 里程碑 | **156 件**（344 → 500） |
| 语料 | JSONL 344 条（本轮不动） |

> **口径纠偏留痕**：交接背景记「今日 140/200」，实测 `registered_at = 2026-11-16` 为 **158** 条（R16~R20 五轮累计）。以实测为准，本表不采用口头值（R61 教训延伸：连计数也要实测）。

### 0.2 源矩阵覆盖率（`SOURCE_HUNTING_MATRIX.md` 逐行解析）

| 维度 | 实测 |
|---|---|
| T0 快车道行（T0-1 ~ T0-8） | **8 / 8 ✔ 全收口**（T0-8 为 R20 新开并当轮收口） |
| 一级源行（T1-1~9 / T2-1~9 / NAMUR NE43 / 半导体 ESC 自研） | **19 行，全部 ◐ 已开组，☐ = 0** |
| T2-1 LGF 子族行 | **13 行全部 ◐**，无 ✔ 收口行（LGF 是按「子族」而非「整组」收口的） |
| 仍显式标注「待挖」的子族 | Bit Logic（LWORD 单字版 / 多段一次搬）、Data Handling（CRC-16 反射 / LWORD 累加和）、Math（SearchMinMax DInt/UDInt 重载）、Counter（INT/UDINT 变体）、Converter（DTL 族）、Signal Generators（频率发生）、Measurement（统计/峰值残余）、T1-3（RTU 帧长一致性）、T1-7（PROFINET 诊断） |
| 结论 | 覆盖率已从「是否有源可挖」转为「子族是否挖尽」——**无 ☐ 可开，只能做◐ 深化**；R21 只深化 T2-1 两条子族，不新开任何源 |

### 0.3 ⚠ 码位游标当场实测（R61 铁律：禁信交接数字）

以全库 344 个 `.st` 为唯一事实源，正则 `16#([0-9A-Fa-f]{4})_([0-9A-Fa-f]{4})` 全量扫描并去重（含头注释中的错误码表行）：

| 段（子系统） | 使用者（实测） | 信息级子带实测 | 故障级子带实测 | 游标（下一空闲） |
|---|---|---|---|---|
| `16#0001_` | **DL_Base + DL_MathData 共用** | `01xx`~`02xx` **满带**（max `02FF`）；`04xx` 已用 `0400`~`0433` | `03xx` 已用 `0300`~`036B` | 信息 **`0434`** ／ 故障 **`036C`** |
| `16#0002_` | DL_Algo | CC 网格已用 `01`~`2A` + 遗留公共码 `00xx` | — | 下一 CC = **`2B`** |
| `16#0003_` | DL_Device | `01xx` max `0171` | `03xx` max `033B` | 信息 **`0172`** ／ 故障 **`033C`** |
| `16#0004_` | DL_Motion | `01xx` max `01D4` | `02xx` max `02E9` | 信息 **`01D5`** ／ 故障 **`02EA`** |
| `16#0005_` | DL_Process | `01xx` max `01D9` | `03xx` max `030A` | 信息 **`01DA`** ／ 故障 **`030B`** |

> 与交接值逐项核对：`0001` 信息 `0434`/故障 `036C` ✔ 一致；`0002` CC=`2B` ✔；`0003` `0172`/`033C` ✔；`0004` `01D5`/`02EA` ✔；`0005` `01DA`/`030B` ✔。**五项全部实测复核通过，交接可信。**
> **注意 `16#0001_` 为 `DL_Base` 与 `DL_MathData` 共用命名空间**——派单时两库槽位必须**统一顺延分配**，不得各自从 `0434` 起算（这是 R17 交叉撞车的根因形态）。

### 0.4 本轮候选名查重实测

20 个候选 POU 名对全库 `DL_*` 目录 grep **零命中**（`EXIT=1`）；语义层面逐件做了「与存量件职责边界」比对，剔除 3 个看似有价值实为重载的候选：

| 被剔除候选 | 剔除理由（防凑数） |
|---|---|
| `FC_DL_ClampLreal` | 与存量 `FC_DL_LimitEx`（R16，三输入限幅 + 倒置自动交换 + 非有限拦截）**语义 100% 重合**；红线手册里写的 `FC_DL_Clamp` 是通称，实际落地件就是 `LimitEx` |
| `FC_DL_ParityEven` | 由存量 `FC_DL_BitCount`（返回 0~32）做 `MOD 2` 即可，独立成件属薄包装（LGF 有 `IsParityEven/Odd` 也不构成立项理由） |
| `FC_DL_SearchMinMaxDint` | 与 `FC_DL_SearchMinMax` 仅差数据类型，属「无工程意义的重载变体」；保留在 ROADMAP 观察池，不占配额 |

---

## 1 R21 20 目标一览（锁定，宁少勿滥）

| # | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批 |
|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_ModPos` | DL_MathData | FC_DL_ | 恒正取模原子（负数取余三平台歧义唯一出口） | T0-4 变体线（库内纪律原子化） | M | 1 |
| 2 | `FC_DL_DivLrealSafe` | DL_MathData | FC_DL_ | 浮点防御除法原子（微量分母闸 + 非有限输入闸 + 溢出饱和） | T0-4 变体线（红线「强制防除零」原子化） | M | 1 |
| 3 | `FC_DL_QuantizeStep` | DL_MathData | FC_DL_ | 按步距量化（给定值对齐 n×step，半步策略显式） | T0-4 变体线（取整族缺「非整数步距」轴） | M | 1 |
| 4 | `FC_DL_PolyEvalHorner` | DL_MathData | FC_DL_ | Horner 多项式求值（PT100/热电偶线性化通用内核） | T0-4 变体线（插值族缺「多项式」轴） | M | 1 |
| 5 | `FC_DL_WrapAngleDeg` | DL_MathData | FC_DL_ | 角度归一（(−180,180] 或 [0,360)，禁 MOD 走条件加减） | T0-4 变体线（凸轮/机器人相位归一原子） | M | 1 |
| 6 | `FC_DL_LwordBitFieldExtract` | DL_MathData | FC_DL_ | LWORD 单字位段读（宽 1~64，宽 64 走常量掩码） | T2-1 LGF Bit Logic（LWORD 单字版待挖） | M | 2 |
| 7 | `FC_DL_LwordBitFieldInsert` | DL_MathData | FC_DL_ | LWORD 单字位段读改写（先算掩码再读旧值，越界拒写） | T2-1 LGF Bit Logic（合并/拆分 LWORD 缺口） | M | 2 |
| 8 | `FC_DL_LwordBitCount` | DL_MathData | FC_DL_ | LWORD 汉明重 0~64（存量 `BitCount` 只覆盖 DWORD） | T2-1 LGF 计数与边沿（BitCount 64 位缺位） | L | 2 |
| 9 | `FC_DL_Crc16Generic` | DL_MathData | FC_DL_ | 参数化 CRC-16（poly/init/xorout/双向反射，任意从站协议） | T2-1 LGF CRC（`CalcCRC16Advanced` 参数域） | H | 2 |
| 10 | `FC_DL_ChecksumSum8` | DL_MathData | FC_DL_ | 8 位累加和校验（DL/T 645、水表/电表自定义帧） | T2-1 LGF Data Handling（累加和待挖） | L | 2 |
| 11 | `FC_DL_StringToDint` | DL_MathData | FC_DL_ | 整数字符串解析（符号/溢出/非法字符定位三闸） | T0-5/T0-6（`StringToLReal` 的整数族缺位） | M | 3 |
| 12 | `FC_DL_DwordToHexString` | DL_MathData | FC_DL_ | DWORD → 8 位十六进制文本（`HexStringToBytes` 逆向） | T0-6 字符串化（十六进制序列化缺位） | L | 3 |
| 13 | `FC_DL_ArraySumLreal` | DL_MathData | FC_DL_ | 静态数组求和/均值纯函数（NaN 剔除 + 有效计数出口） | T0-4 变体线（统计族缺「静态表一次性求值」） | L | 3 |
| 14 | `FC_DL_TimeToHmsString` | DL_MathData | FC_DL_ | TIME → `HH:MM:SS.mmm`（负 TIME 统一带负号） | T2-1 LGF Converter（`TimeToString` 行为定义） | M | 3 |
| 15 | `FC_DL_DateToIsoString` | DL_MathData | FC_DL_ | DATE → `YYYY-MM-DD`（MES 台账/文件名标准形态） | T2-1 LGF Converter（`DTLtoString` 行为定义片段） | M | 3 |
| 16 | `FB_DL_MinOnOffGuard` | DL_Base | FB_DL_ | 最短运行/最短停止双守卫（防压缩机/泵频繁启停） | T0-2 变体线（ROADMAP 多处要「防频繁启停」无原子件） | M | 4 |
| 17 | `FB_DL_SignalChangeCounter` | DL_Base | FB_DL_ | 带死区与最小间隔的变化次数统计（阀动作次数/寿命台账） | T0-1 变体线（LGF `CountBooleanEdges` 语义的模拟量版） | M | 4 |
| 18 | `FB_DL_SamplingTrigger` | DL_Base | FB_DL_ | 均匀采样节拍（真实时基对齐 + 漂移告警 + 样本序号） | T0-2 变体线（趋势记录缺无漂移节拍源） | M | 4 |
| 19 | `FB_DL_SignalFrozenDetect` | DL_Base | FB_DL_ | 信号冻结检测（窗内极差 < 死区即判传感器卡死） | T2-8 NE107 语义（eCheckFunction 判据原子） | M | 4 |
| 20 | `FB_DL_PulseWidthFilter` | DL_Base | FB_DL_ | 窄脉冲抑制（脉宽 < tMinWidth 整段吞掉，宽度不失真） | T0-1 变体线（`SignalDebounce` 只延迟不抑制） | M | 4 |

**分布**：`DL_MathData` **15**（#1~#15）｜ `DL_Base` **5**（#16~#20）＝ **20**
**类型**：FC **15** ｜ FB **5** ｜ **复杂度**：H **1** ｜ M **15** ｜ L **4**
**来源配额**：T2（LGF 待挖子族）**6 件**（#6~#10 + #14 + #15，其中 #14/#15 为行为定义借用）｜ T1 **0 件**（纯 T0 轮允许减配 0~1，本轮取 T2 侧 6 件，超额达标）

### 1.1 为什么这 20 件不是「凑数变体」（逐族辩护）

1. **#1/#2 是红线自己点名、库里却没有的原子**：`coding-standard.md` 第六节写「除法前置防零 / 输入限幅统一走 `FC_DL_Clamp`」，但全库 344 件中没有任何取模/除法/限幅原子（`LimitEx` 是限幅落点，取模与除法则 344 件里每件各写一遍）。原子化之后「一处修正、全库受益」，这是**减债**而非增件。
2. **#3/#4/#5 是三条不同的数学轴**：现有取整族（`RoundSat`/`TruncEx`/`FloorEx`/`CeilEx`）只解「到整数」，未解「到非整数步距」（编码器分辨率、给定值量化）；插值族只有分段线性（`MultiPointLinear`/`InterpolateTable2D`），未解「单一多项式」（PT100 Callendar-Van Dusen、热电偶 NIST 多项式）；角度归一是运动层反复手写「条件加减避 MOD」的第 4 次复现（R48/R11/R19 三处留痕）。
3. **#6~#8 是 LGF 子族的真实缺位**：LGF 位操作 5 件 + 合并拆分 12 件覆盖 BYTE/WORD/DWORD，**唯独 LWORD** 我们只做了移位族（R17）与批量数组族（R12/R13），单字 LWORD 位段读/写与 64 位汉明重仍是空位（`FC_DL_BitCount` 入参实测为 `DWORD`）。
4. **#9 是「固定参数 CRC 无法接任意从站」的工程死结**：`Crc16Modbus`/`Crc16Ccitt` 参数写死，遇到非标从站（自定义 poly/反射）只能现场手改源码。LGF `CalcCRC16Advanced` 的参数域（initValue/mask/finalXorValue/reflectInput/reflectResult）证明这是行业通行解法，本件**只借参数域**、逐位算法自研、零查表零内存。
5. **#10 是「校验族最后一块」**：CRC8/16/32 + LRC 已有，累加和（DL/T 645、水表帧）仍缺；这是**协议兼容性**缺口，不是审美缺口。
6. **#11~#15 是序列化闭环**：`StringToLReal` 已落（R13），整数解析缺位导致「配方号/站号/批次号」只能靠平台隐式转换（无越界、无字符定位）；`DwordToHexString` 与 `HexStringToBytes` 构成双向对；`TimeToHmsString`/`DateToIsoString` 填「数值能转文本、时间日期不能」的半截子现状（LGF 有 `IntToString`/`TimeToString`/`DTLtoString` 三件，我们一件都没有）。
7. **#16~#20 是 Base 层的五条真空白**：全库无「最短运行/停止」守卫（而 ROADMAP 至少 4 条待办写「防频繁启停」）；无「模拟量变化次数」审计（阀寿命台账是 OEM 刚需，`CtuEx` 只能数 BOOL 沿）；无无漂移采样节拍（`PulseGenerator` 是占空比方波，不带真实时基与序号）；无信号冻结检测（NE107 `eCheckFunction` 缺判据原子）；`SignalDebounce` 只延迟跳变、对「短路冲」无能为力（宽 1 拍的毛刺经过去抖照样进逻辑）。

---

## 2 四批划分（每批 5 件，同子库同类内聚）

| 批 | 主题 | 件 | 信息级 2 槽/件 | 故障级 3 槽/件 |
|---|---|---|---|---|
| 批 1 | **数学安全原子族**（取模/除法/量化/多项式/角度） | #1-5 | `0434`~`043D` | `036C`~`037A` |
| 批 2 | **LWORD 位域 + 校验族**（T2-1 LGF 待挖子族收口） | #6-10 | `043E`~`0447` | `037B`~`0389` |
| 批 3 | **文本序列化 + 静态表统计** | #11-15 | `0448`~`0451` | `038A`~`0398` |
| 批 4 | **Base 时序/信号守卫五件** | #16-20 | `0452`~`045B` | `0399`~`03A7` |

**槽位账目**：信息级 `0434`~`045B` 共 **40 槽**（20 件 × 2）；故障级 `036C`~`03A7` 共 **60 槽**（20 件 × 3）＝ **100 槽**。
**实测校验**：上述 100 个码位对全库 344 个 `.st` 做占用比对 → **`collisions: []`**，零冲突（`16#0001_` 故障带 `03xx` 现用至 `036B`，`04xx` 信息带现用至 `0433`，中间空洞正是本轮分配区）。
**R21 收尾游标**（供 R22 直接引用，仍需 R22 当场复测）：信息 **`045C`** ／ 故障 **`03A8`**。

**全局强制（逐件不再重复）**：
- 浮点判等一律 `ABS(a-b) < DL_FLOAT_EPS`；除法前置防零；禁裸数值（一律 `VAR CONSTANT` 或引脚）。
- `TON`/`TOF`/`R_TRIG` **实例在主体最前部无条件刷新**（每件含定时/边沿的 FB 必查）。
- 禁 `WHILE` 长循环；确需循环者带 `nGuard` 防死锁计数器 + 超限置故障。
- 预留槽在头注释错误码表内写 `预留禁用（不得挪用）`，**实现体不得出现该码赋值**。
- 每件头注释必须含七项（名称/子库/版本/兼容性/功能/溯源/修订）+ R1~R8 自检行。
- 每件必须给**遗留假设段**：凡委托平台内建（`DATE_TO_DINT` 等）或依赖扫描周期口径，必须在头注释显式声明「未实测，编译门槛未闭合」。

---

## 3 编码派单规格（引脚级，可直接编码）

> 通用接口三件套：`FUNCTION` 返回主值 + `VAR_OUTPUT eErr : UDINT`（0=正常）+ `bError : BOOL`（故障级 TRUE）+ `bValid : BOOL`（返回值可用）。错误码**一律** `16#0001_XXXX`。

### 3.1 批 1（数学安全原子族）

#### #1 `FC_DL_ModPos` —— 恒正取模原子
- **分类**：DL_MathData / Arithmetic ｜ **前缀**：`FC_DL_` ｜ **类型**：FUNCTION → `DINT` ｜ **复杂度**：M
- **引脚**：IN `nValue : DINT`（被除数，全域）；`nModulus : DINT`（模数，≠0）；OUT `eErr/bError/bValid`。
- **VAR CONSTANT**：`DL_DINT_MIN_ABS : DINT := -2147483647`（`−MAX−1` 不可取绝对值的下界哨兵）；`DL_DINT_MIN : DINT := -2147483648`
- **功能规格**：返回恒非负余数 `r ∈ [0, |m|−1]`。实现**只允许一次 `MOD`**：`r := nValue MOD mAbs; IF r < 0 THEN r := r + mAbs; END_IF`（条件加法归一，禁二次取模、禁 `ABS` 后再 `MOD` 的双重路径）。
- **边界安全条件**：① `nModulus = 0` → 故障 `036C`，返回 0、`bValid := FALSE`；② `nModulus = DL_DINT_MIN`（取绝对值溢出）→ 故障 `036D`，返回 0、`bValid := FALSE`；③ `nModulus < 0` → 取绝对值后照算 + 信息 `0434`（模数符号不影响数学结果，正常防御）；④ 元数据 `0435` 预留；⑤ 无状态机（R6 N/A 句式）。
- **码位**：信息 `0434`（模数为负已取绝对值）/ `0435` 预留 ｜ 故障 `036C`（模数为零）/ `036D`（模数下界不可表示）/ `036E` 预留
- **来源标签**：T0-4 变体线，零检索。立项依据：R48（移位量归一）、R11（`RolloverCounter` 禁 MOD）、R19（`TodAddWrap` 条件加减）三处「MOD 数值域陷阱」留痕的原子化。

#### #2 `FC_DL_DivLrealSafe` —— 浮点防御除法原子
- **分类**：DL_MathData / Arithmetic ｜ **类型**：FUNCTION → `LREAL` ｜ **复杂度**：M
- **引脚**：IN `fNum : LREAL`；`fDen : LREAL`；`fDenEps : LREAL := DL_DIV_EPS`（微量分母阈值，>0）；OUT `eErr/bError/bValid` + `fRatio : LREAL`（= 返回值的分母敏感比，供调试观察，可选）。
- **VAR CONSTANT**：`DL_DIV_EPS : LREAL := 1.0E-12`；`DL_LREAL_MAX_FINITE : LREAL := 1.7976931348623157E308`
- **功能规格**：域内直接 `fNum / fDen`；`|fDen| < fEps` 一律判故障**不输出伪值**（不返回 0 冒充有效结果，`bValid := FALSE` 强制调用方分支）。溢出判据：`ABS(fRet) > DL_LREAL_MAX_FINITE` 不可靠（比较即溢出），改用 `ABS(fRet) >= DL_LREAL_MAX_FINITE` 前先判 `ABS(fNum) > ABS(fDen) * DL_LREAL_MAX_FINITE`。
- **边界安全条件**：① `fDenEps <= 0` → 故障 `0370`，返回 0；② `ABS(fDen) < fDenEps` → 故障 `036F`，返回 0、`bValid := FALSE`；③ 任一输入非有限（NaN 用 `x <> x`、±INF 用 `ABS(x) > DL_LREAL_MAX_FINITE`）→ 故障 `0371`，返回 0；④ 商超有限域 → 饱和至 `±DL_LREAL_MAX_FINITE` + 信息 `0436`，`bValid := TRUE`（饱和值可观测，与「除零」性质不同）；⑤ 元数据 `0437` 预留。
- **码位**：信息 `0436`（商超有限域已饱和）/ `0437` 预留 ｜ 故障 `036F`（微量分母）/ `0370`（阈值参数非法）/ `0371`（输入非有限）
- **来源标签**：T0-4 变体线，零检索。**红线第六节「除法前置防零」的落地载体**。

#### #3 `FC_DL_QuantizeStep` —— 按步距量化
- **分类**：DL_MathData / Arithmetic ｜ **类型**：FUNCTION → `LREAL` ｜ **复杂度**：M
- **引脚**：IN `fIn : LREAL`（待量化值）；`fStep : LREAL`（步距，>0，如 0.01 mm）；`bRoundHalfUp : BOOL := TRUE`（TRUE=四舍五入，FALSE=向零截断）；OUT `eErr/bError/bValid` + `fResidual : LREAL`（量化残差 = 结果 − 输入，带符号）。
- **VAR CONSTANT**：`DL_QUANT_MAX_RATIO : LREAL := 1.0E15`（商超此值即 LREAL 尾数已无小数精度，量化无意义）；`DL_FLOAT_EPS : LREAL := 1.0E-12`
- **功能规格**：`fQ := fIn / fStep`；`bRoundHalfUp` 时 `fQ := fQ + 0.5`（负值同样成立，因 `TRUNC` 向零）→ `fQ := TRUNC(fQ)`；结果 `fRet := fQ * fStep`。**禁用平台 `ROUND`**（银行家舍入三平台不一致），一律 `TRUNC` + 自补 0.5。
- **边界安全条件**：① `fStep <= DL_FLOAT_EPS` → 故障 `0372`，返回 `fIn` 直通（不静默置 0）；② `fIn` 非有限 → 故障 `0373`，返回 0、`bValid := FALSE`；③ `ABS(fIn / fStep) > DL_QUANT_MAX_RATIO` → 信息 `0438`，**按输入直通**（量化已无精度意义，`bValid := TRUE`）；④ 乘积超有限域 → 故障 `0374`，饱和至 `±DL_LREAL_MAX_FINITE`；⑤ 残差在 `±fStep/2` 之外（含浮点误差）→ 信息 `0439`（只提示，不改结果）；⑥ 无状态机（R6 N/A）。
- **码位**：信息 `0438`（商超精确域已直通）/ `0439`（残差越半步，浮点误差提示） ｜ 故障 `0372`（步距非法）/ `0373`（输入非有限）/ `0374`（结果溢出已饱和）
- **来源标签**：T0-4 变体线，零检索。与 `RoundSat`（到整数）职责边界：**本件到非整数步距**。

#### #4 `FC_DL_PolyEvalHorner` —— Horner 多项式求值
- **分类**：DL_MathData / Math ｜ **类型**：FUNCTION → `LREAL` ｜ **复杂度**：M
- **引脚**：IN `nOrder : INT`（阶数 0~`DL_POLY_MAX_ORDER`）；`fX : LREAL`（自变量，如温度 °C）；INOUT `afCoeff : ARRAY[0..DL_POLY_MAX_ORDER] OF LREAL`（升幂系数 a0..an，`VAR_IN_OUT` 免拷贝）；OUT `eErr/bError/bValid` + `nEffOrder : INT`（实际使用阶数）。
- **VAR CONSTANT**：`DL_POLY_MAX_ORDER : INT := 8`（PT100 CVD 需 4 阶、热电偶 NIST 多项式 ≤ 8 阶）；`DL_FLOAT_EPS : LREAL := 1.0E-12`
- **功能规格**：Horner 递推 `fRet := afCoeff[nOrder]; FOR i := nOrder-1 DOWNTO 0 DO fRet := fRet * fX + afCoeff[i]; END_FOR`（`FOR` 定长，`nOrder ≤ 8`，无需守卫计数器）。前导零系数自动降阶（`nEffOrder` 出实际阶数），避免无意义乘法放大浮点误差。
- **边界安全条件**：① `nOrder < 0 OR nOrder > DL_POLY_MAX_ORDER` → 故障 `0375`，返回 0、`bValid := FALSE`；② `fX` 或任一参与运算的系数非有限 → 故障 `0376`，返回 0；③ 中间量或结果非有限（溢出）→ 故障 `0377`，返回 0；④ 前导零降阶（`nEffOrder < nOrder`）→ 信息 `043A`；⑤ 元数据 `043B` 预留；⑥ 无状态机（R6 N/A）。
- **码位**：信息 `043A`（前导零已降阶）/ `043B` 预留 ｜ 故障 `0375`（阶数越界）/ `0376`（输入或系数非有限）/ `0377`（结果溢出）
- **来源标签**：T0-4 变体线，零检索。用途：PT100 Callendar-Van Dusen、热电偶 NIST 多项式、传感器多点拟合（与 `MultiPointLinear` 分段线性互补）。

#### #5 `FC_DL_WrapAngleDeg` —— 角度归一
- **分类**：DL_MathData / Math ｜ **类型**：FUNCTION → `LREAL` ｜ **复杂度**：M
- **引脚**：IN `fAngleDeg : LREAL`（任意角度 [°]）；`bZeroTo360 : BOOL := FALSE`（FALSE → `(−180, 180]`；TRUE → `[0, 360)`）；OUT `eErr/bError/bValid` + `nTurns : DINT`（圈数，向下取整，供凸轮多圈相位追溯）。
- **VAR CONSTANT**：`DL_DEG_PER_TURN : LREAL := 360.0`；`DL_ANGLE_ABS_MAX : LREAL := 1.0E6`（可归一域上限 [°]，超此值 LREAL 已无 0.001° 分辨率）；`DL_FLOAT_EPS : LREAL := 1.0E-9`；`DL_GUARD_MAX : DINT := 1000`
- **功能规格**：**禁 `MOD`（REAL 上三平台不一致）**。`nTurns := LREAL_TO_DINT(TRUNC(fAngleDeg / 360.0))` 后 `fRet := fAngleDeg - LREAL_TO_DINT_TO_LREAL(nTurns) * 360.0`；若 `fRet > 180.0` 则减 360、`≤ −180.0` 则加 360（**条件加减最多一次**，不写循环）。`bZeroTo360` 再统一搬移。
- **边界安全条件**：① 输入非有限 → 故障 `0378`，返回 0；② `ABS(fAngleDeg) > DL_ANGLE_ABS_MAX` → 故障 `0379`，返回 0、`bValid := FALSE`（**不钳位**：角度钳位会静默改变方向语义）；③ 结果落在容差内（`ABS(fRet) < DL_FLOAT_EPS`）→ 归一为 `+0.0`（消除 `−0.0` 与 `360.0` 抖动）+ 信息 `043D`；④ 输入 `|fAngle| > 360` 已归一 → 信息 `043C`；⑤ 本实现无循环，`DL_GUARD_MAX` 仅作防御性预留常量，头注释须说明**守卫计数器未使用的原因**（禁留未用常量而无解释）；⑥ 无状态机（R6 N/A）。
- **码位**：信息 `043C`（输入超一圈已归一）/ `043D`（结果零容差归一） ｜ 故障 `0378`（输入非有限）/ `0379`（超可归一域）/ `037A` 预留
- **来源标签**：T0-4 变体线，零检索。运动层 `CamPhaseTrim`/`ElectronicCam` 反复手写同一段归一逻辑（R11/R19 留痕），本件为其原子出口。

### 3.2 批 2（LWORD 位域 + 校验族 · T2-1 LGF 待挖子族收口）

#### #6 `FC_DL_LwordBitFieldExtract` —— LWORD 单字位段读
- **分类**：DL_MathData / BitOps ｜ **类型**：FUNCTION → `LWORD` ｜ **复杂度**：M
- **引脚**：IN `uWord : LWORD`（源字）；`nStartBit : INT`（起始位 0~63）；`nWidth : INT`（字段宽 1~64）；OUT `eErr/bError/bValid` + `bTruncated : BOOL`。
- **VAR CONSTANT**：`DL_MASK64_ALL : LWORD := 16#FFFF_FFFF_FFFF_FFFF`；`DL_LWORD_BITS : INT := 64`；`DL_MASK32_ALL : DWORD := 16#FFFF_FFFF`
- **功能规格**：**先算有效宽 `nEffWidth := MIN(nWidth, 64 − nStartBit)`，再移位**。掩码构造：`nEffWidth = 64` 时直接取 `DL_MASK64_ALL`（**规避 `SHL(1,64)` 未定义行为**）；否则 `uMask := SHL(LWORD#1, nEffWidth) − 1`，移位量恒 < 64。取段 `uRet := SHR(uWord AND (SHL(uMask, nStartBit)), nStartBit)`——**移位前必须 `AND` 掩码**（否则高位污染）。
- **边界安全条件**：① `nStartBit < 0 OR nStartBit > 63` → 故障 `037B`，返回 0、`bValid := FALSE`；② `nWidth <= 0` → 故障 `037C`，返回 0；③ `nStartBit + nWidth > 64` → **截断策略**：按 `64 − nStartBit` 取可用位、`bTruncated := TRUE` + 信息 `043E`（读操作可截断，结果可观测；与 #7 写操作的拒写策略成对，见 §5 规则候选 R89）；④ `nWidth > 64` → 故障 `037C`（宽域本身非法，不做截断）；⑤ 元数据 `043F` 预留；⑥ 无状态机（R6 N/A）。
- **码位**：信息 `043E`（宽越界已按可用位截断）/ `043F` 预留 ｜ 故障 `037B`（起始位越界）/ `037C`（字段宽非法）/ `037D` 预留
- **来源标签**：T2-1 LGF Bit Logic 子族（「LWORD 单字版与多段一次搬仍待挖」，见矩阵 R13 备注）；**闭源文档只借「合并/拆分位域」分类事实与 `Bit/Width` 参数域**，算法 clean-room。

#### #7 `FC_DL_LwordBitFieldInsert` —— LWORD 单字位段读改写
- **分类**：DL_MathData / BitOps ｜ **类型**：FUNCTION → `LWORD` ｜ **复杂度**：M
- **引脚**：IN `uBase : LWORD`（原字）；`uField : LWORD`（待写入字段值，只用低 `nWidth` 位）；`nStartBit : INT`（0~63）；`nWidth : INT`（1~64）；OUT `eErr/bError/bValid` + `bChanged : BOOL`（字节值真变）。
- **功能规格**：四步固定序 —— ① 算掩码 `uResetMask := NOT (uFieldMask)`；② 清位 `uTemp := uBase AND uResetMask`；③ 取值 `uVal := uField AND uFieldMask`；④ 合成 `uRet := uTemp OR SHL(uVal, nStartBit)`。**顺序不可交换**：先清后置是「读改写」唯一安全序（R13 `BitArrayInsert` 同源纪律）。
- **边界安全条件**：① `nStartBit` 越界 → 故障 `037E`，**返回 `uBase` 原值**、`bValid := FALSE`；② `nWidth <= 0 OR nWidth > 64` → 故障 `037F`，返回原值；③ `nStartBit + nWidth > 64` → 故障 `0380`，**拒写并返回原值**（写操作有不可逆副作用，「宁可一字不写」）；④ `uField` 超出 `nWidth` 可容纳位（`uField AND NOT uFieldMask <> 0`）→ 高位被丢弃 + 信息 `0440`；⑤ `bChanged` 只在 `uRet <> uBase` 时 TRUE（改动计数供上层做配置写回节流）；⑥ 元数据 `0441` 预留。
- **码位**：信息 `0440`（字段值高位已截断）/ `0441` 预留 ｜ 故障 `037E`（起始位越界，已返回原值）/ `037F`（字段宽非法）/ `0380`（越界拒写）
- **来源标签**：T2-1 LGF Bit Logic 子族；与 #6 构成「读/写」对偶，纪律同 `BitArrayExtract`/`BitArrayInsert`（R12）。

#### #8 `FC_DL_LwordBitCount` —— LWORD 汉明重
- **分类**：DL_MathData / BitOps ｜ **类型**：FUNCTION → `USINT`（0~64） ｜ **复杂度**：L
- **引脚**：IN `uValue : LWORD`；OUT `eErr/bError/bValid`。
- **VAR CONSTANT**：`DL_GUARD_MAX_BITS : DINT := 64`（Kernighan 法最多 64 次迭代）
- **功能规格**：Brian Kernighan 法 `uTemp AND (uTemp − 1)`，迭代次数 = 置位数；`WHILE` 必须带 `nGuard` 计数器，超 `DL_GUARD_MAX_BITS` 即跳出并置故障 `0381`（理论不可达，纯防御）。**不得**改写为 `FOR 0..63` 固定 64 次（与存量 `FC_DL_BitCount` 的算法选择保持同源）。
- **边界安全条件**：① `uValue = 0` → 返回 0 并置信息 `0442`（全零是合法工况，非故障）；② 守卫超限 → 故障 `0381`，返回 0、`bValid := FALSE`；③ 元数据 `0382`/`0383`/`0443` 预留；④ 无状态机（R6 N/A）。
- **码位**：信息 `0442`（全零输入）/ `0443` 预留 ｜ 故障 `0381`（守卫超限）/ `0382` 预留 / `0383` 预留
- **来源标签**：T2-1 LGF 计数与边沿子族（`BitCount` 语义，LGF 侧为 DWORD 口径）；**本件为 64 位域自有实现**，零复制。

#### #9 `FC_DL_Crc16Generic` —— 参数化 CRC-16
- **分类**：DL_MathData / Checksum ｜ **类型**：FUNCTION → `WORD` ｜ **复杂度**：H
- **引脚**：IN `nLen : UINT`（待校验字节数）；`uPoly : WORD`（生成多项式，如 `16#8005`/`16#1021`）；`uInit : WORD`（初值）；`uXorOut : WORD`（结果异或值）；`bReflectIn : BOOL`（输入字节按位反射）；`bReflectOut : BOOL`（结果按位反射）；INOUT `afData : ARRAY[0..DL_CRC_BUF_MAX] OF BYTE`；OUT `eErr/bError/bValid`。
- **VAR CONSTANT**：`DL_CRC_BUF_MAX : UINT := 255`（单帧上限 256 字节，Modbus RTU / 645 均远小于此）；`DL_CRC_BITS : USINT := 16`
- **功能规格**：逐位算法（**零查表、零内存**，可移植性优先）：`uCrc := uInit` → 每字节先按 `bReflectIn` 反射（8 次位循环）→ `uCrc := uCrc XOR SHL(BYTE_TO_WORD(uByte), 8)` → 8 次「`SHL` 判最高位 → 条件异或 poly」→ 终值按 `bReflectOut` 反射 → `XOR uXorOut`。
- **强制实证**：头注释必须列出 3 组公开校验向量并声明编码时实测通过：`"123456789"` → CRC-16/IBM(ARC) `poly=16#8005 init=16#0000 xorout=16#0000 双反射` = `16#BB3D`；CCITT-FALSE `poly=16#1021 init=16#FFFF xorout=0 不反射` = `16#29B1`；XMODEM `init=0 不反射` = `16#31C3`。**任一不符即判定实现错误，禁止入库**（R1 式规格向量错误防线）。
- **边界安全条件**：① `uPoly = 0` → 故障 `0384`，返回 `uInit XOR uXorOut`（多项式退化，CRC 无意义）；② `nLen > DL_CRC_BUF_MAX` → 故障 `0385`，返回 0、`bValid := FALSE`（**不静默钳位**：截断数据算出的 CRC 看似合法却必然校验失败，比报错更危险）；③ `nLen = 0` → 信息 `0445`，返回 `uInit XOR uXorOut`（空帧语义是标准行为，非故障）；④ 反射位循环 8 次定长，**无需守卫**（注释说明原因）；⑤ 元数据 `0444` 预留「反射参数与多项式最高位不匹配的告警」——若 `bReflectOut = TRUE` 且 `uPoly` 第 15 位为 0，置信息 `0444`；⑥ 无状态机（R6 N/A）。
- **码位**：信息 `0445`（空帧，返回初值异或）/ `0444`（反射参数与多项式位宽疑似不匹配） ｜ 故障 `0384`（多项式为零）/ `0385`（帧长超上限）/ `0386` 预留
- **来源标签**：T2-1 LGF CRC 子族（`CalcCRC16Advanced` 参数域：initValue / mask / finalXorValue / reflectInput / reflectResult，见 `RAW_NOTES_R21.md` §2）；**只借参数域与语义，算法自研**。

#### #10 `FC_DL_ChecksumSum8` —— 8 位累加和校验
- **分类**：DL_MathData / Checksum ｜ **类型**：FUNCTION → `BYTE` ｜ **复杂度**：L
- **引脚**：IN `nLen : UINT`；`bTwosComplement : BOOL := FALSE`（TRUE → 输出累加和的二进制补码，DL/T 645 口径）；INOUT `afData : ARRAY[0..DL_SUM_BUF_MAX] OF BYTE`；OUT `eErr/bError/bValid`。
- **VAR CONSTANT**：`DL_SUM_BUF_MAX : UINT := 255`；`DL_BYTE_MOD : DINT := 256`
- **功能规格**：`nSum : DINT := 0;` 逐字节 `nSum := nSum + BYTE_TO_DINT(afData[i]);`（**用 DINT 累加**，防 255×256 在 BYTE 域回绕），末了 `uRet := DINT_TO_BYTE(nSum MOD 256)`（`nSum` 恒非负，`MOD` 安全）；`bTwosComplement` 时取 `256 − uRet`（特例 `uRet = 0` 时补码仍为 0，需显式判）。
- **边界安全条件**：① `nLen > DL_SUM_BUF_MAX` → 故障 `0387`，返回 0、`bValid := FALSE`（同 #9，截断即错）；② `nLen = 0` → 信息 `0447`，返回 0；③ 补码模式下结果为 0 的特例 → 信息 `0446`（提示「校验字节为 0 在部分协议中表示无校验」）；④ 元数据 `0389` 预留；⑤ 无状态机（R6 N/A）。
- **码位**：信息 `0446`（补码结果为 0 的特例）/ `0447`（空帧） ｜ 故障 `0387`（帧长超上限）/ `0388` 预留 / `0389` 预留
- **来源标签**：T2-1 LGF Data Handling 子族（「校验族尚余 LWORD 累加和待挖」，本轮收窄为 8 位累加和 —— 8 位是实际协议形态，LWORD 累加无公开协议用例，属过度设计，理由留档）；算法为公开经典，零复制。

### 3.3 批 3（文本序列化 + 静态表统计）

#### #11 `FC_DL_StringToDint` —— 整数字符串解析
- **分类**：DL_MathData / Convert ｜ **类型**：FUNCTION → `DINT` ｜ **复杂度**：M
- **引脚**：IN `sIn : STRING`（待解析串）；`bAllowSign : BOOL := TRUE`（允许前导 `+`/`-`）；OUT `eErr/bError/bValid` + `nErrPos : INT`（首个非法字符位置，1 基；0 = 无错）。
- **VAR CONSTANT**：`DL_DINT_MAX : DINT := 2147483647`；`DL_DINT_MIN : DINT := -2147483648`；`DL_STR_MAXLEN : INT := 255`
- **功能规格**：**状态机四态**（`eLeadSpace` / `eSign` / `eDigits` / `eDone`）+ `CASE` + `ELSE` 兜底。逐字符取 `MID`（长度先 `LEN` 锁存一次，禁循环内重复 `LEN`，R37 纪律）。累加用 `LINT`（`liAcc := liAcc * 10 + LINT(USINT-48)`），**每步先判界再累加**：正数域 `liAcc > DL_DINT_MAX` 即溢出；负数域 `liAcc > 2147483648` 即溢出。
- **边界安全条件**：① 空串或仅符号 → 故障 `038A`，`nErrPos := LEN+1`，返回 0；② 任一字符不在 `'0'..'9'` → 故障 `038C`，返回 0、`nErrPos` 指该位置；③ 溢出 → 故障 `038B`，返回夹到 `DL_DINT_MIN`/`DL_DINT_MAX` 的值、`bValid := FALSE`；④ 前导或尾随空格被忽略 → 信息 `0448`；⑤ 元数据 `0449` 预留；⑥ 循环用 `FOR i := 1 TO nLen`（定长，无 `WHILE`）。
- **码位**：信息 `0448`（前后空格已忽略）/ `0449` 预留 ｜ 故障 `038A`（空串/仅符号）/ `038B`（溢出已夹边界）/ `038C`（非法字符）
- **来源标签**：T0-5/T0-6 变体线（`StringToLReal` R13 的整数族缺口），零检索。

#### #12 `FC_DL_DwordToHexString` —— DWORD → 8 位十六进制文本
- **分类**：DL_MathData / Convert ｜ **类型**：FUNCTION → `STRING` ｜ **复杂度**：L
- **引脚**：IN `uValue : DWORD`；`bUpperCase : BOOL := TRUE`；`bPrefix : BOOL := FALSE`（TRUE → `16#` 前缀，长度 11）；OUT `eErr/bError/bValid` + `nLength : INT`。
- **VAR CONSTANT**：`DL_HEX_UPPER : STRING := '0123456789ABCDEF'`；`DL_HEX_LOWER : STRING := '0123456789abcdef'`；`DL_HEX_DIGITS : INT := 8`
- **功能规格**：**禁止委托平台 `DWORD_TO_STRING(...,16#?)` 的格式参数**（三平台对 `16#` 前缀、大小写、前导零行为不一致）。用半字节表自建：`FOR i := 7 DOWNTO 0`，取 `SHR(uValue, i*4) AND 16#F` → `MID(表串, idx+1, 1)` → `CONCAT`。**必须保留前导零**（8 位定宽，LOG 时间戳对齐与报文回放依赖定宽）。
- **边界安全条件**：① `nLength` 与声明串长一致性校验失败（平台 `STRING` 默认长度 < 11）→ 故障 `038D`，返回 `'00000000'` 并 `bValid := FALSE`（声明 `STRING(16)` 时正常）；② 元数据 `038E`/`038F`/`044A`/`044B` 预留；③ 无状态机（R6 N/A）。
- **码位**：信息 `044A` 预留 / `044B` 预留 ｜ 故障 `038D`（目标串长不足）/ `038E` 预留 / `038F` 预留
- **来源标签**：T0-6 字符串化变体线（`HexStringToBytes` R9 的逆向对偶），零检索。**说明**：预留槽偏多属本批特例，因纯格式化函数的故障域天然窄，头注释须写明「预留槽为后续 `bPadZero=FALSE` 变体保留」。

#### #13 `FC_DL_ArraySumLreal` —— 静态数组求和/均值
- **分类**：DL_MathData / Statistics ｜ **类型**：FUNCTION → `LREAL`（和） ｜ **复杂度**：L
- **引脚**：IN `nCount : INT`（有效元素数 0~`DL_ARRAY_MAX`）；INOUT `afData : ARRAY[0..DL_ARRAY_MAX] OF LREAL`；OUT `eErr/bError/bValid` + `fMean : LREAL` + `nValidCount : INT`（剔除非有限后的有效样本数）。
- **VAR CONSTANT**：`DL_ARRAY_MAX : INT := 255`；`DL_LREAL_MAX_FINITE : LREAL := 1.7976931348623157E308`
- **功能规格**：单遍 `FOR`；非有限样本（`x <> x` 或 `ABS(x) > DL_LREAL_MAX_FINITE`）**剔除并计数**，不污染和；`fMean` 仅在 `nValidCount > 0` 时计算（**除零前置判断**）。与 `FB_DL_SignalStatistics`（流式窗口 FB）职责边界：**本件面向静态表一次性求值**（配方系数、标定表、成本权重），无跨周期状态。
- **边界安全条件**：① `nCount < 0` → 故障 `0390`，返回 0；② `nCount > DL_ARRAY_MAX` → 信息 `044D` + 按上限钳位（**钳位而非拒算**：静态表越界声明是配置问题，能算多少算多少并告警）；③ 全部样本非有限（`nValidCount = 0`）→ 故障 `0391`，返回 0、`fMean := 0`、`bValid := FALSE`；④ 部分剔除 → 信息 `044C`；⑤ 累加和溢出（中间量非有限）→ 故障 `0392`，返回 0；⑥ 无状态机（R6 N/A）。
- **码位**：信息 `044C`（非有限样本已剔除）/ `044D`（元素数超上限已钳位） ｜ 故障 `0390`（元素数为负）/ `0391`（无有效样本）/ `0392`（累加溢出）
- **来源标签**：T0-4 变体线（统计族「静态表求值」缺位），零检索。

#### #14 `FC_DL_TimeToHmsString` —— TIME → `HH:MM:SS.mmm`
- **分类**：DL_MathData / Convert ｜ **类型**：FUNCTION → `STRING` ｜ **复杂度**：M
- **引脚**：IN `tIn : TIME`（待格式化时长）；OUT `eErr/bError/bValid` + `bNegative : BOOL` + `nTotalHours : DINT`。
- **VAR CONSTANT**：`DL_MS_PER_SEC : DINT := 1000`；`DL_MS_PER_MIN : DINT := 60000`；`DL_MS_PER_HOUR : DINT := 3600000`；`DL_HMS_FIELD_WARN_H : DINT := 99`（HMI 常见 2 位小时字段上限）
- **功能规格**：`nMs := TIME_TO_DINT(tIn)`（毫秒口径，**必须头注释声明依赖平台 TIME 为 32 位毫秒**）；负值先取绝对值再分解、输出前置 `'-'`（`TIME` 负数在 `−MAX−1` 处不可取绝对值，走 `DINT_MIN` 哨兵分支）。分解：时 = `nMs / 3600000`、分 = `(nMs MOD 3600000) / 60000`、秒 = `(nMs MOD 60000) / 1000`、毫秒 = `nMs MOD 1000`（**全部非负操作数，`MOD` 安全**）。补零用 `MID('00' + DINT 转文本, ...)`？**不**——直接按「商 < 10 则补 '0'」分支拼接，避免依赖 `DINT_TO_STRING` 的前导空格行为（R79 家族）。
- **边界安全条件**：① 负 TIME → 输出带 `'-'` + 信息 `044E`（**统一口径**，不静默取绝对值）；② 小时 > `DL_HMS_FIELD_WARN_H` → 信息 `044F`（HMI 字段宽度提示，`TIME` 上限 596 h 天然可达）；③ 分解中间量越界（防御，理论不可达）→ 故障 `0393`，返回 `'00:00:00.000'`；④ 元数据 `0394`/`0395` 预留；⑤ 无状态机（R6 N/A）。
- **码位**：信息 `044E`（负 TIME 已带负号）/ `044F`（小时超 99，字段宽度提示） ｜ 故障 `0393`（分解中间量非法）/ `0394` 预留 / `0395` 预留
- **来源标签**：T2-1 LGF Converter 子族（`TimeToString` **行为定义**：时长 → 定宽时间文本；本库实现、码位、补零策略 100% 自有）。

#### #15 `FC_DL_DateToIsoString` —— DATE → `YYYY-MM-DD`
- **分类**：DL_MathData / Convert ｜ **类型**：FUNCTION → `STRING`（10 字符） ｜ **复杂度**：M
- **引脚**：IN `dateIn : DATE`；OUT `eErr/bError/bValid` + `nYear/nMonth/nDay : INT`（分解结果单出口，供报表直接取用）。
- **VAR CONSTANT**：`DL_ISO_LEN : INT := 10`；`DL_EPOCH_YEAR : INT := 1970`；`DL_YEAR_MIN : INT := 1970`；`DL_YEAR_MAX : INT := 9999`
- **功能规格**：`nDays := DATE_TO_DINT(dateIn)`（**头注释必须声明「1970-01-01 = 0 天」口径假设未实测，属编译验证债**）；用 Howard Hinnant 公开 `civil_from_days` 整数算法反算 `y/m/d`（纯整数、无查表、无浮点、无循环）。格式化：年 4 位补零、月日 2 位补零，一律走「商 < 10 则前置 '0'」分支拼接。
- **边界安全条件**：① `DATE_TO_DINT` 返回 < 0（早于纪元）→ 故障 `0396`，返回 `'1970-01-01'`、`bValid := FALSE`；② 反算后回代 `days_from_civil(y,m,d) <> nDays` → 故障 `0397`（算法自校验失败，**不允许输出未复验的日期**）；③ 年越 `1970~9999` → 故障 `0396`；④ 输出串长 ≠ 10 → 信息 `0450`（补零逻辑防御提示）；⑤ 元数据 `0451` 预留；⑥ 无状态机（R6 N/A）。
- **码位**：信息 `0450`（输出串长异常已补零）/ `0451` 预留 ｜ 故障 `0396`（早于纪元或年越域）/ `0397`（回代自校验失败）/ `0398` 预留
- **来源标签**：T2-1 LGF Converter 子族（`DTLtoString` 行为定义片段：日期 → 定宽文本）；`civil_from_days` 为公开算法（Howard Hinnant, 公有领域），实现自有；**编译门槛**：`DATE_TO_DINT` 口径未实测，头注释须显式挂债。

### 3.4 批 4（Base 时序/信号守卫五件）

#### #16 `FB_DL_MinOnOffGuard` —— 最短运行/最短停止双守卫
- **分类**：DL_Base / Timing ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **引脚**：IN `bEnable : BOOL := TRUE`（使能，FALSE 立即放行到安全态）；`bReq : BOOL`（上层运行请求）；`tMinOn : TIME := T#10S`（最短运行时间）；`tMinOff : TIME := T#10S`（最短停止时间）；`bReset : BOOL`（上升沿清故障与计时）。OUT `bOut : BOOL`（实际输出）；`bHoldOn : BOOL`（正在强制延长运行）；`bHoldOff : BOOL`（正在强制延长停止）；`tRemaining : TIME`（当前守卫剩余时间）；`eState : E_DL_MinOnOffState`；`eErr/bError`。
- **枚举**：`E_DL_MinOnOffState`（同文件，归属 DL_Base）：`eIdle := 0` 输出 FALSE 且停止时间已满 / `eStarting := 10` 输出 TRUE 起算最短运行 / `eRunning := 20` 输出 TRUE 且最短运行已满 / `eHolding := 30` 请求已撤但最短运行未满，强制保持 / `eCooldown := 40` 输出 FALSE 且最短停止未满 / `eFault := 99`。
- **功能规格**：`TON` **实例在主体最前部无条件刷新**（`fbMinOn(IN := ..., PT := tMinOn)`、`fbMinOff(IN := ..., PT := tMinOff)`，两条调用在任何 `IF` 之前）；状态转移只用「定时器完成位 + 请求电平」组合，不读 `ET` 做判据（`ET` 仅用于 `tRemaining` 输出）。参数钳位：`tMinOn/tMinOff < T#0S` → 钳 0 + 故障 `0399`；`tMinOn/tMinOff` 超 `DL_MIN_ONOFF_MAX`（=T#24H）→ 钳上限 + 信息 `0452`。
- **边界安全条件**：① 非法状态（枚举被外部改写）→ `ELSE` 兜底 `eState := eFault`、`bOut := FALSE`、故障 `039A`；② `tMinOn/tMinOff` 为负 → 故障 `0399`，钳 0 继续（**不停机**：守卫参数错不该让产线停）；③ `bEnable = FALSE` → 立即 `bOut := FALSE`、`eState := eIdle`（安全侧优先，忽略最短运行）；④ 停机请求被最短运行推迟 → 信息 `0453`；⑤ 「启动请求被最短停止阻延」**不设独立码**（由 `bHoldOff` 与 `tRemaining` 输出直接可观测，R90 禁凑槽）；⑥ 元数据 `039B` 预留。
- **码位**：信息 `0452`（时间参数超上限已钳位）/ `0453`（停机请求被最短运行推迟）｜ 故障 `0399`（时间参数为负）/ `039A`（非法状态）/ `039B` 预留。**「启动请求被最短停止阻延」不设独立信息码**——该场景由 `bHoldOff` 与 `tRemaining` 两个输出直接可观测，加码属冗余（R90：不为凑槽加强加码）。
- **来源标签**：T0-2 变体线，零检索。ROADMAP 中「防频繁启停」（冷水机组群控、热泵除霜、泵轮值）四条待办的公共原子。

#### #17 `FB_DL_SignalChangeCounter` —— 带死区与最小间隔的变化次数统计
- **分类**：DL_Base / Signal ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **引脚**：IN `bEnable : BOOL := TRUE`；`fValue : LREAL`（被监视量，如阀位 [%]）；`fDeadband : LREAL := 1.0`（变化死区，同单位）；`tMinInterval : TIME := T#1S`（最小有效变化间隔）；`bReset : BOOL`（上升沿清零计数）。OUT `uCount : UDINT`（有效变化次数）；`uChatterCount : UDINT`（抖动次数，未计入主计数）；`fLastAccepted : LREAL`（上次被接受的值）；`tSinceLast : TIME`；`bSaturated : BOOL`；`eErr/bError`。
- **功能规格**：判据 `ABS(fValue − fLastAccepted) > fDeadband`（**浮点判等一律带死区，禁 `=`**）；满足后按 `tSinceLast >= tMinInterval` 分流：满足 → `uCount + 1`、刷新 `fLastAccepted`；不满足 → `uChatterCount + 1`、**刷新 `fLastAccepted`**（否则同一段连续爬升会被反复判为抖动，一次真实动作被拆成 N 次抖动——这是本件的核心设计点）。`TON` 用于 `tSinceLast`，主体最前部无条件刷新。
- **边界安全条件**：① `fDeadband < 0` 或非有限 → 故障 `039C`，钳 `|fDeadband|` 继续；② `fValue` 非有限 → 保持 `fLastAccepted` 不变（**不把 NaN 写进基准**）+ 信息 `0454`；③ `uCount` 达 `DL_UDINT_MAX` → 饱和 + `bSaturated := TRUE` + 信息 `0455`；④ `bReset` 上升沿清零 `uCount`/`uChatterCount`/`bSaturated`，**不清 `fLastAccepted`**（清基准会产生一次虚假变化）；⑤ 元数据 `039D` 预留。无状态机（R6 N/A：本件为无顺序判据累加，头注释须写明理由）。
- **码位**：信息 `0454`（输入非有限，基准保持不变）/ `0455`（计数饱和） ｜ 故障 `039C`（死区非法）/ `039D` 预留 / `039E` 预留
- **来源标签**：T0-1 变体线 + T2-1 LGF 计数与边沿子族（`CountBooleanEdges` **语义**：变化次数审计；本件为模拟量 + 死区 + 抖动分流的自有扩展，LGF 无此形态）。

#### #18 `FB_DL_SamplingTrigger` —— 均匀采样节拍
- **分类**：DL_Base / Timing ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **引脚**：IN `bEnable : BOOL := TRUE`；`tInterval : TIME := T#1S`（采样周期）；`tDelta : TIME`（**调用方注入的扫描周期增量**，与 `FB_DL_CycleTimeMeasure` 同一纪律，零平台时刻函数）；`bReset : BOOL`。OUT `bSample : BOOL`（单拍 TRUE）；`uSampleNo : UDINT`（样本序号，1 起）；`tTheoretical : TIME`（理论累计时长 = 序号 × 周期）；`tActual : TIME`（注入增量累计的实际时长）；`bDrift : BOOL`（偏差超阈值）。
- **功能规格**：`TON` 以 `tInterval` 为 `PT`，命中沿即 `bSample` 单拍；同时 `tActual := tActual + tDelta`、`tTheoretical := uSampleNo × tInterval`（**用采样序号重算理论值，而不是每拍累加周期**——这是「无漂移」的来源）。`bDrift := ABS(tActual − tTheoretical) > DL_SAMPLE_DRIFT_MAX`（默认 `T#200MS`），漂移只提示不重置（重置会掩盖真实时基丢失）。
- **边界安全条件**：① `tInterval <= T#0S` → 故障 `039F`，钳至 `DL_SAMPLE_INT_MIN`（=T#1MS）继续；② `tDelta <= T#0S`（首扫或注入错误）→ 故障 `03A0`，**本拍不累加 `tActual`**、不产生样本（防首扫伪造节拍）；③ `tDelta > DL_DELTA_MAX`（=T#10S，任务卡顿）→ 故障 `03A0` 同码，累加但置 `bDrift`；④ `uSampleNo` 达 `DL_UDINT_MAX` → 回绕 0 + 信息 `0457`；⑤ 漂移超阈值 → 信息 `0456`；⑥ `bEnable = FALSE` → `bSample := FALSE`、`TON` 仍无条件刷新（`IN := bEnable AND NOT bReset`），保证重新使能时不产生假沿；⑦ 无状态机（R6 N/A）。
- **码位**：信息 `0456`（累计漂移超阈值）/ `0457`（样本序号回绕） ｜ 故障 `039F`（采样周期非法已钳位）/ `03A0`（周期增量非法）/ `03A1` 预留
- **来源标签**：T0-2 变体线，零检索。与 `FB_DL_PulseGenerator`（占空比方波）职责边界：**本件只出采样沿 + 时基账目**。

#### #19 `FB_DL_SignalFrozenDetect` —— 信号冻结检测
- **分类**：DL_Base / Signal ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **引脚**：IN `bEnable : BOOL := TRUE`；`fValue : LREAL`（被监视量）；`fMoveEps : LREAL := 0.05`（判定「有变化」的最小增量，同单位）；`tWindow : TIME := T#30S`（观察窗）；`bReset : BOOL`。OUT `bFrozen : BOOL`（冻结判定，锁存至值恢复变化）；`tFrozenFor : TIME`；`fSpan : LREAL`（窗内极差）；`bInvalidInput : BOOL`（输入非有限）；`eErr/bError`。
- **功能规格**：窗内**跟踪极差**（`fMin`/`fMax` 增量更新，不用数组）；`fSpan := fMax − fMin`；`tWindow` 满且 `fSpan < fMoveEps` → `bFrozen := TRUE` 锁存；任一拍 `ABS(fValue − fPrev) > fMoveEps` → 清窗、`bFrozen := FALSE`。`TON` 无条件刷新；`R_TRIG` 用于 `bReset`。
- **边界安全条件**：① `tWindow <= T#0S` 或 `fMoveEps < 0` → 故障 `03A2`，钳默认值继续；② 输入非有限 → `bInvalidInput := TRUE` + 信息 `0458`，**不更新极值、不推进窗**（非有限不是「冻结」）；③ 输入连续非有限且持续超过 `tWindow` → 故障 `03A3`（判为信号失效，与冻结区分）；④ `fSpan` 恰为 0（完全无抖动）→ 信息 `0459`；⑤ 元数据 `03A4` 预留；⑥ 无状态机（R6 N/A —— 判据累加，非顺序状态机）。
- **码位**：信息 `0458`（输入非有限，窗暂停）/ `0459`（窗内极差为零） ｜ 故障 `03A2`（窗口/死区参数非法）/ `03A3`（持续非有限，判信号失效）/ `03A4` 预留
- **来源标签**：T2-8 NE107 **语义**（`eCheckFunction` 需要「功能自检」判据，传感器卡死是其典型工况）+ T0-1 变体线；判据、阈值、码位 100% 自有。

#### #20 `FB_DL_PulseWidthFilter` —— 窄脉冲抑制
- **分类**：DL_Base / Signal ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **引脚**：IN `bEnable : BOOL := TRUE`；`bIn : BOOL`（原始信号）；`tMinWidth : TIME := T#20MS`（允许通过的最小脉冲宽度）；`bReset : BOOL`。OUT `bOut : BOOL`；`uRejectCount : UDINT`（被吞掉的窄脉冲数）；`bRejected : BOOL`（本拍发生抑制）；`eErr/bError`。
- **功能规格**：**双侧确认窗**——`bIn` 经过 `tMinWidth` 确认后才搬运到 `bOut`，上升沿与下降沿各用一只 `TON`（`fbOnDelay` 确认上升、`fbOffDelay` 确认下降），两只 `TON` 在主体最前部**无条件刷新**。这样输出相对输入整体滞后 `tMinWidth`，**脉宽不失真**（若只延迟上升沿，每个合格脉冲会被削掉 `tMinWidth` 宽度，是本件最易写错的点）。窄脉冲因无法维持到确认完成而**整段不出现在输出**，`uRejectCount` 在「输入已回落但确认未完成」的拍递增。
- **边界安全条件**：① `tMinWidth <= T#0S` → 故障 `03A5`，钳至 `DL_PWF_MIN`（=T#1MS）继续；② `tMinWidth < 2×扫描周期`（无法保证确认窗有效）→ 信息 `045A`（**只提示**：扫描周期由调用方注入不可知，库不擅改参数）；③ `uRejectCount` 饱和 → 故障 `03A6`（饱和后抑制统计失真，需复位）；④ `bEnable = FALSE` → `bOut := bIn` **直通**（旁路时不得留门控残影）；⑤ 非法状态（若实现引入枚举）→ `ELSE` 兜底置 `bOut := FALSE` + 故障 `03A7`（**注**：本件为无顺序状态机的纯时序件，若不引入枚举，则 `03A7` 保留预留并在头注释写 R6 N/A 理由）。
- **码位**：信息 `045A`（确认窗小于两倍扫描周期的提示）/ `045B` **预留禁用**（本件信息级仅用 1 槽，第 2 槽不加强加码，执行 R90）｜ 故障 `03A5`（最小宽度非法已钳位）/ `03A6`（抑制计数饱和）/ `03A7` 预留
- **来源标签**：T0-1 变体线，零检索。与 `FB_DL_SignalDebounce` 职责边界：**去抖延迟跳变并对两侧同宽；本件整段吞掉窄脉冲且不削宽**。

---

## 4 编码派单规格 · 样板原文（R50 教训：派单必须内嵌可照抄原文）

> 以下四段是**逐字可抄**的样板。编码专家只替换 `[组件名]`/`[分类]`/`[规格]` 等占位，**不得改动结构与注释格式**。

### 4.1 头注释块样板（七项齐全 + R1~R8 自检行）

```iecst
(*
    组件名称 : [POU 名]
    所属子库 : [DL_Base / DL_MathData]
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : [一句话功能]。
              [第 2~4 行写关键设计取舍：为什么这样实现、拒绝了哪条看似可行的路线]
    开源溯源 : [原创实现 / 参考 LGF 公开文档的「分类与参数域经」]，本实现为独立重构，
              未复制任何闭源或开源源码；[若涉及 T2 闭源源，写明「只借 X，算法/码位/状态机 100% 自有」]
    本文件内含 : FUNCTION [POU 名]（单 POU，无配套类型）
                 [若有同文件枚举：TYPE E_DL_XXX（归属本子库）]
    依 赖    : 无 DL_ 内部依赖；Standard.library: [TON / R_TRIG / 无]
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ [本件的具体防御点：除零/越界/守卫/饱和]
              R5 ✓ 全变量中英双语同行注释 ｜ R6 [✓ 状态机 ENUM+CASE+ELSE / N/A 理由]
              R7 [✓ 定时器与边沿实例主体最前部无条件刷新 / N/A 理由]
              R8 ✓ 阈值与上限全常量化
    遗留假设 : [凡委托平台内建或依赖扫描周期口径，逐条写明「未实测，编译门槛未闭合」]
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 [1-4] 入库
*)
```

### 4.2 错误码通道声明样板（`eErr : UDINT` + `16#0001_XXXX` 惯例）

```iecst
VAR_OUTPUT
    eErr   : UDINT;   // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError : BOOL;    // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag
    bValid : BOOL;    // 返回值是否可用，FALSE 时调用方必须走故障分支 / output valid flag
END_VAR

VAR CONSTANT
    DL_ERR_NONE        : UDINT := 16#0000_0000;   // 无故障 / no error
    DL_ERR_INFO_BASE   : UDINT := 16#0001_0434;   // 本件信息级码基址（逐件改写）/ info code base
    DL_ERR_FATAL_BASE  : UDINT := 16#0001_036C;   // 本件故障级码基址（逐件改写）/ fault code base
END_VAR
```

> **错误码表（原文照抄，替换码值与含义）**：
> ```text
> 错误码     : 16#0001_0434 [信息级] XXXXXX —— 具体触发条件、输出行为、是否置 bError
>             16#0001_0435 [信息级] 预留禁用（不得挪用）
>             16#0001_036C [故障级] XXXXXX —— 具体触发条件、返回什么值、bValid 取值
>             16#0001_036D [故障级] XXXXXX —— ...
>             16#0001_036E [故障级] 预留禁用（不得挪用）
> ```
> **纪律**：信息级码**一律 `bError := FALSE`、`bValid := TRUE`**；故障级码 **`bError := TRUE`**；预留槽在实现体**不得出现赋值**（收口阶段的码位唯一性断言会扫这一点）。

### 4.3 变量声明区双语同行注释样板（每个变量必带，含单位）

```iecst
VAR_INPUT
    fIn        : LREAL := 0.0;      // 待处理输入值 [mm]，有效域见遗留假设段 / input value in mm
    nStartBit  : INT   := 0;        // 位段起始位，0~63，越界即拒算 / start bit, 0..63
    tMinWidth  : TIME  := T#20MS;   // 最小允许脉冲宽度 [ms]，≤0 时钳 1ms / min pulse width
    bEnable    : BOOL  := TRUE;     // 使能，FALSE 时输出回安全态 / enable flag
END_VAR

VAR_IN_OUT
    afData     : ARRAY[0..DL_ARRAY_MAX] OF LREAL;   // 定长数组，超出 nCount 的元素不参与 / fixed array
END_VAR

VAR
    fbOnDelay  : TON;               // 上升沿确认窗定时器，主体最前部无条件刷新 / on-delay confirm timer
    rtReset    : R_TRIG;            // 复位上升沿，主体最前部无条件刷新 / reset rising edge
    fPrevValue : LREAL := 0.0;      // 上一拍输入值，用于增量判据 / previous scan value
    bInitDone  : BOOL  := FALSE;    // 首扫初始化标志，防未初始化结构体带入 NaN / first-scan flag
END_VAR

VAR CONSTANT
    DL_FLOAT_EPS   : LREAL := 1.0E-12;   // 浮点判等容差，禁直接用 = / float compare tolerance
    DL_ARRAY_MAX   : INT   := 255;       // 数组声明上限 [个] / array upper bound
    DL_GUARD_MAX   : DINT  := 1000;      // 循环防死锁计数器上限 [次] / loop guard limit
END_VAR
```

### 4.4 状态机样板（仅 FB 件，`ENUM` + `CASE` + `ELSE` 兜底 + 定时器前置刷新）

```iecst
TYPE E_DL_MinOnOffState :
(
    eIdle     := 0,     // 空闲：输出 FALSE，最短停止已满 / idle
    eStarting := 10,    // 启动中：输出 TRUE，最短运行计时 / starting, min-on timing
    eRunning  := 20,    // 运行中：输出 TRUE，最短运行已满 / running
    eHolding  := 30,    // 保持中：请求已撤但最短运行未满，强制输出 TRUE / holding
    eCooldown := 40,    // 冷却中：输出 FALSE，最短停止计时 / cooldown
    eFault    := 99     // 故障锁定，需 bReset 上升沿退出 / fault latched
);
END_TYPE

// ---- 主体：定时器/边沿实例必须在任何 IF 之前无条件刷新（红线 R4/R7）----
fbMinOn ( IN := (eState = eStarting) OR (eState = eHolding), PT := tMinOn );
fbMinOff( IN := (eState = eCooldown),                        PT := tMinOff );
rtReset ( CLK := bReset );

CASE eState OF
    E_DL_MinOnOffState.eIdle:
        bOut := FALSE;
        IF bReq AND fbMinOff.Q THEN
            eState := E_DL_MinOnOffState.eStarting;
        END_IF

    E_DL_MinOnOffState.eStarting:
        bOut := TRUE;
        IF fbMinOn.Q THEN
            eState := E_DL_MinOnOffState.eRunning;
        END_IF

    E_DL_MinOnOffState.eRunning:
        bOut := TRUE;
        IF NOT bReq THEN
            eState := E_DL_MinOnOffState.eHolding;
        END_IF

    E_DL_MinOnOffState.eHolding:
        bOut := TRUE;
        IF fbMinOn.Q THEN
            eState := E_DL_MinOnOffState.eCooldown;
        END_IF

    E_DL_MinOnOffState.eCooldown:
        bOut := FALSE;
        IF fbMinOff.Q THEN
            eState := E_DL_MinOnOffState.eIdle;
        END_IF

    E_DL_MinOnOffState.eFault:
        bOut := FALSE;
        IF rtReset.Q THEN
            eState := E_DL_MinOnOffState.eIdle;
        END_IF

    ELSE
        // 强制安全兜底：非法状态一律回安全态并置故障（红线 R4）
        eState := E_DL_MinOnOffState.eFault;
        eErr   := 16#0001_039A;   // 非法状态，已强制回安全态
        bError := TRUE;
        bOut   := FALSE;
END_CASE
```

### 4.5 收口阶段自检清单（编码专家与总监各跑一遍）

- [ ] 文件名 = POU 名，前缀与类型一致（`FC_DL_` / `FB_DL_`）
- [ ] 头注释七项齐全 + R1~R8 自检行 + **遗留假设段**（本轮新增硬要求）
- [ ] 全部变量 / 枚举项带中英双语同行注释与单位
- [ ] 无 `GVL` / `VAR_EXTERNAL` / `%IX` `%QX` `%MW` / `%I` `%Q` `%M`
- [ ] 无厂商专有库、无 `POINTER TO` / `REFERENCE TO`、无隐式转换
- [ ] FB 件有 `ENUM` + `CASE` + `ELSE` 兜底；定时器/边沿实例在主体最前部
- [ ] 浮点无 `=` 判等；除法前置防零；数组边界显式判；`WHILE` 有守卫
- [ ] 无魔法数（阈值/限幅/超时全常量化或引脚化）
- [ ] 错误码表 5 槽齐（2 信息 + 3 故障），预留槽实现体零赋值
- [ ] 码位与 §3 派单表**逐字一致**（收口后用 grep 断言全库唯一）

---

## 5 检索与合规（合规铁律：闭源只借分类/参数域/命名，代码 clean-room）

| 项 | 内容 |
|---|---|
| 检索次数 | **2 次**（不超过 3 次预算；其余 18 件零检索） |
| 检索目的 | 核对 LGF 的**功能组划分与参数域**，为批 2 / #14 / #15 确立「借什么、不借什么」的边界 |
| 主要来源 | Siemens `Library of General Functions` 公开下载说明页（SIOS-ID 109479728）衍生的公开文档摘录与第三方分类索引（详见 `RAW_NOTES_R21.md`） |
| 许可证结论 | LGF **免费使用但不开源**（不可修改后重新发布）→ 按最严口径处置：**只借「分类事实 + 参数名域 + 行为定义」，零代码行、零注释引用、零符号名复制** |
| 本轮禁用做法 | 不抄 LGF 函数名（`LGF_BitTest` 等前缀一律不用）、不抄其错误处理结构（`ENO` 模式）、不抄其块版本号表 |
| 自查结论 | 20 件的状态机、码位、阈值、判据、错误码全部自有；与 LGF 的交集仅为「位域合并/拆分存在」「CRC 参数含 init/xorout/reflect」「时长与日期存在转文本需求」三条**分类级事实** |

### 5.1 规则候选（转 R21 收口写入 `AGENT_EVOLUTION_LOG.md`）

- **R89（读可截断 / 写必须拒写）**：#6 与 #7 的策略分野——**读操作**越界可按可用宽度截断并置 `bTruncated`（结果可观测、无副作用）；**写操作**越界必须拒写并返回原值（副作用不可逆，「宁可一字不写」）。同源前例：R12 `BitArrayInsert` 的「宁可一字不写不写半个字」。
- **R90（错误码预留槽必须真预留）**：派单给 5 槽但实现只用 2 槽时，余槽写「预留禁用」且实现体零赋值；**严禁为凑满槽位强加低价值信息码**（#20 信息级只用 1 槽即为本规则首个执行样例）。
- **R91（派单必须带遗留假设段）**：凡委托平台内建（`DATE_TO_DINT` / `TIME_TO_DINT`）或依赖扫描周期口径的件，头注释必须显式挂「未实测，编译门槛未闭合」，把编译验证债**从文档债变成代码内可见债**（#14 #15 为执行样例）。

---

## 6 交接口径（本阶段不动作清单）

| 不在本阶段做 | 归属 |
|---|---|
| 生成任何 `.st` 文件 | 批次 1-4 编码阶段 |
| 修改 `INDEX_REGISTRY.json` / JSONL / `VERSION.md` / `MANUAL_*.md` | 收口阶段 |
| 补齐 `LIBRARY_MANUAL.md` 的 R18/R19 两章（ROADMAP §23.3 P2） | 收口阶段文档线（**最高优先，已连欠两轮**） |
| 编译验证债（ROADMAP §23.1 P0，已连续 15 轮悬置） | 收口阶段基础设施线，**不占组件配额**；本轮 #14 #15 又新增 2 条内建链假设，债务继续扩大需在收口时点名 |
| `_verify_counts.py` 台账断言脚本（ROADMAP §23.1 P0） | 收口阶段 |

**下一轮（R22）建议方向**（写入 ROADMAP 时展开）：
1. **P0**：`FB_DL_SemaMutex` v1.1 所有权审计（ROADMAP §23.2 已立项，现场死锁定位刚需）。
2. **P1**：T2-1 LGF「多段一次搬」子族（`FC_DL_BitArrayMultiInsert`）+ Data Handling 残余（`FC_DL_Crc16Reflect` 若 #9 参数化后仍有独立反射优化需求，须先给验收粒度）。
3. **P2**：把 #1/#2 两个数学原子**回灌**到存量件的内联实现（技术债回收，属重构不增件，走 PATCH 版本）。

---

*R21 阶段一 + 阶段二 ｜ 2026-11-16 20:38 ｜ 道莅工控代码库产品总监*
