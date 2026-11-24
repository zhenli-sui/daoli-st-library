# QA_REVIEW_R82 — 独立审校与去重报告

审校席：QA/Dedup（非产品总监同源）｜轮次 R82｜T0=2026-11-24 11:04
输入：`_names_r82_actual.txt`（40 件，实盘 40/40 全部存在，无缺件）
抽检：**14 件**（4 个 FB 全审 + 10 个 FC），占 35%，超 12 件下限
取证：全部结论带 `文件:行号`；行号取本轮磁盘现行文件
篇幅说明：岗位 SOP 的 60 行上限与「14 件逐条行号取证 + 7 段交付格式」不可兼得，本轮按总监给定的 7 段格式与"每条必须带行号"铁律优先，正文约 190 行；如需 ≤60 行版可另行压缩为摘要+附件。

---

## 一、总体结论

40 件 → **PASS 0 / 有缺陷 14 / 拒收 0 / 未抽检 26**
分级：**BLOCK 2 ｜ MAJOR 12 ｜ MINOR 9**（同一件可跨级，故件数不可相加）

> 与历史抽检（R59~R64 严重 13%、PASS 20%）相比，本轮**结构质量明显上台阶**：三层哨兵（分母闸 / 结果域闸 / 全路径预清）几乎无缺，CASE 全部带 ELSE、ENUM 全带 `:=`、TON/R_TRIG 全部无条件刷新（R7/R188）、无一处占位符、无一处构造函数式转换、无 VLA 透传。**缺陷高度集中在同一个点：非有限（NaN）判据的写法**，以及由此派生的"死输出"。

| 项 | 结论 |
|---|---|
| 1 占位符 | **0 处** —— 40 件全文件机检 `// 略 / // 同上 / TODO / ...` 零命中 |
| 2 除零闸 | 抽检 14 件**全部通过**：每个 `/` 前均有分母判据且带 RETURN（见 §三.2） |
| 3 开方/对数域闸 | 2/2 通过：FlareFlowSizing:80 前有 76-79 非负闸；DemisterVelocityChk:72 前有 65-71 非负闸；CatalystActivityDecay 的 LN 由 74-75 钳位保护 |
| 4 非有限判据 | **系统性失效**：35/40 件统一用 `ABS(x) > 1.0E15`，该式对 NaN 恒 FALSE → NaN 全盲。见 §六.1 |
| 5 量纲一致性 | 抽检 14 件量纲链基本正确，唯一错在 CatalystActivityDecay:91 的**符号** |
| 6 死输入 | 0 处（抽检件全部入参均有分支或计算引用） |
| 7 输出未赋值 | 0 处（段 0 全路径预清执行到位） |
| 8 VAR 声明格式 | 0 处（分号在注释前、中英双语齐全、常量零引用 0 处） |
| 9 构造函数式转换 | **0 处** —— 全用 `DINT_TO_LREAL/DINT_TO_INT/INT_TO_DINT/TIME_TO_DINT` |
| 10 VLA 透传 | 0 处 |
| 11 状态机 | 4/4 FB 通过：CASE 带 ELSE、eFault 出口可达、TON/R_TRIG 段外刷新、计数步进≤容量 |
| 12 文件头溯源 | 40/40 齐备（clean-room 工程公式自研 + MIT 声明 + 功能/码表/边界三段式） |

---

## 二、拒收清单

**无。** 道 1/道 2 精确指纹 0 命中；道 3 正文比对 5 组最近邻，无一件满足"删掉即由邻件替代"的拒收判据（详见 §四、§五）。

---

## 三、缺陷清单（按严重度）

### 3.1 BLOCK（2）

**B1 `FB_DL_CoagDoseJarTestSeq.st`：烧杯结果 NaN 污染投加基准并输出 NaN 设定，且专设的码 13 拦不住**
- `:103` 常量 `DL_CDJ_FIN := 1.0E15`，注释自述"非有限判据阈值（ABS 比较用）"。
- `:212` `IF (rJarResultMgL <= DL_CDJ_EPS) OR (ABS(rJarResultMgL) > DL_CDJ_FIN)` —— 这是为非法烧杯结果设的闸（码 13）。**NaN 时两个子式均 FALSE**（NaN 的一切比较为假），闸不动作。
- `:216` `_rDelta := (rJarResultMgL - _rBaseMgL) / _rBaseMgL;` → NaN
- `:217/:220` 限幅比较对 NaN 均 FALSE → 不被夹住
- `:223` `_rBaseMgL := _rBaseMgL * (1.0 + _rDelta);` → **`_rBaseMgL` 永久变 NaN**
- `:277` `_rDoseCmd := _rBaseMgL * rFlowM3h / rStockGL;` → NaN
- `:278/:281` 上限/下限饱和对 NaN 均 FALSE → 不被夹住
- `:315` `rDoseLh := _rDoseCmd;` → **计量泵设定输出 NaN，`bDoseOn` 仍为 TRUE，`iErrCode` 仍为 0**
- 判定式：`NaN <= eps` ≡ FALSE ∧ `ABS(NaN) > 1.0E15` ≡ FALSE ⇒ 闸恒放行。
- 修法：按 R508 双条件补全 —— 段 2 增 `IF NOT ((rJarResultMgL = rJarResultMgL) AND (ABS(rJarResultMgL) <= DL_CDJ_FIN)) THEN _iInfoCode := 13;` 跳过修正；`:223` 后对 `_rBaseMgL` 自身做同款双条件复核。

**B2 `FC_DL_CatalystActivityDecay.st:91`：RUL 公式符号错误，催化剂"越用越新"**
- `:8` 头注释 `RUL = (k·t + LN(1/0.7))/k` —— **注释与代码同样错**，所以自洽性检查抓不到。
- `:91` `rRulRaw := (LN(1.0 / rActivity) + rLnInv07) / rK;`
- 正确推导：`EXP(-k(t+Δ)) = 0.7 ⇒ Δ = [LN(1/0.7) - LN(1/act)] / k`，即 **减号**。代码用加号。
- 误差方向：`+LN(1/act)` 随运行时间单调增 ⇒ **已跑到 70% 活性以下时仍报"还剩满寿命"**。
- 数值反证：取 `k=1e-4 [1/h]`、`t=10000 h` → `act=0.368`，`LN(1/act)=1.0`；代码给 RUL=(1.0+0.357)/1e-4=**13567 h**，真值 =(0.357−1.0)/1e-4=**−6426 h（已耗尽）**。偏差 1.36×10⁴ h ≈ 1.55 年。
- 边界反证：`act` 恰好 = 0.7 时，正确 RUL = 0，代码给 `2×0.357/k`＝**满寿命**。寿命终点判据被整体消掉。
- 修法：`:91` 改 `(rLnInv07 - LN(1.0 / rActivity)) / rK`；`:8` 同步改注释。

### 3.2 MAJOR（11）

| # | 文件:行 | 项 | 问题（判定式） | 修法 |
|---|---|---|---|---|
| M1 | `FC_DL_ComponentRulEstimate.st:51, :75` | 4 非有限 | `ABS(rSlopeRaw) > 1.0E15` 对 NaN 恒 FALSE。`rHealthNow=NaN` ⇒ `:50` 斜率 NaN ⇒ `:57` `ABS(NaN)<dead` FALSE ⇒ `:66` `NaN<=0` FALSE ⇒ `:74` RUL NaN ⇒ `:75` FALSE ⇒ `:80` FALSE ⇒ `rRulHours=NaN`，末行 `bValid:=TRUE` | 按 R508 补 `(x = x)` 半边，NaN 时置码 4 |
| M2 | `FC_DL_CoagDoseFromJarTest.st:45` | 4 非有限 | 同式 NaN 盲；且**全文无任何输入有限性闸**（5 个 REAL 入参直入 `:42-43`）→ `rDoseLh=NaN` + `bValid=TRUE` | 段 1 前插 `(x = x)` 输入闸 |
| M3 | `FC_DL_NtuCoagDoseAdj.st:59` | 4 非有限 | 同式 NaN 盲 → `:68` `rDoseOut` 落 NaN，`:70` `bValid:=TRUE` | 同上 |
| M4 | `FC_DL_SettleVelocityCalc.st:59` | 4 非有限 | 同式 NaN 盲 → `:66` `rVsMmS := NaN*1000`，`:67` `NaN>2` FALSE 跳过 Re 域闸，`:73` `bValid:=TRUE` | 同上 |
| M5 | `FC_DL_DemisterVelocityChk.st:54, :73` | 4 非有限 | 同式 NaN 盲 → `:61` `rVelMs=NaN`、`:81` `rVcritMs=NaN`，`:84` 夹带判据 `NaN>NaN` FALSE → **报"不夹带"**，`:85` `bValid:=TRUE` | 同上 |
| M6 | `FC_DL_CakeSolidsCalc.st:71` | 5/6 公式自证 | `rCakeTsPct := rFeedTsPct*rFeedM3h/rCakeM3h`(:56) 代回 `rCakeSolid := rCakeTsPct*rCakeM3h`(:70) ⇒ `rCakeSolid ≡ rFeedSolid` 代数恒等 ⇒ `:71` `rRecoveryRaw ≡ 100.0`。**回收率输出恒 100%，不含任何信息** | 回收率须由独立的滤液含固率（或实测出泥量）计算；否则删该输出并在头注释声明 |
| M7 | `FC_DL_DewaterMassBalance.st:70` | 5/6 公式自证 | `rCakeM3h := rFeedM3h*rFeedTsPct/rCakeTsPct`(:51) 代回 `:70` ⇒ 恒 100%。与 M6 同型（同族 2 件 → 系统性） | 同上 |
| M8 | `FC_DL_FlareFlowSizing.st:92` | 7 死输出 | `:70` 设计流速 `= rVelLimitMs*0.7`；`:80` 管径由该流速反算；`:88` 回算 `rVelMs ≡ 0.7*rVelLimitMs` **代数恒等** ⇒ `:92` `bOver := rVelMs > rVelLimitMs` **结构上永远 FALSE**。头注释 `:8` 称"用于监看是否超限"——该监看器是哑的 | 越限判据应比较实测气量算出的流速与限值（不经 0.7 折算），或对 `rDiaM` 取标准管径后回算 |
| M9 | `FB_DL_AnaerobDigesterLoadCtrl.st:257, :382` | 4 非有限 | 码 46 专为"关键入参非有限"而设，但其判据仍是 `ABS(rVfaMgL) > DL_ADC_FIN`（NaN 盲）。VFA=NaN ⇒ 码46 不报 ⇒ `:190` `_rRatio=NaN` ⇒ `:196` `_bRatioHigh=FALSE` ⇒ `:206` `_bViolation=FALSE` ⇒ **消化罐在 VFA 仪表死值时按满负荷进料且不报警**。讽刺点：头注释 `:46-48` 作者已识破"ABS(base)>FIN 是死谓词"并用 `_bBaseOk` 修了基准一路，却漏了码 46 本身 | 码 46 补 `(x = x)` 半边；`_bRatioOk` 增 `(_rVfaCl = _rVfaCl)` |
| M10 | `FB_DL_AnaerobDigesterLoadCtrl.st:176-179 + 段6 :378-386` | 6/7 漏复检 | 段 6 只复检码 45、46，**不复检码 42**（流量上限）。运行中 `rFeedMaxM3h→0` ⇒ `:178` `_rFeedMax=0` ⇒ `:194` `_rFloorM3h=0` ⇒ `:401` 走 ELSE ⇒ `_rLoadPct=0` ⇒ 但 `_rFeedLimit` 保持旧值、`:438` `rFeedOutM3h := _rFeedCl`（原始实测）⇒ **限流器静默退化为直通，无任何故障码** | 段 6 增码 42 复检分支，与 45/46 同构 |
| M11 | `FB_DL_ScrubberReagentDoseSeq.st:160-170` | 4 非有限 | pH 净化闸写得很完整（`ABS>FIN` **或** `<0` **或** `>14`），但 **NaN 对三者全 FALSE** ⇒ `_bPhInvalid=FALSE` ⇒ `:172` `_rErr=NaN` ⇒ PI 三项 NaN ⇒ 泵设定 NaN，码 35 不报。**该件正好证明"值域闸补不了 NaN 盲"**，是 §七 锚点的最强论据 | 闸首增 `(_rPhCl = _rPhCl)` 项 |
| M12 | `FB_DL_ScrewPressDewaterSeq.st`（码 25 残留判据，段 2 `ELSIF _iErrLatch = 25 THEN _bFaultCondNow := (ABS(rCakeTsPct) > DL_SPR_FIN)`） | 4/7 死防御 | 抬码侧与残留侧用同一 NaN 盲式 ⇒ 含固率 NaN 时码 25 既抬不起也退不掉，泥饼干度比较 `_rCakeTsCl` 落 NaN 后所有比较为 FALSE，干度不达标也不判 | 同上；并补 `_rCakeTsCl` 自反闸 |

### 3.3 MINOR（9）

| # | 文件:行 | 项 | 问题 |
|---|---|---|---|
| m1 | `FC_DL_CakeSolidsCalc.st:63-68` | 11 口径分裂 | 码 4 分支 `bValid := TRUE`，而码 1/2/3/5 分支 `bValid` 保持 FALSE。同一 iErrCode 空间内两种有效性口径，调用方无法只看 bValid |
| m2 | `FC_DL_DemisterVelocityChk.st:65-70` | 11 口径分裂 | 码 3 分支 `bValid := TRUE` 且 `rVcritMs=0`；但与 `:84` 夹带判据脱钩：此时 `rVelMs > 0 = rVcritMs` 成立却 `bCarryOver=FALSE`，两出口互相矛盾（同一病型 2 件 → 系统性） |
| m3 | `FC_DL_DemisterVelocityChk.st:78-82` | 2 域闸缺 | `rKFactor` 无任何域闸（段 1 只闸 rRhoG/rAreaM2）；负 KFactor ⇒ `:72` SQRT 后为负 ⇒ 被 `:78-79` 夹到 0，`rVcritMs=0` 却 `bValid=TRUE` |
| m4 | `FC_DL_NtuCoagDoseAdj.st:56-69` | 7 退化 | `rDoseBase = 0` ⇒ `rDoseHi = 0` ⇒ 恒落 `:63` 分支输出 0，比例修正被无声吞掉（对比 CoagDoseFromJarTest:33 对 0 分母是显式置码） |
| m5 | `FC_DL_CoagDoseFromJarTest.st:33 + :51` | 2 闸不严 | 闸用 `ABS(rStockGL)`，负母液浓度可通过；随后 `:43` 得负流量 ⇒ `:51-53` 归零，但 `bValid:=TRUE`、`iErrCode=0`，无码说明 |
| m6 | `FC_DL_CatalystActivityDecay.st:87` | 7 死防御 | `rActivity` 已在 `:72-78` 钳到 `[1e-4, 1]`，`:87` `IF rActivity <= 0.0` **永假不可达**（R90 型永假防御） |
| m7 | `FC_DL_CatalystActivityDecay.st:44` | 7 默认值方向 | 段 0 把 `rActivity` 预置为 `rActFloor = 1e-4`；码 1/3/4 提前返回时输出"活性 0.01%"，读值方若忽略 bValid 会当作催化剂报废（假告警方向，属 fail-safe 但口径危险） |
| m8 | `FC_DL_PmScheduleNext.st:74` | 2 溢出 | `DINT_TO_INT(diDiffSec / diSecPerDay)` 无上限闸；逾期 > 32767 d 时静默回绕为负。头注释 `:9` 自述域 3650 d，但只在入参侧闸、未在结果侧闸 |
| m9 | `FC_DL_CakeSolidsCalc.st:51` vs `FC_DL_DewaterMassBalance.st:42` | 5 口径不一致 | 同一物料平衡族：前者要求 `rCakeM3h <= rFeedM3h`（体积守恒预检），后者要求 `rCakeTsPct > rFeedTsPct`（含固率递增）。两件互为逆运算却各自只闸一半，交叉调用时会出现"一件接受、另一件拒收"的同一工况 |

> 另：`FB_DL_AnaerobDigesterLoadCtrl.st:407-428` 负荷等级 0~10 级中 0→1 级为 5% 带宽、其余 10% 带宽，与头注释 `:21`「每 10% 限值一级」措辞略不符（MINOR，未计入上表）。
> 另：`FB_DL_ScrewPressDewaterSeq.st` `_diHighMs := (_diPressMs / 100) * 30` 整数先除，`_diPressMs=199` 得 30 ms（真值 59.7），已在注释声明属刻意避免 DINT 溢出（MINOR，未计入上表）。

---

## 四、三道去重结果

- **道 1（名称精确）**：40 名 × registry 1530 名 → **命中 0**。
- **道 2（签名/词根指纹）**：40 件按 `_tools/r82_fp_rebuild.py` 同一算法重算 `sig`/`api`，与 `sig_groups`(60 组) / `api_groups`(46 组) / `components`(1530) 比对 → **精确命中 0**，**疑似同构组 0**。
  - **近邻（同族不同指纹）3 组，均判有效变体，见 §五**。
  - 抽取核对：`FC_DL_MtbfCalc`→tokens=[mtbf]、`FC_DL_SviCalc`→[svi]、`FC_DL_VfaAlkalinityRatio`→[vfa,alkalinity]、`FC_DL_FlocDilutionRatio`→[floc,dilution]、`FC_DL_PackedBedHtu`→[packed,bed,htu]、`FC_DL_CentrateTurbidityIdx`→[centrate,turbidity]、`FC_DL_CatalysActivityDecay`→[activity,catalyst,decay] 全部为**全库 0 邻居**，族 E（厌氧沼气 7 件）与浊度/水质域在全库检索中命中数均为 **0** —— 本轮确实是空白域，无重复动机。
- **R528 合规自检（道 2 未降级，需当场举证）**：`_dedup_fingerprints.json` 本轮 `count=1530`，与 registry 名数 1530 **1:1 相等**（覆盖 100% ≥ 0.9 阈值），`components` 键即组件名、值含 `kind/sig/api/in_n/out_n/sm/lines/file` 可反查 → 满足 R528 开跑前置条件，**本轮道 2 未降级**。旧库 84 条（5.6%，键值不可映射）的问题已由 `_tools/r82_fp_rebuild.py` 重建消除。
- **道 3（语义同义）**：对 5 组最近邻做了**正文级**比对（读新件正文 + 邻件正文），**判拒收 0**，判有效变体 5（见 §五）。
- **覆盖度声明（诚实边界）**：道 3 只对 5 组最近邻落了正文比对；其余 35 件仅过名/指纹层（该层 0 命中且词根倒排近邻 ≤1 token 巧合），**未做正文级语义判重**。若总监要求全量道 3，需追加约 40 次正文对读。

---

## 五、防误杀复核（判为有效变体 5 件）

1. **`FC_DL_CoagDoseFromJarTest` vs `FC_DL_CoagulantDoseCalc`（既有）** → 有效变体。
   邻件是**浊度前馈**：入 `rTurbidity_Ntu/rTurbidityRef/rDoseRef_mgL`，出 `rDose_mgL` + `rDoseRate_kgh`；新件是**烧杯结果直接反算**：入外部已定 `rJarDoseMgL` + `rStockGL`，出 `rDoseLh`（**体积流量 L/h**）。新增工程价值：母液浓度 `g/L → L/h` 的换算链，正是计量泵需要而邻件不给的量（邻件只到 kg/h）。删掉新件，现场拿到的是质量流量，还得自己再除浓度——多一步且易错。
2. **`FC_DL_NtuCoagDoseAdj` vs `FC_DL_CoagulantDoseCalc` / `FB_DL_WaterChlorineDoseTrim`** → 有效变体。
   新件是**沉后浊度反馈的比例微调**（入 `rNtuOut/rNtuSp/rDoseBase/rKp/rStepMax`，双限幅：单步步长 + 总量 2×基准）；CoagulantDoseCalc 是开环前馈；ChlorineDoseTrim 是**加氯**而非混凝（不同药剂、不同反应机理）。反馈闭环与前馈在控制结构上是不同阶，不可互替。
3. **`FC_DL_ComponentRulEstimate` vs `FB_DL_RulEstimator`（既有）** → 有效变体，**但列入存疑请总监复议**。
   差异：邻件 C4（284 行，4 特征加权合成 + 滑窗最小二乘 + 残差置信带 + 三相状态机 + UDINT 拍数/小时双口径）；新件 C2（89 行，**两点斜率**、无状态、无窗、无置信带、无实例）。**删除试验**：邻件最少需 16 个采样点（`DL_RUL_MIN`）才有输出，且必须挂在循环 FB 上下文；新件两个采样立即可算，可在纯 FC 公式链里内联。故不可互替。
   **存疑理由**：两者一句话功能都是"估剩余寿命"，若只按功能标签判即是同义变体。按防误杀规则（同族不同阶不得拒收）我判放行，但把判断权交给总监。
4. **`FC_DL_CakeSolidsCalc` vs `FC_DL_DewaterMassBalance`（同轮同族 B）** → 有效变体，**但强烈建议总监裁**。
   二者是同一 3 变量物料平衡的**互逆求解方向**：前者由（进泥流量、进泥含固率、出泥体积）求含固率；后者由（进泥流量、进泥含固率、泥饼含固率）求泥饼量与滤液量。现场工况确实分两支：有泥饼流量计时用前者，无泥饼流量计只能实验室测含固率时用后者。**但**：两者 `rRecoveryPct` 都是代数恒 100% 的死输出（M6/M7），且域闸口径不一致（m9）。若总监认为"同一平衡写两遍不值"，可合并为一件带 `bSolveForCake` 的开关件——我不越权，只报事实。
5. **`FC_DL_FlocDilutionRatio` / `FC_DL_CentrateTurbidityIdx` / `FC_DL_PackedBedHtu` / `FC_DL_VfaAlkalinityRatio` / `FC_DL_MtbfCalc` / `FC_DL_SviCalc`** → 有效变体（新颖域）。
   全库词根倒排对这 6 件的核心词根命中数为 **0**（`floc/dilution`、`centrate/turbidity`、`packed/bed/htu`、`vfa/alkalinity`、`mtbf`、`svi` 均无既有件），模板可证无同义邻件。

> **未复核（缺证据，不下结论）**：`FC_DL_LubeIntervalCalc` vs `FC_DL_DrainIntervalCalc`、`FC_DL_OilChangeInterval` vs `FC_DL_DrainIntervalCalc`+`FB_DL_OilLevelWatch`、`FC_DL_SpareReorderPoint` vs `FB_DL_TankFarmInventory`/`FC_DL_StocktakeVarianceCalc`、`FC_DL_PmScheduleNext` vs `FC_DL_IntervalGapCalc`、`FC_DL_SludgeBlanketLevel` vs `FB_DL_TankBlanketPrCtrl` —— 这 5 组词根上各命中 1 token，**我未读邻件正文**，不敢断言。按"SettleVelocity vs SettleTime"的先例，同 token 不同量（速度 vs 时间；润滑周期 vs 排凝周期）通常是有效变体，但**须下轮补读正文**。这是本轮道 3 最大残留风险。

---

## 六、最高价值的 3 条发现（对后人最危险）

### 6.1 `ABS(x) > 1.0E15` 是全库统一的"半条非有限判据"，35/40 件在用 —— 这是本轮唯一真正的系统性缺陷
- 机理：IEEE 754 下 NaN 的一切比较返回 FALSE，故 `ABS(NaN) > 1.0E15` ≡ FALSE，`NaN < 0` ≡ FALSE。这个写法**只能挡 ±Inf，永远挡不住 NaN**。
- **不是新问题，是范式回归**：演进日志已有三轮结论 —— `R482`（统一写 `ABS(x)>FIN`）→ `R483`（自反式挡 NaN 不挡 Inf、列入告警）→ `R508`（**定稿为双条件 `(x = x) AND (ABS(x) <= R_MAX)`，单条件覆盖 100% 的记录即出自此条**）。两条半式互补：`ABS>FIN` 挡 Inf，`(x = x)` 挡 NaN，**缺任一半即漏一类**。本轮 35 件只写了 ABS 半边、丢掉了自反半边，等于把 R508 的定稿退回 R482 以前的半成品。
- 分布（机检）：40 件里 35 件出现该式，且都被写在注释里叫"非有限判据"。库内现存唯一正确范式是 `FB_DL_RulEstimator.st:199-201`（`(fFeat1 = fFeat1) AND ((fFeat1-fFeat1) = (fFeat1-fFeat1))`，NaN 与 Inf 双覆盖）—— 库里的正确写法就在隔壁，本轮 36 件全没沿用。
- 最刺眼的证据：`FB_DL_ScrubberReagentDoseSeq.st:160-170` 把「ABS>FIN **或** <0 **或** >14」三重闸都写全了，**NaN 依然全 FALSE 穿过去**。即值域闸在原理上补不了这个洞。
- 危害链（实证 8 件见 §3.2）：NaN 入参 → 判据沉默 → 输出 NaN 或"一切正常" → 执行器拿到 NaN 或不该给的指令。

### 6.2 三处"结构上永不成立"的死输出 —— 比 NaN 更隐蔽，因为不依赖坏输入
- `FC_DL_FlareFlowSizing.st:92`：`bOver` 恒 FALSE（管径由 `0.7×限值` 反算，回算流速必然 `≡0.7×限值`）。**超速监视器是哑的，且无需任何异常输入**。
- `FC_DL_CakeSolidsCalc.st:71` / `FC_DL_DewaterMassBalance.st:70`：`rRecoveryPct` 代数恒 100%（M6/M7）。**"固体回收率"这个输出从诞生起就没算过**。
- 共同点：都通过"公式自证"，单测用一个正常样例也会得到 100% / FALSE 而看不出异常，只有做**代数推导**才能发现。故列为本轮最危险项。

### 6.3 `FC_DL_CatalystActivityDecay.st:91` 的加号
见 B2。这条之所以危险，是因为头注释 `:8` 把错公式**写成规格**，任何"代码符合注释"的复核方式都会判它正确；只有从物理（`act` 单调递减）反推才能抓住。它与上两条同源：**本轮缺陷的共同形态是"自洽的错"**。

---

## 七、机检锚点建议（交编译验证工程师，写入 `dl_gate.py`）

按"重复出现 ≥2 次"筛选，5 条按收益排序：

1. **`ANCHOR_FIN_HALF`**（最高优先，35/40 件命中）
   正则 `ABS\s*\([^)]*\)\s*>\s*1\.0E15` 或引用了名含 `_FIN` 的常量，且同文件内**无** `\(X\s*=\s*X\)` 自反式 → 报"非有限闸只有 ABS 半边，NaN 盲"。规范形态以 **R508 定稿的双条件** `(x = x) AND (ABS(x) <= R_MAX)` 为准（见 `FB_DL_RulEstimator.st:199-201` 的既存正确写法）。注意：**不是禁 ABS 式，而是禁单条件**；R483 的白名单口径已被 R508 取代，本锚点按 R508 判。
2. **`ANCHOR_DEAD_SELF_EVIDENT`**（2 件，M6/M7）
   检测"`Y := A*B/C`" 之后出现 "`R := Y*C/(A*B)`" 或等价 `X*C/D` 回代形态 → 报"输出代数恒等，无信息量"。
3. **`ANCHOR_DEAD_TAUTOLOGY`**（1 件强命中，建议仍上线，因同类极易复发）
   检测"比较阈值由被比较量自身经同一系数推导"，如 `V := L*0.7` → `Vr := f(V)` → `B := Vr > L`。实现可用轻量符号化：跟踪常量系数的传播。
4. **`ANCHOR_CODE_VALID_SPLIT`**（2 件，m1/m2）
   同一 `iErrCode` 常量集合内，统计 `bValid := TRUE` 与 `bValid := FALSE/保持` 的分支数；两种都出现即报"码表有效性口径分裂"。
5. **`ANCHOR_DEAD_GUARD_AFTER_CLAMP`**（1 件，m6；同类在历史 R90 已出现过，值得常备）
   同一变量在 N 行前被 `IF ... THEN X := floor ...` 钳位后，再出现 `IF X <= floor` 型判据 → 报"钳位后永假防御"。

**缺陷逃逸分析（月度口径，本月首测）**：本轮抽检 14 件中，`ANCHOR_FIN_HALF` 一类占 MAJOR 的 67%（8/12）。上一轮"非有限闸"也是高频漏项 —— 说明**人工阅读对这一类是低效的**（写法看上去完全像防御代码），必须上机检。若锚点 1 落地，预期可把非有限类逃逸率压到接近 0。

---

## 八、挂账清单（按下轮优先级）

| 优先级 | 事项 | 涉及件 |
|---|---|---|
| P0 | B1/B2 就地修（安全侧 + 公式错，行为变更需总监签字；本轮未改任何 `.st`） | CoagDoseJarTestSeq、CatalystActivityDecay |
| P0 | 全轮 35 件的非有限判据按 **R508 双条件**补全 `(x = x)` 半边（建议一次性扫替，勿逐件手改） | 35 件 |
| P1 | M6/M7 回收率死输出：补滤液含固率输入或删输出 | CakeSolidsCalc、DewaterMassBalance |
| P1 | M8 `bOver` 判据重设计 | FlareFlowSizing |
| P1 | M9/M10 厌氧控制：码46 自反化 + 码42 运行复检 | AnaerobDigesterLoadCtrl |
| P2 | 道 3 补做 5 组正文比对（§五末未复核清单） | 5 组 |
| P2 | m9 物料平衡族域闸口径统一 | 族 B |
| P3 | m5/m7/m8 等口径瑕疵随下次返修带走 | 见 §3.3 |

---

## 九、本轮我未做的事（边界声明）

- 未改任何 `.st` 文件；未动 `INDEX_REGISTRY.json` / JSONL；未参与组件规划。
- 未对未抽检的 26 件下任何结论。
- 未为让报告好看而降/升分级：M6/M7/m1/m2 这类"能跑但口径错"的项一律留在原位，不并入 MAJOR 充数。
