# ROUND_PLAN_R36 — 阶段一派单（2026-11-18）

> **轮次**：R36（常态轮，非纯 T0 轮）
> **目标数**：20 件新件（真池足额，无凑数、无降标）
> **本轮性质**：只做阶段一「盘点与锁定」；编码、终审、入册不在本轮范围。
> **检索预算**：WebSearch **0/3（零检索轮）**——来源 100% 取自 `ROADMAP.md` 未勾选真池与 `SOURCE_HUNTING_MATRIX.md` §5 既有 ◐ 行语义，不新增外部源、不抓任何仓库、零代码行复制。逐件账目见 `RAW_NOTES_R36.md`。

---

## 0 统计快照（实测，脚本读 `INDEX_REGISTRY.json` v2.27.0）

| 口径 | 数值 |
|---|---|
| 总库已注册 | **637 / 10,000**（registry `total_components` = 637，磁盘 `DL_*/*.st` = 637，三向一致 ✅） |
| 今日（2026-11-18）已入册 | **118 / 200**（`registered_at` 日期聚合实测） |
| 本轮目标 | **+20 → 658 / 10,000** |
| 今日预计收尾 | 118 + 20 = **138 / 200** |
| 距下一里程碑（1,000） | **1,000 − 658 = 342 件** |
| 子库分布 | `DL_MathData` 174 ｜ `DL_Process` 131 ｜ `DL_Device` 116 ｜ `DL_Base` 75 ｜ `DL_Algo` 62 ｜ `DL_Motion` 60 |
| ROADMAP 未勾选 | **190 条 ≥ 30** → 按步骤 7 规则**本轮不补条**（留待真池跌破 30 时集中补写） |

> **平衡口径**：`DL_Motion`(60) 与 `DL_Algo`(62) 为全库最低两库，本轮各补 2 件；`DL_MathData`(174) 为最高库，仅补 2 件且均为「高频缺失原子」（频谱单点、样条插值），不做同类堆量。`DL_Base` 本轮 0 件——T0 真池仅剩 `FC_DL_ShlDwordEx`/`ShrDwordEx`，R34 已裁定「与既有 `FC_DL_ShlEx`/`ShrEx` 同义，弃立项」，沿用该裁定，不为凑数重开。

---

## 1 目标组件清单（20 件，按批次排序）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_HarmonicSpectrumBin` | DL_MathData | FC | 单频点 DFT（Goertzel）幅值/相位提取，用于振动与电流谐波阶次跟踪（纯函数、无状态） | `t2-1-lgf-math` | 中 | 1 |
| 2 | `FC_DL_CubicSplineInterp` | DL_MathData | FC | 自然三次样条插值与斜率输出（非等距节点 + 节点防重防倒序） | `t2-1-lgf-math` | 中 | 1 |
| 3 | `FB_DL_DisturbanceObserver` | DL_Algo | FB | 模型法负载扰动观测器（标称模型逆 + 一阶低通 Q 滤波 → 扰动估计与补偿量） | `t2-4-s7-motion` | 高 | 1 |
| 4 | `FB_DL_ResonanceTrackNotch` | DL_Algo | FB | 谐振频率在线跟踪与自适应陷波（相位过零判据 + 频率窗钳制 + 松弛回退） | `t1-6-plcopen` | 高 | 1 |
| 5 | `FB_DL_LineShaftClutch` | DL_Motion | FB | 电子 line shaft 离合（相位对齐后咬合/脱开，含咬合斜坡与滑差监视） | `t2-4-s7-motion` | 高 | 1 |
| 6 | `FB_DL_FlyingCutSync` | DL_Motion | FB | 飞剪同步切断（从轴追赶同步窗 + 切窗区间判定 + 回程重装） | `t1-6-plcopen` | 高 | 2 |
| 7 | `FB_DL_WaferCoolChuck` | DL_Device | FB | 静电卡盘吸附-温控联锁（吸附确认后方可投温控，释放须温度降到脱附门限以下） | `t2-2-lbp` | 中 | 2 |
| 8 | `FB_DL_CurtainEFEMZone` | DL_Device | FB | EFEM 作业区光幕分区屏蔽（4 传感器判向 + 屏蔽窗时限 + 屏蔽期自检） | `t1-5-tcopen` | 高 | 2 |
| 9 | `FB_DL_VentPurgeDuty` | DL_Device | FB | 尾气处理双塔轮值切换（吸附/脱附轮换 + 穿透预警 + 单塔故障禁切） | `t2-8-isa88` | 中 | 2 |
| 10 | `FB_DL_SlurryLevelBank` | DL_Device | FB | 浆料罐点式料位巡检组（多实例扇入 + fail-safe 方向审查 + 传感器短路/断路判别） | `t2-8-isa182` | 中 | 2 |
| 11 | `FB_DL_FoupPurgeN2Flow` | DL_Device | FB | FOUP 氮气吹扫流量-露点双判据监视（吹扫建立时限 + 露点越窗分级） | `t2-1-lgf-measurement` | 中 | 3 |
| 12 | `FB_DL_CartonErectVacMonitor` | DL_Device | FB | 开箱吸盘真空建立时长趋势诊断（建立时长基线 + 衰减趋势 → 吸盘老化预警） | `t2-1-lgf-measurement` | 中 | 3 |
| 13 | `FB_DL_CoderRibbonLife` | DL_Device | FB | 打码色带寿命与浓度衰减监视（打印次数累计 + 浓度趋势双口径换带提示） | `t2-1-lgf-technology` | 中 | 3 |
| 14 | `FB_DL_VavBoxZeroCal` | DL_Device | FB | 变风量末端风量零点标定（静流稳定判据 + 两点标定 + 标定期冻结调节） | `t1-2-oscat-building` | 中 | 3 |
| 15 | `FB_DL_HeatSealProfile` | DL_Process | FB | 热封温度-压力-时间三参数配方曲线管理（段切换 + 超窗判废 + 配方校验） | `t2-7-packml` | 中 | 3 |
| 16 | `FB_DL_AhuEconomizer` | DL_Process | FB | 空调箱新风经济器（焓值/干球双判据切换 + 最小新风位 + 低温防冻锁定） | `t1-2-oscat-building` | 高 | 4 |
| 17 | `FB_DL_TerminalReheatSeq` | DL_Process | FB | 末端再热级联联锁（最小风量约束 + 再热上限级联 + 过热度保护） | `t1-2-oscat-building` | 中 | 4 |
| 18 | `FB_DL_RfReflectedMonitor` | DL_Process | FB | 射频电源正向/反射功率比监视与匹配器联动告警（仅监视，不闭环调谐） | `t2-1-lgf-measurement` | 中 | 4 |
| 19 | `FB_DL_StringSolderQuality` | DL_Process | FB | 串焊焊接质量在线判据（红外温度曲线特征窗 + 拉力抽检窗 + 逐通道分级） | `t2-1-lgf-technology` | 高 | 4 |
| 20 | `FB_DL_ModuleLamVacuumSeq` | DL_Process | FB | 组件层压真空顺控（抽气-加热-加压-放气四段 + 段超时升级 + 真空度联锁） | `t2-7-packml` | 高 | 4 |

**分布**：DL_Process 6 ｜ DL_Device 8 ｜ DL_Motion 2 ｜ DL_Algo 2 ｜ DL_MathData 2 ｜ DL_Base 0（T0 真池已尽，如实记 0，不虚账）。
**配额结论**：T2 标签 12 件（覆盖 `t2-1-lgf` / `t2-2-lbp` / `t2-4-s7-motion` / `t2-7-packml` / `t2-8-isa88` / `t2-8-isa182` 六族）、T1 标签 6 件（`t1-2-oscat-building` / `t1-5-tcopen` / `t1-6-plcopen` 三组）→ **硬约束「≥1 个 T2 组件族或 1 个 T1 组」双满足**。T0 未收口组配额如实取 0（真池仅余同义弃判项）。

---

## 2 码位窗口（实测 6 个无冲突窗口，写死本节，编码专家不得越窗）

> **实测方法**：对 `DL_*/*.st` 与全部 `*.md` 做 `16#NN_N_XX` 全量正则扫描（含正文常量，非仅头部 `码位 Code` 行），逐一确认下列 6 段在全库 0 命中。
> **既有占用（实测）**：`02_3_80`（`FB_DL_RfMatcherTune`，DL_Algo）｜`03_2_00~0A`（DL_Device 10 件）｜`04_0_A0~A1`（DL_Motion 2 件）｜`06_0_80~99`（DL_Process 26 件，其中 8C~99 为 R35 件）。
> **R35 撞码整改沿用**：Process `80~89`/`90~99` 两段已占满且 R35 已裁定 `90~99` 属错位段（R35 收口时起新件一律落在 `B0~B9`/`C0~C9`/`D0~D9`）。**本轮 Process 全部落在 `B0` 段，实测 `06_0_B*`/`C*`/`D*` 全库 0 命中，与既有占用零重叠。**

| 窗口 | 码段（闭区间） | 容量 | 归属 | 本轮占用 | 选段理由 |
|---|---|---|---|---|---|
| **W1** | `16#05_0_00` ~ `16#05_0_01` | 2 | DL_MathData | 序号 1、2 | `05` = DL_MathData 分类位，`05_0_*` 全库**首开**（该子库历史件未启用码位体系），从 `00` 起连续给号，不留空洞 |
| **W2** | `16#02_3_81` ~ `16#02_3_82` | 2 | DL_Algo | 序号 3、4 | `02` = DL_Algo，`02_3_80` 已被 `FB_DL_RfMatcherTune` 占用，紧接 `81/82` 续号 |
| **W3** | `16#04_0_A2` ~ `16#04_0_A3` | 2 | DL_Motion | 序号 5、6 | `04` = DL_Motion，`A0/A1` 已占（R34 件），`A2/A3` 续号，保持 `A` 段体例 |
| **W4** | `16#03_2_0B` ~ `16#03_2_0F` | 5 | DL_Device | 序号 7、8、9、10、11 | `03_2_00~0A` 已占，`0B~0F` 为首个连续空段（不与 `03_1_*` 正文常量段交叉） |
| **W5** | `16#03_2_10` ~ `16#03_2_12` | 3 | DL_Device | 序号 12、13、14 | `0B~0F` 用尽后进 `10` 段；**分段理由（R192）**：`03_2` 低半字节 `00~0F` 满，向上进位到 `1x` 是本段唯一不撞车走向，须在各件头注释「码位 Code」行注明「`03_2` 段 `00~0F` 已满，进位 `10` 段」 |
| **W6** | `16#06_0_B0` ~ `16#06_0_B5` | 6 | DL_Process | 序号 15~20 | **R35 撞码整改硬约束**：`80~89`/`90~99` 双段已满且 `90~99` 判为错位段，新件从 `B0` 起；`06_0_B*`/`C*`/`D*` 实测全库 0 命中 |

**窗口纪律（写死）**：
1. 一窗一件，**件内多码**（信息级/故障级细分）只能在本件格内 `+0x01` 递增，**不得跨入下一件格**；
2. 窗内空余格（W4 满、W5 空 `13` 空、W6 无余）保留登记，禁止顺手挪用；
3. 若编码期发现某件判据溢出本格，先报总监**改派相邻空窗**，不得就地连号；
4. 头注释「码位 Code」行格式必须与既有件一致：`码位 Code     : 16#NN_N_XX`。

---

## 3 批次切分（4 批 × 5 件，按依赖自底向上，批内无跨批新增依赖）

| 批次 | 序号 —— 组件名 | 批内依赖（全部为已注册件，禁新建依赖） |
|---|---|---|
| **批 1**（纯计算底噪层） | 1 `HarmonicSpectrumBin` ｜ 2 `CubicSplineInterp` ｜ 3 `DisturbanceObserver` ｜ 4 `ResonanceTrackNotch` ｜ 5 `LineShaftClutch` | `FC_DL_NthRoot` / `FB_DL_LowPassFilter` / `FB_DL_NotchFilter` / `FB_DL_RateLimiter` / `FB_DL_SignalStatistics` / `I_DL_MotionAxis` |
| **批 2**（运动 + 设备联锁） | 6 `FlyingCutSync` ｜ 7 `WaferCoolChuck` ｜ 8 `CurtainEFEMZone` ｜ 9 `VentPurgeDuty` ｜ 10 `SlurryLevelBank` | `FB_DL_ElectronicGear` / `FB_DL_MarkPositionLatch` / `FB_DL_SoftLimitGuard` / `I_DL_LightCurtain` / `FB_DL_SafetyLightCurtain` / `I_DL_VacuumGenerator` / `I_DL_TemperatureZone` / `I_DL_LevelSwitch` / `FB_DL_DutyStandbyRotation` / `FB_DL_InterlockMatrix` |
| **批 3**（设备诊断 + 首个工艺件） | 11 `FoupPurgeN2Flow` ｜ 12 `CartonErectVacMonitor` ｜ 13 `CoderRibbonLife` ｜ 14 `VavBoxZeroCal` ｜ 15 `HeatSealProfile` | `FB_DL_PulseFlowMeter` / `FC_DL_DewPointCalc` / `FB_DL_ToleranceWindow` / `FB_DL_SignalStatistics` / `FB_DL_RuntimeMeter` / `FC_DL_LinearScale` / `FB_DL_SignalDebounce` / `FB_DL_RampSoakProfile` / `FB_DL_StepSequencer` |
| **批 4**（工艺/暖通整段） | 16 `AhuEconomizer` ｜ 17 `TerminalReheatSeq` ｜ 18 `RfReflectedMonitor` ｜ 19 `StringSolderQuality` ｜ 20 `ModuleLamVacuumSeq` | `FC_DL_HumidAirEnthalpy` / `FB_DL_Hysteresis` / `FB_DL_SplitRangeControl` / `FB_DL_RateLimiter` / `FB_DL_SignalDebounce` / `FB_DL_SignalStatistics` / `FB_DL_ToleranceWindow` / `FB_DL_AlarmManager` / `FB_DL_StepSequencer` / `FB_DL_VacuumGaugeMux` |

---

## 4 每批需求规格（编码专家任务书）

### 批 1（纯计算底噪层，最独立，全部可离平台编译）

| # | 规格 |
|---|---|
| 1 | **`FC_DL_HarmonicSpectrumBin`**（DL_MathData/FC，纯函数）：输入 `afSampleBuffer`（采样窗，`ARRAY[0..N-1] OF LREAL`，N 由 `nWindowSize` 给出）、`fSampleRateHz`、`fTargetFreqHz`、`eWindowType`（矩形/Hann，枚举 `E_DL_SpectrumWindow`）；输出 `fMagnitude`（物理量单位随输入，峰值幅值）、`fPhaseDeg`（°）、`bValid`、`nErrId`。算法：Goertzel 单频点 DFT + 窗函数幅值修正（Hann 相干增益 0.5）+ 相位解卷。边界：`nWindowSize` 越界（<8 或 >数组上界）判无效置码；`fSampleRateHz <= 0` 防除零；`fTargetFreqHz` ≥ 奈奎斯特频率判无效（不混叠出假值）；窗内样本非有限（NaN/Inf）整窗无效；幅值 < `fMagFloor` 输出 0 并置「低于分辨力」信息码。 |
| 2 | **`FC_DL_CubicSplineInterp`**（DL_MathData/FC，纯函数）：输入 `afX`/`afY`（节点表）、`nPointCount`、`fQueryX`；输出 `fOutY`、`fOutSlope`、`bInRange`、`nErrId`。算法：自然三次样条（二阶导三对角求解，Thomas 追赶法，`WHILE` 带死锁计数器上限 = 节点数 + 1）。边界：`nPointCount < 2` 判无效；节点 X 非严格递增（含相等）拒绝求值并置码（不做静默排序）；`fQueryX` 越界 → 钳到端点、`bInRange := FALSE` 并**不外推**；三对角主元近零（`ABS(主元) < 1E-12`）判节点病态置码；节点数超 `nMaxNode` 组态上限拒绝（防静态数组越界）。 |
| 3 | **`FB_DL_DisturbanceObserver`**（DL_Algo/FB）：输入 `fCmdOut`（控制器输出，%）、`fMeasSpeed`（实测速度，rpm）、`fInertia`（kg·m²）、`fTorqueConst`（N·m/A）、`fQFilterTau`（s）；输出 `fDistTorqueEst`（N·m）、`fCompOut`（补偿量，%）、`bSaturated`、`bValid`、`eState`（`E_DL_ObserverState`：Idle/Run/Hold/Fault）。算法：标称模型逆（`J·dω/dt ÷ Kt`）与实测之差经一阶 Q 滤波得扰动估计，补偿量按 `fCompGain` 加权后限幅。边界：`fInertia`/`fTorqueConst`/`fQFilterTau` 任一 ≤ 0 判组态错置码且不投运（防除零）；速度信号为 0 且持续超 `tZeroSpeedHold`（本件声明常量 200 ms）时冻结估计器（静止段无可观测加速度，防止噪声灌入积分）；`bEnable` 下降沿清估计值与内部微分状态（R28-1 锁存/复位可达自检：解除式 = `bEnable` 上升沿 + `bReset`，两者均在引脚可满足）；输出限幅到 `fCompLimit`（%，默认 `VAR_INPUT` 而非硬编码）。 |
| 4 | **`FB_DL_ResonanceTrackNotch`**（DL_Algo/FB）：输入 `fSignal`（振动或电流反馈）、`fSampleDt`（s）、`fFreqMinHz`/`fFreqMaxHz`（搜索窗）、`nSettleCycles`；输出 `fResonanceHz`、`fTrackConfidence`（0~1）、`bLocked`、`nErrId`、`eState`。算法：二阶带通相位过零测周期 → 频率估计经滑动中值去野值 → 钳制到 `[fFreqMinHz, fFreqMaxHz]`；连续 `nSettleCycles` 次估计落在 ±`fLockBandHz` 内才 `bLocked`；锁定后失锁须连续 `nLostCycles` 次越带才降级（迟滞，防抖）。边界：`fSampleDt <= 0` 判组态错；`fFreqMinHz >= fFreqMaxHz` 判组态错置码不运行；搜索窗越奈奎斯特判无效；信号幅值 < `fAmpFloor` 不出频率结论（`bLocked := FALSE`，估计值保持但 `fTrackConfidence` 衰减）；频率跳变超 `fMaxSlewHzPerSec` 判野值丢弃并计数（计数超限置「跟踪发散」故障码）。 |
| 5 | **`FB_DL_LineShaftClutch`**（DL_Motion/FB）：注入 `iMasterAxis`/`iSlaveAxis`（`I_DL_MotionAxis`）；输入 `bEngageCmd`、`bDisengageCmd`、`fPhaseOffsetDeg`（°）、`fEngageRampTime`（s）、`fSlipLimitDeg`；输出 `bEngaged`、`fPhaseErrorDeg`（°）、`bSlipFault`、`eState`（`E_DL_ClutchState`：Idle/Aligning/Ramping/Engaged/Disengaging/Fault）。算法：对齐段把从轴相位拉至主轴的 `fPhaseOffsetDeg` 偏移，相位误差进入 `fAlignTolDeg`（本件声明常量 0.5°）后进咬合斜坡，斜坡完成置 `bEngaged`；咬合期相位误差超 `fSlipLimitDeg` 持续 `tSlipDebounce` → `bSlipFault` 且强制脱开。边界：两轴任何一方 `bError`/未使能则拒绝咬合置码；主从同轴（同一实例传引用）判组态错；`fEngageRampTime <= 0` 判组态错；脱开命令与咬合命令同拍 → 以脱开为安全优先并置码；解除路径自证：`bSlipFault` 解除式 = `bReset AND iMasterAxis.bStandstill AND iSlaveAxis.bStandstill`（三条件均可满足，R28-1 通过）。 |

### 批 2（运动同步 + 设备联锁）

| # | 规格 |
|---|---|
| 6 | **`FB_DL_FlyingCutSync`**（DL_Motion/FB）：注入 `iMasterAxis`（料带线轴）/`iCutAxis`（刀轴）；输入 `fCutLengthMm`、`fSyncWindowStartMm`/`fSyncWindowEndMm`（切窗区间）、`fCutOverlapRatio`、`tCutDwell`（ms）；输出 `bCutCmd`（单拍脉冲，注释标注「脉冲语义：置位 1 个 PLC 周期」）、`bInSyncWindow`、`fSyncErrorMm`、`nCutCount`（UDINT）、`eState`。算法：MASTER 位置取模 `fCutLengthMm` 得相位，进入窗口后刀轴按电子齿轮追赶，同步误差进 `fSyncTolMm` 才允许下刀；切完回程重装。边界：`fCutLengthMm <= 0` 防除零判组态错；窗口起止倒置或窗口宽 ≤ 0 判组态错不运行；未同步时**禁止** `bCutCmd`（互锁在内部，不外抛）；`nCutCount` 到 `uCountPreset` 后 `bPresetReached` 置位（UDINT 上限前饱和，**不给 TRUNC(x)+1 型写法**）；切窗内主轴反转立即判废并置码。 |
| 7 | **`FB_DL_WaferCoolChuck`**（DL_Device/FB）：注入 `iVac`（`I_DL_VacuumGenerator`）/`iTempZone`（`I_DL_TemperatureZone`）；输入 `bClampCmd`、`bReleaseCmd`、`fTempAttachMaxC`（脱附允许上限，°C）、`tAttachConfirm`（ms）；输出 `bClamped`、`bTempEnable`、`bInterlockBlocked`、`nErrId`、`eState`（`E_DL_ChuckState`）。算法：吸附确认（真空度达 `fVacConfirmKpa` 且持续 `tAttachConfirm`）才允许 `bTempEnable`；释放须温度 ≤ `fTempAttachMaxC`（迟滞 2 °C）且真空已破；吸附失败重试 `nRetryMax` 次后锁存。边界：`fTempAttachMaxC` 与环境上限倒置判组态错；**区分「吸附中温度越上限」与「未吸附」两路故障码**（不得共用一号）；解除式自证：温度回落 + `bReset`；释放期真空未破不推进状态（带 `tReleaseTimeout` 超时升级）。 |
| 8 | **`FB_DL_CurtainEFEMZone`**（DL_Device/FB）：注入 4 路 `I_DL_LightCurtain`（进入侧 A/B、区内 C、出口侧 D）；输入 `bMutingEnable`、`fZoneSpeedLimit`（mm/s）、`tMutingMax`（屏蔽最长时限，ms）、`tSequenceGap`（判向相邻间隔上限，ms）；输出 `bZoneSafe`、`bMutingActive`、`bSequenceFault`、`bMutingTimeout`、`nErrId`、`eState`（`E_DL_MutingState`）。算法：A→B→C→D 顺序遮光判「正向通过」，D→C→B→A 判「反向」；顺序成立才进屏蔽窗；屏蔽窗内若出现非顺序遮光（如 C 在 A 前）→ `bSequenceFault` 锁存并禁屏蔽。边界：**任一传感器自检失败（信号质量坏）立即退出屏蔽并置码**（不得静默屏蔽）；`tMutingMax` 到点强制解屏蔽；屏蔽期 `fZoneSpeedLimit` 仍受控（屏蔽 ≠ 无限速）；解除式自证：`bSequenceFault` 解除 = `bReset AND NOT bMutingEnable`（组态退出屏蔽路径可满足）；判向超 `tSequenceGap` 判顺序失败而非「无事件」。 |
| 9 | **`FB_DL_VentPurgeDuty`**（DL_Device/FB）：输入双塔状态（`bTowerAAvail`/`bTowerBAvail`、`fTowerADpKpa`/`fTowerBDpKpa`）、`fBreakthroughKpa`（穿透门限）、`tSwitchInterval`（h 口径→内部换 ms）；输出 `bTowerAOnline`、`bSwitchCmd`、`bBreakthroughWarn`、`bBothFault`、`nErrId`。算法：轮值到点切换，但**吸附塔压差已越穿透门限则提前切换**；单塔不可用则禁切（保持运行塔）并告警；两塔均不可用 → `bBothFault` 锁存。边界：穿透门限 ≤ 0 或 `tSwitchInterval` ≤ 0 判组态错；切换中（`tSwitchOverlap` 开）两塔同时在线按允许处理，但**双塔同时离线判严重故障**；解除式自证：`bBothFault` 解除 = `bReset AND (bTowerAAvail OR bTowerBAvail)`；计数器到 UINT 上限前饱和（禁回绕）。 |
| 10 | **`FB_DL_SlurryLevelBank`**（DL_Device/FB）：输入 `abLevelHigh`/`abLevelLow`（多罐点式开关数组）、`anSensorQuality`（0~3 质量字）与 `aeFailSafeDir`（`E_DL_FailSafeDir`：LOW/HIGH，每罐组态）；输出 `abLevelAlarm`、`abSensorFault`、`nFaultCount`、`bBankAlarm`、`nErrId`。算法：按 fail-safe 方向解释「液位 vs 断线」——LOW 型开关在断线时表现为「高位」，反之亦然；质量字非 OK 判 `abSensorFault`，并以「安全侧」值参与联锁（保守取值）。边界：数组长度越界/两数组长度不等直接判码返回（不进入循环）；`uBankSize` = 0 判组态错；**同一罐高低位同时为真**判「开关相反」故障（R28-2 整数/逻辑进位点向量：3 罐 × 2 型共 6 组向量须逐条推演）；输出必须区分「越限」与「传感器故障」两类码。 |

### 批 3（设备诊断 + 首个工艺件）

| # | 规格 |
|---|---|
| 11 | **`FB_DL_FoupPurgeN2Flow`**（DL_Device/FB）：注入 `iFlowMeter`（`FB_DL_PulseFlowMeter` 实例或接口）；输入 `fFlowSetLpm`、`fFlowTolPct`（%）、`fDewPointMaxC`、`tPurgeEstablish`（ms）；输出 `bPurgeOk`、`bEstablishTimeout`、`bDewPointAlarm`、`fFlowDeviationPct`、`nErrId`。算法：吹扫起始后须在 `tPurgeEstablish` 内流量进入 ±`fFlowTolPct` 带，否则 `bEstablishTimeout`；露点超 `fDewPointMaxC` 分级告警（越限 / 严重越限两级）。边界：`fFlowSetLpm <= 0` 防除零判组态错；脉冲流量计 K 系数未组态（=0）判组态错不投运；露点信号缺失（质量坏）时**不当作合格**，置「信号无效」码且 `bPurgeOk := FALSE`；偏差百分比计算分母钳位（`fFlowSetLpm` 已 >0，仍对 `ABS` 结果限幅防溢出）。 |
| 12 | **`FB_DL_CartonErectVacMonitor`**（DL_Device/FB）：注入 `iVac`（`I_DL_VacuumGenerator`）；输入 `fVacTargetKpa`、`tBuildMax`（ms）、`nBaselineSamples`；输出 `fBuildTimeMs`、`fBaselineMs`、`fDriftPct`、`bAgingWarn`、`bBuildTimeout`、`nErrId`。算法：每次取料记录真空建立时长，滑动基线取中值（抗野值），当前时长相对基线漂移超 `fDriftWarnPct` 连续 `nWarnCycles` 次 → `bAgingWarn`（吸盘老化）。边界：`nBaselineSamples` > 数组上限钳制并置信息码；样本数不足不出漂移结论（`bAgingWarn := FALSE`）；`fVacTargetKpa <= 0` 判组态错；建立时长为 0（同拍达成）走下限保护避免除零（基线未建立时 `fDriftPct := 0`）。 |
| 13 | **`FB_DL_CoderRibbonLife`**（DL_Device/FB）：输入 `bPrintPulse`（打印触发）、`nRibbonRatingPrints`（额定打印次数）、`fDensityCmdPct`（浓度设定 %）、`fDensityMinPct`；输出 `nPrintedCount`（UDINT）、`fRemainPct`、`bReplaceWarn`、`bDensityCompSaturated`、`nErrId`。算法：双口径——次数口径（已打/额定）与浓度口径（为达清晰度被迫提升浓度超过 `fDensityRiseMaxPct` 则说明色带衰减）取劣者预警；`nPrintedCount` 饱和到额定值（不回绕）。边界：`nRibbonRatingPrints = 0` 防除零判组态错；`fDensityCmdPct` 越 0~100 钳制并置组态告警；换带复位须 `bRibbonReplaced` 上升沿 + `bReset`（解除式自证）；`bPrintPulse` 用 `R_TRIG`，**每主周期无条件刷新**。 |
| 14 | **`FB_DL_VavBoxZeroCal`**（DL_Device/FB）：输入 `fAirflowRaw`（原始风量信号）、`bDamperClosed`/`bDamperOpen`（两点位置反馈）、`tStableTime`（ms）、`fStableBandPa`；输出 `fZeroOffset`、`fSpanGain`、`bCalValid`、`bCalInProgress`、`bRegulateFrozen`、`nErrId`、`eState`（`E_DL_CalState`）。算法：阀门关位且信号在 `fStableBandPa` 内稳定 `tStableTime` 采零点；开位同理采满量程点算 span；两点标定完成才 `bCalValid`；标定全程 `bRegulateFrozen := TRUE`（冻结调节，防标定期误调）。边界：两点顺序反了（先开位后关位）判顺序错置码；零点与满量程差不满足最小分辨率判标定失败（不透传负 span）；标定超 `tCalTimeout` 退出并保持旧参数；解除式自证：`bCalValid` 置位路径 = 零点/满量程两次采样均成功。 |
| 15 | **`FB_DL_HeatSealProfile`**（DL_Process/FB）：输入 `bStart`、`bAbort`、配方表（温度/压力/时间三段 `ARRAY[0..2]`）、`fTempTolC`/`fPressTolBar`、`tSealMax`（ms）；输出 `bSealing`、`bProfileOk`、`bReject`、`nSegment`、`fElapsedMs`、`nErrId`、`eState`（`E_DL_SealPhase`：Idle/Heat/Press/Cool/Done/Reject/Fault）。算法：升温→加压→冷却三段按配方时长推进，各段温度/压力必须落在容差带内（越带记段不合格，末段汇总 `bProfileOk`）；单段超 `tSealMax` 升级为 `Fault`。边界：配方时长为 0 的段跳过但记信息码；配方三段全为 0 判组态错不启动；`bAbort` 在任意段立即进 `Fault` 并置 `bReject`；`CASE ... ELSE` 必须有兜底分支（未知状态回 Idle 并置码）；解除式自证：`bReject` 解除 = `bStart` 上升沿且 `bReset`。 |

### 批 4（工艺/暖通整段）

| # | 规格 |
|---|---|
| 16 | **`FB_DL_AhuEconomizer`**（DL_Process/FB）：输入 `fOutdoorTempC`/`fReturnTempC`、`fOutdoorRhPct`/`fReturnRhPct`、`bFreezeStat`、`fMinFreshPct`；输出 `fDamperCmdPct`、`bFreeCooling`、`bFreezeLockout`、`bEnthalpyModeActive`、`nErrId`、`eState`。算法：焓值（`FC_DL_HumidAirEnthalpy`）比较为主判据、干球差为后备判据（`eCompareMode` 组态），新风开度在 `[fMinFreshPct, 100]` 区间随需求线性映射；`bFreezeStat` 触发 `bFreezeLockout` 关至最小位并锁存，须温度回升 + `bReset` 解除。边界：两个 RH 信号任一质量坏 → **退到干球判据**（不得用缺省 RH 冒充），并置信息码；`fMinFreshPct` 越 0~100 钳制；焓值差在 `±fDeadbandKjKg` 内保持当前模式（迟滞，防抖）；`bFreezeLockout` 解除式自证：`fOutdoorTempC > fFreezeReleaseC` 且 `bReset`。 |
| 17 | **`FB_DL_TerminalReheatSeq`**（DL_Process/FB）：输入 `fZoneTempC`/`fZoneSetC`、`fAirflowPct`、`fMinAirflowPct`、`fReheatMaxPct`、`fReheatStageStepPct`；输出 `fReheatCmdPct`、`bMinAirflowLimit`、`bReheatInhibit`、`nActiveStage`、`nErrId`。算法：风量低于 `fMinAirflowPct` 时再热**按级降档**（级间延时 `tStageDelay`），并置 `bMinAirflowLimit`；`bReheatInhibit`（如制冷季互锁输入）时再热全关。边界：`fMinAirflowPct` ≥ 100 判组态错（将使再热永久抑制）；级数计算 `nStage = (INT)(fReheatCmdPct / fReheatStageStepPct)` 后**按级数上限钳制**，`fReheatStageStepPct <= 0` 防除零判组态错（R28-2：整除点与上限+1 两点各推向量）；温度/风量信号质量坏 → 保持当前级并置码（不跳变）。 |
| 18 | **`FB_DL_RfReflectedMonitor`**（DL_Process/FB）：输入 `fPowerFwdW`、`fPowerReflW`、`fReflRatioWarnPct`/`fReflRatioFaultPct`（%）、`tRatioDebounce`（ms）；输出 `fReflRatioPct`、`bReflWarn`、`bReflFault`、`bMatcherRequest`（请求调谐，仅请求不闭环）、`nErrId`。算法：反射比 = 反射/正向 ×100，两级阈值带迟滞 + 去抖；`bMatcherRequest` 在越 `fReflRatioWarnPct` 时置位持续 `tMatcherReqHold`。边界：`fPowerFwdW <= 0` 时比值不计算（防除零），输出 0 并置「无正向功率」信息码；反射功率 > 正向功率（比值 > 100%）属异常物理值，钳到 100 并置码；「仅监视」语义写进头注释（不得暗示闭环调谐）；解除式自证：`bReflFault` 解除 = 比值回落到 `fReflRatioWarnPct` 以下且 `bReset`。 |
| 19 | **`FB_DL_StringSolderQuality`**（DL_Process/FB）：输入多通道焊接温度曲线采样（`ARRAY OF` 峰值/升温斜率/保温时长）、`fPeakMinC`/`fPeakMaxC`、`fSlopeMinCs`/`fSlopeMaxCs`、`fPullMinN`（拉力抽检下限）；输出逐通道 `abChannelOk`、`abPeakViolate`/`abSlopeViolate`、`nNgChannelMask`（DWORD）、`bLotReject`、`nErrId`。算法：逐通道三判据（峰值窗、升温斜率窗、保温时长窗）→ 通道 NG 聚合到位掩码；拉力抽检仅对「抽中通道」生效（`abPullSampled`），抽检不合格则整批 `bLotReject`。边界：通道数 `nChannelCount = 0` 或超数组上限判码返回；位掩码只在 `nChannelCount <= 32` 时生成（超 32 判组态错，禁止静默截断）；`fSlopeMaxCs <= fSlopeMinCs` 判组态错；抽检通道与 NG 通道不一致时按「双判据独立记账」，不互相掩盖；**整数位段赋值用 `SHL` 显式位号，禁魔法掩码**。 |
| 20 | **`FB_DL_ModuleLamVacuumSeq`**（DL_Process/FB）：注入 `iVac`（`I_DL_VacuumGenerator`）、`iTempZone`（`I_DL_TemperatureZone`）、`iPressCyl`（`I_DL_Cylinder`）；输入 `fVacTargetKpa`、`fPressTargetBar`、配方四段时长（抽气/加热/加压/放气，ms）、`tSegmentTimeout`；输出 `bCycleDone`、`bSegmentTimeoutFault`、`nSegment`、`fVacKpa`、`nErrId`、`eState`（`E_DL_LamPhase`：Idle/Evac/Heat/Press/Vent/Done/Fault）。算法：四段顺控，每段带 `tSegmentTimeout` 超时升级；加压段须真空度与温度**双到位**才允许升压（联锁内置）；放气段结束真空度须回到常压确认。边界：任一注入接口引用为 0（未装配）判组态错不启动；`fPressTargetBar` 超组态上限钳制并置码；配方时长全 0 判组态错；`CASE` 全态覆盖 + `ELSE` 兜底置 Fault；解除式自证：`bSegmentTimeoutFault` 解除 = `bReset AND eState = Idle`，且 Idle 可达路径（每段正常推进 + 超时回 Idle）逐条给出。 |

---

## 5 判弃清单（本轮已 grep 双查后主动剔除，防止同义邻件撞车 —— R28 选题双查 / R184）

| 曾候选 | 邻件（registry 实测） | 判弃理由 |
|---|---|---|
| `FB_DL_ValveStictionDiag` | `FB_DL_ValveStictionDetect` | 同名同义，仅词尾差异，属「凑数变体」 |
| `FB_DL_SteamTrapSurvey` | `FB_DL_SteamTrapMonitor` / `FB_DL_SteamTrapDiagTrend` / `FB_DL_TrapSealTrend` | 疏水阀族已 3 件，第 4 件无新增工程判据 |
| `FB_DL_TankBlanketPrCtrl` | `FB_DL_TankN2BlanketCtrl` | 氮封压差已被覆盖，语义重合 |
| `FB_DL_CrossLimitGuard` | `FB_DL_CrossLimitSelect` | 交叉限幅选择器已存在，再立一件即成重复 |
| `FB_DL_SampleLoopPurge` | `FB_DL_AnalyzerSampleSeq`（R35 新件） | 取样-吹扫轮换语义与 R35 件重叠，跨轮撞义（R172 教训延伸） |
| `FB_DL_PouchVacuumSeal` | `FB_DL_SealIntegrityMonitor` / `FB_DL_SealJawDwellTrim` | 软包封口判据已有两件，本轮工艺位让给 `HeatSealProfile` |
| `FB_DL_OrificeDpZeroTrim` | `FC_DL_OrificeFlowCalc` / 多件 `*ZeroTrack` | 孔板零点跟踪已由 `FB_DL_CheckweighZeroTrack` 提供骨架，属变体 |
| `FC_DL_ShlDwordEx` / `FC_DL_ShrDwordEx` | `FC_DL_ShlEx` / `FC_DL_ShrEx` | 沿用 R34 同义弃判裁定 |

> **替补充足性**：剔除 8 条后本轮仍从真池（ROADMAP 未注册 135 条 + 矩阵 ◐ 深化语义）足额锁定 20 件，不存在为凑数回填被剔除项的情况。

---

## 6 查重声明

> **全部 20 名已 grep 查重通过**：
> ① **name 查**：`INDEX_REGISTRY.json` 637 条 `components[].name` 精确匹配（大小写不敏感）= 0 命中；
> ② **file_path 查**：`DL_*/*.st` 磁盘文件名（637 个）= 0 命中；
> ③ **同义邻件查**：按组件名 CamelCase 词干拆分，对 637 名做词干包含扫描，逐件判定无同义邻件（或已在 §5 判弃/已给出差异化说明）；
> ④ **码位查**：6 个窗口对全库 `.st` + `.md` 做 `16#NN_N_XX` 全量正则扫描 = 0 命中。
> ⑤ **三向一致核对**：`registry.counts` 合计 637 = registry `components` 长度 637 = 磁盘 `.st` 637，无差额挂账。

---

## 7 附录 A：R35 轻微挂账 3 项（P1 返修池，不占本轮 20 目标名额）

| # | 件名 | 缺陷 | 返修口径 |
|---|---|---|---|
| A1 | `FB_DL_ChillerApproachTrend` | 头注释描述与实现行为不符（注释声称的趋势判据未在主体落地） | 二选一：补实现或改注释，须在头注释修订历史留痕 |
| A2 | `FB_DL_ForelinePressureCtrl` | 失能路径经 `eFault` 过桥（`bEnable := FALSE` 时被错误上报为故障态） | 失能须与故障分轨：`eState` 走 Idle/Disabled，`eFault` 不得承接失能 |
| A3 | `FB_DL_AnalyzerSampleSeq` | 脉冲输出语义未在声明行标注 | 按 R35 起新规补「脉冲语义：置位 N 个 PLC 周期」注释 |

> 上述 3 项为**规划附注**，由返修池排程，**不占** R36 的 20 个新件名额；若本轮编码期有余量可顺带处理，但不得挤占新件。

---

## 8 附录 B：ROADMAP 补条判定

`ROADMAP.md` 未勾选 = **190 条 ≥ 30** → 按步骤 7「≥30 则不补」执行，本轮**不新增待办条目**。观察池现存高价值待办（供 R37 起认领）：`FB_DL_EfEmoInterlock`（EFEM 互锁矩阵）、`FB_DL_ElTestStation`（EL 工站）、`FB_DL_ShrinkTunnelCtrl`（热收缩炉温区-网速联动）、`FB_DL_HjtPvdSeq`（PVD 腔体顺控）。

---

*编制：道莅工控代码库产品总监（阶段一）｜ R36 ｜ 2026-11-18*
