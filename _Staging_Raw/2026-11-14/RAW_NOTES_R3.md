# RAW_NOTES_R3 ｜ 道莅万级工业代码库 · 第三轮狩猎笔记

> **文档编号**：DL-RN-2026-11-14-003
> **轮次**：Round 03 ｜ Level 0 收口（DL_Base 4 + DL_MathData 10）｜ 目标 14 组件
> **撰写人**：道莅工控代码库产品总监（Daoli Library Director）
> **检索日期**：2026-11-14 ｜ 共 7 条检索记录（WebSearch ×7，公开资料核实）
> **性质**：情报记录，不落任何 `.st` 源码文件；本目录原始资料永不被正式目录引用
> **配套规格书**：`C:\Library\_Staging_Raw\2026-11-14\ROUND_PLAN_R3.md`

---

## 0 本轮狩猎目标对应表

| 本轮组件 | 狩猎关键词 | 主要参考（记录编号） |
|---|---|---|
| TwoHandSafety | ISO 13851 two-hand control synchronism 500 ms / anti-tie-down | 记录 6 |
| InterlockMatrix | first-out / first-cause / 8-signal interlock 粒度 | 记录 3（LBP_Intlk8）、记录 1（LGF Bit Logic） |
| RedundantSwitch | tolerance window / plausibility check / deviation | 记录 1（Comparator 组）、记录 3（LBP_AnaAvg 合理性检查） |
| DutyStandbyRotation | 8 aggregates / lead-lag / min run time | 记录 3（LBP_Aggr8） |
| MultiPointLinear | 8-point interpolation / non-linear setpoints | 记录 2（LGF_typeNonLinSetpoints）、记录 3（LBP_Polygon） |
| PolygonArea / LineIntersection | plane geometry / 2D-3D distance | 记录 1（Math 组） |
| Crc32Ethernet | CRC-32/ISO-HDLC check value / 0xEDB88320 | 记录 4 |
| LrcChecksum | Modbus ASCII LRC / two's complement | 记录 5 |
| LifoStack | LIFO / stack / FIFO vs LIFO | 记录 1（Data Handling 组、LGF_LIFO） |
| MedianFilter | median filter / spike removal / _ARRAY_MEDIAN | 记录 7 |
| SignalStatistics | standard deviation / variance / spread | 记录 7（ARRAY_SDV / VAR / SPR）、记录 2（LGF_typeRegressionLine） |
| QuickSortLReal | sort / shell sort / sort in place | 记录 1（LGF_ShellSort_*）、记录 7（_ARRAY_SORT / SORT_1D） |
| HexStringToBytes | hex string to byte / string↔number conversion | 记录 1（Converter 组）、记录 5（ASCII 帧解码） |

---

## 1 记录一 ｜ 西门子 LGF 的组结构与组容量（T2 · 闭源）

| 字段 | 内容 |
|---|---|
| **来源名称** | SIMATIC S7-1500 / S7-1200 Library of General Functions (LGF)，Entry ID **109479728**（官方支持入口页） |
| **URL** | `https://support.industry.siemens.com/cs/dk/en/view/109479728` |
| **许可证** | **免费使用，但闭源版权**（西门子保留版权；块未加密可改，但代码本身非开源） |
| **版本锚点** | 页面标注 V5.5.0（TIA Portal V20/V21）；文档另见 V5.2.1 / V5.3.0。本轮**只读官方页面与文档目录级信息**，未下载、未解包、未导入任何库文件 |
| **提取点** | ① 11 个功能组的**分组骨架**：Bit Logic / Date and Timer / Counter / Comparator / Math / Data Handling / Converter / Signal Generators / Technology / Measurement / Legacy；② 「140+ 个 FC/FB」的规模与**组内粒度**；③ 具体块名与职责边界（`LGF_FIFO`、`LGF_LIFO`、`LGF_ShellSort_DInt/_LReal/_UDInt`、`LGF_SearchMinMax`、`LGF_StoreMinMax`、`LGF_ScaleLinear`、`LGF_IsValueInLimits`、`LGF_Average`、`LGF_RuntimeMeasurement`、`LGF_BitSet`/`LGF_BitToggle`、`LGF_Polygon` 级别的插值转换、`LGF_MergeBytesToWord`/`SplitDWordToBytes`/`SwapBlockWord` 字节族） |
| **对应组件** | `FB_DL_LifoStack`（组内粒度：FIFO/LIFO 各成一块，带满/空/长度）、`FC_DL_QuickSortLReal`（排序按类型分族）、`FC_DL_MultiPointLinear`（定标族参数域）、`FB_DL_RedundantSwitch`（Comparator 公差窗口）、`FC_DL_HexStringToBytes`（Converter 族）、`FB_DL_InterlockMatrix`（Bit Logic 位图组织） |
| **合规处置** | **仅借鉴功能分类体系、接口参数域与组内粒度**，不复制代码、不复制 DB 结构、不复制注释原文。本库实现为 **clean-room 独立编写**，`.st` 头注释按「原创实现（参考 LGF 分类与参数域）」表述 |

**关键判断（写进规格书的依据）**：LGF 把「FIFO」和「LIFO」拆成两个独立 FB 而不是一个带 `MODE` 的队列块——这正是本库「先原子化再矩阵化」纪律的外部佐证。本库沿用该粒度，但**刻意不沿用其实现形态**（LGF 为 SCADA/PLC 双端库，含大量 HMI 面板耦合；本库只做纯 PLC 侧原子件）。

---

## 2 记录二 ｜ LGF 官方文档的组编号、UDT 与常量组织（T2 · 文档版权）

| 字段 | 内容 |
|---|---|
| **来源名称** | *Library of General Functions (LGF)* 文档 V5.2.1（PDF，随 Entry ID 109479728 发布） |
| **URL** | `https://support.industry.siemens.com/cs/attachments/109479728/109479728_LGF_DOC_V5_2_1_en.pdf` |
| **许可证** | 文档版权（西门子）；**文档内容可阅读引用，不可原样转载进本库文档** |
| **提取点** | ① 组编号体系：`5.2 01 Date and timer operations`、`5.3 04 Math operations`、`5.4 05 Data handling`、`5.5 08 Technology operations`、`5.6 09 Measurement operations`、`5.7 10 System operations`；② UDT 命名与归属：`LGF_typeNonLinSetpoints`（08 Technology，非线性设定点表）、`LGF_typeRegressionLine`（09 Measurement，回归线）、`LGF_typeDataLogParameter` / `LGF_typeFileReadWriteDeleteParameter`（05 Data handling）、`LGF_typeDiagnostics`、`LGF_typeGPS`；③ 常量族：`LGF_CONSTANTS`、`LGF_CONSTANTS_UNITS`、`LMATH CONSTANTS`、`LMATH_CONSTANTS_EXTENDED`、`LPHYSICS CONSTANTS` |
| **对应组件** | `FC_DL_MultiPointLinear`（`LGF_typeNonLinSetpoints` 证明「非线性标定 = 折点表 + 点数」是业界标准参数形态）、`FB_DL_SignalStatistics`（`LGF_typeRegressionLine` 说明统计族在该库中属「测量评估」而非纯数学）、`FC_DL_QuickSortLReal`（`LMATH CONSTANTS` 级别的常量组织方式） |
| **合规处置** | 只引用**组名、UDT 名、常量族名**这类「目录级事实」，不引用任何块的接口表原文、不复制 PDF 文字段落。**未引用任何页码**——本次仅取得目录级摘要，页码无法逐条核实，故一律以「文档 ID + 章节名」表述，杜绝编造 |

**产品判断**：LGF 把「非线性标定」放在 Technology 组、把「统计回归」放在 Measurement 组，而不是都塞进 Math——这是**按使用场景而非按数学分支**分组。本库沿用其分类直觉（`MultiPointLinear` 的标签取 `lgf-math` 但规格书中注明其真实归属是「标定/工艺」），但目录落点仍按本库分层纪律（纯数值计算 → `DL_MathData`）。

---

## 3 记录三 ｜ 西门子 LBP 的块清单与 cmd/ind 命名（T2 · 闭源）

| 字段 | 内容 |
|---|---|
| **来源名称** | *Library for Basic Processes (LBP) V2.8 — Operation / Implementation*（Entry ID **109749508**） |
| **URL** | `https://support.industry.siemens.com/cs/attachments/109749508/109749508_LBP_V2.8_Operation_DOC_en.pdf` ／ `https://cache.industry.siemens.com/dl/files/508/109749508/att_1275606/v5/109749508_LBP_V2.8_Implementation_DOC_en.pdf` |
| **许可证** | **免费使用，闭源版权**（同上，非开源） |
| **提取点** | ① 块清单（Table 1-1）：`LBP_Aggr8`（Control of up to **8 Aggregates**）、`LBP_Intlk8`（Interlock for up to **8 signals**）、`LBP_Polygon`（Conversion of values over **8 interpolation points**）、`LBP_AnaAvg`（Average calculation **with plausibility check**）、`LBP_AnaRead`、`LBP_CtrlPID`、`LBP_CtrlStp`、`LBP_Mtr`/`LBP_MtrDS`/`LBP_MtrF`、`LBP_Vlv`/`LBP_VlvA`/`LBP_3wVlv`、`LBP_CntrA`/`CntrD`/`CntrP`、`LBP_TimeSw`、`LBP_SetCrv`、`LBP_Select`、`LBP_Msg8`；② 命名与接口思想：`cmdXXX`（命令输出侧）/ `indXXX`（反馈输入侧）成对命名，块用 `ind` 输入**校验命令是否真的被执行**（电机启动后的反馈确认）；③ `identName` 用于 HMI 消息过滤与符号生成 |
| **对应组件** | `FB_DL_DutyStandbyRotation`（`LBP_Aggr8` 的 8 台粒度 + cmd/ind 命令-反馈分离 → 本库 `abStartCmd` / `abUnitRunning` 双数组）、`FC_DL_MultiPointLinear`（`LBP_Polygon` 的 8 点插值粒度）、`FB_DL_InterlockMatrix`（`LBP_Intlk8` 的 8 路互锁粒度，本库改 16 路并留档）、`FB_DL_RedundantSwitch`（`LBP_AnaAvg` 的「带合理性检查的平均」提供的「先判合理性再算值」范式） |
| **合规处置** | **仅借鉴功能分类、块粒度、参数域与命令/反馈分离的接口思想**；不复制 SCL 代码、不复制 HMI 面板、不复制 `identName` 机制。clean-room 实现 |

**关键判断**：`LBP_Aggr8` 只有 8 台不是技术限制，而是**HMI 面板信息密度与现场机组数量的折中**（一个泵站通常 2~6 台，8 台留余量）。本库取 8 台与之对齐，而不是做 32 台「通用」调度器——后者在 HMI 上不可用，且会让 `anRank` 数组与引脚爆炸。

---

## 4 记录四 ｜ CRC-32/ISO-HDLC 的参数模型与 check 值（T3 · 公开目录）

| 字段 | 内容 |
|---|---|
| **来源名称** | ① CRC Calculator（crccalc.com，12 种 CRC-32 变体参数对照）；② CRC-32 Calculator（testbench.tools，含 ISO-HDLC 参数表、参考实现与 check 值说明）；③ tool.io / webtoolsplanet / altftool 的 CRC-32 工具页（交叉核对） |
| **URL** | `https://crccalc.com/` ／ `https://testbench.tools/tools/crc-32` ／ `https://tool.io/checksum/crc-32` |
| **许可证** | 工具站与公开算法目录（概念与参数引用，不涉及代码分发）；CRC-32 算法本身属公有领域 |
| **提取点** | ① 参数模型：width 32、polynomial `0x04C11DB7`（**反射形式 `0xEDB88320`**）、init `0xFFFFFFFF`、RefIn/RefOut `true/true`、XorOut `0xFFFFFFFF`；② **check 值：ASCII `"123456789"` → `0xCBF43926`**；③ 反例对照：同多项式但不反射的 **CRC-32/BZIP2 → `0xFC891918`**，JAMCRC（不异或终值）→ `0x340BC6D9`，POSIX（init=0）→ `0x765E7680`；④ 反射实现的机理说明：寄存器保持位反序、右移、每次与 `0xEDB88320` 异或 |
| **对应组件** | `FC_DL_Crc32Ethernet`（参数模型 + 4 条自检向量；其中 V4「分块链式」为本库新增语义，需自行复算） |
| **合规处置** | 只引用**参数组合与 check 值**（公开事实），未复制任何工具站的实现代码。**双源核对已完成**（crccalc 与 testbench 参数一致，check 值一致），符合拟新增规则 **R17** |

**关键判断（写进规格书 B1/B2）**：CRC 实现的第一大错不是算错，而是**混搭**——用 `0x04C11DB7` 配右移、或用反射多项式配左移，或漏掉 init/xorout。这三类混搭都能「跑出一个数」，且都能通过「两次调用结果一致」的自测，只有对照 check 值才能发现。因此本库把「`123456789 → 0xCBF43926`」定为**准入门槛**，不是可选项。

---

## 5 记录五 ｜ Modbus ASCII 的 LRC 定义与向量（T3 · 公开规范）

| 字段 | 内容 |
|---|---|
| **来源名称** | ① Otomasyon AVM《What is MODBUS-ASCII?》；② Modbus 中文网《Modbus CRC/LRC 校验原理与编程实现》；③ next.gr Modbus 教程；④ Chipkin《Modbus CRC & LRC Error Checking》；⑤ 公开的 Modbus 应用协议规范（ASCII 传输模式） |
| **URL** | `https://www.otomasyonavm.com/en/what-is-modbus-ascii` ／ `https://www.modbus.cn/44511.html` ／ `https://docs.chipkin.com/articles/modbus-crc-lrc-error-checking-and-troubleshooting/` |
| **许可证** | 公开协议规范 + 技术文章（概念与向量引用） |
| **提取点** | ① LRC 定义：对「地址 + 功能码 + 数据」按无符号 8 位求和，取**二进制补码**（`LRC = 0x100 - (sum AND 0xFF)`）；② **`':'`、CR、LF 不参与计算**；计算对象是**解码后的字节**，不是 ASCII 字符码；③ **向量 1：`01 03 00 00 00 01` → sum `0x05` → LRC `0xFB`**，完整帧 `:010300000001FB\r\n`（并明确指出网上流传的 `...FD` 是错的）；④ **向量 2：响应 `01 03 02 12 34` → sum `0x4C` → LRC `0xB4`**；⑤ 帧格式：`':'` 起始、CR/LF 结束、每字节 2 个 ASCII 十六进制字符、字符间隔 ≤ 1 s；⑥ LRC 弱于 CRC-16，无法检出全部多位错误 |
| **对应组件** | `FC_DL_LrcChecksum`（定义 + 5 条向量）、`FC_DL_HexStringToBytes`（`bStripFraming` 剥离 `':'` 与 CR/LF 的依据：ASCII 帧的边界字符不参与解码） |
| **合规处置** | 只引用**协议定义与公开向量**，独立实现。**双源核对**：向量 1/2 在 otomasyonavm、modbus.cn、chipkin 三处一致（chipkin 页面示例帧尾数字有排版差异，但 LRC 值 `0xFB` 一致） |

**关键判断**：`FC_DL_LrcChecksum` 与 `FC_DL_HexStringToBytes` 必须是**两步**（先解码成字节、再算 LRC），而不是一个「传字符串直接出 LRC」的合成块。理由：① 合成块无法暴露「第几个字符非法」；② 现场调试时工程师需要单独看到字节序列；③ 符合本库「原子化」纪律。这条在 `ROUND_PLAN_R3.md` §7.9 B2 与 §7.14 中互为引用。

---

## 6 记录六 ｜ ISO 13851 / IEC 60204 双手控制的工程约束（T2 · 公开标准解读）

| 字段 | 内容 |
|---|---|
| **来源名称** | ① SpecForge《Two-hand control selection for warehouse machines: ISO 13851, PLd, and timing》；② SpecForge 百科《Two-Hand Control Devices》（Type I/II/IIIA/IIIB/IIIC 特性对照）；③ Industrial Monitor Direct《Hydraulic Press Hands-Free Upgrade: Two-Hand Control Design》（参数表）；④ Banner Engineering《DUO-TOUCH Features》（厂商技术文档）；⑤ Industrial Monitor Direct《Configuring Two-Hand Control on Siemens LOGO!》（含 7 项验证步骤） |
| **URL** | `https://www.sourcebyspec.com/news/two-hand-control-selection-for-warehouse-machines-iso-13851-pld-and-timing.html` ／ `https://www.sourcebyspec.com/encyclopedia/two-hand-control.html` ／ `https://industrialmonitordirect.com/pt/blogs/knowledgebase/hydraulic-press-hands-free-upgrade-two-hand-control-design` ／ `https://info.bannerengineering.com/cs/groups/public/documents/literature/131634.pdf` ／ `https://industrialmonitordirect.com/pl/blogs/knowledgebase/configuring-two-hand-control-on-siemens-logo-plcs` |
| **许可证** | 公开标准的技术解读与厂商公开文档（概念引用，不涉及代码） |
| **提取点** | ① **同步窗 ≤ 500 ms**（ISO 13851:2019 §5.2，Type IIIC；放宽须风险评估支持）；② **释放差允许 ≤ 100 ms**（§5.3）——本库 `tReleaseWindow` 默认值 `T#100MS` 的出处；③ 五项通用特性：双手并用、输出与输入的规定关系、松开任一即断输出、防误操作/防旁路、**必须两只手都回到 off 才能再生输出**（anti-repeat / release-before-reset）；④ **上电时双手已按下不得启动**（LOGO! 案例用 SR 锁存初值 R 实现，验证步骤第 7 条）；⑤ **标准 PLC 的普通输出不是安全额定**，ISO 13851 Type IIIC 要求安全继电器或 F-CPU，标准 PLC + 软件计时被明确列为**不合格配置**；⑥ 按钮间距 ≥ 550 mm、按压力 20~50 N、蘑菇头 ≥ 60 mm 等机械要求（属机械设计，不属本块） |
| **对应组件** | `FB_DL_TwoHandSafety`（`tSyncWindow = 500 ms`、`tReleaseWindow = 100 ms`、上电武装锁 `bArmLatch`、卡死检测、以及**强制合规披露段**） |
| **合规处置** | 只引用**标准条款的工程含义与参数值**，未复制任何继电器厂商的固件逻辑；标准原文未获取全文，故**不引用具体页码**，只引用「ISO 13851:2019 §5.2 / §5.3」这类条款号（多个二级来源一致引用该条款号） |

**关键判断（D-R3-06 的直接来源）**：多份来源反复强调「标准 PLC 不能作为唯一安全措施」。本库若把这个块包装成「安全功能块」，就是在帮客户制造合规风险。因此规格书要求头注释**原文保留**合规披露段，且在索引 `function_tags` 中禁止出现 `safety-certified` 之类暗示认证的词（拟新增 **R18**）。

**与 ROADMAP 的偏差留档**：`ROADMAP.md` 原文写「IEC 60204 标准，要求双按钮在 500ms 内同时按下」。核对后确认：500 ms 同步窗的规范出处是 **ISO 13851**（IEC 60204-1 管的是电气设备的一般要求与安全相关控制的部分条款）。规格书按「`iec60204` + `iso13851` 双标签」处理，不改 ROADMAP 文字（阶段五再统一措辞）。

---

## 7 记录七 ｜ OSCAT 的数组/统计/排序族与其指针入参事实（T1 · EPL-2.0）

| 字段 | 内容 |
|---|---|
| **来源名称** | ① OSCAT BASIC 库文档 V3.33（官方 PDF）；② Teco AT 的 OSCAT BASIC 函数目录页；③ RWTH-EBC/AixOCAT wiki 的《OSCAT BASIC Arrays》章节；④ Industrial Monitor Direct《在 CODESYS PLC 中使用 OSCAT 函式库》 |
| **URL** | `http://www.oscat.de/images/OSCATBasic/oscat_basic333_en.pdf` ／ `https://www.tecomat.cz/en/sw-nastroje/mosaic-programovani-plc/knihovny-rozsireni/open-source-knihovny/oscat-basic` ／ `https://github.com/RWTH-EBC/AixOCAT/wiki/OSCAT-BASIC-Arrays` ／ `https://industrialmonitordirect.com/blogs/knowledgebase/using-oscat-library-with-codesys-plcs-setup-guide` |
| **许可证** | **Eclipse Public License 2.0（EPL-2.0）**，可商用；需致谢 |
| **提取点** | ① 数组族清单：`_ARRAY_MEDIAN`、`_ARRAY_SORT`、`_ARRAY_INIT`、`_ARRAY_ADD`、`_ARRAY_MUL`、`_ARRAY_SHUFFLE`、`ARRAY_AVG/GAV/HAV`、`ARRAY_MAX/MIN`、**`ARRAY_SDV`（标准差）、`ARRAY_VAR`（方差）、`ARRAY_SPR`（极差 = max - min）**、`ARRAY_SUM`、`ARRAY_TREND`、`IS_SORTED`；另有序列 `SORT_1D`、`SEARCH`、`SHIFT_REG`、`FILTER_1D`、`AVERAGE`、`INTEGRAL`；② **关键事实：OSCAT 全部数组函数以 `ADR(Array)` + `SIZEOF(Array)` 指针 + 字节长度入参**，并**直接原地修改内存**（`_ARRAY_MEDIAN` 会把传入数组排成有序，`_ARRAY_ADD` 直接写回）；③ 中值定义：偶数个元素时取中间两个的**平均**；④ 生态提示：完整 OSCAT 库的 POU 数量接近部分 PLC 目标的上限，建议只导出所需 POU |
| **对应组件** | `FB_DL_MedianFilter`（中值行为定义；**拒绝**其指针与原地排序副作用）、`FB_DL_SignalStatistics`（`ARRAY_SDV/VAR/SPR` 的输出集合定义；**拒绝**整数组一次算，改流式窗口 + 两遍法）、`FC_DL_QuickSortLReal`（`_ARRAY_SORT` 的原地排序语义；**拒绝**指针入参，改 `VAR_IN_OUT`；**拒绝**其排序算法，改快排 + 显式栈以沉淀禁递归范式） |
| **合规处置** | EPL-2.0 可商用，但本库仍按 **clean-room** 处理：只借用**行为定义**（「中值是什么」「标准差是 n-1 还是 n」「极差是什么」），接口（`VAR_IN_OUT` 数组 + 返回计数）与实现（环形窗 + 副本排序 + 两遍法）全部独立设计。**未复制任何 OSCAT 源码行**。头注释按「参考 OSCAT 行为定义，独立实现」表述 |

**关键判断（本库与 OSCAT 的分水岭）**：`ADR/SIZEOF` 是 CODESYS 方言，TwinCAT 3 可用但 InoProShop 行为不保证，且本库 R3 红线**明令禁止指针**。所以 OSCAT 的整个数组族在本库**无法照搬**——这不是「不想抄」，是「抄了编不过」。三平台可编译这一条，逼出了本库所有数组接口必须走 `VAR_IN_OUT`，也顺带获得了「参数维度可静态检查」的好处。这条已写入 `ROUND_PLAN_R3.md` §7.8 / §7.10 / §7.13 的溯源说明。

---

## 8 GPL / AGPL 源处置声明

本轮**未使用**任何 GPL / AGPL 源。按 `SOURCE_HUNTING_MATRIX.md` 铁律 2，对下列源维持「**只读思想，不复制任何代码行**」的处置：

| 源 | 典型许可证 | 本轮是否接触 | 处置 |
|---|---|---|---|
| OpenPLC（runtime / editor） | GPL-3.0 | 否 | 若后续参考其 IEC 运行时语义，**只读思想**，不复制代码行，不引入衍生关系 |
| Beremiz（IDE / 运行时） | GPL-2.0-or-later | 否 | 同上 |
| MatIEC（ST→C 编译器） | GPL-3.0 | 否 | 同上；其「ST 语法树」不可作为本库解析器模板 |
| 任意 GitHub `GPL` 标签的 ST 组件 | GPL 各版本 | 否 | 一律只读思路；若思路被采用，实现必须完全重写并在头注释注明「思路参考，非衍生」 |

> 本库以 MIT / Apache-2.0 口径发布，任何 GPL/AGPL 代码进入都会造成许可证传染，属**不可逆错误**。EPL-2.0（OSCAT）虽可商用，本库仍按 clean-room 处理以降低合规审查成本。

---

## 9 合规台账（本轮汇总）

| 来源 | 性质 | 协议 | 商用合规 | 本库取用方式 |
|---|---|---|---|---|
| Siemens LGF（Entry 109479728 页面 + V5.2.1 文档） | 闭源商业库 + 文档 | 免费使用 / 版权保留 | 不可复制代码 | 仅借鉴 **11 组分类、组内粒度、UDT 与参数域形态**；clean-room |
| Siemens LBP（Entry 109749508 文档） | 闭源商业库 + 文档 | 免费使用 / 版权保留 | 不可复制代码 | 仅借鉴 **块清单粒度（8 台/8 路/8 点）、cmd-ind 命令反馈分离思想**；clean-room |
| ISO 13851:2019 / IEC 60204-1 | 公开标准 | 标准文本版权 | 可引用条款含义 | 仅引用 **500 ms / 100 ms / anti-repeat / 上电锁** 等工程约束与条款号，不引用页码 |
| Modbus 应用协议规范（ASCII 模式） | 公开协议 | 规范公开 | 可实现 | 引用 **LRC 定义与两组公开向量** |
| crccalc.com / testbench.tools / tool.io 等 CRC 工具页 | 公开算法目录 | 概念引用 | — | 引用 **参数组合与 check 值**，双源核对 |
| OSCAT Basic / Network | 开源函数库 | **EPL-2.0** | 可商用（需致谢） | 仅借鉴**行为定义**（中值/方差/极差/原地排序语义），接口与实现独立 |
| SpecForge / Chipkin / Otomasyon AVM / Banner / Industrial Monitor Direct 等技术文章 | 技术博客与厂商公开文档 | 概念性参考 | 不涉及代码 | 工程约束、陷阱清单、验证步骤 |

**结论**：本轮 14 个组件全部为**语义借鉴 + 独立重构**，无任何源码级复制；7 条检索记录中 2 条为 T1（OSCAT）、5 条为 T2/T3（LGF、LBP、ISO/IEC 标准、协议规范、算法目录），满足「覆盖 T1 与 T2」要求。**未下载任何闭源库文件，未解包任何 `.zip`/`.ap*`**，因此无需在 `_Staging_Raw` 落原始源码目录（仅落本笔记与规格书）。

**未获取到的信息（如实披露，不编造）**：
1. LGF / LBP 的**具体块内部实现**——闭源，且不应获取；本库也不需要。
2. LGF 文档的具体**页码**——仅取得目录级摘要（章节号可见、页码未逐条核实），故全文以「文档 ID + 章节名」定位。
3. ISO 13851 标准**原文全文**——仅有多个二级来源对同一组条款（§5.2 / §5.3）的一致转述；本库只采用「多源一致」的参数值（500 ms / 100 ms），不引用更细的条款内容。
4. 西门子 LGF V5.5.0 与 V5.2.1 的**差异清单**——与本轮组件无关（本轮只用组结构与参数域，两版一致）。

---

## 10 交给规格书的输入清单（对应 `ROUND_PLAN_R3.md` 决策编号）

1. **500 ms / 100 ms 双窗 + 上电武装锁 + 卡死检测 + 合规披露**（记录 6）→ `FB_DL_TwoHandSafety`（D-R3-06）。
2. **8 台聚合体粒度 + cmd/ind 分离**（记录 3）→ `FB_DL_DutyStandbyRotation`（D-R3-05：不复用 RuntimeMeter）。
3. **8 路互锁 → 本库 16 路**（记录 3 对比记录 1）→ `FB_DL_InterlockMatrix`（D-R3-04：与 16 位报警字同宽）。
4. **公差窗口 + 合理性检查先行**（记录 1 + 记录 3）→ `FB_DL_RedundantSwitch`（D-R3-07：偏差超限默认不猜）。
5. **折点表 = X/Y 双数组 + 点数**（记录 2）→ `FC_DL_MultiPointLinear`。
6. **CRC 参数模型 + check 值 + 反例对照**（记录 4）→ `FC_DL_Crc32Ethernet`（D-R3-09：首版逐位不建表）。
7. **LRC 定义 + 两组公开向量 + 帧边界不含 `':'`/CRLF**（记录 5）→ `FC_DL_LrcChecksum` + `FC_DL_HexStringToBytes`（两步调用）。
8. **FIFO/LIFO 各自成块 + 满/空/长度状态位**（记录 1）→ `FB_DL_LifoStack`。
9. **中值/方差/极差的行为定义**（记录 7）→ `FB_DL_MedianFilter` / `FB_DL_SignalStatistics`（两遍法、n-1、极值每拍重算）。
10. **禁止指针 + 禁止递归 + 显式栈**（记录 7 的 `ADR/SIZEOF` 事实 + 平台差异）→ `FC_DL_QuickSortLReal`（D-R3-01）、全库 `VAR_IN_OUT` 数组约定。

---

*Round 03 ｜ 2026-11-14 ｜ 道莅工控代码库产品总监*
