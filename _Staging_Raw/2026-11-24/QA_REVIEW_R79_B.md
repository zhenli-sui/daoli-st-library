# QA_REVIEW_R79_B（审校去重席 · 2026-11-24 · 32 件全量，零抽样）

审计口径：R1 名称去重（registry 1408 件全量）｜R2 结构指纹（逐件读全码，非签名哈希）｜R3 语义同义。
分级：BLOCK 0 ｜ MAJOR 4 ｜ MINOR 13 ｜ 拒收 5 ｜ 存疑放行 6 ｜ PASS 11。三件 `GeoCircleSectorArea / GeoPointRotateXY / StatsCoeffVarCalc` 标注 **待闸批 3 确认**。

## 一、逐件表（结论｜命中项｜去重｜证据行号）

| # | 件 | 结论 | 命中项 / 行号证据 | 去重 |
|---|---|---|---|---|
|E1|FB_DL_StatsWelfordVar|**MAJOR**|L84-86 `nAcc+1` 后直接 `fDelta/UDINT_TO_LREAL(nAcc)`，nAcc 无上限钳 → 2^32 回绕到 0 时除数为 0（浮点得 Inf 污染累加器）；在库同族 FB_DL_SkewKurtosisCalc L65+L105-107 有 DL_SK_CNTMAX 钳位先例|放行|
|E2|FB_DL_StatsSkewKurtStream|**MAJOR+拒收**|L97-100 同 E1 回绕除零；L127-128 公式与 FB_DL_SkewKurtosisCalc L120-121 逐字符同构（`SQRT(n)*M3/(M2*SQRT(M2))`、`n*M4/(M2*M2)-3`），仅差 bEnable 沿/电平、eStage 枚举、M2 阈值 1e-18 vs 1e-300|**拒收**|
|E3|FC_DL_StatsMadFixed|**拒收**|算法=L16-17 声明「含 NaN 排序不崩但结果无意义」的 MAD；与 FC_DL_MedianAbsDev L139/L141（插入排序 + 绝对偏差中位数）同一算法，只差 10/16/32 点与 REAL/LREAL；MAD 在库已两件（+FC_DL_MadZScore L134/136）|**拒收（第三份 MAD）**|
|E4|FC_DL_StatsTrimmedMeanFixed|**拒收**|L69-72 单侧对称截尾 = FC_DL_TrimmedMeanCalc L64-66 `uTrimLo/uTrimHi` 取等值的子集；除法 L95 有闸、排序自足，技术面无缺陷|**拒收（子集）**|
|E5|FC_DL_StatsPercentileRankFixed|PASS/MINOR|MINOR：L74-86 只排序不验有限性，NaN 样本可比性全假但仍 bValid:=TRUE（L99），且未在头注声明该遗留假设（同批 MadFixed L16 有声明）|存疑放行|
|E6|FC_DL_StatsZScoreClamp|PASS/MINOR|MINOR：L66-69 `fStd<EPS`（含负值）→ 返回 0 且 bValid=TRUE，把物理不可能的负 σ 当"零离散"；FC_DL_StatsCoeffVarCalc L57-59 对同一条件判故障 → 口径分裂。除零闸 L72 前置成立|放行|
|E7|FC_DL_StatsHistogramBin|PASS|L51-66 三重闸齐（nBins/宽度/NaN+Inf）；L78 实数上限兜底后才 LREAL_TO_DINT，无取整溢出；L71/L79 首末桶钳位|存疑放行|
|E8|FC_DL_StatsRunLengthMax|PASS|L60-64 容差闸 + ABS 折叠；L72-80 单趟扫描；L84 出口恒在 1..nUse|放行|
|F1|FC_DL_ChkFletcher16|PASS|L63-64 每步 MOD 255，累加恒 <255；L68 高半 sum2 / 低半 sum1|放行（新）|
|F2|FC_DL_ChkFletcher32|PASS|L69-77 字下标经 `nIdx<=nUse` 复核，尾字节补零；MOD 65535|放行（新）|
|F3|FC_DL_ChkXor8|**拒收**|L55-57 `nAcc := nAcc XOR aData[i]` 与 FC_DL_ByteArrayXor L80 同式；差异仅 16 vs 256 容量与 bInvalid/bClamped 外壳|**拒收**|
|F4|FC_DL_ChkSum8|**拒收**|L61 `UDINT_TO_BYTE(nSum MOD 256)` = FC_DL_ChecksumSum8 L88 + 取模，而老件还多覆盖 `bTwosComplement` 补码口径 → 新件是严格子集|**拒收**|
|F5|FC_DL_ChkTwosCompSum16|PASS|L68-73 字下标安全；L79-84 补码 0 特判（16#10000 不可表示）正确|存疑放行|
|F6|FC_DL_ChkSum32Mod|PASS|L67-72 「减模数」归一：`nAcc >= MOD-nTerm` 等价 `nAcc+nTerm>=MOD`，nTerm≤16#FF00_0000 故 MOD-nTerm 无下溢；L73-77 权值乘前判上界|放行（新）|
|F7|FC_DL_ChkParityBlock|PASS|L63-69 位计数循环；L73 偶数判；nBitOnes 诊断出口|放行（不同阶：整块 vs 单字节）|
|F8|FC_DL_ChkAdler32|PASS|L63-64 双路 MOD 65521；L46 空串返回 1 = 标准 Adler 值|放行（新）|
|G1|FB_DL_CoolingTowerFanStageSeq|**MAJOR**|**L266-268 先判 `nActiveCnt>=nStageCmd` 转 eRunning，L290 刚置的 `_nPendFan` 未清；eRunning 分支 L344-381 全无 _nPendFan 清理路径，而轮换入相 L360 硬要求 `_nPendFan = 0` → eRotate 结构性不可达，主备轮换静默失效；同时末台启动确认（验收 V3 语义）整段被跳过**。其余：R7 全部定时器在 CASE 外 L214-238 ✓；CASE ELSE L469 ✓；eFault 出口 L460 `_bResetPulse AND NOT bEnable` 可达 ✓；bReset 用 rtReset.Q L215 ✓|存疑放行|
|G2|FB_DL_ScrewConveyorDoseSeq|PASS/MINOR|MINOR：L189-191/233 用 `(x-x)<>0` 判 Inf（与批内 ABS 闸冲突）；L303 `OR fDosedKg>=fTargetKg` 被 L215 `_fStopThr` 恒覆盖=冗余。正向：L239-244 除零闸、L279-282 积分带 dt 闸、L346 故障出口可达、CASE ELSE L355 ✓|存疑放行|
|G3|FB_DL_PressForceCurveExec|PASS/MINOR|MINOR：L188-197 三处 x-x 闸；L14-15 头注「力指令按段速率退回 0」vs L257/L290/L316 瞬时归零 = 头注与实现不一致。正向：L235-237 `_bSegReset` 断流使单段 ET 自清（换段超时同源）✓、L329-333 卸力收敛、L349 出口可达|存疑放行|
|G4|FB_DL_AerationBlowerCycle|PASS/MINOR|MINOR：L190-192 x-x 闸；L183 冻结判据为单拍 |Δ|<1e-6，对慢漂移型卡死灵敏度依赖扫描周期。正向：L150-151 最短时间用状态量非单拍位 ✓、L286-314 台级降级换备 ✓、L377 出口可达、CASE ELSE L386 ✓|放行（新）|
|H1|FC_DL_CalAddMonths|PASS/MINOR|MINOR：L8 契约「五个出参全部保持 0」与实现 6 个出参（L25-32）+ bError=TRUE 不符。正向：L64 双侧直比防 INT 下界回绕、L70/L83 闰年优先级 `AND 紧于 OR` 正确、L75 结果域闸|放行（新）|
|H2|FC_DL_CalDateSpanMonths|PASS|L56-66 双日期全量域闸；L69 无除法无溢出；L72-76 符号对称日修正与头注一致|放行（新）|
|H3|FC_DL_IntLcmSafeUdint|PASS|L53-56 零短路；L63 MOD 除数已证非零；L78 `nQ > UMAX/nB` 乘前反算，nB 非零已证|放行（LCM/GCD 分工，非重复）|
|H4|FC_DL_IntIsPrimeUdint|PASS|L62 循环条件 `nD <= nVal/nD` 替代 i*i 防溢出；L44-58 短路齐|放行（新）|
|H5|FC_DL_IntModPowUdint|PASS|L83/L86/L89 三处归约均 `x >= MOD-a` 形式，nAdd<nMod 故无下溢；L91 指数位为 1 才采信 nAccR、L92 平方无条件生效，顺序正确|放行（新）|
|H6|FC_DL_IntFloorLog2Udint|PASS|L46-50 零入参 −1 哨兵 + bError；L55-58 除数为常量 2|放行（新）|
|H7|FC_DL_IntNextPrimeUdint|PASS/MINOR|MINOR：L66-89 最坏 2000 候选 × 3.3e4 试除 ≈ 6.5e7 次内层迭代，头注 L15 只提示单值 √ 步数未提示乘积。正向：L82-85 推进溢出兜底、L54 上界保护带|放行（新）|
|H8|FC_DL_GeoChordHeightCalc|**MAJOR**|**L49-58 用 `fRadius-fRadius` / `fChord-fChord` 判 Inf**；同轮另三件（GeoCircleSectorArea L55、GeoPointRotateXY L64、StatsCoeffVarCalc L51）已改 `ABS(x)>DL_FIN` 并在头注写明「R477 范式：禁用 x-x 差判」→ 本件 v1.0.0 未同步，NaN-无序比较平台上 Inf 闸失效后 `SQRT(Inf−Inf)` 得 NaN 且 bValid=TRUE|放行（新）|
|H9|FC_DL_GeoCircleSectorArea|PASS/MINOR **待闸批3**|MINOR：L50 段注释仍写「Inf 自减判」，实现 L55 为 `ABS(fRadius)>DL_FIN` → 主控修复后注释未同步。逻辑：L67-72 角度归一 [0,360) 正确|放行（新）|
|H10|FC_DL_GeoPointRotateXY|PASS/MINOR **待闸批3**|MINOR：L59 段注释「Inf 自减判」与 L64 ABS 闸不符（同上）。逻辑：L78-81 先减中心再旋转，大坐标不丢精度|放行（新）|
|H11|FC_DL_StatsCoeffVarCalc|PASS/MINOR **待闸批3**|MINOR：L46 段注释同款未同步；L57-59 负 σ 判故障（与 E6 口径相反，见 E6）。逻辑：L64 近零均值容差闸、L70 除子已证 ≥1e-9|放行（新）|
|H12|FC_DL_StatsEntropyCalc|**MAJOR**|**L66 `(aProb[nI]-aProb[nI])<>0` 与 L78 `(fSum-fSum)<>0` 两处 x-x 闸**；若平台 NaN 无序比较使 L62 自反判失效，Inf 直穿 fSum → fH 仍 bValid=TRUE（历史 PmvComfortIndex 型 NaN 穿透）。正向：L54 个数闸、L86 跳过 log(0)|放行（新）|

## 二、拒收清单（5 件，均"仅宽度/形态差异、语义同一"）

1. `FB_DL_StatsSkewKurtStream` → `FB_DL_SkewKurtosisCalc`（L120-121 同构）
2. `FC_DL_StatsMadFixed` → `FC_DL_MedianAbsDev` L139/141（+ `FC_DL_MadZScore` L134/136）→ MAD 将成库内第三份
3. `FC_DL_StatsTrimmedMeanFixed` → `FC_DL_TrimmedMeanCalc` L64-66（对称截尾是其子集）
4. `FC_DL_ChkXor8` → `FC_DL_ByteArrayXor` L80
5. `FC_DL_ChkSum8` → `FC_DL_ChecksumSum8` L88（老件含补码口径）

## 三、MAJOR（4 件，均需下轮返修）
- M1 `FB_DL_StatsWelfordVar` L84-86｜M2 `FB_DL_StatsSkewKurtStream` L97-100：UDINT 样本计数无上限钳 → 回绕除零。
- M3 `FB_DL_CoolingTowerFanStageSeq` L266-268 + L360：末台 pending 未清 → eRotate 永不可达（轮换静默挂死）。
- M4 `FC_DL_GeoChordHeightCalc` L49-58 / M5 `FC_DL_StatsEntropyCalc` L66+L78：x-x 判 Inf，与批内 R477 ABS 闸分裂。

## 四、存疑放行（6 件，供总监复议；我的判断倾向放行）
`PercentileRankFixed`（与 PercentileRank 语义相反，真增量=最近秩不插值）｜`HistogramBin`（FB_DL_HistogramBinTally L44 nLastBin 已含同语义，FC 阶可被其他 FC 调用是唯一增量）｜`ChkTwosCompSum16`（与 ChecksumSum8 补码分支差 8 位字节 vs 16 位小端字）｜`CoolingTowerFanStageSeq`（vs FB_DL_FanArrayStageCtrl 投切+轮换重叠 ≥60%）｜`ScrewConveyorDoseSeq`（vs FB_DL_BatchDoseSeq 计量原理不同：流量积算 vs 定量三段）｜`PressForceCurveExec`（vs FB_DL_StackPressureProfile 单段定时 ramp-hold-release）。

## 五、系统性口径缺陷（触发扩面复审）
**x-x 判 Inf 与 ABS(x)>DL_FIN 双轨并存，本批 6 件分裂**：ABS 轨 = GeoCircleSectorArea L55 / GeoPointRotateXY L64 / StatsCoeffVarCalc L51（主控当轮修复）；x-x 轨 = GeoChordHeightCalc L49-58 / StatsEntropyCalc L66+L78 / ScrewConveyorDoseSeq L189-191+233 / PressForceCurveExec L188-197 / AerationBlowerCycle L190-192。同批 ≥3 件同型 → 请总监触发扩面复审，并把「x−x 差判」列为 dl_gate 机检锚点（禁 `(X - X)` 出现在比较式左侧）。
