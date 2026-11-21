# ROUND_PLAN_R39 — 第 39 轮阶段一派单（20 新件 + 3 P0 返修）

读完即落盘

> **轮次**：R39（常态化轮，零检索轮，WebSearch 0 次）
> **编制**：2026-11-19 01:48 道莅工控代码库产品总监（阶段一：盘点与锁定；不写 `.st`、不改 `INDEX_REGISTRY.json`、不改 JSONL）
> **来源策略**：本轮零 WebSearch，100% 复用 `SOURCE_HUNTING_MATRIX.md` 既有 ☐/◐ 行「待挖」子项与 `ROADMAP.md` 未勾真缺口（详见 `RAW_NOTES_R39.md`）。
> **衔接 R38**：3 件终审挂账返修（P0 首位，缺陷已带行号）+ 机检 R228 两条新规则（先在 3 返修件回归、再上 20 新件）。

---

## 0 统计快照（实测 `INDEX_REGISTRY.json` v? + 磁盘 670 个 `.st` + `ROADMAP.md`）

| 口径 | 数值 | 实测方式 |
|---|---|---|
| 总库已注册 | **670 / 10,000（6.70%）** | `total_components`=670 = `components[]` 长度 = 磁盘 `.st` 670，三向一致 ✅ |
| 今日（2026-11-19）已入册 | **0 / 200** | `registered_at` 前缀 `2026-11-19` 聚合实测（昨日 11-18 = 151/200） |
| 距 500 件计划 | **已达成 +170** | 670 − 500 |
| 距下一里程碑（1,000） | 330 件 | — |
| 子库分布 | Base **77** ｜ MathData **178** ｜ Algo **67** ｜ Device **133** ｜ Motion **64** ｜ Process **151** | `registry.counts` 实测，合计 670 |
| 源矩阵覆盖率 | 台账 **34 行**：✔ **9**（T0-1~T0-8 + T1-3）/ ◐ **25** / ☐ **0** | 已开组率 34/34 = 100%；全收口率 9/34 ≈ 26.5% |
| ROADMAP 未勾条目 | **172 条**（`-\ \[ \]` 计数；已勾 399） | 正则实测；未勾中名称已注册伪缺口 **134**、真缺口 **120**（剔除 `FB_DL_Hysteresis` 依赖误写、`E_DL_ByteOrder` 枚举、`FC_DL_ShlDwordEx/ShrDwordEx` R34 弃判、`FB_DL_GlassFeederAccum` R38 判弃后净可用 ≈115） |
| `code_segment` 字段 | **530 / 670** 有值 | 已不可作占位依据的字段比例大幅收窄，但本轮仍以头部+全文正则实测为准（R217） |
| 本轮目标 | **+20 新件 → 690 / 10,000**（另 3 件返修不占名额） | — |

**分布口径**：参考 R38 分布（Base 2/MathData 2/Algo 3/Motion 2/Device 5/Process 6）微调为 **Base 1 / MathData 2 / Algo 3 / Motion 2 / Device 5 / Process 7** —— DL_Base 真池经词干实测已高度饱和（`PulseStretch`/`WatchdogMonitor`/`EdgeDivider`/`GrayToBinary`/`BinaryToGray`/`BumplessTransfer`/`GainScheduler` 等候选全部在册），按「宁少勿滥」只立 1 件有明确矩阵待挖依据的件，名额转给 Process 真缺口（未勾真缺口 120 条中 Process 占比最高）。**未凑数**：本表 20 件逐件经 registry name 精确查 + 词干同义双查 + 依赖存在性查，判弃记录见 §5。

---

## 1 目标清单（20 件，批次自底向上）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能（含差异化判据） | 来源标签 | 复杂度 | 批次 | 码位 |
|---|---|---|---|---|---|---|---|---|
| 1 | `FB_DL_MutexOwnerAudit` | DL_Base | FB | 互斥锁所有权审计：记录持锁者标识、持有时长、越权释放与超时归还次数台账，**与 `FB_DL_SemaMutex`（互斥本体）分工：本件只做「事后可追」审计出口，不改变加解锁语义**（T0-8 行待挖②：超时归还后的所有权审计） | `t0-8-sema` | 中 | 1 | `16#01_0_02` |
| 2 | `FC_DL_TrendSlopeCalc` | DL_MathData | FC | 滑窗一阶最小二乘趋势斜率：输出斜率、截距、R² 与样本数不足/非有限剔除，**与 `FB_DL_Differentiator`（瞬时微分、噪声敏感）分工：本件为窗内拟合斜率，供温度升速/压降速率/泄漏率等趋势判级**；与 `FB_DL_*Trend` 监视件分工：本件是纯函数估计原子 | `t2-1-lgf-math` | 中 | 1 | `16#05_0_04` |
| 3 | `FC_DL_SphericalDistance` | DL_MathData | FC | 球面大圆距离（haversine 公式，公开领域）：两经纬度 → km，含反余弦域钳制与同点零距分支，**服务 AGV 航点里程 / 光伏阵列地理排布 / 天文钟族**（T2-1 Math「三角方向」待挖项） | `t2-1-lgf-math` | 中 | 1 | `16#05_0_05` |
| 4 | `FB_DL_FrequencyGenerator` | DL_Algo | FB | 连续频率发生（方波 + 相位复位 + 占空比组态）：**与 `FB_DL_PulseGenerator`（单脉冲/脉宽）分工为「生连续波 vs 发单发」，与 `FB_DL_FrequencyMeasure`（测）构成「测 ≠ 生」两侧**（矩阵 R22 已明文记载分工） | `t2-1-lgf-siggen` | 中 | 1 | `02_3_86` |
| 5 | `FB_DL_TriangleGenerator` | DL_Algo | FB | 三角波发生：Sine/Sawtooth 同族第三基本波形，相位连续 + 幅值/频率引脚化，**沿用矩阵「按波形形状切块、明文禁用 eWaveform 枚举合并」组纪律** | `t2-1-lgf-siggen` | 中 | 1 | `02_3_87` |
| 6 | `FB_DL_LaminatorPressCtrl` | DL_Algo | FB | 层压机压力-时间闭环（真空段/加压段分离双目标 + 斜坡限速）：**闭环控制律按分层判定归 Algo（ROADMAP 原记 Process 属分层误记，本轮改判并留痕）；与 `FB_DL_RollCompressForceBalance`（力平衡）分工：本件管压力曲线跟随** | `t2-2-lbp` | 高 | 2 | `02_3_88` |
| 7 | `FB_DL_CamOverrideTrim` | DL_Motion | FB | 凸轮运行中动态修调：幅值/相位偏置实时叠加在凸轮输出上（不重选表、不脱耦），**T1-6 行待挖项「凸轮动态修调」落地；与 `FC_DL_CamTableInterp`（表插值）与 `FB_DL_ElectronicCam`（耦合本体）分工** | `t1-6-plcopen` | 中 | 2 | `04_0_A6` |
| 8 | `FB_DL_AxisLimitRecovery` | DL_Motion | FB | 硬限位触发后的脱离恢复顺控：判限位方向 → 低速反向脱离 → 脱离确认 → 放行再使能，**与 `FB_DL_SoftLimitGuard`（软限位制动预判）分工：本件管硬限位已触发后的恢复，与 `FB_DL_TorqueLimitControl`（达限即限）分工** | `t1-6-plcopen` | 中 | 2 | `04_0_A7` |
| 9 | `FB_DL_BcdFieldPanelIO` | DL_Device | FB | 面板 BCD 拨码阵列采集/输出：多路拨码消抖 → `FC_DL_BcdToWord` 组装 → 设定值带校验出口，**与既有 BCD 转换 FC（单路原子）分工：本件是设备级阵列 IO 组装件** | `t2-1-lgf-converter` | 中 | 2 | `03_2_17` |
| 10 | `FB_DL_DoorInterlockHvac` | DL_Device | FB | 机房门禁-风机联锁：开门降频（经 `FB_DL_RateLimiter` 斜坡）→ 关门延时恢复策略组态，**与 `FB_DL_GuardLockDoor`（门本体握手）和炉门互锁族（全停互锁）分工：本件管「降频-恢复」而非全停** | `t2-2-lbp` | 中 | 2 | `03_2_18` |
| 11 | `FB_DL_ElMutingGantry` | DL_Device | FB | EL 检测龙门进出光幕屏蔽（muting）：4 传感器时序判进/出方向 + 屏蔽窗超时强制退出，**与 `FB_DL_SafetyLightCurtain`（光幕本体）分工：本件只做屏蔽时序仲裁，安全事件不受屏蔽约束** | `t1-5-tcopen` | 中 | 3 | `03_2_19` |
| 12 | `FB_DL_CleaningBrushWear` | DL_Device | FB | 清扫机器人刷辊磨损与换刷里程：行程累计 + 电流趋势窗双判据 + 换刷后基准重置，**三分类诊断结构借 T2-6 AOI 语义（里程类 / 电流类 / 组态类）** | `t2-6-rockwell-aoi` | 中 | 3 | `03_2_1A` |
| 13 | `FB_DL_OrificeDpZeroTrim` | DL_Device | FB | 孔板差压零点漂移补偿：静流时段（`FC_DL_Deadband` 判静流 + `FB_DL_MedianFilter` 取样）长期零点跟踪与修正量出口，**与 `FC_DL_OrificeFlowCalc`（流量计算）分工：本件只供修正量，不算流量** | `t2-8-ne43` | 中 | 3 | `03_2_1B` |
| 14 | `FB_DL_HjtPvdSeq` | DL_Process | FB | HJT 光伏 PVD 镀膜腔体顺控：本底真空确认 → 基片预热 → 工艺镀膜 → 取片联锁四段，段超时升级 + 双到位联锁内置 | 自研线（半导体/光伏工艺） | 高 | 3 | `06_0_B6` |
| 15 | `FB_DL_ElectrolyteFillCtrl` | DL_Process | FB | 注液量闭环（称重罐减量法 + 静置浸润计时）：**与 `FB_DL_ElectrolyteDosingSeq`（定量投加顺控）分工：本件是减量法闭环注液 + 浸润驻留** | `t2-2-lbp` | 高 | 3 | `06_0_B7` |
| 16 | `FB_DL_CartonDenestPush` | DL_Process | FB | 纸箱分离-推箱顺控：料仓分离机构 + 推杆节拍 + 双料位联锁，**与 `FB_DL_CartonErectSeq`/`CartonErectorStation`（开箱成型族）分工：本件是成型上游的分离供箱** | `t2-7-packml` | 中 | 4 | `06_0_B8` |
| 17 | `FB_DL_RadiatorZoneValve` | DL_Process | FB | 散热器末端温控阀脉冲控制：`FB_DL_ThreePointValve` 典型消费场景（三点浮点阀 + 房间温度闭环 + 最小启停间隔保护） | `t2-2-lbp` | 中 | 4 | `06_0_B9` |
| 18 | `FB_DL_TankLevelStrapping` | DL_Process | FB | 储罐液位-容积分层标定与体积折算：容积表（分层点 + 折算）标定核对 + 越表插值拒绝，**与 `FC_DL_MultiPointLinear`（通用折算）分工：本件带标定核对与罐型组态语义** | 自研线（t2-1-lgf-math 次源） | 中 | 4 | `06_0_BA` |
| 19 | `FB_DL_WaferBreakDetect` | DL_Process | FB | 电池片隐裂/碎片在线判据：视觉结果位（`FC_DL_BitFieldExtract`）+ 突发峰值捕获（`FB_DL_PeakDetector`）双判据聚合分级，**判据取「批内突发异常」而非单件越限** | `t2-1-lgf-measurement` | 中 | 4 | `06_0_BB` |
| 20 | `FB_DL_RoomCo2DemandVent` | DL_Process | FB | CO₂ 需量通风与新风阀联动：浓度标定 → 需量闭环 + 最小新风位硬下限 + 传感器失效退守模式，**与 `FB_DL_RoomClimateCtrl`（温湿双回路）分工：本件只管浓度需量回路** | `t1-2-oscat-building` | 中 | 4 | `06_0_BC` |

> **配额结论**：T2 标签 10 件（t2-1 四子组 / t2-2 / t2-6 / t2-7 / t2-8-ne43）、T1 标签 3 件（t1-2 / t1-5 / t1-6）、T0 标签 1 件（t0-8 待挖项）、自研线 2 件 → **「≥1 个 T2 族 + ≥1 个 T1 组」双满足**；零检索轮，全部来源为既有 ◐ 行深化与待挖子项。
> **分布**：Base 1 ｜ MathData 2 ｜ Algo 3 ｜ Motion 2 ｜ Device 5 ｜ Process 7 = 20 ✅（最大单库 7，未全堆一库）

---

## 2 码位窗口实测（R217 硬约束，实测证据；编码专家不得越窗）

> **实测方法**：对磁盘 **670 个 `DL_*/*.st`** 分别跑「头部前 1504 字节」与「全文」正则 `16#(\d\d)_(\d)_([0-9A-F]{2})`，**取并集**为权威占用集。实测发现**仅扫头部会漏报 11 个码位**（`02_3` 漏 38/3C/40/44/48/4C/50/54/58；`06_0` 漏 00/05/0A/0F/14/19/1E/23/28/2D/32 —— 共 20 处分布在 11 个不同码位值），故本轮起口径升级为**头部 ∪ 全文**；`code_segment` 字段（530/670 有值）仍不作依据。
> **实测占用全集（并集，2026-11-19 01:48 快照）**：
> - `01_0`：00 01（2 个）
> - `02_3`：38 3C 40 44 48 4C 50 54 58 5C 5D 5E 5F 80 81 82 83 84 85（19 个）
> - `03_1`：01 02 03 04 05（5 个）
> - `03_2`：00 01 02 03 04 06 07 08 09 0A 0B 0C 0D 0E 0F 10 11 12 13 14 15 16（22 个；05 空穴留存不占）
> - `04_0`：6C A0 A1 A2 A3 A4 A5（7 个）
> - `05_0`：00 01 02 03（4 个）
> - `06_0`：00 05 0A 0F 14 19 1E 23 28 2D 32 37~40 80~8F 90~99 B0~B5（53 个）

| 窗口 | 码段（闭区间） | 归属 | 本轮占用（序号） | 实测依据 |
|---|---|---|---|---|
| W1 | `16#01_0_02` | DL_Base | 1 | `01_0` 仅占 00/01（R38），`02` 起空 |
| W2 | `16#05_0_04` ~ `16#05_0_05` | DL_MathData | 2、3 | `05_0` 占 00~03，`04/05` 空（R38 预留解除，本轮正式启用） |
| W3 | `16#02_3_86` ~ `16#02_3_88` | DL_Algo | 4、5、6 | `02_3` 占至 85，`86~88` 空（R38 预留解除） |
| W4 | `16#04_0_A6` ~ `16#04_0_A7` | DL_Motion | 7、8 | `04_0` 占至 A5，`A6/A7` 空 |
| W5 | `16#03_2_17` ~ `16#03_2_1B` | DL_Device | 9~13 | `03_2` 占 00~04/06~16，`17~1B` 空（R38 预留解除）。**段位说明（R192）**：`03_2` 低半字节 00~0F 已满（05 空穴留存），R38 已进位 `12` 段，本轮续用 `1x` 段，各件头注释注明「低半字节已满，`1x` 段续号」 |
| W6 | `16#06_0_B6` ~ `16#06_0_BC` | DL_Process | 14~20 | R38 W7 预留 `B6~BF` 本轮正式启用 `B6~BC`（7 格）；`90~99` 为 R35 判错位段不碰 |

**窗口纪律（沿用 R38 §2 全部四条）**：一件一码；件内多级码不得就地连号占下一件格，须报总监改派；空穴与余量（`03_2_05`、`03_2_1C~1F`、`06_0_BD~BF`、`06_0_41~7F`、`04_0_A8+`、`02_3_89+`、`05_0_06+`、`01_0_03+`）登记保留。

---

## 3 批次切分（4 批 × 5 件，批内依赖全部为已注册件）

| 批次 | 序号——组件名 | 批内依赖（registry 实测存在，禁新建依赖） |
|---|---|---|
| **批 1**（Level 0 原子 + 纯函数） | 1 `MutexOwnerAudit` ｜ 2 `TrendSlopeCalc` ｜ 3 `SphericalDistance` ｜ 4 `FrequencyGenerator` ｜ 5 `TriangleGenerator` | #1 仅 `Standard.library` + `FB_DL_SemaMutex`（仅对齐状态枚举语义）；#2/#3 纯函数无依赖；#4/#5 仅 `Standard.library`（与 `FB_DL_PulseGenerator`/`FB_DL_SineGenerator` 仅引脚命名对齐） |
| **批 2**（Algo 闭环 + Motion + Device 前段） | 6 `LaminatorPressCtrl` ｜ 7 `CamOverrideTrim` ｜ 8 `AxisLimitRecovery` ｜ 9 `BcdFieldPanelIO` ｜ 10 `DoorInterlockHvac` | #6 `FB_DL_CascadePid`、`FB_DL_RateLimiter`、`FC_DL_Hysteresis`；#7 `I_DL_MotionAxis`、`FC_DL_CamTableInterp`（**注意 FC 前缀，禁写成 FB_**）；#8 `I_DL_MotionAxis`、`FB_DL_AxisInPosMonitor`；#9 `FC_DL_BcdToWord`、`FC_DL_WordToBcd`、`FB_DL_SignalDebounce`；#10 `FB_DL_RateLimiter`、`FC_DL_Hysteresis` |
| **批 3**（Device 诊断 + Process 前段） | 11 `ElMutingGantry` ｜ 12 `CleaningBrushWear` ｜ 13 `OrificeDpZeroTrim` ｜ 14 `HjtPvdSeq` ｜ 15 `ElectrolyteFillCtrl` | #11 `FB_DL_SafetyLightCurtain`、`FB_DL_SignalDebounce`；#12 `FB_DL_EventCounter`、`FB_DL_RuntimeMeter`、`FB_DL_SignalStatistics`；#13 `FC_DL_Deadband`、`FB_DL_MedianFilter`、`FB_DL_SignalStatistics`；#14 `I_DL_VacuumGenerator`、`I_DL_TemperatureZone`、`FB_DL_StepSequencer`；#15 `FB_DL_ToleranceWindow`、`FC_DL_Hysteresis`、`FB_DL_SignalStatistics` |
| **批 4**（Process 后段） | 16 `CartonDenestPush` ｜ 17 `RadiatorZoneValve` ｜ 18 `TankLevelStrapping` ｜ 19 `WaferBreakDetect` ｜ 20 `RoomCo2DemandVent` | #16 `I_DL_Cylinder`、`FB_DL_StepSequencer`、`FB_DL_VacuumEjector`；#17 `FB_DL_ThreePointValve`、`FC_DL_Hysteresis`；#18 `FC_DL_MultiPointLinear`、`FC_DL_LinearScale`、`FB_DL_ToleranceWindow`；#19 `FC_DL_BitFieldExtract`、`FB_DL_PeakDetector`、`FB_DL_SignalStatistics`；#20 `FC_DL_LinearScale`、`FB_DL_PidController`、`FC_DL_Hysteresis` |

---

## 4 P0 返修任务（3 件，R38 终审挂账；路径取自 registry `file_path` 字段，非记忆）

| # | 组件 | registry 路径（实测） | 版本 | 缺陷定位（R38 终审行号） | 返修要求 |
|---|---|---|---|---|---|
| R1 | `FB_DL_ModuleLamVacuumSeq` | `C:\Library\DL_Process\FB_DL_ModuleLamVacuumSeq.st` | 1.0.1 → 1.0.2 | `tonSeg` 的 **PT 误接 `tSegmentTimeout`**（行 106~108）→ 四段配方时长从未接入，推进与超时同拍、`ELSIF` 先判超时 ⇒ **段序永不正常推进**；`eFault` 无迁出边（行 262/263）→ 故障永久锁死 | ① `tonSeg.PT` 改接当前段配方时长（四段各自时长，禁共享单一参数）；② `eFault` 增加 `bReset` 迁出边回 `eIdle`（迁出条件可满足性自证逐字写头注释）；③ 版本升 1.0.2，VERSION.md 迁移说明 |
| R2 | `FB_DL_ElectrodeTabBendCtrl` | `C:\Library\DL_Device\FB_DL_ElectrodeTabBendCtrl.st` | 1.0.1 → 1.0.2 | `tonStep` **三相共享且无迁移断拍**（行 94/95），`eBend` 复用作保压计时（行 173/174）；`eFault` 无迁出边（行 213/214）→ 故障永久锁死 | ① 三相各配独立 TON 实例或迁移拍强制断 IN（R228-A 达标）；② `eFault` 加 `bReset AND eState 迁出可达` 边；③ 保压计时与步进计时分实例；④ 版本升 1.0.2 |
| R3 | `FB_DL_VavBoxZeroCal` | `C:\Library\DL_Device\FB_DL_VavBoxZeroCal.st` | 1.0.1 → 1.0.2 | `tonStable`/`tonCal` 的 IN **跨 `eZeroWait`/`eFullWait` 两相不复位**（行 89/91）→ 满量程驻留失效，迁入次拍带内即采样 | ① 跨相迁移拍复位或按相独立实例（R228-A 达标）；② 版本升 1.0.2 |

> 返修件由编码线一并处理，**不计入 20 新件名额**；修复后须过机检 R228 两条扫描 + 终审抽检（R193：抽检挂账 ≥3 即扩族全量返修）。

## 4bis 机检新规则（R228 缺口单 2 条）验收标准

| 规则 | 扫描内容 | 回归口径（先返修件后新件） |
|---|---|---|
| **A｜TON PT 语义 + 跨相复位** | ① 每个 `TON` 实例的 `PT` 实参必须为「配方/驻留/段时长」语义参数或本相常量，禁接超时/看门狗语义信号（PT 与超时判据同参即命中）；② `TON` 的 `IN` 在状态迁移拍必须断开或实例复位——跨相不复位即命中 | 3 返修件**修复前**应各命中 ≥1 处（R1：PT 误接；R2：跨相共享；R3：跨相不复位）→ 修复后 0 命中；20 新件 0 命中 |
| **B｜eFault 迁出路径** | 扫描 `eFault`/`*Fault` 状态的 `CASE` 分支：必须存在迁出赋值（`eState := 非Fault 态`），且迁出条件表达式经静态检查不含恒假子式（`NOT bEnable AND NOT _bFaultLatch` 类）；无迁出边即命中（缺陷码：永久锁死） | 3 返修件修复前各命中 ≥1（R1 行 262/263、R2 行 213/214）→ 修复后 0；20 新件 0 |

---

## 5 判弃清单（本轮实测剔除 ≥14 条，防凑数变体——R28 选题双查 / R184 / R193）

| 曾候选 | 撞车件（registry 实测） | 判弃理由 |
|---|---|---|
| `FC_DL_GrayCodeConvert` | `FC_DL_BinaryToGray` / `FC_DL_GrayToBinary` **已注册** | 格雷码族已收口，重复立项 |
| `FB_DL_WatchdogSupervise` | `FB_DL_WatchdogMonitor` 已注册 | 同语义邻件，窗口双限属变体，宁少勿滥 |
| `FB_DL_WebGuideCtrl` | `FB_DL_FilmWebCenter` 已注册 | 对中纠偏语义已覆盖 |
| `FB_DL_PulseDivider` | `FB_DL_EdgeDivider` 已注册 | 分频语义已覆盖 |
| `FB_DL_PidBumplessHandover` | `FB_DL_BumplessTransfer` 已注册 | 无扰切换已覆盖（矩阵 T2-5 行该待挖项闭环） |
| `FB_DL_PidGainScheduleBank` | `FB_DL_GainScheduler` + `FB_DL_PidGainScheduler` 已注册 | 双件已覆盖 |
| `FB_DL_ChamberPumpDownSeq` | `FB_DL_ChamberPumpDownProfile` / `FB_DL_PumpDownEnvelopeMonitor` / `FB_DL_ChamberLeakRate` 已注册 | 抽真空+漏率族三件已覆盖，顺控变体不立 |
| `FB_DL_CasePackerPatternVerify` | `FB_DL_CasePackerPattern` 已注册 | 排列校验已覆盖 |
| `FB_DL_CassetteMapVerify` | `FB_DL_WaferMapping` / `FB_DL_WaferCassetteSlot` 已注册 | 片位映射已覆盖 |
| `FB_DL_CellOcvBinSort` | `FB_DL_OcvGradingBin`（R34）已注册 | OCV 分档已覆盖 |
| `FB_DL_DamperBitDiag` | `FC_DL_BitFieldExtract` + `FB_DL_UnpackWordToBits` 原子已在 + `FB_DL_AhuDamperStuckDiag` 邻件 | 薄件（纯位段组装组合），无独立判据 |
| `FB_DL_FilmSpliceCurtain` | `FB_DL_ElMutingGantry`（本轮 #11）+ `FB_DL_SafetyLightCurtain` | 2/4 传感器屏蔽为同族变体，只立判据更完备一件 |
| `FB_DL_RoofUnitDoorSw` | `FB_DL_DoorInterlockHvac`（本轮 #10） | 检修门-风机与门禁-风机同语义，只立一件 |
| `FB_DL_TankBlanketPrCtrl` | `FB_DL_TankN2BlanketCtrl`（R23）已注册 | 氮封族已覆盖 |
| `FB_DL_HumidifierAdiabat` | `FB_DL_HumidifierWaterQual` 已注册邻件 | 补水语义相邻，判据增量不足，宁少勿滥 |
| `FC_DL_ShlDwordEx` / `FC_DL_ShrDwordEx` | R34 弃判项 | 继续有效，不重开 |
| `FB_DL_GlassFeederAccum` | R38 判弃项 | 继续有效，不重开 |

---

## 6 查重声明（四项，全部给实测数字）

1. **name 查**：670 条 `components[].name` 精确匹配（小写比对）→ 20 个目标名 **0 命中**；磁盘 670 文件名同查 **0 命中**。
2. **词干同义查**：19 个词干（watch/mutex/gray/spheric/freq/triang/guide/override/recovery/bcd/panel/muting/brush/orific/pumpdown/pattern/denest/radiator/strap/co2/pvd…）逐个对 670 名扫描，命中者全部进入 §5 判弃或已写明分工判据（如 `OrificeDpZeroTrim` vs `FC_DL_OrificeFlowCalc`：补正量 vs 流量计算）。
3. **码位查**：20 个新码位（§2 六窗口）与实测占用全集（头部∪全文）**零交集**。
4. **依赖可达性查**：38 个依赖名核验，1 处名误当场纠正（`FB_DL_CamTableInterp` → 实为 `FC_DL_CamTableInterp`），其余全在册；禁写不存在类型。

## 7 阶段一边界与 R38 挂账承接

- 本轮**不改** `INDEX_REGISTRY.json` / JSONL / 任何 `.st`（规划线不落码）；
- R38 §六之 3「ROADMAP 138 条勾选漏账专项回写」与「编译验证债（连欠 34 轮）」为编码线/收尾线职责，本轮仅记账：未勾 172 条 ≥ 30，按派单规则**不触发 ROADMAP 补写**；
- R195 编译闸提示：编译债连欠 ≥3 轮已成立，本轮 20 件中**无新增编解码/数学/转换类高复杂度件**（最复杂件为顺控/闭环类），符合闸门约束。

*编制：道莅工控代码库产品总监（R39 阶段一）｜ 2026-11-19 01:48*
