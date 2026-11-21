# R37 派单书（R36-RESUME · 10 件 · 两窗 5+5）

生成：2026-11-18 21:00 主控。码位已实测 `.st` 头注释全库占用（非 registry code_segment，后者仅 62 件有值不可信）。

## 窗口与落点（写死，禁止自行改号）

- W1 `16#02_3_82`~`16#02_3_82` + `16#04_0_A2`~`A3` + `16#03_2_0B`~`0D`（序号 4~9）
- W2 `16#03_2_0E`~`11`（序号 10~13）

## 目标表

| 序号 | 组件名 | 子库 | 前缀 | 码位 | 来源标签 | 复杂度 |
|---|---|---|---|---|---|---|
| 4 | `FB_DL_ResonanceTrackNotch` | DL_Algo | FB | `16#02_3_82` | `t1-6-plcopen` | 高 |
| 5 | `FB_DL_LineShaftClutch` | DL_Motion | FB | `16#04_0_A2` | `t2-4-s7-motion` | 高 |
| 6 | `FB_DL_FlyingCutSync` | DL_Motion | FB | `16#04_0_A3` | `t1-6-plcopen` | 高 |
| 7 | `FB_DL_WaferCoolChuck` | DL_Device | FB | `16#03_2_0B` | `t2-2-lbp` | 中 |
| 8 | `FB_DL_CurtainEFEMZone` | DL_Device | FB | `16#03_2_0C` | `t1-5-tcopen` | 高 |
| 9 | `FB_DL_VentPurgeDuty` | DL_Device | FB | `16#03_2_0D` | `t2-8-isa88` | 中 |
| 10 | `FB_DL_SlurryLevelBank` | DL_Device | FB | `16#03_2_0E` | `t2-8-isa182` | 中 |
| 11 | `FB_DL_FoupPurgeN2Flow` | DL_Device | FB | `16#03_2_0F` | `t2-1-lgf-measurement` | 中 |
| 12 | `FB_DL_CartonErectVacMonitor` | DL_Device | FB | `16#03_2_10` | `t2-1-lgf-measurement` | 中 |
| 13 | `FB_DL_CoderRibbonLife` | DL_Device | FB | `16#03_2_11` | `t2-1-lgf-technology` | 中 |

## 逐件规格（原文，来自 R36 计划，不得删减边界条款）

### 4. FB_DL_ResonanceTrackNotch  （DL_Algo / FB / `16#02_3_82` / `t1-6-plcopen` / 高）

| 4 | **`FB_DL_ResonanceTrackNotch`**（DL_Algo/FB）：输入 `fSignal`（振动或电流反馈）、`fSampleDt`（s）、`fFreqMinHz`/`fFreqMaxHz`（搜索窗）、`nSettleCycles`；输出 `fResonanceHz`、`fTrackConfidence`（0~1）、`bLocked`、`nErrId`、`eState`。算法：二阶带通相位过零测周期 → 频率估计经滑动中值去野值 → 钳制到 `[fFreqMinHz, fFreqMaxHz]`；连续 `nSettleCycles` 次估计落在 ±`fLockBandHz` 内才 `bLocked`；锁定后失锁须连续 `nLostCycles` 次越带才降级（迟滞，防抖）。边界：`fSampleDt <= 0` 判组态错；`fFreqMinHz >= fFreqMaxHz` 判组态错置码不运行；搜索窗越奈奎斯特判无效；信号幅值 < `fAmpFloor` 不出频率结论（`bLocked := FALSE`，估计值保持但 `fTrackConfidence` 衰减）；频率跳变超 `fMaxSlewHzPerSec` 判野值丢弃并计数（计数超限置「跟踪发散」故障码）。 |

### 5. FB_DL_LineShaftClutch  （DL_Motion / FB / `16#04_0_A2` / `t2-4-s7-motion` / 高）

| 5 | **`FB_DL_LineShaftClutch`**（DL_Motion/FB）：注入 `iMasterAxis`/`iSlaveAxis`（`I_DL_MotionAxis`）；输入 `bEngageCmd`、`bDisengageCmd`、`fPhaseOffsetDeg`（°）、`fEngageRampTime`（s）、`fSlipLimitDeg`；输出 `bEngaged`、`fPhaseErrorDeg`（°）、`bSlipFault`、`eState`（`E_DL_ClutchState`：Idle/Aligning/Ramping/Engaged/Disengaging/Fault）。算法：对齐段把从轴相位拉至主轴的 `fPhaseOffsetDeg` 偏移，相位误差进入 `fAlignTolDeg`（本件声明常量 0.5°）后进咬合斜坡，斜坡完成置 `bEngaged`；咬合期相位误差超 `fSlipLimitDeg` 持续 `tSlipDebounce` → `bSlipFault` 且强制脱开。边界：两轴任何一方 `bError`/未使能则拒绝咬合置码；主从同轴（同一实例传引用）判组态错；`fEngageRampTime <= 0` 判组态错；脱开命令与咬合命令同拍 → 以脱开为安全优先并置码；解除路径自证：`bSlipFault` 解除式 = `bReset AND iMasterAxis.bStandstill AND iSlaveAxis.bStandstill`（三条件均可满足，R28-1 通过）。 |

### 6. FB_DL_FlyingCutSync  （DL_Motion / FB / `16#04_0_A3` / `t1-6-plcopen` / 高）

| 6 | **`FB_DL_FlyingCutSync`**（DL_Motion/FB）：注入 `iMasterAxis`（料带线轴）/`iCutAxis`（刀轴）；输入 `fCutLengthMm`、`fSyncWindowStartMm`/`fSyncWindowEndMm`（切窗区间）、`fCutOverlapRatio`、`tCutDwell`（ms）；输出 `bCutCmd`（单拍脉冲，注释标注「脉冲语义：置位 1 个 PLC 周期」）、`bInSyncWindow`、`fSyncErrorMm`、`nCutCount`（UDINT）、`eState`。算法：MASTER 位置取模 `fCutLengthMm` 得相位，进入窗口后刀轴按电子齿轮追赶，同步误差进 `fSyncTolMm` 才允许下刀；切完回程重装。边界：`fCutLengthMm <= 0` 防除零判组态错；窗口起止倒置或窗口宽 ≤ 0 判组态错不运行；未同步时**禁止** `bCutCmd`（互锁在内部，不外抛）；`nCutCount` 到 `uCountPreset` 后 `bPresetReached` 置位（UDINT 上限前饱和，**不给 TRUNC(x)+1 型写法**）；切窗内主轴反转立即判废并置码。 |

### 7. FB_DL_WaferCoolChuck  （DL_Device / FB / `16#03_2_0B` / `t2-2-lbp` / 中）

| 7 | **`FB_DL_WaferCoolChuck`**（DL_Device/FB）：注入 `iVac`（`I_DL_VacuumGenerator`）/`iTempZone`（`I_DL_TemperatureZone`）；输入 `bClampCmd`、`bReleaseCmd`、`fTempAttachMaxC`（脱附允许上限，°C）、`tAttachConfirm`（ms）；输出 `bClamped`、`bTempEnable`、`bInterlockBlocked`、`nErrId`、`eState`（`E_DL_ChuckState`）。算法：吸附确认（真空度达 `fVacConfirmKpa` 且持续 `tAttachConfirm`）才允许 `bTempEnable`；释放须温度 ≤ `fTempAttachMaxC`（迟滞 2 °C）且真空已破；吸附失败重试 `nRetryMax` 次后锁存。边界：`fTempAttachMaxC` 与环境上限倒置判组态错；**区分「吸附中温度越上限」与「未吸附」两路故障码**（不得共用一号）；解除式自证：温度回落 + `bReset`；释放期真空未破不推进状态（带 `tReleaseTimeout` 超时升级）。 |

### 8. FB_DL_CurtainEFEMZone  （DL_Device / FB / `16#03_2_0C` / `t1-5-tcopen` / 高）

| 8 | **`FB_DL_CurtainEFEMZone`**（DL_Device/FB）：注入 4 路 `I_DL_LightCurtain`（进入侧 A/B、区内 C、出口侧 D）；输入 `bMutingEnable`、`fZoneSpeedLimit`（mm/s）、`tMutingMax`（屏蔽最长时限，ms）、`tSequenceGap`（判向相邻间隔上限，ms）；输出 `bZoneSafe`、`bMutingActive`、`bSequenceFault`、`bMutingTimeout`、`nErrId`、`eState`（`E_DL_MutingState`）。算法：A→B→C→D 顺序遮光判「正向通过」，D→C→B→A 判「反向」；顺序成立才进屏蔽窗；屏蔽窗内若出现非顺序遮光（如 C 在 A 前）→ `bSequenceFault` 锁存并禁屏蔽。边界：**任一传感器自检失败（信号质量坏）立即退出屏蔽并置码**（不得静默屏蔽）；`tMutingMax` 到点强制解屏蔽；屏蔽期 `fZoneSpeedLimit` 仍受控（屏蔽 ≠ 无限速）；解除式自证：`bSequenceFault` 解除 = `bReset AND NOT bMutingEnable`（组态退出屏蔽路径可满足）；判向超 `tSequenceGap` 判顺序失败而非「无事件」。 |

### 9. FB_DL_VentPurgeDuty  （DL_Device / FB / `16#03_2_0D` / `t2-8-isa88` / 中）

| 9 | **`FB_DL_VentPurgeDuty`**（DL_Device/FB）：输入双塔状态（`bTowerAAvail`/`bTowerBAvail`、`fTowerADpKpa`/`fTowerBDpKpa`）、`fBreakthroughKpa`（穿透门限）、`tSwitchInterval`（h 口径→内部换 ms）；输出 `bTowerAOnline`、`bSwitchCmd`、`bBreakthroughWarn`、`bBothFault`、`nErrId`。算法：轮值到点切换，但**吸附塔压差已越穿透门限则提前切换**；单塔不可用则禁切（保持运行塔）并告警；两塔均不可用 → `bBothFault` 锁存。边界：穿透门限 ≤ 0 或 `tSwitchInterval` ≤ 0 判组态错；切换中（`tSwitchOverlap` 开）两塔同时在线按允许处理，但**双塔同时离线判严重故障**；解除式自证：`bBothFault` 解除 = `bReset AND (bTowerAAvail OR bTowerBAvail)`；计数器到 UINT 上限前饱和（禁回绕）。 |

### 10. FB_DL_SlurryLevelBank  （DL_Device / FB / `16#03_2_0E` / `t2-8-isa182` / 中）

| 10 | **`FB_DL_SlurryLevelBank`**（DL_Device/FB）：输入 `abLevelHigh`/`abLevelLow`（多罐点式开关数组）、`anSensorQuality`（0~3 质量字）与 `aeFailSafeDir`（`E_DL_FailSafeDir`：LOW/HIGH，每罐组态）；输出 `abLevelAlarm`、`abSensorFault`、`nFaultCount`、`bBankAlarm`、`nErrId`。算法：按 fail-safe 方向解释「液位 vs 断线」——LOW 型开关在断线时表现为「高位」，反之亦然；质量字非 OK 判 `abSensorFault`，并以「安全侧」值参与联锁（保守取值）。边界：数组长度越界/两数组长度不等直接判码返回（不进入循环）；`uBankSize` = 0 判组态错；**同一罐高低位同时为真**判「开关相反」故障（R28-2 整数/逻辑进位点向量：3 罐 × 2 型共 6 组向量须逐条推演）；输出必须区分「越限」与「传感器故障」两类码。 |

### 11. FB_DL_FoupPurgeN2Flow  （DL_Device / FB / `16#03_2_0F` / `t2-1-lgf-measurement` / 中）

| 11 | **`FB_DL_FoupPurgeN2Flow`**（DL_Device/FB）：注入 `iFlowMeter`（`FB_DL_PulseFlowMeter` 实例或接口）；输入 `fFlowSetLpm`、`fFlowTolPct`（%）、`fDewPointMaxC`、`tPurgeEstablish`（ms）；输出 `bPurgeOk`、`bEstablishTimeout`、`bDewPointAlarm`、`fFlowDeviationPct`、`nErrId`。算法：吹扫起始后须在 `tPurgeEstablish` 内流量进入 ±`fFlowTolPct` 带，否则 `bEstablishTimeout`；露点超 `fDewPointMaxC` 分级告警（越限 / 严重越限两级）。边界：`fFlowSetLpm <= 0` 防除零判组态错；脉冲流量计 K 系数未组态（=0）判组态错不投运；露点信号缺失（质量坏）时**不当作合格**，置「信号无效」码且 `bPurgeOk := FALSE`；偏差百分比计算分母钳位（`fFlowSetLpm` 已 >0，仍对 `ABS` 结果限幅防溢出）。 |

### 12. FB_DL_CartonErectVacMonitor  （DL_Device / FB / `16#03_2_10` / `t2-1-lgf-measurement` / 中）

| 12 | **`FB_DL_CartonErectVacMonitor`**（DL_Device/FB）：注入 `iVac`（`I_DL_VacuumGenerator`）；输入 `fVacTargetKpa`、`tBuildMax`（ms）、`nBaselineSamples`；输出 `fBuildTimeMs`、`fBaselineMs`、`fDriftPct`、`bAgingWarn`、`bBuildTimeout`、`nErrId`。算法：每次取料记录真空建立时长，滑动基线取中值（抗野值），当前时长相对基线漂移超 `fDriftWarnPct` 连续 `nWarnCycles` 次 → `bAgingWarn`（吸盘老化）。边界：`nBaselineSamples` > 数组上限钳制并置信息码；样本数不足不出漂移结论（`bAgingWarn := FALSE`）；`fVacTargetKpa <= 0` 判组态错；建立时长为 0（同拍达成）走下限保护避免除零（基线未建立时 `fDriftPct := 0`）。 |

### 13. FB_DL_CoderRibbonLife  （DL_Device / FB / `16#03_2_11` / `t2-1-lgf-technology` / 中）

| 13 | **`FB_DL_CoderRibbonLife`**（DL_Device/FB）：输入 `bPrintPulse`（打印触发）、`nRibbonRatingPrints`（额定打印次数）、`fDensityCmdPct`（浓度设定 %）、`fDensityMinPct`；输出 `nPrintedCount`（UDINT）、`fRemainPct`、`bReplaceWarn`、`bDensityCompSaturated`、`nErrId`。算法：双口径——次数口径（已打/额定）与浓度口径（为达清晰度被迫提升浓度超过 `fDensityRiseMaxPct` 则说明色带衰减）取劣者预警；`nPrintedCount` 饱和到额定值（不回绕）。边界：`nRibbonRatingPrints = 0` 防除零判组态错；`fDensityCmdPct` 越 0~100 钳制并置组态告警；换带复位须 `bRibbonReplaced` 上升沿 + `bReset`（解除式自证）；`bPrintPulse` 用 `R_TRIG`，**每主周期无条件刷新**。 |

## 硬约束（违反即整批退回）

1. **7 项红线**：零 GVL/VAR_EXTERNAL；零 %I/%Q 绝对地址；纯 IEC 61131-3 跨平台（禁 CODESYS 私有属性/指针/REFERENCE TO）；防除零/防越界/浮点容差比较（禁 `=` 比较 REAL）；变量声明行同行中英双语注释；ENUM + CASE 必含 `ELSE` 兜底；每主周期**无条件**刷新所有 `TON`/`R_TRIG`/`F_TRIG` 实例（不得置于 IF 内）。
2. **历史高频缺陷（逐条自检）**：漏声明 VAR_OUTPUT；`(* *)` 注释体内嵌套 `(*`；枚举声明用单冒号 `:` 而非 `:=`；**隐性回夹**（置位与同拍清零写在同一 CASE 段 → 完成脉冲恒假）；**锁存副本与实时镜像混用**；周期节拍 TON 不自复位（R182，R32 三件挂账主因）；CASE 内不得给输出枚举变量直接赋值（N2 规则，改内部状态变量再映射）；故障码不得被段尾 ELSE / 无条件 `bError:=FALSE` 同拍抹除（须按码专清 + 恢复沿清码）。
3. **文件头必含**：`码位 Code     : <派单码位>`（原样抄）；`来源 Source   : <标签> — IEC 61131-3 标准语义的道莅防御性实现`；修订历史行 `v1.0.0  2026-11-18  R37 首版`。
4. **依赖**：只能用已注册件（先 `ls DL_*/<Name>.st` 或 grep registry 确认存在）。接口件 `I_DL_*` 不可实例化，只能注入。依赖缺失 → 内联实现并在头注释标注，禁止臆造不存在的 FB 名。
5. **禁写**：INDEX_REGISTRY.json / JSONL / ROADMAP / README / CHANGELOG / MANUAL / VERSION —— 全部由主控脚本收口。你只写 `.st`。
6. **落盘纪律**：读完本文件立刻开始写第 1 件，禁止先输出长篇计划；每件写完立即落盘再写下一件；禁止占位符 / TODO / `(* 略 *)`。
7. **收口自检**：10 件写完后，逐件回报：行数、7 红线自查结论（PASS/FAIL+原因）、依赖清单、你最担心的 1 处语义风险。
