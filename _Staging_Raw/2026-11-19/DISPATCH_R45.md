# R45 编码派单文本（DISPATCH_R45）｜2026-11-19｜道莅工控代码库

> 派单对象：编码专家（plc-programming-expert 线）
> 前置必读：`ROUND_PLAN_R45.md`（选题与反证）、`AGENT_EVOLUTION_LOG.md`（历史规则）、`references/coding-standard.md`（红线全文）
> 本轮总件数：**2 件 P0 返修（先做）+ 20 件新件（4 批）**
> 硬约束：**不动引脚契约的返修走 PATCH**；新件一律 v1.0.0；**先落 `_Staging_Raw` 溯源笔记再落正式目录**。

---

## 1 新件派单（20 件）

### 通用交付要求（每件都适用）

1. 文件头七要素：组件名 / 所属子库 / 版本 / 兼容性 / 功能描述 / 开源溯源 Origin / 修订历史。
2. 声明区每个变量、每个枚举项**同行**中英双语注释 + 工程单位。
3. 单一主状态机：`ENUM` + `CASE` + `ELSE` 兜底（兜底落 `eFault` 并置码）；一台功能块只允许一个主状态机。
4. 故障码：单件单总码 + `eCause` 归因成员承载多因（R190 范式，**不新增多码位**）；信息级单码。
5. 故障锁存解除式全当拍量（R240 范式），并**自证可满足**（终审两式 1）。
6. 出口单点映射段（段 6）：`bError` 与 `uErrorId` 同源配对，故障相安全侧输出显式钳位。
7. 段 1 单拍量预清零；锁存量不入清零清单。
8. 溯源：写 `_Staging_Raw/2026-11-19/RAW_NOTES_R45.md`，逐件记「来源标签 / 许可证 / 提取点 / 判定（clean-room 或行为定义）」。

---

### 批 1（Level 0 + 纯函数 + 单体算法）

#### 1. `FB_DL_Vote2oo3` ｜ DL_Base ｜ FB ｜ 中

**功能规格**
- 三通道输入 `bCh1/bCh2/bCh3` + 各通道健康位 `bHealthy1..3`；
- 表决：健康通道数 ≥2 时按多数输出；健康通道数 =2 时降级 1oo2（两健康通道不一致 → 判失配）；健康通道数 ≤1 → `bOut := FALSE` 且置故障；
- 输出：`bOut`（表决结果）、`nAgreeCount`（同意数）、`eCause`（无故障 / 通道失配 / 健康数不足 / 组态非法）、`bError`、`nErrId`；
- 失配必须带确认时间 `tMismatchTime`（默认 `T#300MS`），消除单拍抖动误判。

**边界与安全条件**
- `tMismatchTime <= T#0S` 或 `tConfirmTime` 类参数 ≤0 → 组态非法码锁存；
- 输出安全侧：故障相 `bOut := FALSE`（保守关断侧）；
- TON / R_TRIG 实例段 0 无条件刷新；
- 解除式：`bReset` 上升沿 ∧ 组态合法 ∧ 失配计时未到（当拍量）∧ 健康数 ≥2。

**来源标签**：自研线（表决结构惯例，零代码行）｜**码位**：DL_Base 段，落盘前实测自取

#### 2. `FB_DL_EdgeOrderCheck` ｜ DL_Base ｜ FB ｜ 低

**功能规格**
- 监视两信号 A→B 的先后顺序与最小间隔：`bSigA` / `bSigB` / `tMinGap`（A 必须先于 B 至少 `tMinGap`）；
- 逆序发生（B 先于 A 且 A 随后到来）→ `nReverseCount` 递增并锁存故障；
- A 单独持续超过 `tAloneMax` 而未等到 B → 判「缺回应」信息级；B 无 A 前导 → 判「越序」故障级；
- 输出 `bOrderOk` / `nReverseCount` / `eCause` / `bError` / `nErrId`。

**边界与安全条件**
- `tMinGap <= T#0S`、`tAloneMax <= tMinGap` → 组态非法码；
- 计数器饱和（`DL_COUNT_MAX` 常量，不裸数）且回绕置信息级；
- `R_TRIG` 两枚 + `TON` 一枚段 0 无条件刷新；解除式：复位沿 ∧ 组态合法 ∧ 两信号均已回落。

**来源标签**：自研线（现场联锁惯例）｜**码位**：DL_Base 段

#### 3. `FB_DL_AlarmFloodLimiter` ｜ DL_Base ｜ FB ｜ 中

**功能规格**
- 滑动窗同源报警计数：`uAlarmSrc`（来源号）+ `bAlarmActive`；窗内同源次数超 `nFloodLimit` → 进入抑制态 `bSuppressed`；
- 抑制期 `tSuppressHold` 内新报警不再上送（`bPassThrough := FALSE`），但**计数继续**并在抑制结束时输出 `nSuppressedCount`（首末计数台账，ISA-18.2 泛滥抑制语义）；
- 输出：`bPassThrough` / `bSuppressed` / `nSuppressedCount` / `nWindowCount` / `bError` / `nErrId`。

**边界与安全条件**
- **禁止抑制任何「安全类」来源**：加 `bSafetyCritical` 输入，为真时 `bPassThrough` 恒真（安全侧不可被闸掉，这是本件的核心红线）；
- `nFloodLimit = 0`、`tWindow <= T#0S`、`tSuppressHold <= T#0S` → 组态非法；
- 滑动窗不得用数组越界写法（环缓冲下标先判边界）；
- `TON` 两枚 + `R_TRIG` 一枚无条件刷新。

**来源标签**：t2-8-isa182 报警生命周期｜**码位**：DL_Base 段

#### 4. `FC_DL_CubicBezierEval` ｜ DL_MathData ｜ FC ｜ 低

**功能规格**
- 输入 P0~P3 四个控制点（只用一维标量版本，`fP0..fP3` 与 `fT`），输出 `fValue` 与 `fTangent`（对 t 的一阶导）；
- 求值走 **De Casteljau** 三次插值（数值稳定，避免多项式展开的系数相消）；
- `fT` 越域钳制到 `[0,1]` 且置 `bClamped`。

**边界与安全条件**
- 任一输入非有限（NaN/Inf 自反双判，须在头注释声明为浮点判等禁令唯一例外）→ 输出 0、`uErrorId` 置错、不抛异常；
- 纯函数零状态，无 TON/边沿；
- 头注释须写明：**与 `FC_DL_CubicSplineInterp` 分工 = 参数曲线求值 vs 数据点插值**（防同义误读）。

**来源标签**：t2-1-lgf Math 子族｜**码位**：MathData 段

#### 5. `FB_DL_KalmanFilter1D` ｜ DL_Algo ｜ FB ｜ 高

**功能规格**
- 标量卡尔曼：状态 `_fX`、协方差 `_fP`；每拍「预测（`fQ` 过程噪声）→ 更新（`fR` 测量噪声）」；
- 新息门限：`|fMeas - _fX| > fInnovLimit` → 拒野值（`bRejected := TRUE`，本拍不更新，`_fP` 增大）；
- 协方差发散复位：`_fP > fPMax` 持续 `tDivTime` → 用当拍实测重初始化并置信息级；
- 失能 `bEnable := FALSE` → 直通 `fMeas` 并冻结协方差（不归零，便于无扰恢复）；
- 输出：`fOut` / `fPOut`（当前协方差）/ `bRejected` / `bDiverged` / `bError` / `nErrId`。

**边界与安全条件**
- `fQ <= 0.0`、`fR <= 0.0`、`fInnovLimit <= 0.0`、`fPMax <= 0.0` → 组态非法锁存；
- 任意除法前判除子（`fP + fR` 非零，浮点用 `> DL_FLOAT_EPS`）；
- 浮点判等全走容差；NaN 输入 → 本拍拒收并置信息级，**不让 NaN 污染 `_fP`**；
- 解除式：复位沿 ∧ 组态合法 ∧ 非发散态（当拍量）。

**来源标签**：自研线（公开 Kalman 递推式，零代码行）｜**码位**：Algo 段

---

### 批 2（Algo 4 + Motion 1）

#### 6. `FB_DL_TensionObserver` ｜ DL_Algo ｜ FB ｜ 高

**功能规格**
- 由「电机/收放卷转矩 `fTorqueNm`、实际卷径 `fDiaM`、角加速度 `fAngAccRadS2`、传动比 `fGearRatio`、机械效率 `fEff`」反算材料张力估计 `fTensionN`；
- 惯量项补偿：`J` 由 `fInertiaKgm2` 输入（外部辨识件给值，本件不内联辨识）；
- 摩擦补偿：`fFrictionNm` 输入 + 速度符号相关项，方向切换带滞环 `fDirHystN`；
- 输出：`fTensionN`、`bValid`（输入齐备且卷径在域内）、`eCause`、`bError`、`nErrId`。

**边界与安全条件**
- 除零：`fDiaM <= DL_FLOAT_EPS` 或 `fGearRatio <= DL_FLOAT_EPS` 或 `fEff <= DL_FLOAT_EPS` → `bValid := FALSE`、`fTensionN := 0.0` 并置构码（**不输出伪张力**，现场联锁会把伪张力当真值）；
- 卷径超域（`fDiaM > fDiaMaxM`）→ 退化保持上次有效值 + `bSaturated` 置位（信息级）；
- 输出限幅走显式 `MIN/MAX` 双侧钳位，不得只钳一侧；
- 解除式：复位沿 ∧ 组态合法 ∧ 当拍输入齐备。

**分工声明（头注释必写）**：本件是**观测/换算**层，不做张力闭环；`FB_DL_WindingTensionCtrl` 是控制层，二者不允许多实例互相喂值。

**来源标签**：t2-1-lgf Technology 子族｜**码位**：Algo 段

#### 7. `FB_DL_StictionCompensator` ｜ DL_Algo ｜ FB ｜ 中

**功能规格**
- 输入 `fCmd`（阀门/执行器指令 0~100%）、`fPos`（实际位置反馈）；输出 `fCmdOut`（补偿后指令）；
- 死区宽度在线估计：`|fPos - fPosPrev| < fEps` 且指令变化量 > `fDeadbandMin` 时，逐步增大 `_fDbEst`（带上限 `fDbMax`），反应恢复后慢速衰减；
- 脉动叠加（dither）：`fDitherAmp` + `tDitherPeriod`，幅值按死区估计比例钳位；
- 输出 `fDbEst`（死区估计值，供 HMI 趋势）、`bCompActive`、`eCause`、`bError`、`nErrId`。

**边界与安全条件**
- **补偿量绝对钳位**：`|fCmdOut - fCmd| <= fCompLimit`（硬限，防补偿把阀门推到危险位），超限置信息级；
- 死区估计越 `fDbMax` → 冻结并置维护级信息（不是故障：死区变大是磨损趋势）；
- `fDitherAmp <= 0`、`tDitherPeriod <= T#0S`、`fCompLimit <= 0.0` → 组态非法；
- `TON`（脉动相位）+ `R_TRIG` 无条件刷新；脉动相位用条件加减归一，**禁 MOD 负数**。

**分工声明**：与 `FB_DL_ValveStictionDetect`（Device，**诊断/分级**）分工 —— 本件**补偿**、不诊断、不引用 NE107 枚举。

**来源标签**：t2-5-modpid 参数域｜**码位**：Algo 段

#### 8. `FB_DL_LoopPerfIndex` ｜ DL_Algo ｜ FB ｜ 中

**功能规格**
- 输入 `fSp`（设定）/ `fPv`（测量）/ `bInAuto`；输出四指标：`fIae`、`fIse`、`fOvershootPct`（超调 %）、`fDecayRatio`（相邻峰比），外加 `nOscCount`（过零振荡计数，带去抖）；
- 分相：`eIdle`（非自动/未使能）→ `eCollect`（阶跃后窗口采集）→ `eEval`（出指标）→ `eDone`；
- **只出指标与建议档 `eTuneHint`（偏快/合适/偏慢/振荡），不做自整定**（自整定属主为 `FB_DL_RelayAutoTune` / `FB_DL_AutoTuneRelay`）。

**边界与安全条件**
- 阶跃判据用容差（`|ΔfSp| > fStepMin`），浮点禁判等；
- 窗口到时由 `TON` 单点置位；能量积分用 LREAL 中间量防 REAL 累积溢出；
- 测量非有限 → 该拍剔除并计数，连续越限置故障；
- `fStepMin <= 0.0`、`tWindow <= T#0S` → 组态非法；
- 解除式：复位沿 ∧ 组态合法 ∧ 非自动态（`NOT bInAuto` 是解除可达的必要条件之一，不得写成恒假组合）。

**来源标签**：t2-5-modpid 参数域｜**码位**：Algo 段

#### 9. `FB_DL_ThermalRampPredict` ｜ DL_Algo ｜ FB ｜ 中

**功能规格**
- 一阶热模型：`dT/dt = (u*K - (T - Tamb))/tau`；据当前温度与设定推断「到达目标所需剩余时间 `tRemain`」与「预测超调量」；
- 前馈偏移输出 `fFfBias`（距目标 `fLeadBand` 内开始减功率，防超调）；
- 时间常数在线修正：实测斜率与模型斜率偏差持续超阈值 → 按比例微调 `_fTau`（带上下限钳位）。

**边界与安全条件**
- `tau <= T#0S`、`fGainK <= 0.0`、`fLeadBand <= 0.0` → 组态非法；
- `tRemain` 计算需防除零（`dT/dt ≈ 0` 时输出 `DL_TIME_INF` 哨兵并置 `bNoTrend`，不得输出 T#0S 冒充"马上到"）；
- 前馈偏置双侧钳位 `[0, fFfBiasMax]`；
- 解除式：复位沿 ∧ 组态合法 ∧ 非 `bNoTrend`（当拍量）。

**分工**：与 `FB_DL_DryingOvenZone` / `FB_DL_CvdTempRamp`（分区控温与曲线执行）分工 —— 本件只出「预测与前馈偏置」，不闭环、不持曲线。

**来源标签**：t2-1-lgf Technology 子族｜**码位**：Algo 段

#### 10. `FB_DL_AxisDualFeedbackGuard` ｜ DL_Motion ｜ FB ｜ 中

**功能规格**
- 双反馈交叉校核：`fPosMotor`（电机侧位置）与 `fPosLoad`（负载侧尺/光栅位置），换算到同一工程单位后求偏差 `fDev`；
- 分级：`|fDev|` 超 `fDevWarn` → 维护级预警；超 `fDevAlarm` 且持续 `tDevConfirm` → 故障锁存；
- 极性装反识别：偏差随运动方向同号且斜率超阈值 → `eCause = ePolarity`（区别于打滑）；
- 输出：`fDev` / `eCause` / `bWarn` / `bError` / `nErrId`。

**边界与安全条件**
- 比例系数 `fScaleLoad`/`fScaleMotor` 为 0 → 组态非法（防除零/防零增益静默）；
- **不定义轴状态枚举、不发运动指令**（轴状态唯一属主 `I_DL_MotionAxis`）；
- `TON` 两枚（预警/故障确认）+ `R_TRIG` 无条件刷新；
- 解除式：复位沿 ∧ 组态合法 ∧ `|fDev| < fDevWarn`（当拍量）。

**分工**：与 `FB_DL_GantrySyncAxis`（双**轴**同步偏差）分工 —— 本件是**单轴双反馈**（电机 vs 负载）。

**来源标签**：t1-6-plcopen｜**码位**：Motion 段

---

### 批 3（Motion 4 + Device 1）

#### 11. `FB_DL_AxisSs1StopSeq` ｜ DL_Motion ｜ FB ｜ 中

**功能规格**
- SS1 类停止时序：`eIdle` → `eDecel`（发减速停止请求，监视速度降到 `fZeroSpeedThr`）→ `eSettle`（到位/零速稳定 `tSettleTime`）→ `eStoRequest`（输出 `bStoRequest := TRUE`）→ `eDone`；
- 任一步超时（`tDecelMax` / `tSettleMax`）→ `eFault` 并置码，**且 `bStoRequest` 仍置真**（安全侧：宁可切转矩也不放任轴继续动）；
- 输出：`bStoRequest` / `fSpeedAtStop` / `eState` / `eCause` / `bError` / `nErrId`。

**边界与安全条件**
- **头注释必写**：「本件只做停止时序与 STO 请求位，**不实现任何安全认证功能**（ISO 13849/IEC 62061 认证不在本库范围）」；
- 速度阈值 `fZeroSpeedThr <= 0.0`、超时 ≤ `T#0S` → 组态非法，且非法时 `bStoRequest` 直接置真（安全侧优先于组态）；
- 零速判据用容差式；`TON` 三枚 + `R_TRIG` 无条件刷新；
- 解除式：复位沿 ∧ 组态合法 ∧ 速度快照已在阈值内（当拍量）。

**来源标签**：t1-6-plcopen + IEC 60204-1 公开停止类别语义｜**码位**：Motion 段

#### 12. `FB_DL_AxisTeachOffset` ｜ DL_Motion ｜ FB ｜ 低

**功能规格**
- 示教：`bTeach` 上升沿锁存当前 `fPosAct` 到 `_fTaughtPos`；`bApplyOffset` 上升沿把 `fOffsetValue` 存入配方偏移槽；
- 输出：`fTaughtPos` / `fOffsetApplied` / `bTeachOk` / `eCause` / `bError` / `nErrId`；
- 越软限拦截：目标位（示教位 + 偏移）超 `fSoftLo`/`fSoftHi` → 拒绝应用并置码，**原偏移保持不被覆盖**（不得先写后判）。

**边界与安全条件**
- `fSoftHi <= fSoftLo` → 组态非法；
- 示教只在 `bAxisStandstill`（外部注入静止位）为真时受理，运动中示教 → 拒绝并置信息级（防采到抖动位置）；
- 两枚 `R_TRIG` 无条件刷新；解除式：复位沿 ∧ 组态合法 ∧ 越限条件已解除（当拍量）。

**来源标签**：t1-6-plcopen｜**码位**：Motion 段

#### 13. `FB_DL_AxisInertiaIdent` ｜ DL_Motion ｜ FB ｜ 高

**功能规格**
- 加速段多元回归：采集 `(fAcc, fTorque)` 样本对，最小二乘拟合 `T = J·a + Tf` 得惯量 `J` 与摩擦转矩 `Tf`；
- 采样门限：`|fAcc| >= fAccMin` 才纳入样本；样本数 < `nSampleMin` → 不出结果；
- 置信度：残差均方根 `fRms` 超 `fRmsMax` → `bConfident := FALSE`（照出结果但标不可信，不静默）；
- 结果冻结 `bFreeze` 时不再更新，`fInertiaOut` 保持（供调试比对）。

**边界与安全条件**
- 回归分母（`Σ(a²) − (Σa)²/n`）必须防零/防病态：`<= DL_FLOAT_EPS` → 判样本不可分（如全等加速度）→ 置信息级并保持上次结果；
- 用 LREAL 累加防精度丢失；样本环形缓冲下标先判边界；
- `fAccMin <= 0.0`、`nSampleMin = 0`、`fRmsMax <= 0.0` → 组态非法；
- 解除式：复位沿 ∧ 组态合法 ∧ 分母非病态（当拍量）。

**来源标签**：t2-4-s7-motion｜**码位**：Motion 段

#### 14. `FB_DL_AxisRotaryShortPath` ｜ DL_Motion ｜ FB ｜ 中

**功能规格**
- 输入 `fPosAct`（当前，可为任意圈数域）、`fTargetDeg`（0~360 目标）、`fSoftLoDeg`/`fSoftHiDeg`（圈域软限）、`bCwOnly`（单向模式）；输出 `bShortestCw`（转向建议）、`fTargetAbs`（加圈后的绝对目标）、`nTurnIndex`；
- 最短路径：`d := 目标 - 当前归一化角`，`d > 180°` 走反向、`d < -180°` 走正向；**正好 180° 时按 `bCwOnly` 与「正方向优先」约定确定**（约定写进头注释，不得留空）；
- 软限钳制：加圈后若越软限 → 尝试另一圈数；仍越限 → 拒绝并置码。

**边界与安全条件**
- 归一化一律**条件加减**，禁 `MOD`（负数取余三平台不一致，R10/R48 铁律）；
- 圈数域用 DINT 且钳位（防长周期累计溢出），加法前先判溢出；
- **整数进位点必推两向量**：目标与当前正好整除 360° 时，`nTurnIndex` 不得跳圈；`上限 + 1°` 时不得回绕到下限（R149 终审两式 2）；
- 解除式：复位沿 ∧ 组态合法 ∧ 目标已在软限内（当拍量）。

**来源标签**：t1-6-plcopen｜**码位**：Motion 段

#### 15. `FB_DL_SafetyRelayFeedback` ｜ DL_Device ｜ FB ｜ 中

**功能规格**
- 双通道反馈一致性：`bFbCh1` / `bFbCh2` 与指令 `bCmd`；正常应同步动作；
- 判定：指令变化后 `tSyncWin` 内两通道不一致 → 通道不同步故障；仅单通道跟随 → 该通道失效故障（`eCause` 区分 Ch1/Ch2）；
- 常闭回路断开（`bFbCh1 = bFbCh2 = FALSE` 而指令为 FALSE 时应为 TRUE — 由 `bNcLogic` 组态位决定语义）→ `eCause = eNcOpen`；
- 输出：`eCause` / `bSyncOk` / `bError` / `nErrId`，并**引用 `E_DL_Ne107Status` 唯一属主**输出 `eHealth`（不自造健康枚举；属主文件实测 = `C:\Library\DL_Device\I_DL_DeviceHealth.st` L91，只引用不重复声明）。

**边界与安全条件**
- `tSyncWin <= T#0S` → 组态非法，且非法时 `eHealth := eFailure`（保守）；
- **不实现安全认证功能**（头注释声明）；
- `TON` 两枚 + `R_TRIG` 无条件刷新；
- 解除式：复位沿 ∧ 组态合法 ∧ 两通道当前一致（当拍量）。

**来源标签**：t2-8-isa182 安全回路一致性语义（NE107 出口引用唯一属主）｜**码位**：Device 段，**避开 0590~0599**

---

### 批 4（Device 2 + Process 3）

#### 16. `FB_DL_ContactorWeldDetect` ｜ DL_Device ｜ FB ｜ 低

**功能规格**
- 熔焊检测：`bCmdClose`（指令）+ `bFbClosed`（主触点/辅助触点反馈）；
- 断开指令后 `tReleaseMax` 内反馈仍为 1 → 判熔焊 `eCause = eWeld`，故障锁存；
- 闭合指令后 `tPickupMax` 内无反馈 → 判触点不吸合 `eCause = eNoPickup`；
- 输出：`bWeldSuspect` / `eCause` / `bError` / `nErrId` / `eHealth`（引用 NE107 属主 `E_DL_Ne107Status`，属主文件 `DL_Device\I_DL_DeviceHealth.st`）。

**边界与安全条件**
- 熔焊为**不可自恢复故障**：解除式必须写「复位沿 ∧ 反馈已回落」；若反馈真实熔焊则复位不解锁（正确行为，须在头注释写明「复位不解锁是设计意图」）；
- `tReleaseMax`/`tPickupMax` ≤ `T#0S` → 组态非法；
- TON 两枚无条件刷新。

**来源标签**：t2-6-rockwell-aoi 设备级粒度｜**码位**：Device 段，避开 0590~0599

#### 17. `FB_DL_FlowSwitchResponseCheck` ｜ DL_Device ｜ FB ｜ 低

**功能规格**
- 校验流量开关**自身响应**：`bRunCmd`（泵/阀运行指令）上升沿起 `tRespWin` 内应出现 `bFlowSw` 上升沿；
- 未出现 → `eCause = eNoResponse`（开关卡死/管路堵塞/接线断）；
- 指令撤销后 `tDropWin` 内流量信号未回落 → `eCause = eStuckOn`（开关粘连）；
- 输出：`bSwHealthy` / `tRespMeasured`（实测响应时间，供趋势）/ `eCause` / `bError` / `nErrId`。

**边界与安全条件**
- 本件**不判干转**（干转属主 `FB_DL_PumpDryRunGuard` / `FB_DL_PumpDryRunProtect`），头注释必写分工；
- `tRespWin`/`tDropWin` ≤ `T#0S` → 组态非法；
- 响应时间测量用 TON 的 ET 锁存（锁存后不再实时读 ET，R38 范式）；
- 解除式：复位沿 ∧ 组态合法 ∧ 当拍「指令与反馈同相」（即不处于任一异常窗）。

**来源标签**：t2-2-lbp 命令-监视-判定三段｜**码位**：Device 段，避开 0590~0599

#### 18. `FB_DL_SlurryMixingSeq` ｜ DL_Process ｜ FB ｜ 高

**功能规格**
- 四相顺控：`eIdle` → `eFill`（加料：料位/重量达窗）→ `eDisperse`（高速分散：转速达窗 + 时间 `tDisperse`）→ `eDeair`（真空脱泡：真空度达窗 + 时间 `tDeair`）→ `eDischarge`（出料：出料阀开 + 料位下限）→ `eDone`；
- 相内监视：温升速率超 `fTempRiseMax` → 故障（浆料过热会凝胶）；转速偏差持续超 `fSpeedTol` → 故障；
- 每相独立超时（`tFillMax` / `tDisperseMax` / `tDeairMax` / `tDischargeMax`）。

**边界与安全条件**
- 单总码 + `eCause` 归因（组态非法 / 加料超时 / 转速失速 / 真空不足 / 温升超限 / 出料超时）；
- **撤启动（`bStart` 落）在任意执行相 → 直接进 `eDischarge` 安全收料**，不得停在分散相（R98 双出口范式）；
- 组态闸：任一容差 ≤0、任一时长 ≤`T#0S`、`fLevelHi <= fLevelLo` → 故障锁存；
- 4 枚 `TON`（相计时）+ 1 枚 `R_TRIG`（复位）**全部段 0 无条件刷新**，IN 由相位派生（R228A/B 高危区：本件 4 个 TON 是本轮最高密度件，必须逐实例核对）；
- 解除式全当拍量，且故障相迁出唯一路径 = 复位沿。

**分工声明**：与 `FB_DL_SlurryStirrerCtrl`（Device，**单机搅拌器驱动/转速**）分工 —— 本件是**批次相序编排**，不直接驱动电机。

**来源标签**：自研行业池（锂电前段）｜**码位**：Process 段

#### 19. `FB_DL_FrameSealDispenseSeq` ｜ DL_Process ｜ FB ｜ 中

**功能规格**
- 装框打胶顺控：`eHome`（打胶头回参考）→ `ePurge`（预挤胶，废胶接料）→ `eDispense`（分段打胶：按 `nSegCount` 段推进，每段监视胶量/胶压）→ `ePress`（压合到位）→ `eCure`（固化窗计时）→ `eDone`；
- 胶量校核：每段实测胶量 `fGlueDoseG` 与目标差超 `fDoseTolPct` → 段级 NG（累计 `nNgSegCount`）；任一段 NG → 全线判 NG 但**继续打完剩余段**（不中断，避免半框报废——头注释写清这一取舍）；
- 断点检测：`bGlueFlow` 在 `eDispense` 中连续 `tFlowGapMax` 无信号 → 判断胶故障并**立即停止打胶并锁存**（安全侧：断胶继续走会做出废件且可能漏胶到设备）。

**边界与安全条件**
- 单总码 + `eCause`（组态非法 / 回参超时 / 胶量超差 / 断胶 / 压合超时 / 固化超时）；
- `fDoseTolPct <= 0`、`nSegCount = 0`、任一时长 ≤ `T#0S` → 组态非法；
- 4 枚 TON + 2 枚 R_TRIG 段 0 无条件刷新；
- 解除式：复位沿 ∧ 组态合法 ∧ 无断胶（当拍量）；**NG 计数为锁存量，复位不清零**（批次台账语义，须在头注释声明）。

**来源标签**：自研行业池（光伏组件）｜**码位**：Process 段

#### 20. `FB_DL_BoilerBlowdownSeq` ｜ DL_Process ｜ FB ｜ 中

**功能规格**
- 排污顺控：触发源三选（定时 `tInterval` 到 / 电导率超 `fCondLimitUs` / 手动 `bManTrigger`）→ `eOpen`（开排污阀，时长 `tBlowTime`）→ `eSettle`（关阀后稳定 `tSettleTime`）→ `eDone`；
- 联锁：低水位 `bLevelLow` 为真 → **禁止开启**（干烧风险），已开则立即关阀并置故障；排污期间水位持续下降超 `fLevelDropMax` → 中止；
- 输出：`bValveCmd` / `nBlowCount`（累计排污次数）/ `eCause` / `bError` / `nErrId`。

**边界与安全条件**
- `tBlowTime <= T#0S`、`tInterval <= T#0S`、`fCondLimitUs <= 0.0`、`fLevelDropMax <= 0.0` → 组态非法，且非法时 `bValveCmd := FALSE`（安全侧：阀关）；
- 排污水量/时长上限硬钳位（单次最长 `tBlowMax`），防卡阀长时间排污抽空锅炉；
- `TON` 三枚 + `R_TRIG` 三枚段 0 无条件刷新；
- 解除式：复位沿 ∧ 组态合法 ∧ 水位已恢复（当拍量）。

**来源标签**：t1-2-oscat-building 公用工程语义｜**码位**：Process 段

---

## 2 P0 返修规格（2 件，先于 20 件新件执行）

> 依据：`BATTLE_REPORT_R44.md` L18~L19 的终审挂账。**禁止动对外引脚契约**，只改内部判据与注释，版本 PATCH。

### 2.1 `C:\Library\DL_Process\FB_DL_CalenderRollPress.st` ｜ v1.0.0 → v1.0.1 ｜ 中危

**缺陷定性（R281）**：双侧同步判据**缺相位因子**，在 `eIdle` / `eRelease` 相可误锁故障总码 `16#0005_039F`。

**逐行定位**

| 行号 | 现状 | 问题 |
|---|---|---|
| L138 | `IF (NOT _bFault) AND (ABS(_fGapDev) > fGapSyncMaxMm) THEN` | 判据**全相生效**：无相位限定、无 `bStart` 限定 |
| L98 | `_fGapDev := fGapLeftMm - fGapRightMm;` | 偏差当拍量本身无问题，问题在判据侧引用它 |
| L102-103 | `_bCfgBad := …` | 组态闸不含「相位」概念，无法替代相位因子 |
| L155 | 段 4 解除式 | 与相位无关，本身不缺陷（见修法 4 的说明） |
| L14-19 | 头注释边界声明③ | 只写「偏差超限单独归因 eGapSync」，**未声明相位范围**，属规格漏项 |

**误锁成因（现场可复现路径）**
1. `eIdle`：未使能时液压卸压，两侧辊缝机械先后回位，`|左−右|` 常达数百 µm，远超 `fGapSyncMaxMm`（默认 10 µm）→ **上电即报 039F**；
2. `eRelease`：抬辊过程两侧回程速度不同步 → 每次循环收尾报 039F，且 `eDone` 永远到不了；
3. 因 `eFault` 唯一迁出路径是 `bReset` 上升沿，误锁后产线每次都要人工复位，掩盖真故障。

**修法（逐条落）**
1. **段 0 新增相位因子当拍量**（放在 L98 之后、L100 之前）：
   ```iecst
   _bSyncWin := bStart AND ((_eState = E_DL_CrpState.eGapSet)
                          OR (_eState = E_DL_CrpState.eBarPress)
                          OR (_eState = E_DL_CrpState.eRun));   // 同步判据窗：仅在压下/建压/走带且启动电平在效时判同步 [-] / Sync window
   ```
2. **声明区 VAR 增一行**（L87 附近）：
   ```iecst
   _bSyncWin : BOOL;   // 双侧同步判据窗当拍量 [-]（单拍量，不入锁存清单） / Sync criterion window (per-scan)
   ```
3. **L138 判据加窗**：
   ```iecst
   IF (NOT _bFault) AND _bSyncWin AND (ABS(_fGapDev) > fGapSyncMaxMm) THEN   // 仅同步窗内判 / Only inside sync window
   ```
4. **段 4 解除式（L155）保持四因子不变**——不得追加 `NOT _bSyncWin`：复位当拍 `_eState` 仍为 `eFault`，`_bSyncWin` 恒假，追加即写恒真冗余；且复位后 `_eState` 回 `eIdle`，同步窗恒假 → 不复锁，解除可达性成立（终审两式 1 自证写进注释）。
5. **头注释边界③改写**（L17）：`③ 双侧同步偏差 |左-右| > fGapSyncMaxMm，仅在 eGapSet / eBarPress / eRun 且 bStart 为真时判定；eIdle / eRelease / eDone 辊缝机械张开，偏差属正常工况不判`。
6. **修订历史 +1 行**：`2026-11-19  v1.0.1  R45 返修（R281）：同步判据加相位窗 _bSyncWin，消除 eIdle/eRelease 误锁 039F；引脚契约零变更`。
7. **版本行**：`版本 Version : 1.0.0` → `1.0.1`。

**顺带项（同批可修，不升版式）**
- L102 组态闸对 NaN 无防护：`fGapTolMm` 等为 NaN 时 `<= 0.0` 恒假 → 组态闸失效。加 `(fGapTolMm <> fGapTolMm)` 自反判，并在头注释声明「NaN 自反判为浮点判等禁令的唯一例外」（否则机检 G6 误报）。
- L107 `tonRun` 复用 `tGapTmo`：引脚预算取舍，本轮**不改引脚**，但在头注释「接口 Interface」段补一句说明，避免下一轮被当成缺陷重报。

**验收向量（终审必推）**

| 向量 | 输入 | 期望 |
|---|---|---|
| V1 | `_eState=eIdle`、`bStart=FALSE`、`\|左−右\|=0.5mm` | 无 039F，`eState=eIdle` |
| V2 | `_eState=eGapSet`、`bStart=TRUE`、偏差 0.5 > 0.010 | 039F + `eCause=eGapSync` + `bError=TRUE` |
| V3 | `_eState=eRelease`、偏差 0.5、`tonRun` 到 | 无 039F；`eDone` + `nErrId=16#0005_04C7` 单拍 |
| V4 | V2 后 `bReset` 上升沿、组态合法、`tonGap.Q=FALSE` | `bError=FALSE`、`eState=eIdle`，**次拍不复锁** |

---

### 2.2 `C:\Library\DL_Process\FB_DL_IvCurveScan.st` ｜ v1.0.0 → v1.0.1 ｜ 轻危

**缺陷定性（R283）**：复位沿**作用域越界**——非故障相也清窗内极值与采样计数；另顺带修「`eDone` 相 FF 输出恒 0」。

**逐行定位**

| 行号 | 现状 | 问题 |
|---|---|---|
| L121-132 | `IF rtReset.Q THEN` 内无条件清 `_fVocV/_fIscA/_fPmaxW/_nSample` | 相位只在 `eFault` 才回 `eIdle`；若在 `eScan` 中复位，极值被清而 `tonScan` 继续计时、相位仍 `eScan` → 后半窗从零累积 |
| L109 | `tonScan(IN := (_eState = eScan), …)` | 相位不变则计时不重装，与「极值已清零」自相矛盾 |
| L145-156 | 段 3 判据用 `_nSample` / `FC_DL_IvFillFactorCalc` | 依赖被清零的量 → 截断窗结论 |
| L151-152 | 同一 FC **同参调用两次** | 冗余调用（若将来 FC 引入状态即为缺陷），且判据分散难审 |
| L203 | `fFfPu := FC_DL_IvFillFactorCalc(...)` 只在 `eEval` 相赋值 | 段 1（L116）每拍先清零 → 进 `eDone` 后 `fFfPu` 恒 0，而 `bCycleDone` 恰在 `eDone` 为真 → **完成相读到 FF=0**，与语义矛盾 |
| L19 | 头注释边界⑤ | 未声明复位沿作用域，属规格漏项 |

**修法（逐条落）**
1. **L121-132 按相分域改写**：
   ```iecst
   IF rtReset.Q THEN                                  // 复位沿（当拍量） / Reset edge
       _bFault := FALSE;                              // 清故障锁存位 / Clear fault latch
       _uFault := 16#0000_0000;                       // 清故障锁存码 / Clear fault code
       _eCause := E_DL_IvsCause.eNone;                // 清成因 / Clear cause
       IF _eState = E_DL_IvsState.eFault THEN         // 仅故障相做净重装 / Clean re-arm only from fault
           _fVocV := 0.0;       _fIscA := 0.0;
           _fPmaxW := 0.0;      _nSample := 0;
           _eState := E_DL_IvsState.eIdle;            // 故障相迁出唯一路径 / Sole exit from fault
       END_IF
   END_IF
   ```
   **非故障相一律不动**四量与相位（窗内量唯一重置点 = `eIdle → eScan` 迁移，L175-178）。
2. **FF 计算上移段 0**：新增 `_fFfPu : REAL; // FF 当拍量 [-]（段 0 单次求解，供判据与出口）`，在段 0 末尾 `_fFfPu := FC_DL_IvFillFactorCalc(fPmaxW := _fPmaxW, fVocV := _fVocV, fIscA := _fIscA);`。
3. **段 3 判据改用 `_fFfPu`**（删除 L151-152 的两次调用）。
4. **`eEval` 相（L203）**改为只读 `_fFfPu`（`IF (NOT _bFault) AND (_fFfPu >= 0.0) THEN …`），不再重复调用 FC。
5. **段 6 出口**：`fFfPu := _fFfPu;`，故障相仍强制 `0.0`（保安全侧），即把 L235 的 `fFfPu := 0.0` 保留在 `IF _bFault` 分支内。
6. **头注释边界新增⑦**：`⑦ 复位沿作用域：eFault 相内 = 清故障三件 + 净重装窗内量并回 eIdle；非故障相 = 仅清故障锁存三件，窗内量与相位不动；窗内量唯一重置点 = eIdle→eScan 迁移`。
7. **修订历史 +1 行** + **版本行 1.0.0 → 1.0.1**。
8. **L104-106 的 `<>` 自反判**：在头注释注明「NaN/Inf 自反检测为浮点判等禁令的唯一例外」，并告机检侧加白名单（否则 G6 误判）。

**验收向量**

| 向量 | 输入 | 期望 |
|---|---|---|
| V1 | `eScan` 中 `bReset` 上升沿 | `eState` 仍 `eScan`；`nSampleCount` 不回退；`tonScan` 不重装；无新码 |
| V2 | `eScan` 中制造非有限输入 → 03A2/`eNonFinite` 锁存 → `bReset`（非有限已消失） | `eState=eIdle`、四量清零、`bError=FALSE` |
| V3 | `eDone` 相 | `fFfPu = 0.72`（≠0）、`bCycleDone=TRUE`、`nErrId=16#0005_04CA` 单拍 |
| V4 | `eFault` 中 `bReset` + 组态合法 + 非有限消失 | 解除可达（`eFault` 相 `tonScan.IN` 恒假 → `Q` 恒假，解除式必可达） |

---

## 3 七项红线自检清单（每件落盘前逐项打勾，任一不过禁止入库）

- [ ] **① 零全局耦合**：全文零 `GVL` 访问、零 `VAR_EXTERNAL`；外部数据一律经 `VAR_INPUT` / `VAR_OUTPUT` / `VAR_IN_OUT` 或 `I_DL_` 接口注入。
- [ ] **② 零硬编码地址**：全文零 `%IX` / `%QX` / `%IW` / `%QW` / `%MW`（注释里的示范写法同样不允许）。
- [ ] **③ 纯 IEC 61131-3 跨平台**：仅 `Standard.library` 与标准类型；零厂商库（`TcXxx` / `SysXxx` / `SM3_` / `__SYSTEM`）；零 `POINTER TO` / `REFERENCE TO`；零隐式转换；CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop 三平台可直接编译。
- [ ] **④ 防御性编程**：浮点禁 `=` 判等（容差式 `ABS(a-b) < eps`）；除法先判除子且除零有出口；数组访问先判上下界；`WHILE` 带守卫计数器且超限置码跳出；整数溢出前判（饱和或拒收，不静默回绕）。
- [ ] **⑤ 变量同行中英双语注释**：声明区**每个变量、每个枚举项**同行 `//` 中文物理意义 + 英文短语 + 工程单位（`mm` / `µm` / `ms` / `s` / `kN/cm` / `µm` / `V` / `A` / `p.u.` / `%` / `rpm` / `deg`）；引脚注释含取值范围与默认行为。
- [ ] **⑥ ENUM + CASE + ELSE 兜底**：状态机必须 `ENUM` + `CASE`；`ELSE` 兜底落故障态并置码；**枚举全部成员在 CASE 中有显式标签**（`eFault` 不得只靠 ELSE 兜底，R128）。
- [ ] **⑦ TON / TOF / TP / R_TRIG / CTU 无条件周期刷新**：所有定时器/边沿实例在**主周期段 0** 无条件调用，`IN` 由相位或当拍量派生；**严禁**放在任何 `IF` / `CASE` 分支内（R228A）；相内定时器必须核对「跨相复位」语义（R228B）。

> 机检附加三条（R45 新增，见 `ROUND_PLAN_R45.md` §2 #15~#17）：枚举 ⊆ CASE 标签、安全侧赋值来源、单拍脉冲撤销点。

---

## 4 机检口径先固化（跑时不改）

### 4.1 溯源短语（文件头 `溯源 Origin` 字段，二选一，不得自创第三种）

1. **T0 件（`iec-std-wrapper` 来源标签）统一用**：`IEC 61131-3 标准语义的道莅防御性实现`；
   —— **本轮实测 T0 八组已全 ✔ 收口，20 件中 T0 件 = 0**，故本轮该短语仅作为常设口径保留（`FC_DL_CubicBezierEval` 属 t2-1-lgf 数学子族，用第 2 式）。
2. **非 T0 件统一用**：`道莅自研 clean-room（参考 XX 分类与参数域，零代码行复制）`，其中 XX 必须与 `RAW_NOTES_R45.md` 逐件账目的来源标签一致。

### 4.2 历史教训（逐条列，落盘前自查对照）

| # | 教训 | 正确写法 / 处置 |
|---|---|---|
| 1 | **枚举单冒号** | `TYPE` 内枚举成员必须 `eIdle := 0,`（**赋值号 `:=`**），单冒号 `:` 直接编译失败；成员间逗号、末项无逗号、`END_TYPE` 加分号 |
| 2 | **漏 `VAR_OUTPUT`** | 所有对外引脚必须在 `VAR_OUTPUT` 段声明；常见漏项是「内部算了但忘记出口」的镜像位与 `eCause`。落盘前对「段 6 出口单点映射」逐个赋值点名核对声明段 |
| 3 | **注释嵌套 `(* *)`** | IEC 61131-3 **不支持嵌套注释**；头注释块内不得再写 `(* … *)`，中文括注用 `〔〕` / `「」`；嵌套会造成注释提前截断、后续代码被吞 |
| 4 | **TON 跨相复位（R228A/B）** | 定时器 `IN` 必须由相位派生（如 `IN := (_eState = eXxx)`），且**实例调用点**在主周期段 0；离开该相 `IN` 自动落假 → `Q` 落假 → 解除式可达。本批 `SlurryMixingSeq`（4 TON）/`FrameSealDispenseSeq`（4 TON）/`BoilerBlowdownSeq`（3 TON）为最高密度件，逐实例核对 |
| 5 | **`eFault` 迁出链** | `eFault` 相内**只允许复位沿一条迁出路径**；`eFault` 必须有显式 CASE 标签（不可只靠 ELSE 兜底，R128/R44 挂账 6 件同类缺陷）；迁出目标固定为 `eIdle` |
| 6 | **LF 落盘转 CRLF** | 源码必须 **CRLF** 行尾；写盘后立即校验（`file`/字节扫描），JSONL 语料逐行 sha256 复验时不得因换行差异失配（历史 2 件已踩：`SCurveGenerator` / `PulseDirStepper`） |
| 7 | **单拍脉冲撤销点** | 信息码/完成沿必须段 1 预清零 + 唯一分支置位，禁跨拍残留（R44 `DeviceParamVerify` v1.0.1 范式） |
| 8 | **安全侧赋值来源** | 故障/越界/退化分支赋的安全值，不得引用「本闸正在判定的量」（会自证成立，如用被清零后的值再判一次） |

---

## 5 落盘路径与交付规则

- **路径**：`C:\Library\DL_<Category>\<POU名>.st`，**文件名 = POU 名**（含前缀，PascalCase），例：`C:\Library\DL_Algo\FB_DL_TensionObserver.st`。
- **行尾：CRLF**（写盘后字节级校验）；编码 UTF-8（无 BOM）；文件结尾保留一个空行。
- **一个文件一个 POU**；接口与其枚举可同文件但须在头注释说明归属。
- **临时/脚本文件**：`C:\Library\_Staging_Raw\2026-11-19\`，禁止落入 `DL_*` 正式目录。
- **`_Staging_Raw` 原始素材永不作为交付物**，也永不被正式目录直接引用。
- **禁止词**：`TODO` / `FIXME` / `XXX` / `待补` / `placeholder`（含头注释）。
- **码位**：落盘前用「头部 ∪ 全文」双扫描实测自取；Device 件避开 `0590~0599`；新件码段与子库既有段不连续时，**头注释必须写明分段理由**（R192）。
- **收工必交**：`件名 | PASS/FAIL | 失败项号` 机检记账表 + 更新 `RAW_NOTES_R45.md` 账目；FAIL 件当场返修，不得带入终审。
