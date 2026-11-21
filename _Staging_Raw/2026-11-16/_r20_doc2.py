# -*- coding: utf-8 -*-
"""R20 文档增量 2：DL_Device / DL_Motion / DL_Process 三本手册补录 R19 批次 10 件接口表（R19 遗留 P1）"""

TASKS = [
    dict(
        path='MANUAL_DL_Device.md',
        head_old='> **Sublibrary**：`DL_Device` ｜ **Version**：v0.8.0 ｜ **Level**：1 ｜ **Components**：44（接口 16 ｜ 功能块 28）',
        head_new='> **Sublibrary**：`DL_Device` ｜ **Version**：v1.14.0（子库版本以 `VERSION.md` 为准）｜ **Level**：1 ｜ **Components**：57（接口 17 ｜ 功能块 40，R20 按注册表实测校正；本手册接口表已覆盖至 R19 批次，R1~R18 历史件**下轮续补**）',
        tail_old='*Last updated: 2026-11-16（R13 追加 #49~#54，NE107 诊断族开族）｜ 道莅工控代码库产品总监*',
        block='''---

## R19 批次补录接口表（2026-11-16，本子库 4 件，R19 遗留 P1）

> 本节为 R19 文档缺口补录：R19 编 4 件入库时手册仅建骨架、未收录接口表。**引脚级细节以 `.st` 源码声明区为准**，下表逐字取自源码。

### `FB_DL_DeviceHealthArbiter`
- **功能**：16 路 NE107 健康源聚合仲裁，枚举成员编号即仲裁优先级（全库唯一属主 `E_DL_Ne107Status` 只引用不重声明）；输出聚合健康态、首出源下标与通道号、分级掩码。`bIncludeMaintenance` 决定 `eMaintenanceReq` 是否参与升级。
- **输入引脚**：`bEnable`、`bReset`、`aeHealth[0..15]`、`auChannelId[0..15]`、`uSrcCount`、`bIncludeMaintenance`
- **输出引脚**：`eAggHealth`、`uFirstIdx`、`uFirstChannel`、`auLevelMask[0..5]`、`uFaultSrcCount`、`bDegraded`、`eErr`、`bError`
- **码位**：信息 `16#0003_016A` / `016B` ｜ 故障 `16#0003_0330`~`0332`

### `FB_DL_ProfinetAlarmDiag`
- **功能**：PROFINET 诊断条目五元组（通道号 / 通道属性 / 错误类型 / 扩展错误类型 / 附加值）→ 通道故障掩码 + 首出通道 + 分类计数 + NE107 健康态；区分系统级与通道级、维护类与故障类。
- **输入引脚**：`auChannelNo` / `auChannelProp` / `auErrType` / `auExtErrType` / `audAddValue`（各 `[0..15]`）、`uEntryCount`
- **输出引脚**：`uChannelMask`、`uFirstChannel`、`uFirstErrType`、`auClassCount[0..7]`、`bMaintenanceOnly`、`bSystemLevel`、`eHealth`、`bValid`、`eErr`、`bError`
- **码位**：信息 `16#0003_016C` / `016D` ｜ 故障 `16#0003_0333`~`0335`

### `FB_DL_EscChuckCurrentMonitor`
- **功能**：静电吸盘（ESC）吸附电流监视四态（idle / build / steady / release / fault）：建立段等电流落窗、稳态段持续确认、释放段等电流归零；打火判据与泄漏趋势双出口，NE107 健康映射。
- **输入引脚**：`bEnable`、`bReset`、`bChuckOn`、`fChuckCurrent`、`fChuckVoltage`、`fCurMin`、`fCurMax`、`fSparkRise`、`tBuildTime`、`tConfirmTime`、`tSampleTime`
- **输出引脚**：`bAttached`、`bSpark`、`bLeakTrend`、`bDegraded`、`eHealth`、`uAttachCount`、`eErr`、`bError`
- **码位**：信息 `16#0003_016E` / `016F` ｜ 故障 `16#0003_0336`~`0338`

### `FB_DL_DeviceParamWrite`
- **功能**：设备参数写回**事务**（R77 三要素齐备）：白名单 `abWritable` → 快照备份 → 逐项写入 → `afActual` 读回复核（容差 `fVerifyTol`）→ 失败回滚。六态机（idle/backup/write/verify/rollback/done/fault），逐项握手经 `uActiveIdx` + `bWriteNow`。
- **输入引脚**：`bEnable`、`bExecute`、`bAbort`、`bReset`、`auIndex` / `afWriteValue` / `abWritable` / `afActual`（各 `[0..15]`）、`uCount`、`fVerifyTol`、`tWriteTimeout`、`tVerifyTimeout`
- **输出引脚**：`bBusy`、`bDone`、`bRollback`、`uWritten`、`uSkipped`、`uFailedIdx`、`afReadback[0..15]`、`uActiveIdx`、`bWriteNow`、`eErr`、`bError`
- **码位**：信息 `16#0003_0170` / `0171` ｜ 故障 `16#0003_0339`~`033B`

### 续补说明 / Remaining
本手册现覆盖至 R19 批次；`DL_Device` 余下 R1~R18 历史件（约 53 件，含 16 只 `I_DL_*` 契约）接口表**下轮续补**（每轮 ≤10 件，按 R18→R17 倒序推进）。


'''),
    dict(
        path='MANUAL_DL_Motion.md',
        head_old='> **Sublibrary**：`DL_Motion` ｜ **Version**：v0.8.0 ｜ **Level**：1 ｜ **Components**：17（接口 1 ｜ 功能块 15 ｜ 函数 1）',
        head_new='> **Sublibrary**：`DL_Motion` ｜ **Version**：v1.14.0（子库版本以 `VERSION.md` 为准）｜ **Level**：1 ｜ **Components**：25（接口 1 ｜ 功能块 22 ｜ 函数 2，R20 按注册表实测校正；本手册接口表已覆盖至 R19 批次，R1~R18 历史件**下轮续补**）',
        tail_old='*Last updated: 2026-11-16（R13 追加 #20）｜ 道莅工控代码库产品总监*',
        block='''---

## R19 批次补录接口表（2026-11-16，本子库 4 件，R19 遗留 P1）

> 本节为 R19 文档缺口补录。四件一律消费外部给定（位置 / 计数 / 偏差）与采样周期，**不自造轴状态、不定义轴状态枚举、不发运动指令**（R31 家族纪律）；`tSampleTime` 为速度/层数折算的时间基准（R78）。

### `FB_DL_ExternalEncoderScaler`
- **功能**：外部编码器原始计数 → 工程位置 / 速度：多圈回绕展开（`nMultiTurnBits` 位宽）、齿轮比、反向、偏移与每转计数换算，速度按 `tSampleTime` 差分。
- **输入引脚**：`bEnable`、`bReset`、`diRawCount`、`uCountsPerRev`、`fPitch`、`iGearNum`、`iGearDen`、`bInvert`、`fOffset`、`nMultiTurnBits`、`tSampleTime`
- **输出引脚**：`fPosition`、`liTotalCount`、`bWrapped`、`uWrapCount`、`fVelocity`、`bValid`、`eErr`、`bError`
- **码位**：信息 `16#0004_01CD` / `01CE` ｜ 故障 `16#0004_02DE`~`02E0`

### `FB_DL_CamPhaseTrim`
- **功能**：凸轮相位在线修调：目标相位经**限速斜坡**逼近（`fRateMax`），相位偏置整体限幅（`fPhaseLimit`），标记脉冲可触发一次性修正量（`bMarkPulse` + `fMarkCorrection`，已修正的标记不再重复计入，`uMarkCount` 可查）。
- **输入引脚**：`bEnable`、`bReset`、`fPhaseOffsetCmd`、`fRateMax`、`fPhaseLimit`、`bTrimOnMark`、`fMarkCorrection`、`bMarkPulse`、`tSampleTime`
- **输出引脚**：`fPhaseOffset`、`bTrimming`、`bLimited`、`uMarkCount`、`eErr`、`bError`
- **码位**：信息 `16#0004_01CF` / `01D0` ｜ 故障 `16#0004_02E1`~`02E3`

### `FB_DL_FilmWebCenter`
- **功能**：薄膜纠偏（EPC/LPC 位置给定）：偏差 → 增益 → 死区豁免 → 速率限幅 → 行程限位 → 位置给定；`bWebPresent = FALSE` 时判 `bWebLost` 并冻结给定（断料不追偏）。
- **输入引脚**：`bEnable`、`bReset`、`bAuto`、`fDeviation`、`fGain`、`fManualOffset`、`fDeadband`、`fRateMax`、`fTravelMin`、`fTravelMax`、`bWebPresent`、`tSampleTime`
- **输出引脚**：`fPositionSp`、`bInDeadband`、`bLimited`、`bWebLost`、`bValid`、`eErr`、`bError`
- **码位**：信息 `16#0004_01D1` / `01D2` ｜ 故障 `16#0004_02E4`~`02E6`

### `FB_DL_WindingLayerCounter`
- **功能**：收卷层数计数：由卷径 / 芯径 / 材料厚度反推层数并比较上拍值出 `bLayerEdge`，支持换卷复位（`bNewRoll`）、方向选择、厚度在线自估（`fThicknessEst`）；层数与卷径不一致时置 `bInconsistent`。
- **输入引脚**：`bEnable`、`bReset`、`bNewRoll`、`fCoilDiameter`、`fCoreDiameter`、`fThickness`、`diRevCount`、`uLayerMax`、`bDirPositive`
- **输出引脚**：`uLayerDone`、`uLayerRemain`、`bLayerEdge`、`bInconsistent`、`fThicknessEst`、`uRollCount`、`eErr`、`bError`
- **码位**：信息 `16#0004_01D3` / `01D4` ｜ 故障 `16#0004_02E7`~`02E9`

### 续补说明 / Remaining
本手册现覆盖至 R19 批次；`DL_Motion` 余下 R1~R18 历史件（约 21 件）接口表**下轮续补**。


'''),
    dict(
        path='MANUAL_DL_Process.md',
        head_old='> **Sublibrary**：`DL_Process` ｜ **Version**：v0.8.0 ｜ **Level**：2 ｜ **Components**：22（功能块 22）',
        head_new='> **Sublibrary**：`DL_Process` ｜ **Version**：v1.14.0（子库版本以 `VERSION.md` 为准）｜ **Level**：2 ｜ **Components**：30（功能块 30，R20 按注册表实测校正；本手册接口表已覆盖至 R19 批次，R1~R18 历史件**下轮续补**）',
        tail_old='*Last updated: 2026-11-16（R13 追加 #25~#28 + §21 修订记录 v1.0.1）｜ 道莅工控代码库产品总监*',
        block='''---

## R19 批次补录接口表（2026-11-16，本子库 2 件，R19 遗留 P1）

> 本节为 R19 文档缺口补录。两件均只消费外部给定、输出给定值与判据标志，不内联闭环算法（PID 输出一律引脚注入，R19 同族纪律）。

### `FB_DL_DrumLevelThreeElem`
- **功能**：锅炉汽包三冲量给水：水位偏差（正作用）− 蒸汽流量前馈 + 给水流量反馈，三路增益分别可调，输出经上下限钳位；水位高 / 低触限锁存并置联锁跳闸出口。
- **输入引脚**：`bEnable`、`bReset`、`fLevel`、`fLevelSp`、`fSteamFlow`、`fFeedFlow`、`fLevelGain`、`fSteamGain`、`fFeedGain`、`fLevelLow`、`fLevelHigh`、`fOutMin`、`fOutMax`
- **输出引脚**：`fFeedSp`、`bLevelLow`、`bLevelHigh`、`bInterlockTrip`、`bLimited`、`bValid`、`eErr`、`bError`
- **码位**：信息 `16#0005_01D6` / `01D7` ｜ 故障 `16#0005_0305`~`0307`
- **用法要点**：v1.0.1 已修水位项符号构成正反馈的缺陷（R19 终审）——**升级前版本不得用于真实汽包**；量程单位由组态注释约定（mm 或 %），三路增益量纲不同，禁止互相借用数值。

### `FB_DL_VacCupRingCtrl`
- **功能**：真空吸盘环（多吸盘）取放控制：逐只真空确认（`auVacuumOk` + `afVacuum` 阈值 `fVacMin`，确认时长 `tConfirmTime`），最小吸盘数 `uMinCupsRequired` 判成功；`bAllowDegrade` 决定少吸时降级放行还是判 `bPickFailed`；释放可配置外圈优先（`bReleaseOuterFirst`）逐只泄真空。
- **输入引脚**：`bEnable`、`bReset`、`bCmdPick`、`bCmdRelease`、`auVacuumOk[0..7]`、`afVacuum[0..7]`、`uCupCount`、`uMinCupsRequired`、`fVacMin`、`tConfirmTime`、`bAllowDegrade`、`bReleaseOuterFirst`
- **输出引脚**：`auValveOut[0..7]`、`bPicked`、`bReleased`、`uOkCups`、`bDegraded`、`bPickFailed`、`uPickCount`、`eErr`、`bError`
- **码位**：信息 `16#0005_01D8` / `01D9` ｜ 故障 `16#0005_0308`~`030A`
- **用法要点**：`auValveOut` 只是阀指令，物理点由上层映射；膜片老化表现为「确认时长变长」而非「真空值突变」，`tConfirmTime` 按新膜片实测值的 1.5 倍设。

### 续补说明 / Remaining
本手册现覆盖至 R19 批次；`DL_Process` 余下 R1~R18 历史件（约 28 件）接口表**下轮续补**。


'''),
]

for t in TASKS:
    p = t['path']
    s = open(p, encoding='utf-8').read()
    assert t['head_old'] in s, ('head miss', p)
    assert t['tail_old'] in s, ('tail miss', p)
    s = s.replace(t['head_old'], t['head_new'], 1)
    s = s.replace(t['tail_old'], t['block'] + '*Last updated: 2026-11-16（R20 补录 R19 批次接口表）｜ 道莅工控代码库产品总监*', 1)
    open(p, 'w', encoding='utf-8', newline='').write(s)
    print('ok', p)
