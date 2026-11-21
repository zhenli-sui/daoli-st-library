# -*- coding: utf-8 -*-
"""R22 stage-6: append interface tables to six manuals (append-only)."""
import re

manuals = {
 "DL_Base/MANUAL_DL_Base.md": ("""

---

## R22 批次接口表（R22 追加 · 2 件）

### FC_DL_FirstSetBit ｜ 首个置位位定位（DL_Base / BitString ｜ FUNCTION → BOOL）
- **输入引脚**：`uValue`（LWORD 待扫位串）、`uWidth`（UINT 有效位宽 8/16/32/64，缺省 64）、`bHighFirst`（BOOL TRUE 高位优先）
- **输出引脚**：`uBitIndex`（UINT 0 基位号）、`bFound`（BOOL）、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0001_0462`（全零无置位位）/ `0463`（位宽已钳位）｜ 故障 `16#0001_03B1`（位宽为 0）
- **典型用例**：状态字→首个故障位号、IO 字→首个空位；宽 64 走常量掩码，全程无 `SHL(x,64)`。

### FB_DL_FrequencyMeasure ｜ 门时计数测频（DL_Base / Timing）
- **输入引脚**：`bPulse`、`bEnable`、`tGateTime`（TIME 缺省 T#100MS，1 ms~10 s 钳位）、`fLowFreqDead`（REAL Hz 缺省 0.5）
- **输出引脚**：`fFreq`（REAL Hz，分辨率 1/tGateTime）、`fFreqRes`、`uLastCount`、`bValid`、`eErr`、`bError`
- **码位**：信息 `16#0001_0464`（门时间已钳位）/ `0465`（低于死区按 0 输出）｜ 故障 `16#0001_03B4`（门时间为 0）/ `03B5`（计数回退不可信，含状态机兜底复用）
- **遗留假设**：门切换拍不确定度 ±1 计数（±1/tGateTime Hz），不得声称精确。


*Last updated: 2026-11-16（R22 追加接口表）｜ 道莅工控代码库产品总监*
"""),
 "DL_MathData/MANUAL_DL_MathData.md": ("""

---

## R22 批次接口表（R22 追加 · 3 件 · 定宽数值字段族）

### FC_DL_IntToFixedField ｜ 整数→定宽字段（DL_MathData / DataFormat ｜ FUNCTION → BOOL）
- **输入引脚**：`nValue`（DINT 全域）、`uWidth`（UINT 缺省 8，1~20 钳位）、`bZeroPad`（BOOL 缺省 TRUE）、`bForceSign`（BOOL）
- **输出引脚**：`sField`（STRING(20) 右对齐）、`uFieldLen`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0001_045C`（宽度已钳位）｜ 故障 `16#0001_03A8`（宽度不足拒绝编码，不输出半截数字）
- **要点**：负域取模分解防 DINT 最小值；与 `FixedFieldToInt` 构成 round-trip 验收对。

### FC_DL_FixedFieldToInt ｜ 定宽字段→整数（DL_MathData / DataFormat ｜ FUNCTION → BOOL）
- **输入引脚**：`sField`（STRING(20)）、`uWidth`（UINT 缺省 8）、`bAllowLeadingSpace`、`bAllowSign`
- **输出引脚**：`nValue`（DINT）、`uParsedLen`、`nErrPos`（1 基首个非法字符位置）、`bSaturated`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0001_045E`（已剥离前导填充）/ `045F`（超域已饱和）｜ 故障 `16#0001_03AB`（非法字符）/ `03AC`（有效字符数为 0 或宽度非法）

### FC_DL_LrealToFixedField ｜ 浮点→定宽定点文本（DL_MathData / DataFormat ｜ FUNCTION → BOOL）
- **输入引脚**：`fValue`（LREAL）、`uIntDigits`（UINT 缺省 6，1~15）、`uDecDigits`（UINT 缺省 3，0~6）、`bRound`、`bForceSign`
- **输出引脚**：`sField`（STRING(24)）、`uFieldLen`、`bSaturated`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0001_0460`（钳位或舍入进位复用）/ `0461`（整数部分已饱和）｜ 故障 `16#0001_03AE`（非有限输入，不输出 'NaN' 冒充报文）/ `03AF`（字段装不下）
- **要点**：禁 `LREAL_TO_STRING`；非有限用 R79 精确判据；整数 > 15 位时输入本身已失真（遗留假设段留档）。


*Last updated: 2026-11-16（R22 追加接口表）｜ 道莅工控代码库产品总监*
"""),
 "DL_Algo/MANUAL_DL_Algo.md": ("""

---

## R22 批次接口表（R22 追加 · 2 件 · 燃烧控制律）

### FB_DL_CrossLimitSelect ｜ 燃烧双交叉限幅（DL_Algo / ProcessControl）
- **输入引脚**：`fMasterOut`（%）、`fAirFlow`（Nm3/h）、`fGasFlow`（Nm3/h）、`fAirFuelRatio`（缺省 10.0）、`fLeadMargin`（倍 缺省 1.05，须 > 1.0）、`bAirLead`、`bEnable`
- **输出引脚**：`fAirSp`（%）、`fGasSp`（%）、`bLimited`、`fLimitMargin`（%）、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0002_2B01`（空气侧受限）/ `2B02`（燃气侧受限）｜ 故障 `2B10`（空燃比/裕度非法，双侧归零）/ `2B11`（非有限保持末值）/ `2B12`（兜底）
- **要点**：依赖收窄——迟滞与限幅内联等价实现（不引用 DL_Base/DL_MathData）。

### FB_DL_ExcessAirTrim ｜ 氧量修正（DL_Algo / ProcessControl）
- **输入引脚**：`fO2Meas`（%）、`fO2Target`（% 缺省 3.0）、`fO2Deadband`（% 缺省 0.3）、`fTrimLimit`（% 缺省 5.0）、`fTrimStep`（% 缺省 0.05）、`fLoadRate`（%/s）、`fRateFreeze`（%/s 缺省 2.0）、`tConfirm`（缺省 T#30S）、`bEnable`
- **输出引脚**：`fTrim`（%）、`bActive`、`bFrozen`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0002_2C01`（死区内不修正）/ `2C02`（负荷变化率超限已冻结）｜ 故障 `2C10`（参数非法）/ `2C11`（非有限保持末值）/ `2C12`（兜底）


*Last updated: 2026-11-16（R22 追加接口表）｜ 道莅工控代码库产品总监*
"""),
 "MANUAL_DL_Device.md": ("""

---

## R22 批次接口表（R22 追加 · 4 件）

### FB_DL_SlitValveInterlock ｜ 真空闸阀互斥互锁（DL_Device / ValveInterlock）
- **输入引脚**：`bRequest`、`bAtmDoorClosed`、`bAtmDoorOpen`、`fChamberVac`（Pa）、`fVacThreshold`（Pa 缺省 100.0）、`bArmRetracted`、`tFbTimeout`（缺省 T#3S）、`bEnable`
- **输出引脚**：`bValveOpenCmd`、`bValveCloseCmd`（两路互斥先清后置）、`bInterlockOk`、`uBlockMask`（1 真空不足 / 2 门未关 / 4 臂未退 / 8 反馈超时）、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0003_0172`（放行开阀）/ `0173`（无位置确认保持指令）｜ 故障 `033C`（联锁拒绝）/ `033D`（门位矛盾按门未关）/ `033E`（真空非法按不足）
- **要点**：保守侧纪律——反馈矛盾按门未关、真空非法按不足；引脚契约无阀体位置反馈，tFbTimeout 语义为「指令已发无位置确认」的等待窗（收窄声明见头注释）。

### FB_DL_PressureReliefMonitor ｜ 安全阀起跳/回座监视（DL_Device / SafetyMonitor）
- **输入引脚**：`fUpPressure`（bar g）、`fDnPressure`（bar g）、`fSetPressure`（缺省 10.0）、`fBlowdown`（倍 缺省 0.90，须在 0~1 之间）、`tConfirm`、`tMinLift`（缺省 T#500MS）、`uMaintLimit`（次 缺省 50）、`bEnable`
- **输出引脚**：`bLifted`、`nLiftCount`（次）、`tOpenTotal`（ms）、`fPeakPressure`（bar g）、`eHealth`（`E_DL_Ne107Status` 引用唯一属主）、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0003_0174`（起跳已记录）/ `0175`（短起跳滤除）｜ 故障 `033F`（整定/回座比非法）/ `0340`（非有限保持台账）/ `0341`（兜底）

### FB_DL_SteamTrapMonitor ｜ 疏水阀堵塞/泄漏诊断（DL_Device / Diagnostic）
- **输入引脚**：`fTin`（°C）、`fTout`（°C）、`fDeltaNormal`（K 缺省 10.0）、`fDeltaLeak`（K 缺省 5.0）、`fTinMin`（°C 缺省 80.0）、`tConfirm`、`bEnable`
- **输出引脚**：`fDelta`（K）、`bNormal`、`bSteamLeak`、`bBlocked`、`eHealth`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0003_0176`（正常带）/ `0177`（工况未建立冻结判定）｜ 故障 `0342`（温度非有限）/ `0343`（判据阈值自相矛盾）/ `0344`（兜底）
- **要点**：冷态（fTin < fTinMin）冻结全部故障判定——防停机全域「泄漏」误报；健康映射：泄漏→eOutOfSpec、堵塞→eMaintenanceReq。

### FB_DL_LevelRadarValidate ｜ 雷达液位回波可信度仲裁（DL_Device / SignalQuality）
- **输入引脚**：`fLevel`（m）、`fQuality`（%）、`fSnr`（dB）、`fSpan`（m 缺省 10.0）、`fQualityMin`（% 缺省 40.0）、`fSnrMin`（dB 缺省 10.0）、`fRateLimit`（m/s 缺省 0.5）、`tSample`、`tConfirm`、`bEnable`
- **输出引脚**：`fLevelOut`（m，可信则实时值否则末次可信值）、`bTrusted`、`uSuspectMask`（1 置信度 / 2 信噪比 / 4 超量程 / 8 跳变）、`eHealth`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0003_0178`（质量低于门限保持末次可信值）/ `0179`（变化率跳变单拍剔除）｜ 故障 `0345`（量程/门限非法）/ `0346`（非有限不更新发布值）/ `0347`（兜底）

### 续补说明 / Remaining（R22 更新）
本手册现覆盖至 R22 批次；`DL_Device` 余下 R1~R21 历史件（约 53 件，含 16 只 `I_DL_*` 契约）接口表继续按「每轮 ≤10 件、最近两轮优先倒序」补录（R88 纪律）。


*Last updated: 2026-11-16（R22 追加接口表 4 件）｜ 道莅工控代码库产品总监*
"""),
 "MANUAL_DL_Motion.md": ("""

---

## R22 批次接口表（R22 追加 · 5 件 · 轴侧安全层开层）

### FB_DL_AxisBrakeSeq ｜ 伺服抱闸时序（DL_Motion / AxisSafety）
- **输入引脚**：`bEnableReq`、`fActVel`（mm/s）、`fStandstillVel`（mm/s 缺省 1.0）、`bBrakeReleaseFb`、`bBrakeFbAvailable`（缺省 TRUE）、`tBrakeRelease`（缺省 T#200MS）、`tBrakeHold`（缺省 T#300MS）、`tStandstill`（缺省 T#100MS）、`tFbTimeout`（缺省 T#2S，**须 > tBrakeRelease**）
- **输出引脚**：`bServoEnable`、`bBrakeReleaseCmd`、`bSeqDone`（单拍脉冲）、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0004_01D5`（无反馈按时间序列放行）/ `01D6`（等待延长，两处共用靠状态区分）｜ 故障 `02EA`（释放反馈超时禁止使能，全失电）/ `02EB`（未静止拒绝断使能，有转矩时保持带使能+抱闸打开）/ `02EC`（参数非法/非有限/兜底，三支复用）
- **要点**：上电序先释放后使能、断电序先静止后抱闸再断使能——两序写反即掉轴；eEnabled 不得直跳 eDisabled。

### FB_DL_VirtualMasterAxis ｜ 虚拟主轴相位源（DL_Motion / MasterSource）
- **输入引脚**：`bEnable`、`fVelSet`（mm/s）、`fAccLimit`/`fDecLimit`（mm/s² 缺省 1000.0）、`bHold`、`bPhaseReset`（上升沿）、`fPosInit`（mm 缺省 0.0）、`tSample`（缺省 T#1MS，禁读系统时钟）
- **输出引脚**：`fMasterPos`（LREAL mm）、`fMasterVel`、`fMasterAcc`、`bReady`、`bLimited`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0004_01D7`（限幅生效边沿发布）/ `01D8`（复位已执行）｜ 故障 `02ED`（采样/速度参数非法，冻结）/ `02EE`（相位超 1.0E15 mm 精度门已冻结，需复位才可恢复）/ `02EF`（兜底）
- **要点（v1.0.1）**：eFault 相位与故障拍均冻结积分，恢复仅经失能复位或 bPhaseReset。

### FB_DL_MotionCmdQueue ｜ 运动指令排队器（DL_Motion / CommandMgmt）
- **输入引脚**：`bEnq`（上升沿）、`fTargetPos`（mm）、`fVelocity`（mm/s）、`bAxisDone`（调用方注入）、`bAxisError`、`bOverwriteOldest`（缺省 TRUE）、`bClear`
- **输出引脚**：`bExec`（单拍）、`fExecPos`、`fExecVel`、`uCount`（0~8）、`bFull`、`uDropped`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0004_01D9`（满队：靠 uDropped 是否自增区分丢最旧/拒绝）/ `01DA`（同目标去重）｜ 故障 `02F0`（非有限拒绝入队不占槽）/ `02F1`（轴故障清队挂起禁止自动续发）/ `02F2`（兜底）
- **要点（v1.0.1）**：eSending 被清队竞态下回 eIdle 不空等 Done；只做 Buffered 语义，Blending 不立（职责边界段留档）。

### FC_DL_CamTableValidate ｜ 凸轮表合法性校验（DL_Motion / CamData ｜ FUNCTION → BOOL）
- **输入引脚**：`afPhase`（ARRAY[0..63] OF REAL，°）、`afSlave`（mm）、`uSegCount`（2~64）、`bCyclic`（缺省 TRUE）、`fPhaseTol`（° 缺省 0.01）、`fMaxSlope`（mm/° 缺省 100.0）
- **输出引脚**：`uFailMask`（1 非单调 / 2 非有限 / 4 未闭合 / 8 斜率超限 / 16 点数非法，全掩码不早退）、`uFailIdx`（1 基首败段号）、`fMaxSlopeFound`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0004_01DB`（非周期表跳过闭合校验）/ `01DC`（斜率超限表仍可用）｜ 故障 `02F3`（非单调/点数非法）/ `02F4`（从轴非有限）/ `02F5`（首尾未闭合）

### FB_DL_AxisInPosMonitor ｜ 到位稳定判定（DL_Motion / AxisMonitor）
- **输入引脚**：`bEnable`、`fActPos`/`fTargetPos`（mm）、`fActVel`（mm/s）、`fPosTol`（mm 缺省 0.05）、`fVelTol`（mm/s 缺省 1.0）、`tSettle`（缺省 T#100MS）、`uChatterLimit`（次 缺省 5）、`tChatterWin`（缺省 T#2S）
- **输出引脚**：`bInPos`、`bSettled`（取放联锁用，出窗即清不锁存跨件）、`uChatterCount`、`bChatterAlarm`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0004_01DD`（入窗未稳定）/ `01DE`（抖振计数按窗清零）｜ 故障 `02F6`（容差/时间参数非法）/ `02F7`（非有限保持上次判定，下游与 bValid 相与）/ `02F8`（兜底）
- **要点**：只判「到位稳定」，跟随误差监视归驱动器（职责划界段见头注释）。

### 续补说明 / Remaining（R22 更新）
本手册现覆盖至 R22 批次；`DL_Motion` 余下 R1~R21 历史件（约 21 件）接口表继续按「每轮 ≤10 件」补录。


*Last updated: 2026-11-16（R22 追加接口表 5 件）｜ 道莅工控代码库产品总监*
"""),
 "MANUAL_DL_Process.md": ("""

---

## R22 批次接口表（R22 追加 · 4 件）

### FB_DL_CompressorSurgeGuard ｜ 压缩机防喘振（DL_Process / ProcessSafety）
- **输入引脚**：`fSuctionPress`/`fDischargePress`（kPa abs）、`fFlow`（Nm3/h）、`fFlowMinLine`（Nm3/h 缺省 500.0）、`fSurgeMargin`（倍 缺省 0.10）、`fOpenRamp`（%/s 缺省 20.0）、`fCloseRamp`（%/s 缺省 1.0）、`tConfirm`（缺省 T#200MS）、`tSample`（缺省 T#100MS）、`bEnable`
- **输出引脚**：`fBlowoffValve`（% 0~100）、`bSurgeRisk`、`bBlowoffActive`、`fPressureRatio`（倍）、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0005_01DA`（低于危险线已开放空阀）/ `01DB`（出回差带退出放空）｜ 故障 `030B`（参数非法阀全开）/ `030C`（非有限保持末值）/ `030D`（兜底）
- **要点**：两条相反安全方向并列——参数非法阀全开、坏值保持末值；R41 回差退出，eRiskBlowoff 不得被 eNormal 直接抢占。

### FB_DL_ColumnDpCtrl ｜ 精馏塔压差控制（DL_Process / ProcessControl）
- **输入引脚**：`fDpMeas`（kPa）、`fDpSp`（缺省 5.0）、`fDpDeadband`（缺省 0.2）、`fOutMin`/`fOutMax`（%）、`fDpHighLimit`（缺省 8.0）、`fStep`（% 缺省 1.0）、`tConfirm`、`bEnable`
- **输出引脚**：`fRefluxOut`（%）、`fReboilOut`（%）、`bDpHigh`、`bLimited`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0005_01DC`（死区内不调节 或 已退出防冲塔，复用）/ `01DD`（ΔP 越上限已按防冲塔分配）｜ 故障 `030E`（参数非法双输出置 fOutMin）/ `030F`（非有限保持末值）/ `0310`（兜底）

### FB_DL_InertPurgeSeq ｜ 氮气置换顺控（DL_Process / Sequence）
- **输入引脚**：`bStart`、`bAbort`、`fO2Meas`（%）、`bO2SensorOk`、`fO2Target`（% 缺省 2.0）、`uMaxCycles`（次 缺省 3）、`tEvac`/`tFill`/`tHold`（缺省 60/60/30 s）、`fVacOk`（kPa g 缺省 -80.0）、`fVacMeas`（kPa g，抽真空读数由调用方注入）
- **输出引脚**：`bVacValveCmd`、`bN2ValveCmd`、`bVentValveCmd`（三相阀互斥先清后置）、`uCycleDone`（次）、`bDone`、`bFailed`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0005_01DE`（单循环未达标进下一循环）/ `01DF`（氧含量达标）｜ 故障 `0311`（参数非法）/ `0312`（分析仪无效禁止放行）/ `0313`（循环耗尽，含兜底复用）

### FB_DL_BatchTransferSeq ｜ 批次物料转移顺控（DL_Process / Sequence）
- **输入引脚**：`bStart`、`bAbort`、`bSrcValveFb`、`bDstValveFb`、`fTransferred`（m3，调用方积分器注入）、`fVolumeTarget`（m3 缺省 5.0）、`fFlow`（m3/h）、`fDrainFlow`（m3/h 缺省 0.05）、`tDrainVerify`（缺省 T#10S）、`tValveFb`（缺省 T#5S）、`tTimeout`（缺省 T#30M）
- **输出引脚**：`bPumpCmd`、`bSrcValveCmd`、`bDstValveCmd`、`bDrained`、`bDone`、`bFailed`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0005_01E0`（累计量外部注入口径声明）/ `01E1`（排空验证完成）｜ 故障 `0314`（阀位反馈超时不启泵）/ `0315`（超时或参数非法）/ `0316`（兜底）
- **要点（v1.0.1）**：0315 超时分支补置 bError；泵必须在双阀到位后启；bAbort 先停泵后关阀（物理时序分隔 R23 立项，见 ROADMAP §24.1）。

### 续补说明 / Remaining（R22 更新）
本手册现覆盖至 R22 批次；`DL_Process` 余下 R1~R21 历史件（约 28 件）接口表继续按「每轮 ≤10 件」补录。


*Last updated: 2026-11-16（R22 追加接口表 4 件）｜ 道莅工控代码库产品总监*
"""),
}

for path, block in manuals.items():
    s = open(path, encoding="utf-8").read()
    s = re.sub(r"\*Last updated: 2026-11-16（R\d+ [^）]*）｜ 道莅工控代码库产品总监\*\s*$", "", s)
    s = s.rstrip("\n") + "\n" + block.lstrip("\n")
    open(path, "w", encoding="utf-8").write(s)
    print("appended:", path)
