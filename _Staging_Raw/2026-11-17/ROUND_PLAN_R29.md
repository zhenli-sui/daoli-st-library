# ROUND_PLAN_R29（阶段一：盘点与锁定 20 件 → 回归 20 件/轮常态）

> 轮次：**R29** ｜ 日期：**2026-11-17** ｜ 目标：**20 件** ｜ 召唤模式：**规划线（只出派单，不写 .st）**
> 预算声明：**WebSearch 0 次（零检索轮）**；来源全部取自 ROADMAP §7 行业池未勾选项 + `SOURCE_HUNTING_MATRIX.md` 既有 ◐ 台账深化；不新开 ☐ 组。
> 本文件只读产出：ROADMAP 勾选、registry 变更、README/CHANGELOG 更新**一律不在本轮执行**。

## 0 看板（2026-11-17 实测）

| 指标 | 数值 | 说明 |
|---|---|---|
| 总库 | **500 / 10,000（5.00%）** | v2.17.0；500 里程碑已于 R28 达成 |
| 今日 | **116 / 200** | 500 计划收口后按 20 件/轮推进 |
| 距 500 差 | **0** | 已达成 → **回归 20 件/轮常态**（本轮起不再冲量） |
| 六库分布 | Base 74 / MathData 158 / Algo 53 / Device 93 / Motion 48 / Process 74 | MathData 过配，Base 池唯一候选被判同义 → 本轮 Base **0 件** |
| 源矩阵覆盖 | T0 八组全 ✔；T1 九行中 8 ◐ / 1 ✔；T2 十行中 8 ◐ | 本轮全部为 **◐ 深化**，零新开 ☐ 组 |
| 本轮码位 | 0001_047B 起 / 0002_371A 起 / 0003_03C0 起 / 0004_0340 起 / 0005_044E 起 | 每件 5 槽，见 §3 |

## 1 码位游标实测（grep 源码 + registry 双向）

| 库 | 段 | 源码 max | registry 解析 max | 本轮起点 |
|---|---|---|---|---|
| DL_MathData | 0001_ | **047A** | 047A | **047B** |
| DL_Algo | 0002_ | **3719** | 3714（R28 未回写码位，以源码为准） | **371A** |
| DL_Device | 0003_ | **03BF** | 03A6 | **03C0** |
| DL_Motion | 0004_ | **033F** | 0326 | **0340** |
| DL_Process | 0005_ | **044D** | 042F | **044E** |

> 抽查 5 个首槽字面量（`16#0001_047B` / `16#0002_371A` / `16#0003_03C0` / `16#0004_0340` / `16#0005_044E`）：源码 0 命中、registry 0 命中 → 未被占用。
> DL_Base `0001_` 段实测 max **0465**，本轮不占；若后续需 Base 件，起点 **0466**。

## 2 20 个目标总表

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_GasFlowSqrt` | DL_MathData | FC | 差压式气体流量开方 + 温压补偿（含开方死区与量程钳制） | roadmap-L645 / T1-1◐ | 3 | 1 |
| 2 | `FC_DL_CpkCalc` | DL_MathData | FC | 过程能力 Cp/Cpk/Cpl/Cpu 单点计算与判级 | 自研(SPC) / T2-8◐ | 3 | 1 |
| 3 | `FC_DL_PipeFrictionLoss` | DL_MathData | FC | 管道沿程+局部阻力压降（Darcy-Weisbach，层/湍流分流） | 自研(流体) / T1-1◐ | 4 | 1 |
| 4 | `FB_DL_CoatingThicknessCtrl` | DL_Algo | FB | 涂布面密度纯滞后闭环 + 模头间隙增量限速输出 | roadmap-L208 / T2-2◐ | 5 | 1 |
| 5 | `FB_DL_DryingOvenZone` | DL_Algo | FB | 烘箱多温区串级控温（风量联动 + 超温联锁） | roadmap-L211 / T1-1◐ | 4 | 1 |
| 6 | `FB_DL_HeatExchangerCtrl` | DL_Algo | FB | 换热器出口温度分程控制（蒸汽阀/凝水阀无缝交接） | roadmap-L307 / T1-4◐ | 4 | 2 |
| 7 | `FB_DL_CoolantLoopBal` | DL_Device | FB | 机台冷却水多支路流量均衡（阀位增量均衡，总和守恒） | roadmap-L368 / T2-1◐ | 4 | 2 |
| 8 | `FB_DL_AhuFilterDpBank` | DL_Device | FB | 空调箱过滤段压差四级分档与更换预警 | roadmap-L441 / T1-2◐ | 2 | 2 |
| 9 | `FB_DL_CoilFreezeStat` | DL_Device | FB | 盘管防冻低温时长累积判据与温降速率趋势 | roadmap-L386 / T1-2◐ | 3 | 2 |
| 10 | `FB_DL_LamDoorInterlock` | DL_Device | FB | 层压机炉门-真空-温度三联锁与首因定位 | roadmap-L476 / T2-8◐ | 4 | 2 |
| 11 | `FB_DL_FurnaceBeltTension` | DL_Device | FB | 烧结炉网带张力闭环 + 边缘跑偏纠偏限幅 | roadmap-L244 / T2-4◐ | 4 | 3 |
| 12 | `FB_DL_ScreenPrintAlign` | DL_Motion | FB | 丝印相机偏差 → 工作台 XY/θ 纠偏定位 | roadmap-L235 / T1-6◐ | 4 | 3 |
| 13 | `FB_DL_FilmSpliceTensionHold` | DL_Motion | FB | 接膜瞬间张力双回路无扰交接与保持超时 | roadmap-L380 / T1-6◐ | 4 | 3 |
| 14 | `FB_DL_TrackerMotDiag` | DL_Motion | FB | 跟踪支架回转减速机电流/跟随误差健康评分 | roadmap-L420 / T2-4◐ | 3 | 3 |
| 15 | `FB_DL_SocketPressTrend` | DL_Motion | FB | 压装压力-位移包络拐点特征与刚度判定 | roadmap-L352 / T2-7◐ | 3 | 3 |
| 16 | `FB_DL_PalletizerStation` | DL_Process | FB | 码垛整跺工站编排（分层/缠膜/出跺状态机） | roadmap-L653(P0) / T2-7◐ | 5 | 4 |
| 17 | `FB_DL_StringBarcodeTrace` | DL_Process | FB | 电池串条码绑定与工位路由（重复码拦截） | roadmap-L475(P0) / T1-4◐ | 3 | 4 |
| 18 | `FB_DL_PowderDosingLoss` | DL_Process | FB | 粉料失重秤增量式配料与落差补偿 | roadmap-L494 / T2-1◐ | 4 | 4 |
| 19 | `FB_DL_RotaryIndexModulo` | DL_Process | FB | 转盘工位索引与入料放行联锁 | roadmap-L496 / T2-7◐ | 3 | 4 |
| 20 | `FB_DL_ConveyorMetalDetect` | DL_Process | FB | 金属检测剔除联动与过检率统计 | roadmap-L830 / T2-8◐ | 3 | 4 |

## 3 与存量件的职责边界（每件一句话，防凑数变体）

1. `GasFlowSqrt` ≠ 存量 `FC_DL_FlowCompensate`（后者做温压补偿因子，不开方、不判死区）≠ 存量 `FC_DL_NthRoot`（纯数学开方，无流量语义）。
2. `CpkCalc` ≠ 存量 `FB_DL_SignalStatistics`（只给均值/标准差/极值，不出能力指数与判级）。
3. `PipeFrictionLoss` ≠ 存量 `FC_DL_FlowCompensate`（无压降几何量）≠ `FC_DL_OrificeFlowCalc`（孔板差压→流量，反向问题）。
4. `CoatingThicknessCtrl` ≠ 存量 `FB_DL_PidController`（通用 PID，不建模纯滞后、不做模头 mm 增量限速）。
5. `DryingOvenZone` ≠ 存量 `FB_DL_CascadePid`（串级骨架，无多温区矩阵、无风量联动与超温联锁）。
6. `HeatExchangerCtrl` ≠ 存量 `FB_DL_PidController`×2（分程死区与交接偏置由本件持有，双 PID 不互知）。
7. `CoolantLoopBal` ≠ 存量 `FB_DL_PidController`（支路间相对偏差闭环，非绝对设定值闭环）；与池内 `FB_DL_CoolantFlowAudit` 划界：本件**控**、后者**审**。
8. `AhuFilterDpBank` ≠ 存量 `FB_DL_SignalStatistics`（不做统计，做阈值分档 + 迟滞 + 批量汇总）。
9. `CoilFreezeStat` ≠ 存量 `FB_DL_HeatPumpDefrost`（除霜动作编排，本件只出统计判据与趋势，不驱动阀）。
10. `LamDoorInterlock` ≠ 存量 `FB_DL_GuardLockDoor`（单门解锁时序，无真空/温度域）≠ `FB_DL_InterlockMatrix`（通用矩阵，无工艺参数域与首因）。
11. `FurnaceBeltTension` ≠ 存量 `FB_DL_WindingTensionCtrl`（卷材锥度张力，无跑偏纠偏、无网带超温工况）。
12. `ScreenPrintAlign` ≠ 存量 `FB_DL_LineInterp2Axis`（插补轨迹，无视觉偏差摄入与公差判定）。
13. `FilmSpliceTensionHold` ≠ 存量 `FB_DL_WindingTensionCtrl`（稳态张力）≠ `FB_DL_RedundantSwitch`（无扰交接仅借用其思想，本件带张力爬坡与超时保护）。
14. `TrackerMotDiag` ≠ 存量 `FB_DL_SignalStatistics`（不诊断；本件做基线偏差 + 评分 + 双门限）。
15. `SocketPressTrend` ≠ 存量 `FB_DL_PressFitStation`（工站动作编排，本件只做曲线特征与包络判定）。
16. `PalletizerStation` ≠ 存量 `FB_DL_PalletizerLayerSeq`（单层排布几何，本件是整跺工站编排并复用其落点契约）。
17. `StringBarcodeTrace` ≠ 存量 `I_DL_BarcodeScanner` / `FB_DL_SerialScanner`（设备契约，本件是绑定+路由+重码策略）。
18. `PowderDosingLoss` ≠ 存量 `FB_DL_BatchDosingControl`（多料配方批控；本件只做增量失重 + 落差学习子相，输出可回喂批控件）。
19. `RotaryIndexModulo` ≠ 存量 `FB_DL_ModuloCounter`（纯计数回绕，本件带入料放行联锁与到位确认）。
20. `ConveyorMetalDetect` ≠ 存量 `FB_DL_AlarmManager`（告警聚合，本件做检出→延时剔除脉冲→过检率统计）。

## 4 查重声明（R148 新规，必做）

- 方法：对 20 个拟定名在 `C:\Library\INDEX_REGISTRY.json` **全文 grep** 一次（含 name 字段精确匹配 + 双向包含式匹配，跨子库同名一并判）。
- 结论：**20 名全量 grep 无重复 + 跨子库无同名**。首轮选取中被命中的 11 名已全部剔除并换名：

| 被剔除（已入库但 ROADMAP 勾选滞后） | 所在库 | 处置 |
|---|---|---|
| `FC_DL_OrificeFlowCalc` | DL_MathData | 弃用，改 `FC_DL_PipeFrictionLoss`（压降 vs 孔板流量，反向问题） |
| `FC_DL_WaferCountYield` | DL_MathData | 弃用，改 `FC_DL_CpkCalc`（良率折算与能力指数不同语义） |
| `FC_DL_AirDensityFanPower` | DL_Algo | 弃用，改 `FB_DL_CoatingThicknessCtrl` |
| `FB_DL_GasDensityComp` | DL_Algo | 弃用，改 `FB_DL_DryingOvenZone` |
| `FB_DL_LoopWaveInject` | DL_Algo | 弃用，改 `FB_DL_HeatExchangerCtrl` |
| `FB_DL_PumpDryRunGuard` | DL_Device | 弃用，改 `FB_DL_CoilFreezeStat` |
| `FB_DL_ChamberGateValve` | DL_Device | 弃用，改 `FB_DL_FurnaceBeltTension` |
| `FB_DL_WindingAlignEdge` | DL_Motion | 弃用，改 `FB_DL_ScreenPrintAlign` |
| `FB_DL_TrackerSnowShedAngle` | DL_Motion | 弃用，改 `FB_DL_SocketPressTrend` |
| `FB_DL_TrackBarcodeTrace` | DL_Process | 弃用，改 `FB_DL_StringBarcodeTrace`（串级追溯，非托盘级） |
| `FB_DL_NailMachineSeq` | DL_Process | 弃用，改 `FB_DL_ConveyorMetalDetect` |

- 另有 `FC_DL_AirDensity`（存量）与新名 `FC_DL_AirDensityFanPower` 曾构成包含式近同义 → 该候选整体作废，不立。

## 5 分类均衡与批次切分

**分布**：MathData **3**｜Algo **3**｜Device **5**｜Motion **4**｜Process **5**｜Base **0** = **20**。
六子库中 **5 个有新增**（≥5 满足），单库 **≤5** 满足；Base 0 件理由：池内唯一候选 `FC_DL_ShlDwordEx` 被 ROADMAP 自标「疑似与存量同义」，**不降标准入库、不凑数**。

| 批次 | 主题 | 件数 | 组件 |
|---|---|---|---|
| B1 | Level 0 数学 + 纯滞后/多区算法 | 5 | 1–3（MathData）+ 4–5（Algo） |
| B2 | 控制律 + 设备域（流体/过滤/防冻/联锁） | 5 | 6（Algo）+ 7–10（Device） |
| B3 | 设备 + 运动（张紧/对位/诊断/包络） | 5 | 11（Device）+ 12–15（Motion） |
| B4 | 工艺工站（码垛/追溯/配料/索引/剔除） | 5 | 16–20（Process） |

**T1/T2 配额**：T1-1(1,3,5)、T1-2(8,9)、T1-4(6,17)、T1-6(12,13)｜T2-1(7,18)、T2-2(4)、T2-4(11,14)、T2-7(15,16,19)、T2-8(2,10,20) → **18 件带 T1/T2 源**，2 件（2、3）为自研/规范线主源。**T2 ◐ 深化 10 件 + T1 ◐ 深化 8 件**，零新开 ☐ 组。

## 6 交付物与纪律

- 逐件引脚级契约见 `DISPATCH_R29.md`（编码专家可直接执行）。
- 来源留痕与许可证口径见 `RAW_NOTES_R29.md`。
- 本轮**不写任何 .st**、**不改 `INDEX_REGISTRY.json`**、**不改 README/CHANGELOG**、**不勾选 ROADMAP**（勾选在 R29 编码阶段收口时按 ≤10 条/轮批量执行）。

*R29 规划线 ｜ 2026-11-17 ｜ 道莅工控代码库产品总监*
