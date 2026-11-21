# R52 轮次计划（2026-11-20 12:43，阶段一盘点锁定 20 目标 + 阶段二源矩阵狩猎；**零检索轮 WebSearch 0/3**）

## 0 统计快照

| 指标 | 数值 |
|---|---|
| 总库 registry | **925 / 10,000 = 9.25%**（v2.43.0，JSONL 语料 926 条） |
| 今日产出 | **80 / 200**（40.0%，R48+R49+R50+R51 各 20） |
| 500 计划 | 已超额 **+425** |
| 1000 段目标 | 925 → 1000 **差 75 件**（本轮 20 件后余 55） |
| 六库分布 | Base 102 / MathData 210 / Algo 107 / Device 171 / Motion 103 / Process 232 |
| 源矩阵覆盖率 | T0 八组全 ✔（余量 0，**本轮 T0 = 0，禁硬凑**）；T1/T2 台账 ☐ 残留 0 行，◐ 深化行全部复用 |
| ROADMAP 未勾待办 | 54 条 ≥ 30 → **按纪律禁止新增条目，只认领/只记账** |

### 0.1 三向一致性差额实测（本轮新发现，R192 记账）

撞名双查实测发现 **7 条「ROADMAP 未勾 `- [ ]` 但 registry 已有同名件」**差额（三向不一致），本轮不做回写，逐条挂账 R53 首位：

| # | ROADMAP 行 | 条目名 | registry 状态 | 处置 |
|---|---|---|---|---|
| 1 | L725 | `FB_DL_ChillerYearWinStart` | 已存在 | R53 勾选 + 手册核对 |
| 2 | L733 | `FB_DL_ReactorYearWinClean` | 已存在 | R53 勾选 + 手册核对 |
| 3 | L443 | `FB_DL_HumidifierAdiabat` | 已存在 | R53 勾选 |
| 4 | L418 | `FB_DL_TrayLoadVacuum` | 已存在 | R53 勾选 |
| 5 | L435 | `FB_DL_CupFillDenest` | 已存在 | R53 勾选 |
| 6 | L471 | `FB_DL_NgBinDosing` | 已存在 | R53 勾选 |
| 7 | L920 | `FB_DL_SteamTrapSurvey` | 已存在 | R53 勾选 |

> 差额 7 条 < 10 条门槛 → 不触发 R192 专项回写，但**占 R53 排程首位**（勾选 + 手册三段对齐）。此 7 件本轮**不重复立项**。

---

## 1 本轮 20 目标（4 批 × 5 件，批次按依赖切分：批 1 纯函数 → 批 4 最复杂时序件）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_BitCountOnes` | DL_Base | FC_ | 位串置 1 计数（popcount，BYTE/WORD/DWORD/LWORD 四重载族首件） | t2-1-lgf·bitlogic | 2 | 1 |
| 2 | `FC_DL_WrapIndexNeg` | DL_MathData | FC_ | 环窗下标负值模归正（0-based/1-based 双口径，修正 IEC MOD 负余数） | 自研·环窗族治理（R193 配套） | 2 | 1 |
| 3 | `FC_DL_LogDomainNormalize` | DL_MathData | FC_ | 对数域归一化（pH/浓度/浊度 → 0~1 线性度，含定义域与底数守卫） | t1-1-oscat·math | 3 | 1 |
| 4 | `FC_DL_PriorityEncodeWord` | DL_Base | FC_ | 位串优先编码（最高/最低置位位序号，无置位返回 0 号哨兵） | t2-1-lgf·bitlogic | 2 | 1 |
| 5 | `FC_DL_ZnTune` | DL_Algo | FC_ | 临界比例度法（Ziegler-Nichols）由临界增益/周期推算 PID 三参 | t2-5-modpid·tune | 3 | 1 |
| 6 | `FB_DL_SchmittTriggerGap` | DL_Base | FB_ | 带回差的双阈值整形（施密特，阈值滞带宽可组态） | t2-1-lgf·comparator | 2 | 2 |
| 7 | `FB_DL_EdgeIntervalMeter` | DL_Base | FB_ | 双沿间隔/周期与占空比测量（含抖动统计与超时无沿判据） | t2-1-lgf·dateandtimer | 3 | 2 |
| 8 | `FB_DL_AdaptiveDeadbandZone` | DL_Algo | FB_ | 噪声带自适应死区（按信号噪声幅值在线整死区宽度） | t2-5-modpid·deadband | 3 | 2 |
| 9 | `FB_DL_DerivativeNoiseWeight` | DL_Algo | FB_ | 微分项噪声权重与降权（高频能量超阈自动衰减 Kd） | t2-5-modpid·deriv | 3 | 2 |
| 10 | `FB_DL_ControlOutputSlewWatch` | DL_Algo | FB_ | 控制输出变化率监视（阀门行程速率异常→振荡/爬行判据） | t2-1-lgf·measurement | 3 | 2 |
| 11 | `FB_DL_PidParamDriftAudit` | DL_Algo | FB_ | 整定参数漂移审计（现行参数 vs 基准快照，越差即留痕） | t2-3-风格指南·审计 | 3 | 3 |
| 12 | `FB_DL_BrakeResistorThermal` | DL_Device | FB_ | 变频器制动电阻热累积估算（I²t 模型 + 冷却时间常数） | t2-6-rockwell-aoi | 4 | 3 |
| 13 | `FB_DL_PressureSwitchChatter` | DL_Device | FB_ | 压力开关抖动诊断（窗口内翻转次数分档 + 阻尼建议） | t2-8-ne107·诊断 | 3 | 3 |
| 14 | `FB_DL_MeterPulseLossDetect` | DL_Device | FB_ | 脉冲式流量计丢脉冲检测（指令-反馈脉冲比对与速率闸） | t1-3-oscat-network·计量 | 3 | 3 |
| 15 | `FB_DL_HeatTraceCircuitMon` | DL_Device | FB_ | 电伴热回路监视（电流存在性 × 温升响应，断缆/空烧双判） | t2-8-isa182·回路一致性 | 4 | 3 |
| 16 | `FB_DL_AxisJerkLimitCheck` | DL_Motion | FB_ | 加加速度（jerk）指令合法性检查与钳位（防高速贴装冲击） | t1-6-plcopen·limits | 4 | 4 |
| 17 | `FB_DL_AxisHomeRepeatVerify` | DL_Motion | FB_ | 回零重复性校验（多次回零位置标准差 + 超散拒放行） | t1-6-plcopen·homing | 4 | 4 |
| 18 | `FB_DL_AxisSoftLimitPredict` | DL_Motion | FB_ | 软限位超程预测（按当前速度/减速度预判越界，提前请求减速） | t2-4-s7-motion | 4 | 4 |
| 19 | `FB_DL_MakeupWaterDosing` | DL_Process | FB_ | 补水定量加药（流量累计触发 + 加药泵定比投加，水务/暖通） | ROADMAP L501（未勾真缺口） | 3 | 4 |
| 20 | `FB_DL_DieBinCounter` | DL_Process | FB_ | 晶粒分箱计数与满箱切换（半导体后道，满箱前预警与切箱） | ROADMAP L647（未勾真缺口） | 3 | 4 |

### 1.1 反证句（为何不与在册 925 件撞名/同义）

| # | 组件 | 反证 |
|---|---|---|
| 1 | BitCountOnes | 全库 `BitCount*`/`PopCount` 词干 0 命中；存量位族为 `FC_DL_BitFieldExtract`（取值）/`WordBitPack`（打包）/`Shl*Ex`（移位），无「置 1 计数」语义。 |
| 2 | WrapIndexNeg | `WrapIndex`/`IndexWrap` 词干 0 命中；存量 `RingBuffer*` 是数据容器不带下标归正函数，本件为纯函数供三族共用。 |
| 3 | LogDomainNormalize | `LogDomain`/`LogNorm` 0 命中；存量 `FC_DL_LinearScale`（线性）、`DewPointToPpmV`（专用换算）均为线性或单点语义，无对数域归一。 |
| 4 | PriorityEncodeWord | `PriorityEnc`/`BitScan` 0 命中；`BitFieldExtract` 为定宽字段提取，不返回首位序号，也不同义。 |
| 5 | ZnTune | `ZnTune` 0 命中；存量整定为 `PidLambdaTune`（λ 整定）/`RelayAutoTune`（继电反馈）/`GainSchedPid`（增益调度），ZN 临界比例度法为独立经典法。 |
| 6 | SchmittTriggerGap | `Schmitt` 0 命中；`FC_DL_Deadband` 为对称静态死区函数、`SignalDebounce` 为时间去抖，均非双阈值滞环状态机。 |
| 7 | EdgeIntervalMeter | `EdgeInterval` 0 命中；`FB_DL_PulseStretch`（已存在）为脉宽拉伸输出，本件输出周期/占空比/抖动测量值，方向相反。 |
| 8 | AdaptiveDeadbandZone | `AdaptiveDead` 0 命中；存量 `Deadband` 为定宽静态函数，本件按噪声带在线自适应，属闭环层。 |
| 9 | DerivativeNoiseWeight | `Deriv` 0 命中；`PidController` 内微分为固定滤波，本件为独立降权观测器，不改 Pid 契约。 |
| 10 | ControlOutputSlewWatch | `Slew` 0 命中；`ValvePartialStrokeTest`/`AxisTorqueWatch` 分属阀门试验与扭矩，无输出速率监视。 |
| 11 | PidParamDriftAudit | `ParamDrift` 0 命中；`LoopPerfIndex` 评性能不评参数一致性，`RecipeManager` 管参数集不管漂移留痕。 |
| 12 | BrakeResistorThermal | `BrakeResistor` 0 命中；`AxisBrakeTest`（抱闸力矩）/`HeaterSsrBank`（加热）均非电阻热模型。 |
| 13 | PressureSwitchChatter | `Chattering` 0 命中；`FlowSwitchResponseCheck` 测响应时间，本件测翻转次数与阻尼建议。 |
| 14 | MeterPulseLossDetect | `MeterPulse` 0 命中；`HydronicMeterAudit` 为表计台账审计，本件为脉冲级丢失检测，粒度不同。 |
| 15 | HeatTraceCircuitMon | `HeatTrace` 0 命中；`HeaterElementOpenDetect` 不存在（本项目未建），`ContactorWeldDetect` 为接触器粘连，语义不同。 |
| 16 | AxisJerkLimitCheck | `Jerk` 0 命中；`SCurveGenerator` 生成加加速度受限轨迹，本件为**检查器**（钳位 + 报警），不生成轨迹。 |
| 17 | AxisHomeRepeatVerify | `HomeRepeat` 0 命中；`AxisTeachOffset` 为示教偏置设定，`AxisInposGuard` 为到位监守，均不做重复性统计。 |
| 18 | AxisSoftLimitPredict | **强反证**：存量 `FB_DL_SoftLimitGuard`（钳位/拦截，反应式）+ `FB_DL_SoftLimitCfgAudit`（配置审计）；本件为**预测式**（v²/2a 预判越界提前请求减速），输入含速度与减速度，输出为减速请求位，不与 Guard 同义。 |
| 19 | MakeupWaterDosing | `MakeupWater` 0 命中；ROADMAP L501 未勾真缺口；与 `BatchDosingControl`（批次称重定量）不同源——本件按流量累计触发、定比投加。 |
| 20 | DieBinCounter | `DieBinCounter` 0 命中；`BidirectionalCounter`/`PresetCounterSat` 为通用计数器，本件含满箱预警与切箱联锁，属工站语义。 |

### 1.2 分类配额核对

| 库 | 本轮 | 配额上限 | 判定 |
|---|---|---|---|
| DL_Base | 4 | ≤4 | ✔ |
| DL_MathData | 2 | ≤2 | ✔（上轮偏科修正，MathData 持续收缩） |
| DL_Algo | 5 | ≤6 | ✔ |
| DL_Device | 4 | ≤5 | ✔ |
| DL_Motion | 3 | ≤4 | ✔ |
| DL_Process | **2** | ≤5 | ✔ **严重纠偏**（上轮 18 → 本轮 2，+232 存量库停止膨胀） |
| T0 件 | **0** | =0 | ✔ 八组全 ✔ 余量 0，禁硬凑 |

---

## 2 P0 裁决（三项，全部实测，结论写入 RAW_NOTES）

### 裁决 A｜`FB_DL_ValveSeatLeakWatch`（`DL_Device/FB_DL_ValveSeatLeakWatch.st` v1.0.0）→ **有缺陷，须修（r1.0.1）**

**缺陷定位（实证）**：L165
```iecst
_aX[_nHead] := DINT_TO_LREAL(_nHead);   (* 窗序号 = 头游标 *)
```
写入期以**头游标**作 LS 自变量 X，而 Y 按同一槽位存放。首轮填充（`_nHead` 1→n）时 X 单调合法；**一旦回卷**（`_nHead` 归 1），新样本 Y 配 X=1，而槽 2 的旧样本仍配 X=2 —— **X 与 Y 的时间序被旋转打乱**，一阶 LS 斜率符号不可信。后果落在判据 L194：`_bLeakC := (_fMean > fLeakLevel) AND (_fSlope >= 0.0)`，真实上升型泄漏会因斜率算成负而**漏报**（安全侧漏检，不是误报），属 R193「环窗+回归族」扩面隐患的典型样例。

**精确修法（R51 `FB_DL_RulEstimator` v1.0.1 时间序旋转范式，共 4 行）**：
1. **L165（核心一行）**：整行删除，改为注释 `(* X 不再于写入期生成：改为求和期按时间序现算（R52 修 R193 扩面） *)`；
2. **L174 后（`_i := 1;` 之前）插入 2 行**：
   ```iecst
   _nOldest := _nHead - _nFill;  IF _nOldest < 1 THEN _nOldest := _nOldest + _nEff; END_IF   (* 最旧槽：满窗回卷后无偏移，未满窗时=1 *)
   ```
3. **L176**：`_fSumX := _fSumX + DINT_TO_LREAL(_i);`
4. **L178**：`_fSumXY := _fSumXY + DINT_TO_LREAL(_i) * _aRes[((_nOldest + _i - 2) MOD _nEff) + 1];`（L179 Σx² 同法用 `_i` 的平方，L177 Σy 同步取旋转槽位）

**为何不采用更省的「单行 `_nSeq` 全局序号」方案**：全局序号 X 会随运行时间无界增长（x~10⁶ 时 Σx² ~10¹²），在 `_fDen := _fSumX2 - _fSumX*_fSumX/n` 产生灾难性相消，斜率精度崩塌；旋转到 x∈[1.._nFill] 同时解决**配对正确性**与**数值条件**，与 R51 已发布范式一致。附带：`_aX` 数组在修法后可整列废弃（R53 清理），本修法暂保留声明以不破坏 `.st` 差异审阅。

### 裁决 B｜`FB_DL_MoveResumeSeg.fStartRst` 死引脚 → **(2) 标注 `(* reserved *)` 保留**

**实证**：`fStartRst` 仅在 L72 声明（`:= 0.0`）与 L10 头注释出现，正文**零引用**；同族 `fTargetRst` 却在 L150/L151/L201/L202 正常参与（目标注入 + 段长派生）。**裁决理由**：L149/L200 的起点语义是「以当前位置 `fPosNow` 建快照」，L157/L204 已通过 `fStartSave` 把快照起点镜像给上层落盘；若让 `fStartRst` 参与，断电重启后注入的历史起点会覆盖实时 `fPosNow` 快照，段长 `_fSegLen` 与真实物理位置错位 → 进度 `_fProg` 跳变（L165 除子未变但分子失真）。**处置**：L72 注释改为 `(* 预留：起点恢复注入口（当前不参与运算，起点一律取实时 fPosNow 快照）[mm] / reserved *)` + 头注释「接口说明」段加一行预留声明；不删引脚（保外部引脚契约，删则需 MAJOR）。补逻辑必须走 v2.0.0 并同步改段长推导，不在本轮。

### 裁决 C｜`FC_DL_TrendSlopeCalc × RingBuffer/环窗族同源隐患 → **无需修（本体无环窗）**

**实证**：全文 158 行内 `_nHead`/`MOD`/`RingBuffer` 0 命中，X 由 `fXi := UDINT_TO_LREAL(INT_TO_UDINT(i)) * fDt`（L112）在求和期直接现算，`i` 严格 0→nUse-1 单调，无槽位旋转问题；分母 `fDen` 有 `ABS(fDen) < DL_TSC_EPS` 容差闸，非有限样本三段剔除齐备。**结论：不算同源隐患**。唯一残余风险在**调用侧契约**——若上层把 `FB_DL_RingBufferLReal` 的原始槽数组直传（未旋转），本函数会把乱序数组当时间序拟合；此属契约风险非缺陷。**处置**：R53 在头注释「使用约束」段补一行「`afY` 必须时间序（环窗需先按最旧→最新旋转/读出）」——文档级，不计返修。

### 裁决 D｜人格文件微调 → **本轮仍不做（第 3 次顺延）**，记 R53 待办（时长优先，本轮零检索 + 20 目标排满）

---

## 3 阶段二：源矩阵狩猎（零检索，全部复用既有台账行）

- **WebSearch 0/3**（本轮为**零检索轮**，指令硬约束）：不发起任何网络检索，20 目标全部来自 `SOURCE_HUNTING_MATRIX.md` 既有 ◐ 深化行 + `ROADMAP.md` 未勾条目的**语义派生**。
- 复用组（8 组，均既有 ◐，无 ☐→◐ 开组、无 ◐→✔ 收口）：`t2-1-lgf`(bitlogic/comparator/dateandtimer/measurement) / `t2-5-modpid`(tune/deadband/deriv) / `t2-4-s7-motion` / `t2-3-风格指南` / `t2-6-rockwell-aoi` / `t2-8-ne107+isa182` / `t1-1-oscat-math` / `t1-3-oscat-network` / `t1-6-plcopen`(limits/homing) / `roadmap-p1-p2` 真缺口 2 条。
- 合规：闭源源（LGF/LBP/S7）**只借分类与参数域**，代码 clean-room；OSCAT 免费但需致谢口径；GPL/AGPL 源零引用。详见 `RAW_NOTES_R52.md`。

## 4 R53 预置待办（≤3 条，承接本轮实测）

1. **P0**：7 条 ROADMAP-未勾-但已注册差额勾选回写（三向一致，R192 记账首位）。
2. **P0**：`FB_DL_ValveSeatLeakWatch` r1.0.1 按裁决 A 落地 + 全库 `_aX[` 头游标写入模式（环窗+回归族）机检规则化。
3. **P1**：`FC_DL_TrendSlopeCalc` 契约注记 + `MoveResumeSeg.fStartRst` 预留标注落地；人格文件微调（第 3 次顺延）。
