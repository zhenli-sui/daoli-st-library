# ROUND PLAN — Round 10（R10）

> 日期：2026-11-15 ｜ 轮次类型：Phase 1 第十轮批处理（Level 0 数学/日历/计数回补 + **T1-7 PLCnext Community 开组** + 工艺物理量链 + 工站模板）
> 本轮目标：**16 件**（完成后今日累计 126 / 200）｜ 库规模：136 → 152 ｜ 总库版本：v1.8.0 → v1.9.0（入库后）
> 执行人：道莅工控代码库产品总监（Daoli Library Director）· 兜底模式
> 规范依据：`daoli-st-standard` SKILL.md + references 三件（编码红线 / 目录契约 / 文档模板）+ templates 三骨架
> 前置阅读：`INDEX_REGISTRY.json`（v1.8.0）、`ROADMAP.md`、`SOURCE_HUNTING_MATRIX.md`（v1.0）、`AGENT_EVOLUTION_LOG.md` 规则库 R1~R30

---

## 〇、阶段一盘点结论（以实际文件为准，非记忆）

### 0.1 总库与今日进度

| 检查项 | 实测结论 |
|---|---|
| `INDEX_REGISTRY.json` | `total_components = 136`，`version = 1.8.0`，`last_updated = 2026-11-15T13:52+08:00` |
| 子库分布（registry） | DL_Base **29** ｜ DL_MathData **26** ｜ DL_Algo **20** ｜ DL_Device **32** ｜ DL_Motion **14** ｜ DL_Process **15** = **136** |
| 物理文件核对 | `glob DL_*/**/*.st` = **136** 个，与 registry 1:1 一致（无孤儿文件、无空登记） |
| 今日入库（`registered_at` = 2026-11-15） | **110 件**（R3 14 + R4 16 + R5 16 + R6 16 + R7 16 + R8 16 + R9 16） |
| 历史入库（2026-11-14） | 26 件（R1 12 + R2 14） |
| 今日目标对照 | **110 / 200 = 55.0%**，缺口 **90 件** |
| 总库目标对照 | **136 / 10000 = 1.36%** |
| 语料同步 | `_AI_Training_Dataset\daoli_st_synth_dataset.jsonl` 侧 136 条（与 registry 136、文件 136 三方一致；R10 入库后需同步到 152） |

### 0.2 源矩阵挖掘覆盖率（按 registry `function_tags` 实测计数）

| 源组 | 标签 | 已出件数 | 状态（矩阵第 5 节） |
|---|---|---|---|
| T2-1 LGF · Math | `lgf-math` | 6 | ◐ |
| T2-1 LGF · Technology | `lgf-technology` | 10 | ◐ |
| T2-1 LGF · Data Handling | `lgf-datahandling` | 5 | ◐ |
| T2-1 LGF · Measurement | `lgf-measurement` | 5 | ◐（R8 已裁定并入 Math 记账） |
| T2-1 LGF · Date and Timer | `lgf-datetime` | 5 | ◐ |
| T2-1 LGF · Converter | `lgf-converter` | 4 | ◐ |
| T2-1 LGF · Signal Generators | `lgf-signalgen` | 4 | ◐ |
| T2-1 LGF · Comparator | `lgf-comparator` | 3 | ◐ |
| T2-1 LGF · Counter | `lgf-counter` | 3 | ◐ |
| T2-1 LGF · Bit Logic | `lgf-bitlogic` | 2 | ◐（最浅） |
| T2-2 LBP 基础工艺 | `lbp-*` | 16 + 12 | ◐（V2.8 实测 23 块） |
| T2-4 S7-1500 Motion | `s7-motion` | 7 | ◐ |
| T2-5 Mod_PID_Control | `mod-pid-control` | 5 | ◐（参数域已取尽） |
| T2-6 Rockwell AOI | `rockwell-aoi` | **0** | **☐ 未开组** |
| T2-7 PackML / OMAC | `packml-*` | 2 + 2 + 1 + 2 | ◐ |
| T2-8 ISA-88 / ISA-18.2 / NE107 | `isa-*` / `namur-ne43` | 4 + 3 | ◐ |
| T1-1 OSCAT Basic | `oscat-basic` | 8 | ◐ |
| T1-2 OSCAT Building | `oscat-building` | 3 | ◐（AIR_DENSITY 族未挖） |
| T1-3 OSCAT Network | `oscat-network` | 2 | ◐ |
| T1-4 CODESYS Forge | `codesys-forge*` | 2 | ◐ |
| T1-5 TcOpen | `tcopen*` | 13 | ◐ |
| T1-6 PLCopen Motion | `plcopen*` | 12 + 2 + 1 | ◐ |
| **T1-7 PLCnext Community** | `plcnext-community` | **0** | **☐ 未开组（本轮开组）** |
| T1-8 GitHub topics | `stepper` 线 | 2 | ◐ |

> **本轮挖掘方向判定**：①「LGF 三组最浅」＝ Bit Logic（2 件）/ Counter（3 件）/ Math（6 件但仍有 min-max 索引、N 次根、阶乘三个官方函数未落）；②「两个 ☐ 未开组」＝ T1-7 PLCnext + T2-6 Rockwell AOI；③「OSCAT Building 物理量族缺口」＝ AIR_DENSITY；④「ROADMAP 未注册项」＝ `I_DL_RfidReader` / `FB_DL_RfidTagHandler` / `FB_DL_WindingTraverse` / `FB_DL_PickAndPlaceStation`。四条线正好构成 R10 的 16 件。

### 0.3 锁定本轮的 16 个目标组件（逐名对 registry 及全库文件名双向查重 = 0 命中）

| # | 组件 | 类型 | 子库 | 来源组标签 | 立项依据 |
|---|---|---|---|---|---|
| 1 | `FC_DL_BitFieldExtract` | FC | DL_Base | `lgf-bitlogic` | LGF Bit Logic 组最浅（2 件）；与已入库 `FC_DL_WordBitPack`（打包）配成「打包-提取」对 |
| 2 | `FC_DL_WeekOfYearCalc` | FC | DL_Base | `lgf-datetime` | 矩阵「周窗/年窗待挖」；与 `FC_DL_DayOfWeekCalc` 同族不同量（周序号 vs 星期） |
| 3 | `FB_DL_BidirectionalCounter` | FB | DL_Base | `lgf-counter` | 矩阵明写「双向预设计数（CTUD 全语义）族待挖」 |
| 4 | `FC_DL_SearchMinMax` | FC | DL_MathData | `lgf-math` | LGF V5.5 官方 4 个 `SearchMinMax*` 变体（LReal/DInt/UDInt/通用）参数域未挖 |
| 5 | `FC_DL_NthRoot` | FC | DL_MathData | `lgf-math` | LGF `LGF_NthRoot` 官方函数；标准库只有 SQRT |
| 6 | `FC_DL_FactorialSat` | FC | DL_MathData | `lgf-math` | LGF `LGF_GetFactorial`（域 0~12、超域报错）语义 |
| 7 | `FB_DL_SineGenerator` | FB | DL_Algo | `lgf-signalgen` | 矩阵「正弦/锯齿/频率发生族待挖」 |
| 8 | `FB_DL_SawtoothGenerator` | FB | DL_Algo | `lgf-signalgen` | 同上（同族第二件，禁 MODE 巨无霸 → 拆两块） |
| 9 | `FC_DL_CoilDiameterCalc` | FC | DL_Algo | `lgf-technology` | 矩阵「卷径/张力族待挖」；ROADMAP 多条卷绕类待办的前置件 |
| 10 | `FC_DL_AirDensity` | FC | DL_Algo | `oscat-building` | 矩阵明写「AIR_DENSITY / DEW_TEMP / WATER_ENTHALPY 族待挖」 |
| 11 | `I_DL_RfidReader` | I | DL_Device | `tcopen-component` + `rockwell-aoi` | ROADMAP 未注册项（§4）；T2-6 Rockwell AOI **开组**（参数分段范式） |
| 12 | `FB_DL_RfidTagHandler` | FB | DL_Device | `tcopen-component` + `rockwell-aoi` | 同族实现件（契约-实现对） |
| 13 | `FB_DL_AxiolineDiagLatch` | FB | DL_Device | `plcnext-community` | **T1-7 开组**（Axioline 本地总线诊断状态寄存器位域 + 参数寄存器） |
| 14 | `FB_DL_PdiReadScheduler` | FB | DL_Device | `plcnext-community` | **T1-7 开组**（PDI 无环读取调度：Slot/Subslot/Index/Subindex + ErrorCode/AddInfo） |
| 15 | `FB_DL_WindingTraverse` | FB | DL_Motion | `lgf-technology` + `s7-motion` | ROADMAP 未注册项（§7.1 卷径实时估算与横动排线） |
| 16 | `FB_DL_PickAndPlaceStation` | FB | DL_Process | `packml-omac` + `tcopen-component` | ROADMAP 未注册项（§6 P0 待办：拾放工站模板） |

**目录分布**：DL_Base 3 ｜ DL_MathData 3 ｜ DL_Algo 4 ｜ DL_Device 4 ｜ DL_Motion 1 ｜ DL_Process 1 = **16**。

### 0.4 配额自检（矩阵第 4 节硬性要求）

- **T2 非 ST 借鉴源 ≥ 1 组件族**：LGF Bit Logic（#1）/ Date and Timer（#2）/ Counter（#3）/ Math（#4~#6）/ Signal Generators（#7~#8）/ Technology（#9、#15）+ **T2-6 Rockwell AOI 首次开组**（#11~#12）→ **满足，且 6 组均为 ◐ 深化 + 1 组 ☐ 开组**。
- **T1 ST 原生源 ≥ 1 组件族**：**T1-7 PLCnext Community 首次开组**（#13~#14）+ T1-2 OSCAT Building 深化（#10）+ T1-5 TcOpen 深化（#11~#12）→ **满足**。
- **禁止重复挖掘同一组**：本次涉及的 6 个 LGF 组均为「横向扩族」，每件与同组已入库件的**职责边界在规格内逐条写死**（见各件「与既有件边界」小节）；未触碰任何已收口组 → **满足**。
- **矩阵扩产 5 规则**：本轮使用「①数据类型重载」0 次（避免与 R9 已收口的重载族再撞）、「②阶数变体」1 次（#8 锯齿/三角对称度）、「③协议方言」0 次、「④行业工况」1 次（#16 拾放工站为通用模板）、「⑤精度变体」1 次（#4 提供 LREAL 双出口：值 + 索引）。**重申：本轮无任何组件以 `MODE`/`eMode` 参数把多变体塞进单块**（八条红线第 8 条 + 矩阵第 3 节禁令）。

### 0.5 历史范式带入（编码者必须遵守，终审逐条核）

| 规则 | 本轮落点 |
|---|---|
| **R19** 首扫标志唯一合法范式 | #7 #8 #13 #14 #15 #16（含初始化/跟踪的块：`bInit` 初值 FALSE，判据 `NOT bInit`） |
| **R21** 信息级码不得置 `bError` | #3 #7 #8 #11~#16（信息级 `01xx` 只进 `uErrorId` 与趋势，不升级报警） |
| **R24 / R25** 单拍标志生命周期三律 | #3（计数脉冲）、#12（应答单拍）、#14（轮询启动单拍）、#16（步完成单拍）——预清零、实例调用后自清、消费拍与转出拍分离 |
| **R26** 禁孤立分号 | 全 16 件（CASE 终端态一律纯注释占位） |
| **R27** 输出保持语义 | #12（读到标签保持）、#13（诊断锁存）、#16（工站结论位保持）——保持态内每拍重写 |
| **R28** 注释不可嵌套 | 全 16 件（头注释「调用示例」块内只写 `//`） |
| **R29** 赋值目标声明性检查 | 全 16 件（编码后脚本比对，禁「未声明即赋值」） |
| **R30** 码位自证循环禁令 | 本节 0.6 码位表已对全库 136 件 `.st` 求差（脚本核对，非自报） |
| **R22** 接口 OUT 列 = 只读 PROPERTY | #11 `I_DL_RfidReader` + #12 实现块（`FB_DL_RfidTagHandler` 的接口成员一律 `PROPERTY GET`） |
| **R23** 纯事件型组件不设首扫 | #3（计数为事件型但含装载/饱和状态 → 仍需 `bInit` 初始化装载态，规格已定） |

### 0.6 码位占用核对（脚本对全库 136 件 `.st` 求差，重叠 = 0）

**段位公约（沿用 R5 公约 0.7）**：`16#00SS_XXXX`，`SS` = 01 基础/数学（DL_Base + DL_MathData）、02 算法（DL_Algo）、03 设备（DL_Device）、04 运动（DL_Motion）、05 工艺（DL_Process）；`XXXX` 首位 `0` = 信息级、首位 `1`/`2` = 分组件序号段。

| # | 组件 | 已占用（全库实测） | **R10 新分配（空闲块）** |
|---|---|---|---|
| 1 | `FC_DL_BitFieldExtract` | `0001` 段信息级最大 `0112`（ToleranceWindow） | `16#0001_0113` / `0114` / `0115` |
| 2 | `FC_DL_WeekOfYearCalc` | 同上 | `16#0001_0116` / `0117` |
| 3 | `FB_DL_BidirectionalCounter` | `0001` 段故障级最大 `0214`（LimitClassify） | `16#0001_0118`（信息）/ `0215`、`0216`（故障） |
| 4 | `FC_DL_SearchMinMax` | 同上 | `16#0001_0119` / `011A` / `0217` |
| 5 | `FC_DL_NthRoot` | 同上 | `16#0001_011B` / `011C` |
| 6 | `FC_DL_FactorialSat` | 同上 | `16#0001_011D` |
| 7 | `FB_DL_SineGenerator` | `0002` 段组件序号已用 `01`~`1A` | `16#0002_1B01`~`1B04`（信息）/ `1B10`、`1B11`（故障） |
| 8 | `FB_DL_SawtoothGenerator` | 同上 | `16#0002_1C01`~`1C03` / `1C10` |
| 9 | `FC_DL_CoilDiameterCalc` | 同上 | `16#0002_1D01`~`1D03` / `1D10` |
| 10 | `FC_DL_AirDensity` | 同上 | `16#0002_1E01`~`1E03` / `1E10` |
| 11 | `I_DL_RfidReader` | 接口不带码（本库接口公约） | **无码位**（失败经方法返回 `ST_DL_RfidResult` + 实现块 `uErrorId`） |
| 12 | `FB_DL_RfidTagHandler` | `0003` 段信息级最大 `0137`（PulseDirStepper），故障级 `02E4` 后空闲 | `16#0003_0138`~`013A` / `02F0`~`02F3` |
| 13 | `FB_DL_AxiolineDiagLatch` | 同上 | `16#0003_013B`、`013C` / `02F4`~`02F6` |
| 14 | `FB_DL_PdiReadScheduler` | 同上 | `16#0003_013D`~`013F` / `02F7`~`02F9` |
| 15 | `FB_DL_WindingTraverse` | `0004` 段信息级最大 `01A3`，故障级最大 `02B2` | `16#0004_01B0`~`01B3` / `02C0`~`02C3` |
| 16 | `FB_DL_PickAndPlaceStation` | `0005` 段信息级最大 `01A1`，故障级最大 `02A1` | `16#0005_01B0`~`01B4` / `02B0`~`02B5` |

> **编码者铁律（R30）**：以上分配为总监对全库求差后的裁定值，**不允许**再自行「就近取号」；若实现中发现某码位语义需拆细，只能在**本组件已分配的块内**增加尾号（如 `0113`→`0113`、`0119`、`011F` 不得跨到他人块），跨块即视为串台缺陷。

---

## 〇.7 泳道分配（3 条泳道 + 1 条串行族内链，禁止跨泳道依赖本轮新组件）

| 泳道 | 组件 | 依赖约束 |
|---|---|---|
| **A · Level 0 原子回补（6 件）** | ①`FC_DL_BitFieldExtract` ②`FC_DL_WeekOfYearCalc` ③`FB_DL_BidirectionalCounter` ④`FC_DL_SearchMinMax` ⑤`FC_DL_NthRoot` ⑥`FC_DL_FactorialSat` | 仅 `Standard.library`；**零互相依赖**（②不得调用①，④不得调用⑤）。A 泳道最先落盘 |
| **B · 算法/物理量链（4 件）** | ⑦`FB_DL_SineGenerator` ⑧`FB_DL_SawtoothGenerator` ⑨`FC_DL_CoilDiameterCalc` ⑩`FC_DL_AirDensity` | 仅 `Standard.library` + 已入库 `FC_DL_HumidAirEnthalpy` 的**常量口径复用**（⑩ 允许在注释中声明同源公式链，**禁止调用**该 FC，各自内联 Magnus-Tetens） |
| **C · 设备/运动/工艺（6 件）** | ⑪`I_DL_RfidReader` → ⑫`FB_DL_RfidTagHandler`（族内串行）｜ ⑬`FB_DL_AxiolineDiagLatch` ⑭`FB_DL_PdiReadScheduler` ⑮`FB_DL_WindingTraverse` ⑯`FB_DL_PickAndPlaceStation` | ⑫ 依赖 ⑪（同族契约-实现，唯一允许的族内串行）；⑮ 的卷径**由引脚注入**，不得调用 ⑨（跨泳道禁令）；⑯ 依赖已入库 `I_DL_MotionAxis` / `I_DL_VacuumGenerator`，**不依赖** ⑮ |

**硬性禁令**：C 泳道块禁止引用 A/B 泳道本轮新件；若必须引用，回退改设计并在「规格偏离登记」中记明，禁止带病落盘（R11）。

### 0.8 行数配额口径

FB 380~560 行 / FC 200~340 行 / 接口 150~220 行（`wc -l` 含头注释与故障码表）。本轮预估合计 **6,180 行**（A 1,880 / B 1,760 / C 2,540）。

---

## 一、组件规格（16 件）

> **通用要求（对 16 件全部生效，各件正文不再重复）**
> 1. 头注释块七项齐全（名称/子库/版本 1.0.0/兼容性/功能/开源溯源/修订历史），溯源措辞统一为「参考 XXX 公开手册的**功能分类与参数域**，只借分类/参数域/命名，clean-room 实现，不构成衍生作品」。
> 2. 全文严禁出现被禁记号字面（机检按全文命中 = 0 口径）：全局变量表记号、外部变量声明记号、绝对物理地址记号。外部数据一律经引脚 / `VAR_IN_OUT` / 接口注入。
> 3. 100% 中文注释；声明区每变量、每枚举项同行注释，含物理意义、工程单位、取值范围、默认行为。
> 4. 状态机 `ENUM` + `CASE` + `ELSE` 兜底；`TON`/`TOF`/`TP`/`R_TRIG`/`F_TRIG` 在主周期无条件刷新；浮点禁判等（`ABS(a-b) < 容差`）；除法防零；数组访问先判边界；`WHILE` 带防死锁计数器。
> 5. 阈值/限幅/超时/重试一律 `VAR CONSTANT` 或引脚，禁魔法数；故障统一 `uErrorId` 输出，故障码表写入文件头注释块（含信息级/故障级标注，R21）。
> 6. 枚举 `TYPE` 随主 POU 同文件声明（库内既有惯例），前缀 `E_DL_`；结构体前缀 `ST_DL_`，随宿主 POU 同文件发布（公约 0.18）。
> 7. 每个 POU 以 `END_FUNCTION` / `END_FUNCTION_BLOCK` / `END_INTERFACE` / `END_TYPE` 成对终结（R18）。
> 8. 注释区禁嵌套同种定界符（R28）：头注释内的「调用示例」一律 `//` 行注释。

---

### 1. `FC_DL_BitFieldExtract` —— DWORD 位段提取（偏移 + 宽度 → 右对齐值）

- 子库：**DL_Base** ｜ 类型：**FC**（纯函数） ｜ 预计行数：**240** ｜ 来源组标签：`lgf-bitlogic`、`bit-manipulation`、`pure-function`
- 功能描述：从 32 位源字中按「位偏移 + 位宽」提取位段并右对齐输出，是已入库 `FC_DL_WordBitPack`（多位段打包进 WORD）的**逆运算件**。用于通信状态字拆字段、编码器状态位、驱动器状态字（Statusword）位段解析等高频场景。
- **与既有件边界（写死，禁止重复实现）**：`FC_DL_BitGet` 取**单**位；`FB_DL_UnpackWordToBits` 把 WORD 拆成 **16 个固定位**；本件取**任意宽度位段**（宽度 1~32、可跨半字节），三者职责互斥。

**引脚规格**

```iecst
FUNCTION FC_DL_BitFieldExtract : BOOL
VAR_INPUT
    uSource   : DWORD;              // 源字 [位串]，任意 32 位值，不做符号解释
    nOffset   : INT := 0;           // 位段起始位偏移 [bit]，有效域 0~31，LSB = 0
    nWidth    : INT := 1;           // 位段宽度 [bit]，有效域 1~32
END_VAR
VAR_OUTPUT
    uField    : DWORD;              // 提取结果，右对齐（bit0 起连续 nWidth 位有效）
    uMask     : DWORD;              // 本次实际生效掩码（已右对齐），便于调用方直接做位与判断
    nActualW  : INT;                // 实际生效宽度 [bit]（越界截断后的值，1~32）
    uErrorId  : UDINT;              // 事件码，0 = 无事件；信息级 16#0001_01xx 不置 bValid = FALSE
    bValid    : BOOL;               // 入参域全部合法 = TRUE；越界截断 = FALSE（结果仍可用）
END_VAR
VAR CONSTANT
    DL_BIT_MAX      : INT  := 32;   // 字长上限 [bit]（DWORD）
    DL_BIT_MIN      : INT  := 1;    // 最小可提取宽度 [bit]
    DL_MASK_ALL     : DWORD := 16#FFFF_FFFF;  // 全 1 掩码
END_VAR
```

**算法要点**
1. 先判 `nOffset < 0 OR nOffset >= DL_BIT_MAX` → `uErrorId := 16#0001_0113`，`uField := 0`，`uMask := 0`，`bValid := FALSE`，`RETURN FALSE`。
2. 再判 `nWidth < DL_BIT_MIN OR nWidth > DL_BIT_MAX` → `uErrorId := 16#0001_0114`，同上早退。
3. 跨字截断：若 `nOffset + nWidth > DL_BIT_MAX` → `nActualW := DL_BIT_MAX - nOffset`，置 `uErrorId := 16#0001_0115`（信息级），`bValid := FALSE`，**继续按截断宽度计算**（不返回 0，保证现场仍能读到低位可用段）。
4. 掩码构造：`nActualW = 32` 时 `uMask := DL_MASK_ALL`（**禁止** `SHL(1, 32)`——32 位左移 32 位在部分编译器为未定义行为，属可移植性陷阱，R20 口径）；否则 `uMask := SHL(DWORD#1, nActualW) - 1`。
5. 提取：`uField := SHR(uSource, nOffset) AND uMask`（先右移后掩码，次序不得颠倒）。
6. 纯函数语义：无 `VAR` 内部状态、无跨周期残留；同一入参组合在任何周期返回同一结果（可重入）。

**码位表**：`16#0001_0113` 位偏移越界（信息级，结果 0）｜`16#0001_0114` 位宽越界（信息级，结果 0）｜`16#0001_0115` 跨字截断（信息级，结果按可用位有效）。

**验收要点**
- 向量 V1：`uSource = 16#DEAD_BEEF, nOffset = 8, nWidth = 8` → `uField = 16#BE`、`uMask = 16#FF`、`bValid = TRUE`。
- 向量 V2：`nOffset = 31, nWidth = 4` → `nActualW = 1`、`uField = (16#DEADBEEF SHR 31) AND 1 = 1`、`uErrorId = 16#0001_0115`、`bValid = FALSE`。
- 向量 V3：`nOffset = 0, nWidth = 32` → `uField = uSource`、`uMask = 16#FFFF_FFFF`（验证 32 位特例分支，禁止走到 SHL 溢出路径）。
- 向量 V4：`nOffset = -1` → 早退，`uField = 0`、`bValid = FALSE`、码 `0113`。
- 机检：全文无被禁记号；`SHL` 调用点必须被 `IF nActualW < DL_BIT_MAX` 包裹（人工目检项）。

---

### 2. `FC_DL_WeekOfYearCalc` —— ISO-8601 周序号计算（年/月/日 → 年 + 周号 + 周内日）

- 子库：**DL_Base** ｜ 类型：**FC**（纯函数） ｜ 预计行数：**300** ｜ 来源组标签：`lgf-datetime`、`pure-function`、`calendar`
- 功能描述：给定公历年月日，按 **ISO-8601** 规则计算「ISO 周年 + ISO 周序号（1~53）+ 周内日（周一 = 1）」。用于周排产、周窗判定（`FB_DL_TimeWindowCheck` 的周粒度上位判据）、周报表闸门。
- **与既有件边界**：`FC_DL_DayOfWeekCalc` 给**星期几**；本件给**周序号 + ISO 周年**（跨年归属，12 月 31 日可能属次年第 1 周，1 月 1 日可能属上年第 52/53 周——这正是 LGF 日历组「周数计算」的独立价值）。`FB_DL_MonthWindowCheck` 是月窗判定块，不重叠。

**引脚规格**

```iecst
FUNCTION FC_DL_WeekOfYearCalc : BOOL
VAR_INPUT
    nYear   : INT := 2026;          // 公历年 [年]，有效域 1970~2099（受 INT 与算法域约束）
    nMonth  : INT := 1;             // 公历月 [月]，有效域 1~12
    nDay    : INT := 1;             // 公历日 [日]，有效域 1~该月天数
END_VAR
VAR_OUTPUT
    nIsoYear  : INT;                // ISO 周年 [年]（可能 ≠ nYear，跨年归属所致）
    nIsoWeek  : INT;                // ISO 周序号 [周]，1~53
    nIsoDow   : INT;                // ISO 周内日 [1~7]，周一 = 1，周日 = 7
    nWeek53En : BOOL;               // 该 ISO 周年是否含第 53 周（长年判据，便于排程预判）
    uErrorId  : UDINT;              // 事件码，0 = 无事件
END_VAR
VAR CONSTANT
    DL_YEAR_MIN   : INT := 1970;    // 可算年下限 [年]
    DL_YEAR_MAX   : INT := 2099;    // 可算年上限 [年]
    DL_WEEK_DAYS  : INT := 7;       // 每周天数 [日]
    DL_ISO_SHIFT  : INT := 3;       // ISO 周偏移（周四归属法）[日]
END_VAR
```

**算法要点（周四归属法，clean-room）**
1. 入参域校验：年越界 → `16#0001_0116`；月越界或日越界（含闰年 2 月判定 `(y MOD 4 = 0 AND y MOD 100 <> 0) OR y MOD 400 = 0`）→ `16#0001_0117`；任一不合法 → 输出全 0、`RETURN FALSE`。
2. 计算当日「年内序日」`nDoy`（1 起），并计算当日 ISO 周内日：复用**纯整数公式**（不调用 `FC_DL_DayOfWeekCalc`，泳道 A 零互相依赖）——`nDow0 := (nDoy + 5 + y + y/4 - y/100 + y/400) MOD 7`（0 = 周日）；`nIsoDow := nDow0 = 0 ? 7 : nDow0`。
3. 归属判定（周四法）：`nThursdayDoy := nDoy + (4 - nIsoDow)`；若 `nThursdayDoy < 1` → 属上一年，`nIsoYear := nYear - 1`，`nIsoWeek := 该年最后一周号`；若 `nThursdayDoy > 该年天数` → 属次年，`nIsoYear := nYear + 1`，`nIsoWeek := 1`；否则 `nIsoYear := nYear`，`nIsoWeek := (nThursdayDoy - 1) / DL_WEEK_DAYS + 1`（整数除）。
4. `nWeek53En`：该 ISO 周年满足「1 月 1 日为周四」或「闰年且 1 月 1 日为周三」→ 含第 53 周。
5. 全程整数运算，**零浮点、零除法风险**（除数恒为 7 / 4 / 100 / 400 常量）；`INT` 中间量在 1970~2099 域内不溢出（最大 `nDoy + y + y/4 ≈ 366 + 2099 + 524 = 2989 < 32767`）。

**码位表**：`16#0001_0116` 年越界（信息级，输出 0）｜`16#0001_0117` 月/日非法（信息级，输出 0）。

**验收要点**
- V1：`2026-01-01` → ISO 周年 2026、周 **1**、周内日 **4**（周四）。
- V2：`2021-01-01` → 属 **2020** 年第 **53** 周、周内日 **5**（经典跨年例，必须命中）。
- V3：`2027-01-01` → 属 **2026** 年第 **53** 周（2026 年 12 月 31 日为周四 → 2026 是长年）→ `nWeek53En(2026) = TRUE` 自洽性检查。
- V4：`2026-02-29` → 非法（2026 非闰年）→ 码 `0117`、`RETURN FALSE`；`2024-02-29` → 合法。
- V5：`2026-11-15` → 周日 → ISO 周内日 **7**，周号与当日所在周一致（用日历反查确认）。
- 机检：整数除法运算符仅出现在「除以常量 7/4/100/400」处；无 `REAL`/`LREAL`。

---

### 3. `FB_DL_BidirectionalCounter` —— CTUD 全语义双向预设计数器

- 子库：**DL_Base** ｜ 类型：**FB** ｜ 预计行数：**420** ｜ 来源组标签：`lgf-counter`、`state-machine`、`edge-detection`
- 功能描述：上/下双向计数（CU/CD 双沿入口），带装载（Load）、复位（Reset）、上下预设（PV_UP / PV_DN）与双向到预设输出（QU / QD），支持饱和不回绕与「倒置冻结」保护。对应 IEC 61131-3 标准 `CTUD` 语义的超集（标准 CTUD 只有单一 PV）。
- **与既有件边界（四件套职责互斥，必须写进头注释）**：`FB_DL_EventCounter` = 通用事件累加（单向、无预设）；`FB_DL_ModuloCounter` = 取模回绕工位索引；`FB_DL_PresetCounterSat` = **单向**上下限双预设饱和；**本件 = 双向（CU + CD）+ 双向独立预设 + 方向仲裁**。四者不可互相替代。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_BidirectionalCounter
VAR_INPUT
    bCountUp   : BOOL;                  // 加计数输入，上升沿 +1（主周期无条件取沿）
    bCountDown : BOOL;                  // 减计数输入，上升沿 -1（与 bCountUp 同拍时按「加优先」）
    bLoad      : BOOL;                  // 装载请求，电平优先于计数（装载拍不计数）
    nLoadValue : DINT := 0;             // 装载值 [计数值]，域 DL_COUNT_MIN~DL_COUNT_MAX
    bReset     : BOOL;                  // 复位请求，电平有效：CV 归 0、QU/QD 清零、锁存解除
    nPresetUp  : DINT := 100;           // 加预设值 PV_UP [计数值]，CV >= PV_UP 时 QU = TRUE
    nPresetDn  : DINT := 0;             // 减预设值 PV_DN [计数值]，CV <= PV_DN 时 QD = TRUE
    bEnable    : BOOL := TRUE;          // 使能；FALSE 时冻结计数并清 QU/QD（CV 保持）
END_VAR
VAR_OUTPUT
    nCv        : DINT;                  // 当前计数值 CV [计数值]
    bQu        : BOOL;                  // 加预设到达（保持型，CV >= PV_UP 期间持续为真，R27）
    bQd        : BOOL;                  // 减预设到达（保持型，CV <= PV_DN 期间持续为真，R27）
    bAtMax     : BOOL;                  // 已达上限饱和（CV = DL_COUNT_MAX，再 +1 被拒）
    bAtMin     : BOOL;                  // 已达下限饱和（CV = DL_COUNT_MIN，再 -1 被拒）
    bUpPulse   : BOOL;                  // 本次实际加计数成功，单拍脉冲（R25 律①：主体前部预清零）
    bDnPulse   : BOOL;                  // 本次实际减计数成功，单拍脉冲
    bLoadDone  : BOOL;                  // 装载完成，单拍脉冲
    uErrorId   : UDINT;                 // 事件码，0 = 无事件
    bError     : BOOL;                  // 故障锁存（仅故障级 16#0001_02xx 置位，R21）
END_VAR
VAR
    fbTrigUp   : R_TRIG;                // 加计数边沿
    fbTrigDown : R_TRIG;                // 减计数边沿
    fbTrigLoad : R_TRIG;                // 装载边沿
    bInit      : BOOL := FALSE;         // 首扫标志（R19：初值 FALSE，判据 NOT bInit）
    nCvInt     : DINT := 0;             // 内部计数值（对外经 nCv 输出）
    bPresetBad : BOOL;                  // 预设倒置锁存（PV_UP <= PV_DN 为倒置）
END_VAR
VAR CONSTANT
    DL_COUNT_MAX : DINT := 2147483000;  // 计数上限（留安全裕度，防 +1 溢出）
    DL_COUNT_MIN : DINT := -2147483000; // 计数下限
END_VAR
```

**状态机**：无多态主状态机（计数型），但**必须**保留 `bInit` 首扫逻辑（R19）：首扫将 `nCvInt` 置 0、清 `bPresetBad`、`uErrorId := 0`；此后每拍按固定次序执行——

1. **单拍输出预清零**（R25 律①）：`bUpPulse/bDnPulse/bLoadDone := FALSE`。
2. **边沿无条件刷新**（红线第 5 条）：`fbTrigUp(CLK := bCountUp); fbTrigDown(CLK := bCountDown); fbTrigLoad(CLK := bLoad);`
3. **预设域校验（每拍重算）**：`bPresetBad := (nPresetUp <= nPresetDn)`；若为真 → 锁存 `bError := TRUE`、`uErrorId := 16#0001_0215`（故障级）；**计数仍按原值继续**（不冻结，避免现场因一个组态错就停线——与 `PresetCounterSat` 的「倒置冻结」策略相反，差异必须在头注释声明）。
4. **装载优先**：`IF fbTrigLoad.Q THEN nCvInt := 限幅(nLoadValue); bLoadDone := TRUE; uErrorId := 16#0001_0118 IF 发生钳位;` 装载拍**跳过**计数分支。
5. **复位**：`IF bReset THEN nCvInt := 0; bError := FALSE; bPresetBad := FALSE; uErrorId := 0;` （复位优先于装载后的计数，但**不**屏蔽装载脉冲）。
6. **方向仲裁**：`IF bEnable AND NOT bReset AND NOT fbTrigLoad.Q THEN` 内，`IF fbTrigUp.Q AND NOT fbTrigDown.Q THEN +1; bUpPulse := TRUE; ELSIF fbTrigDown.Q AND NOT fbTrigUp.Q THEN -1; bDnPulse := TRUE; ELSIF fbTrigUp.Q AND fbTrigDown.Q THEN` **加优先**（同拍双边沿 = 净 +1，符合 CTUD 惯例，先写死再注释）。
7. **饱和钳位**：+1 时若 `nCvInt >= DL_COUNT_MAX` → 保持并置 `bAtMax := TRUE`、`bUpPulse := FALSE`；-1 对称。
8. **比较输出每拍重写**（R27）：`bQu := (nCvInt >= nPresetUp) AND bEnable;` `bQd := (nCvInt <= nPresetDn) AND bEnable;` 每拍重算，禁止只在「跨预设那一拍」赋值。
9. `nCv := nCvInt;`

**码位表**：`16#0001_0118` 装载值越界钳位（信息级）｜`16#0001_0215` 预设倒置（PV_UP ≤ PV_DN，故障级锁存，计数不冻结）｜`16#0001_0216` 非法状态兜底（保留位，本块无 CASE 主状态机，仅用于防御式默认分支）。

**验收要点**
- V1（基本双向）：PV_UP=3、PV_DN=0，CU 三拍 → `nCv=3`、`bQu=TRUE`；CD 一拍 → `nCv=2`、`bQu=FALSE`、`bQd=FALSE`。
- V2（同拍边沿）：CU 与 CD 同拍上升 → `nCv` **+1**（加优先），`bUpPulse=TRUE`、`bDnPulse=FALSE`。
- V3（装载优先）：`bLoad` 与 `bCountUp` 同拍 → 值 = `nLoadValue`，`bLoadDone=TRUE`、`bUpPulse=FALSE`。
- V4（倒置预设）：`nPresetUp=5, nPresetDn=10` → `bError=TRUE`、码 `0215`，且计数继续（推演 3 拍 CU 后 `nCv=3`）。
- V5（饱和）：将 `nLoadValue=DL_COUNT_MAX` 装载后 CU 一拍 → `nCv` 不变、`bAtMax=TRUE`、`bUpPulse=FALSE`。
- V6（R27 保持）：进入 `bQu=TRUE` 后再 CU 两拍，`bQu` 必须**每拍仍为 TRUE**（不得因未跨阈而回落）。
- 机检：`R_TRIG` 三实例在 `CASE`/`IF` 之外无条件调用；单拍三个输出在主体前部均有预清零语句。

---

### 4. `FC_DL_SearchMinMax` —— 数组极值与索引同出（LREAL）

- 子库：**DL_MathData** ｜ 类型：**FC**（纯函数） ｜ 预计行数：**280** ｜ 来源组标签：`lgf-math`、`pure-function`、`array-scan`
- 功能描述：在注入数组前 `nCount` 个元素中同时求最小值、最大值及其**首个命中索引**；可选「末次命中索引」出口（`bLastHit`），并可统计被跳过的非有限值（NaN/Inf）个数。对应 LGF V5.5 的 `LGF_SearchMinMax` / `_LReal` / `_DInt` / `_UDInt` 四个变体的**LREAL 主线**（其余类型变体后续按「数据类型重载」规则另立块，本轮只做 LREAL，禁 MODE 参数）。
- **与既有件边界**：`FB_DL_SignalStatistics` 是**流式窗口**统计（含均值/方差，块型、有状态）；`FB_DL_PeakDetector` 是**时域峰值跟踪**（带衰减与事件）；本件是**静态数组一次性扫描**（纯函数、无状态），只出极值与索引。

**引脚规格**

```iecst
FUNCTION FC_DL_SearchMinMax : BOOL
VAR_INPUT
    nCount    : DINT := 0;          // 参与扫描的元素个数 [个]，有效域 1~DL_SMM_MAX
    bLastHit  : BOOL := FALSE;      // TRUE = 索引取末次命中；FALSE = 取首个命中（默认）
END_VAR
VAR_IN_OUT
    afData    : ARRAY[0..DL_SMM_MAX-1] OF LREAL;  // 扫描数据体（调用方持有并注入）
END_VAR
VAR_OUTPUT
    fMin      : LREAL;              // 最小值 [工程单位随应用]
    fMax      : LREAL;              // 最大值 [工程单位随应用]
    nMinIdx   : DINT := -1;         // 最小值索引 [元素下标]，未找到 = -1
    nMaxIdx   : DINT := -1;         // 最大值索引 [元素下标]，未找到 = -1
    nValidCnt : DINT;               // 实际参与比较的有效元素数 [个]
    nSkipCnt  : DINT;               // 因非有限值被跳过的元素数 [个]
    bFlat     : BOOL;               // 全等标志（fMin 与 fMax 在容差内相等）
    uErrorId  : UDINT;              // 事件码，0 = 无事件
END_VAR
VAR CONSTANT
    DL_SMM_MAX   : DINT  := 256;    // 数组上限 [元素]
    DL_FLOAT_EPS : LREAL := 1.0E-9; // 浮点比较容差（判全等/防判等陷阱）
END_VAR
```

**算法要点**
1. 域校验：`nCount < 1` → `16#0001_0119`，输出 `-1` 索引、`RETURN FALSE`；`nCount > DL_SMM_MAX` → 钳到 `DL_SMM_MAX` 并置 `0119`（信息级），继续计算。
2. 非有限值过滤（防御式，不依赖厂商 `ISNAN`）：`IF (afData[i] <> afData[i]) OR (ABS(afData[i]) > DL_BIG)` → `nSkipCnt + 1`、跳过。`afData[i] <> afData[i]` 是 IEEE NaN 的**可移植判据**（NaN ≠ 自身），注释必须写明理由；`DL_BIG := 1.0E300` 作为 ±Inf 兜底。
3. 单遍扫描：`i` 从 0 到 `nCount-1`；首命中策略下用严格 `>` / `<`；末命中策略下用 `>=` / `<=`（**不是** MODE，而是既有 `bLastHit` 布尔策略开关，语义单一，不构成巨无霸块）。
4. 全等判定：`bFlat := (nValidCnt > 0) AND (ABS(fMax - fMin) < DL_FLOAT_EPS)`——浮点禁止 `=`（红线第 5 条）。
5. 全量非有限（`nValidCnt = 0`）→ `uErrorId := 16#0001_0217`，`RETURN FALSE`，`fMin = fMax = 0.0`、索引 `-1`（**不静默返回 0 冒充有效最小值**）。
6. `WHILE` 一律改 `FOR`（计数确定），故无需防死锁计数器；但 `FOR` 上界必须是**钳位后的** `nCountClamped`，禁止直接用入参。

**码位表**：`16#0001_0119` 计数越界/钳位（信息级）｜`16#0001_011A` 检测到非有限值并跳过（信息级，附 `nSkipCnt`）｜`16#0001_0217` 全量非有限、无有效极值（故障级，返回 FALSE）。

**验收要点**
- V1：`[3.5, -2.0, 9.0, -2.0]`，`nCount=4`，`bLastHit=FALSE` → `fMin=-2.0 @ idx1`、`fMax=9.0 @ idx2`。
- V2：同上 `bLastHit=TRUE` → `fMin=-2.0 @ idx3`（末次命中）。
- V3：`[1.0, NaN, 1.0]` → `nSkipCnt=1`、`nValidCnt=2`、`bFlat=TRUE`、码含 `011A`。
- V4：`nCount=0` → 返回 FALSE、码 `0119`、两索引 `-1`。
- V5：`nCount=300`（>256）→ 只扫前 256 个、码 `0119`、`RETURN TRUE`（钳位后仍有效）。
- 机检：无 `=` 做浮点比较；`FOR` 上界为钳位变量。

---

### 5. `FC_DL_NthRoot` —— N 次方根（含奇偶次与负数域守卫）

- 子库：**DL_MathData** ｜ 类型：**FC**（纯函数） ｜ 预计行数：**220** ｜ 来源组标签：`lgf-math`、`pure-function`
- 功能描述：计算 `x` 的 `n` 次方根 `x^(1/n)`。标准库只有 `SQRT`（二次）；本件补齐任意次根，覆盖几何平均、等效值折算、按幂律反算（如泵/风机相似定律反算转速比）等场景。
- **与既有件边界**：无同类件；`FC_DL_LinearScale` / `FC_DL_MultiPointLinear` 是线性/折线映射，与幂运算无关。

**引脚规格**

```iecst
FUNCTION FC_DL_NthRoot : LREAL
VAR_INPUT
    fValue : LREAL := 1.0;          // 被开方数 [无量纲/工程单位]，偶次根要求 >= 0
    nRoot  : INT := 2;              // 根次数 n [次]，有效域 1~DL_ROOT_MAX（正整数）
END_VAR
VAR_OUTPUT
    bValid  : BOOL;                 // 计算有效（域合法且结果有限）= TRUE
    uErrorId : UDINT;               // 事件码，0 = 无事件
END_VAR
VAR CONSTANT
    DL_ROOT_MAX  : INT   := 64;     // 根次数上限 [次]（超此域用对数法精度不可控）
    DL_FLOAT_EPS : LREAL := 1.0E-12;// 判零/判负容差
    DL_BIG       : LREAL := 1.0E300;// 非有限值兜底比较门限
END_VAR
```

**算法要点**
1. 域校验：`nRoot < 1 OR nRoot > DL_ROOT_MAX` → `16#0001_011B`，返回 0.0、`bValid := FALSE`。
2. 负数处理（**奇偶分治，唯一正确解**）：`fValue < -DL_FLOAT_EPS` 时——
   - 若 `nRoot MOD 2 = 0`（偶次根）→ 实数域无解：`16#0001_011C`、返回 0.0、`bValid := FALSE`（禁止返回绝对值的结果冒充）。
   - 若奇数 → 取绝对值求根后**取反**：`-EXP(LN(ABS(fValue)) / nRoot)`。
3. 零与近零：`ABS(fValue) < DL_FLOAT_EPS` → 直接返回 0.0、`bValid := TRUE`（避免 `LN(0)`）。
4. 正数主路径：`fValue = 1.0` 特判返回 1.0（省一次 `EXP/LN`）；`nRoot = 2` 特判走 `SQRT`（精度优于对数法）；其余走 `EXP(LN(fValue) / INT_TO_LREAL(nRoot))`。
5. 结果有限性复检：`IF (fResult <> fResult) OR (ABS(fResult) > DL_BIG) THEN` → `16#0001_011C`、`bValid := FALSE`（`EXP` 溢出兜底）。
6. 说明：`EXP`/`LN`/`SQRT` 均为 `Standard.library` 标准函数，跨平台安全；禁止用迭代牛顿法（收敛次数不定，违反确定性）。

**码位表**：`16#0001_011B` 根次数越界（信息级，返回 0）｜`16#0001_011C` 偶次根负数/结果非有限（信息级，返回 0，`bValid=FALSE`）。

**验收要点**
- V1：`fValue=27, nRoot=3` → `3.0`（容差 1E-9）。
- V2：`fValue=-27, nRoot=3` → `-3.0`（奇次负数根，符号必须保留）。
- V3：`fValue=-4, nRoot=2` → `0.0`、`bValid=FALSE`、码 `011C`。
- V4：`fValue=16, nRoot=4` → `2.0`。
- V5：`nRoot=0` → `0.0`、码 `011B`。
- V6：`fValue=0` → `0.0`、`bValid=TRUE`（不得落 `LN(0)` 路径，可在调试版加断点验证）。
- 机检：`LN`/`EXP` 调用前必有 `ABS(fValue) >= DL_FLOAT_EPS` 守卫。

---

### 6. `FC_DL_FactorialSat` —— 阶乘（0~12 域，溢出饱和）

- 子库：**DL_MathData** ｜ 类型：**FC**（纯函数） ｜ 预计行数：**200** ｜ 来源组标签：`lgf-math`、`pure-function`
- 功能描述：计算 `n!`（n 为 0~12 的整数），超出域或结果溢出时**饱和**并给码，绝不返回错误数值冒充结果。用于组合数、排列数、概率判定与工艺配方阶乘系数。
- **与既有件边界**：无同类件。`FC_DL_BitCount` 是汉明重量（位计数），与本件无语义交集。

**引脚规格**

```iecst
FUNCTION FC_DL_FactorialSat : DINT
VAR_INPUT
    nValue : INT := 0;              // 自然数 n [无量纲]，有效域 0~12（13! 超 DINT）
END_VAR
VAR_OUTPUT
    bSat     : BOOL;                // 饱和标志：入参超域或结果溢出 = TRUE
    nUsedN   : INT;                 // 实际参与计算并钳位后的 n [无量纲]
    uErrorId : UDINT;               // 事件码，0 = 无事件
END_VAR
VAR CONSTANT
    DL_FACT_MAX_N : INT  := 12;     // 最大可算 n（12! = 479001600 < DINT 上限）
    DL_FACT_SAT   : DINT := 479001600; // 12! 饱和输出值（超域一律返回此值）
END_VAR
```

**算法要点**
1. 域校验：`nValue < 0` → `nUsedN := 0`、`bSat := TRUE`、`uErrorId := 16#0001_011D`、返回 **1**（0! = 1，负域按 0 处理并置饱和——**必须在头注释写明该约定**，避免现场误判）；`nValue > DL_FACT_MAX_N` → `nUsedN := 12`、`bSat := TRUE`、码 `011D`、返回 `DL_FACT_SAT`。
2. 主路径：`FOR i := 2 TO nValue DO fAcc := fAcc * i; END_FOR`，累加器用 `DINT`（12! 不溢出；注释写明「最大值 479001600，DINT 上限 2147483647，安全裕度 4.5 倍」）。
3. 输出即函数返回值；`bSat = FALSE` 时调用方可直接当精确值使用（契约级承诺，写入头注释）。
4. 无浮点、无除法、无循环不确定次数 → 无需防死锁计数器，但 `FOR` 上界必须是钳位后的 `nUsedN`。

**码位表**：`16#0001_011D` 入参超域（信息级，饱和输出并置 `bSat`）。

**验收要点**
- V1：`nValue=0` → `1`、`bSat=FALSE`。
- V2：`nValue=5` → `120`。
- V3：`nValue=12` → `479001600`、`bSat=FALSE`。
- V4：`nValue=13` → `479001600`、`bSat=TRUE`、码 `011D`。
- V5：`nValue=-3` → `1`、`bSat=TRUE`、码 `011D`。
- 机检：`FOR` 上界为 `nUsedN`；无 `REAL` 累加。

---

### 7. `FB_DL_SineGenerator` —— 正弦波给定发生器（幅值/偏置/频率/相位）

- 子库：**DL_Algo** ｜ 类型：**FB** ｜ 预计行数：**460** ｜ 来源组标签：`lgf-signalgen`、`signal-generation`
- 功能描述：以任务周期与频率引脚推进相位，输出 `fOut = fOffset + fAmplitude · sin(2π·(fFreq·t + fPhase0))` 的连续正弦给定。用于振动台/摇摆机构测试给定、执行器寿命疲劳试验、阀门特性扫描、仿真信号注入。
- **与既有件边界**：`FB_DL_PulseGenerator` 出方波（BOOLEAN/TIME 域）；`FB_DL_SawtoothGenerator`（本轮 #8）出锯齿/三角；本件出**正弦**。三者独立成块，**严禁**用 `eWaveform` 参数合并（矩阵第 3 节禁令 + 八条红线第 8 条）。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_SineGenerator
VAR_INPUT
    bEnable     : BOOL := TRUE;         // 使能；FALSE 时输出保持 fHoldValue 并冻结相位
    bResetPhase : BOOL;                 // 相位复位，上升沿把累计相位归零（不改变频率/幅值）
    fAmplitude  : LREAL := 1.0;         // 幅值 [工程单位]，域 >= 0；0 = 恒输出偏置
    fOffset     : LREAL := 0.0;         // 直流偏置 [工程单位]
    fFreq       : LREAL := 1.0;         // 频率 [Hz]，域 0~DL_FREQ_MAX；0 = 冻结在当前相位
    fPhase0     : LREAL := 0.0;         // 初相位 [°]，域 -360.0~360.0（内部归一到 0~360）
    fTaskCycle  : LREAL := 0.01;        // 任务周期 [s]，域 1ms~1s，由调用方按实际任务注入
    fHoldValue  : LREAL := 0.0;         // 失能时的输出保持值 [工程单位]
    bClampOut   : BOOL := FALSE;        // TRUE = 按 fOutMin/fOutMax 限幅输出
    fOutMin     : LREAL := -1.0E6;      // 输出下限 [工程单位]
    fOutMax     : LREAL := 1.0E6;       // 输出上限 [工程单位]
END_VAR
VAR_OUTPUT
    fOut        : LREAL;                // 正弦输出 [工程单位]
    fPhaseDeg   : LREAL;                // 当前相位 [°]，0~360
    uCycleCnt   : UDINT;                // 完整周期计数 [个]（相位回绕次数，用于寿命/疲劳计数）
    bRunning    : BOOL;                 // 运行中（使能且频率 > 0）
    uErrorId    : UDINT;                // 事件码，0 = 无事件
    bError      : BOOL;                 // 故障锁存（仅故障级置位，R21）
END_VAR
VAR
    fbTrigReset : R_TRIG;               // 相位复位边沿
    bInit       : BOOL := FALSE;        // 首扫标志（R19）
    fPhaseRad   : LREAL := 0.0;         // 累计相位 [rad]，0~2π
    fCycleAcc   : LREAL := 0.0;         // 周期内相位累积 [rad]
    eState      : E_DL_SigGenState;     // 发生器状态机
END_VAR
VAR CONSTANT
    DL_TWO_PI    : LREAL := 6.283185307179586;  // 2π [rad]
    DL_PI        : LREAL := 3.141592653589793;  // π [rad]
    DL_DEG2RAD   : LREAL := 0.017453292519943295; // 度→弧度换算系数 [rad/°]
    DL_FREQ_MAX  : LREAL := 100.0;       // 频率上限 [Hz]（保证每周期采样点 >= 10，防混叠）
    DL_CYCLE_MIN : LREAL := 0.001;       // 任务周期下限 [s]
    DL_CYCLE_MAX : LREAL := 1.0;         // 任务周期上限 [s]
    DL_TASK_CYC  : LREAL := 0.01;        // 默认任务周期 [s]（与默认引脚一致）
END_VAR
TYPE E_DL_SigGenState : (             // 正弦发生器状态（#7 与 #8 共用同一枚举名空间）
    eIdle    := 0,                    // 未初始化 / 已停止
    eRunning := 10,                   // 正常推进
    eFault   := 99                    // 故障锁定
);
END_TYPE
```

**状态机与算法要点**
1. 首扫（R19）：`IF NOT bInit THEN` 初始化 `eState := eIdle`、`fPhaseRad := 归一(fPhase0)`、`uCycleCnt := 0`、`uErrorId := 0`、`bInit := TRUE;`。
2. 边沿无条件刷新：`fbTrigReset(CLK := bResetPhase);`
3. 参数域校验（每拍，信息级不锁存）：`fTaskCycle` 越界 → 钳到 `DL_CYCLE_MIN..DL_CYCLE_MAX` 并置 `16#0002_1B01`；`fFreq` 越界（<0 或 >DL_FREQ_MAX）→ 钳位并置 `16#0002_1B02`；`fAmplitude < 0` → 取绝对值并置 `16#0002_1B03`；`fPhase0` 超 ±360 → 归一并置 `16#0002_1B04`。
4. 故障级：`fAmplitude / fOffset / fFreq / fTaskCycle` 任一非有限值（`x <> x` 或 `ABS(x) > 1E300`）→ `eState := eFault`、`uErrorId := 16#0002_1B10`、`bError := TRUE`，输出 `fHoldValue`（**锁存需 `bResetPhase` 上升沿 + 参数恢复才解除**，写入注释）。
5. 状态机 `CASE eState OF`：
   - `eIdle`：若参数域合法且 `bEnable` → `eRunning`；否则 `fOut := fHoldValue`。
   - `eRunning`：若 `NOT bEnable` → 冻结相位（`fPhaseRad` 不改）、`fOut := fHoldValue`；若 `fFreq = 0.0`（判等用 `ABS(fFreq) < 1E-9`）→ 冻结相位、输出当前相位对应值（**不归零**）；否则 `fCycleAcc := fCycleAcc + DL_TWO_PI * fFreq * fTaskCycle;` 相位累加，`IF fCycleAcc >= DL_TWO_PI THEN fCycleAcc := fCycleAcc - DL_TWO_PI; uCycleCnt := uCycleCnt + 1; END_IF`（**单次减法 + 循环守卫**：若 `fFreq·dt > 2π`（欠采样）则需 `WHILE` 回绕，必须带 `DL_MAX_WRAP := 64` 防死锁计数器，超限置 `16#0002_1B11` 并转 `eFault`）。
   - `ELSE`（非法枚举值）：`eState := eFault; uErrorId := 16#0002_1B11; bError := TRUE; fOut := fHoldValue;`（强制兜底）。
6. 输出：`fOut := fOffset + fAmplitude * SIN(fCycleAcc)`；`IF bClampOut THEN fOut := LIMIT(fOutMin, fOut, fOutMax);`（限幅两侧同时做，红线「限幅只做一侧」陷阱）。
7. `fPhaseDeg := fCycleAcc * 57.29577951308232;`（注释写明系数 = 180/π）；`bRunning := (eState = eRunning) AND bEnable AND (fFreq > 1E-9)`。
8. `SIN` 为 `Standard.library` 标准函数，入参 [rad]，注释必须写明（跨平台仍按 rad）。

**码位表**：`16#0002_1B01` 任务周期钳位（信息级）｜`16#0002_1B02` 频率钳位（信息级）｜`16#0002_1B03` 幅值取绝对值（信息级）｜`16#0002_1B04` 初相归一（信息级）｜`16#0002_1B10` 参数非有限值（故障级锁存）｜`16#0002_1B11` 相位回绕超限/非法状态兜底（故障级）。

**验收要点**
- V1（四分之一周期）：`fAmplitude=10, fOffset=0, fFreq=1, fTaskCycle=0.25, fPhase0=0` → 第 1 拍相位 90° → `fOut≈10.0`（容差 1E-6）。
- V2（整周期）：`fTaskCycle=0.01, fFreq=1` 推 100 拍 → `uCycleCnt=1`，`fOut` 回到 ≈0（容差 1E-6）。
- V3（相位复位）：运行中拉 `bResetPhase` 一拍 → `fPhaseDeg` 归 `fPhase0` 归一值，`uCycleCnt` 保持（不复位计数）。
- V4（失能保持）：`bEnable=FALSE`、`fHoldValue=3.5` → `fOut=3.5` 且 `fPhaseDeg` 冻结（两拍不变）。
- V5（欠采样守卫）：`fFreq=100, fTaskCycle=1.0`（每拍 100 周期）→ 触发 `WHILE` 守卫，`uCycleCnt` 增量 ≤ 64 且置 `1B11` 转 `eFault`（验证防死锁，R13 逐拍推演）。
- 机检：`SIN` 前相位变量注释为 [rad]；`LIMIT` 同时含上下限；`WHILE` 有 `DL_MAX_WRAP` 计数器。

---

### 8. `FB_DL_SawtoothGenerator` —— 锯齿/三角波给定发生器（对称度可调）

- 子库：**DL_Algo** ｜ 类型：**FB** ｜ 预计行数：**400** ｜ 来源组标签：`lgf-signalgen`、`signal-generation`
- 功能描述：单块实现「锯齿 ↔ 三角」连续族：以 `fSymmetry`（上升段占周期比例，0.0~1.0）定义波形形状——`1.0` 为纯锯齿（瞬间回落），`0.5` 为对称三角波，中间值为非对称三角。这是 LGF Signal Generators 组「锯齿波 / 斜坡」族的连续参数化收敛，**不是** MODE 巨无霸（单一物理意义参数，无分支枚举、无职责混杂）。
- **与既有件边界**：`FB_DL_RampGenerator` 是**给定量斜坡**（把阶跃目标平滑，含暂停保持）；`FB_DL_SCurveGenerator` 是 S 型规划；本件是**周期信号源**（无目标值概念，自主循环）。三者输入语义完全不同。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_SawtoothGenerator
VAR_INPUT
    bEnable    : BOOL := TRUE;          // 使能；FALSE 时输出保持 fHoldValue 并冻结相位
    bResetPhase: BOOL;                  // 相位复位，上升沿周期内相位归零
    fPeriod    : LREAL := 1.0;          // 波形周期 [s]，域 DL_PERIOD_MIN~DL_PERIOD_MAX
    fSymmetry  : LREAL := 0.5;          // 上升段占周期比例 [-]，域 0.01~0.99；0.5 = 对称三角
    fLow       : LREAL := 0.0;          // 波形下限 [工程单位]（谷值）
    fHigh      : LREAL := 100.0;        // 波形上限 [工程单位]（峰值）
    fTaskCycle : LREAL := 0.01;         // 任务周期 [s]
    fHoldValue : LREAL := 0.0;          // 失能/故障时输出值 [工程单位]
END_VAR
VAR_OUTPUT
    fOut       : LREAL;                 // 波形输出 [工程单位]，值域 fLow~fHigh
    fPhasePct  : LREAL;                 // 当前周期内相位 [%]，0~100
    bRising    : BOOL;                  // 当前处于上升段（TRUE）/ 下降段（FALSE）
    uCycleCnt  : UDINT;                 // 完整周期计数 [个]
    bRunning   : BOOL;                  // 运行中
    uErrorId   : UDINT;                 // 事件码，0 = 无事件
    bError     : BOOL;                  // 故障锁存（仅故障级，R21）
END_VAR
VAR
    fbTrigReset : R_TRIG;               // 相位复位边沿
    bInit       : BOOL := FALSE;        // 首扫标志（R19）
    fPhase01    : LREAL := 0.0;         // 周期内归一相位 [-]，0.0~1.0（不含 1.0）
    eState      : E_DL_SawState;        // 状态机
END_VAR
VAR CONSTANT
    DL_PERIOD_MIN : LREAL := 0.001;     // 最小周期 [s]（1 ms）
    DL_PERIOD_MAX : LREAL := 3600.0;    // 最大周期 [s]（1 h）
    DL_SYM_MIN    : LREAL := 0.01;      // 对称度下限 [-]
    DL_SYM_MAX    : LREAL := 0.99;      // 对称度上限 [-]
    DL_MAX_WRAP   : INT   := 64;        // 单拍回绕次数上限（防死锁，R13）
    DL_EPS        : LREAL := 1.0E-9;    // 浮点判零容差
    DL_RANGE_MIN  : LREAL := 1.0E-6;    // 高低值最小差（防除零）
END_VAR
TYPE E_DL_SawState : (
    eIdle    := 0,                      // 未初始化/停止
    eRunning := 10,                     // 推进中
    eFault   := 99                      // 故障锁定（需参数恢复 + 复位沿）
);
END_TYPE
```

**算法要点**
1. 首扫（R19）：`IF NOT bInit THEN` 初始化 `eState := eIdle`、`fPhase01 := 0.0`、`uCycleCnt := 0`、`bInit := TRUE;`。
2. 边沿无条件刷新：`fbTrigReset(CLK := bResetPhase);`
3. 域校验（每拍，信息级）：`fPeriod` 越界钳位 → `16#0002_1C01`；`fSymmetry` 越界钳位 → `16#0002_1C02`；`fHigh - fLow < DL_RANGE_MIN` → 交换/抬高（`fHigh := fLow + DL_RANGE_MIN`）并置 `16#0002_1C03`（防分段计算除零，红线除法防零）。
4. 故障级：任一 LREAL 参数非有限 → `eState := eFault`、`16#0002_1C10`、`bError := TRUE`、`fOut := fHoldValue`。
5. 相位推进：`fPhase01 := fPhase01 + fTaskCycle / fPeriod;`（除零已由 `DL_PERIOD_MIN` 钳位保证）；`IF fPhase01 >= 1.0 THEN fPhase01 := fPhase01 - 1.0; uCycleCnt := uCycleCnt + 1;` 欠采样时 `WHILE` 回绕 + `DL_MAX_WRAP` 守卫，超限置 `1C10` 转 `eFault`。
6. 分段换算（**先判段再算，避免除零**）：
   - 上升段（`fPhase01 < fSymmetry`）：`fOut := fLow + (fHigh - fLow) * (fPhase01 / fSymmetry);`，`bRising := TRUE`。
   - 下降段：`fOut := fHigh - (fHigh - fLow) * ((fPhase01 - fSymmetry) / (1.0 - fSymmetry));`，`bRising := FALSE`（`1.0 - fSymmetry >= 0.01` 由 `DL_SYM_MAX` 保证非零）。
7. 边界钉值：`fPhase01` 落在 `[0, 1)` 半开区间；`fSymmetry = 1.0` 被钳到 `0.99`（保留极窄下降段，避免除零），头注释必须声明该收窄（R11）。
8. `fPhasePct := fPhase01 * 100.0;`；`bRunning := (eState = eRunning) AND bEnable;`。
9. `CASE ... ELSE` 兜底：非法枚举 → `eFault` + `1C10` + 输出保持值。

**码位表**：`16#0002_1C01` 周期钳位（信息级）｜`16#0002_1C02` 对称度钳位（信息级）｜`16#0002_1C03` 高低值区间修正（信息级）｜`16#0002_1C10` 参数非有限/回绕超限/非法状态（故障级锁存）。

**验收要点**
- V1（对称三角）：`fLow=0, fHigh=100, fSymmetry=0.5, fPeriod=1.0, fTaskCycle=0.25` → 第 1 拍 `fOut=50`（升），第 3 拍 `fOut=50`（降，`bRising=FALSE`）。
- V2（纯锯齿）：`fSymmetry=0.99` → 相位 0.5 时 `fOut ≈ 0 + 100*(0.5/0.99) ≈ 50.5`（上升段长）。
- V3（周期计数）：`fPeriod=1.0, fTaskCycle=0.1` 推 10 拍 → `uCycleCnt=1`、`fPhase01≈0`。
- V4（区间修正）：`fLow=50, fHigh=50` → 触发 `1C03`，`fHigh=50.000001`，输出不出现除零。
- V5（失能冻结）：`bEnable=FALSE` → `fOut=fHoldValue`，两拍 `fPhasePct` 不变。
- 机检：两处除法分母均被常量钳位保护；无 `MODE`/`eMode` 类多职责参数。

---

### 9. `FC_DL_CoilDiameterCalc` —— 卷径估算（线速度/角速度比法，双出口）

- 子库：**DL_Algo** ｜ 类型：**FC**（纯函数） ｜ 预计行数：**260** ｜ 来源组标签：`lgf-technology`、`web-handling`、`pure-function`
- 功能描述：由「材料线速度 + 卷轴转速 + 机械传动比」反算瞬时卷径 `D = v · i / (π · n)`（`n` 单位 r/min），并同时给出「层厚积分法」所需的层数增量与**卷径变化率**出口。是收/放卷张力控制（扭矩 = 张力 × D/2）、线速度匹配、排线节距计算的数据源头。
- **与既有件边界**：本件只做**瞬时几何反算**（无状态）；层厚积分递推属 `FB_DL_WindingTraverse`（#15）内部职责，二者互为校验关系而非调用关系（泳道禁令）。ROADMAP §7.1 `FB_DL_WindingTraverse` 与本件构成「算法-执行」链，但代码零耦合。

**引脚规格**

```iecst
FUNCTION FC_DL_CoilDiameterCalc : LREAL
VAR_INPUT
    fLineSpeed   : LREAL := 0.0;    // 材料线速度 [m/min]，域 0~DL_VMAX
    fShaftRpm    : LREAL := 0.0;    // 卷轴转速 [r/min]，域 0~DL_NMAX（0 = 停机，见算法第 2 条）
    fGearRatio   : LREAL := 1.0;    // 卷轴:电机 传动比 [-]，域 0.01~1000（1.0 = 直连）
    fCoreDia     : LREAL := 0.100;  // 卷芯（纸管）直径 [m]，域 0.01~1.0
    fThickness   : LREAL := 0.0001; // 材料厚度 [m]，域 1E-6~0.01（层厚积分用）
    fPrevDia     : LREAL := 0.0;    // 上拍卷径 [m]，0 = 无历史（变化率出口置 0）
    fTaskCycle   : LREAL := 0.01;   // 任务周期 [s]，域 1ms~1s（变化率换算用）
    bFilterEn    : BOOL := TRUE;    // 一阶低通使能（编码器量化噪声抑制）
    fFilterTau   : LREAL := 1.0;    // 低通时间常数 [s]，域 0.1~10.0
END_VAR
VAR_OUTPUT
    fDia         : LREAL;           // 估算卷径 [m]（已滤波，低通使能时）
    fDiaRaw      : LREAL;           // 未滤波卷径 [m]（诊断/比对用）
    fDiaRate     : LREAL;           // 卷径变化率 [m/s]，正 = 收卷增大
    fLayerCount  : LREAL;           // 相对卷芯的累计层数 [层]（由厚度积分，双卷径法）
    bValid       : BOOL;            // 计算有效
    uErrorId     : UDINT;           // 事件码，0 = 无事件
END_VAR
VAR CONSTANT
    DL_PI        : LREAL := 3.141592653589793; // π [-]
    DL_VMAX      : LREAL := 3000.0; // 线速度上限 [m/min]（50 m/s，覆盖高速分切）
    DL_NMAX      : LREAL := 6000.0; // 转速上限 [r/min]
    DL_RPM_EPS   : LREAL := 0.5;    // 转速判零门限 [r/min]（低频量化不可信，低于此不反算）
    DL_DIA_MIN   : LREAL := 0.01;   // 卷径下限 [m]
    DL_DIA_MAX   : LREAL := 3.0;    // 卷径上限 [m]
    DL_FLOAT_EPS : LREAL := 1.0E-9; // 浮点容差
END_VAR
```

**算法要点**
1. 域校验（信息级）：`fLineSpeed` 越界钳位 → `16#0002_1D01`；`fGearRatio` 越界钳位 → `16#0002_1D02`；`fCoreDia` / `fThickness` 越界钳位 → `16#0002_1D03`。全部钳位后**继续计算**（现场宁可给近似值也不给 0 断链）。
2. **低速保护（关键工程语义）**：`fShaftRpm < DL_RPM_EPS` → 不反算（编码器低频量化会让直径跳到 ±5 mm 级），`fDia := fPrevDia`（沿用上次有效值，**不归零**）、`fDiaRate := 0.0`、`bValid := (fPrevDia >= DL_DIA_MIN)`、`uErrorId := 16#0002_1D10`（信息级），`RETURN FALSE`。停机瞬间卷径突然归零是现场最常见的事故源，必须在注释中写明。
3. 主算法：`fDiaRaw := (fLineSpeed / 60.0) * fGearRatio / (DL_PI * (fShaftRpm / 60.0));`（分子分母同除 60 可约，但**分开写**以保留单位可读性，注释标注 `[m/min]→[m/s]`、`[r/min]→[r/s]`）；化简后等价 `fDiaRaw := fLineSpeed * fGearRatio / (DL_PI * fShaftRpm)`——注释必须给出化简式，防后续维护者误改。
4. 卷径钳位与卷芯保护：`IF fDiaRaw < fCoreDia THEN fDiaRaw := fCoreDia; uErrorId := 16#0002_1D04;`（卷径不可能小于卷芯，出现即为打滑/测速错）；再 `LIMIT(DL_DIA_MIN, fDiaRaw, DL_DIA_MAX)`。
5. 一阶低通（`bFilterEn` 时）：`fAlpha := fTaskCycle / (fFilterTau + fTaskCycle);` `fDia := fPrevDia + fAlpha * (fDiaRaw - fPrevDia);`（`fPrevDia = 0` 时直接取 `fDiaRaw`，首拍无滞后——R19 精神）；α 分母恒 > 0（`fFilterTau >= 0.1`）。
6. 变化率：`IF fPrevDia > DL_FLOAT_EPS THEN fDiaRate := (fDia - fPrevDia) / fTaskCycle; ELSE fDiaRate := 0.0; END_IF`（除零守卫）。
7. 层数：`fLayerCount := (fDia - fCoreDia) / (2.0 * fThickness);`（厚度域已钳位，分母 ≥ 2E-6）。
8. 非有限入参 → `bValid := FALSE`、`uErrorId := 16#0002_1D10`、各输出保持 0。

**码位表**：`16#0002_1D01` 线速度钳位（信息级）｜`16#0002_1D02` 传动比钳位（信息级）｜`16#0002_1D03` 卷芯/厚度钳位（信息级）｜`16#0002_1D04` 卷径小于卷芯修正（信息级，疑似打滑）｜`16#0002_1D10` 低速不可信/参数非有限（信息级，沿用上次值）。

**验收要点**
- V1：`v=100 m/min, n=100 r/min, i=1` → `D = 100/(π·100) = 0.3183 m`（容差 1E-4）。
- V2：`n=0.2 r/min`（< 0.5）→ 返回 `fPrevDia`、`fDiaRate=0`、码 `1D10`、`bValid` 随 `fPrevDia` 判定。
- V3：`v=10, n=100, fCoreDia=0.2` → `D_raw=0.0318 < 0.2` → 修正为 0.2 并置 `1D04`。
- V4：滤波一致性：`fPrevDia=0`、`bFilterEn=TRUE` → 首拍 `fDia = fDiaRaw`（无滞后）。
- V5：`fPrevDia=0.3, fDia=0.302, fTaskCycle=0.01` → `fDiaRate=0.2 m/s`。
- 机检：所有除法分母（`fShaftRpm`、`fFilterTau+fTaskCycle`、`fPrevDia`、`fThickness`）均有守卫或常量域保证。

---

### 10. `FC_DL_AirDensity` —— 湿空气密度（T/P/RH → kg/m³）

- 子库：**DL_Algo** ｜ 类型：**FC**（纯函数） ｜ 预计行数：**300** ｜ 来源组标签：`oscat-building`、`hvac`、`psychrometrics`、`pure-function`
- 功能描述：按干空气 + 水蒸气分压叠加法计算湿空气密度 `ρ = p_d/(R_d·T) + p_v/(R_v·T)`（kg/m³），饱和蒸汽压用 Magnus-Tetens 式（与已入库 `FC_DL_DewPointCalc` / `FC_DL_HumidAirEnthalpy` 同一常量口径）。用于风量质量流量换算（风机功率、风管风速→质量流量）、洁净室换气次数核算、烘干/涂布风量配比。
- **与既有件边界**：`FC_DL_HumidAirEnthalpy` 出**比焓** [J/g]；`FC_DL_DewPointCalc` 出**露点** [°C]；本件出**密度** [kg/m³]。三件共享 Magnus 常量口径，但**各自内联**（禁互相调用，泳道 B 内零依赖），头注释必须写明「常量口径与 XX 一致，公式链独立内联」。

**引脚规格**

```iecst
FUNCTION FC_DL_AirDensity : LREAL
VAR_INPUT
    fTempC   : LREAL := 20.0;       // 干球温度 [°C]，域 -40.0~120.0
    fPressPa : LREAL := 101325.0;   // 绝对大气压 [Pa]，域 50000~120000
    fRh      : LREAL := 50.0;       // 相对湿度 [%]，域 0.0~100.0
END_VAR
VAR_OUTPUT
    fDensity    : LREAL;            // 湿空气密度 [kg/m³]
    fSatPressPa : LREAL;            // 饱和蒸汽压 [Pa]（诊断/复用出口）
    fVapPressPa : LREAL;            // 水蒸气分压 [Pa]
    bValid      : BOOL;             // 计算有效（入参域全部合法）
    uErrorId    : UDINT;            // 事件码，0 = 无事件
END_VAR
VAR CONSTANT
    DL_R_DRY    : LREAL := 287.058;      // 干空气比气体常数 [J/(kg·K)]
    DL_R_VAP    : LREAL := 461.495;      // 水蒸气比气体常数 [J/(kg·K)]
    DL_KELVIN   : LREAL := 273.15;       // 摄氏→开尔文偏移 [K]
    DL_MAGNUS_A : LREAL := 17.62;        // Magnus 系数 A [-]
    DL_MAGNUS_B : LREAL := 243.12;       // Magnus 系数 B [°C]
    DL_MAGNUS_C : LREAL := 611.2;        // Magnus 基准饱和压 [Pa]（0 °C 时）
    DL_T_MIN    : LREAL := -40.0;        // 温度下限 [°C]
    DL_T_MAX    : LREAL := 120.0;        // 温度上限 [°C]
    DL_P_MIN    : LREAL := 50000.0;      // 压力下限 [Pa]
    DL_P_MAX    : LREAL := 120000.0;     // 压力上限 [Pa]
    DL_RH_MIN   : LREAL := 0.0;          // 湿度下限 [%]
    DL_RH_MAX   : LREAL := 100.0;        // 湿度上限 [%]
    DL_FLOAT_EPS: LREAL := 1.0E-9;       // 浮点容差
END_VAR
```

**算法要点**
1. 域校验（信息级，钳位后继续算）：`fTempC` 越界钳位 → `16#0002_1E01`；`fPressPa` 越界钳位 → `16#0002_1E02`；`fRh` 越界钳位 → `16#0002_1E03`。三者任一钳位 → `bValid := FALSE`（结果仍输出，标注「近似」语义）。
2. 饱和蒸汽压（Magnus-Tetens，Pa）：`fSatPressPa := DL_MAGNUS_C * EXP((DL_MAGNUS_A * fTempC) / (DL_MAGNUS_B + fTempC));`——分母 `243.12 + fTempC` 在 -40 °C 时为 203.12 > 0，温度下限保证不除零（注释写明该保证）。
3. 水蒸气分压：`fVapPressPa := fSatPressPa * fRh / 100.0;`
4. 干空气分压：`fPDry := fPressPa - fVapPressPa;` **必须**防负：`IF fPDry <= 0.0 THEN fPDry := 0.0; bValid := FALSE; uErrorId := 16#0002_1E04; END_IF`（高湿低压极端工况会出现 `p_v > p`，物理不可能但组态可能给出，禁止出现负密度）。
5. 密度：`fKelvin := fTempC + DL_KELVIN;`（`fKelvin >= 233.15 > 0`，由温度下限保证）→ `fDensity := fPDry / (DL_R_DRY * fKelvin) + fVapPressPa / (DL_R_VAP * fKelvin);`
6. 非有限入参 → `bValid := FALSE`、`uErrorId := 16#0002_1E10`、`fDensity := 0.0`（`RETURN 0`）。
7. 精度声明（头注释）：-10~50 °C 域内相对误差 < 0.5%（公开文献口径），超出域仅供趋势参考——这是本库对 OSCAT `AIR_DENSITY` 行为定义的**收窄**，按 R11 留档。

**码位表**：`16#0002_1E01` 温度钳位（信息级）｜`16#0002_1E02` 压力钳位（信息级）｜`16#0002_1E03` 湿度钳位（信息级）｜`16#0002_1E04` 干空气分压为负修正（信息级）｜`16#0002_1E10` 入参非有限（信息级，返回 0）。

**验收要点**
- V1（ISA 海平面标况）：`T=15, P=101325, RH=0` → `ρ ≈ 1.2250 kg/m³`（容差 2E-3）。
- V2（20 °C 干空气）：`T=20, P=101325, RH=0` → `ρ ≈ 1.2041 kg/m³`（容差 2E-3）。
- V3（加湿降密度）：`T=20, P=101325, RH=100` → 必须 **< V2 值**（水蒸气比干空气轻），差值量级约 -0.008 kg/m³。
- V4：`RH=150` → 钳到 100、码 `1E03`、`bValid=FALSE`。
- V5（负分压）：`T=120, P=50000, RH=100` → 触发 `1E04` 修正，`fDensity >= 0`（不得出现负值）。
- 机检：`EXP` 分母无常量为 0 风险；`DL_R_*` 常量带单位注释。

---

### 11. `I_DL_RfidReader` —— RFID 读写头标准抽象契约（T2-6 Rockwell AOI 开组 + T1-5 TcOpen 范式）

- 子库：**DL_Device** ｜ 类型：**INTERFACE** + 配套结构体/枚举（同文件） ｜ 预计行数：**200** ｜ 来源组标签：`tcopen-component`、`rockwell-aoi`、`device-abstraction`
- 功能描述：载具/托盘 RFID 读写头的标准契约。按本库接口三段式（结构体 + 只读属性 + 单发方法）组织，上层工站只依赖接口引用即可适配「串口读写头 / 工业以太网读写头 / IO-Link 读写头 / 仿真器」。
- **来源借鉴点（T2-6 Rockwell AOI 首次开组，硬性配额项）**：AOI 的**参数分段范式**——`In`（指令）/ `Out`（状态）/ `InOut`（诊断与组态结构，别名直通调用方内存）/ `Local`（不对外中间量）+ 外部访问等级（Input 只读 / Output 只读 / InOut 无外部访问 / Local 可读写）。本接口据此把「指令」「状态」「诊断」「组态」**四段分离**：方法 = In 段；只读属性 = Out 段；诊断结构体经属性整体回读 = InOut 段的本库等价封装；Local 段留给实现块。**只借分段组织与访问等级思想，Rockwell 的 UDT 布局、参数命名、AOI 内部逻辑零接触**（1756-PM010 为文档版权，clean-room）。
- **与既有件边界**：`I_DL_BarcodeScanner` 是**一维码扫描**（触发-应答握手，单向读）；本接口是**读写双向 + 载具数据区（分页/字块）+ 防重复读**。二者不做继承合并（方法语义与数据模型都不同）。

**契约规格**

```iecst
TYPE E_DL_RfidState : (
    eOffline  := 0,        // 未初始化/未上电
    eReady    := 10,       // 就绪，可受理指令
    eBusy     := 20,       // 指令执行中（互斥，禁止重入）
    eError    := 90,       // 故障，需 Reset 清除
    eNoTag    := 95        // 视野内无标签（非故障，业务态）
);
END_TYPE

TYPE ST_DL_RfidTag : STRUCT
    sTagId    : STRING(64);   // 标签唯一号 [ASCII]，空串 = 无标签
    sData     : STRING(64);   // 标签数据区内容 [ASCII/HEX 由组态定]
    uPage     : UINT;         // 数据页号 [页]，0 = 连续区
    nRssi     : INT;          // 信号强度 [dBm]，域 -90~0
    bValid    : BOOL;         // 本次读取有效
END_STRUCT
END_TYPE

TYPE ST_DL_RfidDiag : STRUCT
    uLastErrorId : UDINT;     // 末次故障码（实现块自定段位）
    nCommRetry   : INT;       // 通信重试次数 [次]
    nReadTotal   : DINT;      // 累计读成功次数 [次]
    nWriteTotal  : DINT;      // 累计写成功次数 [次]
    bAntennaOk   : BOOL;      // 天线自检通过
    tLastComm    : TIME;      // 末次成功通信距今时长 [ms]
END_STRUCT
END_TYPE

INTERFACE I_DL_RfidReader
// 只读属性（Out 段，R22：接口成员一律 PROPERTY GET，禁止同名 VAR_OUTPUT）
METHOD GetState : E_DL_RfidState        // 当前状态
METHOD GetTag : ST_DL_RfidTag           // 当前标签快照（读到后保持，R27）
METHOD GetDiag : ST_DL_RfidDiag         // 诊断结构整体回读（InOut 段等价物）
// 单发方法（In 段，全部非阻塞，返回 FALSE 时必须给出非零码）
METHOD Init : BOOL                      // 初始化，参数 VAR_IN_OUT 注入 ST_DL_RfidCfg
METHOD ReadTag : BOOL                   // 发起读标签（读 TagId + 数据区）
METHOD WriteTag : BOOL                  // 发起写数据区（内容经 VAR_IN_OUT ST_DL_RfidTag 注入）
METHOD Reset : BOOL                     // 清故障，回 eReady
END_INTERFACE
```

配套 `ST_DL_RfidCfg`（同文件发布）：`sAntennaNo : STRING(8)` 天线号 / `nPowerDbm : INT` 发射功率 [dBm] 域 0~30 / `tTimeout : TIME` 单次指令超时 [ms] 域 50ms~5s / `nMaxRetry : INT` 重试次数 [次] 域 0~5 / `bDupFilterEn : BOOL` 防重复读使能 / `tDupWindow : TIME` 重复读抑制窗 [ms]。

**方法与状态语义（实现块必须逐条保证）**
1. 未 `Init` 或 `Init` 失败时，除 `Reset` 与 `Get*` 外全部方法返回 FALSE 并给码，且**不改变**任何内部状态。
2. 所有方法为**非阻塞单发**：方法内仅登记请求 + 置内部标志，跨周期动作由实现块主体状态机执行（公约 3.4）。
3. `eBusy` 期间再调用 `ReadTag`/`WriteTag` → 返回 FALSE + 码（拒绝重入），不排队（读头硬件本就互斥）。
4. `eNoTag` 是**业务态不是故障**：不置 `bError`、不进 `eError`、不计入重试（R21 精神）。
5. 方法数 = 7（3 属性 + 4 方法），**恰在方法数红线 ≤ 6 之外**——裁定：属性不计入方法预算（与 `I_DL_MotionAxis` 同一口径），方法实为 4 个，红线满足。

**验收要点**
- 契约层：`INTERFACE` 内无变量声明（纯方法/属性签名）；`END_INTERFACE` 成对。
- 实现块（#12）必须覆盖全部 7 个成员，缺一即编译失败（机检：`IMPLEMENTS` 后的成员清单逐条比对）。
- 无码位（接口不带码），失败语义经返回值 + `ST_DL_RfidDiag.uLastErrorId`。

---

### 12. `FB_DL_RfidTagHandler` —— RFID 标签读写状态机实现（防重复读 + 重试链）

- 子库：**DL_Device** ｜ 类型：**FB**（`IMPLEMENTS I_DL_RfidReader`） ｜ 预计行数：**540** ｜ 来源组标签：`tcopen-component`、`rockwell-aoi`、`device-abstraction`、`state-machine`
- 功能描述：`I_DL_RfidReader` 的标准实现件。以「请求-执行-应答」三拍握手驱动外部读写头（硬件经引脚 `bHwReady`/`bHwDone`/`bHwError` + `sHwTagId`/`sHwData` 注入，**零硬编码地址**），内置：单指令互斥、超时→重试→耗尽报错链、同标签重复读抑制窗、写后回读校验、读写计数与诊断结构。
- **T2-6 借鉴落点**：AOI 的「ProgFault（组态/程序类故障）与 OperFault（工艺/操作类故障）分离」→ 本块把故障分为 **组态类**（`16#0003_02F0`~`02F1`：超时/重试参数非法、标签长度超限）与 **工艺类**（`02F2`~`02F3`：读头故障、写校验不符）。两类同置 `bError` 但**分开码段**，HMI 可据此决定「改参数」还是「叫维修」。**仅借分类思想，无任何 Rockwell 代码/UDT 结构接触。**

**引脚规格（对外引脚，接口成员以 PROPERTY GET 承载，R22）**

```iecst
FUNCTION_BLOCK FB_DL_RfidTagHandler IMPLEMENTS I_DL_RfidReader
VAR_INPUT
    bEnable      : BOOL := TRUE;     // 使能；FALSE → eOffline，方法全部拒绝
    // —— 硬件抽象层（由 IO 映射层或协议层注入，禁止绝对地址）——
    bHwReady     : BOOL;             // 读写头就绪反馈
    bHwDone      : BOOL;             // 本次指令执行完成（单拍或电平，内部取沿）
    bHwError     : BOOL;             // 读写头报错
    sHwTagId     : STRING(64);       // 读回的标签 UID [ASCII]
    sHwData      : STRING(64);       // 读回的数据区 [ASCII]
    uHwErrorCode : UDINT;            // 读写头原始错误码（透传进诊断，不改语义）
    tCmdTimeout  : TIME := T#500MS;  // 单指令超时 [ms]，域 50ms~5s
    nMaxRetry    : INT := 2;         // 重试次数 [次]，域 0~5
    bDupFilterEn : BOOL := TRUE;     // 同标签重复读抑制使能
    tDupWindow   : TIME := T#2S;     // 重复读抑制窗 [ms]，域 100ms~60s
END_VAR
VAR_OUTPUT
    bReadDoneOk  : BOOL;             // 读成功，单拍（R25 律①：主体前部预清零）
    bWriteDoneOk : BOOL;             // 写成功，单拍
    bNoTag       : BOOL;             // 视野内无标签（保持型业务态）
    bBusy        : BOOL;             // 指令执行中
    bError       : BOOL;             // 故障锁存（组态类 + 工艺类同置，码区分，R21）
    uErrorId     : UDINT;            // 事件码，0 = 无事件
    nRetryCnt    : INT;              // 本次指令已重试次数 [次]
END_VAR
VAR_IN_OUT
    stCfg        : ST_DL_RfidCfg;    // 组态（调用方持有，只读使用）
END_VAR
VAR
    fbTrigDone   : R_TRIG;           // 硬件完成沿
    fbTrigDup    : R_TRIG;           // 重复读抑制计时用边沿
    fbTmo        : TON;              // 单指令超时（主周期无条件刷新）
    fbDupTmo     : TON;              // 重复抑制窗计时
    bInit        : BOOL := FALSE;    // 首扫标志（R19）
    eState       : E_DL_RfidFsm;     // 主状态机（内部 5 态，经 GetState 映射为接口 5 态，见下）
    eReq         : E_DL_RfidReq;     // 挂起请求（none/read/write）
    sLastTagId   : STRING(64);       // 上次成功读取的标签 UID（重复抑制比对源）
    sWrBuffer    : STRING(64);       // 待写数据缓冲（写请求时锁存，防调用方中途改动）
    stTag        : ST_DL_RfidTag;    // 当前标签快照（属性出口）
    stDiag       : ST_DL_RfidDiag;   // 诊断结构（属性出口）
    bHwReq       : BOOL;             // 硬件请求输出（送 IO 层）
    bHwWr        : BOOL;             // 硬件写/读方向（FALSE=读，TRUE=写）
END_VAR
VAR CONSTANT
    DL_RFID_TMO_MIN : TIME := T#50MS;   // 超时下限 [ms]
    DL_RFID_TMO_MAX : TIME := T#5S;     // 超时上限 [ms]
    DL_RFID_DUP_MIN : TIME := T#100MS;  // 抑制窗下限 [ms]
    DL_RFID_DUP_MAX : TIME := T#60S;    // 抑制窗上限 [ms]
    DL_RFID_RETRY_MAX : INT := 5;       // 重试上限 [次]
    DL_STR_MAX      : INT := 64;        // 字符串域长度 [字符]
END_VAR
TYPE E_DL_RfidFsm : (
    eIdle     := 0,     // 待机，可受理请求
    eWaitHw   := 10,    // 已下发，等 bHwDone / bHwError / 超时
    eVerify   := 20,    // 写后回读校验
    eRetry    := 30,    // 重试退避（等一拍）
    eFault    := 99     // 故障锁定
);
END_TYPE
TYPE E_DL_RfidReq : ( eNone := 0, eRead := 1, eWrite := 2 ); END_TYPE
```

**状态机（`CASE` + `ELSE` 兜底，逐态写死）**
1. **首扫**（R19）：`IF NOT bInit THEN` 清 `eState := eIdle`、`eReq := eNone`、`nRetryCnt := 0`、`stDiag.* := 0`、`sLastTagId := ''`、`bInit := TRUE;`。
2. **单拍输出预清零**（R25 律①）：`bReadDoneOk := FALSE; bWriteDoneOk := FALSE;` 于主体首行。
3. **无条件刷新定时器**：`fbTmo(IN := (eState = eWaitHw), PT := 钳位后的 tCmdTimeout);` `fbDupTmo(IN := (sLastTagId <> ''), PT := 钳位后的 tDupWindow);`（在 `CASE` 之外，红线第 5 条）。
4. `eIdle`：若 `bEnable` 且 `bHwReady`，且有挂起请求（`eReq`）→ 下发 `bHwReq := TRUE`、`eState := eWaitHw`；`bNoTag := FALSE`（新指令开始清业务态）。
5. `eWaitHw`：`bBusy := TRUE`；`IF fbTrigDone.Q THEN` → 若 `bHwError` 或 `sHwTagId = ''` → 走 `eRetry`（无标签时**不计重试**，直接 `bNoTag := TRUE` 回 `eIdle`，语义见 I 接口第 4 条）；否则读请求 → 比对重复抑制窗：同 UID 且 `NOT fbDupTmo.Q` → 丢弃结果 + `16#0003_0138`（信息级）+ 回 `eIdle`；不同 UID → 锁存 `stTag`、`sLastTagId`、`nReadTotal + 1`、`bReadDoneOk := TRUE`、回 `eIdle`。写请求 → `eState := eVerify`（**不回 idle**）。
6. `eVerify`：比较 `sHwData` 与 `sWrBuffer`（字符串相等用标准 `=`，**字符串不是浮点**，可直接判等，注释写明）；一致 → `bWriteDoneOk := TRUE`、`nWriteTotal + 1`、回 `eIdle`；不一致 → 工艺类故障 `16#0003_02F3` 锁存 `eFault`。
7. `eRetry`：`nRetryCnt := nRetryCnt + 1;` 若 `nRetryCnt > 钳位后 nMaxRetry` → 组态类/工艺类分别：超时耗尽 → `16#0003_02F1`（组态类：超时太短或线缆问题）→ `eFault`；读写头报错耗尽 → `16#0003_02F2`（工艺类）→ `eFault`；否则 `eState := eWaitHw`（重新下发，退避一拍由 `eRetry` 单拍停留实现）。
8. `eFault`：`bError := TRUE`、输出 `bBusy := FALSE`；只有 `Reset()` 成功后可回 `eIdle`。
9. `ELSE`（非法枚举）：`eState := eFault; uErrorId := 16#0003_02F3; bError := TRUE;`。
10. **参数域校验（每拍）**：`tCmdTimeout` 越界 → 钳位 + `16#0003_0139`；`nMaxRetry` 越界 → 钳位 + `16#0003_013A`；`tDupWindow` 越界 → 钳位（并入 `0139`）。
11. **方法实现**（单发登记）：`ReadTag()`：若 `eState <> eIdle` → `stDiag.uLastErrorId := 16#0003_02F0`（组态/使用类：忙时重入）→ 返回 FALSE；否则 `eReq := eRead`、返回 TRUE。`WriteTag(VAR_IN_OUT stTagIn)`：锁存 `sWrBuffer := stTagIn.sData`；长度 > `DL_STR_MAX` → `02F0` 拒绝。`Reset()`：`eFault → eIdle`、`bError := FALSE`、`uErrorId := 0`、`nRetryCnt := 0`。
12. **属性 GET**（R22）：
    - `GetState` 映射表（**逐条写死，禁止「就近映射」**）：内部 `eIdle` → 接口 `eReady`（若 `bEnable` 且 `bHwReady`）或 `eOffline`（否则）；`eWaitHw`/`eVerify`/`eRetry` → `eBusy`；`eFault` → `eError`；`bNoTag = TRUE` 时无论内部态一律对外报 `eNoTag`（业务态优先级高于忙态，便于 HMI 直接提示「请放标签」）。
    - `GetTag` 返回 `stTag`（**保持型，R27**：读到后一直有效，直到下次成功读取覆盖）；
    - `GetDiag` 返回 `stDiag`（每拍更新 `tLastComm := 末次成功时刻距今`）；

**码位表**：`16#0003_0138` 同标签重复读被抑制（信息级）｜`16#0003_0139` 超时/抑制窗参数钳位（信息级）｜`16#0003_013A` 重试次数钳位（信息级）｜`16#0003_02F0` **组态/使用类**：忙时重入或写入数据超长（故障级）｜`16#0003_02F1` **组态类**：超时重试耗尽（故障级）｜`16#0003_02F2` **工艺类**：读写头报错重试耗尽（故障级）｜`16#0003_02F3` **工艺类**：写后回读校验不符 / 非法状态兜底（故障级）。

**验收要点**
- V1（读链）：`bHwReady=TRUE` → `ReadTag()` 返回 TRUE → 下一拍 `bHwReq=TRUE`、`bBusy=TRUE` → 给 `bHwDone` 一拍 + `sHwTagId='T001'` → `bReadDoneOk` **单拍**为 TRUE、`GetTag().sTagId='T001'`、`nReadTotal=1`。
- V2（防重复读）：2 s 内再读到 `'T001'` → `bReadDoneOk=FALSE`、码 `0138`；超过 `tDupWindow` 后同 UID 可再次成功。
- V3（无标签）：`bHwDone` 且 `sHwTagId=''` → `bNoTag=TRUE`、`bError=FALSE`、`nRetryCnt` **不减不加**（推演 3 次确认不累积）。
- V4（超时重试链）：不下发 `bHwDone`，`nMaxRetry=2` → 计时到 500 ms 进 `eRetry`，共 **3 次**下发（首发 + 2 重试）后 `eFault` + `02F1`（R13 逐拍推演，禁止只数「2 次」）。
- V5（写校验）：`WriteTag('AB')` 后 `sHwData='AC'` → `02F3` 锁存、`bWriteDoneOk=FALSE`。
- V6（忙时重入）：`eWaitHw` 期间再调 `ReadTag()` → FALSE + `02F0`。
- V7（R27 保持）：读成功后停 10 拍，`GetTag().bValid` 仍 TRUE、`sTagId` 不变。
- 机检：`fbTmo`/`fbDupTmo` 在 `CASE` 之外；`bReadDoneOk`/`bWriteDoneOk` 首行预清零；接口 7 成员全实现。

---

### 13. `FB_DL_AxiolineDiagLatch` —— Axioline 本地总线诊断锁存与定位（T1-7 开组）

- 子库：**DL_Device** ｜ 类型：**FB** ｜ 预计行数：**420** ｜ 来源组标签：`plcnext-community`、`diagnostic`、`fieldbus`
- 功能描述：把 Axioline F 本地总线的**诊断状态寄存器位域**与**诊断参数寄存器（错误码 + 槽号）**解析为工程师可直接读的分级诊断：总线级 / 模块级 / 通道级三档 + 首出故障槽号 + 错误码 + 锁存与复位语义。
- **T1-7 借鉴点（公开手册语义域）**：诊断状态寄存器的位定义（PF 外围故障 / PW 外围警告 / BUS 总线错误 / RUN 数据传输中 / ACT 组态就绪 / RDY 总线就绪 / SYSFAIL 系统故障），诊断参数寄存器给出**错误码**，扩展参数寄存器给出**错误位置（槽号，从 1 起）**，且「无法定位的接口错误」用 **128** 表示。**上述为 PLCnext 官方在线帮助公开的系统变量语义，本库只借位语义与「错误码 + 槽号」参数域，寄存器字宽、位序、枚举、码位与状态机 100% 自有**（输入以 `WORD`/`USINT` 引脚注入，不绑定任何厂商系统变量）。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_AxiolineDiagLatch
VAR_INPUT
    bEnable     : BOOL := TRUE;      // 使能；FALSE 时清所有输出（诊断不保持）
    uStatusWord : WORD;              // 诊断状态寄存器 [位串]，低字节/高字节已由 IO 层合并
    uErrCode    : WORD;              // 诊断参数寄存器：错误码 [代码]
    uErrSlot    : USINT;             // 扩展参数寄存器：错误位置槽号 [槽]，0/128 特例见算法
    bModuleReady: BOOL;              // 总线就绪（由 IO 层给，等价 RDY 位，冗余校验用）
    bAckDiag    : BOOL;              // 诊断确认，上升沿清「可确认」类诊断（硬件侧确认由 PDI 写完成，本块只清本地）
    bReset      : BOOL;              // 复位锁存（清首出与历史）
END_VAR
VAR_OUTPUT
    bBusError   : BOOL;              // 总线级故障（BUS 位）
    bPeriphFault: BOOL;              // 外围故障（PF 位）：模块/通道硬件错
    bPeriphWarn : BOOL;              // 外围警告（PW 位）
    bSysFail    : BOOL;              // 系统故障（SYSFAIL）
    bDiagActive : BOOL;              // 任一诊断有效（聚合位，HMI 单点用）
    eLevel      : E_DL_DiagLevel;    // 诊断等级（无/警告/故障/致命）
    nFirstSlot  : INT := -1;         // 首出故障槽号 [槽]，-1 = 无；128+ 表示「无法定位」
    uFirstCode  : WORD;              // 首出故障错误码 [代码]（与 nFirstSlot 同拍锁存）
    nEventCnt   : UDINT;             // 诊断事件累计次数 [次]（去抖后，防抖窗内不重复计）
    bLatchFull  : BOOL;              // 锁存已满（首出保持，需 bReset）
    uErrorId    : UDINT;             // 事件码，0 = 无事件
END_VAR
VAR
    fbTrigAck   : R_TRIG;            // 确认沿
    fbTrigReset : R_TRIG;            // 复位沿
    fbDebounce  : TON;               // 诊断稳定窗（防抖，主周期无条件刷新）
    bInit       : BOOL := FALSE;     // 首扫标志（R19）
    bLatched    : BOOL;              // 首出锁存有效
    nSlotLatch  : INT := -1;         // 锁存槽号
    uCodeLatch  : WORD;              // 锁存错误码
    eState      : E_DL_DiagFsm;      // 状态机
    uPrevStatus : WORD;              // 上拍状态字（变化检测）
END_VAR
VAR CONSTANT
    DL_BIT_PF      : WORD := 16#0001;   // 外围故障位（本库自有位序，注释标明与现场 IO 映射对照）
    DL_BIT_PW      : WORD := 16#0002;   // 外围警告位
    DL_BIT_BUS     : WORD := 16#0004;   // 总线错误位
    DL_BIT_RUN     : WORD := 16#0008;   // 数据传输中位
    DL_BIT_ACT     : WORD := 16#0010;   // 组态就绪位
    DL_BIT_RDY     : WORD := 16#0020;   // 总线就绪位
    DL_BIT_SYSFAIL : WORD := 16#0040;   // 系统故障位
    DL_SLOT_UNLOC  : USINT := 128;      // 无法定位标志 [槽]
    DL_SLOT_NONE   : USINT := 0;        // 无槽号
    DL_DEB_TIME    : TIME := T#200MS;   // 诊断稳定窗 [ms]
    DL_SLOT_MAX    : INT := 127;        // 有效槽号上限 [槽]
END_VAR
TYPE E_DL_DiagLevel : ( eNone := 0, eWarn := 10, eFault := 20, eFatal := 30 ); END_TYPE
TYPE E_DL_DiagFsm  : ( eIdle := 0, eMonitor := 10, eLatched := 20, eFault := 99 ); END_TYPE
```

**算法要点**
1. **位序声明（关键工程语义）**：本库常量位序为**自有定义**（PF=bit0…SYSFAIL=bit6），与 PLCnext 系统变量的寄存器高低字节拼接关系由**调用方在 IO 层完成**并在头注释给出对照表；本块不做字节序猜测（跨平台歧义禁令）。
2. 首扫（R19）：`IF NOT bInit THEN` 清锁存与计数、`eState := eIdle`、`bInit := TRUE;`。
3. 边沿无条件刷新：`fbTrigAck(CLK := bAckDiag); fbTrigReset(CLK := bReset);`
4. 防抖（红线：定时器主周期刷新）：`fbDebounce(IN := (uStatusWord <> uPrevStatus) OR 有诊断位, PT := DL_DEB_TIME);` 只有 `fbDebounce.Q` 才认为诊断**稳定成立**，防总线瞬断造成事件计数暴涨。
5. 分级判定（优先级从高到低，**先判致命**）：
   - `bSysFail` 或（`bBusError` 且 `NOT bModuleReady`）→ `eLevel := eFatal`；
   - 否则 `bPeriphFault` → `eFault`；否则 `bPeriphWarn` → `eWarn`；否则 `eNone`。
6. 槽号解析（三特例写死）：`uErrSlot = 0` → `nSlot := -1`（无位置）；`uErrSlot = 128` → `nSlot := 128`（无法定位，**保留原值**供 HMI 显示「定位失败」而非伪装成 128 号槽）；`uErrSlot > 127` 且 ≠128 → 视为非法 → `16#0003_013B`（信息级）并 `nSlot := -1`。
7. 首出锁存（`eLevel <> eNone` 且 `NOT bLatched`）→ 锁存 `nSlotLatch := nSlot`、`uCodeLatch := uErrCode`、`bLatched := TRUE`、`nEventCnt + 1`、`eState := eLatched`；**锁存后新诊断不覆盖**（首因追踪，与 `FB_DL_InterlockMatrix` 首出思想一致但独立实现）。
8. 确认与复位：`bAckDiag` 沿 → 清 `bDiagActive` 相关显示位但**不清锁存**（首出必须留到复位，现场排故需要）；`bReset` 沿 → 清锁存、`eState := eMonitor`、`nFirstSlot := -1`、`uErrorId := 0`。
9. 输出每拍重写（R27）：`bDiagActive := bBusError OR bPeriphFault OR bPeriphWarn OR bSysFail;` `bLatchFull := bLatched;` `nFirstSlot := nSlotLatch;`
10. `CASE ... ELSE` 兜底 → `eState := eFault`、`16#0003_02F5`。
11. 未使能（`bEnable = FALSE`）：全输出清 0、锁存**保持**（不掉历史），置 `16#0003_013C`（信息级）。

**码位表**：`16#0003_013B` 槽号非法（信息级，按无位置处理）｜`16#0003_013C` 诊断块未使能（信息级）｜`16#0003_02F4` 诊断生效但错误码为 0（故障级：状态位与参数寄存器不自洽，提示组态/映射错）｜`16#0003_02F5` 非法状态兜底（故障级）｜`16#0003_02F6` 总线就绪丢失超时（故障级：诊断有效而 `bModuleReady` 长时间为 FALSE）。

**验收要点**
- V1：`uStatusWord = 16#0001`（PF）+ `uErrCode=16#0102` + `uErrSlot=3` → 稳定 200 ms 后 `eLevel=eFault`、`nFirstSlot=3`、`uFirstCode=16#0102`、`nEventCnt=1`。
- V2（首出不覆盖）：随后来 `uErrSlot=7, uErrCode=16#0204` → `nFirstSlot` 仍 **3**（首因）。
- V3（无法定位）：`uErrSlot=128` → `nFirstSlot=128`（不得变成 -1 或 28）。
- V4（致命优先）：`uStatusWord = 16#0044`（BUS + SYSFAIL）→ `eLevel=eFatal`（不是 eFault）。
- V5（防抖）：状态字 100 ms 内抖动 5 次 → `nEventCnt` 只 +1（推演确认，R13）。
- V6（复位）：`bReset` 一拍 → `nFirstSlot=-1`、`nEventCnt` 保持（计数值不清，只清锁存），`uErrorId=0`。
- 机检：`fbDebounce` 在 `CASE` 外；每档分级 IF 顺序与规格一致；128 特例分支存在。

---

### 14. `FB_DL_PdiReadScheduler` —— PDI 无环读取调度器（槽/子槽/索引/子索引 + 双码域）

- 子库：**DL_Device** ｜ 类型：**FB** ｜ 预计行数：**520** ｜ 来源组标签：`plcnext-community`、`diagnostic`、`scheduler`
- 功能描述：面向「参数 / 诊断 / 信息（PDI）」类**无环（acyclic）**读取的通用调度器。把「请求描述域（槽 / 子槽 / 索引 / 子索引）+ 结果域（错误码 / 附加信息 / 数据长度）」抽象成与具体总线无关的调度件，硬件经抽象桩引脚（`bSrvReady` / `bSrvDone` / `uSrvError` / `uSrvAddInfo` / `uSrvLen`）注入，**换 RTU/TCP/本地总线只换传输层，调度层零改动**——与已入库 `FB_DL_ModbusPollMaster`（R9，帧级轮询）同构但**对象不同**（本件是对象字典级 PDI，不触碰帧）。
- **T1-7 借鉴点（公开文档语义域）**：PLCnext RSC 的 `PdiParam`（Slot 设备号 / Subslot 子设备号 / Index 对象索引 / Subindex 对象子索引）与 `PdiResult`（ErrorCode / AddInfo 双层错误码）参数域，以及「无环通信执行耗时较长，禁止在实时任务中直接调用」的**工程纪律**（本块以「单拍只发一条 + 忙时拒绝」实现，不阻塞）。**仅借参数域与纪律，结构体布局、状态机、码位自有。**

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_PdiReadScheduler
VAR_INPUT
    bEnable      : BOOL := TRUE;     // 使能
    bStart       : BOOL;             // 启动单次读取，上升沿（忙时忽略并计一次拒绝）
    uSlot        : UINT := 0;        // 设备号（槽）[号]，域 0~DL_SLOT_MAX
    uSubslot     : UINT := 1;        // 子设备号（子槽）[号]，域 0~DL_SUBSLOT_MAX
    uIndex       : UINT := 0;        // 对象索引 [索引]，域 0~16#FFFF
    uSubindex    : USINT := 0;       // 对象子索引 [子索引]，域 0~255
    nExpLen      : INT := 0;         // 期望数据长度 [字节]，域 0~DL_DATA_MAX（0 = 不限）
    tTimeout     : TIME := T#1S;     // 单次超时 [ms]，域 100ms~10s
    nMaxRetry    : INT := 0;         // 重试次数 [次]，域 0~3（PDI 重试须保守）
    // —— 传输层抽象桩（由派生/IO 层实现，本块只调用不实现）——
    bSrvReady    : BOOL;             // 服务就绪
    bSrvDone     : BOOL;             // 服务完成
    uSrvError    : WORD;             // 服务错误码（ErrorCode）
    uSrvAddInfo  : WORD;             // 服务附加信息（AddInfo）
    uSrvLen      : UINT;             // 实际返回数据长度 [字节]
END_VAR
VAR_OUTPUT
    bReqActive   : BOOL;             // 请求已下发（送传输层的启动信号）
    bDone        : BOOL;             // 本次读取完成，单拍（成功或失败均置，R25）
    bSuccess     : BOOL;             // 本次读取成功（bDone 同拍有效）
    uErrCode     : UDINT;            // 双层错误码打包：高 16 位 AddInfo，低 16 位 ErrorCode
    uActLen      : UINT;             // 实际数据长度 [字节]
    nRejectCnt   : UDINT;            // 忙时拒绝启动次数 [次]
    nOkCnt       : UDINT;            // 成功次数 [次]
    nFailCnt     : UDINT;            // 失败次数 [次]（含重试耗尽）
    uErrorId     : UDINT;            // 事件码，0 = 无事件
    bError       : BOOL;             // 故障锁存（仅故障级，R21）
END_VAR
VAR
    fbTrigStart  : R_TRIG;           // 启动沿
    fbTrigDone   : R_TRIG;           // 完成沿
    fbTmo        : TON;              // 超时（主周期无条件刷新）
    bInit        : BOOL := FALSE;    // 首扫标志（R19）
    eState       : E_DL_PdiFsm;      // 状态机
    nRetry       : INT;              // 已重试次数 [次]
    uReqSlot     : UINT;             // 锁存请求域（防止执行中调用方改动）
    uReqSub      : UINT;
    uReqIdx      : UINT;
    uReqSubIdx   : USINT;
END_VAR
VAR CONSTANT
    DL_SLOT_MAX    : UINT := 4095;      // 槽号上限 [号]
    DL_SUBSLOT_MAX : UINT := 255;       // 子槽上限 [号]
    DL_DATA_MAX    : INT  := 1024;      // 单次数据长度上限 [字节]
    DL_TMO_MIN     : TIME := T#100MS;   // 超时下限 [ms]
    DL_TMO_MAX     : TIME := T#10S;     // 超时上限 [ms]
    DL_RETRY_MAX   : INT  := 3;         // 重试上限 [次]
END_VAR
TYPE E_DL_PdiFsm : (
    eIdle    := 0,     // 待机
    eSend    := 10,    // 锁存请求域并下发（单拍）
    eWait    := 20,    // 等待完成/超时
    eRetry   := 30,    // 重试退避
    eFault   := 99     // 故障锁定
);
END_TYPE
```

**状态机与算法要点**
1. 首扫（R19）+ 单拍预清零（R25 律①）：`bDone := FALSE; bSuccess := FALSE;` 主体首行。
2. 边沿与定时器无条件刷新：`fbTrigStart(CLK := bStart); fbTrigDone(CLK := bSrvDone); fbTmo(IN := (eState = eWait), PT := 钳位 tTimeout);`
3. 参数域钳位（每拍，信息级）：`uSlot` 越界 → `16#0003_013D`；`uIndex/uSubindex` 越界 → `16#0003_013E`；`nExpLen` 越界 → `16#0003_013F`。钳位后**只在 `bStart` 沿锁存**进 `uReq*`（执行中不跟随入参变化）。
4. `eIdle`：`IF fbTrigStart.Q THEN` 若 `NOT bEnable OR NOT bSrvReady` → `bDone := TRUE`（失败完成）、`uErrCode := 16#0000_0004`（服务不可用，自有码，非 PDI 码）、`nFailCnt + 1`；否则 → `eSend`。若 `bStart` 上升沿但 `eState <> eIdle`（忙）→ `nRejectCnt + 1`、`bReqActive := FALSE`、**不排队**（无环通信排队会拖尾，注释写明）。
5. `eSend`：锁存 `uReq*` ← 入参，`bReqActive := TRUE`、`eState := eWait`（单拍态，保证「下发」与「等待」分离）。
6. `eWait`：`IF fbTrigDone.Q THEN` → 成功判据 = `uSrvError = 0` 且（`nExpLen = 0` 或 `uActLen >= 期望`）；成功 → `bSuccess := TRUE`、`bDone := TRUE`、`nOkCnt + 1`、`uErrCode := 打包(uSrvAddInfo, uSrvError)`、回 `eIdle`；失败 → 若 `nRetry < 钳位后 nMaxRetry` → `nRetry + 1`、`eRetry`；否则 `bDone := TRUE`、`nFailCnt + 1`、`uErrCode := 打包(...)`、码 `16#0003_02F7`（故障级：PDI 读失败耗尽）→ `eIdle`（**不锁死**，与 ModbusPollMaster 的「记账不停摆」同纪律），仅当同一请求连续 3 轮失败才 `eFault`。
7. 超时：`fbTmo.Q` → 同失败分支，但 `uSrvError` 用自有码 `16#0000_0005`（超时），`bReqActive := FALSE`（撤回请求）。
8. `eRetry`：单拍停留（退避），清 `bReqActive`，下一拍回 `eSend`（重新锁存**同一**请求域，不是入参当前值）。
9. `eFault`：`bError := TRUE`；`bEnable` 下降沿或 `nFailCnt` 清零动作可退出（本块提供 `Reset` 语义经 `bStart` 在 `eFault` 下的**长按 3 拍**？禁止隐式手势——改为：`eFault` 只由 `bEnable` 的 FALSE→TRUE 沿复位，写入注释）。
10. `ELSE` 兜底：`eState := eFault; uErrorId := 16#0003_02F8; bError := TRUE;`
11. 码打包：`uErrCode := SHL(WORD_TO_UDINT(uSrvAddInfo), 16) OR WORD_TO_UDINT(uSrvError);`（显式类型转换，禁隐式；注释给出解包示例）。

**码位表**：`16#0003_013D` 槽/子槽钳位（信息级）｜`16#0003_013E` 索引/子索引钳位（信息级）｜`16#0003_013F` 期望长度钳位（信息级）｜`16#0003_02F7` PDI 读取失败/超时耗尽（故障级）｜`16#0003_02F8` 非法状态兜底（故障级）｜`16#0003_02F9` 连续三轮失败锁定（故障级）。

**验收要点**
- V1（成功链）：`bSrvReady=TRUE`、域合法 → `bStart` 一拍 → `bReqActive=TRUE`（单拍 `eSend` 后保持到完成）→ `bSrvDone` 一拍 + `uSrvError=0` + `uSrvLen=4` → `bDone` 单拍、`bSuccess=TRUE`、`nOkCnt=1`。
- V2（忙时拒绝）：`eWait` 期间再 `bStart` → `nRejectCnt=1`、`bReqActive` 不变、**不排队**（完成后 `nOkCnt` 仍只 +1）。
- V3（重试）：`nMaxRetry=1`、首两次 `uSrvError=16#0080` → 共 **2 次**下发后 `bDone=TRUE`、`bSuccess=FALSE`、`nFailCnt=1`、码 `02F7`。
- V4（超时）：不下发 `bSrvDone`，`tTimeout=1s` → 1 s 后失败完成、`uErrCode` 低 16 位 = `16#0005`、`bReqActive=FALSE`。
- V5（打包解包）：`uSrvError=16#8011, uSrvAddInfo=16#0002` → `uErrCode = 16#0002_8011`（人工验算）。
- V6（长度不符）：`nExpLen=8, uSrvLen=4, uSrvError=0` → 判失败（不得只看 ErrorCode）。
- 机检：`SHL` 前有显式 `WORD_TO_UDINT`；`fbTmo` 在 `CASE` 外；`bDone/bSuccess` 首行预清零。

---

### 15. `FB_DL_WindingTraverse` —— 收卷卷径递推 + 横动排线控制

- 子库：**DL_Motion** ｜ 类型：**FB** ｜ 预计行数：**560** ｜ 来源组标签：`lgf-technology`、`s7-motion`、`web-handling`、`state-machine`
- 功能描述：卷绕工位的「卷径 + 排线」双职责块（**双职责但同属一个物理工艺对象**，边界在结构上分离为两个子段，避免拆成两个必须共享卷径状态的块）：① 卷径递推（层厚积分法：`D = D_core + 2·h·N`，N 由收卷圈数累积）；② 横动排线（排线轴往复：行程由卷宽与排线宽决定，节距由线径与排线角决定，端点换向带减速与 dwell）。**卷径由引脚注入亦可**（`bUseInjectedDia` 为输入选择，非 MODE——两路数据源竞争由明确优先级仲裁，语义单一）。
- **与既有件边界**：`FC_DL_CoilDiameterCalc`（#9）是**瞬时几何反算**（纯函数，无状态）；本块是**递推 + 执行**（有状态，出排线轴指令）。两者互为校验（可用 `fDiaInjected` 注入 FC 结果做比对），**代码零调用**（泳道禁令）。`FB_DL_SingleAxis`/`FB_DL_AxisRelativeMove` 是通用轴件；本块只出**排线目标与方向**，轴执行由上层注入的轴实例负责（`I_DL_MotionAxis` 引用，不内联轴逻辑）。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_WindingTraverse
VAR_INPUT
    bEnable        : BOOL := TRUE;      // 使能
    bStart         : BOOL;              // 启动卷绕（上升沿），进入 eWinding
    bStop          : BOOL;              // 停止（电平），任一态 → eStopping
    bReset         : BOOL;              // 复位故障与卷径计数
    // —— 卷径数据源 ——
    bUseInjectedDia: BOOL := FALSE;     // TRUE = 采用 fDiaInjected（外部反算/测径仪）；FALSE = 内部层厚递推
    fDiaInjected   : LREAL := 0.0;      // 注入卷径 [m]，域 0.01~3.0（bUseInjectedDia 时有效）
    fCoreDia       : LREAL := 0.100;    // 卷芯直径 [m]，域 0.01~1.0
    fThickness     : LREAL := 0.0001;   // 材料厚度 [m]，域 1E-6~0.01
    fLineSpeed     : LREAL := 0.0;      // 材料线速度 [m/min]，域 0~3000（圈数累积用）
    fTaskCycle     : LREAL := 0.01;     // 任务周期 [s]，域 1ms~1s
    // —— 排线参数 ——
    fWebWidth      : LREAL := 0.5;      // 卷材宽度 [m]，域 0.01~5.0
    fTraverseWidth : LREAL := 0.5;      // 排线行程 [m]，域 0.01~5.0（一般 = 卷宽 - 材宽）
    nPitchPerRev   : LREAL := 1.0;      // 每圈排线节距 [mm/圈]，域 0.1~50.0
    fTraverseSpeedMax : LREAL := 0.5;   // 排线轴最大速度 [m/s]，域 0.01~5.0
    tDwellEnd      : TIME := T#100MS;   // 端点停留（换向 dwell）[ms]，域 0~2s
    // —— 轴接口（注入，零硬编码）——
    bAxisReady     : BOOL;              // 排线轴就绪
    fAxisPos       : LREAL;             // 排线轴当前位置 [m]
    bAxisInPos     : BOOL;              // 排线轴到位
END_VAR
VAR_OUTPUT
    fDia           : LREAL;             // 当前卷径 [m]（仲裁后）
    fDiaRate       : LREAL;             // 卷径变化率 [m/s]
    nRevolutions   : LREAL;             // 累计圈数 [圈]（含小数）
    fTargetPos     : LREAL;             // 排线轴目标位置 [m]，0~fTraverseWidth
    nDir           : INT;               // 排线方向（+1 / -1），0 = 停止
    bAtEndA        : BOOL;              // 已到 A 端（0 位）
    bAtEndB        : BOOL;              // 已到 B 端（行程末端）
    eState         : E_DL_WindState;    // 当前状态（对外可观测）
    bRunning       : BOOL;              // 卷绕运行中
    bError         : BOOL;              // 故障锁存
    uErrorId       : UDINT;             // 事件码，0 = 无事件
END_VAR
VAR
    fbTrigStart    : R_TRIG;            // 启动沿
    fbTrigReset    : R_TRIG;            // 复位沿
    fbDwell        : TON;               // 端点停留计时（主周期无条件刷新）
    bInit          : BOOL := FALSE;     // 首扫标志（R19）
    eState         : E_DL_WindState;    // 唯一主状态机（内外同枚举，对外直接可观测）
    fDiaInt        : LREAL := 0.0;      // 内部递推卷径 [m]
    fRevAcc        : LREAL := 0.0;      // 圈数累积 [圈]
    fRevDelta      : LREAL := 0.0;      // 本拍圈增量 [圈]（排线位移的唯一来源，禁重复积分）
    fTravPos       : LREAL := 0.0;      // 排线轴内部当前位置 [m]，域 0~fTraverseWidth
    nDirInt        : INT := 1;          // 排线方向内部量 [±1]，0 = 停止
    fPrevDia       : LREAL := 0.0;      // 上拍卷径（变化率用）
    bDwellActive   : BOOL;              // 端点停留中
END_VAR
VAR CONSTANT
    DL_PI          : LREAL := 3.141592653589793; // π [-]
    DL_DIA_MIN     : LREAL := 0.01;     // 卷径下限 [m]
    DL_DIA_MAX     : LREAL := 3.0;      // 卷径上限 [m]
    DL_LINE_MAX    : LREAL := 3000.0;   // 线速度上限 [m/min]
    DL_PITCH_MIN   : LREAL := 0.1;      // 节距下限 [mm/圈]
    DL_PITCH_MAX   : LREAL := 50.0;     // 节距上限 [mm/圈]
    DL_MM2M        : LREAL := 0.001;    // 毫米→米 [m/mm]
    DL_FLOAT_EPS   : LREAL := 1.0E-9;   // 浮点容差
    DL_DWELL_MAX   : TIME  := T#2S;     // 端点停留上限 [ms]
END_VAR
TYPE E_DL_WindState : (
    eIdle     := 0,                     // 待机（未启动/已停止）
    eWinding  := 10,                    // 卷绕 + 排线推进
    eDwelling := 20,                    // 端点停留（换向前）
    eStopping := 30,                    // 停止收尾
    eFault    := 99                     // 故障锁定
);
END_TYPE
```

**状态机（`ENUM` + `CASE` + `ELSE`，逐态写死；唯一主状态机枚举 `E_DL_WindState`，内外共用，禁止再设第二套 FSM 枚举）**
1. **首扫**（R19）：`IF NOT bInit THEN` `fDiaInt := fCoreDia`、`fRevAcc := 0`、`fTravPos := 0`、`nDirInt := 1`、`fPrevDia := fCoreDia`、`eState := eIdle`、`bInit := TRUE;`。
2. **边沿/定时器无条件刷新**：`fbTrigStart(CLK := bStart); fbTrigReset(CLK := bReset); fbDwell(IN := bDwellActive, PT := MIN(tDwellEnd, DL_DWELL_MAX));`
3. **参数域校验（每拍，信息级）**：`fCoreDia/fThickness/fLineSpeed/fTaskCycle` 越界钳位 → `16#0004_01B0`；`fTraverseWidth/nPitchPerRev` 越界钳位 → `16#0004_01B1`；`fDiaInjected` 在 `bUseInjectedDia` 下越界 → `16#0004_01B2` 并**忽略注入值回落递推**（绝不允许 0 卷径入控制）。任一入参非有限值 → `16#0004_02C0` + `eState := eFault`。
4. `eIdle`：`fbTrigStart.Q AND bEnable` → 若 `NOT bAxisReady` 则 `16#0004_01B3`（信息级，拒绝启动不锁故障）并留在 `eIdle`；否则 `eState := eWinding`。
5. `eWinding`（**每拍固定次序：先算圈增量 → 再仲裁卷径 → 再推排线 → 最后出目标**）：
   - 圈增量（**唯一积分，禁止在两处各积一次**）：
     `fRevDelta := (fLineSpeed / 60.0) / (DL_PI * MAX(fDiaInt, DL_DIA_MIN)) * fTaskCycle;`（线速度 [m/min] ÷ 60 → [m/s]，除周长 [m] → [圈/s]；`MAX` 保证分母 ≥ 0.01，除零守卫）
     `fRevAcc := fRevAcc + fRevDelta;`
   - 卷径仲裁：`IF bUseInjectedDia AND (fDiaInjected >= DL_DIA_MIN) THEN fDia := LIMIT(DL_DIA_MIN, fDiaInjected, DL_DIA_MAX);`（外部值**只做输出**，内部累积仍继续 → 切回递推时无跳变）`ELSE fDiaInt := LIMIT(DL_DIA_MIN, fCoreDia + 2.0 * fThickness * fRevAcc, DL_DIA_MAX); fDia := fDiaInt; END_IF`
   - 排线推进（位移 = 圈增量 × 节距，节距 [mm/圈] → ×`DL_MM2M` → [m/圈]）：
     `fTravPos := fTravPos + INT_TO_LREAL(nDirInt) * fRevDelta * nPitchPerRev * DL_MM2M;`
     `IF fTravPos >= fTraverseWidth THEN fTravPos := fTraverseWidth; bAtEndB := TRUE; bDwellActive := TRUE; eState := eDwelling;`
     `ELSIF fTravPos <= 0.0 THEN fTravPos := 0.0; bAtEndA := TRUE; bDwellActive := TRUE; eState := eDwelling; END_IF`
   - 输出：`fTargetPos := fTravPos; nDir := nDirInt;`
6. `eDwelling`：`bDwellActive` 已置位；`fbDwell.Q` → `nDirInt := -nDirInt;`（方向取反）、`bAtEndA := FALSE; bAtEndB := FALSE;`（**每拍重写的保持位，R27**）、`bDwellActive := FALSE;`、`eState := eWinding;`
7. `eStopping`：`nDir := 0`、`bRunning := FALSE`；轴不回零（由上层决定）、`bDwellActive := FALSE`、`eState := eIdle;`
8. `eFault`：`bError := TRUE`、`nDir := 0`、`bDwellActive := FALSE`；仅 `fbTrigReset.Q`（且入参已回域）可退 `eIdle` 并清 `bError`。
9. **停止优先**：`bStop` 电平在 `eWinding`/`eDwelling` 下先于 `CASE` 判（`IF bStop AND (eState = eWinding OR eState = eDwelling) THEN eState := eStopping; END_IF`），确保任何运行态都能停。
10. `ELSE` 兜底：`eState := eFault; uErrorId := 16#0004_02C1; bError := TRUE;`
11. 输出每拍重写（R27）：`bRunning := (eState = eWinding OR eState = eDwelling);` `fDiaRate := (fDia - fPrevDia) / MAX(fTaskCycle, 0.001);`（除零守卫）→ **先算变化率再更新** `fPrevDia := fDia;`（次序写死，颠倒会产生恒 0 变化率）。
12. 到位超时监视（`16#0004_02C2`）：`nDir <> 0` 且 `NOT bAxisInPos` 持续超过 `2 × fTraverseWidth / fTraverseSpeedMax`（按 ΔT 累加，除数已被域钳位保证 ≥ 0.01）→ 故障级。

**码位表**：`16#0004_01B0` 卷径/厚度/线速度钳位（信息级）｜`16#0004_01B1` 排线参数钳位（信息级）｜`16#0004_01B2` 注入卷径越界回落递推（信息级）｜`16#0004_01B3` 排线轴未就绪拒绝启动（信息级）｜`16#0004_02C0` 参数非有限（故障级）｜`16#0004_02C1` 非法状态兜底（故障级）｜`16#0004_02C2` 排线轴到位超时（故障级：`nDir≠0` 且 `bAxisInPos=FALSE` 超 `2×行程/速度`）｜`16#0004_02C3` 卷径递推不收敛（故障级：卷径达上限仍持续增圈）。

**验收要点**
- V1（递推）：`fCoreDia=0.1, fThickness=0.0001, fLineSpeed=10 m/min, fTaskCycle=0.01` 推 100 拍 → `nRevolutions ≈ 100·(10/60)/(π·0.1)·0.01 ≈ 0.53`，`fDia ≈ 0.1001`（容差 1E-4）。
- V2（注入仲裁）：`bUseInjectedDia=TRUE, fDiaInjected=0.5` → `fDia=0.5` 且内部 `fDiaInt` 仍随圈数增长（切回递推无跳变，推演 2 拍验证）。
- V3（排线到端）：`fTraverseWidth=0.2, nPitchPerRev=5` → 到达 0.2 时 `bAtEndB=TRUE`、`eState=eDwelling`、`fTargetPos=0.2`（不得越界）。
- V4（dwell 后换向）：`tDwellEnd=100ms` → 100 ms 后 `nDir=-1`、`bAtEndB=FALSE`、`eState=eWinding`。
- V5（轴未就绪）：`bAxisReady=FALSE` + `bStart` → 不进入 `eWinding`、码 `01B3`、`bError=FALSE`。
- V6（停止优先）：`eDwelling` 中 `bStop` 一拍 → 立即 `eStopping→eIdle`、`nDir=0`（不完成换向）。
- 机检：所有除法分母有 `MAX` 守卫；`fPrevDia` 更新在 `fDiaRate` 计算之后；三元分支无 MODE。

---

### 16. `FB_DL_PickAndPlaceStation` —— 三轴/气动拾放工站模板（OOP 依赖注入）

- 子库：**DL_Process** ｜ 类型：**FB** ｜ 预计行数：**560** ｜ 来源组标签：`packml-omac`、`tcopen-component`、`station-template`、`state-machine`
- 功能描述：标准「取-升-移-放」上下料工站模板：注入三轴（X/Y/Z）与真空发生器接口，按「下降-吸-确认-上升-横移-下降-破真空-上升-回原点」九步序执行单件搬运，含真空建立超时、工件在位确认、节拍统计与安灯级联出口。ROADMAP §6 P0 未注册项。
- **来源借鉴点**：PackML/OMAC 的「工站级状态语义」（Idle/Starting/Execute/Holding/Held/Stopping/Aborted 的最小可执行子集）→ 本块以 `E_DL_SpState` 落地 7 态（不做 17 态全集，全集已在 `FB_DL_PackMlStateMachine`，本块只做**工站内工序**，避免两套全状态机打架）；TcOpen 的「契约-实现分离 + 状态只读属性」思想 → 轴与真空全部经 `VAR_IN_OUT` 接口引用注入，**块内零硬件细节**。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_PickAndPlaceStation
VAR_INPUT
    bEnable       : BOOL := TRUE;      // 工站使能
    bStart        : BOOL;              // 启动单件循环（上升沿；eHeld 下无效）
    bHold         : BOOL;              // 保持（电平）：当前步完成后停在 eHeld
    bAbort        : BOOL;              // 中止（电平）：任何态 → eAborting → eIdle
    bReset        : BOOL;              // 复位故障
    bPartPresent  : BOOL;              // 取料位工件在位（光电）
    bPlaceClear   : BOOL;              // 放料位空闲（允许放料）
    bVacuumOk     : BOOL;              // 真空建立确认（真空开关）
    bZHomeOk      : BOOL;              // Z 轴原点/上限位就绪
    fPickZ        : LREAL := 0.0;      // 取料位下降目标 Z [mm]
    fPlaceZ       : LREAL := 0.0;      // 放料位下降目标 Z [mm]
    fTravelX      : LREAL := 100.0;    // 取→放 X 行程 [mm]
    fSpeed        : LREAL := 200.0;    // 运动速度 [mm/s]
    fAccel        : LREAL := 1000.0;   // 加减速度 [mm/s²]
    tGripTime     : TIME := T#200MS;   // 吸盘吸附建立时间 [ms]
    tBlowTime     : TIME := T#150MS;   // 破真空吹气时间 [ms]
    tStepTimeout  : TIME := T#5S;      // 单步超时 [ms]
    tCycleTimeout : TIME := T#30S;     // 整循环超时 [ms]
END_VAR
VAR_IN_OUT
    iAxisX        : I_DL_MotionAxis;   // X 轴接口引用（横向搬运）
    iAxisY        : I_DL_MotionAxis;   // Y 轴接口引用（可选，未用时可传同一实例或空实现）
    iAxisZ        : I_DL_MotionAxis;   // Z 轴接口引用（升降）
    iVacuum       : I_DL_VacuumGenerator; // 真空发生器接口引用（吸/破）
END_VAR
VAR_OUTPUT
    eState        : E_DL_SpState;      // 工站状态（对外可观测）
    nStepNo       : INT;               // 当前步号 [1~9]
    bCycleDone    : BOOL;              // 单件循环完成，单拍（R25 律①）
    bCycleOk      : BOOL;              // 本件合格（保持到下一件开始，R27）
    bPartLost     : BOOL;              // 搬运中真空丢失（掉件），保持
    bError        : BOOL;              // 故障锁存
    uErrorId      : UDINT;             // 事件码，0 = 无事件
    tCycleTime    : TIME;              // 上一件节拍 [ms]
    tCycleTimeAvg : TIME;              // 节拍移动平均（8 件窗）[ms]
    nOkCnt        : UDINT;             // 合格计数 [件]
    nNgCnt        : UDINT;             // 不合格计数 [件]
    bCallAndon    : BOOL;              // 需人工介入（缺料/掉件/超时），供安灯系统消費
END_VAR
VAR
    fbTrigStart   : R_TRIG;            // 启动沿
    fbTrigReset   : R_TRIG;            // 复位沿
    fbStepTmo     : TON;               // 单步超时（主周期无条件刷新）
    fbCycleTmo    : TON;               // 整循环超时
    fbGrip        : TON;               // 吸附建立计时
    fbBlow        : TON;               // 破真空计时
    bInit         : BOOL := FALSE;     // 首扫标志（R19）
    nStep         : INT := 0;          // 步号（0 = 无常驻步）
    bStepActive   : BOOL;              // 单步已执行（防重复下发，R24 精神）
    anCycleHistMs : ARRAY[0..7] OF DINT; // 节拍历史窗 [ms]（8 件，移动平均；存毫秒整数以避开 TIME 除法不可移植）
    nHistIdx      : INT := 0;          // 历史窗写指针
    nHistCnt      : INT := 0;          // 历史窗有效个数
END_VAR
VAR CONSTANT
    DL_STEP_NUM     : INT := 9;        // 总步数 [步]
    DL_HIST_LEN     : INT := 8;        // 节拍历史长度 [件]
    DL_SPEED_MIN    : LREAL := 1.0;    // 速度下限 [mm/s]
    DL_ACCEL_MIN    : LREAL := 10.0;   // 加速度下限 [mm/s²]
    DL_TMO_MAX      : TIME := T#60S;   // 超时上限 [ms]
END_VAR
TYPE E_DL_SpState : (
    eIdle     := 0,     // 待机（未启动）
    eStarting := 5,     // 启动自检（轴就绪 + 原点 + 放料位空闲）
    eExecute  := 10,    // 执行九步序
    eHolding  := 20,    // 保持中（当前步完成后停）
    eHeld     := 25,    // 已保持（bStart 无效，需 bHold 释放）
    eAborting := 30,    // 中止收尾（抬 Z、破真空）
    eFault    := 99     // 故障锁定
);
END_TYPE
(* 说明：本块只允许一个主状态机枚举。E_DL_SpState 即主状态机变量类型，且同名供 VAR_OUTPUT 对外可观测，
   禁止再声明第二套 FSM 枚举（库内公约 0.11 + 八条红线「一个功能块只允许一个主状态机」）。 *)
```

**九步序（`nStep` 语义，逐步行写死）；每步遵循「下发 → 等条件 → 单拍推进」三段式**
| 步 | 动作 | 完成条件 | 失败/超时处理 |
|---|---|---|---|
| 1 | Z 轴回/确认原点（`bZHomeOk`） | `bZHomeOk = TRUE` | 超 `tStepTimeout` → `01B0` + 保持态 |
| 2 | X 轴移动到取料位（位置 0） | `iAxisX.bInPos` | `tStepTimeout` → `02B0` |
| 3 | Z 下降至 `fPickZ` | `iAxisZ.bInPos` | 撞料/超时 → `02B1` |
| 4 | 真空吸（`iVacuum.Suck()`）+ 等 `tGripTime` 且 `bVacuumOk` | `fbGrip.Q AND bVacuumOk` | `bVacuumOk=FALSE` 超时 → **`nNgCnt+1`、`bCallAndon`、抬 Z 回步 1**（不锁故障，`01B1`） |
| 5 | Z 抬升至安全位 | `iAxisZ.bInPos` | `02B2` |
| 6 | X 横移至 `fTravelX` | `iAxisX.bInPos` | `02B3` |
| 7 | Z 下降至 `fPlaceZ` | `iAxisZ.bInPos`；每拍监控 `bVacuumOk`，掉真空 → `bPartLost` + `02B4` | 掉件 → 中止 |
| 8 | 破真空（`iVacuum.Blow()`）+ 等 `tBlowTime` | `fbBlow.Q` | 超时 → `02B5` |
| 9 | Z 抬升 + X 回原点 + 结算节拍 | 两轴 `bInPos` | 超时 → `02B6` |

**状态机与算法要点**
1. **首扫**（R19）：清 `nStep := 0`、`nOkCnt/nNgCnt`、`anCycleHistMs`、`nHistIdx/nHistCnt`、`eState := eIdle`、`bInit := TRUE`。
2. **单拍预清零**（R25 律①）：`bCycleDone := FALSE;` 首行。
3. **无条件刷新**：`fbTrigStart/fbTrigReset` 取沿；`fbStepTmo(IN := bStepActive, PT := MIN(tStepTimeout, DL_TMO_MAX))`；`fbCycleTmo(IN := (eState = eExecute), PT := MIN(tCycleTimeout, DL_TMO_MAX))`；`fbGrip/fbBlow` 按其触发标志刷新——**全部在 `CASE` 之外**。
4. **前置安全（每拍最先判）**：`bAbort` → `eState := eAborting`；`bHold` 且当前步完成 → `eState := eHolding`（单拍过渡）→ `eHeld`（`eHeld` 下 `bStart` 沿被丢弃，避免误重启）。
5. `eIdle`：`fbTrigStart.Q` 且 `bEnable` → `eStarting`；否则输出全保持（`bCycleOk` 也保持，R27）。
6. `eStarting`：自检 `bZHomeOk AND bPlaceClear AND bPartPresent`；任一不满足 → `bCallAndon := TRUE`、`16#0005_01B2`、回 `eIdle`（**不锁故障**：缺料是业务态，R21）；全满足 → `nStep := 1; bStepActive := FALSE; eState := eExecute;`
7. `eExecute`：按 `nStep` 推进（上表），每步只在 `NOT bStepActive` 时下发一次动作（`bStepActive := TRUE`），完成则 `nStep + 1`、`bStepActive := FALSE`；`nStep > 9` → 结算：`bCycleDone := TRUE`、`nOkCnt + 1`、`bCycleOk := TRUE`；节拍 `tCycleTime := fbCycleTmo.ET`（**用整循环超时定时器的 ET 作秒表**，避免读系统钟）；`anCycleHistMs[nHistIdx] := TIME_TO_DINT(tCycleTime)`（**转换口径见下条**）、`nHistIdx := (nHistIdx + 1) MOD DL_HIST_LEN`、`nHistCnt := MIN(nHistCnt + 1, DL_HIST_LEN)`；`tCycleTimeAvg` 重算（8 件窗算术平均，`DINT` 累加后 `DINT_TO_TIME(总和 / nHistCnt)`）、`nStep := 0`、`eState := eIdle`。
8. `eHolding` → `eHeld`（单拍过渡）；`eHeld`：所有轴保持当前位置（**不重发任何 Move**，避免保持态抖动），真空状态保持；`bHold` 释放 → `eExecute` 从当前步继续（**不重做已完成步**，`nStep` 不倒退）。
9. `eAborting`：抬 Z → 破真空 → 清 `bStepActive` → `eIdle`（逐拍推进，不得一个扫描周期内连发三条指令），置 `16#0005_01B3`（信息级：正常中止）。
10. `eFault`：`bError := TRUE`，`nStep := 0`，输出轴停止（经接口 `Stop()`，**只在进入 eFault 那一拍调用一次**）；仅 `bReset` 沿可退。
11. `ELSE` 兜底：`eState := eFault; uErrorId := 16#0005_02B7; bError := TRUE;`
12. **时间取整口径（可移植性，必须写入头注释）**：节拍以 `fbCycleTmo.ET`（TIME）为源，经 `TIME_TO_DINT()` 转毫秒整数入窗；该转换族在 CODESYS / TwinCAT 3 / InoProShop 三平台均提供，但**不属于 IEC 61131-3 基础类型转换表**，故：① 头注释标注「依赖平台 TIME↔DINT 转换族」；② 若目标平台缺失，改用 `DINT(TIME)` 显式语法并在头注释「规格偏离登记」留档（R11）；③ 禁止用 `TIME` 直接除以整数（`TIME / INT` 非标准，跨平台必翻）。
13. **接口调用纪律**：`iAxis*.MoveAbsolute(...)` 只在步起始拍调用一次（禁每拍重发，R24 家族）；`iVacuum.Suck()/Blow()` 同样单发；接口方法返回 FALSE 时读 `GetErrorId()` 透传进 `uErrorId` 高位（低 16 位为本块码），注释写明打包规则。

**码位表**：`16#0005_01B0` Z 轴原点未就绪超时（信息级，保持）｜`16#0005_01B1` 真空未建立（信息级，本件转 NG）｜`16#0005_01B2` 前置条件不满足（缺料/放料位占用，业务态 + 安灯）｜`16#0005_01B3` 正常中止完成（信息级）｜`16#0005_01B4` 节拍统计窗重建（信息级）｜`16#0005_02B0` X 轴取料位超时（故障级）｜`02B1` Z 轴下降超时｜`02B2` Z 轴抬升超时｜`02B3` X 轴横移超时｜`02B4` 搬运中掉件（故障级 + 安灯）｜`02B5` 破真空超时｜`02B6` 回原点超时｜`02B7` 非法状态兜底（故障级）。

**验收要点**
- V1（正常单件）：前置全满足 → `bStart` 一拍 → 步 1→9 逐拍推演，`bCycleDone` **单拍**、`nOkCnt=1`、`tCycleTime > 0`、`eState=eIdle`。
- V2（缺料）：`bPartPresent=FALSE` + `bStart` → 停 `eIdle`、`bCallAndon=TRUE`、码 `01B2`、`bError=FALSE`（业务态不锁故障）。
- V3（真空失败）：步 4 `bVacuumOk` 恒 FALSE 超 `tGripTime` → `nNgCnt=1`、`bCallAndon=TRUE`、**回步 1 而非锁死**、`eState≠eFault`。
- V4（掉件）：步 7 `bVacuumOk` 掉 → `bPartLost=TRUE`、`02B4`、转 `eAborting` 并抬 Z（推演 3 拍）。
- V5（保持/恢复）：`eExecute` 步 5 完成时 `bHold`=TRUE → `eHeld`；释放后从**步 6**继续（不重新执行步 5）。
- V6（超时）：步 6 不给 `bInPos`，`tStepTimeout=1s` → 1 s 后 `02B3` + `eFault` + `iAxisX.Stop()` 被调用一次（禁止每拍调用）。
- V7（节拍平均）：连做 9 件（> 8 窗）→ `tCycleTimeAvg` 仅为最近 8 件平均（人工构造 8/9 件数据验算）。
- 机检：接口方法调用点均在 `IF NOT bStepActive` 分支内；`fb*Tmo` 在 `CASE` 外；`bCycleDone` 首行预清零。

---

## 二、本轮机检与终审清单（编码完成后由终审环节执行）

| # | 检查项 | 口径 |
|---|---|---|
| 1 | 文件数 / POU 名 | 16 个 `.st`，文件名 = POU 名，`glob DL_*/**/*.st` 应为 152 |
| 2 | 被禁记号 | 全 16 件全文命中 = 0（全局变量表 / 外部变量声明 / 绝对地址） |
| 3 | 终结符成对（R18） | `END_FUNCTION` **7**（#1 #2 #4 #5 #6 #9 #10）/ `END_FUNCTION_BLOCK` **8**（#3 #7 #8 #12 #13 #14 #15 #16）/ `END_INTERFACE` **1** + `END_METHOD` **4** + `END_PROPERTY` **3**（#11）/ `END_TYPE` 与 `TYPE` 等量（共 13 个 `TYPE`） |
| 4 | 赋值目标声明性（R29） | 脚本对每个 `:=` 左侧标识符与声明区求差 = 0 |
| 5 | 码位跨文件重叠（R30） | 全库 152 件码位求交集 = **0**；R10 分配块与 0.6 表逐条一致 |
| 6 | 孤立分号（R26） | `;\s*$` 落在 `CASE`/`IF` 终端态 = 0 |
| 7 | 注释定界符平衡（R28） | `(*` 与 `*)` 计数相等；头注释示例内无嵌套 `(*` |
| 8 | 定时器位置 | 全部 `TON`/`TOF`/`TP`/`R_TRIG`/`F_TRIG` 调用点不在 `CASE`/`IF` 分支内 |
| 9 | 浮点判等 | 无 `fA = fB` 形式（脚本正则 + 人工目检）；字符串判等允许并注释说明 |
| 10 | 魔法数 | 阈值/限幅/超时全在 `VAR CONSTANT` 或引脚；`VAR CONSTANT` 块缺失 = 0 |
| 11 | 中文注释覆盖 | 声明区变量注释覆盖率 = 100%（脚本按声明行尾 `//` 统计） |
| 12 | 来源标签 | `function_tags` 必含 0.3 表列出的来源组标签（至少 1 个 `lgf-`/`oscat-`/`plcnext-community`/`tcopen-component`/`rockwell-aoi`） |
| 13 | 依赖方向 | 低层不引高层：A 泳道不引 B/C；B 不引 C；`DL_Process` 仅引已入库接口 |
| 14 | 验收向量 | 每件至少 4 组向量写入 `MANUAL_DL_*.md`；时序类（#3 #7 #8 #12 #13 #14 #15 #16）必须逐拍推演（R13） |
| 15 | 文档同步 | 6 个 `VERSION.md` + 6 个 `MANUAL_DL_*.md` + `CHANGELOG.md` + `README.md` + `LIBRARY_MANUAL.md` + `INDEX_REGISTRY.json`（136→152, v1.9.0）+ `_AI_Training_Dataset` jsonl（136→152） |

---

## 三、今日进度与追赶计划（2026-11-15）

### 3.1 当前差距（实测，非估算）

| 指标 | 实测 | 目标 | 差距 |
|---|---|---|---|
| 今日入库 | **110 件** | 200 件 | **-90 件**（达成率 **55.0%**） |
| 总库累计 | **136 件** | 10,000 件 | -9,864 件（1.36%） |
| 本轮计划 | 16 件 | — | 完成后今日 **126 件（63.0%）**，总库 **152 件（v1.9.0）** |
| 单轮产能（R7~R9 实测） | 16 件/轮 | — | 三轮恒定 16，未提升 |

### 3.2 差距归因（产品经理口径，三条，按影响排序）

1. **单轮产能锁死在 16 件**：R7/R8/R9 连续三轮 16 件，说明瓶颈不在「狩猎」也不在「规格」，而在**编码+终审的人力带宽**（每件平均 300~560 行，终审需逐行 + 逐拍推演）。今日剩余 90 件若维持 16/轮，需 **5.6 轮**（R11~R16），单轮周期约 2.5~3 h，即 14~17 h，**当日 200 件目标已不可达**——这是事实判断，必须写进日报而不是粉饰。
2. **P0 编译验证连续九轮悬置**：ROADMAP 自 R7 起标注「P0 编译验证第七/八/九次提醒」，至今未启动 CODESYS 最小工程真实编译。后果：终审只能靠静态机检 + 人工推演，R9 仍出 2 条致命缺陷（`BinarySearchLReal` 漏声明 `uErrorId`，三平台编译必败）。**每轮 16 件的「纸面产能」有真实返工成本隐藏在终审里**——这是产能上不去的结构性原因。
3. **Level 0 已近饱和，增量转向 Level 1/2 的边际成本更高**：本轮 A 泳道 6 件均为纯函数（单件 200~300 行、无需状态机），是**性价比最高的产能补充**；但 C 泳道（设备/运动/工艺）单件 400~560 行且需接口契约配套，占比越高，单轮总行数越高、终审越慢。R10 的 3:6 分配（A 6 / B 4 / C 6）已是当前带宽下的上限。

### 3.3 追赶安排（R11~R16，按优先级，不含未验证承诺）

| 轮次 | 组件量 | 主攻 | 目标累计（今日口径推演） |
|---|---|---|---|
| **R10（本轮）** | 16 | Level 0 数学/日历/计数回补 + T1-7 PLCnext 开组 + 工艺物理量链 + 拾放工站 | 126 / 200 |
| **R11** | **20~22**（若编译验证仍未启动则回落 16） | **先做 P0 编译验证**（最小工程 + 16 件回归向量），再落 LGF 剩余高频族（字符串族 / 绝对值与符号族 / 位段批量族）+ T2-6 Rockwell AOI 深化（设备 AOI 分段范式） | 146 / 200 |
| **R12** | 20 | `DL_Motion` 扩容（`FB_DL_UnwinderDiameterCalc` / `FB_DL_FilmWebCenter` / `FB_DL_StepperXyzGantry`）+ `DL_Device` 电表族（`I_DL_PowerMeter` + `FB_DL_ModbusPowerMeter`，ROADMAP 未注册） | 166 / 200 |
| **R13** | 20 | `DL_Process` 工站族补齐（`FB_DL_RotaryIndexTable` / `FB_DL_PressFitStation` / `FB_DL_EnergySavingMode` / `FB_DL_AgvDockingHandshake`）+ ISA-88 批次模型本体（`FB_DL_BatchPhaseBase`） | 186 / 200 |
| **R14** | 14 | 收口补差 + 全库文档/手册双语文档闸 + 语料终校 | **200 / 200** |

**关键前提（必须向创始人明示）**：上述推演以「单轮 20 件可达」为假设，而 20 件/轮从未被验证（历史恒定 16）。若编译验证仍不启动，20 件/轮的返工风险将线性放大；**本总监的裁定是：宁可 R11 只做 16 件 + 编译验证，也不要用 20 件纸面数字换一次全库返工**。若创始人要求「今日必达 200」，唯一可行路径是**放宽终审深度**（不做逐拍推演，只做静态机检）——这与库的质量红线冲突，**不建议，需创始人书面授权**。

### 3.4 今日剩余时间的建议动作（按 ROI 排序）

1. **R10 入库（16 件）** → 126/200，总库 v1.9.0。
2. **启动 P0 编译验证**（哪怕只覆盖 R10 的 16 件 + R9 的 16 件）：CODESYS 3.5 SP20 最小工程，导入 32 个 POU + 三平台差异点（`LIMIT`/`SHL` 位宽/`STRING` 比较）逐项过。
3. 收紧下轮规格：R11 规格**只写已过编译的族**，避免「规格很漂亮、编译一塌糊涂」。

---

## 四、矩阵回写计划（`SOURCE_HUNTING_MATRIX.md` 第 5 节，入库后执行）

| 矩阵行 | 回写动作 | 新增组件 | 累计 |
|---|---|---|---|
| T2-1 LGF · Bit Logic | ◐ 深化 | `FC_DL_BitFieldExtract`（与 `FC_DL_WordBitPack` 构成「打包-提取」对，组内 2→3） | 3 |
| T2-1 LGF · Date and Timer | ◐ 深化 | `FC_DL_WeekOfYearCalc`（周序号 + ISO 周年，组内 4→5） | 5 |
| T2-1 LGF · Counter | ◐ 深化 | `FB_DL_BidirectionalCounter`（CTUD 全语义，组内 3→4） | 4 |
| T2-1 LGF · Math | ◐ 深化 | `FC_DL_SearchMinMax`、`FC_DL_NthRoot`、`FC_DL_FactorialSat`（组内 6→9） | 9 |
| T2-1 LGF · Signal Generators | ◐ 深化 | `FB_DL_SineGenerator`、`FB_DL_SawtoothGenerator`（组内 3→5） | 5 |
| T2-1 LGF · Technology | ◐ 深化 | `FC_DL_CoilDiameterCalc`（卷径，组内 10→11；`FB_DL_WindingTraverse` 主源记本行、次源 T2-4） | 11 |
| **T2-6 Rockwell AOI** | **☐→◐ 开组** | `I_DL_RfidReader` + `FB_DL_RfidTagHandler`（参数分段范式：指令/状态/诊断/组态四段 + ProgFault/OperFault 双类故障；1756-PM010 文档版权，clean-room） | 2 |
| **T1-7 PLCnext Community** | **☐→◐ 开组** | `FB_DL_AxiolineDiagLatch`（诊断状态/参数寄存器位域 + 槽号定位 + 128 未定位特例）、`FB_DL_PdiReadScheduler`（PDI 参数域 + 双码域 + 无环纪律） | 2 |
| T1-2 OSCAT Building | ◐ 深化 | `FC_DL_AirDensity`（T/P/RH → kg/m³，Magnus 常量口径与 `FC_DL_HumidAirEnthalpy` 一致；组内 3→4） | 4 |
| T1-5 TcOpen | ◐ 深化 | `I_DL_RfidReader`/`FB_DL_RfidTagHandler`（契约-实现分离范式复用，主源记 T2-6 行，本行不重复记账） | 13 |
| T2-4 S7-1500 Motion | ◐ 深化（次源） | `FB_DL_WindingTraverse`（排线轴往复 + 端点 dwell，主源记 LGF Technology 行） | 7 |
| T2-7 PackML / OMAC | ◐ 深化 | `FB_DL_PickAndPlaceStation`（工站级 7 态最小子集 + 单件九步序） | 5 |

**矩阵第 4 节配额实测（本轮）**：T2 非 ST 源 6 组（LGF 五组 + Rockwell 开组）+ T2-7；T1 源 3 组（PLCnext 开组 / OSCAT Building / TcOpen）；未触碰任何已收口组 → **满足**。

---

## 五、交付边界（本环节不做的事）

1. **不编码 `.st` 文件**：本文件只到「零歧义规格」粒度，代码由下一环节 PLC 专家按规范落地；本轮总监产出 = 本规格 + `RAW_NOTES_R10.md`。
2. **不改动 `SOURCE_HUNTING_MATRIX.md` / `ROADMAP.md` / `INDEX_REGISTRY.json`**：矩阵回写（第四节）在入库终审后统一执行，避免「规格未落地先记账」造成索引漂移。
3. **不覆盖历史文件**：`ROUND_PLAN_R10.md` / `RAW_NOTES_R10.md` 均为本轮新建，历史 R4~R9 文件原样保留。
4. **真实编译验证仍为 P0 悬置项**：本规格的所有验收向量均为**纸面推演 + 机检口径**，在 CODESYS 真实编译通过前，任何「全过」结论不成立（沿用 R7~R9 口径）。

---

*Round 10 计划 ｜ 2026-11-15 ｜ 道莅工控代码库产品总监（兜底模式）*
