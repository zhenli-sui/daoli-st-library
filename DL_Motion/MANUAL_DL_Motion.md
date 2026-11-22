# MANUAL_DL_Motion — DL_Motion 运动控制库使用说明书

> **子库定位**：Level 1 运动控制 OOP 封装层（基于 PLCopen MC，轴/凸轮/补偿/折算）。
> **兼容平台**：CODESYS V3.5+ ｜ TwinCAT 3 ｜ 汇川 InoProShop
> **依赖**：见对应 VERSION.md 依赖声明。

> **状态说明（R19 留档）**：本子库历史组件（25 件）的逐件接口表因早期手册缺失尚未补齐，按 R20 计划分批补录；本节先收录 R19 批次 4 件的完整接口表。组件语义、引脚单位与码位详见各 .st 头注释（100% 中文注释规范自 R6 起全库强制）。

---

## R19 组件接口表（2026-11-16，本子库 4 件）

### `FB_DL_ExternalEncoderScaler`
- **功能**：外部编码器回绕展开与折算
- **输入引脚**：bEnable、bReset、diRawCount、uCountsPerRev、fPitch、iGearNum、iGearDen、bInvert、fOffset、nMultiTurnBits、tSampleTime（语义与单位见 .st 头注释）
- **输出引脚**：fPosition、liTotalCount、bWrapped、uWrapCount、fVelocity、eErr、bError、bValid
- **码位**：16#0004_01CD 用 / 16#0004_01CE 预留 ｜ 16#0004_02DE 用 / 16#0004_02DF 用 / 16#0004_02E0 用

### `FB_DL_CamPhaseTrim`
- **功能**：凸轮相位在线修调（限速率渐进 + 标记沿一次性补偿，禁浮点 MOD 归一）
- **输入引脚**：bEnable、bReset、fPhaseOffsetCmd、fRateMax、fPhaseLimit、bTrimOnMark、fMarkCorrection、bMarkPulse、tSampleTime（语义与单位见 .st 头注释）
- **输出引脚**：fPhaseOffset、bTrimming、bLimited、uMarkCount、eErr、bError
- **码位**：16#0004_01CF 用 / 16#0004_01D0 预留 ｜ 16#0004_02E1 用 / 16#0004_02E2 用 / 16#0004_02E3 用

### `FB_DL_FilmWebCenter`
- **功能**：膜卷纠偏（EPC/CPC，死区保持/断料保持/限速率）
- **输入引脚**：bEnable、bReset、bAuto、fDeviation、fGain、fManualOffset、fDeadband、fRateMax、fTravelMin、fTravelMax、bWebPresent、tSampleTime（语义与单位见 .st 头注释）
- **输出引脚**：fPositionSp、bInDeadband、bLimited、bWebLost、eErr、bError、bValid
- **码位**：16#0004_01D1 用 / 16#0004_01D2 预留 ｜ 16#0004_02E4 用 / 16#0004_02E5 用 / 16#0004_02E6 用

### `FB_DL_WindingLayerCounter`
- **功能**：卷绕层数与剩余层数计数（卷径交叉校核）
- **输入引脚**：bEnable、bReset、bNewRoll、fCoilDiameter、fCoreDiameter、fThickness、diRevCount、uLayerMax、bDirPositive（语义与单位见 .st 头注释）
- **输出引脚**：uLayerDone、uLayerRemain、bLayerEdge、bInconsistent、fThicknessEst、uRollCount、eErr、bError
- **码位**：16#0004_01D3 用 / 16#0004_01D4 预留 ｜ 16#0004_02E7 用 / 16#0004_02E8 用 / 16#0004_02E9 预留

---

*Last updated: 2026-11-16（R19 创建骨架 + R19 批次接口表）｜ 道莅工控代码库产品总监*

---

## 附录 · R25 批次接口表（2026-11-17，共 2 件）

> 引脚名与类型均由 `.st` 源码 VAR_INPUT / VAR_OUTPUT 段机读提取（不凭记忆）；单位与工程量纲见各件头注释「单位表」。

### FB_DL_StackingAlignCtrl ｜ 叠片对位纠偏控制（DL_Motion v1.0.0）
- **输入引脚**：`fOffsetXPx`（LREAL）、`fOffsetYPx`（LREAL）、`fAngleMrad`（LREAL）、`afPixelToMachine`（ARRAY[0..2, 0..2] OF LREAL）、`fAxisXMinMm`（LREAL）、`fAxisXMaxMm`（LREAL）、`fAxisYMinMm`（LREAL）、`fAxisYMaxMm`（LREAL）、`fNgTolMm`（LREAL 缺省 0.05）、`fNgTolMrad`（LREAL 缺省 2.0）、`bCamValid`（BOOL）、`bAxisInPos`（BOOL）、`bEnable`（BOOL）、`bReset`（BOOL）
- **输出引脚**：`fCorrXMm`（LREAL）、`fCorrYMm`（LREAL）、`fCorrAngleMrad`（LREAL）、`bNg`（BOOL）、`bClamped`（BOOL）、`bReady`（BOOL）、`bMatrixFallback`（BOOL）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_StackAlignState）
- **码位**：`16#0004_01EB` ｜ `16#0004_01EC` ｜ `16#0004_030C` ｜ `16#0004_030D` ｜ `16#0004_030E`

### FB_DL_LabelApplySync ｜ 贴标同步出标控制（DL_Motion v1.0.0）
- **输入引脚**：`nEncoderPulse`（DINT）、`fPulsePerMm`（LREAL 缺省 100.0）、`fLabelPitchMm`（LREAL 缺省 50.0）、`fLeadMm`（LREAL 缺省 2.0）、`fSpeedMinMpm`（LREAL 缺省 5.0）、`bLabelPresent`（BOOL）、`tTriggerHold`（TIME 缺省 T#20MS）、`uDeltaTimeMs`（UDINT）、`bEnable`（BOOL）、`bReset`（BOOL）
- **输出引脚**：`bFireTrigger`（BOOL）、`uLabelsApplied`（UDINT）、`bMissedLabel`（BOOL）、`fPhaseErrMm`（LREAL）、`fWebSpeedMpm`（LREAL）、`bLowSpeed`（BOOL）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_LabelSyncState）
- **码位**：`16#0004_01ED` ｜ `16#0004_01EE` ｜ `16#0004_030F` ｜ `16#0004_0310` ｜ `16#0004_0311`

*Last updated: 2026-11-17（R25 追加接口表 20 件）｜ 道莅工控代码库产品总监*

## R68 新增件与终审就地修（2026-11-22）

- `FB_DL_AxisPowerOnSelfTest`（v1.0.1，R68）：上电自检五步序，`bTestOk` 供使能链消费；R68 终审补组态锁存解除式（原不可重测）。
