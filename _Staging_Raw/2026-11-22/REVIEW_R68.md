# REVIEW_R68 — 构建轮五抽终审报告（5+1 抽 + 定向全量扫查）

> 轮次：R68 终审（第五阶段）｜日期：2026-11-22｜主控直跑（R335）｜游标：R328 → 本轮新规 R329 起
> 对象：R68 构建轮 16 件（registry source=r68-plan，v2.60.0，total_components=1179）
> 方法：R279 两段式——先按模板清单定向扫查抽件，再对剩余 11 件做同模板快扫（抽检不是免责，R193）
> 就地修：**9 件 10 处**（严重级），全部升 v1.0.1 并重跑 `dl_gate --file` 单文件验证（9/9 PASS）

## 1. 抽件清单与结论

| # | 组件 | 子库 | 7 红线 | 逻辑缺陷 | 终审结论 |
|---|---|---|---|---|---|
| 1 | FB_DL_InterlockBypassAudit | DL_Base | 7/7 ✓ | 1 中（bBypassOn 泄漏）/ 1 轻 | 中缺陷挂账，不修 |
| 2 | FB_DL_FlowMeterKFactorDrift | DL_Device | 7/7 ✓ | **1 严重**（eFault 不可达 → 锁存永不可解）+ 1 中（eFailure 声明未实现） | 严重就地修 → v1.0.1 |
| 3 | FB_DL_RotaryAirlockCtrl | DL_Device | 7/7 ✓ | **1 严重**（bCfgLatch 全文件零清零）+ 2 轻 | 严重就地修 → v1.0.1 |
| 4 | FB_DL_StretchWrapSeq | DL_Process | 7/7 ✓ | **1 严重**（总圈计 255 闸 → 合法配方死锁）+ 1 中（eCut 无失败出口） | 严重就地修 → v1.0.1 |
| 5 | FB_DL_AxisPowerOnSelfTest | DL_Motion | 7/7 ✓ | **1 严重**（bCfgLatch 零清零 → 自检永久不可重测） | 严重就地修 → v1.0.1 |
| 6 | FB_DL_TruckScaleSeq（收口件复核） | DL_Process | 7/7 ✓ | **1 严重**（同型锁存不可解）**1 严重**（超时重测每拍清窗 → 判稳永不可达） | 两处就地修 → v1.0.1 |

计数：**抽件严重 6 处 / 中 3 项 / 轻 3 项 / 纯 PASS 0 件**（6 件全部至少 1 项缺陷，无一纯 PASS）。
扩面后全批合计：**严重 9 处（9 件、10 个修点）/ 中 4 项 / 轻 3 项 → 就地修 9 件、挂账 R69 共 7 项**。

## 2. 严重缺陷详述与修法（就地修，均已机检）

### ① 组态锁存解除路径不可达（同型缺陷，定向扫查命中 **8 件**）
- **现象**：组态域闸置 `bCfgLatch/bFaultLatch := TRUE`，但清零行只写在 `eFault` 相分支；而置锁存后状态机**不迁相**（只回 `eIdle` / 驻留），`eFault` 相不可达 → 锁存一次性永不可解。
- **后果（安全侧）**：一次瞬时组态错（如 `tStepTimeout=0`、`nChannelCount=9`、称重值一拍 NaN）即让该组件的监视 / 保护功能**永久失效直至 PLC 重启**，且 `bError=TRUE + uErrorId` 常驻不可复位 → 违反终审两式①（锁存解除可达）。
- **命中件**：ClockDriftMonitor、CameraHealthWatch、VisionLightBank、FlowMeterKFactorDrift、RotaryAirlockCtrl、TwoSpeedMotor、TruckScaleSeq、AxisPowerOnSelfTest（**8 件**：抽件 5 件 + 扩面 3 件；其中 RotaryAirlockCtrl / TwoSpeedMotor / AxisPowerOnSelfTest 为「全文件零清零」型）。
- **修法（统一最小侵入）**：在组态闸置锁存块之后插入 4 行解除式——
  `IF fbTrigReset.Q AND (NOT 各非法条件) THEN bCfgLatch := FALSE; uErrorId := 16#0000_0000; END_IF`
  与置位条件互斥（置位要求组态非法、解除要求组态已改对），**无需**新增相迁移、**不改**任何对外引脚、**不改**码位表。
- **自证**：解除式可满足（操作员改对组态 + 给复位沿）；置位/解除同扫互斥不振荡。

### ② TruckScaleSeq 超时重测每拍清窗（超时同源挂死）
- **现象**：`tonStableTo.Q` 在 `IN` 保持期间恒真，原实现每拍 `bStatClear := TRUE` → 统计窗被扫描周期级反复清零。
- **后果**：窗永不填满 → 判稳永不可达 → 该车过磅只能靠「开走」触发防作弊作废；`tStableTimeout` 的「重测」语义完全失效（超时同源挂死）。
- **修法**：新增内部单拍标志 `bToutPulse`，一次超时只清一次窗；离开稳定相即撤销，再次进相可再清一次。

### ③ StretchWrapSeq 总圈计数上限死路径
- **现象**：计数闸用单段上界 `DL_WR_TURNS_MAX=255` 作**总数**闸，而配方域为底/顶各 1..255。
- **后果**：合法配方（如底 200 + 顶 100 = 300 圈）在 255 圈停计 → `eTop` 相永不可达、转盘驱动常励磁（死路径 + 执行器长时间通电）。
- **修法**：新增常量 `DL_WR_TOTAL_MAX := 510`（= 2 × 单段上界）作总数闸，配方域与对外契约不变。

## 3. 收口期 3 处就地修复核（确认有效，不重复修）

| 收口修项 | 复核结论 |
|---|---|
| ① InterlockBypassAudit / ClockDriftMonitor / TruckScaleSeq 三件 METHOD 块补 `END_METHOD` | ✓ 三处 `END_METHOD` 在位；`dl_gate` 结构栈 0 BLOCK（METHOD 未闭合会被构造栈抓到） |
| ② TruckScaleSeq 段 7 补 `fTareLatched/fGrossLatched` 槽镜像输出 | ✓ 段 7 第 2/3 行镜像直出，与 `fTareInt/fGrossInt` 同源；写台账后双槽已清零，0 语义与注释一致 |
| ③（本轮新增）Build 期 `DolMotor METHOD` 先例引用失实 | 记录：先例不成立，已由头注释不再引用；不视为既有债（仅编码期口述，无文件留痕） |

## 4. 中/轻挂账（R69 处理，本轮不修）

| # | 件 | 级 | 缺陷 | R69 动作 |
|---|---|---|---|---|
| M1 | FB_DL_InterlockBypassAudit | 中 | 组态故障打断旁路后 `bBypassOn` 残留 TRUE（TON.IN 常真）→ 修复后首次旁路立即到期（04B1），旁路功能退化（安全侧，联锁仍生效） | 迁相时同步 `bBypassOn := FALSE` |
| M2 | FB_DL_StretchWrapSeq | 中 | `eCut` 相无失败出口：`bCutDone` 永不到时永久驻留、`bCutOut` 常励磁、重试计数饱和后无中止 | 需产品决策（新增切膜失败出口 + 码位），R69 立项 |
| M3 | FB_DL_FlowMeterKFactorDrift | 中 | 头注释「组态故障 → eFailure」未实现（实现仅保持上一分级） | 二选一：补 `eHealth := eFailure` 或改注释 |
| M4 | FB_DL_TruckScaleSeq | 中 | 组态闸把 `fWeight<>fWeight`（运行时信号失效）并入 `bCfgBad` 并锁存，与边界披露 5「不另设码位、由超时兜底」矛盾 | 拆为信号闸 + 保持，不锁存 |
| L1 | FB_DL_InterlockBypassAudit | 轻 | 信息码 04B1/04B2 置位后无回落路径（长期常驻） | 随码位口径统一处理 |
| L2 | FB_DL_RotaryAirlockCtrl | 轻 | 段 9 `bJogRevOut` 取上拍 `bRunOut` 反相硬闸 → 反转首拍延后一拍 | 出口改为同拍派生 |
| L3 | FB_DL_StretchWrapSeq | 轻 | `bPreClampOut` 仅在 `ePreClamp` 相有效，底/顶圈段压膜释放（语义待确认） | 确认工艺后定 |

## 5. 机检与三向一致

- 构建期机检：`_gate_R68.json` 16/16 PASS、MAJOR 0、BLOCK 0（WARN 全为跨文件类型未识别，属机检器类型库已知缺口）。
- 终审就地修后单文件复检：**9/9 PASS**（MAJOR 0 / BLOCK 0），行数变化已同步 registry `line_count`。
- registry：9 件 `version` 1.0.0 → **1.0.1**，`function_tags` 追加 `r68-postfix`；`total_components` 仍 1,179（无新增/删除），counts 不变（sum=1179 ✓）。
- 结论：三向（registry ∪ 文件树 ∪ ROADMAP 勾选）本轮无新增差额；v1.0.1 属 PATCH，不触发子库 MAJOR/MINOR。

## 6. 本轮新规（10 条，R347~R356，两账本各 5 条）

> **编号基线订正（R355）**：任务书给定游标 R328 / 新规自 R329 起，但全库 grep 实测最大规则号为 **R346**（R55 期两账本单线推进已用 R329~R346），按「实测 +1」取号 → 本轮新规 **R347~R356**，任务书 R328 仅作交叉校验。

- **PLC 账本（R347~R351）**：R347 组态锁存解除可达性二选一（可判定红线）｜R348 `TON.Q` 常真驱动的清窗/复位必须单拍化｜R349 饱和闸常量与累积量同口径｜R350 头注分级出口与动作动词逐句对账｜R351 ENUM 相三证（迁入/迁出/可退出）。
- **总监账本（R352~R356）**：R352 严重级第四支「不可恢复型」｜R353 抽件同型命中 ≥3 即扩为族全量定向扫查｜R354 收口修件复验不豁免｜R355 编号基线以实测为准｜R356 就地修 ≥8 件按族全量返修轮记账（下轮配额 −20%）。

## 7. 下轮终审模板清单（滚动，供 R69 沿用）

1. 锁存变量全名扫查：`b*Latch` 的 `set` 与 `clr` 计数 + 清零所在相是否可达（R329/R330）。
2. 相迁移闸位复检：置锁存/置故障的每一处是否伴随迁相，或另有可达解除式。
3. `TON.Q` / `R_TRIG.Q` 驱动的「清窗 / 复位 / 计数」动作是否单拍化（R331）。
4. 饱和闸常量与累积量上界一致性（含「分量 vs 累积」混用）（R332）。
5. 头注释语义段逐句对照实现（分级 / 出口 / 码位三类）（R333）。
6. 同拍竞态：解除沿 vs 超时沿、结果沿 vs 超时沿的优先级声明与实现一致。
7. 中轻挂账闭环：上台账 → 下轮验收 → 勾销，禁止无声消失。

*R68 终审 ｜ 2026-11-22 ｜ 道莅工控代码库产品总监（主控直跑）*
