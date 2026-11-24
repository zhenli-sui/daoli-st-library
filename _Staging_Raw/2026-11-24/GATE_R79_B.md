# GATE_R79_B —— R79 批 2 编译闸裁决（闸席本人产出，一票否决）

- 轮次：R79 / **批 2**｜日期：2026-11-24｜裁决人：编译闸席 dlf-compile-verifier
- 环境：RuSTy（`_tools/l2_check.py`，**jobs=1 全程串行**，接口预筛 22/22、缓存命中）+ 自研 L1 静态门（`_tools/dl_gate.py`，selftest 已过）
- 复现命令（每个数字可复跑）：
  - 桩：`python C:\Library\_tools\stub_fix.py --full` → 桩自校验通过
  - L2：`python C:\Library\_tools\l2_check.py <file1> <file2> ...`（4 批：E8 / F8 / H12 / G4+I7）
  - L1：`python C:\Library\_tools\dl_gate.py --file <file>`（39 次逐件）
  - 数值复算：`python` 脚本镜像各件算法（见正文引用）

## 一、门禁原始输出（不可省）

| 批次 | 命令 | 输出 |
|---|---|---|
| E 统计扩展族 8 件 | `l2_check.py DL_MathData/FB_DL_Stats*.st FC_DL_Stats*.st` | `PASS=8 FAIL=0 TOTAL=8` |
| F 校验和族 8 件 | `l2_check.py DL_Algo/FC_DL_Chk*.st` | `PASS=8 FAIL=0 TOTAL=8` |
| H 替换批 12 件 | `l2_check.py DL_MathData/(Cal/Int/Geo/Stats 12 件)` | `PASS=12 FAIL=0 TOTAL=12` |
| G 复杂工艺件 4 件 | `l2_check.py DL_Process/FB_DL_(Cooling/Screw/Press/Aeration)*.st` | `PASS=4 FAIL=0 TOTAL=4` |
| I 修复复验 7 件 | `l2_check.py DL_Device/... DL_Process/... DL_MathData/Cal*4` | `PASS=7 FAIL=0 TOTAL=7` |
| L1 静态 39 件 | `dl_gate.py --file` × 39 | 逐件 `PASS 1 / MAJOR 0 / BLOCK 0` |

> L2 说明：本机 RuSTy 可用，**本轮 L2 为实测 39/39 PASS，非 pending-ci**。E004 假阳性规避：全程 jobs=1，无并行。

## 二、逐件裁决表（E 8 / F 8 / G 4 / H 12 / I 7）

图例：L1 复核五列 = **a** 除零·取模零闸｜**b** DINT/UDINT 溢出与 `-x`｜**c** 死谓词·NaN/Inf 判据｜**d** 数组下标域｜**e** 返回值与 bError/bValid 出口完整性。✓ 通过／✗ 有缺陷／— 不适用。

### E. 统计扩展族（DL_MathData）

| # | 文件 | 结论 | 错误码 | a | b | c | d | e | L1 行号证据 | 建议动作 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | FB_DL_StatsWelfordVar | PASS（MINOR） | 零码位恒 0 | ✓ | ✓ | ✓ | — | ✓ | 非有限双判 L81（`fSample<>fSample` + `ABS>DL_FIN_LIM=1E308`）；除数 L84 先自增再除（n≥1）；样本方差分母 L107-111 有 `nAcc>1` 支路 + 兜底；负偏归零 L112-114；CASE ELSE L125 | 入库。MINOR：fM2 为大样本时 LREAL 可至 Inf，输出 Inf 且 bValid=TRUE（契约未要求，挂账） |
| 2 | FB_DL_StatsSkewKurtStream | PASS（MINOR） | 零码位恒 0 | ✓ | ✓ | ✓ | — | ✓ | 非有限双判 L94；n≥1 由 L97 先自增保证；L126 `fM2 > DL_M2_MIN` 防 `M2^1.5` 除零；零方差支路 L129-131 置 0；CASE ELSE L141 | 入库。MINOR：`fM4` 为 x⁴ 量级，输入 1e100（合法域内）即溢出 LREAL → L128 得 NaN 且 bValid=TRUE；建议记录「四阶量需输入量级 ≤1e77」或加输出有限性复核 |
| 3 | FC_DL_StatsMadFixed | PASS（MINOR） | 零码位恒 0 | ✓ | ✓ | **✗** | ✓ | ✓ | 点数钳位 L57-59；`nUse<1`→bError L60-63；下标 L66/69-77 全在 1..nUse≤10（数组 `ARRAY[1..10]`）；中位下标 L81/84 证不越界 | 入库。MINOR：**无入参 NaN/Inf 闸**，排序比较对 NaN 恒假 → NaN 可落到中位并被 bValid=TRUE 输出（同族 TrimmedMean 同缺） |
| 4 | FC_DL_StatsTrimmedMeanFixed | PASS（MINOR） | 零码位恒 0 | ✓ | ✓ | **✗** | ✓ | ✓ | 截尾上限 L69-71 `nTrim ≤ (nUse-1)/2` → L72 `nKeep = nUse-2·nTrim ≥ 1`；除数 L95 已证 ≥1；求和区间 L90 `1+nTrim .. nUse-nTrim` 恒在 1..10 | 入库。MINOR：同上，无 NaN/Inf 入参闸 |
| 5 | FC_DL_StatsPercentileRankFixed | PASS | 零码位恒 0 | ✓ | ✓ | ✓ | ✓ | ✓ | 点数钳位 L?+百分位整形段 2；最近秩 `nRank` 由实数秩取整后钳到 1..nUse；插入排序下标 1..10 定长（同 #3/#4 模板）；`DL_PCT_DIV=100` 为常量 | 入库（同族三个 FC 建议统一补「入参非有限拒绝」口径） |
| 6 | FC_DL_StatsZScoreClamp | PASS | 零码位恒 0 | ✓ | ✓ | ✓ | — | ✓ | 四参 NaN 闸 L50-53；量级闸 L54-57（`ABS>1E308`）；限幅整形 L60-63 恒正；零标准差闸 L66-69 先于除法 L72；超 Inf 的 z 被 L73-79 限幅兜住 | 入库（本件是统计族非有限判据的正确范式） |
| 7 | FC_DL_StatsHistogramBin | PASS | 零码位恒 0 | ✓ | ✓ | ✓ | ✓ | ✓ | 桶数闸 L51-54、桶宽闸 L55-58（**先于除法 L77**）；NaN 闸 L59-62；量级闸 L63-66；负数偏移钳首桶 L70-74；取整前 L78 `fIdx >= nBins` 兜底防取整溢出，钳末桶 L79 | 入库 |
| 8 | FC_DL_StatsRunLengthMax | PASS | 零码位恒 0 | ✓ | ✓ | ✓ | ✓ | ✓ | 点数钳位 L?；容差 NaN/Inf 双判（`fTol<>fTol` + `ABS>DL_FIN_LIM`）；下标 2..nUse≤10；`nRun/nBest` 最大值 ≤ nUse | 入库（样本数组本身无 NaN 闸，与 #3/#4 同挂账） |

### F. 校验和族（DL_Algo，8 件全部同构：定长 `ARRAY[1..16] OF BYTE` + `nLen` 双向钳位）

| # | 文件 | 结论 | 错误码 | a | b | c | d | e | L1 行号证据 | 建议动作 |
|---|---|---|---|---|---|---|---|---|---|---|
| 9 | FC_DL_ChkFletcher16 | PASS | 零码位恒 0 | ✓ | ✓ | — | ✓ | ✓ | L54-59 `nUse` 钳到 0..16；L62 `FOR i:=1 TO nUse` → 下标 1..16 不越界；L63-64 模数 `DL_MOD255=255` 常量（模零不可达），每步归一故累加值 <255 | 入库 |
| 10 | FC_DL_ChkFletcher32 | PASS | 零码位恒 0 | ✓ | ✓ | — | ✓ | ✓ | 字数 L? 奇数向上取整；`nLo=aData[k*2-1]`、`nHi=aData[k*2]` 由 `nIdx` 判偶尾补 0；模数 `DL_MOD16=65535` 常量 | 入库（建议向量补「奇数长度尾字节」case） |
| 11 | FC_DL_ChkXor8 | PASS | 零码位恒 0 | — | — | — | ✓ | ✓ | L? 钳位后 `FOR 1..nUse`；BYTE 域 XOR 天然模 256；空块 bValid=TRUE 返回 0（异或单位元） | 入库 |
| 12 | FC_DL_ChkSum8 | PASS | 零码位恒 0 | ✓ | ✓ | — | ✓ | ✓ | UDINT 宽域累加（16 字节 ≤4080 不溢出）；出口 L? `UDINT_TO_BYTE(nSum MOD 256)` 先取模再收窄 | 入库 |
| 13 | FC_DL_ChkTwosCompSum16 | PASS | 零码位恒 0 | ✓ | ✓ | — | ✓ | ✓ | 字累加 ≤8×65535 不溢出；`nLow16` 取低 16 位后做二进制补码；奇数尾高字节补 0 | 入库 |
| 14 | FC_DL_ChkSum32Mod | PASS | 零码位恒 0 | ✓ | ✓ | — | ✓ | ✓ | L67 `nTerm ≤ 255×2^24 = 16#FF00_0000 < 模数`；L68-72 「加后即时归约」等价 `(nAcc+nTerm) MOD 2^32` 且无中间溢出；L73-77 权值到 `DL_SHIFT_MAX` 回 1，回绕前先判 | 入库 |
| 15 | FC_DL_ChkParityBlock | PASS | 零码位恒 0 | ✓ | — | — | ✓ | ✓ | 位提取 `nByte MOD 2` 循环 8 次（常量）；`nOnes` 上界 16×8=128；返回偶校验布尔 + `nBitOnes` 诊断出口 | 入库 |
| 16 | FC_DL_ChkAdler32 | PASS | 零码位恒 0 | ✓ | ✓ | — | ✓ | ✓ | A/B 每步 `MOD DL_MOD65521`（常量），累加前值 <65521 故 `+255` 不溢出；空块返回初值 1（与 zlib 一致，实测 `adler32("ABC")=26017991` 与本件算法逐位相同） | 入库（族内最规范一件） |

### G. 复杂工艺件（DL_Process，四问逐条回答）

| # | 文件 | 结论 | 错误码 | ① 故障相可达出口 | ② 等待相超时兜底 | ③ CASE 有 ELSE | ④ 定时器在 CASE 外 | 建议动作 |
|---|---|---|---|---|---|---|---|---|
| 17 | FB_DL_CoolingTowerFanStageSeq | PASS | 零码位恒 0 | ✓ L460 `_bResetPulse AND NOT bEnable` → 清锁存/成因/时长/主用 → eIdle | ✓ `tonSpin`(L220) 管启动确认、`tonGap`(L216) 管级间节拍且 IN 含 eStartup/eStageUp/eStageDown/eRotate 四相（无死锁相）、`tonNoFb`(L237) 管全无反馈 | ✓ L469 | ✓ 段 4（L214-238）全部在 `CASE`(L241) 之前；CASE 内零定时器调用 | 入库 |
| 18 | FB_DL_ScrewConveyorDoseSeq | PASS | 零码位恒 0 | ✓ L344-355 `_bResetPulse AND NOT bEnable`，故障相 `bMotorRun:=FALSE` | ✓ `tonTotal`(L226) 总超时、`tonNoFlow`(L228) 零流量、`tonMotFb`(L234) 反馈不一致、`tonSettle`(L231) 停料稳定 | ✓ L355 | ✓ 段 4（L222-236）在 `CASE`(L247) 前 | 入库 |
| 19 | FB_DL_PressForceCurveExec | PASS | 零码位恒 0 | ✓ L347-357 `_bResetPulse AND NOT bEnable`，故障相 `fForceCmd:=0` | ✓ `tonSeg`(L235) 单段到力超时（IN 含 `NOT _bSegReset` 自清）、`tonDt`(L231) 采样节拍 | ✓ L359 | ✓ 段 5（L229-238）在 `CASE`(L240) 前 | 入库（c 列见下「类缺陷 C1」） |
| 20 | FB_DL_AerationBlowerCycle | PASS | 零码位恒 0 | ✓ L370-383 `_bResetPulse AND NOT bEnable`，故障相台数清 0 且命令全撤 | ✓ `tonBlowOn`(L218)/`tonBlowOff`(L220) 最短曝气·停曝、`tonDoStuck`(L237) DO 冻结、`tonBlowerFb`(L235) 单台无反馈 | ✓ L386 | ✓ 段 4（L216-240）在 `CASE`(L242) 前 | 入库（c 列见「类缺陷 C1」） |

### H. 替换批（DL_MathData，12 件）

| # | 文件 | 结论 | 错误码 | a | b | c | d | e | L1 行号证据 | 建议动作 |
|---|---|---|---|---|---|---|---|---|---|---|
| 21 | FC_DL_CalAddMonths | PASS | 零码位恒 0 | ✓ | ✓ | ✓ | — | ✓ | `nDelta` 域 `|Δ|≤1200` + 结果年 1..9999 域闸；`(m-1+Δ)` 用整数除/取模分解，无大数乘；结果日按结果月长钳位 | 入库 |
| 22 | FC_DL_CalDateSpanMonths | PASS | 零码位恒 0 | ✓ | ✓ | ✓ | — | ✓ | 双日期各自域闸后 `Δ = (yB-yA)*12 + (mB-mA)`，|Δ|≤9999*12 在 DINT 内 | 入库 |
| 23 | FC_DL_IntLcmSafeUdint | PASS | 零码位恒 0 | ✓ | ✓ | ✓ | — | ✓ | 零入参短路 L?；欧几里得 `nY≠0` 保证 `MOD` 安全 + `nIter<DL_GUARD=64` 守卫；先除 L? `nQ=nA/nG`（nG≥1）；乘前反算 L? `nQ > DL_UMAX/nB` → 饱和+bError | 入库 |
| 24 | FC_DL_IntIsPrimeUdint | PASS | 零码位恒 0 | ✓ | ✓ | ✓ | — | ✓ | `nVal<2`/`=2`/偶数三路短路；试除判据写作 `nD <= nVal/nD` **等价 nD²≤nVal 但永不溢出**（正确范式）；nD≥3 故除零不可达 | 入库 |
| 25 | FC_DL_IntModPowUdint | PASS | 零码位恒 0 | ✓ | ✓ | ✓ | — | ✓ | `nMod=0`→bError、`nMod=1`→合法 0；`nPow=nBase MOD nMod`（≥2 已证）；位积两路均「加后即时归约」：`nAccR >= nMod-nAdd` 支路恒落 [0,nMod)，故 32 位全循环不溢出；`nDbl` 倍增同款归约 | 入库（模幂族正确范式） |
| 26 | FC_DL_IntFloorLog2Udint | PASS | 零码位恒 0 | ✓ | ✓ | — | — | ✓ | 零入参→`bError=TRUE` + `-1` 哨兵 + `bValid=FALSE`（三出口齐）；`WHILE nW>1` 除常量 2，≤32 步收敛 | 入库 |
| 27 | FC_DL_IntNextPrimeUdint | PASS | 零码位恒 0 | ✓ | ✓ | ✓ | — | ✓ | 上界保护带 `nVal ≥ DL_NEAR(16#FFFF_FFF0)` → bError（防 `+1` 回绕）；候选步数预算 `nStep` + `bFound` 双出口 | 入库 |
| 28 | FC_DL_GeoChordHeightCalc | PASS（MINOR） | 零码位恒 0 | ✓ | ✓ | **✗** | — | ✓ | NaN 自反判 L?；域闸 r>0、c>0、`c ≤ 2r+DL_TOL` 均在 SQRT 前；判别式 `r²-(c/2)²` 负值归零 L?（防 SQRT 得 NaN） | 入库。**MINOR→MAJOR 见类缺陷 C1**：Inf 判据用 `fDiff:=fRadius-fRadius` 再比 0，被折叠后 `fRadius=Inf` 可产出 `Inf-Inf=NaN` 且 bValid=TRUE |
| 29 | FC_DL_GeoCircleSectorArea | FAIL（MAJOR·回派） | 零码位恒 0 | ✓ | — | **✗** | — | ✓ | 角度归一 L? `TRUNC(θ/360)` 后补圈到 [0,360)；半径闸 L?；但 **L54 是本件唯一的 Inf 闸**且为 `(fRadius-fRadius)<>DL_ZERO` 形态（见 C1），无下游第二道闸 → `fRadius=1E308`（合法域）→ `r²=Inf` → 输出 Inf 且 bValid=TRUE | 回派：L54 改 `ABS(fRadius) > 1.0E308` / `ABS(fAngleDeg) > 1.0E308`；并对面积出口补有限性复核 |
| 30 | FC_DL_GeoPointRotateXY | FAIL（MAJOR·回派） | 零码位恒 0 | ✓ | — | **✗** | — | ✓ | 五参 NaN 自反判；**L63 `(fPx-fPx)<>DL_ZERO` 为本件唯一 Inf 闸**；Inf 经 SIN/COS 变 NaN 后直接出 fOx/fOy，无第二道闸 | 回派：L63（及 fPy/fCx/fCy 同形）改 `ABS(...) > 1.0E308`；出口补有限性复核 |
| 31 | FC_DL_StatsCoeffVarCalc | FAIL（MAJOR·回派） | 零码位恒 0 | ✓ | ✓ | **✗** | — | ✓ | `DL_MIN=1E-9` 近零均值闸先于除法（除零已拦）；负标准差拒收；**L50 `(fMean-fMean)<>DL_ZERO` 为唯一 Inf 闸**，`fMean=Inf` 时 `fAbsMean=Inf ≥ DL_MIN` 通过 → `σ/Inf = 0` 被当合法 CV 输出 | 回派：L50 改 `ABS(fMean) > 1.0E308` / `ABS(fStd) > 1.0E308` |
| 32 | FC_DL_StatsEntropyCalc | PASS（MINOR） | 零码位恒 0 | ✓ | ✓ | **✗** | ✓ | ✓ | `nCnt` 1..8 域闸 L54-57（下标不越界）；元素 NaN 自反判 L62、负概率 L66 拒收；总和 `fSum<=DL_EPS`→bError L74-77 防 `q=p/Σp` 除零；log 前 L86 `p>DL_EPS` 防 log(0) | 入库。MINOR：L66/L78 用 x−x 判 Inf，但 L78 的 `fSum` Inf 闸构成第二道网，后果限于「晚一拍报错」，非漏闸 |

### I. 修复复验（7 件，逐件验「真修好」）

| # | 文件 | 结论 | 复验要点（行号证据） | 建议动作 |
|---|---|---|---|---|
| 33 | FB_DL_AnalogSensorHealthClassify（P1） | PASS（MINOR） | **P1 确已修好且未破坏「逐拍即时判」**：① 即时判仍在采样相同一拍完成——L231-241 `fValue > fRangeMax+DL_ASC_EPS` 当拍即写 `eHealth:=eOverHigh` + `nConfidence:=10`（V3 向量成立）；② 窗级判改为 L270-275 用窗极值 `_fWinMax>fRangeMax` / `_fWinMin<fRangeMin` **重算**标志，故不再依赖已被段 1（L162-163）清掉的单拍位；③ 标志随窗清零 L308-309，作用域闭合；④ L248 `_nCnt<1` 前置防除零 L258-259 | 入库。MINOR：窗级判据 L270/273 未带 `DL_ASC_EPS` 容差，与即时判（带容差）口径不一：样本落在 `(fRangeMax, fRangeMax+EPS]` 时即时判不报、窗末却报 eOverHigh → 建议 L270/L273 统一加容差。MINOR：L166-170 Inf 判据为 x−x 形态（见 C1），本件有 L231/236 超量程闸兜住，非漏闸 |
| 34 | FC_DL_IntPowSatUdint（P2） | **FAIL（MAJOR·回派）** | **P2 未修好，且引入新缺陷**。L77-79 只补了 `nIter >= DL_ITER_MAX` 一支，未修根因（L70-72 底数平方饱和平支内未置 `bOverflow`）。脚本逐例复算（`_tmp_r79/p2_probe.py`）：<br>· `(2,32)`→ res=MAX, **bOverflow=FALSE**（iter=6，真值 2³²>MAX 应饱和）→ **漏报**<br>· `(3,32)`→ 同上 **漏报**<br>· `(65536,2)`→ 同上 **漏报**<br>· `(1,2^31)`→ res=1（精确），**bOverflow=TRUE**（iter=32 触顶）→ **误报**<br>· `(0,2^31)`→ res=0（精确），**bOverflow=TRUE** → **误报**<br>数值侧 13/13 例与真值一致，**只有标志位双向错** | 回派两条最小改动：① L71 `nBaseUse := DL_MAX_UDINT;` 之后补 `bOverflow := TRUE;`（该分支饱和必致后续乘出界，不会误报）；② L77 判据改 `IF nExpUse > DL_ZERO THEN bOverflow := TRUE;`（真正的「未收敛」判据是循环退出时指数未尽，而非迭代计数触顶） |
| 35 | FB_DL_MultiZoneSetpointScheduler（P3） | **FAIL（MAJOR·回派）** | **P3 本次改动本身正确、`bError` 出口无遗漏**：L285-292 在 `_rtReset.Q` 时同拍清 `_bFaultLatch` / `_eCauseLatch` / `eCause` / `nFaultZone`，而 `bError` 是**派生式**（L321 `bError := _bFaultLatch`），故随锁存同步落 FALSE，无需单独清点；L293 `NOT _bFaultLatch AND (_bBoundary OR _rtReset.Q)` 保证清锁存后必回 eApply 重校验，不存在「清了锁存却留在 eHold」的空档。<br>**但批 1 的 P3（x−x Inf 漏闸）未落地**：L218-219 仍为 `(fSetpoint - fSetpoint) <> DL_MZS_FZERO`，本件全文件**无第二道有限性闸**（写入 afActiveSp 后下游直接消费） | 回派：L218-219 改 `OR (ABS(aSlots[_nZ][_nK].fSetpoint) > DL_MZS_FIN)`（新增 `DL_MZS_FIN : REAL := 1.0E308`），删 x−x 子句。另：版本头 L3 仍 `1.0.0`、修订历史止于 v1.0.1，而正文已标 v1.0.2（MINOR） |
| 36 | FC_DL_CalDayOfYear（P4） | PASS | L29 新增 `DL_GREG_LAST := 9999`；L57 域闸 `((nYear < DL_GREG_START) OR (nYear > DL_GREG_LAST))`。溢出复算：上界年时 L84 最大中间量 `365*(9999+4799)=5,401,270 ≪ DINT_MAX` ✔（脚本已验）。数值抽验：2024-03-01→61、2023-12-31→365、2024-12-31→366 ✔ | 入库。MINOR：版本头 L2 `v1.0.0` 与 L29 注释「v1.0.1 补」不一致，修订历史缺 v1.0.1 条 |
| 37 | FC_DL_CalDateFromDayOfYear（P4） | PASS | L29 常量、L63 上界闸同上；逐月递减 L71-86 无大数乘；边界：闰年 366 → (12,31)、1 → (1,1) 路径核对通过（`nRem > nMonthDays` 严格大于，12 月残 31 不推进，月份止于 12） | 入库。MINOR：版本头同 #36 |
| 38 | FC_DL_CalIsWeekend（P4） | PASS | L31 常量、L61 上界闸；JDN 上界 5,401,270 级安全；`nDow := nJdn MOD 7`，`nDow ≥ 5` 判周末。抽验：2024-03-01 JDN mod 7 = 4（周五，非周末）、03-02 = 5（周六）✔ | 入库。MINOR：版本头同 #36 |
| 39 | FC_DL_CalMonthEndDate（P4） | PASS | L28 常量、L51 上界闸；月长选择 L60-69 覆盖 2 月/30 天月/其余，无越界路径 | 入库。MINOR：版本头同 #36（四件同源，建议一次性把 4 件的头标与修订历史补到 v1.0.1） |

## 三、类缺陷（跨件，单列以免漏派）

**C1（MAJOR，安全侧）｜`(x − x) <> 0` 作 Inf 判据，共 9 件 20 处**
`grep` 复现：本批 39 件内命中 20 处 —— FC_DL_GeoCircleSectorArea:54、FC_DL_GeoPointRotateXY:63、FC_DL_StatsCoeffVarCalc:50、FC_DL_StatsEntropyCalc:66/78、FB_DL_AerationBlowerCycle:190/191/192、FB_DL_MultiZoneSetpointScheduler:219、FB_DL_PressForceCurveExec:188/192/197、FB_DL_ScrewConveyorDoseSeq:189/190/191、FB_DL_AnalogSensorHealthClassify:166-170。
- 判据本身在严格 IEEE-754 下可用（Inf−Inf=NaN，NaN≠0 为真），**但库内 R77 已定案其为「死谓词、优化编译可能常量折叠」**，且 FC_DL_IntSignExtractLreal 头注释自述采用 `ABS(x)>1.0E308` 才是库内范式 → **同库两套写法并存本身即不合格**（R478）。
- 分级：**MAJOR（回派）**＝该 Inf 闸是唯一闸且下游无第二道网：GeoCircleSectorArea、GeoPointRotateXY、StatsCoeffVarCalc、MultiZone:219、PressForceCurveExec、ScrewConveyorDoseSeq、AerationBlowerCycle（7 件）；**MINOR（挂账）**＝有第二道网截住：StatsEntropyCalc（L78 fSum 闸）、AnalogSensorHealthClassify（L231/236 超量程闸）、GeoChordHeightCalc（域闸 `c≤2r+tol` 与判别式归零）。
- 统一修法：`ABS(x) > 1.0E308`（各件已有或可加 `DL_*_FIN` 常量），删 x−x 子句。

**C2（MINOR）｜定长数组族缺「样本非有限」拒绝口径**：FC_DL_StatsMadFixed / TrimmedMeanFixed / PercentileRankFixed / RunLengthMax 只闸点数与容差，未闸 `aVals[*]` 本身的 NaN/Inf；NaN 参与比较恒假，可落到中位并被 bValid=TRUE 输出。建议同族统一在段 2 加逐点 `x<>x` / `ABS>1.0E308` 拒绝。

**C3（MINOR）｜修复件版本头未随修复上调**：AnalogSensorHealthClassify（头 1.0.2 / 修订历史止 v1.0.0）、MultiZone（头 1.0.0 / 正文标 v1.0.2）、日历 4 件（头 v1.0.0 / 常量注释标 v1.0.1）。同 R479 三步法第三步。

## 四、汇总

**本批 39 件｜PASS 36｜FAIL 3｜EXEMPT 0｜通过率 92.3%**

- L2：**39/39 PASS**（实测，非 pending-ci）；L1 静态：39/39 PASS / BLOCK 0
- **FAIL（阻断入库，回派编码专家）3 件**：#34 FC_DL_IntPowSatUdint（P2 未修好 + 新增误报）、#29 FC_DL_GeoCircleSectorArea、#30 FC_DL_GeoPointRotateXY、#31 FC_DL_StatsCoeffVarCalc（C1 唯一闸）—— 计 3 类 4 件，其中 #34 与 #35 属「已修但未修好/未落地」，**修复件不通过即整批不得入库**
- **MAJOR 合计 8**：#34、#35（P3 原始缺陷仍在）、#29、#30、#31 + C1 内 MultiZone:219 / PressForceCurveExec / ScrewConveyorDoseSeq / AerationBlowerCycle（其中 MultiZone 与 #35 同一件，去重后 7 件）
- MINOR 合计 11（#1 #2 #3 #4 #33 ×2 #36 #37 #38 #39 + C2/C3）
- EXEMPT：**0**（无一件属「编译器不支持但合法的 IEC 语法」）
- 就地修复：**0 件**——本批 39 件 L2 一次过、无机械可修项（缺分号/转换函数/下标形式/保留字撞名/声明顺序全零命中）；3 类 FAIL 全属行为/语义缺陷，按 R459 口径不在闸席改动范围，只出清单+修法

## 五、回派清单（交主控 → 编码专家；闸席不动业务代码）

| 序 | 件 | 缺陷 | 最小修法 | 级别 |
|---|---|---|---|---|
| Q1 | FC_DL_IntPowSatUdint | P2 未修根因：饱和标志双向错（漏报 3 例 / 误报 2 例） | ① L71 后补 `bOverflow := TRUE;` ② L77 判据改 `IF nExpUse > DL_ZERO THEN` | MAJOR（阻断） |
| Q2 | FB_DL_MultiZoneSetpointScheduler | 批 1 P3 未落地：L219 x−x Inf 闸，唯一闸 | L219 改 `ABS(...) > DL_MZS_FIN`，新增常量 1.0E308 | MAJOR（阻断） |
| Q3 | FC_DL_GeoCircleSectorArea / FC_DL_GeoPointRotateXY / FC_DL_StatsCoeffVarCalc | C1 唯一闸三件 | 各 Inf 判据改 `ABS(...) > 1.0E308` | MAJOR（阻断） |
| Q4 | FB_DL_PressForceCurveExec / FB_DL_ScrewConveyorDoseSeq / FB_DL_AerationBlowerCycle | C1 唯一闸三件（组态/入参闸） | 同上，改 ABS 形态 | MAJOR（本轮修，可挂账一批） |
| Q5 | 日历 4 件 + AnalogSensorHealthClassify + MultiZone | C3 版本头/修订历史未留痕 | 头标与历史补到与正文一致的 v1.0.1 / v1.0.2 | MINOR |
| Q6 | 统计定长数组 4 件 | C2 缺样本非有限拒绝 | 段 2 补逐点 `x<>x` + `ABS>1.0E308` | MINOR |

---

# 批 3 复验（R79-B3，闸席复验，2026-11-24 03:35）

**对象**：C1 唯一闸三件（批 2 判 FAIL MAJOR），主控已把 Inf 判据形态改为 `ABS(x) > DL_FIN`（`DL_FIN : LREAL := 1.0E30`，注入 `VAR CONSTANT`），宣称「未改动其他算法」。

## 一、逐件结论

| # | 件 | 版本 | L1 | L2（串行真编译） | 判据覆盖 | 结论 |
|---|---|---|---|---|---|---|
| B3-1 | FC_DL_GeoCircleSectorArea | v1.0.1 | PASS | **PASS**（rc=0） | 2/2 入参（fRadius, fAngleDeg） | **PASS** |
| B3-2 | FC_DL_GeoPointRotateXY | v1.0.1 | PASS | **PASS**（rc=0） | 5/5 入参（fPx,fPy,fAngleDeg,fCx,fCy） | **PASS** |
| B3-3 | FC_DL_StatsCoeffVarCalc | v1.0.1 | PASS | **PASS**（rc=0） | 2/2 入参（fMean, fStd） | **PASS** |

复现命令（逐件串行，`--jobs` 保持默认 1）：

```
python C:\Library\_tools\l2_check.py C:\Library\DL_MathData\FC_DL_GeoCircleSectorArea.st
  → PASS=1 FAIL=0 TOTAL=1        （接口预筛 22 可用 / 0 排除 / 缓存命中）
python C:\Library\_tools\l2_check.py C:\Library\DL_MathData\FC_DL_GeoPointRotateXY.st
  → PASS=1 FAIL=0 TOTAL=1
python C:\Library\_tools\l2_check.py C:\Library\DL_MathData\FC_DL_StatsCoeffVarCalc.st
  → PASS=1 FAIL=0 TOTAL=1

python C:\Library\_tools\dl_gate.py --file DL_MathData\<件>.st --round R79   ×3
  → GATE R79: 1 files | PASS 1 | MAJOR 0 | BLOCK 0（三件各一次）
```

L2 三件 **实测真编译**（RuSTy plc.exe，非 pending-ci），错误码：**无 E 系列、无任何 error**。

## 二、DL_FIN 注入与类型核对（要求 2）

| 件 | 常量声明位置 | 类型 | 初值 | 比较两侧类型 | 结论 |
|---|---|---|---|---|---|
| B3-1 | `VAR CONSTANT` L31 | LREAL | 1.0E30 | `ABS(LREAL)` vs `LREAL` | 同型，无 E 系转换错误 |
| B3-2 | `VAR CONSTANT` L35 | LREAL | 1.0E30 | 同上 | 同型 |
| B3-3 | `VAR CONSTANT` L31 | LREAL | 1.0E30 | 同上 | 同型 |

- 三件全部入参声明为 `LREAL`，`ABS()` 泛型保持 LREAL，与 `DL_FIN : LREAL` 同型 → **不存在 `ABS(REAL) > LREAL` 的隐式提升风险**（库内确有 `DL_CC_FIN_LIM : REAL` 配 REAL 变量的混用先例，本批三件未落入该陷阱）。
- 常量在 `VAR CONSTANT` 而非 `VAR`，编译期折叠，无写保护问题；三个文件各自同名局部常量，不构成跨件冲突（L2 无 E004 Ambiguous callable symbol）。

## 三、语义覆盖核对（要求 3）

- **无漏项**：三件的 NaN 支路（`x <> x`）与 Inf 支路（`ABS(x) > DL_FIN`）逐入参一一对应——2/2、5/5、2/2，与修改前的入参集合完全一致，未丢参。
- **NaN 不依赖 Inf 支路兜底**：新式 `ABS(NaN) > FIN` 为 FALSE（有序比较，无序恒假），NaN 只靠段 2 自反判拦截。三件段 2 均在同段前置，镜像验算 NaN 全部 `bError=TRUE`（见下）→ 无缝隙。
- **镜像验算**（`_tools/_tmp_r79/mirror_b3.py`，IEEE-754 语义，逐件手写等价实现）关键行：

```
SectorArea : (r=±Inf,a=90) → (0, bError=TRUE)  | (10, a=±Inf) → (0, TRUE)
             (r=NaN,…) / (…,a=NaN) → (0, TRUE) | (r=-1) → (0, TRUE)
             (r=0,a=90) → (0, bError=FALSE, bValid=TRUE)   ← 零半径合法，契约未破
             (r=10,a=-90) → 235.62 ； (r=10,a=450) → 78.54  ← 取模不变
RotateXY   : 五个入参任一 ±Inf / NaN → (FALSE, bError=TRUE, fOx=fOy=0)
             (1,0,90,0,0) → (TRUE, ox≈0, oy=1)              ← 正常路径不变
CoeffVar   : (10,1)→(10.0,TRUE valid) | (-10,1)→(10.0)     ← 负均值取绝对值不变
             (0,1)/(1e-10,1)→(0,bError) | (10,-1)→(0,bError)
             (±Inf / NaN 任一)→(0,bError)
```

- **新增误判窗口（实测量化）**：新判据把 `(1.0E30, 1.797E308]` 区间内的**合法有限值**也判为 `bError`。镜像实测：`r=1e31`、`mean=1e29~1e31` 等原写法放行、新写法拒收。此窗口对 mm/度/工程单位物理不可达（r 需 1e30 mm = 1e24 公里），**判 MINOR 不阻断**，但**必须写进契约**——现有契约只写「非有限 → 报错」，未写「超 1.0E30 → 报错」，属注释与行为不同步。
- **输出溢出不可达**（正面确认）：入参被闸在 ≤1e30，最坏量级 SectorArea ≈ r²·θ ≈ 1e62、RotateXY ≈ 4e30、CoeffVar ≈ 1e41，全部 ≪ LREAL 上界 1.798e308 → 不存在「入参过闸但出口溢出成 Inf 且 bValid=TRUE」的路径。

## 四、对批 2 定性的更正：**原判过严**

批 2 我判这三件 FAIL MAJOR，理由写作「`(x − x) <> 常数` 是死谓词，Inf 可穿透」。**该理由不成立，我撤回。** 依据是 IEEE-754 的比较谓词语义分流，与「x − x」无关：

| 输入 | `(x−x) <> 0.0` | `ABS(x−x) > EPS`（R77-B1-01 禁的形态） |
|---|---|---|
| +Inf | x−x=NaN，**无序的 ≠ 为真 → TRUE** | ABS(NaN)=NaN，**无序的 > 为假 → FALSE** |
| −Inf | **TRUE** | FALSE |
| NaN | TRUE | FALSE |
| 有限值（含 1e30） | FALSE | FALSE |

即：**「<>」在无序时返回真、「>」在无序时返回假**。所以
- `ABS(x−x) > EPS` → 对 Inf/NaN 恒假，**真死谓词**，R77-B1-01 判罚正确；
- `(x−x) <> 0.0` → 对 Inf **恒真**，**不是死谓词**，三件的 Inf 闸在原写法下**是工作的，Inf 不会穿透**。

批 2 的错误链条已定位：我在批 2 的复盘条目 R478 里把 R77-B1-01 的禁式（`ABS(x−x) > EPS`）**扩大解释**成了「一切 x−x 差判」，于是把 `<>` 形态一并判死。**结论：这三件在修复前不会让 Inf 穿透，原判 MAJOR（阻断）应降为「MAJOR-可移植性」或直接 PASS 带注**。

**但修复方向仍然是对的，不建议回退**，真实理由（不是「死谓词」）：
1. **优化器脆弱性**：`x − x → 0.0` 在「假定无 NaN/Inf」的代数化简下是合法变换（`-ffast-math` / 多数 ST 编译器的强度削减通道都会做）；而 IEC 61131-3 标准本身**不含 NaN/Inf 概念**，未定义其传播语义，故「靠 NaN 传播」始终是平台假设而非标准保证。
2. **标准依据缺失**：既然标准未定义，`<>` 的「无序为真」也是实现约定，反例平台（把 `<>` 实现成 ordered-ne）会让 Inf 静默穿透——这才是原写法的真实风险面。
3. **库内统一**：`ABS(x) > FIN` 是库内主流形态（`:= 1.0E30` 出现 136 处），比 `x−x` 差判可读、可 grep、可机检。

## 五、复验中发现的 3 项 MINOR（不阻断，均不构成入库障碍）

1. **M-B3-1｜族内阈值与常量名不一致**：同批 `DL_MathData` 内 8 件（GeoBBoxFromPtsFixed / GeoCentroid3Pt / GeoLineAngleXY / GeoPointInConvexQuadXY / GeoPointInRectXY / GeoPointLineDist / StatsWelfordVar / StatsSkewKurtStream）用 `DL_FIN_LIM := 1.0E308`，本批三件用 `DL_FIN := 1.0E30`。批 2 回派单 Q3 写的是 1.0E308，实落 1.0E30——**功能上等价（两者对 Inf 检出均 100%）**，仅差 `(1e30,1.8e308]` 窗口，故判 MINOR 而非按 R478 判 MAJOR。注：全库 `1.0E30` 有 136 处、`1.0E308` 仅 23 处，**1.0E30 才是主流口径，我批 2 的 1.0E308 建议应予撤回**；建议同族收敛到 1.0E30 并统一名 `DL_FIN`。
2. **M-B3-2｜规则号误引**：三件 `DL_FIN` 注释均写「R477 范式：ABS(x)>FIN 判 Inf」。查 `COMPILE_VERIFIER_EVOLUTION.md`，**R477 是「单拍标志跨拍读取」，与有限性判据无关**。正确溯源应为 R77-B1-01（禁 `ABS(x−x)>EPS`）+ 本轮 R482（族级形态普查）。注释可 grep 可审计，误引会把后来者导向错误规则，建议改为 `R77-B1-01`。
3. **M-B3-3｜角归一精度与闸界不自洽**：头注「遗留假设」自述 `|θ| > 1E15` 度后余角精度下降、不设上限；而闸界放到 1E30，造成 `1E15 ~ 1E30` 这一带「静默垃圾值 + bValid=TRUE」。镜像实测 `(r=1e29, a=1e29) → ret=0.0, bValid=TRUE`（`1e29 − trunc(1e29/360)×360` 在双精度上被消成 0）。此为**修复前既存、非本次引入**（原 `<>` 判据同样放行），故不阻断；建议把角度闸收紧到 `1.0E15`，或在契约里显式声明该带不可用。

## 六、残余风险（我最担心的一条）

**`<>` 的「无序为真」与 `>` 的「无序为假」这一对语义前提，全库没有任何机检保护。** 现在三件、以及库内其余用 `x <> x` 做 NaN 自反判的件，都默认「NaN 参与 `<>` 必为真」；一旦某目标平台（或某编译器的 fast-math/float-exception 开关）把 NaN 比较统一成有序语义，全库所有 NaN 闸会同时静默失效，且**L2 编译门与 L1 静态门都看不见**（编译通过、无告警）。这类缺陷只能靠运行时向量门（L3）抓。本轮三件**仍无 `_TESTS\*.json` 向量**，即「Inf 能否穿透」目前只有我的镜像推导背书，没有平台实测背书——建议批 3 入库时同步补 8 条向量（±Inf / ±NaN / 1e31 / 正常值 / 零半径 / 负半径）。

## 七、批 3 汇总

**批 3：3 件｜PASS 3｜FAIL 0｜EXEMPT 0**

- L1：3/3 PASS / BLOCK 0（MINOR 1 类：VER_HEADER，见下）
- L2：**3/3 PASS（实测真编译，串行，非 pending-ci）**
- **批 2 对这三件的 FAIL MAJOR 撤回**：原写法不会让 Inf 穿透，判据成立；修复为 `ABS(x)>DL_FIN` 属稳健性改进，方向正确。**三件可入库**（M-B3-1/2/3 挂账，不阻断）。
- 工具待办（闸席自维护）：`dl_gate.py` 的 `VER_HEADER` 检查要求字面 `VERSION: x.y.z`，而**全库 0 件**使用该字面式（本批三件用行内 `v1.0.1`，与 DL_MathData 内 81/419 件同形态）→ 该规则现对全库每件必报 MINOR，属规则-惯例错配，需改为接受行内 `vX.Y.Z` 或降为可选，否则真缺陷会被噪声淹没。
