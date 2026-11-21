# R11 阶段五终审报告（双签 · 第二签）

- 终审人：道莅工业代码库产品总监（独立复核，不采信编码方自检结论）
- 终审日期：2026-11-15
- 终审对象：R11 十六件（DL_Process 4 / DL_Device 4 / DL_Base 2 / DL_MathData 4 / DL_Algo 1 / DL_Motion 1）
- 规格依据：`C:\Library\_Staging_Raw\2026-11-15\ROUND_PLAN_R11.md` 章节 1.1~1.16
- 判据依据：`daoli-library-director.md` 人格 + `daoli-st-standard` 技能三件 references（coding-standard / directory-contract / doc-templates）+ 规则库 R1~R32
- 机检工具：`redline_check_r11.py`（文本层八条红线），终审前 16/16 PASS，终审后 16/16 PASS

---

## 一、逐件结论表（16 行 · 全查，无抽样）

| # | 组件 | 机检 | 枚举覆盖（R31） | 时序与实例刷新（R32/R24/R19） | 边界与量纲 | 判定 |
|---|------|------|----------------|------------------------------|-----------|------|
| 1 | FB_DL_PressFitStation | PASS | E_DL_PressFitState 8 成员 / CASE 8 标签 + ELSE ✓ | 3 个边沿 + 2 个 TON 在 CASE 外无条件刷新；`PT := _tStageEff` 已钳 `T#180S`；`bDone` 每拍预清、`eFinish` 唯一置位；`_bInit` 初值 FALSE + `IF NOT _bInit` ✓ | 包络二分带 `DL_MAX_LOOP=64` 防死锁；上下限/容差逐拍钳位；`bError := _bFaultLatch` 派生，01C0/01C1 只进 `uErrorId` ✓ | PASS |
| 2 | FB_DL_RotaryIndexTable | PASS | E_DL_IndexTableState 5 成员 / 5 标签 + ELSE ✓ | `fbTrigInPos`(R_TRIG) 与 `fbTrigInPosFall`(F_TRIG) 顶层刷新；4 个时间量全部钳位；`bIndexReq/bCycleDone` 预清零 ✓ | 掩码用 `uBitAcc * 2` 逐位构，规避 64 位移位；`nI` 钳 1~24，UDINT 累加不溢出 ✓ | PASS |
| 3 | FB_DL_AgvDockingHandshake | PASS | E_DL_DockState 7 成员 / 7 标签 + ELSE ✓ | `fbTmoState` 顶层无条件刷新（`PT := DL_TMAX_STATE`）；`bHandshakeOk` 预清零、`eDockConfirm` 唯一置位；`bTransferComplete` 在 eIdle 清 / eTransferMonitor 置，单点闭环 ✓ | 监视时长钳位防污染均值；超时窗量程合法；02E0/02E2/02E3 分级正确 ✓ | PASS |
| 4 | FB_DL_EnergySavingMode | PASS | E_DL_EcoModeState 5 成员 / 5 标签 + ELSE ✓ | `fbTmoEco/fbTmoWake` 顶层，`PT := DL_TIME_MAX`(T#500H)；三出口 `bAirPressureLow/bHeatStandby/bServoSleep` 段 9 先清后置，无锁存残留 ✓ | 裕量/压力逐拍钳位；唤醒门限 `>= (fWakeGate + EPS)` 判等带容差；`tWakeEff * DL_WAKE_FACTOR` 防零 ✓ | PASS |
| 5 | FB_DL_PortDiagAggregator | PASS | 四相位枚举 4 成员 / 4 标签 + ELSE ✓ | `afbDebounce[1..8]` 在 `FOR i := 1 TO DL_PORT_MAX` 全程刷新，未因 `nPortCount` 少刷（R7 关键项）；`fbTonWindow` 顶层；`uErrorId` 段 11 单一优先级链全拍只写一次 ✓ | 回绕差分按归零处理；`uPortFaultMask AND DL_PORT_MASK_ALL` 屏蔽高位；端口 2+5 → 16#0012 与 V1 一致 ✓ | PASS |
| 6 | FB_DL_StatusWordSegDecoder | PASS | 四相位枚举 4 成员 / 4 标签 + ELSE ✓ | 无边沿实例；`nValidCount`、状态掩码、`eReject` 退出条件均单拍语义清晰（复位沿 + 有效段≥1）✓ | `nWidth >= DL_WORD_BITS` 取 `DL_MASK64_ALL`，**全程无 64 位移位**；`(nOffset+nWidth) > 64` 先拒后移；重叠用占位掩码；`LWORD_TO_UDINT(SHR(...))` 显式转换 ✓ | PASS |
| 7 | FB_DL_NtcTempScan | PASS（修复后） | 四相位枚举 4 成员 / 4 标签 + ELSE ✓ | `fbTonScan` 顶层刷新；`bScanTick` 单拍拉低强制重起算；通道故障掩码只增不减、仅复位清，且置于状态机之后 ✓ | B 值公式三步前置守卫（`ABS(fBeta)<EPS`、`fR25<=EPS`、`fT25<=EPS`）；`fInvTemp <= EPS` 判正后倒数；"饱和累加"守卫**原缺失于全扫分支**，已补 ✓ | 修复后 PASS |
| 8 | FB_DL_RollerGapAdjust | PASS | 五相位枚举 5 成员 / 5 标签 + ELSE ✓ | 超时 `tMoveUse` 钳位（`<=0` 退 `T#24H` 关闭监控）；`fGapCmd` 只在跃迁拍写，故障时自然保持；`bArrived` 预清 + 单点消费 ✓ | `fCmdMax < fCmdMin` 自动换位；背隙钳 `[0, DL_BACKLASH_MAX]`；到位判据带容差 `ABS(残余) <= tol + EPS` ✓ | PASS |
| 9 | FB_DL_YearWindowCheck | PASS | E_DL_YearWinPhase 4 成员 / 4 标签 + ELSE ✓ | 三边沿（`_fbTrigOpen`、`_fbTrigClose`、`_fbTrigReset`）顶层刷新；`bInWindow` 与 `_eState` 同源派生 ✓ | 序数法用 LINT 中间量防 INT 溢出；闰年 `MOD 4/100/400`；两条 WHILE 折叠带 `_nGuard` 与 `DL_GUARD_MAX=2048`；`_nSpan < 0` 判非法（011F）；`_nSpan >= _nCycleLen` 钳整周期 ✓ | PASS |
| 10 | FB_DL_RolloverCounter | PASS | E_DL_RollPhase 3 成员 / 3 标签 + ELSE ✓ | 三 R_TRIG 顶层刷新；`bWrapped/bAtPreset/_bWrapNow/_nTurnStep` 段 1 预清零；装载优先于加减沿（V3 口径）✓ | 回绕用"比较+赋值"**禁 MOD**；`_ufBound` 上下限钳位，越界退化冻结 + 0218；圈数饱和 ±`DL_TURNS_MAX`；0120 信息级不置 `bError` ✓ | PASS |
| 11 | FC_DL_RangeOverlapCheck | PASS | E_DL_RangeRelation 6 成员 / 判定链 6 分支有序 + 兜底 ✓ | 纯函数无实例、无状态、无跨拍量 ✓ | 六输入区间比较取反判非有限（NaN 不穿透）；判定次序 相等→相离→相接→包含→部分；`fOverlapSpan` 前置非负保护；无除法、无循环 ✓ | PASS |
| 12 | FC_DL_CalcDistance3D | PASS | 无枚举（纯函数）✓ | 纯函数；先闸门后计算，早退路径输出已定值 ✓ | 六输入有限性闸门；`_fScale = MAX(ABS(dX), MAX(ABS(dY), ABS(dZ)))` 归一化防平方溢出；后置守卫 + 非负钳位；0219 信息级 ✓ | PASS |
| 13 | FC_DL_RandomNext | PASS | 无枚举（纯函数）✓ | 纯函数；种子由调用方持有，UDINT 自然回绕 ✓ | `_uMul=0`/`_uInc=0` 双向退化保护；`>= 1.0` 钳 `1.0-EPS`；零种子按原值递推并置 `bZeroSeed`（与 V1 向量自洽，与规格叙述冲突见 E-02）✓ | PASS |
| 14 | FC_DL_PercentileLReal | PASS | 无枚举（纯函数）✓ | 纯函数；插入排序双层循环共用 `nGuard`，触顶 `bSortOk := FALSE` 按空集返回 ✓ | `nCount<1` 空集早退；`nUsable` 双约束取小；分位钳位含 NaN 分支；拷贝剔非有限；`nLo+1>=nN` 不外插；结果非有限回退 0 ✓ | PASS |
| 15 | FB_DL_R2rEwmaTuner | PASS | E_DL_R2rState 5 成员 / 5 标签 + ELSE ✓ | `bCorrected/bAtLimit/uErrInfo` 每拍预清零；`bInit` 首扫装载；环索引写入前双检 ✓ | λ 双向钳位 + 非有限回默认（1F01）；`fCorr` 限幅 ±`fCorrLimEff`（1F03）；`LIMIT(fLimLow, ..., fLimHigh)` 保证参数域；1F10 非有限锁存 ✓ | PASS |
| 16 | FB_DL_WindingTensionCtrl | PASS（修复后） | E_DL_TensionPhase 4 成员 / 4 标签 + ELSE ✓ | PID 单实例、段 11 CASE 外单次调用；R_TRIG 顶层；**跟踪拍生命周期断裂已修**（D-01/D-02）✓ | 锥度分母双重校验；卷径域二次钳位；NaN 全线闸门；**02D1 判据与饱和计数不自洽已修**（D-03）✓ | 修复后 PASS |

判定分布：PASS 14 件 · 修复后 PASS 2 件 · 退回 0 件。

---

## 二、缺陷清单

### D-01【致命】FB_DL_WindingTensionCtrl.st:484（原 460 / 496 置位，无任何递减）

- **现象**：`nTrackSync` 仅在进入闭环时置 2（eIdle 与 eOpenLoop 两处），全文件无递减语句；段 11 `bTrack := (nTrackSync > 0)` 因此恒为 TRUE。
- **后果**：PID 永久停在跟踪态，`fOut` 恒等于 `fTrackValue = 0.0`，`fTrim` 恒为 0，闭环退化为开环；验收向量 V3（修正 +1.0 N、输出 63.5 N）不可达。
- **修法**：在 `E_DL_TensionPhase.eClosedLoop` 分支首部逐拍递减（进入拍因 CASE 分支未选中而不递减，正好两拍跟踪）：
  `IF nTrackSync > 0 THEN nTrackSync := nTrackSync - 1; END_IF`

### D-02【致命】FB_DL_WindingTensionCtrl.st:535-543（原 `fActual := fDancerPosEff`）

- **现象**：跟踪窗内 PID 过程值仍取真实摆辊位置，`fErr = 0 - PV = -2.0 mm`，`fP = +1.0`，跟踪分支反算 `fInt := fOut - fP - fD = -1.0`；PID 件 `tTi = T#0S` 时积分永不更新，该残量永久驻留。
- **后果**：跟踪结束后 `fOut = fP + fInt ≡ 0`，且与误差幅值无关（误差越大 `fP` 越大、`fInt` 同步越负）。即使修好 D-01，闭环恢复后修正恒为零——降级恢复路径永久失效，V3 仍不可达。这是"纯比例 + 跟踪值 0 + 反算积分"三者叠加的死锁。
- **修法**：跟踪窗内以基准替代过程值，令偏差恒为零、反算积分保持零，窗口结束全量比例作用恢复：
  `fPidPvEff := fDancerPosEff; IF nTrackSync > 0 THEN fPidPvEff := fDancerRefEff; END_IF`，PID 引脚改 `fActual := fPidPvEff`；新增局部量 `fPidPvEff` 并同步修订头注释设计要点⑤。

### D-03【严重】FB_DL_WindingTensionCtrl.st:489 / 504（原 `> DL_INVALID_MAX`）

- **现象**：`stStat.uInvalidDiaCnt` 三处累加均以 `< DL_INVALID_MAX`(50) 为守卫，计数封顶恰为 50；判据写 `> 50` 永假。
- **后果**：02D1 锁存永不触发，eFault 态不可达——规格"连续无效 50 次即锁存 02D1"与头部现场提示③均落空，卷径几何法彻底不可信时仍继续出张力。
- **修法**：两处判据改为 `>= DL_INVALID_MAX`（第 50 次无效当拍即锁存），与饱和计数上限自洽。

### D-04【轻微】FB_DL_NtcTempScan.st:276

- **现象**：`nScanRounds` 在 `ELSIF bScanTick` 分支有 `< DL_CNT_MAX` 饱和守卫，在 `IF bScanAll` 分支直接 `+1`，两分支不对称。
- **后果**：全扫模式连续运行 2^32 拍（10 ms 周期约 497 天）后 UDINT 回绕归零，统计量语义失真（无控制影响）。
- **修法**：全扫分支补同一守卫，两分支口径统一。

**修复汇总**：4 条缺陷全部当场修复（致命 2 / 严重 1 / 轻微 1），涉及 2 个文件，均升 `v1.0.1` 并在头注释"修订历史"追加中英各一段；修复后两件重跑 `redline_check_r11.py` 均 PASS（缺陷 0、提示 0）。

---

## 三、验收向量复算（每件 ≥2 条独立手算）

| 组件 | 手算过程 | 结论 |
|------|---------|------|
| FB_DL_PressFitStation | V1 包络二分：节点(0,10,2)/(10,20,5)，位移 5 → t=0.5，上限 15、下限 3.5；V2 接触点：(0.05-0.02)/(0.06-0.02)=0.75 → 1.0+0.75×0.2=**1.15 mm**；V5 压降 12.0-8.0=**4.0 kN** > 0.3 判超限 | 与实现及规格一致 |
| FB_DL_RotaryIndexTable | V1 前 5 工位启用：`uBitAcc` 自 1 起逐位 ×2 累或 = **16#001F**；V4 空跑 4 工位：`NOT bDryRun` 门控使 `nCycleCount` 不增，4 拍出一次循环脉冲 | 一致 |
| FB_DL_AgvDockingHandshake | V2 到位超时 10 s 未建立 → 02E0 + 故障态；V4 到位阶段 `bCompleteEarly` → 02E3 直接故障，不经放行 | 一致 |
| FB_DL_EnergySavingMode | V2 门限 4.0+0.2=**4.2 bar**，实测 4.1 < 4.2+EPS → 放行 FALSE；V3 4.25 ≥ 4.2 → 放行 TRUE，缓冲走完后下一拍 eRun | 一致 |
| FB_DL_PortDiagAggregator | V1 端口 2→bit1、5→bit4，OR 得 **16#0012**；V4 16#FFFF_FFFF→3 按归零差分 = **3**；V5 端口数 12 钳 8 + 0140 且 `bError` FALSE（0140 为信息级） | 一致 |
| FB_DL_StatusWordSegDecoder | V1 (16#1234 >> 4) AND 16#FF = **16#23 = 35**；V2 (16#1234 >> 8) AND 16#FF = **16#12 = 18**；V5 宽 64 取 `DL_MASK64_ALL` 后 SHR 0 → LWORD 全 1 → 截 UDINT = **16#FFFF_FFFF**，无 64 位移位 | 一致 |
| FB_DL_NtcTempScan | V2 R=2R25：1/T = 1/298.15 + ln2/3950 = 3.35402E-3 + 1.75467E-4 = 3.52949E-3 → T = **283.33 K = 10.18 ℃**；V3 R=0.5R25：3.35402E-3 - 1.75467E-4 = 3.17855E-3 → T = **314.61 K = 41.46 ℃** | 一致（±0.1 ℃） |
| FB_DL_RollerGapAdjust | V1 阶段 A = 2.500 - 0.050 = **2.450**，保持段 2.500；V3 上限 3.0 钳位后阶段 A = 3.0-0.05 = **2.950**、保持段 **3.000**（规格写 3.0，见 E-03） | 实现正确，规格向量需订正 |
| FB_DL_YearWindowCheck | V1 2026 非闰：3-01 序数 60、6-30 序数 181、4-15 序数 105 → offset 45 ≤ span 121 → 窗内 TRUE，距窗沿 76 天；V4 `bIncludeEnd=FALSE` 时 span 121-1=120，6-30 offset 121 > 120 → 窗外 FALSE | 一致 |
| FB_DL_RolloverCounter | V1 上限 100、计数 100 再加沿 → 比较命中 → 计数 **0**、`bWrapped` TRUE、圈数 +1；V7 上限 9 自 0 起 30 个加沿 → 第 10/20/30 拍各绕一次 → 计数 **0**、圈数 **+3**、脉冲 3 次 | 一致 |
| FC_DL_RangeOverlapCheck | V1 A[0,10] B[5,15] → min(10,15)-max(0,5) = **5.0**（ePartial）；V3 A[0,10] B[2,8] → min(10,8)-max(0,2) = **6.0**（eContains）；V5 相等 → **10.0**（eEqual） | 一致 |
| FC_DL_CalcDistance3D | V1 √(3²+4²+0²) = √25 = **5.0**；V2 √(4+9+36) = √49 = **7.0** | 一致 |
| FC_DL_RandomNext | V1 0×1664525+1013904223 = 1013904223 = 16#3C6E_F35F，×2.3283064E-10 = **0.2360680**；V2 16#FFFF_FFFF×1664525 mod 2³² = 4293302771，+1013904223 回绕 = 1012239698 = 16#3C55_8D52，×2.3283064E-10 = **0.2356716** | 一致 |
| FC_DL_PercentileLReal | V1 [1,2,3,4] P=0.5 → pos=0.5×3=1.5，nLo=1，frac=0.5 → 2+0.5×(3-2) = **2.5**；V2 P=0.9 → pos=2.7，nLo=2，frac=0.7 → 3+0.7×(4-3) = **3.7** | 一致 |
| FB_DL_R2rEwmaTuner | V1 0.3×2.0+0.7×1.0 = **1.3**；V2 fCorr = -1.3×1.0 = -1.3 → 钳 **-1.0**，参数减 1.0，`bAtLimit` + 1F03 | 一致 |
| FB_DL_WindingTensionCtrl | V1 1-0.5×(800-200)/(1000-200) = 1-0.375 = **0.625**（落在 [0.5,1]）；V2 100×0.625 = **62.5 N**；V3 fErr = 0-2.0 = -2.0，fKp = -0.5 → fP = **+1.0** → 钳 1.0 → trim +1.0 → **63.5 N**（修复 D-01/D-02 后方可达）；V5 (120/60)/(π×60/60) = 2/π = 0.636620 m = **636.6 mm**（`fPrevDia=0` 走首拍直取，不被低通拉低）；V6 转速 0 → 01C0 + `bError` FALSE；V7 摆辊 9999 → 02D0 + `bError` TRUE + `bInControl` FALSE + 输出等于基准 | V1/V2/V5/V6/V7 一致；V3 依赖本轮修复 |

---

## 四、规格勘误清单（改规格，不改代码）

| 编号 | 规格位置 | 规格原文 | 实际/正确 | 处置 |
|------|---------|---------|----------|------|
| E-01 | 1.11 | `FC_DL_RangeOverlapCheck` 归属 **DL_Base** | 落盘 `C:\Library\DL_MathData\`，`INDEX_REGISTRY.json` 登记 `DL_MathData`；依赖矩阵中 MathData→Base 单向，落 MathData 更合理 | 改规格 1.11 子库标注为 DL_MathData |
| E-02 | 1.13 | 零种子为"吸收态"（递推后退化为恒 0） | 与同节验收向量 V1（零种子 → 0.2360680）自相矛盾；实现取向量口径（零种子照常递推 + `bZeroSeed` 提示） | 改规格叙述，保留向量 |
| E-03 | 1.14 V3 | 目标 5.0、上限 3.0 → "钳位后指令落在 3.000" | 两阶段算法应为阶段 A = 3.0 - 0.05 = **2.950**、保持段 3.000；实现正确 | 改规格向量 |
| E-04 | 1.15 | 成员名 `abHasEwma`（BOOLEAN 语义） | `a` 前缀为数组红线冲突，实现改 `bHasEwma`，语义不变 | 改规格成员名 |
| E-05 | 1.16 | 成员名 `nInvalidDiaCnt : UDINT` | 无符号量须 `u` 前缀，实现改 `uInvalidDiaCnt`，语义不变 | 改规格成员名 |
| E-06 | 1.16 | 未规定故障态张力输出；未覆盖"使能瞬间反馈已丢失" | 实现取故障态输出 0.0；使能瞬间反馈失效显式进 eOpenLoop 并带 02D0 | 补规格两条 |
| E-07 | 1.16 | `fPidKp` 原样送 PID，同时又要求"正误差得正修正" | 二者符号相反；实现送 `-ABS(fPidKp)`，依托 PID 件"负增益即反作用"，与 V3 自洽 | 补规格符号约定 |
| E-08 | 1.16 / PID 件使用约定 | 未说明跟踪窗内过程值取法 | 纯比例 + 跟踪值 0 + 反算积分会形成死锁（见 D-02）；实现改为跟踪窗内过程值取基准 | 补规格与 PID 件"跟踪使用约定" |

---

## 五、观察项（v1.1 待办，本轮不改语义）

1. **WindingTensionCtrl**：`uErrInfo` 单槽被段 3/7/8/12 四处写，末写胜（优先级 01C2 > 01C1 > 01C0），该优先级未在头注释成表。建议 v1.1 补"信息码优先级表"。
2. **WindingTensionCtrl**：eFault / eIdle 态仍执行段 7 卷径反算与无效计数（结果不出门，无副作用）。建议 v1.1 以状态门控跳过以省算力。
3. **WindingTensionCtrl**：`stStat.tRunTime` 以 TIME 累加，49.7 天后到达类型上限。建议 v1.1 改 UDINT 毫秒或注明"需上位定期清零"。
4. **WindingTensionCtrl**：复位沿当拍 eState 先置 eIdle、再经段 10 立即按 bEnable/bRun 回闭环（同拍两个写点，顺序确定）。属"复位后自动重起"设计，建议 v1.1 在头注释明示。
5. **PressFitStation**：`_nEnvPts < 2`（`_bEnvValid=FALSE`）时 `_fUp/_fLo` 未刷新即参与比较，仅 ePress/eDwell 采样且启动校验已拦截非法表，属不可达路径。建议 v1.1 加显式守卫。
6. **RotaryIndexTable**：偏离 D1（增补 `tCycle` 引脚）、D2（分度计数在到位确认拍）已在头注释登记，功能自洽，维持。
7. **AgvDockingHandshake**：偏离 D1（`bHandshakeOk` 口径）、D2（连续两拍替代沿+与门）已登记，维持。
8. **PortDiagAggregator**：`fbTonWindow` 输入取上一拍 `bWinRun`，窗口判定比物理窗口晚一拍；回绕差分按归零处理，跨越回绕点时少计 1 次（V4 口径已定义）。建议 v1.1 在头注释量化该偏差。
9. **StatusWordSegDecoder**：宽度 64 的段仅回送低 32 位，高位静默丢弃。建议 v1.1 增显式"高位截断"标志位，或明确由调用方按宽度自取。
10. **NtcTempScan**：断线 1.2 MΩ / 短路阈值以常量写死，未随通道量程自适应，属设计取舍。
11. **YearWindowCheck**：月 CASE 的 ELSE 在月份钳位后不可达（防御性冗余），保留即可。
12. **RolloverCounter**：`bError` 由上限合法性条件逐拍直接派生（非纯故障锁存变量），对 R21/R24 无违反，但与该库"统一 `_bFaultLatch` 派生"风格略异。
13. **R2rEwmaTuner**：`bAtLimit` 为单拍语义（规格未要求保持），与 V5 的口径一致。
14. **RangeOverlapCheck**：`fOverlapSpan` 为 VAR_OUTPUT 且在 FC 内赋值，IEC 61131-3 合法；跨平台移植时建议抽查一次实参传递。

---

## 六、双签结论

### 总监签（第二签）

R11 十六件逐件完成八项终审：R31 枚举↔CASE 双向完备（16 件全部成员有标签、全部 CASE 有 ELSE 兜底，无引用不存在成员、无重复值）；R32 状态量写入点全拍排序（含 Winding 复位同拍双写点的确定性确认）；R24/R25 单拍标志生命周期（预清零→唯一置位拍→不复写→自清）；R19 首扫范式（16 件均为 `bInit := FALSE` + `IF NOT bInit` + 同步后置 TRUE）；R21 码分级（01xx/1F0x 信息级只写 `uErrorId`，`bError` 一律由故障级或显式降级态派生）；时序与实例刷新（TON/边沿/PID 均在 CASE 外无条件刷新，无同实例多次调用，TIME 量程全部钳位）；边界与量纲（除零、越界、浮点容差、NaN/Inf 穿透、毫米↔米换算、INT/UDINT 溢出逐项核）；验收向量 32 条以上独立手算复核。

发现并当场修复 4 条缺陷（2 致命 / 1 严重 / 1 轻微），全部集中在 DL_Motion 卷绕张力件与 DL_Device 测温件的统计分支。**两条致命缺陷属同一根因的连锁：跟踪计数不递减 → PID 永久跟踪 → 修正恒零；即便补上递减，纯比例下的积分反算残量仍会把修正钉死在零。**这类缺陷机检查不出、单元向量（仅 V3）才暴露，必须写入范式。

判定：**14 件 PASS，2 件修复后 PASS，0 件退回。R11 准予进入阶段六（入库与索引发布）。**

### 编码方签（第一签，引用其自检结论）

编码方自检：`redline_check_r11.py` 十六件全部 PASS（硬缺陷 0、提示 0），并声明已按 R19/R21/R24/R25/R31/R32 逐条落实。本轮终审确认其文本层自检结论属实，但**自检未覆盖"状态量生命周期闭环"与"跨件契约的量值可达性"两类语义缺陷**，故 16/16 机检 PASS 不能等同于终审通过。

### 统计

| 项 | 数量/结论 |
|----|-----------|
| 终审件数 | 16（全查，无抽样） |
| 判定分布 | PASS 14 · 修复后 PASS 2 · 退回 0 |
| 修复件数 | **2**（DL_Motion/FB_DL_WindingTensionCtrl、DL_Device/FB_DL_NtcTempScan） |
| 修复缺陷数 | **4**（致命 2 · 严重 1 · 轻微 1） |
| 版本变更 | 上述 2 件 1.0.0 → 1.0.1，头注释"修订历史"各追加中英两段 |
| 修复后机检 | 2/2 PASS（缺陷 0、提示 0）；全库 16/16 PASS |
| 是否触发 JSONL 重注入 | **是**：`daoli_st_sft_dataset.jsonl` 共 168 条不变，仅第 159 条（FB_DL_NtcTempScan）与第 168 条（FB_DL_WindingTensionCtrl）的 `output` 被整段替换；已逐条复验 `output` 与 `.st` 字节相等；备份 `daoli_st_sft_dataset.jsonl.backup_R11_v101` |
| 是否执行 register_and_jsonl_r11.py | **否**（会重复追加 16 条并误改 7 件，已按任务书禁令规避） |
| INDEX_REGISTRY.json | 未改（16 件已于 2026-11-15T17:55 登记，`total_components=168`，无版本字段，无需变更） |
| ROADMAP.md | 未改 |

---

## 七、范式沉淀（最重要的一条）

**"单拍标志的三律"必须扩展为"状态量生命周期四律"：预清零 → 唯一置位拍 → 递减/消费拍 → 自清。"只置不销"的计数器就是挂在闭环上的定时炸弹。**

R11 在 `FB_DL_WindingTensionCtrl` 上连中两弹：`nTrackSync` 只置位不递减，`bTrack` 恒真把 PID 永久按在跟踪态；补上递减后才发现第二层——纯比例环（`tTi=T#0S`）在"跟踪值 0 + 积分反算"下会把 `fInt` 钉成 `-fP`，误差越大抵消越多，输出恒零。两次都逃过了八条红线机检和编码方自检，只有把 V1~V7 逐条手算到底才现形。

由此确立三条落盘纪律：
1. **凡"剩余拍数/剩余次数"型变量，置位点与递减点必须同文件可见、同段相邻**，评审时先搜变量名全量出现位置，出现次数少于 3（声明+置位+递减）即判可疑。
2. **凡调用带积分/跟踪/手自动切换的下层件，必须核"退出跟踪后的首拍输出"**：拿纸上算一遍 `fInt := fOut - fP - fD` 的残量，判断它是零还是"负比例项"。
3. **凡饱和计数器参与阈值判据，守卫与判据必须同向**：`< MAX` 封顶就必须配 `>= MAX` 判据，写 `> MAX` 等价于把锁存路径整条删除。R11 的 02D1 就是这样静默失活的。

---

*报告生成：2026-11-15 ｜ 终审人：道莅工业代码库产品总监 ｜ 复核方式：全文逐行人工审 + 32 条向量独立手算 + 机检复跑 + JSONL 字节复验*
