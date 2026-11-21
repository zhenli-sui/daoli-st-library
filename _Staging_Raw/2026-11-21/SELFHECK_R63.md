# SELFHECK_R63（阶段三编码执行 · 编码侧自检记录）

> 执行人：PLC 编程专家（plc-programming-expert）｜ 2026-11-21 ｜ 单次调用内完成
> 范围：返修 5 件 + 新件 13 件 = 18 件落盘与逐件红线自检；注册 / JSONL / 机检由主控统一执行（本文件只供其查冲突与复核）。

---

## 1 返修批 R（5/5 完成）

| # | 文件 | 目标版本 | 修法落地情况 | 红线自检 |
|---|---|---|---|---|
| R1 | C:\Library\DL_Device\FB_DL_VfdDcBusRipple.st | **v1.0.1**（磁盘原 1.0.0，按「禁跳号」递增 MINOR 补丁位；派单书标注目标 v1.0.2 与磁盘版本不一致，如实登记见 §5） | 段 3 后新增**段 3A 组态非法结构早退**：出口三件套（bValid=FALSE + eErr=0710 + bError=TRUE）+ RETURN；段 6 均值除法与段 8 (fAvg/fUdNom) 除法在组态故障拍结构性不可达；头注释边界七 + 修订记录 + 回归向量 V9 同步 | 7 项红线 PASS；与失能分支出口内容逐项等价（失能+组态坏路径行为无变化） |
| R2 | C:\Library\DL_Algo\FB_DL_BiquadFilter.st | **v1.0.1** | ①稳定判据换 **Jury 三条件** `ABS(a2)<1 ∧ (1+a1+a2)>0 ∧ (1−a1+a2)>0`（删 DL_BQ_A1LIM/DL_BQ_DLIM，新增 DL_BQ_ONE）；②码 3735 语义与头注释码表同步；③**V2b**（a1=−1.9, a2=−0.95 → 判 3735+冻结，旧伪判据放行族）与 **V2c**（a1=0, a2=−0.99 → 合法放行，旧判据误杀族）写入验收向量；④**373A 不再复用 bCfgBad**：段 5 / 段 9 的 bCfgBad 改由锁存码派生（3735/3736/3737 组态族才置位，373A 输入坏走 bValid+eErr 表达） | 7 项红线 PASS；373A 路径出口三件套完整 |
| R3 | C:\Library\DL_Device\FB_DL_IonFanInterlock.st | **v1.0.1** | ①按 R300「实现串 bEnable」口径：bAlarmFan/bAlarmSpeed/bAlarmBalance 与 bError 全部串 bEnable；码位回放段（段 5）失能相整链不发码（IF NOT bEnable THEN eErr:=0 ELSIF…）；②头注释边界八订正 + 修订记录；③**顺带消除 R62-D6（轻）**：组态域闸提为段 0 先行，判据与 tonConfirm 改用本拍组态位（段序代价小，派单允许一并消除，未扩单） | 7 项红线 PASS；R45 配对核验：bError 覆盖 0717/0718/0719/071A 四故障成因，与回放段口径一致 |
| R4 | C:\Library\DL_Base\FB_DL_RailPowerSequence.st | **v1.0.3**（磁盘原 1.0.2，与派单一致） | eRampUp 推进判据改「**沿 OR 电平**」双路：`rtFb.Q OR abRailFb[_nStep]`；头注释补「反馈预闭合」处置口径（边界三A）+ 验收向量 V6 + 修订记录；断电相完成判据本为电平式（NOT abRailFb），无同源挂死问题（头注释已注明） | 7 项红线 PASS |
| R5 | C:\Library\DL_MathData\FC_DL_PercentileRank.st | **v1.0.1** | `nNonFinite` 维持不外显（不改接口），头注释边界一 + 声明行二选一定稿为「不外显，诊断请用 FC_DL_SignalStatistics」+ 修订记录 | 7 项红线 PASS |

**R4 附带核验（R62-D7 转办）**：FB_DL_LineClearanceVerify nResidueMax 负值前置判据——按派单结论「已前置，免返修」，未动该文件。
**R3 顺带复核（R62-D6）**：段序调整代价小，已随 R3 一并消除（见上表），未扩单。

---

## 2 新件 13 件（4 批全部完成 13/13）

落盘路径均为 `C:\Library\<子库>\<名>.st`，头注释七项齐全 + 溯源三行 + 100% 中英双语同行注释。

### 批 1（3/3）

| # | 文件 | 版本 | 行数 | 码位（主段 · 具体） |
|---|---|---|---|---|
| 1 | DL_MathData\FC_DL_BcdToDint.st | 1.0.0 | 106 | 0001 · 0657（故障级：非法码元） |
| 2 | DL_MathData\FC_DL_DintToBcd.st | 1.0.0 | 120 | 0001 · 0658（故障级：负值 bOvF=F / 越域 bOvF=T，一码区分，R90 反证句已写） |
| 3 | DL_Algo\FB_DL_EwmaFilter.st | 1.0.0 | 155 | 0002 · 373B（故障：α 组态非法）/ 373C（故障：输入或结果非有限） |

### 批 2（4/4）

| # | 文件 | 版本 | 行数 | 码位 |
|---|---|---|---|---|
| 4 | DL_MathData\FC_DL_TrimmedMeanCalc.st | 1.0.0 | 186 | 0001 · 0659（故障：计数越域/剔净为空）/ 065A（故障：trim 成空集） |
| 5 | DL_MathData\FC_DL_PearsonCorrCalc.st | 1.0.0 | 203 | 0001 · 065B（故障：对数越域）/ 065C（故障：有效对 ≤2）/ 065D（故障：常量通道/下溢）/ 065E（信息：|r|>1 钳回） |
| 6 | DL_Algo\FC_DL_BiquadCoeff.st | 1.0.0 | 221 | 0002 · 373D（故障：域闸失败/枚举非法）/ 373E（故障：归一化分母近零/结果兜底）；枚举 E_DL_BiquadType 属主本文件 |
| 7 | DL_Algo\FB_DL_OutlierFilter.st | 1.0.0 | 348 | 0002 · 373F（故障：fNSigma/tHoldMax 组态非法）/ 3740（信息：窗长钳位）/ 3741（信息：真阶跃重基线）/ 3742（故障：保持超时测点坏） |

### 批 3（3/3）

| # | 文件 | 版本 | 行数 | 码位 |
|---|---|---|---|---|
| 8 | DL_Algo\FB_DL_BiquadCascade.st | 1.0.0 | 308 | 0002 · 3743（故障：nStages 越域/钳位域）/ 3744（故障：活动节越 Jury）/ 3745（故障：活动节系数非有限）/ 3748（故障：输入/中间/输出非有限）/ 3746（信息：输出钳位）/ 3747（信息：系数变更清零） |
| 9 | DL_Device\FB_DL_AdcNoiseFloorWatch.st | 1.0.0 | 253 | 0003 · 071D（故障：组态非法）/ 071E（故障：非有限超半窗）/ 071F（信息：底噪超限）/ 0720（信息：窗长钳位） |
| 10 | DL_Device\FB_DL_VfdOutputImbalance.st | 1.0.0 | 223 | 0003 · 0721（故障：测点非有限或组态非法）/ 0722（信息：不平衡超限）/ 0723（信息：断相）/ 0724（信息：上限 ≥100 判据永假） |

### 批 4（3/3）

| # | 文件 | 版本 | 行数 | 码位 |
|---|---|---|---|---|
| 11 | DL_Algo\FB_DL_AdaptiveLmsFilter.st | 1.0.0 | 231 | 0002 · 3749（故障：fMu 组态非法）/ 374A（信息：uTaps 钳位）/ 374B（信息：fWEnergy 发散提示）/ 374C（故障：输入非有限权重冻结） |
| 12 | DL_Device\FB_DL_VfdCapAgingEst.st | 1.0.0 | 173 | 0003 · 0725（故障：组态非法）/ 0726（信息：老化超限） |
| 13 | DL_Device\FB_DL_VfdPrechargeSeq.st | 1.0.0 | 281 | 0003 · 0728（故障：组态非法/ELSE 非法态拦截）/ 0729（故障：反馈超窗）/ 072A（故障：斜率持续不足）/ 072B（故障：总时限到）/ 072C（故障：电压测点非有限）；枚举 E_DL_PrechargePhase 属主本文件；bResetCmd 输入引脚为派单实现口径（§4 边界三）要求新增，派单引脚表未列，已在头注释写明 |

**码位分配依据（供主控实扫复核）**：全库 grep `16#000[1-5]_xxxx` 实测游标——段 0001 信息/故障带至 0656（PercentileRank 0656 为现最大），故新件从 0657 起连续派号；段 0002 至 373A（BiquadFilter v1.0.1），从 373B 起；段 0003 至 071C（IonFanInterlock 071C），从 071D 起。41 个新码位已逐一与全库 6 子库源码比对，唯一性断言 = 1（各码仅本件命中），零冲突。段 0004/0005 本轮无派号。

---

## 3 逐件 7 项红线自检汇总（13 新件）

| 红线 | 结论 |
|---|---|
| ① 零 GVL / VAR_EXTERNAL / %I/%Q | 全部 PASS（13/13 grep 零命中） |
| ② 命名合规（作用域前缀 + 类型前缀 + 大驼峰） | 全部 PASS；计数语义 n* 类型核查 PASS（FB51-7） |
| ③ 100% 同行中英双语注释（含枚举项） | 全部 PASS；全文件零「同上/同前/见上/ditto」 |
| ④ OOP 封装 | PASS；两枚举 TYPE 属主唯一（E_DL_BiquadType / E_DL_PrechargePhase 全库唯一定义断言 PASS） |
| ⑤ 周期安全 | PASS：PrechargeSeq 4×TON + rtReset 段 0 无条件刷新、错峰窗自复位（IN := NOT tonSlopeWin.Q，R188）；LMS rtWipe 段 0 刷新；BiquadFilter/Cascade rtReset 段 0 刷新；OutlierFilter tonHold 段 0 刷新（IN 串组态闸 + NOT 锁存量，FB50-1）；METHOD 无（本批无 METHOD） |
| ⑥ 防御编程 | PASS：除子全部结构早退或闸后证明（BcdToDint 域证明无溢出分支；DintToBcd 负值/越域显式拒绝；TrimmedMean/Pearson 除子先闸；Pearson SQRT 除子 ≥1E-12 闸；BiquadCoeff a0 ≥1 结构证明 + 兜底闸；VfdOutputImbalance 待机门限除子证明；VfdCapAgingEst/PrechargeSeq 组态闸 RETURN 先行）；NaN 自反 + 差值自减双判逐件点名；浮点禁 `=`/`<>` 判等（容差 1E-6/1E-9 口径）；故障级码 R45/R101 配对已逐行核（见 §4 自纠③） |
| ⑦ 可移植性 | PASS：仅 Standard.library（TON/R_TRIG/SIN/COS/SQRT/SHR/SHL/MOD/DIV 标准）；无 AS 方言、无 TRUNC、无指针 |
| FB50-4 落盘前三查 | ①禁词 0；②枚举单冒号 0；③字面零除子 1 处命中为头注释「2π / 0.45 / Q」误报，已改写为顿号列表（自纠②） |
| FB51-1 三族配对 | FOR↔END_FOR 逐件配平（9 件有循环，计数差全部来自头注释「Platform: FOR / …」字样，注释剥离后合法）；WHILE/REPEAT 0/0 |
| 闸参数全覆盖（FB51-2） | 每件浮点入参逐个点名（含换算量/限值）：Ewma 2/2、BiquadCoeff 3/3、Outlier 2/2+TIME、Cascade 8 系数×活动节+2 限值+输入、LMS 3/3、AdcNoise 3/3、Imbalance 6/6、CapAging 4/4、Precharge 4/4+2×TIME |
| 组态闸 RETURN 早退（族② 专项） | 族② 四件（#9/#10/#12/#13）全部「组态域闸 → 三件套 → RETURN」结构早退 PASS |
| 判据充分性（族① 专项） | #6/#8 采用 Jury 三条件（与返修 R2 固化口径一致，头注释一致性声明已写）；#11 域闸 (0,0.1] + 发散监视 PASS |

---

## 4 编码侧自纠列表（就地修复，3 处）

1. **自纠①（R261 自赋值死语句，2 处）**：FB_DL_AdcNoiseFloorWatch 段 2 组态早退分支初稿写了 `fNoiseStd := fNoiseStd;` 驻留占位行、FB_DL_OutlierFilter 失能分支写了 `nReject := nReject;` 保留行——均违反 FB51-6 自赋值禁令，已删行并将驻留语义改为注释表达（「最近有效值」改由 `_fStdUse`/保持量承载）。
2. **自纠②（FB50-4③ 正则误报主动改写）**：FC_DL_BiquadCoeff 头注释「2π / 0.45 / Q 域界」触发 `/ 0` 字面零除子正则（注释内误报），按落盘前三查纪律改写为「2π、0.45 与 Q 域界」。
3. **自纠③（R45/R101 配对性补强，6 处）**：FB_DL_BiquadCascade 段 2（2 处）与 FB_DL_VfdPrechargeSeq 段 6 CASE（4 处锁存码赋值）初稿在锁存码赋值行后未即时置 bError（bError 在统一出口段才派生）——静态扫查口径下判 R101 挂账风险，已在每处码赋值行后 1 行内补 `bError := TRUE;`（与统一出口派生一致，双写无害）。
4. **文字修正（非红线）**：FB_DL_VfdCapAgingEst 段 3 注释行尾残留 `+/` 已清。

**既有文件疑似缺陷记录（只记录不擅改）**：
- 无新增疑似缺陷；R4 附带核验项按派单结论销账，未动 FB_DL_LineClearanceVerify。

---

## 5 版本号口径说明（供主控对账）

派单书 §1 标注 R1/R2/R3/R5 目标版本为 v1.0.2 / v1.0.2 / v1.0.2 / v1.0.2（其"当前版本"栏写 v1.0.1），但 5 件返修件磁盘实存版本为 1.0.0（VfdDcBusRipple/BiquadFilter/IonFanInterlock/PercentileRank）与 1.0.2（RailPowerSequence）。按「版本号递增 MINOR 补丁位、禁跳号」铁律，本轮执行：磁盘 1.0.0 → **1.0.1**（R1/R2/R3/R5），磁盘 1.0.2 → **1.0.3**（R4）。若 registry 内登记版本确为 1.0.1（与磁盘不同步），主控收口时请按 registry 实测游标统一（必要时补一次递增至 1.0.2），本侧不擅自跳号。

---

## 6 交接提示（主控收口用）

- 注册/JSONL：13 新件待增补 INDEX_REGISTRY（批内未注册）；5 返修件待 JSONL 重注入（sha256 逐行复验）。
- 码位：41 个新码位清单见 §2 表格；分配与头注释/码表三处已一致，registry `code_segment` 待主控回填。
- 文档五件套 / ROADMAP / REVIEW_R63 模板：本轮未动（派单边界外）。
- 委托关系：TrimmedMean/Pearson→SortIndexLReal（双承接 R295）；OutlierFilter→SortIndexLReal 双次；BiquadCoeff→(无委托，属系数属主)；LMS/其余件零 DL_ 内部依赖。
- 新增 TYPE 2 个（E_DL_BiquadType 属主 FC_DL_BiquadCoeff.st；E_DL_PrechargePhase 属主 FB_DL_VfdPrechargeSeq.st），全库唯一属主断言 PASS。

*R63 阶段三编码侧自检 ｜ 2026-11-21 ｜ PLC 编程专家*
