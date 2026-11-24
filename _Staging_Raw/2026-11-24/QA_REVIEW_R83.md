# QA_REVIEW_R83 — 审校去重席独立裁决

**轮次** R83 ｜ **对象** 40 件新件（36 FC + 4 FB，全库 L1/L2 已过）｜ **日期** 2026-11-24
**口径** 全量 40/40 逐件 12 项扫查（非抽样）+ 三道去重全量 ｜ **复核方法** 逐行读源码 1,586 行 + 代数回代 + 与 1,570 件 registry / 1,530 条指纹比对
**结论** PASS 32 ｜ 存疑放行 7（含 MAJOR 挂账 4 件）｜ **拒收 1（BLOCK）** ｜ 去重拒收 0 ｜ MAJOR 5 条 ／ MINOR 24 条

---

## §1 逐件结论表

> 检查项列只列**未过项编号**（12 项见岗位定义）；`—` = 12 项全过。

| # | 组件名 | 检查项结论 | 缺陷清单（行号 + 分级） | 终判 |
|---|---|---|---|---|
| 1 | FC_DL_InkViscosityTempComp | 4 | L30 `fTempCoeff` 符号约定未声明：k 取正时 `fScale` 与物理方向相反（黏度随温升而降），MINOR | 存疑① |
| 2 | FC_DL_RegisterErrorCalc | 10 | L12/L27 `fSpeedMpm` **零引用**：只入非有限闸、不参与任何算式，非法值可把正确结果打成哨兵 −1，MINOR | PASS |
| 3 | FC_DL_AniloxInkTransferCalc | 4 | L26 缺 `fSpeedMpm ≤ 0` 域闸 → 负速得负耗墨且 `xValid=TRUE`，MINOR | PASS |
| 4 | FC_DL_SpliceOverlapWidthCalc | 10 | L32 就地改写 `VAR_INPUT fOverlapPct`（库内 10/36 件同病），MINOR | PASS |
| 5 | FC_DL_CutLengthDeviationCalc | — | 补偿符号 L46 `-fDevMm*fGainK` 方向正确；死区/增益域闸齐 | PASS |
| 6 | FC_DL_DryerSolventLoadCalc | 10 | L30/L32 改写输入 `fSolventPct`；负排风量已由 L44 `>0` 拦在安全侧 | PASS |
| 7 | FB_DL_SpliceCountdownCtrl | 7 | L29 注释称「bReset 上升沿」实为电平清除（`R_TRIG` 未用）；L27 故障拍 `fRemainM=0` 表示「无料」与工况相反，MINOR | 存疑② |
| 8 | FC_DL_ImpulseSealDwellCalc | — | 量纲链 L34（mm²·µm·1E−6=density 前 cm³）复算正确；ΔT 方向闸 L30 齐 | PASS |
| 9 | FC_DL_DyeLiquorRatioCalc | 4/10 | L29-33 改写输入；L44 只判 |流量|>1E−9，负流量 → 负补加时间，MINOR | PASS |
| 10 | FC_DL_FabricWeightAreaCalc | 4 | L42 `fGsm*100/(100+M)` 得**烘干克重**，注释写「公定回潮折算」，口径不符，MINOR | PASS |
| 11 | FC_DL_PaddingPickupCalc | — | 湿干重次序闸 L27、带液量密度 1 kg/L 已声明 | PASS |
| 12 | FC_DL_StenterHeatSetCalc | 4 | L46 净超喂 = MD 超喂 − CD 伸长，**轴向混用**（量纲同为 % 但物理轴不同），MINOR | PASS |
| 13 | FC_DL_YarnCountConvert | 10 | L12/L24 `fDensity` 零引用：Ne↔Tex 换算与密度无关，却可因密度越界返 −1，MINOR | PASS |
| 14 | FC_DL_BeamWarpLengthCalc | 6 | L35 注释「向下取整（R28）」但用 `REAL_TO_INT`（IEC 为四舍五入）→ 层数可多 1 → 长度高估，MINOR | PASS |
| 15 | FB_DL_DyeBathReplenishCtrl | 11 | L44 助剂仅在「同时缺水」时加注：液位足而浓度低 → 永不补加（漏补），MINOR | PASS |
| 16 | FC_DL_ShadeDriftIndexCalc | — | 权重域闸 L27、开方/容限双闸齐 | PASS |
| 17 | FC_DL_PlatingThicknessChargeCalc | — | L42 `100×m/ρ`（g/dm²→µm）复算正确 | PASS |
| 18 | FC_DL_FaradayEfficiencyCalc | — | 双路径独立（L32 不触天平值）、效率上界 120% 口径合理 | PASS |
| 19 | FC_DL_AnodeCurrentDensityCalc | 4/10 | L32 `W×H×n` 为**单面**面积，双面阳极漏 ×2 → 电流密度高估 2 倍（未声明单/双面）；L29 改写输入，MINOR | 存疑③ |
| 20 | FC_DL_RinseDragOutCalc | — | L33 物料平衡 `Qd(Cd/Ct−1)` 正确，浓度次序闸 L27 齐 | PASS |
| 21 | FC_DL_BarrelRotationRpmCalc | 1/6 | **MAJOR**：L25 闸只判 `d<D`，未判 `d<D/2`；L33 落 ELSE → `fCritRpm=0`，L45 无条件 `xValid:=TRUE` → 静默出 0 且标有效（漏报）。MINOR：L29 钳位 `fFillPct` 后全文零引用 | 存疑④ |
| 22 | FB_DL_ElectrolessBathReplenishCtrl | 5 | L41→L44 补加相无回差：浓度在设定值附近每拍 Idle↔Dose 抖动（泵频启停），MINOR | PASS |
| 23 | FC_DL_HexChromeTriRatioCalc | 10 | L12/L26 `fTempC` 零引用（温度只入闸不进算式），MINOR | PASS |
| 24 | FC_DL_SortChuteTimingCalc | — | L31 三项加减方向正确（+扫描延时 −半长），负延时钳零并置不可分拣 | PASS |
| 25 | FC_DL_BeltThroughputCalc | 10 | L34 改写输入；`len≤pitch` 次序闸 L28 齐 | PASS |
| 26 | FC_DL_DiverterLeadTimeCalc | — | L30/L34 提前量→延时方向正确，三出口分支覆盖 | PASS |
| 27 | FC_DL_ScannerReadRateCalc | 4 | **MAJOR**：输入声明 `diTotal`「读码总次数（含重读）」，L30 FSR 用它作分母、L32/L35 `diFail=总次数−首读成功` 当**件数**用 → 100 件 10 件重读时 FSR 81.8%（真值 90%）、平均重读 0.5 次/件（真值 1.0）；L26 无 `diTotal=firstOk+retry` 一致性闸 | 存疑⑤ |
| 28 | FC_DL_ChuteFullPredict | 10 | L29-33 改写输入；净流≤0 分支安全侧正确 | PASS |
| 29 | **FB_DL_ToteGapReleaseCtrl** | 5/8/3 | **BLOCK**：L28 `fGapNeedM=箱长+净距`（中心距口径）与 L37 `fGapActM≥fGapNeedM`（净距实测）**口径混用**，而 L44 退出判据又用净距 `fGapActM<fMinGapM` —— 入口/出口对同一引脚两种口径，必有一错。正常输送工况（净距 < 箱长）下入口**永不满足** → L31 `tonHold` 10 s 到期 → 误报 9302「下游阻塞」停线。另 MINOR：L28 预置由裸输入算出，NaN 入参时 `fGapNeedM/fGapMarginM` 以 NaN 出口（未预置零） | **拒收** |
| 30 | FC_DL_AccumulationZoneFillCalc | 6 | **MAJOR**：L33 `iCapCnt:=REAL_TO_INT(区长/节距)` 注释称「向下取整（R28）」，IEC 语义为四舍五入 → 容量高估 1 件 → 占位率低估 → L46 `xFull` **满料漏报**（安全侧反向）；库内 `FC_DL_FloorEx`/`FC_DL_IntFloorDiv` 即为此事而设，未用 | 存疑⑥ |
| 31 | FC_DL_SlotHeightFitCalc | — | L34 三项相减方向正确；余量≥安全余量判据 L44 齐 | PASS |
| 32 | FC_DL_PalletOverhangCalc | 10 | L32 改写输入；两向取严者 L42-46 正确 | PASS |
| 33 | FC_DL_ForkEntryClearanceCalc | — | L39/L40 偏右时左余量变小，符号方向正确 | PASS |
| 34 | FC_DL_AsrsCycleTimeCalc | — | L35 `d/v+v/a`、L37 `2√(d/a)` 两式复算正确，双轴取大 L43 | PASS |
| 35 | FC_DL_StackerMastSwayCalc | 4 | L40 用 `4/(ζω)`（对应衰减到 **2%**），注释与引脚语义写「衰减到 **5%**」（应为 `3/(ζω)`），MINOR | PASS |
| 36 | FC_DL_InventoryAgeIndexCalc | — | 权重域闸 L27、分档严格不等 | PASS |
| 37 | FB_DL_PrintRegisterAutoTrimSeq | 7 | L230-232「失能迁空闲」被 L238 段尾闸同拍覆盖 → **不可达迁移**（注释与实现不符），MINOR。TON 三实例均单相 `IN`（L115-117），否定「跨相 OR」 | PASS |
| 38 | FB_DL_DyeBatchRecipeSeq | 7/11 | L230-231 同上不可达；L241 加料阀被 `bHeatBlocked`（含 `NOT bHeatEnable`）一并切断 → 加热许可失效会连带停加料并拖出 206 超时，MINOR。**GATE §2.3 的 E037 改写已落地**（L122-124 已换字面界 0..3），本席复跑 `l2_check` → PASS=1，豁免记账可销 | PASS |
| 39 | FB_DL_PlatingLineTransferSeq | 5/8 | **MAJOR-1**：L143 入口要求 `bStart AND _bBeat`，但 L153 槽位等待相放行只判 `_bSlotEdge OR bSlotFree` → 等待最长 120 s 后**脱拍起吊**，错峰互斥失效（且不再复核 `bStart`）。**MAJOR-2**：L162/L171/L180 直接以反馈**电平**推进，无「命令发出后反馈须先假后真」校验 → 限位粘连常真即跳段（未升起就横移，撞槽风险） | 存疑⑦ |
| 40 | FB_DL_SortDiverterSeq | 7 | L126 `(eDone AND NOT _bHs)` 结构恒假（eDone 必经 L164 置 `_bHs`），属自述防御行；复位解除路径 L115-119 可达，不计缺陷，MINOR | PASS |

---

## §2 三道去重结果（全量 40 件）

**道 1 名称**：40 个规范化名（去 `FB_/FC_/DL_` 前缀）与 registry **1,570** 名逐一比对，**精确命中 0、规范化命中 0**；四字词根交集扫描亦无 ≥2 词根同中同一存量件。判：**无命中**。

**道 2 签名指纹**：以 `_tools/r82_fp_rebuild.py:analyze()` 同一算法重算 40 件 sig/api，与 `_dedup_fingerprints.json`（count=1530，与 registry 1:1，覆盖 100%，R82 重建后未降级）比对 → **sig 命中 9 条，全部判假阳性**。

| 新件 | 命中存量件 | 判定 | 理由 |
|---|---|---|---|
| InkViscosityTempComp / AniloxInkTransferCalc / DryerSolventLoadCalc / ImpulseSealDwellCalc | FC_DL_PneuLeakRateCalc | 假阳性 | 命中键为 `REAL×5 入 / 3 出` 的类型序列；两件域（气动泄漏 vs 印刷油墨）无交集 |
| PaddingPickupCalc / StenterHeatSetCalc / PlatingThicknessChargeCalc / FaradayEfficiencyCalc / StackerMastSwayCalc | FC_DL_SludgeAgeCalc | 假阳性 | 同上（`REAL×5 / 4` 全 REAL 序列） |

> 根因举证：`r82_fp_rebuild.py:64` 的 sig 仅由 `kind + 类型序列` 组成，**对同型签名零区分力**；库内已备 `in_n/out_n/sm` 三字段却未参与分组 → 建议道 2 分组键改为 `sig+in_n+out_n+sm`（or 直接 `sig×sm`），交编译验证席落地。**本轮不因此判重**。

**道 3 语义同义**（全量登记，最近邻正文逐对读）：

| 新件 | 最近邻 | 判定 |
|---|---|---|
| FC_DL_InkViscosityTempComp | FB_DL_SlurryViscosityComp | **存疑①**：同族（温-粘补偿），但邻件为 8 点标定曲线插值 + 冻结降级；本件为单系数线性 + 以「目标黏度」求兑稀系数（输出语义不同）→ 有效变体，交总监复议（该族已 3 件） |
| FB_DL_SpliceCountdownCtrl | FB_DL_UnwinderDiameterCalc | **存疑②**：同一物理关系的**互逆方向**（D→余长 vs 余长→D），输入输出形态互补 → 有效变体 |
| FC_DL_AnodeCurrentDensityCalc | FC_DL_PlatingCurrentCtrl | **存疑③**：前者算面积基准 J_A，后者是电流闭环；不同 → 放行（单/双面口径见 §1-19） |
| FC_DL_AsrsCycleTimeCalc | FC_DL_LifterCycleTimeEst | 有效变体：恒速往复模型 vs 梯形/三角双轴模型，不同阶 |
| FC_DL_ForkEntryClearanceCalc | FC_DL_ForkExtendSafeChk | 有效变体：横向入叉余量 vs 纵向伸出余量 |
| FC_DL_DiverterLeadTimeCalc | FC_DL_LaneDiverterAngleCalc | 有效变体：提前量/延时 vs 偏转角/通过时间 |
| FC_DL_RinseDragOutCalc | FC_DL_RinseWaterVolumeCalc | 有效变体：槽液物料平衡补水率 vs 管容×次数冲洗水量 |
| FC_DL_ImpulseSealDwellCalc | FB_DL_SealJawDwellTrim / FB_DL_HeatSealProfile | 有效变体：开环能量平衡 vs 闭环质量微调 / 三段配方曲线 |
| FC_DL_BeltThroughputCalc | FC_DL_ScrewPressThroughput | 有效变体：节距-件长件率 vs 螺旋压榨处理量 |

**去重拒收 0 件**；存疑放行 3 对（①②③）已列 §4 复议入口。

---

## §3 拒收清单

| 文件 | 原因 | 与哪件重复 |
|---|---|---|
| `DL_Algo\FB_DL_ToteGapReleaseCtrl.st` | **BLOCK**：L28 中心距阈值（箱长+净距）与 L37 净距实测量比较、L44 又用净距阈值退出，同一引脚两种口径。正常工况（净距<箱长）入口永不满足 → 10 s 后误报 9302 停线。修法：L37 改 `fGapActM >= fMinGapM`（或在 L28 增设 `fGapActNeed` 净距专用出口），并补 `fGapNeedM/fGapMarginM` 的故障拍预置零 | 不与任何存量件重复（名称/指纹/语义三通均无命中） |

---

## §4 三条最高价值发现

**① 「同一引脚两种口径」是比公式写错更隐蔽的状态机缺陷（1 BLOCK）**
ToteGapReleaseCtrl 的入口用中心距阈值、出口用净距阈值，两边各自看都「自洽」，只有把 L28/L37/L44 连起来读才暴露。这类缺陷**编译闸全绿、单测取默认引脚也全绿**（默认间距大时能放行），现场却必然停线。规则化为机检锚点：FB 内同一输入变量若在同一文件里既与「含尺寸的复合量」比较、又与「该尺寸本身」比较 → 即告警 `ANCHOR_GAP_SEMANTIC_MIX`。

**② 反馈电平直接推进相位 = 限位粘连即跳段（PlatingLineTransferSeq）**
`build` 侧 4 个复杂 FB 里 3 个用 `R_TRIG` 做握手（正确），唯独 PlatingLine 用**电平**推进三段（L162/171/180），且没有「命令发出后反馈须先假后真」的门。历史血案 R527 记的是「反馈预闭合 → 静默挂死」，本次是**镜像形态**：预闭合 → 静默跳段（未升起就横移，撞槽）。同一根因两个方向，应统一成一条规则：相推进的反馈必须在本相入口采样一次基准值，只认**本相内新产生的沿**。

**③ 道 2 的指纹定义本身是缺陷源（9 条假阳性全是同型碰撞）**
sig 只编码「kind + 类型序列」，40 件里 9 件（22.5%）与既有件撞键，全部为 `REAL×5` 同型；若不看语义直接采信道 2，本轮拒单率会凭空多 22.5%。这与 R528/R533 反复强调的「判重严格≠判重粗暴」是同一个陷阱的反面。已给出零成本修法（分组键并入 `in_n/out_n/sm`），并建议把「道 2 命中后必须先做域复核，未复核不得计入拒单」写进流程。
