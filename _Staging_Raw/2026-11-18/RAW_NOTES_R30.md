# RAW_NOTES_R30 —— R30 规划轮原始留痕（2026-11-18）

## 1. 零检索声明

本轮规划 **WebSearch 使用次数 = 0**（配额上限 2 次未动用）。理由：① 返修件 FB_DL_AhuFilterDpBank 已有 R29 终审裁定方案（`_Staging_Raw/2026-11-17/REJECTED_R29/HOLD_REASON_R29.txt`：共享单实例 tonDeb → `ARRAY[1..4] OF TON` 每周期无条件刷新）；② ROADMAP 未勾选条目实测甄别后真实空位待办 233 条，选题池充足。全部选题依据 ROADMAP 条目与 `SOURCE_HUNTING_MATRIX.md` 台账「仍待挖」子项，零外部检索。

## 2. 返修件来源留痕

- 原始隔离件：`C:/Library/_Staging_Raw/2026-11-17/REJECTED_R29/FB_DL_AhuFilterDpBank.st`（220 行，R29 序 8 派单产物，按 DISPATCH_R29 编码）。
- 隔离原因：`HOLD_REASON_R29.txt`——红线 7/R40 复合：共享单实例 `tonDeb` 被 4 温区复用 + 仅 `eTarget<>aeStage` 时刷新（无变化周期 ET 冻结、跨区互相复位）。
- 该件从未注册进 `INDEX_REGISTRY.json`（实测 grep NONE）、从未入语料、码位 03C5~03C9 从未生效。R30 按 **v1.0.0 新件**入册，码位改用实测游标 03D9 起的新块 03D9~03DD；原 03C5~03C9 作废不回收（03C5~03D8 已被 R29 在册件合法占用，实测 distinct 394 码最大 03D8）。
- 返修要点固化进 ROUND_PLAN_R30 §1/§3 序 1：`aTonDeb:ARRAY[1..4] OF TON`，FOR 循环体每拍无条件刷新 4 实例，候选作废分支 `IN:=FALSE` 显式复位。

## 3. 码位实测原始数据（python 全库正则扫描，R61/R105）

扫描对象：`C:/Library/DL_*/*.st` 全部 519 件；模式 `16#000[1-5]_[0-9A-Fa-f]{4}`；剔除非错误码样例 `16#0002_8011`（`FB_DL_PdiReadScheduler.st` 注释中的 PDI 打包示例：错误码 16#8011 + 段号 16#0002 拼装值，非 eErr 码）。

| 段 | 目录 | 剔除后 trueMax | 码数 | 下游游标 |
|---|---|---|---|---|
| 0001 | DL_Base | 0465 | 163 | 共享段取两者最大 |
| 0001 | DL_MathData | 0489 | 574 | → 048A |
| 0002 | DL_Algo | 3728 | 224 | → 3729 |
| 0003 | DL_Device | 03D8 | 395 | → 03D9 |
| 0004 | DL_Motion | 0353 | 267 | → 0354 |
| 0005 | DL_Process | 0466 | 417 | → 0467 |

- 交叉引用核实：其他目录注释中出现的 0001/0002 码均为跨件引用说明，非本目录占用；段-目录对齐无泄漏。
- Process 段实测：信息级与故障级已全部位于 04xx（0400~0466），交接参考所述「Process 信息码 01xx 仅余 2 码、须迁 04xx」**已在历史轮完成迁移**，本轮新件按既有 04xx 惯例续排，无迁移动作。
- 交接参考数字（0001 信息 046F/故障 03BD、0002 CC 0x33、0003 信息 0190/故障 0369、0004 信息 01EB/故障 030C、0005 信息 01FD）实测全部过时（R29 收口后游标前移），以 ROUND_PLAN_R30 §5 实测表为准。

## 4. 选题过程留痕（选题双查实录）

1. 初选命中的 ROADMAP P0/P1 条目实测已被占用（勾选框滞后），全部改判绕开：`FB_DL_ChamberGateValve`、`FB_DL_PumpDryRunGuard`、`FB_DL_LamDoorInterlock`、`FB_DL_TrackBarcodeTrace`、`FB_DL_RotaryIndexModulo`、`FB_DL_PowderDosingLoss`、`FB_DL_WindingAlignEdge`、`FB_DL_SolderRibbonTension`、`FB_DL_LoopWaveInject`、`FC_DL_OrificeFlowCalc`、`FC_DL_WaferCountYield`、`FC_DL_AirDensityFanPower` 等（全量 150 条滞后见 ROUND_PLAN_R30 §6.2）。
2. 实测统计：ROADMAP 未勾选条目名 287 个 → 其中 150 个已注册+落盘（滞后虚账）→ 真实空位 233 条。
3. Motion 段 P0/P1 空位为 0（P1 两条已滞后入库），本轮 Motion 3 件全部取 P2 空位（TrackerBacktrackCalc/LamStepperFeed/ElectrodeRollDiameter），如实申报。
4. Base 空位唯一候选 `FC_DL_ShlDwordEx/ShrDwordEx` 自挂「疑似与存量同义，立项前必过 R61」条款——实测 ShlEx/ShrEx 通用命名件已存在，判不立；Base 改取源矩阵台账 T2-1 LGF Bit Logic 行明文待挖子项「多段一次搬」→ `FC_DL_BitArraySegCopy`。
5. MathData 空位仅剩源矩阵 Data Handling 行待挖子项「LWORD 累加和」→ `FC_DL_ChecksumSum64`；「CRC-16 反射」判为已被 `FC_DL_Crc16Generic` 参数化覆盖，不立。
6. Algo 空位 P1 = R25 增补暖通补位 2 件（`FB_DL_FanArraySeq`、`FB_DL_ChwDifferentialPressure`）全取；`FB_DL_ChwDifferentialPressureReset`（L837）同义并案处理（见 ROUND_PLAN_R30 §6.3）。
7. 依赖存在性核验：20 件全部依赖件（I_DL_BarcodeScanner、FB_DL_PdiReadScheduler、FB_DL_AxiolineDiagLatch、FB_DL_AndonCallSystem、FB_DL_FanArrayStageCtrl、FB_DL_MovingAverage、FB_DL_EventCounter、FB_DL_WindingTraverse、FB_DL_MonthWindowCheck、FC_DL_IntervalMembership 等 30+ 项）逐一实测在册，零缺失依赖。
8. 枚举属主核实：registry 无任何 `E_DL_*` 独立条目（枚举随件同文件定义惯例），序 1 复用 R29 隔离件内 `E_DL_FilterStage` 定义、序 9/11 共享 `E_DL_WeightClass`（定义于序 9 文件，序 11 引用注明属主）。

## 5. 遗留移交

- ROADMAP 150 条勾选框滞后 → 收口轮批量回写（建议脚本化勾选回写 + registry 双向对账断言）。
- `FB_DL_SplicerAutoJoint` 同步相超时（R25 P0 修复）、`eFault` 枚举 CASE 标签 6 件清理（R25 P0）均为**存量修复任务**不占本轮 20 新件配额，保持挂账，建议 R31 P0 前置。
- 本轮规划轮零代码写入 `DL_*` 正式目录，符合「_Staging_Raw 只备份溯源、永不交付」红线。
