# BATTLE REPORT R27 — 道莅工控代码库第 27 轮

**轮次**：R27（2026-11-17，17:59 起）｜ **阶段**：Phase 1 第 27 轮（距 500 冲刺）
**召唤模式**：原生 `daoli-library-director` ×2 + `plc-programming-expert` ×1（三召唤全部可用，无兜底）
**本轮范围**：阶段四元数据 + 终审 + 阶段五进化 + 阶段六文档（阶段一~三由主控与编码批完成）

## 一、四批完成情况（20 件 = 19 新件 + 1 修订）

| 批次 | 内容 | 件数 | 状态 |
|---|---|---|---|
| 批 1 | DL_MathData 2（OrificeFlowCalc / WaferCountYield）+ DL_Algo 3（GasFlowSqrt / AirDensityFanPower / LoopWaveInject） | 5 | ✔ |
| 批 2 | DL_Device 5（FanArrayStageCtrl / FrostProtectFreeze / MfcFlowCtrl / DateCoderSync / SealIntegrityMonitor） | 5 | ✔ |
| 批 3 | DL_Motion 3（UnwinderDiameterCalc / StringCutAlign / StepperZLiftMicron）+ DL_Process 2（FillWeightCtrl / VffsBagLength） | 5 | ✔ |
| 批 4 | DL_Process 4（CartonErectSeq / LoadPortSeq / PumpChangeoverSeq / MachineGuardAudit）+ SplicerAutoJoint v1.0.1→v1.1.1 修订 | 5 | ✔ |

## 二、分类分布与行数（19 新件合计 3,787 行）

| 子库 | 件数 | 行数 | 组件（行数） |
|---|---|---|---|
| DL_MathData | 2 | 305 | OrificeFlowCalc(169) / WaferCountYield(136) |
| DL_Algo | 3 | 541 | GasFlowSqrt(159) / AirDensityFanPower(173) / LoopWaveInject(209) |
| DL_Device | 5 | 971 | FanArrayStageCtrl(197) / FrostProtectFreeze(214) / MfcFlowCtrl(252) / DateCoderSync(167) / SealIntegrityMonitor(141) |
| DL_Motion | 3 | 658 | UnwinderDiameterCalc(188) / StringCutAlign(208) / StepperZLiftMicron(262) |
| DL_Process | 6 | 1,312 | FillWeightCtrl(287) / VffsBagLength(218) / CartonErectSeq(201) / LoadPortSeq(224) / PumpChangeoverSeq(212) / MachineGuardAudit(170) |
| **合计** | **19** | **3,787** | 另 `FB_DL_SplicerAutoJoint` v1.1.0→**v1.1.1**(427 行)；**全批 4,214 行**（入库初值 4,186，终审修复 +28） |

## 三、机检与码位台账

`check_r27.py` **20/20 PASS，fail=0**，轮内重复 0、跨库撞车 0（CLASH=NONE），码位 100，含 R132 TYPE 块种类校验；终审修复后重跑仍 **20/20 PASS**（files=20，codes=100，lines=4,214）。

| 子库 | 码段 | 件数 |
|---|---|---|
| DL_MathData | `16#0001_0471~047A` | 2 |
| DL_Algo | `16#0002_3706~3714` | 3 |
| DL_Device | `16#0003_038E~03A6` | 5 |
| DL_Motion | `16#0004_0318~0326` | 3 |
| DL_Process | `16#0005_0412~042F` | 6 |
| SplicerAutoJoint | 沿用旧码 `0351/0352/0353/040A/040B`（新增 `bSyncTimeout` 复用 0351 段） | 1 修订 |

## 四、终审（4 抽 → 2 修 2 过）

| 组件 | 结论 | 要点 |
|---|---|---|
| `FB_DL_MfcFlowCtrl` | **修 v1.0.1** | 峰值初值取当前回读 → 降设定（20→10 slm）时 `20−10 > 超调阈` 必误报 039A；改为「首次入窗后累积 + 初值取设定」，引脚零变更 |
| `FB_DL_SplicerAutoJoint` | **修 v1.1.1** | 看门狗 `IN = eSyncWait AND NOT bSpeedWithin`，速度差在容差边界抖动时与保持计时器交替复位、两者永不完成 → 相内无限滞留；改为按相驻留计时 |
| `FB_DL_FillWeightCtrl` | **修 v1.0.1** | 互斥与「学习仅完成相」两项 PASS；另发现超重容器被归入 bWeightOk 后转细灌继续加注，改为超重即刻中止（系数提为常量去魔法数） |
| `FB_DL_LoadPortSeq` | **PASS** | 七相顺位单调、仅 Reset 可退出；两表均 `ARRAY[1..25]`、循环界取常量 1/25，无越界；差异只计数不中断，非零走拒收相而非故障相 |

**验证方式**：每件做「向量之外」推演——方向反转（设定下行）、边界抖动（速度差在容差上下逐拍跳）、域端点（0 / 负值 / 25 位全 0 与单位差），并复算验收向量；修复后重跑机检确认无回归。

## 五、源覆盖与合规

T1 族：**T1-2**（OSCAT Building 滞环与轮值纪律，零复制）、T1-5（TcOpen 设备抽象引脚范式）、T1-6（PLCopen 在位确认纪律）、T1-8（步进当量组态）。
T2 族：**T2-7**（PackML 色标同步 / Holding·Held 相语义，clean-room）、T2-8（ISA-88 参数窗、SEMI 对接握手语义）。
T0 快车道 5 件公式为公有领域物理语义，零代码行复制；19 件全部可商用，无 GPL/AGPL 接触，无加密狗绑定。

## 六、账本与文档

- 专家进化新增 **9 条**：PLC 线 `R144~R147`（4 条）+ 总监线 `R139~R143`（5 条），游标推进至 **R148**。
- 文档增量：`README.md`（徽章 464→483，追加 3 行）｜ `CHANGELOG.md`（v2.16.0，9 行）｜ 五本 MANUAL 各追加「R27 新增接口表」（共 19 行）｜ `AGENT_EVOLUTION_LOG.md`（R27 节 8 行）｜ `ROADMAP.md`（勾选 10 条，余 9 条 R28 批量勾选）。
- **固化延期**：R139~R147 共 9 条**延期至 R28**，原因：本轮 50 分钟预算令；已在 PLC 账本顶部「未固化轮次数」记 **4 轮**（R24/R25-RESUME/R26/R27）。

## 七、数字总览

| 指标 | 值 |
|---|---|
| 总库 | **483 / 10,000**（4.83%），距 500 里程碑 **差 17 件** |
| 今日 | **99 / 200**（80 + 19 新件；Splicer 为修订不计数） |
| 本轮入库 | 19 新件 + 1 修订，4,214 行 |
| registry / JSONL | 483 / 483 条（版本 v2.16.0） |
| 机检 | 20/20 PASS，fail=0，CLASH=NONE |

## 八、风险与下轮计划

**风险一句话**：本轮两处缺陷同属「正常向量全绿、异常路径泄漏」，说明现有验收向量仍是上行/稳态口径；若 R28 不补「方向反转 + 边界抖动」向量模板，同类缺陷会按批次复发。
**R28 计划**：① 固化优先——R139~R147 合并进 `daoli-st-standard`（判据类先落契约文件，去重去矛盾），清零未固化计数；② 冲 500——17 件，先补齐六库 VERSION/MANUAL 的 R26 批次欠账（R138 债务显式化）；③ 编译验证债连欠 23 轮，必须启动一次全库语法级核验（TYPE 块种类 + END_\* 配对 + POU 名 = 文件名）。
