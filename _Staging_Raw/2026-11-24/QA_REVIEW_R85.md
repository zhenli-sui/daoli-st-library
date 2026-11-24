审校 13 件 ｜ PASS 3 / 存疑 6 / 拒收 4 ｜ BLOCK 5 / MAJOR 3 / MINOR 8

# R85 审校与去重报告（qa-dedup）
范围：r85_targets.json 40 件全量三道去重；12 项扫查抽检 13 件（含 4 件 C4 全部 + 9 件 C1/C2）。
就地修：0 处（本轮无零变更安全侧修，全部给修法挂下轮）。

## 一、三道去重（40/40 已跑）
| 道 | 命中 | 人工判读 | 真命中 | 假阳性剔除 |
|---|---|---|---|---|
| 名称（精确+词根 Jaccard≥0.55） | 0 | — | 0 | 0 |
| 签名指纹 sig_groups | 2 | 均为 REAL×5 同型碰撞（`FC_DL_ExtrusionSpecificPressureCalc` 5/4、`FC_DL_CompactionPressureCalc` 5/4 → `FC_DL_SludgeAgeCalc`，语义无关：挤出比压/压制压力 vs 污泥龄） | 0 | 2 |
| API 序列 api_groups | 0 | — | 0 | 0 |
| 语义同义（一次调用能否同值） | 3 存疑位 | 见下 | 1 存疑 | 2 放行 |

语义判读明细：
- **存疑** `FC_DL_AnodizeFilmThicknessCalc` 与在册 `FC_DL_PlatingThicknessChargeCalc` 代数同式（M/(z·F)·1000 即 fEquivMgC，同一 fMassG/fThickUm 链路，仅多反算时间 t=δzFρ/(JMη·100)），且与本轮 `FC_DL_AnodizeBathChargeCalc` 输出语义（fFilmUm+fTimeForTargetS）重合 → 建议总监在「FilmThickness/BathCharge 二择一或合并」中裁定，不当场判重。
- 放行 `FC_DL_AnodizeBathChargeCalc`：槽级 Q=I·t、电流密度、标定系数 k 输入，与 Plating 件的电化当量输入域不同，有新增工程价值。
- 放行 `FB_DL_AnodizeLineTransferSeq` vs 在册 `FB_DL_PlatingLineTransferSeq`（词根 0.5，sig 未命中）：工艺对象不同（阳极氧化 vs 电镀）+ 结构签名不同 + 本件有槽位占用表/防双载/路径防撞，判有效变体。
- 提示 `FC_DL_SugarBoilSupersaturationCalc` 与 `FB_DL_SugarPanBatchSeq.CalcSupersaturation`：同一物理量两种公式（纯率+纯度修正 vs (100−Bx) 归一+线性溶解度），本轮放行，后续再出 S 公式件须判重。
- 工艺公式族核查：Chvorinov（凝固）、Harris（渗碳）、PQ²（压射）在册无同式件 → 新件；法拉第族见上。

## 二、逐件缺陷（行号证据）
| 名称 | 项 | 行号 | 分级 | 证据 | 修法 |
|---|---|---|---|---|---|
| FB_DL_SugarPanBatchSeq | ①③ | 232 / 275 / 304 | **BLOCK** | `_bBrixBad := ... OR (fBrix <= 0.0)`；`_bBatchActive` 含 eVacuum；`ELSIF _bBatchActive AND (_bVacBad OR _bBrixBad) THEN _bFaultReq := TRUE` | 空罐抽真空（锤度=0）即锁 E2，批次无法启动；契约④只豁免 eIdle。修：锤度域判起点改为 eConcentrate，或 _bBatchActive 排除 eVacuum/eFillSyrup |
| FC_DL_CarburizeCaseDepthCalc | ③ | 42-45 / 51-53 / 58-64 | **BLOCK** | NaN 闸仅列 fTempC/fHoldH/fKRefMmSqh/fEnergyJmol，缺 **fTRefC**、fTargetMm；`fTRefK <= DL_EPS` 对 NaN 恒假 → `fExp` NaN → `fKCoef` NaN → `xValid := TRUE` 回 NaN | 出口前对 fCaseMm/fKCoef/fTimeTargetH 做自反复检；fTRefC/fTargetMm 纳入非有限闸 |
| FC_DL_QuenchOilTempRiseCalc | ④ | 19 / 52 | **BLOCK** | `fExchCapKW [kW]`；`fSteadyTempC := fOilTemp0C + (fPartHeatKJ / fCycleTimeS) / fExchCapKW` → kW/kW 无因次加 °C | 量纲错：换热能力须为 kW/K（或除以 k·A）；修后 fSteadyTempC=fOilTemp0C+P/(kA)，否则 xOverTemp（54 行）恒假 |
| FB_DL_LadlePourWeightCtrl | ② | 89-93 / 96 | **BLOCK** | 组态闸只置 `_bCfgBad`，无 RETURN；随后 `fDevPct := (fWeightKg - fTargetKg) / fTargetKg * 100`（fTargetKg 可 0/负）→ Inf/NaN 直出 fDevPct | 组态闸与除零闸分离：`IF ABS(fTargetKg) > DL_EPS THEN fDevPct := ... ELSE fDevPct := 0.0`；或闸命中即跳段 4 |
| FB_DL_LadlePourWeightCtrl | ⑩ | 157-160 vs 104/117/131/146/155 | **BLOCK** | ELSE 兜底仅 `_bFault/_uFault`，未置 `bPourFast := FALSE; bPourSlow := FALSE`（其余 5 分支均显式清零，且无段 1 预清零） | 段 1 增加 `bPourFast := FALSE; bPourSlow := FALSE`；安全侧输出不缺省依靠分支覆盖 |
| FB_DL_QuenchTemperLineSeq | ⑤⑧ | 255 + 446 | MAJOR | `IF _ePhase <> _ePhasePrev THEN _nRetry := 0; ...` 与段末 `_ePhasePrev := _ePhase;` → 段 1 进入时两值恒等，分支永不成立 | 相迁移后置（重试清零 + eG1 清）永不执行：_nRetry 跨相累计、E1 记录永久锁存。修：把快照移到段 1 之后（段 2 之前） |
| FB_DL_AnodizeLineTransferSeq | ⑤⑧ | 270 + 451 | MAJOR | 同上：`IF _ePhase <> _ePhasePrev THEN _nRetry := 0`，段末 `_ePhasePrev := _ePhase` | 行走 E1 重试预算跨相累计，第二相提前 eRetryOver。修同上 |
| FB_DL_DieCastCycleSupervise | ⑨ | 247-248 / 305 / 382 | MAJOR | `_bVelBad` 仅在 272 用于峰值跟踪；段 2 只判 `_bPressBad OR _bPosBad` → 速度非有限不进 E3，_fVelPeak 停 0 → 判据点②逐模判废 | 与契约②「信号非有限=黑」不符：速度通道持续失效只出废件不停机。修：段 2 加 `_bVelBad` 或单列 eVelBad 归因 |
| FC_DL_AnodizeFilmThicknessCalc | ③ | 43-47 / 65 | MINOR | fThickTargetUm 未入非有限闸，靠 `(fThickTargetUm > DL_ZERO)` 对 NaN 恒假兜住 | 纳入闸；勿依赖比较恒假 |
| FC_DL_SugarBoilSupersaturationCalc | ⑫ | 16 / 40 / 59 | MINOR | fTempC 仅参与 NaN 闸、公式不使用（溶解度由 fSolubilityPct 外部给） | 删除该引脚或在注释声明「仅链路校验，不参与计算」 |
| FC_DL_SugarBoilSupersaturationCalc | ④ | 46-47 | MINOR | 闸只判 `fBrixPct <= 0`，无 100 上限（锤度物理域 0..100） | 加 `OR (fBrixPct >= DL_PCT_BASE)` |
| FB_DL_DieCastCycleSupervise | ⑫ | 333-334 vs 237-238 | MINOR | bReset 只清 _fVelPeak/_fBuildS，不清 _fSlowEndMm/_fHoldMpa（ResetCycle 清） | 复位清单补两项，消除与 ResetCycle 口径分裂 |
| FB_DL_SugarPanBatchSeq | ⑫ | 351-355 | MINOR | 新批起算只清 _fBatchAccS，_fBrixLatch 跨批残值（中途故障批后 fBrixLast 显示上批） | eIdle→eVacuum 迁入时清 _fBrixLatch |
| FB_DL_QuenchTemperLineSeq | ⑤ | 81 / 87 / 264 | MINOR | fLevelPct 默认 0.0、fLevelMinPct 默认 70 → 首拍即 E3 锁存 | 集成期易误判；建议 fLevelPct 默认改 100（使能类同族）或在注释声明 |
| FB_DL_SoakPitTemperatureCtrl | ③ | 69-72 / 107 | MINOR | 单拍 NaN 即 `_bFault := TRUE` 且仅复位沿可清，输出永久 0% | 加延时确认（连续 N 拍）或超时自恢复，避免一次坏值停产 |
| FC_DL_DieCastShotVelocityCalc | ⑫ | 38 / 62-63 | MINOR | 变量名 fVelCm，实为 m/s（注释已标 cm³/(mm²·s)） | 改名 fVelMs；公式本身量纲正确（1 cm³/(mm²·s)=1 m/s） |

PASS（无缺陷）：`FC_DL_CastingSolidificationTimeCalc`（32-35 全量 NaN 闸 + 40-41 全除子闸 + Chvorinov t=B·M² 自洽）、`FC_DL_DieCastShotVelocityCalc`（除上列命名）、`FC_DL_AnodizeBathChargeCalc`（五出口预置 + 闸后除子 + t=δ/(Jkη) 反算核验正确）。

## 三、拒收件单列
1. `FB_DL_SugarPanBatchSeq` — BLOCK：eVacuum 空罐锤度 0 触发 E2 锁存，正常批次无法启动（默认必现）。
2. `FC_DL_CarburizeCaseDepthCalc` — BLOCK：参考温度/目标层深未纳非有限闸 → NaN 穿透出口且 xValid=TRUE（另 K 极小时 (x/K)² 可上溢 Inf，与契约③「K 过小回哨兵」不符）。
3. `FC_DL_QuenchOilTempRiseCalc` — BLOCK：稳态油温量纲错（kW/kW 无因次加 °C），fSteadyTempC 偏小数量级、xOverTemp 判据失效。
4. `FB_DL_LadlePourWeightCtrl` — BLOCK×2：组态闸非早退致除零直穿（fDevPct=Inf）+ ELSE 兜底未清零双阀输出（非法相位保持上拍开阀值，安全侧）。

## 四、MAJOR 挂账（可入库，下轮修）
- `FB_DL_QuenchTemperLineSeq` / `FB_DL_AnodizeLineTransferSeq`：相迁移后置死代码 → 重试预算跨相、E1 不清零（同一修法：快照移位）。
- `FB_DL_DieCastCycleSupervise`：速度非有限不升黑，持续失效只逐模判废不出停机。

## 五、同型聚类（供机检锚点沉淀）
- C1 相迁移后置死代码（2 件：QTL 255/446、Atl 270/451）→ 锚点：`_ePhasePrev := _ePhase` 位于比较之后且无其他写入点 ⇒ 死路径。
- C2 输入未全量纳入非有限闸（4 件：Carburize fTRefC/fTargetMm、QuenchOil fTempLimC、FilmThickness fThickTargetUm）→ 锚点：REAL 型 VAR_INPUT 全部出现在 NaN 闸表达式。
- C3 复位清单未覆盖 `*Last` 输出锁存量（2 件：Dcs _fSlowEndMm/_fHoldMpa、Spb _fBrixLatch）→ 锚点：每输出锁存量须在 bReset 段出现。
- C4 语义近重（Anodize FilmThickness ↔ BathCharge ↔ 在册 PlatingThicknessCharge）→ 锚点：新增件若核心输出 = f(电荷密度·效率)，与法拉第族比对电化当量换算等价性。
- 建议上报总监：C1 为 2/4 件 C4 共有（QTL、Atl），另 2 件无此模式，属模板级拷贝缺陷，无需全库扩面，仅需替换模板。
