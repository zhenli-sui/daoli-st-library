# DL_Motion — 版本记录 / Version History

> **子库定位 / Role**：Level 1 运动控制 OOP 封装层：以 `I_DL_MotionAxis` 接口 + PLCopen 轴状态模型 clean-room 实现为核心，同一状态机适配真实伺服驱动（位置注入）与虚拟运动学仿真（内部积分），上层工艺块经接口注入编程。
> **兼容平台 / Platforms**：CODESYS V3.5+ ｜ TwinCAT 3 ｜ 汇川 InoProShop ｜ Schneider Machine Expert
> **依赖 / Depends**：仅 `Standard.library`（`TON` / `R_TRIG` / `MIN` / `MAX` / `ABS`）；不引用任何其他 `DL_` 子库、不调用任何厂商轴控功能块。

---

> R37 增量行：组件总数 60→**62**（registry 实测口径，本轮 +2 `FB_DL_LineShaftClutch` 04_0_A2 / `FB_DL_FlyingCutSync` 04_0_A3）；两件均注入 `I_DL_MotionAxis`，无新增依赖。

## v1.24 — 2026-11-22（R71）

- R71 新增 1 件：`FB_DL_FlyingShearSync`（飞剪同步五相，同步窗线速失配即退相）。累计 125 件。

---
## v1.23 — 2026-11-21（R59）

R59 新增 PathCornerBlend / SpindleWarmupSeq / ToolLifeBudget，覆盖拐角过渡、热机顺控与刀具寿命预算。

## 当前版本 / Current Version

| 项 / Item | 值 / Value |
|---|---|
| 子库版本 / Sublibrary Version | **v1.16.0** |
| 组件总数 / Components | **64**（registry 实测口径，R30 新增见下方增量行：52→55） |
| 发布日期 / Release Date | 2026-11-18 |
| 库总版本 / Library Version | 2.30.0 |
| 依赖层级 / Dependency Level | Level 1（依赖 `Standard.library`；R11 存量件 `FB_DL_WindingTensionCtrl` 注入 `DL_Algo` 的 PID 与卷径件；R13 新件 `FB_DL_PassiveHomingMonitor` 引用 `E_DL_Ne107Status`（DL_Device 契约件 A1）作健康出口类型，**不引用轴状态枚举、不调用任何 MC_ 功能块**） |
| 故障码段 / Error Code Family | **`16#0004_xxxx`**（信息级 `16#0004_01xx` ｜ 故障级 `16#0004_02xx`；R13 占用 `01C3`~`01C6` 与 `02D2`~`02D4`，为 R12 声明的下一可用码） |


## v1.15.0 ｜ 2026-11-18 ｜ R38：2 件（SpindleOrientationStop / ElectronicCamSwitchBank）

| # | 组件 / Component | 类型 | 码位 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 8 | FB_DL_SpindleOrientationStop | FB | `16#04_0_A4` | t1-6-plcopen | 主轴定向停止：最短角路径寻标 → 爬行锁定 → 抱闸释放时序 |
| 9 | FB_DL_ElectronicCamSwitchBank | FB | `16#04_0_A5` | t1-6-plcopen | 电子凸轮开关组（位置触发 + 相位偏移 + 触发脉宽 + 单次/周期） |

> R38 增量行：组件总数 → **64**（registry 实测口径）；库总版本 2.30.0。

## v0.16.0 ｜ 2026-11-18 ｜ R30 光伏/锂电运动工艺批：3 件

- `FB_DL_TrackerBacktrackCalc`：光伏跟踪支架逆跟踪角度修正（阵列阴影几何，arctan 归一化防除零，太阳高度角 <0 归位停跟踪）（0004_0354~0358）。
- `FB_DL_LamStepperFeed`：层压机铺膜步进送料（开环步进契约 + 膜长累计 + 保养窗冻结 + 堵转耗时 ×1.5 判据）（0004_0359~035D）。
- `FB_DL_ElectrodeRollDiameter`：极卷直径跟踪与换卷预警（D=v·i/(π·n) 防除零递推 + 单调性校验 + 恰好等于预警径向量）（0004_035E~0362）。

> R30 增量行：组件总数 52→**55**（registry 实测口径）。

---

## v0.11.0 ｜ 2026-11-16 ｜ R19 运动批：外部编码器折算/凸轮相位修调/膜卷纠偏/层数计数 4 件

- `FB_DL_ExternalEncoderScaler`：外部编码器回绕展开与折算（码位见 .st 头注释码位总账）。
- `FB_DL_CamPhaseTrim`：凸轮相位在线修调（限速率渐进 + 标记沿一次性补偿，禁浮点 MOD 归一）（码位见 .st 头注释码位总账）。
- `FB_DL_FilmWebCenter`：膜卷纠偏（EPC/CPC，死区保持/断料保持/限速率）（码位见 .st 头注释码位总账）。
- `FB_DL_WindingLayerCounter`：卷绕层数与剩余层数计数（卷径交叉校核）（码位见 .st 头注释码位总账）。

> `16#0004_` 段游标：信息级下件起点 **01D5**｜故障级下件起点 **02EA**。

---

## v0.10.0 ｜ 2026-11-16 ｜ R18 场景件第 5 轮：跟随误差监控 + 同步停 + 背隙补偿 3 件 / R18 Scenario Lane — 3 Axis Protection Components

**变更性质**：MINOR（新增 3 个组件）+ PATCH（`FB_DL_BacklashCompensator` 学习率下限常量与声明域对齐 v1.0.0→v1.0.1）。

### 新增组件（3 件）/ Added Components

| 组件 | 类型 | 一句话功能 | 关键引脚 |
|---|---|---|---|
| `FB_DL_AxisFollowingErrorMonitor` | FB | 指令/实际位置快照算跟随误差并三级判定 | `fSetPosition` |
| `FB_DL_AxisSynchronizedStop` | FB | 按固定减速度斜坡生成停车指令序列并预估停止距离 | `bExecute` |
| `FB_DL_BacklashCompensator` | FB | 换向瞬间叠加方向性补偿量，EWMA 自学习背隙 | `fCmdPosition` / `fBacklash` / `bAutoLearn` |

> 码位以注册表 `code_segment` 为准；全库重叠复测 = 0。

## v0.9.0 ｜ 2026-11-16 ｜ R13 被动回零旁路监听（参考事件确认，DL_Motion 第 18 件，补 R8 留扩产项）/ R13 Passive Homing Monitor

**变更性质**：MINOR（新增 1 个组件，终审修复后 **v1.0.1**），无破坏性变更，无迁移动作。对应 Round 13「轴被外力移动时的旁路参考事件确认」定位（来源标签 plcopen-motion，参考 PLCopen Part 1 公开的 reference event / passive homing 语义，clean-room）。终审 **PASS with fixes**：缺陷 1 条（中等·坏值穿透）修复 → v1.0.1。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 18 | `FB_DL_PassiveHomingMonitor` | FB | 464 | **1.0.1** | plcopen-motion | **v1.0.1** —— 被动回零旁路监听：轴被外力移动（手摇轮 / 重力下落 / 维护推车）时监听参考事件沿，按「方向一致性 + 速度窗 + 多次位置一致性」三判据确认参考点，输出建议偏移（= 0 − fRefPos）给上层按 MC_SetPosition 语义消费；**不发任何运动指令、不自造轴状态**（ePhase 仅作 HMI 诊断显示，禁止当轴状态用）；与主动回零件 `FB_DL_AxisHomingSeq` 分工互补、可并存；v1.0.1 修复事件受理未排除本拍故障与掉使能（非有限值检出当拍的零化快照可能被采信锁存为参考点，坏值穿透） / Passive homing reference-event monitor, no motion commands issued |

### 故障码台账追加（R13 码位登记，经终审全库复核 0 重叠）/ Error Code Ledger Additions (R13)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0004_01C3` | 信息级 | 速度窗越界，事件已采信但精度降级 | FB_DL_PassiveHomingMonitor |
| `0004_01C4` | 信息级 | 方向与上次相反，一致性计数重置 | FB_DL_PassiveHomingMonitor |
| `0004_01C5` | 信息级 | 布防期间长时间无运动（未超总超时） | FB_DL_PassiveHomingMonitor |
| `0004_01C6` | 信息级 | 多次事件位置超容差，计数重置 | FB_DL_PassiveHomingMonitor |
| `0004_02D2` | 故障级 | 布防超时未捕获事件 | FB_DL_PassiveHomingMonitor |
| `0004_02D3` | 故障级 | 位置或速度非有限 | FB_DL_PassiveHomingMonitor |
| `0004_02D4` | 故障级 | 非法状态兜底 | FB_DL_PassiveHomingMonitor |

---

## v0.8.0 ｜ 2026-11-15 ｜ R12 两轴直线插补（速度剖面自适应，1 件）/ R12 Two-Axis Linear Interpolation

**变更性质**：MINOR（新增 1 个组件，终审修复后 **v1.0.1**），无破坏性变更，无迁移动作。对应 Round 12「GitHub topics 运动线：两轴直线插补」（来源标签 github-topics-motion，只借鉴社区共识的三段剖面结构与参数域，clean-room）。终审 **PASS with fixes**：**缺陷 2 条（严重 1 + 轻微 1）全部修复** → v1.0.1。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 17 | `FB_DL_LineInterp2Axis` | FB | 476 | **1.0.1** | github-topics-motion | **v1.0.1** —— 两轴直线插补：单位向量分解 + 合成速度按单轴限速折算 + 梯形/三角自适应三段剖面（加速 / 匀速 / 减速），逐拍积分给 X/Y 位置给定、路径完成度与合成速度；暂停段速度归零且位移保持，恢复按剩余量分流；终点出口强制把已走距离钳到路径总长（进度置 100），收尾速度保留下限防「永远差最后一点」；v1.0.1 加速段出口补「速度亦达峰值」条件、零长度路径完成时进度给满值（R41） / Two-axis linear interpolation with adaptive trapezoidal profile and speed-capped vector decomposition |

### 故障码台账追加（R12 码位登记，经终审全库复核）/ Error Code Ledger Additions (R12)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0004_0109` | 信息级 | 路径长度为零，当拍直接完成，给定等于起点、进度 100 | FB_DL_LineInterp2Axis |
| `0004_010A` | 信息级 | 标称插补周期越界，已钳到 0.1 ms~1 s | FB_DL_LineInterp2Axis |
| `0004_010B` | 信息级 | 单轴速度上限参与折算，合成速度已被压低（X/Y 分量恰好不越限） | FB_DL_LineInterp2Axis |
| `0004_010C` | 信息级 | 路径过短，速度曲线降为三角（无匀速段） | FB_DL_LineInterp2Axis |
| `0004_0204` | 故障级 | 速度、加速度、单轴限速或最大路径长参数非法（非正 / 非有限） | FB_DL_LineInterp2Axis |
| `0004_0205` | 故障级 | 路径长度超过允许上限（`fMaxPathLen`） | FB_DL_LineInterp2Axis |
| `0004_0206` | 故障级 | 输入含非有限值（NaN / 无穷），前置拦截 | FB_DL_LineInterp2Axis |
| `0004_0207` | 故障级 | 非法状态兜底（终端安全态） | FB_DL_LineInterp2Axis |

**号段占用声明**：本批 `DL_Motion` 取 R11 声明的下一可用信息级码 `0109`（`0109`~`012F` 为本库最大连续空块的首段）与故障级 `0204`，件内连续、未跳号、未借用其他子库码段。

### 缺陷修复 / Fixed

| 组件 / Component | 级别 | 缺陷 / Defect | 修复 / Fix |
|---|---|---|---|
| `FB_DL_LineInterp2Axis` | **严重** | 暂停恢复后第一个扫描周期速度由 0 直跳峰值（V1 工况 100 mm/s）：位置连续但速度阶跃，伺服按位置给定跟随会报跟随误差 | 加速段出口改 `(fS >= fAccDist) AND (fV >= fPeak)`；恢复时按剩余量分流（剩余 ≤ `fAccDist` 直接进减速段，避免再加速冲过终点） |
| `FB_DL_LineInterp2Axis` | 轻微 | 零长度路径完成时 `fPathProgress` 输出 0，与验收 V3「进度 100」及完成相显式赋值矛盾（画面在「已完成」与「0%」间打架） | 零长度分支补「完成相满值」判定（`ELSIF ePhase = eDone THEN 100`） |

### 变更说明 / Change Notes

- **插补件不替代点动/定位件**：`FB_DL_AxisRelativeMove` 走单轴 PLCopen 语义、`FB_DL_ElectronicGear/Cam` 走主轴耦合，本件是**笛卡尔空间的两轴合成**，输出的是位置给定而非轴命令，三者不可互换。
- **不注入轴接口**：本件只产出 `fCmdX` / `fCmdY` 位置给定，由调用方按需送进 `I_DL_MotionAxis`，从而不绑定任何厂商轴控块，也不承担使能、回零与限位职责。
- **红线状态**：R1~R44 全部通过，机检 0 命中；全库码位跨文件重叠 = 0。

---

## v0.7.0 ｜ 2026-11-15 ｜ R11 卷绕张力族开族（锥度张力 + 摆辊修正闭环，1 件）/ R11 Winding Tension Control

**变更性质**：MINOR（新增 1 个组件，终审修复后 **v1.0.1**），无破坏性变更，无迁移动作。对应 Round 11「DL_Motion 卷绕张力族开族件」（来源标签 lgf-technology / s7-motion / PLCopen，只借鉴功能分类与参数域，clean-room）。终审 **PASS with fixes**：**缺陷 3 条（致命 2 + 严重 1）全部修复** → v1.0.1。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 16 | `FB_DL_WindingTensionCtrl` | FB | 576 | **1.0.1** | lgf-technology / s7-motion / PLCopen | 卷绕张力给定合成器：基准张力 = 目标张力 × 锥度系数（随卷径由 1.0 平滑衰减到 1−K），摆辊位置误差经**纯比例**修正环（PID 积分/微分时间给零，卷径时变工况不给积分饱和留活口）折算为张力修正量，两层相加后限幅输出，可直接送比例阀或伺服转矩限幅入口；卷径可由线速/角速反算或外部注入；摆辊反馈丢失**显式**降级开环（只出锥度基准张力，不静默沿用上次闭环输出），开环恢复闭环前做两拍无扰跟踪；锥度分母双重校验 + 系数双向钳位 / Winding tension setpoint synthesiser with taper factor and dancer trim loop |

### 终审缺陷与修复 / Final Review Defects and Fixes（v1.0.0 → v1.0.1）

| 编号 | 级别 | 缺陷 / Defect | 修复 / Fix |
|---|---|---|---|
| D-a | **致命** | 投切跟踪计数器只置位不递减（`bTrack` 恒真）→ 修正量恒为 0、闭环退化为开环 | 在闭环态逐拍递减跟踪计数 |
| D-b | **致命** | 跟踪窗内过程值仍取实测值 → PID 反算积分残量非零（跟踪结束时积分恒等于负比例项），验收向量 V3 的修正 +1.0 N 数学上不可达 | 跟踪窗内过程值改取基准值，使偏差为零、反算积分为零 |
| D-c | **严重** | `02D1` 判据用「大于」饱和计数上限 → 计数封顶时判据永假，锁存永不触发 | 改为「大于等于」，与饱和计数上限自洽 |

### 故障码台账追加（R11 码位登记，经终审全库复核）/ Error Code Ledger Additions (R11)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0004_01C0` | 信息级 | 卷径无效（无有效反算或注入非法），已沿用上次有效值 | FB_DL_WindingTensionCtrl |
| `0004_01C1` | 信息级 | 锥度系数分母退化或系数超界，已钳位（系数置 1.0） | FB_DL_WindingTensionCtrl |
| `0004_01C2` | 信息级 | 张力输出限幅生效，输出被钳到张力域边界 | FB_DL_WindingTensionCtrl |
| `0004_02D0` | 故障级 | 摆辊反馈丢失（非有限值或超机械行程），降级开环（不停机，仅提示） | FB_DL_WindingTensionCtrl |
| `0004_02D1` | 故障级 | 卷径连续无效超限（几何法已不可信），锁存待复位 | FB_DL_WindingTensionCtrl |

**号段占用声明**：信息级 `0004_01C0`~`01C2` 三码连续；故障级 `0004_02D0`/`02D1` 两码（`02Cx` 为存量占用，本批从 `02D0` 起段）。信息级码只进 `uErrorId` 不置 `bError`；`02D0` 虽为故障级但只降级不停机（`bError` 置位提示上游）；`02D1` 进 `eFault` 锁存。终审逐码求差无重叠。

### 变更说明 / Change Notes

- **层次合法性**：本件依赖 `DL_Algo` 的 `FB_DL_PidController`（经 `VAR_IN_OUT` 注入，输出域经 `rOutMin`/`rOutMax` 归一化到 −1~+1）与 `FC_DL_CoilDiameterCalc`（几何反算，入口出口均为米制，本件负责毫米/米换算），Motion 依赖 Algo 属允许方向；不引用 `DL_Process`。
- **工艺相位 ≠ 轴状态**：本件的四态枚举（`eIdle` / `eOpenLoop` / `eClosedLoop` / `eFault`）是工艺相位（闭环或开环降级），**不是**轴状态；轴状态机仍由 `I_DL_MotionAxis` 的 PLCopen 语义承载，两者严禁合并。
- **规格偏离留档**：① 规格伪码把 `fPidKp` 原样送 PID 又要求「摆辊正误差得正修正」，符号相反 → 实现送 `−ABS(fPidKp)`，依托 PID 件已文档化的「负增益即反作用」特性；② 规格成员 `nInvalidDiaCnt` 定义为 `UDINT` 与无符号前缀红线冲突 → 改名 `uInvalidDiaCnt`；③ 规格未规定故障态张力输出 → 实现取 0.0；④ 规格未覆盖「使能瞬间反馈已丢失」→ 显式进 `eOpenLoop` 并带 `02D0`。
- **非安全功能声明**：本件不构成安全功能，断带与超张力保护必须由硬件与认证安全回路承担。
- **红线状态**：R1~R32 全部通过，机检 0 命中；全库码位跨文件重叠 = 0。

---

## v0.6.0 ｜ 2026-11-15 ｜ R10 卷绕排线工步件（排线轴往复 + 卷径仲裁，1 件）/ R10 Winding Traverse

**变更性质**：MINOR（新增 1 个组件，终审修复后 v1.0.1），无破坏性变更，无迁移动作。对应 Round 10「DL_Motion 卷绕排线」（主源标签 lgf-technology 卷径递推语义 / 次源 s7-motion 排线轴定位与端点 dwell 语义，RAW_NOTES_R10 S-4）。终审 **PASS with fixes**：缺陷 4 处——**D-02【致命】待机态每拍清方向量 → 排线位移恒 0**、D-04【严重】A 端判据缺方向条件致启动首拍误判到位、D-07【中等】轴等待上限分母 0/0 得 NaN、D-08【中等】仲裁卷径首拍未预置；全部修复 → **v1.0.1**。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 15 | `FB_DL_WindingTraverse` | FB | 479 | **1.0.1** | lgf-technology / s7-motion | 收卷卷径递推 + 排线轴往复（五态 eIdle/eWinding/eDwelling/eStopping/eFault）：卷径双源仲裁（`bUseInjectedDia` 选注入或内部层厚递推）+ 位移按「圈数增量 × 每圈节距」积分 + 端点方向判据（只有「正在朝该端运动」才算到达）+ 端点 dwell 换向 + 端点钳位绝不越界；`fAxisPos` 仅作监视不参与积分（防反馈抖动反向污染节距） / Diameter recursion plus reciprocating traverse with direction-aware end detection |

### 故障码台账追加（R10 码位登记）/ Error Code Ledger Additions (R10)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0004_01B0` | 信息级 | 卷径、厚度、线速度或任务周期越界被钳位 | FB_DL_WindingTraverse |
| `0004_01B1` | 信息级 | 排线宽度或每圈节距越界被钳位 | FB_DL_WindingTraverse |
| `0004_01B2` | 信息级 | 注入卷径越界，回落内部递推 | FB_DL_WindingTraverse |
| `0004_01B3` | 信息级 | 排线轴未就绪，拒绝启动（不锁故障） | FB_DL_WindingTraverse |
| `0004_02C0` | 故障级 | 参数非有限值 | FB_DL_WindingTraverse |
| `0004_02C1` | 故障级 | 非法状态兜底 | FB_DL_WindingTraverse |
| `0004_02C2` | 故障级 | 排线轴到位超时（方向非零且长期不到位） | FB_DL_WindingTraverse |
| `0004_02C3` | 故障级 | 卷径递推不收敛（已达上限仍持续增圈） | FB_DL_WindingTraverse |

> 码位带：`0004_01B0~01B3` / `0004_02C0~02C3` 为 DL_Motion 在本轮新开的一段（R9 用至 `01A3` / `02B2`），全库求差确认无冲突。

### 变更说明 / Change Notes

- **致命缺陷教训（D-02 / R32 素材）**：待机分支 `nDirInt := 0;` 位于分支体最前且无条件每拍执行，启动后卷绕分支从不重新赋值 ±1（端点只做 `nDirInt := -nDirInt`，0 取反仍 0）→ 位移增量恒 0、轴原地不动、状态在 eWinding/eDwelling 间抖动。修法：方向赋值移入**启动成功分支**（固定正向启动），仅未启动时才清零。**沉淀 R32「内部状态量写入点全拍排序审计」**。
- **D-04**：端点判据必须带方向条件——启动时 `fTravPos = 0` 会让 `<= 0.0` 首拍命中「到达 A 端」，表现为每次启动先跑到 A 端再折返、首圈排线相位错乱。
- **观察项 O-3**：引脚 `nPitchPerRev : LREAL` 前缀（`n` = 有符号整数）与类型冲突；因与规格书/对外契约同源，PATCH 版改名属破坏性变更，下一 MAJOR 统一改 `fPitchPerRev`。
- **红线状态**：R1~R32 全部通过，机检 0 命中；全库码位跨文件重叠 = 0。

---

## v0.5.0 ｜ 2026-11-15 ｜ R9 叠加运动补偿件（T2-4 S7-1500 MC + T1-6 PLCopen 双源）/ R9 Superimposed Move

**变更性质**：MINOR（新增 1 个组件），无破坏性变更，无迁移动作。对应 Round 09「DL_Motion 叠加运动」（来源标签 plcopen-motion / s7-motion 双源印证：S7-1500 Motion Control 公开手册 MC_MoveSuperimposed 行为语义 + PLCopen TC3 叠加命令公开语义域，clean-room）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 14 | `FB_DL_SuperimposedMove` | 功能块 | 358 | 1.0.0 | plcopen-motion / s7-motion | 叠加运动补偿层（MC_MoveSuperimposed 语义）：基础轴运行的同时叠加动态偏移（视觉纠偏/张力微调/飞剪对位），偏移指令经幅值限幅与斜坡限速后与基础位置代数叠加输出合成位置；零偏移收敛需零驻留窗口 + 浮点残差硬置 0（防 HMI 假偏移）；使能撤销为「冻结保持」语义（不归零不跳变）；斜坡内联实现（规格偏离留档：不调用 FB_DL_RateLimiter，无外部组件依赖） / Superimposed motion compensation layer (MC_MoveSuperimposed semantics) |

### 故障码台账追加（R9 码位登记，经终审核实空闲）/ Error Code Ledger Additions (R9)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0004_01A0` | 信息级 | 任务周期引脚非法已按 10 ms 兜底 | FB_DL_SuperimposedMove |
| `0004_01A1` | 信息级 | 偏移指令已按幅值上限限幅（削顶平移不跳变） | FB_DL_SuperimposedMove |
| `0004_01A2` | 信息级 | 偏移指令非有限值已拒绝（保持末次有效） | FB_DL_SuperimposedMove |
| `0004_01A3` | 信息级 | 不限速直通（限速值 <= 0，一次性提示） | FB_DL_SuperimposedMove |
| `0004_02B0` | 故障级 | 偏移幅值上限非法（<= 0 或非有限值），锁存 | FB_DL_SuperimposedMove |
| `0004_02B1` | 故障级 | 任务周期非法（<= 0 或非有限值），锁存 | FB_DL_SuperimposedMove |
| `0004_02B2` | 故障级 | 非法状态兜底（枚举越界），锁存 | FB_DL_SuperimposedMove |

### 变更说明 / Change Notes

- **职责边界**：只做叠加律、限幅与收敛判据——不触碰轴本体指令（合成位置由上层下发）、不做位置闭环、不做软限位判断（归 `FB_DL_SoftLimitGuard`）；与基础运动正交。
- **终审 PASS（零修改）**：eIdle/eActive/eFault 三态出口齐备、TON 无条件刷新且无「调用前自清」缺陷、验收向量 V1~V6 全部符合；观察项 O-07（故障拍与使能下降沿同拍的极窄重建窗口）留档 v1.1。
- **规格偏离留档**：规格 VAR 段 fbSlew : FB_DL_RateLimiter 实例改为内联斜坡积分（一次乘加完成，避免 REAL/LREAL 与 TIME 毫秒量化的双重精度损失），引脚契约与输出语义完全不变。
- **红线状态**：R1~R8 全部通过，机检 0 命中。

---

## v0.4.0 ｜ 2026-11-15 ｜ R8 同步耦合族开族 + 压装/色标/耗时计算六件（T1-6 PLCopen 深化 +6）/ R8 Motion Six-Piece Set

**变更性质**：MINOR（新增 6 个组件），无破坏性变更，无迁移动作。对应 Round 08「DL_Motion 同步耦合族开族」（来源标签 plcopen-motion，T1-6 PLCopen Motion 深化 +6——MC_GearIn/GearInPos、CamIn/CamTableSelect、双驱同步、转矩限幅/固定停止点、注册标记/探针锁存、梯形/三角耗时估算公开语义 clean-room）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 8 | `FB_DL_ElectronicGear` | 功能块 | 1.0.0 | plcopen-motion | 电子齿轮耦合：整数比值对（分子/分母全程整数保存防浮点漂移）+ 主轴实际速度 × 比值 + 比例式相位补偿（钳 ±fPhaseMax）+ 啮合过渡限斜率/脱开受控降速 + 指令重发去抖（每拍至多一次轴方法调用） / Electronic gear coupling with integer ratio pair and phase compensation |
| 9 | `FB_DL_ElectronicCam` | 功能块 | 1.0.0 | plcopen-motion | 电子凸轮耦合：16 点表分段线性插值（单调性/非有限值啮合沿一次校验）+ 相位归一化用条件加减避负数取模 + 周期/非周期双模式 + 主轴固定偏移与运行相位微调（飞剪切点补偿）/ Electronic cam coupling with 16-point table interpolation |
| 10 | `FB_DL_GantrySyncAxis` | 功能块 | 1.0.0 | plcopen-motion | 龙门双驱主从同步：实时偏差监视（预警/故障双阈 + 延时确认 + 回差清除）+ 比例纠偏（饱和计时判机械卡滞）+ 偏差超故障阈双轴停止（向内恢复豁免语义由调用方承载） / Gantry dual-drive synchronization with deviation monitoring and correction |
| 11 | `FB_DL_TorqueLimitControl` | 功能块 | 1.0.0 | plcopen-motion | 力矩达限压装判定（运行到固定挡块语义）：接近→慢速压装→达限（三源 OR）→保持→位移窗一次锁存判定→释放归位；设备异常进故障锁存、工件不合格只出判定与方向提示，两者严格分离 / Torque-limited press judgment with position-window verdict |
| 12 | `FB_DL_MarkPositionLatch` | 功能块 | 1.0.0 | plcopen-motion | 印刷套准色标锁存：布防窗（T#0S=不限）+ 标记上升沿同拍单次读写轴接口 + 定长 8 槽历史前移（索引 0=最新）+ 位置增量与标记缺失提示 / Mark position latch with arm window and history shift |
| 13 | `FC_DL_CalcMoveTime` | 函数 | 1.0.0 | plcopen-motion | 梯形/三角运动耗时计算（纯函数无状态）：临界距离三角退化显式判、起始速度超上限走减速到点分支、稳定延时直接计入、结果超 T#24H 钳位；规格验收向量 V1/V2 数值与公式矛盾经总监验算裁定公式对、向量错（V1 匀速段 ≈1833 ms、V2 峰速 = 20 mm/s），向量已勘误留档 / Trapezoidal/triangular move-time calculator (pure function) |

### 随组件同文件发布的枚举 / Enums Shipped with Host Files

`E_DL_GearState`（随 #8）、`E_DL_CamState`（随 #9）、`E_DL_GantryState`（随 #10）、`E_DL_PressState`（随 #11）、`E_DL_MarkState`（随 #12）——共 5 个，与各自宿主功能块同文件发布；`FC_DL_CalcMoveTime` 纯函数无状态机无枚举。

### 故障码台账追加（R8）/ Error Code Ledger Additions

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0004_0130` | 信息级 | 主轴静止、相位跟踪冻结（不置故障位） | FB_DL_ElectronicGear |
| `0004_0131` | 信息级 | 未开放连续更新时改传动比被拒（沿用旧比值） | FB_DL_ElectronicGear |
| `0004_0132` | 信息级 | 从轴速度指令被绝对限速钳位 | FB_DL_ElectronicGear |
| `0004_0140` | 信息级 | 主轴方向不符 / 非周期未进表首区（等待中） | FB_DL_ElectronicCam |
| `0004_0141` | 信息级 | 缩放系数非法回默认 | FB_DL_ElectronicCam |
| `0004_0142` | 信息级 | 相位微调突变超限提示 | FB_DL_ElectronicCam |
| `0004_0150` | 信息级 | 偏差未回预警阈内，复位被拒 | FB_DL_GantrySyncAxis |
| `0004_0151` | 信息级 | 预警 / 故障阈值对调自修复 | FB_DL_GantrySyncAxis |
| `0004_0152` | 信息级 | 纠偏速度上限非法回默认 | FB_DL_GantrySyncAxis |
| `0004_0160` | 信息级 | 位移窗上下限对调自修复 | FB_DL_TorqueLimitControl |
| `0004_0161` | 信息级 | 达限力矩超额定（机械风险提示） | FB_DL_TorqueLimitControl |
| `0004_0162` | 信息级 | 压装速度高于接近速度（工艺反常） | FB_DL_TorqueLimitControl |
| `0004_0163` | 信息级 | 到位但位移低于窗下限（压浅方向提示） | FB_DL_TorqueLimitControl |
| `0004_0164` | 信息级 | 到位但位移高于窗上限（压深方向提示） | FB_DL_TorqueLimitControl |
| `0004_0170` | 信息级 | 历史深度越界钳位 | FB_DL_MarkPositionLatch |
| `0004_0171` | 信息级 | 布防窗内无标记（缺失提示） | FB_DL_MarkPositionLatch |
| `0004_0180` | 信息级 | 参数非法（速度 / 加减速度近零或非有限值） | FC_DL_CalcMoveTime |
| `0004_0181` | 信息级 | 临界距离浮点残差，匀速段钳零 | FC_DL_CalcMoveTime |
| `0004_0182` | 信息级 | 距离为零，耗时等于稳定延时 | FC_DL_CalcMoveTime |
| `0004_0183` | 信息级 | 起始速度超上限，按减速到点计算 | FC_DL_CalcMoveTime |
| `0004_0184` | 信息级 | 结果超上限钳位（T#24H） | FC_DL_CalcMoveTime |
| `0004_0250` | 故障级 | 传动比参数非法（分母 0 / 分子非正），锁存 | FB_DL_ElectronicGear |
| `0004_0251` | 故障级 | 从轴速度指令被轴拒绝，锁存 | FB_DL_ElectronicGear |
| `0004_0252` | 故障级 | 从轴故障中断耦合（透传），锁存 | FB_DL_ElectronicGear |
| `0004_0260` | 故障级 | 凸轮点数非法，锁存 | FB_DL_ElectronicCam |
| `0004_0261` | 故障级 | 凸轮表主轴点非单调递增，锁存 | FB_DL_ElectronicCam |
| `0004_0262` | 故障级 | 周期长度非法（周期模式），锁存 | FB_DL_ElectronicCam |
| `0004_0263` | 故障级 | 凸轮表含非有限值，锁存 | FB_DL_ElectronicCam |
| `0004_0264` | 故障级 | 从轴定位指令被拒，锁存 | FB_DL_ElectronicCam |
| `0004_0265` | 故障级 | 从轴故障中断耦合（透传），锁存 | FB_DL_ElectronicCam |
| `0004_0270` | 故障级 | 偏差阈值非法，锁存 | FB_DL_GantrySyncAxis |
| `0004_0271` | 故障级 | 纠偏长时间饱和（疑似机械卡滞），锁存 | FB_DL_GantrySyncAxis |
| `0004_0272` | 故障级 | 轴位置信号非有限值，锁存 | FB_DL_GantrySyncAxis |
| `0004_0273` | 故障级 | 偏差超故障阈触发双轴停止，锁存 | FB_DL_GantrySyncAxis |
| `0004_0274` | 故障级 | 单轴故障触发双轴停止（透传），锁存 | FB_DL_GantrySyncAxis |
| `0004_0280` | 故障级 | 压装行程组态非法（终点不大于起点），锁存 | FB_DL_TorqueLimitControl |
| `0004_0281` | 故障级 | 释放超时，锁存 | FB_DL_TorqueLimitControl |
| `0004_0282` | 故障级 | 压装超时未达限，锁存 | FB_DL_TorqueLimitControl |
| `0004_0283` | 故障级 | 力矩信号非有限值，锁存 | FB_DL_TorqueLimitControl |
| `0004_0284` | 故障级 | 轴指令被拒 / 轴故障，锁存 | FB_DL_TorqueLimitControl |
| `0004_0290` | 故障级 | 轴位置 / 速度非有限值，锁存 | FB_DL_MarkPositionLatch |
| `0004_0295` | 故障级 | 非法状态兜底（MarkPositionLatch 专用） | FB_DL_MarkPositionLatch |
| `0004_0296` | 故障级 | 非法状态兜底（TorqueLimitControl 专用） | FB_DL_TorqueLimitControl |
| `0004_0297` | 故障级 | 非法状态兜底（GantrySyncAxis 专用） | FB_DL_GantrySyncAxis |
| `0004_0298` | 故障级 | 非法状态兜底（ElectronicCam 专用） | FB_DL_ElectronicCam |
| `0004_0299` | 故障级 | 非法状态兜底（ElectronicGear 专用） | FB_DL_ElectronicGear |

全部经子库码表核对顺延，冲突 0。

### 终审观察项（留档 v1.1）/ Final-Review Observations

1. **泄漏率量纲**：`FB_DL_LeakTestStation`（DL_Process）的泄漏率口径为 kPa·mL/min 压降法工艺约定（ΔP × 容积 / 时间换算），与流量计 [mL/min] 体积累纲非同一物理口径——两族文档已各自声明，v1.1 评估是否补「压降-流量」统一换算 FC。
2. **Cam 相位商域**：`FB_DL_ElectronicCam` 相位归一化的商域取 [0.0, 1.0)，周期长度恰好整除时相位落点归属（0 或 1）留 v1.1 裁定。
3. **Gantry 同值阈值**：`FB_DL_GantrySyncAxis` 预警阈与故障阈取同值时判据合并为一级动作，是否禁止同值组态（判参数非法）留 v1.1 评估。

### 变更说明 / Change Notes

- **同步耦合族开族**：Gear/Cam/Gantry 三件构成「速度耦合 / 位置耦合 / 双驱监视」三层语义；全部经 `I_DL_MotionAxis` 既有契约注入（VAR_IN_OUT），零接口方法新增，每拍至多一次轴方法调用（公约 0.13）。
- **相位归一化禁负数取模**：Cam 的相位小数部分用「截断取整 + 条件加减」实现——负数取 MOD 三平台行为不一致（R7 EventCounter 同源教训第二处落地）。
- **判定类组件「设备异常 / 工件不合格」分离**：TorqueLimitControl 与 LeakTestStation（DL_Process）同构——设备异常进故障锁存（bError + 故障级码），工件不合格只出判定输出与信息级方向提示，不污染报警链。
- **验收向量勘误（FC_DL_CalcMoveTime）**：规格第 1.6 节验收向量 V1/V2 数值与计算契约公式自相矛盾，总监验算裁定公式正确、向量错误——V1 匀速段修正为 ≈1833 ms、V2 峰速修正为 20 mm/s（三角退化），勘误随代码一并留档（R20 量纲/向量一致性规则的向量侧应用）。
- **纯函数形态**：`FC_DL_CalcMoveTime` 无内部状态、无定时器实例，全部输出为派生量；是 DL_Motion 首个 FC 形态组件（此前 12 件均为接口/FB）。
- **红线状态**：R1~R7 全部通过，机检 0 命中；R19 首扫/跟踪范式（`IF bTrack OR (NOT bInit)`）逐条落实；R25 单拍标志生命周期三律落实（TorqueLimitControl bDone「进入态置位、下一拍开头复位」闭环）。

---

## v0.3.0 ｜ 2026-11-15 ｜ R7 软限位电子围栏（T1-6 PLCopen 深化）/ R7 Soft-Limit Guard

**变更性质**：MINOR（新增 1 个组件）+ PATCH（1 个文件终审修复 → v1.0.1），无破坏性变更，无迁移动作。对应 Round 07「DL_Motion SoftLimitGuard」（来源标签 plcopen-motion，T1-6 PLCopen 软限位/Safety-limited 公开语义 clean-room——制动距离预判含时延项、方向性恢复豁免）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 7 | `FB_DL_SoftLimitGuard` | 功能块 | **1.0.1** | plcopen-motion | 软限位安全电子围栏预判器：按当前速度与减速度实时计算双向制动距离（fStopDist = fSpeed × tLatency + fSpeed²/(2×fDecel)，时延默认 23 ms = 扫描 10 + IO 5 + 驱动 8 ms 三项口径），预警/拦截两级输出（拦截带 ⊇ 预警带，保守安全侧）；超程后仅允许反向指令（向内恢复豁免）；位置/速度经 `I_DL_MotionAxis` 接口引用读取（v1.0.1：fMargin 非数防御 + 预警/拦截带方向勘误） / Soft-limit guard with braking-distance prediction and inward-recovery exemption |

### 变更说明 / Change Notes

- **接口消费**：仅引用 `I_DL_MotionAxis` 既有契约（读 `fPosition` / `fVelocity` 属性，零修改）；R11 留档——速度来源选定既有接口属性，规格备选 `fAxisSpeed` 引脚弃用。
- **定位声明（公约 0.13）**：应用层预判与诊断镜像，输出为建议信号（拦截执行在调用方），不构成认证安全功能。
- **故障码台账追加（R7）**：`0004_0108`（时延口径提示，信息级）、`0004_0240/0241`（减速度/行程边界非法，故障级），经子库码表核对顺延。
- **红线状态**：R1~R7 全部通过，机检 0 命中；R23 周期监视型免首扫、0.9 非数防御逐条落实。

---

## v0.2.0 ｜ 2026-11-15 ｜ R6 回零/定位族（T1-6 PLCopen Motion 首次开组）/ R6 Homing & Motion Group

**变更性质**：MINOR（新增 3 个组件），无破坏性变更，无迁移动作。对应 Round 06（R6）「DL_Motion 回零/运动族」（来源标签 plcopen-motion / s7-motion，T1-6 PLCopen + T2-4 双源 clean-room；回零模式为组合矩阵非厂商魔法数）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 4 | `FB_DL_AxisHomingSeq` | 功能块 | **1.0.1** | plcopen-motion+s7-motion | 标准回零序列状态机（经 `I_DL_MotionAxis` 接口驱动轴体）：限位开关/原点开关/Z 相脉冲/扭矩堵转四模式，逼近-回退-再逼近-标定时序，超时+行程双护栏，终态重启借道 / Industrial homing sequence with four modes and dual guards |
| 5 | `FB_DL_AxisRelativeMove` | 功能块 | 1.0.0 | plcopen-motion+s7-motion | 单轴相对定位（MC_MoveRelative 语义）：链式步进模式、目标递增累加步进、中止与轴故障中断 / Relative move with chained stepping |
| 6 | `FB_DL_AxisVelocityMove` | 功能块 | 1.0.0 | plcopen-motion+s7-motion | 单轴速度模式（MC_MoveVelocity 语义）：动态改速（连续运动中重发指令）、速度上限钳位、受控停止 / Velocity mode with dynamic retargeting |

### 随组件同文件发布的枚举 / Enums Shipped with Host Files

`E_DL_HomingMode`（eLimitSwitch/eHomeSwitch/eZeroPulse/eTorqueBlock 四项）与 `E_DL_HomingStep`（eIdle→eApproach→eRetreat→eReapproach→eCalibrate→eStopping→eDone/eAborted/eFault 九态）随 `FB_DL_AxisHomingSeq` 同文件发布——**不使用任何厂商模式数值**（本库自有枚举）。

### 故障码台账追加 / Error Code Ledger Additions

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0004_0106` | 信息级 | 启动门禁/参数门禁拒绝（三块同码同义共用，终审留档规范） | HomingSeq / RelativeMove / VelocityMove |
| `0004_0107` | 信息级 | 改速请求不被受理 / 速度钳位提示 | FB_DL_AxisVelocityMove |
| `0004_0210` | 故障级 | 回零总超时 | FB_DL_AxisHomingSeq |
| `0004_0211` | 故障级 | 回零行程超限（启动点距离护栏） | FB_DL_AxisHomingSeq |
| `0004_0212` | 故障级 | 回零中止 / 轴故障中断（规格明示分配，含中止给故障级码的语义瑕疵已留观察项） | FB_DL_AxisHomingSeq |
| `0004_0213` | 故障级 | 序列指令被轴拒绝 / 非法状态兜底 | FB_DL_AxisHomingSeq |
| `0004_0220` | 故障级 | 定位指令被轴拒绝（锁存） | FB_DL_AxisRelativeMove |
| `0004_0221` | 故障级 | 中止 / 轴故障中断（锁存） | FB_DL_AxisRelativeMove |
| `0004_0230` | 故障级 | 速度指令被拒 / 轴故障中断（锁存） | FB_DL_AxisVelocityMove |
| `0004_0201` | 故障级 | 非法状态兜底（族码沿用，RelativeMove/VelocityMove 复用） | 两块复用 |
| `0004_0108` | 信息级 | 时延口径提示（默认值建议实测，一次性） | FB_DL_SoftLimitGuard |
| `0004_0240` | 故障级 | 减速度非法（非有限值/趋零，锁存） | FB_DL_SoftLimitGuard |
| `0004_0241` | 故障级 | 行程边界非法（正向 ≤ 负向，锁存） | FB_DL_SoftLimitGuard |


### 变更说明 / Change Notes

- **T1-6 PLCopen Motion 首次开组**：回零模式骨架取自 PLCopen/SIMATIC 公开模式语义（主动回零「逼近-回退-再逼近」三段式 + 参考源三维分类），模式编号不用厂商数值；被动回零（外力移动轴监听参考事件）本轮不实现，留矩阵扩产并在头注释声明。
- **经接口驱动，绝不出自有速度输出**：回零序列全部经 `iAxis.MoveVelocity` / `MoveRelative` / `Stop` 组合；三块均以 `iAxis : I_DL_MotionAxis` 注入（VAR_IN_OUT），仅依赖既有契约。
- **终审修复**：`FB_DL_AxisHomingSeq` 三终态（完成/中止/故障）原无迁出路径、启动沿被吞——首次回零后无法再次回零；修复为「终态重启借道」（终态收到启动沿回空闲、同拍门禁分支受理，不吞沿不要求双击），组件 → v1.0.1。
- **回零方向**：`bDirNeg` 为规格外补充引脚（规格引脚表未列回零方向，R11 留档）；堵转阈值信号 `bTorqueLimitReached` 由驱动层注入（接口无扭矩域，R11 留档）。
- **坐标建立边界**：本块标定成功后暂存 `fHomePosition`，**不直接写轴内部状态**——`bHomed`/坐标系写入由轴实现块或上层联动（接口契约 §方法语义）。

### 已知限制 / Known Limitations

1. `FB_DL_AxisHomingSeq` 的 `0004_0212` 同时承载中止与轴故障两类事件（中止非故障但规格明示分配，遵守规格，观察项留 ROADMAP 评估）。
2. 信号缺失类启动条件（如 Z 相脉冲通道未接线）不可观测，由调用方保证；本块仅做可观测矛盾检测（如「启动时原点开关已压住」）。
3. `FB_DL_AxisRelativeMove` / `FB_DL_AxisVelocityMove` 信息级码为单扫描可见（与 DL_Device 族「无故障透出本拍信息级」口径一致；与 AxisHomingSeq「持久驻留」口径存在跨族差异，HMI 采集需按族适配）。

---

## v0.1.0 ｜ 2026-11-15 ｜ DL_Motion 立项 / Initial Release — DL_Motion Opening

**变更性质**：初始发布（Initial release），无破坏性变更，无迁移动作。全部 3 个组件自 v1.0.0（组件级）起入库，对应 Round 05（R5）「DL_Motion 族」交付（来源标签 s7-motion / plcopen 双源）。

### 组件清单 / Component Inventory

| # | 组件 / Component | 类型 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 1 | `I_DL_MotionAxis` | 接口 | 1.0.0 | plcopen+s7-motion | 单轴运动控制标准抽象契约：PLCopen 六态 + 禁用态枚举 `E_DL_AxisState`、只读属性 7 个、方法 6 个（Enable/Reset/Stop/MoveAbsolute/MoveRelative/MoveVelocity，达 ≤6 红线临界）；回原由后续轮次组件承载不入本接口 / Single-axis motion interface contract on the PLCopen state model |
| 2 | `FB_DL_SingleAxis` | 功能块 | 1.0.0 | plcopen+s7-motion | 单轴运动控制参考实现：PLCopen 状态机 + 指令仲裁（Absolute>Relative>Velocity）+ 软限位预判拦截 + 虚拟运动学梯形积分仿真/真实位置注入双模式 / Single-axis reference implementation with virtual kinematics simulation mode |
| 3 | `FB_DL_AxisJogController` | 功能块 | 1.0.0 | s7-motion | 轴点动操作器：长按低速、按住高速键延时自动升高速、松开受控停止；点动软限位独立于轴组态，制动距离警戒区强制降速 / Axis jog controller with fast-switch delay and jog soft-limit guarding |

### 随组件同文件发布的枚举 / Enums Shipped with Host Files

`E_DL_AxisState`（随 #1）——共 1 个，与 `I_DL_MotionAxis` 同文件发布（归属声明见该文件头注释）。

### 变更说明 / Change Notes

- **接口契约**：3 个组件的引脚名称、类型、方向、默认值与终审后源码声明区逐字一致；引脚级细节以 `DL_Motion/*.st` 为准，完整接口表见 `MANUAL_DL_Motion.md`。
- **故障码**：全部使用 `16#0004_xxxx` 段：信息级 `0004_0101`（指令仲裁丢弃）、`0004_0102`（双向点动冲突）、`0004_0103`（参数对调兜底修复）、`0004_0104`（采样周期钳位）、`0004_0105`（软限位预判降速/停车，点动与连续运动共用同码同义）；故障级 `0004_0201`（非法状态兜底）、`0004_0202`（软限位越界：目标拒绝为瞬态码、实际越限为锁存）、`0004_0203`（驱动故障反馈锁存）。信息级码不置 `bError`（R19/R21 公约），`bError` 为派生式仅反映 `eErrorStop` 态。
- **规格偏离留档（R11）**：① `FB_DL_AxisJogController` 规格未列 `uErrorId`，为信息级出码补充输出引脚；② `FB_DL_SingleAxis` 规格引脚表 OUT 列与接口属性同名的 7 个成员以只读 `PROPERTY GET` 形式实现，避免编译器重名冲突。
- **状态跃迁契约**：`I_DL_MotionAxis.st` 头注释固化七条跃迁契约与实现块落地清单（七属性 + 六方法逐字落地、bError 派生式、零全局耦合、不得重定义 `E_DL_AxisState`、不得自造码段），后续真实驱动适配层必须逐条对齐。
- **`bHomed` 占位**：R6 起 `FB_DL_AxisHomingSeq` 已交付（四模式回零序列）；`bHomed` 属性仍由轴实现块/上层联动维护——`FB_DL_AxisHomingSeq` 标定成功后暂存 `fHomePosition`，不直接写轴内部状态，依赖回原联锁的工站请按「回零完成（eDone）→ 上层写坐标系 → bHomed 置位」链路接线。
- **红线状态**：R1~R7 全部通过，机检 0 命中；接口方法计数 = 6 达红线临界（不超）；R19 首扫/跟踪范式（`IF bTrack OR (NOT bInit)`）逐条落实。

### 已知限制 / Known Limitations

1. `FB_DL_SingleAxis` 虚拟运动学为简化梯形段积分（复用 SCurve 限 jerk 思想），非七段式 S 曲线；仿真模式下的到位时间与真实驱动存在模型差异，仅用于逻辑联调。
2. `FB_DL_SingleAxis` 未实现回原：`eHoming` 为预留态，实现块在该态内不产生任何运动输出。
3. `FB_DL_AxisJogController` 点动加减速由 `fAcc` 单参数承担（升/降速同斜率），不做双向独立斜率；点动「跟手性」通过调大 `fAcc` 获得。
4. 点动软限位与轴组态软限位是两道独立防线，两者取交集生效；现场收紧点动限位不影响程序自动运行的轴组态限位。

---


## v0.13.0 ｜ 2026-11-17 ｜ R23 行业纵深轮 2 件（运动工艺延伸（ROADMAP P1：半导体计数轴 / 包装摆辊同步））

- `FB_DL_WaferCountAxis`：晶圆计数轴（编码器分频 + 片位同步）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_BagFeedDancerSync`：制袋供膜摆辊同步（线速前馈 + 摆辊 PI + 抗饱和；v1.0.1 补拓扑语义假设留档）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。

> **R86 组件数断言**：注册表 counts[DL_Motion] = 32，本文档原记 26（历史批次漏计，随本节一并校正）；本轮已校正为注册表口径。

> **终审留痕**：BagFeedDancerSync 终审补拓扑语义假设留档升 v1.0.1（符号经「抽膜」拓扑推演为负反馈正确）。


## v0.13.0 ｜ 2026-11-17 ｜ R23 行业纵深轮 2 件（运动工艺延伸（ROADMAP P1：半导体计数轴 / 包装摆辊同步））

- `FB_DL_WaferCountAxis`：晶圆计数轴（编码器分频 + 片位同步）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_BagFeedDancerSync`：制袋供膜摆辊同步（线速前馈 + 摆辊 PI + 抗饱和；v1.0.1 补拓扑语义假设留档）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。

> **R86 组件数断言**：注册表 counts[DL_Motion] = 32，本文档原记 32（一致）；本轮已校正为注册表口径。

> **终审留痕**：BagFeedDancerSync 终审补拓扑语义假设留档升 v1.0.1（符号经「抽膜」拓扑推演为负反馈正确）。

## 版本号约定 / Versioning Policy

子库遵循 SemVer，且与库总版本联动：

- **MAJOR**：任一组件删除引脚、改引脚语义、改默认值、改故障码含义、接口方法签名或状态跃迁语义变化。
- **MINOR**：新增组件，或为已有组件新增可选输入（带默认值）。
- **PATCH**：内部实现修正、注释与手册补全、性能优化，接口与行为不变。

破坏性变更必须在本文档写明迁移指引（旧调用 → 新调用）与影响的组件清单；接口升版时实现块同步升版并重跑验收向量基线（见 `I_DL_MotionAxis.st` 头注释）。

---

## 后续计划 / Next

R7 已交付软限位电子围栏；R8 已交付同步耦合族开族（电子齿轮/电子凸轮/龙门同步）+ 压装力矩/色标锁存/耗时计算；R9 叠加补偿；R10 卷绕排线工步；R11 卷绕张力族开族（锥度张力 + 摆辊修正闭环）；v0.8.0（R12）交付双轴直线插补一件（`FB_DL_LineInterp2Axis`），现 17 项（接口 1 ｜ 功能块 15 ｜ 函数 1）。

双轴插补件的边界口径须记住三条：①**只有两轴**，不做圆弧与螺旋，多轴请走 `DL_Motion` 既有多轴件；②插补周期由调用方给（`tCycle`），本件不做周期自校正，周期抖动直接反映为速度波动；③两轴到位判据按**本拍复验**取值（范式 R42），不接受上一拍缓存的轴位置。

后续按 `ROADMAP.md` 第五章推进：张力锥度曲线族（分段锥度 / 双斜率）、被动回零（外力移动轴监听参考事件）、多轴凸轮表管理族、两轴以上插补族等。


---

## v0.12.0 ｜ 2026-11-16 ｜ R22 结构补位轮 5 件

**批次**：本子库 R22 新增 5 件（全库 20 件 6,618 行；机检 20/20 PASS fail=0）
**码位**：本子库本轮占用见各件头注释「码位总账」；收口后全库游标（注册表实测 2026-11-16）：`0001` 信息 `0466` / 故障 `03B7`、`0002` 下一 CC `2D`、`0003` 信息 `017A` / 故障 `0348`、`0004` 信息 `01DF` / 故障 `02F9`、`0005` 信息 `01E2` / 故障 `0317`
**终审结论**：R22 抽检 15 件高风险件，4 件轻微缺陷修复升 v1.0.1（MotionCmdQueue / VirtualMasterAxis / AxisBrakeSeq / BatchTransferSeq），1 件中等安全相关挂账 R23（BatchTransferSeq 中止时序），其余零缺陷 PASS
**码位跨文件冲突断言**：R22 100 槽定向复测 CLASH=NONE；JSONL 384 条全量 sha256 MATCH（本轮另修复 2 件历史换行口径漂移）

- `FB_DL_AxisBrakeSeq`：伺服抱闸时序（上电序先释放后使能 / 断电序先静止后抱闸再断使能，两序写反即掉轴；02EB 拒绝断使能「宁可报警不可掉轴」取舍留档；**v1.0.1**——tBrakeRelease 注释对齐实现并声明 tFbTimeout > tBrakeRelease 约束）。
- `FB_DL_VirtualMasterAxis`：虚拟主轴相位源（速度斜坡积分，LREAL 累加 1.0E15 mm 精度门冻结，bHold 走减速斜坡不阶跃；**v1.0.1**——段 6 积分加 eFault 相位门控，修复参数修复次拍复积分缺陷）。
- `FB_DL_MotionCmdQueue`：运动指令排队器（PLCopen Buffered 语义：前条 Done 才发下条；环形缓冲深度 8 + 指针一致性自愈；出队前移到发令拍消除混叠；**v1.0.1**——eSending 被清队竞态下不再空等 Done，回 eIdle 消除挂死）。
- `FC_DL_CamTableValidate`：凸轮表合法性校验（相位单调/从轴有限/首尾闭合/斜率上限四判据单趟扫描全掩码不早退，Δphase<=0 前置闸先于除法）。
- `FB_DL_AxisInPosMonitor`：到位稳定判定（位置窗 + 速度阈同拍相与 + 稳定时间 + 滚动抖振窗计数，bSettled 出窗即清不锁存跨件；与驱动器跟随误差监视职责划界留档）。

**终审**：本子库 5 件全抽（高风险层），命中 3 件轻微缺陷全部修复升 v1.0.1（见上）。

---

## v0.14.0 ｜ 2026-11-17 ｜ R24 行业纵深轮：运动层 4 新件

**新增 4 件**（码位 0004 段：信息 01E3~01EA / 故障 0300~030B，故障带十年带对齐 0300 起）：

| 组件 | 版本 | 一句话功能 | 来源 |
|---|---|---|---|
| `FC_DL_TrackerBacktrackCalc` | v1.0.0 | 跟踪支架逆跟踪角度修正计算（阵列阴影几何，纯函数） | ROADMAP P2 §360 |
| `FB_DL_WindingAlignEdge` | v1.0.0 | 卷绕极片边缘跟随与蛇形抑制（边缘锁存 + 滤波 + 纠偏行程拦截） | ROADMAP P1 §806 |
| `FB_DL_SolderRibbonTension` | v1.0.0 | 焊带放卷张力与蛇形纠偏（锥度张力 + 横动行程拦截；收口修正头注释子库归属 DL_Device→DL_Motion） | ROADMAP P1 §703 |
| `FB_DL_TrackerSnowShedAngle` | v1.0.0 | 跟踪支架雪载卸荷角与复位（采暖季窗 + 太阳高度角 + 置角限速） | ROADMAP P1 §812 |

---

## v0.15.0 ｜ 2026-11-17 ｜ R25 R25 新增运动封装 2 件 / R25 Batch

**批次**：本轮 20 件中本子库 **2 件**，合计 **702 行**（全库 20 件 7,097 行，终审修复后 7,174 行）
**码位游标（收口后实测）**：信息级推进至 **`01EF`** ｜ 故障级推进至 **`0312`**

| 组件 | 版本 | 一句话功能 / 终审结论 | 来源 |
|---|---|---|---|
| `FB_DL_StackingAlignCtrl` | v1.0.0 | 叠片机 CCD 纠偏（标定矩阵经 FC_DL_Affine2DInvert 求逆 + 行程限幅 + NG 锁存） | ROADMAP P1 §210 |
| `FB_DL_LabelApplySync` | v1.0.0 | 贴标同步出标（编码器提前量 + 低速暂停出标） | ROADMAP P1 §271 |

---

## v0.17.0 ｜ 2026-11-18 ｜ R31 外部编码器族开族（接口 + 锁存）：2 件

| 组件 | 版本 | 码位起始 |
|---|---|---|
| `I_DL_ExternalEncoder` | v1.0.0 | 16#0004_0063 |
| `FB_DL_ExternalEncoderLatch` | v1.0.0 | 16#0004_0067 |

> R31 增量行：组件总数 55→**57**（registry 实测口径）；机检 19/19 PASS fail=0；终审抽 5 件（本库 0 件），修 0 处升 v1.0.1（无）。

### R33 增量（1.10.0 → 1.11.0）

| 组件 | 版本 | 码位 |
|---|---|---|
| `FB_DL_FilmTaperTension` | v1.0.0 | 16#04_0_6C |

> R33 增量行：本库 57 → **58**；机检本库新增件全 PASS；码位全窗口独占无冲突（主控实测）。

### R34 增量（1.12.0 → 1.13.0）

| 组件 | 版本 | 码位 |
|---|---|---|
| `FB_DL_FilmTensionStepper` | v1.0.0 | 16#04_0_A0 |
| `FB_DL_TrackerAngleYearWin` | v1.0.0 | 16#04_0_A1 |

> R34 增量行：本库 1.12.0 → **60**（registry 实测口径）；机检新增件全 PASS；码位全窗口独占无冲突（主控实测 06_0_80~/03_2_00~/04_0_A0~/02_3_80）。

- **v1.14.0**（2026-11-18，R37 续作）：+LineShaftClutch（04_0_A2）、FlyingCutSync（A3）

## R39（2026-11-19）— +2（FB_DL_CamOverrideTrim / FB_DL_AxisLimitRecovery）

- 本轮增量已入册（registry v2.31.0），机检全 PASS；详见 CHANGELOG v2.31.0。

## v1.16.0 — 2026-11-19（R41 · 20 新件批次 2/3）
- 新增 4 件：FB_DL_AxisFollowErrGuard（跟随误差窗口监视）/ FB_DL_AxisOverspeedGuard（速度窗+加速度窗双判据）/ FB_DL_AxisInposGuard（到位带+驻留双判据，R240 解除式全当拍量落地）/ FB_DL_AxisAbortSafeSeq（Abort→Stop→Disable 三段迁出边齐全 + R233 成对超时纪律）；组件总数 66 → 70。
- 码位：段 0004 推进——故障 16#0004_03A8~03B3、信息 16#0004_04A8~04B3。

### v1.15.0 — 2026-11-19（R43）
- 新增组件 2 件；码位窗口 04A6~04A7 零冲突。
- 由 v1.14.0 升位，向后兼容（纯新增，无接口破坏）。

## v1.16.0 — 2026-11-19（R44 · 零检索轮）
- 新增 5 件：FB_DL_AxisBacklashComp（反向间隙补偿）/ FB_DL_AxisTorqueWatch（转矩带域+趋势斜率监视，与 TorqueLimitControl 分工：监 vs 控）/ FB_DL_AxisBrakeTest（抱闸制动测试顺控）/ FB_DL_AxisFrictionFf（静/动摩擦分段前馈）/ FB_DL_CircInterp2Axis（两轴圆弧插补，与 LineInterp2Axis 同线补口）；组件总数 72 → 77。
- 码位：派单建议窗口 04_0_A8~AC，registry 全文口径实测零冲突。
- 向后兼容（纯新增，无接口破坏）。

## v1.17.0 — 2026-11-19（R45）

- R45：+5 新件（AxisDualFeedbackGuard / AxisSs1StopSeq / AxisTeachOffset / AxisInertiaIdent / AxisRotaryShortPath）｜码位 16#0004_03B4~03B8 / 04B4~04B8


## v1.18.0 — 2026-11-19（R46）

- R46：+5 新件（AxisLoadEncoderLossMonitor / AxisEncoderPulseLostScore / AxisFeedbackFailoverSeq / GantrySkewMonitor / CamFollowerLagMonitor）｜双反馈族补口：断线监控/评分/切换序三分属主｜零码位硬编码，码位待主控统一派号｜机检 5/5 PASS
- 向后兼容（纯新增，无接口破坏）。

## v1.18.1 — 2026-11-19（R47）

- R47：+2 新件（AxisBacklashIdent / AxisCoggingFf）+ 1 返修（AxisFeedbackFailoverSeq v1.0.1）｜零码位硬编码，码位待主控统一派号｜机检 3/3 PASS
- 向后兼容（纯新增，无接口破坏）。
---

## v1.16.0 — 2026-11-20（R48）

- 新增组件 4 件：FB_DL_LoadShareDroop / FB_DL_ZoneSpeedTrim / FB_DL_ContourCrossCouple / FB_DL_LookaheadVelPlanner
- 子库组件总数：**93**（registry 实测口径）
- 机检：本轮 21/21 PASS（含 FB_DL_ModulePottingVac v1.0.1 轻返修）

## v1.17.0 — 2026-11-20（R49）

- 新增组件 5 件：FB_DL_MoveResumeSeg / FB_DL_VelFfGainIdent / FB_DL_SoftLimitCfgAudit / FB_DL_AxisLubeDistTrig / FB_DL_BrakeWearAccum
- 子库组件总数：**98**（registry 实测口径）
- 机检：本轮 20/20 PASS（增量仅扫本轮新增件）

## v2.42.0（R49 批次入册 · R50 收口，2026-11-20）
- 新增组件 5 件：FB_DL_MoveResumeSeg / FB_DL_VelFfGainIdent / FB_DL_SoftLimitCfgAudit / FB_DL_AxisLubeDistTrig / FB_DL_BrakeWearAccum
- 子库组件总数：**103**（registry v2.42.0 counts 口径）
- 机检 25/25 PASS；R50 终审本子库挂账 1 件（MoveResumeSeg 中：eResume 方向重派生翻转与边界③不符），挂账 R51 返修

## v1.17 — 2026-11-20（R52）
- 变更：+3（AxisJerkLimitCheck jerk 钳位 / AxisHomeRepeatVerify 回零重复性 / AxisSoftLimitPredict 软限位预测）；返修 MoveResumeSeg v1.0.2（注释级）
- 子库计数：**106 件**（全库 945 / v2.44.0）
- 机检：本子库本轮新增/返修件全部 PASS（audit_r52.py，22/22 全绿）

## v1.18 — 2026-11-20（R53）

- +1：FB_DL_AxisBacklashStepComp（换向首段补偿）；返修：FB_DL_AxisHomeRepeatVerify v1.0.1
- 机检：本轮 20/20 PASS（含 4 件 v1.0.1 返修）；JSONL 同步 962 条。

## R54 追加（2026-11-20，子库 v1.19）
- 新增：FB_DL_CamTableLiveTrim / FB_DL_AxisTorqueRippleWatch
- 子库存量：109 件

## v1.20 — 2026-11-21（R56 追加）
- 新增 3 件（AccelFeedforward / CantileverComp / ProbeMeasCycle）。
- 子库累计 112 件。
## v1.21 — 2026-11-21（R57 追加）
- 返修：FB_DL_AxisAccelFeedforward v1.0.1（信息级成因恢复撤销）
- 子库累计 112 件。

## v1.22 — 2026-11-21（R58 追加）
- 2 件（CamTableGenSeg / AxisSafetyStateMon）。
- 子库累计 114 件。

## v1.24 — 2026-11-21（R60 追加）
- 新增 1 件：FB_DL_AxisCmdArbiter（轴命令源优先级仲裁）
- 子库累计 118 件。

## v1.25 — 2026-11-21（R61 追加）
- 新增 2 件：AxisLimitSwitchBank / TurretToolSelect
- 子库累计 120 件。

## v1.26 — 2026-11-21（R62 追加）
- 无新件（R62 选题侧无 Motion 缺口，配额让给 T0 族补口）。
- 返修 1 件：`FB_DL_TurretToolSelect` v1.0.0 → **v1.0.1**（段 4b 统一故障迁入闸，补 `eFault` 死相位；R291 解除式可达自证）。
- 子库累计 120 件（维持）。

## v1.27 — 2026-11-22（R66 追加）

- 新增 1 件：`FB_DL_FeedOverrideRamp`（进给倍率 0~150% 钳位 + 变化率限幅 + 快速归零/恢复速率分离，PLCopen 倍率域）。
- 终审补抽 PASS（零缺陷）。
- 子库累计 121 件。

## v1.28 — 2026-11-22（R68 追加）

- 新增 1 件：`FB_DL_AxisPowerOnSelfTest`（轴上电自检五步序检：驱动就绪→编码器回读→限位巡检→故障字扫描→结论锁存；轴状态零定义，bTestOk 供 `FB_DL_SingleAxis` 使能链消费）。
- 终审就地修：v1.0.1（组态锁存解除路径可达化，原 bCfgLatch 全文件零清零 → 自检永久不可重测）。
- 节号说明（R311 实测 +1）：实测上一节为 v1.27（R66 追加），本轮取 v1.28。
- 子库累计 122 件。

## v1.29 — 2026-11-22（R69 追加）
- 新增 1 件：`FB_DL_AxisDroopComp`（跟随误差/垂度动态补偿，s7motion 借鉴 clean-room）。

## v1.24 — 2026-11-22（R70 追加）
- 新增：FB_DL_AxisSoftLimitGuard（软限位守卫）。
- 子库累计 124 件。

## v1.25 — 2026-11-23（R72 追加）

- `FB_DL_ToolChangerSeq` 入册（C3，六相换刀顺控，互锁保持相防半程掉刀；与 TurretToolSelect 分工互引）。

## v1.26 — 2026-11-23（R73）

- 新增/变更：FB_DL_FlyingSawSyncSeq / FB_DL_CamTableOnlineBlend
- L2 编译闸：PASS（RuSTy 1.0.8 串行）

## R76 · v2.68.0 · 2026-11-23
- 新增 1 件（抱闸释放互锁），本库累计 **134** 件。
- 全部经本地 RuSTy L2 真编译闸 PASS（串行 jobs=1），审校 12 项扫查 + 三道去重通过。

## R77 · v2.69.0 · 2026-11-23
- 新增 1 件（双编码器偏差监测），本库累计 **135** 件。
- 全部经本地 RuSTy L2 真编译闸 PASS（串行 jobs=1，闸席独立裁决），审校 12 项扫查 + 三道去重通过。

## R79 · v2.71.0 · 2026-11-24
- 新增 本轮无新增，本库累计 **136** 件。
- 全部经本地 RuSTy L2 真编译闸 PASS（串行 jobs=1，闸席独立裁决），审校 12 项扫查 + 三道去重通过。
