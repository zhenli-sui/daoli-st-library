# ROUND_PLAN_R66 — 规划派单（2026-11-22 02:20，硬顶 50 min / 规划限 12 min）

> 配额：固定 **10 新件**（R309 分流配额线 + R64/R65 惯例；对用户 20 目标如实少报）。
> 约束：零 WebSearch（源全部取自源矩阵既有 ◐ 行与 T0 维护模式族内余量）；不改 INDEX_REGISTRY / JSONL / 任何 .st。
> T0：八组维持 8/8 ✔（余量 0），本轮 **T0 = 0**，不硬凑（R278 维护模式）。
> 族避让：R60 曾记 Algo/Process 拒单重灾；R61 已让位轮，本轮 Process 控 2 件、Algo 0 件（BilinearInterp/QuadPolyFit 等数值件入 MathData 不入 Algo），分布 Base 2 / MathData 4 / Device 1 / Motion 1 / Process 2 / Algo 0。

## 1. 目标清单（10 新件，批次按依赖切 3 批）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FC_DL_HammingDist | DL_Base | FC_ | LWORD 两位串汉明距离（逐位异或 + 1 计数，配方/位配置比对） | t2-1-lgf-bitlogic ◐ | 3 | 1 |
| 2 | FB_DL_DutyCycleMeasure | DL_Base | FB_ | BOOL 信号周期 + 占空比在线测量（两沿计时，频率发生器的反向件） | t2-1-lgf-measurement ◐ | 5 | 1 |
| 3 | FC_DL_CircularMeanCalc | DL_MathData | FC_ | 角度循环均值（Σsin/Σcos 向量合成，跨 0°/360° 不穿越） | t2-1-lgf-measurement ◐（统计子族） | 4 | 1 |
| 4 | FC_DL_WeekNumIsoCalc | DL_MathData | FC_ | ISO 8601 周号计算（日历族补口，邻件 DayOfWeekCalc/LeapYearChk） | t2-1-lgf-dateandtimer ◐ | 5 | 1 |
| 5 | FC_DL_BilinearInterp | DL_MathData | FC_ | 2D 等距表双线性插值（四角加权 + 边界钳位，LGF 2D 表补口） | t2-1-lgf-math ◐ | 6 | 2 |
| 6 | FC_DL_QuadPolyFit | DL_MathData | FC_ | 二次多项式最小二乘拟合（3×3 正规方程 + 条件数判据） | t2-1-lgf-math ◐（回归族开件） | 7 | 2 |
| 7 | FB_DL_AnalogOutFailsafe | DL_Device | FB_ | 模拟量输出故障安全（看门狗/使能丢失 → 冻结或安全值二选一 + 回程斜坡） | t2-8-ne43 ◐（输出侧反演）+ self | 6 | 2 |
| 8 | FB_DL_FeedOverrideRamp | DL_Motion | FB_ | 进给倍率处理（0~150% 钳位 + 倍率变化率限幅 + 快速归零与恢复速率分离） | t1-6-plcopen ◐ | 6 | 3 |
| 9 | FB_DL_LotMergeGate | DL_Process | FB_ | 批次合并放行闸（N 批齐套/数量累计到位放行，支持退回与部分放行） | t2-8-isa88 ◐ + roadmap | 7 | 3 |
| 10 | FB_DL_TaktPaceMonitor | DL_Process | FB_ | 目标节拍偏差监视（目标节拍 vs 实测节拍 EWMA + 累计欠产台账） | self-std（ISO 22400-2 公开口径） | 6 | 3 |

## 2. 撞名三查记录（精确名 + 语义同义 + Ex 后缀族正交扫描，存量 1,145 件全扫）

### 2.1 立项件三查结果
- 10 件精确名均零命中；同义邻件逐一声明正交（编码时须写死互引）：
  - HammingDist ↔ `FC_DL_ReverseBitsLword/Word`（位反转）正交；
  - DutyCycleMeasure ↔ `FB_DL_FrequencyGenerator`（发生）/`FC_DL_PeriodJitterCalc`（抖动统计）正交（测量）；
  - BilinearInterp ↔ `FC_DL_InterpolateTable3D`（三线性 3D 表）正交（2D 平面表，LGF 同族分档惯例）；
  - QuadPolyFit ↔ `FC_DL_LinearRegression2Var`（一元线性）正交（二次拟合）；
  - AnalogOutFailsafe ↔ `I_DL_AnalogSensor/FB_DL_AnalogTransmitter/FB_DL_AnalogSignalHealth`（全部输入侧）正交（输出侧）；
  - FeedOverrideRamp ↔ `FB_DL_RateLimiter`（通用斜坡原子）与 `FB_DL_OverrideSelector`（倍率源选择）正交（倍率域钳位+斜坡）；
  - TaktPaceMonitor ↔ `FB_DL_CycleTimeMeasure`（单件节拍测量）与 `FB_DL_OeeCalculator`（OEE 聚合）正交（目标偏差+欠产）。

### 2.2 撞名拒单 15 条（留痕，下轮候选池不可复活）
`FC_DL_Crc8PolyParam`（FC_DL_Crc8 已存）｜`FC_DL_GrayCodeConvert`（BinaryToGray/GrayToBinary 已存）｜`FC_DL_ByteBitReverse`（ReverseBitsWord/Lword 已存）｜`FB_DL_Median3Filter`（FB_DL_MedianFilter 已存）｜`FC_DL_QuartileCalc`（QuantileCalc 已存，拆件即凑数）｜`FB_DL_SolarSunPosCalc`（FC_DL_SolarPositionCalc 已存）｜`FB_DL_MotorPtcChainMon`（FB_DL_MotorPtcThermistProtect 已存）｜`FB_DL_VacCupLeakLocate`（FB_DL_VacCupRingCtrl 已存）｜`FB_DL_PumpSoftStartSeq`（FB_DL_SoftStarterDrive 已存）｜`FB_DL_AxisJogInching`（FB_DL_AxisJogController 已存）｜`FB_DL_SmithDeadTimeComp`（FB_DL_SmithPredictor 已存）｜`FB_DL_LoopSplitRangeCtrl`（FB_DL_SplitRangeControl 已存）｜`FB_DL_SensorStuckWatch`（FB_DL_AnalogSignalHealth 卡滞已含）｜`FB_DL_ToolLifeCycCounter`（FB_DL_ToolLifeBudget 已存）｜`FB_DL_SignalPeakEnvelope`（PeakDetector 已存，同义）。

### 2.3 备胎 2 件（拒单/失败时按序顶替）
1. `FB_DL_SensorWarmupMask`（DL_Device）：传感器上电预热掩蔽（预热窗内屏蔽报警 + 域闸），来源 self-std；
2. `FB_DL_LotSplitGate`（DL_Process）：批次拆批分流闸（与 LotMergeGate 同源组，只许二选一）。

## 3. 「采集队列冷启动」评估（oss_harvest.py + _harvest_manifest.json）

- 脚本链路完整（GitHub 检索→许可分级→三道去重→候选队列），manifest 显示 2026-11-21 23:27 试跑一次：**2 秒结束、repos 空、added 0**——匿名 API 检索在当前网络环境无产出，属低效但不致命。
- 结论：**不建议 R67 直接批量启用**；建议 R67 先加 GITHUB_TOKEN 注入 + 以 `--repo TcOpen/TcOpen --max-files 40` 单仓定向试跑验证抓取链路，链路通再批量（预计单次批量可拉 20~50 候选名）。
- 本轮不阻塞：选题继续走源矩阵 ◐ 组与 self 线，队列冷启动失败不构成产出缺口。

## 4. 留痕

GATE MAJOR 存量人核 + MatIEC CI 裁决：属值守轮事项，本轮不执行。

*R66 规划线 ｜ 2026-11-22 02:20 ｜ 道莅工控代码库产品总监*
