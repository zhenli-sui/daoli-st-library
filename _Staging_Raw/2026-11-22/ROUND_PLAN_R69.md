# ROUND_PLAN_R69 — 构建轮规划（阶段一：盘点与锁定目标）

> 轮次：R69 构建轮｜启动：2026-11-22 13:55｜硬顶 50 分钟｜模式：主控直跑（R335）
> 阶段一职责：盘点 + 锁定目标 + 产出本规划文件。**不写代码、不改 registry**。
> 铁律遵守：本轮只写 ROUND_PLAN_R69.md；ROADMAP 待办 57 条 ≥30 → 免补写（不追加）。

## 0. 统计口径（开工基线，主控实测口径）

| 指标 | 值 | 口径说明 |
|---|---|---|
| 总库 | **1,179 / 10,000（11.79%）** | registry v2.60.0，`total_components`=1179；counts: Base 148 / MathData 280 / Algo 134 / Device 213 / Motion 122 / Process 282，sum=1179 断言通过 |
| 今日 11-22 新增 | **44 / 200** | registry `registered_at=2026-11-22` 口径 |
| JSONL 语料 | 1,206 条（bad=0） | R68 战报口径 |
| 距 1,200 里程碑 | **差 21** | 本轮若 10 新件全注册 → 预计差 11；点修/点修升版不增计数 |
| 源矩阵覆盖变化预估 | T2-1 Converter 定宽字段族 +1（◐ 保持）｜T2-6 AOI 设备级粒度族 +1（阀/电机/夹爪 1/3）｜T2-8 ISA-18.2 报警管理族本体 ☐→◐ 开族 +1｜self-std 新增线 4 件｜T0 iec-std-wrapper 3 件（不记源矩阵台账，tag=iec-std-wrapper） | 零检索轮（WebSearch 0/3），仅用源矩阵待挖粒度 + 既有 RAW_NOTES，同源不重复收口 |

## 1. P0 编译验证硬闸结论（R195，本轮首位）

- **编译器排查结论**：`C:\Library\_tools` 全量清点（dl_gate.py / matic_manifest.py / matic_runner.py / oss_harvest.py / closeout_r6x.py）+ 系统路径探测（无 CODESYS 3.5、无 TwinCAT、无 MatIEC 本地可执行件）→ **全库当前无真实 IEC 编译器可用**。
- **裁定**：按任务书后备方案执行**增强「伪编译」抽样**——`dl_gate.py`（自研 tokenizer + 构造栈：结构语法 BLOCK/MAJOR + 红线 R1~R6 + 声明完整性 F 检，**不做类型推导**）。执行四步：① `--selftest` 判据回归先行；② 5 个点修目标文件改前基线扫描；③ 点修后单文件复检（R68 已有 9/9 PASS 先例）；④ 本轮 10 新件逐件入库即 `--file` 扫描，**17 件全覆盖优于抽样**。
- **留痕要求**：`_gate_R69.json` 与战报中**如实标注「伪编译（结构性语法级，无类型推导）」性质**，不得宣称实编译；真实编译仍挂 ROADMAP 既有「编译验证债立项」条目。
- **闸门约束执行**：本轮新件**零高复杂度编解码/数学/转换件**（3 件 T0 包装均为低复杂度，其余为设备/报警/控制/工艺族，不在禁令类别）。

## 2. 点修 7 项（批 1，P0 闸门并列首位；目标文件已逐一核实存在）

| # | 级 | 组件 | 目标文件路径（已核实 .st 在位） | 修法一句话 |
|---|---|---|---|---|
| ① | P0 | FB_DL_InterlockBypassAudit | `C:\Library\DL_Base\FB_DL_InterlockBypassAudit.st` | 迁相/回 eIdle 时同步 `bBypassOn := FALSE`，防组态故障打断旁路后修复首旁路立即到期（REVIEW_R68 M1） |
| ② | P0 | FB_DL_StretchWrapSeq | `C:\Library\DL_Process\FB_DL_StretchWrapSeq.st` | 产品裁定采纳：**eCut 切膜失败 → 报警停机待人工（新增失败码位），计次超限不自动重切**——补失败出口 + 新码位（M2） |
| ③ | P1 | FB_DL_FlowMeterKFactorDrift | `C:\Library\DL_Device\FB_DL_FlowMeterKFactorDrift.st` | 保留 eFailure 声明并实现：组态故障相补 `eHealth := eFailure`（M3，二选一裁定为"实现"） |
| ④ | P1 | FB_DL_TruckScaleSeq | `C:\Library\DL_Process\FB_DL_TruckScaleSeq.st` | `fWeight<>fWeight` 从组态闸拆出：信号失效只保持上次有效值 + 信息码，**不锁存**（M4，对齐边界披露 5） |
| ⑤ | 轻 | FB_DL_InterlockBypassAudit | 同 ① | 信息码 04B1/04B2 随解除条件回落置 FALSE（L1，与 ① 合并处理防再漏回落） |
| ⑥ | 轻 | FB_DL_RotaryAirlockCtrl | `C:\Library\DL_Device\FB_DL_RotaryAirlockCtrl.st` | `bJogRevOut` 改同拍派生（消除上拍 `bRunOut` 反相硬闸致反转首拍延后）（L2） |
| ⑦ | 轻 | FB_DL_StretchWrapSeq | 同 ② | 产品裁定采纳：**圈段压膜保持释放**口径（防膜皱），`bPreClampOut` 语义在头注释固化并对齐实现（L3） |

点修纪律：①④⑤ 升 v1.0.2；②⑦ 同文件合并一次修改升 v1.0.2；③⑥ 升 v1.0.1（R68 后首次）；全部重跑 dl_gate 单文件复检 + 逐条挂账勾销（R333 只挂账不改码条款在 R69 为有人值守规划轮，点修由后续编码阶段执行）。

## 3. 新件 10 件批次表（撞名三查已完成，见 §5）

> 配额判据（§6）：总目标 **7 点修 + 10 新件 = 17 件**，如实少报 <20，不注水。

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| N1 | FC_DL_TimeMulSat | DL_MathData | FC_DL_ | MUL_TIME 标准语义防御性实现：乘数域闸 + 溢出饱和夹 LTIME 上界，负值禁入 | iec-std-wrapper（T0） | 低 | 1 |
| N2 | FC_DL_TimeClampEx | DL_MathData | FC_DL_ | TIME 版三参 LIMIT 钳制（TIME 在部分平台无 MAX/LIMIT 定义的跨平台防御实现） | iec-std-wrapper（T0） | 低 | 1 |
| N3 | FC_DL_UdintToStringTrim | DL_MathData | FC_DL_ | UDINT→定宽十进制字段右对齐（R22 定宽字段族无符号补口：上界 4294967295 溢出语义与 DINT 版异构） | lgf-converter（T2-1 Converter 定宽字段族深化） | 低 | 1 |
| N4 | FB_DL_MotorHealthAoi | DL_Device | FB_DL_ | 电机 AOI 三分类诊断：过温/过载/启停频繁三判据各带确认延时，NE107 健康出口 | rockwell-aoi（T2-6 设备级粒度族：阀/电机/夹爪之电机） | 中 | 2 |
| N5 | FB_DL_ValveIslandDiag | DL_Device | FB_DL_ | 阀岛诊断：多阀槽位占用仲裁 + 公共供气压力监视 + 槽位失联分类码 | self-std（设备族新增线） | 中 | 2 |
| N6 | FB_DL_AlarmShelveMgmt | DL_Base | FB_DL_ | ISA-18.2 报警搁置管理状态机：申请→搁置→定时自动解除→审计留痕 | isa-18.2（T2-8 报警管理族本体，矩阵记载"待挖"） | 中 | 2 |
| N7 | FB_DL_SignalFreeze | DL_Base | FB_DL_ | 坏值冻结保持：非有限/越界输入时保持上次有效值 + 冻结时长超限告警码 | self-std（防御性新增线） | 低 | 2 |
| N8 | FB_DL_AxisDroopComp | DL_Motion | FB_DL_ | 轴跟随误差前馈补偿（按速度段补偿表折算位置前置量，与 AxisFollowErrGuard 保护件互引分工） | self-std（运动族新增线） | 中低 | 3 |
| N9 | FB_DL_CascadeCtrl | DL_Algo | FB_DL_ | 串级控制骨架：主回路输出作从回路外设定，抗积分饱和 + 从回路跟踪/切换无扰 | self-std（控制族新增线，与 ReactorJacketDeltaT 内联分程件互引分工） | 中 | 3 |
| N10 | FB_DL_CuringOvenSeq | DL_Process | FB_DL_ | 固化炉三段段序：升温速率闸 → 保温计时 → 降温开门联锁 | self-std（工艺新增线，与 DryingOvenZone 干燥分区件互引分工） | 中 | 3 |

批次依赖序：批 1 全低复杂度（3 件 wrapper 可与 7 点修并行）；批 2 中低复杂度（SignalFreeze 无外部依赖先入，AOI/阀岛/搁置各自独立）；批 3 中复杂度收尾（CascadeCtrl 可引用库内 RateLimiter/PidController 低层先例）。

## 4. 撞名三查记录（R214/R192，编码轮派单前已完成第一查）

- **精确同名查**（registry `name` 字段逐词干 grep）：N1~N10 全部 0 命中——TimeMulSat/TimeMul/TimeClamp 无占用（Time 族现有 10 件无 Mul/Clamp）；UdintToStringTrim 无占用（DintToStringTrim/LrealToStringTrim 在库，无符号变体缺位）；MotorHealthAoi/MotorDiag 0 命中；ValveIslandDiag/ValveIsland/Manifold 0 命中；AlarmShelve/Shelve/Suppress 0 命中；SignalFreeze/FreezeHold/HoldLast 0 命中；AxisDroopComp 0 命中（Droop 仅 LoadShareDroop，语义异）；CascadeCtrl/CascadeClamp 0 命中（SplitRangeControl 语义异，已在头注释分工）；CuringOven 0 命中（Oven 仅 DoorInterlock/DryingOvenZone，分工声明）。
- **同义邻件查**（语义撞名裁定）：拒单/分工声明清单——`FB_DL_HeatCurveReset`（OAT 重置）与 R68 `OutdoorTempReset` 同义 **拒**；`FB_DL_RecipeSwitchover*` 与 `FB_DL_RecipeSwitchHandover` 同义 **拒**；`FB_DL_NotchFilter` 已在库（Notch 方向弃）；`FB_DL_AxisHomingSeq` 已在库（Homing 弃）；`FB_DL_DeviceHealthArbiter` / `FB_DL_HealthStatusArbiter` 已在库（NE107 聚合已收口，弃）；`FC_DL_Atan2Ex` / `FC_DL_IntCeilDiv` / `FC_DL_StringEditDistance` / `FB_DL_FrequencyGenerator` 已在库（首轮拟案 5 件全部被拒后改选）；`FB_DL_ShutterCtrl` 与 `FB_DL_BlindPositionCtrl` 同义 **拒**；`FB_DL_AlarmShelveMgmt` 与 `FB_DL_AlarmFloodLimiter` 分工声明（限流 vs 搁置，非同义）。
- **前缀族查**：N1~N3 落 FC 定宽/饱和族（Ex/Sat 后缀按 R57 正交扫描通过）；N4~N10 均无 Ex/Sat 三后缀正交冲突。文件树查：`Glob DL_*` 无同名 .st（精确名 0 命中已覆盖）。

## 5. 配额裁决与判据（R328/R356 复核）

- R68 就地修 9 件 ≥8 → 按 R356 记族全量返修轮，新件基线 16 → 13（−20%）。
- 叠加裁减因子：50 分钟硬顶、编译闸限高复杂度、7 点修占批 1。
- **裁定：新件 10（<13）+ 点修 7 = 17 件**。判据：① 10 < 13 已体现 −20% 与硬顶折减（13→10 再砍 3 件为中复杂度挤出量）；② 10 件中 4 件低复杂度（N1/N2/N3/N7）有库内模板先例可快速成件；③ 6 件中复杂度均有直接骨架先例（AOI 三分类=CapperTorqueTrend/AhuDamperStuckDiag、搁置=InterlockBypassAudit 状态机骨架、串级=ReactorJacketDeltaT 分层、段序=CipCleaningSeq 六相骨架）；④ 不凑变体：唯一变体 N3 为无符号域溢出语义异构补口（非重收口）。若编码轮中途超时，砍件顺序：N10 → N9 → N5（如实少报，禁注水）。

## 6. 下轮（R69 编码轮）执行顺序备忘

1. `dl_gate --selftest` 回归 → 5 点修文件改前基线。
2. 批 1：7 点修（①~⑦）+ N1/N2/N3，逐件 `--file` 复检。
3. 批 2：N7 → N4 → N5 → N6。
4. 批 3：N8 → N9 → N10。
5. 收口：registry 注册（10 新件 + 点修版本/行数同步）、JSONL 语料、五件套文档（closeout 脚本增量合并，R219）、终审两式（锁存解除可达 + 整数进位点）、挂账勾销（REVIEW_R68 §4 七项逐条闭环，禁止无声消失）。

*R69 阶段一规划 ｜ 2026-11-22 ｜ 道莅工控代码库产品总监（主控直跑，零检索轮）*
