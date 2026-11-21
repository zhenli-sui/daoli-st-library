# REVIEW_R62 — R62 终审抽样报告（五抽 · 两段式）

> 时间：2026-11-21 15:42~16:00 ｜ 终审人：道莅产品总监（主控直跑，R335）
> 范围：11 新件抽 4 件语义终审 + 5 件返修逐条对指令复核 ｜ **本轮零改码（R333）**，全部挂 R63 首位
> 机检基线：16/16 PASS，fail=0（机检只证文本红线，**不证数学正确性**，本轮两严重项均逃过机检 → 立 R303）

---

## 一、抽样清单与选中理由（R287 预登记）

| # | 组件 | 子库 | 选中理由 | 预期缺陷家族 | 命中 |
|---|---|---|---|---|---|
| S1 | `FB_DL_BiquadFilter` | DL_Algo | 本轮唯一「高」复杂度 + 含**数学判据**（稳定域三角） | 判据充分性 / 状态回写量纲 | 1 严重 + 1 轻 |
| S2 | `FB_DL_VfdDcBusRipple` | DL_Device | 电气监视类 + 入参**兼作除子**（除零高危） | 除零结构早退 / 粒度口径 | 1 严重 + 1 轻 |
| S3 | `FB_DL_IonFanInterlock` | DL_Device | 安全联锁类 + 三出口（许可/报警/故障） | 失能相出口屏蔽 | 1 中 + 1 轻 |
| S4 | `FC_DL_PercentileRank` | DL_MathData | 委托件（R61-D5 同族）+ 逆运算口径 | 委托双写复发 / 死变量 | 0 严重（1 轻观察） |

> 返修复核 5 件（不抽，逐条对指令）：`RailPowerSequence` v1.0.2 / `TurretToolSelect` v1.0.1 / `SensorPairPlausibility` v1.0.1 / `WeightedPercentile` v1.0.1 / `LineClearanceVerify` v1.0.1。

---

## 二、缺陷台账（7 处 × 4 件）

### R62-D1【严重】`FB_DL_VfdDcBusRipple` 组态非法不早退，除子直穿

- **现象**：段 3 判 `fUdNom ≤ 0 / 非有限` 只置 `_bCfgBad`，**无 RETURN**；段 8 仍执行 `_fPct := (_fAvg / fUdNom) * 100` 并以此驱动三路迟滞判据。
- **矛盾点**：头注释边界三原文「fUdNom 既作除子又作基准，故 ≤ 0 或非有限一律判组态故障并置 bValid = FALSE（**除零防护**）」——只做了标志，没做防护。
- **向量**：`fUdNom = 0.0`、`fUdMeas = 500`、`nWinLen = 4` → 期望 0710 + `bValid=FALSE`；实跑路径先执行 `500/0`。CODESYS x86 默认开除零检查即抛运行期异常（任务级故障），TwinCAT 得 ±Inf 后 `Inf < 85` 为 FALSE、`Inf > 115` 为 TRUE → **过压误报**，均为错。
- **违反**：红线 5（强制防除零）；且属「声明-实现不一致」。
- **修法（R63）**：段 3 末尾 `IF _bCfgBad THEN` 置出口三件套 + `RETURN`（结构早退），或把段 8 包进 `IF NOT _bCfgBad`；二者取「早退」与同族 `FC_` 件口径一致。

### R62-D2【严重】`FB_DL_BiquadFilter` 三角稳定判据数学不成立

- **现象**：段 3 `_bStable := (ABS(fA1) < 2) AND (ABS(fA2) < 1) AND (ABS(fA2 - fA1) < 1)`。
- **事实**：二阶极点落单位圆内的充要条件（Jury）为 `|a2| < 1` ∧ `1 + a1 + a2 > 0` ∧ `1 − a1 + a2 > 0`，即 `a2 > |a1| − 1` 且 `a2 < 1`。实现用的 `|a2 − a1| < 1` **不是**该三角形的边，只覆盖了上边界与一条斜边，**下边界 `a2 > |a1| − 1` 缺失**。
- **反例（必须进 V2b 向量）**：`a1 = −1.9, a2 = −0.95` → 三条全过（`|a2−a1| = 0.95 < 1`）；极点为 `z² − 1.9z − 0.95` 的根 → `z1 = 2.3111`（圆外）。Jury 校验 `1 + a1 + a2 = −1.85 < 0` 判不稳定，与实现结论相反。
- **后果**：发散系数被放行，输出被段 8 钳到 `fOutMax` 后 `bValid := TRUE`、`eErr` 仅 3738（信息级「本拍被钳」）→ **错值被标为可用**，头注释「绝不外泄发散值」的安全断言实际失效（值不外泄，但状态不报警）。
- **验收缺口**：V2 只测 `a1 = 2.5`（被 `|a1| < 2` 拦下），V3 只测 NaN，**恰好绕开失效区**。
- **修法（R63）**：判据换为 `ABS(fA2) < 1 AND (1 + fA1 + fA2) > 0 AND (1 - fA1 + fA2) > 0`，代码 ID 3735 语义与头注释同步改写；补 V2b（上反例，判 3735 + 冻结）与 V2c（`a1=0, a2=-0.99` 合法稳定，须放行，防过度收紧）。

### R62-D3【中】`FB_DL_IonFanInterlock` 失能相未屏蔽报警与故障出口

- **现象**：边界八声明「`bEnable = FALSE`：`bPermit := FALSE`、**三报警位清零**、`eState` 回 `eIdle`」。实现：`bAlarmSpeed := _bAlmSpd` / `bAlarmBalance := _bAlmBal` / `bAlarmFan := NOT bFanRun` 均**未串 `bEnable`**，`_bAlmSpd/_bAlmBal` 除首拍外从不清零；`bError` 亦含 `NOT bFanRun`。
- **向量**：`bEnable = FALSE`、`bFanRun = FALSE`、测点全有效 → 声明期望 `bAlarmFan=FALSE / bError=FALSE`，实测 `TRUE / TRUE` → **失能态报 Failure 级假故障**，HMI 与上游 `DeviceHealthArbiter` 会被污染。
- **修法（R63）**：出口三报警位与 `bError` 串 `bEnable`（或按 R300 新规则改声明为「失能仍报测点坏」并进码表二选一，**禁声明与实现各说一套**）。

### R62-D4【中】`FB_DL_RailPowerSequence` v1.0.2 单轨超时门控与推进判据同源 → 静默挂死

- **现象**：段 0 `_bRailPending := NOT abRailFb[_nStep]`（eRampUp）串入 `tonStep.IN`；推进判据是 `rtFb.Q`（同一反馈的边沿）。
- **向量**：`uRailCount = 3`、`abRailFb[0]` **恒 TRUE**（焊死 / 上次未断电 / 预闭合），`bOnCmd` 上升沿 → `rtFb.Q` 永假（无沿）→ 不推进；同时 `_bRailPending = FALSE` → `tonStep` 永不启动 → **无 0643、无 `bError`、永驻 eRampUp**。v1.0.1 的整段超时至少能锁 0643，v1.0.2 的 D2 修法把「误报」换成了「静默挂死」，属修法副作用。
- **修法（R63）**：另立「无进展」超时（`TON(IN := _bStepGo AND NOT _bRailPending AND NOT rtFb.Q)`）或推进判据改「沿 OR 电平」双路（电平已就位直过），并在头注释写明「反馈预闭合」的处置口径。

### R62-D5【轻】`FB_DL_BiquadFilter` 输入非有限路径复用组态标记

- 段 5 / 段 9 在 373A（输入 / 中间量非有限）路径同样置 `bCfgBad := TRUE`，而本件码表把 `bCfgBad` 定义为「组态非法」→ 仪表坏与组态错在出口上不可分（与件内码位反证段「四码处置人不同」的立论相悖）。建议 373A 走独立出口位或用 `bValid + eErr` 表达。

### R62-D6【轻】`FB_DL_IonFanInterlock` 段 0 定时器使用段 2 才写的组态位

- `tonConfirm(IN := ... AND (NOT _bCfgBad))` 在段 0，`_bCfgBad` 段 2 才计算 → 用上一拍值。非法组态首拍 TON 可能多走一拍。安全影响为零（段 3 同拍迁 eAlarm），属段序瑕疵（R301 立规）。

### R62-D7【轻】`FC_DL_PercentileRank` 剔除计数不外显

- `nNonFinite` 仅累加不出参，头注释自注「仅留档」→ 现场无法区分「样本本身缺测」与「算法剔除过多」。建议加出口或改注为「不外显，需诊断请用 `FC_DL_SignalStatistics`」。

---

## 三、返修 5 件逐条复核（对 ROUND_PLAN_R62 §4）

| 件 | 返修指令要点 | 实测 | 结论 |
|---|---|---|---|
| `FB_DL_RailPowerSequence` v1.0.2 | D1 `_nCnt=0` 早退（eIdle + eStable 两处一致）；D2 `_bRailPending` 串 `tonStep.IN` | L164-172、L188-197 两处早退齐备，原钳位降为二重防御；L115-123 待响应量三相当派 + 串入 IN；段 0 扩相刷 `rtFb` | **D1/D2 落实**，但 D2 引入 D4 新副作用（单轨超时门控自锁），挂 R63 |
| `FB_DL_TurretToolSelect` v1.0.1 | 补 eFault 死相位，四出口 | 段 4b 统一迁入闸（L190）使任一相检出锁存即落 eFault；eMoving 出口直迁 eFault；eFault 出口等 `NOT _bFault` | **通过**（R291 解除式可达：`bReset` 恒可达） |
| `FB_DL_SensorPairPlausibility` v1.0.1 | 变窗长清窗 + 除子改 `_nFill` | `_nUsePrev` 变更沿全窗清（含环元素逐项清）+ `_nFill` 除子 + 复位清单补两项 | **通过**（R294 闭环） |
| `FC_DL_WeightedPercentile` v1.0.1 | 禁委托双写 | `_bSortRet` / `_bSortValid` 分承后 `bSortOk` 合取（L159-160） | **通过**（R295 闭环） |
| `FB_DL_LineClearanceVerify` v1.0.1 | 3036 口径 + 链末位 | 头注释改「窗内残留超 `nResidueMax` 逐拍提示、不锁存、不置 bError」；L174 位于故障回放之后；组态闸含 `nResidueMax < 0` | **通过**（R296 闭环），注：`DINT_TO_UDINT(nResidueMax)` 在负值时先转换后判，建议下轮把 `nResidueMax < 0` 前置为第一判据（轻观察，不入账） |

> 版本偏差留痕：三件实测入库版本为 v1.0.0（计划书假设 R61 已发 v1.0.1），已按实测递增一次并在各自头注释写明「禁跳号」——处置正确，立 R305 入总监账本。

---

## 四、R193 扩面判定

- 挂账 **7 处 × 4 件 × R62**（严重 2 / 中 2 / 轻 3），**≥3 → 触发扩面**：
  - R63 配额 16 → **13**（下调 20%，向上取整）；
  - 扩面族①「二阶 / 结构专用滤波族」（`FB_DL_LowPassFilter` / `HighPassFilter` / `NotchFilter` / `FirFilter` / `SecondOrderFilter` / `BiquadFilter`）逐件核「稳定/系数闸」；
  - 扩面族②「直流母线 / ADC / 测点监视族」（`VfdDcBusRipple` / `InverterGridSync` / `BrakeResistorThermal` / `AnalogTransmitter` / `NtcChannelHealth`）逐件核「入参兼作除子是否结构早退」。

## 五、机检逃逸复盘（→ R303）

两处严重项 **16/16 机检全 PASS**：机检覆盖「禁用符号 / 双语注释 / 声明差集 / 循环配对 / 闸参数枚举」，**不覆盖数学判据充分性与「标志置位但未早退」的语义断裂**。下轮机检候选两项（可文本锚定）：①`IF <cond> THEN` 内仅赋值 `_bXxx` 而无 `RETURN` 的块，且该 `_bXxx` 后续被用作除数保护条件 → 提示；②浮点不等式链中出现 `ABS(a - b) < k` 作为「判据」且注释含「稳定/窗口/三角」字样 → 人工复核。

*R62 终审 ｜ 道莅工控代码库产品总监 ｜ 本轮不改码（R333），全部挂 R63 首位*
