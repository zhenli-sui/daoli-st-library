# REVIEW_R84 · 审校与去重回执（2026-11-24 · 40 件）

## 1. 裁决汇总
PASS **35** ｜ 存疑放行 **2** ｜ 拒收 **3**（拒收均因语义道重复，不含编译闸结论；闸 FAIL 件由总监汇总时剔除）
分级统计：BLOCK 0 ｜ MAJOR **7**（分布 5 件）｜ MINOR **13**（分布 11 件）｜ 逐行细审 23 件（11 FB + 12 公式 FC，占 57.5%）

## 2. 拒收清单（语义道，附行号证据）
| # | 文件 | 与哪件重复 | 附加缺陷 |
|---|---|---|---|
| R1 | FB_DL_ToolMagazinePosSeq | **FB_DL_TurretToolSelect**(DL_Motion/R61)「刀位环计数+最短路径择向」同判据同输出形态；FB_DL_ToolChangerSeq 已覆盖换刀时序 | :70-80 择向 iDiff 取绝对值后丢符号，req<cur 恒按正转计 → 半数工况走最长路径；iDir(:45) 未出口，:83 注释「供执行层决定正/反转」落空 |
| R2 | FB_DL_ReactorHeatupProfile | **FB_DL_ReactorStepCtrl**(DL_Process/R31) 升温·保温·滴加·冷却四工步已含本件三工步；斜坡另有 FB_DL_RampSoakProfile / FB_DL_RampGenerator | :57 非有限闸漏 rCoolTargetC → NaN 时 eCool 永不完成、设定值无界下漂 |
| R3 | FC_DL_FluidBedDryLossCalc | **FC_DL_MoistureContentCalc**(DL_MathData/R75) 同为 (湿−干)/湿×100 且域闸序列逐条相同；本轮计划已以同因驳回其前身 GranuleMoistureCalc | — （干基口径可回填既有件，不宜以新件重入）|

## 3. MAJOR 清单
1. `FB_DL_CncToolWearCompLoop:186` 名义切削功率量纲差 1000×：Kc[N/mm²]×Q[mm³/s]=N·mm/s=1e-3 W，÷1e3 只得 W 记为 kW（应 ÷1e6）→ 比能比恒被 :193 钳到 0.2、:219-221 自适应增益永停 0.02。修：常量改 1.0E6 并同步 :21 量纲自检行。
2. `FB_DL_CncToolWearCompLoop:167` bReset 按电平（注释/引脚声明均写「上升沿」）：按住复位时段3 每拍清路程·滤波·累计刀补并强迁 eIdle，而 :304 xValid 不含复位态 → **上层读到 fVbEst=0 且 xValid=TRUE（零磨损被采信）**。修：改 rtReset(CLK:=bReset)，xValid 加 AND NOT rtReset.Q。（安全侧；修法改变行为，按纪律挂账不就地改）
3. `FB_DL_HeadboxJetRatioLoop:205/209` 段8 只按三闸门控、未按相位门控：eStabilize 相内已积分并出开度增量（稳定窗形同虚设），eIdle 失能仍按 Kp 项改指令 → 与 :202「仅在调节窗口内积分（R99）」及边界五矛盾。修：_bAdjOk 加（eState=eRegulate AND bEnable），冻结判据补 eStabilize。
4. `FB_DL_ReactorChargeSeq:58` 单 TON 以 A|B|C 三相作 IN，且 A→B→C 相邻迁相不复位（:93-127 同拍迁移，IN 恒真）→ 600 s 单组分超时被三相共享，慢 A 挤占 C，C 提前报 505。修：照 `FB_DL_CncLoadUnloadSeq:69-71` 加 xPhaseChg 拉低一拍，或三相各持实例。
5. `FB_DL_KilnPreheatStageSeq:108-134` 压差 NaN/Inf 只在 eStageCheck/eStableCheck 拦（:101/:121），eFeedOn/eFeedUp 不查 xDpBad → 变送器失效时堵料判据判「不堵」，继续投料/升速。修：两相 IF 首句加 `ELSIF xDpBad THEN _iErr:=702`。
6. `FB_DL_ReactorHeatupProfile:57` 非有限闸只枚举 rTargetC 与 rPv（拒收件，缺陷一并记录，便于改判后收编）。
7. `FB_DL_ToolMagazinePosSeq:70-80` 择向方向判反 + iDir 未出口（拒收件，同上）。

## 4. MINOR（13 条，代表 3 例 + 系统性条目）
- 代表性三条：①`FB_DL_TabletWeightAutoCtl:148` 注释「八个浮点入参」实枚举 9 个；②`:227/:256` 段8 称「状态量门控」而 _bAdjOk 无相位判定，且「本拍不调节」与 :205/:228 同拍即调节矛盾；③`FC_DL_PressSectionDewaterCalc:59-61` 缺 fInDryPct<fDryMaxPct 组态闸，入口干度超上限时 fGainPct 反算为负（出口干度低于入口）。
- 其余：CncToolWearCompLoop 2602 信息级 vs RunawayGuard 2712 故障级（口径分裂）；TabletCompactionSeq:55 tonFill 相或共用（#9 同型结构，靠中间相断开才复位）+ iRejectCnt INT 无容量载体（同轮他件用 DINT）；KilnPreheatStageSeq:79-81 堵料锁存不参与任何相联锁；ToolMagazinePosSeq:84/90 到位与超时同拍判故障，而 CncLoadUnloadSeq:90 同拍取到位（四件同型判据口径分裂）；ReactorHeatupProfile:58-66 / HeadboxSliceSeq:64-74 组态闸在复位块之前每拍重锁（601/801 实为电平）；GranuleSizeD50Calc:56-58 仅 D10 有「首档越限」处理；KilnSpecificHeatCalc:9 默认值 32 kg/t 得 176 kcal/kg（常规 700~800）。
- **系统性（≥3 件同型，报总监触发扩面）**：内联重算库内既有低层能力——FC_DL_TabletWeightRsdCalc:61-74 / FC_DL_BlendUniformityCalc:63-76 / FB_DL_TabletWeightAutoCtl:207-224 各写一遍均值+样本标准差（两遍法），库内已有 `FC_DL_StatsMeanStdDev`（Welford 单遍），两法并存且无分工声明；FC_DL_JacketAreaCalc:47-59 内联 LMTD 并重复出口 fLmtd，库内已有 `FC_DL_HeatExchangerLmtd`；另 2 件内联 PI（TabletWeightAutoCtl:232、HeadboxJetRatioLoop:211）与 `FB_DL_PidController` 分工声明冲突。

## 5. 三道去重（registry 1,609 名 / 指纹库 1,530 条 ≡ 100%）
- **名称道 命中 0**：40 件无同名、无规范化后同词根（最高 Jaccard 0.50 三例均假阳性：ForceUnitConvert / AreaUnitConvert / ScrewPressDewaterSeq，逐条已做域复核）。
- **签名道 命中 11，其中假阳性 11、真命中 0**：全部为 `REAL×n/REAL×m` 同型碰撞（R83·R548 已定分组键缺陷，`sig` 不含 in_n/out_n/sm），逐对域复核后全否。
- **语义道 命中 3（拒收）+ 2 存疑**：见第 2 节与第 6 节；已核 8 组最近邻（Turret/StepCtrl/MoistureContent/StatsMeanStdDev/HeatExchangerLmtd/FillWeightCtrl/BatchDoseSeq/RatioController）。

## 6. 存疑放行（请总监复议，勿计入拒单 KPI）
1. `FC_DL_ToolWearVbCalc` — 主输出 VB 为新语义域，但 fRemainMin「到限值剩余时间」与在库 `FB_DL_ToolLifeBudget` 剩余寿命口径重叠，且其前身 ToolLifeRemainCalc 已被本轮计划以同因驳回 → 疑规避式重入。
2. `FC_DL_ReactorAdiabaticRise` — ΔTad 与同轮 `FB_DL_ReactorRunawayGuard:208-218` 数值等价（仅入参 kg×代理摩尔质量 → mol），新增价值为「去代理常量 + 输出投料完成度」；属「联锁件内部段拆为独立计算件」边界情形。

## 7. 就地修记录
0 件。本轮无编译阻断项；唯一安全侧项（MAJOR-2）修法必然改变行为，按 R333「行为零变更」约束挂账至 R85。

## 8. 挂账优先级（R85）
P0：MAJOR-2（CncToolWearCompLoop 复位语义，安全侧）→ MAJOR-5（KilnPreheat NaN 穿透）→ MAJOR-3（HeadboxJetRatio 相位门控）→ MAJOR-1（量纲 1000×）→ MAJOR-4（ReactorCharge 定时器）
P1：拒收件 R1/R2 若不撤，须先修 MAJOR-6/7 并改为组合调用既有件（R216 双向互引）
P2：系统性内联重算（统计内核 ×3 + LMTD ×1 + PI ×2）→ 定口径：组合调用 or 显式分工声明
P3：口径分裂三组（码级 2602/2712、同拍到位判据四件、INT/DINT 计数）
