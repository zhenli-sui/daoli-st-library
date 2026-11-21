# MANUAL_DL_Device — DL_Device 标准设备抽象库使用说明书

> **子库定位**：Level 1 标准物理设备抽象与 OOP 接口层（气缸/阀/电机/变频器/诊断/参数事务）。
> **兼容平台**：CODESYS V3.5+ ｜ TwinCAT 3 ｜ 汇川 InoProShop
> **依赖**：见对应 VERSION.md 依赖声明。

> **状态说明（R19 留档）**：本子库历史组件（57 件）的逐件接口表因早期手册缺失尚未补齐，按 R20 计划分批补录；本节先收录 R19 批次 4 件的完整接口表。组件语义、引脚单位与码位详见各 .st 头注释（100% 中文注释规范自 R6 起全库强制）。

---

## R19 组件接口表（2026-11-16，本子库 4 件）

### `FB_DL_DeviceHealthArbiter`
- **功能**：多源设备健康仲裁（NE107 六态，编号即优先级）
- **输入引脚**：bEnable、bReset、aeHealth、auChannelId、uSrcCount、bIncludeMaintenance（语义与单位见 .st 头注释）
- **输出引脚**：eAggHealth、uFirstIdx、uFirstChannel、auLevelMask、uFaultSrcCount、bDegraded、eErr、bError
- **码位**：16#0003_016A 用 / 16#0003_016B 预留 ｜ 16#0003_0330 用 / 16#0003_0331 用 / 16#0003_0332 预留

### `FB_DL_ProfinetAlarmDiag`
- **功能**：PROFINET 通道诊断八类聚合（首出通道/分类计数/NE107 出口）
- **输入引脚**：auChannelNo、auChannelProp、auErrType、auExtErrType、audAddValue、uEntryCount（语义与单位见 .st 头注释）
- **输出引脚**：uChannelMask、uFirstChannel、uFirstErrType、auClassCount、bMaintenanceOnly、bSystemLevel、eHealth、eErr、bError、bValid
- **码位**：16#0003_016C 用 / 16#0003_016D 预留 ｜ 16#0003_0333 用 / 16#0003_0334 用 / 16#0003_0335 预留

### `FB_DL_EscChuckCurrentMonitor`
- **功能**：半导体 ESC 静电吸附电流监视（吸附/释放三段，失吸与打火分型）
- **输入引脚**：bEnable、bReset、bChuckOn、fChuckCurrent、fChuckVoltage、fCurMin、fCurMax、fSparkRise、tBuildTime、tConfirmTime、tSampleTime（语义与单位见 .st 头注释）
- **输出引脚**：bAttached、bSpark、bLeakTrend、bDegraded、eHealth、uAttachCount、eErr、bError
- **码位**：16#0003_016E 用 / 16#0003_016F 预留 ｜ 16#0003_0336 用 / 16#0003_0337 用 / 16#0003_0338 用

### `FB_DL_DeviceParamWrite`
- **功能**：设备参数写回事务（备份→白名单写→读回复核→回滚，七态机）
- **输入引脚**：bEnable、bExecute、bAbort、bReset、auIndex、afWriteValue、abWritable、afActual、uCount、fVerifyTol、tWriteTimeout、tVerifyTimeout（语义与单位见 .st 头注释）
- **输出引脚**：bBusy、bDone、bRollback、uWritten、uSkipped、uFailedIdx、afReadback、uActiveIdx、bWriteNow、eErr、bError
- **码位**：16#0003_0170 用 / 16#0003_0171 预留 ｜ 16#0003_0339 用 / 16#0003_033A 用 / 16#0003_033B 用

---

*Last updated: 2026-11-16（R19 创建骨架 + R19 批次接口表）｜ 道莅工控代码库产品总监*

---

## 附录 · R25 批次接口表（2026-11-17，共 4 件）

> 引脚名与类型均由 `.st` 源码 VAR_INPUT / VAR_OUTPUT 段机读提取（不凭记忆）；单位与工程量纲见各件头注释「单位表」。

### FB_DL_InverterGridSync ｜ 逆变器并网同步条件监视（DL_Device v1.0.0）
- **输入引脚**：`afGridVoltV`（ARRAY[0..2] OF LREAL）、`fGridFreqHz`（LREAL）、`fInvFreqHz`（LREAL）、`fGridPhaseDeg`（LREAL）、`fInvPhaseDeg`（LREAL）、`fVoltTolPct`（LREAL 缺省 10.0）、`fFreqTolHz`（LREAL 缺省 0.2）、`fPhaseTolDeg`（LREAL 缺省 10.0）、`tConfirm`（TIME 缺省 T#2S）、`bPhaseSeqOk`（BOOL）、`bEnable`（BOOL）、`bReset`（BOOL）
- **输出引脚**：`bSyncOk`（BOOL）、`bPermitClose`（BOOL）、`fVoltDiffPct`（LREAL）、`fFreqDiffHz`（LREAL）、`fPhaseDiffDeg`（LREAL）、`uBlockMask`（WORD）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_GridSyncState）
- **码位**：`16#0003_0190` ｜ `16#0003_0191` ｜ `16#0003_0369` ｜ `16#0003_036A` ｜ `16#0003_036B`

### FB_DL_HeatPumpDefrost ｜ 空气源热泵除霜判据与除霜态时序（DL_Device v1.0.0）
- **输入引脚**：`fCoilC`（LREAL）、`fAmbC`（LREAL）、`fAmbRhPct`（LREAL）、`bCompRunning`（BOOL）、`fCoilAmbDeltaK`（LREAL 缺省 8.0）、`fAmbWinLowC`（LREAL 缺省 -5.0）、`fAmbWinHighC`（LREAL 缺省 15.0）、`fRhMinPct`（LREAL 缺省 50.0）、`fExitCoilC`（LREAL 缺省 12.0）、`tMinCompRun`（TIME 缺省 T#45M）、`tDefrostMax`（TIME 缺省 T#10M）、`tDefrostGap`（TIME 缺省 T#30M）、`bEnable`（BOOL）、`bReset`（BOOL）
- **输出引脚**：`bDefrostReq`（BOOL）、`bDefrostActive`（BOOL）、`tDefrostElapsed`（TIME）、`fDeltaK`（LREAL）、`bBlockedByGap`（BOOL）、`bOutOfWindow`（BOOL）、`uDefrostCount`（UDINT）、`uTimeoutCount`（UDINT）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_DefrostState）
- **码位**：`16#0003_0192` ｜ `16#0003_0193` ｜ `16#0003_036C` ｜ `16#0003_036D` ｜ `16#0003_036E`

### FB_DL_VavBoxCtrl ｜ 压力无关型（DL_Device v1.0.1）
- **输入引脚**：`fFlowSetM3h`（LREAL）、`fFlowMeasM3h`（LREAL）、`fFlowMinM3h`（LREAL）、`fFlowMaxM3h`（LREAL）、`fKpPctPerM3h`（LREAL 缺省 0.02）、`fTiS`（LREAL 缺省 120.0）、`fOpenMinPct`（LREAL 缺省 20.0）、`fOpenMaxPct`（LREAL 缺省 100.0）、`fDamperFbPct`（LREAL）、`bDamperFbValid`（BOOL）、`fFbTolPct`（LREAL 缺省 10.0）、`tFbDelay`（TIME 缺省 T#10S）、`uDeltaTimeMs`（UDINT）、`bEnable`（BOOL）、`bReset`（BOOL）
- **输出引脚**：`fDamperCmdPct`（LREAL）、`bAtMin`（BOOL）、`bAtMax`（BOOL）、`fFlowErrM3h`（LREAL）、`bFbMismatch`（BOOL）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_VavState）
- **码位**：`16#0003_0194` ｜ `16#0003_0195` ｜ `16#0003_036F` ｜ `16#0003_0370` ｜ `16#0003_0371`

### FB_DL_WaferMapping ｜ 晶圆花篮（FOUP）Mapping（DL_Device v1.0.0）
- **输入引脚**：`abSlotSensor`（ARRAY[0..24] OF BOOL）、`nSlotCount`（INT 缺省 25）、`fDoubleThickPct`（LREAL 缺省 1.5）、`tScanTimeout`（TIME 缺省 T#10S）、`bEnable`（BOOL）、`bReset`（BOOL）
- **输出引脚**：`abSlotOccupied`（ARRAY[0..24] OF BOOL）、`aeSlotKind`（ARRAY[0..24] OF E_DL_SlotKind）、`nOccupiedCount`（INT）、`bMapValid`（BOOL）、`bAnyAnomaly`（BOOL）、`nAnomalyCount`（INT）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_WaferMapState）
- **码位**：`16#0003_0196` ｜ `16#0003_0197` ｜ `16#0003_0372` ｜ `16#0003_0373` ｜ `16#0003_0374`

*Last updated: 2026-11-17（R25 追加接口表 20 件）｜ 道莅工控代码库产品总监*
