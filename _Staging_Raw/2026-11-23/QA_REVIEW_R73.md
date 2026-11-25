# QA_REVIEW_R73 ｜ 审校与去重官 ｜ 2026-11-23

## 一、总表（20 件）

| # | 件名 | 结论 | 缺陷(严/中/轻) | 去重判定 |
|---|---|---|---|---|
| 1 | FB_DL_FlyingSawSyncSeq | **REJECT** | 1/0/1 | 名称/指纹/语义三道均未命中，通过 |
| 2 | FB_DL_CamTableOnlineBlend | **REJECT** | 1/0/1 | 通过（与 CamDynTrim/CamTableLiveTrim 分工已互引） |
| 3 | FB_DL_FanSurgeMarginCalc | PASS | 0/0/0 | 通过（与 CompressorSurgeGuard 件不同：开环监视 vs 闭环放空阀，设备域不同） |
| 4 | FB_DL_EmergencyStopChainDiag | PASS-with-note | 0/0/1 | 通过（与 EStopMonitor/EStopDualChannel 不同：四节点断链定位是新域） |
| 5 | FB_DL_TankFarmTransferSeq | **REJECT** | 1/0/0 | **存疑放行**：与 FB_DL_BatchTransferSeq 结构高度同型（开阀→泵→停→关），以"液位双目标终止+稳压相"为新增价值放行，补分工互引，交总监复议 |
| 6 | FB_DL_ConveyorAccumGateSeq | PASS | 0/0/0 | 通过 |
| 7 | FC_DL_MovingRangeCalc | PASS | 0/0/0 | 通过 |
| 8 | FC_DL_PressureAltitudeCalc | PASS-with-note | 0/0/1 | 通过 |
| 9 | FC_DL_SoundSpeedAirCalc | PASS | 0/0/0 | 通过（属主 VaporPressureSat 回执收全） |
| 10 | FC_DL_ExpMovingAvgCalc | PASS-with-note | 0/0/0 | **存疑放行**：与 FB_DL_EwmaFilter 同公式，凭"无状态可重入原子"新价值放行；头注释未与 EwmaFilter 互引，须补 |
| 11 | FC_DL_TorqueUnitConvert | PASS | 0/0/0 | 通过（参考 MS_TO_KMH 仅行为分类，域不同） |
| 12 | FC_DL_BitRotateEx | PASS | 0/0/0 | 通过（与 ShlEx/ShrEx、BitArrayRotate 域均不同，分工已声明） |
| 13 | FB_DL_SignalRouteMatrix | PASS-with-note | 0/0/1 | 通过 |
| 14 | FB_DL_SignalEdgeDelayEx | PASS-with-note | 0/0/1 | 通过（参考 FT_IMP 仅分类，双沿延迟语义不同） |
| 15 | FB_DL_SensorSupplyWatch | PASS-with-note | 0/0/1 | **存疑放行**：与既有 FB_DL_SensorSupplyMon 同族同输入形态（供电电压→bSupplyOk），新增 NE43 四态/过压侧/去抖为放行依据；头注释未互引，交总监复议 |
| 16 | FB_DL_ValveCycleCountBank | PASS-with-note | 0/0/1 | **存疑放行**：与 FB_DL_ValveCycleLifeCounter 同族，凭"无反馈阀指令沿计数 + 4 通道 Bank"放行；须补互引 |
| 17 | FC_DL_TcToFilterCoeff | PASS | 0/0/0 | 通过 |
| 18 | FC_DL_DeadtimeTapCalc | PASS-with-note | 0/0/1 | 通过 |
| 19 | FB_DL_HandAutoModeGateBank | PASS-with-note | 0/0/1 | 通过（MANUAL/CONTROL_MODE 仅分类参考，双钥匙+审计为新价值） |
| 20 | FB_DL_OperatorAckBank | PASS | 0/0/0 | 通过 |

统计：PASS 8 ｜ PASS-with-note 9 ｜ REJECT 3 ｜ 严重(BLOCK) 0 ｜ MAJOR 3 ｜ MINOR 9

## 二、缺陷明细（MAJOR）

1. **FlyingSawSyncSeq L117/L125/L130 ｜MAJOR｜同步切入爬坡段逻辑不可达**：锚点在启动沿锁存为当前主轴位置（L117 `fAnchor := fMasterPos`），而切入窗为 [fAnchor−fSyncLen, fAnchor]（L125、L130），整段位于触发点**之前**的已走过行程。正常触发后 eWait 下拍即满足 L125 转入 eSyncIn，进度比 = 1+(pos−anchor)/syncLen ≥ 1 被 L131 钳到 1，速比 0→1 爬坡从不发生，bCutReq 启动后 1~2 拍即置位——与头注释 L6"锚点前方 fSyncLen 区间线性爬升"矛盾。建议：锚点改为触发点前推（fAnchor := fMasterPos + fSyncLen + fCutLen）或 eWait 等待主轴到达 anchor−fSyncLen 的未来位置。
2. **CamTableOnlineBlend L107 ｜MAJOR｜非有限值穿透输出**：位置源非有限分支仍执行 `fPosOut := fW*fPosB + (1-fW)*fPosA`，fPosA/fPosB 为 NaN/Inf 时 fPosOut 直接变 NaN/Inf，与 L107 注释"冻结口径仍为最后有效权重合成"矛盾。建议：该分支不赋值 fPosOut（保持上拍值）。
3. **TankFarmTransferSeq L171-179 ｜MAJOR｜关阀相无超时监控（静默挂死）**：eCloseValves 仅凭阀反馈消失推进（L176），阀反馈卡死恒 TRUE 时序列无限滞留：无故障码、不置 bError、bCycleDone 永不来；tValveFb 超时闸（L97）只覆盖开阀相。与历史 RailPowerSequence 静默挂死同型（扫查项⑧推进/超时不同源）。建议：关阀相增加关反馈超时闸入 eFault。

## 三、缺陷明细（MINOR，挂账下轮）

4. FlyingSawSyncSeq L91-107 vs 头注释 L21-22：早退分支未把 fRatio 冻结 0（保持上拍脏值，仅 bValid=FALSE 缓解），与注释"速比冻结 0"不符。
5. CamTableOnlineBlend L115 vs 头注释 L22：tBlend<=0 拒绝触发路径未置信息码（注释称"拒绝触发 + 信息码"，实际 uErrCode=0）。
6. EmergencyStopChainDiag L96/L136/L152：bSeqBad 两处置位但无私有消费、无输出口——死变量，复位时序非法信息上层不可见。
7. PressureAltitudeCalc L59：DL_PA_PMAX=108900 注释称"-500 m ISA 标准值"，ISA -500 m 实际 ≈107,477 Pa；反解上端可达 ≈-774 m，与正解域下限 -500 m 往返不对称。
8. SignalRouteMatrix L16-17 vs L79-80：头注释称非法选择兜底"+ 声明哨兵"，ELSE 分支只置输出 FALSE 未置哨兵。
9. SensorSupplyWatch L131-137 vs L102-108：eInvalid 恢复用未去抖的 bInUnder/bInOver 直接落 eUnderRange/eOverRange 态，绕过 tDebounce 确认，态标签先于确认输出翻转。
10. DeadtimeTapCalc L41/L81：进位容差 1e-6 有方向性风险——真整数商因浮点略小于整数（余量~1e-15<容差）时少进一位；建议先就近取整判等再判余量。
11. HandAutoModeGateBank L28 vs L85-88：头注释"R_TRIG ×8"实为 4 实例；L106/L140 等双回路信息码共用单寄存器同拍互相覆盖；初始默认 eAuto（枚举 0）未声明，与"兜底归 eManual 安全侧"口径不一致。
12. ValveCycleCountBank L30-33/L84-95：头注释"指令上升沿 = 一次全行程动作"语义夸大——指令被上层联锁拒绝/阀拒动时同样计数，与既有 ValveCycleLifeCounter"双源同证"口径不一致；另头注释 L16 "R_TRIG ×8"实为 9 实例。
13. ExpMovingAvgCalc 头注释：与最近邻 FB_DL_EwmaFilter（同公式）未做分工互引，仅引 LowPassFilter/TcToFilterCoeff。

## 四、去重结论

- **名称道**：20 件规范化后对 registry 1218 名精确 + 子串模糊比对，**0 命中**。
- **指纹道**：_dedup_fingerprints.json 33 条为候选队列来源名（MS_TO_KMH/WINDOW2/MANUAL/FT_IMP 等），新件 DL_ 名均不在其中，**0 结构指纹碰撞**。
- **语义道**：**0 判重拒绝**；4 件存疑放行（#5 TankFarmTransferSeq↔BatchTransferSeq、#10 ExpMovingAvgCalc↔EwmaFilter、#15 SensorSupplyWatch↔SensorSupplyMon、#16 ValveCycleCountBank↔ValveCycleLifeCounter），均为"同族+新工程价值"判定，放行条件=补齐与既有件的分工互引注释；其中 #5、#15 同型度最高，请总监复议是否合并或强声明分工。
- 3 件 REJECT 均为语义缺陷非重复件，修复后可按同序号重审。

## 五、就地修记录

无（本轮 3 项 MAJOR 均涉行为变更，不满足 R333 零变更例外；只报不改，交主控裁决）。

## 六、存疑放行清单（供总监复议）

| 件 | 疑似重复对象 | 放行依据 | 复议要点 |
|---|---|---|---|
| TankFarmTransferSeq | FB_DL_BatchTransferSeq | 液位双目标终止+稳压相 vs 计量体积+排空验证 | 序列骨架同构，是否合并为参数化件 |
| ExpMovingAvgCalc | FB_DL_EwmaFilter | 无状态可重入原子 vs 状态驻留 FB | 补互引后可入库 |
| SensorSupplyWatch | FB_DL_SensorSupplyMon | NE43 四态+过压+去抖 vs 8通道窗均值+迟滞 | 单通道件是否值得独立存在 |
| ValveCycleCountBank | FB_DL_ValveCycleLifeCounter | 无反馈阀指令沿计数+4通道 | 口径差异须在头注释写死 |
