# MANUAL_DL_Process — DL_Process 工艺模板库使用说明书

> **子库定位**：Level 2 行业工艺与通用工站模板层（依赖 Level 0~1）。
> **兼容平台**：CODESYS V3.5+ ｜ TwinCAT 3 ｜ 汇川 InoProShop
> **依赖**：见对应 VERSION.md 依赖声明。

> **状态说明（R19 留档）**：本子库历史组件（30 件）的逐件接口表因早期手册缺失尚未补齐，按 R20 计划分批补录；本节先收录 R19 批次 2 件的完整接口表。组件语义、引脚单位与码位详见各 .st 头注释（100% 中文注释规范自 R6 起全库强制）。

---

## R19 组件接口表（2026-11-16，本子库 2 件）

### `FB_DL_DrumLevelThreeElem`
- **功能**：汽包水位三冲量单泵轻量版（增量式给定 + 越限锁存）
- **输入引脚**：bEnable、bReset、fLevel、fLevelSp、fSteamFlow、fFeedFlow、fLevelGain、fSteamGain、fFeedGain、fLevelLow、fLevelHigh、fOutMin、fOutMax（语义与单位见 .st 头注释）
- **输出引脚**：fFeedSp、bLevelLow、bLevelHigh、bInterlockTrip、bLimited、eErr、bError、bValid
- **码位**：16#0005_01D6 用 / 16#0005_01D7 预留 ｜ 16#0005_0305 用 / 16#0005_0306 用 / 16#0005_0307 用

### `FB_DL_VacCupRingCtrl`
- **功能**：多吸盘环状拾放（逐通道确认/少吸判据/分组释放/降级放行）
- **输入引脚**：bEnable、bReset、bCmdPick、bCmdRelease、auVacuumOk、afVacuum、uCupCount、uMinCupsRequired、fVacMin、tConfirmTime、bAllowDegrade、bReleaseOuterFirst（语义与单位见 .st 头注释）
- **输出引脚**：auValveOut、bPicked、bReleased、uOkCups、bDegraded、bPickFailed、uPickCount、eErr、bError
- **码位**：16#0005_01D8 用 / 16#0005_01D9 预留 ｜ 16#0005_0308 用 / 16#0005_0309 用 / 16#0005_030A 用

---

*Last updated: 2026-11-16（R19 创建骨架 + R19 批次接口表）｜ 道莅工控代码库产品总监*

---

## 附录 · R25 批次接口表（2026-11-17，共 9 件）

> 引脚名与类型均由 `.st` 源码 VAR_INPUT / VAR_OUTPUT 段机读提取（不凭记忆）；单位与工程量纲见各件头注释「单位表」。

### FB_DL_RoomClimateCtrl ｜ 房间温湿度双回路耦合控制（DL_Process v1.0.1）
- **输入引脚**：`fTempSetC`（LREAL）、`fTempMeasC`（LREAL）、`fRhSetPct`（LREAL）、`fRhMeasPct`（LREAL）、`fTempBandK`（LREAL 缺省 0.5）、`fRhBandPct`（LREAL 缺省 3.0）、`fChwSupplyC`（LREAL）、`fDewMarginK`（LREAL 缺省 1.5）、`fKpValvePctPerK`（LREAL 缺省 12.0）、`fTiTempS`（LREAL 缺省 180.0）、`fKpDehumPctPerPct`（LREAL 缺省 5.0）、`fTiRhS`（LREAL 缺省 240.0）、`uDeltaTimeMs`（UDINT）、`bEnable`（BOOL）、`bReset`（BOOL）
- **输出引脚**：`fCoolValvePct`（LREAL）、`fHeatValvePct`（LREAL）、`fDehumValvePct`（LREAL）、`fHumValvePct`（LREAL）、`bCondensationRisk`（BOOL）、`bConflictArbitrated`（BOOL）、`fDewPointC`（LREAL）、`bAtLimit`（BOOL）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_RoomClimateState）
- **码位**：`16#0005_0400` ｜ `16#0005_0401` ｜ `16#0005_0342` ｜ `16#0005_0343` ｜ `16#0005_0344`

### FB_DL_WeightCheckReject ｜ 动态称重与剔除控制（DL_Process v1.0.0）
- **输入引脚**：`fWeightG`（LREAL）、`fWeightMinG`（LREAL）、`fWeightMaxG`（LREAL）、`nFilterSamples`（INT 缺省 5）、`bProductPresent`（BOOL）、`bRejectFb`（BOOL）、`tRejectWindow`（TIME 缺省 T#500MS）、`tSettle`（TIME 缺省 T#200MS）、`uDeltaTimeMs`（UDINT）、`bEnable`（BOOL）、`bReset`（BOOL）
- **输出引脚**：`fWeightFilteredG`（LREAL）、`bPass`（BOOL）、`bRejectCmd`（BOOL）、`nUnderCount`（UDINT）、`nOverCount`（UDINT）、`nRejectCount`（UDINT）、`bRejectFailed`（BOOL）、`bNoProduct`（BOOL）、`bStopLine`（BOOL）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_WeightRejectState）
- **码位**：`16#0005_0402` ｜ `16#0005_0403` ｜ `16#0005_0345` ｜ `16#0005_0346` ｜ `16#0005_0347`

### FB_DL_CasePackerPattern ｜ 装箱排列模式生成（DL_Process v1.0.0）
- **输入引脚**：`nCols`（INT）、`nRows`（INT）、`nLayers`（INT）、`fPitchXMm`（LREAL）、`fPitchYMm`（LREAL）、`fLayerGapMm`（LREAL）、`eInterlock`（E_DL_PackInterlock）、`nBoxCount`（INT）、`bEnable`（BOOL）、`bReset`（BOOL）
- **输出引脚**：`nSeqIndex`（INT）、`fTargetXMm`（LREAL）、`fTargetYMm`（LREAL）、`fTargetZMm`（LREAL）、`fTargetRotDeg`（LREAL）、`bStepDone`（BOOL）、`bLast`（BOOL）、`nSlotCount`（INT）、`nEmptySlots`（INT）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_CasePackState）
- **码位**：`16#0005_0404` ｜ `16#0005_0405` ｜ `16#0005_0348` ｜ `16#0005_0349` ｜ `16#0005_034A`

### FB_DL_BatteryTestCycler ｜ 单通道电池充放电工步机（DL_Process v1.0.1）
- **输入引脚**：`fVoltV`（LREAL）、`fCurrentA`（LREAL）、`fTempC`（LREAL）、`fCcCurrentA`（LREAL）、`fCvVoltV`（LREAL）、`fCutoffCurrentA`（LREAL）、`fDiscCurrentA`（LREAL）、`fDiscCutoffV`（LREAL）、`tRestCharge`（TIME 缺省 T#10M）、`tRestDisc`（TIME 缺省 T#10M）、`tMaxStep`（TIME 缺省 T#120M）、`fCapNomAh`（LREAL）、`fVoltMaxV`（LREAL）、`fVoltMinV`（LREAL）、`fTempMaxC`（LREAL）、`bStart`（BOOL）、`bStop`（BOOL）、`bReset`（BOOL）、`uDeltaTimeMs`（UDINT）
- **输出引脚**：`eStep`（E_DL_BatteryCycleState）、`fCurrentSetA`（LREAL）、`fVoltLimitV`（LREAL）、`fChargedAh`（LREAL）、`fDischargedAh`（LREAL）、`fCapacityRatioPct`（LREAL）、`bStepDone`（BOOL）、`tStepElapsed`（TIME）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）
- **码位**：`16#0005_0406` ｜ `16#0005_0407` ｜ `16#0005_034B` ｜ `16#0005_034C` ｜ `16#0005_034D`

### FB_DL_PalletizerLayerSeq ｜ 码垛层排布顺控（DL_Process v1.0.1）
- **输入引脚**：`nCasePerLayer`（INT）、`nLayersPerPallet`（INT）、`fPalletLengthMm`（LREAL）、`fPalletWidthMm`（LREAL）、`fCaseLengthMm`（LREAL）、`fCaseWidthMm`（LREAL）、`fLayerHeightMm`（LREAL）、`bOddLayerRotate`（BOOL）、`bCaseReady`（BOOL）、`bGripDone`（BOOL）、`tGripTimeout`（TIME 缺省 T#8S）、`bStart`（BOOL）、`bStop`（BOOL）、`bReset`（BOOL）、`uDeltaTimeMs`（UDINT）
- **输出引脚**：`nLayerIndex`（INT）、`nPosIndex`（INT）、`fTargetXMm`（LREAL）、`fTargetYMm`（LREAL）、`fTargetZMm`（LREAL）、`fTargetRotDeg`（LREAL）、`bPlaceCmd`（BOOL）、`bLayerDone`（BOOL）、`bPalletDone`（BOOL）、`nCaseCount`（INT）、`uPalletCount`（UDINT）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_PalletLayerState）
- **码位**：`16#0005_0408` ｜ `16#0005_0409` ｜ `16#0005_034E` ｜ `16#0005_034F` ｜ `16#0005_0350`

### FB_DL_SplicerAutoJoint ｜ 自动接膜零停机顺控（DL_Process v1.0.1）
- **输入引脚**：`fUnwindDiaMm`（LREAL）、`fCoreDiaMm`（LREAL）、`fFullDiaMm`（LREAL）、`fWebSpeedMpm`（LREAL）、`fNewRollSpeedMpm`（LREAL）、`fRemainWarnPct`（LREAL 缺省 15.0）、`fSyncTolPct`（LREAL 缺省 2.0）、`tSyncHold`（TIME 缺省 T#500MS）、`tPreAccelMax`（TIME 缺省 T#20S）、`tJointMax`（TIME 缺省 T#5S）、`bNewRollReady`（BOOL）、`bKnifeHome`（BOOL）、`bTapeOk`（BOOL）、`bStart`（BOOL）、`bStop`（BOOL）、`bReset`（BOOL）、`uDeltaTimeMs`（UDINT）
- **输出引脚**：`bWarnLowRoll`（BOOL）、`bPreAccelCmd`（BOOL）、`bSyncOk`（BOOL）、`bCutCmd`（BOOL）、`bJointDone`（BOOL）、`fRemainPct`（LREAL）、`uJointCount`（UDINT）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_SplicerState）
- **码位**：`16#0005_040A` ｜ `16#0005_040B` ｜ `16#0005_0351` ｜ `16#0005_0352` ｜ `16#0005_0353`

### FB_DL_ChillerSeqMgr ｜ 冷水机组群控调度（DL_Process v1.0.0）
- **输入引脚**：`abChillerReady`（ARRAY[0..5] OF BOOL）、`abChillerRunning`（ARRAY[0..5] OF BOOL）、`abChillerFault`（ARRAY[0..5] OF BOOL）、`fSupplyC`（LREAL）、`fReturnC`（LREAL）、`fLoadPct`（LREAL）、`fStageUpThrPct`（LREAL 缺省 85.0）、`fStageDownThrPct`（LREAL 缺省 40.0）、`tStageUpDelay`（TIME 缺省 T#10M）、`tStageDownDelay`（TIME 缺省 T#15M）、`tMinRun`（TIME 缺省 T#15M）、`tMinStop`（TIME 缺省 T#10M）、`fSupplyLowC`（LREAL 缺省 4.0）、`bEnable`（BOOL）、`bReset`（BOOL）、`uDeltaTimeMs`（UDINT）
- **输出引脚**：`abStartCmd`（ARRAY[0..5] OF BOOL）、`nLeadChiller`（INT）、`nRunningCmd`（INT）、`fLoadAvgPct`（LREAL）、`bStageUpPending`（BOOL）、`bStageDownPending`（BOOL）、`bNoAvailable`（BOOL）、`bLowSupplyProtect`（BOOL）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_ChillerGroupState）
- **码位**：`16#0005_040C` ｜ `16#0005_040D` ｜ `16#0005_0354` ｜ `16#0005_0355` ｜ `16#0005_0356`

### FB_DL_FormationChannelMgr ｜ 化成/分容柜通道调度（DL_Process v1.0.0）
- **输入引脚**：`abChBusy`（ARRAY[0..15] OF BOOL）、`abChFault`（ARRAY[0..15] OF BOOL）、`abChDone`（ARRAY[0..15] OF BOOL）、`nChannelCount`（INT 缺省 16）、`bAllocReq`（BOOL）、`bBatchStart`（BOOL）、`bBatchAbort`（BOOL）、`bEnable`（BOOL）、`bReset`（BOOL）
- **输出引脚**：`nAllocatedCh`（INT）、`bAllocOk`（BOOL）、`abChBlocked`（ARRAY[0..15] OF BOOL）、`abChCmdStart`（ARRAY[0..15] OF BOOL）、`nDoneCount`（INT）、`nFaultCount`（INT）、`bBatchDone`（BOOL）、`bBatchAborted`（BOOL）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_FormationChState）
- **码位**：`16#0005_040E` ｜ `16#0005_040F` ｜ `16#0005_0357` ｜ `16#0005_0358` ｜ `16#0005_0359`

### FB_DL_SolarStringGroundFault ｜ 光伏组串对地绝缘阻抗检测（DL_Process v1.0.1）
- **输入引脚**：`fPosToGroundV`（LREAL）、`fNegToGroundV`（LREAL）、`fBusV`（LREAL）、`fBridgeKOhm`（LREAL 缺省 100.0）、`fWarnKOhm`（LREAL 缺省 1000.0）、`fAlarmKOhm`（LREAL 缺省 100.0）、`nConfirmSamples`（INT 缺省 3）、`bEnable`（BOOL）、`bReset`（BOOL）
- **输出引脚**：`fInsPosKOhm`（LREAL）、`fInsNegKOhm`（LREAL）、`fInsTotalKOhm`（LREAL）、`bWarn`（BOOL）、`bAlarm`（BOOL）、`bUnbalanced`（BOOL）、`bUndecidable`（BOOL）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_StringInsState）
- **码位**：`16#0005_0410` ｜ `16#0005_0411` ｜ `16#0005_035A` ｜ `16#0005_035B` ｜ `16#0005_035C`

*Last updated: 2026-11-17（R25 追加接口表 20 件）｜ 道莅工控代码库产品总监*

## R68 新增件与终审就地修（2026-11-22）

- `FB_DL_StretchWrapSeq` / `FB_DL_OutdoorTempReset` / `FB_DL_KilnPressureCtrl` / `FB_DL_TruckScaleSeq`（R68）：包装顺控 / OAT 重置 / 窑压控制 / 过磅称重；`StretchWrapSeq` 与 `TruckScaleSeq` 于 R68 终审升 v1.0.1（总圈上限 510 / 超时清窗单拍化），引脚契约不变。
