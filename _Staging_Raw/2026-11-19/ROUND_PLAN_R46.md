# R46 阶段一目标锁定（20 件）

生成：2026-11-19 ｜ 基线：总库 805 / 10,000 ｜ 今日 135/200 ｜ 游标 R294
来源依据：`INDEX_REGISTRY.json`（v2.37.0, total_components=805）+ `ROADMAP.md`（空勾 75 / 已勾 483）+ `SOURCE_HUNTING_MATRIX.md`（◐ 深化组）+ `CONSISTENCY_R46.md`（B 类真缺口 52 条）

## 0. 选题纪律声明

- **零同名反证**：下列 20 名全部对 `INDEX_REGISTRY.json` 的 `components[].name` 做归一化全等 grep，**零命中**（反证句逐条附于表内）。
- **同义邻件双查（R28）**：候选池 33 名中剔除 13 名——4 名精确撞名（`FB_DL_KalmanFilter1D`、`FB_DL_GainSchedPid`、`FB_DL_BumplessTransfer`、`FC_DL_Crc16Ccitt`）、1 名同义邻件（`FB_DL_NotchFilterAdaptive` ← 邻件 `FB_DL_NotchFilter`）、2 名精确撞名（`FB_DL_RelayAutoTune`、`FB_DL_CrossCorrelationDelay`）、6 名主动弃选（`FB_DL_DeadTimeEstimator` 与 `FB_DL_CrossCorrelationDelay` 目标同源、语义重叠，按「同一物理量只准一件属主」弃选；`FB_DL_VacuumPumpDiag`/`FB_DL_EncoderAbsReader`/`FB_DL_TrayLoadVacuum`/`FB_DL_TrayerNestingCtrl`/`FC_DL_ArrayMedianFilt`/`FB_DL_FuzzyPidAssist` 本轮让位配额）。
- **品类纠偏**：MathData 仅 2 件（上限达标）；Motion 5 件含双反馈族补口 3 件。
- **批次约束**：4 批 × 5 件，同批内无 `.st` 文件级依赖（`AxisFeedbackFailoverSeq` 消费 `AxisLoadEncoderLossMonitor` 的断线标志，故二者分置 B1 / B2）。

## 1. 20 件目标清单

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | `FB_DL_AxisLoadEncoderLossMonitor` | DL_Motion | FB | 负载侧编码器断线/失步**独立**监控（不依赖电机侧反馈，单侧可用），输出断线锁存与可信度 | T2-4 S7 Motion ◐ + ROADMAP P1 双反馈族补口 | 6 | 1 |
| 2 | `FB_DL_AxisEncoderPulseLostScore` | DL_Motion | FB | 编码器脉冲丢失率在线评分（按速度窗归一 + 滑动窗口打分，分档预警/故障） | T1-6 PLCopen ◐ 深化 | 5 | 1 |
| 3 | `FC_DL_IntCeilDiv` | DL_Base | FC | 整数向上取整除法（`TRUNC+1` 缺陷写法规避，零除/负数/同余四向量自证） | T0 防御包装 | 2 | 1 |
| 4 | `FB_DL_WatchdogPulseMon` | DL_Base | FB | 外部看门狗脉冲监视（脉冲沿超时判死、恢复确认窗、拒单拍抖动） | T1-7 PLCnext ◐ 深化 | 3 | 1 |
| 5 | `FC_DL_StdDevOnline` | DL_MathData | FC | 在线标准差（Welford 单遍增量，免二次遍历与灾难性相消，非有限样本剔除） | T2-1 LGF · Measurement ◐ 深化 | 4 | 1 |
| 6 | `FB_DL_AxisFeedbackFailoverSeq` | DL_Motion | FB | 主反馈失效→电机侧降级切换序（切换先停后切、切换期禁新运动、不可静默降级） | ROADMAP P1 双反馈族补口 + T2-4 ◐ | 7 | 2 |
| 7 | `FB_DL_GantrySkewMonitor` | DL_Motion | FB | 龙门双侧位置偏斜监控（偏斜量/偏斜角双出口 + 调平超时判据） | T1-6 PLCopen ◐（GantrySyncAxis 族补口） | 5 | 2 |
| 8 | `FB_DL_StribeckFrictionComp` | DL_Algo | FB | Stribeck 摩擦补偿（静/库仑/黏滞三段 + 速度过零区平滑过渡防抖） | T2-1 LGF · Technology ◐ 深化 | 6 | 2 |
| 9 | `FB_DL_LoadCellTareDrift` | DL_Device | FB | 称重传感器零点漂移监视与自动去皮闸（空载判定 + 漂移速率限 + 拒绝带料去皮） | T2-2 LBP ◐ 深化 | 5 | 2 |
| 10 | `FB_DL_TabWeldingMonitor` | DL_Process | FB | 极耳焊接过程监控（能量/位移/压力三包络窗口判定 + NG 分型） | ROADMAP B 类真缺口（T2-8 NE107 出口） | 7 | 2 |
| 11 | `FB_DL_CamFollowerLagMonitor` | DL_Motion | FB | 凸轮从动轴跟随滞后监控（相位-位置双偏差、超差确认窗、脱离/咬合边界识别） | T1-6 PLCopen ◐（CamProfile 族深化） | 6 | 3 |
| 12 | `FB_DL_LuenbergerObserver` | DL_Algo | FB | 离散 Luenberger 状态观测器（观测增益注入 + 收敛判据 + 非有限观测拒绝发布） | 自研线（模型基补偿） | 7 | 3 |
| 13 | `FB_DL_TcChannelScanDiag` | DL_Device | FB | 多路热电偶通道扫描诊断（断偶/反接/漂移三判据 + 通道故障掩码只读出口） | T2-6 Rockwell AOI ◐ 深化 | 6 | 3 |
| 14 | `FB_DL_CellSortingBin` | DL_Process | FB | 电池片分选落料（效率/色差分档 + 料仓满溢调度 + 混档拦截） | ROADMAP B 类真缺口 | 6 | 3 |
| 15 | `FC_DL_MedianAbsDev` | DL_MathData | FC | 中位绝对偏差 MAD（鲁棒离散度，拷贝排序不改入参，非有限样本前置剔除） | T2-1 LGF · Measurement ◐ 深化 | 3 | 3 |
| 16 | `FB_DL_RlsEstimator` | DL_Algo | FB | 递推最小二乘在线参数估计（遗忘因子 + 协方差自增防锁死 + 激励不足拒估） | 自研线（自适应前馈底座） | 8 | 4 |
| 17 | `FB_DL_AdaptiveLeadLag` | DL_Algo | FB | 自适应超前-滞后补偿（相位补偿量随速度调度、限幅与切换无扰） | T2-1 LGF · Technology ◐ 深化 | 6 | 4 |
| 18 | `FB_DL_GripperForceVerify` | DL_Device | FB | 夹爪夹持力校验（力窗判定 + 空夹/滑脱/超力三分类 + 确认窗） | T2-6 Rockwell AOI ◐ 深化 | 5 | 4 |
| 19 | `FB_DL_ModulePottingVac` | DL_Process | FB | 模组灌胶真空脱泡顺控（抽真空-灌注-保压-释放四相 + 真空度终点判据） | ROADMAP B 类真缺口 + T2-8 相语义 | 7 | 4 |
| 20 | `FB_DL_PackHousingTighten` | DL_Process | FB | Pack 箱体螺栓拧紧轴序管理（对角顺序 + 扭矩/角度窗口 + 漏拧追溯） | ROADMAP B 类真缺口 + T2-2 LBP | 6 | 4 |

## 2. 零同名反证句（逐条，grep `components[].name` 归一化全等）

1. `FB_DL_AxisLoadEncoderLossMonitor` — grep name 零命中（全库无 `*EncoderLoss*`，最近邻 `FB_DL_ExternalEncoderLatch` 语义不同：锁存 ≠ 断线监控）。
2. `FB_DL_AxisEncoderPulseLostScore` — grep name 零命中（无 `*PulseLost*`）。
3. `FC_DL_IntCeilDiv` — grep name 零命中（无 `*CeilDiv*`，与 `FC_DL_IntToFixedField` 无关）。
4. `FB_DL_WatchdogPulseMon` — grep name 零命中（无 `*Watchdog*`）。
5. `FC_DL_StdDevOnline` — grep name 零命中（无 `*StdDev*`；`FB_DL_SignalStatistics` 为多统计量聚合块，本件为单量原子 FC，不重复属主）。
6. `FB_DL_AxisFeedbackFailoverSeq` — grep name 零命中（`AxisDualFeedbackGuard` 只做偏差校核、不切源，职责不重叠）。
7. `FB_DL_GantrySkewMonitor` — grep name 零命中（`FB_DL_GantrySyncAxis` 做同步控制，本件只做偏斜监视）。
8. `FB_DL_StribeckFrictionComp` — grep name 零命中（`FB_DL_AxisFrictionFf` 为轴级前馈注入件，本件为摩擦模型本体，须在 ROUND 内声明属主边界）。
9. `FB_DL_LoadCellTareDrift` — grep name 零命中（无 `*Tare*`）。
10. `FB_DL_TabWeldingMonitor` — grep name 零命中；且为 ROADMAP B 类清单首条（已反查未注册）。
11. `FB_DL_CamFollowerLagMonitor` — grep name 零命中（`FB_DL_ElectronicCam`/`CamPhaseTrim` 均无滞后监控职责）。
12. `FB_DL_LuenbergerObserver` — grep name 零命中（无 `*Observer*`）。
13. `FB_DL_TcChannelScanDiag` — grep name 零命中（`FB_DL_NtcTempScan` 为 NTC 阻值族，热电偶断偶判据不同，不合并）。
14. `FB_DL_CellSortingBin` — grep name 零命中；ROADMAP B 类清单条目。
15. `FC_DL_MedianAbsDev` — grep name 零命中（`FB_DL_MedianFilter` 为滤波执行件，本件为离散度统计量）。
16. `FB_DL_RlsEstimator` — grep name 零命中（`FB_DL_AxisInertiaIdent` 为一次性惯量辨识，本件为在线递推多参数）。
17. `FB_DL_AdaptiveLeadLag` — grep name 零命中（`FB_DL_FeedforwardComp`/`SmithPredictor` 均非超前滞后族）。
18. `FB_DL_GripperForceVerify` — grep name 零命中（无 `*Gripper*`）。
19. `FB_DL_ModulePottingVac` — grep name 零命中；ROADMAP B 类清单条目。
20. `FB_DL_PackHousingTighten` — grep name 零命中；ROADMAP B 类清单条目。

## 3. 批次依赖自检

| 批次 | 件数 | 内部依赖 | 结论 |
|---|---|---|---|
| B1 | 5 | 无（全为叶子件，仅依赖 `Standard.library`） | 可并行派单 |
| B2 | 5 | 无（`FeedbackFailoverSeq` 仅经 `VAR_INPUT` 吃 B1 的断线标志，源码不引用 B1 文件） | 可并行派单 |
| B3 | 5 | 无 | 可并行派单 |
| B4 | 5 | 无（`RlsEstimator` 与 `AdaptiveLeadLag` 为并列件，不互相引用） | 可并行派单 |

## 4. 分布核验

Motion 5 / Algo 4 / Device 3 / Process 4 / Base 2 / MathData 2 = **20**，满足「Motion≥5、Algo≥4、Device≥3、Process≥4、Base≥2、MathData≤2」全部约束。
