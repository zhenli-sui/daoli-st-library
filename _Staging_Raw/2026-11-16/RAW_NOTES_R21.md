# RAW NOTES R21 —— 狩猎记录与 clean-room 边界

> 轮次：**R21** ｜ 时间：2026-11-16 20:38 ｜ 编制：道莅工控代码库产品总监
> 检索预算：**2 次 WebSearch / 3 次**（T0 组零检索，仅批 2 的 T2-1 LGF 与 #14/#15 需要核对）
> 结论先行：**本轮零代码行入库**。LGF 是闭源免费库，全部 6 件 T2 关联件只借「分类事实 + 参数域 + 行为定义」，状态机/码位/阈值/判据/错误码 100% 自有。

---

## 1 检索执行记录

| # | 查询语句（原文） | 目的 | 结果可用性 |
|---|---|---|---|
| 1 | `Siemens LGF library "bit logic" functions word bit field extract LWORD "Library of General Functions" TIA Portal` | 核对 LGF 位操作组与位域合并/拆分族的**分类划分与位宽覆盖** | 可用：命中 LGF 位操作 5 件的完整引脚表 + 中文分类索引 |
| 2 | `Siemens LGF "Library of General Functions" data handling checksum CRC functions list TIA Portal` | 核对 LGF 校验族（CRC 7 件）的**参数域**与是否存在累加和族 | 可用：命中 CRC 参数域（initValue/mask/finalXorValue/reflectInput/reflectResult）与 26 分类总表 |

**访问到的公开资料（均为二手索引或官方手册摘录，未下载任何库文件、未取得任何 ST 源码）**：

| 编号 | 类型 | 地址 | 用途 |
|---|---|---|---|
| S1 | 官方手册 PDF 摘录（LGF V4.0.2 EN，TIA V14SP1） | `https://arhiva-2022.loomen.carnet.hr/pluginfile.php/5914957/mod_resource/content/0/109479728_LGF_TIAV14SP1_DOC_V4_0_2_en%20%281%29.pdf` | 资源清单：块名/版本/CPU 资源占用；确认 `LGF_CRC8/16/32`、`LGF_BinaryToGray`、`LGF_DTLtoString`、`LGF_IntToString`、`LGF_TimeToString`、`LGF_Frequency`、`LGF_LimRateOfChangeBasic` 等块**存在于公开资源目录** |
| S2 | 第三方分类索引（26 类 / 148 块） | `https://bbs.plcjs.com/thread-642532-1-55.html` | 26 个功能组的组名与块数分布：位操作 5 / 计时器与脉冲 2 / 日历与时间 7 / 计数器与边沿 6 / 比较 5 / 数学 5 / 范围限值 4 / 随机 6 / 最值搜索 5 / 积分微分 3 / 矩阵 7 / **CRC 7** / 奇偶 2 / 数据处理 6 / 排序 3 / 类型转换 19 / **合并拆分 12** / 字节交换 3 / 字符串 5 / 温度 9 / 信号发生器 8 / 斜率限幅 3 / 统计 7 / 可视化 6 / 系统信息 4 / 文件 2 |
| S3 | 位操作组详解（中文） | `https://bbs.plcjs.com/thread-642624-1-6.html` | `LGF_BitSet/Reset/Toggle/Test/BitSetTo` 五件引脚表：`value : DWORD` / `bitNo : USINT(0-31)` / `Ret_Val` —— **全部 DWORD 口径** |
| S4 | CRC 组详解（中文） | `https://bbs.plcjs.com/thread-643045-1-1.html` | `LGF_CalcCRC16` / `CalcCRC16Advanced` 引脚：`initValue`、`mask`、`finalXorValue`、`reflectInput`、`reflectResult`、`noOfElements`、`array`；`IsParityEven/Odd(DWord)` |
| S5 | 第三方基准数据集说明 | `https://deepwiki.com/cangkui/AutoPLC/4.2-lgf-function-library` | 旁证分类组织（CRC / Matrix / Histogram / FIFO-LIFO / ShiftRegister 等），仅作交叉印证，未采信任何实现细节 |

---

## 2 许可与合规结论（铁律执行）

| 项 | 结论 |
|---|---|
| LGF 许可性质 | **免费使用、非开源**：可免费下载并用于项目，但**不可修改源码后重新发布**（S2 说明页明确区分「开放使用权」与「代码所有权」） |
| 道莅处置口径 | 取**最严口径**：`仅借分类事实 + 参数名域 + 行为定义`；**零代码行、零注释引用、零符号名复制** |
| 具体禁止 | ① 不使用 `LGF_` 前缀与任何 LGF 块名（含派生名如 `BitTestEx`）；② 不复制其 `ENO` 错误处理结构；③ 不复制其块头/版本号表格式；④ 不复制其 `VAR CONSTANT` 常量名（`BINARY_ZERO` / `TRUE_BOOL_BIT` / `MAX_NO_OF_BITS` 一律不用） |
| 本库命名 | 全部走道莅 `FC_DL_` / `FB_DL_` + 语义化驼峰（如 `LwordBitFieldExtract`、`Crc16Generic`） |
| 可商用结论 | 道莅产出物 100% 自有实现，**商用无限制**；无 GPL/AGPL 传染风险（本轮未接触任何开源 ST 源码） |

> 附：检索过程中出现的一处 LGF 源码片段（论坛帖引用了 `LGF_BitTest` 的完整 ST 体：`SHL(IN := TRUE_BOOL_BIT, N := (bitNo MOD MAX_NO_OF_BITS))`）。**已阅但未采用**——本库 `FC_DL_BitGet`（R9 前存量）早已独立实现同语义；该片段仅用于确认「LGF 位操作是 DWORD 口径、位号 MOD 归一」这一**分类事实**，不构成任何实现来源。

---

## 3 提取点与「借 / 不借」判定（逐件对应）

### 3.1 采用的提取点（6 件）

| 组件 | 借什么（分类级/参数级） | 不借什么（自有部分） |
|---|---|---|
| #6 `FC_DL_LwordBitFieldExtract` | **分类事实**：LGF 把「位域合并/拆分」独立成族（12 件），且位宽覆盖 WORD/DWORD → 反证 LWORD 单字位域是**谱系缺口**而非臆造需求 | 参数命名（`startBit/width` 为道莅自定）、掩码构造（宽 64 走 `DL_MASK64_ALL` 常量、规避 `SHL(x,64)`）、截断策略、错误码 `037B~037D`、`bTruncated` 出口 |
| #7 `FC_DL_LwordBitFieldInsert` | 同上（读改写成对） | 四步序（算掩码→清位→取值→合成）、**越界拒写**策略（LGF 无此概念）、`bChanged` 节流出口、码 `037E~0380` |
| #8 `FC_DL_LwordBitCount` | **分类事实**：LGF 计数器与边沿组含 `BitCount`，口径为 DWORD | Kernighan 算法（公开经典）、`WHILE` 守卫、全零信息码 `0442`、64 位域实现 |
| #9 `FC_DL_Crc16Generic` | **参数域**：`initValue / mask(poly) / finalXorValue / reflectInput / reflectResult` 五元组是行业通行参数面 | 逐位算法（零查表零内存）、反射位循环实现、3 组公开校验向量（`BB3D` / `29B1` / `31C3` 自验）、多项式为零闸、帧长超限**拒算**策略、码 `0384~0386` |
| #14 `FC_DL_TimeToHmsString` | **行为定义**：LGF `TimeToString` 证明「时长 → 定宽时间文本」是标准需求形态 | `TIME_TO_DINT` 毫秒口径、负 TIME 带负号统一策略、补零分支实现、小时超 99 提示码 `044F` |
| #15 `FC_DL_DateToIsoString` | **行为定义**：LGF `DTLtoString` 证明「日期时间 → 定宽文本」需求形态 | `civil_from_days`（Howard Hinnant，公有领域）反算、回代自校验闸 `0397`、ISO 10 字符定宽、纪元口径假设挂债声明 |

### 3.2 明确**不立项**的提取点（防下轮重复立项，R85 纪律）

| LGF 功能 | 不立项理由 | 库内落点 |
|---|---|---|
| `IsParityEven` / `IsParityOdd` | 由 `FC_DL_BitCount` 取 `MOD 2` 一行可得，独立成件属**薄包装**（凑数） | `FC_DL_BitCount`（存量，DL_Base） |
| `CountBooleanEdges` | BOOL 沿计数已由 `FB_DL_CtuEx` / `FB_DL_EventCounter` / `FB_DL_BidirectionalCounter` 三重覆盖；本轮只取「**变化次数审计**」的语义做模拟量死区版（#17 `SignalChangeCounter`），LGF 的 BOOL 形态**不复制** | `FB_DL_CtuEx` 等（存量） |
| `SwapBlockWord` / `SwapBlockDWord` / `SwapBlockLWord` | 字节序三档（16/32/64）R20 已齐；「块级搬移」本质是内存块操作，跨平台行为不一致且逼近零厂商依赖红线 | `FC_DL_SwapBytes16/32/64`（存量） |
| `GetCalendarWeek` / `AstroClock` / `IsGermanHoliday` | 已收口（`WeekOfYearCalc` R10 / `SolarPositionCalc` R12）；`IsGermanHoliday` 属地区性业务规则，不入通用库 | 存量三件 |
| `MergeBitsToByte/Word/DWord` | 已由 `FC_DL_PackBitsToWord` / `FC_DL_WordBitPack` / `FC_DL_BitFieldExtract` 覆盖三段位宽 | 存量三件 |
| `LGF_FileRead/FileWrite` | 需文件系统访问，**违反零厂商依赖红线**（与 R12 对 `SysFile` 的裁定同一律） | 不立 |
| `MatrixAdd/Multiply/Transpose`、`Histogram`、`Boxplot`、`RegressionLine` | PLC 侧无稳定工程用例（矩阵乘 R13 已判「不立并写入偏离段」）；可视化类属 HMI 职责 | R13 偏离段留档 |
| `LGF_Ramp` / `LimRateOfChange` / `NonLin` | 已由 `FB_DL_RampGenerator` / `FB_DL_RateLimiter` / `FB_DL_RampSoakProfile` 覆盖 | 存量三件 |
| `LGF_Frequency` | 与 `FB_DL_PulseGenerator`（占空比方波）+ #18 `FB_DL_SamplingTrigger`（采样节拍）职责重叠，无独立语义增量；如后续出现「变频输出频率给定」真实用例再评估 | 存量 + 本轮 #18 |

---

## 4 对源矩阵的记账建议（供收口阶段回写，本阶段不动矩阵）

- **T2-1 LGF · Bit Logic**：状态维持 `◐`（本轮深化 LWORD 单字层 3 件：#6/#7/#8），备注加「LWORD 单字位域读/写/汉明重 R21 收口；DWORD/LWORD 数组批量位段与多段一次搬仍待挖」。
- **T2-1 LGF · Data Handling**：状态维持 `◐`，备注加「校验族 R21 补 CRC-16 参数化（#9）+ 8 位累加和（#10）；**明确不立 `LWORD 累加和`**（无公开协议用例，属过度设计，理由见本文件 §3.2）」。
- **T2-1 LGF · Converter**：状态维持 `◐`，备注加「定宽文本族 R21 补时长（#14）与日期（#15）两件；`IntToString` 对应件 `DintToStringTrim` R20 已落，`StringToDTL` 仍待挖（挂编译债）」。
- **T0-1 / T0-2 / T0-4 / T0-5 / T0-6**：本轮属变体线深化（#1~#5、#11~#13、#16~#20 共 12 件），按 M-E5 裁定**只回写备注，状态列不改 ✔**（零检索变体件不构成「源收口」）。
- **T2-8 ISA-88 / NE107**：`FB_DL_SignalFrozenDetect`（#19）为 `eCheckFunction` 判据原子，作为**次源**记 T2-8 行备注，主源记 T0-1 行，**不重复记账**。

---

## 5 下轮狩猎提示（R22 用，不占本轮）

1. **T1-3 OSCAT Network** 仍余「RTU 帧长度/字节数一致性校验」「ASCII 帧 LRC 定位」两条（T1 源，ST 原生，可检索确认行为定义）。
2. **T1-7 PLCnext** 仍余 PROFINET 诊断（`PN_ALARM_DIAG` 语义）族；注意 R10 的 Q5 证伪教训（PDI ≠ 质量码），立项前先查证。
3. **T2-1 LGF** 建议下轮做「多段一次搬」（`BitArrayMultiInsert`，接 R12/R13 批量层）与「`StringToDTL`」（须先闭合编译债，否则只能挂账）。
4. **源已无 ☐ 可开**——后续所有轮次都必须按「◐ 深化」记账，矩阵状态列不得出现新的 ✔（除非整组挖尽并给出「不再挖」的理由段）。

---

*RAW_NOTES_R21 ｜ 2026-11-16 20:38 ｜ 2 次检索 / 零代码行入库 / 6 件 T2 关联件全 clean-room*
