# GATE_R95_RECHECK · R95 返修复裁正式裁决（S4 编译闸门官）

- 轮次：**R95 补裁决**（上一轮会话在返修复裁阶段中断，正式复裁结论丢失，本报告为重跑后的唯一有效裁决）
- 裁决人：**S4 编译闸门官 dlf-gatekeeper**（一票否决，唯一有权判 PASS 的席位）
- 裁决对象：`C:\Library\_Staging_Raw\2026-11-25\r95_files.txt` 列出的 **40 件**（DL_Motion 10 / DL_Algo 10 / DL_Base 10 / DL_Device 10）
- 前置事实：S6 已在本轮修 18 处缺陷（涉及 **16 个文件**，mtime 2026-11-26 00:09~00:16，全部核对属实）
- 独立性声明：主控预筛的 40/40 L2 PASS **未被采信**，本报告全部结论由本席独立重跑产出；**未修改任何 .st 业务代码**
- 生成时间：2026-11-26

---

## 一、结论汇总（分层报数，禁合并）

| 口径 | 结果 | 说明 |
|---|---|---|
| 检件数 | **40** | — |
| **PASS** | **39** | 可入库 |
| **FAIL** | **1** | `FC_DL_KcellConstCalc`（原缺陷残留·半修） |
| **EXEMPT** | **0** | 无豁免件（本轮无「编译器自身缺口」型件） |
| **L1 通过率** | **40/40 = 100%** | 0 BLOCK / 0 MAJOR；软项 60 条（MINOR 43 / WARN 17） |
| **L2 通过率** | **40/40 = 100%** | `rc=0`，串行 jobs=1，每件独立 `--no-cache` |
| **L3 通过率** | **机检 0/40（工具缺口）· 代值回验 15/15** | `dl_gate.py --numeric` **不存在**，见 §六 |
| **可入库件数** | **39** | S0 只可入库这 39 件，第 37 件隔离待修 |
| 负向对照命中率 | **4/5** | N5「单等号」双闸漏检，见 §五（闸缺口，非业务缺陷） |
| Inf 闸三者齐全 | **8/8** | 闸断 + 实值出口改写 + 返回 FALSE 全齐 |
| 新增 ENUM 唯一性 | **4/4** | 全库各 1 处定义，无跨件重复 |
| 新引入缺陷 | **1 件 / MINOR** | `FB_DL_SevenSegMultiplexSeq` 码 3 变不可达，见 §四 |

> **一句话结论**：R95 的 40 件中 **39 件通过全部可执行闸口、可入库**；**唯一阻断件是 `FC_DL_KcellConstCalc`，属「S5 修法只落地一半」的原缺陷残留，不是修复引入**；S6 的 18 处修复 **17 处验收通过、1 处引入 1 条 MINOR 诊断缺陷（不阻断、无需返修即可入库，但须挂账）**。

---

## 二、逐件裁决表（40 件）

> L1 列 = `dl_gate.py --file`；L2 列 = `l2_check.py --no-cache`（串行）；错误码列只列**影响判定**的码，软项另注。
> 全部 40 件的共同软项：`VER_HEADER` ×1（MINOR，系统性，见 §七 SYS-1）。

| 序号 | 文件名 | L1 | L2 | 错误码 | 判定 | 备注 |
|---|---|---|---|---|---|---|
| 1 | FC_DL_ArcCenterOffsetCalc | PASS | PASS | — | **PASS** | [#10] Inf 双判 5/5 + 出口双判；fDx=5 / fDy=3.3166 复算一致 |
| 2 | FC_DL_HelicalTurnAdvanceCalc | PASS | PASS | — | **PASS** | 除子 2.0 常量；无 S6 改动 |
| 3 | FC_DL_RtcpPivotOffsetCalc | PASS | PASS | — | **PASS** | Inf 3 参仅 1 参覆盖（MINOR-6 挂账，出口无非有限泄漏） |
| 4 | FC_DL_ToolLengthCompDeltaCalc | PASS | PASS | — | **PASS** | 同上，出口闸齐全 |
| 5 | FC_DL_RotFeedInvTimeCalc | PASS | PASS | — | **PASS** | 除子 `_fRaw` 已由 L33/L34 双域闸证 >0 |
| 6 | FC_DL_SagFeedLimitCalc | PASS | PASS | — | **PASS** | `_fTSec<=0` 显式闸，除零不可达 |
| 7 | FC_DL_SwivelHeadTiltLimitCalc | PASS | PASS | — | **PASS** | `fDtSec<=0` 显式闸；Inf 部分覆盖 MINOR |
| 8 | FC_DL_CornerRoundingRadiusCalc | PASS | PASS | — | **PASS** | [#11] 比率改实际采用进给；除零依赖 0/0→NaN 兜底（MINOR-2，见 §四） |
| 9 | FC_DL_RtcpTrackingErrCalc | PASS | PASS | — | **PASS** | Inf 6 参仅 1 参覆盖（MINOR-6 挂账） |
| 10 | FB_DL_RtcpFiveAxisSeq | PASS | PASS | WARN `DECL_UNKNOWN_TYPE`×4 | **PASS** | [#12] `nAxisMode<>0` 组态闸已落 L134；WARN 为闸对 TYPE 自指的假阳性 |
| 11 | FC_DL_BisectIterStep | PASS | PASS | — | **PASS** | [#13] 段 0 预置 0 + Inf 4/4；三者齐全 |
| 12 | FC_DL_RegulaFalsiIterStep | PASS | PASS | — | **PASS** | `_fDen` 双侧判据；Inf 未覆盖（MINOR-6） |
| 13 | FC_DL_SecantIterStep | PASS | PASS | — | **PASS** | [#14] Inf 4/4 含 fX0/fF0；三者齐全 |
| 14 | FC_DL_IllinoisIterStep | PASS | PASS | — | **PASS** | [#15] Inf 5/5；三者齐全 |
| 15 | FC_DL_GoldenSectionIterStep | PASS | PASS | — | **PASS** | Inf 未覆盖（MINOR-6），无除法 |
| 16 | FC_DL_TernaryNarrowIterStep | PASS | PASS | — | **PASS** | `_fLen<=EPS` 闸；Inf 未覆盖（MINOR-6） |
| 17 | FC_DL_ParabolaVertexIterStep | PASS | PASS | MINOR `DECL_NO_CJK`×3（L27-29） | **PASS** | `_fDx12/_fDx13/_fDx23` 三条注释仅英文；除子三判据齐全 |
| 18 | FC_DL_BrentBracketIterStep | PASS | PASS | — | **PASS** | 三除子均有 `ABS(...)>EPS` 前置 |
| 19 | FC_DL_IterTermJudge | PASS | PASS | — | **PASS** | Inf 2/2 |
| 20 | FB_DL_IterSolverRunner | PASS | PASS | WARN `DECL_UNKNOWN_TYPE`×4 | **PASS** | [#16] 超时狗三相武装已落 L146-149；见 §三-2 误踢量化（MINOR-3） |
| 21 | FC_DL_SevenSegBcdDecode | PASS | PASS | — | **PASS** | 极性口径与 #23 一致（同用 `bCommonAnode`） |
| 22 | FC_DL_SevenSegHexCodeCalc | PASS | PASS | — | **PASS** | — |
| 23 | FC_DL_SevenSegMinusFlagCalc | PASS | PASS | — | **PASS** | [#4] `bCommonAnode` 已落 L17/L35-39/L58-63；共阳实测不灭段（0xF9→0xB9，bit6=0） |
| 24 | FC_DL_SevenSegBlankMaskCalc | PASS | PASS | — | **PASS** | [#1] `_uShiftSrc:BYTE` + `_nShift:INT` 已落 L21-22/L43-46 |
| 25 | FC_DL_SevenSegBrightnessPwmCalc | PASS | PASS | — | **PASS** | `uFullScale=0` 显式闸 L30 |
| 26 | FC_DL_SevenSegBlinkPhaseCalc | PASS | PASS | — | **PASS** | `_nPeriod<=0` 显式闸 L33 |
| 27 | FC_DL_SevenSegMultiplexPhaseCalc | PASS | PASS | — | **PASS** | 双域闸（位/帧）使除零结构不可达 |
| 28 | FC_DL_SevenSegGhostGuardCalc | PASS | PASS | — | **PASS** | 整数除法除子常量 |
| 29 | FC_DL_SevenSegGlyphFontCalc | PASS | PASS | — | **PASS** | [#2] 改用编译期常量界 15（L40/L47/L48），E037×4 已消 |
| 30 | FB_DL_SevenSegMultiplexSeq | PASS | PASS | WARN `DECL_UNKNOWN_TYPE`×4 | **PASS** | [#3] 帧窗锁存已落 L77/L96/L210-212/L225/L119/L233/L240；**修复引入 MINOR：码 3 不可达**（§四 N-1） |
| 31 | FC_DL_PhSlopeEffCalc | PASS | PASS | — | **PASS** | `_fDph` 显式判据 |
| 32 | FC_DL_PhAsymmPotentialCalc | PASS | PASS | — | **PASS** | 除子为常量 |
| 33 | FC_DL_OrpRefOffsetCalc | PASS | PASS | — | **PASS** | [#6] Inf 4/4 + 出口双判；199 mV 复算一致；头注闸序口径不符（MINOR-1） |
| 34 | FC_DL_TurbidityNtuCalc | PASS | PASS | — | **PASS** | [#7] Inf 6/6；NTU=4.2 复算一致 |
| 35 | FC_DL_ChlorineDpdAbsorbCalc | PASS | PASS | — | **PASS** | [#8] Inf 3/3 + `|span|>1E-6` 闸；0.76/1.90 复算一致 |
| 36 | FC_DL_DoSalinityPermCalc | PASS | PASS | — | **PASS** | `_fKt` 分母无除法；Inf 未覆盖（MINOR-6） |
| **37** | **FC_DL_KcellConstCalc** | PASS | PASS | **MAJOR-DOM-1**（温补分母只有下限、无上界） | **FAIL** | **[#9 半修]** `_fDen>10` 域闸未落地，有限越域温度仍报码 0/TRUE（失真 66 倍），见 §四 N-2 |
| 38 | FC_DL_SodiumPnaCalc | PASS | PASS | — | **PASS** | `_fSlope<=0` 显式闸 L73 |
| 39 | FC_DL_AnalyzerRecalDaysCalc | PASS | PASS | — | **PASS** | `_fRate<=EPS` 显式闸 L52 |
| 40 | FB_DL_AnalyzerTwopointCalSeq | PASS | PASS | WARN `DECL_UNKNOWN_TYPE`×5 | **PASS** | [#5] L188 全角括号已改 `*)`；除子为常量 |

> 表内「错误码」为空 = L1/L2 均无 BLOCK/MAJOR/E 码；L2 `rc=0` 且**目标件自身 warning 计数 0**（40 件逐件按路径过滤核查，200 条 E014 全部来自桩文件，非业务件）。

---

## 三、S6 修复重点项逐条验收（历史高发点）

### 三-1 `FB_DL_SevenSegMultiplexSeq`：`tonFrame.IN` 改帧窗锁存 —— **修对，但引入 1 条 MINOR**

| 检查项 | 结论 | 证据（行号） |
|---|---|---|
| 帧首是否真有单拍置位 | **是** | L210-212：`IF _nIdx = 0 THEN _bFrameWin := TRUE`（仅 eBlank 且位索引 0 时） |
| 回卷是否真有单拍清位 | **是** | L225：末位完成 `_nIdx := 0; _bFrameWin := FALSE`；L233 超时、L240 故障、L119 撤使能、L110 首扫共 5 处清位 |
| 置位/清位是否同拍冲突 | **无** | 置位在 eBlank、清位在 eSelect，两相互斥；段 0 定时器先于段 7 状态机执行 → 清位拍 tonFrame 先收到 `IN=FALSE` 完成复位，下一拍才重新武装，**不存在"清位当拍又被置位"** |
| 会不会漏扫 | **不会** | 帧窗只驱动看门狗（L96），**不参与位推进**；位推进只由 L223 `_nIdx>=_nCnt-1` 决定。逐拍仿真 1/2/3/4/8 位：选位序列严格周期 `0,1,…,n-1` 重复，**0 漏位** |
| 首拍会不会误报 `uErrId=3` | **不会** | 首拍 `_bFrameWin=FALSE`（L77 初值）→ L96 `IN=FALSE` → `tonFrame.ET=0/Q=FALSE`；段 0 先于状态机执行，任何 `_bFrameWin:=TRUE` 都发生在 tonFrame 调用**之后**，最早第 2 拍才武装。仿真首拍落在 `eBlank(idx=0)`，码 3 = 0 次 |
| 节拍压力 | **1~50 ms 任务周期下码 3 均为 0 次** | 仿真 6000 拍 × 6 种节拍，位序全周期正确 |
| **新问题** | **码 3 变为不可达（死码）** | L221 `IF tonSlot.Q` 在 L230 `ELSIF tonFrame.Q` 之前；`_tSlotPT = _nSlotMs-_nBlankMs ≤ 10 ms < _tFramePT = 2×10 ms`，两定时器 ET 同速累加 ⇒ tonSlot.Q 恒先成立，ELSIF 恒被短路。见 §四 N-1 |

### 三-2 `FB_DL_IterSolverRunner`：超时狗扩到 eEvalLo/eEvalHi —— **修对，正常求值不会被误踢**

- 武装域：L146-149 `_bTmoArm := (eEvalLo) OR (eEvalHi) OR (eRun)`，`tonTotal(IN := _bTmoArm AND NOT _bFault AND (tTimeout > T#0S), PT := tTimeout)`。
- **不存在"武装当拍即超时"**：移相入 eEvalLo 发生在段 4（tonTotal 调用之后），本拍 IN 仍按旧相（eIdle→FALSE）计算，`ET` 保持 0，下一拍才开始计时；`eDone/eFail/eFault/eIdle` 任一相 IN=FALSE 即复位，重新启动一轮干净。
- **误踢量化（关键）**：`tonTotal` 是**整轮总超时**（不在每迭代复位），每迭代至少占 1 拍 ⇒ 默认 `tTimeout=T#5S` 可容纳 100 拍：
  - 任务周期 **≤ 50 ms** → 100 次迭代 ≤ 5 s，**不会**被码 4 踢掉（典型 10 ms ⇒ 1 s，余量 5 倍）；
  - 任务周期 **> 50 ms** → 未到 `nIterMax=100` 即触发码 4。此属"总超时"语义（真超时，非误判），客户须按节拍放大 `tTimeout` 或设 `T#0S`（不限）。
  - 结论：**典型节拍下正常求值不会被误踢**；仅在慢节拍 + 大迭代上限组合下会提前落码 4，属配置问题，建议在头注补一行"节拍 ≤ 50 ms / 100 次迭代"约束（MINOR-3，不阻断）。
- Inf 闸 3/3（L164-167）；出口非有限落 0（L260-269）。

### 三-3 `FC_DL_SevenSegMinusFlagCalc`：新增 `bCommonAnode` —— **修对，共阳输入真的不灭段**

- 极性归一在 L35-39（`_uBase := uSegCode XOR 16#FF`），叠加在共阴域 L58，回送在 L59-63（`_uOut XOR 16#FF`）；段占用冲突判据也在**归一后的域**上做（L51），不是原始码。
- 代值回验：共阴 `0x06 | 0x40 = 0x46` ✓；共阳 `0xF9 → 归一 0x06 → 叠加 0x46 → 回送 0xB9`，**bit6 = 0（低有效=点亮），未灭段** ✓。
- 契约一致性：`FC_DL_SevenSegBcdDecode` 同用 `bCommonAnode`（L13/L27/L49），口径一致；**全库无调用方**（`grep` 仅命中 BcdDecode 头注声明），新增入参零破坏面。

### 三-4 `FC_DL_CornerRoundingRadiusCalc`：比率改 `fCornerFeedMmMin/60` —— **修对，除零不泄漏（但为隐式兜底）**

- 分母 = `fRadiusMm² · fJerkMaxMmS3`。`fJerkMaxMmS3 ≤ 0` 由 L46 拦截（`> 0`）；`fRadiusMm = MIN(_fRmax, 20)`，`_fRmax = min(段长)/2 · tan(θ/2)`，在 `segLen>0`、`θ∈(0,180)` 下严格 > 0。
- **唯一能令分母为 0 的路径**：段长/夹角带入量级小到 `_fRmax` 下溢为 0（需 ≤1e-308 量级）→ `0/0 = NaN` → L61-62 的 NaN/Inf 双判**立即改写 0**，且 L66-70 出口复检再兜一层，**非有限不会穿出**。
- 判定：**不构成除零阻断**（值不泄漏、码位诚实）；但**缺显式 `IF fRadiusMm > 0` 判据**，且 5 入参**只做 NaN 自反、未做 Inf 差值自减**（L39-41）→ MINOR-2（原缺陷残留 MINOR-7，非新引入）。代值：r=20 mm（硬上限生效）、feed=1000 mm/min、jerkRatio=0.011574 ∈ [0,1] ✓。

### 三-5 8 件 Inf 闸「三者齐全」核查 —— **8/8 齐全**

| 件 | Inf 闸断（行号） | 实值出口改写（行号） | 返回 FALSE（行号） | 齐全 |
|---|---|---|---|---|
| FC_DL_ArcCenterOffsetCalc | L38-45（5 参 NaN+Inf） | L37 `fDx/fDy:=0.0` | L36 预置 FALSE，全部 RETURN 不复位 | ✅ |
| FC_DL_BisectIterStep | L34-36（4 参） | L31 `fAnew/fBnew:=0.0` | L30 预置 FALSE | ✅ |
| FC_DL_SecantIterStep | L37, L40-41（4 参） | L34 `fXnew/fDelta:=0.0` | L33 预置 FALSE | ✅ |
| FC_DL_IllinoisIterStep | L38-39, L43-45（5 参） | L35 `fFaOut/fFbOut:=0.0`、`uSideOut:=0` | L34 预置 FALSE | ✅ |
| FC_DL_OrpRefOffsetCalc | L49-54（4 参） | L45 `fOffsetMv/fRefCorrMv:=0.0` | L44 预置 FALSE | ✅ |
| FC_DL_TurbidityNtuCalc | L41-50（6 参） | L38 `fNtu:=0.0`、`uErrId:=2` | L37 预置 FALSE | ✅ |
| FC_DL_ChlorineDpdAbsorbCalc | L46-50（3 参） | L42 `fChlorineMgL/fSlopeMgLAu:=0.0`、`bOutOfRange:=TRUE` | L41 预置 FALSE | ✅ |
| FC_DL_KcellConstCalc | L44-51（4 参） | L40 `fKcell/fKcellTcorr:=0.0`、`uErrId:=2` | L39 预置 FALSE | ✅（Inf 轴齐全；其 FAIL 在另一轴，见 N-2） |

---

## 四、缺陷清单

### N-1【新引入 · MINOR · 不阻断】`FB_DL_SevenSegMultiplexSeq` L230：码 3 变为不可达（修复引入）

- **成因**：帧窗锁存修复后，`tonFrame` 武装时窗 = 一整帧，但判据仍是 `IF tonSlot.Q … ELSIF tonFrame.Q`；因 `_tSlotPT ≤ _nScanMs < _tFramePT = 2×_nScanMs`，且两定时器每拍同步累加，`tonSlot.Q` **恒先成立**，`ELSIF` 分支永不可达。
- **证据**：结构对读（L221/L230）+ 逐拍仿真 6 种节拍（1/2/3/5/10/20/50 ms）码 3 命中 **0 次**。
- **定性**：**诊断能力归零，但不影响安全性**——eBlank 由 tonBlank 兜底、eSelect 由 tonSlot 兜底，状态机不存在挂死路径，故不是安全问题；修复前是"恒误报"，修复后是"永不报"，方向正确但未收尾。
- **最小修法（2 行，正常时序零行为变更）**：把 eSelect 分支首判改为
  `IF tonFrame.Q THEN _bFault:=TRUE; _uFault:=DL_SSQ_C_TMO; _bFrameWin:=FALSE; _eState:=eFault;`
  `ELSIF tonSlot.Q THEN <原推进逻辑> END_IF`
  （或直接删除码 3 与头注③，改由"各相定时器兜底"表述，避免留死码。）

### N-2【原缺陷残留 · MAJOR · 阻断】`FC_DL_KcellConstCalc` L65：温补分母只有下限、无上界

- **S5 修法要求**（当轮工单 #9）：`_fDen` 加谱上限（如 `> 10` 判非法）并入判据；S6 **只落地了前半**（Inf 双判 L44-51、出口复检 L78-81），**谱上限未加**（L65 仍只有 `<= DL_KCL_DFLOOR(0.01)`）。
- **失效机制（有限输入，非 Inf）**：σ=1413 µS/cm、R=100 Ω、α=2 %/°C、T=3276.7 °C →
  `_fDen = 1 + 0.02×(3276.7−25) = 66.03` → `fKcellTcorr = 0.1413/66.03 = 0.002140 1/cm`（**偏低 66 倍**），而 `uErrId = 0`、返回 **TRUE** —— 典型「假安全出口」（值与判据不同源）。
- **旁证（本席扫全批 22 个除法点）**：其余 21 个除子（`_fLen/_fRaw/_fTSec/fDtSec/_fDen(算法族)/_fDph/_fSlope/_fRate/_fLen(三分)/_fDx12·13·23/fAbsSpan/_fT/_nCnt/_nSlotMs/uFullScale/_nPeriod`）**均有显式非零或双侧判据**；唯本件分母只有单侧下限 → 非普适口径问题，是本件独有缺口。
- **最小修法（1 行）**：`VAR CONSTANT` 增 `DL_KCL_DCEIL : REAL := 10.0;`（对应 T > 475 °C 判非法），L65 改
  `IF (_fDen <= DL_KCL_DFLOOR) OR (_fDen > DL_KCL_DCEIL) THEN _bDen := TRUE; END_IF`
  行为：落码 3、`fKcellTcorr` 回退未修正值、返回 FALSE（与现有 `_bDen` 分支完全一致，零新增分支）；头注 L6-7 同步补"分母域 [0.01, 10]"。

### 挂账 MINOR（不阻断，允许入库后批量清）

| 编号 | 件 | 内容 | 归属 |
|---|---|---|---|
| MINOR-1 | FC_DL_OrpRefOffsetCalc | 头注 L8 称「闸序即归因序（类型 → 非有限 → 温度）」，实现为「非有限 → 类型 → 温度」；因签名无出口码、两者同为 FALSE，**行为无差异**，纯文档口径 | 原缺陷残留（工单 #17 未落地） |
| MINOR-2 | FC_DL_CornerRoundingRadiusCalc | 5 入参仅 NaN 自反、无 Inf 差值自减；除零靠 0/0→NaN 隐式兜底，缺显式 `fRadiusMm > 0` 判据 | 原缺陷残留（MINOR-7） |
| MINOR-3 | FB_DL_IterSolverRunner | 总超时未在头注量化「节拍 ≤ 50 ms / 100 次迭代」的隐含约束 | 边界口径 |
| MINOR-4 | FC_DL_ParabolaVertexIterStep | L27-29 三条声明注释仅英文（`_fDx12/_fDx13/_fDx23`） | 本轮新增发现 |
| MINOR-6 | 13 件 | Inf 双判未全量（清单见 SYS-5），出口闸齐备故无假安全泄漏 | 首裁既定口径，不追溯改判 |

---

## 五、负向对照（投毒回归）：**4/5**

| # | 投毒形态 | L1 判定 | L2 判定 | 命中 |
|---|---|---|---|---|
| N1 | 删 `END_METHOD` | BLOCK `SYN_CROSS_END` L270 | `rc=1 E007 Unexpected token … found METHOD` | ✅ |
| N2 | 声明改名造未声明符号 | BLOCK `F_DECL_MISSING` L43 | `rc=1 E048 Could not resolve reference to _fMid` | ✅ |
| N3 | 删 `END_IF` | BLOCK `SYN_CROSS_END` L74 | `rc=1 E006 Missing expected Token [KeywordEndIf…]` | ✅ |
| N4 | 删 `END_VAR` | BLOCK `SYN_STRAY_END` L82 + `SYN_UNCLOSED`×2 | `rc=1 E007 expected KeywordEndVar` | ✅ |
| N5 | 单 token：`:=` → `=` | **PASS（漏）** | **`rc=0`（漏）**；但编译器实发 `warning[E023] This equal statement has no effect` | ❌ |

- **漏检根因（闸缺口，已定位到工具）**：`l2_check.py` 判定只看 `returncode`（L195-197 / L224 `pass: rc==0`），**warning 完全不参与判据**；`dl_gate.py` 无该语义判据。
- **对业务件的影响：无。** 本席对 40 件做过「语句起点单等号」专项扫查，命中 **0** 处；40 件目标件自身 warning 计数亦为 **0**。
- **建议**：`l2_check.py` 增 `--deny-warnings`（或至少把 warning 计数写入 report，`verdict=BLOCK` 阈值可配），并补 N5 为第 6 个固定反例。

---

## 六、L3 工具缺口（必须记录，不得用文本机检冒充）

- 本席规范要求 `python dl_gate.py --numeric`，实测 **`dl_gate.py` 的 argparse 无 `--numeric` 参数**（仅有 `--all/--changed-only/--hours/--file/--round/--strict-decl/--selftest/--json-out/--fix-structural/--apply`）→ **L3 机检在本机不可执行**，报 0/40 机检，不虚报。
- 补救口径：按各件源文件公式**外部脚本复算**（不执行 ST、不改业务码），覆盖 8 个含除法/系数的件，**15/15 量纲与量级一致**：

| 件 | 代值 | 复算 | 判定 |
|---|---|---|---|
| CornerRoundingRadius | θ=90°, 段长 50/50, feed 1000 mm/min, jerk 1000 mm/s³ | r=20 mm、v=73.68 mm/s、feed=1000 mm/min、ratio=0.011574 | 一致 |
| KcellConst | 1413 µS/cm, 100 Ω, T=35, α=2 | 0.1413 → 0.11775 1/cm；**另 T=3276.7 → 0.002140（低 66×，码 0）** | 公式一致 / 域闸缺 |
| OrpRefOffset | 199 mV, 25 °C / 35 °C | 199 mV / 201 mV | 一致 |
| TurbidityNtu | 800/400/0, K=2, Zero=0.2 | 4.2 NTU | 一致 |
| ChlorineDpdAbsorb | 0.40/0.02/1.00, 档 0 / 1 | 0.76 / 1.90 mg/L | 一致 |
| ArcCenterOffset | (0,0)-(10,0), R=6 | dx=5、dy=3.3166 mm | 一致 |
| SevenSegMinusFlag | 0x06 共阴 / 0xF9 共阳 | 0x46 / 0xB9（bit6=0 点亮） | 一致 |
| SevenSegBlankMask | 位数 3 | 0x07 | 一致 |

---

## 七、系统性发现（同一根因 ≥3 件）

**SYS-1｜`VER_HEADER` ×40（100% 命中，MINOR）**：全部件头注用 `｜ v1.0.0 ｜` 写法，无 `VERSION: x.y.z` 字样，`dl_gate.py` L339 正则要求 `VERSION\s*[:：]` → 40 件全判 MINOR。判定层不阻断（MINOR rank=2），但**"版本头合规"指标永久为 0，监测价值归零**。修法二选一：①E2 批量在头注加一行 `VERSION: 1.0.0`（40 件一次改完）；②放宽闸判据为 `v?(\d+\.\d+\.\d+)` 并**先跑 `--selftest` 回归**（当前 10 反例 + 6 正例必须仍全过）。

**SYS-2｜桩侧 `E014` ×200（5 条/件 × 40）**：全部来自 `_iface_stubs/_all_types.st`（L133/L134/L154）与 `I_DL_BarcodeScanner.st`/`I_DL_DeviceHealth.st` 的 `STRING(…n…)` 写法（RuSTy 建议 `STRING[…]`）。**非业务缺陷**，但会让未来真正的目标件告警被噪声淹没。修法：`iface_stub_gen.py` 生成 `STRING[...]`。

**SYS-3｜L2 判据只看 `returncode`（N5 实证漏检）**：见 §五。属闸自维护项，建议本轮后立单。

**SYS-4｜`dl_gate.py --numeric` 不存在**：人格/分派说明与实际工具漂移，L3 名存实亡。建议 S0 立"L3 数值回代机检化"单（输入：`_TESTS/<Name>.json` 的典型值 + 源文件公式；输出：量纲量级断言）。

**SYS-5｜Inf 双判覆盖不均**：30 个浮点件中全量 11 件 / 部分 6 件 / 全缺 13 件（全缺：HelicalTurnAdvance、RotFeedInvTime、SagFeedLimit、CornerRoundingRadius、RegulaFalsi、GoldenSection、TernaryNarrow、ParabolaVertex、BrentBracket、PhSlopeEff、DoSalinityPerm、SodiumPna、AnalyzerRecalDays）。因各件**出口双判齐备、无假安全泄漏**，本轮按首裁口径记 MINOR 不追溯；但建议按 SYS-4 同单扩面。

**SYS-6｜L1 对 `TYPE…END_TYPE` 自定义类型自指判为未识别**（4 件 `DECL_UNKNOWN_TYPE` 共 17 条 WARN）：`0: … : E_DL_*` 引用本文件 TYPE 块的枚举类型时，`declared` 集合未收 TYPE 名。仅 WARN 不阻断，建议闸把 `TYPE <Name>` 并入 `declared`。

---

## 八、复现命令（每个数字均可复算）

```bash
# L1 逐件（40 次；本报告落在 _r95recheck_l1/NN.json）
python C:\Library\_tools\dl_gate.py --file C:\Library\<category>\<name>.st --round R95RECHECK --json-out <NN>.json

# L2 逐件串行、强制无缓存（jobs 默认 1；严禁 >1）
python C:\Library\_tools\l2_check.py C:\Library\<category>\<name>.st --no-cache

# 目标件自身 warning 审计（过滤桩侧告警）
_tools/rusty/plc.exe --check --error-format clang _tools/rusty/iec_std_stub.st \
  _tools/rusty/_iface_stubs/_all_types.st _tools/rusty/_iface_stubs/I_DL_*.st C:/Library/<file>

# 负向对照
for f in _r95recheck_negctl/N*.st; do python C:\Library\_tools\dl_gate.py --file "$f"; \
  python C:\Library\_tools\l2_check.py "$f" --no-cache; done

# ENUM 唯一性
grep -rn "^TYPE E_DL_RtcpSeqPhase\|^TYPE E_DL_IterRunnerPhase\|^TYPE E_DL_SevSegScanPhase\|^TYPE E_DL_AnalyzerCalPhase" DL_*/
```

产物：`_r95recheck_l1/`（40 份 L1 JSON）、`_r95recheck_l2.log`（40 行 rc）、`_r95recheck_warn.log(.detail)`（告警审计）、`_r95recheck_negctl/`（5 投毒样本）。

---

## 九、派工（本席结论直接派单，不经 S3）

1. **S6（阻断件，回本席复裁须 `--no-cache`）**：`FC_DL_KcellConstCalc` —— 按 N-2 一行修法补温补分母上界 + 头注同步。**只此一件**，其余 39 件不得被顺带改动。
2. **S6（MINOR 批，可随下轮）**：N-1（SSQ 码 3 判据上移或删码 3）、MINOR-1/2/4 注释与判据收尾。
3. **S0（执行侧）**：**只可入库 39 件**；第 37 件 `FC_DL_KcellConstCalc` 隔离（不得进 JSONL、不计产出），S6 修完经本席 `--no-cache` 复裁后方可入库。
4. **S0（工具侧）**：SYS-1/SYS-2/SYS-3/SYS-4 立单（闸自维护，不得由业务席代劳）。
