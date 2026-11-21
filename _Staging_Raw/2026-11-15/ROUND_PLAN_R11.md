# ROUND PLAN — Round 11（R11）

> 日期：2026-11-15 ｜ 轮次类型：Phase 1 第十一轮批处理（**DL_Process P0 工站四件套收口** + **T1-7 PLCnext port-based 诊断族深化** + **T2-1 LGF Bit Logic 批量位段开组** + Level 0 年窗/回绕/区间回补 + 卷绕张力与 R2R 各一件）
> 本轮目标：**16 件**（完成后今日累计 **142 / 200**）｜ 库规模：**152 → 168** ｜ 总库版本：v1.9.0 → **v1.10.0**（入库后）
> 执行人：道莅工控代码库产品总监（Daoli Library Director）· 兜底模式（原生专家子代理不可用）
> 规范依据：`daoli-st-standard` SKILL.md + `references/`（coding-standard / directory-contract / doc-templates）+ `templates/`（FB / FC / I 三骨架）
> 前置阅读：`INDEX_REGISTRY.json`（v1.9.0，152 件）、`ROADMAP.md`（未勾选 264 条）、`SOURCE_HUNTING_MATRIX.md`（第 4 节配额 / 第 5 节台账）、`AGENT_EVOLUTION_LOG.md` 规则库 R1~R32

---

## 〇、阶段一盘点结论（以实际文件为准，非记忆）

### 0.1 总库与今日进度（实测）

| 检查项 | 实测结论 |
|---|---|
| `INDEX_REGISTRY.json` | `total_components = 152`，`version = 1.9.0`，`last_updated = 2026-11-15T17:05+08:00` |
| 子库分布（registry `counts`） | DL_Base **32** ｜ DL_MathData **29** ｜ DL_Algo **24** ｜ DL_Device **36** ｜ DL_Motion **15** ｜ DL_Process **16** = **152** |
| 今日入库 | **126 件**（R3 14 + R4 16 + R5 16 + R6 16 + R7 16 + R8 16 + R9 16 + R10 16） |
| 今日目标对照 | **126 / 200 = 63.0%**，缺口 **74 件**（R11 后 → 142 / 200 = 71.0%） |
| 语料同步 | `_AI_Training_Dataset` 侧 **152 条**，与 registry 152、文件 152 三方一致；R11 入库后需同步至 168 |
| `ROADMAP.md` 未勾选 | **264 条**（含 §6 待办 4 项 + 行业池 263 项口径差 3 条已勾选遗留） |
| 本轮唯一改动边界 | 仅 `ROUND_PLAN_R11.md`、`RAW_NOTES_R11.md`、`ROADMAP.md` 三个文件；**不生成任何 `.st`、不动 `INDEX_REGISTRY.json`、不动 JSONL** |

### 0.2 源组挖掘覆盖（按第 5 节台账现状）

| 源组 | 台账状态 | 已出件 | R11 判断 |
|---|---|---|---|
| T2-1 LGF · Bit Logic | ◐ 最浅 | 2（`FC_DL_WordBitPack`、`FC_DL_BitFieldExtract`） | **必挖**：DWORD/LWORD 批量位段族 |
| T2-1 LGF · Math | ◐ | 9 | 可挖：`CalcDistance_2D/_3D`、`Random_*` |
| T2-1 LGF · Counter | ◐ | 4 | 可挖：回绕型（无预设比较的环形计数） |
| T2-1 LGF · Comparator | ◐ | 3 | 可挖：区间关系判定（重叠/包含/相接） |
| T2-1 LGF · Date and Timer | ◐ | 5 | 可挖：**年窗**（月窗已有、年窗缺） |
| T2-2 LBP | ◐ | 28 | 可挖：压装/工站「命令-监视-判定」三段分层 |
| T2-4 S7-1500 Motion | ◐ | 7 | 可挖：张力双层（锥度给定 + 摆辊修正） |
| T2-6 Rockwell AOI | ◐ | 2 | 可挖：设备级粗粒度 AOI（多通道设备一块覆盖） |
| T2-7 PackML / T2-8 ISA-88 | ◐ | 11 | 本轮只借态命名语义（不作主源） |
| T1-7 PLCnext | ◐ | 2（Axioline / PDI） | **必挖**：port-based 诊断族（端口级） |
| T1-6 PLCopen | ◐ | 12 | 借「轴状态与工艺态分离」纪律 |
| T1-2 OSCAT | ◐ | 4 | 借行为定义写法（域外处理） |
| T1-8 GitHub topics | ◐ | 2 | 借纯函数式 PRNG 接口形态 |

### 0.3 锁定本轮 16 件（逐名对 registry + 全库文件名 + ROADMAP 双向查重 = 0 命中新增名）

| # | 组件 | 类型 | 子库 | 来源组标签 | 立项依据 |
|---|---|---|---|---|---|
| 1 | `FB_DL_PressFitStation` | FB | DL_Process | `lbp-process` + `plcopen-motion` | ROADMAP §6 **P0 待办**；本轮工站四件套之首 |
| 2 | `FB_DL_RotaryIndexTable` | FB | DL_Process | `packml-omac` + `lgf-bitlogic` | ROADMAP §6 **P0 待办**（分度盘调度） |
| 3 | `FB_DL_AgvDockingHandshake` | FB | DL_Process | `packml-omac` + `isa-88` | ROADMAP §6 **P0 待办**（AGV 对接交接） |
| 4 | `FB_DL_EnergySavingMode` | FB | DL_Process | `isa-88` + `lbp-process` | ROADMAP §6 **P0 待办**（空闲节能） |
| 5 | `FB_DL_PortDiagAggregator` | FB | DL_Device | `plcnext-community` | **T1-7 深化**：port-based 诊断族（R10 台账明写待挖） |
| 6 | `FB_DL_StatusWordSegDecoder` | FB | DL_Device | `lgf-bitlogic` + `rockwell-aoi` | **T2-1 Bit Logic 最浅组开批量位段**（段表驱动，非单段） |
| 7 | `FB_DL_NtcTempScan` | FB | DL_Device | `rockwell-aoi` + `oscat-building` | ROADMAP §7.1 未勾选项；AOI 粗粒度多通道设备 |
| 8 | `FB_DL_RollerGapAdjust` | FB | DL_Device | `rockwell-aoi` + `lbp-process` | ROADMAP §7.1 未勾选项（辊距伺服微调） |
| 9 | `FB_DL_YearWindowCheck` | FB | DL_Base | `lgf-datetime` | 台账明写「年窗族待挖」；月窗/周窗已收口，缺年粒度 |
| 10 | `FB_DL_RolloverCounter` | FB | DL_Base | `lgf-counter` | 台账明写「回绕型待挖」；与 CTUD/取模三件职责互斥 |
| 11 | `FC_DL_RangeOverlapCheck` | FC | DL_Base | `lgf-comparator` | Comparator 深化：区间**关系**（非单点判限） |
| 12 | `FC_DL_CalcDistance3D` | FC | DL_MathData | `lgf-math` | 台账明写 `CalcDistance_2D/_3D` 待挖（**只做 3D，拒拆 2D 变体**） |
| 13 | `FC_DL_RandomNext` | FC | DL_MathData | `lgf-math` | 台账明写 `Random_*` 待挖 |
| 14 | `FC_DL_PercentileLReal` | FC | DL_MathData | `lgf-math` | 统计族深化（均值/方差已有，分位数缺） |
| 15 | `FB_DL_R2rEwmaTuner` | FB | DL_Algo | `semiconductor-apc` + `lgf-math` | ROADMAP §7.3 未勾选项（R2R EWMA 微调） |
| 16 | `FB_DL_WindingTensionCtrl` | FB | DL_Motion | `lgf-technology` + `s7-motion` | ROADMAP §7.1 未勾选项（锥度张力闭环） |

**目录分布**：DL_Process **4** ｜ DL_Device **4** ｜ DL_Base **3** ｜ DL_MathData **3** ｜ DL_Motion **1** ｜ DL_Algo **1** = **16**。

### 0.4 配额自检（矩阵第 4 节硬性要求）

- **T2 非 ST 借鉴源 ≥ 1 组**：T2-1 LGF 五组（Bit Logic #6 / Math #12~#14 / Counter #10 / Comparator #11 / Date and Timer #9）+ T2-2 LBP（#1 #4 #8）+ T2-6 Rockwell AOI（#6 #7 #8）+ T2-4 S7-1500 Motion（#16）→ **满足（4 个 T2 源，5 个 LGF 组）**。
- **T1 ST 原生源 ≥ 1 组**：T1-7 PLCnext（#5）+ T1-6 PLCopen（#16 纪律）+ T1-2 OSCAT（#7 行为定义）+ T1-8 GitHub topics（#13）→ **满足（4 个 T1 源）**。
- **不重复挖掘已收口组**：本轮 5 个 LGF 组均为「横向扩族」且每件在「与既有件边界」段逐条写死职责边界（如 #10 与 `BidirectionalCounter` / `ModuloCounter` / `PresetCounterSat` 三者互斥，#11 与 `LimitClassify` / `ToleranceWindow` / `Hysteresis` 三者互斥）。
- **矩阵扩产 5 规则使用情况**：①数据类型重载 1 次（#6 支持 DWORD/LWORD 双宽域，经 `LWORD` 单入口 + 零扩展实现，**不拆两块**）；②阶数/阶次变体 0 次；③协议方言 0 次；④行业工况 3 次（#1 锂电/汽配压装、#2 包装/装配分度、#3 物流交接）；⑤精度变体 1 次（#14 输出 LREAL）。
- **铁律重申**：本轮 **零** 组件以 `MODE` / `eMode` / `nVariant` 一类参数把多变体塞进单块。凡「同一算法不同语义」一律拆件（#12 只做 3D 并显式声明 2D 为其退化情形，反向证明「不拆变体」原则）。

### 0.5 历史范式带入（编码者必须逐条落地，终审逐条核）

| 规则 | 本轮落点 |
|---|---|
| **R19 / R21** 信息级码不置 `bError` | 全部 16 件：`01xx` 段只进 `uErrorId` 与趋势量，`bError` 仅反映故障级锁存 |
| **R24 / R25** 单拍标志生命周期三律 | #2（分度请求脉冲）、#3（完成确认单拍）、#4（模式切换单拍）、#5（首出锁存单拍）、#15（本批已修正单拍）——预清零 / 消费拍与转出拍分离 / 实例调用后自清 |
| **R19** 首扫标志唯一合法范式 | #1 #4 #5 #7 #8 #15 #16（含累计/上次值的块：`bInit` 初值 FALSE，判据 `NOT bInit`） |
| **R31** 枚举 → CASE 双向映射完备性 | 全部 FB（**13 个新 ENUM**，其中 12 个驱动 CASE、1 个 `E_DL_RangeRelation` 为 FC 返回枚举）：落盘前逐成员对照 CASE 标签表，**每个成员必须有标签**，缺一即 D-01 级致命（R10 已实证） |
| **R32** 内部状态量写入点全拍排序审计 | #1 #2 #5 #7 #16：同一状态量在同拍多分支写入的，列出「写入点次序表」 |
| **R26 / R28** 禁孤立分号 / 注释不可嵌套 | 全部 16 件（头注释内「调用示例」只用行注释） |
| **R29** 赋值目标声明性检查 | 全部 16 件（落盘后脚本比对，禁未声明即赋值） |
| **R30** 码位自证循环禁令 | 见 0.6：分配值来自脚本对全库 152 件 `.st` 求差，不采信编码者自报「已核对」 |

### 0.6 码位分配（脚本对全库 152 件求差后的裁定值，跨文件重叠 = 0）

**段位公约（沿用 R5 公约 0.7）**：`16#00SS_XXXX`；`SS` = 01 基础+数学 / 02 算法 / 03 设备 / 04 运动 / 05 工艺；`XXXX` 首位 `0` = 信息级，首位 `1`/`2` 及以上 = 故障级，中间两位为分组件族段。

| # | 组件 | 全库实测已占（段内最大值） | **R11 分配** |
|---|---|---|---|
| 1 | `FB_DL_PressFitStation` | `0005` 信息级 ≤ `01B4`，故障级 ≤ `02B7` | 信息 `01C0` `01C1`｜故障 `02C0`~`02C3` |
| 2 | `FB_DL_RotaryIndexTable` | 同上 | 信息 `01C2`｜故障 `02D0`~`02D3` |
| 3 | `FB_DL_AgvDockingHandshake` | 同上 | 信息 `01C3`｜故障 `02E0`~`02E4` |
| 4 | `FB_DL_EnergySavingMode` | 同上 | 信息 `01C4`｜故障 `02F0`~`02F2` |
| 5 | `FB_DL_PortDiagAggregator` | `0003` 信息级 ≤ `013F`，故障级 ≤ `02F9` | 信息 `0140` `0141`｜故障 `0300` `0301` `0307` |
| 6 | `FB_DL_StatusWordSegDecoder` | 同上 | 信息 `0142`~`0144`｜故障 `0302` |
| 7 | `FB_DL_NtcTempScan` | 同上 | 信息 `0145` `0146`｜故障 `0303` `0304` |
| 8 | `FB_DL_RollerGapAdjust` | 同上 | 信息 `0147` `0148`｜故障 `0305` `0306` `0308` |
| 9 | `FB_DL_YearWindowCheck` | `0001` 信息级 ≤ `011D`（Base+Math 合并口径），故障级 ≤ `0217` | 信息 `011E` `011F` |
| 10 | `FB_DL_RolloverCounter` | 同上 | 信息 `0120`｜故障 `0218` |
| 11 | `FC_DL_RangeOverlapCheck` | 同上 | 信息 `0121` |
| 12 | `FC_DL_CalcDistance3D` | 同上 | 信息 `0122`｜故障 `0219` |
| 13 | `FC_DL_RandomNext` | 同上 | 信息 `0123` |
| 14 | `FC_DL_PercentileLReal` | 同上 | 信息 `0124`｜`0002` 段 `000E`（样本不足） |
| 15 | `FB_DL_R2rEwmaTuner` | `0002` 组件序号已用 `01`~`1E` | 信息 `1F01`~`1F03`｜故障 `1F10` |
| 16 | `FB_DL_WindingTensionCtrl` | `0004` 信息级 ≤ `01B3`，故障级 ≤ `02C3` | 信息 `01C0`~`01C2`｜故障 `02D0` `02D1` |

> **编码者铁律（R30）**：以上为总监裁定值。实现中若某码语义需拆细，只允许在**本组件已分配块内**加尾号（如 `02C0` 块内 `02C5` 不允许），跨块即判串台缺陷。

### 0.7 泳道分配（3 条泳道，禁止跨泳道引用本轮新件）

| 泳道 | 组件 | 依赖约束 |
|---|---|---|
| **A · Level 0 原子回补（6 件）** | ⑨`FB_DL_YearWindowCheck` ⑩`FB_DL_RolloverCounter` ⑪`FC_DL_RangeOverlapCheck` ⑫`FC_DL_CalcDistance3D` ⑬`FC_DL_RandomNext` ⑭`FC_DL_PercentileLReal` | 仅标准库；**六件零互相依赖**（⑫ 不得调 ⑪，⑭ 不得调 ⑫） |
| **B · 设备层（4 件）** | ⑤`FB_DL_PortDiagAggregator` ⑥`FB_DL_StatusWordSegDecoder` ⑦`FB_DL_NtcTempScan` ⑧`FB_DL_RollerGapAdjust` | 允许依赖 DL_Base / DL_MathData **既有**件；**禁止**调用 A 泳道本轮新件（⑥ 的位段提取必须自写，不得调 ⑪/⑫） |
| **C · 算法/运动/工艺（6 件）** | ⑮`FB_DL_R2rEwmaTuner` ⑯`FB_DL_WindingTensionCtrl` ①`FB_DL_PressFitStation` ②`FB_DL_RotaryIndexTable` ③`FB_DL_AgvDockingHandshake` ④`FB_DL_EnergySavingMode` | ⑯ 允许调用**已入库** `FB_DL_PidController` / `FC_DL_CoilDiameterCalc`（层次合法：Motion → Algo）；① 的包络插值自写，不得调 `FC_DL_MultiPointLinear`（跨层可用但为保持契约一致，规格统一内联并声明）；其余件只用标准库 |

**层间合法性硬校验**：`DL_Base` / `DL_MathData` 不得引用 `DL_Device` / `DL_Motion` / `DL_Process` 类型；`DL_Device` 不得引用 `DL_Process`。

### 0.8 行数配额口径

FB 380~580 行 / FC 200~340 行（含头注释与码位表，`wc -l` 口径）。本轮预估合计 **6,320 行**（A 1,560 / B 2,200 / C 2,560）。

---

## 一、组件规格（16 件）

> **通用要求（对 16 件全部生效，各件正文不再重复）**
> 1. 头注释七项齐全（名称 / 子库 / 版本 1.0.0 / 兼容性 / 功能 / 开源溯源 / 修订历史）；溯源措辞统一为「参考 XXX 公开手册的**功能分类与参数域**，只借分类 / 参数域 / 命名组织，clean-room 实现，不构成衍生作品」。
> 2. **零全局耦合**：外部数据一律经引脚 / `VAR_IN_OUT` / 接口实例注入；**不引用任何外部变量声明、不出现绝对地址记号、不读系统时钟**。
> 3. 100% 中文注释；声明区每变量、每枚举项同行注释，写清物理意义 + 工程单位 + 取值范围 + 默认行为。
> 4. 状态机 `ENUM` + `CASE` + `ELSE` 兜底；`TON`/`TOF`/`TP`/`R_TRIG`/`F_TRIG` 在主周期无条件刷新；浮点禁判等（`ABS(a-b) < 1E-6`）；除法防零；数组访问先判边界；`WHILE` 带防死锁计数器。
> 5. 阈值 / 限幅 / 超时 / 重试一律 `VAR CONSTANT` 或引脚（禁魔法数）；故障统一 `uErrorId`，码位表写入头注释并区分信息级 / 故障级。
> 6. `E_DL_*` 枚举与 `ST_DL_*` 结构体随宿主 POU 同文件发布（库内既有惯例），以 `END_TYPE` 终结。
> 7. 每个 POU 以 `END_FUNCTION` / `END_FUNCTION_BLOCK` 成对终结（R18）。
> 8. **FC 件（#11~#14）无状态机**：纯函数不存在跨周期状态，规格以「算法分步 + 早退守卫 + 返回码」替代 `ENUM`+`CASE`；其中 #11 因返回值是**关系枚举**仍给出 `E_DL_RangeRelation` 成员表。**FB 件（#1~#10、#15、#16）一律必须有 `ENUM` + `CASE` + `ELSE` 兜底**，无例外。

---

### 1. `FB_DL_PressFitStation` —— 伺服精密压装工站（包络窗口 + 曲线特征点）

- **子库**：DL_Process ｜ **前缀**：`FB_DL_` ｜ **预计行数**：560 ｜ **来源组标签**：`lbp-process`、`plcopen-motion`、`isa-88`
- **一句话功能**：把「接近 → 压入 → 保压 → 回退」四段压装动作做成标准工站状态机，并在压入过程中逐点做**位移-压力包络窗口校验**与**接触点 / 屈服点 / 峰值点 / 终点**四特征点提取，一个循环给出 OK/NG 与 NG 原因位。
- **与既有件边界**：`FB_DL_TorqueLimitControl`（DL_Motion）做的是**轴级**力矩限幅与到位判定，只输出「达限/到位」；本件做的是**工站级**工艺判定（包络 + 曲线特征 + 多原因归并 + 结果结构体），二者分层不同、不可互替。`FB_DL_StepSequencer` 是通用步序基类，本件不复用它：压装态与监控量强耦合，套基类会造成「两步序状态机并存」（R31 风险）。
- **依赖**：仅标准库（包络插值与斜率计算内联实现，保证工站件零算法库耦合）。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_PressFitStation
VAR_INPUT
    bEnable            : BOOL;                    // 使能；FALSE 时回 eIdle 并复位输出 / Enable; reset to eIdle when FALSE
    bStart             : BOOL;                    // 上升沿启动一个压装循环 / Rising edge starts one press cycle
    bAbort             : BOOL;                    // 上升沿中止并立即请求回退 / Rising edge aborts and requests retract
    bReset             : BOOL;                    // 上升沿复位故障锁存 / Rising edge clears latched fault
    fActPos            : REAL;                    // 压头实际位移 [mm]，量程 0.0~500.0 / Actual ram position [mm]
    fActForce          : REAL;                    // 压力传感器实测压力 [kN]，量程 0.0~200.0 / Measured force [kN]
    fContactForceThr   : REAL := 0.05;            // 接触判定压力阈值 [kN]，0 表示禁用接触点提取 / Contact threshold [kN]
    fYieldSlopeRatio   : REAL := 0.50;            // 屈服判据：斜率降至峰值斜率该比例 [无量纲 0~1] / Yield slope ratio [-]
    fPeakDropForce     : REAL := 0.30;            // 峰值后压降判定量 [kN]，0 表示不判 / Force drop after peak [kN]
    fEndPosTarget      : REAL := 10.0;            // 终点位移目标 [mm] / Target end position [mm]
    tStageTimeout      : TIME := T#5S;            // 单段超时 [ms/s]，0 表示不监控 / Per-stage timeout
    tDwell             : TIME := T#500MS;         // 保压时间 [ms]，0 表示跳过保压 / Dwell time
    fForceUpperLimit   : REAL := 180.0;           // 压力硬上限 [kN]，达限立即转保压 / Hard force limit [kN]
END_VAR
VAR_OUTPUT
    eState             : E_DL_PressFitState;      // 主状态机当前态 / Current state of the main state machine
    bBusy              : BOOL;                    // 循环进行中 / Cycle in progress
    bDone              : BOOL;                    // 循环结束单拍脉冲 / Single-scan pulse at cycle end
    bOk                : BOOL;                    // 判定合格（保持到下次启动）/ Result OK, held until next start
    bNg                : BOOL;                    // 判定不合格（保持到下次启动）/ Result NG, held until next start
    bError             : BOOL;                    // 故障级锁存，需 bReset 清除 / Latched fault, cleared by bReset
    uErrorId           : UDINT;                   // 事件/故障码，0 = 无 / Event or fault code, 0 = none
    uNgReason          : WORD;                    // NG 原因位：bit0 上包络越界 bit1 下包络越界 bit2 终点未达 bit3 接触未建立 bit4 保压压降超限 / NG reason bits
    stResult           : ST_DL_PressFitResult;    // 曲线特征点结果结构体 / Curve feature result structure
    fEnvDevMax         : REAL;                    // 全程包络最大偏差 [kN]，用于趋势分析 / Max envelope deviation [kN]
    nSampleCnt         : UDINT;                   // 本循环有效采样点数 / Valid sample count of this cycle
END_VAR
VAR_IN_OUT
    stEnv              : ST_DL_PressFitEnvelope;  // 包络表（位移节点 + 上下限），由工艺组态注入，块内只读 / Envelope table injected by config, read-only here
    stStat             : ST_DL_PressFitStat;      // 跨周期统计（累计循环数 / 合格数），由调用方持有 / Persistent statistics held by caller
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS       : REAL := 1.0E-6;          // 浮点判等容差 / Float comparison epsilon
    DL_ENV_MAX_POINTS  : INT  := 32;              // 包络表最大节点数 / Max envelope knots
    DL_SLOPE_MIN_DELTA : REAL := 1.0E-4;          // 斜率计算最小位移增量 [mm]，防除零 / Min delta for slope, div-by-zero guard
    DL_MAX_CYCLES      : UDINT := 16#FFFF_FFFE;   // 循环计数防溢出上限 / Cycle counter saturation limit
END_VAR
```

**配套类型（同文件发布）**

| 类型 | 成员 | 说明 |
|---|---|---|
| `E_DL_PressFitState` | `eIdle := 0` / `eApproach := 10` / `ePress := 20` / `eDwell := 30` / `eRetract := 40` / `eEvaluate := 50` / `eFinish := 60` / `eFault := 99` | 压装八态；编号留 10 间隔便于后续插态 |
| `ST_DL_PressFitEnvelope` | `nPoints : INT`；`afPos : ARRAY[1..32] OF REAL` [mm]；`afUpper : ARRAY[1..32] OF REAL` [kN]；`afLower : ARRAY[1..32] OF REAL` [kN] | `afPos` 必须严格单调递增，`afUpper >= afLower` |
| `ST_DL_PressFitResult` | `fContactPos` [mm]；`fContactForce` [kN]；`fYieldPos` [mm]；`fYieldForce` [kN]；`fPeakPos` [mm]；`fPeakForce` [kN]；`fEndPos` [mm]；`fEndForce` [kN] | 四特征点，未提取到时保持 0.0 并在 `uNgReason` 说明 |

**关键算法**

1. **包络插值校验**：对当前 `fActPos` 在 `afPos` 上二分定位所在区间 `[i, i+1]`，线性插值得上限 `fUp`、下限 `fLo`；若 `fActForce > fUp + EPS` 置 `uNgReason.0` 并累计 `fEnvDevMax := MAX(fEnvDevMax, fActForce - fUp)`；若 `fActForce < fLo - EPS` 置 `uNgReason.1`。区间长度 `<= DL_SLOPE_MIN_DELTA` 视为退化，跳过该点（防除零）。
2. **接触点**：首个满足 `fActForce >= fContactForceThr` 的采样，用**相邻两采样线性插值**求精确位移：
   `fContactPos := fPos[k-1] + (fPos[k] - fPos[k-1]) * (fContactForceThr - fForce[k-1]) / (fForce[k] - fForce[k-1])`；分母判零。全程无满足点 → `uNgReason.3`。
3. **屈服点**：逐拍维护 `fSlope := (fForce[k] - fForce[k-1]) / (fPos[k] - fPos[k-1])`（分母 `< DL_SLOPE_MIN_DELTA` 时沿用上一拍斜率），并跟踪峰值斜率 `fSlopeMax`；当 `fActForce` 已过峰值且 `fSlope < fSlopeMax * fYieldSlopeRatio` 首次成立时锁存屈服点（位置 + 压力），仅锁存一次。
4. **峰值/终点**：`fPeakForce` 为全程最大压力及其位置；`fEndPos`/`fEndForce` 取 `eRetract` 进入拍的值；若 `fEndPos < fEndPosTarget - EPS` 置 `uNgReason.2`。
5. **保压压降**：`eDwell` 进入拍记录 `fDwellStartForce`，保压结束时若 `fDwellStartForce - fActForce > fPeakDropForce` 置 `uNgReason.4`。
6. **判定**：`eEvaluate` 内 `bNg := uNgReason <> 0`；`bOk := NOT bNg`；两者同时只在 `bDone` 拍更新。

**状态机（ENUM + CASE）**

| 当前态 | 迁移条件 | 目标态 |
|---|---|---|
| `eIdle` | `bStart` 上升沿（且 `bEnable`）→ 清零 `uNgReason` / `stResult` / `fEnvDevMax` / `nSampleCnt` | `eApproach` |
| `eApproach` | `fActForce >= fContactForceThr` → 记录接触点 | `ePress` |
| `eApproach` | `tStageTimeout` 到 | `eFault`（`02C2`） |
| `ePress` | `fActPos >= fEndPosTarget` 或 `fActForce >= fForceUpperLimit` | `eDwell` |
| `ePress` | `tStageTimeout` 到 | `eFault`（`02C2`） |
| `eDwell` | `tDwell` 到（`tDwell = T#0S` 直通） | `eRetract` |
| `eRetract` | `bAbort` 上升沿或回退到位（`fActPos <= fStartPos`） | `eEvaluate` |
| `eEvaluate` | 无条件（当拍完成判定） | `eFinish` |
| `eFinish` | 无条件（`bDone` 单拍在此拍输出，下一拍转出） | `eIdle` |
| `eFault` | `bReset` 上升沿 | `eIdle` |
| **`ELSE`** | 任意未列举值 → 回安全态并置故障 | `eFault` + `16#0005_02C0` |

> **R31 完备性**：八成员逐一对应上表标签，`ELSE` 仅兜非法值，**不得**承担任何合法态（R10 D-01 教训）。
> **R32 写入点次序**：`eState` 只在 CASE 尾部单点写入；`uErrorId` 的写点按「段超时 → 采样非法 → 包络退表」固定次序，禁止在迁移分支与业务分支双写同一码。

**码位表**：`16#0005_01C0` 包络表点数越界已钳位（信息级）｜`16#0005_01C1` 上下限对调已修复（信息级）｜`16#0005_02C0` 非法状态兜底（故障级）｜`16#0005_02C1` 包络表非法（点数 < 2 或 `afPos` 非单调，故障级）｜`16#0005_02C2` 阶段超时（故障级）｜`16#0005_02C3` 采样非有限值（故障级，当拍拒绝更新）。

**验收向量（可独立复算）**

| 向量 | 输入 | 期望输出 |
|---|---|---|
| V1 包络插值 | 节点 `(0 mm, up 0 kN, lo 0 kN)`、`(10 mm, up 10 kN, lo 2 kN)`；`fActPos = 5.0 mm, fActForce = 5.5 kN` | `fUp = 5.0`、`fLo = 1.0`、`fActForce` 上越界 0.5 kN → `uNgReason.0 = 1`、`fEnvDevMax >= 0.5`（容差 1E-6） |
| V2 接触点插值 | 采样 `(1.0 mm, 0.02 kN)`、`(1.2 mm, 0.06 kN)`；`fContactForceThr = 0.05 kN` | `fContactPos = 1.0 + 0.2 × (0.05-0.02)/(0.06-0.02) = 1.15 mm`（±1E-4） |
| V3 屈服点 | 斜率序列 `20 / 18 / 9 kN/mm`，`fYieldSlopeRatio = 0.5`（阈值 10） | 屈服点锁存于第 3 个采样位置，`fYieldForce` = 该采样压力，锁存后不再更新 |
| V4 终点未达 | `fEndPosTarget = 10.0 mm`，实际回退前最大 `fActPos = 9.4 mm` | `uNgReason.2 = 1`、`bNg = TRUE`、`bOk = FALSE`、`bDone` 单拍 |
| V5 保压压降 | 保压起点 `fDwellStartForce = 12.0 kN`，结束 `8.0 kN`，`fPeakDropForce = 0.3 kN` | 压降 4.0 kN > 0.3 → `uNgReason.4 = 1` |

---

### 2. `FB_DL_RotaryIndexTable` —— 多工位分度盘调度框架

- **子库**：DL_Process ｜ **前缀**：`FB_DL_` ｜ **预计行数**：520 ｜ **来源组标签**：`packml-omac`、`lgf-bitlogic`、`isa-88`
- **一句话功能**：管理「分度请求 → 到位确认 → 稳定等待 → 工位工艺放行」的节拍链，维护工位启用表与工艺号映射，支持空跑/清洗模式（跳过工位使能、逐位走完），并对分度超时与到位信号抖动给出可诊断的故障码。
- **与既有件边界**：`FB_DL_BufferMagazine` 管**料仓槽位状态**（空/满/NG 台账），不做分度动作；`FB_DL_ConveyorZone` 管**连续输送**积放；本件管**离散分度盘**的节拍与工位放行。三者拓扑互斥。
- **依赖**：仅标准库。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_RotaryIndexTable
VAR_INPUT
    bEnable          : BOOL;                              // 使能；FALSE 撤回 bIndexReq 并回 eIdle / Enable; withdraws index request on FALSE
    bStart           : BOOL;                              // 上升沿启动节拍循环 / Rising edge starts the indexing cycle
    bStop            : BOOL;                              // 上升沿在完成当前工位后停止（不中断分度）/ Rising edge stops after current station
    bReset           : BOOL;                              // 上升沿复位故障 / Rising edge clears fault
    nStationCount    : INT;                               // 工位总数 [个]，有效域 2~24 / Station count, 2..24
    nAtStation       : INT;                               // 机械到位工位号 [1..nStationCount]，0 = 未定位 / Mechanical station number, 0 = not seated
    bIndexInPos      : BOOL;                              // 分度到位开关信号 / Indexer in-position switch
    abStationEnable  : ARRAY[1..24] OF BOOL;              // 工位启用表，FALSE 工位视为空位 / Station enable table, FALSE = empty station
    anStationRecipe  : ARRAY[1..24] OF INT;               // 工位工艺号表（仅透传，不做校验）/ Per-station recipe number, pass-through only
    tDwellTime       : TIME := T#1S;                      // 每工位停留时间 [ms/s]，0 = 不停留 / Dwell per station
    tSettleTime      : TIME := T#100MS;                   // 到位后稳定确认时间 [ms]，滤除机械抖动 / Settling time after in-position
    tIndexTimeout    : TIME := T#3S;                      // 分度超时 [ms/s]，0 = 不监控 / Indexing timeout
    bDryRun          : BOOL;                              // 空跑/清洗模式：忽略工位使能，逐位走完 / Dry-run mode, ignores station enable
END_VAR
VAR_OUTPUT
    bIndexReq        : BOOL;                              // 分度请求输出，单拍脉冲 / Index request, single-scan pulse
    nActiveStation   : INT;                               // 当前作业工位号 [1..n]，0 = 无效 / Active station number
    bStationReady    : BOOL;                              // 当前工位允许工艺动作 / Station ready for process action
    nRecipeAtStation : INT;                               // 当前工位工艺号（透传）/ Recipe number at active station
    uStationMask     : DWORD;                             // 工位启用镜像，bit(n-1) 对应第 n 工位 / Station enable mirror, bit(n-1) for station n
    bCycleDone       : BOOL;                              // 一轮（n 个工位）走完单拍 / Single pulse when a full revolution completes
    tDwellRemain     : TIME;                              // 当前工位剩余停留时间 [ms/s] / Remaining dwell time
    eState           : E_DL_IndexTableState;              // 主状态机当前态 / Current state
    bError           : BOOL;                              // 故障锁存 / Latched fault
    uErrorId         : UDINT;                             // 事件/故障码 / Event or fault code
END_VAR
VAR_IN_OUT
    stStat           : ST_DL_IndexTableStat;              // 跨周期统计（分度次数 / 循环数 / 累计运行时长）/ Persistent statistics
END_VAR
VAR CONSTANT
    DL_STATION_MAX   : INT := 24;                         // 工位上限 [个] / Max station count
    DL_STATION_MIN   : INT := 2;                          // 工位下限 [个] / Min station count
    DL_MASK_BITS     : INT := 32;                         // 掩码位宽 [bit] / Mask width
END_VAR
```

**配套类型**

| 类型 | 成员 | 说明 |
|---|---|---|
| `E_DL_IndexTableState` | `eIdle := 0` / `eDwell := 10` / `eIndexing := 20` / `eSettling := 30` / `eFault := 99` | 五态；`eSettling` 单独成态是为隔离「到位后抖动」诊断 |
| `ST_DL_IndexTableStat` | `nIndexCount : UDINT`；`nCycleCount : UDINT`；`tRunTime : TIME` | 由调用方持有，块内累加，掉电保持由上层负责 |

**关键算法**

1. **工位号合法性**：`nAtStation` 必须满足 `1 <= nAtStation <= nStationCount`，否则 `eSettling` 判定失败 → `02D2`。
2. **掩码构造**：每拍由 `abStationEnable` 重建 `uStationMask`：`bit(n-1) := abStationEnable[n]`，`n > 32` 位不参与（`nStationCount <= 24` 恒安全）。**不用** `SHL` 拼累计量，改为逐位置位，规避宽度边界。
3. **停留计时**：`tDwellRemain := MAX(tDwellTime - fbDwell.ET, T#0S)`；`bDryRun = TRUE` 时停留时间直通（`eDwell` 当拍转出）。
4. **空跑模式**：`bDryRun = TRUE` 时 `bStationReady` 恒 FALSE（不工艺放行），但分度链照走，用于清洗/调试；此时不计 `nCycleCount`。
5. **循环计数**：工位号由 `nStationCount` 回到 1 的那一拍 `bCycleDone := TRUE`，`nCycleCount` 递增（上限 `16#FFFF_FFFE` 饱和）。
6. **到位抖动诊断**：`eSettling` 期间 `bIndexInPos` 掉沿 → `02D1`，并回 `eFault`（**不自动重试**：机械到位信号抖动属硬件问题，自动重试会掩盖故障）。

**状态机**

| 当前态 | 迁移条件 | 目标态 |
|---|---|---|
| `eIdle` | `bStart` 上升沿 | `eDwell`（先给出首工位放行） |
| `eDwell` | 停留计时到且 `bStop = FALSE` | `eIndexing`（当拍 `bIndexReq` 脉冲） |
| `eDwell` | 停留计时到且 `bStop = TRUE` | `eIdle` |
| `eIndexing` | `bIndexInPos` 上升沿 | `eSettling` |
| `eIndexing` | `tIndexTimeout` 到 | `eFault`（`02D0`） |
| `eSettling` | `tSettleTime` 到且 `bIndexInPos` 仍为 TRUE 且 `nAtStation` 合法 | `eDwell` |
| `eSettling` | `bIndexInPos` 掉沿 | `eFault`（`02D1`） |
| `eSettling` | `nAtStation` 越界 | `eFault`（`02D2`） |
| `eFault` | `bReset` 上升沿 | `eIdle` |
| **`ELSE`** | 非法值 | `eFault` + `16#0005_02D3` |

**码位表**：`16#0005_01C2` 工位数量越界已钳位（信息级）｜`16#0005_02D0` 分度超时｜`16#0005_02D1` 到位信号抖动/丢失｜`16#0005_02D2` 工位号越界｜`16#0005_02D3` 非法状态兜底。

**验收向量**

| 向量 | 输入 | 期望输出 |
|---|---|---|
| V1 掩码 | `nStationCount = 8`，前 5 个工位启用 | `uStationMask = 16#0000_001F` |
| V2 工艺号透传 | `nAtStation = 3`，`anStationRecipe[3] = 27` | `nActiveStation = 3`、`nRecipeAtStation = 27`、`bStationReady = TRUE` |
| V3 分度超时 | `tIndexTimeout = T#2S`，`bIndexInPos` 2 s 内未建立 | `uErrorId = 16#0005_02D0`、`eState = eFault`、`bError = TRUE` |
| V4 空跑 | `nStationCount = 4`，`bDryRun = TRUE` | 每拍推进 1 工位，4 拍后 `bCycleDone` 单拍，`nCycleCount` **不**递增 |
| V5 抖动 | 到位后 50 ms 内 `bIndexInPos` 由 TRUE → FALSE | `uErrorId = 16#0005_02D1`，无自动重试 |

---

### 3. `FB_DL_AgvDockingHandshake` —— AGV / AMR 对接交接状态机

- **子库**：DL_Process ｜ **前缀**：`FB_DL_` ｜ **预计行数**：500 ｜ **来源组标签**：`packml-omac`、`isa-88`、`lbp-process`
- **一句话功能**：把「到位检测 → 双侧就绪握手 → 交接放行 → 完成确认」做成带超时与失序诊断的交接状态机，屏蔽 AGV 与工站两侧信号时序差异，产出单一 `bTransferPermit` 与单拍 `bHandshakeOk`。
- **与既有件边界**：`FB_DL_ConveyorLineLink` 做的是**固定段间**输送握手（SMEMA 类，连续物流）；本件做的是**移动载体与固定工站**的临时对接（会话式、一次性），握手对象含「物料在位」与「双侧就绪」双条件，语义不同。
- **依赖**：仅标准库（状态全部外置，无接口注入）。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_AgvDockingHandshake
VAR_INPUT
    bEnable            : BOOL;                 // 使能；FALSE 时撤回所有放行位 / Enable; withdraws all permits on FALSE
    bReset             : BOOL;                 // 上升沿复位故障 / Rising edge clears fault
    bAbort             : BOOL;                 // 上升沿中止本次交接 / Rising edge aborts the handshake
    bAgvArrived        : BOOL;                 // AGV 到位光电（粗定位）/ AGV presence sensor
    bAgvDockReady      : BOOL;                 // AGV 侧对接机构就绪 / AGV-side dock ready
    bStationReady      : BOOL;                 // 工站侧可收料/可放料 / Station-side ready
    bMaterialOnAgv     : BOOL;                 // 物料在位（交接前 = AGV 侧有料，交接后 = 工站侧有料）/ Material present flag
    bTransferDone      : BOOL;                 // 下游完成接收确认 / Downstream receipt confirmation
    tArriveTimeout     : TIME := T#10S;        // 到位确认超时 [ms/s]，0 = 不监控 / Arrival timeout
    tHandshakeTimeout  : TIME := T#5S;         // 双侧就绪握手超时 [ms/s] / Handshake timeout
    tTransferTimeout   : TIME := T#30S;        // 交接过程超时 [ms/s] / Transfer timeout
END_VAR
VAR_OUTPUT
    bDockLamp          : BOOL;                 // 对接允许指示灯（AGV 可进入）/ Dock-permitted lamp for AGV
    bTransferPermit    : BOOL;                 // 放行交接（AGV 可放料 / 工站可接料）/ Transfer permit
    bHandshakeOk       : BOOL;                 // 握手成功单拍 / Single pulse when handshake succeeds
    bTransferComplete  : BOOL;                 // 交接完成（保持到下次启动）/ Transfer complete, held until next cycle
    eState             : E_DL_AgvDockState;    // 主状态机当前态 / Current state
    bError             : BOOL;                 // 故障锁存 / Latched fault
    uErrorId           : UDINT;                // 事件/故障码 / Event or fault code
    tElapsed           : TIME;                 // 当前态已耗时 [ms/s]，便于现场判读 / Elapsed time in current state
END_VAR
VAR_IN_OUT
    stStat             : ST_DL_AgvDockStat;    // 跨周期统计（对接次数 / 累计交接时长）/ Persistent statistics
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS       : REAL := 1.0E-6;       // 浮点判等容差（预留）/ Float epsilon
    DL_STAT_MAX        : UDINT := 16#FFFF_FFFE;// 统计计数饱和上限 / Statistics saturation limit
END_VAR
```

**配套类型**

| 类型 | 成员 | 说明 |
|---|---|---|
| `E_DL_AgvDockState` | `eIdle := 0` / `eWaitArrive := 10` / `eDockConfirm := 20` / `ePermitTransfer := 30` / `eTransferMonitor := 40` / `eComplete := 50` / `eFault := 99` | 七态 |
| `ST_DL_AgvDockStat` | `nDockCount : UDINT`；`tTotalTransfer : TIME`；`tLastCycle : TIME` | 由调用方持有 |

**关键算法**

1. **到位节拍**：`eWaitArrive` 内 `tArriveTimeout` 计时（`TON` 主周期无条件刷新）；超时 → `02E0`，`bDockLamp` 保持 FALSE。
2. **双侧就绪**：`eDockConfirm` 需 `bAgvDockReady AND bStationReady` **同时**为 TRUE 且持续一个扫描周期（用 `R_TRIG` 后的与门），避免单拍毛刺误放行；超时 → `02E1`。
3. **物料一致性**：进入 `eTransferMonitor` 时快照 `bMaterialOnAgv`；过程中若其由 TRUE→FALSE 且 `bTransferDone` 尚未置位 → `02E2`（物料丢失/错位）。
4. **完成判定**：`bTransferDone` 上升沿 → `bTransferComplete`、`stStat.nDockCount + 1`、`bTransferPermit := FALSE`、`bHandshakeOk` 单拍 → `eComplete`；`eComplete` 保持 1 拍后回 `eIdle`。
5. **失序诊断**：`bTransferDone = TRUE` 但在 `eWaitArrive` / `eDockConfirm` 阶段出现 → `02E3`（非法请求序列），直接 `eFault`。
6. **统计**：`tTotalTransfer` 累加 `eTransferMonitor` 停留时长（`tTransferTimeout` 钳位后累加，防异常值污染均值）。

**状态机**

| 当前态 | 迁移条件 | 目标态 |
|---|---|---|
| `eIdle` | `bEnable` 且 `bAgvArrived` | `eWaitArrive`（`bDockLamp := TRUE`） |
| `eWaitArrive` | `bAgvArrived` 稳定 TRUE | `eDockConfirm` |
| `eWaitArrive` | `tArriveTimeout` 到 | `eFault`（`02E0`） |
| `eDockConfirm` | `bAgvDockReady AND bStationReady` | `ePermitTransfer` |
| `eDockConfirm` | `tHandshakeTimeout` 到 | `eFault`（`02E1`） |
| `ePermitTransfer` | 无条件（`bTransferPermit := TRUE`，`bHandshakeOk` 单拍） | `eTransferMonitor` |
| `eTransferMonitor` | `bTransferDone` 上升沿 | `eComplete` |
| `eTransferMonitor` | 物料在位信号丢失 | `eFault`（`02E2`） |
| `eTransferMonitor` | `tTransferTimeout` 到（与握手超时同族：均属「未在期望时间内建立期望状态」） | `eFault`（`02E1`） |
| `eComplete` | 保持 1 拍 | `eIdle` |
| 任意态 | `bAbort` 上升沿 | `eIdle`（不置故障） |
| **`ELSE`** | 非法值 | `eFault` + `16#0005_02E4` |

**码位表**：`16#0005_01C3` 超时参数越界已钳位（信息级）｜`16#0005_02E0` AGV 到位超时｜`16#0005_02E1` 握手/交接超时｜`16#0005_02E2` 物料在位信号丢失｜`16#0005_02E3` 非法请求序列（完成信号提前到达）｜`16#0005_02E4` 非法状态兜底。

**验收向量**

| 向量 | 输入 | 期望输出 |
|---|---|---|
| V1 正常序 | `bAgvArrived`、`bAgvDockReady`、`bStationReady` 依序 TRUE | `bDockLamp` → `bTransferPermit` → `bTransferDone` 后 `bTransferComplete = TRUE`、`bHandshakeOk` 单拍、`stStat.nDockCount +1` |
| V2 到位超时 | `tArriveTimeout = T#10S`，10 s 内 `bAgvArrived` 未建立 | `uErrorId = 16#0005_02E0`、`eState = eFault` |
| V3 物料丢失 | `eTransferMonitor` 内 `bMaterialOnAgv` TRUE→FALSE 且 `bTransferDone = FALSE` | `uErrorId = 16#0005_02E2`、`bTransferPermit = FALSE` |
| V4 完成信号提前 | `eWaitArrive` 阶段 `bTransferDone = TRUE` | `uErrorId = 16#0005_02E3`、直接 `eFault` |
| V5 统计 | 一轮交接在 `eTransferMonitor` 停留 12 s，`tTransferTimeout = T#30S` | `stStat.tLastCycle = T#12S`，`tTotalTransfer` 累加 12 s |

---

### 4. `FB_DL_EnergySavingMode` —— 产线空闲智能节能模式管理器

- **子库**：DL_Process ｜ **前缀**：`FB_DL_` ｜ **预计行数**：460 ｜ **来源组标签**：`isa-88`、`lbp-process`、`namur-ne43`
- **一句话功能**：以「空闲确认延时 → 节能态（降压/停热/伺服休眠）→ 唤醒缓冲（压力先恢复再放行）」三段编排节能与生产，输出可解释的节能标志与累计节能时长，杜绝「唤醒即放行」造成的低压启动。
- **与既有件边界**：`FB_DL_DutyStandbyRotation` 管**多台设备轮值**；`FB_DL_RuntimeMeter` 管**单机运行时长**；本件管**整线状态级**的能量模式切换与放行门控，不替代任何单机控制块。
- **依赖**：仅标准库（压力/温度全部经引脚注入，不读任何外部变量）。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_EnergySavingMode
VAR_INPUT
    bEnable            : BOOL;                 // 使能；FALSE 立即回 eRun 并撤回节能请求 / Enable; returns to eRun on FALSE
    bReset             : BOOL;                 // 上升沿复位故障 / Rising edge clears fault
    bLineIdle          : BOOL;                 // 产线空闲判据（无料且无作业）/ Line idle criterion
    bWakeRequest       : BOOL;                 // 唤醒请求（来料 / 操作员 / 上位机）/ Wake-up request
    fAirPressureAct    : REAL;                 // 实际气源压力 [bar]，量程 0.0~10.0 / Actual air pressure [bar]
    fAirPressureEco    : REAL := 4.0;          // 节能目标压力 [bar] / Eco target pressure [bar]
    fWakeMargin        : REAL := 0.2;          // 唤醒压力裕量 [bar]，恢复需达 目标+裕量 / Wake margin [bar]
    tIdleDelay         : TIME := T#120S;       // 空闲确认延时 [ms/s]，0 = 立即节能 / Idle confirm delay
    tWakeRamp          : TIME := T#3S;         // 唤醒缓冲（压力恢复等待上限）[ms/s] / Wake ramp allowance
    bServoSleepPermit  : BOOL;                 // 允许伺服休眠（工艺侧给出）/ Servo sleep permitted by process
    bHeatStandbyPermit : BOOL;                 // 允许加热转保温/关闭 / Heater standby permitted
END_VAR
VAR_OUTPUT
    bEcoActive         : BOOL;                 // 节能模式生效 / Eco mode active
    bAirPressureLow    : BOOL;                 // 请求降压（送气源比例阀）/ Request reduced air pressure
    bHeatStandby       : BOOL;                 // 请求加热转保温 / Request heater standby
    bServoSleep        : BOOL;                 // 请求伺服休眠 / Request servo sleep
    bReadyToRun        : BOOL;                 // 唤醒完成，可放行生产 / Ready to run after wake
    eState             : E_DL_EcoModeState;    // 主状态机当前态 / Current state
    bError             : BOOL;                 // 故障锁存 / Latched fault
    uErrorId           : UDINT;                // 事件/故障码 / Event or fault code
    tIdleElapsed       : TIME;                 // 空闲累计已计时长 [ms/s] / Idle elapsed time
    tEcoElapsed        : TIME;                 // 本次节能已持续时长 [ms/s] / Eco elapsed time
END_VAR
VAR_IN_OUT
    stStat             : ST_DL_EcoStat;        // 跨周期统计（节能累计时长 / 切换次数）/ Persistent statistics
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS       : REAL := 1.0E-6;       // 浮点判等容差 / Float epsilon
    DL_PRESSURE_MAX    : REAL := 10.0;         // 压力上限 [bar]，用于越界判定 / Pressure upper bound [bar]
    DL_SWITCH_MAX      : UDINT := 16#FFFF_FFFE;// 切换次数饱和上限 / Switching counter saturation
END_VAR
```

**配套类型**

| 类型 | 成员 | 说明 |
|---|---|---|
| `E_DL_EcoModeState` | `eRun := 0` / `eIdleCount := 10` / `eEco := 20` / `eWake := 30` / `eFault := 99` | 四工作态 + 故障 |
| `ST_DL_EcoStat` | `tTotalEco : TIME`；`nSwitchCount : UDINT`；`tLastEco : TIME` | 由调用方持有 |

**关键算法**

1. **空闲确认**：`eIdleCount` 内 `bLineIdle` 必须**持续** TRUE（中途掉沿则 `TON` 复位回 `eRun`）；`tIdleDelay = T#0S` 时直通。
2. **节能输出编排**：进入 `eEco` 的顺序固定为「先降压 → 再停热 → 最后伺服休眠」，每步间隔 `DL_STEP_GAP`（常量 `T#500MS`）；原因：伺服休眠时若气源仍为工作压力，抱闸释放瞬间会顶件。**退出顺序严格反序**。
3. **唤醒门控**：`eWake` 内 `bReadyToRun := (fAirPressureAct >= fAirPressureEco + fWakeMargin) AND NOT bAirPressureLow`；压力恢复后仍需等 `tWakeRamp` 剩余时间走完（取两者**同时**满足），防「压力表冲高瞬放行」。
4. **压力反馈失效**：`fAirPressureAct <= DL_FLOAT_EPS` 且 `bEcoActive` → `02F1`（信息级转故障级：无反馈时无法确认恢复，禁止放行）。
5. **统计**：`eEco` 转出拍 `stStat.tLastEco := tEcoElapsed`、`tTotalEco := tTotalEco + tEcoElapsed`、`nSwitchCount + 1`。

**状态机**

| 当前态 | 迁移条件 | 目标态 |
|---|---|---|
| `eRun` | `bLineIdle` 上升沿 | `eIdleCount` |
| `eIdleCount` | `tIdleDelay` 到且 `bLineIdle` 仍 TRUE | `eEco` |
| `eIdleCount` | `bLineIdle` 掉沿 | `eRun` |
| `eEco` | `bWakeRequest` 或 `NOT bLineIdle` | `eWake` |
| `eEco` | 压力反馈失效 | `eFault`（`02F1`） |
| `eWake` | 压力达 `目标 + 裕量` 且 `tWakeRamp` 走完 | `eRun`（`bReadyToRun` 保持 1 拍后转出） |
| `eWake` | 超过 `2 × tWakeRamp` 仍未达压 | `eFault`（`02F0`） |
| `eFault` | `bReset` 上升沿 | `eRun` |
| **`ELSE`** | 非法值 | `eFault` + `16#0005_02F2` |

**码位表**：`16#0005_01C4` 延时/压力参数越界已钳位（信息级）｜`16#0005_02F0` 唤醒超时（压力未恢复）｜`16#0005_02F1` 气源压力反馈缺失｜`16#0005_02F2` 非法状态兜底。

**验收向量**

| 向量 | 输入 | 期望输出 |
|---|---|---|
| V1 进入节能 | `bLineIdle` 持续 TRUE 达 `tIdleDelay = T#120S` | `bEcoActive = TRUE`，`bAirPressureLow = TRUE`（t=120 s 拍） |
| V2 唤醒门控 | `fAirPressureEco = 4.0 bar`、`fWakeMargin = 0.2 bar`、`fAirPressureAct = 4.1 bar` | `bReadyToRun = FALSE`（未达 4.2 bar） |
| V3 唤醒完成 | 同上但 `fAirPressureAct = 4.25 bar` 且 `tWakeRamp` 已走完 | `bReadyToRun = TRUE`，下一拍 `eState = eRun` |
| V4 反馈缺失 | `fAirPressureAct = 0.0` 且 `bEcoActive = TRUE` | `uErrorId = 16#0005_02F1`、`eState = eFault` |
| V5 统计 | 一次节能持续 300 s | `stStat.tTotalEco` 增加 `T#300S`、`nSwitchCount +1` |

---

### 5. `FB_DL_PortDiagAggregator` —— 端口级诊断聚合与首出定位（T1-7 port-based 诊断族）

- **子库**：DL_Device ｜ **前缀**：`FB_DL_` ｜ **预计行数**：540 ｜ **来源组标签**：`plcnext-community`、`profibus-diag`、`namur-ne107`
- **一句话功能**：把 **最多 8 个现场总线端口**的链路状态 / 诊断码 / 错误计数聚合成单一掩码、首出端口与错误风暴标志，解决「多端口同时报警时 HMI 只能看到最后一个」的现场痛点。
- **与既有件边界**：`FB_DL_AxiolineDiagLatch` 做**本地总线模块级**（槽号 + 位域）诊断锁存；`FB_DL_PdiReadScheduler` 做**参数对象读取调度**；本件做**端口级**（通讯物理端口）聚合与首出仲裁。三者数据源不同、码段不共享。
- **依赖**：仅标准库（端口状态全部**引脚注入**，不绑定任何厂商系统变量名）。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_PortDiagAggregator
VAR_INPUT
    bEnable          : BOOL;                              // 使能；FALSE 时掩码清零、首出保持 / Enable; clears mask, holds first-out
    bReset           : BOOL;                              // 上升沿复位首出锁存 / Rising edge clears first-out latch
    nPortCount       : INT;                               // 实际端口数 [个]，有效域 1~8 / Port count, 1..8
    abPortLinkOk     : ARRAY[1..8] OF BOOL;               // 各端口链路正常标志 / Per-port link-up flags
    auPortErrCode    : ARRAY[1..8] OF UDINT;              // 各端口诊断码，0 = 正常 / Per-port diagnostic code, 0 = OK
    auPortCrcErrCnt  : ARRAY[1..8] OF UDINT;              // 各端口 CRC 错误累计计数 / Per-port CRC error counter
    nBurstThreshold  : UDINT := 10;                       // 窗口内错误增量阈值 [次]，0 = 不判风暴 / Burst threshold per window
    tBurstWindow     : TIME := T#1S;                      // 错误风暴统计窗口 [ms/s] / Burst evaluation window
    tDebounce        : TIME := T#200MS;                   // 端口故障确认去抖 [ms]，0 = 不去抖 / Port fault debounce
END_VAR
VAR_OUTPUT
    bAnyPortFault    : BOOL;                              // 任一端口感故障 / Any port faulted
    bBurstDetected   : BOOL;                              // 错误风暴（窗口增量超阈值）/ Error burst detected
    uPortFaultMask   : WORD;                              // 端口故障掩码，bit(n-1) 对应第 n 端口 / Port fault mask
    nFirstFaultPort  : INT;                               // 首出故障端口号 [1..8]，0 = 无 / First-fault port number
    uFirstFaultCode  : UDINT;                             // 首出端口诊断码 / First-fault diagnostic code
    auPortDelta      : ARRAY[1..8] OF UDINT;              // 本窗口各端口错误增量 [次] / Per-port counter delta
    eState           : E_DL_PortDiagPhase;                // 主状态机当前态 / Current state
    bError           : BOOL;                              // 故障级锁存 / Latched fault
    uErrorId         : UDINT;                             // 事件/故障码 / Event or fault code
END_VAR
VAR_IN_OUT
    stState          : ST_DL_PortDiagState;               // 跨周期状态（上窗口计数 / 首出锁存）/ Persistent state
END_VAR
VAR CONSTANT
    DL_PORT_MAX      : INT := 8;                          // 端口上限 [个] / Max port count
    DL_PORT_MASK_ALL : WORD := 16#00FF;                   // 8 端口全掩码 / All-port mask
END_VAR
```

**配套类型**

| 类型 | 成员 | 说明 |
|---|---|---|
| `ST_DL_PortDiagState` | `auPrevCnt : ARRAY[1..8] OF UDINT`；`nLatchPort : INT`；`uLatchCode : UDINT`；`bLatchValid : BOOL` | `nLatchPort / uLatchCode` 为**首出**锁存，仅 `bReset` 可清 |
| `E_DL_PortDiagPhase` | `eIdle := 0` / `eMonitor := 10` / `eBurst := 20` / `eFault := 99` | 监视型件的三工作态 + 故障态（**与 `ST_DL_PortDiagState` 刻意同名不同前缀**：前者是跨周期数据，后者是相位枚举） |

**关键算法**

1. **端口数钳位**：`nPortCount < 1` → `0301`（诊断源为零）；`> DL_PORT_MAX` → 钳位 8 并置 `0140`（信息级）。
2. **增量差分**：`auPortDelta[i] := auPortCrcErrCnt[i] - stState.auPrevCnt[i]`，若 `auPortCrcErrCnt[i] < auPrevCnt[i]`（计数器回绕/复位）则 `auPortDelta[i] := auPortCrcErrCnt[i]`（按归零处理，**不**算负数，UDINT 语义）。
3. **风暴判定**：窗口结束拍（`tBurstWindow` 到时）对 `auPortDelta` 求最大值，`> nBurstThreshold` → `bBurstDetected := TRUE`（单拍），随后把 `auPrevCnt` 全部装载为本拍计数、`auPortDelta` 清零。
4. **端口故障**：`(NOT abPortLinkOk[i]) OR (auPortErrCode[i] <> 0)` 经 `tDebounce` 去抖后置 `uPortFaultMask.bit(i-1)`。
5. **首出仲裁**：仅在 `stState.bLatchValid = FALSE` 时锁存；同拍多端口故障取**端口号最小者**（现场惯例：低号端口更靠近主站）；锁存后不再更新，`bReset` 上升沿清。
6. **输出一致性**：`bAnyPortFault := (uPortFaultMask AND DL_PORT_MASK_ALL) <> 0`，避免高位脏数据误判。

**状态机（ENUM + CASE，监视型三段式）**

| 当前态 | 迁移条件 | 目标态 |
|---|---|---|
| `eIdle` | `bEnable` 且 `nPortCount >= 1` | `eMonitor` |
| `eIdle` | `nPortCount < 1` | `eFault`（`0301`） |
| `eMonitor` | 窗口结束拍且`最大增量 <= nBurstThreshold` | `eMonitor`（自保持，装载 `auPrevCnt`） |
| `eMonitor` | 窗口结束拍且`最大增量 > nBurstThreshold` | `eBurst`（当拍 `bBurstDetected := TRUE`） |
| `eMonitor` | 去抖后掩码非 0 | `eMonitor`（`bError := TRUE`，`0300` 锁存） |
| `eBurst` | 保持 1 拍（风暴是**趋势事件**不锁存） | `eMonitor` |
| `eFault` | `bReset` 上升沿 | `eIdle` |
| **`ELSE`** | 非法值 | `eFault` + `16#0003_0307` |

> **设计说明**：本件虽是监视型，但「窗口差分 → 风暴判定」本身有明确的拍序（窗口边界拍必须与装载拍分离，否则增量恒为 0——这是 R24/R25 单拍纪律在监视件上的变体），故引入三工作态；`eBurst` 只停留 1 拍，不构成告警锁存（告警锁存归 `0300` 与首出结构）。

**码位表**：`16#0003_0140` 端口数越界已钳位（信息级）｜`16#0003_0141` 去抖/窗口参数越界已钳位（信息级）｜`16#0003_0300` 端口故障锁存（故障级，伴随 `uPortFaultMask <> 0`）｜`16#0003_0301` 诊断源未注入（`nPortCount < 1`，故障级）｜`16#0003_0307` 非法状态兜底（故障级）。

> R21 口径：`0300/0301/0307` 属故障级故置 `bError`；`0140/0141` 只进 `uErrorId` 与趋势，不置任何故障位。

**验收向量**

| 向量 | 输入 | 期望输出 |
|---|---|---|
| V1 掩码 | 端口 2 与端口 5 故障，其余正常 | `uPortFaultMask = 16#0012`（bit1 = 2、bit4 = 16）、`bAnyPortFault = TRUE` |
| V2 首出 | 端口 5 先故障 → 端口 2 后故障 | `nFirstFaultPort = 5`、`uFirstFaultCode = 端口5码`；`bReset` 后才可更新为 2 |
| V3 风暴 | `tBurstWindow = T#1S`、`nBurstThreshold = 10`、端口 3 计数 100 → 115 | 窗口结束拍 `auPortDelta[3] = 15`、`bBurstDetected = TRUE`（单拍） |
| V4 回绕不误判 | 端口 4 计数 16#FFFF_FFFF → 3 | `auPortDelta[4] = 3`（不出现巨大正数） |
| V5 端口数钳位 | `nPortCount = 12` | 钳位 8、`uErrorId = 16#0003_0140`、`bError = FALSE` |

---

### 6. `FB_DL_StatusWordSegDecoder` —— 设备状态字批量位段解码器（DWORD / LWORD × N 段表驱动）

- **子库**：DL_Device ｜ **前缀**：`FB_DL_` ｜ **预计行数**：500 ｜ **来源组标签**：`lgf-bitlogic`、`rockwell-aoi`、`plcnext-community`
- **一句话功能**：用一张**段描述表**（最多 16 段，每段 = 偏移 + 宽度 + 名称）把设备状态字一次性解码成值数组，并给出越界 / 重叠 / 段数三类组态诊断；替代「每字段调用一次单段提取函数」的碎片写法。
- **与既有件边界（写死，禁止重复实现）**：`FC_DL_BitGet` = 取**单**位；`FB_DL_UnpackWordToBits` = WORD 拆 **16 个固定位**；`FC_DL_BitFieldExtract` = 取**单**段（1~32 位）；`FC_DL_WordBitPack` = **单**段打包；**本件 = 段表驱动的 N 段批量解码 + 段间重叠诊断**，是本族唯一的「组态级」件。四者互斥。
- **依赖**：仅标准库（**不调用** `FC_DL_BitFieldExtract`，A 泳道零跨依赖）。
- **双宽域实现**：入口统一为 `LWORD`（64 位），DWORD 调用方高位补 0 即可；**不拆 DWORD / LWORD 两块**（宽度是参数域，不是语义差异）。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_StatusWordSegDecoder
VAR_INPUT
    bEnable            : BOOL;                     // 使能；FALSE 时值数组清零 / Enable; clears value array on FALSE
    bReset             : BOOL;                     // 上升沿清组态诊断 / Rising edge clears configuration diagnostics
    uWord              : LWORD;                    // 被解码状态字（64 位，DWORD 请高位补 0）/ Source status word, 64-bit
    nSegCount          : INT;                      // 有效段数 [个]，有效域 1~16 / Valid segment count, 1..16
    bRejectOnOverlap   : BOOL;                     // TRUE = 存在重叠则整表拒绝；FALSE = 后者覆盖 / Reject whole table on overlap
END_VAR
VAR_OUTPUT
    auValue            : ARRAY[1..16] OF UDINT;    // 各段解码值（右对齐，未定义段为 0）/ Decoded values, right-aligned
    nValidCount        : INT;                      // 实际成功解码的段数 [个] / Successfully decoded segment count
    uSegStatusMask     : WORD;                     // 段状态位：置位 = 该段越界或重叠被拒 / Segment status bits
    eState             : E_DL_SegDecodePhase;      // 主状态机当前态 / Current state
    bConfigFault       : BOOL;                     // 段表组态故障（重叠 / 全非法）/ Segment table configuration fault
    uErrorId           : UDINT;                    // 事件/故障码 / Event or fault code
END_VAR
VAR_IN_OUT
    stSegs             : ST_DL_BitSegTable;        // 段描述表（偏移 / 宽度 / 名称），块内只读 / Segment descriptor table, read-only
END_VAR
VAR CONSTANT
    DL_SEG_MAX         : INT := 16;                // 段数上限 [段] / Max segment count
    DL_WORD_BITS       : INT := 64;                // 字宽 [bit] / Word width in bits
    DL_MASK64_ALL      : LWORD := 16#FFFF_FFFF_FFFF_FFFF; // 全 1 掩码（64 位特例用）/ All-ones mask
END_VAR
```

**配套类型**

| 类型 | 成员 | 说明 |
|---|---|---|
| `ST_DL_BitSeg` | `nOffset : USINT` [bit]；`nWidth : USINT` [bit]；`sName : STRING[16]` | `nOffset` 0~63，`nWidth` 1~64 |
| `ST_DL_BitSegTable` | `aSeg : ARRAY[1..16] OF ST_DL_BitSeg`；`nReserved : INT` | `nReserved` 预留（库内结构体惯例） |
| `E_DL_SegDecodePhase` | `eIdle := 0` / `eDecode := 10` / `eReject := 20` / `eFault := 99` | `eReject` = 段表整体不可用（组态故障态，需 `bReset` 退出） |

**关键算法**

1. **段数钳位**：`nSegCount < 1` → `0144` 并整体不动作；`> 16` → 钳位 16 + `0144`。
2. **逐段越界判定**：`nOffset + nWidth > 64` 或 `nWidth = 0` → 该段置 `uSegStatusMask.bit(i-1)`、`auValue[i] := 0`、`nValidCount` 不计，并置 `0143`（**其余段照常解码**，不整表作废）。
3. **重叠检测**：用 `LWORD` 占位掩码逐段 `OR`，若 `(uOccupy AND uSegMask) <> 0` 即重叠 → 置段状态位与 `0142`；`bRejectOnOverlap = TRUE` 时该段丢弃，`FALSE` 时允许覆盖（值取**后段**）。
4. **掩码构造**：`nWidth = 64` 时用 `DL_MASK64_ALL`（**禁止** `SHL(x, 64)`，未定义行为，同 R10 `FC_DL_BitFieldExtract` 教训）；否则 `uMask := SHL(LWORD#1, nWidth) - 1`，再 `SHL(uMask, nOffset)`。
5. **取值**：`auValue[i] := LWORD_TO_UDINT(SHR(uWord AND uSegMask, nOffset))`（显式转换，禁隐式，R29 邻域纪律）。
6. **组态故障判定**：`nValidCount = 0` 且 `nSegCount >= 1` → `bConfigFault := TRUE` + `0302`（故障级，锁存需 `bReset`）。

**状态机（ENUM + CASE）**

| 当前态 | 迁移条件 | 目标态 |
|---|---|---|
| `eIdle` | `bEnable` | `eDecode` |
| `eDecode` | `nValidCount >= 1` | `eDecode`（自保持，逐拍重解） |
| `eDecode` | `nValidCount = 0` 且 `nSegCount >= 1` | `eReject`（`0302`、`bConfigFault := TRUE`） |
| `eDecode` / `eReject` | `NOT bEnable` | `eIdle`（`auValue` 清零） |
| `eReject` | `bReset` 上升沿且段表已修正 | `eIdle` |
| **`ELSE`** | 非法值 | `eFault` + `16#0003_0302` |

**码位表**：`16#0003_0142` 段重叠（信息级；`bRejectOnOverlap` 时该段作废）｜`16#0003_0143` 段越界已拒绝（信息级）｜`16#0003_0144` 段数越界已钳位（信息级）｜`16#0003_0302` 段表整体非法（故障级，`bConfigFault`）。

**验收向量**

| 向量 | 输入 | 期望输出 |
|---|---|---|
| V1 单段（跨半字节） | `uWord = 16#1234`，段 1 =（offset 4, width 8） | `auValue[1] = 16#23 = 35` |
| V2 双段 | 段 1 =（4,8）、段 2 =（8,8） | `auValue[1] = 35`、`auValue[2] = 16#12 = 18` |
| V3 重叠 | 段 1 =（0,8）、段 2 =（4,8）、`bRejectOnOverlap = TRUE` | `uSegStatusMask = 16#0003`、`nValidCount = 1`、`uErrorId = 16#0003_0142` |
| V4 越界 | 段 =（60,8） | 该段 `auValue = 0`、状态位置位、`uErrorId = 16#0003_0143`，其余段不受影响 |
| V5 64 位特例 | 段 =（0,64）、`uWord = 16#FFFF_FFFF_FFFF_FFFF` | `auValue` 返回 `16#FFFF_FFFF`（低 32 位），无 `SHL(x,64)` 路径 |

---

### 7. `FB_DL_NtcTempScan` —— 多通道 NTC 温度巡检（设备级粗粒度）

- **子库**：DL_Device ｜ **前缀**：`FB_DL_` ｜ **预计行数**：520 ｜ **来源组标签**：`rockwell-aoi`、`oscat-building`、`lgf-measurement`
- **一句话功能**：一块覆盖 1~16 路 NTC 的完整设备对象：B 值公式换算温度、逐通道断线/短路诊断、高温/低温判定、最热通道定位与超温累计，替代「每通道一个温控块」的堆叠写法。
- **与既有件边界**：`FB_DL_AnalogTransmitter` 处理 **4~20 mA / 0~10 V 变送器**（线性标定 + NE43 诊断）；本件处理**电阻型 NTC**（非线性 B 值公式 + 阻值域诊断），输入量纲不同，不可互替。`FB_DL_HeatCoolZone` 是**控温**执行块（PID + SSR），本件只做**测量与判定**（不做任何控制输出）。
- **依赖**：仅标准库（`LN` / `EXP` 属标准函数）。
- **AOI 粗粒度借鉴**：参数分四段——输入段 = 阻值数组与通道数；输出段 = 温度数组与统计量；只读属性段 = 通道故障掩码；内部段 = 轮询索引与统计（`rockwell-aoi` 参数分段范式的 clean-room 复用）。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_NtcTempScan
VAR_INPUT
    bEnable          : BOOL;                            // 使能；FALSE 时保持上次温度 / Enable; holds last temperatures on FALSE
    bReset           : BOOL;                            // 上升沿复位通道故障锁存 / Rising edge clears channel fault latch
    nChannelCount    : INT;                             // 通道数 [路]，有效域 1~16 / Channel count, 1..16
    afResistance     : ARRAY[1..16] OF REAL;            // 各通道 NTC 阻值 [Ω]，量程 10.0~1.0E6 / Per-channel resistance [ohm]
    fBeta            : REAL := 3950.0;                  // NTC B 常数 [K]，典型 3435 / 3950 / Beta constant [K]
    fR25             : REAL := 10000.0;                 // 25 °C 标称阻值 [Ω] / Nominal resistance at 25 degC [ohm]
    fT25             : REAL := 298.15;                  // 基准绝对温度 [K] / Reference absolute temperature [K]
    afTempHigh       : ARRAY[1..16] OF REAL;            // 各通道高温阈值 [°C] / Per-channel high limit [degC]
    afTempLow        : ARRAY[1..16] OF REAL;            // 各通道低温阈值 [°C] / Per-channel low limit [degC]
    tScanPeriod      : TIME := T#100MS;                 // 通道轮询节拍 [ms]，0 = 全通道每拍扫描 / Channel scan period
END_VAR
VAR_OUTPUT
    afTempC          : ARRAY[1..16] OF REAL;            // 各通道温度 [°C] / Per-channel temperature [degC]
    nHottestCh       : INT;                             // 最热通道号 [1..16]，0 = 无有效通道 / Hottest channel number
    fHottestTemp     : REAL;                            // 最热通道温度 [°C] / Hottest temperature [degC]
    bAnyOverTemp     : BOOL;                            // 任一通道超高温阈值 / Any channel above high limit
    bAnyUnderTemp    : BOOL;                            // 任一通道低于低温阈值 / Any channel below low limit
    uChannelFaultMask: WORD;                            // 通道故障掩码，bit(n-1)：断线 / 短路分别见码表 / Channel fault mask
    eState           : E_DL_NtcScanPhase;               // 主状态机当前态 / Current state
    bError           : BOOL;                            // 故障锁存（全通道失效等）/ Latched fault
    uErrorId         : UDINT;                           // 事件/故障码 / Event or fault code
END_VAR
VAR_IN_OUT
    stStat           : ST_DL_NtcStat;                   // 跨周期统计（逐通道超温次数 / 断线次数）/ Persistent statistics
END_VAR
VAR CONSTANT
    DL_CH_MAX        : INT  := 16;                      // 通道上限 [路] / Max channel count
    DL_R_OPEN        : REAL := 1.0E6;                   // 断线判定阻值上限 [Ω] / Open-circuit resistance threshold
    DL_R_SHORT       : REAL := 10.0;                    // 短路判定阻值下限 [Ω] / Short-circuit resistance threshold
    DL_KELVIN_OFFSET : REAL := 273.15;                  // 摄氏/开尔文偏移 [K] / Kelvin offset
    DL_FLOAT_EPS     : REAL := 1.0E-6;                  // 浮点判等容差 / Float epsilon
END_VAR
```

**配套类型**

| 类型 | 成员 | 说明 |
|---|---|---|
| `ST_DL_NtcStat` | `anOverTempCnt : ARRAY[1..16] OF UDINT`；`anOpenCnt : ARRAY[1..16] OF UDINT`；`nScanRounds : UDINT` | 由调用方持有 |
| `E_DL_NtcScanPhase` | `eIdle := 0` / `eScan := 10` / `eAllFail := 20` / `eFault := 99` | `eAllFail` = 有效通道为 0（不可降级的故障态） |

**关键算法**

1. **B 值换算**（Steinhart 简化 / Beta 方程，公开物理公式）：
   `fTempK := 1.0 / (1.0 / fT25 + LN(fR / fR25) / fBeta)`；`afTempC[i] := fTempK - DL_KELVIN_OFFSET`。
   前置守卫：`fR <= DL_FLOAT_EPS`、`fR25 <= DL_FLOAT_EPS`、`ABS(fBeta) < DL_FLOAT_EPS` 任一成立 → 本通道保持上次值 + `0304`（**不做除法**）。
2. **通道诊断**：`fR >= DL_R_OPEN` → 断线位；`fR <= DL_R_SHORT` → 短路位；两者共用 `uChannelFaultMask`（断线置位，短路置位并同时置 `0146` 区分语义写入 `uErrorId`）。
3. **轮询扫描**：`tScanPeriod > T#0S` 时每拍只扫一个通道（`nScanIdx` 环形推进），降低高通道数时的单拍负载；`tScanPeriod = T#0S` 时全通道每拍扫描。
4. **最热通道**：仅在有有效通道时计算；**平局取通道号最小者**（避免逐拍跳变）；全通道无效 → `nHottestCh := 0`、`0303`。
5. **温限判定**：逐通道比较（`>` 高温 → 超温；`<` 低温 → 低温）；超温在**上升沿**累加 `stStat.anOverTempCnt[i]`（持续超温不重复计数）。
6. **锁存策略**：单通道故障只置掩码 + 信息码（不置 `bError`）；`bError` 仅在「有效通道数 = 0」时置位（`0303`），符合 R21。

**状态机（ENUM + CASE）**

| 当前态 | 迁移条件 | 目标态 |
|---|---|---|
| `eIdle` | `bEnable` | `eScan` |
| `eScan` | 有效通道数 ≥ 1 | `eScan`（自保持，轮询推进） |
| `eScan` | 有效通道数 = 0 | `eAllFail`（`0303`、`bError := TRUE`） |
| `eScan` | `fBeta` / `fR25` 非法 | `eFault`（`0304`，一次性锁存） |
| `eAllFail` | 任一通道恢复有效 | `eScan`（自动恢复：全失效可由接线修复自愈，不应强制复位） |
| `eFault` | `bReset` 上升沿 | `eIdle` |
| **`ELSE`** | 非法值 | `eFault` + `16#0003_0303` |

**码位表**：`16#0003_0145` 通道数越界已钳位（信息级）｜`16#0003_0146` 单通道断线/短路已跳过（信息级）｜`16#0003_0303` 全通道失效（故障级）｜`16#0003_0304` B 值 / R25 参数非法，已回退默认（故障级，一次性，需 `bReset`）。

**验收向量**

| 向量 | 输入 | 期望输出 |
|---|---|---|
| V1 基准点 | `fR = 10000 Ω`、`fR25 = 10000 Ω`、`fBeta = 3950` | `LN(1) = 0` → `fTempK = 298.15 K` → `afTempC = 25.00 °C`（±0.05） |
| V2 双倍阻值 | `fR = 20000 Ω`，其余同上 | `1/T = 1/298.15 + LN(2)/3950 = 0.0035295` → `T = 283.33 K` → `10.2 °C`（±0.1） |
| V3 半阻值 | `fR = 5000 Ω` | `1/T = 0.0031785` → `T = 314.61 K` → `41.5 °C`（±0.1） |
| V4 断线 | 通道 3 `fR = 1.2E6 Ω` | `uChannelFaultMask.bit2 = 1`（`16#0004`）、`afTempC[3]` 保持上次值、`bError = FALSE` |
| V5 全失效 | 16 通道全部断线 | `nHottestCh = 0`、`uErrorId = 16#0003_0303`、`bError = TRUE` |

---

### 8. `FB_DL_RollerGapAdjust` —— 辊距伺服微调与背隙补偿（设备级）

- **子库**：DL_Device ｜ **前缀**：`FB_DL_` ｜ **预计行数**：440 ｜ **来源组标签**：`rockwell-aoi`、`lbp-process`、`lgf-technology`
- **一句话功能**：把「目标辊距 → 单向逼近（吃掉背隙）→ 到位窗口判定 → 偏差记账」封装成设备对象，输出位置指令与到位状态；解决电动缸双向逼近时**背隙导致的重复定位偏差**。
- **与既有件边界**：`FB_DL_ThreePointValve` 是**浮点式阀**开度积分估算；`FB_DL_AnalogValve` 是**模拟量比例阀**；本件是**位置伺服式间隙调整**（带背隙补偿与到位窗口），执行机构语义不同。
- **依赖**：仅标准库（不注入轴接口：辊距调整多为独立电动缸 + 位移传感器，避免与 `DL_Motion` 层耦合，保持层间合法）。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_RollerGapAdjust
VAR_INPUT
    bEnable          : BOOL;                // 使能；FALSE 时指令保持、撤回到位标志 / Enable; holds command, drops in-position flag
    bReset           : BOOL;                // 上升沿复位故障 / Rising edge clears fault
    bAdjustStart     : BOOL;                // 上升沿执行一次调整（单次触发，电平不复位）/ Rising edge triggers one adjustment
    fGapSetpoint     : REAL;                // 目标辊距 [mm]，量程 0.0~20.0 / Target roller gap [mm]
    fGapActual       : REAL;                // 位移传感器实测辊距 [mm] / Measured roller gap [mm]
    fGapTol          : REAL := 0.02;        // 到位容差 [mm]，0 表示必须完全相等 / In-position tolerance [mm]
    fBacklash        : REAL := 0.05;        // 反向背隙补偿量 [mm]，0 表示不补偿 / Backlash compensation [mm]
    fCmdMin          : REAL := 0.0;         // 指令下限 [mm] / Command lower limit [mm]
    fCmdMax          : REAL := 20.0;        // 指令上限 [mm] / Command upper limit [mm]
    bFeedbackValid   : BOOL;                // 位移反馈有效（传感器自诊断汇总）/ Position feedback valid
    tMoveTimeout     : TIME := T#10S;       // 单次调整超时 [ms/s]，0 = 不监控 / Adjustment timeout
END_VAR
VAR_OUTPUT
    fGapCmd          : REAL;                // 电动缸位置指令 [mm] / Actuator position command [mm]
    bAdjusting       : BOOL;                // 调整进行中 / Adjustment in progress
    bInPosition      : BOOL;                // 到位（保持到下次调整）/ In position, held until next adjustment
    eState           : E_DL_GapPhase;       // 主状态机当前态 / Current state
    bError           : BOOL;                // 故障锁存 / Latched fault
    uErrorId         : UDINT;               // 事件/故障码 / Event or fault code
    fLastDeviation   : REAL;                // 上次调整结束时的残余偏差 [mm] / Residual deviation of last adjustment [mm]
    nAdjustCount     : UDINT;               // 累计调整次数（饱和）/ Adjustment counter, saturating
END_VAR
VAR_IN_OUT
    stTrim           : ST_DL_GapTrimStat;   // 跨周期统计（偏差趋势 / 平均调整耗时）/ Persistent statistics
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS     : REAL := 1.0E-6;      // 浮点判等容差 / Float epsilon
    DL_APPROACH_SIGN : REAL := -1.0;        // 逼近方向（负向吃背隙）/ Approach direction sign
    DL_BACKLASH_MAX  : REAL := 1.0;         // 背隙补偿上限 [mm]，防组态错值 / Backlash compensation upper bound [mm]
END_VAR
```

**配套类型**

| 类型 | 成员 | 说明 |
|---|---|---|
| `ST_DL_GapTrimStat` | `fDevAvg : REAL` [mm]；`tLastMove : TIME`；`nOverTolCnt : UDINT` | 偏差均值用于预测机械磨损 |
| `E_DL_GapPhase` | `eIdle := 0` / `eApproach := 10` / `eFine := 20` / `eHold := 30` / `eFault := 99` | `eApproach` = 越过目标的吃背隙段；`eFine` = 反向精定位段；`eHold` = 到位保持 |

**关键算法**

1. **参数钳位**：`fGapSetpoint` 钳到 `[fCmdMin, fCmdMax]`，越界置 `0147`；`fBacklash` 钳到 `[0, DL_BACKLASH_MAX]`，越界置 `0148`；`fGapTol < 0` 取绝对值。
2. **背隙补偿两阶段**：阶段 A `fGapCmd := fGapSetpoint + DL_APPROACH_SIGN * fBacklash`（先越过目标 `fBacklash`），阶段 B 反向逼近 `fGapCmd := fGapSetpoint`。**始终从同一侧逼近**，保证重复定位一致性。
3. **到位判定**：`ABS(fGapActual - fGapSetpoint) <= fGapTol` 且 `bFeedbackValid` → `bInPosition := TRUE`，`fLastDeviation := fGapActual - fGapSetpoint`。
4. **反馈无效**：`bFeedbackValid = FALSE` → `fGapCmd` **保持上一拍值**（不得清零，清零等于全开，属危险侧），置 `0306`。
5. **超时**：`tMoveTimeout` 到时仍未到位 → `0305` + `eFault` 等价处理（本件为监视线程型，`bError := TRUE`，`bAdjusting := FALSE`，指令保持）。
6. **统计**：到位拍累加 `stTrim.fDevAvg` 的一阶低通（`fDevAvg := fDevAvg + 0.2 * (fLastDeviation - fDevAvg)`，系数提为常量），偏差超容差次数累加 `nOverTolCnt`。

**状态机（ENUM + CASE，四态）**

| 当前态 | 迁移条件 | 目标态 |
|---|---|---|
| `eIdle` | `bAdjustStart` 上升沿且 `bFeedbackValid` | `eApproach`（`fGapCmd := 目标 + 逼近符号 × 背隙`） |
| `eIdle` | `bAdjustStart` 上升沿但 `bFeedbackValid = FALSE` | `eFault`（`0306`，指令保持） |
| `eApproach` | 反馈已达「目标 + 逼近符号 × 背隙 × 0.5」（越程过半） | `eFine`（`fGapCmd := 目标`） |
| `eApproach` | `tMoveTimeout` 到 | `eFault`（`0305`） |
| `eFine` | `ABS(反馈 − 目标) <= fGapTol` | `eHold`（`bInPosition := TRUE`、写 `fLastDeviation`） |
| `eFine` | `tMoveTimeout` 到 | `eFault`（`0305`） |
| `eHold` | 始终保持（指令维持目标值，等待下次 `bAdjustStart`） | `eHold` |
| `eFault` | `bReset` 上升沿 | `eIdle` |
| **`ELSE`** | 非法值 | `eFault` + `16#0003_0308` |

> **为什么必须有 `eApproach` 与 `eFine` 两段**：单向逼近是背隙补偿的**本体**；把两段压成「一次赋值 + 到位判定」会失去「先越程再回退」的动作序列，重复定位精度退化到双向逼近水平（这是本件相对普通定位块的全部价值）。

**码位表**：`16#0003_0147` 目标间隙越界已钳位（信息级）｜`16#0003_0148` 背隙补偿量越界已钳位（信息级）｜`16#0003_0305` 到位超时（故障级）｜`16#0003_0306` 位移反馈无效/丢失（故障级，指令保持）｜`16#0003_0308` 非法状态兜底（故障级）。

**验收向量**

| 向量 | 输入 | 期望输出 |
|---|---|---|
| V1 两阶段指令 | `fGapSetpoint = 2.500 mm`、`fBacklash = 0.050 mm` | 阶段 A `fGapCmd = 2.450 mm`；到位后阶段 B `fGapCmd = 2.500 mm` |
| V2 到位判定 | `fGapSetpoint = 2.500`、`fGapTol = 0.02`、`fGapActual = 2.515` | `bInPosition = TRUE`、`fLastDeviation = +0.015 mm` |
| V3 限幅 | `fGapSetpoint = 5.0`、`fCmdMax = 3.0` | `fGapCmd = 3.0`、`uErrorId = 16#0003_0147` |
| V4 反馈丢失 | `bFeedbackValid` 由 TRUE→FALSE（指令原为 2.50） | `fGapCmd` 保持 2.50、`uErrorId = 16#0003_0306`、`bError = TRUE` |
| V5 超时 | `tMoveTimeout = T#10S`，10 s 内偏差始终 > `fGapTol` | `uErrorId = 16#0003_0305`、`bAdjusting = FALSE`、`nAdjustCount` 不加 |

---

### 9. `FB_DL_YearWindowCheck` —— 年度生效窗判定（年粒度，含跨年与闰日）

- **子库**：DL_Base ｜ **前缀**：`FB_DL_` ｜ **预计行数**：420 ｜ **来源组标签**：`lgf-datetime`、`calendar`、`state-machine`
- **一句话功能**：判定「当前日期是否落在某个年度生效区间内」并给出开/闭沿单拍；支持跨年窗（如 11 月 1 日至次年 2 月底）、结束日含/不含、闰日自动生效，日期全部**引脚注入**（不读系统时钟）。
- **与既有件边界（四件日历族职责互斥）**：`FB_DL_TimeWindowCheck` = **日内时刻窗**；`FB_DL_OccScheduleWindow` = **多时刻窗排程**；`FB_DL_MonthWindowCheck` = **月度日窗**（月粒度）；**本件 = 年粒度区间窗**（可跨年）。四者不可互相替代；年窗**不**复用月窗实现（跨年语义相反：年窗跨年合法、月窗跨月非法）。
- **依赖**：仅标准库。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_YearWindowCheck
VAR_INPUT
    bEnable        : BOOL;                  // 使能；FALSE 时 bInWindow 强制 FALSE / Enable; forces bInWindow FALSE
    bReset         : BOOL;                  // 上升沿清组态非法标志 / Rising edge clears invalid-configuration flag
    nYear          : INT;                   // 当前年 [年]，有效域 1970~2099 / Current year
    nMonth         : INT;                   // 当前月 [月]，1~12 / Current month
    nDay           : INT;                   // 当前日 [日]，1~31（按当月天数校验）/ Current day
    nStartYear     : INT;                   // 窗口起始年 [年] / Window start year
    nStartMonth    : INT;                   // 窗口起始月 [月] / Window start month
    nStartDay      : INT;                   // 窗口起始日 [日] / Window start day
    nEndYear       : INT;                   // 窗口结束年 [年] / Window end year
    nEndMonth      : INT;                   // 窗口结束月 [月] / Window end month
    nEndDay        : INT;                   // 窗口结束日 [日] / Window end day
    bIncludeEnd    : BOOL := TRUE;          // 结束日是否含当天（含 = 闭区间）/ Include end day
END_VAR
VAR_OUTPUT
    bInWindow      : BOOL;                  // 当前日期在窗内 / Current date inside window
    bEdgeOpen      : BOOL;                  // 进入窗口单拍脉冲 / Single pulse on window entry
    bEdgeClose     : BOOL;                  // 离开窗口单拍脉冲 / Single pulse on window exit
    bInvalidConfig : BOOL;                  // 窗口组态非法（已按空窗处理）/ Window configuration invalid
    nDaysUntilEdge : INT;                   // 距窗口切换（开或关）的天数 [日]，便于提前预警 / Days until next window edge
    eState         : E_DL_YearWinPhase;     // 主状态机当前态 / Current state
    uErrorId       : UDINT;                 // 事件码，0 = 无 / Event code, 0 = none
END_VAR
VAR CONSTANT
    DL_YEAR_MIN    : INT := 1970;           // 可算年下限 [年] / Year lower bound
    DL_YEAR_MAX    : INT := 2099;           // 可算年上限 [年] / Year upper bound
    DL_MONTH_MAX   : INT := 12;             // 月上限 [月] / Month upper bound
    DL_DAY_MAX     : INT := 31;             // 日上限 [日] / Day upper bound
    DL_EPOCH_YEAR  : INT := 2000;           // 序数基准年 [年] / Ordinal epoch year
END_VAR
```

**配套类型（同文件发布）**

| 类型 | 成员 | 说明 |
|---|---|---|
| `E_DL_YearWinPhase` | `eIdle := 0` / `eOutWindow := 10` / `eInWindow := 20` / `eInvalid := 30` | `eInvalid` = 归一后为空窗（组态错），需 `bReset` 退出；开/闭沿只在 `eOutWindow` ↔ `eInWindow` 之间产生 |

**关键算法**

1. **日期合法性**：年越界 / 月越界 / 日超过当月天数（含闰年判定 `(y MOD 4 = 0 AND y MOD 100 <> 0) OR (y MOD 400 = 0)`）→ 置 `011E` 并**钳位照算**（不中断，现场 HMI 误设不应停机）。
2. **日期 → 连续日序数**：`nOrd := (nYear * 365) + 闰年累计(nYear - 1) + 年内序日`（整数运算，域内不溢出：2099 × 365 ≈ 766,135 < 2^31）。用 `LINT` 中间量，规避 `INT` 溢出。
3. **区间归一**：`nStartOrd` 与 `nEndOrd` 分别计算；`nStartOrd > nEndOrd` 视为**跨年窗**（合法，语义为「起始日到次年结束日」）；`bIncludeEnd = FALSE` 时 `nEndOrd := nEndOrd - 1`；若归一后 `nStartOrd > nEndOrd`（即跨年窗退化为空，例如起止同日且不含尾）→ `bInvalidConfig := TRUE` + `011F`，`bInWindow := FALSE`。
4. **窗内判定**：`bInWindow := (nCurOrd >= nStartOrd) AND (nCurOrd <= nEndOrd)`；**年度重复**语义：若组态年差 > 1（如 2026→2031），按「一年一循环」处理——判定时把 `nCurOrd` 折叠到 `[nStartOrd, nStartOrd + 366]` 的单周期内（`nCurOrd - nStartOrd MOD 365 天` 取模），此分支必须在头注释显式声明（避免多年度语义歧义）。
5. **沿输出**：用 `R_TRIG` 在主周期无条件刷新，`bEdgeOpen := bInWindow AND NOT bInWindowPrev`，`bEdgeClose := bInWindowPrev AND NOT bInWindow`；`bInWindowPrev` 为内部保持量。
6. **切换天数**：`nDaysUntilEdge := bInWindow ? (nEndOrd - nCurOrd) : (nStartOrd - nCurOrd)`（跨年时按周期折叠后取正差值）。

**状态机（ENUM + CASE）**

| 当前态 | 迁移条件 | 目标态 |
|---|---|---|
| `eIdle` | `bEnable`（首拍直接按判定结果落态） | `eInWindow` 或 `eOutWindow` |
| `eOutWindow` | `bInWindow` 上升沿 | `eInWindow`（`bEdgeOpen` 单拍） |
| `eInWindow` | `bInWindow` 掉沿 | `eOutWindow`（`bEdgeClose` 单拍） |
| 任一态 | `bInvalidConfig` | `eInvalid`（`011F`，`bInWindow` 强制 FALSE，同时产生 `bEdgeClose` 若之前在内） |
| `eInvalid` | `bReset` 上升沿且组态已修正 | `eIdle` |
| **`ELSE`** | 非法值 | `eInvalid` + `16#0001_011F` |

**码位表**：`16#0001_011E` 日期参数越界已钳位照算（信息级）｜`16#0001_011F` 窗口归一后为空（信息级，`bInvalidConfig`）。

**验收向量**

| 向量 | 输入 | 期望输出 |
|---|---|---|
| V1 窗内 | 窗口 2026-03-01 ~ 2026-06-30，当前 2026-04-15 | `bInWindow = TRUE`、`nDaysUntilEdge = 76`（4/15 → 6/30） |
| V2 窗外 | 同上窗口，当前 2026-07-01 | `bInWindow = FALSE`、`bEdgeClose` 单拍（当日边界拍） |
| V3 跨年窗 | 窗口 2026-11-01 ~ 2027-02-28，当前 2027-01-10 | `bInWindow = TRUE`（跨年语义生效） |
| V4 不含尾 | 窗口 2026-03-01 ~ 2026-06-30，`bIncludeEnd = FALSE`，当前 2026-06-30 | `bInWindow = FALSE`；`bIncludeEnd = TRUE` 时同输入为 `TRUE` |
| V5 闰日 | 窗口 2028-02-01 ~ 2028-03-01，当前 2028-02-29 | `bInWindow = TRUE`（序数法自动含闰日） |
| V6 非法 | 窗口起止同为 2026-05-10 且 `bIncludeEnd = FALSE` | `bInvalidConfig = TRUE`、`uErrorId = 16#0001_011F`、`bInWindow = FALSE` |

---

### 10. `FB_DL_RolloverCounter` —— 回绕型可逆计数器（无预设比较的环形计数）

- **子库**：DL_Base ｜ **前缀**：`FB_DL_` ｜ **预计行数**：380 ｜ **来源组标签**：`lgf-counter`、`edge-detection`、`state-machine`
- **一句话功能**：在 `0 ~ uPreset` 的环形域内做可逆计数，输出回绕事件单拍与**净回绕圈数**（可负），用于转盘圈数、编码器溢出圈数、料盘循环计数。
- **与既有件边界（四件套互斥，写进头注释）**：`FB_DL_EventCounter` = 单向事件累加；`FB_DL_ModuloCounter` = **取模**工位索引（单向）；`FB_DL_PresetCounterSat` = 单向双预设**饱和**（到限冻结）；`FB_DL_BidirectionalCounter` = CTUD **双预设比较**；**本件 = 环形回绕 + 净圈数**，无任何预设比较逻辑。五者不可互替。
- **依赖**：仅标准库。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_RolloverCounter
VAR_INPUT
    bEnable      : BOOL;              // 使能；FALSE 时冻结计数 / Enable; freezes counting on FALSE
    bReset       : BOOL;              // 上升沿计数清零、圈数清零 / Rising edge clears count and turns
    bCountUp     : BOOL;              // 上升沿加计数 / Rising edge increments
    bCountDown   : BOOL;              // 上升沿减计数 / Rising edge decrements
    bLoad        : BOOL;              // 电平有效装载（优先级最高）/ Level-true load, highest priority
    uLoadValue   : UDINT;             // 装载值 [cnt]，超 uPreset 时钳位 / Load value, clamped to preset
    uPreset      : UDINT;             // 回绕上限（含）[cnt]，有效域 1~16#FFFF_FFFE / Wrap upper bound, inclusive
END_VAR
VAR_OUTPUT
    uCount       : UDINT;             // 当前计数值 [cnt]，0 ~ uPreset / Current count
    bWrapped     : BOOL;              // 本拍发生回绕单拍脉冲 / Single-scan wrap pulse
    nTurns       : DINT;              // 净回绕圈数（上加下减）[圈] / Net wrap turns, signed
    bAtPreset    : BOOL;              // 当前值等于回绕上限 / Count equals preset
    eState       : E_DL_RolloverPhase;// 主状态机当前态 / Current state
    bError       : BOOL;              // 故障（预设退化）/ Fault, degenerate preset
    uErrorId     : UDINT;             // 事件/故障码 / Event or fault code
END_VAR
VAR CONSTANT
    DL_PRESET_MIN : UDINT := 1;              // 预设下限 [cnt] / Preset lower bound
    DL_TURNS_MAX  : DINT  := 2_000_000_000;  // 圈数饱和上限 [圈] / Turn counter saturation
END_VAR
```

**配套类型（同文件发布）**

| 类型 | 成员 | 说明 |
|---|---|---|
| `E_DL_RolloverPhase` | `eIdle := 0` / `eCount := 10` / `eFrozen := 20` | `eFrozen` = 预设退化冻结态（`bError` 置位），预设恢复后回 `eIdle` 重新装载 |

**关键算法**

1. **预设退化**：`uPreset < DL_PRESET_MIN` → `uCount` 冻结（保持上次）、`bError := TRUE`、`0218`；退化期间不接受计数（**不回绕到 0 造成死循环**）。
2. **装载优先**：`bLoad = TRUE` 时 `uCount := MIN(uLoadValue, uPreset)`（超限钳位 + `0120`），本拍不加不减。
3. **同拍双向**：`bCountUp` 与 `bCountDown` 同时出现上升沿 → **计数不变**、`bWrapped := FALSE`、置信息码（按公约复用 `0120` 族，语义为「方向冲突已丢弃」）。
4. **回绕**：`uCount = uPreset` 且 UP → `uCount := 0`、`bWrapped := TRUE`、`nTurns + 1`；`uCount = 0` 且 DOWN → `uCount := uPreset`、`bWrapped := TRUE`、`nTurns - 1`。
5. **条件加减法**：回绕用「比较 + 赋值」而非取模（跨平台取模对无符号/有符号行为差异是历史坑，禁 `MOD` 实现回绕）。
6. **饱和**：`nTurns` 触 `±DL_TURNS_MAX` 后停在此值并置信息码（不再累加，防远端诊断溢出）。

**状态机（ENUM + CASE）**

| 当前态 | 迁移条件 | 目标态 |
|---|---|---|
| `eIdle` | `bEnable` 且 `uPreset >= DL_PRESET_MIN` | `eCount` |
| `eIdle` | `bEnable` 但 `uPreset < DL_PRESET_MIN` | `eFrozen`（`0218`） |
| `eCount` | `uPreset < DL_PRESET_MIN` | `eFrozen`（`0218`，计数保持） |
| `eCount` | `bReset` 上升沿 | `eCount`（清零后继续，不必回 `eIdle`） |
| `eFrozen` | `uPreset >= DL_PRESET_MIN`（组态修正）或 `bReset` | `eIdle` |
| `eCount` / `eFrozen` | `NOT bEnable` | `eIdle` |
| **`ELSE`** | 非法值 | `eFrozen` + `16#0001_0218` |

**码位表**：`16#0001_0120` 装载值超上限已钳位 / 同拍双向已丢弃（信息级）｜`16#0001_0218` 预设为零退化，计数冻结（故障级）。

**验收向量**

| 向量 | 输入 | 期望输出 |
|---|---|---|
| V1 上回绕 | `uPreset = 100`、`uCount = 100`、`bCountUp` 上升沿 | `uCount = 0`、`bWrapped = TRUE`、`nTurns` +1 |
| V2 下回绕 | `uCount = 0`、`bCountDown` 上升沿 | `uCount = 100`、`bWrapped = TRUE`、`nTurns` −1 |
| V3 装载优先 | `bLoad = TRUE`、`uLoadValue = 42`、同时 `bCountUp` 有沿 | `uCount = 42`、`nTurns` 不变、`bWrapped = FALSE` |
| V4 双向冲突 | `bCountUp` 与 `bCountDown` 同拍上升沿 | `uCount` 不变、`bWrapped = FALSE`、`uErrorId = 16#0001_0120` |
| V5 预设退化 | `uPreset = 0`、`bCountUp` 连续给沿 | `uCount` 保持 0、`bError = TRUE`、`uErrorId = 16#0001_0218` |

---

### 11. `FC_DL_RangeOverlapCheck` —— 区间关系判定（重叠 / 包含 / 相接 / 相离）

- **子库**：DL_Base ｜ **前缀**：`FC_DL_` ｜ **预计行数**：280 ｜ **来源组标签**：`lgf-comparator`、`pure-function`
- **一句话功能**：判定两个实数区间 A、B 的**几何关系**（相离 / 仅在端点相接 / 部分重叠 / 一方包含另一方 / 完全相等），并输出重叠长度；用于配方参数域校验、时间窗互斥检查、公差带叠加分析。
- **与既有件边界**：`FC_DL_LimitClassify` 判**单点**落在哪一档；`FC_DL_Hysteresis` 判**单点**迟滞；`FB_DL_ToleranceWindow` 判**单点**是否在公差带；**本件判「两个区间之间」的关系**，输入是 4 个端点而非 1 个测量值 —— 是本族唯一的二元件。
- **依赖**：仅标准库。

**引脚规格**

```iecst
FUNCTION FC_DL_RangeOverlapCheck : E_DL_RangeRelation
VAR_INPUT
    fA1 : REAL;            // 区间 A 端点 1 [任意工程单位]，无序自动对调 / Range A endpoint 1, auto-swapped
    fA2 : REAL;            // 区间 A 端点 2 / Range A endpoint 2
    fB1 : REAL;            // 区间 B 端点 1，无序自动对调 / Range B endpoint 1
    fB2 : REAL;            // 区间 B 端点 2 / Range B endpoint 2
    bIncA : BOOL := TRUE;  // A 是否闭区间（含端点）/ A closed interval
    bIncB : BOOL := TRUE;  // B 是否闭区间 / B closed interval
END_VAR
VAR_OUTPUT
    fOverlapSpan : REAL;   // 重叠长度 [同输入单位]，无重叠 = 0.0 / Overlap length
    bTouching    : BOOL;   // 仅端点相接（重叠长度 0 但边界重合）/ Endpoint touch only
    bValid       : BOOL;   // 输入全部有限 = TRUE / Inputs all finite
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : REAL := 1.0E-6;   // 端点比较容差 / Endpoint comparison epsilon
END_VAR
```

**枚举（同文件发布）**

| 成员 | 值 | 语义 |
|---|---|---|
| `eInvalid` | 0 | 输入非有限值，关系不可判 |
| `eDisjoint` | 10 | 完全相离（含间隙） |
| `eTouching` | 20 | 仅端点相接（重叠长度 0） |
| `ePartial` | 30 | 部分重叠（互相不包含） |
| `eContains` | 40 | 一方包含另一方（含相等端点） |
| `eEqual` | 50 | 两端点均相等（容差内） |

**算法**

1. **有限性**：任一输入非有限（`x <> x` 判 NaN、`ABS(x) > 1.0E37` 判 Inf）→ `eInvalid`、`fOverlapSpan := 0.0`、`bValid := FALSE`、码 `0121`。
2. **归一**：`IF fA1 > fA2 THEN 交换 END_IF`（同理 B），保证 `A1 <= A2`。
3. **相等**：`ABS(A1-B1) < EPS AND ABS(A2-B2) < EPS` → `eEqual`，`fOverlapSpan := A2 - A1`。
4. **相离**：`A2 < B1 - EPS` 或 `B2 < A1 - EPS` → `eDisjoint`，`bTouching := FALSE`。
5. **相接**：`ABS(A2 - B1) < EPS` 或 `ABS(B2 - A1) < EPS` → `eTouching`、`bTouching := TRUE`、`fOverlapSpan := 0.0`（**开区间同样判相接**：端点相接与开闭无关，开闭只影响「相接处是否算公共点」，由 `bIncA AND bIncB` 表达在 `bTouching` 的补充输出中）。
6. **包含**：`(A1 <= B1 + EPS AND A2 >= B2 - EPS)` 或反向 → `eContains`，`fOverlapSpan := MIN(A2,B2) - MAX(A1,B1)`。
7. **其余** → `ePartial`，`fOverlapSpan := MIN(A2,B2) - MAX(A1,B1)`（恒 `> 0`）。

**码位表**：`16#0001_0121` 输入非有限值（信息级，返回 `eInvalid`）。

**验收向量**

| 向量 | 输入 | 期望输出 |
|---|---|---|
| V1 部分重叠 | A=[0,10]、B=[5,15] | `ePartial`、`fOverlapSpan = 5.0` |
| V2 端点相接 | A=[0,10]、B=[10,20] | `eTouching`、`fOverlapSpan = 0.0`、`bTouching = TRUE` |
| V3 包含 | A=[0,10]、B=[2,8] | `eContains`、`fOverlapSpan = 6.0` |
| V4 相离 | A=[0,10]、B=[20,30] | `eDisjoint`、`fOverlapSpan = 0.0` |
| V5 相等 | A=[0,10]、B=[0,10] | `eEqual`、`fOverlapSpan = 10.0` |
| V6 无序端点 | A=[10,0]、B=[5,15] | 归一后同 V1 → `ePartial`、`fOverlapSpan = 5.0` |

---

### 12. `FC_DL_CalcDistance3D` —— 三维空间两点距离（2D 为其退化情形）

- **子库**：DL_MathData ｜ **前缀**：`FC_DL_` ｜ **预计行数**：240 ｜ **来源组标签**：`lgf-math`、`pure-function`、`vision-geometry`
- **一句话功能**：计算两点三维欧氏距离，含非有限值防护与大数溢出缩放；平面距离通过 `fZ1 = fZ2 = 0` 退化获得。
- **与既有件边界**：`FC_DL_PolygonArea` 算面积/质心、`FC_DL_LineIntersection` 算交点；本件只算**点间距离**。**明确不拆 2D / 3D 两个组件**：2D 是 3D 在 `fZ1 = fZ2` 时的退化，拆两块属「为凑数拆分变体」，矩阵第 3 节禁令明确禁止。
- **依赖**：仅标准库（`SQRT`）。

**引脚规格**

```iecst
FUNCTION FC_DL_CalcDistance3D : REAL
VAR_INPUT
    fX1 : REAL;    // 点 1 X 坐标 [mm]，量程 ±1.0E6 / Point 1 X [mm]
    fY1 : REAL;    // 点 1 Y 坐标 [mm] / Point 1 Y [mm]
    fZ1 : REAL;    // 点 1 Z 坐标 [mm]，平面场景填 0.0 / Point 1 Z [mm], 0.0 for 2D
    fX2 : REAL;    // 点 2 X 坐标 [mm] / Point 2 X [mm]
    fY2 : REAL;    // 点 2 Y 坐标 [mm] / Point 2 Y [mm]
    fZ2 : REAL;    // 点 2 Z 坐标 [mm] / Point 2 Z [mm]
END_VAR
VAR_OUTPUT
    bValid     : BOOL;   // 输入全有限 = TRUE / Inputs all finite
    bSaturated : BOOL;   // 触发溢出缩放保护 / Overflow scaling applied
    fDeltaX    : REAL;   // X 分量差 [mm]，便于诊断 / X delta [mm]
    fDeltaY    : REAL;   // Y 分量差 [mm] / Y delta [mm]
    fDeltaZ    : REAL;   // Z 分量差 [mm] / Z delta [mm]
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : REAL := 1.0E-6;   // 浮点判等容差 / Float epsilon
    DL_SCALE_THR : REAL := 1.0E18;   // 触发缩放的模长阈值 [mm] / Scaling threshold
END_VAR
```

**算法**

1. **有限性**：六个输入任一非有限 → `bValid := FALSE`、返回 `0.0`、码 `0122`（**不返回 NaN**：NaN 会沿调用链污染下游滤波/比较）。
2. **分量差**：`fDeltaX := fX2 - fX1`（同 Y / Z）。
3. **直接求模**：`fScale := MAX(ABS(fDeltaX), MAX(ABS(fDeltaY), ABS(fDeltaZ)))`；若 `fScale < DL_SCALE_THR` → `SQRT(dx² + dy² + dz²)`。
4. **缩放求模**：否则 `SQRT((dx/fScale)² + (dy/fScale)² + (dz/fScale)²) * fScale`，`bSaturated := TRUE`、码 `0219`（信息级：结果有效但已进入缩放置信区）。
5. **退化**：三点差全零 → 返回 `0.0`，不置任何码（距离 0 是合法值）。

**码位表**：`16#0001_0122` 输入非有限值（信息级，返回 0.0）｜`16#0001_0219` 模长超阈已缩放（信息级，结果可用）。

**验收向量**

| 向量 | 输入 | 期望输出 |
|---|---|---|
| V1 2D 退化 | (0,0,0) → (3,4,0) | `5.0`（勾股 3-4-5） |
| V2 3D | (0,0,0) → (2,3,6) | `7.0`（4+9+36=49 → √49） |
| V3 同点 | (1,1,1) → (1,1,1) | `0.0`、`bValid = TRUE` |
| V4 非有限 | `fX1 = NaN` | `0.0`、`bValid = FALSE`、`uErrorId = 16#0001_0122` |
| V5 负坐标 | (-3,-4,0) → (0,0,0) | `5.0`（差值绝对值参与平方） |

---

### 13. `FC_DL_RandomNext` —— 确定性伪随机序列（种子进 / 新种子出）

- **子库**：DL_MathData ｜ **前缀**：`FC_DL_` ｜ **预计行数**：220 ｜ **来源组标签**：`lgf-math`、`pure-function`、`test-stimulus`
- **一句话功能**：给定种子返回 `[0,1)` 均匀分布随机数与**新种子**，无内部状态；调用方只需保存种子即可获得可复现序列，适合通讯压力测试、仿真激励与算法自检。
- **与既有件边界**：`FB_DL_SineGenerator` / `FB_DL_SawtoothGenerator` 是**确定性波形**发生器；本件是**伪随机**序列且**无状态**（不用 `FB`，不占实例内存），二者用途正交。
- **依赖**：仅标准库。

**引脚规格**

```iecst
FUNCTION FC_DL_RandomNext : REAL
VAR_INPUT
    uSeed    : UDINT;    // 当前种子 [cnt]，首次调用由调用方给定任意值 / Current seed, any value on first call
    bReseed  : BOOL;     // TRUE 时用 DL_SEED_DEFAULT 覆盖种子（可复现基线）/ TRUE forces the default seed
END_VAR
VAR_OUTPUT
    uNextSeed : UDINT;   // 下一拍应传回的种子 / Seed to pass back next call
    bZeroSeed : BOOL;    // 输入种子为 0 已替换（0 是 LCG 的不动点）/ Zero seed replaced
    bSat      : BOOL;    // 结果被钳到 1.0 - EPS（保证半开区间）/ Result clamped to stay in [0,1)
END_VAR
VAR CONSTANT
    DL_LCG_MUL      : UDINT := 1664525;        // 乘子（Numerical Recipes 经典参数）/ Multiplier
    DL_LCG_INC      : UDINT := 1013904223;     // 增量 / Increment
    DL_SEED_DEFAULT : UDINT := 16#0000_0001;   // 默认种子 / Default seed
    DL_RAND_SCALE   : REAL  := 2.3283064E-10;  // 2^-32 缩放因子 / 2^-32 scale
    DL_FLOAT_EPS    : REAL  := 1.0E-6;         // 结果上限保护 / Result upper guard
END_VAR
```

**算法**

1. **零种子保护**：`uSeed = 0` 时改用 `DL_SEED_DEFAULT`（0 在乘法型 LCG 中是吸收态，会退化为常数序列），置 `bZeroSeed := TRUE`。
2. **重播种**：`bReseed = TRUE` 时 `uNextSeed := DL_SEED_DEFAULT`，返回值为该种子的首个随机数（**同一组态永远得到同一序列**，这是可复现性承诺）。
3. **递推**：`uNextSeed := uSeed * DL_LCG_MUL + DL_LCG_INC`（`UDINT` 自然按 2^32 回绕，**不显式取模**，跨平台一致）。
4. **归一**：`fOut := UDINT_TO_REAL(uNextSeed) * DL_RAND_SCALE`；若 `fOut >= 1.0`（浮点舍入所致）→ `fOut := 1.0 - DL_FLOAT_EPS`、`bSat := TRUE`。**半开区间 `[0,1)` 由后置守卫硬保证**。
5. **确定性关系**（可用作独立复算依据）：`FLOOR(fOut / DL_RAND_SCALE) = uNextSeed`。

**码位表**：`16#0001_0123` 乘子/增量参数被外部改写，已回退默认常数（信息级，保护性）。

**验收向量**

| 向量 | 输入 | 期望输出 |
|---|---|---|
| V1 零种子 | `uSeed = 0` | `uNextSeed = 16#3C6E_F35F`（= 1013904223）、`fOut ≈ 0.2360680`、`bZeroSeed = TRUE` |
| V2 满量程种子 | `uSeed = 16#FFFF_FFFF` | `uNextSeed = (0xFFFFFFFF×1664525 + 1013904223) mod 2³² = 1013904223 − 1664525 = 1012239698 = 16#3C55_8D52`、`fOut ≈ 0.2356716` |
| V3 确定性 | 同一种子连调两次，第二次传回 `uNextSeed` | 两次的 `uNextSeed` 按 V1/V2 公式逐次复算一致（序列可复现） |
| V4 半开区间 | 任取 1000 个种子 | 全部 `0.0 <= fOut < 1.0`；`bSat` 仅在舍入到 1.0 时置位 |

---

### 14. `FC_DL_PercentileLReal` —— 分位数计算（线性插值法，P50 / P95 等）

- **子库**：DL_MathData ｜ **前缀**：`FC_DL_` ｜ **预计行数**：320 ｜ **来源组标签**：`lgf-math`、`statistics`、`pure-function`
- **一句话功能**：对样本数组求任意分位值（P0~P100），采用「排序 + 线性插值」口径（与主流统计库默认一致），用于节拍抖动 P95、称重偏差 P99、温度分布 P50 等现场统计判据。
- **与既有件边界**：`FB_DL_SignalStatistics` 给**均值/方差/极值**（不含分位）；`FC_DL_QuickSortLReal` 只排序不取值；**本件 = 排序 + 分位插值**（内部完成拷贝排序，**不修改调用方数组**，与排序函数的就地语义相反，必须写进头注释）。
- **依赖**：仅标准库。

**引脚规格**

```iecst
FUNCTION FC_DL_PercentileLReal : LREAL
VAR_INPUT
    nCount : INT;      // 样本数 [个]，有效域 0~64 / Sample count, 0..64
    fP     : REAL;     // 分位点 [0.0~1.0]，如 0.95 表示 P95 / Percentile, 0.0..1.0
END_VAR
VAR_IN_OUT
    afData : ARRAY[1..64] OF LREAL;   // 样本数组（块内拷贝排序，原数组不变）/ Sample array, copied internally
END_VAR
VAR_OUTPUT
    fActualP : REAL;                  // 实际生效分位点（越界已钳位）/ Effective percentile after clamping
    nGuard   : DINT;                  // 排序循环防死锁计数 / Sort loop guard counter
    bEmpty   : BOOL;                  // 样本为空（返回 0.0）/ Empty sample set
END_VAR
VAR CONSTANT
    DL_SAMPLE_MAX : INT := 64;        // 样本上限 [个] / Max samples
    DL_GUARD_MAX  : DINT := 100000;   // 循环防死锁上限 / Loop guard limit
    DL_FLOAT_EPS  : REAL := 1.0E-6;   // 浮点判等容差 / Float epsilon
END_VAR
```

**算法（线性插值 / R-7 口径）**

1. **空集**：`nCount <= 0` → 返回 `0.0`、`bEmpty := TRUE`、码 `16#0002_000E`。
2. **分位钳位**：`fP < 0` → `0.0`；`fP > 1` → `1.0`；越界置 `0124`（信息级），`fActualP` 输出实际值。
3. **拷贝排序**：把 `afData[1..MIN(nCount,64)]` 拷进局部数组，用**插入排序**（样本 ≤ 64，插入排序常数更小且无递归），带 `nGuard` 防死锁；`nCount > 64` 取前 64 个并置 `0124`。
4. **位置计算**：`fPos := fActualP * (n - 1)`；`nLo := TRUNC(fPos)`；`fFrac := fPos - nLo`。
5. **插值**：`nLo + 1 >= n` 时返回 `afSorted[n]`；否则 `afSorted[nLo+1] + fFrac * (afSorted[nLo+2] - afSorted[nLo+1])`（注意库内数组 1 起，索引需 +1）。
6. **有限性**：若插值结果非有限 → 返回 `0.0` 并置 `0124`（信息级，不中断调用方扫描）。

**码位表**：`16#0001_0124` 分位点/样本数越界已钳位（信息级）｜`16#0002_000E` 样本为空或全部非有限（信息级，返回 0.0）。

**验收向量**

| 向量 | 输入 | 期望输出 |
|---|---|---|
| V1 中位 | 数据 [1,2,3,4]、`fP = 0.5` | `pos = 1.5` → `2 + 0.5×(3−2) = 2.5` |
| V2 P90 | 同上、`fP = 0.9` | `pos = 2.7` → `3 + 0.7×(4−3) = 3.7` |
| V3 单样本 | 数据 [7.5]、`fP = 0.9` | `7.5`（`pos = 0`，不外插） |
| V4 越界钳位 | `fP = 1.5`、数据 [1,2,3,4] | `fActualP = 1.0`、返回 `4.0`、`uErrorId` 含 `16#0001_0124` |
| V5 空集 | `nCount = 0` | 返回 `0.0`、`bEmpty = TRUE`、码 `16#0002_000E` |
| V6 输入不变 | 数据 [4,1,3,2]、`fP = 0.5` | 返回 `2.5`，且 `afData` 帧后仍为 [4,1,3,2]（拷贝排序验证） |

---

### 15. `FB_DL_R2rEwmaTuner` —— Run-to-Run 工艺参数 EWMA 自动微调

- **子库**：DL_Algo ｜ **前缀**：`FB_DL_` ｜ **预计行数**：480 ｜ **来源组标签**：`semiconductor-apc`、`lgf-math`、`isa-88`
- **一句话功能**：按「批 — 测量 — 修正」事务把一个批次一个批次的实测偏差用 EWMA 平滑后反馈到工艺参数上，做到**逐批小步收敛**而非一次性大改；修正量受单次限幅与参数域双重约束，全程可审计（批号计数 + EWMA 值）。
- **与既有件边界**：`FB_DL_PidController` 是**连续闭环**（拍级）；`FB_DL_RateLimiter` 限的是**信号变化率**；本件是**批级离散更新**（一个批次只动一次），时间尺度差 3~4 个数量级，不可互替。
- **依赖**：仅标准库（EWMA 与限幅内联，不依赖 `DL_MathData` 的滤波件，避免拍级滤波语义混淆）。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_R2rEwmaTuner
VAR_INPUT
    bEnable        : BOOL;             // 使能；FALSE 时输出保持上次参数 / Enable; holds last parameter on FALSE
    bReset         : BOOL;             // 上升沿清 EWMA 与故障（参数保持）/ Rising edge clears EWMA and fault
    bNewLot        : BOOL;             // 上升沿开始一个新批次 / Rising edge starts a new lot
    fMeasure       : REAL;             // 本批实测值 [工艺单位]（如膜厚 nm）/ Measured value of this lot
    fTarget        : REAL;             // 目标值 [同测量单位] / Target value
    fLambda        : REAL := 0.30;     // EWMA 权重 λ [0~1]，1 = 只看本批 / EWMA weight
    fGainInv       : REAL := 1.0;      // 工艺增益倒数 [参数单位 / 测量单位] / Inverse process gain
    fCorrectionLim : REAL := 1.0;      // 单次修正限幅 [参数单位] / Per-lot correction limit
    fParamMin      : REAL := 0.0;      // 参数下限 [参数单位] / Parameter lower bound
    fParamMax      : REAL := 100.0;    // 参数上限 [参数单位] / Parameter upper bound
    fParamInit     : REAL := 50.0;     // 初始参数（首扫装载）/ Initial parameter on first scan
END_VAR
VAR_OUTPUT
    fParamOut      : REAL;             // 下发工艺参数 [参数单位] / Output process parameter
    fEwmaDev       : REAL;             // 平滑后偏差 [测量单位] / Smoothed deviation
    bCorrected     : BOOL;             // 本批已执行修正单拍 / Single pulse when a correction was applied
    bAtLimit       : BOOL;             // 修正量或参数触限 / Correction or parameter at limit
    uLotCount      : UDINT;            // 已处理批次数 [批] / Processed lot count
    eState         : E_DL_R2rState;    // 主状态机当前态 / Current state
    bError         : BOOL;             // 故障锁存 / Latched fault
    uErrorId       : UDINT;            // 事件/故障码 / Event or fault code
END_VAR
VAR_IN_OUT
    stHist         : ST_DL_R2rHistory; // 跨周期历史（上批参数 / 最近偏差环形缓冲）/ Persistent history
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS   : REAL := 1.0E-6;   // 浮点判等容差 / Float epsilon
    DL_HIST_DEPTH  : INT  := 10;       // 历史环形缓冲深度 [批] / History depth
    DL_LOT_MAX     : UDINT := 16#FFFF_FFFE; // 批次计数饱和上限 / Lot counter saturation
END_VAR
```

**配套类型**

| 类型 | 成员 | 说明 |
|---|---|---|
| `E_DL_R2rState` | `eIdle := 0` / `eReady := 10` / `eCompute := 20` / `eApply := 30` / `eFault := 99` | 批事务四态 + 故障 |
| `ST_DL_R2rHistory` | `fLastParam : REAL`；`fLastEwma : REAL`；`abHasEwma : BOOL`；`afDevBuf : ARRAY[1..10] OF REAL`；`nBufIdx : INT` | `abHasEwma` 承担「首样本直取」职责（等价 R19 首扫标志） |

**算法**

1. **λ 钳位**：`fLambda < 0` → `0.0`；`> 1` → `1.0`；越界置 `1F01`（信息级）。`λ = 1` 时退化为「只用本批」（不做平滑，属合法组态）。
2. **EWMA**：`abHasEwma = FALSE` 时 `fEwmaDev := fDev`（**首样本直取**，不得用 0 参与平均，否则前若干批严重偏置，R19 家族教训）；否则 `fEwmaDev := fLambda * fDev + (1 - fLambda) * stHist.fLastEwma`。`fDev := fMeasure - fTarget`。
3. **修正量**：`fCorr := -fEwmaDev * fGainInv`；若 `ABS(fCorr) > fCorrectionLim` → 钳到 `±fCorrectionLim`、`bAtLimit := TRUE`、`1F03`（信息级）。
4. **参数更新**：`fParamNew := CLAMP(stHist.fLastParam + fCorr, fParamMin, fParamMax)`；触界同样置 `bAtLimit`（参数到边 vs 修正被限，靠 `uErrorId` 区分）。
5. **单批单次**：`bNewLot` 上升沿开启事务，`eCompute` 内计算，`eApply` 内写出参数并置 `bCorrected` 单拍（下一拍清），**同一批次不重复修正**（R24/R25 单拍纪律）。
6. **非有限值**：`fMeasure` / `fTarget` / `fGainInv` 任一非有限 → 拒绝本批（不改参数）、`1F10`（故障级锁存，需 `bReset`）；这一条与「信息级限幅」严格分离。
7. **审计**：`stHist.afDevBuf` 环写入（`nBufIdx` 环绕），`uLotCount` 饱和累加。

**状态机**

| 当前态 | 迁移条件 | 目标态 |
|---|---|---|
| `eIdle` | `bEnable` | `eReady` |
| `eReady` | `bNewLot` 上升沿 | `eCompute` |
| `eCompute` | 无条件（算 EWMA + 修正量，当拍完成） | `eApply` |
| `eApply` | 无条件（写 `fParamOut`、`bCorrected` 单拍） | `eReady` |
| `eReady` / `eCompute` | 非有限值 | `eFault`（`1F10`） |
| `eFault` | `bReset` 上升沿 | `eIdle` |
| **`ELSE`** | 非法值 | `eFault` + `16#0002_1F10` |

**码位表**：`16#0002_1F01` λ 越界已钳位（信息级）｜`16#0002_1F02` 无历史样本，首样本直取（信息级）｜`16#0002_1F03` 修正量达限幅（信息级）｜`16#0002_1F10` 测量/增益非有限值（故障级锁存）。

**验收向量**

| 向量 | 输入 | 期望输出 |
|---|---|---|
| V1 EWMA | 历史 `fLastEwma = 1.0`、本批 `fDev = +2.0`、`λ = 0.3` | `fEwmaDev = 0.3×2 + 0.7×1 = 1.3` |
| V2 修正限幅 | `fGainInv = 1.0`、`fEwmaDev = 1.3`、`fCorrectionLim = 1.0` | `fCorr` 钳到 `-1.0`、`fParamOut` 减 1.0、`bAtLimit = TRUE`、`uErrorId = 16#0002_1F03` |
| V3 首样本 | `abHasEwma = FALSE`、`fDev = 0.5` | `fEwmaDev = 0.5`（不与 0 平均）、`uErrorId = 16#0002_1F02` |
| V4 λ 钳位 | `fLambda = 1.5` | `fLambda` 实际 1.0 → `fEwmaDev = fDev`、码 `16#0002_1F01` |
| V5 参数到界 | `fParamOut` 已为 `fParamMax`、`fCorr > 0` | `fParamOut` 保持 `fParamMax`、`bAtLimit = TRUE` |
| V6 非有限 | `fMeasure = NaN` | 参数不变、`eState = eFault`、码 `16#0002_1F10` |

---

### 16. `FB_DL_WindingTensionCtrl` —— 卷绕锥度张力闭环（锥度给定 + 摆辊修正）

- **子库**：DL_Motion ｜ **前缀**：`FB_DL_` ｜ **预计行数**：560 ｜ **来源组标签**：`lgf-technology`、`s7-motion`、`plcopen-motion`
- **一句话功能**：把「目标张力 × 锥度系数（随卷径衰减）+ 摆辊位置修正」两层合成张力给定，输出送比例阀或伺服转矩限幅；卷径由线速度与角速度反算，锥度系数随机组直径从 1.0 平滑衰减到 `1-K`。
- **与既有件边界**：`FB_DL_WindingTraverse`（R10）做**排线横动 + 卷径递推**，不含张力闭环；`FC_DL_CoilDiameterCalc` 做**单点几何反算**；本件是**张力控制层**，调用二者之一作为前置（见依赖）。`FB_DL_ElectronicGear` 只管传动比，不涉及张力物理量。
- **依赖**：允许调用**已入库** `FB_DL_PidController`（DL_Algo）与 `FC_DL_CoilDiameterCalc`（DL_Algo）——层次合法（Motion 可依赖 Algo）。两个调用均按对方**真实契约**落地：卷径件为 9 入 6 出的 `LREAL` 函数（入口米制、出口米制，本件负责 mm↔m 换算与显式类型转换），PID 件输出域经 `rOutMin/rOutMax` 取 −1~+1 归一化。若现场不需要几何反算，可直接经 `fDiaInjected` 引脚注入卷径并置 `bUseInjectedDia := TRUE`（**不引入 MODE 参数**，用一个布尔选择「算 / 用注入值」两种数据源，语义单一）。

**引脚规格**

```iecst
FUNCTION_BLOCK FB_DL_WindingTensionCtrl
VAR_INPUT
    bEnable          : BOOL;              // 使能；FALSE 时输出 0 并复位 PID / Enable; zeroes output and resets PID
    bReset           : BOOL;              // 上升沿复位故障与 PID / Rising edge clears fault and PID
    bRun             : BOOL;              // 卷绕运行中；FALSE 时张力给定保持 0 / Winding running flag
    fTensionSet      : REAL;              // 目标张力（满卷前基准）[N]，量程 0.0~500.0 / Base tension setpoint [N]
    fDancerPos       : REAL;              // 摆辊实际位置 [mm]，0 = 机械中位 / Dancer actual position [mm]
    fDancerRef       : REAL := 0.0;       // 摆辊中位基准 [mm] / Dancer reference [mm]
    fAxisSpeedRpm    : REAL;              // 卷轴转速 [rpm]，用于卷径反算 / Winder shaft speed [rpm]
    fLineSpeed       : REAL;              // 线速度 [m/min] / Line speed [m/min]
    fCoreDia         : REAL := 200.0;     // 卷芯直径 [mm] / Core diameter [mm]
    fDiaMax          : REAL := 1000.0;    // 满卷直径 [mm] / Full-roll diameter [mm]
    fDiaInjected     : REAL;              // 外部注入卷径 [mm]（视觉/上位机）/ Injected diameter [mm]
    bUseInjectedDia  : BOOL;              // TRUE = 用注入卷径；FALSE = 由速度比反算 / Use injected diameter
    fThickness       : REAL := 0.10;      // 材料厚度 [mm]，供卷径件层数积分 / Material thickness [mm]
    fTaperK          : REAL := 0.50;      // 锥度系数 [0~1]，满卷张力降至 (1-K) 倍 / Taper coefficient
    fPidKp           : REAL := 0.5;       // 摆辊修正归一化增益 [1/mm]，输出域 −1~+1 / Normalised dancer gain
    fTrimSpan        : REAL := 1.0;       // 修正满量程 [N]，归一化输出 × 该值 = 张力修正 [N] / Trim span [N]
    fTensionMin      : REAL := 0.0;       // 张力输出下限 [N] / Tension lower limit
    fTensionMax      : REAL := 500.0;     // 张力输出上限 [N] / Tension upper limit
END_VAR
VAR_OUTPUT
    fTensionOut      : REAL;              // 张力给定输出 [N]，送比例阀或转矩限幅 / Tension command [N]
    fDiaAct          : REAL;              // 当前生效卷径 [mm] / Effective diameter [mm]
    fTaperFactor     : REAL;              // 实际锥度系数 [无量纲 1-K~1] / Effective taper factor
    fDancerErr       : REAL;              // 摆辊位置误差 [mm] / Dancer position error [mm]
    eState           : E_DL_TensionPhase; // 主状态机当前态 / Current state
    bInControl       : BOOL;              // 张力闭环生效 / Tension loop active
    bError           : BOOL;              // 故障锁存 / Latched fault
    uErrorId         : UDINT;             // 事件/故障码 / Event or fault code
    fDiaLastValid    : REAL;              // 最近一次有效卷径 [mm]（诊断用）/ Last valid diameter [mm]
END_VAR
VAR_IN_OUT
    fbTensionPid     : FB_DL_PidController;  // 摆辊修正环 PID 实例，由调用方持有 / Dancer PID instance held by caller
    stStat           : ST_DL_WindingStat;    // 跨周期统计（张力均值 / 无效卷径次数）/ Persistent statistics
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS     : REAL := 1.0E-6;    // 浮点判等容差 / Float epsilon
    DL_RPM_MIN       : REAL := 1.0;       // 卷径反算最小转速 [rpm]，低于此值不反算 / Min rpm for diameter calc
    DL_DIA_MIN       : REAL := 10.0;      // 卷径物理下限 [mm] / Physical min diameter [mm]
    DL_DIA_MAX       : REAL := 3000.0;    // 卷径物理上限 [mm] / Physical max diameter [mm]
    DL_TASK_CYCLE    : REAL := 0.010;     // 主任务周期 [s]，供卷径件变化率换算 / Task cycle for the diameter function [s]
    DL_FILTER_TAU    : REAL := 0.50;      // 卷径一阶低通时间常数 [s] / Diameter low-pass time constant [s]
    DL_INVALID_MAX   : UDINT := 50;       // 卷径连续无效次数上限 [次] / Consecutive invalid-diameter limit
END_VAR
```

**配套类型**

| 类型 | 成员 | 说明 |
|---|---|---|
| `ST_DL_WindingStat` | `fTensionAvg : REAL` [N]；`nInvalidDiaCnt : UDINT`；`tRunTime : TIME` | 由调用方持有 |
| `E_DL_TensionPhase` | `eIdle := 0` / `eOpenLoop := 10` / `eClosedLoop := 20` / `eFault := 99` | `eOpenLoop` = 摆辊反馈不可用，只出锥度基准张力（**降级态**，不是故障态） |

**关键算法**

1. **卷径获取**：`bUseInjectedDia = TRUE` → `fDiaAct := CLAMP(fDiaInjected, DL_DIA_MIN, DL_DIA_MAX)`；否则 `fAxisSpeedRpm < DL_RPM_MIN` 或 `fLineSpeed` / `fAxisSpeedRpm` 非有限 → **沿用 `fDiaLastValid`** + `01C0`（信息级）+ `nInvalidDiaCnt` 累加；正常时按下述**真实契约**调用已入库卷径函数（单位换算写死，禁止把 mm 直接喂进米制入口）：

   ```iecst
   // 已入库 FC 的入口单位：线速度 米每分 / 转速 转每分 / 卷径 米 / 厚度 米 / 周期 秒
   fDiaM := FC_DL_CoilDiameterCalc(
       fLineSpeed := fLineSpeed,                       // 米每分，与本部引脚同单位
       fShaftRpm  := fAxisSpeedRpm,                    // 转每分，与本部引脚同单位
       fGearRatio := 1.0,                              // 直连，传动比由机械决定，作为组态常量
       fCoreDia   := fCoreDia / 1000.0,                // mm → m
       fThickness := fThickness / 1000.0,              // mm → m
       fPrevDia   := fDiaLastValid / 1000.0,           // mm → m，0 表示无历史
       fTaskCycle := DL_TASK_CYCLE,                    // s
       bFilterEn  := TRUE,
       fFilterTau := DL_FILTER_TAU,
       fDia       => fDiaM );                          // LREAL 出口
   fDiaAct := REAL#(fDiaM * 1000.0);                   // m → mm，显式转换
   ```

   > 平台差异提示：函数出口绑定语法（`fDia =>`）在 CODESYS V3.5 / TwinCAT 3 均支持；若目标平台版本不支持，只允许在 DL_Motion 内建一个**只做调用转发的轻包装 FB** 承接出口，**禁止**把卷径公式复制进来（复制即违反「低层能力不得内联」红线）。

   该 FC 自带的 `1D10`（低速沿用上次值）、`1D04`（卷芯修正）等事件码**不复制进本件码表**：本件统一以自有 `01C0` 表达「卷径无效已沿用」，两套码各归其主（R30 码位自证边界）。
2. **锥度系数**：`fTaperFactor := 1.0 - fTaperK * (fDiaAct - fCoreDia) / (fDiaMax - fCoreDia)`；分母 `<= EPS` → 置 1.0 并 `01C1`；结果钳到 `[1 - fTaperK, 1.0]`（`fTaperK` 本身钳到 `[0, 1]`）。
3. **基准张力**：`fBase := fTensionSet * fTaperFactor`。
4. **摆辊修正**：`fDancerErr := fDancerPos - fDancerRef`；调用已入库 PID 实例（**输出域取 −1~+1 归一化**，而非默认 0~100 百分比），再乘修正满量程转成张力：

   ```iecst
   fbTensionPid(
       bEnable   := bEnable AND bRun,
       fSetpoint := fDancerRef,
       fActual   := fDancerPos,
       fKp       := fPidKp,
       tTi       := T#0S,           // 纯比例：摆辊环不做积分，防卷径变化时积分饱和
       tTd       := T#0S,
       rOutMin   := -1.0,           // 归一化下限
       rOutMax   := 1.0,            // 归一化上限
       tSampleTime := T#10MS,
       bReset    := bReset );
   fTrim := fbTensionPid.fOut * fTrimSpan;   // 归一化 → 张力修正 [N]
   ```

   修正项**加在基准上**而非串接，保证「摆辊故障时仍有锥度张力可用」（失反馈不丢张力）。
5. **限幅**：`fTensionOut := CLAMP(fBase + fTrim, fTensionMin, fTensionMax)`；触限置 `01C2`（信息级）。
6. **失反馈**：`fDancerPos` 非有限或绝对值 > 500.0 mm（机械不可能值）→ `02D0`（故障级，`bError` 置位，输出保持限幅后的基准张力**不加修正**，即「降级到开环」）。
7. **卷径连续无效**：`nInvalidDiaCnt > DL_INVALID_MAX`（50 次）→ `02D1` 锁存（几何法已不可信，必须停线检查），`nInvalidDiaCnt` 在任一次有效反算时清零。
8. **状态纪律**：本件的 `E_DL_TensionPhase` 是**工艺相位**（闭环 / 开环降级），**不是**轴状态；轴状态机仍归 `I_DL_MotionAxis`（PLCopen 语义分层，T1-6 借鉴点）。二者严禁合并进同一枚举。

**状态机（ENUM + CASE）**

| 当前态 | 迁移条件 | 目标态 |
|---|---|---|
| `eIdle` | `bEnable AND bRun` | `eClosedLoop`（`bInControl := TRUE`） |
| `eClosedLoop` | 摆辊反馈丢失（`fDancerPos` 非有限或绝对越界） | `eOpenLoop`（`02D0`，`bInControl := FALSE`，只出 `fBase`） |
| `eOpenLoop` | 摆辊反馈恢复（连续 3 拍在物理域内） | `eClosedLoop`（`bInControl := TRUE`，PID 以 `bTrack` 无扰投切） |
| `eClosedLoop` | 卷径连续无效超限 | `eFault`（`02D1` 锁存） |
| `eClosedLoop` / `eOpenLoop` | `NOT bEnable` 或 `NOT bRun` | `eIdle`（`fTensionOut := 0.0`，PID 复位） |
| `eFault` | `bReset` 上升沿 | `eIdle` |
| **`ELSE`** | 非法值 | `eFault` + `16#0004_02D1`（复用本件最高优先级故障码，不另造码） |

**码位表**：`16#0004_01C0` 卷径无效已沿用上次有效值（信息级）｜`16#0004_01C1` 锥度系数分母退化/超界已钳位（信息级）｜`16#0004_01C2` 张力输出限幅生效（信息级）｜`16#0004_02D0` 摆辊反馈丢失（故障级，降级开环）｜`16#0004_02D1` 卷径连续无效锁存（故障级）。

**验收向量**

| 向量 | 输入 | 期望输出 |
|---|---|---|
| V1 锥度系数 | `fTaperK = 0.5`、`fCoreDia = 200`、`fDiaMax = 1000`、`fDiaAct = 800 mm` | `fTaperFactor = 1 − 0.5×(800−200)/(1000−200) = 0.625` |
| V2 基准张力 | 同上且 `fTensionSet = 100 N` | `fBase = 62.5 N` |
| V3 摆辊修正 | `fDancerErr = +2.0 mm`、`fPidKp = 0.5`（归一化 1/mm）→ P 输出 `+1.0`（恰达归一化上限）、`fTrimSpan = 1.0 N` | `fTrim = +1.0 N` → `fTensionOut = 63.5 N`（62.5 + 1.0） |
| V4 满卷 | `fDiaAct = fDiaMax = 1000 mm`、`fTensionSet = 100 N` | `fTaperFactor = 0.5` → `fBase = 50.0 N` |
| V5 卷径反算 | `fLineSpeed = 120 m/min`、`fAxisSpeedRpm = 60 rpm`、直连 | `D = v/(π·n) = 120/(π×60) = 0.63662 m` → `fDiaAct ≈ 636.6 mm`（±0.5） |
| V6 卷径无效 | `fAxisSpeedRpm = 0` | `fDiaAct` 沿用上次值、码 `16#0004_01C0`、`bError = FALSE` |
| V7 反馈丢失 | `fDancerPos` 突变为 9999.0 mm | `fTensionOut = fBase`（不加修正）、码 `16#0004_02D0`、`bError = TRUE` |

---

## 二、与 ROADMAP 勾选对应关系（入库后执行，本轮不动 ROADMAP 勾选位）

| ROADMAP 位置 | 条目 | 本轮状态 |
|---|---|---|
| §6 P0 待办 | `FB_DL_PressFitStation` / `FB_DL_RotaryIndexTable` / `FB_DL_AgvDockingHandshake` / `FB_DL_EnergySavingMode` | 4 件全部立项，入库后勾选 |
| §7.1 锂电 | `FB_DL_NtcTempScan`（DL_Device 行） | 立项，入库后勾选 |
| §7.1 锂电 | `FB_DL_RollerGapAdjust`（DL_Device 行） | 立项，入库后勾选 |
| §7.1 锂电 | `FB_DL_WindingTensionCtrl`（DL_Motion 行） | 立项，入库后勾选 |
| §7.3 半导体 | `FB_DL_R2rEwmaTuner`（DL_Algo 行） | 立项，入库后勾选 |
| 其余 8 件 | `FB_DL_PortDiagAggregator` / `FB_DL_StatusWordSegDecoder` / `FB_DL_YearWindowCheck` / `FB_DL_RolloverCounter` / `FC_DL_RangeOverlapCheck` / `FC_DL_CalcDistance3D` / `FC_DL_RandomNext` / `FC_DL_PercentileLReal` | ROADMAP 既有清单**无对应行**，入库后按 R5~R10 先例登记至「R11 新增」小节 |

---

## 三、风险与阻断项

1. **P0 阻断（第十一次提醒，已升级为硬阻断）**：R10 终审仍出 2 条「文本机检 + 人工通读均无法捕获」的致命缺陷（缺 CASE 标签、方向量清零）。**R11 落盘前必须先以 CODESYS V3.5 SP19 最小工程导入全库 152 个 POU 完成一次真实编译**；编译通过前，本轮 16 件只进 `_Staging_Raw`，不进 `INDEX_REGISTRY.json`。本计划仅覆盖规格与狩猎，不解除该阻断。
2. **R31 高风险件**：本轮 7 个新 ENUM（`E_DL_PressFitState` / `E_DL_IndexTableState` / `E_DL_AgvDockState` / `E_DL_EcoModeState` / `E_DL_R2rState` / `E_DL_RangeRelation`）。落盘前须逐件填「枚举成员 → CASE 标签」双向映射表（含 `ELSE` 只兜非法值的声明）。
3. **R32 高风险件**：#1 `uErrorId` 写点最多（4 类），#5 `uPortFaultMask` 与首出锁存存在同拍竞争，#7 `afTempC` 有「保持上次值」路径 —— 三件须附「状态量写入点次序表」。
4. **层次风险**：#16 调用 `FB_DL_PidController` 与 `FC_DL_CoilDiameterCalc` 属 Motion → Algo 合法方向；**但** #1 若被后续开发者改为调用 `FC_DL_MultiPointLinear` 则变成 Process → MathData（合法），仍不构成逆向依赖。终审须脚本校验 import 方向。
5. **码位风险**：`0001` 段由 DL_Base 与 DL_MathData 共用，本轮 #9~#14 六个组件同段分配，已在 0.6 表中对全库求差；落盘后须再跑一次全库求差（R30），重叠即回退重排。

---

## 四、验收汇总口径

- 16 件全部给出 ≥3 条可独立复算向量，其中 **FC 件（#11~#14）给出 5~6 条**，覆盖「正常 / 边界 / 退化 / 非法输入」四类。
- 每件必须能回答三个问题：①与同族既有件的边界（写进头注释首段）；②信息级码与故障级码的分界；③`ELSE` 兜底后的安全输出。
- 本轮**不产出**任何 `.st`：规格层面的验收以「编码者照本实现后自检」为界，真正的验收在落盘轮次执行。
