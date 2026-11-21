# REVIEW_R64 — 五抽终审 + 点修复核（2026-11-21）

> 范围：10 新件 + 2 点修件中抽 5 件（两段式：先模板定向扫查，再快速通读）。机检 12/12 PASS 已由 closeout_r64.py 出具，本报告只覆盖**语义与闸位**层。

## 1 五抽结论分级

| # | 组件 | 子库 | 分级 | 结论 |
|---|---|---|---|---|
| 1 | `FC_DL_FlowUnitConvert` | MathData | **严重（安全侧·已就地修）** | `DL_FUC_LMIN = 16.666667` 实为「L/min 每 m³/h」的倒数，与本表声明单位 [（m³/h）/（L/min）] 相反 → L/min 参与的全部换算错 **277.78 倍**（60 m³/h→L/min 得 3.6，头注释 V1 声明 1000.0）。旁证：Temp / Press 姊妹件因子均为「基准/源」正向，本件为族内唯一反向件。**修法**：常量改 `0.06`（1 L/min = 0.06 m³/h）+ 注释单位校正 + 版本 v1.0.1 + registry/JSONL 重注入；修复后 V1 60→1000.0 / V2 100→6.0 / V3 50→3.0 / V4 100 SCFM→169.9011 四向量全部自证成立。 |
| 2 | `FB_DL_DualValveBlockSet` | Device | **中（挂 R65）** | `tonMismatch` IN 仅串锁存门控、缺相位条件：eIdle 期不一致电平继续累计 ET 且退出 eRun 不清零 → 再令时窗口被前次残留侵蚀，实际窗短于 `tMismatchWin`（与头注释边界三「窗吸收切换瞬态」的承诺不符）。同轮 `FB_DL_UnscramblerSeq` 的 `tonJam`/`tonPhase` 三闸齐备，同批两件两写法。另 1 处**轻**：边界五写 `bValveCmd = bOpenCmd AND NOT _bFaultLatch AND bEnable` 三式，段 6 实现为两式（`bEnable` 由段 3 早退保证，行为等价，属口径不符）。 |
| 3 | `FB_DL_ReworkLotGate` | Process | **轻（挂 R65）** | `eReleased` 相不随复检失效回迁：登记仍在 + 放行电平仍持 + `bRecheckPass` 掉电时，`bReleaseAllow` 正确关断但 `eState` 仍报 eReleased，HMI 读状态会误读为「放行中」。另：3037 为单拍信息位（已声明 R256），HMI 轮询可能漏读。 |
| 4 | `FB_DL_UnscramblerSeq` | Process | **轻（挂 R65）** | `_bHold` 未在离开 eFeed / eSort 时清零（仅复位沿与失能清），跨相粘滞一拍 → 重进相时 `tonPhase` 门槛晚一拍起算。行为上无安全后果（门槛只会延后不会提前）。 |
| 5 | `FC_DL_GcdUdintCalc` | MathData | **PASS** | 双零哨兵 + 单零口径正确；`MOD` 除子由循环条件 `nY <> 0` 结构证明；守卫 64 > 32 位欧几里得最坏步数（Fibonacci F47 口径约 46 步）；`nIter` 与 V5 向量 2 步一致；无进位/截断类写法。 |

**合计**：严重 1（就地修）/ 中 1 / 轻 2 / PASS 1；**就地修 1 件**，挂 R65 3 处。族分布：数值常量 1 / 计时门控 1 / 状态标签 1 / 标记清除 1 —— 分散型，按 R309 不扩面，R65 只做点修 + 配额不下调（本轮就地修已替代 1 处挂账）。

## 2 逐条红线机检（增量，5 件 + 姊妹件对照）

| 检查项 | 结果 |
|---|---|
| GVL / `VAR_EXTERNAL` / `%I%Q%M` 物理地址 | 6/6 件 0 命中 |
| 声明行中文注释覆盖率 | 6/6 件 0 裸声明 |
| 自赋值死语句（R261/R282） | 6/6 件 0 命中 |
| 故障级码后 ≤3 行 `bError := TRUE`（R310） | 4 处命中**全为误报**（预设 `16#0000_0000` 与信息级 3037/0663）→ 立 **R318 白名单** |
| 浮点 `=` 判等 | 0 命中（`fValue <> fValue` 属 NaN 惯用法，非判等） |
| 变量除零 | FlowUnitConvert `/ fToF` 除子仅由常量表赋值且表内四项 > 0，ELSE 早退 → 证明成立 |
| `ELSE` 兜底（CASE） | 5/5 件齐备 |
| 锁存解除式可达自证 | 5/5 件 `bResetCmd` 上升沿可达（DualValveBlockSet / UnscramblerSeq 复位后若电平仍在会 2 拍内重锁，属安全侧期望行为） |

## 3 点修复核（ROUND_PLAN_R64 §1 六锚点抽 3 条）

| 锚点 | 实测 | 结论 |
|---|---|---|
| A1 `tonSlopeLow` IN 含 `NOT _bMeasBad` | L150：`tonSlopeLow(IN := (... eRamp) AND _bSlopeLow AND (NOT _bMeasBad) AND (NOT _bFaultLatch), PT := DL_VPS_SLOPEGRACE)` | ✅ |
| A2 `NOT bKmCmd` 早于同分支超时命中 | L230 `NOT bKmCmd` < L232 `tonTotal.Q`；L244 `NOT bKmCmd` < L246 `tonTotal.Q`（两分支各验一次） | ✅ |
| A6 LMS 先算后用 + 写回预检 | L165 `_nTaps := USINT_TO_DINT(uTaps)` < L177 变更沿比较；L233 `_fProdAbs := ABS(_fCorr * _afX[_i])` < L238 权重写回 | ✅ |

（未抽 A3/A4/A5：A3 头注释两处文案已由 A1/A2 同文件确认存在；A4/A5 属 AdaptiveLmsFilter 的 374B 口径，已在 A6 同文件通读中一并目检通过。）

## 4 三向一致

`INDEX_REGISTRY.json` counts 135/267/134/204/120/275 = **1,135**；文件树实测 `ls DL_*/*.st` 同值逐库对齐；ROADMAP 本轮不追加待办（>30 条阈值）。**差额 0**。

## 5 下轮转移（R65 首位）

1. `FB_DL_DualValveBlockSet` v1.0.1：`tonMismatch` IN 补相位条件（`(_eState = eRun)`），同步订正边界五三式与段 6 两式的口径不符。
2. `FB_DL_ReworkLotGate` v1.0.1：`eReleased` 相在 `bLotRework AND NOT bRecheckPass` 时回迁 `eReworkHold`（状态标签与许可同源）。
3. `FB_DL_UnscramblerSeq` v1.0.1：离开 eFeed / eSort 时清 `_bHold`（与 `_eState` 迁移同拍）。
4. 机检脚本落地 R318 白名单与 R316 相位门控锚点（登记待验）。
