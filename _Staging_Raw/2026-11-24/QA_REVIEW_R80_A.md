# QA_REVIEW_R80_A — R80 轮 A 批（36 简单件）独立审校与三道去重

> 审校席：dl-qa-dedup｜2026-11-24｜对象：ROUND_PLAN_R80 §二 序号 1~36（A1/B1/C1/D1/E1 五族）
> 方法：36/36 全文通读（非抽样，本批件均 ≤134 行）+ 名称/指纹/语义三道去重 + 12 项定向扫查逐项取行号
> 前置声明：本席未参与规划；L2 闸报告（GATE_R80_A）在本人独立取证后才交叉比对，重合项已注明"双源独立命中"

## 一、分级统计

| 口径 | 计数 | 明细 |
|---|---|---|
| PASS（可入库） | 33 | 其中 11 件"带 MAJOR 挂账入库" |
| 存疑放行（供总监复议） | 1 | FC_DL_StatsGeoMeanCalc |
| 拒收 | 2 | FC_DL_HydroPipePressDrop（去重）、FC_DL_StatsIqrCalc（BLOCK 返修） |
| BLOCK | 1 | FC_DL_StatsIqrCalc |
| MAJOR | 12 | 11 件 + 1 条族级（非有限闸，覆盖 34 件） |
| MINOR | 12 | 见 §四 |

## 二、12 项定向扫查汇总（36 件全量）

| # | 扫查项 | 结论 | 证据（文件:行号） |
|---|---|---|---|
| 1 | 组态闸结构早退 | **命中 1**（MINOR） | CoagulantDoseCalc:62-65 下限钳零后未复核 `_rLo ≤ _rHi`，`LIMIT(0,x,负)` 主参倒置 |
| 2 | 除子全闸 | 无 | 逐件核 `/` 共 47 处：IQR:68/89 有 span 闸、PooledStd:57 自由度闸、CopCalc:44 功率下限闸、SludgeAge:63 排泥闸均在除前 |
| 3 | 数组下标越界 | **命中 1**（BLOCK） | StatsIqrCalc:69 `WHILE (j >= 0) AND (aBuf[j] > _rKey)` —— j 递减到 −1 后若右侧被求值即读 aBuf[−1]；IEC 61131-3 不保证 AND 短路 |
| 4 | 浮点容差比较 | 无硬 `=` 判等 | 全件无 `IF x = 常数`；StatsRangeCalc:55 / DevSumSq:56,66 / GeoMean:53 用 `<>` 变体做非有限判（见 #5） |
| 5 | 非有限值处理 | **命中族级**（MAJOR） | 34/36 件写 `(rX = rX)` 自反判定（例 WeighNetFromGross:35、StatsRangeCalc:47）；该式只挡 NaN、**+Inf 判为有限**（Inf=Inf 为真）→ Inf 直穿出口且 bValid=TRUE。违反 R482「非有限闸统一 ABS(x)>FIN」 |
| 6 | 状态机可达性/出口 | **命中 2** | WeighHopperRefillSeq:75-78 置 `_nFault:=3` 同拍被 :117 `rtStop.Q` 复位 → 故障码 3 永不可观测；HydroPressRampSeq:121-125 复位需 rtBuild/rtRelease 上升沿，可达 ✔ |
| 7 | 故障/空闲态输出清零 | **命中 1**（MAJOR） | HydroPressRampSeq:120-125 eFault 相不写 `_rSp`，每拍 :130 继续输出故障前高压设定；eIdle:84 却归零 → 同件内两套口径 |
| 8 | 超时兜底 / TON 无条件刷新 | 无 | HopperRefillSeq:56-59、HydroPressRampSeq:62-67、StatsRollingVar:47 的 TON/R_TRIG 全在 CASE 外段 0 调用 ✔；等待相（eSettle:107、eRampUp:94、eRampDown:116）均配 TON ✔ |
| 9 | 声明未赋值/赋值未声明 | **命中 3**（2 MAJOR 1 MINOR） | HydroAccumulatorSizing:18 rPressPrecharge 仅进门闸、:59-72 公式零引用；PneuCvFlowCalc:20 rDownPressBarA 不入 :67 流量式；RefCondApproach:17 rApproachRef 全文零引用（MINOR） |
| 10 | 死代码/恒假恒真谓词 | 无 | 逐件扫 ELSE 兜底与 8 处「阈值倒置交换」皆可达；WeighMultiHeadSum:53-75 穷举 255 掩码无恒假支 |
| 11 | 双语注释/分号位置 | 无 | 36/36 行内注释均「中文 / English」双写且 `;` 在注释之前；缺英注 0 处 |
| 12 | 版本头与溯源 | **命中 1**（MINOR） | 36/36 有 组件名/分类/功能/开源溯源/复杂度/版本 六段头 ✔；仅 WeighSpanCalibRatio:6 溯源自称 internal-design，而规划表:29 标 `queue:oscatBasic/F_LIN green`，且正文无 F_LIN 语义对齐说明 |

## 三、缺陷明细（BLOCK / MAJOR，逐件带判定式）

**BLOCK-1 FC_DL_StatsIqrCalc:69** — `WHILE (j >= 0) AND (aBuf[j] > _rKey)`，内层 `j := j - 1`（:71）后 j 可达 −1；若编译器不短路，`aBuf[-1]` 越界读 → 运行期异常/邻变量污染。判定式：`j` 的下界闸必须写在数组取值之前（`IF j < 0 THEN EXIT` 或改写为 `WHILE j >= 0 DO IF aBuf[j] <= _rKey THEN EXIT`）。**本席独立发现，L2 闸未报**。返修后入库。

**MAJOR-1 FC_DL_WeighSpanCalibRatio:53-55（双源独立命中）** — `_rRatio := rRefSpan/_rDelta`（kg/count）后 `:54 _rPred := _rRatio * rRefSpan`（kg²/count）→ `:55 _rErr := (_rPred-rRefSpan)/rRefSpan*100`。量纲不闭合：`_rPred` 应乘的是另一组 count 读数。典型值 ref=10 kg、Δ=20000 count → `_rErr≈−99.95%` → `:59` 恒超 5% 闸 → **本件永远 bValid=FALSE**，标定功能整体失效。R333 例外不适用（改公式即改行为），挂账返修。

**MAJOR-2 FC_DL_HydroAccumulatorSizing:59-72（双源独立命中）** — 分母 `_rDen` 取 `(Pmax/Pmin)−1`（或 `EXPT(·,0.714)−1`），**预充压力 P0 完全不进式**；标准口径 ΔV=V0[(P0/Pmin)^k−(P0/Pmax)^k]。取 P0=100/PMin=150/PMax=250：应 V0=3.75·ΔV，实算 1.5·ΔV → **容积偏小 2.5 倍**；`:72 rUsableRatio := ΔV/_rVol` 恒等于 `_rDen`，是自反输出而非独立量。选型偏小属工程错误输出。

**MAJOR-3 FB_DL_WeighHopperRefillSeq:75-78 ↔ :117** — 段 2 在 bStop 电平上置 `_nFault:=3` 并迁 eFault；同拍 CASE 进 eFault，`:117 rtStop.Q`（同一上升沿）立即清 `_nFault:=0` 迁 eIdle → **置位与复位同拍**，:42 声明的"故障码 3 人工停止"永不可观测。与 R79 R466（声明上升沿、实现电平）同族。

**MAJOR-4 FC_DL_PneuCvFlowCalc:67 + :65（双源独立命中 + 本席新增半条）** — `:67 _rFlow := 0.865*Cv*rUpPressBarA*SQRT(1/(SG*T))` 只含阀前压力，**阀后压力与流量无关**（rDownPressBarA 沦为门闸件）；`:65 rCritical := _rRatio >= 0.528` 把"压降比"与"临界压比"混用，空气阻塞判据应为 `P2/P1 ≤ 0.528` 即 `压降比 ≥ 0.472`，现口径把 0.472~0.528 区间误判为未阻塞。

**MAJOR-5/6 FC_DL_RefSatPressToTemp:25-26 与 FC_DL_RefSatTempToPress:25-26（双源独立命中）** — 两件 R410A 行压力表与 R134a **逐值相同**（1/2/4/6/8/10/14/18 bar）。R410A 公开物性：0 °C↔7.99 bar、45 °C↔27.3 bar；表中 `(6 bar, 0.4 °C)`、`(18 bar, 45 °C)` 分别偏 ~33%/34%，插值后饱和温度误差 5~8 K，直接毁掉过热度/过冷度判据。R134a 行抽核 `1 bar↔−26.1 °C`、`10 bar↔39.4 °C` 正确 → 仅 R410A 行错。

**MAJOR-7 FC_DL_RefCompressorCapacity:59-62** — ①`:59` 把 `rSweptVol_m3h`（额定转速下的理论排量）再乘 `_rSpeedRatio`，重复计量；②`:62 _rCap := _rMass * rDh / 3600`，`rDh` 定义为"吸气到排气焓差"（压缩功）→ 算出的是**轴功率**而非制冷量，按 COP 3~4 计系统偏低 3~4 倍，却挂在 `rCapEst_kW` 出口。

**MAJOR-8 FC_DL_PneuAirConsumeCalc:63** — `_rStdL := _rVolL * (rPressBar + DL_ATM_BAR)`：结果为 l·bar 量纲，缺 `/DL_ATM_BAR`。标准状态折算应为 `V·(P+1.013)/1.013`，现式对任意工况恒偏大 1.013 倍（1.3%），量纲不闭合；`:29 DL_ATM_BAR:=1.013` 与 PneuLeakRateCalc:27 `1.01325` 常量口径亦不统一。

**MAJOR-9 FB_DL_StatsRollingVar:83** — `_rVar := (_rSumSq - _rSum²/n)/(n-1)` 单趟平方和法。样本偏置 1e6、波动 1e-3 时有效位数尽失，`:84-86` 负值钳零 → **静默输出方差 0 且 bValid=TRUE**。库内同量已有 Welford 口径件（FC_DL_StdDevOnline、FB_DL_StatsWelfordVar 头注明写"免灾难性抵消"）→ 口径分裂，与 R482 族级教训同类。

**MAJOR-10 FC_DL_SludgeAgeCalc:55-58** — 排泥固体浓度取 `MAX(rWasTss, rEffTss)` 后乘**排泥流量**：出水带泥属另一流股（Qe·Xe），用 max 替和既漏计出水侧又不该套排泥流量；方向使排泥量偏小 → **SRT 偏大（非保守）**，直接影响排泥定值。

**MAJOR-11 FB_DL_HydroPressRampSeq:120-130** — 见扫查 #7：故障锁存相残留高压设定输出，与 eIdle:84 归零口径矛盾；液压故障时下游仍收到建压设定。

**MAJOR-12（族级）非有限闸口径** — 34 件写 `(rX = rX)`：挡 NaN 不挡 ±Inf（Inf=Inf=TRUE），Inf 直穿出口并置 bValid=TRUE。违 R482。同族计数 34 ≥ 3 → **触发扩面复审**（建议交由 dl-gate 落机检锚点：实参形如 `(X = X)` 即告警）。

## 四、MINOR（留档，不修）
1. WeighTareDriftCheck:18 nSamples 仅作 `≥1` 计数闸，无均值装配；规划:23 声明"滑动均值对比标定值"未实现（死参数+规划漂移）。
2. WeighDoseTolBand:26 `_bFin` 注释"三实数输入"实为五输入（复制残留，与 L2 闸同判）。
3. WeighSpanCalibRatio:6 溯源与规划表:29 oscat F_LIN 不一致（见扫查 #12）。
4. CoagulantDoseCalc:62-65 上限为负时 LIMIT 主参倒置（见扫查 #1）。
5. DoDeficitCalc:22 `rSaturationPct` 名为饱和度实为"实测/设定百分比"，口径命名不符。
6. RefCondApproach:17 rApproachRef 死输入（声明但正文零引用）。
7. StatsIqrCalc:60-90 与库内 FC_DL_QuartileCalc 的排序+插值逻辑重复实现（未引用既有件）。
8. StatsDevSumSq:47 `bUseGivenMean=FALSE` 时仍强制校验 `rMeanGiven` 有限 → 无谓判无效；:74 自由度用 REAL 出口（应为 INT）。
9. RefSuperheatCalc / RefSubcoolCalc 结构孪生（L38-59 逐行同构，仅差号与命名），建议后续合并为带符号口件的单件。
10. StatsRollingVar 头注未披露"平方和法"选择理由（MAJOR-9 的文档侧）。
11. **族级**：17/36 件头注「复杂度」与 ROUND_PLAN:22-57 不符（例 HopperRefillSeq C2↔C3、WaterLangelierIndex C2↔C3、SludgeAge C1↔C2、PneuCvFlow C1↔C2）→ 复杂度配额统计失真。
12. HydroPipePressDrop:22 rRough_mm 仅登记不入判据（头注已声明，随拒收件退场）。

## 五、三道去重结论（36 件全量）

| 道 | 结果 |
|---|---|
| a 名称 | 对 1,453 条 registry 规范化后精确比对：**零撞名**；词根/编辑距离 ≥0.85 邻名命中 1 组：`StatsGeoMeanCalc` ↔ 在库 `FC_DL_GeoMeanCalc`（去 Stats 前缀后同词根） |
| b 指纹 | 36 件签名分组后无跨件同指纹；与库内同族件比：`RefSuperheatCalc`/`RefSubcoolCalc` 互为孪生（见 MINOR-9），`StatsPooledStd`/`StatsDevSumSq`/`RangeCalc`/`IqrCalc` 各自独立；批内无互重 |
| c 语义 | 判重 **1**：`FC_DL_HydroPipePressDrop` ↔ 在库 `FC_DL_PipeFrictionLoss`（DL_MathData，Darcy-Weisbach，含层流/过渡/湍流+粗糙度+密度黏度+局部阻力+kPa 全参数）。新件仅固定 ρ=850、改 cSt 输入、bar 输出、去掉过渡区与局部阻力 → 既有件 `fRho_kgm3:=850, fMu_cP:=cSt*0.85` 一次调用即同值同语义，属**严格子集再实现**，无新边界/新域/新行业约束 → 拒收<br>存疑 **1**：`FC_DL_StatsGeoMeanCalc` ↔ `FC_DL_GeoMeanCalc`（同为 log 域 Σln/n → exp）。豁免理由：REAL[0..31] vs LREAL[1..32] 精度/索引方言（属法定有效变体）+ 新增 `nSkipped` 逐点剔除语义（既有件为整体拒算 + nRejectReason）→ 判**存疑放行**，请总监 3 日内复议；若维持则须在头注声明与 GeoMeanCalc 的口径差 |
| 放行（不为重复） | `StatsRangeCalc`↔`StatsMinMaxWindow`（新增极差+NUsed，索引宽度不同）；`StatsIqrCalc`↔`QuartileCalc`（新增 IQR+双栅栏）；`StatsRollingVar`↔`WelfordVar`/`StdDevOnline`（定窗 vs 终身，形态不同）；`WeighTareDriftCheck`↔`FB_DL_LoadCellTareDrift`（基准件 vs 自建基线速率档，判据不同）；`PneuLeakRateCalc`↔`FB_DL_AirLeakDecayTest`（纯函数叶 vs 三段顺控）；`HydroAccumulatorSizing`↔`FB_DL_HydraulicAccumPreChg`（选型 vs 预充监视）；`WeighBatchYieldCalc`↔`FC_DL_WaferCountYield`（工艺投料 vs 晶圆计数，域不同） |

**复议候选（仅此 1 件）**：`FC_DL_HydroPipePressDrop`。若总监认定"液压油固定介质 + cSt/bar 行业方言"构成 R134a/R410A 式的介质方言豁免，可撤销拒收并改为「复用 PipeFrictionLoss 的液压简版」，须在头注显式链接既有件并声明覆盖关系。

## 六、挂账清单（下轮优先级排序；本轮修复配额 0，全部不就地修）
1. **[P0]** StatsIqrCalc:69 短路越界（BLOCK，返修后入库）— 1 行改判据。
2. **[P0]** 非有限闸族级整改（34 件）：`(X = X)` → `ABS(X) > 1.0E30`，按 R482「一族一次做完 + 注释同步」，并交 dl-gate 落 `(X = X)` 机检锚点。
3. **[P1]** RefSatPressToTemp/ToPress R410A 行按 NIST REFPROP 重录（0 °C↔7.99 bar、40 °C↔24.2 bar 两点锚）。
4. **[P1]** WeighSpanCalibRatio 重写量程误差式（须引入第二组 count 读数或改为对 ref 的偏差口径）。
5. **[P1]** HydroAccumulatorSizing 换标准式 `ΔV/((P0/PMin)^k−(P0/PMax)^k)` 并让 rUsableRatio 独立于 _rDen。
6. **[P2]** PneuCvFlowCalc 补 `P2/P1` 阻塞式（Q ∝ P1·0.471 段截断）+ 临界判据改 0.472。
7. **[P2]** HopperRefillSeq 故障码 3 复位改 rtBuild 单一路径（避免同拍自清）。
8. **[P2]** HydroPressRampSeq eFault 输出归零或加 bSafeHold 显式声明。
9. **[P2]** RefCompressorCapacity 拆分「轴功率」与「制冷量」双出口，去掉重复转速比。
10. **[P3]** StatsRollingVar 换 Welford 递推（或头注披露精度边界 + bSaturated 标志）。
11. **[P3]** SludgeAgeCalc 排泥量改 `Qw·Xw + Qe·Xe`。
12. **[P3]** PneuAirConsumeCalc 补 `/DL_ATM_BAR` 并统一 1.01325。
13. **[P3]** 17 件复杂度头注校准（宁升不降，保配额口径一致）。

## 七、给 dl-gate 的新增机检锚点（反推自本轮逃逸）
- `A_NAN_SELF`：实参形如 `(X = X)` 或 `(X - X)` 的比较式 → 告警（本轮 34 件同型，L1/L2 全过）。
- `A_WHILE_SHORT_CIRCUIT`：`WHILE ... AND (arr[i] ...)` 且循环体内对 i 自减 → 告警（本轮 BLOCK 唯一漏网）。
- `A_COMPLEXITY_MISMATCH`：头注 `复杂度` 与 ROUND_PLAN 表列不一致 → 告警（本轮 17 件）。
