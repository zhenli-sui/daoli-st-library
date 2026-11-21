# ROUND_PLAN_R30 —— 道莅代码库 R30 阶段一/二规划书（盘点与锁定 20 件）

**读完即落盘**：编码按批执行，批 1 = offset 1 / limit 5（序 1~5），批 2 = offset 6 / limit 5（序 6~10），批 3 = offset 11 / limit 5（序 11~15），批 4 = offset 16 / limit 5（序 16~20）。每批完成后回写 `VERSION.md` / `MANUAL_DL_*.md` / `CHANGELOG.md` / `README.md` / `LIBRARY_MANUAL.md` 并登记 registry。

---

## 0. 盘点统计（2026-11-18 开账，全部实测）

| 项 | 实测值 | 说明 |
|---|---|---|
| 总库组件数 | **519 / 10000** | registry v2.18.0，last_updated 2026-11-17T23:51:30+08:00 |
| 六库分布 | Base 74 / MathData 161 / Algo 56 / Device 97 / Motion 52 / Process 79 | registry.counts 实测 |
| 今日配额 | **0 / 200**（2026-11-18 开账） | 本轮 20 件全部计入今日 |
| 语料库 | 519 条 | registry components 全量 |
| ROADMAP 待办 | 未勾选条目名 287 个，其中 **150 个勾选框滞后**（组件实际已注册+落盘，属台账虚账）；**真实空位待办 233 条** | 本轮已实测甄别，见 §6.2 滞后清单披露 |
| 源矩阵台账 | 35 行：✔ 9 / ◐ 25 / ☐ 0（另有 1 行分隔线） | 覆盖率 34/35 = 97.1%，无待挖掘 ☐ 行；本轮新件全部取 ◐ 行内「仍待挖」子项与 ROADMAP 空位池 |
| 本轮检索 | **零 WebSearch**（返修件有 R29 裁定方案 + ROADMAP 空位池 233 条充足） | RAW_NOTES_R30.md 留痕 |

**重要盘点发现（R30 新账）**：ROADMAP 未勾选条目中 150 个名字已在 registry 注册且 `.st` 已落盘（如 `FB_DL_ChamberGateValve`、`FB_DL_PumpDryRunGuard`、`FB_DL_WindingAlignEdge`、`FC_DL_OrificeFlowCalc` 等），属历轮收口后未回写勾选的台账滞后。本轮选题一律以「registry 全量 name grep + 文件树 ls」双查实测为准，**不信任勾选框**；滞后条目清单移交收口轮批量回写。

---

## 1. 返修件（批次 1 · 序 1）

**FB_DL_AhuFilterDpBank**（DL_Device，v1.0.0 新件入册——原 R29 隔离件从未注册、未入语料，隔离原因见 `_Staging_Raw/2026-11-17/REJECTED_R29/HOLD_REASON_R29.txt`）

- **隔离原因**：红线 7/R40 复合——共享单实例 `tonDeb` 被 4 温区复用，且仅当 `eTarget<>aeStage` 时才刷新（无变化周期 ET 冻结、跨区互相复位）。
- **裁定返修方案（已批准，编码必须照此执行）**：`tonDeb : TON` 改为 **`aTonDeb : ARRAY[1..4] OF TON`**，每温区独立实例；**每个扫描周期对 4 个实例无条件刷新**（`aTonDeb[uZi](IN := ..., PT := tDebounce)` 在 FOR 循环体内每拍调用，不允许放进任何 IF 分支）；候选作废分支传 `IN := FALSE` 显式复位而不是跳过调用。其余对外契约（引脚、码位语义、迟滞分档、低风量冻结、传感器故障档）不变。
- **码位重排**：原隔离件自占 03C5~03C9 作废（从未注册，且 03C5~03D8 已被 R29 在册件合法占用），本件改用实测游标新段 **03D9~03DD**。
- **枚举属主**：registry 无 `E_DL_FilterStage`（全库枚举均随件同文件定义），本件头文件内定义 `E_DL_FilterStage`（eClean/eEarly/eMid/eChange/eSensorFault）并声明全库唯一属主。
- **锁存解除可达自证（R28 终审式 1）**：故障码非锁存式输出（`eErr` 每拍重算、无内部锁存位），`bFrozen` 每拍由当前工况推导，恢复合法输入即恢复，无需解除式。

---

## 2. R30 目标 20 件总表（1 返修 + 19 新件）

分类配比实测裁定：**Device 5（含返修）/ Process 8 / Motion 3 / Algo 2 / MathData 1 / Base 1**。偏离建议配比的裁定理由见 §6.3。

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签(function_tags) | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FB_DL_AhuFilterDpBank | DL_Device | FB_ | 空调箱 4 段过滤器压差四级分档（迟滞+独立去抖+低风量冻结）返修件 | hvac, filter-monitoring, dp-grading, hysteresis, debounce | 7 | 1 |
| 2 | FB_DL_FoupDoorSeq | DL_Device | FB_ | FOUP 开合门与载具联锁顺控（解锁-开门-载具在位-再锁定确认窗） | semiconductor, door-interlock, sequencing, foup | 7 | 1 |
| 3 | FB_DL_CoolantFlowAudit | DL_Device | FB_ | 机台冷却水多支路流量审计（多流量计实例汇总+欠流首出+AlarmManager 分级） | semiconductor, coolant, flow-audit, alarm-management | 6 | 1 |
| 4 | FB_DL_ValvePdiSched | DL_Device | FB_ | 阀岛 PDI 批量读取调度（多 PdiReadScheduler 实例分槽轮询+异常台账） | valve-island, pdi, scheduling, diagnostics | 6 | 1 |
| 5 | FB_DL_RackDiagSummary | DL_Device | FB_ | 机架 Axioline 诊断汇总与首出定位（多 DiagLatch 实例聚合+首出三律） | diagnostics, axioline, first-out, rack | 6 | 1 |
| 6 | FB_DL_WaferScanRouter | DL_Process | FB_ | 晶圆盒扫码路由（扫码契约+花篮位取模索引+分道路由） | semiconductor, barcode-routing, modulo-index, wafer | 7 | 2 |
| 7 | FB_DL_SiloLevelInterlock | DL_Process | FB_ | 料仓高低料位-输送联锁（防溢仓/空跑双联锁+卡料窗） | process-control, silo, interlock, conveyor | 6 | 2 |
| 8 | FB_DL_PalletZoneMerge | DL_Process | FB_ | 码垛前多线合流积放（多 ConveyorZone 级联+上区补跑语义） | packaging, conveyor, merge, accumulation | 7 | 2 |
| 9 | FB_DL_WeightClassifySort | DL_Process | FB_ | 重量四档分级剔除（LimitClassify 判档+剔除口放行+档位计数） | packaging, weight-sorting, classification, reject | 6 | 2 |
| 10 | FB_DL_EmoAndonFab | DL_Process | FB_ | 洁净室 EMO-安灯联动呼叫（四级仲裁复用+门审计联动） | semiconductor, andon, emo, safety-linkage | 6 | 2 |
| 11 | FB_DL_FillWeightCheckweigher | DL_Process | FB_ | 称重剔除秤（重量平滑+欠/超重四档+剔除计数与批统计） | packaging, checkweigher, oiml, reject-count | 6 | 3 |
| 12 | FB_DL_FilmSpliceDetect | DL_Process | FB_ | 薄膜接膜位检测与降速段放行（接口锁存+放行窗+接料计数） | packaging, splice-detection, conveyor, film | 6 | 3 |
| 13 | FB_DL_CoatingGapMeasure | DL_Process | FB_ | 涂布留白（Gap）宽度与边缘对齐判定（像素→mm 标定+区间带+窗口一致性） | lithium-battery, coating, vision-metrology, tolerance | 7 | 3 |
| 14 | FB_DL_TrackerBacktrackCalc | DL_Motion | FB_ | 光伏跟踪支架逆跟踪角度修正（阵列阴影几何，逐排互遮挡角计算） | photovoltaic, solar-tracker, backtrack, geometry | 7 | 3 |
| 15 | FB_DL_LamStepperFeed | DL_Motion | FB_ | 层压机铺膜步进送料（开环步进契约+膜长累计+保养窗冻结） | photovoltaic, laminator, stepper-open-loop, maintenance | 6 | 3 |
| 16 | FB_DL_ElectrodeRollDiameter | DL_Motion | FB_ | 极卷直径跟踪与换卷预警（卷径递推+排线位置联动+换卷阈值预警） | lithium-battery, winding, coil-diameter, warning | 6 | 4 |
| 17 | FB_DL_FanArraySeq | DL_Algo | FB_ | 风机阵列轮值与变频/工频混拖调度（轮值均衡+分级投切消费+混拖互斥） | hvac, fan-array, duty-rotation, staging | 7 | 4 |
| 18 | FB_DL_ChwDifferentialPressure | DL_Algo | FB_ | 冷冻水差压旁通控制（压差平滑+PID 闭环+旁通阀位限幅） | hvac, chw, differential-pressure, pid | 7 | 4 |
| 19 | FC_DL_ChecksumSum64 | DL_MathData | FC_ | LWORD 数组 64 位累加和校验（纯函数，模 2^64 求和+非有限/溢出守卫） | checksum, data-integrity, pure-function, lword | 3 | 4 |
| 20 | FC_DL_BitArraySegCopy | DL_Base | FC_ | 位段数组多段一次搬（源→目标多段批量复制，逐段域校验+整段原子性） | bit-field, array-copy, batch-transfer, lgf-bitlogic | 5 | 4 |

---

## 3. 逐件引脚级规格（3~6 行/件）

**序 1 FB_DL_AhuFilterDpBank**（返修）
- IN：`bEnable:BOOL`；`afDp_Pa:ARRAY[1..4] OF REAL`（段压差 0~2000 Pa）；`afDpEarly_Pa/afDpChange_Pa:ARRAY[1..4] OF REAL`（初堵/更换阈值 Pa）；`fHyst_Pa:REAL`（迟滞 0~100 Pa）；`fDpMax_Pa:REAL`（量程 Pa）；`fFanPct/fFanMinPct:REAL`（风机 0~100 %）；`tDebounce:TIME`（100 ms~120 s）。
- OUT：`aeStage:ARRAY[1..4] OF E_DL_FilterStage`；`auMaxStage:USINT`（0~3）；`bChangeReq:BOOL`；`bFrozen:BOOL`；`eErr:UDINT`。
- 关键改动：`aTonDeb:ARRAY[1..4] OF TON` 每周期无条件刷新；候选作废显式 `IN:=FALSE`。
- 验收：任一区间切换去抖期间另一区间不变慢；`tDebounce` 合法域外冻结置 03DA；向量覆盖「恰好等于阈值」「上阈+1 Pa」两点。

**序 2 FB_DL_FoupDoorSeq**
- IN：`bEnable`；`bDoorClosed/bDoorOpen`（门磁双反馈）；`bCarrierPresent`；`bUnlockCmd/bLockCmd`；`bVacuumOk`；`tUnlockHold/tRelockWin:TIME`。
- OUT：`bUnlockOut/bLockOut`；`eState:E_DL_FoupDoorState`（同文件枚举：eIdle/eUnlocking/eDoorOpen/eTransfer/eRelocking/eFault）；`bTransferPermit`；`eErr:UDINT`。
- 边界：解锁输出有效但门未开超时 → 故障（电磁铁/卡滞）；再锁定确认窗内门磁必须回到 closed，否则落 eFault；安全侧 = 输出全 0。
- 验收：故障锁存解除式可达（`bReset` 沿 + 门磁 closed）；ELSE 兜底落 eFault 并置码。

**序 3 FB_DL_CoolantFlowAudit**
- IN：`bEnable`；`afFlow_Lpm:ARRAY[1..8] OF REAL`（0~500 L/min）；`afMinFlow_Lpm`（欠流阈值）；`tConfirm:TIME`；`fHyst_Lpm:REAL`。
- OUT：`uwUnderMask:WORD`（欠流位掩码）；`uFirstOut:USINT`（0=无）；`bAllOk:BOOL`；`eErr:UDINT`。
- 边界：非有限/负流量 → 该支路判传感器故障独立于欠流；首出三律（未锁存才仲裁、同拍取最小支路号、复位在仲裁后）。
- 验收：阈值倒置置组态故障码；欠流确认窗内瞬时抖动不误报。

**序 4 FB_DL_ValvePdiSched**
- IN：`bEnable`；`auSlots:USINT`（并行槽 1~4）；`tPollCycle:TIME`；槽配置结构体数组注入；`abSlotEn:ARRAY[1..4] OF BOOL`。
- OUT：`eErr:UDINT`；`uActiveSlot:USINT`；`auErrSlot:ARRAY[1..4] OF UDINT`（各槽错误码回放）；`bAllSlotsOk:BOOL`。
- 边界：单拍单发（每槽一拍至多一次读）；槽号越界钳位；异常计数照记账不停摆。
- 验收：与库内 `FB_DL_PdiReadScheduler` 语义一致（调度与传输分层），本件只做多实例分槽编排，不重复实现传输。

**序 5 FB_DL_RackDiagSummary**
- IN：`auBoardStat:ARRAY[1..8] OF WORD`（诊断位引脚注入，零厂商系统变量）；`bReset`。
- OUT：`uwFaultMask:WORD`；`uFirstBoard:USINT`；`uFirstCode:UDINT`；`bStorm:BOOL`；`eErr:UDINT`。
- 边界：首出三律沿用 `FB_DL_PortDiagAggregator` 范式；回绕差分按归零处理；风暴单拍不进 bError。
- 验收：聚合与单件 `FB_DL_AxiolineDiagLatch` 契约字段一一对应；同名位语义不复定义。

**序 6 FB_DL_WaferScanRouter**（P0）
- IN：`bScanTrigger`；`sBarcode:STRING`；`bReadOk`；`uStationMod:USINT`（花篮位 1~25）；`abRouteEn`（分道允许表）；`tScanTimeout:TIME`。
- OUT：`uRouteSel:USINT`（选中分道 0=拒收）；`bRouteOk:BOOL`；`uSlotIdx:USINT`（取模索引）；`eErr:UDINT`。
- 边界：超时未读 → 拒收路径 + 故障码；`uStationMod=0` 组态非法；条码空串与读码失败语义分离。
- 验收：`uSlotIdx` 条件加减不用 MOD（跨平台负数歧义禁令）；R_TRIG 无条件刷新。

**序 7 FB_DL_SiloLevelInterlock**
- IN：`bHighLevel/bLowLevel`（双料位开关，FALSE=正常为失电安全侧需声明）；`bConvRun`（输送运行反馈）；`tJamWin:TIME`（卡料窗）；`bReset`。
- OUT：`bConvPermit`（输送允许）；`bOverflowTrip/bEmptyTrip`；`bJamDet`；`eErr:UDINT`。
- 边界：双信号同时有效 = 组态矛盾故障码；高料位 → 停进料（联锁）不停输送完成当前批次；低料位 → 停输送防空跑。
- 验收：联锁动作与告警码分离；`bConvPermit` 安全侧 FALSE；解除式可达（料位恢复 + bReset 沿）。

**序 8 FB_DL_PalletZoneMerge**
- IN：`bEnable`；`abZiOcc:ARRAY[1..4] OF BOOL`（区光电占用）；`bMergeReq`；`tZiGapMin:TIME`；`uMergeMode:USINT`（1=顺序 2=先到先走）。
- OUT：`abZiRelease:ARRAY[1..4] OF BOOL`；`bMergeBusy`；`uReleaseSeq:USINT`；`eErr:UDINT`。
- 边界：`uMergeMode` 非法值 → ELSE 兜底冻结 + 故障码；释放互斥（同拍至多一区）；上区补跑语义沿用 ConveyorZone。
- 验收：同拍多区请求取最小区号；光电闪断去抖不丢件。

**序 9 FB_DL_WeightClassifySort**
- IN：`bPartInZone`；`fWeight_g:REAL`（0~5000 g）；`afTh_LL/afTh_L/afTh_H/afTh_HH:ARRAY[1..4] OF REAL`（或四阈值标量 + 单通道）；`bRejectArm`。
- OUT：`eClass:E_DL_WeightClass`（同文件枚举 eLL/eL/eOK/eH/eHH）；`bRejectOut`；`uOkCount/uNgCount:UDINT`；`eErr:UDINT`。
- 边界：非有限重量 → NG 侧安全分流 + 传感器故障码（与超重 NG 区分）；阈值单调性组态闸。
- 验收：复用 `FC_DL_LimitClassify` 判档（不重写分级律），本件做「判档→剔除口→计数」编排；闭/开区间归属与 LimitClassify 勘误口径一致。

**序 10 FB_DL_EmoAndonFab**
- IN：`abEmo:ARRAY[1..6] OF BOOL`（EMO 急停按钮）；`iDoor1..iDoorN:I_DL_SafetyDoor 契约注入`（或 bDoorOpenMask:WORD）；`bAck/bReset`。
- OUT：`eAndonLevel:E_DL_AndonLevel`（复用库内属主不重造）；`bLampRed/bBuzzer`；`uFirstEmo:USINT`；`eErr:UDINT`。
- 边界：EMO 优先级高于安灯普通呼叫（同拍取高者）；未应答解除不计入应答统计（沿用 AndonCallSystem 语义）。
- 验收：本件为「联动编排」，仲裁律全部消费 `FB_DL_AndonCallSystem`，不重写四级仲裁；EMO 触发不唯一属主，首出定位到按钮号。

**序 11 FB_DL_FillWeightCheckweigher**
- IN：`bWeightValid`；`fWeight_g:REAL`；`fNominal_g:REAL`；`fTolPct:REAL`；`tStableWin:TIME`；`bRejectArm`。
- OUT：`eClass:E_DL_WeightClass`（属主=序 9 文件，引用注明）；`bRejectOut`；`uRejectCount:UDINT`；`eErr:UDINT`。
- 边界：动态称重稳定窗（tStableWin 内波动 < 门槛才判）；欠/超重两向四档；去皮错误（fWeight < 0）独立故障码。
- 验收：`fTolPct=0` 退化为判等（浮点禁 `=`，用 ±1E-6 g 容差声明）；剔除脉冲宽度可配置。

**序 12 FB_DL_FilmSpliceDetect**
- IN：`bEnable`；`iMarkLatch 引脚注入`（接口位置锁存，消费 `FB_DL_MarkPositionLatch`）；`bConvRun`；`fConvSpeed_mmin:REAL`；`tSlowWin:TIME`。
- OUT：`bSpliceApproach`（接近）；`bSlowPermit`（降速放行）；`uSpliceCount:UDINT`；`eErr:UDINT`。
- 边界：停机后位置锁存不触发放行（run-on 语义沿用 ConveyorZone）；两膜间距 < 最小膜长 → 组态故障。
- 验收：接膜计数只在降速窗完成放行时递增；速度非有限/负值闸。

**序 13 FB_DL_CoatingGapMeasure**
- IN：`afPixEdge1/afPixEdge2:REAL`（边缘像素坐标）；`fPixToMm:REAL`（mm/px，>0）；`afGapLo/afGapHi_mm:REAL`（留白带）；`fWinTolPct:REAL`；`uWinSize:USINT`。
- OUT：`fGap_mm:REAL`；`bGapOk:BOOL`；`bWindowConsist:BOOL`；`eErr:UDINT`。
- 边界：`fPixToMm<=0` 组态闸；窗口一致性消费 `FB_DL_SignalStatistics`（不重写统计）；边缘顺序颠倒（edge2<=edge1）判负 Gap → 传感器故障码。
- 验收：带判定消费 `FC_DL_IntervalMembership`；向量含「恰好落在带端点」两点（闭/开区间归属声明）。

**序 14 FB_DL_TrackerBacktrackCalc**
- IN：`fSunElev_deg/fSunAzi_deg:REAL`（来自 `FC_DL_SolarPositionCalc` 引脚注入）；`fRowPitch_m:REAL`（排间距 0.5~20 m）；`fCollectWidth_m:REAL`；`fMaxAngle_deg:REAL`（±60°）。
- OUT：`fTrackAngle_deg:REAL`；`bBacktrackActive:BOOL`；`fShadeLimit_deg:REAL`；`eErr:UDINT`。
- 边界：太阳高度角 < 0 → 归位停跟踪（安全侧 0°）；`fRowPitch_m<=0` 组态闸；输出限幅 ±fMaxAngle，限幅置信息码。
- 验收：逆跟踪角 = 阴影几何推导（arctan 归一化防除零），非有限太阳角输入保持上次有效角并置码；每拍全量重算。

**序 15 FB_DL_LamStepperFeed**
- IN：`iStepper:I_DL_StepperOpenLoop 引脚注入`；`fFilmLen_m:REAL`（单卷膜长）；`fFedLen_m:REAL`（累计送料，反馈注入）；`iMonthWin 引脚注入`（保养窗）；`tFeedTimeout:TIME`。
- OUT：`bFeedCmd`；`bFeedDone:BOOL`；`fRemainLen_m:REAL`；`bMaintHold:BOOL`；`eErr:UDINT`。
- 边界：保养窗激活 → 冻结送料（bMaintHold=TRUE，安全侧不启动）；膜长耗尽预警（< 换膜余量）信息码；步进堵转理论耗时 ×1.5 判据沿用库内 stepper 范式。
- 验收：本件为组合编排件，开环运动语义全部消费 `I_DL_StepperOpenLoop`，不自造轴状态枚举。

**序 16 FB_DL_ElectrodeRollDiameter**
- IN：`fLineSpd_mmin:REAL`；`fRollRpm:REAL`；`fPrevDia_mm:REAL`（上次卷径注入）；`fCoreDia_mm:REAL`（芯径）；`fThick_um:REAL`（层厚校核）；`fWarnDia_mm:REAL`（预警径）。
- OUT：`fDia_mm:REAL`；`bChangeWarn:BOOL`；`bAtCore:BOOL`；`eErr:UDINT`。
- 边界：低速保护（线速或转速低于门限冻结递推）；`fDia` 单调递减（放卷）违反 → 保持 + 信息码；卷径下限钳卷芯径。
- 验收：`D = v·i/(π·n)` 换算防除零；恰好等于预警径与预警径 −0.01 mm 两向量；与 `FC_DL_CoilDiameterCalc` 口径一致（本件加跟踪/预警层）。

**序 17 FB_DL_FanArraySeq**
- IN：`bEnable`；`uReqStages:USINT`（台数 0~N）；`abFanAvail:ARRAY[1..6] OF BOOL`；`abVfdEn:ARRAY[1..6] OF BOOL`（变频位）；`tMinRun:TIME`（防振颤）；`bRotateReq`。
- OUT：`abFanRun:ARRAY[1..6] OF BOOL`；`abFanVfdMode:ARRAY[1..6] OF BOOL`；`uRunCount:USINT`；`eErr:UDINT`。
- 边界：需求台数 > 可用台数 → 只投可用数 + 信息码；变频台优先投切、工频台补位（一台同拍至多一种模式）；轮值消费 `FB_DL_DutyStandbyRotation` 范式、分级投切消费 `FB_DL_FanArrayStageCtrl`。
- 验收：台数 0 → 全停（安全侧）；最短运行时间内不轮值；`uReqStages` 越界钳位 + 码。

**序 18 FB_DL_ChwDifferentialPressure**
- IN：`bEnable`；`fDp_kPa:REAL`（供回水压差 0~400 kPa）；`fDpSet_kPa:REAL`；`iPid 引脚注入`（`FB_DL_PidController` 实例输出）；`fValveMin/fValveMax_Pct:REAL`；`fResetRate_kPa_s:REAL`（设定值重置限速）。
- OUT：`fValveOut_Pct:REAL`（旁通阀位）；`fDpSmooth_kPa:REAL`；`bByPassActive:BOOL`；`eErr:UDINT`。
- 边界：压差平滑消费 `FB_DL_MovingAverage`；设定值重置限速消费 `FB_DL_RateLimiter`（斜坡防水锤）；阀位限幅 + 限幅饱和信息码。
- 验收：非有限压差 → 阀位保持 + 故障码（安全侧不新增动作）；PID 输出引脚注入不内联（可依赖低层不复制低层）。

**序 19 FC_DL_ChecksumSum64**
- 签名：`FC_DL_ChecksumSum64(aData:LWORD array IN, uCount:USINT) : LWORD` + `uErrorId:UDINT`（VAR_OUTPUT 或引用 `FC_DL_ChecksumSum8` 现行错误出口约定——编码前先读该件头注释对齐）。
- 语义：模 2^64 累加和（LWORD 自然回绕，禁用 MOD）；`uCount=0` 返回 0 + 信息码；数组越界守护计数强制退出。
- 边界：`aData` 中间量无浮点（全整型域，无非有限问题）；与 `FC_DL_ChecksumSum8` 构成 8/64 位宽两件，拒绝更多位宽变体。
- 验收：空数组、单元素、回绕触发（0xFFFF..F + 0x1）三点向量；矩阵台账「校验族尚余 LWORD 累加和待挖」收口。

**序 20 FC_DL_BitArraySegCopy**
- 签名：源/目标 DWORD 数组 IN_OUT + 段表（`aSrcBit:UINT/aDstBit:UINT/nLen:USINT` ×N 段）+ `uSegCount:USINT` + `uErrorId:UDINT`。
- 语义：一次调用搬 N 段（批量「多段一次搬」）；逐段域校验（起位 + 长度 ≤ 数组位容量）先整体校验后统一搬移（整段原子性：任一段非法则零段搬移 + 段号报错）。
- 边界：跨字窗口读改写沿用 R12 Extract/Insert 范式（移位量 `MOD 32`、宽 64 走常量掩码、全程无 64 位移位）；`uSegCount=0` 信息码返回。
- 验收：与 `FC_DL_BitArrayExtract/Insert` 逐段对拍位守恒；重叠段（源内两段同域）本件不做去重、显式声明「后段覆盖前段」行为；矩阵台账「DWORD/LWORD 数组批量位段族——多段一次搬」收口。

---

## 4. 四批分配

| 批次 | offset/limit | 序号 | 子库构成 |
|---|---|---|---|
| 批 1 | 1..5 | 1~5 | Device：返修件 + 4 新件（Device 收口日） |
| 批 2 | 6..10 | 6~10 | Process：P0 先行 + 4 件 P1 |
| 批 3 | 11..15 | 11~15 | Process 3 + Motion 2 |
| 批 4 | 16..20 | 16~20 | Motion 1 + Algo 2 + MathData 1 + Base 1 |

---

## 5. 码位实测表（R61/R105：python 全库扫描实测，非记忆值）

**方法**：`16#000[1-5]_XXXX` 正则扫描 `C:/Library/DL_*/*.st` 全部 519 件；剔除注释内非错误码样例（`16#0002_8011` 为 PDI 打包示例，非 eErr 码，已剔除）。段-目录实测对齐：0001=DL_Base+DL_MathData（共享段）、0002=DL_Algo、0003=DL_Device、0004=DL_Motion、0005=DL_Process。

| 段号 | 子库 | 在册实测最大码 | 本轮游标（下一空位） | 本轮分配块 |
|---|---|---|---|---|
| 0001 | Base+MathData | 0489（MathData 侧） | **048A** | 序 19 ChecksumSum64：048A~048D（FC 4 槽）；序 20 BitArraySegCopy：048E~0491（FC 4 槽） |
| 0002 | Algo | 3728 | **3729** | 序 17 FanArraySeq：3729~372D；序 18 ChwDifferentialPressure：372E~3732 |
| 0003 | Device | 03D8 | **03D9** | 序 1：03D9~03DD；序 2：03DE~03E2；序 3：03E3~03E7；序 4：03E8~03EC；序 5：03ED~03F1 |
| 0004 | Motion | 0353 | **0354** | 序 14：0354~0358；序 15：0359~035D；序 16：035E~0362 |
| 0005 | Process | 0466 | **0467** | 序 6：0467~046B；序 7：046C~0470；序 8：0471~0475；序 9：0476~047A；序 10：047B~047F；序 11：0480~0484；序 12：0485~0489；序 13：048A~048E |

**交接参考复核结论**：给定参考（0001 信息 046F/故障 03BD、0003 信息 0190/故障 0369、0004 信息 01EB/故障 030C、0005 信息 01FD）**全部已过时**——R29 收口后实测游标前移。以本表实测为准。

**槽位纪律**：FB_ 件 5 槽块（首槽信息级、次槽起故障级、余槽子工况）；FC_ 件 4 槽（R25 增补 P0 分型裁定：纯函数 4 槽合法）。Process 段信息级码**沿用既有 04xx 惯例**（实测 Process 码已全部位于 04xx，无需迁移动作，按惯例续排）。返修件原 03C5~03C9 作废不回收。I_ 接口件本轮无，不占码位。

---

## 6. 查重声明（R148/R157/R160：registry 全量 name + 文件树 ls 双查）

### 6.1 20 件查重结果

| 组件名 | registry grep | 文件树 ls | 结论 |
|---|---|---|---|
| FB_DL_AhuFilterDpBank | NONE（R29 隔离件从未注册） | NONE（仅存于 _Staging_Raw/REJECTED_R29，非正式目录） | 通过 |
| FB_DL_FoupDoorSeq | NONE | NONE | 通过 |
| FB_DL_CoolantFlowAudit | NONE | NONE | 通过 |
| FB_DL_ValvePdiSched | NONE | NONE | 通过 |
| FB_DL_RackDiagSummary | NONE | NONE | 通过 |
| FB_DL_WaferScanRouter | NONE | NONE | 通过 |
| FB_DL_SiloLevelInterlock | NONE | NONE | 通过 |
| FB_DL_PalletZoneMerge | NONE | NONE | 通过 |
| FB_DL_WeightClassifySort | NONE | NONE | 通过 |
| FB_DL_EmoAndonFab | NONE | NONE | 通过 |
| FB_DL_FillWeightCheckweigher | NONE | NONE | 通过 |
| FB_DL_FilmSpliceDetect | NONE | NONE | 通过 |
| FB_DL_CoatingGapMeasure | NONE | NONE | 通过 |
| FB_DL_TrackerBacktrackCalc | NONE | NONE | 通过 |
| FB_DL_LamStepperFeed | NONE | NONE | 通过 |
| FB_DL_ElectrodeRollDiameter | NONE | NONE | 通过 |
| FB_DL_FanArraySeq | NONE | NONE | 通过（邻件 FB_DL_FanArrayStageCtrl 已注册，名称不同族不撞，为消费关系） |
| FB_DL_ChwDifferentialPressure | NONE | NONE | 通过（见 6.3 同义裁定） |
| FC_DL_ChecksumSum64 | NONE | NONE | 通过（邻件 FC_DL_ChecksumSum8 位宽不同不撞） |
| FC_DL_BitArraySegCopy | NONE | NONE | 通过（邻件 Extract/Insert/ChangeWatch/Rotate 名称不撞） |

**20/20 全部 NONE，零改名。**

### 6.2 ROADMAP 勾选框滞后披露（本轮实测，150 条移交收口轮）

代表性样例（本轮选题实测命中，全量以脚本复核为准）：`FB_DL_ChamberGateValve`、`FB_DL_PumpDryRunGuard`、`FB_DL_LamDoorInterlock`、`FB_DL_TrackBarcodeTrace`、`FB_DL_RotaryIndexModulo`、`FB_DL_PowderDosingLoss`、`FB_DL_WindingAlignEdge`、`FB_DL_SolderRibbonTension`、`FB_DL_LoopWaveInject`、`FC_DL_OrificeFlowCalc`、`FC_DL_WaferCountYield`、`FC_DL_AirDensityFanPower` 等——均已注册+落盘但未勾选。**本轮选题一律绕开**（占用即改判），滞后勾选回写列入收口待办。

### 6.3 同义邻件裁定（选题双查第二查）

1. **FB_DL_ChwDifferentialPressure（本轮立项）vs FB_DL_ChwDifferentialPressureReset（ROADMAP L837 未勾选且空位）**：两条目同义（冷冻水差压旁通/压差重置）。裁定：本轮按 R25 增补线（L1053）名称立项；L837 条目**并入本件规格**（设定值重置限速已纳入引脚），收口轮在 ROADMAP 对 L837 注记「已由 R30 序 18 并案，不另立」。
2. **FB_DL_WaferScanRouter（本轮立项）vs FB_DL_CartonScannerSort（L492 空位）vs 已注册 FB_DL_TrackBarcodeTrace**：同为扫码路由族。裁定：本轮只立 P0 的 WaferScanRouter；CartonScannerSort 与已注册 TrackBarcodeTrace 语义高度重叠（扫码+分道），按「宁少勿滥」延后不立，收口轮注记。
3. **FB_DL_TrackerBacktrackCalc vs 已注册 FC_DL_SolarPositionCalc**：太阳位置是天文计算（MathData），逆跟踪角是阵列阴影几何（Motion 工艺层），语义分层不重叠，后者消费前者输出。通过。
4. **FB_DL_ElectrodeRollDiameter vs 已注册 FC_DL_CoilDiameterCalc**：卷径公式算一个值（Algo FC）vs 直径跟踪+预警（Motion FB 编排层）。沿用 R10 已声明的职责切分（「层厚递推与排线执行归 WindingTraverse」），本件只加跟踪/预警，不重写公式。通过。
5. **FC_DL_ChecksumSum64 vs FC_DL_Crc16Modbus/Crc16Ccitt/Crc16Generic**：累加和与 CRC 是两类校验算法，不撞；反射型 CRC-16 判为已被 Generic 参数化覆盖，不立（防变体）。

### 6.4 配比偏离说明

建议配比 Device4/Process5/Motion3/Algo3/MathData2/Base2，实际 **Device5/Process8/Motion3/Algo2/MathData1/Base1**。理由：(a) Algo 空位池中 P1 仅 R25 补位 2 件（全取），其余 P2 件均与存量同义或依赖未立项前置（如 FanArrayStageCtrl〔前置件〕类）——不凑数；(b) Base 空位仅 ShlDwordEx/ShrDwordEx（自挂「疑似与存量同义、立项前必过 R61」条款，实测 ShlEx/ShrEx 通用命名件已存在，判不立）——Base 改取矩阵台账「多段一次搬」待挖子项 1 件；(c) MathData 空位中 OrificeFlowCalc/WaferCountYield 实测已被占用（勾选框滞后），仅剩矩阵台账「LWORD 累加和」1 件；(d) 缺额由 Process/Device 真实 P0/P1 空位补足，全部为 ROADMAP 明文待办。

---

## 7. 编码派单样板（R50，编码轮逐件套用）

### 7.1 文件头注释样板

```iecst
// =====================================================================
// <POU 名>.st
// <中文一句话功能> / <English one-line function>
// 所属子库: DL_<Category>    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#<段>_<起> ~ 16#<段>_<止> (本件独占 <n> 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现（T1/T2 件用此句；IEC 标准语义件改用「IEC 61131-3 标准语义的道莅防御性实现」）
//       来源组标签: <lgf-*/oscat-*/packml/isa-88/industry-pool/源矩阵行号>
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 <n>)
// =====================================================================
```

注：头注释**严禁出现全局变量区、外部变量声明、物理输入/输出地址记号的字面原文**（含对应英文缩写），一律用「外部数据经引脚注入」「信号经输入/输出映像区引脚接入」等语义描述。

### 7.2 双语注释行样板

- 每个变量声明行 `// 中文说明（含物理意义与工程单位）/ English comment`，单位必须出现（ms/s/mm/kPa/%/g/L/min 等）。
- 枚举成员逐项同行注释，枚举与状态机 `CASE` 标签集合一致（R25 增补「枚举成员 ⊆ CASE 标签」机检规则生效中）。

### 7.3 错误码声明样板（5 槽块，FC 件 4 槽）

```iecst
VAR_OUTPUT
    eErr           : UDINT;            // 错误码 16#<段>_<XX>~<XX>（本件独占块首槽信息级，次槽起故障级） / Error code
END_VAR
// 代码位表（本件独占，勿复用）:
//   16#<段>_<+0> 信息 <正常/完成语义>
//   16#<段>_<+1> 故障 <首要故障语义>（锁存解除式 = <可达解除条件>）
//   16#<段>_<+2> 故障 <次要故障语义>
//   16#<段>_<+3> 信息/故障 <子工况>
//   16#<段>_<+4> 故障 <兜底/非法态>
```

### 7.4 编码硬提醒（编码轮开工前逐件确认）

1. **VAR_OUTPUT 必须显式声明**——所有对外输出（含 `eErr`、状态、诊断出口）一律出现在 `VAR_OUTPUT` 区，禁止用内部变量间接暴露。
2. TON/TOF/R_TRIG 在主周期**无条件刷新**；数组定时器逐实例刷新（返修件为 R40 家族核对件）。
3. 状态机 ENUM + CASE + ELSE 安全兜底；浮点判等用 `ABS(a-b) < 1E-6`；防除零、数组边界、WHILE 守卫计数器三件套齐全。
4. 锁存位解除式终审自证可达（R28 式 1）；整数进位点取「恰好整除」「上限+1」两向量（R28 式 2）。
5. 依赖库内低层件一律引脚/接口注入消费，不内联复制低层能力；跨层依赖方向只允许高层→低层。
6. 每件完成后按批回写五件套文档 + registry（name/category/type/file_path/function_tags/complexity 与 §2 表一致）。
