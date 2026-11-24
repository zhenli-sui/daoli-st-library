# QA_REVIEW_R79_A —— R79 批 1 审校 + 三道去重（dlf-qa-dedup 本人产出）

- 轮次 R79 / 批 1｜日期 2026-11-24｜范围：日历 9 + 数论 8 + 几何 8 = **25 件**
- 方法：25 件逐件全文阅读（非抽样）+ 8 件既有邻居件全文/契约比对；12 项扫查逐项给行号
- 结论计数：**PASS 7 ｜ PASS-WITH-MINOR 5 ｜ MAJOR（可入库挂账）3 ｜ 存疑放行 2 ｜ 拒收 8**

## 一、逐件表

| # | 文件 | 结论 | 扫查命中项（行号） | 去重结论（比对对象 → 判据） |
|---|---|---|---|---|
| 1 | FC_DL_CalIsLeapYear | **拒收** | 9: L45-46 年域外只 `RETURN` 不置 bError，族内 7 件同情形置 bError（口径分裂） | 对 `DL_Base/FC_DL_LeapYearChk` L86-94：同 4/100/400 三律、同布尔合成式；后者 `bFullRule:=TRUE` 即等价 → 参数已覆盖（R447） |
| 2 | FC_DL_CalMonthDays | **拒收** | 11: L57-59 `nYear<1583` 静默按平年 28 天，bValid 仍 TRUE（事实口径）；L49-52 月份闸为唯一故障口 | 对 `DL_Base/FC_DL_DaysInMonthChk` L134-167：同月长表（1,3,5,7,8,10,12 / 4,6,9,11 / 2 闰分档），同映射 |
| 3 | FC_DL_CalDayOfYear | PASS-WITH-MINOR | 11: **L29 常量注释「v1.0.1 补」与 L2 版本 v1.0.0、L14「首版」矛盾**；L57 已有 9999 上界闸（P4 已落地） | 无同映射件（`DateToDintDays` 是 1970 历元天数，非年内序号）→ 有效变体 |
| 4 | FC_DL_CalDateFromDayOfYear | PASS-WITH-MINOR | 手算校验 L71-86：366→(12,31)、365→(12,30)、60→(3,1)、31→(1,31)、1→(1,1) ✔；MINOR 同 L29 版本口径 | 无同映射件（`DintDaysToDate` 是历元天数→日期）→ 有效变体 |
| 5 | FC_DL_CalWeekdayIndex | **拒收** | **MAJOR：L56 域闸缺 `nYear > DL_GREG_LAST`（闸席 P4 点名 4 件之一，本件漏修）**；L80 `365*nY2`，nYear ≳ 5.88×10⁶（365×nY2 超 2³¹−1）即回绕为负 | 对 `DL_Base/FC_DL_DayOfWeekCalc`：同 (y,m,d)→星期，仅 0=周一 vs 1=周一 基数差 → 按 R64/R78 明确「基数偏移非有效变体」 |
| 6 | FC_DL_CalIsoWeekNo | **拒收** | **MAJOR：L80 域闸缺年上界（P4 漏修）**，L103/L104 同源回绕；算法手算 3 例 ✔（2024-01-01→W01、2021-01-01→2020-W53、2025-12-29→2026-W01）；L119 上一年闰律第三次内联 | 对 `FC_DL_WeekNumIsoCalc`（ISO 周+周年）**且** `DL_Base/FC_DL_WeekOfYearCalc` L55-63（ISO 周+周年）→ 一新件对两存量件 |
| 7 | FC_DL_CalQuarterIndex | PASS | 清（L38 月份闸；L44 `(m-1)/3+1` 除数常量，边界 3/6/9/12 ✔） | 库内无月→季件（`FB_DL_QuarterCellCutSeq` 为机序）→ 新功能 |
| 8 | FC_DL_CalIsWeekend | **存疑放行** | L61 域闸完整（含年上界）；L89 `nDow>=5` ✔ | 无独立周末谓词件；但 L5 自述「与 CalWeekdayIndex 同口径内联」= 派生封装，弱差异（详见复议） |
| 9 | FC_DL_CalMonthEndDate | **拒收** | L51 域闸完整（含年上界） | **批内互撞**：#2 与 #9 同为 (年,月)→当月天数，仅出口形态差（DINT vs BOOL+nLastDay）→ R463 同构；且同映射再次命中 DaysInMonthChk |
| 10 | FC_DL_IntSqrtFloorUdint | PASS-WITH-MINOR | 9/12: L63 `nIter>=64` 与收敛共用计数器（恰第 64 次收敛会误置 bError，结构不可达）；手算 0/1/2/3/4/MAX ✔ | 对 `SqrtEx`(LREAL)、`InvSqrtApprox`：整数 UDINT 精确域 → 有效类型域变体 |
| 11 | FC_DL_IntIsPerfectSquareUdint | PASS-WITH-MINOR | 12: L68 `nApprox>65535` 恒不成立（⌊√UDINT_MAX⌋=65535）死分支；手算 0/1/2/4/9 ✔ | 无同映射件 → 新功能 |
| 12 | FC_DL_IntDigitSumUdint | PASS | 清（L45 守卫 10 恰覆盖 UDINT 10 位） | 无同映射件 |
| 13 | FC_DL_IntDigitCountUdint | PASS | 清（L44 `>=10` 降位，MAX→10 位 ✔） | 无同映射件 |
| 14 | FC_DL_IntPowSatUdint | **MAJOR×2** | ①L70-71 平方钳位到 MAX **未置 bOverflow**（实测 2^32/3^32 → 返回 MAX 且 bOverflow=FALSE，与 L6-7 契约相反）；②**L77-79 `nIter>=32` 把「恰 32 次合法完成」判为不收敛** → nBase∈{0,1} 且 nExp≥2^31 时 bOverflow 误报（手算 1^2^31 → 返回 1 + bOverflow=TRUE）；L78 注释「v1.0.1」与头注 v1.0.0 矛盾 | 对 `PowIntSat`(LREAL 底) → 整数饱和域为有效变体 |
| 15 | FC_DL_IntDivModSafe | **拒收** | 12 项清（L48 除零闸、L54 下界/−1 特判 ✔） | 对 `FC_DL_DivDintSafeChk` L32-41/L61-64：同 DINT 入、同「商+余」双出口、同除零闸、同 DINT_MIN/−1 特判 → 逐项同一契约 |
| 16 | FC_DL_IntSignExtractLreal | **拒收** | 3: L46/L54 非有限闸为本库正确范式（清） | 对 `FC_DL_SignumCalc` L22-25：±1/0 三值、非有限拦截；其 `fEps` 入参传 1.0E-12 即复现本件死区 → 参数已覆盖 |
| 17 | FC_DL_IntReverseDigitsUdint | PASS | 清；手算 120→21、MAX→饱和、反算式 `(MAX-d)/10` 保守正确 | 对 `BitArrayReverse`/`ReverseBitsWord`（位反转）→ 十进制位反转，不同域 |
| 18 | FC_DL_GeoPointLineDist | PASS | 清（L51 NaN 六点闸、L61 长度非有限闸、L66 退化闸、L79 除数已证非零） | 对 `EuclidDist2DCalc`/`CalcDistance2D`（点-点）→ 点-无限长线，不同几何 |
| 19 | FC_DL_GeoLineIntersectXY | **拒收** | 10: L75-77 把「平行」判为 bError=TRUE | 对 `FC_DL_LineIntersection` L183-196（`bSegmentMode:=TRUE` 时 t,u∈[0,1] 才返回 TRUE）+ L131-141：同映射；且新件口径与后者「线段模式平行属业务判定、不置码」**相反** |
| 20 | FC_DL_GeoPointInRectXY | PASS | 清（L49 NaN、L53 量级、L63 退化、L69 容差窗口，无等号判等） | 库内无点在矩形件（`RangeOverlapCheck` 是 1D 区间） |
| 21 | FC_DL_GeoPointInConvexQuadXY | PASS-WITH-MINOR | 11: L14-15 遗留假设只声明「顶点序由调用方保证」，**未声明「四边形必须凸」**；凹四边形入参静默误判且不置 bError | 无同映射件 |
| 22 | FC_DL_GeoCentroid3Pt | PASS | 清（L50 NaN、L57 非有限、L61 共线闸、L67 除数常量 3） | 对 `PolygonArea`（面积非质心）→ 新功能 |
| 23 | FC_DL_GeoPolylineLenFixed | **MAJOR** | ①**L53-55 `nCnt>10` 静默钳位继续算 → 总长被低估且 bValid=TRUE、bError=FALSE**（与 DaysInMonthChk 明文「钳位即伪造事实、域外拒绝」相反）；②11: L12 声明「非有限段由出口自证拦下」，L70 只拦 NaN，Inf 直穿 | 无同映射件（`CalcDistance2D` 单段） |
| 24 | FC_DL_GeoBBoxFromPtsFixed | **MAJOR** | 同源 L60-62：`nCnt>10` 钳位 → 包围盒**欠覆盖**（漏第 11 点起），bValid=TRUE，视觉 ROI 静默漏点 | 无同映射件（`SearchMinMax*` 是标量） |
| 25 | FC_DL_GeoLineAngleXY | **存疑放行** | 象限补偿手算 ✔（Q2/Q3/负 X 轴归一 +π）；L86 用长度容差 1e-9 比角度 | 对 `FC_DL_Atan2Ex` L15-24：同 (−π,π]、同四象限分支；差异仅「4 绝对坐标 vs 2 分量」+ 重合语义内建；**其 L4-6「刻意不用 ATAN2 因形参序歧义」理由不成立——库内 Atan2Ex 已封住该歧义** |

## 二、拒收清单（8 件，含被拒件名 / 重复对象 / 证据）

| 被拒件 | 重复对象 | 证据（函数契约对比） | 是否有效变体 |
|---|---|---|---|
| CalIsLeapYear | DL_Base/FC_DL_LeapYearChk | 被拒 L51-56 三余数合成 ≡ 对方 L86-94；对方 `bFullRule:=TRUE` 即等价 | 否：域扩到 1583 只需改对方 DL_YEAR_MIN/MAX 两常量 |
| CalMonthDays | DL_Base/FC_DL_DaysInMonthChk | 被拒 L62-72 月长分支 ≡ 对方 L134-167；同 31/30/2 月闰分档 | 否：同上，且本件 pre-1583 静默伪造平年 |
| CalMonthEndDate | **批内 CalMonthDays** + DaysInMonthChk | 两件均 (年,月)→当月天数；仅出口形态差 | 否：R463「形参归一后同构即拒其一」 |
| CalWeekdayIndex | DL_Base/FC_DL_DayOfWeekCalc | 被拒 L80-83 JDN mod 7（0=周一）≡ 对方 Sakamoto→ISO（1=周一） | **否**：仅基数偏移（R64/R78 明文） |
| CalIsoWeekNo | FC_DL_WeekNumIsoCalc **及** DL_Base/FC_DL_WeekOfYearCalc | 三件同为 (y,m,d)→{ISO 周 1..53, ISO 周年}；被拒 L109-132 的周式/跨年归属 ≡ 两存量件 | 否：新件是**第三**套实现（存量两件已互为邻件） |
| IntDivModSafe | FC_DL_DivDintSafeChk | 被拒 L48-62 ≡ 对方 L61-64：除零闸 + DINT_MIN/−1 特判 + 商余双出口 + 余数由乘法自证 | 否：输出通道数/类型全同，仅命名与码位范式不同 |
| IntSignExtractLreal | FC_DL_SignumCalc | 被拒 L46-70（NaN→死区 1e-12→±1）≡ 对方 `lrIn+fEps`，传 `fEps:=1.0E-12` 即逐拍同值 | 否：参数已覆盖（R447） |
| GeoLineIntersectXY | FC_DL_LineIntersection | 被拒 L81-93 ≡ 对方段 7-8（`bSegmentMode:=TRUE`）；后者另有 t/u 出参 | 否：且错误分级口径反而倒退 |

> 复议口径（供总监二选一，非拒收理由）：若认定「1583~9999 全域 + DINT + R297 零码位」构成有效数据域变体，正确做法是**改存量件的域常量**（LeapYearChk 的 DL_YEAR_MIN/MAX、DaysInMonthChk 的 DL_DIM_YMIN/YMAX 共 4 个常量），而非并行第三套实现。

## 三、MAJOR 清单（可入库，须挂账）

| 件 | 行号 | 后果 |
|---|---|---|
| IntPowSatUdint | L70-71 | 底数平方钳到 MAX 未置 bOverflow：nBase=2/3, nExp=32 返回 16#FFFF_FFFF 且 bOverflow=FALSE，违反 L6-7 契约；闸席 P2 指定修此行，**未落地** |
| IntPowSatUdint | L77-79 | nExp≥2^31 时迭代恰满 32 次（合法完成）被判不收敛 → nBase∈{0,1} 返回 1/0 却 bOverflow=TRUE 误报；此为**闸席未要求的改动所引入** |
| GeoPolylineLenFixed | L53-55 | nCnt>10 钳位后返回被低估的总长，bValid=TRUE 无任何降级标志；下游轨迹余量核算直接吃错值 |
| GeoBBoxFromPtsFixed | L60-62 | 同源：包围盒漏第 11 点起，视觉 ROI 欠覆盖且无标志 |
| CalWeekdayIndex | L56 | 闸席 P4 点名、**漏修**：nYear ≳ 5.88×10⁶ 时 L80 回绕，星期/周末静默错值（同族 CalIsWeekend L61 已有闸，两件代码同构但防护不一致） |
| CalIsoWeekNo | L80 | 同上漏修，L103/L104 回绕 → ISO 周号静默错值 |

## 四、MINOR 清单（留档，不阻塞入库）

| 件 | 行号 | 瑕疵 |
|---|---|---|
| CalDayOfYear / CalDateFromDayOfYear / CalIsWeekend / CalMonthEndDate / IntPowSatUdint | L29 / L29 / L31 / L28 / L78 | 常量注释写「（v1.0.1 补…）」而头注版本仍 v1.0.0 且修订历史无该条 → 版本口径分裂（**与 R78-B #27/#28 同型，已连续两轮**） |
| CalDayOfYear / CalDateFromDayOfYear / CalIsWeekend / CalMonthEndDate | 同上 | 注释理由「防 int64/日期串溢出」在纯 DINT 整数件内不成立（无 int64、无日期串） |
| IntSqrtFloorUdint / IntIsPerfectSquareUdint | L63 / L62 | 收敛判据与迭代上限共用 `nIter`，恰在上限拍收敛会误置 bError |
| IntIsPerfectSquareUdint | L68 | `nApprox>65535` 结构性恒假 |
| GeoPolylineLenFixed | L12 vs L70 | 声明「非有限段由出口自证拦下」，实际只拦 NaN，+Inf 直穿返回 |
| GeoPointInConvexQuadXY | L14-15 | 未声明「必须凸」，凹四边形静默误判 |
| GeoLineAngleXY | L86 | 长度容差 1e-9 用于角度比较（量纲串用） |
| CalIsLeapYear | L45-46 | 族内「年域外」分级分裂（本件不置 bError，其余 7 件置） |

## 五、族级系统性缺陷（报总监，触发扩面审视）

**S1 闰年律唯一属主被绕过**：9 件日历件中 **6 件内联 4/100/400 判据**（CalMonthDays L58、CalWeekdayIndex L60、CalDayOfYear L61、CalIsoWeekNo L75+L119、CalIsWeekend L65、CalMonthEndDate L57），而 `DL_Base/FC_DL_DaysInMonthChk` L8-11 已明文规定「闰年律**唯一属主**为 FC_DL_LeapYearChk，**零内联**（常量单源纪律）」。历法口径将来任何调整需同步 7 处 → 建议本族改「组合调用 + 域常量上移」，而非各件自足。
**S2 静默钳位 3 件**（GeoPolylineLenFixed、GeoBBoxFromPtsFixed、CalMonthDays）与库内「R81 事实口径：钳位即伪造事实、域外拒绝」冲突。
**S3 存量双胞胎**：`FC_DL_WeekOfYearCalc`（DL_Base）与 `FC_DL_WeekNumIsoCalc`（DL_MathData）同为 ISO 周+周年，本次新件若入库将成三胞胎 → 交总监清理存量。

## 六、挂账清单（按下一轮优先级）

1. **P1 修复回验（最高）**：IntPowSatUdint 原缺陷未修 + 新误报 → 按闸席行号重做并逐行回验（本批已证「已修复」回执不可信）。
2. **P2**：CalWeekdayIndex L56 / CalIsoWeekNo L80 补 `nYear > 9999` 闸（P4 漏件）。
3. **P3**：GeoPolylineLenFixed / GeoBBoxFromPtsFixed 钳位改「bClamped 标志或域外 bError」。
4. **P4**：8 件拒收件删除或改存量件域常量（净减 8 件，registry 计数需相应调整）。
5. **P5**：5 处「v1.0.1」版本口径 + dl_gate 新增锚点（注释内 vX.Y.Z 必与头注 Version 一致）。
6. **P6**：S1 闰年单源化、S3 存量 ISO 周双胞胎清理。

## 七、存疑放行（2 件，请总监复议）

| 件 | 弱差异 | 我倾向 |
|---|---|---|
| CalIsWeekend | 相对 DayOfWeekCalc 仅多一次阈值比较（`>=eSaturday`） | **放行**：库内无独立周末谓词，且已声明「不含法定节假日/调休」边界 |
| GeoLineAngleXY | 相对 Atan2Ex 仅多两次减法 + 重合语义；头注新建理由不成立 | **放行（附条件）**：头注删除「ATAN2 形参序歧义」论证并改为「Atan2Ex 的点对适配器」，否则按重复处理 |

## 八、12 项扫查总账（25 件全覆盖）

1 双语注释覆盖率：25/25 全 VAR 声明行含 `// 中文 / English`，**零缺**（awk 逐行扫）。
2 分号完整性：25/25 声明行分号在 `//` 之前，**零缺**。
3 构造式转换：`LREAL(`/`DINT(`/`UDINT(`/`INT(`/`BOOL(` 作转换用 **零命中**。
4 保留字撞名：AT/TO/OF/END/TYPE/VAR/REAL/TIME/INT/AR/AND/MOD/TRUE/FALSE 作标识符 **零命中**。
5 数组定长：`ARRAY[*]` **零命中**；两件用 `ARRAY[1..10]`，循环上界由钳位保证。
6 除零/取模零：所有 `/` `MOD` 分母为常量或先证非零（IntDivModSafe L48、IntSqrtFloor L51、GeoPointLineDist L66+L79、IntPowSat L61/L70、IntReverseDigits L54）**零缺闸**。
7 溢出闸：见 MAJOR 表（IntPowSat L70-71、L77-79）；IntReverseDigits 反算式与 IntIsPerfectSquare 回乘前拦均正确。
8 浮点容差：**零处**用 `=`/`<>` 直接比较 LREAL 数值；NaN 一律 `x<>x`，无穷一律 `>1.0E308`。
9 返回值全路径 + bError/bValid 一致：25/25 预置出口 + 分支全覆盖（逐个 RETURN 路径核对）。
10 错误码口径：**25/25 为 R297 零码位**，`eErr` 恒 0，**零处** `16#` 码位（与全库码位总账零冲突）。
11 头注与实现一致：8 处不一致（MINOR 表）+ IntPowSat 契约违背（MAJOR）。
12 死代码/不可达：IntIsPerfectSquare L68、IntSqrtFloor L63-67 边界、CalDateFromDayOfYear L86 后无可达语句外，无未初始化/不可达输出路径。
