# QA_REVIEW_R95 ｜ S5 质量审校官（dlf-inspector）｜ 2026-11-25

- 审校对象：`GATE_R95.json` 中 **l2=pass 且 verdict=PASS 的 36 件**（4 件 FAIL 已交 S6，不参与本席审校；其中 `FB_DL_SevenSegMultiplexSeq` 虽 l2=pass 但 exit_gate N2 FAIL，已排除）。
- 依据：`daoli-qa-dedup.md`（双职责/12 项）、`_dedup_fingerprints.json`（1549 条）、`01-coding-standard.md`（R4/R45~R101/FB32~FB51）、`INDEX_REGISTRY.json`（2041 条）。
- 纪律声明：本轮**未修改任何 .st**；未参与规划；`_Staging_Raw\` 下仅落本文件。

## 一、汇总结论

| 判定 | 件数 | 说明 |
|---|---|---|
| PASS | 9 | 无缺陷或仅"备注"级观察 |
| BLOCK | 0 | 无编译阻断/安全侧硬缺陷（L1/L2 双绿成立） |
| MAJOR | 12 | 14 条 MAJOR 缺陷（`RtcpFiveAxisSeq`/`IterSolverRunner` 各 2 条）→ 全部派 S6 |
| MINOR | 15 | 19 条 MINOR 缺陷（`GoldenSection`/`ParabolaVertex` 各 2 条；另 3 条与 MAJOR 同件并存）→ 挂账，可随 S6 顺手修 |
| 拒收（去重） | 0 | 三道去重全量 36 件，有效命中 0 |
| 存疑放行（报 S0 复核） | 3 | 见第六节 |

MAJOR 12 件：`FC_DL_ArcCenterOffsetCalc`、`FC_DL_CornerRoundingRadiusCalc`、`FB_DL_RtcpFiveAxisSeq`、`FC_DL_BisectIterStep`、`FC_DL_SecantIterStep`、`FC_DL_IllinoisIterStep`、`FB_DL_IterSolverRunner`、`FC_DL_SevenSegMinusFlagCalc`、`FC_DL_OrpRefOffsetCalc`、`FC_DL_TurbidityNtuCalc`、`FC_DL_ChlorineDpdAbsorbCalc`、`FC_DL_KcellConstCalc`。

## 二、分件结论表（36 件，缺陷带行号）

| # | 件名 | 判定 | 缺陷（文件:行 ｜ 级别 ｜ 扫查项 ｜ 现象 ｜ 修法） |
|---|---|---|---|---|
| 1 | FC_DL_ArcCenterOffsetCalc | **MAJOR** | L38/L45/L54/L64-67 ｜ MAJOR ｜ #2 ｜ `fRadiusMm=+Inf` 过 NaN 闸（L38）与域闸（L50 `Inf<=0` 为假），L54 `_fH=Inf`，L56-60 出 `±Inf`，L64 `fDx<>fDx` 对 Inf 恒假 → L67 `uErrId:=0; bOk:=TRUE`；L45 注释"Inf 入参所致"实为谎称（`_fLen<>_fLen` 只判 NaN） ｜ 补 `(fRadiusMm-fRadiusMm)<>(fRadiusMm-fRadiusMm)` 入 L38 闸；L64 出口闸改双判 |
| 2 | FC_DL_HelicalTurnAdvanceCalc | MINOR | L37/L58 ｜ MINOR ｜ #2 ｜ 仅 NaN 全量枚举，`fRadiusMm=+Inf` 时 `_fArcPerRev=Inf` → L58 `fPitchMmRev > Inf` 恒假，升角校验静默失效（出口值仍有限正确） ｜ 补 Inf 双判；升角校验用原始参数上方钳定 |
| 3 | FC_DL_RtcpPivotOffsetCalc | PASS | — （Inf 由 L44-55 折叠 + L56-59 钳位结构兜住，出口恒有限；代值见第四节 A2） |
| 4 | FC_DL_ToolLengthCompDeltaCalc | PASS | — （`fLenOldMm=Inf` 由 L39 `ABS(_fDelta)>200` 兜住；新值 Inf 由 L32 双判） |
| 5 | FC_DL_RotFeedInvTimeCalc | MINOR | L51 ｜ MINOR ｜ #1 ｜ `fFeedDegMin / _fRaw` 无显式非零判据，依赖 L35-36 两域闸间接成立；反规格化下溢至 0 时由 L52-54 复检兜成码 4 ｜ L51 前加 `IF _fRaw <= 0.0 THEN uErrId:=4; RETURN; END_IF` |
| 6 | FC_DL_SagFeedLimitCalc | MINOR | L34/L42/L46 ｜ MINOR ｜ #2 ｜ 头注 L5 承诺"非有限 → 上限 0、bLimited=TRUE"，实现只判 NaN；`fSagTolMm=+Inf` → `_fVSag=Inf` → L46 取 ELSE 分支 → 返回 TRUE 且 bLimited=FALSE，弦高约束被静默解除 ｜ L34 补 Inf 双判（三入参全量） |
| 7 | FC_DL_SwivelHeadTiltLimitCalc | MINOR | L34-35/L47/L71 ｜ MINOR ｜ #2 ｜ 头注 L5 称"任一入参非有限 → 倾角落 0°"，实现 Inf 双判只覆盖 `fTiltCmdDeg`（L35）；`fRateMaxDegS=+Inf` 或 `fDtSec=+Inf` → `_fStepMax=Inf` → L72/L74 恒假 → 角速度限幅静默解除、L85 返回 TRUE ｜ L35 扩为三入参双判 |
| 8 | FC_DL_CornerRoundingRadiusCalc | **MAJOR** | L52/L56/L58 ｜ MAJOR ｜ #12 ｜ `fJerkRatio` 为**代数恒等式**：`_fVuse=(j·r²)^(1/3)`（L52）代回 `v³/(r²·j)`（L56）恒 =1.0，与"jerk 使用率"名实不符；代值（θ=90°/r=20/j=50000/feed=5000）实测比率 1.000000，而按实际采用进给应为 0.0289 → 该输出无信息量 ｜ 比率改用实际采用速度 `(fCornerFeedMmMin/60)³/(r²·j)`；若定位为回代自检位则改名 `bJerkCalibOk` 并入头注 |
| | | | L56 ｜ MINOR ｜ #1 ｜ 除子 `(fRadiusMm*fRadiusMm*fJerkMaxMmS3)` 中 `fRadiusMm` 可为 0（`_fRmax→0`），无前置非零判据，仅靠 L57 NaN 闸兜底 ｜ L56 前加 `IF fRadiusMm <= 0.0 THEN fJerkRatio:=0.0; ...` 或改除子判定 |
| 9 | FC_DL_RtcpTrackingErrCalc | MINOR | L52-53 ｜ MINOR ｜ #12 ｜ `uErrId=3`（门限非法）分支对 `CONSTANT DL_RTE_LIMIT:=5.0` 恒假 → 声明了不可达出口码，头注 L5 仍称"门限≤0 → 码 3" ｜ 门限改为入参（带域闸）或删除码 3 并同步头注 |
| 10 | FB_DL_RtcpFiveAxisSeq | **MAJOR** | L169-178 + L131 + L186-188 ｜ MAJOR ｜ #6/#7 ｜ 迁入**执行相** eInterp 的判据（L176-177 `ELSE → eInterp`）未复检 `_bCfgBad`（R274 要求迁入安全相携全量闸位）；运行中 `nAxisMode` 变非法后 eEnable/eInterp 均不查，最终由 L186 `CalcPivotComp` 拒收并**误归因码 3（软限位）** ｜ eEnable→eInterp 与 eInterp 段首补 `_bCfgBad` 分支（码 1）；CalcPivotComp 拒收按成因分码（R190） |
| | | | L34/L131/L186 ｜ MAJOR ｜ #12 ｜ `nAxisMode`（0=刀尖跟随/1=工件坐标）**只入 L131 组态闸，不参与任何换算**：`CalcPivotComp`（L76-112）不接该引脚，模式 0/1 输出逐位相同 → 死引脚/功能缺失 ｜ 二选一：按模式分列补偿式（工件坐标需转到工件系），或删引脚/降为门控并在头注声明"模式仅约束组态" |
| | | | L152-153/L159-160 ｜ MINOR ｜ #2 ｜ `_bNonFin` 在 eIdle/ePivotCal 归因到码 1（组态），与头注 L13-14"2 非有限"冲突，码 2 仅 eInterp 可达 ｜ 两处按 `_bNonFin → 码 2` 分列 |
| 11 | FC_DL_BisectIterStep | **MAJOR** | L31 + L34-35 ｜ MAJOR ｜ #2/#12 ｜ 段 0 用**原始入参**预置出口：`fAnew := fA; fBnew := fB`（L31）；NaN 入参时 L34 `RETURN` **不改写实值** → `fAnew/fBnew` 直出 NaN（bBrktLost=TRUE 只置判据位，正是 R19「只置标志不改实值」同型）；头注 L5-6 明写"原样回传"，与 FB51-3 冲突 ｜ 闸命中路径改为 `fAnew:=0.0; fBnew:=0.0`（或保持上一有效括号），并把"原样回传"改为仅对有限入参 |
| 12 | FC_DL_RegulaFalsiIterStep | MINOR | L37/L40 ｜ MINOR ｜ #2 ｜ Inf 双判只覆盖 `(fB-fA)`，`fFa/fFb/fDenEps` 的 Inf 靠 L51-58 退化路径与 L65 复检兜住（出口安全） ｜ 段 1 扩为五入参全量双判 |
| 13 | FC_DL_SecantIterStep | **MAJOR** | L37-38 + L54-55 + L62 ｜ MAJOR ｜ #2 ｜ Inf 双判只覆盖 `fX1`、`fF1`（L38）；`fF0=+Inf` → `_fDen=-Inf` → L54 `fF1·Δx/(-Inf)=∓0` → `fXnew=fX1`、`fDelta=0`，L55 `bDegenerate:=FALSE`、L62 返回 TRUE → **静默零步空转**，与头注 L5-6"非有限 → bDegenerate=TRUE"相反 ｜ 段 1 扩为 `fX0/fF0` 双判；L61 前补 `IF fDelta = 0.0 THEN bDegenerate:=TRUE` |
| 14 | FC_DL_IllinoisIterStep | **MAJOR** | L38/L41/L42/L60-62/L68 ｜ MAJOR ｜ #2 ｜ Inf 双判只覆盖 `fXPrev`（L41）；`fFa=+Inf` 过闸后 L42 原样回传，L62/L60 `fFa/2 = Inf` → **出口 `fFaOut=Inf`**，L68 `uSideOut:=_uSide`（1 或 2）且返回 TRUE；头注 L6-7 承诺"非有限 → 两值原样回传且 uSideOut=0" ｜ 段 1 补 `fFa/fFb/fA/fB` 双判，命中即 `fFaOut:=0; fFbOut:=0; uSideOut:=0; RETURN` |
| 15 | FC_DL_GoldenSectionIterStep | MINOR | L28 ｜ MINOR ｜ #9 ｜ `DL_GSD_PHI := 6.1803…E-1` 实为 1/φ（0.618），名值相反（S4 MINOR-3 复核**成立**） ｜ 改名 `DL_GSD_INVPHI` 或值改 1.618（同步 L49-51 用法） |
| | | | L39/L52 ｜ MINOR ｜ #2 ｜ `fTol=+Inf` 时 `_fTol=Inf` → L52 `bConverged` 恒真（宽区间也判收敛） ｜ L39 补 `fTol` 双判与上限域闸 |
| 16 | FC_DL_TernaryNarrowIterStep | MINOR | L34-35 vs 头注 L6-7 ｜ MINOR ｜ #2 ｜ 头注称"非有限 → 原区间回传"，实为段 0 预置 `0/0`、闸命中后直接 RETURN（S4 MINOR-1 复核**成立**，但与 #11 口径不一致） ｜ 统一口径：或改预置为 `fA/fB`，或改头注为"落 0 安全侧" |
| 17 | FC_DL_ParabolaVertexIterStep | MINOR | L27-29 ｜ MINOR ｜ #10 ｜ `_fDx12/_fDx13/_fDx23` 注释为**英文单语**（"x1 − x2 [-] / Difference…"），全库 36 件唯一 R5 缺口（S4 MINOR-4 复核**成立**） ｜ 补中文物理意义（如"第一/第二点横坐标差 [-]"） |
| | | | L41/L65 ｜ MINOR ｜ #2 ｜ 六入参无 Inf 双判；`fX1=Inf` 时 L65 兜底把 `fXv:=_fMid`（中位数亦为 Inf）→ 实值出口 Inf（bDegenerate=TRUE、返回值 FALSE，未伪报） ｜ L41 扩双判，兜底写 0 |
| 18 | FC_DL_BrentBracketIterStep | MINOR | L41-42 vs 头注 L6-7 ｜ MINOR ｜ #12 ｜ 头注称"非有限 → 括号原样回传、uStepKind=0"，实现段 0 预置 `fAnew:=0.0; fBnew:=0.0`（L42），闸命中（L45-49）在 L50 原样回传之前（S4 MINOR-2 复核**成立**） ｜ 二者取一并对齐（建议保留 0 安全侧、改头注） |
| 19 | FC_DL_IterTermJudge | MINOR | L59 ｜ MINOR ｜ #12 ｜ 返回值语义未声明：`TRUE` 仅表示"未命中任何判据（继续）"，命中终止时返回 FALSE，与 `bDone=TRUE` 反向，上层若按"返回 FALSE=失败"理解即误用（头注无返回契约句，违反 R5 头注契约项） ｜ 头注补"返回值 = 继续迭代"契约句，或改为恒 TRUE + 由 bDone 承载 |
| 20 | FB_DL_IterSolverRunner | **MAJOR** | L142 + L176-182 + L184-197 ｜ MAJOR ｜ #8 ｜ 总超时狗 `tonTotal.IN` 仅含 `_eState = eRun`（L142），但 **eEvalLo/eEvalHi 为纯回灌等待相**（L177 仅 `_bFed`、L180 仅"括号零宽"、L185 仅 `_bFed`）→ 调用方漏回灌即**永久挂死且无码**；`fXLo=+Inf` 未闸（L157 只 NaN）→ L173 `_fXCur=Inf`、L135 `|fX - Inf|>eps` 恒丢弃回灌 → 同样挂死 ｜ 超时狗 IN 扩到"非 eIdle/eDone/eFail/eFault"全体驻留相；L157 补 Inf 双判 |
| | | | L36-37 + L211 ｜ MAJOR ｜ #4 ｜ `nIterMax`/`tTimeout` 均无默认值（隐式 0 = 不限）→ **默认组合即两重防死锁同时失效**，与头注 L7-8"双防死锁"名实不符（FB32-2 默认值组合跑闸） ｜ 组态闸内禁止 `nIterMax=0 AND tTimeout=T#0S` 组合（码 1），或给 `nIterMax:=100`/`tTimeout:=T#10S` 默认 |
| 21 | FC_DL_SevenSegBcdDecode | PASS | — （字形位 0-9 逐位复核全对，见第四节 C1；共阳取反 L49 正确；>9 全灭且实值同步 L27/L30 合规） |
| 22 | FC_DL_SevenSegHexCodeCalc | PASS | — （0~15 字形位全对，A-F 近似字形合规；L29 `BYTE_TO_UDINT` 单侧判足够） |
| 23 | FC_DL_SevenSegMinusFlagCalc | **MAJOR** | L12-13/L27-28/L36/L43 ｜ MAJOR ｜ #12 ｜ **跨件极性契约断裂**：本件无极性引脚且头注未声明前提，仅按 `OR` 叠加 g(0x40)/dp(0x80)；而族内 `FC_DL_SevenSegBcdDecode` L6 明确指定"dp 叠加由本件负责"、且其共阳码为取反（亮=0）→ 串联共阳时 OR 置位等于**灭段**，负号/小数点反向消失 ｜ 加 `bCommonAnode` 入参并按极性改 `AND NOT`（共阳）分支；或头注+入参注释硬声明"仅接受共阴码"并在 BcdDecode L6 同步加极性前提 |
| 24 | FC_DL_SevenSegBrightnessPwmCalc | PASS | — （除零闸 L30、UDINT 承载 L36、钳段 L40-44 齐备；代值见 C3） |
| 25 | FC_DL_SevenSegBlinkPhaseCalc | MINOR | L18 vs L34 ｜ MINOR ｜ #12 ｜ 输出注释声明相位域 `[0,1)`，但 `tPeriod<=0` 恒亮路径置 `fPhase:=1.0`（L29/L34）越出声明域 ｜ 注释改 `[0,1]`（并说明 1.0 仅恒亮态）或恒亮态用 0.0 |
| 26 | FC_DL_SevenSegMultiplexPhaseCalc | MINOR | L41-49 ｜ MINOR ｜ #1/#12 ｜ `_nSlotMs` 被抬到 ≥1ms（L42）后，`tScan < uDigitCnt`（如 4ms/8 位）时帧内只覆盖前 4 位，**高位永不点亮且无任何告警**（头注 L6 只声明"防索引恒 0"） ｜ L42 后加 `IF _nSlotMs*_nCnt > _nScanMs THEN` 置组态非法标志/头注声明该退化 |
| 27 | FC_DL_SevenSegGhostGuardCalc | MINOR | L34 ｜ MINOR ｜ #1（R54）｜ `_nBlank := _nSeg + TIME_TO_DINT(tDigitSwitch)` 为 DINT 相加，无溢出预判；两个近 `T#24d` 的 TIME 相加溢出为负 → L40 `>5` 恒假、`bCfgBad=FALSE`、经 L45 输出**负时长** ｜ 按 R54 加法式预判 `IF _nSeg > 5 - TIME_TO_DINT(tDigitSwitch) THEN` 直接钳顶 |
| 28 | FC_DL_PhSlopeEffCalc | PASS | — （斜率 −59.1667 mV/pH、效率 100.011% 与 25°C 名义 59.16 一致；R95 代理阈值三句声明齐备 L6-8） |
| 29 | FC_DL_PhAsymmPotentialCalc | PASS | — （Nernst 温度修正代值 3.000 mV 与验收一致；温度钳定 L48-52 禁外推合规） |
| 30 | FC_DL_OrpRefOffsetCalc | **MAJOR** | L49-50 + L74 + L79 ｜ MAJOR ｜ #2 ｜ 四入参只判 NaN（L49-50），无任何 Inf 双判；`fMeasMv=+Inf` → L74 `fRefCorrMv := _fRefT - Inf = -Inf` → **出口 −Inf** 且 L79 返回 TRUE（伪可信） ｜ 段 1 补四入参 `(x-x)<>(x-x)` 双判；L73-74 后加出口双判 |
| | | | L8 vs L49/L52 ｜ MINOR ｜ #12 ｜ 头注称"闸序即归因序（类型 → 非有限 → 温度）"，实现段序为非有限（段 1）→ 类型（段 2）→ 温度（段 3） ｜ 改头注顺序或调整段序 |
| 31 | FC_DL_TurbidityNtuCalc | **MAJOR** | L41-42 + L47 + L53-64 ｜ MAJOR ｜ #2 ｜ 六入参只判 NaN；`fTransmitV=+Inf` → `_fT=Inf`、`_fS/_fT=0` → `_fNtu=Zero`（**伪读数：相当于"洁净水"**）、`uErrId:=0`、返回 TRUE ｜ 段 1 补双判；L47 前对 S/T 分量加双判 |
| 32 | FC_DL_ChlorineDpdAbsorbCalc | **MAJOR** | L46 + L49 + L60-76 ｜ MAJOR ｜ #2 ｜ 三入参只判 NaN；`fAbsSpan=+Inf` → L60 `_fSlo=0` → `_fC=0` → L76 返回 TRUE、`fChlorineMgL=0`、`bOutOfRange=FALSE`（**伪有效零浓度**，余氯监测"假安全"） ｜ 段 1 补双判；`_fSlo<=0` 时置组态码 |
| 33 | FC_DL_DoSalinityPermCalc | MINOR | L45-46/L66 ｜ MINOR ｜ #2 ｜ 六入参只判 NaN；`fDoMax=+Inf` → L66 上限比较恒假 → 量程钳制静默解除、返回 TRUE（值仍有限） ｜ 段 1 补双判；L49 域闸加 `fDoMax > 1E6` 谱上限 |
| 34 | FC_DL_KcellConstCalc | **MAJOR** | L44-45 + L58-59 + L67-68 ｜ MAJOR ｜ #2 ｜ 四入参只判 NaN；`fTempC=+Inf`（温度测量故障）→ L58 `_fDen=Inf` → L59 `Inf<=0.01` 假 → L67 `fKcellTcorr = _fK/Inf = 0`、L68 **`uErrId:=0` 且返回 TRUE**（伪有效池常数 0 → 下游电导率恒报 0） ｜ 段 1 补双判；`_fDen` 加谱上限（如 >10 判非法）并入 L59 |
| 35 | FC_DL_SodiumPnaCalc | PASS | — （pNa 5.4936 / 5.8036 与验收一致；µg/L 量程 ↔ pNa 8.36~2.36 反算完全吻合；EXPT 结果双判 L79 齐备） |
| 36 | FC_DL_AnalyzerRecalDaysCalc | PASS | — （20 天与验收一致；R151 先钳后转型 L66-71 合规；哨兵 32767 不受钳位影响） |

## 三、12 项定向扫查汇总（逐项给行号证据）

| # | 扫查项 | 结论 | 命中与行号证据 |
|---|---|---|---|
| 1 | 除零/越界（R17 E059） | 34/36 合规，2 件缺口 | **MINOR**：`CornerRoundingRadiusCalc:56`（除子含可 0 的 `fRadiusMm`）、`RotFeedInvTimeCalc:51`（`_fRaw` 无显式非零判据）。全部 `/` 清单已逐件核：分母均有域闸或结构常量（`ArcCenter:46`、`SagFeed:39`、`Swivel:47`、`RegulaFalsi:51`、`Secant:42`、`Parabola:57`、`Brent:62-63`、`Ternary:45`、`Brightness:30`、`Blink:33`、`Multiplex:32/38/42`、`PhSlope:48`、`Turbidity:47`、`Chlorine:49`、`Kcell:59`、`Sodium:73`、`RecalDays:52`）。数组下标：36 件**零数组访问**（无 `[...]` 取址），E059 结构性不适用 |
| 2 | 非有限值闸断实值出口（R19 高发） | **系统性缺口**：NaN 全量枚举 29/29 合格，Inf 双判 **0 件做到全量** | 真穿透/伪有效 6 件：`ArcCenter:38/45/54/64`、`OrpRefOffset:49/74`、`Kcell:44/58/67`、`Turbidity:41/53`、`Chlorine:46/60`、`BisectIter:31/34`（NaN 透传）；零步/伪不推进：`Secant:37-38/55`；Inf 出口：`Illinois:38/42/62`。Inf 双判缺失统计（脚本实扫）：**6 件 0 处**（ArcCenter、Bisect、GoldenSection、Ternary、Brent、OrpRefOffset），其余 23 件只覆盖 1~3 个入参 |
| 3 | 判据同源（先 LIMIT 再判超限） | **36/36 PASS** | 代表证据：`ArcCenter:51`（用原始 `fRadiusMm` 判、L54 才夹 MAX）、`Swivel:62/64`（原始指令判、L71 后限幅）、`SodiumPna:57/59`（原始 `fTempC` 判）、`Chlorine:68`（`bOutOfRange` 用钳前 `_fC`）、`RTCPSeq:101`（原始角度判软限位）、`Turbidity:59/61`（钳前判）、`AnalyzerRecal:66-72`（钳后转型、判据用钳前 `_fDay`） |
| 4 | 冷启动初值（安全侧） | **36/36 PASS** | 29 件 FC 段 0 全部预置安全侧（`fX:=0.0` + 码取最严 + 判据位 TRUE）；2 件 FB 有 `_bInit` 首扫块（`RTCPSeq:124-128`、`IterSolver:149-153`）；`IterSolver` 的 `nIterMax/tTimeout` 无初值虽属安全侧缺口，已计入 #20 MAJOR（属防死锁而非出口初值） |
| 5 | 跨拍状态清零（停车/复位/撤使能） | **2/2 PASS（1 备注）** | `RTCPSeq:124-128` 清 `_bFault/_uFault/_fCompZ/_fAPrev/_fBPrev/_bAngSeen` 并迁 eIdle ✓；`IterSolver:149-153` 清锁存/计数/`_fA/_fB/_fXCur/_bFed` ✓。备注：`_fFa/_fFb/_fFedX/_fFedF` 未入复位清单，但有 `_bFed` 闸且进相即重灌，暂不计缺陷 |
| 6 | 使能门覆盖（后段无条件赋值覆盖前段门） | **36/36 PASS** | 全部采用"单一出口裁决段"结构：`ArcCenter:63-67`、`Helical:60-66`、`ToolLength:43-45`、`RotFeed:50-55`、`SagFeed:52-57`、`Swivel:80-85`、`Corner:60-65`、`RTCPSeq:216-224`、`IterSolver:243-255`、`MinusFlag:42-44`、`Ghost:39-46` 等，无"段尾无条件覆盖前段使能/故障门" |
| 7 | 状态机 ELSE 兜底回安全态 | **2/2 PASS** | `RTCPSeq:207-208`（ELSE → 码 6 + eFault）、`IterSolver:234-235`（ELSE → 码 6 + eFault）；两件枚举成员与 CASE 标签一一对应（6/6、7/7），无 `eFault` 落 ELSE 的历史缺陷（FB32-5） |
| 8 | 定时器无条件调用 + 许可 AND | 1 件 MAJOR | 两件 FB 的 `TON/R_TRIG` 均在段 0、CASE 之前无条件刷新（`RTCPSeq:115-118`、`IterSolver:140-143`）✓；`RTCPSeq` 稳定窗挂相驻留+`_bAngStable`、超时狗挂 `相驻留 AND NOT _bFault`（R145 合规）✓。**MINOR→MAJOR 缺口**：`IterSolver:142` 使能域不含 eEvalLo/eEvalHi（见 #20） |
| 9 | 量纲/系数（代值回代） | **12 件回代全部量级正确** | 见第四节；唯一异常为 `CornerRounding:56` 的"比率"恒等于 1（语义缺陷，已记 MAJOR），其量纲本身正确 |
| 10 | 双语注释（R5） | 35/36 PASS | 唯一缺口 `ParabolaVertex:27-29`（英文单语，DECL_NO_CJK）；**空注释 0 处**、中文单语 0 处、英文 <3 字母 0 处（脚本全量扫 36 件 × 全部 VAR/VAR_INPUT/VAR_OUTPUT/VAR/VAR CONSTANT 行） |
| 11 | 语法收尾（注释配平/分号/终结符） | **36/36 PASS** | `(*` 与 `*)` 计数全配平且嵌套深度归零（含 FAIL 件同源缺陷 N6 形态零命中）；**全角 `）` 作注释收尾 0 处**；VAR 声明缺分号 0 处；`FUNCTION/END_FUNCTION`、`FUNCTION_BLOCK/END_FUNCTION_BLOCK`、`TYPE/END_TYPE`、`METHOD/END_METHOD` 计数全等；代码区非 ASCII 字符 0 处 |
| 12 | 接口自洽（出口未赋值/METHOD 配对） | 36/36 机械项 PASS，1 件契约缺口 | 脚本扫全部 VAR_OUTPUT 标识符在主体中的 `:=` 赋值点：**未赋值路径 0 件**（36 件全命中）；`METHOD CalcPivotComp`（RTCPSeq:76-112）、`METHOD NextTrial/FeedEval`（IterSolver:80-137）声明+实现配对 ✓。契约缺口：`MinusFlag` 与族件 `BcdDecode:6` 的 dp 叠加契约在共阳下不成立（MAJOR #23） |

## 四、代数值回代表（14 件，含 4 族各 ≥3 件）

| 族 | 件 | 输入 | 手算/脚本回代 | 量级判据 | 结论 |
|---|---|---|---|---|---|
| A Motion | ArcCenterOffsetCalc | P1=(0,0) P2=(10,0) R=6 bCcw=1 | `_fH=√11=3.3166`；d=(5.0000, 3.3166)；\|c−P1\|=\|c−P2\|=6.0000；扫掠角 112.89°<180° | 两径等长=6 ✓、劣弧判定成立 ✓、偏移 < 弦长 | 正确 |
| A | RtcpPivotOffsetCalc | L=300 A=30° B=0° | v=(0,−0.5,0.8660)（\|v\|=1）；off=(0,−150.0,−40.19)，模长 155.29 | 补偿量 155 mm **< 枢轴长 300 mm**（<刀具长度量级）✓ | 正确 |
| A | SagFeedLimitCalc | R=50 e=0.02 a=2000 T=4ms | `v_sag=707.11 mm/s=42426 mm/min`；`v_acc=316.23 mm/s=18974 mm/min` | 取小 18974 mm/min≈19 m/min（合理进给域）；bLimited=FALSE（向心更紧）✓ | 正确 |
| A | CornerRoundingRadiusCalc | θ=90° segA=segB=100 feed=5000 j=50000 | `_fRmax=50·tan45=50 → r=min(50,20)=20`；`v_jerk=(5e4·400)^⅓=271.44 mm/s=16287 mm/min`；feed=min(5000,16287)=5000 | r=20 mm（20 mm 硬上限生效）✓；**fJerkRatio 恒 1.000000，按实际采用进给应为 0.0289** ✗ | 量级正确，比率输出缺陷（MAJOR #8） |
| A | HelicalTurnAdvanceCalc | pitch=2 R=20 feed=1000 rpm=5000 | Vz=10000 mm/min；每转弧长 2πR=125.66 mm；合成 10049.9 mm/min | pitch 2 < 125.66 → 升角 atan(2/125.66)=0.91°<45°，码 0 ✓ | 正确 |
| B Algo | RegulaFalsiIterStep | a=0 b=2 fa=−1 fb=3 | den=4；x=0−(−1)·2/4=0.5；width=MAX(0.5,1.5)=1.5 | 新点落在括号内且宽度守恒 ✓ | 正确 |
| B | SecantIterStep | x0=1 x1=2 f0=−1 f1=3 | den=4；x=2−3·1/4=1.25；delta=−0.75 | 步长 < 区间尺度、方向朝根（x²−? 型）✓ | 正确 |
| B | ParabolaVertexIterStep | x=(0,1,2) f=x² | num=0 den=2 → xv=0.0；curv=1.0 | x² 顶点 0、二阶系数 1.0（精确）✓ | 正确 |
| B | GoldenSectionIterStep | a=0 b=1 tol=0.01 | x1=0.381966 x2=0.618034 w=0.618034 | 0.618 收缩率 ✓、未达容差 bConverged=FALSE ✓ | 正确（唯 DL_GSD_PHI 命名相反） |
| C Base | SevenSegBcdDecode | 0~9 全量 | 逐位复核 9 个字形的 a..g 位图**全对**；8→0x7F；共阳取反→0x80（仅 dp 熄灭位为高） | 全部字码 < 0x80，**位落 8 位内** ✓ | 正确 |
| C | SevenSegHexCodeCalc | 0~15 全量 | 10→0x77(A) 11→0x7C(b) 12→0x39(C) 13→0x5E(d) 14→0x79(E) 15→0x71(F) | 均为标准近似字形且 <0x80 ✓ | 正确 |
| C | SevenSegBrightnessPwmCalc | lvl=100 full=255 min=10 | 100·255/255=100；lvl=1→1<10→抬到 10 且 bAtMin=TRUE | 占空域 [0,255] ✓、中间积 65025 由 UDINT 承载 ✓ | 正确 |
| C | SevenSegMultiplexPhaseCalc | scan=20ms cnt=4 tNow=13ms | slot=5ms；idx=(13 MOD 20)/5=2 | 索引 0..3 内 ✓（帧覆盖不足情形另计 MINOR） | 正确 |
| D Device | PhSlopeEffCalc | mV1=0/pH1=7; mV2=177.5/pH2=4 | S=177.5/(4−7)=**−59.1667 mV/pH**；eff=59.1667/59.16·100=100.011% | 与 **25°C 理论 −59.16 mV/pH** 吻合 ✓ | 正确 |
| D | KcellConstCalc | 1413 µS/cm, 100 Ω, T=35, α=2%/°C | K=1413e-6·100=**0.1413 1/cm**；den=1+0.02·10=1.2；Kc=0.1178 | 与头注 0.1413/0.1178 一致 ✓ | 正确（Inf 通道另计 MAJOR） |
| D | SodiumPnaCalc | mV=−325 T=25 sel0/1 | pNa=325/59.16=5.4936（µg/L=73.8）；sel1: 325/56=5.8036（36.2） | 量程 0.1~1e5 µg/L ↔ pNa **8.36~2.36** 反算与头注完全吻合 ✓ | 正确 |
| D | TurbidityNtuCalc | S=800 T=400 D=0 K=2 Zero=0.2 | ratio=2.0；NTU=2·2+0.2=4.2 | 与头注 4.2 一致 ✓ | 正确 |
| D | OrpRefOffsetCalc | meas=550 T=25 nom=199 type0 | refT=199+0.2·0=199；offset=199；corr=199−199=0 | SHE 换算量级 mV 级 ✓ | 正确 |
| D | ChlorineDpdAbsorbCalc | A=0.40 A0=0.02 span=1.00 档0/1 | slope=2.0→C=0.76；slope=5.0→C=1.90 mg/L | 与头注一致、量级合理（余氯 0~5 mg/L）✓ | 正确 |
| D | AnalyzerRecalDaysCalc | limit=2 now=0.5 rate=0.05 已标定 10 天 | (2−0.5)/0.05−10=**20 天** | 与头注一致 ✓ | 正确 |
| D | DoSalinityPermCalc | C=8 T=25 S=35 K=1 kT=2% | 8+0.084·35=**10.94 mg/L**；kt@25=1.0 | 0.084 mg/L per ‰ = 84 µg/L 每 g/kg（mg/L↔µg/L 差 1000× 换算正确）✓ | 正确 |

## 五、三道去重结论（全量 36 件，不抽样）

**道 1 名称（registry 2041 条，规范化后编辑距离 ≤3）**
- 精确同名：0。
- 全库最近邻（去 `FC_/FB_/DL_` 前缀后全称编辑距离）：最小 **5**（`FC_DL_SecantIterStep` ↔ `FC_DL_QuantizeStep`，语义无关）；其余 ≥6。**≤3 命中 0 件**。
- 批内互比：8 件 `*IterStep` 同后缀族，但基名（Bisect/RegulaFalsi/Secant/Illinois/GoldenSection/TernaryNarrow/ParabolaVertex/BrentBracket）互异，编辑距离 ≥10。→ 道 1 判 **0 命中**。

**道 2 签名指纹（入参+出参类型序列，1549 条；剔除全 REAL 桶）**
- 全 REAL 桶 3 件：`CornerRoundingRadiusCalc`、`RegulaFalsiIterStep`、`TernaryNarrowIterStep`。
- 唯一命中：`FC_DL_TernaryNarrowIterStep` sig=`685268c4204f1c53` ↔ `FC_DL_PolarDecomp2D`（**落在被剔除的全 REAL 桶**，历史 28 条假阳性即此桶）。语义比对：三分收缩（区间→区间）vs 极分解（矩阵→两分量），入参域/输出语义均不同 → **不拒收**。
- 剔除全 REAL 桶后有效命中 **0 件**；`api` 词根指纹命中 0 件。→ 道 2 判 **0 命中**。

**道 3 功能语义（同族不同阶/精度变体/协议方言属有效变体）**
- **求根单步族 8 件（DL_Algo）**：算法阶互异（二分/试位/割线/改进试位 Illinois/黄金分割/三分/抛物线顶点/Brent），入参形态各异（2 值/4 值/5 值/7 值、有无 `fFa`、是否括号型），输出语义不同（括号对/新点/探针/顶点/步型码）→ **有效变体，不拒收**。与库内 `FC_DL_NewtonRaphson`（多项式系数 + 解析导数，含 `FC_DL_NewtonStep` 两入口范式）分属导数型 vs 括号型两支，且本族无函数指针依赖 → **非同义**。
- **七段显示族 7 件（DL_Base）**：字形译码/十六进制字形/负号与 dp 叠加/亮度 PWM/闪烁相位/多路扫描相位/鬼影消隐，输出语义互异、无两项同输入同输出 → **不拒收**。（本轮另 1 件 FAIL `FB_DL_SevenSegMultiplexSeq` 是相序机，不属本族同义体）
- **水质分析族 9 件（DL_Device）**：pH 斜率效率/不对称电位/ORP 参比偏移/浊度 NTU/DPD 余氯/DO 盐度渗透/电导池常数/钠 pNa/标定天数。逐条比对库内近邻：`FC_DL_CentrateTurbidityIdx`（浊度相对基线指数，入 NTU 出指数）vs `TurbidityNtuCalc`（入三路光电压出 NTU）输入输出域不重叠；`FB_DL_WaterChlorineDoseTrim`（加药微调）vs `ChlorineDpdAbsorbCalc`（吸光度→浓度）不同层；`FB_DL_AnalyzerSampleSeq`（采样时序）vs `AnalyzerRecalDaysCalc`（漂移天数）不同语义 → **不拒收**。
- **RTCP/运动族 10 件（DL_Motion）**：与 `FC_DL_WebSagCalc`（张力→垂度）vs `SagFeedLimitCalc`（弦高容差→进给上限）输入输出域正交；`FC_DL_TrackingOffsetChk`（脉冲折算位移漂移）vs `RtcpTrackingErrCalc`（三维偏差模长）不同 → **不拒收**。`FB_DL_PathCornerBlend` vs `FC_DL_CornerRoundingRadiusCalc` 语义相邻，列入**存疑放行**（见第六节）。
- 结论：真同义 **0 件**，拒收 **0 件**。

## 六、拒收清单 / 存疑放行

**拒收（0 件）**：无。

**存疑放行（报 S0 复议，不阻断入库）**
1. `FC_DL_CornerRoundingRadiusCalc` ↔ 库内 `FB_DL_PathCornerBlend`（DL_Motion）：同用 `拐角角+两段长` 入参，但前者反解"半径上限 + 拐角进给 + jerk 比"，后者正向解"切点距 + 弦高误差 + 回夹标志"，输出语义不同。**建议**：S0 确认是否需在 README 同族索引里互相引用，避免用户误选。
2. `FB_DL_RtcpFiveAxisSeq:34/131` 的 `nAxisMode` 死引脚：若确认"模式仅作组态门控"（非计算分支），则 MAJOR 可降为 MINOR（补头注声明即可），**需 S0 裁决口径**。
3. `FC_DL_CornerRoundingRadiusCalc:56` 的 `fJerkRatio`：若原意是"系数回代自检位"（N5），则应改名 `bJerkCalibOk` 并改头注，而非按使用率修公式——**需 S0 裁决该输出的契约语义**。

## 七、系统性漏洞与规则建议（供 S0 写入红线）

| 编号 | 现象 | 覆盖 | 建议 |
|---|---|---|---|
| SYS-1 | **Inf 通道系统性敞开**：36 件 NaN 判据 29/29 全量枚举，但 Inf「差值自减」双判 **0 件做到全量**（6 件 0 处、23 件部分覆盖）。成因：模板只下沉了 N1（NaN）判据，实战规则 15/FB51-2 的 Inf 要求未进模板 | 影响 29 件浮点件 | 写入红线：「非有限闸 = NaN 自反 + Inf 差值自减，**入参集合必须全量枚举**，且出口实值同闸」；并作为 `dl_gate` 新机检锚点（当前 gate_gaps 已自承 N4_nan_pass 双漏，Inf 更无判据） |
| SYS-2 | **「判据位置位、实值照旧污染」同型复发**（R19 老谱）：`BisectIterStep:31/34` 把原始 NaN 入参直接预置成出口 | 1 件已确证 | 写入红线：「故障/非有限路径的连续量出口禁止镜像原始入参；预置值必须是常量 0 或上一有效快照」 |
| SYS-3 | **头注契约与实现二元分歧**：6 件头注宣称"非有限→落安全侧/固定码"，实现只覆盖 NaN（ArcCenter L45 更把 NaN 判据注释成"Inf 入参所致"）。gate 的 `systemic` 已记录"版本头 40/40 缺 VERSION"同类问题 | 6 件 | 建议 gate 增「头注边界句 ↔ 实现闸位」对拍项（自然语言无法机检，但可锚定"头注出现 Inf/非有限 + 正文无 `(x−x)<>`" 即报警） |
| SYS-4 | **代数恒等式型伪输出**：`CornerRounding:56` 把"用限制值算出的量"再代回限制式，比值恒 1。此类"回代自检位"与"使用率位"混淆在算法族易复发（本族 8 件均有 `fRatio/fJerkRatio/fWidthNew` 类比率出口） | 1 件已确证 + 族风险 8 件 | 建议红线：「比率类出口的分子分母必须来自**不同来源**（限制值 vs 采用值）；同源回代式只能作为内部断言，禁作 VAR_OUTPUT」 |
| SYS-5 | **跨件极性契约缺位**：`BcdDecode:6` 指定 dp 叠加归 `MinusFlagCalc`，但后者无极性引脚/无极性前提声明，共阳链断裂。属"文件名避让绕过接口一致性"的变体 | 2 件 | 建议红线：同族件的"极性/字节序/量纲方向"类隐含前提，必须在**双方**头注互写，或加显式引脚 |
| SYS-6 | **看门狗相域覆盖不全**：`IterSolver:142` 只守 eRun，纯等待相（eEvalLo/eEvalHi）无超时 → 静默挂死。与历史 RailPowerSequence「推进/超时不同源」同型 | 1 件 | 建议红线：「回灌/握手类等待相的驻留必须有超时出口」；gate 增「等待相集合 ⊇ 超时狗使能域」机检锚点 |

> 族级触发：SYS-1 影响 29 件（≥3 件同型阈值），**建议 S0 触发扩面复审**（对已入库全库同类件做一次 Inf 通道普查）。
