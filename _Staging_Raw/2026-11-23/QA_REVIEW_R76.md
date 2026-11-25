# QA_REVIEW_R76（审校去重席 · 2026-11-23 · 批次 A 36 件全量三道比对 + 12 项扫查）

## 一、12 项扫查结论（36/36 全量，机检 grep + 逐件人工复核）

| 项 | 结论 | 证据 |
|---|---|---|
| R1 GVL/VAR_EXTERNAL | CLEAN | grep `VAR_EXTERNAL|VAR_GLOBAL|ADR(` 全 36 件零命中 |
| R2 %I/%Q/%M | CLEAN | grep `%[IQM]` 零命中 |
| R3 POINTER/REFERENCE/UNION | CLEAN | 唯一命中 FC_DL_EndianProbe.st:11-12 为头注释禁用说明，非使用 |
| R4 除零/越界/容差 | CLEAN | 除法点 3 处均有闸：WrapToRange.st:49 宽度≤0 先拒；SincSafe.st:43-48 Taylor 支路避开 0 分母；HypotChk.st:54-57 a=0 早退；移位量全部 ≤ 位宽-1（BitMaskRange.st:52 _nLo≤31 等） |
| R5 双语注释 | CLEAN | 36/36 变量行均「中文 / English」双注 |
| R6 CASE 带 ELSE | N/A 合规 | 无 CASE 语句；唯一 grep 命中 HystWindow3.st:16 为注释；各件头注均写明 R6 N/A 及兜底说明 |
| R7 TON/R_TRIG 周期刷新 | N/A 合规 | 36 件无定时器实例；HystTimeQualified 确认计时由调用方 TON 持有（头注 :9 明示），函数内无条件分支调用定时器问题不存在 |
| R10 构造函数式转换 | CLEAN | grep 构造式转换零命中；仅用 `DWORD#16#...` 类型字面量与 `_TO_` 标准转换 |
| R11 分号在注释前 | CLEAN | 逐件复核通过 |
| R13 语义查重 | 1 命中 | 见第三节，拒收 1 件 |
| R14 PROPERTY | CLEAN | 零命中 |
| R15 保留字撞名 | CLEAN | 无与 IEC 保留字不分大小写撞名 |

## 二、三道去重结论（对 INDEX_REGISTRY.json 1,288 条）

1. **名称**：36 规范化名比对零命中。
2. **签名指纹**：批内 6 组同签名组（如 LREAL<LREAL 族 6 件），经语义复核全部为不同数学函数（sin/cos/tan/asin/acos/sinc），指纹命中≠重复，放行。跨轮 staging 指纹库 hash 配方不可复算，以语义道为权威闸。
3. **语义同义**（逐对判定）：
   - BitReverse8/16 ↔ ReverseBitsLword：宽度变体，**有效**。⚠️ registry 含 FC_DL_ReverseBitsWord 但库内**无源文件**（死条目）——BitReverse16 实际补回了该缺失能力，列入存疑放行请总监清理条目
   - BitMaskRange ↔ BitFieldExtract/LwordBitFieldExtract：构造掩码 vs 抽取字段值，输出语义异，**有效**
   - AngleLerpShort ↔ WrapAngleNorm/WrapAngleDeg/LerpClamped：插值 vs 归一 vs 标量插值，**有效**
   - SinDeg/CosDeg/TanDegChk/AsinDegChk/AcosDegChk/Atan2Deg ↔ SinEx/CosEx/TanEx/AsinEx/AcosSafe/Atan2Ex：**度制 vs 弧度制单位变体，有效**（已实测邻居头注确认弧度口径）；Atan2Deg 输出域 [0,360) vs (-π,π] 亦异
   - HypotChk ↔ Hypot3D：维度变体，**有效**
   - ClampDintChk ↔ IndexClampEx（DL_MathData，实测签名 DINT×3→DINT）：核心限幅同形，新增 nDir 越界方向输出——**有效但列入存疑放行**（族内第三件须族化，参 R411）
   - HystWindow3/HystLatchAlarm/HystCounterStep/HystTimeQualified ↔ FC_DL_Hysteresis/FB_DL_HysteresisBandMon：Hysteresis 为单设定点+回差总宽 2 态比较器（实测签名 REAL/REAL/REAL→BOOL），四新件分别为三带/锁存复位/跨带计数/时间确认，功能级异，**逐件有效**
   - BytesToWord/DwordToWords/WordsToDword/LwordToDwords/DwordsToLword ↔ SwapBytes16/32/64：装配拆包 vs 字节交换，语义类不相交，**确认有效**
   - EndianProbe：**结论成立，不判 MAJOR**——IEC 数值语义层无内存重解释手段（R3 禁 POINTER/UNION），恒 FALSE 是诚实约定而非静默占位；但「Probe」名实不符、运行期零信息量，判 MINOR-4
   - **AngleDiffDeg ↔ FC_DL_AngleDiffWrap（R41 在库）：判重拒收**。同族（角度差归一）、同输入形态（2×LREAL 度制）、同输出语义（最短带符号弧差）；仅 ±180° 折返方向（Wrap 归 +180、Deg 归 −180）、1.0E12 量程闸、信息级码三处差异，均非新工程价值——同库两件折返口径相反反而是口径分裂隐患。1.0E12 闸建议并入 AngleDiffWrap 而非另立新件
   - WrapToRange ↔ WrapAngleDeg/Norm：任意周期区间 vs 固定 360°，泛化域新，**有效**

## 三、抽样深审（3 件逐行）

1. **FC_DL_HystWindow3**：门限校验 :54 与头注契约一致；三带滞回分支 :63-85 无「相内累计/跨相不清零」型缺陷，nPrevState 非法走 :77-85 电平重判兜底。**PASS**。
2. **FC_DL_AngleToCompass**：归一 :48-51、中心对齐 :53-54 实测 r=359.9→16 码 0（北）✓、8 码 MOD 折回 :56-57 无越界（LREAL_TO_DINT 输入 ≤16.5）。**PASS**。
3. **FC_DL_TanDegChk**：1e-12 判据 :46 对应 |tan|≈1e12 量级，渐近防护成立；非有限闸 :35 先行。**PASS**。
   - 深审另发现：WrapToRange 手工验算 fIn=250,fLo=100,fHi=200 → 150 ✓、fIn=200→100（左闭右开）✓；AngleDiffDeg 区间端点 ±180 折返自洽（该件因判重被拒，见上）。

## 四、缺陷清单

| 文件 | 行号 | 分级 | 问题 | 最小修法（交编码席） |
|---|---|---|---|---|
| DL_MathData/FC_DL_AngleDiffDeg.st | 全件 | **拒收（语义重复）** | 与 FC_DL_AngleDiffWrap（R41）同族同签名同输出语义，仅 ±180 折返口径相反 | 下架；1.0E12 量程闸与预留码位 1B01 并入 AngleDiffWrap 后续轮 |
| DL_MathData/FC_DL_AngleLerpShort.st | :6 | MINOR-1 | 头注写「fA−fB 最短弧差」，实现 :54 为 fB−fA（实现正确，注释反向） | 头注改为 fB−fA；另 :10 补 fB 量程说明（实现 :43 双查） |
| DL_Algo/FC_DL_HystLatchAlarm.st | :22 | MINOR-2 | fOff 注释「复位资格参考」，但实现仅在 :48 作参数校验，复位 :55 不检查 fIn<fOff | 注释改为「迟滞反向校验参考」，或实现补复位资格闸（二选一，注明口径） |
| DL_MathData/FC_DL_AngleQuadrant.st | :52-67 | MINOR-3 | bOnAxis 容差 1e-9 未贯穿象限判定：90°−ε（ε<1e-9）bOnAxis=TRUE 但象限给 0，与头注 :9「轴线取后一侧」不符 | 象限判定前先做轴线容差吸附，或头注写明容差仅作用于标志位 |
| DL_Base/FC_DL_EndianProbe.st | :22-33 | MINOR-4 | 恒 FALSE 常量件，名「Probe」实为约定锚，运行期零信息量（结论本身成立，不判 MAJOR） | 改名 FC_DL_EndianConvention 或并入库级文档；保留亦可但需总监点头 |

分级统计：**BLOCK 0 / MAJOR 0 / MINOR 4 / 拒收 1**。

## 五、最终名单

- **PASS（35 件）**：DL_Base 14 件（BitMaskRange/BitReverse8/BitReverse16/BitRunLength/BitLowestSet/BitSwapPairs/BitCountTransitions/BitFillLowestZero/BytesToWord/DwordToWords/WordsToDword/EndianProbe*/LwordToDwords/DwordsToLword，*附 MINOR-4）；DL_MathData 9 件（AngleLerpShort*/AngleQuadrant*/AngleBisector/AngleToCompass/AngleTolInside/AngleReflect/AngleUnwrapStep/SinDeg/CosDeg/TanDegChk/AsinDegChk/AcosDegChk/Atan2Deg/SincSafe/HypotChk 中除 AngleDiffDeg 外 15 件）；DL_Algo 6 件（HystWindow3/HystLatchAlarm*/HystCounterStep/HystTimeQualified/ClampDintChk*/WrapToRange，*附 MINOR）
- **拒收（1 件）**：FC_DL_AngleDiffDeg（重复于 FC_DL_AngleDiffWrap）
- **存疑放行（请总监复议）**：①BitReverse16 vs 死条目 FC_DL_ReverseBitsWord（registry 无源文件，建议清理或归属）；②ClampDintChk vs IndexClampEx（nDir 是否足以支撑第三件，R411 族化阈值）；③HystCounterStep 死区回中 nBand:=0（:70-71）使 fUpTh 附近抖动每次越限都重计数——与头注三带模型自洽，但建议头注显式写明「重臂」语义

## 批次 B（4 复杂件）审校

对象：FB_DL_BrakeReleaseInterlock / FB_DL_HeaterBankLoadBalance / FB_DL_AnalogDriftWatch / FB_DL_ChillerDoorPurgeSeq。抽检方式：4 件全检（复杂件全量过 R6/R7/R4 + 置码一致性，不做抽样）。

### 一、三道去重（全量 4 件，比对 registry 1,288 条）

| 新件 | 最近邻 | 判定 | 依据 |
|---|---|---|---|
| FB_DL_BrakeReleaseInterlock | FB_DL_AxisBrakeSeq（R22，351 行） | **有效差异** | AxisBrakeSeq 属主「上电/断电两条全序」（先放闸后使能 vs 先静止后上闸），无力矩判据；本件为「释放侧单序 + fTorque<tReleaseTh 持续确认 + eReady 态失使能即时回闸/反馈跌落 1D06」运行期监视，属主边界不同、新增力矩确认与就绪态回闸两条工程价值 |
| FB_DL_HeaterBankLoadBalance | FB_DL_HeaterBreakDetect（R48）· FB_DL_LoadShareDroop（R48） | **有效差异** | HeaterBreakDetect 是加热元件断路诊断（单件故障判别），无选主；LoadShareDroop 是多轴速度基准 droop 修正（连续量分配），无主/备概念；本件为「按累计工时选主 + 故障顺延 + 占空比 0/1 等值映射」，输入形态（工时数组+健康/投运布尔）与输出语义（通道号离散选主）均不同族 |
| FB_DL_AnalogDriftWatch | FB_DL_SensorDriftBaseline（R54） | **有效差异** | Baseline 为单通道 EMA 基线跟踪 + 快偏差报警（区分工况阶跃与慢漂移）；本件为双通道冗余「互偏差 |A−B| 遗忘累积 + 单边非有限失可信 + 逐通道信任标志」。同族（漂移）但输入形态（双通道 vs 单通道）与输出语义（信任裁决 vs 基线估计）不同，非同义变体 |
| FB_DL_ChillerDoorPurgeSeq | FB_DL_InertPurgeSeq（R35）· FB_DL_NightPurgeSeq（R57） | **有效差异** | InertPurgeSeq 为抽真空/充氮/保压三相循环 + 氧含量判据；NightPurgeSeq 为按日序时间窗的夜间免费制冷吹扫；本件为「检修门受限空间进入联锁：门关→风压建立确认→吹扫倒计时→开门允许放行」，放行对象（人）与安全语义（急停最高优先、门中途打开即锁存）均为新增边界 |

名称道与指纹道：4 件 FB 名与 4 个 ENUM 类型名（E_DL_BrakeRelState / E_DL_HeatBalState / E_DL_DriftState / E_DL_PurgeState）registry 全量零命中，无 E052/E004 重名风险。**拒收 0 件**。

### 二、逐件扫查（R6 状态机 / R7 定时器 / R4 防错 / 置码一致性）

| 文件 | 行号 | 分级 | 问题 | 判定式/证据 |
|---|---|---|---|---|
| FB_DL_BrakeReleaseInterlock.st | :24 vs :116/:121/:163/:176/:192/:194/:213 | **MAJOR-1** | 头注 :24 声明 16#0005_1D00「力矩确认超时——故障级，撤输出回退」，且 :32 码位总账称「1D00..1D07 全部定义并使用，无空悬码位」；正文通篇无 1D00 赋值，eTorqueQual 相亦无任何超时转出路径 | 全文 grep `1D00` 仅头注 :24/:32 两处；CASE eTorqueQual（:140-150）仅 使能丢失/eTorqueQual.Q 两路转出 → 力矩长期不达标时相驻留无界（头注承诺的时序保护未落地，与「无空悬码位」自检结论矛盾） |
| FB_DL_HeaterBankLoadBalance.st | :101-105 vs :44/:175 | **MAJOR-2** | 段 2 预置清单无 aDuty（仅 nMaster/bDerated/nErrCode/bError/bValid），eIdle 与 eFault 相体均不写 aDuty → 故障/待机相占空比残留上拍值；头注 :44 与 :175 注释「占空比全零/由预置全零」为虚假声明。上位若直接消费 aDuty，故障转出后主通道仍按旧占空比受电 | 段 2（:101-105）缺 `FOR _i:=1 TO 8 DO aDuty[_i]:=0`；eFault 相（:207-215）无 aDuty 写入；nMaster:=0 但 aDuty[旧主] 仍持值 |
| FB_DL_HeaterBankLoadBalance.st | :145-205 | MINOR-5 | eRun 相无 bBankEnable 撤令转出路径（eRun 仅两条转出：1E01→eFault、门禁→eFault），bBankEnable 置 FALSE 后整组继续选主并持续发布占空比；头注 :31 只声明进入方向未声明撤令方向，属口径未声明而非实现错误 | CASE eRun 体（:150-205）grep 无 `bBankEnable`；建议头注显式声明「撤令不清相，输出保持至故障/复位」或补 eRun→eIdle 转出 |
| FB_DL_AnalogDriftWatch.st | 全件 | PASS | R6：ENUM `:=` + CASE + ELSE（:188-195）齐；R4：α 除法仅在 _bParOk 闸后（:117-119，分母 fTauSec+fDtSec > fDtSec > 0）；双通道非有限冻结估计不污染累计量（:146-160）；条件级 2002/2003 与预警级 2004 置码口径与头注一致；复位链可达（:182-186） | 12 项扫查零命中 |
| FB_DL_ChillerDoorPurgeSeq.st | 全件 | PASS | R6：CASE + ELSE（:207-214）齐、五态全可达、急停最高优先前置段 3（:112-117）；R7：三 TON + 两 R_TRIG 段 1 无条件刷新（:90-93）；bDone 两段式单拍脉冲无同拍抹除（:97-98/:184）；tPressTo>tPressQual 闸（:121）使 ePressQual 双定时器无同拍双 Q 竞态；置码一致性全对（无信息级码，故障级三行齐） | 12 项扫查零命中 |

其余通检项（4 件共用结论）：无除法/取模分母裸奔；数组下标全部硬界内（HeaterBank 的 1.._nEff 钳位 :114-120 + :165 下标守卫；其余件无数组）；非有限判定一律 NaN `f<>f` + ±Inf `(f-f)<>(f-f)` 双判且入闸；TON/R_TRIG 全部本体段 1 无条件刷新；无 PROPERTY / 无构造函数式转换；声明分号均在注释前；故障码锁存-回放结构（段 2 回放 + eFault 覆盖保护）三件一致正确。

### 三、分级统计与处置

**PASS 2 / 缺陷 2（MAJOR 2 / MINOR 1 / BLOCK 0）/ 拒收 0。**

- MAJOR-1（BrakeReleaseInterlock 1D00 未实现 + 力矩确认相无超时转出）：行为变更类，**挂账下轮**，非就地修（需补一只 TON + 转出支路 + 码位）。
- MAJOR-2（HeaterBankLoadBalance aDuty 故障/待机残留）：安全侧（加热器故障后持续受电）但修法为加清零循环、行为有变，**挂账下轮**优先处置，不建议就地修。
- MINOR-5：口径声明类，下轮与 MAJOR-2 同件一并处理。
- 无同族系统性缺陷（两件 MAJOR 分属不同缺陷型：一为「头注承诺未落地」，一为「预置清单漏项」），不触发扩面复审。

### 四、存疑放行（请总监复议）

无。两件 MAJOR 证据链完整（均有行号对照），两件 PASS 为全检通过非抽样放宽。

