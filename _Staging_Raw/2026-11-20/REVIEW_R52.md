# REVIEW_R52 — 五抽语义终审（只读轮，R333）

- 轮次：R52 / 2026-11-20 / 抽查 5 件（本轮新增）
- 模式：只读审查，不做行为变更；全部问题挂账 R53
- 审查口径：环窗时间序(R194/R205)、状态机完整性、安全侧方向、定时器段 0 刷新、声明一致性(R191/R204)

结论总表

| # | 组件 | 级别 | 主症 | 行号 |
|---|------|------|------|------|
| 1 | DL_Algo/FB_DL_ControlOutputSlewWatch | 严重 | 环形写头无初值 → `_aSign[0]` 越界写；运行期窗深变小不回钳 | 61 / 152 / 154-165 |
| 2 | DL_Motion/FB_DL_AxisHomeRepeatVerify | 中 | eDone 相不保持判定，bPass/bReject 回 FALSE 与注释相悖 | 97-98 / 173 |
| 3 | DL_Algo/FB_DL_PidParamDriftAudit | 轻 | 有限性闸只拦 NaN，Inf−Inf→NaN 使越差判据静默为 FALSE | 83 / 134-147 |
| 4 | DL_Device/FB_DL_HeatTraceCircuitMon | 中 | 段 0 双定时器未与 eMon 联锁 → 使能瞬间绕过确认延时/首窗即刻结算误报 | 83-84 / 146-156 |
| 5 | DL_Device/FB_DL_BrakeResistorThermal | 中 | 能量占额→温升线性映射与一阶冷却模型不自洽，默认参数下额定电流即 100% 过载 | 127 / 141 |

统计：严重 1 / 中 3 / 轻 1 / PASS 0 → **5 项挂账 ≥ 3，按 R193 触发族级扩面**。

---

## 1. FB_DL_ControlOutputSlewWatch（DL_Algo，211 行）— 严重

### 1.1 环形写头无初值 → 数组越界写（严重，红线 5）
- `61` `_nHead : INT;` 声明无初始值，CODESYS 零初始化 → 首拍 `_nHead = 0`。
- `152` `_aSign[_nHead] := _nSg;` → 首拍写 `_aSign[0]`，而数组域为 `ARRAY[1..32]`（`60`），越界写入相邻存储（`_fPeak` 邻位）。
- 连带后果：首拍 `_nOldest := _nHead - _nFill`（`161`）= `1-1=0` → `<1` 分支 +`_nEff`（`163`）得 16 → `175` 读到未写槽 `_aSign[16]`（Z），首个样本被漏计，首窗翻转数偏小。
- 修法（一行）：`61` 改为 `_nHead : INT := 1;`（`_nOldest` 同改 `:= 1`，与 `113` 复位值对齐）。

### 1.2 运行期窗深变小时环窗不回钳（严重，R308 遗漏面）
- `88-94` 仅钳 `_nEff`，未把 `_nHead` / `_nFill` 回钳到新窗深。
- 例：`nWinLen` 16→4 时 `_nHead` 可能为 12（写入落在 1..32 内但破坏环序），`_nFill` 仍 16（`157` 的 `_nFill < _nEff` 为假不再封顶）。
- `161` `_nOldest := _nHead - _nFill` 可能为 −12，`162-164` 只做一次 `+_nEff` 修正 → 仍 ≤ 0 → `175` `_aSign[_nOldest+_nJ]` 读 0 或负下标；`172-174` 单次减法无法把 `_nIdx` 折回 1.._nEff。
- 修法（一行）：`94` 之后加 `IF _nHead > _nEff THEN _nHead := 1; END_IF  IF _nFill > _nEff THEN _nFill := _nEff; END_IF`（窗深变更即整体重同步）。

### 1.3 时间序环回本体（无缺陷，记录自证）
- 稳态下 `_nOldest := _nHead - _nFill`（未满窗=<1）与 `+_nEff` 满窗回卷（`161-164`）、`171-174` 时间序→槽位单次回卷在 `_nEff ∈ [4,32]`、`_nFill ≤ _nEff` 前提下正确；遍历跳 Z 符号（`176-181`）与首点不计数符合设计。

### 1.4 轻项
- `188` `fSlewPeak := _fPeak;` 而 `168` 每趟 `_fPeak := 0.0` 后仅比本拍 `fSlew` → 出口恒等于 `ABS(fSlew)`，与 `41` 声明「窗口内 |速率| 峰值」名实不符；且 `fSlewPeak` 未进段 1 预清，eIdle/eFault 保持陈旧值。
- `95-97` `_nEff < 2` 守卫在已钳 `>=4` 后为死代码（仅可读性问题，不影响行为）。

### 1.5 通过项
- 定时器：`87` `rtReset` 在段 0 无条件刷新 ✓；CASE `ELSE` 兜底 `201-204` ✓；复位作用域逐项声明 `108-119` ✓；常量集 ⊆ 引用集（`73-78` 全部被引）✓。

---

## 2. FB_DL_AxisHomeRepeatVerify（DL_Motion，190 行）— 中

### 2.1 判定结果在 eDone 相不保持（中，R191 名实不符）
- `97-98` 段 1 每拍无条件 `bPass := FALSE; bReject := FALSE;`，而置位仅发生在 `166` / `168`（eCollect 结算那一拍）。
- `171` 迁入 eDone 后，下一拍起 `bPass`/`bReject` 双 FALSE，与 `173` 注释「完成相：保持判定」及 `44-45` 声明（「合格（可放行）」「超散拒绝放行」）矛盾；上层按电平取判定时读到「既不 Pass 也不 Reject」的第三态。
- 修法（一行）：把 `97-98` 的预清移入 eCollect 分支内（或仅在 `_bDoneC` 拍预清），eDone 相保留 `bPass`/`bReject` 至复位/失能。

### 2.2 轻项
- `122` eIdle 清 `_nGot := 0` 但未清出口 `nGot` → 失能后出口仍显示旧样本数（内部 0），名实短暂不一致。
- `131` 容量闸用 `DL_AHR_NMAX` 而非 `_nEff` 无关紧要（`_nGot` 达 `_nEff` 当拍即结算），无越界风险。
- `85` 有限性判据（NaN 自反 + Inf 差判）写法正确，Inf 被拦 ✓；`154/163` 除子 `_nEff >= 2`、`_nEff-1 >= 1` 到位 ✓；`183` ELSE 兜底 ✓；`83-84` 两 R_TRIG 段 0 无条件 ✓；常量集（`74-77`）全部被引 ✓。

---

## 3. FB_DL_PidParamDriftAudit（DL_Algo，186 行）— 轻

### 3.1 有限性闸只拦 NaN，不拦 Inf（轻，安全侧）
- `83-84` 六个 `x = x` 自反闸对 Inf 恒真 → Inf 直通。
- 后果：`134-147` 当 `fTi = Inf, fTiRef = Inf` 时 `ABS(Inf-Inf) = NaN`，`NaN > 阈值` 为 FALSE → `_bExTi = FALSE`，静默判「无漂移」；单侧 Inf 则得 Inf 而报警（安全侧）。属非安全侧的窄口，非主判据失效。
- 修法（一行）：`83` 每条补差判 `AND ((fX - fX) = (fX - fX))`（与同库 `FB_DL_AxisHomeRepeatVerify:85` 范式统一）。

### 3.2 轻项
- `80` `fTolAbs <= DL_PDA_EPS` 无条件进组态闸，但绝对口径仅在基准近零时使用；用户把未用口径置 0 即整件锁存故障（可用性紧）。
- `92` `bDriftAny` 每拍预清且仅在 `_bFinite` 分支重算 → 非有限拍汇总位回落 FALSE，而 `bDriftKp/Ti/Td` 仍为 TRUE（同源自洽性缺口）。
- `71/85` `_fHun` 作可变 VAR 承载 100.0 常量，宜入 `VAR CONSTANT`（无魔法数收口）。
- 通过项：基准近零分支除零前置 `127/134/141` ✓；`158-172` 确认拍数与饱和累加无回绕 ✓；`176-179` ELSE 兜底 ✓；`82` rtReset 段 0 无条件 ✓。

---

## 4. FB_DL_HeatTraceCircuitMon（DL_Device，171 行）— 中

### 4.1 段 0 双定时器未与 eMon 相位联锁（中，确认延时被绕过 + 首窗误报）
- `83` `tonObs(IN := NOT tonObs.Q, PT := tObserve)` 与 `84` `tonNoCur(IN := bHeatCmd AND NOT _bCur, PT := DL_HTC_CONF)` 在段 0 全相位运行（eIdle / eFault 亦计时）。
- 后果 A（误报断缆）：eIdle 下上层已给 `bHeatCmd`、电流为 0，`tonNoCur` 累积满 5s → 使能当拍进 eMon 即 `tonNoCur.Q = TRUE`（`139`）直接锁存 `bOpenCirc`，与 `③` 条「断缆判据需延时确认，避开合闸瞬态」的设计意图相悖。
- 后果 B（误报无温升）：eIdle 期 `_bT0Ok := FALSE`（`116`）不快照，但 `tonObs` 相位自由运行；使能后首窗可能在 1~2 拍内 `tonObs.Q`（`146`），此时 `_fRise ≈ 0 < fRiseMin` 且 `_bCur` 为真 → 锁存 `bNoRise`（`148`），窗口未满即结算。
- 修法（一行）：`83/84` 的 IN 各加相位闸 → `IN := (_eState = E_DL_HtcState.eMon) AND (NOT tonObs.Q)` / `IN := (_eState = E_DL_HtcState.eMon) AND bHeatCmd AND NOT _bCur`（用上拍相位，1 拍延迟可接受）；并在 eIdle→eMon 迁入拍同步 `_fTempT0 := fTemp; _bT0Ok := TRUE;`。

### 4.2 轻项
- `125-157` 非有限输入整拍跳过判据（温度 NaN 时过热判据静默）→ 对「断传感器」这种典型工况落在非安全侧，建议 R53 评估是否单列 `eSensorBad`。
- `147` 无温升判据用结算拍的单点 `_bCur` 判定「窗内有电流」，窗内电流断续工况判据偏松（宜用窗内累计/占空比）。

### 4.3 通过项
- `114-165` CASE 各相齐全 + ELSE 兜底 ✓；`95-104` 复位逐项清（含 `_bT0Ok`/`_fTempT0`）✓；`82` rtReset、`83-84` 两 TON 均在段 0 无 IF 包裹（形式合规；缺陷在相位联锁，见 4.1）✓；`85-87` NaN+Inf 双闸完备 ✓；三种成因枚举独立（`28-30`）且 `IF NOT _bFault` 唯一归因（`134-152`）✓；常量集（`72-74`）全部被引 ✓。

---

## 5. FB_DL_BrakeResistorThermal（DL_Device，170 行）— 中

### 5.1 能量占额→温升的映射与一阶冷却模型不自洽（中，默认域即误报）
- `141` `_fRiseEst := fRiseRated * (_fAccKj / fEnergyMax);` 把「满载稳态温升」当作能量占额的线性斜率，而 `127` 的一阶冷却只作用于能量、不参与温升换算，两者量纲不自洽。
- 自证：稳态能量平衡 `_fAccJ(eq) = I²R·tau`（`127-128`）。默认 `fRatedCurrent=20, fResistance=50, fTauCool=300` → 6.0e6 J = 6000 kJ，而 `fEnergyMax` 默认 20 kJ → 连续额定电流下 `_fPct` 立刻饱和 100（`134-139`）→ `bOverload` 恒 TRUE（`152`）；反之按 `141` 反推稳态温升为 `250 × 300 = 75000 K`。
- 影响：默认参数直接上线即「额定负载持续过载」，且降额建议恒 0（`147-150`）。方向偏保守（不丢保护），但组件作为产品不可用。
- 修法（一行）：`141` 改由热阻口径给出 → `_fRiseEst := fRiseRated * (_fPowerW / (fRatedCurrent * fRatedCurrent * fResistance));`（稳态功率比 × 满载温升），或在头注释与默认值上把「能量额度」明确定义为 `I²R·tau` 的派生量并在组态闸加一致性校验 `fEnergyMax <= I_rated²·R·tau`。

### 5.2 轻项
- `114-120` eIdle 只镜像 `fEnergyKj`/`fTempRise`/`fTempEst`，`fEnergyPct` 与 `fDeratePct` 留陈旧值；且失能期 `_fAccJ` 冻结、不执行冷却（`127-128` 仅在 eEst），复使能后能量偏高（保守侧，但语义上「停机即不冷却」不物理）。
- `129-131` 能量仅设下界 0，无上界饱和 → 极端电流下 `_fAccJ` 可无界增长，`fEnergyPct` 虽饱和 100 但恢复时间被拉长（建议在 `_fPct` 饱和处同步回夹 `_fAccJ`）。
- `89-90` `bWarn`/`bOverload` 每拍预清且只在 eEst 置位 → 组态故障相（eFault）期间丢失过载指示。

### 5.3 通过项
- `79-83` 全部除子（`fTauCool`、`fEnergyMax`、`fRiseRated`、`tCycle`）组态前置 ✓；`124` 另加 `_fDtSec > eps` 双闸 ✓；`135-139` 百分比对称饱和、`152/154` 用 `>=` 直比阈值（非浮点等值）✓；`160-163` ELSE 兜底 ✓；`84` rtReset 段 0 无条件 ✓；常量集（`72-75`）全部被引 ✓。

---

## 6. 收口与挂账

- 挂账明细：R52-01 件 1 越界写+环窗回钳（严重）；R52-02 件 1 `fSlewPeak` 语义（轻）；R52-03 件 2 判定保持（中）；R52-04 件 2 `nGot` 失同步（轻）；R52-05 件 3 Inf 闸缺口（轻）；R52-06 件 3 `fTolAbs` 过严 + 汇总回落（轻）；R52-07 件 4 定时器相位联锁（中）；R52-08 件 4 传感器故障未单列（轻）；R52-09 件 5 温升映射模型（中）；R52-10 件 5 冷却冻结+能量无上界（轻）。
- **R193 判定**：5 抽中 5 件挂账（≥3）→ 触发族级扩面，需返修受影响族：① 环窗族（`_nHead` 初值 + 窗深回钳，全库 `_aXXX[_nHead]` 模式）；② 判定保持族（eDone 相出口回落）；③ 段 0 定时器相位族（`IN` 未挂相位闸的 TON）；④ 设备热模型族（能量↔温升换算）。下轮计划件数按 R193 下调 20%。
- 本轮未改任何 `.st`（只读轮，R333）；以上均转 R53 派单。
